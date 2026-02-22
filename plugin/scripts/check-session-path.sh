#!/bin/sh
# check-session-path.sh — SessionStart hook for claude-session-recover
#
# Reads hook input from stdin (JSON with session_id, cwd, transcript_path).
# Compares the original session cwd to the current cwd.
# If different, outputs advisory context about the path change.
#
# Requires jq. Becomes a silent no-op if jq is not available.

# jq is required for JSON parsing
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# Read hook input from stdin
INPUT=$(cat)

TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')
CURRENT_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')

# If no transcript path or no current cwd, nothing to do
if [ -z "$TRANSCRIPT_PATH" ] || [ -z "$CURRENT_CWD" ]; then
  exit 0
fi

# If transcript doesn't exist, nothing to do
if [ ! -f "$TRANSCRIPT_PATH" ]; then
  exit 0
fi

# Read the first 20 lines, find the first user message, extract its cwd
# Uses jq to filter for type=user and grab the cwd from the first match
ORIGINAL_CWD=$(head -n 20 "$TRANSCRIPT_PATH" | jq -r 'select(.type == "user") | .cwd // empty' 2>/dev/null | head -n 1)

# If we couldn't determine the original cwd, nothing to report
if [ -z "$ORIGINAL_CWD" ]; then
  exit 0
fi

# Compare paths
if [ "$ORIGINAL_CWD" != "$CURRENT_CWD" ]; then
  # Output advisory context (use jq to safely encode paths in JSON)
  jq -n --arg orig "$ORIGINAL_CWD" --arg curr "$CURRENT_CWD" \
    '{hookSpecificOutput:{additionalContext:("Note: This session was originally started in " + $orig + " but is now being resumed in " + $curr + ". File paths referenced in earlier messages may need adjustment.")}}'
fi

exit 0
