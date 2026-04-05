#!/bin/sh
# run-tests.sh — Test suite for claude-session-recover
#
# Usage: sh tests/run-tests.sh
#
# Creates a sandboxed environment under a temp directory so nothing
# touches real ~/.claude data. Cleans up after itself.

# NOTE: no `set -e` — tests intentionally trigger non-zero exits

PLUGIN_DIR=$(cd "$(dirname "$0")/.." && pwd)
RECOVER="$PLUGIN_DIR/scripts/session-recover.sh"
EXPORT="$PLUGIN_DIR/scripts/session-export.sh"
IMPORT="$PLUGIN_DIR/scripts/session-import.sh"
HOOK="$PLUGIN_DIR/scripts/check-session-path.sh"
WRAPPER="$PLUGIN_DIR/bin/claude-resume"

PASS=0
FAIL=0
TESTS=0

# ── Helpers ──────────────────────────────────────────────────────────

sandbox() {
  SANDBOX=$(mktemp -d)
  FAKE_HOME="$SANDBOX/home"
  FAKE_CLAUDE="$FAKE_HOME/.claude"
  FAKE_PROJECTS="$FAKE_CLAUDE/projects"
  mkdir -p "$FAKE_PROJECTS"
}

cleanup() {
  rm -rf "$SANDBOX"
}

pass() {
  PASS=$((PASS + 1))
  TESTS=$((TESTS + 1))
  printf "  PASS: %s\n" "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  TESTS=$((TESTS + 1))
  printf "  FAIL: %s\n" "$1"
  [ -n "${2:-}" ] && printf "        %s\n" "$2"
}

assert_exists() {
  if [ -e "$1" ]; then pass "$2"; else fail "$2" "missing: $1"; fi
}

assert_not_exists() {
  if [ ! -e "$1" ]; then pass "$2"; else fail "$2" "unexpectedly exists: $1"; fi
}

assert_regular_file() {
  if [ -f "$1" ] && [ ! -L "$1" ]; then pass "$2"; else fail "$2" "not a regular file: $1"; fi
}

assert_directory() {
  if [ -d "$1" ] && [ ! -L "$1" ]; then pass "$2"; else fail "$2" "not a regular directory: $1"; fi
}

assert_exit() {
  expected=$1; shift
  actual=$1; shift
  if [ "$expected" -eq "$actual" ]; then pass "$1"; else fail "$1" "expected exit $expected, got $actual"; fi
}

assert_contains() {
  if printf '%s' "$1" | grep -qF -- "$2"; then pass "$3"; else fail "$3" "output missing: $2"; fi
}

assert_empty() {
  if [ -z "$1" ]; then pass "$2"; else fail "$2" "expected empty, got: $1"; fi
}

assert_valid_json() {
  if printf '%s' "$1" | jq . >/dev/null 2>&1; then pass "$2"; else fail "$2" "invalid JSON: $1"; fi
}

# ── session-recover.sh tests ────────────────────────────────────────

echo ""
echo "=== session-recover.sh ==="

echo ""
echo "-- Recovery via glob search --"
sandbox
  OLD="-old-project-path"
  SID="session-glob-001"
  mkdir -p "$FAKE_PROJECTS/$OLD/$SID/subagents"
  echo '{"type":"user"}' > "$FAKE_PROJECTS/$OLD/$SID.jsonl"
  echo "data" > "$FAKE_PROJECTS/$OLD/$SID/subagents/agent.jsonl"

  OUTPUT=$(HOME="$FAKE_HOME" sh "$RECOVER" "$SID" "/new/project/path" 2>&1)
  RC=$?
  NEW_ENC="-new-project-path"

  assert_exit 0 $RC "exits 0 on successful recovery"
  assert_regular_file "$FAKE_PROJECTS/$NEW_ENC/$SID.jsonl" "copies .jsonl file"
  assert_directory "$FAKE_PROJECTS/$NEW_ENC/$SID" "copies session directory"
  assert_contains "$OUTPUT" "copied:" "prints copied message"

  # Verify content accessible through copy
  CONTENT=$(cat "$FAKE_PROJECTS/$NEW_ENC/$SID/subagents/agent.jsonl" 2>/dev/null || echo "")
  if [ "$CONTENT" = "data" ]; then pass "copied content is readable"; else fail "copied content is readable" "got: $CONTENT"; fi
