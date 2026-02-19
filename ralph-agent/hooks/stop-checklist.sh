#!/usr/bin/env bash
# ralph-agent/hooks/stop-checklist.sh
# PreCompletionChecklist (Stop Hook)
#
# Harness Engineering Concept: "Always Challenge Once"
# On the FIRST stop attempt: always emit a contextual challenge (exit 2).
# On the SECOND stop attempt: stop_hook_active=true breaks the loop (exit 0).
#
# Challenge tone varies by state:
#   - Tests passed: light confirmation prompt
#   - Tests failed or not run + commands exist: strong "run them NOW"
#   - No commands at all: generic "verify manually"
#
# CRITICAL: Must check stop_hook_active to prevent infinite loops.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/state.sh"

INPUT=$(cat)
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
CWD=$(echo "$INPUT" | jq -r '.cwd // "."')

export HARNESS_STATE_DIR="${CWD}/.harness"

# CRITICAL: Prevent infinite loop — second attempt always passes through
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

# Skip if checklist is disabled
if [ "$HARNESS_CHECKLIST_ENABLED" != "true" ]; then
  exit 0
fi

# Skip if state dir doesn't exist (not a harness-managed project)
if [ ! -d "$HARNESS_STATE_DIR" ]; then
  exit 0
fi

# --- Read current state ---
TESTS_RUN=$(read_state ".verification_status.tests_run")
TESTS_PASSED=$(read_state ".verification_status.tests_passed")
DISCOVERED_CMDS=$(read_state ".discovered_verification_commands")
CMD_COUNT=$(echo "${DISCOVERED_CMDS:-[]}" | jq 'length' 2>/dev/null || echo 0)

# --- Build contextual challenge message ---
MSG=""

if [ "$TESTS_RUN" = "true" ] && [ "$TESTS_PASSED" = "true" ]; then
  # Light challenge: verification passed, confirm quality
  MSG="VERIFICATION PASSED. Before stopping, confirm:
- Your changes match the requirements
- No TODOs or placeholders left in code
- Edge cases are covered"

elif [ "$CMD_COUNT" -gt 0 ]; then
  # Strong challenge: list the discovered commands
  CMD_LIST=$(echo "${DISCOVERED_CMDS:-[]}" | jq -r '.[]' 2>/dev/null | sed 's/^/  - /' || true)

  if [ "$TESTS_RUN" = "true" ] && [ "$TESTS_PASSED" != "true" ]; then
    MSG="VERIFICATION NOT CONFIRMED: Tests ran but FAILED. Fix failures before stopping.

Discovered verification commands:
$CMD_LIST"
  else
    MSG="VERIFICATION NOT CONFIRMED: None of the verification commands were run.
Run them NOW:
$CMD_LIST"
  fi

else
  # Generic challenge: no commands discovered
  MSG="VERIFICATION NOT CONFIRMED: No verification commands found. Verify your changes manually before stopping.

If you have verified manually, run: echo 'ralph:verify-complete'"
fi

# --- Append remaining tasks warning (gated by require_plan_check) ---
if [ "$HARNESS_REQUIRE_PLAN_CHECK" = "true" ]; then
  if [ -f "$CWD/IMPLEMENTATION_PLAN.md" ]; then
    REMAINING=$(grep -c '^\- \[ \]' "$CWD/IMPLEMENTATION_PLAN.md" 2>/dev/null || echo "0")
    if [ "$REMAINING" -gt 0 ]; then
      NEXT=$(grep '^\- \[ \]' "$CWD/IMPLEMENTATION_PLAN.md" 2>/dev/null | head -1 | sed 's/^- \[ \] //')
      MSG+="

WARNING: $REMAINING unchecked task(s) remaining. Next: $NEXT"
    fi
  fi
fi

echo -e "$MSG" >&2
exit 2
