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
import unicodedata
from pathlib import Path
from typing import Any, Dict, List, Optional

# Sprint 4A DISS-001/DISS-002 closure: module-level import of the centralized
# kill-switch helper. No import cycle exists between providers.base and
# audit.modelinv (verified via direct import test); the earlier draft used a
# lazy function-local import out of misplaced caution.
from loa_cheval.providers.base import _streaming_disabled

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

# cycle-103 T3.7 / AC-3.7 / DISS-004 — extended bearer-token gate.
#
# Coverage:
#   1. `Bearer <token>` — space-separated (original)
#   2. `bearer <token>` — case-insensitive (original)
#   3. `Bearer\t<token>` — tab-separated (original)
#   4. `bearer:<token>` — colon separator (no space) — NEW
#   5. `%20Bearer%20<token>` — percent-encoded — NEW (via _normalize_for_gate)
#   6. `\"Bearer <token>\"` — JSON-escape-quoted — NEW (via _normalize_for_gate)
#   7. `Ｂｅａｒｅｒ <token>` — Unicode fullwidth — NEW (via NFKC in _normalize_for_gate)
#   8. `B​earer <token>` — zero-width insertion — NEW (via control-byte strip)
#
# Detection mirrors the cycle-099 sprint-1E.c.3.c Unicode-glob bypass closure
# pattern: NFKC normalize + zero-width strip + light percent-decode BEFORE
# regex match. The character-class allows colon as separator alongside the
# original space/tab.
_GATE_BEARER = re.compile(r"[Bb]earer[ \t:]+[A-Za-z0-9._~+/=\-]{16,}")

# Zero-width and bidi-override characters that can be inserted between the
# letters of "Bearer" to bypass a naive regex. Same disposition as cycle-099
# sprint-1E.c.3.c: strip before matching.
_ZERO_WIDTH = re.compile("[​-‍﻿‪-‮]")

# Percent-encoded forms that can hide Bearer in URL-embedded headers.
# Single-pass decode (no recursion → no amplification attack surface).
_PERCENT_DECODE_MAP = {
    "%20": " ",
    "%09": "\t",
    "%22": '"',
    "%3A": ":",
    "%3a": ":",
}


