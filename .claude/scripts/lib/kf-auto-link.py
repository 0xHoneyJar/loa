#!/usr/bin/env python3
"""cycle-109 Sprint 1 T1.5 — KF-auto-link script (SDD §1.4.3, PRD §FR-1.5).

Parses ``grimoires/loa/known-failures.md`` for KF entries that reference
specific (provider, model_id) pairs, and applies the IMP-001 severity-to-
downgrade mapping to ``model-config.yaml``:

    | KF status               | Effect on recommended_for                  |
    |-------------------------|--------------------------------------------|
    | OPEN                    | Remove all roles                           |
    | RESOLVED                | No change                                  |
    | RESOLVED-VIA-WORKAROUND | Remove only the role named in **Role**     |
    | RESOLVED-STRUCTURAL     | No change                                  |
    | LATENT / LAYER-N-LATENT | Remove role named in **Role** (if any)     |
    | DEGRADED-ACCEPTED       | No change (informational only)             |

`failure_modes_observed` accumulates KF IDs for entries that triggered any
degradation, plus all OPEN / LATENT entries even when no role is removed.

The script is **idempotent** (NFR-Rel-3): running twice on the same ledger
state produces a byte-identical ``model-config.yaml``. Recommended_for
lists are recomputed from the union of the canonical allow-all baseline +
override-retained roles minus KF-removed roles, so the final shape is a
function of the (KF ledger, override config) pair rather than the prior
recommended_for value.

Operator overrides (T1.5 stub, T1.6 hardens):
- ``.loa.config.yaml::kf_auto_link.overrides[]`` consulted per (model, role).
- A ``force_retain`` decision for (model, role) inserts the role into the
  effective recommended_for set even if a KF would have removed it.
- A ``force_remove`` decision removes the role unconditionally.
- T1.6 will add SKP-004 conditional precedence: ``effective_until``
  expiry check, ``kf_references[]`` validation against the ledger,
  ``authorized_by`` resolution via OPERATORS.md, and break-glass gating
  for OPEN CRITICAL KFs.

IMP-005 parsing policy:
- Unknown status → stderr warning + skip the entry (exit 0).
- Empty / missing Model → no-op skip.
- Malformed entry (empty Status field, missing required fields, etc.)
  → exit 2 with a line reference.
- Multiple Model values comma-separated → processed independently.
- Duplicate KF IDs → exit 2.

Audit log entries are appended to ``.run/kf-auto-link.jsonl`` (one entry
per (kf_id, model) decision). T1.5 emits a plain JSON line; cycle-098
signed audit envelope wrapping is wired in via T1.6 audit-trust closure.

Usage:
    kf-auto-link.py \\
        --known-failures grimoires/loa/known-failures.md \\
        --model-config .claude/defaults/model-config.yaml \\
        --loa-config .loa.config.yaml \\
        --audit-log .run/kf-auto-link.jsonl

Exit codes:
    0 — success (zero or more decisions applied)
    2 — malformed KF entry / duplicate KF IDs / config error
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import re
import sys
from collections import OrderedDict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

try:
    import yaml
except ImportError as e:  # pragma: no cover - hard dependency
    print(
        "[kf-auto-link] FATAL: PyYAML not installed (required for "
        "model-config.yaml read/write).",
        file=sys.stderr,
    )
    raise

# Canonical role allowlist (SKP-004 v5 closure — allow-all default).
ALLOW_ALL_ROLES: Tuple[str, ...] = (
    "review", "audit", "implementation", "dissent", "arbiter",
)

# Canonical IMP-001 status enum. KF Status fields in known-failures.md
# may carry parenthetical dates and qualifier text after the canonical
# token; the parser extracts the canonical token by longest-prefix match.
STATUS_OPEN = "OPEN"
STATUS_RESOLVED = "RESOLVED"
STATUS_RESOLVED_WORKAROUND = "RESOLVED-VIA-WORKAROUND"
STATUS_RESOLVED_STRUCTURAL = "RESOLVED-STRUCTURAL"
STATUS_LATENT = "LATENT"
STATUS_DEGRADED_ACCEPTED = "DEGRADED-ACCEPTED"

# Status tokens are checked in descending specificity so the longer
# composite tokens win over their substring prefixes.
_STATUS_TOKENS: Tuple[str, ...] = (
    STATUS_RESOLVED_WORKAROUND,
    STATUS_RESOLVED_STRUCTURAL,
    STATUS_DEGRADED_ACCEPTED,
    STATUS_OPEN,
    STATUS_RESOLVED,
    STATUS_LATENT,  # also matches LAYER-N-LATENT via _classify_status
)


@dataclass
class KFEntry:
    kf_id: str
    line_no: int
    status_raw: str
    status_canonical: Optional[str]
    model_refs: List[Tuple[str, str]]  # [(provider, model_id), ...]
    role: Optional[str]
    body: str


# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------

_KF_HEADER_RE = re.compile(r"^##\s+(KF-\d+):", re.MULTILINE)


def _classify_status(raw: str) -> Optional[str]:
    """Map a raw Status field to a canonical IMP-001 token.

    Returns None for unrecognized status strings (caller emits warning
    per IMP-005 and skips the entry).
    """
    if not raw:
        return None
    upper = raw.upper()
    # LAYER-N-LATENT → LATENT family
    if re.search(r"\bLAYER[-\s]?\d+[-\s]?LATENT\b", upper):
        return STATUS_LATENT
    if re.search(r"\bLAYERS?[-\s].*LATENT\b", upper):
        return STATUS_LATENT
    # Longest-prefix-first match.
    for token in _STATUS_TOKENS:
        # Word-boundary match — the token must appear as a contiguous
        # uppercase run, not as a substring of a longer identifier.
        pattern = r"\b" + re.escape(token) + r"\b"
        if re.search(pattern, upper):
            return token
    # Some entries carry composite forms like
    #   LAYERS-2-AND-3-RESOLVED-STRUCTURAL
    # which we treat as RESOLVED-STRUCTURAL (the meaningful tail). The
    # earlier regex pass would have already matched on the canonical
    # token; this branch handles only the unrecognized tail.
    return None


def _parse_field(body: str, name: str) -> Optional[str]:
    """Extract a ``**Name**:`` field value from a KF entry body.

    Returns the trimmed value, or None when the field is absent.
    Empty values (``**Name**:``) return the empty string — the caller
    decides whether that's a malformed-entry condition or an explicit
    skip signal.
    """
    # Restrict whitespace after the colon to non-newline so an empty
    # field doesn't accidentally swallow the next line's content.
    pattern = rf"\*\*{re.escape(name)}\*\*[ \t]*:[ \t]*([^\n]*)"
    m = re.search(pattern, body)
    if m is None:
        return None
    return m.group(1).strip()


def _parse_model_refs(value: Optional[str]) -> List[Tuple[str, str]]:
    """Parse a ``**Model**:`` field value into [(provider, model_id), ...].

    Accepts comma-separated entries of the form ``provider:model_id``.
    Returns an empty list when the value is None, empty, or contains no
    parseable entries (the caller treats this as the no-op skip path per
    IMP-005).
    """
    if not value:
        return []
    refs: List[Tuple[str, str]] = []
    for token in value.split(","):
        token = token.strip()
        if not token:
            continue
        if ":" not in token:
            continue
        provider, model_id = token.split(":", 1)
        provider = provider.strip()
        model_id = model_id.strip()
        if provider and model_id:
            refs.append((provider, model_id))
    return refs


def parse_known_failures(text: str) -> List[KFEntry]:
    """Parse a known-failures.md document into KFEntry records.

    Each entry starts at a ``## KF-NNN:`` header; the body extends to
    the next header or EOF. The Status / Model / Role fields are
    extracted from the body via the standard ``**Field**:`` markdown
    convention.

    Raises ValueError on:
      - Duplicate KF IDs (IMP-005 rule 5)
      - Empty Status field (IMP-005 rule 3 — malformed entry)

    Unknown status tokens are NOT raised; the caller decides whether to
    warn-and-skip (IMP-005 rule 1).
    """
    lines = text.splitlines(keepends=True)
    # Find header positions.
    header_positions: List[Tuple[int, int, str]] = []  # (line_no, char_offset, kf_id)
    char_offset = 0
    for lineno, raw in enumerate(lines, start=1):
        m = re.match(r"^##\s+(KF-\d+):", raw)
        if m:
            header_positions.append((lineno, char_offset, m.group(1)))
        char_offset += len(raw)
    # Slice into per-entry bodies.
    entries: List[KFEntry] = []
    seen_ids: Dict[str, int] = {}
    for idx, (lineno, offset, kf_id) in enumerate(header_positions):
        if kf_id in seen_ids:
            raise ValueError(
                f"duplicate KF ID {kf_id!r} at line {lineno} "
                f"(first occurrence at line {seen_ids[kf_id]})"
            )
        seen_ids[kf_id] = lineno
        end = header_positions[idx + 1][1] if idx + 1 < len(header_positions) else len(text)
        body = text[offset:end]

        status_raw = _parse_field(body, "Status")
        if status_raw is None or status_raw == "":
            raise ValueError(
                f"malformed KF entry {kf_id!r} at line {lineno}: "
                f"Status field is empty or missing"
            )
        status_canonical = _classify_status(status_raw)

        model_raw = _parse_field(body, "Model")
        model_refs = _parse_model_refs(model_raw)

        role_raw = _parse_field(body, "Role")
        role = role_raw.strip().lower() if role_raw else None

        entries.append(KFEntry(
            kf_id=kf_id,
            line_no=lineno,
            status_raw=status_raw,
            status_canonical=status_canonical,
            model_refs=model_refs,
            role=role,
            body=body,
        ))
    return entries


# ---------------------------------------------------------------------------
# Severity-to-downgrade engine (IMP-001)
# ---------------------------------------------------------------------------

@dataclass
class Decision:
    kf_id: str
    provider: str
    model_id: str
    status_canonical: Optional[str]
    status_raw: str
    role_in_kf: Optional[str]
    role_removed: Optional[str]
    record_failure_mode: bool
    note: str


def decide_for_entry(
    entry: KFEntry,
    provider: str,
    model_id: str,
) -> Decision:
    """Apply IMP-001 mapping for one (entry, model) pair.

    Returns a Decision describing whether a role is removed and whether
    the KF id should be appended to failure_modes_observed.
    """
    status = entry.status_canonical
    role = entry.role
    if status == STATUS_OPEN:
        return Decision(
            kf_id=entry.kf_id, provider=provider, model_id=model_id,
            status_canonical=status, status_raw=entry.status_raw,
            role_in_kf=role, role_removed="__ALL__",
            record_failure_mode=True,
            note="OPEN — remove all roles from recommended_for",
        )
    if status in (STATUS_RESOLVED, STATUS_RESOLVED_STRUCTURAL):
        return Decision(
            kf_id=entry.kf_id, provider=provider, model_id=model_id,
            status_canonical=status, status_raw=entry.status_raw,
            role_in_kf=role, role_removed=None,
            record_failure_mode=False,
            note=f"{status} — no degradation",
        )
    if status == STATUS_RESOLVED_WORKAROUND:
        return Decision(
            kf_id=entry.kf_id, provider=provider, model_id=model_id,
            status_canonical=status, status_raw=entry.status_raw,
            role_in_kf=role, role_removed=role,
            record_failure_mode=True,
            note=(
                f"RESOLVED-VIA-WORKAROUND — remove role '{role}'"
                if role else
                "RESOLVED-VIA-WORKAROUND — no Role field; no role removed"
            ),
        )
    if status == STATUS_LATENT:
        return Decision(
            kf_id=entry.kf_id, provider=provider, model_id=model_id,
            status_canonical=status, status_raw=entry.status_raw,
            role_in_kf=role, role_removed=role,
            record_failure_mode=True,
            note=(
                f"LATENT — remove role '{role}'"
                if role else
                "LATENT — no Role field; degradation recorded only"
            ),
        )
    if status == STATUS_DEGRADED_ACCEPTED:
        return Decision(
            kf_id=entry.kf_id, provider=provider, model_id=model_id,
            status_canonical=status, status_raw=entry.status_raw,
            role_in_kf=role, role_removed=None,
            record_failure_mode=False,
            note="DEGRADED-ACCEPTED — informational only",
        )
    return Decision(
        kf_id=entry.kf_id, provider=provider, model_id=model_id,
        status_canonical=None, status_raw=entry.status_raw,
        role_in_kf=role, role_removed=None,
        record_failure_mode=False,
        note=f"unknown status {entry.status_raw!r} — skip per IMP-005",
    )


# ---------------------------------------------------------------------------
# Overrides — SKP-004 conditional precedence (T1.6).
# ---------------------------------------------------------------------------

# Caps per PRD §FR-1.5 IMP-002 / SDD §3.5.1.
OVERRIDE_EFFECTIVE_UNTIL_MAX_DAYS = 90
BREAK_GLASS_EXPIRY_MAX_HOURS = 24
BREAK_GLASS_REASON_MIN_LEN = 16


@dataclass
class OverrideMatch:
    decision: str  # 'force_retain' | 'force_remove'
    reason: str
    authorized_by: Optional[str]
    break_glass_operator: Optional[str] = None


@dataclass
class OverrideEvaluation:
    """Result of evaluating a (model, role) override against SKP-004 gates."""
    matched: bool
    accepted: bool
    match: Optional[OverrideMatch]
    rejection_reason: Optional[str]
    raw_override: Optional[Dict[str, Any]]


def _parse_iso_or_none(value: Optional[Any]) -> Optional[datetime.datetime]:
    if not isinstance(value, str) or not value.strip():
        return None
    raw = value.strip()
    if raw.endswith("Z"):
        raw = raw[:-1] + "+00:00"
    try:
        dt = datetime.datetime.fromisoformat(raw)
    except (ValueError, TypeError):
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=datetime.timezone.utc)
    return dt


def _load_operator_slugs(operators_path: Optional[Path]) -> Set[str]:
    """Parse OPERATORS.md frontmatter and return the set of ACTIVE
    operator IDs (active_until missing or in the future).

    Returns an empty set when the file is missing or malformed; the
    caller treats that state as 'no operator slug resolves'.
    """
    if operators_path is None or not operators_path.is_file():
        return set()
    text = operators_path.read_text(encoding="utf-8")
    # Extract YAML frontmatter between the first two '---' delimiters.
    lines = text.splitlines()
    fm_lines: List[str] = []
    started = False
    for line in lines:
        if line.strip() == "---":
            if not started:
                started = True
                continue
            else:
                break
        if started:
            fm_lines.append(line)
    if not fm_lines:
        return set()
    try:
        parsed = yaml.safe_load("\n".join(fm_lines)) or {}
    except yaml.YAMLError:
        return set()
    operators = parsed.get("operators", [])
    if not isinstance(operators, list):
        return set()
    active: Set[str] = set()
    now = datetime.datetime.now(datetime.timezone.utc)
    for entry in operators:
        if not isinstance(entry, dict):
            continue
        slug = entry.get("id")
        if not isinstance(slug, str) or not slug:
            continue
        active_until = _parse_iso_or_none(entry.get("active_until"))
        if active_until is not None and active_until < now:
            # Offboarded.
            continue
        active.add(slug)
    return active


def _validate_override(
    entry: Dict[str, Any],
    *,
    valid_kf_ids: Set[str],
    open_kf_ids: Set[str],
    operator_slugs: Set[str],
    now: datetime.datetime,
) -> Tuple[bool, Optional[str]]:
    """Apply SKP-004 conditional-precedence gates to an override entry.

    Returns (accepted, rejection_reason). rejection_reason is None when
    accepted. The reason strings are stable identifiers consumed by
    `tests/integration/kf-override-conditional.bats` substring matches.
    """
    decision = str(entry.get("decision", "")).strip()
    if decision not in ("force_retain", "force_remove"):
        return False, "rejected:decision-invalid"

    # effective_until — REQUIRED, not in past, not > now()+90d.
    effective_until_raw = entry.get("effective_until")
    if effective_until_raw is None:
        return False, "rejected:effective_until-missing"
    effective_until = _parse_iso_or_none(effective_until_raw)
    if effective_until is None:
        return False, "rejected:effective_until-malformed"
    if effective_until < now:
        return False, "rejected:effective_until-past"
    if effective_until > now + datetime.timedelta(days=OVERRIDE_EFFECTIVE_UNTIL_MAX_DAYS):
        return False, "rejected:effective_until-exceeds-90d"

    # kf_references — REQUIRED non-empty; all entries present in ledger.
    refs = entry.get("kf_references")
    if not isinstance(refs, list) or len(refs) == 0:
        return False, "rejected:kf_references-empty"
    for ref in refs:
        if not isinstance(ref, str) or ref not in valid_kf_ids:
            return False, f"rejected:kf_references-unknown:{ref!r}"

    # authorized_by — REQUIRED; resolves via OPERATORS.md.
    authorized_by = entry.get("authorized_by")
    if not isinstance(authorized_by, str) or not authorized_by.strip():
        return False, "rejected:authorized_by-missing"
    if authorized_by not in operator_slugs:
        return False, f"rejected:authorized_by-unknown-operator:{authorized_by!r}"

    # Break-glass requirement: force_retain on OPEN KF.
    references_open = any(ref in open_kf_ids for ref in refs)
    is_force_retain = decision == "force_retain"
    break_glass = entry.get("break_glass")

    if is_force_retain and references_open:
        if not isinstance(break_glass, dict):
            return False, "rejected:break_glass-required-for-OPEN-KF"
        bg_operator = break_glass.get("operator_slug")
        if not isinstance(bg_operator, str) or not bg_operator:
            return False, "rejected:break_glass-operator_slug-missing"
        if bg_operator not in operator_slugs:
            return False, f"rejected:break_glass-operator_slug-unknown:{bg_operator!r}"
        bg_reason = break_glass.get("reason")
        if not isinstance(bg_reason, str) or len(bg_reason) < BREAK_GLASS_REASON_MIN_LEN:
            return False, f"rejected:break_glass-reason-min-{BREAK_GLASS_REASON_MIN_LEN}-chars"
        bg_expiry = _parse_iso_or_none(break_glass.get("expiry"))
        if bg_expiry is None:
            return False, "rejected:break_glass-expiry-missing-or-malformed"
        if bg_expiry > now + datetime.timedelta(hours=BREAK_GLASS_EXPIRY_MAX_HOURS):
            return False, f"rejected:break_glass-expiry-exceeds-{BREAK_GLASS_EXPIRY_MAX_HOURS}h"
        if bg_expiry < now:
            return False, "rejected:break_glass-expiry-past"
        audit_event_id = break_glass.get("audit_event_id")
        if not isinstance(audit_event_id, str) or not audit_event_id.strip():
            return False, "rejected:break_glass-audit_event_id-missing"
    elif break_glass is not None and not isinstance(break_glass, dict):
        return False, "rejected:break_glass-malformed"

    return True, None


def evaluate_override(
    overrides: List[Dict[str, Any]],
    model_id: str,
    role: str,
    *,
    valid_kf_ids: Set[str],
    open_kf_ids: Set[str],
    operator_slugs: Set[str],
    now: datetime.datetime,
) -> OverrideEvaluation:
    """Find the first override matching (model_id, role) and evaluate it
    against the SKP-004 conditional-precedence gates.

    Returns an OverrideEvaluation; the caller logs the decision_outcome
    and only applies the override when ``accepted is True``.
    """
    if not overrides:
        return OverrideEvaluation(False, False, None, None, None)
    for entry in overrides:
        if not isinstance(entry, dict):
            continue
        if entry.get("model") != model_id:
            continue
        if entry.get("role") != role:
            continue
        accepted, rejection_reason = _validate_override(
            entry,
            valid_kf_ids=valid_kf_ids,
            open_kf_ids=open_kf_ids,
            operator_slugs=operator_slugs,
            now=now,
        )
        decision = str(entry.get("decision", "")).strip()
        bg = entry.get("break_glass") if isinstance(entry.get("break_glass"), dict) else None
        bg_operator = bg.get("operator_slug") if isinstance(bg, dict) else None
        match = OverrideMatch(
            decision=decision,
            reason=str(entry.get("reason", "")),
            authorized_by=entry.get("authorized_by"),
            break_glass_operator=bg_operator,
        )
        return OverrideEvaluation(
            matched=True,
            accepted=accepted,
            match=match,
            rejection_reason=rejection_reason,
            raw_override=entry,
        )
    return OverrideEvaluation(False, False, None, None, None)


def lookup_override(
    overrides: List[Dict[str, Any]],
    model_id: str,
    role: str,
) -> Optional[OverrideMatch]:
    """Legacy unconditional lookup retained for backward compatibility.

    Callers that need SKP-004 conditional precedence should use
    ``evaluate_override`` instead. This shim preserves the T1.5 surface
    used by older imports; new code paths go through ``evaluate_override``.
    """
    if not overrides:
        return None
    for entry in overrides:
        if not isinstance(entry, dict):
            continue
        if entry.get("model") != model_id:
            continue
        if entry.get("role") != role:
            continue
        decision = str(entry.get("decision", "")).strip()
        if decision not in ("force_retain", "force_remove"):
            continue
        return OverrideMatch(
            decision=decision,
            reason=str(entry.get("reason", "")),
            authorized_by=entry.get("authorized_by"),
        )
    return None


# ---------------------------------------------------------------------------
# Apply
# ---------------------------------------------------------------------------

def apply_decisions(
    model_config: Dict[str, Any],
    decisions: List[Decision],
    overrides: List[Dict[str, Any]],
    *,
    valid_kf_ids: Optional[Set[str]] = None,
    open_kf_ids: Optional[Set[str]] = None,
    operator_slugs: Optional[Set[str]] = None,
    now: Optional[datetime.datetime] = None,
) -> List[Dict[str, Any]]:
    """Mutate ``model_config`` per the accumulated decisions.

    For each (provider, model_id) touched, recompute recommended_for from
    the canonical allow-all baseline minus the union of KF-derived
    removals, then apply overrides on top. The recomputation is what
    makes the script idempotent (NFR-Rel-3): re-running on the same
    inputs yields the same output.

    SKP-004 conditional precedence: each override is evaluated against
    effective_until / kf_references / authorized_by / break_glass gates.
    Rejected overrides do NOT apply; the audit record carries
    ``decision_outcome: rejected:<reason>`` and the KF auto-decision
    falls through. Accepted overrides apply per their direction
    (force_retain inserts; force_remove removes) and the audit record
    carries ``decision_outcome: accepted``.

    Returns the list of audit-log records for the caller to append.
    """
    valid_kf_ids = set(valid_kf_ids or set())
    open_kf_ids = set(open_kf_ids or set())
    operator_slugs = set(operator_slugs or set())
    now = now or datetime.datetime.now(datetime.timezone.utc)
    # Group decisions by (provider, model_id).
    by_model: "OrderedDict[Tuple[str, str], List[Decision]]" = OrderedDict()
    for d in decisions:
        key = (d.provider, d.model_id)
        by_model.setdefault(key, []).append(d)

    audit_records: List[Dict[str, Any]] = []

    for (provider, model_id), model_decisions in by_model.items():
        model_entry = (
            model_config.get("providers", {})
            .get(provider, {})
            .get("models", {})
            .get(model_id)
        )
        if not isinstance(model_entry, dict):
            # Unknown model — skip; record audit row.
            for d in model_decisions:
                audit_records.append(_decision_to_audit(d, None, None, "model-not-in-config"))
            continue

        before_recommended = list(model_entry.get("recommended_for", []))
        before_failure_modes = list(model_entry.get("failure_modes_observed", []))

        # Start from allow-all baseline; apply KF removals; then apply overrides.
        effective: List[str] = list(ALLOW_ALL_ROLES)
        removed_roles: List[str] = []
        failure_modes: List[str] = []

        for d in model_decisions:
            if d.role_removed == "__ALL__":
                removed_roles = list(ALLOW_ALL_ROLES)
            elif d.role_removed:
                if d.role_removed in effective and d.role_removed not in removed_roles:
                    removed_roles.append(d.role_removed)
            if d.record_failure_mode and d.kf_id not in failure_modes:
                failure_modes.append(d.kf_id)

        # Apply KF removals.
        effective = [r for r in effective if r not in removed_roles]

        # SKP-004 conditional-precedence override evaluation. Each
        # (model, role) override is evaluated against the full gate set;
        # only accepted overrides mutate `effective`. Rejected overrides
        # leave the KF auto-decision in place and append a rejection
        # record to the audit log.
        for role in list(ALLOW_ALL_ROLES):
            ev = evaluate_override(
                overrides, model_id, role,
                valid_kf_ids=valid_kf_ids,
                open_kf_ids=open_kf_ids,
                operator_slugs=operator_slugs,
                now=now,
            )
            if not ev.matched:
                continue
            if ev.accepted and ev.match is not None:
                if ev.match.decision == "force_retain" and role not in effective:
                    effective.append(role)
                elif ev.match.decision == "force_remove" and role in effective:
                    effective.remove(role)
                audit_records.append(_override_to_audit(
                    model_id, role, ev, outcome="accepted",
                ))
            else:
                # Rejected — emit a warning and audit the rejection.
                reason = ev.rejection_reason or "rejected:unknown"
                print(
                    f"[kf-override-rejected] model={model_id} role={role} "
                    f"reason={reason}",
                    file=sys.stderr,
                )
                audit_records.append(_override_to_audit(
                    model_id, role, ev, outcome=reason,
                ))

        # Preserve canonical role ordering for byte-stable output.
        effective_ordered = [r for r in ALLOW_ALL_ROLES if r in effective]

        model_entry["recommended_for"] = effective_ordered
        # failure_modes_observed: replace with the freshly-computed list
        # so re-runs produce the same state (idempotency).
        model_entry["failure_modes_observed"] = failure_modes

        # Record audit entries — one per decision.
        for d in model_decisions:
            audit_records.append(_decision_to_audit(
                d,
                before={"recommended_for": before_recommended,
                        "failure_modes_observed": before_failure_modes},
                after={"recommended_for": list(effective_ordered),
                       "failure_modes_observed": list(failure_modes)},
                outcome="applied",
            ))

    return audit_records


def _override_to_audit(
    model_id: str,
    role: str,
    ev: OverrideEvaluation,
    outcome: str,
) -> Dict[str, Any]:
    """Audit record for an SKP-004 override evaluation. ``outcome`` is
    ``accepted`` on acceptance or ``rejected:<reason>`` on rejection."""
    match = ev.match
    raw = ev.raw_override or {}
    kf_refs = raw.get("kf_references") if isinstance(raw, dict) else None
    return {
        "event": "kf-override-evaluation",
        "model": model_id,
        "role": role,
        "decision_outcome": outcome,
        "decision": match.decision if match else None,
        "authorized_by": match.authorized_by if match else None,
        "break_glass_operator_slug": match.break_glass_operator if match else None,
        "kf_references": list(kf_refs) if isinstance(kf_refs, list) else None,
        "reason": match.reason if match else None,
        "rejection_reason": ev.rejection_reason,
        "timestamp": datetime.datetime.now(datetime.timezone.utc)
        .isoformat().replace("+00:00", "Z"),
    }


def _decision_to_audit(
    d: Decision,
    before: Optional[Dict[str, Any]],
    after: Optional[Dict[str, Any]],
    outcome: str,
) -> Dict[str, Any]:
    return {
        "kf_id": d.kf_id,
        "model": f"{d.provider}:{d.model_id}",
        "status_canonical": d.status_canonical,
        "status_raw": d.status_raw,
        "role_in_kf": d.role_in_kf,
        "role_removed": d.role_removed,
        "outcome": outcome,
        "note": d.note,
        "before_state": before,
        "after_state": after,
        "timestamp": datetime.datetime.now(datetime.timezone.utc)
        .isoformat()
        .replace("+00:00", "Z"),
    }


# ---------------------------------------------------------------------------
# Audit log
# ---------------------------------------------------------------------------

def append_audit_log(path: Path, records: List[Dict[str, Any]]) -> None:
    """Append audit records to ``path`` as JSON lines.

    T1.5 emits plain JSON. T1.6 will wrap each record in the cycle-098
    signed audit envelope (Ed25519 + hash-chain).
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as fh:
        for r in records:
            fh.write(json.dumps(r, separators=(",", ":"), ensure_ascii=False))
            fh.write("\n")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _load_yaml(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def _dump_yaml(data: Any, path: Path) -> None:
    with path.open("w", encoding="utf-8") as fh:
        yaml.safe_dump(
            data,
            fh,
            sort_keys=False,
            default_flow_style=None,
            allow_unicode=True,
        )


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="cycle-109 T1.5 — KF-auto-link script (IMP-001 / IMP-005).",
    )
    parser.add_argument(
        "--known-failures",
        required=True,
        type=Path,
        help="Path to known-failures.md ledger.",
    )
    parser.add_argument(
        "--model-config",
        required=True,
        type=Path,
        help="Path to model-config.yaml (v3 schema).",
    )
    parser.add_argument(
        "--loa-config",
        required=True,
        type=Path,
        help="Path to .loa.config.yaml (consulted for kf_auto_link.overrides).",
    )
    parser.add_argument(
        "--audit-log",
        required=True,
        type=Path,
        help="Path to .run/kf-auto-link.jsonl (audit trail).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Compute decisions + emit audit log but do not mutate model-config.yaml.",
    )
    args = parser.parse_args(argv)

    # Load configs.
    if not args.known_failures.is_file():
        print(f"[kf-auto-link] FATAL: known-failures path not a file: {args.known_failures}", file=sys.stderr)
        return 2
    if not args.model_config.is_file():
        print(f"[kf-auto-link] FATAL: model-config path not a file: {args.model_config}", file=sys.stderr)
        return 2
    if not args.loa_config.is_file():
        print(f"[kf-auto-link] FATAL: loa-config path not a file: {args.loa_config}", file=sys.stderr)
        return 2

    text = args.known_failures.read_text(encoding="utf-8")
    try:
        entries = parse_known_failures(text)
    except ValueError as e:
        print(f"[kf-auto-link] ERROR: {e}", file=sys.stderr)
        return 2

    loa_config = _load_yaml(args.loa_config) or {}
    kf_block = loa_config.get("kf_auto_link", {}) if isinstance(loa_config, dict) else {}
    enabled = kf_block.get("enabled", True) if isinstance(kf_block, dict) else True
    overrides = kf_block.get("overrides", []) if isinstance(kf_block, dict) else []
    if not isinstance(overrides, list):
        overrides = []

    if not enabled:
        # IMP-005-adjacent escape hatch — explicit operator opt-out. Emit
        # an audit row noting the no-op and exit clean.
        record = {
            "outcome": "skipped",
            "reason": "kf_auto_link.enabled=false",
            "timestamp": datetime.datetime.now(datetime.timezone.utc)
            .isoformat().replace("+00:00", "Z"),
        }
        append_audit_log(args.audit_log, [record])
        return 0

    model_config = _load_yaml(args.model_config) or {}

    # Build decisions for every (entry, model_ref) pair.
    decisions: List[Decision] = []
    for entry in entries:
        if entry.status_canonical is None:
            print(
                f"[kf-auto-link] WARNING: unknown status {entry.status_raw!r} "
                f"for {entry.kf_id} at line {entry.line_no} — skipping (IMP-005 rule 1)",
                file=sys.stderr,
            )
            continue
        if not entry.model_refs:
            # IMP-005 rule 2 — no-op skip with no warning (entries that
            # don't reference a model are out of scope by design).
            continue
        for provider, model_id in entry.model_refs:
            decisions.append(decide_for_entry(entry, provider, model_id))

    # Build the SKP-004 evaluation context: which KFs exist and which
    # are OPEN (for break-glass requirement). OPERATORS.md is resolved
    # via LOA_OPERATORS_FILE override, falling back to the default path.
    valid_kf_ids: Set[str] = {entry.kf_id for entry in entries}
    open_kf_ids: Set[str] = {
        entry.kf_id for entry in entries
        if entry.status_canonical == STATUS_OPEN
    }
    operators_path_env = os.environ.get("LOA_OPERATORS_FILE")
    if operators_path_env:
        operators_path: Optional[Path] = Path(operators_path_env)
    else:
        operators_path = Path(__file__).resolve().parents[2] / "grimoires" / "loa" / "operators.md"
    operator_slugs = _load_operator_slugs(operators_path)
    now = datetime.datetime.now(datetime.timezone.utc)

    if args.dry_run:
        records = [_decision_to_audit(d, None, None, "dry-run") for d in decisions]
        append_audit_log(args.audit_log, records)
        return 0

    audit_records = apply_decisions(
        model_config,
        decisions,
        overrides,
        valid_kf_ids=valid_kf_ids,
        open_kf_ids=open_kf_ids,
        operator_slugs=operator_slugs,
        now=now,
    )
    _dump_yaml(model_config, args.model_config)
    append_audit_log(args.audit_log, audit_records)
    return 0


if __name__ == "__main__":
    sys.exit(main())
