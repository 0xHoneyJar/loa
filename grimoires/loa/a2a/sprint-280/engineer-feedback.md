All good

# sprint-280 (cycle-136 Sprint 1) — Senior Technical Lead Review, round 2 (final)

**Reviewer:** lead (Fable 5.1) · **Head reviewed:** `be35c3ac6` on `feature/cycle-136-bridgebuilder-followups` (+ the docs commit after it) · **Round 1:** `engineer-feedback-r1.md` (CHANGES_REQUIRED at `9279db32e`: 1 HIGH, 3 MEDIUM, 3 LOW; two dissent runs 2/2 voices, consensus) · **Round-1 commits:** A `eb2dac6b9` → `be35c3ac6`, B `b695008fc` (tests only), lead `f46e8879e` · **Report:** `reviewer.md` § Round 1

## Summary

Every round-1 finding is fixed behind a test that was red first, pinned by a green-by-design test, or documented. The HIGH is gone: a plain-scalar `if:` whose value continues on a deeper line is now multi-line and never matched, so a customised guard that begins with the legacy text cannot be misdetected or rewritten into a broken workflow. The scaffold detection is now also proven against the real pre-cycle-135 workflow, the flag path prints one line on success, B's silence set covers every non-failed outcome, and the SDD's message text matches the shipped line. The code was read in full against the round-1 text (A's awk continuation guard, the reordered WARN/notice flow and the stdout-reason protocol of the rewrite helper; B's three test additions and helper change); the red/green of A's pair reproduced on the landed shas with `red-test-check.sh`. Approved for audit.

## Round 1 dispositions

| # | Sev | Finding (round 1) | Disposition | Evidence |
|---|---|---|---|---|
| 1 | HIGH | a plain-scalar continuation after a legacy-looking `if:` was detected as the legacy guard and rewritable | Fixed: the awk pass marks a candidate multi-line when the next non-blank non-comment line in the block is deeper than C (comments and blanks skipped; a mis-indented key counts too) → `notsingle`; silent, with the flag the refuse WARN, byte-identical | `.claude/scripts/lib/scaffold-post-merge-workflow.sh:90`; T36, T37; mutation: disabling the check fails exactly T36/T37; DEC-1102 |
| 2 | MEDIUM | no fixture was the real pre-cycle-135 workflow | Fixed: `tests/fixtures/mount-workflow-scaffold/post-merge-legacy.yml` (= `git show 4256a1b3:.github/workflows/post-merge.yml`, 277 lines); T38 asserts WARN, byte-identical, one-line rewrite equal to the allowlist swap, second run silent | `eb2dac6b9`; DEC-1104 |
| 3 | MEDIUM | two lines on a successful flagged rewrite | Fixed: a successful fix prints only its notice; the legacy WARN prints when the flag is off or ahead of a refuse/failure WARN; the rewrite helper returns its reason on stdout (empty = success) | `.claude/scripts/lib/scaffold-post-merge-workflow.sh:150`; T17, T26, T29–T32; DEC-1103 |
| 4 | MEDIUM | the WARN-silence set lacked `deadline` and the empty-content case | Fixed (tests): `deadline` writes no WARN; an empty `text` answer with additions > 0 is `error` + exactly one WARN | `b695008fc`; `paged-fetch-contents.test.ts`; DEC-1105 |
| 5 | LOW | sdd.md § 4 showed an unquoted `<file>` | Fixed (docs): § 4 shows the quoted, bounded name as shipped | `f46e8879e` |
| 6 | LOW | the stderr-swapping helper dropped the callback; no concurrency pin | Fixed (tests): the three helpers forward the callback through `process.nextTick` under `{ concurrency: 1 }` | `b695008fc` |
| 7 | LOW | temp-file leak window on a signal | Filed: bd-lkdsx (a trap inside a sourced library function touches the callers' trap state) | DEC-1106 |

## Lead verification

- Source read of A's round-1 diff (`eb2dac6b9..be35c3ac6`): the `pending`/`cmulti` guard sits before the block-end test so a continuation is seen even when it is the last line of the block; the rewrite helper's stdout protocol is empty-on-success and the caller's `|| why="the rewrite failed"` covers a non-zero exit; the wrapper and failure paths still print the legacy WARN first.
- `red-test-check.sh --red eb2dac6b9 --green be35c3ac6 -- bats tests/unit/mount-workflow-scaffold.bats` → VERIFIED (red 9 cases, green 44/44 with `cycle-124-live-scaffold.bats`); A's busybox-awk cross-check 38/38.
- B's `b695008fc`: `npm test` 1323/1323 after the patch; the two new cases pin existing behaviour (stated in the commit).
- Head `be35c3ac6`: `npm test` 1323/1323; `tsc` clean; dist fresh; `check-prompt-budget.sh` rc 0; `gen-checksums.sh --check` OK (2080 entries); REPO-MAP consistent; `check-manifest-paths.sh` 0 untracked / 0 missing.

## Observations

- **LOW** (confidence: low) `.claude/scripts/lib/scaffold-post-merge-workflow.sh:150` — the rewrite helper now communicates its failure reason as stdout text, with the empty string meaning success. Failure: when a future edit prints a diagnostic to stdout inside the helper then the caller reports a spurious rewrite failure although the file was rewritten.

## Acceptance

FR-1 … FR-5 and Tasks 1.0 … 1.4 as in round 0 (`reviewer.md` § AC verification), plus the round-1 criteria in A's and B's round-1 reports: every row met with `file:line` evidence; `sprint.md` Tasks 1.0 … 1.4 may be ticked. Tasks 1.5 (this gate and the audit), 1.6 (ship) and 1.E2E remain with the lead.

## Rejected dissent payloads

None new this round. Round 1's rejected advisory (a block-scalar or two-line legacy guard gets no WARN) stands as by design (DEC-1067, DEC-1078; DEC-1106).

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":1},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-280","ts":"2026-10-27T02:28:07Z"} -->
