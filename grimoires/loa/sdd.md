# SDD: Minimal Footprint by Default — Submodule-First Installation

> Cycle: cycle-035 | Author: soju + Claude (Bridgebuilder)
> Source PRD: `grimoires/loa/prd.md` ([#402](https://github.com/0xHoneyJar/loa/issues/402))
> Predecessor: cycle-034 SDD (Declarative Execution Router + Adaptive Multi-Pass)
> Design Context: Bridgebuilder review of [Issue #402](https://github.com/0xHoneyJar/loa/issues/402#issuecomment-3944873665)

---

## 1. Executive Summary

This SDD flips Loa's default installation mode from vendored (800+ files copied into `.claude/`) to git submodule (single reference at `.loa/` with symlinks). The infrastructure already exists — `mount-submodule.sh` is 619 lines and fully functional. The work is: (1) flip the default in `mount-loa.sh`, (2) resolve the `.loa/` path collision between Memory Stack and submodule, (3) expand stealth mode from 4 gitignore entries to comprehensive coverage, and (4) add migration tooling.

**Critical correction from PRD**: The PRD proposed `.claude/loa` as the submodule mount point. This **breaks** the `@.claude/loa/CLAUDE.loa.md` import in `CLAUDE.md` (line 1). The `@`-import resolves to `.claude/loa/CLAUDE.loa.md` as a file path — if `.claude/loa` were the submodule root (the Loa repo), that file would be at `.claude/loa/.claude/loa/CLAUDE.loa.md` (nested), not where the import expects it. The correct design keeps the submodule at `.loa/` (mount-submodule.sh's existing `SUBMODULE_PATH`, line 50) and uses symlinks to bridge into `.claude/`. This is exactly what `create_symlinks()` (mount-submodule.sh:260-359) already implements.

**Architecture principle**: The submodule IS the framework. Symlinks project its structure into `.claude/` where Claude Code expects it. User-owned files (settings.json, commands/, overrides/) live directly in `.claude/`, never symlinked. Memory Stack relocates from `.loa/` to `.loa-cache/` to clear the collision.

**Scope boundary**: Default flip + collision resolution + stealth expansion + migration. No changes to runtime behavior, skill execution, or Claude Code interaction patterns.

---

## 2. System Architecture

### 2.1 Installation Mode Comparison

```
VENDORED (current default)          SUBMODULE (new default)
──────────────────────────          ───────────────────────
.claude/                            .loa/                     ← git submodule (Loa repo)
├── scripts/      (800+ files)      │ └── .claude/
├── skills/       (copied)          │     ├── scripts/
├── protocols/    (copied)          │     ├── skills/
├── hooks/        (copied)          │     ├── protocols/
├── data/         (copied)          │     ├── hooks/
├── schemas/      (copied)          │     ├── data/
├── loa/          (copied)          │     ├── schemas/
├── settings.json (user)            │     └── loa/
├── commands/     (user)            .claude/
└── overrides/    (user)            ├── scripts    → ../.loa/.claude/scripts     (symlink)
                                    ├── skills/    → per-skill symlinks          (symlinks)
                                    ├── protocols  → ../.loa/.claude/protocols   (symlink)
                                    ├── hooks      → ../.loa/.claude/hooks       (symlink)
                                    ├── data       → ../.loa/.claude/data        (symlink)
                                    ├── schemas    → ../.loa/.claude/schemas     (symlink)
                                    ├── loa/       (real dir, files symlinked)
                                    │   └── CLAUDE.loa.md → ../../.loa/.claude/loa/CLAUDE.loa.md
                                    ├── settings.json      (user-owned, NOT symlinked)
                                    ├── commands/          (user-owned, NOT symlinked)
                                    └── overrides/         (user-owned, NOT symlinked)
```

### 2.2 File Ownership Model

| Owner | Tracked | Examples |
|-------|---------|----------|
| **User** | Yes | `CLAUDE.md`, `.loa.config.yaml`, `.claude/settings.json`, `.claude/commands/`, `.gitmodules` |
| **Submodule** | Via reference | `.loa/` (all framework content) |
| **Symlinks** | Gitignored | `.claude/scripts`, `.claude/skills/*`, `.claude/protocols`, etc. |
| **State** | Gitignored | `grimoires/`, `.beads/`, `.ck/`, `.run/`, `.loa-cache/` |

### 2.3 @-Import Resolution Chain

The critical path that constrains submodule placement:

```
CLAUDE.md line 1:  @.claude/loa/CLAUDE.loa.md
                   │
                   ▼
.claude/loa/CLAUDE.loa.md  (symlink, created by mount-submodule.sh:329)
                   │
                   ▼ resolves to
../../.loa/.claude/loa/CLAUDE.loa.md  (real file inside submodule)
                   │
                   = .loa/.claude/loa/CLAUDE.loa.md  (from project root)
```

This chain works because:
1. `.claude/loa/` is a real directory (not a symlink itself), created at mount-submodule.sh:326
2. `CLAUDE.loa.md` inside it is a symlink into the submodule
3. The `../../` traversal from `.claude/loa/` reaches project root, then `.loa/` enters the submodule

If the submodule were at `.claude/loa` instead:
- `.claude/loa/` would BE the submodule root (Loa repo)
- `CLAUDE.loa.md` is NOT at the Loa repo root — it's at `.claude/loa/CLAUDE.loa.md` within the repo
- So the @-import would resolve to `.claude/loa/CLAUDE.loa.md` → Loa repo root has no such file
- The actual file would be at `.claude/loa/.claude/loa/CLAUDE.loa.md` — unreachable by the @-import

**Decision: Submodule stays at `.loa/`** (D-012 updated from PRD's `.claude/loa`).

### 2.4 `.loa/` Path Collision Resolution

| Component | Current Path | New Path | Rationale |
|-----------|-------------|----------|-----------|
| Git submodule | `.loa/` (mount-submodule.sh:50) | `.loa/` (unchanged) | Already correct |
| Memory Stack | `.loa/` (gitignored) | `.loa-cache/` (gitignored) | Clears collision |
| .gitignore | `.loa/` on line 75 | REMOVED (submodule tracked) | Submodule must be visible to git |

The collision resolution is: Memory Stack moves, submodule stays.

---

## 3. Component Design

### 3.1 mount-loa.sh — Default Flip

**File**: `.claude/scripts/mount-loa.sh` (~1540 lines)

#### 3.1.1 SUBMODULE_MODE Default (line 183)

```bash
# Before:
SUBMODULE_MODE=false

# After:
SUBMODULE_MODE=true
```

Single line change. This makes `/mount` (without flags) route to `mount-submodule.sh` via `route_to_submodule()` (line 1336).

#### 3.1.2 Flag Inversion (lines 212-214)

```bash
# Before:
--submodule)
  SUBMODULE_MODE=true
  shift
  ;;

# After:
--vendored)
  SUBMODULE_MODE=false
  shift
  ;;
```

Add `--vendored` as the opt-in for standard mode. Keep `--submodule` as a no-op (already the default) with deprecation log.

#### 3.1.3 Help Text Update (lines 227-234)

```bash
echo "Installation Modes:"
echo "  (default)         Submodule mode - adds Loa as git submodule at .loa/"
echo "  --vendored        Standard mode - copies files into .claude/ (legacy)"
echo ""
echo "Submodule Mode Options:"
echo "  --branch <name>   Loa branch to use (default: main)"
echo "  --tag <tag>       Loa tag to pin to"
echo "  --ref <ref>       Loa ref to pin to"
echo ""
echo "Standard (Vendored) Mode Options:"
echo "  --branch <name>   Loa branch to use (default: main)"
```

#### 3.1.4 Mode Conflict Messages (lines 1310-1333)

Update error messages for the inverted default:

```bash
check_mode_conflicts() {
  if [[ -f "$VERSION_FILE" ]]; then
    local current_mode=$(jq -r '.installation_mode // "standard"' "$VERSION_FILE" 2>/dev/null)

    if [[ "$SUBMODULE_MODE" == "true" ]] && [[ "$current_mode" == "standard" ]]; then
      err "Loa is installed in vendored (standard) mode. Cannot switch to submodule mode.
To migrate: /mount --migrate-to-submodule
To keep vendored: /mount --vendored"
    fi

    if [[ "$SUBMODULE_MODE" == "false" ]] && [[ "$current_mode" == "submodule" ]]; then
      err "Loa is installed in submodule mode. Cannot switch to vendored mode.
To switch modes:
  1. Remove the submodule: git submodule deinit -f .loa && git rm -f .loa
  2. Remove symlinks from .claude/ (preserve settings.json, commands/, overrides/)
  3. Remove .loa-version.json
  4. Run: /mount --vendored"
    fi
  fi
}
```

### 3.1.5 Graceful Degradation Preflight (Flatline IMP-001, SKP-001, SKP-002)

Before routing to submodule or vendored mode, add environment preflight checks. If submodule prerequisites fail, **automatically fall back to vendored mode** with a clear warning — never leave the user unable to install.

```bash
# Add to mount-loa.sh, called before route_to_submodule():
preflight_submodule_environment() {
  local can_submodule=true
  local reasons=()

  # Check 1: git present and working
  if ! command -v git &>/dev/null; then
    can_submodule=false
    reasons+=("git not found in PATH")
  fi

  # Check 2: inside a git repository
  if ! git rev-parse --git-dir &>/dev/null 2>&1; then
    can_submodule=false
    reasons+=("not inside a git repository")
  fi

  # Check 3: submodule support (git version >= 1.8.5 for submodule add)
  if command -v git &>/dev/null; then
    local git_ver
    git_ver=$(git --version | grep -oE '[0-9]+\.[0-9]+' | head -1)
    if [[ "$(printf '%s\n' "1.8" "$git_ver" | sort -V | head -1)" != "1.8" ]]; then
      can_submodule=false
      reasons+=("git version too old for submodule support")
    fi
  fi

  # Check 4: symlink support (write test symlink, check it works)
  if [[ "$can_submodule" == "true" ]]; then
    local test_link=".claude/.symlink-test-$$"
    local test_target=".claude"
    if ! ln -sf "$test_target" "$test_link" 2>/dev/null; then
      can_submodule=false
      reasons+=("symlinks not supported (ln -sf failed)")
    else
      rm -f "$test_link" 2>/dev/null
    fi
  fi

  # Check 5: CI submodule init status (detect shallow/partial clones)
  if [[ "${CI:-}" == "true" ]] && [[ "$can_submodule" == "true" ]]; then
    if [[ -f ".gitmodules" ]] && ! git submodule status &>/dev/null 2>&1; then
      warn "CI environment detected with uninitialized submodules"
      warn "Running: git submodule update --init"
      git submodule update --init 2>/dev/null || {
        can_submodule=false
        reasons+=("submodule init failed in CI")
      }
    fi
  fi

  if [[ "$can_submodule" == "false" ]]; then
    warn "Cannot use submodule mode:"
    for reason in "${reasons[@]}"; do
      warn "  - $reason"
    done
    warn "Falling back to vendored (standard) mode"
    SUBMODULE_MODE=false
    return 1
  fi

  return 0
}
```

This addresses SKP-001 (submodule-first assumes git everywhere) and SKP-002 (symlink fragility) by making the default **best-effort submodule, guaranteed-fallback vendored**.

### 3.2 mount-submodule.sh — Missing Symlinks

**File**: `.claude/scripts/mount-submodule.sh` (619 lines)

The existing `create_symlinks()` (lines 260-359) handles skills, commands, scripts, protocols, schemas, and loa/CLAUDE.loa.md. Missing from the current implementation:

#### 3.2.1 Missing `.claude/hooks/` Symlink

```bash
# Add after schemas symlink (line 322):
step "Linking hooks directory..."
if [[ -d "$SUBMODULE_PATH/.claude/hooks" ]]; then
  safe_symlink ".claude/hooks" "../$SUBMODULE_PATH/.claude/hooks"
  log "  Linked: .claude/hooks/"
fi
```

#### 3.2.2 Missing `.claude/data/` Symlink

```bash
# Add after hooks symlink:
step "Linking data directory..."
if [[ -d "$SUBMODULE_PATH/.claude/data" ]]; then
  safe_symlink ".claude/data" "../$SUBMODULE_PATH/.claude/data"
  log "  Linked: .claude/data/"
fi
```

#### 3.2.3 Missing `.claude/loa/reference/` Symlinks

The current code (line 329) only symlinks `CLAUDE.loa.md`. The `.claude/loa/reference/` directory also needs linking:

```bash
# Add after CLAUDE.loa.md symlink (line 331):
if [[ -d "$SUBMODULE_PATH/.claude/loa/reference" ]]; then
  safe_symlink ".claude/loa/reference" "../../$SUBMODULE_PATH/.claude/loa/reference"
  log "  Linked: .claude/loa/reference/"
fi

# Also link feedback-ontology.yaml and learnings/
if [[ -f "$SUBMODULE_PATH/.claude/loa/feedback-ontology.yaml" ]]; then
  safe_symlink ".claude/loa/feedback-ontology.yaml" "../../$SUBMODULE_PATH/.claude/loa/feedback-ontology.yaml"
  log "  Linked: .claude/loa/feedback-ontology.yaml"
fi

if [[ -d "$SUBMODULE_PATH/.claude/loa/learnings" ]]; then
  safe_symlink ".claude/loa/learnings" "../../$SUBMODULE_PATH/.claude/loa/learnings"
  log "  Linked: .claude/loa/learnings/"
fi
```

#### 3.2.4 Preflight Fix (lines 131-166)

The `preflight()` function checks for existing `.loa/` directory at line 156-158. When Memory Stack has written to `.loa/`, this check would block submodule creation. Add a Memory Stack migration step:

```bash
# In preflight(), after detecting .loa/ exists:
if [[ -d ".loa" ]] && [[ ! -f ".loa/.git" ]]; then
  # .loa/ exists but is NOT a submodule — likely Memory Stack data
  warn "Found existing .loa/ directory (not a submodule)"
  step "Relocating Memory Stack data to .loa-cache/..."

  # Flatline SKP-003: Use atomic mv, not cp+rm, to prevent data loss
  if [[ -d ".loa-cache" ]]; then
    err "Both .loa/ and .loa-cache/ exist. Cannot auto-migrate.
Please manually resolve:
  mv .loa-cache .loa-cache.old
  mv .loa .loa-cache"
  fi

  # Atomic move (same filesystem = rename, no data copy)
  if mv .loa .loa-cache 2>/dev/null; then
    log "Memory Stack relocated to .loa-cache/ (atomic move)"
  else
    # Cross-filesystem: fall back to rsync with verification
    if command -v rsync &>/dev/null; then
      rsync -a --include='.*' .loa/ .loa-cache/ || {
        err "Memory Stack relocation failed (rsync error). Aborting."
      }
      # Verify file count matches
      local src_count dst_count
      src_count=$(find .loa -type f 2>/dev/null | wc -l)
      dst_count=$(find .loa-cache -type f 2>/dev/null | wc -l)
      if [[ "$src_count" != "$dst_count" ]]; then
        err "Memory Stack relocation verification failed: $src_count source files, $dst_count destination files. Aborting."
      fi
      rm -rf .loa
      log "Memory Stack relocated to .loa-cache/ (rsync + verified)"
    else
      err "Cannot relocate .loa/ to .loa-cache/ (mv failed, rsync not available).
Please manually: mv .loa .loa-cache"
    fi
  fi
fi
```

#### 3.2.5 Post-Clone Auto-Init (Flatline IMP-002)

When a user clones without `--recurse-submodules`, the `.loa/` directory exists but is empty. Detect this and auto-initialize:

```bash
# Add to mount-submodule.sh preflight() or as standalone recovery function:
auto_init_submodule() {
  # Check if .gitmodules references .loa but it's uninitialized
  if [[ -f ".gitmodules" ]] && grep -q 'path = .loa' .gitmodules 2>/dev/null; then
    if [[ ! -f ".loa/.git" ]] && [[ ! -d ".loa/.claude" ]]; then
      warn "Submodule .loa/ appears uninitialized (missing .git marker)"
      step "Auto-initializing submodule..."
      git submodule update --init .loa || {
        err "Failed to initialize submodule. Run manually:
  git submodule update --init .loa"
      }
      log "Submodule initialized"

      # Recreate symlinks (they don't survive clone)
      step "Recreating symlinks..."
      create_symlinks
      log "Symlinks recreated"
    fi
  fi
}
```

This also applies after `git clone` in CI — the mount script (or a post-checkout hook) detects the uninitialized state and self-heals.

### 3.3 .gitignore — Collision Resolution + Stealth Expansion

**File**: `.gitignore` (222 lines)

#### 3.3.1 Remove `.loa/` from Default Gitignore (line 75)

```diff
-# Memory stack
-.loa/
+# Memory stack (relocated from .loa/ to avoid submodule collision)
+.loa-cache/
```

The `.loa/` entry MUST be removed because git submodules at `.loa/` need to be tracked. Memory Stack's new home `.loa-cache/` takes its place.

#### 3.3.2 Add Symlink Gitignore Entries

Symlinks created by `mount-submodule.sh` should be gitignored (they're recreated on clone):

```gitignore
# Submodule symlinks (recreated by mount-submodule.sh)
.claude/scripts
.claude/protocols
.claude/hooks
.claude/data
.claude/schemas
.claude/loa/CLAUDE.loa.md
.claude/loa/reference
.claude/loa/feedback-ontology.yaml
.claude/loa/learnings
```

**Note**: `.claude/skills/` uses per-skill symlinks (not a directory symlink), so individual skill symlinks are gitignored by the existing `.claude/skills/*/` pattern or need explicit entries.

### 3.4 apply_stealth() — Comprehensive Expansion

**File**: `.claude/scripts/mount-loa.sh`, lines 985-1009

Current `apply_stealth()` adds only 4 entries. Expand to comprehensive coverage:

```bash
apply_stealth() {
  local mode="standard"

  if [[ "$STEALTH_MODE" == "true" ]]; then
    mode="stealth"
  elif [[ -f "$CONFIG_FILE" ]]; then
    mode=$(yq_read "$CONFIG_FILE" '.persistence_mode' "standard")
  fi

  if [[ "$mode" == "stealth" ]]; then
    step "Applying stealth mode..."

    local gitignore=".gitignore"
    touch "$gitignore"

    # Core state (always gitignored in stealth)
    local entries=(
      "grimoires/loa/"
      ".beads/"
      ".loa-version.json"
      ".loa.config.yaml"
    )

    # Root documents (generated, gitignored in stealth)
    local doc_entries=(
      "PROCESS.md"
      "CHANGELOG.md"
      "INSTALLATION.md"
      "CONTRIBUTING.md"
      "SECURITY.md"
      "LICENSE.md"
      "BUTTERFREEZONE.md"
      ".reviewignore"
      ".trufflehog.yaml"
      ".gitleaksignore"
    )

    for entry in "${entries[@]}" "${doc_entries[@]}"; do
      grep -qxF "$entry" "$gitignore" 2>/dev/null || echo "$entry" >> "$gitignore"
    done

    log "Stealth mode applied (${#entries[@]} core + ${#doc_entries[@]} doc entries)"
  fi
}
```

### 3.5 Memory Stack Relocation

All references to `.loa/` as Memory Stack storage must update to `.loa-cache/`.

**Affected files** (identified via grep for `.loa/` path references excluding mount scripts):

| File | Change |
|------|--------|
| `.claude/scripts/mount-loa.sh` | `.loa/` gitignore reference in comments |
| Any memory/embedding scripts | Path constant from `.loa/` to `.loa-cache/` |

**Auto-detection**: On first access, if `.loa-cache/` doesn't exist but `.loa/` does and contains Memory Stack data (not a submodule), auto-migrate:

```bash
# memory-stack-path.sh (utility function sourced by memory scripts)
# Flatline SKP-003: Use atomic mv, verify before delete, never swallow errors
get_memory_stack_path() {
  local new_path=".loa-cache"
  local old_path=".loa"

  # Already using new path
  if [[ -d "$new_path" ]]; then
    echo "$new_path"
    return 0
  fi

  # Old path exists and is NOT a submodule — migrate atomically
  if [[ -d "$old_path" ]] && [[ ! -f "$old_path/.git" ]]; then
    if mv "$old_path" "$new_path" 2>/dev/null; then
      echo "$new_path"
      return 0
    fi
    # mv failed (cross-filesystem) — do NOT auto-migrate with cp
    # Surface the error so the user can resolve it
    echo >&2 "WARNING: Cannot auto-migrate Memory Stack from $old_path to $new_path"
    echo >&2 "Please manually: mv $old_path $new_path"
    echo "$old_path"  # Use old path as fallback
    return 0
  fi

  # Fresh install
  mkdir -p "$new_path"
  echo "$new_path"
}
```

### 3.6 /mount --migrate-to-submodule

New migration subcommand added to `mount-loa.sh` argument parser.

**Workflow** (Flatline SKP-004: discovery phase + dry-run + clean working tree):

```
0. PRE-CHECKS (Flatline SKP-004)
   └── Require clean working tree (git status --porcelain empty)
      └── If dirty → exit "Commit or stash changes before migration"
   └── Create dedicated migration branch: git checkout -b loa/migrate-to-submodule

1. Detect current mode from .loa-version.json
   └── If already submodule → exit "Already in submodule mode"
   └── If not standard → exit "Unknown mode"

2. DISCOVERY PHASE (Flatline SKP-004)
   └── Build framework file manifest from .loa-version.json checksums
   └── Classify .claude/ files:
       ├── FRAMEWORK: matches known framework file hashes → will be removed
       ├── USER_MODIFIED: framework file with different hash → FLAGGED for review
       └── USER_OWNED: settings.json, commands/, overrides/ → preserved
   └── If --dry-run: output classification report and exit
   └── Display plan and require confirmation

3. Create backup
   └── .claude.backup.{timestamp}/ ← cp -r .claude/
   └── chmod 0700 on backup directory

4. Remove framework files from git tracking
   └── Only remove files classified as FRAMEWORK in discovery phase
   └── USER_MODIFIED files: warn and offer choice (keep/remove/backup)
   └── git rm --cached (not -r; enumerate specific paths from manifest)

5. Add submodule
   └── git submodule add $LOA_REMOTE_URL .loa
   └── git submodule update --init .loa

6. Create symlinks via create_symlinks()

7. Restore user-owned files from backup if needed

8. Update .loa-version.json
   └── installation_mode: "submodule"
   └── submodule_path: ".loa"

9. Update .gitignore

10. Commit on migration branch
    └── Commit message includes file counts and classification summary

11. Report summary with rollback instructions:
    └── "To undo: git checkout main && git branch -D loa/migrate-to-submodule"
    └── "Backup at: .claude.backup.{timestamp}/"
```

**Estimated size**: ~180 lines as a new function in `mount-loa.sh`.

### 3.7 /loa Status Boundary Report (FR-5)

Enhance the `/loa` skill to detect installation mode and display footprint:

```
Loa Framework v1.40.0
────────────────────────────
Installation: submodule (.loa/ @ abc1234)
Mode: standard | Cycle: 035 | Sprint: 44

Repository Footprint:
  Tracked (yours):     5 files
  Submodule (Loa):     1 reference → 823 files
  Gitignored (state):  147 files

  Your files:
    CLAUDE.md
    .loa.config.yaml
    .claude/settings.json
    .claude/commands/my-command.md
    .gitmodules
```

Implementation reads `.loa-version.json` for mode detection, runs `git ls-files` for tracked count, and `git submodule status` for submodule info.

### 3.8 /update-loa Submodule Support (FR-7, Flatline IMP-004)

When `installation_mode == "submodule"` in `.loa-version.json`:

```bash
# In update-loa skill:
if [[ "$install_mode" == "submodule" ]]; then
  cd .loa
  git fetch origin
  # If tag specified: git checkout $tag
  # If branch tracking: git pull origin $branch
  cd ..
  git add .loa
  # Verify and reconcile symlinks (IMP-004)
  verify_and_reconcile_symlinks
fi
```

#### 3.8.1 Symlink Verify/Reconcile Algorithm (Flatline IMP-004)

After any submodule update, internal paths may change. Define a reconciliation algorithm:

```bash
# verify_and_reconcile_symlinks()
# Checks every expected symlink, removes dangling, recreates missing.
# Returns: 0 if all healthy, 1 if reconciliation was needed.

verify_and_reconcile_symlinks() {
  local reconciled=0

  # Expected symlinks manifest (authoritative list)
  local -a expected_dirs=(
    ".claude/scripts:../.loa/.claude/scripts"
    ".claude/protocols:../.loa/.claude/protocols"
    ".claude/hooks:../.loa/.claude/hooks"
    ".claude/data:../.loa/.claude/data"
    ".claude/schemas:../.loa/.claude/schemas"
  )

  local -a expected_files=(
    ".claude/loa/CLAUDE.loa.md:../../.loa/.claude/loa/CLAUDE.loa.md"
    ".claude/loa/reference:../../.loa/.claude/loa/reference"
    ".claude/loa/feedback-ontology.yaml:../../.loa/.claude/loa/feedback-ontology.yaml"
    ".claude/loa/learnings:../../.loa/.claude/loa/learnings"
  )

  # Phase 1: Check and fix directory symlinks
  for entry in "${expected_dirs[@]}"; do
    local link="${entry%%:*}"
    local target="${entry#*:}"

    if [[ -L "$link" ]]; then
      # Symlink exists — check if target resolves
      if [[ ! -e "$link" ]]; then
        warn "Dangling symlink: $link → $(readlink "$link")"
        rm -f "$link"
        safe_symlink "$link" "$target"
        log "Reconciled: $link"
        ((reconciled++))
      fi
    elif [[ ! -e "$link" ]]; then
      # Missing entirely — create
      safe_symlink "$link" "$target"
      log "Created missing: $link"
      ((reconciled++))
    fi
    # If it's a real directory (vendored), leave it alone
  done

  # Phase 2: Check file/nested symlinks
  for entry in "${expected_files[@]}"; do
    local link="${entry%%:*}"
    local target="${entry#*:}"

    if [[ -L "$link" ]] && [[ ! -e "$link" ]]; then
      rm -f "$link"
      safe_symlink "$link" "$target"
      log "Reconciled: $link"
      ((reconciled++))
    elif [[ ! -e "$link" ]] && [[ -e "${target}" ]]; then
      mkdir -p "$(dirname "$link")"
      safe_symlink "$link" "$target"
      log "Created missing: $link"
      ((reconciled++))
    fi
  done

  # Phase 3: Check per-skill symlinks
  if [[ -d ".loa/.claude/skills" ]]; then
    for skill_dir in .loa/.claude/skills/*/; do
      local skill_name=$(basename "$skill_dir")
      local link=".claude/skills/$skill_name"
      local target="../../.loa/.claude/skills/$skill_name"

      if [[ -L "$link" ]] && [[ ! -e "$link" ]]; then
        rm -f "$link"
        safe_symlink "$link" "$target"
        log "Reconciled skill: $skill_name"
        ((reconciled++))
      elif [[ ! -e "$link" ]]; then
        safe_symlink "$link" "$target"
        log "Created missing skill: $skill_name"
        ((reconciled++))
      fi
    done
  fi

  if [[ $reconciled -gt 0 ]]; then
    log "Reconciliation complete: $reconciled symlinks fixed"
    return 1
  fi
  return 0
}
```

This runs after every `/update-loa` and can also be invoked standalone for mount health checks.

### 3.9 15-Script Compatibility Audit

Scripts that reference `installation_mode` or check for submodule/standard mode:

| Script | Reference | Change Needed |
|--------|-----------|---------------|
| `mount-loa.sh` | `SUBMODULE_MODE` flag, mode detection | Yes (§3.1) |
| `mount-submodule.sh` | `SUBMODULE_PATH`, symlink creation | Yes (§3.2) |
| `update-loa.sh` | Mode detection for update strategy | Yes (§3.8) |
| `loa-eject.sh` | Mode detection for cleanup | Update eject flow for submodule |
| `verify-mount.sh` | Checks file existence | Add symlink verification |
| `golden-path.sh` | `/loa` status display | Yes (§3.7) |
| `butterfreezone-gen.sh` | Installation mode in output | Update label |
| `beads-health.sh` | Checks `.claude/scripts` exists | Works via symlink |
| `ground-truth-gen.sh` | Reads `.claude/` structure | Works via symlink |
| `run-mode-ice.sh` | Branch safety | No change needed |
| `bridge-orchestrator.sh` | Uses scripts via path | Works via symlink |
| `flatline-orchestrator.sh` | Uses scripts via path | Works via symlink |
| `config-path-resolver.sh` | Path resolution | No change needed |
| `memory-query.sh` | Memory Stack path | Update to `.loa-cache/` |
| `check-permissions.sh` | Permission validation | No change needed |

**Key insight**: Most scripts access framework content via `.claude/scripts/` paths. Since symlinks make these resolve transparently, the majority need NO changes. The compatibility surface is smaller than it appears.

---

## 4. Data Architecture

### 4.1 .loa-version.json

Existing schema, no changes:

```json
{
  "installation_mode": "submodule",
  "submodule_path": ".loa",
  "version": "1.40.0",
  "commit": "abc1234",
  "installed_at": "2026-02-24T12:00:00Z"
}
```

### 4.2 .gitmodules

Created automatically by `git submodule add`:

```ini
[submodule ".loa"]
    path = .loa
    url = https://github.com/0xHoneyJar/loa.git
```

### 4.3 Configuration Changes

No new config keys required. Existing `.loa.config.yaml` works identically in both modes. The `persistence_mode: stealth` key already controls stealth behavior — the expansion (§3.4) just makes it more comprehensive.

---

## 5. Security Architecture

### 5.1 Symlink Traversal Prevention

`safe_symlink()` (mount-submodule.sh:248-258) validates that symlink targets stay within the repository. The `validate_symlink_target()` function (lines 220-243) uses `realpath` to resolve paths and checks they're under the project root:

```bash
validate_symlink_target() {
  local target="$1"
  local resolved
  resolved=$(cd "$(dirname "$target")" 2>/dev/null && pwd -P)/$(basename "$target")
  local repo_root
  repo_root=$(git rev-parse --show-toplevel)

  if [[ "$resolved" != "$repo_root"* ]]; then
    err "Symlink target escapes repository: $target → $resolved"
    return 1
  fi
  return 0
}
```

**No changes needed** — this protection already covers the `.loa/` submodule path.

### 5.2 Submodule Supply Chain Integrity (Flatline SKP-005)

The `LOA_REMOTE_URL` (mount-submodule.sh:46) defaults to `https://github.com/0xHoneyJar/loa.git`. URL verification alone is insufficient — a compromised upstream or DNS interception could serve malicious content.

**Integrity model**:

1. **URL verification**: Confirm .gitmodules URL matches expected origin
2. **Commit recording**: `.loa-version.json` records expected commit hash at install time
3. **Update verification**: `/update-loa` compares current submodule HEAD against recorded hash before accepting changes
4. **Tag pinning**: Default to tagged releases, not branch HEAD

```bash
verify_submodule_integrity() {
  local expected_url="https://github.com/0xHoneyJar/loa.git"

  # Check 1: URL verification
  local actual_url
  actual_url=$(git config --file .gitmodules submodule..loa.url 2>/dev/null)
  if [[ "$actual_url" != "$expected_url" ]]; then
    warn "Submodule URL mismatch:"
    warn "  Expected: $expected_url"
    warn "  Actual:   $actual_url"
    warn "This may indicate the submodule has been retargeted."
    return 1
  fi

  # Check 2: Commit hash verification against .loa-version.json
  if [[ -f "$VERSION_FILE" ]]; then
    local expected_commit recorded_commit
    recorded_commit=$(jq -r '.commit // empty' "$VERSION_FILE" 2>/dev/null)
    if [[ -n "$recorded_commit" ]]; then
      local actual_commit
      actual_commit=$(cd .loa && git rev-parse HEAD 2>/dev/null)
      if [[ "$actual_commit" != "$recorded_commit"* ]]; then
        warn "Submodule commit mismatch:"
        warn "  Recorded: $recorded_commit"
        warn "  Actual:   $actual_commit"
        warn "Run /update-loa to update the recorded commit."
        # Note: mismatch is a warning, not a block — user may have manually updated
      fi
    fi
  fi

  # Check 3: Signed tag verification (optional, if gpg is available)
  if command -v gpg &>/dev/null; then
    local current_tag
    current_tag=$(cd .loa && git describe --exact-match --tags HEAD 2>/dev/null) || true
    if [[ -n "$current_tag" ]]; then
      if cd .loa && git verify-tag "$current_tag" &>/dev/null 2>&1; then
        log "Submodule tag $current_tag: signature verified"
      fi
      cd ..
    fi
  fi

  return 0
}
```

On `/update-loa`, after fetching new content:
- Record new commit hash in `.loa-version.json`
- Log the previous and new commit for auditability
- Run `verify_and_reconcile_symlinks()` (§3.8.1)

### 5.3 Migration Backup

`--migrate-to-submodule` creates a timestamped backup before any changes. The backup captures the entire `.claude/` directory including user-owned files. Permissions: `0700` on backup directory.

### 5.4 Mode Conflict Detection

Existing `check_mode_conflicts()` (mount-loa.sh:1310-1333) prevents accidental mode switches. The only change is updating error messages to reflect the inverted default (§3.1.4). The detection mechanism itself is unchanged.

---

## 6. Testing Strategy

### 6.1 Unit Tests

**New file**: `.claude/scripts/tests/test-mount-submodule-default.bats`

| Test | Scenario | Assertion |
|------|----------|-----------|
| `default_is_submodule` | Run mount-loa.sh with no flags | `SUBMODULE_MODE == true` |
| `vendored_flag` | Run with `--vendored` | `SUBMODULE_MODE == false` |
| `submodule_flag_noop` | Run with `--submodule` | `SUBMODULE_MODE == true` (no-op, deprecation log) |
| `mode_conflict_standard_to_sub` | Existing standard install, no flag | Error with migration hint |
| `mode_conflict_sub_to_vendored` | Existing submodule install, `--vendored` | Error with instructions |

### 6.2 Symlink Verification Tests

**New file**: `.claude/scripts/tests/test-mount-symlinks.bats`

| Test | Scenario | Assertion |
|------|----------|-----------|
| `scripts_symlink` | After submodule mount | `.claude/scripts` → `../.loa/.claude/scripts` |
| `protocols_symlink` | After submodule mount | `.claude/protocols` → `../.loa/.claude/protocols` |
| `hooks_symlink` | After submodule mount | `.claude/hooks` → `../.loa/.claude/hooks` |
| `data_symlink` | After submodule mount | `.claude/data` → `../.loa/.claude/data` |
| `schemas_symlink` | After submodule mount | `.claude/schemas` → `../.loa/.claude/schemas` |
| `claude_loa_md_symlink` | After submodule mount | `.claude/loa/CLAUDE.loa.md` resolves |
| `reference_symlink` | After submodule mount | `.claude/loa/reference/` resolves |
| `at_import_resolves` | After submodule mount | `@.claude/loa/CLAUDE.loa.md` file exists |
| `user_files_not_symlinked` | After submodule mount | `settings.json` is real file |
| `overrides_not_symlinked` | After submodule mount | `.claude/overrides/` is real dir |

### 6.3 Stealth Mode Tests

**New file**: `.claude/scripts/tests/test-stealth-expansion.bats`

| Test | Scenario | Assertion |
|------|----------|-----------|
| `stealth_core_entries` | Apply stealth | 4 core entries in .gitignore |
| `stealth_doc_entries` | Apply stealth | 10 doc entries in .gitignore |
| `stealth_idempotent` | Apply stealth twice | No duplicate entries |
| `standard_no_docs` | Apply standard mode | Doc entries NOT added |

### 6.4 Migration Tests

**New file**: `.claude/scripts/tests/test-migration.bats`

| Test | Scenario | Assertion |
|------|----------|-----------|
| `migration_creates_backup` | Migrate standard→submodule | `.claude.backup.*` exists |
| `migration_preserves_settings` | Migrate with settings.json | settings.json survives |
| `migration_preserves_commands` | Migrate with custom commands | commands/ survives |
| `migration_preserves_overrides` | Migrate with overrides | overrides/ survives |
| `migration_already_submodule` | Migrate when already submodule | Exit with message |
| `migration_dry_run` | Migrate with --dry-run | No files changed |

### 6.5 Memory Stack Relocation Tests

| Test | Scenario | Assertion |
|------|----------|-----------|
| `memory_stack_new_path` | Fresh install | `.loa-cache/` used |
| `memory_stack_auto_migrate` | Old `.loa/` with data | Data moved to `.loa-cache/` |
| `memory_stack_submodule_safe` | `.loa/` is submodule | No migration attempted |

### 6.6 Gitignore Tests

| Test | Scenario | Assertion |
|------|----------|-----------|
| `loa_dir_not_gitignored` | After submodule mount | `.loa/` NOT in .gitignore |
| `loa_cache_gitignored` | After submodule mount | `.loa-cache/` in .gitignore |
| `symlinks_gitignored` | After submodule mount | `.claude/scripts` in .gitignore |

---

## 7. Deployment & Rollout

### 7.1 Version Bump

This is a **minor version bump** (v1.40.0): the change is backward-compatible via `--vendored`, and existing installations continue to work without modification.

### 7.2 Rollout Strategy

1. **Phase 1**: Ship with `SUBMODULE_MODE=true` as default
2. **Phase 2**: Update documentation (INSTALLATION.md, README.md, PROCESS.md)
3. **Phase 3**: Test on THJ internal repos (hub-interface, temple)
4. **Phase 4**: Announce migration path for existing users

### 7.3 Rollback

If submodule-first causes issues:
- Revert `SUBMODULE_MODE=true` → `false` (single line)
- Users who already installed with submodule continue to work
- No data loss in either direction

---

## 8. Sprint Allocation

### Sprint 1 (P0 — Foundation, ~190 lines changed)

| Task | File | Lines (est.) |
|------|------|-------------|
| Flip `SUBMODULE_MODE` default | mount-loa.sh:183 | 1 |
| Add `--vendored` flag | mount-loa.sh:212-214 | 8 |
| Update help text | mount-loa.sh:227-234 | 15 |
| Update mode conflict messages | mount-loa.sh:1310-1333 | 20 |
| Add missing symlinks (hooks, data, reference) | mount-submodule.sh:300+ | 35 |
| Fix preflight Memory Stack detection | mount-submodule.sh:131-166 | 20 |
| .gitignore collision fix (.loa → .loa-cache) | .gitignore:75 | 5 |
| Symlink gitignore entries | .gitignore | 12 |
| Unit tests (default, flags, conflicts) | test-mount-submodule-default.bats | ~80 |

### Sprint 2 (P1 — Migration + Polish, ~490 lines new/changed)

| Task | File | Lines (est.) |
|------|------|-------------|
| `--migrate-to-submodule` command | mount-loa.sh (new function) | ~120 |
| apply_stealth() expansion | mount-loa.sh:985-1009 | 30 |
| Memory Stack relocation utility | mount-submodule.sh or new file | 40 |
| /loa status boundary report | golden-path.sh or loa skill | 50 |
| /update-loa submodule support | update-loa skill | 40 |
| Documentation updates | INSTALLATION.md, README.md, PROCESS.md | 100 |
| Migration tests | test-migration.bats | ~60 |
| Stealth tests | test-stealth-expansion.bats | ~50 |

### Sprint 3 (P1 — Hardening, ~305 lines new/changed)

| Task | File | Lines (est.) |
|------|------|-------------|
| Symlink verification tests | test-mount-symlinks.bats | ~100 |
| Memory Stack relocation tests | test suite | ~40 |
| Gitignore tests | test suite | ~30 |
| Submodule URL verification | mount-submodule.sh or update-loa | 25 |
| 15-script compatibility audit | Various | ~50 |
| loa-eject.sh submodule support | loa-eject.sh | 40 |
| CI/CD documentation | INSTALLATION.md | 20 |

---

## 9. Risks and Mitigations

| Risk | Severity | Likelihood | Mitigation |
|------|----------|------------|------------|
| `@.claude/loa/CLAUDE.loa.md` breaks | CRITICAL | ZERO (design verified) | Submodule at `.loa/` preserves symlink chain (§2.3) |
| Users unfamiliar with submodules | MEDIUM | HIGH | Docs, `/loa` status, error messages with instructions |
| CI without `--recurse-submodules` | HIGH | MEDIUM | Document in INSTALLATION.md, add to CI examples |
| Memory Stack data loss during relocation | LOW | LOW | Auto-detect + copy before remove (§3.5) |
| Windows symlink issues | MEDIUM | LOW | Already handled by mount-submodule.sh (`safe_symlink`) |
| Existing `.loa/` directory blocks submodule add | MEDIUM | MEDIUM | Preflight auto-relocates Memory Stack (§3.2.4) |

---

## 10. Resolved Design Decisions

| ID | Decision | Alternatives Considered | Rationale |
|----|----------|------------------------|-----------|
| D-012 | Submodule at `.loa/` (not `.claude/loa`) | `.claude/loa` (PRD proposal) | @-import chain breaks with `.claude/loa` (§2.3) |
| D-013 | Memory Stack at `.loa-cache/` (project-local) | `~/.cache/loa/` (user-global) | Multi-project isolation |
| D-014 | `--vendored` flag for backward compat | `--standard`, `--copy` | "Vendored" is the industry term for bundled dependencies |
| D-015 | Root docs gitignored in stealth | Always gitignored | Non-stealth users may want docs committed |

---

## 11. Dependency Map

```
Sprint 1 (Foundation)
  ├── mount-loa.sh default flip (§3.1)
  ├── mount-submodule.sh missing symlinks (§3.2)
  ├── .gitignore collision fix (§3.3)
  └── Unit tests (§6.1)

Sprint 2 (Migration + Polish)
  ├── Migration command (§3.6)     ← depends on Sprint 1
  ├── Stealth expansion (§3.4)
  ├── Memory Stack relocation (§3.5)
  ├── /loa status (§3.7)
  ├── /update-loa (§3.8)
  └── Documentation

Sprint 3 (Hardening)
  ├── Symlink verification (§6.2)  ← depends on Sprint 1
  ├── 15-script audit (§3.9)      ← depends on Sprint 2
  ├── loa-eject update
  └── CI/CD documentation
```
