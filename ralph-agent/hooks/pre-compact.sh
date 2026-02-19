#!/usr/bin/env bash
# ralph-agent/hooks/pre-compact.sh
# Context Preservation (PreCompact)
#
# Harness Engineering Concept: "Artifacts for Continuity"
# When context is compacted, re-inject critical state so the
# agent maintains awareness of its position and progress.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/state.sh"

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // "."')

export HARNESS_STATE_DIR="${CWD}/.harness"

# Skip if state doesn't exist
if [ ! -f "$HARNESS_STATE_DIR/state.json" ]; then
  exit 0
fi

# --- Build Preservation Context ---

PHASE=$(read_state ".phase")
CURRENT_TASK=$(read_state ".current_task")
COMPLETED=$(read_state ".tasks_completed")
REMAINING=$(read_state ".tasks_remaining")
ITERATION=$(read_state ".iteration")
TDD_PHASE=$(read_state ".tdd_phase")

CONTEXT="## HARNESS STATE (Preserved across compaction)
- Phase: $PHASE
- Current task: $CURRENT_TASK
- Progress: $COMPLETED completed, $REMAINING remaining
- Iteration: $ITERATION
- TDD Phase: $TDD_PHASE
- IMPORTANT: Continue working on the current task. Do NOT restart from the beginning."

# Add verification commands reminder
if [ -f "$CWD/AGENTS.md" ]; then
  VERIFY_CMDS=$(grep -E '^\s*-\s*`[^`]+`' "$CWD/AGENTS.md" 2>/dev/null | head -10 || true)
  if [ -n "$VERIFY_CMDS" ]; then
    CONTEXT+="

## Verification Commands
$VERIFY_CMDS"
  fi
fi

# Update compaction timestamp
write_state ".last_compacted_at" "\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\""

jq -n --arg ctx "$CONTEXT" '{
  hookSpecificOutput: {
    hookEventName: "PreCompact",
    additionalContext: $ctx
  }
}'

exit 0
