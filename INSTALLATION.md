# Installation Guide

Loa can be installed in three ways: **submodule mode** (default, recommended), **cloning the template** (new projects), or **vendored mode** (legacy).

**Time to first command**: ~2 minutes (one-liner install) | ~5 minutes (manual install with optional tools)

## Contents

- [Prerequisites](#prerequisites)
- [Method 1: Submodule Mode](#method-1-submodule-mode-default) (recommended - adds Loa as git submodule)
- [Method 2: Clone Template](#method-2-clone-template) (start a new project from scratch using loa)
- [Method 3: Vendored Mode](#method-3-vendored-mode-legacy) (legacy - copies files into .claude/)
- [Migrating from Vendored to Submodule](#migrating-from-vendored-to-submodule)
- [Verify Installation](#verify-installation)
- [Post-Install Enhancements](#post-install-enhancements) (optional tools that extend Loa)
- [Ownership Model](#ownership-model-v1150)
- [Configuration](#configuration)
- [Updates](#updates)
- [Customization](#customization)
- [Validation](#validation)
- [Troubleshooting](#troubleshooting)
- [Uninstalling Loa](#uninstalling-loa)
- [Loa Constructs (Commercial Skills)](#loa-constructs-commercial-skills)
- [Frictionless Permissions](#frictionless-permissions)

## Prerequisites

### Required
- **Claude Code** - Claude's official CLI ([install guide](https://docs.anthropic.com/en/docs/claude-code/overview))
- **Git** (required)
- **jq** (required) - JSON processor
- **yq v4+** (required) - YAML processor ([mikefarah/yq](https://github.com/mikefarah/yq), NOT the Python yq)

```bash
# Claude Code
npm install -g @anthropic-ai/claude-code

# macOS
brew install jq yq

# Ubuntu/Debian
sudo apt install jq
# yq — MUST be mikefarah/yq v4+, NOT `pip install yq` (different tool, incompatible)
wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq && chmod +x /usr/local/bin/yq
# Or: sudo snap install yq

# Verify all prerequisites
claude --version
jq --version
yq --version   # Should show "mikefarah/yq"
git --version
```

## Choosing Your Installation Method

| Factor | Submodule (Default) | Clone Template | Vendored (Legacy) |
|--------|--------------------|-----------------|--------------------|
| **Best for** | Existing projects | New projects from scratch | No git submodule/symlink support |
| **Framework updates** | `git submodule update` or `/update-loa` | `git pull` from upstream | `/update-loa` (full copy) |
| **Tracked files added** | ~5 (submodule ref + config) | 800+ (full framework) | 800+ (full framework) |
| **Separation** | Clean — framework in `.loa/`, symlinks in `.claude/` | Mixed — framework files in your tree | Mixed — copied into `.claude/` |
| **Version pinning** | `cd .loa && git checkout v1.39.0` | Standard git tags | Manual update script |
| **CI/CD setup** | Needs `--recurse-submodules` | Nothing extra | Nothing extra |
| **Symlink support** | Required | Not needed | Not needed |
| **Disk footprint** | ~2 MB (shared .loa/) | Full repo clone | ~2 MB (copied) |
| **Recommended?** | Yes | Yes (new projects only) | Only if submodules unavailable |

**Our recommendation**: Use **Submodule Mode** for existing projects (Method 1) or **Clone Template** for brand new projects (Method 2). Vendored mode exists for environments without submodule/symlink support (rare).

## Method 1: Submodule Mode (Default)

Adds Loa as a git submodule at `.loa/`, with symlinks from `.claude/` into the submodule. This provides version isolation, easy updates, and clean separation of framework from project code.

### One-Line Install

```bash
curl -fsSL https://raw.githubusercontent.com/0xHoneyJar/loa/main/.claude/scripts/mount-loa.sh | bash
```

This automatically uses submodule mode. The installer handles git submodule setup, symlink creation, and configuration.

> **Security note**: Piping curl to bash executes remote code without prior inspection. This is standard practice for developer tools (Homebrew, Rust, nvm) but carries inherent supply-chain risk. For higher-assurance installs, download and inspect first:
> ```bash
> curl -fsSL https://raw.githubusercontent.com/0xHoneyJar/loa/main/.claude/scripts/mount-loa.sh -o mount-loa.sh
> less mount-loa.sh  # inspect the script
> bash mount-loa.sh  # run after review
> ```
> Or use the [manual install](#manual-install), [verify after install](#verify-installation), or pin to a release tag with `--tag v1.39.0`.

### Manual Install

```bash
# 1. Navigate to your project
cd your-existing-project

# 2. Add Loa as submodule
git submodule add -b main https://github.com/0xHoneyJar/loa.git .loa

# 3. Pin to a specific version (recommended)
cd .loa && git checkout v1.39.0 && cd ..

# 4. Run the submodule mount script
.loa/.claude/scripts/mount-submodule.sh --force

# 5. Start Claude Code
claude
```

### Pin to Specific Version

```bash
# Pin to tag
mount-loa.sh --tag v1.39.0

# Pin to specific commit
mount-loa.sh --ref abc1234
```

### What Gets Installed

```
your-project/
├── .loa/                       # Git submodule (Loa framework source)
│   └── .claude/                # Framework files (source of truth)
├── .claude/                    # Symlinks into .loa/.claude/
│   ├── skills/ -> ../.loa/.claude/skills/
│   ├── commands/ -> ../.loa/.claude/commands/
│   ├── scripts/ -> ../.loa/.claude/scripts/
│   ├── protocols/ -> ../.loa/.claude/protocols/
│   ├── hooks/ -> ../.loa/.claude/hooks/
│   └── overrides/              # Your customizations (NOT a symlink)
├── grimoires/loa/              # State Zone (project memory)
│   ├── NOTES.md                # Structured agentic memory
│   ├── a2a/trajectory/         # Agent trajectory logs
│   └── ...                     # Your project docs
├── .beads/                     # Task graph (optional)
├── .loa-version.json           # Version manifest
└── .loa.config.yaml            # Your configuration
```

> **Note**: `.claude/overrides/` is a real directory you own. Everything else in `.claude/` is a symlink to the submodule.

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

## Method 3: Vendored Mode (Legacy)

Copies framework files directly into `.claude/`. Use this only if your environment does not support git submodules or symlinks.

```bash
curl -fsSL https://raw.githubusercontent.com/0xHoneyJar/loa/main/.claude/scripts/mount-loa.sh | bash -s -- --vendored
```

Or manually:

```bash
mount-loa.sh --vendored
```

> **Note**: Vendored mode is maintained for backward compatibility. New installations should use submodule mode (the default).

## Migrating from Vendored to Submodule

If you have an existing vendored installation, migrate with one command:

```bash
# Preview migration (dry run - no changes)
mount-loa.sh --migrate-to-submodule

# Execute migration
mount-loa.sh --migrate-to-submodule --apply
```

The migration:
1. Classifies files as FRAMEWORK, USER_MODIFIED, or USER_OWNED
2. Creates a timestamped backup at `.claude.backup.{timestamp}/`
3. Removes vendored files and adds Loa as a submodule
4. Creates symlinks and restores user-owned files
5. Commits the migration

**Rollback**: `git checkout <pre-migration-commit>` restores the exact pre-migration state.

## Verify Installation

After any install method, verify everything is working:

```bash
# 1. Check that the files exist in your repo
ls .claude/ grimoires/loa/ .loa.config.yaml

# 2. Start Claude Code and run the health check
claude
# Then inside Claude Code (these are slash commands, not shell commands):
/loa doctor
```

A healthy system shows all green checks. Any issues include structured error codes (LOA-E001+) with fix instructions. If the health check fails, see [Troubleshooting](#troubleshooting).

> `/loa doctor` is a slash command typed inside the Claude Code interactive session, not a shell command. All `/` commands in this guide work the same way.

### Integrity Verification (Optional)

After installation, verify that framework files match the expected checksums from the pinned version:

```bash
# Compare local checksums against the release tag
cd .loa && git diff --stat HEAD  # Should show no changes if pinned correctly

# Verify the submodule commit matches the expected tag
cd .loa && git describe --tags --exact-match 2>/dev/null || echo "Not on a tagged release"

# For vendored installs: validate checksums file
cat .claude/checksums.json | jq '.files | length'  # Should match expected file count
```

If you used the one-line curl installer without `--tag`, you can verify what was installed by checking the git log of the submodule:

```bash
cd .loa && git log --oneline -1
```

## Post-Install Enhancements

These tools are **optional** — Loa works fully without them. Install them after Loa is mounted and verified. They are listed in order of recommendation.

### beads_rust (Task Graph) {#beads_rust-optional}

**What it does**: Persistent task graph tracking across sessions using SQLite + JSONL for git-friendly diffs.

**Benefits**:
- **Cross-session persistence**: Tasks survive context clears and session restarts
- **Dependency tracking**: Block tasks on others, track readiness
- **Sprint integration**: Tasks linked to sprint plans

**When you need it**: Required for autonomous/run mode (`/run sprint-N`). Without it, Loa tracks sprint state in markdown only and will prompt you about beads at workflow boundaries. For interactive use (`/plan`, `/build`, `/review`), everything works without beads.

**Installation** (requires Rust toolchain — see ck section below for Rust install):

```bash
# Install via cargo
cargo install beads_rust

# Verify installation
br --version

# Initialize in your project root (creates .beads/ directory)
br init
```

### ck (Semantic Code Search) {#ck-semantic-code-search}

**What it does**: Enables semantic code search using embeddings, improving agent precision and context loading speed.

**Without ck**: All commands work normally using grep fallbacks. The integration is invisible to users.

**Installation**:

```bash
# Install ck via cargo (requires Rust toolchain)
cargo install ck-search

# Verify installation — expected: ck 0.7.0 or higher
ck --version
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

### Memory Stack (Vector Database) {#memory-stack-optional}

**What it does**: SQLite vector database with [sentence-transformers](https://github.com/UKPLab/sentence-transformers) embeddings for mid-stream semantic memory recall.

**Without Memory Stack**: Loa works normally using `grimoires/loa/NOTES.md` for structured memory. Memory Stack adds semantic recall on top.

**Resource Requirements**:
> sentence-transformers requires ~2-3 GB disk (PyTorch + model weights) and ~500 MB RAM when embedding.

**Installation** (run these from your project root, after Loa is mounted):

```bash
# Run the setup wizard (available after Loa is installed)
.claude/scripts/memory-setup.sh

# Or manual setup
pip install sentence-transformers
mkdir -p .loa-state
```

**Configuration** (add to `.loa.config.yaml`):

```yaml
memory:
  pretooluse_hook:
    enabled: false  # Opt-in — set to true after verifying setup
```

### Flatline Protocol — NotebookLM Integration {#notebooklm-optional}

**What it does**: Enables Tier 2 knowledge retrieval from Google NotebookLM for the Flatline Protocol's multi-model adversarial review.

**Without NotebookLM**: Flatline Protocol works with local knowledge only (Tier 1). NotebookLM adds supplementary context for specialized domains.

**Prerequisites**: Python 3.8+, a Google account.

**Installation** (run from your project root, after Loa is mounted):

```bash
# Install patchright (browser automation)
pip install --user patchright

# Install browser binaries
patchright install chromium

# One-time authentication (opens browser for Google sign-in)
python3 .claude/skills/flatline-knowledge/resources/notebooklm-query.py --setup-auth
```

**Configuration** (add to `.loa.config.yaml`):

```yaml
flatline_protocol:
  enabled: true
  knowledge:
    notebooklm:
      enabled: true
      notebook_id: "your-notebook-id"  # Optional: from notebooklm.google.com URL
```

## Ownership Model (v1.15.0)

Loa uses a **Projen-style ownership model** where framework-managed files are clearly separated from user-owned files. This prevents conflicts during updates and makes ownership explicit.

### File Ownership Types

| Type | Owner | Updates | How to Identify |
|------|-------|---------|-----------------|
| **Framework-managed** | Loa | Auto-updated | Has `@loa-managed` marker or `loa-` prefix |
| **User-owned** | You | Never touched | No marker, no `loa-` prefix |
| **Override** | You | Preserved | In `.claude/overrides/` |

### Namespace Separation

Framework files use the `loa-` prefix namespace to avoid collisions with user content:

```
.claude/skills/
├── loa-implementing-tasks/    # Framework skill (auto-updated)
├── loa-designing-architecture/  # Framework skill (auto-updated)
├── my-custom-skill/           # Your skill (never touched)
└── team-review-process/       # Your skill (never touched)

.claude/commands/
├── loa-implement.md           # Framework command (auto-updated)
├── loa-architect.md           # Framework command (auto-updated)
├── my-deploy.md               # Your command (never touched)
└── team-standup.md            # Your command (never touched)
```

**Why `loa-` prefix?** Claude Code only scans `.claude/skills/` - there's no support for nested directories like `.claude/loa/skills/`. The prefix provides logical separation while ensuring all skills are discovered.

### CLAUDE.md Import Pattern

Framework instructions are loaded via Claude Code's `@` import syntax:

```markdown
@.claude/loa/CLAUDE.loa.md

# Project-Specific Instructions

Your customizations here take precedence over imported content.
```

**How it works**:
1. Claude Code loads `.claude/loa/CLAUDE.loa.md` first (framework instructions)
2. Then loads the rest of `CLAUDE.md` (your project instructions)
3. Your instructions **take precedence** over framework defaults

**File locations**:
- `.claude/loa/CLAUDE.loa.md` - Framework-managed (auto-updated)
- `CLAUDE.md` - User-owned (never modified by updates)

### Migration from Legacy Format

If you have an existing `CLAUDE.md` with `<!-- LOA:BEGIN -->` markers:

1. Remove the `<!-- LOA:BEGIN -->` ... `<!-- LOA:END -->` section
2. Add `@.claude/loa/CLAUDE.loa.md` at the top of your file
3. Keep your project-specific content after the import

**Before** (legacy):
```markdown
<!-- LOA:BEGIN - Framework instructions -->
[Framework content here]
<!-- LOA:END -->

<!-- PROJECT:BEGIN -->
Your content here
<!-- PROJECT:END -->
```

**After** (v1.15.0+):
```markdown
@.claude/loa/CLAUDE.loa.md

# Project-Specific Instructions
Your content here
```

### Pack Namespace Convention

Commercial packs from the Loa Constructs Registry use vendor prefixes:

```
.claude/skills/
├── loa-implementing-tasks/      # Core Loa (loa- prefix)
├── gtm-market-analyst/          # GTM Collective pack (gtm- prefix)
├── sec-threat-model/            # Security pack (sec- prefix)
└── my-custom-skill/             # Your skill (no prefix)
```

### Feature Gates

Optional framework features can be disabled to reduce context overhead:

```yaml
# .loa.config.yaml
feature_gates:
  security_audit: false       # Disable security auditing skill
  deployment: false           # Disable deployment skill
  run_mode: false             # Disable autonomous run mode
  constructs: false           # Disable Loa Constructs integration
  continuous_learning: false  # Disable learning extraction
  executive_translation: false # Disable executive summaries
```

Disabled skills are moved to `.claude/.skills-disabled/` (gitignored) and don't load into Claude Code context.

## Configuration

### .loa.config.yaml

User-owned configuration file. Framework updates never touch this. Copied from `.loa.config.yaml.example` during install.

**Minimal working config** (this is all you need to start):

```yaml
# .loa.config.yaml — minimal
persistence_mode: standard
drift_resolution: code
```

That's it. All other settings have sensible defaults. The full example file (`.loa.config.yaml.example`) documents every option.

**Common configuration options**:

```yaml
# Persistence mode
persistence_mode: standard  # or "stealth" for local-only (gitignored)

# Integrity enforcement (Projen-level)
integrity_enforcement: strict  # or "warn", "disabled"

# Drift resolution
drift_resolution: code  # or "docs", "ask"

# Structured memory
memory:
  notes_file: grimoires/loa/NOTES.md
  trajectory_dir: grimoires/loa/a2a/trajectory
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

This adds `grimoires/loa/`, `.beads/`, `.loa-version.json`, and `.loa.config.yaml` to `.gitignore`.

## Updates

### Automatic Updates

```bash
.claude/scripts/update.sh
```

Or use the slash command:
```
/update-loa
```

### What Happens During Updates

1. **Fetch**: Downloads upstream to staging directory
2. **Validate**: Checks YAML syntax, shell script validity
3. **Migrate**: Runs any pending schema migrations (blocking — update halts if migration fails)
4. **Swap**: Atomic replacement of System Zone
5. **Restore**: Your `.claude/overrides/` are preserved
6. **Commit**: Creates single atomic commit with version tag

If an update fails mid-way, your previous version is intact — the swap is atomic. Roll back with `git revert HEAD` if the update committed, or re-run the update.

### Project File Protection (v1.5.0+)

Your `README.md` and `CHANGELOG.md` are automatically preserved during updates via `.gitattributes`.

The `/update-loa` command runs this git config automatically, but if you use the update script directly, ensure this one-time setup is done:
```bash
git config merge.ours.driver true
```

This tells Git to always keep your version of these files when merging from upstream.

### Clean Upgrade (v1.4.0+)

Both `mount-loa.sh` and `update.sh` create a single atomic git commit, preventing history pollution:

```
chore(loa): upgrade framework v1.3.0 -> v1.4.0

- Updated .claude/ System Zone
- Preserved .claude/overrides/
- See: https://github.com/0xHoneyJar/loa/releases/tag/v1.4.0

Generated by Loa update.sh
```

**Version tags**: `loa@v{VERSION}` (e.g., `loa@v1.4.0`)

```bash
# View upgrade history
git tag -l 'loa@*'

# View specific upgrade
git show loa@v1.4.0

# Rollback to previous version
git revert HEAD  # If upgrade was last commit
```

### Skipping Auto-Commit

```bash
# Via CLI flag
.claude/scripts/update.sh --no-commit

# Via configuration (.loa.config.yaml)
upgrade:
  auto_commit: false
  auto_tag: false
```

**Note**: In stealth mode, no commits are created automatically.

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

# Linux (mikefarah/yq — required, NOT the Python yq)
wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq
chmod +x /usr/local/bin/yq

# Or: sudo snap install yq

# Verify (should show "mikefarah/yq")
yq --version
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

# Keep your changes for grimoires/loa/
git checkout --ours grimoires/loa/
```

## CI/CD Configuration

When using submodule mode in CI/CD environments, you must ensure the submodule is initialized. Without `--recurse-submodules`, the `.loa/` directory will be empty and Loa will not function.

### GitHub Actions

```yaml
# .github/workflows/ci.yml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive   # Required for Loa submodule
          # fetch-depth: 0       # Optional: full history for git describe

      # Loa symlinks are recreated automatically on mount
      - name: Verify Loa
        run: |
          ls .loa/.claude/scripts/  # Verify submodule is populated
```

### GitLab CI

```yaml
# .gitlab-ci.yml
variables:
  GIT_SUBMODULE_STRATEGY: recursive  # Required for Loa submodule

build:
  script:
    - ls .loa/.claude/scripts/  # Verify submodule is populated
```

### Shallow Clones

Shallow clones (`--depth 1`) work with submodules. Combine both flags:

```bash
git clone --depth 1 --recurse-submodules https://github.com/your-org/your-repo.git
```

In GitHub Actions:

```yaml
- uses: actions/checkout@v4
  with:
    submodules: recursive
    fetch-depth: 1  # Shallow clone + submodule works
```

### Post-Clone Recovery

If a clone was made without `--recurse-submodules`, initialize manually:

```bash
git submodule update --init .loa
```

Loa's mount script also auto-detects uninitialized submodules and runs this automatically when `/mount` is invoked.

## Uninstalling Loa

### Submodule Mode (Default)

```bash
# 1. Remove symlinks (these point into .loa/)
rm -rf .claude/

# 2. Remove the submodule
git submodule deinit -f .loa
git rm -f .loa
rm -rf .git/modules/.loa  # Clean submodule cache

# 3. Remove state files (optional — contains your project memory and docs)
rm -rf grimoires/loa/ .beads/ .loa-state/ .loa-version.json .loa.config.yaml

# 4. Commit the removal
git commit -m "chore: remove Loa framework (submodule)"
```

### Vendored Mode (Legacy)

```bash
# 1. Remove the framework (System Zone)
rm -rf .claude/

# 2. Remove state files (optional — contains your project memory and docs)
rm -rf grimoires/loa/ .beads/ .loa-state/ .loa-version.json .loa.config.yaml

# 3. Remove from git tracking
git rm -r --cached .claude/ grimoires/loa/ .loa-version.json .loa.config.yaml 2>/dev/null
git commit -m "chore: remove Loa framework (vendored)"

# 4. Remove the upstream remote (if mounted)
git remote remove loa-upstream 2>/dev/null
```

### Using /loa-eject (Recommended)

The safest way to uninstall is `/loa-eject`, which creates a backup before removing:

```bash
# Preview what will be removed
/loa-eject --dry-run

# Execute with backup
/loa-eject
```

> **Note**: Your application code (`src/`, `lib/`, etc.) is never touched by Loa and remains unaffected.

## Loa Constructs (Commercial Skills)

Loa Constructs is a registry for commercial skill packs that extend Loa with specialized capabilities (GTM strategy, security auditing, etc.).

### Authentication

```bash
# Option 1: Environment variable (recommended for scripts)
export LOA_CONSTRUCTS_API_KEY="sk_your_api_key_here"

# Option 2: Credentials file
mkdir -p ~/.loa
echo '{"api_key": "sk_your_api_key_here"}' > ~/.loa/credentials.json
```

Contact the THJ team for API key access.

### Browse and Install with `/constructs` (Recommended)

The easiest way to discover and install packs:

```bash
/constructs              # Browse available packs with multi-select UI
/constructs install <pack>   # Install a specific pack directly
/constructs list         # Show installed packs
/constructs update       # Check for updates
/constructs uninstall <pack> # Remove a pack
/constructs auth         # Check authentication status
/constructs auth setup   # Interactive API key setup
```

The `/constructs` command provides a guided experience with multi-select UI for choosing which packs to install.

### Installing Packs via Script

Alternatively, use the install script directly:

```bash
# Install a pack (downloads and symlinks commands)
.claude/scripts/constructs-install.sh pack gtm-collective

# Install individual skill
.claude/scripts/constructs-install.sh skill thj/market-analyst

# Re-link commands if needed
.claude/scripts/constructs-install.sh link-commands gtm-collective

# Remove a pack
.claude/scripts/constructs-install.sh uninstall pack gtm-collective
```

### What Gets Installed

```
.claude/constructs/
├── packs/{slug}/
│   ├── .license.json      # JWT license token
│   ├── manifest.json      # Pack metadata
│   ├── skills/            # Bundled skills
│   └── commands/          # Pack commands (auto-symlinked)
└── skills/{vendor}/{slug}/
    ├── .license.json
    ├── index.yaml
    └── SKILL.md
```

Pack commands are automatically symlinked to `.claude/commands/` on install, making them immediately available.

### Loading Priority

| Priority | Source | Description |
|----------|--------|-------------|
| 1 | `.claude/skills/` | Local (built-in) |
| 2 | `.claude/overrides/skills/` | User overrides |
| 3 | `.claude/constructs/skills/` | Registry skills |
| 4 | `.claude/constructs/packs/.../skills/` | Pack skills |

Local skills always win. The loader resolves conflicts silently by priority.

### Offline Support

Skills are validated via JWT with grace periods:
- **Individual/Pro**: 24 hours
- **Team**: 72 hours
- **Enterprise**: 168 hours

Force offline mode: `export LOA_OFFLINE=1`

### Configuration

```yaml
# .loa.config.yaml
registry:
  enabled: true
  offline_grace_hours: 24
  check_updates_on_setup: true
```

See [CLI-INSTALLATION.md](grimoires/loa/context/CLI-INSTALLATION.md) for the full setup guide.

## Frictionless Permissions

Loa ships with a `.claude/settings.json` (installed automatically as part of the System Zone) that pre-approves 300+ common development commands, eliminating permission prompts for standard workflows. You don't need to create this file — it's included in the framework.

### What's Pre-Approved

| Category | Examples | Count |
|----------|----------|-------|
| Package Managers | `npm`, `pnpm`, `yarn`, `bun`, `cargo`, `pip`, `poetry`, `gem`, `go` | ~85 |
| Git Operations | `git add`, `commit`, `push`, `pull`, `branch`, `merge`, `rebase`, `stash` | ~35 |
| File System | `mkdir`, `cp`, `mv`, `touch`, `chmod`, `cat`, `ls`, `tar`, `zip` | ~25 |
| Runtimes | `node`, `python`, `python3`, `ruby`, `java`, `rustc`, `deno` | ~15 |
| Containers | `docker`, `docker-compose`, `kubectl`, `helm` | ~25 |
| Databases | `psql`, `mysql`, `redis-cli`, `mongosh`, `prisma` | ~15 |
| Testing | `jest`, `vitest`, `pytest`, `mocha`, `bats`, `playwright`, `cypress` | ~15 |
| Build Tools | `webpack`, `vite`, `esbuild`, `tsc`, `swc`, `turbo`, `nx` | ~20 |
| Deploy CLIs | `vercel`, `fly`, `railway`, `aws`, `gcloud`, `az`, `terraform`, `pulumi` | ~30 |
| Linters | `eslint`, `prettier`, `black`, `ruff`, `rubocop`, `shellcheck` | ~15 |
| Utilities | `curl`, `wget`, `jq`, `yq`, `grep`, `find`, `sed`, `awk` | ~40 |

### Security Deny List

Dangerous commands are explicitly blocked to prevent accidental damage:

| Category | Examples |
|----------|----------|
| Privilege Escalation | `sudo`, `su`, `doas` |
| Destructive Operations | `rm -rf /`, `rm -rf ~`, `rm -rf /home` |
| Fork Bombs | `:(){ :|:& };:` |
| Remote Code Execution | `curl ... | bash`, `wget ... | sh`, `eval "$(curl ..."` |
| Device Attacks | `dd if=/dev/zero of=/dev/sda`, `mkfs`, `fdisk` |
| Permission Attacks | `chmod -R 777 /` |
| System Control | `reboot`, `shutdown`, `poweroff`, `iptables -F` |
| User Management | `passwd`, `useradd`, `userdel`, `visudo` |

**Deny takes precedence over allow** - if a command matches both lists, it's blocked.

### Customizing Permissions

You can extend permissions in your personal Claude Code settings or project `.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(my-custom-tool:*)"
    ],
    "deny": [
      "Bash(some-dangerous-command:*)"
    ]
  }
}
```

**Note**: The deny list is security-critical. Add to it carefully and never remove framework deny patterns.

## Recommended Git Hooks

Loa recommends (but doesn't require) git hooks for team workflows. These handle mechanical tasks like linting and formatting—leaving Loa's agents to focus on higher-level work.

### Husky Setup

```bash
# Initialize Husky
npx husky install

# Add pre-commit hook for linting
npx husky add .husky/pre-commit "npm run lint-staged"

# Add pre-push hook for tests
npx husky add .husky/pre-push "npm test"
```

### lint-staged Configuration

Add to `package.json`:

```json
{
  "lint-staged": {
    "*.{ts,tsx,js,jsx}": ["eslint --fix", "prettier --write"],
    "*.{md,json,yaml,yml}": ["prettier --write"],
    "*.sh": ["shellcheck"]
  }
}
```

### Commitlint (Optional)

Enforce conventional commits:

```bash
# Install
npm install -D @commitlint/cli @commitlint/config-conventional

# Configure
echo "module.exports = {extends: ['@commitlint/config-conventional']}" > commitlint.config.js

# Add hook
npx husky add .husky/commit-msg "npx commitlint --edit $1"
```

### Why Git Hooks Instead of AI?

- **Git hooks are deterministic** - same input always produces same output
- **No API costs** - runs locally with zero latency
- **Team standardization** - everyone runs the same checks
- **Separation of concerns** - mechanical tasks vs. intelligent decisions

Loa's agents focus on design, implementation, and review—not formatting code.

## Generated Files

After installation, Loa generates `BUTTERFREEZONE.md` — the machine-readable agent-API interface for your project. This file provides token-efficient orientation with provenance-tagged content for any agent entering your repository. It is regenerated automatically during `/run-bridge`, post-merge automation, and on-demand via `/butterfreezone`. See [PROCESS.md](PROCESS.md) for the BUTTERFREEZONE standard.

## Next Steps

After installation, start Claude Code and run these slash commands inside it:

```bash
# 1. Start Claude Code (this is a shell command)
claude

# 2. Inside Claude Code — check system health (slash command)
/loa doctor

# 3. Begin (no setup required!)
/plan
```

`/plan` takes 2-5 minutes on first run and creates `grimoires/loa/prd.md`. Type `/loa` at any time to see where you are and what to do next.

If something goes wrong, see [Troubleshooting](#troubleshooting) or run `/loa doctor` for structured diagnostics. See [README.md](README.md) for the complete workflow.
