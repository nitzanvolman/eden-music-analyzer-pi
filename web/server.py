#!/usr/bin/env python3
"""SC-OSC Web Server — lightweight web interface for the audio analyzer.

Designed for Raspberry Pi in art car conditions (unreliable WiFi).
Uses aiohttp for async HTTP + WebSocket support.
"""

import os
import time
import json
import asyncio
import shutil
import subprocess
from pathlib import Path
from aiohttp import web

from web.osc_bridge import start_osc_server, register_ws, unregister_ws, get_latest

# Default port, overridable via env var
WEB_PORT = int(os.environ.get("SC_WEB_PORT", "8080"))

# Path to config files
SC_OSC_DIR = Path(os.environ.get("SC_OSC_DIR", os.path.expanduser("~/sc-osc")))
CONFIG_FILE = SC_OSC_DIR / "config.env"
CONFIG_TEMPLATE = SC_OSC_DIR / "config_template.env"

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


async def api_restart(request: web.Request) -> web.Response:
    """Restart the SC-OSC analyzer service.

    Tries systemd first (sudo systemctl restart sc-osc), then falls back
    to looking for a running sclang process and sending it SIGHUP/restarting.
    """
    try:
        # Check if systemd service exists
        check = await asyncio.create_subprocess_exec(
            "systemctl", "is-active", "sc-osc",
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        stdout, _ = await check.communicate()
        service_active = check.returncode == 0

        if service_active or stdout.decode().strip() in ("inactive", "failed", "activating"):
            # Systemd service exists — restart it
            proc = await asyncio.create_subprocess_exec(
                "sudo", "systemctl", "restart", "sc-osc",
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            )
            _, stderr = await proc.communicate()
            if proc.returncode == 0:
                return web.json_response({"status": "restarting", "method": "systemd"})
            return web.json_response(
                {"status": "error", "message": stderr.decode().strip()},
                status=500,
            )

        # No systemd service — try to find and restart sclang directly
        proc = await asyncio.create_subprocess_exec(
            "pkill", "-f", "sclang.*analyzer.scd",
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        await proc.communicate()
        # pkill returns 0 if matched, 1 if no match — both are OK
        return web.json_response({
            "status": "restarting",
            "method": "pkill",
            "note": "Process killed. If using autostart/crontab, it will restart automatically.",
        })

    except Exception as e:
        return web.json_response(
            {"status": "error", "message": str(e)},
            status=500,
        )


def _parse_env_file(path: Path) -> dict[str, str]:
    """Parse a KEY=VALUE env file, ignoring comments and blank lines."""
    result = {}
    if not path.exists():
        return result
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" in line:
            key, _, value = line.partition("=")
            result[key.strip()] = value.strip()
    return result


def _write_env_file(path: Path, values: dict[str, str]) -> None:
    """Write config values to an env file, preserving comments and structure.

    Strategy: read the existing file (or template), update matching keys,
    append new keys at the end.
    """
    source = path if path.exists() else CONFIG_TEMPLATE
    lines: list[str] = []
    written_keys: set[str] = set()

    if source.exists():
        for line in source.read_text().splitlines():
            stripped = line.strip()
            # Check if this line is a commented-out or active key
            check = stripped.lstrip("# ")
            if "=" in check:
                key = check.partition("=")[0].strip()
                if key in values:
                    # Replace with the new value (uncommented)
                    lines.append(f"{key}={values[key]}")
                    written_keys.add(key)
                else:
                    lines.append(line)
            else:
                lines.append(line)

    # Append any keys not found in the file
    for key, value in values.items():
        if key not in written_keys:
            lines.append(f"{key}={value}")

    path.write_text("\n".join(lines) + "\n")


async def api_config_get(request: web.Request) -> web.Response:
    """GET /api/config — return all current config values."""
    config = _parse_env_file(CONFIG_FILE)
    # Also include defaults from template for reference
    template = _parse_env_file(CONFIG_TEMPLATE)
    return web.json_response({
        "config": config,
        "defaults": template,
    })


async def api_config_set(request: web.Request) -> web.Response:
    """POST /api/config — update config values.

    Expects JSON body: {"key": "value", ...}
    Only accepts keys starting with SC_ to prevent arbitrary env pollution.
    """
    try:
        body = await request.json()
    except Exception:
        return web.json_response(
            {"status": "error", "message": "Invalid JSON body"},
            status=400,
        )

    if not isinstance(body, dict):
        return web.json_response(
            {"status": "error", "message": "Expected JSON object"},
            status=400,
        )

    # Validate keys
    invalid_keys = [k for k in body if not k.startswith("SC_")]
    if invalid_keys:
        return web.json_response(
            {"status": "error", "message": f"Invalid keys (must start with SC_): {invalid_keys}"},
            status=400,
        )

    # Validate values (no newlines — would corrupt env file)
    for k, v in body.items():
        sv = str(v)
        if "\n" in sv or "\r" in sv:
            return web.json_response(
                {"status": "error", "message": f"Value for {k} contains invalid characters"},
                status=400,
            )

    # Read current config, merge updates
    current = _parse_env_file(CONFIG_FILE)
    current.update({k: str(v) for k, v in body.items()})
    _write_env_file(CONFIG_FILE, current)

    return web.json_response({
        "status": "ok",
        "updated": list(body.keys()),
        "note": "Restart the analyzer for changes to take effect.",
    })


async def api_osc_latest(request: web.Request) -> web.Response:
    """GET /api/osc/latest — return latest value for every OSC address."""
    return web.json_response(get_latest())


async def ws_osc(request: web.Request) -> web.WebSocketResponse:
    """WebSocket /ws/osc — stream live OSC data to the client."""
    ws = web.WebSocketResponse()
    await ws.prepare(request)

    register_ws(ws)
    try:
        # Send current state snapshot on connect
        for data in get_latest().values():
            await ws.send_str(json.dumps(data))
        # Keep connection alive until client disconnects
        async for msg in ws:
            pass  # We don't expect messages from the client
    finally:
        unregister_ws(ws)

    return ws


async def on_startup(app: web.Application) -> None:
    """Start the OSC listener when the web server starts."""
    loop = asyncio.get_event_loop()
    app["osc_transport"] = await start_osc_server(loop)


async def on_cleanup(app: web.Application) -> None:
    """Clean up the OSC listener on shutdown."""
    transport = app.get("osc_transport")
    if transport:
        transport.close()


def create_app() -> web.Application:
    """Create and configure the aiohttp application."""
    app = web.Application()

    # API routes
    app.router.add_get("/", index)
    app.router.add_get("/api/ping", api_ping)
    app.router.add_get("/api/health", api_health)
    app.router.add_post("/api/restart", api_restart)
    app.router.add_get("/api/config", api_config_get)
    app.router.add_post("/api/config", api_config_set)
    app.router.add_get("/api/osc/latest", api_osc_latest)
    app.router.add_get("/ws/osc", ws_osc)

    # Static file serving (if directory exists)
    if STATIC_DIR.exists():
        app.router.add_static("/static/", STATIC_DIR, name="static")

    # Lifecycle hooks
    app.on_startup.append(on_startup)
    app.on_cleanup.append(on_cleanup)

    return app


def main() -> None:
    """Entry point for the web server."""
    app = create_app()
    print(f"SC-OSC Web Server starting on port {WEB_PORT}")
    web.run_app(app, host="0.0.0.0", port=WEB_PORT, print=None)


if __name__ == "__main__":
    main()
