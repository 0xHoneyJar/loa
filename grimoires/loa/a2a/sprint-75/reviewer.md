# Sprint 75 (Sprint 2) Implementation Report — Vision-Aware Active Presentation

## Summary

Sprint 2 implements the active presentation layer for the Vision Registry, integrating vision queries into the `/plan-and-analyze` SKILL.md workflow, strengthening content sanitization, and adding comprehensive integration tests.

## Tasks Completed

### T1: Vision Loading Step in SKILL.md
- Added Step 0.5 between Phase 0 (Context Synthesis) and Phase 0.5 (Targeted Interview)
- Config check gates all vision code on `vision_registry.enabled: true`
- Tag derivation from changed files and PRD keywords
- Shadow mode: silent JSONL logging, no user-visible output
- Active mode: presents matched visions with scores and insights

### T2: Vision Presentation Template
- User choices: [E]xplore (increments refs, updates status), [D]efer, [S]kip All
- Graduation prompt after shadow threshold crossed with matches > 0
- Template includes vision ID, title, score, matched tags, and sanitized insight

### T3: Content Sanitization Strengthening (Audit ADVISORY-2)
- Case-insensitive `sed -E` patterns for `<system>`, `<prompt>`, `<instructions>` tags
- Additional XML directive stripping: `<context>`, `<role>`, `<user>`, `<assistant>`
- Case-insensitive `grep -viE` for indirect instruction patterns:
  - "ignore previous", "forget all", "you are now", "act as", "pretend to be"
  - "ignore all", "ignore the above", "do not follow", "new instructions", "reset context"
- New fixture: `entry-semantic-threat.md` with mixed-case attack vectors
- New test: `vision_sanitize_text: strips case-insensitive injection patterns`

### T4: Shadow Graduation Detection
- Graduation triggered when `shadow_cycles >= threshold AND matches > 0`
- Returns `{results, graduation: {ready: true, shadow_cycles, total_matches}}` JSON
- SKILL.md prompts user: "Vision Registry has been running in shadow mode..."

### T5: Integration Tests (10 tests)
- E2E: config disabled returns results (config check is caller's responsibility)
- E2E: shadow mode writes JSONL and updates `.shadow-state.json`
- E2E: active mode returns scored results with sanitized text
- E2E: ref tracking increments on active mode interaction
- E2E: capture script `--help` still works
- E2E: capture script `--check-relevant` works with empty index
- E2E: capture script creates vision entries from findings
- E2E: graduation triggers after threshold cycles
- Regression: Sprint 1 vision-lib tests still pass
- Regression: Sprint 1 vision-registry-query tests still pass

## Bug Fix During Implementation

- Shadow JSONL log entries were written as multi-line pretty-printed JSON. Fixed by adding `-c` (compact) flag to `jq -n` call in `vision-registry-query.sh:323`.

## Test Results

- Unit tests: 53/53 passing
- Integration tests: 10/10 passing
- Total: 63 tests, 0 failures

## Files Changed

| File | Change |
|------|--------|
| `.claude/scripts/vision-registry-query.sh` | Shadow JSONL compact output fix |
| `.claude/scripts/vision-lib.sh` | Case-insensitive sanitization patterns |
| `.claude/skills/discovering-requirements/SKILL.md` | Step 0.5 vision loading |
| `tests/unit/vision-lib.bats` | +1 semantic threat test |
| `tests/integration/vision-planning-integration.bats` | +10 integration tests |
| `tests/fixtures/vision-registry/entry-semantic-threat.md` | New fixture |
| `grimoires/loa/a2a/sprint-75/reviewer.md` | This report |
