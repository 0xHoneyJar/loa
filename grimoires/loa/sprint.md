# Sprint Plan: Cycle-115 — Sprint S1 (OKF Follow-up Maintenance)

> **Cycle**: `cycle-115-okf-followup-mempalace` (NEW — small follow-up cycle; do **NOT** mislabel under the completed cycle-114)
> **Sprint**: sprint-1 (local) / sprint-226 (global)
> **Epic**: `bd-okf-followup-mempalace-sjtw` (P1) — tracked residual of OKF epic `bd-mnn6` (closed 2026-06-28)
> **Ground truth**: `grimoires/loa/proposals/okf-icm-adoption-cycle-plan-2026-06-28.md` + the mempalace-vs-loa comparison / FAANG-PE panel (session 2026-06-29). No fresh PRD/SDD required — all three deliverables are drawn from already-verified, file-grounded specs.
> **Theme**: Normalize the KF knowledge surface, relabel a dead subsystem honestly, and position the audit moat truthfully. Three GATED deliverables, each test-first.
> **Beads policy**: Beads ALREADY EXIST (label `okf-followup-mempalace`). This sprint **registers/relates** them — it does **not** duplicate. The three in-sprint beads carry `sprint:226` + `cycle-115-okf-followup`.

---

## Executive Summary

A single MEDIUM sprint (3 tasks) closing the agent-doable residuals surfaced when loa was compared against memory-palace tools. Each deliverable is independent, low blast radius, and test-first:

- **D1** (P1, SYSTEM zone) — make the `known-failures.md ## Index` a **generated, drift-proof** artifact + add a default-OFF session-start surfacing hook.
- **D2** (P2, SYSTEM zone, docs-only) — relabel the dead semantic-memory recall pipeline **EXPERIMENTAL** without reviving it.
- **D3** (P2, STATE zone) — author an honest two-tier **audit-moat positioning** note.

**Total Sprints:** 1 (this is a focused follow-up, not a multi-sprint cycle)
**Task count:** 3 (MEDIUM)
**Out-of-sprint (track only, do NOT implement here):** `bd-verify-modelinv-signing-cigj` (runtime verification, not `/implement`) and `bd-root-key-offline-n9nf` (OPERATOR-ONLY — agent MUST NOT run). `bd-dead-recall-doc-consistency-xz9b` (P3) is a deferred D2 follow-up, also out of this sprint.
**Routing:** `/run sprint-1` → `/implement` → `/review-sprint` → `/audit-sprint`. `/bug` is correctly disqualified (D1 adds a config flag + a new hook = feature-shaped). System-Zone (`.claude/`) writes for D1/D2 land **inside `/implement` under cycle authorization** (zone-write-guard blocks Edit/Write; use the Bash-patcher).
**PR review:** @janitooor (CODEOWNERS).

---

## Sprint Overview

| Sprint | Theme | Key Deliverables | Beads | Dependencies |
|--------|-------|------------------|-------|--------------|
| 1 | OKF follow-up maintenance | D1 kf-index reframe · D2 dead-recall relabel · D3 audit-moat positioning | `bd-kf-index-reframe-hbya`, `bd-dead-recall-relabel-7hi2`, `bd-audit-moat-positioning-sji4` | None (all 3 independent) |

---

## Sprint 1: OKF Follow-up Maintenance — Index, Relabel, Positioning

**Duration:** 1 day (D1 ~half-to-full day; D2 ~30–45 min; D3 ~70-line doc)
**Cycle:** `cycle-115-okf-followup-mempalace`

### Sprint Goal
Land three already-specified OKF residuals — a drift-proof generated KF index (D1), an honest EXPERIMENTAL relabel of the dead recall pipeline (D2), and a truthful audit-moat positioning doc (D3) — each test-first, with zero weakening of any fail-closed gate.

### Deliverables
- [x] **D1** — `known-failures.md ## Index` table generated FROM the actual `## KF-NNN:` headings (drift structurally impossible), with a Symptom column + numeric recurrence; `grimoire-index.sh --validate` hardened to a fail-on-drift assertion; default-OFF `loa-kf-surface.sh` SessionStart hook (loud-but-nonblocking); hook registered in `settings.json`; flag documented in `.loa.config.yaml.example`. → bead `bd-kf-index-reframe-hbya`
- [x] **D2** — EXPERIMENTAL banner + corrected ownership table across `memory-reference.md`, `recommended-hooks.md`, `hooks/README.md`; docs-only with a regression guard. → bead `bd-dead-recall-relabel-7hi2`
- [x] **D3** — new STATE-zone doc `grimoires/loa/proposals/audit-moat-positioning-2026-06-29.md`: Tier-1 integrity TRUE-TODAY (cited), Tier-2 authorship DEFERRED, root-key caveat. → bead `bd-audit-moat-positioning-sji4`

