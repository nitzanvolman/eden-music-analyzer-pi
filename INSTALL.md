# Installation

## Prerequisites

- Raspberry Pi 4 or 5, 64-bit Raspberry Pi OS (Bookworm or later)
- USB audio interface or audio HAT (e.g., HiFiBerry DAC+ ADC, Pisound, Fe-Pi)
- Network connection (for install and OSC output)

## Quick install (redFrik standalone — pre-built, 5 min)

```bash
chmod +x install.sh
./install.sh
```

Uses [redFrik's pre-built SuperCollider standalone](https://github.com/redFrik/supercolliderStandaloneRPI64) — SC 3.13.0 with sc3-plugins included. No compilation. Single maintainer's personal repo.

## Safe install (build from source — 60-90 min on Pi 4)

```bash
chmod +x install.sh
./install.sh --from-source
```

Builds SC and sc3-plugins from the official repos. No third-party binary dependency. Takes longer but you get the latest SC version and full control.

## Optional: autostart on boot

Add `--systemd` to either mode:

```bash
./install.sh --systemd                # with redFrik standalone
./install.sh --from-source --systemd  # with source build
```

After install, **reboot** so that real-time audio limits and CPU governor take effect.

## What install.sh does (and how to do it manually)

### 1. System dependencies

```bash
sudo apt-get update
sudo apt-get install -y jackd2 libjack-jackd2-dev libfftw3-3 libfftw3-dev \
  libsndfile1 libsndfile1-dev libasound2 liblo-tools git
# For redFrik standalone only (pre-built binaries need Qt runtime):
sudo apt-get install -y libqt5network5 libqt5sensors5 libqt5positioning5
# For building from source only:
sudo apt-get install -y build-essential cmake libxt-dev libavahi-client-dev \
  libudev-dev libreadline-dev
```

### 2. SuperCollider

**Option A: redFrik standalone** (what `./install.sh` does)

```bash
git clone --depth 1 https://github.com/redFrik/supercolliderStandaloneRPI64.git \
  ~/supercolliderStandaloneRPI64
```

Pre-built SC 3.13.0 + sc3-plugins for Pi 3/4/5 (64-bit). ~200MB download.

**Option B: build from source** (what `./install.sh --from-source` does)

```bash
# SuperCollider (sclang needs Qt even headless — only the IDE is disabled)
sudo apt-get install -y build-essential cmake qtbase5-dev libqt5svg5-dev \
  libqt5websockets5-dev libxt-dev libavahi-client-dev libudev-dev libreadline-dev
git clone --depth 1 --recurse-submodules \
  https://github.com/supercollider/supercollider.git ~/supercollider-src
cd ~/supercollider-src && mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release -DSUPERNOVA=OFF -DSC_IDE=OFF \
  -DNO_X11=ON -DNATIVE=ON -DSC_EL=OFF -DSC_VIM=OFF
make -j2   # -j2 to avoid OOM on Pi 3 (1GB RAM)
sudo make install && sudo ldconfig

# sc3-plugins (Tartini pitch tracker, etc.)
git clone --depth 1 --recurse-submodules \
  https://github.com/supercollider/sc3-plugins.git ~/sc3-plugins-src
cd ~/sc3-plugins-src && mkdir build && cd build
cmake .. -DSC_PATH=~/supercollider-src -DCMAKE_BUILD_TYPE=Release -DSUPERNOVA=OFF
make -j2
sudo make install

# SCMIRUGens (Chromagram — NOT part of sc3-plugins, separate project)
git clone --depth 1 https://github.com/spluta/SCMIRUGens.git ~/scmir-ugens-src
cd ~/scmir-ugens-src && mkdir build && cd build
cmake .. -DSC_PATH=~/supercollider-src -DCMAKE_BUILD_TYPE=Release
make -j2
sudo make install
```

This installs `sclang` and `scsynth` to `/usr/local/bin/`. Build takes 30-60 min on Pi 4, 60-90 min on Pi 3. Use `-j2` (not `-j4`) to avoid running out of memory on 1GB Pi models.

### 3. JACK audio configuration

```bash
# Create JACK config (adjust -dhw:N to match your audio device)
# Run 'aplay -l' to find your device number
echo '/usr/bin/jackd -dalsa -dhw:0 -p512 -n3 -r44100 -s' > ~/.jackdrc
```

Use `-n3` for USB audio interfaces, `-n2` for onboard/HAT audio.

### 4. Real-time audio permissions

```bash
sudo tee /etc/security/limits.d/audio.conf > /dev/null <<'EOF'
@audio   -  rtprio     95
@audio   -  memlock    unlimited
EOF
sudo usermod -a -G audio $USER
```

### 5. CPU governor

```bash
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
```

### 6. Copy analyzer files

```bash
mkdir -p ~/sc-osc
cp analyzer.scd autostart.sh test_receiver.py config_template.env ~/sc-osc/
cp config_template.env ~/sc-osc/config.env  # create config from template
chmod +x ~/sc-osc/autostart.sh ~/sc-osc/test_receiver.py
```
