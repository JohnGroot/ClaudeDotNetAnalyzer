# Fork Design: Easy Forking for Roslyn Analysis Pipelines

**Date:** 2026-03-18
**Status:** Implemented

## Context

ClaudeDotNetAnalyzer is a Claude Code Stop hook that runs Roslyn analyzers on .NET projects after Claude writes code. As the project matures, other developers will want to fork it to implement their team's specific analyzer pipeline — custom packages, style rules, and hook behavior — while still being able to pull upstream bug fixes without painful merge conflicts.

**The problem:** there's currently no clear guidance on what to customize vs. leave alone, and the hook script has no extension mechanism, so forkers who need custom behavior must edit core files and risk conflicts on every upstream merge.

**The solution:** add a documented sidecar extension point to the hook (`hooks/local.sh`), plus a `FORK.md` guide that makes the file ownership contract explicit.

---

## File Ownership Taxonomy

| File/Directory | Owner | Policy |
|---|---|---|
| `project-templates/` | Forker | Change freely — these are copied into user projects |
| `hooks/local.sh` | Forker | Create from `hooks/local.sh.example`; tracked in forks, absent from upstream |
| `hooks/analyze-dotnet.sh` | Upstream | Avoid editing; accept upstream changes without conflict |
| `lib/` | Upstream | Avoid editing; accept upstream changes without conflict |
| `install.sh` | Upstream | Avoid editing; accept upstream changes without conflict |
| `FORK.md` | Upstream | Reference only; can add your own `FORK.local.md` if needed |

---

## Extension Mechanism: `hooks/local.sh`

The hook sources `hooks/local.sh` (if it exists) after config loading, before `dotnet build` runs. This gives forkers a stable, conflict-free place to:

1. **Override config variables** (`SEVERITY_THRESHOLD`, `MAX_ISSUES`, `IGNORE_RULES`, `PROJECT_FILE`)
2. **Append MSBuild properties** via the `EXTRA_BUILD_PROPS` array

### Why a sourced sidecar?

- **No conflict surface**: `local.sh` is absent from upstream, so `git merge upstream/main` never touches it
- **Full shell power**: forkers can use conditionals, read environment variables, or compute values at hook run time
- **Discoverable**: the example file documents all override points in one place

### Why `EXTRA_BUILD_PROPS` as an array?

The hook runs under `set -euo pipefail`. With bash's `-u` (nounset), `"${arr[@]}"` on an empty array triggers an error in bash 3.x (macOS's default shell). The expansion pattern `${arr[@]+"${arr[@]}"}` safely expands to nothing when the array is empty, and to the full array contents when non-empty.

### Convention: not gitignored

`hooks/local.sh` is absent from upstream by convention, not by `.gitignore`. If it were gitignored upstream, forked repos would inherit that rule and couldn't commit their own `local.sh`. Forkers simply create the file and commit it.

---

## FORK.md Structure

1. **Overview** — why fork vs. install, what you get
2. **What to customize** — ownership table
3. **Adding a custom analyzer** — step-by-step walkthrough
4. **Pulling upstream fixes** — merge workflow and conflict guidance

---

## Files Created/Modified

- `hooks/analyze-dotnet.sh` — added `EXTRA_BUILD_PROPS` init, `local.sh` sourcing, array expansion in build command
- `hooks/local.sh.example` — documented template for fork customizations
- `FORK.md` — fork guide
- `README.md` — "For Forkers" section in Customization
- `docs/superpowers/specs/2026-03-18-fork-design.md` — this document
