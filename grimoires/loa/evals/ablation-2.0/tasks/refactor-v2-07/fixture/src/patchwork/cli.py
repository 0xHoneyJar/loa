"""The command line entry point main()."""
import argparse
import json
import sys

import patchwork
from .exceptions import InputError


def _load(path):
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        raise InputError("cannot read %r" % (path,))
    try:
        return json.loads(text)
    except ValueError:
        raise InputError("bad json in %r" % (path,))


def main(argv=None):
    """Run the command line and return the exit code."""
    p = argparse.ArgumentParser(prog="patchwork")
    sub = p.add_subparsers(dest="command", required=True)
    a = sub.add_parser("apply")
    a.add_argument("document")
    a.add_argument("patch")
    g = sub.add_parser("get")
    g.add_argument("document")
    g.add_argument("pointer")
    d = sub.add_parser("diff")
    d.add_argument("before")
    d.add_argument("after")
    sub.add_parser("explain").add_argument("patch")
    sub.add_parser("paths").add_argument("document")
    sub.add_parser("types").add_argument("document")
    args = p.parse_args(argv)
    try:
        if args.command == "apply":
            out = json.dumps(patchwork.apply_patch(_load(args.document), _load(args.patch)), sort_keys=True, indent=2)
        elif args.command == "get":
            out = json.dumps(patchwork.resolve(_load(args.document), args.pointer), sort_keys=True)
        elif args.command == "diff":
            out = json.dumps(patchwork.diff(_load(args.before), _load(args.after)), indent=2)
        elif args.command == "paths":
            out = "\n".join(p or "(root)" for p in patchwork.list_pointers(_load(args.document)))
        elif args.command == "types":
            counts = patchwork.type_counts(_load(args.document))
            out = "\n".join("%s %d" % (k, v) for k, v in counts.items() if v)
        else:
            out = patchwork.explain(_load(args.patch))
    except patchwork.PatchError as e:
        print("error: %s" % e, file=sys.stderr)
        return 2
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
