# Sprint Plan: Vision-Aware Planning — Creative Agency for AI Peers

**Cycle**: cycle-041
**PRD**: `grimoires/loa/prd.md` (v1.1)
**SDD**: `grimoires/loa/sdd.md` (v1.1)

---

## Sprint 1 (Global: Sprint-74) — Foundation: Schema, Library, Query, Shadow Mode

### T1: Create `vision-lib.sh` shared library
- [ ] **File**: `.claude/scripts/vision-lib.sh` (new)
- [ ] Extract `update_vision_status()` from `bridge-vision-capture.sh:32-66`
- [ ] Extract `record_reference()` from `bridge-vision-capture.sh:75-121`
- [ ] Extract `extract_pr_tags()` from `bridge-vision-capture.sh:129-152`
- [ ] Extract `check_relevant_visions()` from `bridge-vision-capture.sh:157-207`
- [ ] Add new functions: `vision_load_index()`, `vision_match_tags()`, `vision_sanitize_text()`, `vision_validate_entry()`, `vision_atomic_write()`
- [ ] Source `bootstrap.sh` and `compat-lib.sh` (for `_require_flock`)
- [ ] Dependency check for jq at source time
- [ ] **Shell safety** *(SKP-005)*: All variables double-quoted, vision IDs validated against `^vision-[0-9]{3}$` regex, file paths validated against visions directory (no traversal), tag values validated against `^[a-z][a-z0-9_-]*$` allowlist
- **Acceptance**: All functions callable, unit tests pass, no unquoted variables in shellcheck

### T2: Refactor `bridge-vision-capture.sh` to source library
- [ ] **File**: `.claude/scripts/bridge-vision-capture.sh` (modify)
- [ ] Add `source "$SCRIPT_DIR/vision-lib.sh"` at top
- [ ] Remove inline function definitions (replaced by library)
- [ ] Keep all existing entry points unchanged: `--check-relevant`, `--record-reference`, `--update-status`, main capture mode
- [ ] Error exit if `vision-lib.sh` is missing (no silent fallback)
- [ ] **Rollback plan** *(IMP-001)*: If refactor breaks capture, revert to inline functions by copying them back from git history. Run `bridge-vision-capture.sh --check-relevant` and `--record-reference` as smoke tests before committing.
- **Acceptance**: All existing capture behaviors identical. Existing bridge tests pass. Smoke test both entry points.

### T3: Vision Registry schema definition
- [ ] **File**: `grimoires/loa/visions/index.md` (create bootstrap template)
- [ ] Schema version comment: `<!-- schema_version: 1 -->`
- [ ] Table header: `| ID | Title | Source | Status | Tags | Refs |`
- [ ] `vision_validate_entry()` checks required fields: ID, Source, Status, Tags, Insight section
- [ ] Malformed entries logged and skipped, not fatal
- **Acceptance**: Validation function correctly accepts/rejects test fixtures

### T4: Create `vision-registry-query.sh`
- [ ] **File**: `.claude/scripts/vision-registry-query.sh` (new)
- [ ] Source `vision-lib.sh`
- [ ] Arguments: `--tags`, `--status`, `--min-overlap`, `--max-results`, `--visions-dir`, `--json`, `--include-text`
- [ ] **Tag derivation rules** *(IMP-002)*: When `--tags` is `auto`, derive from sprint context:
  - File paths: `*orchestrator*|*architect*|*bridge*` → `architecture`, `*security*|*redact*` → `security`, etc.
  - Keywords: match user request text against controlled vocabulary
  - PRD sections: map section headers to tags
  - Example: sprint modifying `flatline-orchestrator.sh` + `scoring-engine.sh` → tags `architecture,multi-model`