cleanup

echo ""
echo "-- Recovery via history.jsonl lookup --"
sandbox
  SID="session-hist-002"
  OLD_PROJECT="/Users/test/OldProject"
  OLD_ENC=$(printf '%s' "$OLD_PROJECT" | sed 's|[^a-zA-Z0-9-]|-|g')
  mkdir -p "$FAKE_PROJECTS/$OLD_ENC/$SID/tool-results"
  echo '{"type":"user"}' > "$FAKE_PROJECTS/$OLD_ENC/$SID.jsonl"

  # Create history.jsonl pointing to the old project
  echo "{\"display\":\"test\",\"timestamp\":123,\"project\":\"$OLD_PROJECT\",\"sessionId\":\"$SID\"}" > "$FAKE_CLAUDE/history.jsonl"

  OUTPUT=$(HOME="$FAKE_HOME" sh "$RECOVER" "$SID" "/Users/test/NewProject" 2>&1)
  RC=$?
  NEW_ENC="-Users-test-NewProject"

  assert_exit 0 $RC "exits 0 via history lookup"
  assert_regular_file "$FAKE_PROJECTS/$NEW_ENC/$SID.jsonl" "copies .jsonl via history"
  assert_directory "$FAKE_PROJECTS/$NEW_ENC/$SID" "copies session dir via history"
cleanup

echo ""
echo "-- Session already at target path (no-op) --"
sandbox
  SID="session-exists-003"
  ENC="-already-here"
  mkdir -p "$FAKE_PROJECTS/$ENC"
  echo '{"existing":true}' > "$FAKE_PROJECTS/$ENC/$SID.jsonl"

  OUTPUT=$(HOME="$FAKE_HOME" sh "$RECOVER" "$SID" "/already/here" 2>&1)
  RC=$?

  assert_exit 0 $RC "exits 0 when session already exists"
  assert_empty "$OUTPUT" "produces no output for existing session"
  # Verify it's still the original file, not overwritten
  CONTENT=$(cat "$FAKE_PROJECTS/$ENC/$SID.jsonl" 2>/dev/null)
  if [ "$CONTENT" = '{"existing":true}' ]; then pass "does not overwrite existing file"; else fail "does not overwrite existing file" "got: $CONTENT"; fi
cleanup

echo ""
echo "-- Session not found --"
sandbox
  OUTPUT=$(HOME="$FAKE_HOME" sh "$RECOVER" "nonexistent-session" "/some/path" 2>&1); RC=$?

  assert_exit 1 $RC "exits 1 when session not found"
  assert_contains "$OUTPUT" "not found" "prints not-found error"
cleanup

echo ""
echo "-- Missing session ID argument --"
sandbox
  OUTPUT=$(HOME="$FAKE_HOME" sh "$RECOVER" "" 2>&1); RC=$?

  assert_exit 2 $RC "exits 2 when session ID is missing"
cleanup

echo ""
echo "-- Missing .claude/projects directory --"
sandbox
  rmdir "$FAKE_PROJECTS"
  OUTPUT=$(HOME="$FAKE_HOME" sh "$RECOVER" "any-id" "/any/path" 2>&1); RC=$?

  assert_exit 2 $RC "exits 2 when projects dir missing"
cleanup

echo ""
echo "-- Session with .jsonl only (no session directory) --"
sandbox
  OLD="-jsonl-only"
  SID="session-nod-004"
  mkdir -p "$FAKE_PROJECTS/$OLD"
  echo '{"type":"user"}' > "$FAKE_PROJECTS/$OLD/$SID.jsonl"
  # No session directory created

  HOME="$FAKE_HOME" sh "$RECOVER" "$SID" "/new/path" >/dev/null 2>&1
  RC=$?
  NEW_ENC="-new-path"

  assert_exit 0 $RC "exits 0 with jsonl-only session"
  assert_regular_file "$FAKE_PROJECTS/$NEW_ENC/$SID.jsonl" "copies .jsonl when no session dir"
  assert_not_exists "$FAKE_PROJECTS/$NEW_ENC/$SID" "does not create copy for missing session dir"
cleanup

