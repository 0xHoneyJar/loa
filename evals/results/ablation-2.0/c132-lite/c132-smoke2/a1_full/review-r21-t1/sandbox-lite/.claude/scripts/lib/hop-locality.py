#!/usr/bin/env python3
"""hop-locality.py — classify model hops as local or hosted for `hounfour.locality: local_voices` (cycle-129 FR-8,
SDD D-8.0 / D-8.1, DEC-0146).

    python3 -I hop-locality.py --catalog <model-config.yaml> --config <.loa.config.yaml> -- <hop>...

One tab-separated line per hop, in the order given:

    <hop> TAB <provider|unknown> TAB <local|hosted> TAB <reason>

A hop is `local` only when ALL of these hold in the merged view (the System Zone catalog overlaid with the project
config's `hounfour.providers` / `hounfour.aliases`, the two layers cheval merges):
  * it resolves (a `provider:id` pin, an alias chain, or a bare id that exactly one provider declares) to a model entry
    that exists;
  * that model entry, or its provider block, says `dispatch_group: local` (the canonical key, D-8.0);
  * every hop on the entry's own `fallback_chain` is local by the same rule — cheval walks that chain inside one call,
    so a local entry that falls back to a hosted one would leave the declared providers without the planner seeing it.
Everything else is `hosted`: an unresolved hop, an unreadable config, a headless CLI hop (its dispatch group is the
provider family's), the native session. Fail closed — a hop is never called local because it could not be read.

This file reads declarations only: it never dispatches, never reads credentials and never imports the cheval package
(run under `-I`, so neither the cwd nor PYTHONPATH reaches sys.path). The request-time rules for a local hop (IP-literal
or localhost endpoint, no DNS, redirects refused, proxy env ignored, destination logged) are cheval's.
"""
from __future__ import annotations

import argparse
import sys
from typing import Any, Dict, List, Optional, Tuple

MAX_DEPTH = 10


def _merge(base: Any, overlay: Any) -> Any:
    if isinstance(base, dict) and isinstance(overlay, dict):
        out = dict(base)
        for key, value in overlay.items():
            out[key] = _merge(base.get(key), value) if key in base else value
        return out
    return overlay


def load_merged(catalog_path: str, config_path: Optional[str]) -> Dict[str, Any]:
    import yaml

    with open(catalog_path, "r", encoding="utf-8") as fh:
        catalog = yaml.safe_load(fh) or {}
    if not isinstance(catalog, dict):
        raise ValueError("catalog is not a mapping")
    merged: Dict[str, Any] = {k: (catalog.get(k) if isinstance(catalog.get(k), dict) else {})
                              for k in ("providers", "aliases", "backward_compat_aliases")}
    if config_path:
        try:
            with open(config_path, "r", encoding="utf-8") as fh:
                project = yaml.safe_load(fh) or {}
        except FileNotFoundError:
            project = {}
        if not isinstance(project, dict):
            raise ValueError("project config is not a mapping")
        hounfour = project.get("hounfour")
        if isinstance(hounfour, dict):
            for key in ("providers", "aliases"):
                if isinstance(hounfour.get(key), dict):
                    merged[key] = _merge(merged.get(key) or {}, hounfour[key])
    return merged


def _alias_target(name: str, merged: Dict[str, Any]) -> Optional[str]:
    for table in ("aliases", "backward_compat_aliases"):
        target = (merged.get(table) or {}).get(name)
        if isinstance(target, dict):
            target = target.get("target") or target.get("model")
        if isinstance(target, str) and target.strip():
            return target.strip()
    return None


def resolve(hop: str, merged: Dict[str, Any]) -> Optional[Tuple[str, str]]:
    name = (hop or "").strip()
    if not name:
        return None
    current, seen = name, set()
    for _ in range(MAX_DEPTH):
        if ":" in current:
            provider, _, model = current.partition(":")
            return (provider, model) if provider and model else None
        target = _alias_target(current, merged)
        if not target:
            break
        if target in seen:
            return None
        seen.add(current)
        current = target
    if ":" in current:
        provider, _, model = current.partition(":")
        return (provider, model) if provider and model else None
    providers = merged.get("providers") or {}
    matches = [p for p, block in providers.items()
               if isinstance(block, dict) and isinstance(block.get("models"), dict) and current in block["models"]]
    return (matches[0], current) if len(matches) == 1 else None


def classify(hop: str, merged: Dict[str, Any], _depth: int = 0, _seen: Optional[set] = None) -> Tuple[str, str, str]:
    """(provider, locality, reason) for one hop."""
    seen = set(_seen or ())
    target = resolve(hop, merged)
    if target is None:
        return "unknown", "hosted", "unresolved"
    provider, model = target
    block = (merged.get("providers") or {}).get(provider)
    if not isinstance(block, dict):
        return provider, "hosted", "provider_not_declared"
    entry = (block.get("models") or {}).get(model) if isinstance(block.get("models"), dict) else None
    if not isinstance(entry, dict):
        return provider, "hosted", "model_not_declared"
    group = entry.get("dispatch_group") or block.get("dispatch_group") or ""
    if group != "local":
        return provider, "hosted", f"dispatch_group={group or 'unset'}"
    key = f"{provider}:{model}"
    if key in seen:
        return provider, "local", "dispatch_group=local"
    seen.add(key)
    chain = entry.get("fallback_chain") or []
    if not isinstance(chain, list):
        return provider, "hosted", "fallback_chain_unreadable"
    if _depth >= MAX_DEPTH:
        return provider, "hosted", "fallback_chain_too_deep"
    for nxt in chain:
        if not isinstance(nxt, str):
            return provider, "hosted", "fallback_chain_unreadable"
        p2, loc, _ = classify(nxt, merged, _depth + 1, seen)
        if loc != "local":
            return provider, "hosted", f"fallback_chain_reaches_hosted:{nxt}({p2})"
    return provider, "local", "dispatch_group=local"


def _clean(text: str) -> str:
    return "".join(c if c.isprintable() and c not in "\t" else "_" for c in text)[:128]


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--catalog", required=True)
    ap.add_argument("--config", default="")
    ap.add_argument("hops", nargs="*")
    args = ap.parse_args(argv)
    try:
        merged = load_merged(args.catalog, args.config or None)
        err = ""
    except Exception as exc:  # noqa: BLE001 — fail closed: every hop hosted, the reason said once
        merged, err = None, f"{type(exc).__name__}"
        print(f"hop-locality: the merged config could not be read ({err}) — every hop is hosted", file=sys.stderr)
    for hop in args.hops:
        if merged is None:
            print(f"{_clean(hop)}\tunknown\thosted\tconfig_unreadable")
            continue
        provider, loc, reason = classify(hop, merged)
        print(f"{_clean(hop)}\t{_clean(provider)}\t{loc}\t{_clean(reason)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
