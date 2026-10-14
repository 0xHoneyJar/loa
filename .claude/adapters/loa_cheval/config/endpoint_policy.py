"""Per-provider endpoint policy on the cheval Python path (cycle-129 FR-7, SDD D-7.2, D-8.0).

The rule, applied at config load to every HTTP provider in the merged ``hounfour.providers`` view:

* ``allow_insecure_endpoint`` is a host STRING, never a boolean. It must be an IP literal or ``localhost``
  (an insecure endpoint is never resolved through DNS, so there is no rebinding), and the address must be
  loopback (``127.0.0.0/8``, ``::1``) or RFC1918 (``10/8``, ``172.16/12``, ``192.168/16``). Link-local,
  the cloud metadata addresses, unique-local IPv6 and every public range are refused.
* An ``http://`` endpoint is admitted only when its host equals the provider's opt-in host. A mismatched
  host, a public ``http`` host or an ``http`` endpoint without an opt-in fails at load with a named reason.
* Every other endpoint keeps the cycle-099 refusals: ``https`` only, no userinfo, no control bytes or path
  traversal, and no loopback, private, link-local, metadata or otherwise blocked IP literal (``localhost``
  included). One provider's opt-in never changes another provider's checks.
* ``keyless: true`` marks a provider that needs no credential; a literal ``auth: "local"`` is accepted and
  normalised to ``keyless: true`` in the merged view. A keyless provider is admitted only when every model
  declares ``context_window`` and ``dispatch_group``.

ONE implementation: every URL and opt-in decision here is made by the canonical
``.claude/scripts/lib/endpoint-validator.py`` (the module the bash callers and the health probe use),
loaded by path as ``loa_cheval.codegen.emit_endpoint_validator_ts`` does: ``check_insecure_optin`` for the
opt-in and ``validate_declared_endpoint`` (the full pipeline minus the host allowlist, which an
operator-declared https host is not on) for the endpoint. The refusal codes are therefore the validator's
codes, and URL parsing stays confined to that module (the cycle-099 import guard).
``tests/test_endpoint_validator_optin.py`` runs one case table through both entry points.

THE LOCAL-HOP RULE (D-8.1, review round r257-1): a hop is ``local`` only when its provider is an HTTP provider
(not ``kind: cli`` / ``*-headless``) whose endpoint host is an IP literal in a loopback (``127.0.0.0/8``, ``::1``)
or RFC1918 (``10/8``, ``172.16/12``, ``192.168/16``) range, or the literal ``localhost`` — exactly the host
acceptance of the validator's ``check_insecure_optin`` (``local_host`` / ``local_endpoint_host`` below). A
``dispatch_group: local`` on a model entry or the provider block of any other provider is refused at load; an
``https`` endpoint on such a host needs no ``allow_insecure_endpoint`` (an ``http`` one still does). The same rule
is applied at request time (``TransportPolicy.local``), in the planner (``.claude/scripts/lib/hop-locality.py``,
stdlib mirror) and in Bridgebuilder (``config.ts`` ``localEndpointHost``, TypeScript mirror).

Request-time half (``TransportPolicy`` in ``providers/base.py``): for an opted-in provider, or a model whose
``dispatch_group`` is ``local``, the adapter ignores proxy environment variables, refuses HTTP redirects and
requires every request URL to stay under the declared endpoint path; for a local hop the request host must also
pass the local-hop rule.

CLI (used by ``model-health-probe.sh --provider <name>``; reads the merged config, never prints a secret)::

    python3 -m loa_cheval.config.endpoint_policy list-providers [--project-root DIR]
    python3 -m loa_cheval.config.endpoint_policy describe-provider NAME [--project-root DIR]
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sys
import threading
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from loa_cheval.types import ConfigError

# The literal auth values normalised to keyless (D-8.0). Only "local": any other literal could be a real key.
KEYLESS_AUTH_LITERALS = frozenset({"local"})

# .claude/adapters/loa_cheval/config/endpoint_policy.py → .claude/scripts/lib/endpoint-validator.py
_VALIDATOR_PATH = Path(__file__).resolve().parents[3] / "scripts" / "lib" / "endpoint-validator.py"
_VALIDATOR: Any = None
_VALIDATOR_LOCK = threading.Lock()


def _validator() -> Any:
    """The canonical endpoint-validator module, loaded once by path. A missing
    or unloadable validator is a ConfigError (fail-closed: no endpoint is
    admitted unchecked)."""
    global _VALIDATOR
    with _VALIDATOR_LOCK:
        if _VALIDATOR is not None:
            return _VALIDATOR
        name = "loa_endpoint_validator_canonical"
        spec = importlib.util.spec_from_file_location(name, _VALIDATOR_PATH)
        if spec is None or spec.loader is None or not _VALIDATOR_PATH.is_file():
            raise ConfigError(f"[ENDPOINT-VALIDATOR-MISSING] {_VALIDATOR_PATH} not found; reinstall the framework")
        module = importlib.util.module_from_spec(spec)
        sys.modules[name] = module
        try:
            spec.loader.exec_module(module)
        except Exception as exc:  # noqa: BLE001 — any load failure is fail-closed
            sys.modules.pop(name, None)
            raise ConfigError(f"[ENDPOINT-VALIDATOR-MISSING] {_VALIDATOR_PATH} failed to load: {exc}") from exc
        _VALIDATOR = module
        return module


class EndpointPolicyError(ConfigError):
    """A provider endpoint or opt-in refused at load. ``policy_code`` is the endpoint-validator code."""

    def __init__(self, code: str, detail: str, provider: Optional[str] = None):
        where = f"providers.{provider}: " if provider else ""
        super().__init__(f"[{code}] {where}{detail}", context={"policy_code": code, "provider": provider})
        self.policy_code = code
        self.detail = detail


def split_url(url: str) -> Tuple[str, str, Optional[int], str]:
    """(scheme, canonical host, explicit port or None, path) via the canonical validator; ValueError on a bad URL."""
    return _validator().split_url(url)


def canonical_optin_host(value: Any, provider: Optional[str] = None) -> str:
    """Validate an ``allow_insecure_endpoint`` value and return its canonical host, or raise."""
    ok, code, detail, host = _validator().check_insecure_optin(value)
    if not ok:
        raise EndpointPolicyError(code or "ENDPOINT-OPTIN-INVALID", detail or "invalid opt-in", provider)
    return host


def check_endpoint(endpoint: str, allow_insecure_endpoint: Any = None, provider: Optional[str] = None) -> Optional[str]:
    """Apply the D-7.2 rule to one provider's endpoint. Returns the canonical opt-in host (or None); raises."""
    optin = canonical_optin_host(allow_insecure_endpoint, provider) if allow_insecure_endpoint is not None else None
    result = _validator().validate_declared_endpoint(endpoint, allow_insecure_endpoint=optin)
    if not result.valid:
        raise EndpointPolicyError(result.code or "ENDPOINT-INVALID", result.detail or "endpoint refused", provider)
    return optin


