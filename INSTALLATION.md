# Installation Guide

Loa can be installed in two ways: **mounting onto an existing repository** (recommended) or **cloning the template**.

## Prerequisites

### Required
- **Git** (required)
- **jq** (required) - JSON processor
- **yq** (required) - YAML processor
- **Claude Code** - Claude's official CLI

```bash
# macOS
brew install jq yq

# Ubuntu/Debian
sudo apt install jq
pip install yq  # or snap install yq

# Verify
jq --version
yq --version
```

### Optional Enhancements

#### ck (Semantic Code Search)

**What it does**: Enables semantic code search using embeddings, dramatically improving agent precision and context loading speed.

**Benefits**:
- **Semantic understanding**: Find code by meaning, not just keywords
- **80-90% faster**: Delta-indexed embeddings with high cache hit rate
- **Ghost Feature detection**: Automatically detect documented features missing from code
- **Shadow System detection**: Identify undocumented code requiring documentation

**Without ck**: All commands work normally using grep fallbacks. The integration is completely invisible to users.

**Installation**:

```bash
# Install ck via cargo (requires Rust toolchain)
cargo install ck-search

# Verify installation
ck --version

# Expected: ck 0.7.0 or higher
```

If you don't have Rust/cargo installed:

```bash
# macOS
brew install rust
cargo install ck-search

# Ubuntu/Debian
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
cargo install ck-search
```

**Note**: ck is optional. Loa works perfectly without it, using grep-based fallbacks.

## Method 1: Mount onto Existing Repository (Recommended)

Mount Loa onto any existing git repository. This is the **sidecar pattern** - Loa rides alongside your project.

### One-Line Install

```bash
curl -fsSL https://raw.githubusercontent.com/0xHoneyJar/loa/main/.claude/scripts/mount-loa.sh | bash
```

### Manual Install

```bash
# 1. Navigate to your project
cd your-existing-project

# 2. Add Loa remote
git remote add loa-upstream https://github.com/0xHoneyJar/loa.git
git fetch loa-upstream main

# 3. Pull System Zone only
git checkout loa-upstream/main -- .claude

# 4. Create State Zone (if not exists)
mkdir -p loa-grimoire/{context,discovery,a2a/trajectory} .beads

# 5. Initialize config
cp .claude/templates/.loa.config.yaml .loa.config.yaml  # or create manually

# 6. Start Claude Code
claude
```

### What Gets Installed

```
your-project/
├── .claude/                    # System Zone (framework-managed)
│   ├── skills/                 # 8 agent skills
│   ├── commands/               # Slash commands
│   ├── protocols/              # Framework protocols
│   ├── scripts/                # Helper scripts
│   └── overrides/              # Your customizations (preserved on updates)
├── loa-grimoire/               # State Zone (project memory)
│   ├── NOTES.md                # Structured agentic memory
│   ├── a2a/trajectory/         # Agent trajectory logs
│   └── ...                     # Your project docs
├── .beads/                     # Task graph (optional)
├── .loa-version.json           # Version manifest
└── .loa.config.yaml            # Your configuration
```

## Method 2: Clone Template

Best for new projects starting from scratch.

```bash
# Clone and rename
git clone https://github.com/0xHoneyJar/loa.git my-project
cd my-project

# Remove upstream history (optional)
rm -rf .git
git init
git add .
git commit -m "Initial commit from Loa template"

# Start Claude Code
claude
```

## Configuration

### .loa.config.yaml

User-owned configuration file. Framework updates never touch this.

```yaml
# Persistence mode
persistence_mode: standard  # or "stealth" for local-only

# Integrity enforcement (Projen-level)
integrity_enforcement: strict  # or "warn", "disabled"

# Drift resolution
drift_resolution: code  # or "docs", "ask"

# Structured memory
memory:
  notes_file: loa-grimoire/NOTES.md
  trajectory_dir: loa-grimoire/a2a/trajectory
  trajectory_retention_days: 30

# Evaluation-driven development
edd:
  enabled: true
  min_test_scenarios: 3
  trajectory_audit: true
```

### Stealth Mode

Run Loa without committing state files to your repo:

```yaml
persistence_mode: stealth
```

This adds `loa-grimoire/`, `.beads/`, `.loa-version.json`, and `.loa.config.yaml` to `.gitignore`.

## Updates

### Automatic Updates

```bash
.claude/scripts/update.sh
```

