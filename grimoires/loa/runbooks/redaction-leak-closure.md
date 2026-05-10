# Redaction-Leak Closure — MODELINV Emit Path

> **Status:** active runbook · cycle-102 Sprint 1D · 2026-05-10
> **Owners:** maintainer of `.claude/adapters/loa_cheval/audit/modelinv.py`
> **Audience:** operators triaging audit-chain leaks; agents extending the redactor

## What this closes

The cycle-102 Sprint 1B T1B.1 commit shipped a **schema-level redaction
contract** on `original_exception` (and the per-failed-model
`message_redacted` field): the schema description states that emitters
MUST redact upstream content before persisting it to the hash-chained,
immutable MODELINV audit log.

Until Sprint 1D, that contract was **documented but not enforced**. The
audit chain accepted unredacted bearer tokens, AWS access keys, and PEM
private-key blocks if any cheval emit-path bug let them through. Per
`grimoires/loa/NOTES.md` 2026-05-09 Decision Log on T1B.1 contract
documented vs T1.7 contract enforced:

> The X1 contract pin verifies the schema *says* "MUST run redactor"; it
> does not verify that anything *enforces* the MUST. On a hash-chained,
> immutable audit log, that gap is unusually expensive — a single emitter
> that ignores the MUST writes a permanent record of a secret.

Sprint 1D wires the enforcement layer. This runbook is the operator's map
to the resulting two-layer defense.

## The two layers

```
┌─────────────────────────────────────────────────────────────────┐
│  cheval cmd_invoke() — finally clause                           │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ Layer 1 — REDACTOR (substitution, structural-identity)    │  │
│  │ .claude/scripts/lib/log-redactor.{sh,py}                  │  │
│  │   • URL userinfo (cycle-099 sprint-1E.a)                  │  │
│  │   • 6 query-string secrets (cycle-099 sprint-1E.a)        │  │
│  │   • AKIA AWS access keys     (cycle-102 sprint-1D / NEW)  │  │
│  │   • PEM private-key blocks   (cycle-102 sprint-1D / NEW)  │  │
│  │   • Bearer-token shapes      (cycle-102 sprint-1D / NEW)  │  │
│  │ Run on `message_redacted`, `original_exception`,          │  │
│  │ `exception_summary`, `error_message` field VALUES.        │  │
│  └───────────────────────────────────────────────────────────┘  │
│                          ▼                                      │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ Layer 2 — GATE (assertion, fail-closed)                   │  │
│  │ assert_no_secret_shapes_remain(json.dumps(payload))       │  │
│  │   • If AKIA / PEM-BEGIN / Bearer shape REMAINS in the     │  │
│  │     post-redaction serialized payload → raise             │  │
│  │     RedactionFailure                                      │  │
│  │   • audit_emit is NEVER called on RedactionFailure        │  │
│  │   • Operator signal: [REDACTION-GATE-FAILURE] on stderr   │  │
│  └───────────────────────────────────────────────────────────┘  │
│                          ▼                                      │
│  audit_emit("MODELINV", "model.invoke.complete", payload, log)  │
└─────────────────────────────────────────────────────────────────┘
```

**Layer 1 (redactor)** is the structural-identity pass: it replaces secrets
with stable sentinels (`[REDACTED-AKIA]`, `[REDACTED-PRIVATE-KEY]`,
`[REDACTED-BEARER-TOKEN]`) so audit log queries can still reason about WHAT
kind of secret was redacted without seeing the value. Cross-runtime parity
with the bash twin is asserted by
`tests/integration/log-redactor-cross-runtime.bats`.

**Layer 2 (gate)** is the fail-closed safety net. It fires when the
redactor missed a shape — for example, a future API response format that
embeds AKIA inside a JSON path the redactor doesn't yet inspect, or a
pass-order bug that lets a Bearer token slip through. The gate's patterns
mirror the redactor's, so under correct operation Layer 2 never fires.
When it DOES fire, it's a signal that the redactor needs extending.

## Operator response when gate fires

If you see `[REDACTION-GATE-FAILURE] redaction gate rejected payload:
<shape>-shape secret remained after redactor` on cheval stderr:

1. **The audit chain is intact.** The unredacted payload was NOT written.
   You don't have a secret-leak incident; you have a redactor-coverage gap.
2. **Identify the shape** from the marker (AKIA / PEM-PRIVATE-KEY /
   Bearer-token).
3. **Locate the upstream content source.** The cheval invocation that
   triggered the gate has structured stderr — look for `[AUDIT-EMIT-FAILED]`
   or the original error_json that preceded the `[REDACTION-GATE-FAILURE]`
   line. The error message field is the most likely carrier.
4. **Extend the redactor** — add a pattern for the shape, or extend the
   detection-field allowlist in `_REDACT_FIELDS` if a new field-name needs
   redactor coverage. See "Adding a new secret shape" below.
5. **Add a regression test** to
   `tests/integration/log-redactor-cross-runtime.bats` and
   `tests/integration/cheval-redaction-emit-path.bats` so the closure
   sticks.

## Adding a new secret shape

The redactor has two cooperating implementations:

- `.claude/scripts/lib/log-redactor.py` — Python canonical. Hand-edit the
  `redact()` function and the `_…_RE` constants.
- `.claude/scripts/lib/log-redactor.sh` — bash twin. Hand-edit the
  `_redact()` sed pipeline. POSIX BRE only — no GNU extensions.

