# PRD: Multi-Model Adversarial Review Upgrade — GPT-5.3-Codex Primary + Gemini Tertiary

**Version**: 1.1 (post-Flatline review)
**Cycle**: cycle-040
**Depends-On**: [PR #413](https://github.com/0xHoneyJar/loa/pull/413) (gpt-5.2-codex → gpt-5.3-codex base upgrade)

---

## 1. Problem Statement

The Loa adversarial review infrastructure supports three model providers (OpenAI, Anthropic, Google) but only uses two: Claude Opus 4.6 (primary) and GPT-5.2 (secondary). Despite Gemini API keys being available in the environment and full Google API call infrastructure existing in `model-adapter.sh.legacy`, Gemini is never invoked because no config points to it.

Additionally, GPT-5.3-Codex has been performing well on security benchmarks and is now available via the Responses API (PR #413 handles the codex-specific upgrade). However, the broader model routing still defaults to the older GPT-5.2 for flatline secondary, reviewer/reasoning aliases, red team models, and GPT review document reviews.

**Root causes:**
- `flatline_protocol.models.secondary: gpt-5.2` — not upgraded to 5.3-codex
- `reviewer`/`reasoning` aliases in `model-config.yaml` → `openai:gpt-5.2` — stale
- `.hounfour.flatline_tertiary_model` — unset, so FR-3 triangular scoring never activates
- `red_team.models.*` — all point to `gpt-5.2`
- `gemini-3-flash`/`gemini-3-pro` missing from legacy adapter registration maps
- No iteration cap on flatline loops

> Sources: `.loa.config.yaml:112-114`, `.claude/defaults/model-config.yaml:99-100`, `.claude/scripts/flatline-orchestrator.sh:277-287`

## 2. Goals & Success Metrics

| Goal | Metric | Target |
|------|--------|--------|
| GPT-5.3-codex as default external model everywhere | Zero remaining `gpt-5.2` hard defaults (excluding backward-compat aliases) | 100% |
| Gemini enabled as tertiary in Flatline | 3-way triangular scoring produces consensus from 3 models | Functional |
| Flatline iteration safety | Maximum loop cap enforced | 5 iterations |
| All model registrations complete | `validate_model_registry()` passes for all 3 providers | Zero gaps |

## 3. Scope

### In Scope

| Area | Change | Files |
|------|--------|-------|
| **Flatline secondary** | `gpt-5.2` → `gpt-5.3-codex` | `.loa.config.yaml`, `.loa.config.yaml.example`, `flatline-orchestrator.sh` |
| **Model-config aliases** | `reviewer` → `openai:gpt-5.3-codex`, `reasoning` → `openai:gpt-5.3-codex` | `.claude/defaults/model-config.yaml` |
| **GPT review documents** | Default doc model `gpt-5.2` → `gpt-5.3-codex` | `gpt-review-api.sh`, `gpt-review-integration.md`, `gpt-review.md` |
| **Red team models** | `attacker_secondary`/`defender_secondary` → `gpt-5.3-codex` | `.loa.config.yaml`, `.loa.config.yaml.example` |
| **Gemini tertiary** | Configure `flatline_tertiary_model: gemini-2.5-pro` | `.loa.config.yaml`, `.loa.config.yaml.example` |
| **Gemini 3 registration** | Add `gemini-3-flash`/`gemini-3-pro` to legacy adapter maps | `model-adapter.sh.legacy`, `model-adapter.sh` |
| **Flatline iteration cap** | Add `max_iterations: 5` to flatline config | `.loa.config.yaml`, `flatline-orchestrator.sh` |
| **Agent bindings** | Verify all flatline agents use updated aliases | `.claude/defaults/model-config.yaml` |
| **Flatline reference doc** | Update model table and examples | `.claude/loa/reference/flatline-reference.md` |

### Out of Scope

- Hounfour dynamic model selection (future work — noted by user)
- Changing Opus as primary (stays as-is)
- `hounfour.flatline_routing: true` enablement (keep legacy path as default)
- Bridgebuilder model change (stays Opus 4.6 — it's a native Claude skill)

### Dependency on PR #413

PR #413 upgrades `gpt-5.2-codex` → `gpt-5.3-codex` across 18 files. This PRD extends that work by:
1. Upgrading the **non-codex** `gpt-5.2` references (flatline secondary, doc reviews, red team, aliases)
2. Adding **Gemini as tertiary** (entirely new)
3. Adding **iteration cap** (entirely new)

Implementation should branch from PR #413's head or merge after it lands.

## 4. Functional Requirements

### FR-1: GPT-5.3-Codex as Universal Secondary

**Acceptance Criteria:**
- `flatline_protocol.models.secondary` defaults to `gpt-5.3-codex`
- `gpt-review-api.sh` DEFAULT_MODELS uses `gpt-5.3-codex` for all phases (prd, sdd, sprint, code)
- `model-config.yaml` aliases `reviewer` and `reasoning` both resolve to `openai:gpt-5.3-codex`
- `red_team.models.attacker_secondary` and `defender_secondary` default to `gpt-5.3-codex`
- Backward-compat: `gpt-5.2` remains a valid model name in registries (don't remove, just don't default to it)

### FR-2: Gemini Tertiary in Flatline

**Acceptance Criteria:**
- `.hounfour.flatline_tertiary_model: gemini-2.5-pro` configured in `.loa.config.yaml`
- `gemini-3-flash` and `gemini-3-pro` added to `MODEL_PROVIDERS`, `MODEL_IDS`, `COST_INPUT`, `COST_OUTPUT` in `model-adapter.sh.legacy`
- `gemini-3-flash` and `gemini-3-pro` added to `MODEL_TO_ALIAS` in `model-adapter.sh`
- Flatline Phase 1 runs 6 parallel calls (primary + secondary + tertiary, each as reviewer + skeptic)
- Flatline Phase 2 runs 6 cross-scoring calls (triangular: each model scores the other two)
- Consensus calculation uses 3-way agreement
- Graceful degradation: if Gemini API fails, fall back to 2-model mode (existing behavior)

**3-Way Consensus Decision Rule** (Flatline IMP-001):
- HIGH_CONSENSUS: 2-of-3 models score >700 (majority rule)
- DISPUTED: any pair delta >300 with no majority agreement
- BLOCKER: any 1 skeptic concern >700 (conservative — any model can block)
- Tie-break: average score across all scoring models; highest average wins
- Missing tertiary scores: fall back to 2-model thresholds (existing behavior)

**Graceful Degradation Modes** (Flatline IMP-002):
- Missing API key at startup: skip tertiary, log warning, proceed in 2-model mode
- Transient failure (429/5xx) during Phase 1: retry with backoff (existing `call_api_with_retry`); if still fails, mark model as degraded, continue with available results
- Failure mid-Phase 2 (cross-scoring): use available scores only; consensus engine handles missing score files
- Invalid JSON response: `normalize_json_response()` handles markdown-wrapped; if still invalid, treat as call failure

**Rate Limit Handling** (Flatline SKP-003):
- Phase 1 uses 2s stagger between review and skeptic waves (existing)
- Per-provider concurrency: max 2 concurrent calls to same provider
- Global budget/timeout per run enforced by orchestrator (existing `check_budget()` + `--timeout`)
- 3-model worst case: 12 calls per iteration × 5 max iterations = 60 calls ceiling

### FR-3: Flatline Iteration Cap

**Acceptance Criteria:**
- `flatline_protocol.max_iterations: 5` in config
- Orchestrator enforces cap — exits after 5 loops regardless of consensus state
- Warning logged when cap is hit
- **Output on cap hit** (Flatline IMP-003): emit best-available consensus from last completed iteration with `"capped": true` flag in output JSON. Do not fail — downstream consumers treat capped results as valid but flagged

### FR-4: Complete Model Registration

**Acceptance Criteria:**
- `validate_model_registry()` passes with zero errors
- All models in `VALID_FLATLINE_MODELS` have entries in `MODEL_TO_PROVIDER_ID`
- All models in `MODEL_TO_PROVIDER_ID` have entries in `MODEL_TO_ALIAS`
- Gemini 3 models have correct pricing in COST_INPUT/COST_OUTPUT
- `gemini-2.5-pro` confirmed present in all registries (Flatline IMP-005 — it's the default tertiary, must be fully registered not just Gemini 3)

### FR-5: Observability (Flatline IMP-008)

**Acceptance Criteria:**
- Flatline orchestrator logs iteration count, consensus delta, and degradation events
- Structured log entries include: `iteration_number`, `models_active`, `high_consensus_count`, `blocker_count`, `degraded_models[]`
- Existing `log()` function used — no new logging infrastructure needed

## 5. Technical Constraints

- **API compatibility**: GPT-5.3-Codex uses the Responses API (`/v1/responses`), not Chat Completions — PR #413 already handles this routing
- **Gemini API**: Uses `/v1beta/` endpoint with API key as URL parameter (existing `call_google_api()`). Key is passed via curl config file with `chmod 600` — not visible in process list or shell history. Xtrace disabled around calls (existing `prev_xtrace` guard). URL-parameter key passing is Google's standard for Generative Language API — header-based auth requires OAuth2 service accounts which adds complexity beyond scope
- **Environment vars**: `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GOOGLE_API_KEY` must all be present for 3-model Flatline
- **Cost**: GPT-5.3-Codex at $1.75/$14 per MTok is actually cheaper than GPT-5.2 at $10/$30 per MTok — net cost decrease
- **Gemini 2.5 Pro pricing**: $1.25/$10 per MTok — comparable to GPT-5.3-Codex

## 6. Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| GPT-5.3-codex Responses API format differs from Chat Completions | Low (PR #413 handles) | High | PR #413 already implements dual-path routing |
| Gemini API returns non-JSON despite `responseMimeType` | Medium | Medium | Existing `normalize_json_response()` handles markdown-wrapped JSON |
| 3-model Flatline exceeds budget | Low | Low | GPT-5.3-codex is cheaper; Gemini 2.5 Pro is cheap; budget configurable |
| Missing GOOGLE_API_KEY in some environments | Medium | Low | Graceful degradation to 2-model (existing FR-3 fallback logic) |

## 7. Implementation Notes

- Branch from PR #413's `chore/upgrade-gpt-5.3-codex` branch or merge #413 first
- Gemini 3 models (`gemini-3-flash`, `gemini-3-pro`) should be registered even though we use `gemini-2.5-pro` as default tertiary — they're available for user override
- The `gpt-5.2` entry must remain in all registries as a valid alias (backward compat) but should no longer be any default
- All changes are to System Zone (`.claude/`) and config files — no application code
