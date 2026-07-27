#!/bin/bash
# Hook script for Devin CLI SessionEnd event.
# Sends a final stop notification and cleans up the session_id cache.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

if ! should_use_structured; then
    exit 0
fi

source "$SCRIPT_DIR/build-payload.sh"

# Read hook input from stdin (Devin sends { "reason": "..." })
INPUT=$(cat)

REASON=$(echo "$INPUT" | jq -r '.reason // "session ended"' 2>/dev/null)

# Emit final stop event
BODY=$(build_payload "$INPUT" "stop" \
    --arg summary "$REASON")
"$SCRIPT_DIR/warp-notify.sh" "warp://cli-agent" "$BODY"

# Clean up the session_id cache
_clear_session_id
