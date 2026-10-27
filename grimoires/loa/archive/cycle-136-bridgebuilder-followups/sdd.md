# Software Design Document: Bridgebuilder and scaffold follow-ups (cycle-136)

**Version:** 1.3
**Date:** 2026-10-27
**Author:** Software Architect Agent (Claude Fable 5.1, unattended)
**Status:** Draft 1.2 — autonomous run; design-level decisions taken on the operator's behalf are § 11.D D-1.1 … D-1.6 (DEC-1067 … DEC-1072), the Flatline-driven PRD 1.1 rows DEC-1073 … DEC-1077 and the Flatline SDD rows § 11.D D-2.1 … D-2.7 (proposed, confirm at the cycle close)
**PRD:** `grimoires/loa/prd.md` 1.3 (FR-1 … FR-5)
**Cycle:** `cycle-136-bridgebuilder-followups`; **branch:** `feature/cycle-136-bridgebuilder-followups`
**Flatline:** `grimoires/loa/a2a/flatline/cycle-136-sdd-review.json` (2/2 voices, cross-scoring degraded — KF-041 shape; 5 skeptic blockers and 30 medium items, every one read; dispositions in § 11.F — 1.1 → 1.2)

---

## Table of Contents

1. Project Architecture
2. Software Stack
3. Database Design
4. UI Design
5. API Specifications
6. Error Handling Strategy
7. Testing Strategy
8. Development Phases
9. Known Risks and Mitigation
10. Open Questions
11. Appendix

---

## 1. Project Architecture

### 1.1 System Overview

Three independent changes in two components of the Loa framework:

- **C-1 Scaffold (shell).** `scaffold_post_merge_workflow` in `.claude/scripts/lib/scaffold-post-merge-workflow.sh` gains a *legacy-guard check* inside its existing-file (idempotency) branch and an opt-in *fix* mode. Callers: `mount-loa.sh:703` (`scaffold_post_merge_workflow ""`) and `mount-submodule.sh:308`. One detection path (`awk`); no `yq` (D-2.1).
- **C-2 Base `.reviewignore` through the contents API (TypeScript 5.9).** `paged-fetch.ts` `attempt` resolves the base branch's `.reviewignore` through `IGitProvider.getFileContent` when the local read reports the base commit missing from the clone, confirms a 404 is an absence (not an authorization gap) with one bounded probe, and passes the result into the selection.
- **C-3 Contract tidy-up (TypeScript 5.9).** `SelectionConfig` lives in `core/types.ts` with one optional `reviewignoreBase` result object; `TruncationResult.reviewignoreSource` is a declared field; `ports/index.ts` re-exports `FileContentResult`; a failed content read logs one WARN; the stats suffix grammar is removed; FR-5 downgrades head-side scope validation to a WARN in pull-request mode with an explicit hand-off to `applyTrustedReviewScope`.

### 1.2 Architectural Pattern

Hexagonal as today: `paged-fetch.ts` (core) talks to the provider through the `IGitProvider` port; `truncateFiles` (core) stays synchronous and receives inputs, never performs I/O beyond the existing local `.reviewignore` read. The scaffold is a sourced bash library with no new dependency.

### 1.3 Component Diagram

```
mount-loa.sh / mount-submodule.sh ──► scaffold_post_merge_workflow(source_path)   [C-1]
                                         │ existing file?
                                         ├─ yes → legacy_release_guard_check(target)  → WARN | silent   (awk only)
                                         │           └─ LOA_SCAFFOLD_FIX_RELEASE_GUARD=1 → rewrite one `if:` line (safe write) | refuse WARN
                                         └─ no  → cp | git checkout (unchanged)

fetchPRFilesTwoPass (cache: Map<baseSha, BaseReviewignore|undefined>)
   └─► attempt ─► resolveBaseReviewignore(git, owner, repo, pin.base_sha, repoRoot, pin.files, cache)   [C-2]
                     │ local readBaseReviewignore → ok → {patterns, "base"} · absent → {[], "none"} · other → undefined
                     │ unknown_commit → getFileContent(".reviewignore", base_sha, 1 MiB)
                     │      text (regular file) → {patterns, "base"} + INFO line
                     │      404 → access probe on a file the PR modifies/removes at the base (maxBytes 1):
                     │             readable → {[], "none"} · 404 / error / no such file → undefined
                     │      other failure → undefined
                     ▼
         truncateFiles(listed, { ...selConfig, reviewignoreBase?, reviewignoreBaseSha })
                     └─ reviewignoreBase given → use it; else today's read (base_unavailable + degrade on failure — DEC-1043)
```

