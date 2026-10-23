# Security analysis working file — sprint-1 audit (PR cycle-126 sprint-247), 2026-10-23

Scope: `pr/head.diff` (65 files). `security-audit-scope.sh --json` over `pr/head`: sources 0, sinks 26 (command_exec 14, file_operations 11, database_query 1), auth files 24, llm files 23. No `.reviewignore`.

## Sources (untrusted or semi-trusted inputs)

| # | Source | Location | Trust | Status |
|---|--------|----------|-------|--------|
| S1 | Provider HTTP error body (400/413) → `is_context_limit_message` / `parse_context_limit` | `anthropic_adapter.py:361`, `:503`; `ceiling.py:153-198` | configured endpoint (provider or gateway) | CONFIRMED → MED-001 (unvalidated numbers become a bound); LOW-001 (raw text to stderr) |
| S2 | `.run/ceiling-observed.json` (state file, read every hop) | `ceiling.py:225-261` | local user / same host | PARTIAL → MED-003 (unlocked RMW, growth), LOW-006 (no expiry); tampering = DoS of one entry, same trust as code exec |
| S3 | `LOA_CHEVAL_CEILING_OBSERVED_PATH`, `LOA_CHEVAL_MAX_INPUT_TOKENS`, `LOA_CHEVAL_UNCALIBRATED_CEILING`, `LOA_CHEVAL_LEGACY_CEILING` | `ceiling.py:59-82`, `:211-222` | operator env | SAFE (parsed defensively; path redirect = env-level trust) |
| S4 | Catalog `params.beta_headers` | `anthropic_adapter.py:163-181` | operator (System Zone) | SAFE with gap → LOW-002 (`$` admits trailing newline; http.client rejects) |
| S5 | Catalog `pricing.long_context` | `pricing.py:281-300` | operator | SAFE with gap → LOW-003 (`inf`, <1.0 accepted) |
| S6 | Catalog `endpoint` → `http_get` / `count_tokens` / `health_check` | `base.py:309-355`; `anthropic_adapter.py:591-619`, `:661-690` | operator | LOW-004 (no scheme check / body cap; same as http_post) |
| S7 | `count_tokens` response `input_tokens` | `anthropic_adapter.py:617-619` | provider | SAFE (positive int only; advisory; replaces estimate at the gate — a low count could let an oversize prompt through to the provider, which then refuses it: no security impact) |
| S8 | Probe tool argv (`--model`, `--write-catalog PATH`, `--tier`, `--itpm`) | `ceiling-probe-live.py:179-193` | operator | SAFE (tier choices; model only matched as a YAML block key; ValueError on no block) |
| S9 | Probe tool stream events / HTTP error bodies | `ceiling-probe-live.py:62-89` | provider | SAFE (JSON parsed defensively; bodies truncated to 300 chars in the record) |
| S10 | Request `messages` content → `estimate_input` non-ASCII share / tool detection | `base.py:967-1002` | caller | SAFE (pure counting) |
| S11 | Alias/model strings in shell (`flatline_voice_max_tokens`, `_anthropic_ceiling_json` yq query) | `flatline-orchestrator.sh:936-946`; `loa-status.sh:800-808` | catalog / orchestrator | SAFE (assoc-array keys not arithmetic-evaluated; yq interpolates the catalog's own alias target) |

## Sinks

| # | Sink | Location | Status |
|---|------|----------|--------|
| K1 | `anthropic-beta` request header | `anthropic_adapter.py:298-300`, `:607-609` | SAFE (allowlist) / LOW-002 |
| K2 | `.run/ceiling-observed.json` write (`mkstemp` + `os.replace`) | `ceiling.py:264-306` | MED-003, LOW-005 (0600 mode); symlink: `os.replace` replaces the link, does not follow — not a defect |
| K3 | `.claude/defaults/model-config.yaml` write (`--write-catalog`) | `ceiling-probe-live.py:167-176` | MED-008 (System Zone write surfaced to agents), LOW-005 |
| K4 | stderr `_error_json` with provider text + absolute path | `cheval.py:2016`, `:2032` | LOW-001 |
| K5 | MODELINV envelope `models_failed[].message_redacted` | `cheval.py:2022` | SAFE (emit-time redaction `modelinv.py:213-223`) |
| K6 | Live paid API calls (probe tool, `count_tokens`) | `ceiling-probe-live.py:53-63`; `anthropic_adapter.py:611` | PARTIAL → MED-008 (probe spend by agents); count call bounded by `read_timeout=60` |
| K7 | Generated bash maps sourced by orchestrators (`MODEL_MAX_OUTPUT`) | `gen-adapter-maps.sh:249-264`; `generated-model-maps.sh:242-262` | SAFE (same generator pattern as existing maps; catalog-controlled keys) |
| K8 | `urllib.request.urlopen` GET | `base.py:342` | LOW-004 |

## Second-order flows

- S1 → K2 → S2 → `input_bound` (`ceiling.py:122`) → pre-flight/hop preempt: CONFIRMED (MED-001).
- K2 → `loa-status.sh:811-814` → status line: CONFIRMED (MED-004, zero row → `observed -1`).
- Retry shrink lost on final attempt → `RetriesExhaustedError` → walk: CONFIRMED (HIGH-002, PoC).

## Deferred / unable to assess

- Bridgebuilder `dist/` artefacts: no node toolchain; generated tables checked by the review against the yaml.
- `core/truncation.ts` at the PR base: not in the bundle (HIGH-003 confidence medium).
