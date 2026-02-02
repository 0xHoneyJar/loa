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

#### ck (Semantic Code Search) {#ck-semantic-code-search}

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

#### beads_rust (Task Graph) {#beads_rust-optional}

**What it does**: Persistent task graph tracking across sessions using SQLite + JSONL for git-friendly diffs.

**Benefits**:
- **Cross-session persistence**: Tasks survive context clears and session restarts
- **Dependency tracking**: Block tasks on others, track readiness
- **Sprint integration**: Tasks linked to sprint plans

**Without beads_rust**: Sprint state is tracked in markdown files only. Works fine for most projects.

**Installation**:

```bash
# Install via cargo
cargo install beads_rust

# Verify installation
br --version

# Initialize in project
br init
```

#### Memory Stack (Vector Database) {#memory-stack-optional}

**What it does**: SQLite vector database with [sentence-transformers](https://github.com/UKPLab/sentence-transformers) embeddings for mid-stream semantic memory recall during Claude Code sessions.

**Benefits**:
- **Semantic grounding**: Recall relevant learnings during tool execution
- **NOTES.md sync**: Automatically extract learnings to searchable database
- **QMD integration**: Document search with semantic or grep fallback

**Without Memory Stack**: Loa works normally using NOTES.md for structured memory. The Memory Stack adds semantic recall.

**Resource Requirements**:
> ⚠️ **Warning**: sentence-transformers requires significant disk space and memory.
> - **Disk**: ~2-3 GB for dependencies (PyTorch, transformers, model weights)
> - **RAM**: ~500 MB when embedding (model loaded into memory)
> - **First run**: Downloads ~90 MB model (`all-MiniLM-L6-v2`) to `~/.cache/sentence_transformers/`

**Prerequisites**:
- Python 3.8+ with pip
- sentence-transformers ([GitHub](https://github.com/UKPLab/sentence-transformers) | [Docs](https://www.sbert.net/))

**Installation**:

```bash
# Run setup wizard
.claude/scripts/memory-setup.sh

# Or manual setup
pip install sentence-transformers
mkdir -p .loa
```

**Configuration** (`.loa.config.yaml`):

```yaml
memory:
  pretooluse_hook:
    enabled: false  # Opt-in for safety
    thinking_chars: 1500
    similarity_threshold: 0.35
    max_memories: 3
    timeout_ms: 500
```

**Note**: Memory Stack is opt-in by default. Enable via config after setup.

#### Flatline Protocol - NotebookLM Integration (Optional) {#notebooklm-optional}

**What it does**: Enables Tier 2 knowledge retrieval from Google NotebookLM for the Flatline Protocol's multi-model adversarial review.

**Benefits**:
- **Curated knowledge**: Query your own NotebookLM notebooks with domain expertise
- **Two-tier knowledge**: Combines local learnings (Tier 1) with NotebookLM (Tier 2)
- **Better context**: Models receive relevant domain knowledge before reviewing

**Without NotebookLM**: Flatline Protocol works perfectly with local knowledge only (Tier 1). NotebookLM adds supplementary context for specialized domains.

**Prerequisites**:
- Python 3.8+
- A Google account (any gmail or workspace account)
- Optionally: A NotebookLM notebook with uploaded sources

> **Note**: NotebookLM is NOT Gemini. It's a separate Google product (notebooklm.google.com) for creating personal knowledge bases. No API key required - uses browser session authentication.

**Installation**:

```bash
# Install patchright (browser automation) - must be accessible as Python module
pip install --user patchright
# OR in a virtual environment: pip install patchright

# Install browser binaries (Chromium)
patchright install chromium
# OR: python3 -m patchright install chromium

# One-time authentication (opens browser for Google sign-in)
python3 .claude/skills/flatline-knowledge/resources/notebooklm-query.py --setup-auth
```

**Authentication Process**:
1. Browser window opens to notebooklm.google.com
2. Sign in with your Google account
3. Navigate to any notebook (confirms access)
4. Close the browser when done
5. Session saved to `~/.claude/notebooklm-auth/` (with 0700 permissions)

**Configuration** (`.loa.config.yaml`):

```yaml
flatline_protocol:
  enabled: true
  knowledge:
    notebooklm:
      enabled: true                    # Enable Tier 2 knowledge
      notebook_id: "your-notebook-id"  # Optional: specific notebook
      timeout_ms: 30000                # Query timeout
```

**Getting a Notebook ID** (optional):
1. Go to notebooklm.google.com
2. Open or create a notebook
3. Copy the ID from the URL: `notebooklm.google.com/notebook/NOTEBOOK_ID`

**Security Notes**:
- Auth session stored with restrictive permissions (0700)
- Uses isolated browser profile
- No credentials stored in plain text
- Session can be revoked by deleting `~/.claude/notebooklm-auth/`

**Testing**:

```bash
# Dry run (no browser needed)
python3 .claude/skills/flatline-knowledge/resources/notebooklm-query.py \
  --dry-run --domain "your domain" --phase prd

# Live query (requires auth setup)
python3 .claude/skills/flatline-knowledge/resources/notebooklm-query.py \
  --domain "your domain" --phase prd --json
```

**Updating existing repos**: If you're updating Loa to v0.8.0+ in an existing repository, you'll need to manually initialize the ck index:

```bash
# From your project root
ck --index .
```

This creates the `.ckignore` file and builds the initial semantic index.

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
mkdir -p grimoires/loa/{context,discovery,a2a/trajectory} .beads

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
├── grimoires/loa/               # State Zone (project memory)
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
3. **Migrate**: Runs any pending schema migrations (blocking)
4. **Swap**: Atomic replacement of System Zone
5. **Restore**: Your `.claude/overrides/` are preserved
6. **Commit**: Creates single atomic commit with version tag

### Project File Protection (v1.5.0+)

Your `README.md` and `CHANGELOG.md` are automatically preserved during updates via `.gitattributes`.

**One-time setup** (required for `/update-loa`):
```bash
git config merge.ours.driver true
```

This tells Git to always keep your version of these files when merging from upstream. The `/update-loa` command runs this automatically, but you can also set it manually.

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

# Keep your changes for grimoires/loa/
git checkout --ours grimoires/loa/
```

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

Loa includes a comprehensive `.claude/settings.json` that pre-approves 300+ common development commands, eliminating permission prompts for standard workflows.

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

## Next Steps

After installation:

```bash
# 1. Start Claude Code
claude

# 2. Begin workflow (no setup required!)
/plan-and-analyze
```

See [README.md](README.md) for the complete workflow.
