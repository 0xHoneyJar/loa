# Fairness review — feature-v2-01

**Reviewer:** fairness session R2 (Claude Opus 5.5), 2026-10-17 · **Author:** implementer D2 · **Verdict:** PASS

## 1. No solution leak

PASS. `grep -ril hidden` over `TASK.md` and `fixture/` is empty. The only hit in the task directory outside `hidden/` is `task.yaml`, whose `success_criterion` and `reference_patch` name the grader paths by schema; `task.yaml` is grader-side. `TASK.md` and the fixture name no test file, test name, defect id, arm id or the acceptance overlay directory. The docstrings in `fixture/src/textpipe/` describe today's behaviour only.

Every hidden assertion traces to a `TASK.md` sentence:

| test (line) | asserts | TASK.md sentence |
|---|---|---|
| `test_config_and_command_line_definitions_apply_in_step_order` (27, 28) | config and `--define` definitions run their steps in order | "applying it to a line applies the steps in order"; the two definition bullets |
| same (31) | the config `apply` list may name a command-line definition | "After the registry is complete, every name to apply is looked up in it … the config file's `apply` list" |
| `test_command_line_replaces_config_which_replaces_builtin` (36–38) | command line replaces config, config replaces a built-in | "a config definition may replace a built-in filter, a command-line definition may replace either" |
| `test_steps_always_mean_the_builtin_filter` (43, 44) | `shout=[strip, upper]` still means the built-ins after `upper` is redefined and `strip` disabled | "a step keeps meaning the built-in filter even when that name has been redefined or removed" |
| same (45) | `b=a` where `a` is a definition is `unknown step a in b` | "a definition cannot use another definition"; table row "a step that is not a built-in filter" |
| `test_removal_deletes_the_name_and_brings_nothing_back` (50–53) | `--undefine`/`disable` of a redefined built-in leaves no filter; `--apply` error has no `config:` prefix | "it does not bring back a lower-precedence filter"; "errors about command-line values do not" |
| `test_removals_follow_definitions_within_a_source` (57, 59) | removal before definition in argv or JSON order still removes | "Within the config file and within the command line, definitions are applied first and removals second" |
| same (62) | config `disable upper`, then `--define upper=rev` works | "then the command line" |
| `test_unknown_names_in_removals_and_in_the_config_apply_list` (66, 68) | unknown removal from each source, with and without prefix | table row "a removed or applied name not in the registry" |
| same (70) | a config removal does not see a command-line definition | "A removal may name anything in the registry as it stands at that point" plus the source order |
| same (73) | config `apply` checked against the complete registry although `--apply` is given | "The config file's `apply` list is checked against the complete registry even when `--apply` is given" |
| `test_listing_is_sorted_with_sources` (80–86) | sorted, width of the longest name, built-in descriptions kept, `steps joined by " | " [source]` | the whole Listing section, including its example |
| `test_listing_of_an_empty_registry_prints_nothing` (93) | exit 0, empty output | "prints one line per filter in the complete registry … and nothing else" |
| `test_invalid_names` (98, 100; `Shout`, `9lives`, `a.b`, 33 chars) | `invalid filter name: <name>` from both sources | the name rule sentence; table row "a name that is not valid" |
| `test_longest_valid_name_and_boundary_characters` (106) | a 32-character name with digits, `_`, `-` is valid | "1–32 characters: a lowercase ASCII letter followed by lowercase ASCII letters, digits, `_` or `-`" |
| `test_definition_shapes` (111) | seven malformed `--define` values (no `=`, empty steps, empty step, trailing comma, empty name, a space, two `=`) | "exactly one `=`, a name before it and one or more non-empty comma-separated steps after it, with no spaces" |
| same (114, 116) | `[]`, a string, `["upper", 3]`, `null` as steps; `disable` as a string | table rows "not a non-empty list of strings" and "`disable` that is not a list of strings" |
| `test_unknown_steps` (120, 122) | unknown step from both sources | table row "a step that is not a built-in filter" |
| `test_duplicate_definitions_within_one_source` (126, 128) | twice in `--define`; a duplicate JSON key in `filters` | table row "twice in `--define`, or twice as a key of the config `filters` object" |
| same (131) | the same name in config and command line is a replacement | the precedence replacement sentence |

No assertion depends on error ordering: every error case has exactly one fault. Every message is stated verbatim in the table.

## 2. Red then green

Runner: `timeout 120 env PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider` on fresh copies under `mktemp -d`. The one manifest entry was overlaid at `tests/acceptance/test_user_filters.py` in both copies. `patch -p1 --batch --forward` applied cleanly to `cli.py`, `config.py`, `format.py`, `model.py` and `registry.py`, with exit 0 and no `.rej` or `.orig` files.

| run | `pytest -q tests` | `pytest -q tests --ignore=tests/acceptance` |
|---|---|---|
| base | `16 failed, 15 passed in 0.06s` | `15 passed in 0.02s` |
| reference | `31 passed in 0.04s` | `15 passed in 0.02s` |

All 16 failures at base are in the overlaid file, one per hidden case, counting the four `test_invalid_names` parameters. These counts match `success_criterion` exactly. The copies were deleted afterwards.

## 3. Criterion mechanical

PASS.

- **`success_criterion`** names the file, the overlay path, 16 of 16, 31 of 31, red at 16 failed and 15 passed, and the regression condition at 15 cases. Two graders would apply it identically.
- **`criterion`** is behavioural and names no path or test.
- **`grader_protected`** lists `tests/conftest.py`, `tests/helpers.py`, `tests/test_cli.py` and `tests/test_config.py`. That is every fixture test file. The fixture has no `pytest.ini`, `setup.cfg` or `pyproject.toml`.
- **`bounds`** are `{max_turns: {IMPLEMENT: 80, BARE: 190}, timeout_min: {IMPLEMENT: 35, BARE: 80}}`, which is the lead's stated bounds with the BARE sum.
- **`suite_version`** is 2. `source.kind` is `synthetic` and `date` is `2026-10-17`.
- **Fixture hygiene** holds. The fixture is 68K and has 13 files. It has no `__pycache__` or `.pyc`, nothing named `hidden*`, and no dotfile or dot-directory, so no `.claude/`, `.git/` or `.run/`. It also has no `CLAUDE.md`, `.loa.config.yaml` or `grimoires/`.

## Notes

- **Hardness read.** The correct change touches four or five modules. `load_config` today checks `apply` against the built-in registry at load time, so that check must move after the full build. The listing's `max()` crashes on an empty registry, and duplicate JSON keys need an `object_pairs_hook`. Every one of those edges is stated explicitly in `TASK.md`, so a careful bare Opus 5.5 agent with 170 turns will probably pass, which puts the a0_bare ≤ 0.5 bar at risk for this task. The likeliest bare misses are the duplicate JSON key, the empty listing, and a config removal that wrongly sees command-line definitions.
- **One mild reading point.** The shape sentence says "a name before it", and `a.b=upper` must give `invalid filter name: a.b`, not `invalid --define value`. The table's separate command-line "invalid filter name" row resolves that, because `--define` is the only command-line source of new names. It is not a FAIL.
- The reference's `--define` pattern `[^=,\s]+` also excludes Unicode whitespace. No test exercises that, and the spec says "no spaces" only.
- `--undefine` with an invalid name such as `Shout` is untested. The reference reports `unknown filter: Shout`, which the brief also allows.
