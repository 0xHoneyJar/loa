# Product Requirements Document: Review-coverage follow-ups (cycle-135)

**Version:** 1.0
**Date:** 2026-10-26
**Author:** PRD Architect Agent (Claude Fable 5.1, unattended)
**Status:** Draft — autonomous run (operator instruction 2026-10-26, quoted verbatim in the brief: "yes approve and then also work on the other things also")
**Brief:** `grimoires/loa/context/cycle-135-brief.md`
**Cycle:** `cycle-135-review-coverage-followups` (ledger, active); **branch:** `feature/cycle-135-review-coverage` from `main 4256a1b3` (the merge of PR #1300, so the confirmed rows DEC-1001 … DEC-1010 are the base)
**Predecessor:** the two `/bug` micro-sprints of 2026-10-26 (PR #1299 → `b880a1cd`; sprint-bug-277 and sprint-bug-278; record `record/cycle-134-post-ship-fixes` stage 3 `9790f92b`) and cycle-134 "post-ship fixes" (PR #1296 → `a8d7c973`; archive `grimoires/loa/archive/cycle-134-post-ship-fixes/`)

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

The two `/bug` micro-sprints of 2026-10-26 fixed a classifier over-match and a dot-segment gap in the Bridgebuilder's exclusion matcher, and their review, audit and Bridgebuilder rounds left five follow-ups behind: a pre-existing substring match that lets a pull-request author hide a file from the reviewer (bd-ow72o, security), a widening of broad wildcard exclusions into CI and agent-config paths that no default protects (bd-i4fyw), large added files that the GitHub API returns without a patch and that degrade every round (bd-w5pd9), housekeeping merges that still prepare a release candidate on the "other" path (bd-nr5i6), and a wall-clock test guardrail that fails under host load (bd-oglcu).

This cycle closes the five through the golden path in one sprint with three implementers, each change tested first, shipped as one PR with a Bridgebuilder round, recorded and archived; no release. The semantics decided on the operator's behalf are recorded as proposed rows DEC-1011 … DEC-1018 (Appendix A) and stay proposed until the operator confirms them at the close.

> Sources: cycle-135-brief.md § Objective, § Scope; PR #1299 triage comment 6405801838; `grimoires/loa/a2a/bug-20261025-826c6b/auditor-sprint-feedback.md` § Findings (record stage 3); DEC-1011, DEC-1018

---

## Problem Statement

### The Problem

The Bridgebuilder decides what it reviews by subtracting exclusions from the pull request's file list. Three defects in that subtraction, one in the release pipeline's routing and one in the test suite remain after the micro-sprints:

1. A non-wildcard exclusion pattern is matched with `filename.includes(pattern)` (`truncation.ts:195-197`, and the Node < 22 fallback's non-glob branch). The default list carries six such patterns (`.loa-version.json`, `.loa.config.yaml`, `.loa.config.yaml.example`, `PROCESS.md`, `BUTTERFREEZONE.md`, `INSTALLATION.md`), so `util.loa-version.json.ts`, `x/.loa-version.json.bak` or `MYPROCESS.md` are silently dropped from the review set — a hiding path a pull-request author controls by naming.
2. Since sprint-bug-278, wildcard exclusions match dot-led segments on Node ≥ 22 (as the Node < 22 fallback always did). A broad `**/*.yml` now also excludes `.github/workflows/*.yml`; `**/*.json` excludes `.claude/settings.json`, `.husky/*` goes with `**/*.sh`. Nothing protects the files an attacker edits first, and the loss shows only in the coverage record after the review.
3. The GitHub `pulls/N/files` endpoint omits the patch for large files. Such a file is excluded at selection ("diff unavailable") and recorded as a reviewable `no_patch` omission, which degrades the round (`incomplete_coverage`). On PR #1296 round 1 the two added planning documents did exactly that.
4. sprint-bug-277 routes archive, ledger and decisions-confirm merges to `other`; the "Prepare Release (Bugfix or Other)" job still runs `post-merge-orchestrator.sh --generate` and uploads a candidate (merge `b880a1cd`, run 40255620297). Housekeeping produces release artifacts nobody wants.
5. Two performance guardrails in `progressive-truncation.test.ts` measure wall-clock time; the `< 100 ms` one failed in about one of two full-suite runs on a loaded host (102–146 ms) and passes alone.

### User Pain Points

- The maintainer cannot trust "excluded by pattern" to mean "the operator excluded it": a file name can do it.
- A tuned `.reviewignore` on Node ≥ 22 can remove CI workflows from review without any configuration change.
- A large added file degrades a round that was otherwise complete, and the operator has to re-run with exclusions to get a verdict.
- Every archive merge produces a candidate artifact that looks publishable.
- A green suite turns red when the host is busy, and the lead re-runs it to be sure.

### Current State

`matchesExcludePattern` (`truncation.ts:182-200`): Node ≥ 22 → `path.matchesGlob`, then exact/substring for non-wildcard patterns, then the dot-agnostic `dotSegmentGlobMatch` retry for wildcard patterns; Node < 22 → `simplifiedGlobMatch` (single-`*` crosses `/`; non-glob is substring). `.reviewignore` lines ending in `/` become `<line>**` (`:395`). Patch-less files are excluded at selection and counted as `no_patch` omissions (`paged-fetch.ts:39-150`). `classify_pr_type` returns `cycle | bugfix | other`; `post-merge.yml` runs `simple-release` for every non-cycle merge with a PR number (`:109`) and `full-pipeline` for cycle merges (`:187`). The guardrails use `performance.now()` (`progressive-truncation.test.ts:548-590`).

### Desired State

A non-wildcard pattern matches whole path segments (gitignore-like) and the same matcher runs on every Node version; a default protected-paths list keeps CI workflows, agent settings and hooks and git hooks in the review set against wildcard exclusions and names them in the coverage record; an added file without a patch is fetched by content, bounded, and reviewed; housekeeping merges classify `housekeeping` and prepare nothing; the guardrails measure CPU time. Every change is pinned by a test that was red first.

> Sources: `truncation.ts:182-200, 261-278, 395`, `paged-fetch.ts:39-150, 240-280`, `classify-pr-type.sh:42-90`, `post-merge.yml:109, 187, 258-270`, `progressive-truncation.test.ts:548-590` (Appendix B); run 40255620297; PR #1296 round 1 (`~/.cache/loa/cycle-134/bb/round1.log`)

---

## Goals & Success Metrics

### Primary Goals

- **G-1** Every in-scope bead (bd-ow72o, bd-i4fyw, bd-w5pd9, bd-nr5i6, bd-oglcu) is closed with a commit and a test named in its close reason.
- **G-2** No substring hiding path: a fixture set shows that `util.loa-version.json.ts`, `x/.loa-version.json.bak` and `MYPROCESS.md` stay in the review set while `docs/PROCESS.md`, `a/b` (anchored) and every current default still match; the matcher gives identical results with and without the native glob (the fallback is exercised by a test seam).
- **G-3** Protected paths are kept and named: a wildcard exclusion that matches `.github/workflows/ci.yml` leaves it in the review set with a `protected_kept` entry naming the pattern; an exact pattern naming it excludes it; housekeeping merges prepare nothing (both prepare jobs skip; the workflow guards are pinned both ways).
- **G-4** A patch-less added file is reviewed: with a provider test double that returns no patch and serves content, the synthesized patch is in the review set and the coverage is not degraded; a binary or over-budget file stays `no_patch`.
- **G-5** Green suites at no real model spend; one PR; one non-degraded Bridgebuilder verdict; the cycle's meter-priced spend ≤ USD 40 (DEC-0999 shape).

### Key Performance Indicators (KPIs)

- Red-first evidence for every acceptance test (the red commit SHA in `reviewer.md`).
- `npm test` in the Bridgebuilder skill green three runs in a row on the loaded lead host (bd-oglcu).
- The next archive or decisions-confirm merge after this cycle ships runs neither prepare job (live confirmation, recorded on bd-nr5i6).

### Constraints

- System Zone files (`.claude/skills/bridgebuilder-review/**`, `.claude/scripts/classify-pr-type.sh`, `.claude/scripts/classify-merge-pr.sh`, `.github/workflows/post-merge.yml`) are edited under the bounded marker (DEC-0824) with `checksums.json`, `REPO-MAP.md` and the Bridgebuilder `dist/` regenerated in the same commit.
- Spend cap USD 40 ([ASSUMPTION decision] (DEC-1018)) in the meter's unit; no publication.
- The Loa tier's own exclusion (`LOA_EXCLUDE_PATTERNS` under the self-review label) is not changed except for the matching semantics of its six non-wildcard entries ([ASSUMPTION decision] (DEC-1014)).

> Sources: cycle-135-brief.md § Objective, § Standing rules; DEC-0824, DEC-0999, DEC-1014, DEC-1018

---

## User Personas & Use Cases

### Primary Persona: The maintainer (operator)

Reads Bridgebuilder verdicts on their pull requests and the post-merge run summaries. Wants exclusions to mean what they wrote, CI and agent-config files always in front of the reviewer, large added files reviewed rather than excused, and no release artifacts from housekeeping merges.

### Secondary Persona: The lead agent (Fable) and its Opus subagents

Implement, review and audit under the standing rules. Need disjoint path allowlists, a test double for the GitHub provider, and deterministic suites.

### Tertiary Persona: A pull-request author

Benign or not: controls file names and contents, never the operator's patterns. The matcher must not let a name decide what is reviewed.

### Use Cases

- UC-1 A PR adds `src/util.loa-version.json.ts`: today excluded by the default `.loa-version.json`; after this cycle reviewed.
- UC-2 An operator's `.reviewignore` holds `**/*.yml`: today (Node ≥ 22) `.github/workflows/ci.yml` is excluded; after this cycle kept and named `protected_kept`.
- UC-3 A PR adds a 400 KB `prd.md`: today `no_patch`, round degraded; after this cycle fetched by content within the byte budget and reviewed.
- UC-4 The lead merges `chore/cycle-135-archive`: today a candidate is prepared on the other path; after this cycle no prepare job runs.
- UC-5 The suite runs while two implementers work on the host: today the `< 100 ms` guardrail may fail; after this cycle it measures CPU time and passes.

> Sources: cycle-135-brief.md § Scope; the bead descriptions (`br show bd-ow72o bd-i4fyw bd-w5pd9 bd-nr5i6 bd-oglcu`, 2026-10-26)

---

## Functional Requirements

### FR-1: Non-wildcard exclusion patterns match whole path segments, and one matcher runs on every Node version (bd-ow72o)
**Priority:** Must Have
**Description:** `matchesExcludePattern` (`truncation.ts:182-200`) treats a pattern without `*`, `?`, `{` or `[` as a substring (`filename === pattern || filename.includes(pattern)`), and the Node < 22 fallback does the same in `simplifiedGlobMatch`. The semantics become gitignore-like ([ASSUMPTION decision] (DEC-1013)): a pattern without `/` matches a filename whose path contains the pattern as one whole segment at any depth (`PROCESS.md` ⇢ `PROCESS.md`, `docs/PROCESS.md`; not `MYPROCESS.md`, `PROCESS.md.old`); a pattern containing `/` is anchored at the repository root and matches the path and its subtree (`a/b` ⇢ `a/b`, `a/b/c`; not `x/a/b`). Wildcard patterns run through `path.matchesGlob` and then `dotSegmentGlobMatch` where the native matcher exists, and through `dotSegmentGlobMatch` alone otherwise; `simplifiedGlobMatch` is removed.
**Acceptance Criteria:**
- [ ] Fixtures both ways in `loa-detection.test.ts`: `util.loa-version.json.ts`, `x/.loa-version.json.bak`, `MYPROCESS.md`, `PROCESS.md.old` are **not** excluded by the defaults; `.loa-version.json`, `docs/PROCESS.md`, `BUTTERFREEZONE.md` are; `a/b` excludes `a/b/c` and not `x/a/b`; every existing `LOA_EXCLUDE_PATTERNS` case keeps its result.
- [ ] A test seam lets the suite run the matcher with the native glob disabled; the dot-segment, zero-segment globstar, single-`*` and non-wildcard cases give identical results with it on and off (the Node 20 / Node 22 divergence is closed); the "single `*` stays within one segment" case is no longer skipped.
- [ ] `simplifiedGlobMatch` no longer exists; `npm test` and `tsc --noEmit` are green; the function's doc comment states the semantics; the Bridgebuilder SKILL.md's `.reviewignore` / `exclude_patterns` text names them.
- [ ] CHANGELOG `[Unreleased]` names the behaviour change (a pattern that relied on substring matching stops matching) with bd-ow72o.
**Dependencies:** none.

> Sources: `truncation.ts:94-200, 261-278, 395` (Appendix B); `grimoires/loa/a2a/bug-20261025-826c6b/auditor-sprint-feedback.md` § Findings (MEDIUM, pre-existing); DEC-1010, DEC-1013

### FR-2: Protected paths survive wildcard user exclusions and are named in the coverage record (bd-i4fyw)
**Priority:** Must Have
**Description:** A default protected set ([ASSUMPTION decision] (DEC-1014)) — `.github/workflows/**`, `.github/actions/**`, `.claude/settings.json`, `.claude/settings.local.json`, `.claude/hooks/**`, `.husky/**` — applies at the user-pattern call sites (`truncation.ts:1292, 1442, 1515`; `--exclude`, `bridgebuilder.exclude_patterns`, `.reviewignore`): when the pattern that matches a protected file is a wildcard pattern, the file stays in the review set and the coverage record gains `protected_kept: [{file, pattern}]`; a non-wildcard pattern (segment-anchored, FR-1) that names the file still excludes it. The Loa tier (`LOA_EXCLUDE_PATTERNS`, `:666`) is not subject to the list. `bridgebuilder.protected_paths` (config) replaces the default when set; `[]` disables.
**Acceptance Criteria:**
- [ ] `**/*.yml` leaves `.github/workflows/ci.yml` in the review set with a `protected_kept` entry naming the pattern; `.github/workflows/ci.yml` (exact) or `.github/workflows/` (`.reviewignore`, becomes a glob — so an operator who wants to exclude workflows sets `protected_paths`) behave as documented and pinned.
- [ ] With `protected_paths: []` the wildcard excludes the workflow; with a custom list only its entries are protected.
- [ ] The Loa tier still strips `.claude/settings.json` in a Loa repository without the self-review label (unchanged behaviour, pinned).
- [ ] The coverage summary rendered on the PR lists protected-kept files under their own heading; the SKILL.md documents the knob and the default list; CHANGELOG entry with bd-i4fyw.
**Dependencies:** FR-1 (the wildcard / non-wildcard distinction).

> Sources: `truncation.ts:1292-1318, 1442, 1515`, `paged-fetch.ts` coverage record and rendering (`:400-410`), `config.ts:1100-1142, 1524-1537` (Appendix B); DEC-1009 (the accepted widening), DEC-1014

### FR-3: Added files without a patch are fetched by content and reviewed (bd-w5pd9)
**Priority:** Should Have
**Description:** In the two-pass fetch (`paged-fetch.ts`), a file with `status: added`, no patch in its metadata and `additions > 0` is fetched through a new provider method `getFileContent(owner, repo, path, ref)` that runs `gh api /repos/{o}/{r}/contents/{path}?ref=<head_sha>` with the raw media type (an allowlisted `gh api` shape, `github-cli.ts assertAllowedArgs`), bounded by the file's planned bytes under `max_diff_bytes` ([ASSUMPTION decision] (DEC-1015)). UTF-8 text becomes a synthesized patch (`@@ -0,0 +1,N @@` followed by `+` lines) reviewed like any other and marked `source: contents` in the coverage record's `reviewed` entry; binary content (NUL byte or invalid UTF-8), an over-budget file or a failed fetch keeps today's `no_patch` omission. Modified, renamed and removed files without a patch are unchanged.
**Acceptance Criteria:**
- [ ] With a provider double that lists an added file without a patch and serves its content: the file is in the review set with the synthesized patch, `reviewed[].source == "contents"`, and the coverage is not degraded by it.
- [ ] Binary content, content over the planned bytes, and a provider error each leave the file as `no_patch` (reviewable omission) exactly as today, with a test each.
- [ ] A modified file without a patch is still `no_patch` (pinned).
- [ ] `assertAllowedArgs` admits only the exact `api /repos/<o>/<r>/contents/<path>?ref=<sha>` shape with the `Accept` header the adapter sets; a test rejects a path with `..`, a query other than `ref`, and a non-hex ref.
- [ ] SKILL.md's coverage section names the new source; CHANGELOG entry with bd-w5pd9.
**Dependencies:** none.

> Sources: `paged-fetch.ts:14-66, 120-150, 240-280`, `github-cli.ts:150-200, 290-307`, `ports/git-provider.ts:60-95` (Appendix B); PR #1296 round 1 coverage record; DEC-1015

### FR-4: Housekeeping merges classify `housekeeping` and prepare nothing (bd-nr5i6)
**Priority:** Must Have
**Description:** `classify_pr_type` (`classify-pr-type.sh:42-90`) returns `housekeeping` for rule 1a (a merge from an `owner/chore/…` branch or a `chore(archive|ledger|decisions):` subject) instead of `other` ([ASSUMPTION decision] (DEC-1016)). `classify-merge-pr.sh` passes the value through; its KF-063 guard (no PR number → `other`) is unchanged. `post-merge.yml` guards `simple-release` with `pr_type != 'cycle' && pr_type != 'housekeeping' && pr_number != ''`; `full-pipeline` keeps `pr_type == 'cycle' && pr_number != ''`; `notify` carries the value. The orchestrator is not changed (its own classifier branch maps unknown values to `other`, `:377-387`; it is never invoked for a housekeeping merge).
**Acceptance Criteria:**
- [ ] PCT-T28 … T32 and T38 expect `housekeeping`; T35 (`chore: bump deps`) still `other`; T33, T34, T36, T37, T39, T40 unchanged; the header lists four values.
- [ ] `classify-merge-pr.bats`: a housekeeping subject with a PR number emits `pr_type=housekeeping`; the no-PR ledger push still emits `other` (KF063-T1).
- [ ] `post-merge-workflow-guards.bats`: both prepare jobs skip for `housekeeping` (new case), `simple-release` still runs for `bugfix` and `other`, `full-pipeline` only for `cycle`; the comment near the guard names bd-nr5i6.
- [ ] `post-merge-orchestrator.sh --generate --type housekeeping` is refused with its usage error (pinned, so a future caller cannot prepare a housekeeping candidate by accident).
- [ ] CHANGELOG entry with bd-nr5i6; the live confirmation is recorded on the bead after the next housekeeping merge.
**Dependencies:** none.

> Sources: `classify-pr-type.sh:42-90`, `classify-merge-pr.sh:118-160`, `post-merge.yml:46-51, 106-109, 179-187, 255-270`, `post-merge-orchestrator.sh:290, 377-387`, `tests/unit/post-merge-classifier.bats`, `tests/unit/post-merge-workflow-guards.bats` (Appendix B); run 40255620297; DEC-1016

### FR-5: The performance guardrails measure CPU time (bd-oglcu)
**Priority:** Should Have
**Description:** The two guardrails in `progressive-truncation.test.ts` (`< 500 ms` around `progressiveTruncate`, `< 100 ms` around `detectLoa` + `applyLoaTierExclusion` over 100 files) measure `process.cpuUsage()` user + system time around the call instead of `performance.now()`, with the same thresholds ([ASSUMPTION decision] (DEC-1017)).
**Acceptance Criteria:**
- [ ] Both cases use CPU time; the assertion messages name it; a comment explains why (load-independent).
- [ ] `npm test` passes three consecutive full runs on the lead host while the implementers' worktrees are active.
- [ ] A deliberately quadratic stand-in (test-only) still trips the `< 100 ms` bound, so the regression signal is kept (one red-first demonstration in the report, not a permanent test).
**Dependencies:** none.

> Sources: `progressive-truncation.test.ts:548-590` (Appendix B); bd-oglcu (2026-10-26 observations: 102.1 ms, 115.2 ms, 146.1 ms under load; 5/5 alone); DEC-1017

### FR-6: Ship — one PR, a non-degraded Bridgebuilder verdict, record, archive, no release
**Priority:** Must Have
**Description:** After review and audit approve the sprint: one PR from `feature/cycle-135-review-coverage` with code, tests, docs, CHANGELOG, decision rows, ledger and the regenerated manifests and dist; a Bridgebuilder round (`BRIDGEBUILDER_MODEL=codex-headless`, excludes by prefix for generated files; ≤ 2 rounds; stop when the remaining budget is under USD 8); admin merge after every check run is green; record stage on a record branch; archive; no tag ([ASSUMPTION decision] (DEC-1018)).
**Acceptance Criteria:**
- [ ] The PR's Bridgebuilder summary has no `degraded_reason` and a consensus verdict; every finding is dispositioned in a triage comment.
- [ ] Every check run on the merged head is green; the merge classifies `cycle`.
- [ ] `record/cycle-135-review-coverage` stage 1 holds the a2a tree; the archive directory holds prd, sdd, sprint, ledger, CHANGELOG entries and README.
**Dependencies:** FR-1 … FR-5.

> Sources: cycle-135-brief.md § Standing rules; DEC-0960, DEC-1018; `~/.cache/loa/cycle-134/ship/` (the ship scripts to adapt)

---

## Non-Functional Requirements

### Performance

The matcher compiles one regex per pattern (memoized, sprint-bug-278) and runs one `path.matchesGlob` and at most one regex test per (file, pattern) pair; the content fetch adds one bounded `gh api` call per patch-less added file (never more than the file cap); the guardrails bound the hot paths in CPU time.

### Security

Patterns come from the operator (config, CLI, `.reviewignore` read from the reviewer's `repoRoot`); filenames and contents come from the PR author and are matched or displayed, never interpreted. FR-1 closes the substring hiding path; FR-2 keeps attack-prone paths in front of the reviewer by default; FR-3's fetch is bounded, allowlisted by shape, and refuses `..`, foreign queries and non-hex refs; FR-4 removes release-prep work for housekeeping merges without touching the publication contract (the approved digest is still required to publish anything).

### Reliability

Every change is pinned by a red-first test; the matcher's two runtimes are tested through one seam; the suite no longer depends on host load.

### Compliance

System Zone discipline (DEC-0824): bounded marker, `checksums.json`, `REPO-MAP.md` and the Bridgebuilder `dist/` regenerated in every fix commit; `tools/check-bb-dist-fresh.sh --check` fresh.

### Authorization basis and refusal list

The operator's instruction of 2026-10-26 (brief § Operator instruction) authorises the cycle through the golden path; the System Zone authorization carries over for `.claude/` and `.github/` writes. The refusal list of the brief applies unchanged.

> Sources: cycle-135-brief.md § Standing rules and refusals; `truncation.ts:277-350` (`.reviewignore` provenance); DEC-0824

---

## User Experience

### Key User Flows

- The operator reads a Bridgebuilder summary: the coverage section lists reviewed files, omissions with reasons, and now protected-kept files with the pattern that would have excluded them, and content-fetched files with `source: contents`.
- The operator reads a post-merge run on an archive merge: the classify step prints `pr_type=housekeeping`; both prepare jobs are skipped; the notify step carries the type.

### Interaction Patterns

No new commands. One new config key (`bridgebuilder.protected_paths`), documented with its default and the `[]` opt-out.

### Accessibility Requirements

Plain-text summaries and one-line refusals, as today.

> Sources: `paged-fetch.ts:400-410` (coverage rendering); `post-merge.yml:255-270`; SKILL.md § exclude_patterns

---

## Technical Considerations

### Architecture (for the SDD)

Five local changes in two systems: the Bridgebuilder skill (TypeScript, `resources/core/truncation.ts`, `resources/core/paged-fetch.ts`, `resources/adapters/github-cli.ts`, `resources/ports/git-provider.ts`, `resources/config.ts`, tests) and the post-merge pipeline (Bash classifier + workflow YAML + bats). No new component, no new interface except one provider method and one config key.

### System Zone authorization (explicit, cycle-level)

`.claude/skills/bridgebuilder-review/**`, `.claude/scripts/classify-pr-type.sh`, `.claude/scripts/classify-merge-pr.sh` and `.github/workflows/post-merge.yml` are System Zone; their edits run under the bounded marker (`.run/zone-guard-authorization.json`, scope framework, reason, expiry ≤ 2 h) with `checksums.json`, REPO-MAP and the Bridgebuilder `dist/` regenerated in the same commit (DEC-0824 carries over).

### Integrations

GitHub REST through `gh api` (one new allowlisted shape), GitHub Actions (`post-merge.yml`), the Bridgebuilder on the PR.

### Dependencies

Node 22.22 (host), `tsx` and `node:test` (skill dev deps), bats 1.13 via the npx cache, jq 1.7, Bash 5.2.

### Technical Constraints

Tests first; no live model calls by implementers; no new npm dependency; `.reviewignore` is read from the reviewer's checkout only; the publication contract (`validate_candidate_v2`) is untouched.

> Sources: cycle-135-brief.md § Grounding facts; `github-cli.ts:150-200`; DEC-0824

---

## Scope & Prioritization

### In Scope (MVP — this cycle)

FR-1 … FR-6 ([ASSUMPTION decision] (DEC-1011)).

### In Scope (Future Iterations)

Brace and character-class forms in the dot-agnostic matcher; content fetch for modified files without a patch (base + head diff); a `fix/`-branch rule for cycle-named bugfix branches.

### Out of Scope

Any release; the Loa tier's self-review policy; the orchestrator's candidate schema.

### Priority order under time pressure

FR-1 (security) → FR-4 → FR-2 → FR-5 → FR-3 → FR-6.

### Release-blocking status

Nothing in this cycle blocks a release; the rc.8 soak continues.

> Sources: cycle-135-brief.md § Scope; DEC-1011, DEC-1018

---

## Success Criteria

- G-1 … G-5 met with the evidence named in the sprint plan's goal table.
- The review and audit gates approve with every dissent payload dispositioned; the Bridgebuilder round's findings are triaged on the PR.
- The next housekeeping merge after the ship runs no prepare job (live, recorded on bd-nr5i6).

> Sources: § Goals & Success Metrics; sprint.md § Appendix (to be written)

---

## Risks & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| A default or operator pattern relied on substring matching | low | a file silently reviewed that was meant excluded (the safe direction) | CHANGELOG names the change; the coverage record shows what was reviewed |
| The protected list blocks an operator's legitimate exclusion | medium | noise in the review | `protected_paths` replaces the default; `[]` disables; the record names the pattern |
| The content fetch shape is refused by `assertAllowedArgs` in some `gh` versions | low | `no_patch` as today | the fetch falls back to today's omission; a test pins the shape |
| A consumer of `pr_type` rejects the fourth value | low | a red post-merge run | the workflow guards and notify are read and pinned; the orchestrator maps unknowns to `other` |
| CPU time includes GC noise | low | a rare false red | thresholds unchanged; three-run evidence on a loaded host |

> Sources: § Functional Requirements; `post-merge-orchestrator.sh:377-387`

---

## Timeline & Milestones

Planning (PRD, SDD, sprint plan, Flatline reviews) → Sprint 1 (global 279: three implementers in parallel, landing, review, audit) → ship (PR, Bridgebuilder, merge, record, archive). One day of unattended work.

> Sources: cycle-134's timeline (archive README); DEC-1018

---

## Appendix A — Decisions taken on the operator's behalf

| # | Decision | Row |
|---|----------|-----|
| D-1 | Scope: the five follow-ups; brace/class glob forms, `fix/` routing and releases out | DEC-1011 |
| D-2 | Grounding by direct file:line reads; no /ride | DEC-1012 |
| D-3 | Non-wildcard exclusion semantics: whole path segments, gitignore-like; one matcher on every Node version | DEC-1013 |
| D-4 | Protected paths: default list, user wildcard patterns only, configurable, named in the coverage record | DEC-1014 |
| D-5 | Patch-less added files fetched by content (bounded); other statuses unchanged | DEC-1015 |
| D-6 | `housekeeping` classifier value; both prepare jobs skip it; KF-063 guard and orchestrator unchanged | DEC-1016 |
| D-7 | Guardrails measure CPU time with the existing thresholds | DEC-1017 |
| D-8 | Cycle shape: one sprint, three implementers, one PR, Bridgebuilder round, record, archive, no release; cap USD 40 | DEC-1018 |

Standing decisions carried over: DEC-0824 (System Zone marker), DEC-0960 (per-sprint PRs), DEC-0999 (cap in the meter's unit), DEC-1009 (the accepted dot-led widening this cycle mitigates), DEC-1010 (the substring pin dropped). The rows of this cycle stay `proposed` until the operator confirms them (`/decisions confirm --cycle cycle-135-review-coverage-followups --all`, offered at the cycle close).

> Sources: `grimoires/loa/decisions.yaml` DEC-1011 … DEC-1018 (phase discovery, cycle `cycle-135-review-coverage-followups`, proposed, each sourced to this appendix)

---

## Appendix B — Grounding reads

All reads 2026-10-26 on `main 4256a1b3` (the lead, direct `sed -n` / `grep -n`; no /ride, DEC-1012):

- `.claude/skills/bridgebuilder-review/resources/core/truncation.ts:94-96` (`hasNativeGlob`, exported), `:101-141` (`simplifiedGlobMatch`), `:143-178` (`dotSegmentGlobMatch`, memoized), `:182-200` (`matchesExcludePattern`), `:261-278` (`LOA_EXCLUDE_PATTERNS`), `:277-350` (`parseReviewignoreFile`: `O_NOFOLLOW`, regular-file check, `repoRoot`), `:395` (`/` suffix → `**`), `:666`, `:1292-1318`, `:1442`, `:1515` (call sites).
- `.claude/skills/bridgebuilder-review/resources/core/paged-fetch.ts:14-66` (two-pass metadata, planning on recorded sizes), `:39-41` (`REVIEWABLE_OMISSION_REASONS`), `:120-150` (`exclusionReason`, `evaluateCoverage`, `omission`), `:240-280` (pass 2, retained files, coverage record), `:400-410` (rendering).
- `.claude/skills/bridgebuilder-review/resources/adapters/github-cli.ts:150-200` (`assertAllowedArgs`, `gh()` with `maxBuffer`), `:290-307` (`getPRFilesPage`: `patch` only when a string).
- `.claude/skills/bridgebuilder-review/resources/ports/git-provider.ts:60-95` (`IGitProvider`).
- `.claude/skills/bridgebuilder-review/resources/config.ts:1077-1142, 1300-1330, 1524-1537` (`exclude_patterns`, `max_files_per_pr`, defaults and YAML parsing).
- `.claude/skills/bridgebuilder-review/resources/__tests__/loa-detection.test.ts:368-450` (`LOA_EXCLUDE_PATTERNS`, dot-led segment cases), `progressive-truncation.test.ts:548-590` (guardrails).
- `.claude/scripts/classify-pr-type.sh:29-35` (rule list), `:42-90` (`classify_pr_type`); `.claude/scripts/classify-merge-pr.sh:118-170`; `.github/workflows/post-merge.yml:46-51, 106-109, 145-146, 179-187, 221-222, 255-270`; `.claude/scripts/post-merge-orchestrator.sh:290, 331-347, 377-387`.
- `tests/unit/post-merge-classifier.bats` (40 cases), `tests/unit/classify-merge-pr.bats` (31), `tests/unit/post-merge-workflow-guards.bats` (PMWG-T1 … T4).
- Live: Post-Merge Pipeline run 40255620297 on `b880a1cd` (classify `other`, "Prepare Release (Bugfix or Other)" success, cycle job skipped); PR #1296 round-1 log `~/.cache/loa/cycle-134/bb/round1.log` (`incomplete_coverage`, `no_patch` for `prd.md`/`sdd.md`).

> Sources: the lead's session transcript 2026-10-26; cycle-135-brief.md § Grounding facts
