#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

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

echo "=== Testing pre-compact.sh ==="

mkdir -p "$TMPDIR/.harness"
cat > "$TMPDIR/.harness/state.json" << 'EOF'
{
  "phase": "executing",
  "current_task": "Task 3: Add authentication",
  "tasks_completed": 2,
  "tasks_remaining": 5,
  "iteration": 3,
  "tdd_phase": "green"
}
EOF
echo '{}' > "$TMPDIR/.harness/edit-tracker.json"
touch "$TMPDIR/.harness/trace-log.jsonl"
echo '- `pytest tests/`' > "$TMPDIR/AGENTS.md"

export HARNESS_STATE_DIR="$TMPDIR/.harness"

INPUT=$(jq -n '{
  trigger: "auto",
  cwd: "'"$TMPDIR"'",
  hook_event_name: "PreCompact"
}')

OUTPUT=$(echo "$INPUT" | bash "$SCRIPT_DIR/pre-compact.sh" 2>/dev/null)

assert_contains "outputs JSON" "hookSpecificOutput" "$OUTPUT"
assert_contains "contains current task" "Task 3" "$OUTPUT"
assert_contains "contains progress" "2" "$OUTPUT"
assert_contains "contains TDD phase" "green" "$OUTPUT"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
