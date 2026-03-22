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
4) Else, emit "ROADMAP COMPLETE" and stop.

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

1) **Append** an entry to the **end** of worklog.md summarizing your work. Never insert entries in the middle — always add at the bottom so the log reflects chronological order.
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
23. [🟢] - Analyzer heartbeat OSC — analyzer sends a periodic heartbeat OSC message; web home page reports analyzer status (alive/dead) based on heartbeat presence.
24. [🟢] - Onset detection suite — replace the single onset detector with a multi-channel onset suite. Each channel runs the Onsets UGen with a specific algorithm, frequency band, and threshold tuned for a distinct musical event. All channels fire independently on their own OSC path. Uses PV_Copy to share a single FFT analysis across all onset instances.
    - **Channels:**
      | OSC Path | Algorithm | Frequency Band | Default Threshold | Detects |
      |----------|-----------|---------------|-------------------|---------|
      | `/audio/onset/kick` | mkl | LPF 100 Hz | 0.3 | Kick drum / bass drum thump |
      | `/audio/onset/snare` | mkl | BPF 200–2000 Hz | 0.4 | Snare crack, claps, rim shots |
      | `/audio/onset/hihat` | mkl | HPF 5000 Hz | 0.3 | Hi-hats, cymbals, shakers |
      | `/audio/onset/perc` | mkl | Full spectrum | 0.4 | Any sharp percussive hit |
      | `/audio/onset/bass` | phase | LPF 200 Hz | 0.7 | Bass note changes (synth bass, bass guitar) |
      | `/audio/onset/melody` | phase | BPF 300–4000 Hz | 0.7 | Vocal/synth/lead note changes |
      | `/audio/onset/bright` | phase | HPF 3000 Hz | 0.7 | High-pitched melodic changes, arpeggios |
      | `/audio/onset/any` | rcomplex | Full spectrum | 0.5 | Catch-all — any onset of any kind |
      | `/audio/onset/drop` | power | Full spectrum | 0.8 | Big energy spikes — drops, impacts, explosions |
      | `/audio/onset/soft` | rcomplex | Full spectrum | 0.9 | Only the most obvious, unmistakable onsets |
    - **Sub-tasks:**
    - 24a. [🟢] - Analyzer (`analyzer.scd`): Replace the single Onsets UGen with the onset suite. For each channel: apply the frequency band filter (LPF/BPF/HPF) to the input signal, run FFT + Onsets with the specified algorithm and threshold, SendReply on the channel's OSC path. Use PV_Copy where channels share the same filtered signal. Each channel is gated by its own feature toggle env var. Remove the old `SC_ONSET_ALGORITHM` and `SC_ONSET_THRESHOLD` config vars.
    - 24b. [🟢] - Config (`config_template.env`): Replace `SC_ONSET_ALGORITHM` and `SC_ONSET_THRESHOLD` with per-channel config. For each onset channel: `SC_ONSET_{NAME}=0/1` (enable/disable, default from table above) and `SC_ONSET_{NAME}_THRESHOLD` (default from table above). Remove the old single-onset config vars. Replace `SC_FEATURE_ONSET=1` with `SC_FEATURE_ONSET_SUITE=1` as a master toggle for the entire suite.
    - 24c. [🟢] - Web OSC bridge (`web/osc_bridge.py`): Register listeners for all 10 onset OSC paths. Forward each as its own WebSocket message type (e.g. `onset/kick`, `onset/snare`, etc.). Update the latest-value cache to store each channel separately.
    - 24d. [🟢] - Web UI: Update the visualization page to show the onset suite — replace the single onset indicator with a group of per-channel indicators. Each indicator is a flash/pulse animation (not a counter) — it lights up on trigger and fades out, like a beat light. Update the help page with descriptions of each onset channel and what it detects.
    - 24e. [🟢] - Documentation: Update README.md output reference, help page, and CLAUDE.md to reflect the new onset suite OSC paths, config vars, and architecture.
