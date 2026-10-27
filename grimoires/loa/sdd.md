# Software Design Document: Bridgebuilder and scaffold follow-ups (cycle-136)

**Version:** 1.1
**Date:** 2026-10-27
**Author:** Software Architect Agent (Claude Fable 5.1, unattended)
**Status:** Draft 1.1 — autonomous run; design-level decisions taken on the operator's behalf are § 11.D D-1.1 … D-1.6 (DEC-1067 … DEC-1072) and the Flatline-driven PRD 1.1 rows DEC-1073 … DEC-1077 (proposed rows, confirm at the cycle close)
**PRD:** `grimoires/loa/prd.md` 1.1 (FR-1 … FR-5)
**Cycle:** `cycle-136-bridgebuilder-followups`; **branch:** `feature/cycle-136-bridgebuilder-followups`

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

- **C-1 Scaffold (shell).** `scaffold_post_merge_workflow` in `.claude/scripts/lib/scaffold-post-merge-workflow.sh` gains a *legacy-guard check* inside its existing-file (idempotency) branch and an opt-in *fix* mode. Callers: `mount-loa.sh:703` (`scaffold_post_merge_workflow ""`) and `mount-submodule.sh:308`.
- **C-2 Base `.reviewignore` through the contents API (TypeScript 5.9).** `paged-fetch.ts` `attempt` resolves the base branch's `.reviewignore` through `IGitProvider.getFileContent` when the local sha read cannot answer, and passes the patterns into the selection.
- **C-3 Contract tidy-up (TypeScript 5.9).** `SelectionConfig` moves to `core/types.ts` with the two provenance fields; `TruncationResult.reviewignoreSource` becomes a declared field; `ports/index.ts` re-exports `FileContentResult`; a failed content read logs one WARN; the stats suffix grammar is removed; head-side scope validation is downgraded to a WARN in pull-request mode.

### 1.2 Architectural Pattern

Hexagonal as today: `paged-fetch.ts` (core) talks to the provider through the `IGitProvider` port; `truncateFiles` (core) stays synchronous and receives inputs, never performs I/O beyond the existing local `.reviewignore` read. The scaffold is a sourced bash library with no new dependency (yq optional).

### 1.3 Component Diagram

```
mount-loa.sh / mount-submodule.sh ──► scaffold_post_merge_workflow(source_path)   [C-1]
                                         │ existing file?
                                         ├─ yes → legacy_release_guard_check(target)  → WARN | silent
                                         │           └─ LOA_SCAFFOLD_FIX_RELEASE_GUARD=1 → rewrite one `if:` line
                                         └─ no  → cp | git checkout (unchanged)

fetchPRFilesTwoPass ─► attempt ─► resolveBaseReviewignore(git, owner, repo, pin.base_sha, repoRoot)   [C-2]
                                      │ 1. readBaseReviewignore (git ls-tree/show)  → ok → patterns, "base"
                                      │ 2. absent at a readable base               → [] , "none"
                                      │ 3. else getFileContent(".reviewignore", base_sha, 1 MiB)
                                      │      text → parseReviewignoreLines → patterns, "base"
                                      │      404 / absent → [], "none"
                                      │      other failure → undefined (fall through)
                                      ▼
                        truncateFiles(listed, { ...selConfig, reviewignoreBasePatterns?, reviewignoreBaseSha })
                                      └─ patterns given → use them (source "base" | "none"); else today's read
```

### 1.4 Components

| Component | Files | Owner |
|---|---|---|
| C-1 scaffold legacy-guard check + fix mode | `.claude/scripts/lib/scaffold-post-merge-workflow.sh`, `tests/unit/mount-workflow-scaffold.bats` (new cases MWS-T13 …), `CHANGELOG.md` | A |
| C-2 base `.reviewignore` via contents API | `resources/core/paged-fetch.ts`, `resources/core/truncation.ts` (exported `parseReviewignoreLines`, `REVIEWIGNORE_MAX_BYTES`, a `BaseRead`-shaped result for the sha read), `__tests__/paged-fetch-reviewignore.test.ts` (new), `resources/exclusions-and-coverage.md`, `CHANGELOG.md` | B |
| C-3 contract tidy-up | `resources/core/types.ts`, `resources/core/paged-fetch.ts`, `resources/core/truncation.ts`, `resources/ports/index.ts`, `resources/config.ts`, `__tests__/paged-fetch-coverage.test.ts`, `__tests__/paged-fetch-contents.test.ts`, `__tests__/truncation.test.ts`, `CHANGELOG.md` | B (after C-2) |

