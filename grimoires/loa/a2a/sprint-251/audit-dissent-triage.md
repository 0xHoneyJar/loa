# Sprint 251 — audit dissent: triage

## Run 1 (full sprint range `6f6cc8a6..d12bdfab`, 22 chunks a3…u3, two-voice at 2026-10-07T15:42:04Z)

- **Envelope.** `adversarial-audit-run1-merged.json` (the merge of the 22 chunk envelopes; `adversarial-audit.json` now carries run 2): 60 findings — **0 CRITICAL, 0 HIGH, 18 MEDIUM, 42 LOW**; 0 schema-rejected; verdict_quality 2/2 voices, chain_health ok, status APPROVED before triage. gpt-5.5-pro contributed 2 of the 60 (n37, n51).
- **Verification.** Two Opus 5.5 read-only verifiers at HEAD `58f87195` (`audit-dissent-run-1-verifier-E.md` n1–30, `-F.md` n31–60), each re-running the load-bearing probes (planted-config walk, env-exported include guard, YAML alias/merge-key/odd-tag spellings, the newline injection into the catalog, the merge-gate arithmetic under readError). The Ruling column is theirs.
- **MEDIUM outcome.** 18 claimed → 1 stands as MEDIUM: n22 (Bridgebuilder's merge gate fails open under a config read error). Security-relevant LOWs: n6 (cwd-walk opt-in read — a planted `/tmp/.loa.config.yaml` opts in), n52 (newline injection into the tracked catalog through `--host-route` / `--cli-model`), n5/n17-new (one strict tag/alias rule across the three readers), n10/n15 (the include guard and the unguarded source). The rest: refuted by probe, declined by recorded decision (D-3.10/C1, C7, the agy argv design), or pre-existing.
- **Fix round r251-4.** Two Opus 5.5 implementers — **S** core (`r251-4-core.patch`, S1–S9) and **T** probe (`r251-4-probe.patch`, T1–T7); docs by the lead. No third audit dissent run (≤ 2 per gate): the r251-4 delta is covered by the Fable audit.

| ID | Sev | Voice | Chunk | Anchor | Ruling | Action |
|---|---|---|---|---|---|---|
| n1 | MEDIUM | claude-headless | a3-gatepy | `cmd_invoke` | REFUTED (diff); pre-existing LOW | `str(_e)` sites pre-exist (9 in the base); the new opt_in_required emit carries the constant MESSAGE; MODELINV redacts every field. Optional: `sanitize_provider_error_message` at the two new sites. |
| n2 | LOW | claude-headless | a3-gatepy | `_plan_around_agy` | DOC | S8: reword the `models_requested` comment (requested ∪ not_planned = the full chain). |
| n3 | MEDIUM | claude-headless | b3-gatepy | `agy_opt_in_enabled` | DECLINED (trust model) | the project tree is the trust root; a PR-head checkout that supplies the config supplies the code too; the residual is n6. |
| n4 | LOW | claude-headless | b3-gatepy | `_agy_opt_in_raw_yq` | REAL (doc) — LOW | S8: `warn_agy_available_once` docstring (the yq path spawns). |
| n5 | LOW | claude-headless | b3-gatepy | `_agy_opt_in_raw` | REAL — LOW | S3: require the exact full bool tag (`!<x:bool> true` opted Python in while bash/TS read off). |
| n6 | MEDIUM | claude-headless | c3-gatepy | `test_the_project_root_defaults_to_the_cwd_walk` | REAL — LOW (security-relevant) | S2: cheval read the opt-in from a cwd-ancestor config (a planted `/tmp/.loa.config.yaml` opts in under /tmp); anchor the read to cheval's install root and refuse a foreign-owned or writable config. |
| n7 | LOW | claude-headless | c3-gatepy | `test_k1_the_strict_rule_holds_without_pyyaml` | DECLINED — INFO | PATH is the trust root; python-yq lacks `eval` → ConfigError → off (fail closed). |
| n8 | LOW | claude-headless | c3-gatepy | `test_off_refuses_before_any_discovery_or_spawn` | REFUTED | the only spawn is inside `complete()` after the gate; `validate_config`/`health_check` gated; `_build_command` does not spawn. |
| n9 | MEDIUM | claude-headless | c3b-gatepy | `loa_cheval/providers/agy_headless_adapter.py (agy -p <p` | DECLINED (documented, pre-existing) | argv exposure predates the sprint, documented in the example config, WARNs once; default off; stdin transport awaits bd-ugmi. |
| n10 | MEDIUM | claude-headless | d3-gatesh | `[[ -n "${_LOA_AGY_GATE_LIB_LOADED:-}" ]] && return 0` | REAL — LOW | S4: the include guard read `_LOA_AGY_GATE_LIB_LOADED` from the environment (exported → functions undefined, exit 127); `declare -F` guard. |
| n11 | LOW | claude-headless | d3-gatesh | `_anthropic_ceiling_json` | REAL (hardening) — LOW | S8: `strenv` for `$model` in loa-status yq. |
| n12 | LOW | claude-headless | d3-gatesh | `_providers_config_file` | DECLINED — INFO | the seam honours env only; env control is PATH control; display-only. |
| n13 | LOW | claude-headless | d3-gatesh | `_adv_agy_lib` | REFUTED | `PROJECT_ROOT` is set unconditionally from `$SCRIPT_DIR`. |
| n14 | LOW | claude-headless | d3-gatesh | `_tertiary_routes_to_agy` | REAL (narrow) — LOW | S8 (if cheap): bash resolves the hop through project aliases before `routes_to_agy`; cheval refuses/plans around regardless. |
| n15 | LOW | claude-headless | e3-gatesh | `source "$SCRIPT_DIR/lib/agy-gate-lib.sh"` | REAL — LOW | S4: run-preflight sources the lib unguarded under `set -uo pipefail` → fail closed. |
| n16 | LOW | claude-headless | e3-gatesh | `for m in $models $chain; do` | DECLINED (pre-existing) — INFO | operator-owned config; optional `set -f`. |
| n17 | MEDIUM | claude-headless | f3-gatesh | `tests/unit/run-preflight.bats:@test "PF-AGY-4 (review r` | REFUTED at HEAD + NEW | truthy spellings covered by r251-2; NEW divergence: a YAML alias (`*t`) opts Python in, a merge key opts TS in → S3 reads both as off in every reader, AGC rows. |
| n18 | LOW | claude-headless | f3-gatesh | `tests/unit/flatline-tertiary-agy-opt-in.bats:@test "FTA` | DECLINED — INFO | fail-closed on malformed YAML verified by probe; only tests missing. |
| n19 | MEDIUM | claude-headless | g3-bb | `assert.equal(isAgyRouted("google", "gemini-3.1-pro-prev` | REFUTED | prefer-cli: `_plan_around_agy` keeps the HTTP hops and lists gemini-headless not planned; cli-only is agy-alone → refused; BB `isAgyRouted(prefer-cli)=false` is correct. |
| n20 | LOW | claude-headless | g3-bb | `assert.equal(loaConfigPathFor(undefined), ".loa.config.` | DECLINED — INFO | repoRoot from CLI / env / git toplevel; BB only plans. |
| n21 | LOW | claude-headless | g3-bb | `assert.ok(!result.reviewVerdict.mergeBlocked, "a not-pl` | REAL — LOW | S8: the posted Verdict Quality line names not-planned voices. |
| n22 | MEDIUM | claude-headless | h3-bb | `if (modelResults.length !== multiConfig.models.length -` | REAL — MEDIUM | S1: under `readError` every Google voice (HTTP ones too) is notPlanned and the merge check subtracts them → a host fault shrinks the quorum; now `mergeBlocked = true` under readError, strict throws, test. |
| n23 | LOW | claude-headless | h3-bb | `export function loaConfigPathFor(repoRoot?: string): st` | DECLINED — INFO | as n20. |
| n24 | LOW | claude-headless | h3-bb | `readError = (stderr || e.message || String(err)).split(` | DECLINED — INFO | the thrown text is yq's diagnostic or ENOENT, console only. |
| n25 | LOW | claude-headless | h3-bb | `'{"opt": (.hounfour.headless.agy_opt_in | (tag == "!!bo` | REFUTED | go-yq v4.44.1: `True`/`TRUE` tag bool but `. == true` is false → off; `canon` is live. |
| n26 | MEDIUM | claude-headless | i3-effort | `build_headless_argv` | REFUTED — INFO | both callers pass `prompt=None` — the prompt travels on stdin; `effort` allowlisted; S8 drops the unused parameter / adds `--`. |
| n27 | LOW | claude-headless | i3-effort | `if is_context_limit_message(full_diag) and not any(w in` | REFUTED — INFO | the classifier runs only on rc≠0 / is_error and reads the error result/stderr; r251-3 throttle precedence applies. |
| n28 | LOW | claude-headless | i3-effort | `f"claude CLI refused the prompt as too large: {full_dia` | DECLINED (pre-existing) — INFO | same pattern at three pre-existing sites; MODELINV redacts. |
| n29 | LOW | claude-headless | i3-effort | `wire_effort` | DECLINED (latent) — LOW | S8: wrap `_effort_on_wire` at the emit site in a local try (an exception there would lose the whole envelope). |
| n30 | MEDIUM | claude-headless | j3-effort | `wire_effort` | PARTIAL — LOW | the test claim is refuted (grok covered); latent `__new__` risk as n29 → S8. |
| n31 | LOW | claude-headless | j3-effort | `_dry` | REAL (test hygiene) — LOW | T6: `_dry` sets a `CLAUDE_HEADLESS_BIN` sentinel and a minimal PATH. |
| n32 | LOW | claude-headless | j3-effort | `_invoke` | DECLINED (pre-existing pattern) — LOW | identity-patching `redact_payload_strings` is the repo's MODELINV-capture idiom; effort fields are not redacted fields. |
| n33 | MEDIUM | claude-headless | k3-effort | `.claude/defaults/model-config.yaml: effective_input_cei` | DECLINED (D-3.10 + C1) | nothing new beyond the recorded decision: foreign-transport tightening, count from 0.5×, no beta header needed, `probe_outcome: partial` visible. |
| n34 | LOW | claude-headless | k3-effort | `tests/unit/cycle-124-effort-flag.bats: @test "c127-2-1:` | REFUTED | runtime guard exists and is tested (`ultra`, `HIGH`, 3, True, list, None). |
| n35 | LOW | claude-headless | k3-effort | `.claude/data/schemas/model-config-v3.schema.json: "prob` | REAL (schema hardening) — LOW | T5: if/then `probed_headless` ⇒ `transport: claude-headless` + `probe_outcome` required; `maxLength` on cli_*. |
| n36 | LOW | claude-headless | k3-effort | `.claude/adapters/tests/test_effort_wire_conformance.py:` | DECLINED — LOW | placeholder creds; an uncaptured transport fails the test. |
| n37 | MEDIUM | gpt-5.5-pro | l3-ceil | `` | DECLINED (documented C7 trade-off) — LOW | the `warn` path risks one rejected upload; the provider enforces the limit; the 400 is recorded and tightens the next call. |
| n38 | MEDIUM | claude-headless | l3-ceil | `input_bound` | PARTLY REAL — LOW | envelope claim refuted; writer is cheval only from HTTP 400/413 text; lock symlink/owner/inode-checked; tighten-only. Residue: no plausibility floor (`observed=1` wedges the route) → S7. |
| n39 | LOW | claude-headless | l3-ceil | `parse_context_limit` | REFUTED | `parse_context_limit` runs only behind `is_context_limit_message` and not-throttle; the CLI verdict is not persisted. |
| n40 | LOW | claude-headless | m3-ceil | `"cli_bin": "/home/merlin/.local/bin/claude-bedrock"` | REAL (doc/nit) — LOW | T4: `~`-relative paths in the record; the committed record's two `/home/merlin` occurrences rewritten; no credentials in it. |
| n41 | LOW | claude-headless | m3-ceil | `test_calibrated_entry_without_a_count_warns_that_the_es` | DECLINED (dup n37) — LOW | — |
| n42 | MEDIUM | claude-headless | m3-ceil | `test_cli_shape_variants` | REFUTED | as n39. |
| n43 | LOW | claude-headless | n3-probe | `test_default_binary_is_claude_on_path` | REAL — LOW | T4: record `shutil.which(cli_bin)`. |
| n44 | LOW | claude-headless | n3-probe | `test_runs_from_another_cwd_under_python_isolated_mode` | DECLINED | PATH emptied and the bin asserted to be the fake. |
| n45 | LOW | claude-headless | o3-probe | `test_write_operator_set_changes_only_the_entry_and_repl` | REAL (dup n52) — LOW | cli_version is json-quoted and capped; host_route/cli_model newline injection → T1. |
| n46 | LOW | claude-headless | o3-probe | `test_p7_a_timeout_kills_the_whole_process_group` | REAL (nit) — LOW | T7: check `/proc/<pid>/cmdline` before killing. |
| n47 | MEDIUM | claude-headless | p3-probe | `tools/ceiling-probe-live.py @@ -13,6 +13,91 @@ module d` | REAL (dup n52) — LOW | T1. |
| n48 | LOW | claude-headless | p3-probe | `.claude/adapters/tests/test_ceiling_probe_cli_transport` | REAL (dup n35) — LOW | T5. |
| n49 | LOW | claude-headless | p3-probe | `.claude/adapters/tests/test_ceiling_probe_cli_transport` | DECLINED (doc) — LOW | `detail` capped at 300 chars; the operator reviews a record before committing it. |
| n50 | LOW | claude-headless | p3-probe | `.claude/adapters/tests/test_ceiling_probe_cli_transport` | REFUTED | the module-scoped sentinel points `CLAUDE_HEADLESS_BIN` at a non-existent path and the test asserts it. |
| n51 | MEDIUM | gpt-5.5-pro | q3-probe | `tools/ceiling-probe-live.py::_cli_bin and tools/ceiling` | DECLINED (same trust model, pre-existing) | the adapter already runs the env-selected binary with the full environment; whoever sets the env holds the credentials. |
| n52 | MEDIUM | claude-headless | q3-probe | `write_catalog_operator_set` | REAL — LOW (must-fix: silent corruption of a tracked default) | T1: `--host-route` / `--cli-model` (incl. `ANTHROPIC_DEFAULT_OPUS_MODEL`) with a newline rewrote `effective_input_ceiling` in the loaded YAML (verifier probe); reject control chars / over-long values before the dry run, dry-run with the resolved kwargs, re-parse the written text and assert the ceilings before `os.replace`. |
| n53 | LOW | claude-headless | q3-probe | `_classify_unguarded` | REFUTED | wait clamped to the cap; `retry_after_s` dropped from the sample. |
| n54 | LOW | claude-headless | q3-probe | `_cli_bin` | DECLINED (dup n51) | provenance part → n43. |
| n55 | MEDIUM | claude-headless | r3-probe | `"route_env": _route_env(),` | REFUTED | `_route_env` is a 3-key allowlist, the Bedrock switch recorded as presence only; argv carries no credential. |
| n56 | LOW | claude-headless | r3-probe | `_charge` | REAL (robustness) — LOW | T2: finite-number guard on CLI-reported cost/tokens/retry-after (`Infinity` → OverflowError outside the attempt try). |
| n57 | LOW | claude-headless | r3-probe | `write_catalog_operator_set(fh.read(), args.model, ceili` | REAL (dup n52) — LOW | T1: dry-run with the resolved kwargs. |
| n58 | LOW | claude-headless | r3-probe | `if spent_micro + est_micro > budget_micro:` | REAL — LOW | T3: 1.8 prior for the first step's estimate and the pre-flight line. |
| n59 | LOW | claude-headless | t3-docs | `docs/migration/v2.0-model-generation-floor.md` | DECLINED (pre-existing, documented) | argv exposure predates the sprint; the sprint makes the route default-off. |
| n60 | LOW | claude-headless | t3-docs | `docs/migration/v2.0-model-generation-floor.md` | DECLINED (pre-existing design, out of scope) | every dissent key is read from the project tree; base-ref config on PR review is a bead-worthy idea — noted on bd-ugmi. |

**Counts (run 1).** DECLINED 22, DOC 1, PARTIAL 1, PARTLY 1, REAL 21, REFUTED 14.

## Run 2 (the r251-3 delta `d12bdfab..58f87195`, 4 chunks a4…d4, two-voice at 2026-10-07T15:5xZ)

- **Envelope.** `adversarial-audit.json` = `adversarial-audit-run2-merged.json`: 11 findings — **4 MEDIUM, 7 LOW**; 0 schema-rejected; 2/2 voices, APPROVED before triage. Lead rulings (the delta is small; the probes are the lead's and the implementers' tests):

| ID | Sev | Voice | Chunk | Anchor | Ruling | Action |
|---|---|---|---|---|---|---|
| n1 | MEDIUM | claude-headless | a4-delta | `_catalog_provider_maps` | REAL — LOW | S5: `_catalog_provider_maps` must not cache a partial map built after a swallowed exception; WARN once; name-rule fallback. |
| n2 | MEDIUM | claude-headless | a4-delta | `routes_to_agy` | REFUTED (chunk visibility) | the bash lib WAS updated in r251-3 (`agy_catalog_provider` through the generated maps); the chunk saw loader.py only. |
| n3 | MEDIUM | claude-headless | a4-delta | `catalog_provider_of` | REFUTED | `routes_to_agy` checks the literal `gemini-headless` forms (bare, `*:gemini-headless`, `gemini-headless:*`) before the provider rule, so an alias targeting `gemini-headless:<m>` is agy-routed by name. |
| n4 | LOW | claude-headless | a4-delta | `_calibrate_hint` | REAL — LOW | S6: `shlex.quote` the model ids in the calibrate hint. |
| n5 | LOW | claude-headless | a4-delta | `_RE_THROTTLE_STATUS` | REAL — LOW | S6: `_RE_THROTTLE_STATUS` word boundaries (a request id `req_a529fz` matched). |
| n6 | LOW | claude-headless | a4-delta | `is_context_limit_message` | VERIFY → S6 | if `is_context_limit_message` fires on a bare `N tokens (limit M)` with no marker word, require a marker or the CLI sentence shape; false-positive test. |
| n7 | MEDIUM | claude-headless | b4-delta | `agy_catalog_provider` | REFUTED (+ hardening test) | `generated-model-maps.sh` declares `MODEL_PROVIDERS`/`MODEL_IDS`/`MODEL_AUTH_TYPE` with `declare -A` — a string subscript is not arithmetically evaluated; S5 adds a hostile-string test anyway. |
| n8 | LOW | claude-headless | b4-delta | `routes_to_agy` | REAL — LOW | S5: WARN once on the silent name-rule fallback (also review round-2 Obs 4). |
| n9 | LOW | claude-headless | b4-delta | `_zero_live_spend` | DECLINED | the `CLAUDE_HEADLESS_BIN` sentinel is the guard (review Obs 8 asked for the host-global ledger assertion to go). |
| n10 | LOW | claude-headless | c4-delta | `is_throttle_message` | DECLINED (documented trade-off) | Bedrock's throttle text carries a context marker; a genuine size rejection does not say 'please wait' / carry a 429; the Fable review's HIGH required exactly this precedence; the probe scopes the throttle text to result + api_status. |
| n11 | LOW | claude-headless | d4-delta | `_classify_unguarded` | DECLINED | the widened markers are the adapter's pre-existing rate-limit words; one shared rule keeps the probe and the adapter equal (conformance test). |

## Round r251-4 outcome

Committed as `cbfccab2` (pushed). Two Opus 5.5 implementers (`wt-127-9` core S1–S9, `wt-127-10` probe T1–T7); both patches applied cleanly; the lead fixed one schema-bats fixture (`V3-add (c127)` now carries `probe_outcome` and two negative if/then cases), regenerated the model artefacts, REPO-MAP and checksums, rebuilt the Bridgebuilder dist, ran the suites and the lints.

| Item | Outcome |
|---|---|
| S1 (n22) | Under `readError` the merge check no longer subtracts not-planned voices: `mergeBlocked = true` with the read error as the reason; `api_key_mode: strict` throws; test. |
| S2 (n6) | `agy_opt_in_enabled` with no explicit root reads from cheval's install root (the repo the adapters belong to), never a cwd ancestor; a config not owned by the euid or group/world-writable reads off with one WARN; planted-parent / foreign-owned / install-root tests. |
| S3 (n5, n17-new) | The exact `tag:yaml.org,2002:bool` tag in Python, bash and TS; alias and merge-key nodes read off in every reader; AGC rows + Python/TS cases. |
| S4 (n10, n15) | `declare -F agy_opted_in` include guard, `_LOA_AGY_GATE_WARNED` reset; `run-preflight.sh` fails closed (exit 2) when the lib cannot be sourced. |
| S5 (run 2 n1, n7, n8) | No caching of a partial provider map; one WARN on the name-rule fallback (bash and Python); hostile-subscript test against the `declare -A` maps. |
| S6 (run 2 n4, n5, n6) | `_RE_THROTTLE_STATUS` non-word boundaries; the CLI-shape parse requires its sentence (false-positive test); `shlex.quote` in the calibrate hint. |
| S7 (n38) | Observations below 10 % of the window or above it are ignored with a WARN. |
| S8 | Comment/docstring fixes, `strenv` in loa-status yq, not-planned voices in the posted Verdict Quality line, `build_headless_argv` without the unused `prompt` parameter, `_effort_on_wire` wrapped at the emit site. |
| S9 (review Obs 2) | AGC-6 prints `$status`, `$stderr` and the `--json` output on failure; the batch ran three times green in the worktree and 18/18 in the real tree. |
| T1 (n52, n45, n47, n57) | Control characters / > 200 chars in `--host-route`, the resolved `--cli-model` or `cli_version` → exit 2 before the dry run; the dry run uses the real write's kwargs; the written text is re-parsed and its ceilings and provenance asserted before `os.replace`; newline tests. |
| T2–T4 (n56, n58, n43, n40) | Finite, bounded CLI numbers; 1.8 prior for the first-step estimate (pre-flight line says so); `shutil.which` + `~`-relative paths in the record; the committed record's two home paths rewritten. |
| T5 (n35, n48) | Schema if/then (`probed_headless` ⇒ `transport: claude-headless` + `probe_outcome`), `maxLength: 200` on the cli_* fields; the live catalog validates; negative cases. |
| T6, T7 (n31, n46) | `_dry` sentinel + minimal PATH; `/proc/<pid>/cmdline` check before kill. |

**Suites, real tree, serial (ok / not ok / skip):** adapters pytest 3015 / 0 / 6 (279 subtests); bats agy-gate-conformance 18/0, run-preflight 22/0, loa-status-providers 12/0, adversarial-review-companion (filtered) 47/0, flatline-tertiary-agy-opt-in 5/0, model-config-v3-schema 35/0, cycle-124-anthropic-catalog 14/0, cycle-124-effort-flag 13/0, gen-bb-registry-codegen 40/0; Bridgebuilder 807/808 (`persona.test.ts` = KF-036); lints clean; `regen-model-artifacts --check` drift-free, dist fresh; `regen-checksums --check` changed=0.

**Not done (by ruling):** no third audit dissent run (≤ 2 per gate) — the r251-4 delta is covered by the Fable audit; the agy argv transport (bd-ugmi) and base-ref config on PR review (noted on bd-ugmi) stay operator-side.

## Round r251-5 (the Fable audit's APPROVED-with-items feedback) — commit `c2ef7581`

- **MED-001** one permission rule across the three readers: the bash lib (`stat` owner/mode, BSD fallback) and `readAgyGate` (`fs.statSync` uid/mode) refuse a config not owned by the current user or group/world-writable, like the loader — off, one WARN; conformance rows (world-/group-writable `true` → off everywhere). **LOW-001** the private-group exception is gone (group-writable refused unconditionally). **LOW-003** static-auth markers precede a "please wait"-only throttle match. **LOW-004** root cause found and fixed: `workflow-state.sh` let a cache tool's status line ("v Cached result for key: …") onto stdout on every cache miss, so `loa-status --json`'s jq merge failed with exit 5 when the cache missed under the batch — the stray stdout is now discarded; regression case in `agent-ergonomics-workflow-state.bats`. **LOW-002** CHANGELOG, addendum, SDD D-1.1 + D-1.11.
- Suites: adapters pytest 3039 / 0 / 6; agy-gate-conformance 21/0 twice, run-preflight 22/0, loa-status-providers 13/0, agent-ergonomics-workflow-state 5/0, companion (filtered) 47/0, flatline-tertiary 5/0; Bridgebuilder 819/820 (KF-036); lints clean; artefacts drift-free.

