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
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected='$expected', actual='$actual')"
    FAIL=$((FAIL + 1))
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
