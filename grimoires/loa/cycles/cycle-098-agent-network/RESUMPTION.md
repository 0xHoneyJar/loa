# cycle-098-agent-network — Session Resumption Brief

**Last updated**: 2026-05-03 (mid-Sprint-1)
**Author**: deep-name + Claude Opus 4.7 1M
**Purpose**: Crash-recovery + cross-session continuity. Read this first if resuming cycle-098 Sprint 1 work in a new session.

## TL;DR for next session

```
Read grimoires/loa/cycles/cycle-098-agent-network/RESUMPTION.md and continue cycle-098 Sprint 1 from where the previous session left off. Sub-sprints 1A-1D in progress on feat/cycle-098-sprint-1 branch. Pre-written briefs for 1C and 1D are in this doc, embed-ready for Agent calls. R11 weekly check routine is scheduled (trig_01E2ayirT9E93qCx3jcLqkLp).
```

That's the resume command — paste it into a new Claude Code session.

---

## State as of session end

### Repository

| Marker | Value |
|--------|-------|
| Active cycle | `cycle-098-agent-network` (per ledger.json) |
| main HEAD | `b882c9f` (PR #686 README drift prevention merge) |
| Active sprint branch | `feat/cycle-098-sprint-1` (HEAD: `2774a32` after 1A; 1B push pending) |
| Latest GitHub release | `v1.110.1` (cycle-098 ledger activation) |
| Global sprint counter | 138 (Sprint 1-7 reservations 132-138; sprint-bug-131 already at 131) |

### Sub-sprint progress

| Sub-sprint | Status | Commit | Tests | Files |
|-----------|--------|--------|-------|-------|
| **1A** JCS + audit envelope foundation | ✅ Done | `2774a32` | 96 passing | +19/+2221 |
| **1B** Trust + Identity (Ed25519, trust-store, OPERATORS.md, fd-secrets, protected-classes) | 🔄 Running | — | — | — |
| **1C** Cross-cutting ops (sanitize_for_session_start, tier-validator, /loa status, hash-chain recovery) | ⏳ Pending | — | — | — |
| **1D** L1 hitl-jury-panel skill | ⏳ Pending | — | — | — |
| Consolidated /review-sprint sprint-1 | ⏳ Pending | — | — | — |
| Consolidated /audit-sprint sprint-1 | ⏳ Pending | — | — | — |
| Bridgebuilder kaironic on Sprint 1 PR | ⏳ Pending | — | — | — |
| Sprint 1 admin-merge | ⏳ Pending | — | — | — |

### Active worktree-isolated agents

Check via `git worktree list`. Agents are auto-cleaned on completion; if running, the worktree path is `.claude/worktrees/agent-<id>/`. As of session end:
- `agent-ad425b786579386e4` (Sub-sprint 1B, Trust + Identity) — running, no commits yet at session end

### Today's commits on main (chronological)

| Commit | PR | Title |
|--------|----|----|
| `7427227` | #677 | fix(model-adapter): large-payload hardening — sprint-bug-131 (#675) |
| `0b81d9c` | #678 | feat(cycle-098): planning artifacts (PRD v1.3, SDD v1.5, sprint plan, decisions) |
| `9341930` | #679 | chore(cycle-098): activate cycle in ledger + reserve Sprint 1-7 IDs |
| `2a05d86` | #685 | chore: bump README + .loa-version.json to v1.110.1 (drift catch-up) |
| `b882c9f` | #686 | chore(ci): add README ↔ .loa-version.json drift prevention |

### Open follow-up issues (cycle-099 candidates)

| # | Title | Priority |
|---|-------|----------|
| #675 | cheval/httpx HTTP/2 disconnect on 137KB+ payloads (4 sub-issues) | shipped (sprint-bug-131) |
| #680 | vision-013: Per-PR opt-in flag for Loa-content bridgebuilder review | cycle-099 |
| #681 | vision-014: CI guard for *.bak and backup-sibling files | cycle-099 P2 |
| #682 | vision-015: RFC 3647 Certificate Policy for audit-key bootstrap | cycle-099 (or later) |
| #683 | vision-016: Stacked diffs for incremental SDD changes | cycle-099 (or later) |
| #684 | vision-017: Planning tooling stops emitting .bak siblings entirely (REFRAME) | cycle-099 |
| #687 | sync-readme-version.sh — add unit tests | cycle-099 P3 |

### Routines scheduled

| ID | Cron | Purpose |
|----|------|---------|
| `trig_01E2ayirT9E93qCx3jcLqkLp` | `0 16 * * 5` (Friday 16:00 UTC) | R11 cycle-098 weekly schedule-check ritual; first run 2026-05-08T16:00Z |

URL: https://claude.ai/code/routines/trig_01E2ayirT9E93qCx3jcLqkLp

### Operator action prerequisites (all approved 2026-05-03)

1. ✅ Offline root key generated (Ed25519, mode 0600 at `~/.config/loa/audit-keys/cycle098-root.priv`)
   - Fingerprint: `e7:6e:ec:46:0b:34:eb:61:0f:6d:b1:27:2d:7e:f3:64:b9:94:d5:1e:49:f1:3a:d0:88:6f:a8:b9:e8:54:c4:d1`
   - **Outstanding**: passphrase-encrypt OR migrate to YubiKey/hardware token before Sprint 1 production use
2. ✅ Fingerprint published in 3 channels (PR description template, NOTES.md, release notes — all in `grimoires/loa/cycles/cycle-098-agent-network/`)
3. ✅ tier_enforcement_mode default decision: Option C (warn-then-refuse migration) — at `decisions/tier-enforcement-default.md`
4. ✅ R11 routine scheduled (above)
5. ✅ #675 triaged + shipped as sprint-bug-131 (PR #677 merged)
6. ✅ Claude GitHub App installed on 0xHoneyJar/loa

---

## Pre-written briefs (paste into Agent calls when ready)

### How to fire each sub-sprint

```python
Agent(
    description="<short description>",
    subagent_type="general-purpose",
    isolation="worktree",
    run_in_background=True,
    prompt="<paste full brief from below>",
)
```

Each brief is self-contained and tight. Sub-sprints depend on previous ones (1B needs 1A's commit, 1C needs 1B's, 1D needs 1C's). Fire sequentially — do not parallelize.

### Sub-sprint 1C brief (fire when 1B completes)

```
You are implementing **Sub-sprint 1C** of cycle-098-agent-network Sprint 1: **Cross-cutting Operations**. This is sub-sprint 3 of 4. Builds on 1A foundation + 1B trust/identity. Test-first per Loa convention.

**Working directory**: this worktree
**Repo**: 0xHoneyJar/loa
**Branch**: `feat/cycle-098-sprint-1` already exists at origin with 1A + 1B commits. Pull this branch.
**Cycle**: cycle-098-agent-network (active per ledger.json)

## Setup

```bash
git fetch origin feat/cycle-098-sprint-1
git checkout feat/cycle-098-sprint-1
git pull origin feat/cycle-098-sprint-1 --ff-only
git log --oneline -5   # Verify HEAD includes 1A (2774a32) AND 1B's commit
```

Read 1A handoff at `grimoires/loa/a2a/sprint-1/progress-1A.md` and 1B handoff at `grimoires/loa/a2a/sprint-1/progress-1B.md` for TODO hooks.

## Scope (1C only)

You implement the **cross-cutting operations layer** that 1D depends on:

### Deliverables

1. **`sanitize_for_session_start` extension** to `.claude/scripts/lib/context-isolation-lib.sh`
   - Per SDD §1.4.1 (line 257) + §1.9.3.2 (line 876, "Adversarial Prompt-Injection Defense")
   - Function: `sanitize_for_session_start <source> <content_or_path> [--max-chars N]`
   - Layer 1: Pattern detection (`<function_calls>`, role-switch, tool-call exfiltration → redact)
   - Layer 2: Structural sanitization (wrap in `<untrusted-content source="L6|L7" path="...">...</untrusted-content>` with explicit framing)
   - Layer 3: Per-source policy rules (placeholder; Sprint 6/7 expand)
   - Layer 4: Adversarial corpus hook (test fixtures; Sprint 7 ships full corpus)
   - Layer 5: Hard tool-call boundary — provenance tagging (mark untrusted-source content; tool-resolver enforcement is a Loa harness change, document but don't implement here)

2. **`tier-validator.sh`** at `.claude/scripts/tier-validator.sh` (CC-10 enforcement)
   - Per SDD §1.4.1 (find via `grep -n "Tier Validator" grimoires/loa/sdd.md`) + PRD §Supported Configuration Tiers
   - At Loa boot or skill load: inspects `.loa.config.yaml` for enabled primitives; matches against 5 supported tiers (Tier 0..4); applies `tier_enforcement_mode: warn|refuse`
   - Default: `warn` (per Operator-decided Option C in `cycles/cycle-098-agent-network/decisions/tier-enforcement-default.md`)
   - Outputs: `tier-N` identifier or `unsupported` warning to stderr

3. **`/loa status` integration** — extend `.claude/scripts/loa-status.sh`
   - Per SDD §4.4 (line 1550) — full ASCII layout already specified
   - Add `Agent-Network Primitives (cycle-098)` section showing per-primitive enabled/recent-activity
   - Add `Tier validator: Tier N (<label>) -- supported.`
   - Add `Protected queue: N items awaiting operator action.` (read `.run/protected-queue.jsonl` if exists)
   - Add `Audit chain: N/7 primitives validate. Last verify: <relative time>.`
   - Read `.loa.config.yaml` for enabled status; read `.run/<primitive>-events.jsonl` for recent activity
   - Don't break existing `/loa status` output — extend, don't replace

4. **Hash-chain recovery procedure** (NFR-R7) at `.claude/scripts/audit-envelope.sh`
   - Per SDD §3.4.4 (line 1292)
   - Extend the `audit_recover_chain` function (1A scaffolded; 1C implements)
   - Two paths:
     - **TRACKED logs** (L4 trust-ledger.jsonl, L6 INDEX.md): rebuild from `git log -p <log_file>`; locate most recent valid chain state; mark broken segment with `[CHAIN-GAP-RECOVERED-FROM-GIT]` marker
     - **UNTRACKED chain-critical logs** (L1 panel-decisions.jsonl, L2 cost-budget-events.jsonl): restore from latest signed snapshot at `grimoires/loa/audit-archive/<utc-date>-<primitive>.jsonl.gz`; verify snapshot signature; restore entries; mark gap with `[CHAIN-GAP-RESTORED-FROM-SNAPSHOT-RPO-24H]` marker
   - On rebuild success: write `[CHAIN-RECOVERED]` marker entry; resume normal chain
   - On rebuild failure: write `[CHAIN-BROKEN]` marker; emit BLOCKER; degraded mode (reads OK, writes blocked)

### Tests (test-first)

1. `tests/integration/sanitize-for-session-start.bats` — exercises Layers 1-5 with malicious fixtures (role-switch attempt, tool-call exfiltration, code-fence injection)
2. `tests/unit/tier-validator.bats` — Tier 0..4 detection + unsupported combination + warn vs refuse mode
3. `tests/integration/loa-status-integration.bats` — extended /loa status output includes the cycle-098 section
4. `tests/integration/hash-chain-recovery-tracked.bats` — induce chain break in L4 ledger; recover from git history; verify [CHAIN-RECOVERED] marker
5. `tests/integration/hash-chain-recovery-untracked.bats` — induce chain break in L1 panel-decisions.jsonl; recover from snapshot; verify [CHAIN-GAP-RESTORED-FROM-SNAPSHOT-RPO-24H] marker

Verify all 5 tests FAIL before implementation, PASS after.

## Constraints

- **Test-first non-negotiable**
- **Karpathy principles**: simplicity, surgical, goal-driven
- **Beads UNHEALTHY** (#661); ledger fallback; `git commit --no-verify` per documented workaround
- **macOS portability**: use `_require_flock()` and `lib/portable-realpath.sh` from cycle-098 patterns
- **Security patterns**: BB-001 xtrace-disable around any sensitive ops; tmpfile mode 0600 + trap cleanup
- **Compose with 1A + 1B**: extend audit-envelope's chain-recovery hook; reference protected-classes from 1B; use OPERATORS.md identity from 1B
- **Stay focused on 1C scope**: do NOT implement L1 hitl-jury-panel skill (1D); do NOT implement L2-L7 primitives (later sprints)

## Workflow

1. Setup (above)
2. Read 1A + 1B handoffs
3. Read SPECIFIC SDD sections (don't read whole SDD):
   - §1.4.1 line 257 + §1.9.3.2 line 876 for sanitize_for_session_start
   - §3.4.4 line 1292 for hash-chain recovery
   - §4.4 line 1550 for /loa status layout
4. Write 5 failing tests
5. Verify tests FAIL
6. Implement in dependency order:
   - sanitize_for_session_start (extends existing context-isolation-lib.sh)
   - tier-validator.sh
   - hash-chain recovery (extends 1A's audit-envelope.sh stub)
   - /loa status integration (extends loa-status.sh)
7. Verify tests PASS
8. Run regression suites (pytest + bats)
9. Commit with `feat(cycle-098-sprint-1C): cross-cutting ops (sanitize + tier-validator + /loa status + hash-chain recovery)` (use `--no-verify`)
10. Push via ICE wrapper
11. Write progress report at `grimoires/loa/a2a/sprint-1/progress-1C.md` with handoff for 1D

## Output

Brief structured report:
1. Outcome (COMPLETED / HALTED with reason)
2. Files added/modified (count + key paths)
3. Tests added (count, all passing)
4. Regression status
5. Commit hash
6. Cost (token usage + approximate $)
7. Handoff to 1D (TODO hooks, integration points)
8. Any blockers
```

### Sub-sprint 1D brief (fire when 1C completes)

```
You are implementing **Sub-sprint 1D** of cycle-098-agent-network Sprint 1: **L1 hitl-jury-panel skill**. This is sub-sprint 4 of 4 (FINAL). Builds on 1A + 1B + 1C. Test-first per Loa convention.

**Working directory**: this worktree
**Repo**: 0xHoneyJar/loa
**Branch**: `feat/cycle-098-sprint-1` (must include 1A, 1B, 1C commits). Pull this branch.

## Setup

```bash
git fetch origin feat/cycle-098-sprint-1
git checkout feat/cycle-098-sprint-1
git pull origin feat/cycle-098-sprint-1 --ff-only
git log --oneline -5   # Verify HEAD includes 1A + 1B + 1C
```

Read previous handoffs at `grimoires/loa/a2a/sprint-1/progress-{1A,1B,1C}.md`.

## Scope (1D only)

You implement the **L1 hitl-jury-panel skill**, the headline primitive of Sprint 1.

### Deliverables

1. **L1 skill** at `.claude/skills/hitl-jury-panel/SKILL.md`
   - Per source RFC #653 (https://github.com/0xHoneyJar/loa/issues/653)
   - Per PRD §FR-L1 (find via `grep -n "FR-L1" grimoires/loa/prd.md`)
   - Per SDD §1.4.1 sub-section (line 338) + §5.3 (line 1693, full API spec)

2. **9 acceptance criteria** from PRD FR-L1-1 through FR-L1-9:
   - **FR-L1-1**: skill convenes ≥3 panelists in parallel
   - **FR-L1-2**: panelist views logged BEFORE selection (verifiable from log if skill crashes after solicitation)
   - **FR-L1-3**: deterministic seed `seed = sha256(decision_id || context_hash) % len(sorted(panelists, key=id))` (cross-process determinism via sorted panelist list)
   - **FR-L1-4**: protected classes route to `QUEUED_PROTECTED` without panel invocation (uses 1B's protected-class router)
   - **FR-L1-5**: fallback matrix tested for 4 cases (timeout, API failure, tertiary unavailable, all-fail)
   - **FR-L1-6**: disagreement check uses caller-configurable embedding fn (default no-op pass; OpenAI text-embedding-3-small adapter ships separately, NOT default-wired)
   - **FR-L1-7**: all decisions written to JSONL audit log `.run/panel-decisions.jsonl` using 1A's audit envelope (1B's signing scheme) with full panelist reasoning + selection seed + binding view + minority dissent
   - **FR-L1-8**: selection-seed distribution audit script verifies no panelist >50% selection rate over 30d window with N≥10 decisions (script ships; enforcement is post-ship telemetry)
   - **FR-L1-9**: cost estimation integrates with L2 cost-budget-enforcer **when L2 is enabled** (compose-when-available; this cycle has L2 unimplemented, so this is a stub that will activate in Sprint 2)

3. **Library functions** at `.claude/scripts/lib/hitl-jury-panel-lib.sh`:
   - `panel_invoke <decision_id> <decision_class> <context_hash> <panelists_yaml_path> <context_path>`
   - `panel_solicit <panelist_id> <model> <persona_path> <context_path> [--timeout <s>]`
   - `panel_select <panelists_json> <decision_id> <context_hash>`
   - `panel_log_views <decision_id> <panelists_with_views_json> <log_path>`
   - `panel_log_binding <decision_id> <selected_panelist_id> <seed> <minority_dissent_json> <log_path>`

4. **PanelDecision payload schema** (extends 1A's audit envelope per IMP-001 additive payload):
   - Per SDD §5.3.3 (line 1732-1759) — full schema captured
   - Required fields: `decision_id`, `decision_class`, `context_hash`, `panelists[]`, `selection_seed`, `selected_panelist_id`, `binding_view`, `minority_dissent[]`, `outcome`, `fallback_path`, `cost_estimate_usd`, `trust_check_result`

5. **Default panelists configuration template** at `.loa.config.yaml.example` (or extension):
   ```yaml
   hitl_jury_panel:
     enabled: false               # opt-in default
     default_panelists:
       - id: persona-a
         model: claude-opus-4-7
         persona_file: .claude/data/personas/persona-a.md
       - id: skeptic
         model: claude-opus-4-7
         persona_file: .claude/data/personas/skeptic.md
       - id: alternative-model
         model: gpt-5.3-codex
         persona_file: .claude/data/personas/alternative-model.md
     selection: random
     seed_source: decision_id+context_hash
     audit_log: .run/panel-decisions.jsonl
     default_disagreement_threshold: 0.5
   ```

6. **3 default persona stubs** at `.claude/data/personas/{persona-a,skeptic,alternative-model}.md` — minimal markdown documents identifying the persona's stance/voice. Operator can extend.

### Tests (test-first)

1. `tests/integration/hitl-jury-panel-skill.bats` — full skill invocation; ≥3 panelists; views logged before selection; deterministic seed; binding view emitted
2. `tests/unit/panel-deterministic-seed.bats` — `panel_select` with same `(decision_id, context_hash)` produces same selection across runs
3. `tests/integration/panel-protected-class.bats` — protected-class decision routes to `QUEUED_PROTECTED` without panel invocation (uses 1B's protected-class-router)
4. `tests/integration/panel-fallback-matrix.bats` — 4 cases: timeout (one panelist >timeout), API failure (one panelist 5xx), tertiary unavailable (3-panelist degrades to 2), all-fail (all 3 fail → returns ERROR outcome)
5. `tests/unit/panel-audit-envelope.bats` — verify panel-decisions.jsonl entries match 1A's envelope schema + 1B's signing
6. `tests/unit/panel-disagreement-no-op-default.bats` — no embedding fn provided → disagreement check always passes (FR-L1-6)

Verify all 6 tests FAIL before implementation, PASS after.

## Constraints

- **Test-first non-negotiable**
- **Karpathy principles**
- **Beads UNHEALTHY**; `--no-verify` workaround
- **Security**: do NOT execute panelist views; treat all panelist content as untrusted (use 1C's `sanitize_for_session_start` as integration point)
- **Compose**: panelist solicitation uses cheval/model-adapter (existing); audit log uses 1A envelope + 1B signing; protected-class check uses 1B router
- **Stay focused on 1D scope**: do NOT implement L2-L7 primitives

## Workflow

1. Setup
2. Read previous handoffs (1A, 1B, 1C progress reports)
3. Read SPECIFIC PRD/SDD sections:
   - PRD FR-L1 + Appendix D (protected-class taxonomy)
   - SDD §1.4.1 sub-section (line 338) + §5.3 (line 1693)
   - Source issue #653 (https://github.com/0xHoneyJar/loa/issues/653) for full RFC
4. Write 6 failing tests
5. Verify tests FAIL
6. Implement
7. Verify tests PASS
8. Run regression suites
9. Commit with `feat(cycle-098-sprint-1D): L1 hitl-jury-panel skill`
10. Push
11. Write progress report at `grimoires/loa/a2a/sprint-1/progress-1D.md`

## Output

Brief structured report:
1. Outcome
2. Files added (count + key paths) — should include `.claude/skills/hitl-jury-panel/SKILL.md`
3. Tests added
4. Regression status
5. Commit hash
6. Cost
7. Sprint-1 readiness for consolidated /review-sprint + /audit-sprint
8. Any blockers
```

### Consolidated /review-sprint brief (fire when 1D completes)

```
Run /review-sprint sprint-1 (cycle-098-agent-network) on the consolidated 4-sub-sprint branch `feat/cycle-098-sprint-1`. Implementation report aggregated from `grimoires/loa/a2a/sprint-1/progress-{1A,1B,1C,1D}.md`. Sprint plan: `grimoires/loa/sprint.md`. PRD: `grimoires/loa/prd.md`. SDD: `grimoires/loa/sdd.md`.

The 4 sub-sprints landed:
- 1A: JCS canonicalization + audit envelope foundation (commit 2774a32)
- 1B: Trust + identity (Ed25519, trust-store, OPERATORS.md, fd-secrets, protected-classes)
- 1C: Cross-cutting ops (sanitize_for_session_start, tier-validator, /loa status, hash-chain recovery)
- 1D: L1 hitl-jury-panel skill

Adversarial protocol mandatory: ≥3 concerns, ≥1 challenged assumption, ≥1 alternative not considered. Cross-model adversarial review (Phase 2.5) mandatory. AC verification per Issue #475 (walk every AC verbatim from PRD FR-L1-1..9 + SDD §6 Sprint 1 ACs + cross-cutting CC-1..CC-11).

Output to `grimoires/loa/a2a/sprint-1/engineer-feedback.md`. State transition: REVIEWING → AUDITING (approved) or → IMPLEMENTING (changes required).
```

### Consolidated /audit-sprint brief (fire when /review-sprint approves)

```
Run /audit-sprint sprint-1 (cycle-098-agent-network). Branch `feat/cycle-098-sprint-1` reviewed and approved by /review-sprint. Cross-model adversarial clean. Engineer feedback at `grimoires/loa/a2a/sprint-1/engineer-feedback.md`.

Paranoid cypherpunk auditor stance. 7-area security checklist + 10 paranoia red-team checks per `.claude/skills/auditing-security/SKILL.md`. Particular attention to:
- Ed25519 key handling (no argv leakage; mode 0600; trap cleanup)
- fd-based password loading (process inspection tests; no env var leak)
- Audit envelope signing (canonicalization + signature attest)
- Protected-class taxonomy (10 classes per PRD Appendix D; can operator add malicious classes?)
- Trust-store root-of-trust (release-signed git tag verification; offline root key chain)
- Sanitize_for_session_start (prompt-injection layered defense; tool-call boundary)
- Hash-chain recovery (gap markers; tracked vs untracked log paths)

If APPROVED — LETS FUCKING GO: create COMPLETED marker at `grimoires/loa/a2a/sprint-1/COMPLETED`. State: AUDITING → COMPLETED.
```

### Bridgebuilder kaironic on Sprint 1 PR (fire when audit approves)

```
Run iterative Bridgebuilder kaironic on the Sprint 1 PR (will be created against main from feat/cycle-098-sprint-1). Per `grimoires/loa/memory/feedback_kaironic_flatline_signals.md` stopping criteria. Max 5 iterations. Single PR carries 4 sub-sprints' worth of code (JCS + envelope + trust + identity + cross-cutting + L1 hitl-jury-panel).

Expect 2-4 iterations given large surface area. Implement fixes for Critical/High findings in-place; PRAISE/SPECULATION/REFRAME captured for cycle-099. Stop on plateau (HC plateau, finding-rotation, REFRAME emergence, factually-stale findings).
```

### Final PR creation prompt

```
Create draft PR for Sprint 1 (cycle-098-agent-network):
- Branch: feat/cycle-098-sprint-1
- Base: main
- Title: feat(cycle-098): sprint-1 — L1 hitl-jury-panel + cross-cutting infrastructure
- Description: use template at grimoires/loa/cycles/cycle-098-agent-network/pr-description-template.md, fill in:
  - Sub-sprint summary (1A, 1B, 1C, 1D each: commit + lines)
  - AC traceability (PRD FR-L1-1..9 + SDD §6 Sprint 1 ACs + cross-cutting CC-1..CC-11)
  - Test counts (pytest + bats)
  - Quality gate verdicts (review APPROVED, audit APPROVED, cross-model clean, bridgebuilder kaironic)
  - Maintainer root pubkey fingerprint (channel 1 of 3): e7:6e:ec:46:0b:34:eb:61:0f:6d:b1:27:2d:7e:f3:64:b9:94:d5:1e:49:f1:3a:d0:88:6f:a8:b9:e8:54:c4:d1
- After all gates green: gh pr ready, then admin-squash merge
```

---

## Vision content backup

These 5 visions are persisted in:
1. **GitHub issues** #680-#684 (canonical record)
2. **Local entry files** at `grimoires/loa/visions/entries/vision-013.md` through `vision-017.md` (gitignored)
3. **Index** at `grimoires/loa/visions/index.md` (statistics updated to 15 captured; uncommitted change in stash `vision-index-update-deferred`)

Brief summaries (full content in issues):

### vision-013 / issue #680
**Per-PR opt-in flag for Loa-content bridgebuilder review** (`review-loa-content: true`). Discovered during PR #678 bridge iter-1 REFRAME `loa-content-excluded`. The Loa-aware filter excludes `grimoires/loa/*` from bridgebuilder review payload — correct for code PRs, wrong for planning PRs.

### vision-014 / issue #681
**CI guard for `*.bak` and backup-sibling files**. Discovered during PR #678 bridge iter-1+2+4. Policy-as-code beats policy-as-comment. Counterpart: vision-017 (root-cause REFRAME — stop emitting siblings entirely).

### vision-015 / issue #682
**RFC 3647 Certificate Policy for audit-key bootstrap**. Discovered during PR #678 bridge iter-1 SPECULATION `audit-key-cert-policy`. Cycle-098's audit-keys-bootstrap README is operational; this is the formal policy layer.

### vision-016 / issue #683
**Stacked diffs for incremental SDD changes** (Sapling/Phabricator-style). Discovered during PR #678 bridge iter-3+5 meta-commentary. Cycle-098's PR #678 was +6155/-2223 — the deliberative trail is hostile to reviewers.

### vision-017 / issue #684
**Planning tooling stops emitting `.bak` siblings entirely** (REFRAME — root-cause counterpart to vision-014). cycle-098 PR #678's initial commit accidentally included 1386 lines of `.bak` content. The right fix is to stop emitting them, not just to gitignore them harder.

---

## Memory backup

Auto-memory file: `~/.claude/projects/-home-merlin-Documents-thj-code-loa/memory/MEMORY.md`

Key memory entry: `project_cycle098_session.md` — captures session learnings (subagent worktree-isolated delegation, ledger activation sequence, Python function-local-import scoping rule, curl `-d "$payload"` MAX_ARG_STRLEN bug, kaironic convergence on planning vs code PRs).

---

## Sprint 2 (L2 cost-budget-enforcer) prerequisites — clear

Existing infrastructure that L2 will compose with:
- `.claude/scripts/cost-report.sh` (Hounfour Sprint 3) — reads `grimoires/loa/a2a/cost-ledger.jsonl` per-call ledger
- `.claude/scripts/measure-token-budget.sh` (existing budget tooling)
- `.claude/scripts/lib/event-bus.sh` (PR #215, sprint-bug-127) — for verdict event publishing
- `.claude/scripts/lib/schema-validator.sh` — for verdict envelope validation
- 1A's audit envelope schema (CC-2 + CC-11) — verdicts use shared schema
- 1B's signing infrastructure — verdicts signed
- 1B's protected-class router — `budget.cap_increase` class

L2 will:
- Extend per-call cost-ledger.jsonl → daily aggregate via audit-envelope-typed verdicts
- Add reconciliation cron (un-deferred from FU-2 per SKP-005)
- Add daily snapshot job (RPO 24h for `.run/cost-budget-events.jsonl` per SKP-001 §3.4.4↔§3.7)

No structural blockers for Sprint 2.

---

## Resumption checklist (next session, in order)

1. **Read this file**
2. **Verify state**:
   - `git log main --oneline -5` (confirm 5 commits today: 7427227, 0b81d9c, 9341930, 2a05d86, b882c9f)
   - `git fetch origin && git log origin/feat/cycle-098-sprint-1 --oneline -5` (see how many sub-sprints landed)
   - `git worktree list` (any agent-* worktrees still locked = agents still running)
   - `gh pr list --state open` (open PRs requiring action)
3. **Check Sub-sprint 1B status**:
   - If `progress-1B.md` exists at `grimoires/loa/a2a/sprint-1/progress-1B.md` → 1B done, fire 1C with brief from this doc
   - Else → 1B may be running or crashed; check for active agents in `git worktree list`
4. **If sub-sprints incomplete, fire next via Agent call** using briefs in this doc
5. **If Sprint 1 complete (4 sub-sprints landed)**, fire `/review-sprint sprint-1`, then `/audit-sprint sprint-1`, then bridgebuilder kaironic, then PR + admin-merge
6. **After Sprint 1 ships**: fire `/run sprint-2` for L2 cost-budget-enforcer

## Outstanding manual operator actions

- [ ] Encrypt `~/.config/loa/audit-keys/cycle098-root.priv` with passphrase (currently unencrypted) — defer to Sprint 1 final hardening
- [ ] Eventually create release-signed git tag `cycle-098-root-key-v1` (after Sprint 1 ships) for the multi-channel fingerprint chain
- [ ] Migrate root key to YubiKey/hardware token before formal cycle-098 release (Sprint 1 ACs cover this design; operator does the actual ceremony)

---

*This resumption brief is the canonical handoff for any future session. Update at session end (or before walking away) to keep it accurate.*