# --- the local-hop rule (D-8.1, r257-1) -------------------------------------------------------------------

LOCAL_RULE_TEXT = "a loopback or RFC1918 IP literal or localhost"


def local_host(host: Any) -> Optional[str]:
    """The canonical host when ``host`` passes the local-hop rule, else None. ONE implementation: the
    validator's ``check_insecure_optin`` host acceptance (brackets stripped, IP literals canonicalised)."""
    if not isinstance(host, str) or not host.strip():
        return None
    ok, _code, _detail, canonical = _validator().check_insecure_optin(host)
    return canonical if ok else None


def endpoint_host(endpoint: Any) -> str:
    """The endpoint's canonical host for a refusal message ('' when absent; the raw text when it does not parse)."""
    if not isinstance(endpoint, str) or not endpoint:
        return ""
    try:
        return split_url(endpoint)[1]
    except ValueError:
        return endpoint[:128]


def local_endpoint_host(endpoint: Any) -> Optional[str]:
    """The canonical host when ``endpoint`` is an http(s) URL whose host passes the local-hop rule, else None."""
    if not isinstance(endpoint, str) or not endpoint:
        return None
    try:
        scheme, host, _port, _path = split_url(endpoint)
    except ValueError:
        return None
    if scheme not in ("http", "https"):
        return None
    return local_host(host)


