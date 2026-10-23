# Reviewer concerns (Phase 2, preliminary) — sprint-1 / PR cycle-127 sprint-251

Scope: pr/head.diff (45 files). Focus the dissent on:
1. loader.agy_opt_in_enabled: does the merged config it reads actually have `headless` at top level (hounfour subtree) or is the key path wrong?
2. Four separate shell/TS copies of the yq opt-in predicate (`yq eval ... tag == "!!bool"`): go-yq only; python-yq hosts fail closed even when the operator opted in (run-preflight handles YQ_FLAVOUR, the others don't).
3. flatline `_tertiary_routes_to_agy` gates only `cli-only`; `prefer-cli` with no GOOGLE key still routes a Google tertiary to agy in cheval -> failed voice instead of not planned.
4. adversarial-review.sh: `companion_skip_reason=opt_in_required` — is the reason propagated to the envelope `companion_voice.reason` and accepted by any schema/enum?
5. cheval.resolve_effort / _effort_on_wire: fallback hops inherit the primary's effort; modelinv effort_effective derivation from final_model_id.
6. catalog: probed_ceiling 936000 vs measured_input_tokens 972887 (I2 clamp) vs schema description saying measured value "is the value written to probed_ceiling"; checksum consistency; generated truncation table consistency; dist bundles vs resources.
7. tools/ceiling-probe-live.py clean-write clamp; test coverage of the clamp; needle verification; spend accounting.
8. Bridgebuilder readAgyGate: sync execFileSync yq per call; mode handling parity with cheval.