echo ""
echo "-- Idempotent: running recovery twice --"
sandbox
  OLD="-idempotent-old"
  SID="session-idem-005"
  mkdir -p "$FAKE_PROJECTS/$OLD/$SID/subagents"
  echo '{"type":"user"}' > "$FAKE_PROJECTS/$OLD/$SID.jsonl"

  HOME="$FAKE_HOME" sh "$RECOVER" "$SID" "/idempotent/new" >/dev/null 2>&1
  # Run again — should succeed without error
  HOME="$FAKE_HOME" sh "$RECOVER" "$SID" "/idempotent/new" >/dev/null 2>&1
  RC=$?

  assert_exit 0 $RC "second run is idempotent"
cleanup

# ── check-session-path.sh (hook) tests ──────────────────────────────

echo ""
echo "=== check-session-path.sh (SessionStart hook) ==="

HAS_JQ=true
if ! command -v jq >/dev/null 2>&1; then
  echo "  SKIP: jq not available, skipping hook tests"
  HAS_JQ=false
fi

if $HAS_JQ; then

echo ""
echo "-- Mismatched cwds produces advisory context --"
sandbox
  TRANSCRIPT="$SANDBOX/transcript.jsonl"
  echo '{"type":"system","message":"init"}' > "$TRANSCRIPT"
  echo '{"type":"user","cwd":"/old/path","message":"hello"}' >> "$TRANSCRIPT"

  OUTPUT=$(printf '{"session_id":"s1","cwd":"/new/path","transcript_path":"%s"}' "$TRANSCRIPT" \
    | sh "$HOOK")
  RC=$?

  assert_exit 0 $RC "exits 0 on mismatch"
  assert_valid_json "$OUTPUT" "output is valid JSON"
  assert_contains "$OUTPUT" "additionalContext" "contains additionalContext"
  assert_contains "$OUTPUT" "/old/path" "mentions original path"
  assert_contains "$OUTPUT" "/new/path" "mentions current path"
cleanup

echo ""
echo "-- Matching cwds produces no output --"
sandbox
  TRANSCRIPT="$SANDBOX/transcript.jsonl"
  echo '{"type":"user","cwd":"/same/path","message":"hello"}' > "$TRANSCRIPT"

  OUTPUT=$(printf '{"session_id":"s2","cwd":"/same/path","transcript_path":"%s"}' "$TRANSCRIPT" \
    | sh "$HOOK")
  RC=$?

  assert_exit 0 $RC "exits 0 on match"
  assert_empty "$OUTPUT" "no output when paths match"
cleanup

echo ""
echo "-- Missing transcript file --"
sandbox
  OUTPUT=$(printf '{"session_id":"s3","cwd":"/some/path","transcript_path":"/nonexistent/file.jsonl"}' \
    | sh "$HOOK")
  RC=$?

  assert_exit 0 $RC "exits 0 when transcript missing"
  assert_empty "$OUTPUT" "no output when transcript missing"
cleanup

echo ""
echo "-- No user message in transcript --"
sandbox
  TRANSCRIPT="$SANDBOX/transcript.jsonl"
  echo '{"type":"system","message":"init"}' > "$TRANSCRIPT"
  echo '{"type":"assistant","message":"hi"}' >> "$TRANSCRIPT"

  OUTPUT=$(printf '{"session_id":"s4","cwd":"/some/path","transcript_path":"%s"}' "$TRANSCRIPT" \
    | sh "$HOOK")
  RC=$?

  assert_exit 0 $RC "exits 0 when no user message"
  assert_empty "$OUTPUT" "no output when no user message found"
cleanup

echo ""
echo "-- Special characters in paths --"
sandbox
  TRANSCRIPT="$SANDBOX/transcript.jsonl"
  printf '{"type":"user","cwd":"/path/with \\"quotes\\" and spaces","message":"hi"}\n' > "$TRANSCRIPT"

  OUTPUT=$(printf '{"session_id":"s5","cwd":"/different/path","transcript_path":"%s"}' "$TRANSCRIPT" \
    | sh "$HOOK")
  RC=$?

  assert_exit 0 $RC "exits 0 with special chars"
  assert_valid_json "$OUTPUT" "output is valid JSON even with special chars"
cleanup

echo ""
echo "-- Empty stdin --"
sandbox
  OUTPUT=$(printf '' | sh "$HOOK")
  RC=$?

  assert_exit 0 $RC "exits 0 on empty stdin"
  assert_empty "$OUTPUT" "no output on empty stdin"
cleanup

fi # HAS_JQ

