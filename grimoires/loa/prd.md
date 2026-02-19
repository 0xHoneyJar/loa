# PRD: UX Redesign — Vercel-Grade Developer Experience (Phase 1)

> Cycle: cycle-030 | Author: soju + Claude
> Source: [#380](https://github.com/0xHoneyJar/loa/issues/380)-[#390](https://github.com/0xHoneyJar/loa/issues/390)
> Related: [#332](https://github.com/0xHoneyJar/loa/issues/332) (game design), [#90](https://github.com/0xHoneyJar/loa/issues/90) (AskUserQuestion UX), [#343](https://github.com/0xHoneyJar/loa/issues/343) (progressive disclosure), [#379](https://github.com/0xHoneyJar/loa/issues/379) (construct trust)
> Design Context: `grimoires/loa/context/ux-redesign-plan.md`
> Priority: P0 (user-facing — directly impacts adoption and first impressions)

---

## 1. Problem Statement

Loa's installation and first-run experience creates unnecessary friction that undermines its value proposition. A real user (J Nova, Opus 4.5) reported:

1. **Wrong error messages** — `mount-loa.sh` suggests `pip install yq` which contradicts docs; beads installer points to wrong repo; flock hint is wrong on macOS
2. **10-16 manual commands** before first `/plan` — "time to first command: ~2 minutes" claim is 3-8x optimistic
3. **Setup wizard that can't fix** — `/loa setup` validates but cannot install missing deps, forcing exit-fix-reenter loops
4. **Silent failures** — beads installer silently fails, user discovers breakage only when `/run` mode fails later

The core issue: Loa adds friction ON TOP of the Claude Code installation burden. Users who already struggled to install Claude Code are asked to install more tools, run more commands, and debug more errors before reaching a productive flow state.

> Sources: J Nova Discord feedback (2026-02-19), UX audit by 4 research agents, issues #380-#390

---

## 2. Vision

**One command. Zero questions. Productive in 60 seconds.**

Loa's installation should feel like Vercel's — opinionated defaults that just work. The framework trusts that sensible defaults serve 90% of users. Power users customize after (Layer 2 in the progressive disclosure model from issue #343).

### Design Philosophy

| Principle | Application |
|-----------|------------|
| **Show, don't tell** | Value surfaces through experience, not feature lists |
| **Tension-driven** | Capabilities revealed at moments of contrast (fun ↔ learn ↔ earn) |
| **Progressive disclosure** | Layer 0 (invisible defaults) → Layer 1 (discoverable) → Layer 2 (customizable) → Layer 3 (composable) |
| **Zero-config happy path** | One command installs everything with sensible defaults |

> Sources: grimoires/loa/context/ux-redesign-plan.md, issue #332 (game design), issue #343 (progressive disclosure)

---

## 3. Goals & Success Metrics

### G-1: Zero Misleading Error Messages
- Every install hint is correct for the target platform
- No silent failures — if something fails, it says what failed and what to do
- **Metric**: 0 wrong install suggestions across macOS (Intel + ARM) and Linux (Ubuntu, Debian)

### G-2: Time-to-First-Plan Under 5 Commands
- From clone/curl to first `/plan` completion in 5 or fewer user actions
- Current state: 10-16 commands
- **Metric**: Count of distinct user commands from `curl` to `/plan` response ≤ 5

### G-3: User Feedback Signal
- Next user reports fewer friction points than J Nova
- `/feedback` is discoverable at tension moments
- **Metric**: Qualitative — subsequent user feedback submissions show reduced install friction

### G-4: Post-Mount Message Uses Golden Path
- Post-mount output suggests `/plan` (golden path) not `/plan-and-analyze` (truename)
- Single clear next-step instruction
- **Metric**: Post-mount output contains exactly one next-step instruction using golden path command

---

## 4. User & Stakeholder Context

### Primary Persona: New Loa User (J Nova proxy)
- Has Claude Code installed (already overcame that hurdle)
- Wants to start building, not configuring
- Expects AI to handle setup, not list manual steps
- Mental model: "I'm using Claude" — doesn't yet think of themselves as a "Loa operator"
- **Key frustration**: "I had errors of a missing dependency. Would rather AI just installed it for me."

### Secondary Persona: Returning User
- Has used Loa before, upgrading or reinstalling
- Expects the process to be smoother than first time
- Wants to verify their setup is current without starting from scratch

### Stakeholder: Maintainer (@janitooor)
- Wants adoption growth through reduced friction
- Bridgebuilder will security-review the auto-install changes
- Cares about install correctness across platforms

> Sources: J Nova Discord feedback, grimoires/loa/context/ux-redesign-plan.md (Persona section)

---

## 5. Functional Requirements

### FR-1: Fix Wrong Install Hints (Tier 0 Bugs)

Three install suggestions are incorrect and must be fixed:

| Bug | File:Line | Current (Wrong) | Fix |
|-----|-----------|-----------------|-----|
| #380 | `mount-loa.sh:340` | `steveyegge/beads` repo URL | `Dicklesworthstone/beads_rust` or call `install-br.sh` |
| #381 | `mount-loa.sh:321` | `pip install yq` suggestion | `brew install yq` / mikefarah/yq link |
| #382 | `loa-doctor.sh:189` | `brew install util-linux` for flock | Correct macOS flock install method |

**Acceptance Criteria**:
- [ ] `mount-loa.sh:340` references correct beads_rust repo or delegates to `install-br.sh`
- [ ] `mount-loa.sh:321` error message suggests only correct yq install methods (no pip)
- [ ] `loa-doctor.sh:189` flock suggestion works on macOS
- [ ] Each fix verified on macOS ARM64 (primary dev platform)

### FR-2: Fix /plan Entry Flow Bugs (Tier 0 Bugs)

Two bugs in the `/plan` command entry flow:

| Bug | File:Line | Issue | Fix |
|-----|-----------|-------|-----|
| #383 | `plan.md:~93` | "What does Loa add?" falls through to planning with no re-entry prompt | Add follow-up confirmation after info block |
| #384 | `plan.md:116-123` | 5th archetype (`schema.yaml`) silently truncated by 4-option AskUserQuestion limit | Reduce to 3 archetypes or redesign selection |

**Acceptance Criteria**:
- [ ] Selecting "What does Loa add?" shows info then asks "Ready to start?" before proceeding
- [ ] All archetype files in `.claude/data/archetypes/` are accessible (none silently dropped)

### FR-3: Auto-Installing Setup (`--auto-install`)

Transform `mount-loa.sh` from "error on missing deps" to "install missing deps automatically."

**Target experience**:
```
$ curl -fsSL loa.sh | bash
  ✓ Detected macOS arm64
  ✓ jq found (v1.7.1)
  ✗ yq not found — installing mikefarah/yq... ✓ (v4.40.5)
  ✓ git found (v2.43.0)
  ✗ beads_rust not found — installing via cargo... ✓ (v0.4.2)
  ✓ Mounted Loa v1.39.0

  Start Claude Code and type /plan
```

**Auto-install behavior**:

| Dependency | Detection | Install Method (macOS) | Install Method (Linux) | Fallback |
|-----------|-----------|----------------------|----------------------|----------|
| jq | `command -v jq` | `brew install jq` | `apt install jq` / `yum install jq` | Error with correct instructions |
| yq (mikefarah) | `command -v yq && yq --version \| grep mikefarah` | `brew install yq` | Binary download from GitHub releases | Error with correct instructions |
| git | `command -v git` | `xcode-select --install` | `apt install git` | Error — git is truly required |
| beads_rust | `command -v br` | `cargo install beads_rust` (if cargo present) | Same | Warn and skip — optional tool |
| Rust/cargo | `command -v cargo` | Skip if beads not needed | Skip | Info: "Install rustup for beads_rust" |

**Constraints**:
- `--auto-install` is the DEFAULT (opt-out with `--no-auto-install`)
- Auto-install ONLY runs for missing deps, never upgrades existing
- Each install attempt has a 60-second timeout
- Failed auto-install falls back to correct manual instructions (never wrong ones)
- beads_rust is treated as optional — warn on skip, don't error

**Acceptance Criteria**:
- [ ] `mount-loa.sh` auto-installs jq, yq on macOS when missing
- [ ] `mount-loa.sh` auto-installs jq, yq on Linux (apt-based) when missing
- [ ] beads_rust install attempted if cargo present, skipped with warning if not
- [ ] `--no-auto-install` flag preserves current error-and-stop behavior
- [ ] Failed auto-install shows correct manual instructions (never wrong packages)
- [ ] All auto-installs logged to stdout with ✓/✗ status

### FR-4: Post-Mount Golden Path Message

Replace current post-mount output with golden path commands.

**Current** (`mounting-framework/SKILL.md:244-246`):
```
1. Run 'claude' to start Claude Code
2. Issue '/ride' to analyze this codebase
3. Or '/plan-and-analyze' for greenfield development
```

**Target**:
```
✓ Loa mounted successfully.

  Next: Start Claude Code and type /plan
```

**Acceptance Criteria**:
- [ ] Post-mount output uses `/plan` (golden path) not `/plan-and-analyze` or `/ride`
- [ ] Single next-step instruction — no multi-option confusion
- [ ] No truename commands in user-facing output

### FR-5: `/loa setup` Auto-Fix Capability

Transform `/loa setup` from read-only validator to active fixer.

**Current behavior**: Shows ✓/✗ results, cannot install anything.
**Target behavior**: Shows ✓/✗ results, then offers to fix ✗ items.

```
Setup Check Results
═══════════════════
✓ API Key configured
✓ jq (v1.7.1)
✗ yq — not found
✓ git (v2.43.0)
⚠ beads — not installed (optional)

Fix missing dependencies?
> Yes, install yq (Recommended)
> Skip — I'll install manually
```

**Acceptance Criteria**:
- [ ] `/loa setup` can install missing jq, yq via Bash tool
- [ ] `/loa setup` can install beads_rust if cargo is present
- [ ] Each fix attempt shows progress and result
- [ ] User must confirm before any install action (AskUserQuestion)
- [ ] If all deps present, no fix prompt shown — clean pass

### FR-6: `/feedback` at Tension Points

Surface `/feedback` at moments of friction, not everywhere.

| Touchpoint | Trigger | Message |
|-----------|---------|---------|
| `/loa doctor` finds issues | Health check has warnings/errors | "Something broken? `/feedback` reports it directly." |
| User selects "Other" in AskUserQuestion | Broke out of structured options | "Options didn't fit? `/feedback` helps us improve." |
| First-time `/loa` | Initial state, no PRD | Brief mention in 3-line welcome |

**NOT** in: post-mount, post-setup, every help screen, every skill completion. That's noise.

**Acceptance Criteria**:
- [ ] `/feedback` mentioned in `/loa doctor` output when issues found
- [ ] `/feedback` mentioned in first-time `/loa` initial state
- [ ] `/feedback` NOT added to post-mount, post-setup, or every help screen

---

## 6. Technical & Non-Functional Requirements

### NF-1: Platform Coverage
- macOS: Intel + ARM (Homebrew)
- Linux: apt-based (Ubuntu, Debian) — primary
- Linux: yum-based (RHEL, Fedora) — best-effort
- Windows/WSL: not in scope

### NF-2: Backwards Compatibility
- `--no-auto-install` preserves current behavior exactly
- Existing `.loa.config.yaml` files are not modified
- No breaking changes to `/loa setup` for users who already have deps installed

### NF-3: Security
- Auto-install uses official package managers only (Homebrew, apt, cargo)
- No piping random scripts to bash for individual deps
- yq install verifies it's mikefarah/yq (not kislyuk Python yq)
- beads_rust install via cargo (auditable, versioned)

### NF-4: Fail-Safe
- If auto-install fails for any dep, continue with remaining deps
- Never leave a partial install state — either dep is installed or user gets correct manual instructions
- Failed beads install is a warning, not an error (beads is optional)

---

## 7. Scope & Prioritization

### In Scope (Cycle-030)

| Priority | Feature | Issue(s) | Why |
|----------|---------|----------|-----|
| P0 | FR-1: Fix wrong install hints | #380, #381, #382 | Users hitting broken paths right now |
| P0 | FR-2: Fix /plan entry flow bugs | #383, #384 | First command experience is broken |
| P0 | FR-3: Auto-installing setup | #390 | Core DX improvement — largest time-to-value impact |
| P1 | FR-4: Post-mount golden path | — | Small change, big clarity improvement |
| P1 | FR-5: `/loa setup` auto-fix | #390 | Completes the zero-friction install story |
| P2 | FR-6: `/feedback` at tension points | #388 | Feedback loop for continuous improvement |

### Deferred to Cycle-031

| Feature | Issue(s) | Why Deferred |
|---------|----------|-------------|
| Free-text first plan flow | #386 | Requires SKILL.md redesign — different scope |
| Post-completion highlights + steer | #385 | Requires `<post_completion>` sections in 3 SKILL.md files |
| Sprint time estimation calibration | #387 | Template change — lower urgency |
| Tool hesitancy fix | #389 | Zone model change — needs careful design |
| Flatline auto-trigger default | — | Open question — needs user testing |

---

## 8. Risks & Dependencies

### R-1: Homebrew Availability (Medium)
- **Risk**: macOS users without Homebrew can't auto-install
- **Mitigation**: Detect `brew` presence first; if missing, fall back to manual instructions with Homebrew install link

### R-2: cargo/Rust Not Present (Low)
- **Risk**: beads_rust requires Rust toolchain, which most users won't have
- **Mitigation**: Treat beads as optional; skip with informational warning; don't error

### R-3: yq Version Confusion (Medium)
- **Risk**: User has kislyuk/yq (Python) installed, `command -v yq` succeeds but it's the wrong one
- **Mitigation**: Verify with `yq --version | grep mikefarah` after detection; if wrong yq, offer to install correct one alongside

### R-4: Platform Detection Edge Cases (Low)
- **Risk**: Unusual Linux distros (Arch, Alpine, NixOS) not covered by apt/yum
- **Mitigation**: Fall back to correct manual instructions; don't attempt unknown package managers

### D-1: No External Dependencies
- All changes are to Loa's own scripts and skill files
- No upstream dependencies or API changes required
- Bridgebuilder review will cover security of auto-install changes
