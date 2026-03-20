#!/usr/bin/env bash
# dev.sh — Run analyzer + web server locally for development.
# Both run in the foreground; Ctrl+C stops everything.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SCLANG="/Applications/SuperCollider.app/Contents/MacOS/sclang"
VENV_DIR="$SCRIPT_DIR/.venv"

if [[ ! -x "$SCLANG" ]]; then
	echo "ERROR: sclang not found at $SCLANG"
	exit 1
fi

if [[ ! -d "$VENV_DIR" ]]; then
	echo "ERROR: .venv not found. Run: python3 -m venv .venv && .venv/bin/pip install -r requirements.txt"
	exit 1
fi

source config.env

cleanup() {
	echo ""
	echo "Stopping..."
	kill $WEB_PID $SC_PID 2>/dev/null || true
	wait $WEB_PID $SC_PID 2>/dev/null || true
	echo "Done."
}
trap cleanup EXIT INT TERM

# Start web server
"$VENV_DIR/bin/python" -m web.server &
WEB_PID=$!

# Start analyzer
"$SCLANG" analyzer.scd &
SC_PID=$!

echo "=== Dev mode ==="
echo "  Web server: http://localhost:${SC_WEB_PORT:-8080}"
echo "  Analyzer:   PID $SC_PID"
echo "  Ctrl+C to stop both"
echo ""

wait
