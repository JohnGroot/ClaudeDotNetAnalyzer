#!/bin/bash
# ClaudeDotNetAnalyzer - Claude Code Stop Hook
# Runs StyleCop and .NET analyzers on modified C# files
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

# Read JSON input from stdin
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty')

# Validate we have required input
if [[ -z "$CWD" ]]; then
	echo '{}' # No output needed if no cwd
	exit 0
fi

cd "$CWD"

# Check if this is a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
	echo '{}' # Not a git repo, skip analysis
	exit 0
fi

# Check if any .cs files were modified (staged, unstaged, or untracked)
# Note: git diff HEAD fails if there are no commits yet, so we handle that
CS_CHANGES=""
if git rev-parse HEAD >/dev/null 2>&1; then
	CS_CHANGES=$(git diff --name-only HEAD 2>/dev/null | grep '\.cs$' || true)
fi
CS_STAGED=$(git diff --name-only --cached 2>/dev/null | grep '\.cs$' || true)
CS_UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null | grep '\.cs$' || true)

if [[ -z "$CS_CHANGES" && -z "$CS_STAGED" && -z "$CS_UNTRACKED" ]]; then
	echo '{}' # No C# changes, skip analysis
	exit 0
fi

# Load project-specific configuration if it exists
CONFIG_FILE="$CWD/.claude-dotnet-analyzer.json"
SEVERITY_THRESHOLD="${DOTNET_ANALYZER_SEVERITY:-all}"
MAX_ISSUES="${DOTNET_ANALYZER_MAX_ISSUES:-50}"
IGNORE_RULES=""
PROJECT_FILE=""

if [[ -f "$CONFIG_FILE" ]]; then
	SEVERITY_THRESHOLD=$(jq -r '.severity_threshold // "all"' "$CONFIG_FILE")
	MAX_ISSUES=$(jq -r '.max_issues // 50' "$CONFIG_FILE")
	IGNORE_RULES=$(jq -r '.ignore_rules // [] | join(",")' "$CONFIG_FILE")
	PROJECT_FILE=$(jq -r '.project_file // empty' "$CONFIG_FILE")
fi

# Detect .NET project file if not specified
if [[ -z "$PROJECT_FILE" ]]; then
	PROJECT_FILE=$("$LIB_DIR/detect-project.sh" "$CWD")
fi

if [[ -z "$PROJECT_FILE" ]]; then
	echo '{}' # No .NET project found, skip analysis
	exit 0
fi

# Create temporary file for SARIF output
SARIF_FILE="${TMPDIR:-/tmp}/sarif-$$.json"
trap "rm -f '$SARIF_FILE'" EXIT

# Run dotnet build with SARIF output
# Note: ErrorLog uses semicolon separator, not comma
# Use --no-incremental to ensure SARIF is generated (incremental builds don't produce it)
BUILD_OUTPUT=$(dotnet build "$PROJECT_FILE" \
	"/p:ErrorLog=$SARIF_FILE;version=2.1" \
	-consoleloggerparameters:NoSummary \
	--no-incremental \
	-v:q 2>&1) || true

# Check if SARIF file was created
if [[ ! -f "$SARIF_FILE" || ! -s "$SARIF_FILE" ]]; then
	# Build may have failed before generating SARIF, check for errors in output
	if echo "$BUILD_OUTPUT" | grep -q "error CS"; then
		ERROR_MSG=$(echo "$BUILD_OUTPUT" | grep "error CS" | head -10)
		REASON="Build failed with compilation errors:\n\n$ERROR_MSG"
		echo "{\"decision\": \"block\", \"reason\": $(echo -e "$REASON" | jq -Rs .)}"
		exit 0
	fi
	echo '{}' # No SARIF output and no errors, allow
	exit 0
fi

# Parse SARIF for issues
ISSUES=$("$LIB_DIR/parse-sarif.sh" "$SARIF_FILE" "$SEVERITY_THRESHOLD" "$IGNORE_RULES" "$MAX_ISSUES")

# Count issues (grep -c returns non-zero if no matches, so we handle that)
if [[ -z "$ISSUES" ]]; then
	ISSUE_COUNT=0
else
	ISSUE_COUNT=$(echo "$ISSUES" | grep -c '^\[' || true)
	# Ensure ISSUE_COUNT is a valid number
	if ! [[ "$ISSUE_COUNT" =~ ^[0-9]+$ ]]; then
		ISSUE_COUNT=0
	fi
fi

if [[ "$ISSUE_COUNT" -gt 0 ]]; then
	# Format the reason message
	if [[ "$ISSUE_COUNT" -ge "$MAX_ISSUES" ]]; then
		HEADER="Found $ISSUE_COUNT+ code analysis issues (showing first $MAX_ISSUES):"
	else
		HEADER="Found $ISSUE_COUNT code analysis issue(s):"
	fi

	REASON=$(cat <<EOF
$HEADER

$ISSUES

Please fix these issues before continuing.
EOF
)
	echo "{\"decision\": \"block\", \"reason\": $(echo "$REASON" | jq -Rs .)}"
else
	echo '{}' # No issues found, allow
fi

exit 0
