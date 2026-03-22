# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Real-time audio analyzer for the Eden Art Car. A SuperCollider (`analyzer.scd`) process runs on a Raspberry Pi, extracts musical features from live audio, and emits OSC messages. A Python/aiohttp web server (`web/`) receives those OSC messages and serves a browser dashboard with live WebSocket streaming.

## Commands

```bash
# Development — runs both analyzer (sclang) and web server; Ctrl+C stops both
./dev.sh

# Web server only (no audio hardware needed)
source .venv/bin/activate
python -m web.server

# Run tests
.venv/bin/pytest tests/

# Install Python deps
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
```

## Architecture

### Two-process design
1. **SuperCollider analyzer** (`analyzer.scd`) — runs on scsynth's audio thread, extracts features via UGens, forwards OSC messages to configured destinations via sclang OSCdefs. All config comes from environment variables (sourced from `config.env`).
2. **Python web server** (`web/server.py` + `web/osc_bridge.py`) — aiohttp app that listens for OSC on UDP (default port 9000), stores latest values, and broadcasts to browser clients over WebSocket at `/ws/osc`. Also exposes REST APIs for health, config CRUD, logs, and analyzer restart.

### Data flow
```
Mic → scsynth (SynthDef) → [Input Conditioning] → SendReply → sclang OSCdefs → UDP OSC → osc_bridge.py → WebSocket → browser
```

### Configuration
All runtime config is in `config.env` (env vars prefixed `SC_`). `config_template.env` documents all options with defaults. Config is read once at startup — changes require restart.

Key config areas: OSC destinations, feature toggles (`SC_FEATURE_*=0/1`), trigger rates, detection thresholds, FFT size, onset suite per-channel toggles and thresholds (`SC_ONSET_*`), input conditioning (gain, HPF, noise gate, compressor), scene/energy/vocal detection parameters.

### Onset detection suite
The analyzer runs 10 parallel onset detectors, each with its own algorithm, frequency band filter, and threshold. Frequency-filtered channels (kick, snare, hihat, bass, melody, bright) have their own FFT chain. Full-spectrum channels (perc, any, drop, soft) share the main FFT via PV_Copy. OSC paths: `/audio/onset/{channel}`. Config: `SC_FEATURE_ONSET_SUITE` master toggle, `SC_ONSET_{NAME}` per-channel toggle, `SC_ONSET_{NAME}_THRESHOLD` per-channel threshold.

### Web server structure
- `web/server.py` — `create_app()` factory pattern, route handlers, config file I/O
- `web/osc_bridge.py` — async OSC UDP listener, WebSocket client registry, latest-value cache, analyzer heartbeat status
- `web/static/` — HTML pages (index, config, viz, help, logs)
- Tests use `pytest-aiohttp` with fixtures in `tests/conftest.py` that mock OSC server and use temp directories for config files

### Test mode
Set `SC_TEST_MODE=1` to run `analyzer.scd` without audio hardware — sends synthetic OSC data from sclang for testing receivers and the web UI.
