#!/bin/bash
# Parse SARIF file and extract diagnostics with two-tier output
# Usage: parse-sarif.sh <sarif_file> [severity_threshold] [ignore_rules] [max_issues] [modified_files_json]
#
# Output format:
#   Line 1: COUNTS:<modified_count>,<total_count>
#   Lines 2+: Formatted tier-1 (modified file issues, deduplicated) and tier-2 (summary of rest)

SARIF_FILE="$1"
SEVERITY_THRESHOLD="${2:-all}"
IGNORE_RULES="${3:-}"
MAX_ISSUES="${4:-50}"
MODIFIED_FILES="${5:-[]}"

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
	IGNORE_ARRAY=$(echo "$IGNORE_RULES" | jq -R 'split(",") | map(select(length > 0))')
	RULES_FILTER="and (.ruleId as \$r | $IGNORE_ARRAY | index(\$r) | not)"
else
	RULES_FILTER=""
fi

# Single jq pipeline: parse, filter, partition, deduplicate, format
jq -r --argjson max "$MAX_ISSUES" --argjson modified_files "$MODIFIED_FILES" "
def clean_path: gsub(\"file:///?\";\"\");

def is_modified:
  .file | clean_path | . as \$f |
  (\$modified_files | length > 0) and (\$modified_files | any(. as \$mf | \$f | endswith(\$mf)));

def format_group:
  if length == 1 then
    .[0] | \"[\(.ruleId)] \(.file | clean_path)(\(.line),\(.column)): \(.message)\"
  else
    .[0] as \$first |
    \"[\(\$first.ruleId)] \(\$first.file | clean_path): \(\$first.message) (\(length) occurrences, lines \(map(.line) | join(\", \")))\"
  end;

# Extract all matching results
[
  .runs[]? |
  .results[]? |
  select(($SEVERITY_FILTER $RULES_FILTER) and ((.suppressions // []) | length == 0)) |
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
  }
] |

# Partition into modified vs other
. as \$all |
[.[] | select(is_modified)] as \$mod |
[.[] | select(is_modified | not)] as \$other |

# Deduplicate modified-file issues: group by rule+file
(\$mod | group_by([.ruleId, .file]) | map(format_group) | .[:(\$max)] | join(\"\n\")) as \$tier1 |

# Summarize other-file issues by rule
(\$other | length) as \$other_count |
(
  if \$other_count > 0 then
    \$other | group_by(.ruleId) | map({rule: .[0].ruleId, count: length}) | sort_by(-.count) |
    if length <= 4 then
      map(\"\(.rule): \(.count)\") | join(\", \")
    else
      (.[:3] | map(\"\(.rule): \(.count)\") | join(\", \")) + \", other: \(.[3:] | map(.count) | add)\"
    end |
    \"Remaining: \(\$other_count) issues in other files (\" + . + \")\"
  else
    \"\"
  end
) as \$tier2 |

# Output counts line, then formatted tiers
\"COUNTS:\(\$mod | length),\(\$all | length)\" +
(if (\$tier1 | length) > 0 then \"\n\" + \$tier1 else \"\" end) +
(if (\$tier2 | length) > 0 then \"\n\" + \$tier2 else \"\" end)
" "$SARIF_FILE" 2>/dev/null || true
