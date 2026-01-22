---
name: ralph-agent:loop
description: Execute any agent with explicit iteration control, pause prompts, and checkpoint summaries
argument-hint: <agent-name> [max=N] [pause=true|false] [parallel=M]
allowed-tools: ["Task"]
---

# /ralph-agent:loop Command

A powerful wrapper that executes any agent with explicit iteration control, pause prompts between tasks, and detailed checkpoint summaries.

`★ Insight ─────────────────────────────────────`
**/ralph-agent:loop vs Agent Arguments:**
- Agent `--max-iterations=N`: Simple limit, runs until done
- `/ralph-agent:loop`: Full control with pause prompts, summaries, and resumable sessions
- Best for: Careful review between tasks, testing workflows, learning agent behavior
`─────────────────────────────────────────────────`

## What This Does

The `/ralph-agent:loop` command:
1. Spawns the specified agent (ralph, geoff-builder, etc.)
2. Monitors agent progress through tasks
3. Pauses after each task (if `pause=true`)
4. Provides checkpoint summaries with continuation option
5. Stops at max iterations or when all tasks complete

## Usage

```
/ralph-agent:loop ralph max=5 pause=true
```

```
/ralph-agent:loop geoff-builder max=10 pause=true parallel=50
```

```
/ralph-agent:loop geoff-builder max=0 pause=false
```

## Arguments

| Argument | Description | Default |
|----------|-------------|---------|
| `agent-name` | Agent to run (ralph, geoff-builder, geoff-planner) | Required |
| `max=N` | Maximum iterations (0 = unlimited) | 0 (unlimited) |
| `pause=true|false` | Prompt user after each task | true |
| `parallel=M` | Parallel subagents (for geoff agents) | 10 |

**Agents Available:**
- `ralph` - Execute IMPLEMENTATION_PLAN.md tasks
- `geoff-builder` - Execute tasks with git workflow + tags
- `geoff-planner` - Create/update IMPLEMENTATION_PLAN.md (not typically looped)

## Behavior

### With Pause (pause=true)

After each task completion:

```
✓ Task completed: [Task name]
  - Files modified: [list]
  - Verification: PASSED

╔══════════════════════════════════════════╗
║            LOOP CHECKPOINT                ║
╚══════════════════════════════════════════╝

Iteration: 3 / 5
Tasks completed this session: 3
Tasks remaining: 7
Latest git tag: 0.0.3 (if geoff-builder)

Continue to next task?
- Type "yes" or "y" to continue
- Type "no" or "n" to stop and save
- Type "status" for detailed progress
```

### Without Pause (pause=false)

Runs continuously until:
- All tasks complete, OR
- Max iterations reached

Then provides summary:

```
╔══════════════════════════════════════════╗
║           LOOP SESSION COMPLETE          ║
╚══════════════════════════════════════════╝

Session Summary:
- Agent: geoff-builder
- Iterations: 5 / 5 (max reached)
- Tasks completed: 5
- Tasks remaining: 18
- Git commits: 5
- Latest tag: 0.0.5

To continue: Run /ralph-agent:loop geoff-builder again (will resume)
```

## Examples

### Test Ralph with 3 Tasks

```
/ralph-agent:loop ralph max=3 pause=true
```

Process 3 tasks, pause after each for review.

### Build with Geoff, Pause Between Each

```
/ralph-agent:loop geoff-builder max=0 pause=true parallel=50
```

Build ALL tasks, pause after each for review and git verification.

### Quick Batch Build

```
/ralph-agent:loop geoff-builder max=10 pause=false
```

Build 10 tasks continuously, then stop for checkpoint.

### Full Continuous Build

```
/ralph-agent:loop geoff-builder max=0 pause=false
```

Build all tasks without stopping (equivalent to `/ralph-agent:gbuild`).

## Comparison

| Command | Max Iterations | Pause | Git Workflow | Best For |
|---------|---------------|-------|--------------|----------|
| `/ralph-agent:ralph` | Yes (flag) | No | No | Simple execution |
| `/ralph-agent:gbuild` | Yes (flag) | No | Yes | Git workflow |
| `/ralph-agent:loop ralph` | Yes (arg) | Optional | No | Controlled execution |
| `/ralph-agent:loop geoff-builder` | Yes (arg) | Optional | Yes | Controlled git workflow |

## Resuming Sessions

When you stop a loop session (or hit max iterations):

```
To continue: Run /ralph-agent:loop geoff-builder again
```

The agent will:
- Read current IMPLEMENTATION_PLAN.md
- Resume from first unchecked task
- Continue until max iterations or completion

## Checkpoint Commands

When paused, you can type:
- `yes` / `y` - Continue to next task
- `no` / `n` - Stop and save current state
- `status` - Show detailed progress report
- `tasks` - List remaining tasks
- `git` - Show git status (for geoff-builder)

## Stopping /ralph-agent:loop

To stop at any time:
- Say "stop", "cancel", or "abort"
- The agent will complete current task
- Save state and provide checkpoint summary

## Error Handling

If agent fails or errors occur:
- /ralph-agent:loop captures the error
- Displays error context
- Asks if you want to continue or stop
- Preserves all completed work

## Workflow Examples

### Careful Review Workflow

```bash
# 1. Create plan
/ralph-agent:gplan

# 2. Build with review after each task
/ralph-agent:loop geoff-builder max=0 pause=true

# 3. After each task:
#    - Review git diff
#    - Check tests passed
#    - Verify tag created
#    - Type "yes" to continue
```

### Testing Workflow

```bash
# Test Ralph with 2 tasks first
/ralph-agent:loop ralph max=2 pause=true

# Review output, check if working correctly

# If good, continue with more
/ralph-agent:loop ralph max=5 pause=true
```

### Batch Workflow

```bash
# Process 10 tasks at a time, review after each batch
/ralph-agent:loop geoff-builder max=10 pause=false

# Review git log, tags, tests

# Continue for next batch
/ralph-agent:loop geoff-builder max=10 pause=false
```

## Advanced: Combining with Agent Flags

You can combine /ralph-agent:loop with agent-specific arguments:

```
/ralph-agent:loop geoff-builder max=5 pause=true parallel=100
```

This:
- Uses `/ralph-agent:loop` for iteration control and pausing
- Passes `parallel=100` to geoff-builder for analysis
- Stops after 5 tasks with prompts between each

## Notes

- `/ralph-agent:loop` is a wrapper, not a replacement for direct agent commands
- For simple "run until done" use the agent directly (`/ralph-agent:ralph`, `/ralph-agent:gbuild`)
- Use `/ralph-agent:loop` when you need checkpoints, pauses, or resumable sessions
- All state is preserved in IMPLEMENTATION_PLAN.md between sessions
