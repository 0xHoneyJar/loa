# Git Safety Protocol

This protocol prevents accidental pushes to the Loa upstream template repository. It is a **soft block** - users can always proceed after explicit confirmation.

## Known Template Repositories

- `github.com/0xHoneyJar/loa`
- `github.com/thj-dev/loa`

## Detection Layers

Detection uses a 4-layer approach with fallback behavior:

### Layer 1: Cached Detection

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

### Layer 2: Origin URL Check

```bash
ORIGIN_URL=$(git remote get-url origin 2>/dev/null)
if echo "$ORIGIN_URL" | grep -qE "(0xHoneyJar|thj-dev)/loa"; then
    DETECTION_METHOD="Origin URL match"
    IS_TEMPLATE="true"
fi
```

### Layer 3: Upstream Remote Check (catches forks whose upstream is the template)

```bash
if git remote -v | grep -E "^(upstream|loa)\s" | grep -qE "(0xHoneyJar|thj-dev)/loa"; then
    DETECTION_METHOD="Upstream remote match"
    IS_TEMPLATE="true"
fi
```

### Layer 4: GitHub API Check (when local detection is inconclusive)

```bash
if command -v gh &>/dev/null; then
    PARENT=$(gh repo view --json parent -q '.parent.nameWithOwner' 2>/dev/null)
    if echo "$PARENT" | grep -qE "(0xHoneyJar|thj-dev)/loa"; then
        DETECTION_METHOD="GitHub API fork check"
        IS_TEMPLATE="true"
    fi
fi
```

## Detection Procedure

Before executing ANY `git push`, `gh pr create`, or GitHub MCP PR creation:

1. Identify the target remote (`git remote -v`) and its URL.
2. If the URL matches `(0xHoneyJar|thj-dev)/loa` (or a layer above says template), show the warning below with every placeholder filled — never proceed without it.
3. Ask via `AskUserQuestion` (below); never auto-proceed, and free-text "yes" is not a confirmation.
4. "Proceed anyway" → execute the operation once; "Cancel" → stop; "Fix remotes" → show the remediation guide, then stop.

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

## Edge Cases and Exceptions

- Show the warning even when the user explicitly asked for the push, and again for the same remote later in the session — there is no global disable, only per-operation confirmation.
- `/contribute` skips this check; it has its own safeguards.
- `.loa-setup-complete` with `template_source.detected: false` skips the warning; a missing file does NOT disable the checks.
- Remotes that match no known template proceed without a warning.
- Commands use `2>/dev/null`; Layer 4 is skipped without `gh` or on network failure, falling back to local detection.
