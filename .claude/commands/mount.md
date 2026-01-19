---
name: "mount"
version: "1.0.0"
description: |
  Install Loa framework onto an existing repository. Prepares the System Zone,
  initializes State Zone structure, and sets up integrity verification.
  "The Loa mounts the repository, preparing to ride."

command_type: "wizard"

arguments:
  - name: "stealth"
    type: "flag"
    required: false
    description: "Don't commit framework files (local only)"
  - name: "skip-beads"
    type: "flag"
    required: false
    description: "Don't initialize Beads CLI"
  - name: "branch"
    type: "string"
    required: false
    default: "main"
    description: "Loa branch to use (default: main)"

pre_flight:
  - check: "command_exists"
    command: "git"
    error: "Git is required. Please install git."
  - check: "directory_exists"
    path: ".git"
    error: "Not a git repository. Initialize with 'git init' first."
  - check: "command_exists"
    command: "jq"
    error: "jq is required. Install with: brew install jq / apt install jq"

outputs:
  - path: ".loa-version.json"
    type: "file"
    description: "Version manifest and schema tracking"
  - path: ".loa.config.yaml"
    type: "file"
    description: "User configuration (never overwritten)"
  - path: ".claude/"
    type: "directory"
    description: "System Zone (framework-managed)"
  - path: "grimoires/loa/"
    type: "directory"
    description: "State Zone (project memory)"
  - path: "grimoires/loa/NOTES.md"
    type: "file"
    description: "Structured agentic memory"
  - path: ".beads/"
    type: "directory"
    description: "Task graph (if Beads installed)"

mode:
  default: "foreground"
  allow_background: false
---

# /mount - Mount Loa Framework onto Repository

> *"The Loa mounts the repository, preparing to ride through its code."*

## Purpose

Install the Loa framework onto an existing repository, setting up the three-zone architecture and preparing for codebase analysis.

## Invocation

```
/mount
/mount --stealth
/mount --branch feature-branch
```

## What It Does

1. **Installs System Zone** (`.claude/`) - Framework skills, commands, protocols
2. **Initializes State Zone** (`grimoires/loa/`) - Project memory structure
3. **Configures Beads** (`.beads/`) - Task graph (if available)
4. **Generates checksums** - Anti-tamper protection
5. **Creates config** (`.loa.config.yaml`) - User preferences

## Zone Structure Created

```
{repo}/
├── .claude/              ← System Zone (framework-managed)
│   ├── commands/
│   ├── skills/
│   ├── protocols/
│   ├── scripts/
│   ├── checksums.json
│   └── overrides/        ← User customizations (preserved)
├── .loa-version.json     ← Version manifest
├── .loa.config.yaml      ← User config (never overwritten)
├── grimoires/loa/         ← State Zone (project memory)
│   ├── NOTES.md          ← Structured agentic memory
│   ├── context/          ← User-provided context
│   └── a2a/trajectory/   ← Agent trajectory logs
└── .beads/               ← Task graph
```

## Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| `--stealth` | Add State Zone to .gitignore (local only) | No |
| `--skip-beads` | Don't initialize Beads CLI | No |
| `--branch <name>` | Use specific Loa branch (default: main) | No |

## Workflow

### Phase 1: Pre-Mount Checks

1. Verify this is a git repository
2. Check for existing mount (offer remount if found)
3. Verify dependencies (jq, yq)

### Phase 2: Configure Upstream

```bash
LOA_REMOTE_URL="https://github.com/0xHoneyJar/loa.git"
LOA_REMOTE_NAME="loa-upstream"

git remote add "$LOA_REMOTE_NAME" "$LOA_REMOTE_URL" 2>/dev/null || \
  git remote set-url "$LOA_REMOTE_NAME" "$LOA_REMOTE_URL"

git fetch "$LOA_REMOTE_NAME" "$LOA_BRANCH" --quiet
```

### Phase 3: Install System Zone

```bash
git checkout "$LOA_REMOTE_NAME/$LOA_BRANCH" -- .claude
```

### Phase 4: Initialize State Zone

Create directory structure:
- `grimoires/loa/context/` - User-provided context
- `grimoires/loa/reality/` - Code extraction results
- `grimoires/loa/legacy/` - Legacy doc inventory
- `grimoires/loa/a2a/trajectory/` - Agent reasoning logs

Initialize `grimoires/loa/NOTES.md` with structured memory template.

### Phase 5: Generate Checksums

Create `.claude/checksums.json` with SHA256 hashes of all System Zone files.

### Phase 6: Create Config

Create `.loa.config.yaml` if not exists (preserve if present).

### Phase 7: Initialize beads_rust (Optional)

If `br` CLI available and not `--skip-beads`:
```bash
br init --quiet
```

## Stealth Mode

If `--stealth` flag is provided:

```bash
for entry in "grimoires/loa/" ".beads/" ".loa-version.json" ".loa.config.yaml"; do
  grep -qxF "$entry" .gitignore 2>/dev/null || echo "$entry" >> .gitignore
done
```

## Post-Mount Output

```
╔═════════════════════════════════════════════════════════════════╗
║  ✓ Loa Successfully Mounted!                                    ║
╚═════════════════════════════════════════════════════════════════╝

Zone structure:
  📁 .claude/          → System Zone (framework-managed)
  📁 .claude/overrides → Your customizations (preserved)
  📁 grimoires/loa/     → State Zone (project memory)
  📄 grimoires/loa/NOTES.md → Structured agentic memory
  📁 .beads/           → Task graph

Next steps:
  1. Run 'claude' to start Claude Code
  2. Issue '/ride' to analyze this codebase
  3. Or '/plan-and-analyze' for greenfield development

⚠️ STRICT ENFORCEMENT: Direct edits to .claude/ will block execution.
   Use .claude/overrides/ for customizations.

The Loa has mounted. Issue '/ride' when ready.
```

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| "Not a git repository" | No `.git` directory | Run `git init` first |
| "jq is required" | Missing jq | Install jq |
| "Failed to checkout .claude/" | Network or permission issue | Check remote URL and auth |

## Relationship to /ride

| Command | Purpose | When to Use |
|---------|---------|-------------|
| `/mount` | Install framework | Once per repository |
| `/ride` | Analyze codebase | After mounting, or to re-analyze |

*"First the Loa mounts, then it rides."*

## Technical Details

The mount process can also be executed directly via shell:

```bash
curl -fsSL https://raw.githubusercontent.com/0xHoneyJar/loa/main/.claude/scripts/mount-loa.sh | bash
```

## Next Step

After mounting: `/ride` to analyze the codebase and generate grimoire artifacts
