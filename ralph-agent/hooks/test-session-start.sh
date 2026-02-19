#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Create a fake project structure
mkdir -p "$TMPDIR/src" "$TMPDIR/tests" "$TMPDIR/.harness"
echo '{}' > "$TMPDIR/.harness/state.json"
echo '{}' > "$TMPDIR/.harness/edit-tracker.json"
touch "$TMPDIR/.harness/trace-log.jsonl"
echo '# Verification Commands' > "$TMPDIR/AGENTS.md"
echo '- `pytest tests/`' >> "$TMPDIR/AGENTS.md"
echo '- [ ] Task 1: Do something' > "$TMPDIR/IMPLEMENTATION_PLAN.md"
echo '- [x] Task 2: Already done' >> "$TMPDIR/IMPLEMENTATION_PLAN.md"

PASS=0
FAIL=0

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (needle='$needle' not found)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Testing session-start.sh ==="

# Simulate SessionStart hook input
INPUT=$(jq -n '{
  session_id: "test-session-123",
  cwd: "'"$TMPDIR"'",
  hook_event_name: "SessionStart",
  source: "startup"
}')

export HARNESS_STATE_DIR="$TMPDIR/.harness"
OUTPUT=$(echo "$INPUT" | bash "$SCRIPT_DIR/session-start.sh" 2>/dev/null)

assert_contains "outputs JSON" "hookSpecificOutput" "$OUTPUT"
assert_contains "contains additionalContext" "additionalContext" "$OUTPUT"
assert_contains "contains directory structure" "src" "$OUTPUT"
assert_contains "contains verification commands" "pytest" "$OUTPUT"
assert_contains "contains task status" "Task 1" "$OUTPUT"

# Verify state was updated
STATE_PHASE=$(jq -r '.phase' "$TMPDIR/.harness/state.json")
assert_contains "state phase updated" "executing" "$STATE_PHASE"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