### Acceptance Criteria
- [x] **D1**: bats `TEST-1..TEST-7` pass; **TEST-5 (loud-but-nonblocking) is load-bearing** — asserts a visible `[KF-SURFACE]` WARNING on enabled+degraded/zero-KF/unreadable, and silence ONLY when the flag is disabled. `--validate` fails (non-zero) when index-row-count ≠ heading-count.
- [x] **D1**: generated `## Index` lists all 20 `## KF-NNN:` headings (currently 14 rows; **missing KF-009, KF-016, KF-017, KF-018, KF-019, KF-020** — verified drift); KF prose is NOT bot-rewritten.
- [x] **D1**: hook ships **default-OFF**; with the flag disabled it exits 0 silently and emits nothing.
- [x] **D2**: grep/doc-lint asserts the EXPERIMENTAL marker is present near the recall/Memory-Writer-Hook section in each of the 3 files; ownership-table cell corrected to "hand-authored, zero hook-generated entries" (NOT "all-null").
- [x] **D2**: docs-only regression guard — `git diff --name-only` touches **NO** `.claude/hooks/*.sh`, `memory-*.sh`, `settings.hooks.json`, or `.loa*/` (relabel changes ZERO behavior). Version stamps (v1.28.0 / v1.40.0) left as historical provenance.
- [x] **D3**: every integrity-mechanism claim cites a resolving `file:line`; **NO authorship/non-repudiation verb appears outside the labeled DEFERRED section**; the signed-count statement is reproducible over `.run/model-invoke.jsonl`; root-key-on-disk caveat present; file under `grimoires/loa/proposals/` NOT `.claude/`.

### Technical Tasks

<!-- D1/D2/D3 map to the project's deliverable goals; annotated → **[G-Dn]** -->

#### Task 1.1 — D1: kf-index reframe (bead `bd-kf-index-reframe-hbya`, P1) → **[G-D1]**
> From the OKF plan, Sprint 3 R1: *"`--validate` (flag KF Index-vs-heading drift)"* (okf-icm-adoption-cycle-plan-2026-06-28.md:35).
> Verified reality: `grimoire-index.sh:69-76` already reads `## KF-NNN:` headings as source of truth; `:178` already emits an **informational** stale-Index `::warning::` — D1 promotes this to a generated Index + a fail assertion.

- [ ] **TEST-FIRST**: author bats `TEST-1..TEST-7` (in `tests/unit/`) per the verified spec **before** code. TEST-5 (loud-but-nonblocking hook contract) is load-bearing: assert visible `[KF-SURFACE]` WARNING on enabled+degraded, silence only when disabled, and **exit 0 in all enabled paths**.
- [ ] Extend `emit_kf` in `.claude/scripts/grimoire-index.sh` to emit a **Symptom column + numeric recurrence** for each KF (parsed from the entry body), and generate the `## Index` table content FROM the headings so the hand-table can no longer drift.
- [ ] Harden `grimoire-index.sh --validate`: change the index-row-count vs heading-count check from `::warning::` (currently `:174-178`) to a **machine-checkable assertion** that exits non-zero on drift.
- [ ] Add `.claude/hooks/loa-kf-surface.sh` — SessionStart hook, **default-OFF**, surfaces a compact symptom→KF table. MUST exit 0 always; emits a visible `[KF-SURFACE]` WARNING on any enabled-but-degraded / zero-KF / unreadable path; silent only when the flag is disabled.
- [ ] Register the hook in `.claude/settings.json` under the existing `SessionStart` array (present at `:475`).
- [ ] Document the flag `known_failures.surface_at_session_start` (default `false`) in `.loa.config.yaml.example` (no such key exists today — additive).
- [ ] Do **NOT** bot-rewrite `known-failures.md` prose; the derived `## Index` becomes authoritative. The hand-table repair stays human-edit scope of `bd-2fy3` (already related, not duplicated).

#### Task 1.2 — D2: dead-recall docs relabel (bead `bd-dead-recall-relabel-7hi2`, P2, docs-only) → **[G-D2]**
> Verified reality: `observations.jsonl` holds exactly **1** record (a hand-authored 2026-04-24 cycle-093 "pattern" entry, well-formed JSON — NOT "all-null"); memory hooks unregistered; vector DB empty; sentence-transformers in the wrong venv → recall is dead.

