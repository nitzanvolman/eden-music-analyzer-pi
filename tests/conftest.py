"""Shared pytest fixtures for SC-OSC web server tests."""

import pytest
from pathlib import Path
from unittest.mock import AsyncMock, patch

from web.server import create_app
import web.server as server_module


@pytest.fixture
def tmp_sc_osc_dir(tmp_path):
    """Create a temporary SC_OSC_DIR with config files."""
    config_template = tmp_path / "config_template.env"
    config_template.write_text(
        "# Template\n"
        "SC_OSC_DESTINATIONS=127.0.0.1:9000\n"
        "# SC_ONSET_THRESHOLD=0.5\n"
        "# SC_FFT_SIZE=2048\n"
    )

    config_file = tmp_path / "config.env"
    config_file.write_text(
        "SC_OSC_DESTINATIONS=127.0.0.1:9000\n"
        "SC_ONSET_THRESHOLD=0.3\n"
    )

    logs_dir = tmp_path / "logs"
    logs_dir.mkdir()

    return tmp_path


@pytest.fixture
def patched_server(tmp_sc_osc_dir, monkeypatch):
    """Patch server module paths to use tmp directory."""
    monkeypatch.setattr(server_module, "SC_OSC_DIR", tmp_sc_osc_dir)
    monkeypatch.setattr(server_module, "CONFIG_FILE", tmp_sc_osc_dir / "config.env")
    monkeypatch.setattr(server_module, "CONFIG_TEMPLATE", tmp_sc_osc_dir / "config_template.env")


@pytest.fixture
def mock_osc_server():
    """Mock the OSC server startup so tests don't bind UDP ports."""
    with patch("web.server.start_osc_server", new_callable=AsyncMock) as mock:
        mock.return_value = AsyncMock()  # mock transport
        yield mock


@pytest.fixture
async def client(aiohttp_client, patched_server, mock_osc_server):
    """Create an aiohttp test client with patched config paths."""
    app = create_app()
    return await aiohttp_client(app)
