# Loa open-weight and local-model readiness (cheval substrate)

Verified against: `main @ 864069f2` (v2.0.0-rc.4), 2026-10-14. Read-only audit. No cheval calls, no network. Every claim cites `path:line`. Claims marked **[inference]** are reasoned from code, not executed. Claims about third-party servers (vLLM, Ollama, Bedrock catalog) are marked **[external, unverified here]**.

## Bottom line

- An operator can point cheval at a local OpenAI-compatible server today, with no System Zone edit. The provider must be named something other than `openai`, use `type: openai_compat` (or `openai`), and every model must declare `endpoint_family`, `auth_type`, `dispatch_group`, `capabilities` and `context_window`. The auth value must be a non-empty string even when the server ignores it. The documented Azure example would fail at load as written.
- Plain `http://localhost` is not refused on the cheval Python path. The endpoint validator that refuses http, loopback and RFC1918 is used only by bash callers such as the health probe.
- The gates are the problem, not the transport. A model with an open-weight id has `unknown` family. The dissent companion is then never counted as an independent voice. Bridgebuilder refuses any provider outside `anthropic`, `openai` and `google`. Structured output is never enforced on the chat-completions path, so every local voice runs on the tolerant parser plus the KF-004 repair loop. That repair loop sends payloads to Anthropic first when a key is present.
- The cycle-124 "model-generation floor" refuses nothing. It is a set of alias retargets plus pytest invariants over the Anthropic catalog.

## 1. Provider types and wire protocols

The adapter registry is one hard-coded dict, `_ADAPTER_REGISTRY` (`.claude/adapters/loa_cheval/providers/__init__.py:48-59`). An unknown type raises `ConfigError("Unknown provider type: '...'. Supported: [...]")` (`providers/__init__.py:64-66`).

| `type` | Adapter | Wire protocol | Cite |
|---|---|---|---|
| `openai` | OpenAIAdapter | `POST {endpoint}/chat/completions` or `POST {endpoint}/responses`, chosen by `endpoint_family`, Bearer auth | `providers/openai_adapter.py:144-155` |
| `openai_compat` | OpenAIAdapter (same class) | same as `openai` | `providers/__init__.py:51` |
| `anthropic` | AnthropicAdapter | Messages API, `x-api-key`, `output_config.format` for schemas | `providers/anthropic_adapter.py:292-306` |
| `google` | GoogleAdapter | Gemini generateContent (no output schema support: 0 `output_schema` references) | `providers/google_adapter.py` (grep count 0) |
| `bedrock` | BedrockAdapter | Bedrock Converse, Bearer token, URL `https://bedrock-runtime.{region}.amazonaws.com/model/{id}/converse` | `providers/bedrock_adapter.py:212-215`, `:251-255` |
| `codex-headless`, `claude-headless`, `gemini-headless` (routes to agy), `cursor-headless`, `grok-headless` | CLI subprocess adapters | `codex exec`, `claude -p`, `agy -p`, `cursor-agent -p`, `grok --prompt-file` | `providers/__init__.py:20-47`, `:54-58` |

Other hard-coded enums that matter:

- `kind: cli` maps a provider name to a CLI adapter only for `anthropic`, `openai` and `google` (`.claude/adapters/cheval.py:352-356`). Any other CLI needs a new adapter class.
- `auth_type` must be one of `headless`, `http_api`, `aws_iam` (`config/loader.py:863`).
- `endpoint_family` must be `chat` or `responses` (`providers/openai_adapter.py:63`, `config/loader.py:860`).
- `model_aliases_extra.provider` is locked to `openai`, `anthropic`, `google`, `bedrock` (`.claude/data/trajectory-schemas/model-aliases-extra.schema.json:42-43`).
- The advisory JSON schema lists only four types (`.claude/schemas/model-config.schema.json:78`). No script or test validates against it; the only references are the file itself and `checksums.json` (grep over `.claude/` and `tests/`).
- The health probe accepts only `openai|google|anthropic|bedrock` (`.claude/scripts/model-health-probe.sh:1589-1591`).
- Bridgebuilder's key map has only `anthropic`, `openai`, `google` (`.claude/skills/bridgebuilder-review/resources/config.ts:135-139`).

