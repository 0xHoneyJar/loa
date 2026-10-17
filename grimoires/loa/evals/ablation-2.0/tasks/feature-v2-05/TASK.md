# Task: JSON Pointer, JSON Patch, canonical diff and revert for docstore

`docstore` (under `src/docstore/`) is a small JSON document store: documents by id, a revision per document, an append-only history, bundles, a command line. Documents can only be replaced whole today. Add JSON Pointer addressing and JSON Patch updates, following RFC 6901 and RFC 6902 **as specified below**, then a canonical structural diff, revision retrieval and revert built on them. Where this text and the RFCs differ, this text wins. Every message below is exact; `<repr X>` means Python's `repr()` of the string X as given (for example `'/a/b'`).

## 1. Pointers: `docstore.pointer`

Add a module `docstore.pointer` with `parse_pointer(text)`, `format_pointer(tokens)` and `resolve(doc, pointer)`, and an exception `docstore.errors.PointerError` (a direct subclass of `DocstoreError`).

1. `parse_pointer("")` is `[]` (the whole document). Any other pointer must start with `/`; otherwise `PointerError("pointer must start with '/': <repr text>")`.
2. The text after the first `/` is split on `/` into tokens, so `"/"` is `[""]` and `"/a//b"` is `["a", "", "b"]`.
3. In each token `~1` decodes to `/` and then `~0` decodes to `~`, so `~01` is `~1`, never `/`. A `~` followed by anything other than `0` or `1`, or at the end of a token, raises `PointerError("bad escape in pointer: <repr text>")` (the whole pointer).
4. `format_pointer(tokens)` is the inverse: each token has `~` encoded as `~0` and then `/` as `~1`, each prefixed with `/`. `format_pointer([])` is `""`.
5. `resolve(doc, pointer)` parses the pointer (rules 1–3) and walks its tokens from the left, starting at `doc`. At each step, with the current value `cur` and the token `t`:
   - `cur` is an object: `t` is a member name (any string, including `""`, `-` and `01`). A missing member raises `PointerError("path <repr pointer> does not exist")`.
   - `cur` is an array: `t` must be `0` or a non-zero digit followed by digits (`[1-9][0-9]*`). The token `-` raises `PointerError("index '-' out of range in <repr pointer>")`. Any other non-conforming token (`01`, `+1`, `1.0`, ` 1`, `""`, `x`) raises `PointerError("invalid array index <repr t> in <repr pointer>")`. A conforming index `>= len(cur)` raises `PointerError("index <repr t> out of range in <repr pointer>")`.
   - `cur` is anything else (string, number, boolean, null): `PointerError("path <repr pointer> does not exist")`.
   In every message the pointer is the full pointer as given, not the prefix walked so far.
6. `resolve` returns the value itself (no copy); `resolve(doc, "")` is `doc`.

## 2. Patches: `docstore.patch`

Add a module `docstore.patch` with `apply_patch(doc, ops, max_ops=100)` and `json_equal(a, b)`, and an exception `docstore.errors.PatchError` (a direct subclass of `DocstoreError`, not of `PointerError`). `apply_patch` returns the patched document and never modifies `doc` or `ops`; the returned document shares no list or object with `doc` or `ops`.

Every error raised for operation number `i` (counting from **0**) whose `op` member is the valid name `NAME` reads `op <i> (<NAME>): <reason>`; errors raised before the name is known read `op <i>: <reason>`; errors about the patch as a whole have no prefix. A pointer problem's reason is exactly the `PointerError` message of section 1, raised as a `PatchError`.

### 2.1 Checks before anything is applied

