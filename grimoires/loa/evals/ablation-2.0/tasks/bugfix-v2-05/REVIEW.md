# Fairness review — bugfix-v2-05

**Reviewer:** fairness session R3 (Claude Opus 5.5), 2026-10-17 · **Author:** D3 (swap round 1) · **Verdict:** PASS

## 1. No solution leak / fair

PASS.

- `grep -ri hidden TASK.md fixture/` prints nothing (exit 1). TASK.md names no arm id, no test name, no overlay path and no oracle. The criterion names behaviour only.
- The brief is a declarative 15-rule spec: a stated six-zone table, wall time `u + offset(u)`, the fire-time definition over whole UTC minutes, the day specials, the either-day rule, the error order and texts, and the CLI line format. Every hand-written assertion traced to a rule. I recomputed each scenario by hand from the brief:
  - `test_backward_transition_repeats_wall_times` (line 32): north end 2026-10-25 01:00 UTC, west end 2026-11-01 06:00 UTC, south end 2027-04-04 15:00 UTC, midnight end 2027-02-21 02:00 UTC. Rules 3, 5 and 11 give the repeated instants, and `15 2` in south fires once (15:45) because 15:15 has offset 630.
  - `test_forward_transition_skips_wall_times` (line 53): north 02:30 on 2026-03-29 is skipped, south 02:10 on 2026-10-05 is skipped, midnight 00:00 on 2026-11-01 is skipped (rule 11, "a wall time skipped by a forward transition does not fire that day").
  - `test_inputs_between_whole_minutes` (line 64): rules 1, 2, 11 and 12 (floor for `matches`/`offset`/`wall`, strict `<`/`>` for prev/next, `start ≤ u < end`), the UTC `tzinfo` and the `ValueError` prefix of rule 1.
  - `test_day_fields_either_rule` (line 86) and `test_steps_and_ranges` (line 96): rule 9 (`*/1` restricted, `?` unrestricted) and rule 6 (`*/n` from the minimum, `a/n` = `a-<max>/n`, `MON/2` reaches 7 = Sunday). February 2026 starts on a Sunday, so `1-3 * */7` gives 1, 2, 3, 8, 15, 22.
  - `test_nearest_weekday_edges` (line 105): rule 7's two stated edge examples (Saturday 1st → Monday 3rd, Sunday last day → Friday two days earlier), nearest weekday otherwise, nothing without day `n`.
  - `test_expression_errors` (line 167): every message follows rule 10's order. Examples: `70/0` reports the step first, `L/2` reports `invalid day-of-month value` because specials take no step, `1,,2` reports `''`, `8L` reports out of range, `L` in day of week is invalid, and `MON` in month is invalid.
  - `test_upcoming_and_catch_up` (line 188): rule 13's ties follow job order (zeta before alpha), and rule 14's `last_run < u ≤ now`. `test_command_line` (line 204) uses rule 15's format, exit codes 0/1/2, and the repr of the argument text. `test_horizon` (line 225) uses 2922 days.
- I sampled the oracle's branches against the brief. All match:
  - `_field`: `L-n` 1–30 and `nW` 1–31 ranges, `d#k` with `k` 1–5, `dL`, step before values, values before range, names only in their own field, `?` only in day fields, ASCII digits only.
  - `day_ok`: the either/one/neither rule.
  - `_special_hit` W branch: Saturday gives `n-1`, or `n+2` on the 1st. Sunday gives `n+1`, or `n-2` on the last day.
  - `offset`: inclusive start, exclusive end, and the wrapped period when start > end.
  - `instants_of`: candidate offsets checked for consistency.
  - `minutes_of` floor/ceil: matches rules 2, 11, 12 and 14.
  - `upcoming`: chained `next_fire`, ordered by (instant, position). This is the literal "all fire times after `after`".
  - `parse`: the macro is stripped, matched case-insensitively and its repr is reported. The BAD list cases (`LW-1`, `x#1`, `?/x`, `* ? * * *`) all follow rule 10.
- **Advisory, not a fail.** Three spots in the grading file use fixture attributes that TASK.md does not document. None of them is a behavioural assertion. Each is existing fixture surface that the brief tells the solver to keep ("keep the public names"), and the reference keeps it.
  - `walls()` (line 21) reads `schedule.zone`.
  - Line 79 builds `Job("j", s)` positionally, which is the fixture dataclass.
  - `_check_sample` (line 319) reads `ZONES[zone].dst`.

  The `.dst` read sits in the `zone` branch of every conformance case. A solver who renamed the Zone dataclass field would fail all 15 generated cases with an AttributeError. Switching line 319 to `oracle.ZONES[zone][1] is not None` would remove that exposure. I judge the risk low because a bug fix has no reason to rename that field.

## 2. Red then green

PASS. I used fresh copies under `mktemp -d`, overlaid both manifest entries at `tests/acceptance/`, and ran `patch -p1 --batch --forward -s` in the reference copy. The patch exited 0 and left no `.rej`. Each run was `timeout 300 env PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider …`.

| run | `pytest -q tests` | `pytest -q tests --ignore=tests/acceptance` |
|-----|-------------------|---------------------------------------------|
| base | `28 failed, 35 passed in 0.45s` | `33 passed in 0.04s` |
| reference | `63 passed in 26.26s` | `33 passed in 0.04s` |

At base, 13 of the 15 tables fail. `test_nth_weekday` and `test_horizon` pass, and all 15 generated cases fail. That is 2 of 30 hidden green plus the 33 fixture cases, which matches `success_criterion` exactly. The reference touches 8 of the 13 modules.

## 3. Criterion mechanical

PASS.

- `success_criterion` is one line. It names the file, both overlay paths and the exact counts at both ends (28 failed, 35 passed of 63, then 63 of 63). It also states the regression condition (33 cases green at both ends).
- `criterion` is behavioural and names no path or test.
- `grader_protected` lists `tests/conftest.py`, `tests/test_expressions.py`, `tests/test_schedule.py` and `tests/test_zones.py`. Those are all the fixture test files. The fixture has no ini, pyproject or setup.cfg.
- The task file sets these fields correctly:
  - `bounds` is `{max_turns: {IMPLEMENT: 80, BARE: 190}, timeout_min: {IMPLEMENT: 35, BARE: 80}}`.
  - `suite_version: 2`, `source.kind: synthetic` and `date: "2026-10-17"`.
- The fixture is 84K. It holds no `__pycache__`, `.pyc` or `.pytest_cache`, and nothing named `hidden*`. It has no `.claude/`, `CLAUDE.md`, `.loa.config.yaml`, `grimoires/`, `.run/` or `.git/`.
- Both overlay `dest`s are under `tests/`.

## Notes

- **Hardness read.** A bare Opus 5.5 agent with 190 turns and 80 minutes probably reaches above 0.5 only if it finds every deviation. The correct change touches 8 modules. The fixture's 33 tests do not constrain the DST search, the leap-February cache, the rounding or the error order. Every generated case samples the whole surface: all six zones with heavy weight near transitions, every day special, macros, the BAD error list, jobs and the CLI. So one leftover deviation fails most of the 15 generated cases and scores at or below 0.5.
- **Author's self-solve evidence.** The author reports two blind self-solves: 0.47 under a 10-minute framing on an earlier version, and 1.0 under a 30-minute framing where the solver wrote its own brute-force check. An agent that builds a minute-by-minute checker from the brief can pass, so the 190-turn bare arm can plausibly exceed 0.5. The calibration smoke decides.
- **Reference runtime.** The reference suite takes about 26 s on the host because of the brute-force oracle. That is well inside `timeout 300`.
