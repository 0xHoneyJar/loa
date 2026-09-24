# Sprint Plan: Loa Friction Floor (cycle-125)

**Version:** 1.0
**Date:** 2026-09-23
**Author:** Sprint Planner Agent (unattended run)
**PRD:** `grimoires/loa/prd.md` · **SDD:** `grimoires/loa/sdd.md`
**Branch:** `feature/cycle-125-friction-floor` → draft PR to `main` (prepared as `2.0.0-rc.2`)

---

## Executive Summary

Four sprints remove the five friction sources the usage mining ranked highest: fence false positives (FR-1), oversized planning artefacts (FR-2), unattended runs that stall (FR-3), invisible provider health (FR-4) and blind cost accounting (FR-5). Every sprint is test-first, keeps the prompt byte budgets green, regenerates REPO-MAP and checksums after `.claude/` changes, and closes through `/review-sprint` and `/audit-sprint` with cross-model dissent. The a2a record goes to `record/cycle-125-a2a`.

> From prd.md §Goals: G-1 fence precision without losing a genuine catch; G-2 artefacts readable by section within tool limits; G-3 runs fail loud before the first task or resume at the last task; G-4 provider health visible and self-healing; G-5 the ids the fleet actually calls are priced.

---

## Sprint Overview

| Sprint | Theme | Key Deliverables | Dependencies |
|--------|-------|------------------|--------------|
| 1 | Fence precision | `block-destructive-bash.sh` D-1.1…D-1.5, `git-branch-prune.sh`, fence corpus + data-driven bats | None |
| 2 | Sectioned artefacts | `notes-guard.sh --section/--index`, skill routing within budgets, `/loa` artefact sizes, `update-loa.sh` NOTES rotation, migration addendum | None (parallel-safe with 1) |
| 3 | Run preflight and resume | `run-preflight.sh`, run-mode pre-flight collapse, `checkpoint` field, resume surfacing in `workflow-state.sh`/`loa-status.sh`/SessionStart, re-entry proof | Sprint 2 (`notes-guard.sh check` reuse) |
| 4 | Provider health, cost, docs, E2E | breaker `--list`/`--reset-breaker`, status block, chain-walk test, KF template + seeding, pricing ladder, resolved-id rows, `cost-report.sh` legacy/unpriced, CHANGELOG, E2E validation | Sprints 1–3 |

---

## Sprint 1: Fence precision

**Duration:** 2.5 days
**Dates:** 2026-09-23 – 2026-09-25

### Sprint Goal
Stop the four false-positive classes in `block-destructive-bash.sh` without losing a single genuine catch, proven by a committed corpus.

> From prd.md FR-1: "Reclassify the four false-positive classes without weakening any genuine catch." · From sdd.md §1.2 D-1.1–D-1.6.

### Deliverables
- [x] `tests/fixtures/fence-corpus/corpus.jsonl` (≥ 40 benign, ≥ 15 dangerous, scrubbed) and the data-driven case in `tests/unit/block-destructive-bash.bats` with the ≥ 80 % / 100 % gates
- [x] `rm -rf` allowances (cache vocabulary by last segment, scratch working directory, temp roots with the real `$TMPDIR`, single-assignment mktemp variables) with the catastrophic and exclude lists untouched; no bare project-directory allowance; no remote-payload scrub
- [x] Sink-aware precondition for the DROP / TRUNCATE / DELETE rules
- [x] Offline ancestor check for `git branch -D` in the hook and the sanctioned `.claude/scripts/git-branch-prune.sh` (merged-PR probe with timeout, `LOA_FENCE_NO_NETWORK` opt-out) for squash-merged branches
- [x] Corpus lint (no hostnames, URLs, IPs, credentials, key shapes, bucket names) alongside the data-driven case
- [x] Generated-path allowance for `git checkout -- <path>` / `git restore <path>`
- [x] REPO-MAP and `.claude/checksums.json` regenerated; hook header documents the residuals

### Acceptance Criteria
- [x] Corpus run: benign pass rate ≥ 80 %, dangerous block rate 100 %; the existing 216 fence cases stay green (prd.md FR-1 AC 1–2)
- [x] Every relaxation has its dangerous twin in the corpus (prd.md FR-1 AC 3)
- [x] Hook runtime over the corpus within 1.5× of the pre-change measurement (prd.md FR-1 AC 4)
- [x] `git-branch-prune.sh` bats: merged, squash-merged (stub `gh`), unmerged, gone-upstream cases
- [x] No hook file outside `block-destructive-bash.sh` changed; `hook-wiring.bats` green

