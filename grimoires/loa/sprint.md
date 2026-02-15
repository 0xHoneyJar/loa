# Sprint Plan: Environment Design Hardening — Bridgebuilder Review Response

> Source: Bridgebuilder review of PR #326 — 3 MEDIUM, 3 LOW, 4 PRAISE, 3 SPECULATION
> Cycle: cycle-014 (continued)
> Issue: https://github.com/0xHoneyJar/loa/issues/325
> PR: https://github.com/0xHoneyJar/loa/pull/326
> Global Sprint Counter: starts at 94
> Motivation: "Fix what the review found wrong. Build what the review found possible."

## Context

Sprints 91-93 implemented the four environment design advances (trajectory narrative, bidirectional lore, vision sprints, speculation channel). The Bridgebuilder review of PR #326 identified 3 MEDIUM findings, 3 LOW findings, and 3 SPECULATION opportunities. Additionally, 7 framework eval tests are failing because the eval fixture is stale.

### Findings Summary

| ID | Severity | Title | Sprint |
|----|----------|-------|--------|
| M-1 | MEDIUM | Trajectory generation lacks staleness indicator | 4 |
| M-2 | MEDIUM | Lore discovery overwrites instead of accumulating | 4 |
| M-3 | MEDIUM | Vision sprint timeout advisory, not enforced | 4 |
| L-1 | LOW | grep -c exit code semantics undocumented | 4 |
| L-2 | LOW | EXPLORING state not in resume state machine | 5 |
| L-3 | LOW | Prose pattern extraction not labeled experimental | 4 |
| EVAL-1-7 | CI | 7 framework eval failures (fixture stale) | 4 |
| S-1 | SPECULATION | Trajectory as Manje wrapper for multi-model | 5 |
| S-2 | SPECULATION | Discovered lore as model selection signal | 5 |
| S-3 | SPECULATION | Vision Registry as agent's dream journal | 5 |

---

## Sprint 4: Hardening — Fix All Findings + Eval Compliance

**Goal**: Address every MEDIUM and LOW finding from the Bridgebuilder review. Fix all 7 framework eval failures. Zero regressions, zero new failures.

**Global Sprint**: sprint-94

### Task 4.1: Add Staleness Indicator to Trajectory Narrative (M-1)

**Description**: Trajectory synthesizes data from multiple sources (ledger, memory, visions) without indicating when each was last updated. Stale memory data could mislead agents. Add freshness tracking.

**Files**:
- `.claude/scripts/trajectory-gen.sh` (modify)

**Changes**:
- In `extract_memory()`: capture the timestamp of the most recent observation
- In `extract_visions()`: capture the most recent vision date from entry files
- In `generate_prose()`: add freshness parenthetical after each section (e.g., "Recent learnings (2h ago):")
- In `generate_json()`: add `freshness` object with `memory_age_hours`, `visions_last_updated`, `ledger_last_modified`
- In `generate_condensed()`: append staleness warning only if any source > 7 days old

**Acceptance Criteria**:
- [ ] JSON output includes `freshness` object with per-source ages
- [ ] Prose output shows age parenthetical when source > 1 day old
- [ ] Condensed output appends "(stale: memory)" warning when source > 7 days old
- [ ] No output change when all sources are fresh (< 1 day)
- [ ] `--json` freshness includes ISO timestamps, not just relative ages

---

### Task 4.2: Accumulative Lore Discovery — Append with Dedup (M-2)

**Description**: `lore-discover.sh` overwrites `patterns.yaml` each run. For a knowledge accumulation system, destructive writes are architecturally inconsistent. Change to append-with-dedup.

**Files**:
- `.claude/scripts/lore-discover.sh` (modify)

**Changes**:
- Before writing, read existing `patterns.yaml` and extract existing IDs
- Compare new candidates against existing IDs — skip duplicates
- Append only genuinely new entries to the existing file
- Preserve the file header and manually-seeded entries
- Add `--overwrite` flag for explicit destructive behavior (not default)
- Output summary: "3 new, 2 duplicates skipped, 11 total"

**Acceptance Criteria**:
- [ ] Running twice with same bridge-id produces no duplicates
- [ ] Manually-seeded entries (graceful-degradation-cascade, etc.) are never overwritten
- [ ] New entries are appended after existing entries
- [ ] `--overwrite` flag restores original overwrite behavior
- [ ] Summary output shows new/duplicate/total counts

---

### Task 4.3: Vision Sprint Timeout Enforcement (M-3)

**Description**: The orchestrator emits `SIGNAL:VISION_SPRINT_TIMEOUT` but doesn't enforce it. Add a hard timeout at the orchestrator level as defense-in-depth.

**Files**:
- `.claude/scripts/bridge-orchestrator.sh` (modify — EXPLORING section)

**Changes**:
- Wrap the vision sprint signal emission and wait in a `timeout` command
- Use `timeout --signal=TERM ${vision_timeout}m` as a hard backstop
- On timeout: log warning, record `vision_sprint_timeout: true` in bridge state, continue to FINALIZING
- The skill layer can still handle its own timeout gracefully within the hard limit

