"""The command line entry point main()."""
import argparse
import datetime
import sys

from . import fires, month_report, normalize, CronError, ArgumentError


def main(argv=None):
    """Run the command line and return the exit code."""
    p = argparse.ArgumentParser(prog="cronplan")
    sub = p.add_subparsers(dest="command", required=True)
    n = sub.add_parser("next")
    n.add_argument("expression")
    n.add_argument("--after", required=True)
    n.add_argument("--count", type=int, default=1)
    sub.add_parser("normalize").add_argument("expression")
    sub.add_parser("check").add_argument("expression")
    m = sub.add_parser("month")
    m.add_argument("expression")
    m.add_argument("month")
    args = p.parse_args(argv)
    try:
        if args.command == "next":
            try:
                after = datetime.datetime.fromisoformat(args.after)
            except Exception:
                raise ArgumentError("bad datetime: %r" % (args.after,))
            for t in fires(args.expression, after, args.count):
                print(t.isoformat(timespec="minutes"))
        elif args.command == "month":
            year, dash, mon = args.month.partition("-")
            if not dash or not year.isdigit() or not mon.isdigit():
                raise ArgumentError("bad month: %r" % (args.month,))
            print(month_report(args.expression, int(year), int(mon)))
        elif args.command == "check":
            normalize(args.expression)
            print("ok")
        else:
            print(normalize(args.expression))
    except CronError as e:
        sys.stderr.write("error: %s\n" % e)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
