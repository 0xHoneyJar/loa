# Security analysis working file — sprint-1 audit (PR sprint-257), 2026-10-22

Scope: `pr/head.diff` (80 files, 23 generated `dist/`), cited as `head/<path>:<line>`.

## Sources (untrusted or semi-trusted entry points)

| # | Source | Trust | Reaches | Status |
|---|--------|-------|---------|--------|
| S1 | `.loa.config.yaml` `hounfour.providers.*` (endpoint, auth, keyless, allow_insecure_endpoint, dispatch_group) | operator; attacker on a PR-head checkout | loader → cheval adapters; hop-locality.py; Bridgebuilder trusted view; probe | CONFIRMED (HIGH-001, HIGH-002, MED-001, LOW-001, LOW-003) |
| S2 | `hounfour.locality`, `flatline_protocol.*.advisory_voices`, `advisory_timeout_seconds` | operator | yq → bash case/regex → jq/python argv | SAFE (validated: enum / `[A-Za-z0-9._/:-]{1,128}` / `_conf_uint`) |
| S3 | Provider HTTP responses (status, body, `reasoning_content`, `<think>`) | remote server | `_names_response_format`, thinking strip, redirect refusal | PARTIAL (LOW-004: server-controlled schema downgrade) |
| S4 | Bridgebuilder exit code / stdout JSON | child process | dispatcher.sh, spiral-harness.sh | CONFIRMED (MED-003) |
| S5 | `git show refs/remotes/origin/<base>`, `GITHUB_BASE_REF`, `BRIDGEBUILDER_TRUSTED_CONFIG` | CI platform / repo settings | loadTrustedConfig | SAFE (isSafeRefName; execFileSync, no shell) |
| S6 | `--provider <name>` CLI arg | operator | probe `_configured_providers` grep -xF, `_CONFIGURED_NAME_RE` | SAFE |
| S7 | `{env:VAR}` names in config | operator | probe `${!auth_env}` indirect expansion | SAFE (loader's `secret_env_allowlist` refuses before the probe reads; regex-validated name) |

## Sinks

| # | Sink | Guard | Status |
|---|------|-------|--------|
| K1 | `jq --arg/--argjson`, `yq eval` with spliced keys | only internal `config_key`; hop names validated; envelopes as files | SAFE |
| K2 | `python3 -I hop-locality.py -- <hops>` | `--`; fail-closed to hosted | SAFE |
| K3 | curl via `endpoint_validator__guarded_curl` (`--proto =http,https --max-redirs 0 --noproxy '*'`) | validator first | SAFE |
| K4 | httpx/urllib in `providers/base.py` under TransportPolicy | check_url, trust_env=False, refuse_redirect | PARTIAL (MED-002 CA bundle; MED-001 non-OpenAI adapters never get a policy) |
| K5 | MODELINV audit chain (`destination`, `hop_locality`) | emit validates enums | PARTIAL (HIGH-001 records a label; LOW-005 cli-subprocess for unknown) |
| K6 | `log_info`/`log_warn` in the probe | reasons capped | PARTIAL (LOW-003 URL with query printed) |
| K7 | Bridgebuilder voice dispatch → cheval (checkout config) | trusted view planner-side only | CONFIRMED (HIGH-002) |

## Reproductions run against `pr/head`

- `hop-locality.py` with a public-https provider labelled `dispatch_group: local` → `local`; provider-block label → `local`.
- `endpoint_policy.validate_providers` accepts: public https labelled local; keyed `http://10.0.0.5` with opt-in; `type: anthropic` over http with opt-in.
- `validate_declared_endpoint`: shipped defaults (openai, google, anthropic, bedrock template) admit; opt-in table behaves (mismatch, userinfo, traversal, metadata, ULA, `127.0.0.1:8000` refused); `?api_key=` query admitted.
- PR Python suites in a head-over-framework tree: 123 passed.
- Not run: bats (needs full tree), TypeScript tests (needs node_modules), dist rebuild.
