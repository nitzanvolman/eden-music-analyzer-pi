# Real-Time Audio Analysis on Raspberry Pi with SuperCollider for Eden Art Car

SuperCollider-based audio analyzer that runs headless on a Raspberry Pi and emits OSC messages for every audio feature it extracts. Point any OSC-capable application at the Pi and get amplitude, pitch, onsets, beats, MFCC, key, chroma, and spectral descriptors in real time.

## Install

See **[INSTALL.md](INSTALL.md)** for full installation instructions (quick install, build from source, manual steps, systemd setup).

## Configuration

Edit `~/sc-osc/config.env`:

```bash
# OSC destinations — comma-separated ip:port pairs (sends to all)
SC_OSC_DESTINATIONS=192.168.1.100:9000
# Multiple destinations example:
# SC_OSC_DESTINATIONS=192.168.1.100:9000,192.168.1.200:9000,10.0.0.5:7000

# Onset detection threshold (0.0 - 1.0, lower = more sensitive)
# SC_ONSET_THRESHOLD=0.5
```

This file is sourced by `autostart.sh`, the systemd service, and can be sourced manually before running. The install script preserves your edits on re-run.

## Run

### Manual (foreground)

```bash
source ~/sc-osc/config.env
export QT_QPA_PLATFORM=offscreen

# install.sh writes the sclang path to this file:
SCLANG="$(cat ~/sc-osc/.sclang_path)"

# Test with hello.scd first:
$SCLANG ~/sc-osc/hello.scd

# Then run the full analyzer:
$SCLANG ~/sc-osc/analyzer.scd
```

### Headless autostart (crontab)

```bash
crontab -e
# Add:
@reboot /home/pi/sc-osc/autostart.sh
```

### Systemd (if installed with --systemd)

```bash
sudo systemctl enable sc-osc
sudo systemctl start sc-osc
journalctl -u sc-osc -f
```

## OSC Output Reference

All messages are sent to the configured destinations (default `127.0.0.1:9000`). Trigger rates are configurable via `SC_TRIG_RATE_FAST/MEDIUM/SLOW`. Each feature can be individually disabled with `SC_FEATURE_<name>=0`.

| Address                    | Types         | Rate    | Description                          |
|----------------------------|---------------|---------|--------------------------------------|
| `/audio/amplitude`         | `f`           | 30 Hz   | RMS amplitude, 0.0 -- 1.0           |
| `/audio/pitch`             | `ff`          | 30 Hz   | Frequency (Hz), hasFreq (0.0--1.0)  |
| `/audio/onset`             | `i`           | trigger | 1 on each detected onset             |
| `/audio/loudness`          | `f`           | 30 Hz   | Loudness in sones (0--64+)           |
| `/audio/spectral/centroid` | `f`           | 30 Hz   | Spectral centroid (Hz, 200--8000)    |
| `/audio/spectral/flatness` | `f`           | 30 Hz   | Spectral flatness, 0.0 -- 1.0       |
| `/audio/mfcc`              | N x `f`       | 10 Hz   | MFCC coefficients (default 13)       |
| `/audio/key`               | `ii`          | 2 Hz    | Key (0--11, C=0), mode (0=min 1=maj)|
| `/audio/beat`              | `i`           | trigger | 1 on each detected beat              |
| `/audio/bpm`               | `f`           | trigger | Estimated tempo (BPM)                |
| `/audio/chroma`            | 12x `f`       | 10 Hz   | Chromagram, 12 pitch classes (C--B)  |

### Analysis Details

**Amplitude** — Volume envelope of the audio signal. Configurable attack/release times (`SC_AMP_ATTACK_TIME`, `SC_AMP_RELEASE_TIME`). Use for brightness, level thresholds.

**Pitch** — Fundamental frequency detection with confidence score. `hasFreq` > 0.5 means a reliable pitch is detected. Configure detection range with `SC_PITCH_MIN_FREQ` / `SC_PITCH_MAX_FREQ`.

