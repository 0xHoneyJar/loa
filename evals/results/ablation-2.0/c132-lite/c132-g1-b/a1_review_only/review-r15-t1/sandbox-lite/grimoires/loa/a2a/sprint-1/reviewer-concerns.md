# Reviewer concerns — sprint-1 (PR: cycle-127 sprint-251 operator decisions)

Scope: pr/head.diff (45 files). Cite as head/<path>:<line>.

## Candidate findings (please confirm, refute, or extend)

1. HIGH? Foreign-transport calibration written as the provider-wide HTTP bound.
   head/.claude/defaults/model-config.yaml:494-513 writes effective_input_ceiling/probed_ceiling 936000 with
   source: operator_set, calibrated_at set, measured through claude-headless on Bedrock. The entry governs the
   anthropic HTTP route (claude-opus-5-5), which was never measured; CLI hops take no bound from routing/ceiling.
   The PR's own test comment (head/tests/unit/loa-status-providers.bats:69) states a calibrated bound is never
   lowered by observations. If the HTTP route rejects below 936K, cheval stops preempting and cannot self-correct.
   Also the tool refused to write (outcome partial) and the lead hand-wrote method: probed_headless.

2. MEDIUM. The I2 clamp (fr23b) was added only to write_catalog_operator_set (head/tools/ceiling-probe-live.py:402-443);
   the API-transport writer (head/tools/ceiling-probe-live.py:286-316) still writes int(ceiling) raw and never
   updates probed_ceiling or method. An API probe on a 1M-window model that accepts >936K writes a catalog that
   fails test_anthropic_catalog_floor's I2 assertion. Docstring line 45 still says "raw".

3. MEDIUM. Six re-implementations of the opt-in predicate (loader.py:113, adversarial-review.sh:2350,
   flatline-orchestrator.sh:522, loa-status.sh:798, run-preflight.sh:154, bridgebuilder config.ts:159) and they
   disagree on what "agy-routed" means: flatline (:529) and bridgebuilder (:180-182) gate any Google model under
   hounfour.headless.mode cli-only; adversarial-review.sh:2360 and run-preflight.sh:153/190 gate only the literal
   gemini-headless hop. Under cli-only, a gemini-3.1-pro companion hop is planned, dispatched, refused by cheval
   with INVALID_CONFIG and recorded as a failed/dropped voice (model_unavailable), contradicting the
   "not planned, never failed" contract in .loa.config.yaml.example:742-750 and docs/migration.

4. MEDIUM. cheval chain walk (head/.claude/adapters/cheval.py:2544) hard-aborts on any ChevalError, so
   AgyOptInRequiredError at a non-first hop aborts the whole invocation with INVALID_CONFIG and masks the earlier
   hop's real failure class; models_failed records error_class UNKNOWN. The "not planned" seam exists only in the
   shell/TS planners, not in cheval itself.

5. LOW. Schema description head/.claude/data/schemas/model-config-v3.schema.json:306 says measured_input_tokens is
   "the value written to probed_ceiling / effective_input_ceiling" — false after the clamp (972887 vs 936000).
   docs/migration:297 and probe docstring :45 likewise. modelinv.py:498 / cheval.py:2834 comments omit "extra".

6. LOW. resolve_effort (cheval.py:908) emits the "both rungs" WARN even when an explicit --effort makes it moot.

7. LOW. ceiling-probe-live.py:217 _run_capped passes the full os.environ to the CLI (no build_headless_subprocess_env
   strip, unlike the adapter the probe claims to mirror).

8. LOW. test_ceiling_probe_cli_transport.py:459 permanently skips the live-catalog writer test now that the catalog
   is calibrated; the writer is covered only by SYNTH.

9. LOW. loa-status display (:865) substitutes a 50-char note into a %-7s column; schema enum probed_api unused.

## Areas I would like a second opinion on
- Does cheval under hounfour.headless.mode cli-only actually route Google HTTP models through agy (the assumption
  shared by flatline/bridgebuilder)? If not, those two planners under-plan voices instead.
- Any argv/stdin leak or env exposure in the new probe transport (tools/ceiling-probe-live.py _run_capped/_classify).
- Correctness of bisection/re-anchor logic in _main_cli (next_target, step) — infinite-loop or off-by-one risks.
- Any way the YAML-boolean gate can be bypassed (interpolation, yq flavour differences in run-preflight.sh:154-160).
