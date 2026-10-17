"""Command line: ``docstore [--root DIR] [--config FILE] COMMAND ...``.

Commands::

    create ID FILE            store FILE's JSON object as a new document
    put ID FILE [--rev N]     replace a document (N: expected current revision)
    show ID                   print the document's canonical JSON
    select ID PATH            print the value at a dotted path
    delete ID [--rev N]       delete a document
    list                      print every id with its revision
    history [ID]              print history lines (of one document)
    export                    print a bundle of every document
    import FILE [--replace]   load a bundle
    find PATH JSON            print the ids whose value at PATH equals JSON
    stats                     print store statistics

The configuration is ``--config FILE`` or, when absent, ``<root>/docstore.conf``
if that file exists. Output goes to standard output, one item per line. An error
prints ``docstore: <message>`` on standard error and exits with the status of
EXIT_CODES (2 for usage errors).
"""
import argparse
import os
import sys

from .canon import canonical, parse_json
from .config import Config, load_config
from .errors import Conflict, DocstoreError, NotFound, ValidationError
from .export import export_bundle, import_bundle
from .history import History
from .query import find, select
from .stats import format_stats, store_stats
from .storage import FileStorage
from .store import Store

EXIT_CODES = (
    (NotFound, 3),
    (Conflict, 4),
    (ValidationError, 5),
    (DocstoreError, 1),
)


class _Parser(argparse.ArgumentParser):
    def error(self, message):
        raise _Usage(message)


class _Usage(Exception):
    pass


def build_parser():
    parser = _Parser(prog="docstore", add_help=False)
    parser.add_argument("--root", default=".")
    parser.add_argument("--config")
    sub = parser.add_subparsers(dest="command", parser_class=_Parser)
    p = sub.add_parser("create", add_help=False)
    p.add_argument("id")
    p.add_argument("file")
    p = sub.add_parser("put", add_help=False)
    p.add_argument("id")
    p.add_argument("file")
    p.add_argument("--rev", type=int)
    p = sub.add_parser("show", add_help=False)
    p.add_argument("id")
    p = sub.add_parser("select", add_help=False)
    p.add_argument("id")
    p.add_argument("path")
    p = sub.add_parser("delete", add_help=False)
    p.add_argument("id")
    p.add_argument("--rev", type=int)
    sub.add_parser("list", add_help=False)
    p = sub.add_parser("history", add_help=False)
    p.add_argument("id", nargs="?")
    sub.add_parser("export", add_help=False)
    p = sub.add_parser("import", add_help=False)
    p.add_argument("file")
    p.add_argument("--replace", action="store_true")
    p = sub.add_parser("find", add_help=False)
    p.add_argument("path")
    p.add_argument("value")
    sub.add_parser("stats", add_help=False)
    return parser


def open_store(root, config_path=None):
    if config_path is None:
        default = os.path.join(root, "docstore.conf")
        config = load_config(default) if os.path.exists(default) else Config()
    else:
        config = load_config(config_path)
    storage = FileStorage(root)
    history = History(os.path.join(root, config.history_file))
    return Store(storage, history, config)


def _read_json(path):
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except OSError as exc:
        raise DocstoreError(f"cannot read {path}: {exc.strerror}") from None
    return parse_json(text, path)


def _read_text(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except OSError as exc:
        raise DocstoreError(f"cannot read {path}: {exc.strerror}") from None


def _run(args, out):
    store = open_store(args.root, args.config)
    command = args.command
    if command == "create":
        rev = store.create(args.id, _read_json(args.file))
        out.write(f"rev {rev}\n")
    elif command == "put":
        rev = store.put(args.id, _read_json(args.file), expected_rev=args.rev)
        out.write(f"rev {rev}\n")
    elif command == "show":
        out.write(canonical(store.get(args.id)) + "\n")
    elif command == "select":
        out.write(canonical(select(store.get(args.id), args.path)) + "\n")
    elif command == "delete":
        store.delete(args.id, expected_rev=args.rev)
    elif command == "list":
        for doc_id in store.ids():
            out.write(f"{doc_id} {store.revision(doc_id)}\n")
    elif command == "history":
        for entry in store.history.entries(args.id):
            out.write("\t".join(map(str, entry)) + "\n")
    elif command == "export":
        out.write(export_bundle(store) + "\n")
    elif command == "import":
        count = import_bundle(store, _read_text(args.file), replace=args.replace)
        out.write(f"imported {count}\n")
    elif command == "find":
        value = parse_json(args.value, "value")
        for doc_id in find(store, args.path, value):
            out.write(doc_id + "\n")
    elif command == "stats":
        out.write(format_stats(store_stats(store)))
    return 0


def exit_code(error):
    for cls, code in EXIT_CODES:
        if isinstance(error, cls):
            return code
    return 1


def main(argv=None, stdout=None, stderr=None):
    out = stdout if stdout is not None else sys.stdout
    err = stderr if stderr is not None else sys.stderr
    try:
        args = build_parser().parse_args(sys.argv[1:] if argv is None else list(argv))
        if args.command is None:
            raise _Usage("a command is required")
    except _Usage as exc:
        err.write(f"docstore: usage: {exc}\n")
        return 2
    try:
        return _run(args, out)
    except DocstoreError as exc:
        err.write(f"docstore: {exc}\n")
        return exit_code(exc)


if __name__ == "__main__":
    sys.exit(main())
