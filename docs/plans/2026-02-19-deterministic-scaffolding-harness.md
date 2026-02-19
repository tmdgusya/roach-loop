# Deterministic Scaffolding Harness Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Migrate the ralph-agent plugin from prompt-driven control (Agent 1.0) to a deterministic scaffolding harness using Claude Code hooks as middleware layers (Agent 2.0).

**Architecture:** Claude Code hooks intercept tool calls and agent lifecycle events to enforce behavior deterministically from *outside* the model. Each hook maps to a harness engineering concept: `SessionStart` → Context Injection, `PostToolUse` → Loop Detection, `Stop` → PreCompletionChecklist, `PreCompact` → Context Preservation. JSON state files replace prompt-based state tracking. The agent prompt becomes thinner because hooks enforce the guardrails.

**Tech Stack:** Bash (hook scripts), jq (JSON processing), Claude Code Hooks API, JSON (state management)

**Key Principle:** Move control from inside the prompt to outside the model. The prompt tells the agent *what* to do; the hooks ensure *how* it does it is correct.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Claude Code Agent                      │
│  ┌───────────┐  ┌──────────┐  ┌──────────────────────┐  │
│  │   Ralph    │  │  Tools   │  │   Model (LLM)        │  │
│  │  (thin     │  │  (Read,  │  │   opus/sonnet/haiku  │  │
│  │   prompt)  │  │  Write,  │  │                      │  │
│  │           │  │  Bash..) │  │                      │  │
│  └───────────┘  └────┬─────┘  └──────────────────────┘  │
│                      │                                    │
├──────────────────────┼────────────────────────────────────┤
│   DETERMINISTIC      │   SCAFFOLDING (Hooks Layer)        │
│                      │                                    │
│  ┌──────────────┐    │    ┌───────────────────────────┐   │
│  │ SessionStart │────┼───▶│ Context Injection         │   │
│  │   Hook       │    │    │ (dir tree, tools, state)  │   │
│  └──────────────┘    │    └───────────────────────────┘   │
│                      │                                    │
│  ┌──────────────┐    │    ┌───────────────────────────┐   │
│  │ PreToolUse   │────┼───▶│ Input Validation          │   │
│  │   Hook       │    │    │ (file protection, sanitize)│  │
│  └──────────────┘    │    └───────────────────────────┘   │
│                      │                                    │
│  ┌──────────────┐    │    ┌───────────────────────────┐   │
│  │ PostToolUse  │────┼───▶│ Loop Detection +          │   │
│  │   Hook       │    │    │ Trace Logger              │   │
│  └──────────────┘    │    └───────────────────────────┘   │
│                      │                                    │
│  ┌──────────────┐    │    ┌───────────────────────────┐   │
│  │ Stop Hook    │────┼───▶│ PreCompletionChecklist    │   │
│  │              │    │    │ (force verification)      │   │
│  └──────────────┘    │    └───────────────────────────┘   │
│                      │                                    │
│  ┌──────────────┐    │    ┌───────────────────────────┐   │
│  │ PreCompact   │────┼───▶│ Context Preservation      │   │
│  │   Hook       │    │    │ (re-inject critical state) │  │
│  └──────────────┘    │    └───────────────────────────┘   │
│                      │                                    │
│  ┌───────────────────┴────────────────────────────────┐   │
│  │              .harness/ (JSON State)                 │   │
│  │  state.json  edit-tracker.json  trace-log.jsonl    │   │
│  └────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

## File Structure (New/Modified)

```
ralph-agent/
├── hooks/                          # NEW: Hook scripts
│   ├── hooks.json                  # Hook event → script mapping
│   ├── session-start.sh            # Context injection
│   ├── pre-tool-use.sh             # Input validation + file protection
│   ├── post-tool-use.sh            # Loop detection + trace logging
│   ├── stop-checklist.sh           # PreCompletionChecklist
│   ├── pre-compact.sh              # Context preservation
│   └── lib/                        # Shared utilities
│       ├── state.sh                # State management functions
│       └── config.sh               # Configuration constants
├── harness/                        # NEW: Harness configuration
│   ├── harness.json                # Thresholds, feature flags
│   └── templates/
│       └── state.json.template     # Initial state structure
├── agents/
│   └── ralph.md                    # MODIFY: Thinner prompt, hooks handle enforcement
├── .claude-plugin/
│   └── plugin.json                 # MODIFY: Add hooks registration
└── ...existing files unchanged...
```

---

### Task 1: Create Hook Infrastructure & Shared Libraries

**Files:**
- Create: `ralph-agent/hooks/lib/config.sh`
- Create: `ralph-agent/hooks/lib/state.sh`
- Create: `ralph-agent/harness/harness.json`
- Create: `ralph-agent/harness/templates/state.json.template`

**Step 1: Write the test script for shared libraries**

Create a verification script that tests the shared library functions:

```bash
# ralph-agent/hooks/lib/test-libs.sh
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/state.sh"

PASS=0
FAIL=0
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    ((PASS++))
  else
    echo "  FAIL: $desc (expected='$expected', actual='$actual')"
    ((FAIL++))
  fi
}

echo "=== Testing config.sh ==="
assert_eq "LOOP_THRESHOLD is set" "true" "$([ -n "$HARNESS_LOOP_THRESHOLD" ] && echo true || echo false)"
assert_eq "LOOP_THRESHOLD is number" "true" "$([ "$HARNESS_LOOP_THRESHOLD" -gt 0 ] 2>/dev/null && echo true || echo false)"

echo ""
echo "=== Testing state.sh ==="

# Test init_harness_state
export HARNESS_STATE_DIR="$TMPDIR/.harness"
init_harness_state
assert_eq "state.json created" "true" "$([ -f "$HARNESS_STATE_DIR/state.json" ] && echo true || echo false)"
assert_eq "edit-tracker.json created" "true" "$([ -f "$HARNESS_STATE_DIR/edit-tracker.json" ] && echo true || echo false)"
assert_eq "trace-log.jsonl created" "true" "$([ -f "$HARNESS_STATE_DIR/trace-log.jsonl" ] && echo true || echo false)"

# Test read/write state
write_state ".phase" '"executing"'
PHASE=$(read_state ".phase")
assert_eq "write/read state" "executing" "$PHASE"

# Test increment_edit_count
increment_edit_count "/path/to/file.ts"
increment_edit_count "/path/to/file.ts"
increment_edit_count "/path/to/file.ts"
COUNT=$(get_edit_count "/path/to/file.ts")
assert_eq "edit count tracked" "3" "$COUNT"

# Test check_loop_detected
LOOP=$(check_loop_detected "/path/to/file.ts")
assert_eq "no loop at 3 edits (threshold=$HARNESS_LOOP_THRESHOLD)" "false" "$LOOP"

# Push to threshold
for i in $(seq 4 "$HARNESS_LOOP_THRESHOLD"); do
  increment_edit_count "/path/to/file.ts"
done
LOOP=$(check_loop_detected "/path/to/file.ts")
assert_eq "loop detected at threshold" "true" "$LOOP"

# Test append_trace
append_trace "Edit" '{"file_path":"/test.ts"}' "success"
LINES=$(wc -l < "$HARNESS_STATE_DIR/trace-log.jsonl")
assert_eq "trace appended" "1" "$(echo $LINES | tr -d ' ')"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
```

