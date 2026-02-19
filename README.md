# Ralph Agent Plugin

Implementation agents for Claude Code that follow structured implementation plans with continuous task execution, verification, and optional git workflow.

## Overview

This plugin provides two complementary workflows for automated implementation:

### Geoff's Iterative Planning & Building
For projects with specification files in `specs/` directory:
- **Geoff's Planner** (`/ralph-agent:gplan`): Analyzes specs and code, creates prioritized `IMPLEMENTATION_PLAN.md`
- **Geoff's Builder** (`/ralph-agent:gbuild`): Implements tasks with automatic git commits, pushes, and version tags
- Best for: Spec-driven projects requiring git workflow and version tracking

### Ralph's Direct Execution
For projects with manual or existing implementation plans:
- **Ralph** (`/ralph-agent:ralph`): Executes tasks from `IMPLEMENTATION_PLAN.md` sequentially
- Best for: Simple task lists where you manage your own git workflow

## Features

### Geoff's Workflow
- **Parallel Analysis**: Configurable parallel subagents for specs and codebase analysis
- **Spec-Driven Planning**: Automatic plan generation from `specs/` directory
- **Git Workflow**: Automatic add → commit → push → tag (0.0.0 → 0.0.1 → ...)
- **Gap Detection**: Compares implementation against specs, identifies missing features
- **Ultrathink Prioritization**: Uses Opus for deep analysis and task ordering

### Ralph's Workflow
- **Continuous Execution**: Automatically moves to the next task after verification passes
- **Verification Gated**: Never marks a task complete without passing verification
- **Progress Tracking**: Uses markdown checklist format (`- [ ]` / `- [x]`) for task status
- **Error Recovery**: Fixes failed verification and retries until tasks pass
- **Clear Reporting**: Shows progress after each task completion

## Installation

### Method 1: Via Marketplace (Recommended)

Add the ralph-agent marketplace to Claude Code:

```bash
/plugin marketplace add tmdgusya/roach-loop
```

Then install the plugin:

```bash
/plugin install ralph-agent@ralph-agent-marketplace
```

The plugin will be installed globally and available in all projects.

**To update to the latest version:**

```bash
/plugin update ralph-agent
```

### Method 2: Project Local

Copy the plugin to your project's `.claude-plugin/` directory:

```bash
cp -r ralph-agent /path/to/your-project/.claude-plugin/
```

**Optional:** Copy `loop.py` script for external iteration control:

```bash
cp ralph-agent/ralph-agent:loop.py /path/to/your-project/
chmod +x loop.py
```

### Method 3: Global Manual Installation

```bash
cp -r ralph-agent ~/.claude/plugins/ralph-agent:ralph-agent
```

**Optional:** Install `loop.py` globally:

```bash
sudo cp ralph-agent/ralph-agent:loop.py /usr/local/bin/ralph-agent:ralph-loop
# Or create a symlink
ln -s ~/.claude/plugins/ralph-agent:ralph-agent/ralph-agent:loop.py ~/bin/ralph-agent:ralph-loop
```

### Method 4: Command-Line Flag

```bash
cc --plugin-dir /path/to/ralph-agent:ralph-agent
```

**Note:** The `loop.py` script requires access to the ralph-agent plugin. If using global installation, use `--plugin-dir` to specify the plugin path:

```bash
./ralph-agent:loop.py ralph 10 --plugin-dir ~/.claude/plugins/ralph-agent:ralph-agent
```

## Quick Start

### Workflow A: Geoff's Iterative (Recommended for spec-driven projects)

#### 1. Create Specifications Directory

```bash
mkdir specs
```

#### 2. Write Your Specs

Create specification files in `specs/`:

```markdown
# specs/user-auth.md

## Feature: User Authentication

### Requirements
- Users can register with email/password
- Users can login with JWT tokens
- Passwords are hashed with bcrypt

### Acceptance Criteria
- POST /auth/register creates new user
- POST /auth/login returns JWT token
- Passwords stored as hash, not plaintext
```

#### 3. Generate Implementation Plan

```bash
/ralph-agent:gplan
```

This analyzes your specs and creates `IMPLEMENTATION_PLAN.md`.

#### 4. Build with Git Workflow

```bash
/ralph-agent:gbuild
```

Geoff's Builder will:
- Implement each task
- Run tests and fix failures
- Git commit → push → tag (0.0.0, 0.0.1, ...)
- Continue until all tasks complete

### Workflow B: Ralph's Direct (For simple task lists)

#### 1. Create an Implementation Plan

```bash
/ralph-agent:ralph-init
```

This creates `IMPLEMENTATION_PLAN.md` with a template.

#### 2. Edit the Plan

Open `IMPLEMENTATION_PLAN.md` and add your tasks:

```markdown
# Implementation Plan

## Tasks
- [ ] Create database models
- [ ] Implement API endpoints
- [ ] Write unit tests
- [ ] Add authentication
```

