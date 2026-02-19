#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Create a fake project structure with AGENTS.md for discovery
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

# Verify discovered_verification_commands written to state
echo ""
echo "=== Test: discovery writes to state ==="

DISC_CMDS=$(jq -r '.discovered_verification_commands' "$TMPDIR/.harness/state.json")
if echo "$DISC_CMDS" | grep -q "pytest"; then
  echo "  PASS: discovered_verification_commands written to state (contains pytest)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: discovered_verification_commands not written to state (got: $DISC_CMDS)"
  FAIL=$((FAIL + 1))
fi

HAS_INFRA=$(jq -r '.has_test_infra' "$TMPDIR/.harness/state.json")
if [ "$HAS_INFRA" = "true" ]; then
  echo "  PASS: has_test_infra=true written to state"
  PASS=$((PASS + 1))
else
  echo "  FAIL: has_test_infra should be true (got: $HAS_INFRA)"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Test: startup resets edit-tracker and verification_status ==="

# Seed edit-tracker with stale data
echo '{"bloated.ts": 99}' > "$HARNESS_STATE_DIR/edit-tracker.json"

# Seed state.json with stale verification_status
SEEDED_STATE=$(jq '.verification_status.tests_passed = true' "$TMPDIR/.harness/state.json")
echo "$SEEDED_STATE" > "$TMPDIR/.harness/state.json"

# Simulate fresh startup
echo '{"session_id":"abc","cwd":"'"$TMPDIR"'","source":"startup"}' | bash "$SCRIPT_DIR/session-start.sh" > /dev/null

# Assert edit-tracker bloated.ts is 0 or missing
BLOATED_COUNT=$(jq -r '."bloated.ts" // 0' "$HARNESS_STATE_DIR/edit-tracker.json")
if [ "$BLOATED_COUNT" -eq 0 ] 2>/dev/null; then
  echo "  PASS: startup resets edit-tracker (bloated.ts count is 0 or missing)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: startup resets edit-tracker (bloated.ts count is '$BLOATED_COUNT', expected 0)"
  FAIL=$((FAIL + 1))
fi

# Assert verification_status.tests_passed is false
TESTS_PASSED=$(jq -r 'if .verification_status.tests_passed == false then "false" else "not-false" end' "$TMPDIR/.harness/state.json")
if [ "$TESTS_PASSED" = "false" ]; then
  echo "  PASS: startup resets verification_status.tests_passed to false"
  PASS=$((PASS + 1))
else
  echo "  FAIL: startup resets verification_status.tests_passed (expected false)"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Test: resume preserves edit-tracker ==="

# Re-seed edit-tracker with data that should survive a resume
echo '{"bloated.ts": 3}' > "$HARNESS_STATE_DIR/edit-tracker.json"

# Simulate resume
echo '{"session_id":"abc","cwd":"'"$TMPDIR"'","source":"resume"}' | bash "$SCRIPT_DIR/session-start.sh" > /dev/null

# Assert bloated.ts count is still 3
RESUME_COUNT=$(jq -r '."bloated.ts" // 0' "$HARNESS_STATE_DIR/edit-tracker.json")
if [ "$RESUME_COUNT" -eq 3 ] 2>/dev/null; then
  echo "  PASS: resume preserves edit-tracker (bloated.ts count is still 3)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: resume preserves edit-tracker (bloated.ts count is '$RESUME_COUNT', expected 3)"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
