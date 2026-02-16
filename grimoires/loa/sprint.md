# Sprint Plan: The Hygiene Sprint

> Cycle: cycle-024 | Source: SDD (grimoires/loa/sdd.md)
> Fixes: #339, #345, #346

## Sprint Structure

2 sprints, 10 tasks total.

| Sprint | Focus | Files | Est. Lines |
|--------|-------|-------|------------|
| Sprint 1 | Adapter fix + Scoring engine | 2 files | ~50 |
| Sprint 2 | Settings cleanup hook | 2 files | ~85 |

---

## Sprint 1: Multi-Model Pipeline Fixes

**Goal**: Fix the OpenAI adapter parameter mismatch and scoring engine resilience issues so Flatline Protocol works end-to-end.

### Task 1.1: OpenAI Adapter — Model-Version-Aware Parameter

**File**: `.claude/adapters/loa_cheval/providers/openai_adapter.py`

**Changes**:
1. Add `_token_limit_key(self, model: str) -> str` method to `OpenAIAdapter` class
   - Returns `"max_tokens"` for models starting with `gpt-4` or `gpt-3`
   - Returns `"max_completion_tokens"` for all other models (GPT-5.2+, future)
2. Replace line 44: `"max_tokens": request.max_tokens` → `self._token_limit_key(request.model): request.max_tokens`
3. Update `_SUPPORTED_PARAMS` (line 26): add `"max_completion_tokens"` to the set

**Acceptance**: `_token_limit_key("gpt-5.2")` → `"max_completion_tokens"`, `_token_limit_key("gpt-4o")` → `"max_tokens"`

**Closes**: #346

### Task 1.2: Scoring Engine — JSON Validation

**File**: `.claude/scripts/scoring-engine.sh`

**Changes**:
1. Replace `cat` on lines 101-102 with `jq -c '.'` validation wrapper
2. Add `gpt_degraded` / `opus_degraded` tracking variables
3. On invalid JSON: set scores to `'{"scores":[]}'`, set degraded flag, log WARNING with filename
4. Add `validate_scores_structure()` function after JSON parse to verify `.scores` array exists

**Acceptance**: Feed a non-JSON file as `--gpt-scores` → logs WARNING, continues with opus-only scoring

### Task 1.3: Scoring Engine — Mode Display Fix

**File**: `.claude/scripts/scoring-engine.sh`

**Change**: Replace line 569 bash parameter expansion with explicit conditional:
```bash
local mode_display="standard"
[[ "$attack_mode" == "true" ]] && mode_display="attack"
log "Input items: GPT=$gpt_count, Opus=$opus_count (mode=$mode_display)"
```

**Acceptance**: Log shows `mode=standard` (not `mode=attackfalse`)

### Task 1.4: Scoring Engine — Skeptic Deduplication

**File**: `.claude/scripts/scoring-engine.sh`

**Change**: In the jq filter (line 164-170), add `group_by(.concern) | map(.[0])` before the severity filter to deduplicate skeptic concerns from multiple sources.

**Acceptance**: Duplicate SKP-001/SKP-006 entries collapsed to 1 each in output

### Task 1.5: Scoring Engine — Degraded Mode Flag

**File**: `.claude/scripts/scoring-engine.sh`

**Change**: Add `degraded` and `degraded_model` fields to the consensus output JSON when one model's response was invalid.

**Acceptance**: Output includes `"degraded": true, "degraded_model": "gpt"` when GPT file was invalid

---

## Sprint 2: Settings Cleanup Hook

**Goal**: Create and register a Stop event hook that automatically cleans `settings.local.json` after each session.

### Task 2.1: Create Cleanup Script

**New file**: `.claude/hooks/hygiene/settings-cleanup.sh`

**Implementation**:
1. Shebang + fail-open trap (`trap 'exit 0' ERR`)
2. Settings file path: `.claude/settings.local.json`
3. Size check: exit early if < 64KB
4. Parse `.permissions.allow` array with jq
5. Filter: remove entries > 200 chars, entries with newlines, entries matching credential patterns
6. Credential patterns (explicit list from SDD §2.3): AWS, GitHub, JWT, DB URLs, bearer tokens, OpenAI/Stripe keys, Slack tokens, PEM blocks
7. Deduplicate remaining entries
8. Write to temp file, atomic rename
9. Post-cleanup scan: grep remaining entries for suspected secret prefixes, log warnings
10. Log summary to `.run/audit.jsonl`

**Acceptance**:
- File with AWS key pattern entry → entry removed after hook runs
- File < 64KB → hook exits immediately
- Kill jq mid-execution → hook exits 0 (fail-open)

### Task 2.2: Register Hook

**File**: `.claude/hooks/settings.hooks.json`

**Change**: Add cleanup hook to the existing `Stop` array:
```json
{
  "type": "command",
  "command": ".claude/hooks/hygiene/settings-cleanup.sh",
  "async": true
}
```

**Acceptance**: Hook appears in Stop array alongside existing `run-mode-stop-guard.sh`

### Task 2.3: Verify End-to-End

**Verification checklist**:
1. `openai_adapter.py` — `_token_limit_key` method present and correct
2. `scoring-engine.sh` — JSON validation, mode display, dedup, degraded flag all working
3. `settings-cleanup.sh` — executable, fail-open, size threshold, credential patterns
4. `settings.hooks.json` — cleanup hook registered
5. No broken imports, no syntax errors in bash scripts

---

## Commit Strategy

| Sprint | Commit Message |
|--------|---------------|
| Sprint 1 | `fix(flatline): OpenAI adapter max_completion_tokens + scoring engine resilience (#345, #346)` |
| Sprint 2 | `fix(hooks): settings.local.json cleanup hook for autonomous runs (#339)` |
