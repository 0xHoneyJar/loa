# Sprint 4A — Engineer Feedback

**Verdict**: CHANGES REQUIRED

**Reviewer**: Senior tech lead (autonomous review pass, session 10)
**Adversarial cross-model dissenter**: claude-opus-4-7 via
`adversarial-review.sh --type review` (cost: $0.1364, 31s wall-clock).
The dissenter call succeeded cleanly on the ~120K-token sprint diff —
organic AC-4A.7 partial validation: the new streaming transport was
dogfooded as part of its own review pass and survived without
`PROVIDER_DISCONNECT` events.

## Overall Assessment

The Sprint 4A implementation is **substantially correct**. All 9 ACs
are documented in the reviewer.md with file:line evidence; all 887
cheval tests pass; live integration smokes against all three providers
confirm streaming works end-to-end at sprint-typical scale. The
streaming transport is functionally complete.

**One blocking issue must be fixed before approval**: an inconsistency
between the 3 adapter kill-switch checks and the audit-payload emit
helper that causes the audit chain to record a *wrong* `streaming`
value under specific (operator-realistic) configurations.

Adversarial pass also surfaced 2 pre-existing concerns (DISS-002 +
DISS-003) and 2 advisory observations (DISS-004 + DISS-005). These are
**non-blocking for Sprint 4A** — documented below for transparency but
do not require fix in this cycle.

## Critical Issues (BLOCKING)

### DISS-001 — `LOA_CHEVAL_DISABLE_STREAMING` truthy-value mismatch causes audit-chain lie

**Severity**: BLOCKING (spec-violation)

**Anchors**:
- `.claude/adapters/loa_cheval/providers/anthropic_adapter.py:93`
- `.claude/adapters/loa_cheval/providers/openai_adapter.py:128`
- `.claude/adapters/loa_cheval/providers/google_adapter.py:324`
- `.claude/adapters/loa_cheval/audit/modelinv.py:227` (`_streaming_active`)

**The issue**:

All three adapters perform a **strict, case-sensitive** check:
```python
streaming_disabled = os.environ.get("LOA_CHEVAL_DISABLE_STREAMING") == "1"
```

The MODELINV audit emit helper performs a **case-insensitive, multi-value** check:
```python
return os.environ.get("LOA_CHEVAL_DISABLE_STREAMING", "").lower() not in (
    "1", "true", "yes",
)
```

When an operator sets `LOA_CHEVAL_DISABLE_STREAMING=true` (or `TRUE`,
or `yes`, or `Yes`, etc.):
- Adapters see the value, `!= "1"`, so they take the **streaming** path
- Audit-emit helper sees the value, matches in the truthy tuple, so it
  records **`streaming: false`** on the payload

The audit chain claims `streaming=false` while the call actually used
streaming. This is exactly the silent-degradation pattern vision-019 M1
was built to detect, manifesting in the substrate that audits it.

**Why it slipped past tests**: the existing test surface
(`test_modelinv_streaming_field.py`) checks the modelinv helper in
isolation with parametrized truthy values, and the adapter tests check
adapter behavior with `LOA_CHEVAL_DISABLE_STREAMING=1` (the strict
value). No test exercises the **interaction** of an alternative truthy
value at the adapter layer + the audit layer in the same process.

**Required fix**:

1. Extract kill-switch detection to **one canonical helper** —
   recommend `loa_cheval/providers/base.py::_streaming_disabled() -> bool`
   matching the modelinv helper's semantics (case-insensitive,
   multi-value). The same env-var must drive the same boolean
   everywhere.
2. Update all 3 adapters to import and call the helper instead of the
   inline `== "1"` check.
3. Update `modelinv.py::_streaming_active()` to call the same helper
   (or delete the helper and import from base directly).
4. Add a regression test in `test_modelinv_streaming_field.py` (or new
   file `test_kill_switch_consistency.py`) that exercises adapter-call
   + audit-emit in the **same** test with `LOA_CHEVAL_DISABLE_STREAMING=true`
   (lowercase). Assert: adapter routes to legacy (mock-intercepted),
   AND audit payload records `streaming: false`. Both should agree.