## 2. Software Stack

### 2.1 Languages and runtimes
Bash 5 (library sourced by the mount scripts; bats-core tests); TypeScript 5.9 on Node 22 (`node:test` via tsx; `npm run build` = gen-bb-registry + tsc + dist manifest).

### 2.2 Build and verification
`npm test`, `npm run build`, `tools/check-bb-dist-fresh.sh --check`, `tools/check-prompt-budget.sh --quiet` (SKILL.md ≤ 16,384 B — unchanged this cycle), `tools/gen-checksums.sh`, `repo-map-gen.sh`, `check-manifest-paths.sh`; bats via the npx cache on PATH.

### 2.3 External services
GitHub contents API through the existing allowlisted `gh api repos/<o>/<r>/contents/<path>?ref=<40-hex>` shape (`adapters/github-cli.ts` `getFileContent`); no new shape, no headers.

## 3. Database Design

None. The only persisted artefacts are the coverage record (unchanged schema — `reviewignore_source` keeps its four values) and the files the scaffold reads or, on opt-in, rewrites.

## 4. UI Design

CLI text only. New lines (all single-line, stderr):

- `[scaffold] WARN: .github/workflows/post-merge.yml keeps the legacy simple-release guard (pr_type != 'cycle' && pr_number != ''); since Loa cycle-135 housekeeping merges classify 'housekeeping' and this guard sends them to the orchestrator, which refuses. Replace it with: (needs.classify.outputs.pr_type == 'bugfix' || needs.classify.outputs.pr_type == 'other') && needs.classify.outputs.pr_number != ''  — or re-run the mount with LOA_SCAFFOLD_FIX_RELEASE_GUARD=1 to rewrite that one line (bd-nr5i6)`
- `[scaffold] fixed: .github/workflows/post-merge.yml simple-release if: → allowlist guard (one line changed; bd-nr5i6)`
- `[scaffold] WARN: LOA_SCAFFOLD_FIX_RELEASE_GUARD=1 but the simple-release if: is neither the legacy nor the allowlist text — left unchanged`
- `[bridgebuilder] WARN: .reviewignore at base <sha> read through the contents API (the base commit is not in the clone)` (info-level WARN, once per run)
- `[bridgebuilder] WARN: content read of <file> failed: <outcome> (no_patch)`
- `[bridgebuilder] WARN: bridgebuilder.<key>: the PR head's value is invalid (<why>) — ignored on a pull request; the trusted value governs`

## 5. API Specifications

### 5.1 `scaffold_post_merge_workflow(source_path)` (C-1)

Unchanged signature and return (always 0). New behaviour in the existing-file branch:

```
legacy_release_guard_check(target):
  # 1. locate the simple-release job block: from the line matching /^<J>simple-release:/ (J = the jobs' key indentation,
  #    read from the file) to the next line matching /^<J>[A-Za-z_-]+:/ (the next job) or EOF
  # 2. inside the block, candidate lines are /^<J+2>if:/ exactly at the job-key child indentation (step-level `if:` lines
  #    are deeper; comments start with #; a value of `|` or `>` is multi-line)
  # 3. exactly one candidate with a single-line value → guard; zero, two or more, or multi-line → "not a single job-level if:" → silent
  #    (with the flag set: the "left unchanged" WARN)
  # yq path (mikefarah v4 only, `yq --version` matched): `.jobs."simple-release".if`; a multi-line result is treated like step 3's
  # refusal; the yq and awk paths must give the same verdict on every fixture (tests run both)
  norm  = collapse whitespace, strip surrounding quotes
  if norm == LEGACY  → WARN (above); if LOA_SCAFFOLD_FIX_RELEASE_GUARD=1 → rewrite exactly that physical line (sed on its line number), print "fixed"
  elif norm == ALLOWLIST → silent
  else → silent (customised; with the flag set → the "left unchanged" WARN)
  return 0 in every branch (both callers run under set -e — DEC-1077)
```

