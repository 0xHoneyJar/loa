"""Content digests: the leading hex digits of a SHA-256."""
import hashlib

from . import tree


def digest_bytes(data, length=16):
    return hashlib.sha256(data).hexdigest()[:length]


def digest_file(root, rel, length=16):
    h = hashlib.sha256()
    with open(tree.absolute(root, rel), "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()[:length]
