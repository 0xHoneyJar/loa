# Sprint Plan: Platform Hardening — Cross-Platform Compatibility, Model Catalog, Quality Gates

> Source: PRD cycle-015, SDD cycle-015
> Cycle: cycle-015
> Issues: #328, #327, #323, #322, #316
> Global Sprint Counter: starts at 96

## Context

7 functional requirements across 4 domains: platform compatibility, model-invoke resilience, model catalog expansion, and output quality. All FRs are independent (parallelizable within sprints) except FR-7 which depends on FR-1. Grouped by priority into 3 sprints.

---

## Sprint 1: Critical Platform Fixes (HIGH priority)

> **Goal**: macOS users can run bridge, model-invoke failures don't kill reviews
> **Global ID**: sprint-96
> **Scope**: FR-1 (portable locking) + FR-2 (model-invoke fallback) + FR-7 (flatline check extraction)

### Task 1.1: Platform-Aware Locking in `bridge-state.sh`

**File**: `.claude/scripts/bridge-state.sh`

**Work**:
1. Add `_LOCK_STRATEGY` detection at source time (flock vs mkdir)
2. Create `_acquire_lock_mkdir()` with PID-based stale detection and age-based timeout
3. Create `_release_lock_mkdir()` cleanup function
4. Create `_portable_mtime()` wrapper for cross-platform `stat`
5. Refactor `atomic_state_update()` into strategy dispatch:
   - `_atomic_state_update_flock()` — existing logic, extracted
   - `_atomic_state_update_mkdir()` — new, same jq+rename pattern with mkdir lock
6. Add cleanup trap for mkdir lock on EXIT/INT/TERM

**Acceptance Criteria**:
- [ ] When `flock` unavailable, `atomic_state_update()` succeeds using mkdir strategy
- [ ] PID-based stale detection removes lock when holding process is dead
- [ ] Age-based stale detection removes lock older than 30s
- [ ] Lock timeout works (5s default, fails cleanly on expiry)
- [ ] All 6 existing callers work without changes
- [ ] Linux behavior unchanged (still uses flock when available)

### Task 1.2: model-invoke Runtime Fallback in `gpt-review-api.sh`

**File**: `.claude/scripts/gpt-review-api.sh`

**Work**:
1. In `call_api_via_model_invoke()` (line ~379): Change `exit $exit_code` to `return $exit_code`
2. At lines 914-920: Wrap model-invoke call with `|| { fallback }` pattern
3. Fallback logs warning to stderr with exit code, then calls `call_api()` directly

**Acceptance Criteria**:
- [ ] When model-invoke returns non-zero, falls back to direct curl
- [ ] Warning message logged to stderr includes exit code
- [ ] Direct curl path (call_api) exercised on fallback
- [ ] Happy path (model-invoke succeeds) unchanged

### Task 1.3: Standalone Flatline Check Script

**File**: New `.claude/scripts/bridge-flatline-check.sh`

**Work**:
1. Create standalone script that reads `.run/bridge-state.json`
2. Evaluates `.flatline.flatline_detected` field
3. Outputs JSON summary on stdout
4. Exit 0 if flatlined, exit 1 if should continue
5. Only depends on `bootstrap.sh` — does not source `bridge-state.sh`

**Acceptance Criteria**:
- [ ] Exit 0 when flatline detected, exit 1 otherwise
- [ ] JSON summary on stdout with all flatline fields
- [ ] No state file → exit 1 with explanation JSON
- [ ] Standalone — no dependency on `bridge-state.sh`

### Task 1.4: Portable Locking in `butterfreezone-gen.sh`

**File**: `.claude/scripts/butterfreezone-gen.sh`

**Work**:
1. Apply same portable locking pattern from Task 1.1
2. Replace `flock -n` with `mkdir` attempt when flock unavailable
3. Non-blocking: single attempt, skip if locked (existing behavior)

**Acceptance Criteria**:
- [ ] Script runs on macOS without flock
- [ ] Non-blocking lock behavior preserved
- [ ] Generation still skipped when another instance running

---

## Sprint 2: Model Catalog + Construct Sync (MEDIUM priority)

> **Goal**: Gemini 3 models available in Flatline, construct packs stay synced
> **Global ID**: sprint-97
> **Scope**: FR-3 (Gemini 3 catalog) + FR-4 (construct sync) + FR-6 (persona path config)

### Task 2.1: Gemini 3 Model Validation

**File**: `.claude/scripts/flatline-orchestrator.sh`

**Work**:
1. Add `gemini-3-pro` and `gemini-3-flash` to `VALID_FLATLINE_MODELS` array
2. Add Google provider routing in `call_model()` for `gemini-3-*` patterns
3. Ensure `GOOGLE_API_KEY` env var used for authentication

**Acceptance Criteria**:
- [ ] `validate_model gemini-3-pro` succeeds
- [ ] `validate_model gemini-3-flash` succeeds
- [ ] Google API key routing works for Gemini 3 models

### Task 2.2: Tertiary Model Support in Flatline

**File**: `.claude/scripts/flatline-orchestrator.sh`

**Work**:
1. Add `get_model_tertiary()` function reading `hounfour.flatline_tertiary_model` config
2. Modify Phase 1 to conditionally add tertiary review + skeptic calls (6 parallel when configured)
3. Modify Phase 2 to support 3-way triangular cross-scoring (6 parallel when configured)
4. Maintain 2-model backward compatibility when tertiary not configured

