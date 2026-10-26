# Sprint Plan: Bug Fix — Bridgebuilder exclusion globs do not match dot-led path segments (Node `path.matchesGlob`), so excluded fixture trees stay in the review set and the round degrades (bd-a8l0c)

**Type**: bugfix
**Bug ID**: 20261025-826c6b
**Source**: /bug (triage) — bead bd-a8l0c (Bridgebuilder round 1 on PR #1296, 2026-10-25); operator instruction 2026-10-26 ("do what can easily be done")
**Sprint**: sprint-bug-278

---

## sprint-bug-278: exclusion globs exclude the whole tree

### Sprint Goal
Fix the reported bug with a failing test proving the fix: `matchesExcludePattern` matches a path with a dot-led segment against a `**` or `*` exclusion glob on every Node version, so `--exclude 'evals/tests/fixtures/**'` removes the pinned-framework fixtures from the review set; exact and substring patterns and the existing `LOA_EXCLUDE_PATTERNS` behaviour are unchanged.

### Deliverables
- [ ] Failing test that reproduces the bug (`resources/__tests__/loa-detection.test.ts`: dot-segment cases under `**` and `*`, negatives, unchanged exact/substring)
- [ ] Source code fix (`resources/core/truncation.ts` `matchesExcludePattern`: native glob, then the regex fallback for `*`/`?` patterns; denylist semantics documented)
- [ ] `dist/` rebuilt and the System Zone manifests regenerated in the fix commit (lead, under the bounded marker)
- [ ] All existing tests pass (no regressions: `npm test` in `.claude/skills/bridgebuilder-review`, `npx tsc --noEmit`)
- [ ] Triage analysis document

### Technical Tasks

#### Task 1: Write Failing Test [G-5]
- Create unit tests reproducing the bug
- Verify tests fail with current code (Node ≥ 22)
- Test file: `.claude/skills/bridgebuilder-review/resources/__tests__/loa-detection.test.ts`

**Acceptance Criteria**:
- Tests fail with current code, proving the bug exists: `evals/tests/fixtures/**` does not match `…/pinned/.claude/settings.json` today
- Test names clearly describe the bug scenario (dot-led segment under `**`, dot-file under `*`, single `*` stays within a segment, exact/substring unchanged)
- Tests are isolated (pure function calls; no filesystem, no network)
- Committed alone (`test(20261025-826c6b): failing test`) before any fix commit; SHA recorded in `reviewer.md` as `Red commit: <sha>`

#### Task 2: Implement Fix [G-1, G-2]
- Fix root cause in `resources/core/truncation.ts` (`matchesExcludePattern`: when `path.matchesGlob` says no for a pattern containing `*`/`?`, also test `simplifiedGlobMatch`; comment: exclusion globs are a denylist and match dot-led segments)
- Verify failing tests now pass
- Run `npm test` and `npx tsc --noEmit -p resources/tsconfig.json`; the lead runs `npm run build` (dist + manifest) and the manifest regeneration under the marker

**Acceptance Criteria**:
- Failing tests now pass; `npm test` green; typecheck clean
- No regressions in existing tests (`LOA_EXCLUDE_PATTERNS`, truncation, progressive truncation)
- Fix addresses root cause (two matchers with different dot-segment semantics; the denylist one now always applies), not just symptoms (no special-casing of `.claude`)
- The fix is a later commit and does not weaken the test (`.claude/scripts/red-test-check.sh --red <Red commit> -- npm test --prefix .claude/skills/bridgebuilder-review` exits 0)
- `tools/check-bb-dist-fresh.sh --check`, `tools/gen-checksums.sh --check`, `tools/check-manifest-paths.sh`, `repo-map-gen.sh --validate` pass on the fix commit

#### Task 3: Documentation and record
- CHANGELOG `[Unreleased]` `### Fixed` entry (bd-a8l0c); `reviewer.md` with `## AC Verification` (file:line per row) and the E2E: the reproduction one-liner through the built `dist/` returns `true` for the pinned fixture path

### Acceptance Criteria
- [ ] Bug is no longer reproducible: the pinned fixture path matches `evals/tests/fixtures/**`
- [ ] Failing test proves the fix
- [ ] No regressions in existing tests
- [ ] Fix addresses root cause (not just symptoms)

### Triage Reference
See: grimoires/loa/a2a/bug-20261025-826c6b/triage.md
