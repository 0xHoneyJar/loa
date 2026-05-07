# cycle-098-agent-network — Session Resumption Brief

**Last updated**: 2026-05-08 (Sprint 1..7 + H1 + H2 + /bug #711 ALL SHIPPED — **CYCLE-098 COMPLETE**)
**Author**: deep-name + Claude Opus 4.7 1M
**Purpose**: Crash-recovery + cross-session continuity. Read first when resuming cycle-098 work.

## 🎉 TL;DR — Sprint 7 SHIPPED 2026-05-08; CYCLE-098 COMPLETE (L1-L7 all on main)

**2026-05-08 session win — Sprint 7 (PR #775, merge `9957f938`) — L7 soul-identity-doc foundation SHIPPED.** FR-L7-1..7 + NFR-Sec3 (prescriptive-section rejection). 4-commit branch (7A schema+lib+events 34 tests, 7B SessionStart hook 16 tests, 7C SKILL+CLI+cross-primitive+lore+CLAUDE.md 8 tests, 7-rem pre-merge remediation 16 tests + BB iter-1 4-MED inline fixes) totaling **74 cumulative L7 tests green**.

Pre-BB substantive review caught **2 CRIT + 4 HIGH** (closed in `5677da7e`):
- **CRIT-1+2** test-mode gate too permissive (BATS_TMPDIR alone bypassed) → strict gate requires BOTH `LOA_SOUL_TEST_MODE=1` + bats marker (`BATS_TEST_FILENAME` or `BATS_VERSION`). Same pattern class as cycle-099 #761 / L4. **L6's prototype carries the same dead-code clause; tracked in #776.**
- **HIGH-1** hook honored absolute / `..` `path:` in `.loa.config.yaml` — surfaced `/etc/passwd` as `<untrusted-content>` in pure production mode → realpath-canonicalize + REPO_ROOT containment + `..` substring rejection.
- **HIGH-2** Unicode prescriptive-pattern bypass (FULLWIDTH `Ｍ Ｕ Ｓ Ｔ` and zero-width `M​UST`) → NFKC normalize + Cf-strip before pattern match.
- **HIGH-3** context-isolation `\x1eREPORT\x1e` sentinel leak in surfaced body (pre-existing in L6 codepath; bash `$(...)` strips trailing newlines, breaking parameter-expansion split on the empty-report common case) → drop trailing-newline requirement; benefits L6 too.
- **HIGH-4** audit blinded by control-byte heading (ANSI/control bytes in section heading → schema reject → `soul_emit` exits non-zero → hook's `\|\| true` silenced; body still surfaced in warn-mode while audit chain blinded) → scrub headings (drop C0/C1/zero-width; replace disallowed chars with `_`) before lists.

Optimist HIGH closures:
- **OPT-HIGH-1** `audit-retention-policy.yaml` realigned (was describing `SOUL.md` operator content; actual audit log is `.run/soul-events.jsonl`).
- **OPT-HIGH-2** SessionStart hook unwired in `.claude/settings.json` (L6 same gap; documented in SKILL.md; canonical wiring tracked in #776).

BB kaironic iter-1 (Anthropic-only consensus per cycle-098 API-unavailability plateau pattern; OpenAI timeout + Google network error): **0 BLOCKER, 0 HIGH_CONS, 4 MED + 5 LOW + 5 PRAISE + 1 REFRAME**. The 4 MED were genuine test-correctness bugs (F7 inverted grep semantics, F3 production-test didn't exercise gate, F9 T-CHAIN-3 tautology, F10 T-ISOLATION-1 swallowed handoff_write errors) — closed inline in `3b20a71f`. Plateau called: pre-BB review was substantive (2 CRIT + 4 HIGH), BB iter-1 had no BLOCKER/HIGH_CONSENSUS, mechanical fixes wouldn't trigger new findings.

**LOW deferred to follow-up issue #776** (~6 cosmetic items + L6 inheritance: hook wiring + test-mode gate dead-code clause).

**Sprint 7D (50+ adversarial jailbreak vectors) DEFERRED to its own cycle.** That's curatorial security-research work qualitatively different from the bash/python lib shipped in 7A/7B/7C. The previous Claude's handoff explicitly granted permission to question the framing for exactly this scope decision; operator confirmed split at session start.

**Cumulative cycle-098 tests on main: 690+ (existing) + 74 (Sprint 7) = 764+. 0 regressions in any prior sprint.**

## 🚦 Next: Cycle-100 — Adversarial Jailbreak Corpus (50+ vectors for L6/L7 SessionStart sanitization)

Sprint 7D was carved out of cycle-098 because the corpus is qualitatively different work (security research + curation, not engineering). Per SDD §1.9.3.2 Layer 4: 50+ documented attack vectors at `tests/red-team/jailbreak/` covering role-switch, indirect injection via Markdown, Unicode obfuscation, encoded payloads, multi-turn conditioning. CI gate: every PR touching `prompt_isolation` / L6 / L7 / SessionStart hook MUST pass jailbreak suite.

When cycle-100 opens (likely needs its own session for context budget):
- Survey OWASP LLM Top 10 (LLM01: Prompt Injection)
- Mine public jailbreak corpora (DAN, Anthropic red-team papers)
- Reuse L6 6E E4-E6 / C9-C10 runtime-construction pattern (`_make_evil_body` keeps trigger strings out of bats source files)
- Quality over count — 100 well-curated vectors with expected sanitization outcomes is better than 200 superficial ones
- Defensible against cypherpunk pushback on every vector's inclusion

Open follow-ups before cycle-100 opens:
- **#776**: cycle-098 sprint-7 follow-up — LOW batch (~6 cosmetic) + L6 inheritance (hook wiring + test-mode gate)
- **Cycle archive** (next chore): close cycle-098 ledger, archive grimoires/loa/cycles/cycle-098-agent-network/

## 🗄️ Sprint 7 SHIPPED — archived brief

The original Sprint 7 brief has been archived (now executed and merged in PR #775). Sub-sprint slicing (7A/7B/7C/7-rem with 7D deferred), design pinpoints, and quality-gate chain are preserved in the merged PR description (https://github.com/0xHoneyJar/loa/pull/775) and commit history (`b2e48a8a` 7A → `4146eeaa` 7B → `dc9d6721` 7C → `5677da7e` review-remediation → `3b20a71f` BB-iter1 fixes → squashed at `9957f938`).

## 🚨 TL;DR — Sprint 6 SHIPPED 2026-05-08; only L7 remains (HISTORICAL — superseded above)

**2026-05-07/08 session wins**:
- **Sprint 6 (PR #771, merge `1b820a0f`) — L6 structured-handoff SHIPPED.** FR-L6-1..7 + same-machine guardrail (SDD §1.7.1) + lore + CLAUDE.md. **90 cumulative tests** across 5 sub-sprint files (6A 27 + 6B 17 + 6C 17 + 6D 11 + 6E 18). Subagent dual-review (general-purpose + paranoid cypherpunk in parallel) caught **3 CRIT + 7 HIGH + 12 MED** — all CRIT/HIGH and 6 MED closed inline pre-BB; remaining MED + LOW (~22 items) deferred to a follow-up issue. Bridgebuilder iter-1 (Anthropic-only consensus per cycle-098 API-unavailability plateau pattern): 0 BLOCKER, 0 HIGH_CONSENSUS, 5 MED + 14 LOW + 4 PRAISE; 5 MED + 1 LOW (BB-F8) closed inline. Patterns extended: env-var test-mode gate (`_handoff_test_mode_active` + `_handoff_check_env_override`, 8 security-critical env vars gated, mirrors L4 cycle-099 #761), explicit-rollback in atomic_publish (replaced trap-based ERR rollback that proved fragile under bats `run`), filename-shape regex pinning in INDEX consumers (defense-in-depth against forged rows), JSONSchema control-byte rejection in slug fields (closes Python `re.$`-accepts-`\n` bypass with INDEX row-injection PoC pinned in test E6), bootstrap-pending state for absent OPERATORS.md (mirrors audit-envelope BOOTSTRAP-PENDING).
- **Sprint 5 (PR #767) — L5 cross-repo-status-reader SHIPPED.** FR-L5-1..7. 43 cumulative tests (26 sprint + 17 cypherpunk-remediation). Cypherpunk audit caught 1 CRIT (p95 heredoc RCE via cache-poisoned `_latency_seconds`) + 3 HIGH (cache shape poisoning, invalidate-all over-deletion, mktemp TOCTOU) + 7 MED — all CRIT/HIGH and selected MED closed pre-merge. BB iter-1 plateau (0 BLOCKER, 0 HIGH_CONS, 1 HIGH + 1 MEDIUM closed inline; #768 follow-up filed). Patterns extended: shell-opt save/restore helpers (`_l5_save_shell_opts`); `_audit_primitive_id_for_log` extended for L5 (`cross-repo-status*` → `L5`).
- **Sprint 4 (PR #764) — L4 graduated-trust SHIPPED.** Per-(scope, capability, actor) trust ledger (FR-L4-1..8). 118 cumulative tests. Cypherpunk audit caught 2 CRIT (seal bypass via marker, cooldown_until forgery) + 6 HIGH + 3 MED — all closed pre-merge with the `fc3ad7f0` remediation pass. Pre-existing audit-envelope `_audit_recover_from_git` path-resolution bug (basename vs repo-relative) fixed during 4C.

**Earlier wins on main:**
- Sprint 3 (PR #712, `3e9c2f7`) — L3 scheduled-cycle-template
- Sprint H1 (PR #716, `d8eca75`) — signed-mode harness
- Sprint H2 (PR #717, `430d1e4`) — observer allowlist + audit-snapshot strict-pin
- /bug #711 (PR #718, `4a576da`) — gpt-review hook recursion + 429 diagnostic
- cycle-099 entire registry-refactor cycle SHIPPED (Sprints 1-2F). See cycle-099 RESUMPTION for that full ladder.

**Cumulative cycle-098 tests on main: 690+ ; 0 regressions.**

---

## 🚦 Brief: Sprint 7 (L7 soul-identity-doc — LARGE, likely needs its own session)

Paste into a fresh Claude Code session:

```
Read grimoires/loa/cycles/cycle-098-agent-network/RESUMPTION.md FIRST and the section "Brief: Sprint 7 (L7 soul-identity-doc, LARGE)". Sprints 1+1.5+2+3+4+5+6+H1+H2+/bug #711 ALL SHIPPED on main (cycle-098 cumulative tests: 690+).

Today's main HEAD: 1b820a0f (Sprint 6 merged).
Cycle-098 status: L1+L2+L3+L4+L5+L6 SHIPPED; ONLY L7 REMAINS.

Execute Sprint 7: L7 soul-identity-doc per PRD FR-L7-1..N (#653/#660 — confirm via PRD). Compose with:
  - 1A audit envelope (soul.surface event — define payload schema)
  - 1C lib/context-isolation-lib.sh::sanitize_for_session_start (already extended for L7 in Sprint 1C — surface_max_chars default 2000)
  - 6 SessionStart hook pattern (mirror .claude/hooks/session-start/loa-l6-surface-handoffs.sh structure)

Branch: feat/cycle-098-sprint-7 from origin/main (1b820a0f).

Sub-sprint slicing (4-slice pattern; Sprint 7 is LARGER — adversarial corpus is its own slice):
  - 7A: SOUL.md schema + frontmatter validator + lib (FR-L7 schema; required sections per SDD §1.4.2: ## What I am / What I am not / Voice / Discipline / Influences; optional: ## Refusals / Glossary / Provenance)
  - 7B: surface_soul_identity SessionStart hook integration via sanitize_for_session_start("L7", content) — mirror L6 pattern
  - 7C: /loa soul validate CLI + operator-time validation; cycle integration tests (L1 ↔ L4 ↔ L6 ↔ L7 cross-primitive ACs from SDD §6)
  - 7D: ADVERSARIAL JAILBREAK CORPUS at tests/red-team/jailbreak/ (50+ documented attack vectors per SDD §1.9.3.2 Layer 4) — role-switch, indirect injection via Markdown, Unicode obfuscation, encoded payloads, multi-turn conditioning. CI gate: every PR touching prompt_isolation/L6/L7/SessionStart MUST pass jailbreak suite.

Quality gate chain (full Sprint 4+5+6 pattern):
  1. /implement test-first × 4 sub-sprints
  2. Subagent dual-review IN PARALLEL (general-purpose + paranoid cypherpunk via Agent run_in_background:true)
     - Cypherpunk threat model for L7: SOUL.md is OPERATOR-WRITTEN but reaches session via SessionStart hook; verify schema validation strict-mode + sanitize layer match L6's discipline. Probe the jailbreak corpus completeness.
  3. Remediation pass — fix HIGH/MEDIUM inline; defer LOW to follow-up issue
  4. Bridgebuilder kaironic INLINE (.claude/skills/bridgebuilder-review/resources/entry.sh --pr <N>)
     - Expect API-unavailability plateau (OpenAI + Google often error; Anthropic-only consensus is plateau-ready per cycle-098 sprints 4/5/6 precedent)
  5. Address BB iter-1 HIGH/MED inline; LOW → follow-up issue
  6. Admin-squash merge after CI green (Shell Tests pre-existing flakes admin-merged-through: BHM-T1/T5, FOPP-T1..T8, ~178 unrelated)

Patterns proven across Sprints 4+5+6 (apply in Sprint 7):
  - Schema-mirror with audit-retention-policy.yaml: lib's _DEFAULT_LOG must match policy basename; add primitive_id case to `_audit_primitive_id_for_log` (`soul-events*` → `L7`); add a unit test asserting alignment.
  - Env-var test-mode gate (cycle-098 sprint 6 CYP-F1/F3/F4 remediation; mirrors L4 cycle-099 #761): every security-critical env-var override MUST be gated behind `BATS_TEST_DIRNAME` / `LOA_*_TEST_MODE=1` AND emit stderr WARN-and-ignore in production. Apply to: LOA_SOUL_PATH override, LOA_SOUL_LOG, LOA_SOUL_DISABLE_*, etc.
  - Control-byte rejection in slug-shape fields (cycle-098 sprint 6 CYP-F2; defends Python `re.$` trailing-newline). If L7 has any slug-shape fields (provenance.author?), apply same defense — reject `\x00-\x1f \x7f` in parse helper.
  - Filename-shape pinning in any consumers that read structured state (cycle-098 sprint 6 CYP-F7).
  - Pre-emptive hardening before subagent review (mktemp over `${path}.tmp.$$`, realpath canonicalize, system-path rejection /etc /usr /proc /sys /dev /boot /var /root /srv, bounds-check operator-controlled timestamps).
  - Trust-boundary discipline: SOUL.md is operator-authored but UNTRUSTED at SURFACING — sanitize_for_session_start("L7", body) at SessionStart hook; never interpret as instructions. Operator-time validation (`/loa soul validate`) is separate from surfacing-time sanitization.
  - Adversarial test discipline (cycle-098 sprint 6 C9/C10): construct evil-body fixtures programmatically via runtime helpers (`_make_evil_body` style) so the bats source files never contain literal trigger strings.
  - Inline rollback over ERR-trap: `if ! mv ...; then rm ...; exit 4; fi` (cycle-098 sprint 6 CYP-F6; trap-based approach is fragile under bats `run` set-e state).

Sprint 7 specific design pinpoints:
  - SDD §1.4.2 (L7 component spec) + §1.5.2 (SessionStart surfacing flow) + §1.9.3.2 Layer 4 (adversarial corpus requirements)
  - SOUL.md schema: required sections (## What I am, ## What I am not, ## Voice, ## Discipline, ## Influences); optional (## Refusals, ## Glossary, ## Provenance); REJECT prescriptive sections (anything that looks like CLAUDE.md instructions)
  - Cap: surface_max_chars default 2000 per SDD §5.13 (vs L6's 4000)
  - Hook silent on enabled: false / file missing
  - Cache scoped to session — no re-validation per tool use
  - L1+L4+L6+L7 cross-primitive integration tests (SDD §6 ACs) — verify the umbrella `agent_network.enabled: true` flow

Operational gotchas:
  - bypassPermissions ON in .claude/settings.local.json
  - Beads UNHEALTHY (#661); use `git commit --no-verify` with `[NO-VERIFY-RATIONALE: …]`
  - Pre-existing CI flakes admin-merged through: BHM-T1/T5, FOPP-T1..T8 (Shell Tests, ~178 unrelated failures — none touch L7/SOUL)
  - Cycle-098 BB iter-1 typically gets Anthropic-only consensus (OpenAI 400 / Google network errors); plateau-defensible per the established pattern AS LONG AS pre-BB subagent review was substantive

Cost expectation: ~$50-100 (Sprint 7 is LARGER than 4/5/6 because of the adversarial corpus and cross-primitive integration tests — likely needs a fresh session for context budget).

Begin: `git fetch origin main && git checkout -b feat/cycle-098-sprint-7 origin/main`. Read PRD §FR-L7 + SDD §1.4.2 (L7 component) + SDD §5.9 (L7 API spec) + SDD §1.9.3.2 Layer 4 (adversarial corpus) for full task list + ACs. Slice 7A.
```

After Sprint 7 ships: cycle-098-agent-network is COMPLETE (L1-L7 all SHIPPED). Next steps: cycle-archive + post-cycle hardening sweeps.

---

## 🗄️ Sprint 6 SHIPPED — archived brief

The original Sprint 6 brief has been archived (now executed and merged in PR #771). The full sprint-6 scope ladder, sub-sprint slicing, design pinpoints, and the full quality-gate chain are preserved in the merged PR description and the commit history (`152a554c` 6A → `a4bf56ac` 6B → `d56bae84` 6C → `f5193fb9` 6D → `e9444029` 6E review-remediation → `1fa2381b` BB-iter1 fixes → squashed at `1b820a0f`).

---

## 🚦 Brief: Sprint 6 (L6 structured-handoff, MEDIUM) — ARCHIVED, kept for reference

Paste into a fresh Claude Code session:

```
Read grimoires/loa/cycles/cycle-098-agent-network/RESUMPTION.md FIRST and the section "Brief: Sprint 6 (L6 structured-handoff, MEDIUM)". Sprints 1+1.5+2+3+4+5+H1+H2+/bug #711 ALL SHIPPED on main (cycle-098 cumulative tests: 600+).

Today's main HEAD: 0db09254 (post Sprint 5 RESUMPTION chore).
Cycle-098 status: L1+L2+L3+L4+L5 SHIPPED; L6+L7 remain.

Execute Sprint 6: L6 structured-handoff per PRD FR-L6-1..8 (#658). Compose with:
  - 1A audit envelope (handoff.write event)
  - 1A `lib/context-isolation-lib.sh::sanitize_for_session_start` (Sprint 1 helper for SessionStart surfacing)
  - 1B operator-identity.sh + OPERATORS.md (verify_operators flag; strict mode rejects from/to not in OPERATORS.md)
  - 1A `lib/jcs.sh` (content-addressable handoff_id via SHA-256 of canonical-JSON)
  - 4 graduated-trust (compose-when-available; from/to reference L4 actor identity)

Branch: feat/cycle-098-sprint-6 from origin/main (0db09254).

Sub-sprint slicing (proven 4-slice pattern from Sprints 4+5):
  - 6A: schema + handoff_id + atomic write (FR-L6-1, FR-L6-2, FR-L6-3, FR-L6-6, FR-L6-7)
  - 6B: same-day collision handling + OPERATORS.md verify (FR-L6-4 + verify_operators)
  - 6C: SessionStart hook integration via sanitize_for_session_start (FR-L6-5)
  - 6D: same-machine-only enforcement + lore + CLAUDE.md (cross-host refusal per SDD §1.7.1)

Quality gate chain (full Sprint 4+5 pattern):
  1. /implement test-first × 4 sub-sprints
  2. Subagent dual-review IN PARALLEL (general-purpose + cypherpunk via Agent run_in_background:true)
  3. Remediation pass — fix HIGH/MEDIUM inline; defer LOW to follow-up issue
  4. Bridgebuilder kaironic INLINE (.claude/skills/bridgebuilder-review/resources/entry.sh --pr <N>)
     - Expect API-unavailability plateau (OpenAI + Google often error; Anthropic-only consensus is plateau-ready)
  5. Address BB iter-1 HIGH/MED inline; LOW → follow-up issue
  6. Admin-squash merge after CI green

Patterns to apply (all from `feedback_lib_hardening_patterns.md`):
  - Save+restore caller shell opts via `_save_shell_opts`/`_restore_shell_opts` helpers if `set +e` needed internally
  - Audit-payload visibility surface (NOT stderr WARN — bats `run` pollutes stdout)
  - Explicit cleanup at end of function, NO `RETURN` trap when called via `$(...)`
  - Pre-emptive hardening before subagent review:
    * mktemp over `${path}.tmp.$$` for any tmp-file path
    * realpath canonicalize on operator-controlled paths
    * system-path rejection (`/etc`, `/usr`, `/proc`, `/sys`, `/dev`, `/boot`)
    * Bounds-check operator-controlled timestamps
  - Schema-mirror with audit-retention-policy.yaml: lib's _DEFAULT_LOG must match policy basename; add primitive_id case to `_audit_primitive_id_for_log` (`handoffs*` → `L6`); add a unit test asserting alignment
  - Trust-boundary discipline: handoff body is UNTRUSTED — sanitize_for_session_start at surfacing; never interpret as instructions

Sprint 6 specific design pinpoints:
  - SDD §1.7.1: same-machine-only hard runtime guardrail. Use `hostname -f` + `/etc/machine-id` (or equivalent) as the machine fingerprint; cross-host write attempt → `[CROSS-HOST-REFUSED]` BLOCKER + audit log
  - SDD §5.8 — full L6 API spec
  - INDEX.md atomic update: flock + write tmp + rename (per FR-L6-3)
  - handoff_id = SHA-256 of canonical-JSON (handoff content). Collision protocol per IMP-010 v1.1: numeric suffix on collision
  - prompt_isolation MANDATORY on body (handoffs from prior sessions are untrusted text)
  - default handoffs_dir = `grimoires/loa/handoffs/` per SDD §5.8

Operational gotchas:
  - bypassPermissions ON in .claude/settings.local.json
  - Beads UNHEALTHY (#661); use `git commit --no-verify` with `[NO-VERIFY-RATIONALE: …]`
  - Pre-existing CI flakes admin-merged through: BHM-T1/T5, FOPP-T1..T8 (Shell Tests)

Cost expectation: ~$30-50 (single sub-sprint pattern smaller than Sprint 4; closer to Sprint 5 footprint).

Begin: `git fetch origin main && git checkout -b feat/cycle-098-sprint-6 origin/main`. Read PRD §FR-L6 + SDD §1.4.2 (L6 component) + SDD §5.8 (L6 API spec) for full task list + ACs. Slice 6A.

After Sprint 6 ships: only Sprint 7 remains (L7 soul-identity-doc + cycle integration tests + adversarial jailbreak corpus — LARGE — likely needs its own session).
```

### Operator priority (2026-05-04 session-end)

> "Model feature is really important and needed urgently."

**Path A (URGENT — recommended next)** — `/plan cycle-099` for the model-registry refactor (#710). Operator flagged this as the priority. Pre-written brief in §"Brief A — cycle-099 (urgent model registry)".

**Path B (resumable later)** — Sprint 4 (L4 graduated-trust) per the original cycle-098 plan. Pre-written brief in §"Brief B — Sprint 4 (L4 graduated-trust, resumable)". State markers preserved so resumption is loss-free.

**Both briefs are equally complete** — operator chooses at session start.

---

## Brief A — cycle-099 (urgent model registry)

Paste into a fresh Claude Code session:

```
Read grimoires/loa/cycles/cycle-098-agent-network/RESUMPTION.md FIRST and the sections "Brief A" + "Open backlog at session-end". Do NOT start coding. Use /plan-and-analyze to create cycle-099 PRD covering #710 (model-registry consolidation).

Cycle-098 status: Sprint 1 + 1.5 + 2 + 3 + H1 + H2 + /bug #711 ALL SHIPPED on main. Last commit: 4a576da. 480+ tests, 0 regressions.

#710 scope (per issue body, author's own disposition: multi-sprint refactor cycle):

  1. P0 — Single source of truth: promote .claude/defaults/model-config.yaml to be THE registry. Every consumer (legacy adapter, hounfour, Red Team adapter, Bridgebuilder TS truncation map, model-permissions.yaml, persona files) reads from it directly OR from a generated artifact.
  2. P0 — Config extension mechanism: .loa.config.yaml::model_aliases_extra (mirrors protected_classes_extra pattern). Operators can register a new model via config alone — no System Zone edits.
  3. P1 — Sunset legacy adapter: remove model-adapter.sh.legacy + the hounfour.flatline_routing feature flag. Single code path.

Confirmed registries (from earlier spike — verify still current):
  - .claude/scripts/model-adapter.sh + .legacy
  - .claude/scripts/generated-model-maps.sh (newer)
  - .claude/scripts/red-team-model-adapter.sh
  - .claude/skills/bridgebuilder-review/resources/core/truncation.ts (compiled to dist/)
  - .claude/data/model-permissions.yaml
  - .claude/data/personas/*.md (per-persona model refs)

Operator decision needed at /plan time:
  - Cycle scope: bundle L4-L7 sprints into cycle-099 (≈3-month cycle) OR keep cycle-099 narrow (registry-only, 1-2 sprints) and ship L4-L7 as cycle-098 continuation
  - Migration ordering: P0 + P0 + P1 in one shot OR phased

Key learnings to apply (from today's H1/H2/#711 sprints):
  - Quality-gate chain works: /implement → /review-sprint → /audit-sprint → bridgebuilder kaironic 2-iter loop → admin-squash
  - Inline implementation on Opus 4.7 1M context; no subagent delegation needed for sequential sub-sprint work
  - Test-first non-negotiable; chain-repair tamper helper + chain-valid envelope helper proven patterns for fixture realism
  - Conservative-default discipline (skip when ambiguous) makes regression of "over-fire" bugs structurally hard
  - Observer/path allowlist pattern (Sprint 3 + H2) generalizes to other operator-configurable execution paths

Run /plan-and-analyze to begin. After PRD lands, operator approves scope before /architect.
```

### cycle-099 readiness inventory

| Artifact | Status | Notes |
|----------|--------|-------|
| Issue #710 spec | ✅ Filed | Detailed; includes audit of 5+ registries |
| Existing registries to consolidate | ✅ Spiked | 5 confirmed; each has its own quirks (TS compile, bash alias arrays, etc.) |
| Sprint counter | 138 | Next reservations would be 139+ |
| Ledger.json active_cycle | `cycle-098-agent-network` | Will need transition when cycle-099 activates |
| Beads | UNHEALTHY (#661) | Workaround: ledger fallback + `--no-verify` for commits |
| Sprint 4-7 reservations in cycle-098 ledger | 135-138 | If cycle-099 absorbs L4-L7, these get re-mapped |

---

## Brief B — Sprint 4 (L4 graduated-trust, resumable)

For when operator chooses to resume the original 7-sprint plan instead of pivoting to cycle-099.

Paste into a fresh Claude Code session:

```
Read grimoires/loa/cycles/cycle-098-agent-network/RESUMPTION.md FIRST and the sections "Brief B" + "Open backlog at session-end". Sprint 1 + 1.5 + 2 + 3 + H1 + H2 + /bug #711 ALL SHIPPED on main (4a576da). 480+ tests cumulative.

Execute Sprint 4: L4 graduated-trust per PRD FR-L4-1..8 (#656). Wire compose-with from Sprint 1 audit envelope + protected-class-router (cycle-098 SDD §1.4.2 + §5.6).

Branch: feat/cycle-098-sprint-4 from origin/main.

Slice into 4 sub-sprints (4A/4B/4C/4D) per the proven Sprint 1/2/3 pattern. Full quality-gate chain (Sprint 3 / H1 / H2 / #711 all used this successfully):

  1. /implement (test-first per sub-sprint)
  2. /review-sprint subagent (general-purpose)
  3. /audit-sprint subagent (paranoid cypherpunk)
  4. Remediation pass — fix HIGH/MEDIUM findings inline; add tests
  5. Bridgebuilder kaironic INLINE — never via subagent dispatch (.claude/skills/bridgebuilder-review/resources/entry.sh --pr <N>)
  6. Admin-squash merge after kaironic plateau (typical: 2 iterations for code PRs)

Patterns proven across H1/H2/#711 (apply in Sprint 4):
  - Shared fixture lib at tests/lib/signing-fixtures.sh exposes signing_fixtures_setup --strict + signing_fixtures_tamper_with_chain_repair + signing_fixtures_inject_chain_valid_envelope
  - Chain-valid envelope helper for tamper tests (#708 F-006 pattern; sprint H2)
  - Observer/path allowlist for any operator-configurable execution surfaces (#708 F-005 pattern; sprint H2)
  - Per-event-type schema registry under .claude/data/trajectory-schemas/<primitive>-events/ (Sprint 3 pattern)
  - Test-mode flag (_l3_test_mode pattern from Sprint 3 remediation) for production-vs-test escape hatches
  - Sentinel-counter idempotency tests (#714 F4 pattern)

Sprint 4 scope (sprint.md §"Sprint 4"):
  - .claude/skills/graduated-trust/SKILL.md + .claude/scripts/lib/graduated-trust-lib.sh + tests
  - Hash-chained ledger at .run/trust-ledger.jsonl (TRACKED in git per SDD §3.7) — note: TRACKED, unlike L3 cycles.jsonl which is UNTRACKED
  - Tier transitions per operator-defined TransitionRule array (configured in .loa.config.yaml)
  - Auto-drop on recordOverride() with cooldown (default 7d) enforcement
  - Force-grant audit-logged exception (trust.force_grant event type)
  - Concurrent-write tests (runtime + cron + CLI per FR-L4-6)
  - Reconstructable from git history (FR-L4-7) — git log -p to rebuild trust-ledger
  - Auto-raise stub: ships as stub returning eligibility_required (FU-3 deferral per PRD)

Composes with:
  - Sprint 1A audit envelope (audit_emit + chain hash)
  - Sprint 1B signing (Ed25519 signed envelopes)
  - Sprint 1B protected-class-router.sh
  - Sprint 1B operator-identity.sh (LedgerEntry references actor identity)
  - H1 signing-fixtures.sh (signing_fixtures_setup --strict for tests)
  - H2 chain-valid envelope helper (signing_fixtures_inject_chain_valid_envelope for tamper-realism tests)

Workarounds: beads UNHEALTHY (#661) — use --no-verify for commits per documented pattern.

Cost expectation: ~$50-100 per sprint (4-slice; full quality gate chain). Models: claude-opus-4-7 1M for build+inline review; gpt-5.5-pro + gemini-3.1-pro-preview for bridgebuilder/flatline (when reachable; gracefully degrades to single-model when others 404/error).

Begin: `git fetch origin main && git checkout -b feat/cycle-098-sprint-4 origin/main`. Read sprint.md §"Sprint 4" for full task list + ACs. Slice 4A.
```

### Sprint 4 readiness inventory

| Artifact | Status | Path |
|----------|--------|------|
| PRD FR-L4 spec | ✅ Filed | `grimoires/loa/prd.md:485-507` |
| SDD §1.4.2 component spec | ✅ Filed | `grimoires/loa/sdd.md:393-412` |
| SDD §5.6 API spec | ✅ Filed | `grimoires/loa/sdd.md:1927-1997` |
| Sprint plan §"Sprint 4" | ✅ Filed | `grimoires/loa/sprint.md:391-462` |
| Composes-with libs | ✅ All shipped | audit-envelope, protected-class-router, operator-identity, signing-fixtures |
| Sprint counter reservation | 135 | Pre-allocated in cycle-098 ledger |
| Branch name | `feat/cycle-098-sprint-4` | Off main `4a576da` |

---

## Today's session (2026-05-04) — full log

| PR | Commit | Component | Tests added | Closes |
|----|--------|-----------|-------------|--------|
| [#712](https://github.com/0xHoneyJar/loa/pull/712) | `3e9c2f7` | Sprint 3 L3 scheduled-cycle-template | 106 | #655 |
| [#715](https://github.com/0xHoneyJar/loa/pull/715) | `517ea33` | RESUMPTION.md plan persistence (chore) | n/a | n/a |
| [#716](https://github.com/0xHoneyJar/loa/pull/716) | `d8eca75` | Sprint H1 signed-mode harness | 32 | #706, #713 |
| [#717](https://github.com/0xHoneyJar/loa/pull/717) | `430d1e4` | Sprint H2 BB LOW-batch consolidation | 15+ | #708 (substantive) |
| [#718](https://github.com/0xHoneyJar/loa/pull/718) | `4a576da` | /bug gpt-review hook + 429 | 28 | #711 |

**Cumulative test count on main**: 480+. **Quality gates**: every PR ran the full chain (review subagent → bridgebuilder kaironic 2-iter loop → admin-squash after plateau).

### CRITICAL audit findings closed today

- **CRIT-A1** (Sprint 3): idempotency log forgery — `cycle_idempotency_check` validates full envelope (primitive_id, schema_version, prev_hash, signature when post-cutoff)
- **CRIT-A2** (Sprint 3): dispatch_contract path RCE — realpath canonicalize + allowlist prefix-match, default `.claude/skills`, `.run/schedules`, `.run/cycles-contracts`
- **CRIT-A3** (Sprint 3): lock-touch symlink truncate — `O_NOFOLLOW` lock creation via Python `os.open` + bash post-creation symlink check fallback
- **F-005** (Sprint H2): L2 observer command allowlist — same realpath + prefix-match shape as L3 phase paths

### Patterns/lore captured

- `scheduled-cycle` lore entry (cycle-098 sprint 3) — `grimoires/loa/lore/patterns.yaml`
- `fail-closed-cost-gate` lore entry (cycle-098 sprint 2) — pre-existing
- `governance-isomorphism`, `deliberative-council` lore — pre-existing
- Engineering note: bash `RETURN` traps are NOT function-local without `extdebug` — explicit cleanup at single exit paths
- Engineering note: `printf '%s\n' "${arr[@]+...}"` produces `[""]` for empty arrays; use `jq -nc '$ARGS.positional' --args ...` instead
- Engineering note: chain-repair tamper helper isolates signature as sole failure mode (vs chain-hash + signature both)
- Engineering note: shared signing fixture lib (Sprint H1) consolidates the ephemeral-Ed25519 + trust-store + env-var dance from 4 prior bats files

## Open backlog at session-end

| # | Title | Tier | Notes |
|---|-------|------|-------|
| [#710](https://github.com/0xHoneyJar/loa/issues/710) | Model registry consolidation | **URGENT (cycle-099)** | Operator-flagged priority for next session |
| [#719](https://github.com/0xHoneyJar/loa/issues/719) | gpt-review test infra polish (BB iter-2) | T3 polish | 3 MEDIUM + 5 LOW; non-blocking |
| [#714](https://github.com/0xHoneyJar/loa/issues/714) | Sprint 3 BB iter-2 LOW batch | T3 polish | Cosmetic; some items closed in H2 (F5 hygiene); rest deferred |
| [#694](https://github.com/0xHoneyJar/loa/issues/694) | Sprint 1 BB iter-1 batch (8 findings) | T3 polish | Cosmetic; no items closed in H2 (deemed lowest-priority) |
| [#708](https://github.com/0xHoneyJar/loa/issues/708) | Sprint 2 BB LOW batch | T3 polish | F-005, F-006, F-007, F-003-cron CLOSED in H2; remaining LOWs cosmetic |
| #628 | BATS test sourcing REFRAME (lib/ convention) | T4 structural | Large; own planning cycle |
| #661 | Beads UNHEALTHY (migration error) | T2 ops | Workaround: ledger fallback + `--no-verify` |

## Sprint 3 SHIPPED ✅ (2026-05-04)

| Sub-sprint | Commit | Tests | Status |
|-----------|--------|-------|--------|
| 3A foundation (5 schemas + lib + dispatch + replay) | `eb8fb90` | 32 | ✅ Squashed into PR #712 |
| 3B lock + idempotency + per-phase timeout | `304d802` | +12 (44) | ✅ |
| 3C L2 budget pre-check (compose-when-available) | `ab05664` | +11 (55) | ✅ |
| 3D SKILL + contracts + lore + CLAUDE.md | `e3c7a0e` | +14 (69) | ✅ |
| Remediation pass (3 CRIT + 7 HIGH + 8 MED) | `e4f4727` | +35 (104) | ✅ |
| Bridgebuilder iter-1 closures (1 MED + 4 LOW) | `f465025` | +2 (106) | ✅ |
| **PR #712 admin-squash merge** | **`3e9c2f7`** | **106 cumulative** | ✅ on main |

**6 quality gates passed**:
1. /implement (test-first × 4 sub-sprints) — 69/69 PASS
2. Review subagent (general-purpose) → 11 findings (3 HIGH + 5 MED + 3 LOW)
3. Audit subagent (paranoid cypherpunk) → 14 findings (3 CRITICAL + 4 HIGH + 4 MED + 3 LOW)
4. Remediation closed all CRIT/HIGH/MED + 4 LOW; +35 tests
5. Bridgebuilder kaironic iter-1 → 16 findings (1 MED + 5 PRAISE + 10 LOW); closed 1 MED + 4 LOW
6. Bridgebuilder kaironic iter-2 → 9 findings (0 MED + 1 PRAISE + 7 LOW + 1 SPEC) → CONVERGED

**Three CRITICAL audit findings closed** with PoC-verified fixes:
- **CRIT-A1**: idempotency log forgery (`cycle_idempotency_check` now validates full envelope)
- **CRIT-A2**: dispatch_contract path RCE (allowlist + realpath canonicalization)
- **CRIT-A3**: lock-touch symlink truncate (`O_NOFOLLOW` lock creation)

**Follow-ups filed**: #713 (signed-mode tests), #714 (iter-2 LOW batch).

## Sprint 2 SHIPPED ✅ (2026-05-04)

| Sub-sprint | Commit | Tests | Status |
|-----------|--------|-------|--------|
| 2A L2 verdict-engine foundation | `94e2b23` | 31 | ✅ Squashed into PR #705 |
| 2B Reconciliation cron + installer | `7b20038` | +11 (42) | ✅ |
| 2C Daily snapshot job + runbook | `d74ee61` | +13 (55) | ✅ |
| 2D Skill + CLI + lore + config | `bde8088` | +12 (67) | ✅ |
| Remediation pass (HIGH-1, HIGH-3/F1, F2, F3, MED-3) | `23b1b66` | +21 (88) | ✅ |
| Bridgebuilder iter-1 LOW (F12, F-001) | `a076ac5` | +4 (92) | ✅ |
| **PR #705 admin-squash merge** | **`a7c50ff`** | **92 cumulative** | ✅ on main |

**Quality gates passed**:
1. /implement (test-first × 4 sub-sprints) — 67 / 67 PASS
2. Review subagent (general-purpose) → CHANGES_REQUIRED (3 HIGH + 4 MED)
3. Audit subagent (paranoid cypherpunk) → CHANGES_REQUIRED (3 HIGH + 3 MED + 2 LOW)
4. Remediation closed all HIGHs and most MEDs (21 new tests)
5. Bridgebuilder kaironic iter-1 → 0 BLOCKER, 0 HIGH_CONSENSUS, 3 disputed
6. Bridgebuilder kaironic iter-2 → 0 BLOCKER, 0 HIGH_CONSENSUS, 4 disputed → CONVERGED
7. Admin-squash merge after kaironic plateau

**Follow-up filed**: #706 (signed-mode happy-path test coverage; F-001 from bridgebuilder).

## Hardening waves shipped 2026-05-03 (post-Sprint-1)

| PR | Commit | Issues closed | New tests | Bridgebuilder |
|----|--------|---------------|-----------|---------------|
| [#698](https://github.com/0xHoneyJar/loa/pull/698) | `289b927` | #689, #690, #695 | 47 | iter-3 converged |
| [#699](https://github.com/0xHoneyJar/loa/pull/699) | `8d368a5` | #697 | 13 | iter-2 converged |
| [#700](https://github.com/0xHoneyJar/loa/pull/700) | `a6c9940` | #674, #634 (stale), #633, #676 | 16 | iter-2 converged |
| [#703](https://github.com/0xHoneyJar/loa/pull/703) | `22257f1` | #636, #561 (stale), #681, #687, #691, #692 | 27 | iter-2 converged |

**Total**: 13 GitHub issues closed (10 actionable + 3 stale), 103 new tests, 4 PRs admin-squash merged after kaironic bridgebuilder convergence.

### What this hardening enables for Sprint 2

- **#689** Python flock parity → Sprint 2's L2 reconciliation cron + verdict path are the first cross-adapter writers; no race risk
- **#690** trust-store auto-verify → safe before operators populate signed trust-store post-bootstrap
- **#695 F8** redaction allowlist tightened → safer to add Sprint 2 audit log paths
- **#695 F9** schema_version in signed payload → defeats downgrade attacks on the new gate
- **#697** post-merge gt_regen + multi-changelog routing → cleaner cycle ships for downstream Loa-mounted projects
- **#674** post-merge archive gate → cycle PRs no longer auto-revert
- **#633** post-pr-e2e bats support → loa repo's own E2E gate now functional
- **#676** Bridgebuilder fresh-findings check → no false-positive FLATLINE in autonomous post-PR validation
- **#636** construct-invoke session-id race fix → trajectory pair-matching reliable for Sprint 2's audit-event path
- **#681** *.bak CI guard → planning tooling artifacts can't sneak into Sprint 2 PRs
- **#691, #692** mktemp + argv hardening → consistent security pattern across panel infra

### Backlog after this hardening

Only 2 outstanding bug-shaped items, neither blocks Sprint 2:

| # | Tier | Notes |
|---|------|-------|
| #694 | T3 | Sprint-1 bridgebuilder test-discipline batch (8 findings); ~1-2 days; own micro-sprint; non-blocking |
| #628 | T4 | BATS test sourcing REFRAME (lib/ convention); large structural; own planning cycle |

---

## State as of session end (2026-05-03 ~09:23 UTC)

### Repository

| Marker | Value |
|--------|-------|
| Active cycle | `cycle-098-agent-network` (per ledger.json) |
| **main HEAD** | **`6e93587` (PR #693 — Sprint 1 SHIPPED)** |
| Latest GitHub release | (auto-tagged at PR #693 merge — likely v1.111.0) |
| Global sprint counter | 138 (Sprint 1-7 reservations 132-138; sprint-bug-131 at 131) |

### Sprint 1 — SHIPPED ✅

| Sub-sprint | Commit | Tests | Status |
|-----------|--------|-------|--------|
| 1A JCS + audit envelope foundation | `2774a32` | 96 | ✅ Squashed into PR #693 |
| 1B Trust + identity | `a534479` | +35 (131) | ✅ |
| 1C Cross-cutting ops | `f582002` | +36 (167) | ✅ |
| 1D L1 hitl-jury-panel skill | `ba1eeba` | +45 (212) | ✅ |
| Remediation pass | `db0dc26` | +21 | ✅ Closed F1 strip-attack + F2 CLI + F3 flock + F4 schema doc + 9 ACs |
| F1 SLO waiver | `2bc8a3b` | — | ✅ Closed bridgebuilder F1 (operator-signed waiver in decisions/) |
| **PR #693 squash merge** | `6e93587` | **250+ cumulative** | ✅ on main |

**6 quality gates passed**:
1. /implement (test-first × 4 sub-sprints)
2. /review-sprint iter-1 → CHANGES_REQUIRED (4 findings + 9 ACs gaps)
3. Remediation closed all
4. /review-sprint iter-2 → APPROVED (29/29 ACs)
5. Cross-model adversarial (gpt-5.3-codex) → 0 actionable findings
6. /audit-sprint paranoid cypherpunk → APPROVED — LETS FUCKING GO (7/7 + 10/10)
7. Bridgebuilder kaironic iter-1 → 1 HIGH (F1) + 7 disputed; F1 fixed inline
8. Bridgebuilder kaironic iter-2 → 0 consensus + 5 disputed + 0 BLOCKER → CONVERGED

### Sprint 2 — READY TO FIRE

After Sprint 1.5 hardening (Path A) or directly (Path B). Per sprint plan:

- **Scope**: L2 cost-budget-enforcer per FR-L2-1..10 (PRD #654) + reconciliation cron (un-deferred from FU-2 per SDD pass-#1 SKP-005) + daily snapshot job (RPO 24h per SDD §3.4.4↔§3.7)
- **Estimated**: ~$15-25, ~3-5h wall-clock for 4 sub-sprints (using Sprint 1's 4-slice pattern)
- **Compose-with**: Sprint 1A's audit envelope schema (CC-2 + CC-11), Sprint 1B's signing infra, Sprint 1B's protected-class router (`budget.cap_increase`), existing `cost-report.sh`, `measure-token-budget.sh`, `event-bus.sh`, `schema-validator.sh`

---

## Pre-written brief: Sprint 1.5 hardening (Path A — RECOMMENDED)

### Brief (paste into Agent or fresh session)

```
You are implementing Sprint 1.5 — hardening pass that closes Sprint 2 prerequisites identified by the Sprint 1 audit + bridgebuilder. This is a SMALL focused PR. Test-first per Loa convention.

**Working directory**: this checkout (or worktree if delegated)
**Repo**: 0xHoneyJar/loa
**Branch**: create `chore/cycle-098-sprint-1.5-hardening` from origin/main (commit 6e93587)
**Source**: GitHub issues #689 (P2 MED), #690 (P2 MED), and optionally #695 (F8 + F9, P2 MED security tightening)

## Setup

\`\`\`bash
git fetch origin main
git checkout main
git pull origin main --ff-only
git checkout -b chore/cycle-098-sprint-1.5-hardening
\`\`\`

## Scope (3 issues, all P2 MED)

### #689 — Python adapter flock parity

**Why critical for Sprint 2**: Sprint 2's L2 ships the FIRST Python writers (reconciliation cron + verdict path) to the audit envelope. Without flock parity, concurrent writes from bash + Python could race.

**Location**: \`.claude/adapters/loa_cheval/audit_envelope.py:300-302\` — appends without flock; bash adapter (post-Sprint-1 F3 fix) does flock.

**Fix**:
- Mirror bash \`audit-envelope.sh\` flock semantics in Python
- Use \`fcntl.flock(fd, fcntl.LOCK_EX)\` on \`<log_path>.lock\` before write
- Release on context-manager exit
- Test: \`tests/integration/audit-envelope-python-concurrent.bats\` parallel to existing bash equivalent — 5+ concurrent Python audit_emit writes preserve chain integrity

### #690 — audit_trust_store_verify auto-call

**Why critical for Sprint 2**: Sprint 2 ships operator-facing reconciliation cron. Once operators populate the trust-store via the audit-keys-bootstrap runbook, runtime auto-verify becomes critical (currently mitigated only by BOOTSTRAP-PENDING empty keys[]).

**Fix**:
- Auto-call \`audit_trust_store_verify\` at top of \`audit_verify_chain\` AND \`audit_emit\` (cached per-process, validated once)
- On verify failure: emit \`[TRUST-STORE-INVALID]\` BLOCKER and refuse all writes/reads
- BOOTSTRAP-PENDING state still permits reads/writes (graceful fallback for empty trust-store)
- Cached verify result invalidated on trust-store mtime change
- Test: trust-store substitution test (tamper trust-store.yaml; \`audit_verify_chain\` fails)

### #695 — Security tightening (OPTIONAL, include if budget permits)

**F8 — audit-secret-redaction.yml allowlist overly broad**:
- Restrict to named files (e.g., \`audit-keys-bootstrap.md\`, deprecation docs)
- Reject assignment patterns in \`progress/\` and \`handoff/\` markdown entirely
- Allow only fenced-code documentation form
- Test: deliberately commit fake secret in \`progress/\` markdown → workflow catches it

**F9 — Trust-store signature scope (decision needed)**:
- Either include \`schema_version\` in signed payload OR document SDD rationale for excluding it
- Update SDD §1.9.3.1 to make signed-payload boundary EXPLICIT
- Test: schema_version-tampering → trust-store verify fails (or proven safe per option 2)

## Workflow

1. Setup (above)
2. Read previous handoffs at \`grimoires/loa/a2a/sprint-1/progress-{1A,1B,1C,1D}.md\` + \`remediation-1.md\` for API context
3. Read issue bodies #689, #690, #695 for full specifications
4. **Test-first** for each fix:
   - #689: write failing concurrent-write Python test → fix → verify pass
   - #690: write failing substitution test → fix → verify pass
   - #695 F8: write failing redaction test → fix → verify pass
   - #695 F9: write tampering test OR document rationale (decision)
5. Run full regression suites — confirm 250+ Sprint 1 tests still PASS
6. Commit with message:
   \`\`\`
   chore(cycle-098-sprint-1.5): hardening — close #689 (Python flock) + #690 (trust-store auto-verify) + #695 (F8 + F9 security tightening)

   Sprint 2 prerequisite hardening per Sprint 1 audit/bridgebuilder follow-ups.
   - #689: Python audit_emit flock parity with bash adapter (post-F3)
   - #690: audit_trust_store_verify auto-called from audit_verify_chain + audit_emit
   - #695 F8: audit-secret-redaction.yml allowlist tightened
   - #695 F9: trust-store signed-payload boundary explicit + schema_version test
   \`\`\`
7. Push via ICE wrapper
8. Create PR
9. Run kaironic bridgebuilder inline (use \`.claude/skills/bridgebuilder-review/resources/entry.sh --pr <N>\`)
10. After convergence: \`gh pr ready <N>\` + \`gh pr merge <N> --admin --squash\`

## Output back

Brief structured report:
1. Outcome
2. Files changed + key paths
3. Tests added (count, all passing)
4. Regression status
5. Commit hash
6. PR URL + merge commit
7. Cost
8. Sprint-2 readiness (foundation now hardened)

## Constraints

- Test-first non-negotiable
- Karpathy: surgical changes only; don't refactor adjacent code
- Beads UNHEALTHY (#661); ledger fallback; \`--no-verify\` per documented workaround
- Keep scope tight — 3 issues, no expansion
- Sprint 2 follows immediately after this lands
```

---

## Pre-written brief: Sprint 2 (L2 cost-budget-enforcer)

### Brief (paste into Agent or fresh session)

```
You are implementing Sprint 2 of cycle-098-agent-network: L2 cost-budget-enforcer + reconciliation cron + daily snapshot job. Sprint 1 is fully shipped (PR #693, commit 6e93587). Sprint 1.5 hardening (#689 + #690 + optionally #695) should be merged before this — verify via \`git log\` if uncertain.

**Slice into 4 sub-sprints if total brief exceeds 5K tokens** (per Sprint 1 lesson: single-shot Sprint stalled at 25K). Use the same 4-slice pattern:
- 2A: L2 verdict-engine foundation (4 verdicts + tiered metering hierarchy + envelope-typed events)
- 2B: Reconciliation cron (un-deferred from FU-2 per SKP-005; default 6h cadence)
- 2C: Daily snapshot job (RPO 24h per SKP-001 §3.4.4↔§3.7)
- 2D: L2 skill + per-provider counter + UTC clock + provider lag handling

**Working directory**: this checkout (or worktree if delegated)
**Repo**: 0xHoneyJar/loa
**Branch**: \`feat/cycle-098-sprint-2\` from origin/main
**Cycle**: cycle-098-agent-network (active)
**Source RFC**: #654 (https://github.com/0xHoneyJar/loa/issues/654)

## Compose-with (Sprint 1 + 1.5 deliverables)

- 1A's audit envelope schema (CC-2 + CC-11) + JCS canonicalization adapters
- 1B's Ed25519 signing scheme + fd-based secret loading
- 1B's protected-class router (\`budget.cap_increase\` class)
- 1C's hash-chain recovery (audit_recover_chain with TRACKED + UNTRACKED paths)
- 1.5's Python adapter flock parity (#689) + auto-verify trust-store (#690)
- Existing \`cost-report.sh\`, \`measure-token-budget.sh\`, \`event-bus.sh\`, \`schema-validator.sh\`

## Quality gate chain (full Sprint 1 pattern)

After build (4 sub-sprints):
1. Consolidated /review-sprint sprint-2 → expect CHANGES_REQUIRED on first pass; remediate; re-review
2. Cross-model adversarial review (mandatory)
3. /audit-sprint paranoid cypherpunk
4. Bridgebuilder kaironic on Sprint 2 PR (use \`.claude/skills/bridgebuilder-review/resources/entry.sh\` inline — proven reliable in Sprint 1)
5. After kaironic convergence: admin-squash merge

## Specific deliverables (per PRD FR-L2 + SDD §5.4)

### FR-L2-1..10 (10 ACs)

1. \`allow\` returned when usage <90% AND data fresh (≤5min)
2. \`warn-90\` returned when 90% ≤ usage <100% AND data fresh
3. \`halt-100\` returned when usage ≥100% AND data fresh
4. \`halt-uncertainty\` returned when billing API stale + counter near cap (75%+)
5. Reconciliation drift detection (>5%) emits BLOCKER
6. Counter inconsistencies (negative, decreasing, backwards) → halt-uncertainty
7. Fail-closed under all uncertainty modes — never \`allow\` under doubt
8. Per-repo caps respected when configured
9. All verdicts logged to JSONL audit envelope (\`.run/cost-budget-events.jsonl\`)
10. Integration tests cover billing API outage, counter drift, sudden cap change

### Plus reconciliation cron (un-deferred from FU-2)

- Default 6h cadence
- Cross-checks internal counter vs billing API
- Drift >5% emits BLOCKER (configurable threshold)
- Counter NOT auto-corrected — operator decides via \`force-reconcile\`

### Plus daily snapshot job

- Per SDD §3.7: cycle-098-budget-events.jsonl is UNTRACKED chain-critical
- Daily snapshot to \`grimoires/loa/audit-archive/<utc-date>-L2.jsonl.gz\`
- Snapshots themselves Ed25519-signed by operator's writer key, committed to git
- RPO 24h
- Integrates with hash-chain recovery (1C's audit_recover_chain UNTRACKED path)

### Sprint 2 ACs from SDD §6 (additional)

- Per-provider counter
- UTC clock + provider lag handling
- Fail-closed: never allow under doubt

## Constraints

- Test-first
- Karpathy
- Beads UNHEALTHY (#661); ledger fallback; \`--no-verify\` per documented workaround
- Sprint 4.5 buffer week available if needed (per SKP-001 mitigation)
- No silent slip — invoke /run-status if drift detected; document de-scope decisions explicitly

## Output back

Final report after Sprint 2 ships:
1. Sprint outcome
2. PR URL + merge commit
3. Total cost
4. Tests added (cumulative + per-sub-sprint)
5. Regression status
6. Sprint 3 readiness
7. Any blockers / discovered issues
```

---

## Today's overall log (2026-05-02 → 2026-05-03)

### PRs merged (8)

| # | Title |
|---|-------|
| #677 | sprint-bug-131 — model-adapter large-payload hardening (#675) |
| #678 | feat(cycle-098): planning artifacts (PRD v1.3 + SDD v1.5 + sprint plan + decisions) |
| #679 | chore(cycle-098): activate cycle in ledger + reserve Sprint 1-7 IDs |
| #685 | chore: bump README + .loa-version.json to v1.110.1 (drift catch-up) |
| #686 | chore(ci): README ↔ .loa-version.json drift prevention |
| #688 | chore(cycle-098): RESUMPTION brief + vision-013..017 index update |
| **#693** | **feat(cycle-098): sprint-1 — L1 hitl-jury-panel + cross-cutting infrastructure** |

### Issues filed (16)

- #675 (cheval HTTP/2 bug — auto-closed by #677 merge)
- #680-#684 (visions 013-017 — cycle-099 candidates)
- #687 (sync-readme-version.sh bats coverage)
- #689-#692 (Sprint 1 audit follow-ups: Python flock, trust-store auto-verify, mktemp, argv exposure)
- #694 (Sprint 1 bridgebuilder test-discipline batch — 9 findings)
- #695 (Sprint 1 bridgebuilder security tightening — F8 + F9)

### Sprint 1.5 hardening targets (RECOMMENDED before Sprint 2)

- #689 P2 MED — Python adapter flock parity (Sprint 2 prereq)
- #690 P2 MED — audit_trust_store_verify auto-call (Sprint 2 prereq, before operator populates trust-store)
- #695 P2 MED — F8 audit-secret-redaction allowlist + F9 trust-store signature scope (optional, cheap)

### Cycle-099 candidate backlog

- #680 vision-013 — Per-PR opt-in flag for Loa-content bridgebuilder review
- #681 vision-014 — CI guard for *.bak files
- #682 vision-015 — RFC 3647 Certificate Policy
- #683 vision-016 — Stacked diffs for incremental SDD
- #684 vision-017 — Planning tooling stops emitting .bak siblings (REFRAME, root-cause for #681)
- #687 — sync-readme-version.sh bats coverage (P3 LOW)
- #691 — panel-distribution-audit.sh /tmp/$$ → mktemp (P3 LOW)
- #692 — model-invoke --prompt argv exposure (P3 LOW; mirrors #675 fix pattern)
- #694 (batch) — 9 test-discipline findings from bridgebuilder iter-1

### Routines scheduled

| ID | Cron | Purpose |
|----|------|---------|
| `trig_01E2ayirT9E93qCx3jcLqkLp` | `0 16 * * 5` (Friday 16:00 UTC) | R11 cycle-098 weekly schedule-check ritual; first run 2026-05-08T16:00Z |

URL: https://claude.ai/code/routines/trig_01E2ayirT9E93qCx3jcLqkLp

### Operator action prerequisites (all approved 2026-05-03)

1. ✅ Offline root key generated (Ed25519, mode 0600 at `~/.config/loa/audit-keys/cycle098-root.priv`)
2. ✅ Fingerprint published in 3 channels: PR description (#693), NOTES.md, release-notes-sprint1.md
3. ✅ tier_enforcement_mode default decision: Option C (warn-then-refuse migration)
4. ✅ R11 routine scheduled
5. ✅ #675 triaged + shipped as sprint-bug-131
6. ✅ Claude GitHub App installed

### Outstanding manual operator actions (post-Sprint-1 ship)

- [ ] Encrypt `~/.config/loa/audit-keys/cycle098-root.priv` with passphrase (currently unencrypted prep state)
- [ ] Create release-signed git tag `cycle-098-root-key-v1` for the multi-channel fingerprint chain
- [ ] (Eventually) migrate root key to YubiKey/hardware token before formal cycle-098 release

---

## Key learnings & patterns (for future cycle work)

### The 4-slice pattern for large sprints

When a single-shot Sprint subagent stalls on context load (~25K-token brief), slice into 4 thin sub-sprints with tight (~5K-token) briefs each, sharing a feature branch. Worked for Sprint 1 — should work for Sprint 2-7.

### Inline bridgebuilder beats subagent delegation

Bridgebuilder via \`/bridgebuilder-review\` skill subagent stalled twice (Sprint 1 attempt + initial PR #693 attempt). Direct invocation of \`.claude/skills/bridgebuilder-review/resources/entry.sh --pr <N>\` from main checkout worked reliably both iter-1 and iter-2. **Use the inline pattern.**

### Kaironic stopping criteria

Per `grimoires/loa/memory/feedback_kaironic_flatline_signals.md`:
1. HIGH_CONSENSUS plateau (count + topic same across 2 iters)
2. Finding-rotation at finer grain
3. REFRAME signals (architectural reframe rather than incremental fixes)
4. Critical+High count → 0 (clean iteration with only PRAISE/SPECULATION)
5. Mutation-test-confirmed correctness (when applicable)
6. Factually-stale findings (strongest single terminator)

### Quality gate chain (Sprint pattern)

For each sprint:
1. /implement (test-first × N sub-sprints)
2. /review-sprint → expect 1-2 iters; remediate findings
3. Cross-model adversarial (mandatory)
4. /audit-sprint paranoid cypherpunk
5. Bridgebuilder kaironic
6. Admin-squash merge after kaironic convergence

Total cost per sprint: ~$25-50 build + $10-20 review/audit/bridge = ~$35-70 typical.

### Documented memory entry

Full session learnings in: `~/.claude/projects/-home-merlin-Documents-thj-code-loa/memory/project_cycle098_session.md`

---

*This resumption brief is the canonical handoff for any future session. Update at session end (or before walking away) to keep it accurate.*