## 2. A local OpenAI-compatible server through a custom `endpoint`

### Request path

`.loa.config.yaml` `hounfour.providers.<name>` is deep-merged over the System defaults (`config/loader.py:610-611`). Then `_build_provider_config` builds `ProviderConfig(type=prov.get("type","openai"), endpoint=..., auth=...)` (`cheval.py:489-549`). `get_adapter` selects OpenAIAdapter. `complete()` enforces the context window, routes by `endpoint_family`, reads auth, and posts to `{endpoint}/chat/completions` (`providers/openai_adapter.py:126-166`).

### What breaks or refuses, item by item

| Item | Behaviour | Refusal text or code path |
|---|---|---|
| Documented Azure example | Fails at load: the example model has no `auth_type` or `dispatch_group` and no `endpoint_family` (`.loa.config.yaml.example:1099-1113`). Inference covers only `*-headless` types (`config/loader.py:631-636`, `:909-914`). | `[CONFIG-INVALID] providers.azure-openai.models.gpt-5-azure is missing required 'auth_type' (cycle-110 SDD §3.2)...` (`config/loader.py:986-994`) |
| Credential env var | `{env:AZURE_OPENAI_KEY}` is refused unless `secret_env_allowlist` is extended. The core allowlist is `^LOA_`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `MOONSHOT_API_KEY`, `GOOGLE_API_KEY`, `GEMINI_API_KEY` (`config/interpolation.py:24-31`). | `Environment variable '...' is not in the allowlist.` (`config/interpolation.py:253-258`). Extension point: `config/loader.py:672-676`. |
| No-key server (Ollama, llama.cpp) | Auth must be a non-empty string; a literal such as `"local"` passes and is sent as `Authorization: Bearer local`. | `No auth configured for provider '...'` or `API key is empty for provider '...'` (`providers/base.py:1096-1112`) |
| `parse_provider_model_id` | Splits on the first colon only, so `local:qwen3-coder:30b` parses as provider `local`, model `qwen3-coder:30b` (`types.py:750-791`). No refusal. | none |
| Model must be declared | An undeclared model id fails chain resolution. | `Model 'p:m' not declared in providers.p.models (available: [...])` (`routing/chain_resolver.py:211-218`) |
| `endpoint_family` | Load-time check runs only for the provider literally named `openai` (`config/loader.py:1048-1049`). A custom provider skips it but fails at request time if absent. Use `chat`; most local servers do not serve `/responses` **[external, unverified here]**. | `OpenAI model '...' lacks required 'endpoint_family' field...` (`providers/openai_adapter.py:110-118`) |
| Capability gate | Requires `chat` always and `tools` when the request carries tools. A model with empty `capabilities` is skipped, not failed, and the chain walks on (`routing/capability_gate.py`, `_derive_required_capabilities`; `routing/chain_resolver.py:182`). | `models_failed[].reason = "capability_mismatch"` (`routing/capability_gate.py` module docstring) |
| `model_aliases_extra` | Cannot register the model: the provider enum is locked and the endpoint pattern is `^https://` (`model-aliases-extra.schema.json:42-43`, `:60-61`). This path feeds the skill resolver, not cheval's loader (`.claude/scripts/lib/model-resolver.py:421`). Use `hounfour.providers` instead. | JSON-schema enum violation |
| Pricing and ledger | No pricing means `pricing_source: "unknown"`, cost 0, counted as unknown (`metering/ledger.py:170-173`; `metering/pricing.py:358-421`). An explicit `{input_per_mtok: 0, output_per_mtok: 0}` is truthy, so the row reads `pricing_source: "config"` at cost 0 (`metering/pricing.py:285-293`). Usage absent from the server marks `usage_source: estimated` (`providers/openai_adapter.py:712-717`). | none |
| Network guard | Not on this path. `cheval-network-guard.sh` wraps only the shell `curl`, `wget`, `nc` and `ftp`, and only when `LOA_NETWORK_RESTRICTED=1` in benchmark replay (`.claude/scripts/lib/cheval-network-guard.sh:5-9`). Its allowlist is exact-host (`:31-37`, `:77`); `localhost` is absent but addable through `LOA_NETWORK_ALLOWLIST_EXTRA` (`:40-45`). | `[NETWORK-GUARD-BLOCKED] ... not in allowlist`, exit 78 (`:88`) |
| https, loopback, RFC1918 | The cheval Python HTTP path has no scheme or IP check (no `endpoint_validator` reference under `loa_cheval/`). The bash endpoint validator refuses non-https and loopback, private and link-local IPs (`.claude/scripts/lib/endpoint-validator.py:1035-1039`, `:134-139`). It guards the health probe and other bash callers (`model-health-probe.sh:132-137`). | `ENDPOINT-INSECURE-SCHEME`; `IP ... is loopback`; `IP ... is in a private range` |
| Context window | Defaults to 128000 when undeclared (`cheval.py:520`, `types.py:135`). Undeclared on an 8K or 32K local model, cheval overfills and the server rejects. The ceiling policy returns no bound for entries without `probed_ceiling` or `effective_input_ceiling` (`routing/ceiling.py:162-165`). Only `enforce_context_window` applies (`providers/base.py:1006-1025`). | `ContextTooLargeError` |
| Output budget | Non-Anthropic default is `min(16000, max_output_tokens)`, else 4096 when undeclared (`providers/base.py:186-209`, `:170`). | none |
| Structured JSON | The chat body never carries a schema (`providers/openai_adapter.py:323-341`). Only the `responses` body sets `text.format` json_schema (`:435-447`). `schema_enforced` is false on chat (`:163-165`). | MODELINV `schema_enforced=false` |
| Streaming recovery | Always on for OpenAI-type streams (`providers/openai_streaming.py:83-95`). The first-token deadline is 30 s by default (`streaming/recovery.py:26`), and only `delta.content` and `refusal` feed the tracker (`openai_streaming.py:155-178`). A CPU server processing a large prompt, or a reasoning model streaming `reasoning_content`, may abort as `first_token_deadline` **[inference]**. Per-model `streaming_recovery` overrides exist (`streaming/recovery.py:91-104`). | `StreamingRecoveryAbort` |
| Thinking traces | `<think>` blocks and `reasoning_content` are not handled anywhere (grep over `loa_cheval/` and `adversarial-review.sh`). Inline `<think>` text lands in `content`. | none |
| Health probe | The provider enum refuses a custom name (`model-health-probe.sh:1589-1591`); the OpenAI probe is hard-coded to `https://api.openai.com/v1/models` and needs `OPENAI_API_KEY` (`:1046-1058`). The adapter's own `health_check` uses the configured endpoint (`providers/openai_adapter.py:737-762`). Do not set `probe_required`, which treats an entry as unavailable until the probe confirms it (`types.py:160-162`). | `invalid provider: ... (allowed: openai|google|anthropic|bedrock)`, exit 64 |

