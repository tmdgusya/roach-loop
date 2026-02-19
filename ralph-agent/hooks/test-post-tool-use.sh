#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Setup
mkdir -p "$TMPDIR/.harness"
echo '{}' > "$TMPDIR/.harness/state.json"
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

echo "=== Testing post-tool-use.sh ==="

export HARNESS_STATE_DIR="$TMPDIR/.harness"

# Test 1: Normal edit (no loop)
INPUT=$(jq -n '{
  tool_name: "Edit",
  tool_input: { file_path: "/test/src/app.ts", old_string: "a", new_string: "b" },
  tool_response: { success: true },
  cwd: "'"$TMPDIR"'",
  hook_event_name: "PostToolUse"
}')

OUTPUT=$(echo "$INPUT" | bash "$SCRIPT_DIR/post-tool-use.sh" 2>/dev/null)
COUNT=$(jq -r '.["/test/src/app.ts"] // 0' "$TMPDIR/.harness/edit-tracker.json")
assert_eq "edit count incremented" "1" "$COUNT"

# Test 2: Trace logged
TRACE_LINES=$(wc -l < "$TMPDIR/.harness/trace-log.jsonl")
assert_eq "trace logged" "1" "$(echo $TRACE_LINES | tr -d ' ')"

# Test 3: Loop detection (hit threshold)
# Edit same file 5 more times (total 6, threshold is 5)
for i in $(seq 2 6); do
  echo "$INPUT" | bash "$SCRIPT_DIR/post-tool-use.sh" > /dev/null 2>&1
done

OUTPUT=$(echo "$INPUT" | bash "$SCRIPT_DIR/post-tool-use.sh" 2>/dev/null)
assert_contains "loop warning injected" "reconsider" "$OUTPUT"

# Test 4: Non-edit tool (Read) should not increment
READ_INPUT=$(jq -n '{
  tool_name: "Read",
  tool_input: { file_path: "/test/README.md" },
  tool_response: { content: "hello" },
  cwd: "'"$TMPDIR"'",
  hook_event_name: "PostToolUse"
}')

echo "$READ_INPUT" | bash "$SCRIPT_DIR/post-tool-use.sh" > /dev/null 2>&1
READ_COUNT=$(jq -r '.["/test/README.md"] // 0' "$TMPDIR/.harness/edit-tracker.json")
assert_eq "read does not increment edit count" "0" "$READ_COUNT"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
