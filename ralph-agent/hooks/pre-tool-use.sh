#!/usr/bin/env bash
# ralph-agent/hooks/pre-tool-use.sh
# Input Validation (PreToolUse)
#
# Harness Engineering Concept: "Sandboxing / Access Control"
# Validates tool inputs before execution:
#   - Protects sensitive files from writes
#   - Updates verification_status when test commands are detected

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/state.sh"

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')
CWD=$(echo "$INPUT" | jq -r '.cwd // "."')

export HARNESS_STATE_DIR="${CWD}/.harness"

# --- File Protection (Write/Edit tools) ---
if [ "$HARNESS_PROTECTION_ENABLED" = "true" ]; then
  FILE_PATH=""
  case "$TOOL_NAME" in
    Write|Edit)
      FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')
      ;;
  esac

  if [ -n "$FILE_PATH" ]; then
    BASENAME=$(basename "$FILE_PATH")
    BLOCKED=false

    # Check against protected patterns
    case "$BASENAME" in
      .env|.env.*) BLOCKED=true ;;
      *.pem|*.key) BLOCKED=true ;;
      credentials.*) BLOCKED=true ;;
      id_rsa*) BLOCKED=true ;;
    esac

    if [ "$BLOCKED" = "true" ]; then
      jq -n --arg reason "Protected file: '$BASENAME' cannot be modified by the harness." '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          permissionDecisionReason: $reason
        }
      }'
      exit 0
    fi
  fi
fi

# --- Track Verification Runs (Bash tool) ---
if [ "$TOOL_NAME" = "Bash" ] && [ -d "$HARNESS_STATE_DIR" ]; then
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

  if matches_verification_command "$COMMAND"; then
    init_harness_state
    write_state ".verification_status.tests_run" 'true'
  fi
fi

# No output = allow the tool call
exit 0
