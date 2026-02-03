#!/bin/bash
# ClaudeDotNetAnalyzer Installer
# Installs the analyzer tool and configures Claude Code hook
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${CLAUDE_TOOLS_DIR:-$SCRIPT_DIR}"

echo "ClaudeDotNetAnalyzer Installer"
echo "=============================="
echo ""

# Check prerequisites
echo "Checking prerequisites..."

if ! command -v dotnet &> /dev/null; then
	echo "ERROR: dotnet CLI not found. Please install .NET SDK first."
	echo "       https://dotnet.microsoft.com/download"
	exit 1
fi

if ! command -v jq &> /dev/null; then
	echo "ERROR: jq not found. Please install jq first."
	echo "       macOS: brew install jq"
	echo "       Ubuntu: sudo apt-get install jq"
	exit 1
fi

echo "  dotnet: $(dotnet --version)"
echo "  jq: $(jq --version)"
echo ""

# Create installation directory
echo "Installing to: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

# Copy files
if [[ "$SCRIPT_DIR" != "$INSTALL_DIR" ]]; then
	cp -r "$SCRIPT_DIR/hooks" "$INSTALL_DIR/"
	cp -r "$SCRIPT_DIR/lib" "$INSTALL_DIR/"
	cp -r "$SCRIPT_DIR/project-templates" "$INSTALL_DIR/"
	cp "$SCRIPT_DIR/README.md" "$INSTALL_DIR/" 2>/dev/null || true
fi

# Make scripts executable
chmod +x "$INSTALL_DIR/hooks/"*.sh
chmod +x "$INSTALL_DIR/lib/"*.sh

echo ""
echo "Installation complete!"
echo ""
echo "=============================="
echo "NEXT STEPS"
echo "=============================="
echo ""
echo "1. Add the hook to your Claude Code settings."
echo "   Edit .claude/settings.local.json and add:"
echo ""
echo '   {'
echo '     "hooks": {'
echo '       "Stop": ['
echo '         {'
echo '           "type": "command",'
echo '           "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/tools/ClaudeDotNetAnalyzer/hooks/analyze-dotnet.sh",'
echo '           "timeout": 60000'
echo '         }'
echo '       ]'
echo '     }'
echo '   }'
echo ""
echo "2. (Optional) Copy config files to your .NET project root:"
echo "   cp $INSTALL_DIR/project-templates/config/Directory.Build.props ./"
echo "   cp $INSTALL_DIR/project-templates/config/.editorconfig ./"
echo "   cp $INSTALL_DIR/project-templates/config/stylecop.json ./"
echo ""
echo "3. (Optional) Create project-specific config:"
echo "   cp $INSTALL_DIR/project-templates/templates/.claude-dotnet-analyzer.json ./"
echo ""
echo "For more information, see: $INSTALL_DIR/README.md"