**Loudness** — Perceptual loudness in sones (psychoacoustic model). More natural than raw amplitude — accounts for human hearing sensitivity across frequencies.

**Spectral Centroid** — "Brightness" of the sound. Low values = dark/bassy, high values = bright/trebly. Map to color temperature (warm reds to cool blues).

**Spectral Flatness** — How noise-like vs tone-like the sound is. 0.0 = pure tone (flute), 1.0 = noise (static). Drums/percussion score higher than melodic instruments.

**Onset Detection** — Triggers on note/drum hits. Configurable threshold (`SC_ONSET_THRESHOLD`, lower = more sensitive) and algorithm (`SC_ONSET_ALGORITHM`: rcomplex, complex, phase, wphase, mkl, magsum, power).

**MFCC** — Timbre fingerprint. Compact representation of the sound's texture. Coefficient 0 = energy, 1--5 = broad spectral shape, higher = finer detail. Count configurable (`SC_MFCC_NUM_COEFF`, default 13, max 42).

**Key Detection** — Musical key estimation. Returns pitch class (0=C through 11=B) and mode (1=major, 0=minor). Smoothing via `SC_KEY_DECAY_TIME`. Works best with `SC_FFT_SIZE=4096`.

**Chromagram** — Energy of each of the 12 pitch classes (C through B) regardless of octave. Shows which notes are playing. Requires Chromagram UGen (included in redFrik standalone, build SCMIRUGens for from-source).

**Beat Tracking** — Detects beats and estimates BPM using template matching. `SC_BEAT_LOCK=0` adapts quickly (live DJs), `SC_BEAT_LOCK=1` holds steady tempo (produced tracks).

## Testing

### With oscdump (liblo-tools)

```bash
sudo apt install liblo-tools
oscdump 9000
```

### With Python

```bash
pip install python-osc
python test_receiver.py
# or from another machine:
python test_receiver.py --port 9000
```

## Tuning

### JACK buffer sizes

Edit `~/.jackdrc`. Smaller buffers = lower latency but higher CPU:

| Setting       | Latency   | CPU   | Use case           |
|---------------|-----------|-------|--------------------|
| `-p 256 -n 2` | ~11.6 ms  | High  | Tight onset detect |
| `-p 512 -n 3` | ~34.8 ms  | Med   | Default, balanced  |
| `-p 1024 -n 3`| ~69.7 ms  | Low   | CPU-constrained    |

### CPU governor

The install script sets `performance`. To revert:

```bash
echo ondemand | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
```

### Disable features to save CPU

Set `SC_FEATURE_<name>=0` in `config.env` to disable individual features. Disabled features are completely excluded from the analysis graph — no computation, no OSC output. Most expensive features by CPU cost:

1. `SC_FEATURE_BEAT=0` — disable beat/BPM tracking
2. `SC_FEATURE_CHROMA=0` — disable chromagram
3. `SC_FEATURE_MFCC=0` — disable MFCC (or reduce `SC_MFCC_NUM_COEFF` to 7)
4. `SC_FEATURE_KEY=0` — disable key detection

## Web Interface

Start the web server:

```bash
source ~/sc-osc/.venv/bin/activate
python -m web.server
```

Open `http://<pi-ip>:8080` in a browser. Pages:

- **Home** — server status
- **Config** — view and edit all configuration values, restart analyzer
- **Viz** — live audio visualization (expert dashboard + full-screen public mode)
- **Help** — detailed analysis feature reference

The web server receives OSC data from the analyzer and streams it to browsers via WebSocket. Configure the port with `SC_WEB_PORT` (default 8080).

## Troubleshooting

See **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** for a comprehensive guide covering audio/JACK issues, SuperCollider issues, OSC debugging, system/Pi issues, autostart problems, and a step-by-step diagnostic checklist.
