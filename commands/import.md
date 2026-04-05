---
description: Import Claude session files from a previously exported archive into the current project
allowed-tools:
  - Bash
  - Read
---

# Session Import

Import session files from a `.tar.gz` archive created by `/session-recover:export`.

## Instructions

1. **Locate the import script** at `${CLAUDE_PLUGIN_ROOT}/scripts/session-import.sh`. Read it to confirm it exists.

2. **Find the archive**. If the user didn't specify a path, look for recent export archives:
   ```bash
   ls -lt ~/claude-session-export-*.tar.gz 2>/dev/null | head -5
   ls -lt ./claude-session-export-*.tar.gz 2>/dev/null | head -5
   ```
   Ask the user to confirm which archive to import.

3. **Preview the archive contents**:
   ```bash
   tar tzf ARCHIVE_PATH | head -30
   ```

4. **Check for existing session files** that would conflict:
   ```bash
   ENCODED=$(printf '%s' "$(pwd)" | sed 's|[^a-zA-Z0-9-]|-|g')
   # Extract session IDs from archive and check if they exist locally
   tar tzf ARCHIVE_PATH | grep '\.jsonl$' | sed 's|.*/||;s|\.jsonl$||' | while read SID; do
     [ -e ~/.claude/projects/${ENCODED}/${SID}.jsonl ] && echo "conflict: ${SID}"
   done
   ```
   If conflicts exist, ask the user whether to skip or overwrite (`--force`).

5. **Run the import script**:
   ```bash
   sh "${CLAUDE_PLUGIN_ROOT}/scripts/session-import.sh" [-f|--force] ARCHIVE_PATH
   ```

6. **Report the result**: Show how many session files were imported and skipped.

7. **Explain next steps**: The imported session can be resumed with `claude --resume SESSION_ID`.
