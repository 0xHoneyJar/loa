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

## Sprint 2: Test infra + filter + SSOT close-out

**Global Sprint ID:** 120
**Scope:** SMALL (4 tasks)
**Duration:** ~4h
**Tier:** 1

### Sprint Goal

Close the structural test-infra gap (G-5), the adversarial-review observability gap (G-6), the SSOT refactor cycle-093 deferred (G-7), and a final E2E fork-PR smoke (G-E2E).

### Deliverables

- [ ] BATS test files source the probe script via native `source` (no sed-strip pattern)
- [ ] Adversarial-review hallucination filter root cause documented; metadata assertion added; regression test catches non-application
- [ ] Red-team adapter `MODEL_TO_PROVIDER_ID` sourced from generator (or eliminated in favor of generated maps)
- [ ] Fork-PR E2E smoke documented in NOTES.md with command + expected output

### Acceptance Criteria (Sprint 2)

- [ ] **G-5 satisfied**: `tests/unit/model-health-probe*.bats` use `source "$PROBE_SCRIPT"` directly. The probe script's `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]` guard handles the source-vs-execute distinction. No `sed`-based pattern.
- [ ] **G-6 satisfied**: Adversarial-review JSON metadata always carries `hallucination_filter` key with `applied: bool`. Regression test asserts presence on a known-hallucinated diff.
- [ ] **G-7 satisfied**: `red-team-model-adapter.sh:MODEL_TO_PROVIDER_ID` either sourced from generated maps OR replaced by direct lookup against `MODEL_PROVIDERS`+`MODEL_IDS`. The cross-file invariant `model-registry-sync.bats:test 9` still green.
- [ ] **G-E2E satisfied**: `gh pr create` against a fork without API keys triggers `model-health-probe.yml` workflow → exits 0 with "no_api_keys" sentinel JSON; PR comment shows "skipped" status.

### Technical Tasks (Sprint 2)

- [ ] **Task 2.1** [G-5]: Update bats test setup pattern. Replace `eval "$(sed '...' "$PROBE")"` with `source "$PROBE"`. Verify the existing `if [[ BASH_SOURCE = $0 ]]; then main; fi` guard correctly skips main when sourced. Touch ~5 bats files.
- [ ] **Task 2.2** [G-6]: Read `adversarial-review.sh` to find hallucination-filter invocation. Determine why metadata didn't carry `hallucination_filter` key on sprint-4. Restore guarantee: filter ALWAYS runs (and writes metadata) on `--type review`, even when no findings would be downgraded. Add bats regression: synthetic diff + planted finding with `{{DOCUMENT_CONTENT}}` token → metadata.hallucination_filter.applied == true.
- [ ] **Task 2.3** [G-7]: Two-step refactor:
   1. Extend `gen-adapter-maps.sh` to emit a flat `RED_TEAM_PROVIDER_ID` map (alias → provider:model-id) for adapter use
   2. `red-team-model-adapter.sh` sources generated map; deletes hand-maintained `MODEL_TO_PROVIDER_ID`
   - If structural mismatch makes this invasive, fallback: keep hand-maintained map + tighten the cross-file invariant test to also validate keys (not just values)
- [ ] **Task 2.4** [G-E2E]: Manually trigger `model-health-probe.yml` on a no-secrets PR (use `gh workflow run` if dispatch is enabled, or simulate locally with `act`). Confirm exit 0 + sentinel JSON. Document in NOTES.md cycle-094 closure.

### Risks (Sprint 2)

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Native source breaks because probe script does work at top-level not gated by main-guard | Medium | Medium | Audit top-level statements in probe; gate any with-side-effect calls behind the main-guard |
| Hallucination-filter root cause is upstream (in `adversarial-review.sh` runtime) | Medium | Medium | If fix is invasive (>50 LoC), narrow to metadata-assertion only; full fix in cycle-095 |
| Red-team adapter SSOT refactor invasive | Low-Med | Medium | Fallback to invariant-test tightening instead of full source |

---

## Cycle-094 Cumulative Acceptance

- [ ] Both sprints merge cleanly to main (canonical order: sprint-1 → sprint-2)
- [ ] All 198 cycle-093 regression tests green throughout the cycle
- [ ] No new findings in security audit per sprint
- [ ] Cycle-094 closes with all 7 PRD goals (G-1 through G-7) ✓ Met
- [ ] CHANGELOG entry for v1.105.0 (or v1.104.x for patch-level) post-merge

## Out-of-scope deferrals

- **R27 — live GPT-5.5 validation**: deferred to whichever cycle follows OpenAI's API ship. Tracked in NOTES.md.
- **Shell Tests main breakage**: ~20 pre-existing failures in `release-notes` and `search-orchestrator` test files. Predates cycle-093. If cycle-095 picks this up, it's a 2-3 sprint cycle on its own.
