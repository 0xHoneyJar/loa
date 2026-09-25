"""Input-bound policy over a catalog entry (cycle-126 Sprint 1, PRD FR-1.1,
SDD D-1.1 / D-1.1b).

The bound a request may carry to a model is not one literal; it is decided
from the entry and the request:

  I1  ``estimate + max_tokens_on_wire ≤ context_window`` — the provider's
      hard invariant. ``fit_max_tokens`` shrinks the output budget to a
      4,096 floor before anything is refused; ``input_bound`` never returns
      more than ``context_window − max_tokens``.
  I2  the input bound proper:
        calibrated entry (``ceiling_calibration.calibrated_at`` set) →
            its ``effective_input_ceiling`` (a measurement);
        uncalibrated entry, default policy ``probed`` →
            ``probed_ceiling`` (the last measured value the catalog ships);
        uncalibrated entry, policy ``derived`` (``LOA_CHEVAL_UNCALIBRATED_CEILING=derived``) →
            ``context_window − max_tokens`` (the catalog's own arithmetic);
        an observed provider limit (``.run/ceiling-observed.json``, written by
            the self-correction) caps an uncalibrated bound at
            ``observed − 1`` until calibration;
        ``LOA_CHEVAL_MAX_INPUT_TOKENS`` lowers any bound (basis ``guard``);
        ``LOA_CHEVAL_LEGACY_CEILING=1`` → today's single literal, no I1.

Every basis is named in the decision so the envelope, the log line and the
tests can say why a request was allowed or refused. Entries without any
ceiling field (v2 shapes, CLI hops) have no bound here (``None``).
"""
from __future__ import annotations

import datetime as _dt
import json
import os
import re
import tempfile
from dataclasses import dataclass, replace
from typing import Any, Callable, Dict, List, Optional

FLOOR_MAX_TOKENS = 4_096
_TRUTHY = ("1", "true", "yes", "on")


@dataclass(frozen=True)
class CeilingDecision:
    value: int
    basis: str  # calibrated | probed | derived | observed | i1 | guard | legacy
    calibrated: bool
    probed: Optional[int]
    derived: Optional[int]
    observed: Optional[int] = None
    policy: str = "probed"


@dataclass(frozen=True)
class MaxTokensFit:
    max_tokens: Optional[int]  # None ⇒ even the floor does not fit
    shrunk_from: Optional[int]


def policy_from_env() -> str:
    """``legacy`` (kill switch wins) | ``derived`` (opt-in) | ``probed`` (default)."""
    if os.environ.get("LOA_CHEVAL_LEGACY_CEILING", "").strip().lower() in _TRUTHY:
        return "legacy"
    if os.environ.get("LOA_CHEVAL_UNCALIBRATED_CEILING", "").strip().lower() == "derived":
        return "derived"
    return "probed"


def _pos_int(value: Any) -> Optional[int]:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        return None
    return value


def _guard_from_env() -> Optional[int]:
    raw = os.environ.get("LOA_CHEVAL_MAX_INPUT_TOKENS", "").strip()
    if not raw:
        return None
    try:
        n = int(raw)
    except ValueError:
        return None
    return n if n > 0 else None


def is_calibrated(entry: Dict[str, Any]) -> bool:
    cal = entry.get("ceiling_calibration")
    return isinstance(cal, dict) and bool(cal.get("calibrated_at"))


def input_bound(
    entry: Dict[str, Any],
    *,
    max_tokens: int,
    observed: Optional[int] = None,
    policy: Optional[str] = None,
) -> Optional[CeilingDecision]:
    """The largest input (tokens) this request may carry, with its basis."""
    if not isinstance(entry, dict):
        return None
    ceiling = _pos_int(entry.get("effective_input_ceiling"))
    probed = _pos_int(entry.get("probed_ceiling")) or ceiling
    if ceiling is None and probed is None:
        return None  # v2 entry / CLI hop — no bound from this module
    cw = _pos_int(entry.get("context_window"))
    derived = (cw - int(max_tokens)) if cw else None
    if derived is not None and derived <= 0:
        derived = 0
    policy = policy or policy_from_env()
    calibrated = is_calibrated(entry)

    if policy == "legacy":
        return CeilingDecision(value=ceiling or probed or 0, basis="legacy", calibrated=calibrated,
                               probed=probed, derived=derived, observed=observed, policy=policy)

    if calibrated and ceiling is not None:
        value, basis = ceiling, "calibrated"
    elif policy == "derived" and derived is not None:
        value, basis = derived, "derived"
    else:
        value, basis = (probed or ceiling or 0), "probed"

    if not calibrated and observed is not None and _pos_int(observed) and observed - 1 < value:
        value, basis = observed - 1, "observed"

    if derived is not None and derived < value:  # I1 — never promise more than the window minus the output
        value, basis = derived, "i1"

    guard = _guard_from_env()
    if guard is not None and guard < value:
        value, basis = guard, "guard"

    return CeilingDecision(value=value, basis=basis, calibrated=calibrated, probed=probed,
                           derived=derived, observed=observed, policy=policy)


