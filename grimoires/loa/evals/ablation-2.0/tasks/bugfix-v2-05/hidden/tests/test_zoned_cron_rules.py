"""Acceptance cases for cronzone: scenario tables and generated full-surface conformance."""
import io
import random
from datetime import datetime, timedelta, timezone

import pytest

from cronzone import CronError, CronExpr, Job, Schedule, ZONES, catch_up, get_zone, upcoming
from cronzone.cli import main

import _oracle_cron as oracle

UTC = timezone.utc


def at(*args):
    return datetime(*args, tzinfo=UTC)


def walls(schedule, instants):
    return [schedule.zone.wall(t) for t in instants]


def outcome(fn, *args):
    try:
        return ("ok", fn(*args))
    except CronError as exc:
        return ("err", "CronError", str(exc))


# -- scenario tables ------------------------------------------------------------
def test_backward_transition_repeats_wall_times():
    s = Schedule("30 * * * *", "north")
    got = s.fires_between(at(2026, 10, 24, 23, 0), at(2026, 10, 25, 3, 0))
    assert got == [at(2026, 10, 24, 23, 30), at(2026, 10, 25, 0, 30), at(2026, 10, 25, 1, 30), at(2026, 10, 25, 2, 30)]
    assert [w.hour for w in walls(s, got)] == [1, 2, 2, 3]
    assert s.next_fire(at(2026, 10, 25, 0, 30)) == at(2026, 10, 25, 1, 30)
    assert s.prev_fire(at(2026, 10, 25, 1, 30)) == at(2026, 10, 25, 0, 30)
    w = Schedule("*/20 1 * * *", "west")
    assert w.next_fires(at(2026, 11, 1, 5, 50), 4) == [at(2026, 11, 1, 6, 0), at(2026, 11, 1, 6, 20),
                                                     at(2026, 11, 1, 6, 40), at(2026, 11, 2, 6, 0)]
    assert w.prev_fire(at(2026, 11, 1, 6, 0)) == at(2026, 11, 1, 5, 40)
    south = Schedule("45 1 * * *", "south")
    assert south.fires_between(at(2027, 4, 4, 14, 0), at(2027, 4, 4, 16, 0)) == [at(2027, 4, 4, 14, 45),
                                                                               at(2027, 4, 4, 15, 15)]
    assert Schedule("15 2 * * *", "south").fires_between(at(2027, 4, 4, 14, 0), at(2027, 4, 4, 16, 0)) == [
        at(2027, 4, 4, 15, 45)]
    mid = Schedule("45 23 * * *", "midnight")
    assert mid.fires_between(at(2027, 2, 21, 0, 0), at(2027, 2, 22, 0, 0)) == [at(2027, 2, 21, 1, 45),
                                                                             at(2027, 2, 21, 2, 45)]


def test_forward_transition_skips_wall_times():
    north = Schedule("30 2 * * *", "north")
    assert north.fires_between(at(2026, 3, 28, 0, 0), at(2026, 3, 31, 0, 0)) == [at(2026, 3, 28, 1, 30), at(2026, 3, 30, 0, 30)]
    south = Schedule("10 2 * * *", "south")
    assert south.next_fire(at(2026, 10, 3, 16, 0)) == at(2026, 10, 5, 15, 10)
    mid = Schedule("@daily", "midnight")
    assert mid.next_fires(at(2026, 10, 31, 4, 0), 2) == [at(2026, 11, 2, 2, 0), at(2026, 11, 3, 2, 0)]
    assert mid.prev_fire(at(2026, 11, 2, 2, 0)) == at(2026, 10, 31, 3, 0)
    assert get_zone("north").instants(datetime(2026, 3, 29, 2, 59)) == []


