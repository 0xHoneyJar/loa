# Sprint Plan: Review-coverage follow-ups (cycle-135)

**Version:** 1.1
**Date:** 2026-10-26
**Author:** Sprint Planner Agent (Claude Fable 5.1, unattended)
**PRD Reference:** `grimoires/loa/prd.md` (1.2, FR-1 … FR-6, G-1 … G-5)
**SDD Reference:** `grimoires/loa/sdd.md` (1.1, C-1 … C-5, D-1.1 … D-2.2, D-1.1a … D-1.5a)
**Flatline:** `grimoires/loa/a2a/flatline/cycle-135-sprint-review.json` (2/2 voices, cross-scoring degraded — KF-041 shape; 4 skeptic blockers and 38 medium items, every one read; dispositions in the Appendix)
**Ledger:** cycle `cycle-135-review-coverage-followups`, sprint global 279 (local sprint-1)
**Execution:** `/run sprint-plan --no-consolidate` (one PR for the one sprint, DEC-0960); Opus 5.5 implementers A, B, C in linked worktrees returning `git diff --cached` patches (test patch first, then fix patch); the lead lands, reviews, audits and ships; implementers make no live model calls and never commit, push or stash.
**Task kinds:** every task carries `kind: mechanical | judgment` (DEC-0144); the lead's tasks are `judgment`; no `operator` task exists — the operator's instruction of 2026-10-26 ("yes approve and then also work on the other things also") authorises the cycle; the operator confirms the proposed rows at the close.
**Spend:** USD 40 cap in the meter's unit (DEC-1018, DEC-0999 shape): Flatline reviews, dissent runs and the Bridgebuilder round on subscription routes; real charges ≈ 0; stop the Bridgebuilder when the remaining budget is under USD 8.
**System Zone authorization:** DEC-0824 carries over — `.claude/skills/bridgebuilder-review/**`, `.claude/scripts/classify-pr-type.sh`, `.claude/scripts/classify-merge-pr.sh`, `.github/workflows/post-merge.yml` under the bounded zone marker (scope framework, reason, expiry ≤ 2 h, re-issued per write session), `checksums.json`, REPO-MAP and the Bridgebuilder `dist/` regenerated in every landing commit.

---

## Executive Summary

One sprint closes the five follow-ups of the 2026-10-26 micro-sprints: segment-anchored exclusion matching with one matcher on every Node version (FR-1), protected paths that wildcard exclusions cannot remove (FR-2), bounded content fetch for added files without a patch (FR-3), a `housekeeping` classifier value that both prepare jobs skip (FR-4), CPU-time test guardrails (FR-5), and the ship (FR-6). Three implementers work in parallel on disjoint files from a lead-authored contract commit; the lead lands in the order A → B → C, runs review and audit with at most three dissent runs, and ships one PR with a Bridgebuilder round, a record stage and the archive. No release.

> Sources: prd.md § Executive Summary; sdd.md § 8

---

## Sprint Overview

| Sprint | Global | Goal | Implementers |
|---|---|---|---|
| 1 | 279 | The five follow-ups fixed, tested first, shipped | A (matcher, protected paths), B (content fetch, coverage rendering, guardrails), C (classifier, workflow), lead |

> Sources: sdd.md § 8 (Development Phases)

---

## Sprint 1: The five follow-ups and the ship (global 279)

### Sprint Goal

Every in-scope bead closed with a red-first test and a commit; the Bridgebuilder's exclusion matching safe and predictable, protected paths kept and named, patch-less added files reviewed, housekeeping merges preparing nothing, the test suite deterministic under load; one PR merged with a non-degraded Bridgebuilder verdict, recorded and archived.

### Deliverables

