# Sprint 257 review — round 1 (cycle-129 Sprint 3)

**Reviewer:** Senior Technical Lead (Claude Fable 5.1, `global.anthropic.claude-fable-5-1`)
**Date:** 2026-10-14
**Implementation:** `163656ff` (base `a7682ba4`); reports `reviewer.md`, `reviewer-g.md`, `reviewer-h.md`, `reviewer-i.md`, `e2e.md`
**Dissent:** `adversarial-review.json` — two voices (`codex-headless` gpt-5.5-pro primary: clean; `claude-headless` companion: 5 advisory findings), consensus, confidence floor high, chain ok, 0 rejected payloads

The code was read, not the reports: `lib/hop-locality.py` (`classify`, the fail-closed branches), `config/endpoint_policy.py` (`check_insecure_optin` through the validator, `canonical_optin_host`, `check_endpoint`, `normalise_keyless`, `validate_providers`, `describe_provider`, `_main`), `providers/base.py` (`TransportPolicy.check_url`, `refuse_redirect`, the opener), `providers/openai_adapter.py` (`_build_chat_body` response_format, `_schema_enforced`, the one retry, `_transport_policy`), `providers/openai_streaming.py` (`strip_thinking_blocks`, `apply_thinking_strip`), `adversarial-review.sh` (advisory voices, locality filter, budget estimate, promotion refusal, companion locality refusal), `flatline-orchestrator.sh` (`flatline_locality_mode`, `flatline_locality_gate`), Bridgebuilder `config.ts` (`isSafeRefName`, `loadTrustedConfig`, head-only refusal, `applyLocality`), `core/run-outcome.ts`, `main.ts` exit path, `spiral-harness.sh` `_bb_surface_exit`, `metering/ledger.py`, `metering/rollup.py`, `cost-report.sh`, `cost-budget-enforcer-lib.sh`, the locality and flatline fixtures. On the integrated tree: the six Sprint 3 bats suites 45/45, the six pytest files 123 passed, the TypeScript port `--check` clean, BB dist fresh, prompt budget and guard register in sync. Every dissent finding was checked against the tree before it was kept or refuted.

## Findings

### HIGH-1 — a declared `dispatch_group: local` is trusted, not enforced (dissent DISS-C-001, confirmed and widened)

Nothing relates `dispatch_group: local` to where the provider's endpoint points. `hop-locality.py:116-134` classifies a hop `local` from the key alone; `endpoint_policy.validate_providers:143-176` applies the endpoint rule and the keyless preconditions but never looks at `dispatch_group`; `base.py` `TransportPolicy.check_url:128-144` enforces same origin, the path prefix, no proxy and no redirects, but no host class; `openai_adapter._transport_policy` applies that policy for `dispatch_group == "local"`. So a provider `endpoint: "https://api.acme.example/v1"` whose model entry says `dispatch_group: local` (a typo, or a catalog entry copied from the local example) loads, is classified `local`, is planned under `locality: local_voices` (the LOC filter passes it), is dispatched to a public DNS host with the proxy environment ignored, and is recorded in MODELINV as `hop_locality: local`. SDD D-8.1 states "every local hop is dispatched under the D-7.2 request-time rules (IP-literal or `localhost` endpoint, no DNS resolution, redirects refused, proxy environment ignored …), so a declared locality is enforced, not trusted" — the request-time host rule is not implemented, and PRD AC-8.1 ("no hosted hop is planned under the switch") holds only by declaration. The same gap is in Bridgebuilder's `applyLocality` (`config.ts:739`), which filters on the dispatch group alone although the trusted config carries the endpoint.

Required in the fix round — one rule, stated once, applied in the four places that decide locality: a hop is local only when its provider is an HTTP provider whose endpoint host is an IP literal in a loopback or RFC1918 range or the literal `localhost` (the D-7.2 opt-in host rule, already implemented as `check_insecure_optin`; an `https` endpoint on such a host needs no opt-in).
(a) Loader: `validate_providers` admits `dispatch_group: local` (on a model entry or the provider block) only when the provider's endpoint host passes that rule; otherwise `[CONFIG-INVALID] providers.<p>.models.<m>: dispatch_group local requires an endpoint on a loopback or RFC1918 IP literal or localhost (host <h>)`; a CLI provider never carries `dispatch_group: local`.
(b) Request time: `TransportPolicy` for a local hop refuses by name a request host that fails the rule (a DNS name, a public IP literal), so the SDD's "enforced, not trusted" sentence is true even if a config reaches the adapter by another loader.
(c) Planner: `hop-locality.py` returns `hosted` with reason `endpoint_not_local:<host>` when the provider's endpoint host fails the rule (stdlib `ipaddress`; the script runs under `-I` and cannot import the validator); a LOC case with a hosted-DNS provider labelled local.
(d) Bridgebuilder: `applyLocality` drops a `dispatch_group: local` model whose provider endpoint host fails the rule, with the reason named (the TypeScript port `lib/endpoint-validator.generated.ts` or a small host check beside it); one `trusted-config.test.ts` case; `dist/` rebuilt.
(e) Docs: the FR-8 paragraph of `.claude/loa/reference/multi-model-reference.md:102` states the rule; the CHANGELOG Sprint 3 entry names it.
Tests: pytest — a hosted `https` DNS provider with a `local` model is refused at load with the named reason; `https://192.168.1.10:8443/v1` with a `local` model loads without an opt-in; `http://127.0.0.1:8000/v1` with the opt-in loads; `TransportPolicy` refuses a DNS host and a public IP literal for a local hop; the LOC bats case; the node:test case.