**Step 2: Run test to verify it fails**

Run: `bash ralph-agent/hooks/lib/test-libs.sh`
Expected: FAIL with "config.sh: No such file or directory"

**Step 3: Create harness.json configuration**

```json
{
  "version": "1.0.0",
  "middleware": {
    "context_injection": {
      "enabled": true,
      "inject_dir_tree": true,
      "inject_tools": true,
      "max_tree_depth": 3,
      "time_budget_seconds": 0
    },
    "loop_detection": {
      "enabled": true,
      "edit_threshold": 5,
      "reset_on_new_task": true
    },
    "pre_completion_checklist": {
      "enabled": true,
      "require_verification": true,
      "require_tests_pass": true,
      "require_plan_check": true
    },
    "file_protection": {
      "enabled": true,
      "protected_patterns": [
        ".env",
        ".env.*",
        "*.pem",
        "*.key",
        "credentials.*"
      ]
    },
    "trace_logging": {
      "enabled": true,
      "log_tool_calls": true,
      "log_file_edits": true,
      "max_log_size_mb": 10
    }
  },
  "state": {
    "format": "json",
    "dir": ".harness"
  }
}
```

**Step 4: Create state.json template**

```json
{
  "session_id": null,
  "started_at": null,
  "phase": "idle",
  "current_task": null,
  "tasks_completed": 0,
  "tasks_remaining": 0,
  "iteration": 0,
  "verification_status": {
    "tests_run": false,
    "tests_passed": false,
    "lint_run": false,
    "lint_passed": false,
    "last_verified_at": null
  },
  "tdd_phase": null,
  "context_injected": false,
  "last_compacted_at": null
}
```

**Step 5: Implement config.sh**

```bash
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
  HARNESS_LOOP_ENABLED=$(jq -r '.middleware.loop_detection.enabled // true' "$_HARNESS_JSON")
  HARNESS_CHECKLIST_ENABLED=$(jq -r '.middleware.pre_completion_checklist.enabled // true' "$_HARNESS_JSON")
  HARNESS_CONTEXT_ENABLED=$(jq -r '.middleware.context_injection.enabled // true' "$_HARNESS_JSON")
  HARNESS_TRACE_ENABLED=$(jq -r '.middleware.trace_logging.enabled // true' "$_HARNESS_JSON")
  HARNESS_PROTECTION_ENABLED=$(jq -r '.middleware.file_protection.enabled // true' "$_HARNESS_JSON")
  HARNESS_MAX_TREE_DEPTH=$(jq -r '.middleware.context_injection.max_tree_depth // 3' "$_HARNESS_JSON")
  HARNESS_TIME_BUDGET=$(jq -r '.middleware.context_injection.time_budget_seconds // 0' "$_HARNESS_JSON")
  HARNESS_STATE_DIR_NAME=$(jq -r '.state.dir // ".harness"' "$_HARNESS_JSON")
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
fi

# Resolve state directory (use CWD or override)
HARNESS_STATE_DIR="${HARNESS_STATE_DIR:-$(pwd)/$HARNESS_STATE_DIR_NAME}"

export HARNESS_LOOP_THRESHOLD HARNESS_LOOP_ENABLED HARNESS_CHECKLIST_ENABLED
export HARNESS_CONTEXT_ENABLED HARNESS_TRACE_ENABLED HARNESS_PROTECTION_ENABLED
export HARNESS_MAX_TREE_DEPTH HARNESS_TIME_BUDGET HARNESS_STATE_DIR
export PLUGIN_ROOT HOOK_LIB_DIR
```

**Step 6: Implement state.sh**

```bash
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
```

**Step 7: Run test to verify it passes**

Run: `bash ralph-agent/hooks/lib/test-libs.sh`
Expected: All PASS, exit 0

**Step 8: Commit**

```bash
git add ralph-agent/hooks/lib/config.sh ralph-agent/hooks/lib/state.sh \
        ralph-agent/hooks/lib/test-libs.sh \
        ralph-agent/harness/harness.json \
        ralph-agent/harness/templates/state.json.template
git commit -m "feat: add harness hook infrastructure with shared libraries"
```

---

### Task 2: SessionStart Context Injection Hook

**Files:**
- Create: `ralph-agent/hooks/session-start.sh`

**Concept:** Instead of making the agent discover its environment (ls, find, etc.), inject a pre-built "map" at session start. This is the most impactful single harness improvement per LangChain's research.

**Step 1: Write the test**

```bash
# ralph-agent/hooks/test-session-start.sh
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Create a fake project structure
mkdir -p "$TMPDIR/src" "$TMPDIR/tests" "$TMPDIR/.harness"
echo '{}' > "$TMPDIR/.harness/state.json"
echo '{}' > "$TMPDIR/.harness/edit-tracker.json"
touch "$TMPDIR/.harness/trace-log.jsonl"
echo '# Verification Commands' > "$TMPDIR/AGENTS.md"
echo '- `pytest tests/`' >> "$TMPDIR/AGENTS.md"
echo '- [ ] Task 1: Do something' > "$TMPDIR/IMPLEMENTATION_PLAN.md"
echo '- [x] Task 2: Already done' >> "$TMPDIR/IMPLEMENTATION_PLAN.md"

PASS=0
FAIL=0

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    echo "  PASS: $desc"
    ((PASS++))
  else
    echo "  FAIL: $desc (needle='$needle' not found)"
    ((FAIL++))
  fi
}

echo "=== Testing session-start.sh ==="

# Simulate SessionStart hook input
INPUT=$(jq -n '{
  session_id: "test-session-123",
  cwd: "'"$TMPDIR"'",
  hook_event_name: "SessionStart",
  source: "startup"
}')

export HARNESS_STATE_DIR="$TMPDIR/.harness"
OUTPUT=$(echo "$INPUT" | bash "$SCRIPT_DIR/session-start.sh" 2>/dev/null)

assert_contains "outputs JSON" "hookSpecificOutput" "$OUTPUT"
assert_contains "contains additionalContext" "additionalContext" "$OUTPUT"
assert_contains "contains directory structure" "src" "$OUTPUT"
assert_contains "contains verification commands" "pytest" "$OUTPUT"
assert_contains "contains task status" "Task 1" "$OUTPUT"

# Verify state was updated
STATE_PHASE=$(jq -r '.phase' "$TMPDIR/.harness/state.json")
assert_contains "state phase updated" "executing" "$STATE_PHASE"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
```

**Step 2: Run test to verify it fails**

Run: `bash ralph-agent/hooks/test-session-start.sh`
Expected: FAIL with "session-start.sh: No such file or directory"

