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

## Sprint 4: Bridgebuilder Review Fixes (PR #330 findings)

> **Goal**: Address all 9 findings from Bridgebuilder review — 1 HIGH, 3 MEDIUM, 5 LOW
> **Global ID**: sprint-99
> **Source**: [Bridgebuilder Review on PR #330](https://github.com/0xHoneyJar/loa/pull/330#issuecomment-3903185016)
> **Scope**: Correctness, portability, and architecture fixes across all 3 implementation sprints

### Task 4.1: Phase 2 Tertiary Scoring Output + Consensus Integration (HIGH)

**Files**: `.claude/scripts/flatline-orchestrator.sh` (Phase 1 output, Phase 2 output, Phase 3 consensus)

**Finding**: Phase 2 computes 6 tertiary scoring files but only returns 2 file paths. Phase 3 consensus never sees the tertiary cross-validation results. The cost is incurred but the value is discarded.

**Work**:
1. **Phase 1 output** (line ~691): Only output tertiary file paths when `has_tertiary=true`:
   ```bash
   if [[ "$has_tertiary" == "true" ]]; then
       echo "$tertiary_review_file"
       echo "$tertiary_skeptic_file"
   fi
   ```
2. **Phase 2 output** (line ~817): Output all 6 scoring file paths when tertiary is active:
   ```bash
   echo "$gpt_scores_file"
   echo "$opus_scores_file"
   if [[ "$has_tertiary" == "true" ]]; then
       echo "$tertiary_scores_opus_file"
       echo "$tertiary_scores_gpt_file"
       echo "$gpt_scores_tertiary_file"
       echo "$opus_scores_tertiary_file"
   fi
   ```
3. **Main orchestrator**: Update Phase 2 caller to detect 4-line vs 6-line Phase 1 output, and Phase 3 caller to detect 2-line vs 6-line Phase 2 output
4. **Phase 3 consensus** (`run_consensus()`): Accept optional tertiary scoring files and merge them into consensus. When tertiary scores exist, each improvement gets 3 scores instead of 2 — adjust thresholds proportionally (e.g., HIGH_CONSENSUS requires 2/3 models >700)

**Acceptance Criteria**:
- [ ] Phase 1 only outputs tertiary paths when tertiary is configured
- [ ] Phase 2 returns all scoring file paths (2 or 6 depending on config)
- [ ] Phase 3 consensus incorporates tertiary scores when present
- [ ] 2-model mode unchanged (4 Phase 1 → 2 Phase 2 → consensus with 2 scores)
- [ ] 3-model mode works end-to-end (6 Phase 1 → 6 Phase 2 → consensus with 3 scores)
- [ ] `bash -n` passes

### Task 4.2: Atomic Lock Recovery in mkdir Strategy (MEDIUM + LOW)

**File**: `.claude/scripts/bridge-state.sh:75-120`

**Findings**:
- **TOCTOU window** (med-1): After `rm -rf "$lock_dir"`, another process can grab the lock before we retry `mkdir` in the next loop iteration
- **PID file write gap** (low-1): If process crashes between `mkdir` and `echo $$ > pid`, stale detection can't identify the holder

**Work**:
1. After `rm -rf` for stale lock, immediately attempt `mkdir` + PID write before `continue`:
   ```bash
   if [[ -n "$holder_pid" ]] && ! kill -0 "$holder_pid" 2>/dev/null; then
       echo "WARNING: Removing stale lock (PID $holder_pid no longer running)" >&2
       rm -rf "$lock_dir"
       if mkdir "$lock_dir" 2>/dev/null; then
           echo $$ > "$lock_dir/pid"
           return 0
       fi
       continue
   fi
   ```
2. Apply same pattern to age-based stale detection block
3. Ensure PID write immediately follows successful mkdir (already the case for non-recovery path, but make explicit)

**Acceptance Criteria**:
- [ ] After stale lock cleanup, immediately claim instead of re-entering loop
- [ ] No TOCTOU window between `rm -rf` and next `mkdir`
- [ ] Both PID-based and age-based recovery paths use atomic cleanup-and-acquire
- [ ] `bash -n` passes

### Task 4.3: Fix Flatline Check Unused Window Parameter (MEDIUM)

**File**: `.claude/scripts/bridge-flatline-check.sh`

**Finding**: Usage docs describe a `[window]` parameter ($1) but only `$2` (threshold) is read. The window is already computed by `bridge-state.sh` and stored in state — this script is a reader, not a computer.

**Work**:
1. Remove window parameter from usage comments (lines 12-14)
2. Change `THRESHOLD="${2:-0.05}"` to `THRESHOLD="${1:-0.05}"` (threshold becomes first and only positional arg)
3. Update usage to:
   ```
   # Usage:
   #   bridge-flatline-check.sh [threshold]
   #   bridge-flatline-check.sh          # default: 0.05
   #   bridge-flatline-check.sh 0.10     # custom: 10% threshold
   ```

**Acceptance Criteria**:
- [ ] Usage docs match actual behavior
- [ ] `bridge-flatline-check.sh 0.10` sets threshold to 0.10
- [ ] No unused positional args
- [ ] `bash -n` passes

### Task 4.4: Replace `echo -e` with `printf` in Mermaid Generation (MEDIUM)

**File**: `.claude/scripts/butterfreezone-gen.sh:629-660`

**Finding**: `echo -e` is a bashism. POSIX `echo` does not define `-e` behavior. On some macOS configurations, `echo -e` outputs literal `-e`. Ironic in a portability-focused PR.

**Work**:
1. Replace Mermaid string building to use `printf` instead of `echo -e`:
   ```bash
   # Build mermaid as actual multi-line string using printf
   mermaid=$(printf '```mermaid\ngraph TD')
   # ... in loop ...
   mermaid=$(printf '%s\n    %s[%s]' "$mermaid" "$id" "$dir")
   ```
2. Replace output:
   ```bash
   $(if [[ -n "$mermaid" ]]; then printf '%s\n' "$mermaid"; echo; fi)
   ```
3. Check for any other `echo -e` usage in the file and replace

**Acceptance Criteria**:
- [ ] No `echo -e` in `butterfreezone-gen.sh`
- [ ] Mermaid block renders correctly (test with actual output)
- [ ] `bash -n` passes

### Task 4.5: Explicit Exit Code Capture in model-invoke Fallback (LOW)

**File**: `.claude/scripts/gpt-review-api.sh:827-832`

**Finding**: `$?` inside `|| { }` block could be fragile across shells. Explicit capture is more portable.

**Work**:
1. Refactor from:
   ```bash
   response=$(call_api_via_model_invoke ...) || {
       local mi_exit=$?
       log "WARNING: model-invoke failed (exit $mi_exit)..."
       response=$(call_api ...)
   }
   ```
   To:
   ```bash
   local mi_exit=0
   response=$(call_api_via_model_invoke ...) || mi_exit=$?
   if [[ $mi_exit -ne 0 ]]; then
       log "WARNING: model-invoke failed (exit $mi_exit), falling back to direct API call"
       response=$(call_api "$model" "$system_prompt" "$user_prompt" "$timeout")
   fi
   ```

**Acceptance Criteria**:
- [ ] Exit code captured explicitly before any other statement
- [ ] Fallback behavior unchanged
- [ ] `bash -n` passes

### Task 4.6: Scope Architecture Diagram Validation to Section (LOW)

**File**: `.claude/scripts/butterfreezone-validate.sh:507-518`

**Finding**: The validation checks for mermaid/code blocks anywhere in the file. A code block in Quick Start satisfies the Architecture diagram check.

**Work**:
1. Extract Architecture section content before checking for diagrams:
   ```bash
   validate_architecture_diagram() {
       if ! grep -q "^## Architecture" "$FILE" 2>/dev/null; then
           log_warn "arch_section" "Missing Architecture section" "section missing"
           return 0
       fi

       # Extract Architecture section only (between ## Architecture and next ## heading)
       local arch_content
       arch_content=$(sed -n '/^## Architecture/,/^## /p' "$FILE" | sed '$ d')
       if echo "$arch_content" | grep -q "mermaid"; then
           log_pass "arch_diagram" "Architecture section contains Mermaid diagram"
       elif echo "$arch_content" | grep -q '```'; then
           log_pass "arch_diagram" "Architecture section contains code block diagram"
       else
           log_warn "arch_diagram" "Architecture section missing diagram (mermaid or code block)" "diagram missing"
       fi
   }
   ```

**Acceptance Criteria**:
- [ ] Architecture diagram check only looks at Architecture section
- [ ] Code blocks in other sections don't trigger false pass
- [ ] `bash -n` passes

### Task 4.7: Document Construct Sync Version Limitation (LOW)

**File**: `.claude/scripts/sync-constructs.sh`

**Finding**: Registered skills get `"version": "synced"` — a sentinel that doesn't track real versions. On subsequent pack updates, the version won't update because the script only checks existence.

**Work**:
1. Add comment documenting the limitation:
   ```bash
   # NOTE: Version tracking is existence-only (v1).
   # Registered skills get version "synced" — a sentinel.
   # Future: compare manifest version against registered version
   # for construct update detection.
   ```
2. Add version comparison TODO in the `if [[ -z "$registered" ]]` block:
   ```bash
   if [[ -z "$registered" ]]; then
       # New skill — register it
       ...
   # else
   #   TODO: Compare manifest version against registered version
   #   for construct update detection (v2)
   fi
   ```

**Acceptance Criteria**:
- [ ] Limitation documented in code comments
- [ ] No functional change
- [ ] Future upgrade path clear

---

## Sprint Summary

| Sprint | Global ID | Tasks | Scope | Priority |
|--------|-----------|-------|-------|----------|
| Sprint 1 | sprint-96 | 4 tasks | FR-1, FR-2, FR-7 | HIGH |
| Sprint 2 | sprint-97 | 5 tasks | FR-3, FR-4, FR-6 | MEDIUM |
| Sprint 3 | sprint-98 | 4 tasks | FR-5 | MEDIUM |
| Sprint 4 | sprint-99 | 7 tasks | Bridgebuilder review fixes | HIGH (blocking) |

**Total**: 20 tasks across 4 sprints. Sprint 4 addresses all 9 Bridgebuilder findings (1 HIGH, 3 MEDIUM, 5 LOW).

## Close Actions (Post-Implementation)

After all sprints complete:
1. Close #320 with note: "All 3 bugs fixed in cycle-013 (LazyValue, personas, merge logic)"
2. Close #321 with note: "All 3 bugs fixed in cycle-013 (env dedup, fences, gpt-reviewer persona)"
3. Update #328 noting items 1, 3, 5 fixed; item 2 deferred to RFC; item 4 already done
4. Close #327, #323, #322, #316 with PR reference
5. Reply to Bridgebuilder review on PR #330 with resolution status for each finding
