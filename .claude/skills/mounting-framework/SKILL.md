---
name: mount
description: "Install Loa framework onto an existing repository"
capabilities:
  schema_version: 1
  read_files: true
  search_code: true
  write_files: true
  execute_commands: true
  web_access: false
  user_interaction: true
  agent_spawn: false
  task_management: false
cost-profile: heavy
---

# Mounting the Loa Framework

You are installing the Loa framework onto a repository. This is the first step before the Loa can ride through the codebase.

> *"The Loa mounts the repository, preparing to ride."*

## Core Principle

```
MOUNT once → RIDE many times
```

Mounting installs the framework. Riding analyzes the code.

---

## Pre-Mount Checks

### 1. Verify Git Repository

```bash
if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "❌ Not a git repository. Initialize with 'git init' first."
  exit 1
fi
echo "✓ Git repository detected"
```

### 2. Check for Existing Mount

```bash
if [[ -f ".loa-version.json" ]]; then
  VERSION=$(jq -r '.framework_version' .loa-version.json 2>/dev/null)
  echo "⚠️ Loa already mounted (v$VERSION)"
  echo "Use '/update-loa' to sync framework, or continue to remount"
  # Use AskUserQuestion to confirm remount
fi
```

### 3. Verify Dependencies

```bash
command -v jq >/dev/null || { echo "❌ jq required"; exit 1; }
echo "✓ Dependencies satisfied"
```

---

## Mount Process

### Step 1: Configure Upstream Remote

```bash
LOA_REMOTE_URL="${LOA_UPSTREAM:-https://github.com/0xHoneyJar/loa.git}"
LOA_REMOTE_NAME="loa-upstream"
LOA_BRANCH="${LOA_BRANCH:-main}"

if git remote | grep -q "^${LOA_REMOTE_NAME}$"; then
  git remote set-url "$LOA_REMOTE_NAME" "$LOA_REMOTE_URL"
else
  git remote add "$LOA_REMOTE_NAME" "$LOA_REMOTE_URL"
fi

git fetch "$LOA_REMOTE_NAME" "$LOA_BRANCH" --quiet
echo "✓ Upstream configured"
```

### Step 2: Install System Zone

```bash
echo "Installing System Zone (.claude/)..."
git checkout "$LOA_REMOTE_NAME/$LOA_BRANCH" -- .claude 2>/dev/null || {
  echo "❌ Failed to checkout .claude/ from upstream"
  exit 1
}
echo "✓ System Zone installed"
```

### Step 3: Initialize State Zone

```bash
echo "Initializing State Zone..."

# Create structure (preserve if exists)
mkdir -p grimoires/loa/{context,reality,legacy,discovery,a2a/trajectory}
mkdir -p .beads

# Initialize structured memory
if [[ ! -f "grimoires/loa/NOTES.md" ]]; then
  cat > grimoires/loa/NOTES.md << 'EOF'
# Agent Working Memory (NOTES.md)

> This file persists agent context across sessions and compaction cycles.

## Active Sub-Goals

## Discovered Technical Debt

## Blockers & Dependencies

## Session Continuity
| Timestamp | Agent | Summary |
|-----------|-------|---------|

## Decision Log
| Date | Decision | Rationale | Decided By |
|------|----------|-----------|------------|
EOF
  echo "✓ Structured memory initialized"
else
  echo "✓ Structured memory preserved"
fi
```

### Step 4: Create Version Manifest

The manifest's `framework_version` is resolved from the upstream HEAD that is being mounted. The skill writes a `__PENDING__` placeholder and then delegates to `.claude/scripts/update-loa-bump-version.sh` — the same resolver `/update-loa` uses (Phase 5.6). This makes `/mount` and `/update-loa` share a single source of truth so the version stamp can never go stale relative to the framework files just checked out.

```bash
# Resolve target version from the upstream HEAD the user just checked out.
# Source priority: upstream's .loa-version.json → upstream tag → short SHA fallback.
# Uses the remote/branch already configured by Step 1 (LOA_REMOTE_NAME=loa-upstream,
# LOA_BRANCH defaults to main). NOT the same as $LOA_UPSTREAM env var which Step 1
# overloads as the remote URL — name collision avoided here by composing the ref
# from the remote name + branch directly.
LOA_UPSTREAM_REF="loa-upstream/${LOA_BRANCH:-main}"
TARGET_VERSION=""
if git show "${LOA_UPSTREAM_REF}":.loa-version.json 2>/dev/null | jq -er '.framework_version' >/dev/null 2>&1; then
  TARGET_VERSION=$(git show "${LOA_UPSTREAM_REF}":.loa-version.json | jq -r '.framework_version')
elif git tag --points-at "${LOA_UPSTREAM_REF}" 2>/dev/null | grep -qE '^v[0-9]+\.'; then
  TARGET_VERSION=$(git tag --points-at "${LOA_UPSTREAM_REF}" | grep -E '^v[0-9]+\.' | head -1 | sed 's/^v//')
else
  TARGET_VERSION="0.0.0-unknown-$(git rev-parse --short "${LOA_UPSTREAM_REF}" 2>/dev/null || echo 'nosha')"
fi

cat > .loa-version.json << EOF
{
  "framework_version": "__PENDING__",
  "schema_version": 2,
  "last_sync": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "zones": {
    "system": ".claude",
    "state": ["grimoires/loa", ".beads"],
    "app": ["src", "lib", "app"]
  },
  "migrations_applied": ["001_init_zones"],
  "integrity": {
    "enforcement": "strict",
    "last_verified": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  }
}
EOF

# Replace placeholder via the SAME resolver /update-loa uses (single source of truth).
# Fail-loud: if the resolver fails, the manifest is left at __PENDING__ and would
# poison the trajectory log + NOTES.md. Delete the manifest and exit so the user
# gets a clear failure instead of a silent stale-stamp.
if ! .claude/scripts/update-loa-bump-version.sh --target "$TARGET_VERSION"; then
  echo "❌ Failed to resolve framework_version via update-loa-bump-version.sh"
  rm -f .loa-version.json
  exit 1
fi

# Defense-in-depth: verify the placeholder was actually replaced. Guards against
# a resolver that exits 0 without patching (e.g., target-validation rejects the
# value silently, or bump_version_json no-ops on an unexpected match).
if [[ "$(jq -r '.framework_version' .loa-version.json 2>/dev/null)" == "__PENDING__" ]]; then
  echo "❌ Resolver returned 0 but framework_version is still __PENDING__"
  rm -f .loa-version.json
  exit 1
fi
echo "✓ Version manifest created (resolved: $TARGET_VERSION)"
```

