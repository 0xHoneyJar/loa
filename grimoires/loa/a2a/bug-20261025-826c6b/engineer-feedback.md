All good

# sprint-bug-278 (bug 20261025-826c6b, bd-a8l0c) — Senior Technical Lead Review, round 2 (final)

**Reviewer:** lead (Fable 5.1) · **Head reviewed:** `63a3a9d1f` (red `511a9e11d`, fix `01a5868eb`, round-1 `63a3a9d1f`) on `fix/post-ship-bugs-classifier-bb-glob` · **Round 1:** `engineer-feedback-r1.md` (CHANGES_REQUIRED, 1 HIGH, 1 MEDIUM, 2 LOW) · **Dissent:** one review run (`adversarial-review.json`, codex-headless + claude-headless 2/2, chain ok, consensus APPROVED, 1 BLOCKING + 5 ADVISORY) — all payloads dispositioned below; not re-run for round 1 (the round-1 change implements the dissent's own fix, read in full by the lead) · **Implementation report:** `reviewer.md`

## Summary

Round 1 closes every finding. `dotSegmentGlobMatch` (`truncation.ts:143-178`) is now segment-aware: the pattern is split on `/`, consecutive globstar segments collapse, a whole-segment `**` becomes `(?:[^/]*/)*` when followed, `(?:/.*)?` when trailing and `.*` alone (zero or more segments), an in-segment `**` collapses to `*`, `*` → `[^/]*`, `?` → `[^/]`, and the compiled RegExp is memoized per pattern in a module-level map. The retry site is unchanged (native matcher first; retry only for wildcard patterns it rejects); `simplifiedGlobMatch` and the Node < 22 branch are untouched. Five new tests pin the globstar semantics; the "single `*` stays within one segment" case is skipped where the native glob is absent, with the reason in its name.

## Verified

- Round-1 red-then-green (lead's landing, round-1 tests against the round-0 fix): `npm test` rc 1, 1080 tests / 5 fail — the four new positive cases (`**/*.md` vs `.hidden.md`, `fixtures/**/*.json` vs `fixtures/.hidden.json`, `**/fixtures/**` vs `fixtures/.claude/settings.json`, `**.md` vs `a/b.md`) plus the pre-existing flaky wall-clock guardrail; then with the round-1 fix 1080/1080 on the second run (the first run showed only the same flake, 1079/1); `tsc --noEmit` clean. The implementer's own red run showed the four cases alone (1076/4). Round 0: manual red-then-green in detached worktrees (red 1072/3, green 1075/0; DEC-1007); the fix commits touch no test file.
- dist E2E through the built `dist/core/truncation.js` at `63a3a9d1f`: pinned fixture path vs `evals/tests/fixtures/**` → true; `.hidden.md` vs `**/*.md` → true; `fixtures/.hidden.json` vs `fixtures/**/*.json` → true; `a/b.md` vs `**.md` → false; sibling tree → false. `check-bb-dist-fresh.sh --check` fresh; manifests regenerated under the bounded marker in both commits.
- Backtracking: the implementer's probe `**/**/a/**/a/**/a/**/zz` against an 80-segment path ≈ 5 ms; each globstar group consumes a whole `/`-terminated segment per iteration, no adjacent ambiguous quantifiers.
- `.reviewignore` is read from the reviewer's `repoRoot` (`truncation.ts:304`), not from the PR head: the patterns are the operator's own.

## Observations (non-blocking)

- **LOW** (confidence: low) `.claude/skills/bridgebuilder-review/resources/core/truncation.ts:160` — a trailing globstar matches the bare tree root (`evals/tests/fixtures/**` vs a file named exactly `evals/tests/fixtures`); native says false. Failure: when a PR adds a file whose path equals an excluded tree's root, then it is excluded although the native matcher would keep it; PR file lists hold files, so only that one shape differs. Left as specified.
- **LOW** (confidence: high) `.claude/skills/bridgebuilder-review/resources/core/truncation.ts:171` — brace and character-class patterns (`{a,b}/**`, `[ab]/**`) still miss dot-led segments: the regex escapes `{}`/`[]` as literals, so only the native matcher sees them. Failure: when an operator writes `**/*.{json,md}` and a PR adds a file under a dot-led directory, then neither matcher excludes it. Out of the observed failure; documented in `reviewer.md`.
- **LOW** (confidence: low) `.claude/skills/bridgebuilder-review/resources/core/truncation.ts:149` — the memo map is unbounded. Failure: when a process compiles very many distinct patterns, then the map grows with them; patterns come from config, `.reviewignore` and the CLI, a small set fixed per process.
- Pre-existing flaky wall-clock guardrail `progressive-truncation.test.ts:564` (<100 ms under full-suite load) — not this sprint's; candidate bead.
- Out of scope, noted on bd-a8l0c: large added docs returning `no_patch` count as reviewable and degrade coverage.

## Dissent dispositions (1 blocking, 5 advisories)

- BLOCKING zero-segment globstar → **fixed** in `63a3a9d1f` (tests 8–10 of the new block).
- Leading/trailing `**/` translation → **fixed** (same change).
- In-segment `**` as globstar → **fixed** (`**.md` → `*.md`; test 11).
- Native-only test property → **fixed** (`{ skip: !hasNativeGlob }`).
- Per-call RegExp / backtracking → **fixed** (memoized; consecutive globstars collapse); the "PR author controls `.reviewignore`" premise is corrected (read from `repoRoot`).
- dist missing from the diff → artefact of the dissent input; present in `01a5868eb` and `63a3a9d1f`.

## Rejected dissent payloads

None.

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":3},"excluded":0,"sprint_id":"sprint-bug-278","ts":"2026-10-26T00:55:00Z"} -->
