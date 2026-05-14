# cycle-109 Sprint 3 T3.7 — mock-mode fixtures (cheval-shape)

Per-mode mock fixtures consumed by `model-adapter.sh` when
`FLATLINE_MOCK_MODE=true`. T3.7 migrated mock-mode from the legacy
adapter's `get_mock_response` synthetic-content generator (deleted) to
cheval's `--mock-fixture-dir` substrate.

## Layout

  ```
  mock-mode/
    review/response.json     # flatline-reviewer canonical mock content
    skeptic/response.json    # flatline-skeptic canonical mock content
    score/response.json      # flatline-scorer canonical mock content
    dissent/response.json    # flatline-dissenter canonical mock content
  ```

## Fixture shape

cheval's `--mock-fixture-dir` (cheval.py:617) loads
`<dir>/<provider>__<sanitized_model>.json` first, falling back to
`<dir>/response.json`. We use `response.json` so any model alias gets
the same per-mode canonical content.

Required schema (per cheval `_load_mock_fixture_response`):

  ```json
  {
    "content": "<JSON-encoded model output string>",
    "model": "<string>",
    "provider": "<string>",
    "usage": { "input_tokens": <int>, "output_tokens": <int> },
    "latency_ms": <int>
  }
  ```

Content equivalence with the deleted legacy synthetic outputs is
documented in `grimoires/loa/cycles/cycle-109-substrate-hardening/baselines/legacy-final-baseline.json`.

## Override

Tests can override the default base path via the `FLATLINE_MOCK_DIR`
env var; `model-adapter.sh` then routes to
`$FLATLINE_MOCK_DIR/$mode/response.json` (or `$FLATLINE_MOCK_DIR` flat
if no `$mode` subdir exists, for backward compat).

## Why fixture-dir not synthetic generation

The pre-T3.7 legacy `get_mock_response` generated synthetic content via
case-statement heredocs. cheval's `--mock-fixture-dir` is the canonical
mock substrate; routing mock-mode through it means:

  - Tests exercise the same dispatch path as live runs (just with
    pre-recorded fixtures instead of API calls).
  - No second mock-content surface to maintain.
  - Test infrastructure (cycle-099 sprint-1C curl-mock harness) and
    cheval's fixture-dir are the only two mock paths in the substrate.
