#!/usr/bin/env bash
# install.sh — Set up SuperCollider audio analyzer
# Supports multiple install modes:
#   ./install.sh              — Raspberry Pi, redFrik pre-built standalone (fast, 5 min)
#   ./install.sh --from-source — Raspberry Pi, builds SC from source (safe, 60-90 min)
#   ./install.sh --mac         — macOS, installs via Homebrew
#   ./install.sh --systemd    — also sets up a systemd service for autostart (Pi only)
# Flags can be combined: ./install.sh --from-source --systemd
#
# Idempotent: safe to run multiple times.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SC_OSC_DIR="$HOME/sc-osc"
SETUP_SYSTEMD=false
FROM_SOURCE=false
MAC_MODE=false

# Where SC ends up
SC_INSTALL_DIR=""  # set below based on mode
SCLANG_BIN=""      # set below based on mode

# --- Parse flags ---
for arg in "$@"; do
	case "$arg" in
		--systemd) SETUP_SYSTEMD=true ;;
		--from-source) FROM_SOURCE=true ;;
		--mac) MAC_MODE=true ;;
		*) echo "Unknown flag: $arg"; echo "Usage: $0 [--from-source] [--mac] [--systemd]"; exit 1 ;;
	esac
done

# --- Platform check ---
ARCH="$(uname -m)"
OS="$(uname -s)"

if [[ "$MAC_MODE" == true ]]; then
	if [[ "$OS" != "Darwin" ]]; then
		echo "ERROR: --mac flag requires macOS. Detected: $OS"
		exit 1
	fi
	echo "=== SC-OSC Installer (macOS) ==="
elif [[ "$ARCH" != "aarch64" && "$ARCH" != "armv7l" ]]; then
	echo "ERROR: This script is intended for Raspberry Pi (aarch64/armv7l) or macOS (--mac)."
	echo "Detected: $OS $ARCH"
	exit 1
else
	echo "=== SC-OSC Installer ==="
	echo "Architecture: $ARCH"
	if [[ "$FROM_SOURCE" == true ]]; then
		echo "Mode: build from source"
	else
		echo "Mode: redFrik standalone (pre-built)"
	fi
fi
echo ""

if [[ "$MAC_MODE" == true ]]; then
# ==========================================================================
# macOS install via Homebrew
# ==========================================================================
echo "--- macOS: Installing via Homebrew ---"

if ! command -v brew &>/dev/null; then
	echo "ERROR: Homebrew not found. Install from https://brew.sh"
	exit 1
fi

# Install SuperCollider (includes sclang, scsynth, sc3-plugins)
if command -v sclang &>/dev/null; then
	echo "sclang already installed: $(command -v sclang)"
	SCLANG_BIN="$(command -v sclang)"
else
	echo "Installing SuperCollider..."
	brew install --cask supercollider
	# sclang is inside the app bundle
	SCLANG_BIN="/Applications/SuperCollider.app/Contents/MacOS/sclang"
	if [[ ! -x "$SCLANG_BIN" ]]; then
		echo "ERROR: sclang not found at $SCLANG_BIN after install."
		echo "Check SuperCollider.app installation and adjust SCLANG_BIN."
		exit 1
	fi
	echo "SuperCollider installed."
fi

# Install liblo for oscdump testing tool
brew list liblo &>/dev/null || brew install liblo

# Python (macOS usually has python3 via Xcode/Homebrew)
if ! command -v python3 &>/dev/null; then
	echo "Installing Python..."
	brew install python@3.12
fi

echo "macOS dependencies ready."
echo ""

else
# ==========================================================================
# Raspberry Pi: System dependencies (needed for both modes)
# ==========================================================================
echo "--- Installing system dependencies ---"
sudo apt-get update -qq

# Base deps for both modes
sudo apt-get install -y --no-install-recommends \
	jackd2 \
	libjack-jackd2-dev \
	libfftw3-3 \
	libfftw3-dev \
	libsndfile1 \
	libsndfile1-dev \
	libasound2 \
	liblo-tools \
	git \
	python3-pip

if [[ "$FROM_SOURCE" == true ]]; then
	# Extra deps for building SC from source
	# sclang requires Qt even for headless operation (class library, event loop)
	sudo apt-get install -y --no-install-recommends \
		build-essential \
		cmake \
		libxt-dev \
		libavahi-client-dev \
		libudev-dev \
		libreadline-dev \
		qtbase5-dev \
		libqt5network5 \
		libqt5sensors5 \
		libqt5positioning5 \
		libqt5svg5-dev \
		libqt5websockets5-dev
