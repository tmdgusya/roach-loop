#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/state.sh"

PASS=0
FAIL=0
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

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

echo "=== Testing config.sh ==="
assert_eq "LOOP_THRESHOLD is set" "true" "$([ -n "$HARNESS_LOOP_THRESHOLD" ] && echo true || echo false)"
assert_eq "LOOP_THRESHOLD is number" "true" "$([ "$HARNESS_LOOP_THRESHOLD" -gt 0 ] 2>/dev/null && echo true || echo false)"

echo ""
echo "=== Testing state.sh ==="

# Test init_harness_state
export HARNESS_STATE_DIR="$TMPDIR/.harness"
init_harness_state
assert_eq "state.json created" "true" "$([ -f "$HARNESS_STATE_DIR/state.json" ] && echo true || echo false)"
assert_eq "edit-tracker.json created" "true" "$([ -f "$HARNESS_STATE_DIR/edit-tracker.json" ] && echo true || echo false)"
assert_eq "trace-log.jsonl created" "true" "$([ -f "$HARNESS_STATE_DIR/trace-log.jsonl" ] && echo true || echo false)"

# Test read/write state
write_state ".phase" '"executing"'
PHASE=$(read_state ".phase")
assert_eq "write/read state" "executing" "$PHASE"

# Test increment_edit_count
increment_edit_count "/path/to/file.ts"
increment_edit_count "/path/to/file.ts"
increment_edit_count "/path/to/file.ts"
COUNT=$(get_edit_count "/path/to/file.ts")
assert_eq "edit count tracked" "3" "$COUNT"

# Test check_loop_detected
LOOP=$(check_loop_detected "/path/to/file.ts")
assert_eq "no loop at 3 edits (threshold=$HARNESS_LOOP_THRESHOLD)" "false" "$LOOP"

# Push to threshold
for i in $(seq 4 "$HARNESS_LOOP_THRESHOLD"); do
  increment_edit_count "/path/to/file.ts"
done
LOOP=$(check_loop_detected "/path/to/file.ts")
assert_eq "loop detected at threshold" "true" "$LOOP"

# Test append_trace
append_trace "Edit" '{"file_path":"/test.ts"}' "success"
LINES=$(wc -l < "$HARNESS_STATE_DIR/trace-log.jsonl")
assert_eq "trace appended" "1" "$(echo $LINES | tr -d ' ')"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