**Step 3: Implement session-start.sh**

```bash
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
```

**Step 4: Make executable and run test**

Run: `chmod +x ralph-agent/hooks/session-start.sh && bash ralph-agent/hooks/test-session-start.sh`
Expected: All PASS

**Step 5: Commit**

```bash
git add ralph-agent/hooks/session-start.sh ralph-agent/hooks/test-session-start.sh
git commit -m "feat: add SessionStart context injection hook"
```

---

### Task 3: PostToolUse Loop Detection & Trace Logger Hook

**Files:**
- Create: `ralph-agent/hooks/post-tool-use.sh`

**Concept:** Track file edit counts. When a file is edited N+ times, inject a "reconsider your approach" meta-cognition prompt. This breaks the agent out of doom loops. Also logs all tool calls for trace analysis.

**Step 1: Write the test**

```bash
# ralph-agent/hooks/test-post-tool-use.sh
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Setup
mkdir -p "$TMPDIR/.harness"
echo '{}' > "$TMPDIR/.harness/state.json"
echo '{}' > "$TMPDIR/.harness/edit-tracker.json"
touch "$TMPDIR/.harness/trace-log.jsonl"

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    ((PASS++))
  else
    echo "  FAIL: $desc (expected='$expected', actual='$actual')"
    ((FAIL++))
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    echo "  PASS: $desc"
    ((PASS++))
  else
    echo "  FAIL: $desc (needle='$needle' not found)"
    ((FAIL++))
  fi
}

echo "=== Testing post-tool-use.sh ==="

export HARNESS_STATE_DIR="$TMPDIR/.harness"

# Test 1: Normal edit (no loop)
INPUT=$(jq -n '{
  tool_name: "Edit",
  tool_input: { file_path: "/test/src/app.ts", old_string: "a", new_string: "b" },
  tool_response: { success: true },
  cwd: "'"$TMPDIR"'",
  hook_event_name: "PostToolUse"
}')

OUTPUT=$(echo "$INPUT" | bash "$SCRIPT_DIR/post-tool-use.sh" 2>/dev/null)
COUNT=$(jq -r '.["/test/src/app.ts"] // 0' "$TMPDIR/.harness/edit-tracker.json")
assert_eq "edit count incremented" "1" "$COUNT"

# Test 2: Trace logged
TRACE_LINES=$(wc -l < "$TMPDIR/.harness/trace-log.jsonl")
assert_eq "trace logged" "1" "$(echo $TRACE_LINES | tr -d ' ')"

# Test 3: Loop detection (hit threshold)
# Edit same file 5 more times (total 6, threshold is 5)
for i in $(seq 2 6); do
  echo "$INPUT" | bash "$SCRIPT_DIR/post-tool-use.sh" > /dev/null 2>&1
done

OUTPUT=$(echo "$INPUT" | bash "$SCRIPT_DIR/post-tool-use.sh" 2>/dev/null)
assert_contains "loop warning injected" "reconsider" "$OUTPUT"

# Test 4: Non-edit tool (Read) should not increment
READ_INPUT=$(jq -n '{
  tool_name: "Read",
  tool_input: { file_path: "/test/README.md" },
  tool_response: { content: "hello" },
  cwd: "'"$TMPDIR"'",
  hook_event_name: "PostToolUse"
}')

echo "$READ_INPUT" | bash "$SCRIPT_DIR/post-tool-use.sh" > /dev/null 2>&1
READ_COUNT=$(jq -r '.["/test/README.md"] // 0' "$TMPDIR/.harness/edit-tracker.json")
assert_eq "read does not increment edit count" "0" "$READ_COUNT"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
```

**Step 2: Run test to verify it fails**

Run: `bash ralph-agent/hooks/test-post-tool-use.sh`
Expected: FAIL with "post-tool-use.sh: No such file or directory"

**Step 3: Implement post-tool-use.sh**

```bash
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

# No output needed for normal operations
exit 0
```

**Step 4: Make executable and run test**

Run: `chmod +x ralph-agent/hooks/post-tool-use.sh && bash ralph-agent/hooks/test-post-tool-use.sh`
Expected: All PASS

**Step 5: Commit**

```bash
git add ralph-agent/hooks/post-tool-use.sh ralph-agent/hooks/test-post-tool-use.sh
git commit -m "feat: add PostToolUse loop detection and trace logging hook"
```

---

### Task 4: Stop PreCompletionChecklist Hook

**Files:**
- Create: `ralph-agent/hooks/stop-checklist.sh`

**Concept:** The agent's most common failure mode is declaring "done" without running verification. This hook intercepts the Stop event and forces the agent back into execution if the checklist isn't satisfied.

**Step 1: Write the test**

```bash
# ralph-agent/hooks/test-stop-checklist.sh
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

PASS=0
FAIL=0

assert_exit_code() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    ((PASS++))
  else
    echo "  FAIL: $desc (expected exit=$expected, actual exit=$actual)"
    ((FAIL++))
  fi
}

echo "=== Testing stop-checklist.sh ==="

# Setup: state with verification NOT done
mkdir -p "$TMPDIR/.harness"
cat > "$TMPDIR/.harness/state.json" << 'EOF'
{
  "phase": "executing",
  "verification_status": {
    "tests_run": false,
    "tests_passed": false,
    "lint_run": false,
    "lint_passed": false
  }
}
EOF
echo '{}' > "$TMPDIR/.harness/edit-tracker.json"
touch "$TMPDIR/.harness/trace-log.jsonl"
echo '- [ ] Task 1: pending' > "$TMPDIR/IMPLEMENTATION_PLAN.md"

export HARNESS_STATE_DIR="$TMPDIR/.harness"

# Test 1: Block stop when verification not done
INPUT=$(jq -n '{
  stop_hook_active: false,
  last_assistant_message: "I have completed the task.",
  cwd: "'"$TMPDIR"'",
  hook_event_name: "Stop"
}')

set +e
OUTPUT=$(echo "$INPUT" | bash "$SCRIPT_DIR/stop-checklist.sh" 2>/tmp/stop-stderr)
EXIT_CODE=$?
set -e

assert_exit_code "blocks stop without verification" "2" "$EXIT_CODE"

# Test 2: Allow stop when already in stop_hook_active
INPUT_ACTIVE=$(jq -n '{
  stop_hook_active: true,
  last_assistant_message: "Running verification now.",
  cwd: "'"$TMPDIR"'",
  hook_event_name: "Stop"
}')

set +e
echo "$INPUT_ACTIVE" | bash "$SCRIPT_DIR/stop-checklist.sh" > /dev/null 2>&1
EXIT_CODE=$?
set -e

assert_exit_code "allows when stop_hook_active=true" "0" "$EXIT_CODE"

# Test 3: Allow stop when all verified
cat > "$TMPDIR/.harness/state.json" << 'EOF'
{
  "phase": "executing",
  "verification_status": {
    "tests_run": true,
    "tests_passed": true,
    "lint_run": true,
    "lint_passed": true
  }
}
EOF
# All tasks done
echo '- [x] Task 1: done' > "$TMPDIR/IMPLEMENTATION_PLAN.md"

set +e
OUTPUT=$(echo "$INPUT" | bash "$SCRIPT_DIR/stop-checklist.sh" 2>/dev/null)
EXIT_CODE=$?
set -e

assert_exit_code "allows stop when verified and tasks done" "0" "$EXIT_CODE"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
```

