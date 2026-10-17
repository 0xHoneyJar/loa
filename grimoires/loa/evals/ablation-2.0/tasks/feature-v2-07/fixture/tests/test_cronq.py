import io

import pytest

from cronq import cli
from cronq.agenda import build_agenda, format_agenda, upcoming
from cronq.clock import SimClock
from cronq.config import parse_config
from cronq.errors import ConfigError, CronqError, JobsError, ScheduleError, TimeFormatError, ZoneError
from cronq.jobs import parse_jobs
from cronq.runlog import Entry, parse_log
from cronq.runner import Runner
from cronq.schedule import IntervalSchedule, parse_schedule
from cronq.timeutil import format_local, format_offset, format_utc, parse_instant, parse_offset
from cronq.zones import UTC, parse_zones

ZONES_TEXT = """\
# test zones
zone Lakeland
  initial +01:00
  2026-03-29T01:00Z +02:00
  2026-10-25T01:00Z +01:00
zone Westport
  initial -05:00
"""


def zones():
    return parse_zones(ZONES_TEXT)


def t(text):
    return parse_instant(text)


def test_instants_round_trip():
    assert parse_instant("1970-01-01T00:00Z") == 0
    assert format_utc(t("2026-03-29T01:02:03Z")) == "2026-03-29T01:02:03Z"
    assert t("2026-03-29T01:02Z") == t("2026-03-29T01:02:00Z")


@pytest.mark.parametrize("text", ["2026-03-29 01:02Z", "2026-02-30T00:00Z", "2026-03-29T01:02", "x"])
def test_bad_instants(text):
    with pytest.raises(TimeFormatError) as info:
        parse_instant(text)
    assert str(info.value) == f"bad instant {text!r}"


def test_offsets():
    assert parse_offset("+05:30") == 330 and parse_offset("-04:00") == -240
    assert format_offset(-270) == "-04:30" and format_offset(0) == "+00:00"
    for bad in ("+15:00", "+01:60", "0100", "+1:00"):
        with pytest.raises(TimeFormatError):
            parse_offset(bad)
    assert format_local(t("2026-03-29T01:00Z"), 120) == "2026-03-29T03:00+02:00"


def test_zone_offsets_follow_transitions():
    lake = zones()["Lakeland"]
    assert lake.offset_at(t("2026-03-29T00:59:59Z")) == 60
    assert lake.offset_at(t("2026-03-29T01:00Z")) == 120
    assert lake.offset_at(t("2026-10-25T01:00Z")) == 60
    assert lake.offsets() == [60, 120]
    assert str(lake.wall(t("2026-03-29T01:00Z"))) == "2026-03-29 03:00:00"
    assert zones()["UTC"] is UTC and zones()["Westport"].offset_at(0) == -300


@pytest.mark.parametrize(
    "text, message",
    [
        ("zone\n", "zones:1: expected 'zone NAME'"),
        ("zone UTC\n initial +00:00\n", "zones:1: duplicate zone 'UTC'"),
        ("zone A\n initial +01:00\nzone A\n", "zones:3: duplicate zone 'A'"),
        (" initial +01:00\n", "zones:1: entry outside a zone"),
        ("zone A\n 2026-01-01T00:00Z +01:00\n", "zones:2: zone 'A' has no initial offset"),
        ("zone A\n initial +01:00\n 2026-02-01T00:00Z +02:00\n 2026-01-01T00:00Z +01:00\n", "zones:4: transitions must increase"),
        ("zone A\n initial +1\n", "zones:2: bad offset '+1'"),
        ("zone A\n", "zones:1: zone 'A' has no initial offset"),
    ],
)
def test_zone_file_errors(text, message):
    with pytest.raises(ZoneError) as info:
        parse_zones(text)
    assert str(info.value) == message


def test_interval_schedule():
    every = parse_schedule("every 15m")
    assert isinstance(every, IntervalSchedule) and every.minutes == 15
    assert format_utc(every.next_after(t("2026-05-04T10:07:30Z"), UTC)) == "2026-05-04T10:15:00Z"
    assert format_utc(every.next_after(t("2026-05-04T10:15:00Z"), UTC)) == "2026-05-04T10:30:00Z"
    assert parse_schedule("every 2h").minutes == 120 and parse_schedule(" every  1d ").describe() == "every 1d"


