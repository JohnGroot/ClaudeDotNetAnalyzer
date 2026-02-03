#!/bin/bash
# Detect .NET project or solution file in directory
# Usage: detect-project.sh <directory>
# Returns: Path to .sln or .csproj file, or empty if none found

SEARCH_DIR="${1:-.}"

# First, look for a solution file (preferred)
SLN_FILE=$(find "$SEARCH_DIR" -maxdepth 2 -name "*.sln" -type f 2>/dev/null | head -1)
if [[ -n "$SLN_FILE" ]]; then
	echo "$SLN_FILE"
	exit 0
fi

# Next, look for a csproj file
CSPROJ_FILE=$(find "$SEARCH_DIR" -maxdepth 3 -name "*.csproj" -type f 2>/dev/null | head -1)
if [[ -n "$CSPROJ_FILE" ]]; then
	echo "$CSPROJ_FILE"
	exit 0
fi

# No .NET project found
exit 0