### Technical Tasks

<!-- → **[G-N]** contributing goal(s); ⇐ blockers become --deps -->

- [x] Task 1.1: Build the fence corpus from the attributed samples (`.run/usage-mining/mine-attrib.json` → neutral paths; dangerous twins per SDD D-1.6) with the corpus lint and the data-driven bats case (cwd and `TMPDIR` per row); run it red against the current hook and record the baseline pass rate and runtime → **[G-1]** ⇐ none
- [x] Task 1.2: D-1.1 `rm -rf` allowances: cache vocabulary by last segment, scratch cwd, temp roots with the real `$TMPDIR`, single-assignment mktemp variables (`block-destructive-bash.sh:1070–1087`, `:1221–1240`); named bats per class plus twins (`rm -rf src` and `./.git/` stay blocked) → **[G-1]** ⇐ Task 1.1
- [x] Task 1.3: Hook header: document the withdrawn remote-payload scrub and the SQL driver residual; confirm `ssh host 'rm -rf /'` and `python -c` SQL rows behave as today in the corpus → **[G-1]** ⇐ Task 1.1
- [x] Task 1.4: D-1.3 sink-aware SQL precondition for P8/P9/P10 (`:690–760`); bats: heredoc-to-file passes, `psql -c` / heredoc-into-psql / `mysql -e` block → **[G-1]** ⇐ Task 1.1
- [x] Task 1.5: D-1.4 offline ancestor check in the hook (no network) and `git-branch-prune.sh [--dry-run] [--base]` with the merged-PR probe (`timeout 5 gh`, `LOA_FENCE_NO_NETWORK`); bats with a fixture repo and a stub `gh`; hook recognises the helper's invocation shape → **[G-1]** ⇐ Task 1.1
- [x] Task 1.6: D-1.5 generated-path allowance for checkout/restore (`:660–668`) via `git check-attr linguist-generated` and the path classes; bats → **[G-1]** ⇐ Task 1.1
- [x] Task 1.7: Corpus gates green, runtime measured, hook header residuals documented, `repo-map-gen.sh` + checksum regen, `lint-invariants.sh`, CHANGELOG `[Unreleased]` line, `reviewer.md` with AC Verification → **[G-1]** ⇐ Task 1.2, Task 1.3, Task 1.4, Task 1.5, Task 1.6

### Dependencies
- None (first sprint). Uses the untracked `.run/usage-mining/mine-attrib.json` as the corpus seed.

### Security Considerations
- **Trust boundaries**: the hook reads the raw command text an agent produced; every relaxation applies only on a positively established predicate, and any evaluation error falls back to the current block (sdd.md §6).
- **External dependencies**: `gh` is optional and bounded by `timeout 5`; `LOA_FENCE_NO_NETWORK=1` disables the network probe. No new packages.
- **Sensitive data**: the corpus is scrubbed of hostnames, users, DB URLs, bucket and key names before commit; `emit_block` keeps redacting via `log-redactor.sh`.

### Risks & Mitigation
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| A bare-name allowance admits a destructive operand | Low | High | catastrophic list first; no `/ ~ . $` leading chars; dangerous twins; audit dissent |
| SQL runner list misses a project tool | Med | Low | conservative list + `-c/--command`; residual documented; corpus row for `-f file.sql` |
| `gh` probe latency | Low | Low | only on `branch -D`; 5 s cap; failure = block |

### Success Metrics
- Benign corpus pass rate ≥ 80 %; dangerous block rate 100 %
- Fence suite 216 + new cases green; runtime ≤ 1.5× baseline

---

## Sprint 2: Sectioned artefacts

**Duration:** 2 days
**Dates:** 2026-09-25 – 2026-09-27

### Sprint Goal
Make `prd.md`, `sdd.md`, `sprint.md` and `NOTES.md` readable by section under a budget, route the skills through it without breaking byte budgets, and rotate an oversized NOTES.md on upgrade.

> From prd.md FR-2: "Generalise `notes-guard.sh read` into one heading-addressed, budgeted artefact reader … `update-loa` rotates NOTES.md when it is at or over the block line." · From sdd.md §1.3.

