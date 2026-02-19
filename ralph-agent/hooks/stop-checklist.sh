#!/usr/bin/env bash
# ralph-agent/hooks/stop-checklist.sh
# PreCompletionChecklist (Stop Hook)
#
# Harness Engineering Concept: "PreCompletionChecklistMiddleware"
# Intercepts the agent's attempt to stop and forces verification.
# If verification hasn't been run, blocks the stop (exit 2)
# and injects a checklist prompt.
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

# CRITICAL: Prevent infinite loop - if we already forced a retry, let it through
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

# --- Check Completion Criteria ---

BLOCKERS=""

# 1. Check if verification was run
TESTS_RUN=$(read_state ".verification_status.tests_run")
TESTS_PASSED=$(read_state ".verification_status.tests_passed")

if [ "$TESTS_RUN" != "true" ]; then
  BLOCKERS+="- Verification tests have NOT been run. Run ALL verification commands from AGENTS.md.\n"
elif [ "$TESTS_PASSED" != "true" ]; then
  BLOCKERS+="- Verification tests were run but FAILED. Fix the failures before stopping.\n"
fi

# 2. Check if there are remaining tasks
if [ -f "$CWD/IMPLEMENTATION_PLAN.md" ]; then
  REMAINING=$(grep -c '^\- \[ \]' "$CWD/IMPLEMENTATION_PLAN.md" 2>/dev/null || echo "0")
  if [ "$REMAINING" -gt 0 ]; then
    NEXT=$(grep '^\- \[ \]' "$CWD/IMPLEMENTATION_PLAN.md" 2>/dev/null | head -1 | sed 's/^- \[ \] //')
    BLOCKERS+="- There are $REMAINING unchecked tasks remaining. Next: $NEXT\n"
  fi
fi

# --- Decision ---

if [ -n "$BLOCKERS" ]; then
  # Block the stop - send checklist to stderr
  echo -e "PRECOMPLETION CHECKLIST FAILED - You cannot stop yet.\n\nBlockers:\n$BLOCKERS\nComplete these items before attempting to stop." >&2
  exit 2
fi

# All clear - allow stop
exit 0
