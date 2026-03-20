#!/usr/bin/env bash
# autostart.sh — Launch SC-OSC analyzer headless on boot
# Usage: add to crontab with @reboot ~/sc-osc/autostart.sh
set -euo pipefail

SC_OSC_DIR="$HOME/sc-osc"
LOG_DIR="$SC_OSC_DIR/logs"
LOGFILE="$LOG_DIR/analyzer.log"
MAX_LOG_SIZE=5242880  # 5 MB
MAX_LOG_FILES=3
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

# --- Log rotation ---
mkdir -p "$LOG_DIR"
if [[ -f "$LOGFILE" ]]; then
	LOG_SIZE=$(stat -c%s "$LOGFILE" 2>/dev/null || stat -f%z "$LOGFILE" 2>/dev/null || echo 0)
	if [[ "$LOG_SIZE" -gt "$MAX_LOG_SIZE" ]]; then
		# Rotate: .3 -> delete, .2 -> .3, .1 -> .2, current -> .1
		for i in $(seq $((MAX_LOG_FILES - 1)) -1 1); do
			[[ -f "$LOGFILE.$i" ]] && mv "$LOGFILE.$i" "$LOGFILE.$((i + 1))"
		done
		mv "$LOGFILE" "$LOGFILE.1"
		echo "=== Log rotated $(date) ===" > "$LOGFILE"
	fi
fi

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
