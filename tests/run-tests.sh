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

# ── Summary ──────────────────────────────────────────────────────────

echo ""
echo "========================================"
printf "Results: %d passed, %d failed, %d total\n" "$PASS" "$FAIL" "$TESTS"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