**Acceptance Criteria**:
- [ ] Vision sprint phase is bounded by `timeout` command at orchestrator level
- [ ] Timeout triggers SIGTERM, not SIGKILL (allows cleanup)
- [ ] Bridge state records `vision_sprint_timeout: true` on timeout
- [ ] Successful completion within limit is unaffected
- [ ] Default timeout matches config value (`run_bridge.vision_sprint.timeout_minutes`)

---

### Task 4.4: Documentation Polish — grep Semantics + Experimental Labels (L-1, L-3)

**Description**: Add explanatory comments for the grep -c exit code behavior and label the prose pattern extraction as experimental.

**Files**:
- `.claude/scripts/trajectory-gen.sh` (modify — add comments at lines 99-102)
- `.claude/scripts/lore-discover.sh` (modify — add experimental label at line 155)

**Changes**:
- `trajectory-gen.sh`: Add comment block above `grep -c` calls explaining that grep -c exits 1 on zero matches (a valid result, not an error), and why `|| var=0` is needed
- `lore-discover.sh`: Add comment at `extract_prose_patterns()` labeling it as `# EXPERIMENTAL: keyword-based extraction, expect noise. Future: ML-based or LLM-assisted extraction`

**Acceptance Criteria**:
- [ ] Comment explains grep -c exit code semantics for future maintainers
- [ ] Prose extraction function labeled as experimental
- [ ] No functional changes — documentation only

---

### Task 4.5: Sync Eval Fixture with Repo Structure (EVAL-1 through EVAL-7)

**Description**: 7 framework eval tests fail because the `evals/fixtures/loa-skill-dir/` fixture is stale — it lacks the bridge scripts, lore directory, vision scripts, and ground-truth generator added in recent cycles.

**Files**:
- `evals/fixtures/loa-skill-dir/.claude/scripts/` (add missing scripts)
- `evals/fixtures/loa-skill-dir/.claude/data/lore/` (create structure)

**Changes**:
Sync the fixture with the actual repo structure. Copy minimal versions of:
1. `bridge-findings-parser.sh` — needs `bridge-findings-start` pattern
2. `bridge-state.sh` — needs `init_bridge_state` function
3. `ground-truth-gen.sh` — needs `checksums` pattern
4. `bridge-vision-capture.sh` — needs `vision-` pattern
5. `golden-path.sh` — update fixture copy to include `golden_detect_bridge_state` and `golden_bridge_progress` functions
6. `lore/index.yaml` — needs `version:` and `categories:` fields
7. `lore/mibera/core.yaml` — needs `id:`, `term:`, `short:`, `context:` fields

**Acceptance Criteria**:
- [ ] `bridge-findings-parser-works` eval passes (file exists + marker pattern)
- [ ] `bridge-state-schema-valid` eval passes (file exists + init function)
- [ ] `golden-path-bridge-detection` eval passes (bridge state detection functions)
- [ ] `gt-checksums-match` eval passes (file exists + checksums pattern)
- [ ] `lore-entries-schema` eval passes (required fields in core.yaml)
- [ ] `lore-index-valid` eval passes (version + categories in index.yaml)
- [ ] `vision-entries-traceability` eval passes (file exists + vision pattern)
- [ ] All 32 previously-passing framework evals still pass
- [ ] Run `evals/harness/run-eval.sh --suite framework` confirms 39/39 pass

---

## Sprint 5: Enhancement — State Recovery + Speculation Primitives

**Goal**: Implement the EXPLORING state recovery path and build the most impactful speculation primitives: source model attribution, vision revisitation tracking, and lore freshness in the trajectory narrative.

**Global Sprint**: sprint-95

### Task 5.1: EXPLORING State Resume Recovery (L-2)

**Description**: Crash during the EXPLORING phase has no recovery path. The resume logic handles ITERATING but not EXPLORING. Since convergence was already achieved when EXPLORING starts, the simplest and safest recovery is to skip to FINALIZING.

**Files**:
- `.claude/scripts/bridge-orchestrator.sh` (modify — resume section)

**Changes**:
- Add `EXPLORING` to the resume state machine
- On resume from EXPLORING: log "Convergence was achieved. Skipping exploration, proceeding to finalization."
- Set state to FINALIZING and continue
- Record `vision_sprint_skipped: "resumed"` in bridge state

**Acceptance Criteria**:
- [ ] `--resume` from EXPLORING state proceeds to FINALIZING
- [ ] Bridge state records that exploration was skipped due to resume
- [ ] No data loss — convergence findings from prior iterations are preserved
- [ ] Log message explains why exploration was skipped

---

### Task 5.2: Source Model Attribution in Discovered Lore (S-2 Prep)

**Description**: Add `source_model` field to discovered lore entries, recording which model produced the PRAISE finding or insight. This enables future model-affinity routing in the Hounfour.

**Files**:
- `.claude/scripts/lore-discover.sh` (modify — add source_model extraction)
- `.claude/data/lore/discovered/patterns.yaml` (modify — add source_model to seeded entries)

