#!/usr/bin/env python3
"""cycle-109 Sprint 1 T1.9 — overlay/override conflict lint (SDD §3.5.2).

Surfaces (model, role) pairs where the L1 ``model_overlay`` layer
(operator config-level model-config.yaml override) disagrees with the
L3 ``kf_auto_link.overrides[]`` layer (operator override of KF
auto-link decisions).

Conflict shapes:

* Overlay's ``recommended_for`` INCLUDES role X and the override
  declares ``force_remove`` for the same (model, X).
* Overlay's ``recommended_for`` EXCLUDES role X and the override
  declares ``force_retain`` for the same (model, X).

Non-conflict shapes:

* Overlay agrees with the override's direction (include/retain or
  exclude/remove).
* Overlay does not declare ``recommended_for`` for the targeted
  (model, role) — the override is then the sole decision.
* No overlay block or no overrides.

Exit codes:
  0 — no conflicts.
  1 — conflicts found (printed to stderr; full report on stdout in
      ``--json`` mode).
  2 — usage / config error.

CI usage: invoke as a pre-merge gate on any PR touching
``.loa.config.yaml::model_overlay`` or
``.loa.config.yaml::kf_auto_link.overrides``.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any, Dict, List, Optional

try:
    import yaml
except ImportError:  # pragma: no cover
    print("[lint-overlay-override-conflict] FATAL: PyYAML required.", file=sys.stderr)
    raise


@dataclass
class Conflict:
    model: str
    role: str
    overlay_recommended_for: List[str]
    override_decision: str
    override_authorized_by: Optional[str]
    explanation: str


def _walk_overlay_models(overlay: Dict[str, Any]):
    """Yield (provider, model_id, model_entry) tuples from the overlay block."""
    if not isinstance(overlay, dict):
        return
    providers = overlay.get("providers", {})
    if not isinstance(providers, dict):
        return
    for provider, prov_block in providers.items():
        if not isinstance(prov_block, dict):
            continue
        models = prov_block.get("models", {})
        if not isinstance(models, dict):
            continue
        for model_id, model_entry in models.items():
            if isinstance(model_entry, dict):
                yield provider, model_id, model_entry


def find_conflicts(config: Dict[str, Any]) -> List[Conflict]:
    overlay = config.get("model_overlay", {}) if isinstance(config, dict) else {}
    kf_block = config.get("kf_auto_link", {}) if isinstance(config, dict) else {}
    overrides = kf_block.get("overrides", []) if isinstance(kf_block, dict) else []
    if not isinstance(overrides, list):
        overrides = []

    # Map (model_id) → overlay recommended_for list (None if not declared).
    overlay_index: Dict[str, Optional[List[str]]] = {}
    for _provider, model_id, model_entry in _walk_overlay_models(overlay):
        rec = model_entry.get("recommended_for")
        if isinstance(rec, list):
            overlay_index[model_id] = [str(x) for x in rec]
        else:
            overlay_index[model_id] = None

    conflicts: List[Conflict] = []
    for entry in overrides:
        if not isinstance(entry, dict):
            continue
        model = entry.get("model")
        role = entry.get("role")
        decision = str(entry.get("decision", "")).strip()
        if not isinstance(model, str) or not isinstance(role, str):
            continue
        if decision not in ("force_retain", "force_remove"):
            continue
        if model not in overlay_index:
            # Overlay silent on this model — override is sole authority.
            continue
        overlay_recommended_for = overlay_index[model]
        if overlay_recommended_for is None:
            # Overlay declares the model but not its recommended_for —
            # treat as silent on the role.
            continue
        in_overlay = role in overlay_recommended_for
        if decision == "force_retain" and not in_overlay:
            conflicts.append(Conflict(
                model=model,
                role=role,
                overlay_recommended_for=list(overlay_recommended_for),
                override_decision=decision,
                override_authorized_by=entry.get("authorized_by"),
                explanation=(
                    f"Overlay omits role {role!r} from recommended_for "
                    f"but kf_auto_link override force_retain insists on "
                    f"keeping it. The two layers disagree."
                ),
            ))
        elif decision == "force_remove" and in_overlay:
            conflicts.append(Conflict(
                model=model,
                role=role,
                overlay_recommended_for=list(overlay_recommended_for),
                override_decision=decision,
                override_authorized_by=entry.get("authorized_by"),
                explanation=(
                    f"Overlay includes role {role!r} in recommended_for "
                    f"but kf_auto_link override force_remove insists on "
                    f"dropping it. The two layers disagree."
                ),
            ))
    return conflicts


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="cycle-109 T1.9 — overlay/override conflict lint (SDD §3.5.2).",
    )
    parser.add_argument(
        "--config",
        required=True,
        type=Path,
        help="Path to .loa.config.yaml (the file declaring both "
             "model_overlay and kf_auto_link.overrides).",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit a structured JSON report on stdout instead of "
             "the human-readable summary.",
    )
    args = parser.parse_args(argv)

    if not args.config.is_file():
        print(
            f"[lint-overlay-override-conflict] config not found: {args.config}",
            file=sys.stderr,
        )
        return 2

    try:
        config = yaml.safe_load(args.config.read_text(encoding="utf-8")) or {}
    except yaml.YAMLError as e:
        print(f"[lint-overlay-override-conflict] YAML parse error: {e}", file=sys.stderr)
        return 2

    conflicts = find_conflicts(config)

    if args.json:
        report = {
            "config": str(args.config),
            "conflicts": [asdict(c) for c in conflicts],
            "conflict_count": len(conflicts),
        }
        print(json.dumps(report, indent=2, ensure_ascii=False))
    else:
        if not conflicts:
            print(f"[lint-overlay-override-conflict] no conflicts in {args.config}")
        else:
            print(
                f"[lint-overlay-override-conflict] {len(conflicts)} CONFLICT(S) "
                f"in {args.config}:",
                file=sys.stderr,
            )
            for c in conflicts:
                print(
                    f"  - model={c.model} role={c.role} "
                    f"override={c.override_decision} "
                    f"authorized_by={c.override_authorized_by}",
                    file=sys.stderr,
                )
                print(f"    overlay.recommended_for={c.overlay_recommended_for}", file=sys.stderr)
                print(f"    {c.explanation}", file=sys.stderr)

    return 0 if not conflicts else 1


if __name__ == "__main__":
    sys.exit(main())