25. [🟢] - Pitch card redesign — replace the raw Hz display with a note history piano ribbon. Show a small horizontal piano keyboard (2–3 octaves) that scrolls left over time, highlighting the detected note on each update. Only display notes when pitch confidence is above a threshold to avoid jitter from noise. The current note name (e.g. "A4") should be shown large above the ribbon. Hz value can be small secondary text or removed entirely.
26. [🟢] - Brightness card redesign — replace the raw Hz number with a sliding marker on a dark-to-bright gradient bar. The marker position represents the spectral centroid value. No number needed — the position on the gradient is the information. Apply exponential smoothing so the marker glides instead of jumping. Keep the existing color-temperature aesthetic of the bar.
27. [🟢] - Remove MFCC Timbre card from the visualization UI.
28. [🟢] - Organize the visualization UI into meaningful groupings: (Tempo + Onsets), (Key + Pitch + Chromagram), (Loudness + Spectral Centroid + Noisiness).
29. [🟢] - When i click on any of the cards in the visualization UI, I would like to open a modal popup showing the all of the specific OSC commands being send and their values in real time, so it's easy for me to program the OSC reciever.
30. [🟢] - Modularize viz.html — split the monolithic file into separate CSS, JS, and HTML files for easier maintenance. Extract styles into a stylesheet, JS into modules (state, websocket, renderers, modal, public view), and keep viz.html as a slim shell that imports them.
31. [🟢] - Fix pitch ribbon jitter — the piano ribbon canvas visually jumps up and down as new notes arrive. Likely caused by the auto-ranging (median recalculation) shifting minMidi/maxMidi on every frame, causing all dots to reposition. Fix by stabilizing the range — e.g. only recalculate range when the current note falls outside the visible window, or smooth the range transitions.
32. [🟢] - Fit the viz layout on screen without scrolling. The "Pitch & Harmony" section currently overflows — Key, Pitch, and Chromagram each take too much vertical space. Make all three fit in a single row: Key stays narrow (1 col), Pitch becomes 1 col (not wide), Chromagram becomes 1 col (not wide). Reduce canvas heights as needed. The goal is that the full dashboard (all 3 sections) is visible without scrolling on a standard laptop screen.
33. [🟢] - Pitch card: reduce to 1 column width and halve the time span (show 50% of current history length).
34. [🟢] - Analyzer: add scene change detection using `PV_HainsworthFoote` (spectral novelty trigger, OSC path `/audio/scene_change`) and energy contour (short-term vs long-term loudness comparison, OSC path `/audio/energy_direction` — positive = building, negative = breaking down).
35. [🟢] - Analyzer: add vocal likelihood detection — band-pass to vocal range (300–4000 Hz), combine pitch confidence + low spectral flatness as a 0–1 "vocal likelihood" score. OSC path `/audio/vocal`. Note: this is a heuristic — it will also trigger on tonal synth leads, which is acceptable for EDM lighting use.
36. [🟢] - Viz UI: combine Tempo and Onsets into one card, and add vocal detection indicator to it (Beat + Onsets + Vocal in a single card).
37. [🟢] - Viz UI: add a new card on the first row for Scene/Mood. Shows scene change triggers (flash on spectral novelty events) and a building-up / breaking-down energy direction indicator.
38. [🟢] - Viz UI: align all meter bars in the "Dynamics & Timbre" section to the bottom of their cards, so they share the same Y position regardless of card content height.
39. [🟢] - Documentation review: audit README.md, help page, and CLAUDE.md to ensure the OSC interface documentation is up to date with all recent additions (input conditioning, scene change, energy direction, vocal likelihood). Update output reference tables, feature descriptions, and architecture notes.
40. [🟢] - Analyzer: improve chromagram accuracy — (a) band-pass the signal to melodic range (configurable `SC_CHROMA_MIN_FREQ`/`SC_CHROMA_MAX_FREQ`, default 200–4000 Hz) before feeding it to Chromagram, filtering out percussion/sub-bass/noise that splash energy across all pitch classes; (b) use a dedicated larger FFT buffer (4096 or 8192) for the Chromagram UGen to improve frequency resolution and reduce pitch class bleed.
41. [🟢] - Viz UI: make the Rhythm card 2 columns wide and the Scene/Mood card 2 columns wide, so both fit in a single row.
42. [🟢] - Analyzer: fix BPM bug — BPM is constantly showing 1 or 2 instead of actual tempo. Investigate and fix the BeatTrack2 output or OSC forwarding in analyzer.scd.
43. [🟢] - Viz UI: in the Scene/Mood card, change "Breaking" / "Building" labels to "DOWN" / "UP".
44. [🟢] - Viz UI: in the Rhythm card, add Beat and Vocal as onset-style pip boxes in the grid (12 total pips instead of 10 + separate BPM/vocal displays). Beat pip flashes on each beat, Vocal pip lights up when vocal likelihood is high. Remove the separate vocal meter bar.
45. [🔵] - Modularize analyzer.scd — split the monolithic file into several files (e.g., config, SynthDef, OSC forwarding, test mode) for easier maintenance. Use sclang's file loading mechanisms to compose them.