# ── bin/claude-resume (wrapper) tests ────────────────────────────────

echo ""
echo "=== bin/claude-resume (arg parsing) ==="

# We can't test `exec claude` without claude installed, but we can
# verify arg parsing by replacing the recover script and claude binary.

echo ""
echo "-- Parses --resume=SESSION_ID --"
sandbox
  OLD="-old-wrap"
  SID="wrap-session-001"
  mkdir -p "$FAKE_PROJECTS/$OLD"
  echo '{}' > "$FAKE_PROJECTS/$OLD/$SID.jsonl"

  # Create a fake claude that just echoes args
  FAKE_BIN="$SANDBOX/bin"
  mkdir -p "$FAKE_BIN"
  printf '#!/bin/sh\necho "claude called with: $*"\n' > "$FAKE_BIN/claude"
  chmod +x "$FAKE_BIN/claude"

  OUTPUT=$(HOME="$FAKE_HOME" PATH="$FAKE_BIN:$PATH" sh "$WRAPPER" --resume="$SID" --print 2>&1)

  assert_contains "$OUTPUT" "claude called with" "passes args through to claude"
  assert_contains "$OUTPUT" "--resume=$SID" "preserves --resume=ID format"
cleanup

echo ""
echo "-- Parses --resume SESSION_ID (space separated) --"
sandbox
  OLD="-old-wrap2"
  SID="wrap-session-002"
  mkdir -p "$FAKE_PROJECTS/$OLD"
  echo '{}' > "$FAKE_PROJECTS/$OLD/$SID.jsonl"

  FAKE_BIN="$SANDBOX/bin"
  mkdir -p "$FAKE_BIN"
  printf '#!/bin/sh\necho "claude called with: $*"\n' > "$FAKE_BIN/claude"
  chmod +x "$FAKE_BIN/claude"

  OUTPUT=$(HOME="$FAKE_HOME" PATH="$FAKE_BIN:$PATH" sh "$WRAPPER" --resume "$SID" --print 2>&1)

  assert_contains "$OUTPUT" "claude called with" "passes args through to claude"
  assert_contains "$OUTPUT" "--resume $SID" "preserves --resume ID format"
cleanup

echo ""
echo "-- No --resume flag passes through cleanly --"
sandbox
  FAKE_BIN="$SANDBOX/bin"
  mkdir -p "$FAKE_BIN"
  printf '#!/bin/sh\necho "claude called with: $*"\n' > "$FAKE_BIN/claude"
  chmod +x "$FAKE_BIN/claude"

  OUTPUT=$(HOME="$FAKE_HOME" PATH="$FAKE_BIN:$PATH" sh "$WRAPPER" --help 2>&1)

  assert_contains "$OUTPUT" "claude called with: --help" "non-resume args pass through"
cleanup

echo ""
echo "-- Recovery runs before claude launches --"
sandbox
  OLD="-pre-launch"
  SID="wrap-session-003"
  mkdir -p "$FAKE_PROJECTS/$OLD/$SID/subagents"
  echo '{}' > "$FAKE_PROJECTS/$OLD/$SID.jsonl"

  FAKE_BIN="$SANDBOX/bin"
  mkdir -p "$FAKE_BIN"
  NEW_ENC=$(printf '%s' "$SANDBOX/workdir" | sed 's|[^a-zA-Z0-9-]|-|g')
  # Fake claude checks if the recovered file exists at launch time
  cat > "$FAKE_BIN/claude" <<SCRIPT
#!/bin/sh
if [ -f "$FAKE_PROJECTS/$NEW_ENC/$SID.jsonl" ]; then
  echo "RECOVERY_HAPPENED_BEFORE_LAUNCH"
else
  echo "NO_RECOVERY"
fi
SCRIPT
  chmod +x "$FAKE_BIN/claude"

  mkdir -p "$SANDBOX/workdir"
  OUTPUT=$(cd "$SANDBOX/workdir" && HOME="$FAKE_HOME" PATH="$FAKE_BIN:$PATH" sh "$WRAPPER" --resume "$SID" 2>&1)

  assert_contains "$OUTPUT" "RECOVERY_HAPPENED_BEFORE_LAUNCH" "recovery runs before claude exec"
cleanup

# ── session-export.sh tests ─────────────────────────────────────────

echo ""
echo "=== session-export.sh ==="

