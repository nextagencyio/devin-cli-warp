#!/bin/bash
# Hook script for Devin CLI Stop event.
# Sends a structured Warp notification when Devin completes a turn,
# followed by an idle_prompt so Warp shows the session is ready for input.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

if ! should_use_structured; then
    echo '{}'
    exit 0
fi

source "$SCRIPT_DIR/build-payload.sh"

# Read hook input from stdin (Devin sends { "stop_hook_active": bool })
INPUT=$(cat)

# Skip if a stop hook is already active (prevents double-notification on retries)
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    echo '{}'
    exit 0
fi

# Emit stop event
BODY=$(build_payload "$INPUT" "stop")
"$SCRIPT_DIR/warp-notify.sh" "warp://cli-agent" "$BODY"

# Emit idle_prompt so Warp transitions to "ready for input" state
BODY=$(build_payload "$INPUT" "idle_prompt")
"$SCRIPT_DIR/warp-notify.sh" "warp://cli-agent" "$BODY"

# Output empty JSON so we don't interfere with the agent
echo '{}'
