"""The command line entry point main()."""
import argparse
import sys

import semverkit
from semverkit.ranges import InvalidRange


def main(argv=None):
    """Run the command line and return the exit code."""
    parser = argparse.ArgumentParser(prog="semverkit")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("parse").add_argument("version")
    sub.add_parser("sort").add_argument("versions", nargs="+")
    b = sub.add_parser("bump")
    b.add_argument("version")
    b.add_argument("part")
    b.add_argument("--id", dest="ident")
    t = sub.add_parser("test")
    t.add_argument("version")
    t.add_argument("range")
    t.add_argument("--pre", action="store_true")
    m = sub.add_parser("max")
    m.add_argument("range")
    m.add_argument("versions", nargs="+")
    m.add_argument("--pre", action="store_true")
    tb = sub.add_parser("table")
    tb.add_argument("--range", dest="ranges", action="append", required=True)
    tb.add_argument("versions", nargs="*")
    sub.add_parser("normalize").add_argument("range")
    args = parser.parse_args(argv)
    try:
        if args.command == "parse":
            out = semverkit.valid(args.version)
            if out is None:
                print("error: invalid version: %r" % (args.version,), file=sys.stderr)
                return 2
            print(out)
        elif args.command == "sort":
            print("\n".join(semverkit.sort(args.versions)))
        elif args.command == "bump":
            print(semverkit.bump(args.version, args.part, args.ident))
        elif args.command == "test":
            if semverkit.satisfies(args.version, args.range, args.pre):
                print("yes")
            else:
                print("no")
                return 1
        elif args.command == "max":
            best = semverkit.max_satisfying(args.versions, args.range, args.pre)
            if best is None:
                print("none")
                return 1
            print(best)
        elif args.command == "table":
            print(semverkit.render_table(args.versions, args.ranges))
        else:
            print(semverkit.normalize_range(args.range))
    except (ValueError, InvalidRange) as exc:
        print("error: %s" % exc, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