### Step 5: Generate Checksums (Anti-Tamper)

```bash
echo "Generating integrity checksums..."

CHECKSUMS_FILE=".claude/checksums.json"
checksums='{"generated":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","algorithm":"sha256","files":{'

first=true
while IFS= read -r -d '' file; do
  hash=$(sha256sum "$file" | cut -d' ' -f1)
  relpath="${file#./}"
  [[ "$first" == "true" ]] && first=false || checksums+=','
  checksums+='"'"$relpath"'":"'"$hash"'"'
done < <(find .claude -type f ! -name "checksums.json" ! -path "*/overrides/*" -print0 | sort -z)

checksums+='}}'
echo "$checksums" | jq '.' > "$CHECKSUMS_FILE"
echo "✓ Checksums generated"
```

### Step 6: Create User Config

```bash
if [[ ! -f ".loa.config.yaml" ]]; then
  cat > .loa.config.yaml << 'EOF'
# Loa Framework Configuration
# This file is yours - framework updates will never modify it

persistence_mode: standard  # standard | stealth
integrity_enforcement: strict  # strict | warn | disabled
drift_resolution: code  # code | docs | ask

disabled_agents: []

memory:
  notes_file: grimoires/loa/NOTES.md
  trajectory_dir: grimoires/loa/a2a/trajectory
  trajectory_retention_days: 30
  auto_restore: true

edd:
  enabled: true
  min_test_scenarios: 3
  trajectory_audit: true
  require_citations: true

compaction:
  enabled: true
  threshold: 5

integrations:
  - github
EOF
  echo "✓ Config created"
else
  echo "✓ Config preserved"
fi
```

### Step 7: Initialize beads_rust (Optional)

```bash
if command -v br &> /dev/null; then
  if [[ ! -f ".beads/beads.db" ]]; then
    br init --quiet 2>/dev/null && echo "✓ beads_rust initialized"
  else
    echo "✓ beads_rust already initialized"
  fi
else
  echo "⚠️ beads_rust (br) not found - skipping (install: .claude/scripts/beads/install-br.sh)"
fi
```

### Step 8: Create Overrides Directory

```bash
mkdir -p .claude/overrides
[[ -f .claude/overrides/README.md ]] || cat > .claude/overrides/README.md << 'EOF'
# User Overrides

Files here are preserved across framework updates.
Mirror the .claude/ structure for any customizations.
EOF
```

---

## Post-Mount Output

Display completion message:

```markdown
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

---

## Stealth Mode

If `--stealth` flag or `persistence_mode: stealth` in config:

```bash
echo "Applying stealth mode..."
touch .gitignore

for entry in "grimoires/loa/" ".beads/" ".loa-version.json" ".loa.config.yaml"; do
  grep -qxF "$entry" .gitignore 2>/dev/null || echo "$entry" >> .gitignore
done

echo "✓ State files added to .gitignore"
```

---

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| "Not a git repository" | No `.git` directory | Run `git init` first |
| "jq required" | Missing jq | Install jq (`brew install jq` / `apt install jq`) |
| "Failed to checkout .claude/" | Network/auth issue | Check remote URL and credentials |
| "Loa already mounted" | `.loa-version.json` exists | Use `/update-loa` or confirm remount |

---

## Trajectory Logging

Log mount action to trajectory:

```bash
MOUNT_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TRAJECTORY_FILE="grimoires/loa/a2a/trajectory/mounting-$(date +%Y%m%d).jsonl"
# Read the resolved version BACK from the manifest written in Step 4.
# Never re-template a literal here — this is how prior recurrences (#56, #123, #640) regressed.
RESOLVED_VERSION=$(jq -r '.framework_version' .loa-version.json)

# Use jq to construct the JSON line. String concatenation breaks on unusual
# chars in $RESOLVED_VERSION (quote, newline, backslash) and could produce a
# malformed JSONL row that breaks downstream parsers. jq handles encoding.
jq -nc --arg ts "$MOUNT_DATE" --arg v "$RESOLVED_VERSION" \
  '{timestamp:$ts, agent:"mounting-framework", action:"mount", status:"complete", version:$v}' \
  >> "$TRAJECTORY_FILE"
```

---

## NOTES.md Update

After successful mount, add an entry to NOTES.md. The version field MUST be read from `.loa-version.json` (NOT templated as a literal — that is how prior recurrences #56, #123, and #640 regressed). The agent that runs this step should resolve `${RESOLVED_VERSION}` via:

```bash
RESOLVED_VERSION=$(jq -r '.framework_version' .loa-version.json)
```

…and then append the row, substituting the variable into the markdown:

```markdown
## Session Continuity
| Timestamp | Agent | Summary |
|-----------|-------|---------|
| [now] | mounting-framework | Mounted Loa v${RESOLVED_VERSION} on repository |
```