Cross-runtime parity is the contract. The bats suite asserts byte-equal
output between the two implementations across the entire fixture corpus.
Multi-line patterns (PEM blocks) require slurp via `:a;N;$!ba;` in the
bash sed pipeline and are applied as a second pipe stage so the
line-by-line URL/query/AKIA/Bearer passes don't see `\n` in pattern
space (which would over-match their negated character classes).

To add a new shape:

1. Add a Python regex to `log-redactor.py`:
   ```python
   _NEW_RE = re.compile(r"<your-pattern>")
   # in redact():
   text = _NEW_RE.sub("[REDACTED-NEW]", text)
   ```
2. Add the equivalent sed expression to `log-redactor.sh`. Decide whether
   it's line-by-line (first sed) or needs multi-line slurp (second sed).
3. Add a parity test stanza to `log-redactor-cross-runtime.bats` (e.g.,
   T17 for the next class). Include positive case, negative control, and
   idempotency assertion.
4. Update the gate in `.claude/adapters/loa_cheval/audit/modelinv.py` —
   add a `_GATE_NEW` regex that detects the unredacted shape and a branch
   in `assert_no_secret_shapes_remain`. The gate's pattern MAY be
   slightly relaxed compared to the redactor's (e.g., the gate detects
   `-----BEGIN ... PRIVATE KEY-----` even without the matching END
   marker, which the redactor does not redact because there's no
   complete block to substitute).
5. Add a regression test to `cheval-redaction-emit-path.bats` (R8 for
   the next shape) that exercises both the redact-success path and the
   gate-rejection path (use a malformed shape that the gate detects but
   the redactor's tighter pattern won't match).

## Operator-controlled overrides

The emit-path honors three environment variables. **None of them should
be set in production**; they exist for tests and for emergency operator
control.

| Env var | Effect | Use case |
|---------|--------|----------|
| `LOA_MODELINV_LOG_PATH` | Override the canonical `.run/model-invoke.jsonl` path. | bats tests that need per-test log isolation |
| `LOA_MODELINV_AUDIT_DISABLE=1` | Skip the audit_emit call entirely. Redaction + gate still run, but no log entry is appended. | Test environments without audit-envelope infrastructure |
| `LOA_MODELINV_FAIL_LOUD=1` | Re-raise audit_emit failures (lock contention, schema validation slip) instead of fail-soft logging. | Operator policy where audit chain breakage MUST surface as user-facing failure |
| `LOA_FORCE_LEGACY_MODELS=1` | Populates `kill_switch_active: true` in the envelope. | Operator-driven legacy-mode use; vision-019 audit query exercises this field |

## Why this isn't generic-secret detection

The redactor is **shape-driven**, not entropy-driven. It recognizes:

- AKIA-prefixed AWS access keys (real AWS keys are exactly 20 chars)
- PEM private-key blocks bracketed by `-----BEGIN ... PRIVATE KEY-----`
  and `-----END ... PRIVATE KEY-----`
- HTTP Bearer-token headers (RFC 7235 form)

It does **not** detect:

- Generic high-entropy strings (UUIDs, git SHAs, content addresses are
  high-entropy but not secrets — entropy thresholding has false positives
  that break audit-query semantics)
- API keys without a recognizable prefix (`sk-...`, `xoxb-...`, etc.)
  unless caller wraps them in URL framing or one of the known shapes
- Bearer tokens without the `Bearer<sep>` literal (raw JWTs in body
  fields, etc.)

Caller responsibility (per `log-redactor.py` docstring) is to:

1. **Reformat upstream content into URL-style framing** when feasible —
   the redactor's URL-grammar passes catch query-string and userinfo
   secrets reliably.
2. **Redact at the source** when the shape is genuinely
   one-of-a-kind — the audit-emit pipeline trusts that strings flowing
   into `models_failed[].message_redacted` either carry a known shape
   or have been pre-redacted upstream.

The gate is the safety net for callers that get this wrong; the
operator response loop above is how we close coverage gaps over time.

## Test references

- `tests/integration/log-redactor-cross-runtime.bats` —
  cross-runtime parity for the redactor (T13 AKIA, T14 PEM, T15 Bearer,
  T16 mixed) plus pre-existing T1-T12 (URL/query/idempotency/safety)
- `tests/integration/cheval-redaction-emit-path.bats` —
  emit-path integration (R1 AKIA · R2 PEM · R3 Bearer · R4 URL
  regression · R5 kill_switch_active · R7 gate accept/reject)
- `tests/unit/model-error-schema.bats` X1+X2 —
  schema contract pins (cycle-102 Sprint 1B T1B.1)

## Source: provenance

- **Origin issue**: T1.7 carry from cycle-102 Sprint 1B → Sprint 1D
- **Decision Log**: `grimoires/loa/NOTES.md` § 2026-05-09 Decision Log:
  T1B.1 contract documented vs T1.7 contract enforced
- **Vision references**: vision-023 (fractal recursion — "no surface fix is
  final"), vision-024 (substrate speaks twice — "iter-N REFRAME =
  instance, iter-(N+1) REFRAME = class"), vision-025 (substrate becomes
  the answer — "the bug class doesn't have to be solved at every layer;
  it just has to be routable AROUND")
- **PR**: cycle-102 Sprint 1D (this sprint)
- **Bridgebuilder iter-1 source**: FIND-001 HIGH_CONSENSUS Security
  (PR #813 BB iter-1) — "Redaction contract is documentation-only on
  an immutable chain"
