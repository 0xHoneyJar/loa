# sprint-bug-278 (bug 20261025-826c6b, bd-a8l0c) — implementation report

**Implementer:** Opus 5.5 subagent (worktree `../loa-wt-bug-b`, brief `~/.cache/loa/bugs/briefs/b.md`) · **Lead:** Fable 5.1 (triage, landing, dist rebuild, manifests, this report) · **Branch:** `fix/post-ship-bugs-classifier-bb-glob` · Node v22.22.2

**Red commit:** `511a9e11d` — `test(20261025-826c6b): failing test — sprint-bug-278 (.claude/skills/bridgebuilder-review/resources/__tests__/loa-detection.test.ts)`
**Fix commit:** `01a5868eb` — `fix(bridgebuilder): exclusion globs match dot-led path segments — …` (System Zone files under the bounded marker; `dist/` rebuilt with `npm run build` — `dist/core/truncation.js{,.map}`, `dist/.build-manifest.json` — `checksums.json`, `REPO-MAP.md` regenerated in the same commit)

## What was built

`matchesExcludePattern` (`.claude/skills/bridgebuilder-review/resources/core/truncation.ts:162-190`) keeps Node's `path.matchesGlob` as the first matcher and, when it rejects a pattern containing `*` or `?`, retries with the new private helper `dotSegmentGlobMatch` (`:143-160`): the same regex translation as the `**` branch of `simplifiedGlobMatch` (`**` → `.*`, `*` → `[^/]*`, `?` → `[^/]`), so a dot-led segment matches and a single `*` stays within one segment. Exact/substring patterns and the Node < 22 branch are unchanged. Seven `node:test` cases (`resources/__tests__/loa-detection.test.ts:393-425`). CHANGELOG `[Unreleased]` `### Fixed` line (bd-a8l0c).

## Red run (at `511a9e11d`)

`npm test` (in `.claude/skills/bridgebuilder-review`; `node:test` via tsx): tests 1075, pass 1072, fail 3 — `not ok 1 ** exclusion glob matches files under a dot-led directory in the named tree` (expected true, actual false), `not ok 2 **/*.md matches a file under a dot-led directory`, `not ok 3 single * matches a dot-file at the start of a segment`. The two negatives and the two unchanged-behaviour cases pass before and after. Log: `~/.cache/loa/bugs/red-b.log`.

## Green run (at `01a5868eb`)

