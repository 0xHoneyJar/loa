# Task: a time window for logq

`logq` (the package under `src/logq/`) filters log lines of the form `<timestamp> <LEVEL> <message>`; the timestamp is ISO-8601 and a timestamp without an offset is UTC. Its entry point is `logq.cli.main(argv, stdin=None, stdout=None, stderr=None)`, which returns the exit status. Add two options that keep only the records inside a time window.

## Options

- `--since T` keeps records whose timestamp is at or after `T` (inclusive).
- `--until T` keeps records whose timestamp is at or before `T` (inclusive).

Either may be given alone; both together keep the records inside the window. They combine with `--level`, `--grep` and the file argument as an AND: a record is printed only when every given filter keeps it. Output lines stay unchanged and in input order; malformed lines are still dropped.

## Accepted values of T

Exactly these three forms, nothing else:

1. `YYYY-MM-DD` — a date alone;
2. `YYYY-MM-DDTHH:MM` — seconds omitted, meaning `:00`;
3. `YYYY-MM-DDTHH:MM:SS`.

Forms 2 and 3 may end in `Z` or a `+HH:MM` / `-HH:MM` offset; without one the time is UTC. A date alone never carries an offset. Fractional seconds, a bare hour (`2026-10-15T10`), other separators (`15/10/2026`), words and the empty string are not accepted, and neither is a value that matches a form but is not a real date or time (month 13, hour 25).

Comparison is by instant, so offsets are honoured: `2026-10-15T12:00:00+02:00` is the same bound as `2026-10-15T10:00:00Z`.

A date alone means the whole UTC day: `--since 2026-10-15` starts at `2026-10-15T00:00:00Z`; `--until 2026-10-15` keeps every record before `2026-10-16T00:00:00Z`, including `2026-10-15T23:59:59.900Z`. A time bound is an exact instant: `--until 2026-10-15T10:00` keeps a record at `10:00:00Z` and drops one at `10:00:30Z`.

## Errors

Errors are usage errors: exit status 2, nothing on standard output, and exactly one line on standard error.

- A value that is not accepted: `logq: invalid --since value: <value>` (or `--until`), where `<value>` is the value as given.
- A window that no instant can satisfy (the `--since` bound is later than the last instant the `--until` bound keeps): `logq: --since is after --until`. Equal instants are a valid window; `--since 2026-10-15 --until 2026-10-15` is the whole day.

Update the usage text in the module docstring. Run the suite with `python3 -m pytest -q tests`, and add tests of your own for the new options.