### Deliverables
- [ ] `notes-guard.sh read --file F --section <Sprint N | N. | substring>` and `--index`; non-NOTES default is `--index`; never empty
- [ ] `context_discipline` skill-include line (≤ 100 B) regenerated into every skill, with compensating trims in `implementing-tasks`, `reviewing-code`, `auditing-security`; `implementing-tasks` reads its sprint block by section
- [ ] `loa-status.sh` "Artefacts" line with the 100 KiB warn
- [ ] `update-loa.sh` post-refresh NOTES rotation (check exit 3 → rotate, logged)
- [ ] `docs/migration/v2.0-model-generation-floor.md` rc.2 addendum (NOTES rotation on upgrade)

### Acceptance Criteria
- [ ] `notes-guard.bats`: exact heading, `Sprint N`, numbered SDD section, substring, no-match → index + one-line reason, budget footer, `--full`, NOTES default unchanged (prd.md FR-2 AC 1)
- [ ] This repository's `prd.md` and `sdd.md` read by section stay ≤ 100 KiB per call (byte proxy for 25k tokens) (prd.md FR-2 AC 2)
- [ ] `tools/check-prompt-budget.sh` ok; `prompt-audit-keeplist.bats` green; the four skills remain ≤ 16,384 B (prd.md FR-2 AC 3)
- [ ] `update-loa` rotation bats with a generated ≥ 200 KiB fixture; migration addendum present (prd.md FR-2 AC 4)

### Technical Tasks

- [ ] Task 2.1: Failing bats for `--section`/`--index`/no-match/non-NOTES default in `tests/unit/notes-guard.bats` → **[G-2]** ⇐ none
- [ ] Task 2.2: Implement `--section` and `--index` in `notes-guard.sh` (`index_blocks` reuse, `select_ranges` by spec, `emit_ranges` budget); usage text → **[G-2]** ⇐ Task 2.1
- [ ] Task 2.3: Skill routing within budgets: include line in `.claude/data/skill-includes/context_discipline.md`, regenerate includes, compensating trims, `implementing-tasks` sprint-block read; keeplist and budget checks green → **[G-2]** ⇐ Task 2.2
- [ ] Task 2.4: `loa-status.sh` Artefacts line (`notes-guard.sh check --file` ×4) + bats snapshot → **[G-2]** ⇐ Task 2.2
- [ ] Task 2.5: `update-loa.sh` rotation step + bats with generated fixture (`tests/fixtures/notes/make-large-notes.sh`); migration addendum → **[G-2]** ⇐ Task 2.2
- [ ] Task 2.6: REPO-MAP + checksum regen, CHANGELOG line, `reviewer.md` AC Verification → **[G-2]** ⇐ Task 2.3, Task 2.4, Task 2.5

### Dependencies
- Independent of Sprint 1 (different files); runs after it in the plan order.

### Security Considerations
- **Trust boundaries**: the reader only reads files under the grimoire; `--file` is validated as a regular file (no symlink following in `rotate`, unchanged).
- **External dependencies**: none.
- **Sensitive data**: none; rotation archives under `grimoires/loa/archive/notes/` (gitignored path in this repo).

### Risks & Mitigation
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Byte budgets overflow after the include grows | Med | Med | trims in the same commit; budget check gates |
| Section addressing misses a heading grammar | Low | Low | substring fallback + index listing |

### Success Metrics
- Zero Read-cap rejections on the four artefacts in this repository's own next sprints (observed in Sprint 3/4 transcripts)
- Skills ≤ 16,384 B; kernel ≤ 10,240 B

---

## Sprint 3: Run preflight and resume

**Duration:** 2.5 days
**Dates:** 2026-09-27 – 2026-09-29

### Sprint Goal
An unattended run refuses to start unless it can finish, checkpoints after every task, and the next session is told exactly how to resume.

> From prd.md FR-3: "`run-preflight.sh` runs at the entry of `/run`, `/run-sprint-plan` and `run-mode`, and fails loud with a checklist … The run state is checkpointed after every task … a stale `RUNNING` / `INTERRUPTED` state is surfaced with the exact resume command." · From sdd.md §1.4 D-3.1–D-3.3.

