# PRD: Minimal Footprint by Default — Submodule-First Installation

> Cycle: cycle-035 | Author: soju + Claude (Bridgebuilder)
> Predecessor: cycle-034 (Declarative Execution Router + Adaptive Multi-Pass)
> Source: [#402](https://github.com/0xHoneyJar/loa/issues/402) (Minimal footprint by default)
> Related: [#393](https://github.com/0xHoneyJar/loa/issues/393) (Stealth mode gap), [#110](https://github.com/0xHoneyJar/loa/issues/110) (Installation UX)
> Cross-Ecosystem: [loa-finn#66](https://github.com/0xHoneyJar/loa-finn/issues/66) (Launch readiness), [loa-finn#31](https://github.com/0xHoneyJar/loa-finn/issues/31) (Hounfour RFC)
> Priority: P0 — Prerequisite for production adoption and multi-runtime distribution

---

## 1. Problem Statement

Loa's default installation method (`/mount`) copies ~800 framework files directly into the user's `.claude/` directory. Combined with state zone artifacts (`grimoires/`, `.ck/`, `.beads/`), a typical Loa-managed repository accumulates **2,600+ framework-related tracked files** (per #393 audit of hub-interface).

This creates three concrete problems:

### 1.1 Repository Hygiene Violation

THJ members work on "libraries, protocols and other standards where the hygiene of the repo is essential" (from #402). The current installation model makes Loa-managed repositories unsuitable for:
- **Open source libraries**: Contributors see 2,600 framework files alongside application code
- **Regulated codebases**: Compliance teams flag unaudited framework files
- **CI/CD pipelines**: 800 framework files inflate Docker build contexts and checkout times

### 1.2 Boundary Confusion

The Three-Zone Model (System/State/App) exists in CLAUDE.md instructions but not in git reality. Users cannot distinguish "what's mine" from "what's Loa's" using standard git tooling. `git log --stat` conflates framework maintenance with application development.

### 1.3 Distribution Prerequisite

The Hounfour RFC (loa-finn#31) describes multi-runtime distribution where Loa runs in contexts beyond Claude Code. The current installation model — copying 800 files into `.claude/` — is untenable for server runtimes, CI pipelines, and containerized deployments. The launch readiness analysis (loa-finn#66) identifies this as an adoption blocker: 52 sprints of infrastructure are useless if the framework's footprint makes it inappropriate for production repositories.

### Current State: What Already Exists

Importantly, the infrastructure for submodule installation **already exists**:
- `mount-submodule.sh` (619 lines): Complete submodule installation with secure symlink creation
- `mount-loa.sh` routing: `--submodule` flag triggers `route_to_submodule()` (line 1463)
- Mode detection: `.loa-version.json` tracks `installation_mode: "standard"|"submodule"`
- Symlink security: `safe_symlink()` prevents directory traversal attacks

The problem is not missing capability. It is **wrong defaults**: submodule mode requires opt-in (`--submodule`), while the invasive mode requires no flag at all.

> Sources: #402 (user request), #393 (quantified footprint), loa-finn#66 (launch readiness), loa-finn#31 (distribution strategy)

---

## 2. Vision

A Loa installation where **the user's repository remains the user's repository**. The framework exists as a versioned reference (git submodule) rather than embedded content. State artifacts are ephemeral and gitignored by default. From `git status`, a Loa-managed project looks like any other project — with a single `.gitmodules` entry and a user-owned config file as the only framework-related tracked content.

The Stripe philosophy applied to developer tooling: **minimal surface area, maximum capability**.

---

## 3. Goals and Success Metrics

### 3.1 Primary Goals

| Goal | Metric | Target |
|------|--------|--------|
| G1: Submodule as default | New `/mount` installations use submodule | 100% of new installs |
| G2: Minimal tracked files | Framework-related tracked files in user repo | ≤ 5 files |
| G3: Comprehensive gitignore | All regenerable/ephemeral state gitignored by default | Zero `.ck/`, `.run/`, state zone in `git status` |
| G4: Migration path | Existing standard installations can migrate | One-command migration |
| G5: Backward compatibility | Standard (vendored) mode still available | `--vendored` flag preserves old behavior |

### 3.2 Non-Goals

- **N1**: Removing standard (vendored) installation entirely — it remains available via `--vendored`
- **N2**: Changing the Three-Zone Model semantics — the zones remain; only their git tracking changes
- **N3**: Restructuring `.claude/` directory layout — symlinks preserve the existing layout
- **N4**: Memory Stack migration — `.loa/` path collision is resolved by relocating Memory Stack, not redesigning it

### 3.3 Success Criteria

After this cycle, a fresh `/mount` on a new repository should produce:

```
# Tracked files (committed to git):
.gitmodules              # Submodule reference
.loa                     # Submodule directory (framework)
.claude/settings.json    # User's Claude Code settings (if exists)
.claude/commands/        # User's custom commands (if any)
.loa.config.yaml         # User's Loa configuration
CLAUDE.md                # User's project instructions

# Everything else: gitignored by default
```

---

## 4. User Stories

### US-1: New Project Setup (Library Author)

**As** a library author setting up a new open-source project,
**I want** Loa installed as a git submodule by default,
**So that** my repository's git history shows only my code changes, not framework files.

**Acceptance Criteria:**
- Running `/mount` (without flags) installs Loa as a submodule at `.loa/`
- Only `.gitmodules`, `.loa`, `.loa.config.yaml`, and `CLAUDE.md` are tracked
- `git log` shows no framework file changes after initial setup
- `git clone --recurse-submodules` reproduces the full environment

### US-2: Existing Project Migration

**As** an existing Loa user with standard (vendored) installation,
**I want** a migration command to convert to submodule mode,
**So that** I can adopt minimal footprint without losing my configuration.

**Acceptance Criteria:**
- `/mount --migrate-to-submodule` converts an existing standard installation
- User config (`.loa.config.yaml`) is preserved unchanged
- User overrides (`.claude/overrides/`) are preserved unchanged
- Custom commands (`.claude/commands/`) are preserved unchanged
- Framework files move to submodule reference; originals removed from tracking
- A backup is created before migration

### US-3: Stealth Mode Completeness

**As** a developer using stealth mode,
**I want** ALL regenerable state gitignored automatically,
**So that** `.ck/` caches (2,400+ files) never appear in my repository.

**Acceptance Criteria:**
- `.ck/` is gitignored in ALL modes (not just stealth) — this is a bug fix (#393)
- Stealth mode adds comprehensive gitignore entries beyond the current 4
- Root document files (PROCESS.md, CHANGELOG.md, etc.) are gitignored in stealth
- `grimoires/loa/` is fully gitignored in stealth

### US-4: Version Management

**As** a team lead,
**I want** to pin and upgrade the Loa framework version,
**So that** I control when the framework updates without worrying about untracked file drift.

**Acceptance Criteria:**
- Submodule pins to a specific commit/tag
- `/update-loa` runs `git submodule update --remote` for submodule installations
- Version shown in `/loa` status output includes submodule commit hash
- Downgrade possible via `git checkout <tag>` in submodule

### US-5: CI/CD Compatibility

**As** a DevOps engineer,
**I want** Loa to work in CI pipelines with `--recurse-submodules`,
**So that** automated builds can use Loa without special configuration.

**Acceptance Criteria:**
- `git clone --recurse-submodules` produces a working Loa environment
- GitHub Actions / GitLab CI examples provided for common patterns
- Shallow clone (`--depth 1`) works for CI optimization

---

## 5. Functional Requirements

### FR-1: Default Installation Mode Switch

**Priority: P0**

Modify `/mount` (`mount-loa.sh`) to use submodule mode as default:

| Current Behavior | New Behavior |
|-----------------|--------------|
| `--submodule` flag triggers submodule mode | Submodule mode is default (no flag needed) |
| No flag = standard (vendored) mode | `--vendored` flag triggers standard mode |
| Standard mode creates 800+ files | Default creates submodule + symlinks |

**Technical Details:**
- Flip `SUBMODULE_MODE` default from `false` to `true` in `mount-loa.sh:~L40`
- Add `--vendored` flag alias for `--no-submodule`
- Update help text and progress messages
- Detect existing installation mode and prevent accidental mode switch

### FR-2: .loa/ Path Collision Resolution

**Priority: P0**

The current `.loa/` path is used by Memory Stack (vector embeddings, gitignored). The submodule installation also targets `.loa/` via `mount-submodule.sh`. This collision must be resolved.

**Resolution:** Submodule stays at `.loa/` (mount-submodule.sh's existing design). Memory Stack relocates to `.loa-cache/`.

| Component | Current Path | New Path |
|-----------|-------------|----------|
| Submodule | `.loa/` (mount-submodule.sh) | `.loa/` (unchanged) |
| Memory Stack | `.loa/` (gitignored) | `.loa-cache/` (gitignored) |
| .gitignore | `.loa/` on line 75 | REMOVED (submodule must be tracked) |

**Why `.loa/` (not `.claude/loa` as originally proposed)**:
- `.claude/loa` breaks the `@.claude/loa/CLAUDE.loa.md` import in CLAUDE.md — the submodule root would be the Loa repo, placing CLAUDE.loa.md at `.claude/loa/.claude/loa/CLAUDE.loa.md` (nested), not at the expected import path
- mount-submodule.sh already uses `.loa/` (SUBMODULE_PATH, line 50) — no retargeting needed
- Symlinks from `.claude/` into `.loa/` already implemented (create_symlinks(), lines 260-359)
- Memory Stack relocation to `.loa-cache/` is the simpler collision resolution

> **SDD Correction**: The original PRD proposed `.claude/loa`. Architectural analysis during SDD (see sdd.md §2.3) found this breaks the @-import chain. Decision D-012 updated accordingly.

### FR-3: Comprehensive .gitignore by Default

**Priority: P0**

Expand default `.gitignore` coverage for ALL installation modes:

| Path | Current State | Required State | Rationale |
|------|--------------|----------------|-----------|
| `.ck/` | Gitignored (line 85) | Gitignored (keep) | Regenerable cache — already correct |
| `.run/` | Gitignored (line 71) | Gitignored (keep) | Ephemeral state — already correct |
| `.beads/` | Gitignored (line 202) | Gitignored (keep) | Already correct |
| `grimoires/loa/prd*.md` | Gitignored (line 116) | Gitignored (keep) | Already correct |
| `.loa-cache/` | N/A (new) | Gitignored | Relocated Memory Stack |
| Root docs (stealth) | NOT gitignored | Gitignored in stealth | PROCESS.md, CHANGELOG.md, etc. |

**Stealth mode expansion:**

Current `apply_stealth()` adds 4 entries. Expand to comprehensive list:

```gitignore
# Stealth mode additions (beyond standard .gitignore)
PROCESS.md
CHANGELOG.md
INSTALLATION.md
CONTRIBUTING.md
SECURITY.md
LICENSE.md
BUTTERFREEZONE.md
.reviewignore
.trufflehog.yaml
.gitleaksignore
```

### FR-4: Migration Command

**Priority: P1**

Add `/mount --migrate-to-submodule` for existing standard installations:

**Workflow:**
1. Detect current installation mode from `.loa-version.json`
2. If already submodule → exit with message
3. Create backup of current `.claude/` → `.claude.backup.{timestamp}/`
4. Record user-owned files: `settings.json`, `commands/`, `overrides/`
5. Remove framework-managed files from git tracking (`git rm --cached`)
6. Add submodule at `.loa/`
7. Create symlinks from framework directories to submodule
8. Restore user-owned files to their original locations
9. Update `.loa-version.json` with `installation_mode: "submodule"`
10. Update `.gitignore` with new entries
11. Report migration summary

**Safety:**
- Backup created before any changes
- Dry-run mode (`--dry-run`) shows what would change
- Rollback instruction provided in migration output

### FR-5: /loa Status Boundary Report

**Priority: P1**

Enhance `/loa` status to show clear framework boundary information:

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

### FR-6: Documentation Updates

**Priority: P1**

Update all installation documentation to submodule-first:

| Document | Changes |
|----------|---------|
| `INSTALLATION.md` | Rewrite Method 1 as submodule, add Method 3 as vendored (legacy) |
| `README.md` | Update quickstart to show submodule install |
| `PROCESS.md` | Update "Getting Started" section |
| `.claude/skills/mounting-framework/SKILL.md` | Update default behavior documentation |
| `/update-loa` skill | Document submodule update flow |

### FR-7: /update-loa Submodule Support

**Priority: P1**

When installation mode is `submodule`, `/update-loa` should:

1. Detect installation mode from `.loa-version.json`
2. If submodule: `cd .loa && git fetch && git checkout <tag>`
3. If standard: existing behavior (git checkout from upstream)
4. Verify symlinks are still valid after update
5. Run integrity checks on updated content

---

## 6. Technical Constraints

### C-1: Git Submodule Limitations
- Requires `--recurse-submodules` on `git clone` (documented, not fixable)
- Submodule detached HEAD can confuse users unfamiliar with git internals
- GitHub PR diffs show submodule pointer changes, not file diffs

### C-2: Symlink Platform Compatibility
- `mount-submodule.sh` already handles this with `safe_symlink()`
- Windows requires `git config core.symlinks true` or falls back to copies
- CI environments may need explicit symlink support

### C-3: Claude Code Settings Discovery
- Claude Code discovers `.claude/` via standard path resolution
- Symlinks from `.claude/skills/` → `../../.loa/.claude/skills/` must resolve correctly
- The `@.claude/loa/CLAUDE.loa.md` import path must work through symlink at `.claude/loa/CLAUDE.loa.md`

### C-4: Backward Compatibility
- Existing standard installations must continue to work without modification
- `--vendored` flag preserves exact current behavior
- Mode detection prevents accidental mode switches

### C-5: Path Collision Resolution
- `.loa/` currently used by Memory Stack (gitignored)
- Submodule cannot target `.loa/` without breaking Memory Stack
- Resolution: submodule stays at `.loa/`, Memory Stack relocates to `.loa-cache/`

---

## 7. Architecture Considerations

### 7.1 Submodule Mount Point: `.loa/`

The submodule lives at `.loa/` (project root), NOT inside `.claude/`. This is required because `.claude/loa/` is an existing directory containing `CLAUDE.loa.md` (the @-import target) — placing the submodule there would break the import chain. Symlinks bridge from `.claude/` into `.loa/`.

> **Note**: Originally proposed as `.claude/loa`. Corrected during SDD analysis — see sdd.md §2.3 for the @-import resolution chain that constrains this.

### 7.2 Symlink Structure

```
.loa/                          # Git submodule (Loa repository)
│ └── .claude/
│     ├── skills/
│     ├── scripts/
│     ├── protocols/
│     ├── hooks/
│     ├── data/
│     ├── schemas/
│     └── loa/                 # CLAUDE.loa.md and reference docs
│
.claude/
├── scripts    → ../.loa/.claude/scripts     # Directory symlink
├── skills/                                   # Per-skill symlinks
│   ├── mounting-framework → ../../.loa/.claude/skills/mounting-framework
│   └── ...
├── protocols  → ../.loa/.claude/protocols   # Directory symlink
├── hooks      → ../.loa/.claude/hooks       # Directory symlink
├── data       → ../.loa/.claude/data        # Directory symlink
├── schemas    → ../.loa/.claude/schemas     # Directory symlink
├── loa/                                      # Real directory (NOT symlinked)
│   ├── CLAUDE.loa.md → ../../.loa/.claude/loa/CLAUDE.loa.md  # File symlink
│   ├── reference → ../../.loa/.claude/loa/reference            # Dir symlink
│   └── ...
├── settings.json          # User-owned (NOT symlinked)
├── commands/              # User-owned (NOT symlinked)
└── overrides/             # User-owned (NOT symlinked)
```

### 7.3 Installation Mode Detection

`.loa-version.json` already supports mode detection:

```json
{
  "installation_mode": "submodule",
  "submodule_path": ".loa",
  "version": "1.40.0",
  "commit": "abc1234",
  "installed_at": "2026-02-24T12:00:00Z"
}
```

### 7.4 Version Pinning

Submodule mode provides natural version pinning:
- Pin to tag: `cd .loa && git checkout v1.40.0`
- Pin to commit: `cd .loa && git checkout abc1234`
- Track branch: `git submodule set-branch --branch main .loa`
- Update: `git submodule update --remote .loa`

---

## 8. Security Considerations

### S-1: Symlink Traversal Prevention
- `safe_symlink()` in `mount-submodule.sh` already validates targets
- Symlinks must not escape `.claude/` directory
- Integrity checks verify symlink targets after creation

### S-2: Submodule Source Verification
- Submodule URL must match expected Loa repository
- Commit hash provides integrity verification (stronger than checksums)
- `/update-loa` should verify remote URL hasn't been tampered with

### S-3: Migration Backup
- Full backup before any migration operation
- Backup includes all user-owned files
- Backup path communicated clearly in output

---

## 9. Risks and Mitigations

| Risk | Severity | Likelihood | Mitigation |
|------|----------|------------|------------|
| Users unfamiliar with git submodules | MEDIUM | HIGH | Clear documentation, `/loa` status shows submodule state |
| CI/CD breaks without `--recurse-submodules` | HIGH | MEDIUM | Document CI patterns, add clone command to INSTALLATION.md |
| Symlink issues on Windows | MEDIUM | LOW | Fallback to copies, document `core.symlinks` |
| Memory Stack path migration breaks existing installs | LOW | LOW | Graceful detection, auto-migrate on first use |
| Submodule at `.loa/` creates confusion with former Memory Stack path | LOW | MEDIUM | Clear documentation, `/loa` boundary report |

---

## 10. Scope and Prioritization

### Sprint 1 (P0 — Foundation)
- FR-1: Flip default to submodule mode in `mount-loa.sh`
- FR-2: Resolve `.loa/` path collision (Memory Stack → `.loa-cache/`)
- FR-3: Expand `.gitignore` and stealth mode coverage
- Update `mount-submodule.sh` missing symlinks (hooks, data, reference)
- Comprehensive test coverage for new default behavior

### Sprint 2 (P1 — Migration + Polish)
- FR-4: Migration command (`--migrate-to-submodule`)
- FR-5: `/loa` status boundary report
- FR-6: Documentation updates (INSTALLATION.md, README.md, PROCESS.md)
- FR-7: `/update-loa` submodule support

### Sprint 3 (P1 — Hardening)
- CI/CD compatibility testing and documentation
- Windows symlink fallback verification
- Edge case handling (offline submodule, detached HEAD recovery)
- Integration testing with existing Loa workflows (/run, /simstim, etc.)

---

## 11. Ecosystem Impact

### 11.1 Launch Readiness (loa-finn#66)

The minimal footprint directly addresses the adoption blocker identified in the launch readiness RFC. With submodule-first installation, Loa becomes viable for:
- Production repositories with strict hygiene requirements
- Open source projects where contributor experience matters
- Enterprise environments with code audit requirements

### 11.2 Multi-Runtime Distribution (loa-finn#31)

The Hounfour RFC's five-layer architecture requires Loa to exist in multiple runtime contexts. Submodule installation provides a clean separation between framework definition (the submodule) and framework execution (symlinks + Claude Code). This is the architectural prerequisite for running Loa agents inside loa-finn's server runtime.

### 11.3 Constitutional Governance (loa-hounfour)

The constitutional architecture building in loa-hounfour — constraint provenance, event-sourced reputation, Ostrom governance principles — requires clear boundaries between governed and governing systems. The submodule boundary enforces this at the version control level: the framework's authority is auditable, pinned, and revocable.

### 11.4 Economic Protocol (loa-freeside)

Paying customers won't accept 2,600 framework files in their repository. The minimal footprint is a prerequisite for the billing infrastructure (loa-freeside#62, PR#90) to have a product worth billing for.

---

## 12. Open Questions

### Q-1: Submodule URL (Resolved)
**Question:** Should the submodule point to the public Loa repo or a dedicated distribution repo?
**Answer:** Public repo (`https://github.com/0xHoneyJar/loa.git`). Same URL already used by `mount-submodule.sh`.

### Q-2: Memory Stack Relocation
**Question:** Should Memory Stack move to `.loa-cache/` (project-local) or `~/.cache/loa/` (user-global)?
**Recommendation:** `.loa-cache/` (project-local, gitignored). User-global would break multi-project isolation.

### Q-3: Root Document Generation
**Question:** Should framework-generated root documents (PROCESS.md, etc.) still be generated but gitignored, or not generated at all?
**Recommendation:** Generated on-demand (when `/loa setup` runs), but gitignored by default. Users who want them committed can remove the gitignore entries.

---

## Appendix A: File Count Comparison

| Mode | Tracked Files | Gitignored Files | Total |
|------|--------------|-----------------|-------|
| Current default (standard) | ~2,640 | ~150 | ~2,790 |
| Current stealth | ~1,560 | ~1,230 | ~2,790 |
| **New default (submodule)** | **≤ 5** | **~2,785** | **~2,790** |
| New vendored (explicit) | ~2,640 | ~150 | ~2,790 |

The total file count doesn't change — the framework still needs its files. What changes is **who tracks them**. In submodule mode, git tracks one reference to 800+ files rather than 800+ individual files.

---

## Appendix B: Competitive Context

| Framework | Installation Model | Tracked Files |
|-----------|--------------------|---------------|
| **Loa (current)** | Copy into repo | ~2,640 |
| **Loa (proposed)** | Git submodule | ≤ 5 |
| Conway/Automaton | npm package | 0 (node_modules gitignored) |
| Cursor Rules | Single .cursorrules file | 1 |
| Claude Code (vanilla) | .claude/ directory | ~3-5 |
| Devin | Cloud-only | 0 |

The proposed approach brings Loa in line with the "minimal local footprint" pattern that successful dev tools use.
