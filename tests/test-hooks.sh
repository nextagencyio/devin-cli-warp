#!/bin/bash
# Tests for the Devin CLI + Warp integration hook scripts.
#
# Validates that build-payload.sh produces correctly structured JSON payloads
# and that should-use-structured.sh gates correctly.
#
# Usage: ./tests/test-hooks.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
source "$SCRIPT_DIR/build-payload.sh"

PASSED=0
FAILED=0

# --- Test helpers ---

assert_eq() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  ✓ $test_name"
        PASSED=$((PASSED + 1))
    else
        echo "  ✗ $test_name"
        echo "    expected: $expected"
        echo "    actual:   $actual"
        FAILED=$((FAILED + 1))
    fi
}

assert_json_field() {
    local test_name="$1"
    local json="$2"
    local field="$3"
    local expected="$4"
    local actual
    actual=$(echo "$json" | jq -r "$field" 2>/dev/null)
    assert_eq "$test_name" "$expected" "$actual"
}

# --- Tests ---

echo "=== build-payload.sh ==="

echo ""
echo "--- Common fields (Devin synthesizes session_id + uses DEVIN_PROJECT_DIR) ---"
export DEVIN_PROJECT_DIR="/Users/alice/my-project"
PAYLOAD=$(build_payload '{}' "stop")
assert_json_field "v is 1" "$PAYLOAD" ".v" "1"
assert_json_field "agent is devin" "$PAYLOAD" ".agent" "devin"
assert_json_field "event is stop" "$PAYLOAD" ".event" "stop"
# session_id should be non-empty — check it's not the empty string
SESSION_ID=$(echo "$PAYLOAD" | jq -r '.session_id')
if [ -n "$SESSION_ID" ]; then
    echo "  ✓ session_id is synthesized (non-empty)"
    PASSED=$((PASSED + 1))
else
    echo "  ✗ session_id is synthesized (non-empty)"
    echo "    expected: non-empty string"
    echo "    actual:   empty"
    FAILED=$((FAILED + 1))
fi
assert_json_field "cwd from DEVIN_PROJECT_DIR" "$PAYLOAD" ".cwd" "/Users/alice/my-project"
assert_json_field "project is basename of cwd" "$PAYLOAD" ".project" "my-project"

echo ""
echo "--- Common fields with no DEVIN_PROJECT_DIR ---"
unset DEVIN_PROJECT_DIR
PAYLOAD=$(build_payload '{}' "stop")
assert_json_field "empty cwd when no DEVIN_PROJECT_DIR" "$PAYLOAD" ".cwd" ""
assert_json_field "empty project when no cwd" "$PAYLOAD" ".project" ""

echo ""
echo "--- Extra args are merged ---"
export DEVIN_PROJECT_DIR="/tmp/proj"
PAYLOAD=$(build_payload '{}' "stop" \
    --arg query "hello" \
    --arg response "world")
assert_json_field "query merged" "$PAYLOAD" ".query" "hello"
assert_json_field "response merged" "$PAYLOAD" ".response" "world"
assert_json_field "common fields still present" "$PAYLOAD" ".cwd" "/tmp/proj"

echo ""
echo "--- Stop event ---"
PAYLOAD=$(build_payload '{}' "stop" \
    --arg query "write a haiku" \
    --arg response "Code flows like water, through silicon pathways bright")
assert_json_field "event is stop" "$PAYLOAD" ".event" "stop"
assert_json_field "query present" "$PAYLOAD" ".query" "write a haiku"
assert_json_field "response present" "$PAYLOAD" ".response" "Code flows like water, through silicon pathways bright"

echo ""
echo "--- Permission request event ---"
PAYLOAD=$(build_payload '{}' "permission_request" \
    --arg summary "Wants to run exec: rm -rf /tmp" \
    --arg tool_name "exec" \
    --argjson tool_input '{"command":"rm -rf /tmp"}')
assert_json_field "event is permission_request" "$PAYLOAD" ".event" "permission_request"
assert_json_field "summary present" "$PAYLOAD" ".summary" "Wants to run exec: rm -rf /tmp"
assert_json_field "tool_name present" "$PAYLOAD" ".tool_name" "exec"
assert_json_field "tool_input.command present" "$PAYLOAD" ".tool_input.command" "rm -rf /tmp"

echo ""
echo "--- Session start event with plugin_version ---"
PAYLOAD=$(build_payload '{}' "session_start" \
    --arg plugin_version "1.0.0")
assert_json_field "event is session_start" "$PAYLOAD" ".event" "session_start"
assert_json_field "plugin_version present" "$PAYLOAD" ".plugin_version" "1.0.0"

echo ""
echo "--- JSON special characters in values ---"
PAYLOAD=$(build_payload '{}' "stop" \
    --arg query 'what does "hello world" mean?' \
    --arg response 'It means greeting. Use: printf("hello")')
assert_json_field "quotes in query preserved" "$PAYLOAD" ".query" 'what does "hello world" mean?'
assert_json_field "parens in response preserved" "$PAYLOAD" ".response" 'It means greeting. Use: printf("hello")'

echo ""
echo "--- Protocol version negotiation ---"

