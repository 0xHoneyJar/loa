# Transition Requests

A transition request is the only way the harness worldline advances. The agent writes the request; the Stop hook validates it.

## Location

```text
.loa-harness/runtime/transition.request.json
```

## Schema

```json
{
  "schema_version": "loa-harness.transition-request/v0.1",
  "from": "PLANNING",
  "to": "ARCHITECTING",
  "actor": "claude-cli",
  "reason": "PRD exists and is ready for architecture.",
  "evidence": [
    {
      "path": "grimoires/loa/prd.md",
      "min_bytes": 500,
      "contains_any": ["Acceptance", "Requirements", "PRD"]
    }
  ]
}
```

`evidence` is optional. If omitted, the harness uses `default_transition_evidence` from `.loa-harness/policy.json` for the `FROM->TO` transition.

## Evidence fields

```text
path            Repository-relative path to a file.
min_bytes       Minimum UTF-8 byte size.
contains_any    At least one marker string must exist.
contains_all    Every marker string must exist.
optional        Missing optional evidence does not block.
```

## CLI helper

```bash
python3 .loa-harness/bin/loa_harness.py request-transition \
  --to ARCHITECTING \
  --reason "PRD accepted" \
  --evidence grimoires/loa/prd.md:500:Acceptance
```

Then end the turn. The Stop hook validates and advances.

## Failure behavior

If validation fails, the Stop hook returns:

```json
{"decision":"block","reason":"..."}
```

Claude Code should feed the reason back to the model so it can produce missing evidence or correct the request.

## Block-loop guard

Claude Code includes `stop_hook_active` when a Stop hook has already blocked and the model is trying to continue. The reference implementation allows the stop when `stop_hook_active=true` to avoid repeated block loops. For stricter deployments, remove that guard and raise the runtime’s Stop hook cap deliberately.
