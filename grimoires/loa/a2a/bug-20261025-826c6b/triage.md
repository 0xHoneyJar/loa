# Bug Triage: Bridgebuilder `--exclude` / `.reviewignore` globs do not match path segments that start with a dot (Node `path.matchesGlob`), so an excluded fixture tree stays in the review set and the round degrades on `file_cap` (bd-a8l0c)

## Metadata
- **schema_version**: 1
- **bug_id**: 20261025-826c6b
- **classification**: logic_bug (the native glob matcher applies shell dot-file semantics to an exclusion denylist; the fallback matcher the code carries for Node < 22 would have matched)
- **severity**: medium
- **eligibility_score**: 3
- **eligibility_reasoning**: Reproducible steps with exact output (+2): on Node v22.22.2, `path.matchesGlob("evals/tests/fixtures/sandbox-mount/pinned/.claude/settings.json", "evals/tests/fixtures/**")` is `false` while the same pattern matches `evals/tests/fixtures/a/b.md`; `matchesExcludePattern` returns the native result for every pattern containing `*`. Production log (+1): Bridgebuilder round 1 on PR #1296 (2026-10-25, `~/.cache/loa/cycle-134/bb/round1.log`) with `--exclude 'evals/tests/fixtures/**'` recorded `evals/tests/fixtures/sandbox-mount/pinned/.claude/settings.json`, `…/pinned/.claude/rows/r02.md` and 29 more `pinned/.claude/…` files as reviewable, pushed 8 files past the 50-file cap, and returned `degraded_reason: incomplete_coverage` (15 findings withheld). No disqualifier.
- **test_type**: unit
- **risk_level**: low
- **created**: 2026-10-25T23:52:00Z

## Reproduction
### Steps
1. `node -e 'const p=require("path"); console.log(p.matchesGlob("evals/tests/fixtures/sandbox-mount/pinned/.claude/settings.json","evals/tests/fixtures/**"), p.matchesGlob("evals/tests/fixtures/a/b.md","evals/tests/fixtures/**"))'` → `false true` (Node v22.22.2).
2. In `.claude/skills/bridgebuilder-review/resources`: `npx tsx -e 'import {matchesExcludePattern} from "./core/truncation.ts"; console.log(matchesExcludePattern("evals/tests/fixtures/sandbox-mount/pinned/.claude/settings.json", ["evals/tests/fixtures/**"]))'` → `false`.
3. Live: `BRIDGEBUILDER_MODEL=codex-headless node .claude/skills/bridgebuilder-review/dist/main.js --repo 0xHoneyJar/loa --pr 1296 --exclude 'evals/tests/fixtures/**' …` (round 1, head 9b9eebab): the coverage record lists the `pinned/.claude/…` fixtures with no exclusion reason, `file_cap` omissions follow, `degradedReason: incomplete_coverage`.

### Expected Behavior
- Steps 1–2: an exclusion glob names a tree; every file under it is excluded, including files whose path has a segment starting with `.` (`.claude`, `.github`, `.run`, dot-files). `evals/tests/fixtures/**` matches `evals/tests/fixtures/sandbox-mount/pinned/.claude/settings.json`.
- Step 3: the 31 pinned-framework fixture files are `excluded_pattern`, the review set stays under the cap, the round is not degraded by them.
- Exact and substring patterns (no `*`/`?`) behave as today; patterns that do not name the tree (`evals/tests/other/**`) still do not match.

