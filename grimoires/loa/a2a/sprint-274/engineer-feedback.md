All good

# Sprint 274 (cycle-133 Sprint 3) — Senior Technical Lead Review, round 2

**Reviewer:** lead (Fable 5.1) · **Round 1:** `engineer-feedback-r1.md` (CHANGES_REQUIRED, one medium) · **Dissent:** run 1 of 3 reused (`adversarial-review.json`; the one blocking payload stays rejected below, the five advisories are the lows below) · **Fix reviewed:** `87c7041e3`.

## Summary

The one required change landed: `verdict-derive.sh` now treats a code fence left open at the end of the file as a violation (fail closed), VFC-13 was red first and is green with its closed-fence control, the floor amendment row pins the new bytes and `FLOOR_SHA256` the new `floor.yaml`; the verdict, floor and conformance suites pass 169/169 and the gates pass. The probe from round 1 now reports `line 7: a code fence opened here never closes`. The added lines are an END block, one branch and a widened comment — additive, as the amendment requires. The seven lows are follow-up beads (bd-yt1k1 evidence, bd-afz2p grader, bd-znx6q floor). Approved.

## Observations

- **LOW** (confidence: high) `evals/harness/lib/egress-proxy.sh:368` — denial attribution by address alone merges the self-check's probes with the trial when the guard address is reused on the batch network. Failure: when the self-check runs on the same batch network before a trial and the denials are read per address, then the trial appears to carry twenty-five denials it never made. Follow-up bd-yt1k1.
- **LOW** (confidence: high) `evals/harness/took-effect.sh:97` — the clause (f) failure detail names one file and a count. Failure: when clause (f) fails on several files in one run, then the record does not say which files, phases and tools were involved beyond the first. Follow-up bd-yt1k1.
- **LOW** (confidence: medium) `evals/harness/ablation-grade.sh:2001` — a byte-identical duplicate verdict line is tolerated when a later row supersedes its hash (dissent DISS-001, downgraded). Failure: when a verdicts file holds the same original row twice followed by a correction naming its hash, then the grade succeeds and reports one superseded row where the contract text promises duplicate rejection. Follow-up bd-afz2p.
- **LOW** (confidence: medium) `evals/harness/ablation-grade.sh:3445` — stale judge rows are checked only when the grade credits pairs (dissent DISS-C-002). Failure: when an operator re-grades a refused run with a verdicts file that still carries rows for that run id, then the grader writes a grade without judge fields and the cell counts as unjudged. Follow-up bd-afz2p.
- **LOW** (confidence: medium) `evals/harness/ablation-grade.sh:1883` — the grader's RFC 8785 serialiser is not cross-checked against the repository's jcs helper on edge inputs (dissent DISS-C-003). Failure: when a key manifest ever carries an integer above two to the fifty-third power or a DEL character, then the two serialisers may hash the same key differently and every verdict is rejected as stale. Follow-up bd-afz2p.
- **LOW** (confidence: medium) `evals/harness/ablation-grade.sh:253` — the verdicts contract expects finding_sha256 copied per credited pair (dissent DISS-C-004). Failure: when a judge tool computes one canonical reference per finding id instead of copying finding_sha256 from credited_pairs, then its rows for the second pair of that finding are rejected as stale. Follow-up bd-afz2p.
- **LOW** (confidence: medium) `.claude/data/floor.yaml:58` — additive-only is a proxy for strengthening, not a proof (dissent DISS-C-005; DEC-0946). Failure: when a future amendment adds a late redefinition or an early exit before the scan, then FS-1 accepts the file at its pinned sha while the gate approves a file it should block. Follow-up bd-znx6q; this amendment's bytes were read in full in both rounds.

## Verified in this round

- `tests/unit/verdict-derive-failure-clause.bats` VFC-13: an open fence before a CRITICAL bullet is a violation naming the fence line; the closed-fence control is judged by the tally itself.
- 169/169 across verdict-derive-failure-clause, verdict-derive, verdict-observations-section, golden-path-c8-verdict-trailer, profile-floor, floor-snapshot, guard-origins, finding-conformance; `guard-yield --check` in sync; gates PASS; `checksums.json` and REPO-MAP regenerated under the bounded marker.
- The round-1 verified items stand (secret classes byte-identical, seeder path refusals before any write, guard rules before the launcher proceeds, validators agree on 47 vectors, home-scope reverse check on 1,776 files).

## Rejected dissent payloads

- DISS-C-001 (blocking, `seed-corpus-from-external.sh:502`, "a hostile tree-entry path reaches write_layout"): rejected as in round 1 — `unsafe_path` (lines 434–446) refuses every PR path with an empty, `.` or `..` segment, a leading slash, a backslash, a NUL or control character, or a `.git` segment before any tree entry is looked up; only checked paths reach `write_layout`; the dissent read a truncated diff.

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":7},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-274","ts":"2026-10-24T12:50:41Z"} -->
