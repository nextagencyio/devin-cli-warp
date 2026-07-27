#!/bin/bash
# Hook script for Devin CLI PermissionRequest event.
# Sends a structured Warp notification when Devin needs permission to run a tool,
# so Warp can surface the approval prompt in its notification center.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

if ! should_use_structured; then
    exit 0
fi

source "$SCRIPT_DIR/build-payload.sh"

# Read hook input from stdin
# Devin sends: { "tool_name": "...", "tool_input": {...} }
INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null)
TOOL_INPUT=$(echo "$INPUT" | jq -c '.tool_input // {}' 2>/dev/null)
[ -z "$TOOL_INPUT" ] && TOOL_INPUT='{}'

# Build a human-readable summary
TOOL_PREVIEW=$(echo "$INPUT" | jq -r '
    .tool_input | if .command then .command
    elif .file_path then .file_path
    elif .path then .path
    elif .pattern then .pattern
    else "" end
' 2>/dev/null)

SUMMARY="Wants to run $TOOL_NAME"
if [ -n "$TOOL_PREVIEW" ] && [ "$TOOL_PREVIEW" != "null" ]; then
    if [ ${#TOOL_PREVIEW} -gt 120 ]; then
        TOOL_PREVIEW="${TOOL_PREVIEW:0:117}..."
    fi
    SUMMARY="$SUMMARY: $TOOL_PREVIEW"
fi

BODY=$(build_payload "$INPUT" "permission_request" \
    --arg summary "$SUMMARY" \
    --arg tool_name "$TOOL_NAME" \
    --argjson tool_input "$TOOL_INPUT")

"$SCRIPT_DIR/warp-notify.sh" "warp://cli-agent" "$BODY"
