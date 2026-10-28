# ESO pass 17 — cheval startup: lazy provider adapters

**Change (revised per orchestrator redirect):** `.claude/adapters/loa_cheval/providers/__init__.py`. The ten adapter modules no longer import at package import. There is NO dict subclass. A private `_ADAPTER_TYPES` (type -> class name, same keys/order) drives `get_adapter` and `adapter_class_for_type`, which import only the one adapter needed. `_ADAPTER_REGISTRY` is built on first touch by module `__getattr__` as a plain `dict` of type -> class (imports all ten, old contents and key order), cached in globals. Adapter class names resolve lazily the same way, through `_adapter_class`, which prefers the globals-cached class so every path returns the same class object. The unknown-type error uses `list(_ADAPTER_TYPES)`, so "Supported: [...]" is byte-identical. `cli_adapter_types()` uses the full registry. `__all__` unchanged.

## Matrix
Impact 3 (15 ms of import, ~7-12% of a cheval spawn) x Confidence 4 x Effort 2 = 6.0 (>= 2.0).

## Hotspot (before)
`-X importtime` on `--help`: `loa_cheval.providers` 18.9 ms cum of ~120 ms wall (~16%); 20.1 ms on `--validate-bindings`. After: 5.1 ms (base + types only). `loa_cheval.config.loader`/yaml (14 ms) is NOT deferrable: every real command loads config through yaml, and the pure-Python yaml parse (~125 ms per `_load_yaml` pair, cProfile) dominates real commands. That is a separate lever (C loader), not taken because error text/behaviour could differ.

## Numbers (hyperfine -N, warmup 5, 40 runs, same-session head-to-head, system python3)
| command | old (HEAD) | new |
|---|---|---|
| --help | 123.9 ± 4.1 ms | 115.2 ± 3.5 ms (-7.0%) |
Earlier separate runs: --validate-bindings 205.1 -> 199-210 ms (noise-level); --print-effective-config 208.0 -> 198.4 ms. importtime of `loa_cheval.providers`: 20.1 -> 5.8 ms. A real invoke still imports the adapter it uses; yaml parsing dominates config commands.

## Isomorphism proof
- Ordering preserved: yes. Registry key order identical (golden reg.out compares keys and `items()` order).
- Tie-breaking unchanged: yes (no sorting/selection touched).
- Floating-point: N/A. RNG/hash seeds: N/A (PYTHONHASHSEED=0 used).
- Trust-boundary sanitisation: unchanged, no sanitiser code touched.
- Error/degraded paths: unchanged. Unknown provider type still raises ConfigError with same "Supported: [...]" text (reg.out); yaml-hidden shim run (`--validate-bindings`, `--help`) byte-identical rc/stdout/stderr (yaml is not touched; the loader falls back to yq as before).
- Public names: every `from loa_cheval.providers import <Adapter>` and `import *` (via `__all__`) still works, including `_ADAPTER_REGISTRY`, `get_adapter`, `adapter_class_for_type`, `cli_adapter_types`. `loa_cheval` and `loa_cheval.config` namespaces unchanged (dir() compared in reg.out).
- Registry is now a plain dict: `type(r) is dict`, `dict(r) == r`, `{**r} == r`, key order and class identities identical to HEAD (reg2.out). `get_adapter` no longer reads `_ADAPTER_REGISTRY`, so patching that dict would not affect it; no test or script does (grep).
- A first revision failed `test_get_adapter_google` in the full suite (a test evicts adapter modules from sys.modules, so re-importing gave a different class object); fixed by `_adapter_class` preferring the globals-cached class.
- Registration side effects: none exist (adapters do not self-register; registry is a static table), so lazy loading cannot reorder registration.
- Golden: 13 command captures (help, bogus flag, no args, validate-bindings, print-effective-config, reset-breaker, dry-run text and json, bad model, poll, cancel, yaml-hidden x2) plus registry/public-name dump; old (git archive HEAD) vs live: all stdout/stderr/rc identical (path-normalised), all files identical across 13 captures + reg.out + reg2.out.

## Tests
`.claude/adapters/tests` live tree: 3279 passed, 6 skipped, 2 failed (test_claude_headless_adapter test_minimal_command and test_complete_round_trip). Both fail identically on the HEAD tree: the host's `claude` resolves to `~/.local/bin/claude-fallback` — environmental, unrelated. Full old-tree run not possible from /tmp (a test needs repo-root files); the failing file was run on both trees (same 2 failures).

## Checked, found already optimal / left alone
- `providers.base` (5 ms: inspect, dataclasses) is needed by cheval itself, stays eager.
- `yaml` import (12 ms) is used by every non-help command; deferring it only helps `--help`, and `loader` uses it at class-definition scope inside functions with an `except ImportError` yq fallback whose timing I did not want to move.
- `argparse`/`logging`/`dataclasses` stdlib imports are required by cheval.py top level.
- `cli_adapter_types()` still loads all adapters (it must read each class's `auth_type`), but it is only called on kind:cli routing.

## Not fixed (out of scope)
- Pure-Python `yaml.safe_load` of model-config.yaml/.loa.config.yaml is ~60% of real command wall time; `yaml.CSafeLoader` would be the lever but may change error messages. Suggest as a later pass.
- Two pre-existing test failures above.
