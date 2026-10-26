# sprint-279 (cycle-135 Sprint 1) — implementation report

**Lead:** Fable 5.1 (contract commit, landing, wiring, this report) · **Implementers:** three Opus 5.5 subagents in `../loa-wt-c135-{a,b,c}` (briefs `~/.cache/loa/cycle-135/briefs/`; their reports `~/.cache/loa/cycle-135/reports/{a,b,c}.md` are reproduced in substance below) · **Branch:** `feature/cycle-135-review-coverage` from `main 4256a1b3` · **Contract commit:** `a2960b963` (types.ts fields, § 3 of sdd.md; Q-1 probe in `contract.md`)

## Commits (red → fix per task; every fix under the bounded System Zone marker with dist, `checksums.json` and REPO-MAP regenerated)

| Task | Red commit | Fix commit | Red-then-green |
|---|---|---|---|
| 1.1 (A) exclusion matcher semantics | `c9a1ac9d3` (34 red) | `4f926bcfd` | `red-green-npm.sh` (detached worktrees, nested node_modules): red 34 fail → green 1128/1128 |
| 1.2 (A) protected paths, `.reviewignore` provenance, config | `808379e76` (25 red) | `e6ba40f96` | red 25 fail → green 1160/1160 |
| 1.3 (B) content fetch | `59d53530d` (26 red) | `46237970c` | red 26 fail → green 1189/1189 |
| 1.4 (B) coverage record + rendering | `c27a4394f` (9 red) | `625c5a901` | red 9 fail → green 1198/1198 |
| 1.5 (B) CPU-time guardrails | (report-only negative control: O(n²) stand-in min CPU 398.7 / 598.4 ms vs 100 ms — DEC-1031) | `189741489` | three green full runs under two concurrent `npm test` loops (load 14 → 35 on 8 cores) |
| 1.6 (C) housekeeping classifier value | `e8a773dfc` (12 red) | `ba454a74f` | `red-test-check.sh --red e8a773dfc --green ba454a74f -- bats …` → **VERIFIED** (a first run tripped the shared-.git guard because another session on this host moved `refs/heads/instrument-repair-2026-10-26-public-clean`; the retry verified) |
| 1.7 (lead) wiring | — | `9300f9b3d` | the record takes `reviewignoreSource` from the selection result; 1199/1199 |

Also: `CHANGELOG.md` cycle-135 sections (`### Changed` / `### Fixed`), PRD 1.3 (FR-3 allowlist criterion aligned with DEC-1028), beads 1.0 … 1.6 closed with the commits.

## What was built

