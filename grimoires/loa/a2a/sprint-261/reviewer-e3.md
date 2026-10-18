# s4-e3 — suite v2 swap round 1, feature-build authors (E3)

Delivered: all four tasks. feature-v2-05, 07 and 08 are in `patches/s4-e3.patch`. feature-v2-06 followed in a supplemental patch, `patches/s4-e3-f06.patch`, which applies on top of it.

**The headline: none of the four tasks meets the hardness bar on my blind self-solve.** A fresh Opus 5.5 subagent saw only TASK.md and the fixture, worked with no time pressure, and was graded against my hidden suites. It scored 1.0 on three tasks and 0.98 on feature-v2-06, in 3 to 7 minutes:

| Task | Round A (mechanism spec) | Round B (hardened, delivered) |
|---|---|---|
| feature-v2-05 | 45/45 | 36/36 |
| feature-v2-06 | 44/45 | 52/53 |
| feature-v2-07 | 51/51 | 56/56 |
| feature-v2-08 | 53/53 | 60/60 |

In round A the brief states the mechanism, rule by rule. Round B adds a component defined declaratively with a unique answer: an optimum or a set definition, checked by a brute-force oracle and worth more than 55 % of the cases. The blind solvers wrote their own brute-force checkers and passed. The calibration smoke decides, but I expect these three near 1.0. A fair, complete spec appears to be transcribed and self-verified reliably at this size.

## Tasks

### feature-v2-05: JSON Pointer, JSON Patch and a canonical diff in `docstore`
- **Spec:** RFC 6901/6902 as a stated variant: exact ordered errors, syntax validation before apply, index tokens, move-after-removal, refusal of a move into a child, JSON equality, atomic `Store.patch` with history, dry run and `max_ops`. It adds a canonical `diff` under type-strict equality: an array LCS with the lexicographically smallest index tuple into a, then into b; removes high to low, then adds low to high. Stored revisions, `Store.at` and `Store.revert`, and the CLI commands `get`, `patch`, `diff` and `revert` complete it. TASK.md has 37 numbered rules.
- **Sizes:** fixture 752 lines in 14 modules, with 20 fixture cases. The reference changes about 470 lines in 10 files.
- **Hidden cases:** 36 in total, 12 on patch and 24 on diff (67 %). 19 are conformance cases over seeded inputs against `_oracle_zq_jpatch.py` and the brute-force `_oracle_zq_jdiff.py`.
- **Proofs**, on a fresh fixture copy with the hidden files overlaid:
  ```
  base full 36 failed, 20 passed | base regression 20 passed | ref full 56 passed | ref regression 20 passed
  ```
- **Naive LCS tie variants:** they fail 17–19 of the 24 diff cases, a whole-suite rate of 0.47–0.53. The blind self-solve scored 1.0.

### feature-v2-07: cron schedules on local wall time in `cronq`
- **Spec:** five fields with names, steps, L/LW/nW, nL/n#k, the dom-or-dow rule with `*/1` restricted, macros and exact ordered errors. `next_after` works over a zone table: gap wall times never fire, a repeated wall time fires on its first occurrence, and a horizon bounds the search. Added as set definitions over the fire set F: `prev_before`, `count_between` and `nth_after`, over a 1096-day span. POSIX-TZ rule zones add an inverted sign, Jn/n/Mm.w.d dates, times from −167 to 167 h and 11 ordered errors. The CLI gains `prev`, `count` and `--tz`. TASK.md has 33 rules.
- **Sizes:** fixture 716 lines in 13 modules, with 36 fixture cases. The reference changes 639 lines in 8 files.
- **Hidden cases:** 56, 38 hand-written and 18 conformance. 34 of them (61 %) cover the new components.
- **Proofs:**
  ```
  base full 56 failed, 36 passed | base regression 36 passed | ref full 92 passed | ref regression 36 passed
  ```
- **Blind self-solve:** 1.0.

### feature-v2-08: glob ignore rules, extended groups and brace expansion in `snapkit`
- **Spec:** a glob matcher with brackets, ASCII classes, escapes and `**` segment forms. Rules files work like gitignore: per-directory files, last match wins, anchoring and basename rules, directory-only rules and excluded-parent pruning. Extended groups `?() *() +() @() !()` are defined as string sets over every cut, and `!()` is the complement and may take the empty piece. Brace expansion adds lists, padded and stepped sequences, a literal rescan, de-duplication at the end and a limit of 256. The CLI gains `check-ignore` and `match`.
- **Sizes:** fixture 619 lines in 13 modules, with 27 fixture cases. The reference changes 727 lines in 9 files.
- **Hidden cases:** 60, 39 hand-written and 21 conformance against the cut-enumerating `_oracle_zq_snap.py`. 35 of them (58 %) cover the new components.
- **Proofs:**
  ```
  base full 60 failed, 27 passed | base regression 27 passed | ref full 87 passed | ref regression 27 passed
  ```
- **Blind self-solve:** 1.0.