def test_inputs_between_whole_minutes():
    s = Schedule("* * * * *")
    assert s.prev_fire(at(2026, 5, 1, 10, 0, 30)) == at(2026, 5, 1, 10, 0)
    assert s.prev_fire(at(2026, 5, 1, 10, 0)) == at(2026, 5, 1, 9, 59)
    assert s.next_fire(at(2026, 5, 1, 10, 0, 30)) == at(2026, 5, 1, 10, 1)
    assert s.fires_between(at(2026, 5, 1, 10, 0), at(2026, 5, 1, 10, 2)) == [at(2026, 5, 1, 10, 0), at(2026, 5, 1, 10, 1)]
    assert s.fires_between(at(2026, 5, 1, 10, 0, 0, 1), at(2026, 5, 1, 10, 2, 0, 1)) == [at(2026, 5, 1, 10, 1),
                                                                                       at(2026, 5, 1, 10, 2)]
    plus5 = timezone(timedelta(hours=5))
    h = Schedule("0 * * * *", "plus0530")
    result = h.prev_fire(datetime(2026, 5, 1, 15, 30, 10, tzinfo=plus5))
    assert result == at(2026, 5, 1, 10, 30) and result.tzinfo is UTC and result.second == 0
    assert Schedule("0 3 * * *").matches(at(2026, 5, 1, 3, 0, 59))
    for call in (lambda: s.next_fire(datetime(2026, 1, 1)), lambda: s.prev_fire("2026-01-01"),
                 lambda: s.fires_between(at(2026, 1, 1), datetime(2026, 1, 2)), lambda: s.matches(None),
                 lambda: catch_up(Job("j", s), at(2026, 1, 1), datetime(2026, 1, 2), "skip"),
                 lambda: get_zone("north").offset(datetime(2026, 1, 1))):
        with pytest.raises(ValueError) as info:
            call()
        assert str(info.value).startswith("expected a timezone-aware datetime, got ")


def test_day_fields_either_rule():
    cases = [("0 0 13 * FRI", [6, 13, 20, 27]), ("0 0 13 * ?", [13]), ("0 0 ? * FRI", [6, 13, 20, 27]),
             ("0 0 */1 * FRI", list(range(1, 29))), ("0 0 1-3 * */7", [1, 2, 3, 8, 15, 22]),
             ("0 0 L * MON#1", [2, 28]), ("0 0 ? * ?", list(range(1, 29)))]
    for text, days in cases:
        s = Schedule(text)
        got = [t.day for t in s.fires_between(at(2026, 2, 1), at(2026, 3, 1))]
        assert got == days, text


def test_steps_and_ranges():
    assert [t.day for t in Schedule("0 0 */10 * *").fires_between(at(2026, 1, 1), at(2026, 2, 1))] == [1, 11, 21, 31]
    assert [t.month for t in Schedule("0 0 1 */4 *").fires_between(at(2026, 1, 1), at(2027, 1, 1))] == [1, 5, 9]
    assert [t.weekday() for t in Schedule("0 0 * * MON/2").fires_between(at(2026, 3, 2), at(2026, 3, 9))] == [0, 2, 4, 6]
    assert [t.minute for t in Schedule("10/25 0 1 1 *").fires_between(at(2026, 1, 1), at(2026, 1, 2))] == [10, 35]
    assert [t.day for t in Schedule("0 0 * * 5-7").fires_between(at(2026, 3, 1), at(2026, 3, 8))] == [1, 6, 7]
    assert [t.day for t in Schedule("0 0 * jan/5 SAT").fires_between(at(2026, 6, 1), at(2026, 7, 1))] == [6, 13, 20, 27]


def test_nearest_weekday_edges():
    def days(text, year, month):
        s = Schedule(text)
        end = at(year + (month == 12), month % 12 + 1, 1)
        return [t.day for t in s.fires_between(at(year, month, 1), end)]
    assert days("0 9 1W * *", 2026, 8) == [3]
    assert days("0 9 31W * *", 2026, 5) == [29]
    assert days("0 9 15W * *", 2026, 8) == [14]
    assert days("0 9 30W * *", 2026, 2) == []
    assert days("0 9 31W * *", 2026, 4) == []
    assert days("0 9 lw * *", 2026, 5) == [29]
    assert days("0 9 1W,15 * *", 2028, 1) == [3, 15]


def test_last_day_specials_across_years():
    s = Schedule("0 12 L * *")
    order = [(2026, 2, 28), (2032, 2, 29), (2028, 2, 29), (2033, 2, 28), (2026, 2, 28)]
    for year, month, day in order:
        assert s.next_fire(at(year, month, 20)) == at(year, month, day, 12), year
    t = Schedule("0 12 L-1 2 *")
    for year, day in [(2032, 28), (2026, 27), (2028, 28), (2033, 27)]:
        assert t.next_fire(at(year, 2, 1)) == at(year, 2, day, 12), year
    u = Schedule("0 12 * 2 SUNL")
    for year, day in [(2026, 22), (2032, 29), (2037, 22)]:
        assert u.next_fire(at(year, 2, 1)) == at(year, 2, day, 12), year


