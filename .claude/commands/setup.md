---
name: "setup"
version: "1.1.0"
description: |
  First-time Loa setup wizard for onboarding and project initialization.
  Detects user type, configures MCP integrations, initializes analytics.

command_type: "wizard"

arguments: []

pre_flight:
  - check: "file_not_exists"
    path: ".loa-setup-complete"
    error: "Setup already completed. Run /config to modify MCP settings."

mcp_source: ".claude/mcp-registry.yaml"

outputs:
  - path: ".loa-setup-complete"
    type: "file"
    description: "Setup marker with user type and configuration"
  - path: "loa-grimoire/analytics/usage.json"
    type: "file"
    description: "Analytics file (THJ users only)"

mode:
  default: "foreground"
  allow_background: false
---

# Setup

## Purpose

First-time setup wizard that initializes Loa for a new project. Determines user type (THJ vs OSS), configures MCP integrations, and initializes analytics tracking.

## Invocation

```
/setup
```

## Workflow

### Phase 0: User Type Detection

Ask the user to identify their pathway:
- **THJ Developer**: Full analytics, MCP configuration, `/feedback` and `/config` access
- **OSS User**: Streamlined setup, no analytics, documentation pointers

### Phase 0.5: Template Detection

Detect if this repository is a fork/template of Loa:

1. Check origin remote URL for known templates
2. Check upstream/loa remote for template references
3. Query GitHub API for fork relationship (if `gh` CLI available)

Store detection result for Git Safety features.

### Phase 0.6: Repository Mode Detection

Detect if this is a greenfield or established codebase:

<repo_mode_detection>

#### Step 1: Calculate Establishment Score

```bash
ESTABLISHED_SCORE=0

# Git history depth (more commits = more established)
COMMIT_COUNT=$(git rev-list --count HEAD 2>/dev/null || echo 0)
[ "$COMMIT_COUNT" -gt 100 ] && ((ESTABLISHED_SCORE+=2))

# Source file count
SOURCE_COUNT=$(find . -name "*.ts" -o -name "*.js" -o -name "*.py" -o -name "*.go" -o -name "*.java" 2>/dev/null | grep -v node_modules | head -100 | wc -l)
[ "$SOURCE_COUNT" -gt 20 ] && ((ESTABLISHED_SCORE+=2))

# Has test directory
[ -d "test" ] || [ -d "tests" ] || [ -d "__tests__" ] || [ -d "spec" ] && ((ESTABLISHED_SCORE+=1))

# Has substantial README
[ -f "README.md" ] && [ $(wc -l < README.md) -gt 50 ] && ((ESTABLISHED_SCORE+=1))

# Has existing documentation
DOC_COUNT=$(find . -name "*.md" -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null | wc -l)
[ "$DOC_COUNT" -gt 5 ] && ((ESTABLISHED_SCORE+=1))

# Has CI/CD configuration
[ -f ".github/workflows/"* ] || [ -f ".gitlab-ci.yml" ] || [ -f "Jenkinsfile" ] && ((ESTABLISHED_SCORE+=1))

if [ $ESTABLISHED_SCORE -ge 4 ]; then
  REPO_MODE="established"
  echo "Detected: Established codebase (score: $ESTABLISHED_SCORE)"
else
  REPO_MODE="greenfield"
  echo "Detected: Greenfield project (score: $ESTABLISHED_SCORE)"
fi
```

#### Step 2: Confirm with User

Ask using AskUserQuestion:

**Question**: "This appears to be an **[established/greenfield]** repository (score: X/8). Is this correct?"

Options:
- "Yes, this is correct"
- "No, this is a greenfield project" (if detected as established)
- "No, this is an established codebase" (if detected as greenfield)

#### Step 3: Configure Mode

```bash
mkdir -p .claude/config

# Create or update loa-config.yaml
cat >> .claude/config/loa-config.yaml << EOF
repo_mode: $REPO_MODE
detected_at: $(date -Iseconds)
establishment_score: $ESTABLISHED_SCORE
EOF

# Set freedom level for established repos
if [ "$REPO_MODE" = "established" ]; then
  echo "freedom_level: low" >> .claude/config/loa-config.yaml
fi
```

#### Step 4: Beads Mode Selection (Established Repos Only)

If `repo_mode: established`, ask about Beads visibility:

**Question**: "How should Beads track issues in this established repo?"

Options:
- "Team mode (Recommended)" - Commits `.beads/` to repository, visible to all
- "Stealth mode" - Local only, not committed, for solo exploration

```bash
if [ "$BEADS_MODE" = "stealth" ]; then
  echo ".beads/" >> .gitignore
  echo "beads_mode: stealth" >> .claude/config/loa-config.yaml
else
  echo "beads_mode: team" >> .claude/config/loa-config.yaml
fi
```

</repo_mode_detection>

### Phase 0.7: Beads Installation

Beads (`bd`) is a git-backed issue tracker that Loa uses for sprint task management. It enables dependency tracking, ready detection, and clean session handoffs.

#### Step 1: Check Current Status

```bash
.claude/scripts/beads/check-beads.sh
```

**Possible outcomes:**
- `READY` → Skip to Phase 1
- `NOT_INSTALLED` → Proceed to Step 2
- `NOT_INITIALIZED` → Skip to Step 3

