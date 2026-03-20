# Troubleshooting

This project was built without access to a Raspberry Pi. The following covers every likely issue a first-time deployer will hit.

---

## Audio / JACK Issues

### JACK fails to start: "cannot open audio device"

**Symptom:** sclang prints `could not open component` or `Cannot open audio device hw:0` and the server never boots.

**Cause:** The device in `~/.jackdrc` doesn't exist, or another process (PulseAudio, a previous JACK instance) has exclusive access.

**Fix:**
```bash
# List available audio devices
aplay -l
arecord -l

# Kill anything holding the device
killall jackd pulseaudio 2>/dev/null

# Update ~/.jackdrc with the correct device number
# If your USB interface shows as card 1:
echo '/usr/bin/jackd -dalsa -dhw:1 -p512 -n3 -r44100 -s' > ~/.jackdrc

# Test JACK manually
jackd -dalsa -dhw:1 -p512 -n3 -r44100 -s
```

### JACK fails to start: "Cannot use real-time scheduling"

**Symptom:** `Cannot use real-time scheduling (RR/80)` or `Cannot lock down ... memory`.

**Cause:** The user is not in the `audio` group, or `/etc/security/limits.d/audio.conf` is missing.

**Fix:**
```bash
# Check group membership
groups $USER  # should include 'audio'

# If not:
sudo usermod -a -G audio $USER

# Check limits file exists
cat /etc/security/limits.d/audio.conf
# Should contain:
# @audio   -  rtprio     95
# @audio   -  memlock    unlimited

# If missing, create it:
sudo tee /etc/security/limits.d/audio.conf > /dev/null <<'EOF'
@audio   -  rtprio     95
@audio   -  memlock    unlimited
EOF

# REBOOT required for group/limits changes to take effect
sudo reboot
```

### No audio input detected (silence, all values zero)

**Symptom:** SC boots successfully, OSC messages are sent, but amplitude is always 0.0, pitch is random, onsets never fire.

