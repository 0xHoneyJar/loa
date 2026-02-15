# PRD: Platform Hardening — Cross-Platform Compatibility, Model Catalog, and Quality Gates

> Source: [#328](https://github.com/0xHoneyJar/loa/issues/328), [#327](https://github.com/0xHoneyJar/loa/issues/327), [#323](https://github.com/0xHoneyJar/loa/issues/323), [#322](https://github.com/0xHoneyJar/loa/issues/322), [#316](https://github.com/0xHoneyJar/loa/issues/316)
> Author: PRD discovery + context synthesis
> Cycle: cycle-015
> Previously fixed: [#320](https://github.com/0xHoneyJar/loa/issues/320) (all 3 bugs), [#321](https://github.com/0xHoneyJar/loa/issues/321) (all 3 bugs) — recommend closing

## Triage Summary

Seven issues were evaluated. Two (#320, #321) are **already fully fixed** in the codebase from cycle-013's work — all 6 chained bugs (LazyValue resolution, missing personas, persona merge logic, env dedup, markdown fence stripping, gpt-reviewer persona) have landed. These should be closed.

The remaining five issues contain **8 actionable items** across 4 domains: platform compatibility, model-invoke resilience, model catalog expansion, and output quality.

## 1. Problem Statement

The Loa framework has platform-specific assumptions, missing resilience patterns, an incomplete model catalog, and output quality gaps that degrade the experience for macOS users, multi-model operators, and downstream consumers.

Specifically:
- **macOS users cannot use Run Bridge** because `bridge-state.sh` hard-fails on missing `flock` (#328.1)
- **model-invoke runtime failures kill the review pipeline** with no fallback to working direct-curl path (#327)
- **Gemini 3 Pro/Flash are available** but not in the model catalog, limiting multi-model diversity (#322)
- **Construct skill symlinks break** when packs add new skills — no sync mechanism exists (#323)
- **Butterfreezone output is a sparse list** instead of the rich, glanceable README expected by humans and agents (#316)
- **Bridge orchestrator has 3 smaller gaps**: hardcoded persona path, missing standalone flatline check script, and signal model that doesn't pause for agent work (#328.2, #328.3, #328.5)

> Sources: #328 body (v1.36.0 feedback, macOS), #327 body (v1.37.0 feedback), #322 body (v1.38.0 feedback), #323 body, #316 body

### Why Now

The v1.38.0 release shipped the Adversarial Hardening package. Downstream users are actively exercising multi-model review, Run Bridge, and construct packs. These issues are reported from production use — not theoretical.

## 2. Goals & Success Metrics

### Primary Goals

1. **Run Bridge works on macOS**: `bridge-state.sh` operates without `flock` using a portable locking mechanism
2. **model-invoke failures gracefully degrade**: Runtime errors in `call_api_via_model_invoke` fall back to `call_api` (direct curl) with a warning
3. **Gemini 3 Pro/Flash in model catalog**: Available as Flatline tertiary models and plan-mode options
4. **Construct symlink sync**: New skills in pack updates become discoverable without manual intervention
5. **Butterfreezone produces rich, glanceable READMEs**: Narrative prose with architecture overview, not just a bulleted list

### Success Metrics

| Metric | Target |
|--------|--------|
| `bridge-state.sh` works on macOS (Darwin) | Exit 0, atomic state updates |
| `gpt-review-api.sh` with broken model-invoke | Falls back to curl, warning logged |
| Gemini 3 Pro in VALID_FLATLINE_MODELS | Present, routable |
| Construct sync after pack update | All manifest skills symlinked |
| Butterfreezone output | >500 words, has Architecture section |

## 3. User & Stakeholder Context

### Primary Persona: macOS Framework User

A developer on macOS who installs Loa, runs `/run-bridge`, and encounters `flock` failures. The #328 reporter had to bypass shell scripts entirely — managing `.run/bridge-state.json` manually with the Write tool.

**Current experience**: Hard failure with "flock is required" error. No workaround except abandoning the scripts.

**Expected experience**: Portable locking that works on both Linux and macOS without extra dependencies.

### Secondary Persona: Multi-Model Operator

A developer using Flatline Protocol with 3+ models (Opus + GPT-5.2 + Gemini). The #322 reporter has already implemented Gemini 3 support downstream and wants to contribute upstream.

### Tertiary Persona: Construct Consumer

A developer using construct packs (e.g., Observer pack) where skill additions in pack updates are invisible because symlinks weren't synced (#323).

> Sources: #328 survey (process comfort B), #327 survey (process comfort C), #322 body, #323 body

## 4. Functional Requirements

### FR-1: Portable Locking in `bridge-state.sh` (HIGH — #328.1)

**File**: `.claude/scripts/bridge-state.sh`

**Current behavior**: Hard-fails if `flock` is unavailable. macOS doesn't ship `flock`.

**Required behavior**: Platform-aware locking with fallback:
1. If `flock` is available, use it (current behavior, preferred)
2. If `flock` is unavailable, use `mkdir`-based locking (atomic on all POSIX systems)
3. The `mkdir` lock must support timeout (polling with sleep) and stale lock detection (PID check or age-based)
4. All existing `atomic_state_update()` callers continue to work without changes

**Acceptance criteria**:
- `atomic_state_update` succeeds on macOS (Darwin) without `flock` installed
- Concurrent access is still safe (no state corruption)
- Lock timeout and stale detection still work
- Existing Linux behavior unchanged

### FR-2: model-invoke Runtime Fallback in `gpt-review-api.sh` (HIGH — #327)

**File**: `.claude/scripts/gpt-review-api.sh:916-920`

**Current behavior**: `call_api_via_model_invoke` errors propagate directly. No runtime fallback.

**Required behavior**: Wrap `call_api_via_model_invoke` in try/catch:
```
response=$(call_api_via_model_invoke ...) || {
    warn "model-invoke failed (exit $?), falling back to direct API"
    response=$(call_api ...)
}
```

**Acceptance criteria**:
- When model-invoke returns non-zero exit, falls back to direct curl
- Warning message logged to stderr including the exit code
- Direct curl path is exercised on fallback (not skipped)
- Happy path (model-invoke succeeds) behavior unchanged

### FR-3: Gemini 3 Pro/Flash in Model Catalog (MEDIUM — #322)

**Files**: `.claude/scripts/flatline-orchestrator.sh`, `.claude/scripts/model-adapter.sh.legacy`, `.claude/adapters/loa_cheval/providers/`

**Current behavior**: `VALID_FLATLINE_MODELS` includes `gemini-2.0` only. No Gemini 3 Pro/Flash.

**Required behavior**:
1. Add `gemini-3-pro` and `gemini-3-flash` to `VALID_FLATLINE_MODELS`
2. Add provider ID mappings in `MODEL_TO_PROVIDER_ID` (or equivalent)
3. Add `get_model_tertiary()` function in `flatline-orchestrator.sh` for 3-model config
4. Expand Phase 1 to support 6 parallel calls when tertiary model configured (3 models x review + skeptic)
5. Expand Phase 2 to support 3-way cross-scoring (4 calls)
6. Configuration: `hounfour.flatline_tertiary_model` in `.loa.config.yaml`

**Note**: The #322 reporter has a working downstream implementation. The upstream integration should follow the same patterns.

**Acceptance criteria**:
- `gemini-3-pro` accepted by `validate_model()`
- Phase 1 fires 6 parallel calls when tertiary configured
- Phase 2 cross-scores between all 3 models
- Backward compatible: 2-model config still works when no tertiary set
- Google API provider routing works (API key: `GOOGLE_API_KEY`)

### FR-4: Construct Symlink Sync (MEDIUM — #323)

**Files**: New script `.claude/scripts/sync-constructs.sh`, updates to `scripts/install.sh`

**Current behavior**: Symlinks created at install time only. New skills in pack updates are invisible.

**Required behavior**:
1. New script `sync-constructs.sh` that:
   - Reads each installed pack's `manifest.json`
   - Compares manifest skills against existing symlinks in `.claude/skills/`
   - Creates missing symlinks
   - Reports what was added (stdout)
2. Hook into `/update-loa` to auto-run after framework update
3. Idempotent: running twice produces no changes the second time

**Acceptance criteria**:
- Skills listed in `manifest.json` but missing from `.claude/skills/` get symlinked
- Running twice produces no output on second run
- `/update-loa` triggers sync automatically

### FR-5: Butterfreezone Output Quality (MEDIUM — #316)

**File**: `.claude/scripts/butterfreezone-gen.sh`

**Current behavior**: Produces sparse bulleted list output. The #316 reporter references [loa-finn's README](https://github.com/0xHoneyJar/loa-finn/blob/main/README.md) as the quality bar — a rich, narrative README with architecture diagrams, capabilities, and getting-started content.

**Required behavior**:
1. Output should include narrative prose, not just lists
2. Must have sections: Summary, Architecture Overview, Key Capabilities, Getting Started, Project Structure
3. Architecture section should include a text-based diagram (Mermaid or ASCII)
4. Each section should have 2-5 sentences of context, not just bullet points
5. Provenance tags preserved (existing `<!-- butterfreezone: ... -->` markers)

**Acceptance criteria**:
- Output >500 words
- Has Architecture section with diagram
- Has narrative prose (not all bullet lists)
- Validation script (`butterfreezone-validate.sh`) still passes
- Provenance tags intact

### FR-6: Bridge Orchestrator Persona Path Config (LOW — #328.3)

**File**: `.claude/skills/run-bridge/SKILL.md`

**Required behavior**: Persona path configurable via `.loa.config.yaml`:
```yaml
run_bridge:
  persona_path: .claude/data/bridgebuilder-persona.md  # default
```

### FR-7: Standalone Flatline Check Script (LOW — #328.5)

**File**: New script `.claude/scripts/bridge-flatline-check.sh`

**Required behavior**: Extract flatline detection logic from `bridge-state.sh` into a standalone script that:
- Reads last N iteration scores from `bridge-state.json`
- Compares against threshold (default: 0.05 of initial score)
- Exits 0 if flatlined, 1 if should continue
- Outputs JSON summary on stdout

**Note**: Logic already exists in `bridge-state.sh:is_flatlined()`. This is extraction, not new implementation.

## 5. Non-Functional Requirements

### NFR-1: No New Dependencies

Portable locking must use POSIX primitives only. No `brew install` requirements for macOS.

### NFR-2: Backward Compatibility

All changes must be backward compatible:
- 2-model Flatline config still works when no tertiary model set
- Linux `flock` path unchanged
- Existing construct installs unaffected by sync additions

### NFR-3: Defensive Error Reporting

All fallback paths must log warnings with actionable context (file, line, exit code, fallback action taken). No `2>/dev/null` on fallback paths.

## 6. Scope & Prioritization

### In Scope (This Cycle)

| Priority | Item | Issue | Effort |
|----------|------|-------|--------|
| HIGH | Portable locking (macOS) | #328.1 | 1 sprint |
| HIGH | model-invoke runtime fallback | #327 | 1 task |
| MEDIUM | Gemini 3 model catalog | #322 | 1 sprint |
| MEDIUM | Construct symlink sync | #323 | 1 sprint |
| MEDIUM | Butterfreezone quality | #316 | 1 sprint |
| LOW | Persona path config | #328.3 | 1 task |
| LOW | Standalone flatline check | #328.5 | 1 task |

### Out of Scope

| Item | Reason |
|------|--------|
| #320 (Flatline 3 bugs) | Already fixed — recommend closing |
| #321 (gpt-review 3 bugs) | Already fixed — recommend closing |
| #328.2 (Orchestrator signal model redesign) | Design-level refactor; current workaround (skill-as-orchestrator) is stable. Track in a future RFC. |
| #328.4 (Findings parser fallback) | Already has 3-tier fallback (v2 JSON → v1 legacy → empty) |

## 7. Risks & Dependencies

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `mkdir` locking less robust than `flock` | Medium | Medium | PID-based stale detection + age-based timeout |
| Gemini 3 API format differences | Low | Medium | Validate against Google's API docs before implementation |
| Butterfreezone quality subjective | Medium | Low | Use loa-finn README as reference standard; validate with word count + section presence |
| Construct sync breaks on malformed manifest | Low | Low | Validate manifest JSON before processing |

## Appendix: Issue Status

| Issue | Status | Action |
|-------|--------|--------|
| #320 | **FIXED** (all 3 bugs) | Close with note: LazyValue, personas, merge logic all landed in cycle-013 |
| #321 | **FIXED** (all 3 bugs) | Close with note: env dedup, fences, persona all landed in cycle-013 |
| #327 | Open — runtime fallback missing | Fix in this cycle (FR-2) |
| #328 | Open — 3/5 items need work | Fix items 1, 3, 5 in this cycle; item 2 deferred; item 4 already done |
| #323 | Open | Fix in this cycle (FR-4) |
| #322 | Open | Fix in this cycle (FR-3) |
| #316 | Open | Fix in this cycle (FR-5) |
