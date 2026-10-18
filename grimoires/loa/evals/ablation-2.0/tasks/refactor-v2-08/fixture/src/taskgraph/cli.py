"""The command line entry point main()."""
import argparse
import sys

import taskgraph
from .scheduler import ArgumentError
from .util import format_duration


def main(argv=None):
    """Run the command line and return the exit code."""
    p = argparse.ArgumentParser(prog="taskgraph")
    sub = p.add_subparsers(dest="command", required=True)
    for name in ("order", "levels", "critical", "schedule", "check", "slack", "dot"):
        c = sub.add_parser(name)
        c.add_argument("manifest")
        if name == "schedule":
            c.add_argument("--workers", type=int, default=2)
    args = p.parse_args(argv)
    try:
        try:
            with open(args.manifest, encoding="utf-8") as fh:
                text = fh.read()
        except OSError:
            raise ArgumentError("cannot read %r" % (args.manifest,))
        if args.command == "order":
            print("\n".join(taskgraph.order(text)))
        elif args.command == "levels":
            for i, names in enumerate(taskgraph.levels(text)):
                print("%d: %s" % (i, " ".join(names)))
        elif args.command == "critical":
            total, path = taskgraph.critical_path(text)
            print("%s: %s" % (format_duration(total), " > ".join(path)))
        elif args.command == "schedule":
            print(taskgraph.report(text, args.workers))
        elif args.command == "slack":
            for name, value in taskgraph.slack(text).items():
                print("%s %s" % (name, format_duration(value)))
        elif args.command == "dot":
            print(taskgraph.to_dot(text))
        else:
            print("ok: %d tasks" % len(taskgraph.parse(text).tasks))
    except taskgraph.PlanError as e:
        print("error: %s" % e, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
