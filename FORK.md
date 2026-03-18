# Forking ClaudeDotNetAnalyzer

Feel free to fork this repo to customize it for your team's needs!

---

## Overview

**Fork** when you need to:
- Add analyzer NuGet packages not in the built-in list
- Modify `project-templates/` to match your team's conventions
- Change hook behavior in a way that `hooks/local.sh` alone can't cover

**Install** (without forking) when:
- The built-in analyzers and config options are sufficient
- You want automatic upstream updates with no merge management

When you fork, you get a stable extension point (`hooks/local.sh`) that lets you customize analyzer behavior without touching upstream-maintained files — so `git merge upstream/main` stays clean.

---

## What to Customize

| File / Directory | Owner | What to do |
|---|---|---|
| `project-templates/` | **You** | Edit freely — these are copied into user projects |
| `hooks/local.sh` | **You** | Create from `hooks/local.sh.example`; commit in your fork |
| `hooks/analyze-dotnet.sh` | Upstream | **Don't edit** — pull upstream fixes here |
| `lib/` | Upstream | **Don't edit** — pull upstream fixes here |
| `install.sh` | Upstream | **Don't edit** — pull upstream fixes here |

> **Why not gitignore `hooks/local.sh`?** If upstream gitignored it, your fork would inherit that rule and couldn't commit your own `local.sh`. Instead, `local.sh` is simply absent from upstream by convention.

---

## Adding a Custom Analyzer

This is the most common fork customization. Here's the full workflow:

### 1. Add the NuGet package to `project-templates/config/Directory.Build.props`

```xml
<ItemGroup>
  <!-- Your custom analyzer -->
  <PackageReference Include="SecurityCodeScan.VS2019" Version="5.6.7">
    <PrivateAssets>all</PrivateAssets>
    <IncludeAssets>runtime; build; native; contentfiles; analyzers</IncludeAssets>
  </PackageReference>
</ItemGroup>
```

Use `PrivateAssets="all"` so the analyzer is a build-time tool only, not a transitive dependency.

### 2. Create `hooks/local.sh` from the example

```bash
cp hooks/local.sh.example hooks/local.sh
```

### 3. Add the MSBuild toggle to `hooks/local.sh`

```bash
# Enable your custom analyzer
EXTRA_BUILD_PROPS+=("-p:EnableSecurityCodeScan=true")
```

`EXTRA_BUILD_PROPS` is an array that gets appended to the `dotnet build` invocation. You can add as many entries as needed:

```bash
EXTRA_BUILD_PROPS+=("-p:EnableSecurityCodeScan=true")
EXTRA_BUILD_PROPS+=("-p:SecurityCodeScanMode=strict")
```

### 4. Commit both files

```bash
git add project-templates/config/Directory.Build.props hooks/local.sh
git commit -m "Add SecurityCodeScan analyzer"
```

### 5. (Optional) Add a config toggle to `hooks/analyze-dotnet.sh`'s loop

If you want the analyzer to be toggleable via `.claude-dotnet-analyzer.json`, add a new entry in the `for key_prop in` loop in `hooks/analyze-dotnet.sh`. Note this means editing an upstream-maintained file — consider whether `hooks/local.sh` is sufficient first.

---

## Overriding Config Variables

`hooks/local.sh` is sourced after the config file is loaded, so you can override any variable:

```bash
# Raise the severity bar for your team
SEVERITY_THRESHOLD="warning"

# Suppress rules your team has agreed to ignore
IGNORE_RULES="CA1707,SA1633,MA0016"

# Always use a specific solution
PROJECT_FILE="src/MyCompany.sln"
```

---

## Pulling Upstream Fixes

```bash
# One-time setup (after forking on GitHub)
git remote add upstream https://github.com/johngroot/ClaudeDotNetAnalyzer.git

# Pull upstream fixes
git fetch upstream
git merge upstream/main
```

### What to expect

**No conflicts (typical):** Changes to `hooks/analyze-dotnet.sh`, `lib/`, `install.sh`, `README.md` merge cleanly because you haven't edited those files.

**Possible conflicts:**
- `project-templates/` — if upstream changed a template you also modified, resolve manually, keeping your team's version where it differs
- `FORK.md` — upstream may update this guide; accept upstream's version unless you've added local notes

**Never conflicts:**
- `hooks/local.sh` — absent from upstream, so it's invisible to `git merge`

### If a conflict appears in an upstream-maintained file

This means you've edited a file you shouldn't have. Options:
1. Accept upstream's version (`git checkout --theirs <file>`) and re-apply your change to `hooks/local.sh` or `project-templates/` instead
2. If the change truly can't go elsewhere, keep it and document it — you'll need to re-apply it after each upstream merge
