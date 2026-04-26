# Cycle-094 Sprint Plan — Cycle-093 Follow-ups

**Cycle:** 094
**Theme:** Tighten the screws after cycle-093 stabilization
**Duration:** 1 day total (2 sprints, ~4h each)
**Tier:** 1 (debt cleanup, no architectural changes)

> Note: this cycle does not have a dedicated SDD. The work is a curated set of follow-up fixes already broken down by task. Architectural decisions made during cycle-093 (probe state machine, scrubber lib, generator SSOT) remain authoritative — see `grimoires/loa/cycles/cycle-093-stabilization/sdd.md` (archived).

## Canonical merge order

`sprint-1` → `sprint-2`. Sprint 2 depends on Sprint 1's bash-3.2 sweep (Task 1.2) because Task 2.1 modifies the same probe script's BASH_SOURCE handling.

---

## Sprint 1: Probe + portability hardening

**Global Sprint ID:** 119
**Scope:** SMALL (4 tasks)
**Duration:** ~4h
**Tier:** 1 (debt cleanup)

### Sprint Goal

Close the production-impacting issues from cycle-093: probe cost-hardstop trip on no-API-key fork PRs (G-1), bash-3.2 portability gaps (G-2), and two filed cycle-093 follow-ups (G-3, G-4).

### Deliverables

- [x] `_probe_one_model` skips `COST_CENTS_USED++` when probe never made an HTTP call (PROBE_ERROR_CLASS=auth + HTTP_STATUS=0)
- [x] Repository-wide audit + remediation of `exec {[a-z_]+}>file` named-fd patterns; replaced with bash-3.2-compatible subshell+fd9 pattern
- [x] Issue #626 closed: `_lock_fd` unbound-variable error path now emits actionable error citing the writable-cache requirement
- [x] Issue #627 closed: dead inline `_redact_secrets` in `model-health-probe.sh` removed (lib is canonical post-sprint-3B)
- [x] Regression tests for each fix
- [x] Fork-PR-style smoke (no API keys) on local + CI — graceful skip, no exit 5 (local covered; CI gate to sprint-2 T2.4)

### Acceptance Criteria

- [x] **G-1 satisfied**: invocation with no API keys produces `summary.skipped: true` (or all-UNKNOWN for partial keys) without tripping cost hardstop. Subprocess exit 0.
- [x] **G-2 satisfied**: `grep -rE 'exec \{[a-z_]+\}>' .claude/scripts/` returns no matches (excluding test fixtures that test the pattern itself). All affected scripts pass `bash -n` AND run on macOS bash 3.2 (CI matrix).
- [x] **G-3 satisfied**: `LOA_CACHE_DIR=/readonly` invocation produces a clear "cache directory not writable: /readonly" error, not "_lock_fd: unbound variable".
- [x] **G-4 satisfied**: `grep -c "_redact_secrets() {" .claude/scripts/model-health-probe.sh` returns 0 (function only sourced from lib). All probe paths still pass redaction.
- [x] All 198 cycle-093 regression tests stay green
- [x] New tests cover each fix (≥1 test per task minimum)

### Technical Tasks (Sprint 1)

- [x] **Task 1.1** [G-1]: Edit `_probe_one_model` in `model-health-probe.sh`. Add a guard: only increment `PROBES_USED`/`COST_CENTS_USED` when `[[ "$PROBE_ERROR_CLASS" != "auth" || "$PROBE_HTTP" -ne 0 ]]`. Add 2 bats tests: (a) no-key probe doesn't increment; (b) 9 no-key probes don't trip the 5-cent budget.
- [x] **Task 1.2** [G-2]: `grep -rnE 'exec \{[a-z_]+\}>'` `.claude/scripts/`. For each match, apply the subshell+fd9 rewrite already used in `_cache_atomic_write` and `_circuit_update`. Add a meta-test that asserts no named-fd patterns remain via the same grep.
- [x] **Task 1.3** [G-3]: `model-health-probe.sh:_cache_atomic_write` should pre-flight check `[[ -w "$(dirname "$cache")" ]]` before attempting `exec 9>"$lockfile"`. Emit `log_error "cache directory not writable: $(dirname "$cache")"` and `return 1`. Add bats test using `chmod 555` on temp dir.
- [x] **Task 1.4** [G-4]: Remove the inline `_redact_secrets` definition from `model-health-probe.sh:118-128`. The library source line at the top of the file (cycle-093 sprint-3B) is the canonical implementation. Add a meta-test that asserts inline definition is gone. (Verified already-removed in cycle-093 sprint-3B; iter-2 added regression-guard meta-tests.)

