# Task: version ranges resolve to the wrong versions

`semrange` (under `src/semrange/`) parses semantic versions (Semantic Versioning 2.0.0) and npm-style range expressions, and picks, sorts and increments versions. A dependency resolver, a lock-file checker and a release tool are built on it. The public API, all importable from `semrange`:

- `parse(text) -> Version`, `valid(text) -> str | None`; a `Version` has `major`, `minor`, `patch` (ints), `prerelease` and `build` (tuples of identifier strings), `str()`, and the comparison operators `< <= > >= == !=` and `hash()`.
- `compare(a, b) -> -1 | 0 | 1` and `sort_versions(versions, reverse=False) -> list[Version]` (arguments are strings or `Version` objects).
- `Range(text)` with `str(range)` and `range.test(version)`; `satisfies(version, range_text) -> bool`.
- `max_satisfying(versions, range_text)`, `min_satisfying(versions, range_text)`, `filter_satisfying(versions, range_text)`.
- `VersionIndex(versions)` with `index.max_satisfying(range)`, `index.min_satisfying(range)`, `index.filter_satisfying(range)` and `len(index)`: a version list prepared once for many queries.
- `inc(version, kind, preid=None) -> str`.
- `resolve`, `format_report`, `parse_lock`, `dump_lock`, `check_lock` (built on the functions above; their own formats are documented in their modules and are not in question).
- Errors: `VersionError` (a `ValueError`) and its subclasses `InvalidVersion`, `InvalidRange`, `InvalidIncrement`.

**Bug (observed):**
- The lock checker accepts `left-pad = 0.0.9` against the requirement `^0.0.3`, and accepts `widget = 1.2.9` against `>1.2`.
- Given `1.0.0-alpha.2` and `1.0.0-alpha.10`, the resolver picks `1.0.0-alpha.2` for `>=1.0.0-alpha`.
- A requirement written `>= 1.2.3` (a space after the operator) is refused as an invalid range, and so is `1.x ||`.
- `inc("1.2.3-beta.1", "patch")` returns `1.2.4`.
- Sorting newest-first swaps two builds of the same version, and `parse("1.0.0-01")` is accepted.
- With two builds of the newest matching version on offer, the resolver reports the one listed last.

These are the reported symptoms. The implementation deviates from the rules below in more places than these; it must conform to every rule in **Expected**, not only to the symptoms.

**Expected:**

*Versions*
- V1. A version is `MAJOR.MINOR.PATCH`, optionally followed by `-PRERELEASE`, optionally followed by `+BUILD`. Surrounding whitespace (what `str.strip()` removes) is ignored, and one leading lower-case `v` is accepted and dropped. Nothing else may precede the number (`vv1.2.3`, `V1.2.3`, `=1.2.3` and `v 1.2.3` are invalid).
- V2. MAJOR, MINOR and PATCH are non-negative decimal integers written in ASCII digits without a leading zero (`0` is fine, `01` is not) and without a sign.
- V3. PRERELEASE and BUILD are dot-separated lists of identifiers. An identifier is a non-empty run of ASCII letters, digits and hyphens. An identifier made only of digits is *numeric*; in PRERELEASE a numeric identifier must not have a leading zero (`1.0.0-01` is invalid, `1.0.0-0a` is valid). BUILD identifiers may have leading zeros (`1.0.0+001`). An empty identifier anywhere is invalid (`1.0.0-a..b`, `1.0.0-`, `1.0.0+a.`, `1.0.0+`).
- V4. An invalid version raises `InvalidVersion` with the message `invalid version: ` followed by `repr()` of the argument as given (unstripped), e.g. `invalid version: ' 1.2 '`.
- V5. `str(version)` is the canonical form `M.m.p`, then `-` and the prerelease identifiers joined by `.` if there are any, then `+` and the build identifiers if there are any. `valid(text)` returns that string, or `None` for an invalid version.