Within-company chains still hold: every `fallback_chain` entry must share the primary's provider name (`routing/chain_resolver.py:254-275`).

Minimal working declaration **[inference, not executed]**:

```yaml
hounfour:
  providers:
    local:
      type: openai_compat
      endpoint: "http://127.0.0.1:8000/v1"
      auth: "local"
      models:
        qwen3-coder-30b:
          endpoint_family: chat
          auth_type: http_api
          dispatch_group: local-vllm
          capabilities: [chat]
          context_window: 32768
          max_output_tokens: 8192
          pricing: {input_per_mtok: 0, output_per_mtok: 0}
  aliases:
    local-reviewer: "local:qwen3-coder-30b"
```

## 3. The cycle-124 model-generation floor

- **What it is.** Alias retargets (`opus` to `claude-opus-5`, `fable` to `claude-fable-5-1`), typed Anthropic params, larger Anthropic `max_tokens` defaults, wire schemas and strict dissent parsing (`CHANGELOG.md:142-163`; `docs/architecture/ADR-004-model-generation-floor.md:19-30`). Old ids "stay in the catalog and resolve by explicit pin" (`CHANGELOG.md:150`).
- **Where it is enforced.** As pytest invariants over the live Anthropic catalog (`.claude/adapters/tests/test_anthropic_catalog_floor.py:1-8`, `:31-66`). No resolver or loader rejects a model for its generation.
- **Would it refuse an open-weight model?** No. Nothing in the loader, resolver or adapters checks generation or vendor. The cost is indirect: ADR-004 sizes defaults and prompt budgets for the current Claude generation and says gates are only as strong as their weakest executor (`ADR-004-model-generation-floor.md:15`).
- **Bedrock non-Anthropic ids.** The adapter builds a generic Converse URL from any id (`providers/bedrock_adapter.py:212-215`). It checks only the region prefix (`:415-440`) and parses text and `reasoningContent` blocks generically (`:563-577`). Nothing refuses `us.meta.*`, `us.deepseek.*` or `mistral.*` ids. Anthropic coupling remains in the remediation text (`:519-522`), the `prefer_bedrock` fallback to `api.anthropic.com` (`:340`), the thinking translation that always emits Anthropic `adaptive` shapes (`:771-803`), the absence of output-schema support (0 `output_schema` references), and the absence of streaming (`:186-191`). The probe allowlist covers three regions (`.claude/scripts/lib/allowlists/loa-providers.json`). Whether Converse serves a given open-weight id is **[external, unverified here]**.

