# Worklog

- [Task #1] The roadmap was created.
- [Task #1] ✅
- [Task #2] Created an initial implementation of a SuperCollider-based audio analyzer that runs headless on a Raspberry Pi and emits OSC messages for every audio feature it extracts.
- [Task #2] ❌
  - redFrik's pre-built SuperCollider Fork may not be well maintained and may be risky to rely on.
  - The project is untested without access to a raspberry pi
- [Task #2] Did the following
  - Added a safe install option from the official repos.
  - Added a Troubleshooting section to the README.
- [Task #2] ✅
- [Task #3] The README has been split into three files:
  - README.md — Configuration, how to run, OSC output reference, testing, and tuning
  - INSTALL.md — Prerequisites, quick/source install, manual steps
  - TROUBLESHOOTING.md — All troubleshooting sections and diagnostic checklist
  The README links to both new files at the top (Install) and bottom (Troubleshooting).
- [Task #3] ✅
- [Task #4] Created config_template.env with all tweakable parameters from analyzer.scd: audio input channel, FFT buffer size, amplitude attack/release times, pitch min/max frequency, onset detection algorithm, MFCC coefficient count, key decay time, beat tracker lock mode, and trigger rates for fast/medium/slow features. Existing parameters (OSC dest IP/port, JACK device, onset threshold) are also included.
- [Task #4] ✅ (reviewer note: Chromagram.kr FFT size on line 296 should track SC_FFT_SIZE when Task 6 wires env vars)
- [Task #5] Added multi-destination OSC support. New SC_OSC_DESTINATIONS env var accepts comma-separated ip:port pairs. Falls back to legacy SC_OSC_DEST_IP/SC_OSC_DEST_PORT if not set. All OSCdef forwarders now iterate over the dests array (broadcast pattern). Updated config_template.env, README, and analyzer.scd.
- [Task #5] ✅
- [Task #4] ❌ - Re-review against SC API docs found: (1) onset algorithm options missing `complex` and `magsum`, (2) KeyTrack requires FFT size 4096 but no warning in config template. Fixed both issues.
