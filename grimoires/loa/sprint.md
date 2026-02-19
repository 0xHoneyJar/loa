# Sprint Plan: UX Redesign — Vercel-Grade Developer Experience (Phase 1)

> Cycle: cycle-030 | PRD: grimoires/loa/prd.md | SDD: grimoires/loa/sdd.md
> Source: [#380](https://github.com/0xHoneyJar/loa/issues/380)-[#390](https://github.com/0xHoneyJar/loa/issues/390)
> Sprints: 2 | Team: 1 developer (AI-assisted)

---

## Executive Summary

| Field | Value |
|-------|-------|
| **Total Sprints** | 2 |
| **Scope** | Tier 0 bug fixes + auto-install onboarding + /plan entry fixes + /feedback visibility |
| **Success Metric** | Time-to-first-plan ≤ 5 commands; 0 wrong install suggestions |

---

## Sprint 1: Bug Fixes + Auto-Install Infrastructure

**Scope**: FR-1 (wrong install hints), FR-3 (auto-install), FR-4 (post-mount golden path)

### Task 1.1: Fix Beads Installer URL (#380)

**File**: `.claude/scripts/mount-loa.sh:326-349`

**Change**: Replace `install_beads()` to delegate to `.claude/scripts/beads/install-br.sh` instead of referencing wrong `steveyegge/beads` URL.

**Acceptance Criteria**:
- [ ] `install_beads()` calls `.claude/scripts/beads/install-br.sh` when present
- [ ] No reference to `steveyegge` remains in mount-loa.sh
- [ ] Falls back to warning (not error) if installer missing
- [ ] Existing `--skip-beads` flag preserved

### Task 1.2: Fix yq Install Suggestion (#381)

**File**: `.claude/scripts/mount-loa.sh:321`

**Change**: Replace `pip install yq` with correct `mikefarah/yq` instructions.

**Acceptance Criteria**:
- [ ] Error message references `brew install yq` and `mikefarah/yq` GitHub link
- [ ] No mention of `pip install yq` anywhere in mount-loa.sh
- [ ] Warning about incompatible Python yq included

### Task 1.3: Fix flock Hint (#382)

**File**: `.claude/scripts/loa-doctor.sh:189`

**Change**: Replace `brew install util-linux` with `brew install flock`.

**Acceptance Criteria**:
- [ ] macOS suggestion is `brew install flock`
- [ ] Linux suggestion is `apt install util-linux`

### Task 1.4: Add `detect_os()` Helper

**File**: `.claude/scripts/mount-loa.sh`

**Change**: Add OS detection function that returns `macos` | `linux-apt` | `linux-yum` | `unknown`.

**Acceptance Criteria**:
- [ ] Function exists and is callable
- [ ] Correctly identifies macOS, Debian/Ubuntu, RHEL/Fedora
- [ ] Returns `unknown` for unsupported platforms

### Task 1.5: Add `auto_install_deps()` Function

**File**: `.claude/scripts/mount-loa.sh`

**Change**: New function that auto-installs missing jq, yq (mikefarah) based on detected OS. Includes yq version verification (mikefarah vs kislyuk).

**Acceptance Criteria**:
- [ ] Installs jq via brew (macOS) or apt (Linux) when missing
- [ ] Installs yq via brew (macOS) or GitHub binary (Linux) when missing
- [ ] Detects and warns about wrong yq (kislyuk/Python)
- [ ] Each install logged with ✓/✗ status
- [ ] Failed installs produce correct manual instructions

### Task 1.6: Integrate Auto-Install into `preflight()`

**File**: `.claude/scripts/mount-loa.sh:282-324`

**Change**: Replace hard-error dep checks with `auto_install_deps()` call followed by verification. Add `--no-auto-install` CLI flag.

**Acceptance Criteria**:
- [ ] `auto_install_deps()` called before dep verification
- [ ] Hard-error messages updated with "Auto-install failed" prefix
- [ ] `--no-auto-install` flag skips auto-install, preserves current behavior
- [ ] `NO_AUTO_INSTALL` variable added to arg parsing section

### Task 1.7: Consolidate Post-Mount Message (FR-4)

**File**: `.claude/scripts/mount-loa.sh:1418-1446`

**Change**: Replace dual banner (fallback + golden path) with single line: "Next: Start Claude Code and type /plan"

**Acceptance Criteria**:
- [ ] Post-mount output is a single "Next:" instruction
- [ ] Uses `/plan` (golden path), not `/plan-and-analyze` or `/ride`
- [ ] No mention of `/loa setup` in happy path (auto-install handles deps)
- [ ] Duplicate banner eliminated

---

## Sprint 2: /plan Entry Fixes + /feedback Visibility + Setup Auto-Fix

**Scope**: FR-2 (/plan bugs), FR-5 (/loa setup auto-fix), FR-6 (/feedback tension points)

### Task 2.1: Fix "What does Loa add?" Fall-Through (#383)

**File**: `.claude/commands/plan.md:55-95`

**Change**: After the info block (line 93), add a follow-up AskUserQuestion: "Ready to start planning?" with "Let's go!" / "Not yet" options.

**Acceptance Criteria**:
- [ ] Selecting "What does Loa add?" shows info then asks "Ready to start?"
- [ ] Selecting "Not yet" exits cleanly with resume message
- [ ] Selecting "Let's go!" proceeds to archetype selection
- [ ] The line "This step never blocks" is removed

### Task 2.2: Fix Archetype Truncation (#384)

**File**: `.claude/commands/plan.md:97-137`

**Change**: Limit to 3 archetype options (not 4) so "Other" is the 4th visible option. If more than 3 archetypes exist, add note to 3rd option's description.

**Acceptance Criteria**:
- [ ] Max 3 archetypes shown as options
- [ ] All archetype files remain functional (just not all shown)
- [ ] "Other" (auto-appended) visible as 4th option
- [ ] Comment about "first 4 files found" updated

### Task 2.3: Add Auto-Fix to `/loa setup` (FR-5)

**File**: `.claude/commands/loa-setup.md`

**Change**: Insert Step 2.5 after validation results. If any dep is `fail`, offer to install via AskUserQuestion. On confirm, run install commands via Bash tool and re-validate.

**Acceptance Criteria**:
- [ ] Missing deps trigger AskUserQuestion: "Fix missing dependencies?"
- [ ] "Yes, install now" runs correct install commands for each dep
- [ ] Progress shown per dep: "Installing jq... ✓"
- [ ] Re-runs validation after install to confirm
- [ ] "Skip" preserves current behavior

### Task 2.4: Add `/feedback` to First-Time `/loa` (FR-6)

**File**: `.claude/commands/loa.md`

**Change**: In initial state output (no PRD, no completed cycles), add "Something unexpected? /feedback reports it directly." before the "Next: /plan" line.

**Acceptance Criteria**:
- [ ] `/feedback` mention appears in initial state
- [ ] Does NOT appear in subsequent `/loa` calls (only first-time)
- [ ] Does NOT appear in /loa --help (too noisy — only help-full)

### Task 2.5: Add `/feedback` to `/loa --help`

**File**: `.claude/commands/loa.md`

**Change**: Add `/feedback` to the visible help output command list.

**Acceptance Criteria**:
- [ ] `/feedback` listed in `/loa --help` output
- [ ] Description: "Report issues or suggestions"
- [ ] Positioned in the "Ad-hoc" commands section

---

## Dependency Graph

```
Sprint 1:
  Task 1.1 ──┐
  Task 1.2 ──┤
  Task 1.3 ──┤── All independent, can be done in parallel
  Task 1.4 ──┘
       │
  Task 1.5 ←── Depends on 1.4 (detect_os)
       │
  Task 1.6 ←── Depends on 1.5 (auto_install_deps)
       │
  Task 1.7 ──── Independent

Sprint 2:
  Task 2.1 ──┐
  Task 2.2 ──┤── All independent, can be done in parallel
  Task 2.3 ──┤
  Task 2.4 ──┤
  Task 2.5 ──┘
```

---

## Review Criteria

### Sprint 1 Review
- [ ] `mount-loa.sh` has no references to `steveyegge/beads`
- [ ] `mount-loa.sh` has no references to `pip install yq`
- [ ] `loa-doctor.sh` flock suggestion works on macOS
- [ ] `auto_install_deps()` handles macOS + Linux (apt)
- [ ] `--no-auto-install` preserves current behavior
- [ ] Post-mount message is single "Next: ... /plan" instruction

### Sprint 2 Review
- [ ] `/plan` "What does Loa add?" has re-entry prompt
- [ ] Archetype selection shows ≤3 options (no silent truncation)
- [ ] `/loa setup` can install missing deps when user confirms
- [ ] `/feedback` visible in initial `/loa` and `/loa --help`
