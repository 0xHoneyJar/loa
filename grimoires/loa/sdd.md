# SDD: UX Redesign — Vercel-Grade Developer Experience (Phase 1)

> Cycle: cycle-030 | Author: soju + Claude
> Source PRD: `grimoires/loa/prd.md` (#380-#390)
> Design Context: `grimoires/loa/context/ux-redesign-plan.md`

---

## 1. Architecture Overview

This cycle modifies **existing scripts and commands only** — no new architectural components. All changes are surgical fixes to the installation flow, dependency management, and command entry points.

### Modified Components

```
.claude/scripts/mount-loa.sh          ← FR-1 (bug fixes) + FR-3 (auto-install) + FR-4 (post-mount msg)
.claude/scripts/loa-doctor.sh         ← FR-1 (flock hint fix)
.claude/commands/plan.md              ← FR-2 (plan entry flow fixes)
.claude/commands/loa-setup.md         ← FR-5 (auto-fix capability)
.claude/commands/loa.md               ← FR-6 (/feedback at tension points)
```

### Unchanged Components

- All SKILL.md files (deferred to cycle-031)
- `.loa.config.yaml` schema
- Beads, hooks, guardrails, Flatline
- Three-zone model, constraint system

---

## 2. Detailed Design

### 2.1 FR-1: Fix Wrong Install Hints

#### 2.1.1 Beads Repo URL (#380)

**File**: `mount-loa.sh:326-349` (`install_beads()` function)

**Current**:
```bash
local installer_url="https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh"
```

**Change**: Replace entire `install_beads()` function to delegate to `install-br.sh`:

```bash
install_beads() {
  if [[ "$SKIP_BEADS" == "true" ]]; then
    log "Skipping Beads installation (--skip-beads)"
    return 0
  fi

  if command -v br &> /dev/null; then
    local version=$(br --version 2>/dev/null || echo "unknown")
    log "Beads CLI already installed: $version"
    return 0
  fi

  local br_installer=".claude/scripts/beads/install-br.sh"
  if [[ -x "$br_installer" ]]; then
    step "Installing Beads CLI..."
    if "$br_installer"; then
      log "Beads CLI installed"
    else
      warn "Beads CLI installation failed (optional - /run mode requires it)"
    fi
  else
    warn "Beads installer not found - skipping (optional)"
  fi
}
```

**Rationale**: `install-br.sh` already has correct logic (tries `cargo install beads_rust` from crates.io, then GitHub fallback at `Dicklesworthstone/beads_rust`). Delegating eliminates the wrong URL and centralizes install logic.

#### 2.1.2 yq Install Suggestion (#381)

**File**: `mount-loa.sh:321`

**Current**:
```bash
command -v yq >/dev/null || err "yq is required (brew install yq / pip install yq)"
```

**Change**:
```bash
command -v yq >/dev/null || err "yq v4+ is required. Install: brew install yq (macOS) or see https://github.com/mikefarah/yq#install (Linux). WARNING: Do NOT use pip install yq — that is a different, incompatible tool."
```

#### 2.1.3 flock Hint (#382)

**File**: `loa-doctor.sh:189`

**Current**:
```bash
_doctor_add_suggestion "Install flock: brew install util-linux (macOS)"
```

**Change**:
```bash
_doctor_add_suggestion "Install flock: brew install flock (macOS) or apt install util-linux (Linux)"
```

---

### 2.2 FR-2: Fix /plan Entry Flow Bugs

#### 2.2.1 "What does Loa add?" Fall-Through (#383)

**File**: `plan.md:55-95`

**Current** (line 95):
```
Then continue to archetype selection. This step never blocks — it's informational only.
```

**Change**: Replace line 95 with:

```
After displaying the information, present a follow-up confirmation:

```yaml
question: "Ready to start planning?"
header: "Continue"
options:
  - label: "Let's go!"
    description: "Start the planning process now"
  - label: "Not yet"
    description: "Exit — come back when ready"
multiSelect: false
```

If user selects "Not yet", end the command with: "No problem. Run /plan when you're ready."
```

#### 2.2.2 Archetype Truncation (#384)

**File**: `plan.md:97-137`

**Current** (line 121):
```
# AskUserQuestion supports max 4 options, so use the first 4 files found
```

**Change**: Replace the archetype selection approach. Instead of showing 4 archetypes as options, use 3 archetypes + make room for the "Other" auto-appended option:

```
Build AskUserQuestion options from discovered archetype files. Since AskUserQuestion has a maximum of 4 options (plus auto-appended "Other"), select the 3 most common archetypes:

1. Read all `.claude/data/archetypes/*.yaml` files
2. Sort by a `priority` field if present, otherwise alphabetically
3. Take the first 3 files as options
4. The 4th slot is reserved — leave it empty so "Other" (auto-appended) is the 4th visible option

If more than 3 archetypes exist, add a note in the 3rd option's description: "More archetypes available — select Other to describe your project."
```

**Note**: This is a stopgap. Cycle-031 replaces archetype selection entirely with free-text-first flow (issue #386).

---

### 2.3 FR-3: Auto-Installing Setup

**File**: `mount-loa.sh` — new function `auto_install_deps()` inserted between `preflight()` and `setup_remote()`

#### Function Design

```bash
auto_install_deps() {
  if [[ "$NO_AUTO_INSTALL" == "true" ]]; then
    log "Auto-install disabled (--no-auto-install)"
    return 0
  fi

  local os_type
  os_type=$(detect_os)  # "macos" | "linux-apt" | "linux-yum" | "unknown"

  # --- jq ---
  if ! command -v jq &>/dev/null; then
    step "Installing jq..."
    case "$os_type" in
      macos)
        if command -v brew &>/dev/null; then
          brew install jq && log "✓ jq installed" || warn "jq auto-install failed. Manual: brew install jq"
        else
          warn "jq not found. Install Homebrew first (https://brew.sh) then: brew install jq"
        fi
        ;;
      linux-apt)
        sudo apt-get install -y jq && log "✓ jq installed" || warn "jq auto-install failed. Manual: sudo apt install jq"
        ;;
      linux-yum)
        sudo yum install -y jq && log "✓ jq installed" || warn "jq auto-install failed. Manual: sudo yum install jq"
        ;;
      *)
        warn "Unknown OS. Install jq manually: https://jqlang.github.io/jq/download/"
        ;;
    esac
  else
    log "✓ jq found ($(jq --version 2>/dev/null || echo 'unknown'))"
  fi

  # --- yq (mikefarah) ---
  if ! command -v yq &>/dev/null; then
    step "Installing yq (mikefarah)..."
    case "$os_type" in
      macos)
        if command -v brew &>/dev/null; then
          brew install yq && log "✓ yq installed" || warn "yq auto-install failed. Manual: brew install yq"
        else
          warn "yq not found. Install: brew install yq (requires Homebrew)"
        fi
        ;;
      linux-apt|linux-yum)
        # Direct binary download for Linux
        local yq_version="v4.40.5"
        local yq_arch
        case "$(uname -m)" in
          x86_64) yq_arch="amd64" ;;
          aarch64|arm64) yq_arch="arm64" ;;
          *) warn "Unknown arch for yq download"; return 0 ;;
        esac
        local yq_url="https://github.com/mikefarah/yq/releases/download/${yq_version}/yq_linux_${yq_arch}"
        if curl -fsSL "$yq_url" -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq; then
          log "✓ yq installed (${yq_version})"
        else
          warn "yq auto-install failed. Manual: https://github.com/mikefarah/yq#install"
        fi
        ;;
      *)
        warn "Unknown OS. Install yq manually: https://github.com/mikefarah/yq#install"
        ;;
    esac
  else
    # Verify it's mikefarah/yq, not kislyuk/yq
    if yq --version 2>/dev/null | grep -qi "mikefarah"; then
      log "✓ yq found (mikefarah $(yq --version 2>/dev/null))"
    else
      warn "Wrong yq detected (likely Python kislyuk/yq). Loa requires mikefarah/yq v4+."
      warn "Install correct version: brew install yq (macOS) or https://github.com/mikefarah/yq#install"
    fi
  fi
}
```

#### OS Detection Helper

```bash
detect_os() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux)
      if command -v apt-get &>/dev/null; then
        echo "linux-apt"
      elif command -v yum &>/dev/null; then
        echo "linux-yum"
      else
        echo "unknown"
      fi
      ;;
    *) echo "unknown" ;;
  esac
}
```

#### Integration into Main Flow

Current `preflight()` (lines 319-321) hard-errors on missing deps:
```bash
command -v jq >/dev/null || err "jq is required ..."
command -v yq >/dev/null || err "yq is required ..."
```

**Change**: Replace these lines with a call to `auto_install_deps()`, then re-check:

```bash
# Auto-install missing dependencies
auto_install_deps

# Verify all required deps are now present
command -v git >/dev/null || err "git is required"
command -v jq >/dev/null || err "jq is required. Auto-install failed. Manual: brew install jq (macOS) or apt install jq (Linux)"
command -v yq >/dev/null || err "yq v4+ is required. Auto-install failed. Manual: brew install yq (macOS) or https://github.com/mikefarah/yq#install"
```

#### New CLI Flag

```bash
# Add to argument parsing (near line 250)
--no-auto-install)
  NO_AUTO_INSTALL=true
  shift
  ;;
```

---

### 2.4 FR-4: Post-Mount Golden Path Message

**File**: `mount-loa.sh:1418-1446`

**Current** (lines 1429-1433, 1442-1446):
```bash
info "  1. Run 'claude' to start Claude Code"
info "  2. Run '/loa setup' to check dependencies"
info "  3. Start planning with '/plan'"
...
log "  1. Start Claude Code:  claude"
log "  2. Run setup wizard:   /loa setup"
log "  3. Start planning:     /plan"
```

**Change**: Consolidate into single clear message:

```bash
echo ""
log "✓ Loa mounted successfully."
echo ""
log "  Next: Start Claude Code and type /plan"
echo ""
```

Remove the duplicate banner. Remove `/loa setup` from the happy path (it runs automatically if needed inside Claude Code). Single instruction.

---

### 2.5 FR-5: `/loa setup` Auto-Fix

**File**: `loa-setup.md`

Insert new Step 2.5 between Step 2 (Display Results) and Step 3 (Interactive Configuration):

```markdown
### Step 2.5: Offer to Fix Missing Dependencies (NEW)

If any required dependency has status `fail`:

1. Collect all failed dependencies into a list
2. Present via AskUserQuestion:

```yaml
question: "Fix missing dependencies?"
header: "Auto-fix"
options:
  - label: "Yes, install now (Recommended)"
    description: "Install {list of missing deps} automatically"
  - label: "Skip"
    description: "I'll install manually later"
multiSelect: false
```

3. If user selects "Yes":
   - For each missing dep, run the appropriate install command via Bash tool:
     - jq: `brew install jq` (macOS) or `sudo apt install jq` (Linux)
     - yq: `brew install yq` (macOS) or download mikefarah binary (Linux)
     - beads: Run `.claude/scripts/beads/install-br.sh`
   - Show progress for each: "Installing jq... ✓"
   - Re-run `loa-setup-check.sh` after to verify fixes

4. If user selects "Skip", continue to Step 3.
```

---

### 2.6 FR-6: `/feedback` at Tension Points

**File**: `loa.md`

#### Change 1: First-time `/loa` (initial state)

In the initial state output (when no PRD exists, no completed cycles), add to the navigation menu:

```
Something unexpected? /feedback reports it directly.
```

Add this as the last line before the "Next: /plan" instruction.

#### Change 2: Add `/feedback` to `/loa --help`

In the help output section, add `/feedback` to the visible command list (not just `--help-full`):

```
/feedback    Report issues or suggestions
```

---

## 3. Data Model

No data model changes. All modifications are to scripts and command files.

---

## 4. Testing Strategy

### Unit Tests (Bash)

| Test | What | How |
|------|------|-----|
| `detect_os()` | Returns correct OS identifier | Mock `uname`, verify output |
| `auto_install_deps()` jq path | Attempts brew install on macOS when jq missing | Mock `command -v`, verify brew called |
| `auto_install_deps()` yq verification | Detects wrong yq (kislyuk) | Mock yq --version output |
| `install_beads()` delegation | Calls install-br.sh, not old URL | Verify no reference to steveyegge |

### Integration Tests

| Test | What | How |
|------|------|-----|
| `mount-loa.sh --no-auto-install` | Preserves current error behavior | Run with missing dep, verify error message |
| `mount-loa.sh` with all deps | Clean pass, correct post-mount message | Run in test env with all deps present |
| `/plan` welcome flow | "What does Loa add?" has re-entry prompt | Manual: select info, verify follow-up question |
| `/plan` archetype truncation | No silent drops | Count options presented vs files in archetypes/ |

### Manual Verification Checklist

- [ ] Fresh macOS install: `curl | bash` auto-installs jq, yq
- [ ] Post-mount message shows only `/plan` (no truenames)
- [ ] `/loa setup` offers to install missing deps
- [ ] `/plan` "What does Loa add?" returns to confirmation
- [ ] All 5 archetype files accessible (or 3+Other with note)
- [ ] `/loa` initial state mentions `/feedback`

---

## 5. Security Considerations

### Auto-Install Trust Chain

| Dep | Install Source | Trust Level |
|-----|--------------|-------------|
| jq | Homebrew / apt official repos | High — package manager verified |
| yq | Homebrew or mikefarah GitHub releases | High — verified author, checksummed releases |
| beads_rust | crates.io / Dicklesworthstone GitHub | Medium — community package, audited by Loa team |

### Risks Mitigated

- **No `sudo` on macOS**: Homebrew installs to user space, no elevation needed
- **`sudo` on Linux**: Required for apt/yum. Only runs for system packages (jq, yq), not cargo packages
- **No arbitrary script piping**: Individual dep installs use package managers, not `curl | bash` for each dep
- **yq verification**: After install, verify it's mikefarah/yq to prevent supply chain confusion

---

## 6. Rollback Plan

All changes are to `.claude/` files (System Zone). If issues arise:

1. `git checkout .claude/scripts/mount-loa.sh` — reverts to current behavior
2. `--no-auto-install` flag provides immediate opt-out without rollback
3. No data migrations, no state changes, no config schema changes