echo ""
echo "-- Export a single session by ID --"
sandbox
  SID="export-single-001"
  ENC="-export-project"
  mkdir -p "$FAKE_PROJECTS/$ENC/$SID/subagents"
  echo '{"type":"user"}' > "$FAKE_PROJECTS/$ENC/$SID.jsonl"
  echo "agent-data" > "$FAKE_PROJECTS/$ENC/$SID/subagents/agent.jsonl"

  OUTPUT_FILE="$SANDBOX/out.tar.gz"
  OUTPUT=$(HOME="$FAKE_HOME" sh "$EXPORT" -o "$OUTPUT_FILE" -C "/export/project" "$SID" 2>&1)
  RC=$?

  assert_exit 0 $RC "exits 0 on single session export"
  assert_exists "$OUTPUT_FILE" "creates archive file"
  # Verify archive contents
  CONTENTS=$(tar tzf "$OUTPUT_FILE" 2>/dev/null)
  assert_contains "$CONTENTS" "claude-session-export/session/${SID}.jsonl" "archive contains .jsonl"
  assert_contains "$CONTENTS" "claude-session-export/session/${SID}/subagents/agent.jsonl" "archive contains session directory"
  assert_contains "$CONTENTS" "claude-session-export/manifest.json" "archive contains manifest"
cleanup

echo ""
echo "-- Export multiple session IDs --"
sandbox
  ENC="-multi-project"
  SID1="export-multi-001"
  SID2="export-multi-002"
  mkdir -p "$FAKE_PROJECTS/$ENC"
  echo '{"type":"user","id":"1"}' > "$FAKE_PROJECTS/$ENC/$SID1.jsonl"
  echo '{"type":"user","id":"2"}' > "$FAKE_PROJECTS/$ENC/$SID2.jsonl"

  OUTPUT_FILE="$SANDBOX/multi.tar.gz"
  OUTPUT=$(HOME="$FAKE_HOME" sh "$EXPORT" -o "$OUTPUT_FILE" -C "/multi/project" "$SID1" "$SID2" 2>&1)
  RC=$?

  assert_exit 0 $RC "exits 0 on multi-session export"
  CONTENTS=$(tar tzf "$OUTPUT_FILE" 2>/dev/null)
  assert_contains "$CONTENTS" "${SID1}.jsonl" "archive contains first session"
  assert_contains "$CONTENTS" "${SID2}.jsonl" "archive contains second session"
  assert_contains "$OUTPUT" "exported 2 session(s)" "reports correct count"
cleanup

echo ""
echo "-- Export with 'latest' selector --"
sandbox
  ENC="-latest-project"
  SID_OLD="export-old-001"
  SID_NEW="export-new-002"
  mkdir -p "$FAKE_PROJECTS/$ENC"
  echo '{"type":"user","id":"old"}' > "$FAKE_PROJECTS/$ENC/$SID_OLD.jsonl"
  sleep 1
  echo '{"type":"user","id":"new"}' > "$FAKE_PROJECTS/$ENC/$SID_NEW.jsonl"

  OUTPUT_FILE="$SANDBOX/latest.tar.gz"
  OUTPUT=$(HOME="$FAKE_HOME" sh "$EXPORT" -o "$OUTPUT_FILE" -C "/latest/project" latest 2>&1)
  RC=$?

  assert_exit 0 $RC "exits 0 with latest selector"
  CONTENTS=$(tar tzf "$OUTPUT_FILE" 2>/dev/null)
  assert_contains "$CONTENTS" "${SID_NEW}.jsonl" "archive contains the newest session"
  assert_contains "$OUTPUT" "exported 1 session(s)" "exports exactly one session"
cleanup

echo ""
echo "-- Export with 'all' selector --"
sandbox
  ENC="-all-project"
  mkdir -p "$FAKE_PROJECTS/$ENC"
  echo '{}' > "$FAKE_PROJECTS/$ENC/all-001.jsonl"
  echo '{}' > "$FAKE_PROJECTS/$ENC/all-002.jsonl"
  echo '{}' > "$FAKE_PROJECTS/$ENC/all-003.jsonl"

  OUTPUT_FILE="$SANDBOX/all.tar.gz"
  OUTPUT=$(HOME="$FAKE_HOME" sh "$EXPORT" -o "$OUTPUT_FILE" -C "/all/project" all 2>&1)
  RC=$?

  assert_exit 0 $RC "exits 0 with all selector"
  assert_contains "$OUTPUT" "exported 3 session(s)" "exports all three session files"
