# Reviewer concerns — sprint-1 (PR: cycle-127 sprint-251 operator decisions)

Scope: pr/head.diff. Cite head/<path>:<line>.

## Areas I want a second opinion on
1. cheval.py `effort_effective` on the MODELINV envelope: resolved once against the PRIMARY entry; when the primary has no default and the chain falls to a CLI hop whose `extra.effort` is set, the headless adapter still sends `--effort <extra>` but `_effort` is None so `effort_effective` is omitted (under-report).
2. loader.agy_opt_in_enabled merges System defaults (model-config.yaml) UNDER the project config — the bash (yq) and TS readers read only .loa.config.yaml. A `headless.agy_opt_in: true` in the System catalog would opt cheval in while every planner reads off.
3. Three bash readers (flatline-orchestrator.sh, adversarial-review.sh, loa-status.sh) use go-yq-only syntax (`tag == "!!bool"`); run-preflight.sh branches on YQ_FLAVOUR. On a python-yq host, operator opt-in true → cheval dispatches agy but flatline/dissent/status say "not planned".
4. adversarial-review.sh `_adv_agy_filter_chain` drops only hops canonicalising to `gemini-headless`; flatline/TS also treat any Google model under headless mode cli-only as agy-routed. Operator companion_chain with a Google API id under cli-only → planned, dispatched, refused by cheval → dropped voice.
5. model-config.yaml claude-opus-5-5: effective_input_ceiling 180000 → 936000 written as `operator_set` from a probe whose own outcome was `partial` (the tool refuses to write partial). Measured through Bedrock CLI, applied to the anthropic HTTP entry; account_limits itpm null; the calibrated state means observed 429s never lower the bound (per LSP-5 comment). Fallback chain hop claude-opus-5 still 180000.
6. test_anthropic_catalog_floor: test_write_operator_set_changes_only_the_entry_and_replaces_the_shortcut now `pytest.skip`s permanently in head (the shortcut comment is gone) — it was the only test validating the writer's ceiling_calibration output against the JSON schema and input_bound.
7. loa-status.sh `_provider_hop_note` prints "agy: opt-in (disabled…)" for google even on hosts with no agy binary.
8. run-preflight P3: a stage whose only voice is a gated agy hop FAILs with detail "no credential present and no CLI hop on PATH" (misleading reason) plus the not-planned note.
9. ceiling-probe-live.py: the head catalog's provenance comment is not what the writer (fr23b) produces — re-running the writer rewrites it (adds the clamp note). Also `next_target` re-anchors the top after a parsed size rejection, costing a second top-size attempt.
10. agy adapter: `agy_opt_in_enabled()` is re-read (two YAML loads + deep merge of the whole catalog) on every complete()/health_check()/validate_config().
