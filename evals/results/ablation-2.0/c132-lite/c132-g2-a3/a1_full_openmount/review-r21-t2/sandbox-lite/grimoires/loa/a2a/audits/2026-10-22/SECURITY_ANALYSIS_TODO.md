# Security Analysis Working File — sprint-1 (pr/head.diff, sprint-257 / cycle-129)

Date: 2026-10-22 · Auditor: Paranoid Cypherpunk Auditor · Scope: `pr/head.diff` (80 files) read via `pr/head/`.
`security-audit-scope.sh --json` over `pr/head/`: 23 sinks (12 command_exec, 9 file_operations, 2 database_query), 20 auth files, 17 LLM files, 0 web sources.

## Phase 1A — Recon: untrusted entry points (sources)

| # | Source | Trust | Reaches | Status |
|---|--------|-------|---------|--------|
| S1 | `.loa.config.yaml` `hounfour.providers.*` (endpoint, auth, keyless, allow_insecure_endpoint, dispatch_group, fallback_chain) | operator; ATTACKER on a PR-head checkout (config.ts:669) | cheval loader → adapters; hop-locality.py; Bridgebuilder trusted config | CONFIRMED (MED-002, HIGH-001, LOW-001) |
| S2 | `hounfour.locality` value | operator | adversarial-review.sh, flatline-orchestrator.sh, config.ts, modelinv.py | SAFE (invalid refused by name in all three shell/TS readers; cheval records None) |
| S3 | `flatline_protocol.<gate>.advisory_voices[]` | operator | yq → jq regex → `_adv_invoke_hop` argv | SAFE (hop-name regex `[A-Za-z0-9._/:-]{1,128}`, index-only logging of bad elements) |
| S4 | `GITHUB_BASE_REF`, `gh pr view` baseRefName | CI / GitHub | `git show refs/remotes/origin/<base>:.loa.config.yaml` | SAFE (`isSafeRefName`, execFileSync argv, no shell) |
| S5 | `BRIDGEBUILDER_TRUSTED_CONFIG` env text | repository variable | yq via stdin | SAFE (stdin, not argv; parse failure → no provider trusted) |
| S6 | Head `.loa.config.yaml` on a PR | ATTACKER | `parseProviderDecls` → head-only refusal list only | PARTIAL (keyless/insecure refused; endpoint/auth not covered → MED-002) |
| S7 | Remote OpenAI-compatible server responses (400 bodies, 3xx, `reasoning_content`, `<think>`) | REMOTE / possibly hostile local server | `_names_response_format`, `refuse_redirect`, `strip_thinking_blocks` | PARTIAL (LOW-003 substring heuristic; redirects refused; strip regex linear) |
| S8 | `--provider <name>` CLI arg of model-health-probe.sh | operator | `_CONFIGURED_NAME_RE`, `grep -qxF` against loader names, `${!auth_env}` indirect expansion | SAFE (name regex; auth_env from `_ENV_AUTH` regex) |
| S9 | Catalog `price_source` / `price_date` | catalog / operator | pricing.py date parsing | SAFE (regex + fromisoformat, non-string dropped) |
| S10 | Bridgebuilder run JSON read back by dispatcher.sh / spiral-harness.sh | own output | `jq -r ... join(", ")` into a log line | SAFE (jq, no eval) |

## Phase 1A — Recon: dangerous sinks