- [ ] Scoring: `(tag_overlap * 3) + (refs * 2) + recency_bonus`
- [ ] Recency bonus: 1 if Date within 30 days, else 0
- [ ] Sort by score descending, tie-break by vision ID
- [ ] Handle empty/missing registry gracefully (return `[]`)
- [ ] Dependency check for jq, yq
- [ ] **Shell safety** *(SKP-005)*: All `--tags` input validated against `^[a-z][a-z0-9_,-]*$`, `--visions-dir` validated as existing directory under project root, `--status` values checked against enum
- **Acceptance**: Returns correct JSON for all fixture scenarios. Auto-tag derivation tested with example paths. Invalid input rejected with clear error.

### T5: Configuration & feature flags
- [ ] **File**: `.loa.config.yaml.example` (modify)
- [ ] Add `vision_registry:` section with all config keys and defaults
- [ ] **File**: `.loa.config.yaml` (modify)
- [ ] Add `vision_registry:` section with `enabled: false` default
- [ ] All settings readable via `yq eval '.vision_registry.X // default'`
- **Acceptance**: Config reads return correct defaults when section is absent

### T6: Shadow mode logging pipeline
- [ ] **File**: `.claude/scripts/vision-registry-query.sh` (extend with `--shadow` mode)
- [ ] Shadow log output to `grimoires/loa/a2a/trajectory/vision-shadow-{date}.jsonl`
- [ ] Log format: timestamp, cycle, work_tags, matches array, shadow_cycle_number
- [ ] **File**: `grimoires/loa/visions/.shadow-state.json` (new, atomic writes)
- [ ] Track `shadow_cycles_completed`, `last_shadow_run`, `matches_during_shadow`
- [ ] Graduation check: if cycles >= threshold AND matches > 0, output prompt flag
- **Acceptance**: Shadow logs written correctly, counter increments, graduation detected

### T7: Vision reference tracking with flock
- [ ] **File**: `.claude/scripts/vision-lib.sh` (in `vision_record_ref`)
- [ ] Wrap read-modify-write in `flock` (using `_require_flock` from compat-lib.sh)
- [ ] Lock file: `{index_file}.lock`
- [ ] 5-second timeout on lock acquisition
- [ ] Same flock pattern for `vision_update_status()`
- **Acceptance**: Concurrent ref updates don't corrupt counters (tested with parallel writers)

### T8: Unit tests for vision-lib.sh
- [ ] **File**: `tests/unit/vision-lib.bats` (new)
- [ ] Tests: load_index (empty, valid, malformed), match_tags (overlap, zero, boundary), sanitize_text (clean, injection, truncation), validate_entry (valid, missing fields)
- [ ] **File**: `tests/unit/vision-registry-query.bats` (new)
- [ ] Tests: empty registry, matches, max-results, min-overlap, status filter, scoring, include-text
- [ ] **File**: `tests/fixtures/vision-registry/` (new directory)
- [ ] Fixtures: index-empty.md, index-three-visions.md, index-malformed.md, entry-valid.md, entry-malformed.md, entry-injection.md
- **Acceptance**: All BATS tests pass

### Dependencies
- T1 → T2 (library before refactor)
- T1 → T4 (library before query script)
- T3 → T4 (schema before query)
- T1 → T7 (library before flock integration)
- T4 → T6 (query before shadow mode)
- T5 is independent
- T8 depends on T1, T3, T4, T6

---

## Sprint 2 (Global: Sprint-75) — Active Presentation

### T1: Vision loading in discovering-requirements SKILL.md
- [ ] **File**: `.claude/skills/discovering-requirements/SKILL.md` (modify)
- [ ] Add Step 0.5 after reality file loading
- [ ] Read vision_registry config
- [ ] If disabled: skip entirely (no mention to user)
- [ ] Derive work_context_tags using tag derivation rules (sprint files → keywords → PRD sections)
- [ ] Call `vision-registry-query.sh`
- [ ] Branch: shadow mode → log silently; active mode → present to user
- **Acceptance**: SKILL.md correctly routes between shadow and active modes

