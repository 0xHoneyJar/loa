# Software Design Document: Review-coverage follow-ups (cycle-135)

**Version:** 1.0
**Date:** 2026-10-26
**Author:** Architect Agent (Claude Fable 5.1, unattended)
**Status:** Draft 1.0 — autonomous run; design-level decisions taken on the operator's behalf are § 11.D D-1.1 … D-2.2 (DEC-1019 … DEC-1025); the PRD-level rows are DEC-1011 … DEC-1018
**PRD:** `grimoires/loa/prd.md` 1.0 (FR-1 … FR-6, G-1 … G-5)
**Brief:** `grimoires/loa/context/cycle-135-brief.md`
**Cycle:** `cycle-135-review-coverage-followups`; **branch:** `feature/cycle-135-review-coverage`

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

> Sources: this document's sections

---

## 1. Project Architecture

### 1.1 System Overview

Five local changes in two existing systems, no new component: the Bridgebuilder review skill (TypeScript 5.9 under Node 22.22, `.claude/skills/bridgebuilder-review/resources/**`, built to `dist/` by `npm run build`) and the post-merge pipeline (Bash 5.2 classifier `.claude/scripts/classify-pr-type.sh`, its wrapper `.claude/scripts/classify-merge-pr.sh`, the GitHub Actions workflow `.github/workflows/post-merge.yml`, tests in bats 1.13). The Bridgebuilder changes touch the file-selection layer (exclusion matching, protection, patch-less content) and the coverage record; the pipeline change adds one classifier value and one job guard.

> Sources: prd.md § Technical Considerations / Architecture; § 1.4 below

### 1.2 Architectural Pattern

Selection is a pure function of the PR's file list and the operator's configuration; everything a PR author controls (names, contents) is matched or displayed, never interpreted (D-1.1, D-1.2). Fetches are bounded and allowlisted by shape; a failed or oversized fetch degrades to today's behaviour, never to an exception (D-1.3). The classifier is a pure function of the merge subject and labels; the workflow consumes its output with explicit guards (D-1.4). Tests measure what the code does, not what the host does (D-1.5).

> Sources: prd.md § Non-Functional Requirements / Security, Reliability; DEC-1019 … DEC-1023

### 1.3 Component Diagram

```
 operator config ─ .reviewignore (repoRoot) ─ --exclude ─ exclude_patterns ─ protected_paths (default list)
        │
        ▼
 truncateFiles ── partitionUserExclusions(files, userPatterns, protectedPatterns)      [C-1, C-2]
        │             ├─ matchesExcludePattern(filename, patterns, {native})  ─ isWildcardPattern → native glob → dotSegmentGlobMatch
        │             │                                                        └ non-wildcard → segmentMatch (gitignore-like)
        │             └─ protectedKept[{file, pattern}]  ──► TruncationResult.protectedKept
        ▼
 paged-fetch pass 1 (metadata) ── eligible added file without patch ──► IGitProvider.getFileContent (gh api contents, raw, ≤ max_diff_bytes)   [C-3]
        │                                                                 └─ text → synthesized patch (+patchBytes, source: contents) │ binary/too_large/error → unchanged
        ▼
 selection → pass 2 (patches) → CoverageRecord { reviewed[{file, bytes, hunks, source?}], omitted, protected_kept, degraded … } → PR summary

 post-merge.yml: classify (classify-merge-pr.sh → classify_pr_type: cycle | bugfix | housekeeping | other; no PR → other)   [C-4]
                 ├─► simple-release  [pr_type != 'cycle' && pr_type != 'housekeeping' && pr_number != '']
                 └─► full-pipeline   [pr_type == 'cycle' && pr_number != '']
                 post-merge-orchestrator.sh --type housekeeping → "Invalid --type" (exit 1, existing check)

 progressive-truncation.test.ts guardrails: process.cpuUsage() around the measured call   [C-5]
```

> Sources: the file:line reads in § 1.4

### 1.4 Components