**Acceptance Criteria**:
- [ ] `get_model_tertiary()` returns empty string when not configured
- [ ] Phase 1 fires 6 parallel calls when tertiary set
- [ ] Phase 2 fires 6 cross-scores when tertiary set
- [ ] 2-model config (no tertiary) fires 4+2 calls as before
- [ ] Cost accumulation works across all 3 models

### Task 2.3: Construct Symlink Sync Script

**File**: New `.claude/scripts/sync-constructs.sh`

**Work**:
1. Create script that reads each installed pack's `manifest.json`
2. Compare manifest skills against `.constructs-meta.json` registrations
3. Register missing skills with `from_pack` provenance
4. Report what was added on stdout
5. Idempotent: second run produces no output

**Acceptance Criteria**:
- [ ] Skills in manifest but missing from meta get registered
- [ ] Running twice produces no output on second run
- [ ] Missing skill directories logged as warnings
- [ ] Malformed manifest JSON → skip pack with warning

### Task 2.4: Construct Sync in Update-Loa

**File**: `.claude/commands/update-loa.md`

**Work**:
1. Add Phase 5.6 after merge: run `sync-constructs.sh`
2. Report newly synced skills in update output

**Acceptance Criteria**:
- [ ] `/update-loa` triggers construct sync after merge
- [ ] Sync output visible in update results

### Task 2.5: Persona Path Config Connection

**File**: `.claude/scripts/bridge-orchestrator.sh` (or equivalent orchestrator script)

**Work**:
1. Add `get_persona_path()` function reading from config
2. Replace hardcoded persona path references with function call
3. Default: `.claude/data/bridgebuilder-persona.md`

**Acceptance Criteria**:
- [ ] Custom path from config used when set
- [ ] Default path used when config empty
- [ ] Persona integrity check uses resolved path

---

## Sprint 3: Output Quality (MEDIUM priority)

> **Goal**: Butterfreezone produces rich, glanceable READMEs
> **Global ID**: sprint-98
> **Scope**: FR-5 (butterfreezone quality)

### Task 3.1: Butterfreezone Word Budget Adjustment

**File**: `.claude/scripts/butterfreezone-gen.sh`

**Work**:
1. Increase `header` budget: 120 → 200 words
2. Increase `capabilities` budget: 600 → 800 words
3. Increase `architecture` budget: 400 → 600 words
4. Decrease `interfaces` budget: 800 → 600 words
5. Decrease `module_map` budget: 600 → 400 words
6. Increase `quick_start` budget: 200 → 300 words
7. Update `TOTAL_BUDGET`: 3200 → 3400

**Acceptance Criteria**:
- [ ] Word budgets updated as specified
- [ ] Total budget enforced at 3400
- [ ] Truncation priority unchanged

### Task 3.2: Architecture Section Enhancement

**File**: `.claude/scripts/butterfreezone-gen.sh`

**Work**:
1. Modify `extract_architecture()` to generate a Mermaid component diagram
2. Read top-level directory structure to identify major components
3. Limit diagram to 8 nodes maximum
4. Add 2-3 sentences of narrative context after diagram
5. Preserve directory tree output after narrative

**Acceptance Criteria**:
- [ ] Architecture section contains `mermaid` code block
- [ ] Diagram has ≤8 nodes
- [ ] Narrative prose present (not just tree listing)
- [ ] Provenance tag preserved

### Task 3.3: Narrative Prose in Key Sections

**File**: `.claude/scripts/butterfreezone-gen.sh`

**Work**:
1. Modify `extract_header()`: Add 2-3 sentence narrative summary below H1
2. Modify `extract_capabilities()`: Transform from symbol list to prose with inline references
3. Modify `extract_quick_start()`: Include actual commands from README/package.json scripts
4. Add `--narrative` flag (default: true for Tier 1/2)

**Acceptance Criteria**:
- [ ] Header section has narrative summary (not just title)
- [ ] Capabilities section has prose descriptions (not just bullet lists)
- [ ] Quick start includes actual runnable commands
- [ ] Total output > 500 words

### Task 3.4: Butterfreezone Validation Update

**File**: `.claude/scripts/butterfreezone-validate.sh`

**Work**:
1. Add word count check: output must be > 500 words
2. Add architecture diagram check: mermaid marker present
3. Keep existing provenance and checksum checks

**Acceptance Criteria**:
- [ ] Validation fails if output < 500 words
- [ ] Validation fails if no architecture diagram
- [ ] Existing checks still pass
- [ ] Passes on newly generated output

---

## Sprint Summary

| Sprint | Global ID | Tasks | FRs Covered | Priority |
|--------|-----------|-------|-------------|----------|
| Sprint 1 | sprint-96 | 4 tasks | FR-1, FR-2, FR-7 | HIGH |
| Sprint 2 | sprint-97 | 5 tasks | FR-3, FR-4, FR-6 | MEDIUM |
| Sprint 3 | sprint-98 | 4 tasks | FR-5 | MEDIUM |

**Total**: 13 tasks across 3 sprints covering all 7 functional requirements.

## Close Actions (Post-Implementation)

After all sprints complete:
1. Close #320 with note: "All 3 bugs fixed in cycle-013 (LazyValue, personas, merge logic)"
2. Close #321 with note: "All 3 bugs fixed in cycle-013 (env dedup, fences, gpt-reviewer persona)"
3. Update #328 noting items 1, 3, 5 fixed; item 2 deferred to RFC; item 4 already done
4. Close #327, #323, #322, #316 with PR reference