cleanup

echo ""
echo "-- Export includes history metadata --"
sandbox
  ENC="-hist-project"
  SID="export-hist-001"
  mkdir -p "$FAKE_PROJECTS/$ENC"
  echo '{"type":"user"}' > "$FAKE_PROJECTS/$ENC/$SID.jsonl"
  echo "{\"sessionId\":\"${SID}\",\"project\":\"/hist/project\",\"display\":\"test session\"}" > "$FAKE_CLAUDE/history.jsonl"

  OUTPUT_FILE="$SANDBOX/hist.tar.gz"
  OUTPUT=$(HOME="$FAKE_HOME" sh "$EXPORT" -o "$OUTPUT_FILE" -C "/hist/project" "$SID" 2>&1)
  RC=$?

  # Extract and check history
  EXTRACT_DIR=$(mktemp -d)
  tar xzf "$OUTPUT_FILE" -C "$EXTRACT_DIR"
  assert_exists "$EXTRACT_DIR/claude-session-export/history.jsonl" "archive contains history.jsonl"
  HIST_CONTENT=$(cat "$EXTRACT_DIR/claude-session-export/history.jsonl" 2>/dev/null)
  assert_contains "$HIST_CONTENT" "$SID" "history contains session ID"
  rm -rf "$EXTRACT_DIR"
cleanup

echo ""
echo "-- Export nonexistent session --"
sandbox
  OUTPUT=$(HOME="$FAKE_HOME" sh "$EXPORT" -o "$SANDBOX/nope.tar.gz" "nonexistent-id" 2>&1); RC=$?

  assert_exit 1 $RC "exits 1 when session not found"
  assert_not_exists "$SANDBOX/nope.tar.gz" "does not create archive on failure"
cleanup

echo ""
echo "-- Export with no arguments --"
sandbox
  OUTPUT=$(HOME="$FAKE_HOME" sh "$EXPORT" 2>&1); RC=$?

  assert_exit 2 $RC "exits 2 with no arguments"
  assert_contains "$OUTPUT" "Usage" "prints usage message"
cleanup

echo ""
echo "-- Export session with .jsonl only (no directory) --"
sandbox
  ENC="-jsonl-only-export"
  SID="export-nod-001"
  mkdir -p "$FAKE_PROJECTS/$ENC"
  echo '{"type":"user"}' > "$FAKE_PROJECTS/$ENC/$SID.jsonl"

  OUTPUT_FILE="$SANDBOX/nod.tar.gz"
  OUTPUT=$(HOME="$FAKE_HOME" sh "$EXPORT" -o "$OUTPUT_FILE" -C "/jsonl/only/export" "$SID" 2>&1)
  RC=$?

  assert_exit 0 $RC "exits 0 with jsonl-only session"
  CONTENTS=$(tar tzf "$OUTPUT_FILE" 2>/dev/null)
  assert_contains "$CONTENTS" "${SID}.jsonl" "archive contains .jsonl"
cleanup

# ── session-import.sh tests ─────────────────────────────────────────

echo ""
echo "=== session-import.sh ==="

echo ""
echo "-- Import a valid archive --"
sandbox
  # Create an archive manually
  SID="import-valid-001"
  STAGE="$SANDBOX/stage"
  mkdir -p "$STAGE/claude-session-export/session/$SID/subagents"
  echo '{"type":"user"}' > "$STAGE/claude-session-export/session/$SID.jsonl"
  echo "agent-data" > "$STAGE/claude-session-export/session/$SID/subagents/agent.jsonl"
  printf '{"version":1}\n' > "$STAGE/claude-session-export/manifest.json"
  ARCHIVE="$SANDBOX/import.tar.gz"
  tar czf "$ARCHIVE" -C "$STAGE" claude-session-export

  OUTPUT=$(HOME="$FAKE_HOME" sh "$IMPORT" "$ARCHIVE" "/import/target" 2>&1)
  RC=$?
  TARGET_ENC="-import-target"

  assert_exit 0 $RC "exits 0 on valid import"
  assert_regular_file "$FAKE_PROJECTS/$TARGET_ENC/$SID.jsonl" "imports .jsonl file"
  assert_directory "$FAKE_PROJECTS/$TARGET_ENC/$SID" "imports session directory"
  CONTENT=$(cat "$FAKE_PROJECTS/$TARGET_ENC/$SID/subagents/agent.jsonl" 2>/dev/null)
  if [ "$CONTENT" = "agent-data" ]; then pass "imported content is correct"; else fail "imported content is correct" "got: $CONTENT"; fi
  assert_contains "$OUTPUT" "imported: $SID" "prints imported message"
