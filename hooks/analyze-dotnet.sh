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

# Combine modified .cs files into a JSON array for context-efficient output
ALL_CS_FILES=$(printf '%s\n%s\n%s' "$CS_CHANGES" "$CS_STAGED" "$CS_UNTRACKED" \
	| sort -u | grep -v '^$' | jq -R . | jq -s . || echo '[]')

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
	# Only use config file values when env vars are not set (env vars take priority)
	if [[ -z "${DOTNET_ANALYZER_SEVERITY:-}" ]]; then
		SEVERITY_THRESHOLD=$(jq -r '.severity_threshold // "all"' "$CONFIG_FILE")
	fi
	if [[ -z "${DOTNET_ANALYZER_MAX_ISSUES:-}" ]]; then
		MAX_ISSUES=$(jq -r '.max_issues // 50' "$CONFIG_FILE")
	fi
	IGNORE_RULES=$(jq -r '.ignore_rules // [] | join(",")' "$CONFIG_FILE")
	PROJECT_FILE=$(jq -r '.project_file // empty' "$CONFIG_FILE")
fi

# Read analyzer toggles from config and build MSBuild property flags
ANALYZER_PROPS=""
if [[ -f "$CONFIG_FILE" ]]; then
	for key_prop in \
		"idisposable_analyzers:EnableIDisposableAnalyzers" \
		"async_fixer:EnableAsyncFixer" \
		"meziantou_analyzer:EnableMeziantouAnalyzer" \
		"roslynator_analyzers:EnableRoslynatorAnalyzers" \
		"sonar_analyzer:EnableSonarAnalyzer"; do
		json_key="${key_prop%%:*}"
		msbuild_prop="${key_prop##*:}"
		val=$(jq -r ".analyzers.${json_key} | if type == \"boolean\" then tostring else empty end" "$CONFIG_FILE")
		if [[ "$val" == "true" || "$val" == "false" ]]; then
			ANALYZER_PROPS="$ANALYZER_PROPS /p:${msbuild_prop}=${val}"
		fi
	done
fi

# Extension point: load fork-specific customizations if present
# Forkers: copy hooks/local.sh.example to hooks/local.sh and customize
EXTRA_BUILD_PROPS=()
LOCAL_HOOK="$SCRIPT_DIR/local.sh"
if [[ -f "$LOCAL_HOOK" ]]; then
	# shellcheck source=/dev/null
	source "$LOCAL_HOOK"
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
	-v:q $ANALYZER_PROPS ${EXTRA_BUILD_PROPS[@]+"${EXTRA_BUILD_PROPS[@]}"} 2>&1) || true

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

# Parse SARIF for issues with two-tier context-efficient output
PARSE_OUTPUT=$("$LIB_DIR/parse-sarif.sh" "$SARIF_FILE" "$SEVERITY_THRESHOLD" "$IGNORE_RULES" "$MAX_ISSUES" "$ALL_CS_FILES")

# Parse the COUNTS line and formatted output
COUNTS_LINE=$(echo "$PARSE_OUTPUT" | head -1)
FORMATTED=$(echo "$PARSE_OUTPUT" | tail -n +2)
MODIFIED_COUNT=$(echo "$COUNTS_LINE" | cut -d: -f2 | cut -d, -f1)
TOTAL_COUNT=$(echo "$COUNTS_LINE" | cut -d: -f2 | cut -d, -f2)

# Ensure counts are valid numbers
if ! [[ "$MODIFIED_COUNT" =~ ^[0-9]+$ ]]; then MODIFIED_COUNT=0; fi
if ! [[ "$TOTAL_COUNT" =~ ^[0-9]+$ ]]; then TOTAL_COUNT=0; fi

if [[ "$TOTAL_COUNT" -gt 0 ]]; then
	# Build header based on counts
	if [[ "$MODIFIED_COUNT" -gt 0 ]]; then
		HEADER="Found $MODIFIED_COUNT issues in modified files ($TOTAL_COUNT total across project):"
	else
		HEADER="Found $TOTAL_COUNT code analysis issues in project (none in modified files):"
	fi

	REASON=$(cat <<EOF
$HEADER

$FORMATTED

Please fix these issues before continuing.
EOF
)
	echo "{\"decision\": \"block\", \"reason\": $(echo "$REASON" | jq -Rs .)}"
else
	echo '{}' # No issues found, allow
fi

exit 0