`LEGACY = needs.classify.outputs.pr_type != 'cycle' && needs.classify.outputs.pr_number != ''`; `ALLOWLIST = (needs.classify.outputs.pr_type == 'bugfix' || needs.classify.outputs.pr_type == 'other') && needs.classify.outputs.pr_number != ''`. Multi-line `if: |` blocks are read as customised (D-1.1). The flag is an environment variable rather than a positional argument so both callers surface it without signature changes (D-1.2).

### 5.2 `resolveBaseReviewignore(git, owner, repo, baseSha, repoRoot)` (C-2, `paged-fetch.ts`)

```ts
type BaseRead = { ok: true; patterns: string[] } | { ok: false; why: "absent" | "unknown_commit" | "other"; detail: string };
type BaseReviewignore = { patterns: string[]; source: "base" | "none" } | undefined;
async function resolveBaseReviewignore(git: PagedContentGit, owner, repo, baseSha, repoRoot, cache: Map<string, BaseReviewignore>): Promise<BaseReviewignore>
```
1. `readBaseReviewignore(repoRoot, baseSha)` (exported from `truncation.ts`; never throws) now classifies its failure: `absent` (empty `ls-tree` output at a commit the clone holds), `unknown_commit` (`ls-tree` fails on the object — "Not a valid object name" / "bad object"), `other` (mode not a blob, oversize, git error). `ok` → `{patterns, source: "base"}`; `absent` → `{patterns: [], source: "none"}`; `other` → `undefined`.
2. Only `unknown_commit`, and only when `typeof git.getFileContent === "function"`: `await git.getFileContent(owner, repo, ".reviewignore", baseSha, REVIEWIGNORE_MAX_BYTES)` against the run's target `owner/repo` (the PR's base repository; never a fork's). `kind: "text"` → `{patterns: parseReviewignoreLines(content), source: "base"}` plus the notice line; a `GitProviderError` with `httpStatus === 404` → `{patterns: [], source: "none"}` (the base sha came from `pulls/N` on this provider in this attempt, so the commit exists and the path is absent); any other result or error → `undefined`.
3. `undefined` leaves today's path: `truncateFiles` performs its own read and reports `base_unavailable` (checkout copy, degrade).
4. The result is cached in `attempt`'s caller keyed by `baseSha` for the run, so a restarted attempt with the same base sha makes no second call; a base move (new sha) resolves again. The read is outside the `max_content_fetches` cap and the `fetch_missing_patches` switch (they govern listed files).

### 5.3 `SelectionConfig` and `TruncationResult` (C-3, `core/types.ts`)

```ts
export type SelectionConfig = Pick<BridgebuilderConfig, …same keys…> & {
  /** cycle-135 C-2: read `.reviewignore` at this PR base sha (undefined: the checkout). */
  reviewignoreBaseSha?: string;
  /** cycle-136 C-2: patterns already resolved for the base (wins over the sha read); with `reviewignoreBaseSource`. */
  reviewignoreBasePatterns?: string[];
  reviewignoreBaseSource?: "base" | "none";
};
export interface TruncationResult { …; reviewignoreSource?: "base" | "checkout" | "base_unavailable" | "none"; }
```
`paged-fetch.ts` imports `SelectionConfig` from `./types.js`; the `& { reviewignoreBaseSha?: string }` and `as TruncationResult & {…}` casts are deleted. `truncateFiles` honours `reviewignoreBasePatterns` at both read sites (`truncation.ts:1461, 1613`): when set, it uses them and sets `reviewignoreSource = config.reviewignoreBaseSource`, skipping `parseReviewignoreFile`.

### 5.4 `ports/index.ts`
Adds `FileContentResult` to the `./git-provider.js` type export block.

### 5.5 Stats suffix removal
`patternSuffix` / `PATTERN_SUFFIX` / `exclusionPattern` deleted; every exclusion entry already carries `pattern`; `paged-fetch.ts` reads `ex.pattern` only; the posted stats lose the ` [pattern: <p>]` tail. `resources/exclusions-and-coverage.md` and the CHANGELOG state the removal.

### 5.6 Head-side scope validation in pull-request mode (FR-5, Could Have)
`resolveConfig(cliArgs, env, yaml)` already receives `env`; it computes `const pr = isPullRequestContext(cliArgs.pr, env)`. For the three validated scope keys (`protected_paths`, `max_content_fetches`, and the `exclude_patterns` list shape), a validation error in PR mode is caught, written as the WARN in § 4, and the key is left *unset* — never the invalid value. Fail-closed composition: `applyTrustedReviewScope` then installs the trusted source's validated value, or (no source, DEC-1055) the default; an invalid *trusted* value stays a config error. Local mode throws as today. Tests cover each key under `--pr`, `GITHUB_EVENT_NAME=pull_request` and `GITHUB_BASE_REF` detection, the no-source default path, the invalid-trusted error and the three local throws (DEC-1075).

