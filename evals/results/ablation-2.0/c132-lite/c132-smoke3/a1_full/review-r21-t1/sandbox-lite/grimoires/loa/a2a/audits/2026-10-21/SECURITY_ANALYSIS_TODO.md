# Security analysis working file — sprint-1 (PR: sprint-257, cycle-129)

Scope: `pr/head.diff` (80 files). Sources and sinks catalogued in Phase 1A, traced in Phase 1B.
Status: `CONFIRMED` (defect found) · `SAFE` (traced, no defect) · `PARTIAL` · `N/A` · `DEFERRED`.

## Sources (untrusted or operator-controlled input)

| # | Source | Trust | Location | Status | Note |
|---|--------|-------|----------|--------|------|
| S1 | `hounfour.providers.*` (endpoint, auth, keyless, allow_insecure_endpoint, dispatch_group) | operator; PR head on a PR-head checkout | `head/.claude/adapters/loa_cheval/config/loader.py:645-705` | PARTIAL | endpoint rule enforced (SAFE); opt-in admitted for every provider type (CONFIRMED M1); `dispatch_group: local` never cross-checked against the endpoint (CONFIRMED M2) |
| S2 | `hounfour.locality` | operator | `adversarial-review.sh:238-250`, `flatline-orchestrator.sh:704-716`, `config.ts:700-704` | SAFE | invalid value refused by name on all three paths |
| S3 | `flatline_protocol.<gate>.advisory_voices` | operator | `adversarial-review.sh:3799-3824` | SAFE | yq tag check, regex on each alias, index-only warnings |
| S4 | Server HTTP response (status, body, redirects, `reasoning_content`, `<think>`) | untrusted | `openai_adapter.py:101-111, 288-294`; `openai_streaming.py:56-97` | PARTIAL | 400 heuristic lets the server downgrade structured output (CONFIRMED M3); unterminated `<think>` empties content (L6) |
| S5 | Model findings (dissent primary/companion/advisory) | untrusted | `adversarial-review.sh:3915-3985` | SAFE | process_findings schema, hallucination filter, control-char strip on `error`, files not argv |
| S6 | `GITHUB_BASE_REF`, `gh pr view` base name | CI env / GitHub | `config.ts:548-552, 626-636` | SAFE | `isSafeRefName`, `--` separator, no option injection |
| S7 | `BRIDGEBUILDER_TRUSTED_CONFIG` text | repository variable | `config.ts:620-624` | SAFE | yq via stdin, 5 s timeout, parse failure → no provider trusted |
| S8 | PR head `.loa.config.yaml` (BB pull-request mode) | attacker | `config.ts:674-693` | PARTIAL | only keyless/insecure flags refused; cheval's own config read is outside this control (CONFIRMED M4 — doc overstates) |
| S9 | `describe-provider` JSON → bash (`auth_env`, `endpoint`, `models[]`) | own helper | `model-health-probe.sh:1440-1452, 1495` | SAFE | `auth_env` regex-validated in Python before `${!auth_env}`; names regex `_CONFIGURED_NAME_RE` |
| S10 | Catalog prices (`pricing --alias`) → shell arithmetic | own helper | `adversarial-review.sh:3866-3905` | SAFE | 1-12 digit regex, fallback said by name |

## Sinks

| # | Sink | Location | Status | Note |
|---|------|----------|--------|------|
| K1 | Outbound HTTP (httpx / urllib) with policy | `base.py:118-163, 296-340, 529-535` | SAFE for OpenAI adapter | `trust_env=False`, `follow_redirects=False`, `_NoRedirect`, ProxyHandler({}); tested against a real stub (123 pytest pass) |
| K2 | Outbound HTTP without policy (anthropic/google adapters) | `anthropic_adapter.py:334` (unchanged) | CONFIRMED M1 | loader admits http+opt-in on these types; no request-time rules |
| K3 | curl via `endpoint_validator__guarded_curl` | `endpoint-validator.sh:403-412` | SAFE | `--proto =http,https --max-redirs 0 --noproxy '*'` only for the opted-in host |
| K4 | `git show`/`git ls-tree`/`gh pr view` (execFileSync) | `config.ts:541-569` | SAFE | argv arrays, safe ref regex |
| K5 | jq programs with model text | `adversarial-review.sh:3944-3970` | SAFE | `--slurpfile`/`--arg`/`--argjson` only |
| K6 | MODELINV audit chain (`destination`, `hop_locality`, `locality_mode`) | `modelinv.py:436-495, 687-700` | CONFIRMED H1/M2 | `hop_locality_of` reads the model entry only; label trusted |
| K7 | Budget gate (exit 4 before dispatch) | `adversarial-review.sh:4321-4341` | CONFIRMED H2 | sum of voices vs per-call contract; reproduced on this diff: 955c > 200c |
| K8 | Process exit code (BB exit 3) | `main.ts:742-750`, `dispatcher.sh:75-91`, `spiral-harness.sh:697-712`, `entry.sh:118-120` | SAFE | all in-tree callers updated; exit 4 for missing deps |
| K9 | Handoff file `bb-stdout.json` | `dispatcher.sh:65-72` | SAFE | under per-cycle `$TMPDIR` handoff dir |
| K10 | Probe log lines with resolved endpoint | `model-health-probe.sh:1505`; `endpoint_policy.py:200` | CONFIRMED L8 | resolved endpoint printed verbatim |

## Deferred / not assessable here

- Bridgebuilder TypeScript tests and `dist/` parity (no `node_modules`, no network) — DEFERRED.
- `emit_endpoint_validator_ts --check` (no `jinja2`) — DEFERRED.
- bats suites: not re-run in this audit; the review's run (all pass on an executable filesystem) is the reference.