### T2: Vision presentation template
- [ ] **File**: `.claude/skills/discovering-requirements/SKILL.md` (in Step 0.5)
- [ ] Template for presenting matched visions with provenance
- [ ] Per-vision user choice: Explore / Defer / Skip
- [ ] "Explore" calls `vision_update_status()` to transition Captured → Exploring
- [ ] All choices logged to trajectory JSONL
- [ ] Template-based relevance explanation (not LLM-generated)
- **Acceptance**: Visions presented with correct provenance, choices recorded

### T3: Content sanitization — allowlist extraction
- [ ] **File**: `.claude/scripts/vision-lib.sh` (strengthen `vision_sanitize_text`)
- [ ] Primary: extract only text between `## Insight` and next heading
- [ ] Normalize: decode HTML entities, strip zero-width chars
- [ ] Secondary: pattern strip `<system>`, `<prompt>`, code fences
- [ ] Truncate to 500 chars
- [ ] Adversarial test fixtures: injection.md, encoded instructions, nested markdown
- [ ] **Semantic threat tests** *(IMP-003)*: test entries with indirect instructions ("please ignore previous context"), role-play prompts, and encoded directives
- **Acceptance**: All adversarial fixtures sanitized to safe output including semantic threats

### T4: Shadow graduation prompt
- [ ] When shadow cycles meet threshold AND matches > 0
- [ ] Present summary: "Over N cycles, M visions matched your work"
- [ ] Offer: Enable active mode / Adjust thresholds / Keep shadow / Disable
- [ ] On "Enable": set `shadow_mode: false` in config (via yq)
- **Acceptance**: Graduation prompt appears at correct threshold, config updated on choice

### T5: Integration tests
- [ ] **File**: `tests/integration/vision-planning-integration.bats` (new)
- [ ] E2E: config disabled = zero vision code runs
- [ ] E2E: shadow mode logs but doesn't present
- [ ] E2E: active mode presents and tracks refs
- [ ] E2E: bridge-vision-capture.sh still works after refactor
- [ ] **Cross-sprint regression** *(IMP-005)*: run Sprint 1 unit tests as part of Sprint 2 integration suite to catch regressions from SKILL.md changes
- **Acceptance**: All integration tests pass, Sprint 1 unit tests still green

### Dependencies
- T3 before T2 (sanitization before presentation)
- T1 before T2 (SKILL.md routing before template)
- T4 depends on T1
- T5 depends on all

---

## Sprint 3 (Global: Sprint-76) — Creative Agency (Experimental)

### T1: Vision-inspired requirement proposals
- [ ] **File**: `.claude/skills/discovering-requirements/SKILL.md` (extend)
- [ ] When `propose_requirements: true` AND a vision is marked "Explore"
- [ ] Load full vision entry, synthesize with work context
- [ ] Propose 1-3 requirements tagged `[VISION-INSPIRED]`
- [ ] Separate PRD section: "## Vision-Inspired Requirements"
- [ ] Each traces to source vision ID with provenance
- [ ] User accept/modify/reject per proposal
- **Acceptance**: Vision-inspired requirements appear in separate section, traceable

### T2: Lore elevation automation
- [ ] **File**: `.claude/scripts/vision-lib.sh` (new function `vision_check_lore_elevation`)
- [ ] When ref count exceeds threshold, output elevation suggestion
- [ ] Format compatible with `lore-discover.sh` input
- [ ] Populate `visions.yaml` lore file with elevated entries
- **Acceptance**: High-ref visions produce lore elevation suggestions

### T3: Documentation
- [ ] **File**: `.loa.config.yaml.example` (verify all vision settings documented)
- [ ] Vision workflow documented in existing reference files
- **Acceptance**: Configuration is self-documenting

### Dependencies
- T1 is independent (builds on Sprint 2 SKILL.md changes)
- T2 depends on Sprint 1 T7 (ref tracking)
- T3 is independent