def fit_max_tokens(*, context_window: int, estimate: int, requested: int) -> MaxTokensFit:
    """I1 auto-shrink: keep ``requested`` when it fits, else the largest budget
    that fits (never below the floor); ``None`` when even the floor does not."""
    if estimate + requested <= context_window:
        return MaxTokensFit(max_tokens=requested, shrunk_from=None)
    room = context_window - estimate
    if room >= FLOOR_MAX_TOKENS:
        return MaxTokensFit(max_tokens=room, shrunk_from=requested)
    if 0 < requested < FLOOR_MAX_TOKENS and room >= requested:
        return MaxTokensFit(max_tokens=requested, shrunk_from=None)
    return MaxTokensFit(max_tokens=None, shrunk_from=requested)


# --- provider context-limit messages (D-1.1b) ---------------------------------

# The two shapes the Anthropic Messages API uses for an oversize request; the
# numbers are the provider's own count, more accurate than any estimate.
_RE_INPUT_ONLY = re.compile(r"(\d[\d,]*)\s+tokens\s*>\s*(\d[\d,]*)\s+maximum", re.I)
_RE_INPUT_PLUS_OUTPUT = re.compile(
    r"input length and\s+`?max_tokens`?\s+exceed context limit:\s*(\d[\d,]*)\s*\+\s*(\d[\d,]*)\s*>\s*(\d[\d,]*)", re.I
)
_CONTEXT_LIMIT_MARKERS = (
    "prompt is too long",
    "too many tokens",
    "exceed context limit",
    "exceeds the context",
    "exceeds context",
    "context length",
    "context window",
    "maximum context",
    "input length",
    "request_too_large",
    "request too large",
)


def is_context_limit_message(message: str) -> bool:
    """True when a provider error message is of the prompt-too-long class."""
    low = (message or "").lower()
    return any(marker in low for marker in _CONTEXT_LIMIT_MARKERS)


def _num(text: str) -> int:
    return int(text.replace(",", ""))


def parse_context_limit(message: str) -> Dict[str, Optional[int]]:
    """Numbers stated by a provider context-limit message.

    Returns ``{input_tokens, limit, max_tokens}`` (each ``None`` when the
    message does not state it). ``max_tokens`` is set only for the
    ``input + max_tokens > limit`` shape — the one a smaller output budget
    can still satisfy.
    """
    out: Dict[str, Optional[int]] = {"input_tokens": None, "limit": None, "max_tokens": None}
    m = _RE_INPUT_PLUS_OUTPUT.search(message or "")
    if m:
        out["input_tokens"], out["max_tokens"], out["limit"] = _num(m.group(1)), _num(m.group(2)), _num(m.group(3))
        return out
    m = _RE_INPUT_ONLY.search(message or "")
    if m:
        out["input_tokens"], out["limit"] = _num(m.group(1)), _num(m.group(2))
    return out


# --- the observed-bound store (.run/ceiling-observed.json) --------------------

OBSERVED_PATH_ENV = "LOA_CHEVAL_CEILING_OBSERVED_PATH"
_OBSERVED_BASENAME = os.path.join(".run", "ceiling-observed.json")
PROBE_COMMAND = "python3 tools/ceiling-probe-live.py --model {model} --write-catalog"
# Only a provider's context verdict lowers the bound; other recorded classes
# (a 429 above the probed bound) are calibration signals, not bounds.
BOUND_LOWERING_CLASSES = frozenset({"CEILING_UNVERIFIED_LIMIT", "PROVIDER_CONTEXT_LIMIT"})


def observed_store_path() -> str:
    """``$LOA_CHEVAL_CEILING_OBSERVED_PATH`` (tests / operator redirect), else
    ``<repo root>/.run/ceiling-observed.json``."""
    override = os.environ.get(OBSERVED_PATH_ENV, "").strip()
    if override:
        return override
    # Same rule as audit/modelinv._resolve_log_path: the repo root is fixed
    # relative to this module (.claude/adapters/loa_cheval/routing/), so a
    # cheval invoked from a subdirectory does not fork the store.
    here = os.path.abspath(__file__)
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(here)))))
    return os.path.join(root, _OBSERVED_BASENAME)


