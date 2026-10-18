"""RFC 6901 JSON pointers and RFC 6902 JSON patches."""
from .exceptions import PatchError, PointerError, PathError, OperationError, TestFailed
from .jsonpointer import parse_pointer as _parse_pointer, format_pointer, resolve
from .patch import apply_patch
from .diff import diff
from .patch import explain
from .util import json_equal
from .inspect import list_pointers, type_counts


def parse_pointer(text):
    """Split a pointer into its unescaped tokens."""
    return list(_parse_pointer(text))
