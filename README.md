# ClaudeDotNetAnalyzer

A portable Claude Code "Stop" hook that runs StyleCop.Analyzers and Microsoft.CodeAnalysis.NetAnalyzers on your .NET projects, presenting issues to Claude for automatic fixing.

Inspired by the [HumanLayer blog post](https://www.humanlayer.dev/blog/writing-a-good-claude-md) on setting up Claude Code hooks for linting.

## How It Works

1. When Claude Code finishes responding, the Stop hook runs
2. The hook checks if any `.cs` files were modified (via `git diff`)
3. If changes exist, it runs `dotnet build` with SARIF output enabled
4. Analyzer issues are parsed and formatted
5. If issues are found, Claude is blocked and presented with the issues to fix
6. Claude automatically continues to fix the reported issues

## Prerequisites

- **dotnet CLI** - .NET SDK 8.0+ ([download](https://dotnet.microsoft.com/download))
- **jq** - JSON processor ([install](https://stedolan.github.io/jq/download/))
- **bash** - Shell (included on macOS/Linux)

## Installation

### Quick Install (Project-Local)

```bash
# From your project root, clone into .claude/tools/
git clone https://github.com/johngroot/ClaudeDotNetAnalyzer .claude/tools/ClaudeDotNetAnalyzer

# Run the installer
.claude/tools/ClaudeDotNetAnalyzer/install.sh
```

### Manual Install

1. Copy the `ClaudeDotNetAnalyzer` directory to your project's `.claude/tools/`
2. Make scripts executable:
   ```bash
   chmod +x .claude/tools/ClaudeDotNetAnalyzer/hooks/*.sh
   chmod +x .claude/tools/ClaudeDotNetAnalyzer/lib/*.sh
   ```

## Configuration

### 1. Configure Claude Code Hook

Add to your project's `.claude/settings.local.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "type": "command",
        "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/tools/ClaudeDotNetAnalyzer/hooks/analyze-dotnet.sh",
        "timeout": 60000
      }
    ]
  }
}
```

The `$CLAUDE_PROJECT_DIR` variable resolves to your project root, making the path portable.

### 2. Enable Analyzers in Your Project

If you don’t have any of the config files already defined in your project you can copy them to its root:

```bash
cp .claude/tools/ClaudeDotNetAnalyzer/project-templates/config/Directory.Build.props ./
cp .claude/tools/ClaudeDotNetAnalyzer/project-templates/config/.editorconfig ./
cp .claude/tools/ClaudeDotNetAnalyzer/project-templates/config/stylecop.json ./
```

Otherwise you can add the various properties to your existing files.

The `Directory.Build.props` file:
- Enables .NET analyzers with `latest-all` analysis level
- Adds StyleCop.Analyzers as a dependency
- Enforces code style during build

### 3. (Optional) Project-Specific Settings

Create `.claude-dotnet-analyzer.json` in your project root:

```json
{
  "severity_threshold": "all",
  "max_issues": 50,
  "ignore_rules": ["CA1707", "SA1633"],
  "project_file": "src/MyProject.sln"
}
```

**Options:**
- `severity_threshold`: `"error"`, `"warning"`, or `"all"` (default)
- `max_issues`: Maximum issues to report (default: 50)
- `ignore_rules`: Array of rule IDs to skip
- `project_file`: Explicit path to .sln or .csproj (auto-detected if omitted)

**Environment variables** (override config file):
- `DOTNET_ANALYZER_SEVERITY` - Severity threshold
- `DOTNET_ANALYZER_MAX_ISSUES` - Maximum issues

## Code Style Rules

The included `.editorconfig` enforces these conventions:

| Element | Convention | Example |
|---------|------------|---------|
| Classes, Methods, Properties | PascalCase | `MyClass`, `DoSomething()` |
| Private/Protected fields | `_camelCase` | `_myField` |
| Public fields | `_PascalCase` | `_MyField` |
| Constants | `ALL_CAPS` | `MAX_VALUE` |
| Parameters, locals | camelCase | `myParam` |
| Indentation | Tabs | - |

You can customize the severity and specificity of those settings in that file 

## Analyzers Included

Further documentation [can be found here](https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/overview?tabs=net-10), but a brief overview:

### Microsoft.CodeAnalysis.NetAnalyzers
- CA1xxx: Design rules
- CA2xxx: Usage rules
- CA3xxx: Security rules
- CA5xxx: Security rules

### StyleCop.Analyzers
- SA1xxx: Documentation rules
- SA0xxx: Special rules

## Customization

### Suppress Specific Rules

In your `.editorconfig`:
```ini
dotnet_diagnostic.CA1822.severity = none
dotnet_diagnostic.SA1633.severity = suggestion
```

In your code:
```csharp
#pragma warning disable CA1822
// code here
#pragma warning restore CA1822
```

Or globally in `GlobalSuppressions.cs`:
```csharp
[assembly: SuppressMessage("Category", "CA1234:Rule", Justification = "Reason")]
```

### Adjust Severity Levels

Edit `Directory.Build.props`:
```xml
<PropertyGroup>
  <!-- Only errors and warnings, not suggestions -->
  <AnalysisLevel>latest-recommended</AnalysisLevel>

  <!-- Treat warnings as errors -->
  <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
</PropertyGroup>
```

## Troubleshooting

### Hook not running
- Verify the hook is configured in `.claude/settings.local.json`
- Check that scripts are executable: `chmod +x .claude/tools/ClaudeDotNetAnalyzer/hooks/*.sh .claude/tools/ClaudeDotNetAnalyzer/lib/*.sh`
- Run with `claude --debug` to see hook execution

### No issues reported
- Verify your project has `Directory.Build.props` or analyzer packages
- Check that `.cs` files were actually modified (check `git status`)
- Run `dotnet build` manually to see if analyzers are running

### Build takes too long
- The hook uses `--no-restore` for speed
- Consider increasing the timeout in settings
- Use `project_file` config to target a specific project instead of solution

### Too many issues
- You can refine issue counts via your project's `.claude-dot-net-analyzer.json` config
- Set `max_issues` to limit output
- Adjust `severity_threshold` to `"warning"` or `"error"`
- Add rules to `ignore_rules` array

## File Structure

```
ClaudeDotNetAnalyzer/
├── hooks/                   # Source: hook scripts
│   └── analyze-dotnet.sh    # Main entry point (Stop hook)
├── lib/                     # Source: utility scripts
│   ├── parse-sarif.sh       # SARIF output parser
│   └── detect-project.sh    # .NET project detection
├── project-templates/       # Files to copy into your project
│   ├── config/
│   │   ├── Directory.Build.props # MSBuild config (enables analyzers)
│   │   ├── .editorconfig    # Code style rules
│   │   └── stylecop.json    # StyleCop settings
│   └── templates/
│       ├── claude-settings.json # Hook config template
│       └── .claude-dotnet-analyzer.json # Project config template
├── install.sh               # Installer script
└── README.md
```

