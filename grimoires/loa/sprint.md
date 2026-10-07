# Sprint Plan: Operator Decisions (cycle-127)

**Version:** 1.0
**Date:** 2026-10-07
**Status:** Draft — autonomous run (maintainer delegation with admin preapproval)
**PRD:** `grimoires/loa/prd.md` · **SDD:** `grimoires/loa/sdd.md` · **Decision record:** `grimoires/loa/NOTES.md` § Decision Log — 2026-10-07
**Branch:** `feature/cycle-127-operator-decisions` · **Ledger:** cycle `cycle-127-operator-decisions`, sprint 251 (= sprint-1)

---

## Executive Summary

One sprint, one lead agent, unattended, with an Opus 5.5 implementer and Fable review and audit. Three narrow changes at existing seams (SDD §1.1): the agy route becomes opt-in and every planner treats "off" as *not planned*; `claude-opus-5-5` gets a typed catalog effort default resolved once at the cheval chokepoint; the ceiling probe gains a headless-CLI transport and is run once through this host's Bedrock route to replace the 180K shortcut with a measured, provenance-tagged bound.

## Sprint Overview

| Sprint | Global | Theme | FR | Exit gate |
|---|---|---|---|---|
| 1 (Final) | 251 | agy opt-in, Opus 5.5 effort default, ceiling probe | FR-1 … FR-3 | SC-1 … SC-4: refusal + not-planned on this host; `effort: high (catalog default)` in a dry run; probe record + catalog write (or documented attempt); review and audit APPROVED |

---

## Sprint 1 (Final): agy opt-in, Opus 5.5 effort default, ceiling probe

**Global id:** 251 · **FR:** FR-1, FR-2, FR-3 · **SDD:** §1.2 (D-1.1 … D-1.4), §1.3 (D-2.1 … D-2.4), §1.4 (D-3.1 … D-3.4)

### Sprint Goal
On a host without `agy` and without the opt-in, no planner counts the agy route as a voice and none reports it as failed; an `opus` call with no `--effort` reasons at `high` through both adapters; the Opus 5.5 input bound on this host's route is measured and recorded with its provenance — or the attempt is recorded and 180K stays.

### Deliverables
- `hounfour.headless.agy_opt_in` (default false) read by the agy adapter (refusal, `opt_in_required`), the dissent, Flatline, Bridgebuilder registration, `run-preflight.sh` and `/loa` Providers; `.loa.config.yaml.example` key with rationale.
- `params.default_effort` in the v3 schema; `claude-opus-5-5: high`; `resolve_effort(args, entry)` at the cheval chokepoint; MODELINV `effort_source`; `--dry-run` line.
- `tools/ceiling-probe-live.py --transport claude-headless`; the record under `grimoires/loa/reports/`; the catalog write (`operator_set`) if clean; the 180K pin sweep; regenerated maps/registry.
- Docs: migration addendum (gate, effort default replacing the caveat, probe transport), CHANGELOG `[Unreleased]`, cycle-126 SDD D-4.1 pointer, beads bd-ugmi (decision) and bd-9qe2 (closed).

### Acceptance Criteria
- [ ] With `hounfour.headless.agy_opt_in` absent or `false`: `cheval` refuses an agy dispatch before any subprocess with a message naming the key; the dissent envelope, Flatline and Bridgebuilder record the voice as `planned: false, reason: opt_in_required` (verdict quality not DEGRADED on its account); `/loa` Providers and `run-preflight.sh` show "agy: opt-in (disabled)". With `true`, today's path runs (binary absent here → `PROVIDER_UNAVAILABLE`).
- [ ] `cheval invoke --model opus --dry-run` with no `--effort` reports `effort: high (catalog default)`; `--effort low` reports `low (caller)`; the HTTP adapter emits `output_config.effort: high` and the CLI adapter passes `--effort high` for the default; `claude-opus-5` (no default) sends nothing; the MODELINV envelope carries `effort_source`; a bad `params.default_effort` fails schema validation.
- [ ] `tools/ceiling-probe-live.py --transport claude-headless` is tested (command shape, OK/size/other classification, partial → no write, `operator_set` write shape) and was run once for `claude-opus-5-5` through `claude-bedrock` within the $20 budget; the record is under `grimoires/loa/reports/`; the catalog carries either the measured `operator_set` bound with `calibrated_at` and `reprobe_trigger` or the unchanged 180K with the attempt documented; no test pins the Opus 5.5 bound by literal.
- [ ] Docs present (migration addendum, CHANGELOG, example config, SDD pointer); beads updated; every touched suite green with 0 skips; REPO-MAP + sidecar + checksums regenerated; `reviewer.md` with `## AC Verification` and the live evidence (refusal, dry-run line, `/loa` line, probe record).