#### Step 2: Install Beads (if needed)

**Explain to user:**
> Loa uses Beads for sprint task tracking. This provides:
> - **Dependency modeling**: Track which tasks block others
> - **Ready detection**: `bd ready` finds your next actionable work
> - **Session handoff**: Clean state persistence between sessions
>
> Beads is a lightweight CLI tool (~2MB) that stores data in `.beads/` within your project.

**Ask for confirmation using AskUserQuestion:**
- "Install Beads now? (Recommended)"
- "Skip for now (some features will be limited)"
- "I'll install manually later"

**If user confirms installation:**

```bash
.claude/scripts/beads/install-beads.sh
```

**If installation fails**, provide manual instructions:
> Installation failed. You can install manually:
> ```bash
> # Option 1: Install script
> curl -fsSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash
>
> # Option 2: Go install (if you have Go)
> go install github.com/steveyegge/beads/cmd/bd@latest
>
> # Option 3: Build from source
> git clone https://github.com/steveyegge/beads.git
> cd beads && go build -o bd ./cmd/bd && sudo mv bd /usr/local/bin/
> ```
> After installing, run `/setup` again.

**If user skips:**
> Note: Sprint task tracking will use markdown-only mode.
> You can install Beads later and run `/setup` again to enable full features.

#### Step 3: Initialize Beads Database (if needed)

```bash
[ -d ".beads" ] || bd init --quiet
```

#### Step 4: Verify Installation

```bash
.claude/scripts/beads/check-beads.sh
```

**If READY:**
> ✓ Beads installed and initialized successfully
> - Database: `.beads/beads.jsonl`
> - Run `bd --help` to explore commands

**Record in marker file:**
```json
"beads": {
  "installed": true,
  "version": "<output of bd --version>",
  "initialized_at": "ISO-8601 timestamp"
}
```

**If still not working:**
> ⚠ Beads setup incomplete. Sprint tracking will use fallback mode.
> Run `bd --version` to diagnose, or see: https://github.com/steveyegge/beads

### Phase 1A: THJ Developer Setup

1. Display welcome message with command overview
2. Show analytics notice (cannot be disabled)
3. Initialize `loa-grimoire/analytics/usage.json`
4. Offer MCP integration selection (multiSelect)
5. Provide setup instructions for selected MCPs
6. Create `.loa-setup-complete` marker

### Phase 1B: OSS User Setup

1. Display welcome message with documentation pointers
2. Create `.loa-setup-complete` marker (no analytics)
3. Point to GitHub issues for support

## Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| None | | |

## Outputs

| Path | Description |
|------|-------------|
| `.loa-setup-complete` | Marker file with user type and config |
| `loa-grimoire/analytics/usage.json` | Usage metrics (THJ only) |
| `loa-grimoire/analytics/summary.md` | Human-readable summary (THJ only) |

## User Type Differences

| Feature | THJ Developer | OSS User |
|---------|---------------|----------|
| Analytics | Full tracking | None |
| `/feedback` | Available | Unavailable |
| `/config` | Available | Unavailable |
| MCP Setup | Guided wizard | Manual |

## MCP Integrations

Available servers are defined in `.claude/mcp-registry.yaml`.

Use helper scripts to query the registry:
```bash
.claude/scripts/mcp-registry.sh list      # List all servers
.claude/scripts/mcp-registry.sh groups    # List server groups
.claude/scripts/mcp-registry.sh info <server>  # Get setup instructions
```

### Server Groups (THJ developers)

| Group | Description | Servers |
|-------|-------------|---------|
| essential | Recommended for all | linear, github |
| deployment | Production workflows | github, vercel |
| crypto | Blockchain projects | web3-stats, github |
| communication | Team communication | discord |
| productivity | Document tools | gdrive |

## Marker File Format

```json
{
  "completed_at": "ISO-8601 timestamp",
  "framework_version": "0.4.0",
  "user_type": "thj|oss",
  "mcp_servers": ["list", "of", "configured"],
  "git_user": "developer@example.com",
  "template_source": {
    "detected": true,
    "repo": "0xHoneyJar/loa",
    "detection_method": "origin_url",
    "detected_at": "ISO-8601 timestamp"
  },
  "repo_mode": {
    "mode": "greenfield|established",
    "establishment_score": 0-8,
    "freedom_level": "high|low",
    "detected_at": "ISO-8601 timestamp"
  },
  "beads": {
    "installed": true,
    "version": "1.0.0",
    "mode": "team|stealth",
    "initialized_at": "ISO-8601 timestamp"
  }
}
```

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| "Setup already completed" | `.loa-setup-complete` exists | Run `/config` to modify MCP settings |
| "Cannot determine user type" | User didn't respond | Re-run `/setup` and select an option |

## Next Step

**For Greenfield Projects:**
After setup: `/plan-and-analyze` to create Product Requirements Document

**For Established Codebases:**
After setup: `/adopt` to extract documentation from code

```
Setup complete for established codebase.

Recommended next step:
  /adopt

This will:
  - Extract documentation from actual code
  - Identify drift from existing documentation
  - Import tech debt to Beads
  - Establish Loa as source of truth
```
