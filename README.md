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

## Example Workflow

```bash
# Create initial plan
/ralph-agent:ralph-init

# Edit the plan with your tasks
# Edit AGENTS.md with verification commands

# Start Ralph
/ralph-agent:ralph

# Ralph output:
✓ Task completed: Task 1: Create database models
  - Files modified: models.py
  - Verification: PASSED
  - Next task: Task 2: Implement API endpoints

✓ Task completed: Task 2: Implement API endpoints
  - Files modified: api.py
  - Verification: PASSED
  - Next task: Task 3: Write unit tests

╔══════════════════════════════════════════╗
║   ALL TASKS COMPLETED SUCCESSFULLY ✓    ║
╚══════════════════════════════════════════╝

Summary:
- Total tasks: 3
- Completed: 3
- Verification: All passed
```

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
