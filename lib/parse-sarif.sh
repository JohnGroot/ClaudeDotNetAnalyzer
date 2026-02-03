#!/bin/bash
# Parse SARIF file and extract diagnostics
# Usage: parse-sarif.sh <sarif_file> [severity_threshold] [ignore_rules] [max_issues]

SARIF_FILE="$1"
SEVERITY_THRESHOLD="${2:-all}"
IGNORE_RULES="${3:-}"
MAX_ISSUES="${4:-50}"

if [[ ! -f "$SARIF_FILE" ]]; then
	exit 0
fi

# Build jq filter based on severity threshold
case "$SEVERITY_THRESHOLD" in
	error)
		SEVERITY_FILTER='.level == "error"'
		;;
	warning)
		SEVERITY_FILTER='(.level == "error" or .level == "warning")'
		;;
	all|*)
		SEVERITY_FILTER='(.level == "error" or .level == "warning" or .level == "note")'
		;;
esac

# Build ignore rules filter
if [[ -n "$IGNORE_RULES" ]]; then
	# Convert comma-separated rules to jq array check
	IGNORE_ARRAY=$(echo "$IGNORE_RULES" | jq -R 'split(",") | map(select(length > 0))')
	RULES_FILTER="and (.ruleId as \$r | $IGNORE_ARRAY | index(\$r) | not)"
else
	RULES_FILTER=""
fi

# Extract results using jq
# Handle both SARIF 1.0.0 (string message, resultFile) and 2.1.0 (message.text, physicalLocation) formats
jq -r --argjson max "$MAX_ISSUES" "
.runs[]? |
.results[]? |
select($SEVERITY_FILTER $RULES_FILTER) |
{
	ruleId: .ruleId,
	level: .level,
	message: (if .message | type == \"object\" then .message.text else .message end // \"No message\"),
	file: (
		.locations[0]?.physicalLocation?.artifactLocation?.uri //
		.locations[0]?.resultFile?.uri //
		\"unknown\"
	),
	line: (
		.locations[0]?.physicalLocation?.region?.startLine //
		.locations[0]?.resultFile?.region?.startLine //
		0
	),
	column: (
		.locations[0]?.physicalLocation?.region?.startColumn //
		.locations[0]?.resultFile?.region?.startColumn //
		0
	)
} |
\"[\(.ruleId)] \(.file | gsub(\"file://\"; \"\"))(\(.line),\(.column)): \(.message)\"
" "$SARIF_FILE" 2>/dev/null | head -n "$MAX_ISSUES"