*Precedence*
- P1. Versions compare by MAJOR, then MINOR, then PATCH, numerically.
- P2. With equal MAJOR.MINOR.PATCH, a version with a prerelease ranks lower than one without.
- P3. Two prereleases compare identifier by identifier from the left: two numeric identifiers compare numerically; a numeric identifier ranks lower than a non-numeric one; two non-numeric identifiers compare by ASCII order (as Python compares the strings). If one list is a prefix of the other, the longer list ranks higher.
- P4. Build metadata takes no part in precedence: `compare` returns 0, `==` is true and `hash()` is equal for versions that differ only in BUILD.
- P5. `sort_versions` returns `Version` objects in ascending precedence, or descending with `reverse=True`. The sort is stable in both directions: versions of equal precedence keep their input order.

*Ranges*
- R1. A range is one or more comparator sets separated by `||` (with or without whitespace around it). A version satisfies the range when it satisfies at least one set. A set that is empty or only whitespace means `*`.
- R2. A set is either a hyphen range `A - B` (the `-` a separate word between two partial versions, and nothing else in the set) or one or more terms separated by whitespace (spaces or tabs). A version satisfies a set when it satisfies every comparator the set's terms produce (R4–R7) and the prerelease rule R8.
- R3. A term is an optional operator `<`, `<=`, `>`, `>=`, `=`, `~` or `^` followed by a partial version; no operator means `=`. Whitespace may separate an operator from its partial version (`>= 1.2.3`). An operator with no partial version after it, or followed by another operator, is invalid.
- R4. A partial version is `X`, `X.Y` or `X.Y.Z`, optionally with one leading `v`. Each component is a number (as V2) or a wildcard `x`, `X` or `*`; once a component is a wildcard every later one must be a wildcard too (`1.x.3` and `x.1` are invalid); missing components count as wildcards. A prerelease (`-…`, as V3) and a build (`+…`, as V3) are allowed only after a full `X.Y.Z` without wildcards; a build in a range is accepted and dropped.
- R5. Each term becomes one or more primitive comparators (an operator in `< <= > >= =` and a full version). Below, `-0` is the lowest prerelease, so `<2.0.0-0` excludes `2.0.0` and every prerelease of it.
  - A full version with `<`, `<=`, `>`, `>=` or `=` stays as it is.
  - All wildcards (`*`, `x`, `X`, also `x.x`): with `=`, `>=` or `<=` it is `>=0.0.0`; with `<` or `>` it is `<0.0.0-0` (matches nothing).
  - `X` (major only): `=X` is `>=X.0.0 <(X+1).0.0-0`; `>X` is `>=(X+1).0.0`; `>=X` is `>=X.0.0`; `<X` is `<X.0.0-0`; `<=X` is `<(X+1).0.0-0`.
  - `X.Y`: `=X.Y` is `>=X.Y.0 <X.(Y+1).0-0`; `>X.Y` is `>=X.(Y+1).0`; `>=X.Y` is `>=X.Y.0`; `<X.Y` is `<X.Y.0-0`; `<=X.Y` is `<X.(Y+1).0-0`.
- R6. Tilde: `~X.Y.Z[-pre]` is `>=X.Y.Z[-pre] <X.(Y+1).0-0`; `~X.Y` is `>=X.Y.0 <X.(Y+1).0-0`; `~X` is `>=X.0.0 <(X+1).0.0-0`; `~*` is `>=0.0.0`.
  Caret: the lower bound is `>=X.Y.Z[-pre]` with missing components as 0; the upper bound is `<(X+1).0.0-0` when X > 0 or only X is given; otherwise (X = 0) `<0.(Y+1).0-0` when Y > 0 or Z is missing; otherwise (`^0.0.Z`) `<0.0.(Z+1)-0`. `^*` is `>=0.0.0`. So `^0.0.3` is `>=0.0.3 <0.0.4-0`, `^0.0` is `>=0.0.0 <0.1.0-0` and `^0` is `>=0.0.0 <1.0.0-0`.
