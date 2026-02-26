# SDD: Multi-Model Adversarial Review Upgrade — GPT-5.3-Codex + Gemini Tertiary

**Version**: 1.1 (post-Flatline review)
**Cycle**: cycle-040
**PRD**: `grimoires/loa/prd.md`
**Depends-On**: [PR #413](https://github.com/0xHoneyJar/loa/pull/413) (gpt-5.2-codex → gpt-5.3-codex base upgrade)

**PR #413 Verification Gate**: Before merging, confirm: (1) all test suites pass, (2) Responses API dual-path routing validated with live call, (3) jq fallback chain at `model-adapter.sh.legacy:557-563` tested with both Chat Completions and Responses API payloads

---

## 1. Architecture Overview

This is a **configuration and registration upgrade** — no new architectural patterns are introduced. The existing three-layer model routing stack and FR-3 triangular scoring infrastructure already support everything we need. We are:

1. Changing defaults from GPT-5.2 → GPT-5.3-codex across all model selection points
2. Activating the dormant FR-3 tertiary model slot with Gemini 2.5 Pro
3. Completing model registration for Gemini 3 variants
4. Adding a flatline iteration safety cap

### Routing Stack (Unchanged)

```
.loa.config.yaml (defaults)
    ↓
flatline-orchestrator.sh → get_model_primary/secondary/tertiary()
    ↓
model-adapter.sh (shim) → MODEL_TO_ALIAS map
    ↓
model-adapter.sh.legacy → MODEL_PROVIDERS/MODEL_IDS → call_{openai,anthropic,google}_api()
```

### Model Selection After This Cycle

| Context | Before | After |
|---------|--------|-------|
| Flatline primary | `opus` (Claude Opus 4.6) | `opus` (unchanged) |
| Flatline secondary | `gpt-5.2` | `gpt-5.3-codex` |
| Flatline tertiary | (none) | `gemini-2.5-pro` |
| GPT review (docs) | `gpt-5.2` | `gpt-5.3-codex` |
| GPT review (code) | `gpt-5.3-codex` (PR #413) | `gpt-5.3-codex` (no change) |
| Adversarial dissent | `gpt-5.3-codex` (PR #413) | `gpt-5.3-codex` (no change) |
| Red team attacker secondary | `gpt-5.2` | `gpt-5.3-codex` |
| Red team defender secondary | `gpt-5.2` | `gpt-5.3-codex` |
| model-config `reviewer` alias | `openai:gpt-5.2` | `openai:gpt-5.3-codex` |
| model-config `reasoning` alias | `openai:gpt-5.2` | `openai:gpt-5.3-codex` |

## 2. Detailed Design

### 2.1 Flatline Secondary: GPT-5.2 → GPT-5.3-codex

**Files to modify:**

| File | Location | Change |
|------|----------|--------|
| `.loa.config.yaml` | Line 114 | `secondary: gpt-5.2` → `secondary: gpt-5.3-codex` |
| `.loa.config.yaml.example` | flatline_protocol.models.secondary | Same |
| `flatline-orchestrator.sh` | Line 196 `get_model_secondary()` | Default `'gpt-5.2'` → `'gpt-5.3-codex'` |

**API routing impact:** GPT-5.3-codex uses the Responses API (`/v1/responses`) instead of Chat Completions (`/v1/chat/completions`). PR #413 already implements the dual-path routing in both:
- `model-adapter.sh.legacy:249-279` (bash legacy path: `if [[ "$model_id" == *"codex"* ]]`)
- `openai_adapter.py:31-33` (Python cheval path: `_is_codex_model()`)

**Consensus:** The Responses API returns a different response structure (`output[].content[].text` vs `choices[0].message.content`). PR #413's response parsing at `model-adapter.sh.legacy:557-563` handles both formats with a jq fallback chain.

**Error handling for secondary failures** (Flatline IMP-001): When GPT-5.3-codex calls fail (429, timeout, malformed response), the orchestrator should:
1. Retry via existing `call_api_with_retry` (3 attempts, exponential backoff)
2. If retries exhausted: mark model as degraded, log error with stderr capture
3. Phase 1: continue with available results (2 of 4+ calls sufficient)
4. Phase 2: skip cross-scoring pairs involving failed model
5. Consensus: use available scores only — existing scoring engine handles missing files
6. Never silently swallow empty content — if jq `empty` triggers, log a warning and mark the call as failed

**Known tech debt**: The `*codex*` substring match for API routing is brittle (Flatline SKP-001/002). This is PR #413's pattern and out of scope for this cycle. Future work: replace with explicit `MODEL_API_TYPE` associative array.

### 2.2 Gemini Tertiary Activation

**Files to modify:**

| File | Location | Change |
|------|----------|--------|
| `.loa.config.yaml` | Under `hounfour:` | Add `flatline_tertiary_model: gemini-2.5-pro` |
| `.loa.config.yaml.example` | Under `hounfour:` | Add commented example |

**Existing infrastructure used (no code changes needed):**
- `flatline-orchestrator.sh:200-203` — `get_model_tertiary()` already reads `.hounfour.flatline_tertiary_model`
- `flatline-orchestrator.sh:790-800` — FR-3 tertiary validation and `has_tertiary` flag
- `flatline-orchestrator.sh:822-828,842-848` — Phase 1 tertiary review + skeptic calls
- `flatline-orchestrator.sh:988-1024` — Phase 2 triangular cross-scoring (6 calls)
- `flatline-orchestrator.sh` consensus — 3-way agreement calculation

**Tertiary model JSON schema validation** (Flatline IMP-003): The Gemini tertiary must return JSON conforming to the Flatline scoring schema (`{"improvements": [...]}` for review, `{"concerns": [...]}` for skeptic, `{"scores": [...]}` for scoring). Validation steps:
1. `normalize_json_response()` strips markdown wrappers (existing)
2. `extract_json_content()` validates required top-level key exists (existing)
3. If validation fails: treat as call failure, log raw response for debugging, proceed without tertiary scores

**Why gemini-2.5-pro (not gemini-3-pro):**
- gemini-2.5-pro is a stable, production model with proven JSON output
- gemini-3-pro is newer and may have JSON formatting inconsistencies
- User can override to gemini-3-pro via config at any time
- Both are registered in VALID_FLATLINE_MODELS

**Graceful degradation:** If `GOOGLE_API_KEY` is missing or Gemini API fails, the orchestrator falls back to 2-model mode automatically — `has_tertiary` stays false and all tertiary code paths are skipped.

### 2.3 Gemini 3 Model Registration

**File: `model-adapter.sh.legacy`** — Add to all 4 maps:

```bash
# MODEL_PROVIDERS (after gemini-2.5-pro line)
["gemini-3-flash"]="google"
["gemini-3-pro"]="google"

# MODEL_IDS
["gemini-3-flash"]="gemini-3-flash"
["gemini-3-pro"]="gemini-3-pro"

# COST_INPUT (per 1K tokens, from model-config.yaml)
["gemini-3-flash"]="0.0002"     # $0.20/MTok
["gemini-3-pro"]="0.0025"       # $2.50/MTok

# COST_OUTPUT
["gemini-3-flash"]="0.0008"     # $0.80/MTok
["gemini-3-pro"]="0.015"        # $15.00/MTok
```

**File: `model-adapter.sh`** — Add to MODEL_TO_ALIAS map:

```bash
["gemini-3-flash"]="google:gemini-3-flash"
["gemini-3-pro"]="google:gemini-3-pro"
```

**Validation:** `validate_model_registry()` at `model-adapter.sh.legacy:128-149` will automatically verify all 4 maps are synchronized.

### 2.4 Model-Config Aliases Update

**File: `.claude/defaults/model-config.yaml`** lines 99-100:

```yaml
# Before
reviewer: "openai:gpt-5.2"
reasoning: "openai:gpt-5.2"

# After
reviewer: "openai:gpt-5.3-codex"
reasoning: "openai:gpt-5.3-codex"
```

**Cascade effect:** All agent bindings that reference `reviewer` or `reasoning` automatically use GPT-5.3-codex:
- `flatline-reviewer` (line 132-134)
- `flatline-skeptic` (line 135-139)
- `flatline-scorer` (line 140-142)
- `flatline-dissenter` (line 143-147)
- `gpt-reviewer` (line 148-150)
- `reviewing-code` (line 124-126)
- `jam-reviewer-gpt` (line 177-179)
- `jam-reviewer-kimi` (line 180-184)

No changes needed to agent binding lines themselves — alias indirection handles it.

### 2.5 GPT Review Document Model Update

**File: `gpt-review-api.sh`** line 25:

```bash
# Before
declare -A DEFAULT_MODELS=(["prd"]="gpt-5.2" ["sdd"]="gpt-5.2" ["sprint"]="gpt-5.2" ["code"]="gpt-5.3-codex")

# After
declare -A DEFAULT_MODELS=(["prd"]="gpt-5.3-codex" ["sdd"]="gpt-5.3-codex" ["sprint"]="gpt-5.3-codex" ["code"]="gpt-5.3-codex")
```

**Note:** The `code` entry was already updated by PR #413. We're updating `prd`, `sdd`, and `sprint`.

**Protocol doc updates:**
- `.claude/protocols/gpt-review-integration.md` line 70: `documents: "gpt-5.2"` → `documents: "gpt-5.3-codex"`
- `.claude/commands/gpt-review.md` line 333: Same change

### 2.6 Red Team Model Update

**File: `.loa.config.yaml`** lines 138-141:

```yaml
# Before
models:
  attacker_primary: opus
  attacker_secondary: gpt-5.2
  defender_primary: opus
  defender_secondary: gpt-5.2

# After
models:
  attacker_primary: opus
  attacker_secondary: gpt-5.3-codex
  defender_primary: opus
  defender_secondary: gpt-5.3-codex
```

**File: `.loa.config.yaml.example`** — Same change.

### 2.7 Flatline Iteration Cap

**File: `.loa.config.yaml`** — Add under `flatline_protocol:`:

```yaml
flatline_protocol:
  max_iterations: 5    # Safety cap — exit after 5 loops regardless of consensus
```

**File: `flatline-orchestrator.sh`** — Add iteration limit enforcement (Flatline IMP-002).

The orchestrator's main loop (in autonomous/simstim mode) needs a guard:

```bash
# In read_config section (near line 60)
get_max_iterations() {
    read_config '.flatline_protocol.max_iterations' '5'
}
```

**Termination semantics when cap is hit:**
1. Log warning: `"Max iterations reached ($MAX_ITERATIONS). Emitting best-available consensus."`
2. Emit consensus from last completed iteration with `"capped": true` in output JSON
3. Exit code 0 (success) — capped results are valid but flagged
4. Downstream consumers (simstim, autonomous mode) check `capped` flag and present it to user

The flatline beads loop in simstim (Phase 6.5) already has a hardcoded `1/6` iteration display, suggesting 6 max. We set the config default to 5 per user requirement.

### 2.8 Reference Documentation Updates

**File: `.claude/loa/reference/flatline-reference.md`** — Update:
- Model table to show GPT-5.3-codex as secondary, Gemini 2.5 Pro as tertiary
- Config examples
- Cost estimates per run

**File: `.claude/protocols/flatline-protocol.md`** — Update:
- Model names in examples
- Add `max_iterations` to config reference

## 3. File Change Summary

| File | Changes | Zone |
|------|---------|------|
| `.loa.config.yaml` | Secondary → gpt-5.3-codex, tertiary → gemini-2.5-pro, red team models, max_iterations | State |
| `.loa.config.yaml.example` | Mirror all config changes | State |
| `.claude/scripts/flatline-orchestrator.sh` | Default secondary, max_iterations function | System |
| `.claude/scripts/gpt-review-api.sh` | DEFAULT_MODELS prd/sdd/sprint → gpt-5.3-codex | System |
| `.claude/scripts/model-adapter.sh.legacy` | Add gemini-3-flash/pro to 4 maps | System |
| `.claude/scripts/model-adapter.sh` | Add gemini-3-flash/pro to MODEL_TO_ALIAS | System |
| `.claude/defaults/model-config.yaml` | reviewer/reasoning aliases → gpt-5.3-codex | System |
| `.claude/protocols/gpt-review-integration.md` | Doc model → gpt-5.3-codex | System |
| `.claude/commands/gpt-review.md` | Doc model → gpt-5.3-codex | System |
| `.claude/loa/reference/flatline-reference.md` | Model table, config examples | System |
| `.claude/protocols/flatline-protocol.md` | Model names, max_iterations | System |

**Estimated total:** ~11 files, ~40-50 line changes.

## 4. API Compatibility Notes

### GPT-5.3-codex as Flatline Secondary

The Flatline orchestrator calls `call_model()` which routes to `call_openai_api()` in the legacy path. PR #413's codex detection (`if [[ "$model_id" == *"codex"* ]]`) correctly routes GPT-5.3-codex to the Responses API.

**Key difference from Chat Completions:**
- Request: `{"model": "gpt-5.3-codex", "input": "...", "reasoning": {"effort": "medium"}}` (no messages array)
- Response: `{"output": [{"type": "message", "content": [{"type": "output_text", "text": "..."}]}]}` (no choices array)

The response parsing jq at `model-adapter.sh.legacy:557-563` handles both:
```bash
content=$(echo "$response" | jq -r '
    .choices[0].message.content //
    (.output[] | select(.type == "message") | .content[] | select(.type == "output_text") | .text) //
    empty
')
```

### Gemini as Tertiary

Gemini uses the existing `call_google_api()` at `model-adapter.sh.legacy:368-426`:
- Endpoint: `https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`
- Auth: API key as URL parameter (not Authorization header)
- JSON enforced via `responseMimeType: "application/json"`

No changes needed — infrastructure is already working.

## 5. Cost Impact

| Model | Input/MTok | Output/MTok | Role |
|-------|-----------|-------------|------|
| Claude Opus 4.6 | $5.00 | $25.00 | Primary (unchanged) |
| GPT-5.3-codex | $1.75 | $14.00 | Secondary (was GPT-5.2 @ $10/$30) |
| Gemini 2.5 Pro | $1.25 | $10.00 | Tertiary (new) |

**Per Flatline run estimate (3-model):**
- Phase 1: 6 calls (~$0.40-0.60)
- Phase 2: 6 calls (~$0.15-0.25)
- Total: ~$0.55-0.85 per run

**Compared to before (2-model):**
- Phase 1: 4 calls (~$0.50-0.80)
- Phase 2: 2 calls (~$0.10-0.20)
- Total: ~$0.60-1.00 per run

Net cost is **comparable or lower** because GPT-5.3-codex is significantly cheaper than GPT-5.2.

## 6. Testing Strategy

1. **Registration validation**: Run `validate_model_registry()` — must pass with zero errors
2. **Config validation**: `yq` read of all new config keys
3. **Dry-run Flatline**: `flatline-orchestrator.sh --dry-run` to verify 3-model selection
4. **Existing test suites**: Run adversarial-review.bats, gpt-review-codex-adapter.bats — should pass after model name updates in test fixtures
5. **FR-3 triangular scoring validation** (Flatline SKP-003): Run a live 3-model Flatline review against a test document to verify Gemini tertiary participates and consensus includes 3-way scoring. Inspect output JSON for `tertiary-review.json`, `tertiary-skeptic.json`, and all 6 cross-scoring files
6. **jq fallback chain test**: Verify `model-adapter.sh.legacy:557-563` correctly parses both Chat Completions and Responses API response shapes (part of PR #413 verification gate)

## 7. Rollback

All changes are config/registration. Rollback = revert the config values:
- `secondary: gpt-5.2` (restore)
- Remove `flatline_tertiary_model` line
- `reviewer`/`reasoning` → `openai:gpt-5.2` (restore)
- Red team models → `gpt-5.2` (restore)

No data migration, no schema changes, no API contract changes.
