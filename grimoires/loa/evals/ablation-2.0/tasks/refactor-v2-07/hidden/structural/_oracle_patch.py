"""Reference behaviour of the package, flattened into one module (grader side)."""

import enum
from dataclasses import dataclass
import re
import copy
import json


# ---- errors ----

class PatchError(ValueError):
    """Base class of every error the package raises."""


class PointerError(PatchError):
    """A pointer string does not follow RFC 6901."""


class PathError(PatchError):
    """A pointer does not lead to a usable location in the document."""


class OperationError(PatchError):
    """A patch or one of its operations is malformed or cannot apply."""


class TestFailedError(PatchError):
    """A test operation found a different value."""


class InputError(PatchError):
    """A command-line input file cannot be read or decoded."""


# ---- model ----

class OpKind(enum.Enum):
    """The six operations of RFC 6902."""

    ADD = "add"
    REMOVE = "remove"
    REPLACE = "replace"
    MOVE = "move"
    COPY = "copy"
    TEST = "test"


class JsonType(enum.Enum):
    """The six JSON value types, in report order."""

    OBJECT = "object"
    ARRAY = "array"
    STRING = "string"
    NUMBER = "number"
    BOOLEAN = "boolean"
    NULL = "null"


@dataclass(frozen=True, slots=True)
class Operation:
    """One validated operation; source is the from pointer of move and copy."""

    kind: OpKind
    path: str
    value: object = None
    source: str = ""
    index: int = 0


@dataclass(frozen=True, slots=True)
class Target:
    """A parsed pointer with its text and the operation it belongs to."""

    tokens: tuple[str, ...]
    pointer: str
    index: int = -1


# ---- pointer ----

def _unescape(token: str, text: str) -> str:
    if re.search(r"~(?![01])", token):
        raise PointerError(f"invalid escape in pointer: {text!r}")
    return token.replace("~1", "/").replace("~0", "~")


def parse_pointer(text: str) -> tuple[str, ...]:
    """Split a pointer into its unescaped reference tokens."""
    if not isinstance(text, str):
        raise PointerError(f"pointer must be a string: {text!r}")
    if text == "":
        return ()
    if not text.startswith("/"):
        raise PointerError(f"invalid pointer: {text!r}")
    return tuple(_unescape(token, text) for token in text[1:].split("/"))


def format_pointer(tokens: tuple[str, ...]) -> str:
    """Join reference tokens into an escaped pointer."""
    return "".join("/" + t.replace("~", "~0").replace("/", "~1") for t in tokens)


# ---- equality ----

def _is_number(value: object) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _same_list(a: list[object], b: list[object]) -> bool:
    return len(a) == len(b) and all(json_equal(x, y) for x, y in zip(a, b))


def _same_dict(a: dict[str, object], b: dict[str, object]) -> bool:
    return a.keys() == b.keys() and all(json_equal(a[k], b[k]) for k in a)


def json_equal(a: object, b: object) -> bool:
    """Compare two JSON values; 1 equals 1.0, true never equals 1."""
    if _is_number(a) and _is_number(b):
        return a == b
    if type(a) is not type(b):
        return False
    if isinstance(a, list):
        return _same_list(a, b)
    if isinstance(a, dict):
        return _same_dict(a, b)
    return a == b


# ---- navigate ----

def where(target: Target) -> str:
    """Return the message prefix naming the operation, if any."""
    return f"operation {target.index}: " if target.index >= 0 else ""


def _number(token: str, target: Target) -> int:
    if not re.fullmatch(r"0|[1-9][0-9]*", token):
        raise PathError(f"{where(target)}invalid array index {token!r} in {target.pointer!r}")
    return int(token)


def array_index(token: str, length: int, target: Target) -> int:
    """Read an index of an existing array element."""
    if token == "-":
        raise PathError(f"{where(target)}index '-' is past the end: {target.pointer!r}")
    index = _number(token, target)
    if index >= length:
        raise PathError(f"{where(target)}index {index} out of range in {target.pointer!r}")
    return index


