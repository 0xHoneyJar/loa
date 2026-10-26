# fix(check): type-check local wasm imports

Native `deno check` materialized types for remote (`http(s):`) `.wasm`
imports but not local ones, so `import { x } from "./foo.wasm"` produced a
spurious `TS2307 Cannot find module` instead of surfacing the wasm module's
typed exports.

`deno sync-types` now walks the module graph for local (`file://`) wasm
modules and writes their generated declarations under `.deno/wasm/<rel>`.
Because tsgo's `paths` never matches a relative specifier, the generated
tsconfig overlays `.deno/wasm` onto the project root via `rootDirs` together
with `allowArbitraryExtensions`, so tsc resolves `./foo.wasm` to the
declaration. This is gated on the project actually importing local wasm, so
other projects are unaffected.

This re-enables `tests/specs/check/wasm_multi_value`, restored to assert the
real multi-value type error rather than the `TS2307` it had been changed to
document while ignored.