@pytest.mark.parametrize(
    "text, message",
    [
        ("", "empty schedule"),
        ("every", "expected 'every <n><m|h|d>', got 'every'"),
        ("every 0m", "bad interval '0m'"),
        ("every 5s", "bad interval '5s'"),
        ("hourly", "unknown schedule kind 'hourly'"),
    ],
)
def test_schedule_errors(text, message):
    with pytest.raises(ScheduleError) as info:
        parse_schedule(text)
    assert str(info.value) == message


def test_config():
    config = parse_config("# c\ndefault_zone = Westport\nhorizon_days = 30\nagenda_count=3\n")
    assert (config.default_zone, config.horizon_days, config.agenda_count) == ("Westport", 30, 3)
    for text, message in [
        ("colour = red\n", "config:1: unknown key 'colour'"),
        ("horizon_days = 0\n", "config:1: horizon_days must be an integer 1..36600, got '0'"),
        ("agenda_count = 3\nagenda_count = 4\n", "config:2: duplicate key 'agenda_count'"),
        ("nonsense\n", "config:1: expected 'key = value'"),
    ]:
        with pytest.raises(ConfigError) as info:
            parse_config(text)
        assert str(info.value) == message


def test_jobs_file():
    jobs = parse_jobs("# jobs\nping | - | every 15m | ping host\n\nsync | Lakeland | every 1h | sync\n", zones())
    assert [(job.name, job.zone.name, job.schedule.describe(), job.command, job.line) for job in jobs] == [
        ("ping", "UTC", "every 15m", "ping host", 2),
        ("sync", "Lakeland", "every 1h", "sync", 4),
    ]
    jobs = parse_jobs("ping | - | every 15m | p\n", zones(), parse_config("default_zone = Westport\n"))
    assert jobs[0].zone.name == "Westport"


@pytest.mark.parametrize(
    "text, message",
    [
        ("a | - | every 5m\n", "jobs:1: expected 4 fields separated by '|', got 3"),
        ("A | - | every 5m | x\n", "jobs:1: bad job name 'A'"),
        ("a | - | every 5m | x\na | - | every 5m | y\n", "jobs:2: duplicate job 'a'"),
        ("a | Mars | every 5m | x\n", "jobs:1: unknown zone 'Mars'"),
        ("a | - | every 5x | x\n", "jobs:1: bad schedule: bad interval '5x'"),
        ("a | - | every 5m |\n", "jobs:1: empty command"),
    ],
)
def test_jobs_errors(text, message):
    with pytest.raises(JobsError) as info:
        parse_jobs(text, zones())
    assert str(info.value) == message


def test_clock():
    clock = SimClock(0)
    assert clock.advance(5) == 300 and clock.set(600) == 600
    with pytest.raises(CronqError):
        clock.set(0)
    assert list(SimClock(0).ticks(150, 1)) == [60, 120, 150]


def test_runlog_round_trip():
    text = "2026-03-29T03:00:00Z backup fires=2\n2026-03-29T03:15:00Z ping fires=1\n"
    log = parse_log(text)
    assert log.entries[0] == Entry(t("2026-03-29T03:00Z"), "backup", 2)
    assert log.to_text() == text and len(log.for_job("ping")) == 1
    with pytest.raises(CronqError):
        parse_log("2026-03-29T03:00:00Z backup fires=0\n")


def test_runner_coalesces_missed_fires_and_orders_entries():
    jobs = parse_jobs("slow | - | every 1h | s\nfast | - | every 15m | f\n", zones())
    start = t("2026-05-04T00:00Z")
    runner = Runner(jobs, start)
    entries = runner.tick(t("2026-05-04T01:00Z"))
    assert [entry.format() for entry in entries] == [
        "2026-05-04T01:00:00Z slow fires=1",
        "2026-05-04T01:00:00Z fast fires=4",
    ]
    assert runner.tick(t("2026-05-04T01:10Z")) == []
    assert [entry.format() for entry in runner.tick(t("2026-05-04T01:40Z"))] == ["2026-05-04T01:30:00Z fast fires=2"]
    with pytest.raises(CronqError):
        runner.tick(start)


