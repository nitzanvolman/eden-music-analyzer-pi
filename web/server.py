#!/usr/bin/env python3
"""SC-OSC Web Server — lightweight web interface for the audio analyzer.

Designed for Raspberry Pi in art car conditions (unreliable WiFi).
Uses aiohttp for async HTTP + WebSocket support.
"""

import os
import time
import asyncio
import shutil
from pathlib import Path
from aiohttp import web

# Default port, overridable via env var
WEB_PORT = int(os.environ.get("SC_WEB_PORT", "8080"))

# Path to static files (served from web/static/)
STATIC_DIR = Path(__file__).parent / "static"

# Server start time (for uptime calculation)
_start_time = time.monotonic()


async def index(request: web.Request) -> web.Response:
    """Serve the main page."""
    index_path = STATIC_DIR / "index.html"
    if index_path.exists():
        return web.FileResponse(index_path)
    return web.Response(text="SC-OSC Web Interface", content_type="text/html")


async def api_ping(request: web.Request) -> web.Response:
    """Simple health check endpoint."""
    return web.json_response({"status": "ok"})


def _read_cpu_temp() -> float | None:
    """Read CPU temperature on Raspberry Pi. Returns None if unavailable."""
    try:
        temp_path = Path("/sys/class/thermal/thermal_zone0/temp")
        if temp_path.exists():
            return int(temp_path.read_text().strip()) / 1000.0
    except (ValueError, OSError):
        pass
    return None


def _get_load_avg() -> list[float]:
    """Get system load averages (1, 5, 15 min)."""
    try:
        return list(os.getloadavg())
    except OSError:
        return []


async def api_health(request: web.Request) -> web.Response:
    """Health monitoring endpoint with uptime, resource usage, and status."""
    uptime_sec = time.monotonic() - _start_time

    # Memory info from /proc/meminfo (Linux)
    mem = {}
    try:
        meminfo = Path("/proc/meminfo")
        if meminfo.exists():
            lines = meminfo.read_text().splitlines()
            for line in lines:
                if line.startswith(("MemTotal:", "MemAvailable:", "MemFree:")):
                    parts = line.split()
                    mem[parts[0].rstrip(":")] = int(parts[1]) * 1024  # kB to bytes
    except (ValueError, OSError):
        pass

    # Disk usage for the home partition
    disk = {}
    try:
        usage = shutil.disk_usage(os.path.expanduser("~"))
        disk = {"total": usage.total, "used": usage.used, "free": usage.free}
    except OSError:
        pass

    data = {
        "status": "ok",
        "uptime_seconds": round(uptime_sec, 1),
        "load_avg": _get_load_avg(),
        "memory": mem,
        "disk": disk,
    }

    cpu_temp = _read_cpu_temp()
    if cpu_temp is not None:
        data["cpu_temp_c"] = round(cpu_temp, 1)

    return web.json_response(data)


def create_app() -> web.Application:
    """Create and configure the aiohttp application."""
    app = web.Application()

    # API routes
    app.router.add_get("/", index)
    app.router.add_get("/api/ping", api_ping)
    app.router.add_get("/api/health", api_health)

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
