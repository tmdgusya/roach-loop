#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

mkdir -p "$TMPDIR/.harness"
cat > "$TMPDIR/.harness/state.json" << 'EOF'
{
  "phase": "executing",
  "discovered_verification_commands": [],
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

# Simulate successful ruff run — now sets tests_passed (folded into verification)
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

INPUT_LINT=$(jq -n '{
  tool_name: "Bash",
  tool_input: { command: "ruff check ." },
  tool_response: { stdout: "All checks passed", exit_code: 0 },
  cwd: "'"$TMPDIR"'",
  hook_event_name: "PostToolUse"
}')

echo "$INPUT_LINT" | bash "$SCRIPT_DIR/post-tool-use.sh" > /dev/null 2>&1

# Lint is now folded into tests_passed (matches_verification_command includes lint patterns)
TESTS_PASSED_AFTER_LINT=$(jq -r '.verification_status.tests_passed' "$TMPDIR/.harness/state.json")
assert_eq "ruff check . sets tests_passed=true (lint folded into verification)" "true" "$TESTS_PASSED_AFTER_LINT"

# Test: ralph:verify-complete marker sets tests_passed=true
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

INPUT_MARKER=$(jq -n '{
  tool_name: "Bash",
  tool_input: { command: "echo '\''ralph:verify-complete'\''" },
  tool_response: { stdout: "ralph:verify-complete", exit_code: 0 },
  cwd: "'"$TMPDIR"'",
  hook_event_name: "PostToolUse"
}')

echo "$INPUT_MARKER" | bash "$SCRIPT_DIR/post-tool-use.sh" > /dev/null 2>&1

MARKER_PASSED=$(jq -r '.verification_status.tests_passed' "$TMPDIR/.harness/state.json")
assert_eq "ralph:verify-complete sets tests_passed=true" "true" "$MARKER_PASSED"

# Test: custom verification_commands pattern is recognized (HARNESS_VERIFICATION_COMMANDS)
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

INPUT_CUSTOM=$(jq -n '{
  tool_name: "Bash",
  tool_input: { command: "my-custom-verify --all" },
  tool_response: { stdout: "OK", exit_code: 0 },
  cwd: "'"$TMPDIR"'",
  hook_event_name: "PostToolUse"
}')

echo "$INPUT_CUSTOM" | HARNESS_VERIFICATION_COMMANDS='["my-custom-verify"]' bash "$SCRIPT_DIR/post-tool-use.sh" > /dev/null 2>&1

CUSTOM_PASSED=$(jq -r '.verification_status.tests_passed' "$TMPDIR/.harness/state.json")
assert_eq "custom verification_commands pattern recognized" "true" "$CUSTOM_PASSED"

# Test: discovered command from state is recognized
cat > "$TMPDIR/.harness/state.json" << 'EOF'
{
  "phase": "executing",
  "discovered_verification_commands": ["my-project-test --ci"],
  "verification_status": {
    "tests_run": false,
    "tests_passed": false,
    "lint_run": false,
    "lint_passed": false
  }
}
EOF

INPUT_DISCOVERED=$(jq -n '{
  tool_name: "Bash",
  tool_input: { command: "my-project-test --ci --verbose" },
  tool_response: { stdout: "all pass", exit_code: 0 },
  cwd: "'"$TMPDIR"'",
  hook_event_name: "PostToolUse"
}')

echo "$INPUT_DISCOVERED" | bash "$SCRIPT_DIR/post-tool-use.sh" > /dev/null 2>&1

DISCOVERED_PASSED=$(jq -r '.verification_status.tests_passed' "$TMPDIR/.harness/state.json")
assert_eq "discovered command from state is recognized" "true" "$DISCOVERED_PASSED"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
