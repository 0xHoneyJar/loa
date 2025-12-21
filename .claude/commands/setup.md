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

### Phase 0.6: Beads Installation

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
  "beads": {
    "installed": true,
    "version": "1.0.0",
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

After setup: `/plan-and-analyze` to create Product Requirements Document
