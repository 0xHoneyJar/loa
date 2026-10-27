# Sprint Plan: Bridgebuilder and scaffold follow-ups (cycle-136)

**Version:** 1.3
**Date:** 2026-10-27
**Author:** Sprint Planner Agent (Claude Fable 5.1, unattended)
**PRD Reference:** `grimoires/loa/prd.md` (1.2, FR-1 … FR-5, G-1 … G-5)
**SDD Reference:** `grimoires/loa/sdd.md` (1.2, C-1 … C-3, D-1.1 … D-1.6, D-2.1 … D-2.7; DEC-1067 … DEC-1084)
**Flatline:** `grimoires/loa/a2a/flatline/cycle-136-sprint-review.json` (2/2 voices, cross-scoring degraded — KF-041 shape; 3 skeptic blockers and 32 medium items, every one read; dispositions in the Appendix — 1.2 → 1.3)
**Ledger:** cycle `cycle-136-bridgebuilder-followups`, sprint global 280 (local sprint-1)
**Execution:** `/run sprint-plan --no-consolidate` (one implementation PR for the one sprint, DEC-0960; the archive is the separate housekeeping merge, as every cycle); Opus 5.5 implementers A and B in linked worktrees returning `git diff --cached` patches (test patch first, then fix); the lead (Fable 1) lands, reviews, audits and ships. CHANGELOG lines are returned as text in the reports and inserted by the lead (no CHANGELOG hunks in implementer patches). Bounded-loop exits (unattended): a patch returned for allowlist or red-test violations more than twice → the lead implements the task or defers it with a bead; a dissent voice unreachable → lead-only gate, recorded in a DEC row; Bridgebuilder rounds exhausted with fixes still needed → the fixes land red-first, lead-read, recorded; spend cap or the one-day window reached → the run HALTS with the state recorded and the sprint stays open.
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

- `scaffold-post-merge-workflow.sh`: legacy-guard check (one awk pass) and the `LOA_SCAFFOLD_FIX_RELEASE_GUARD=1` fix mode with the safe-write recipe; bats MWS-T13 … with heredoc fixtures inside the bats file (C-1).
- `paged-fetch.ts` `resolveBaseReviewignore` (probe-confirmed 404, failure-inclusive per-base-sha cache) + `SelectionConfig.reviewignoreBase` honoured by `truncateFiles` through `resolveBasePatterns`; `paged-fetch-reviewignore.test.ts` (C-2).
- `core/types.ts` `SelectionConfig` + `TruncationResult.reviewignoreSource`; `ports/index.ts` `FileContentResult`; suffix grammar removed; bounded failed-read WARN; tests updated (C-3); FR-5 PR-mode validation deferral in `resolveConfig` as its own task (1.3b, Could Have).
- CHANGELOG `[Unreleased]` entries for the three beads; `resources/exclusions-and-coverage.md` updated (the read order; the suffix removal).
- One PR, Bridgebuilder round(s), record branch, archive, JACKED_OUT (FR-4).

### Acceptance Criteria