def _local_labels(prov: Dict[str, Any]) -> Tuple[bool, List[str]]:
    """(provider block says local, [model ids whose entry says local])."""
    models = prov.get("models") if isinstance(prov.get("models"), dict) else {}
    return (
        prov.get("dispatch_group") == "local",
        [m for m, entry in models.items() if isinstance(entry, dict) and entry.get("dispatch_group") == "local"],
    )


def _local_label_refusal(name: str, prov: Dict[str, Any]) -> Optional[ConfigError]:
    """The refusal for a ``dispatch_group: local`` (model entry or provider block) the provider cannot honour —
    a CLI provider, or an endpoint host that fails the local-hop rule — or None (not labelled, or it passes)."""
    block_local, local_models = _local_labels(prov)
    if not block_local and not local_models:
        return None
    if _is_cli_provider(prov):
        return ConfigError(f"[CONFIG-INVALID] providers.{name}: dispatch_group local is not admitted on a CLI provider")
    endpoint = prov.get("endpoint")
    if local_endpoint_host(endpoint) is not None:
        return None
    where = f"providers.{name}" if block_local else f"providers.{name}.models.{local_models[0]}"
    shown = endpoint_host(endpoint) or "missing"
    return ConfigError(
        f"[CONFIG-INVALID] {where}: dispatch_group local requires an endpoint on {LOCAL_RULE_TEXT} (host {shown})"
    )


# --- the merged view --------------------------------------------------------------------------------------


def _is_cli_provider(prov: Dict[str, Any]) -> bool:
    ptype = str(prov.get("type") or "")
    if ptype.endswith("-headless"):
        return True
    models = prov.get("models") or {}
    return bool(models) and isinstance(models, dict) and all(
        isinstance(m, dict) and m.get("kind") == "cli" for m in models.values()
    )


def normalise_keyless(merged: Dict[str, Any]) -> None:
    """Pre-interpolation step: a literal ``auth: "local"`` becomes ``keyless: true`` (D-8.0); ``keyless`` must be a bool."""
    providers = merged.get("providers")
    if not isinstance(providers, dict):
        return
    for name, prov in providers.items():
        if not isinstance(prov, dict):
            continue
        if "keyless" in prov and not isinstance(prov["keyless"], bool):
            raise ConfigError(
                f"[CONFIG-INVALID] providers.{name}.keyless must be true or false, got {prov['keyless']!r}"
            )
        auth = prov.get("auth")
        if isinstance(auth, str) and auth.strip().lower() in KEYLESS_AUTH_LITERALS:
            if prov.get("keyless") is False:
                raise ConfigError(
                    f"[CONFIG-INVALID] providers.{name}: keyless: false conflicts with the literal auth "
                    f"\"{auth.strip()}\""
                )
            prov["keyless"] = True