**Changes**:
- In `extract_praise_patterns()`: look for model attribution in findings JSON (if present)
- Add `source_model` field to YAML output: `source_model: "claude-opus-4"` or `source_model: "unknown"`
- Update the 3 seeded patterns with `source_model: "claude-opus-4"` (they came from the Claude-powered Bridgebuilder)
- Field is optional — missing model info defaults to `"unknown"`

**Acceptance Criteria**:
- [ ] New lore entries include `source_model` field when model info is available
- [ ] Seeded patterns have `source_model: "claude-opus-4"`
- [ ] Missing model info produces `source_model: "unknown"` (not an error)
- [ ] Field is documented in discovered/patterns.yaml header comment

---

### Task 5.3: Vision Revisitation Frequency Tracking (S-3 Partial)

**Description**: Track how often visions are referenced in bridge reviews. High-frequency references suggest the vision is becoming a pattern that should be elevated to lore. This is the "spaced repetition for architectural ideas" concept.

**Files**:
- `.claude/scripts/bridge-vision-capture.sh` (modify — add `--record-reference` mode)
- `grimoires/loa/visions/index.md` (modify — add Refs column)

**Changes**:
- New subcommand: `bridge-vision-capture.sh --record-reference <vision-id> <bridge-id>`
- Increments a reference counter for the specified vision in index.md
- Add `| Refs |` column to the Active Visions table
- When ref count exceeds threshold (default: 3), emit a log suggesting lore elevation
- Bridge orchestrator can call this after each review iteration when a vision is mentioned

**Acceptance Criteria**:
- [ ] `--record-reference` increments the ref counter for a vision
- [ ] Ref count is visible in the Active Visions table
- [ ] Threshold crossing emits a log message: "vision-001 referenced 4 times — consider elevating to lore"
- [ ] Existing visions start at ref count 0

---

### Task 5.4: Lore Freshness in Trajectory Narrative

**Description**: Extend the trajectory narrative to include a one-line lore summary: how many discovered patterns exist, when the last one was discovered, and whether any visions have high revisitation counts.

**Files**:
- `.claude/scripts/trajectory-gen.sh` (modify — add `extract_lore()` function)

**Changes**:
- New function `extract_lore()`: reads `discovered/patterns.yaml`, counts entries, gets latest source date
- In prose mode: add "**Discovered patterns** (N total, latest from bridge-YYYYMMDD): [top 2 pattern names]"
- In JSON mode: add `lore` object with `discovered_count`, `latest_bridge`, `high_revisit_visions[]`
- In condensed mode: append "N patterns discovered" to the one-liner

**Acceptance Criteria**:
- [ ] Prose trajectory includes discovered lore summary
- [ ] JSON trajectory includes lore object
- [ ] Condensed trajectory appends pattern count
- [ ] Graceful degradation when no discovered patterns exist
- [ ] High-revisitation visions (ref > 3) are highlighted

---

## Summary

| Sprint | Global ID | Tasks | Theme |
|--------|-----------|-------|-------|
| Sprint 4 | sprint-94 | 5 | Fix all findings + eval compliance |
| Sprint 5 | sprint-95 | 4 | State recovery + speculation primitives |
| **Total** | | **9** | Bridgebuilder review response |

### Relationship to Previous Sprints

```
Sprint 91-93 (COMPLETED): Build the four environment advances
  └── Sprint 94 (HARDENING): Fix every finding from Bridgebuilder review
  └── Sprint 95 (ENHANCEMENT): Build the most impactful speculations
```

### Dependencies

```
Sprint 4 (Hardening) — all tasks independent, can run in any order
  └── Task 4.1 (staleness) — standalone
  └── Task 4.2 (accumulative lore) — standalone
  └── Task 4.3 (timeout enforcement) — standalone
  └── Task 4.4 (docs) — standalone
  └── Task 4.5 (eval fixture) — standalone

Sprint 5 (Enhancement) — depends on Sprint 4 completion
  └── Task 5.1 (EXPLORING recovery) — standalone
  └── Task 5.2 (source model) — depends on 4.2 (accumulative lore)
  └── Task 5.3 (revisitation) — standalone
  └── Task 5.4 (lore in trajectory) — depends on 5.2 (source model) and 5.3 (revisitation)
```

### Success Criteria

- [ ] All 3 MEDIUM findings resolved
- [ ] All 3 LOW findings resolved
- [ ] Framework eval suite: 39/39 passing (was 32/39)
- [ ] No regressions in hounfour test suite (15/15)
- [ ] Source model attribution in discovered lore entries
- [ ] Vision revisitation tracking operational
- [ ] Trajectory narrative includes lore freshness

### Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Eval fixture sync breaks existing tests | Low | Medium | Run full suite before and after |
| Accumulative lore produces merge conflicts | Low | Low | Per-entry dedup by ID |
| Vision ref counter regex fails on new table format | Low | Low | Test against all 3 existing visions |
| Source model field breaks lore schema consumers | Low | Low | Field is optional, defaults to "unknown" |