- [ ] Contract commit (lead): `types.ts` fields `TruncationResult.protectedKept`, `CoverageRecord.protected_kept`, `reviewed[].source`; dist and manifests regenerated (D-2.1)
- [ ] A: `truncation.ts` matcher (C-1), protected paths and config (C-2 producer side), tests, SKILL.md text
- [ ] B: `paged-fetch.ts` content fetch (C-3), coverage copy and rendering of `protectedKept`, `github-cli.ts` + `git-provider.ts` method and allowlist shape, CPU-time guardrails (C-5), tests
- [ ] C: `classify-pr-type.sh` `housekeeping`, `classify-merge-pr.sh` comment, `post-merge.yml` guard, bats in both directions, orchestrator refusal pinned (C-4)
- [ ] Lead: landing commits (red then fix per implementer), CHANGELOG `[Unreleased]` entries, DEC rows from the implementers' judgment calls, review and audit, PR, Bridgebuilder round, merge, record, archive

### Acceptance Criteria

- [ ] FR-1 … FR-5 acceptance criteria met as written in prd.md 1.2, each by a test that was red first (red commit SHA in `reviewer.md`; FR-5's red is the report-only negative control); FR-6 by the third bullet below
- [ ] `npm test` (skill) and `tsc --noEmit` green; `post-merge-classifier.bats`, `classify-merge-pr.bats`, `post-merge-workflow-guards.bats`, `post-merge-orchestrator-type.bats`, `post-merge-publication.bats` green; `bash -n`; `yq` parse and `actionlint` (when installed) of the workflow; dist fresh; checksums, REPO-MAP and manifest-paths pass; the local CI mirror green except the named host-local reds (Task 1.7) — any other red is fixed, not absorbed
- [ ] Review and audit APPROVED with every dissent payload dispositioned; the Bridgebuilder's findings triaged on the PR; every check run green on the merged head
- [ ] G-1 … G-5 evidenced in `a2a/sprint-279/e2e.md`

### Technical Tasks

<!-- → **[G-n]** names the PRD goal; ⇐ names the blocking task(s) (edge-or-none); every line ends with · kind: … -->

- [x] Task 1.0: Contract commit and Q-1 probe (lead, System Zone) — `resources/core/types.ts`: `TruncationResult.protectedKept?`, `CoverageRecord.protected_kept?`, `CoverageRecord.reviewed[].source?: "contents"`, `CoverageRecord.omitted[].pattern?`, `CoverageRecord.omitted[].fetch?`, `CoverageRecord.reviewignore_source?`, `CoverageRecord.reviewignore_changed_in_pr?`, `BridgebuilderConfig.protectedPaths`, `.fetchMissingPatches`, `.maxContentFetches` (sdd.md § 3); `npm run build`, `check-bb-dist-fresh.sh --check`, checksums and REPO-MAP regenerated under the marker; one read-only `gh api /repos/0xHoneyJar/loa/contents/README.md?ref=<main sha>` probe with the envelope shape (fields, `encoding`, `size`) recorded in `a2a/sprint-279/contract.md`; worktrees `../loa-wt-c135-{a,b,c}` created from this commit (D-2.1) → **[G-1]** ⇐ none · kind: judgment
- [x] Task 1.1: Exclusion matcher semantics (A) — `truncation.ts`: `isWildcardPattern`, `segmentMatch` (gitignore-like: no `/` → whole segment at any depth, `/` → root-anchored path or subtree; one trailing `/` stripped), `matchesExcludePattern(filename, patterns)` = non-wildcard → `segmentMatch`; wildcard → `dotSegmentGlobMatch` only (`path.matchesGlob` never called, `hasNativeGlob` removed), with one-level `{a,b}` and `[..]` / `[!..]` added to the translation; pattern normalisation at load (trim, strip `./` or `/`, reject `!` lines and constructs outside the grammar — extglob, nested braces, backslash escapes — with one WARN each; rejected patterns match nothing); the `.reviewignore` `/` → `**` conversion at `:395` removed; `simplifiedGlobMatch` deleted after a grep for importers and for callers of `matchesExcludePattern` outside A's allowlist (reported before the patch); doc comment states the grammar; tests in `loa-detection.test.ts`: `util.loa-version.json.ts`, `x/.loa-version.json.bak`, `MYPROCESS.md`, `PROCESS.md.old` not excluded by the defaults; `docs/PROCESS.md`, `BUTTERFREEZONE.md` excluded; `a/b` vs `a/b/c` and `x/a/b`; `/README.md`, `./x`, trailing `/`, whitespace; `**/*.{json,md}` and `**/*.[jt]s` against dot-led paths; `+(a|b).md` and `a\*.md` rejected with a WARN; a guard test that deletes `path.matchesGlob` for its duration and asserts every case unchanged; the skipped single-`*` case un-skipped; CHANGELOG line for the lead (bd-ow72o) (C-1, D-1.1, D-1.1a) → **[G-2]** ⇐ Task 1.0 · kind: mechanical
- [x] Task 1.2: Protected paths and `.reviewignore` provenance (A) — `truncation.ts`: `export const DEFAULT_PROTECTED_PATHS` (sdd.md C-2 list incl. `.github/CODEOWNERS`, `.reviewignore`), `partitionUserExclusions(files, userPatterns, protectedPatterns)` order-independent (any non-wildcard match excludes; a protected file with only wildcard matches is kept, first wildcard recorded), applied at the three user-pattern call expressions (self-review branch, non-Loa branch, fail-closed path — named by function in the report, not line), not at `applyLoaTierExclusion`, whose omissions gain the matching default `pattern`; protected-kept files first in the selection order; `truncateFiles` takes `protectedPaths` from its config object and returns `protectedKept`; `parseReviewignoreFile(repoRoot, { baseSha? })` reads `git show <baseSha>:.reviewignore` when a base sha is given (same validation; failure → `none` + WARN) and the checkout file otherwise, returning `{ patterns, source }`; `config.ts`: `protected_paths` (validated: non-empty strings, `./` or `/` stripped, no `..`, else a config error naming the entry; set → replaces the default; `[]` disables), `fetch_missing_patches` (default true), `max_content_fetches` (default 20) parsed like their neighbours; `SKILL.md` exclusion-patterns and protected-paths headings: the keys, the default list, the wildcard/non-wildcard rule, the grammar and normalisation of Task 1.1, the base-ref provenance; tests (`truncation.test.ts`): `**/*.yml` keeps `.github/workflows/ci.yml` with `protectedKept = [{file, pattern}]`; exact `.github/workflows/ci.yml` and the `.reviewignore` line `.github/workflows/` exclude it in both pattern orders and the file is absent from `protectedKept`; protected first under a file cap of 1; `[]` disables; a custom list protects only its entries; validation errors name the entry; the Loa tier still strips `.claude/settings.json` without self-review; base-sha read vs checkout read; CHANGELOG line for the lead (bd-i4fyw) (C-2, D-1.2, D-1.2a) → **[G-3]** ⇐ Task 1.1 · kind: judgment
- [x] Task 1.3: Content fetch for patch-less added files (B) — `ports/git-provider.ts`: `FileContentResult` and the optional `getFileContent?(owner, repo, path, ref, maxBytes)` after an inventory of every in-tree `IGitProvider` implementation and typed test double (reported; absent method → no fetch); `adapters/github-cli.ts`: `gh api /repos/<o>/<r>/contents/<path>?ref=<sha>` (default JSON media type, no headers), output as bytes with `maxBuffer = ceil(maxBytes × 4/3) + 4096` (overflow → `too_large`), strict envelope validation (`type: file`, `encoding: base64` — `none` → `too_large`; integer `size` > `maxBytes` → `too_large`; string `content`), base64 → bytes (malformed → error), binary test on the bytes (NUL in the first 8 KiB or fatal UTF-8 failure), string only afterwards; `assertAllowedArgs` admits exactly that shape (owner/repo `[A-Za-z0-9_.-]+`; path validated before encoding — no empty, `.` or `..` segment, no leading `/`, no `?`, `#` or control character — percent-encoded per segment and the canonical decoded request re-checked; ref `^[0-9a-f]{40}$`; no headers); `paged-fetch.ts` pass 1: after the Loa-tier and user exclusions (with protection) over the metadata, eligible = surviving `status === "added" && patch == null && additions > 0`, listing order, at most `maxContentFetches` within a 120 s deadline, `getFileContent(baseOwner, baseRepo, path, pin.head_sha, remainingBudget)` with the synthesized patch's encoded bytes (header, `+` prefixes, the `\\ No newline at end of file` marker when needed, CRLF kept, `N` = lines) charged against the aggregate `maxDiffBytes` — over budget → `too_large`, never truncated; `source: "contents"`, pre-retained for pass 2 and discarded on a head-pin restart; binary / too_large / error / skipped_cap / deadline → metadata unchanged with `omitted[].fetch` set; `fetchMissingPatches === false` skips the step; tests: provider double end to end (listing without a patch → content → selection → pass 2 → coverage) reviewed with `source: "contents"` and not degraded; binary, too large (size and `encoding: none`), malformed envelope / base64, provider error → `no_patch` with the outcome; an excluded patch-less file never fetched (counting double); cap and deadline → `skipped_cap` / `deadline`; several files competing for the budget incl. overhead; the exact ref passed equals the listing head sha; the restart path discards synthesized patches; `fetch_missing_patches: false` → no provider call; modified-without-patch → `no_patch`; synthesized matrix (missing final newline, CRLF, multibyte UTF-8, content starting with diff markers, a raw text file shaped like an envelope reviewed as text); allowlist accepts the shape and rejects `..` plain and encoded, empty and `.` segments, leading `/`, `?`/`#`/control characters, encoded separators, option-like inputs, a foreign query, a short or non-hex ref, any header; CHANGELOG line for the lead (bd-w5pd9) (C-3, D-1.3, D-1.3a, D-1.3b) → **[G-4]** ⇐ Task 1.0 · kind: judgment
- [x] Task 1.4: Coverage record and rendering (B) — `paged-fetch.ts`: `coverage.protected_kept = sel.protectedKept ?? []`, `coverage.reviewignore_source` / `reviewignore_changed_in_pr` from the base-ref read and the PR's file list, `omitted[].pattern` and `omitted[].fetch` carried through; the PR summary renders "Protected paths kept (n)" with `file — kept despite <pattern>` and `then omitted (<reason>)` when a budget later cut the file, `(source: contents)` on synthesized entries, the excluding pattern on Loa-tier and user-pattern omissions, the `fetch:` outcome on patch-less omissions, and one `.reviewignore: <source>` line with `(changed in this PR)`; every name and pattern through `safePath` escaping with a hostile-string fixture (Markdown delimiters, HTML, newlines); SKILL.md coverage heading documents the new fields and markers; tests on the record and the rendered text (`paged-fetch.test.ts`) (C-2 consumer side, § 4) → **[G-3]** ⇐ Task 1.3 · kind: mechanical
- [x] Task 1.5: CPU-time guardrails (B) — `progressive-truncation.test.ts`: both guardrails take the minimum of three `process.cpuUsage()` user + system samples around the synchronous measured call; thresholds unchanged; message names CPU time; comment names bd-oglcu and the GC/JIT caveat; red-first for this test-infrastructure change is the report-only negative control: an O(n²) loop over the 100-file list must fail the 100 ms bound under the new measurement, figures in the report; three consecutive green full `npm test` runs with two concurrent `npm test` runs in the other worktrees as the load condition, recorded (C-5, D-1.5, D-1.5a) → **[G-5]** ⇐ Task 1.0 · kind: mechanical
- [x] Task 1.6: Housekeeping classifier value and workflow guard (C, System Zone) — `classify-pr-type.sh`: rule 1a echoes `housekeeping`, header grammar `<cycle|bugfix|housekeeping|other>`, rule list 1a updated; `classify-merge-pr.sh`: comment only (the no-PR guard still forces `other`); `post-merge.yml`: `simple-release` `if:` becomes the allowlist `(needs.classify.outputs.pr_type == 'bugfix' || needs.classify.outputs.pr_type == 'other') && needs.classify.outputs.pr_number != ''` with a comment naming bd-nr5i6, `full-pipeline` unchanged; every place that enumerates the values (classifier header, wrapper usage, workflow comments, the notify template) updated; Q-3 as a gate: enumerate every in-tree consumer of `pr_type` / `PM_PR_TYPE` in the report — one that would misroute `housekeeping` is a blocker returned to the lead before the fix patch; tests: PCT-T28 … T32, T38 → `housekeeping`, T35 → `other`, others unchanged; `classify-merge-pr.bats`: housekeeping subject with a PR → `pr_type=housekeeping`, no-PR push → `other`; `post-merge-workflow-guards.bats`: the guard text pinned and a shell mirror of both expressions evaluated over {cycle, bugfix, other, housekeeping, unknown, empty} × {PR number, none} — both prepare jobs skip `housekeeping`, unknown and empty, `simple-release` runs for `bugfix`/`other` with a PR number, `full-pipeline` for `cycle` only; `yq` parse and `actionlint` (when installed) of the workflow; new `tests/unit/post-merge-orchestrator-type.bats` pins `post-merge-orchestrator.sh --generate --type housekeeping` → exit 1 "Invalid --type"; CHANGELOG line for the lead (bd-nr5i6) (C-4, D-1.4, D-1.4a) → **[G-3]** ⇐ Task 1.0 · kind: judgment
- [x] Task 1.7: Sprint close (lead) — land A (1.1, 1.2) → B (1.3 … 1.5) → C (1.6) as red commit then fix commit each, under the marker with dist, checksums and REPO-MAP regenerated; red-first verified (`red-test-check.sh` with `bats` on PATH for C; the detached-worktree equivalent for the skill's `npm test`, DEC-1007 shape); suites and the local CI mirror (accepted host-local reds only by name: the three KF-034 cases of `post-merge-publication.bats`, the gitignored vision-021 template-safety case, the two adapter pytest cases that pass with `CLAUDE_HEADLESS_BIN` unset); after A and B land, the lead's integration check: a config with `**/*.yml` → `truncateFiles` → the coverage record → the rendered "Protected paths kept (1)" line; fix rounds: the lead fast-forwards the implementer's worktree to the landed head before each round (wording/test rounds exempt from red-first; behaviour rounds follow it; ≤ 3 rounds per implementer); SKILL.md hunks resolved by heading when B lands after A; CHANGELOG `[Unreleased]` `### Fixed` / `### Changed` entries; DEC rows from the implementers' judgment calls; `reviewer.md` with AC verification → **[G-1]** ⇐ Task 1.1, Task 1.2, Task 1.3, Task 1.4, Task 1.5, Task 1.6 · kind: judgment
- [x] Task 1.8: Review and audit (lead) — `/review-sprint` with ≤ 3 dissent runs (`adversarial-review.sh --type review`, code-only diffs per implementer), `engineer-feedback.md` (C-11 bullet grammar; `verdict-derive` consistent); `/audit-sprint` with the audit envelope (`--type audit`), `auditor-sprint-feedback.md`, COMPLETED marker; fix rounds back to the implementers as needed → **[G-1]** ⇐ Task 1.7 · kind: judgment
- [ ] Task 1.9: Ship (lead) — after review and audit APPROVED: PR from `feature/cycle-135-review-coverage` (code, tests, docs, CHANGELOG, decisions, ledger, manifests, dist), secret scan first; Bridgebuilder round (`BRIDGEBUILDER_MODEL=codex-headless`, prefix excludes for `dist/`, `checksums.json`, REPO-MAP, `decisions.yaml`, `ledger.json`; ≤ 2 rounds; stop under USD 8 remaining); triage comment; admin merge when every check run is green — the operator's confirmation of the proposed rows is post-ship, as every cycle, and does not gate the merge; if the second Bridgebuilder round or the budget stop is reached without a non-degraded consensus verdict the ship proceeds with the degraded record documented in the triage comment, the e2e and a DEC row; the cycle merge classifies `cycle` and its candidate stays unpublished; the Bridgebuilder that reviews the PR runs from the lead's checkout, i.e. the branch's `dist/`, and its "Protected paths kept" section is recorded in the e2e; `record-branch.sh --cycle 135 --prev origin/record/cycle-134-post-ship-fixes --stage "stage 1"`; `archive-cycle.sh`; archive PR; JACKED_OUT; no tag (FR-6) → **[G-5]** ⇐ Task 1.8 · kind: judgment
- [ ] Task 1.E2E: Sprint 1 goal validation — G-1 (five beads closed with commit and test), G-2 (the matcher fixtures both ways and with `{ native: false }`), G-3 (protected-kept fixture and rendering; housekeeping guards both ways; the live confirmation on the next housekeeping merge, recorded on bd-nr5i6), G-4 (content-fetch fixtures; a live read-only `getFileContent` probe recorded in the report), G-5 (every check run green on the merged head; three green full `npm test` runs on the loaded host; cost-ledger rows of the cycle ≤ USD 40 meter-priced) → `a2a/sprint-279/e2e.md`; post-merge verification: merge-triggered CI green on `main`, the record branch pushed, the archive PR merged → **[G-1]** ⇐ Task 1.9 · kind: judgment

### Patch contract (per-implementer path allowlist)

| Implementer | May change | Must not touch |
|---|---|---|
| A | `.claude/skills/bridgebuilder-review/resources/core/truncation.ts`, `resources/config.ts` (the three new keys), `resources/__tests__/loa-detection.test.ts`, `resources/__tests__/truncation.test.ts`, `.claude/skills/bridgebuilder-review/SKILL.md` (exclusion-patterns and protected-paths headings only) | `types.ts`, `paged-fetch.ts`, `github-cli.ts`, `git-provider.ts`, `progressive-truncation.test.ts`, `dist/`, CHANGELOG (lines go in the report), everything outside the skill |
| B | `resources/core/paged-fetch.ts`, `resources/adapters/github-cli.ts`, `resources/ports/git-provider.ts`, `resources/__tests__/paged-fetch*.test.ts`, `resources/__tests__/github-cli*.test.ts`, `resources/__tests__/progressive-truncation.test.ts`, any typed `IGitProvider` test double its inventory names, `SKILL.md` (coverage heading only) | `types.ts`, `truncation.ts`, `config.ts`, `loa-detection.test.ts`, `truncation.test.ts`, `dist/`, CHANGELOG, everything outside the skill |
| C | `.claude/scripts/classify-pr-type.sh`, `.claude/scripts/classify-merge-pr.sh` (comment and usage text), `.github/workflows/post-merge.yml`, `tests/unit/post-merge-classifier.bats`, `tests/unit/classify-merge-pr.bats`, `tests/unit/post-merge-workflow-guards.bats`, new `tests/unit/post-merge-orchestrator-type.bats`, documentation lines that enumerate `pr_type` values (listed in the report) | `post-merge-orchestrator.sh`, `checksums.json`, REPO-MAP, CHANGELOG, the skill |

A patch outside its allowlist is returned, not landed. `types.ts` is the lead's (Task 1.0).

### Seams Under Test

| Seam | Catches | Misses | Prior art |
|------|---------|--------|-----------|
| `matchesExcludePattern` with `{ native: true/false }` over fixture names | substring hiding paths; segment anchoring errors; Node-version divergence | a `path.matchesGlob` behaviour change in a future Node | `loa-detection.test.ts` (sprint-bug-278 cases) |
| `truncateFiles` / `partitionUserExclusions` with user and protected patterns | a protected file silently excluded; a protected list that overrides an explicit name; config parsing | the operator's judgement of what is protected | `truncation.test.ts`, `progressive-truncation.test.ts` |
| `paged-fetch` with a provider double (no patch, content served) | an unreviewed added file; an unbounded fetch; binary misread as text | GitHub's real raw-media behaviour (Q-1 probe, read-only) | `paged-fetch.test.ts` (cycle-133 C-1) |
| `assertAllowedArgs` over the contents shape | a widened `gh api` surface | `gh` version differences in header handling | `github-cli.test.ts` |
| `classify-pr-type.sh` + `classify-merge-pr.sh` + the workflow `if:` text | a housekeeping merge that still prepares; a cycle merge misrouted | GitHub's expression evaluation (not executed in tests) | `post-merge-classifier.bats`, `post-merge-workflow-guards.bats` |
| guardrails on CPU time | an algorithmic regression | wall-clock stalls (by design) | `progressive-truncation.test.ts` |

### Dependencies

- None external beyond the host toolchain: Node 22.22, tsx 4.21 and TypeScript 5.9 in the skill, bats 1.13 through the npx cache, jq 1.7, `gh` 2.x authenticated for the Q-1 read-only probe (one call).
- Internal: Task 1.1 → 1.2 (same file, implementer A); Task 1.3 → 1.4 (same file, implementer B); Task 1.7 after 1.1 … 1.6; 1.8 after 1.7; 1.9 after 1.8; 1.E2E after 1.9.

### Security Considerations

- The matcher never interprets a filename; patterns come from the operator only (`.reviewignore` from the reviewer's `repoRoot`). FR-1 closes a PR-author-controlled hiding path; FR-2 keeps attack-prone paths reviewable by default.
- The content fetch is the only new network read: one allowlisted `gh api` shape, path and ref validated, bytes bounded, failures degrade to today's behaviour; no credential handling changes.
- System Zone writes (Tasks 1.0, 1.1 … 1.6 landings) under the bounded marker with checksums, REPO-MAP and dist regenerated; secret scan (detect-secrets and the repository scanners) before every push; the publication contract is untouched.

### Risks & Mitigation

- Risk: a default pattern relied on substring matching → none known (six root-level file names); the CHANGELOG names the change; the coverage record shows what was reviewed.
- Risk: the raw media type returns base64 JSON on the host's `gh` → the adapter decodes that shape too; Q-1 probe before the fix lands.
- Risk: the protected list blocks a legitimate exclusion → `protected_paths` replaces the default; `[]` disables; the record names the pattern.
- Risk: a consumer of `pr_type` rejects `housekeeping` → Q-3 grep; the workflow guards and notify pinned; the orchestrator's refusal pinned.
- Risk: the dissent voices time out on the full diff → code-only diff per implementer; ≤ 3 runs.
- Risk: the Bridgebuilder round degrades on the PR → prefix excludes for generated files; the PR is code, tests and docs well under the file cap.

### Success Metrics

- G-1: 5 of 5 beads closed with commit and test.
- G-2: the matcher fixtures pass in both directions and with the native glob disabled.
- G-3: the protected-kept fixture and rendering pass; both prepare jobs skip `housekeeping` in the guard tests; the next live housekeeping merge runs no prepare job.
- G-4: the content-fetch fixtures pass; the Q-1 probe recorded.
- G-5: every check run green on the merged head; three consecutive green `npm test` runs under load; cycle spend ≤ USD 40 meter-priced.

> Sources: prd.md § Functional Requirements, § Goals & Success Metrics; sdd.md § 1.4, § 7, § 8; DEC-1019 … DEC-1025

---

## Appendix

### Goals (from prd.md § Goals & Success Metrics)

| Goal | Statement | Evidence at sprint close |
|------|-----------|--------------------------|
| G-1 | Every in-scope bead closed with evidence | 5 beads closed, each close reason naming the commit and the test; `reviewer.md` |
| G-2 | No substring hiding path; one matcher on every Node version | the FR-1 fixtures both ways and with `{ native: false }` |
| G-3 | Protected paths kept and named; housekeeping merges prepare nothing | the FR-2 fixtures and rendering; the FR-4 guard fixtures both ways; the live confirmation on bd-nr5i6 |
| G-4 | Patch-less added files reviewed | the FR-3 fixtures; the Q-1 probe |
| G-5 | Green suites at no real spend; one PR, one non-degraded Bridgebuilder verdict | check runs on the merged head; three green `npm test` runs under load; the cycle's cost-ledger rows ≤ USD 40 |

> Sources: prd.md § Goals & Success Metrics, § Success Criteria

### Flatline sprint review dispositions (1.0 → 1.1)

Two voices, cross-scoring degraded (KF-041 shape), 4 skeptic blockers and 38 medium items; every item read. Design-level items are dispositioned in sdd.md § 11.F and requirement-level ones in prd.md Appendix C.2; this table carries the plan-level outcome.

| Item | Concern (short) | Disposition |
|---|---|---|
| SKP-002, gpt IMP-002, IMP-008 | synthesized patches vs shared budgets; caps; deadline | **Accepted** — Task 1.3 (aggregate budget incl. overhead, `max_content_fetches`, 120 s deadline, outcomes) |
| SKP-001 (envelope sniffing), gpt IMP-004, opus IMP-010 | body-sniffed base64 fallback | **Accepted** — Task 1.3: JSON envelope only, strict validation, sized buffer |
| SKP-005, gpt IMP-003 | ref bound to the listing's head sha | **Accepted** — Task 1.3 (asserted ref; restart discards) |
| SKP-001 (matcher OR), gpt IMP-001, opus IMP-001 | one matcher everywhere | **Accepted** — Task 1.1: `dotSegmentGlobMatch` only, grammar pinned, guard test |
| gpt IMP-005 | synthesized-patch fixture matrix | **Accepted** — Task 1.3 |
| gpt IMP-006, opus IMP-003 | provider inventory; contract scope | **Accepted** — Task 1.3 (inventory), Task 1.0 (all `types.ts` fields) |
| gpt IMP-007, opus IMP-017, IMP-019, IMP-022 | SKILL.md ownership; renderer module | **Accepted** — allowlists by heading; renderer is `paged-fetch.ts` (B) |
| gpt IMP-009, opus IMP-008 | Q-3 as a compatibility gate | **Accepted** — Task 1.6 |
| gpt IMP-010, opus IMP-015 | degraded Bridgebuilder outcome | **Accepted** — Task 1.9 (ship with the degraded record documented + DEC row) |
| gpt IMP-011, opus IMP-004 | live housekeeping verification as deferred evidence | **Accepted** — bd-nr5i6 closes on commit + tests; the live confirmation is appended later and named non-blocking in e2e |
| gpt IMP-012, opus IMP-005, IMP-018 | FR-5 red-first and load condition | **Accepted** — Task 1.5 (negative control as the red artefact; two concurrent `npm test` runs) |
| gpt IMP-013, opus IMP-016 | named host-local red allowlist | **Accepted** — Task 1.7, Acceptance Criteria |
| gpt IMP-014 | protection tests in both orders | **Accepted** — Task 1.2 |
| gpt IMP-015 | rendering escapes | **Accepted** — Task 1.4 |
| gpt IMP-016 | classifier vs wrapper tests | **Already distinct** — `post-merge-classifier.bats` / `classify-merge-pr.bats` |
| gpt IMP-017, opus IMP-009 | evaluate guard conditions; lint YAML | **Accepted** — Task 1.6 (shell mirror over the matrix; yq + actionlint) |
| opus IMP-002 | `isWildcardPattern` set; non-wildcard directory patterns vs protection | **Accepted** — Task 1.1 (`[*?{[]`), Task 1.2 (an explicit directory line excludes) |
| opus IMP-006 | kinds for Tasks 1.2 and 1.6 | **Accepted** — both `judgment` |
| opus IMP-007 | line refs → anchors | **Accepted** — Task 1.2 names call expressions and functions |
| opus IMP-011 | Q-1 probe by the lead | **Accepted** — Task 1.0 |
| opus IMP-012 | lead integration check | **Accepted** — Task 1.7 |
| opus IMP-013 | grep for importers/callers | **Accepted** — Task 1.1 |
| opus IMP-014 | fix-round basing | **Accepted** — Task 1.7 |
| opus IMP-020 | `.reviewignore` provenance test | **Accepted** — Task 1.2 (base-sha read) |
| opus IMP-021 | FR-6 in the acceptance bullets; A's red/fix pairs | **Accepted** — Acceptance Criteria; A returns two pairs (1.1, 1.2) |
| opus IMP-023 | operator confirmation timing | **Clarified** — post-ship (Task 1.9) |

> Sources: `grimoires/loa/a2a/flatline/cycle-135-sprint-review.json`; sdd.md § 11.F; prd.md Appendix C.2
