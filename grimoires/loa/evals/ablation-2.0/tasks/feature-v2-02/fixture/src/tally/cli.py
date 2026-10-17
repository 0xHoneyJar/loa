"""tally - print CSV records as a table.

Usage:
  tally [--where FIELD=VALUE]... [--sort [-]COLUMN] [--format plain|markdown] [FILE]

Options:
  --where FIELD=VALUE   keep rows whose FIELD equals VALUE exactly (repeatable; all must hold)
  --sort [-]COLUMN      sort by COLUMN, ascending, or descending with a leading -
  --format FORMAT       plain (the default) or markdown

Reads FILE, or standard input when no FILE is given. The table is followed by a
footer line counting the rows. Errors exit with status 2.
"""

import sys

from .errors import UsageError
from .format import footer, render
from .query import apply_where, parse_where
from .reader import read_table
from .sorting import sort_rows

VALUE_OPTIONS = ("--sort", "--format")
LIST_OPTIONS = ("--where",)


def parse_args(argv):
    opts = {"where": [], "sort": None, "format": "plain", "file": None}
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg in VALUE_OPTIONS or arg in LIST_OPTIONS:
            if i + 1 >= len(argv):
                raise UsageError(f"{arg} needs a value")
            if arg in LIST_OPTIONS:
                opts[arg[2:]].append(argv[i + 1])
            else:
                opts[arg[2:]] = argv[i + 1]
            i += 2
            continue
        if arg.startswith("--"):
            raise UsageError(f"unknown option: {arg}")
        if opts["file"] is not None:
            raise UsageError("too many arguments")
        opts["file"] = arg
        i += 1
    return opts


def read_input(path, stdin):
    if path is None:
        return stdin.read()
    try:
        with open(path, encoding="utf-8", newline="") as handle:
            return handle.read()
    except OSError:
        raise UsageError(f"cannot read {path}") from None


def run(opts, text):
    table = read_table(text)
    table = apply_where(table, [parse_where(value) for value in opts["where"]])
    if opts["sort"] is not None:
        table = sort_rows(table, opts["sort"])
    return render(table, opts["format"]) + [footer(len(table.rows))]


def main(argv, stdin=None, stdout=None, stderr=None):
    stdin = stdin if stdin is not None else sys.stdin
    stdout = stdout if stdout is not None else sys.stdout
    stderr = stderr if stderr is not None else sys.stderr
    try:
        opts = parse_args(list(argv))
        lines = run(opts, read_input(opts["file"], stdin))
    except UsageError as err:
        print(f"tally: {err}", file=stderr)
        return 2
    for line in lines:
        print(line, file=stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