def insert_index(token: str, length: int, target: Target) -> int:
    """Read an index where an add may insert; '-' and the length append."""
    if token == "-":
        return length
    index = _number(token, target)
    if index > length:
        raise PathError(f"{where(target)}index {index} out of range in {target.pointer!r}")
    return index


def _step(current: object, token: str, target: Target) -> object:
    if isinstance(current, dict):
        if token not in current:
            raise PathError(f"{where(target)}path not found: {target.pointer!r}")
        return current[token]
    if isinstance(current, list):
        return current[array_index(token, len(current), target)]
    raise PathError(f"{where(target)}cannot descend into a scalar at {target.pointer!r}")


def get_at(document: object, tokens: tuple[str, ...], target: Target) -> object:
    """Return the value at the given tokens of a target's pointer."""
    current = document
    for token in tokens:
        current = _step(current, token, target)
    return current


# ---- operations ----

def required_members(kind: OpKind) -> tuple[str, ...]:
    """Return the members an operation of this kind needs besides op and path."""
    match kind:
        case OpKind.ADD | OpKind.REPLACE | OpKind.TEST:
            return ("value",)
        case OpKind.MOVE | OpKind.COPY:
            return ("from",)
        case OpKind.REMOVE:
            return ()


def _kind(raw: dict[str, object], index: int) -> OpKind:
    if "op" not in raw:
        raise OperationError(f"operation {index}: missing 'op'")
    names = [k.value for k in OpKind]
    if not isinstance(raw["op"], str) or raw["op"] not in names:
        raise OperationError(f"operation {index}: unknown op {raw['op']!r}")
    return OpKind(raw["op"])


def _pointer_member(raw: dict[str, object], name: str, index: int) -> str:
    if name not in raw:
        raise OperationError(f"operation {index}: missing {name!r}")
    if not isinstance(raw[name], str):
        raise OperationError(f"operation {index}: {name!r} must be a string")
    parse_pointer(raw[name])
    return raw[name]


def parse_operation(raw: object, index: int) -> Operation:
    """Validate one raw operation object."""
    if not isinstance(raw, dict):
        raise OperationError(f"operation {index}: not an object")
    kind = _kind(raw, index)
    path = _pointer_member(raw, "path", index)
    needs = required_members(kind)
    if "value" in needs and "value" not in raw:
        raise OperationError(f"operation {index}: missing 'value'")
    source = _pointer_member(raw, "from", index) if "from" in needs else ""
    return Operation(kind, path, raw.get("value"), source, index)


def parse_patch(raw: object) -> tuple[Operation, ...]:
    """Validate a whole patch before anything is applied."""
    if not isinstance(raw, list):
        raise OperationError("patch must be a list")
    return tuple(parse_operation(item, index) for index, item in enumerate(raw))


# ---- survey ----

def _children(value: object) -> list[tuple[str, object]]:
    if isinstance(value, dict):
        return list(value.items())
    if isinstance(value, list):
        return [(str(i), v) for i, v in enumerate(value)]
    return []


def _collect(value: object, tokens: tuple[str, ...], out: list[str]) -> None:
    out.append(format_pointer(tokens))
    for token, child in _children(value):
        _collect(child, tokens + (token,), out)


def list_pointers(document: object) -> list[str]:
    """List the pointer of every value, the root first, in document order."""
    out: list[str] = []
    _collect(document, (), out)
    return out


def json_type(value: object) -> JsonType:
    """Return the JSON type of a value."""
    checks = ((dict, JsonType.OBJECT), (list, JsonType.ARRAY), (str, JsonType.STRING), (bool, JsonType.BOOLEAN))
    for cls, kind in checks:
        if isinstance(value, cls):
            return kind
    if isinstance(value, (int, float)):
        return JsonType.NUMBER
    if value is None:
        return JsonType.NULL
    raise PathError(f"not a JSON value: {value!r}")