### 1.4 Components

| Component | Files | Owner |
|---|---|---|
| C-1 scaffold legacy-guard check + fix mode | `.claude/scripts/lib/scaffold-post-merge-workflow.sh` (header comment documents the flag), `tests/unit/mount-workflow-scaffold.bats` (new cases MWS-T13 …), `CHANGELOG.md` | A |
| C-2 base `.reviewignore` via contents API | `resources/core/paged-fetch.ts`, `resources/core/truncation.ts` (typed `BaseRead`, `resolveBasePatterns` helper), `__tests__/paged-fetch-reviewignore.test.ts` (new), `__tests__/truncation.test.ts`, `resources/exclusions-and-coverage.md`, `CHANGELOG.md` | B |
| C-3 contract tidy-up + FR-5 | `resources/core/paged-fetch.ts`, `resources/core/truncation.ts`, `resources/config.ts`, `__tests__/paged-fetch-coverage.test.ts`, `__tests__/paged-fetch-contents.test.ts`, `__tests__/truncation.test.ts`, `CHANGELOG.md`; Phase 0 (lead): `resources/core/types.ts`, `resources/ports/index.ts` | B (after C-2); lead for Phase 0 |

## 2. Software Stack

### 2.1 Languages and runtimes
Bash 5 (library sourced by the mount scripts under `set -euo pipefail`; bats-core tests); TypeScript 5.9 on Node 22 (`node:test` via tsx; `npm run build` = gen-bb-registry + tsc + dist manifest).

### 2.2 Build and verification
`npm test`, `npm run build`, `tools/check-bb-dist-fresh.sh --check`, `tools/check-prompt-budget.sh --quiet` (SKILL.md ≤ 16,384 B — unchanged this cycle), `tools/gen-checksums.sh`, `repo-map-gen.sh`, `check-manifest-paths.sh`; bats via the npx cache on PATH; the cross-platform shell lint (no `sed -i`, `readlink -f`, `grep -P`, `find -printf`, bare `timeout`).

### 2.3 External services
GitHub contents API through the existing allowlisted `gh api repos/<o>/<r>/contents/<path>?ref=<40-hex>` shape (`adapters/github-cli.ts` `getFileContent`); no new shape, no headers; the adapter's 30 s `gh` timeout and its error mapping (`httpStatus`, `RATE_LIMITED`, `FORBIDDEN`) apply unchanged.

## 3. Database Design

None. The only persisted artefacts are the coverage record (unchanged schema — `reviewignore_source` keeps its four values) and the files the scaffold reads or, on opt-in, rewrites.

## 4. UI Design

CLI text only. Every line is single-line; filenames, provider error details and validation reasons are rendered bounded (≤ 200 characters) with control characters escaped and never a raw response body (D-2.6). New lines (stderr):

- `[scaffold] WARN: <target> keeps the legacy simple-release guard (pr_type != 'cycle' && pr_number != ''); since Loa cycle-135 housekeeping merges classify 'housekeeping' and this guard sends them to the orchestrator, which refuses. Replace it with: (needs.classify.outputs.pr_type == 'bugfix' || needs.classify.outputs.pr_type == 'other') && needs.classify.outputs.pr_number != ''  — or re-run the mount with LOA_SCAFFOLD_FIX_RELEASE_GUARD=1 to rewrite that one line (bd-nr5i6)`
- `[scaffold] fixed: <target> simple-release if: → allowlist guard (one line changed; bd-nr5i6)`
- `[scaffold] WARN: LOA_SCAFFOLD_FIX_RELEASE_GUARD=1 but <target> has no single job-level simple-release if: carrying the legacy guard — left unchanged`
- `[bridgebuilder] INFO: .reviewignore at base <sha> read through the contents API (the base commit is not in the clone)` (once per base-sha resolution; cached, so once per run unless the base moves)
- `[bridgebuilder] WARN: content read of "<file>" failed: <outcome> (no_patch)` (once per file per attempt; outcomes `error`, `too_large`, `binary`, and an empty `text` answer; the file name is JSON-quoted and bounded through `boundedForLog` — review round 1 LOW 6)
- `[bridgebuilder] WARN: bridgebuilder.<key>: the PR head's value is invalid (<reason>) — ignored on a pull request; the trusted configuration (or its default) governs`

## 5. API Specifications

### 5.1 `scaffold_post_merge_workflow(source_path)` (C-1)

Unchanged signature and return (always 0). New behaviour in the existing-file branch, one detection path (`awk`, no `yq` — D-2.1):