### 5.7 Configuration
No new `.loa.config.yaml` keys. One new environment variable for the mount scripts: `LOA_SCAFFOLD_FIX_RELEASE_GUARD=1`.

## 6. Error Handling Strategy

| Situation | Behaviour |
|---|---|
| `yq` absent or not mikefarah v4 | awk fallback; same verdict on every fixture |
| `if:` unparseable / multi-line / zero or several job-level candidates | treated as customised: silent; with the flag, the "left unchanged" WARN |
| legacy text on a step-level `if:`, in another job or in a comment | never matched (job-scoped, indentation-anchored) |
| base `.reviewignore`: local read `unknown_commit` | contents API (one call per base sha per run) |
| base `.reviewignore`: local read `other` (symlink, oversize, git error) | today's `base_unavailable` + degrade, no API call |
| contents API 404 for `.reviewignore` at the base | `none` (no patterns; the PR's own copy is not applied) |
| contents API rate-limit / auth / malformed / too_large / binary | fall through to today's `base_unavailable` + degrade (fail closed) |
| provider without `getFileContent` | today's behaviour |
| failed content read of a listed file | outcome recorded as today + one WARN line |
| invalid head scope key on a PR | WARN, key unset, trusted value governs; locally: config error (unchanged) |

## 7. Testing Strategy

- **C-1 bats** (`mount-workflow-scaffold.bats` MWS-T13 …): legacy file → WARN + byte-identical; allowlist → silent; customised `if:` → silent; flag + legacy → one changed line, notice, idempotent second run; flag + customised → refuse WARN, unchanged, exit 0; negative fixtures byte-identical with and without the flag — step-level `if:` with the legacy text, a second job carrying it, the text in a comment, a multi-line `if: |` block; every fixture run twice: with mikefarah `yq` v4 on PATH and with PATH scrubbed (plus a python-yq banner stub → fallback); existing MWS-T1 … T12 unchanged.
- **C-2** (`paged-fetch-reviewignore.test.ts`, fixture adapter): `unknown_commit` + API text → `reviewignore_source: "base"`, base patterns applied, `degraded: false`, exactly one `.reviewignore` contents call at `pin.base_sha` against the target `owner/repo`, one notice line; + 404 → `none`, no patterns, not degraded; + RATE_LIMITED / FORBIDDEN / 401 / malformed / too_large / binary / size mismatch → `base_unavailable`, checkout patterns, `reviewignore_unavailable` (per case); `ok` / `absent` locally → zero API calls; `other` locally → `base_unavailable`, zero calls; provider without `getFileContent` → today's behaviour; local mode → no call; restarted attempt, same base → no second call; base move → one new call; content at the bound / one over / empty; `max_content_fetches: 0` and `fetch_missing_patches: false` do not affect it.
- **C-3**: `tsc` clean; no intersection casts (grep pin in a test); `FileContentResult` imported from `../ports/index.js`; coverage fixtures use `pattern`; a literal ` [pattern: x]` in stats is plain text; a repository-wide `[pattern:` search is clean outside CHANGELOG / archive / a2a / the plain-text fixtures; failed read → one WARN. **FR-5**: per key, PR mode (three detection routes) + valid trusted → WARN + trusted value; PR mode + no source → default; invalid trusted → error; local → throws.
- Red-first for every behaviour: each implementer delivers a test patch (red) and a fix patch (green); the lead reproduces red → green on the landed shas (`red-green-npm.sh`, `red-test-check.sh` for bats).
- Suites: `npm test`, the scaffold + pipeline bats files, `tools/check-prompt-budget.sh`, the CI mirror from the landed head before the PR.

## 8. Development Phases

| Phase | Owner | Content |
|---|---|---|
| 0 contract | lead | `core/types.ts` gains `SelectionConfig` (with the three provenance fields) and `TruncationResult.reviewignoreSource`; `ports/index.ts` re-export; `truncation.ts` exports `readBaseReviewignore`, `parseReviewignoreLines`, `REVIEWIGNORE_MAX_BYTES`; tests compile |
| 1 | A | C-1 scaffold check + fix mode, bats, CHANGELOG |
| 2 | B | C-2 `resolveBaseReviewignore` + selection input, tests, reference doc, CHANGELOG |
| 3 | B | C-3 remaining items: suffix removal, WARN on failed read, PR-mode validation, tests |
| 4 | lead | land red → fix pairs, dist/manifests, review gate (≤ 3 dissent runs), audit gate, PR, Bridgebuilder, merge, record, archive, JACKED_OUT |

## 9. Known Risks and Mitigation

| Risk | Mitigation |
|---|---|
| awk fallback matches an `if:` of another job | job-scoped scan: from the `simple-release:` key to the next job key at the same indent |
| `getFileContent`'s 404 surfaces as a generic NETWORK error | the adapter maps gh's exit 1 + `HTTP 404` to `httpStatus: 404`; the test pins the 404 → `none` path through the real error shape |
| removing the suffix breaks a downstream `stats` reader | structured `pattern` shipped in cycle-135; CHANGELOG names the removal |
| PR-mode downgrade hides a genuine misconfiguration | the WARN names the key and the reason; the trusted value is what governs anyway |

## 10. Open Questions

- OQ-1: should the scaffold also detect the legacy guard on the `full-pipeline` job (`pr_type == 'cycle'`)? Not part of the defect: that guard is unchanged since cycle-134. Out of scope unless Flatline argues otherwise.
- OQ-2: should `reviewignore_source` distinguish the API read (`base_api`)? Decided no (DEC-1064, DEC-1070): same trust level, same file.

## 11. Appendix

### 11.D Design decisions taken on the operator's behalf

| # | Decision | Row |
|---|----------|-----|
| D-1.1 | Scaffold detection reads only single-line `if:` forms (yq, awk fallback); multi-line or unknown text is "customised" and silent | DEC-1067 |
| D-1.2 | The opt-in fix is the environment variable `LOA_SCAFFOLD_FIX_RELEASE_GUARD=1`, not a new positional argument | DEC-1068 |
| D-1.3 | The base `.reviewignore` is resolved in `paged-fetch.ts` (async) and handed to the synchronous selection through `reviewignoreBasePatterns` / `reviewignoreBaseSource`; `truncateFiles` keeps its own read as the fallback | DEC-1069 |
| D-1.4 | `SelectionConfig` moves to `core/types.ts`; `TruncationResult.reviewignoreSource` declared; no new coverage-record values | DEC-1070 |
| D-1.5 | The stats suffix is removed in this cycle; the failed-read line is a `[bridgebuilder] WARN:` on stderr, no logger threading | DEC-1071 |
| D-1.6 | Head-side scope validation is downgraded to a WARN only in pull-request mode, inside `resolveConfig` via `isPullRequestContext(cliArgs.pr, env)` | DEC-1072 |

### 11.E Grounding reads
`.claude/scripts/lib/scaffold-post-merge-workflow.sh` (whole), `.claude/scripts/mount-loa.sh:703`, `.claude/scripts/mount-submodule.sh:308`, `.github/workflows/post-merge.yml:106-114, 190-192`, `tests/unit/mount-workflow-scaffold.bats` (MWS-T1 … T12); `resources/core/paged-fetch.ts:34-71, 305-375, 463-470, 495`, `resources/core/truncation.ts:394-470, 540-600, 1393-1414, 1461, 1613`, `resources/core/types.ts:328`, `resources/ports/index.ts`, `resources/ports/git-provider.ts`, `resources/adapters/github-cli.ts` (`getFileContent`, `gh()` error mapping), `resources/config.ts:634-640, 1544-1560` (`isPullRequestContext`, `resolveConfig`), `__tests__/paged-fetch-coverage.test.ts:67-91`.

### 11.F Flatline SDD review dispositions
Pending the review. (PRD 1.1's Flatline items that changed this design: SKP-001/002 → § 5.1 job-scoped exactly-one rule, DEC-1073; gpt IMP-005…008, opus IMP-001/003 → § 5.2 typed outcomes, 404 reasoning, per-base-sha cache, DEC-1074; SKP-007 → § 5.6 fail-closed composition, DEC-1075; gpt IMP-004 / opus IMP-005 → return 0 on refusal, DEC-1077.)
