# claude-session-recover

A Claude Code plugin that automatically recovers `--resume` sessions when project directories have been moved or renamed.

## Problem

Claude Code stores session transcripts under `~/.claude/projects/` in directories named after the path-encoded project directory (e.g., `/home/alice/my-tool` becomes `-home-alice-my-tool`). When you move or rename a project directory, `claude --resume SESSION_ID` fails because the session files still live under the old encoded path.

There is no built-in migration. Anthropic has marked this as [NOT_PLANNED](https://github.com/anthropics/claude-code/issues/1516).

## Prior Art

- **[claude-tools](https://github.com/dlond/claude-tools)** — OCaml suite with `claude-mv` for manual session moves between project paths. Preserves UUIDs. Installed via Homebrew/Nix. Manual, after-the-fact — you must know old and new paths.
- **[Migration Guide Gist](https://gist.github.com/gwpl/e0b78a711b4a6b2fc4b594c9b9fa2c4c)** — Comprehensive walkthrough of Claude's session storage architecture and manual `mv` fix.
- **[Rescuing Conversations Blog Post](https://curiouslychase.com/posts/rescuing-your-claude-conversations-when-you-rename-projects/)** — Same manual approach documented for end users.

None of these automatically detect and recover a failed resume.

## Architecture Decision: Why a Hybrid Plugin

### The timing constraint

`SessionStart` hooks fire **after** session resolution. If `--resume SESSION_ID` fails because the session isn't under the current project path, Claude Code errors out before any hook runs. A `SessionStart` hook with matcher `resume` only fires on successful resumes.

| Approach | Solves timing? | Distributable as plugin? | Works with `/resume` TUI? |
|---|---|---|---|
| SessionStart hook only | No | Yes | No |
| Shell wrapper only | Yes | No (manual shell config) | No |
| Standalone CLI only | Yes | No (separate install) | No |
| **Plugin + shell wrapper + hook** | **Yes** | **Yes** | No |

The one inherent limitation across all approaches: none can intercept `/resume` issued inside an already-running TUI session — that's handled internally by Claude Code.

### Recommended: Claude Code Plugin (hybrid)

A plugin that bundles four components:

## Components

### 1. `bin/claude-resume` — Shell Wrapper (primary mechanism)

A shell script that:
1. Intercepts `--resume SESSION_ID` before Claude runs
2. Encodes the current `pwd` to find the expected project directory under `~/.claude/projects/`
3. Checks if `SESSION_ID.jsonl` exists there
4. If not, searches all `~/.claude/projects/*/SESSION_ID.jsonl` for the session under any old path
5. If found, symlinks the session file into the current project's directory
6. `exec`s `claude --resume SESSION_ID` with the path now correct

Symlinks over copies: avoids doubling disk usage, keeps a single source of truth, and if the user renames the directory back the original path still works.

### 2. Setup Command — `/session-recover:setup`

A slash command or skill that:
- Detects the user's shell (bash/zsh/fish)
- Adds an alias (`alias claude-resume='~/.claude/plugins/.../bin/claude-resume'`) or symlinks `bin/claude-resume` into a PATH directory
- Optionally wraps `claude` itself so `claude --resume` transparently uses the recovery logic
- Provides uninstall instructions

### 3. SessionStart Hook (secondary, advisory)

In `hooks/hooks.json` with matcher `resume`:
- Fires after a successful resume
- Inspects the session transcript metadata to detect if the session was originally created under a different project path (by reading the `cwd` field from early messages)
- Outputs `additionalContext` warning Claude that the project directory has changed since the session was created
- Can perform post-hoc cleanup (e.g., updating `cwd` references)

### 4. Recovery Skill — `SKILL.md`

A skill that Claude can use when a user says "I can't resume my session" or "I moved my project":
- Instructs Claude to search `~/.claude/projects/` for the session ID
- Creates the appropriate symlinks using Bash tool calls
- Works as a fallback for users who haven't set up the shell wrapper

## Plugin Structure

```
claude-session-recover/
├── .claude-plugin/
│   └── plugin.json
├── hooks/
│   └── hooks.json
├── scripts/
│   ├── session-recover.sh        # Core recovery logic (shared by wrapper + skill)
│   └── check-session-path.sh     # SessionStart hook script
├── commands/
│   └── setup.md                  # /session-recover:setup slash command
├── skills/
│   └── recover-session/
│       └── SKILL.md              # Recovery skill for in-session use
├── bin/
│   └── claude-resume             # Standalone wrapper script
├── README.md
└── LICENSE
```

## Session Storage Reference

### Path encoding algorithm

1. Take the absolute path of the working directory
2. Replace all non-alphanumeric characters (except `-`) with `-`
3. This becomes the directory name under `~/.claude/projects/`

Examples:
- `/home/alice/code/project` → `-home-alice-code-project`
- `/Users/bob/My Documents/work` → `-Users-bob-My-Documents-work`
- `/Users/bob/GoogleDrive-bob@example.com/project` → `-Users-bob-GoogleDrive-bob-example-com-project`

### Session file format

JSONL files named `{uuid}.jsonl` containing:
- `parentUuid` — links messages in conversation threads
- `sessionId` — unique identifier for the session
- `cwd` — working directory at message time
- `version` — Claude Code version
- `timestamp` — ISO 8601 timestamp

### Resume resolution process

1. Get current directory (`pwd`)
2. Encode path (replace `/` with `-`)
3. Look for `~/.claude/projects/[encoded-path]/`
4. Load all JSONL files in that directory
5. Resume from the matching session

## Key Design Decisions

- **Symlinks over copies** — Single source of truth, no disk bloat, reversible.
- **Plugin as distribution, shell wrapper as execution** — The plugin framework handles install/update/discovery; the wrapper does the actual pre-session interception.
- **SessionStart hook as supplement** — Provides in-session awareness even though it can't do pre-session fixup.
- **Cross-platform** — Must handle macOS, Linux, and optionally WSL. `sed`, `find`, `ln -s` are POSIX.

## Sources

- [claude-tools (dlond)](https://github.com/dlond/claude-tools)
- [Feature Request #1516](https://github.com/anthropics/claude-code/issues/1516)
- [Migration Guide Gist (gwpl)](https://gist.github.com/gwpl/e0b78a711b4a6b2fc4b594c9b9fa2c4c)
- [Rescuing Conversations (curiouslychase)](https://curiouslychase.com/posts/rescuing-your-claude-conversations-when-you-rename-projects/)
- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks)