This is a small surgical fix (~30 lines) but **blocks approval** because
the audit-chain integrity is load-bearing for vision-019 M1.

## Adversarial Analysis

### Concerns Identified

1. **DISS-001** (BLOCKING): truthy-value mismatch — fix path above.
2. **DISS-002** (raised by dissenter as BLOCKING; reviewer downgrades
   to MEDIUM, non-blocking for Sprint 4A): error-body API-key echo.
   When a 4xx response body contains an echoed API key (Anthropic
   occasionally does this on authentication errors), the raw body
   flows into `InvalidInputError.args` → cheval stderr → operator
   visible, bypassing MODELINV redaction (the exception is raised
   before `emit_model_invoke_complete` fires). **Anchor**:
   `anthropic_adapter.py:_complete_streaming` (lines 120-137).
   **Justification for non-blocking**: this pattern exists IDENTICALLY
   in the pre-Sprint-4A `_complete_nonstreaming` path (lines 178-188).
   Sprint 4A did not introduce or worsen the surface. The fix —
   redacting error-body strings before exception construction —
   belongs in a follow-up sprint dedicated to error-path redaction
   hardening. Filing as carry-forward.
3. **DISS-003** (raised by dissenter as BLOCKING; reviewer downgrades
   to MEDIUM, out-of-scope): `redact_payload_strings` walks nested
   dicts but only checks field names at the immediate parent level. A
   payload with `original_exception` as a nested dict could leak
   secrets in the inner values. **Anchor**:
   `modelinv.py:redact_payload_strings`. **Justification for
   out-of-scope**: pre-existing Sprint 1D design choice. The schema
   constrains `original_exception` to a string, so the test-mode
   boundary protects normal usage. Sprint 4A did not modify the
   redactor. Filing against the redactor module as separate tech debt.
4. **DISS-004** (ADVISORY): `_GATE_BEARER` regex misses some token
   shapes (`bearer:` without space, percent-encoded). Pre-existing
   redactor coverage gap. Out of scope.
5. **DISS-005** (ADVISORY): possible resource leak on early-exit
   stream. Reviewer disposition: **overstated** — httpx's
   `stream_cm.__exit__()` (called in the `http_post_stream` finally
   block at `base.py:330`) closes the underlying connection regardless
   of whether `iter_bytes()` was fully drained, per httpx docs. The
   urllib fallback path closes via `handle.close()` in the iterator's
   own finally block. No additional fix needed.

### Assumptions Challenged

- **Assumption**: "streaming eliminates the 60s wall by construction"
  assumes the FIRST token arrives within the intermediary's idle-timer
  window.
- **Risk if wrong**: a model with extreme reasoning depth + queue
  congestion could still take >60s to emit byte 1, in which case the
  streaming path would hit the same `RemoteProtocolError` as the
  legacy path.
- **Recommendation**: make this explicit in the runbook
  (`grimoires/loa/runbooks/cheval-streaming-transport.md` already
  acknowledges it, but the language could be sharper). Also: capture
  per-call TTFB (time-to-first-byte) in the MODELINV audit payload as
  a new optional metric — operators can detect "TTFB approaching 60s"
  as a leading indicator before the failure mode reappears. Filing as
  follow-on enhancement.

### Alternatives Not Considered

- **Alternative**: use the `httpx-sse` PyPI package for the SSE parsing
  layer instead of hand-rolling `_iter_sse_events_raw_data` /
  `_iter_sse_events` in each `*_streaming.py` module.