### Deliverables
- [ ] `.claude/scripts/run-preflight.sh` with predicates P1–P8, `--unattended`, `--json`, checklist output
- [ ] run-mode SKILL pre-flight collapsed onto the script (net negative bytes); `run-sprint-plan`, `run-bridge` reference it
- [ ] `checkpoint` field in `sprint-plan-state.json` (schema doc + write points in the run-mode resources)
- [ ] `workflow-state.sh` resume suggestion; `loa-status.sh` `Run:` line; `loa-run-state-surface.sh` SessionStart line wired in `settings.json` and `hooks/settings.hooks.json` behind `hook-guard.sh`
- [ ] Re-entry proof: `/implement sprint-N` skips closed beads (fixture), or the fix that makes it so

### Acceptance Criteria
- [ ] `run-preflight.bats`: one passing and one failing fixture per predicate; checklist names predicate and fix; `--json` shape (prd.md FR-3 AC 1)
- [ ] Checkpoint written after each task and phase; resume restarts at the recorded task in the integration fixture (prd.md FR-3 AC 2)
- [ ] `loa-status.sh` prints the resume line for a stale state and nothing for a clean one; `hook-wiring.bats` covers the new SessionStart line (prd.md FR-3 AC 3)
- [ ] No new config key; inputs are settings files, env and existing state (prd.md FR-3 AC 4)

### Technical Tasks

- [ ] Task 3.1: Failing bats for P1–P8 with settings/state/breaker/NOTES fixtures in `tests/unit/run-preflight.bats` → **[G-3]** ⇐ none
- [ ] Task 3.2: Implement `run-preflight.sh` (compose `check-permissions.sh`, `beads-health.sh`, `run-mode-ice.sh validate`, `notes-guard.sh check`, breaker listing, voice/credential/hop checks, state age) with `--unattended`/`--json` → **[G-3]** ⇐ Task 3.1
- [ ] Task 3.3: run-mode SKILL/resources: pre-flight collapse, `checkpoint` schema and write points, `run-resume` reports checkpoint; `run-sprint-plan`/`run-bridge` references; budgets green → **[G-3]** ⇐ Task 3.2
- [ ] Task 3.4: Resume surfacing: `workflow-state.sh get_suggested_command`, `loa-status.sh` `Run:` line, `loa-run-state-surface.sh` + hook wiring in both settings files; bats → **[G-3]** ⇐ Task 3.2
- [ ] Task 3.5: Re-entry proof fixture (closed beads skipped by `/implement`), fix if needed; session-limit reset feeds the surface line → **[G-3]** ⇐ Task 3.4
- [ ] Task 3.6: REPO-MAP + checksum regen, CHANGELOG line, `reviewer.md` AC Verification → **[G-3]** ⇐ Task 3.3, Task 3.5

### Dependencies
- Sprint 2 (`notes-guard.sh check` unchanged interface; `loa-status.sh` section layout).

### Security Considerations
- **Trust boundaries**: the preflight reads settings files and state files; it never prints credential values (presence only) and never modifies settings.
- **External dependencies**: none new; `gh`/`codex`/`claude`/`agy` presence is probed with `command -v` only.
- **Sensitive data**: `.run/session-limit-state.json` and breaker files contain no secrets; the SessionStart line prints state and age only.

### Risks & Mitigation
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Preflight blocks a wanted run | Low | Low | checklist names the fix; interactive mode unchanged |
| Re-entry does not skip closed beads in some path | Med | Med | Task 3.5 proves or fixes before relying on it |
| Hook wiring drift between the two settings files | Low | Med | `hook-wiring.bats` W4 covers both |

### Success Metrics
- Every predicate has fixtures; the loa repo's own Sprint 4 run passes preflight
- Resume line appears on the next session start after a halt

---

## Sprint 4 (Final): Provider health, cost accounting, docs and E2E

**Duration:** 3 days
**Dates:** 2026-09-29 – 2026-10-02

### Sprint Goal
Provider health is one glance in `/loa` and self-heals through the chain; the ids the fleet actually calls are priced; the cycle's documentation lands; every PRD goal is validated end-to-end.

> From prd.md FR-4, FR-5 and §Success Criteria · From sdd.md §1.5, §1.6, §8.

