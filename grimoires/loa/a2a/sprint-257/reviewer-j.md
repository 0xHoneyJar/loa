# Sprint 257 — review fix round r257-1 (implementer J)

**Implementer:** Claude Opus 5.5 subagent, model id `global.anthropic.claude-opus-5-5`
**Date:** 2026-10-14
**Worktree:** `/home/merlin/Documents/thj/code/loa-wt-s3d` (branch `wt/cycle-129-s3d`, base `163656ff`), not committed (KF-014)
**Patch:** `~/.cache/loa/cycle-129/patches/s3-j.patch`
**Feedback:** `grimoires/loa/a2a/sprint-257/engineer-feedback.md` (main checkout), round 1, CHANGES_REQUIRED (HIGH-1, LOW-1 … LOW-3)

## Executive Summary

A declared `dispatch_group: local` is now enforced, not trusted. One rule: a hop is local only when its provider is an
HTTP provider (not `kind: cli` / `*-headless`) whose endpoint host is an IP literal in a loopback (`127.0.0.0/8`,
`::1`) or RFC1918 (`10/8`, `172.16/12`, `192.168/16`) range, or the literal `localhost`. On the cheval path the rule is
the validator's own `check_insecure_optin` host acceptance (`endpoint_policy.local_host`); the planner and Bridgebuilder
carry stdlib mirrors with the same ranges. It is applied at load, at request time, in the planner, in Bridgebuilder, and
(beyond the four required places) in MODELINV's `hop_locality`. An `https` endpoint on a passing host loads with no
`allow_insecure_endpoint`; `http` still needs it. The three LOWs are fixed. DISS-C-002 (refuted) was not touched.

## Feedback Addressed

### HIGH-1 (a) — Loader

Status: **done**.
- `.claude/adapters/loa_cheval/config/endpoint_policy.py:125` `LOCAL_RULE_TEXT`; `:128` `local_host` (the validator's
  `check_insecure_optin`, brackets stripped by its `_canonical_host`); `:147` `local_endpoint_host` (http/https only,
  host from the validator's `split_url`); `:169` `_local_label_refusal` (CLI refusal, then the host rule; provider-block
  form names `providers.<p>`, model-entry form names `providers.<p>.models.<m>`, host `missing` when absent).
- `validate_providers` (`:222`): the D-7.2 endpoint checks run first (their codes are the more specific reason); a
  labelled provider is then held to the rule. A labelled `https` endpoint on a passing host with no opt-in runs
  `validate_declared_endpoint` with that host admitted for that provider only.
- Pinned by `.claude/adapters/tests/test_local_dispatch_group_rule.py`:
  `test_hosted_dns_endpoint_with_a_local_model_is_refused_by_name`,
  `test_hosted_dns_endpoint_with_a_local_provider_block_is_refused_naming_the_provider`,
  `test_non_local_ip_literal_with_a_local_model_is_refused` (169.254.169.254, 203.0.113.5, fd12::1, 8.8.8.8),
  `test_local_endpoint_with_a_local_model_loads` (`https://192.168.1.10:8443/v1`, 10/8, 172.16/12, `https://[::1]:8443/v1`,
  localhost, 127.0.0.1 with no opt-in; `http://127.0.0.1:8000/v1` + `"127.0.0.1"`; `http://[::1]` + `"::1"`),
  `test_http_local_endpoint_still_needs_the_optin`, `test_cli_provider_with_a_local_label_is_refused`,
  `test_cli_provider_refusal_in_validate_providers_directly`, `test_local_label_without_an_endpoint_is_refused`,
  `test_hosted_provider_without_a_local_label_is_untouched`, `test_unlabelled_provider_keeps_the_https_private_refusal`,
  `test_local_host_rule_table`, `test_local_endpoint_host_needs_http_or_https`.
- `tests/test_config_examples_load.py`: the two refusal cases `https-loopback-without-optin` and
  `https-private-without-optin` now relabel the model `dispatch_group: lab-gpu`, because a local-labelled provider is
  admitted there by design; the unlabelled refusal is unchanged.

### HIGH-1 (b) — Request time

Status: **done**.
- `.claude/adapters/loa_cheval/providers/base.py:132` `TransportPolicy.local: bool = False`; `:143` `check_url` refuses
  `request host <h> for provider '<p>' is not a loopback or RFC1918 IP literal or localhost (dispatch_group local, D-7.2)`
  before the origin and path checks.
- `.claude/adapters/loa_cheval/providers/openai_adapter.py:224` `_transport_policy` sets `local=True` when the model's
  `dispatch_group == "local"`. An opted-in, unlabelled provider gets `local=False`, which is today's behaviour.
- Pinned by `test_local_policy_refuses_a_non_local_request_host_by_name` (DNS name, 203.0.113.5, 169.254.169.254),
  `test_local_policy_accepts_a_local_request_host` (127.0.0.1, 10.0.0.5, [::1], localhost),
  `test_opted_in_policy_without_the_local_label_keeps_todays_behaviour`, `test_adapter_marks_a_local_hop_policy_local`,
  `test_adapter_opted_in_hop_without_the_label_is_not_local`.
