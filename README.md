# ai-plan-usage

![Terminal showing usage bars for Claude and Codex 5-hour and 7-day windows](./screenshot.png)

Terminal bars for Claude and Codex plan usage (5-hour, 7-day).

## Requirements

- macOS, `jq`, `curl`
- Claude: `claude` CLI logged in
- Codex: `codex` CLI logged in with ChatGPT (`~/.codex/auth.json`)

## Usage

```sh
./ai-plan-usage.sh --interval=600 --providers=claude,codex
```

| Flag | Default | Description |
|------|---------|-------------|
| `--providers=LIST` | `claude,codex` | Providers to show, in order |
| `--interval=N` | `600` | Seconds between refreshes |
| `--width=N` | `auto` | Bar width; `auto` fits terminal |
| `--full` | off | Print raw JSON |

## Adding a provider

- Add name to `PROVIDERS`
- `fetch_<name>`: print raw JSON, fail with message on stderr
- `rows_<name>`: JSON on stdin → `label<TAB>percent<TAB>reset` rows

## macOS menu bar prototype

Open `agent-usage/agent-usage.xcodeproj` in Xcode, select the **agent-usage**
scheme and **My Mac**, then Run. Requires macOS 14 or newer. It runs without a
Dock icon; click either provider's menu bar item for details, Refresh, launch at
login, and Quit. Each item is 132 points wide, with the short window above the
long window. `—` means unavailable; `…` means loading; `!` means an error (the last
successful values remain visible when available).

The app reads Claude's `Claude Code-credentials` Keychain item and Codex's
`~/.codex/auth.json` (`CODEX_HOME` is honored when present in the app's environment).
macOS may ask for access to the Claude Keychain item on first run. Claude must
already be logged in; expired credentials renew with `claude -p "ok" --model haiku`,
which can consume a small amount of allowance. The CLI is found in `~/.local/bin`,
Homebrew, or `PATH`. For Codex, use `codex login` with a ChatGPT account and a
file-based credential store. Apps launched from Finder do not inherit shell
configuration or shell-only environment variables.

Both providers refresh on launch and every ten minutes. Sleep skips missed ticks;
waking preserves the display until the next scheduled tick. Requests have timeouts,
and failures retain the previous successful reading. Usage stays in memory and
network requests use an ephemeral session. App Sandbox is disabled to support the
existing CLI credentials and Claude renewal process. These usage endpoints are
undocumented and may change.

For launch at login, keep the built app in a stable location such as
`~/Applications`, then enable its toggle. macOS may require approval under System
Settings → General → Login Items. Use a stable signing identity in Xcode to avoid
repeated Keychain prompts across rebuilds.

Build from Terminal without changing your global Xcode selection:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project agent-usage/agent-usage.xcodeproj -scheme agent-usage \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/agent-usage-build CODE_SIGN_IDENTITY=- build
open /tmp/agent-usage-build/Build/Products/Debug/agent-usage.app
```

Run the isolated parser checks (no network or credentials):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  agent-usage/agent-usage/UsageModels.swift tests/UsageParserChecks.swift \
  -o /tmp/agent-usage-parser-checks
/tmp/agent-usage-parser-checks
```

A Debug build launched with `--diagnostics /tmp/agent-usage-preview` exports the
rendered menu bar images and a short status report after its first fetch. This is
opt-in and contains usage percentages and errors, never tokens or API bodies.

Provider SVG marks come from [Simple Icons](https://github.com/simple-icons/simple-icons):
[Claude](https://github.com/simple-icons/simple-icons/blob/develop/icons/claude.svg)
and [OpenAI](https://github.com/simple-icons/simple-icons/blob/15.0.0/icons/openai.svg).
Simple Icons artwork is distributed under CC0; the marks remain their owners'
trademarks.
