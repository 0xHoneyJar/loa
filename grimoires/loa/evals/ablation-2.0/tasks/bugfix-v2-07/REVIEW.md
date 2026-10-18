# Fairness review — bugfix-v2-07 (second review)

**Reviewer:** R3 (Claude Opus 5.5), 2026-10-17 · **Author:** D3 (swap round 1) · **Verdict:** PASS

This is the second review. The lead corrected the brief after the first review's check-1 FAIL.

- **The first review's finding.** Rule 21 stated `<blockquote>` + `\n` for every block quote. The oracle and markdown-it 14.1.0 render a quote with no children as `<blockquote></blockquote>`. Empty quotes occur in all 15 conformance profiles, so a brief-literal solver capped at 20/35. Rule 9's "consists only of `#` and spaces, it is empty" was also wrong for `# # #`.
- **What changed.** `git diff` against the index shows two sentences changed in TASK.md and nothing else. Rule 21 now adds: "A block quote with no children is `<blockquote></blockquote>` + `\n` (no newline between the tags, as for an empty item in rule 22)." Rule 9 now reads: "If the content is a single run of `#` and nothing else, the heading is empty. Otherwise a final run of `#` …". The fixture, the hidden tests, the oracle, the manifest, the reference patch and task.yaml are unchanged.

## 1. No solution leak / fair

PASS.

- **Leak checks.** `grep -ri hidden TASK.md fixture/` is still empty. TASK.md names no arm id, test name, oracle module or overlay path. The criterion is behavioural.
- **The oracle agrees with both corrected sentences.**

```
'>\n'      -> '<blockquote></blockquote>\n'
'- >\n'    -> '<ul>\n<li>\n<blockquote></blockquote>\n</li>\n</ul>\n'
'# #\n'    -> '<h1></h1>\n'
'# # #\n'  -> '<h1>#</h1>\n'
'### #\n'  -> '<h3></h3>\n'
```

- **Every conformance profile now traces.** The only branch that disagreed in the first review was the `nxt.nesting == -1 and nxt.tag == token.tag` newline rule in `render_token`, applied to a block quote. Corrected rule 21 now states it. I applied the corrected rule 9 literally across all 4,050 generated documents of the 15 profiles. It changes no rendering. The nine oracle branches sampled in the first review still trace to rules 13 to 20 and 22. Those branches cover item continuation and the empty-item blank rule, fence closing, indented-code blanks, marker spacing, paragraph interruption, list matching, the indented-code tip test, looseness by end lines and the newline after a hidden paragraph.
- **The scenario tables still trace.** All 20 tables trace row by row to the brief, as in the first review. No table row has an empty quote or a `#`-only heading beyond `### #` and `#`, and both match corrected rule 9.
- **Minor, not blocking.** A `#`-only content followed by trailing spaces, such as `# ##  `, is empty in the oracle. A strictly literal reading of corrected rule 9 keeps `##`. The generators strip trailing spaces from every line and no table row has the form, so no graded case depends on it. The class attribute's escaping (`language-a&amp;b`) is still not stated in rule 21. The fixture already escapes it and nothing asks the solver to change it.

## 2. Red then green

PASS, rerun on the corrected tree. I used fresh copies under `mktemp -d`, overlaid both manifest entries at `tests/acceptance/`, and ran `patch -p1 --batch --forward -s` (exit 0, no `.rej`). Every run was `timeout 300 env PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider`.

| run | `tests` | `tests --ignore=tests/acceptance` |
|-----|---------|-----------------------------------|
| base | `35 failed, 28 passed in 2.11s` | `28 passed in 0.02s` |
| reference | `63 passed in 3.60s` | `28 passed in 0.02s` |

The counts match `success_criterion` exactly, and they are the same as in the first review. The reference adds no test file.

## 3. Criterion mechanical

PASS, unchanged from the first review.

- `success_criterion` is one line. It gives the overlay path, the counts at both ends and the regression condition.
- `grader_protected` lists `tests/conftest.py`, `tests/test_cli.py`, `tests/test_containers.py` and `tests/test_leaves.py`. That is every fixture test file, and the fixture has no ini, pyproject or setup.cfg.
- The bounds are `{max_turns: {IMPLEMENT: 80, BARE: 190}, timeout_min: {IMPLEMENT: 35, BARE: 80}}`. The task has `suite_version: 2`, `source.kind: synthetic` and `date: "2026-10-17"`.
- The fixture holds no cache and no dotfile. Nothing in it is named `hidden*`, and it has no `.claude/`, `CLAUDE.md`, `.loa.config.yaml`, `grimoires/` or `.run/`. Both overlay `dest`s are under `tests/`.

## Notes

- **Hardness read.** The correct change touches 8 files (about 260 lines, including a new token module), and each conformance case spans the whole surface, so any leftover deviation fails most of the 15. A bare agent with 190 turns and 80 minutes plausibly lands near the 0.5 line rather than well above it. The deciding factor is whether it audits all of rule 19's end-line rules and rule 22's newline rules, which the fixture suite's 28 cases do not constrain.
- **The earlier blind self-solve is stale.** The author's 20/35 matches the ceiling the old brief imposed. The calibration smoke on the corrected brief is the measurement that counts.
