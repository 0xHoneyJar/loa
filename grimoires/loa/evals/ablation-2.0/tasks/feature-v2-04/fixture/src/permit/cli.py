"""Command line: ``permit check --policy FILE --users FILE USER ACTION PATH``."""
import sys

from .engine import Evaluator
from .errors import PermitError
from .principals import parse_directory
from .rules import parse_rules

USAGE = "usage: permit check --policy FILE --users FILE USER ACTION PATH"


def _parse_args(args):
    options, positionals = {}, []
    while args:
        arg = args.pop(0)
        if arg in ("--policy", "--users"):
            if not args:
                return None
            options[arg[2:]] = args.pop(0)
        elif arg.startswith("--"):
            return None
        else:
            positionals.append(arg)
    if set(options) != {"policy", "users"} or len(positionals) != 3:
        return None
    return options, positionals


def _read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def main(argv, stdout=None, stderr=None):
    stdout = stdout or sys.stdout
    stderr = stderr or sys.stderr
    parsed = _parse_args(list(argv[1:])) if argv and argv[0] == "check" else None
    if parsed is None:
        print(USAGE, file=stderr)
        return 2
    options, (user, action, path) = parsed
    try:
        evaluator = Evaluator(parse_directory(_read(options["users"])), parse_rules(_read(options["policy"]), "policy"))
        allowed = evaluator.check(user, action, path)
    except OSError as exc:
        print(f"permit: {exc.filename}: cannot read", file=stderr)
        return 2
    except PermitError as exc:
        print(f"permit: {exc}", file=stderr)
        return 2
    print("allow" if allowed else "deny", file=stdout)
    return 0