```
legacy_release_guard_check(target):
  # 0. target must be a regular file (not a symlink) readable by the caller; else silent (with the flag: the refuse WARN)
  # 1. J = indentation of the first non-blank, non-comment line after `^jobs:` whose indentation is > 0 (the jobs' key indent)
  #    block = from the line /^<J>simple-release:/ to the first following non-blank, non-comment line whose indentation ≤ J (or EOF)
  #    (D-2.2: no job-id regex — job ids with digits, quoted keys, anchors or aliases cannot extend the block;
  #     zero or two `simple-release:` keys → not found → silent)
  # 2. C = indentation of the first non-blank, non-comment line inside the block (the job's child indent, read from the file)
  #    walk the block tracking block scalars: a line whose value is `|`, `>` (with optional chomping/indent indicators) opens a
  #    block scalar at its own indentation k; every following line with indentation > k is scalar content and is skipped (D-2.3)
  #    candidates = lines at indentation exactly C matching /^if:[[:space:]]/ outside block-scalar content
  # 3. exactly one candidate whose value is single-line (not `|`/`>`, not empty, not ending in a flow/mapping opener) → guard
  #    zero, two or more, or multi-line → "not a single job-level if:" → silent (with the flag: the refuse WARN)
  # 4. normalise the value: strip one `${{ … }}` wrapper, strip a trailing ` # comment`, collapse whitespace runs to one space,
  #    trim, strip one pair of surrounding single or double quotes (D-2.1)
  if norm == LEGACY  → WARN (above); if LOA_SCAFFOLD_FIX_RELEASE_GUARD=1 → safe rewrite (below), print "fixed"
  elif norm == ALLOWLIST → silent
  else → silent (customised; with the flag set → the refuse WARN)
  return 0 in every branch (both callers run under set -e — DEC-1077)

safe rewrite (D-2.4): re-read the candidate line by number immediately before writing and require it to still match; build
  `<original indent>if: <ALLOWLIST>` preserving the original quoting style (none / single / double); write the whole file to a
  temp file in the same directory (mktemp there), preserve the original mode, `mv -f` over the target; refuse (WARN, no change)
  if the target is a symlink or the re-read differs.
```

`LEGACY = needs.classify.outputs.pr_type != 'cycle' && needs.classify.outputs.pr_number != ''`; `ALLOWLIST = (needs.classify.outputs.pr_type == 'bugfix' || needs.classify.outputs.pr_type == 'other') && needs.classify.outputs.pr_number != ''`. Multi-line `if: |` blocks, two job-level `if:` lines, a missing `simple-release` job and anything the normalisation does not reduce to one of the two texts are "customised" (silent). The flag is an environment variable so both callers surface it without signature changes (DEC-1068); the library's header comment and the CHANGELOG document it (D-2.7).

### 5.2 `resolveBaseReviewignore(git, owner, repo, baseSha, repoRoot, files, cache)` (C-2, `paged-fetch.ts`)

```ts
type BaseRead =
  | { ok: true; patterns: string[] }
  | { ok: false; why: "absent" | "unknown_commit" | "other"; detail: string };          // truncation.ts (exported)
