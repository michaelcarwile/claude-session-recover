---
description: Export one or more Claude session files to a portable archive for backup or transfer to another machine
allowed-tools:
  - Bash
  - Read
---

# Session Export

Export session files to a portable `.tar.gz` archive that can be imported on another machine.

## Instructions

1. **Locate the export script** at `${CLAUDE_PLUGIN_ROOT}/scripts/session-export.sh`. Read it to confirm it exists.

2. **List available session files** under the current project path so the user can choose:
   ```bash
   ENCODED=$(printf '%s' "$(pwd)" | sed 's|[^a-zA-Z0-9-]|-|g')
   ls -lt ~/.claude/projects/${ENCODED}/*.jsonl 2>/dev/null | head -20
   ```

3. **Ask the user** what to export:
   - A specific session ID (or multiple IDs)
   - `latest` — the most recently modified session
   - `all` — every session under the current project

4. **Run the export script**:
   ```bash
   sh "${CLAUDE_PLUGIN_ROOT}/scripts/session-export.sh" [-o OUTPUT_PATH] [SESSION_ID... | latest | all]
   ```
   - If the user doesn't specify an output path, the script defaults to `~/claude-session-export-YYYYMMDD-HHMMSS.tar.gz`
   - The `-o` flag allows a custom output path

5. **Report the result**: Show the archive path and file size:
   ```bash
   ls -lh OUTPUT_PATH
   ```

6. **Explain next steps**: To import on another machine, transfer the archive and run `/session-recover:import`.