### LOW-1 — the locality fixtures declare a provider cheval itself refuses (dissent DISS-C-003, confirmed)

`tests/unit/adversarial-review-locality.bats:19-42` and `tests/unit/flatline-locality.bats:22-34` declare `localbox` with `endpoint: "http://127.0.0.1:8000/v1"` and no `allow_insecure_endpoint`, `keyless`, `endpoint_family`, `auth_type` or `context_window`; `validate_providers` refuses exactly that table at load (`model-health-probe-configured-provider.bats` asserts the refusal). The suites pass because `hop-locality.py` reads the YAML without the loader, so the plan-time gate is proven against a provider table the actual hop could never use. Fix: the fixtures declare a cheval-admissible `localbox` (`allow_insecure_endpoint: "127.0.0.1"`, `keyless: true`, `endpoint_family: chat`, `auth_type: http_api`, `context_window`), and each suite gains one case that loads its fixture through `loa_cheval.config.loader.load_config` with the fixture as project root. After HIGH-1(c) the fixture's endpoint host must pass the rule in any case.

### LOW-2 — `keyless: false` beside `auth: "local"` is silently overridden (dissent DISS-C-004, confirmed)

`endpoint_policy.normalise_keyless:134-140` validates that `keyless` is a bool and then sets it `True` whenever `auth` is a keyless literal; an explicit `keyless: false` is overwritten without a word, against the module's own posture (a boolean opt-in and a non-bool `keyless` are refused by name). Fix: `[CONFIG-INVALID] providers.<p>: keyless: false conflicts with the literal auth "local"`; a pytest case.

### LOW-3 — the probe helper CLI leaks tracebacks outside its exit-code contract (dissent DISS-C-005, confirmed)

`endpoint_policy._main:221-226` wraps `load_config` for `ConfigError` only; an unparseable `.loa.config.yaml` or a failed interpolation exits 1 with a Python traceback and no JSON, which `model-health-probe.sh:876-896` (`_configured_providers`, `_configured_provider_json`) cannot read — it greps `"error"` from stderr. Fix: every exception from `load_config` becomes `{"error":"config_load_failed","detail":"<class>: <message>"}` with exit 78, and `describe_provider` is wrapped the same way; a pytest case with a broken project-root config asserting exit 78, JSON on stderr and no traceback.

### Refuted — `stale_catalog` counted as unpriced downstream (dissent DISS-C-002)

`cost-report.sh:426-427` counts a row unpriced only when `pricing_source == "unknown"` (or absent on a zero-cost row) and keys `by_resolution` by the value itself; the budget enforcer reads the report's unpriced share (`cost-budget-enforcer-lib.sh:1228-1240`); `metering/ledger.py:200` and `metering/rollup.py:121` admit `stale_catalog`; `metering/reprice.py:75-78` targets `unknown` only; no TypeScript reader exists. No change.

## Notes (no action)

- The primary voice returned clean with 36,644 output tokens on a 1,400-line code diff; the companion carried the review. Recorded for the arm follow-up, not for this sprint.
- `.run/sprint-plan-state.json` lists sprint-2 `in_progress` and sprint-3 `pending` while `sprints.current` is sprint-3 and `completed` is 2; the lead rebuilds the cache with `run-checkpoint.sh derive --write` at the next phase write.

## Acceptance criteria

AC-3.1 … AC-3.5, AC-3.7, AC-3.8 as reported (met). AC-3.6 is Partial until HIGH-1 lands: "no hosted hop in the inventory is planned" holds by declaration only.

## Verdict

CHANGES_REQUIRED — one HIGH. Fix round: HIGH-1 (a)–(e), LOW-1 … LOW-3, then the whole cheval pytest suite, the six Sprint 3 bats suites plus the probe and locality suites, `npm test` with `dist/` rebuilt and `tools/check-bb-dist-fresh.sh`, the TypeScript port `--check`, update `reviewer.md` (AC-3.6 evidence, Feedback Addressed), commit, and re-run the review dissent on the committed range.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":0,"low":3},"excluded":0,"sprint_id":"sprint-257","ts":"2026-10-14T08:35:01Z"} -->
