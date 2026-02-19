#!/usr/bin/env bash
# ralph-agent/hooks/post-tool-use.sh
# Loop Detection + Trace Logger (PostToolUse)
#
# Harness Engineering Concept: "LoopDetectionMiddleware"
# Tracks edit counts per file. When threshold exceeded,
# injects a meta-cognition prompt to break doom loops.
#
# Also logs all tool calls to trace-log.jsonl for
# post-session analysis (Trace Analyzer Skill / Boosting).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/state.sh"

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')
TOOL_INPUT=$(echo "$INPUT" | jq -c '.tool_input // {}')
CWD=$(echo "$INPUT" | jq -r '.cwd // "."')

export HARNESS_STATE_DIR="${CWD}/.harness"
init_harness_state

# --- Trace Logging ---
if [ "$HARNESS_TRACE_ENABLED" = "true" ]; then
  append_trace "$TOOL_NAME" "$TOOL_INPUT" "success"
fi

# --- Loop Detection (Edit/Write tools only) ---
if [ "$HARNESS_LOOP_ENABLED" = "true" ]; then
  FILE_PATH=""

  case "$TOOL_NAME" in
    Edit)
      FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')
      ;;
    Write)
      FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')
      ;;
  esac

  if [ -n "$FILE_PATH" ]; then
    increment_edit_count "$FILE_PATH"
    LOOP_DETECTED=$(check_loop_detected "$FILE_PATH")

    if [ "$LOOP_DETECTED" = "true" ]; then
      COUNT=$(get_edit_count "$FILE_PATH")
      WARNING="LOOP DETECTION WARNING: You have edited '$FILE_PATH' $COUNT times (threshold: $HARNESS_LOOP_THRESHOLD). This suggests you may be stuck in a doom loop. STOP and reconsider your approach:
1. Re-read the error message carefully - you may be misinterpreting it.
2. Try a completely different strategy rather than tweaking the same file.
3. Check if the issue is in a DIFFERENT file than the one you keep editing.
4. Consider if a dependency or configuration is the root cause."

      jq -n --arg ctx "$WARNING" '{
        hookSpecificOutput: {
          hookEventName: "PostToolUse",
          additionalContext: $ctx
        }
      }'
      exit 0
    fi
  fi
fi

# --- Verification Result Tracking (Bash tool) ---
if [ "$TOOL_NAME" = "Bash" ] && [ -d "$HARNESS_STATE_DIR" ]; then
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
  # PostToolUse means the command succeeded (exit 0)

  # Track test results
  if echo "$COMMAND" | grep -qE '(pytest|npm test|npm run test|go test|jest|vitest|cargo test|make test)'; then
    write_state ".verification_status.tests_passed" 'true'
    write_state ".verification_status.last_verified_at" "\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\""
  fi

  # Track lint results
  if echo "$COMMAND" | grep -qE '(ruff|eslint|flake8|pylint|npm run lint|clippy|golangci-lint)'; then
    write_state ".verification_status.lint_passed" 'true'
  fi
fi

# No output needed for normal operations
exit 0
