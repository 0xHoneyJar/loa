"""MODELINV model.invoke.complete envelope emitter (cycle-102 Sprint 1D / T1.7).

Closes the redaction-leak vector documented in Sprint 1B T1B.1 by:

1. **Field-level redaction** (`redact_payload_strings`) — runs the
   `.claude/scripts/lib/log-redactor.py` canonical redactor over every
   string in the model.invoke.complete payload that may carry untrusted
   upstream content (error messages, exception summaries). Does NOT
   redact strings that come from operator config (model identifiers).

2. **Defense-in-depth gate** (`assert_no_secret_shapes_remain`) — a
   shape-driven scan over the post-redaction serialized payload. Raises
   `RedactionFailure` if AKIA / PEM / Bearer shapes remain. The gate is
   the fail-closed safety net for shapes the redactor doesn't yet
   recognize. NEVER reaches `audit_emit` on RedactionFailure — chain
   integrity preserved.

3. **audit_emit invocation** (`emit_model_invoke_complete`) — calls the
   cycle-098 `loa_cheval.audit_envelope.audit_emit` with primitive_id
   "MODELINV", event_type "model.invoke.complete", validated payload,
   and the canonical `.run/model-invoke.jsonl` log path (override via
   `LOA_MODELINV_LOG_PATH` for tests).

Per Sprint 1D NOTES.md Decision Log on T1B.1-vs-T1.7: T1B.1 shipped the
schema redaction *contract*; T1.7 ships *enforcement*. Both are required
to close the leak.
"""

from __future__ import annotations

import importlib.util
import json
import logging
import os
import re
from pathlib import Path
from typing import Any, Dict, List, Optional

logger = logging.getLogger("loa_cheval.audit.modelinv")


# -----------------------------------------------------------------------------
# Redactor module loading.
#
# `.claude/scripts/lib/log-redactor.py` is the canonical Python implementation;
# it lives outside the loa_cheval package because it's also invoked as a bash
# filter (the bash twin is `log-redactor.sh`). The hyphen in the filename
# prevents standard `import` syntax, so we use importlib.util to load it once
# at module-import time.
# -----------------------------------------------------------------------------

_REDACTOR_PATH = (
    Path(__file__).resolve().parent.parent.parent.parent / "scripts" / "lib" / "log-redactor.py"
)


