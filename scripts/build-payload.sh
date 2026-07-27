#!/bin/bash
# Builds a structured JSON notification payload for warp://cli-agent.
#
# Usage: source this file, then call build_payload with event-specific fields.
#
# Example:
#   source "$(dirname "${BASH_SOURCE[0]}")/build-payload.sh"
#   BODY=$(build_payload "$INPUT" "stop" \
#       --arg query "$QUERY" \
#       --arg response "$RESPONSE")
#
# Devin CLI hooks do NOT provide session_id or cwd in stdin (unlike Gemini/Claude).
# This script synthesizes them:
#   - cwd: from $DEVIN_PROJECT_DIR (set by Devin CLI)
#   - session_id: generated at SessionStart, cached in a temp file keyed by PPID + project.
#                 Subsequent hooks read the cached value. SessionEnd cleans it up.

# The current protocol version this plugin knows how to produce.
PLUGIN_CURRENT_PROTOCOL_VERSION=1

# The agent slug Warp sees in payloads. Must be stable — Warp correlates events by this.
AGENT_SLUG="devin"

# Negotiate the protocol version with Warp.
# Uses min(plugin_current, warp_declared), falling back to 1 if Warp doesn't advertise a version.
negotiate_protocol_version() {
    local warp_version="${WARP_CLI_AGENT_PROTOCOL_VERSION:-1}"
    if [ "$warp_version" -lt "$PLUGIN_CURRENT_PROTOCOL_VERSION" ] 2>/dev/null; then
        echo "$warp_version"
    else
        echo "$PLUGIN_CURRENT_PROTOCOL_VERSION"
    fi
}

# Temp file path for session_id cache, keyed by parent PID + project dir.
# PPID is the devin process itself — stable across all hook invocations within one session.
_session_cache_path() {
    local project_dir="${DEVIN_PROJECT_DIR:-/unknown}"
    local key="${PPID}:$(echo "$project_dir" | md5 -q 2>/dev/null || echo "$project_dir" | md5sum 2>/dev/null | cut -d' ' -f1)"
    local hash
    hash=$(echo "$key" | md5 -q 2>/dev/null || echo "$key" | md5sum 2>/dev/null | cut -d' ' -f1)
    echo "/tmp/devin-warp-session-${hash}"
}

# Get or create a session_id. Called by build_payload.
# If a cache file exists (written by SessionStart), read it. Otherwise generate a new UUID.
_get_session_id() {
    local cache_path
    cache_path=$(_session_cache_path)
    if [ -f "$cache_path" ]; then
        cat "$cache_path" 2>/dev/null
    else
        # No SessionStart seen yet (or cache was cleaned). Generate an ephemeral one.
        uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "devin-$$-$(date +%s)"
    fi
}

# Write a session_id to the cache. Called by on-session-start.sh.
_save_session_id() {
    local session_id="$1"
    local cache_path
    cache_path=$(_session_cache_path)
    echo -n "$session_id" > "$cache_path" 2>/dev/null || true
}

# Remove the session_id cache. Called by on-session-end.sh.
_clear_session_id() {
    local cache_path
    cache_path=$(_session_cache_path)
    rm -f "$cache_path" 2>/dev/null || true
}

build_payload() {
    local input="$1"
    local event="$2"
    shift 2

    local protocol_version
    protocol_version=$(negotiate_protocol_version)

    # Devin doesn't provide session_id or cwd in stdin — synthesize them.
    local session_id cwd project
    session_id=$(_get_session_id)
    cwd="${DEVIN_PROJECT_DIR:-}"
    project=""
    if [ -n "$cwd" ]; then
        project=$(basename "$cwd")
    fi

    # Build the payload: common fields + any extra args passed by the caller.
    # Extra args should be jq flag pairs like: --arg key "value" or --argjson key '{"a":1}'
    jq -nc \
        --argjson v "$protocol_version" \
        --arg agent "$AGENT_SLUG" \
        --arg event "$event" \
        --arg session_id "$session_id" \
        --arg cwd "$cwd" \
        --arg project "$project" \
        "$@" \
        '{v:$v, agent:$agent, event:$event, session_id:$session_id, cwd:$cwd, project:$project} + $ARGS.named'
}
