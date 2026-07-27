#!/bin/bash
# install.sh — installs the Devin CLI + Warp integration into ~/.config/devin/
#
# What it does:
#   1. Copies the hook scripts to ~/.config/devin/warp-scripts/
#   2. Merges the hooks config into ~/.config/devin/config.json (under "hooks")
#      with absolute paths to the installed scripts
#   3. Verifies jq is available (required dependency)
#
# Usage:
#   ./install.sh              # install
#   ./install.sh --uninstall  # remove the hooks and scripts
#
# After installing, restart any running Devin CLI sessions for hooks to take effect.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVIN_CONFIG_DIR="${HOME}/.config/devin"
DEVIN_CONFIG_FILE="${DEVIN_CONFIG_DIR}/config.json"
SCRIPTS_INSTALL_DIR="${DEVIN_CONFIG_DIR}/warp-scripts"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}✓${NC} $1"; }
warn()  { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }

# --- Check dependencies ---
if ! command -v jq &>/dev/null; then
    error "jq is required. Install it with: brew install jq (macOS) or apt install jq (Linux)"
    exit 1
fi

uninstall() {
    echo "Uninstalling Devin CLI + Warp integration..."

    # Remove installed scripts
    if [ -d "$SCRIPTS_INSTALL_DIR" ]; then
        rm -rf "$SCRIPTS_INSTALL_DIR"
        info "Removed scripts from $SCRIPTS_INSTALL_DIR"
    fi

    # Remove hooks from config.json
    if [ -f "$DEVIN_CONFIG_FILE" ]; then
        local tmp
        tmp=$(mktemp)
        if jq 'del(.hooks)' "$DEVIN_CONFIG_FILE" > "$tmp" 2>/dev/null; then
            # Only overwrite if there are other keys remaining; otherwise remove the file
            local remaining_keys
            remaining_keys=$(jq 'keys | length' "$tmp" 2>/dev/null)
            if [ "$remaining_keys" -gt 0 ]; then
                mv "$tmp" "$DEVIN_CONFIG_FILE"
                info "Removed hooks from $DEVIN_CONFIG_FILE"
            else
                rm -f "$tmp" "$DEVIN_CONFIG_FILE"
                info "Removed empty $DEVIN_CONFIG_FILE"
            fi
        else
            rm -f "$tmp"
            warn "Could not parse $DEVIN_CONFIG_FILE — leaving it untouched"
        fi
    fi

    # Clean up any stale session cache files
    rm -f /tmp/devin-warp-session-* 2>/dev/null || true

    echo ""
    info "Uninstall complete. Restart any running Devin CLI sessions."
    exit 0
}

# --- Parse args ---
if [ "${1:-}" = "--uninstall" ] || [ "${1:-}" = "-u" ]; then
    uninstall
fi

# --- Install ---
echo "Installing Devin CLI + Warp integration..."
echo ""

# 1. Create config directory
mkdir -p "$DEVIN_CONFIG_DIR"

# 2. Copy scripts
mkdir -p "$SCRIPTS_INSTALL_DIR"
cp "$SCRIPT_DIR"/scripts/*.sh "$SCRIPTS_INSTALL_DIR/"
chmod +x "$SCRIPTS_INSTALL_DIR"/*.sh
info "Installed scripts to $SCRIPTS_INSTALL_DIR"

# 3. Build hooks config with absolute paths
HOOKS_JSON=$(jq -r \
    --arg dir "$SCRIPTS_INSTALL_DIR" \
    'walk(if type == "string" and . == "__SCRIPTS_DIR__/on-session-start.sh" then ($dir + "/on-session-start.sh")
          elif type == "string" and . == "__SCRIPTS_DIR__/on-prompt-submit.sh" then ($dir + "/on-prompt-submit.sh")
          elif type == "string" and . == "__SCRIPTS_DIR__/on-post-tool-use.sh" then ($dir + "/on-post-tool-use.sh")
          elif type == "string" and . == "__SCRIPTS_DIR__/on-stop.sh" then ($dir + "/on-stop.sh")
          elif type == "string" and . == "__SCRIPTS_DIR__/on-session-end.sh" then ($dir + "/on-session-end.sh")
          elif type == "string" and . == "__SCRIPTS_DIR__/on-permission-request.sh" then ($dir + "/on-permission-request.sh")
          else . end)' \
    "$SCRIPT_DIR/hooks/hooks.v1.json")

# 4. Merge into config.json
if [ -f "$DEVIN_CONFIG_FILE" ]; then
    # Merge hooks into existing config, preserving other keys
    EXISTING=$(cat "$DEVIN_CONFIG_FILE")
    MERGED=$(echo "$EXISTING" | jq --argjson hooks "$HOOKS_JSON" '.hooks = $hooks')
    echo "$MERGED" > "$DEVIN_CONFIG_FILE"
    info "Merged hooks into existing $DEVIN_CONFIG_FILE"
else
    # Create new config with just hooks
    echo "{\"hooks\": $HOOKS_JSON}" | jq '.' > "$DEVIN_CONFIG_FILE"
    info "Created $DEVIN_CONFIG_FILE"
fi

# 5. Verify
echo ""
echo "Verification:"
if [ -f "$DEVIN_CONFIG_FILE" ]; then
    HOOK_COUNT=$(jq '.hooks | keys | length' "$DEVIN_CONFIG_FILE" 2>/dev/null)
    info "Config has $HOOK_COUNT hook event(s) registered"
fi

SCRIPT_COUNT=$(ls "$SCRIPTS_INSTALL_DIR"/*.sh 2>/dev/null | wc -l | tr -d ' ')
info "$SCRIPT_COUNT script(s) installed in $SCRIPTS_INSTALL_DIR"

echo ""
info "Install complete!"
echo ""
echo "Next steps:"
echo "  1. Restart any running Devin CLI sessions"
echo "  2. Run 'devin' inside Warp — you should see notifications in Warp's sidebar"
echo "  3. Verify hooks are loaded with the /hooks command in Devin CLI"
echo ""
echo "To uninstall: ./install.sh --uninstall"
