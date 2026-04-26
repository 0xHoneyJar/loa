# Cycle-094 PRD — Cycle-093 Follow-ups + Technical Debt Cleanup

**Cycle:** 094
**Theme:** Tighten the screws after cycle-093 stabilization
**Active:** 2026-04-25 — TBD
**Predecessor:** cycle-093 (shipped at v1.104.0; 6 PRD goals closed)

## Background

Cycle-093 shipped a major stabilization wave (probe + resilience + registry SSOT). Across the four sprints we collected a known set of follow-up items — some filed as GitHub issues, some surfaced during implementation/audit/review, all genuinely small but cumulatively worth a focused cleanup cycle.

This cycle does NOT introduce new functionality. It pays down debt and closes loose ends so cycle-095 can start from a clean baseline.

## Goals

| ID | Goal | Closure |
|---|---|---|
| **G-1** | Probe gracefully degrades when no API keys are configured | `_probe_one_model` skips cost increment for no-network paths (UNKNOWN+auth, HTTP_STATUS=0) — fixes the cost-hardstop trip that broke fork PR CI |
| **G-2** | bash-3.2 portability across all Loa probe-adjacent scripts | Sweep for `exec {_var}>file` named-fd usages; replace with hardcoded fd subshell pattern |
| **G-3** | #626 closed — `_lock_fd` unbound-variable on unwritable cache | Diagnostic upgrade for fail-mode visibility |
| **G-4** | #627 closed — dead `_redact_secrets` cleanup in probe (post-sprint-3B refactor) | Remove the inline shadow now that lib-sourced is canonical |
| **G-5** | #628 closed — BATS sed-sourcing structural pattern hardened | Replace fragile `sed`-based source pattern with native sourceability |
| **G-6** | Hallucination-filter non-trigger investigation | Determine why sprint-4's adversarial review didn't apply T1.3 filter; restore the guard or document the bypass condition |
| **G-7** | Red-team adapter sources generated maps (SSOT refactor) | Eliminate the last hand-maintained `MODEL_TO_PROVIDER_ID` map; close cycle-093 sprint-4 ⚠ Partial |

## Non-Goals

- Live GPT-5.5 validation (R27 — deferred to follow-up cycle when OpenAI ships `gpt-5.5` in `/v1/models`).
- Shell Tests pre-existing main breakage (~20 tests in `release-notes`/`search-orchestrator` — unrelated to cycle-093, deserves its own focused cycle if a fix-up is desired).
- New features, architectural changes, or model migrations.

## Success Metrics

- All 6 PRD goals (G1–G7) closed with regression tests where applicable
- 0 CRITICAL/HIGH findings in security audit
- Probe + adapter test suite stays green (all 198 cycle-093 tests + new follow-up regressions)
- Fork PR CI passes cleanly (no API keys configured) — current behavior: probe trips cost hardstop, exits 5
- macOS portability verified end-to-end (probe, adapter, any other touched script)

## Scope (8 tasks across 2 sprints)

### Sprint 1: Probe + portability hardening (4 tasks)

- **Task 1.1** [G-1]: Gate `_probe_one_model` cost/probe increments on actual HTTP activity (not auth/no-key paths)
- **Task 1.2** [G-2]: Repository-wide grep for `exec {[a-z_]+}>` patterns; convert to subshell + hardcoded fd
- **Task 1.3** [G-3]: Issue #626 — `_lock_fd` unbound-variable diagnostic upgrade on unwritable cache
- **Task 1.4** [G-4]: Issue #627 — remove dead `_redact_secrets` inline implementation from probe (now sourced from lib)

### Sprint 2: Test infra + filter + SSOT (4 tasks)

- **Task 2.1** [G-5]: Issue #628 — replace `sed`-based bats source pattern with native `source` of the script (and a small `BASH_SOURCE`-aware guard for main-runner skip)
- **Task 2.2** [G-6]: Investigate adversarial-review hallucination-filter non-trigger; add metadata assertion + regression test
- **Task 2.3** [G-7]: Refactor red-team adapter to source `MODEL_TO_PROVIDER_ID` from generated-model-maps.sh (extend generator if needed)
- **Task 2.4** [E2E]: End-to-end smoke — fork-PR-style invocation (no API keys) on local + macOS to confirm graceful skip rather than cost-hardstop trip

## Authorization

This PRD authorizes System Zone writes (`.claude/scripts/*`, `.claude/skills/*` only as touched by these tasks) for cycle-094 scope only per `.claude/rules/zone-system.md` "explicit cycle-level approval".

## Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| bash-3.2 sweep surfaces too many call sites | Medium | Medium | Scope to probe-adjacent scripts; remaining sites tracked as cycle-095 candidates |
| Hallucination filter root cause is in `adversarial-review.sh` (sprint-2 territory) | Medium | Low-Med | If invasive fix needed, narrow to "regression test + metadata assertion"; deeper rewrite in next cycle |
| Generator extension for red-team `MODEL_TO_PROVIDER_ID` requires structural change | Low-Med | Medium | If structure-incompatible, retain the cross-file invariant guard from cycle-093 sprint-4 T4.4 |
| Test infrastructure changes (sed-source → native source) trigger regression in 100+ bats files | Medium | High | Roll out incrementally; invariant tests catch regressions; --check gates merge |

## Dependencies

- Cycle-093 closed (DONE, archived 2026-04-25)
- Branch from current main (`12a185c` after ledger archive commit)
- Ledger global_sprint_counter starts at 119 (sprint-118 was cycle-093's last)
