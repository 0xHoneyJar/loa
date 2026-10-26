# fix `dc-glob` `ls **` and `ls **/*/*/*` among other things

## Description

This PR fixes recursive glob semantics in the experimental **dc-glob** backend (`--experimental-options=[dc-glob]`), addressing the behaviors reported in #18600 and follow-up review gaps for prefixed trailing `**` (`dir/**`), exclude/start-dir emission, and nested terminal `**` in alternatives.

dc-glob is aligned with [rust-lang/glob `Pattern`](https://docs.rs/glob/latest/glob/struct.Pattern.html) (the same model `nu-glob` documents), while remaining a **superset** for extras such as `{a,b}`, repeats, `--ignore-case`, excludes, and depth.

### Problems fixed

1. **Bare `**` expanded to nothing**  
   Users often expected `**` to work like recursive listing. dc-glob previously returned no paths because the recurse program could not match a final path component (it only matched `(component/)*`) and the walker never emitted the start directory.

2. **`**/*/*/*` behaved like `**/*`**  
   Extra `/*` segments did not enforce a minimum depth. Root cause: an empty `*` plus a too-permissive `Separator` instruction could ÔÇ£eatÔÇØ path segments without binding a real component (`*/*` incorrectly matched a single-component path).

3. **`**/*` and the topmost directory**  
   dc-glob already omitted the start directory for `**/*`. That matches rust-lang/glob expansion and the issue OPÔÇÖs expected table. This PR **keeps** that behavior and locks it in with tests (legacy `nu-glob` still includes the start dir for `**/*` ÔÇö a known dual-backend difference while the option is experimental).

4. **Prefixed trailing `**` (`foo/**`) never emitted `foo`**  
   The walker only probed the empty relative path for trailing recursive patterns, while `traversal_start_dir` advances into literal prefixes. Combined with matcher `Separator`-at-EOF rules needed for #18600, path `foo` did not complete-match `foo/**`. Fixed by omitting the separator before a terminal recurse, a `ComponentBoundary` instruction so `foo/**` matches `foo` but not `foobar`, and probing/emitting the real traversal-start relative path (e.g. `foo`).

5. **Trailing-`**` start emit skipped excludes**  
   The special start-dir emission path now applies the same exclude filters (and directory-only rules) as normal complete-match emission.

6. **Nested terminal `**` in `{ÔÇª}` / repeats**  
   Compilation now uses the same node-index lookahead inside alternatives and repeats, so `{**}` / `foo/{**}` get a terminal recurse gadget. `trailing_recursive` is set only when every alternative choice is trailing-recursive (so `{**,README.md}` does not force directory-only expansion).

## User-facing changes (Release notes)

### Fixed recursive glob behavior in the experimental `dc-glob` backend

With `--experimental-options=[dc-glob]` (or the equivalent config):

- Bare `**` now expands to directories at any depth (including the current directory), not an empty list. It does **not** list regular files; use `**/*` for files and directories under the start path.
- Prefixed trailing patterns like `foo/**` include the prefix directory itself and nested directories only (not files).
- Patterns like `**/*/*` and `**/*/*/*` again respect minimum depth (extra `/*` segments are no longer ignored).
- `**/*` continues to list contents **under** the start directory and does **not** include the start directory itself (differs from legacy `nu-glob`, matches common `glob` crate behavior).


### Examples 

```nushell
# enable dc-glob for the session
$env.NU_EXPERIMENTAL_OPTIONS = [dc-glob]
# or: nu --experimental-options=[dc-glob]

mkdir 0/1/2/3
touch 0/1/2/3/file.txt
cd 0

glob '**'
# start dir + nested directories only (no file.txt)

glob '**/*'
# everything under start ÔÇö not the start dir itself

glob '**/*/*'
# paths at least 2 components deep

glob '**/*/*/*'
# paths at least 3 components deep (e.g. 1/2/3 and 1/2/3/file.txt)

mkdir foo/bar
touch foo/sibling.txt
glob 'foo/**'
# foo and foo/bar only (not sibling.txt)
```

Matcher-level checks (debug flags require dc-glob):

```nushell
glob --dbg-matches '**/*/*' '1'       # false
glob --dbg-matches '**/*/*' '1/2'     # true
glob --dbg-matches '**/*/*/*' '1/2'   # false
glob --dbg-matches '**/*/*/*' '1/2/3' # true
glob --dbg-matches '**/foo' 'foo'     # true
glob --dbg-matches 'foo/**' 'foo'     # true
glob --dbg-matches 'foo/**' 'foo/bar' # true
glob --dbg-matches 'foo/**' 'foobar'  # false
glob --dbg-matches '*/*' '1'          # false
```
## Additional notes

closes https://github.com/nushell/nushell/issues/18600
