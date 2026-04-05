# Export/Import Feature for claude-session-recover

## Context

Users need to transfer a Claude Code session between machines (e.g., desktop to laptop, CI to local). Currently the plugin only recovers a session after a directory move on the same machine. This adds portable archive-based export/import.

Also: move `claude-session-recover-spec.md` to `context/` and fix any path refs.

## Implementation

### Step 0: Housekeeping
- Create `context/` directory
- `git mv claude-session-recover-spec.md context/`
- Update any references (README, etc.) to the new path

### Step 1: `scripts/session-export.sh`
- POSIX shell, same patterns as `session-recover.sh`
- **Args**: `session-export.sh [-o OUTPUT] [SESSION_ID... | latest | all]`
- **Exit codes**: 0=success, 1=not found, 2=error
- **Selectors**: explicit ID(s), `latest` (newest by mtime), `all` (every session under current project)
- Searches current project dir first, falls back to all project dirs (same two-stage lookup)
- Stages files in `mktemp -d`, creates tar.gz with structure:
  ```
  claude-session-export/
    manifest.json       # {version, exportDate, sourceProject, sessionCount}
    session/            # .jsonl files + session directories
    history.jsonl       # filtered entries from ~/.claude/history.jsonl
  ```
- Default output: `~/claude-session-export-YYYYMMDD-HHMMSS.tar.gz`

### Step 2: `scripts/session-import.sh`
- **Args**: `session-import.sh [-f|--force] ARCHIVE [CWD]`
- Extracts to `mktemp -d`, validates structure (`session/` dir must exist)
- Copies `.jsonl` + session dir(s) to `~/.claude/projects/[ENCODED_CWD]/`
- **Skip existing** by default; `--force` overwrites
- Merges history entries: appends to `~/.claude/history.jsonl`, rewrites `project` field to current CWD, deduplicates by sessionId

### Step 3: Tests (append to `tests/run-tests.sh`)
Key cases for export:
- Single session, multiple session IDs, `latest`, `all`
- Includes history metadata
- Session not found (exit 1), no args (exit 2)
- `.jsonl`-only session (no session directory)
- Custom `-o` output path

Key cases for import:
- Valid archive import
- Skip existing session (default)
- `--force` overwrites
- History merge + dedup + project field rewrite
- Invalid/missing archive (exit 1/2)
- Round-trip: export then import, verify content identical

### Step 4: Commands
- `commands/export.md` — `/session-recover:export` slash command
  - Lists available session files, asks user what to export
  - Runs export script, reports archive path + size
  - Allowed tools: Bash, Read
- `commands/import.md` — `/session-recover:import` slash command
  - Auto-detects `claude-session-export-*.tar.gz` in cwd/home or asks for path
  - Previews contents, checks for conflict, runs import
  - Allowed tools: Bash, Read

### Step 5: Docs
- Update `README.md` with export/import section
- Update `context/claude-session-recover-spec.md` with new components

## Key files
- `scripts/session-recover.sh` — pattern reference (path encoding, exit codes, lookup strategy)
- `tests/run-tests.sh` — test framework (sandbox/cleanup, assert helpers)
- `commands/setup.md` — command frontmatter template

## Verification
1. `sh tests/run-tests.sh` — all tests pass
2. Manual: export a real session, import it to a different project path, verify `claude --resume` works
3. Reinstall plugin and verify commands appear