def type_counts(document: object) -> dict[str, int]:
    """Count the values of each JSON type, the root included."""
    counts = {kind.value: 0 for kind in JsonType}
    stack = [document]
    while stack:
        value = stack.pop()
        counts[json_type(value).value] += 1
        stack.extend(child for _, child in _children(value))
    return counts


# ---- mutate ----

def add_at(document: object, target: Target, value: object) -> object:
    """Add a value at a target and return the new root."""
    if not target.tokens:
        return copy.deepcopy(value)
    parent = get_at(document, target.tokens[:-1], target)
    last = target.tokens[-1]
    if isinstance(parent, dict):
        parent[last] = copy.deepcopy(value)
    elif isinstance(parent, list):
        parent.insert(insert_index(last, len(parent), target), copy.deepcopy(value))
    else:
        raise PathError(f"{where(target)}cannot add to a scalar at {target.pointer!r}")
    return document


def _container(document: object, target: Target) -> dict[str, object] | list[object]:
    parent = get_at(document, target.tokens[:-1], target)
    if not isinstance(parent, (dict, list)):
        raise PathError(f"{where(target)}cannot descend into a scalar at {target.pointer!r}")
    if isinstance(parent, dict) and target.tokens[-1] not in parent:
        raise PathError(f"{where(target)}path not found: {target.pointer!r}")
    return parent


def _slot(parent: dict[str, object] | list[object], target: Target) -> str | int:
    last = target.tokens[-1]
    return last if isinstance(parent, dict) else array_index(last, len(parent), target)


def remove_at(document: object, target: Target) -> tuple[object, object]:
    """Remove the value at a target; return the new root and the value."""
    if not target.tokens:
        raise PathError(f"{where(target)}cannot remove the root")
    parent = _container(document, target)
    return document, parent.pop(_slot(parent, target))


def replace_at(document: object, target: Target, value: object) -> object:
    """Replace the value at a target and return the new root."""
    if not target.tokens:
        return copy.deepcopy(value)
    parent = _container(document, target)
    parent[_slot(parent, target)] = copy.deepcopy(value)
    return document


# ---- diffing ----

def _op(kind: str, tokens: tuple[str, ...], value: object = None) -> dict[str, object]:
    out: dict[str, object] = {"op": kind, "path": format_pointer(tokens)}
    if kind != "remove":
        out["value"] = value
    return out


def _only_in(a: dict[str, object], b: dict[str, object]) -> list[str]:
    return sorted(k for k in a if k not in b)


def _diff_dicts(a: dict[str, object], b: dict[str, object], tokens: tuple[str, ...]) -> list[dict[str, object]]:
    ops = [_op("remove", tokens + (k,)) for k in _only_in(a, b)]
    for key in sorted(k for k in a if k in b):
        ops.extend(diff(a[key], b[key], tokens + (key,)))
    ops.extend(_op("add", tokens + (k,), b[k]) for k in _only_in(b, a))
    return ops


def _diff_lists(a: list[object], b: list[object], tokens: tuple[str, ...]) -> list[dict[str, object]]:
    ops: list[dict[str, object]] = []
    for index, (x, y) in enumerate(zip(a, b)):
        ops.extend(diff(x, y, tokens + (str(index),)))
    return ops


def diff(a: object, b: object, tokens: tuple[str, ...] = ()) -> list[dict[str, object]]:
    """Return raw operations that turn a into b."""
    if json_equal(a, b):
        return []
    if isinstance(a, dict) and isinstance(b, dict):
        return _diff_dicts(a, b, tokens)
    if isinstance(a, list) and isinstance(b, list) and len(a) == len(b):
        return _diff_lists(a, b, tokens)
    return [_op("replace", tokens, b)]


# ---- explain ----

def _shown(pointer: str) -> str:
    return pointer if pointer else "(root)"


