#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Source just state.sh (config.sh provides HARNESS_STATE_DIR etc.)
source "$SCRIPT_DIR/lib/config.sh"
export HARNESS_STATE_DIR="$TMPDIR/.harness"

PASS=0
FAIL=0

assert_contains_cmd() {
  local desc="$1" cmd="$2" result="$3"
  if echo "$result" | jq -e --arg c "$cmd" '. | index($c) != null' > /dev/null 2>&1; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected '$cmd' in: $result)"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains_cmd() {
  local desc="$1" cmd="$2" result="$3"
  if echo "$result" | jq -e --arg c "$cmd" '. | index($c) == null' > /dev/null 2>&1; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (did NOT expect '$cmd' in: $result)"
    FAIL=$((FAIL + 1))
  fi
}

assert_empty() {
  local desc="$1" result="$2"
  if [ "$result" = "[]" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected '[]', got: $result)"
    FAIL=$((FAIL + 1))
  fi
}

# Source state.sh to get discover_verification_commands
source "$SCRIPT_DIR/lib/state.sh"

echo "=== Testing discover_verification_commands() ==="

# Test 1: Discovers from IMPLEMENTATION_PLAN.md ## Verification section
PROJ="$TMPDIR/proj1"
mkdir -p "$PROJ"
cat > "$PROJ/IMPLEMENTATION_PLAN.md" << 'EOF'
# Plan

## Tasks
- [ ] Task 1

## Verification
- `pytest tests/` - run tests
- `ruff check .` - lint

## Notes
nothing here
EOF

RESULT=$(discover_verification_commands "$PROJ")
assert_contains_cmd "plan-verification: discovers pytest" "pytest tests/" "$RESULT"
assert_contains_cmd "plan-verification: discovers ruff" "ruff check ." "$RESULT"

# Test 2: Discovers from AGENTS.md
PROJ2="$TMPDIR/proj2"
mkdir -p "$PROJ2"
cat > "$PROJ2/AGENTS.md" << 'EOF'
# Agents

## Verification Commands
- `npm test` - run tests
- `npm run lint` - check style
EOF

RESULT2=$(discover_verification_commands "$PROJ2")
assert_contains_cmd "agents-md: discovers npm test" "npm test" "$RESULT2"
assert_contains_cmd "agents-md: discovers npm run lint" "npm run lint" "$RESULT2"

# Test 3: Deduplicates across sources
PROJ3="$TMPDIR/proj3"
mkdir -p "$PROJ3"
cat > "$PROJ3/IMPLEMENTATION_PLAN.md" << 'EOF'
## Verification
- `pytest tests/` - from plan
EOF
cat > "$PROJ3/AGENTS.md" << 'EOF'
- `pytest tests/` - from agents
EOF

RESULT3=$(discover_verification_commands "$PROJ3")
COUNT=$(echo "$RESULT3" | jq 'length')
if [ "$COUNT" -eq 1 ]; then
  echo "  PASS: deduplication: only one pytest entry"
  PASS=$((PASS + 1))
else
  echo "  FAIL: deduplication: expected 1 entry, got $COUNT: $RESULT3"
  FAIL=$((FAIL + 1))
fi

# Test 4: Discovers from package.json with real test script
PROJ4="$TMPDIR/proj4"
mkdir -p "$PROJ4"
cat > "$PROJ4/package.json" << 'EOF'
{
  "scripts": {
    "test": "jest",
    "lint": "eslint src/"
  }
}
EOF

RESULT4=$(discover_verification_commands "$PROJ4")
assert_contains_cmd "package-json: discovers npm test" "npm test" "$RESULT4"
assert_contains_cmd "package-json: discovers npm run lint" "npm run lint" "$RESULT4"

# Test 5: Ignores npm-init default ("no test specified")
PROJ5="$TMPDIR/proj5"
mkdir -p "$PROJ5"
cat > "$PROJ5/package.json" << 'EOF'
{
  "scripts": {
    "test": "echo \"Error: no test specified\" && exit 1"
  }
}
EOF

RESULT5=$(discover_verification_commands "$PROJ5")
assert_not_contains_cmd "package-json-default: ignores npm-init default" "npm test" "$RESULT5"

# Test 6: Discovers from pyproject.toml [tool.pytest]
PROJ6="$TMPDIR/proj6"
mkdir -p "$PROJ6"
cat > "$PROJ6/pyproject.toml" << 'EOF'
[tool.pytest.ini_options]
testpaths = ["tests"]
EOF

RESULT6=$(discover_verification_commands "$PROJ6")
assert_contains_cmd "pyproject-pytest: discovers pytest tests/" "pytest tests/" "$RESULT6"

# Test 7: Discovers from Makefile test: target
PROJ7="$TMPDIR/proj7"
mkdir -p "$PROJ7"
cat > "$PROJ7/Makefile" << 'EOF'
test:
	go test ./...

build:
	go build ./...
EOF

RESULT7=$(discover_verification_commands "$PROJ7")
assert_contains_cmd "makefile: discovers make test" "make test" "$RESULT7"

# Test 8: Discovers from *_test.go files
PROJ8="$TMPDIR/proj8"
mkdir -p "$PROJ8/pkg"
touch "$PROJ8/pkg/main_test.go"

RESULT8=$(discover_verification_commands "$PROJ8")
assert_contains_cmd "go-test: discovers go test ./..." "go test ./..." "$RESULT8"

# Test 9: Discovers from Cargo.toml
PROJ9="$TMPDIR/proj9"
mkdir -p "$PROJ9"
cat > "$PROJ9/Cargo.toml" << 'EOF'
[package]
name = "myapp"
version = "0.1.0"
EOF

RESULT9=$(discover_verification_commands "$PROJ9")
assert_contains_cmd "cargo: discovers cargo test" "cargo test" "$RESULT9"

# Test 10: Empty project → empty array
PROJ10="$TMPDIR/proj10"
mkdir -p "$PROJ10"

RESULT10=$(discover_verification_commands "$PROJ10")
assert_empty "empty-project: returns []" "$RESULT10"

# Test 11: Verification section stops at next header
PROJ11="$TMPDIR/proj11"
mkdir -p "$PROJ11"
cat > "$PROJ11/IMPLEMENTATION_PLAN.md" << 'EOF'
## Verification
- `pytest tests/` - tests

## Notes
- `this should NOT be included` - not a verification cmd
EOF

RESULT11=$(discover_verification_commands "$PROJ11")
assert_contains_cmd "section-boundary: includes pytest" "pytest tests/" "$RESULT11"
assert_not_contains_cmd "section-boundary: excludes Notes section cmd" "this should NOT be included" "$RESULT11"

# Test 12: ruff.toml triggers ruff check .
PROJ12="$TMPDIR/proj12"
mkdir -p "$PROJ12"
touch "$PROJ12/ruff.toml"

RESULT12=$(discover_verification_commands "$PROJ12")
assert_contains_cmd "ruff-toml: discovers ruff check ." "ruff check ." "$RESULT12"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