def _normalize_for_gate(text: str) -> str:
    """Apply NFKC + zero-width strip + light percent-decode before matching.

    The gate's job (cycle-098 audit-envelope defense-in-depth) is to catch
    secret shapes the redactor missed. Post-cycle-103 T3.7, encoded /
    obfuscated bearer shapes are normalized to ASCII canonical form before
    the regex run so that:

      - Unicode fullwidth (Ｂｅａｒｅｒ) becomes ASCII (Bearer) via NFKC
      - Zero-width insertions (B​earer) get stripped
      - Percent-encoded (%20Bearer%20) gets decoded to space-separated
      - JSON-escape-quoted (\"Bearer X\") gets decoded — the inner Bearer
        is then matchable by the canonical regex

    The function is idempotent on already-normalized input: ASCII Bearer
    passes through unchanged.
    """
    # NFKC handles fullwidth Bearer → Bearer + other Unicode look-alikes.
    text = unicodedata.normalize("NFKC", text)
    # Strip zero-width and bidi-override characters that defeat naive regex.
    text = _ZERO_WIDTH.sub("", text)
    # Single-pass percent-decode for the common URL-embedded forms.
    for encoded, decoded in _PERCENT_DECODE_MAP.items():
        text = text.replace(encoded, decoded)
    return text


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
    # cycle-103 T3.7 / AC-3.7 / DISS-004: normalize encoded/obfuscated
    # bearer-token variants to canonical ASCII form before matching.
    if _GATE_BEARER.search(_normalize_for_gate(payload_json)):
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
    untrusted-content field names — **path-aware** (T3.6 / DISS-003).

    Once a key in `_REDACT_FIELDS` is encountered, every descendant string
    is redacted regardless of intermediate dict keys or list nesting. This
    closes the gap where an adapter returns a structured exception body
    (e.g. `{"error_message": {"detail": "<leaked>"}}` or
    `{"error_message": [{"inner": "<leaked>"}]}`) and the original
    immediate-parent-only walk would leave the nested untrusted string
    intact.

    Structure (dict shape, list shape, key names, ordering, non-string
    types) is preserved exactly — only string VALUES under an
    untrusted-content ancestor are passed through `redact()`. This matters
    for the audit-envelope round-trip pin (sprint.md R8a).
    """
    return _redact_recurse(payload, under_untrusted=False)


def _redact_recurse(node: Any, under_untrusted: bool) -> Any:
    """Inner walk that threads the `under_untrusted` flag through the
    recursion. Once set, the flag stays set for every descendant; redaction
    applies to every string regardless of immediate-parent key.
    """
    if isinstance(node, dict):
        out = {}
        for k, v in node.items():
            child_untrusted = under_untrusted or (k in _REDACT_FIELDS)
            if child_untrusted and isinstance(v, str):
                out[k] = _REDACT(v)
            else:
                out[k] = _redact_recurse(v, child_untrusted)
        return out
    if isinstance(node, list):
        return [
            _REDACT(item) if (under_untrusted and isinstance(item, str))
            else _redact_recurse(item, under_untrusted)
            for item in node
        ]
    return node


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


def _streaming_active() -> bool:
    """True iff the Sprint 4A streaming transport was used for this call.

    Sprint 4A DISS-001 closure: this helper delegates to
    `base._streaming_disabled()` to guarantee that adapters and audit-emit
    consume an identical boolean. Before centralization, the adapters used
    strict `== "1"` while this helper used case-insensitive multi-value —
    that mismatch let an operator setting `LOA_CHEVAL_DISABLE_STREAMING=true`
    route through streaming while the audit chain recorded `streaming=false`
    (the silent-degradation pattern vision-019 M1 was built to detect).

    Sprint 4A cycle-2 DISS-002 closure: the import is at module level (no
    actual cycle exists; verified via direct import test). Earlier draft
    used a lazy function-local import to defend against a hypothetical
    cycle that doesn't materialize in practice.
    """
    return not _streaming_disabled()


# Cycle-108 sprint-1 T1.F — writer_version single source of truth.
# Read from .claude/data/cycle-108/modelinv-writer-version once per process.
# Cached for the lifetime of this module's import (per SDD §21.4 contract).
_WRITER_VERSION_CACHE: Optional[str] = None
_WRITER_VERSION_PATH = ".claude/data/cycle-108/modelinv-writer-version"


def _find_repo_root(start: Path) -> Path:
    """Walk up from ``start`` looking for a stable repo-root marker.

    Looks for either ``.git`` or ``.loa.config.yaml`` as the marker
    (both are present at the canonical loa repo root). Falls back to
    ``start.parents[4]`` if no marker is found within 10 ancestors —
    preserves backward-compat with the original hardcoded depth.

    cycle-109 Sprint 5 T5.2 (#875): replaces the brittle ``parents[4]``
    hardcode that broke when the module moved or was site-packaged.
    """
    current = start
    for _ in range(10):  # bounded walk
        parent = current.parent
        if parent == current:
            break  # reached filesystem root
        if (parent / ".git").exists() or (parent / ".loa.config.yaml").exists():
            return parent
        current = parent
    # Fallback: original parents[4] depth for callers in well-known
    # locations (.claude/adapters/loa_cheval/audit/<file>.py → 4 levels up)
    try:
        return start.parents[4]
    except IndexError:
        return start.parent


def _read_writer_version() -> Optional[str]:
    """Read writer_version from the SoT file. Cached after first read.

    Returns the version string (e.g. '1.2') or None if the file is absent
    (which preserves v1.1 legacy emit behavior in case of a partial install).
    """
    global _WRITER_VERSION_CACHE
    if _WRITER_VERSION_CACHE is not None:
        return _WRITER_VERSION_CACHE

    # cycle-109 Sprint 5 T5.2 (#875): repo-root resolution via marker
    # walker rather than parents[N] hardcode. parents[4] was brittle —
    # it broke when the module moved, when callers patched __file__,
    # or when the package was installed as site-packages. The walker
    # looks for a stable repo-root marker (.git directory or .loa.config.yaml)
    # and falls back to parents[4] for backward compat.
    repo_root = _find_repo_root(Path(__file__).resolve())
    sot_path = repo_root / _WRITER_VERSION_PATH

    if not sot_path.exists():
        return None

    try:
        version = sot_path.read_text().strip()
        if version:
            _WRITER_VERSION_CACHE = version
            return version
    except OSError:
        pass
    return None


def _reset_writer_version_cache_for_tests() -> None:
    """Test-only helper to clear the writer_version cache between tests."""
    global _WRITER_VERSION_CACHE
    _WRITER_VERSION_CACHE = None


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
    streaming: Optional[bool] = None,
    final_model_id: Optional[str] = None,
    transport: Optional[str] = None,
    config_observed: Optional[Dict[str, str]] = None,
    # Cycle-108 sprint-1 T1.F — advisor-strategy additive fields (v1.2 envelope).
    # Backward-compat: all None defaults → emitter produces v1.1-shaped output.
    role: Optional[str] = None,
    tier: Optional[str] = None,
    tier_source: Optional[str] = None,
    tier_resolution: Optional[str] = None,
    sprint_kind: Optional[str] = None,
    invocation_chain: Optional[List[str]] = None,
    # Cycle-108 sprint-2 T2.J — envelope-captured pricing (SDD §20.9 ATK-A20).
    # Snapshot of providers.<p>.models.<m>.pricing at invocation time.
    pricing_snapshot: Optional[Dict[str, int]] = None,
    # Cycle-109 Sprint 1 T1.4 — capability-aware substrate evaluation (SDD §3.3.1).
    # Snapshot of the pre-flight gate decision: effective_input_ceiling,
    # reasoning_class, recommended_for, ceiling_stale, estimated_input_tokens,
    # preflight_decision ∈ {dispatch, preempt, chunk}. None when the call
    # path bypassed the gate (LOA_CHEVAL_DISABLE_INPUT_GATE=1, async mode,
    # or pre-resolution failure).
    capability_evaluation: Optional[Dict[str, Any]] = None,
    # Cycle-109 Sprint 2 T2.3 — verdict-quality envelope (SDD §3.3.1 v1.3
    # additive + §3.2 schema). Validated + status-stamped envelope built
    # by the caller via `loa_cheval.verdict.quality.emit_envelope_with_status`.
    # Optional/additive — callers that don't (yet) produce envelopes simply
    # omit the kwarg and the payload is shape-identical to pre-T2.3 emits.
    verdict_quality: Optional[Dict[str, Any]] = None,
    # Cycle-109 Sprint 4 T4.7 — chunked-review snapshot (SDD §5.4).
    # Populated when the pre-flight gate routed the call through the
    # chunking package. Absent when chunking was not invoked.
    chunked_review: Optional[Dict[str, Any]] = None,
    # Cycle-109 Sprint 4 T4.7 — streaming-with-recovery telemetry
    # (SDD §5.4.4 / IMP-014). Populated when the streaming code path
    # observed (and possibly aborted via) one of the three thresholds.
    streaming_recovery: Optional[Dict[str, Any]] = None,
    # Cycle-110 sprint-2b1 T2.8 — MODELINV v1.4 additive fields
    # ([PRD:FR-3.4, FR-7.1], SDD §3.4). All optional — when ALL are None,
    # the emitted envelope is shape-identical to v1.3. Operators reading v1.3
    # envelopes tolerate unknown fields per the cycle-109 forward-compat
    # contract; cycle-110 readers default absent fields to "http_api" /
    # per_token / None.
    auth_type_resolved: Optional[str] = None,
    auth_type_selection_reason: Optional[str] = None,
    auto_selection_inputs: Optional[Dict[str, Any]] = None,
    auto_evaluation_timestamp: Optional[float] = None,
    semaphore_exhausted: Optional[bool] = None,
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
        # Sprint 4A: surface whether the streaming transport was used.
        # Default-derived from the env-var kill switch so callers don't have
        # to pass it explicitly. Caller may override for tests / dry-runs.
        # cycle-103 T3.2 / AC-3.2: precedence is
        #   1. caller-supplied `streaming` arg (read from adapter's
        #      CompletionResult.metadata['streaming'] — the actual transport
        #      observed at completion time).
        #   2. env-derived `_streaming_active()` — fallback for legacy callers
        #      that don't propagate the adapter's observation.
        # The adapter override matters when an operator sets
        # LOA_CHEVAL_DISABLE_STREAMING=1 mid-session: the env-derived value
        # would record streaming=False for in-flight requests that actually
        # ran via the streaming transport. The metadata override ties the
        # audit record to the wire behavior, not the env state at emit time.
        "streaming": streaming if streaming is not None else _streaming_active(),
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
    # cycle-104 Sprint 2 T2.6 (FR-S2.3 / SDD §3.4): chain-walk evidence.
    # final_model_id, transport, config_observed are additive — the schema's
    # additionalProperties:false constraint means we only attach them when
    # populated to keep backward-compat with single-model emitters that
    # haven't been migrated.
    if final_model_id is not None:
        payload["final_model_id"] = final_model_id
    if transport is not None:
        if transport not in ("http", "cli"):
            raise ValueError(
                f"emit_model_invoke_complete: transport must be 'http' or "
                f"'cli', got {transport!r}"
            )
        payload["transport"] = transport
    if config_observed is not None:
        payload["config_observed"] = dict(config_observed)

    # Cycle-108 sprint-1 T1.F — advisor-strategy v1.2 additive fields.
    # All optional; additionalProperties:false is satisfied because each
    # field is now declared in the v1.2 schema. Backward-compat: when ALL
    # of these are None (legacy callers), the emitted envelope is shape-
    # identical to v1.1.
    if role is not None:
        payload["role"] = role
    if tier is not None:
        payload["tier"] = tier
    if tier_source is not None:
        payload["tier_source"] = tier_source
    if tier_resolution is not None:
        payload["tier_resolution"] = tier_resolution
    if sprint_kind is not None:
        payload["sprint_kind"] = sprint_kind
    if invocation_chain is not None:
        payload["invocation_chain"] = list(invocation_chain)

    # writer_version is set unconditionally for cycle-108+ emitters
    # (single source of truth from .claude/data/cycle-108/modelinv-writer-version).
    # Note: ATK-A7 closure (strip-attack detection) lives in the rollup tool
    # (Sprint 2 deliverable), not here — emitter side just records the version.
    _writer_version = _read_writer_version()
    if _writer_version is not None:
        payload["writer_version"] = _writer_version

    # cycle-108 ATK-A15: replay_marker (env-flag-controlled)
    if os.environ.get("LOA_REPLAY_CONTEXT") == "1":
        payload["replay_marker"] = True

    # cycle-108 sprint-2 T2.J — envelope-captured pricing (SDD §20.9 ATK-A20).
    # Optional; only emitted when caller supplied a snapshot. Rollup tool reads
    # pricing FROM the envelope, so historical pricing changes never retroactively
    # rewrite cost reports.
    if pricing_snapshot is not None:
        # Defensive copy + integer coerce. Caller may pass numpy ints etc.;
        # JSON schema requires plain ints. Drops keys that don't validate.
        _snapshot: Dict[str, Any] = {}
        for _k in ("input_per_mtok", "output_per_mtok", "reasoning_per_mtok", "per_task_micro_usd"):
            if _k in pricing_snapshot and pricing_snapshot[_k] is not None:
                _snapshot[_k] = int(pricing_snapshot[_k])
        if "pricing_mode" in pricing_snapshot and pricing_snapshot["pricing_mode"] is not None:
            _snapshot["pricing_mode"] = str(pricing_snapshot["pricing_mode"])
        # Required-key gate: schema requires input/output. Skip emit if missing.
        if "input_per_mtok" in _snapshot and "output_per_mtok" in _snapshot:
            payload["pricing_snapshot"] = _snapshot

    # cycle-109 Sprint 1 T1.4 — capability_evaluation pass-through. Schema
    # additivity: only emit when caller supplied the dict. Required keys
    # (effective_input_ceiling, reasoning_class, recommended_for,
    # ceiling_stale, estimated_input_tokens, preflight_decision) are
    # enforced by the JSON Schema downstream of redaction; the emitter
    # passes the dict through verbatim so the caller's pre-flight gate
    # state is recorded faithfully.
    if capability_evaluation is not None:
        # Defensive copy so the caller's dict cannot be mutated by downstream
        # redaction passes.
        payload["capability_evaluation"] = dict(capability_evaluation)
        # Normalize recommended_for to a plain list (defensive against tuples).
        if "recommended_for" in payload["capability_evaluation"]:
            payload["capability_evaluation"]["recommended_for"] = list(
                payload["capability_evaluation"]["recommended_for"]
            )

    # cycle-109 Sprint 4 T4.7 — chunked_review + streaming_recovery
    # pass-throughs (SDD §3.3.1 v1.3 additive + §5.4 chunking +
    # §5.4.4 IMP-014). Defensive copy at the top level so caller's
    # dict cannot be mutated by downstream redaction passes.
    if chunked_review is not None:
        payload["chunked_review"] = dict(chunked_review)
    if streaming_recovery is not None:
        payload["streaming_recovery"] = dict(streaming_recovery)

    # Cycle-110 sprint-2b1 T2.8 — MODELINV v1.4 additive fields.
    # All four flow through the redactor at the end of this function (the
    # redactor walks the dict recursively, so adding keys here does not
    # require redaction-table changes). auth_type_resolved is validated
    # against the closed enum at the call site (resolver), but we defense-
    # in-depth re-validate here so a stale caller cannot smuggle bad values.
    if auth_type_resolved is not None:
        if auth_type_resolved not in ("headless", "http_api", "aws_iam"):
            raise ValueError(
                "emit_model_invoke_complete: auth_type_resolved must be one of "
                f"('headless', 'http_api', 'aws_iam'), got {auth_type_resolved!r}"
            )
        payload["auth_type_resolved"] = auth_type_resolved
    if auth_type_selection_reason is not None:
        # Match dispatch_filter.SELECTION_REASONS enum.
        if auth_type_selection_reason not in (
            "explicit-dispatch_preference",
            "auto-band-comparison",
            "auto-cold-start-recommended_for",
            "auto-cold-start-default-headless",
        ):
            raise ValueError(
                "emit_model_invoke_complete: auth_type_selection_reason must "
                "be one of {explicit-dispatch_preference, auto-band-comparison, "
                "auto-cold-start-recommended_for, auto-cold-start-default-headless}, "
                f"got {auth_type_selection_reason!r}"
            )
        payload["auth_type_selection_reason"] = auth_type_selection_reason
    if auto_selection_inputs is not None:
        # Defensive copy + shape check. C11 carry-in: must conform to SDD §3.4
        # canonical example. Three required keys per the spec.
        if not isinstance(auto_selection_inputs, dict):
            raise ValueError(
                "auto_selection_inputs must be a dict, got "
                f"{type(auto_selection_inputs).__name__}"
            )
        # Defensive copy at top level + dict-coerce on the three sub-keys.
        _aux: Dict[str, Any] = {}
        for k in ("sample_n_per_bucket", "band_per_bucket", "success_rate_per_bucket"):
            if k in auto_selection_inputs and auto_selection_inputs[k] is not None:
                _aux[k] = dict(auto_selection_inputs[k])
        payload["auto_selection_inputs"] = _aux
    if auto_evaluation_timestamp is not None:
        payload["auto_evaluation_timestamp"] = float(auto_evaluation_timestamp)
    if semaphore_exhausted is not None:
        payload["semaphore_exhausted"] = bool(semaphore_exhausted)

    # cycle-109 Sprint 2 T2.3 — verdict_quality pass-through (SDD §3.3.1 v1.3
    # additive). Schema additivity: only emit when caller supplied the dict.
    # The caller (cheval.cmd_invoke for PRODUCER #1) is responsible for
    # building + validating the envelope via emit_envelope_with_status; the
    # emitter trusts the contract and passes the dict through verbatim
    # (post-redaction) into the MODELINV payload.
    if verdict_quality is not None:
        # Defensive copy at the top level so caller's dict cannot be mutated
        # by the redaction pass. voices_dropped[] entries are dicts too —
        # do a one-level-deep copy on the list contents for the same reason.
        _vq_copy: Dict[str, Any] = dict(verdict_quality)
        _dropped = _vq_copy.get("voices_dropped")
        if isinstance(_dropped, list):
            _vq_copy["voices_dropped"] = [
                dict(d) if isinstance(d, dict) else d for d in _dropped
            ]
        _succeeded_ids = _vq_copy.get("voices_succeeded_ids")
        if isinstance(_succeeded_ids, list):
            _vq_copy["voices_succeeded_ids"] = list(_succeeded_ids)
        payload["verdict_quality"] = _vq_copy

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
