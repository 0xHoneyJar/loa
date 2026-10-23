# Reviewer concerns — sprint-1 (PR: sprint-251 operator decisions)

Scope: pr/head.diff (45 files). Cite head/<path>:<line>.

1. cheval chain walk never plans around the agy hop. AgyOptInRequiredError is a ChevalError; the walk's
   `except ChevalError` surfaces it immediately (head/.claude/adapters/cheval.py ~2545). Under
   hounfour.headless.mode prefer-cli the CLI hop is FIRST (chain_resolver cli + http), so a Google voice with a
   valid GOOGLE_API_KEY and agy installed dies at hop 1 with INVALID_CONFIG while the TS/flatline planners
   (isAgyRouted / _tertiary_routes_to_agy gate only cli-only) still count the voice as planned -> DEGRADED.
2. claude-opus-5-5 effective_input_ceiling/probed_ceiling 936000 written as a CALIBRATED entry on the anthropic
   HTTP entry from a Bedrock claude-headless measurement whose own outcome was `partial`; the bats comment says a
   calibrated bound is never lowered by observations, so an API 429/400 at large sizes has no self-correction;
   the catalog comment itself says the estimator under-counts ~1.8x on the Opus 4.7+ tokenizer.
3. agy_opt_in_enabled merges .claude/defaults/model-config.yaml (System Zone) under the project config, so a
   framework-shipped `headless.agy_opt_in: true` would opt downstream mounts in; docstring says .loa.config.yaml.
4. Python reader is PyYAML (YAML 1.1: yes/on are booleans) while bash/TS readers are yq v4 (YAML 1.2) ->
   divergent gate for `agy_opt_in: yes`.
5. _effort_on_wire returns the resolved effort for every CLI entry, but codex/grok headless adapters never read
   request.effort -> effort_effective misreported for those hops.
6. Bridgebuilder pipeline: a not-planned voice caused by a READ ERROR (yq missing, unreadable config) shrinks the
   quorum the same way as an operator decision; strict api_key_mode silently drops the voice.
7. readAgyGate default path is cwd-relative for callers other than the pipeline.
8. validate_config keeps checking PATH after the opt-in refusal (noise); health_check placed under the
   "command construction" section.
9. Catalog provenance: sample_size null though 5 samples; probe outcome `partial` only in a comment.
10. Test weakening: test_ceiling_is_the_computed_value_per_entry becomes tautological for measured entries;
    test_write_operator_set_changes_only_the_entry... always skips on the calibrated head catalog.
