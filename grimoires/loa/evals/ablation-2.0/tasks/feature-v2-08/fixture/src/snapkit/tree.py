"""Filesystem access for the walker: listing, typing and reading entries."""
import os
import stat

FILE, DIRECTORY, OTHER = "file", "dir", "other"


class Entry:
    """One directory entry: its relative path, kind and size in bytes."""

    __slots__ = ("path", "kind", "size")

    def __init__(self, path, kind, size=0):
        self.path = path
        self.kind = kind
        self.size = size

    @property
    def is_dir(self):
        return self.kind == DIRECTORY

    def __repr__(self):
        return f"Entry({self.path!r}, {self.kind!r}, {self.size!r})"

    def __eq__(self, other):
        return isinstance(other, Entry) and (self.path, self.kind, self.size) == (
            other.path, other.kind, other.size)


def absolute(root, rel):
    """Filesystem path of the relative path ``rel`` (``""`` is the root)."""
    if rel == "":
        return root
    return os.path.join(root, *rel.split("/"))


def kind_of(root, rel):
    """FILE, DIRECTORY or OTHER; symbolic links are OTHER, never followed."""
    try:
        st = os.lstat(absolute(root, rel))
    except OSError:
        return None
    if stat.S_ISLNK(st.st_mode):
        return OTHER
    if stat.S_ISDIR(st.st_mode):
        return DIRECTORY
    if stat.S_ISREG(st.st_mode):
        return FILE
    return OTHER


def list_names(root, rel):
    """Entry names of directory ``rel``, sorted by string order."""
    return sorted(os.listdir(absolute(root, rel)))


def file_size(root, rel):
    return os.lstat(absolute(root, rel)).st_size


def read_bytes(root, rel):
    with open(absolute(root, rel), "rb") as fh:
        return fh.read()


def read_text(root, rel):
    return read_bytes(root, rel).decode("utf-8")