### Technical Tasks
- **Task 1.1 — Failing tests.** Agy gate (adapter spy: no spawn when off), dissent `planned: false` reason, Bridgebuilder registration + verdict quality, preflight/`/loa` line; schema enum + bad value; `resolve_effort` precedence (caller > catalog > none) and both adapters' emission; probe CLI transport shape, classification, partial → no write, `operator_set` write.
- **Task 1.2 — agy opt-in gate (FR-1).** Key + loader; adapter refusal; planner mapping in `adversarial-review.sh`, `flatline-orchestrator.sh`, Bridgebuilder `config.ts`/registration, `run-preflight.sh`, `loa-status.sh`; example config; bd-ugmi comment.
- **Task 1.3 — Effort default (FR-2).** Schema field; catalog value; `resolve_effort` at the three `CompletionRequest` sites; MODELINV `effort_source`; `--dry-run` line; migration caveat replaced; bd-9qe2 closed.
- **Task 1.4 — Probe transport (FR-3.1–3.2).** `--transport claude-headless` mirroring the adapter's command; record fields; `operator_set` write path; the 180K pin sweep (literal → catalog read).
- **Task 1.5 — The probe run (FR-3.3, lead).** One run through `claude-bedrock`, budget $20; record committed; catalog written if clean; maps/registry regenerated; affected suites re-run.
- **Task 1.6 — Docs + E2E.** Migration addendum, CHANGELOG, SDD pointer; live evidence collected into `reviewer.md` (refusal transcript, `/loa` line, dry-run line, probe record); full affected-suite table.

### Task 1.5 result (2026-10-07)
One live run through `claude-bedrock`: three needle-verified accepts (696,136 / 880,634 / 972,887 measured input tokens), two CLI pre-flight rejections at the 1,000,000 window, $12.74 CLI-reported spend, outcome `partial` (budget cap before the filler tolerance). Catalog written by the lead as `operator_set` at 936,000 (I2 clamp: 1M − 64K default output; measured 972,887 recorded in `ceiling_calibration.measured_input_tokens`). Record: `grimoires/loa/reports/2026-10-07-opus-5-5-ceiling-probe-cli.json`. See SDD §1.6.

### Dependencies
Task 1.1 before 1.2–1.4 (test-first); 1.5 after 1.4; 1.6 last.

### Testing Requirements
Serial bats and pytest in the real tree (`env -u CLAUDE_HEADLESS_BIN -u AWS_BEARER_TOKEN_BEDROCK`); Bridgebuilder vitest; the one live probe (Task 1.5) is the only model spend besides review/audit dissent.

---

### Flatline review integration (2026-10-07; scoring degraded — KF-041 — integrated by judgment)
- **Clean vs partial probe outcome (AC 3, SDD D-3.7/3.8).** *Clean*: an attempt at N accepted and verified by the echoed needle, a size-class rejection at the next step within `--tolerance-tokens`, and no `other` classification anywhere in the bisection. *Partial*: any `other` failure, a budget abort, an unverified completion counted as the bound, or inconsistent classifications (accept above a rejection). Only a clean outcome writes the catalog; a partial one writes the record and keeps 180K, and the entry's `ceiling_calibration.reprobe_trigger` gains a pointer to the attempt record.
- **Budget (Task 1.5).** Before the first call the probe prints the worst-case per-step cost and the step count that fits in `--budget-usd 20` at the catalog price; spend is cumulative across attempts and retries; the lead runs with `CLAUDE_HEADLESS_BIN=$HOME/.local/bin/claude-bedrock` and `AWS_BEARER_TOKEN_BEDROCK` present (the wrapper reads its own secret), then re-runs the affected suites under the usual `env -u CLAUDE_HEADLESS_BIN -u AWS_BEARER_TOKEN_BEDROCK` isolation.
- **Conformance.** One fixture config pair (opt-in on / off) is read by every reader — the agy adapter, `adversarial-review.sh`, `flatline-orchestrator.sh`, Bridgebuilder, `run-preflight.sh`, `loa-status.sh` — and a conformance test asserts they agree; a non-boolean value fails loudly at the loader. With agy off and a *different* voice failing, verdict quality still reports DEGRADED (negative test).
- **SC ↔ AC map.** SC-1 ↔ AC 1 (gate and planners), SC-2 ↔ AC 2 (effort), SC-3 ↔ AC 3 (probe), SC-4 ↔ AC 4 plus the review/audit gates.
- **Loop stop condition.** The unattended loop is `/run sprint-plan`'s: at most the circuit breaker's cycles per gate; CHANGES_REQUIRED → `/implement` round; APPROVED review → `/audit-sprint`; APPROVED audit → COMPLETED → PR. Dissent ≤ 2 runs per gate for this one-sprint cycle.
- **Scope-cut order if blocked.** FR-1 > FR-2 > FR-3 transport code > FR-3 live run (the live run may end as "attempt recorded, 180K kept" and still satisfy AC 3).
- **Rollback.** FR-1: unset or set the key to false (default-off is the safe state); FR-2: delete the `default_effort` line from the `claude-opus-5-5` entry; FR-3: revert the catalog diff and keep the report.

## MVP Definition
All three FRs; the probe may legitimately end with "attempt recorded, 180K kept" if the bound is unclean — that outcome still satisfies the AC.

## Risk Assessment
See SDD §9. The probe is the only step with external uncertainty; it is bounded by budget and by the no-write-on-partial rule.

## Success Metrics
PRD KPIs: verdict quality on this host not DEGRADED on the agy route's account (the google-family voice, which reaches Gemini only through agy here); `effort: high` by default for `opus`; a measured Opus 5.5 bound or a documented attempt.
