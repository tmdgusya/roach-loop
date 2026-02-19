#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

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

echo "=== Testing hooks.json structure ==="

# Verify hooks.json exists and is valid JSON
assert_eq "hooks.json exists" "true" "$([ -f "$SCRIPT_DIR/hooks.json" ] && echo true || echo false)"

if [ -f "$SCRIPT_DIR/hooks.json" ]; then
  jq empty "$SCRIPT_DIR/hooks.json" 2>/dev/null
  assert_eq "hooks.json is valid JSON" "0" "$?"

  # Check all events are registered (hooks.json has a top-level "hooks" key)
  EVENTS=$(jq -r '.hooks | keys[]' "$SCRIPT_DIR/hooks.json" 2>/dev/null)
  for event in SessionStart PreToolUse PostToolUse Stop PreCompact; do
    if echo "$EVENTS" | grep -q "$event"; then
      echo "  PASS: $event registered"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: $event not registered"
      FAIL=$((FAIL + 1))
    fi
  done
fi

# Verify all hook scripts exist and are executable
echo ""
echo "=== Testing hook scripts ==="
for script in session-start.sh pre-tool-use.sh post-tool-use.sh stop-checklist.sh pre-compact.sh; do
  FULL_PATH="$SCRIPT_DIR/$script"
  assert_eq "$script exists" "true" "$([ -f "$FULL_PATH" ] && echo true || echo false)"
  assert_eq "$script executable" "true" "$([ -x "$FULL_PATH" ] && echo true || echo false)"
done

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
