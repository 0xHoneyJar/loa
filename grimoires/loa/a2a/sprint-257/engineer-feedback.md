All good

# Sprint 257 review — round 2 (cycle-129 Sprint 3) — APPROVED

**Reviewer:** Senior Technical Lead (Claude Fable 5.1, `global.anthropic.claude-fable-5-1`)
**Date:** 2026-10-14
**Implementation:** `cf88e427` (fix round r257-1 on `163656ff`, base `a7682ba4`); reports `reviewer.md` (Feedback Addressed section), `reviewer-j.md`, `reviewer-g.md`, `reviewer-h.md`, `reviewer-i.md`, `e2e.md`
**Dissent:** `adversarial-review.json` (round 2, committed range `a7682ba4..cf88e427`, code-only diff of 61 files) — two voices (`codex-headless` gpt-5.5-pro primary: clean; `claude-headless` companion: 4 advisory findings), consensus, confidence floor high, chain ok, 0 rejected payloads. Round 1 envelope kept as `adversarial-review.r1.json`; round 1 feedback as `engineer-feedback-r1.md`.

## Round 1 items

HIGH-1 is closed: the local-hop rule is stated once (`endpoint_policy.py` `LOCAL_RULE_TEXT`, `local_host`, `local_endpoint_host`, `_local_label_refusal`) and read in the patch hunks at every place the review named — `validate_providers` (the D-7.2 checks first, then the label refusal; an `https` endpoint on a local host admitted with the provider's own canonical host as the per-call opt-in), `TransportPolicy.local` in `check_url` (before the origin and path checks; set by `openai_adapter._transport_policy`), `hop-locality.py` `endpoint_locality` and `_is_cli` (stdlib mirror of the validator's ranges and `_canonical_host`), Bridgebuilder `config.ts` `localEndpointHost` / `localVoiceDecision` (hand-split authority, leading-zero IPv4 refused, `::1` canonicalised through `URL`) with `ProviderDecl.endpoint`/`cli` carried from the trusted view, and `audit/modelinv.py` `hop_locality_of`. LOW-1 (loader-admissible fixtures, LOC-10/FLL-9 load them through `load_config`), LOW-2 (`keyless: false` conflict refused by name) and LOW-3 (every load failure one JSON line and exit 78) are closed as described in `reviewer.md`. The lead reran on the integrated tree: cheval pytest 3256 passed / 2 baseline failures, Sprint 3 bats plus every probe suite 136/136, `npm test` 867/868 (KF-036), dist fresh, TypeScript port clean, fence corpus 99/99 · 184/184, lints green.

## Round 2 dissent findings (all advisory; checked against the tree)

- **LOW-1 — `exit_on_degraded` documented as any integer 0..125 while the callers understand two values (DISS-C-001, confirmed).** `.loa.config.yaml.example:2513` says "Integer 0..125"; `spiral-harness.sh` `_bb_surface_exit` and the session-cap dispatcher treat 3 as "completed, degraded" and every other non-zero exit as "did not complete", and `entry.sh` reserves 4. Hardening (lead, before the audit): the comment names the two meaningful values and says what the callers do with any other.
- **LOW-2 — LOC-9's whole-run clause describes an outcome production cannot show (DISS-C-002, confirmed).** The classifier assertions are right, but "the local hop answers" holds only under the harness stub: with `hostedbox`, `blockbox`, `clibox` and `noend` in the config, cheval's `load_config` refuses the whole config at `lq`'s first dispatch (`_local_label_refusal`), so the planner's by-name refusal and the loader's whole-config refusal are two layers, not one behaviour. Hardening (lead, before the audit): LOC-9 keeps the plan-time by-name refusal and adds the loader's refusal of the same config by name as the production outcome; the "local hop answers" claim goes.
- **LOW-3 — no test pins the advisory voice's own cost (DISS-C-003, half refuted).** `_adv_advisory_block` already records `cost_usd` (and `exit_code`) per advisory entry, and the counted envelope's `metadata.cost_usd` excluding advisory spend is AC-3.3's byte-identity by design; what is missing is an assertion. Hardening (lead, before the audit): ADV-1 asserts `.advisory_voices[0].cost_usd` equals the stub's advisory cost and the counted `metadata.cost_usd` is the counted voices' alone.
- **Refuted — Example 3's `secret_env_allowlist` would remove the defaults (DISS-C-004).** `loader.py:677` compiles the project list into `extra_env_patterns`; `interpolation.py:25-27` keeps `^LOA_`, `^OPENAI_API_KEY$`, `^ANTHROPIC_API_KEY$` … as built-in defaults and `_check_env_allowed(source_ref, extra_env_patterns)` tests both sets, so a copied Example 3 adds a pattern, exactly as the comment says. No change.

## Acceptance criteria

AC-3.1 … AC-3.8 met; AC-3.6's "no hosted hop in the inventory is planned" now holds by the endpoint host at load, request time, planner and Bridgebuilder (evidence in `reviewer.md`).

## Verdict

APPROVED. The three LOW hardenings are small enough to land as a lead chore commit before the audit dissent, which runs on the committed range and so reviews them; the review dissent budget stays at two runs.

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":3},"excluded":0,"sprint_id":"sprint-257","ts":"2026-10-14T09:27:24Z"} -->
