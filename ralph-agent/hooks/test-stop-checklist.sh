#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

PASS=0
FAIL=0

assert_exit_code() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected exit=$expected, actual exit=$actual)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Testing stop-checklist.sh ==="

# Setup: state with verification NOT done
mkdir -p "$TMPDIR/.harness"
cat > "$TMPDIR/.harness/state.json" << 'EOF'
{
  "phase": "executing",
  "verification_status": {
    "tests_run": false,
    "tests_passed": false,
    "lint_run": false,
    "lint_passed": false
  }
}
EOF
echo '{}' > "$TMPDIR/.harness/edit-tracker.json"
touch "$TMPDIR/.harness/trace-log.jsonl"
echo '- [ ] Task 1: pending' > "$TMPDIR/IMPLEMENTATION_PLAN.md"

export HARNESS_STATE_DIR="$TMPDIR/.harness"

# Test 1: Block stop when verification not done
INPUT=$(jq -n '{
  stop_hook_active: false,
  last_assistant_message: "I have completed the task.",
  cwd: "'"$TMPDIR"'",
  hook_event_name: "Stop"
}')

set +e
OUTPUT=$(echo "$INPUT" | bash "$SCRIPT_DIR/stop-checklist.sh" 2>/tmp/stop-stderr)
EXIT_CODE=$?
set -e

assert_exit_code "blocks stop without verification" "2" "$EXIT_CODE"

# Test 2: Allow stop when already in stop_hook_active
INPUT_ACTIVE=$(jq -n '{
  stop_hook_active: true,
  last_assistant_message: "Running verification now.",
  cwd: "'"$TMPDIR"'",
  hook_event_name: "Stop"
}')

set +e
echo "$INPUT_ACTIVE" | bash "$SCRIPT_DIR/stop-checklist.sh" > /dev/null 2>&1
EXIT_CODE=$?
set -e

assert_exit_code "allows when stop_hook_active=true" "0" "$EXIT_CODE"

# Test 3: Allow stop when all verified
cat > "$TMPDIR/.harness/state.json" << 'EOF'
{
  "phase": "executing",
  "verification_status": {
    "tests_run": true,
    "tests_passed": true,
    "lint_run": true,
    "lint_passed": true
  }
}
EOF
# All tasks done
echo '- [x] Task 1: done' > "$TMPDIR/IMPLEMENTATION_PLAN.md"

set +e
OUTPUT=$(echo "$INPUT" | bash "$SCRIPT_DIR/stop-checklist.sh" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_exit_code "allows stop when verified and tasks done" "0" "$EXIT_CODE"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
