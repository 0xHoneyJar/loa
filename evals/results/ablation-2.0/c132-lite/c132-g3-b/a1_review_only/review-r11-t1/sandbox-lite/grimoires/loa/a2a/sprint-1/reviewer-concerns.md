# Reviewer concerns — sprint-1 (pr/head.diff, cycle-126 sprint-247)

Scope: 65 files. Python adapters (loa_cheval providers/base, anthropic, openai, google, bedrock, retry, routing/ceiling, types, metering), shell (flatline-orchestrator, lib-multipass, cost-report, loa-status, gen-adapter-maps, generated-model-maps), Bridgebuilder TS (config.ts, truncation.generated.ts, multi-model-pipeline.ts, gen-bb-registry.ts, dist/*), catalog model-config.yaml, bats and pytest tests.

Concerns to probe:
1. "Every size decision derives from the resolved catalog entry" — look for any remaining hardcoded max_tokens / input-size / truncation constants that bypass the catalog, or fallbacks that silently reintroduce a fixed size when the catalog entry is missing or malformed.
2. Generated artifacts (generated-model-maps.sh, config.generated.ts, truncation.generated.ts, dist/*) — do they match the catalog they are generated from? Any hand-edited drift vs the generator?
3. Ceiling / retry logic: off-by-one or unit confusion (tokens vs chars vs bytes), clamping order (floor vs ceiling), negative or zero budgets, long-context pricing tier boundaries.
4. Shell: unquoted expansions, yq/jq failures swallowed (set -e vs pipelines), numeric validation of catalog values before arithmetic.
5. Tests: do new tests actually assert the catalog-derived value or just the constant the code happens to use? Any tests weakened or deleted?
6. Bridgebuilder pipeline timeouts: catalog-derived timeout wiring, default when provider missing, dist/ rebuild parity with resources/.
