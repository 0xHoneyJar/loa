All good

Sprint 251 has been reviewed and approved. All acceptance criteria met. Observations documented and non-blocking. See Observations below.

# Sprint 251 Review Feedback — round 2 (r251-3)

**Reviewer:** Senior Tech Lead Reviewer Agent (Fable 5.1)
**Date:** 2026-10-08
**Sprint Reference:** grimoires/loa/sprint.md (Sprint 1 = global sprint 251, cycle-127 operator decisions)
**Implementation Report:** grimoires/loa/a2a/sprint-251/reviewer.md
**Scope reviewed:** HEAD `58f87195` (`git diff 6f6cc8a6..58f87195`; the round-1 delta `git diff d12bdfab..58f87195`, 24 files, +543/−203), the round-1 feedback (CHANGES_REQUIRED: 1 HIGH, 3 MEDIUM, 7 LOW), the two dissent rounds and the merged envelope `adversarial-review.json` (76 findings, 2/2 voices, `rejected_summary: []`, every rejected sidecar empty), the `e2e/` artefacts and the probe record. No model was called by this review.

---

## Overall Assessment

Round r251-3 closes the one blocker and every round-1 observation in code, tests and docs, or defers it to a named bead where that was the right call. The HIGH is fixed the way it should be: one `is_throttle_message()` in `loa_cheval/routing/ceiling.py` is now consulted by the headless adapter before its context-limit mapping and by the probe's classifier in place of its private regex, and a conformance test feeds identical strings to both. I re-ran my round-1 probe of the shipped `_raise_for_error` on fifteen shapes: Bedrock's "Too many tokens, please wait before trying again" in its stderr, `result` + `api_error_status: 429`, bare and `ThrottlingException:` forms, `API Error: 429. Too many tokens`, `429 rate limit exceeded` and `529 overloaded_error` all raise `RateLimitError` (the Bedrock shapes with `token_limited=True`), while `Prompt is too long`, `Prompt is too long: 1,429,000 tokens > 1,000,000 maximum`, `~1065182 tokens (limit 1000000)`, `~1052900 tokens (limit 1000000)` and the `input length and max_tokens exceed context limit` form raise `ProviderContextLimitError`; a token count containing 429/529 is never read as a status. On a CLI hop `RateLimitError` is retried by the retry layer and then walked (`_hop_unverified` cannot be set for an entry without `probed_ceiling`, `cheval.py:2364`), which restores the pre-K8 behaviour for throttles while keeping K8's size verdict.

The two acceptance-criteria gaps are closed: the K9 check reads the catalog and the literal guard sweeps the current bound's digits; the cycle-126 SDD D-4.1 amendment carries the pointer and the beads export is flushed. The planning documents now say what shipped. Four observations remain, none blocking; the first is a report-hygiene item the lead must fix before the audit gate runs its own AC validator.

**Verdict:** APPROVED

---

## Observations

### 1. reviewer.md's AC 1 heading lags the amended acceptance-criteria text

- **MEDIUM** (confidence: high) `grimoires/loa/a2a/sprint-251/reviewer.md:41` — r251-3 amended AC 1 in `sprint.md` (binary absent → "the existing `INVALID_CONFIG` "agy CLI not found" refusal, unchanged by this cycle") but the report's `### With …` heading still carries the pre-r251-3 wording (→ `PROVIDER_UNAVAILABLE`), so `validate-ac-verification.sh --report reviewer.md --sprint sprint.md --sprint-id sprint-1` now fails ("acceptance criterion not walked verbatim"). The walkthrough itself is complete (all four ACs with `file:line` evidence; the other three headings are verbatim), which is why this does not block approval — but the audit gate (C9) runs the same validator before the COMPLETED marker and will refuse.
**Suggestion:** lead: paste the amended AC 1 text into the heading (one line), re-run the validator on `reviewer.md`.
**Benefit:** `/audit-sprint` is not stopped by a mechanical check on a report that is substantively correct.

### 2. AGC-6 still fails intermittently inside the full-file batch after the 180 s timeout

