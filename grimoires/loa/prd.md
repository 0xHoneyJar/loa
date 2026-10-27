# Product Requirements Document: Bridgebuilder and scaffold follow-ups (cycle-136)

**Version:** 1.3
**Date:** 2026-10-27
**Author:** PRD Architect Agent (Claude Fable 5.1, unattended)
**Status:** Draft — autonomous run (operator instruction 2026-10-27, quoted verbatim in the brief: "i sign off on all your recommended choices for the desicions and you can proceed with fixing up any remaining beads")
**Brief:** `grimoires/loa/context/cycle-136-brief.md`
**Cycle:** `cycle-136-bridgebuilder-followups` (ledger, active); **branch:** `feature/cycle-136-bridgebuilder-followups` from `main 54a8c2824` (the merge of PR #1306, so the confirmed cycle-135 rows DEC-1011 … DEC-1060 are the base)
**Flatline:** `grimoires/loa/a2a/flatline/cycle-136-prd-review.json` (codex-headless + claude-headless, 2/2 voices, cross-scoring degraded — KF-041 shape; 4 skeptic blockers and 30 medium items, every one read; dispositions in Appendix C — 1.0 → 1.1); the Flatline SDD review (`cycle-136-sdd-review.json`, 5 blockers / 30 medium) changed FR-1, FR-2 and FR-5 text in 1.2 (sdd.md § 11.F, DEC-1078 … DEC-1084); the Flatline sprint review (`cycle-136-sprint-review.json`, 3 blockers / 32 medium) touched FR-1, FR-2, FR-4 and FR-5 text in 1.3 (sprint.md Appendix, DEC-1085 … DEC-1088)
**Predecessor:** cycle-135 "review-coverage follow-ups" (PR #1302 → `fd20c4e0a`; record `record/cycle-135-review-coverage-followups` `881de5480`; archive PR #1304 → `564b05fbf`), whose review, Bridgebuilder rounds and implementer reports left exactly three beads open.

---

## Table of Contents

1. Executive Summary
2. Problem Statement
3. Goals & Success Metrics
4. User Personas & Use Cases
5. Functional Requirements
6. Non-Functional Requirements
7. User Experience
8. Technical Considerations
9. Scope & Prioritization
10. Success Criteria
11. Risks & Mitigation
12. Timeline & Milestones
13. Appendix A — Decisions taken on the operator's behalf
14. Appendix C — Flatline PRD review dispositions
15. Appendix B — Grounding reads

> Sources: this document's sections

---

## Executive Summary

Cycle-135 shipped the review-coverage follow-ups and left three small, well-specified beads behind: the mount scaffold does not tell a downstream repository that its `post-merge.yml` still carries the legacy release guard (bd-akkgq); a Bridgebuilder run on a shallow checkout cannot read the base branch's `.reviewignore` and therefore degrades every Loa-aware pull-request review (bd-9tt4b); and the Bridgebuilder contract carries a handful of plumbing debts — a missing re-export, two fields living as intersection types, a silent failed read, and a stats suffix kept "for one release" (bd-gyrgq).

This cycle closes the three through the golden path in one sprint with two implementers (A: shell + bats for the scaffold; B: TypeScript for the two Bridgebuilder beads), each change tested first, shipped as one PR with a Bridgebuilder round, recorded and archived; no release — the v2.0.0-rc.8 soak continues. A fifth, Could-Have requirement (FR-5, head-side scope validation failing closed on a pull request) rides along if it lands.

> Sources: `grimoires/loa/context/cycle-136-brief.md`; beads bd-akkgq, bd-9tt4b, bd-gyrgq (`br show`); DEC-1043, DEC-1050, DEC-1056, DEC-1057, DEC-1060

---

## Problem Statement

### The Problem

Three behaviours shipped by cycle-135 are correct but leave an operator without a signal or a path:

1. **Legacy guard on re-mount.** `scaffold_post_merge_workflow` (`.claude/scripts/lib/scaffold-post-merge-workflow.sh:34-56`) returns at once when `.github/workflows/post-merge.yml` already exists, to preserve user customizations. A repository that mounted before cycle-135 therefore keeps the negative-list guard `needs.classify.outputs.pr_type != 'cycle' && needs.classify.outputs.pr_number != ''` on its `simple-release` job. Since cycle-135 its archive, ledger and decisions merges classify `housekeeping` (bd-nr5i6), so that guard passes them to the orchestrator with `--type housekeeping`, which refuses with exit 1 and a HINT line (DEC-1041, DEC-1051). The refusal is loud by design (DEC-1060), but nothing tells the operator *at mount time* that the guard is stale.
2. **Shallow checkout degrades every review.** `parseReviewignoreFile` reads the base branch's `.reviewignore` with `git ls-tree` / `git show` at the PR base sha (`truncation.ts:447-470`). On a shallow CI checkout the base commit is not in the clone, the read fails, the checkout copy governs as `base_unavailable`, and the review degrades with the merge-blocking `reviewignore_unavailable` reason (DEC-1043, DEC-1056). The operator's only remedy is to fetch the base ref — a workflow change in every downstream repository.
3. **Contract debts.** `ports/index.ts` does not re-export `FileContentResult`; `reviewignoreBaseSha` (selection config) and `reviewignoreSource` (result) live as intersection types outside `core/types.ts` (`paged-fetch.ts:51-53, 465-467`); a failed content read leaves only the `omitted[].fetch` outcome and no log line (`paged-fetch.ts` has no logger in scope); the ` [pattern: <p>]` stats suffix was kept one release beside the structured `excluded[].pattern` field (`truncation.ts:394-397`, `paged-fetch.ts:63-71, 375`); and the Bridgebuilder round-2 triage noted that a PR head's invalid `protected_paths` fails the head's own review before the trusted value can replace it (`config.ts` `resolveConfig`).

### User Pain Points

- A maintainer who re-mounts Loa sees archive merges fail in the Post-Merge Pipeline with a HINT line, instead of being told at mount time what to change.
- A CI operator with the default shallow checkout gets a degraded, merge-blocked Bridgebuilder review on every Loa-aware pull request until they change the workflow.
- Contributors to the Bridgebuilder skill meet two type intersections and a duplicated suffix grammar that the cycle-135 contract commits promised to retire.

### Current State

Everything above works as specified; the gaps are signal (1), reach (2) and hygiene (3). Cycle-135's archive merge `564b05fbf` and decisions merge `54a8c2824` both classified `housekeeping` and prepared nothing on this repository, which carries the allowlist guard.

### Desired State

Mount warns about a stale guard and can fix exactly that line on request; a shallow checkout still gets `reviewignore_source: base`; the Bridgebuilder contract carries no "next release" debt.

> Sources: `.claude/scripts/lib/scaffold-post-merge-workflow.sh:34-56`, `.github/workflows/post-merge.yml:106-114, 190-192`, `truncation.ts:394-397, 447-470`, `paged-fetch.ts:51-71, 349-375, 463-470`, `ports/index.ts`, `config.ts` (`resolveConfig`, `applyTrustedReviewScope`); DEC-1041, DEC-1043, DEC-1051, DEC-1056, DEC-1060; Post-Merge Pipeline runs 40299345049 and 40427521292

---

## Goals & Success Metrics

### Primary Goals

- G-1: the three beads closed with a commit and a red-first test each.
- G-2: a re-mount over a legacy `post-merge.yml` prints one warning naming the file, the legacy guard, the allowlist replacement, the opt-in flag and bd-nr5i6, and changes nothing; the opt-in flag rewrites exactly the `if:` line of `simple-release` and refuses anything else.
- G-3: with the base commit absent from the clone and the provider answering, the coverage record says `reviewignore_source: base` and the review does not degrade; a 404 at the pinned base sha means `none`; any other provider failure keeps today's `base_unavailable` and the degrade.
- G-4: the Bridgebuilder contract has no intersection-typed plumbing, re-exports `FileContentResult`, logs a failed content read, and no longer emits or parses the stats suffix (FR-5 counts toward G-4 only if it lands; otherwise it is recorded as deferred with a bead).
- G-5: one PR, every check run green on the final head and on the merged head, one non-degraded Bridgebuilder verdict, record and archive, no release.

### Key Performance Indicators (KPIs)

- `npm test` green on every landed commit; `tests/unit/mount-workflow-scaffold.bats`, `classify-merge-pr.bats`, `post-merge-workflow-guards.bats` and `post-merge-orchestrator-type.bats` green.
- Bridgebuilder round on the PR: `degraded: false`, 2/2 voices, with the head sha recorded.
- Cycle meter spend ≤ USD 20 (subscription routes; real money ≈ 0).

### Constraints

- System Zone writes only under the bounded marker, with `checksums.json`, REPO-MAP and the Bridgebuilder dist manifest regenerated in the same commit (DEC-0824).
- Red-first tests; one sprint; one PR (DEC-0960); ≤ 2 Bridgebuilder rounds; ≤ 3 dissent runs; no release.
- Never edit the cycle-132 … 135 records; secret scan before every push.

> Sources: `grimoires/loa/context/cycle-136-brief.md` § Constraints; DEC-0824, DEC-0960, DEC-1018, DEC-1057

---

## User Personas & Use Cases

### Primary Persona: The maintainer (operator)

Signs off decision rows at each close, reads the ELI5 summaries, decides releases. Wants the three beads gone without a new semantic surprise.

### Secondary Persona: A downstream mount operator

Runs `/mount` or `/update-loa` on a repository that mounted months ago; runs Bridgebuilder in CI with `actions/checkout` at its default depth 1.

### Tertiary Persona: The lead agent and its Opus implementers

Needs crisp seams: one shell function with a test matrix; one TypeScript read path with a fixture adapter; one contract tidy-up with no behaviour change beyond the suffix.

### Use Cases

- UC-1: re-mount over a legacy workflow → one WARN, file unchanged; with `LOA_SCAFFOLD_FIX_RELEASE_GUARD=1` only the `if:` line changes; a customised or ambiguous guard is never touched.
- UC-2: Bridgebuilder on a shallow checkout → the base `.reviewignore` arrives through the contents envelope; `reviewignore_source: base`; no degrade.
- UC-3: a contributor imports `FileContentResult` from `ports/index.js` and reads `reviewignoreBaseSha` / `reviewignoreSource` on the typed selection config and result.

> Sources: `grimoires/loa/context/cycle-136-brief.md`; `.claude/skills/mounting-framework/SKILL.md` (mount path); `truncation.ts:447-470`

---

## Functional Requirements

### FR-1: The scaffold detects the legacy simple-release guard on re-mount (bd-akkgq)
**Priority:** Must Have
**Description:** Inside the existing-file branch of `scaffold_post_merge_workflow` (`scaffold-post-merge-workflow.sh:38-41`), identify the `simple-release` job's own `if:` expression and nothing else with one `awk` pass (no `yq` — DEC-1078): the job block runs from the `simple-release:` key to the first non-blank, non-comment line whose indentation is not deeper than the jobs' key indentation (DEC-1079); candidates are `if:` lines at the job's child indentation, read from the file, outside block-scalar content (DEC-1080) — step-level `if:` lines, other jobs carrying the same text, comments, `run: |` bodies and multi-line (`if: |` / `>`) values never match; exactly one candidate or nothing. Normalise the value (strip a `${{ }}` wrapper, a trailing comment, whitespace runs, one pair of quotes) and compare the expression with the legacy text `needs.classify.outputs.pr_type != 'cycle' && needs.classify.outputs.pr_number != ''`. On a match print one WARN on stderr naming the file, the legacy guard, the allowlist replacement `(needs.classify.outputs.pr_type == 'bugfix' || needs.classify.outputs.pr_type == 'other') && needs.classify.outputs.pr_number != ''`, the opt-in flag and bd-nr5i6 (the cycle-135 bead that made archive, ledger and decisions merges classify `housekeeping` and prepare nothing); never modify the file. The opt-in flag `LOA_SCAFFOLD_FIX_RELEASE_GUARD=1` (an environment variable, so both mount callers surface it without a signature change — DEC-1068) rewrites exactly that one physical `if:` line to the allowlist text (preserving indentation and quoting style; symlink target refused; the line re-read immediately before writing; temp file in the same directory, mode preserved, `mv -f` — DEC-1081) and prints a one-line notice; it refuses — with a WARN and no change — when the match is not a single-line job-level `if:` carrying exactly the legacy text (duplicate, multi-line, `${{ }}`-wrapped, aliased or customised forms). The function keeps returning 0 (both callers run under `set -e`; a refusal is a WARN line, not a mount failure — DEC-1077) and the fresh-install branches are unchanged ([ASSUMPTION decision] the mount CLI surfaces the flag; the SDD decides where — DEC-1063). The repository's own `post-merge.yml`, classifier and guard are not changed by this cycle; the scaffold may rewrite a *downstream mount's* guard only on opt-in.
**Acceptance Criteria:**
- [ ] bats: a legacy workflow → exit 0, one WARN containing the file path, `pr_type != 'cycle'`, the allowlist text, `LOA_SCAFFOLD_FIX_RELEASE_GUARD` and `bd-nr5i6`; the file is byte-identical afterwards.
- [ ] bats: the current allowlist workflow → exit 0, silent; a workflow with a customised single-line `if:` → silent (not ours to judge).
- [ ] bats: the opt-in flag on a legacy file → only the `if:` line differs (`diff` shows one changed line), a one-line notice is printed, a second run is silent; the flag on a customised `if:` → refuses with a WARN, file unchanged, exit 0.
- [ ] bats (negative fixtures, each byte-identical with and without the flag): a step-level `if:` carrying the legacy text inside `simple-release`; a second job (`legacy-copy`) carrying the legacy text while `simple-release` is already the allowlist; the legacy text inside a `#` comment; a multi-line `if: |` block holding the legacy text; the legacy text inside a `run: |` step body at the child indentation; two job-level `if:` lines; no `simple-release` job; a job id with digits (`simple-release-2:`) right after the block; a 4-space-indented workflow; a `${{ … }}`-wrapped legacy guard (detected, not rewritten); a symlinked target (→ with the flag: the refuse WARN).
- [ ] bats: every case runs with the library sourced under `set -euo pipefail` and a PATH holding coreutils/awk/sed/grep/bash but no `yq`; a CRLF workflow is detected and a rewrite keeps `\r\n`; an inline ` # comment` after the guard is ignored by detection; a non-writable target with the flag → WARN naming the failure, unchanged, exit 0.
- [ ] The fresh-install path (`cp` from `source_path`; `git checkout` fallback) is unchanged (existing `mount-workflow-scaffold.bats` cases stay green).
**Dependencies:** none.

> Sources: `.claude/scripts/lib/scaffold-post-merge-workflow.sh:20-56`, `.claude/scripts/mount-loa.sh:703`, `.claude/scripts/mount-submodule.sh:308`, `.github/workflows/post-merge.yml:106-114`, `tests/unit/mount-workflow-scaffold.bats`, `tests/unit/cycle-124-live-scaffold.bats`; DEC-1041, DEC-1051, DEC-1060, DEC-1063, DEC-1068

### FR-2: Bridgebuilder reads the base `.reviewignore` through the contents API when the base commit is not in the clone (bd-9tt4b)
**Priority:** Must Have
**Description:** The local base read (`readBaseReviewignore`, `truncation.ts`) gains typed outcomes: `ok` (patterns), `absent` (the file is missing at a commit the clone holds), `unknown_commit` (the base sha is not in the clone — `git ls-tree` fails on the object), and `other` (any other git failure, oversize, symlink). In `paged-fetch.ts` `attempt`, before the placement selection, `resolveBaseReviewignore` runs the local read first and uses its answer for `ok` (→ `base`) and `absent` (→ `none`, DEC-1056). Only `unknown_commit` triggers the contents envelope: one `git.getFileContent(owner, repo, ".reviewignore", pin.base_sha, REVIEWIGNORE_MAX_BYTES)` against the pull request's *base repository* (the `owner/repo` the run targets — for a fork PR that is the target repository, never the fork) at the pinned base sha, with the existing 1 MiB bound, timeout and allowlist shape; the text — complete by construction: the adapter answers `too_large` above the bound and rejects a `size` that disagrees with the decoded bytes — is parsed with `parseReviewignoreLines` and handed to `truncateFiles` through the selection-config input `reviewignoreBase` (`{ patterns, source }`, one object — DEC-1082), which takes precedence over the sha read; the record says `reviewignore_source: "base"` and one stderr notice names the API read (not a degrade). A 404 is not proof of absence (an authorization gap also answers 404 — DEC-1083): it becomes `none` only after one access probe — `getFileContent` of the first listed file the PR modifies, removes or renames (a path that exists at the base) at the base sha with `maxBytes` 1 — answers `text`, `too_large` or `binary`; a probe 404/error, or a PR that only adds files, keeps today's `base_unavailable` (at most two calls per resolution). Any other result (rate limit, authorisation, malformed envelope, oversize, binary, `size` mismatch) or `other` from the local read keeps today's path: the checkout copy governs as `base_unavailable` and the review degrades. The resolution — including a failed one — is cached once per base sha per run (`Map.has`) and reused across restarted attempts (a base move re-resolves; DEC-1082); `unknown_commit` is decided by `git cat-file -e <sha>^{commit}`'s exit status under `LC_ALL=C`, never by stderr text; it does not count against `max_content_fetches` and is not governed by `fetch_missing_patches` (those bound reads of *listed files*). Local mode (no PR) and a clone that holds the base commit make no API call. ([ASSUMPTION decision] `getFileContent` is optional on the port; when the provider lacks it the behaviour is today's — DEC-1064)
**Acceptance Criteria:**
- [ ] `paged-fetch-reviewignore.test.ts`: base commit absent (`unknown_commit`) + API returns the file → `reviewignore_source: "base"`, the base patterns apply, `degraded: false`, exactly one contents call, for `.reviewignore`, at `pin.base_sha`, against the target `owner/repo`; one notice line on stderr.
- [ ] base commit absent + API 404 + probe readable → `none`, no patterns, not degraded, exactly two calls; + 404 + probe 404 → `base_unavailable`; + 404 with no modified/removed/renamed file in the listing → `base_unavailable`, one call; + RATE_LIMITED / FORBIDDEN / 401 / malformed envelope / `too_large` / `binary` / `size` mismatch / a non-provider throw / a timeout-shaped error → `base_unavailable`, checkout patterns, `reviewignore_unavailable` degrade (today's behaviour pinned per case).
- [ ] base commit present in the clone → zero API calls (`ok` and `absent` answer locally); `other` local failure (a symlink at the base, oversize) → `base_unavailable` with no API call.
- [ ] a provider without `getFileContent` → today's behaviour (`base_unavailable`); local mode → no API call; a restarted attempt with the same base sha → no second call (also after a failed resolution); a base move → one new call.
- [ ] content exactly at `REVIEWIGNORE_MAX_BYTES` is read; one byte over is `too_large` → `base_unavailable`; an empty file → `base` with zero patterns.
- [ ] the read does not count against `max_content_fetches` (a cap of 0 still reads it) and `fetch_missing_patches: false` does not disable it; both pinned.
- [ ] CHANGELOG + `resources/exclusions-and-coverage.md` state the read order (local sha read → contents API when the base commit is not in the clone → checkout copy) and the notice line; `SKILL.md` is unchanged (prompt budget).
**Dependencies:** none (the port method and the envelope exist since cycle-135).

> Sources: `truncation.ts:394-470, 540-600` (`parseReviewignoreFile`, `readBaseReviewignore`, `REVIEWIGNORE_MAX_BYTES`), `paged-fetch.ts:51-60, 340-370, 463-470`, `adapters/github-cli.ts` (`getFileContent`, `contentsPathProblem`, the `gh()` error mapping), `ports/git-provider.ts` (`FileContentResult`); DEC-1027, DEC-1028, DEC-1043, DEC-1056, DEC-1064

### FR-3: Bridgebuilder contract tidy-up (bd-gyrgq)
**Priority:** Should Have
**Description:** (a) `ports/index.ts` re-exports `FileContentResult`. (b) `SelectionConfig` moves to `core/types.ts` with `reviewignoreBaseSha` and the one `reviewignoreBase` object; `reviewignoreSource` becomes a declared optional field of `TruncationResult`; the intersection types in `paged-fetch.ts` and `truncation.ts` are deleted. (c) A failed content read writes one `[bridgebuilder] WARN:` line on stderr naming the file and the outcome through `process.stderr.write`, the module's existing mechanism (no logger plumbing); the base-`.reviewignore` notice of FR-2 uses the same prefix. (d) The ` [pattern: <p>]` stats suffix is dropped: `patternSuffix`, `PATTERN_SUFFIX` and `exclusionPattern` are removed, every producer sets `pattern` (true since DEC-1050's round), the coverage reader uses `ex.pattern` only, and the `omitted[].pattern` test fixtures move to the structured field. (e) — head-side scope validation — is its own requirement, FR-5 (Could Have); bd-gyrgq closes on (a)–(d).
**Acceptance Criteria:**
- [ ] `tsc` clean; `npm test` green; no `as TruncationResult & {` or `SelectionConfig & {` left in `paged-fetch.ts` / `truncation.ts` (a grep pin in a test).
- [ ] A test imports `FileContentResult` from `../ports/index.js`.
- [ ] `paged-fetch-coverage.test.ts`: the suffix fixtures replaced by `pattern` fields; a stats string carrying a literal ` [pattern: x]` is treated as plain text.
- [ ] A failed read in `paged-fetch-contents.test.ts` produces one WARN line naming the file and the outcome.
- [ ] A repository-wide search for the literal `[pattern:` returns no hits outside `CHANGELOG.md`, `grimoires/loa/archive/`, `grimoires/loa/a2a/` and test fixtures that assert the plain-text treatment.
- [ ] Rollback: FR-2 and FR-3 (d) ship in separate commits so either is a single-commit revert before the next tag (no release this cycle).
**Dependencies:** FR-2 lands first (same files); B sequences them in one worktree.

> Sources: `ports/index.ts`, `core/types.ts:328`, `paged-fetch.ts:34-71, 375, 463-470`, `truncation.ts:394-397, 883-891, 1517, 1677`, `__tests__/paged-fetch-coverage.test.ts:67-91`; DEC-1045, DEC-1050, DEC-1057 (round-1 disposition #12), DEC-1060, DEC-1065

### FR-5: Head-side review-scope validation fails closed on a pull request (from bd-gyrgq; Bridgebuilder round-1 disposition #12)
**Priority:** Could Have
**Description:** `resolveConfig(cliArgs, env, yaml)` learns the mode with `isPullRequestContext(cliArgs.pr, env)` (the same test `loadTrustedConfig` uses: `--pr`, `GITHUB_EVENT_NAME` `pull_request` / `pull_request_target`, or `GITHUB_BASE_REF`). In pull-request mode a validation error on the head's `protected_paths`, `exclude_patterns` (list shape) or `max_content_fetches` is written as one WARN naming the key and the reason, the key is left *unset* and its name is recorded in `provenance.deferredScopeKeys` (DEC-1084); the head YAML is validated before the trusted replacement, and the trusted scope keys then *replace* the head values (flat lists, booleans and integers; `exclude_patterns` is recomposed as defaults + trusted + CLI) — nothing is deep-merged; the governing value is then whatever `applyTrustedReviewScope` installs — the trusted source's value when one was loaded and validated, else the default (DEC-1055 fail-closed) — never the head's invalid value; the applier clears the list, the review pipeline refuses a configuration that still carries deferred keys, and a test pins the `main.ts` call order. If the trusted replacement itself fails validation that remains a config error (today). In local mode every validation error stays a config error. ([ASSUMPTION decision] `resolveConfig` can learn the mode from `cliArgs.pr` / the GitHub env the same way `loadTrustedConfig` does; if not, the SDD documents FR-5 as deferred — DEC-1065)
**Acceptance Criteria:**
- [ ] For each of the three keys: PR mode (`--pr 1`) with an invalid head value and a valid trusted source → one WARN naming the key, the trusted value governs; PR mode detected through `GITHUB_EVENT_NAME=pull_request` and through `GITHUB_BASE_REF` alone → the same.
- [ ] PR mode with an invalid head value and no trusted source → WARN, the default governs (DEC-1055 path); PR mode with an invalid *trusted* value → config error (unchanged).
- [ ] Local mode (no `--pr`, no PR env) with the same invalid head values → throws as today (three cases pinned).
- [ ] `deferredScopeKeys` is populated by `resolveConfig` and cleared by `applyTrustedReviewScope`; the pipeline entry throws a config error on a configuration that still carries deferred keys; the `main.ts` call-order pin; composition: a permissive valid head value vs a restrictive trusted value, and mixed valid/invalid keys.
**Dependencies:** FR-3 (same files); deferrable without blocking the sprint.

> Sources: `config.ts:634-640` (`isPullRequestContext`), `resolveConfig`, `applyTrustedReviewScope`; DEC-1045, DEC-1055, DEC-1057 (#12), DEC-1065

### FR-4: Ship — one PR, a non-degraded Bridgebuilder verdict, record, archive, no release
**Priority:** Must Have
**Description:** As cycle-135: review and audit gates, one PR from `feature/cycle-136-bridgebuilder-followups`, Bridgebuilder round(s) ≤ 2 with the generated and planning files excluded, `record-branch.sh --cycle 136 --prev origin/record/cycle-135-review-coverage-followups`, archive PR, JACKED_OUT. **Every gate binds to the exact final PR head sha:** the admin merge requires every check run on that sha to be `completed` with conclusion `success`, or `skipped` / `neutral` only for jobs whose path filter excludes the diff (the six required checks must be `success`); any head change after a verdict invalidates it. The Bridgebuilder verdict must be non-degraded on the final head when the two-round budget allows (round 1 on the opened PR; round 2 on the head carrying round-1 fixes); when round-2 findings require fixes, those land red-first, the lead re-reads them, and the PR records that the final head was not re-reviewed by Bridgebuilder (the cycle-135 shape, DEC-1060). The CI mirror runs from the landed head before the PR and the secret scan before every push. The CHANGELOG `[Unreleased]` gains the entries; no version heading is added. Merge-triggered runs on `main` are monitored after the fact; they are not a merge gate.
**Acceptance Criteria:**
- [ ] The PR title names the behaviour changes; the body lists beads, DEC rows, gates and the Bridgebuilder outcome per head sha.
- [ ] On the final head: every check run completed; the six required checks — Template Protection, Validate Framework Files, Lint Markdown, Lint YAML, Shell Tests, Cross-Platform Compatibility — `success`; no `failure` / `cancelled` / `timed_out`; `skipped` only where the job's path filter excluded the diff (listed in the ship record); fixes landed after a Bridgebuilder round go back through the review and audit addenda before the merge; a red check on the merged commit → a follow-up fix PR, or a revert of the merge commit (with dist, checksums and REPO-MAP regenerated in the revert) if `main` is broken.
- [ ] Bridgebuilder: ≤ 2 rounds, each non-degraded; the verdict's head sha recorded; fixes after the last round red-first and named.
- [ ] CI mirror from the landed head (reds explained or fixed); secret scan clean on every pushed range.
- [ ] Every check run on the merged head completed green (post-merge monitoring); the archive merge classifies `housekeeping` and prepares nothing.
- [ ] Record branch pushed; cycle archived; `.run/*.cycle-136.jacked-out.json` parked.
**Dependencies:** FR-1 … FR-3 (FR-5 if landed).

> Sources: `~/.cache/loa/cycle-135/ship/*.sh` (the recipe that worked); DEC-0960, DEC-1057, DEC-1060, DEC-1076

---

## Non-Functional Requirements

### Performance
One extra provider call per Bridgebuilder run at most (the base `.reviewignore`), only when the base commit is not in the clone; bounded by the existing 1 MiB / timeout limits; cached per base sha across restarted attempts. The scaffold check is one `yq` or `awk` pass over one file.

### Security
The contents read for `.reviewignore` uses the existing allowlisted shape pinned to a 40-hex sha against the base repository; a 404 is `none` (review everything), every other failure keeps the fail-closed degrade; the PR head's copy is never applied. The scaffold never rewrites a customised or ambiguous guard; the opt-in flag changes one line it recognises exactly and refuses anything else. Head-side validation (FR-5) downgrades only in pull-request mode and never installs the head's invalid value.

### Reliability
Red-first tests for every behaviour; the pipeline and scaffold bats files and `npm test` green on every landed commit; the CI mirror run from the landed head before the PR; rollback by single-commit revert (no release this cycle).

### Compliance
System Zone writes under the bounded marker with manifests regenerated (DEC-0824); decision rows for every judgment call, proposed until the operator confirms.

### Authorization basis and refusal list
Operator instruction of 2026-10-27 (verbatim above). Refused regardless of instruction: writing `main` outside the merge, deleting tags or branches, bypassing red CI or an unresolved Bridgebuilder blocker, publishing a release, touching credentials or the cycle-132 … 135 records.

> Sources: `grimoires/loa/context/cycle-136-brief.md`; DEC-0824; `adapters/github-cli.ts` (`getFileContent` bounds)

---

## User Experience

### Key User Flows
Re-mount → WARN → (optional) one-line fix. Shallow CI checkout → review with `reviewignore_source: base` and one notice line. Contributor → typed fields, one import.

### Interaction Patterns
All messages are single `[bridgebuilder] WARN:` or `[scaffold] WARN:` lines on stderr naming the file, the value seen and the action; no interactive prompts; no exit-code change for the scaffold (DEC-1077).

### Accessibility Requirements
Plain-text output; no colour-only signals.

> Sources: `paged-fetch.ts` / `truncation.ts` WARN style; `scaffold-post-merge-workflow.sh` output conventions

---

## Technical Considerations

### Architecture (for the SDD)
C-1 scaffold detection (bash lib + bats); C-2 base `.reviewignore` via the contents envelope (paged-fetch → truncateFiles input); C-3 contract tidy-up (`core/types.ts`, `ports/index.ts`, `paged-fetch.ts`, `truncation.ts`) with FR-5 in `config.ts`. Two implementers: A (C-1), B (C-2 then C-3 and FR-5, same files, one worktree).

### System Zone authorization (explicit, cycle-level)
This PRD authorises writes under `.claude/scripts/lib/scaffold-post-merge-workflow.sh`, `.claude/skills/bridgebuilder-review/**` (source, tests, dist, `resources/exclusions-and-coverage.md`; `SKILL.md` only if the budget allows), `tests/unit/*.bats`, `CHANGELOG.md`, with `checksums.json`, REPO-MAP and the dist manifest regenerated in the same commit.

### Integrations
GitHub contents API through the existing `gh api` allowlist; mikefarah `yq` v4 optional for the scaffold with an `awk` fallback.

### Dependencies
None new.

### Technical Constraints
`SKILL.md` must stay under the 16,384 B prompt budget (DEC-1053) — documentation goes to `resources/exclusions-and-coverage.md`.

> Sources: DEC-1053; `tools/check-prompt-budget.sh`; `.claude/scripts/lib/scaffold-post-merge-workflow.sh`

---

## Scope & Prioritization

### In Scope (MVP — this cycle)
FR-1, FR-2, FR-3 (a)–(d), FR-4; FR-5 as Could Have.

### In Scope (Future Iterations)
FR-5 if it does not land in the sprint; gitignore directory semantics for slashless wildcard matches (DEC-1054 discussion item); the cheval safeguard-retry bead bd-uqdl8.

### Out of Scope
Any change to this repository's classifier, workflow or release guard (the scaffold rewrites a downstream mount's guard only on opt-in); releases; new allowlist shapes; changes to the cycle-135 semantics (DEC-1043, DEC-1056, DEC-1058).

### Priority order under time pressure
FR-2 (reach) → FR-1 (signal) → FR-3 (hygiene) → FR-5 → FR-4.

### Release-blocking status
None: no release this cycle.

> Sources: `grimoires/loa/context/cycle-136-brief.md` § Scope, § Non-goals; DEC-1054

---

## Success Criteria

G-1 … G-5 as measured in `a2a/sprint-280/e2e.md`: beads closed with evidence; the scaffold matrix green (positive and negative fixtures, with and without `yq`); the shallow-checkout fixture green with `reviewignore_source: base` and the fail-closed cases pinned; `tsc` and `npm test` green with no intersection types; one PR merged with every check run green on the final head, record, archive, no release.

> Sources: § Goals & Success Metrics

---

## Risks & Mitigation

| Risk | Mitigation |
|---|---|
| The scaffold's `awk` fallback matches an `if:` of a step or another job | job-scoped range at the job's indentation; exactly one match or refuse; negative fixtures pin it |
| A reformatted or multi-line legacy guard is not detected | reported as customised and left alone (silent); the CHANGELOG tells operators the single-line form that is detected |
| The API read of `.reviewignore` adds a provider call on shallow-checkout runs | only on `unknown_commit`; one call per base sha per run; bounded |
| The real `gh` 404 shape differs from the fixture | the test uses the adapter's own `GitProviderError` (`httpStatus` 404) read from the adapter's mapping; any non-404 failure falls back to the fail-closed degrade |
| Dropping the suffix breaks a downstream reader of `stats` | the structured `pattern` field has shipped since cycle-135; CHANGELOG names the removal; single-commit revert |
| FR-5 downgrade hides a genuine misconfiguration | the WARN names the key and reason; the trusted value or the default governs; local mode still throws |

> Sources: § Functional Requirements; DEC-1050, DEC-1057

---

## Timeline & Milestones

One sprint (global 280): plan → implement (A, B) → review → audit → PR → Bridgebuilder → merge → record → archive, unattended, 2026-10-27.

> Sources: `grimoires/loa/ledger.json` (sprint 280 registered)

---

## Appendix A — Decisions taken on the operator's behalf

| # | Decision | Row |
|---|----------|-----|
| D-1 | Scope: exactly the three beads; classifier/guard changes, releases and the cheval retry bead out | DEC-1061 |
| D-2 | Grounding by direct file:line reads; no /ride | DEC-1062 |
| D-3 | Scaffold: warn on the legacy guard, never overwrite; an opt-in flag rewrites exactly the `if:` line and refuses customised text | DEC-1063 |
| D-4 | Base `.reviewignore` on a shallow checkout: local sha read → contents API at the base sha → checkout copy; 404 = `none`; other failure = `base_unavailable` + degrade; source stays `base` | DEC-1064 |
| D-5 | Contract tidy-up: drop the stats suffix now; WARN line on a failed read; fields into `core/types.ts`; head-side validation as FR-5 | DEC-1065 |
| D-6 | Cycle shape: one sprint, two implementers, one PR, ≤ 2 Bridgebuilder rounds, record, archive, no release; cap USD 20 | DEC-1066 |
| D-7 | Scaffold detection and rewrite job-scoped, exactly one single-line job-level `if:`, else refuse; same with and without `yq` (Flatline SKP-001/002) | DEC-1073 |
| D-8 | Typed local-read outcomes; only `unknown_commit` calls the API; 404 at the pinned base sha = `none`; one resolution per base sha per run (Flatline gpt IMP-005…008, opus IMP-001/003) | DEC-1074 |
| D-9 | FR-5 as its own Could Have with a fail-closed clause (Flatline SKP-007, opus IMP-002/009) | DEC-1075 |
| D-10 | Ship gates bound to the exact final head sha (Flatline SKP-010) | DEC-1076 |
| D-11 | The scaffold's refusal is a WARN with return 0 (both callers run under `set -e`) (Flatline gpt IMP-004, opus IMP-005) | DEC-1077 |
| D-12 … D-18 | Flatline SDD review: awk-only detection with full normalisation; indentation-bounded job block; block-scalar tracking; safe rewrite; `cat-file` classification, failure-inclusive cache, one `reviewignoreBase` object; 404 confirmed by an access probe, DEC-1043 kept; explicit FR-5 deferral (sdd.md § 11.D D-2.1 … D-2.7) | DEC-1078 … DEC-1084 |

> Sources: this document; `grimoires/loa/decisions.yaml`

---

## Appendix C — Flatline PRD review dispositions (1.0 → 1.1)

Cross-scoring degraded (KF-041 shape): 0 HIGH_CONSENSUS, 4 skeptic blockers, 30 medium items from the two voices; every item read.

| Item | Disposition |
|---|---|
| SKP-001, SKP-002, gpt IMP-003, opus IMP-003/004/013 — the fallback cannot tell the job's `if:` from a step's, a copy in another job or a comment; multi-line values | **Integrated (FR-1, D-7):** detection and rewrite scoped to the `simple-release:` job block, exactly one single-line job-level `if:` at the job's indentation, refuse otherwise, identical with and without `yq`; negative fixtures (step-level, second job, comment, multi-line) added to the ACs. |
| SKP-007, opus IMP-002, gpt IMP-010 — the PR-mode downgrade must depend on a valid trusted replacement; "if cheap" is not a requirement | **Integrated (FR-5, D-9):** (e) is its own Could Have requirement with an explicit fail-closed clause: the key is left unset and the trusted value or the default governs; an invalid trusted value stays a config error; per-key tests incl. env-based PR detection. |
| SKP-010, gpt IMP-012, opus IMP-016 — bind the gates to the final head sha; define skipped/neutral; list the CI mirror and secret scan as ACs | **Integrated (FR-4, D-10).** |
| gpt IMP-005/006, opus IMP-001/003 — typed local-read outcomes; only "base commit not in the clone" triggers the API; 404 → `none` only at a known commit | **Integrated (FR-2, D-8):** `ok` / `absent` / `unknown_commit` / `other`; in 1.2 the 404 is additionally confirmed by an access probe (the SDD review showed a 404 can be an authorization gap — DEC-1083). |
| gpt IMP-007 — base repository and pinned sha, fork PRs | **Integrated (FR-2).** |
| gpt IMP-008 — one-call budget across restarts; cache per base sha | **Integrated (FR-2).** |
| gpt IMP-009, opus IMP-008 — matrix: no `getFileContent`, local mode, auth failure, content at the bound, empty file | **Integrated (FR-2 ACs).** |
| opus IMP-007 — the read is not governed by `max_content_fetches` / `fetch_missing_patches` | **Integrated (FR-2).** |
| opus IMP-014 — one notice line when the API supplies the file | **Integrated (FR-2; already in sdd.md § 4).** |
| opus IMP-011 — repository-wide `[pattern:` search as an AC | **Integrated (FR-3).** |
| opus IMP-012 — pin the `yq` flavour | **Integrated (FR-1: mikefarah v4 by `yq --version`, else the fallback).** |
| opus IMP-005, gpt IMP-002/004 — how the flag reaches the function; a distinguishable refusal outcome | **Integrated / decided (FR-1, D-11):** environment variable (DEC-1068); the refusal is a WARN with return 0 because both callers run under `set -e`; a non-zero return would abort the mount. |
| opus IMP-006 — define bd-nr5i6 in the PRD | **Integrated (FR-1, Problem Statement).** |
| opus IMP-015 — name the bats files; `sprint-280` | **Integrated (KPIs, Success Criteria).** |
| opus IMP-017 — documentation AC for FR-2 | **Integrated (FR-2 ACs; SKILL.md unchanged for the budget).** |
| opus IMP-018 — rollback path | **Integrated (FR-3 AC: separate commits, single-commit revert; no release).** |
| opus IMP-009 — FR-3 (e) as its own requirement | **Integrated (FR-5).** |
| gpt IMP-001 — scope contradiction (guard change vs out-of-scope) | **Integrated (§ Scope: this repository's guard unchanged; downstream rewrite only on opt-in).** |
| gpt IMP-011 — WARN semantics for base lookups | **Integrated (FR-2: notice on an API read; DEC-1056's WARN when the base lacks the file and the PR adds one is unchanged).** |
| opus IMP-010 — move (e) to a new bead | **Rejected:** FR-5 stays in this cycle as Could Have; the mode is one call away (sdd.md § 5.6). |

> Sources: `grimoires/loa/a2a/flatline/cycle-136-prd-review.json`

---

## Appendix B — Grounding reads

`.claude/scripts/lib/scaffold-post-merge-workflow.sh` (whole file), `.claude/scripts/mount-loa.sh:703`, `.claude/scripts/mount-submodule.sh:308`, `.github/workflows/post-merge.yml:106-114, 190-192, 262-268`, `tests/unit/mount-workflow-scaffold.bats`, `tests/unit/cycle-124-live-scaffold.bats`; `.claude/skills/bridgebuilder-review/resources/core/truncation.ts:394-470, 540-600, 883-891, 1517, 1677`, `core/paged-fetch.ts:34-71, 305-375, 463-470, 495`, `core/types.ts:328`, `adapters/github-cli.ts` (`getFileContent`, `contentsPathProblem`, `gh()` error mapping), `ports/index.ts`, `ports/git-provider.ts`, `config.ts:634-640, 1544-1560` (`isPullRequestContext`, `resolveConfig`, `loadTrustedConfig`, `applyTrustedReviewScope`), `__tests__/paged-fetch-coverage.test.ts:67-91`; `grimoires/loa/archive/cycle-135-review-coverage-followups/{prd,sdd,sprint}.md`; `grimoires/loa/a2a/sprint-279/{reviewer,engineer-feedback,auditor-sprint-feedback,e2e}.md`; Post-Merge Pipeline runs 40299345049, 40427521292.

> Sources: the files named above