else
	# Qt runtime libs needed by the redFrik standalone binaries
	sudo apt-get install -y --no-install-recommends \
		libqt5network5 \
		libqt5sensors5 \
		libqt5positioning5
fi

echo "System dependencies installed."

# ==========================================================================
# SuperCollider installation
# ==========================================================================
if [[ "$FROM_SOURCE" == true ]]; then
	# ------------------------------------------------------------------
	# BUILD FROM SOURCE
	# ------------------------------------------------------------------
	SC_SRC_DIR="$HOME/supercollider-src"
	SC_INSTALL_DIR="/usr/local"
	SCLANG_BIN="$SC_INSTALL_DIR/bin/sclang"

	echo ""
	echo "--- Building SuperCollider from source ---"
	echo "This will take 30-60 minutes on Pi 4, longer on Pi 3."
	echo ""

	if [[ -x "$SCLANG_BIN" ]]; then
		echo "sclang already installed at $SCLANG_BIN, skipping build."
		echo "To rebuild, remove it first: sudo rm $SCLANG_BIN"
	else
		# Clone SC source
		if [[ -d "$SC_SRC_DIR" ]]; then
			echo "SC source already cloned at $SC_SRC_DIR"
		else
			echo "Cloning SuperCollider source..."
			git clone --depth 1 --recurse-submodules \
				https://github.com/supercollider/supercollider.git "$SC_SRC_DIR"
		fi

		# Build SC (headless, no IDE, no Qt GUI)
		echo "Configuring build (headless, no IDE)..."
		mkdir -p "$SC_SRC_DIR/build"
		cd "$SC_SRC_DIR/build"
		# sclang needs Qt (class library, event loop). We disable only the IDE.
		# QT_QPA_PLATFORM=offscreen handles headless operation at runtime.
		cmake .. \
			-DCMAKE_BUILD_TYPE=Release \
			-DSUPERNOVA=OFF \
			-DSC_EL=OFF \
			-DSC_VIM=OFF \
			-DSC_IDE=OFF \
			-DNO_X11=ON \
			-DNATIVE=ON
		echo "Building (this is the slow part)..."
		make -j2
		sudo make install
		sudo ldconfig
		echo "SuperCollider installed to $SC_INSTALL_DIR"
	fi

	# Build sc3-plugins (for Tartini pitch tracker, etc.)
	SC3_SRC_DIR="$HOME/sc3-plugins-src"
	echo ""
	echo "--- Building sc3-plugins ---"

	if [[ -d "$SC_INSTALL_DIR/share/SuperCollider/Extensions/SC3plugins" ]]; then
		echo "sc3-plugins already installed, skipping."
	else
		if [[ -d "$SC3_SRC_DIR" ]]; then
			echo "sc3-plugins source already cloned."
		else
			echo "Cloning sc3-plugins..."
			git clone --depth 1 --recurse-submodules \
				https://github.com/supercollider/sc3-plugins.git "$SC3_SRC_DIR"
		fi

		mkdir -p "$SC3_SRC_DIR/build"
		cd "$SC3_SRC_DIR/build"
		cmake .. \
			-DSC_PATH="$SC_SRC_DIR" \
			-DCMAKE_BUILD_TYPE=Release \
			-DSUPERNOVA=OFF
		make -j2
		sudo make install
		echo "sc3-plugins installed."
	fi

	# Build SCMIRUGens (for Chromagram — NOT part of sc3-plugins)
	# SCMIRUGens is Nick Collins' SCMIR library, which the redFrik standalone bundles
	# but sc3-plugins does not include.
	SCMIR_SRC_DIR="$HOME/scmir-ugens-src"
	SC_EXTENSIONS_DIR="$SC_INSTALL_DIR/share/SuperCollider/Extensions"
	echo ""
	echo "--- Building SCMIRUGens (Chromagram) ---"

	if [[ -d "$SC_EXTENSIONS_DIR/SCMIRUGens" ]]; then
		echo "SCMIRUGens already installed, skipping."
	else
		if [[ -d "$SCMIR_SRC_DIR" ]]; then
			echo "SCMIRUGens source already cloned."
		else
			echo "Cloning SCMIRUGens..."
			git clone --depth 1 \
				https://github.com/spluta/SCMIRUGens.git "$SCMIR_SRC_DIR"
		fi

		mkdir -p "$SCMIR_SRC_DIR/build"
		cd "$SCMIR_SRC_DIR/build"
		cmake .. \
			-DSC_PATH="$SC_SRC_DIR" \
			-DCMAKE_BUILD_TYPE=Release
		make -j2
		# Install to the SC extensions directory
		sudo mkdir -p "$SC_EXTENSIONS_DIR/SCMIRUGens"
		sudo cp -r "$SCMIR_SRC_DIR/build/"*.so "$SC_EXTENSIONS_DIR/SCMIRUGens/" 2>/dev/null || true
		sudo cp -r "$SCMIR_SRC_DIR/SCMIRUGens/sc/"*.sc "$SC_EXTENSIONS_DIR/SCMIRUGens/" 2>/dev/null || true
		echo "SCMIRUGens installed."
		echo "NOTE: If Chromagram fails to load, see the troubleshooting section in README.md."
		echo "You can comment out the Chromagram lines in analyzer.scd — everything else will work."
	fi

	cd "$SCRIPT_DIR"