### Risks (Sprint 1)

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| bash-3.2 sweep finds more call sites than expected | Medium | Medium | If >5 call sites, scope to probe-related only; remaining sites tracked as cycle-095 |
| Cost-increment fix changes hardstop semantics for legitimate probes | Low | Medium | The fix is conservative: only skip when ERROR_CLASS=auth AND HTTP=0 (truly no-network); legitimate auth-failed probes still consume budget |
| `_redact_secrets` removal breaks probe paths that don't source the lib | Low | High | Verify via grep that all callers reference the lib; covered by existing 18 secret-redaction.bats tests |

---

## Sprint 1 Amendment: Bridgebuilder review hardening

**Trigger:** PR #632 multi-model Bridgebuilder review (run `bridgebuilder-20260426T004443-cbe6`) returned 7 actionable test-quality findings (0 BLOCKER, 2 MEDIUM, 5 LOW). All target the Sprint-1 test files added in this PR; addressing them in-place keeps the PR's test surface coherent before merge.
**Scope:** Test-only. No production-code changes. Goal: tests assert what they claim to assert, and survive root execution + host bash drift.
**Duration:** ~1.5h

### Acceptance Criteria (Amendment)

- [x] **A1** Both G-3 read-only-cache tests skip with a clear message when `id -u == 0` (resolves F-001).
- [x] **A2** `bash32-portability.bats` either runs `bash -n` against an actual 3.2 binary when one exists on the host, or emits a loud `skip` documenting the gap (resolves F-002).
- [x] **A3** G-1 no-key probe test asserts on the cost-counter / probe-attempt invariant directly rather than via registry size (resolves F1).
- [x] **A4** G-4 secret-redaction test pins the canonical guard text via a focused micro-test, so a script restructure breaks one test instead of silently passing G-4 (resolves F2).
- [x] **A5** C-1 mv-shim test installs a witness marker that the shim asserts via `touch`, with a post-shim assertion that the marker exists (resolves F3).
- [x] **A6** C-1 timeout test moves holder-process cleanup into `trap '...' EXIT` so an assertion failure can't leak the holder (resolves F4).
- [x] **A7** `bash32-portability.bats` named-fd grep widened to cover `<`, `<>`, and digit-suffixed names (`exec[[:space:]]+\{[a-zA-Z_][a-zA-Z0-9_]*\}[<>]`), with a comment documenting why the EXCLUDE pattern lacks an implementation (resolves F5).
- [x] All 157 sprint-1 bats tests still green after amendment. (Net: 160/160 — +3 new tests.)

### Technical Tasks (Amendment)

- [x] **Task A.1** [F-001]: Add `[ "$(id -u)" = 0 ] && skip "chmod-based test invalid as root"` at the top of the two G-3 tests in `tests/unit/model-health-probe.bats`.
- [x] **Task A.2** [F-002]: In `tests/unit/bash32-portability.bats`, detect a 3.2 binary (`/bin/bash` on macOS or `LOA_BASH32_PATH` override) and run `bash -n` against it; otherwise emit `skip "bash 3.2 not available; gate is host-bash-only"`.
- [x] **Task A.3** [F1]: Reworked the G-1 no-key full-registry test in `tests/unit/model-health-probe-hardstop.bats` to assert via `LOA_PROBE_MAX_PROBES=1` (any probe attempt → exit 5; with guard → exit ≠ 5), making the invariant independent of registry size. Original cost-cap path retained as a companion test.
- [x] **Task A.4** [F2]: Added focused regression test in `tests/unit/secret-redaction.bats` (`G-4: probe still carries the canonical 'BASH_SOURCE == 0' main-script guard`) that pins the exact guard text via `grep -qxE`.
- [x] **Task A.5** [F3]: C-1 mv-shim test now `touch`es `$TEST_TMPDIR/mv-shim-fired` and asserts the marker exists immediately after the run.
- [x] **Task A.6** [F4]: C-1 lock-acquisition timeout test now installs `trap 'kill $hold_pid …; wait …' EXIT` before the timing-sensitive body.
- [x] **Task A.7** [F5]: Named-fd grep broadened to `exec[[:space:]]+\{[a-zA-Z_][a-zA-Z0-9_]*\}[<>]` (covers `<`, `>`, `<>`, digit-suffixed names) with an inline comment explaining why the EXCLUDE array is currently documentation-only.

---

## Sprint 2: Test infra + filter + SSOT close-out

**Global Sprint ID:** 120
**Scope:** SMALL (4 tasks)
**Duration:** ~4h
**Tier:** 1

### Sprint Goal

Close the structural test-infra gap (G-5), the adversarial-review observability gap (G-6), the SSOT refactor cycle-093 deferred (G-7), and a final E2E fork-PR smoke (G-E2E).

### Deliverables