### Deliverables
- [ ] `python3 -m loa_cheval.routing.circuit_breaker --list [--json]`, `cheval --reset-breaker`, expiry surfaced; `loa-status.sh` Providers block; chain-walk-on-OPEN test
- [ ] `.claude/templates/known-failures.md.template`; seeding in `mount-submodule.sh` and `mount-loa.sh`; `check-loa.sh` warning
- [ ] `find_pricing` resolution ladder (exact → dated → alias → hop); headless adapters record the resolved id and `transport`; `cost_estimated` rows; `cost-report.sh --include-legacy` / `--migrate-legacy` with receipt and unpriced share; enforcer field names
- [ ] CHANGELOG `[Unreleased]` entries for FR-1…FR-5; README one-liner; migration addendum (legacy ledger)
- [ ] Task 4.E2E goal validation with evidence

### Acceptance Criteria
- [ ] Breaker bats/pytest: `--list` shape, reset journals, OPEN → HALF_OPEN after cooldown; status snapshot prints state/age/credential presence/hop and never a value (prd.md FR-4 AC 1–2)
- [ ] Chain-walk test: OPEN `anthropic/http_api` fixture → the alias resolves to the CLI hop in a dry-run trace (prd.md FR-4 AC 3)
- [ ] Mount tests assert the seeded `known-failures.md` (prd.md FR-4 AC 4)
- [ ] Pricing pytest over the fleet ids: each resolves; unknown ids stay `unknown` and are counted; per-hop adapter test pins the resolved id (prd.md FR-5 AC 1–2)
- [ ] `cost-report.bats`: totals match a hand computation; legacy include/migrate/receipt; unpriced share printed (prd.md FR-5 AC 3); ledger isolation preserved (prd.md FR-5 AC 4)
- [ ] All PRD goals validated in Task 4.E2E with documented evidence

### Technical Tasks

- [ ] Task 4.1: Failing tests for breaker `--list`/reset/expiry, provider status snapshot, chain walk on OPEN, KF seeding → **[G-4]** ⇐ none
- [ ] Task 4.2: Implement breaker CLI listing + `cheval --reset-breaker`, `loa-status.sh` Providers block (credential presence, hops), KF template + mount seeding + `check-loa.sh` warning → **[G-4]** ⇐ Task 4.1
- [ ] Task 4.3: Failing pytest/bats for the pricing ladder over the fleet ids, adapter resolved-id recording, `cost-report.sh` legacy/unpriced/receipt → **[G-5]** ⇐ none
- [ ] Task 4.4: Implement `find_pricing` ladder + `pricing_resolution`, adapter `resolved_model`/`transport`, `cost_estimated`, `cost-report.sh --include-legacy`/`--migrate-legacy`/unpriced share, enforcer field names → **[G-5]** ⇐ Task 4.3
- [ ] Task 4.5: Docs: CHANGELOG `[Unreleased]` entries for FR-1…FR-5, README line, migration addendum (legacy ledger, NOTES rotation), hook header residuals cross-checked → **[G-1, G-2, G-3, G-4, G-5]** ⇐ Task 4.2, Task 4.4
- [ ] Task 4.6: REPO-MAP + checksum regen, full `tests/unit/` run with ledger hashes before/after, `reviewer.md` AC Verification → **[G-4, G-5]** ⇐ Task 4.5
- [ ] Task 4.E2E: End-to-End Goal Validation (table below) → **[G-1, G-2, G-3, G-4, G-5]** ⇐ Task 4.6

### Task 4.E2E: End-to-End Goal Validation
**Priority:** P0 (Must Complete)
**Goal Contribution:** All goals (G-1, G-2, G-3, G-4, G-5)

**Validation Steps:**
| Goal ID | Goal | Validation Action | Expected Result |
|---------|------|-------------------|-----------------|
| G-1 | Fence precision without losing a catch | run the corpus case; run the full fence suite | ≥ 80 % benign pass, 100 % dangerous block, suite green |
| G-2 | Artefacts readable by section | `notes-guard.sh read --file grimoires/loa/prd.md --section 'Functional Requirements'`; `--index` on sdd.md; budget check | block ≤ 100 KiB; index lists every H2; budgets ok |
| G-3 | Runs fail loud / resume | `run-preflight.sh --unattended --json` on this repo; simulate a HALTED state → `loa-status.sh` | checklist with all predicates; `Run: HALTED … → /run-resume` |
| G-4 | Provider health visible | `loa-status.sh` with fixture buckets; chain-walk dry-run trace | per-provider lines; walk to CLI hop on OPEN |
| G-5 | Fleet ids priced | pytest ladder fixture; `cost-report.sh --json --include-legacy` on a fixture ledger | unpriced share < 5 %; totals match |

