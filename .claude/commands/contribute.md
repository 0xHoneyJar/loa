---
description: Create an OSS contribution PR to the Loa upstream repository
---

# Contribute to Loa

This command guides you through creating a standards-compliant pull request to contribute improvements back to the Loa framework.

---

## Phase 1: Pre-flight Checks

Execute these checks in order. **STOP** if any check fails.

### Check 1: Feature Branch

```bash
CURRENT_BRANCH=$(git branch --show-current)
```

**If `$CURRENT_BRANCH` is empty (detached HEAD state):**

Display this message and **STOP**:

```
## Detached HEAD State Detected

You're in a detached HEAD state, which means you're not on any branch.
Contributions must be made from a feature branch.

### How to Fix

1. Create a branch at your current position:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Run `/contribute` again.

**Why?** Branches are required to track and push your changes properly.
```

**If `$CURRENT_BRANCH` is `main` or `master`:**

Display this message and **STOP**:

```
## Cannot Contribute from Main Branch

You're on the main branch. Contributions must be made from a feature branch.

### How to Fix

1. Create a feature branch:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Make your changes (if you haven't already)

3. Commit your changes:
   ```bash
   git add .
   git commit -s -m "your commit message"
   ```

4. Run `/contribute` again.

**Why?** Feature branches isolate your changes and make review easier.
```

### Check 2: Clean Working Tree

```bash
git status --porcelain
```

**If output is not empty (uncommitted changes exist):**

Display this message and **STOP**:

```
## Uncommitted Changes Detected

Your working tree has uncommitted changes. Please commit or stash them first.

### How to Fix

**Option A: Commit your changes**
```bash
git add .
git commit -s -m "your commit message"
```

**Option B: Stash changes for later**
```bash
git stash push -m "WIP: description"
```

Then run `/contribute` again.

**Why?** Contributions should include only committed, intentional changes.
```

### Check 3: Upstream Remote Configured

```bash
git remote -v | grep -E "^(upstream|loa)\s.*0xHoneyJar/loa"
```

**If no match found (no upstream remote):**

Display this message and **STOP**:

```
## Upstream Remote Not Configured

The Loa upstream remote is not configured. This is needed to create a PR.

### How to Fix

Add the Loa repository as a remote:
```bash
git remote add loa https://github.com/0xHoneyJar/loa.git
git fetch loa
```

Then run `/contribute` again.

### Verify Remote Setup

After adding, your remotes should look like:
```bash
$ git remote -v
origin    git@github.com:YOUR_ORG/YOUR_PROJECT.git (fetch)
origin    git@github.com:YOUR_ORG/YOUR_PROJECT.git (push)
loa       https://github.com/0xHoneyJar/loa.git (fetch)
loa       https://github.com/0xHoneyJar/loa.git (push)
```
```

### All Pre-flight Checks Passed

If all checks pass, display:

```
## Pre-flight Checks ✓

✓ On feature branch: {CURRENT_BRANCH}
✓ Working tree is clean
✓ Upstream remote configured

Proceeding to standards checklist...
```

Continue to Phase 2.

---

## Phase 2: Standards Checklist

Use the `AskUserQuestion` tool with `multiSelect: false` to confirm the user has prepared their contribution:

```javascript
AskUserQuestion({
  questions: [{
    question: "Have you completed the contribution standards checklist?",
    header: "Standards",
    multiSelect: false,
    options: [
      {
        label: "Yes, all items complete",
        description: "Commits are clean, no secrets, tests pass, DCO sign-off present"
      },
      {
        label: "I have concerns",
        description: "I need help addressing one or more items"
      },
      {
        label: "Show me the checklist",
        description: "Display the full checklist with details"
      }
    ]
  }]
})
```

### If user selects "Show me the checklist":

Display:

```
## Contribution Standards Checklist

Please ensure each item is complete before proceeding:

### 1. Clean Commit History
[ ] Commits are focused and atomic (one logical change per commit)
[ ] Commit messages are clear and descriptive
[ ] History is rebased/squashed if needed for clarity

### 2. No Sensitive Data
[ ] No API keys, tokens, or credentials in code
[ ] No personal information in commits (use work email)
[ ] No internal URLs or proprietary information

### 3. Tests (if applicable)
[ ] Existing tests still pass
[ ] New functionality has appropriate test coverage
[ ] Edge cases are handled

### 4. DCO Sign-off
[ ] All commits include `Signed-off-by: Your Name <email>` line
[ ] Sign-off certifies you have the right to submit this contribution
[ ] Use `git commit -s` to add sign-off automatically

**Details**: See CONTRIBUTING.md for full contribution guidelines.
```

Then ask again using the same AskUserQuestion.

### If user selects "I have concerns":

Use `AskUserQuestion` to identify the specific concern:

```javascript
AskUserQuestion({
  questions: [{
    question: "Which item do you need help with?",
    header: "Help",
    multiSelect: false,
    options: [
      {
        label: "Clean commit history",
        description: "Help squashing or rebasing commits"
      },
      {
        label: "Removing sensitive data",
        description: "Help finding and removing secrets"
      },
      {
        label: "Running tests",
        description: "Help running the test suite"
      },
      {
        label: "Adding DCO sign-off",
        description: "Help adding sign-off to commits"
      }
    ]
  }]
})
```

Provide targeted help based on selection, then return to Phase 2 checklist confirmation.

### If user selects "Yes, all items complete":

Continue to Phase 3.

---

## Phase 3: Automated Checks

### Check 3A: Secrets Scanning

Determine the upstream remote name (either `loa` or `upstream`):

```bash
UPSTREAM_REMOTE=$(git remote -v | grep -E "^(loa|upstream)\s.*0xHoneyJar/loa" | head -1 | cut -f1)
```

Scan for common secrets patterns in the diff between upstream and HEAD:

```bash
# Get files changed since upstream/main
CHANGED_FILES=$(git diff ${UPSTREAM_REMOTE}/main...HEAD --name-only 2>/dev/null)

# If no upstream/main, try to use loa/main or just check recent commits
if [ -z "$CHANGED_FILES" ]; then
    CHANGED_FILES=$(git diff HEAD~10...HEAD --name-only 2>/dev/null)
fi

# Define secrets patterns
SECRETS_PATTERN='(sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|(password|secret|api_key|apikey|token|credential)\s*[=:]\s*["\x27][^"\x27]{8,}["\x27])'

# Scan changed files for secrets
SECRETS_FOUND=$(echo "$CHANGED_FILES" | xargs grep -lE "$SECRETS_PATTERN" 2>/dev/null)
```

**If secrets are found:**

Display warning and use `AskUserQuestion`:

```
## ⚠️ Potential Secrets Detected

The following files may contain sensitive data:

{SECRETS_FOUND - list each file}

### Common Issues

- API keys left in code or config files
- Test credentials not using environment variables
- Private keys accidentally committed

### How to Fix

1. Remove the sensitive data from the files
2. If already committed, consider:
   - `git commit --amend` (for last commit)
   - `git rebase -i` to edit older commits
   - Using `git filter-branch` or BFG Repo-Cleaner for history
3. Use environment variables instead of hardcoded secrets

**Note**: This is a basic scan and may have false positives.
Test fixtures with fake credentials are usually fine.
```

```javascript
AskUserQuestion({
  questions: [{
    question: "How would you like to proceed?",
    header: "Secrets",
    multiSelect: false,
    options: [
      {
        label: "These are false positives",
        description: "The detected patterns are test data or intentional"
      },
      {
        label: "I'll fix them now",
        description: "Stop and let me remove the secrets"
      }
    ]
  }]
})
```

- If "These are false positives" → Log acknowledgment and continue
- If "I'll fix them now" → **STOP** and let user address

**If no secrets found:**

Display:
```
✓ Secrets scan: No potential secrets detected
```

Continue to Check 3B.

### Check 3B: DCO Sign-off Verification

```bash
UPSTREAM_REMOTE=$(git remote -v | grep -E "^(loa|upstream)\s.*0xHoneyJar/loa" | head -1 | cut -f1)
DCO_MISSING=$(git log ${UPSTREAM_REMOTE}/main...HEAD --format='%H %s' 2>/dev/null | while read hash msg; do
    if ! git log -1 --format='%B' "$hash" | grep -q 'Signed-off-by:'; then
        echo "$hash"
    fi
done)
```

