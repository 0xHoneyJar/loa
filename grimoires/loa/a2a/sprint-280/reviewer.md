# sprint-280 (cycle-136 Sprint 1) — implementation report

**Lead:** Fable 5.1 (contract commit, landing, FR-5 wiring, this report) · **Implementers:** two Opus 5.5 subagents in `../loa-wt-c136-{a,b}` (briefs `~/.cache/loa/cycle-136/briefs/{common,a,b}.md`, reports `reports/{a,b}.md`, patches `patches/`) · **Branch:** `feature/cycle-136-bridgebuilder-followups` from `main 54a8c2824` · **Head at this report:** `9279db32e` · **Run:** `run-20261027-d90695b1`.

## Commits (red → fix per task; every fix under the bounded System Zone marker with dist, `checksums.json` and REPO-MAP regenerated)

| Task | Red commit | Fix commit | Red-then-green |
|---|---|---|---|
| 1.0 (lead) contract | — | `3982334a0` | `SelectionConfig` / `ReviewignoreSource` into `core/types.ts` (with `reviewignoreBaseSha`, `reviewignoreBase`), `TruncationResult.reviewignoreSource`, `FileContentResult` re-export, `truncation.ts` exports, paged-fetch casts deleted; tsc clean, 1251/1251; pre-dispatch inventory `contract.md` |
| 1.1 (A) scaffold legacy-guard check + fix mode | `4e81a0df5` (16 red) | `90b259222` | `red-test-check.sh --red 4e81a0df5 --green 90b259222 -- bats tests/unit/mount-workflow-scaffold.bats` → **VERIFIED**; 41/41 bats (35 scaffold + 6 cycle-124) |
| 1.2 (B) base `.reviewignore` via the contents API | `92b8ab78f` (68 red lines) | `66c35c9c4` | `red-green-npm.sh`: red → green 1288/1288 |
| 1.3 (B) contract tidy-up (suffix removal, failed-read WARN) | `52e988057` (44 red lines) | `5d5080b69` | red → green 1297/1297 |
| 1.3b (B) FR-5 head-side validation deferral | `613ffad95` (38 red lines) | `63f6d1ae3` | red → green 1321/1321 |
| 1.4 (lead) wiring + CHANGELOG | — | `81ef8f47d` | `main.ts` passes `GITHUB_EVENT_NAME` / `GITHUB_BASE_REF` to `resolveConfig`, hands `provenance` to `applyTrustedReviewScope`, calls `assertNoDeferredScopeKeys`; CHANGELOG cycle-136 `### Changed` / `### Fixed`; tsc clean, 1321/1321, dist fresh, budget rc 0 |

Decision rows: discovery DEC-1061 … DEC-1066, Flatline PRD DEC-1073 … DEC-1077, architecture DEC-1067 … DEC-1072, Flatline SDD DEC-1078 … DEC-1084, sprint planning DEC-1085 … DEC-1088, implementer A DEC-1089 … DEC-1093 (`9514bf3da`), implementer B + FR-5 acceptance DEC-1094 … DEC-1101 (`9279db32e`).

## What was built