- **LOW** (confidence: medium) `tests/unit/agy-gate-conformance.bats:121` — on my side AGC-6 failed in 2 of 3 full-file runs and passed in 0.9 s every time alone, and passed paired with AGC-5; the third full-file run (with `--timing`) passed 12/12. A pure load flake would not spare AGC-8, which makes the same `loa-status --json` call six times with no fake `agy` on PATH and has never failed. The test's failure branch prints `$output | tail -5` only, so a timeout (empty output) and a JSON mismatch look alike.
**Suggestion:** print `$status` and `$stderr` on failure too, and if it recurs capture one failing `--json` output to tell a `timeout 180` expiry (`loa-status` → `loa-doctor.sh --quick` → `br`, which can wait on the beads SQLite lock while another agent writes) from a gate mismatch; the 180 s bump treats a symptom.
**Benefit:** the next failure is diagnosable instead of recorded as "load".

### 3. The throttle check now precedes the auth checks with broader markers

- **LOW** (speculative, confidence: low) `.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:577` — `is_throttle_message` adds `please wait`, `throttl`, `rate_limit` and `tokens per min` to the words that used to trigger the rate-limit branch, and that branch runs before the auth-revoked / not-logged-in branches as it did before. A CLI auth or login message that happened to contain "please wait" would be classed as a rate limit (walked, retried) rather than `ConfigError` (hard abort). I know of no such Claude Code `-p` message; the probe carried the same marker since r251-1 without incident.
**Suggestion:** none required; if a real shape appears, give the static-auth markers (`not logged in`, `/login`) precedence over `please wait` alone.
**Benefit:** a misclassified auth failure would waste retries instead of failing fast.

### 4. The provider lookup behind the routing rule fails soft

- **LOW** (confidence: medium) `.claude/adapters/loa_cheval/config/loader.py:220` and `.claude/scripts/lib/agy-gate-lib.sh:104` — when the System catalog or `generated-model-maps.sh` cannot be read (or bash < 4), `catalog_provider_of` / `agy_catalog_provider` fall back to the `gemini*` name rule, so a Google voice without that prefix (`deep-research-pro`) under cli-only is planned by the bash/Python readers while cheval (`_entry_routes_to_agy`, kind:cli under provider google) still refuses it: a planned voice that fails `opt_in_required`, the round-1 shape, but only on a host whose catalog is unreadable. Cheval's own gate still refuses, so nothing is spawned.
**Suggestion:** accept as documented (the docstrings say "fail soft"); optionally WARN once when the maps could not be read, as the lib does for the opt-in type.
**Benefit:** the degraded rule is visible when it applies.

---

## Previous Feedback Status

Round 1 (`engineer-feedback.md`, CHANGES_REQUIRED) → round r251-3 (`58f87195`). Verified in the code, not the report.

