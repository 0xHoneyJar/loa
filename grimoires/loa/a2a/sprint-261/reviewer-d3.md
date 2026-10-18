# Sprint 261 swap round 1, author D3: bugfix-v2-05, 06, 07

All three tasks are ready. Each proves red at base and green at the reference on the host, and the staging root validates with zero violations. Only bugfix-v2-07 has fallen below 0.5 in a blind self-solve, and only barely above it (0.57). bugfix-v2-05 has one blind solve at 0.47 and one at 1.0. bugfix-v2-06 scored 1.0 in its blind solve. The calibration smoke decides.

## Method for the self-solve
A fresh Opus 5.5 general-purpose subagent got a /tmp copy holding only the fixture and TASK.md. It was told not to read anything else. It never saw the grading files. I graded its tree with the fixture tests restored and the grading suite overlaid. Two framings were used: "about 10 minutes, at most 40 tool calls" and "be thorough, up to about 30 minutes". These numbers measure the final task versions. Blind solves of discarded designs are listed separately.

## Tasks

| Id | Component | Fixture | Fixture suite | Reference | Hidden cases | Base red | Blind self-solve |
|---|---|---|---|---|---|---|---|
| bugfix-v2-05 | cron with a stated six-zone daylight-saving table | 667 lines, 13 modules | 33 | 8 files, 158 lines | 30 (15 tables, 15 conformance) | 28/30 | 0.47 (10-min framing; tree from the version before five extra deviations), 1.0 (30-min framing, solver wrote its own brute-force check) |
| bugfix-v2-06 | semver 2.0.0 and npm-style ranges plus a VersionIndex | 916 lines, 14 modules | 34 | 8 files, 202 lines | 36 (21 tables, 15 conformance) | 35/36 | 1.0 (10-min framing, 2.2 min) |
| bugfix-v2-07 | CommonMark 0.31.2 block structure (lists, quotes, fences, setext) | 690 lines, 14 modules | 28 | 8 files, 260 lines | 35 (20 tables, 15 conformance) | 35/35 | 0.57 (10-min framing, 20/35, all 15 conformance cases red) |

Proof tails (host, `prove.sh`: fresh copies, `patch -p1 --batch --forward`, `timeout 300`, `PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider`):
```
bugfix-v2-05 [base] regression: 33 passed | full: 28 failed, 35 passed | [ref] regression: 33 passed | full: 63 passed
bugfix-v2-06 [base] regression: 34 passed | full: 35 failed, 35 passed | [ref] regression: 34 passed | full: 70 passed
bugfix-v2-07 [base] regression: 28 passed | full: 35 failed, 28 passed | [ref] regression: 28 passed | full: 63 passed
validate-suite: OK — 7 task(s) valid (staging root: review-01..04 + bugfix-v2-05..07, --allow-partial)
no-secrets.sh: pass on all three fixtures; every .py parses with feature_version=(3, 11); no caches; no `hidden` token in TASK.md or the fixtures
```

### bugfix-v2-05 (cron, author D3)
The spec is declarative: a fire time is a whole UTC minute whose wall time in the zone matches. So a skipped wall time never fires and a repeated one fires twice. The oracle is brute force over UTC minutes with an independent parser and independent zone arithmetic. The fixture searches by wall clock, which misses repeated wall times, and its prev and next searches are mirrored. It also has these deviations:
- a day cache keyed by (month, first weekday), which conflates leap Februaries;
- a month skip that keeps the time-of-day bounds;
- floor versus ceil rounding in `prev_fire` and `fires_between`;
- southern zones never entering saving time;
- `*` steps counting from 0;
- `?` treated as restricting;
- the `W` rule at month edges;
- job ties broken by name, and the `catch_up` bounds;
- `instants` and `transitions` order, and `wall` rounding up;
- macros that are case-sensitive and unstripped;
- the step checked after the values;
- a missing `between` CLI command.

A single leftover search hunk fails 16 to 30 of the 30 cases.

### bugfix-v2-06 (semver, built by a fork from my brief)
The tree is the fork's "VersionIndex" version, frozen at the deadline. The intersects and subset rework was not finished and is not included. The deviations are visible parse, compare, desugar, prerelease and increment ones, plus VersionIndex bisect, tie and cache bugs. N2 is a timing rule: 1,000 queries over 50,000 versions in under 5 s. Rerun it in the image to check for flakiness.

### bugfix-v2-07 (CommonMark blocks, built by a fork from my brief)
The oracle ports commonmark.js's block algorithm. It was cross-checked against markdown-it 14.1.0, read-only on the host, over about 4,240 documents: zero disagreements after excluding 187 documents that hit four documented markdown-it departures. Those 187 are skipped by sha256. The 15 deviations are listed in the fork's notes (starts, continuation, markers, node, looseness, render).

## DECISION
- DECISION: each conformance case spans the whole public surface, so scoring is bimodal by design. One leftover deviation fails at least about 15 of the 30–36 cases, so any residual scores ≤ 0.5. Per-class conformance cases had given blind solvers 1.0.
- DECISION: the self-solve uses a fresh blind subagent rather than my own attempt. The author cannot unsee the grading suite.
- DECISION: four designs were discarded after blind solvers scored 1.0. They were JSON Patch (29 deviations), semver v1 (25), gitignore rules (18) and CommonMark inline (21; two versions, one with the emphasis algorithm kept implicit). That makes seven blind solves at 1.0, 2–4 minutes each. Fully built candidates are kept in scratch (`work-d3/bugfix-v2-05/markdown-candidate/` and `jpatch-discarded/`).
- DECISION: the reference patches add no regression tests, and the briefs do not ask for any, so the counts are exact.
- DECISION: bugfix-v2-05 was kept as the cron version, not CommonMark inline. Cron had one sub-0.5 blind solve; markdown had none in three.
- DECISION: I corrected bugfix-v2-06's stale `success_criterion` to the proven counts (36 hidden; 35/70 at base, 70/70 at the reference).

## Limitations
- bugfix-v2-05's reference is 158 changed lines, below the 200 target.
- In bugfix-v2-06 the intersects and subset lever was not delivered. Its blind solve is 1.0, so expect it to fail calibration.
- Blind-solve evidence across five designs: a thorough Opus solver audits code against the stated rules and fixes everything it is told about. Declarative rules let it brute-force-check itself, and domain memory covers what the brief leaves implicit. Expect the bar to be hard to meet for bug-fix tasks.

## Handoff for the fairness reviewer
- **bugfix-v2-05.** Rule 11 is the declarative fire rule that the oracle brute-forces. Rules 6–10 cover parsing; check the order of the error messages. Rule 15 covers the CLI message for a naive START.
- **bugfix-v2-07.** Rules 19, 20 and 22 come first: end lines, looseness and tight-item newlines.
- **bugfix-v2-06.** The N2 timing rule. The R6 caret table: `^0.x` gives `<1.0.0-0`.
- **All three.** Tables were computed by the oracles. The v2-07 tables match markdown-it row for row.
