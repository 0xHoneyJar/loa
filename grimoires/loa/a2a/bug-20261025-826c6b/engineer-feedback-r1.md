CHANGES_REQUIRED

# sprint-bug-278 (bug 20261025-826c6b, bd-a8l0c) — Senior Technical Lead Review, round 1

**Reviewer:** lead (Fable 5.1) · **Head reviewed:** `01a5868eb` (red `511a9e11d`) on `fix/post-ship-bugs-classifier-bb-glob` · **Dissent:** one review run (`adversarial-review.json` in this directory; codex-headless + claude-headless, 2/2, chain ok, consensus APPROVED, 1 BLOCKING + 5 ADVISORY payloads) · **Implementation report:** `reviewer.md` · **Code read:** `dotSegmentGlobMatch` and the retry site (`truncation.ts:143-190`), the seven tests, the rebuilt `dist/core/truncation.js`; manual red-then-green in detached worktrees (red 1072/3, green 1075/0; DEC-1007)

## Summary

The approach is right — native matcher first, a dot-agnostic segment-aware retry, exact/substring and the Node < 22 branch untouched — and the implementer's two deviations from the brief are correct (a private helper because the fallback's single-`*` branch crosses `/`, DEC-1005; `*`/`?` match a leading dot, DEC-1006). The helper's translation is not yet the semantics the comment promises. The dissent's BLOCKING payload is real: `**` → `.*` makes a leading `**/` demand a slash, so a globstar cannot match zero segments and the dot-files the bug is about stay unexcluded when they sit at the root or directly in the named directory (`**/*.md` vs `.hidden.md`; `fixtures/**/*.json` vs `fixtures/.hidden.json`; `**/fixtures/**` vs `fixtures/.claude/x`). Two advisories follow from the same translation: `**` inside a segment (`**.md`) becomes a cross-directory match (minimatch treats it as `*`), a behaviour change outside the bug that silently removes files from a denylist's complement; and a regex is compiled per (file, pattern) pair with adjacent `.*` groups for repeated globstars. One advisory is about the test: "single `*` stays within one segment" is only true on the native-glob branch.

## Findings

- **HIGH** (confidence: high) `.claude/skills/bridgebuilder-review/resources/core/truncation.ts:150-159` — the globstar requires at least one segment. Failure: when `.reviewignore` or `--exclude` names `**/*.md` and the PR adds `.hidden.md` at the root, then neither matcher excludes it and the file stays in the review set — the bug's own symptom class. Fix: segment-aware translation where a whole-segment `**` matches zero or more segments (`(?:[^/]*/)*` when followed, `(?:/.*)?` when trailing, `.*` alone), with tests for the three shapes above (red first).
- **MEDIUM** (confidence: high) `truncation.ts:150-159` — `**` not forming a whole segment is treated as a globstar. Failure: when a pattern says `src/**.ts`, then `src/a/b.ts` is excluded although minimatch (and the operator) mean `src/*.ts`. Fix: collapse an in-segment `**` to `*`; negative test `**.md` vs `a/b.md`.
- **LOW** (confidence: medium) `truncation.ts:159`, `:185` — a `RegExp` is compiled on every call and consecutive globstars produce adjacent `.*` groups; patterns come from the operator's config and the reviewer's checkout (`.reviewignore` is read from `repoRoot`, not from the PR head — checked), so the exposure is the operator's own patterns. Fix: memoize per pattern, collapse consecutive globstar segments.
- **LOW** (confidence: high) `resources/__tests__/loa-detection.test.ts:413-415` — the "single `*` stays within one segment" assertion encodes a property the Node < 22 branch does not have. Fix: guard it with `typeof path.matchesGlob === "function"` and say so.

## Observations

- The dissent's last advisory ("no `dist/` in the diff") is an artefact of the dissent input (the lead's diff excluded the generated files): `01a5868eb` carries `dist/core/truncation.js{,.map}` and `dist/.build-manifest.json`; `tools/check-bb-dist-fresh.sh --check` is fresh.
- The pre-existing flaky wall-clock guardrail (`progressive-truncation.test.ts:564`) is not this sprint's; candidate bead.

## Dissent dispositions (1 blocking, 5 advisories)

- BLOCKING zero-segment globstar → HIGH (fix required).
- Leading/trailing `**/` translation → folded into the HIGH.
- In-segment `**` → MEDIUM.
- Native-only test property → LOW (guard).
- Per-call RegExp / backtracking → LOW (memoize + collapse); the PR-head claim is **not** the case here (`.reviewignore` is read from the reviewer's `repoRoot`).
- dist missing from the diff → observation (present in the commit).

## Rejected dissent payloads

None (the `.reviewignore`-from-PR-head premise of the performance advisory is corrected in its disposition, the advisory itself is kept).

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":1,"low":2},"excluded":0,"sprint_id":"sprint-bug-278","ts":"2026-10-26T00:40:00Z"} -->