**Step 2: Run test to verify it fails**

Run: `bash ralph-agent/hooks/test-stop-checklist.sh`
Expected: FAIL with "stop-checklist.sh: No such file or directory"

**Step 3: Implement stop-checklist.sh**

```bash
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
```

**Step 4: Make executable and run test**

Run: `chmod +x ralph-agent/hooks/stop-checklist.sh && bash ralph-agent/hooks/test-stop-checklist.sh`
Expected: All PASS

**Step 5: Commit**

```bash
git add ralph-agent/hooks/stop-checklist.sh ralph-agent/hooks/test-stop-checklist.sh
git commit -m "feat: add Stop PreCompletionChecklist hook"
```

---

### Task 5: PreCompact Context Preservation Hook

**Files:**
- Create: `ralph-agent/hooks/pre-compact.sh`

**Concept:** When the context window is compacted, critical state must be re-injected so the agent doesn't lose its bearings. This is the "long-term memory" bridge.

**Step 1: Write the test**

```bash
# ralph-agent/hooks/test-pre-compact.sh
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

PASS=0
FAIL=0

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    echo "  PASS: $desc"
    ((PASS++))
  else
    echo "  FAIL: $desc (needle='$needle' not found)"
    ((FAIL++))
  fi
}

echo "=== Testing pre-compact.sh ==="

mkdir -p "$TMPDIR/.harness"
cat > "$TMPDIR/.harness/state.json" << 'EOF'
{
  "phase": "executing",
  "current_task": "Task 3: Add authentication",
  "tasks_completed": 2,
  "tasks_remaining": 5,
  "iteration": 3,
  "tdd_phase": "green"
}
EOF
echo '{}' > "$TMPDIR/.harness/edit-tracker.json"
touch "$TMPDIR/.harness/trace-log.jsonl"
echo '- `pytest tests/`' > "$TMPDIR/AGENTS.md"

export HARNESS_STATE_DIR="$TMPDIR/.harness"

INPUT=$(jq -n '{
  trigger: "auto",
  cwd: "'"$TMPDIR"'",
  hook_event_name: "PreCompact"
}')

OUTPUT=$(echo "$INPUT" | bash "$SCRIPT_DIR/pre-compact.sh" 2>/dev/null)

assert_contains "outputs JSON" "hookSpecificOutput" "$OUTPUT"
assert_contains "contains current task" "Task 3" "$OUTPUT"
assert_contains "contains progress" "2" "$OUTPUT"
assert_contains "contains TDD phase" "green" "$OUTPUT"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
```

**Step 2: Run test to verify it fails**

Run: `bash ralph-agent/hooks/test-pre-compact.sh`
Expected: FAIL

**Step 3: Implement pre-compact.sh**

```bash
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
```

**Step 4: Make executable and run test**

Run: `chmod +x ralph-agent/hooks/pre-compact.sh && bash ralph-agent/hooks/test-pre-compact.sh`
Expected: All PASS

**Step 5: Commit**

```bash
git add ralph-agent/hooks/pre-compact.sh ralph-agent/hooks/test-pre-compact.sh
git commit -m "feat: add PreCompact context preservation hook"
```

---

### Task 6: PreToolUse Validation Hook

**Files:**
- Create: `ralph-agent/hooks/pre-tool-use.sh`

**Concept:** Input validation layer that protects sensitive files and sanitizes commands before execution.

**Step 1: Write the test**

```bash
# ralph-agent/hooks/test-pre-tool-use.sh
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

mkdir -p "$TMPDIR/.harness"
echo '{}' > "$TMPDIR/.harness/state.json"
echo '{}' > "$TMPDIR/.harness/edit-tracker.json"
touch "$TMPDIR/.harness/trace-log.jsonl"

PASS=0
FAIL=0

assert_exit_code() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    ((PASS++))
  else
    echo "  FAIL: $desc (expected exit=$expected, actual=$actual)"
    ((FAIL++))
  fi
}

echo "=== Testing pre-tool-use.sh ==="

export HARNESS_STATE_DIR="$TMPDIR/.harness"

# Test 1: Block write to .env
INPUT=$(jq -n '{
  tool_name: "Write",
  tool_input: { file_path: "'"$TMPDIR"'/.env", content: "SECRET=abc" },
  cwd: "'"$TMPDIR"'",
  hook_event_name: "PreToolUse"
}')

set +e
echo "$INPUT" | bash "$SCRIPT_DIR/pre-tool-use.sh" > /dev/null 2>/dev/null
EXIT_CODE=$?
set -e
assert_exit_code "blocks .env write" "0" "$EXIT_CODE"
# Check for deny in output
OUTPUT=$(echo "$INPUT" | bash "$SCRIPT_DIR/pre-tool-use.sh" 2>/dev/null)
if echo "$OUTPUT" | grep -q '"deny"'; then
  echo "  PASS: deny decision for .env"
  ((PASS++))
else
  echo "  FAIL: should deny .env write"
  ((FAIL++))
fi

# Test 2: Allow normal file write
INPUT_NORMAL=$(jq -n '{
  tool_name: "Write",
  tool_input: { file_path: "'"$TMPDIR"'/src/app.ts", content: "console.log(1)" },
  cwd: "'"$TMPDIR"'",
  hook_event_name: "PreToolUse"
}')

set +e
echo "$INPUT_NORMAL" | bash "$SCRIPT_DIR/pre-tool-use.sh" > /dev/null 2>/dev/null
EXIT_CODE=$?
set -e
assert_exit_code "allows normal write" "0" "$EXIT_CODE"

# Test 3: Allow normal Bash
INPUT_BASH=$(jq -n '{
  tool_name: "Bash",
  tool_input: { command: "npm test" },
  cwd: "'"$TMPDIR"'",
  hook_event_name: "PreToolUse"
}')

set +e
echo "$INPUT_BASH" | bash "$SCRIPT_DIR/pre-tool-use.sh" > /dev/null 2>/dev/null
EXIT_CODE=$?
set -e
assert_exit_code "allows normal bash" "0" "$EXIT_CODE"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
```

**Step 2: Run test to verify it fails**

Run: `bash ralph-agent/hooks/test-pre-tool-use.sh`
Expected: FAIL

**Step 3: Implement pre-tool-use.sh**