**Acceptance Criteria:**
- [ ] Each goal validated with documented evidence in `reviewer.md`
- [ ] Integration points verified (preflight reads notes-guard and breakers; status reads all three)
- [ ] No goal marked "not achieved" without explicit justification

### Dependencies
- Sprints 1–3 (status layout from 2, preflight from 3).

### Security Considerations
- **Trust boundaries**: `--reset-breaker` is an operator action journaled before the write; `--migrate-legacy` writes through the resolver-validated ledger writer (`O_NOFOLLOW`, refusals intact).
- **External dependencies**: none new.
- **Sensitive data**: status prints credential presence only; the KF template carries no secrets; the migration receipt records paths and hashes, not row contents.

### Risks & Mitigation
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Dated-id stripping maps to a wrong price | Low | Low | strip only when the base id exists; `pricing_resolution` recorded; unpriced share visible |
| Chain walk on OPEN not reproducible offline | Med | Med | dry-run trace with breaker fixture; if the resolver needs a live call, assert on the resolver's decision log |
| Only one dissent voice | Med | Low | failed-run envelope per skill guidance |

### Success Metrics
- Unpriced share on the fleet-id fixture < 5 %
- Providers block present in `/loa`; reset and expiry tested
- E2E table complete with evidence

---

## Risk Register

| # | Risk | Sprint | Owner | Status |
|---|------|--------|-------|--------|
| R1 | Fence relaxation admits a destructive command | 1 | implementer + auditor | mitigated by twins + corpus |
| R2 | Byte budgets overflow | 2 | implementer | trims in-commit; CI gate |
| R3 | Re-entry semantics unproven | 3 | implementer | Task 3.5 |
| R4 | Pricing ladder mis-maps | 4 | implementer | resolution field + share |
| R5 | Single dissent voice | all | reviewer/auditor | envelopes recorded |

---

## Success Metrics Summary

| Goal | Metric | Target |
|------|--------|--------|
| G-1 | corpus benign pass / dangerous block | ≥ 80 % / 100 % |
| G-2 | section reads of prd/sdd ≤ 100 KiB; budgets | pass |
| G-3 | preflight predicates with fixtures; resume line | ≥ 8; present |
| G-4 | providers reported; chain-walk test | all; pass |
| G-5 | unpriced share on fleet-id fixture | < 5 % |

---

## Dependencies Map

```
Sprint 1 (fences) ──────────────┐
Sprint 2 (artefacts) ──► Sprint 3 (preflight/resume) ──► Sprint 4 (health, cost, docs, E2E)
```

---

## Appendix

### A. PRD Feature Mapping
| PRD Requirement | Sprint | Tasks |
|-----------------|--------|-------|
| FR-1 Fence precision | 1 | 1.1–1.7 |
| FR-2 Sectioned artefacts | 2 | 2.1–2.6 |
| FR-3 Run preflight and resume | 3 | 3.1–3.6 |
| FR-4 Provider health | 4 | 4.1, 4.2, 4.5, 4.6, 4.E2E |
| FR-5 Cost accounting | 4 | 4.3, 4.4, 4.5, 4.6, 4.E2E |

### B. SDD Component Mapping
| SDD Section | Sprint |
|-------------|--------|
| §1.2 D-1.1–D-1.6 fence | 1 |
| §1.3 artefact reader, skill routing, rotation | 2 |
| §1.4 D-3.1–D-3.3 preflight, checkpoints, surfacing | 3 |
| §1.5 provider health · §1.6 cost | 4 |

### C. PRD Goal Mapping
| Goal ID | Goal | Sprints | Validation |
|---------|------|---------|------------|
| G-1 | Fences stop blocking harmless commands without losing a genuine catch | 1, 4 | corpus gates |
| G-2 | Planning artefacts readable and editable by section within tool limits | 2, 4 | reader bats + budgets |
| G-3 | Unattended runs fail loud before the first task or resume at the last task | 3, 4 | preflight fixtures + resume line |
| G-4 | Provider health visible and self-healing | 4 | status snapshot + chain-walk test |
| G-5 | The ids the fleet actually calls are priced | 4 | pricing ladder fixture + report |
