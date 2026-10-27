# Sprint Plan: Bridgebuilder and scaffold follow-ups (cycle-136)

**Version:** 1.1
**Date:** 2026-10-27
**Author:** Sprint Planner Agent (Claude Fable 5.1, unattended)
**PRD Reference:** `grimoires/loa/prd.md` (1.1, FR-1 … FR-5, G-1 … G-5)
**SDD Reference:** `grimoires/loa/sdd.md` (1.1, C-1 … C-3, D-1.1 … D-1.6, DEC-1073 … DEC-1077)
**Flatline:** pending (`grimoires/loa/a2a/flatline/cycle-136-sprint-review.json` after the review)
**Ledger:** cycle `cycle-136-bridgebuilder-followups`, sprint global 280 (local sprint-1)
**Execution:** `/run sprint-plan --no-consolidate` (one PR for the one sprint, DEC-0960); Opus 5.5 implementers A and B in linked worktrees returning `git diff --cached` patches (test patch first, then fix); the lead (Fable 5.1) lands, reviews, audits and ships.
**Task kinds:** every task carries `kind: mechanical | judgment` (DEC-0144); the lead's tasks are `judgment`; no `operator` task exists — the operator's instruction of 2026-10-27 ("i sign off on all your recommended choices for the desicions and you can proceed with fixing up any remaining beads") authorises the whole cycle; proposed decision rows are confirmed at the close.
**Spend:** USD 20 cap in the meter's unit (DEC-1066): Flatline reviews, dissent runs and the Bridgebuilder rounds on subscription routes; real charges ≈ 0.
**System Zone authorization:** DEC-0824 carries over — `.claude/scripts/lib/scaffold-post-merge-workflow.sh`, `.claude/skills/bridgebuilder-review/**`, `tests/unit/*.bats`, `CHANGELOG.md`, under the bounded marker with `checksums.json`, REPO-MAP and the dist manifest regenerated in the same commit.

---

## Executive Summary

One sprint closes the three beads cycle-135 left open: the scaffold warns about (and can fix) a legacy release guard on re-mount (bd-akkgq), Bridgebuilder reads the base `.reviewignore` through the contents API on shallow checkouts (bd-9tt4b), and the Bridgebuilder contract loses its intersection types, suffix grammar and silent failed read (bd-gyrgq). Two implementers: A owns the shell scaffold; B owns both TypeScript beads in sequence. The lead lands red → fix pairs, runs the gates and ships one PR with a Bridgebuilder round; no release.

## Sprint Overview

| Sprint | Global | Goal | Owners |
|---|---|---|---|
| Sprint 1 | 280 | FR-1 … FR-3 implemented and tested; FR-4 shipped | lead, A, B |

Duration: one unattended day (2026-10-27). Team: the lead plus two Opus 5.5 implementers. Cadence: implementers return patches; the lead lands them in dependency order and runs the gates.

## Sprint 1: The three follow-ups and the ship (global 280)

### Sprint Goal

Close bd-akkgq, bd-9tt4b and bd-gyrgq with red-first tests, ship them as one PR with a non-degraded Bridgebuilder verdict, record and archive the cycle; no release.

### Deliverables

- `scaffold-post-merge-workflow.sh`: legacy-guard check (yq, job-scoped awk fallback) and the `LOA_SCAFFOLD_FIX_RELEASE_GUARD=1` fix mode; bats MWS-T13 … (C-1).
- `paged-fetch.ts` `resolveBaseReviewignore` + `SelectionConfig.reviewignoreBasePatterns` / `reviewignoreBaseSource` honoured by `truncateFiles`; `paged-fetch-reviewignore.test.ts` (C-2).
- `core/types.ts` `SelectionConfig` + `TruncationResult.reviewignoreSource`; `ports/index.ts` `FileContentResult`; suffix grammar removed; failed-read WARN; PR-mode validation downgrade in `resolveConfig`; tests updated (C-3).
- CHANGELOG `[Unreleased]` entries for the three beads; `resources/exclusions-and-coverage.md` updated (the read order; the suffix removal).
- One PR, Bridgebuilder round(s), record branch, archive, JACKED_OUT (FR-4).

### Acceptance Criteria

