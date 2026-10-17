"""Command line.

  cronq validate --jobs FILE --zones FILE [--config FILE]
  cronq agenda   --jobs FILE --zones FILE [--config FILE] --now INSTANT [--count N]
  cronq run      --jobs FILE --zones FILE [--config FILE] --from INSTANT --to INSTANT [--step MINUTES]

Exit status 0 on success.  On any error: exit status 2 and one line
``cronq: <message>`` on standard error (a malformed command line prints the
usage text instead).
"""
import sys

from .agenda import build_agenda, format_agenda
from .clock import SimClock
from .config import Config, parse_config
from .errors import CronqError, UsageError
from .jobs import parse_jobs
from .runner import Runner
from .timeutil import parse_instant
from .zones import parse_zones

USAGE = """usage: cronq validate --jobs FILE --zones FILE [--config FILE]
       cronq agenda --jobs FILE --zones FILE [--config FILE] --now INSTANT [--count N]
       cronq run --jobs FILE --zones FILE [--config FILE] --from INSTANT --to INSTANT [--step MINUTES]"""

COMMANDS = {
    "validate": ({"jobs", "zones"}, {"config"}, 0),
    "agenda": ({"jobs", "zones", "now"}, {"config", "count"}, 0),
    "run": ({"jobs", "zones", "from", "to"}, {"config", "step"}, 0),
}


def parse_args(argv):
    """``(command, options, positionals)``; raises UsageError."""
    if not argv or argv[0] not in COMMANDS:
        raise UsageError("unknown command")
    command = argv[0]
    required, optional, npos = COMMANDS[command]
    options, positionals, args = {}, [], list(argv[1:])
    while args:
        arg = args.pop(0)
        if arg.startswith("--"):
            name = arg[2:]
            if name not in required | optional or name in options or not args:
                raise UsageError(f"bad option {arg!r}")
            options[name] = args.pop(0)
        else:
            positionals.append(arg)
    if not required <= set(options) or len(positionals) != npos:
        raise UsageError("missing arguments")
    return command, options, positionals


def read_file(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except OSError:
        raise CronqError(f"{path}: cannot read") from None


def positive_int(text, what, high):
    if not text.isdigit() or not 1 <= int(text) <= high:
        raise CronqError(f"{what} must be an integer 1..{high}, got {text!r}")
    return int(text)


def load(options):
    config = parse_config(read_file(options["config"])) if "config" in options else Config()
    zones = parse_zones(read_file(options["zones"]))
    jobs = parse_jobs(read_file(options["jobs"]), zones, config)
    return config, zones, jobs


def cmd_validate(options, positionals, out):
    _, _, jobs = load(options)
    for job in jobs:
        print(f"{job.name} {job.zone.name} {job.schedule.describe()}", file=out)
    print(f"ok {len(jobs)} jobs", file=out)


def cmd_agenda(options, positionals, out):
    config, _, jobs = load(options)
    now = parse_instant(options["now"])
    count = positive_int(options["count"], "count", 1000) if "count" in options else config.agenda_count
    for line in format_agenda(build_agenda(jobs, now, count)):
        print(line, file=out)


def cmd_run(options, positionals, out):
    _, _, jobs = load(options)
    start, until = parse_instant(options["from"]), parse_instant(options["to"])
    if until < start:
        raise CronqError("--to is before --from")
    step = positive_int(options["step"], "step", 100000) if "step" in options else 1
    runner = Runner(jobs, start)
    for entry in runner.run(SimClock(start), until, step):
        print(entry.format(), file=out)


HANDLERS = {"validate": cmd_validate, "agenda": cmd_agenda, "run": cmd_run}


def main(argv, stdout=None, stderr=None):
    stdout = stdout or sys.stdout
    stderr = stderr or sys.stderr
    try:
        command, options, positionals = parse_args(list(argv))
    except UsageError:
        print(USAGE, file=stderr)
        return 2
    try:
        HANDLERS[command](options, positionals, stdout)
    except CronqError as exc:
        print(f"cronq: {exc}", file=stderr)
        return 2
    return 0


if __name__ == "__main__":  # pragma: no cover
    sys.exit(main(sys.argv[1:]))