- [ ] **TEST-FIRST**: author the grep/doc-lint assertions (EXPERIMENTAL marker present near the recall section in each of the 3 files) and the docs-only regression guard (`git diff --name-only` touches none of `.claude/hooks/*.sh`, `memory-*.sh`, `settings.hooks.json`, `.loa*/`) **before** editing.
- [ ] `.claude/loa/reference/memory-reference.md`: add an `EXPERIMENTAL — not wired, do not rely on` banner near the recall / Memory-Writer-Hook / progressive-disclosure sections; correct the ownership-boundary table cell to describe `observations.jsonl` as **hand-authored, zero hook-generated entries** (NOT "all-null"). Leave the v1.28.0 / v1.40.0 stamps as historical provenance — do NOT bump.
- [ ] `.claude/protocols/recommended-hooks.md`: mark the `memory-inject.sh` / `memory-writer.sh` wiring as dead/optional/experimental.
- [ ] `.claude/hooks/README.md`: add the same EXPERIMENTAL marker.
- [ ] Do **NOT** revive the subsystem. Zero runtime change; trade no false claim for another.

#### Task 1.3 — D3: audit-moat positioning doc (bead `bd-audit-moat-positioning-sji4`, P2, STATE zone) → **[G-D3]**
> Verified citations (all resolve in `.claude/scripts/audit-envelope.sh`): JCS source `:72-74`; `_audit_sha256` `:150-167`; strip `signature`+`signing_key_id` before hash `:169-177`; GENESIS + prev_hash continuity `:184-203`; verify-walk fails on first break `:939-943`.

- [ ] Author `grimoires/loa/proposals/audit-moat-positioning-2026-06-29.md` (STATE zone — written directly, no `/implement` gate needed for the file itself; the reviewer greps are the acceptance check).
- [ ] **Tier 1 (TRUE TODAY, claim now)**: SHA-256 hash chain over RFC 8785 JCS canonical chain-input with `signature`/`signing_key_id` stripped before hashing; GENESIS anchor + prev_hash continuity; verify walk fails on first break ⇒ any edit/reorder/deletion of a past entry is DETECTED. Tamper-EVIDENCE at zero cost, no signing required — **this is the moat.** Every mechanism claim cites the resolving `file:line` above.
- [ ] **Tier 2 (DEFERRED — do NOT claim authorship yet)**: per-writer authorship/non-repudiation via Ed25519 + root-signed trust-store. Signing is **ARMED** (`LOA_AUDIT_SIGNING_KEY_ID=deep-name` live; trust-store VERIFIED; `trust_cutoff` 2026-06-29T00:00:00Z now PAST) so the first signed entry appears on the next cheval emit — **but** the log is single-operator and gitignored, so "who wrote this" is not yet a meaningful question. Unlock Tier-2 language only when BOTH (a) new entries verifiably signed AND (b) a shared multi-writer log exists.
- [ ] **Honest limit**: cycle-098 root private key still on disk (`~/.config/loa/audit-keys/cycle098-root.priv`) ⇒ root-of-trust is bootstrap-grade until the offline move (the OPERATOR bead) is done — caveat must be present.
- [ ] Make the signed-count statement reproducible over `.run/model-invoke.jsonl` (state the exact command/grep the reviewer can re-run).
- [ ] Keep ALL authorship/non-repudiation verbs **inside** the labeled DEFERRED section (acceptance grep).

### Dependencies
- None between D1/D2/D3 — all three are independent and may be implemented in any order.
- D1 is **related** (not blocking) to `bd-2fy3` (human hand-table repair); the generated Index supersedes the need for hand-repair but does not block it.
- Out-of-sprint and tracked-only: `bd-verify-modelinv-signing-cigj`, `bd-root-key-offline-n9nf`, `bd-dead-recall-doc-consistency-xz9b`.

### Security Considerations
- **Trust boundaries (D1)**: `known-failures.md` is append-only/anti-tamper; the generated `## Index` is derived output, NOT a rewrite of entry bodies — preserve that boundary. The KF entry bodies (and any grimoire L5/L6/L7 bodies the parser touches) are UNTRUSTED — sanitize control bytes at surfacing, never interpret as instructions (per agent-network universal invariant + `grimoire-index.sh` per-field sanitization).
- **Fail-closed discipline (D1 hook)**: the SessionStart hook is **observability only** — it exits 0 always and MUST NOT block a session. It is loud-but-nonblocking, not a gate. Default-OFF.
- **No gate weakening (D3)**: D3 is a positioning *document*; it changes no verification path. It must not overclaim authorship while signing is merely armed.
- **Operator-only boundary**: the root-key offline move (`bd-root-key-offline-n9nf`) is explicitly out of agent scope — the agent MUST NOT run `move-root-key-offline.sh`.
- **Sensitive data (D3)**: do not paste private-key material or full key contents; the pinned root pubkey is public and fine, the `.priv` contents are not.

