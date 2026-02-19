#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then echo "  PASS: $desc"; PASS=$((PASS + 1))
  else echo "  FAIL: $desc (expected='$expected', actual='$actual')"; FAIL=$((FAIL + 1)); fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then echo "  PASS: $desc"; PASS=$((PASS + 1))
  else echo "  FAIL: $desc ('$needle' not found)"; FAIL=$((FAIL + 1)); fi
}

echo "════════════════════════════════════════════"
echo "  INTEGRATION TEST: Full Harness Lifecycle"
echo "════════════════════════════════════════════"
echo ""

# Setup fake project
mkdir -p "$TMPDIR/src" "$TMPDIR/tests"
echo '# Verification Commands' > "$TMPDIR/AGENTS.md"
echo '- `echo "tests pass"`' >> "$TMPDIR/AGENTS.md"
cat > "$TMPDIR/IMPLEMENTATION_PLAN.md" << 'EOF'
# Plan
- [ ] Task 1: Create hello module
- [ ] Task 2: Add greeting function
- [x] Task 3: Already done
EOF

export HARNESS_STATE_DIR="$TMPDIR/.harness"

# --- Phase 1: SessionStart ---
echo "Phase 1: SessionStart"

SESSION_INPUT=$(jq -n '{
  session_id: "integration-test",
  cwd: "'"$TMPDIR"'",
  hook_event_name: "SessionStart",
  source: "startup"
}')

OUTPUT=$(echo "$SESSION_INPUT" | bash "$SCRIPT_DIR/session-start.sh" 2>/dev/null)
assert_contains "context injected" "Project Structure" "$OUTPUT"
assert_contains "tasks detected" "Task 1" "$OUTPUT"

PHASE=$(jq -r '.phase' "$TMPDIR/.harness/state.json")
assert_eq "state phase=executing" "executing" "$PHASE"
echo ""

# --- Phase 2: PreToolUse (protection) ---
echo "Phase 2: PreToolUse Protection"

BLOCKED_INPUT=$(jq -n '{
  tool_name: "Write",
  tool_input: { file_path: "'"$TMPDIR"'/.env", content: "SECRET=x" },
  cwd: "'"$TMPDIR"'",
  hook_event_name: "PreToolUse"
}')

OUTPUT=$(echo "$BLOCKED_INPUT" | bash "$SCRIPT_DIR/pre-tool-use.sh" 2>/dev/null)
assert_contains ".env blocked" "deny" "$OUTPUT"
echo ""

# --- Phase 3: PostToolUse (loop detection) ---
echo "Phase 3: PostToolUse Loop Detection"

EDIT_INPUT=$(jq -n '{
  tool_name: "Edit",
  tool_input: { file_path: "/src/app.ts", old_string: "a", new_string: "b" },
  tool_response: { success: true },
  cwd: "'"$TMPDIR"'",
  hook_event_name: "PostToolUse"
}')

# Edit 6 times (threshold is 5)
for i in $(seq 1 6); do
  echo "$EDIT_INPUT" | bash "$SCRIPT_DIR/post-tool-use.sh" > /dev/null 2>&1
done

OUTPUT=$(echo "$EDIT_INPUT" | bash "$SCRIPT_DIR/post-tool-use.sh" 2>/dev/null)
assert_contains "loop warning" "reconsider" "$OUTPUT"
echo ""

# --- Phase 4: Stop (always challenge once) ---
echo "Phase 4: Stop Checklist"

STOP_INPUT=$(jq -n '{
  stop_hook_active: false,
  last_assistant_message: "Done!",
  cwd: "'"$TMPDIR"'",
  hook_event_name: "Stop"
}')
STOP_ACTIVE_INPUT=$(jq -n '{
  stop_hook_active: true,
  last_assistant_message: "Done!",
  cwd: "'"$TMPDIR"'",
  hook_event_name: "Stop"
}')

set +e
echo "$STOP_INPUT" | bash "$SCRIPT_DIR/stop-checklist.sh" > /dev/null 2>/dev/null
EXIT_CODE=$?
set -e
assert_eq "stop challenged first attempt (no verification)" "2" "$EXIT_CODE"

# Simulate verification passing
jq '.verification_status.tests_run = true | .verification_status.tests_passed = true | .verification_status.lint_run = true | .verification_status.lint_passed = true' \
  "$TMPDIR/.harness/state.json" > "$TMPDIR/.harness/state.json.tmp" && \
  mv "$TMPDIR/.harness/state.json.tmp" "$TMPDIR/.harness/state.json"

# Mark all tasks done (macOS-compatible sed)
sed -i '' 's/- \[ \]/- [x]/' "$TMPDIR/IMPLEMENTATION_PLAN.md"

# First attempt still challenges even when verified (always challenge once)
set +e
echo "$STOP_INPUT" | bash "$SCRIPT_DIR/stop-checklist.sh" > /dev/null 2>/dev/null
EXIT_CODE=$?
set -e
assert_eq "stop challenged even when verified (first attempt)" "2" "$EXIT_CODE"

# Second attempt with stop_hook_active=true passes through
set +e
echo "$STOP_ACTIVE_INPUT" | bash "$SCRIPT_DIR/stop-checklist.sh" > /dev/null 2>/dev/null
EXIT_CODE=$?
set -e
assert_eq "stop allowed on second attempt (stop_hook_active=true)" "0" "$EXIT_CODE"
echo ""

# --- Phase 5: PreCompact ---
echo "Phase 5: PreCompact"

COMPACT_INPUT=$(jq -n '{
  trigger: "auto",
  cwd: "'"$TMPDIR"'",
  hook_event_name: "PreCompact"
}')

OUTPUT=$(echo "$COMPACT_INPUT" | bash "$SCRIPT_DIR/pre-compact.sh" 2>/dev/null)
assert_contains "preserves state" "HARNESS STATE" "$OUTPUT"
echo ""

# --- Phase 6: Trace Analysis ---
echo "Phase 6: Trace Analysis"

TRACE_LINES=$(wc -l < "$TMPDIR/.harness/trace-log.jsonl" | tr -d ' ')
assert_eq "trace log has entries" "true" "$([ "$TRACE_LINES" -gt 0 ] && echo true || echo false)"

OUTPUT=$(bash "$SCRIPT_DIR/lib/analyze-trace.sh" "$TMPDIR/.harness/trace-log.jsonl" 2>/dev/null)
assert_contains "trace analysis runs" "TRACE ANALYSIS" "$OUTPUT"
echo ""

echo "════════════════════════════════════════════"
echo "  Results: $PASS passed, $FAIL failed"
echo "════════════════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