## 4. Voices, companions, scorers, Bridgebuilder

### The rules

- **Never substitute across companies.** Chains are within-company (`routing/chain_resolver.py:1-8`, `:96-101`). An exhausted Flatline voice is dropped, not replaced (`.claude/loa/reference/multi-model-reference.md:28`).
- **Two voices, companion chain.** Dissent plans a companion from the other family. An Anthropic primary gets the OpenAI chain; every other family gets `opus` then `claude-headless` (`.claude/scripts/adversarial-review.sh:2340-2345`, `:2398-2419`). `companion_chain` reads only its `anthropic` and `openai` keys (`.loa.config.yaml.example:1466-1468`).
- **Independence.** A companion counts only when both answering families are known and differ; `unknown` never counts (`adversarial-review.sh:3428-3445`). Otherwise it is `counted_as: duplicate_voice`.
- **Verdict quality.** APPROVED requires `voices_succeeded == voices_planned`; partial success is DEGRADED (`.claude/adapters/loa_cheval/verdict/quality.py:6-14`, `:185-207`). On `security_audit`, a missing companion route is a `DEGRADED_SECURITY_REVIEW` on every audit (`.loa.config.yaml.example:1471-1476`, `:1516-1517`).
- **Flatline scorers.** No separate judge model. Voices cross-score each other's items against `flatline-scorer.wire.json` (`.claude/scripts/flatline-orchestrator.sh:138`, `:1894-1924`). A Flatline voice is therefore also a scorer.

### Could an open-weight model fill each role today?

| Role | Today | Why |
|---|---|---|
| Dissent primary (`flatline_protocol.code_review.model`) | Yes, with caveats | The id resolves through cheval like any alias. Its family is `unknown`: `_adv_family_of` reads only the System Zone catalog and name rules (`adversarial-review.sh:2305-2337`, `:2843`). |
| Dissent companion | Not as a counted voice | Families are hard-coded to `anthropic` and `openai` (`adversarial-review.sh:2398-2410`). An operator chain naming a local model succeeds but is a `duplicate_voice` (`:3432-3441`). The config tells operators to "list the model in the catalog", which is a System Zone edit (`.loa.config.yaml.example:1469-1471`). |
| Flatline primary, secondary or tertiary | Yes | `validate_model` accepts any model the project declares (`flatline-orchestrator.sh:615-665`). Flatline has no family check (no `family` reference in the script). Content must pass `qualify_flatline_content` (`:325`). |
| Flatline scorer | Implicitly yes | It is the same voice (`flatline-orchestrator.sh:1894-1924`). KF-041 shows a scorer can null every score while its review succeeded. |
| Bridgebuilder voice | No | `validateApiKeys` rejects any provider missing from the key map: `Unknown provider: <name>` (`.claude/skills/bridgebuilder-review/resources/config.ts:384-388`). A model under `provider: openai` would be sent to the `openai` provider's endpoint. Fixing this needs a System Zone edit. |
| Bridgebuilder routing | Transport is generic | All calls go through cheval (`resources/adapters/adapter-factory.ts:3-8`). The blocker is the key gate alone. |