def _value(value: object) -> str:
    return " = " + json.dumps(value, sort_keys=True, separators=(",", ":"))


def explain_operation(op: Operation) -> str:
    """Describe one operation in a single line."""
    head = f"{op.index + 1}. {op.kind.value} {_shown(op.path)}"
    match op.kind:
        case OpKind.ADD | OpKind.REPLACE | OpKind.TEST:
            return head + _value(op.value)
        case OpKind.MOVE | OpKind.COPY:
            return head + " from " + _shown(op.source)
        case OpKind.REMOVE:
            return head


def explain_patch(raw: object) -> str:
    """Describe a raw patch, one line per operation."""
    operations = parse_patch(raw)
    if not operations:
        return "(empty patch)"
    return "\n".join(explain_operation(op) for op in operations)


# ---- apply ----

def target_of(pointer: str, index: int) -> Target:
    """Parse a pointer of an operation into a target."""
    return Target(parse_pointer(pointer), pointer, index)


def _move(document: object, op: Operation) -> object:
    source, target = target_of(op.source, op.index), target_of(op.path, op.index)
    if op.source == op.path:
        get_at(document, source.tokens, source)
        return document
    if op.path.startswith(op.source + "/"):
        raise OperationError(f"{where(target)}cannot move a value into itself")
    document, value = remove_at(document, source)
    return add_at(document, target, value)


def _copy(document: object, op: Operation) -> object:
    source = target_of(op.source, op.index)
    value = copy.deepcopy(get_at(document, source.tokens, source))
    return add_at(document, target_of(op.path, op.index), value)


def _test(document: object, op: Operation) -> object:
    target = target_of(op.path, op.index)
    if not json_equal(get_at(document, target.tokens, target), op.value):
        raise TestFailedError(f"{where(target)}test failed at {op.path!r}")
    return document


def apply_operation(document: object, op: Operation) -> object:
    """Apply one operation and return the new root."""
    match op.kind:
        case OpKind.ADD:
            return add_at(document, target_of(op.path, op.index), op.value)
        case OpKind.REMOVE:
            return remove_at(document, target_of(op.path, op.index))[0]
        case OpKind.REPLACE:
            return replace_at(document, target_of(op.path, op.index), op.value)
        case OpKind.MOVE:
            return _move(document, op)
        case OpKind.COPY:
            return _copy(document, op)
        case OpKind.TEST:
            return _test(document, op)


def apply_patch(document: object, operations: tuple[Operation, ...]) -> object:
    """Apply operations to a copy of a document; the input is never changed."""
    result = copy.deepcopy(document)
    for op in operations:
        result = apply_operation(result, op)
    return result


# ---- facade ----

def apply(document: object, patch: object) -> object:
    """Validate a raw patch, then apply it to a copy of a document."""
    return apply_patch(document, parse_patch(patch))


def resolve(document: object, pointer: str) -> object:
    """Return the value a pointer refers to."""
    target = target_of(pointer, -1)
    return get_at(document, target.tokens, target)


def diff_documents(a: object, b: object) -> list[dict[str, object]]:
    """Return raw operations that turn a into b."""
    return diff(a, b)


def explain(patch: object) -> str:
    """Describe a raw patch, one line per operation."""
    return explain_patch(patch)


def same_json(a: object, b: object) -> bool:
    """Compare two JSON values."""
    return json_equal(a, b)


def pointer_tokens(text: str) -> list[str]:
    """Split a pointer into its unescaped tokens."""
    return list(parse_pointer(text))


def format_tokens(tokens: list[str]) -> str:
    """Join tokens into an escaped pointer."""
    return format_pointer(tuple(tokens))


def pointer_list(document: object) -> list[str]:
    """List the pointer of every value of a document."""
    return list_pointers(document)


def value_types(document: object) -> dict[str, int]:
    """Count the values of each JSON type in a document."""
    return type_counts(document)

