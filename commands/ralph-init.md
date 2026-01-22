---
name: ralph-init
description: Create a new IMPLEMENTATION_PLAN.md template file with standard sections
argument-hint: [no arguments]
allowed-tools: ["Write"]
---

# /ralph-init Command

This command creates a template IMPLEMENTATION_PLAN.md file in the current directory.

## What This Does

Creates a standard implementation plan template with:
- Project description section
- Prerequisites section
- Task checklist (markdown format)
- Verification section
- Notes section

## Usage

```
/ralph-init
```

This creates IMPLEMENTATION_PLAN.md in the current working directory.

## Template Structure

The generated template includes:

```markdown
# Implementation Plan

## Description
[Brief description of what this plan implements]

## Prerequisites
- [ ] Dependency 1
- [ ] Dependency 2

## Tasks
- [ ] Task 1: [Description]
- [ ] Task 2: [Description]
- [ ] Task 3: [Description]

## Verification
Commands to verify implementation (also add these to AGENTS.md):
- `pytest tests/`
- `npm run test`

## Notes
[Additional notes, context, or reminders]
```

## After Creation

1. Edit the plan to add your specific tasks
2. Ensure AGENTS.md has verification commands
3. Run `/ralph` to start implementation

## Overwriting

If IMPLEMENTATION_PLAN.md already exists, this command will:
- Ask if you want to overwrite it
- Preserve existing content if you decline

## Best Practices

- Break large tasks into smaller, verifiable chunks
- Each task should be completable in one session
- Include enough context in task descriptions
- Keep verification commands up to date in AGENTS.md
