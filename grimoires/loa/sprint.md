# Sprint Plan: cycle-055 — Bridgebuilder A4 + A5 Completions

**Cycle**: cycle-055-bridgebuilder-a4-a5
**Branch**: feat/cycle-055-bridgebuilder-a4-a5
**PRD**: Issue 0xHoneyJar/loa#464 (Part A items A4 and A5)
**Roadmap**: Issue 0xHoneyJar/loa#467 (Option C)
**Date**: 2026-04-13

---

## Cycle Summary

Complete the last two open items from #464's Part A follow-up list. Both are "written but unwired" features in the multi-model Bridgebuilder that have ineffective config flags today:

- **A4**: `core/cross-repo.ts` exports (`detectRefs`, `parseManualRefs`, `fetchCrossRepoContext`) are unit-tested but never invoked from the multi-model review path. `config.cross_repo.auto_detect` + `config.cross_repo.manual_refs` are effectively no-ops.
- **A5**: `template.buildEnrichedSystemPrompt()` accepts `loreEntries` but no code loads `grimoires/loa/lore/patterns.yaml`. `config.depth_5.lore_active_weaving` is a no-op.

Both features have concrete acceptance criteria already written in #464. No PRD/SDD needed — this sprint plan goes straight from #464 into `/run sprint-plan`.

---

## Sprint 1: A5 — Lore Active Weaving

**Scope**: SMALL (3 tasks)
**FRs**: FR-A5.1 (loader), FR-A5.2 (wiring), FR-A5.3 (tests)
**Goal**: When `depth_5.lore_active_weaving: true`, load `grimoires/loa/lore/patterns.yaml`, parse entries into `LoreEntry[]`, pass through `executeMultiModelReview()` to `template.buildEnrichedSystemPrompt()`.

### Rationale for ordering A5 first

A5 is self-contained (pure function: read file → parse → return typed entries). No network, no timeouts, no failure cases beyond "file missing" or "malformed YAML." Lower risk than A4 which has network egress. Getting A5 green first proves the wiring path before we add A4's complexity.

### Tasks

| ID | Task | File(s) | FR | Goal |
|----|------|---------|-----|------|
| T1 | Create `core/lore-loader.ts`. Export `loadLoreEntries(path: string): Promise<LoreEntry[]>` that reads YAML, parses, validates required fields (id, term, short, context), and returns typed entries. Handle missing file → `[]` + logger.warn. Handle malformed YAML → throw with actionable message. | `.claude/skills/bridgebuilder-review/resources/core/lore-loader.ts` (new) | FR-A5.1 | G-1 |
| T2 | Wire `loadLoreEntries()` into `main.ts` multi-model path: load once per review run (not per item), pass `loreEntries` through `executeMultiModelReview()` into `EnrichmentContext`, thread to `buildEnrichedSystemPrompt()`. Only invoke when `config.depth_5.lore_active_weaving === true`. Path configurable via `config.depth_5.lore_path` with default `grimoires/loa/lore/patterns.yaml`. | `.claude/skills/bridgebuilder-review/resources/main.ts`, `.claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts` | FR-A5.2 | G-1 |
| T3 | Unit tests for `loadLoreEntries`: (a) parses valid YAML with multiple entries, (b) validates required fields, (c) empty file → `[]`, (d) missing file → `[]` + warning logged, (e) malformed YAML → throws with helpful message. Node test runner + tsx. | `.claude/skills/bridgebuilder-review/resources/core/__tests__/lore-loader.test.ts` (new) | FR-A5.3 | G-3 |

### Acceptance Criteria (A5)

- [ ] `loadLoreEntries()` exists and is exported from `core/lore-loader.ts`
- [ ] `main.ts` calls loader when `lore_active_weaving` is true, skips otherwise
- [ ] Lore entries reach `buildEnrichedSystemPrompt()` via `EnrichmentContext`
- [ ] `lore_path` config default works; override works
- [ ] Missing `patterns.yaml` does NOT crash — loader returns `[]` with warning
- [ ] Unit tests pass (5 tests in Node test runner)
- [ ] Existing Bridgebuilder unit tests still pass
- [ ] `npm run build` succeeds; `dist/` committed

---

## Sprint 2: A4 — Cross-Repo Context Wiring

**Scope**: MEDIUM (4 tasks)
**FRs**: FR-A4.1 (auto-detect), FR-A4.2 (manual refs), FR-A4.3 (prompt injection), FR-A4.4 (tests)
**Goal**: Wire `core/cross-repo.ts` into multi-model review. `config.cross_repo.auto_detect: true` triggers `detectRefs()` against PR title+body. `config.cross_repo.manual_refs: [...]` passes through `parseManualRefs()`. Both feed `fetchCrossRepoContext()` with its documented per-ref (5s) and total (30s) timeouts. Fetched context is appended to the review user prompt under a clearly-marked section.

