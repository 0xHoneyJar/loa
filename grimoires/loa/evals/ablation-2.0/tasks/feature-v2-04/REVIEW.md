# Fairness review — feature-v2-04

**Reviewer:** fairness session R1 (Claude Opus 5.5), 2026-10-17 · **Author:** implementer E2 · **Verdict:** PASS

## 1. No solution leak

PASS. `grep -ri hidden` over `TASK.md` and `fixture/` is empty, and neither names an arm id, a test or the overlay path. The test calls `parse_rule(text, source, line)` and reads `Rule.effect`, `Rule.source` and `Rule.line`. The brief does not name these, but they already exist in the fixture's `rules.py` with those signatures, so no new API is assumed. Every hidden assertion traces to a sentence:

- `test_deny_by_default_and_for_unknown_users` traces to "When no rule matches at all, the answer is deny", "A user missing from the users file has no groups", "When nothing matched it is `deny by default`", "`rule` (… `None` when nothing matched)", and `*` meaning anyone.
- `test_single_and_double_star_segments` traces to the `PATTERN` bullet: `*` is exactly one segment, `**` is zero or more, `/docs/**` matches `/docs`, and `/**` matches every path, including `/`.
- `test_explicit_deny_beats_allow_of_the_same_specificity` traces to deciding step 3 and the explain format.
- `test_a_more_specific_allow_beats_a_broader_deny` traces to step 2's first comparison, more literal segments.
- `test_specificity_order` traces to the three-part order. `/a/b/**` beats `/a/*/*` on literals. `/a/b/*` beats `/a/b/**` on "without `**`". `/a/**` beats `/a/*/**` on fewer `*` segments, and the `/a` case uses "a `**` segment is not a `*` segment" and zero-segment `**`.
- `test_principal_and_action_wildcards_do_not_change_specificity` traces to "The principal and the action never affect specificity".
- `test_overrides_beat_the_policy_whatever_their_specificity` and `test_overrides_only_count_when_one_matches` trace to deciding step 1 and to `Evaluator(directory, policy, overrides=())`. `overrides:2` after a comment line uses the fixture's existing line numbering, which counts every file line.
- `test_paths_and_patterns_are_normalised` traces to "Repeated and trailing slashes are dropped, exactly as for a request path", "with the four fields as written in the file", and "a bad path still raises `PathError`".
- `test_the_deciding_rule_is_the_first_winner_in_file_order` traces to "The deciding rule is the first rule, in file order, among the rules left after step 2 whose effect is the answer". Both tie cases follow from it. In the allow tie, rule 1 wins. In the deny tie, rule 2 wins, because it is the first deny among three equally specific rules.
- `test_malformed_rules` (14 inputs) traces to the eight ordered reasons and "`<repr>` is the `repr` of the field as written". `**` as an action fails rule 4, since an action is "a name or `*`". `/docs/***` fails rule 7 before rule 8. The two multi-fault lines check the order: effect before principal, and principal before action and pattern. The valid `bob.smith-2 x_y.z` uses the name alphabet `A-Z a-z 0-9 _ . -`.
- `test_cli_overrides_and_explain` and `test_cli_reports_a_malformed_override` trace to the command-line paragraph: `--overrides`, `--explain` replacing `allow` / `deny`, and "exit status 2 and `permit: <message>` on standard error", together with the `<source>:<line>: <reason>` error form.

No assertion depends on a choice the brief leaves open.

## 2. Red then green

Runner: host Python 3.13.5 and pytest 9, `PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider`, a fresh `fixture/` copy per side, the manifest file at its `dest`, and the reference applied with `patch -p1` after a clean dry run, leaving no `.orig` or `.rej`.

```
[base] pytest -q tests                         => 13 failed, 21 passed in 0.08s
[base] pytest -q tests/acceptance              => 13 failed in 0.07s
[base] pytest -q tests --ignore=tests/acceptance => 21 passed in 0.02s
  patching file src/permit/cli.py
  patching file src/permit/engine.py
  patching file src/permit/paths.py
  patching file src/permit/rules.py
[ref]  pytest -q tests                         => 34 passed in 0.04s
[ref]  pytest -q tests/acceptance              => 13 passed in 0.03s
[ref]  pytest -q tests --ignore=tests/acceptance => 21 passed in 0.02s
```

The counts match `success_criterion`. The hidden file fails 13 of 13 at base and passes at the reference. The regression command passes 21 cases at both ends.

## 3. Criterion mechanical

PASS. `success_criterion` is one line naming the file, the overlay path, the counts at both ends and the regression condition. `criterion` is behavioural and names no path or test. `grader_protected` lists `tests/conftest.py` and `tests/test_permit.py`, and the fixture has no ini or pyproject. `bounds`, `suite_version: 2`, and `source.kind: synthetic` with the date 2026-10-17 all match the rules. The fixture is 56K and clean. `no-secrets.sh` exits 0.

## Notes

- **Hardness:** moderate. The reference adds about 120 lines in four files, and the brief states the specificity key, tie-breaks and error order exactly. The likely slips are counting `**` as a `*` segment, letting a principal or action wildcard change specificity, picking the deciding rule before filtering by effect, and checking pattern faults in the wrong order. A bare agent that encodes specificity as a sort key probably passes.