def test_runner_run_steps_the_clock():
    jobs = parse_jobs("fast | - | every 15m | f\n", zones())
    start = t("2026-05-04T00:00Z")
    entries = Runner(jobs, start).run(SimClock(start), t("2026-05-04T01:00Z"), 20)
    assert [entry.format() for entry in entries] == [
        "2026-05-04T00:15:00Z fast fires=1",
        "2026-05-04T00:30:00Z fast fires=1",
        "2026-05-04T01:00:00Z fast fires=2",
    ]


def test_agenda_merges_and_formats_in_job_zones():
    jobs = parse_jobs("sync | Lakeland | every 1h | s\nping | Westport | every 30m | p\n", zones())
    rows = build_agenda(jobs, t("2026-03-29T00:10Z"), 4)
    assert format_agenda(rows) == [
        "2026-03-28T19:30-05:00 ping",
        "2026-03-29T03:00+02:00 sync",
        "2026-03-28T20:00-05:00 ping",
        "2026-03-28T20:30-05:00 ping",
    ]
    assert len(upcoming(jobs[0], 0, 3)) == 3
    assert format_agenda([]) == ["no upcoming runs"]


def run(argv, tmp_path, jobs_text):
    (tmp_path / "zones.txt").write_text(ZONES_TEXT)
    (tmp_path / "jobs.txt").write_text(jobs_text)
    argv = [str(tmp_path / "zones.txt") if a == "Z" else str(tmp_path / "jobs.txt") if a == "J" else a for a in argv]
    out, err = io.StringIO(), io.StringIO()
    return cli.main(argv, stdout=out, stderr=err), out.getvalue(), err.getvalue()


def test_cli_validate_agenda_run(tmp_path):
    jobs = "ping | - | every 30m | p\nsync | Lakeland | every 1h | s\n"
    status, out, err = run(["validate", "--jobs", "J", "--zones", "Z"], tmp_path, jobs)
    assert (status, out, err) == (0, "ping UTC every 30m\nsync Lakeland every 1h\nok 2 jobs\n", "")
    status, out, err = run(["agenda", "--jobs", "J", "--zones", "Z", "--now", "2026-05-04T00:00Z", "--count", "3"], tmp_path, jobs)
    assert (status, out) == (0, "2026-05-04T00:30+00:00 ping\n2026-05-04T01:00+00:00 ping\n2026-05-04T03:00+02:00 sync\n")
    status, out, err = run(["run", "--jobs", "J", "--zones", "Z", "--from", "2026-05-04T00:00Z", "--to", "2026-05-04T01:00Z", "--step", "60"], tmp_path, jobs)
    assert (status, out) == (0, "2026-05-04T01:00:00Z ping fires=2\n2026-05-04T01:00:00Z sync fires=1\n")


def test_cli_errors(tmp_path):
    status, out, err = run(["agenda", "--jobs", "J", "--zones", "Z", "--now", "soon"], tmp_path, "")
    assert (status, out, err) == (2, "", "cronq: bad instant 'soon'\n")
    status, out, err = run(["validate", "--jobs", "J", "--zones", "Z"], tmp_path, "a | - | every | x\n")
    assert (status, err) == (2, "cronq: jobs:1: bad schedule: expected 'every <n><m|h|d>', got 'every'\n")
    status, out, err = run(["validate", "--jobs", "J"], tmp_path, "")
    assert status == 2 and err.startswith("usage: cronq validate")
    status, out, err = run(["agenda", "--jobs", "J", "--zones", "Z", "--now", "2026-05-04T00:00Z", "--count", "0"], tmp_path, "")
    assert (status, err) == (2, "cronq: count must be an integer 1..1000, got '0'\n")
    status, out, err = run(["validate", "--jobs", "/nonexistent/jobs", "--zones", "Z"], tmp_path, "")
    assert (status, err) == (2, "cronq: /nonexistent/jobs: cannot read\n")
