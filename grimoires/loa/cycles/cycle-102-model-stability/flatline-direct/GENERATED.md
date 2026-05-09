# flatline-direct/ — generated artifacts

Per-model verdicts captured during the cycle-102 PRD/SDD Flatline review pass.

## What's here

| File | Source | Schema | Canonical? |
|---|---|---|---|
| `<model>-<mode>.json` | `model-adapter` stdout | informal: model output, OR `{status: "degraded", ...}` marker for empty-response runs | yes — these are the council voices |
| `<model>-<mode>.stderr` | `model-adapter` stderr | adapter status lines only (model id, provider, mode, phase, input path, attempt count, "Empty response content" / "Connection lost") | no — debug aid |

The stderr files exist as forensic evidence of the silent-degradation events that vision-019 axiom 3 names — when the orchestrator failed to surface that 4 of its 6 voices returned empty/connection-lost. The PRD body cites this directly.

## Scrub policy

Stderr files in this directory MUST contain only:

- Adapter `[model-adapter]` / `[cheval]` status prefixes
- Model id, provider, mode, phase, and input file path (already public)
- API attempt counters (`attempt N/M`)
- Failure mode markers: `Empty response content`, `Connection lost`, `RemoteProtocolError`
- Issue cross-references (e.g., `See issue #774`)
- Exit code line (e.g., `ERROR: API call failed with exit code 5`)

Stderr files MUST NOT contain:

- API keys, bearer tokens, x-api-key values
- Request bodies (the prompts being reviewed)
- Response bodies (the model output content)
- Stack traces with absolute paths outside `grimoires/`
- Environment variable values
- User identifiers

The audit was performed at commit `f35642ce` on PR #795. All current `*.stderr` files conform.

## Regeneration

These artifacts were captured by the manual Flatline dogfood pass during cycle-102 kickoff. Re-running:

```bash
# Per-voice adapter call (each voice runs independently):
.claude/scripts/model-adapter.sh \
  --model <opus|gpt-5.5-pro|gemini-3.1-pro> \
  --mode <review|skeptic> \
  --phase <prd|sdd> \
  --input grimoires/loa/cycles/cycle-102-model-stability/<phase>.md \
  > <model>-<mode>.json 2> <model>-<mode>.stderr
```

Re-running will produce different content (model nondeterminism) and overwrite both files. The committed snapshot is the v1 baseline; subsequent passes belong in versioned subdirectories (`flatline-direct-v2/` etc.) so the council-convergence trail remains auditable.

## Provenance

Generated during cycle-102 kickoff (commit `2a93c0dd`, 2026-05-08). The empty-content `*.json` files were replaced with structured degradation markers in commit `f35642ce` so the CI Validate Framework Files job passes — the markers preserve the silent-degradation narrative the PRD body relies on.