**Cause:** Wrong `hw:N` device (you're reading from a device with no input), USB interface not recognized, or input gain is at zero.

**Fix:**
```bash
# List CAPTURE devices specifically
arecord -l

# Test that the device actually captures audio
arecord -D hw:1 -f S16_LE -r 44100 -c 1 -d 5 /tmp/test.wav
aplay /tmp/test.wav  # should hear what you recorded

# If the USB device isn't listed at all:
lsusb                    # check it's physically recognized
dmesg | tail -20         # check for USB errors
# Try a different USB port, or a powered USB hub
```

Also check that `SoundIn.ar(0)` in `analyzer.scd` matches your input channel. Some interfaces put the mic on channel 1, not 0.

### Xruns / audio dropouts

**Symptom:** Console fills with `**** alsa_pcm: xrun of at least X msecs` messages. Analysis becomes choppy or unreliable.

**Cause:** Buffer too small for the Pi's CPU, CPU governor set to `ondemand` (throttling), or SD card I/O causing stalls.

**Fix:**
```bash
# Increase buffer size in ~/.jackdrc
# Change -p512 to -p1024 (or -p2048 for extreme cases)
echo '/usr/bin/jackd -dalsa -dhw:1 -p1024 -n3 -r44100 -s' > ~/.jackdrc

# Verify CPU governor is 'performance'
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
# If it says 'ondemand' or 'powersave':
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Check CPU usage while SC is running
top -bn1 | head -20
```

### "Cannot lock down memory" warning

**Symptom:** JACK prints `Cannot lock down ... byte memory area (Cannot allocate memory)` but continues running.

**Cause:** `memlock` limit is not set to `unlimited`. This is a warning, not an error — JACK still works, but real-time performance may suffer.

**Fix:** Same as the real-time scheduling fix above — ensure `/etc/security/limits.d/audio.conf` exists with `memlock unlimited`, user is in `audio` group, and you've rebooted.

### JACK zombie process from a previous crash

**Symptom:** JACK refuses to start with `server already active` or `cannot create server`.

**Cause:** A previous JACK instance crashed without cleaning up.

**Fix:**
```bash
killall -9 jackd scsynth sclang 2>/dev/null
# Wait a moment, then try again
sleep 2
jackd -dalsa -dhw:1 -p512 -n3 -r44100 -s
```

---

## SuperCollider Issues

### sclang crashes on startup: "could not find a Qt platform plugin"

**Symptom:** sclang exits immediately with `This application failed to start because no Qt platform plugin could be initialized`.

**Cause:** `QT_QPA_PLATFORM=offscreen` is not set. sclang has Qt dependencies even in headless mode.

**Fix:**
```bash
export QT_QPA_PLATFORM=offscreen
# This is already set in autostart.sh and the systemd service.
# If running manually, source config or set the variable first.
```

### sclang crashes: missing shared libraries

**Symptom:** `error while loading shared libraries: libQt5Network.so.5` (or similar Qt/FFTW/sndfile library).

**Cause:** System dependencies from install.sh were not installed, or you're on a minimal OS image.

**Fix:**
```bash
sudo apt-get update
sudo apt-get install -y libqt5network5 libqt5sensors5 libqt5positioning5 \
  libfftw3-3 libsndfile1 libasound2
```

### "Class not defined: Chromagram"

**Symptom:** SC errors with `ERROR: Class not defined: Chromagram` and the SynthDef fails to compile.

**Cause:** sc3-plugins are not installed. This happens if you built SC from source instead of using the redFrik standalone (which bundles sc3-plugins).

**Fix (option A):** Switch to the redFrik standalone, which includes sc3-plugins:
```bash
git clone https://github.com/redFrik/supercolliderStandaloneRPI64.git ~/supercolliderStandaloneRPI64
```

**Fix (option B):** Comment out Chromagram in `analyzer.scd`. Remove or comment these lines:
```supercollider
// In the SynthDef:
hpcp = Chromagram.kr(chain, 2048);
SendReply.kr(trig10, '/tr_chroma', hpcp);

// In the OSC forwarding section:
OSCdef(\fwdChroma, { |msg| ... }, '/tr_chroma');
```
Everything else will work without sc3-plugins. Chromagram is the only sc3-plugins UGen used.

### SynthDef syntax errors: "Parse error", "Variable not defined", "unexpected token"

**Symptom:** sclang prints errors like `ERROR: syntax error, unexpected BADTOKEN`, `Variable 'xyz' not defined`, or `Parse error` and the analyzer never starts.

**Cause:** SuperCollider has strict syntax rules that differ from most languages:
- All `var` declarations must come before any executable code in a function
- UGen arguments are **positional** (not named) — `Pitch.kr(sig, 440, 50, 4000)`, not `Pitch.kr(sig, minFreq: 50)`
- `if` requires function braces: `if(condition, { trueValue }, { falseValue })`
- Every statement ends with `;`
- Strings use double quotes `"text"`, symbols use backslash `\symbol` or single quotes `'symbol'`
- The `#` before a variable list is array destructuring: `# a, b = someUGen.kr(...)`

**Fix:** Use `hello.scd` to isolate the problem:

```bash
# Step 1: test that SC works at all with the minimal hello.scd
export QT_QPA_PLATFORM=offscreen
cd ~/supercolliderStandaloneRPI64
./sclang ~/sc-osc/hello.scd

# If hello.scd works but analyzer.scd doesn't, the bug is in analyzer.scd.
# SC error messages include line numbers — look for the line it points to.
```

**Common fixes for analyzer.scd edits:**

```supercollider
// WRONG: named arguments on UGens
Amplitude.kr(sig, attackTime: 0.01)
// RIGHT: positional arguments
Amplitude.kr(sig, 0.01, 0.1)

// WRONG: if without function braces
var mode = if(raw < 12, 1, 0);
// RIGHT: if with function braces
var mode = if(raw < 12, { 1 }, { 0 });

// WRONG: var after executable code
onset = Onsets.kr(chain, 0.5, \rcomplex);
var extra = 42;  // ERROR: var must come first
// RIGHT: all vars at top
var onset, extra;
onset = Onsets.kr(chain, 0.5, \rcomplex);
extra = 42;

// WRONG: missing semicolon
amp = Amplitude.kr(sig, 0.01, 0.1)
SendReply.kr(trig30, '/tr_amp', [amp])
// RIGHT:
amp = Amplitude.kr(sig, 0.01, 0.1);
SendReply.kr(trig30, '/tr_amp', [amp]);
```

### hello.scd — minimal test script

`hello.scd` is a stripped-down version of the analyzer that only measures volume. Use it to test that SC, JACK, and OSC work before debugging analyzer.scd:

```bash
# Terminal 1: listen for OSC
oscdump 9000

# Terminal 2: run hello world
export QT_QPA_PLATFORM=offscreen
cd ~/supercolliderStandaloneRPI64
./sclang ~/sc-osc/hello.scd
```

You should see `/hello/amplitude f <value>` in oscdump, and amplitude values printed to the console. If values are > 0 when you make noise, audio input + JACK + SC + OSC all work. From there, switch to `analyzer.scd`.

If `hello.scd` fails, the problem is in your system setup (JACK, audio device, permissions), not in the analysis code.

### Server fails to boot: "Server 'localhost' failed to start"

**Symptom:** sclang prints `Server 'localhost' failed to start` and the `onFailure` handler fires.

**Cause:** JACK is not running, or there's an audio device conflict.

**Fix:**
```bash
# Check if JACK is running
ps aux | grep jackd

# If not, check ~/.jackdrc exists and is valid
cat ~/.jackdrc

# Try starting JACK manually first
jackd -dalsa -dhw:1 -p512 -n3 -r44100 -s &
sleep 2
# Then start SC
cd ~/supercolliderStandaloneRPI64
./sclang ~/sc-osc/analyzer.scd
```

### "Buffer UGen channel mismatch" or FFT errors

**Symptom:** SC prints warnings about buffer channel mismatches or FFT-related errors.

**Cause:** FFT buffer size is not a power of 2, or a UGen expects a different FFT size than what's provided.

**Fix:** The default `LocalBuf(2048)` in `analyzer.scd` should work. If you changed it, ensure it's a power of 2 (512, 1024, 2048, 4096) and that the `Chromagram.kr(chain, 2048)` call uses the same size.

### SC hangs on boot (no output, never reaches "Booted")

**Symptom:** sclang starts but sits forever without printing the "Booted" banner. No error messages.

**Cause:** JACK started but is stuck waiting for the audio device, or the audio device has a sample rate mismatch.

**Fix:**
```bash
# Kill everything and start fresh
killall -9 jackd sclang scsynth 2>/dev/null
sleep 2

# Check what sample rates your device supports
cat /proc/asound/card1/stream0  # adjust card number

# If your device only supports 48000, update ~/.jackdrc:
echo '/usr/bin/jackd -dalsa -dhw:1 -p512 -n3 -r48000 -s' > ~/.jackdrc
```

If using autostart, the `sleep 15` in `autostart.sh` may not be long enough on older Pis. Increase it to 20 or 30.

### How to check SC is running

```bash
ps aux | grep -E 'sclang|scsynth|jackd'
# Should show three processes: jackd, scsynth, sclang
```

---

## OSC Issues

### No OSC messages received on the remote machine

**Symptom:** `test_receiver.py` or `oscdump` shows nothing, even though SC says "Analyzer running."

**Cause:** Wrong destination IP, firewall blocking UDP, or SC is sending to localhost.

**Fix:**
```bash
# Step 1: verify SC is actually sending OSC (test on the Pi itself)
oscdump 9000 &
# Edit config.env to send to 127.0.0.1 temporarily
# Restart SC — you should see messages in oscdump

# Step 2: check config.env has the right remote IP
cat ~/sc-osc/config.env
# SC_OSC_DEST_IP should be the IP of the RECEIVING machine, not the Pi

# Step 3: check firewall on the Pi
sudo iptables -L -n | grep 9000
sudo ufw status  # if ufw is installed

# Step 4: check firewall on the receiving machine
# On the receiver, ensure UDP port 9000 is open
# macOS: check System Preferences → Firewall
# Linux: sudo ufw allow 9000/udp
# Windows: add inbound rule for UDP 9000

# Step 5: test basic UDP connectivity
# On receiver:
nc -ul 9000
# On Pi:
echo "test" | nc -u <receiver-ip> 9000
```

### How to verify OSC is being sent from the Pi

```bash
# oscdump listens on a UDP port and prints all incoming OSC messages
# Install it (already included by install.sh):
sudo apt install liblo-tools

# Listen on port 9000 (temporarily set SC_OSC_DEST_IP=127.0.0.1)
oscdump 9000
# You should see lines like:
# /audio/amplitude f 0.003215
# /audio/pitch ff 440.0 0.98
# /audio/onset i 1
```

### Messages received but values are always zero or nonsensical

**Symptom:** You see OSC messages arriving, but amplitude is always ~0.0, pitch is random noise, etc.

**Cause:** Audio input is silent (wrong device, unplugged cable, muted input, gain at zero).

**Fix:** This is an audio input problem, not an OSC problem. Go back to "No audio input detected" above. Verify audio is reaching SC by recording a test with `arecord`.

### Firewall blocking UDP traffic

**Symptom:** OSC works on localhost (127.0.0.1) but not across the network.

**Cause:** `iptables`, `ufw`, or `firewalld` is blocking outbound or inbound UDP.

**Fix:**
```bash
# On the Pi (allow outbound — usually not blocked, but check):
sudo ufw allow out 9000/udp 2>/dev/null

# On the receiving machine:
sudo ufw allow in 9000/udp  # Linux
# macOS: System Settings → Network → Firewall → allow incoming
# Or just temporarily: sudo pfctl -d  (disables macOS firewall entirely)
```

### Test locally first, then go over the network

Always confirm the full pipeline works on localhost before involving the network:

```bash
# 1. Set destination to localhost
# In config.env:
SC_OSC_DEST_IP=127.0.0.1
SC_OSC_DEST_PORT=9000

# 2. Run the test receiver on the Pi
python3 ~/sc-osc/test_receiver.py --port 9000 &

# 3. Start SC
source ~/sc-osc/config.env
cd ~/supercolliderStandaloneRPI64
./sclang ~/sc-osc/analyzer.scd

# 4. You should see colored output in the test receiver
# Once confirmed, change SC_OSC_DEST_IP to the remote machine's IP
```

---

## System / Raspberry Pi Issues

### install.sh fails: "This script is intended for Raspberry Pi"

**Symptom:** `ERROR: This script is intended for Raspberry Pi (aarch64/armv7l). Detected architecture: x86_64`

**Cause:** You're running install.sh on a non-Pi machine (e.g., your laptop).

**Fix:** Run it on the Pi. If you want to inspect the script locally, that's fine — but it must be executed on ARM hardware. Transfer the files to the Pi first:
```bash
scp -r sc-osc/ pi@<pi-ip>:~/
ssh pi@<pi-ip>
cd ~/sc-osc
chmod +x install.sh
./install.sh
```

### Package not found errors during install

**Symptom:** `apt-get install` fails with `E: Unable to locate package libqt5network5` or similar.

**Cause:** Different Raspberry Pi OS version (Bullseye vs Bookworm vs Trixie) ships different package names.

**Fix:**
```bash
# Check your OS version
cat /etc/os-release

# Update package lists
sudo apt-get update

# Search for the package under a different name
apt-cache search libqt5network
# On Bookworm it might be libqt5network5t64 instead of libqt5network5

# If packages have moved, install the closest match:
sudo apt-get install -y libqt5network5t64  # Bookworm/Trixie variant
```

### Out of disk space

**Symptom:** `git clone` or `apt-get install` fails with `No space left on device`.

**Cause:** The redFrik standalone is ~200MB, and a small SD card may not have room.

**Fix:**
```bash
# Check available space
df -h /

# Clean up package cache
sudo apt-get clean
sudo apt-get autoremove -y

# If still tight, use --depth 1 for a shallow clone (saves ~50%)
git clone --depth 1 https://github.com/redFrik/supercolliderStandaloneRPI64.git ~/supercolliderStandaloneRPI64
```

### SD card too slow (causing audio dropouts)

**Symptom:** Xruns even with large buffers, `dmesg` shows `mmc0: Timeout waiting for hardware interrupt`.

**Cause:** Cheap or old SD cards have slow random I/O. SC loads class libraries and plugins from disk on startup.

**Fix:** Use a Class A2 SD card (e.g., Samsung EVO Plus, SanDisk Extreme). Once SC is running, disk I/O is minimal — this mainly affects startup time. If xruns persist, the cause is likely CPU, not disk.

### Pi overheating under sustained analysis load

**Symptom:** After running for hours, SC starts producing xruns or crashes. `vcgencmd measure_temp` shows 80C+.

**Cause:** The Pi is thermally throttling. The `performance` CPU governor keeps all cores at max frequency, generating more heat.

**Fix:**
```bash
# Check temperature
vcgencmd measure_temp

# If above 80C, add a heatsink and/or fan
# The official Pi 5 Active Cooler keeps temps under 60C

# As a software workaround, reduce analysis load:
# Comment out expensive features in analyzer.scd (BeatTrack2, Chromagram)
# Or increase JACK buffer to reduce CPU: -p1024 or -p2048
```

### 32-bit vs 64-bit OS mismatch

**Symptom:** The redFrik standalone binaries fail to execute with `cannot execute binary file: Exec format error` or `No such file or directory` (misleading — actually a dynamic linker mismatch).

**Cause:** You're running 32-bit Raspberry Pi OS but cloned the 64-bit standalone (`supercolliderStandaloneRPI64`), or vice versa.

**Fix:**
```bash
# Check your OS architecture
uname -m
# aarch64 = 64-bit → use supercolliderStandaloneRPI64
# armv7l  = 32-bit → use supercolliderStandaloneRPI2

# Check if your kernel is 64-bit but userland is 32-bit
dpkg --print-architecture
# arm64 = 64-bit userland (use RPI64)
# armhf = 32-bit userland (use RPI2)

# If you're on 32-bit and want to switch:
# Easiest: reflash with 64-bit Raspberry Pi OS
# The Pi 3, 4, 5, and Zero 2 all support 64-bit
```

---

## Autostart Issues

### Service doesn't start on boot

**Symptom:** After reboot, SC is not running. `ps aux | grep sclang` shows nothing.

**Cause (crontab):** The `sleep 15` in `autostart.sh` wasn't long enough — JACK tried to open the audio device before ALSA was ready.

**Cause (systemd):** The `ExecStartPre=/bin/sleep 10` wasn't long enough, or the service isn't enabled.

**Fix:**
```bash
# For crontab: increase sleep in autostart.sh
# Edit ~/sc-osc/autostart.sh, change 'sleep 15' to 'sleep 30'

# For systemd: check if enabled
sudo systemctl is-enabled sc-osc
# If not: sudo systemctl enable sc-osc

# Check why it failed
journalctl -u sc-osc --no-pager | tail -50

# Increase the sleep
sudo systemctl edit sc-osc
# Add:
# [Service]
# ExecStartPre=/bin/sleep 30
sudo systemctl daemon-reload
```

### How to check logs

```bash
# Crontab-based autostart logs to /tmp/sc-osc.log:
cat /tmp/sc-osc.log
tail -f /tmp/sc-osc.log  # follow in real time

# Systemd-based service logs to journald:
journalctl -u sc-osc -f           # follow in real time
journalctl -u sc-osc --no-pager   # full history
journalctl -u sc-osc -n 100       # last 100 lines
```

### How to stop and restart

```bash
# Nuclear option — kill everything:
killall jackd sclang scsynth 2>/dev/null

# Systemd:
sudo systemctl stop sc-osc
sudo systemctl start sc-osc
sudo systemctl restart sc-osc

# Crontab: kill and re-run
killall jackd sclang scsynth 2>/dev/null
sleep 2
~/sc-osc/autostart.sh &
```

### Crontab vs systemd: when to use which

| | Crontab | Systemd |
|---|---|---|
| **Setup** | One line in `crontab -e` | `install.sh --systemd` |
| **Restart on crash** | No (stays dead) | Yes (`Restart=on-failure`) |
| **Logging** | `/tmp/sc-osc.log` (manual) | `journalctl` (automatic, rotated) |
| **Dependency ordering** | `sleep N` (guess) | `After=sound.target` (declarative) |
| **Stop/start** | `killall` | `systemctl stop/start` |
| **Recommendation** | Quick testing | Production deployment |

---

## Quick Diagnostic Checklist

Run through this numbered sequence when something isn't working. Each step builds on the previous one.

```bash
# 1. Is the audio device recognized?
arecord -l
# Expected: at least one card listed. Note the card number (e.g., card 1).

# 2. Can you record audio from it?
arecord -D hw:1 -f S16_LE -r 44100 -c 1 -d 3 /tmp/test.wav && aplay /tmp/test.wav
# Expected: you hear what was recorded. If silent, check cables/gain.

# 3. Does ~/.jackdrc point to the right device?
cat ~/.jackdrc
# Expected: the -dhw:N matches your audio device card number from step 1.

# 4. Can JACK start?
killall jackd 2>/dev/null; sleep 1
jackd -dalsa -dhw:1 -p512 -n3 -r44100 -s &
sleep 2
jack_lsp
# Expected: lists JACK ports (system:capture_1, system:playback_1, etc.)
# If JACK fails, fix audio device/permissions first.

# 5. Can SC boot and send OSC? (uses hello.scd — our "hello world")
killall jackd sclang scsynth 2>/dev/null; sleep 1
export QT_QPA_PLATFORM=offscreen
oscdump 9000 &
DUMP_PID=$!
cd ~/supercolliderStandaloneRPI64
./sclang ~/sc-osc/hello.scd &
sleep 10
# Expected: oscdump shows /hello/amplitude messages.
# Console prints amp values. Values > 0 when making noise = audio input works.
# If hello.scd works, your system is ready for analyzer.scd.
kill $DUMP_PID 2>/dev/null
killall sclang scsynth jackd 2>/dev/null

# 6. Is the full analyzer sending OSC on localhost?
killall jackd sclang scsynth 2>/dev/null; sleep 1
# Terminal 1:
oscdump 9000 &
DUMP_PID=$!
# Terminal 2 (set destination to localhost first):
sed -i 's/SC_OSC_DEST_IP=.*/SC_OSC_DEST_IP=127.0.0.1/' ~/sc-osc/config.env
source ~/sc-osc/config.env
cd ~/supercolliderStandaloneRPI64
./sclang ~/sc-osc/analyzer.scd &
sleep 10
# Check oscdump output — should see /audio/amplitude, /audio/pitch, etc.
kill $DUMP_PID 2>/dev/null

# 7. Is OSC reaching the remote machine?
# On the REMOTE machine:
python3 test_receiver.py --port 9000
# On the Pi, update config.env with the remote machine's IP, restart SC.
# Expected: test_receiver.py prints colored OSC messages.

# 8. Are values sensible (not zero)?
# In the test_receiver output, check:
#   /audio/amplitude  should be > 0 when there's sound
#   /audio/pitch      second value (hasFreq) should be > 0.5 for tonal sound
#   /audio/onset      should fire on loud transients
# If all zeros: go back to step 2 (audio input problem).
```

If you get through all 8 steps, the system is working end to end.
