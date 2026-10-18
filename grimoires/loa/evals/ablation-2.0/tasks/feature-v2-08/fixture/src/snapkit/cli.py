"""Command line.

    snapkit snapshot [--root DIR] [--config FILE] [--output FILE]
    snapkit diff OLD NEW
    snapkit du [--root DIR] [--config FILE] [--depth N] [--human]

The config file is ``--config FILE`` when given, else ``<root>/snapkit.conf``
when it exists, else the defaults.  Errors print ``snapkit: <message>`` on
standard error and exit with status 2; ``diff`` exits 1 when the snapshots
differ and 0 when they are equal.
"""
import sys

from . import sizes, walker
from .config import load_config
from .diff import diff_snapshots, format_diff
from .errors import SnapError
from .report import format_du
from .snapshot import build_snapshot, format_snapshot, parse_snapshot

USAGE = """usage: snapkit snapshot [--root DIR] [--config FILE] [--output FILE]
       snapkit diff OLD NEW
       snapkit du [--root DIR] [--config FILE] [--depth N] [--human]"""


class UsageError(SnapError):
    pass


def _options(args, valued, flags=()):
    """Split ``args`` into ({option: value}, [positionals])."""
    options, positionals = {}, []
    args = list(args)
    while args:
        arg = args.pop(0)
        if arg in valued:
            if not args:
                raise UsageError(f"option {arg} needs a value")
            options[arg] = args.pop(0)
        elif arg in flags:
            options[arg] = True
        elif arg.startswith("--"):
            raise UsageError(f"unknown option {arg}")
        else:
            positionals.append(arg)
    return options, positionals


def _read(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except OSError:
        raise SnapError(f"{path}: cannot read") from None


def _cmd_snapshot(args, out):
    opts, pos = _options(args, ("--root", "--config", "--output"))
    if pos:
        raise UsageError("snapshot takes no arguments")
    root = opts.get("--root", ".")
    config = load_config(root, opts.get("--config"))
    text = format_snapshot(build_snapshot(root, config))
    if "--output" in opts:
        with open(opts["--output"], "w", encoding="utf-8") as fh:
            fh.write(text)
    else:
        out.write(text)
    return 0


def _cmd_diff(args, out):
    opts, pos = _options(args, ())
    if len(pos) != 2:
        raise UsageError("diff takes OLD and NEW")
    old = parse_snapshot(_read(pos[0]), pos[0])
    new = parse_snapshot(_read(pos[1]), pos[1])
    changes = diff_snapshots(old, new)
    out.write(format_diff(changes))
    return 1 if changes else 0


def _cmd_du(args, out):
    opts, pos = _options(args, ("--root", "--config", "--depth"), ("--human",))
    if pos:
        raise UsageError("du takes no arguments")
    root = opts.get("--root", ".")
    config = load_config(root, opts.get("--config"))
    max_depth = None
    if "--depth" in opts:
        if not opts["--depth"].isdigit():
            raise UsageError("--depth needs a non-negative integer")
        max_depth = int(opts["--depth"])
    totals = sizes.directory_totals(walker.walk(root, config), config.block_size)
    out.write(format_du(totals, max_depth, bool(opts.get("--human"))))
    return 0


COMMANDS = {"snapshot": _cmd_snapshot, "diff": _cmd_diff, "du": _cmd_du}


def main(argv, stdout=None, stderr=None):
    stdout = stdout or sys.stdout
    stderr = stderr or sys.stderr
    if not argv or argv[0] not in COMMANDS:
        print(USAGE, file=stderr)
        return 2
    try:
        return COMMANDS[argv[0]](argv[1:], stdout)
    except UsageError as exc:
        print(f"snapkit: {exc}", file=stderr)
        print(USAGE, file=stderr)
        return 2
    except SnapError as exc:
        print(f"snapkit: {exc}", file=stderr)
        return 2


if __name__ == "__main__":  # pragma: no cover
    sys.exit(main(sys.argv[1:]))