def _load_redactor():
    """Load .claude/scripts/lib/log-redactor.py as a module and return its
    `redact` function. Cached at module import via _REDACT.
    """
    if not _REDACTOR_PATH.is_file():
        raise RuntimeError(
            f"log-redactor.py not found at {_REDACTOR_PATH}. "
            "MODELINV emit requires the cycle-099 sprint-1E.a + cycle-102 "
            "sprint-1D log redactor library."
        )
    spec = importlib.util.spec_from_file_location("loa_log_redactor", _REDACTOR_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Failed to load redactor module from {_REDACTOR_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.redact


_REDACT = _load_redactor()


# -----------------------------------------------------------------------------
# Defense-in-depth gate (T1.7.e).
#
# Detection patterns mirror the redactor's bare-shape patterns from
# log-redactor.py. Any survival in the post-redaction serialized payload is
# treated as a redactor miss and rejected fail-closed.
#
# Patterns are intentionally redundant with the redactor — the gate's job is
# to catch (a) bugs in the redactor pass-order, (b) future shapes the
# redactor doesn't yet handle, (c) embedded structures (e.g., AKIA inside a
# JSON string field) that the redactor's URL-grammar passes can't reach.
# -----------------------------------------------------------------------------

_GATE_AKIA = re.compile(r"AKIA[0-9A-Z]{16}")
_GATE_PEM_BEGIN = re.compile(r"-----BEGIN [A-Z 0-9]*PRIVATE KEY-----")
_GATE_BEARER = re.compile(r"[Bb]earer[ \t][A-Za-z0-9._~+/=-]+")


class RedactionFailure(Exception):
    """Raised when the defense-in-depth gate finds a secret shape in the
    serialized audit payload. Maps to STRICT_VIOLATION exit code in cheval.

    The exception MUST NOT include the offending substring in its message —
    that would leak the secret into cheval stderr. Instead, name the shape
    that triggered and the field path (where determinable). Operator
    diagnostics live in the audit chain (which never wrote the unredacted
    payload).
    """

    def __init__(self, shape: str, field_hint: str = ""):
        self.shape = shape
        self.field_hint = field_hint
        msg = f"redaction gate rejected payload: {shape}-shape secret remained after redactor"
        if field_hint:
            msg += f" (likely field: {field_hint})"
        super().__init__(msg)


def assert_no_secret_shapes_remain(payload_json: str) -> None:
    """Scan the serialized JSON payload for secret shapes the redactor missed.

    Raises:
        RedactionFailure: if any AKIA / PEM-BEGIN / Bearer shape remains.
            Caller MUST treat as fatal — the audit_emit MUST NOT be called.

    The function is shape-driven and idempotent on already-redacted input
    (the `[REDACTED-AKIA]` etc. sentinels never match the detection
    patterns).
    """
    if _GATE_AKIA.search(payload_json):
        raise RedactionFailure("AKIA")
    if _GATE_PEM_BEGIN.search(payload_json):
        raise RedactionFailure("PEM-PRIVATE-KEY")
    if _GATE_BEARER.search(payload_json):
        raise RedactionFailure("Bearer-token")


# -----------------------------------------------------------------------------
# Field-level redaction (T1.7.d).
# -----------------------------------------------------------------------------

# Field names whose values come from untrusted upstream content (API error
# bodies, exception messages). These get redacted unconditionally.
#
# Other fields (`model`, `models_requested`, `capability_class`, etc.) come
# from operator-controlled config and are NOT redacted — redacting model
# identifiers would break audit-query semantics.
_REDACT_FIELDS = frozenset(
    [
        "message_redacted",
        "original_exception",
        "exception_summary",
        "error_message",
    ]
)


def redact_payload_strings(payload: Any) -> Any:
    """Recursively walk a payload structure; redact strings under known
    untrusted-content field names.

    The walk preserves list/dict structure exactly. Only string VALUES under
    the configured field names are passed through `redact()`. Strings under
    other keys (or in lists at the top level) are left unchanged.

    This is field-aware redaction — distinct from blanket-redacting every
    string value, which would over-redact operator-controlled identifiers.
    """
    if isinstance(payload, dict):
        out = {}
        for k, v in payload.items():
            if k in _REDACT_FIELDS and isinstance(v, str):
                out[k] = _REDACT(v)
            else:
                out[k] = redact_payload_strings(v)
        return out
    if isinstance(payload, list):
        return [redact_payload_strings(item) for item in payload]
    return payload


# -----------------------------------------------------------------------------
# Log-path resolution (T1.7.d).
#
# `audit-retention-policy.yaml::primitives.MODELINV.log_basename` is
# `model-invoke.jsonl`. The canonical log path is `.run/model-invoke.jsonl`
# (UNTRACKED, hash-chained). Tests override via LOA_MODELINV_LOG_PATH.
# -----------------------------------------------------------------------------

_DEFAULT_LOG_BASENAME = "model-invoke.jsonl"


def _resolve_log_path() -> Path:
    """Return the canonical MODELINV log path. Honors LOA_MODELINV_LOG_PATH
    test override. Otherwise resolves to `<repo-root>/.run/model-invoke.jsonl`,
    where repo-root is two directories up from .claude/adapters/loa_cheval/.
    """
    override = os.environ.get("LOA_MODELINV_LOG_PATH")
    if override:
        return Path(override)
    # Walk up to the repo root from .claude/adapters/loa_cheval/audit/modelinv.py
    here = Path(__file__).resolve()
    repo_root = here.parent.parent.parent.parent.parent
    return repo_root / ".run" / _DEFAULT_LOG_BASENAME


# -----------------------------------------------------------------------------
# High-level emitter (T1.7.d).
# -----------------------------------------------------------------------------


def _kill_switch_active() -> bool:
    """True iff `LOA_FORCE_LEGACY_MODELS` is set to a truthy value at the
    moment of the emit. Per SDD §11 + gemini IMP-004 HIGH.

    Truthy values: "1", "true", "yes" (case-insensitive). Anything else
    (including empty string) is falsy.
    """
    val = os.environ.get("LOA_FORCE_LEGACY_MODELS", "")
    return val.lower() in ("1", "true", "yes")


def emit_model_invoke_complete(
    *,
    models_requested: List[str],
    models_succeeded: List[str],
    models_failed: List[Dict[str, Any]],
    operator_visible_warn: bool,
    capability_class: Optional[str] = None,
    calling_primitive: Optional[str] = None,
    probe_latency_ms: Optional[int] = None,
    invocation_latency_ms: Optional[int] = None,
    cost_micro_usd: Optional[int] = None,
) -> None:
    """Emit a model.invoke.complete envelope to the MODELINV audit chain.

    Pipeline:
      1. Build payload conforming to model-invoke-complete.payload.schema.json.
      2. `redact_payload_strings(payload)` — field-level redaction.
      3. `assert_no_secret_shapes_remain(json.dumps(payload))` — gate check.
         RAISES RedactionFailure if any secret shape remains.
      4. `audit_emit(MODELINV, model.invoke.complete, payload, log_path)`.

    Caller contract:
      - `models_requested`: list of `provider:model_id` strings; MUST have
        at least one entry per schema.
      - `models_succeeded`: subset of models_requested that produced a usable
        response. Empty on failure-only paths.
      - `models_failed`: list of dicts with keys (model, error_class,
        message_redacted, [fallback_from, fallback_to, retryable]).
        `message_redacted` MAY contain raw upstream content; it WILL be
        redacted in step 2.
      - `operator_visible_warn`: did the operator see a WARN line on this
        call? Required for vision-019 M1 silent-degradation audit query.
      - `kill_switch_active`: derived from env (LOA_FORCE_LEGACY_MODELS).

    Failures:
      - RedactionFailure: gate rejected the payload. Caller MAPS to exit
        code STRICT_VIOLATION (see cheval.py main()).
      - Other exceptions (audit_emit failure, schema invalid, lock timeout):
        logged to cheval stderr with [AUDIT-EMIT-FAILED] marker; NOT
        re-raised by default (audit failure should not break user-facing
        invocations). Override via LOA_MODELINV_FAIL_LOUD=1.
    """
    payload: Dict[str, Any] = {
        "models_requested": models_requested,
        "models_succeeded": models_succeeded,
        "models_failed": models_failed,
        "operator_visible_warn": operator_visible_warn,
        "kill_switch_active": _kill_switch_active(),
    }
    # Optional fields — only set when caller provides a value, so the
    # additionalProperties: false schema constraint stays satisfied.
    if capability_class is not None:
        payload["capability_class"] = capability_class
    if calling_primitive is not None:
        payload["calling_primitive"] = calling_primitive
    if probe_latency_ms is not None:
        payload["probe_latency_ms"] = probe_latency_ms
    if invocation_latency_ms is not None:
        payload["invocation_latency_ms"] = invocation_latency_ms
    if cost_micro_usd is not None:
        payload["cost_micro_usd"] = cost_micro_usd

    # Field-level redaction.
    payload = redact_payload_strings(payload)

    # Defense-in-depth gate.
    payload_json = json.dumps(payload, separators=(",", ":"), ensure_ascii=False)
    assert_no_secret_shapes_remain(payload_json)  # raises RedactionFailure

    # audit_emit invocation. Lazy import to avoid a hard dependency on the
    # cycle-098 audit_envelope module being loadable in environments where
    # cheval is invoked without an active audit chain (e.g., dry-run).
    try:
        from loa_cheval.audit_envelope import audit_emit
    except ImportError as e:
        logger.warning(
            "[AUDIT-EMIT-FAILED] could not import audit_envelope module: %s. "
            "Set LOA_MODELINV_AUDIT_DISABLE=1 to suppress this warning in "
            "test environments without audit infrastructure.",
            e,
        )
        return

    if os.environ.get("LOA_MODELINV_AUDIT_DISABLE", "").lower() in ("1", "true", "yes"):
        return

    log_path = _resolve_log_path()
    try:
        audit_emit("MODELINV", "model.invoke.complete", payload, log_path)
    except Exception as e:  # noqa: BLE001 — broad on purpose; see fail-loud env
        logger.warning(
            "[AUDIT-EMIT-FAILED] MODELINV emit raised %s: %s. "
            "User-facing call NOT failed (audit fail-soft default). "
            "Set LOA_MODELINV_FAIL_LOUD=1 to re-raise.",
            type(e).__name__,
            e,
        )
        if os.environ.get("LOA_MODELINV_FAIL_LOUD", "").lower() in ("1", "true", "yes"):
            raise
