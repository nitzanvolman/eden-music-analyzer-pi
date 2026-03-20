# Eden Music Analyzer Roadmap

## Context

This is the audio analysis system for Eden, a Burning Man art car. It listens to music, extracts features (beat, pitch, loudness, etc.), and sends OSC messages to drive the light show on playa.

That said — this is a hobby project, not life-or-death infrastructure. Favor pragmatic solutions, converge quickly, and don't over-engineer. Good enough and working beats perfect and unfinished.

## Operating Procedure

- You will be invoked repeatadly and given this prompt, you will either execute or review one work item on each iteration, log your work and commit to git.
- Follow this procedure precicely.

### Statuses

- ⚪ - pending, ready for work
- 🟠 - in progress
- 🔵 - ready for review
- 🟢 - done

### Workflow

⚪ -> 🟠 -> 🔵 -> 🟢

### Steps

#### 1. Select the next task

1) Select the first 🔵 if exists.
2) Else, Select the first 🟠 if exists.
3) Else, Select the first ⚪ if exists
4) Else, no more tasks

#### 2. Update your context

1) Look at the latest git commits relevant to this task and see what was changed.
2) Look at any pending changes that were not yet commited.
3) Look at the relevant worklog entries to see what was done.
4) Read relevant API documentation for technologies used in the task (e.g. SuperCollider, Python libraries) to ensure correct usage.

**note**: if the selected task status is ⚪, the context would likely be empty

#### 3. Work

- If 🔵:
  1. Code / Documentation analysis in a sub agent with a fresh context window.
  2. If applicable simulate / test the feature.
  3. Update the task status. Failed -> 🟠 , Passed -> 🟢
- If 🟠 or ⚪:
  1. Execute the task
  2. Update the task status -> 🔵

#### 4. Report

1) append an entry to worklog.md summarizing your work, so the next session would know the progress.
  Format:
  - If 🟠 or ⚪:
    `- [Task #{taskid}] {what was done}`
  - If 🔵:  
    `- [Task #{taskid}] ✅`
    or
    `- [Task #{taskid}] ❌ - {issues description}`
2) commit.

#### 5. Done

This iteration is done. the next task will be done by the next iteration. 


## Tasks

1. [🟢] - Create the roadmap.
2. [🟢] - Create the initial implementation.
3. [🟢] - Split the @README.md into 3 files INSTALL.md, TROUBLESHOOTING.md, the main README should refer to these new files, but focus on how to run (when already
installed), how to tune, and Output Reference (what the reciever of the OSC messages needs)
4. [🟢] - Create config_template.env with all *new* tweakable parameters from analyzer.scd (onset threshold and OSC dest IP/port are already externalized): audio input channel, FFT buffer size, amplitude attack/release times, pitch min/max frequency, onset detection algorithm, MFCC coefficient count, key decay time, beat tracker lock mode, and trigger rates for fast/medium/slow features.
5. [🟢] - Configuration supports sending OSC to multiple destination IPs. (Do this before or alongside Task 6 to avoid rework.)
6. [🟢] - Update analyzer.scd to read all config values from environment variables (with current hardcoded values as defaults).
7. [🟢] - Add config.env to .gitignore; update install script to copy config_template.env → config.env if not present.
8. [🟢] - Add OSC test mode as a mode within analyzer.scd: when enabled, bypass audio input and send synthetic OSC messages on all channels (for testing receivers without audio).
9. [🟢] - Install script creates a Python (3.12+) virtual environment.
10. [🟢] - Configuration allows toggling individual analysis features on/off to conserve CPU (gate SendReply triggers per feature).
11. [🟢] - Configuration can toggle OSC test mode on/off.
12. [🟢] - Web interface: Python web server setup. Design assuming WiFi drops frequently (art car conditions).
    - 12a. [🟢] - Set up a simple Python web server (default port 8080) with basic routing.
    - 12b. [🟢] - Server health monitoring endpoint (uptime, status, resource usage).
    - 12c. [🟢] - Service restart endpoint (restart the analyzer process).
    - 12d. [🟢] - Configuration read/write API (expose all config values, apply changes, force reload).
    - 12e. [🟢] - Live OSC data websocket/SSE stream for real-time frontend consumption.
