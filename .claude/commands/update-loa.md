---
name: "update-loa"
version: "1.3.0"
description: |
  Pull latest Loa framework updates from upstream repository.
  Fetches, previews, confirms, and merges with conflict guidance.
  Supports WIP branch testing with checkout option.

command_type: "git"

arguments:
  - name: "branch"
    type: "string"
    required: false
    description: "Optional branch name to update from (default: main)"

pre_flight:
  - check: "command_succeeds"
    command: "test -z \"$(git status --porcelain)\""
    error: |
      Your working tree has uncommitted changes.

      Please commit or stash your changes before updating:
      - Commit: git add . && git commit -m "WIP: save before update"
      - Stash: git stash push -m "before loa update"

      After handling your changes, run /update-loa again.

  - check: "command_succeeds"
    command: "git remote -v | grep -qE '^(loa|upstream)'"
    error: |
      The Loa upstream remote is not configured.

      To add it, run:
        git remote add loa https://github.com/0xHoneyJar/loa.git

      After adding the remote, run /update-loa again.

  - check: "command_succeeds"
    command: "git config merge.ours.driver >/dev/null 2>&1 || git config merge.ours.driver true"
    error: |
      Failed to configure merge driver for project files.

outputs:
  - path: "git merge commit"
    type: "git"
    description: "Merged upstream changes"

mode:
  default: "foreground"
  allow_background: false
---

# Update Loa

## Purpose

Pull the latest Loa framework updates from the upstream repository. Safely fetches, previews changes, and merges with guidance for conflict resolution.

## Invocation

```
/update-loa
/update-loa main
/update-loa feature/constructs-multiselect
```

## WIP Branch Testing (v1.2.0)

When a feature branch is specified (matching `feature/*`, `fix/*`, `topic/*`, `wip/*`, or `test/*`), the command offers two options via AskUserQuestion:

1. **Checkout for testing (Recommended)** - Creates a local `test/loa-{branch}` branch from the remote
2. **Merge into current branch** - Traditional merge behavior

### Branch Testing Flow

```
/update-loa feature/constructs-multiselect
    ↓
AskUserQuestion: "How would you like to use this branch?"
    ↓
[Checkout] → Creates test/loa-feature/constructs-multiselect
           → Saves state to .loa/branch-testing.json
           → "Ready for testing. Run /update-loa to return."
    ↓
[Later: /update-loa with no args while in test branch]
    ↓
AskUserQuestion: "You're testing loa/feature/constructs-multiselect"
    ↓
[Return to main] → Checks out original branch
                 → Clears state file
```

### Configuration

```yaml
# .loa.config.yaml
update_loa:
  branch_testing:
    enabled: true
    feature_patterns:
      - "feature/*"
      - "fix/*"
      - "topic/*"
      - "wip/*"
      - "test/*"
    test_branch_prefix: "test/loa-"
```

### AskUserQuestion Integration

**Branch mode selection** (when feature branch detected):

```yaml
questions:
  - question: "How would you like to use branch '{branch}'?"
    header: "Branch mode"
    options:
      - label: "Checkout for testing (Recommended)"
        description: "Switch to test/loa-{branch} for isolated testing"
      - label: "Merge into current branch"
        description: "Merge changes into your current branch ({current})"
    multiSelect: false
```

**Return helper** (when in test branch and no args):

```yaml
questions:
  - question: "You're testing loa/{branch}. What would you like to do?"
    header: "Test branch"
    options:
      - label: "Return to {original} (Recommended)"
        description: "Checkout original branch and clear test state"
      - label: "Stay on test branch"
        description: "Continue testing, keep state"
      - label: "Merge into {original}"
        description: "Merge test branch changes into original"
    multiSelect: false
```

### State Management

State is tracked via `.claude/scripts/branch-state.sh`:

```bash
# Check if in test mode
.claude/scripts/branch-state.sh is-testing

# Load state
.claude/scripts/branch-state.sh load
# → {"testing_branch":"feature/foo","original_branch":"main",...}

# Clear after return
.claude/scripts/branch-state.sh clear
```

## Prerequisites

- Working tree must be clean (no uncommitted changes)
- `loa` or `upstream` remote must be configured
- Merge driver configured (one-time): `git config merge.ours.driver true`

