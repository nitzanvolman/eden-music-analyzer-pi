#!/usr/bin/env python3
"""OSC test receiver — prints all incoming messages with timestamps and color coding."""

import argparse
import sys
import time
from datetime import datetime

from pythonosc.dispatcher import Dispatcher
from pythonosc.osc_server import BlockingOSCUDPServer

# ANSI color codes
COLORS = {
    "/audio/amplitude":         "\033[32m",   # green
    "/audio/pitch":             "\033[36m",   # cyan
    "/audio/onset":             "\033[91m",   # bright red
    "/audio/loudness":          "\033[33m",   # yellow
    "/audio/spectral/centroid": "\033[35m",   # magenta
    "/audio/spectral/flatness": "\033[34m",   # blue
    "/audio/mfcc":              "\033[90m",   # gray
    "/audio/key":               "\033[93m",   # bright yellow
    "/audio/beat":              "\033[95m",   # bright magenta
    "/audio/bpm":               "\033[94m",   # bright blue
    "/audio/chroma":            "\033[37m",   # white
}
RESET = "\033[0m"

KEY_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


def supports_color():
    """Check if the terminal supports ANSI color."""
    return hasattr(sys.stdout, "isatty") and sys.stdout.isatty()


def make_handler(use_color):
    """Return a generic OSC handler that prints messages."""
    def handler(address, *args):
        ts = datetime.now().strftime("%H:%M:%S.%f")[:-3]
        color = ""
        reset = ""
        extra = ""

        if use_color:
            color = COLORS.get(address, "")
            reset = RESET if color else ""

        # Human-readable extras for certain addresses
        if address == "/audio/key" and len(args) >= 2:
            key_idx = int(args[0]) % 12
            mode = "major" if int(args[1]) == 1 else "minor"
            extra = f"  ({KEY_NAMES[key_idx]} {mode})"
        elif address == "/audio/pitch" and len(args) >= 2:
            if args[1] > 0.5:
                extra = f"  ({args[0]:.1f} Hz)"
            else:
                extra = "  (no pitch)"
        elif address == "/audio/bpm" and len(args) >= 1:
            extra = f"  ({args[0]:.1f} BPM)"

        args_str = ", ".join(f"{a:.4f}" if isinstance(a, float) else str(a) for a in args)
        print(f"{color}[{ts}] {address:30s}  {args_str}{extra}{reset}")

    return handler


def main():
    parser = argparse.ArgumentParser(description="OSC test receiver for SC-OSC analyzer")
    parser.add_argument("--ip", default="0.0.0.0", help="IP to listen on (default: 0.0.0.0)")
    parser.add_argument("--port", type=int, default=9000, help="Port to listen on (default: 9000)")
    parser.add_argument("--no-color", action="store_true", help="Disable color output")
    args = parser.parse_args()

    use_color = supports_color() and not args.no_color

    dispatcher = Dispatcher()
    handler = make_handler(use_color)
    dispatcher.set_default_handler(handler)

    server = BlockingOSCUDPServer((args.ip, args.port), dispatcher)
    print(f"SC-OSC Test Receiver listening on {args.ip}:{args.port}")
    print("Waiting for messages... (Ctrl+C to stop)")
    print()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()
