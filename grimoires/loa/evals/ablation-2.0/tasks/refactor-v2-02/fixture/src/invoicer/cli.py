"""Command line: ``invoicer render FILE``, ``invoicer total FILE``, ``invoicer batch FILE...``."""
import sys

from . import batch
from .api import process
from .pricing import ParseError, PricingError, format_money, invoice_totals, parse_invoice

USAGE = "usage: invoicer render FILE | invoicer total FILE | invoicer batch FILE..."


def _read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def main(argv, stdout=None, stderr=None):
    stdout = stdout or sys.stdout
    stderr = stderr or sys.stderr
    if len(argv) < 2 or argv[0] not in ("render", "total", "batch") or (argv[0] != "batch" and len(argv) != 2):
        print(USAGE, file=stderr)
        return 2
    command, paths = argv[0], argv[1:]
    try:
        texts = [_read(path) for path in paths]
    except OSError as exc:
        print(f"invoicer: {exc.filename}: cannot read", file=stderr)
        return 1
    if command == "batch":
        stdout.write(batch.summary(texts))
        return 0
    try:
        if command == "render":
            stdout.write(process(texts[0]))
        else:
            invoice = parse_invoice(texts[0])
            print(format_money(invoice_totals(invoice).total, invoice.currency), file=stdout)
    except (ParseError, PricingError) as exc:
        print(f"invoicer: {paths[0]}: {exc}", file=stderr)
        return 1
    return 0