cleanup

echo ""
echo "-- Import skips existing session --"
sandbox
  SID="import-skip-001"
  TARGET_ENC="-skip-target"
  mkdir -p "$FAKE_PROJECTS/$TARGET_ENC"
  echo '{"existing":true}' > "$FAKE_PROJECTS/$TARGET_ENC/$SID.jsonl"

  STAGE="$SANDBOX/stage"
  mkdir -p "$STAGE/claude-session-export/session"
  echo '{"new":true}' > "$STAGE/claude-session-export/session/$SID.jsonl"
  ARCHIVE="$SANDBOX/skip.tar.gz"
  tar czf "$ARCHIVE" -C "$STAGE" claude-session-export

  OUTPUT=$(HOME="$FAKE_HOME" sh "$IMPORT" "$ARCHIVE" "/skip/target" 2>&1)
  RC=$?

  assert_exit 0 $RC "exits 0 when skipping"
  # Verify original file was not overwritten
  CONTENT=$(cat "$FAKE_PROJECTS/$TARGET_ENC/$SID.jsonl" 2>/dev/null)
  if [ "$CONTENT" = '{"existing":true}' ]; then pass "does not overwrite existing session"; else fail "does not overwrite existing session" "got: $CONTENT"; fi
  assert_contains "$OUTPUT" "skip" "prints skip message"
  assert_contains "$OUTPUT" "skipped 1" "reports skipped count"
cleanup

echo ""
echo "-- Import with --force overwrites --"
sandbox
  SID="import-force-001"
  TARGET_ENC="-force-target"
  mkdir -p "$FAKE_PROJECTS/$TARGET_ENC"
  echo '{"old":true}' > "$FAKE_PROJECTS/$TARGET_ENC/$SID.jsonl"

  STAGE="$SANDBOX/stage"
  mkdir -p "$STAGE/claude-session-export/session"
  echo '{"new":true}' > "$STAGE/claude-session-export/session/$SID.jsonl"
  ARCHIVE="$SANDBOX/force.tar.gz"
  tar czf "$ARCHIVE" -C "$STAGE" claude-session-export

  OUTPUT=$(HOME="$FAKE_HOME" sh "$IMPORT" --force "$ARCHIVE" "/force/target" 2>&1)
  RC=$?

  assert_exit 0 $RC "exits 0 with --force"
  CONTENT=$(cat "$FAKE_PROJECTS/$TARGET_ENC/$SID.jsonl" 2>/dev/null)
  if [ "$CONTENT" = '{"new":true}' ]; then pass "overwrites with --force"; else fail "overwrites with --force" "got: $CONTENT"; fi
cleanup

echo ""
echo "-- Import merges history entries --"
sandbox
  SID="import-hist-001"
  STAGE="$SANDBOX/stage"
  mkdir -p "$STAGE/claude-session-export/session"
  echo '{}' > "$STAGE/claude-session-export/session/$SID.jsonl"
  echo "{\"sessionId\":\"${SID}\",\"project\":\"/old/path\",\"display\":\"test\"}" > "$STAGE/claude-session-export/history.jsonl"
  ARCHIVE="$SANDBOX/hist.tar.gz"
  tar czf "$ARCHIVE" -C "$STAGE" claude-session-export

  OUTPUT=$(HOME="$FAKE_HOME" sh "$IMPORT" "$ARCHIVE" "/new/path" 2>&1)
  RC=$?

  assert_exit 0 $RC "exits 0 with history merge"
  assert_exists "$FAKE_CLAUDE/history.jsonl" "creates history.jsonl"
  HIST=$(cat "$FAKE_CLAUDE/history.jsonl" 2>/dev/null)
  assert_contains "$HIST" "$SID" "history contains session ID"
  assert_contains "$HIST" "/new/path" "history has updated project path"
cleanup

