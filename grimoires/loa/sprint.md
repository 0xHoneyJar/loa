# Sprint Plan: Review-coverage follow-ups (cycle-135)

**Version:** 1.0
**Date:** 2026-10-26
**Author:** Sprint Planner Agent (Claude Fable 5.1, unattended)
**PRD Reference:** `grimoires/loa/prd.md` (1.0, FR-1 … FR-6, G-1 … G-5)
**SDD Reference:** `grimoires/loa/sdd.md` (1.0, C-1 … C-5, D-1.1 … D-2.2)
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

- [ ] FR-1 … FR-5 acceptance criteria met as written in prd.md, each by a test that was red first (red commit SHA in `reviewer.md`)
- [ ] `npm test` (skill) and `tsc --noEmit` green; `post-merge-classifier.bats`, `classify-merge-pr.bats`, `post-merge-workflow-guards.bats`, `post-merge-publication.bats` green; `bash -n`; dist fresh; checksums, REPO-MAP and manifest-paths pass; the local CI mirror green except known host-local reds (KF-034 shape)
- [ ] Review and audit APPROVED with every dissent payload dispositioned; the Bridgebuilder's findings triaged on the PR; every check run green on the merged head
- [ ] G-1 … G-5 evidenced in `a2a/sprint-279/e2e.md`

### Technical Tasks

<!-- → **[G-n]** names the PRD goal; ⇐ names the blocking task(s) (edge-or-none); every line ends with · kind: … -->

