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

### Installing Packs

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
