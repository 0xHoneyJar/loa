# Git Safety Protocol

This protocol prevents accidental pushes to the Loa upstream template repository. It is a **soft block** - users can always proceed after explicit confirmation.

## Known Template Repositories

- `github.com/0xHoneyJar/loa`
- `github.com/thj-dev/loa`

## Detection Layers

Detection uses a 4-layer approach with fallback behavior:

### Layer 1: Cached Detection (Fastest, < 100ms)

```bash
# Check .loa-setup-complete for cached template_source
if [ -f ".loa-setup-complete" ]; then
    CACHED=$(cat .loa-setup-complete 2>/dev/null | grep -o '"detected": *true')
    if [ -n "$CACHED" ]; then
        DETECTION_METHOD="Cached from setup"
        IS_TEMPLATE="true"
    fi
fi
```

**When to use**: Always check first. If `template_source.detected` is `true`, use this result.

### Layer 2: Origin URL Check (Local, < 1s)

```bash
ORIGIN_URL=$(git remote get-url origin 2>/dev/null)
if echo "$ORIGIN_URL" | grep -qE "(0xHoneyJar|thj-dev)/loa"; then
    DETECTION_METHOD="Origin URL match"
    IS_TEMPLATE="true"
fi
```

**When to use**: When cache miss or verifying cache.

### Layer 3: Upstream Remote Check (Local, < 1s)

```bash
if git remote -v | grep -E "^(upstream|loa)\s" | grep -qE "(0xHoneyJar|thj-dev)/loa"; then
    DETECTION_METHOD="Upstream remote match"
    IS_TEMPLATE="true"
fi
```

**When to use**: Catches forks where origin is user's repo but upstream points to template.

### Layer 4: GitHub API Check (Network, < 3s)

```bash
if command -v gh &>/dev/null; then
    PARENT=$(gh repo view --json parent -q '.parent.nameWithOwner' 2>/dev/null)
    if echo "$PARENT" | grep -qE "(0xHoneyJar|thj-dev)/loa"; then
        DETECTION_METHOD="GitHub API fork check"
        IS_TEMPLATE="true"
    fi
fi
```

**When to use**: When local detection is inconclusive, or for authoritative verification.

## Detection Procedure

Before executing ANY `git push`, `gh pr create`, or GitHub MCP PR creation:

```
START Detection Procedure
│
├─► Step 1: Identify target remote
│   Run: git remote -v
│   Extract the URL for the remote being pushed to
│
├─► Step 2: Check against known templates
│   Does URL contain "(0xHoneyJar|thj-dev)/loa"?
│   ├── YES → Template detected, proceed to Warning
│   └── NO  → Safe to proceed, skip to Step 6
│
├─► Step 3: Display warning message
│   Fill all placeholders with actual values
│   NEVER proceed without showing this warning
│
├─► Step 4: Wait for user response (MANDATORY)
│   Use AskUserQuestion tool
│   DO NOT auto-proceed under any circumstances
│
├─► Step 5: Handle user response
│   ├── "Proceed anyway" → Execute operation ONCE
│   ├── "Cancel"         → Stop, do nothing further
│   └── "Fix remotes"    → Display remediation, then stop
│
└─► Step 6: Execute or stop based on user choice
    END Detection Procedure
```

## Warning Message Template

```
⚠️  UPSTREAM TEMPLATE DETECTED

You appear to be pushing to the Loa template repository.

┌─────────────────────────────────────────────────────────────────┐
│  Detection Method: {DETECTION_METHOD}                           │
│  Target Remote:    {REMOTE_NAME} → {REMOTE_URL}                 │
│  Operation:        {OPERATION_TYPE}                             │
└─────────────────────────────────────────────────────────────────┘

⚠️  CONSEQUENCES OF PROCEEDING:
• Your code will be pushed to the PUBLIC Loa repository
• Your commits (including author info) will be visible publicly
• This may expose proprietary code, API keys, or personal data
• An unintentional PR may clutter the upstream project

Choose an option:
  1. [Proceed anyway]     - I understand the risks and want to continue
  2. [Cancel]             - Stop this operation
  3. [Fix my remotes]     - Show me how to fix my git configuration
```

**Placeholder Values**:
- `{DETECTION_METHOD}`: "Cached from setup", "Origin URL match", "Upstream remote match", "GitHub API fork check"
- `{REMOTE_NAME}`: The remote name (e.g., "origin", "upstream")
- `{REMOTE_URL}`: The full URL (e.g., "git@github.com:0xHoneyJar/loa.git")
- `{OPERATION_TYPE}`: The operation (e.g., "git push origin main", "Create PR to 0xHoneyJar/loa")

## User Confirmation Flow

**NEVER auto-proceed without explicit user confirmation.**

Use `AskUserQuestion` tool:

```javascript
AskUserQuestion({
  questions: [{
    question: "This appears to be a push to the Loa template repository. How would you like to proceed?",
    header: "Git Safety",
    multiSelect: false,
    options: [
      {
        label: "Proceed anyway",
        description: "I understand the risks and want to push to the upstream template"
      },
      {
        label: "Cancel",
        description: "Stop this operation, I'll reconsider"
      },
      {
        label: "Fix my remotes",
        description: "Show me how to configure my git remotes correctly"
      }
    ]
  }]
})
```

## Response Handling

| User Selection | Behavior |
|----------------|----------|
| "Proceed anyway" | Log confirmation, execute operation ONCE |
| "Cancel" | Stop immediately, inform user |
| "Fix my remotes" | Display remediation steps, then stop |

## Remediation Steps

When user selects "Fix my remotes":

```
📋 GIT REMOTE CONFIGURATION GUIDE

First, let's see your current setup:
  $ git remote -v

OPTION A: Change origin to your repo (recommended for new projects)
───────────────────────────────────────────────────────────────────
  git remote rename origin loa
  git remote add origin git@github.com:YOUR_ORG/YOUR_PROJECT.git
  git branch --set-upstream-to=origin/main main
  git push -u origin main

OPTION B: Just change the origin URL (if you have an existing repo)
───────────────────────────────────────────────────────────────────
  git remote set-url origin git@github.com:YOUR_ORG/YOUR_PROJECT.git
  git remote add loa https://github.com/0xHoneyJar/loa.git

VERIFY YOUR SETUP:
  $ git remote -v
  origin    git@github.com:YOUR_ORG/YOUR_PROJECT.git (fetch)
  origin    git@github.com:YOUR_ORG/YOUR_PROJECT.git (push)
  loa       https://github.com/0xHoneyJar/loa.git (fetch)
```

## Edge Cases

1. **User explicitly requests push**: Still show warning - they may not realize origin points to upstream
2. **User says "yes" without seeing options**: Use AskUserQuestion anyway - free-text is insufficient
3. **User asks to bypass all warnings**: Explain this is per-operation; no global disable
4. **Same session, same remote**: Show warning each time - don't assume previous confirmation applies
5. **`/contribute` command running**: Skip this check - it has its own safeguards

## Exceptions

- `/contribute` command handles upstream PRs with its own safeguards
- User explicit "proceed anyway" via AskUserQuestion allows the operation
- If `.loa-setup-complete` shows `template_source.detected: false`, skip warnings
- Operations targeting remotes that don't match known templates proceed without warning

## Error Handling

- All commands use `2>/dev/null` for graceful failures
- Layer 4 skipped if `gh` CLI not installed
- Network failures in Layer 4 fall back to local detection
- Missing `.loa-setup-complete` does NOT disable safety checks
