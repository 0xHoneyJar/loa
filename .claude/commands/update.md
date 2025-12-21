---
name: "update"
version: "1.0.0"
description: |
  Pull latest Loa framework updates from upstream repository.
  Fetches, previews, confirms, and merges with conflict guidance.

command_type: "git"

arguments: []

pre_flight:
  - check: "command_succeeds"
    command: "test -z \"$(git status --porcelain)\""
    error: |
      Your working tree has uncommitted changes.

      Please commit or stash your changes before updating:
      - Commit: git add . && git commit -m "WIP: save before update"
      - Stash: git stash push -m "before loa update"

      After handling your changes, run /update again.

  - check: "command_succeeds"
    command: "git remote -v | grep -qE '^(loa|upstream)'"
    error: |
      The Loa upstream remote is not configured.

      To add it, run:
        git remote add loa https://github.com/0xHoneyJar/loa.git

      After adding the remote, run /update again.

outputs:
  - path: "git merge commit"
    type: "git"
    description: "Merged upstream changes"

mode:
  default: "foreground"
  allow_background: false
---

# Update

## Purpose

Pull the latest Loa framework updates from the upstream repository. Safely fetches, previews changes, and merges with guidance for conflict resolution.

## Invocation

```
/update
```

## Prerequisites

- Working tree must be clean (no uncommitted changes)
- `loa` or `upstream` remote must be configured

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

### Phase 5: Merge Updates

```bash
git merge loa/main -m "chore: update Loa framework"
```

### Phase 6: Handle Merge Result

- **Success**: Show changelog excerpt and next steps
- **Conflicts**: List conflicted files with resolution guidance

## Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| None | | |

## Outputs

| Path | Description |
|------|-------------|
| Git merge commit | Merged upstream changes |

## Merge Strategy

| File Location | Merge Behavior |
|---------------|----------------|
| `.claude/agents/` | Updated to latest Loa versions |
| `.claude/commands/` | Updated to latest Loa versions |
| `CLAUDE.md` | Standard merge (may conflict) |
| `PROCESS.md` | Standard merge (may conflict) |
| `app/` | Preserved (your code) |
| `loa-grimoire/prd.md` | Preserved (your docs) |
| `loa-grimoire/sdd.md` | Preserved (your docs) |
| `loa-grimoire/analytics/` | Preserved (your data) |
| `.loa-setup-complete` | Preserved (your setup state) |

## Conflict Resolution

### Framework Files (`.claude/`)

Recommend accepting upstream version:
```bash
git checkout --theirs {filename}
```

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

## Next Steps After Update

- Review `CHANGELOG.md` for new features and changes
- Check `CLAUDE.md` for new commands or workflow updates
- Run `/setup` if prompted by new setup requirements