def test_nth_weekday():
    s = Schedule("0 8 * * 1#5")
    assert s.next_fires(at(2026, 4, 1), 3) == [at(2026, 6, 29, 8, 0), at(2026, 8, 31, 8, 0), at(2026, 11, 30, 8, 0)]
    assert Schedule("0 8 * * sun#1,6L").fires_between(at(2026, 2, 1), at(2026, 3, 1)) == [at(2026, 2, 1, 8, 0),
                                                                                        at(2026, 2, 28, 8, 0)]


def test_month_skips_reset_the_time_of_day():
    assert Schedule("0 9 * 6 *").next_fire(at(2026, 5, 20, 10, 0)) == at(2026, 6, 1, 9, 0)
    assert Schedule("30 22 * 1 *").prev_fire(at(2026, 2, 10, 5, 0)) == at(2026, 1, 31, 22, 30)
    assert Schedule("15 6 1 */6 *", "north").next_fire(at(2026, 2, 3, 12, 0)) == at(2026, 7, 1, 4, 15)


def test_southern_and_wrapping_zones():
    south, mid = get_zone("south"), get_zone("midnight")
    assert [south.offset(at(2026, m, 15)) for m in (1, 4, 7, 10, 12)] == [660, 630, 630, 660, 660]
    assert [mid.offset(at(2026, m, 20)) for m in (1, 2, 7, 11, 12)] == [-120, -180, -180, -120, -120]
    assert [mid.offset(at(2026, 2, 15, h)) for h in (1, 2)] == [-120, -180]
    assert south.transitions(2027) == [(at(2027, 4, 4, 15, 0), 630), (at(2027, 10, 3, 15, 30), 660)]
    assert mid.wall(at(2026, 11, 1, 3, 0)) == datetime(2026, 11, 1, 1, 0)
    assert south.wall(at(2026, 1, 1, 0, 59, 59)) == datetime(2026, 1, 1, 11, 59)
    assert Schedule("0 12 * * *", "south").next_fire(at(2026, 1, 1)) == at(2026, 1, 1, 1, 0)


def test_zone_instants():
    cases = [("north", datetime(2026, 10, 25, 2, 30, 45), [at(2026, 10, 25, 0, 30), at(2026, 10, 25, 1, 30)]),
             ("west", datetime(2026, 11, 1, 1, 0), [at(2026, 11, 1, 5, 0), at(2026, 11, 1, 6, 0)]),
             ("south", datetime(2027, 4, 5, 1, 45), [at(2027, 4, 4, 14, 45), at(2027, 4, 4, 15, 15)]),
             ("midnight", datetime(2027, 2, 20, 23, 0), [at(2027, 2, 21, 1, 0), at(2027, 2, 21, 2, 0)]),
             ("south", datetime(2026, 10, 5, 2, 0), []), ("midnight", datetime(2026, 11, 1, 0, 30), []),
             ("plus0530", datetime(2026, 1, 1, 5, 30), [at(2026, 1, 1, 0, 0)])]
    for name, wall, expected in cases:
        assert get_zone(name).instants(wall) == expected, (name, wall)


def test_expression_errors():
    cases = [("* * * * * *", "expected 5 fields, got 6"), ("? * * * *", "invalid minute value: '?'"),
             ("70/0 * * * *", "invalid minute step: '70/0'"), ("1-70/x * * * *", "invalid minute step: '1-70/x'"),
             ("* 30-40 * * *", "hour value out of range: '30-40'"), ("* 5-x * * *", "invalid hour value: '5-x'"),
             ("* * L-31 * *", "day-of-month value out of range: 'L-31'"), ("* * 0W * *", "day-of-month value out of range: '0W'"),
             ("* * 1,,2 * *", "invalid day-of-month value: ''"), ("* * * 0 *", "month value out of range: '0'"),
             ("* * * MON *", "invalid month value: 'MON'"), ("* * * * 1#6", "day-of-week value out of range: '1#6'"),
             ("* * * * 8L", "day-of-week value out of range: '8L'"), ("* * * * L", "invalid day-of-week value: 'L'"),
             ("* * L/2 * *", "invalid day-of-month value: 'L/2'"), ("@Weekly", None), ("  @HOURLY ", None),
             ("@every 5m", "unknown macro: '@every 5m'"), ("*/5 1-2 13 jan-Mar sun-sat", None),
             ("61 25 * * *", "minute value out of range: '61'")]
    for text, message in cases:
        if message is None:
            CronExpr(text)
            continue
        with pytest.raises(CronError) as info:
            CronExpr(text)
        assert str(info.value) == message, text
    assert Schedule("@WEEKLY").next_fire(at(2026, 3, 4)) == at(2026, 3, 8)