- [ ] FR-1 AC rows all green (`mount-workflow-scaffold.bats`: legacy → WARN + byte-identical; allowlist → silent; customised → silent; flag + legacy → one changed line, idempotent; flag + customised → refused, exit 0; step-level / second-job / comment / multi-line fixtures byte-identical; with and without `yq` the same verdicts; MWS-T1 … T12 unchanged).
- [ ] FR-2 AC rows all green (`paged-fetch-reviewignore.test.ts`: `unknown_commit` + API text → `base`, not degraded, one call at `pin.base_sha` against the target repo, one notice; 404 → `none`; each other failure → `base_unavailable` + degrade; `ok` / `absent` / `other` locally → zero calls; no `getFileContent`, local mode, restart with the same base, base move, bound / over / empty, cap 0 and switch off — all pinned).
- [ ] FR-3 AC rows all green (`tsc` clean; no intersection casts; `FileContentResult` from `ports/index.js`; coverage fixtures on `pattern`; the `[pattern:` grep pin; failed read → one WARN); FR-5 AC rows green if landed (PR-mode invalid head key → WARN + trusted value or default; invalid trusted → error; local → throws), else FR-5 recorded as deferred.
- [ ] `npm test`, `npm run build`, `check-bb-dist-fresh.sh --check`, `check-prompt-budget.sh --quiet`, the scaffold and pipeline bats files green at every landed commit; CI mirror from the landed head.
- [ ] Review All good, audit APPROVED; PR merged only when every check run on the exact final head is completed and the six required checks are `success` (skipped only for path-filtered jobs, listed); Bridgebuilder non-degraded with the verdict's head sha recorded; CI mirror and secret scan recorded; record + archive, JACKED_OUT.

### Technical Tasks

<!-- → **[G-n]** names the PRD goal; ⇐ names the blocking task(s) (edge-or-none); every line ends with · kind: … -->

