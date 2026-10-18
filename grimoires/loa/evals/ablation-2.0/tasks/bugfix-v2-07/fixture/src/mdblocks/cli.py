"""Command line: ``python -m mdblocks [file]`` renders a document (stdin without a file)."""

import sys

from . import render


def main(argv=None, out=None):
    argv = sys.argv[1:] if argv is None else argv
    out = sys.stdout if out is None else out
    if len(argv) > 1:
        print("usage: python -m mdblocks [file]", file=sys.stderr)
        return 2
    if argv:
        try:
            with open(argv[0], encoding="utf-8") as fh:
                text = fh.read()
        except OSError as exc:
            print(f"mdblocks: {exc}", file=sys.stderr)
            return 1
    else:
        text = sys.stdin.read()
    out.write(render(text))
    return 0