### What a weaker model would hit

- **Unenforced output everywhere.** `--json-schema` is enforced only on Anthropic `structured_json` entries and `claude-headless` (`cheval.py:3188-3196`). OpenAI enforces only on `/responses` (`openai_adapter.py:435-447`). Bedrock and Google never enforce. A local voice always takes the tolerant path.
- **KF-004 repair loop.** Unenforced findings that fail validation get one repair per hop. The repair chain is `tiny` (Anthropic key present), then `claude-headless`, then the answering voice (`.loa.config.yaml.example:1487-1492`). `tiny` is `anthropic:claude-haiku-4-5-20251001` (`.claude/defaults/model-config.yaml:1127`). `LOA_ADVERSARIAL_REPAIR_MODEL` pins the chain (`adversarial-review.sh:578-580`).
- **Strict wire schemas.** Schema-enforced payloads are parsed strictly. Any rejected finding makes a review or audit DEGRADED unconditionally (`CHANGELOG.md:153`).
- **Empty content (KF-002, KF-003).** Streaming recovery aborts empty or stalled streams with typed exits (`grimoires/loa/known-failures.md:181`). Local servers will trip the 30 s first-token deadline before they produce empty content.
- **Malformed output (KF-011).** A `raw_decode` extraction handles a prose preamble before JSON (`known-failures.md:828`). Small models emitting `<think>` blocks or trailing prose depend on this path.
- **Silent single voice (KF-023).** Exit-0 prose no longer counts as a voice; content is qualified first (`known-failures.md:1236-1240`). The reproduction was a non-frontier secondary voice.
- **KF-041.** A scorer returned null for every item and the run went DEGRADED with no recorded cause (`known-failures.md:1656-1660`). It is Open.

## 5. Privacy and locality

- **What leaves the machine.** Each dissent sends the review diff after secret scanning. Scanning is forced on even when configured off (`adversarial-review.sh:230-236`). Redaction targets secrets, with entropy rules (`.loa.config.yaml.example:1144-1155`). It does not strip code or repo paths from the diff. The companion voice sends the same diff to the other family's provider (`CHANGELOG.md:89`). KF-004 repairs send the offending finding JSON (`.loa.config.yaml.example:1494-1498`).
- **Local leakage.** `agy -p` puts the prompt on argv, readable through `/proc` (`.loa.config.yaml.example:893-896`).
- **cheval redaction.** It covers secrets in exceptions, logs and envelopes (`loa_cheval/config/redaction.py:1-8`; `loa_cheval/redaction/sanitize.py:1-29`), not prompt bodies.
- **Context filtering.** It is opt-in through `feature_flags.context_filtering` set to `audit` or `enforce` (`cheval.py:1895-1911`). An unknown model gets no filtering (`routing/context_filter.py:411`).
- **Audit and telemetry.** MODELINV records model ids, chains and token counts, not prompts (`loa_cheval/audit/modelinv.py:549-568`). No third-party telemetry client exists (grep for posthog, sentry and analytics under `.claude/adapters` and `.claude/scripts/lib` returned nothing).
- **Local-only mode.** None exists. The "Conservative (all native, no remote calls)" example still runs the Claude Code session against Anthropic (`.loa.config.yaml.example:1081-1089`). A fully local dissent requires `companion_voice: false`, which makes every security audit DEGRADED. It also requires pinning the repair chain away from `tiny` and `claude-headless`.
- **Zero-price models.** See section 2. The dissent budget gate ignores model price: it uses fixed rates of 10 and 30 per Mtok (`adversarial-review.sh:3927-3929`), so a free model is still estimated and gated.

## 6. Known failures of the class "model weaker than the harness assumes"

