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

All messages are sent to the configured destination (default `127.0.0.1:9000`).

| Address                    | Types         | Rate    | Description                          |
|----------------------------|---------------|---------|--------------------------------------|
| `/audio/amplitude`         | `f`           | 30 Hz   | RMS amplitude, 0.0 -- 1.0           |
| `/audio/pitch`             | `ff`          | 30 Hz   | Frequency (Hz), hasFreq (0.0--1.0)  |
| `/audio/onset`             | `i`           | trigger | 1 on each detected onset             |
| `/audio/loudness`          | `f`           | 30 Hz   | Loudness in sones                    |
| `/audio/spectral/centroid` | `f`           | 30 Hz   | Spectral centroid (Hz)               |
| `/audio/spectral/flatness` | `f`           | 30 Hz   | Spectral flatness, 0.0 -- 1.0       |
| `/audio/mfcc`              | `fffffffffffff` | 10 Hz | 13 MFCC coefficients                |
| `/audio/key`               | `ii`          | 2 Hz    | Key (0--11, C=0), mode (0=min 1=maj)|
| `/audio/beat`              | `i`           | trigger | 1 on each detected beat              |
| `/audio/bpm`               | `f`           | trigger | Estimated tempo (BPM)                |
| `/audio/chroma`            | 12x `f`       | 10 Hz   | Chromagram, 12 pitch classes         |

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

In `analyzer.scd`, comment out any `SendReply` / `OSCdef` pair you don't need. The most expensive features by CPU cost:

1. `BeatTrack2` -- remove if you don't need beat/BPM
2. `Chromagram` -- remove if you don't need chroma
3. `MFCC` -- reduce coefficients from 13 to 7
4. `KeyTrack` -- remove if you don't need key detection

## Troubleshooting

See **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** for a comprehensive guide covering audio/JACK issues, SuperCollider issues, OSC debugging, system/Pi issues, autostart problems, and a step-by-step diagnostic checklist.
