---
name: ralph-agent:gbuild
description: Trigger Geoff's Builder agent to implement tasks from IMPLEMENTATION_PLAN.md with verification, git workflow, and auto-tagging
argument-hint: [--parallel=N] [--max-iterations=N]
allowed-tools: ["Task"]
---

# /ralph-agent:gbuild Command

This command invokes Geoff's Builder agent to implement tasks from IMPLEMENTATION_PLAN.md with continuous verification, git commits, and automatic version tagging.

`★ Insight ─────────────────────────────────────`
**Geoff's Builder vs Traditional Implementation:**
- Traditional: Write code, maybe test, forget to commit, no version tags
- Geoff's Builder: Parallel codebase search → Implement → Test → Fix → Commit → Push → Tag (repeat)
- Result: Clean git history, auto-incrementing versions (0.0.0→0.0.1), tested code
`─────────────────────────────────────────────────`

## What This Does

Geoff's Builder will:
1. Study `specs/*` with configurable parallel subagents
2. Study `IMPLEMENTATION_PLAN.md` for task list
3. Choose highest priority unchecked task
4. Search codebase (don't assume not implemented) with parallel subagents
5. Implement the task completely (no placeholders/stubs)
6. Run tests for the implemented unit
7. Update plan, git add, commit, push when tests pass
8. Create git tags (0.0.0, 0.0.1, etc.) when no build/test errors
9. Continue until all tasks are complete

## Usage

```
/ralph-agent:gbuild
```

With custom parallelism:

```
/ralph-agent:gbuild --parallel=100
```

With iteration limit:

```
/ralph-agent:gbuild --max-iterations=5
```

## Arguments

| Argument | Description | Default |
|----------|-------------|---------|
| `--parallel=N` | Number of parallel subagents for codebase search/analysis | 10 |
| `--max-iterations=N` | Maximum number of tasks to process (0 = unlimited) | 0 (unlimited) |

**Parallelism Guide:**
- `10-20`: Small projects (<100 files)
- `50-100`: Medium projects (100-500 files)
- `100-500`: Large projects (500+ files)

**Max Iterations Guide:**
- `0` or no flag: Process all tasks until complete
- `--max-iterations=5`: Process exactly 5 tasks, then stop for review
- Useful for: controlled batches, testing, review checkpoints

**Note:** Parallelism is for analysis/search only. Implementation is single-threaded to ensure consistency.

## Requirements

- **`IMPLEMENTATION_PLAN.md`** must exist with unchecked tasks
  - Run `/ralph-agent:gplan` first if missing
- **`AGENTS.md`** should contain verification commands
- **Git repository** with remote configured

## Git Workflow

Geoff's Builder automatically handles:

1. **Git Add:** Stages relevant files for each task
2. **Git Commit:** Creates descriptive commits
   - Format: `[Geoff] Task name - Brief description`
3. **Git Push:** Pushes commits to remote
4. **Git Tag:** Auto-increments patch version
   - First task: `0.0.0`
   - Subsequent: `0.0.1`, `0.0.2`, `0.0.3`, etc.
   - Only tags when ALL tests pass

## Example Output

During execution:

```
✓ Task completed: Implement user authentication
  - Files modified: src/auth.ts, src/auth.test.ts
  - Tests: PASSED (12/12)
  - Git: Committed as a1b2c3d, Tagged as 0.0.1
  - Next task: Create database schema
```

When complete:

```
╔══════════════════════════════════════════╗
║     ALL TASKS COMPLETED SUCCESSFULLY ✓   ║
╚══════════════════════════════════════════╝

Summary:
- Total tasks: 23
- Completed: 23
- Git commits: 23
- Final tag: 0.0.23
- All tests: PASSED
```

## Verification

Geoff's Builder runs verification commands from AGENTS.md:

```markdown
# Verification Commands

## General
- `pytest tests/` - Run all tests
- `npm run test` - Run test suite
- `npm run build` - Verify build
```

**ALL commands must pass** before git commit and tag are created.

## Stopping Geoff's Builder

To stop while running:
- Say "stop", "cancel", or "abort"
- Geoff's Builder will complete current task verification
- Commit current work if tests pass
- Report remaining tasks

## Key Differences from Other Commands

| Command | Purpose |
|---------|---------|
| `/ralph-agent:gplan` | Create/update IMPLEMENTATION_PLAN.md from specs |
| `/ralph-agent:gbuild` | Implement tasks with git workflow + auto-tags |
| `/ralph-agent:ralph` | Execute tasks without git workflow or tagging |

## Best Practices

1. **Run `/ralph-agent:gplan` first:** Ensure plan is up-to-date before building
2. **Review first task:** Check what will be implemented
3. **Keep tests passing:** Geoff's Builder will fix unrelated test failures too
4. **Monitor git tags:** Each successful task creates a new version tag
5. **Use appropriate parallelism:** Higher values for faster codebase search

## Error Conditions

| Error | Solution |
|-------|----------|
| `No IMPLEMENTATION_PLAN.md found` | Run `/ralph-agent:gplan` first to create the plan |
| `No unchecked tasks in plan` | All tasks are complete! |
| `No verification commands in AGENTS.md` | Add verification commands to AGENTS.md |
| `Tests failing` | Geoff's Builder will fix and re-run |
| `Git push failed` | Check remote configuration, resolve conflicts |

## Guardrails

Geoff's Builder follows these principles:

- **Complete implementation:** No placeholders, stubs, or TODO comments
- **Single source of truth:** No duplicate implementations or adapters
- **All tests must pass:** Related or unrelated failures are resolved
- **Capture the why:** Documentation explains reasoning
- **Clean git history:** One commit per task, descriptive messages
- **Auto-versioning:** Tags only when tests pass

## Related Commands

- `/ralph-agent:gplan` - Create/update the implementation plan
- `/ralph-agent:ralph` - Execute plan without git workflow
- `/ralph-agent:ralph-init` - Create empty IMPLEMENTATION_PLAN.md template

## Workflow Example

```bash
# 1. Create/update plan from specs
/ralph-agent:gplan --parallel=50

# 2. Review the plan
cat IMPLEMENTATION_PLAN.md

# 3. Implement with full git workflow
/ralph-agent:gbuild --parallel=100

# 4. Check the results
git log --oneline
git tag
```
