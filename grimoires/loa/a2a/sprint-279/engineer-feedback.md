All good

# sprint-279 (cycle-135 Sprint 1) — Senior Technical Lead Review, round 2 (final)

**Reviewer:** lead (Fable 5.1) · **Head reviewed:** `b02459e5a` on `feature/cycle-135-review-coverage` · **Round 1:** `engineer-feedback-r1.md` (CHANGES_REQUIRED at `998c3bd58`: 3 HIGH, 4 MEDIUM, 7 LOW) · **Round-1 commits:** A `058524011` → `8d22e449a`, B `fa45947b2` → `04b552529`, C `74ff045cf`, lead `b02459e5a` · **Report:** `reviewer.md` § Round 1

## Summary

Every round-1 finding is fixed behind a test that was red first, or closed by evidence with a pin that keeps it closed. The three HIGHs are gone: a failed base `.reviewignore` read now keeps the operator's deny list (the checkout copy governs, the record says `base_unavailable`, the review degrades and blocks the merge); only a root-anchored name or the full path can remove a protected file from the review; and on a pull request the four review-scope keys come from the trusted config, with `main.ts` calling the new `applyTrustedReviewScope` right after the trusted load. The content-fetch budget is now honest (bytes selected ahead are charged before any read; a file that cannot fit is `budget` without a call; a refusal that would repeat stops the loop). The code was read in full against the round-1 text, not taken from the reports; the red/green of both patch pairs was reproduced on the landed shas. Approved for audit.

## Round 1 dispositions

| # | Sev | Finding (round 1) | Disposition | Evidence |
|---|---|---|---|---|
| 1 | HIGH | `readBaseReviewignore` turned every failure into `none` (deny list dropped) | Fixed: fail closed — checkout copy governs, `base_unavailable`, review degrades `reviewignore_unavailable`; `none` only when base and checkout both lack the file; checkout symlink / invalid repoRoot still throw | `truncation.ts` `parseReviewignoreFile` + `readBaseReviewignore` (`BaseRead`), `paged-fetch.ts` pushes the fetch-side reason; tests 5/7/8 of A's red set; DEC-1043 |
| 2 | HIGH | "explicit" = any non-wildcard, so `ci.yml` / `.github` defeated protection silently | Fixed: `isExplicitFor` = non-wildcard and (root-anchored after one trailing `/` is ignored, or equal to the full path), the same anchoring test as `segmentMatch`; kept files recorded with the pattern | `truncation.ts` `partitionUserExclusions` / `isExplicitFor`; `loa-detection.test.ts` + `truncation.test.ts` red set; DEC-1044 |
| 3 | HIGH | the four scope keys came from the checkout YAML only (a PR could set `protected_paths: []`) | Fixed: `TRUSTED_VIEW_YQ` carries `scope` (plain paths, no `//`), `loadTrustedConfig` returns `reviewScope` on a PR with a source, `applyTrustedReviewScope` replaces the head's effective values with one WARN per differing key (no refusal), `--exclude` stays additive; wired in `main.ts` | `config.ts` `applyTrustedReviewScope`, `main.ts` after `config.trusted = trusted;` (lead, `b02459e5a`); 5 tests in `truncation.test.ts` incl. "matching head and trusted values warn nothing"; DEC-1045 |
| 4 | MEDIUM | slashless wildcards were root-anchored while slashless names floated | Fixed: `compileGlob` prefixes an implicit `**/` to a slashless wildcard; recorded as written; a test pins that no default or protected pattern is a slashless wildcard | `truncation.ts` `compileGlob`; DEC-1046 |
| 5 | MEDIUM | a finding on a contents-sourced file might be anchored to a line GitHub cannot resolve | No change needed, closed by evidence: `postReview` sends `body`, `event`, `commit_id` only; `PostReviewInput` has no comments field; the gh allowlist refuses JSON-typed fields; the multi-model path posts issue comments; pinned | `github-cli-contents.test.ts` (reviews POST carries only those fields); DEC-1049 |
| 6 | MEDIUM | RATE_LIMITED / FORBIDDEN swallowed per file (N identical failures) | Fixed: `stopsContentFetches` (codes RATE_LIMITED / FORBIDDEN, or `httpStatus` 401 / 403) → `error` for the file, `aborted` for the rest, one call; 404 / malformed envelope stay per-file | `paged-fetch.ts`; B's red test 11; DEC-1048 |
| 7 | MEDIUM | a read that could not fit because GitHub patches ahead consumed the budget was read and dropped as `too_large` | Fixed: candidates enter a 0-byte placement selection; reads walk `placement.included` charging the GitHub and synthesized bytes ahead; `remaining < 16 + 2·additions − 1` → `budget` without a call; a synthesized patch that does not fit → `budget` (never truncated); `too_large` stays for encoding / size / buffer | `paged-fetch.ts` `fetchMissingPatches` + `attempt`; B's red tests 8/9; DEC-1047 |
| 8 | LOW | `maxBuffer = ceil(4/3·maxBytes) + 4096` ignored the JSON-escaped newlines and link metadata | Fixed: `ceil(4/3·maxBytes·62/60) + 8192`; the authoritative bound stays `size` | `github-cli.ts` `getFileContent` |
| 9 | LOW | the contents stub recorded `options.timeout` but nothing asserted it | Fixed: asserted (30 s gh timeout bounds a stalled read) | `github-cli-contents.test.ts:62` |
| 10 | LOW | the excluding pattern travelled only as a stats suffix | Fixed: structured `pattern` on every `excluded[]` entry (Loa tiers, `.reviewignore`, strict deny, `exclude_patterns`); `paged-fetch.ts` reads `ex.pattern` first; the suffix stays one release | `truncation.ts` (`pattern:` at every push), `types.ts` `excluded[].pattern?` (contract 2); bd-gyrgq for the suffix removal |
| 11 | LOW | PMWG-T8 ran actionlint with default options (shellcheck / pyflakes over every `run:` block) | Fixed: `-shellcheck= -pyflakes=` (workflow and expression syntax only); the lead's docker run returned 0 | `post-merge-workflow-guards.bats` (`74ff045cf`) |
| 12 | LOW | a downstream mount keeping the old negative-list guard calls the orchestrator with `--type housekeeping` | Refused loudly with the HINT line (pinned, prefix match, PMOT-T1/T2); CHANGELOG note stands; scaffold detection filed | `post-merge-orchestrator-type.bats`; DEC-1051; bd-akkgq |
| 13 | LOW | `max_content_fetches:` with an empty value became `0` (every fetch disabled) | Fixed: empty = unset with a WARN (the default, 20) | `config.ts` `loadYamlConfig` |
| 14 | LOW | the selection ran twice when a patch was synthesized | Accepted and made deliberate: with a candidate present the selection runs exactly twice (placement, then real sizes); never a third time | `paged-fetch.ts` `attempt`; DEC-1047 |