echo ""
echo "-- Import does not duplicate history entries --"
sandbox
  SID="import-dedup-001"
  echo "{\"sessionId\":\"${SID}\",\"project\":\"/existing\"}" > "$FAKE_CLAUDE/history.jsonl"

  STAGE="$SANDBOX/stage"
  mkdir -p "$STAGE/claude-session-export/session"
  echo '{}' > "$STAGE/claude-session-export/session/$SID.jsonl"
  echo "{\"sessionId\":\"${SID}\",\"project\":\"/old\"}" > "$STAGE/claude-session-export/history.jsonl"
  ARCHIVE="$SANDBOX/dedup.tar.gz"
  tar czf "$ARCHIVE" -C "$STAGE" claude-session-export

  OUTPUT=$(HOME="$FAKE_HOME" sh "$IMPORT" --force "$ARCHIVE" "/existing" 2>&1)
  RC=$?

  HIST_COUNT=$(grep -c "\"sessionId\":\"${SID}\"" "$FAKE_CLAUDE/history.jsonl" 2>/dev/null || echo 0)
  if [ "$HIST_COUNT" -eq 1 ]; then pass "does not duplicate history entry"; else fail "does not duplicate history entry" "found $HIST_COUNT entries"; fi
cleanup

echo ""
echo "-- Import missing archive --"
sandbox
  OUTPUT=$(HOME="$FAKE_HOME" sh "$IMPORT" "/nonexistent/archive.tar.gz" 2>&1); RC=$?

  assert_exit 1 $RC "exits 1 when archive not found"
  assert_contains "$OUTPUT" "not found" "prints not-found error"
cleanup

echo ""
echo "-- Import invalid archive --"
sandbox
  echo "not a tarball" > "$SANDBOX/bad.tar.gz"
  OUTPUT=$(HOME="$FAKE_HOME" sh "$IMPORT" "$SANDBOX/bad.tar.gz" 2>&1); RC=$?

  assert_exit 2 $RC "exits 2 on invalid archive"
cleanup

echo ""
echo "-- Import with no arguments --"
sandbox
  OUTPUT=$(HOME="$FAKE_HOME" sh "$IMPORT" 2>&1); RC=$?

  assert_exit 2 $RC "exits 2 with no arguments"
  assert_contains "$OUTPUT" "Usage" "prints usage message"
cleanup

echo ""
echo "-- Round-trip: export then import --"
sandbox
  SID="roundtrip-001"
  SRC_ENC="-source-project"
  DST_ENC="-dest-project"
  mkdir -p "$FAKE_PROJECTS/$SRC_ENC/$SID/tool-results"
  echo '{"type":"user","message":"hello"}' > "$FAKE_PROJECTS/$SRC_ENC/$SID.jsonl"
  echo "result-data" > "$FAKE_PROJECTS/$SRC_ENC/$SID/tool-results/result.txt"

  # Export
  ARCHIVE="$SANDBOX/roundtrip.tar.gz"
  HOME="$FAKE_HOME" sh "$EXPORT" -o "$ARCHIVE" "$SID" >/dev/null 2>&1

  # Import to a different project path
  HOME="$FAKE_HOME" sh "$IMPORT" "$ARCHIVE" "/dest/project" >/dev/null 2>&1

  # Verify content is identical
  ORIG=$(cat "$FAKE_PROJECTS/$SRC_ENC/$SID.jsonl")
  IMPORTED=$(cat "$FAKE_PROJECTS/$DST_ENC/$SID.jsonl" 2>/dev/null)
  if [ "$ORIG" = "$IMPORTED" ]; then pass "round-trip preserves .jsonl content"; else fail "round-trip preserves .jsonl content"; fi

  ORIG_RESULT=$(cat "$FAKE_PROJECTS/$SRC_ENC/$SID/tool-results/result.txt")
  IMPORTED_RESULT=$(cat "$FAKE_PROJECTS/$DST_ENC/$SID/tool-results/result.txt" 2>/dev/null)
  if [ "$ORIG_RESULT" = "$IMPORTED_RESULT" ]; then pass "round-trip preserves session directory content"; else fail "round-trip preserves session directory content"; fi
cleanup

# ── Summary ──────────────────────────────────────────────────────────

echo ""
echo "========================================"
printf "Results: %d passed, %d failed, %d total\n" "$PASS" "$FAIL" "$TESTS"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