| Issue | Status | Notes |
|-------|--------|-------|
| Changes Required 1 (HIGH) — Bedrock token throttle classified as a context limit on the headless route | Resolved | `routing/ceiling.py:249` `is_throttle_message` (`_THROTTLE_MARKERS` `:236`, `_RE_THROTTLE_STATUS` `:246`), consulted at `claude_headless_adapter.py:562` before the context-limit mapping (`:563`) and by the probe at `tools/ceiling-probe-live.py:350` (its private `_THROTTLE` removed); `test_claude_headless_context_limit.py:58` (the four Bedrock shapes → `RateLimitError`), `:74` (digits in a count never a status), `:102` (the predicate table), `:144` (probe-vs-adapter conformance on 18 strings); CHANGELOG `:15`, addendum `:345`, SDD §6 `:93`. My own probe at 58f87195 agrees on every shape (see Overall Assessment). |
| Obs 1 (MEDIUM) — literal 936_000 pin vs AC 3 | Resolved | `test_anthropic_catalog_floor.py:191` reads `effective_input_ceiling` from the entry and asserts `input_bound(...).basis == "calibrated"`; the guard pattern at `test_no_literal_opus55_ceiling_pins.py:21` is `(180|936)[_,]?000`; LSP-5 fixtures moved to 920,000 |
| Obs 2 (MEDIUM) — SIMPLICITY[shrink] `_main_cli` | Deferred, by bead | `bd-rbkz` (extract a `Bisection` object on the next touch); accepted in round 1 as non-blocking for an operator tool |
| Obs 3 (MEDIUM) — cycle-126 SDD D-4.1 pointer absent; beads not flushed | Resolved | `grimoires/loa/archive/cycle-126-full-size/sdd.md:89` carries the pointer; `bd-c2rd`, `bd-y49y`, `bd-n6lk`, `bd-rbkz` are in `.beads/issues.jsonl` (both paths are gitignored here — host-local by design) |
| Obs 4 (LOW) — name-prefix vs provider routing rule | Resolved, with one residue | `loader.py:257` `catalog_provider_of` (catalog + alias overlay) and `agy-gate-lib.sh:104` `agy_catalog_provider` (generated maps); `run-preflight.sh:175` `provider_of` falls through to it; rows in `test_agy_opt_in_gate.py:224`, `agy-gate-conformance.bats:54` (AGC-1/AGC-2), `run-preflight.bats:333` (PF-AGY-6). Residue: the fail-soft fallback, Observation 4 above |
| Obs 5 (LOW) — Bedrock HTTP adapter ignores `request.effort` | Deferred, by bead | `bd-n6lk` (pre-existing, outside FR-2's scope) |
| Obs 6 (LOW) — calibrate hint names the CLI entry | Resolved | `cheval.py:358` `_calibrate_hint`: an HTTP hop names itself, a claude-headless hop names the chain's Anthropic HTTP entry with `--transport claude-headless`, otherwise no hint and "the CLI's own window refused the payload" (`:2248`, `:2259`); `test_claude_headless_context_limit.py:228` and the cheval-level test assert it |
| Obs 7 (LOW) — SDD §5/§6, sprint.md:62, AC 1 / PRD SC-1 drift | Resolved | `sdd.md:89`, `:93`; `sprint.md:62` marks the superseded sentence; `prd.md:142` and AC 1 name the `INVALID_CONFIG` refusal (which is why reviewer.md's heading now lags — Observation 1) |
| Obs 8 (LOW) — host-global ledger assertion in the probe suite | Resolved | `test_ceiling_probe_cli_transport.py:106` is per-test over the conftest-isolated `LOA_MODELINV_LOG_PATH`; 456/456 with no teardown error |
| Obs 9 (LOW) — `cycle-124-effort-flag.bats` host-env sensitivity | Resolved | `tests/unit/cycle-124-effort-flag.bats:30` unsets `CLAUDE_HEADLESS_BIN` and `AWS_BEARER_TOKEN_BEDROCK`; 13/13 under the host env |
| Obs 10 (LOW) — AGC-6 batch flake | Partially addressed | timeout 120 → 180 s (`agy-gate-conformance.bats:121`); the batch-only failure persisted in 2 of my 3 full-file runs — Observation 2 |

---

## AC Verification

### With `hounfour.headless.agy_opt_in` absent or `false`: `cheval` refuses an agy dispatch before any subprocess with a message naming the key; the dissent envelope, Flatline and Bridgebuilder record the voice as `planned: false, reason: opt_in_required` (verdict quality not DEGRADED on its account); `/loa` Providers and `run-preflight.sh` show "agy: opt-in (disabled)". With `true`, today's path runs (binary absent here → the existing `INVALID_CONFIG` "agy CLI not found" refusal, unchanged by this cycle).
- Status: ✓ Met
- Evidence: `grimoires/loa/a2a/sprint-251/e2e/agy-refusal.txt` (live refusal, `INVALID_CONFIG`, key named, no spawn — unchanged since round 1); `.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:124` (gate before discovery), `:262` (`validate_config`), `:294` (`health_check`), `:201` (opt-in on, binary absent → the existing `ConfigError` / `INVALID_CONFIG` "agy CLI not found" — now what the AC says); `.claude/adapters/loa_cheval/config/loader.py:167` (`agy_opt_in_enabled`, project config only, strict `true`), `:257` (`catalog_provider_of`), `:294` (`routes_to_agy`: provider-based under cli-only); `.claude/adapters/cheval.py:375` (`_plan_around_agy`), `:2631` (the `opt_in_required` arm → `models_failed` INVALID_CONFIG); `.claude/scripts/lib/agy-gate-lib.sh:83` (`agy_opted_in`), `:104` (`agy_catalog_provider`), `:128` (`routes_to_agy`); `.claude/scripts/adversarial-review.sh:2367` / `:4116`; `.claude/scripts/flatline-orchestrator.sh:540`; `.claude/skills/bridgebuilder-review/resources/config.ts:232`; `core/multi-model-pipeline.ts:453`; `.claude/scripts/run-preflight.sh:193` (P3 not planned), `:175` (`provider_of` → the generated maps); `.claude/scripts/loa-status.sh:807`; `e2e/loa-providers.txt:30`. Run by me at 58f87195: `test_agy_opt_in_gate.py` (incl. the new rows at `:224`), `test_agy_chain_walk_opt_in.py`; bats `agy-gate-conformance` 12/12 (AGC-6 — Observation 2), `run-preflight` 20/20 (PF-AGY-6 at `tests/unit/run-preflight.bats:333`), `loa-status-providers` 9/9, `flatline-tertiary-agy-opt-in` 5/5, `adversarial-review-companion -f 'opt.in|agy|no_route|not planned'` 6/6; the bash lib probed directly: `deep-research-pro`, `researcher`, `google:deep-research-pro`, `gemini-2.5-pro` → agy under cli-only; `opus`, `claude-opus-5-5`, `gpt-5.5`, an unknown id → planned.

### `cheval invoke --model opus --dry-run` with no `--effort` reports `effort: high (catalog default)`; `--effort low` reports `low (caller)`; the HTTP adapter emits `output_config.effort: high` and the CLI adapter passes `--effort high` for the default; `claude-opus-5` (no default) sends nothing; the MODELINV envelope carries `effort_source`; a bad `params.default_effort` fails schema validation.
- Status: ✓ Met
- Evidence: `grimoires/loa/a2a/sprint-251/e2e/dry-run-opus.json` + `.err` (`effort: high (catalog default)`, `effort_source: catalog`, `effort_effective: high`); `.claude/adapters/cheval.py:931` (`resolve_effort`), `:983` (`_effort_on_wire`), `:1593`, `:1620` (dry-run line), `:1907`, `:2934` (MODELINV); `.claude/adapters/loa_cheval/audit/modelinv.py:499`; `.claude/data/schemas/model-config-v3.schema.json:163`; `.claude/defaults/model-config.yaml:524` (`default_effort: high`); `.claude/adapters/loa_cheval/providers/anthropic_adapter.py:203` (`wire_effort`), `claude_headless_adapter.py:189`. Run by me at 58f87195: `test_effort_catalog_default.py` (`:348` HTTP body, `:362` CLI argv, `:218`/`:299` `claude-opus-5` sends nothing, `:283` MODELINV fields), `test_effort_wire_conformance.py`, `test_effort_levels_single_source.py`; bats `cycle-124-effort-flag` 13/13 under the HOST env (the setup now unsets the two variables, `tests/unit/cycle-124-effort-flag.bats:30`), `model-config-v3-schema` 35/35 (round 1).

### `tools/ceiling-probe-live.py --transport claude-headless` is tested (command shape, OK/size/other classification, partial → no write, `operator_set` write shape) and was run once for `claude-opus-5-5` through `claude-bedrock` within the $20 budget; the record is under `grimoires/loa/reports/`; the catalog carries either the measured `operator_set` bound with `calibrated_at` and `reprobe_trigger` or the unchanged 180K with the attempt documented; no test pins the Opus 5.5 bound by literal.
- Status: ✓ Met
- Evidence: Tested: `.claude/adapters/tests/test_ceiling_probe_cli_transport.py` (argv = the adapter's builder `:238`, OK/size/other `:283`–`:418`, partial → no write `:432`, `operator_set` write shape `:523`–`:674`, throttle precedence `:1096`–`:1131`; the ledger guard is per-test at `:106`); `tools/ceiling-probe-live.py:834` (`_main_cli`), `:479`/`:504` (`i2_clamped`, `write_catalog_operator_set`), `:350` (the shared throttle rule); `.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:128` (`build_headless_argv`). Run once: `grimoires/loa/reports/2026-10-07-opus-5-5-ceiling-probe-cli.json` (5 samples, `outcome: partial`, $12.74 CLI-reported within the $20 cap, `cli_version 2.1.292`, `cli_model global.anthropic.claude-opus-5-5`). Catalog: `.claude/defaults/model-config.yaml:494` (`effective_input_ceiling: 936000`), `:501` (`probed_ceiling: 936000`), `:502`–`:513` (`ceiling_calibration`: `operator_set`, `calibrated_at`, `reprobe_trigger`, `method: probed_headless`, `transport`, `cli_version`, `cli_model`, `measured_input_tokens: 972887`, `probe_outcome: partial`, `sample_size: 5`); the partial outcome and the operator_set decision are disclosed (SDD §1.6, sprint § Task 1.5 result, reviewer.md). No literal pin: `.claude/adapters/tests/test_anthropic_catalog_floor.py:191` now reads the expectation from the catalog entry (and asserts the gate's basis is `calibrated`); the guard `test_no_literal_opus55_ceiling_pins.py:21` sweeps `(180|936)[_,]?000` with nothing allow-listed for 936; the LSP-5 fixtures use 920,000 (`tests/unit/loa-status-providers.bats:80`) so no bats pin follows the live value either. Run by me at 58f87195: the 12 sprint pytest modules plus `test_ceiling_policy`, `test_ceiling_e2e`, `test_ceiling_retry` → 456 passed, 0 errors.

### Docs present (migration addendum, CHANGELOG, example config, SDD pointer); beads updated; every touched suite green with 0 skips; REPO-MAP + sidecar + checksums regenerated; `reviewer.md` with `## AC Verification` and the live evidence (refusal, dry-run line, `/loa` line, probe record).
- Status: ✓ Met
- Evidence: Docs: `docs/migration/v2.0-model-generation-floor.md:268` (effort default), `:276` (cycle-127 addendum), `:345` (the throttle rule); `CHANGELOG.md:12`–`:15` (four cycle-127 bullets; the K8 sentence at `:15` names the shared throttle rule); `.loa.config.yaml.example:751` (`agy_opt_in: false` with the rationale); `grimoires/loa/sdd.md:48`–`:74` (D-1.5…D-3.12, §1.6), `:89` (§5: `effort_source` incl. `extra`, `effort_effective`), `:93` (§6: resolve-time WARN, the headless throttle rule, the partial flag); `grimoires/loa/sprint.md:62` (the superseded `reprobe_trigger` sentence marked), `:83` (the r251-3 round section); `grimoires/loa/prd.md:142` (SC-1 names the `INVALID_CONFIG` refusal); the cycle-126 SDD D-4.1 amendment carries the pointer at `grimoires/loa/archive/cycle-126-full-size/sdd.md:89`. Beads (read-only): `bd-9qe2` closed; `bd-ugmi` DECIDED comment; `bd-c2rd`, `bd-y49y`, `bd-n6lk`, `bd-rbkz` open and present in both `.beads/beads.db` and `.beads/issues.jsonl` (note: `.beads/` and `grimoires/loa/archive/` are gitignored by this repo, `.gitignore:273` / `:185`, so both live on this host only — the ledger is the tracked record, by design). Suites: every bats suite I ran is 0 skips (`agy-gate-conformance` 12, `run-preflight` 20, `cycle-124-effort-flag` 13, `loa-status-providers` 9, `flatline-tertiary-agy-opt-in` 5, companion filtered 6; round 1: `model-config-v3-schema` 35, `gen-bb-registry-codegen` 40); pytest 456/456 for the sprint's modules. REPO-MAP + `.checksum` + `.claude/checksums.json` regenerated in 58f87195 (`git diff --stat d12bdfab..58f87195`). `reviewer.md` carries `## AC Verification` with the live evidence and an r251-3 section (`grimoires/loa/a2a/sprint-251/reviewer.md:101`); its AC 1 heading at `:41` still carries the pre-r251-3 wording — Observation 1, to sync before `/audit-sprint`.

---

## Security Checklist

- [x] No hardcoded secrets or credentials — unchanged from round 1; the delta adds no credential reads (the catalog-provider lookup reads the System catalog and the project config's `providers`/`aliases` only)
- [x] Input validation and sanitization present — the opt-in is still the YAML boolean scalar `true` only on all three readers; `agy_catalog_provider` reads an associative array by key (no arithmetic evaluation, no `eval`) in a subshell; `provider_of` still admits only catalog-shaped ids to yq
- [x] Authentication/authorization correct — project-config-only read, no environment override, fail-closed on an unreadable config, PATH-lookup-only availability WARN (tests unchanged and green)
- [x] No SQL/XSS injection vulnerabilities — n/a
- [x] Dependencies secure (no known CVEs) — no new dependency
- [x] Error messages don't leak sensitive data — the throttle/size diagnostics are the provider's text passed through the existing redaction (`cheval.py:2214`); the new remedy string carries a model id only

---

## Code Quality Summary

**Strengths:**
- The fix for the HIGH removed a second classifier instead of patching the first: one predicate, one table test, one probe-vs-adapter conformance test over 18 strings including the stale-stderr case.
- The routing rule is now the same thing in three languages (provider-based under cli-only), and the conformance suite pins Python against bash row by row, including the non-`gemini*` Google ids.
- The probe suite's ledger guard became hermetic instead of being deleted; the effort-flag suite became hermetic to the operator's Bedrock credential.
- Each round-1 observation was either fixed with a test or deferred to a named bead; nothing was argued away.

**Areas for Improvement:**
- Keep `reviewer.md`'s AC headings in lockstep with `sprint.md` when an AC is amended (Observation 1).
- AGC-6 deserves one diagnostic capture rather than a longer timeout (Observation 2).

**Complexity review:** the delta's new functions are small (`_calibrate_hint` 17 lines, `catalog_provider_of` 11, `_catalog_provider_maps` ~35, `agy_catalog_provider` 14, `is_throttle_message` 6); the round-1 `_main_cli` item is tracked by `bd-rbkz`. Lean already. Ship.

**Fast-gate parity:** the lead records adapters pytest 2910 passed / 6 skipped and the lints clean after the round; the Bridgebuilder sources did not change in r251-3 (no rebuild needed; `dist/` untouched in the delta). CI runs no ruff/mypy on the adapters.

**Documentation verification:** no `documentation-coherence-*.md` report for this sprint; verified by hand — CHANGELOG, the migration addendum, SDD §5/§6 and the sprint round section name the shared throttle rule and the provider-based routing; no new command or skill; the cycle-126 SDD pointer is present.

**Subagent reports:** none under `grimoires/loa/a2a/subagent-reports/` for sprint-251; reviewed manually.

---

## What this review ran (serial, no model calls, at 58f87195)

- adapters pytest, 15 modules (the 12 sprint modules + `test_ceiling_policy`, `test_ceiling_e2e`, `test_ceiling_retry`) → **456 passed**, 0 errors.
- bats: `agy-gate-conformance` 11/12 then 12/12 in two full-file runs (AGC-6 alone 1/1 in 0.9 s; AGC-5+AGC-6 2/2); `run-preflight` 20/20; `cycle-124-effort-flag` 13/13 under the host env; `loa-status-providers` 9/9; `flatline-tertiary-agy-opt-in` 5/5; `adversarial-review-companion -f 'opt.in|agy|no_route|not planned'` 6/6.
- A read-only Python probe of `ClaudeHeadlessAdapter._raise_for_error` on fifteen throttle/size strings; the bash lib's `agy_catalog_provider` / `routes_to_agy` on eight ids; `bash -n` on the lib and `run-preflight.sh`; a read-only `sqlite3` query of `.beads/beads.db`; `validate-ac-verification.sh` on `reviewer.md` (fails — Observation 1).

**Not verified by me:** Bridgebuilder vitest and `dist/` freshness (unchanged in the delta; the lead's 797/798 recorded), `gen-bb-registry-codegen.bats` and `model-config-v3-schema.bats` (unchanged since my round-1 runs, 40/40 and 35/35), the live probe run itself; the guardrails pre-execution and trajectory steps (they write under `grimoires/loa/a2a/trajectory/`, outside this review's write allowance).

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate": "review", "verdict": "APPROVED", "counts": {"critical": 0, "high": 0, "medium": 1, "low": 3}, "excluded": 0, "sprint_id": "sprint-1", "ts": "2026-10-07T15:56:15Z"} -->
