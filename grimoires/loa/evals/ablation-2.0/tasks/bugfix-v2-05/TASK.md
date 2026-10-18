# Task: scheduled jobs fire at the wrong times

`cronzone` (under `src/cronzone/`) evaluates cron expressions in zones with daylight saving. The package exports `CronExpr`, `Schedule`, `Zone`, `ZONES`, `get_zone`, `Job`, `upcoming`, `catch_up` and `CronError` (a `ValueError`); `cronzone.cli.main(argv, stdout, stderr)` is the command line.

- `Schedule(expression, zone="utc")` (zone: a name from the table below or a `Zone`) has `next_fire(after)`, `prev_fire(before)`, `next_fires(after, count)`, `fires_between(start, end)` and `matches(instant)`.
- A `Zone` has `offset(instant)` (minutes east of UTC), `wall(instant)` (naive wall-clock datetime), `instants(wall)` and `transitions(year)`.
- `Job.create(name, expression, zone="utc")` makes a job (`job.name`, `job.schedule`); `upcoming(jobs, after, count)` and `catch_up(job, last_run, now, policy="all")` work on jobs.

The implementation deviates from the specification below in several places that interact. The symptoms under **Bug (observed)** are the ones users reported; they are not the complete list. The code must conform to **every** rule under **Expected**, exactly as written, including error types and message texts. The module layout and the existing tests may guide you, but the rules decide.

## Bug (observed)

- On the night the clocks go back in `north`, `fires_between` for `30 * * * *` lists the wall time 02:30 only once.
- `0 12 L * *` in `utc` fires on 28 February 2028 (a leap year) after it has been used for February 2026 (or the other way round, depending on which month was asked first).
- `prev_fire` of `* * * * *` at 10:00:30 UTC returns 09:59 instead of 10:00; `fires_between(t, …)` leaves out `t` itself when `t` is a fire time.
- In `south` the offset is +10:30 all year.
- `0 9 1W * *` never fires in a month that starts on a Saturday.

## Expected

### Instants and wall time
1. Instants are timezone-aware `datetime`s; every method that takes one raises `ValueError` with the message `expected a timezone-aware datetime, got <repr>` for anything else (a naive `datetime` included). Every instant returned is an aware `datetime` in UTC (`tzinfo` is `datetime.timezone.utc`) with zero seconds and microseconds. Fire times are whole UTC minutes.
2. The wall time of a whole minute `u` in a zone is `u + offset(u)`, as a naive `datetime`, where `offset(u)` is the zone's offset in effect at `u`. For an instant that is not a whole minute, `offset` and `wall` use the whole minute at or before it.

### The zone table
3. A transition rule `(month, nth, weekday, hh:mm)` is the UTC instant `hh:mm` on the `nth` `weekday` of `month` of a year (UTC dates; `last` is the last such weekday). A zone with daylight saving uses its saving offset from its start transition (inclusive) to its end transition (exclusive) in each year; for a zone whose start month is later than its end month the saving period runs from the start transition of a year to the end transition of the next, so in each year the saving offset applies before the end transition and from the start transition on.

| Zone | Standard | Saving | Start | End |
|---|---|---|---|---|
| `utc` | +00:00 | — | — | — |
| `plus0530` | +05:30 | — | — | — |
| `north` | +01:00 | +02:00 | last Sunday of March, 01:00 UTC | last Sunday of October, 01:00 UTC |
| `west` | −05:00 | −04:00 | 2nd Sunday of March, 07:00 UTC | 1st Sunday of November, 06:00 UTC |
| `south` | +10:30 | +11:00 | 1st Sunday of October, 15:30 UTC | 1st Sunday of April, 15:00 UTC |
| `midnight` | −03:00 | −02:00 | 1st Sunday of November, 03:00 UTC | 3rd Sunday of February, 02:00 UTC |

4. `get_zone(name)` returns the zone; an unknown name raises `CronError` with the message `unknown zone: <repr>` (also from `Schedule`). `ZONES` maps the six names to their zones.
5. `zone.instants(wall)` returns the UTC instants (ascending) whose wall time is `wall` (seconds of `wall` are ignored): none for a wall time a forward transition skips, two for one a backward transition repeats, one otherwise. `zone.transitions(year)` returns `[(instant, offset after), …]` for the transitions of `year`, in time order (`[]` for a fixed zone).