- Extension: `.claude/adapters/loa_cheval/audit/modelinv.py:473` `hop_locality_of` records `local` only when the rule
  passes. Pinned by `test_modelinv_never_records_local_for_a_hop_the_rule_calls_hosted`.

### HIGH-1 (c) — Planner

Status: **done**.
- `.claude/scripts/lib/hop-locality.py:42` `_LOCAL_NETS` (the validator's ranges); `:58` `endpoint_locality` (stdlib
  `urllib.parse` + `ipaddress`, the validator's `_canonical_host` logic copied, `localhost` literal, brackets stripped);
  `_is_cli`; `classify` `:173` `cli_provider`, `:176` `endpoint_not_local:<host>` / `endpoint_missing`. Fallback-chain
  entries go through the same rule.
- Pinned by `tests/unit/adversarial-review-locality.bats:231` LOC-9: hostedbox `https://api.acme.example/v1` gives
  `endpoint_not_local:api.acme.example`; a provider-block-local `https://203.0.113.5/v1` gives
  `endpoint_not_local:203.0.113.5`; a CLI provider gives `cli_provider`; no endpoint gives `endpoint_missing`. A whole
  run refuses `hb (hostedbox)` by name and never dispatches it.
- `tests/unit/flatline-locality.bats:129` FLL-8: hosted DNS voices labelled local refuse the Flatline run by name.

### HIGH-1 (d) — Bridgebuilder

Status: **done**.
- `.claude/skills/bridgebuilder-review/resources/core/types.ts` `ProviderDecl` gains `endpoint?` and `cli?`.
- `config.ts`: the `ProviderEntrySchema` reads `endpoint` and `type`, and `parseProviderDecls` carries them from the
  trusted view. `:750` `localEndpointHost` is a hand-split authority, so `0x7f.1` stays a DNS name as in Python, and
  IPv4 leading zeros are refused as in `ipaddress`. `:801` `localVoiceDecision` returns `local`, `declared` and
  `reason`. `applyLocality` (`:844`) and `singleModelLocalityRefusal` (`:874`) use the named reason:
  `locality: local_voices refuses hosted hop <m> (<p>): dispatch_group local but endpoint host <h> is not a loopback or RFC1918 IP literal or localhost`
  (or `… but <p> is a CLI provider`). `isLocalVoice` keeps its signature.
- Pinned by `__tests__/trusted-config.test.ts:371` (hosted DNS, metadata, no endpoint, CLI; reader carries the
  endpoint; single-model path) and the `localEndpointHost` range table. The existing D-8.1 fixture's `local-vllm` and
  `lan-box` got loopback / RFC1918 https endpoints.
- `dist/` rebuilt with `npm run build`. `tools/check-bb-dist-fresh.sh` passes.

### HIGH-1 (e) — Docs

Status: **done**.
- `.claude/loa/reference/multi-model-reference.md:102`: the FR-8 paragraph states the rule and the places it applies:
  load, request time, planner, Bridgebuilder.
- `CHANGELOG.md` `## [Unreleased]`: a `### Fixed` entry names the rule (review round r257-1) and the three LOWs. A
  Migration row covers operators who labelled a hosted or CLI provider local. The Sprint 3 test counts are updated:
  locality 10, flatline-locality 9, trusted-config 21.

### LOW-1 — Fixtures

Status: **done**. `localbox` in `tests/unit/adversarial-review-locality.bats` `_cfg` and `tests/unit/flatline-locality.bats`
`_cfg` now declares `allow_insecure_endpoint: "127.0.0.1"` and `keyless: true`. Each model declares
`endpoint_family: chat`, `auth_type: http_api` and `context_window: 32768`. No other S3 suite declares `localbox`
(grep of `tests/unit/*.bats` and `adversarial-review-s3-helpers.bash`). LOC-10 (`:258`) and FLL-9 (`:152`) load the
fixture through `loa_cheval.config.loader.load_config` and assert exit 0. Every existing LOC and FLL case is green.

### LOW-2 — `normalise_keyless`

Status: **done**. `endpoint_policy.py` `normalise_keyless` (`:200`) raises
`[CONFIG-INVALID] providers.<p>: keyless: false conflicts with the literal auth "local"`. Pinned by
`test_keyless_false_beside_literal_auth_local_is_refused` and `test_literal_auth_local_still_normalises_to_keyless`;
the existing `test_literal_auth_local_is_normalised_to_keyless` still passes.

### LOW-3 — `endpoint_policy._main`

Status: **done**. `_main` (`:305`) handles `ConfigError` with its current detail text. Any other exception becomes
`{"error":"config_load_failed","detail":"<Class>: <message>"}` with exit 78. A `ConfigError` from `describe_provider`
also exits 78; `KeyError` stays 64 `provider_not_configured`. Pinned by `test_main_unparseable_config_is_78_with_json`
(`hounfour: [unclosed`), `test_main_any_load_exception_is_78_with_class_and_message` and
`test_main_describe_provider_config_error_is_78_and_missing_provider_stays_64`. Each asserts one JSON line and no
`Traceback`.

## Testing Summary

| Command | Result |
|---|---|
| `cd .claude/adapters && python3 -m pytest -q` | 3256 passed, 6 skipped, 279 subtests, 2 failed |
| the four focused pytest files, new file included | 135 passed |
| bats: locality, flatline-locality, advisory, budget, bb-exit-degraded-callers and `model-health-probe*.bats` | 136/136 |
| `cd .claude/skills/bridgebuilder-review && npm run build && npm test` | 868 tests, 867 pass, 1 fail |
| `tools/check-bb-dist-fresh.sh` | `[OK] BB dist is fresh` |
| `python3 -m loa_cheval.codegen.emit_endpoint_validator_ts --check` | rc 0 |
| `bash tools/check-no-raw-sha256sum.sh` | OK |
| `python3 -m py_compile` on every touched .py | ok |
| `tests/unit/instruction-diet-revert.bats` | pass |
| `tests/integration/flatline-issue-sweep.bats -f 1199` | pass |

- **Pytest baseline.** The two failures are `test_claude_headless_adapter.py::TestCommandConstruction::test_minimal_command`
  and `test_claude_headless_adapter.py::TestEndToEnd::test_complete_round_trip`. Both fail on the base commit too.
- **Node baseline.** The one failure is `__tests__/persona.test.ts`, KF-036.
- **The bats command as given fails twice.** It lists `model-health-probe-configured-provider.bats` explicitly and again
  through the `model-health-probe*.bats` glob. Bats then reports `setup_file failed` for tests 104 and 118, with
  `bats-exec-file: …/9-model-health-probe-resilience.bats.src: No such file or directory`. That is the duplicate file
  argument colliding in the bats source cache, not a test failure. With the list deduplicated, 136 of 136 pass, and each
  probe file passes alone.

The `check-no-raw-sha256sum.sh` script lives under `tools/`, not `.claude/scripts/`. The TypeScript port was not
changed, because `endpoint-validator.py` was not changed.

## Known Limitations

- The planner and Bridgebuilder read the raw config text. An endpoint written as a template such as `{env:LOCAL_URL}`
  is not a URL to them, so the hop is classified hosted (`endpoint_not_local:…`). This fails closed. cheval resolves
  the template at load and applies the rule to the interpolated value.
- `OpenAIAdapter.health_check` still uses the `TransportPolicy` only for an opted-in provider. An `https` local-labelled
  provider with no opt-in probes `/models` through the default client. The probe never sends a prompt. Out of scope.
- The `bats` locality log line still reads `refuses hosted hop <alias> (<provider>)` without the reason. The reason is
  in `hop-locality.py`'s output, which LOC-9 and FLL-8 assert. The shell log format was left unchanged so the existing
  grep-exact assertions stay valid.

## Assumptions

- `[ASSUMPTION decision]` **Provider-block vs model-entry form.** A provider is "labelled" when its block or any model
  entry says `dispatch_group: local`. The provider-block form names `providers.<p>` only. The model-entry form names the
  first labelled model. At request time only the model's `dispatch_group` sets `TransportPolicy.local`, because
  `ProviderConfig` has no `dispatch_group` field. A provider-block label that fails the rule never loads, so this leaves
  no gap.
- `[ASSUMPTION decision]` **Check order at load.** The D-7.2 endpoint checks run before the local-label refusal, so
  their more specific codes still fire. That covers public http, metadata, documentation ranges such as TEST-NET-3
  203.0.113.5, and ULA. The local-label refusal fires for what D-7.2 admits: hosted DNS names and public literals such
  as 8.8.8.8. Every non-local case is refused either way.
- `[ASSUMPTION decision]` **https without an opt-in on a local-labelled provider.** Per the review, this is admitted by
  passing the provider's own canonical local host as the per-call opt-in to `validate_declared_endpoint`, only when the
  scheme is `https`. `http` still requires an explicit `allow_insecure_endpoint`. Unlabelled providers keep the
  loopback and private refusal on https.
- `[ASSUMPTION fact]` **IPv6 brackets.** On the Python path the validator's `split_url` and `_canonical_host` strip
  brackets and compress, so `[0:0:0:0:0:0:0:1]` becomes `::1`. The planner copies that logic. Bridgebuilder strips
  brackets while splitting the authority and canonicalises through `new URL("http://[h]/")`. IPv4-mapped
  `::ffff:127.0.0.1` is not local on any path, because Python's `ipaddress` skips version-mismatched networks.
- `[ASSUMPTION fact]` **The TypeScript port.** `lib/endpoint-validator.generated.ts` does not export an opt-in host
  check: it exports only `loadAllowlist` and `validate`. A small mirror, `localEndpointHost`, sits beside
  `applyLocality` in `config.ts`.
- `[ASSUMPTION decision]` **CLI detection.** A CLI provider is `type: *-headless`, or every model `kind: cli`, as in
  `_is_cli_provider`. The planner also treats an entry with `kind: cli` as CLI. Bridgebuilder's `cli` flag uses the
  provider-level form.
- `[ASSUMPTION decision]` **MODELINV `hop_locality_of`.** It was hardened with the same rule. This goes beyond the four
  places the review named, so the record cannot say `local` for a hop the rule calls hosted.
