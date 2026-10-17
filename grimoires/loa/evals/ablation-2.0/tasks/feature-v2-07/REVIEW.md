# Fairness review — feature-v2-07

**Reviewer:** fairness session R3 (Claude Opus 5.5), 2026-10-17 · **Author:** implementer E3 (swap round 1) · **Verdict:** PASS

## 1. No solution leak

PASS. `grep -ri hidden TASK.md fixture/` is empty. A wider grep of TASK.md and the fixture for `oracle`, `zq_`, `acceptance`, `conformance` and the arm ids is also empty. TASK.md names no overlay path, no hidden test and no arm. It states 32 numbered rules with every message exact; rule 20 is skipped in the numbering, which is cosmetic. I read the test file and `_oracle_zq_cron.py` in full and checked them against the brief.

Hand-written cases in `test_zq_cron_accept.py`:

- `test_api_exports_and_error_class` (87) traces to the API section: `CronError` subclass of `ScheduleError`, the `cronq` re-exports and the six methods.
- `test_strictly_after_steps_ranges_and_lists` (101) traces to rules 9 and 17. `10:15:59` → `10:16:00` is "strictly after, whole minute". `*/100` → minute 0 only is "a step larger than the range selects only the start". `10/20` and `20/2` are "`a/s` means `a` through the field's maximum". `05 07` is "leading zeros allowed".
- `test_names_dow_seven_and_matches` (119) traces to rules 4, 7 and 12 and to the `matches` bullet ("seconds ignored"). `1-7/3` → Mon, Thu, Sun and `5-7` → Fri–Sun follow from "7 counts as Sunday".
- `test_macros_describe_and_unknown_macros` (135) traces to rule 2 and the `describe` bullet ("as written (stripped)", "joined by single spaces"). `@` alone and `@daily x` give the repr of the stripped text.
- `test_expression_and_value_errors` (149) traces to rules 1, 3, 5 and 7. `-5` → `bad value ''`, `*-5` → `bad value '*'` and `1-2-3` → `bad value '2-3'` follow from rule 9's "split at the first `-`" with the start then the end checked by rule 7. `007` is 7.
- `test_range_step_item_errors_and_order` (172) traces to rules 5, 6 and 9. `5-3/0` → reversed and `x/0` → bad value follow from "the base is checked first, then the step". `70-x` → out of range follows from "the start is checked completely by rule 7 before the end". `1/2/3` → `bad step '2/3'` is "split at the first `/`". `* 25 32 * *` reports field 2 by "left to right".
- `test_special_item_errors` (195) traces to rule 8 word for word. `0W` → value 0 is "its number is a value of the `dom` range". `XYZL` and `9#6` are "`<d>` checked as a `dow` value ... `<k>` checked after `<d>`". `L` in dow, `L/2` and `5L` in dom and `MON#x` are rule 8's own list of ordinary items.
- `test_last_and_nearest_weekday_days` (214) traces to rules 8, 12 and 15. I checked the calendar: 2026-08-01 is a Saturday so `1W` gives day 3. 2026-05-31 is a Sunday and the last day so `31W` gives the 29th. 2026-08-30 is a Sunday but not the last day so `30W` gives the 31st. `31W` in April and June picks nothing.
- `test_last_and_nth_weekday_of_month` (235) traces to rules 13 and 14. `5#5` skips February–April 2026, which have no fifth Friday.
- `test_day_field_combination` (247) traces to rules 10 and 12. `*/1` and `0-7` are restricted, so with the other day field restricted every day matches.
- `test_wall_time_gap_and_overlap` (266) traces to rules 16 and 17. The Lakeland `*/15` case from `01:10Z` is rule 17's last sentence: wall 02:15–02:45 already occurred at `00:15Z`–`00:45Z`, so the next fire is `03:00+01:00`.
- `test_horizon` (285) and `error_of_next` (294) trace to rule 18, including "at most `horizon_days × 86400` seconds" being inclusive (`horizon=31` reaches 02-01).
- `test_schedule_jobs_and_config_integration` (301) traces to the `parse_schedule` bullet. `parse_schedule("cron")` → `empty expression` is "minus its leading word `cron`" then rule 1. The `jobs:2: bad schedule:` text is the fixture's existing jobs error path. The config's `horizon_days` reaches the job.
- `test_agenda_with_cron_jobs` (322) traces to rule 19. The agenda stops a job when it runs out of fires, and `no upcoming runs` is the fixture's existing text. The runner records `leap fires=1` and does not raise.
- `test_runner_with_cron_jobs` (342) traces to the runner's documented catch-up rule plus rule 17. Over `(23:45Z, 02:15Z]` in Lakeland the fire set is `00:00Z`, `00:30Z` and `02:00Z`. The repeated `01:00Z` and `01:30Z` do not fire, so the entry is `02:00:00Z half fires=3`.
- `test_cli_next_and_validate` (364) traces to rule 32. The horizon message `horizon must be an integer 1..36600, got '0'` is the fixture's `positive_int` form for `count`, as rule 32 says. The unknown-zone text is the fixture's `lookup`. The horizon miss after one line matches "printed after those lines". The `validate` line uses `describe()`.
- `test_prev_before_*` (413–438) trace to rule 21 and the definition of F. `2026-10-25T03:00Z` → `00:30Z` is the first occurrence of 02:30. The gap cases skip the nonexistent 02:30 on 03-29. `[t − H·86400, t)` is inclusive at the low end (`horizon=31` reaches 01-01).
- `test_count_between_*` (448–475) trace to rule 22. `(start, end]` gives `09:59:59 → 10:00:00` = 1 and `t, t` = 0. Lakeland 2026 has 8759 hourly fires because one hour is skipped and the repeated hour fires once. The span limit is inclusive at exactly 1096 days, and `end before start` is checked first.
- `test_nth_after` (478) and `test_nth_after_errors` (490) trace to rule 23. `horizon_days` plays no part. The window is 1096 days, so daily 1096 reaches 2029-01-01 and 1097 fails.
- `test_cli_prev_and_count` (502) traces to rule 33 ("mirror of `next`", `--tz` on `prev`, one integer line, the `count_between` error through `cronq: <message>`).
- `test_tz_standard_only_zones_and_the_sign` (536) traces to rules 26, 27 and the `parse_tz(text, name="TZ")` bullet. The sign cases (`EST5` → −300, `<+0330>-3:30` → 210, `BBB-14` → 840) are the bold sentence in rule 27.
- `test_tz_month_week_day_rules` (546) traces to rules 28–30. 460 changes is two per year over 1970–2199. `M2.5.0` in February 2026, which has four Sundays, is "the fourth when there is no fifth". The end at `M5.5.6/0` read in daylight time gives `2026-05-29T23:00Z`.
- `test_tz_explicit_daylight_offset` (559), `test_tz_julian_and_zero_based_days` (565), `test_tz_transition_times_beyond_the_day` (575) and `test_tz_southern_hemisphere` (583) trace to rules 27–30. `J60` is March 1 in 2028. `59` is February 29 in 2028. `365` in 2026 is January 1, 2027 local, which lands on 2026-12-31T23:00Z. `/167`, `/-1`, `/26` and `/-2:30` move the day. The southern case needs no special handling.
- `test_tz_errors_in_names_and_offsets` (589) and `test_tz_errors_in_rules_and_times` (603) trace to rule 31's ordered list. I walked every case. `EST5,M3.2.0,M11.1.0` is "followed by anything other than the end, `<` or a letter". `EST5EDT;` is "the daylight part followed by a character other than `,`". `EST5EDT4` is "ends after the daylight part". `EST5EDT,M3.2.0` (date then end) → `bad start rule`, while `EST5EDT,M3.2.0/2` would be `bad start time`, exactly as the two sentences say. `M3.2.07` gives `bad start rule` under any reading of the digit run.
- `test_zone_file_rule_entries` (619) traces to rule 24: `second rule`, `rule and table entries cannot be mixed` in both orders, and `zones:2: dst rules required`.
- `test_cron_in_rule_zones` (638) and `test_cli_tz_option` (647) trace to rules 30 and 33, including `--zone and --tz are exclusive` and `cronq: dst rules required`.

