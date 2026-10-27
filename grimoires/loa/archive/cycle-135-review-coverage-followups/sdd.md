# Software Design Document: Review-coverage follow-ups (cycle-135)

**Version:** 1.2
**Date:** 2026-10-26
**Author:** Architect Agent (Claude Fable 5.1, unattended)
**Status:** Draft 1.1 — autonomous run; design-level decisions taken on the operator's behalf are § 11.D D-1.1 … D-2.2 (DEC-1019 … DEC-1025) and the Flatline-driven amendments D-1.1a … D-1.5a (DEC-1026 … DEC-1031); the PRD-level rows are DEC-1011 … DEC-1018
**Flatline:** `grimoires/loa/a2a/flatline/cycle-135-sdd-review.json` (2/2 voices, cross-scoring degraded — KF-041 shape; 5 skeptic blockers, 40 medium items, every one read and dispositioned in § 11.F)
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

Selection is a pure function of the PR's file list and the operator's configuration, where `.reviewignore` is the base ref's copy, not the PR head's (D-1.2a); everything a PR author controls (names, contents, the head's `.reviewignore`) is matched, displayed or reviewed, never interpreted (D-1.1a, D-1.2). Fetches are bounded and allowlisted by shape; a failed or oversized fetch degrades to today's behaviour, never to an exception (D-1.3). The classifier is a pure function of the merge subject and labels; the workflow consumes its output with explicit guards (D-1.4). Tests measure what the code does, not what the host does (D-1.5).

> Sources: prd.md § Non-Functional Requirements / Security, Reliability; DEC-1019 … DEC-1023

### 1.3 Component Diagram

```
 operator config ─ .reviewignore (PR base sha via git show; the checkout only when no base) ─ --exclude ─ exclude_patterns ─ protected_paths ─ fetch_missing_patches ─ max_content_fetches
        │
        ▼
 truncateFiles ── partitionUserExclusions(files, userPatterns, protectedPatterns)      [C-1, C-2]
        │             ├─ matchesExcludePattern(filename, patterns)  ─ isWildcardPattern → dotSegmentGlobMatch (the one grammar: * ** ? {a,b} [..]; others rejected at load)
        │             │                                              └ non-wildcard → segmentMatch (gitignore-like)
        │             └─ protectedKept[{file, pattern}]  ──► TruncationResult.protectedKept
        ▼
 paged-fetch pass 1 (metadata → exclusions with protection → eligible added file without patch) ──► IGitProvider.getFileContent (gh api contents JSON envelope, base64; size ≤ bound; ≤ max_content_fetches; 120 s deadline)   [C-3]
        │                                                                 └─ text → synthesized patch (+patchBytes, source: contents) │ binary/too_large/error/skipped_cap/deadline → unchanged, outcome recorded
        ▼
 selection → pass 2 (patches) → CoverageRecord { reviewed[{file, bytes, hunks, source?}], omitted, protected_kept, degraded … } → PR summary

 post-merge.yml: classify (classify-merge-pr.sh → classify_pr_type: cycle | bugfix | housekeeping | other; no PR → other)   [C-4]
                 ├─► simple-release  [(pr_type == 'bugfix' || pr_type == 'other') && pr_number != '']   (allowlist: unknown values prepare nothing)
                 └─► full-pipeline   [pr_type == 'cycle' && pr_number != '']
                 post-merge-orchestrator.sh --type housekeeping → "Invalid --type" (exit 1, existing check)

 progressive-truncation.test.ts guardrails: min of 3 × process.cpuUsage() around the measured synchronous call   [C-5]
```

> Sources: the file:line reads in § 1.4

### 1.4 Components

| ID | Component | Where (read 2026-10-26) | Change |
|---|---|---|---|
| C-1 | Exclusion matcher | `.claude/skills/bridgebuilder-review/resources/core/truncation.ts:94-200` (`hasNativeGlob`, `simplifiedGlobMatch`, `dotSegmentGlobMatch`, `matchesExcludePattern`), `:261-278` (`LOA_EXCLUDE_PATTERNS`), `:395` (`.reviewignore` `/` → `**`) | pattern normalisation at load (every source): trim; strip one leading `./` or `/`; reject `!` lines and constructs outside the grammar (extglob `+( @( !( ?( *(`, nested braces, backslash escapes) with one WARN naming the pattern — a rejected pattern matches nothing; the `.reviewignore` `/` → `**` conversion at `:395` is removed (a directory line is a non-wildcard segment pattern). `isWildcardPattern(p) = /[*?{[]/.test(p)`; `segmentMatch(filename, p)`: strip one trailing `/`; no `/` in `p` → `("/" + filename + "/").includes("/" + p + "/")`; otherwise `filename === p || filename.startsWith(p + "/")`; wildcard → `dotSegmentGlobMatch(filename, p)` only (`path.matchesGlob` is no longer called; `hasNativeGlob` removed), where `dotSegmentGlobMatch` gains one level of brace alternation (`{a,b}` → `(?:a|b)`, no nesting) and character classes (`[ab]` passed through, `[!ab]` → `[^ab]`) on top of the sprint-bug-278 segment translation; `matchesExcludePattern(filename, patterns)` (no options); `simplifiedGlobMatch` deleted; doc comment states the grammar (D-1.1, D-1.1a) |
| C-2 | Protected paths | `truncation.ts:1292-1318, 1442, 1515` (user-pattern call sites), `config.ts:1100-1142, 1300-1330, 1524-1537` (defaults, YAML keys, merge), `types.ts` (`TruncationResult`, `CoverageRecord`), `paged-fetch.ts:400-410` (rendering) | `export const DEFAULT_PROTECTED_PATHS = [".github/workflows/**", ".github/actions/**", ".claude/settings.json", ".claude/settings.local.json", ".claude/hooks/**", ".husky/**"]`; `export const DEFAULT_PROTECTED_PATHS = [".github/workflows/**", ".github/actions/**", ".github/CODEOWNERS", ".claude/settings.json", ".claude/settings.local.json", ".claude/hooks/**", ".husky/**", ".reviewignore"]`; `partitionUserExclusions(files, userPatterns, protectedPatterns) → { excluded: Array<{file, pattern}>, protectedKept: Array<{file, pattern}> }` — order-independent: all matching user patterns are resolved first; a file matched by any non-wildcard user pattern is excluded (that pattern recorded); otherwise, if it matches a protected pattern (same matcher) and only wildcard user patterns matched it, it is kept with the first matching wildcard recorded; otherwise excluded by the first match; applied at the three user-pattern sites (the call expressions `matchesExcludePattern(f.filename, userPatterns)` in the self-review branch, the non-Loa branch and the fail-closed path — function names in the implementer report, not line numbers); protected-kept files are placed first in the selection order; `truncateFiles` receives `protectedPaths` through its existing config object (`SelectionConfig`/`BridgebuilderConfig.protectedPaths`, contract commit) and returns `protectedKept`; `protected_paths` validated at load (non-empty strings, `./` or `/` stripped, no `..`; else a config error naming the entry); `parseReviewignoreFile(repoRoot, { baseSha? })` reads `git show <baseSha>:.reviewignore` (bounded, same checks) when a base sha is known and the checkout file otherwise, returning `{ patterns, source: "base" | "checkout" | "none" }`; paged-fetch copies `protectedKept` to `coverage.protected_kept`, sets `coverage.reviewignore_source` and `coverage.reviewignore_changed_in_pr` (the PR's file list contains `.reviewignore`), and renders "Protected paths kept (n)" with file, pattern and the file's final status (D-1.2, D-1.2a); the Loa tier call (`applyLoaTierExclusion`) is untouched except that its omissions now carry the matching default pattern |
| C-3 | Patch-less added files | `paged-fetch.ts:14-66` (pass 1), `:240-280` (pass 2, coverage), `github-cli.ts:150-200` (`assertAllowedArgs`, `gh()`), `:290-307` (`getPRFilesPage`), `ports/git-provider.ts:60-95` | `IGitProvider.getFileContent?(owner, repo, path, ref, maxBytes): Promise<FileContentResult>` — optional on the port (a provider or double without it → no fetch); `FileContentResult` declared in `ports/git-provider.ts`: `{ kind: "text"; content: string; bytes: number } | { kind: "binary" } | { kind: "too_large" }`; adapter: `gh api /repos/<o>/<r>/contents/<path percent-encoded per segment>?ref=<40-hex>` (default JSON media type, no `-H`), output taken as bytes with `maxBuffer = ceil(maxBytes × 4/3) + 4096` (an overflow → `too_large`), parsed as a JSON envelope validated strictly (`type === "file"`, `encoding === "base64"` else `too_large` for `"none"`, `size` a non-negative integer, `size > maxBytes → too_large`, `content` a string), base64 decoded to bytes (malformed → error), binary test on the bytes (NUL in the first 8 KiB or `TextDecoder("utf-8", { fatal: true })` failure), decoded to a string only afterwards; `assertAllowedArgs` admits exactly that shape — owner/repo segments `[A-Za-z0-9_.-]+`, path validated before encoding (no empty or `.`/`..` segment, no leading `/`, no `?`, `#` or control character) and the canonical decoded request re-checked, ref `^[0-9a-f]{40}$`, no headers; pass 1: after the Loa-tier and user exclusions (with protection) are applied to the metadata list, for each surviving file with `status === "added" && patch == null && additions > 0`, in listing order, at most `maxContentFetches` (config `max_content_fetches`, default 20) within a 120 s deadline, `getFileContent(baseOwner, baseRepo, path, pin.head_sha, remainingBudget)` where `remainingBudget = min(maxDiffBytes, maxDiffBytes − bytes already planned for synthesized patches)`; text → `patch = "@@ -0,0 +1,N @@\n" + lines.map(l => "+" + l).join("\n")` (+ `\n\\ No newline at end of file` when the content lacks a final newline; CRLF kept; `N` = line count), `patchBytes = utf8Bytes(patch)` (must fit the remaining budget, else `too_large`), `source: "contents"` carried on the metadata entry and pre-retained for pass 2 pinned to `pin.head_sha` (discarded when the post-pass-1 re-check restarts); `binary`, `too_large`, error, `skipped_cap` (beyond the cap) or `deadline` → the entry stays as listed (today's `no_patch` at selection) with `omitted[].fetch` set to the outcome; `bridgebuilder.fetch_missing_patches: false` skips the whole step; coverage `reviewed[].source?: "contents"` (D-1.3, D-1.3a, D-1.3b) |
| C-4 | Housekeeping classification | `classify-pr-type.sh:29-35, 42-90`, `classify-merge-pr.sh:118-170`, `post-merge.yml:46-51, 106-109, 179-187, 255-270`, `post-merge-orchestrator.sh:2491-2492` | rule 1a echoes `housekeeping`; header grammar `pr_type=<cycle|bugfix|housekeeping|other>`; the wrapper's no-PR guard still forces `other` (KF-063); `simple-release` `if: (needs.classify.outputs.pr_type == 'bugfix' || needs.classify.outputs.pr_type == 'other') && needs.classify.outputs.pr_number != ''` (allowlist, D-1.4a); `full-pipeline` unchanged; a comment at the guard names bd-nr5i6; `post-merge-workflow-guards.bats` pins the guard text and evaluates a shell mirror of both expressions over {cycle, bugfix, other, housekeeping, unknown, empty} × {PR number, none}; the workflow is parsed with yq and linted with actionlint when installed; the orchestrator's existing validation refuses `--type housekeeping` ("Invalid --type", exit 1) — pinned by `tests/unit/post-merge-orchestrator-type.bats`, no code change (1.1 → 1.2, implementer C: its own classifier branch at `:377` would assign `housekeeping` directly rather than map it to `other`, but that branch is unreachable from `main` — `--generate` requires both `--pr` and `--type` — and candidate validation refuses the value; recorded, not fixed); Q-3 (consumers of `pr_type` / `PM_PR_TYPE`) is a gate: a consumer that would misroute `housekeeping` is returned to the lead before C's fix patch lands — passed, inventory in `a2a/sprint-279/reviewer.md` (D-1.4, D-1.4a) |
| C-5 | CPU-time guardrails | `progressive-truncation.test.ts:548-590` | both cases run the measured synchronous call three times, each with `const t0 = process.cpuUsage(); … ; const u = process.cpuUsage(t0); ms = (u.user + u.system) / 1000`, and assert `Math.min(...samples)` against the unchanged thresholds (500 ms, 100 ms); the assertion message names CPU time; a comment names bd-oglcu and the GC/JIT-thread caveat; the report-only negative control is an O(n²) loop over the 100-file list that must fail the 100 ms bound; the three green full runs are recorded under a stated load (two concurrent `npm test` runs in the other worktrees) (D-1.5, D-1.5a) |

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

- `CoverageRecord` (types.ts): `reviewed: Array<{ file; bytes; hunks; source?: "contents" }>`; `omitted: Array<{ file; reason; reviewable; pattern?: string; fetch?: "binary" | "too_large" | "error" | "skipped_cap" | "deadline" }>` (`pattern` = the default or user pattern that excluded the file; `fetch` = the outcome of an attempted content fetch); new optional `protected_kept: Array<{ file: string; pattern: string }>`, `reviewignore_source?: "base" | "checkout" | "none"`, `reviewignore_changed_in_pr?: boolean`. All additive and optional (older records stay readable); consumers: the summary renderer in `paged-fetch.ts`, the coverage assertions in `paged-fetch.test.ts`, the triage reader (humans).
- `TruncationResult` (types.ts): new optional `protectedKept: Array<{ file: string; pattern: string }>`.
- `BridgebuilderConfig` (types.ts): `protectedPaths: string[]`, `fetchMissingPatches: boolean` (default true), `maxContentFetches: number` (default 20); `SelectionConfig` (paged-fetch.ts, B) extends its `Pick` with the three.
- `FileContentResult` and the optional `getFileContent?` live in `ports/git-provider.ts` (B).

The lead's contract commit (D-2.1) adds every `types.ts` field above (`CoverageRecord`, `TruncationResult`, `BridgebuilderConfig`) so A (producer) and B (consumer) compile against one definition; YAML keys `bridgebuilder.protected_paths`, `bridgebuilder.fetch_missing_patches`, `bridgebuilder.max_content_fetches` (A parses `protected_paths`; B parses the two fetch keys — both in `config.ts`, so A owns the parsing of all three to keep `config.ts` single-owner, with the values documented in the contract commit's report). The lead also runs the Q-1 probe in the contract-commit step and records the envelope shape.

> Sources: `types.ts:20-40, 291-300`; `config.ts:1100-1142`; DEC-1020, DEC-1024

---

## 4. UI Design

The PR summary's coverage section gains: a "Protected paths kept (n)" list (`file — kept despite <pattern>`, with `then omitted (<reason>)` appended when the file was later cut by a budget) after the omissions; a `(source: contents)` marker on reviewed entries whose patch was synthesized; the excluding pattern on Loa-tier and user-pattern omissions; the `fetch:` outcome on patch-less omissions; and one line `.reviewignore: <base|checkout|none>` plus `(changed in this PR)` when applicable. Every file name and pattern is rendered through the existing `safePath` escaping (Markdown delimiters, HTML, line breaks), with a hostile-string fixture. The post-merge run's classify step prints `pr_type=housekeeping` for housekeeping merges and both prepare jobs show as skipped; the notify step carries the type unchanged. No new command-line flags; one new configuration key documented in the skill's SKILL.md with its default list and the `[]` opt-out.

> Sources: `paged-fetch.ts:400-410`; `post-merge.yml:255-270`; prd.md § User Experience

---

## 5. API Specifications

### 5.1 `matchesExcludePattern(filename, patterns)`

Input: a repository-relative filename (GitHub's `filename`) and a list of normalised patterns. Output: boolean. Semantics (D-1.1, D-1.1a): non-wildcard patterns match whole segments (gitignore-like, § 1.4 C-1); wildcard patterns match through the one segment matcher whose grammar is `*`, `?`, whole-segment `**`, one-level `{a,b}`, `[..]` classes; constructs outside it were rejected at load and match nothing. Pure; memoized regexes per pattern; `path.matchesGlob` is never consulted.

### 5.2 `partitionUserExclusions(files, userPatterns, protectedPatterns)`

Returns `{ excluded, protectedKept }` with the matching pattern recorded for every entry. Order-independent: any non-wildcard user match excludes (recorded); otherwise a protected match with only wildcard user matches keeps (first wildcard recorded); otherwise the first match excludes. Protected patterns use the same matcher.

### 5.3 `IGitProvider.getFileContent?(owner, repo, path, ref, maxBytes)`

`gh api /repos/{owner}/{repo}/contents/{path}?ref={ref}` (default JSON media type); `owner`/`repo` `[A-Za-z0-9_.-]+`; `path` validated before encoding (segments non-empty, not `.`/`..`, no leading `/`, no `?`, `#` or control characters), percent-encoded per segment, and the canonical decoded request re-validated; `ref` a 40-hex commit (the listing's head sha); output as bytes with `maxBuffer = ceil(maxBytes × 4/3) + 4096` (overflow → `too_large`); the envelope must be an object with `type: "file"`, `encoding: "base64"` (`"none"` → `too_large`), integer `size` (`> maxBytes` → `too_large`) and string `content`; base64 → bytes (malformed → error); NUL in the first 8 KiB or invalid UTF-8 → `{ kind: "binary" }`; otherwise `{ kind: "text", content, bytes }`. Errors propagate as `GitProviderError` and are caught at the call site (metadata unchanged, `fetch: error`). Optional on the port: absent → no fetch.

### 5.4 Classifier output grammar

`pr_type=<cycle|bugfix|housekeeping|other>` and `pr_number=<digits or empty>` on stdout and in `$GITHUB_OUTPUT`. `housekeeping` is produced only by rule 1a with a PR number; a push without a PR is `other` (KF-063). Consumers: `post-merge.yml` (two guards, notify), nothing else in-tree (the orchestrator receives `--type` only from the two prepare jobs, which never run for housekeeping; its own validation refuses the value).

### 5.5 Configuration

`bridgebuilder.protected_paths: string[]` — when present it replaces `DEFAULT_PROTECTED_PATHS`; `[]` disables protection; entries validated (§ 1.4 C-2). `bridgebuilder.fetch_missing_patches: boolean` (default true). `bridgebuilder.max_content_fetches: integer ≥ 0` (default 20). All parsed in `config.ts` like `exclude_patterns` / `max_files_per_pr` (`config.ts:1300-1330`).

> Sources: § 1.4; `github-cli.ts:150-200`; `classify-merge-pr.sh:160-170`; `config.ts:1300-1330`; DEC-1019 … DEC-1022

---

## 6. Error Handling Strategy

- Matcher: no exceptions at match time; constructs outside the grammar are rejected at load with one WARN per pattern and never compiled; a pattern that compiles to nothing matches nothing.
- Protected paths: never throw; a kept file is recorded; an unknown config type for `protected_paths` is a config error at load, as for `exclude_patterns`.
- `.reviewignore` from the base ref: a failed `git show` (no base, missing file, git error) yields `source: "none"` (or `"checkout"` when no base sha was known) with one WARN; never an exception.
- Content fetch: `GitProviderError` (network, auth, 404 for a path that moved between listing and fetch, `maxBuffer` overflow → `too_large`, malformed envelope or base64 → error) is caught per file and logged at info; the file keeps today's `no_patch` treatment with `fetch` set; the cap and the deadline stop further fetches (`skipped_cap`, `deadline`). The head-sha pin is re-checked after pass 1 as today (`recheck`); a moved head restarts the fetch and discards every synthesized patch.
- Classifier/workflow: an unexpected, empty or malformed `pr_type` value skips both prepare jobs (both guards are allowlists) and the notify step still reports; the orchestrator refuses an unknown `--type` with exit 1.
- Guardrails: a CPU-time threshold trip is a real regression; the message names the measured milliseconds and the bound.

> Sources: `paged-fetch.ts:240-250` (`recheck`); `post-merge-orchestrator.sh:2491-2492`; prd.md § Non-Functional Requirements

---

## 7. Testing Strategy

Red first for every acceptance criterion; the red commit lands alone, the fix after (`red-test-check.sh` where the runner allows — `bats` from the npx cache on PATH; `npm test` through the manual detached-worktree equivalent when nested `node_modules` is needed, DEC-1007 shape).

| FR | Tests (file) | Red-first cases |
|---|---|---|
| FR-1 | `loa-detection.test.ts` | `util.loa-version.json.ts`, `x/.loa-version.json.bak`, `MYPROCESS.md`, `PROCESS.md.old` not excluded by the defaults; `docs/PROCESS.md`, `BUTTERFREEZONE.md` excluded; `a/b` vs `a/b/c` and `x/a/b`; leading `/`, `./`, trailing `/`, whitespace normalisation; `!` line and extglob / nested-brace / escaped patterns rejected with a WARN and matching nothing; `**/*.{json,md}`, `**/*.[jt]s` match dot-led paths; a guard test deletes `path.matchesGlob` for its duration and asserts every grammar case unchanged; the skipped single-`*` case un-skipped; no importer of `simplifiedGlobMatch` (grep) |
| FR-2 | `truncation.test.ts` (A), `paged-fetch.test.ts` (B: rendering, provenance) | `**/*.yml` keeps `.github/workflows/ci.yml` with `protectedKept = [{file, pattern}]`; exact `.github/workflows/ci.yml` and the `.reviewignore` line `.github/workflows/` exclude it; both pattern orders (wildcard first / exact first) exclude when an exact pattern is present and the file is absent from `protectedKept`; protected files first in selection order (file cap 1); `protected_paths: []` disables; a custom list protects only its entries; validation errors name the entry; the Loa tier still strips `.claude/settings.json` without self-review; `.reviewignore` from the base sha (a PR-added line has no effect; `reviewignore_source`, `reviewignore_changed_in_pr`) and from the checkout without a base; the rendered summary lists protected-kept files with their final status and escapes hostile names |
| FR-3 | `paged-fetch.test.ts` (provider double, end to end), `github-cli.test.ts` (stub executor) | an added file without a patch and served content → reviewed with the synthesized patch, `source: "contents"`, not degraded; binary, too large (size and `encoding: none`), malformed envelope / base64, provider error → `no_patch` with the `fetch` outcome; an excluded patch-less file is never fetched; `max_content_fetches` and the deadline → `skipped_cap` / `deadline`; several files competing for the aggregate budget (incl. header and `+` overhead); the exact ref passed equals the listing head sha; the restart path discards synthesized patches; `fetch_missing_patches: false` → no provider call; a modified file without a patch → `no_patch` (pinned); synthesized-patch matrix: missing final newline marker, CRLF, multibyte UTF-8, content starting with diff markers; a raw text file shaped like a contents envelope is reviewed as text; `assertAllowedArgs` accepts the exact shape and rejects `..` (plain and encoded), empty and `.` segments, a leading `/`, `?`/`#`/control characters, encoded separators, option-like inputs, a foreign query, a short or non-hex ref, any header |
| FR-4 | `post-merge-classifier.bats`, `classify-merge-pr.bats`, `post-merge-workflow-guards.bats`, new `post-merge-orchestrator-type.bats` | PCT-T28 … T32, T38 → `housekeeping`; T35 → `other`; the rest unchanged; wrapper: housekeeping subject with PR → `pr_type=housekeeping`, no-PR push → `other`; guards: text pinned and a shell mirror of both expressions over {cycle, bugfix, other, housekeeping, unknown, empty} × {PR, none}; yq parse and actionlint (when installed) of the workflow; orchestrator `--type housekeeping` → exit 1 "Invalid --type" |
| FR-5 | `progressive-truncation.test.ts` | both guardrails on the minimum of three CPU-time samples; three consecutive green full runs under two concurrent `npm test` runs in the other worktrees, recorded in the report; the report-only O(n²) negative control trips the 100 ms bound with its figures recorded |

Suites run at landing: `npm test` and `npx tsc --noEmit -p resources/tsconfig.json` in the skill; `npx --no-install bats tests/unit/post-merge-classifier.bats tests/unit/classify-merge-pr.bats tests/unit/post-merge-workflow-guards.bats tests/unit/post-merge-orchestrator-type.bats tests/unit/post-merge-publication.bats`; `bash -n` on the shell files; `yq` parse and `actionlint` (when installed) on the workflow; the full local CI mirror (`~/.cache/loa/cycle-134/scripts/s-tests.sh all`, adapted) before the PR, where the only accepted host-local reds are named: the three KF-034 cases of `tests/unit/post-merge-publication.bats` (host git config), the gitignored vision-021 date case of the template-safety suite, and the two adapter pytest cases that pass with `CLAUDE_HEADLESS_BIN` unset — anything else is a red to fix.

> Sources: prd.md § Functional Requirements (acceptance criteria); DEC-1007; `~/.cache/loa/cycle-134/scripts/s-tests.sh`

---

## 8. Development Phases

One sprint (global 279). Lead prep: the contract commit (D-2.1: every `types.ts` field of § 3, dist and manifests regenerated under the marker) and the Q-1 read-only probe recorded in its report. Then three Opus 5.5 implementers in worktrees from that commit, disjoint allowlists (D-2.2). Fix rounds: the lead fast-forwards the implementer's worktree to the landed head before each round; a round that only adjusts wording, tests or hygiene is exempt from red-first, a round that changes behaviour follows it; rounds are capped at three per implementer before the lead takes the change over. SKILL.md is split by heading: A owns the exclusion-patterns and protected-paths headings, B the coverage heading; the lead resolves hunk conflicts when applying B after A.

| Implementer | Owns | Tasks |
|---|---|---|
| A | `resources/core/truncation.ts`, `resources/config.ts` (all three new keys), `resources/__tests__/loa-detection.test.ts`, `resources/__tests__/truncation.test.ts`, `SKILL.md` (exclusion-patterns and protected-paths headings) | FR-1 (C-1), FR-2 (C-2 except the coverage copy and rendering); a grep for importers of `simplifiedGlobMatch` and callers of `matchesExcludePattern` outside the allowlist, reported before the patch |
| B | `resources/core/paged-fetch.ts`, `resources/adapters/github-cli.ts`, `resources/ports/git-provider.ts`, their tests (`paged-fetch*.test.ts`, `github-cli*.test.ts`), `resources/__tests__/progressive-truncation.test.ts`, `SKILL.md` (coverage heading); an inventory of every in-tree `IGitProvider` implementation and typed test double before adding the optional method | FR-3 (C-3), the coverage copy, provenance fields and rendering (C-2 consumer side), FR-5 (C-5) |
| C | `.claude/scripts/classify-pr-type.sh`, `.claude/scripts/classify-merge-pr.sh` (comment only), `.github/workflows/post-merge.yml`, `tests/unit/post-merge-classifier.bats`, `tests/unit/classify-merge-pr.bats`, `tests/unit/post-merge-workflow-guards.bats`, new `tests/unit/post-merge-orchestrator-type.bats` | FR-4 (C-4); Q-3 consumer inventory as a gate |
| lead | contract commit + Q-1 probe, landing (A → B → C), dist rebuild, manifests, CHANGELOG, DEC rows from the reports, an integration check after A and B land (a config with `**/*.yml` → `truncateFiles` → coverage → the rendered "Protected paths kept (1)" line), review, audit, PR (the branch's dist reviews it), Bridgebuilder, merge, record, archive | FR-6 |

Landing order A → B → C: B's rendering reads A's field through the contract commit, so either order compiles; A first keeps the matcher change reviewable on its own.

> Sources: prd.md § Timeline & Milestones; DEC-1024, DEC-1025

---

## 9. Known Risks and Mitigation

| Risk | Mitigation |
|---|---|
| The contents endpoint returns `encoding: "none"` with empty content above 1 MiB | `too_large` → `no_patch` as today; `max_diff_bytes` is far below 1 MiB in practice |
| A `gh` version changes the envelope shape | strict validation fails → error → `no_patch`; the Q-1 probe in Task 1.0 records the live shape before B codes against it |
| A PR edits `.reviewignore` to hide a file | the base ref's copy governs; the edit is reviewed and flagged |
| A protected pattern in the default list matches nothing in a given repository | no cost; the list is documentation of intent |
| A non-wildcard default that relied on substring matching | none known (the six defaults are root-level file names); the CHANGELOG names the change |
| The one matcher mis-translates a construct the native glob handled | the grammar is small and pinned; constructs outside it are rejected loudly rather than silently mismatched |
| `post-merge-workflow-guards.bats` greps the YAML text | the guard text is written exactly as the test expects and the test is updated in the same patch |

> Sources: § 5.3; `post-merge-workflow-guards.bats`; prd.md § Risks & Mitigation

---

## 10. Open Questions

- **Q-1** What exactly does `gh api /repos/{o}/{r}/contents/{path}?ref=<sha>` return on the lead host's `gh` for a small text file (envelope fields, `encoding`, `size`)? The lead runs one read-only call during Task 1.0 and records the shape in the contract commit's report; B codes the strict validation against it.
- **Q-3** Does any in-tree consumer read `pr_type` / `PM_PR_TYPE` and switch on it in a way that misroutes `housekeeping`? Implementer C enumerates every consumer and reports; a misrouting consumer is a blocker returned to the lead before the fix patch lands. None is known in-tree (the two guards, notify, the orchestrator's `--type` validation).

(Q-2 of 1.0 — depth of the six non-wildcard defaults — was already decided by DEC-1013 and is recorded in § 11.D, not here.)

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
| D-1.1a | One glob grammar, one matcher (no `path.matchesGlob`); constructs outside the grammar rejected at load — supersedes D-1.1's native-then-fallback | DEC-1026 |
| D-1.2a | `.reviewignore` read from the PR base sha; source and PR-modified flag recorded | DEC-1027 |
| D-1.3a | JSON contents envelope, base64, size checked before decoding; no raw media type — supersedes D-1.3's transport | DEC-1028 |
| D-1.4a | `simple-release` guard as an allowlist — supersedes D-1.4's negative list | DEC-1029 |
| D-1.3b | Fetch bounds: exclusions first, `max_content_fetches`, deadline, outcomes recorded, `fetch_missing_patches` | DEC-1030 |
| D-1.5a | Guardrails take the minimum of three CPU-time samples; negative control defined | DEC-1031 |
| (note) | Q-2 of 1.0 (six non-wildcard defaults match at any depth) is DEC-1013 | — |

> Sources: `grimoires/loa/decisions.yaml` DEC-1019 … DEC-1031 (phase architecture, cycle `cycle-135-review-coverage-followups`, proposed, sourced to this section)

### 11.E Grounding reads

See prd.md Appendix B (all reads 2026-10-26 on `main 4256a1b3`); additionally for this document: `types.ts:20-40` (`CoverageRecord`), `:291-300` (`TruncationResult`); `post-merge-orchestrator.sh:2429` (`--type` parsing), `:2491-2492` (validation, exit 1); `package.json` of the skill (versions).

> Sources: the lead's session transcript 2026-10-26

### 11.F Flatline SDD review dispositions (1.0 → 1.1)

Two voices, cross-scoring degraded (KF-041 shape), 5 skeptic blockers and 40 medium items; every item read. The sprint review's design-level items (4 blockers, 38 medium) are folded in where they touch this document.

| Item | Concern (short) | Disposition |
|---|---|---|
| SKP-003; gpt IMP-002, IMP-003; opus IMP-003, IMP-014; sprint SKP-001, gpt IMP-001, opus IMP-001 | native-OR-fallback is not one semantics; braces/classes undefined on Node 20 | **Accepted** — D-1.1a: one matcher, one grammar, constructs outside rejected at load |
| SKP-002; gpt IMP-004; opus IMP-004; sprint gpt IMP-014 | order-dependent protection | **Accepted** — C-2: order-independent rule; tests both orders |
| SKP-005; gpt IMP-008, IMP-009, IMP-010; opus IMP-006; sprint SKP-001, gpt IMP-004, opus IMP-010 | body sniffing; buffer sizing; malformed base64 | **Accepted** — D-1.3a: JSON envelope only, bytes-first validation, base64-sized buffer, overflow → too_large |
| SKP-001 (guard); gpt IMP-001; opus IMP-001 | negative-list guard admits unknown values | **Accepted** — D-1.4a: allowlist; matrix mirror test |
| SKP-001 (`.reviewignore` trust boundary); sprint opus IMP-020 | PR head owns `.reviewignore` | **Accepted** — D-1.2a: base-sha read; flags recorded; `.reviewignore` protected |
| gpt IMP-005; opus IMP-002 | normalisation per source; the `/` → `**` conversion | **Accepted** — C-1: normalisation at load; conversion removed |
| gpt IMP-006, IMP-007; opus IMP-005, IMP-009, IMP-010; sprint SKP-002, gpt IMP-002, IMP-008 | unbounded fetches; budgets on encoded bytes; outcomes; off switch; deadline | **Accepted** — D-1.3b |
| gpt IMP-011; opus IMP-011; sprint gpt IMP-005 | synthesized-patch edge cases and budget accounting | **Accepted** — C-3 (newline marker, CRLF, N, budget on encoded bytes, never truncated) |
| gpt IMP-012; opus IMP-012, IMP-013; sprint SKP-005, gpt IMP-003 | restart discards; head pin; fork coordinates; `.` segments | **Accepted** — C-3, § 5.3 |
| gpt IMP-013, IMP-014; opus IMP-018, IMP-020 | rendering escapes; kept-then-omitted; Loa-tier pattern shown | **Accepted** — § 4, § 3 |
| gpt IMP-015 | validate the whole endpoint shape; before/after encoding | **Accepted** — § 5.3 |
| gpt IMP-016; opus IMP-021 | separate classifier/wrapper tests; where the orchestrator pin lives | **Accepted** — § 7: distinct files; new `post-merge-orchestrator-type.bats` |
| gpt IMP-017; sprint opus IMP-009 | evaluate the guard conditions, not only text; lint the YAML | **Accepted** — C-4: shell mirror over the matrix; yq + actionlint |
| gpt IMP-018; opus IMP-019; sprint gpt IMP-012, opus IMP-005, IMP-018 | CPU-time contract; noise; red-first for a test change; load condition | **Accepted** — D-1.5a, C-5 |
| opus IMP-007, IMP-008; sprint opus IMP-003, gpt IMP-006 | contract commit scope; optional provider method; `truncateFiles` signature | **Accepted** — § 3, § 8 (all `types.ts` fields in the contract commit; `getFileContent?` optional; config through the existing object; B inventories doubles) |
| opus IMP-015 | leading `/` | **Accepted** — C-1 normalisation |
| opus IMP-016 | Q-2 is decided | **Accepted** — moved to § 11.D |
| opus IMP-017, IMP-022; sprint gpt IMP-007, opus IMP-017, IMP-019 | test and docs ownership (rendering → B; SKILL.md by heading) | **Accepted** — § 7, § 8 |
| sprint gpt IMP-013, opus IMP-016 | named host-local red allowlist | **Accepted** — § 7 |
| sprint opus IMP-011 | Q-1 probe by the lead in Task 1.0 | **Accepted** — § 8, § 10 |
| sprint opus IMP-012 | lead integration check after A and B | **Accepted** — § 8 |
| sprint opus IMP-013 | grep for `simplifiedGlobMatch` importers / external callers | **Accepted** — § 8 (A) |
| sprint opus IMP-014 | fix-round basing rule | **Accepted** — § 8 |
| sprint gpt IMP-009, opus IMP-008 | Q-3 as a gate | **Accepted** — C-4, § 10 |
| sprint gpt IMP-010, IMP-011, opus IMP-004, IMP-015, IMP-023 | degraded-verdict outcome; live confirmation; operator confirmation timing | **Accepted** — prd.md FR-4, FR-6 (stated) |
| sprint opus IMP-006 | kinds for Tasks 1.2 and 1.6 | **Accepted** — sprint plan (judgment) |
| sprint opus IMP-007 | line refs → code anchors | **Accepted** — C-2 names the call expressions and functions |
| sprint opus IMP-021, IMP-022 | FR-6 in the acceptance bullets; the branch's dist reviews the PR | **Accepted** — sprint plan; § 8 |

> Sources: `grimoires/loa/a2a/flatline/cycle-135-sdd-review.json`, `cycle-135-sprint-review.json`; DEC-1026 … DEC-1031