- [ ] Task 1.0: Contract commit (lead, System Zone) — `core/types.ts`: `SelectionConfig` (the `Pick` + `reviewignoreBaseSha?`, `reviewignoreBasePatterns?`, `reviewignoreBaseSource?`) and `TruncationResult.reviewignoreSource?`; `ports/index.ts` re-exports `FileContentResult`; `truncation.ts` exports `readBaseReviewignore`, `parseReviewignoreLines`, `REVIEWIGNORE_MAX_BYTES`; `paged-fetch.ts` imports `SelectionConfig` from `./types.js` (behaviour unchanged); `npm test` green; dist + manifests → **[G-4]** · kind: judgment
- [ ] Task 1.1: Scaffold legacy-guard check and fix mode (A, System Zone) — `scaffold-post-merge-workflow.sh`: in the existing-file branch, `legacy_release_guard_check` per sdd.md § 5.1 (mikefarah `yq` v4 `.jobs."simple-release".if` when `yq --version` names it, else an awk pass scoped to the `simple-release:` job block that accepts exactly one single-line job-level `if:` at the job's child indentation; step-level lines, other jobs, comments and multi-line values never match; whitespace-normalised comparison; WARN text per sdd.md § 4; `LOA_SCAFFOLD_FIX_RELEASE_GUARD=1` rewrites exactly the matched physical line, prints the notice, refuses with a WARN otherwise; return 0 in every branch); bats MWS-T13 … red first incl. the negative fixtures (step-level, second job, comment, multi-line) each run with and without `yq`; CHANGELOG line (bd-akkgq) → **[G-2]** ⇐ 1.0 · kind: mechanical
- [ ] Task 1.2: Base `.reviewignore` through the contents API (B, System Zone) — `truncation.ts`: `readBaseReviewignore` classifies `absent` / `unknown_commit` / `other` (exported with `parseReviewignoreLines`, `REVIEWIGNORE_MAX_BYTES`); `paged-fetch.ts`: `resolveBaseReviewignore(git, owner, repo, pin.base_sha, repoRoot, cache)` per sdd.md § 5.2 (`ok` → `base`; `absent` → `none`; `unknown_commit` → one `getFileContent(".reviewignore", base_sha, REVIEWIGNORE_MAX_BYTES)` against the target `owner/repo`: text → `base` + notice line, 404 → `none`, else undefined; `other` → undefined; cached per base sha across attempts; outside `max_content_fetches` / `fetch_missing_patches`); the selection receives `reviewignoreBasePatterns` / `reviewignoreBaseSource`; `truncation.ts` honours them at both read sites and skips `parseReviewignoreFile`; `paged-fetch-reviewignore.test.ts` red first (fixture adapter over the full FR-2 matrix); `resources/exclusions-and-coverage.md` + CHANGELOG (bd-9tt4b) → **[G-3]** ⇐ 1.0 · kind: mechanical
- [ ] Task 1.3: Contract tidy-up and FR-5 (B, System Zone) — `paged-fetch.ts` / `truncation.ts`: delete the intersection casts, `patternSuffix`, `PATTERN_SUFFIX`, `exclusionPattern`; readers use `ex.pattern`; one `[bridgebuilder] WARN:` on a failed content read (FR-3, bd-gyrgq, its own commit pair); then FR-5 (Could Have, separate commit pair): `config.ts` `resolveConfig` learns the mode with `isPullRequestContext(cliArgs.pr, env)` and downgrades an invalid head `protected_paths` / `max_content_fetches` / `exclude_patterns` shape to a WARN with the key left unset (the trusted value or the default governs; an invalid trusted value stays an error; local throws); tests: coverage fixtures on `pattern`, literal ` [pattern: x]` is plain text, a repository `[pattern:` grep pin, failed-read WARN, a grep pin that no `& {` cast remains, the FR-5 matrix (three keys × `--pr` / `GITHUB_EVENT_NAME` / `GITHUB_BASE_REF`, no-source default, invalid trusted error, local throws); CHANGELOG (bd-gyrgq; FR-5 line) → **[G-4]** ⇐ 1.2 · kind: mechanical
- [ ] Task 1.4: Sprint close (lead) — land A (1.1) and B (1.2, 1.3) as red commit then fix commit each, under the marker with dist, checksums and REPO-MAP regenerated; red-first verified (`red-test-check.sh` for bats, `red-green-npm.sh` for the skill); CHANGELOG assembled; DEC rows for the implementers' judgment calls; `reviewer.md` → **[G-1]** ⇐ 1.1, 1.3 · kind: judgment
- [ ] Task 1.5: Review and audit (lead) — `/review-sprint` with ≤ 3 dissent runs (`adversarial-review.sh --type review`, code-only diffs), `engineer-feedback.md` (C-11 grammar, verdict-derive consistent); `/audit-sprint` → `auditor-sprint-feedback.md`, COMPLETED, ledger sprint 280 completed, beads closed with evidence → **[G-1]** ⇐ 1.4 · kind: judgment
- [ ] Task 1.6: Ship (lead) — secret scan; PR from `feature/cycle-136-bridgebuilder-followups` (title names the three behaviour changes; body lists beads, DEC rows, gates); Bridgebuilder round(s) ≤ 2 with the generated and planning files excluded, triage comment per round, fixes red-first; admin merge only when every check run on the final head is completed and green; `record-branch.sh --cycle 136 --prev origin/record/cycle-135-review-coverage-followups`; archive PR (housekeeping) merged; JACKED_OUT with the completion block → **[G-5]** ⇐ 1.5 · kind: judgment
- [ ] Task 1.E2E: Sprint 1 goal validation — G-1 (three beads closed with commit and test), G-2 (the scaffold matrix), G-3 (the shallow-checkout fixtures; `reviewignore_source: base`), G-4 (`tsc`, no casts, re-export, suffix gone, WARN), G-5 (every check run green on the merged head, non-degraded Bridgebuilder verdict, one PR, record, archive, spend ≤ USD 20) → `a2a/sprint-280/e2e.md` → **[G-5]** ⇐ 1.6 · kind: judgment

### Patch contract (per-implementer path allowlist)

| Implementer | May change | Must not touch |
|---|---|---|
| A | `.claude/scripts/lib/scaffold-post-merge-workflow.sh`, `tests/unit/mount-workflow-scaffold.bats`, `CHANGELOG.md` (its own line) | the mount scripts' call sites, `post-merge.yml`, anything under `.claude/skills/` |
| B | `resources/core/paged-fetch.ts`, `resources/core/truncation.ts`, `resources/config.ts` (the PR-mode downgrade only), `resources/__tests__/paged-fetch*.test.ts`, `resources/__tests__/truncation.test.ts`, `resources/__tests__/loa-detection.test.ts`, `resources/exclusions-and-coverage.md`, `CHANGELOG.md` (its own lines) | `core/types.ts` and `ports/index.ts` (the lead's Task 1.0), `adapters/github-cli.ts`, `SKILL.md` (prompt budget), `dist/` |

A patch outside its allowlist is returned, not landed. Implementers make no live model or GitHub calls and never commit, push or stash in their worktrees.

### Seams Under Test

| Seam | Catches | Misses | Prior art |
|------|---------|--------|-----------|
| `scaffold_post_merge_workflow` over fixture workflows (legacy / allowlist / customised / step-level / second job / comment / multi-line) with and without `yq` on PATH | a stale guard left silent; a customised guard overwritten; a step-level or foreign `if:` mistaken for the job's; yq/awk disagreement | the mount CLI's own flag surface (none changed) | `mount-workflow-scaffold.bats` MWS-T1 … T12 |
| `fetchPRFilesTwoPass` with a fixture adapter whose `getFileContent` serves `.reviewignore` at the base sha (text / 404 / each failure class / absent method), with the local read forced to `ok`, `absent`, `unknown_commit` or `other` | a degrade on a shallow checkout; the PR's own copy applied; an API call on a local answer; a repeated call across attempts | the real `gh` 404 shape (pinned from the adapter's error mapping, not a live call) | `paged-fetch-contents.test.ts`, `paged-fetch-coverage.test.ts` |
| `truncateFiles` with `reviewignoreBasePatterns` set | the selection ignoring the resolved patterns; the provenance mislabelled | — | `truncation.test.ts` provenance block |
| `resolveConfig` in PR mode vs local with an invalid head scope key | the head failing its own review; local silently downgraded | — | `truncation.test.ts` trusted-scope block |
| the coverage reader without the suffix grammar | a `stats` string parsed for a pattern it no longer carries | downstream readers outside this repository | `paged-fetch-coverage.test.ts:67-91` |

### Dependencies

- None external beyond the host toolchain: Node 22.22, tsx and TypeScript 5.9 in the skill, bats 1.13 through the npx cache, jq 1.7, `yq` v4 (optional for the scaffold; the tests scrub PATH for the fallback case), `gh` 2.x authenticated for the ship steps.
- Internal: Task 1.0 → 1.1, 1.2; 1.2 → 1.3 (same files, implementer B); 1.4 after 1.1 and 1.3; 1.5 after 1.4; 1.6 after 1.5; 1.E2E after 1.6.

### Security Considerations

- The only new network read is `.reviewignore` at the PR base sha through the existing allowlisted contents shape; a 404 is `none` (review everything); any other failure keeps the fail-closed `base_unavailable` degrade; the PR head's copy is never applied.
- The scaffold rewrites nothing unless the operator sets the flag, and then only an `if:` line whose text it recognises exactly; a customised guard is left alone with a WARN.
- The PR-mode validation downgrade never installs the head's invalid value: the key is left unset so the trusted value (or the default) governs; local mode is unchanged.
- System Zone writes under the bounded marker with manifests regenerated; secret scan before every push; implementers make no live calls.

### Risks & Mitigation

- Risk: the awk fallback matches a step-level `if:` → the scan is scoped to the `simple-release:` block and stops at the next job key; a fixture with a step-level `if:` pins it.
- Risk: the real `gh` 404 surfaces differently from the fixture → the test uses the adapter's own `GitProviderError` shape (`httpStatus` 404) and the adapter's mapping is read, not assumed; a non-404 failure falls back to today's path, so a mis-shape degrades rather than hides.
- Risk: dropping the suffix breaks an external `stats` reader → CHANGELOG names the removal; the structured field has shipped since cycle-135.
- Risk: B's two tasks collide → sequential in one worktree; 1.3 lands only after 1.2.
- Risk: the Bridgebuilder round degrades → prefix excludes for generated and planning files; the PR is code, tests and docs well under the file cap.

### Success Metrics

- G-1: 3 of 3 beads closed with commit and test.
- G-2: the scaffold matrix green (legacy WARN, allowlist silent, customised silent, flag fixes one line, fallback without yq).
- G-3: the shallow-checkout fixtures green with `reviewignore_source: base` and no degrade; the fail-closed cases pinned.
- G-4: `tsc` clean, no intersection casts, `FileContentResult` re-exported, suffix gone, failed-read WARN, PR-mode downgrade.
- G-5: every check run green on the merged head; one PR; a non-degraded Bridgebuilder verdict; record and archive; spend ≤ USD 20.

> Sources: prd.md § Functional Requirements, § Goals & Success Metrics; sdd.md § 1.4, § 5, § 7, § 8; DEC-1061 … DEC-1072

---

## Appendix

### Goals (from prd.md § Goals & Success Metrics)

| Goal | Criterion | Evidence |
|---|---|---|
| G-1 | Every in-scope bead closed with evidence | 3 beads closed, each close reason naming the commit and the test |
| G-2 | Re-mount warns about the legacy guard and can fix exactly one line | the FR-1 bats matrix |
| G-3 | A shallow checkout gets `reviewignore_source: base` without a degrade | the FR-2 fixtures |
| G-4 | The contract carries no "next release" debt | `tsc`, the FR-3 tests, a grep pin |
| G-5 | Green suites, one PR, one non-degraded Bridgebuilder verdict, record, archive, no release | check runs on the merged head; the Bridgebuilder summary; the ledger |

### Flatline sprint review dispositions
Pending the review.