else
	# ------------------------------------------------------------------
	# REDFRIK STANDALONE (pre-built, fast)
	# ------------------------------------------------------------------
	SC_INSTALL_DIR="$HOME/supercolliderStandaloneRPI64"
	SCLANG_BIN="$SC_INSTALL_DIR/sclang"

	echo ""
	echo "--- SuperCollider standalone ---"
	echo "NOTE: This uses pre-built binaries from github.com/redFrik."
	echo "Single maintainer, ships SC 3.13.0. For a safer alternative:"
	echo "  ./install.sh --from-source"
	echo ""

	if [[ -d "$SC_INSTALL_DIR" ]]; then
		echo "Already present at $SC_INSTALL_DIR, skipping clone."
	else
		echo "Cloning redFrik supercolliderStandaloneRPI64..."
		git clone --depth 1 \
			https://github.com/redFrik/supercolliderStandaloneRPI64.git "$SC_INSTALL_DIR"
		echo "Cloned."
	fi
fi

fi # end if MAC_MODE / else Pi block

if [[ "$MAC_MODE" != true ]]; then
# ==========================================================================
# JACK configuration (Pi only — macOS uses CoreAudio)
# ==========================================================================
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

# ==========================================================================
# Real-time audio permissions
# ==========================================================================
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

# ==========================================================================
# CPU governor
# ==========================================================================
echo ""
echo "--- Setting CPU governor to performance ---"
for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
	if [[ -f "$cpu" ]]; then
		echo performance | sudo tee "$cpu" > /dev/null
	fi
done
echo "CPU governor set to performance."

RC_LOCAL="/etc/rc.local"
GOVERNOR_LINE='echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null'
if [[ -f "$RC_LOCAL" ]] && grep -qF "scaling_governor" "$RC_LOCAL"; then
	echo "CPU governor persistence already configured in $RC_LOCAL."
else
	echo "Note: Add the following to rc.local or a systemd service to persist across reboots:"
	echo "  $GOVERNOR_LINE"
fi

fi # end Pi-only JACK/permissions/governor block

# ==========================================================================
# Copy analyzer files
# ==========================================================================
echo ""
echo "--- Copying analyzer files ---"
mkdir -p "$SC_OSC_DIR"
cp "$SCRIPT_DIR/analyzer.scd" "$SC_OSC_DIR/analyzer.scd"
cp "$SCRIPT_DIR/hello.scd" "$SC_OSC_DIR/hello.scd"
cp "$SCRIPT_DIR/autostart.sh" "$SC_OSC_DIR/autostart.sh"
cp "$SCRIPT_DIR/test_receiver.py" "$SC_OSC_DIR/test_receiver.py"
# Copy config_template.env (always, so new parameters are visible)
cp "$SCRIPT_DIR/config_template.env" "$SC_OSC_DIR/config_template.env"
# Only create config.env from template if it doesn't already exist (preserve user edits)
if [[ ! -f "$SC_OSC_DIR/config.env" ]]; then
	cp "$SCRIPT_DIR/config_template.env" "$SC_OSC_DIR/config.env"
	echo "Created config.env from template — edit to set OSC destination, audio device, etc."
else
	echo "config.env already exists, not overwriting. Check config_template.env for new parameters."
fi
chmod +x "$SC_OSC_DIR/autostart.sh"
chmod +x "$SC_OSC_DIR/test_receiver.py"