| # | Sink | File:line | Status |
|---|------|-----------|--------|
| K1 | Outbound HTTP with credential (`Authorization: Bearer`) | openai_adapter.py:172-173, 850-865 | CONFIRMED LOW-002 (plaintext http to opted-in RFC1918 host with a non-keyless auth) |
| K2 | Outbound HTTP destination = `providers.*.endpoint` from project config | endpoint-validator.py:1291 (`_declared_endpoint` admits any https host); loader.py:704 | CONFIRMED MED-002 (credentialed built-in provider redirectable from a head checkout) |
| K3 | Proxy env / redirect following on local hops | base.py:118-163, 270-345, 375-430, 465-630 | PARTIAL → MED-001 (policy constructed only by openai_adapter.py:217) |
| K4 | `git show` / `git rev-parse` / `gh pr view` subprocess | config.ts:552-581 | SAFE (execFileSync argv, ref regex) |
| K5 | `yq` subprocess on config text | config.ts:517-528 | SAFE (stdin) |
| K6 | `python3 -I hop-locality.py -- <hops>` | adversarial-review.sh:3834; flatline-orchestrator.sh:729 | SAFE (argv, `--` separator, fail-closed on no row) |
| K7 | `python3 -m loa_cheval.metering.pricing --alias …` | adversarial-review.sh:3875 | SAFE (argv; output parsed by anchored sed) |
| K8 | jq programs with `--arg`/`--slurpfile` | adversarial-review.sh:3972-4040 | SAFE (data via --arg/--slurpfile/files) |
| K9 | curl via `endpoint_validator__guarded_curl --allow-insecure-endpoint` | endpoint-validator.sh:406-411 | SAFE (`--proto =http,https --max-redirs 0 --noproxy '*'`, validator first) |
| K10 | stdout/log of provider metadata | endpoint_policy.py:200,224; model-health-probe.sh:1505 | CONFIRMED LOW-005 (interpolated endpoint printed verbatim) |
| K11 | `process.exitCode` / caller exit-code mapping | main.ts:750; dispatcher.sh:78-91; spiral-harness.sh:697-712; entry.sh:120 | SAFE (3 = completed-degraded consistently; preflight moved to 4) |
| K12 | MODELINV emit with new fields | modelinv.py:684-700 | SAFE (enum-checked; destination stringified) — LOW-001 consistency only |

## Phase 1B — Traces

- S1→K2: `load_config` → `validate_providers` → `check_endpoint` → `validate_declared_endpoint` (`validate(url, {}, _declared_endpoint=True)`) → any https host passes step 8 skipped (endpoint-validator.py:1291-1297). `_build_provider_config` then hands `auth` (LazyValue over `{env:VAR}`) and `endpoint` to the adapter. Bridgebuilder voices dispatch through `cheval-delegate.ts` (`--model provider:model`), cheval reads the checkout's `.loa.config.yaml`. Trusted config (config.ts:605-712) never compares endpoint/auth → MED-002.
- S1→HIGH-001: `applyLocality` (config.ts:739) keeps a voice when `isLocalVoice` (726) says local; `isLocalVoice` reads `dispatch_group` only. cheval `chain_resolver.py:92` appends the primary's `fallback_chain` entries to the walk → a hosted hop is reachable inside the call. `hop-locality.py:123-133` refuses the same entry for the shell planners.
- S1→K3: `endpoint_policy.validate_providers` (143-176) admits `allow_insecure_endpoint` for any non-CLI provider type; `TransportPolicy` constructed only in `OpenAIAdapter._transport_policy` (openai_adapter.py:217-222); anthropic_adapter.py / google_adapter.py (untouched) call `http_post`/`http_post_stream`/`http_get` without `policy` → MED-001.
- S7→K-parser: `_names_response_format` (openai_adapter.py:101-111) is a substring test on the whole 400 body → LOW-003; retry re-sends the same prompt to the same server (no new destination).
- K1: `validate_providers` never couples `allow_insecure_endpoint` with `keyless`; `complete()` attaches `Bearer` unless keyless (openai_adapter.py:172-173) → plaintext credential on the opted-in http hop → LOW-002.
- K10: `interpolate_config` is eager for every string except `providers.*.auth` (interpolation.py:40) → an endpoint carrying `{env:…}` is printed resolved by `describe_provider` and the probe's `log_info` → LOW-005.
- Deferred (time budget): bats fixtures under `tests/unit/*.bats` reviewed by test name only; TypeScript tests not executed (no node_modules).

## Status legend
PENDING → CONFIRMED / SAFE / PARTIAL / N/A. All rows resolved; nothing left PENDING.
