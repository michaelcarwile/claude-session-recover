---
name: recover-session
description: Recover a Claude Code session that can't be resumed after a project directory was moved or renamed. Triggers on "can't resume session", "session not found", "moved my project", "renamed my project", "resume failed", "lost session", "recover session".
---

# Recover a Lost Session

When a project directory is moved or renamed, Claude Code can't find existing sessions because they're stored under the old encoded path in `~/.claude/projects/`.

## Steps

1. **Get the session ID** from the user. If they don't know it, list recent sessions:
   ```bash
   ls -lt ~/.claude/projects/*//*.jsonl | head -20
   ```

2. **Encode the current working directory** by replacing non-alphanumeric characters with `-`:
   ```bash
   ENCODED=$(printf '%s' "$(pwd)" | sed 's|[^a-zA-Z0-9-]|-|g')
   ```

3. **Check if the session already exists** at the expected path:
   ```bash
   ls ~/.claude/projects/${ENCODED}/${SESSION_ID}.jsonl
   ```

4. **If not found, search all project directories:**
   ```bash
   ls ~/.claude/projects/*/${SESSION_ID}.jsonl
   ```

5. **Copy files** for both the `.jsonl` file and the session directory:
   ```bash
   TARGET_DIR=~/.claude/projects/${ENCODED}
   mkdir -p "$TARGET_DIR"

   # Copy the transcript file
   cp /path/to/found/${SESSION_ID}.jsonl "$TARGET_DIR/${SESSION_ID}.jsonl"

   # Copy the session directory (contains subagents/ and tool-results/)
   cp -r /path/to/found/${SESSION_ID} "$TARGET_DIR/${SESSION_ID}"
   ```

6. **Verify** the session can now be resumed:
   ```bash
   ls -la "$TARGET_DIR/${SESSION_ID}.jsonl"
   ls -la "$TARGET_DIR/${SESSION_ID}/"
   ```

7. **Suggest running `/session-recover:setup`** to install the shell wrapper so future resumes are handled automatically.

## Important Notes

- Each session has **two** artifacts: a `{SESSION_ID}.jsonl` file and a `{SESSION_ID}/` directory. Both must be copied.
- The session directory contains `subagents/` and `tool-results/` which are needed for full session context.
- This creates copies of the session files at the new path. The originals remain at the old path.