### feature-v2-06: semver 2.0.0 ranges plus an optimal resolver in `pkglock` (supplemental patch)
- **Spec:** strict semver parsing and precedence, a stated range desugaring table, the per-set prerelease rule and exact ordered errors. The resolver returns, among all valid selections with no extra packages, the one that is maximal when compared package by package in name order, with absent below every version. It covers TASK.md sections 1–5, with S1–S9 for the resolver.
- **Sizes:** fixture 711 lines in 15 modules, with 31 fixture cases. The reference adds 627 lines and removes 95, in 8 files.
- **Hidden cases:** 53, of which 30 cover the resolver and 20 are conformance cases. The brute-force oracle is `_oracle_zq_semver.py`.
- **Proofs:**
  ```
  base full 53 failed, 31 passed | base regression 31 passed | ref full 84 passed | ref regression 31 passed
  ```
- **Blind self-solve:** 52/53, failing only the range-error conformance case. The solver's own test file was again named `tests/test_semver_ranges.py`.
- **Naive variants measured by the author:** breadth-first greedy scores 0.51 and first-found DFS 0.74. Plain name-order backtracking scores 0.98.
- **History:** my earlier reading of "26 of 84 failed" was taken while the author was regenerating the files. I updated task.yaml's origin, criterion and success criterion myself.

## Common checks
- **Proof method:** the commands are in `~/.cache/loa/cycle-130/work-e3/prove.sh`. Each run uses `timeout 300 env PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider -o addopts= --rootdir <tree> tests`, plus `--ignore=tests/acceptance` for the regression run. The reference is applied with `patch -p1 --batch --forward`. Host pytest lives in the user site, so `-I -s` could not run on the host; the in-image rerun is authoritative.
- **Staging root:** review-01…04 plus all four feature tasks. Output: `validate-suite: OK — 8 task(s) valid (partial: type counts not enforced)`.
- **Hygiene:** no-secrets passes on every fixture. The fixtures are 80–92 KB. No caches. Every `.py` parses under `ast.parse(feature_version=(3,11))`. TASK.md has no `hidden` token and no hidden-file stem.
- **Blind grading:** `~/.cache/loa/cycle-130/work-e3/grade.sh` copies the solved tree, restores `grader_protected`, overlays the manifest and runs. The solved trees are under `work-e3/blind/` (round A) and `work-e3/blind2/` (round B).

## DECISION bullets
- DECISION: the self-solve is a fresh Opus 5.5 subagent that saw only TASK.md and the fixture, not my own solve. As the author I cannot be blind.
- DECISION: every hidden test file uses a `test_zq_<x>_accept.py` stem, and every oracle is `_oracle_zq_<x>.py`. In round A a blind solver wrote `tests/test_semver_ranges.py`, the same basename as the hidden file. That aborted pytest collection with an import-file-mismatch error, so a correct solution would grade as 0. Other authors' hidden files may share the risk.
- DECISION: each hardened task keeps its id, because none had been delivered. The new declarative component is at least 55 % of the hidden cases, and the round-A mechanism cases are merged into fewer cases.
- DECISION: references grew past 600 changed lines on 07 and 08, to 639 and 727. I accepted up to 800 for the hardening round.
- DECISION: feature-v2-06 ships as a separate patch, s4-e3-f06.patch, so the patch already sent stays unchanged.
- DECISION (05): the new module is `docstore.delta`. Revert bumps the revision even when the diff is empty and ignores `max_ops`. The `diff ID REV` command runs from REV to the current document. Arrays in the tests have at most 10 elements and depth at most 6.
- DECISION (07): `*/1` counts as restricted. `count_between` and `nth_after` use a fixed 1096-day span. Unlike POSIX, a dst name requires explicit rules. `tz.py` is folded into `zones.py`, and `CronError` subclasses `ScheduleError`.
- DECISION (08): an unclosed group is an error, not a literal, and `**` inside a group is two stars. A leading `!` is stripped before group parsing, so `@(!(a))` is the workaround. Braces expand only in rule lines and the `match` pattern, the 256 limit counts before de-duplication, and a step of 0 is literal.

## Limitations
- The hardness bar is unmet on my measurement, for all three delivered tasks.
- One trial per task, with a subagent rather than the BARE arm in the image.
- feature-v2-06's notes file in work-e3 is stale; this report supersedes it.

## Fairness-reviewer handoff
- **05:** the oracle encodes rules 23–28 by brute force: combinations in lexicographic order, and the leftmost embedding for J. Possible misreadings are the sorted-key walk across both objects (rule 26), the I-then-J tuple order (rule 27), 0.0 == -0.0 (rule 23) and the diff direction (rule 35).
- **07:** the oracle encodes rules 1–18 and 21–31; the CLI rules are tested only by hand. Possible misreadings are the first-occurrence clause in `prev_before` (rule 21), the start read in standard time and the end in daylight time (rule 29), `n=365` in a common year (rule 28), and the order of the error reasons (rule 31).
- **08:** the oracle encodes G, B, X1–X7, BR1–BR8, R1–R9 and E1–E4. Possible misreadings are X5 (`a!(b)c`, and `!(*)x` against `x`), X2 (a bracket inside a group), the BR5 rescan, BR4's `{-01..1}` and C6's validate-first rule.