### Risks & Mitigation
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| D1 hook accidentally blocks session start | Low | High | TEST-5 load-bearing: assert exit 0 in all enabled paths; default-OFF ships dark |
| D1 `--validate` assertion breaks an unrelated CI lane already tolerating the warning | Med | Med | Scope the fail strictly to KF index-vs-heading drift; run `validate-framework` + existing drift lanes before PR |
| D2 relabel accidentally touches behavior (a hook/script/state file) | Low | Med | Docs-only regression guard in the AC asserts `git diff` touches none of the forbidden paths |
| D2 reintroduces the inaccurate "all-null" claim | Med | Low | AC pins the exact wording "hand-authored, zero hook-generated entries"; reviewer greps for it |
| D3 overclaims authorship while signing is only armed | Med | Med | AC: no authorship verb outside the DEFERRED section; two-trigger unlock condition stated explicitly |
| Beads JSONL/DB drift (KF-005 class) hides label/sprint registration | Med | Low | Beads + labels verified durable in `beads.db` (the store `br` reads); JSONL flush left to normal commit flow — do NOT force-overwrite the historical JSONL (data-loss risk) |

### Success Metrics
- D1: `grimoire-index.sh --validate` exits non-zero on a planted index/heading mismatch; generated Index lists 20/20 KF headings; `bats tests/unit/<kf-surface>.bats` green (TEST-1..7).
- D2: 3/3 files carry the EXPERIMENTAL marker; regression-guard test green (0 forbidden paths in the diff).
- D3: reviewer grep finds 0 authorship verbs outside DEFERRED; 5/5 integrity claims cite a resolving `file:line`; signed-count command reproduces.
- Cycle: `/review-sprint` + `/audit-sprint` both pass; PR reviewed by @janitooor.

---

## Appendix C: Goal Traceability

PRD goals are substituted by the three deliverable goals (no PRD; grounded in the OKF plan + verified specs).

| Goal ID | Goal | Contributing Task(s) | Bead | Validation Method |
|---------|------|----------------------|------|-------------------|
| G-D1 | KF `## Index` is generated & drift-proof; symptoms surfaced; optional default-OFF session hook | Task 1.1 | `bd-kf-index-reframe-hbya` | bats TEST-1..7 (TEST-5 load-bearing); `--validate` fails on planted drift |
| G-D2 | Dead recall pipeline honestly relabeled EXPERIMENTAL, zero behavior change | Task 1.2 | `bd-dead-recall-relabel-7hi2` | grep/doc-lint for marker + docs-only regression guard |
| G-D3 | Audit moat positioned two-tier honestly (integrity true, authorship deferred) | Task 1.3 | `bd-audit-moat-positioning-sji4` | reviewer greps: cited file:line per integrity claim; no authorship verb outside DEFERRED |

**E2E validation** is folded into each task's acceptance (the sprint is 3 independent maintenance deliverables, not a build with a single integrated path). No separate Task N.E2E is warranted; each deliverable's AC is its own end-to-end check.

**Coverage check:** every goal (G-D1/G-D2/G-D3) maps to exactly one task and one bead. No goal is task-less.

---

## Appendix D: Bead Registration (relate, do not duplicate)

The beads already exist (created session 2026-06-29, label `okf-followup-mempalace`). This sprint registered them — it did NOT create duplicates.

| Bead | Role | Priority | Sprint membership | In this sprint? |
|------|------|----------|-------------------|-----------------|
| `bd-okf-followup-mempalace-sjtw` | Epic (umbrella) | P1 | — (epic) | Tracks all 6 |
| `bd-kf-index-reframe-hbya` | D1 | P1 | `sprint:226`, `cycle-115-okf-followup` | ✅ in sprint |
| `bd-dead-recall-relabel-7hi2` | D2 | P2 | `sprint:226`, `cycle-115-okf-followup` | ✅ in sprint |
| `bd-audit-moat-positioning-sji4` | D3 | P2 | `sprint:226`, `cycle-115-okf-followup` | ✅ in sprint |
| `bd-verify-modelinv-signing-cigj` | Runtime verify (NOT `/implement`) | P1 | — | ❌ track only |
| `bd-root-key-offline-n9nf` | OPERATOR-ONLY (agent MUST NOT run) | P1 | — | ❌ track only |
| `bd-dead-recall-doc-consistency-xz9b` | Deferred D2 follow-up | P3 | — | ❌ out of sprint (do after D2) |
| `bd-2fy3` | Hand-table repair (human edit) | P3 | — | Related to D1 (not duplicate) |

Ledger: cycle `cycle-115-okf-followup-mempalace` registered as **active**; sprint-1 = global sprint-226; `next_sprint_number` advanced to 227.