Conformance (18 seeded cases) compares the implementation to `_oracle_zq_cron.py`. I traced these oracle branches to the brief:

- `parse_field` (61): specials only when the whole item has the shape. `<digits>W`, `<d>L` with `<d>` digits or exactly three letters, and `<d>#<k>` split at the first `#` with `d` checked before the `k` range. Everything else falls to the ordinary path, splitting at the first `/` and then the first `-`, with base before step. This is rules 8 and 9.
- `number` (36): ASCII digits, month names only in field 4, day names only in field 5, case-insensitive, then the range message. This is rule 7.
- `dom_ok` (148) for `W`: Saturday → n−1 unless n = 1 (→ 3), Sunday → n+1 unless last (→ n−2), and nothing when the month lacks day n. This is rule 15. `dow_ok` (177): `d + 7 > last` and `(d−1)//7+1 == k` are rules 13 and 14. `day_ok` (190): unrestricted is exactly `text == "*"`, otherwise EITHER. This is rules 10 and 12.
- `Timeline.seen_before` (223) tests whether the wall minute occurred at an earlier instant under any offset the zone uses, which is the F definition and rule 17. The day/hour jumps in `fires_forward`/`fires_backward` never cross a transition mark, so they are optimisations, not semantics.
- `next_after`/`prev_before`/`count_between`/`nth_after` (281–314): the bounds `t//60+1 … (t+H·86400)//60`, `ceil((t−H·86400)/60) … ceil(t/60)−1`, `(a, b]`, and `n < 1` before the 1096-day count. These are rules 18 and 21–23 with their messages. Error order in `count_between` is "end before start" then span.
- `read_clock` (372): longest digit runs, h ≤ 2 digits ≤ 24 for offsets and ≤ 3 digits ≤ 167 for times, mm exactly two digits ≤ 59, ss must be `00`. This is rules 27 and 29. `read_name` (355): the first `>` closes a quoted name, which needs at least three of `[A-Za-z0-9+-]`; an unquoted name is the longest letter run, at least three letters. This is rule 26.
- `parse_tz` (418): the follow-character checks and their order match rule 31 clause by clause. `rule_day` and `tz_timeline` (462–493): J via a common year, n counting February 29, M with week 5 as last, start minus standard and end minus daylight, sorted with start before end at a tie. This is rules 28–30.

