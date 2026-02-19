#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

PASS=0
FAIL=0

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qiF "$needle"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (needle='$needle' not found)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Testing analyze-trace.sh ==="

# Create sample trace log
cat > "$TMPDIR/trace-log.jsonl" << 'EOF'
{"timestamp":"2026-02-19T10:00:00Z","tool":"Read","input":{"file_path":"/src/app.ts"},"result":"success"}
{"timestamp":"2026-02-19T10:00:05Z","tool":"Edit","input":{"file_path":"/src/app.ts"},"result":"success"}
{"timestamp":"2026-02-19T10:00:10Z","tool":"Bash","input":{"command":"pytest tests/"},"result":"success"}
{"timestamp":"2026-02-19T10:00:15Z","tool":"Edit","input":{"file_path":"/src/app.ts"},"result":"success"}
{"timestamp":"2026-02-19T10:00:20Z","tool":"Edit","input":{"file_path":"/src/app.ts"},"result":"success"}
{"timestamp":"2026-02-19T10:00:25Z","tool":"Edit","input":{"file_path":"/src/app.ts"},"result":"success"}
{"timestamp":"2026-02-19T10:00:30Z","tool":"Edit","input":{"file_path":"/src/app.ts"},"result":"success"}
{"timestamp":"2026-02-19T10:00:35Z","tool":"Edit","input":{"file_path":"/src/app.ts"},"result":"success"}
{"timestamp":"2026-02-19T10:00:40Z","tool":"Bash","input":{"command":"npm test"},"result":"success"}
{"timestamp":"2026-02-19T10:00:45Z","tool":"Write","input":{"file_path":"/src/utils.ts"},"result":"success"}
EOF

OUTPUT=$(bash "$SCRIPT_DIR/analyze-trace.sh" "$TMPDIR/trace-log.jsonl" 2>/dev/null)

assert_contains "shows total calls" "10" "$OUTPUT"
assert_contains "identifies hot file" "app.ts" "$OUTPUT"
assert_contains "detects loop pattern" "loop" "$OUTPUT"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