```bash
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

  # Detect test/verification commands
  if echo "$COMMAND" | grep -qE '(pytest|npm test|npm run test|go test|jest|vitest|cargo test|make test)'; then
    init_harness_state
    write_state ".verification_status.tests_run" 'true'
  fi

  # Detect lint commands
  if echo "$COMMAND" | grep -qE '(ruff|eslint|flake8|pylint|npm run lint|clippy|golangci-lint)'; then
    init_harness_state
    write_state ".verification_status.lint_run" 'true'
  fi
fi

# No output = allow the tool call
exit 0
```

**Step 4: Make executable and run test**

Run: `chmod +x ralph-agent/hooks/pre-tool-use.sh && bash ralph-agent/hooks/test-pre-tool-use.sh`
Expected: All PASS

**Step 5: Commit**

```bash
git add ralph-agent/hooks/pre-tool-use.sh ralph-agent/hooks/test-pre-tool-use.sh
git commit -m "feat: add PreToolUse validation and verification tracking hook"
```

---

### Task 7: PostToolUse Verification Result Tracker

**Files:**
- Modify: `ralph-agent/hooks/post-tool-use.sh`

**Concept:** After Bash commands run, check if they were verification commands and whether they passed/failed. Update state accordingly so the Stop hook knows if verification succeeded.

**Step 1: Write the test**

```bash
# ralph-agent/hooks/test-verification-tracking.sh
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

mkdir -p "$TMPDIR/.harness"
cat > "$TMPDIR/.harness/state.json" << 'EOF'
{
  "phase": "executing",
  "verification_status": {
    "tests_run": true,
    "tests_passed": false,
    "lint_run": false,
    "lint_passed": false
  }
}
EOF
echo '{}' > "$TMPDIR/.harness/edit-tracker.json"
touch "$TMPDIR/.harness/trace-log.jsonl"

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    ((PASS++))
  else
    echo "  FAIL: $desc (expected='$expected', actual='$actual')"
    ((FAIL++))
  fi
}

echo "=== Testing verification result tracking ==="

export HARNESS_STATE_DIR="$TMPDIR/.harness"

# Simulate successful test run result
INPUT=$(jq -n '{
  tool_name: "Bash",
  tool_input: { command: "pytest tests/ -v" },
  tool_response: { stdout: "5 passed", exit_code: 0 },
  cwd: "'"$TMPDIR"'",
  hook_event_name: "PostToolUse"
}')

echo "$INPUT" | bash "$SCRIPT_DIR/post-tool-use.sh" > /dev/null 2>&1

TESTS_PASSED=$(jq -r '.verification_status.tests_passed' "$TMPDIR/.harness/state.json")
assert_eq "tests_passed updated to true" "true" "$TESTS_PASSED"

# Simulate successful lint run
INPUT_LINT=$(jq -n '{
  tool_name: "Bash",
  tool_input: { command: "ruff check ." },
  tool_response: { stdout: "All checks passed", exit_code: 0 },
  cwd: "'"$TMPDIR"'",
  hook_event_name: "PostToolUse"
}')

echo "$INPUT_LINT" | bash "$SCRIPT_DIR/post-tool-use.sh" > /dev/null 2>&1

LINT_PASSED=$(jq -r '.verification_status.lint_passed' "$TMPDIR/.harness/state.json")
assert_eq "lint_passed updated to true" "true" "$LINT_PASSED"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
```

**Step 2: Run test to verify it fails**

