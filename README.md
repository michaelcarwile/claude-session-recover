# claude-session-recover

A Claude Code plugin that automatically recovers sessions after a project directory is moved or renamed.

## The Problem

Claude Code stores session transcripts under `~/.claude/projects/` in directories named after path-encoded project directories (non-alphanumeric characters replaced with `-`). When you move or rename a project, `claude --resume SESSION_ID` fails because the session files still live under the old encoded path.

Anthropic has marked this as [NOT_PLANNED](https://github.com/anthropics/claude-code/issues/1983).

## How It Works

Each session has two artifacts — a `{SESSION_ID}.jsonl` transcript file and a `{SESSION_ID}/` directory (containing `subagents/` and `tool-results/`). This plugin finds them under the old path and copies them to the new expected path. It checks `~/.claude/history.jsonl` first for a fast lookup, then falls back to searching all project directories.

**Three layers of recovery:**

1. **Shell wrapper** (recommended) — A `claude()` shell function intercepts `--resume` before Claude launches and recovers the session automatically. Install via `/session-recover:setup`.

2. **SessionStart hook** — After a successful resume, detects if the original working directory differs from the current one and adds advisory context to the session.

3. **Recovery skill** — If all else fails, ask Claude: *"I can't resume my session"* and it will walk you through manual recovery.

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/michaelcarwile/claude-session-recover/main/install.sh | sh
```

This sets up a local marketplace (if you don't have one), registers the plugin, and installs it.

### Try without installing

```bash
git clone https://github.com/michaelcarwile/claude-session-recover.git
claude --plugin-dir ./claude-session-recover
```

## Quick Start

After installing the plugin, run the setup command in a Claude session:

```
/session-recover:setup
```

This installs a shell function that automatically recovers sessions when you use `--resume`.

## Standalone Wrapper

Alternatively, use the standalone `claude-resume` wrapper without installing the plugin at all:

```bash
# Add to your PATH
export PATH="/path/to/claude-session-recover/bin:$PATH"

# Use instead of claude
claude-resume --resume SESSION_ID
```

## Manual Recovery

If you prefer to recover a session manually:

```bash
# Find the session
ls ~/.claude/projects/*/${SESSION_ID}.jsonl

# Encode your current directory
ENCODED=$(printf '%s' "$(pwd)" | sed 's|[^a-zA-Z0-9-]|-|g')

# Copy session files
TARGET=~/.claude/projects/${ENCODED}
mkdir -p "$TARGET"
cp /path/to/old/${SESSION_ID}.jsonl "$TARGET/${SESSION_ID}.jsonl"
cp -r /path/to/old/${SESSION_ID} "$TARGET/${SESSION_ID}"
```

## Uninstall

```bash
claude plugin uninstall claude-session-recover@local-marketplace
```

If you ran `/session-recover:setup`, also remove the `claude()` function from your shell rc file (look for the `# claude-session-recover` comment).

## Limitations

- Cannot intercept the `/resume` TUI command inside an active Claude session — only `claude --resume` from the shell
- The SessionStart hook requires `jq` for JSON parsing (degrades gracefully to a no-op without it)
- Recovery creates copies, so recovered sessions use additional disk space

## License

MIT
