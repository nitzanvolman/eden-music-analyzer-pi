"""OSC-to-WebSocket bridge.

Listens for OSC messages from the analyzer (on localhost) and broadcasts
them to all connected WebSocket clients as JSON.
"""

import os
import json
import asyncio
import time
from pythonosc.osc_server import AsyncIOOSCUDPServer
from pythonosc.dispatcher import Dispatcher

# Port to listen for OSC messages from the analyzer
OSC_LISTEN_PORT = int(os.environ.get("SC_OSC_BRIDGE_PORT", "9000"))

# Connected WebSocket clients
_ws_clients: set = set()

# Latest values for each OSC address (for new clients to get current state)
_latest: dict[str, dict] = {}


async def _safe_send(ws, data: str) -> None:
    """Send to a WebSocket client, silently ignoring errors."""
    try:
        await ws.send_str(data)
    except Exception:
        pass


def _handle_osc(address: str, *args) -> None:
    """Handle incoming OSC message — store latest and queue broadcast."""
    data = {
        "address": address,
        "args": [float(a) if isinstance(a, (int, float)) else a for a in args],
        "t": round(time.time(), 3),
    }
    _latest[address] = data

    # Schedule broadcast to all WebSocket clients
    msg = json.dumps(data)
    for ws in _ws_clients:
        asyncio.ensure_future(_safe_send(ws, msg))


def get_latest() -> dict[str, dict]:
    """Return the latest values for all OSC addresses."""
    return dict(_latest)


def get_analyzer_status() -> dict:
    """Return analyzer status based on heartbeat recency."""
    hb = _latest.get("/audio/heartbeat")
    if hb is None:
        return {"status": "unknown", "detail": "No heartbeat received"}
    age = round(time.time() - hb["t"], 1)
    if age < 10:
        return {"status": "alive", "last_heartbeat_age": age}
    return {"status": "dead", "last_heartbeat_age": age, "detail": "Heartbeat stale"}


def create_dispatcher() -> Dispatcher:
    """Create an OSC dispatcher that routes all /audio/* messages."""
    disp = Dispatcher()
    disp.map("/audio/*", _handle_osc)
    # Nested paths (e.g. /audio/onset/kick, /audio/spectral/centroid)
    # need their own pattern — OSC * only matches one path level.
    disp.map("/audio/*/*", _handle_osc)
    return disp


async def start_osc_server(loop: asyncio.AbstractEventLoop) -> None:
    """Start the async OSC UDP server."""
    disp = create_dispatcher()
    server = AsyncIOOSCUDPServer(
        ("0.0.0.0", OSC_LISTEN_PORT), disp, loop,
    )
    transport, _ = await server.create_serve_endpoint()
    print(f"OSC bridge listening on port {OSC_LISTEN_PORT}")
    return transport


def register_ws(ws) -> None:
    """Register a WebSocket client."""
    _ws_clients.add(ws)


def unregister_ws(ws) -> None:
    """Unregister a WebSocket client."""
    _ws_clients.discard(ws)
