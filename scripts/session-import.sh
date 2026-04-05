#!/bin/sh
# session-import.sh — Import session files from a portable archive
#
# Usage: session-import.sh [-f|--force] ARCHIVE [CWD]
# Exit codes: 0 = success, 1 = not found, 2 = error
#
# Extracts a tar.gz archive created by session-export.sh and copies
# session files into ~/.claude/projects/ under the current directory's
# encoded path.
# POSIX-only: no jq, no bash-isms

set -e

# ── Argument parsing ────────────────────────────────────────────────

FORCE=false
ARCHIVE=""
CWD=""

while [ $# -gt 0 ]; do
  case "$1" in
    -f|--force)
      FORCE=true
      ;;
    *)
      if [ -z "$ARCHIVE" ]; then
        ARCHIVE="$1"
      elif [ -z "$CWD" ]; then
        CWD="$1"
      fi
      ;;
  esac
  shift
done

if [ -z "$ARCHIVE" ]; then
  echo "Usage: session-import.sh [-f|--force] ARCHIVE [CWD]" >&2
  exit 2
fi

if [ ! -f "$ARCHIVE" ]; then
  echo "error: archive not found: ${ARCHIVE}" >&2
  exit 1
fi

# ── Extract ─────────────────────────────────────────────────────────

TMPDIR=$(mktemp -d)

if ! tar xzf "$ARCHIVE" -C "$TMPDIR" 2>/dev/null; then
  echo "error: failed to extract archive" >&2
  rm -rf "$TMPDIR"
  exit 2
fi

EXPORT_DIR="$TMPDIR/claude-session-export"
if [ ! -d "$EXPORT_DIR/session" ]; then
  echo "error: invalid archive structure (missing session/)" >&2
  rm -rf "$TMPDIR"
  exit 2
fi

# ── Target path ─────────────────────────────────────────────────────

CWD="${CWD:-$(pwd)}"
ENCODED_CWD=$(printf '%s' "$CWD" | sed 's|[^a-zA-Z0-9-]|-|g')
TARGET_DIR="${HOME}/.claude/projects/${ENCODED_CWD}"
mkdir -p "$TARGET_DIR"

# ── Import session files ────────────────────────────────────────────

IMPORTED=0
SKIPPED=0

for jsonl in "$EXPORT_DIR/session"/*.jsonl; do
  [ -e "$jsonl" ] || continue
  SID=$(basename "$jsonl" .jsonl)
  TARGET_JSONL="${TARGET_DIR}/${SID}.jsonl"

  if [ -e "$TARGET_JSONL" ] && [ "$FORCE" = false ]; then
    echo "skip: ${SID} (already exists, use --force to overwrite)" >&2
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  cp "$jsonl" "$TARGET_JSONL"

  if [ -d "$EXPORT_DIR/session/${SID}" ]; then
    # Remove existing dir if forcing
    if [ "$FORCE" = true ] && [ -d "${TARGET_DIR}/${SID}" ]; then
      rm -rf "${TARGET_DIR}/${SID}"
    fi
    cp -r "$EXPORT_DIR/session/${SID}" "${TARGET_DIR}/${SID}"
  fi

  echo "imported: ${SID}"
  IMPORTED=$((IMPORTED + 1))
done

# ── Merge history entries ───────────────────────────────────────────

if [ -f "$EXPORT_DIR/history.jsonl" ]; then
  HIST="${HOME}/.claude/history.jsonl"
  while IFS= read -r line; do
    # Extract sessionId
    SID=$(printf '%s' "$line" | sed 's/.*"sessionId":"\([^"]*\)".*/\1/')
    # Skip if already in history
    if [ -f "$HIST" ] && grep -qF "\"sessionId\":\"${SID}\"" "$HIST" 2>/dev/null; then
      continue
    fi
    # Rewrite the project field to current CWD
    UPDATED=$(printf '%s' "$line" | sed "s|\"project\":\"[^\"]*\"|\"project\":\"${CWD}\"|")
    printf '%s\n' "$UPDATED" >> "$HIST"
  done < "$EXPORT_DIR/history.jsonl"
fi

# ── Cleanup ─────────────────────────────────────────────────────────

rm -rf "$TMPDIR"

echo "imported ${IMPORTED} session(s), skipped ${SKIPPED}" >&2

exit 0
