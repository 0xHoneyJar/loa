# Reviewer concerns — sprint-1 (PR: cycle-127 sprint-251 operator decisions)

Scope: `pr/head.diff` (45 files). Cite as `head/<path>:<line>`.

## Primary concerns (verify or refute)

1. **Bridgebuilder budget units** — `head/.claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts:34` and
   `dist/core/truncation.generated.js:31` set `claude-opus-5-5.maxInput: 916000` (= 936000 − 20000). BB's maxInput is in
   estimate units (coefficient 0.25 tokens/char); the catalog ceiling 936000 is in provider-measured tokens. The PR's own
   catalog comment (`head/.claude/defaults/model-config.yaml:496`) says the filler under-counts ~1.8x under the Opus 4.7+
   tokenizer. A diff admitted at ~900K estimated tokens measures ~1.6M on the wire — above the 1M window. Previously the
   160K budget left headroom to the 1M window; now the ceiling sits at the window edge.
2. **CLI/Bedrock measurement written to the HTTP entry** — `head/.claude/defaults/model-config.yaml:495-512`: the
   `anthropic:claude-opus-5-5` HTTP entry's `effective_input_ceiling` goes 180000 → 936000 from a claude-headless/Bedrock
   measurement. `_lookup_max_input_tokens("anthropic", ...)` (HTTP route) now returns 936000; a calibrated bound is never
   lowered by observation (tests/unit/loa-status-providers.bats LSP-5). Direct-API accounts with ITPM limits lose the
   pre-emption.
3. **Opt-in refusal inside a cheval chain walk** — `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:124-125`
   raises `AgyOptInRequiredError` (a `ConfigError`, INVALID_CONFIG, exit 2). cheval's chain walk hard-aborts on
   ConfigError (`cheval.py` ~2527 comment). A catalog `fallback_chain` ending in `gemini-headless` (every stock Google
   chain) that walks there after an upstream HTTP failure now exits INVALID_CONFIG and masks the upstream failure; the
   planner-side filters (`_adv_agy_filter_chain`, `isAgyRouted`, `_tertiary_routes_to_agy`) only gate explicit hops /
   cli-only mode, not catalog fallback chains.
4. **`agy_opt_in_enabled` loads the full catalog** — `head/.claude/adapters/loa_cheval/config/loader.py:113-125` deep-merges
   `load_system_defaults` (the whole model-config.yaml) into the project config just to read one key; a `headless:` key
   in a System-Zone catalog would opt in without touching `.loa.config.yaml`.
5. **Hand-written operator_set with `method: probed_headless`** — the tool refused to write (outcome `partial`), the
   operator wrote `probed_ceiling: 936000`, `measured_input_tokens: 972887`; the schema description of
   `measured_input_tokens` (`model-config-v3.schema.json:300-304`) says it is the value written to probed_ceiling, which
   the fr23b clamp contradicts. Stale trailing comment `# cycle-124 FR-3 (SDD §2.1): see claude-fable-5-1` on line 494.
6. **Tests that now self-reference** — `test_anthropic_catalog_floor.py:589-591` expected = min(entry value, …) for
   measured entries; `test_ceiling_probe_cli_transport.py::test_write_operator_set_changes_only_the_entry_and_replaces_the_shortcut`
   skips permanently now that the live catalog is calibrated.
7. **resolve_effort "both" WARN** fires for HTTP entries whose `extra.effort` is never read (`cheval.py:922-925`).
8. **Effort resolved against the primary entry only** — a fallback hop with its own `default_effort` never gets it;
   `effort_effective` recomputed from `final_model_id` with the primary's effort.
9. **Probe `_run_capped` env** — `tools/ceiling-probe-live.py:~290` passes the full `os.environ` plus one var rather than
   the adapter's `build_headless_subprocess_env()`; docstring says "as the adapter".
10. **Missing `## AC Verification`** in the implementation report (`pr/PR.md`).

## Areas believed sound
- Checksum `model-config.yaml.checksum` matches head catalog; build manifest hashes match head TS sources.
- Opt-in predicate: YAML boolean only, no env override, fail-closed; shell/TS/python readers agree on semantics.
- `build_headless_argv` extraction preserves the adapter's argv byte-for-byte (test pins it).
- `test_no_literal_opus55_ceiling_pins.py` guard holds on head files.