- **C-1 (A):** `isWildcardPattern` (`[*?{[]`), `segmentMatch` (gitignore-like: no `/` → whole segment at any depth; `/` → root-anchored path or subtree; one trailing `/` stripped), one wildcard matcher built from `translateGlobSegment` + `compileGlob` + a memoized `patternMatcher` (sprint-bug-278's segment/globstar translation kept; one-level `{a,b}`, `[..]` / `[!..]` added); `path.matchesGlob`, `hasNativeGlob` and `simplifiedGlobMatch` are gone; `normalizeExcludePatterns` at every loader (config, CLI, `.reviewignore`, the Loa defaults, protected paths): trim, strip one leading `./` or `/`, reject `!` lines and constructs outside the grammar with one JSON-quoted WARN (rejected patterns match nothing, also when they bypass the loaders); the `.reviewignore` `/` → `**` conversion removed. SKILL.md exclusion-patterns heading documents it.
- **C-2 (A, producer):** `DEFAULT_PROTECTED_PATHS` (eight entries, sdd.md C-2), `partitionUserExclusions` order-independent (any non-wildcard match excludes; a protected file with only wildcard matches is kept, first wildcard recorded) at the three user-pattern sites (self-review arm, default-mode strict-deny arm, the `excludePatterns` Step 1 loop), protected files placed first in the selection order, every Loa-tier and user-pattern omission's stats suffixed ` [pattern: <p>]`; `truncateFiles` reads `config.protectedPaths ?? DEFAULT_PROTECTED_PATHS` and `config.reviewignoreBaseSha`, returns `protectedKept` and `reviewignoreSource`; `parseReviewignoreFile(repoRoot, { baseSha })` reads `git ls-tree` + `git show <sha>:.reviewignore` (40-hex, 10 s, 1 MiB, symlink mode refused) or the checkout file; `config.ts` parses and validates `protected_paths`, `fetch_missing_patches`, `max_content_fetches`. SKILL.md protected-paths heading.
- **C-3 (B):** `FileContentResult` and the optional `getFileContent?` on the port; `GitHubCLIAdapter.getFileContent` over the JSON contents envelope (no headers; strict `type`/`encoding`/`size`/`content` validation; 60-column base64 wrapping stripped; size vs decoded length; NUL / fatal-UTF-8 binary test; `maxBuffer` overflow → `too_large`); `assertContentsArgs` (owner/repo `[A-Za-z0-9_.-]+` not option-like, path validated before encoding and re-validated after decoding, `%2F` refused, 2048-char bound, no headers); pass 1 fetches, after the first selection, for its patch-less added survivors in listing order under `max_content_fetches` (20) and a 120 s deadline with `remaining = min(maxDiffBytes, maxDiffBytes − synthesized)`, synthesizes `@@ -0,0 +1,N @@` + `+` lines (CRLF kept, no-newline marker, BOM verbatim), re-runs the selection, pre-retains for pass 2 pinned to `pin.head_sha` (discarded on restart); outcomes on `omitted[].fetch`; `fetch_missing_patches: false` or a provider without the method skips the step.
- **C-2 (B, consumer) + § 4:** `coverage.protected_kept`, `omitted[].pattern` (suffix parsed; config-pattern fallback), `omitted[].fetch`, `reviewignore_changed_in_pr` (listing contains `.reviewignore`), `reviewignore_source` from the selection result (lead wiring); the summary renders "Protected paths kept (n)" with final status, "Reviewed from file contents (n)", patterns and fetch outcomes on omissions, and the `.reviewignore: <source>` line, all through `safePath`. SKILL.md coverage heading.
- **C-5 (B):** both guardrails take the minimum of three `process.cpuUsage` samples around the synchronous call; thresholds unchanged.
- **C-4 (C):** rule 1a echoes `housekeeping`; grammar `pr_type=<cycle|bugfix|housekeeping|other>` in the classifier header, the wrapper's usage and `loa-capabilities.sh`'s description; `simple-release` guard `(pr_type == 'bugfix' || pr_type == 'other') && pr_number != ''` with a comment naming bd-nr5i6; tests PCT-T28 … T32/T38 → housekeeping, HK-T1/T2 (wrapper pass-through), PMWG-T1 … T8 (guard text, yq-read shell mirror over the 12-cell matrix, yq parse, actionlint when installed), new `post-merge-orchestrator-type.bats` PMOT-T1/T2 (hermetic refusal pin). Q-3 gate passed (inventory in C's report § 5; no consumer misroutes).

## Suites at `9300f9b3d`

`npm test` 1199/1199 (was 1081 at the contract commit); `tsc --noEmit` clean; `npm run build` + `check-bb-dist-fresh.sh --check` fresh; the four pipeline bats files 84 ok / 1 skip (actionlint not installed on this host); `bash -n`; `gen-checksums.sh --check` 2078 entries, `repo-map-gen.sh --validate`, `check-manifest-paths.sh` 0/0. The full local CI mirror runs before the PR (`~/.cache/loa/cycle-135/logs/s-tests-*.log`).

## E2E (G-3, G-4)

- Lead integration check through the built dist: files `.github/workflows/ci.yml`, `src/app.ts`, `docs/other.yml` with `excludePatterns: ['**/*.yml']` → included `.github/workflows/ci.yml`, `src/app.ts`; excluded `docs/other.yml` with stats `… (excluded by pattern) [pattern: **/*.yml]`; `protectedKept = [{ file: ".github/workflows/ci.yml", pattern: "**/*.yml" }]`.
- Live read-only probe through the built adapter (one call): `getFileContent('0xHoneyJar','loa','README.md', <main sha>, 512000)` → `{ kind: "text", bytes: 23632 }`; bounded to 1000 → `too_large`.

## AC verification

FR-1 … FR-5 and Tasks 1.0 … 1.7: every criterion met with `file:line` evidence in the three implementer reports (A § 3, B § 3, C § 3), reproduced here by reference; the lead-owned rows: manifests regenerated in every fix commit (`git show --stat` of each), CHANGELOG lines inserted (`CHANGELOG.md` `[Unreleased]` cycle-135 sections), the Q-1 probe (`contract.md`), the live G-4 probe and the integration check (above), the wiring (`9300f9b3d`). FR-6 is Task 1.9 (ship).

## Judgment calls → decision rows

Recorded as DEC rows (phase implementation, cycle `cycle-135-review-coverage-followups`, proposed): I-1.1a/b (matcher internals, normalisation and negation), I-1.2a (stats-suffix grammar), I-1.2b (kept-then-stripped composition), I-1.2c (base-sha plumbing and single read), I-1.2d (config validation posture), I-1.3a (fetch placement and budget), I-1.3b (no Accept header; string stdout; dedicated validator), I-1.3c (`maxBuffer` formula's ~3 % conservative band), I-1.6a (shell mirror; hermetic pin; docs left true), I-1.6b (SDD orchestrator-branch imprecision corrected). Ids in `~/.cache/loa/cycle-135/dec-map.tsv`.

## Open items (not fixed here)

- `maxBuffer` band (I-1.3c): near-limit files read as `too_large` — a follow-up may widen the formula.
- No info log on a failed content read (no logger in `paged-fetch.ts` scope); the outcome is in the record.
- Downstream mounts keeping an old `post-merge.yml`: the negative-list guard would call the orchestrator with `--type housekeeping` → refused loudly (CHANGELOG note).
- `ports/index.ts` does not re-export `FileContentResult` (importers use the module path).
- The two optional plumbing fields (`reviewignoreBaseSha` on the selection config, `reviewignoreSource` on the result) live as intersection types outside `types.ts` — candidate for the next contract tidy-up.
- actionlint is not installed on the lead host (PMWG-T8 skips); CI may run it.

---

## Round 1 (after `engineer-feedback-r1.md`, CHANGES_REQUIRED at `998c3bd58`) — head `b02459e5a`

### Commits (red → fix, every fix under the bounded System Zone marker with dist, `checksums.json` and REPO-MAP regenerated)

| Implementer | Red | Fix | Scope |
|---|---|---|---|
| A (bd-ow72o, bd-i4fyw) | `058524011` (29 of 279 red in `loa-detection.test.ts` + `truncation.test.ts`) | `8d22e449a` | `core/truncation.ts`: fail-closed base `.reviewignore` read (`base_unavailable`), explicit = root-anchored or full path, implicit `**/` for slashless wildcards, structured `pattern` on every exclusion entry; `config.ts`: `TrustedReviewScope` in the yq view, `applyTrustedReviewScope`, empty `max_content_fetches` = unset |
| B (bd-w5pd9) | `fa45947b2` (8 of 46 red in `paged-fetch-contents.test.ts`, `github-cli-contents.test.ts`, `paged-fetch-coverage.test.ts`) | `04b552529` | `core/paged-fetch.ts`: placement selection with 0-byte placeholders, bytes-ahead charging, `budget` outcome, `aborted` on RATE_LIMITED / FORBIDDEN / 401 / 403, `reviewignore_unavailable` degrade from the resolved source, `ex.pattern` first; `adapters/github-cli.ts`: envelope-sized `maxBuffer`; lead's seam adjustment in `paged-fetch.test.ts` (DEC-1050) |
| C (bd-nr5i6) | — (tests only) | `74ff045cf` | `post-merge-workflow-guards.bats` PMWG-T8 runs actionlint with `-shellcheck= -pyflakes=`; `post-merge-orchestrator-type.bats` PMOT-T1/T2 pin the HINT line's stable prefix (present for `housekeeping`, absent for `bogus`) |
| lead | — | `b02459e5a` | `resources/main.ts` calls `applyTrustedReviewScope(config, trusted, cliArgs)` right after `config.trusted = trusted;` (A's item 3 wiring); CHANGELOG round-1 texts for bd-ow72o, bd-i4fyw, bd-w5pd9 |

Red/green verified on the landed shas with `red-green-npm.sh`: A `058524011` red (e.g. "an unknown base commit with no checkout file is base_unavailable with no patterns (never none)", "a symlink at the base is base_unavailable with the checkout read", "… still throws ESYMLINKREJECTED") → `8d22e449a` green 1236/1236; B `fa45947b2` red ("content that fits the bound but whose synthesized patch does not is budget, never truncated", "GitHub patches selected ahead consume the budget first: no read is issued and the outcome is budget", "RATE_LIMITED / FORBIDDEN / HTTP 401·403 stop the loop: error for the file, aborted for the rest, one call") → `04b552529` green 1243/1243.

### Suites at `b02459e5a`

`npm test` 1243/1243 (three consecutive runs under the CI-mirror load: 16 s / 15 s / 16 s, all 1243 pass); `npm run build` (gen-bb-registry + tsc + manifest) clean; `check-bb-dist-fresh.sh --check` fresh; `gen-checksums.sh --check` 2078 entries match; `repo-map-gen.sh --validate` consistent; `check-manifest-paths.sh` 0 untracked / 0 missing; the full local CI mirror (`s-tests.sh all`) was still running at the time of this report (result in `e2e.md`).

### Round-1 judgment calls → decision rows

DEC-1043 (fail-closed base read, `none` reserved for absent-at-a-readable-base and absent-in-checkout), DEC-1044 (explicit = root-anchored or full path; recorded pattern order), DEC-1045 (review-scope keys follow the trusted config; WARN not refusal; `main.ts` wiring), DEC-1046 (implicit `**/` at compile time; recorded as written), DEC-1047 (placement selection, bytes-ahead charging, `budget`), DEC-1048 (stop codes), DEC-1049 (inline anchors: no change needed, pinned), DEC-1050 (lead's test-seam landing adjustment), DEC-1051 (HINT prefix pin). All proposed, cycle `cycle-135-review-coverage-followups`, recorded by `review-sprint`.

### Open items after round 1 (filed as beads)

- bd-akkgq — scaffold: detect the legacy simple-release guard on re-mount (C § 5).
- bd-9tt4b — read the base `.reviewignore` through the contents API when the base commit is not in the clone (A § 5 "still accepted"; DEC-1043).
- bd-ous65 — on a pull request with no trusted source the review-scope keys fall to the PR head today (lead observation at review; pinned behaviour).
- bd-gyrgq — contract tidy-up: `FileContentResult` re-export, intersection-typed plumbing fields, failed-read info log, drop the stats suffix next release (A § 5, B § 5).

### Post-gate addendum — PB-9 prompt budget (lead, `b6d0a07b4`)

The local CI mirror's unit suite (run from `998c3bd58`) reported `PB-9 live gate: the repository's prompt surface fits every budget` red: `bridgebuilder-review` `SKILL.md` was 24,710 B against the 16,384 B cap (`tools/check-prompt-budget.sh`, charged with unconditionally-read `resources/*.md`). The sprint's three implementers had each added their operator-facing rules to `SKILL.md` (110 lines), and the pre-cycle prompt was already at 15,762 B. Fix (documentation only, no code or test change): the cycle-135 long-form text (exclusion grammar, protected paths, trusted review-scope keys, `.reviewignore` provenance, content-fetch outcomes table, coverage-record fields), the paged-fetch detail paragraph and the cycle-129 trusted-provider contract moved verbatim into `resources/exclusions-and-coverage.md`; `SKILL.md` keeps short pointers whose lines carry a guard word (`See …` / `… when …`) so the resource is not charged (the first wording, "failed read → … `resources/…`", was charged by the `read` imperative — reworded). `SKILL.md` is 15,245 B; `tools/check-prompt-budget.sh --quiet` rc 0; `tests/unit/prompt-budget.bats` 10/10; dist manifest, checksums (2079 entries) and REPO-MAP regenerated. The other three mirror reds (`semver-evidence.bats` cases 2/3/5, `git tag v1.0.0 … fatal: no tag message?`) are the host-local KF-034 class (recurrence 5 → 6), green in CI. Recorded as DEC-1053.