# Default: no env var set → falls back to plugin max (1)
unset WARP_CLI_AGENT_PROTOCOL_VERSION
PAYLOAD=$(build_payload '{}' "stop")
assert_json_field "defaults to v1 when env var absent" "$PAYLOAD" ".v" "1"

# Warp declares v1 → use 1
export WARP_CLI_AGENT_PROTOCOL_VERSION=1
PAYLOAD=$(build_payload '{}' "stop")
assert_json_field "v1 when warp declares 1" "$PAYLOAD" ".v" "1"

# Warp declares a higher version than the plugin knows → capped to plugin current
export WARP_CLI_AGENT_PROTOCOL_VERSION=99
PAYLOAD=$(build_payload '{}' "stop")
assert_json_field "capped to plugin current when warp is ahead" "$PAYLOAD" ".v" "1"

# Warp declares a lower version than the plugin knows → use warp's version
PLUGIN_CURRENT_PROTOCOL_VERSION=5
export WARP_CLI_AGENT_PROTOCOL_VERSION=3
PAYLOAD=$(build_payload '{}' "stop")
assert_json_field "uses warp version when plugin is ahead" "$PAYLOAD" ".v" "3"
PLUGIN_CURRENT_PROTOCOL_VERSION=1

# Clean up
unset WARP_CLI_AGENT_PROTOCOL_VERSION

echo ""
echo "--- Session ID caching ---"

# Save a session_id, then verify build_payload reads it back
export DEVIN_PROJECT_DIR="/tmp/test-cache-dir"
TEST_SESSION_ID="test-uuid-1234-abcd"
_save_session_id "$TEST_SESSION_ID"
PAYLOAD=$(build_payload '{}' "stop")
assert_json_field "session_id read from cache" "$PAYLOAD" ".session_id" "$TEST_SESSION_ID"

# Clear it and verify a new one is generated
_clear_session_id
PAYLOAD=$(build_payload '{}' "stop")
CACHED_ID=$(echo "$PAYLOAD" | jq -r '.session_id')
if [ -n "$CACHED_ID" ] && [ "$CACHED_ID" != "$TEST_SESSION_ID" ]; then
    echo "  ✓ new session_id generated after cache cleared"
    PASSED=$((PASSED + 1))
else
    echo "  ✗ new session_id generated after cache cleared"
    echo "    expected: non-empty string != $TEST_SESSION_ID"
    echo "    actual:   $CACHED_ID"
    FAILED=$((FAILED + 1))
fi

echo ""
echo "=== should-use-structured.sh ==="

source "$SCRIPT_DIR/should-use-structured.sh"

echo ""
echo "--- No protocol version → legacy ---"
unset WARP_CLI_AGENT_PROTOCOL_VERSION
unset WARP_CLIENT_VERSION
should_use_structured
assert_eq "no protocol version returns false" "1" "$?"

echo ""
echo "--- Protocol set, no client version → legacy ---"
export WARP_CLI_AGENT_PROTOCOL_VERSION=1
unset WARP_CLIENT_VERSION
should_use_structured
assert_eq "missing WARP_CLIENT_VERSION returns false" "1" "$?"

echo ""
echo "--- Protocol set, dev version → always structured (dev was never broken) ---"
export WARP_CLI_AGENT_PROTOCOL_VERSION=1
export WARP_CLIENT_VERSION="v0.2026.03.30.08.43.dev_00"
should_use_structured
assert_eq "dev version returns true" "0" "$?"

echo ""
echo "--- Protocol set, broken stable version → legacy ---"
export WARP_CLIENT_VERSION="v0.2026.03.25.08.24.stable_05"
should_use_structured
assert_eq "exact broken stable version returns false" "1" "$?"

echo ""
echo "--- Protocol set, newer stable version → structured ---"
export WARP_CLIENT_VERSION="v0.2026.04.01.08.00.stable_00"
should_use_structured
assert_eq "newer stable version returns true" "0" "$?"

echo ""
echo "--- Protocol set, broken preview version → legacy ---"
export WARP_CLIENT_VERSION="v0.2026.03.25.08.24.preview_05"
should_use_structured
assert_eq "exact broken preview version returns false" "1" "$?"

echo ""
echo "--- Protocol set, newer preview version → structured ---"
export WARP_CLIENT_VERSION="v0.2026.04.01.08.00.preview_00"
should_use_structured
assert_eq "newer preview version returns true" "0" "$?"

# Clean up
unset WARP_CLI_AGENT_PROTOCOL_VERSION
unset WARP_CLIENT_VERSION
unset DEVIN_PROJECT_DIR

# --- Routing tests ---
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"

echo ""
echo "=== Routing ==="

echo ""
echo "--- Hooks exit silently without protocol version ---"

for HOOK in on-prompt-submit.sh on-post-tool-use.sh on-stop.sh on-session-start.sh on-session-end.sh on-permission-request.sh; do
    echo '{}' | bash "$HOOK_DIR/$HOOK" 2>/dev/null
    assert_eq "$HOOK exits 0 without protocol version" "0" "$?"
done

# --- Summary ---

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
