# ralph-agent

A persistent TDD implementation agent that reads IMPLEMENTATION_PLAN.md and completes tasks using Red-Green-Refactor.

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

### Running Tests

```bash
# Unit tests
bash hooks/lib/test-libs.sh
bash hooks/test-session-start.sh
bash hooks/test-post-tool-use.sh
bash hooks/test-stop-checklist.sh
bash hooks/test-pre-compact.sh
bash hooks/test-pre-tool-use.sh
bash hooks/test-verification-tracking.sh
bash hooks/test-hooks-json.sh
bash test-thin-prompt.sh

# Integration test
bash hooks/test-integration.sh
```