def test_upcoming_and_catch_up():
    jobs = [Job.create("zeta", "0 * * * *"), Job.create("alpha", "0 */2 * * *"), Job.create("never", "0 0 31 2 *"),
            Job.create("late", "30 1 * * *", "north")]
    assert upcoming(jobs, at(2026, 6, 1, 0, 0), 5) == [(at(2026, 6, 1, 1, 0), "zeta"), (at(2026, 6, 1, 2, 0), "zeta"),
                                                     (at(2026, 6, 1, 2, 0), "alpha"), (at(2026, 6, 1, 3, 0), "zeta"),
                                                     (at(2026, 6, 1, 4, 0), "zeta")]
    assert upcoming([jobs[2]], at(2026, 6, 1), 3) == []
    job = Job.create("j", "0 * * * *")
    assert catch_up(job, at(2026, 6, 1, 9, 0), at(2026, 6, 1, 11, 0)) == [at(2026, 6, 1, 10, 0), at(2026, 6, 1, 11, 0)]
    assert catch_up(job, at(2026, 6, 1, 9, 0), at(2026, 6, 1, 11, 0), "latest") == [at(2026, 6, 1, 11, 0)]
    assert catch_up(job, at(2026, 6, 1, 9, 0), at(2026, 6, 1, 9, 59), "latest") == []
    with pytest.raises(CronError) as info:
        catch_up(job, at(2026, 6, 1), at(2026, 6, 2), "most")
    assert str(info.value) == "unknown policy: 'most'"


def test_command_line():
    out, err = io.StringIO(), io.StringIO()
    assert main(["next", "0 2 * * *", "south", "2026-10-03T00:00Z", "3"], out, err) == 0
    assert out.getvalue() == ("2026-10-03T15:30Z 2026-10-04T02:00+10:30\n2026-10-05T15:00Z 2026-10-06T02:00+11:00\n"
                              "2026-10-06T15:00Z 2026-10-07T02:00+11:00\n")
    out, err = io.StringIO(), io.StringIO()
    assert main(["between", "0 1 * * *", "west", "2026-11-01T00:00-04:00", "2026-11-02T00:00-05:00"], out, err) == 0
    assert out.getvalue() == "2026-11-01T05:00Z 2026-11-01T01:00-04:00\n2026-11-01T06:00Z 2026-11-01T01:00-05:00\n"
    for argv, message in [(["next", "* * * * *", "x", "2026-01-01T00:00Z"], "error: unknown zone: 'x'\n"),
                          (["next", "* * * * *", "utc", "2026-01-01T00:00"],
                           "error: expected a timezone-aware datetime, got '2026-01-01T00:00'\n"),
                          (["between", "0 0 30 2 *", "utc", "2026-01-01T00:00Z", "2026-12-01T00:00Z"], None)]:
        out, err = io.StringIO(), io.StringIO()
        code = main(argv, out, err)
        if message is None:
            assert code == 0 and out.getvalue() == "" and err.getvalue() == ""
        else:
            assert code == 1 and err.getvalue() == message and out.getvalue() == ""
    assert main(["next", "* * * * *"], io.StringIO(), io.StringIO()) == 2


def test_horizon():
    leap = Schedule("0 0 29 2 *")
    assert leap.next_fire(at(2025, 3, 1)) == at(2028, 2, 29)
    assert leap.prev_fire(at(2028, 2, 28)) == at(2024, 2, 29)
    for text in ("0 0 31 4 *", "0 0 L-30 2 *", "0 0 30W 2 *"):
        for call in (Schedule(text).next_fire, Schedule(text).prev_fire):
            with pytest.raises(CronError) as info:
                call(at(2026, 1, 1))
            assert str(info.value) == "no fire time within 8 years"