- [ ] Task 1.0: Contract commit (lead, System Zone) — `resources/core/types.ts`: `TruncationResult.protectedKept?: Array<{ file: string; pattern: string }>`, `CoverageRecord.protected_kept?: Array<{ file: string; pattern: string }>`, `CoverageRecord.reviewed[]` gains `source?: "contents"`; `npm run build`, `check-bb-dist-fresh.sh --check`, checksums and REPO-MAP regenerated under the marker; worktrees `../loa-wt-c135-{a,b,c}` created from this commit (D-2.1) → **[G-1]** ⇐ none · kind: judgment
- [ ] Task 1.1: Exclusion matcher semantics (A) — `truncation.ts`: `isWildcardPattern`, `segmentMatch` (gitignore-like: no `/` → whole segment at any depth, `/` → root-anchored path or subtree; one trailing `/` stripped), `matchesExcludePattern(filename, patterns, opts?: { native?: boolean })` = non-wildcard → `segmentMatch`; wildcard → `(native && path.matchesGlob) || dotSegmentGlobMatch`; `simplifiedGlobMatch` deleted; doc comment states the semantics; tests in `loa-detection.test.ts`: `util.loa-version.json.ts`, `x/.loa-version.json.bak`, `MYPROCESS.md`, `PROCESS.md.old` not excluded by the defaults; `docs/PROCESS.md`, `BUTTERFREEZONE.md` excluded; `a/b` vs `a/b/c` and `x/a/b`; every case run with `{ native: false }` giving the same result; the skipped single-`*` case un-skipped; CHANGELOG line for the lead (bd-ow72o) (C-1, D-1.1) → **[G-2]** ⇐ Task 1.0 · kind: mechanical
- [ ] Task 1.2: Protected paths (A) — `truncation.ts`: `export const DEFAULT_PROTECTED_PATHS`, `partitionUserExclusions(files, userPatterns, protectedPatterns)`, applied at `:1292`, `:1442`, `:1515` (not at the Loa-tier call `:666`); `truncateFiles` returns `protectedKept`; `config.ts`: `protected_paths?: string[]` YAML key → `protectedPaths` (set → replaces the default; `[]` disables), parsed like `exclude_patterns`; `SKILL.md`: the key, the default list, the wildcard/non-wildcard rule, the new segment semantics of Task 1.1; tests: `**/*.yml` keeps `.github/workflows/ci.yml` with `protectedKept = [{file, pattern}]`, exact pattern excludes it, `[]` disables, custom list protects only its entries, the Loa tier still strips `.claude/settings.json` without self-review; CHANGELOG line for the lead (bd-i4fyw) (C-2, D-1.2) → **[G-3]** ⇐ Task 1.1 · kind: mechanical
- [ ] Task 1.3: Content fetch for patch-less added files (B) — `ports/git-provider.ts`: `getFileContent(owner, repo, path, ref, maxBytes): Promise<FileContentResult>`; `adapters/github-cli.ts`: the method (`gh api -H "Accept: application/vnd.github.raw+json" /repos/<o>/<r>/contents/<path>?ref=<sha>`, `maxBuffer = maxBytes + 1024`, binary = NUL in the first 8 KiB or invalid UTF-8, `too_large` over `maxBytes`; a base64-JSON response decoded as a fallback — Q-1 verified first with one read-only call against a public file of this repository at a known sha, shape recorded in the report), `assertAllowedArgs` admits exactly that shape (path segments without `..`, no leading `/`, no `?`/`#`, percent-encoded; ref `^[0-9a-f]{40}$`; the single fixed `-H` value); `paged-fetch.ts` pass 1: eligible = `status === "added" && patch == null && additions > 0`, listing order, at most `maxFilesPerPr` fetches, each `≤ maxDiffBytes`; text → synthesized `@@ -0,0 +1,N @@` patch, `patchBytes`, `source: "contents"`, pre-retained for pass 2; binary / too_large / error → metadata unchanged (today's `no_patch`); tests with a provider double: reviewed with the synthesized patch and `reviewed[].source == "contents"`, not degraded; binary, too large, provider error, modified-without-patch → `no_patch`; allowlist accepts the shape and rejects `..`, a foreign query, a non-hex ref, a different `Accept`; SKILL.md coverage text names the source; CHANGELOG line for the lead (bd-w5pd9) (C-3, D-1.3) → **[G-4]** ⇐ Task 1.0 · kind: judgment
- [ ] Task 1.4: Coverage record and rendering of protected paths (B) — `paged-fetch.ts`: `coverage.protected_kept = sel.protectedKept ?? []`; the PR summary renders "Protected paths kept (n)" with `file — kept despite <pattern>` after the omissions and `(source: contents)` on synthesized entries; tests on the rendered text (C-2 consumer side) → **[G-3]** ⇐ Task 1.3 · kind: mechanical
- [ ] Task 1.5: CPU-time guardrails (B) — `progressive-truncation.test.ts`: both guardrails measure `process.cpuUsage()` user + system around the measured call; thresholds unchanged; message names CPU time; comment names bd-oglcu; the report shows three consecutive green full runs on the loaded host and one report-only quadratic stand-in tripping the 100 ms bound (C-5, D-1.5) → **[G-5]** ⇐ Task 1.0 · kind: mechanical
- [ ] Task 1.6: Housekeeping classifier value and workflow guard (C, System Zone) — `classify-pr-type.sh`: rule 1a echoes `housekeeping`, header grammar `<cycle|bugfix|housekeeping|other>`, rule list 1a updated; `classify-merge-pr.sh`: comment only (the no-PR guard still forces `other`); `post-merge.yml`: `simple-release` `if:` gains `&& needs.classify.outputs.pr_type != 'housekeeping'` with a comment naming bd-nr5i6, `full-pipeline` unchanged; Q-3: grep the repository for other consumers of `pr_type` / `PM_PR_TYPE` and report; tests: PCT-T28 … T32, T38 → `housekeeping`, T35 → `other`, others unchanged; `classify-merge-pr.bats`: housekeeping subject with a PR → `pr_type=housekeeping`, no-PR push → `other`; `post-merge-workflow-guards.bats`: both prepare jobs skip `housekeeping`, `simple-release` runs for `bugfix`/`other`, `full-pipeline` for `cycle` only; a bats case pins `post-merge-orchestrator.sh --generate --type housekeeping` → exit 1 "Invalid --type"; CHANGELOG line for the lead (bd-nr5i6) (C-4, D-1.4) → **[G-3]** ⇐ Task 1.0 · kind: mechanical
- [ ] Task 1.7: Sprint close (lead) — land A (1.1, 1.2) → B (1.3 … 1.5) → C (1.6) as red commit then fix commit each, under the marker with dist, checksums and REPO-MAP regenerated; red-first verified (`red-test-check.sh` with `bats` on PATH for C; the detached-worktree equivalent for the skill's `npm test`, DEC-1007 shape); suites and the local CI mirror; CHANGELOG `[Unreleased]` `### Fixed` / `### Changed` entries; DEC rows from the implementers' judgment calls; `reviewer.md` with AC verification → **[G-1]** ⇐ Task 1.1, Task 1.2, Task 1.3, Task 1.4, Task 1.5, Task 1.6 · kind: judgment
- [ ] Task 1.8: Review and audit (lead) — `/review-sprint` with ≤ 3 dissent runs (`adversarial-review.sh --type review`, code-only diffs per implementer), `engineer-feedback.md` (C-11 bullet grammar; `verdict-derive` consistent); `/audit-sprint` with the audit envelope (`--type audit`), `auditor-sprint-feedback.md`, COMPLETED marker; fix rounds back to the implementers as needed → **[G-1]** ⇐ Task 1.7 · kind: judgment
- [ ] Task 1.9: Ship (lead) — after review and audit APPROVED: PR from `feature/cycle-135-review-coverage` (code, tests, docs, CHANGELOG, decisions, ledger, manifests, dist), secret scan first; Bridgebuilder round (`BRIDGEBUILDER_MODEL=codex-headless`, prefix excludes for `dist/`, `checksums.json`, REPO-MAP, `decisions.yaml`, `ledger.json`; ≤ 2 rounds; stop under USD 8 remaining); triage comment; admin merge when every check run is green; `record-branch.sh --cycle 135 --prev origin/record/cycle-134-post-ship-fixes --stage "stage 1"`; `archive-cycle.sh`; archive PR; JACKED_OUT; no tag (FR-6) → **[G-5]** ⇐ Task 1.8 · kind: judgment
- [ ] Task 1.E2E: Sprint 1 goal validation — G-1 (five beads closed with commit and test), G-2 (the matcher fixtures both ways and with `{ native: false }`), G-3 (protected-kept fixture and rendering; housekeeping guards both ways; the live confirmation on the next housekeeping merge, recorded on bd-nr5i6), G-4 (content-fetch fixtures; a live read-only `getFileContent` probe recorded in the report), G-5 (every check run green on the merged head; three green full `npm test` runs on the loaded host; cost-ledger rows of the cycle ≤ USD 40 meter-priced) → `a2a/sprint-279/e2e.md`; post-merge verification: merge-triggered CI green on `main`, the record branch pushed, the archive PR merged → **[G-1]** ⇐ Task 1.9 · kind: judgment

### Patch contract (per-implementer path allowlist)

| Implementer | May change | Must not touch |
|---|---|---|
| A | `.claude/skills/bridgebuilder-review/resources/core/truncation.ts`, `resources/config.ts`, `resources/__tests__/loa-detection.test.ts`, `resources/__tests__/truncation.test.ts`, `.claude/skills/bridgebuilder-review/SKILL.md` (exclusion / protected-paths text) | `types.ts`, `paged-fetch.ts`, `github-cli.ts`, `dist/`, CHANGELOG (lines go in the report), everything outside the skill |
| B | `resources/core/paged-fetch.ts`, `resources/adapters/github-cli.ts`, `resources/ports/git-provider.ts`, `resources/__tests__/paged-fetch*.test.ts`, `resources/__tests__/github-cli*.test.ts`, `resources/__tests__/progressive-truncation.test.ts`, `SKILL.md` (coverage text only) | `types.ts`, `truncation.ts`, `config.ts`, `dist/`, CHANGELOG, everything outside the skill |
| C | `.claude/scripts/classify-pr-type.sh`, `.claude/scripts/classify-merge-pr.sh` (comment), `.github/workflows/post-merge.yml`, `tests/unit/post-merge-classifier.bats`, `tests/unit/classify-merge-pr.bats`, `tests/unit/post-merge-workflow-guards.bats`, one new bats file for the orchestrator `--type` refusal | `post-merge-orchestrator.sh`, `checksums.json`, REPO-MAP, CHANGELOG, the skill |

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

Appended after the Flatline sprint review.

> Sources: `grimoires/loa/a2a/flatline/cycle-135-sprint-review.json` (after the review)
