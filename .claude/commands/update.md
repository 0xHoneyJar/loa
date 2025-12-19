---
description: Update Loa framework from upstream repository
---

# Loa Update

This command pulls the latest Loa framework updates from the upstream repository.

---

## Phase 1: Pre-flight Checks

### Check Working Tree

First, ensure your working tree is clean:

```bash
git status --porcelain
```

If output is NOT empty:

1. Display:
   ```
   Your working tree has uncommitted changes.

   Please commit or stash your changes before updating:
   ```

2. List the changed files:
   ```bash
   git status --short
   ```

3. Display:
   ```
   Options:
   - Commit your changes: git add . && git commit -m "WIP: save before update"
   - Stash your changes: git stash push -m "before loa update"

   After handling your changes, run `/update` again.
   ```

4. **STOP** - Do not proceed with update.

---

### Check Upstream Remote

Verify the Loa upstream remote is configured:

```bash
git remote -v | grep -E "^(loa|upstream)" | head -1
```

Look for a remote named `loa` or `upstream` that points to the Loa repository.

If no matching remote found:

1. Display:
   ```
   The Loa upstream remote is not configured.

   To add it, run:
     git remote add loa https://github.com/0xHoneyJar/loa.git

   After adding the remote, run `/update` again.
   ```

2. **STOP** - Do not proceed with update.

---

## Phase 2: Fetch Updates

Fetch the latest changes from the Loa remote:

```bash
git fetch loa main
```

If fetch fails (network error, auth issue):

1. Display error message
2. Suggest checking network connection and remote URL
3. **STOP** - Do not proceed

---

## Phase 3: Show Changes

### Check for New Commits

```bash
git log HEAD..loa/main --oneline
```

If no output (no new commits):

1. Display:
   ```
   You're already up to date with Loa!

   No new commits available from upstream.
   ```

2. **STOP** - Nothing to update.

### Display Changes Summary

If there are new commits:

1. Count new commits:
   ```bash
   git rev-list HEAD..loa/main --count
   ```

2. Show commit list:
   ```bash
   git log HEAD..loa/main --oneline --no-merges
   ```

3. Show files that will change:
   ```bash
   git diff --stat HEAD..loa/main
   ```

4. Display summary:
   ```
   ## Loa Updates Available

   **{N} new commit(s)** from upstream:

   {commit_list}

   **Files to be updated:**
   {file_diff_stat}
   ```

---

## Phase 4: Confirm Update

Ask for confirmation before merging:

```
Would you like to merge these updates?

- Yes: Proceed with merge
- No: Cancel update

Note: Framework files in .claude/ will be updated to the latest Loa versions.
Your project files (app/, loa-grimoire/prd.md, etc.) will be preserved.
```

If user says No:
1. Display: "Update cancelled. Run `/update` again when ready."
2. **STOP**

---

## Phase 5: Merge Updates

Perform the merge:

```bash
git merge loa/main -m "chore: update Loa framework

Merged latest updates from loa/main.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

---

## Phase 6: Handle Merge Result

### If Merge Successful (No Conflicts)

1. Display:
   ```
   ## Loa Updated Successfully!

   The framework has been updated to the latest version.

   ### What's New

   Review CHANGELOG.md for details on new features and changes:
   ```

2. Show recent changelog entries if available:
   ```bash
   head -50 CHANGELOG.md 2>/dev/null | grep -A 20 "## \[" | head -25
   ```

3. Display:
   ```
   ### Next Steps

   - Review any new commands or features in CLAUDE.md
   - Check CHANGELOG.md for breaking changes
   - Run `/setup` if prompted by new setup requirements
   ```

### If Merge Has Conflicts

1. List conflicted files:
   ```bash
   git diff --name-only --diff-filter=U
   ```

2. Display:
   ```
   ## Merge Conflicts Detected

   The following files have conflicts that need resolution:

   {conflicted_files_list}
   ```

3. For each conflicted file, provide guidance:

   **For files in `.claude/` directory**:
   ```
   ### {filename} (Framework File)

   This is a Loa framework file. Recommended action:
   - Accept the upstream (Loa) version unless you have intentional customizations
   - To accept upstream: git checkout --theirs {filename}
   ```

   **For files outside `.claude/`**:
   ```
   ### {filename} (Project File)

   This is a project file. You'll need to manually resolve the conflict:
   1. Open the file and look for conflict markers (<<<<<<< HEAD)
   2. Keep the changes you want from both versions
   3. Remove the conflict markers
   4. Save the file
   ```

4. Display resolution instructions:
   ```
   ### After Resolving Conflicts

   Once all conflicts are resolved:

   1. Stage the resolved files:
      git add .

   2. Complete the merge:
      git commit -m "chore: update Loa framework (conflicts resolved)"

   3. Verify the update:
      git log --oneline -3
   ```

---

## Merge Strategy Notes

The update process uses standard git merge behavior:

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

**Recommendation**: For `.claude/` files, prefer accepting upstream versions to get the latest agent improvements and bug fixes. Only keep local versions if you have intentional customizations.