- R7. Hyphen `A - B`: the lower bound is `>=A` with missing components as 0 (`>=0.0.0` when A is all wildcards, keeping A's prerelease when A is full); the upper bound is `<=B` when B is full, `<X.(Y+1).0-0` when B is `X.Y`, `<(X+1).0.0-0` when B is `X`, and there is no upper bound when B is all wildcards.
- R8. Prerelease rule: a version with a prerelease satisfies a set only if, besides satisfying all its comparators, at least one comparator *of that same set* has a version with a prerelease and the same MAJOR.MINOR.PATCH. So `*` and `1.x` match no prerelease, `>=1.2.3-alpha` matches `1.2.3-beta` but not `1.2.4-alpha`, and a comparator in another `||` set does not count.
- R9. `str(range)` is canonical: the sets joined by ` || `, each set's comparators in term order joined by one space, each comparator written as its operator followed by the canonical version (V5), except that `=` is not written. Every comparator R5–R7 produce is listed (none is merged or dropped): `>1.2 <=2` is `>=1.3.0 <3.0.0-0`, `*` is `>=0.0.0`, `1.x ||` is `>=1.0.0 <2.0.0-0 || >=0.0.0`. An invalid range raises `InvalidRange` with the message `invalid range: ` followed by `repr()` of the whole range text.

*Selection*
- S1. `satisfies(version, range_text)` raises `InvalidVersion` for an invalid version and `InvalidRange` for an invalid range.
- S2. `max_satisfying` returns the item of highest precedence that satisfies the range, `min_satisfying` the item of lowest precedence; among items of equal precedence (differing only in BUILD) the first in input order wins. They return the item exactly as given (`"v1.2.3"` stays `"v1.2.3"`) and `None` when nothing satisfies.
- S3. `filter_satisfying` returns the satisfying items in input order, as given.
- S4. In all three, items that are not valid versions are skipped (an invalid range still raises).

*Index*
- N1. `VersionIndex(versions)` reads the list (any iterable) once at construction; later changes to the list do not affect the index. `index.max_satisfying(range)`, `index.min_satisfying(range)` and `index.filter_satisfying(range)` (the range as text or a `Range`) return exactly what S2–S4 return for that list and that range, for any number and order of queries on the same index; an invalid range raises `InvalidRange`. `len(index)` is the number of valid entries of the list. The list functions of S2–S4 and `resolve` answer through an index.
- N2. After construction a `max_satisfying` or `min_satisfying` query must not examine every entry: over 50,000 versions an index answers 1,000 such queries on narrow ranges (each matching few or none of the entries) in under 5 seconds in total. Building the index may take time proportional to sorting the list.

*Increments*
- I1. `inc` parses the version first (`InvalidVersion`), then checks the kind, then the preid. A kind outside `major`, `minor`, `patch`, `premajor`, `preminor`, `prepatch`, `prerelease` raises `InvalidIncrement` with `unknown increment: ` and `repr(kind)`. A preid that is not `None` must be a single non-numeric identifier (V3), otherwise `InvalidIncrement` with `invalid preid: ` and `repr(preid)`. The result is the canonical string; build metadata is always dropped; a preid is ignored by `major`, `minor` and `patch`.
- I2. `major`: `X.0.0-pre` becomes `X.0.0`; otherwise `(X+1).0.0`. `minor`: `X.Y.0-pre` becomes `X.Y.0`; otherwise `X.(Y+1).0`. `patch`: `X.Y.Z-pre` becomes `X.Y.Z`; otherwise `X.Y.(Z+1)`.
- I3. `premajor`, `preminor` and `prepatch` increment like `major`, `minor`, `patch` on a release (`(X+1).0.0`, `X.(Y+1).0`, `X.Y.(Z+1)`, whether or not the version has a prerelease) and add the prerelease `0`, or `<preid>.0` with a preid.
- I4. `prerelease`: a release `X.Y.Z` becomes `X.Y.(Z+1)-0` (or `-<preid>.0`). A prerelease with a preid that differs from its first identifier becomes `X.Y.Z-<preid>.0`. Otherwise the right-most numeric identifier is incremented (`alpha.1.beta` becomes `alpha.2.beta`), and if there is none, `0` is appended (`alpha` becomes `alpha.0`).

Fix the bug in place; keep the public API and the existing passing behaviour. Run the suite with `python3 -m pytest -q tests`.
