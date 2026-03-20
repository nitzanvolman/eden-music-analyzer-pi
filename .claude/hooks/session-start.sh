#!/bin/bash
# SessionStart hook: activate Python 3.12 venv for the session.

cd "$CLAUDE_PROJECT_DIR" || exit 1

# Verify the venv exists
if [ ! -d ".venv" ]; then
  echo "ERROR: .venv directory not found in $CLAUDE_PROJECT_DIR" >&2
  exit 1
fi

# Persist into session via CLAUDE_ENV_FILE (SessionStart-only feature)
if [ -n "$CLAUDE_ENV_FILE" ]; then
  cat >> "$CLAUDE_ENV_FILE" <<EOF
export VIRTUAL_ENV="$CLAUDE_PROJECT_DIR/.venv"
export PATH="$CLAUDE_PROJECT_DIR/.venv/bin:\$PATH"
EOF
fi