`npm test` 1075/1075 (lead's landing run; the implementer saw 1074/1075 in two of three runs because of a pre-existing wall-clock guardrail, see Open items); `npx tsc --noEmit -p resources/tsconfig.json` clean; `npm run build` ok, `tools/check-bb-dist-fresh.sh --check` fresh; `gen-checksums.sh --check` OK (2075 entries), `repo-map-gen.sh --validate` consistent, `check-manifest-paths.sh` 0/0. Log: `~/.cache/loa/bugs/green-b.log`.

**Red-then-green (manual equivalent):** `red-test-check.sh` links only top-level dependency directories into its worktrees and accepts only test runners as `--setup`, so it cannot provide the skill's nested `node_modules`. The lead reproduced its discipline by hand: detached worktrees at `511a9e11d` and `01a5868eb` (`git worktree add --detach`), the nested `node_modules` symlinked from the live tree, `npm test` in each — red: rc 1, pass 1072 / fail 3 (the three positive cases); green: rc 0, pass 1075 / fail 0. The fix commit touches no test file (`git diff --stat 511a9e11d 01a5868eb -- '*__tests__*'` empty).

## E2E

- Source: `npx tsx -e 'import {matchesExcludePattern} from "./core/truncation.ts"; console.log(matchesExcludePattern("evals/tests/fixtures/sandbox-mount/pinned/.claude/settings.json", ["evals/tests/fixtures/**"]))'` → `false` before, `true` after.
- Built dist: the lead's check through `dist/core/truncation.js` after `npm run build` — recorded in `engineer-feedback.md`.

## AC verification

| AC (sprint.md) | Status | Evidence |
|---|---|---|
| T1 tests fail with current code | met | red run; `loa-detection.test.ts:396` |
| T1 names describe the scenario | met | `it` titles at `:396, :401, :405, :409, :413, :417, :422` |
| T1 isolated (pure calls) | met | only `matchesExcludePattern` is called |
| T1 red committed alone, SHA recorded | met | `511a9e11d` (test file only) |
| T2 failing tests pass; `npm test` green; typecheck clean | met | green run |
| T2 no regressions | met | 1075/1075 incl. `LOA_EXCLUDE_PATTERNS`, truncation, progressive truncation |
| T2 root cause, no `.claude` special-casing | met | `truncation.ts:143-160` (helper), `:185-187` (retry for any rejected wildcard pattern); no path literals |
| T2 fix does not weaken the test; red-then-green | met (manual equivalent) | section above |
| T2 dist-fresh, checksums, manifest-paths, repo-map | met | `01a5868eb`; `check-bb-dist-fresh.sh --check` fresh |
| T3 CHANGELOG entry (bd-a8l0c) | met | `CHANGELOG.md:13` (under the shared `### Fixed` heading) |
| T3 dist E2E | lead | `engineer-feedback.md` |
| Bug no longer reproducible | met | the one-liner prints `true` |

## DECISION bullets (judgment calls → decision rows)

- **Second matcher is a new private helper, not `simplifiedGlobMatch`.** The brief's literal retry fails the brief's own negative case: the fallback's single-`*` branch (`startsWith(before) && endsWith(after)`) crosses `/`, so `evals/tests/fixtures/*.md` would match `evals/tests/fixtures/a/b.md` and `*.lock` would match `a/b.lock`. Rejected alternatives: reuse as briefed (wrong); fix `simplifiedGlobMatch` itself (forbidden by the brief and changes Node < 22 behaviour). Cost: ~10 duplicated lines of regex translation.
- **`*` and `?` match a leading dot** (`fixtures/*.json` ⇢ `fixtures/.hidden.json`). Rejected: shell semantics (`dot: false`). Exclusion is a denylist; hiding dot-files from an exclusion only leaks files into the review set.
- **Retry only when the native matcher says no and the pattern has a wildcard**; native stays first (brace expansion, character classes); exact/substring branch untouched.
- **CHANGELOG**: line placed under the plain `### Fixed` heading sprint-bug-277 created (one heading for both micro-sprints).
- **Exact-pattern pin**: `.loa-version.json` matching `x/.loa-version.json.bak` (today's substring behaviour) is pinned as unchanged, per the brief.

## Open items

- Residual matcher differences (described, not fixed): brace and class patterns (`{a,b}/**`, `[ab]/**`) still miss dot-led segments because the regex escapes `{}`/`[]` as literals; `{a,b}/**` now also matches a literal `{a,b}/` prefix (harmless); trailing-slash patterns match in neither matcher; the regex treats `a/../b.md` as under `a/**` (GitHub API filenames are normalized). ReDoS exposure of operator patterns is the same as the existing fallback's.
- Pre-existing flaky test: `progressive-truncation.test.ts:564` (`detectLoa + applyLoaTierExclusion with 100 files completes in <100ms`, wall-clock) fails under full-suite load on unpatched code too (2 of 4 baseline runs; 146 ms observed); passes in isolation 5/5 with and without the fix. Candidate bead: loosen the threshold or measure CPU time.
- Out of scope (unchanged): large added docs returning `no_patch` from the GitHub API count as reviewable and degrade coverage (`paged-fetch.ts:39-150`) — stays as a note on bd-a8l0c.
- `red-test-check.sh` cannot link nested dependency directories (only `node_modules .venv vendor target .tox` at the worktree root) and `--setup` accepts runners only — the manual equivalent above; candidate improvement: a `--link-dep <path>` option.

## Suites

`npm test` 1075/1075 · `npx tsc --noEmit` · `npm run build` + `check-bb-dist-fresh.sh --check` · `gen-checksums.sh --check` · `repo-map-gen.sh --validate` · `check-manifest-paths.sh`.


## Rounds after the first landing

- Review round 1 `63a3a9d1f`: segment-aware globstar (zero or more segments), in-segment `**` → `*`, memoized RegExp, native-only test guarded; the dissent's BLOCKING fixed. Audit round `69bdf7680`: substring over-match pin dropped (bd-ow72o), CHANGELOG behaviour-change sentence (bd-i4fyw). Bridgebuilder round `84c328455`: brace/class limitation documented and pinned, `hasNativeGlob` exported. Final head `84c328455`. Recorded 2026-10-26T00:52:50Z.