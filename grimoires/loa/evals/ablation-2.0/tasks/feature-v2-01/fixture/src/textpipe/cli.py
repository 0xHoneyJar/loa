"""textpipe - apply named line filters to text.

Usage:
  textpipe [--config PATH] [--apply NAMES] [--number] [--skip-blank] [FILE]
  textpipe [--config PATH] --list

Options:
  --config PATH   a JSON config file; its `apply` list is used when --apply is not given
  --apply NAMES   comma-separated filter names, applied in order to every line
  --number        prefix each output line with its number
  --skip-blank    drop lines that are blank after filtering
  --list          print the available filters and exit

Reads FILE, or standard input when no FILE is given. Errors exit with status 2.
"""

import sys

from .config import Config, load_config
from .errors import UsageError
from .format import listing
from .pipeline import parse_apply, resolve, run
from .registry import Registry

VALUE_OPTIONS = ("--config", "--apply")
FLAG_OPTIONS = ("--number", "--skip-blank", "--list")


def parse_args(argv):
    opts = {"config": None, "apply": None, "number": False, "skip_blank": False,
            "list": False, "file": None}
    args = list(argv)
    i = 0
    while i < len(args):
        arg = args[i]
        if arg in VALUE_OPTIONS:
            if i + 1 >= len(args):
                raise UsageError(f"{arg} needs a value")
            opts[arg[2:]] = args[i + 1]
            i += 2
            continue
        if arg in FLAG_OPTIONS:
            opts[arg[2:].replace("-", "_")] = True
        elif arg.startswith("--"):
            raise UsageError(f"unknown option: {arg}")
        elif opts["file"] is None:
            opts["file"] = arg
        else:
            raise UsageError("too many arguments")
        i += 1
    return opts


def read_lines(path, stdin):
    if path is None:
        text = stdin.read()
    else:
        try:
            with open(path, encoding="utf-8") as handle:
                text = handle.read()
        except OSError:
            raise UsageError(f"cannot read {path}") from None
    return text.splitlines()


def main(argv, stdin=None, stdout=None, stderr=None):
    stdin = stdin if stdin is not None else sys.stdin
    stdout = stdout if stdout is not None else sys.stdout
    stderr = stderr if stderr is not None else sys.stderr
    try:
        opts = parse_args(argv)
        registry = Registry.with_builtins()
        config = load_config(opts["config"], registry) if opts["config"] else Config()
        if opts["list"]:
            out = listing(registry.entries())
        else:
            names = parse_apply(opts["apply"]) if opts["apply"] is not None else config.apply
            filters = resolve(registry, names)
            out = run(read_lines(opts["file"], stdin), filters,
                      number=opts["number"], skip_blank=opts["skip_blank"])
    except UsageError as err:
        print(f"textpipe: {err}", file=stderr)
        return 2
    for line in out:
        print(line, file=stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
