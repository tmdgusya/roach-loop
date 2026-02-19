# Harness Session Reset Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reset the correct `.harness` files on each fresh session start so loop detection and verification status are per-session, not cumulative.

**Architecture:** `session-start.sh` already distinguishes `source=resume` from `source=startup` — add reset logic for fresh starts only. The `edit-tracker.json` must clear on fresh start so the loop detection threshold (5 edits) doesn't fire immediately on files that were heavily edited in prior sessions. `verification_status` in `state.json` must also reset so the stop checklist requires fresh evidence each session. `trace-log.jsonl` is appended-to (not reset) since it is a bounded audit log.

**Tech Stack:** Bash, jq, `.harness/` state files, `ralph-agent/hooks/`

---

## Why This Bug Matters

Current `.harness/edit-tracker.json`:
```json
{
  "/Users/lit/roach-loop/ralph-agent/agents/geoff-planner.md": 13
}
```

The loop detection threshold is 5. This means `geoff-planner.md` will trigger a "doom loop" warning on the **very first edit** of a new session. That is a false positive. Loop detection should track edits **within a session**, not across all sessions.

## Reset Semantics (what should happen)

| File | On fresh start (`source=startup`) | On resume (`source=resume`) |
|------|-----------------------------------|------------------------------|
| `edit-tracker.json` | **RESET** to `{}` | keep as-is |
| `state.json` `.verification_status` | **RESET** (all false/null) | keep as-is |
| `state.json` session/task fields | overwrite with new values | overwrite |
| `trace-log.jsonl` | **KEEP** (audit log, 10MB bounded) | keep |

---

### Task 1: Add `reset_session_state()` to `lib/state.sh`

**Files:**
- Modify: `ralph-agent/hooks/lib/state.sh`
- Create: `ralph-agent/hooks/test-session-reset.sh`

**Step 1: Write the failing test**

Create `ralph-agent/hooks/test-session-reset.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/state.sh"

PASS=0
FAIL=0
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    ((PASS++))
  else
    echo "  FAIL: $desc (expected='$expected', actual='$actual')"
    ((FAIL++))
  fi
}

echo "=== Testing reset_session_state ==="

export HARNESS_STATE_DIR="$TMPDIR"

# Seed stale state
echo '{"someFile.ts": 9, "other.ts": 3}' > "$TMPDIR/edit-tracker.json"
cp "$PLUGIN_ROOT/harness/templates/state.json.template" "$TMPDIR/state.json"
# Inject stale verification data
jq '
  .verification_status.tests_run = true |
  .verification_status.tests_passed = true |
  .verification_status.lint_run = true |
  .verification_status.lint_passed = true |
  .verification_status.last_verified_at = "2026-01-01T00:00:00Z"
' "$TMPDIR/state.json" > "$TMPDIR/state.json.tmp" && mv "$TMPDIR/state.json.tmp" "$TMPDIR/state.json"

reset_session_state

# Verify edit-tracker is empty
EDIT_COUNT=$(jq 'length' "$TMPDIR/edit-tracker.json")
assert_eq "edit-tracker cleared" "0" "$EDIT_COUNT"

# Verify verification_status is reset
TESTS_PASSED=$(jq -r '.verification_status.tests_passed' "$TMPDIR/state.json")
LINT_PASSED=$(jq -r '.verification_status.lint_passed' "$TMPDIR/state.json")
LAST_VERIFIED=$(jq -r '.verification_status.last_verified_at' "$TMPDIR/state.json")
assert_eq "tests_passed reset to false" "false" "$TESTS_PASSED"
assert_eq "lint_passed reset to false" "false" "$LINT_PASSED"
assert_eq "last_verified_at reset to null" "null" "$LAST_VERIFIED"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
```

**Step 2: Run test to verify it fails**

Run: `bash ralph-agent/hooks/test-session-reset.sh`
Expected: `FAIL: reset_session_state: command not found` (or similar)

**Step 3: Implement `reset_session_state` in `lib/state.sh`**

Add after the existing `reset_edit_tracker()` function:

```bash
reset_session_state() {
  # Reset edit-tracker so loop detection is per-session, not cumulative.
  # A file edited N times last session should not trigger loop detection
  # on the first edit of a new session.
  echo '{}' > "$HARNESS_STATE_DIR/edit-tracker.json"

  # Reset verification_status so the stop checklist requires fresh evidence
  # each session. Stale "tests_passed=true" from a prior session should not
  # count as proof for the current session.
  local tmp="$HARNESS_STATE_DIR/state.json.tmp"
  jq '
    .verification_status.tests_run = false |
    .verification_status.tests_passed = false |
    .verification_status.lint_run = false |
    .verification_status.lint_passed = false |
    .verification_status.last_verified_at = null
  ' "$HARNESS_STATE_DIR/state.json" > "$tmp" && mv "$tmp" "$HARNESS_STATE_DIR/state.json"
}
```

**Step 4: Run test to verify it passes**

Run: `bash ralph-agent/hooks/test-session-reset.sh`
Expected: All `PASS`

**Step 5: Commit**

```bash
git add ralph-agent/hooks/lib/state.sh ralph-agent/hooks/test-session-reset.sh
git commit -m "feat: add reset_session_state to clear per-session harness state"
```

---

### Task 2: Call `reset_session_state` on fresh session start

**Files:**
- Modify: `ralph-agent/hooks/session-start.sh`

**Step 1: Write tests for startup vs resume behavior**

Add two test cases to `ralph-agent/hooks/test-session-start.sh`. Open the existing file and add after the existing tests:

```bash
echo "=== Testing startup resets edit-tracker ==="

# Seed stale edit counts
echo '{"bloated.ts": 99}' > "$TMPDIR/.harness/edit-tracker.json"

# Simulate fresh startup
echo '{"session_id":"abc","cwd":"'"$TMPDIR"'","source":"startup"}' \
  | bash "$SCRIPT_DIR/session-start.sh" > /dev/null

COUNT=$(jq -r '."bloated.ts" // 0' "$TMPDIR/.harness/edit-tracker.json")
assert_eq "edit-tracker cleared on startup" "0" "$COUNT"

echo "=== Testing resume preserves edit-tracker ==="

# Re-seed
echo '{"bloated.ts": 3}' > "$TMPDIR/.harness/edit-tracker.json"

# Simulate resume
echo '{"session_id":"abc","cwd":"'"$TMPDIR"'","source":"resume"}' \
  | bash "$SCRIPT_DIR/session-start.sh" > /dev/null

COUNT=$(jq -r '."bloated.ts" // 0' "$TMPDIR/.harness/edit-tracker.json")
assert_eq "edit-tracker preserved on resume" "3" "$COUNT"
```

**Step 2: Run tests to verify they fail**

Run: `bash ralph-agent/hooks/test-session-start.sh 2>&1 | tail -10`
Expected: the two new assertions FAIL (edit-tracker is not cleared yet)

**Step 3: Add reset call in `session-start.sh`**

In `ralph-agent/hooks/session-start.sh`, after the `init_harness_state` call (line 34), insert:

```bash
# Per-session state reset:
# - edit-tracker: counts are per-session; reset prevents cross-session false positives
# - verification_status: stop-checklist must see fresh evidence each session
# On "resume": preserve state so in-flight work continues correctly
if [ "$SOURCE" != "resume" ]; then
  reset_session_state
fi
```

**Step 4: Run tests to verify they pass**

Run: `bash ralph-agent/hooks/test-session-start.sh 2>&1 | grep -E "PASS|FAIL"`
Expected: all `PASS`

**Step 5: Verify the current `.harness` state is now correct**

Run: `cat .harness/edit-tracker.json`
Expected: `{}` — the previous session's stale counts are gone since `session-start.sh` ran at this session's startup.

**Step 6: Commit**

```bash
git add ralph-agent/hooks/session-start.sh ralph-agent/hooks/test-session-start.sh
git commit -m "fix: reset edit-tracker and verification_status on fresh session start"
```

---

### Task 3: Run the full integration test suite

**Step 1: Run all hook tests**

```bash
bash ralph-agent/hooks/test-integration.sh
```
Expected: All tests pass

**Step 2: Run unit tests for good measure**

```bash
bash ralph-agent/hooks/lib/test-libs.sh
bash ralph-agent/hooks/test-session-reset.sh
bash ralph-agent/hooks/test-session-start.sh
bash ralph-agent/hooks/test-pre-tool-use.sh
bash ralph-agent/hooks/test-post-tool-use.sh
bash ralph-agent/hooks/test-stop-checklist.sh
bash ralph-agent/hooks/test-pre-compact.sh
bash ralph-agent/hooks/test-verification-tracking.sh
```
Expected: All pass

**Step 3: Commit if any test file was updated**

```bash
git add -u
git commit -m "test: confirm all hook tests pass after session reset implementation"
```