#### 3. Set Up Verification

Create or edit `AGENTS.md` with verification commands:

```markdown
# Verification Commands
- `pytest tests/`
- `ruff check .`
```

#### 4. Start Ralph

```bash
/ralph-agent:ralph
```

Ralph will work through all tasks continuously until complete.

**Note:** Ralph does NOT handle git workflow. Commit manually or use `/ralph-agent:gbuild`.

## Commands

### `/ralph-agent:gplan` - Geoff's Planner

Create or update `IMPLEMENTATION_PLAN.md` by analyzing your `specs/` directory.

**Usage:**
```
/ralph-agent:gplan
```

With custom parallelism:
```
/ralph-agent:gplan --parallel=50
```

**What happens:**
1. Studies all files in `specs/` directory using parallel subagents
2. Studies existing `IMPLEMENTATION_PLAN.md` and `src/lib/*`
3. Compares `src/*` implementation against `specs/*` requirements
4. Uses Opus with "Ultrathink" for task prioritization
5. Creates/updates `IMPLEMENTATION_PLAN.md` with prioritized tasks

**Requirements:**
- `specs/` directory must exist with specification files

### `/ralph-agent:gbuild` - Geoff's Builder

Implement tasks from `IMPLEMENTATION_PLAN.md` with git workflow and auto-tagging.

**Usage:**
```
/ralph-agent:gbuild
```

With custom parallelism:
```
/ralph-agent:gbuild --parallel=100
```