7. `ops` must be a list: `PatchError("patch must be a list of operations")`.
8. `len(ops) > max_ops`: `PatchError("too many operations: <len> > <max_ops>")`. An empty list is a valid patch.
9. Then **every** operation is checked, in list order, before any is applied; the first failure is raised. So a malformed operation 5 is reported even when operation 0 would fail when applied. Each operation is checked in this order:
   1. not an object: `op <i>: operation must be an object`
   2. no `op` member: `op <i>: missing 'op'`
   3. `op` is not one of the strings `add`, `remove`, `replace`, `move`, `copy`, `test`: `op <i>: unknown op <repr value>` (the `repr` of the member's value, so `'Add'`, `5`, `None`)
   4. no `path` member: `missing 'path'`; `path` is not a string: `'path' must be a string`; `path` is not a valid pointer: the pointer syntax message of rule 1 or 3
   5. for `move` and `copy` only: the same three checks for `from` (`missing 'from'`, `'from' must be a string`, the syntax message)
   6. for `add`, `replace` and `test` only: no `value` member: `missing 'value'`. A `value` of `null` is present.
   Other members are ignored. Only syntax is checked here; whether a path exists is decided when the operation is applied.

### 2.2 Applying

10. The operations are applied in order to a deep copy of `doc`; each sees the result of the ones before it. If any fails, `apply_patch` raises and nothing is returned.
11. Locating a target walks every token but the last exactly as `resolve` does (rule 5), with the same messages. The last token is then handled by the operation, again with rule 5's messages unless stated otherwise. `-` is accepted only as the last token of an `add` path (or of the target path of `move` and `copy`, which add).
12. `add`: the path `""` replaces the whole document with the value. On an object the member is set (added, or replaced if present). On an array, `-` appends; a conforming index `n` with `n <= len` inserts before position `n` (`n == len` appends); `n > len` is `index <repr t> out of range in <repr path>`. A parent that is not an object or array is `path <repr path> does not exist`.
13. `remove`: the target must exist (rule 5 messages). Removing from an array shifts the later elements left. The path `""` raises `cannot remove the document root`.
14. `replace`: the target must exist (rule 5 messages), then it is replaced. The path `""` replaces the whole document.
15. `move`: first `from` is located; it must exist (messages name the `from` pointer). Then, if `from` and `path` parse to the same token list, the operation does nothing. Otherwise, if `from`'s token list is a proper prefix of `path`'s, it raises `cannot move <repr from> into its own child <repr path>` (so a `from` of `""` cannot move anywhere else). Otherwise the value is removed from `from` and then added at `path` by rule 12, **with `path` located in the document as it is after the removal** (moving `/a/0` to `/a/2` in `[x, y, z]` gives `[y, z, x]`).
16. `copy`: `from` is located and must exist; a deep copy of its value is added at `path` by rule 12.
17. `test`: the target must exist (rule 5 messages; a missing target is that error, not a failed test). If it is not `json_equal` to `value`, it raises `test failed at <repr path>`.
18. Every value placed into the document by `add`, `replace` or `copy` is a deep copy, so later operations, and later changes to `ops`, never change two places at once.

### 2.3 Equality

19. `json_equal(a, b)` is JSON equality: two numbers (`int` or `float`, never `bool`) are equal when their values are equal, so `1` equals `1.0`; booleans equal only booleans of the same value, so `true` never equals `1` and `false` never equals `0`; `null` equals only `null`; strings by content; arrays when they have the same length and are equal element by element in order; objects when they have the same member names and equal values for each, whatever the member order. Values of different kinds are never equal. These rules apply at every depth.

## 3. The store: `Store.get` and `Store.patch`

20. `Store.get(doc_id, pointer=None)`: with no pointer, as today. With a pointer, a deep copy of `resolve(document, pointer)`; pointer problems raise `PointerError`. The id is checked, and the document must exist, before the pointer is looked at.
21. `Config` gains `max_ops` (a positive integer, default `100`), settable in the configuration file like `max_depth`.
22. `Store.patch(doc_id, ops, expected_rev=None, dry_run=False)` returns a `docstore.patch.PatchResult`, a named tuple `(revision, document)`. It checks and acts in this order:
    1. the id (`InvalidId`), then that the document exists (`NotFound`), then `expected_rev` exactly as `put` does (`Conflict`, same message);
    2. `apply_patch(current_document, ops, config.max_ops)` (`PatchError`);
    3. the result must pass the store's document validation; a failure raises `PatchError("result invalid: <validation message>")` (for example `result invalid: document root must be an object` after replacing the root with an array);
    4. without `dry_run`: the document is stored with revision current + 1 and one history entry is appended with action `patch`, that revision, the digest of the new document and the detail `ops=<number of operations>`. The revision grows by one even when the patch changes nothing (only `test` operations, or none).
    5. The result is `PatchResult(new revision, deep copy of the new document)`. With `dry_run=True` nothing is stored and no history is written; the result is the revision the document would get and the document it would have.
    On any error the stored document, its revision and the history are unchanged.

## 4. Canonical diff: `docstore.delta`

Add a module `docstore.delta` with `strict_equal(a, b)` and `diff(a, b)`. Both take JSON values: `dict` with `str` keys, `list`, `str`, `int`, `float`, `bool`, `None`.

23. `strict_equal(a, b)` is type-sensitive equality. The seven kinds null, boolean, integer (`int`, never `bool`), float, string, array and object are distinct, and values of different kinds are never equal: `1`, `1.0` and `true` are pairwise unequal, and so are `0`, `0.0`, `false` and `null`. Two values of the same scalar kind are equal when Python's `==` says so (so `0.0` equals `-0.0`). Arrays are equal when they have the same length and are `strict_equal` element by element in order. Objects are equal when they have the same member names and `strict_equal` values for each, whatever the member order.
24. `diff(a, b)` returns a new list of operations (section 2 syntax) such that `apply_patch(a, diff(a, b))` is `strict_equal` to `b`. The list is **exactly** the one defined by rules 25–29, built by a walk that starts at the root with the pointer `""`. Every operation is a dict with exactly the members shown, and every `value` is a deep copy taken from `b`. Pointers are written with `format_pointer`, and array positions are decimal tokens. Neither argument is modified.
25. At a location where the two values are `strict_equal`, nothing is emitted.
26. Where both are objects, the member names of either are visited in ascending order (Python's `sorted`). For each name, a member only in `a` emits `{"op": "remove", "path": P}`, and a member only in `b` emits `{"op": "add", "path": P, "value": v}`. A member in both continues the walk at `P` (rules 25–29). `P` is the current pointer extended by the name.
27. Where both are arrays (`a` of length `m`, `b` of length `n`), whole elements are compared with `strict_equal`, and the walk never descends into array elements.
    - A **common subsequence** is a pair of index tuples `I = (i1 < i2 < … < ik)` into `a` and `J = (j1 < j2 < … < jk)` into `b` with `a[i_t]` `strict_equal` to `b[j_t]` for every `t`.
    - The **kept pair** is the common subsequence of greatest length `k`. Among those, it is the one whose `I` is lexicographically smallest (compared as Python tuples). Among those with that `I`, it is the one whose `J` is lexicographically smallest. This pair is unique.
    - Emit `{"op": "remove", "path": P + "/" + i}` for every index `i` of `a` not in `I`, from the highest index to the lowest.
    - Then emit `{"op": "add", "path": P + "/" + j, "value": b[j]}` for every index `j` of `b` not in `J`, from the lowest to the highest.
    - For example, `diff({"l": ["x", "y"]}, {"l": ["y", "x"]})` keeps `I = (0,)`, `J = (1,)` and is `[{"op": "remove", "path": "/l/1"}, {"op": "add", "path": "/l/0", "value": "y"}]`.
28. In every other case (different kinds, two different scalars, an array against an object), emit one `{"op": "replace", "path": P, "value": b}`. At the root, `P` is `""`.
29. The tests use arrays of at most 10 elements and values at most 6 levels deep.

## 5. Revisions and revert

30. The store now keeps the document of every revision it writes: those from `create`, `put`, `patch` (not a dry run), `revert` and bundle import. `FileStorage` keeps them under `<root>/versions/<id>/<rev>.json`; the memory storage keeps them in memory. Deleting a document forgets all its revisions. Importing a document from a bundle forgets its earlier revisions and keeps only the imported one.
31. `Store.at(doc_id, rev)` returns a deep copy of the document as it was at revision `rev`. It checks the id (`InvalidId`), then that the document exists (`NotFound`, as `get`). A `rev` the store does not hold for that document (including one that is not an `int`, or is a `bool`) raises `NotFound("no revision <repr rev> of <repr id>")`, for example `no revision 7 of 'doc'`.
32. `Store.revert(doc_id, rev, expected_rev=None)` makes the document equal to its revision `rev` again, as a new revision. Its checks run in this order: id, existence, `expected_rev` (as `put`), and then the revision (rule 31). The operations are `diff(current document, document at rev)`, applied with `apply_patch`; the `max_ops` limit does not apply. The result is validated as in rule 22.3. It is stored as revision current + 1 (also when the diff is empty), and one history entry is appended with action `revert`, that revision, the new digest and the detail `to=<rev> ops=<number of operations>`. It returns `PatchResult(new revision, deep copy of the document)`. On any error nothing changes.

## 6. Command line

33. `docstore get ID POINTER` prints the canonical JSON of the value (one line). `docstore get ID ''` prints the whole document.
34. `docstore patch ID FILE [--rev N] [--dry-run]` reads FILE as JSON (unreadable or invalid JSON is reported as today for `put`) and applies it as a patch with `expected_rev=N`. It prints `rev <n>`; with `--dry-run` it prints the canonical JSON of the document the patch would produce instead, and stores nothing.
35. `docstore diff ID REV` prints, as canonical JSON on one line, `diff(document at REV, current document)`: the operations that turn revision REV into the current document. `docstore revert ID REV [--rev N]` reverts to revision REV with `expected_rev=N` and prints `rev <n>`. A missing revision exits 3 like any `NotFound`.
36. `PointerError` and `PatchError` exit with status 6 and print `docstore: <message>` on standard error, like every other error.
37. `docstore.PointerError`, `docstore.PatchError` and `docstore.PatchResult` are importable from the package.

The existing suite must stay green. Run it with `python3 -m pytest -q tests`, and add tests of your own.