### Actual Behavior
- `matchesExcludePattern` (`.claude/skills/bridgebuilder-review/resources/core/truncation.ts:143-160`) uses `path.matchesGlob` whenever Node provides it (`hasNativeGlob`, `:94-96`) and only falls back to exact/substring for patterns without `*`/`?`. Node's matcher follows shell semantics: `*` and `**` do not match a segment that starts with a dot, so `evals/tests/fixtures/**` leaves every `pinned/.claude/…` file in the review set. The Node < 22 fallback `simplifiedGlobMatch` (`:101-141`) converts `**` to `.*` and would have matched — the behaviour differs by Node version.
- Live effect (round 1 on PR #1296): 31 fixture files reviewable, 8 files past the 50-file cap, `incomplete_coverage`, 15 findings withheld; the operator had to re-run with prefix patterns (`evals/tests/fixtures/`), which take the substring path.

### Environment
main `3e903cb83`; Node v22.22.2 (`path.matchesGlob` present); `.claude/skills/bridgebuilder-review/resources/core/truncation.ts` (`matchesExcludePattern`, the sole exclusion enforcement point, IMP-005), `dist/` built by `npm run build` (tsc + `tools/check-bb-dist-fresh.sh --write-manifest`); tests `npm test` (`node:test` via `tsx`, `resources/__tests__/*.test.ts`, `loa-detection.test.ts:368-394` covers `LOA_EXCLUDE_PATTERNS`).

## Analysis
### Suspected Files
| File | Line(s) | Confidence | Reason |
|------|---------|------------|--------|
| `.claude/skills/bridgebuilder-review/resources/core/truncation.ts` | 143-160 | high | `matchesExcludePattern`: returns the native glob result for any pattern with `*`/`?`; no dot-segment handling |
| `.claude/skills/bridgebuilder-review/resources/core/truncation.ts` | 94-141 | medium | `hasNativeGlob` and `simplifiedGlobMatch`: the fallback's `**` → `.*`, `*` → `[^/]*` regex matches dot segments; the two matchers disagree |
| `.claude/skills/bridgebuilder-review/resources/__tests__/loa-detection.test.ts` | 368-394 | high | `LOA_EXCLUDE_PATTERNS` cases through `matchesExcludePattern`; no dot-segment case — the new cases land here |
| `.claude/skills/bridgebuilder-review/resources/config.ts` | 1077-1100 | low | cycle-133 fixture exclude patterns (prepended to user patterns); consumers of the matcher, unchanged |
| `.claude/skills/bridgebuilder-review/resources/core/paged-fetch.ts` | 39-150 | low | coverage / `no_patch` accounting — the large-added-docs `no_patch` degradation is a separate design question, out of scope |
| `.claude/skills/bridgebuilder-review/dist/**` | — | medium | generated; the lead rebuilds (`npm run build`) in the fix commit so `bridgebuilder-dist-smoke` and the dist manifest stay fresh |

### Related Tests
| Test File | Coverage |
|-----------|----------|
| `resources/__tests__/loa-detection.test.ts` | `LOA_EXCLUDE_PATTERNS` match `.claude/`, `grimoires/`, `.beads/`, `.loa-version.json`; system-zone prefixes in sync |
| `resources/__tests__/truncation.test.ts`, `progressive-truncation.test.ts` | selection, caps, `.reviewignore` merge, self-review opt-in (through `truncateFiles`) |
| (none) | a `**` or `*` exclusion glob against a path with a dot-led segment |

### Test Target
Add cases (failing first on Node ≥ 22) to `resources/__tests__/loa-detection.test.ts` (a new `describe("matchesExcludePattern dot segments")`) or a new `resources/__tests__/exclude-glob.test.ts`:
- `evals/tests/fixtures/**` matches `evals/tests/fixtures/sandbox-mount/pinned/.claude/settings.json` and `…/pinned/.claude/rows/r02.md` (fails today: `false`);
- `**/*.md` matches `a/.hidden/b.md`; `fixtures/*.json` matches `fixtures/.hidden.json`;
- negative: `evals/tests/fixtures/**` does not match `evals/tests/other/x.md`; `evals/tests/fixtures/*.md` does not match `evals/tests/fixtures/a/b.md` (single `*` stays within one segment);
- unchanged: exact (`.loa-version.json`) and substring (`grimoires/`) patterns, and the existing `LOA_EXCLUDE_PATTERNS` cases.

### Constraints
- Exclusion globs are a denylist: a pattern that names a tree excludes everything under it regardless of dot-led segments (operator intent; the native matcher's shell dot-file rule is wrong here). Document that in the function comment.
- Keep `path.matchesGlob` as the first matcher (brace expansion, character classes) and make the regex fallback run as well when it says no for a pattern containing `*`/`?`; the fallback's segment rule (`*` → `[^/]*`, `**` → `.*`) is the dot-segment-agnostic semantics wanted. No new dependency; no behaviour change for exact/substring patterns; the Node < 22 branch unchanged.
- System Zone (`.claude/skills/bridgebuilder-review/**`): edit under the bounded marker (DEC-0824); the lead rebuilds `dist/` (`npm run build`: registry, tsc, dist manifest) and regenerates `checksums.json` / `REPO-MAP.md` in the fix commit; `tools/check-bb-dist-fresh.sh --check` passes.
- `npm test` (node:test via tsx) green; `npx tsc --noEmit -p resources/tsconfig.json` clean; the red commit lands alone first (`test(20261025-826c6b): failing test`); `red-test-check.sh` exits 0 on the fix commit.
- Out of scope: large added docs returning `no_patch` and counting as reviewable (a coverage-policy question; stays on bd-a8l0c as a note).

## Fix Strategy
In `matchesExcludePattern`, treat the native glob as one of two matchers: when `path.matchesGlob` returns false for a pattern that contains `*` or `?`, also test `simplifiedGlobMatch`, whose regex translation matches dot-led segments, so an exclusion glob that names a tree excludes every file under it on every Node version; document the denylist semantics in the function comment; add the dot-segment cases both ways; rebuild `dist/` and the System Zone manifests in the same commit.

### Fix Hints
Structured hints for multi-model handoff (each hint targets one file change):

| File | Action | Target | Constraint |
|------|--------|--------|------------|
| `.claude/skills/bridgebuilder-review/resources/core/truncation.ts` | fix | `matchesExcludePattern`: native glob, then `simplifiedGlobMatch` for `*`/`?` patterns; comment on denylist semantics | no change to `simplifiedGlobMatch`; exact/substring unchanged |
| `.claude/skills/bridgebuilder-review/resources/__tests__/loa-detection.test.ts` | add | dot-segment cases (positive ×4, negative ×2, unchanged ×2) | red first on Node ≥ 22 |
| `CHANGELOG.md` | add | `[Unreleased]` `### Fixed` entry (bd-a8l0c) | one line |
| `.claude/skills/bridgebuilder-review/dist/**` | fix | rebuilt by the lead (`npm run build`) | same commit as the fix |