No hidden assertion depends on a choice the brief leaves open.

## 2. Red then green

PASS. On a fresh `mktemp -d` copy of `fixture/` with both manifest entries overlaid under `tests/acceptance/`, `patch -p1 --batch --forward -s < hidden/reference.patch` exited 0 with no `.rej` or `.orig`. Every run was `timeout 300 env PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider …`.

| run | `pytest -q tests` | `pytest -q tests --ignore=tests/acceptance` |
|-----|-------------------|---------------------------------------------|
| base | `56 failed, 36 passed in 1.04s` | `36 passed in 0.05s` |
| reference | `92 passed in 6.12s` | `36 passed in 0.05s` |

There are 39 `test_` functions. One is parametrized over 18 conformance names, which gives 38 hand-written cases plus 18 conformance cases, 56 in all. 22 hand cases and 12 conformance cases cover prev, count, nth and rule zones, which is the stated 34. Every count matches `success_criterion`. The copies were deleted with `find -mindepth 1 -delete`.

## 3. Criterion mechanical

PASS.

- `success_criterion` is one line. It names the file, the overlay path and the oracle beside it, the counts at both ends (56 failed / 36 passed, then 92 passed) and the regression condition (36 green at both ends).
- `criterion` is behavioural and names no path or test.
- `grader_protected` is `[tests/conftest.py, tests/test_cronq.py]`. These are the only fixture test files, and the fixture has no ini, `setup.cfg` or `pyproject.toml`.
- `bounds` is exactly `{max_turns: {IMPLEMENT: 80, BARE: 190}, timeout_min: {IMPLEMENT: 35, BARE: 80}}`.
- `suite_version` is 2, `source.kind` is `synthetic`, and `date` is `"2026-10-17"`.
- The fixture is 13 modules under `src/cronq/` plus two test files. It holds no `__pycache__`, `.pyc` or `.pytest_cache`, nothing named `hidden*`, and no `.claude/`, `CLAUDE.md`, `.loa.config.yaml`, `grimoires/`, `.run/` or `.git/`.
- Both overlay `dest` values are under `tests/`.

## Notes

- **Hardness read (decides nothing):** The correct change touches 8 files. It needs a new cron module, the rule-zone parser in `zones.py`, schedule, errors, the package exports, agenda, runner and the CLI. The conformance cases are all-or-nothing over 250–1000 seeded samples each, covering malformed cron items, malformed rule strings, gap/overlap wall times near every transition, and half-hour and 45-minute offsets. Even so, the brief is complete and mechanical, and 38 of 56 cases are hand-written. A bare Opus 5.5 with 190 turns would very likely pass more than half, and probably all. The author's own blind self-solve scored 56/56 in minutes, according to the handoff notes.
- The fixture suite holds 36 cases on the interval schedule, the zone table, the agenda and the runner. They stop shortcuts that would break the existing agenda format or catch-up rule.
- `test_count_between_errors_and_the_span_limit` counts about 1.58M every-minute fires. A naive per-minute implementation is slow but stays well inside the 300-second limit.
- `ZONE_LIST` and `TRANSITIONS` are defined twice in the test file, at lines 390 and 659, with the same values. This is harmless.
