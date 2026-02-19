#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

mkdir -p "$TMPDIR/.harness"
cat > "$TMPDIR/.harness/state.json" << 'EOF'
{
  "phase": "executing",
  "verification_status": {
    "tests_run": true,
    "tests_passed": false,
    "lint_run": false,
    "lint_passed": false
  }
}
EOF
echo '{}' > "$TMPDIR/.harness/edit-tracker.json"
touch "$TMPDIR/.harness/trace-log.jsonl"

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected='$expected', actual='$actual')"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Testing verification result tracking ==="

export HARNESS_STATE_DIR="$TMPDIR/.harness"

# Simulate successful test run result
INPUT=$(jq -n '{
  tool_name: "Bash",
  tool_input: { command: "pytest tests/ -v" },
  tool_response: { stdout: "5 passed", exit_code: 0 },
  cwd: "'"$TMPDIR"'",
  hook_event_name: "PostToolUse"
}')

echo "$INPUT" | bash "$SCRIPT_DIR/post-tool-use.sh" > /dev/null 2>&1

TESTS_PASSED=$(jq -r '.verification_status.tests_passed' "$TMPDIR/.harness/state.json")
assert_eq "tests_passed updated to true" "true" "$TESTS_PASSED"

# Simulate successful lint run
INPUT_LINT=$(jq -n '{
  tool_name: "Bash",
  tool_input: { command: "ruff check ." },
  tool_response: { stdout: "All checks passed", exit_code: 0 },
  cwd: "'"$TMPDIR"'",
  hook_event_name: "PostToolUse"
}')

echo "$INPUT_LINT" | bash "$SCRIPT_DIR/post-tool-use.sh" > /dev/null 2>&1

LINT_PASSED=$(jq -r '.verification_status.lint_passed' "$TMPDIR/.harness/state.json")
assert_eq "lint_passed updated to true" "true" "$LINT_PASSED"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
