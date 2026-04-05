#!/bin/sh
# session-recover.sh — Core recovery logic for claude-session-recover
#
# Usage: session-recover.sh SESSION_ID [CWD]
# Exit codes: 0 = session ready, 1 = not found, 2 = error
#
# Searches ~/.claude/history.jsonl first (fast exact lookup), then
# falls back to glob-searching ~/.claude/projects/*/.
# POSIX-only: no jq, no find, no bash-isms

set -e

SESSION_ID="${1:-}"
CWD="${2:-$(pwd)}"

if [ -z "$SESSION_ID" ]; then
  echo "Usage: session-recover.sh SESSION_ID [CWD]" >&2
  exit 2
fi

CLAUDE_DIR="${HOME}/.claude/projects"

if [ ! -d "$CLAUDE_DIR" ]; then
  echo "error: ${CLAUDE_DIR} does not exist" >&2
  exit 2
fi

# Encode CWD: replace all non-alphanumeric characters (except -) with -
ENCODED_CWD=$(printf '%s' "$CWD" | sed 's|[^a-zA-Z0-9-]|-|g')
TARGET_DIR="${CLAUDE_DIR}/${ENCODED_CWD}"
TARGET_JSONL="${TARGET_DIR}/${SESSION_ID}.jsonl"

# If session already exists at the target path, nothing to do
if [ -e "$TARGET_JSONL" ]; then
  exit 0
fi

# Strategy 1: Look up the session's original project in ~/.claude/history.jsonl
HISTORY_FILE="${HOME}/.claude/history.jsonl"
FOUND_JSONL=""

if [ -f "$HISTORY_FILE" ]; then
  # Extract the project path for this session ID from history (POSIX: grep + sed)
  ORIGINAL_PROJECT=$(grep "\"sessionId\":\"${SESSION_ID}\"" "$HISTORY_FILE" | head -n 1 | sed 's/.*"project":"\([^"]*\)".*/\1/')
  if [ -n "$ORIGINAL_PROJECT" ]; then
    ORIGINAL_ENCODED=$(printf '%s' "$ORIGINAL_PROJECT" | sed 's|[^a-zA-Z0-9-]|-|g')
    CANDIDATE="${CLAUDE_DIR}/${ORIGINAL_ENCODED}/${SESSION_ID}.jsonl"
    if [ -e "$CANDIDATE" ]; then
      FOUND_JSONL="$CANDIDATE"
    fi
  fi
fi

# Strategy 2: Glob-search all project directories as fallback
if [ -z "$FOUND_JSONL" ]; then
  for candidate in "${CLAUDE_DIR}"/*/"${SESSION_ID}.jsonl"; do
    # Guard against unexpanded glob
    [ -e "$candidate" ] || continue
    FOUND_JSONL="$candidate"
    break
  done
fi

if [ -z "$FOUND_JSONL" ]; then
  echo "error: session ${SESSION_ID} not found under ${CLAUDE_DIR}" >&2
  exit 1
fi

FOUND_DIR=$(dirname "$FOUND_JSONL")
FOUND_SESSION_DIR="${FOUND_DIR}/${SESSION_ID}"

# Create target directory if needed
mkdir -p "$TARGET_DIR"

# Symlink the .jsonl file
if [ ! -e "$TARGET_JSONL" ]; then
  ln -s "$FOUND_JSONL" "$TARGET_JSONL"
  echo "linked: ${FOUND_JSONL} -> ${TARGET_JSONL}"
fi

# Symlink the session directory (subagents/, tool-results/) if it exists
TARGET_SESSION_DIR="${TARGET_DIR}/${SESSION_ID}"
if [ -d "$FOUND_SESSION_DIR" ] && [ ! -e "$TARGET_SESSION_DIR" ]; then
  ln -s "$FOUND_SESSION_DIR" "$TARGET_SESSION_DIR"
  echo "linked: ${FOUND_SESSION_DIR} -> ${TARGET_SESSION_DIR}"
fi

exit 0