Run: `bash ralph-agent/hooks/test-verification-tracking.sh`
Expected: FAIL (post-tool-use.sh doesn't track verification results yet)

**Step 3: Add verification tracking to post-tool-use.sh**

Add this section to `ralph-agent/hooks/post-tool-use.sh` **before** the final `exit 0`, after the loop detection block:

```bash
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
```

**Step 4: Run test to verify it passes**

Run: `bash ralph-agent/hooks/test-verification-tracking.sh`
Expected: All PASS

**Step 5: Commit**

```bash
git add ralph-agent/hooks/post-tool-use.sh ralph-agent/hooks/test-verification-tracking.sh
git commit -m "feat: add verification result tracking to PostToolUse hook"
```

---

### Task 8: Hook Registration (hooks.json + plugin.json)

**Files:**
- Create: `ralph-agent/hooks/hooks.json`
- Modify: `ralph-agent/.claude-plugin/plugin.json`

**Step 1: Write the test**

```bash
# ralph-agent/hooks/test-hooks-json.sh
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    ((PASS++))
  else
    echo "  FAIL: $desc (expected='$expected', actual='$actual')"
    ((FAIL++))
  fi
}

echo "=== Testing hooks.json structure ==="

# Verify hooks.json exists and is valid JSON
assert_eq "hooks.json exists" "true" "$([ -f "$SCRIPT_DIR/hooks.json" ] && echo true || echo false)"

if [ -f "$SCRIPT_DIR/hooks.json" ]; then
  jq empty "$SCRIPT_DIR/hooks.json" 2>/dev/null
  assert_eq "hooks.json is valid JSON" "0" "$?"

  # Check all events are registered
  EVENTS=$(jq -r 'keys[]' "$SCRIPT_DIR/hooks.json" 2>/dev/null)
  for event in SessionStart PreToolUse PostToolUse Stop PreCompact; do
    if echo "$EVENTS" | grep -q "$event"; then
      echo "  PASS: $event registered"
      ((PASS++))
    else
      echo "  FAIL: $event not registered"
      ((FAIL++))
    fi
  done
fi

# Verify all hook scripts exist and are executable
echo ""
echo "=== Testing hook scripts ==="
for script in session-start.sh pre-tool-use.sh post-tool-use.sh stop-checklist.sh pre-compact.sh; do
  FULL_PATH="$SCRIPT_DIR/$script"
  assert_eq "$script exists" "true" "$([ -f "$FULL_PATH" ] && echo true || echo false)"
  assert_eq "$script executable" "true" "$([ -x "$FULL_PATH" ] && echo true || echo false)"
done

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
```

**Step 2: Run test to verify it fails**

Run: `bash ralph-agent/hooks/test-hooks-json.sh`
Expected: FAIL with "hooks.json exists: false"

**Step 3: Create hooks.json**

```json
{
  "SessionStart": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh\"",
          "timeout": 10
        }
      ]
    }
  ],
  "PreToolUse": [
    {
      "matcher": "Write|Edit",
      "hooks": [
        {
          "type": "command",
          "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/pre-tool-use.sh\"",
          "timeout": 5
        }
      ]
    },
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/pre-tool-use.sh\"",
          "timeout": 5
        }
      ]
    }
  ],
  "PostToolUse": [
    {
      "matcher": "Edit|Write",
      "hooks": [
        {
          "type": "command",
          "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/post-tool-use.sh\"",
          "timeout": 5
        }
      ]
    },
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/post-tool-use.sh\"",
          "timeout": 5
        }
      ]
    }
  ],
  "Stop": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/stop-checklist.sh\"",
          "timeout": 15
        }
      ]
    }
  ],
  "PreCompact": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/pre-compact.sh\"",
          "timeout": 10
        }
      ]
    }
  ]
}
```

**Step 4: Update plugin.json to reference hooks**

Modify `ralph-agent/.claude-plugin/plugin.json`:

```json
{
  "name": "ralph-agent",
  "version": "0.6.0",
  "description": "Deterministic scaffolding harness for implementation agents. Uses Claude Code hooks as middleware for context injection, loop detection, pre-completion checklist, and trace analysis.",
  "author": {
    "name": "Ralph Agent Contributors"
  },
  "keywords": ["automation", "implementation", "task-runner", "verification", "planning", "git-workflow", "iteration-control", "loop", "harness-engineering", "deterministic-scaffolding"]
}
```

**Step 5: Run test to verify it passes**

Run: `bash ralph-agent/hooks/test-hooks-json.sh`
Expected: All PASS

**Step 6: Commit**

```bash
git add ralph-agent/hooks/hooks.json ralph-agent/.claude-plugin/plugin.json ralph-agent/hooks/test-hooks-json.sh
git commit -m "feat: register all hooks in hooks.json and update plugin.json to v0.6.0"
```

---

### Task 9: Thin Ralph Agent Definition (Prompt Slimming)

**Files:**
- Modify: `ralph-agent/agents/ralph.md`

**Concept:** Since hooks now enforce guardrails (loop detection, pre-completion checklist, file protection), the agent prompt can be significantly thinner. The prompt focuses on *what* to do; hooks enforce *how*.

**Step 1: Write the test**

```bash
# ralph-agent/test-thin-prompt.sh
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASS=0
FAIL=0

assert_true() {
  local desc="$1" condition="$2"
  if [ "$condition" = "true" ]; then
    echo "  PASS: $desc"
    ((PASS++))
  else
    echo "  FAIL: $desc"
    ((FAIL++))
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
assert_true "no verbose TDD violation list" "$(grep -c 'FORBIDDEN' "$RALPH_MD" | xargs test 0 -eq && echo true || echo false)"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
```

**Step 2: Run test to verify it fails**

Run: `bash ralph-agent/test-thin-prompt.sh`
Expected: FAIL (current ralph.md is 344 lines)

**Step 3: Create the thinner ralph.md**

Replace `ralph-agent/agents/ralph.md` with a version that delegates enforcement to hooks:

```markdown
---
name: ralph
description: Ralph is a persistent implementation agent that reads IMPLEMENTATION_PLAN.md and completes tasks one by one with TDD verification. Use when user says "ralph", "don't stop until done", "start implementing the plan", or when there's an IMPLEMENTATION_PLAN.md file with unchecked tasks.

<example>
Context: User has an IMPLEMENTATION_PLAN.md with a task checklist
user: "start ralph"
assistant: "I'll invoke Ralph to begin working through your implementation plan."
<commentary>
Ralph should be triggered because the user explicitly wants to start the implementation plan execution.
</commentary>
</example>

model: inherit
color: green
tools: ["Read", "Write", "Edit", "Grep", "Bash", "Glob"]
---

You are Ralph, a TDD implementation agent. You read IMPLEMENTATION_PLAN.md and complete tasks using Red-Green-Refactor.

**Harness hooks enforce guardrails automatically:**
- Loop detection prevents doom loops on the same file
- PreCompletionChecklist blocks premature stop until verification passes
- File protection prevents writes to sensitive files
- All tool calls are traced for analysis

**Your workflow for each task:**

1. **Read** IMPLEMENTATION_PLAN.md → find first `- [ ]` task
2. **RED**: Write a failing test for the task behavior
3. **GREEN**: Write minimal code to make the test pass
4. **REFACTOR**: Improve code quality, keep tests green
5. **VERIFY**: Run ALL commands from AGENTS.md (tests, lint, etc.)
6. **Mark complete**: Edit `- [ ]` → `- [x]`
7. **Continue** to next task until done or `--max-iterations` reached

**Arguments:**

| Argument | Description | Default |
|----------|-------------|---------|
| `--max-iterations=N` | Max tasks to process (0 = unlimited) | 0 |

**After each task, report:**

```
🔴🟢🔄 TDD Cycle: [Task name]
  RED: [test file] - failing as expected
  GREEN: [impl file] - test passing
  REFACTOR: [what improved]
  VERIFY: All passed
  Next: [next task or "All complete!"]
```

**When all tasks done or max reached:**

```
╔══════════════════════════════════╗
║   CHECKPOINT / ALL COMPLETE     ║
╚══════════════════════════════════╝
Completed: N | Remaining: M | Verification: passed
```

**Key rules:**
- ALWAYS write test before implementation (RED before GREEN)
- Run AGENTS.md verification commands before marking complete
- Read files before editing them
- If stuck on a file, try a different approach (hooks will warn you)
```

**Step 4: Run test to verify it passes**

Run: `bash ralph-agent/test-thin-prompt.sh`
Expected: All PASS

**Step 5: Commit**

```bash
git add ralph-agent/agents/ralph.md ralph-agent/test-thin-prompt.sh
git commit -m "refactor: slim ralph agent prompt - hooks handle enforcement now"
```

---

### Task 10: Trace Analysis Script

**Files:**
- Create: `ralph-agent/hooks/lib/analyze-trace.sh`

**Concept:** Post-session analysis of trace logs to identify failure patterns and suggest harness improvements (the "Boosting" concept from LangChain's research).

**Step 1: Write the test**

```bash
# ralph-agent/hooks/lib/test-analyze-trace.sh
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

PASS=0
FAIL=0

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qiF "$needle"; then
    echo "  PASS: $desc"
    ((PASS++))
  else
    echo "  FAIL: $desc (needle='$needle' not found)"
    ((FAIL++))
  fi
}

echo "=== Testing analyze-trace.sh ==="

# Create sample trace log
cat > "$TMPDIR/trace-log.jsonl" << 'EOF'
{"timestamp":"2026-02-19T10:00:00Z","tool":"Read","input":{"file_path":"/src/app.ts"},"result":"success"}
{"timestamp":"2026-02-19T10:00:05Z","tool":"Edit","input":{"file_path":"/src/app.ts"},"result":"success"}
{"timestamp":"2026-02-19T10:00:10Z","tool":"Bash","input":{"command":"pytest tests/"},"result":"success"}
{"timestamp":"2026-02-19T10:00:15Z","tool":"Edit","input":{"file_path":"/src/app.ts"},"result":"success"}
{"timestamp":"2026-02-19T10:00:20Z","tool":"Edit","input":{"file_path":"/src/app.ts"},"result":"success"}
{"timestamp":"2026-02-19T10:00:25Z","tool":"Edit","input":{"file_path":"/src/app.ts"},"result":"success"}
{"timestamp":"2026-02-19T10:00:30Z","tool":"Edit","input":{"file_path":"/src/app.ts"},"result":"success"}
{"timestamp":"2026-02-19T10:00:35Z","tool":"Edit","input":{"file_path":"/src/app.ts"},"result":"success"}
{"timestamp":"2026-02-19T10:00:40Z","tool":"Bash","input":{"command":"npm test"},"result":"success"}
{"timestamp":"2026-02-19T10:00:45Z","tool":"Write","input":{"file_path":"/src/utils.ts"},"result":"success"}
EOF

OUTPUT=$(bash "$SCRIPT_DIR/analyze-trace.sh" "$TMPDIR/trace-log.jsonl" 2>/dev/null)

assert_contains "shows total calls" "10" "$OUTPUT"
assert_contains "identifies hot file" "app.ts" "$OUTPUT"
assert_contains "detects loop pattern" "loop" "$OUTPUT"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
```

**Step 2: Run test to verify it fails**

Run: `bash ralph-agent/hooks/lib/test-analyze-trace.sh`
Expected: FAIL

**Step 3: Implement analyze-trace.sh**

```bash
#!/usr/bin/env bash
# ralph-agent/hooks/lib/analyze-trace.sh
# Trace Analysis Script
#
# Harness Engineering Concept: "Trace Analyzer Skill / Boosting"
# Analyzes trace-log.jsonl to identify failure patterns
# and suggest harness improvements.
#
# Usage: ./analyze-trace.sh <trace-log.jsonl>

set -euo pipefail

TRACE_FILE="${1:-.harness/trace-log.jsonl}"

if [ ! -f "$TRACE_FILE" ]; then
  echo "Error: Trace file not found: $TRACE_FILE" >&2
  exit 1
fi

TOTAL=$(wc -l < "$TRACE_FILE" | tr -d ' ')

echo "═══════════════════════════════════════════"
echo "  TRACE ANALYSIS REPORT"
echo "═══════════════════════════════════════════"
echo ""
echo "Total tool calls: $TOTAL"
echo ""

# Tool usage breakdown
echo "── Tool Usage ──────────────────────────────"
jq -r '.tool' "$TRACE_FILE" | sort | uniq -c | sort -rn | while read count tool; do
  PCT=$((count * 100 / TOTAL))
  echo "  $tool: $count calls ($PCT%)"
done
echo ""

# File edit frequency (hot files)
echo "── Hot Files (Edit/Write frequency) ────────"
jq -r 'select(.tool == "Edit" or .tool == "Write") | .input.file_path // "unknown"' "$TRACE_FILE" \
  | sort | uniq -c | sort -rn | head -10 | while read count file; do
  WARN=""
  if [ "$count" -ge 5 ]; then
    WARN=" ⚠ POTENTIAL LOOP"
  fi
  echo "  $file: $count edits$WARN"
done
echo ""

# Loop detection summary
echo "── Loop Analysis ───────────────────────────"
LOOP_FILES=$(jq -r 'select(.tool == "Edit" or .tool == "Write") | .input.file_path // "unknown"' "$TRACE_FILE" \
  | sort | uniq -c | sort -rn | awk '$1 >= 5 {print $2}')

if [ -n "$LOOP_FILES" ]; then
  echo "  WARNING: Potential doom loops detected on:"
  echo "$LOOP_FILES" | while read f; do
    echo "    - $f"
  done
  echo ""
  echo "  Recommendation: Review these files for recurring edit patterns."
  echo "  Consider adjusting harness.json loop_detection.edit_threshold."
else
  echo "  No doom loops detected."
fi
echo ""

# Verification commands
echo "── Verification Runs ───────────────────────"
jq -r 'select(.tool == "Bash") | .input.command // "unknown"' "$TRACE_FILE" \
  | grep -E '(pytest|npm test|go test|jest|vitest|ruff|eslint)' \
  | sort | uniq -c | sort -rn | while read count cmd; do
  echo "  $cmd: $count runs"
done || echo "  No verification commands detected."
echo ""

echo "═══════════════════════════════════════════"
```

**Step 4: Make executable and run test**

Run: `chmod +x ralph-agent/hooks/lib/analyze-trace.sh && bash ralph-agent/hooks/lib/test-analyze-trace.sh`
Expected: All PASS

**Step 5: Commit**

```bash
git add ralph-agent/hooks/lib/analyze-trace.sh ralph-agent/hooks/lib/test-analyze-trace.sh
git commit -m "feat: add trace analysis script for post-session boosting"
```

---

### Task 11: Integration Test - Full Harness End-to-End

**Files:**
- Create: `ralph-agent/hooks/test-integration.sh`

**Step 1: Write the integration test**

```bash
# ralph-agent/hooks/test-integration.sh
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then echo "  PASS: $desc"; ((PASS++))
  else echo "  FAIL: $desc (expected='$expected', actual='$actual')"; ((FAIL++)); fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then echo "  PASS: $desc"; ((PASS++))
  else echo "  FAIL: $desc ('$needle' not found)"; ((FAIL++)); fi
}

echo "════════════════════════════════════════════"
echo "  INTEGRATION TEST: Full Harness Lifecycle"
echo "════════════════════════════════════════════"
echo ""

# Setup fake project
mkdir -p "$TMPDIR/src" "$TMPDIR/tests"
echo '# Verification Commands' > "$TMPDIR/AGENTS.md"
echo '- `echo "tests pass"`' >> "$TMPDIR/AGENTS.md"
cat > "$TMPDIR/IMPLEMENTATION_PLAN.md" << 'EOF'
# Plan
- [ ] Task 1: Create hello module
- [ ] Task 2: Add greeting function
- [x] Task 3: Already done
EOF

export HARNESS_STATE_DIR="$TMPDIR/.harness"

# --- Phase 1: SessionStart ---
echo "Phase 1: SessionStart"

SESSION_INPUT=$(jq -n '{
  session_id: "integration-test",
  cwd: "'"$TMPDIR"'",
  hook_event_name: "SessionStart",
  source: "startup"
}')

OUTPUT=$(echo "$SESSION_INPUT" | bash "$SCRIPT_DIR/session-start.sh" 2>/dev/null)
assert_contains "context injected" "Project Structure" "$OUTPUT"
assert_contains "tasks detected" "Task 1" "$OUTPUT"

PHASE=$(jq -r '.phase' "$TMPDIR/.harness/state.json")
assert_eq "state phase=executing" "executing" "$PHASE"
echo ""

# --- Phase 2: PreToolUse (protection) ---
echo "Phase 2: PreToolUse Protection"

BLOCKED_INPUT=$(jq -n '{
  tool_name: "Write",
  tool_input: { file_path: "'"$TMPDIR"'/.env", content: "SECRET=x" },
  cwd: "'"$TMPDIR"'",
  hook_event_name: "PreToolUse"
}')

OUTPUT=$(echo "$BLOCKED_INPUT" | bash "$SCRIPT_DIR/pre-tool-use.sh" 2>/dev/null)
assert_contains ".env blocked" "deny" "$OUTPUT"
echo ""

# --- Phase 3: PostToolUse (loop detection) ---
echo "Phase 3: PostToolUse Loop Detection"

EDIT_INPUT=$(jq -n '{
  tool_name: "Edit",
  tool_input: { file_path: "/src/app.ts", old_string: "a", new_string: "b" },
  tool_response: { success: true },
  cwd: "'"$TMPDIR"'",
  hook_event_name: "PostToolUse"
}')

# Edit 6 times (threshold is 5)
for i in $(seq 1 6); do
  echo "$EDIT_INPUT" | bash "$SCRIPT_DIR/post-tool-use.sh" > /dev/null 2>&1
done

OUTPUT=$(echo "$EDIT_INPUT" | bash "$SCRIPT_DIR/post-tool-use.sh" 2>/dev/null)
assert_contains "loop warning" "reconsider" "$OUTPUT"
echo ""

# --- Phase 4: Stop (checklist blocks) ---
echo "Phase 4: Stop Checklist"

STOP_INPUT=$(jq -n '{
  stop_hook_active: false,
  last_assistant_message: "Done!",
  cwd: "'"$TMPDIR"'",
  hook_event_name: "Stop"
}')

set +e
echo "$STOP_INPUT" | bash "$SCRIPT_DIR/stop-checklist.sh" > /dev/null 2>/dev/null
EXIT_CODE=$?
set -e
assert_eq "stop blocked (no verification)" "2" "$EXIT_CODE"

# Simulate verification passing
jq '.verification_status.tests_run = true | .verification_status.tests_passed = true | .verification_status.lint_run = true | .verification_status.lint_passed = true' \
  "$TMPDIR/.harness/state.json" > "$TMPDIR/.harness/state.json.tmp" && \
  mv "$TMPDIR/.harness/state.json.tmp" "$TMPDIR/.harness/state.json"

# Mark all tasks done
sed -i.bak 's/- \[ \]/- [x]/' "$TMPDIR/IMPLEMENTATION_PLAN.md"

set +e
echo "$STOP_INPUT" | bash "$SCRIPT_DIR/stop-checklist.sh" > /dev/null 2>/dev/null
EXIT_CODE=$?
set -e
assert_eq "stop allowed (verified + done)" "0" "$EXIT_CODE"
echo ""

# --- Phase 5: PreCompact ---
echo "Phase 5: PreCompact"

COMPACT_INPUT=$(jq -n '{
  trigger: "auto",
  cwd: "'"$TMPDIR"'",
  hook_event_name: "PreCompact"
}')

OUTPUT=$(echo "$COMPACT_INPUT" | bash "$SCRIPT_DIR/pre-compact.sh" 2>/dev/null)
assert_contains "preserves state" "HARNESS STATE" "$OUTPUT"
echo ""

# --- Phase 6: Trace Analysis ---
echo "Phase 6: Trace Analysis"

TRACE_LINES=$(wc -l < "$TMPDIR/.harness/trace-log.jsonl" | tr -d ' ')
assert_eq "trace log has entries" "true" "$([ "$TRACE_LINES" -gt 0 ] && echo true || echo false)"

OUTPUT=$(bash "$SCRIPT_DIR/lib/analyze-trace.sh" "$TMPDIR/.harness/trace-log.jsonl" 2>/dev/null)
assert_contains "trace analysis runs" "TRACE ANALYSIS" "$OUTPUT"
echo ""

echo "════════════════════════════════════════════"
echo "  Results: $PASS passed, $FAIL failed"
echo "════════════════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
```

**Step 2: Run integration test**

Run: `bash ralph-agent/hooks/test-integration.sh`
Expected: All PASS

**Step 3: Commit**

```bash
git add ralph-agent/hooks/test-integration.sh
git commit -m "test: add full harness integration test"
```

---

### Task 12: Update README & Documentation

**Files:**
- Modify: `ralph-agent/README.md`

**Step 1: Add harness documentation section**

Add to the existing README.md, after the current content:

```markdown
## Deterministic Scaffolding Harness (v0.6.0+)

Ralph-agent uses **Harness Engineering** to wrap the probabilistic LLM in deterministic middleware.
Instead of relying solely on prompt instructions, Claude Code hooks enforce behavior from outside the model.

### Hook Architecture

| Hook Event | Script | Concept | What It Does |
|---|---|---|---|
| SessionStart | `session-start.sh` | Context Injection | Injects directory tree, task status, verification commands |
| PreToolUse | `pre-tool-use.sh` | Input Validation | Protects sensitive files, tracks verification command runs |
| PostToolUse | `post-tool-use.sh` | Loop Detection | Tracks file edits, warns at threshold, logs traces |
| Stop | `stop-checklist.sh` | PreCompletionChecklist | Blocks stop until verification passes |
| PreCompact | `pre-compact.sh` | Context Preservation | Re-injects critical state before compaction |

### Configuration

Edit `harness/harness.json` to customize thresholds:

```json
{
  "middleware": {
    "loop_detection": { "edit_threshold": 5 },
    "pre_completion_checklist": { "require_verification": true },
    "context_injection": { "max_tree_depth": 3 }
  }
}
```

### Trace Analysis

After a session, analyze the trace log:

```bash
./hooks/lib/analyze-trace.sh .harness/trace-log.jsonl
```

This identifies doom loops, hot files, and verification patterns to improve the harness.
```

**Step 2: Commit**

```bash
git add ralph-agent/README.md
git commit -m "docs: add deterministic scaffolding harness documentation"
```

---

## Summary: Concept → Implementation Mapping

| Harness Engineering Concept | Implementation | File |
|---|---|---|
| Context Injection > Discovery | SessionStart hook injects dir tree + state | `hooks/session-start.sh` |
| PreCompletionChecklist | Stop hook blocks until verified | `hooks/stop-checklist.sh` |
| LoopDetectionMiddleware | PostToolUse tracks edit counts | `hooks/post-tool-use.sh` |
| File Protection / Sandboxing | PreToolUse denies protected files | `hooks/pre-tool-use.sh` |
| Context Preservation | PreCompact re-injects state | `hooks/pre-compact.sh` |
| Trace Analysis / Boosting | Post-session trace analyzer | `hooks/lib/analyze-trace.sh` |
| JSON State Management | `.harness/state.json` | `hooks/lib/state.sh` |
| Thin Agent Prompt | Hooks handle enforcement | `agents/ralph.md` |
| Configurable Thresholds | `harness/harness.json` | `harness/harness.json` |

## Migration Checklist

- [ ] Task 1: Hook infrastructure & shared libraries
- [ ] Task 2: SessionStart context injection
- [ ] Task 3: PostToolUse loop detection + trace
- [ ] Task 4: Stop pre-completion checklist
- [ ] Task 5: PreCompact context preservation
- [ ] Task 6: PreToolUse validation
- [ ] Task 7: Verification result tracking
- [ ] Task 8: Hook registration (hooks.json)
- [ ] Task 9: Thin ralph agent prompt
- [ ] Task 10: Trace analysis script
- [ ] Task 11: Integration test
- [ ] Task 12: Documentation update