### Tasks

| ID | Task | File(s) | FR | Goal |
|----|------|---------|-----|------|
| T1 | Add cross-repo resolution step in `main.ts` multi-model path, BEFORE `executeMultiModelReview`: combine `auto_detect` results (from PR title + body) with `manual_refs`. Deduplicate. Call `fetchCrossRepoContext()`. Capture timings for observability. | `.claude/skills/bridgebuilder-review/resources/main.ts` | FR-A4.1, FR-A4.2 | G-2 |
| T2 | Thread `crossRepoContext` through `executeMultiModelReview()` signature and down to `template.buildConvergenceUserPrompt()`. Append a `## Cross-Repository Context` section when non-empty. Truncate to a configurable max bytes (default 20KB) to protect input token budget. | `.claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts`, `.claude/skills/bridgebuilder-review/resources/core/template.ts` | FR-A4.3 | G-2 |
| T3 | Graceful degradation: if any ref fetch times out, include successful fetches + warning note in context (`[timeout fetching <ref>]`). Do NOT fail the review. Log per-ref latencies. | `.claude/skills/bridgebuilder-review/resources/main.ts` | FR-A4.3 | G-4 |
| T4 | Integration tests: (a) no refs → context empty, prompt unchanged; (b) detected ref + successful fetch → context appears in user prompt; (c) timeout → successful refs included, timeout note present. Use mock `fetchRef` to avoid real network in CI. | `.claude/skills/bridgebuilder-review/resources/core/__tests__/cross-repo-wiring.test.ts` (new) | FR-A4.4 | G-3 |

### Acceptance Criteria (A4)

- [ ] `auto_detect: true` surfaces refs from PR title/body into fetch step
- [ ] `manual_refs: [...]` passes through `parseManualRefs()` and joins auto-detected
- [ ] `fetchCrossRepoContext()` called with documented 5s/30s timeouts (already its defaults)
- [ ] Successful context appears in review user prompt under marked section
- [ ] Partial-failure mode: timeouts don't break the review
- [ ] Context truncation prevents blowing the input token budget
- [ ] Integration tests pass (3 scenarios)
- [ ] Existing cross-repo unit tests still pass
- [ ] `npm run build` succeeds; `dist/` committed

---

## Goals

- **G-1**: Ship the missing wiring — config flags `lore_active_weaving` and `cross_repo.auto_detect` stop being no-ops
- **G-2**: Minimal signature changes — additive parameters, backwards-compatible call sites
- **G-3**: Test coverage — every new code path has a test that would fail without it
- **G-4**: Graceful degradation — network failures and missing files do not break reviews

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Cross-repo fetch timeouts cascade | Per-ref 5s + total 30s already in `fetchCrossRepoContext`. Sprint 2 T3 explicitly handles partial failures. |
| Lore file grows unbounded; prompt tokens explode | A5 T1 loader does not apply size limit; A5 T2 wiring respects `buildEnrichedSystemPrompt` existing truncation. Future optimization if needed. |
| Injection via cross-repo content | Existing `INJECTION_HARDENING` in template.ts treats all external content as untrusted; cross-repo context goes through the same layer. |
| Review prompt token blow-out | A4 T2 truncates cross-repo context to 20KB (configurable). |
| Stale `dist/` after TS changes | Every sprint ends with `npm run build` + commit; `Fixture Sync Check` CI catches drift. |

## Dependencies

- PR #463 (multi-model pipeline) — merged in `bfe7ade`
- PR #465 (A1+A2+A3) — merged in `916836d`
- Issue #464 Part A items A1-A3 — **closed** by #465
- Issue #464 Part B (close-the-loop) — **closed** by #466 + #468

## Zone & Authorization

**System Zone writes required**: `.claude/skills/bridgebuilder-review/resources/core/*.ts`, `.claude/skills/bridgebuilder-review/resources/main.ts`, `.claude/skills/bridgebuilder-review/resources/core/__tests__/*.test.ts`, `.claude/skills/bridgebuilder-review/resources/dist/*` (build artifacts).

Cycle-level authorization: cycle-055 sprint plan authorizes System Zone writes for the Bridgebuilder skill's TypeScript source only. No changes to other `.claude/` subtrees (no shell scripts, no hooks, no data files).

## Execution Note

Using `/run sprint-plan` with default `consolidate_pr: true` so A4 + A5 ship as a single PR with per-sprint commit markers (`feat(sprint-1): ...` and `feat(sprint-2): ...`). This matches the pattern used by cycle-052 (#463) which shipped 4 sprints in one consolidated PR.

---

*2 sprints, 7 tasks total (3 + 4), closes Issue #464 Part A completely*