# -- generated full-surface conformance ------------------------------------------
POOLS = {
    "minute": ["0", "15", "30", "45", "59", "*", "*/7", "10-20", "0,30", "5/20", "*/30", "1-59/29", "*", "*/13"],
    "hour": ["0", "1", "2", "3", "23", "*", "*/2", "1-3", "0-23/5", "2,14", "22-23", "*", "*", "0-3", "1,2"],
    "dom": ["*", "?", "1", "15", "29", "30", "31", "L", "L-1", "L-3", "1W", "15W", "31W", "LW", "*/2",
            "1-7", "10-20/3", "L,15", "1W,L"],
    "month": ["*", "*", "*", "*/3", "FEB", "mar-apr", "10-12", "2,3,10,11", "JAN/5", "*/2", "nov"],
    "dow": ["*", "?", "*", "0", "7", "MON-FRI", "5-7", "SUN#2", "1#5", "FRIL", "*/2", "sat", "MON/2", "0#1,6L",
            "?", "*"],
}
MACRO_TEXTS = ["@daily", "@HOURLY", "@Weekly", "@monthly", "@midnight", "@yearly", "@annually"]
BAD = ["60 * * * *", "* 24 * * *", "* * 0 * *", "* * 32 * *", "* * * 13 *", "* * * * 8", "*/0 * * * *",
       "5-1 * * * *", "* * L-0 * *", "* * 32W * *", "* * * * 0#0", "* * * * x#1", "* * * jan-feb/0 *",
       "* * * * *  *", "@reboot", "* ? * * *", "* * ?/x * *", "1,2,,3 * * * *", "* * LW-1 * *", "* * * * 1-8"]


def gen_expr(rng):
    if rng.random() < 0.05:
        return rng.choice(MACRO_TEXTS)
    return " ".join(rng.choice(POOLS[k]) for k in ("minute", "hour", "dom", "month", "dow"))


def gen_instant(rng, zone):
    year = rng.randint(2025, 2033)
    trans = get_zone(zone).transitions(year) if zone in ZONES else []
    r = rng.random()
    if trans and r < 0.45:
        base = rng.choice(trans)[0]
        delta = rng.randint(-90, 90)
    elif trans and r < 0.6:
        base = rng.choice(trans)[0]
        delta = rng.randint(-200, 200)
    elif trans and r < 0.8:
        base = rng.choice(trans)[0]
        delta = int(rng.triangular(-1500, 1500, 0))
    else:
        base = at(year, rng.randint(1, 12), rng.randint(1, 28))
        delta = rng.randint(0, 1439)
    t = base + timedelta(minutes=delta)
    if rng.random() < 0.3:
        t += timedelta(seconds=rng.randint(0, 59), microseconds=rng.choice([0, 1, 999999]))
    if rng.random() < 0.15:
        t = t.astimezone(timezone(timedelta(minutes=rng.choice([-300, 90, 330]))))
    return t


