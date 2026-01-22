---
name: ralph
description: Start Ralph agent to work through IMPLEMENTATION_PLAN.md tasks continuously
argument-hint: [--max-iterations=N]
allowed-tools: ["Task"]
---

# /ralph Command

This command invokes the Ralph agent to work through tasks in IMPLEMENTATION_PLAN.md.

## What This Does

Ralph will:
1. Read IMPLEMENTATION_PLAN.md to find the first unchecked task
2. Implement the task by writing/modifying code
3. Verify the work using commands from AGENTS.md
4. Mark the task as complete when verification passes
5. Continue automatically to the next task until all are done (or `--max-iterations` reached)

## Usage

Simply invoke this command:
```
/ralph
```

With iteration limit:
```
/ralph --max-iterations=3
```

Ralph will report progress as it works through each task.

## Arguments

| Argument | Description | Default |
|----------|-------------|---------|
| `--max-iterations=N` | Maximum number of tasks to process (0 = unlimited) | 0 (unlimited) |

**Max Iterations Guide:**
- `0` or no flag: Process all tasks until complete
- `--max-iterations=5`: Process exactly 5 tasks, then stop for review
- Useful for: controlled batches, testing, review checkpoints

## Requirements

- **IMPLEMENTATION_PLAN.md** must exist in the current directory
- Use `/ralph-init` if you need to create a template plan file
- **AGENTS.md** should contain verification commands (optional but recommended)

## Stopping Ralph

To stop Ralph while it's working:
- Say "stop", "cancel", or "abort"
- Ralph will complete the current task and save progress

## Task Format

IMPLEMENTATION_PLAN.md should use markdown checklist format:
```markdown
## Tasks
- [ ] Task one: Do something
- [ ] Task two: Do another thing
- [x] Task three: Already completed
```

## Verification

Ralph looks for verification commands in AGENTS.md:
```markdown
# Verification Commands
- `pytest tests/`
- `npm run lint`
```

All verification commands must pass before a task is marked complete.
