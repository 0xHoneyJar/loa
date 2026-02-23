# Declarative Execution Router — Design Notes

## Problem Statement

The current `route_review()` function uses a 56-line imperative if/else cascade
to select between three API backends: hounfour, codex, and curl. Adding a new
backend requires modifying deeply nested conditional logic.

## Design Goals

1. **Declarative configuration**: Routes defined in YAML, not code
2. **Zero behavioral change**: Existing users see identical routing
3. **Extensible**: New backends added without code changes
4. **Observable**: Route decisions logged for debugging
5. **Safe**: Fail-closed for custom routes, fail-open for defaults

## Architecture

### Parallel Arrays (bash has no nested data types)

| Array | Purpose |
|-------|---------|
| `_RT_BACKENDS` | Backend name for each route |
| `_RT_CONDITIONS` | Comma-separated condition names |
| `_RT_CAPABILITIES` | Required capabilities |
| `_RT_FAIL_MODES` | `fallthrough` or `hard_fail` |
| `_RT_TIMEOUTS` | Per-route timeout in seconds |
| `_RT_RETRIES` | Per-route retry count |

### Condition Registry

Maps condition names to evaluator functions:

```bash
_CONDITION_REGISTRY["has_api_key"]=_cond_has_api_key
_CONDITION_REGISTRY["model_available"]=_cond_model_available
```

### Backend Registry

Maps backend names to handler functions:

```bash
_BACKEND_REGISTRY["hounfour"]=_backend_hounfour
_BACKEND_REGISTRY["codex"]=_backend_codex
_BACKEND_REGISTRY["curl"]=_backend_curl
```

## Migration Strategy

- `LOA_LEGACY_ROUTER=1` reverts to imperative code path
- Default route table matches existing cascade exactly
- Metrics compare old vs new routing decisions
