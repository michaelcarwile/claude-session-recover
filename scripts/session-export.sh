#!/bin/sh
# session-export.sh — Export session files to a portable archive
#
# Usage: session-export.sh [-o OUTPUT] [-C CWD] [SESSION_ID... | latest | all]
# Exit codes: 0 = success, 1 = not found, 2 = error
#
# Bundles one or more session .jsonl files (and their session directories)
# into a tar.gz archive that can be imported on another machine.
# POSIX-only: no jq, no bash-isms

set -e

# ── Argument parsing ────────────────────────────────────────────────

OUTPUT=""
CWD=""
SELECTORS=""

while [ $# -gt 0 ]; do
  case "$1" in
    -o)
      shift
      OUTPUT="${1:-}"
      if [ -z "$OUTPUT" ]; then
        echo "error: -o requires an output path" >&2
        exit 2
      fi
      ;;
    -o*)
      OUTPUT="${1#-o}"
      ;;
    -C)
      shift
      CWD="${1:-}"
      ;;
    *)
      SELECTORS="$SELECTORS $1"
      ;;
  esac
  shift
done

# Trim leading space
SELECTORS=$(printf '%s' "$SELECTORS" | sed 's/^ //')

if [ -z "$SELECTORS" ]; then
  echo "Usage: session-export.sh [-o OUTPUT] [SESSION_ID... | latest | all]" >&2
  exit 2
fi

# ── Environment ─────────────────────────────────────────────────────

CWD="${CWD:-$(pwd)}"
CLAUDE_DIR="${HOME}/.claude/projects"

if [ ! -d "$CLAUDE_DIR" ]; then
  echo "error: ${CLAUDE_DIR} does not exist" >&2
  exit 2
fi

ENCODED_CWD=$(printf '%s' "$CWD" | sed 's|[^a-zA-Z0-9-]|-|g')
PROJECT_DIR="${CLAUDE_DIR}/${ENCODED_CWD}"

# ── Resolve selectors to session IDs ────────────────────────────────

SESSION_IDS=""

case "$SELECTORS" in
  all)
    if [ ! -d "$PROJECT_DIR" ]; then
      echo "error: no session found under ${PROJECT_DIR}" >&2
      exit 1
    fi
    for f in "$PROJECT_DIR"/*.jsonl; do
      [ -e "$f" ] || continue
      sid=$(basename "$f" .jsonl)
      SESSION_IDS="$SESSION_IDS $sid"
    done
    ;;
  latest)
    if [ ! -d "$PROJECT_DIR" ]; then
      echo "error: no session found under ${PROJECT_DIR}" >&2
      exit 1
    fi
    # Find the most recently modified .jsonl file
    latest_file=""
    latest_time=0
    for f in "$PROJECT_DIR"/*.jsonl; do
      [ -e "$f" ] || continue
      # Use stat for mtime comparison (POSIX-compatible)
      mtime=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)
      if [ "$mtime" -gt "$latest_time" ]; then
        latest_time="$mtime"
        latest_file="$f"
      fi
    done
    if [ -z "$latest_file" ]; then
      echo "error: no session found under ${PROJECT_DIR}" >&2
      exit 1
    fi
    SESSION_IDS=$(basename "$latest_file" .jsonl)
    ;;
  *)
    SESSION_IDS="$SELECTORS"
    ;;
esac

# Trim leading space
SESSION_IDS=$(printf '%s' "$SESSION_IDS" | sed 's/^ //')

if [ -z "$SESSION_IDS" ]; then
  echo "error: no session found" >&2
  exit 1
fi

# ── Default output path ────────────────────────────────────────────

if [ -z "$OUTPUT" ]; then
  OUTPUT="${HOME}/claude-session-export-$(date +%Y%m%d-%H%M%S).tar.gz"
fi

# ── Stage files ─────────────────────────────────────────────────────

STAGING=$(mktemp -d)
EXPORT_DIR="$STAGING/claude-session-export"
mkdir -p "$EXPORT_DIR/session"

EXPORTED=0
HISTORY_FILE="${HOME}/.claude/history.jsonl"

for SID in $SESSION_IDS; do
  # Find the .jsonl file: current project dir first, then all dirs
  FOUND_JSONL=""
  if [ -f "$PROJECT_DIR/${SID}.jsonl" ]; then
    FOUND_JSONL="$PROJECT_DIR/${SID}.jsonl"
  else
    # Search history.jsonl for the original project path
    if [ -f "$HISTORY_FILE" ]; then
      ORIG_PROJECT=$(grep "\"sessionId\":\"${SID}\"" "$HISTORY_FILE" | head -n 1 | sed 's/.*"project":"\([^"]*\)".*/\1/')
      if [ -n "$ORIG_PROJECT" ]; then
        ORIG_ENCODED=$(printf '%s' "$ORIG_PROJECT" | sed 's|[^a-zA-Z0-9-]|-|g')
        CANDIDATE="${CLAUDE_DIR}/${ORIG_ENCODED}/${SID}.jsonl"
        [ -f "$CANDIDATE" ] && FOUND_JSONL="$CANDIDATE"
      fi
    fi
    # Glob fallback
    if [ -z "$FOUND_JSONL" ]; then
      for candidate in "${CLAUDE_DIR}"/*/"${SID}.jsonl"; do
        [ -e "$candidate" ] || continue
        FOUND_JSONL="$candidate"
        break
      done
    fi
  fi

  if [ -z "$FOUND_JSONL" ]; then
    echo "warning: session ${SID} not found, skipping" >&2
    continue
  fi

  FOUND_DIR=$(dirname "$FOUND_JSONL")

  # Copy .jsonl
  cp "$FOUND_JSONL" "$EXPORT_DIR/session/${SID}.jsonl"

  # Copy session directory if it exists
  if [ -d "$FOUND_DIR/${SID}" ]; then
    cp -r "$FOUND_DIR/${SID}" "$EXPORT_DIR/session/${SID}"
  fi

  # Extract matching history entry
  if [ -f "$HISTORY_FILE" ]; then
    grep "\"sessionId\":\"${SID}\"" "$HISTORY_FILE" >> "$EXPORT_DIR/history.jsonl" 2>/dev/null || true
  fi

  EXPORTED=$((EXPORTED + 1))
done

if [ "$EXPORTED" -eq 0 ]; then
  echo "error: no session found to export" >&2
  rm -rf "$STAGING"
  exit 1
fi

# ── Generate manifest ───────────────────────────────────────────────

printf '{"version":1,"exportDate":"%s","sourceProject":"%s","sessionCount":%d}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$CWD" "$EXPORTED" > "$EXPORT_DIR/manifest.json"

# ── Create archive ──────────────────────────────────────────────────

tar czf "$OUTPUT" -C "$STAGING" claude-session-export

# ── Cleanup ─────────────────────────────────────────────────────────

rm -rf "$STAGING"

echo "$OUTPUT"
echo "exported ${EXPORTED} session(s)" >&2

exit 0
