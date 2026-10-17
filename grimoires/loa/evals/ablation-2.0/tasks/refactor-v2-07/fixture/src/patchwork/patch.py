"""RFC 6902 patches."""
import json

from . import registry
from .exceptions import OperationError, PathError, TestFailed
from .jsonpointer import parse_pointer, walk, index_of, _prefix
from .util import clone, json_equal


def _validate(patch):
    if not isinstance(patch, list):
        raise OperationError("patch must be a list")
    ops = []
    for i, raw in enumerate(patch):
        if not isinstance(raw, dict):
            raise OperationError("operation %d: not an object" % i)
        if "op" not in raw:
            raise OperationError("operation %d: missing 'op'" % i)
        if not isinstance(raw["op"], str) or raw["op"] not in registry.OP_NAMES:
            raise OperationError("operation %d: unknown op %r" % (i, raw["op"]))
        for name in ["path"] + registry.REQUIRED[raw["op"]]:
            if name not in raw:
                raise OperationError("operation %d: missing %r" % (i, name))
            if name != "value":
                if not isinstance(raw[name], str):
                    raise OperationError("operation %d: %r must be a string" % (i, name))
                parse_pointer(raw[name])
        ops.append(raw)
    return ops


def apply_patch(doc, patch):
    """Validate a raw patch, then apply it to a copy of a document."""
    ops = _validate(patch)
    doc = clone(doc)
    for i, op in enumerate(ops):
        kind = op["op"]
        path = op["path"]
        tokens = parse_pointer(path)
        if kind == "add" or kind == "copy":
            if kind == "copy":
                value = clone(walk(doc, parse_pointer(op["from"]), op["from"], i))
            else:
                value = op["value"]
            if not tokens:
                doc = clone(value)
                continue
            parent = walk(doc, tokens[:-1], path, i)
            if isinstance(parent, dict):
                parent[tokens[-1]] = clone(value)
            elif isinstance(parent, list):
                parent.insert(index_of(tokens[-1], parent, path, i, forAdd=True), clone(value))
            else:
                raise PathError("%scannot add to a scalar at %r" % (_prefix(i), path))
        elif kind == "remove" or kind == "replace":
            if not tokens:
                if kind == "remove":
                    raise PathError("%scannot remove the root" % _prefix(i))
                doc = clone(op["value"])
                continue
            parent = walk(doc, tokens[:-1], path, i)
            if not isinstance(parent, (dict, list)):
                raise PathError("%scannot descend into a scalar at %r" % (_prefix(i), path))
            if isinstance(parent, dict):
                if tokens[-1] not in parent:
                    raise PathError("%spath not found: %r" % (_prefix(i), path))
                key = tokens[-1]
            else:
                key = index_of(tokens[-1], parent, path, i)
            if kind == "remove":
                parent.pop(key)
            else:
                parent[key] = clone(op["value"])
        elif kind == "move":
            src = op["from"]
            if src == path:
                walk(doc, parse_pointer(src), src, i)
                continue
            if path.startswith(src + "/"):
                raise OperationError("%scannot move a value into itself" % _prefix(i))
            stoks = parse_pointer(src)
            if not stoks:
                raise PathError("%scannot remove the root" % _prefix(i))
            sparent = walk(doc, stoks[:-1], src, i)
            if not isinstance(sparent, (dict, list)):
                raise PathError("%scannot descend into a scalar at %r" % (_prefix(i), src))
            if isinstance(sparent, dict):
                if stoks[-1] not in sparent:
                    raise PathError("%spath not found: %r" % (_prefix(i), src))
                value = sparent.pop(stoks[-1])
            else:
                value = sparent.pop(index_of(stoks[-1], sparent, src, i))
            if not tokens:
                doc = clone(value)
                continue
            parent = walk(doc, tokens[:-1], path, i)
            if isinstance(parent, dict):
                parent[tokens[-1]] = clone(value)
            elif isinstance(parent, list):
                parent.insert(index_of(tokens[-1], parent, path, i, forAdd=True), clone(value))
            else:
                raise PathError("%scannot add to a scalar at %r" % (_prefix(i), path))
        else:
            actual = walk(doc, tokens, path, i)
            if not json_equal(actual, op["value"]):
                raise TestFailed("%stest failed at %r" % (_prefix(i), path))
    return doc


def explain(patch):
    """Describe a raw patch, one line per operation."""
    ops = _validate(patch)
    if len(ops) == 0:
        return "(empty patch)"
    lines = []
    for i, op in enumerate(ops):
        path = op["path"] or "(root)"
        line = "%d. %s %s" % (i + 1, op["op"], path)
        if op["op"] in ("add", "replace", "test"):
            line += " = " + json.dumps(op["value"], sort_keys=True, separators=(",", ":"))
        elif op["op"] in ("move", "copy"):
            line += " from " + (op["from"] or "(root)")
        lines.append(line)
    return "\n".join(lines)
