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

# discover_verification_commands() — dynamically discover verification commands
# from project config files. Returns a JSON array on stdout.
# Sources (in priority order, deduped):
#   1. IMPLEMENTATION_PLAN.md ## Verification section (backtick-wrapped commands)
#   2. AGENTS.md lines matching bullet + backtick pattern
#   3. package.json scripts.test / scripts.lint
#   4. Python test config files -> pytest tests/
#   5. *_test.go files -> go test ./...
#   6. Cargo.toml -> cargo test
#   7. Makefile test: target -> make test
#   8. ruff.toml / pyproject.toml [tool.ruff] -> ruff check .
discover_verification_commands() {
  local cwd="${1:-$(pwd)}"
  local -a cmds=()

  # 1. IMPLEMENTATION_PLAN.md ## Verification section
  if [ -f "$cwd/IMPLEMENTATION_PLAN.md" ]; then
    local in_verification=false
    while IFS= read -r line; do
      if echo "$line" | grep -qE '^## Verification'; then
        in_verification=true
        continue
      fi
      if $in_verification && echo "$line" | grep -qE '^## '; then
        break
      fi
      if $in_verification; then
        local cmd
        cmd=$(echo "$line" | grep -oE '`[^`]+`' | head -1 | tr -d '`')
        if [ -n "$cmd" ]; then
          cmds+=("$cmd")
        fi
      fi
    done < "$cwd/IMPLEMENTATION_PLAN.md"
  fi

  # 2. AGENTS.md lines matching bullet + backtick pattern
  if [ -f "$cwd/AGENTS.md" ]; then
    while IFS= read -r line; do
      local cmd
      cmd=$(echo "$line" | grep -oE '`[^`]+`' | head -1 | tr -d '`')
      if [ -n "$cmd" ]; then
        cmds+=("$cmd")
      fi
    done < <(grep -E '^\s*-\s*`[^`]+`' "$cwd/AGENTS.md" 2>/dev/null || true)
  fi

  # 3. package.json test/lint scripts
  if [ -f "$cwd/package.json" ]; then
    local test_script lint_script
    test_script=$(jq -r '.scripts.test // ""' "$cwd/package.json" 2>/dev/null)
    lint_script=$(jq -r '.scripts.lint // ""' "$cwd/package.json" 2>/dev/null)
    if [ -n "$test_script" ] && ! echo "$test_script" | grep -q "no test specified"; then
      cmds+=("npm test")
    fi
    if [ -n "$lint_script" ]; then
      cmds+=("npm run lint")
    fi
  fi

  # 4. Python test config -> pytest tests/
  local has_pytest=false
  for cfg in pytest.ini setup.cfg tox.ini; do
    if [ -f "$cwd/$cfg" ]; then
      has_pytest=true
      break
    fi
  done
  if [ -f "$cwd/pyproject.toml" ] && grep -q '\[tool\.pytest' "$cwd/pyproject.toml" 2>/dev/null; then
    has_pytest=true
  fi
  if $has_pytest; then
    cmds+=("pytest tests/")
  fi

  # 5. *_test.go files (maxdepth 3) -> go test ./...
  if find "$cwd" -maxdepth 3 -name '*_test.go' 2>/dev/null | grep -q .; then
    cmds+=("go test ./...")
  fi

  # 6. Cargo.toml -> cargo test
  if [ -f "$cwd/Cargo.toml" ]; then
    cmds+=("cargo test")
  fi

  # 7. Makefile with test: target -> make test
  if [ -f "$cwd/Makefile" ] && grep -q '^test:' "$cwd/Makefile" 2>/dev/null; then
    cmds+=("make test")
  fi

  # 8. ruff.toml / pyproject.toml [tool.ruff] -> ruff check .
  local has_ruff=false
  if [ -f "$cwd/ruff.toml" ]; then
    has_ruff=true
  fi
  if [ -f "$cwd/pyproject.toml" ] && grep -q '\[tool\.ruff' "$cwd/pyproject.toml" 2>/dev/null; then
    has_ruff=true
  fi
  if $has_ruff; then
    cmds+=("ruff check .")
  fi

  # Deduplicate and output as JSON array
  if [ ${#cmds[@]} -eq 0 ]; then
    echo '[]'
    return 0
  fi

  printf '%s\n' "${cmds[@]}" | sort -u | jq -R . | jq -sc .
}

# matches_verification_command() — returns 0 if command matches a known
# verification pattern, 1 otherwise. Checks:
#   1. ralph:verify-complete escape hatch
#   2. Hardcoded well-known test/lint patterns
#   3. Discovered commands from state.json
#   4. Custom commands from HARNESS_VERIFICATION_COMMANDS (harness.json)
matches_verification_command() {
  local command="$1"

  # 1. ralph:verify-complete escape hatch
  if echo "$command" | grep -q 'ralph:verify-complete'; then
    return 0
  fi

  # 2. Hardcoded well-known patterns (tests + linters)
  if echo "$command" | grep -qE '(pytest|npm test|npm run test|go test|jest|vitest|cargo test|make test|ruff|eslint|flake8|pylint|npm run lint|clippy|golangci-lint)'; then
    return 0
  fi

  # 3. Discovered commands from state
  if [ -f "${HARNESS_STATE_DIR}/state.json" ]; then
    local discovered
    discovered=$(jq -r '.discovered_verification_commands // [] | .[]' "${HARNESS_STATE_DIR}/state.json" 2>/dev/null || true)
    if [ -n "$discovered" ]; then
      while IFS= read -r pattern; do
        if [ -n "$pattern" ] && echo "$command" | grep -qF "$pattern"; then
          return 0
        fi
      done <<< "$discovered"
    fi
  fi

  # 4. Custom commands from harness.json (HARNESS_VERIFICATION_COMMANDS)
  if [ -n "${HARNESS_VERIFICATION_COMMANDS:-}" ] && \
     [ "$HARNESS_VERIFICATION_COMMANDS" != "null" ] && \
     [ "$HARNESS_VERIFICATION_COMMANDS" != "[]" ]; then
    while IFS= read -r pattern; do
      if [ -n "$pattern" ] && echo "$command" | grep -qF "$pattern"; then
        return 0
      fi
    done < <(echo "$HARNESS_VERIFICATION_COMMANDS" | jq -r '.[]' 2>/dev/null || true)
  fi

  return 1
}

# has_test_infra() — derived from discover_verification_commands
has_test_infra() {
  local cmds
  cmds=$(discover_verification_commands "${1:-$(pwd)}")
  if [ "$(echo "$cmds" | jq 'length')" -gt 0 ]; then
    echo "true"
  else
    echo "false"
  fi
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
