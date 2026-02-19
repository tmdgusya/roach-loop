#!/usr/bin/env bash
# ralph-agent/hooks/session-start.sh
# Context Injection Hook (SessionStart)
#
# Harness Engineering Concept: "Context Injection > Context Discovery"
# Instead of letting the agent explore, inject a pre-built environment map.
#
# Injects:
#   - Directory tree snapshot (depth-limited)
#   - Verification commands from AGENTS.md
#   - Current task status from IMPLEMENTATION_PLAN.md
#   - Previous session state (for resume)
#   - Time budget constraints (if configured)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/state.sh"

# Read hook input from stdin
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
CWD=$(echo "$INPUT" | jq -r '.cwd // "."')
SOURCE=$(echo "$INPUT" | jq -r '.source // "startup"')

# Skip if context injection is disabled
if [ "$HARNESS_CONTEXT_ENABLED" != "true" ]; then
  exit 0
fi

# Initialize harness state
export HARNESS_STATE_DIR="${CWD}/.harness"
init_harness_state

# --- Build Context ---

CONTEXT=""

# 1. Directory Tree
if [ -d "$CWD" ]; then
  TREE=$(find "$CWD" -maxdepth "$HARNESS_MAX_TREE_DEPTH" \
    -not -path '*/node_modules/*' \
    -not -path '*/.git/*' \
    -not -path '*/.harness/*' \
    -not -path '*/__pycache__/*' \
    -not -path '*/.venv/*' \
    -not -name '*.pyc' \
    2>/dev/null | head -100 | sed "s|$CWD/||" | sort)

  CONTEXT+="## Project Structure
\`\`\`
$TREE
\`\`\`

"
fi

# 2. Verification Commands from AGENTS.md
if [ -f "$CWD/AGENTS.md" ]; then
  VERIFY_CMDS=$(grep -E '^\s*-\s*`[^`]+`' "$CWD/AGENTS.md" 2>/dev/null | head -20 || true)
  if [ -n "$VERIFY_CMDS" ]; then
    CONTEXT+="## Verification Commands (from AGENTS.md)
$VERIFY_CMDS

"
  fi
fi

# 3. Task Status from IMPLEMENTATION_PLAN.md
if [ -f "$CWD/IMPLEMENTATION_PLAN.md" ]; then
  TOTAL=$(grep -c '^\- \[.\]' "$CWD/IMPLEMENTATION_PLAN.md" 2>/dev/null || echo "0")
  DONE=$(grep -c '^\- \[x\]' "$CWD/IMPLEMENTATION_PLAN.md" 2>/dev/null || echo "0")
  REMAINING=$((TOTAL - DONE))
  NEXT_TASK=$(grep '^\- \[ \]' "$CWD/IMPLEMENTATION_PLAN.md" 2>/dev/null | head -1 | sed 's/^- \[ \] //' || echo "none")

  CONTEXT+="## Task Status
- Total tasks: $TOTAL
- Completed: $DONE
- Remaining: $REMAINING
- Next task: $NEXT_TASK

"

  # Update state
  write_state ".tasks_completed" "$DONE"
  write_state ".tasks_remaining" "$REMAINING"
  write_state ".current_task" "\"$NEXT_TASK\""
fi

# 4. Previous Session State (for resume)
PREV_PHASE=$(read_state ".phase")
if [ "$SOURCE" = "resume" ] && [ -n "$PREV_PHASE" ] && [ "$PREV_PHASE" != "idle" ]; then
  PREV_TASK=$(read_state ".current_task")
  PREV_ITER=$(read_state ".iteration")
  CONTEXT+="## Resumed Session
- Previous phase: $PREV_PHASE
- Previous task: $PREV_TASK
- Iteration: $PREV_ITER
- IMPORTANT: Continue from where you left off.

"
fi

# 5. Time Budget
if [ "$HARNESS_TIME_BUDGET" -gt 0 ] 2>/dev/null; then
  CONTEXT+="## Time Budget
- Maximum time: ${HARNESS_TIME_BUDGET} seconds
- Do NOT spend time on unnecessary exploration or optimization.

"
fi

# 6. Harness Rules
CONTEXT+="## Harness Rules (Enforced by Hooks)
- Loop Detection: Editing the same file $HARNESS_LOOP_THRESHOLD+ times triggers a strategy reconsideration prompt.
- PreCompletionChecklist: You cannot stop until verification commands have been run and passed.
- File Protection: Protected files (.env, credentials, keys) cannot be written to.
- All tool calls are logged for trace analysis.
"

# --- Update State ---
write_state ".session_id" "\"$SESSION_ID\""
write_state ".started_at" "\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\""
write_state ".phase" '"executing"'
write_state ".context_injected" 'true'

# --- Output Context ---
jq -n --arg ctx "$CONTEXT" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'

exit 0
