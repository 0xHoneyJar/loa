# Fairness review — bugfix-v2-06

**Reviewer:** R3 (Claude Opus 5.5), 2026-10-17 · **Author:** D3 (swap round 1) · **Verdict:** PASS

## 1. No solution leak / fair

PASS.

- `grep -ri hidden TASK.md fixture/` is empty. A grep for `oracle`, `acceptance`, `resolution_rules`, `grader` and `reference.patch` over TASK.md and the fixture is also empty. No arm id, test name or overlay path appears in agent-facing text.
- The brief is a numbered rule set (V1–V5, P1–P5, R1–R9, S1–S4, N1–N2, I1–I4). Every hand-written table traces to a stated rule:
  - `test_version_validity_table` traces to V1–V4, including `vv1.2.3`, `V1.2.3`, `=1.2.3` and the unstripped `repr` in the message.
  - `test_precedence_table` and `test_sorting_table` trace to P1–P5. `Beta<alpha` is ASCII order (P3). The stable descending sort is stated in P5.
  - `test_caret_table`, `test_tilde_table`, `test_partials_under_operators_table`, `test_wildcards_and_x_ranges_table` and `test_hyphen_table` trace to R4–R7 and R9. Several rows are spelled out word for word in R6 and R9, such as `^0.0.3`, `^0.0`, `^0` and `>1.2 <=2`.
  - `test_prerelease_rule_table` traces to R8. Its examples are R8's own.
  - `test_whitespace_and_empty_sets_table` traces to R1–R3. `test_malformed_ranges_table` traces to R2–R4 and R9. One example is `>=1 - 2`, which is invalid because `>=1` is not a partial version (R2).
  - The `test_index_*` tables trace to S2–S4 and N1. They cover first-in-input-order ties, the item returned as given, invalid entries skipped, `len`, a snapshot at construction and a `Range` argument.
  - `test_increment_table` traces to I1–I4.
  - `test_report_and_lock_scenario` traces to the docstrings of the report and lock modules. TASK.md points the reader there.
- **Oracle sample.** These branches of the reference model were checked against the brief:
  - `o_parse` strips first, then accepts at most one `v` (V1).
  - `_ident_key` follows P3.
  - `_expand` follows R5 and R6 branch for branch. The caret upper bound is `M > 0 or m is None`, then `m > 0 or p is None`, then `^0.0.Z`. Primitive partials follow the R5 table.
  - `_hyphen` follows R7.
  - The `o_range` operator-gap rule rejects a missing partial version or a following operator (R3).
  - `_test_set` applies R8 within one set only.
  - `o_max` and `o_min` break ties by lowest input index (S2).
  - `o_inc` follows I1–I4 and checks in the order version, kind, preid.
  - `o_report` and `o_check_lock` match the module docstrings.
- **Two readings are worth recording. Neither is a FAIL.**
  - `^0.x` gives `<1.0.0-0`, from the caret row and the R6 rule. A wildcard component counts as not given. R4 says missing components count as wildcards. Reading `0.x` any other way makes `<0.(Y+1).0-0` undefined, and npm agrees.
  - A preid is validated for `major`, `minor` and `patch` too, from conformance via `gen_inc_args`. I1 orders the checks as "then checks the kind, then the preid" for every kind. "Ignored" applies to the result. The fixture's own `_check_preid` already behaves this way, and the brief says to keep existing behaviour.
- **N2 timing rule.** `test_index_answers_quickly` times exactly 1,000 queries over 50,000 versions, as N2 states. The limit is 5 s. Measured times:

| run | time |
|-----|------|
| reference, 3 runs | 0.48–0.54 s |
| base | 0.51 s |
| reference full suite pinned to one core | 5.15 s total |

  That is about a 10× margin, so flakiness inside a CPU-limited container is unlikely. The case is green at base, which makes it a regression guard and not a red case. A correct rewrite that scans every entry would fail it, and N2 states that explicitly. The author asks for a rerun in the image, and that is still worth doing.

## 2. Red then green

PASS. Fresh copies of `fixture/` were used. Both manifest entries were overlaid at `tests/acceptance/`. The reference was applied with `patch -p1 --batch --forward -s`, which exited 0 and left no `.rej` or `.orig`. The runner was `timeout 300 env PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider`.

| run | `tests` | regression (`--ignore=tests/acceptance`) | hidden only |
|-----|---------|------------------------------------------|-------------|
| base | `35 failed, 35 passed in 3.01s` | `34 passed in 0.03s` | `35 failed, 1 passed`, and the green one is `test_index_answers_quickly` |
| reference | `70 passed in 5.72s` | `34 passed in 0.04s` | 36 of 36 |

The counts match `success_criterion` exactly. The reference adds no test file.

## 3. Criterion mechanical

PASS.

- `success_criterion` is one line. It names the overlay paths, the counts at both ends and the green regression condition.
- `criterion` is behavioural and names no path or test.
- `grader_protected` lists `tests/conftest.py`, `tests/test_ranges.py`, `tests/test_tools.py` and `tests/test_versions.py`. The fixture has no ini, pyproject or setup.cfg.
- `bounds` is `{max_turns: {IMPLEMENT: 80, BARE: 190}, timeout_min: {IMPLEMENT: 35, BARE: 80}}`.
- `suite_version` is 2. `source.kind` is synthetic and `date` is "2026-10-17".
- The fixture is 92K. It holds no cache, nothing named `hidden*`, no dotfiles, `.claude/`, `CLAUDE.md`, `.loa.config.yaml`, `grimoires/`, `.run/` or `.git/`.
- Both overlay destinations are under `tests/`.

## Notes

- **Hardness read.** The reference touches 8 of the 14 modules, about 200 changed lines. Each of the 15 conformance cases draws from the whole public surface: parse, precedence, desugaring, the R8 set rule, index ties and bounds, increments, report and lock. So one residual deviation fails many cases. The spec is fully declarative and largely npm-semver shaped, though. Domain memory and a self-written brute-force check carry a thorough agent far. The author's blind solve scored 1.0 in 2.2 minutes, so a bare Opus 5.5 agent with 190 turns and 80 minutes will very likely exceed 0.5, and this task may not meet the calibration bar.
- The 34 fixture tests constrain little. They are green at base, so they do not block shortcuts. The N2 timing case is the one guard against a correct but linear rewrite of the index.
- The author's notes say the planned intersects and subset part was not delivered.
