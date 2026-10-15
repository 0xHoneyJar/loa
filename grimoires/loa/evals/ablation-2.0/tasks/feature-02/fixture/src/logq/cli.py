"""logq command line.

    logq [--level LEVEL] [--grep TEXT] [FILE]

Reads FILE (or standard input), drops lines that are not well-formed log lines,
and prints the remaining lines unchanged, in input order.

  --level LEVEL   keep records at LEVEL or more severe (DEBUG < INFO < WARN < ERROR)
  --grep TEXT     keep records whose message contains TEXT (case-sensitive)

Exit status: 0 on success (even when nothing matched), 2 on a usage error
(message on standard error, nothing on standard output).
"""
import argparse
import sys

from .records import LEVELS, parse_line


class UsageError(Exception):
    pass


class _Parser(argparse.ArgumentParser):
    def error(self, message):
        raise UsageError(message)


def build_parser():
    p = _Parser(prog="logq", add_help=False)
    p.add_argument("--level", choices=LEVELS)
    p.add_argument("--grep")
    p.add_argument("file", nargs="?")
    return p


def select(records, args):
    floor = LEVELS.index(args.level) if args.level else 0
    for rec in records:
        if LEVELS.index(rec.level) < floor:
            continue
        if args.grep is not None and args.grep not in rec.message:
            continue
        yield rec


def main(argv=None, stdin=None, stdout=None, stderr=None):
    stdin = stdin or sys.stdin
    stdout = stdout or sys.stdout
    stderr = stderr or sys.stderr
    try:
        args = build_parser().parse_args(argv)
    except UsageError as e:
        print(f"logq: {e}", file=stderr)
        return 2
    if args.file:
        with open(args.file, encoding="utf-8") as fh:
            lines = fh.readlines()
    else:
        lines = stdin.readlines()
    records = [r for r in (parse_line(l) for l in lines) if r is not None]
    for rec in select(records, args):
        print(rec.raw, file=stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
