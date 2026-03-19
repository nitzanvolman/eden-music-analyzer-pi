#!/usr/bin/env bash
# autostart.sh — Launch SC-OSC analyzer headless on boot
# Usage: add to crontab with @reboot ~/sc-osc/autostart.sh
set -euo pipefail

LOGFILE="/tmp/sc-osc.log"
SC_OSC_DIR="$HOME/sc-osc"
ANALYZER="$SC_OSC_DIR/analyzer.scd"
CONFIG="$SC_OSC_DIR/config.env"
SCLANG_PATH_FILE="$SC_OSC_DIR/.sclang_path"

# Resolve sclang binary (written by install.sh, works for both standalone and source builds)
if [[ -f "$SCLANG_PATH_FILE" ]]; then
	SCLANG="$(cat "$SCLANG_PATH_FILE")"
elif [[ -x "$HOME/supercolliderStandaloneRPI64/sclang" ]]; then
	SCLANG="$HOME/supercolliderStandaloneRPI64/sclang"
elif command -v sclang &>/dev/null; then
	SCLANG="$(command -v sclang)"
else
	echo "ERROR: sclang not found. Run install.sh first." >> "$LOGFILE"
	exit 1
fi

# Load config file
if [[ -f "$CONFIG" ]]; then
	set -a
	source "$CONFIG"
	set +a
fi

# Environment for headless operation
export QT_QPA_PLATFORM=offscreen
export JACK_NO_AUDIO_RESERVATION=1
export DISPLAY=

# Wait for system services (audio, network) to stabilize
sleep 15

echo "=== SC-OSC autostart $(date) ===" >> "$LOGFILE"
echo "  sclang: $SCLANG" >> "$LOGFILE"

# Verify required files exist
if [[ ! -x "$SCLANG" ]]; then
	echo "ERROR: sclang not executable at $SCLANG" >> "$LOGFILE"
	exit 1
fi

if [[ ! -f "$ANALYZER" ]]; then
	echo "ERROR: analyzer.scd not found at $ANALYZER" >> "$LOGFILE"
	exit 1
fi

# Launch sclang with the analyzer script, logging all output
exec "$SCLANG" "$ANALYZER" >> "$LOGFILE" 2>&1
