# Sprint 251 — review dissent run 2: triage

- **Run.** Two-voice cross-model dissent on `059e26be` (the r251-1 fix round; base `8ad37c55`), 17 chunks (a2-gatepy … q2-docs), voices codex-headless gpt-5.5-pro + claude-headless (Bedrock); every chunk two-voice at 2026-10-07T13:39:10Z; merged envelope `adversarial-review-run2-merged.json` (= `adversarial-review.json`), 76 findings: **10 BLOCKING, 66 ADVISORY**, 0 schema-rejected. verdict_quality: 2/2 voices, chain_health ok, status APPROVED (the consensus outcome of the merge, before triage).
- **Verification.** Two Opus 5.5 read-only verifiers at 059e26be (`review-dissent-run-2-verifier-C.md` n1–38, `-D.md` n39–76; verifier D also answered the lead's extra probe on the headless pre-flight class). Their verdicts are the Ruling column.
- **BLOCKING outcome.** 10 claimed → 0 stand as blocking: n6/n7/n39/n40 chunker mislabels (new-file hunks under the previous file's header — the chunker was rewritten to keep per-file headers before the audit run), n1/n50/n57 refuted by probe, n12/n13 REAL at MEDIUM (preflight P3 false PASS for an agy-routed voice with the opt-in on), n69 a doc inconsistency the lead introduced in r251-1's CHANGELOG (fixed).
- **Fix round r251-2.** Two Opus 5.5 implementers in disposable worktrees — **K** core (`r251-2-core.patch`: K1–K9) and **Q** probe (`r251-2-probe.patch`: Q1–Q7); docs by the lead. This is the last review-dissent round for the sprint (≤ 2 runs per gate); the delta is covered by the Fable review and the full-range audit dissent.

## Rulings

| ID | Sev | Voice | Chunk | Anchor | Ruling | Action |
|---|---|---|---|---|---|---|
| n1 | BLOCKING | gpt-5.5-pro | a2-gatepy | `.claude/adapters/cheval.py:_effort_on_wire` | REFUTED | `ProviderAdapter.wire_effort` (base.py) defaults to None; all 10 registered adapters subclass it; `adapter_class_for_type` None is guarded. |
| n2 | ADVISORY | claude-headless | a2-gatepy | `.claude/adapters/cheval.py:cmd_invoke` | REAL — MEDIUM | K2: an agy-alone refusal was in both `models_requested` and `models_not_planned` and counted as a planned-dropped voice; now `models_failed` (INVALID_CONFIG / opt_in_required) only, `voices_dropped` reason named. |
| n3 | ADVISORY | claude-headless | a2-gatepy | `.claude/adapters/cheval.py:_plan_around_agy` | REFUTED | `ResolvedChain` has exactly the four fields the rebuild passes. |
| n4 | ADVISORY | claude-headless | a2-gatepy | `.claude/adapters/cheval.py:resolve_effort` | REFUTED | codex's own allowed set excludes `minimal`; it never reaches the wire; `effort_effective: None` is accurate. |
| n5 | ADVISORY | claude-headless | a2-gatepy | `.claude/adapters/cheval.py:cmd_invoke` | REFUTED | effort/dry-run resolve against the binding's resolved entry by design (D-2.2); every `_chain` consumer runs after `_plan_around_agy`. |
| n6 | BLOCKING | gpt-5.5-pro | b2-gatepy | `.claude/adapters/cheval.py:@@ -0,0 +1,232 @@` | REFUTED (mislabel) | the 232-line new-file hunk is `tests/test_agy_chain_walk_opt_in.py`; cheval.py's real diff carries the production hunks. |
| n7 | BLOCKING | claude-headless | b2-gatepy | `.claude/adapters/cheval.py:@@ -0,0 +1,232 @@` | REFUTED (mislabel) | as n6; every claimed-missing hunk is in the cheval.py / modelinv.py diff. |
| n8 | ADVISORY | claude-headless | b2-gatepy | `.claude/adapters/cheval.py:test_direct_gemini_headless_still` | REAL — LOW | K2: agy-alone tests assert `seen`, the requested/failed/not_planned relation and the dropped reason. |
| n9 | ADVISORY | claude-headless | c2-gatesh | `.claude/scripts/adversarial-review.sh:_adv_agy_filter_chain` | REAL — LOW | K4: lib-missing path keeps a minimal inline name filter (fail closed) and the comment is corrected. |
| n10 | ADVISORY | claude-headless | c2-gatesh | `.claude/scripts/lib/agy-gate-lib.sh:agy_opted_in` | REAL (latent) — LOW | K5: yq flavour selects the fallback, not output shape. |
| n11 | ADVISORY | claude-headless | c2-gatesh | `.claude/scripts/run-preflight.sh:P3 voices` | REAL — MEDIUM (dup of 12/13) | K3. |
| n12 | BLOCKING | gpt-5.5-pro | d2-gatesh | `.claude/scripts/adversarial-review.sh:@@ -176,32 +175,44 @@ ` | REAL — MEDIUM | K3: P3 judged an agy-routed voice (opt-in on, cli-only) by its Google credential → false PASS without agy; now `routes_to_agy → cli=agy`; PF-AGY cases. |
| n13 | BLOCKING | claude-headless | d2-gatesh | `.claude/scripts/adversarial-review.sh:@@ -176,32 +175,44 @@ ` | REAL — MEDIUM | K3 (also the `gemini-headless:<m>` form). |
| n14 | ADVISORY | claude-headless | d2-gatesh | `tests/unit/agy-gate-conformance.bats:AGC-7 (case "$w" in boo` | REAL — LOW | K6: AGC-7 bool branch / AGC-1 `!` vacuous under bats set -e. |
| n15 | ADVISORY | claude-headless | d2-gatesh | `tests/unit/agy-gate-conformance.bats:AGC-9 (and the loa-stat` | REAL — LOW | K6: AGC-9/AGC-8 PATH guard consistent with the runs; specific WARN greps. |
| n16 | ADVISORY | claude-headless | d2-gatesh | `.claude/adapters/loa_cheval/config/loader.py:agy_opt_in_enab` | REAL — MEDIUM | K1: bash accepted only `true`, Python also `yes/on/True/TRUE` — split-brain on the security route; one strict rule (source text exactly `true`) on both sides, rows added to AGC-7 and the Python tests. |
| n17 | ADVISORY | claude-headless | e2-gatesh | `.claude/scripts/adversarial-review.sh:@@ -75,6 +77,11 @@ _cf` | REAL — LOW | K6: split the `&&` chain in flatline-tertiary-agy-opt-in.bats:84. |
| n18 | ADVISORY | claude-headless | e2-gatesh | `.claude/scripts/adversarial-review.sh` | REFUTED (mislabel) | the hunks are `tests/unit/flatline-tertiary-agy-opt-in.bats`. |
| n19 | ADVISORY | claude-headless | f2-bb | `.claude/skills/bridgebuilder-review/resources/__tests__/mult` | REAL — LOW | K7a: behavioural test replaces the `.length === 2` guard. |
| n20 | ADVISORY | claude-headless | f2-bb | `.claude/skills/bridgebuilder-review/resources/__tests__/mult` | REAL — LOW | K7b: `readError` is fail-closed for google voices; mode pinned. |
| n21 | ADVISORY | claude-headless | f2-bb | `.claude/skills/bridgebuilder-review/resources/__tests__/prog` | REFUTED | `TOKEN_BUDGETS` is imported at line 13 of the test. |
| n22 | ADVISORY | claude-headless | g2-bb | `.claude/skills/bridgebuilder-review/resources/core/multi-mod` | REAL — LOW | K7c: message built from `readError`; one zero-adapters message listing notPlanned and missing. |
| n23 | ADVISORY | claude-headless | g2-bb | `.claude/skills/bridgebuilder-review/resources/core/multi-mod` | REAL — LOW | K7d: the `readError` warn names the voices. |
| n24 | ADVISORY | claude-headless | g2-bb | `.claude/skills/bridgebuilder-review/scripts/gen-bb-registry.` | DECLINED | one documented single-tokenizer factor and one calibrated entry; per-entry `tokenizer_ratio` is a refinement → noted on bd-c2rd. |
| n25 | ADVISORY | claude-headless | g2-bb | `.claude/skills/bridgebuilder-review/scripts/gen-bb-registry.` | REAL — LOW | K7e: `${MEASURED_TO_ESTIMATE_SAFETY}` in the template. |
| n26 | ADVISORY | claude-headless | g2-bb | `.claude/skills/bridgebuilder-review/resources/main.ts:main` | REAL — LOW | K7f: `readError` and `typeWarning` printed once at startup. |
| n27 | ADVISORY | claude-headless | h2-ceil | `.claude/adapters/loa_cheval/providers/claude_headless_adapte` | DECLINED | the resolvers read only `request.*` / `model_config.extra`; the `cls.__new__` hazard is hypothetical. |
| n28 | ADVISORY | claude-headless | h2-ceil | `.claude/adapters/loa_cheval/providers/base.py:ProviderAdapte` | REFUTED | `test_effort_wire_conformance.py` iterates every catalog model through its real adapter and fails on an adapter without a reader. |
| n29 | ADVISORY | claude-headless | h2-ceil | `.claude/adapters/loa_cheval/routing/ceiling.py:input_bound` | REFUTED | `record_observed` is unconditional on `ProviderContextLimitError`; no calibrated skip. |
| n30 | ADVISORY | claude-headless | h2-ceil | `.claude/adapters/loa_cheval/routing/ceiling.py:GateOutcome.a` | REFUTED (pre-existing drift noted) | `capability_evaluation` is closed but omits every cycle-126 gate key already; not enforced at emit → bead bd-y49y. |
| n31 | ADVISORY | claude-headless | h2-ceil | `.claude/adapters/tests/test_anthropic_catalog_floor.py:test_` | REFUTED | `tests/conftest.py::_isolate_ledgers` isolates the observed store per test. |
| n32 | ADVISORY | claude-headless | h2-ceil | `.claude/adapters/loa_cheval/routing/ceiling.py:parse_context` | DECLINED | only the HTTP adapter and the probe call `parse_context_limit`; a CLI `limit` would be I1-clamped anyway. |
| n33 | ADVISORY | claude-headless | i2-ceil | `.claude/adapters/loa_cheval/providers/__init__.py:@@ -141,14` | REFUTED (mislabel) | the hunks are `tests/test_anthropic_catalog_floor.py`; `providers/__init__.py` changed by +8. |
| n34 | ADVISORY | claude-headless | i2-ceil | `.claude/adapters/tests/test_ceiling_calibrated_count.py:_cal` | REFUTED | `is_calibrated` is `bool(calibrated_at)`; staleness feeds only `ceiling_stale`. |
| n35 | ADVISORY | claude-headless | i2-ceil | `.claude/adapters/loa_cheval/providers/__init__.py:test_legac` | REAL — LOW | K9: one concrete `_lookup_max_input_tokens` pin. |
| n36 | ADVISORY | claude-headless | i2-ceil | `.claude/adapters/loa_cheval/providers/__init__.py:test_a_for` | REAL (1, 3) — LOW | K9: `method == probed_headless` required for a non-api transport; ≥ 1 foreign entry asserted. |
| n37 | ADVISORY | claude-headless | i2-ceil | `.claude/adapters/tests/test_ceiling_calibrated_count.py:test` | DECLINED | documented trade-off (C7): no count → `warn`, one upload at risk; the gate serves the HTTP route only. |
| n38 | ADVISORY | claude-headless | i2-ceil | `.claude/adapters/tests/test_ceiling_calibration_transport.py` | DECLINED | the live entry's transport is `claude-headless`, so the test runs; an `http` spelling fails loudly. |
| n39 | BLOCKING | gpt-5.5-pro | j2-ceil | `.claude/adapters/loa_cheval/providers/__init__.py:@@ -393,3 ` | REFUTED (mislabel) | the hunk is `tests/test_effort_catalog_default.py`. |
| n40 | BLOCKING | claude-headless | j2-ceil | `.claude/adapters/loa_cheval/providers/__init__.py:@@ -393,3 ` | REFUTED (mislabel); NIT | K9: `adapter_class_for_type` added to `__all__`. |
| n41 | ADVISORY | claude-headless | j2-ceil | `.claude/adapters/tests/test_effort_wire_conformance.py:_http` | REAL (narrow) — LOW | K9: `_http_body` fails on a missing body; the interactions-API body is captured or excluded with a reason. |
| n42 | ADVISORY | claude-headless | j2-ceil | `.claude/adapters/tests/test_effort_wire_conformance.py:test_` | DECLINED | codex has always read `extra.reasoning_effort`; `wire_effort` now reports what it sends — FR-2 is scoped to Anthropic effort. |
| n43 | ADVISORY | claude-headless | j2-ceil | `.claude/defaults/model-config.yaml:claude-opus-5-5.ceiling_c` | REFUTED | nothing outside the tool reads `sample_size`; provenance is `source` + `probe_outcome`. |
| n44 | ADVISORY | claude-headless | k2-probe | `.claude/adapters/tests/test_ceiling_probe_cli_transport.py:t` | DECLINED | `huge` is an output-cap overflow and is charged the estimate; provider transients at 0 is the documented table. |
| n45 | ADVISORY | claude-headless | k2-probe | `.claude/adapters/tests/test_ceiling_probe_cli_transport.py:F` | REFUTED | all four fake knobs are used. |
| n46 | ADVISORY | claude-headless | k2-probe | `.claude/adapters/tests/test_ceiling_probe_cli_transport.py:_` | REAL — NIT | Q6: `monkeypatch.syspath_prepend`. |
| n47 | ADVISORY | claude-headless | l2-probe | `.claude/adapters/tests/test_ceiling_probe_cli_transport.py:t` | REFUTED | the module-scoped autouse `_no_real_cli` sets the sentinel unconditionally. |
| n48 | ADVISORY | claude-headless | l2-probe | `tools/ceiling-probe-live.py:_run_capped` | REFUTED | `run_subprocess_pgkill` catches BaseException and SIGKILLs the group on ^C too. |
| n49 | ADVISORY | claude-headless | l2-probe | `.claude/adapters/tests/test_ceiling_probe_cli_transport.py:t` | REAL — NIT | Q6: assert the pidfile exists; wait cap ~5 s. |
| n50 | BLOCKING | gpt-5.5-pro | m2-probe | `.claude/adapters/tests/test_ceiling_probe_cli_transport.py:m` | REFUTED | `args.tier = args.tier or "unverified"` runs before any api use; probe wrote `account_limits.tier: unverified`. |
| n51 | ADVISORY | claude-headless | m2-probe | `.claude/adapters/tests/test_ceiling_probe_cli_transport.py:_` | REAL — MEDIUM | Q1: the 429 lookahead rejected "429." so `API Error: 429. Too many tokens` was a clean-eligible context bracket; precedence read the whole stderr. |
| n52 | ADVISORY | claude-headless | m2-probe | `loa_cheval/providers/base.py:run_subprocess_pgkill` | REFUTED | `run_subprocess_pgkill` encodes the string input; the step catches exactly its two exceptions. |
| n53 | ADVISORY | claude-headless | m2-probe | `.claude/adapters/tests/test_ceiling_probe_cli_transport.py:m` | REFUTED | as n50. |
| n54 | ADVISORY | claude-headless | m2-probe | `.claude/adapters/tests/test_ceiling_probe_cli_transport.py:w` | REFUTED | `probe_outcome`/`sample_size` are passed at the one call site; end-to-end `--write-catalog` tests exist. |
| n55 | ADVISORY | claude-headless | m2-probe | `.claude/adapters/tests/test_ceiling_probe_cli_transport.py:@` | DECLINED | `waited ≥ 140` with four attempts; the record's reasons name a token_limit bracket → partial. |
| n56 | ADVISORY | claude-headless | m2-probe | `.claude/adapters/tests/test_ceiling_probe_cli_transport.py` | REFUTED (mislabel) | the test file really changed (+570). |
| n57 | BLOCKING | gpt-5.5-pro | n2-probe | `.claude/adapters/tests/test_ceiling_probe_cli_transport.py:_` | REFUTED | the dry-run opens read-only and discards the text; `ceiling=1` cannot fail `i2_clamped`. |
| n58 | ADVISORY | claude-headless | n2-probe | `tools/ceiling-probe-live.py:_main_cli` | REAL — LOW | Q2: writability checked before spend. |
| n59 | ADVISORY | claude-headless | n2-probe | `tools/ceiling-probe-live.py:_main_cli` | REAL — LOW | Q3: `written_*` set only after the write lands. |
| n60 | ADVISORY | claude-headless | n2-probe | `tools/ceiling-probe-live.py:_main_cli` | REAL — NIT | Q4: `setdefault` / `write_skipped`. |
| n61 | ADVISORY | claude-headless | n2-probe | `tools/ceiling-probe-live.py:_main_cli` | DECLINED | documented in the docstring and --help. |
| n62 | ADVISORY | claude-headless | n2-probe | `tools/ceiling-probe-live.py:_main_cli` | REAL — LOW | Q5: traceback printed for non-interrupt exceptions. |
| n63 | ADVISORY | claude-headless | n2-probe | `tools/ceiling-probe-live.py:_persisted_transient` | REFUTED | a shorter retry-after is ignored (`max(schedule, hint)`); `waited` ≥ 140 or = 180. |
| n64 | ADVISORY | claude-headless | o2-docs | `CHANGELOG.md:@@ -9,10 +9,10 @@ ## [Unreleased]` | DOC | lead: one current BB value (508,000; 916,000 as history). |
| n65 | ADVISORY | claude-headless | o2-docs | `CHANGELOG.md:@@ -9,10 +9,10 @@ ## [Unreleased]` | DOC + REAL (pre-existing gap) | lead: count_tokens sentence scoped to the HTTP adapter; K8: the headless adapter mapped the CLI pre-flight rejection to `ProviderUnavailableError` (walked, breaker-counted) → `ProviderContextLimitError`. |
| n66 | ADVISORY | claude-headless | o2-docs | `CHANGELOG.md:@@ -9,10 +9,10 @@ ## [Unreleased]` | REFUTED | `claude-opus-5-5` carries no `pricing.long_context`; the lead's draft sentence about the premium tier was removed. |
| n67 | ADVISORY | claude-headless | p2-docs | `CHANGELOG.md:## [Unreleased]` | REFUTED (chunker artefact) | the part carried a context-only CHANGELOG hunk; fixed in the audit chunker (per-file headers, v7). |
| n68 | ADVISORY | claude-headless | p2-docs | `.claude/defaults/model-config.yaml:claude-opus-5-5` | DECLINED | D-3.10 lead decision with the tighten-only safeguard and the explicit partial flag. |
| n69 | BLOCKING | gpt-5.5-pro | q2-docs | `CHANGELOG.md:@@ -284,20 +284,37 @@ ### Cycle-127 addendum — ` | DOC — MEDIUM | lead: CHANGELOG + addendum now state the two-case rule (no key clause). |
| n70 | ADVISORY | claude-headless | q2-docs | `CHANGELOG.md:@@ -284,20 +284,37 @@` | DOC | as n69. |
| n71 | ADVISORY | claude-headless | q2-docs | `CHANGELOG.md:@@ -307,8 +324,26 @@` | DOC | lead: stale 916,000 removed; formula (bound − 20,000) ÷ 1.8 = 508,000; 1.4× cheval / 1.8× chars/4-class attribution. |
| n72 | ADVISORY | claude-headless | q2-docs | `grimoires/loa/prd.md:@@ -109,7 +109,7 @@` | DOC | lead: PRD FR-3.5 and SDD D-3.8 mention `--write-partial-as-operator-set`; sprint MVP line annotated. |
| n73 | ADVISORY | claude-headless | q2-docs | `CHANGELOG.md:@@ -284,20 +284,37 @@` | DOC | lead: effort carried to every hop as existing behaviour; no 'declares no default' qualifier. |
| n74 | ADVISORY | claude-headless | q2-docs | `grimoires/loa/sdd.md:@@ -56,6 +56,17 @@` | DOC | lead: D-1.8 / CHANGELOG / addendum: only a dispatch whose sole hop is agy-routed refuses (direct `gemini-headless`, or a Google voice under effective `cli-only`). |
| n75 | ADVISORY | claude-headless | q2-docs | `CHANGELOG.md:@@ -307,8 +324,26 @@` | DOC | as n65. |
| n76 | ADVISORY | claude-headless | q2-docs | `grimoires/loa/sdd.md:@@ -56,6 +56,17 @@` | REFUTED | `_outcome_reasons` makes a non-context-limit bracket `partial`; never clean. |

**Counts.** DECLINED 10, DOC 9, REAL 27, REFUTED 30.

## Round r251-2 outcome

Committed as `d12bdfab` (pushed). Two Opus 5.5 implementers in disposable worktrees (`wt-127-6` core, `wt-127-7` probe); both patches applied cleanly; the lead regenerated the model artefacts, REPO-MAP and checksums, rebuilt the Bridgebuilder dist, ran the suites and the lints, and wrote the docs.

| Item | Outcome |
|---|---|
| K1 (n16) | Both readers accept only the YAML scalar whose source text is exactly `true` (Python locates the node and checks tag + text; bash keeps the typed go-yq form); `yes`/`on`/`True`/`TRUE`/`1`/`"true"` stay off with the one-shot type WARN; AGC-7 rows and Python cases for every spelling on both sides. |
| K2 (n2, n8) | An agy-alone refusal: `models_requested` + `models_failed` (`INVALID_CONFIG`, `failure_class: opt_in_required`), never `models_not_planned`; `voices_dropped` reason `opt_in_required`; docstrings corrected; the agy-alone tests assert `seen`, the three-list relation and the reason; the mixed-chain test asserts `models_not_planned` only. |
| K3 (n11–13) | `run-preflight.sh` P3: `routes_to_agy "$m" "$p3_mode" && cli=agy`; PF-AGY: opt-in on + cli-only + key + no agy → no usable voice; fake agy → `(cli agy)`; `gemini-headless:any`. |
| K4 (n9) | Lib-missing path keeps the inline name filter (fail closed), comment corrected, no-op WARN call dropped; companion bats case. |
| K5 (n10) | yq flavour (mikefarah) selects the fallback; shim test. |
| K6 (n14, n15, n17) | Vacuous `&&` / `!` assertions rewritten with `|| return 1`; one `rp` PATH for guard and runs; specific WARN greps; the flatline-tertiary chain split. |
| K7 (n19, n20, n22, n23, n25, n26) | Behavioural gate test; `readError` fail-closed for google voices with the mode pinned; messages built from `readError` / one zero-adapters message; the strict warn names the voices; `${MEASURED_TO_ESTIMATE_SAFETY}` in the header template; `main.ts` prints `readError` and `typeWarning` once at startup. |
| K8 (n65) | `ClaudeHeadlessAdapter._raise_for_error`: the CLI's own pre-flight rejection → `ProviderContextLimitError` (not walked, no breaker increment, no observation for a CLI hop); `test_claude_headless_context_limit.py` (unit + cheval-level with a fake CLI). |
| K9 (n35, n36, n40, n41) | Concrete `_lookup_max_input_tokens` pin; provenance guard requires `method == probed_headless` for a foreign transport and ≥ 1 foreign entry; `adapter_class_for_type` in `__all__`; `_http_body` fails on a missing body. |
| Q1 (n51) | `_THROTTLE` 429 lookahead `(?!\d|[,.]\d)`; the throttle verdict reads result + api_status, stderr only when there is no result; both probes pinned. |
| Q2–Q5 (n58–n60, n62) | Writability (`os.access` on directory and file) checked before spend → exit 2; the catalog lands before the record is serialized and `written_*` is claimed only after; `write_skipped` separate from `error`; `traceback.print_exc()` for non-interrupt exceptions. |
| Q6, Q7 (n46, n49, n63) | `monkeypatch.syspath_prepend`; pidfile assertion with a 5 s cap; import-time `sum(_TPM_BACKOFF_S) >= _TPM_WINDOW_S`. |
| Docs | CHANGELOG, addendum, SDD D-1.8/D-1.9/D-3.8/D-3.10b/D-3.12, PRD FR-3.5, sprint round section. |

**Suites, real tree, serial (ok / not ok / skip):** adapters pytest 2842 / 0 / 6 (279 subtests); bats agy-gate-conformance 11/1 in the batch (AGC-6, the 120 s `loa-status` call, failed under the concurrent Bridgebuilder build and passed alone twice — a load flake, same class as LSP-1), run-preflight 19/0, flatline-tertiary-agy-opt-in 5/0, adversarial-review-companion (filtered) 47/0, loa-status-providers 9/0, gen-bb-registry-codegen 40/0; Bridgebuilder 797/798 (`persona.test.ts` = KF-036); lints clean; `regen-model-artifacts --check` drift-free, dist fresh; `regen-checksums --check` changed=0.

**Not done (by ruling):** no third review dissent run (≤ 2 per gate); the r251-2 delta is covered by the Fable review and the full-range audit dissent. Beads: bd-y49y, bd-c2rd.