**If DCO sign-off is missing from any commits:**

Display warning:

```
## ⚠️ DCO Sign-off Missing

Some commits are missing the Developer Certificate of Origin sign-off.

### Why DCO?

The DCO is a lightweight way to certify that you wrote or have the right
to submit the code you're contributing. It's required for Loa contributions.

### How to Fix

**For the most recent commit:**
```bash
git commit --amend -s
```

**For multiple commits:**
```bash
# Interactive rebase to add sign-off to each commit
git rebase -i ${UPSTREAM_REMOTE}/main

# In the editor, change 'pick' to 'edit' for commits needing sign-off
# For each commit, run:
git commit --amend -s
git rebase --continue
```

**For all future commits (recommended):**
Configure git to always sign-off:
```bash
# Add alias for signed commits
git config --global alias.cs 'commit -s'
```

### Sign-off Format

```
Signed-off-by: Your Name <your.email@example.com>
```

The name and email should match your git config:
```bash
git config user.name
git config user.email
```
```

```javascript
AskUserQuestion({
  questions: [{
    question: "DCO sign-off is recommended. How would you like to proceed?",
    header: "DCO",
    multiSelect: false,
    options: [
      {
        label: "Continue anyway",
        description: "Proceed without DCO (maintainers may request it later)"
      },
      {
        label: "I'll add sign-off now",
        description: "Stop and let me add DCO sign-off to my commits"
      }
    ]
  }]
})
```

- If "Continue anyway" → Log and continue with warning
- If "I'll add sign-off now" → **STOP**

**If DCO sign-off is present:**

Display:
```
✓ DCO sign-off: Present in all commits
```

### Automated Checks Complete

Display summary:

```
## Automated Checks Complete

✓ Secrets scan: {Passed/Acknowledged}
✓ DCO sign-off: {Present/Acknowledged}

Ready to create your pull request!
```

Continue to Phase 4.

---

## Phase 4: PR Creation

### Step 1: Gather PR Information

Use `AskUserQuestion` to get PR title:

```javascript
AskUserQuestion({
  questions: [{
    question: "What is the title for your pull request? (Be concise and descriptive)",
    header: "PR Title",
    multiSelect: false,
    options: [
      {
        label: "Enter title",
        description: "I'll provide a custom PR title"
      }
    ]
  }]
})
```

The user will provide the title via free text (selecting "Other").

Then get PR description:

```javascript
AskUserQuestion({
  questions: [{
    question: "Briefly describe your changes. What does this PR do and why?",
    header: "Description",
    multiSelect: false,
    options: [
      {
        label: "Enter description",
        description: "I'll provide a custom description"
      }
    ]
  }]
})
```

### Step 2: Confirm PR Details

Display PR preview:

```
## Pull Request Preview

**Target**: 0xHoneyJar/loa:main
**Source**: {your-branch}

### Title
{user_provided_title}

### Description
{user_provided_description}

### Checklist (auto-included)
- [x] Commits are clean and focused
- [x] No sensitive data in commits
- [x] DCO sign-off present (or acknowledged)

---
🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

```javascript
AskUserQuestion({
  questions: [{
    question: "Does this look correct?",
    header: "Confirm",
    multiSelect: false,
    options: [
      {
        label: "Create PR",
        description: "Submit this pull request to 0xHoneyJar/loa"
      },
      {
        label: "Edit details",
        description: "Let me change the title or description"
      },
      {
        label: "Cancel",
        description: "Don't create the PR right now"
      }
    ]
  }]
})
```

- If "Edit details" → Return to Step 1
- If "Cancel" → **STOP** with message "PR creation cancelled."

### Step 3: Create the PR

Determine the upstream remote name:
```bash
UPSTREAM_REMOTE=$(git remote -v | grep -E "^(loa|upstream)\s.*0xHoneyJar/loa" | head -1 | cut -f1)
```

First, ensure branch is pushed to origin:
```bash
git push -u origin $(git branch --show-current)
```

**Option A: Using GitHub MCP (preferred)**

Use `mcp__github__create_pull_request`:

```javascript
mcp__github__create_pull_request({
  owner: "0xHoneyJar",
  repo: "loa",
  title: "{user_provided_title}",
  head: "{user_github_username}:{branch_name}",
  base: "main",
  body: `## Summary

{user_provided_description}

## Checklist

- [x] Commits are clean and focused
- [x] No sensitive data in commits
- [x] DCO sign-off present

---
🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>`
})
```

**Option B: Using gh CLI (fallback)**

```bash
gh pr create \
  --repo 0xHoneyJar/loa \
  --base main \
  --title "{user_provided_title}" \
  --body "$(cat <<'EOF'
