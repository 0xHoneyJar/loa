# Product Requirements Document: Bridgebuilder and scaffold follow-ups (cycle-136)

**Version:** 1.0
**Date:** 2026-10-27
**Author:** PRD Architect Agent (Claude Fable 5.1, unattended)
**Status:** Draft — autonomous run (operator instruction 2026-10-27, quoted verbatim in the brief: "i sign off on all your recommended choices for the desicions and you can proceed with fixing up any remaining beads")
**Brief:** `grimoires/loa/context/cycle-136-brief.md`
**Cycle:** `cycle-136-bridgebuilder-followups` (ledger, active); **branch:** `feature/cycle-136-bridgebuilder-followups` from `main 54a8c2824` (the merge of PR #1306, so the confirmed cycle-135 rows DEC-1011 … DEC-1060 are the base)
**Flatline:** pending (`grimoires/loa/a2a/flatline/cycle-136-prd-review.json` after the review)
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
14. Appendix B — Grounding reads

> Sources: this document's sections

---

## Executive Summary

Cycle-135 shipped the review-coverage follow-ups and left three small, well-specified beads behind: the mount scaffold does not tell a downstream repository that its `post-merge.yml` still carries the legacy release guard (bd-akkgq); a Bridgebuilder run on a shallow checkout cannot read the base branch's `.reviewignore` and therefore degrades every Loa-aware pull-request review (bd-9tt4b); and the Bridgebuilder contract carries a handful of plumbing debts — a missing re-export, two fields living as intersection types, a silent failed read, and a stats suffix kept "for one release" (bd-gyrgq).

This cycle closes the three through the golden path in one sprint with two implementers (A: shell + bats for the scaffold; B: TypeScript for the two Bridgebuilder beads), each change tested first, shipped as one PR with a Bridgebuilder round, recorded and archived; no release — the v2.0.0-rc.8 soak continues. Nothing else is in scope.

> Sources: `grimoires/loa/context/cycle-136-brief.md`; beads bd-akkgq, bd-9tt4b, bd-gyrgq (`br show`); DEC-1043, DEC-1050, DEC-1056, DEC-1057, DEC-1060

---

## Problem Statement

### The Problem

Three behaviours shipped by cycle-135 are correct but leave an operator without a signal or a path:

1. **Legacy guard on re-mount.** `scaffold_post_merge_workflow` (`.claude/scripts/lib/scaffold-post-merge-workflow.sh:34-56`) returns at once when `.github/workflows/post-merge.yml` already exists, to preserve user customizations. A repository that mounted before cycle-135 therefore keeps the negative-list guard `needs.classify.outputs.pr_type != 'cycle' && needs.classify.outputs.pr_number != ''` on its `simple-release` job. Since cycle-135 its archive, ledger and decisions merges classify `housekeeping`, so that guard passes them to the orchestrator with `--type housekeeping`, which refuses with exit 1 and a HINT line (DEC-1041, DEC-1051). The refusal is loud by design (DEC-1060), but nothing tells the operator *at mount time* that the guard is stale.
2. **Shallow checkout degrades every review.** `parseReviewignoreFile` reads the base branch's `.reviewignore` with `git ls-tree` / `git show` at the PR base sha (`truncation.ts:447-470`). On a shallow CI checkout the base commit is not in the clone, the read fails, the checkout copy governs as `base_unavailable`, and the review degrades with the merge-blocking `reviewignore_unavailable` reason (DEC-1043, DEC-1056). The operator's only remedy is to fetch the base ref — a workflow change in every downstream repository.
3. **Contract debts.** `ports/index.ts` does not re-export `FileContentResult`; `reviewignoreBaseSha` (selection config) and `reviewignoreSource` (result) live as intersection types outside `types.ts` (`paged-fetch.ts:51-53, 465-467`); a failed content read leaves only the `omitted[].fetch` outcome and no log line (`paged-fetch.ts` has no logger in scope); the ` [pattern: <p>]` stats suffix was kept one release beside the structured `excluded[].pattern` field (`truncation.ts:394-397`, `paged-fetch.ts:63-71, 375`); and the Bridgebuilder round-2 triage noted that a PR head's invalid `protected_paths` fails the head's own review before the trusted value can replace it (`config.ts` `resolveConfig`).

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
- G-2: a re-mount over a legacy `post-merge.yml` prints one warning naming the file, the legacy guard, the allowlist replacement and bd-nr5i6, and changes nothing; the opt-in flag rewrites exactly the `if:` line of `simple-release`.
- G-3: with the base commit absent from the clone and the provider answering, the coverage record says `reviewignore_source: base` and the review does not degrade; a 404 at the base means `none`; any other provider failure keeps today's `base_unavailable` and the degrade.
- G-4: the Bridgebuilder contract has no intersection-typed plumbing, re-exports `FileContentResult`, logs a failed content read, and no longer emits or parses the stats suffix.
- G-5: one PR, every check run green on the merged head, one non-degraded Bridgebuilder verdict, record and archive, no release.

### Key Performance Indicators (KPIs)

- `npm test` green on every landed commit; the four pipeline / scaffold bats files green.
- Bridgebuilder round on the PR: `degraded: false`, 2/2 voices.
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

- UC-1: re-mount over a legacy workflow → one WARN, file unchanged; with `--fix-release-guard` (name to be confirmed in the SDD) only the `if:` line changes.
- UC-2: Bridgebuilder on a shallow checkout → the base `.reviewignore` arrives through the contents envelope; `reviewignore_source: base`; no degrade.
- UC-3: a contributor imports `FileContentResult` from `ports/index.js` and reads `reviewignoreBaseSha` / `reviewignoreSource` on the typed selection config and result.

> Sources: `grimoires/loa/context/cycle-136-brief.md`; `.claude/skills/mounting-framework/SKILL.md` (mount path); `truncation.ts:447-470`

---

## Functional Requirements

### FR-1: The scaffold detects the legacy simple-release guard on re-mount (bd-akkgq)
**Priority:** Must Have
**Description:** Inside the existing-file branch of `scaffold_post_merge_workflow` (`scaffold-post-merge-workflow.sh:38-41`), read the `simple-release` job's `if:` expression — with `yq` (`.jobs."simple-release".if`) when available, else a line-anchored `grep`/`sed` fallback — and compare it with the legacy text `needs.classify.outputs.pr_type != 'cycle' && needs.classify.outputs.pr_number != ''` (whitespace-normalised). On a match print one WARN on stderr naming the file, the legacy guard, the allowlist replacement `(needs.classify.outputs.pr_type == 'bugfix' || needs.classify.outputs.pr_type == 'other') && needs.classify.outputs.pr_number != ''` and bd-nr5i6; never modify the file. An opt-in flag (SDD names it; default off) rewrites exactly that one `if:` line to the allowlist text and prints what it changed; it refuses when the job's `if:` is neither the legacy nor the allowlist text. The function's return value and the fresh-install branches are unchanged ([ASSUMPTION decision] the mount CLI surfaces the flag; the SDD decides where — DEC-1063).
**Acceptance Criteria:**
- [ ] bats: a legacy workflow → exit 0, one WARN containing the file path, `pr_type != 'cycle'`, the allowlist text and `bd-nr5i6`; the file is byte-identical afterwards.
- [ ] bats: the current allowlist workflow → exit 0, silent; a workflow with a customised `if:` → silent (not ours to judge).
- [ ] bats: the opt-in flag on a legacy file → only the `if:` line differs (`diff` shows one changed line), a one-line notice is printed, a second run is silent; the flag on a customised `if:` → refuses with a message, file unchanged.
- [ ] bats: without `yq` on PATH the fallback detects the same legacy text.
- [ ] The fresh-install path (`cp` from `source_path`; `git checkout` fallback) is unchanged (existing `mount-workflow-scaffold.bats` cases stay green).
**Dependencies:** none.

> Sources: `.claude/scripts/lib/scaffold-post-merge-workflow.sh:20-56`, `.github/workflows/post-merge.yml:106-114`, `tests/unit/mount-workflow-scaffold.bats`, `tests/unit/cycle-124-live-scaffold.bats`; DEC-1041, DEC-1051, DEC-1060

### FR-2: Bridgebuilder reads the base `.reviewignore` through the contents API when the base commit is not in the clone (bd-9tt4b)
**Priority:** Must Have
**Description:** In `paged-fetch.ts` `attempt`, before the placement selection, when a local base read would fail because the base commit is absent (the existing `readBaseReviewignore` reports a non-`absent` failure — unknown commit), resolve the base file through the existing allowlisted contents envelope `git.getFileContent(owner, repo, ".reviewignore", pin.base_sha, REVIEWIGNORE_MAX_BYTES)` (one call, the existing 1 MiB bound and timeouts, no new allowlist shape), parse the text with the same line rules (`parseReviewignoreLines`), and hand the patterns to `truncateFiles` through a new optional selection-config input (SDD names it, e.g. `reviewignoreBasePatterns`) that takes precedence over the sha read; the result's `reviewignoreSource` is `base`. A 404 / absent answer at the base means the base has no file → `none` (DEC-1056 semantics, the checkout copy is not applied). Any other provider failure (rate limit, auth, malformed envelope, oversize, binary) keeps today's path: the checkout copy governs as `base_unavailable` and the review degrades. Local mode (no PR) and a clone that holds the base commit are unchanged (no API call). ([ASSUMPTION decision] `getFileContent` is optional on the port; when the provider lacks it the behaviour is today's — DEC-1064)
**Acceptance Criteria:**
- [ ] `paged-fetch-contents.test.ts` (or a new `paged-fetch-reviewignore.test.ts`): base commit absent + API returns the file → `reviewignore_source: "base"`, the base patterns apply, `degraded: false`, exactly one contents call for `.reviewignore` at `pin.base_sha`.
- [ ] base commit absent + API 404 → `none`, no patterns, not degraded; + API error (RATE_LIMITED / malformed / too_large / binary) → `base_unavailable`, checkout patterns, `reviewignore_unavailable` degrade (today's behaviour pinned).
- [ ] base commit present in the clone → no API call (the `git show` path answers first).
- [ ] `fetch_missing_patches: false` does not disable this read (it governs content fetches of listed files, not the base `.reviewignore`); documented.
- [ ] CHANGELOG + `resources/exclusions-and-coverage.md` state the new order: local sha read → contents API → checkout copy.
**Dependencies:** none (the port method and the envelope exist since cycle-135).

> Sources: `truncation.ts:394-470, 540-600` (`parseReviewignoreFile`, `readBaseReviewignore`, `REVIEWIGNORE_MAX_BYTES`), `paged-fetch.ts:51-60, 340-370, 463-470`, `adapters/github-cli.ts` (`getFileContent`, `contentsPathProblem`), `ports/git-provider.ts` (`FileContentResult`); DEC-1027, DEC-1028, DEC-1043, DEC-1056

### FR-3: Bridgebuilder contract tidy-up (bd-gyrgq)
**Priority:** Should Have
**Description:** (a) `ports/index.ts` re-exports `FileContentResult`. (b) `reviewignoreBaseSha` moves onto `SelectionConfig` and `reviewignoreSource` onto `TruncationResult` in `types.ts` (both optional); the intersection types in `paged-fetch.ts` and `truncation.ts` go. (c) A failed content read writes one `[bridgebuilder] WARN:` line on stderr naming the file and the outcome, in the module's existing style (no logger plumbing). (d) The ` [pattern: <p>]` stats suffix is dropped: `patternSuffix` and `PATTERN_SUFFIX` are removed, every producer sets `pattern` (already true since DEC-1050's round), the coverage reader uses `ex.pattern` only, and the `omitted[].pattern` test fixtures move to the structured field. (e) Head-side scope validation: in pull-request mode an invalid head `protected_paths` / `exclude_patterns` / `max_content_fetches` is downgraded to a WARN and the trusted value governs; in local mode it stays a config error ([ASSUMPTION decision] `resolveConfig` can learn the mode from `cliArgs.pr` / the GitHub env the same way `loadTrustedConfig` does; if not, the SDD documents (e) as deferred and the bead closes on (a)–(d) — DEC-1065).
**Acceptance Criteria:**
- [ ] `tsc` clean; `npm test` green; no `as TruncationResult & {` or `SelectionConfig & {` left in `paged-fetch.ts` / `truncation.ts`.
- [ ] A test imports `FileContentResult` from `../ports/index.js`.
- [ ] `paged-fetch-coverage.test.ts`: the suffix fixtures replaced by `pattern` fields; a stats string carrying a literal ` [pattern: x]` is treated as plain text.
- [ ] A failed read in `paged-fetch-contents.test.ts` produces one WARN line naming the file and the outcome.
- [ ] (e) if implemented: a PR-mode test where the head YAML has `protected_paths: "oops"` and the trusted source is valid → WARN + trusted value; local mode → throws as today.
**Dependencies:** FR-2 lands first (same files), or B sequences them in one worktree.

> Sources: `ports/index.ts`, `types.ts`, `paged-fetch.ts:51-71, 375, 463-470`, `truncation.ts:394-397, 883-891, 1517, 1677`, `config.ts` (`resolveConfig`, `loadTrustedConfig`, `applyTrustedReviewScope`), `__tests__/paged-fetch-coverage.test.ts:67-91`; DEC-1045, DEC-1050, DEC-1057 (round-1 disposition #12), DEC-1060

### FR-4: Ship — one PR, a non-degraded Bridgebuilder verdict, record, archive, no release
**Priority:** Must Have
**Description:** As cycle-135: review and audit gates, one PR from `feature/cycle-136-bridgebuilder-followups`, Bridgebuilder round(s) ≤ 2 with the generated and planning files excluded, admin merge when every check run on the head is green, `record-branch.sh --cycle 136 --prev origin/record/cycle-135-review-coverage-followups`, archive PR, JACKED_OUT. The CHANGELOG `[Unreleased]` gains the three entries; no version heading is added.
**Acceptance Criteria:**
- [ ] The PR title names the three behaviour changes; the body lists beads, DEC rows, gates and the Bridgebuilder outcome.
- [ ] Every check run completed green on the merged head; the archive merge classifies `housekeeping` and prepares nothing.
- [ ] Record branch pushed; cycle archived; `.run/*.cycle-136.jacked-out.json` parked.
**Dependencies:** FR-1 … FR-3.

> Sources: `~/.cache/loa/cycle-135/ship/*.sh` (the recipe that worked); DEC-0960, DEC-1057, DEC-1060

---

## Non-Functional Requirements

### Performance
One extra provider call per Bridgebuilder run at most (the base `.reviewignore`), only when the local read fails; bounded by the existing 1 MiB / timeout limits. The scaffold check is one `yq` or `grep` over one file.

### Security
The contents read for `.reviewignore` uses the existing allowlisted shape pinned to a 40-hex sha; a 404 is `none` (review everything), every other failure keeps the fail-closed degrade. The scaffold never rewrites a customised guard; the opt-in flag changes one line and refuses anything it does not recognise. Head-side validation downgrades only in pull-request mode and only to the trusted value.

### Reliability
Red-first tests for every behaviour; the pipeline and scaffold bats files and `npm test` green on every landed commit; the CI mirror run from the landed head before the PR.

### Compliance
System Zone writes under the bounded marker with manifests regenerated (DEC-0824); decision rows for every judgment call, proposed until the operator confirms.

### Authorization basis and refusal list
Operator instruction of 2026-10-27 (verbatim above). Refused regardless of instruction: writing `main` outside the merge, deleting tags or branches, bypassing red CI or an unresolved Bridgebuilder blocker, publishing a release, touching credentials or the cycle-132 … 135 records.

> Sources: `grimoires/loa/context/cycle-136-brief.md`; DEC-0824; `adapters/github-cli.ts` (`getFileContent` bounds)

---

## User Experience

### Key User Flows
Re-mount → WARN → (optional) one-line fix. Shallow CI checkout → review with `reviewignore_source: base`. Contributor → typed fields, one import.

### Interaction Patterns
All messages are single `[bridgebuilder] WARN:` or `[scaffold] WARN:` lines on stderr naming the file, the value seen and the action; no interactive prompts.

### Accessibility Requirements
Plain-text output; no colour-only signals.

> Sources: `paged-fetch.ts` / `truncation.ts` WARN style; `scaffold-post-merge-workflow.sh` output conventions

---

## Technical Considerations

### Architecture (for the SDD)
C-1 scaffold detection (bash lib + bats); C-2 base `.reviewignore` via the contents envelope (paged-fetch → truncateFiles input); C-3 contract tidy-up (types.ts, ports/index.ts, paged-fetch.ts, truncation.ts, config.ts). Two implementers: A (C-1), B (C-2 then C-3, same files, one worktree).

### System Zone authorization (explicit, cycle-level)
This PRD authorises writes under `.claude/scripts/lib/scaffold-post-merge-workflow.sh`, `.claude/skills/bridgebuilder-review/**` (source, tests, dist, SKILL.md only if the budget allows, `resources/exclusions-and-coverage.md`), `tests/unit/*.bats`, `CHANGELOG.md`, with `checksums.json`, REPO-MAP and the dist manifest regenerated in the same commit.

### Integrations
GitHub contents API through the existing `gh api` allowlist; `yq` optional for the scaffold with a grep fallback.

### Dependencies
None new.

### Technical Constraints
`SKILL.md` must stay under the 16,384 B prompt budget (DEC-1053) — documentation goes to `resources/exclusions-and-coverage.md`.

> Sources: DEC-1053; `tools/check-prompt-budget.sh`; `.claude/scripts/lib/scaffold-post-merge-workflow.sh`

---

## Scope & Prioritization

### In Scope (MVP — this cycle)
FR-1, FR-2, FR-3 (a)–(d), FR-4.

### In Scope (Future Iterations)
FR-3 (e) if `resolveConfig` cannot learn the mode cheaply; gitignore directory semantics for slashless wildcard matches (DEC-1054 discussion item); the cheval safeguard-retry bead bd-uqdl8.

### Out of Scope
Any classifier or release-guard change; releases; new allowlist shapes; changes to the cycle-135 semantics (DEC-1043, DEC-1056, DEC-1058).

### Priority order under time pressure
FR-2 (reach) → FR-1 (signal) → FR-3 (hygiene) → FR-4.

### Release-blocking status
None: no release this cycle.

> Sources: `grimoires/loa/context/cycle-136-brief.md` § Scope, § Non-goals; DEC-1054

---

## Success Criteria

G-1 … G-5 as measured in `a2a/sprint-<global>/e2e.md`: beads closed with evidence; the scaffold matrix green; the shallow-checkout fixture green with `reviewignore_source: base`; `tsc` and `npm test` green with no intersection types; one PR merged green, record, archive, no release.

> Sources: § Goals & Success Metrics

---

## Risks & Mitigation

| Risk | Mitigation |
|---|---|
| The scaffold's `yq` fallback mis-parses a multi-line `if:` block | detect only the single-line forms we ship; anything else is "customised" → silent |
| The API read of `.reviewignore` adds a provider call on every shallow-checkout run | only after the local read fails; one call; bounded |
| Dropping the suffix breaks a downstream reader of `stats` | the structured `pattern` field has shipped since cycle-135; CHANGELOG names the removal |
| FR-3 (e) needs mode awareness in `resolveConfig` | explicitly deferrable; the bead closes on (a)–(d) |

> Sources: § Functional Requirements; DEC-1050, DEC-1057

---

## Timeline & Milestones

One sprint (global 280): plan → implement (A, B) → review → audit → PR → Bridgebuilder → merge → record → archive, unattended, 2026-10-27.

> Sources: `grimoires/loa/ledger.json` (`next_sprint_number` 280)

---

## Appendix A — Decisions taken on the operator's behalf

| # | Decision | Row |
|---|----------|-----|
| D-1 | Scope: exactly the three beads; classifier/guard changes, releases and the cheval retry bead out | DEC-1061 |
| D-2 | Grounding by direct file:line reads; no /ride | DEC-1062 |
| D-3 | Scaffold: warn on the legacy guard, never overwrite; an opt-in flag rewrites exactly the `if:` line and refuses customised text | DEC-1063 |
| D-4 | Base `.reviewignore` on a shallow checkout: local sha read → contents API at the base sha → checkout copy; 404 = `none`; other failure = `base_unavailable` + degrade; source stays `base` | DEC-1064 |
| D-5 | Contract tidy-up: drop the stats suffix now; WARN line on a failed read; fields into types.ts; head-side validation softened only in PR mode and only if cheap | DEC-1065 |
| D-6 | Cycle shape: one sprint, two implementers, one PR, ≤ 2 Bridgebuilder rounds, record, archive, no release; cap USD 20 | DEC-1066 |

> Sources: this document; `grimoires/loa/decisions.yaml`

---

## Appendix B — Grounding reads

`.claude/scripts/lib/scaffold-post-merge-workflow.sh` (whole file), `.github/workflows/post-merge.yml:106-114, 190-192, 262-268`, `tests/unit/mount-workflow-scaffold.bats`, `tests/unit/cycle-124-live-scaffold.bats`; `.claude/skills/bridgebuilder-review/resources/core/truncation.ts:394-470, 540-600, 883-891, 1517, 1677`, `core/paged-fetch.ts:51-71, 340-375, 463-470`, `adapters/github-cli.ts` (`getFileContent`, `contentsPathProblem`), `ports/index.ts`, `ports/git-provider.ts`, `types.ts`, `config.ts` (`resolveConfig`, `loadTrustedConfig`, `applyTrustedReviewScope`), `__tests__/paged-fetch-coverage.test.ts:67-91`; `grimoires/loa/archive/cycle-135-review-coverage-followups/{prd,sdd,sprint}.md`; `grimoires/loa/a2a/sprint-279/{reviewer,engineer-feedback,auditor-sprint-feedback,e2e}.md`; Post-Merge Pipeline runs 40299345049, 40427521292.

> Sources: the files named above