# Write the sclang path so autostart.sh can find it
echo "$SCLANG_BIN" > "$SC_OSC_DIR/.sclang_path"

echo "Files copied to $SC_OSC_DIR"

# ==========================================================================
# Python virtual environment
# ==========================================================================
echo ""
echo "--- Setting up Python virtual environment ---"
VENV_DIR="$SC_OSC_DIR/.venv"

# Find Python 3.12+ (try python3.12, python3.13, ..., then fall back to python3)
PYTHON_BIN=""
for py in python3.13 python3.12 python3; do
	if command -v "$py" &>/dev/null; then
		PY_VER=$("$py" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
		PY_MAJOR=$("$py" -c 'import sys; print(sys.version_info.major)')
		PY_MINOR=$("$py" -c 'import sys; print(sys.version_info.minor)')
		if [[ "$PY_MAJOR" -ge 3 && "$PY_MINOR" -ge 12 ]]; then
			PYTHON_BIN="$py"
			break
		fi
	fi
done

if [[ -z "$PYTHON_BIN" ]]; then
	echo "WARNING: Python 3.12+ not found. Skipping virtual environment setup."
	echo "Install Python 3.12+ and re-run, or create the venv manually:"
	echo "  python3.12 -m venv $VENV_DIR"
else
	echo "Using $PYTHON_BIN (version $PY_VER)"
	if [[ -d "$VENV_DIR" ]]; then
		echo "Virtual environment already exists at $VENV_DIR"
	else
		"$PYTHON_BIN" -m venv "$VENV_DIR"
		echo "Created virtual environment at $VENV_DIR"
	fi
	# Install/upgrade pip and any requirements if present
	"$VENV_DIR/bin/pip" install --upgrade pip --quiet
	if [[ -f "$SCRIPT_DIR/requirements.txt" ]]; then
		"$VENV_DIR/bin/pip" install -r "$SCRIPT_DIR/requirements.txt" --quiet
		echo "Installed Python dependencies from requirements.txt"
	fi
	echo "Activate with: source $VENV_DIR/bin/activate"
fi

# ==========================================================================
# Systemd service (optional)
# ==========================================================================
if [[ "$SETUP_SYSTEMD" == true && "$MAC_MODE" != true ]]; then
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
ExecStart=$SCLANG_BIN $SC_OSC_DIR/analyzer.scd
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

# ==========================================================================
# Done
# ==========================================================================
echo ""
echo "============================================="
echo "  Installation complete!"
echo "============================================="
echo ""
if [[ "$MAC_MODE" == true ]]; then
	echo "Platform:         macOS"
else
	echo "SC installed via: $(if [[ "$FROM_SOURCE" == true ]]; then echo 'source build'; else echo 'redFrik standalone'; fi)"
fi
echo "sclang binary:    $SCLANG_BIN"
echo ""
echo "Next steps:"
if [[ "$MAC_MODE" == true ]]; then
	echo "  1. Edit $SC_OSC_DIR/config.env (set OSC destinations)"
	echo "  2. Test with hello.scd first:"
	echo "     $SCLANG_BIN $SC_OSC_DIR/hello.scd"
	echo "  3. Run the analyzer:"
	echo "     source $SC_OSC_DIR/config.env && $SCLANG_BIN $SC_OSC_DIR/analyzer.scd"
	echo "  4. Start the web server:"
	echo "     source $SC_OSC_DIR/.venv/bin/activate && python -m web.server"
	echo "  5. Verify OSC output:"
	echo "     oscdump 9000"
else
	echo "  1. Reboot for audio group and limits to take effect"
	echo "  2. Plug in your USB audio interface"
	echo "  3. Edit ~/.jackdrc if your audio device is not hw:0"
	echo "     (run 'aplay -l' to list devices)"
	echo "  4. Test with hello.scd first:"
	echo "     export QT_QPA_PLATFORM=offscreen"
	echo "     $SCLANG_BIN $SC_OSC_DIR/hello.scd"
	echo "  5. Then run the full analyzer:"
	echo "     $SCLANG_BIN $SC_OSC_DIR/analyzer.scd"
	echo "  6. Verify OSC output:"
	echo "     oscdump 9000"
	echo "  7. For autostart via crontab:"
	echo "     crontab -e"
	echo "     @reboot $SC_OSC_DIR/autostart.sh"
fi
echo ""