## Summary

{user_provided_description}

## Checklist

- [x] Commits are clean and focused
- [x] No sensitive data in commits
- [x] DCO sign-off present

---
🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

### Step 4: Success Message

If PR creation succeeds:

```
## 🎉 Contribution Submitted!

Your pull request has been created successfully.

### Pull Request URL
{PR_URL}

### What Happens Next

1. **CI Checks**: Automated tests will run on your PR
2. **Review**: Loa maintainers will review your changes
3. **Feedback**: You may receive comments or change requests
4. **Merge**: Once approved, your contribution will be merged!

### Tips for a Smooth Review

- Respond promptly to reviewer feedback
- Keep changes focused on the PR scope
- Be open to suggestions and alternative approaches

### Thank You!

Your contribution helps make Loa better for everyone.
We appreciate your time and effort! 🙏
```

### Error Handling

If PR creation fails, display:

```
## PR Creation Failed

An error occurred while creating your pull request.

### Error Details
{error_message}

### Manual PR Creation

You can create the PR manually:

1. Go to: https://github.com/0xHoneyJar/loa/compare/main...{your-username}:{branch}
2. Click "Create pull request"
3. Copy this body:

---
## Summary

{user_provided_description}

## Checklist

- [x] Commits are clean and focused
- [x] No sensitive data in commits
- [x] DCO sign-off present

---
🤖 Generated with [Claude Code](https://claude.com/claude-code)
---

### Common Issues

- **Fork not found**: Ensure you've forked 0xHoneyJar/loa to your account
- **Branch not pushed**: Run `git push -u origin {branch}`
- **Permission denied**: Check your GitHub authentication (`gh auth status`)
```

---

## Exceptions and Notes

### Exception: Running from Loa Repository Directly

If the user is working directly in the `0xHoneyJar/loa` repository (not a fork):

```bash
ORIGIN_URL=$(git remote get-url origin 2>/dev/null)
if echo "$ORIGIN_URL" | grep -qE "0xHoneyJar/loa"; then
    # User is working directly in upstream
    # Skip upstream remote check, PR will be branch-to-main
fi
```

In this case:
- Skip Check 3 (upstream remote)
- Create PR from branch to main within same repo
- Use `--head {branch}` instead of `--head {user}:{branch}`

### Analytics (THJ Users Only)

After successful PR creation, update analytics if user is THJ:

```bash
USER_TYPE=$(cat .loa-setup-complete 2>/dev/null | grep -o '"user_type": *"[^"]*"' | cut -d'"' -f4)
if [ "$USER_TYPE" = "thj" ]; then
    # Check if analytics file exists
    if [ -f "loa-grimoire/analytics/usage.json" ]; then
        # Increment commands_executed in analytics
        # Read current value
        CURRENT_COMMANDS=$(cat loa-grimoire/analytics/usage.json | grep -o '"commands_executed": *[0-9]*' | grep -o '[0-9]*')
        if [ -n "$CURRENT_COMMANDS" ]; then
            NEW_COMMANDS=$((CURRENT_COMMANDS + 1))
            # This is non-blocking - failures don't stop the flow
            # Analytics update would be done by the agent reading this instruction
        fi
    fi
fi
```

**Note**: Analytics updates are non-blocking. If the analytics file is missing or cannot be updated, the `/contribute` command should still complete successfully. OSS users (those without `user_type: "thj"`) skip analytics entirely.

### This Command Skips Git Safety Warnings

The `/contribute` command is explicitly listed as an exception in the Git Safety Protocol (CLAUDE.md). This command handles its own safeguards for intentional upstream contributions, so the normal push/PR warnings are bypassed.