| ID | Component | Where (read 2026-10-26) | Change |
|---|---|---|---|
| C-1 | Exclusion matcher | `.claude/skills/bridgebuilder-review/resources/core/truncation.ts:94-200` (`hasNativeGlob`, `simplifiedGlobMatch`, `dotSegmentGlobMatch`, `matchesExcludePattern`), `:261-278` (`LOA_EXCLUDE_PATTERNS`), `:395` (`.reviewignore` `/` → `**`) | `isWildcardPattern(p) = /[*?{[]/.test(p)`; `segmentMatch(filename, p)`: strip one trailing `/`; no `/` in `p` → `("/" + filename + "/").includes("/" + p + "/")`; otherwise `filename === p || filename.startsWith(p + "/")`; wildcard → `(native && path.matchesGlob(filename, p)) || dotSegmentGlobMatch(filename, p)`; `matchesExcludePattern(filename, patterns, opts?: { native?: boolean })`, `opts.native ?? hasNativeGlob`; `simplifiedGlobMatch` deleted; doc comment states the semantics (D-1.1) |
| C-2 | Protected paths | `truncation.ts:1292-1318, 1442, 1515` (user-pattern call sites), `config.ts:1100-1142, 1300-1330, 1524-1537` (defaults, YAML keys, merge), `types.ts` (`TruncationResult`, `CoverageRecord`), `paged-fetch.ts:400-410` (rendering) | `export const DEFAULT_PROTECTED_PATHS = [".github/workflows/**", ".github/actions/**", ".claude/settings.json", ".claude/settings.local.json", ".claude/hooks/**", ".husky/**"]`; `partitionUserExclusions(files, userPatterns, protectedPatterns) → { excluded: Array<{file, pattern}>, protectedKept: Array<{file, pattern}> }` — a file is kept when the first matching user pattern is a wildcard and the file matches a protected pattern (same matcher); applied at the three call sites; `truncateFiles` returns `protectedKept`; config key `protected_paths?: string[]` → `protectedPaths: string[]` (set → replaces the default; `[]` disables); paged-fetch copies to `coverage.protected_kept` and renders "Protected paths kept (n)" with file and pattern (D-1.2); the Loa tier call (`:666`) is untouched |
| C-3 | Patch-less added files | `paged-fetch.ts:14-66` (pass 1), `:240-280` (pass 2, coverage), `github-cli.ts:150-200` (`assertAllowedArgs`, `gh()`), `:290-307` (`getPRFilesPage`), `ports/git-provider.ts:60-95` | `IGitProvider.getFileContent(owner, repo, path, ref, maxBytes): Promise<FileContentResult>` with `FileContentResult = { kind: "text"; content: string; bytes: number } | { kind: "binary" } | { kind: "too_large" }`; adapter: `gh api -H "Accept: application/vnd.github.raw+json" /repos/<o>/<r>/contents/<path percent-encoded per segment>?ref=<40-hex>` with `maxBuffer = maxBytes + 1024`; `assertAllowedArgs` admits exactly that shape (path segments without `..`, no leading `/`, no `?`/`#`; ref `^[0-9a-f]{40}$`; the single `-H` value fixed); pass 1: for each listed file with `status === "added" && patch == null && additions > 0`, in listing order and at most `maxFilesPerPr` fetches, `getFileContent(…, pin.head_sha, maxDiffBytes)`; text (no NUL in the first 8 KiB, valid UTF-8 via `TextDecoder("utf-8", { fatal: true })`) → `patch = "@@ -0,0 +1,N @@\n" + lines.map(l => "+" + l).join("\n")`, `patchBytes = utf8Bytes(patch)`, `source: "contents"` carried on the metadata entry and pre-retained for pass 2; `binary`, `too_large` or an error → the entry stays as listed (today's `no_patch` at selection); coverage `reviewed[].source?: "contents"` (D-1.3) |
| C-4 | Housekeeping classification | `classify-pr-type.sh:29-35, 42-90`, `classify-merge-pr.sh:118-170`, `post-merge.yml:46-51, 106-109, 179-187, 255-270`, `post-merge-orchestrator.sh:2491-2492` | rule 1a echoes `housekeeping`; header grammar `pr_type=<cycle|bugfix|housekeeping|other>`; the wrapper's no-PR guard still forces `other` (KF-063); `simple-release` `if: needs.classify.outputs.pr_type != 'cycle' && needs.classify.outputs.pr_type != 'housekeeping' && needs.classify.outputs.pr_number != ''`; `full-pipeline` unchanged; a comment at the guard names bd-nr5i6; the orchestrator's existing validation refuses `--type housekeeping` ("Invalid --type", exit 1) — pinned by a bats case, no code change (D-1.4) |
| C-5 | CPU-time guardrails | `progressive-truncation.test.ts:548-590` | `const t0 = process.cpuUsage(); … ; const u = process.cpuUsage(t0); const ms = (u.user + u.system) / 1000;` in both cases; thresholds 500 ms and 100 ms unchanged; assertion message names CPU time; comment names bd-oglcu (D-1.5) |

> Sources: prd.md FR-1 … FR-5; the reads in § 11.E; DEC-1019 … DEC-1023

---

## 2. Software Stack

### 2.1 Languages and runtimes

TypeScript 5.9 compiled by `tsc` to ES modules in `dist/` (Node 22.22 on the lead host; the skill's `engines.node` is `>= 20.0.0`, so the matcher must behave identically without `path.matchesGlob` — D-1.1); Bash 5.2 for the classifier and wrapper; YAML for `post-merge.yml` (GitHub Actions); bats 1.13 for shell tests; `node:test` via tsx 4.21 for the skill's tests; jq 1.7 in the workflow's notify step.

### 2.2 Build and verification

`npm run build` in the skill (`gen-bb-registry`, `tsc`, `tools/check-bb-dist-fresh.sh --write-manifest`); `tools/check-bb-dist-fresh.sh --check`; `tools/gen-checksums.sh --check`; `.claude/scripts/repo-map-gen.sh --validate`; `tools/check-manifest-paths.sh`. All under the bounded System Zone marker (DEC-0824).

### 2.3 External services

GitHub REST through the `gh` CLI (`gh api`, allowlisted shapes), GitHub Actions. No new npm dependency.

> Sources: `.claude/skills/bridgebuilder-review/package.json` (typescript ^5.9.3, tsx ^4.21.0, node >= 20); `tools/check-bb-dist-fresh.sh`; DEC-0824

---

## 3. Database Design

No database. Two JSON records change shape, both written by the Bridgebuilder and read by its rendering and by the operator:

- `CoverageRecord` (types.ts): `reviewed: Array<{ file; bytes; hunks; source?: "contents" }>`; new optional `protected_kept: Array<{ file: string; pattern: string }>`. Absent fields mean "none" (older records stay readable).
- `TruncationResult` (types.ts): new optional `protectedKept: Array<{ file: string; pattern: string }>`.

The lead adds both fields in a contract commit before dispatch (D-2.1) so A (producer) and B (consumer) compile against one definition. The `BridgebuilderConfig` gains `protectedPaths: string[]` (default `DEFAULT_PROTECTED_PATHS`); YAML key `bridgebuilder.protected_paths`.

> Sources: `types.ts:20-40, 291-300`; `config.ts:1100-1142`; DEC-1020, DEC-1024

---

## 4. UI Design

The PR summary's coverage section gains two things: a "Protected paths kept (n)" list (`file — kept despite pattern`) after the omissions, and a `(source: contents)` marker on reviewed entries whose patch was synthesized. The post-merge run's classify step prints `pr_type=housekeeping` for housekeeping merges and both prepare jobs show as skipped; the notify step carries the type unchanged. No new command-line flags; one new configuration key documented in the skill's SKILL.md with its default list and the `[]` opt-out.

> Sources: `paged-fetch.ts:400-410`; `post-merge.yml:255-270`; prd.md § User Experience

---

## 5. API Specifications

### 5.1 `matchesExcludePattern(filename, patterns, opts?)`

Input: a repository-relative filename (GitHub's `filename`), a list of patterns, optional `{ native?: boolean }`. Output: boolean. Semantics (D-1.1): non-wildcard patterns match whole segments (gitignore-like, § 1.4 C-1); wildcard patterns match through the native glob when enabled and through the dot-agnostic segment matcher otherwise or in addition. Pure; memoized regexes per pattern.

### 5.2 `partitionUserExclusions(files, userPatterns, protectedPatterns)`

Returns `{ excluded, protectedKept }` with the matching pattern recorded for every entry. A protected pattern is matched with the same matcher. A non-wildcard user pattern that names a protected file excludes it.

### 5.3 `IGitProvider.getFileContent(owner, repo, path, ref, maxBytes)`

`gh api -H "Accept: application/vnd.github.raw+json" /repos/{owner}/{repo}/contents/{path}?ref={ref}`; `path` percent-encoded per segment (no `..`, no leading `/`, no `?`/`#`), `ref` a 40-hex commit; `maxBuffer = maxBytes + 1024`; a response longer than `maxBytes` → `{ kind: "too_large" }`; a NUL in the first 8 KiB or invalid UTF-8 → `{ kind: "binary" }`; otherwise `{ kind: "text", content, bytes }`. Errors propagate as `GitProviderError` and are caught at the call site (→ no fetch, metadata unchanged).

### 5.4 Classifier output grammar

`pr_type=<cycle|bugfix|housekeeping|other>` and `pr_number=<digits or empty>` on stdout and in `$GITHUB_OUTPUT`. `housekeeping` is produced only by rule 1a with a PR number; a push without a PR is `other` (KF-063). Consumers: `post-merge.yml` (two guards, notify), nothing else in-tree (the orchestrator receives `--type` only from the two prepare jobs, which never run for housekeeping; its own validation refuses the value).

### 5.5 Configuration

`bridgebuilder.protected_paths: string[]` — when present it replaces `DEFAULT_PROTECTED_PATHS`; `[]` disables protection. Parsed like `exclude_patterns` (`config.ts:1300-1330`).

> Sources: § 1.4; `github-cli.ts:150-200`; `classify-merge-pr.sh:160-170`; `config.ts:1300-1330`; DEC-1019 … DEC-1022

---

## 6. Error Handling Strategy

- Matcher: no exceptions; an invalid pattern shape cannot occur (strings are escaped before compilation); a pattern that compiles to nothing matches nothing.
- Protected paths: never throw; a kept file is recorded; an unknown config type for `protected_paths` is a config error at load, as for `exclude_patterns`.
- Content fetch: `GitProviderError` (network, auth, 404 for a path that moved between listing and fetch, buffer overflow) is caught per file and logged at info; the file keeps today's `no_patch` treatment. The head-sha pin is re-checked after pass 1 as today (`recheck`), so a moved head still restarts the fetch.
- Classifier/workflow: an unexpected `pr_type` value skips both prepare jobs (both guards are positive/negative lists that exclude it) and the notify step still reports; the orchestrator refuses an unknown `--type` with exit 1.
- Guardrails: a CPU-time threshold trip is a real regression; the message names the measured milliseconds and the bound.

> Sources: `paged-fetch.ts:240-250` (`recheck`); `post-merge-orchestrator.sh:2491-2492`; prd.md § Non-Functional Requirements

---

## 7. Testing Strategy

Red first for every acceptance criterion; the red commit lands alone, the fix after (`red-test-check.sh` where the runner allows — `bats` from the npx cache on PATH; `npm test` through the manual detached-worktree equivalent when nested `node_modules` is needed, DEC-1007 shape).

| FR | Tests (file) | Red-first cases |
|---|---|---|
| FR-1 | `loa-detection.test.ts` | `util.loa-version.json.ts`, `x/.loa-version.json.bak`, `MYPROCESS.md`, `PROCESS.md.old` not excluded by the defaults; `docs/PROCESS.md`, `BUTTERFREEZONE.md` excluded; `a/b` vs `a/b/c` and `x/a/b`; trailing `/` normalisation; identical results with `{ native: false }` for every dot-segment, globstar, single-`*` and non-wildcard case (the skipped case un-skipped); `simplifiedGlobMatch` absent (`typeof` import check or grep in a bats guard) |
| FR-2 | `loa-detection.test.ts`, `truncation.test.ts` | `**/*.yml` keeps `.github/workflows/ci.yml` with `protectedKept = [{file, pattern}]`; exact `.github/workflows/ci.yml` excludes it; `protected_paths: []` disables; a custom list protects only its entries; the Loa tier still strips `.claude/settings.json` without self-review; the rendered summary lists protected-kept files |
| FR-3 | `paged-fetch.test.ts` (provider double), `github-cli.test.ts` | an added file without a patch and served content → reviewed with the synthesized patch, `source: "contents"`, not degraded; binary → `no_patch`; too large → `no_patch`; provider error → `no_patch`; a modified file without a patch → `no_patch` (pinned); `assertAllowedArgs` accepts the exact shape and rejects `..`, a foreign query, a non-hex ref and a different `Accept` value |
| FR-4 | `post-merge-classifier.bats`, `classify-merge-pr.bats`, `post-merge-workflow-guards.bats`, `post-merge-publication.bats` (or a new `post-merge-orchestrator-type.bats`) | PCT-T28 … T32, T38 → `housekeeping`; T35 → `other`; the rest unchanged; wrapper: housekeeping subject with PR → `pr_type=housekeeping`, no-PR push → `other`; guards: both prepare jobs skip `housekeeping`, `simple-release` runs for `bugfix`/`other`, `full-pipeline` for `cycle` only; orchestrator `--type housekeeping` → exit 1 "Invalid --type" |
| FR-5 | `progressive-truncation.test.ts` | both guardrails on CPU time; three consecutive green full runs on the loaded host recorded in the report; a report-only quadratic stand-in trips the 100 ms bound |

Suites run at landing: `npm test` and `npx tsc --noEmit -p resources/tsconfig.json` in the skill; `npx --no-install bats tests/unit/post-merge-classifier.bats tests/unit/classify-merge-pr.bats tests/unit/post-merge-workflow-guards.bats tests/unit/post-merge-publication.bats`; `bash -n` on the shell files; the full local CI mirror (`~/.cache/loa/cycle-134/scripts/s-tests.sh all`, adapted) before the PR.

> Sources: prd.md § Functional Requirements (acceptance criteria); DEC-1007; `~/.cache/loa/cycle-134/scripts/s-tests.sh`

---

## 8. Development Phases

One sprint (global 279). Lead prep: the contract commit (D-2.1: `types.ts` fields, dist and manifests regenerated under the marker). Then three Opus 5.5 implementers in worktrees from that commit, disjoint allowlists (D-2.2):

| Implementer | Owns | Tasks |
|---|---|---|
| A | `resources/core/truncation.ts`, `resources/config.ts`, `resources/__tests__/loa-detection.test.ts`, `resources/__tests__/truncation.test.ts`, `SKILL.md` (the exclusion / protected-paths text) | FR-1 (C-1), FR-2 (C-2 except the coverage copy and rendering) |
| B | `resources/core/paged-fetch.ts`, `resources/adapters/github-cli.ts`, `resources/ports/git-provider.ts`, their tests, `resources/__tests__/progressive-truncation.test.ts` | FR-3 (C-3), the coverage copy and rendering of `protectedKept` (reads `sel.protectedKept ?? []`), FR-5 (C-5) |
| C | `.claude/scripts/classify-pr-type.sh`, `.claude/scripts/classify-merge-pr.sh` (comment only), `.github/workflows/post-merge.yml`, `tests/unit/post-merge-classifier.bats`, `tests/unit/classify-merge-pr.bats`, `tests/unit/post-merge-workflow-guards.bats`, the orchestrator pin test | FR-4 (C-4) |
| lead | landing (A → B → C), dist rebuild, manifests, CHANGELOG, DEC rows from the reports, review, audit, PR, Bridgebuilder, merge, record, archive | FR-6 |

Landing order A → B → C: B's rendering reads A's field through the contract commit, so either order compiles; A first keeps the matcher change reviewable on its own.

> Sources: prd.md § Timeline & Milestones; DEC-1024, DEC-1025

---

## 9. Known Risks and Mitigation

| Risk | Mitigation |
|---|---|
| `gh api` with the raw media type returns JSON instead of raw bytes for some `gh` versions | the adapter checks the first bytes: a JSON object with `content`/`encoding` fields is decoded from base64 as a fallback (one bounded decode); a test covers both shapes (Q-1) |
| The contents endpoint caps raw responses at 1 MiB and returns an error above it | treated as `too_large` → `no_patch` as today; `max_diff_bytes` is far below 1 MiB in practice |
| A protected pattern in the default list matches nothing in a given repository | no cost; the list is documentation of intent |
| A non-wildcard default that relied on substring matching | none known (the six defaults are root-level file names); the CHANGELOG names the change |
| The skill's tests mock `path.matchesGlob` absence through `opts.native` only | the real Node 20 path is the same function with `native=false`; CI runs on Node 22 — documented |
| `post-merge-workflow-guards.bats` greps the YAML text | the guard text is written exactly as the test expects and the test is updated in the same patch |

> Sources: § 5.3; `post-merge-workflow-guards.bats`; prd.md § Risks & Mitigation

---

## 10. Open Questions

- **Q-1** Does `gh api -H "Accept: application/vnd.github.raw+json"` on the lead host's `gh` version return the raw file bytes on stdout? Implementer B verifies with one read-only call against a public file of this repository at a known sha and records the shape; the adapter handles both the raw and the base64-JSON shape (§ 9).
- **Q-2** Should the Loa tier's six non-wildcard defaults also match at any depth (`docs/PROCESS.md`)? Decided yes by D-3 (DEC-1013) for consistency with gitignore; the test pins it; the operator may narrow later.
- **Q-3** Does any downstream consumer read `pr_type` from the notify payload and switch on it? Implementer C greps the repository (`pr_type`, `PM_PR_TYPE`) and reports; none is known in-tree.

> Sources: § 5.3, § 5.4; DEC-1013

---

## 11. Appendix

### 11.D Design decisions taken on the operator's behalf

| # | Decision | Row |
|---|---|---|
| D-1.1 | Matcher structure: wildcard / non-wildcard branch, segmentMatch, native seam, `simplifiedGlobMatch` deleted | DEC-1019 |
| D-1.2 | Protected paths: default list, one helper at the user-pattern call sites, `protectedKept` on the truncation result and coverage record, config replaces the default | DEC-1020 |
| D-1.3 | Content fetch in pass 1 for added files without a patch; bounded; synthesized patch; failures leave today's behaviour | DEC-1021 |
| D-1.4 | `housekeeping` wiring: classifier, wrapper pass-through, `simple-release` guard, orchestrator refusal pinned | DEC-1022 |
| D-1.5 | CPU-time guardrails with unchanged thresholds | DEC-1023 |
| D-2.1 | Lead contract commit for the shared types before dispatch | DEC-1024 |
| D-2.2 | Three disjoint implementer allowlists | DEC-1025 |

> Sources: `grimoires/loa/decisions.yaml` DEC-1019 … DEC-1025 (phase architecture, cycle `cycle-135-review-coverage-followups`, proposed, sourced to this section)

### 11.E Grounding reads

See prd.md Appendix B (all reads 2026-10-26 on `main 4256a1b3`); additionally for this document: `types.ts:20-40` (`CoverageRecord`), `:291-300` (`TruncationResult`); `post-merge-orchestrator.sh:2429` (`--type` parsing), `:2491-2492` (validation, exit 1); `package.json` of the skill (versions).

> Sources: the lead's session transcript 2026-10-26

### 11.F Flatline SDD review dispositions

Appended after the Flatline SDD review (1.0 → 1.1).

> Sources: `grimoires/loa/a2a/flatline/cycle-135-sdd-review.json` (after the review)
