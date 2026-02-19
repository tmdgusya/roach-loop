#!/usr/bin/env bash
# ralph-agent/hooks/lib/state.sh
# State management functions for the harness.
# Requires config.sh to be sourced first.

init_harness_state() {
  mkdir -p "$HARNESS_STATE_DIR"

  # Initialize state.json if not exists
  if [ ! -f "$HARNESS_STATE_DIR/state.json" ]; then
    if [ -f "$PLUGIN_ROOT/harness/templates/state.json.template" ]; then
      cp "$PLUGIN_ROOT/harness/templates/state.json.template" "$HARNESS_STATE_DIR/state.json"
    else
      echo '{}' > "$HARNESS_STATE_DIR/state.json"
    fi
  fi

  # Initialize edit-tracker.json if not exists
  if [ ! -f "$HARNESS_STATE_DIR/edit-tracker.json" ]; then
    echo '{}' > "$HARNESS_STATE_DIR/edit-tracker.json"
  fi

  # Initialize trace-log.jsonl if not exists
  if [ ! -f "$HARNESS_STATE_DIR/trace-log.jsonl" ]; then
    touch "$HARNESS_STATE_DIR/trace-log.jsonl"
  fi
}

read_state() {
  local jq_path="$1"
  jq -r "$jq_path // empty" "$HARNESS_STATE_DIR/state.json" 2>/dev/null
}

write_state() {
  local jq_path="$1" value="$2"
  local tmp="$HARNESS_STATE_DIR/state.json.tmp"
  jq "$jq_path = $value" "$HARNESS_STATE_DIR/state.json" > "$tmp" && mv "$tmp" "$HARNESS_STATE_DIR/state.json"
}

increment_edit_count() {
  local file_path="$1"
  local tracker="$HARNESS_STATE_DIR/edit-tracker.json"
  local tmp="$tracker.tmp"
  local key=$(echo "$file_path" | sed 's/[^a-zA-Z0-9._/-]/_/g')

  jq --arg k "$key" '.[$k] = ((.[$k] // 0) + 1)' "$tracker" > "$tmp" && mv "$tmp" "$tracker"
}

get_edit_count() {
  local file_path="$1"
  local key=$(echo "$file_path" | sed 's/[^a-zA-Z0-9._/-]/_/g')
  jq -r --arg k "$key" '.[$k] // 0' "$HARNESS_STATE_DIR/edit-tracker.json" 2>/dev/null
}

check_loop_detected() {
  local file_path="$1"
  local count=$(get_edit_count "$file_path")
  if [ "$count" -ge "$HARNESS_LOOP_THRESHOLD" ]; then
    echo "true"
  else
    echo "false"
  fi
}

reset_edit_tracker() {
  echo '{}' > "$HARNESS_STATE_DIR/edit-tracker.json"
}

reset_session_state() {
  # Reset edit-tracker so loop detection is per-session, not cumulative.
  # A file edited N times last session should not trigger loop detection
  # on the first edit of a new session.
  echo '{}' > "$HARNESS_STATE_DIR/edit-tracker.json"

  # Reset verification_status so the stop checklist requires fresh evidence
  # each session. Stale "tests_passed=true" from a prior session should not
  # count as proof for the current session.
  local tmp="$HARNESS_STATE_DIR/state.json.tmp"
  jq '
    .verification_status.tests_run = false |
    .verification_status.tests_passed = false |
    .verification_status.lint_run = false |
    .verification_status.lint_passed = false |
    .verification_status.last_verified_at = null
  ' "$HARNESS_STATE_DIR/state.json" > "$tmp" && mv "$tmp" "$HARNESS_STATE_DIR/state.json"
}

append_trace() {
  local tool_name="$1" tool_input="$2" result="$3"
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  jq -n -c \
    --arg ts "$timestamp" \
    --arg tool "$tool_name" \
    --arg input "$tool_input" \
    --arg res "$result" \
    '{timestamp: $ts, tool: $tool, input: ($input | fromjson? // $input), result: $res}' \
    >> "$HARNESS_STATE_DIR/trace-log.jsonl"
}
