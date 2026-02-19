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
VERIFY_OUTPUT=$(jq -r 'select(.tool == "Bash") | .input.command // "unknown"' "$TRACE_FILE" \
  | grep -E '(pytest|npm test|go test|jest|vitest|ruff|eslint)' \
  | sort | uniq -c | sort -rn 2>/dev/null || true)

if [ -n "$VERIFY_OUTPUT" ]; then
  echo "$VERIFY_OUTPUT" | while read count cmd; do
    echo "  $cmd: $count runs"
  done
else
  echo "  No verification commands detected."
fi
echo ""

echo "═══════════════════════════════════════════"
