---
name: gplan
description: Trigger Geoff's Planner agent to study specs and code, creating/updating IMPLEMENTATION_PLAN.md with prioritized tasks
argument-hint: [--parallel=N] [--max-passes=N]
allowed-tools: ["Task"]
---

# /gplan Command

This command invokes Geoff's Planner agent to analyze your specs/ directory and codebase, creating or updating IMPLEMENTATION_PLAN.md with prioritized tasks.

`★ Insight ─────────────────────────────────────`
**Geoff's Planner vs Traditional Planning:**
- Traditional: Manual planning, missed dependencies, stale specs
- Geoff's Planner: Parallel subagent analysis of ALL specs, gap detection against actual code, prioritization via Ultrathink
- Result: Accurate, up-to-date implementation plans automatically
`─────────────────────────────────────────────────`

## What This Does

Geoff's Planner will:
1. Study all files in `specs/` directory using parallel subagents
2. Study existing `IMPLEMENTATION_PLAN.md` (if exists) and `src/lib/*`
3. Compare `src/*` implementation against `specs/*` requirements using parallel subagents
4. Use Opus with "Ultrathink" for deep analysis and task prioritization
5. Create/update `IMPLEMENTATION_PLAN.md` with prioritized, actionable tasks

## Usage

```
/gplan
```

With custom parallelism:

```
/gplan --parallel=50
```

## Arguments

| Argument | Description | Default |
|----------|-------------|---------|
| `--parallel=N` | Number of parallel subagents for analysis | 10 |
| `--max-passes=N` | Maximum planning passes (typically 1) | 1 |

**Parallelism Guide:**
- `10-20`: Small projects (<50 spec files)
- `50-100`: Medium projects (50-200 spec files)
- `100-250`: Large projects (200+ spec files)

**Note:** Planning is typically a one-shot operation. For iterative execution control, use `/gbuild --max-iterations=N`.

## Requirements

- **`specs/` directory** must exist with specification files
  - If missing: Error message will guide you to create it
- Git repository (optional but recommended)

## What Gets Created

**`IMPLEMENTATION_PLAN.md`** with:
- Project description from specs
- Geoff Analysis section (specs analyzed, gaps found)
- Prerequisites checklist
- Tasks ordered by priority ([P1], [P2], [P3])
- Verification commands from AGENTS.md
- Notes section for context and assumptions

## Example Output

```
╔══════════════════════════════════════════╗
║     GEOFF'S PLANNER - COMPLETE ✓        ║
╚══════════════════════════════════════════╝

Analysis Summary:
- Specs analyzed: 15 files
- Parallel subagents: 10
- Gap analysis: 45 comparisons
- Tasks created: 23 tasks

Highest Priority Tasks:
1. [P1] Implement user authentication
2. [P1] Create database schema
3. [P2] Build REST API endpoints

IMPLEMENTATION_PLAN.md updated.
Ready for Geoff's Builder: /gbuild
```

## Next Steps

After `/gplan` completes:

1. **Review the plan:** Check `IMPLEMENTATION_PLAN.md`
2. **Start building:** Run `/gbuild` to implement tasks
3. **Iterate:** Re-run `/gplan` after spec changes to update the plan

## Stopping Geoff's Planner

To stop while running:
- Say "stop", "cancel", or "abort"
- Geoff's Planner will save partial findings to IMPLEMENTATION_PLAN.md

## Key Differences from Other Commands

| Command | Purpose |
|---------|---------|
| `/gplan` | Create/update IMPLEMENTATION_PLAN.md from specs |
| `/gbuild` | Implement tasks from IMPLEMENTATION_PLAN.md |
| `/ralph` | Execute existing IMPLEMENTATION_PLAN.md tasks (no git workflow) |
| `/plan` | Generic planning command (varies by project) |

## Best Practices

1. **Keep specs/ clean:** One file per feature/requirement
2. **Re-run after changes:** Update plan when specs change
3. **Review before building:** Check the plan to ensure priorities are correct
4. **Use higher parallelism for large projects:** Speeds up analysis significantly

## Error Conditions

| Error | Solution |
|-------|----------|
| `specs/ directory not found` | Create `specs/` directory with your specification files |
| `specs/ is empty` | Add specification files to `specs/` directory |
| `No specs/ and no IMPLEMENTATION_PLAN.md` | Create specs/ first, then run `/gplan` |

## Related Commands

- `/gbuild` - Implement the plan with git workflow
- `/ralph-init` - Create empty IMPLEMENTATION_PLAN.md template
- `/ralph` - Execute plan without git workflow