- [ ] FR-1 AC rows all green (`mount-workflow-scaffold.bats`: legacy → WARN + byte-identical; allowlist → silent; customised → silent; flag + legacy → one changed line, idempotent; flag + customised → refused, exit 0; every negative fixture byte-identical; `set -euo pipefail`, yq-less PATH; MWS-T1 … T12 unchanged).
- [ ] FR-2 AC rows all green (`paged-fetch-reviewignore.test.ts`: `unknown_commit` + API text → `base`, not degraded, one call at `pin.base_sha` against the target repo, one INFO line; 404 + probe readable → `none` (two calls); 404 + probe failed or no probe target → `base_unavailable`; each other failure incl. non-provider throw and timeout → `base_unavailable` + degrade; `ok` / `absent` / `other` locally → zero calls; no `getFileContent`, local mode, restart with the same base (also after a failure), base move, bound / over / empty, cap 0 and switch off — all pinned).
- [ ] FR-3 AC rows all green (`tsc` clean; no intersection casts; `FileContentResult` from `ports/index.js`; coverage fixtures on `pattern`; the `[pattern:` grep pin; failed read → one WARN); FR-5 AC rows green if landed (PR-mode invalid head key → WARN + trusted value or default; invalid trusted → error; local → throws), else FR-5 recorded as deferred.
- [ ] `npm test`, `npm run build`, `check-bb-dist-fresh.sh --check`, `check-prompt-budget.sh --quiet`, the scaffold and pipeline bats files green at every *fix* commit and at the final head; each *red* commit fails only its own new cases (verified by `red-test-check.sh` / `red-green-npm.sh` on the landed pair); CI mirror from the landed head.
- [ ] Review All good, audit APPROVED; PR merged only when every check run on the exact final PR head is completed and the six required checks — Template Protection, Validate Framework Files, Lint Markdown, Lint YAML, Shell Tests, Cross-Platform Compatibility — are `success` (other jobs may be `skipped` only when their path filter excludes this PR's paths; the list is recorded in `e2e.md`); Bridgebuilder non-degraded with the verdict's head sha recorded and invalidated by any later commit; fixes landed after a Bridgebuilder round go back through the lead's review and audit addenda before the merge; the merged commit's own check runs are recorded afterwards (a red there → a follow-up fix PR, or a revert of the merge commit with dist/checksums/REPO-MAP regenerated in the revert if `main` is broken); CI mirror and secret scan recorded; record + archive, JACKED_OUT.

### Technical Tasks

<!-- → **[G-n]** names the PRD goal; ⇐ names the blocking task(s) (edge-or-none); every line ends with · kind: … -->

- [ ] Task 1.0: Contract commit (lead, System Zone) — `core/types.ts`: `ReviewignoreSource`, `SelectionConfig` (the `Pick` + `reviewignoreBaseSha?` + `reviewignoreBase?: { patterns; source }`) and `TruncationResult.reviewignoreSource?`; `ports/index.ts` re-exports `FileContentResult`; `truncation.ts` exports `readBaseReviewignore` with today's `BaseRead` shape (Task 1.2 reshapes it to `absent | unknown_commit | other`), `BaseRead`, `parseReviewignoreLines`, `REVIEWIGNORE_MAX_BYTES`, and takes `SelectionConfig`; `paged-fetch.ts` imports both types from `./types.js`, its local aliases and the intersection casts deleted (behaviour unchanged); pre-dispatch inventory: grep `PATTERN_SUFFIX`, `patternSuffix`, `exclusionPattern`, `[pattern:` and the casts across the whole skill incl. `adapters/`, `SKILL.md`, `dist/` and record the hits in `a2a/sprint-280/contract.md`; confirm `isPullRequestContext` is exported for B; `npm test` green; dist + manifests → **[G-4]** · kind: judgment
- [ ] Task 1.1: Scaffold legacy-guard check and fix mode (A, System Zone) — `scaffold-post-merge-workflow.sh`: in the existing-file branch, `legacy_release_guard_check` per sdd.md § 5.1 (one awk pass, no yq: block from the `simple-release:` key to the first non-blank non-comment line at indentation ≤ J; child indentation read from the file; block scalars tracked; exactly one single-line `if:` candidate or nothing; normalisation strips `${{ }}`, a trailing comment, whitespace runs and one pair of quotes; WARN text per sdd.md § 4; `LOA_SCAFFOLD_FIX_RELEASE_GUARD=1` rewrites exactly the matched physical line through the safe-write recipe — symlink refused, re-read before write, temp file in the same directory, mode preserved, `mv -f` — prints the notice, refuses with a WARN otherwise; return 0 in every branch; the library header documents the flag); bats MWS-T13 … red first incl. every negative fixture of prd.md FR-1 (step-level, second job, comment, multi-line, `run: |` body, two `if:` lines, no job, digit job id, 4-space indent, `${{ }}` wrapper, symlink) under `set -euo pipefail` with a yq-less PATH; CHANGELOG line returned as text (bd-akkgq); fix-mode failure path: target not writable → WARN naming the failure, unchanged, return 0; CRLF fixture: a `\r\n` workflow is detected and the rewritten line keeps `\r\n`; inline-comment fixture → **[G-2]** · kind: mechanical
- [ ] Task 1.2: Base `.reviewignore` through the contents API (B, System Zone) — `truncation.ts`: `readBaseReviewignore` classifies `absent` / `unknown_commit` (by `git cat-file -e` exit status, `LC_ALL=C`) / `other` and `resolveBasePatterns(config)` serves both read sites; `paged-fetch.ts`: `resolveBaseReviewignore(git, owner, repo, pin.base_sha, repoRoot, files, cache)` per sdd.md § 5.2 (`ok` → `base`; `absent` → `none`; `unknown_commit` → one `getFileContent(".reviewignore", base_sha, REVIEWIGNORE_MAX_BYTES)` against the target `owner/repo`: text → `base` + INFO line; 404 → access probe on the first modified/removed/renamed listed file at the base with `maxBytes` 1 → readable = `none`, else undefined; other failures / non-provider throws → undefined; `other` → undefined; cached per base sha incl. failures (`Map.has`); outside `max_content_fetches` / `fetch_missing_patches`); the selection receives the one `reviewignoreBase` object; `paged-fetch-reviewignore.test.ts` red first (fixture adapter over the full FR-2 matrix incl. the probe cases, the failed-resolution cache and a timeout-shaped error; a `deps.readBaseReviewignore` seam forces the local class); the `text` result is complete by construction (the adapter returns `too_large` above the bound and rejects a `size` that disagrees with the decoded bytes — pinned by the `size`-mismatch case); the cache lives for the run (one repository per run), a transient failure is cached as failed for the run (bounded, fail closed — no retry); diagnostic counts asserted per attempt alongside call counts (INFO once per base-sha resolution; failed-read WARN once per file per attempt); `max_content_fetches: 0` and `fetch_missing_patches: false` → the base read still happens (it sits outside both); `resources/exclusions-and-coverage.md`; CHANGELOG line returned as text (bd-9tt4b) → **[G-3]** ⇐ 1.0 · kind: mechanical
- [ ] Task 1.3: Contract tidy-up (B, System Zone) — `paged-fetch.ts` / `truncation.ts`: delete `patternSuffix`, `PATTERN_SUFFIX`, `exclusionPattern`; readers use `ex.pattern`; one bounded `[bridgebuilder] WARN:` on a failed content read (per file per attempt); tests: coverage fixtures on `pattern`, literal ` [pattern: x]` is plain text, a grep pin over the runtime sources only (`resources/core/**`, `resources/*.ts`; excluding `__tests__/`, docs and `dist/`) for `[pattern:` and the intersection casts, failed-read WARN incl. an escaped newline in a filename; CHANGELOG lines returned as text (bd-gyrgq) → **[G-4]** ⇐ 1.2 · kind: mechanical
- [ ] Task 1.3b: FR-5 head-side validation deferral (B, System Zone, Could Have) — `config.ts` `resolveConfig` (which receives `env`; `isPullRequestContext` is exported) learns the mode, validates the head YAML *before* the trusted replacement, downgrades an invalid head `protected_paths` / `max_content_fetches` / `exclude_patterns` shape to a WARN with the key left unset and recorded in `provenance.deferredScopeKeys`; the trusted scope keys then *replace* (not merge) the head values in `applyTrustedReviewScope` — they are flat lists, booleans and integers; `exclude_patterns` is recomposed as defaults + trusted + CLI — which clears the list; a config-time assertion exported from `config.ts` refuses a configuration still carrying deferred keys and the lead wires it with the applier in `main.ts`; a test pins the `main.ts` call order; tests: the FR-5 matrix (three keys × `--pr` / `GITHUB_EVENT_NAME` / `GITHUB_BASE_REF`, no-source default, invalid trusted error, local throws, deferral set/cleared, the assertion, permissive-head vs restrictive-trusted and mixed-key composition). Deferral trigger: if the FR-5 patch pair fails the gates after one return, or is not landed when Task 1.4 starts, FR-5 is deferred to a bead and G-4 excludes it → **[G-4]** ⇐ 1.3 · kind: mechanical
- [ ] Task 1.4: Sprint close (lead) — land A (1.1) and B (1.2, 1.3, 1.3b if accepted) as red commit then fix commit each, under the marker with dist, checksums and REPO-MAP regenerated; red-first verified (`red-test-check.sh` for bats, `red-green-npm.sh` for the skill); the implementers' CHANGELOG texts inserted by the lead; the implementers' judgment calls (listed in their reports, decided by the lead) recorded as DEC rows; `main.ts` wiring of the FR-5 assertion if 1.3b landed; `reviewer.md` → **[G-1]** ⇐ 1.1, 1.3 · kind: judgment
- [ ] Task 1.5: Review and audit (lead) — `/review-sprint` with ≤ 3 dissent runs (`adversarial-review.sh --type review`, code-only diffs), `engineer-feedback.md` (C-11 grammar, verdict-derive consistent); `/audit-sprint` → `auditor-sprint-feedback.md`, COMPLETED, ledger sprint 280 completed, beads closed with evidence → **[G-1]** ⇐ 1.4 · kind: judgment
- [ ] Task 1.6: Ship (lead) — secret scan; PR from `feature/cycle-136-bridgebuilder-followups` (title names the behaviour changes; body lists beads, DEC rows, gates per head sha); before the first Bridgebuilder round confirm the review's exclusions come from `--exclude` (additive) and the base branch's `.reviewignore` / trusted config, never from the PR head; Bridgebuilder round(s) ≤ 2 with the generated and planning files excluded, triage comment per round, fixes red-first and back through the review and audit addenda; the G-3 live probe (below) before the merge; admin merge only when every check run on the exact final head is completed and the six required checks are `success`; `record-branch.sh --cycle 136 --prev origin/record/cycle-135-review-coverage-followups`; archive PR (housekeeping) merged; the merged commit's check runs recorded; JACKED_OUT with the completion block → **[G-5]** ⇐ 1.5 · kind: judgment
- [ ] Task 1.E2E: Sprint 1 goal validation — G-1 (three beads closed with commit and test), G-2 (the scaffold matrix), G-3 (the shallow-checkout fixtures; plus the live probe: from a `git clone --depth 1 -b feature/cycle-136-bridgebuilder-followups` of the open PR head, a node script against the built dist calls `fetchPRFilesTwoPass` with the real `gh` adapter on the cycle's own PR — no model call — and records `coverage.reviewignore_source` (`base` when the base branch has a `.reviewignore`, else `none` via the probe-confirmed 404), `degraded: false` and the INFO line), G-4 (`tsc`, no casts, re-export, suffix gone, WARN; FR-5 if landed), G-5 (every check run green on the final PR head and recorded on the merged head, non-degraded Bridgebuilder verdict with its sha, one implementation PR, record, archive, spend ≤ USD 20) → `a2a/sprint-280/e2e.md` → **[G-5]** ⇐ 1.6 · kind: judgment

### Patch contract (per-implementer path allowlist)

| Implementer | May change | Must not touch |
|---|---|---|
| A | `.claude/scripts/lib/scaffold-post-merge-workflow.sh`, `tests/unit/mount-workflow-scaffold.bats` (fixtures as heredocs inside it) | `CHANGELOG.md` (text returned in the report), the mount scripts' call sites, `post-merge.yml`, anything under `.claude/skills/` |
| B | `resources/core/paged-fetch.ts`, `resources/core/truncation.ts`, `resources/config.ts` (Task 1.3b only), `resources/__tests__/paged-fetch*.test.ts`, `resources/__tests__/truncation.test.ts`, `resources/__tests__/loa-detection.test.ts`, `resources/exclusions-and-coverage.md` | `CHANGELOG.md` (text returned in the report), `core/types.ts` and `ports/index.ts` (the lead's Task 1.0), `main.ts` (the lead wires the FR-5 assertion), `adapters/github-cli.ts`, `SKILL.md` (prompt budget), `dist/` |

A patch outside its allowlist is returned, not landed. Implementers make no live model or GitHub calls and never commit, push or stash in their worktrees.

### Seams Under Test

| Seam | Catches | Misses | Prior art |
|------|---------|--------|-----------|
| `scaffold_post_merge_workflow` over fixture workflows (legacy / allowlist / customised / step-level / second job / comment / multi-line / `run: |` body / two `if:` / no job / digit job id / 4-space indent / `${{ }}` / symlink) under `set -euo pipefail`, yq-less PATH | a stale guard left silent; a customised guard overwritten; a step-level, scalar-body or foreign `if:` mistaken for the job's; an unsafe write | the mount CLI's own flag surface (none changed) | `mount-workflow-scaffold.bats` MWS-T1 … T12 |
| `fetchPRFilesTwoPass` with a fixture adapter whose `getFileContent` serves `.reviewignore` at the base sha (text / 404 + probe outcomes / each failure class / absent method), with the local read forced to `ok`, `absent`, `unknown_commit` or `other` | a degrade on a shallow checkout; the PR's own copy applied; a 404 that is an authorization gap read as absence; an API call on a local answer; a repeated call across attempts | the real `gh` 404 shape (pinned from the adapter's error mapping, not a live call) | `paged-fetch-contents.test.ts`, `paged-fetch-coverage.test.ts` |
| `truncateFiles` with `reviewignoreBase` set | the selection ignoring the resolved patterns; the provenance mislabelled | the interaction with `protected_paths` precedence on the same path (covered by the existing partition tests, not re-tested here) | `truncation.test.ts` provenance block |
| `resolveConfig` in PR mode vs local with an invalid head scope key | the head failing its own review; local silently downgraded; a deferred key consumed before the trusted replacement | a real GitHub event payload (the three detection routes are simulated through `env`) | `truncation.test.ts` trusted-scope block |
| the coverage reader without the suffix grammar | a `stats` string parsed for a pattern it no longer carries | downstream readers outside this repository | `paged-fetch-coverage.test.ts:67-91` |

### Dependencies

- None external beyond the host toolchain: Node 22.22, tsx and TypeScript 5.9 in the skill, bats 1.13 through the npx cache, jq 1.7, `yq` v4 (optional for the scaffold; the tests scrub PATH for the fallback case), `gh` 2.x authenticated for the ship steps.
- Internal: Task 1.0 → 1.2 (A's Task 1.1 touches only the shell library and its bats file and does not depend on the contract); 1.2 → 1.3 → 1.3b (same files, implementer B); 1.4 after 1.1 and 1.3 (1.3b if landed); 1.5 after 1.4; 1.6 after 1.5; 1.E2E after 1.6.

### Security Considerations

- The only new network read is `.reviewignore` at the PR base sha through the existing allowlisted contents shape; a 404 is `none` (review everything); any other failure keeps the fail-closed `base_unavailable` degrade; the PR head's copy is never applied.
- The scaffold rewrites nothing unless the operator sets the flag, and then only an `if:` line whose text it recognises exactly; a customised guard is left alone with a WARN.
- The PR-mode validation downgrade never installs the head's invalid value: the key is left unset so the trusted value (or the default) governs; local mode is unchanged.
- System Zone writes under the bounded marker with manifests regenerated; secret scan before every push; implementers make no live calls.

### Risks & Mitigation

- Risk: the awk fallback matches a step-level `if:` → the scan is scoped to the `simple-release:` block and stops at the next job key; a fixture with a step-level `if:` pins it.
- Risk: the real `gh` 404 surfaces differently from the fixture → the test uses the adapter's own `GitProviderError` shape (`httpStatus` 404) and the adapter's mapping is read, not assumed; a non-404 failure falls back to today's path, so a mis-shape degrades rather than hides.
- Risk: a 404 is an authorization gap, not an absence → the access probe on a base-existing listed file; no probe target → fail closed (DEC-1083).
- Risk: dropping the suffix breaks an external `stats` reader → CHANGELOG names the removal; the structured field has shipped since cycle-135.
- Risk: B's tasks collide → sequential in one worktree; 1.3 lands only after 1.2, 1.3b after 1.3.
- Rollback: revert the single merge commit and regenerate `dist/`, `checksums.json` and REPO-MAP in the revert commit; consumers are unaffected until the next release (none this cycle).
- Risk: the Bridgebuilder round degrades → prefix excludes for generated and planning files; the PR is code, tests and docs well under the file cap.

### Success Metrics

- G-1: 3 of 3 beads closed with commit and test.
- G-2: the scaffold matrix green (legacy WARN, allowlist silent, customised silent, flag fixes one line, fallback without yq).
- G-3: the shallow-checkout fixtures green with `reviewignore_source: base` and no degrade; the fail-closed cases pinned.
- G-4: `tsc` clean, no intersection casts, `FileContentResult` re-exported, suffix gone, failed-read WARN (FR-5 counted only if Task 1.3b landed; otherwise recorded as deferred with its bead).
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

### Flatline sprint review dispositions (1.2 → 1.3)

Cross-scoring degraded (KF-041 shape): 0 HIGH_CONSENSUS, 3 skeptic blockers, 32 medium items; every item read.

| Item | Disposition |
|---|---|
| SKP-003 — `text → base` without a completeness requirement | **Integrated (Task 1.2):** the adapter returns `too_large` above the bound and rejects a `size` that disagrees with the decoded bytes, so a `text` result is complete by construction; the `size`-mismatch case pins it. |
| SKP-006 — FR-5 validation order / nested merge | **Integrated (Task 1.3b):** the head YAML is validated first (invalid keys unset + deferred), then the trusted scope keys *replace* the head values (flat lists/booleans/integers; `exclude_patterns` recomposed defaults + trusted + CLI). |
| SKP-002, gpt IMP-008, opus IMP-003/004 — yq ↔ physical line mapping; yq shims | **Superseded:** the SDD review dropped `yq` (DEC-1078); one awk pass detects and rewrites the same physical line. CRLF and inline-comment fixtures added (Task 1.1). |
| gpt IMP-001, opus IMP-001 — "green at every landed commit" vs red commits | **Integrated (ACs):** green at every fix commit and the final head; red commits fail only their own new cases. |
| gpt IMP-002, opus IMP-002 — FR-5 optional vs mandatory | **Integrated:** Task 1.3b with an explicit deferral trigger; G-4 excludes FR-5 unless landed. |
| gpt IMP-003 — return path from Bridgebuilder fixes to review/audit | **Integrated (ACs, Task 1.6):** fixes go back through the lead's review and audit addenda before the merge. |
| gpt IMP-004/005/006, opus IMP-007 — required checks by name; skipped jobs; pre- vs post-merge; verdict bound to the final head | **Integrated (ACs, Task 1.6, 1.E2E).** |
| gpt IMP-007, opus IMP-008 — bounded-loop exits | **Integrated (header Execution).** |
| gpt IMP-009/010 — diagnostic counts; cache lifetime and transient failures | **Integrated (Task 1.2):** once per base-sha resolution / per file per attempt; the cache lives for the run, failures cached (no retry). |
| gpt IMP-011, opus IMP-006 — scoped grep pins | **Integrated (Task 1.3).** |
| gpt IMP-012 — one PR vs the archive PR | **Integrated (header Execution).** |
| opus IMP-005 — drop the 1.0 → 1.1 edge | **Integrated (Task 1.1, Dependencies).** |
| opus IMP-009 — Task 1.0 vs 1.2 on `truncation.ts` | **Integrated (Task 1.0):** the contract exports today's shape; 1.2 reshapes. |
| opus IMP-010 — `isPullRequestContext` exported | **Confirmed (Task 1.3b).** |
| opus IMP-011 — pre-dispatch inventory | **Integrated (Task 1.0).** |
| opus IMP-012 — where the fixtures live | **Integrated (Deliverables, Patch contract): heredocs in the bats file.** |
| opus IMP-013 — CHANGELOG hunk collision | **Integrated:** implementers return text; the lead inserts; CHANGELOG removed from both allowlists. |
| opus IMP-014 — cap 0 / switch off behaviour | **Integrated (Task 1.2): the read still happens.** |
| opus IMP-015 — task kinds vs DEC rows | **Integrated (Task 1.4): implementers list judgment calls; the lead decides and records.** |
| opus IMP-016 — fix-mode failure path; CRLF | **Integrated (Task 1.1).** |
| opus IMP-017 — post-merge dogfood | **Integrated as a pre-merge live probe (Task 1.E2E):** a depth-1 clone of the PR head runs the built fetch path against the open PR with the real adapter, no model call. |
| opus IMP-018 — rollback note | **Integrated (Risks).** |
| opus IMP-019 — Seams "Misses" cells | **Integrated (Seams table).** |
| opus IMP-020 — exclusions' provenance before the Bridgebuilder round | **Integrated (Task 1.6).** |

> Sources: `grimoires/loa/a2a/flatline/cycle-136-sprint-review.json`; decision rows DEC-1085 … DEC-1088 (sprint-planning)