- **C-1 (A, `scaffold-post-merge-workflow.sh`):** `legacy_release_guard_check` — one awk pass: the jobs' key indentation J read from the file, the `simple-release:` block bounded at the first non-blank non-comment line with indentation ≤ J, the child indentation C read from the block, block scalars tracked (`|`/`>` openers; content lines skipped), exactly one single-line `if:` candidate at C or nothing; normalisation strips a trailing comment, trims, rejects block/flow openers, strips one pair of quotes (single-quote `''` unescaped), strips one `${{ }}` wrapper, collapses whitespace. LEGACY → one WARN (sdd.md § 4 text); `LOA_SCAFFOLD_FIX_RELEASE_GUARD=1` → `_legacy_release_guard_rewrite`: symlink refused, re-read-and-compare of the physical line, `cp -p` onto a same-directory `mktemp` (mode kept), awk rewrite of that one line (indent, quoting style, trailing comment, CRLF and a missing final newline preserved), `mv -f`; every failure a WARN naming the reason; return 0 in every branch; the header comment documents the check and the flag. Bats MWS-T13 … T35 (positive, negative, flag, CRLF, inline comment, non-writable file and directory, symlink, 4-space indent, `${{ }}`, `run: |` body, two `if:`, no job, digit job id; every case under `env -i … bash -euo pipefail -c 'source …'` with a scratch PATH without yq; busybox awk cross-check).
- **C-2 (B, `truncation.ts` / `paged-fetch.ts`):** `readBaseReviewignore` classifies `absent` / `unknown_commit` (by `git cat-file -e <sha>^{commit}` exit status, every git call under `LC_ALL=C`) / `other`; `parseReviewignoreFile` keeps today's mapping (`absentAtBase` helper). `resolveBaseReviewignore(git, owner, repo, baseSha, repoRoot, files, cache, readLocal)` per sdd.md § 5.2: cache (`Map.has`, failures cached), local read first, `unknown_commit` → one `getFileContent(".reviewignore", baseSha, 1 MiB)` against the target `owner/repo`; `text` → `base` + one INFO line; 404 → access probe (`getFileContent` of the first `modified`/`removed` listed file at the base, `maxBytes` 1; `text`/`too_large`/`binary` prove access) → `none`, else `undefined`; every other result or throw → `undefined` (today's `base_unavailable` + degrade). Gated to Loa-aware repositories. `truncateFiles` resolves patterns through `resolveBasePatterns(config)` at both read sites (`reviewignoreBase` wins; `none` keeps the DEC-1056 checkout check). `TwoPassDeps.readBaseReviewignore` test seam. New `paged-fetch-reviewignore.test.ts` (the full FR-2 matrix incl. probe cases, nine failure classes, cache after failure, base move, bound/over/empty, cap 0 and switch off) + truncation provenance cases.
- **C-3 (B):** `patternSuffix` / `PATTERN_SUFFIX` / `exclusionPattern` removed; readers use `ex.pattern`; `boundedForLog` (JSON-quoted, ≤ 200 chars, escaped) renders every WARN/INFO operand; failed content reads (`error` / `too_large` / `binary`, incl. empty content) write one WARN per file per attempt; grep pin over the runtime sources for the casts and `[pattern:`; coverage fixtures on `pattern`; `FileContentResult` imported from `ports/index.js` in a test.
- **FR-5 (B, `config.ts`):** `resolveConfig` computes `prMode` from `cliArgs.pr` + its `env` argument, validates the head YAML first and in PR mode downgrades an invalid `protected_paths` / `max_content_fetches` / `exclude_patterns` (new list-of-strings shape check) to one WARN, leaves the key unset and records it in `provenance.deferredScopeKeys`; `applyTrustedReviewScope(config, trusted, cli, provenance)` replaces the scope keys, skips the drift WARN for deferred keys and deletes the list; `assertNoDeferredScopeKeys(provenance)` exported; the `main.ts` call-order pin and the FR-5 matrix in `truncation.test.ts`. Lead wiring in `main.ts` (`81ef8f47d`).
- Docs: `resources/exclusions-and-coverage.md` (read order, INFO line, cache, suffix sentence removed, FR-5); CHANGELOG `### Changed` (bd-akkgq, bd-gyrgq ×2) / `### Fixed` (bd-9tt4b, FR-5); `SKILL.md` untouched (budget rc 0).

## Suites at `81ef8f47d`

`npm test` 1321/1321; `tsc --noEmit` clean; `npm run build` + `check-bb-dist-fresh.sh --check` fresh; `check-prompt-budget.sh --quiet` rc 0; `mount-workflow-scaffold.bats` 35/35 + `cycle-124-live-scaffold.bats` 6/6; `bash -n` on the library and both mount callers; `gen-checksums.sh --check` OK; `repo-map-gen.sh --validate` consistent; `check-manifest-paths.sh` 0 untracked / 0 missing.

## AC verification

