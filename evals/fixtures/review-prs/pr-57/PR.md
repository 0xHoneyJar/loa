# fix(npm): reject symlinked package materialization dirs

## Summary

- reject symlinked package materialization destinations
- apply the check to both hard-link and copy paths
- cover both helpers with in-memory filesystem regressions

## Details

Package initialization previously treated an existing symlinked destination
as a directory. Creating the destination and then hard-linking or copying
package files could therefore write through that redirected path.

Materialization now checks each destination directory before and after
creation using symlink-aware metadata. Existing ordinary directories continue
to work as before, while a symlinked destination returns an ordinary
filesystem error.

## Validation

- `./tools/format.js --check`
- `cargo test -p deno_npm_cache hard_link_dir_recursive -- --nocapture`
- `cargo test -p deno_npm_installer copy_dir_recursive -- --nocapture`

AI assistance was used to help implement and test this change.
