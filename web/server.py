#!/usr/bin/env python3
"""SC-OSC Web Server — lightweight web interface for the audio analyzer.

Designed for Raspberry Pi in art car conditions (unreliable WiFi).
Uses aiohttp for async HTTP + WebSocket support.
"""

import os
import asyncio
from pathlib import Path
from aiohttp import web

# Default port, overridable via env var
WEB_PORT = int(os.environ.get("SC_WEB_PORT", "8080"))

# Path to static files (served from web/static/)
STATIC_DIR = Path(__file__).parent / "static"


async def index(request: web.Request) -> web.Response:
    """Serve the main page."""
    index_path = STATIC_DIR / "index.html"
    if index_path.exists():
        return web.FileResponse(index_path)
    return web.Response(text="SC-OSC Web Interface", content_type="text/html")


async def api_ping(request: web.Request) -> web.Response:
    """Simple health check endpoint."""
    return web.json_response({"status": "ok"})


def create_app() -> web.Application:
    """Create and configure the aiohttp application."""
    app = web.Application()

    # API routes
    app.router.add_get("/", index)
    app.router.add_get("/api/ping", api_ping)

    # Static file serving (if directory exists)
    if STATIC_DIR.exists():
        app.router.add_static("/static/", STATIC_DIR, name="static")

    return app


def main() -> None:
    """Entry point for the web server."""
    app = create_app()
    print(f"SC-OSC Web Server starting on port {WEB_PORT}")
    web.run_app(app, host="0.0.0.0", port=WEB_PORT, print=None)


if __name__ == "__main__":
    main()
