---
name: "contribute"
version: "1.0.0"
description: |
  Create a standards-compliant PR to contribute improvements to Loa upstream.
  Includes pre-flight checks, secrets scanning, DCO verification, and PR creation.

command_type: "git"

arguments: []

pre_flight:
  - check: "command_succeeds"
    command: "git branch --show-current | grep -qvE '^(main|master)$'"
    error: |
      Cannot contribute from main branch.

      Please create a feature branch:
        git checkout -b feature/your-feature-name

      Then run /contribute again.

  - check: "command_succeeds"
    command: "test -z \"$(git status --porcelain)\""
    error: |
      Your working tree has uncommitted changes.

      Please commit or stash your changes first:
        git add . && git commit -s -m "your commit message"

      Then run /contribute again.

  - check: "command_succeeds"
    command: "git remote -v | grep -qE '^(upstream|loa).*0xHoneyJar/loa'"
    error: |
      Upstream remote not configured.

      Add the Loa repository as a remote:
        git remote add loa https://github.com/0xHoneyJar/loa.git
        git fetch loa

      Then run /contribute again.

outputs:
  - path: "GitHub PR"
    type: "external"
    description: "Pull request to 0xHoneyJar/loa"

mode:
  default: "foreground"
  allow_background: false

git_safety:
  bypass: true
  reason: "Command has its own safeguards for intentional upstream contributions"
---

# Contribute

## Purpose

Guide intentional contributions back to the Loa framework. Creates a standards-compliant pull request with proper DCO sign-off, secrets scanning, and PR formatting.

## Invocation

```
/contribute
```

## Prerequisites

- Must be on a feature branch (not main/master)
- Working tree must be clean (no uncommitted changes)
- `loa` or `upstream` remote configured pointing to `0xHoneyJar/loa`

## Workflow

### Phase 1: Pre-flight Checks

1. Verify on feature branch
2. Verify working tree is clean
3. Verify upstream remote is configured

### Phase 2: Standards Checklist

Interactive confirmation of contribution standards:
- Clean commit history (focused, atomic commits)
- No sensitive data in commits
- Tests passing (if applicable)
- DCO sign-off present

### Phase 3: Automated Checks

#### Secrets Scanning
Scan for common secrets patterns in changed files:
- API keys (sk-, AKIA, ghp_, xox)
- Private keys (BEGIN PRIVATE KEY)
- Hardcoded credentials

If found, offer: "These are false positives" or "I'll fix them now"

#### DCO Sign-off Verification
Check all commits have `Signed-off-by:` line.

If missing, show how to add:
```bash
git commit --amend -s
```

### Phase 4: PR Creation

1. Prompt for PR title
2. Prompt for PR description
3. Preview PR details
4. Confirm and create PR

## Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| None | | |

## Outputs

| Path | Description |
|------|-------------|
| GitHub PR | Pull request to `0xHoneyJar/loa:main` |

## Contribution Standards Checklist

### Clean Commit History
- Commits are focused and atomic (one logical change per commit)
- Commit messages are clear and descriptive
- History is rebased/squashed if needed

### No Sensitive Data
- No API keys, tokens, or credentials
- No personal information in commits
- No internal URLs or proprietary information

### Tests (if applicable)
- Existing tests still pass
- New functionality has appropriate coverage

### DCO Sign-off
All commits include:
```
Signed-off-by: Your Name <email>
```

Add automatically with: `git commit -s`

## PR Format

```markdown
## Summary
{user_provided_description}

## Checklist
- [x] Commits are clean and focused
- [x] No sensitive data in commits
- [x] DCO sign-off present

---
Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| "Cannot contribute from main" | On main/master branch | Create feature branch |
| "Uncommitted changes" | Dirty working tree | Commit or stash changes |
| "Upstream remote not configured" | Missing loa/upstream remote | Add remote with `git remote add` |
| "Secrets detected" | Potential credentials in code | Review and remove or acknowledge |
| "DCO sign-off missing" | Commits without Signed-off-by | Amend commits with `-s` flag |
| "PR creation failed" | GitHub auth or network error | Manual PR creation instructions |

## Git Safety Exception

This command bypasses normal Git Safety warnings because it includes comprehensive safeguards for intentional upstream contributions:
- Branch verification
- Working tree check
- Upstream remote validation
- Secrets scanning
- DCO verification
- User confirmation at each step

## Analytics (THJ Only)

After successful PR creation, increments `commands_executed` in analytics (non-blocking).
