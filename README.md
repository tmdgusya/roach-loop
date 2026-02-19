# Ralph Agent

A Claude Code plugin that automatically executes implementation plans. Give it a task list and it implements each one in order, fixes itself until verification passes, then moves to the next task.

## Why Use This

- **Continuous Execution**: Finishes one task and automatically moves to the next. No need to manually prompt each step
- **Verification Gating**: Tasks are only marked complete when tests/linting pass. The agent cannot stop and claim "done" without proof
- **Loop Detection**: Warns and forces strategy reconsideration if the same file is edited 5+ times
- **File Protection**: Blocks writes to sensitive files like `.env`, `*.pem`, `*.key`
- **Context Preservation**: Re-injects current progress and verification commands even after conversation compaction

## Installation

Run two commands in Claude Code:

```bash
# 1. Add the marketplace
/plugin marketplace add tmdgusya/roach-loop

# 2. Install the plugin
/plugin install ralph-agent@ralph-agent-marketplace
```

To update:
```bash
/plugin update ralph-agent
```

## Quick Start

Two workflows are available. Pick the one that fits your situation.

### Ralph Workflow — Write your own task list and execute

You write the task list manually. Ralph implements each task in order. You handle Git yourself.

**Step 1: Create the plan file**

```bash
/ralph-agent:ralph-init
```

**Step 2: Write your tasks**

Open `IMPLEMENTATION_PLAN.md` and fill in tasks:

```markdown
# Implementation Plan

## Tasks
- [ ] Create SQLAlchemy User model (id, email, name, created_at)
- [ ] Implement POST /users endpoint with input validation
- [ ] Implement GET /users/:id endpoint with 404 handling
- [ ] Write pytest tests for all endpoints
```

**Step 3: Set up verification commands**

Create `AGENTS.md` in your project root:

```markdown
# Verification Commands
- `pytest tests/ -v`
- `ruff check .`
```

**Step 4: Run**

```bash
/ralph-agent:ralph
```

Ralph finds the first unchecked task (`- [ ]`), implements it, runs all verification commands, and marks it `- [x]` when they pass. Then moves to the next task.

### Geoff Workflow — Auto-generate plan from specs + Git management

Write requirements in a `specs/` directory. Geoff generates the plan automatically and handles Git commits and version tags.

**Step 1: Write specs**

```bash
mkdir specs
```

Create requirement files in `specs/`:

```markdown
# specs/user-auth.md

## Feature: User Authentication

### Requirements
- Users can register with email/password
- Users can login with JWT tokens
- Passwords are hashed with bcrypt
```

**Step 2: Generate the plan**

```bash
/ralph-agent:gplan
```

Analyzes your specs and generates `IMPLEMENTATION_PLAN.md` automatically.

**Step 3: Build**

```bash
/ralph-agent:gbuild
```

Implements each task, runs tests, then automatically `git commit → push → tag (0.0.0, 0.0.1, ...)`.

### Which workflow should I use?

| Situation | Recommended | Commands |
|-----------|-------------|----------|
| I want to manage my own task list | Ralph | `/ralph-agent:ralph-init` → `/ralph-agent:ralph` |
| I want to handle Git commits myself | Ralph | `/ralph-agent:ralph` |
| I have spec documents and want auto-planning | Geoff | `/ralph-agent:gplan` → `/ralph-agent:gbuild` |
| I want automatic Git commits + version tags | Geoff | `/ralph-agent:gplan` → `/ralph-agent:gbuild` |

## Practical Tips

### Writing good tasks

Specific, independent tasks dramatically improve Ralph's success rate.

| Bad | Good |
|-----|------|
| "Work on auth" | "Implement JWT-based POST /auth/login endpoint" |
| "Add tests" | "Write pytest tests for User model CRUD operations" |
| "Refactor" | "Extract DB logic from UserService into UserRepository" |

**Principles:**
- One task = one verifiable outcome
- Tasks should not depend on each other's completion order
- 30 minutes to 2 hours of work per task is ideal

### Verification command setup

List verification commands in `AGENTS.md`, ordered **fastest first**:

```markdown
# Verification Commands
- `ruff check .`          # Lint (fast)
- `mypy src/`             # Type check (medium)
- `pytest tests/ -v`      # Tests (slow)
```

Ralph runs **all** of these after each task. All must pass before a task is marked complete. If any fail, Ralph fixes the code and retries.

### Iteration limits

For long-running sessions, you can cap the number of tasks:

```bash
# Process only 5 tasks then stop
/ralph-agent:ralph --max-iterations=5

# Pause for user review between tasks
/ralph-agent:loop ralph max=5 pause=true
```

### Stopping mid-session

Type `stop` or `cancel` while Ralph is working. It will finish the current task, save progress to `IMPLEMENTATION_PLAN.md`, and stop. Run `/ralph-agent:ralph` later to resume from where it left off.

## Things to Know

### The `.harness/` directory

Ralph creates a `.harness/` directory in your project root during execution:

```
.harness/
├── state.json          # Session state (current task, verification results, etc.)
├── edit-tracker.json   # Per-file edit counts (for loop detection)
└── trace-log.jsonl     # Log of all tool calls
```

This is for **session state tracking**. Add it to `.gitignore`:

```
.harness/
```

### Loop detection behavior

If the same file is edited 5 times (default threshold), a warning fires:

> "You have edited 'src/api.py' 5 times. STOP and reconsider your approach."

This prevents "doom loops" where the agent keeps making the same mistake. After the warning, the agent tries a different strategy.

### Stop hook behavior

Ralph can only stop when both conditions are met:

1. **Verification commands have been run and passed**
2. **No unchecked tasks (`- [ ]`) remain**

If either condition fails, the stop is blocked and the unmet requirements are displayed.

### File protection

Files matching `.env`, `.env.*`, `*.pem`, `*.key`, `credentials.*` are write-protected. If you intentionally need to write to these files, disable `file_protection` in the harness configuration.

### Harness tuning

Defaults work for most projects. To adjust, edit `harness.json` inside the plugin directory:

```jsonc
// Lower the loop threshold (default: 5)
"edit_threshold": 3

// Add a time budget per session (default: 0 = no limit)
"time_budget_seconds": 1800

// Disable file protection if needed
"file_protection": { "enabled": false }
```

## Troubleshooting

### "No IMPLEMENTATION_PLAN.md found"

No plan file exists. Run `/ralph-agent:ralph-init` to create a template and fill in your tasks.

### "No verification commands found"

`AGENTS.md` is missing or has no verification commands. Create it in your project root with test/lint commands.

### Verification keeps failing

Ralph automatically fixes code and retries on failure. If it keeps failing:

- Check if the task scope is too broad — split into smaller tasks
- Verify that commands in `AGENTS.md` actually work in your environment (dependencies installed, etc.)
- If loop detection triggered, make the task description more specific

### Ralph stopped unexpectedly

Session limits or network issues can interrupt a session. Progress is saved in `IMPLEMENTATION_PLAN.md`, so run `/ralph-agent:ralph` again to resume from the last unchecked task.

## Command Reference

| Command | Description |
|---------|-------------|
| `/ralph-agent:ralph-init` | Create `IMPLEMENTATION_PLAN.md` template |
| `/ralph-agent:ralph` | Execute tasks sequentially (no Git) |
| `/ralph-agent:gplan` | Analyze `specs/` and auto-generate implementation plan |
| `/ralph-agent:gbuild` | Execute tasks + automatic Git commit/tag |
| `/ralph-agent:loop <agent> max=N pause=true` | Iteration limits + pause between tasks |
| `/ralph-agent:spec` | Create a spec file interactively |

## License

MIT
