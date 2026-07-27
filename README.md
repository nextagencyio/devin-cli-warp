# Devin CLI + Warp

Community [Warp](https://warp.dev) terminal integration for [Devin CLI](https://cli.devin.ai) — native notifications and session status via the OSC 777 `warp://cli-agent` protocol.

> **Not affiliated with Cognition or Warp.** This is a community adapter modeled after [warpdotdev/gemini-cli-warp](https://github.com/warpdotdev/gemini-cli-warp). Tracked upstream request: [warpdotdev/warp#9375](https://github.com/warpdotdev/warp/issues/9375).

## Features

### Native Notifications

Get Warp notifications when Devin CLI:
- **Completes a task** — stop event fires when Devin finishes its turn
- **Needs your input** — idle prompt when the session is ready for the next message
- **Requests permission** — when Devin wants to run a tool that needs approval

Notifications appear in Warp's notification center and as system notifications, so you can context-switch while Devin works and get alerted when attention is needed.

### Session Status

The adapter keeps Warp informed of Devin's current state by emitting structured events on every session transition:
- **Session started** — a new Devin session begins
- **Prompt submitted** — you sent a prompt, Devin is working
- **Tool completed** — a tool call finished, Devin is back to running
- **Permission needed** — Devin is blocked waiting for approval
- **Session ended** — cleanup and final notification

This powers Warp's inline status indicators for Devin CLI sessions.

## How It Works

Devin CLI fires [lifecycle hooks](https://docs.devin.ai/cli/extensibility/hooks/overview) (JSON on stdin → shell command) at each session transition. This adapter's hook scripts read that JSON, build a structured payload, and emit it to Warp via the OSC 777 escape sequence:

```
ESC ] 777 ; notify ; warp://cli-agent ; {"v":1,"agent":"devin","event":"stop",...} BEL
```

Warp parses the sequence on the pane's tty and routes it into the notification center and session UI.

### Session ID synthesis

Devin CLI hooks don't include a `session_id` in stdin (unlike Gemini/Claude). This adapter generates a UUID at `SessionStart`, caches it in `/tmp/devin-warp-session-<hash>` keyed by the Devin process PID + project directory, and reads it in subsequent hooks. `SessionEnd` cleans up the cache file.

### Working directory

Devin sets the `DEVIN_PROJECT_DIR` environment variable to the project root. The adapter uses this as the `cwd` field in payloads.

## Installation

### Prerequisites

- [Warp](https://warp.dev) terminal (macOS, Linux, or Windows)
- [Devin CLI](https://cli.devin.ai) — v3000.2.17+ (hooks support)
- `jq` for JSON parsing — install with `brew install jq` (macOS) or `apt install jq` (Linux)

### One-line install

```bash
git clone https://github.com/nextagencyio/devin-cli-warp.git
cd devin-cli-warp
./install.sh
```

This installs the hook scripts to `~/.config/devin/warp-scripts/` and merges the hooks config into `~/.config/devin/config.json` with absolute paths.

After installing, **restart any running Devin CLI sessions** for hooks to take effect.

### Verify installation

Run `/hooks` inside Devin CLI to see all loaded hooks and their source files:

```
/hooks
```

You should see 6 hook events: `SessionStart`, `UserPromptSubmit`, `PostToolUse`, `Stop`, `SessionEnd`, `PermissionRequest`.

### Uninstall

```bash
./install.sh --uninstall
```

Removes the scripts and clears the hooks from `~/.config/devin/config.json`.

## Hook Event Mapping

| Devin Hook | Warp Event | Description |
|---|---|---|
| `SessionStart` | `session_start` | New session begins, generates session_id |
| `UserPromptSubmit` | `prompt_submit` | User submits a prompt |
| `PostToolUse` | `tool_complete` | A tool call finished |
| `Stop` | `stop` + `idle_prompt` | Devin finishes its turn |
| `SessionEnd` | `stop` | Session ends, cleans up cache |
| `PermissionRequest` | `permission_request` | Devin needs tool approval |

## Limitations

- **No branded footer/toolbar.** Warp's `CLIAgent` enum only recognizes `claude`, `gemini`, `codex`, and `goose`. Devin sessions get structured notifications and session status, but not the branded agent-mode UI. Adding `CLIAgent::Devin` to Warp is a small upstream Rust change tracked in [#9375](https://github.com/warpdotdev/warp/issues/9375).
- **Session ID is synthetic.** Generated per-session by this adapter, not from Devin internals. Concurrent Devin sessions in the same project directory may share a session_id.
- **No `PreToolUse` notification.** The Warp protocol has no "tool started" event, so only `PostToolUse` (`tool_complete`) is emitted.

## Testing

```bash
./tests/test-hooks.sh
```

Tests validate the payload builder (`build-payload.sh`) and capability gate (`should-use-structured.sh`) by piping mock hook input and checking JSON output.

## Architecture

```
devin-cli-warp/
├── devin-extension.json      # Plugin metadata
├── install.sh                # One-command install/uninstall
├── hooks/
│   └── hooks.v1.json         # Hook config template (paths filled by install.sh)
├── scripts/
│   ├── build-payload.sh      # Shared JSON payload builder (session_id synthesis)
│   ├── should-use-structured.sh  # Warp capability gate
│   ├── warp-notify.sh        # OSC 777 emitter
│   ├── on-session-start.sh   # SessionStart → session_start
│   ├── on-prompt-submit.sh   # UserPromptSubmit → prompt_submit
│   ├── on-post-tool-use.sh   # PostToolUse → tool_complete
│   ├── on-stop.sh            # Stop → stop + idle_prompt
│   ├── on-session-end.sh     # SessionEnd → stop (cleanup)
│   └── on-permission-request.sh  # PermissionRequest → permission_request
└── tests/
    └── test-hooks.sh
```

## Credits

- Adapted from [warpdotdev/gemini-cli-warp](https://github.com/warpdotdev/gemini-cli-warp) (MIT)
- Protocol reference: [reverse-engineering Warp's cli-agent notification protocol](https://yigitkonur.com/reverse-engineering-warp-cli-agent-protocol) by Yiğit Konur
- Devin CLI hooks documentation: [docs.devin.ai/cli/extensibility/hooks](https://docs.devin.ai/cli/extensibility/hooks/overview)

## License

MIT
