#!/usr/bin/env bash
# ralph-agent/hooks/lib/config.sh
# Shared configuration for all harness hooks.
# Sources harness.json and exports constants.

HOOK_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$HOOK_LIB_DIR/../.." && pwd)"

# Load harness.json defaults (jq required)
_HARNESS_JSON="$PLUGIN_ROOT/harness/harness.json"

if [ -f "$_HARNESS_JSON" ]; then
  HARNESS_LOOP_THRESHOLD=$(jq -r '.middleware.loop_detection.edit_threshold // 5' "$_HARNESS_JSON")
  HARNESS_LOOP_ENABLED="${HARNESS_LOOP_ENABLED:-$(jq -r '.middleware.loop_detection.enabled // true' "$_HARNESS_JSON")}"
  HARNESS_CHECKLIST_ENABLED="${HARNESS_CHECKLIST_ENABLED:-$(jq -r '.middleware.pre_completion_checklist.enabled // true' "$_HARNESS_JSON")}"
  HARNESS_CONTEXT_ENABLED="${HARNESS_CONTEXT_ENABLED:-$(jq -r '.middleware.context_injection.enabled // true' "$_HARNESS_JSON")}"
  HARNESS_TRACE_ENABLED="${HARNESS_TRACE_ENABLED:-$(jq -r '.middleware.trace_logging.enabled // true' "$_HARNESS_JSON")}"
  HARNESS_PROTECTION_ENABLED="${HARNESS_PROTECTION_ENABLED:-$(jq -r '.middleware.file_protection.enabled // true' "$_HARNESS_JSON")}"
  HARNESS_MAX_TREE_DEPTH=$(jq -r '.middleware.context_injection.max_tree_depth // 3' "$_HARNESS_JSON")
  HARNESS_TIME_BUDGET=$(jq -r '.middleware.context_injection.time_budget_seconds // 0' "$_HARNESS_JSON")
  HARNESS_STATE_DIR_NAME=$(jq -r '.state.dir // ".harness"' "$_HARNESS_JSON")
  HARNESS_REQUIRE_VERIFICATION="${HARNESS_REQUIRE_VERIFICATION:-$(jq -r '.middleware.pre_completion_checklist.require_verification // true' "$_HARNESS_JSON")}"
  HARNESS_REQUIRE_TESTS_PASS="${HARNESS_REQUIRE_TESTS_PASS:-$(jq -r '.middleware.pre_completion_checklist.require_tests_pass // true' "$_HARNESS_JSON")}"
  HARNESS_REQUIRE_PLAN_CHECK="${HARNESS_REQUIRE_PLAN_CHECK:-$(jq -r '.middleware.pre_completion_checklist.require_plan_check // true' "$_HARNESS_JSON")}"
  HARNESS_VERIFICATION_COMMANDS="${HARNESS_VERIFICATION_COMMANDS:-$(jq -c '.middleware.pre_completion_checklist.verification_commands // []' "$_HARNESS_JSON")}"
else
  # Fallback defaults
  HARNESS_LOOP_THRESHOLD=5
  HARNESS_LOOP_ENABLED=true
  HARNESS_CHECKLIST_ENABLED=true
  HARNESS_CONTEXT_ENABLED=true
  HARNESS_TRACE_ENABLED=true
  HARNESS_PROTECTION_ENABLED=true
  HARNESS_MAX_TREE_DEPTH=3
  HARNESS_TIME_BUDGET=0
  HARNESS_STATE_DIR_NAME=".harness"
  HARNESS_REQUIRE_VERIFICATION=true
  HARNESS_REQUIRE_TESTS_PASS=true
  HARNESS_REQUIRE_PLAN_CHECK=true
  HARNESS_VERIFICATION_COMMANDS='[]'
fi

# Resolve state directory (use CWD or override)
HARNESS_STATE_DIR="${HARNESS_STATE_DIR:-$(pwd)/$HARNESS_STATE_DIR_NAME}"

export HARNESS_LOOP_THRESHOLD HARNESS_LOOP_ENABLED HARNESS_CHECKLIST_ENABLED
export HARNESS_CONTEXT_ENABLED HARNESS_TRACE_ENABLED HARNESS_PROTECTION_ENABLED
export HARNESS_MAX_TREE_DEPTH HARNESS_TIME_BUDGET HARNESS_STATE_DIR
export HARNESS_REQUIRE_VERIFICATION HARNESS_REQUIRE_TESTS_PASS HARNESS_REQUIRE_PLAN_CHECK
export HARNESS_VERIFICATION_COMMANDS
export PLUGIN_ROOT HOOK_LIB_DIR