- **Tradeoff**: external dep vs self-contained code. Self-contained
  is more auditable (you can see exactly what's parsed); external is
  battle-tested across many SSE consumers.
- **Verdict**: current approach is justified because (a) the SSE byte
  format is stable + simple, (b) per-provider variations (Anthropic's
  event-type discrimination, OpenAI's `[DONE]` terminator, Google's
  JSON-fragmented chunks) wouldn't be cleanly served by a single
  external parser anyway, and (c) the test surface (8-11 cases per
  provider) pins behavior. No fix recommended; documented as a noted
  alternative for future maintainers.

## Non-Critical Improvements (recommended but non-blocking)

1. **Test surgery scope is too broad** (reviewer's pre-adversarial
   concern). `test_providers.py` and `test_google_adapter.py` added
   module-level autouse fixtures setting
   `LOA_CHEVAL_DISABLE_STREAMING=1` for every test in the module.
   Some of those tests (e.g.,
   `TestOpenAIResponsesNormalization`,
   `TestFallbackChain`) don't actually need to route through the
   adapter's `complete()` and could run with streaming default. Future
   cleanup: narrow the fixture to per-class or per-test scope.

2. **Input-size gate raised aggressively** (reviewer's pre-adversarial
   concern). Sprint 1F was 24K/36K. Live smokes went to 50K. Raised
   values are 200K/180K (4-5x larger than empirically validated).
   Recommend a follow-up sprint to live-smoke at 100K + 150K + 180K
   before declaring the streaming-default ceiling at 200K.

3. **Bats integration tests deferred**. Sprint plan named the test
   target `tests/cycle-102/cheval-streaming.bats`; implementation
   placed pytest-only tests at `.claude/adapters/tests/test_*_streaming.py`.
   The reviewer.md acknowledges this as a known limitation. Recommend
   landing the bats integration in a follow-up if `bats` is the
   preferred CI smoke surface for cheval.

## Previous Feedback Status

No prior `engineer-feedback.md` exists for sprint-4A. This is the
first reviewer cycle.

## Cross-Model Observations

The adversarial reviewer was claude-opus-4-7 — same provider family as
the Anthropic adapter being reviewed. A separate cycle with
gemini-3.1-pro or gpt-5.5-pro as the dissenter would provide
cross-provider triangulation and is worth attempting in a future
review pass. Per `flatline_protocol.code_review.fallback_chain` config,
the run-bridge / BB phases will exercise the multi-model triangulation
naturally; this single dissenter pass is the minimum mandated check.

The cost of the adversarial pass ($0.1364) and clean reviewed-status
on a ~120K-token diff are themselves evidence the streaming transport
works at sprint-diff scale — even though that wasn't the explicit
purpose of the call. Cross-model AC-4A.7 organic-evidence note worth
adding to the reviewer.md known-limitations section.

## Incomplete Tasks

None. All 8 sprint tasks (T4A.1 through T4A.8) are complete per the
reviewer.md. The blocker (DISS-001) is a quality issue inside an
otherwise complete deliverable, not an incomplete task.

## Next Steps

1. **Engineer**: address DISS-001 per the fix path described above.
2. Add the regression test that pins the kill-switch + audit-emit
   consistency across the truthy-value set.
3. Run the full pytest suite — expect 888-889 passes (1-2 new tests).
4. Commit as a Sprint 4A follow-up:
   `fix(cycle-102 sprint-4A): centralize LOA_CHEVAL_DISABLE_STREAMING
   detection — close DISS-001 audit-chain lie`.
5. Reviewer will re-run review on the fixed branch state. If no new
   findings (or only advisory), approval issues.

After approval, the loop continues to `/audit-sprint sprint-4A`.

## Verification of Fix (for next review cycle)

The fix is verifiable by:

```bash
# Set the non-strict truthy value
LOA_CHEVAL_DISABLE_STREAMING=true python3 -c "
import sys; sys.path.insert(0, '.claude/adapters')
import os
from loa_cheval.providers import base
from loa_cheval.audit.modelinv import _streaming_active

# Adapters should detect the kill switch
disabled_adapter = base._streaming_disabled()   # to-be-added helper
print(f'adapter sees streaming_disabled={disabled_adapter}')

# Audit should record the same boolean
audit_streaming = _streaming_active()
print(f'audit sees streaming_active={audit_streaming}')

# These MUST be consistent: disabled_adapter == (not audit_streaming)
assert disabled_adapter is (not audit_streaming), 'DISS-001 unfixed'
print('DISS-001 fixed ✓')
"
```