## Lead verification

- Source read of both fix diffs (`git diff 058524011 8d22e449a`, `git diff fa45947b2 04b552529`, source files only) and of the `main.ts` wiring against `applyTrustedReviewScope`'s signature (`Pick<CLIArgs, "exclude">`).
- Composition parity: `applyTrustedReviewScope` builds `excludePatterns` as `DEFAULT_EXCLUDE_PATTERNS` + trusted + CLI, the same order `resolveConfig` uses (`config.ts` ~1648), so equal values warn nothing (test "matching head and trusted values warn nothing").
- Object identity through the placement selection: `truncateFiles` pushes file objects by reference on every path a patch-less candidate can take; the one spread copy (`included.push({ ...file, patch: rebuilt … })`) is the hunk-reduction path, which needs a patch — a candidate never reaches it, so `candidates.has(f)` is sound.
- `yq` `//` pitfall avoided: the `scope` view uses plain paths so `fetch_missing_patches: false` survives.
- Red/green reproduced on the landed shas (`red-green-npm.sh`): A 3 red cases shown → 1236 green; B 3 red cases shown → 1243 green. `npm test` 1243/1243 three times under load (16 s / 15 s / 16 s). Build, dist manifest, checksums (2078), REPO-MAP and manifest paths all consistent at `b02459e5a`.
- CHANGELOG: the round-1 texts for bd-ow72o, bd-i4fyw and bd-w5pd9 replace the round-0 bullets (semantics now stated: floating slashless wildcards, explicit = root-anchored, trusted scope keys, `base_unavailable`, `budget` / `aborted`).

## Observations

- **LOW** (confidence: low) `.claude/skills/bridgebuilder-review/resources/core/paged-fetch.ts:276` — the candidate set is keyed by object identity, so it relies on the selection returning patch-less entries by reference; today only the hunk-reduction path copies an entry and that path needs a patch. Failure: when a future selection path copies a patch-less entry then every candidate is treated as a non-candidate and no content is read.
- **LOW** (confidence: low) `.claude/skills/bridgebuilder-review/resources/config.ts:800` — on a pull request with no trusted source the early return leaves the PR head's four scope keys in force; this is today's behaviour, WARNed by the existing trusted-config-unavailable line, pinned by a test and filed as bd-ous65. Failure: when a CI checkout is shallow and no trusted config variable is set then a PR head can still widen its own review scope.

## Acceptance

FR-1 … FR-5 and Tasks 1.0 … 1.7 as in round 0 (`reviewer.md` § AC verification), plus the round-1 criteria in A § 3, B § 3 and C § 3 of the round-1 reports: every row met with `file:line` evidence; `sprint.md` Tasks 1.0 … 1.7 may be ticked. Tasks 1.8 (this gate and the audit), 1.9 (ship) and 1.E2E remain with the lead.

## Rejected dissent payloads

None. No new dissent run this round: the three permitted runs were spent at round 0 on the three implementer diffs (A, B, C), and their payloads produced the three HIGHs fixed here.

## Post-approval addendum (lead, `b6d0a07b4`)

After this approval the CI mirror reported the Bridgebuilder `SKILL.md` over its 16,384 B prompt budget (PB-9); the fix is documentation-only — the long-form rules moved to `resources/exclusions-and-coverage.md` behind guarded pointers (`reviewer.md` § Post-gate addendum, DEC-1053). `git diff --stat b02459e5a b6d0a07b4` touches `SKILL.md`, the new reference file, the dist manifest, `checksums.json` and REPO-MAP only; no source, test or behaviour changed, so this approval stands for `b6d0a07b4`.

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":2},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-279","ts":"2026-10-26T07:06:19Z"} -->
