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

assert_stderr_contains() {
  local desc="$1" needle="$2" stderr_file="$3"
  if grep -qF "$needle" "$stderr_file" 2>/dev/null; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (needle='$needle' not found in stderr)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Testing stop-checklist.sh (Always Challenge Once) ==="

# --- Helper: base state setup ---
setup_state() {
  mkdir -p "$TMPDIR/.harness"
  cat > "$TMPDIR/.harness/state.json" << 'EOF'
{
  "phase": "executing",
  "discovered_verification_commands": [],
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
}

export HARNESS_STATE_DIR="$TMPDIR/.harness"
STOP_INPUT=$(jq -n '{stop_hook_active: false, cwd: "'"$TMPDIR"'", hook_event_name: "Stop"}')
STOP_ACTIVE_INPUT=$(jq -n '{stop_hook_active: true, cwd: "'"$TMPDIR"'", hook_event_name: "Stop"}')

# Test 1: First attempt with tests NOT run + no discovered commands → exit 2, generic message
setup_state
echo '- [x] Task 1: done' > "$TMPDIR/IMPLEMENTATION_PLAN.md"

set +e
echo "$STOP_INPUT" | bash "$SCRIPT_DIR/stop-checklist.sh" 2>/tmp/stop-stderr-1
EXIT_CODE=$?
set -e

assert_exit_code "no-commands: first attempt exits 2" "2" "$EXIT_CODE"
assert_stderr_contains "no-commands: stderr has VERIFICATION NOT CONFIRMED" "VERIFICATION NOT CONFIRMED" /tmp/stop-stderr-1
assert_stderr_contains "no-commands: suggests manual verify" "Verify" /tmp/stop-stderr-1

# Test 2: First attempt with tests passed + tasks done → exit 2 (light challenge)
setup_state
cat > "$TMPDIR/.harness/state.json" << 'EOF'
{
  "phase": "executing",
  "discovered_verification_commands": [],
  "verification_status": {
    "tests_run": true,
    "tests_passed": true,
    "lint_run": false,
    "lint_passed": false
  }
}
EOF
echo '- [x] Task 1: done' > "$TMPDIR/IMPLEMENTATION_PLAN.md"

set +e
echo "$STOP_INPUT" | bash "$SCRIPT_DIR/stop-checklist.sh" 2>/tmp/stop-stderr-2
EXIT_CODE=$?
set -e

assert_exit_code "tests-passed: first attempt still exits 2 (challenge once)" "2" "$EXIT_CODE"
assert_stderr_contains "tests-passed: stderr contains 'confirm'" "confirm" /tmp/stop-stderr-2

# Test 3: Second attempt (stop_hook_active=true) → exit 0
setup_state

set +e
echo "$STOP_ACTIVE_INPUT" | bash "$SCRIPT_DIR/stop-checklist.sh" > /dev/null 2>&1
EXIT_CODE=$?
set -e

assert_exit_code "stop_hook_active=true: exits 0 (loop break)" "0" "$EXIT_CODE"

# Test 4: HARNESS_CHECKLIST_ENABLED=false → exit 0
setup_state

set +e
HARNESS_CHECKLIST_ENABLED=false bash "$SCRIPT_DIR/stop-checklist.sh" <<< "$STOP_INPUT" > /dev/null 2>&1
EXIT_CODE=$?
set -e

assert_exit_code "checklist disabled: exits 0" "0" "$EXIT_CODE"

# Test 5: Remaining tasks warning appended to challenge message
setup_state
echo '- [ ] Task 1: still pending' > "$TMPDIR/IMPLEMENTATION_PLAN.md"
echo '- [x] Task 2: done' >> "$TMPDIR/IMPLEMENTATION_PLAN.md"

set +e
echo "$STOP_INPUT" | bash "$SCRIPT_DIR/stop-checklist.sh" 2>/tmp/stop-stderr-5
EXIT_CODE=$?
set -e

assert_exit_code "remaining-tasks: exits 2" "2" "$EXIT_CODE"
assert_stderr_contains "remaining-tasks: warning in message" "WARNING" /tmp/stop-stderr-5
assert_stderr_contains "remaining-tasks: task name in message" "Task 1" /tmp/stop-stderr-5

# Test 6: No .harness dir → exit 0
rm -rf "$TMPDIR/.harness"

set +e
echo "$STOP_INPUT" | bash "$SCRIPT_DIR/stop-checklist.sh" > /dev/null 2>&1
EXIT_CODE=$?
set -e

assert_exit_code "no-harness-dir: exits 0" "0" "$EXIT_CODE"

# Recreate state dir for remaining tests
setup_state

# Test 7: Discovered commands listed in strong challenge (tests not run)
cat > "$TMPDIR/.harness/state.json" << 'EOF'
{
  "phase": "executing",
  "discovered_verification_commands": ["pytest tests/", "ruff check ."],
  "verification_status": {
    "tests_run": false,
    "tests_passed": false,
    "lint_run": false,
    "lint_passed": false
  }
}
EOF
echo '- [x] Task 1: done' > "$TMPDIR/IMPLEMENTATION_PLAN.md"

set +e
echo "$STOP_INPUT" | bash "$SCRIPT_DIR/stop-checklist.sh" 2>/tmp/stop-stderr-7
EXIT_CODE=$?
set -e

assert_exit_code "with-commands: exits 2" "2" "$EXIT_CODE"
assert_stderr_contains "with-commands: lists pytest" "pytest tests/" /tmp/stop-stderr-7
assert_stderr_contains "with-commands: lists ruff" "ruff check ." /tmp/stop-stderr-7
assert_stderr_contains "with-commands: says Run them NOW" "Run them NOW" /tmp/stop-stderr-7

# Test 8: Tests ran but failed + commands exist → strong challenge with failure message
cat > "$TMPDIR/.harness/state.json" << 'EOF'
{
  "phase": "executing",
  "discovered_verification_commands": ["pytest tests/"],
  "verification_status": {
    "tests_run": true,
    "tests_passed": false,
    "lint_run": false,
    "lint_passed": false
  }
}
EOF

set +e
echo "$STOP_INPUT" | bash "$SCRIPT_DIR/stop-checklist.sh" 2>/tmp/stop-stderr-8
EXIT_CODE=$?
set -e

assert_exit_code "tests-failed: exits 2" "2" "$EXIT_CODE"
assert_stderr_contains "tests-failed: mentions FAILED" "FAILED" /tmp/stop-stderr-8

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
