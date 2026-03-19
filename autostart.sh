#!/usr/bin/env bash
# autostart.sh — Launch SC-OSC analyzer headless on boot
# Usage: add to crontab with @reboot /home/pi/sc-osc/autostart.sh
set -euo pipefail

LOGFILE="/tmp/sc-osc.log"
SC_OSC_DIR="$HOME/sc-osc"
SC_STANDALONE_DIR="$HOME/supercolliderStandaloneRPI64"
ANALYZER="$SC_OSC_DIR/analyzer.scd"
CONFIG="$SC_OSC_DIR/config.env"

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

# Verify required files exist
if [[ ! -x "$SC_STANDALONE_DIR/sclang" ]]; then
	echo "ERROR: sclang not found at $SC_STANDALONE_DIR/sclang" >> "$LOGFILE"
	exit 1
fi

if [[ ! -f "$ANALYZER" ]]; then
	echo "ERROR: analyzer.scd not found at $ANALYZER" >> "$LOGFILE"
	exit 1
fi

# Launch sclang with the analyzer script, logging all output
exec "$SC_STANDALONE_DIR/sclang" "$ANALYZER" >> "$LOGFILE" 2>&1
