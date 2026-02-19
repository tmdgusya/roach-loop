#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

mkdir -p "$TMPDIR/.harness"
echo '{}' > "$TMPDIR/.harness/state.json"
echo '{}' > "$TMPDIR/.harness/edit-tracker.json"
touch "$TMPDIR/.harness/trace-log.jsonl"

PASS=0
FAIL=0

assert_exit_code() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected exit=$expected, actual=$actual)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Testing pre-tool-use.sh ==="

export HARNESS_STATE_DIR="$TMPDIR/.harness"

# Test 1: Block write to .env
INPUT=$(jq -n '{
  tool_name: "Write",
  tool_input: { file_path: "'"$TMPDIR"'/.env", content: "SECRET=abc" },
  cwd: "'"$TMPDIR"'",
  hook_event_name: "PreToolUse"
}')

set +e
echo "$INPUT" | bash "$SCRIPT_DIR/pre-tool-use.sh" > /dev/null 2>/dev/null
EXIT_CODE=$?
set -e
assert_exit_code "blocks .env write" "0" "$EXIT_CODE"
# Check for deny in output
OUTPUT=$(echo "$INPUT" | bash "$SCRIPT_DIR/pre-tool-use.sh" 2>/dev/null)
if echo "$OUTPUT" | grep -q '"deny"'; then
  echo "  PASS: deny decision for .env"
  PASS=$((PASS + 1))
else
  echo "  FAIL: should deny .env write"
  FAIL=$((FAIL + 1))
fi

# Test 2: Allow normal file write
INPUT_NORMAL=$(jq -n '{
  tool_name: "Write",
  tool_input: { file_path: "'"$TMPDIR"'/src/app.ts", content: "console.log(1)" },
  cwd: "'"$TMPDIR"'",
  hook_event_name: "PreToolUse"
}')

set +e
echo "$INPUT_NORMAL" | bash "$SCRIPT_DIR/pre-tool-use.sh" > /dev/null 2>/dev/null
EXIT_CODE=$?
set -e
assert_exit_code "allows normal write" "0" "$EXIT_CODE"

# Test 3: Allow normal Bash
INPUT_BASH=$(jq -n '{
  tool_name: "Bash",
  tool_input: { command: "npm test" },
  cwd: "'"$TMPDIR"'",
  hook_event_name: "PreToolUse"
}')

set +e
echo "$INPUT_BASH" | bash "$SCRIPT_DIR/pre-tool-use.sh" > /dev/null 2>/dev/null
EXIT_CODE=$?
set -e
assert_exit_code "allows normal bash" "0" "$EXIT_CODE"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