### Expressions
6. An expression is five fields separated by whitespace (surrounding whitespace ignored): minute (0–59), hour (0–23), day of month (1–31), month (1–12 or `JAN`–`DEC`), day of week (0–7 or `SUN`–`SAT`; 0 and 7 are Sunday). Names are case-insensitive and allowed only in their own field; numbers are ASCII decimal digits (leading zeros allowed). A field is a comma-separated list of elements; an element is `*`, a value, a range `a-b` (`a` ≤ `b`), or one of those followed by `/n` (a step, `n` ≥ 1). `*/n` steps from the field's minimum; `a/n` means `a-<max>/n`, where `<max>` is the field's maximum (59, 23, 31, 12, and 7 for day of week, so `MON/2` includes Sunday as 7). `?` is accepted in the two day fields and means the same as `*`.
7. Day specials, each a whole element (no range or step): in day of month `L` (the last day), `L-n` (`n` = 1–30 days before the last day; nothing when that is before the 1st), `nW` (`n` = 1–31: the weekday Monday–Friday nearest to day `n`, never leaving the month — a Saturday 1st gives Monday the 3rd, a Sunday last day gives the Friday two days earlier; nothing in a month without day `n`), `LW` (the last weekday Monday–Friday of the month); in day of week `d#k` (the `k`-th, `k` = 1–5, day `d` of the month; nothing if there is none) and `dL` (the last day `d` of the month). Letters in specials are case-insensitive.
8. Macros (case-insensitive): `@yearly` and `@annually` = `0 0 1 1 *`, `@monthly` = `0 0 1 * *`, `@weekly` = `0 0 * * 0`, `@daily` and `@midnight` = `0 0 * * *`, `@hourly` = `0 * * * *`. Any other text starting with `@` raises `CronError` `unknown macro: <repr of the stripped text>`.
9. A wall time matches when its minute, hour and month are in their fields and its day is selected: a day field whose whole text is `*` or `?` is unrestricted (anything else, `*/1` included, is restricted); if both day fields are restricted, a day is selected when either field selects it; if only one is restricted, that one decides; if neither, every day is selected.
10. Errors are `CronError`, the first problem found, fields left to right, elements left to right: `expected 5 fields, got <n>`; within an element, the step first (`invalid <field> step: <repr>` when `n` is not digits or is 0), then each value left to right (`invalid <field> value: <repr>` when it is not a number or name of the field, `<field> value out of range: <repr>` when it is outside the field's range — also for `L-n`, `nW` and `d#k` outside the stated ranges), then the range (`invalid <field> range: <repr>` when `a` > `b`). `<field>` is `minute`, `hour`, `day-of-month`, `month` or `day-of-week`; `<repr>` is the `repr` of the whole element as written.

### Fire times
11. `next_fire(after)` is the earliest whole minute `u` with `after < u ≤ after + 2922 days` whose wall time matches; `prev_fire(before)` is the latest whole minute `u` with `before − 2922 days ≤ u < before` whose wall time matches. When there is none they raise `CronError` with the message `no fire time within 8 years`. So a wall time skipped by a forward transition does not fire that day, and a wall time repeated by a backward transition fires at both instants.
12. `next_fires(after, count)` is `count` successive `next_fire` results; `fires_between(start, end)` is every fire time `u` with `start ≤ u < end`, ascending (`[]` when there is none); `matches(instant)` tells whether the whole minute at or before `instant` fires.

### Jobs
13. `upcoming(jobs, after, count)` returns the first `count` pairs `(instant, job name)` of all fire times after `after` of all jobs, ordered by instant, equal instants in the order of `jobs`; a job without fire times within the horizon contributes nothing.
14. `catch_up(job, last_run, now, policy)` returns the fire times `u` with `last_run < u ≤ now`, ascending, for policy `all`; only the last of them (or `[]`) for `latest`; `[]` for `skip`; any other policy raises `CronError` `unknown policy: <repr>`.

### Command line
15. `main(["next", EXPR, ZONE, START] + optionally [COUNT])` prints `next_fires(START, COUNT)` (COUNT defaults to 1) and `main(["between", EXPR, ZONE, START, END])` prints `fires_between`, one line per instant: `<UTC>Z <wall><offset>` as in `2026-03-29T01:00Z 2026-03-29T03:00+02:00` (`%Y-%m-%dT%H:%M`, offset `±HH:MM`), returning `0`. START and END are ISO 8601 with an offset (`datetime.fromisoformat`); a START or END without one is a `ValueError` with the message `expected a timezone-aware datetime, got <repr of the argument text>`. A `CronError` or `ValueError` prints `error: <message>` to `stderr` and returns `1`; other arguments print a usage line to `stderr` and return `2`.

Fix the package in place; keep the public names and the existing tests passing. Run the suite with `python3 -m pytest -q tests`.