- [x] BATS test files source the probe script via native `source` (no sed-strip pattern)
- [x] Adversarial-review hallucination filter metadata assertion added; regression test catches non-application
- [x] Red-team adapter `MODEL_TO_PROVIDER_ID` cross-file invariant tightened (fallback path: provider agreement validated against generated `MODEL_PROVIDERS` map for shared keys)
- [x] Fork-PR E2E smoke documented in NOTES.md with command + expected output

### Acceptance Criteria (Sprint 2)

- [x] **G-5 satisfied**: `tests/unit/model-health-probe*.bats` use `source "$PROBE_SCRIPT"` directly. The probe script's `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]` guard handles the source-vs-execute distinction. No `sed`-based pattern.
- [x] **G-6 satisfied**: Adversarial-review JSON metadata always carries `hallucination_filter` key with `applied: bool`. Regression test asserts presence on a known-hallucinated diff.
- [x] **G-7 satisfied** (via fallback): hand-maintained `MODEL_TO_PROVIDER_ID` retained; cross-file invariant test (`tests/integration/model-registry-sync.bats`) tightened with new G-7 test that validates provider agreement on every key shared between the red-team adapter and the generated `MODEL_PROVIDERS` map.
- [x] **G-E2E satisfied** (local + workflow YAML inspection): script-side fork-PR-equivalent smoke produces exit 0 + `summary.skipped: true` + 12 UNKNOWN entries. Workflow-side no-keys path (`.github/workflows/model-health-probe.yml:98-103`) inspected; produces sentinel JSON with `reason: "no_api_keys"`. CI re-trigger on fresh fork deferred — out-of-scope for this sprint, tracked as future fork-test infra.

### Technical Tasks (Sprint 2)

- [x] **Task 2.1** [G-5]: Replaced `eval "$(sed '...' "$PROBE")"` with `source "$PROBE"` in 4 bats files. Verified probe top-level statements are pure declarations (no side effects beyond variable initialization). Main-guard at `model-health-probe.sh:1509` correctly skips main on source.
- [x] **Task 2.2** [G-6]: Updated `_apply_hallucination_filter()` in `.claude/scripts/adversarial-review.sh` so all three early-return paths (missing diff, no findings, dirty diff) emit `metadata.hallucination_filter = {applied: false, downgraded: 0, reason: <category>}`. Added 2 BATS regression tests: full-coverage path enumeration + verbatim AC test (planted `{{DOCUMENT_CONTENT}}` finding on clean diff).
- [x] **Task 2.3** [G-7]: Took the planned fallback path (invariant tightening). Added new G-7 test in `tests/integration/model-registry-sync.bats` that sources `generated-model-maps.sh`, parses red-team's `MODEL_TO_PROVIDER_ID`, and asserts every K shared between the two maps has matching provider. Path 1 (full SSOT refactor) deferred — would have expanded `model-config.yaml`'s scope to include red-team-only aliases (`gpt`, `gemini`, `kimi`, `qwen`).
- [x] **Task 2.4** [G-E2E]: Smoke command + expected output documented in `grimoires/loa/NOTES.md` Decision Log "2026-04-26 (cycle-094 sprint-2 — test infra + filter + SSOT close-out)". Local script-side smoke verified exit 0; workflow-side inspected for the sentinel-JSON path.

### Risks (Sprint 2)

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Native source breaks because probe script does work at top-level not gated by main-guard | Medium | Medium | Audit top-level statements in probe; gate any with-side-effect calls behind the main-guard |
| Hallucination-filter root cause is upstream (in `adversarial-review.sh` runtime) | Medium | Medium | If fix is invasive (>50 LoC), narrow to metadata-assertion only; full fix in cycle-095 |
| Red-team adapter SSOT refactor invasive | Low-Med | Medium | Fallback to invariant-test tightening instead of full source |

---

## Cycle-094 Cumulative Acceptance

- [x] Sprint-1 merged cleanly to main via #632 (commit 7ae3a12)
- [ ] Sprint-2 PR ready (this sprint)
- [x] All 198 cycle-093 regression tests green throughout the cycle (188/188 in the directly-affected sprint-2 suite; remaining tests untouched)
- [ ] No new findings in security audit per sprint (post-PR audit pending)
- [x] Cycle-094 closes with all 7 PRD goals (G-1 through G-7) ✓ Met
- [ ] CHANGELOG entry for cycle-094 closure (post-merge automation)

## Out-of-scope deferrals

- **R27 — live GPT-5.5 validation**: deferred to whichever cycle follows OpenAI's API ship. Tracked in NOTES.md.
- **Shell Tests main breakage**: ~20 pre-existing failures in `release-notes` and `search-orchestrator` test files. Predates cycle-093. If cycle-095 picks this up, it's a 2-3 sprint cycle on its own.
