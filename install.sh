#!/usr/bin/env bash
# install.sh — Set up SuperCollider audio analyzer on Raspberry Pi
# Idempotent: safe to run multiple times.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SC_STANDALONE_DIR="$HOME/supercolliderStandaloneRPI64"
SC_OSC_DIR="$HOME/sc-osc"
SETUP_SYSTEMD=false

# --- Parse flags ---
for arg in "$@"; do
	case "$arg" in
		--systemd) SETUP_SYSTEMD=true ;;
		*) echo "Unknown flag: $arg"; exit 1 ;;
	esac
done

# --- Architecture check ---
ARCH="$(uname -m)"
if [[ "$ARCH" != "aarch64" && "$ARCH" != "armv7l" ]]; then
	echo "ERROR: This script is intended for Raspberry Pi (aarch64/armv7l)."
	echo "Detected architecture: $ARCH"
	exit 1
fi

echo "=== SC-OSC Installer ==="
echo "Architecture: $ARCH"
echo ""

# --- System dependencies ---
echo "--- Installing system dependencies ---"
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
	jackd2 \
	libjack-jackd2-dev \
	libqt5network5 \
	libqt5sensors5 \
	libqt5positioning5 \
	libfftw3-3 \
	libsndfile1 \
	libasound2 \
	liblo-tools \
	git \
	python3-pip

echo "System dependencies installed."

# --- Clone redFrik standalone ---
echo ""
echo "--- SuperCollider standalone ---"
if [[ -d "$SC_STANDALONE_DIR" ]]; then
	echo "Already present at $SC_STANDALONE_DIR, skipping clone."
else
	echo "Cloning redFrik supercolliderStandaloneRPI64..."
	git clone https://github.com/redFrik/supercolliderStandaloneRPI64.git "$SC_STANDALONE_DIR"
	echo "Cloned."
fi

# --- Configure JACK ---
echo ""
echo "--- Configuring JACK ---"
JACKDRC="$HOME/.jackdrc"
JACK_CONFIG="/usr/bin/jackd -dalsa -dhw:0 -p512 -n3 -r44100 -s"
if [[ -f "$JACKDRC" ]]; then
	echo "~/.jackdrc already exists:"
	cat "$JACKDRC"
	echo ""
	echo "Leaving it as-is. Edit manually if needed."
else
	echo "$JACK_CONFIG" > "$JACKDRC"
	echo "Created $JACKDRC:"
	cat "$JACKDRC"
fi

# --- Real-time audio permissions ---
echo ""
echo "--- Configuring real-time audio permissions ---"
LIMITS_FILE="/etc/security/limits.d/audio.conf"
if [[ -f "$LIMITS_FILE" ]]; then
	echo "$LIMITS_FILE already exists, skipping."
else
	sudo tee "$LIMITS_FILE" > /dev/null <<'LIMITS'
@audio   -  rtprio     95
@audio   -  memlock    unlimited
LIMITS
	echo "Created $LIMITS_FILE"
fi

# Add user to audio group if not already a member
if id -nG "$USER" | grep -qw audio; then
	echo "User $USER already in audio group."
else
	sudo usermod -a -G audio "$USER"
	echo "Added $USER to audio group."
fi

# --- CPU governor ---
echo ""
echo "--- Setting CPU governor to performance ---"
for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
	if [[ -f "$cpu" ]]; then
		echo performance | sudo tee "$cpu" > /dev/null
	fi
done
echo "CPU governor set to performance."

# Make it persistent across reboots
RC_LOCAL="/etc/rc.local"
GOVERNOR_LINE='echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null'
if [[ -f "$RC_LOCAL" ]] && grep -qF "scaling_governor" "$RC_LOCAL"; then
	echo "CPU governor persistence already configured in $RC_LOCAL."
else
	echo "Note: Add the following to rc.local or a systemd service to persist across reboots:"
	echo "  $GOVERNOR_LINE"
fi

# --- Copy analyzer files ---
echo ""
echo "--- Copying analyzer files ---"
mkdir -p "$SC_OSC_DIR"
cp "$SCRIPT_DIR/analyzer.scd" "$SC_OSC_DIR/analyzer.scd"
cp "$SCRIPT_DIR/hello.scd" "$SC_OSC_DIR/hello.scd"
cp "$SCRIPT_DIR/autostart.sh" "$SC_OSC_DIR/autostart.sh"
cp "$SCRIPT_DIR/test_receiver.py" "$SC_OSC_DIR/test_receiver.py"
# Only copy config.env if it doesn't already exist (preserve user edits)
if [[ ! -f "$SC_OSC_DIR/config.env" ]]; then
	cp "$SCRIPT_DIR/config.env" "$SC_OSC_DIR/config.env"
	echo "Created config.env — edit to set OSC destination, audio device, etc."
else
	echo "config.env already exists, not overwriting."
fi
chmod +x "$SC_OSC_DIR/autostart.sh"
chmod +x "$SC_OSC_DIR/test_receiver.py"
echo "Files copied to $SC_OSC_DIR"

# --- Systemd service (optional) ---
if [[ "$SETUP_SYSTEMD" == true ]]; then
	echo ""
	echo "--- Setting up systemd service ---"
	SERVICE_FILE="/etc/systemd/system/sc-osc.service"
	sudo tee "$SERVICE_FILE" > /dev/null <<SERVICE
[Unit]
Description=SC-OSC Audio Analyzer
After=sound.target network.target
Wants=sound.target

[Service]
Type=simple
User=$USER
EnvironmentFile=$SC_OSC_DIR/config.env
Environment=QT_QPA_PLATFORM=offscreen
Environment=JACK_NO_AUDIO_RESERVATION=1
Environment=DISPLAY=
ExecStartPre=/bin/sleep 10
ExecStart=$SC_STANDALONE_DIR/sclang $SC_OSC_DIR/analyzer.scd
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE
	sudo systemctl daemon-reload
	sudo systemctl enable sc-osc
	echo "Systemd service created and enabled."
	echo "Start with: sudo systemctl start sc-osc"
	echo "Logs with:  journalctl -u sc-osc -f"
fi

# --- Done ---
echo ""
echo "============================================="
echo "  Installation complete!"
echo "============================================="
echo ""
echo "Next steps:"
echo "  1. Reboot for audio group and limits to take effect"
echo "  2. Plug in your USB audio interface"
echo "  3. Edit ~/.jackdrc if your audio device is not hw:0"
echo "     (run 'aplay -l' to list devices)"
echo "  4. Test manually:"
echo "     cd $SC_STANDALONE_DIR"
echo "     ./sclang $SC_OSC_DIR/analyzer.scd"
echo "  5. Verify OSC output:"
echo "     oscdump 9000"
echo "  6. For autostart via crontab:"
echo "     crontab -e"
echo "     @reboot $SC_OSC_DIR/autostart.sh"
echo ""