type BaseReviewignore = { patterns: string[]; source: "base" | "none" };               // the resolved result
async function resolveBaseReviewignore(git: PagedContentGit, owner: string, repo: string, baseSha: string,
  repoRoot: string | undefined, files: readonly PullRequestFile[], cache: Map<string, BaseReviewignore | undefined>,
): Promise<BaseReviewignore | undefined>
```
1. `cache.has(baseSha)` → return the cached value (an `undefined` outcome is cached too, so a restarted attempt makes no second call — D-2.5). Attempts are sequential; no in-flight promise cache is needed.
2. `readBaseReviewignore(repoRoot, baseSha)` (exported from `truncation.ts`; never throws) classifies: `unknown_commit` when `git cat-file -e <sha>^{commit}` exits non-zero (exit status, not stderr text; `LC_ALL=C` on every git call — D-2.5); otherwise `absent` when `ls-tree` prints nothing; `other` for a non-blob mode, oversize, `git show` failure or timeout. `ok` → `{patterns, "base"}`; `absent` → `{[], "none"}`; `other` → `undefined`.
3. Only `unknown_commit`, and only when `typeof git.getFileContent === "function"`: `await git.getFileContent(owner, repo, ".reviewignore", baseSha, REVIEWIGNORE_MAX_BYTES)` against the run's target `owner/repo` (the PR's base repository; never a fork's). `kind: "text"` (the adapter already requires a regular `type: "file"` envelope with base64 content, answers `too_large` when `size` exceeds the bound and rejects a `size` that disagrees with the decoded bytes — so `text` is complete by construction; a symlink or directory entry is not `text`) → `{parseReviewignoreLines(content), "base"}` plus the INFO line.
4. A `GitProviderError` with `httpStatus === 404` is **not** proof of absence (an authorization gap also surfaces as 404 — SKP-002). Confirm access with one probe (D-2.6): take the first listed file whose status is `modified`, `removed` or `renamed` (`previous_filename` for renamed) — a path that exists at the base — and call `getFileContent(owner, repo, <path>, baseSha, 1)`; any `text` / `too_large` / `binary` answer proves the ref is readable → the 404 was an absence → `{[], "none"}`; a 404 or error on the probe, or no such file in the listing (all files added), → `undefined` (fail closed). At most two calls per resolution.
5. Any other result or error on step 3 (rate limit, `FORBIDDEN` / 401 / 403, malformed envelope, `too_large`, `binary`, `size` mismatch, a non-`GitProviderError` throw, a timeout surfacing as an error) → `undefined`.
6. `undefined` leaves today's path: `truncateFiles` performs its own read and reports `base_unavailable` (checkout copy, degrade — DEC-1043's trade-off, restated in § 6 and § 9 — D-2.6).
7. The result (or `undefined`) is stored in `cache` under `baseSha`. The read is outside the `max_content_fetches` cap and the `fetch_missing_patches` switch (they govern listed files).

### 5.3 `SelectionConfig` and `TruncationResult` (C-3, `core/types.ts`, Phase 0)

```ts
export type ReviewignoreSource = "base" | "checkout" | "base_unavailable" | "none";
export type SelectionConfig = Pick<BridgebuilderConfig, …the keys truncateFiles reads…> & {
  /** cycle-135 C-2: read `.reviewignore` at this PR base sha (undefined: the checkout). */
  reviewignoreBaseSha?: string;
  /** cycle-136 C-2 (D-2.5): the base `.reviewignore` already resolved by paged-fetch; wins over the sha read. */
  reviewignoreBase?: { patterns: string[]; source: "base" | "none" };
};
export interface TruncationResult { …; reviewignoreSource?: ReviewignoreSource; }
```
One optional object instead of two coupled fields (gpt IMP-005 / opus IMP-009): `source: "none"` always carries `patterns: []`. `truncateFiles(files, config: SelectionConfig): TruncationResult`; `paged-fetch.ts` imports `SelectionConfig` and `ReviewignoreSource` from `./types.js`; the intersection casts and the local type aliases are deleted in Phase 0 (opus IMP-012). `truncateFiles` resolves the base patterns through one helper `resolveBasePatterns(config)` called from both read sites (opus IMP-017): `config.reviewignoreBase` when set (skip `parseReviewignoreFile`, `reviewignoreSource = config.reviewignoreBase.source`), else today's read.

### 5.4 `ports/index.ts`
Adds `FileContentResult` to the `./git-provider.js` type export block (Phase 0).

### 5.5 Stats suffix removal
`patternSuffix` / `PATTERN_SUFFIX` / `exclusionPattern` deleted; every exclusion entry already carries `pattern`; `paged-fetch.ts` reads `ex.pattern` only; the posted stats lose the ` [pattern: <p>]` tail. `resources/exclusions-and-coverage.md` and the CHANGELOG state the removal; a repository-wide `[pattern:` search is an acceptance criterion.

### 5.6 Head-side scope validation in pull-request mode (FR-5, Could Have)
`resolveConfig(cliArgs, env, yaml)` already receives `env`; it computes `const prMode = isPullRequestContext(cliArgs.pr, env)`. The YAML it validates on a pull request *is* the PR head's `.loa.config.yaml` (the trusted replacement arrives later through `loadTrustedConfig`), so a validation error there is head-origin by construction (gpt IMP-007). The head YAML is validated first, before any trusted value is seen; the trusted scope keys later *replace* the head values in `applyTrustedReviewScope` (flat lists, booleans and integers — `exclude_patterns` is recomposed as defaults + trusted + CLI; nothing is deep-merged). For the three validated scope keys (`protected_paths`, `max_content_fetches`, and the `exclude_patterns` list shape), a validation error in PR mode is caught, written as the WARN in § 4, the key is left *unset* — never the invalid value — and the key's name is appended to `provenance.deferredScopeKeys` (SKP-008). `applyTrustedReviewScope` is the only consumer: it installs the trusted source's validated value, or (no source, DEC-1055) the default, and clears the list. Every production caller of `resolveConfig` (today: `main.ts` only) must call `applyTrustedReviewScope` before using the configuration; a test pins this by reading `main.ts` and asserting the call order, and `fetchPRFilesTwoPass` / the review pipeline never read the three keys from a configuration that still carries a non-empty `deferredScopeKeys` (an assertion at the pipeline entry throws a config error naming the keys). An invalid *trusted* value stays a config error; local mode throws as today. Composition tests cover a permissive valid head value vs a restrictive trusted value and mixed valid/invalid keys (gpt IMP-008).

### 5.7 Configuration
No new `.loa.config.yaml` keys. One new environment variable for the mount scripts: `LOA_SCAFFOLD_FIX_RELEASE_GUARD=1`.

## 6. Error Handling Strategy

| Situation | Behaviour |
|---|---|
| `if:` unparseable / multi-line / zero or several job-level candidates / no `simple-release` job | treated as customised: silent; with the flag, the refuse WARN |
| legacy text on a step-level `if:`, inside a block scalar, in another job or in a comment | never matched (job-scoped, child-indentation-anchored, block-scalar aware) |
| target is a symlink, or the line changed between detection and rewrite | fix mode refuses (WARN), file unchanged |
| base `.reviewignore`: local read `unknown_commit` | contents API (one call per base sha per run, cached incl. failures) |
| base `.reviewignore`: local read `other` (symlink, oversize, git error) | today's `base_unavailable` + degrade, no API call |
| contents API 404 for `.reviewignore` | one access probe on a base-existing listed file; readable → `none`; else `base_unavailable` |
| contents API rate-limit / auth / malformed / too_large / binary / timeout / non-provider throw | fall through to today's `base_unavailable` + degrade (fail closed) |
| provider without `getFileContent` | today's behaviour |
| **`base_unavailable` on a pull request** | the checkout copy — PR-head-controlled — governs and the review degrades (`reviewignore_unavailable`, merge-blocking). This is DEC-1043's deliberate trade-off: dropping the deny list would send excluded content (secrets, vendored trees) to the model; applying the head's copy can hide files, which the degrade makes visible and merge-blocking. C-2 makes this path rare on shallow checkouts; it is not changed here (SKP-001 → D-2.6). |
| failed content read of a listed file | outcome recorded as today + one bounded WARN line |
| invalid head scope key on a PR | WARN, key unset and deferred, trusted value or default governs; locally: config error (unchanged) |

## 7. Testing Strategy

- **C-1 bats** (`mount-workflow-scaffold.bats` MWS-T13 …), every case with the library sourced under `set -euo pipefail` as the callers do, PATH set to a directory holding only coreutils/awk/sed/grep/bash (no `yq`): legacy file → WARN + byte-identical (`cmp`); allowlist → silent; customised single-line `if:` → silent; flag + legacy → one changed line, "fixed" notice, idempotent second run, result byte-identical to the allowlist fixture; flag + customised → refuse WARN, unchanged, exit 0; negative fixtures byte-identical with and without the flag — step-level `if:` with the legacy text, a second job (`legacy-copy`) carrying it, the text in a comment, a multi-line `if: |` block, the text inside a `run: |` block scalar at the child indentation, two job-level `if:` lines, no `simple-release` job, a job id with digits (`simple-release-2:`) following the block, a 4-space-indented workflow, a `${{ … }}`-wrapped legacy guard (detected; rewritten preserving the wrapper is NOT attempted — refuse), a symlinked target (refuse); existing MWS-T1 … T12 unchanged.
- **C-2** (`paged-fetch-reviewignore.test.ts`, fixture adapter; the local read's class forced through a `deps.readBaseReviewignore` seam): `unknown_commit` + API text → `reviewignore_source: "base"`, base patterns applied, `degraded: false`, exactly one `.reviewignore` call at `pin.base_sha` against the target `owner/repo`, one INFO line; + 404 + probe readable → `none`, not degraded, exactly two calls; + 404 + probe 404 → `base_unavailable`; + 404 + no modified/removed file in the listing → `base_unavailable`, one call; + RATE_LIMITED / FORBIDDEN / 401 / malformed / too_large / binary / size mismatch / a plain `TypeError` thrown / a timeout-shaped error → `base_unavailable` (per case); `ok` / `absent` locally → zero API calls; `other` locally → `base_unavailable`, zero calls; provider without `getFileContent` → today's behaviour; local mode → no call; restarted attempt (one head move), same base → no second call, also when the first outcome was `undefined`; base move → one new call; content at the bound / one over / empty; `maxContentFetches: 0` and `fetchMissingPatches: false` do not affect it. `truncation.test.ts`: the three `BaseRead` failure classes via temp git repos (incl. `cat-file -e` for an unknown sha), `resolveBasePatterns` honouring `reviewignoreBase` at both read sites.
- **C-3**: `tsc` clean; no intersection casts (grep pin in a test); `FileContentResult` imported from `../ports/index.js`; coverage fixtures use `pattern`; a literal ` [pattern: x]` in stats is plain text; a repository-wide `[pattern:` search is clean outside CHANGELOG / archive / a2a / the plain-text fixtures; failed read → one bounded WARN (a filename with a newline is escaped). **FR-5**: per key, PR mode (three detection routes) + valid trusted → WARN + trusted value; PR mode + no source → default; invalid trusted → error; local → throws; `deferredScopeKeys` populated by `resolveConfig` and cleared by `applyTrustedReviewScope`; the `main.ts` call-order pin; the pipeline-entry assertion fires on a configuration with a non-empty `deferredScopeKeys`; composition: permissive valid head vs restrictive trusted; mixed valid/invalid keys.
- Red-first for every behaviour: each implementer delivers a test patch (red) and a fix patch (green); the lead reproduces red → green on the landed shas (`red-green-npm.sh`, `red-test-check.sh` for bats).
- Suites: `npm test`, the scaffold + pipeline bats files, `tools/check-prompt-budget.sh`, the cross-platform shell lint patterns, the CI mirror from the landed head before the PR.

## 8. Development Phases

| Phase | Owner | Content |
|---|---|---|
| 0 contract | lead | `core/types.ts` gains `ReviewignoreSource`, `SelectionConfig` (with `reviewignoreBaseSha` and `reviewignoreBase`) and `TruncationResult.reviewignoreSource`; `ports/index.ts` re-export; `truncation.ts` exports `readBaseReviewignore`, `BaseRead`, `parseReviewignoreLines`, `REVIEWIGNORE_MAX_BYTES` and takes `SelectionConfig`; `paged-fetch.ts` imports both types from `./types.js`, its local aliases and the intersection casts deleted; behaviour unchanged; tests compile |
| 1 | A | C-1 scaffold check + fix mode (awk only, safe write), bats, header comment, CHANGELOG |
| 2 | B | C-2 typed `BaseRead` (cat-file classification), `resolveBaseReviewignore` with the probe and the cache, `resolveBasePatterns`, tests, reference doc, CHANGELOG |
| 3 | B | C-3 remaining items: suffix removal, bounded WARN on failed read, tests; then FR-5 (own commit pair): PR-mode deferral + `deferredScopeKeys` + pipeline assertion + `main.ts` pin |
| 4 | lead | land red → fix pairs, dist/manifests, review gate (≤ 3 dissent runs), audit gate, PR, Bridgebuilder, merge, record, archive, JACKED_OUT |

## 9. Known Risks and Mitigation

| Risk | Mitigation |
|---|---|
| awk block detection ends early or late on an unusual layout | block ends at the first non-blank non-comment line with indentation ≤ J; child indentation read from the file; block scalars tracked; fixtures for digits in job ids, 4-space indents, `run: |` content |
| the rewrite races a concurrent edit or follows a symlink | re-read-and-compare immediately before the write; symlink refused; temp file + `mv -f` in the same directory with the mode preserved |
| a 404 from the contents API hides an authorization gap | the access probe on a base-existing listed file; no such file → fail closed |
| `getFileContent`'s 404 surfaces as a generic NETWORK error | the adapter maps gh's `HTTP 404` to `httpStatus: 404`; the test pins the shape from the adapter's mapping |
| a stalled contents request | the adapter's 30 s `gh` timeout → error → `undefined` → `base_unavailable`; one test with a timeout-shaped rejection |
| `base_unavailable` on a PR applies the head's `.reviewignore` | DEC-1043's trade-off, now rare (C-2); the degrade is merge-blocking; a future cycle may choose "no patterns" if the leak side is reassessed (OQ-3) |
| removing the suffix breaks a downstream `stats` reader | structured `pattern` shipped in cycle-135; CHANGELOG names the removal; single-commit revert |
| FR-5 deferral consumed without the trusted replacement | `deferredScopeKeys` + the pipeline-entry assertion + the `main.ts` call-order pin |

## 10. Open Questions

- OQ-1: should the scaffold also detect the legacy guard on the `full-pipeline` job (`pr_type == 'cycle'`)? Not part of the defect: that guard is unchanged since cycle-134. Out of scope.
- OQ-2: should `reviewignore_source` distinguish the API read (`base_api`)? Decided no (DEC-1064, DEC-1070): same trust level, same file; the INFO line carries the provenance.
- OQ-3: should `base_unavailable` on a pull request apply no patterns instead of the head's copy? Kept as DEC-1043 (leak side weighted heavier); recorded for a future review once C-2 has made the path rare in practice.

## 11. Appendix

### 11.D Design decisions taken on the operator's behalf

| # | Decision | Row |
|---|----------|-----|
| D-1.1 | Scaffold detection reads only single-line `if:` forms; multi-line or unknown text is "customised" and silent | DEC-1067 |
| D-1.2 | The opt-in fix is the environment variable `LOA_SCAFFOLD_FIX_RELEASE_GUARD=1`, not a new positional argument | DEC-1068 |
| D-1.3 | The base `.reviewignore` is resolved in `paged-fetch.ts` (async) and handed to the synchronous selection; `truncateFiles` keeps its own read as the fallback | DEC-1069 |
| D-1.4 | `SelectionConfig` moves to `core/types.ts`; `TruncationResult.reviewignoreSource` declared; no new coverage-record values | DEC-1070 |
| D-1.5 | The stats suffix is removed in this cycle; the failed-read line is a `[bridgebuilder] WARN:` on stderr, no logger threading | DEC-1071 |
| D-1.6 | Head-side scope validation is downgraded to a WARN only in pull-request mode, inside `resolveConfig` via `isPullRequestContext(cliArgs.pr, env)` | DEC-1072 |
| D-2.1 | One detection path: `awk`; no `yq`; normalisation strips a `${{ }}` wrapper, a trailing comment and one pair of quotes (Flatline opus IMP-003/004) | DEC-1078 |
| D-2.2 | The job block ends at the first non-blank, non-comment line with indentation ≤ J; the child indentation is read from the file (Flatline SKP-003, opus IMP-001/002) | DEC-1079 |
| D-2.3 | Block scalars are tracked; content lines never yield candidates (Flatline SKP-004) | DEC-1080 |
| D-2.4 | Safe rewrite: symlink refused, re-read before write, temp file in the same directory, mode preserved, `mv -f` (Flatline gpt IMP-003, opus IMP-005) | DEC-1081 |
| D-2.5 | `unknown_commit` by `git cat-file -e` exit status under `LC_ALL=C`; the resolution cached per base sha including failures (`Map.has`); one `reviewignoreBase` object (Flatline opus IMP-007/008/009, gpt IMP-005/006/011) | DEC-1082 |
| D-2.6 | A 404 for `.reviewignore` is confirmed by one access probe on a base-existing listed file before it becomes `none`; no probe target → fail closed; `base_unavailable` keeps DEC-1043's checkout-copy trade-off, restated (Flatline SKP-002, SKP-001, opus IMP-015); WARN rendering bounded and escaped (gpt IMP-009) | DEC-1083 |
| D-2.7 | FR-5 deferral is explicit: `provenance.deferredScopeKeys`, cleared by `applyTrustedReviewScope`, asserted at the pipeline entry, `main.ts` call order pinned (Flatline SKP-008, gpt IMP-007/008); the flag is documented in the library header and the CHANGELOG (opus IMP-014) | DEC-1084 |

### 11.E Grounding reads
`.claude/scripts/lib/scaffold-post-merge-workflow.sh` (whole), `.claude/scripts/mount-loa.sh:703`, `.claude/scripts/mount-submodule.sh:308`, `.github/workflows/post-merge.yml:106-114, 190-192`, `tests/unit/mount-workflow-scaffold.bats` (MWS-T1 … T12); `resources/core/paged-fetch.ts:34-71, 305-375, 463-470, 495`, `resources/core/truncation.ts:394-470, 540-600, 1393-1414, 1461, 1613`, `resources/core/types.ts:62, 328`, `resources/ports/index.ts`, `resources/ports/git-provider.ts`, `resources/adapters/github-cli.ts` (`getFileContent`, `gh()` error mapping, the 30 s timeout), `resources/config.ts:634-640, 1544-1560` (`isPullRequestContext`, `resolveConfig`), `resources/main.ts` (`resolveConfig` → `loadTrustedConfig` → `applyTrustedReviewScope` order), `__tests__/paged-fetch-coverage.test.ts:67-91`.

### 11.F Flatline SDD review dispositions (1.1 → 1.2)

Cross-scoring degraded (KF-041 shape): 0 HIGH_CONSENSUS, 5 skeptic blockers, 30 medium items; every item read.

| Item | Disposition |
|---|---|
| SKP-001 (790) — `base_unavailable` applies the PR-head-controlled checkout copy; the degrade does not prevent exclusion | **Kept, restated (§ 6, § 9, OQ-3; D-2.6):** DEC-1043's trade-off — the deny list protects secrets from reaching the model; the degrade is merge-blocking; C-2 makes the path rare. Not changed in this cycle. |
| SKP-002 (730) — a 404 can be an authorization gap | **Integrated (§ 5.2 step 4; D-2.6):** one access probe on a base-existing listed file (`maxBytes` 1); no probe target → fail closed. |
| SKP-003 (740) — job-id regex misses digits/quoted keys | **Integrated (§ 5.1; D-2.2):** block ends at the first non-blank non-comment line with indentation ≤ J. |
| SKP-004 (710) — block scalars can hold text at the child indentation | **Integrated (§ 5.1; D-2.3):** block-scalar tracking; fixture with `run: |` content. |
| SKP-008 (720) — PR-mode suppression without a guaranteed `applyTrustedReviewScope` | **Integrated (§ 5.6; D-2.7):** `deferredScopeKeys`, cleared by the applier, asserted at the pipeline entry, `main.ts` order pinned. |
| opus IMP-003, IMP-004, gpt IMP-001/002 — single detection path; normalisation rules; conservative subset | **Integrated (§ 5.1; D-2.1):** `awk` only, no `yq`; `${{ }}`, trailing comment, quotes; quoted keys / anchors / aliases / duplicates never match. PRD FR-1 1.2 drops the `yq` path. |
| opus IMP-001/002, gpt IMP-002 — block termination; child indentation from the file; digit job ids | **Integrated (§ 5.1; D-2.2).** |
| gpt IMP-003, opus IMP-005 — safe rewrite mechanics | **Integrated (§ 5.1; D-2.4).** |
| opus IMP-006 — fixtures under `set -euo pipefail`; PATH with coreutils but no yq | **Integrated (§ 7).** |
| opus IMP-016 — fixtures: no `simple-release`, two `if:` lines | **Integrated (§ 7).** |
| opus IMP-007, gpt IMP-011 — classify by `cat-file -e` exit status / `LC_ALL=C` | **Integrated (§ 5.2 step 2; D-2.5).** |
| gpt IMP-006, opus IMP-008 — cache semantics (`Map.has`, failures cached) | **Integrated (§ 5.2 steps 1, 7; D-2.5).** |
| gpt IMP-005, opus IMP-009 — one `reviewignoreBase` object | **Integrated (§ 5.3; D-2.5).** |
| gpt IMP-004 — verify a regular file | **Integrated (§ 5.2 step 3):** the adapter's envelope check (`type: "file"`, base64) already rejects other entries; stated. |
| gpt IMP-012 — timeout behaviour | **Integrated (§ 2.3, § 9, § 7):** the adapter's 30 s timeout → error → `undefined`; a timeout-shaped test. |
| gpt IMP-009 — bounded WARN rendering | **Integrated (§ 4; D-2.6).** |
| gpt IMP-010 — warning deduplication | **Integrated (§ 4):** INFO once per base-sha resolution (cached); failed-file WARN once per file per attempt. |
| gpt IMP-007/008 — FR-5 provenance and composition tests | **Integrated (§ 5.6, § 7).** |
| opus IMP-010 — INFO not WARN for the notice; once-per-run vs per-base | **Integrated (§ 4).** |
| opus IMP-011 — parameterised FR-5 WARN | **Integrated (§ 4):** "the trusted configuration (or its default) governs" — the applier, not `resolveConfig`, knows which. |
| opus IMP-012 — Phase 0 takes the import switch and cast deletion | **Integrated (§ 8 Phase 0).** |
| opus IMP-013 — diagram vs § 5.2 | **Integrated (§ 1.3).** |
| opus IMP-014 — operator-facing doc for the flag | **Integrated (§ 1.4, § 5.1; D-2.7):** library header comment + CHANGELOG (the mounting SKILL.md is budget-bound; a one-line pointer only if it fits). |
| opus IMP-015 — state the checkout-copy consequence | **Integrated (§ 6, § 9).** |
| opus IMP-017 — one `resolveBasePatterns` helper | **Integrated (§ 5.3).** |
| opus IMP-018 — non-`GitProviderError` throw | **Integrated (§ 5.2 step 5, § 7).** |

> Sources: `grimoires/loa/a2a/flatline/cycle-136-sdd-review.json`