**What happens:**
1. Studies `specs/*` with parallel subagents
2. Reads `IMPLEMENTATION_PLAN.md` for task list
3. Searches codebase (doesn't assume not implemented)
4. Implements task completely (no placeholders)
5. Runs tests, fixes failures until pass
6. Git add → commit → push
7. Creates git tag (0.0.0 → 0.0.1 → ...)
8. Continues to next task until all complete

**Requirements:**
- `IMPLEMENTATION_PLAN.md` must exist
- Git repository with remote configured

### `/ralph-agent:ralph`

Start Ralph to work through tasks in `IMPLEMENTATION_PLAN.md`.

**Usage:**
```
/ralph-agent:ralph
```

**What happens:**
1. Ralph reads `IMPLEMENTATION_PLAN.md`
2. Finds the first unchecked task
3. Implements the task
4. Runs verification commands from `AGENTS.md`
5. Marks task complete when verification passes
6. Continues to the next task automatically

**Note:** Ralph does NOT handle git workflow. Use `/ralph-agent:gbuild` for automatic commits/tags.

### `/ralph-agent:ralph-init`

Create a new `IMPLEMENTATION_PLAN.md` template file.

**Usage:**
```
/ralph-agent:ralph-init
```

Creates a template with:
- Project description section
- Prerequisites section
- Task checklist
- Verification section
- Notes section

### `/ralph-agent:loop` - Loop Wrapper Command

Execute any agent with explicit iteration control, pause prompts, and checkpoint summaries.

**Usage:**
```
/ralph-agent:loop ralph max=5 pause=true
/ralph-agent:loop geoff-builder max=10 pause=true parallel=50
/ralph-agent:loop geoff-builder max=0 pause=false
```

**Features:**
- `max=N`: Maximum iterations (0 = unlimited)
- `pause=true`: Prompt user after each task for review
- `parallel=M`: Pass to geoff agents for parallelism

**Best for:**
- Interactive development (5-20 tasks with review)
- Learning agent behavior
- Testing workflows

## Iteration Control

All agents support iteration limits for controlled execution:

### Agent Flags (Simple Limit)

```bash
# Limit to 5 tasks
/ralph-agent:ralph --max-iterations=5

# Limit to 10 tasks with git workflow
/ralph-agent:gbuild --max-iterations=10

# Unlimited (default)
/ralph-agent:gbuild
```

### `/ralph-agent:loop` Command (Full Control)

```bash
# Pause between tasks for review
/ralph-agent:loop ralph max=5 pause=true

# Continuous batch execution
/ralph-agent:loop geoff-builder max=20 pause=false
```

### External `loop.py` Script (Production)

For long-running autonomous work that survives Claude Code session limits:

**Installation:**

The `loop.py` script is included in the ralph-agent plugin. To use it:

```bash
# Option 1: Copy to your project
cp ralph-agent/ralph-agent:loop.py ./

# Option 2: Install globally
sudo cp ralph-agent/ralph-agent:loop.py /usr/local/bin/ralph-agent:ralph-loop

# Option 3: Create symlink
ln -s /path/to/ralph-agent:ralph-agent/ralph-agent:loop.py ~/bin/ralph-agent:ralph-loop
```

**Usage:**

```bash
# Ralph unlimited
./ralph-agent:loop.py ralph

# Ralph max 10 iterations
./ralph-agent:loop.py ralph 10

# Geoff Builder unlimited with custom parallelism
./ralph-agent:loop.py gbuild 0 --parallel 100

# Geoff Builder max 50 iterations
./ralph-agent:loop.py gbuild 50

# With custom plugin path
./ralph-agent:loop.py ralph 20 --plugin-dir /path/to/ralph-agent:ralph-agent
```

**Features:**
- Spawns NEW Claude process each iteration
- Survives Claude Code crashes/restarts
- Git commit between each iteration
- True "infinite loop" capability
- Best for: Production workflows, overnight builds

**Comparison:**

| Method | Session | Max Iterations | Best For |
|--------|---------|---------------|----------|
| Agent flags | Internal | Yes (`--max-iterations`) | Simple limits |
| `/ralph-agent:loop` command | Internal | Yes + pause prompts | Interactive review |
| `loop.py` script | External | Yes + true infinite | Production, long-running |

## File Format

### IMPLEMENTATION_PLAN.md

Uses standard markdown checklist format:

```markdown
# Implementation Plan

## Description
Brief description of plan objectives.

## Prerequisites
- [ ] Dependency 1
- [ ] Dependency 2

## Tasks
- [ ] Task 1: First task description
- [ ] Task 2: Second task description
- [x] Task 3: Already completed

## Verification
- `pytest tests/`
- `npm test`

## Notes
Additional context or reminders.
```

### AGENTS.md

Contains verification commands:

```markdown
# Verification Commands

## General
- `pytest tests/` - Run all tests
- `npm test` - Run test suite

## Linting
- `ruff check .` - Python linting
- `eslint .` - JavaScript linting
```

## How Ralph Works

```
┌─────────────────────────────────────────────────────────────┐
│  1. Read IMPLEMENTATION_PLAN.md                              │
│     → Find first unchecked task (- [ ])                       │
├─────────────────────────────────────────────────────────────┤
│  2. Understand task requirements                              │
│     → Read related files if needed                            │
├─────────────────────────────────────────────────────────────┤
│  3. Implement the task                                       │
│     → Write/modify code                                      │
├─────────────────────────────────────────────────────────────┤
│  4. Verify work                                              │
│     → Read AGENTS.md for verification commands               │
│     → Run ALL verification commands                          │
│     → If fail: fix code and retry                            │
├─────────────────────────────────────────────────────────────┤
│  5. Mark task complete                                       │
│     → Change - [ ] to - [x] in plan                          │
├─────────────────────────────────────────────────────────────┤
│  6. Continue or report                                       │
│     → More tasks? Go to step 2                               │
│     → All done? Report completion and exit                   │
└─────────────────────────────────────────────────────────────┘
```

## User Interaction Flow

This plugin provides two workflows for different use cases:

### Workflow 1: Geoff's Iterative Planning & Building

For projects with specification files in `specs/` directory:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        GEOFF'S ITERATIVE WORKFLOW                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────┐      ┌─────────────┐      ┌─────────────────────────┐    │
│  │   specs/    │─────▶│    /ralph-agent:gplan   │─────▶│ IMPLEMENTATION_PLAN.md │    │
│  │  directory  │      │  (planner)  │      │   (prioritized tasks)   │    │
│  └─────────────┘      └─────────────┘      └───────────┬─────────────┘    │
│         │                                            │ review?             │
│         │           ┌─────────────┐                  │                     │
│         │           │  Edit plan  │◀─────────────────┘                     │
│         │           │  (optional) │                                       │
│         │           └──────┬──────┘                                       │
│         │                  │                                              │
│         │                  ▼                                              │
│         │           ┌─────────────┐      ┌─────────────────────────┐    │
│         │           │   /ralph-agent:gbuild   │─────▶│  Git commits + tags     │    │
│         └──────────▶│  (builder)  │      │  (0.0.0 → 0.0.1 → ...)  │    │
│                     └─────────────┘      └───────────┬─────────────┘    │
│                                                           │               │
│  Specs change? ──────────────────────────────────────────┘               │
│       │                                                                   │
│       ▼                                                                   │
│   Re-run /ralph-agent:gplan                                                           │
│   (updates plan with gaps)                                                │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

Key Features:
• Parallel analysis of specs/ and src/ (configurable with --parallel=N)
• Auto-generates IMPLEMENTATION_PLAN.md from specifications
• Git workflow: commit → push → auto-tag (each task = new version)
• Continuous: repeats until all tasks complete
• Iteration control: --max-iterations=N, /ralph-agent:loop command, or loop.py script
```

### Workflow 2: Ralph's Direct Execution

For projects with manual or existing implementation plans:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          RALPH'S DIRECT WORKFLOW                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────┐      ┌─────────────┐      ┌───────────────────────┐  │
│  │ Manual plan OR  │─────▶│ /ralph-agent:ralph-init │─────▶│ IMPLEMENTATION_PLAN.md│  │
│  │ /ralph-agent:ralph-init     │      │ (optional)  │      │  (you create tasks)   │  │
│  └─────────────────┘      └─────────────┘      └───────────┬───────────┘  │
│                                                     │                     │
│                              ┌─────────────┐        │                     │
│                              │   Edit plan │◀───────┘                     │
│                              │  (required) │                              │
│                              └──────┬──────┘                              │
│                                     │                                      │
│                              ┌──────▼──────┐                              │
│                              │   /ralph-agent:ralph    │                              │
│                              │  (executor) │                              │
│                              └──────┬──────┘                              │
│                                     │                                      │
│                              ┌──────▼──────┐                              │
│                              │ Tasks done  │                              │
│                              │  one by one│                              │
│                              └─────────────┘                              │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

Key Features:
• Simple: create plan → run /ralph-agent:ralph
• No git workflow (you handle commits)
• No specs/ directory required
• Continuous: repeats until all tasks complete
• Iteration control: --max-iterations=N, /ralph-agent:loop command, or loop.py script
```

### Choosing Your Workflow

| Use Case | Recommended Workflow | Commands |
|----------|---------------------|----------|
| I have `specs/` with feature specifications | Geoff's Iterative | `/ralph-agent:gplan` → `/ralph-agent:gbuild` |
| I want automatic git commits + version tags | Geoff's Iterative | `/ralph-agent:gplan` → `/ralph-agent:gbuild` |
| I have a simple task list | Ralph's Direct | `/ralph-agent:ralph-init` → `/ralph-agent:ralph` |
| I manage my own git workflow | Ralph's Direct | `/ralph-agent:ralph` |
| I need to update plan after spec changes | Geoff's Iterative | `/ralph-agent:gplan` (re-run) |

### Comparison

| Feature | Geoff's Workflow | Ralph's Workflow |
|---------|------------------|------------------|
| Specs required | Yes (`specs/` directory) | No |
| Git workflow | Automatic (commit/push/tag) | Manual |
| Planning | Automatic from specs | Manual |
| Version tags | Yes (0.0.0, 0.0.1, ...) | No |
| Parallel analysis | Yes (configurable) | No |
| Iteration control | `--max-iterations`, `/ralph-agent:loop`, `loop.py` | `--max-iterations`, `/ralph-agent:loop`, `loop.py` |
| Best for | Spec-driven projects | Quick task lists |

## Stopping Ralph

To stop Ralph while it's working:

```
stop
```

Or:
```
cancel
```

Ralph will:
- Complete the current task (if in progress)
- Save current state in `IMPLEMENTATION_PLAN.md`
- Report how many tasks remain

## Requirements

- **IMPLEMENTATION_PLAN.md**: Must exist in the current directory
- **AGENTS.md**: Should contain verification commands (optional but recommended)

## Practical Usage Guide

A step-by-step walkthrough of actually using this plugin, from zero to completed tasks.

### Step 1: Initialize the Plan

```bash
/ralph-agent:ralph-init
```

This creates `IMPLEMENTATION_PLAN.md` with a template. Open it and replace the placeholder tasks with your own:

```markdown
# Implementation Plan

## Description
Build a REST API for user management.

## Tasks
- [ ] Create User model with SQLAlchemy (id, email, name, created_at)
- [ ] Implement POST /users endpoint with input validation
- [ ] Implement GET /users/:id endpoint with 404 handling
- [ ] Add pytest test suite for all endpoints
- [ ] Add ruff linting configuration
```

Keep tasks specific and independently verifiable. Each task should produce a testable outcome.

### Step 2: Set Up Verification Commands

Create `AGENTS.md` in your project root:

```markdown
# Verification Commands
- `pytest tests/ -v`
- `ruff check .`
```

These are the commands Ralph runs after each task to confirm it works. The harness tracks whether these have been executed and whether they passed — **Ralph cannot stop until all verification passes**.

### Step 3: (Optional) Tune the Harness

The defaults work well for most projects. But if you need to adjust, edit `harness.json` inside the plugin directory. The location depends on how you installed:

| Installation Method | Path |
|---|---|
| Marketplace | `~/.claude/plugins/cache/*/ralph-agent/*/harness/harness.json` |
| Global manual | `~/.claude/plugins/ralph-agent/harness/harness.json` |
| Project local | `.claude-plugin/ralph-agent/harness/harness.json` |

Example changes:

```jsonc
// Lower the loop threshold for tight files (default: 5)
"edit_threshold": 3

// Add a time budget for each session (default: 0 = no limit)
"time_budget_seconds": 1800

// Disable file protection if you need to write .env
"file_protection": { "enabled": false }
```

### Step 4: Start Ralph

```bash
/ralph-agent:ralph
```

Ralph reads `IMPLEMENTATION_PLAN.md`, finds the first `- [ ]` task, and starts working. Behind the scenes, the harness is active:

```
Session starts
  └─ SessionStart hook fires
       └─ Injects: directory tree, verification commands, task status
           └─ Agent begins Task 1

Agent edits src/models.py
  └─ PreToolUse hook: checks file protection (allowed)
  └─ PostToolUse hook: logs to trace, increments edit count (1/5)

Agent edits src/models.py again
  └─ PostToolUse hook: edit count now 2/5 (still fine)

Agent runs: pytest tests/ -v
  └─ PreToolUse hook: records tests_run = true
  └─ PostToolUse hook: records tests_passed = true

Agent marks Task 1 complete: - [ ] → - [x]
  └─ Moves to Task 2 automatically
```

### Step 5: Let Ralph Work

Ralph will work through all tasks continuously. You'll see output like:

```
✓ Task completed: Create User model with SQLAlchemy
  - Files modified: src/models.py
  - Verification: PASSED
  - Next task: Implement POST /users endpoint

✓ Task completed: Implement POST /users endpoint
  - Files modified: src/api.py, tests/test_users.py
  - Verification: PASSED
  - Next task: Implement GET /users/:id endpoint
```

If Ralph gets stuck editing the same file repeatedly, the loop detection hook kicks in:

```
⚠ LOOP DETECTION WARNING: You have edited 'src/api.py' 5 times.
  STOP and reconsider your approach...
```

### Step 6: Completion

When all tasks are checked off and verification passes, Ralph reports:

```
╔══════════════════════════════════════════╗
║   ALL TASKS COMPLETED SUCCESSFULLY ✓    ║
╚══════════════════════════════════════════╝

Summary:
- Total tasks: 5
- Completed: 5
- Verification: All passed
```

If Ralph tries to stop before verification passes, the Stop hook blocks it:

```
PRECOMPLETION CHECKLIST FAILED - You cannot stop yet.
Blockers:
- Verification tests have NOT been run.
```

### Step 7: Post-Session Analysis

After Ralph finishes, review the trace log in `.harness/trace-log.jsonl`. The plugin includes a trace analysis script you can run:

```bash
# Find and run the analysis script from the plugin directory
# (The exact path depends on your installation method)
bash "$(find ~/.claude/plugins -name analyze-trace.sh 2>/dev/null | head -1)" .harness/trace-log.jsonl
```

Or use `jq` directly for a quick summary:

```bash
# Tool usage breakdown
jq -r '.tool' .harness/trace-log.jsonl | sort | uniq -c | sort -rn

# Hot files (most-edited)
jq -r 'select(.tool == "Edit" or .tool == "Write") | .input.file_path' .harness/trace-log.jsonl | sort | uniq -c | sort -rn
```

This tells you how many tool calls were made, which files were edited most, and whether any doom loops occurred. Use this to refine your task granularity or harness settings for next time.

### For Geoff's Workflow

The same harness applies when using Geoff. The only difference is the setup:

```bash
# 1. Write specs (instead of a manual plan)
mkdir specs
# Create specs/user-api.md with requirements

# 2. Generate the plan from specs
/ralph-agent:gplan

# 3. Review the generated IMPLEMENTATION_PLAN.md

# 4. Build with git workflow
/ralph-agent:gbuild
# (auto-commits, pushes, and tags each completed task)
```

The hooks enforce the same rules: loop detection, file protection, verification gating, and context preservation all work identically regardless of which agent is driving.

## Components

### Agents

#### `ralph`
Core executor agent that implements tasks from `IMPLEMENTATION_PLAN.md` sequentially.

#### `geoff-planner`
Planning agent that analyzes `specs/` directory and codebase to create/update `IMPLEMENTATION_PLAN.md` with prioritized tasks.

#### `geoff-builder`
Implementation agent that executes tasks with git workflow (add/commit/push/tag) and continuous verification.

### Commands

#### `/ralph-agent:ralph`
Start Ralph to execute tasks sequentially without git workflow.

#### `/ralph-agent:ralph-init`
Create an empty `IMPLEMENTATION_PLAN.md` template file.

#### `/ralph-agent:gplan`
Trigger Geoff's Planner to analyze specs and generate/update implementation plan.

#### `/ralph-agent:gbuild`
Trigger Geoff's Builder to implement tasks with full git workflow and auto-tagging.

### Skill: `implementation-plan`
Provides knowledge about:
- Parsing markdown checklists
- Reading verification commands
- Updating task completion status
- Continuous execution patterns

## Plugin Structure

```
ralph-agent/
├── .claude-plugin/
│   └── plugin.json          # Plugin manifest
├── agents/
│   ├── ralph.md             # Ralph executor agent
│   ├── geoff-planner.md     # Geoff's Planner agent
│   └── geoff-builder.md     # Geoff's Builder agent
├── commands/
│   ├── ralph.md             # /ralph-agent:ralph command
│   ├── ralph-init.md        # /ralph-agent:ralph-init command
│   ├── gplan.md             # /ralph-agent:gplan command
│   ├── gbuild.md            # /ralph-agent:gbuild command
│   └── loop.md              # /ralph-agent:loop wrapper command
├── harness/
│   ├── harness.json         # Middleware configuration
│   └── templates/
│       └── state.json.template  # Initial state template
├── hooks/
│   ├── hooks.json           # Hook event registrations
│   ├── session-start.sh     # Context injection (SessionStart)
│   ├── pre-tool-use.sh      # File protection + tracking (PreToolUse)
│   ├── post-tool-use.sh     # Loop detection + tracing (PostToolUse)
│   ├── stop-checklist.sh    # Completion gate (Stop)
│   ├── pre-compact.sh       # State preservation (PreCompact)
│   └── lib/
│       ├── config.sh        # Shared config loader
│       ├── state.sh         # State management functions
│       └── analyze-trace.sh # Post-session trace analysis
├── skills/
│   └── implementation-plan/
│       ├── SKILL.md         # Main skill file
│       ├── references/      # Detailed references
│       │   ├── task-examples.md
│       │   └── verification-patterns.md
│       ├── examples/        # Working examples
│       │   ├── IMPLEMENTATION_PLAN.md.template
│       │   └── AGENTS.md.example
│       └── scripts/         # Utility scripts
│           └── parse-tasks.sh
├── loop.py                  # External loop controller script
├── README.md
└── .gitignore
```

## Deterministic Scaffolding Harness

Beyond the agent workflows, this plugin includes a **hook-based harness** that enforces reliability constraints on any agent running inside it. The harness uses [Claude Code hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) as middleware — intercepting tool calls, injecting context, and gating completion — so the agent stays on track without relying on prompt discipline alone.

### Why a Harness?

Agents fail in predictable ways: they lose context after compaction, get stuck editing the same file in a loop, skip verification, or write to sensitive files. The harness addresses each of these with a dedicated hook:

| Failure Mode | Hook | Enforcement |
|---|---|---|
| Agent explores instead of working | `SessionStart` | Injects pre-built environment map so the agent starts with context |
| Doom loop (same file edited repeatedly) | `PostToolUse` | Tracks per-file edit counts; triggers strategy reconsideration at threshold |
| Writes to secrets/credentials | `PreToolUse` | Blocks writes to `.env`, `*.pem`, `*.key`, `credentials.*` |
| Stops without verifying | `Stop` | Blocks the agent from stopping until verification commands pass |
| Loses state after context compaction | `PreCompact` | Re-injects phase, task progress, and verification commands |

### Hook Events

#### SessionStart — Context Injection

**Script:** `hooks/session-start.sh`

When a session starts, this hook injects a pre-built context snapshot so the agent doesn't waste time exploring:

- **Project structure**: Depth-limited directory tree (excludes `node_modules`, `.git`, etc.)
- **Verification commands**: Extracted from `AGENTS.md`
- **Task status**: Total/completed/remaining counts and next task from `IMPLEMENTATION_PLAN.md`
- **Resume state**: If resuming a previous session, injects the previous phase and task
- **Time budget**: Optional time constraint (if configured in `harness.json`)
- **Harness rules**: Summary of active enforcement rules

The design principle is **"Context Injection > Context Discovery"** — instead of letting the agent discover its environment through tool calls, inject a complete map upfront.

#### PreToolUse — File Protection & Verification Tracking

**Script:** `hooks/pre-tool-use.sh`
**Triggers on:** `Write`, `Edit`, `Bash`

Two responsibilities:

1. **File protection**: Blocks writes to sensitive files matching protected patterns. If the agent attempts to write to `.env`, `*.pem`, `*.key`, or `credentials.*`, the hook returns a `deny` decision with a reason.

2. **Verification tracking**: When a Bash command matches known test patterns (`pytest`, `npm test`, `jest`, `vitest`, etc.) or lint patterns (`ruff`, `eslint`, `flake8`, etc.), the hook records that verification was *attempted* in the harness state.

#### PostToolUse — Loop Detection & Trace Logging

**Script:** `hooks/post-tool-use.sh`
**Triggers on:** `Edit`, `Write`, `Bash`

Three responsibilities:

1. **Trace logging**: Every tool call is appended to `trace-log.jsonl` with timestamp, tool name, and input. This enables post-session analysis.

2. **Loop detection**: For `Edit` and `Write` tools, increments a per-file edit counter. When the count reaches the threshold (default: 5), injects a warning prompt:
   > *"You have edited 'file.py' 5 times. STOP and reconsider your approach..."*

   The warning suggests: re-read the error, try a different strategy, check a different file, or look at dependencies.

3. **Verification result tracking**: When a Bash command succeeds and matches test/lint patterns, records that verification *passed* in the harness state.

#### Stop — Pre-Completion Checklist

**Script:** `hooks/stop-checklist.sh`

Intercepts the agent's attempt to stop and checks two conditions:

1. **Verification ran and passed**: Were test commands executed? Did they succeed?
2. **No remaining tasks**: Are there unchecked tasks (`- [ ]`) in `IMPLEMENTATION_PLAN.md`?

If either condition fails, the hook **blocks the stop** (exit code 2) and returns a checklist of blockers. The agent must address all blockers before it can stop.

A `stop_hook_active` guard prevents infinite loops — if the stop hook already fired once and the agent is retrying, it lets the stop through.

#### PreCompact — Context Preservation

**Script:** `hooks/pre-compact.sh`

When Claude Code compacts the conversation to stay within context limits, critical state can be lost. This hook re-injects:

- Current phase and task
- Progress counts (completed/remaining)
- Iteration number and TDD phase
- Verification commands from `AGENTS.md`
- An instruction to continue from the current position (not restart)

### Configuration: `harness.json`

All middleware modules are configured in `harness/harness.json`:

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
        ".env", ".env.*", "*.pem", "*.key", "credentials.*"
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

Each middleware module can be independently enabled or disabled. Key settings:

| Setting | Default | Description |
|---|---|---|
| `loop_detection.edit_threshold` | `5` | Number of edits to the same file before triggering a warning |
| `context_injection.max_tree_depth` | `3` | Directory tree depth for the session-start context |
| `context_injection.time_budget_seconds` | `0` | Time constraint injected into context (0 = no limit) |
| `file_protection.protected_patterns` | See above | File patterns that cannot be written to |
| `trace_logging.max_log_size_mb` | `10` | Maximum trace log file size |

### Runtime State: `.harness/`

The harness creates a `.harness/` directory in your project root to track state across tool calls:

```
.harness/
├── state.json          # Session phase, verification status, task progress
├── edit-tracker.json   # Per-file edit counts for loop detection
└── trace-log.jsonl     # Chronological log of all tool calls
```

**`state.json`** tracks the agent's current position:
```json
{
  "session_id": "abc-123",
  "started_at": "2026-02-19T10:00:00Z",
  "phase": "executing",
  "current_task": "Implement API endpoints",
  "tasks_completed": 2,
  "tasks_remaining": 5,
  "iteration": 3,
  "verification_status": {
    "tests_run": true,
    "tests_passed": true,
    "lint_run": true,
    "lint_passed": true,
    "last_verified_at": "2026-02-19T10:45:00Z"
  },
  "tdd_phase": null,
  "context_injected": true,
  "last_compacted_at": null
}
```

**`edit-tracker.json`** maps file paths to edit counts:
```json
{
  "src/api.py": 3,
  "src/models.py": 1
}
```

**`trace-log.jsonl`** records every tool call as a JSON line:
```json
{"timestamp":"2026-02-19T10:30:00Z","tool":"Edit","input":{"file_path":"src/api.py"},"result":"success"}
{"timestamp":"2026-02-19T10:30:05Z","tool":"Bash","input":{"command":"pytest tests/"},"result":"success"}
```

### Trace Analysis

After a session completes, you can analyze the trace log in `.harness/trace-log.jsonl` to identify patterns and potential improvements. The plugin includes a trace analysis script:

```bash
# Find and run the analysis script from the plugin directory
bash "$(find ~/.claude/plugins -name analyze-trace.sh 2>/dev/null | head -1)" .harness/trace-log.jsonl

# Or use jq directly for a quick summary:
jq -r '.tool' .harness/trace-log.jsonl | sort | uniq -c | sort -rn
```

This produces a report including:

- **Tool usage breakdown**: How many calls to each tool (Edit, Bash, Read, etc.)
- **Hot files**: Files edited most frequently, with loop warnings for files at or above threshold
- **Loop analysis**: Whether any doom loops were detected
- **Verification runs**: Which verification commands were executed and how many times

Example output:
```
═══════════════════════════════════════════
  TRACE ANALYSIS REPORT
═══════════════════════════════════════════

Total tool calls: 47

── Tool Usage ──────────────────────────────
  Edit: 18 calls (38%)
  Bash: 12 calls (25%)
  Read: 10 calls (21%)
  Write: 4 calls (8%)
  Glob: 3 calls (6%)

── Hot Files (Edit/Write frequency) ────────
  src/api.py: 6 edits ⚠ POTENTIAL LOOP
  src/models.py: 3 edits

── Loop Analysis ───────────────────────────
  WARNING: Potential doom loops detected on:
    - src/api.py

── Verification Runs ───────────────────────
  pytest tests/: 4 runs
  ruff check .: 2 runs

═══════════════════════════════════════════
```

Use this data to tune `harness.json` (e.g., adjust `edit_threshold`) or to identify where agents struggle in your codebase.

## Best Practices

### Writing Tasks
- Be specific: "Add JWT authentication" instead of "Work on auth"
- Keep tasks independent: Each task should be completable separately
- Make tasks verifiable: Include acceptance criteria
- Reasonable scope: Tasks should take 30 minutes to 2 hours

### Verification Commands
- Order by speed: Fast checks first (linting) then slow (tests)
- Be specific: Use paths to test only affected code when possible
- Include all checks: Linting, type checking, and tests
- Use AGENTS.md: Keep verification commands out of the plan file

### Using Ralph
- Let it run: Ralph works best when allowed to complete multiple tasks
- Check progress: Ralph reports after each task
- Stop gracefully: Use "stop" to halt between tasks
- Verify before commit: All verification commands pass automatically

## Troubleshooting

### "No IMPLEMENTATION_PLAN.md found"
Run `/ralph-agent:ralph-init` to create a template plan file.

### "No verification commands found"
Create `AGENTS.md` with verification commands.

### Verification keeps failing
Ralph will automatically fix and retry. If it fails repeatedly, Ralph will ask for guidance.

### Ralph stopped unexpectedly
Ralph saves progress after each task. Just run `/ralph-agent:ralph` again to continue.

## Publishing & Distribution

This plugin is distributed via the Claude Code marketplace system from the [roach-loop repository](https://github.com/tmdgusya/roach-loop).

### For Users - Quick Start

**Install the plugin in 2 commands:**

```bash
# 1. Add the marketplace
/plugin marketplace add tmdgusya/roach-loop

# 2. Install the plugin
/plugin install ralph-agent@ralph-agent-marketplace
```

**Update to latest version:**

```bash
/plugin update ralph-agent
```

**Verify installation:**

```bash
/plugin list
```

You should see `ralph-agent` in the installed plugins list.

### For Plugin Developers

To publish updates to this plugin:

1. **Update version** in both files:
   - `ralph-agent/.claude-plugin/plugin.json` (line 3)
   - `.claude-plugin/marketplace.json` at repository root (line 11)

2. **Commit and push changes**:
   ```bash
   git add .
   git commit -m "Release v0.4.0: Add new features"
   git push origin main
   ```

3. **Create a release tag** (recommended):
   ```bash
   git tag v0.4.0
   git push origin v0.4.0
   ```

4. **Users update automatically**:
   Users who have added your marketplace can update with:
   ```bash
   /plugin update ralph-agent
   ```

### Repository Structure

```
roach-loop/                              # GitHub repository root
├── .claude-plugin/
│   └── marketplace.json                 # Marketplace catalog (source: ./ralph-agent:ralph-agent)
├── ralph-agent/                         # Plugin directory
│   ├── .claude-plugin/
│   │   ├── plugin.json                  # Plugin manifest
│   │   └── marketplace.json             # (backup/reference)
│   ├── agents/                          # ralph, geoff-planner, geoff-builder
│   ├── commands/                        # /ralph-agent:ralph, /ralph-agent:gplan, /ralph-agent:gbuild, etc.
│   ├── skills/                          # implementation-plan skill
│   ├── loop.py                          # External loop controller
│   └── README.md                        # This file
└── ...
```

### Marketplace System

Claude Code uses a **decentralized marketplace model**:

| Traditional App Store | Claude Code Marketplace |
|----------------------|------------------------|
| ❌ Submit to centralized authority | ✅ Host on your own GitHub |
| ❌ Wait for approval | ✅ Instant distribution |
| ❌ Follow store policies | ✅ Full control over updates |
| ❌ Revenue sharing | ✅ Free and open |

**How it works:**
1. **Plugin author** creates `marketplace.json` in their GitHub repo
2. **Users** add the marketplace: `/plugin marketplace add tmdgusya/roach-loop`
3. **Claude Code** fetches plugin from GitHub when user installs
4. **Updates** are pulled from GitHub when user runs `/plugin update`

**Advantages:**
- ✅ No gatekeepers - publish instantly
- ✅ Version control via Git
- ✅ Users choose which marketplaces to trust
- ✅ Open source and transparent
- ✅ No lock-in to Anthropic's marketplace

### Distribution URLs

**Primary distribution (Recommended):**
```bash
/plugin marketplace add tmdgusya/roach-loop
/plugin install ralph-agent@ralph-agent-marketplace
```

**Alternative - Direct Git URL:**
```bash
/plugin install https://github.com/tmdgusya/roach-loop.git --subdirectory ralph-agent
```

**Alternative - Clone and install locally:**
```bash
git clone https://github.com/tmdgusya/roach-loop.git
/plugin install ./roach-loop/ralph-agent:ralph-agent
```

## License

MIT

## Contributing

Contributions welcome! Please feel free to submit issues or pull requests.
