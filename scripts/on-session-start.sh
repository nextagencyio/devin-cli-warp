#!/bin/bash
# Hook script for Devin CLI SessionStart event.
# Generates a session_id, caches it for subsequent hooks, and emits a
# structured Warp notification so Warp begins tracking the session.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

if ! should_use_structured; then
    exit 0
fi

if ! command -v jq &>/dev/null; then
    cat << 'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Warp notifications require jq! Install it with: brew install jq (macOS) or apt install jq (Linux)"
  }
}
EOF
    exit 0
fi

source "$SCRIPT_DIR/build-payload.sh"

# Read hook input from stdin (Devin sends { "source": "..." })
INPUT=$(cat)

# Read plugin version from devin-extension.json
PLUGIN_VERSION=$(jq -r '.version // "unknown"' "$SCRIPT_DIR/../devin-extension.json" 2>/dev/null)

# Generate and cache a session_id for this session
SESSION_ID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "devin-$$-$(date +%s)")
_save_session_id "$SESSION_ID"

# Emit structured notification with plugin version so Warp can track it
BODY=$(build_payload "$INPUT" "session_start" \
    --arg plugin_version "$PLUGIN_VERSION")
"$SCRIPT_DIR/warp-notify.sh" "warp://cli-agent" "$BODY"