def validate_providers(merged: Dict[str, Any]) -> None:
    """Post-interpolation step: the local-hop rule, the endpoint rule and keyless preconditions for every provider."""
    providers = merged.get("providers")
    if not isinstance(providers, dict):
        return
    for name, prov in providers.items():
        if not isinstance(prov, dict):
            continue
        optin = prov.get("allow_insecure_endpoint")
        endpoint = prov.get("endpoint")
        # D-8.1 (r257-1): a declared locality is enforced, not trusted. The D-7.2 endpoint checks run first (their
        # codes are the more specific reason); a labelled provider they admit is then held to the local-hop rule.
        block_local, local_models = _local_labels(prov)
        labelled = block_local or bool(local_models)
        local = local_endpoint_host(endpoint) if labelled and not _is_cli_provider(prov) else None
        if not _is_cli_provider(prov) and endpoint not in (None, ""):
            if not isinstance(endpoint, str):
                raise ConfigError(f"[CONFIG-INVALID] providers.{name}.endpoint must be a string")
            # (local is set only when the endpoint parsed, so split_url cannot raise here)
            if local is not None and optin is None and split_url(endpoint)[0] == "https":
                # An https endpoint on a local host needs no opt-in: the full pipeline runs with the host
                # admitted for this provider only (the scheme is https, so nothing is sent in the clear).
                result = _validator().validate_declared_endpoint(endpoint, allow_insecure_endpoint=local)
                if not result.valid:
                    raise EndpointPolicyError(result.code or "ENDPOINT-INVALID", result.detail or "endpoint refused",
                                              name)
            else:
                check_endpoint(endpoint, optin, name)
        elif optin is not None:
            # An opt-in with nothing to apply to is still validated, so a typo never sits silent.
            canonical_optin_host(optin, name)
        refusal = _local_label_refusal(name, prov)
        if refusal is not None:
            raise refusal
        if prov.get("keyless") is True:
            models = prov.get("models") or {}
            if not isinstance(models, dict) or not models:
                raise ConfigError(f"[CONFIG-INVALID] providers.{name} is keyless but declares no models")
            for model_id, model in models.items():
                model = model if isinstance(model, dict) else {}
                cw = model.get("context_window")
                if not isinstance(cw, int) or isinstance(cw, bool) or cw <= 0:
                    raise ConfigError(
                        f"[CONFIG-INVALID] providers.{name}.models.{model_id}: a keyless provider is admitted only "
                        f"with a declared context_window (a positive integer)"
                    )
                if not model.get("dispatch_group"):
                    raise ConfigError(
                        f"[CONFIG-INVALID] providers.{name}.models.{model_id}: a keyless provider is admitted only "
                        f"with a declared dispatch_group"
                    )


# --- probe helper CLI -------------------------------------------------------------------------------------

_ENV_AUTH = re.compile(r"^\{env:([A-Za-z_][A-Za-z0-9_]*)\}$")


def describe_provider(merged: Dict[str, Any], name: str) -> Dict[str, Any]:
    """What the health probe needs about one configured provider. Never carries a secret value."""
    prov = (merged.get("providers") or {}).get(name)
    if not isinstance(prov, dict):
        raise KeyError(name)
    raw_auth = getattr(prov.get("auth"), "_raw", prov.get("auth"))
    auth_env = None
    if isinstance(raw_auth, str):
        m = _ENV_AUTH.match(raw_auth.strip())
        if m:
            auth_env = m.group(1)
    optin = prov.get("allow_insecure_endpoint")
    models = prov.get("models") or {}
    return {
        "name": name,
        "type": prov.get("type", "openai"),
        "endpoint": prov.get("endpoint") or "",
        "keyless": prov.get("keyless") is True,
        "allow_insecure_endpoint": canonical_optin_host(optin, name) if optin is not None else None,
        "auth_env": auth_env,
        "cli": _is_cli_provider(prov),
        "models": sorted(models.keys()) if isinstance(models, dict) else [],
    }


def _main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(prog="endpoint_policy")
    sub = parser.add_subparsers(dest="cmd", required=True)
    lp = sub.add_parser("list-providers")
    lp.add_argument("--project-root", default=None)
    dp = sub.add_parser("describe-provider")
    dp.add_argument("name")
    dp.add_argument("--project-root", default=None)
    args = parser.parse_args(argv)

    from loa_cheval.config.loader import load_config

    # Exit-code contract (model-health-probe.sh greps "error" from stderr): every load failure — a ConfigError,
    # unparseable YAML, a failed interpolation — is one JSON line and 78; never a traceback.
    try:
        merged, _sources = load_config(project_root=args.project_root)
    except ConfigError as exc:
        print(json.dumps({"error": "config_load_failed", "detail": str(exc)}), file=sys.stderr)
        return 78
    except Exception as exc:  # noqa: BLE001 — the contract above
        print(json.dumps({"error": "config_load_failed", "detail": f"{type(exc).__name__}: {exc}"}), file=sys.stderr)
        return 78
    if args.cmd == "list-providers":
        print("\n".join(sorted((merged.get("providers") or {}).keys())))
        return 0
    try:
        described = describe_provider(merged, args.name)
    except KeyError:
        print(json.dumps({"error": "provider_not_configured", "provider": args.name}), file=sys.stderr)
        return 64
    except ConfigError as exc:
        print(json.dumps({"error": "config_load_failed", "detail": str(exc)}), file=sys.stderr)
        return 78
    print(json.dumps(described, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