def _check_sample(rng, zone_weights):
    zone = rng.choices(sorted(ZONES), zone_weights)[0]
    kind = rng.choices(["next", "prev", "between", "next_fires", "matches", "zone", "parse", "upcoming",
                        "catch_up", "cli", "transition"], [6, 6, 6, 3, 2, 2, 2, 1, 2, 1, 4])[0]
    text = gen_expr(rng)
    t = gen_instant(rng, zone)
    if kind == "transition":
        zone = rng.choice(["north", "west", "south", "midnight"])
        when, _ = rng.choice(get_zone(zone).transitions(rng.randint(2025, 2033)))
        t = when + timedelta(minutes=rng.randint(-75, 75), seconds=rng.choice([0, 0, 30]))
        text = " ".join([rng.choice(["*", "*/7", "*/20", "0,30", "59", "1-59/29", "15-45/15"]),
                         rng.choice(["*", "*", "0-3", "22-23,0-2", "*/2"]), rng.choice(["*", "?", "*/2", "L,1-28"]),
                         "*", rng.choice(["*", "?", "0-6", "SUN,MON,SAT"])])
        kind = rng.choice(["next", "prev", "between", "next_fires"])
    if kind == "next":
        assert outcome(Schedule(text, zone).next_fire, t) == oracle.next_fire(text, zone, t), (text, zone, t)
    elif kind == "prev":
        assert outcome(Schedule(text, zone).prev_fire, t) == oracle.prev_fire(text, zone, t), (text, zone, t)
    elif kind == "between":
        end = t + timedelta(minutes=rng.choice([rng.randint(0, 240), rng.randint(0, 2 * 1440)]))
        assert outcome(Schedule(text, zone).fires_between, t, end) == oracle.fires_between(text, zone, t, end), (text, zone, t, end)
    elif kind == "next_fires":
        n = rng.randint(1, 4)
        assert outcome(Schedule(text, zone).next_fires, t, n) == oracle.next_fires(text, zone, t, n), (text, zone, t)
    elif kind == "matches":
        f = oracle.parse(text)
        u = oracle.minutes_of(t)[0]
        assert Schedule(text, zone).matches(t) == oracle.fires_at(f, zone, u), (text, zone, t)
    elif kind == "zone":
        z = get_zone(zone)
        u = oracle.minutes_of(t)[0]
        assert z.offset(t) == oracle.offset(zone, u)
        assert z.wall(t) == oracle.wall_of(zone, u)
        wall = oracle.wall_of(zone, u) + timedelta(minutes=rng.randint(-90, 90), seconds=rng.randint(0, 59))
        assert z.instants(wall) == [oracle.instant(x) for x in oracle.instants_of(zone, wall)], (zone, wall)
        year = rng.randint(2025, 2033)
        want = []
        if ZONES[zone].dst is not None:
            rules = oracle._year_rules(zone, year)
            std, dst = oracle.ZONES[zone]
            want = sorted([(oracle.instant(rules[0]), dst[0]), (oracle.instant(rules[1]), std)])
        assert z.transitions(year) == want
    elif kind == "parse":
        text = rng.choice(BAD) if rng.random() < 0.6 else text
        try:
            oracle.parse(text)
            want = None
        except oracle.Err as e:
            want = str(e)
        if want is None:
            CronExpr(text)
        else:
            with pytest.raises(CronError) as info:
                CronExpr(text)
            assert str(info.value) == want, text
    elif kind == "upcoming":
        specs = [(f"job{rng.randint(0, 3)}", gen_expr(rng), rng.choice(sorted(ZONES))) for _ in range(rng.randint(1, 4))]
        jobs = [Job.create(*s) for s in specs]
        n = rng.randint(1, 6)
        assert upcoming(jobs, t, n) == oracle.upcoming(specs, t, n), (specs, t)
    elif kind == "catch_up":
        policy = rng.choice(["all", "all", "latest", "skip"])
        now = t + timedelta(minutes=rng.randint(0, 1440), seconds=rng.randint(0, 59))
        if rng.random() < 0.3:
            r = oracle.next_fire(text, zone, t)
            if r[0] == "ok":
                t = r[1]
        assert catch_up(Job.create("j", text, zone), t, now, policy) == oracle.catch_up(text, zone, t, now, policy)[1]
    else:
        n = rng.randint(1, 3)
        start = t.isoformat()
        out, err = io.StringIO(), io.StringIO()
        code = main(["next", text, zone, start, str(n)], out, err)
        want = oracle.next_fires(text, zone, datetime.fromisoformat(start), n)
        if want[0] == "ok":
            lines = []
            for inst in want[1]:
                u = oracle.minutes_of(inst)[0]
                off = oracle.offset(zone, u)
                sign = "+" if off >= 0 else "-"
                lines.append(f"{inst:%Y-%m-%dT%H:%M}Z {oracle.wall_of(zone, u):%Y-%m-%dT%H:%M}"
                             f"{sign}{abs(off) // 60:02d}:{abs(off) % 60:02d}\n")
            assert (code, out.getvalue(), err.getvalue()) == (0, "".join(lines), ""), (text, zone, start)
        else:
            assert (code, out.getvalue(), err.getvalue()) == (1, "", f"error: {want[2]}\n")


CONFORMANCE = [
    (7101, [1, 1, 1, 1, 1, 1]), (7102, [3, 1, 1, 1, 1, 1]), (7103, [1, 3, 1, 1, 1, 1]),
    (7104, [1, 1, 3, 1, 1, 1]), (7105, [1, 1, 1, 3, 1, 1]), (7106, [1, 1, 1, 1, 3, 1]),
    (7107, [1, 1, 1, 1, 1, 3]), (7108, [2, 2, 1, 2, 1, 1]), (7109, [1, 2, 2, 1, 2, 1]),
    (7110, [2, 1, 2, 2, 1, 1]), (7111, [1, 1, 1, 2, 2, 2]), (7112, [2, 2, 2, 1, 1, 1]),
    (7113, [1, 2, 1, 2, 1, 2]), (7114, [2, 1, 2, 1, 2, 1]), (7115, [1, 1, 2, 2, 2, 1]),
]


@pytest.mark.parametrize("seed, zone_weights", CONFORMANCE)
def test_generated_full_surface(seed, zone_weights):
    rng = random.Random(seed)
    for _ in range(400):
        _check_sample(rng, zone_weights)
