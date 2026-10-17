"""Walk a tree, leaving out what the config excludes.

``walk(root, config)`` yields an ``Entry`` for every directory and regular
file that is kept, parents before children, each directory's entries in name
order.  Symbolic links and other special files are skipped.  An excluded
directory is never entered, so nothing below it is yielded.
"""
from . import tree
from .paths import join


class Exclusions:
    """The config's ``exclude`` list: exact relative paths."""

    def __init__(self, entries=()):
        self.entries = set(entries)

    def excluded(self, path, is_dir):
        return path in self.entries


def walk(root, config, exclusions=None):
    if exclusions is None:
        exclusions = Exclusions(config.exclude)
    yield from _walk_dir(root, "", exclusions)


def _walk_dir(root, rel, exclusions):
    for name in tree.list_names(root, rel):
        path = join(rel, name)
        kind = tree.kind_of(root, path)
        if kind not in (tree.FILE, tree.DIRECTORY):
            continue
        is_dir = kind == tree.DIRECTORY
        if exclusions.excluded(path, is_dir):
            continue
        if is_dir:
            yield tree.Entry(path, kind, 0)
            yield from _walk_dir(root, path, exclusions)
        else:
            yield tree.Entry(path, kind, tree.file_size(root, path))


def files(root, config, exclusions=None):
    """Only the regular files of ``walk``."""
    return [e for e in walk(root, config, exclusions) if not e.is_dir]