def load_observed(path: Optional[str] = None) -> Dict[str, Any]:
    """The store as a dict ``{"version": 1, "entries": [...]}``; empty on a
    missing or malformed file (never raises — the gate must not fail closed
    on a bad state file)."""
    path = path or observed_store_path()
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return {"version": 1, "entries": []}
    if not isinstance(data, dict) or not isinstance(data.get("entries"), list):
        return {"version": 1, "entries": []}
    return data


def observed_for(provider: str, model: str, data: Optional[Dict[str, Any]] = None) -> Optional[int]:
    """The tightest observed input for an entry: the smallest
    ``observed_input_tokens`` a provider refused, or ``provider_limit + 1``
    when the provider stated its limit (so the bound becomes the limit)."""
    data = data if data is not None else load_observed()
    best: Optional[int] = None
    for row in data.get("entries", []):
        if not isinstance(row, dict) or row.get("provider") != provider or row.get("model") != model:
            continue
        if row.get("error_class") not in BOUND_LOWERING_CLASSES:
            continue  # e.g. RATE_LIMIT_UNVERIFIED: recorded for calibration, never a bound
        candidates: List[int] = []
        obs = _pos_int(row.get("observed_input_tokens"))
        if obs:
            candidates.append(obs)
        lim = _pos_int(row.get("provider_limit"))
        if lim:
            candidates.append(lim + 1)
        for c in candidates:
            if best is None or c < best:
                best = c
    return best


def record_observed(
    *,
    provider: str,
    model: str,
    observed_input_tokens: int,
    error_class: str,
    estimated_input_tokens: Optional[int] = None,
    provider_limit: Optional[int] = None,
    path: Optional[str] = None,
) -> Dict[str, Any]:
    """Append one observation atomically (write-to-temp + ``os.replace``)
    and return the row. The store is append-only history; ``observed_for``
    reduces it. The parent directory is created (``.run/`` may not exist on a
    fresh mount)."""
    path = path or observed_store_path()
    data = load_observed(path)
    row = {
        "provider": provider,
        "model": model,
        "observed_input_tokens": int(observed_input_tokens),
        "estimated_input_tokens": estimated_input_tokens,
        "provider_limit": provider_limit,
        "error_class": error_class,
        "ts": _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "calibrate": PROBE_COMMAND.format(model=model),
    }
    data.setdefault("entries", []).append(row)
    data["version"] = 1
    directory = os.path.dirname(os.path.abspath(path)) or "."
    os.makedirs(directory, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".ceiling-observed.", suffix=".tmp", dir=directory)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(data, fh, indent=2, sort_keys=True)
            fh.write("\n")
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    return row


# --- the gate decision (D-1.1 / D-1.4) ----------------------------------------

@dataclass(frozen=True)
class GateEstimate:
    """What the gate knows about the input size (``base.estimate_input``
    produces the heuristic form; the count endpoint replaces it)."""
    tokens: int
    method: str = "heuristic"      # heuristic | tiktoken | count_tokens
    uncertainty: str = "low"       # low | high | none (a provider count)
    chars: int = 0

    def as_envelope(self) -> Dict[str, Any]:
        return {"method": self.method, "chars": self.chars, "tokens": self.tokens, "uncertainty": self.uncertainty}


@dataclass(frozen=True)
class GateOutcome:
    action: str                    # dispatch | warn | preempt
    reason: str
    estimate: GateEstimate
    decision: Optional[CeilingDecision]
    bound: Optional[int]           # the bound compared against (after the CLI override)
    basis: Optional[str]
    max_tokens: int                # the output budget after I1
    shrunk_from: Optional[int]
    unverified: bool = False       # dispatching above the probed bound (opt-in zone)
    policy: str = "probed"

    def as_envelope(self) -> Dict[str, Any]:
        d = self.decision
        return {
            "preflight_decision": self.action,
            "ceiling_policy": self.policy,
            "input_ceiling": None if d is None else {
                "value": self.bound, "basis": self.basis, "calibrated": d.calibrated,
                "probed": d.probed, "derived": d.derived, "observed": d.observed,
            },
            "estimator": self.estimate.as_envelope(),
            "max_tokens_shrunk": None if self.shrunk_from is None else {"from": self.shrunk_from, "to": self.max_tokens},
            "ceiling_unverified": self.unverified,
        }