13. [🟢] - Web interface: configuration control page — view and edit all configuration values, force configuration update.
14. [🟢] - Web interface: live OSC visualization — animated graphical visualization driven by real-time analysis data. Goal: testing, tweaking, and demo to the Eden crew.
15. [🟢] - Web interface: two visualization screens — (1) public readonly view (wow factor) (2) expert/tweaking mode with configuration controls. Goal: help with integration and tuning the receivers (and ultimately the light show).
16. [🟢] - Web interface: add analysis details as in-app help — descriptions of each analysis feature (detail level matching analyzer.scd comments).
17. [🟢] - Enhance README with detailed descriptions of each analysis type (matching the level of detail in analyzer.scd comments).
18. [🟢] - Add install-on-Mac option (for testing on this machine).
19. [🟢] - Add install-on-PC/Windows option (best effort, validate by web information only, must not interfere with Pi or Mac install modes).
20. [🟢] - Logging with rotation — persistent logs with size caps (don't fill the SD card). Must capture sclang stdout/stderr.
21. [🟢] - Web interface: log viewer screen — view logs in real-time from the web UI.
22. [🟢] - CPU temperature monitoring + throttle alerts — expose Pi temp via web UI, warn when overheating.

## Unit Tests

Each task: write tests first (they should fail), then make them pass. Use pytest + aiohttp test client. Add pytest + pytest-aiohttp to requirements.txt in Task 23.

23. [🟠] - Test setup: add pytest + pytest-aiohttp to requirements.txt, create tests/ directory with conftest.py (aiohttp test client fixture, temp config files, mock SC_OSC_DIR).
24. [⚪] - Test: GET /api/ping returns {"status": "ok"} with 200.
25. [⚪] - Test: GET /api/health returns uptime_seconds (> 0), status "ok", load_avg (list), memory (dict), disk (dict). Verify cpu_temp_c is a float or absent. Verify temp_alert is "warning"/"critical"/absent based on thresholds.
26. [⚪] - Test: GET /api/config returns config and defaults dicts. POST /api/config with valid SC_ keys writes to config.env and returns updated keys. POST with non-SC_ keys returns 400. POST with newline in value returns 400. POST with invalid JSON returns 400.
27. [⚪] - Test: config file parsing (_parse_env_file): handles comments, blank lines, KEY=VALUE, values containing "=". Writing (_write_env_file): preserves comments/structure from template, uncomments matching keys, appends unknown keys.
28. [⚪] - Test: POST /api/restart returns {"status": "restarting"} with a method field. Mock subprocess to avoid actually restarting. Verify systemd path is tried first, pkill fallback works.
29. [⚪] - Test: GET /api/logs returns lines array. Verify file param validation (only "analyzer"/"web" accepted, others return 400). Verify lines param caps at 500. Verify non-integer lines param defaults to 100. Verify missing log file returns empty lines array.
30. [⚪] - Test: GET /api/osc/latest returns a dict. Verify it reflects data pushed through the OSC bridge (_latest dict). Test get_latest() and register_ws/unregister_ws lifecycle.
31. [⚪] - Test: WebSocket /ws/osc — connect, receive snapshot of latest values, verify JSON format {address, args, t}. Verify new OSC data is broadcast to connected client. Verify disconnect cleanup (unregister_ws).
32. [⚪] - Test: static file serving — GET / returns HTML (index.html). GET /static/viz.html returns 200. GET /static/nonexistent returns 404.
33. [⚪] - Test: OSC bridge dispatcher routes /audio/* messages to _handle_osc. Verify _latest is updated. Verify unknown addresses (e.g. /foo) are not stored.