FR-1 … FR-5 and Tasks 1.0 … 1.4: every criterion met with `file:line` evidence in the two implementer reports (A § 3, B § 3), reproduced here by reference; lead-owned rows: the contract commit (Task 1.0, incl. the pre-dispatch inventory), the `main.ts` FR-5 wiring (B § 5 open item → `81ef8f47d`), the CHANGELOG insertion, manifests in every fix commit. Not met by design and recorded: the pipeline-entry assertion *inside* `fetchPRFilesTwoPass` (B § 3 FR-5 last row) — the enforcement is the `main.ts` assertion plus the call-order pin (DEC-1100); `[pattern:` hits remain only in `dist/` (rebuilt) and the planning documents (A/B § 5).

## Judgment calls → decision rows

A: DEC-1089 (cp -p mode, explicit writable check), DEC-1090 (failure WARN texts), DEC-1091 (comment/CRLF/newline kept; single-quote handling), DEC-1092 (normalisation order; two lines on a fixed file), DEC-1093 (fixture semantics: 4-space positive, symlink silent, jobs end at column 0). B: DEC-1094 (Loa-aware gate), DEC-1095 (probe targets modified/removed; add-only PRs fail closed), DEC-1096 (resolved `none` keeps the checkout check; `deps.readBaseReviewignore` seam), DEC-1097 (`unknown_commit` by exit status), DEC-1098 (bounded quoted rendering), DEC-1099 (`exclude_patterns` shape check; deferral list lifecycle; one WARN per key), DEC-1100 (hand-off on provenance; `main.ts` assertion), DEC-1101 (FR-5 accepted — the deferral trigger did not fire).

## Open items (not fixed here)

- The pipeline-entry assertion inside `fetchPRFilesTwoPass` needs a `BridgebuilderConfig` field (`types.ts`); the `main.ts` assertion + pin is the enforcement (DEC-1100) — a follow-up only if judged insufficient at review.
- A's re-read-mismatch branch (`_legacy_release_guard_rewrite`, "line N changed since detection") is implemented but has no test (needs a seam between detection and write) — A § 5.
- The race window between the re-read and `mv -f` is not closed (the SDD's recipe) — A § 5.
- `compat-lib.sh` is not sourced by the library (both callers source it; it has no mode helper) — A § 5.
- shellcheck is not installed on the lead host (not run); the cross-platform lint patterns were grepped clean.
- G-3 live probe (`~/.cache/loa/cycle-136/scripts/g3-live-probe.sh <pr>`) runs after the PR is opened (Task 1.E2E).

---

## Round 1 (after `engineer-feedback-r1.md`, CHANGES_REQUIRED at `9279db32e`) — head `be35c3ac6`

| Implementer | Red | Fix | Scope |
|---|---|---|---|
| A | `eb2dac6b9` (9 red: T36/T37 continuation, T38 real fixture, T17/T26/T29–T32 one-line notice) | `be35c3ac6` | awk: a candidate `if:` followed by a deeper non-blank non-comment line is multi-line → `notsingle`; the legacy WARN prints when the flag is off or ahead of a refuse/failure WARN, a successful fix prints only its notice; `_legacy_release_guard_rewrite` returns its failure reason on stdout; new fixture `tests/fixtures/mount-workflow-scaffold/post-merge-legacy.yml` (= `git show 4256a1b3:.github/workflows/post-merge.yml`, 277 lines) with T38; 44/44 bats; busybox awk 38/38; mutation: disabling the continuation check fails T36/T37 only |
| B | — | `b695008fc` (tests only, green by design) | `paged-fetch-contents.test.ts`: `deadline` writes no WARN; an empty `text` answer with additions > 0 is `error` + one WARN; the three stderr-swapping helpers forward the write callback (`process.nextTick`) under `{ concurrency: 1 }`; 1323/1323 |
| lead | — | `f46e8879e` | sdd.md § 4: the failed-read line shows the quoted, bounded file name (LOW 6) |

Red/green: A `red-test-check.sh --red eb2dac6b9 --green be35c3ac6` (see `engineer-feedback.md`); B's commit pins existing behaviour (no red by design, stated in the commit). Round-1 judgment calls: DEC-1102 … DEC-1106 (recorded by review-sprint). The temp-file leak window on a signal is bd-lkdsx (LOW 7).