COUNT_NEAR_BOUND = 0.9


def gate(
    entry: Dict[str, Any],
    *,
    estimate: GateEstimate,
    requested_max_tokens: int,
    cli_override: Optional[int] = None,
    observed: Optional[int] = None,
    policy: Optional[str] = None,
    counter: Optional[Callable[[], Optional[int]]] = None,
) -> GateOutcome:
    """Decide dispatch / warn / preempt for the head entry.

    Order: I1 (shrink the output budget to fit the window; preempt only when
    the 4,096 floor does not fit) → I2 bound (``input_bound``; the CLI
    override lowers it) → near the bound, a provider count replaces the
    estimate when ``counter`` is given → compare. Above the probed bound but
    under the derived one (reachable only under the opt-in) a count or a
    ``low`` estimate ``warn``s, a ``high`` estimate ``preempt``s with the
    calibration command. ``legacy`` policy: no I1, no count, the literal.
    """
    policy = policy or policy_from_env()
    max_tokens = int(requested_max_tokens)
    shrunk_from: Optional[int] = None
    cw = _pos_int(entry.get("context_window")) if isinstance(entry, dict) else None

    def _out(action: str, reason: str, decision: Optional[CeilingDecision], bound: Optional[int],
             basis: Optional[str], est: GateEstimate, unverified: bool = False) -> GateOutcome:
        return GateOutcome(action=action, reason=reason, estimate=est, decision=decision, bound=bound,
                           basis=basis, max_tokens=max_tokens, shrunk_from=shrunk_from,
                           unverified=unverified, policy=policy)

    if policy != "legacy" and cw:
        fit = fit_max_tokens(context_window=cw, estimate=estimate.tokens, requested=max_tokens)
        if fit.max_tokens is None:
            return _out("preempt", f"I1: estimated {estimate.tokens} input tokens + the {FLOOR_MAX_TOKENS} output floor "
                        f"exceed context_window {cw}", None, None, "i1", estimate)
        if fit.shrunk_from is not None:
            max_tokens, shrunk_from = fit.max_tokens, fit.shrunk_from

    decision = input_bound(entry, max_tokens=max_tokens, observed=observed, policy=policy)
    if decision is None:
        if cli_override is not None and 0 < int(cli_override) < estimate.tokens:
            return _out("preempt", f"estimated {estimate.tokens} input tokens > {int(cli_override)} "
                        f"(--max-input-tokens)", None, int(cli_override), "cli_override", estimate)
        return _out("dispatch", "no input bound for this entry", None, None, None, estimate)
    bound, basis = decision.value, decision.basis
    if cli_override is not None and 0 < int(cli_override) < bound:
        bound, basis = int(cli_override), "cli_override"

    est = estimate
    probed = decision.probed
    in_unverified_zone = bool(policy == "derived" and not decision.calibrated and probed and est.tokens > probed)
    # D-1.4: near the bound — or anywhere in the unverified zone, where the
    # count settles a `high` estimate — the provider's count is authoritative.
    if policy != "legacy" and counter is not None and (est.tokens >= COUNT_NEAR_BOUND * bound or in_unverified_zone):
        counted = counter()
        if _pos_int(counted):
            est = replace(est, tokens=int(counted), method="count_tokens", uncertainty="none")

    if est.tokens > bound:
        return _out("preempt", f"estimated {est.tokens} input tokens > {bound} input bound ({basis})",
                    decision, bound, basis, est)

    if policy == "derived" and not decision.calibrated and probed and est.tokens > probed:
        model = entry.get("model_id") or entry.get("_model_id") or "<model>"
        if est.method == "count_tokens" or est.uncertainty == "low":
            return _out("warn", f"estimated {est.tokens} input tokens above the probed bound {probed} "
                        f"(uncalibrated; {est.method}, uncertainty {est.uncertainty}) — proceeding under the "
                        f"derived bound {bound}; calibrate: {PROBE_COMMAND.format(model=model)}",
                        decision, bound, basis, est, unverified=True)
        return _out("preempt", f"estimated {est.tokens} input tokens above the probed bound {probed} with a "
                    f"high-uncertainty estimate ({est.method}); calibrate first: "
                    f"{PROBE_COMMAND.format(model=model)}", decision, bound, basis, est)
    return _out("dispatch", "under the input bound", decision, bound, basis, est)
