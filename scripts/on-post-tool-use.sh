#!/bin/bash
# Hook script for Devin CLI PostToolUse event.
# Sends a structured Warp notification after a tool call completes,
# transitioning the session status from Blocked back to Running.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

if ! should_use_structured; then
    echo '{}'
    exit 0
fi

source "$SCRIPT_DIR/build-payload.sh"

# Read hook input from stdin
# Devin sends: { "tool_name": "...", "tool_input": {...}, "tool_response": { "success": bool, "output": "...", "error": "..." } }
INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

BODY=$(build_payload "$INPUT" "tool_complete" \
    --arg tool_name "$TOOL_NAME")

"$SCRIPT_DIR/warp-notify.sh" "warp://cli-agent" "$BODY"

# Output empty JSON so we don't interfere with the agent
echo '{}'
