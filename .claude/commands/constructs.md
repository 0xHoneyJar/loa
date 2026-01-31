---
name: "constructs"
version: "1.0.0"
description: |
  Browse, select, and install packs from the Loa Constructs Registry.
  Multi-select UI for composable pack installation.

agent: "browsing-constructs"
agent_path: ".claude/skills/browsing-constructs"

command_type: "wizard"

arguments:
  - name: "action"
    description: "Action to perform: browse, install, list, update, auth"
    required: false
    default: "browse"
  - name: "target"
    description: "Pack slug for install/uninstall, or 'setup' for auth"
    required: false

integrations:
  - service: "loa-constructs-api"
    description: "Registry API for pack discovery"
    required: true

pre_flight:
  - check: "api_reachable"
    description: "Registry API is accessible"
    required: false  # Can work offline with cache

outputs:
  - path: ".claude/constructs/packs/"
    type: "directory"
    description: "Installed packs location"
  - path: ".constructs-meta.json"
    type: "file"
    description: "Installation metadata"

mode:
  default: "foreground"
  allow_background: false
---

# Constructs

## Purpose

Browse and install packs from the Loa Constructs Registry with a multi-select UI. Enables composable skill installation per-repo.

## Invocation

```
/constructs                    # Browse and install (default)
/constructs browse             # Browse available packs
/constructs install <pack>     # Install specific pack
/constructs list               # List installed packs
/constructs update             # Check for updates
/constructs uninstall <pack>   # Remove a pack
```

## Prerequisites

- `LOA_CONSTRUCTS_API_KEY` environment variable (for premium packs)
- Or `~/.loa/credentials.json` with API key
- Network access to registry (or cached pack data)

## Workflow

### Action: browse (default)

Interactive pack selection with multi-select UI.

#### Phase 1: Fetch Available Packs

```bash
# Fetch packs from registry
packs=$(.claude/scripts/constructs-browse.sh list --json)
```

Returns JSON array:
```json
[
  {
    "slug": "observer",
    "name": "Observer",
    "description": "User truth capture",
    "skills_count": 6,
    "tier": "free",
    "icon": "🔮"
  },
  {
    "slug": "crucible", 
    "name": "Crucible",
    "description": "Validation & testing",
    "skills_count": 5,
    "tier": "free",
    "icon": "⚗️"
  }
]
```

#### Phase 2: Display Multi-Select UI

Use AskUserQuestion with multiSelect to allow pack selection:

```json
{
  "questions": [{
    "question": "Select packs to install:",
    "header": "Packs",
    "multiSelect": true,
    "options": [
      {
        "label": "🔮 Observer (6 skills)",
        "description": "User truth capture - interviews, personas, journey mapping"
      },
      {
        "label": "⚗️ Crucible (5 skills)", 
        "description": "Validation & testing - test plans, quality gates"
      },
      {
        "label": "🎨 Artisan (10 skills)",
        "description": "Brand/UI craftsmanship - design systems, components"
      }
    ]
  }]
}
```

#### Phase 3: Install Selected Packs

For each selected pack:

```bash
.claude/scripts/constructs-install.sh pack <slug>
```

#### Phase 4: Report Results

Display installation summary:
- ✅ Installed packs
- Skills loaded count
- Commands available
- Any errors encountered

### Action: install <pack>

Direct installation without UI:

```bash
.claude/scripts/constructs-install.sh pack <pack>
```

### Action: list

Show installed packs:

```bash
.claude/scripts/constructs-loader.sh list
```

### Action: update

Check for newer versions:

```bash
.claude/scripts/constructs-loader.sh check-updates
```

### Action: uninstall <pack>

Remove installed pack:

```bash
.claude/scripts/constructs-install.sh uninstall pack <pack>
```

### Action: auth

Check or set up authentication for premium packs.

```bash
# Check authentication status
.claude/scripts/constructs-auth.sh status

# Set up API key
.claude/scripts/constructs-auth.sh setup <api_key>

# Validate current key
.claude/scripts/constructs-auth.sh validate

# Remove credentials
.claude/scripts/constructs-auth.sh clear
```

**Getting an API key:**
1. Visit https://loa-constructs.dev/account
2. Sign in or create an account
3. Generate an API key
4. Run `/constructs auth setup` and paste the key

**Alternative methods:**
- Environment variable: `export LOA_CONSTRUCTS_API_KEY=sk_...`
- Credentials file: `~/.loa/credentials.json`

## Pack Selection Guidelines

When presenting packs, include:

1. **Icon + Name** - Visual identifier
2. **Skill count** - e.g., "(6 skills)"
3. **Description** - One-line summary
4. **Tier indicator** - Free vs Pro badge

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| "No API key" | Missing credentials | Set `LOA_CONSTRUCTS_API_KEY` or create `~/.loa/credentials.json` |
| "Pack not found" | Invalid slug | Check available packs with `/constructs browse` |
| "Network error" | API unreachable | Check connection; cached packs still work |
| "License expired" | Subscription lapsed | Renew at constructs registry |

## Per-Repo Configuration

Installed packs are stored in `.claude/constructs/packs/` (gitignored).

Each repo can have different packs:
- Project A: Observer + Crucible
- Project B: Artisan only
- Project C: All packs

## Related

- `constructs-install.sh` - Installation script
- `constructs-loader.sh` - Skill loading
- `constructs-lib.sh` - Shared utilities
