#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASS=0
FAIL=0

assert_true() {
  local desc="$1" condition="$2"
  if [ "$condition" = "true" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Testing thin ralph prompt ==="

RALPH_MD="$SCRIPT_DIR/agents/ralph.md"

# Check file exists
assert_true "ralph.md exists" "$([ -f "$RALPH_MD" ] && echo true || echo false)"

# Check it's shorter (under 200 lines = thinner than current 344)
LINE_COUNT=$(wc -l < "$RALPH_MD" | tr -d ' ')
assert_true "ralph.md is thinner (<200 lines, actual=$LINE_COUNT)" "$([ "$LINE_COUNT" -lt 200 ] && echo true || echo false)"

# Check key concepts are still present
assert_true "mentions TDD" "$(grep -q 'TDD' "$RALPH_MD" && echo true || echo false)"
assert_true "mentions IMPLEMENTATION_PLAN" "$(grep -q 'IMPLEMENTATION_PLAN' "$RALPH_MD" && echo true || echo false)"
assert_true "mentions AGENTS.md" "$(grep -q 'AGENTS.md' "$RALPH_MD" && echo true || echo false)"
assert_true "mentions Red-Green-Refactor" "$(grep -qi 'red.*green.*refactor\|RED.*GREEN' "$RALPH_MD" && echo true || echo false)"

# Check it references hooks handling enforcement
assert_true "mentions hooks" "$(grep -qi 'hook\|harness\|scaffold' "$RALPH_MD" && echo true || echo false)"

# Check verbose enforcement text is REMOVED
FORBIDDEN_COUNT=$(grep -c 'FORBIDDEN' "$RALPH_MD" || true)
assert_true "no verbose TDD violation list" "$([ "$FORBIDDEN_COUNT" -eq 0 ] && echo true || echo false)"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