| KF | Status, recurrence | Meaning for an open-weight voice |
|---|---|---|
| KF-004 validator ate dissenter findings | Resolved by sidecar; recurrence at least 31 (`known-failures.md:381-383`, `:409`) | The structural root is models omitting `id` or `failure_mode`. Expect higher rates from smaller models. Every zero-findings verdict needs a sidecar check (`:409`, `:429-438`). |
| KF-011 prose-wrapped JSON | Resolved, 3 (`known-failures.md:824-828`) | The parser tolerates a preamble. Thinking-tag output is untested. |
| KF-023 prose counted as a voice | Resolved in flight, 1 (`known-failures.md:1234-1240`) | Content qualification is the guard. Transport success does not mean a voice. |
| KF-041 scorer nulls every score | Open, 3 (`known-failures.md:1656-1660`) | A weaker scorer degrades consensus silently. Scorer failure class is not recorded. |
| KF-002, KF-003 empty content | Resolved structurally (`known-failures.md:181`, `:351`) | Typed aborts exist. Deadlines are tuned for hosted APIs, not local prefill. |
| KF-015 gate passes degraded runs | Resolved, 4+1 (`known-failures.md:1035-1043`) | Fail-closed validation on empty content stays load-bearing. |
| KF-019 confabulated absence | Documented (`known-failures.md:1132-1141`) | An agent-behaviour failure from a weaker or misinformed executor. It argues against local models as the orchestrator. |

KF-004 is the only entry at or above the recurrence-3 structural threshold that bears directly on weaker voices. Its fix is mechanical: enforce schemas at the wire. Local servers can do that **[external, unverified here]** but cheval does not ask them to.

## 7. Effort estimate and gate risks

**Overall estimate: M.** It is about one sprint for a mechanically honest path, and L if open-weight voices must count toward two-voice verdicts.

| Slice | Size | Work |
|---|---|---|
| A. Document and fix the operator recipe | S | Fix the Azure example to load. Document `openai_compat`, a literal auth value, `secret_env_allowlist`, `context_window`, and `streaming_recovery` deadlines. Add a local `dispatch_group` convention. |
| B. Schema enforcement on chat completions | S-M | Send `response_format: {type: json_schema}` on the chat body for entries that declare `structured_json`. Set `schema_enforced` from the body sent. Read `reasoning_content` deltas and strip `<think>` blocks. |
| C. Family and voice accounting | M | Let an operator declare a model's `family` and `lineage` in `hounfour.providers`. `_adv_family_of` must read the merged config, not only the System catalog. Allow `companion_chain.<family>` keys beyond `anthropic` and `openai`. Add a `local` or `open_weight` family that verdict quality can record. |
| D. Bridgebuilder and health probe | S-M | Derive the key map from the merged config with a keyless option. Add an OpenAI-compatible probe that uses the configured endpoint. Add an explicit opt-in for loopback and http that bypasses the endpoint validator. |
| E. Local-only posture | S | One switch that pins the repair chain, disables `tiny` and `claude-headless` fallbacks, and records `locality: local` in MODELINV. |

### Risks to the gates

- **Independence inflation.** If two open-weight models fine-tuned from one base count as independent, cross-family consensus loses meaning. Lineage needs a declared, reviewed field, and the default must stay `unknown`, never counted.
- **Weaker voices dilute APPROVED.** Verdict quality counts voices, not voice strength (`verdict/quality.py:6-14`). A local voice that returns schema-valid, empty findings satisfies quorum. Mark open-weight voices as advisory unless an eval gate shows recall.
- **Repair-loop exfiltration.** The `tiny` default sends findings to Anthropic on any host with a key. A local-only posture must pin the chain.
- **Ceiling defaults.** The 128K default context window will overfill most local models unless they are declared.
- **Unknown pricing hides spend on hosted open-weight APIs.** OpenRouter, Together, Groq and similar services need real prices, or ledgers read `unknown`.
- **Endpoint trust.** Allowing http and loopback on cheval is fine for local use. Applying it to every provider would weaken the cycle-099 protections the bash validator encodes.

Related prior proposal: hosted open-weight access through OpenRouter as a `kind:http` provider, with "no local infra" (`grimoires/loa/proposals/headless-adapters/headless-adapter-expansion.md:29`, `:58-63`). No runbook or proposal in scope mentions Ollama, vLLM, llama.cpp or LM Studio (grep over the listed runbooks and proposals).