## Workflow

### Phase 1: Pre-flight Checks

1. Verify working tree is clean
2. Verify upstream remote exists

### Phase 2: Fetch Updates

```bash
git fetch loa main
```

### Phase 3: Show Changes

- Count new commits
- Display commit list
- Show files that will change

### Phase 4: Confirm Update

Ask for confirmation before merging. Note which files will be updated vs preserved.

### Phase 5: Merge Updates (with --no-commit)

```bash
git merge loa/main --no-commit
```

> **IMPORTANT**: The `--no-commit` flag stages the merge without committing, allowing
> Phases 5.3 and 5.5 to inspect and fix collateral damage before the commit is created.
> HEAD still points to the pre-merge branch tip during these phases.
>
> **Conflict handling**: If `git merge --no-commit` exits non-zero due to conflicts,
> resolve conflicts first (see Phase 6), then proceed to Phase 5.3. The safeguard
> operates on staged deletions (`--diff-filter=D`) which are present even during a
> conflicted merge state — conflicted files show as "both modified", not as deletions.

### Phase 5.3: Collateral Deletion Safeguard (v1.3.0)

After the merge is staged but before committing, scan for files being deleted that are **outside** the Loa framework zone. These deletions are collateral damage from upstream cleanup and must not propagate to downstream projects.

```bash
# Identify files staged for deletion by the merge
deleted_files=$(git diff --cached --diff-filter=D --name-only)
restored_count=0

if [[ -n "$deleted_files" ]]; then
  while IFS= read -r file; do
    case "$file" in
      # Framework zone — upstream deletions are intentional, allow them
      .claude/*) ;;
      .loa-version.json) ;;
      CLAUDE.md) ;;
      PROCESS.md) ;;
      .gitattributes) ;;
      INSTALLATION.md) ;;
      .loa.config.yaml.example) ;;
      # Everything else — non-framework file, restore from pre-merge state
      *)
        git checkout HEAD -- "$file" 2>/dev/null && ((restored_count++)) || true
        ;;
    esac
  done <<< "$deleted_files"

  if [[ $restored_count -gt 0 ]]; then
    echo "Safeguard: restored $restored_count non-framework files that would have been deleted by upstream merge"
  fi
fi
```