Or use the slash command:
```
/update
```

### What Happens During Updates

1. **Fetch**: Downloads upstream to staging directory
2. **Validate**: Checks YAML syntax, shell script validity
3. **Migrate**: Runs any pending schema migrations (blocking)
4. **Swap**: Atomic replacement of System Zone
5. **Restore**: Your `.claude/overrides/` are preserved

### Integrity Enforcement

If you accidentally edit `.claude/` files directly:

```bash
# Check integrity
.claude/scripts/check-loa.sh

# Force restore (resets .claude/ to upstream)
.claude/scripts/update.sh --force-restore
```

## Customization

### Overrides Directory

Place customizations in `.claude/overrides/` - they survive updates.

```
.claude/overrides/
├── skills/
│   └── implementing-tasks/
│       └── SKILL.md          # Your customized skill
└── commands/
    └── my-command.md         # Your custom command
```

### User Configuration

All user preferences go in `.loa.config.yaml` - never edit `.claude/` directly.

## Validation

Run the CI validation script:

```bash
.claude/scripts/check-loa.sh
```

Checks:
- Loa installation status
- System Zone integrity (sha256 checksums)
- Schema version
- Structured memory presence
- Configuration validity
- Zone structure

## Troubleshooting

### "yq: command not found"

```bash
# macOS
brew install yq

# Linux (Python yq)
pip install yq

# Linux (Go yq - recommended)
wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq
chmod +x /usr/local/bin/yq
```

### "jq: command not found"

```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt install jq
```

### Integrity Check Failures

If you see "SYSTEM ZONE INTEGRITY VIOLATION":

1. **Don't edit `.claude/` directly** - use `.claude/overrides/` instead
2. **Force restore**: `.claude/scripts/update.sh --force-restore`
3. **Check your overrides**: Move customizations to `.claude/overrides/`

### Merge Conflicts on Update

```bash
# Accept upstream for .claude/ files (recommended)
git checkout --theirs .claude/

# Keep your changes for loa-grimoire/
git checkout --ours loa-grimoire/
```

## HivemindOS Integration (THJ Users)

For THJ organization members with access to HivemindOS, Loa can integrate with organizational memory.

### Prerequisites

- HivemindOS repository cloned locally
- `HIVEMIND_PATH` environment variable set (optional but recommended)

### Setting Up Integration

```bash
# Option 1: Set environment variable (recommended)
export HIVEMIND_PATH="/path/to/hivemind-os"

# Add to your shell profile (~/.zshrc or ~/.bashrc):
echo 'export HIVEMIND_PATH="/path/to/hivemind-os"' >> ~/.zshrc
```

### During Setup

When you run `/setup`, Loa will detect HivemindOS availability:

```
✓ HivemindOS available (organizational memory)
  → Would you like to enable HivemindOS integration? [y/N]
```

If you accept, Loa will:
1. Merge hooks (HivemindOS hooks run first, then Loa hooks)
2. Use merged status line showing both contexts
3. Enable HivemindOS skills and database access

### Merged Status Line

When integrated, the status line shows both systems:

```
⬢ HIVEMINDOS 🔬LAB · ◆ BUILD · context · Opus
     │          │       │         │        │
     │          │       │         │        └── Model
     │          │       │         └── Loa context
     │          │       └── Loa frame (BUILD)
     │          └── HivemindOS database (Laboratory)
     └── HivemindOS branding
```

### Configuration

Integration state is stored in `.loa.config.yaml`:

```yaml
hivemind_integration: true
hivemind_path: "/path/to/hivemind-os"
integration:
  status_line_mode: merged  # merged | loa-only | hivemind-only
```

### Session State Coexistence

Two session files work together:
- `.claude/.session` - HivemindOS database state (Library, Laboratory, etc.)
- `.loa/.session` - Loa frame state (SEARCH, BUILD, TUNE)

### Installing Hooks to Target Project

When mounting Loa onto a target project with HivemindOS integration:

```bash
# From Loa directory
.claude/scripts/install-hooks.sh /path/to/target --integrated
```

This will:
- Copy hooks from both systems
- Use merged status line from HivemindOS
- Preserve existing hooks in target

## Next Steps

After installation:

```bash
# 1. Start Claude Code
claude

# 2. Run setup wizard
/setup

# 3. Begin workflow
/plan-and-analyze
```

See [README.md](README.md) for the complete workflow.
