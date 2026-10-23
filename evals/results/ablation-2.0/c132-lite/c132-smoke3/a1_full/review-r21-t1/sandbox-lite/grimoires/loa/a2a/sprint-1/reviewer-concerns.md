# Reviewer concerns — sprint-1 (PR: sprint-257 advisory open-weight voices, local_voices posture, Bridgebuilder trusted config and exit codes)

Phase 2 concern notes for the cross-model dissenter. Scope: `pr/head.diff` (80 files).

## Where I want a second pair of eyes

1. `.claude/scripts/adversarial-review.sh` `_adv_budget_estimate` / main budget pre-check: the estimate now sums primary + companion first hop + every advisory voice at catalog prices and compares the SUM against `budget_cents`, which the docs and the example config describe as a cap on ONE dissent call. With the shipped `gpt-5.5-pro` ($30/$180 per Mtok) a 200 KB diff alone estimates 242c > 200c; previously 74c. Does this refuse reviews that used to run?
2. `.claude/scripts/lib/hop-locality.py` `classify` and Bridgebuilder `isLocalVoice` accept a provider-level `dispatch_group: local`; cheval's `hop_locality_of` (`audit/modelinv.py`) and `OpenAIAdapter._transport_policy` only read the model entry. A provider-level declaration plans as local but is recorded `hop_locality: hosted` and gets no TransportPolicy unless an opt-in is present.
3. `_adv_advisory_walk` runs `process_findings` (incl. the KF-004 repair loop) in a backgrounded subshell concurrently per advisory voice. Any shared state (CLI locks, `_ADV_*` globals, ledgers) races? Repair hops during advisory runs under `local_voices`?
4. `openai_adapter.py` `_names_response_format`: the 400 retry heuristic matches any body mentioning `response_format`/`json_schema` — false positives (a schema validation error from a server that DOES support response_format) silently drop the schema.
5. `openai_streaming.py` `strip_thinking_blocks`: an unterminated leading `<think>` blanks the whole content. Any case where a legitimate answer begins with `<think>` text?
6. `endpoint-validator.py` Step 1.5: the opt-in branch returns early before Steps 2–8. Which checks are skipped for the opted-in host (IDN, path, port, userinfo are re-done — anything else)?
7. `TransportPolicy.check_url`: traversal check is string-based (`/../`); percent-encoded traversal passes. URL is adapter-built, so is this exploitable?
8. Bridgebuilder `loadTrustedConfig`: `isPullRequestContext` false when run locally with no env → the working tree is trusted. Any CI path where a PR head is checked out but none of `--pr`, `GITHUB_EVENT_NAME`, `GITHUB_BASE_REF` is set?
9. `model-health-probe.sh` `_probe_configured`: `key="${!auth_env:-}"` indirect expansion of a name from JSON (regex-validated in Python). Safe?
10. `flatline-orchestrator.sh` `flatline_locality_gate`: `run_phase1` under `local_voices` — bats FLL-3 fails in this checkout; is it a test-environment issue or a real dispatch defect?
11. `pricing.py` `_main` default `--config` path `here.parents[4]/.loa.config.yaml` and `--catalog` `here.parents[3]/defaults/model-config.yaml` — correct relative to `.claude/adapters/loa_cheval/metering/pricing.py`?
12. `session-cap-bb/dispatcher.sh`: BB stdout redirected to `$HANDOFF_DIR/bb-stdout.json` then `cat` — file left in handoff dir; any consumer that globs the dir?