> **Why?** When upstream performs cleanup (removing template/example files), `git merge`
> propagates those deletions to downstream projects that share git history. This safeguard
> uses an allowlist of framework-managed paths — only deletions within the framework zone
> are permitted. All other files are restored from HEAD (pre-merge state), preserving
> downstream application code, configurations, and documentation.
>
> **Fixes**: [#331](https://github.com/0xHoneyJar/loa/issues/331) — cycle-014 merge
> deleting 933 downstream project files.

### Phase 5.5: Revert Protected Paths

Check for and revert any changes to protected paths that should not propagate to downstream projects. Since the merge is not yet committed (`--no-commit`), use `git diff --cached` and restore from `HEAD`:

```bash
# Check if .github/workflows/ has staged changes from the merge
workflow_changes=$(git diff --cached --name-only -- '.github/workflows/')
if [[ -n "$workflow_changes" ]]; then
  while IFS= read -r f; do
    if git show "HEAD:$f" >/dev/null 2>&1; then
      # File existed before merge — restore pre-merge version
      git checkout HEAD -- "$f"
    else
      # New file from upstream — unstage and remove
      git rm -f --cached "$f" 2>/dev/null || true
      rm -f "$f" 2>/dev/null || true
    fi
  done <<< "$workflow_changes"
fi
```

> **Why?** GitHub requires the `workflow` OAuth scope to push changes to `.github/workflows/`. Most downstream users don't have this scope. The `.gitattributes` `merge=ours` rule protects existing workflow files, but new workflow files added upstream still propagate via merge. This step catches both cases. (Defense-in-depth: Phase 5.3 already handles workflow file deletions, but this phase additionally catches new and modified workflow files.)

### Phase 5.7: Commit the Safeguarded Merge

After all safeguards have run, create the merge commit:

```bash
git commit -m "chore: update Loa framework"
```

### Phase 5.8: Sync Constructs

After the merge commit, sync construct pack skills to ensure newly added skills in pack updates are registered:

```bash
if [[ -x ".claude/scripts/sync-constructs.sh" ]]; then
  echo "Syncing construct packs..."
  .claude/scripts/sync-constructs.sh
fi
```

### Phase 6: Handle Merge Result

- **Success**: Show changelog excerpt and next steps
- **Conflicts**: List conflicted files with resolution guidance

## Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| `branch` | Branch name to update from (default: main) | No |

## Outputs

| Path | Description |
|------|-------------|
| Git merge commit | Merged upstream changes |

## Merge Strategy

| File Location | Merge Behavior |
|---------------|----------------|
| `.claude/skills/` | Updated to latest Loa versions |
| `.claude/commands/` | Updated to latest Loa versions |
| `.claude/protocols/` | Updated to latest Loa versions |
| `.claude/scripts/` | Updated to latest Loa versions |
| `CLAUDE.md` | Standard merge (may conflict) |
| `PROCESS.md` | Standard merge (may conflict) |
| `app/` | **Auto-preserved** via Phase 5.3 collateral deletion safeguard |
| `grimoires/loa/prd.md` | **Auto-preserved** via Phase 5.3 collateral deletion safeguard |
| `grimoires/loa/sdd.md` | **Auto-preserved** via Phase 5.3 collateral deletion safeguard |
| `grimoires/loa/analytics/` | **Auto-preserved** via Phase 5.3 collateral deletion safeguard |
| All non-framework files | **Auto-preserved** via Phase 5.3 collateral deletion safeguard |
| `.github/workflows/` | **Auto-preserved** via `.gitattributes` + Phase 5.5 revert |
| `CHANGELOG.md` | **Auto-preserved** via `.gitattributes` (merge=ours) |
| `README.md` | **Auto-preserved** via `.gitattributes` (merge=ours) |

> **Note**: All non-framework files are protected by the Phase 5.3 collateral deletion safeguard (v1.3.0). README.md, CHANGELOG.md, and `.github/workflows/` files have additional protection via `.gitattributes` merge=ours and Phase 5.5 revert. The pre-flight check ensures the `merge.ours.driver` is configured.

## Conflict Resolution

### Framework Files (`.claude/`)

Recommend accepting upstream version:
```bash
git checkout --theirs {filename}
```

### Project Identity Files (`CHANGELOG.md`, `README.md`)

These files define YOUR project, not the Loa framework. ALWAYS keep your version:
```bash
git checkout --ours CHANGELOG.md README.md
```

Never accept upstream versions of these files - they contain Loa's template content, not your project's history and documentation.

### Project Files

Manual resolution required:
1. Open file and find conflict markers (`<<<<<<< HEAD`)
2. Keep changes you want from both versions
3. Remove conflict markers
4. Save the file

### After Resolving

```bash
git add .
git commit -m "chore: update Loa framework (conflicts resolved)"
```

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| "Uncommitted changes" | Dirty working tree | Commit or stash changes first |
| "Remote not configured" | Missing loa/upstream remote | Add remote with `git remote add` |
| "Fetch failed" | Network or auth error | Check connection and remote URL |
| "Already up to date" | No new commits | Nothing to update |
| "Branch not found" | Remote branch doesn't exist | Check available branches with `git branch -r \| grep loa/` |
| "Invalid branch name" | Branch contains invalid characters | Only use alphanumeric, dash, underscore, slash, dot |
| "State file corrupt" | Invalid JSON in branch-testing.json | State auto-cleared, continue normally |
| "Safeguard: restored N files" | Upstream cleanup deleted non-framework files | Normal — safeguard working as intended |

### Branch Testing Errors

**Branch not found on remote:**
```
Error: Branch 'feature/does-not-exist' not found on remote 'loa'
Available branches:
  loa/main
  loa/feature/constructs-multiselect
  loa/fix/label-handling

To list all remote branches: git branch -r | grep loa/
```

**Dirty working tree (with stash suggestion):**
```
Error: Your working tree has uncommitted changes.

Quick fix: git stash push -m "before testing loa branch"
After testing: git stash pop
```

## Next Steps After Update

- Review [Loa releases](https://github.com/0xHoneyJar/loa/releases) for new features and changes
- Check `CLAUDE.md` for new commands or workflow updates
