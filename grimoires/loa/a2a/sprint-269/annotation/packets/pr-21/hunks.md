# Hunks — pr-21

The later fix changed 105 region(s) in 35 of the change's 80 file(s). Line numbers are head-side (the code under review). Each entry shows up to 12 head lines before and after the region; `>` marks a head line the fix changed.

## H01 — .claude/adapters/cheval.py — insertion after head line 422

Head context (head/.claude/adapters/cheval.py, lines 411–434):

~~~~text
   411 |         return chain, []
   412 |     kept = [e for e in chain.entries if e not in agy]
   413 |     skipped = [{"model": e.canonical, "provider": e.provider, "reason": "opt_in_required"} for e in agy]
   414 |     if not _AGY_NOT_PLANNED_WARNED:
   415 |         _AGY_NOT_PLANNED_WARNED = True
   416 |         logger.warning(
   417 |             "agy hop(s) %s not planned: the agy route is opt-in (hounfour.headless.agy_opt_in is not true) — "
   418 |             "walking the remaining hop(s) %s", ", ".join(x["model"] for x in skipped), ", ".join(e.canonical for e in kept))
   419 |     # (r251-6 V8, BB #4: every other ResolvedChain field is carried, and `entries` keeps its container type)
   420 |     return _dc_replace(chain, entries=type(chain.entries)(kept)), skipped
   421 | 
   422 | 
   423 | def _get_adapter_for_entry(entry: Any, hounfour: Dict[str, Any]):
   424 |     """Select the adapter for a single ResolvedEntry honoring `adapter_kind`.
   425 | 
   426 |     For `kind: http` entries, this is `get_adapter(_build_provider_config(...))`
   427 |     — the legacy path that selects via `provider.type`.
   428 | 
   429 |     For `kind: cli` entries, this looks up the CLI adapter type via
   430 |     `_CLI_ADAPTER_BY_PROVIDER[entry.provider]` and constructs it directly
   431 |     against the SAME provider block (so the operator's endpoint / auth
   432 |     declarations are preserved for the HTTP siblings under the same
   433 |     provider, but the CLI adapter never calls `_get_auth_header()`).
   434 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -422,0 +423,37 @@
+def _entry_is_local(entry: Any, hounfour: Dict[str, Any]) -> bool:
+    """The local-hop rule (SDD D-8.1) for one resolved hop: `endpoint_policy.hop_is_local` on the merged view, and a
+    `kind: cli` hop (the resolver's adapter_kind) is hosted whatever its label says."""
+    from loa_cheval.config.endpoint_policy import hop_is_local
+    if getattr(entry, "adapter_kind", "http") == "cli":
+        return False
+    return hop_is_local(hounfour, getattr(entry, "provider", ""), getattr(entry, "model_id", ""))
+
+
+def _plan_around_locality(chain: Any, hounfour: Dict[str, Any]) -> Tuple[Any, List[Dict[str, Any]]]:
+    """cycle-129 audit a257-1 MEDIUM-A1 (a), SDD D-8.1: under `hounfour.locality: local_voices` cheval — the process
+    that sends the prompt — plans around every hop that fails the local-hop rule, the way `_plan_around_agy` plans
+    around the agy opt-in: the hop is dropped before the walk (never dispatched, not in models_requested) with one
+    stderr line naming it, and returned as `[{model, provider, reason: locality_refused}]` for MODELINV
+    `models_not_planned`. A chain left empty raises `LocalityRefusedError` — never a silent reroute. Under `hosted` (or
+    unset) the chain is returned unchanged."""
+    if not isinstance(hounfour, dict) or hounfour.get("locality") != "local_voices":
+        return chain, []
+    from loa_cheval.types import LocalityRefusedError
+    primary = chain.entries[0] if chain.entries else None
+    hosted = [e for e in chain.entries if not _entry_is_local(e, hounfour)]
+    if not hosted:
+        return chain, []
+    for e in hosted:
+        where = "primary" if e is primary else f"fallback of {chain.primary_alias}"
+        print(f"locality: local_voices refuses hosted hop {e.provider}:{e.model_id} ({where})", file=sys.stderr)
+    if len(hosted) == len(chain.entries):
+        raise LocalityRefusedError(
+            f"locality: local_voices refuses every hop of {chain.primary_alias} "
+            f"({', '.join(e.canonical for e in hosted)}): none passes the local-hop rule (dispatch_group local on an "
+            f"HTTP provider whose endpoint host is a loopback or RFC1918 IP literal or localhost)"
+        )
+    kept = [e for e in chain.entries if e not in hosted]
+    skipped = [{"model": e.canonical, "provider": e.provider, "reason": "locality_refused"} for e in hosted]
+    return _dc_replace(chain, entries=type(chain.entries)(kept)), skipped
+
+
~~~~

## H02 — .claude/adapters/cheval.py — insertion after head line 1813

Head context (head/.claude/adapters/cheval.py, lines 1802–1825):

~~~~text
  1802 |             _exc,
  1803 |         )
  1804 | 
  1805 |     # cycle-102 Sprint 1D / T1.7 + cycle-104 Sprint 2 T2.6: MODELINV emit-state.
  1806 |     # The finally-clause emits a single envelope at function exit (success or
  1807 |     # failure). Pre-resolution failures (handled above) deliberately do NOT
  1808 |     # emit because no model invocation occurred. `models_requested` enumerates
  1809 |     # the PLANNED chain — every hop the walk may dispatch, not just whichever
  1810 |     # entry happened to succeed; `models_requested` ∪ `models_not_planned` is
  1811 |     # the full resolved chain (cycle-127 review r251-1 G1: a gated agy hop is
  1812 |     # planned around before models_requested is taken; r251-4 S8, audit n2).
  1813 |     _chain, _models_not_planned = _plan_around_agy(_chain, hounfour)
  1814 |     if _models_not_planned and _auth_type_resolved is not None:
  1815 |         _auth_type_resolved = _chain.entries[0].auth_type
  1816 |     _modelinv_capability_class = getattr(binding, "capability_class", None)
  1817 |     _modelinv_models_requested = [e.canonical for e in _chain.entries]
  1818 |     _modelinv_state: Dict[str, Any] = {
  1819 |         "models_succeeded": [],
  1820 |         "models_failed": [],
  1821 |         "operator_visible_warn": False,
  1822 |         "invocation_latency_ms": None,
  1823 |         "cost_micro_usd": None,
  1824 |         # cycle-103 T3.2 / AC-3.2: observed-streaming. None = adapter didn't
  1825 |         # report → emit falls back to env-derived value. True/False = actual
~~~~

The change from head to the fix:

~~~~diff
@@ -1813,0 +1851,27 @@
+    # cycle-129 audit a257-1 MEDIUM-A1 (a): under hounfour.locality local_voices the hosted hops are planned around;
+    # a chain with no local hop is refused before any dispatch, with a MODELINV row (failure_class locality_refused).
+    from loa_cheval.types import LocalityRefusedError as _LocalityRefusedError
+    try:
+        _chain, _models_not_planned_loc = _plan_around_locality(_chain, hounfour)
+    except _LocalityRefusedError as _e:
+        print(_error_json(_e.code, _e.detail, retryable=False, failure_class=_e.failure_class), file=sys.stderr)
+        try:
+            _emit_modelinv(
+                models_requested=[e.canonical for e in _chain.entries],
+                models_succeeded=[],
+                models_failed=[{"model": e.canonical, "provider": e.provider, "error_class": "INVALID_CONFIG",
+                                "failure_class": _e.failure_class, "message_redacted": _e.detail}
+                               for e in _chain.entries],
+                operator_visible_warn=True,
+                capability_class=getattr(binding, "capability_class", None),
+                calling_primitive=(getattr(args, "skill", None) or agent_name),
+                models_not_planned=_models_not_planned or None,
+                **_modelinv_hop_telemetry(_chain.entries[0].canonical, hounfour),
+            )
+        except Exception as _emit_err:  # noqa: BLE001 — fail-soft; never mask the refusal
+            print(f"[AUDIT-EMIT-FAILED] {type(_emit_err).__name__}: {_emit_err}", file=sys.stderr)
+        return EXIT_CODES["INVALID_CONFIG"]
+    if _models_not_planned_loc:
+        _models_not_planned = list(_models_not_planned) + _models_not_planned_loc
+        if _auth_type_resolved is not None:
+            _auth_type_resolved = _chain.entries[0].auth_type
~~~~

## H03 — .claude/adapters/loa_cheval/audit/modelinv.py — head lines 474–476

Head context (head/.claude/adapters/loa_cheval/audit/modelinv.py, lines 462–488):

~~~~text
   462 | 
   463 | def locality_mode_of(hounfour: Dict[str, Any]) -> Optional[str]:
   464 |     """`hounfour.locality` (default `hosted`). An unknown value is not recorded
   465 |     (None) rather than recorded as something it is not; the config reader that
   466 |     owns the switch reports it."""
   467 |     value = (hounfour or {}).get("locality")
   468 |     if value is None:
   469 |         return "hosted"
   470 |     return value if value in LOCALITY_MODES else None
   471 | 
   472 | 
   473 | def hop_locality_of(provider: str, model_id: Optional[str], hounfour: Dict[str, Any]) -> str:
>  474 |     """`local` when the hop's model declares dispatch_group `local` (D-8.0), else `hosted`."""
>  475 |     _prov, entry = _provider_model_entry(provider, model_id, hounfour)
>  476 |     return "local" if entry.get("dispatch_group") == "local" else "hosted"
   477 | 
   478 | 
   479 | def hop_telemetry(hop: Optional[str], hounfour: Dict[str, Any]) -> Dict[str, Any]:
   480 |     """The cycle-129 MODELINV kwargs (`destination`, `locality_mode`,
   481 |     `hop_locality`) for a `provider:model_id` hop. Fail-soft: a malformed hop
   482 |     yields only `locality_mode`, never an exception at an emit site."""
   483 |     out: Dict[str, Any] = {}
   484 |     mode = locality_mode_of(hounfour)
   485 |     if mode is not None:
   486 |         out["locality_mode"] = mode
   487 |     if not hop or ":" not in str(hop):
   488 |         return out
~~~~

The change from head to the fix:

~~~~diff
@@ -474,3 +474,7 @@
-    """`local` when the hop's model declares dispatch_group `local` (D-8.0), else `hosted`."""
-    _prov, entry = _provider_model_entry(provider, model_id, hounfour)
-    return "local" if entry.get("dispatch_group") == "local" else "hosted"
+    """`local` when the hop's model declares dispatch_group `local` (D-8.0) AND the provider honours it — an
+    HTTP provider whose endpoint host passes the local-hop rule (D-8.1, r257-1) — else `hosted`, so the record
+    never says local for a hop the rule calls hosted. ONE implementation: ``endpoint_policy.hop_is_local`` (the
+    rule cheval's planner applies under ``local_voices``, audit a257-1 MEDIUM-A1)."""
+    from loa_cheval.config.endpoint_policy import hop_is_local
+
+    return "local" if hop_is_local(hounfour, provider, model_id) else "hosted"
~~~~

## H04 — .claude/adapters/loa_cheval/config/endpoint_policy.py — head lines 26–28

Head context (head/.claude/adapters/loa_cheval/config/endpoint_policy.py, lines 14–40):

~~~~text
    14 | * ``keyless: true`` marks a provider that needs no credential; a literal ``auth: "local"`` is accepted and
    15 |   normalised to ``keyless: true`` in the merged view. A keyless provider is admitted only when every model
    16 |   declares ``context_window`` and ``dispatch_group``.
    17 | 
    18 | ONE implementation: every URL and opt-in decision here is made by the canonical
    19 | ``.claude/scripts/lib/endpoint-validator.py`` (the module the bash callers and the health probe use),
    20 | loaded by path as ``loa_cheval.codegen.emit_endpoint_validator_ts`` does: ``check_insecure_optin`` for the
    21 | opt-in and ``validate_declared_endpoint`` (the full pipeline minus the host allowlist, which an
    22 | operator-declared https host is not on) for the endpoint. The refusal codes are therefore the validator's
    23 | codes, and URL parsing stays confined to that module (the cycle-099 import guard).
    24 | ``tests/test_endpoint_validator_optin.py`` runs one case table through both entry points.
    25 | 
>   26 | Request-time half (``TransportPolicy`` in ``providers/base.py``): for an opted-in provider, or a model whose
>   27 | ``dispatch_group`` is ``local``, the adapter ignores proxy environment variables, refuses HTTP redirects and
>   28 | requires every request URL to stay under the declared endpoint path.
    29 | 
    30 | CLI (used by ``model-health-probe.sh --provider <name>``; reads the merged config, never prints a secret)::
    31 | 
    32 |     python3 -m loa_cheval.config.endpoint_policy list-providers [--project-root DIR]
    33 |     python3 -m loa_cheval.config.endpoint_policy describe-provider NAME [--project-root DIR]
    34 | """
    35 | 
    36 | from __future__ import annotations
    37 | 
    38 | import argparse
    39 | import importlib.util
    40 | import json
~~~~

The change from head to the fix:

~~~~diff
@@ -26,3 +26,13 @@
+THE LOCAL-HOP RULE (D-8.1, review round r257-1): a hop is ``local`` only when its provider is an HTTP provider
+(not ``kind: cli`` / ``*-headless``) whose endpoint host is an IP literal in a loopback (``127.0.0.0/8``, ``::1``)
+or RFC1918 (``10/8``, ``172.16/12``, ``192.168/16``) range, or the literal ``localhost`` — exactly the host
+acceptance of the validator's ``check_insecure_optin`` (``local_host`` / ``local_endpoint_host`` below). A
+``dispatch_group: local`` on a model entry or the provider block of any other provider is refused at load; an
+``https`` endpoint on such a host needs no ``allow_insecure_endpoint`` (an ``http`` one still does). The same rule
+is applied at request time (``TransportPolicy.local``), in the planner (``.claude/scripts/lib/hop-locality.py``,
+stdlib mirror) and in Bridgebuilder (``config.ts`` ``localEndpointHost``, TypeScript mirror).
+
 Request-time half (``TransportPolicy`` in ``providers/base.py``): for an opted-in provider, or a model whose
 ``dispatch_group`` is ``local``, the adapter ignores proxy environment variables, refuses HTTP redirects and
-requires every request URL to stay under the declared endpoint path.
+requires every request URL to stay under the declared endpoint path; for a local hop the request host must also
+pass the local-hop rule.
~~~~

## H05 — .claude/adapters/loa_cheval/config/endpoint_policy.py — insertion after head line 112

Head context (head/.claude/adapters/loa_cheval/config/endpoint_policy.py, lines 101–124):

~~~~text
   101 |     return host
   102 | 
   103 | 
   104 | def check_endpoint(endpoint: str, allow_insecure_endpoint: Any = None, provider: Optional[str] = None) -> Optional[str]:
   105 |     """Apply the D-7.2 rule to one provider's endpoint. Returns the canonical opt-in host (or None); raises."""
   106 |     optin = canonical_optin_host(allow_insecure_endpoint, provider) if allow_insecure_endpoint is not None else None
   107 |     result = _validator().validate_declared_endpoint(endpoint, allow_insecure_endpoint=optin)
   108 |     if not result.valid:
   109 |         raise EndpointPolicyError(result.code or "ENDPOINT-INVALID", result.detail or "endpoint refused", provider)
   110 |     return optin
   111 | 
   112 | 
   113 | # --- the merged view --------------------------------------------------------------------------------------
   114 | 
   115 | 
   116 | def _is_cli_provider(prov: Dict[str, Any]) -> bool:
   117 |     ptype = str(prov.get("type") or "")
   118 |     if ptype.endswith("-headless"):
   119 |         return True
   120 |     models = prov.get("models") or {}
   121 |     return bool(models) and isinstance(models, dict) and all(
   122 |         isinstance(m, dict) and m.get("kind") == "cli" for m in models.values()
   123 |     )
   124 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -112,0 +123,64 @@
+# --- the local-hop rule (D-8.1, r257-1) -------------------------------------------------------------------
+
+LOCAL_RULE_TEXT = "a loopback or RFC1918 IP literal or localhost"
+
+
+def local_host(host: Any) -> Optional[str]:
+    """The canonical host when ``host`` passes the local-hop rule, else None. ONE implementation: the
+    validator's ``check_insecure_optin`` host acceptance (brackets stripped, IP literals canonicalised)."""
+    if not isinstance(host, str) or not host.strip():
+        return None
+    ok, _code, _detail, canonical = _validator().check_insecure_optin(host)
+    return canonical if ok else None
+
+
+def endpoint_host(endpoint: Any) -> str:
+    """The endpoint's canonical host for a refusal message ('' when absent; the raw text when it does not parse)."""
+    if not isinstance(endpoint, str) or not endpoint:
+        return ""
+    try:
+        return split_url(endpoint)[1]
+    except ValueError:
+        return endpoint[:128]
+
+
+def local_endpoint_host(endpoint: Any) -> Optional[str]:
+    """The canonical host when ``endpoint`` is an http(s) URL whose host passes the local-hop rule, else None."""
+    if not isinstance(endpoint, str) or not endpoint:
+        return None
+    try:
+        scheme, host, _port, _path = split_url(endpoint)
+    except ValueError:
+        return None
+    if scheme not in ("http", "https"):
+        return None
+    return local_host(host)
+
+
+def _local_labels(prov: Dict[str, Any]) -> Tuple[bool, List[str]]:
+    """(provider block says local, [model ids whose entry says local])."""
+    models = prov.get("models") if isinstance(prov.get("models"), dict) else {}
+    return (
+        prov.get("dispatch_group") == "local",
+        [m for m, entry in models.items() if isinstance(entry, dict) and entry.get("dispatch_group") == "local"],
+    )
+
+
+def _local_label_refusal(name: str, prov: Dict[str, Any]) -> Optional[ConfigError]:
+    """The refusal for a ``dispatch_group: local`` (model entry or provider block) the provider cannot honour —
+    a CLI provider, or an endpoint host that fails the local-hop rule — or None (not labelled, or it passes)."""
+    block_local, local_models = _local_labels(prov)
+    if not block_local and not local_models:
+        return None
+    if _is_cli_provider(prov):
+        return ConfigError(f"[CONFIG-INVALID] providers.{name}: dispatch_group local is not admitted on a CLI provider")
+    endpoint = prov.get("endpoint")
+    if local_endpoint_host(endpoint) is not None:
+        return None
+    where = f"providers.{name}" if block_local else f"providers.{name}.models.{local_models[0]}"
+    shown = endpoint_host(endpoint) or "missing"
+    return ConfigError(
+        f"[CONFIG-INVALID] {where}: dispatch_group local requires an endpoint on {LOCAL_RULE_TEXT} (host {shown})"
+    )
+
+
~~~~

## H06 — .claude/adapters/loa_cheval/config/endpoint_policy.py — insertion after head line 125

Head context (head/.claude/adapters/loa_cheval/config/endpoint_policy.py, lines 114–137):

~~~~text
   114 | 
   115 | 
   116 | def _is_cli_provider(prov: Dict[str, Any]) -> bool:
   117 |     ptype = str(prov.get("type") or "")
   118 |     if ptype.endswith("-headless"):
   119 |         return True
   120 |     models = prov.get("models") or {}
   121 |     return bool(models) and isinstance(models, dict) and all(
   122 |         isinstance(m, dict) and m.get("kind") == "cli" for m in models.values()
   123 |     )
   124 | 
   125 | 
   126 | def normalise_keyless(merged: Dict[str, Any]) -> None:
   127 |     """Pre-interpolation step: a literal ``auth: "local"`` becomes ``keyless: true`` (D-8.0); ``keyless`` must be a bool."""
   128 |     providers = merged.get("providers")
   129 |     if not isinstance(providers, dict):
   130 |         return
   131 |     for name, prov in providers.items():
   132 |         if not isinstance(prov, dict):
   133 |             continue
   134 |         if "keyless" in prov and not isinstance(prov["keyless"], bool):
   135 |             raise ConfigError(
   136 |                 f"[CONFIG-INVALID] providers.{name}.keyless must be true or false, got {prov['keyless']!r}"
   137 |             )
~~~~

The change from head to the fix:

~~~~diff
@@ -125,0 +200,74 @@
+def hop_is_local(merged: Dict[str, Any], provider: str, model_id: Optional[str]) -> bool:
+    """True when the ``provider:model_id`` hop passes the local-hop rule in the merged view (D-8.1): the model entry
+    (or, when the entry is silent, its provider block) says ``dispatch_group: local``, the hop is not a CLI hop (a
+    ``*-headless`` / all-``kind: cli`` provider or a ``kind: cli`` model) and the provider's endpoint host passes
+    ``local_endpoint_host``. ONE implementation for cheval's planner, the loader's fallback check and MODELINV
+    ``hop_locality`` (``hop-locality.py`` is the stdlib mirror). Fail closed: an undeclared hop is hosted."""
+    providers = (merged or {}).get("providers")
+    prov = providers.get(provider) if isinstance(providers, dict) else None
+    if not isinstance(prov, dict):
+        return False
+    models = prov.get("models") if isinstance(prov.get("models"), dict) else {}
+    entry = models.get(model_id) if model_id else None
+    entry = entry if isinstance(entry, dict) else {}
+    if (entry.get("dispatch_group") or prov.get("dispatch_group")) != "local":
+        return False
+    if _is_cli_provider(prov) or entry.get("kind") == "cli":
+        return False
+    return local_endpoint_host(prov.get("endpoint")) is not None
+
+
+LOCAL_FALLBACK_MAX_DEPTH = 8
+
+
+def resolve_hop_spec(spec: Any, aliases: Any) -> Optional[Tuple[str, str]]:
+    """``(provider, model_id)`` for a ``fallback_chain`` entry — a ``provider:model`` pin or an alias followed through
+    ``aliases`` (depth-limited, cycle-safe) — or None when it does not resolve."""
+    current = spec.strip() if isinstance(spec, str) else ""
+    table = aliases if isinstance(aliases, dict) else {}
+    seen = set()
+    for _ in range(LOCAL_FALLBACK_MAX_DEPTH + 1):
+        if not current:
+            return None
+        if ":" in current:
+            provider, _, model = current.partition(":")
+            return (provider, model) if provider and model else None
+        if current in seen:
+            return None
+        seen.add(current)
+        target = table.get(current)
+        if isinstance(target, dict):
+            target = target.get("target") or target.get("model")
+        current = target.strip() if isinstance(target, str) else ""
+    return None
+
+
+def validate_local_fallbacks(merged: Dict[str, Any]) -> None:
+    """Audit a257-1 MEDIUM-A1 (b): ONLY under ``hounfour.locality: local_voices`` (the merged root's ``locality``), a
+    model that says ``dispatch_group: local`` whose ``fallback_chain`` names an entry that fails the local-hop rule —
+    or does not resolve — is refused at load: cheval walks that chain inside one call, so the prompt would leave the
+    declared providers. Under ``hosted`` (or unset) a local model may still fall back to a hosted one."""
+    if (merged or {}).get("locality") != "local_voices":
+        return
+    providers = merged.get("providers")
+    if not isinstance(providers, dict):
+        return
+    aliases = merged.get("aliases")
+    for name, prov in providers.items():
+        if not isinstance(prov, dict) or not isinstance(prov.get("models"), dict):
+            continue
+        for model_id, entry in prov["models"].items():
+            if not isinstance(entry, dict):
+                continue
+            if (entry.get("dispatch_group") or prov.get("dispatch_group")) != "local":
+                continue
+            chain = entry.get("fallback_chain") or []
+            for spec in (chain if isinstance(chain, list) else [chain]):
+                target = resolve_hop_spec(spec, aliases)
+                if target is None or not hop_is_local(merged, target[0], target[1]):
+                    raise ConfigError(
+                        f"[CONFIG-INVALID] providers.{name}.models.{model_id}: under hounfour.locality local_voices "
+                        f"the fallback_chain reaches a hosted hop {spec}"
+                    )
+
+
~~~~

## H07 — .claude/adapters/loa_cheval/config/endpoint_policy.py — insertion after head line 139

Head context (head/.claude/adapters/loa_cheval/config/endpoint_policy.py, lines 128–151):

~~~~text
   128 |     providers = merged.get("providers")
   129 |     if not isinstance(providers, dict):
   130 |         return
   131 |     for name, prov in providers.items():
   132 |         if not isinstance(prov, dict):
   133 |             continue
   134 |         if "keyless" in prov and not isinstance(prov["keyless"], bool):
   135 |             raise ConfigError(
   136 |                 f"[CONFIG-INVALID] providers.{name}.keyless must be true or false, got {prov['keyless']!r}"
   137 |             )
   138 |         auth = prov.get("auth")
   139 |         if isinstance(auth, str) and auth.strip().lower() in KEYLESS_AUTH_LITERALS:
   140 |             prov["keyless"] = True
   141 | 
   142 | 
   143 | def validate_providers(merged: Dict[str, Any]) -> None:
   144 |     """Post-interpolation step: endpoint rule and keyless preconditions for every provider."""
   145 |     providers = merged.get("providers")
   146 |     if not isinstance(providers, dict):
   147 |         return
   148 |     for name, prov in providers.items():
   149 |         if not isinstance(prov, dict):
   150 |             continue
   151 |         optin = prov.get("allow_insecure_endpoint")
~~~~

The change from head to the fix:

~~~~diff
@@ -139,0 +288,5 @@
+            if prov.get("keyless") is False:
+                raise ConfigError(
+                    f"[CONFIG-INVALID] providers.{name}: keyless: false conflicts with the literal auth "
+                    f"\"{auth.strip()}\""
+                )
~~~~

## H08 — .claude/adapters/loa_cheval/config/endpoint_policy.py — head line 144

Head context (head/.claude/adapters/loa_cheval/config/endpoint_policy.py, lines 132–156):

~~~~text
   132 |         if not isinstance(prov, dict):
   133 |             continue
   134 |         if "keyless" in prov and not isinstance(prov["keyless"], bool):
   135 |             raise ConfigError(
   136 |                 f"[CONFIG-INVALID] providers.{name}.keyless must be true or false, got {prov['keyless']!r}"
   137 |             )
   138 |         auth = prov.get("auth")
   139 |         if isinstance(auth, str) and auth.strip().lower() in KEYLESS_AUTH_LITERALS:
   140 |             prov["keyless"] = True
   141 | 
   142 | 
   143 | def validate_providers(merged: Dict[str, Any]) -> None:
>  144 |     """Post-interpolation step: endpoint rule and keyless preconditions for every provider."""
   145 |     providers = merged.get("providers")
   146 |     if not isinstance(providers, dict):
   147 |         return
   148 |     for name, prov in providers.items():
   149 |         if not isinstance(prov, dict):
   150 |             continue
   151 |         optin = prov.get("allow_insecure_endpoint")
   152 |         endpoint = prov.get("endpoint")
   153 |         if not _is_cli_provider(prov) and endpoint not in (None, ""):
   154 |             if not isinstance(endpoint, str):
   155 |                 raise ConfigError(f"[CONFIG-INVALID] providers.{name}.endpoint must be a string")
   156 |             check_endpoint(endpoint, optin, name)
~~~~

The change from head to the fix:

~~~~diff
@@ -144 +297 @@
-    """Post-interpolation step: endpoint rule and keyless preconditions for every provider."""
+    """Post-interpolation step: the local-hop rule, the endpoint rule and keyless preconditions for every provider."""
~~~~

## H09 — .claude/adapters/loa_cheval/config/endpoint_policy.py — head lines 153–159

Head context (head/.claude/adapters/loa_cheval/config/endpoint_policy.py, lines 141–171):

~~~~text
   141 | 
   142 | 
   143 | def validate_providers(merged: Dict[str, Any]) -> None:
   144 |     """Post-interpolation step: endpoint rule and keyless preconditions for every provider."""
   145 |     providers = merged.get("providers")
   146 |     if not isinstance(providers, dict):
   147 |         return
   148 |     for name, prov in providers.items():
   149 |         if not isinstance(prov, dict):
   150 |             continue
   151 |         optin = prov.get("allow_insecure_endpoint")
   152 |         endpoint = prov.get("endpoint")
>  153 |         if not _is_cli_provider(prov) and endpoint not in (None, ""):
>  154 |             if not isinstance(endpoint, str):
>  155 |                 raise ConfigError(f"[CONFIG-INVALID] providers.{name}.endpoint must be a string")
>  156 |             check_endpoint(endpoint, optin, name)
>  157 |         elif optin is not None:
>  158 |             # An opt-in with nothing to apply to is still validated, so a typo never sits silent.
>  159 |             canonical_optin_host(optin, name)
   160 |         if prov.get("keyless") is True:
   161 |             models = prov.get("models") or {}
   162 |             if not isinstance(models, dict) or not models:
   163 |                 raise ConfigError(f"[CONFIG-INVALID] providers.{name} is keyless but declares no models")
   164 |             for model_id, model in models.items():
   165 |                 model = model if isinstance(model, dict) else {}
   166 |                 cw = model.get("context_window")
   167 |                 if not isinstance(cw, int) or isinstance(cw, bool) or cw <= 0:
   168 |                     raise ConfigError(
   169 |                         f"[CONFIG-INVALID] providers.{name}.models.{model_id}: a keyless provider is admitted only "
   170 |                         f"with a declared context_window (a positive integer)"
   171 |                     )
~~~~

The change from head to the fix:

~~~~diff
@@ -153,7 +306,24 @@
+        # D-8.1 (r257-1): a declared locality is enforced, not trusted. The D-7.2 endpoint checks run first (their
+        # codes are the more specific reason); a labelled provider they admit is then held to the local-hop rule.
+        block_local, local_models = _local_labels(prov)
+        labelled = block_local or bool(local_models)
+        local = local_endpoint_host(endpoint) if labelled and not _is_cli_provider(prov) else None
         if not _is_cli_provider(prov) and endpoint not in (None, ""):
             if not isinstance(endpoint, str):
                 raise ConfigError(f"[CONFIG-INVALID] providers.{name}.endpoint must be a string")
-            check_endpoint(endpoint, optin, name)
+            # (local is set only when the endpoint parsed, so split_url cannot raise here)
+            if local is not None and optin is None and split_url(endpoint)[0] == "https":
+                # An https endpoint on a local host needs no opt-in: the full pipeline runs with the host
+                # admitted for this provider only (the scheme is https, so nothing is sent in the clear).
+                result = _validator().validate_declared_endpoint(endpoint, allow_insecure_endpoint=local)
+                if not result.valid:
+                    raise EndpointPolicyError(result.code or "ENDPOINT-INVALID", result.detail or "endpoint refused",
+                                              name)
+            else:
+                check_endpoint(endpoint, optin, name)
         elif optin is not None:
             # An opt-in with nothing to apply to is still validated, so a typo never sits silent.
             canonical_optin_host(optin, name)
+        refusal = _local_label_refusal(name, prov)
+        if refusal is not None:
+            raise refusal
~~~~

## H10 — .claude/adapters/loa_cheval/config/endpoint_policy.py — insertion after head line 220

Head context (head/.claude/adapters/loa_cheval/config/endpoint_policy.py, lines 209–232):

~~~~text
   209 | def _main(argv: Optional[List[str]] = None) -> int:
   210 |     parser = argparse.ArgumentParser(prog="endpoint_policy")
   211 |     sub = parser.add_subparsers(dest="cmd", required=True)
   212 |     lp = sub.add_parser("list-providers")
   213 |     lp.add_argument("--project-root", default=None)
   214 |     dp = sub.add_parser("describe-provider")
   215 |     dp.add_argument("name")
   216 |     dp.add_argument("--project-root", default=None)
   217 |     args = parser.parse_args(argv)
   218 | 
   219 |     from loa_cheval.config.loader import load_config
   220 | 
   221 |     try:
   222 |         merged, _sources = load_config(project_root=args.project_root)
   223 |     except ConfigError as exc:
   224 |         print(json.dumps({"error": "config_load_failed", "detail": str(exc)}), file=sys.stderr)
   225 |         return 78
   226 |     if args.cmd == "list-providers":
   227 |         print("\n".join(sorted((merged.get("providers") or {}).keys())))
   228 |         return 0
   229 |     try:
   230 |         print(json.dumps(describe_provider(merged, args.name), sort_keys=True))
   231 |     except KeyError:
   232 |         print(json.dumps({"error": "provider_not_configured", "provider": args.name}), file=sys.stderr)
~~~~

The change from head to the fix:

~~~~diff
@@ -220,0 +391,2 @@
+    # Exit-code contract (model-health-probe.sh greps "error" from stderr): every load failure — a ConfigError,
+    # unparseable YAML, a failed interpolation — is one JSON line and 78; never a traceback.
~~~~

## H11 — .claude/adapters/loa_cheval/config/endpoint_policy.py — insertion after head line 225

Head context (head/.claude/adapters/loa_cheval/config/endpoint_policy.py, lines 214–237):

~~~~text
   214 |     dp = sub.add_parser("describe-provider")
   215 |     dp.add_argument("name")
   216 |     dp.add_argument("--project-root", default=None)
   217 |     args = parser.parse_args(argv)
   218 | 
   219 |     from loa_cheval.config.loader import load_config
   220 | 
   221 |     try:
   222 |         merged, _sources = load_config(project_root=args.project_root)
   223 |     except ConfigError as exc:
   224 |         print(json.dumps({"error": "config_load_failed", "detail": str(exc)}), file=sys.stderr)
   225 |         return 78
   226 |     if args.cmd == "list-providers":
   227 |         print("\n".join(sorted((merged.get("providers") or {}).keys())))
   228 |         return 0
   229 |     try:
   230 |         print(json.dumps(describe_provider(merged, args.name), sort_keys=True))
   231 |     except KeyError:
   232 |         print(json.dumps({"error": "provider_not_configured", "provider": args.name}), file=sys.stderr)
   233 |         return 64
   234 |     return 0
   235 | 
   236 | 
   237 | if __name__ == "__main__":
~~~~

The change from head to the fix:

~~~~diff
@@ -225,0 +398,3 @@
+    except Exception as exc:  # noqa: BLE001 — the contract above
+        print(json.dumps({"error": "config_load_failed", "detail": f"{type(exc).__name__}: {exc}"}), file=sys.stderr)
+        return 78
~~~~

## H12 — .claude/adapters/loa_cheval/config/endpoint_policy.py — head lines 230–233

Head context (head/.claude/adapters/loa_cheval/config/endpoint_policy.py, lines 218–238):

~~~~text
   218 | 
   219 |     from loa_cheval.config.loader import load_config
   220 | 
   221 |     try:
   222 |         merged, _sources = load_config(project_root=args.project_root)
   223 |     except ConfigError as exc:
   224 |         print(json.dumps({"error": "config_load_failed", "detail": str(exc)}), file=sys.stderr)
   225 |         return 78
   226 |     if args.cmd == "list-providers":
   227 |         print("\n".join(sorted((merged.get("providers") or {}).keys())))
   228 |         return 0
   229 |     try:
>  230 |         print(json.dumps(describe_provider(merged, args.name), sort_keys=True))
>  231 |     except KeyError:
>  232 |         print(json.dumps({"error": "provider_not_configured", "provider": args.name}), file=sys.stderr)
>  233 |         return 64
   234 |     return 0
   235 | 
   236 | 
   237 | if __name__ == "__main__":
   238 |     raise SystemExit(_main())
~~~~

The change from head to the fix:

~~~~diff
@@ -230,4 +405,8 @@
-        print(json.dumps(describe_provider(merged, args.name), sort_keys=True))
+        described = describe_provider(merged, args.name)
     except KeyError:
         print(json.dumps({"error": "provider_not_configured", "provider": args.name}), file=sys.stderr)
         return 64
+    except ConfigError as exc:
+        print(json.dumps({"error": "config_load_failed", "detail": str(exc)}), file=sys.stderr)
+        return 78
+    print(json.dumps(described, sort_keys=True))
~~~~

## H13 — .claude/adapters/loa_cheval/config/loader.py — head line 28

Head context (head/.claude/adapters/loa_cheval/config/loader.py, lines 16–40):

~~~~text
    16 | from __future__ import annotations
    17 | 
    18 | import copy
    19 | import json
    20 | import logging
    21 | import os
    22 | import re
    23 | import stat
    24 | import sys
    25 | from pathlib import Path
    26 | from typing import Any, Dict, List, Optional, Tuple
    27 | 
>   28 | from loa_cheval.config.endpoint_policy import normalise_keyless, validate_providers
    29 | from loa_cheval.config.interpolation import interpolate_config, redact_config
    30 | from loa_cheval.types import ConfigError
    31 | 
    32 | logger = logging.getLogger("loa_cheval.config.loader")
    33 | 
    34 | # Module-level guard so the force-legacy-aliases WARN fires at most once per
    35 | # process even when load_config() is invoked multiple times (cache-clear,
    36 | # tests, --print-effective-config).
    37 | _force_legacy_warned = False
    38 | _endpoint_family_default_warned: set[str] = set()
    39 | 
    40 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -28 +28 @@
-from loa_cheval.config.endpoint_policy import normalise_keyless, validate_providers
+from loa_cheval.config.endpoint_policy import normalise_keyless, validate_local_fallbacks, validate_providers
~~~~

## H14 — .claude/adapters/loa_cheval/config/loader.py — insertion after head line 704

Head context (head/.claude/adapters/loa_cheval/config/loader.py, lines 693–716):

~~~~text
   693 |         )
   694 |     except ConfigError:
   695 |         raise
   696 |     except Exception as e:
   697 |         raise ConfigError(f"Config interpolation failed: {e}")
   698 | 
   699 |     # cycle-129 FR-7 (SDD D-7.2): every HTTP provider's endpoint is checked
   700 |     # against the per-provider insecure-endpoint opt-in and the cycle-099
   701 |     # refusals (https only; no loopback/private/link-local/metadata literal),
   702 |     # and keyless providers must declare context_window and dispatch_group.
   703 |     # Runs on the interpolated endpoint so a templated value is checked as sent.
   704 |     validate_providers(merged)
   705 | 
   706 |     return merged, sources
   707 | 
   708 | 
   709 | def get_effective_config_display(
   710 |     config: Dict[str, Any],
   711 |     sources: Dict[str, str],
   712 | ) -> str:
   713 |     """Format merged config for --print-effective-config with source annotations.
   714 | 
   715 |     Secret values are redacted.
   716 |     """
~~~~

The change from head to the fix:

~~~~diff
@@ -704,0 +705,3 @@
+    # cycle-129 audit a257-1 MEDIUM-A1 (b): under hounfour.locality local_voices a
+    # dispatch_group local model whose fallback_chain reaches a hosted hop is refused.
+    validate_local_fallbacks(merged)
~~~~

## H15 — .claude/adapters/loa_cheval/providers/base.py — head lines 123–130

Head context (head/.claude/adapters/loa_cheval/providers/base.py, lines 111–142):

~~~~text
   111 |     _HTTP2_AVAILABLE = None
   112 | 
   113 | 
   114 | # --- cycle-129 FR-7 (SDD D-7.2): request-time rules for an opted-in / local provider ---
   115 | 
   116 | 
   117 | @dataclass(frozen=True)
   118 | class TransportPolicy:
   119 |     """The request-time half of D-7.2 for a provider with `allow_insecure_endpoint`
   120 |     (or a model with dispatch_group `local`): proxy environment variables are
   121 |     ignored, an HTTP redirect is an error and is never followed, and every request
   122 |     URL must keep the declared endpoint's scheme, host and port and start with its
>  123 |     path. The load-time half lives in config/endpoint_policy.py."""
>  124 | 
>  125 |     endpoint: str
>  126 |     provider: str
>  127 | 
>  128 |     def check_url(self, url: str) -> None:
>  129 |         # URL parsing stays in the canonical endpoint validator (cycle-099 import guard).
>  130 |         from loa_cheval.config.endpoint_policy import split_url
   131 | 
   132 |         try:
   133 |             d_scheme, d_host, d_port, d_path = split_url(self.endpoint)
   134 |             r_scheme, r_host, r_port, r_path = split_url(url)
   135 |         except ValueError as exc:
   136 |             raise InvalidConfigError(f"request URL for provider '{self.provider}' does not parse: {exc}") from None
   137 |         prefix = d_path.rstrip("/")
   138 |         same_origin = (r_scheme, r_host, r_port) == (d_scheme, d_host, d_port)
   139 |         in_path = (r_path == prefix or r_path.startswith(prefix + "/")) if prefix else True
   140 |         if not same_origin or not in_path or "/../" in r_path or r_path.endswith("/.."):
   141 |             raise InvalidConfigError(
   142 |                 f"request URL path {r_path!r} on {r_host!r} is outside the declared endpoint "
~~~~

The change from head to the fix:

~~~~diff
@@ -123,8 +123,14 @@
-    path. The load-time half lives in config/endpoint_policy.py."""
+    path. The load-time half lives in config/endpoint_policy.py.
+
+    `local` (D-8.1, r257-1) marks a hop whose model says dispatch_group `local`: the
+    request host must then also pass the local-hop rule (a loopback or RFC1918 IP
+    literal or `localhost`, endpoint_policy.local_host), so a declared locality is
+    enforced even when a config reaches the adapter by another loader."""
 
     endpoint: str
     provider: str
+    local: bool = False
 
     def check_url(self, url: str) -> None:
         # URL parsing stays in the canonical endpoint validator (cycle-099 import guard).
-        from loa_cheval.config.endpoint_policy import split_url
+        from loa_cheval.config.endpoint_policy import LOCAL_RULE_TEXT, local_host, split_url
~~~~

## H16 — .claude/adapters/loa_cheval/providers/base.py — insertion after head line 136

Head context (head/.claude/adapters/loa_cheval/providers/base.py, lines 125–148):

~~~~text
   125 |     endpoint: str
   126 |     provider: str
   127 | 
   128 |     def check_url(self, url: str) -> None:
   129 |         # URL parsing stays in the canonical endpoint validator (cycle-099 import guard).
   130 |         from loa_cheval.config.endpoint_policy import split_url
   131 | 
   132 |         try:
   133 |             d_scheme, d_host, d_port, d_path = split_url(self.endpoint)
   134 |             r_scheme, r_host, r_port, r_path = split_url(url)
   135 |         except ValueError as exc:
   136 |             raise InvalidConfigError(f"request URL for provider '{self.provider}' does not parse: {exc}") from None
   137 |         prefix = d_path.rstrip("/")
   138 |         same_origin = (r_scheme, r_host, r_port) == (d_scheme, d_host, d_port)
   139 |         in_path = (r_path == prefix or r_path.startswith(prefix + "/")) if prefix else True
   140 |         if not same_origin or not in_path or "/../" in r_path or r_path.endswith("/.."):
   141 |             raise InvalidConfigError(
   142 |                 f"request URL path {r_path!r} on {r_host!r} is outside the declared endpoint "
   143 |                 f"{self.endpoint!r} for provider '{self.provider}' (D-7.2 path-prefix rule)"
   144 |             )
   145 | 
   146 |     def refuse_redirect(self, status: int) -> None:
   147 |         if 300 <= int(status) < 400:
   148 |             raise InvalidConfigError(
~~~~

The change from head to the fix:

~~~~diff
@@ -136,0 +143,11 @@
+        if self.local and (r_scheme not in ("http", "https") or local_host(r_host) is None):
+            raise InvalidConfigError(
+                f"request host {r_host or '(none)'} for provider '{self.provider}' is not {LOCAL_RULE_TEXT} "
+                f"(dispatch_group local, D-7.2)"
+            )
+        if str(local_host(r_host)).lower() == "localhost":
+            # audit a257-1 LOW-A1: an IP literal is never resolved, but `localhost` is resolved by the system resolver
+            # (/etc/hosts, nsswitch) when the request is sent — so it is resolved here first and every address it
+            # yields must be loopback. Fail closed: a resolver failure refuses too. (Every policy hop — a local one or
+            # an `allow_insecure_endpoint: localhost` opt-in, whose plain http must stay on this machine.)
+            self._check_localhost_resolves_to_loopback()
~~~~

## H17 — .claude/adapters/loa_cheval/providers/base.py — insertion after head line 145

Head context (head/.claude/adapters/loa_cheval/providers/base.py, lines 134–157):

~~~~text
   134 |             r_scheme, r_host, r_port, r_path = split_url(url)
   135 |         except ValueError as exc:
   136 |             raise InvalidConfigError(f"request URL for provider '{self.provider}' does not parse: {exc}") from None
   137 |         prefix = d_path.rstrip("/")
   138 |         same_origin = (r_scheme, r_host, r_port) == (d_scheme, d_host, d_port)
   139 |         in_path = (r_path == prefix or r_path.startswith(prefix + "/")) if prefix else True
   140 |         if not same_origin or not in_path or "/../" in r_path or r_path.endswith("/.."):
   141 |             raise InvalidConfigError(
   142 |                 f"request URL path {r_path!r} on {r_host!r} is outside the declared endpoint "
   143 |                 f"{self.endpoint!r} for provider '{self.provider}' (D-7.2 path-prefix rule)"
   144 |             )
   145 | 
   146 |     def refuse_redirect(self, status: int) -> None:
   147 |         if 300 <= int(status) < 400:
   148 |             raise InvalidConfigError(
   149 |                 f"HTTP {status} redirect refused for provider '{self.provider}': an opted-in or local "
   150 |                 f"endpoint never follows redirects (D-7.2)"
   151 |             )
   152 | 
   153 | 
   154 | def _policy_urllib_opener():
   155 |     """urllib opener for a TransportPolicy: no proxy handler, no redirect following."""
   156 |     import urllib.request
   157 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -145,0 +163,34 @@
+    def _check_localhost_resolves_to_loopback(self) -> None:
+        import ipaddress
+
+        try:
+            infos = socket.getaddrinfo("localhost", None)
+        except Exception as exc:  # noqa: BLE001 — any resolver failure refuses (fail closed)
+            raise InvalidConfigError(
+                f"request host localhost for provider '{self.provider}' could not be resolved "
+                f"({type(exc).__name__}) (dispatch_group local, D-7.2)"
+            ) from None
+        addrs = []
+        for info in infos or ():
+            try:
+                addrs.append(str(info[4][0]))
+            except (IndexError, TypeError):
+                addrs.append("(unreadable)")
+        if not addrs:
+            raise InvalidConfigError(
+                f"request host localhost for provider '{self.provider}' could not be resolved "
+                f"(no address) (dispatch_group local, D-7.2)"
+            )
+        for addr in addrs:
+            try:
+                ip = ipaddress.ip_address(addr.split("%", 1)[0])
+                mapped = getattr(ip, "ipv4_mapped", None)
+                loopback = ip.is_loopback or bool(mapped is not None and mapped.is_loopback)
+            except ValueError:
+                loopback = False
+            if not loopback:
+                raise InvalidConfigError(
+                    f"request host localhost for provider '{self.provider}' resolves to {addr[:64]}, not a loopback "
+                    f"address (dispatch_group local, D-7.2)"
+                )
+
~~~~

## H18 — .claude/adapters/loa_cheval/providers/openai_adapter.py — head lines 220–222

Head context (head/.claude/adapters/loa_cheval/providers/openai_adapter.py, lines 208–234):

~~~~text
   208 |         # (truthful telemetry) — `text.format` on /v1/responses, `response_format`
   209 |         # on /chat/completions.
   210 |         meta = {**(result.metadata or {}), "schema_enforced": _schema_enforced(body)}
   211 |         if schema_rejected:
   212 |             meta["schema_rejected_by_server"] = True
   213 |         meta.setdefault("thinking_stripped", False)
   214 |         result.metadata = meta
   215 |         return result
   216 | 
   217 |     def _transport_policy(self, model_config: ModelConfig) -> Optional[TransportPolicy]:
   218 |         """The D-7.2 TransportPolicy when the provider carries an insecure-endpoint
   219 |         opt-in or the model's dispatch_group is `local`; None otherwise (hosted
>  220 |         providers keep today's transport unchanged)."""
>  221 |         if getattr(self.config, "allow_insecure_endpoint", None) or getattr(model_config, "dispatch_group", None) == "local":
>  222 |             return TransportPolicy(endpoint=self.config.endpoint, provider=self.provider)
   223 |         return None
   224 | 
   225 |     def _dispatch(
   226 |         self,
   227 |         url: str,
   228 |         headers: Dict[str, str],
   229 |         body: Dict[str, Any],
   230 |         family: str,
   231 |         policy: Optional[TransportPolicy],
   232 |         model_data: Dict[str, Any],
   233 |     ) -> CompletionResult:
   234 |         # Sprint 4A DISS-001 closure: centralized kill-switch detection so
~~~~

The change from head to the fix:

~~~~diff
@@ -220,3 +220,5 @@
-        providers keep today's transport unchanged)."""
-        if getattr(self.config, "allow_insecure_endpoint", None) or getattr(model_config, "dispatch_group", None) == "local":
-            return TransportPolicy(endpoint=self.config.endpoint, provider=self.provider)
+        providers keep today's transport unchanged). A local hop also carries the
+        local-hop host rule (D-8.1, r257-1)."""
+        local = getattr(model_config, "dispatch_group", None) == "local"
+        if getattr(self.config, "allow_insecure_endpoint", None) or local:
+            return TransportPolicy(endpoint=self.config.endpoint, provider=self.provider, local=local)
~~~~

## H19 — .claude/adapters/loa_cheval/types.py — insertion after head line 542

Head context (head/.claude/adapters/loa_cheval/types.py, lines 531–554):

~~~~text
   531 |     machine-readable seam planners read as "not planned", never as a failed voice.
   532 |     """
   533 | 
   534 |     failure_class = "opt_in_required"
   535 |     MESSAGE = ("agy headless route is opt-in: set hounfour.headless.agy_opt_in: true (the prompt travels on the CLI's "
   536 |                "argv, readable by local users; the CLI must be OAuth-authed)")
   537 | 
   538 |     def __init__(self, message: str = MESSAGE):
   539 |         # (review r251-1 G5: through the base constructor — cheval's error envelope and MODELINV read `context`)
   540 |         super().__init__(message, context={"failure_class": self.failure_class})
   541 | 
   542 | 
   543 | class AuthRevokedError(ChevalError):
   544 |     """Runtime auth-credential revocation on a CLI/subscription leg (KF-017/#1071).
   545 | 
   546 |     Distinct from ConfigError (INVALID_CONFIG / static misconfig). A token that
   547 |     WAS valid and is now server-side-invalidated ("401 Unauthorized: token
   548 |     invalidated", expired session) makes THIS leg unusable but says nothing
   549 |     about the operator's other legs. retryable=True, code AUTH_REVOKED so the
   550 |     cheval chain-walk loop walks to the next entry (e.g. a valid HTTP leg)
   551 |     rather than hard-aborting. NOT a ProviderUnavailableError subclass: it must
   552 |     reach cheval.py via retry.py's `except ChevalError: raise`, like
   553 |     EmptyContentError. STATIC misconfig still raises ConfigError (hard-abort) so
   554 |     operator config errors are never silently masked.
~~~~

The change from head to the fix:

~~~~diff
@@ -542,0 +543,12 @@
+class LocalityRefusedError(ConfigError):
+    """Under ``hounfour.locality: local_voices`` every hop of the resolved chain fails the local-hop rule (cycle-129
+    audit a257-1 MEDIUM-A1, SDD D-8.1): cheval refuses the call before any dispatch — never a silent reroute.
+    ``failure_class: locality_refused`` (also in ``context``) is the machine-readable seam MODELINV records."""
+
+    failure_class = "locality_refused"
+
+    def __init__(self, message: str):
+        super().__init__(message, context={"failure_class": self.failure_class})
+        self.detail = message   # (the bare refusal, `locality: local_voices refuses every hop of <alias> …`)
+
+
~~~~

## H20 — .claude/adapters/tests/test_config_examples_load.py — head line 134

Head context (head/.claude/adapters/tests/test_config_examples_load.py, lines 122–146):

~~~~text
   122 |     cfg["providers"]["local"]["auth"] = "local"
   123 |     merged = _load(tmp_path, cfg)
   124 |     assert merged["providers"]["local"]["keyless"] is True
   125 | 
   126 | 
   127 | # --- refusals at load ------------------------------------------------------------------------------------
   128 | 
   129 | 
   130 | def _local(**overrides: Any) -> Dict[str, Any]:
   131 |     cfg = copy.deepcopy(_BY_NAME["local-openai-compatible"])
   132 |     prov = cfg["providers"]["local"]
   133 |     for k, v in overrides.items():
>  134 |         if v is None:
   135 |             prov.pop(k, None)
   136 |         else:
   137 |             prov[k] = v
   138 |     return cfg
   139 | 
   140 | 
   141 | REFUSALS = [
   142 |     ("public-http-host", dict(endpoint="http://8.8.8.8/v1", allow_insecure_endpoint=None), "ENDPOINT-INSECURE-SCHEME"),
   143 |     ("public-http-dns", dict(endpoint="http://api.example.com/v1", allow_insecure_endpoint=None),
   144 |      "ENDPOINT-INSECURE-SCHEME"),
   145 |     ("boolean-optin", dict(allow_insecure_endpoint=True), "ENDPOINT-OPTIN-BOOLEAN"),
   146 |     ("optin-public-host", dict(endpoint="http://8.8.8.8/v1", allow_insecure_endpoint="8.8.8.8"),
~~~~

The change from head to the fix:

~~~~diff
@@ -134 +134,3 @@
-        if v is None:
+        if k == "model_dispatch_group":   # relabel the example's one model (r257-1: a local label changes the rule)
+            prov["models"]["qwen3-coder-30b"]["dispatch_group"] = v
+        elif v is None:
~~~~

## H21 — .claude/adapters/tests/test_config_examples_load.py — head lines 158–161

Head context (head/.claude/adapters/tests/test_config_examples_load.py, lines 146–173):

~~~~text
   146 |     ("optin-public-host", dict(endpoint="http://8.8.8.8/v1", allow_insecure_endpoint="8.8.8.8"),
   147 |      "ENDPOINT-OPTIN-NOT-LOCAL"),
   148 |     ("optin-dns-name", dict(endpoint="http://llm.internal/v1", allow_insecure_endpoint="llm.internal"),
   149 |      "ENDPOINT-OPTIN-DNS-NAME"),
   150 |     ("optin-link-local", dict(endpoint="http://169.254.10.10/v1", allow_insecure_endpoint="169.254.10.10"),
   151 |      "ENDPOINT-OPTIN-LINK-LOCAL"),
   152 |     ("optin-metadata", dict(endpoint="http://169.254.169.254/v1", allow_insecure_endpoint="169.254.169.254"),
   153 |      "ENDPOINT-OPTIN-METADATA"),
   154 |     ("optin-ipv6-ula", dict(endpoint="http://[fd12::1]:8000/v1", allow_insecure_endpoint="fd12::1"),
   155 |      "ENDPOINT-OPTIN-NOT-LOCAL"),
   156 |     ("mismatched-host", dict(endpoint="http://localhost:8000/v1", allow_insecure_endpoint="127.0.0.1"),
   157 |      "ENDPOINT-INSECURE-HOST-MISMATCH"),
>  158 |     ("https-loopback-without-optin", dict(endpoint="https://127.0.0.1:8000/v1", allow_insecure_endpoint=None),
>  159 |      "ENDPOINT-IP-BLOCKED"),
>  160 |     ("https-private-without-optin", dict(endpoint="https://10.0.0.5/v1", allow_insecure_endpoint=None),
>  161 |      "ENDPOINT-IP-BLOCKED"),
   162 |     ("https-metadata-without-optin", dict(endpoint="https://169.254.169.254/v1", allow_insecure_endpoint=None),
   163 |      "ENDPOINT-IP-BLOCKED"),
   164 |     ("userinfo", dict(endpoint="http://u:p@127.0.0.1:8000/v1"), "ENDPOINT-USERINFO-PRESENT"),
   165 | ]
   166 | 
   167 | 
   168 | @pytest.mark.parametrize("case, overrides, code", REFUSALS, ids=[c for c, _, _ in REFUSALS])
   169 | def test_refused_at_load_with_a_named_reason(tmp_path, case, overrides, code):
   170 |     with pytest.raises(EndpointPolicyError) as info:
   171 |         _load(tmp_path, _local(**overrides))
   172 |     assert info.value.policy_code == code, str(info.value)
   173 |     assert f"[{code}]" in str(info.value) and "providers.local" in str(info.value)
~~~~

The change from head to the fix:

~~~~diff
@@ -158,4 +160,6 @@
-    ("https-loopback-without-optin", dict(endpoint="https://127.0.0.1:8000/v1", allow_insecure_endpoint=None),
-     "ENDPOINT-IP-BLOCKED"),
-    ("https-private-without-optin", dict(endpoint="https://10.0.0.5/v1", allow_insecure_endpoint=None),
-     "ENDPOINT-IP-BLOCKED"),
+    # A provider NOT labelled dispatch_group local keeps the loopback/private refusal on https; a local-labelled one
+    # is admitted without an opt-in (tests/test_local_dispatch_group_rule.py, r257-1).
+    ("https-loopback-without-optin", dict(endpoint="https://127.0.0.1:8000/v1", allow_insecure_endpoint=None,
+                                          model_dispatch_group="lab-gpu"), "ENDPOINT-IP-BLOCKED"),
+    ("https-private-without-optin", dict(endpoint="https://10.0.0.5/v1", allow_insecure_endpoint=None,
+                                         model_dispatch_group="lab-gpu"), "ENDPOINT-IP-BLOCKED"),
~~~~

## H22 — .claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json — head lines 66–67

Head context (head/.claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json, lines 54–79):

~~~~text
    54 |           "fallback_from": {
    55 |             "type": "string",
    56 |             "minLength": 1
    57 |           },
    58 |           "fallback_to": {
    59 |             "type": "string",
    60 |             "minLength": 1
    61 |           },
    62 |           "retryable": {
    63 |             "type": "boolean"
    64 |           },
    65 |           "failure_class": {
>   66 |             "description": "cycle-127 review r251-2 K2. A finer class under error_class: opt_in_required (an agy-alone chain refused by hounfour.headless.agy_opt_in, error_class INVALID_CONFIG); context_window_refused (cycle-129 FR-7, SDD D-7.2: the hop's estimated input exceeded its declared context_window, the hop was refused and the input never truncated, error_class ROUTING_MISS). Optional/additive.",
>   67 |             "enum": ["opt_in_required", "context_window_refused"]
    68 |           },
    69 |           "provider": {
    70 |             "description": "cycle-104 Sprint 2 (T2.6 / FR-S2.3). Provider key for this entry (e.g. openai, anthropic, google). Optional for backward compat; new emitters MUST populate.",
    71 |             "type": "string",
    72 |             "minLength": 1
    73 |           },
    74 |           "missing_capabilities": {
    75 |             "description": "cycle-104 Sprint 2 (FR-S2.7). Populated when error_class=CAPABILITY_MISS; lists the capabilities the request required that this entry does not declare.",
    76 |             "type": "array",
    77 |             "items": {
    78 |               "type": "string",
    79 |               "minLength": 1
~~~~

The change from head to the fix:

~~~~diff
@@ -66,2 +66,2 @@
-            "description": "cycle-127 review r251-2 K2. A finer class under error_class: opt_in_required (an agy-alone chain refused by hounfour.headless.agy_opt_in, error_class INVALID_CONFIG); context_window_refused (cycle-129 FR-7, SDD D-7.2: the hop's estimated input exceeded its declared context_window, the hop was refused and the input never truncated, error_class ROUTING_MISS). Optional/additive.",
-            "enum": ["opt_in_required", "context_window_refused"]
+            "description": "cycle-127 review r251-2 K2. A finer class under error_class: opt_in_required (an agy-alone chain refused by hounfour.headless.agy_opt_in, error_class INVALID_CONFIG); context_window_refused (cycle-129 FR-7, SDD D-7.2: the hop's estimated input exceeded its declared context_window, the hop was refused and the input never truncated, error_class ROUTING_MISS); locality_refused (cycle-129 audit a257-1 MEDIUM-A1, SDD D-8.1: under hounfour.locality local_voices no hop of the chain passes the local-hop rule, the call was refused before any dispatch, error_class INVALID_CONFIG). Optional/additive.",
+            "enum": ["opt_in_required", "context_window_refused", "locality_refused"]
~~~~

## H23 — .claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json — head line 761

Head context (head/.claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json, lines 749–773):

~~~~text
   749 |     },
   750 |     "effort": {
   751 |       "description": "Cycle-114 FR-8: reasoning-effort level requested for this invocation (Anthropic output_config.effort on Opus 4.5+/Sonnet 4.6). Optional \u2014 absent on calls that did not set effort (model default = high). Lets the Empirical Model Economy roll-up report cost-per-clean-output by (skill x model x effort).",
   752 |       "enum": [
   753 |         "low",
   754 |         "medium",
   755 |         "high",
   756 |         "xhigh",
   757 |         "max"
   758 |       ]
   759 |     },
   760 |     "models_not_planned": {
>  761 |       "description": "Cycle-127 review r251-1 G1 (SDD D-1.3/D-1.6): chain hops cheval did NOT plan \u2014 never dispatched, not in models_requested, not a failure (verdict quality counts planned hops only; no circuit-breaker count). `opt_in_required`: an agy (gemini-headless) hop while hounfour.headless.agy_opt_in is not true. Also present on a direct agy call refused by the opt-in. Optional/additive.",
   762 |       "type": "array",
   763 |       "items": {
   764 |         "type": "object",
   765 |         "required": [
   766 |           "model",
   767 |           "reason"
   768 |         ],
   769 |         "additionalProperties": false,
   770 |         "properties": {
   771 |           "model": {
   772 |             "type": "string",
   773 |             "minLength": 1
~~~~

The change from head to the fix:

~~~~diff
@@ -761 +761 @@
-      "description": "Cycle-127 review r251-1 G1 (SDD D-1.3/D-1.6): chain hops cheval did NOT plan \u2014 never dispatched, not in models_requested, not a failure (verdict quality counts planned hops only; no circuit-breaker count). `opt_in_required`: an agy (gemini-headless) hop while hounfour.headless.agy_opt_in is not true. Also present on a direct agy call refused by the opt-in. Optional/additive.",
+      "description": "Cycle-127 review r251-1 G1 (SDD D-1.3/D-1.6): chain hops cheval did NOT plan \u2014 never dispatched, not in models_requested, not a failure (verdict quality counts planned hops only; no circuit-breaker count). `opt_in_required`: an agy (gemini-headless) hop while hounfour.headless.agy_opt_in is not true. Also present on a direct agy call refused by the opt-in. `locality_refused` (cycle-129 audit a257-1 MEDIUM-A1): under hounfour.locality local_voices, a hop that fails the local-hop rule while another hop of the chain passes it. Optional/additive.",
~~~~

## H24 — .claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json — head line 781

Head context (head/.claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json, lines 769–793):

~~~~text
   769 |         "additionalProperties": false,
   770 |         "properties": {
   771 |           "model": {
   772 |             "type": "string",
   773 |             "minLength": 1
   774 |           },
   775 |           "provider": {
   776 |             "type": "string",
   777 |             "minLength": 1
   778 |           },
   779 |           "reason": {
   780 |             "enum": [
>  781 |               "opt_in_required"
   782 |             ]
   783 |           }
   784 |         }
   785 |       }
   786 |     },
   787 |     "effort_source": {
   788 |       "description": "Cycle-127 FR-2 (SDD D-2.3/D-2.5): where `effort` came from \u2014 `caller` (explicit --effort), `catalog` (the resolved entry's params.default_effort), `extra` (a CLI entry's legacy extra.effort) or `none` (nothing sent; vendor default). Optional/additive.",
   789 |       "enum": [
   790 |         "caller",
   791 |         "catalog",
   792 |         "extra",
   793 |         "none"
~~~~

The change from head to the fix:

~~~~diff
@@ -781 +781,2 @@
-              "opt_in_required"
+              "opt_in_required",
+              "locality_refused"
~~~~

## H25 — .claude/loa/reference/multi-model-reference.md — head lines 102–104

Head context (head/.claude/loa/reference/multi-model-reference.md, lines 90–112):

~~~~text
    90 | cycle-124 adds one **backstop** (not a rollback): `LOA_CHEVAL_LEGACY_WIRE=1`
    91 | makes the Anthropic adapter emit the pre-cycle-124 request body (no adaptive
    92 | `thinking`, no `cache_control` blocks, 4096 default `max_tokens`) so a wire
    93 | regression can be neutralised without a deploy while the credentialed
    94 | `live-floor-check.yml` is still unprobed. It removes what cycle-124 ADDED, no
    95 | more: temperature omission is catalog-driven and stays, and on Opus 5 /
    96 | Sonnet 5 / Fable the server runs thinking whether or not the block is sent, so
    97 | pass `--max-tokens` explicitly on those ids under the switch (the
    98 | `max_tokens` stop warning still fires). The code path stays; reverting is
    99 | still `git revert` of the cycle-124 unit commits (see the Sprint 1 rollback
   100 | proof). Env table: `grimoires/loa/runbooks/cheval-delegate-architecture.md`.
   101 | 
>  102 | cycle-129 (FR-8) — **local posture**: under `hounfour.locality: local_voices` the dissent, Flatline, Bridgebuilder and health-probe hops are planned only on providers whose model entry says `dispatch_group: local`, each hosted hop refused by name at plan time; the Claude Code session model is exempt and remains the platform, so a local posture keeps model calls local but the session itself still runs against Anthropic. Fewer voices means a DEGRADED verdict quality where the planned voice count is not met — the posture says so in the config comment and in the run output rather than inventing a voice. One fail-closed classifier (`.claude/scripts/lib/hop-locality.py`) serves the shell scripts: an unresolved hop, an unreadable config or a local entry whose fallback chain reaches a hosted entry counts as hosted; an invalid value refuses the run.
>  103 | 
>  104 | cycle-129 (FR-7) — **open-weight and local voices**: a local OpenAI-compatible server is declared as a provider (`type: openai_compat`, `keyless: true`, `allow_insecure_endpoint: "<host>"` where the host is a loopback or RFC1918 IP literal or `localhost`; Example 4 in `.loa.config.yaml.example`). The endpoint rule lives once in `.claude/scripts/lib/endpoint-validator.py` and is used by the cheval loader (`loa_cheval/config/endpoint_policy.py`), the bash wrapper and `model-health-probe.sh --provider <name>`, which probes a configured provider's `/models` with no credential when keyless; at request time a local hop runs with no proxy, no redirects and the declared path prefix. cheval refuses an `http`, loopback or private endpoint without the opt-in at load, for every provider. On the chat-completions path a `structured_json` entry sends `response_format` json_schema and `schema_enforced` is derived from the body sent (one retry without the schema on a server 400 that names it); `reasoning_content`, `reasoning` deltas and a leading `<think>` block go to `thinking` (`thinking_stripped`); an over-window prompt is refused by name. **Advisory voices**: `flatline_protocol.code_review.advisory_voices` and `security_audit.advisory_voices` run beside the counted voices under `advisory_timeout_seconds`; their findings appear only under `advisory_voices[].findings` with `duplicate_of` links and never touch the verdict, the counts or the cost totals — promotion to a counted role needs `hounfour.advisory_promotion`. The budget gate prices each planned voice from the catalog (`loa_cheval.metering.pricing --alias … --json`), whose entries now carry `open_weight`, `price_source` and `price_date`. **Bridgebuilder** reads `hounfour.providers`, `hounfour.locality` and `bridgebuilder.exit_on_degraded` from trusted configuration only (locally the working tree; on a pull request the `BRIDGEBUILDER_TRUSTED_CONFIG` repository variable, else the base branch's config, never the head), prints `completed/planned` voices and exits 3 on a DEGRADED consensus (`0` restores the old exit; `entry.sh`'s dependency preflight exits 4).
   105 | 
   106 | ### Verification (cycle-107 sprint-1 + cycle-109 sprint-2/3 cumulative)
   107 | 
   108 | - FL 3-model run: 549s, 3 voices' MODELINV envelopes recorded, chains populated, all primaries succeeded
   109 | - RT review: 1 MODELINV envelope, cheval audit signature confirmed
   110 | - BB: verified via cycle-104 sprint-3 T3.4 (4/4 trials at 297-539KB clean)
   111 | - **cycle-109 Sprint 2**: 234 new tests; verdict-quality envelope wired through 7/7 IMP-004 consumers; 5 canonical regression fixtures (#807/#809/#823/#868/KF-002 PRD-review) locked in conformance matrix.
   112 | - **cycle-109 Sprint 3 progress**: T3.1 matrix scaffold + T3.2-T3.5 Cluster B fixes (#864/#863/#793/#820) + T3.6 feature-flag removal + T3.10 activation regression CI workflow. 810-cell matrix wired into `.github/workflows/activation-regression.yml`.
~~~~

The change from head to the fix:

~~~~diff
@@ -102,3 +102,3 @@
-cycle-129 (FR-8) — **local posture**: under `hounfour.locality: local_voices` the dissent, Flatline, Bridgebuilder and health-probe hops are planned only on providers whose model entry says `dispatch_group: local`, each hosted hop refused by name at plan time; the Claude Code session model is exempt and remains the platform, so a local posture keeps model calls local but the session itself still runs against Anthropic. Fewer voices means a DEGRADED verdict quality where the planned voice count is not met — the posture says so in the config comment and in the run output rather than inventing a voice. One fail-closed classifier (`.claude/scripts/lib/hop-locality.py`) serves the shell scripts: an unresolved hop, an unreadable config or a local entry whose fallback chain reaches a hosted entry counts as hosted; an invalid value refuses the run.
+cycle-129 (FR-8) — **local posture**: under `hounfour.locality: local_voices` the dissent, Flatline, Bridgebuilder and health-probe hops are planned only on providers whose model entry says `dispatch_group: local`, each hosted hop refused by name at plan time; the Claude Code session model is exempt and remains the platform, so a local posture keeps model calls local but the session itself still runs against Anthropic. Fewer voices means a DEGRADED verdict quality where the planned voice count is not met — the posture says so in the config comment and in the run output rather than inventing a voice. One fail-closed classifier (`.claude/scripts/lib/hop-locality.py`) serves the shell scripts: an unresolved hop, an unreadable config or a local entry whose fallback chain reaches a hosted entry counts as hosted; an invalid value refuses the run. A declared locality is enforced, not trusted: a hop is local only when its provider is an HTTP provider (not a CLI provider) whose endpoint host is an IP literal in a loopback (`127.0.0.0/8`, `::1`) or RFC1918 (`10/8`, `172.16/12`, `192.168/16`) range, or the literal `localhost` — the host rule of `allow_insecure_endpoint` (an `https` endpoint on such a host needs no opt-in; an `http` one does). The rule is applied at config load (the cheval loader refuses any other `dispatch_group: local` by name), at request time (the local hop's transport policy refuses a request host that fails it), in the planner (`hop-locality.py`: `endpoint_not_local:<host>`) and in Bridgebuilder's locality filter. Under `local_voices` cheval itself plans around every chain hop that fails the rule (one stderr line `locality: local_voices refuses hosted hop <provider>:<model> (fallback of <alias>)`; a chain with no local hop refuses the call with MODELINV `failure_class: locality_refused`), the loader refuses a `dispatch_group: local` model whose `fallback_chain` reaches a hosted hop, and Bridgebuilder walks a local voice's `fallback_chain` the same way; under `hosted` a local model may still fall back to a hosted one. A `localhost` endpoint is resolved and checked at request time (every address loopback, a resolver failure refuses); IP literals are never resolved.
 
-cycle-129 (FR-7) — **open-weight and local voices**: a local OpenAI-compatible server is declared as a provider (`type: openai_compat`, `keyless: true`, `allow_insecure_endpoint: "<host>"` where the host is a loopback or RFC1918 IP literal or `localhost`; Example 4 in `.loa.config.yaml.example`). The endpoint rule lives once in `.claude/scripts/lib/endpoint-validator.py` and is used by the cheval loader (`loa_cheval/config/endpoint_policy.py`), the bash wrapper and `model-health-probe.sh --provider <name>`, which probes a configured provider's `/models` with no credential when keyless; at request time a local hop runs with no proxy, no redirects and the declared path prefix. cheval refuses an `http`, loopback or private endpoint without the opt-in at load, for every provider. On the chat-completions path a `structured_json` entry sends `response_format` json_schema and `schema_enforced` is derived from the body sent (one retry without the schema on a server 400 that names it); `reasoning_content`, `reasoning` deltas and a leading `<think>` block go to `thinking` (`thinking_stripped`); an over-window prompt is refused by name. **Advisory voices**: `flatline_protocol.code_review.advisory_voices` and `security_audit.advisory_voices` run beside the counted voices under `advisory_timeout_seconds`; their findings appear only under `advisory_voices[].findings` with `duplicate_of` links and never touch the verdict, the counts or the cost totals — promotion to a counted role needs `hounfour.advisory_promotion`. The budget gate prices each planned voice from the catalog (`loa_cheval.metering.pricing --alias … --json`), whose entries now carry `open_weight`, `price_source` and `price_date`. **Bridgebuilder** reads `hounfour.providers`, `hounfour.locality` and `bridgebuilder.exit_on_degraded` from trusted configuration only (locally the working tree; on a pull request the `BRIDGEBUILDER_TRUSTED_CONFIG` repository variable, else the base branch's config, never the head), prints `completed/planned` voices and exits 3 on a DEGRADED consensus (`0` restores the old exit; `entry.sh`'s dependency preflight exits 4).
+cycle-129 (FR-7) — **open-weight and local voices**: a local OpenAI-compatible server is declared as a provider (`type: openai_compat`, `keyless: true`, `allow_insecure_endpoint: "<host>"` where the host is a loopback or RFC1918 IP literal or `localhost`; Example 4 in `.loa.config.yaml.example`). The endpoint rule lives once in `.claude/scripts/lib/endpoint-validator.py` and is used by the cheval loader (`loa_cheval/config/endpoint_policy.py`), the bash wrapper and `model-health-probe.sh --provider <name>`, which probes a configured provider's `/models` with no credential when keyless; at request time a local hop runs with no proxy, no redirects and the declared path prefix. cheval refuses an `http`, loopback or private endpoint without the opt-in at load, for every provider. On the chat-completions path a `structured_json` entry sends `response_format` json_schema and `schema_enforced` is derived from the body sent (one retry without the schema on a server 400 that names it); `reasoning_content`, `reasoning` deltas and a leading `<think>` block go to `thinking` (`thinking_stripped`); an over-window prompt is refused by name. **Advisory voices**: `flatline_protocol.code_review.advisory_voices` and `security_audit.advisory_voices` run beside the counted voices under `advisory_timeout_seconds`; their findings appear only under `advisory_voices[].findings` with `duplicate_of` links and never touch the verdict, the counts or the cost totals — promotion to a counted role needs `hounfour.advisory_promotion`. The budget gate prices each planned voice from the catalog (`loa_cheval.metering.pricing --alias … --json`), whose entries now carry `open_weight`, `price_source` and `price_date`. **Bridgebuilder** reads `hounfour.providers`, `hounfour.locality` and `bridgebuilder.exit_on_degraded` from trusted configuration only (locally the working tree; on a pull request the `BRIDGEBUILDER_TRUSTED_CONFIG` repository variable, else the base branch's config, never the head), prints `completed/planned` voices and exits 3 on a DEGRADED consensus (`0` restores the old exit; `entry.sh`'s dependency preflight exits 4). cheval reads the checkout's configuration for the dispatch, so a pull request whose head changes `hounfour.providers`, `hounfour.aliases`, `hounfour.locality` or the secret allowlist is refused by name before any voice is planned (`trusted config drift refused: <keys> differ between the PR head and <source>`, exit 5): merge the base branch into the head or set `BRIDGEBUILDER_TRUSTED_CONFIG`.
~~~~

## H26 — .claude/scripts/adversarial-review.sh — insertion after head line 3889

Head context (head/.claude/scripts/adversarial-review.sh, lines 3878–3901):

~~~~text
  3878 |   local k _bv_role _bv_hop _bv_src _bv_in _bv_out _bv_cents
  3879 |   for (( k = 0; k < ${#hops[@]}; k++ )); do
  3880 |     _bv_role="${roles[$k]}"; _bv_hop="${hops[$k]}"   # (a role word and a validated hop name — the jq operands below are small)
  3881 |     line=$(awk -v a="alias=$_bv_hop" '$1 == a { print; exit }' <<<"$rows")
  3882 |     _bv_in=$(sed -n 's/.* input_per_mtok=\([0-9][0-9]*\) .*/\1/p' <<<"$line")
  3883 |     _bv_out=$(sed -n 's/.* output_per_mtok=\([0-9][0-9]*\) .*/\1/p' <<<"$line")
  3884 |     _bv_src=$(sed -n 's/.* pricing_source=\([a-z_]*\)$/\1/p' <<<"$line")
  3885 |     if [[ ! "$_bv_in" =~ ^[0-9]{1,12}$ || ! "$_bv_out" =~ ^[0-9]{1,12}$ || "$_bv_src" == "unknown" || -z "$_bv_src" ]]; then
  3886 |       _bv_in=10000000; _bv_out=30000000; _bv_src="fallback"
  3887 |       log "budget: no catalog price for $_bv_hop ($_bv_role) — the fixed 10 / 30 USD per Mtok applies to this voice"
  3888 |     elif (( _bv_in == 0 && _bv_out == 0 )); then
  3889 |       log "budget: $_bv_hop ($_bv_role) is zero-priced in the catalog — estimated 0c"
  3890 |     elif [[ "$_bv_src" == "stale_catalog" ]]; then
  3891 |       log "budget: $_bv_hop ($_bv_role) has a stale catalog price (price_date older than 90 days) — used as given"
  3892 |     fi
  3893 |     c_in=$(( tokens * _bv_in / 10000000000 )); c_out=$(( 2000 * _bv_out / 10000000000 )); _bv_cents=$(( c_in + c_out ))
  3894 |     total=$(( total + _bv_cents ))
  3895 |     voices=$(jq -c --arg r "$_bv_role" --arg h "$_bv_hop" --arg s "$_bv_src" --argjson c "$_bv_cents" --argjson i "$_bv_in" --argjson o "$_bv_out" \
  3896 |       '. + [{role: $r, alias: $h, estimated_cents: $c, input_per_mtok: $i, output_per_mtok: $o, pricing_source: $s}]' <<<"$voices")
  3897 |   done
  3898 |   _ADV_BUDGET_TOTAL="$total"; _ADV_BUDGET_VOICES="$voices"
  3899 |   log "budget: estimate ${total}c over ${#hops[@]} planned voice(s) ($(jq -r 'map("\(.role) \(.alias) \(.estimated_cents)c") | join(", ")' <<<"$voices"))"
  3900 | }
  3901 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -3889,0 +3890,8 @@
+      # audit a257-1 LOW-A3: a zero price is expected only on an open-weight (local) entry; on any other it is a pricing
+      # overlay that would zero both this estimate and the ledger — said by name (warning only: metering is unchanged).
+      # The open_weight flag is read from the same CLI's --json row; an unreadable answer warns (fail loud).
+      local _bv_ow=""
+      _bv_ow=$(PYTHONSAFEPATH=1 PYTHONPATH="$PROJECT_ROOT/.claude/adapters" python3 -W ignore::RuntimeWarning -m loa_cheval.metering.pricing \
+        --catalog "${LOA_MODEL_CONFIG:-$PROJECT_ROOT/.claude/defaults/model-config.yaml}" --config "${CONFIG_FILE:-}" --json --alias "$_bv_hop" 2>/dev/null \
+        | jq -r --arg a "$_bv_hop" 'select(.alias == $a) | .open_weight' 2>/dev/null | head -n 1) || _bv_ow=""
+      [[ "$_bv_ow" == "true" ]] || log "budget: zero price on $_bv_hop ($_bv_role), not marked open_weight — check the pricing overlay"
~~~~

## H27 — .claude/scripts/adversarial-review.sh — head line 4845

Head context (head/.claude/scripts/adversarial-review.sh, lines 4833–4857):

~~~~text
  4833 |   result=$(_apply_hallucination_filter "$result" "$diff_file")
  4834 | 
  4835 |   # twenty-sixth run, b2 DISS-C-002/003: the envelope says what it reviewed — a skill refused while another run held the lock
  4836 |   # adopts the envelope that run left only when the scope is the one it asked for (a chunk driver's tagged run reviews one chunk)
  4837 |   local _scope_sha="" _scoped=""
  4838 |   _scope_sha=$( { sha256_portable < "$diff_file" || shasum -a 256 < "$diff_file"; } 2>/dev/null | cut -c1-64) || _scope_sha=""
  4839 |   [[ "$_scope_sha" =~ ^[0-9a-f]{64}$ ]] || _scope_sha=""
  4840 |   if _scoped=$(jq -c --argjson sc "$(_adv_scope_json "$_scope_sha")" '.metadata.scope = $sc' <<<"$result" 2>/dev/null) && [[ -n "$_scoped" ]]; then
  4841 |     result="$_scoped"
  4842 |   fi
  4843 | 
  4844 |   # cycle-129 FR-8 (D-8.1): a local_voices envelope says so — the refused hops by name and, on the audit gate, the
> 4845 |   # DEGRADED sentence (absent under hosted: the default envelope is unchanged)
  4846 |   if [[ "$CONF_LOCALITY" == "local_voices" ]]; then
  4847 |     local _locj _locf="$_ADVERSARIAL_WORKDIR/locality-refused.json"
  4848 |     _adv_locality_refused_json > "$_locf" 2>/dev/null || printf '[]' > "$_locf"
  4849 |     if _locj=$(jq -c --slurpfile rf "$_locf" --arg t "$type" --arg s "$_ADV_LOC_DEGRADED_SENTENCE" \
  4850 |         '.metadata.locality = ({mode: "local_voices", refused: $rf[0]} + (if $t == "audit" then {note: $s} else {} end))' <<<"$result" 2>/dev/null) \
  4851 |         && [[ -n "$_locj" ]]; then
  4852 |       result="$_locj"
  4853 |     fi
  4854 |   fi
  4855 | 
  4856 |   # cycle-129 FR-7 (D-7.4, DEC-0165): the advisory voices run now — after the counted voices, on the same prompts, under one
  4857 |   # wall clock — and their findings are written ONLY under advisory_voices[]: every other key of the envelope, the voice
~~~~

The change from head to the fix:

~~~~diff
@@ -4845 +4853,4 @@
-  # DEGRADED sentence (absent under hosted: the default envelope is unchanged)
+  # DEGRADED sentence (absent under hosted: the default envelope is unchanged). Audit a257-1 LOW-A2: the one-family case
+  # is machine-readable — `degraded_security_review: true` on an audit whose companion is not an independent second
+  # voice (duplicate_voice, not planned, failed or the sole voice), with the sentence; `false` otherwise (a review, or
+  # an audit with an independent companion). verdict_quality, verdict-derive.sh and the artefact gate do not read it.
~~~~

## H28 — .claude/scripts/adversarial-review.sh — head line 4850

Head context (head/.claude/scripts/adversarial-review.sh, lines 4838–4862):

~~~~text
  4838 |   _scope_sha=$( { sha256_portable < "$diff_file" || shasum -a 256 < "$diff_file"; } 2>/dev/null | cut -c1-64) || _scope_sha=""
  4839 |   [[ "$_scope_sha" =~ ^[0-9a-f]{64}$ ]] || _scope_sha=""
  4840 |   if _scoped=$(jq -c --argjson sc "$(_adv_scope_json "$_scope_sha")" '.metadata.scope = $sc' <<<"$result" 2>/dev/null) && [[ -n "$_scoped" ]]; then
  4841 |     result="$_scoped"
  4842 |   fi
  4843 | 
  4844 |   # cycle-129 FR-8 (D-8.1): a local_voices envelope says so — the refused hops by name and, on the audit gate, the
  4845 |   # DEGRADED sentence (absent under hosted: the default envelope is unchanged)
  4846 |   if [[ "$CONF_LOCALITY" == "local_voices" ]]; then
  4847 |     local _locj _locf="$_ADVERSARIAL_WORKDIR/locality-refused.json"
  4848 |     _adv_locality_refused_json > "$_locf" 2>/dev/null || printf '[]' > "$_locf"
  4849 |     if _locj=$(jq -c --slurpfile rf "$_locf" --arg t "$type" --arg s "$_ADV_LOC_DEGRADED_SENTENCE" \
> 4850 |         '.metadata.locality = ({mode: "local_voices", refused: $rf[0]} + (if $t == "audit" then {note: $s} else {} end))' <<<"$result" 2>/dev/null) \
  4851 |         && [[ -n "$_locj" ]]; then
  4852 |       result="$_locj"
  4853 |     fi
  4854 |   fi
  4855 | 
  4856 |   # cycle-129 FR-7 (D-7.4, DEC-0165): the advisory voices run now — after the counted voices, on the same prompts, under one
  4857 |   # wall clock — and their findings are written ONLY under advisory_voices[]: every other key of the envelope, the voice
  4858 |   # counts and verdict_quality are already final and are not touched. A failed or timed-out voice is a status in its entry.
  4859 |   if [[ -n "$CONF_ADVISORY_VOICES" ]]; then
  4860 |     if (( ${#advisory_planned[@]} > 0 )); then
  4861 |       log "Advisory voices: ${advisory_planned[*]} (wall clock ${CONF_ADVISORY_TIMEOUT}s; findings under advisory_voices[] only, never counted)"
  4862 |       _adv_run_advisory_voices "$type" "$sprint_id" "$timeout" "$diff_files" "${advisory_planned[@]}" || log "Advisory voices: the advisory workdir could not be made — none ran"
~~~~

The change from head to the fix:

~~~~diff
@@ -4850 +4861,3 @@
-        '.metadata.locality = ({mode: "local_voices", refused: $rf[0]} + (if $t == "audit" then {note: $s} else {} end))' <<<"$result" 2>/dev/null) \
+        '(($t == "audit") and ((.metadata.companion_voice.counted_as // null) != "independent_voice")) as $dsr
+         | .metadata.locality = ({mode: "local_voices", refused: $rf[0], degraded_security_review: $dsr}
+                                 + (if $dsr then {note: $s} else {} end))' <<<"$result" 2>/dev/null) \
~~~~

## H29 — .claude/scripts/lib/hop-locality.py — insertion after head line 15

Head context (head/.claude/scripts/lib/hop-locality.py, lines 4–27):

~~~~text
     4 | 
     5 |     python3 -I hop-locality.py --catalog <model-config.yaml> --config <.loa.config.yaml> -- <hop>...
     6 | 
     7 | One tab-separated line per hop, in the order given:
     8 | 
     9 |     <hop> TAB <provider|unknown> TAB <local|hosted> TAB <reason>
    10 | 
    11 | A hop is `local` only when ALL of these hold in the merged view (the System Zone catalog overlaid with the project
    12 | config's `hounfour.providers` / `hounfour.aliases`, the two layers cheval merges):
    13 |   * it resolves (a `provider:id` pin, an alias chain, or a bare id that exactly one provider declares) to a model entry
    14 |     that exists;
    15 |   * that model entry, or its provider block, says `dispatch_group: local` (the canonical key, D-8.0);
    16 |   * every hop on the entry's own `fallback_chain` is local by the same rule — cheval walks that chain inside one call,
    17 |     so a local entry that falls back to a hosted one would leave the declared providers without the planner seeing it.
    18 | Everything else is `hosted`: an unresolved hop, an unreadable config, a headless CLI hop (its dispatch group is the
    19 | provider family's), the native session. Fail closed — a hop is never called local because it could not be read.
    20 | 
    21 | This file reads declarations only: it never dispatches, never reads credentials and never imports the cheval package
    22 | (run under `-I`, so neither the cwd nor PYTHONPATH reaches sys.path). The request-time rules for a local hop (IP-literal
    23 | or localhost endpoint, no DNS, redirects refused, proxy env ignored, destination logged) are cheval's.
    24 | """
    25 | from __future__ import annotations
    26 | 
    27 | import argparse
~~~~

The change from head to the fix:

~~~~diff
@@ -15,0 +16,6 @@
+  * the provider is an HTTP provider (not `kind: cli` / `*-headless`) whose `endpoint` host is an IP literal in a
+    loopback (127.0.0.0/8, ::1) or RFC1918 (10/8, 172.16/12, 192.168/16) range, or the literal `localhost` — the
+    local-hop rule (D-8.1, review round r257-1), the same host acceptance as the endpoint validator's
+    `check_insecure_optin`, mirrored here in stdlib `ipaddress` because this script cannot import the validator.
+    A declared locality is enforced, not trusted: otherwise the hop is hosted with reason `cli_provider`,
+    `endpoint_missing` or `endpoint_not_local:<host>`;
~~~~

## H30 — .claude/scripts/lib/hop-locality.py — head line 28

Head context (head/.claude/scripts/lib/hop-locality.py, lines 16–40):

~~~~text
    16 |   * every hop on the entry's own `fallback_chain` is local by the same rule — cheval walks that chain inside one call,
    17 |     so a local entry that falls back to a hosted one would leave the declared providers without the planner seeing it.
    18 | Everything else is `hosted`: an unresolved hop, an unreadable config, a headless CLI hop (its dispatch group is the
    19 | provider family's), the native session. Fail closed — a hop is never called local because it could not be read.
    20 | 
    21 | This file reads declarations only: it never dispatches, never reads credentials and never imports the cheval package
    22 | (run under `-I`, so neither the cwd nor PYTHONPATH reaches sys.path). The request-time rules for a local hop (IP-literal
    23 | or localhost endpoint, no DNS, redirects refused, proxy env ignored, destination logged) are cheval's.
    24 | """
    25 | from __future__ import annotations
    26 | 
    27 | import argparse
>   28 | import sys
    29 | from typing import Any, Dict, List, Optional, Tuple
    30 | 
    31 | MAX_DEPTH = 10
    32 | 
    33 | 
    34 | def _merge(base: Any, overlay: Any) -> Any:
    35 |     if isinstance(base, dict) and isinstance(overlay, dict):
    36 |         out = dict(base)
    37 |         for key, value in overlay.items():
    38 |             out[key] = _merge(base.get(key), value) if key in base else value
    39 |         return out
    40 |     return overlay
~~~~

The change from head to the fix:

~~~~diff
@@ -28 +34,3 @@
+import ipaddress
 import sys
+import re
~~~~

## H31 — .claude/scripts/lib/hop-locality.py — insertion after head line 32

Head context (head/.claude/scripts/lib/hop-locality.py, lines 21–44):

~~~~text
    21 | This file reads declarations only: it never dispatches, never reads credentials and never imports the cheval package
    22 | (run under `-I`, so neither the cwd nor PYTHONPATH reaches sys.path). The request-time rules for a local hop (IP-literal
    23 | or localhost endpoint, no DNS, redirects refused, proxy env ignored, destination logged) are cheval's.
    24 | """
    25 | from __future__ import annotations
    26 | 
    27 | import argparse
    28 | import sys
    29 | from typing import Any, Dict, List, Optional, Tuple
    30 | 
    31 | MAX_DEPTH = 10
    32 | 
    33 | 
    34 | def _merge(base: Any, overlay: Any) -> Any:
    35 |     if isinstance(base, dict) and isinstance(overlay, dict):
    36 |         out = dict(base)
    37 |         for key, value in overlay.items():
    38 |             out[key] = _merge(base.get(key), value) if key in base else value
    39 |         return out
    40 |     return overlay
    41 | 
    42 | 
    43 | def load_merged(catalog_path: str, config_path: Optional[str]) -> Dict[str, Any]:
    44 |     import yaml
~~~~

The change from head to the fix:

~~~~diff
@@ -32,0 +41,64 @@
+# The local-hop rule's ranges — the same as endpoint-validator.py `_OPTIN_LOOPBACK` / `_OPTIN_RFC1918`.
+_LOCAL_NETS = tuple(ipaddress.ip_network(n) for n in (
+    "127.0.0.0/8", "::1/128", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"))
+
+
+def _canonical_host(host: str) -> str:
+    h = str(host).strip().lower()
+    if h.startswith("[") and h.endswith("]"):
+        h = h[1:-1]
+    if h.endswith(".") and not h.endswith(".."):
+        h = h[:-1]
+    try:
+        return str(ipaddress.ip_address(h))
+    except ValueError:
+        return h
+
+
+_URL_RE = re.compile(r"^([A-Za-z][A-Za-z0-9+.-]*)://([^/?#]*)")  # scheme://authority
+
+
+def endpoint_locality(endpoint: Any) -> Tuple[bool, str]:
+    """(passes the local-hop rule, canonical host for the reason) for a provider endpoint."""
+    if not isinstance(endpoint, str) or not endpoint.strip():
+        return False, ""
+    # The authority is split by hand (no URL library: URL parsing is confined to the endpoint validator by the
+    # cycle-099 import guard, and this stdlib mirror runs where the validator cannot be imported) — the same split as
+    # Bridgebuilder's localEndpointHost: scheme://[userinfo@]host[:port], a bracketed IPv6 host, a numeric port.
+    m = _URL_RE.match(endpoint.strip())
+    if not m:
+        return False, "unparseable"
+    scheme, authority = m.group(1).lower(), m.group(2)
+    if "@" in authority:
+        authority = authority.rsplit("@", 1)[1]
+    if authority.startswith("["):
+        close = authority.find("]")
+        if close < 0:
+            return False, "unparseable"
+        raw_host, port = authority[1:close], authority[close + 1:]
+    else:
+        raw_host, sep, rest = authority.partition(":")
+        port = (":" + rest) if sep else ""
+    if port and not re.fullmatch(r":[0-9]*", port):
+        return False, "unparseable"
+    if len(port) > 1 and int(port[1:]) > 65535:
+        return False, "unparseable"
+    host = _canonical_host(raw_host)
+    if scheme not in ("http", "https") or not host:
+        return False, host or "unparseable"
+    if host == "localhost":
+        return True, host
+    try:
+        addr = ipaddress.ip_address(host)
+    except ValueError:
+        return False, host
+    return any(addr.version == net.version and addr in net for net in _LOCAL_NETS), host
+
+
+def _is_cli(block: Dict[str, Any], entry: Dict[str, Any]) -> bool:
+    if str(block.get("type") or "").endswith("-headless") or entry.get("kind") == "cli":
+        return True
+    models = block.get("models")
+    return isinstance(models, dict) and bool(models) and all(
+        isinstance(m, dict) and m.get("kind") == "cli" for m in models.values())
+
~~~~

## H32 — .claude/scripts/lib/hop-locality.py — insertion after head line 118

Head context (head/.claude/scripts/lib/hop-locality.py, lines 107–130):

~~~~text
   107 |     if target is None:
   108 |         return "unknown", "hosted", "unresolved"
   109 |     provider, model = target
   110 |     block = (merged.get("providers") or {}).get(provider)
   111 |     if not isinstance(block, dict):
   112 |         return provider, "hosted", "provider_not_declared"
   113 |     entry = (block.get("models") or {}).get(model) if isinstance(block.get("models"), dict) else None
   114 |     if not isinstance(entry, dict):
   115 |         return provider, "hosted", "model_not_declared"
   116 |     group = entry.get("dispatch_group") or block.get("dispatch_group") or ""
   117 |     if group != "local":
   118 |         return provider, "hosted", f"dispatch_group={group or 'unset'}"
   119 |     key = f"{provider}:{model}"
   120 |     if key in seen:
   121 |         return provider, "local", "dispatch_group=local"
   122 |     seen.add(key)
   123 |     chain = entry.get("fallback_chain") or []
   124 |     if not isinstance(chain, list):
   125 |         return provider, "hosted", "fallback_chain_unreadable"
   126 |     if _depth >= MAX_DEPTH:
   127 |         return provider, "hosted", "fallback_chain_too_deep"
   128 |     for nxt in chain:
   129 |         if not isinstance(nxt, str):
   130 |             return provider, "hosted", "fallback_chain_unreadable"
~~~~

The change from head to the fix:

~~~~diff
@@ -118,0 +191,5 @@
+    if _is_cli(block, entry):
+        return provider, "hosted", "cli_provider"
+    ok, host = endpoint_locality(block.get("endpoint"))
+    if not ok:
+        return provider, "hosted", (f"endpoint_not_local:{host}" if host else "endpoint_missing")
~~~~

## H33 — .claude/skills/auditing-security/SKILL.md — head lines 181–184

Head context (head/.claude/skills/auditing-security/SKILL.md, lines 169–196):

~~~~text
   169 | Run `.claude/scripts/security-audit-scope.sh` before detailed analysis. It categorises the surface into Sources, Sinks, Auth and LLM/AI files.
   170 | 
   171 | ## Phase 1A: Recon Pass
   172 | 
   173 | Catalog untrusted entry points and dangerous sinks without investigating yet (lists, trust levels: `resources/REFERENCE.md` §Sources and Sinks). Track them in a working file, e.g. `grimoires/loa/a2a/audits/YYYY-MM-DD/SECURITY_ANALYSIS_TODO.md`, with file:line, trust level and a status (`PENDING` → `CONFIRMED` / `SAFE` / `PARTIAL` / `N/A`) per item. On a large repo, prioritize by sink severity and reachability; cap entries, log the overflow.
   174 | 
   175 | ## Phase 1B: Investigate Pass
   176 | 
   177 | Trace each flagged source forward to a sink or sanitizer (is the data validated/escaped first?) and each flagged sink backward to every source that reaches it (authorization and input-validation guards?), including second-order flows where stored data becomes dangerous on retrieval. Record each confirmed or dismissed path in the working file. If tracing outruns the time budget, mark the rest deferred, log it, and continue.
   178 | 
   179 | ## Phase 1C: Security Dissenter Analysis
   180 | 
>  181 | Runs when `flatline_protocol.security_audit.enabled: true` in `.loa.config.yaml`; skipping it blocks the `COMPLETED` marker write (`adversarial-review-gate.sh`). Emergency override: `LOA_ADVERSARIAL_REVIEW_ENFORCE=false`, noted in sprint notes.
>  182 | 
>  183 | Run `.claude/scripts/adversarial-review.sh --type audit --sprint-id <sprint_id> --diff-range main...HEAD --json` — no `--context-file`. Two voices by default (`companion_voice`). Output: `grimoires/loa/a2a/{sprint_id}/adversarial-audit.json`; one top-level bullet per rejected payload (`rejected_summary` or sidecar rows, whichever is more) under `## Rejected dissent payloads`, else `verdict-derive.sh` fails the trailer. Mechanics: `resources/ADVERSARIAL-REVIEW.md`.
>  184 | Read `advisory_voices[].findings` as advisory input, never tallied.
   185 | 
   186 | ## Phase 1: Systematic Audit
   187 | 
   188 | Execute by category (sequential, or split per Phase -1), each per its `resources/REFERENCE.md` section: **Security**, **Architecture**, **Code Quality**, **DevOps**, and **Blockchain/Crypto** when applicable.
   189 | 
   190 | ## Phase 2: Report Generation
   191 | 
   192 | Use `resources/templates/audit-report.md`. Output stays in the State Zone: codebase audits → `grimoires/loa/a2a/audits/YYYY-MM-DD/SECURITY-AUDIT-REPORT.md` plus files under `remediation/` (Write creates it); sprint audits → `grimoires/loa/a2a/sprint-N/auditor-sprint-feedback.md`; deployment audits → `grimoires/loa/a2a/deployment-feedback.md`.
   193 | 
   194 | ### Coverage
   195 | 
   196 | Report every finding you actually observe — minor, uncertain, or on an otherwise clean sprint;
~~~~

The change from head to the fix:

~~~~diff
@@ -181,4 +181,4 @@
-Runs when `flatline_protocol.security_audit.enabled: true` in `.loa.config.yaml`; skipping it blocks the `COMPLETED` marker write (`adversarial-review-gate.sh`). Emergency override: `LOA_ADVERSARIAL_REVIEW_ENFORCE=false`, noted in sprint notes.
+Runs when `flatline_protocol.security_audit.enabled: true`; skipping it blocks the `COMPLETED` marker write (`adversarial-review-gate.sh`). Emergency override: `LOA_ADVERSARIAL_REVIEW_ENFORCE=false`, noted in sprint notes.
 
 Run `.claude/scripts/adversarial-review.sh --type audit --sprint-id <sprint_id> --diff-range main...HEAD --json` — no `--context-file`. Two voices by default (`companion_voice`). Output: `grimoires/loa/a2a/{sprint_id}/adversarial-audit.json`; one top-level bullet per rejected payload (`rejected_summary` or sidecar rows, whichever is more) under `## Rejected dissent payloads`, else `verdict-derive.sh` fails the trailer. Mechanics: `resources/ADVERSARIAL-REVIEW.md`.
-Read `advisory_voices[].findings` as advisory input, never tallied.
+Read `advisory_voices[].findings` as advisory input, never tallied; `metadata.locality.degraded_security_review: true` ⇒ state DEGRADED_SECURITY_REVIEW.
~~~~

## H34 — .claude/skills/bridgebuilder-review/dist/.build-manifest.json — head lines 3–4

Head context (head/.claude/skills/bridgebuilder-review/dist/.build-manifest.json, lines 1–16):

~~~~text
     1 | {
     2 |   "version": "1.0",
>    3 |   "generated_at": "2026-10-14T07:40:42Z",
>    4 |   "source_hash": "ffa2ae2ff364c468d601f0fc7a1ff0f21a1495d138efcc18a0e94c0d7b761d54",
     5 |   "file_count": 43,
     6 |   "files": [
     7 |     {
     8 |       "path": ".claude/skills/bridgebuilder-review/resources/adapters/adapter-factory.ts",
     9 |       "sha256": "e40e075c96c8c73244d6344a6a18e6f128ccf86bb35b56325fb3d88fd3efda18"
    10 |     },
    11 |     {
    12 |       "path": ".claude/skills/bridgebuilder-review/resources/adapters/cheval-delegate.ts",
    13 |       "sha256": "bafda4073a3bfd6bd3506a124640135fbd02397f5157bfef7009390861818470"
    14 |     },
    15 |     {
    16 |       "path": ".claude/skills/bridgebuilder-review/resources/adapters/console-logger.ts",
~~~~

The change from head to the fix:

~~~~diff
@@ -3,2 +3,2 @@
-  "generated_at": "2026-10-14T07:40:42Z",
-  "source_hash": "ffa2ae2ff364c468d601f0fc7a1ff0f21a1495d138efcc18a0e94c0d7b761d54",
+  "generated_at": "2026-10-14T10:15:43Z",
+  "source_hash": "5dc9f2234313e53dae6152a581dd0ab7bbcdde5b23b2a70b3c9b3eb3aae843c1",
~~~~

## H35 — .claude/skills/bridgebuilder-review/dist/.build-manifest.json — head line 49

Head context (head/.claude/skills/bridgebuilder-review/dist/.build-manifest.json, lines 37–61):

~~~~text
    37 |       "sha256": "0001d17da0a8100c245e3e029d563420e4949cc86092715433c06fee99711c54"
    38 |     },
    39 |     {
    40 |       "path": ".claude/skills/bridgebuilder-review/resources/adapters/sanitizer.ts",
    41 |       "sha256": "b3a14d979760b11f546c2ec426a6811375e766eafe51b02f3ab2cf70443db368"
    42 |     },
    43 |     {
    44 |       "path": ".claude/skills/bridgebuilder-review/resources/config.generated.ts",
    45 |       "sha256": "d07ec360fccdaa9bfdff7397ea3e120cc59839a60617d130a7fae36f4db817fa"
    46 |     },
    47 |     {
    48 |       "path": ".claude/skills/bridgebuilder-review/resources/config.ts",
>   49 |       "sha256": "4a17672d468d763c6eb9dfe24a9c0ecf1327ab2e22c36b1a3cca454c949b0dce"
    50 |     },
    51 |     {
    52 |       "path": ".claude/skills/bridgebuilder-review/resources/core/cache.ts",
    53 |       "sha256": "8b198aacb3d50f1614999077c48b6aff9fc791a85d8bc532b6eb9604ac6e53ec"
    54 |     },
    55 |     {
    56 |       "path": ".claude/skills/bridgebuilder-review/resources/core/context.ts",
    57 |       "sha256": "3e91d50e9d24b06fee26250ce6b39323b6713b64b8afc1ef268b7cc5db3238f4"
    58 |     },
    59 |     {
    60 |       "path": ".claude/skills/bridgebuilder-review/resources/core/cross-repo-render.ts",
    61 |       "sha256": "b6d82e9c833ab46dd1a80c8d767550043e04a3fccbceed6e02e6bd0b69ea9e07"
~~~~

The change from head to the fix:

~~~~diff
@@ -49 +49 @@
-      "sha256": "4a17672d468d763c6eb9dfe24a9c0ecf1327ab2e22c36b1a3cca454c949b0dce"
+      "sha256": "39543c7beef4919f453fb552a6182075f78554a85987b67891ef5f020f21ff2e"
~~~~

## H36 — .claude/skills/bridgebuilder-review/dist/.build-manifest.json — head line 133

Head context (head/.claude/skills/bridgebuilder-review/dist/.build-manifest.json, lines 121–145):

~~~~text
   121 |       "sha256": "9b0163d3aca18196e5701fe27575e5d27249763b42f59ea09680719e978b215f"
   122 |     },
   123 |     {
   124 |       "path": ".claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts",
   125 |       "sha256": "16512a332df1ac467337fd70a34b2904c3576cc4ff55c58d3ece30f9c668de6b"
   126 |     },
   127 |     {
   128 |       "path": ".claude/skills/bridgebuilder-review/resources/core/truncation.ts",
   129 |       "sha256": "5ed9bd99a13564cc0a65e2a8117e258e557d002b05f31887398fbec22112b249"
   130 |     },
   131 |     {
   132 |       "path": ".claude/skills/bridgebuilder-review/resources/core/types.ts",
>  133 |       "sha256": "b047232236a1219e578fe7151b4aba16ecedcd05ea71931ef9eaf18f9a705af8"
   134 |     },
   135 |     {
   136 |       "path": ".claude/skills/bridgebuilder-review/resources/lib/endpoint-validator.generated.ts",
   137 |       "sha256": "d530416cd95770fb04b28a828932757dae6bcb31dd492914c6061aff3f6b372a"
   138 |     },
   139 |     {
   140 |       "path": ".claude/skills/bridgebuilder-review/resources/lib/model-resolver.generated.ts",
   141 |       "sha256": "5f32f6e734a27195962bb69de704d6d0b7eb9c24415f4a008800346f4711bb45"
   142 |     },
   143 |     {
   144 |       "path": ".claude/skills/bridgebuilder-review/resources/main.ts",
   145 |       "sha256": "8509c88a4038dccde7eeea79f557a0b6cdad74fb2412c2c743ba5bf92281ec27"
~~~~

The change from head to the fix:

~~~~diff
@@ -133 +133 @@
-      "sha256": "b047232236a1219e578fe7151b4aba16ecedcd05ea71931ef9eaf18f9a705af8"
+      "sha256": "11cbc1ed7b4e0dca7ef4fdc2c16a34ca7f122709eaf9ac478ebe2dea0cfb1866"
~~~~

## H37 — .claude/skills/bridgebuilder-review/dist/.build-manifest.json — head line 145

Head context (head/.claude/skills/bridgebuilder-review/dist/.build-manifest.json, lines 133–157):

~~~~text
   133 |       "sha256": "b047232236a1219e578fe7151b4aba16ecedcd05ea71931ef9eaf18f9a705af8"
   134 |     },
   135 |     {
   136 |       "path": ".claude/skills/bridgebuilder-review/resources/lib/endpoint-validator.generated.ts",
   137 |       "sha256": "d530416cd95770fb04b28a828932757dae6bcb31dd492914c6061aff3f6b372a"
   138 |     },
   139 |     {
   140 |       "path": ".claude/skills/bridgebuilder-review/resources/lib/model-resolver.generated.ts",
   141 |       "sha256": "5f32f6e734a27195962bb69de704d6d0b7eb9c24415f4a008800346f4711bb45"
   142 |     },
   143 |     {
   144 |       "path": ".claude/skills/bridgebuilder-review/resources/main.ts",
>  145 |       "sha256": "8509c88a4038dccde7eeea79f557a0b6cdad74fb2412c2c743ba5bf92281ec27"
   146 |     },
   147 |     {
   148 |       "path": ".claude/skills/bridgebuilder-review/resources/ports/context-store.ts",
   149 |       "sha256": "f944e87b3e9ace803ef9b75786e0523af0e35aa4f51fe8586a615c931de409d8"
   150 |     },
   151 |     {
   152 |       "path": ".claude/skills/bridgebuilder-review/resources/ports/git-provider.ts",
   153 |       "sha256": "fe1150762a666f6c09beb204218f284d7a1535c7179ab2c9bc1c839419574b1e"
   154 |     },
   155 |     {
   156 |       "path": ".claude/skills/bridgebuilder-review/resources/ports/hasher.ts",
   157 |       "sha256": "4af765b36cc296550e4be7c02c4e00f0a9567c1fbb9916cec3b2c9f801924e12"
~~~~

The change from head to the fix:

~~~~diff
@@ -145 +145 @@
-      "sha256": "8509c88a4038dccde7eeea79f557a0b6cdad74fb2412c2c743ba5bf92281ec27"
+      "sha256": "6db270fc245fff889312487e40488f02cb8841201ecd2f243a16eb76cf5f36a8"
~~~~

## H38 — .claude/skills/bridgebuilder-review/dist/config.d.ts — insertion after head line 161

Head context (head/.claude/skills/bridgebuilder-review/dist/config.d.ts, lines 150–173):

~~~~text
   150 | export declare function providerKeyEnv(provider: string, trusted?: TrustedConfig): string | undefined;
   151 | /** Default `bridgebuilder.exit_on_degraded` (DEC-0150): exit 3 when the consensus verdict is DEGRADED. */
   152 | export declare const DEFAULT_EXIT_ON_DEGRADED = 3;
   153 | /**
   154 |  * Normalise `hounfour.providers` (any JSON) into declarations. A non-mapping value or an entry that is not a mapping is
   155 |  * dropped with a warning — never admitted. D-8.0: `keyless: true` or a literal `auth` (one without `{env:`) is keyless.
   156 |  */
   157 | export declare function parseProviderDecls(raw: unknown, label: string, warnings: string[]): Record<string, ProviderDecl>;
   158 | export interface TrustedView {
   159 |     providers: unknown;
   160 |     locality: unknown;
   161 |     exit: unknown;
   162 | }
   163 | /** Parse Loa config text (YAML or JSON) into the trusted view with yq; throws with yq's first stderr line on failure. */
   164 | export declare function yqTrustedView(text: string): TrustedView;
   165 | /** A branch name safe to place in `refs/remotes/origin/<name>` for `git show` (no option, no `..`, no control chars). */
   166 | export declare function isSafeRefName(name: string): boolean;
   167 | /** I/O seams for loadTrustedConfig (tests replace them; the defaults touch git, gh, the filesystem and yq). */
   168 | export interface TrustedConfigDeps {
   169 |     env: Record<string, string | undefined>;
   170 |     /** The working tree's `.loa.config.yaml` text, or undefined when the file is absent. */
   171 |     readWorkingTree: (path: string) => string | undefined;
   172 |     /** True when `ref` names a commit in the repository. */
   173 |     refExists: (repoRoot: string | undefined, ref: string) => boolean;
~~~~

The change from head to the fix:

~~~~diff
@@ -161,0 +162,6 @@
+    /** `hounfour.aliases` (audit a257-1: resolves fallback aliases; compared for head drift). */
+    aliases?: unknown;
+    /** `hounfour.secret_env_allowlist` — the list cheval's loader reads (compared for head drift). */
+    allowlist?: unknown;
+    /** A root-level `secret_env_allowlist` (compared for head drift too: it is the shape the docs once showed). */
+    rootAllowlist?: unknown;
~~~~

## H39 — .claude/skills/bridgebuilder-review/dist/config.d.ts — head lines 191–192

Head context (head/.claude/skills/bridgebuilder-review/dist/config.d.ts, lines 179–204):

~~~~text
   179 | }
   180 | export declare const defaultTrustedConfigDeps: TrustedConfigDeps;
   181 | /** True when Bridgebuilder runs on a pull request (D-7.5): `--pr`, a PR event, or a base ref in the environment. */
   182 | export declare function isPullRequestContext(pr: number | undefined, env: Record<string, string | undefined>): boolean;
   183 | /** The env var a workflow sets from a repository variable to supply trusted config text (YAML or JSON). */
   184 | export declare const TRUSTED_CONFIG_ENV = "BRIDGEBUILDER_TRUSTED_CONFIG";
   185 | /**
   186 |  * Load the trusted configuration (D-7.5, DEC-0170). Precedence:
   187 |  *   local (no PR context):  the working tree's `.loa.config.yaml`.
   188 |  *   pull request:           `BRIDGEBUILDER_TRUSTED_CONFIG` (repository settings) when set, else `.loa.config.yaml` at
   189 |  *                           `refs/remotes/origin/<base>` (base from `GITHUB_BASE_REF`, else the PR metadata), else at
   190 |  *                           `refs/remotes/origin/main`; when none can be read, no provider declaration is trusted.
>  191 |  * The head checkout is read on a pull request only to find keyless / insecure declarations the trusted source lacks,
>  192 |  * which are refused by name. Throws on an invalid `hounfour.locality` (a posture typo never runs hosted silently).
   193 |  */
   194 | export declare function loadTrustedConfig(opts: {
   195 |     pr?: number;
   196 |     repoRoot?: string;
   197 |     repo?: string;
   198 | }, deps?: TrustedConfigDeps): TrustedConfig;
   199 | /** One startup line naming where the trusted config was read from (main.ts prints it with the warnings). */
   200 | export declare function trustedConfigStartupLine(t: TrustedConfig): string;
   201 | /**
   202 |  * True when the trusted config marks this voice's provider `dispatch_group: local` (D-8.0): the model's own entry when
   203 |  * declared, else the provider-level key, else every declared model of the provider. Anything undeclared is hosted.
   204 |  */
~~~~

The change from head to the fix:

~~~~diff
@@ -191,2 +197,3 @@
- * The head checkout is read on a pull request only to find keyless / insecure declarations the trusted source lacks,
- * which are refused by name. Throws on an invalid `hounfour.locality` (a posture typo never runs hosted silently).
+ * The head checkout is read on a pull request to find keyless / insecure declarations the trusted source lacks, which
+ * are refused by name, and (audit a257-1 MEDIUM-A2) to compute `headDrift` — the keys cheval would read differently from
+ * the checkout than the trusted source says; main.ts refuses the run on any. Throws on an invalid `hounfour.locality` (a posture typo never runs hosted silently).
~~~~

## H40 — .claude/skills/bridgebuilder-review/dist/config.d.ts — head lines 199–204

Head context (head/.claude/skills/bridgebuilder-review/dist/config.d.ts, lines 187–216):

~~~~text
   187 |  *   local (no PR context):  the working tree's `.loa.config.yaml`.
   188 |  *   pull request:           `BRIDGEBUILDER_TRUSTED_CONFIG` (repository settings) when set, else `.loa.config.yaml` at
   189 |  *                           `refs/remotes/origin/<base>` (base from `GITHUB_BASE_REF`, else the PR metadata), else at
   190 |  *                           `refs/remotes/origin/main`; when none can be read, no provider declaration is trusted.
   191 |  * The head checkout is read on a pull request only to find keyless / insecure declarations the trusted source lacks,
   192 |  * which are refused by name. Throws on an invalid `hounfour.locality` (a posture typo never runs hosted silently).
   193 |  */
   194 | export declare function loadTrustedConfig(opts: {
   195 |     pr?: number;
   196 |     repoRoot?: string;
   197 |     repo?: string;
   198 | }, deps?: TrustedConfigDeps): TrustedConfig;
>  199 | /** One startup line naming where the trusted config was read from (main.ts prints it with the warnings). */
>  200 | export declare function trustedConfigStartupLine(t: TrustedConfig): string;
>  201 | /**
>  202 |  * True when the trusted config marks this voice's provider `dispatch_group: local` (D-8.0): the model's own entry when
>  203 |  * declared, else the provider-level key, else every declared model of the provider. Anything undeclared is hosted.
>  204 |  */
   205 | export declare function isLocalVoice(provider: string, modelId: string, trusted: TrustedConfig): boolean;
   206 | /**
   207 |  * D-8.1: under `hounfour.locality: local_voices` drop every planned voice whose provider is not local, each with the named
   208 |  * reason; never reroute. `hosted` (the default) returns the list unchanged.
   209 |  */
   210 | export declare function applyLocality(models: MultiModelProviderEntry[], trusted: TrustedConfig): {
   211 |     kept: MultiModelProviderEntry[];
   212 |     refused: Array<{
   213 |         provider: string;
   214 |         modelId: string;
   215 |         reason: string;
   216 |     }>;
~~~~

The change from head to the fix:

~~~~diff
@@ -199,6 +206,54 @@
+/** Key-order-independent structural equality over JSON values (the yq view is JSON). */
+export declare function jsonDeepEqual(a: unknown, b: unknown): boolean;
+/**
+ * audit a257-1 MEDIUM-A2 (pure): the dotted keys that differ between the PR head's view and the trusted view —
+ * `hounfour.providers.<name>` (every field: endpoint, auth template, models, opt-ins), `hounfour.aliases.<alias>`,
+ * `hounfour.locality` (absent ⇒ `hosted`), `hounfour.secret_env_allowlist` and a root `secret_env_allowlist` (absent ⇒
+ * `[]`). An absent head file reads as all defaults; an unparsable head is drift on `.loa.config.yaml` itself (fail
+ * closed: cheval's YAML reader might accept what yq refused).
+ */
+export declare function computeHeadDrift(head: TrustedView | undefined, trusted: TrustedView, headUnreadable?: boolean): string[];
+/** Where the trusted config came from, in words, for the drift refusal. */
+export declare function trustedSourceDescription(t: TrustedConfig): string;
+/** Exit code for a multi-model run refused by trusted-config drift (distinct from 0, 3 DEGRADED and 4 FAILED). */
+export declare const EXIT_TRUSTED_CONFIG_DRIFT = 5;
+/**
+ * The refusal decision for the multi-model run (pure; main.ts prints and exits): the stderr line, or undefined when the
+ * run may proceed (local mode, or no drift).
+ */
+export declare function headDriftRefusal(t: TrustedConfig): string | undefined;
 /** One startup line naming where the trusted config was read from (main.ts prints it with the warnings). */
 export declare function trustedConfigStartupLine(t: TrustedConfig): string;
+/** The local-hop rule's wording, shared with cheval (endpoint_policy.LOCAL_RULE_TEXT) and the planner. */
+export declare const LOCAL_RULE_TEXT = "a loopback or RFC1918 IP literal or localhost";
 /**
- * True when the trusted config marks this voice's provider `dispatch_group: local` (D-8.0): the model's own entry when
- * declared, else the provider-level key, else every declared model of the provider. Anything undeclared is hosted.
+ * The local-hop rule (D-8.1, review round r257-1) on a provider endpoint: `ok` when it is an http(s) URL whose host is an
+ * IP literal in a loopback (127.0.0.0/8, ::1) or RFC1918 (10/8, 172.16/12, 192.168/16) range, or the literal `localhost`.
+ * Link-local, metadata, unique-local IPv6, public ranges and every other DNS name fail. A stdlib mirror of the canonical
+ * validator's `check_insecure_optin` host acceptance (the generated TypeScript port does not export it): the authority is
+ * split by hand, not by WHATWG `URL`, so a host such as `0x7f.1` stays a DNS name here exactly as it does in Python.
+ * `host` is the canonical host for a refusal message ("" when there is no endpoint).
  */
+export declare function localEndpointHost(endpoint: unknown): {
+    ok: boolean;
+    host: string;
+};
+/**
+ * The locality decision for one voice. `declared`: the trusted config marks it `dispatch_group: local` (the model's own
+ * entry when declared, else the provider-level key, else every declared model of the provider). `local`: declared AND
+ * the provider honours it — not a CLI provider, and its endpoint host passes the local-hop rule (D-8.1, r257-1: a
+ * declared locality is enforced, not trusted). `reason` names why a declared voice is still hosted.
+ */
+export declare function localVoiceDecision(provider: string, modelId: string, trusted: TrustedConfig): {
+    local: boolean;
+    declared: boolean;
+    reason?: string;
+};
+/** The fallback walk's depth bound (audit a257-1 MEDIUM-A1 (c); endpoint_policy.LOCAL_FALLBACK_MAX_DEPTH). */
+export declare const LOCAL_FALLBACK_MAX_DEPTH = 8;
+/**
+ * A `fallback_chain` entry as `[provider, model]`: a `provider:model` pin, or an alias followed through the TRUSTED
+ * `hounfour.aliases` (depth-limited, cycle-safe). Undefined when it does not resolve — the caller treats that as hosted.
+ */
+export declare function resolveFallbackSpec(spec: string, aliases: Record<string, string> | undefined): [string, string] | undefined;
+/** True when the voice is local by `localVoiceDecision` (declared `dispatch_group: local` AND the endpoint honours it). */
~~~~

## H41 — .claude/skills/bridgebuilder-review/dist/config.d.ts.map — head line 1

Head context (head/.claude/skills/bridgebuilder-review/dist/config.d.ts.map, lines 1–1):

~~~~text
>    1 | {"version":3,"file":"config.d.ts","sourceRoot":"","sources":["../resources/config.ts"],"names":[],"mappings":"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"}
~~~~

The change from head to the fix:

~~~~diff
@@ -1 +1 @@
-{"version":3,"file":"config.d.ts","sourceRoot":"","sources":["../resources/config.ts"],"names":[],"mappings":"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"}
\ No newline at end of file
+{"version":3,"file":"config.d.ts","sourceRoot":"","sources":["../resources/config.ts"],"names":[],"mappings":"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"}
\ No newline at end of file
~~~~

## H42 — .claude/skills/bridgebuilder-review/dist/config.js — insertion after head line 4

Head context (head/.claude/skills/bridgebuilder-review/dist/config.js, lines 1–16):

~~~~text
     1 | import { execFile, execFileSync, execSync } from "node:child_process";
     2 | import { promisify } from "node:util";
     3 | import { readFile } from "node:fs/promises";
     4 | import { closeSync, existsSync, fstatSync, openSync, readFileSync, statSync } from "node:fs";
     5 | import { join } from "node:path";
     6 | import { z } from "zod/v4";
     7 | import { GENERATED_MODEL_REGISTRY } from "./config.generated.js";
     8 | const execFileAsync = promisify(execFile);
     9 | /**
    10 |  * Zod schema for multi-model configuration (SDD Section 2.7).
    11 |  * Validated at startup; all fields have sensible defaults so partial config works.
    12 |  */
    13 | const ScoringThresholdsSchema = z.object({
    14 |     high_consensus: z.number().default(700),
    15 |     disputed_delta: z.number().default(300),
    16 |     low_value: z.number().default(400),
~~~~

The change from head to the fix:

~~~~diff
@@ -4,0 +5 @@
+import { isIPv6 } from "node:net";
~~~~

## H43 — .claude/skills/bridgebuilder-review/dist/config.js — insertion after head line 411

Head context (head/.claude/skills/bridgebuilder-review/dist/config.js, lines 400–423):

~~~~text
   400 |     if (Object.hasOwn(PROVIDER_API_KEY_ENV, provider))
   401 |         return PROVIDER_API_KEY_ENV[provider];
   402 |     return trusted?.providers[provider]?.authEnv;
   403 | }
   404 | /** Default `bridgebuilder.exit_on_degraded` (DEC-0150): exit 3 when the consensus verdict is DEGRADED. */
   405 | export const DEFAULT_EXIT_ON_DEGRADED = 3;
   406 | /** The lenient shape of one provider entry (unknown keys pass through: cheval owns the full schema). */
   407 | const ProviderEntrySchema = z.looseObject({
   408 |     keyless: z.unknown().optional(),
   409 |     auth: z.unknown().optional(),
   410 |     allow_insecure_endpoint: z.unknown().optional(),
   411 |     dispatch_group: z.unknown().optional(),
   412 |     models: z.unknown().optional(),
   413 | });
   414 | const ENV_AUTH_RE = /^\{env:([A-Za-z_][A-Za-z0-9_]*)\}$/;
   415 | /**
   416 |  * Normalise `hounfour.providers` (any JSON) into declarations. A non-mapping value or an entry that is not a mapping is
   417 |  * dropped with a warning — never admitted. D-8.0: `keyless: true` or a literal `auth` (one without `{env:`) is keyless.
   418 |  */
   419 | export function parseProviderDecls(raw, label, warnings) {
   420 |     const out = {};
   421 |     if (raw === null || raw === undefined)
   422 |         return out;
   423 |     if (typeof raw !== "object" || Array.isArray(raw)) {
~~~~

The change from head to the fix:

~~~~diff
@@ -411,0 +413,2 @@
+    endpoint: z.unknown().optional(),
+    type: z.unknown().optional(),
~~~~

## H44 — .claude/skills/bridgebuilder-review/dist/config.js — insertion after head line 437

Head context (head/.claude/skills/bridgebuilder-review/dist/config.js, lines 426–449):

~~~~text
   426 |     }
   427 |     for (const [name, entry] of Object.entries(raw)) {
   428 |         const parsed = ProviderEntrySchema.safeParse(entry);
   429 |         if (!parsed.success) {
   430 |             warnings.push(`[bridgebuilder] ${label}: hounfour.providers.${name} is not a mapping — ignored`);
   431 |             continue;
   432 |         }
   433 |         const e = parsed.data;
   434 |         const auth = typeof e.auth === "string" ? e.auth : undefined;
   435 |         const envMatch = auth !== undefined ? ENV_AUTH_RE.exec(auth) : null;
   436 |         const literalAuth = auth !== undefined && auth !== "" && !auth.includes("{env:");
   437 |         const modelGroups = {};
   438 |         if (e.models !== null && typeof e.models === "object" && !Array.isArray(e.models)) {
   439 |             for (const [mid, m] of Object.entries(e.models)) {
   440 |                 const g = m !== null && typeof m === "object" ? m.dispatch_group : undefined;
   441 |                 modelGroups[mid] = typeof g === "string" ? g : undefined;
   442 |             }
   443 |         }
   444 |         out[name] = {
   445 |             keyless: e.keyless === true || literalAuth,
   446 |             insecure: e.allow_insecure_endpoint !== undefined && e.allow_insecure_endpoint !== null && e.allow_insecure_endpoint !== false,
   447 |             ...(envMatch ? { authEnv: envMatch[1] } : {}),
   448 |             ...(typeof e.dispatch_group === "string" ? { dispatchGroup: e.dispatch_group } : {}),
   449 |             modelGroups,
~~~~

The change from head to the fix:

~~~~diff
@@ -437,0 +441,3 @@
+        const modelFallbacks = {};
+        let modelCount = 0;
+        let cliModels = 0;
~~~~

## H45 — .claude/skills/bridgebuilder-review/dist/config.js — head lines 442–443

Head context (head/.claude/skills/bridgebuilder-review/dist/config.js, lines 430–455):

~~~~text
   430 |             warnings.push(`[bridgebuilder] ${label}: hounfour.providers.${name} is not a mapping — ignored`);
   431 |             continue;
   432 |         }
   433 |         const e = parsed.data;
   434 |         const auth = typeof e.auth === "string" ? e.auth : undefined;
   435 |         const envMatch = auth !== undefined ? ENV_AUTH_RE.exec(auth) : null;
   436 |         const literalAuth = auth !== undefined && auth !== "" && !auth.includes("{env:");
   437 |         const modelGroups = {};
   438 |         if (e.models !== null && typeof e.models === "object" && !Array.isArray(e.models)) {
   439 |             for (const [mid, m] of Object.entries(e.models)) {
   440 |                 const g = m !== null && typeof m === "object" ? m.dispatch_group : undefined;
   441 |                 modelGroups[mid] = typeof g === "string" ? g : undefined;
>  442 |             }
>  443 |         }
   444 |         out[name] = {
   445 |             keyless: e.keyless === true || literalAuth,
   446 |             insecure: e.allow_insecure_endpoint !== undefined && e.allow_insecure_endpoint !== null && e.allow_insecure_endpoint !== false,
   447 |             ...(envMatch ? { authEnv: envMatch[1] } : {}),
   448 |             ...(typeof e.dispatch_group === "string" ? { dispatchGroup: e.dispatch_group } : {}),
   449 |             modelGroups,
   450 |         };
   451 |     }
   452 |     return out;
   453 | }
   454 | /** The subtree Bridgebuilder reads from a Loa config, as one yq program (the same yq the agy gate uses). */
   455 | const TRUSTED_VIEW_YQ = '{"providers": (.hounfour.providers // null), "locality": (.hounfour.locality // null), "exit": (.bridgebuilder.exit_on_degraded // null)}';
~~~~

The change from head to the fix:

~~~~diff
@@ -442,2 +448,12 @@
+                modelCount += 1;
+                if (m !== null && typeof m === "object" && m.kind === "cli")
+                    cliModels += 1;
+                // (audit a257-1 MEDIUM-A1 (c): the chain cheval walks inside one call; a scalar is a one-entry chain, as in
+                // endpoint_policy.validate_local_fallbacks, and a non-string entry is "" — unresolvable, so hosted)
+                const fb = m !== null && typeof m === "object" ? m.fallback_chain : undefined;
+                if (fb !== undefined && fb !== null) {
+                    modelFallbacks[mid] = (Array.isArray(fb) ? fb : [fb]).map((x) => (typeof x === "string" ? x : ""));
+                }
             }
         }
+        const cli = (typeof e.type === "string" && e.type.endsWith("-headless")) || (modelCount > 0 && cliModels === modelCount);
~~~~

## H46 — .claude/skills/bridgebuilder-review/dist/config.js — insertion after head line 449

Head context (head/.claude/skills/bridgebuilder-review/dist/config.js, lines 438–461):

~~~~text
   438 |         if (e.models !== null && typeof e.models === "object" && !Array.isArray(e.models)) {
   439 |             for (const [mid, m] of Object.entries(e.models)) {
   440 |                 const g = m !== null && typeof m === "object" ? m.dispatch_group : undefined;
   441 |                 modelGroups[mid] = typeof g === "string" ? g : undefined;
   442 |             }
   443 |         }
   444 |         out[name] = {
   445 |             keyless: e.keyless === true || literalAuth,
   446 |             insecure: e.allow_insecure_endpoint !== undefined && e.allow_insecure_endpoint !== null && e.allow_insecure_endpoint !== false,
   447 |             ...(envMatch ? { authEnv: envMatch[1] } : {}),
   448 |             ...(typeof e.dispatch_group === "string" ? { dispatchGroup: e.dispatch_group } : {}),
   449 |             modelGroups,
   450 |         };
   451 |     }
   452 |     return out;
   453 | }
   454 | /** The subtree Bridgebuilder reads from a Loa config, as one yq program (the same yq the agy gate uses). */
   455 | const TRUSTED_VIEW_YQ = '{"providers": (.hounfour.providers // null), "locality": (.hounfour.locality // null), "exit": (.bridgebuilder.exit_on_degraded // null)}';
   456 | /** Parse Loa config text (YAML or JSON) into the trusted view with yq; throws with yq's first stderr line on failure. */
   457 | export function yqTrustedView(text) {
   458 |     try {
   459 |         const out = execFileSync("yq", ["eval", "-o=json", "-I=0", TRUSTED_VIEW_YQ, "-"], {
   460 |             encoding: "utf8", timeout: 5000, input: text, stdio: ["pipe", "pipe", "pipe"],
   461 |         });
~~~~

The change from head to the fix:

~~~~diff
@@ -449,0 +466,3 @@
+            ...(typeof e.endpoint === "string" ? { endpoint: e.endpoint } : {}),
+            ...(cli ? { cli: true } : {}),
+            ...(Object.keys(modelFallbacks).length > 0 ? { modelFallbacks } : {}),
~~~~

## H47 — .claude/skills/bridgebuilder-review/dist/config.js — head line 455

Head context (head/.claude/skills/bridgebuilder-review/dist/config.js, lines 443–467):

~~~~text
   443 |         }
   444 |         out[name] = {
   445 |             keyless: e.keyless === true || literalAuth,
   446 |             insecure: e.allow_insecure_endpoint !== undefined && e.allow_insecure_endpoint !== null && e.allow_insecure_endpoint !== false,
   447 |             ...(envMatch ? { authEnv: envMatch[1] } : {}),
   448 |             ...(typeof e.dispatch_group === "string" ? { dispatchGroup: e.dispatch_group } : {}),
   449 |             modelGroups,
   450 |         };
   451 |     }
   452 |     return out;
   453 | }
   454 | /** The subtree Bridgebuilder reads from a Loa config, as one yq program (the same yq the agy gate uses). */
>  455 | const TRUSTED_VIEW_YQ = '{"providers": (.hounfour.providers // null), "locality": (.hounfour.locality // null), "exit": (.bridgebuilder.exit_on_degraded // null)}';
   456 | /** Parse Loa config text (YAML or JSON) into the trusted view with yq; throws with yq's first stderr line on failure. */
   457 | export function yqTrustedView(text) {
   458 |     try {
   459 |         const out = execFileSync("yq", ["eval", "-o=json", "-I=0", TRUSTED_VIEW_YQ, "-"], {
   460 |             encoding: "utf8", timeout: 5000, input: text, stdio: ["pipe", "pipe", "pipe"],
   461 |         });
   462 |         const parsed = JSON.parse(out);
   463 |         return { providers: parsed?.providers ?? null, locality: parsed?.locality ?? null, exit: parsed?.exit ?? null };
   464 |     }
   465 |     catch (err) {
   466 |         const e = err;
   467 |         const stderr = typeof e.stderr === "string" ? e.stderr.trim() : "";
~~~~

The change from head to the fix:

~~~~diff
@@ -455 +474,2 @@
-const TRUSTED_VIEW_YQ = '{"providers": (.hounfour.providers // null), "locality": (.hounfour.locality // null), "exit": (.bridgebuilder.exit_on_degraded // null)}';
+const TRUSTED_VIEW_YQ = '{"providers": (.hounfour.providers // null), "locality": (.hounfour.locality // null), "exit": (.bridgebuilder.exit_on_degraded // null), ' +
+    '"aliases": (.hounfour.aliases // null), "allowlist": (.hounfour.secret_env_allowlist // null), "rootAllowlist": (.secret_env_allowlist // null)}';
~~~~

## H48 — .claude/skills/bridgebuilder-review/dist/config.js — head line 463

Head context (head/.claude/skills/bridgebuilder-review/dist/config.js, lines 451–475):

~~~~text
   451 |     }
   452 |     return out;
   453 | }
   454 | /** The subtree Bridgebuilder reads from a Loa config, as one yq program (the same yq the agy gate uses). */
   455 | const TRUSTED_VIEW_YQ = '{"providers": (.hounfour.providers // null), "locality": (.hounfour.locality // null), "exit": (.bridgebuilder.exit_on_degraded // null)}';
   456 | /** Parse Loa config text (YAML or JSON) into the trusted view with yq; throws with yq's first stderr line on failure. */
   457 | export function yqTrustedView(text) {
   458 |     try {
   459 |         const out = execFileSync("yq", ["eval", "-o=json", "-I=0", TRUSTED_VIEW_YQ, "-"], {
   460 |             encoding: "utf8", timeout: 5000, input: text, stdio: ["pipe", "pipe", "pipe"],
   461 |         });
   462 |         const parsed = JSON.parse(out);
>  463 |         return { providers: parsed?.providers ?? null, locality: parsed?.locality ?? null, exit: parsed?.exit ?? null };
   464 |     }
   465 |     catch (err) {
   466 |         const e = err;
   467 |         const stderr = typeof e.stderr === "string" ? e.stderr.trim() : "";
   468 |         throw new Error((stderr || e.message || String(err)).split("\n")[0].slice(0, 300));
   469 |     }
   470 | }
   471 | /** A branch name safe to place in `refs/remotes/origin/<name>` for `git show` (no option, no `..`, no control chars). */
   472 | export function isSafeRefName(name) {
   473 |     return /^[A-Za-z0-9][A-Za-z0-9._/-]{0,199}$/.test(name) && !name.includes("..") && !name.endsWith(".lock") && !name.endsWith("/");
   474 | }
   475 | function gitArgs(repoRoot, rest) {
~~~~

The change from head to the fix:

~~~~diff
@@ -463 +483,4 @@
-        return { providers: parsed?.providers ?? null, locality: parsed?.locality ?? null, exit: parsed?.exit ?? null };
+        return {
+            providers: parsed?.providers ?? null, locality: parsed?.locality ?? null, exit: parsed?.exit ?? null,
+            aliases: parsed?.aliases ?? null, allowlist: parsed?.allowlist ?? null, rootAllowlist: parsed?.rootAllowlist ?? null,
+        };
~~~~

## H49 — .claude/skills/bridgebuilder-review/dist/config.js — head lines 533–534

Head context (head/.claude/skills/bridgebuilder-review/dist/config.js, lines 521–546):

~~~~text
   521 |     if (ev === "pull_request" || ev === "pull_request_target")
   522 |         return true;
   523 |     return (env.GITHUB_BASE_REF ?? "") !== "";
   524 | }
   525 | /** The env var a workflow sets from a repository variable to supply trusted config text (YAML or JSON). */
   526 | export const TRUSTED_CONFIG_ENV = "BRIDGEBUILDER_TRUSTED_CONFIG";
   527 | /**
   528 |  * Load the trusted configuration (D-7.5, DEC-0170). Precedence:
   529 |  *   local (no PR context):  the working tree's `.loa.config.yaml`.
   530 |  *   pull request:           `BRIDGEBUILDER_TRUSTED_CONFIG` (repository settings) when set, else `.loa.config.yaml` at
   531 |  *                           `refs/remotes/origin/<base>` (base from `GITHUB_BASE_REF`, else the PR metadata), else at
   532 |  *                           `refs/remotes/origin/main`; when none can be read, no provider declaration is trusted.
>  533 |  * The head checkout is read on a pull request only to find keyless / insecure declarations the trusted source lacks,
>  534 |  * which are refused by name. Throws on an invalid `hounfour.locality` (a posture typo never runs hosted silently).
   535 |  */
   536 | export function loadTrustedConfig(opts, deps = defaultTrustedConfigDeps) {
   537 |     const warnings = [];
   538 |     const mode = isPullRequestContext(opts.pr, deps.env) ? "pull-request" : "local";
   539 |     const wtPath = loaConfigPathFor(opts.repoRoot);
   540 |     let source = "none";
   541 |     let ref;
   542 |     let text;
   543 |     if (mode === "local") {
   544 |         source = "working-tree";
   545 |         text = deps.readWorkingTree(wtPath);
   546 |     }
~~~~

The change from head to the fix:

~~~~diff
@@ -533,2 +556,3 @@
- * The head checkout is read on a pull request only to find keyless / insecure declarations the trusted source lacks,
- * which are refused by name. Throws on an invalid `hounfour.locality` (a posture typo never runs hosted silently).
+ * The head checkout is read on a pull request to find keyless / insecure declarations the trusted source lacks, which
+ * are refused by name, and (audit a257-1 MEDIUM-A2) to compute `headDrift` — the keys cheval would read differently from
+ * the checkout than the trusted source says; main.ts refuses the run on any. Throws on an invalid `hounfour.locality` (a posture typo never runs hosted silently).
~~~~

## H50 — .claude/skills/bridgebuilder-review/dist/config.js — head lines 601–604

Head context (head/.claude/skills/bridgebuilder-review/dist/config.js, lines 589–616):

~~~~text
   589 |     if (text !== undefined) {
   590 |         try {
   591 |             view = deps.parse(text);
   592 |         }
   593 |         catch (err) {
   594 |             warnings.push(`[bridgebuilder] trusted config (${source}${ref ? ` ${ref}` : ""}) unreadable: ${err instanceof Error ? err.message : String(err)} — no provider declaration is trusted`);
   595 |             source = "none";
   596 |         }
   597 |     }
   598 |     const providers = parseProviderDecls(view.providers, `trusted config (${source})`, warnings);
   599 |     // Head-only refusal: on a PR the head checkout is attacker-controlled.
   600 |     const headOnlyRefused = [];
>  601 |     if (mode === "pull-request") {
>  602 |         const headText = deps.readWorkingTree(wtPath);
>  603 |         if (headText !== undefined) {
>  604 |             let headView;
   605 |             try {
   606 |                 headView = deps.parse(headText);
   607 |             }
   608 |             catch {
   609 |                 headView = undefined; // (an unparsable head declares nothing Bridgebuilder would admit)
   610 |             }
   611 |             const headWarnings = [];
   612 |             const head = headView ? parseProviderDecls(headView.providers, "head config", headWarnings) : {};
   613 |             for (const [name, decl] of Object.entries(head)) {
   614 |                 const t = Object.hasOwn(providers, name) ? providers[name] : undefined;
   615 |                 const keylessOnlyInHead = decl.keyless && t?.keyless !== true;
   616 |                 const insecureOnlyInHead = decl.insecure && t?.insecure !== true;
~~~~

The change from head to the fix:

~~~~diff
@@ -601,4 +625,6 @@
+    let headDrift = [];
     if (mode === "pull-request") {
         const headText = deps.readWorkingTree(wtPath);
+        let headView;
+        let headUnreadable = false;
         if (headText !== undefined) {
-            let headView;
~~~~

## H51 — .claude/skills/bridgebuilder-review/dist/config.js — head line 610

Head context (head/.claude/skills/bridgebuilder-review/dist/config.js, lines 598–622):

~~~~text
   598 |     const providers = parseProviderDecls(view.providers, `trusted config (${source})`, warnings);
   599 |     // Head-only refusal: on a PR the head checkout is attacker-controlled.
   600 |     const headOnlyRefused = [];
   601 |     if (mode === "pull-request") {
   602 |         const headText = deps.readWorkingTree(wtPath);
   603 |         if (headText !== undefined) {
   604 |             let headView;
   605 |             try {
   606 |                 headView = deps.parse(headText);
   607 |             }
   608 |             catch {
   609 |                 headView = undefined; // (an unparsable head declares nothing Bridgebuilder would admit)
>  610 |             }
   611 |             const headWarnings = [];
   612 |             const head = headView ? parseProviderDecls(headView.providers, "head config", headWarnings) : {};
   613 |             for (const [name, decl] of Object.entries(head)) {
   614 |                 const t = Object.hasOwn(providers, name) ? providers[name] : undefined;
   615 |                 const keylessOnlyInHead = decl.keyless && t?.keyless !== true;
   616 |                 const insecureOnlyInHead = decl.insecure && t?.insecure !== true;
   617 |                 if (keylessOnlyInHead || insecureOnlyInHead) {
   618 |                     headOnlyRefused.push(name);
   619 |                     warnings.push(`[bridgebuilder] ${headOnlyRefusal(name)} (${[keylessOnlyInHead ? "keyless" : "", insecureOnlyInHead ? "allow_insecure_endpoint" : ""].filter(Boolean).join(", ")} is declared in the PR head, not in the trusted config)`);
   620 |                 }
   621 |             }
   622 |         }
~~~~

The change from head to the fix:

~~~~diff
@@ -610 +636,7 @@
+                headUnreadable = true;
             }
+        }
+        // audit a257-1 MEDIUM-A2: cheval reads the CHECKOUT's configuration for the dispatch, so on a pull request every
+        // difference in what it would read (providers, aliases, locality, the secret allowlist) is drift, refused by name.
+        headDrift = computeHeadDrift(headView, view, headUnreadable);
+        if (headText !== undefined) {
~~~~

## H52 — .claude/skills/bridgebuilder-review/dist/config.js — head line 642

Head context (head/.claude/skills/bridgebuilder-review/dist/config.js, lines 630–654):

~~~~text
   630 |             throw new Error(`hounfour.locality: invalid value ${JSON.stringify(view.locality)} (expected hosted or local_voices)`);
   631 |     }
   632 |     // bridgebuilder.exit_on_degraded
   633 |     let exitOnDegraded = DEFAULT_EXIT_ON_DEGRADED;
   634 |     if (view.exit !== null && view.exit !== undefined) {
   635 |         if (typeof view.exit === "number" && Number.isInteger(view.exit) && view.exit >= 0 && view.exit <= 125) {
   636 |             exitOnDegraded = view.exit;
   637 |         }
   638 |         else {
   639 |             warnings.push(`[bridgebuilder] bridgebuilder.exit_on_degraded: invalid value ${JSON.stringify(view.exit)} (expected an integer 0..125) — using ${DEFAULT_EXIT_ON_DEGRADED}`);
   640 |         }
   641 |     }
>  642 |     return { mode, source, ...(ref ? { ref } : {}), providers, headOnlyRefused, locality, exitOnDegraded, warnings };
   643 | }
   644 | /** One startup line naming where the trusted config was read from (main.ts prints it with the warnings). */
   645 | export function trustedConfigStartupLine(t) {
   646 |     const where = t.source === "base-ref" ? `base-ref ${t.ref}` : t.source;
   647 |     const keyless = Object.entries(t.providers).filter(([, d]) => d.keyless).map(([n]) => n);
   648 |     return `[bridgebuilder] Trusted config: ${where} (mode: ${t.mode}); locality: ${t.locality}; exit_on_degraded: ${t.exitOnDegraded}` +
   649 |         (keyless.length > 0 ? `; keyless providers: ${keyless.join(", ")}` : "");
   650 | }
   651 | /**
   652 |  * True when the trusted config marks this voice's provider `dispatch_group: local` (D-8.0): the model's own entry when
   653 |  * declared, else the provider-level key, else every declared model of the provider. Anything undeclared is hosted.
   654 |  */
~~~~

The change from head to the fix:

~~~~diff
@@ -642 +674,105 @@
-    return { mode, source, ...(ref ? { ref } : {}), providers, headOnlyRefused, locality, exitOnDegraded, warnings };
+    return {
+        mode, source, ...(ref ? { ref } : {}), providers, headOnlyRefused, locality, exitOnDegraded, warnings,
+        aliases: stringAliases(view.aliases), headDrift,
+    };
+}
+/** `hounfour.aliases` as a string map (non-string targets — cheval's dict form included — read through `target`/`model`). */
+function stringAliases(raw) {
+    const out = {};
+    if (raw === null || typeof raw !== "object" || Array.isArray(raw))
+        return out;
+    for (const [k, v] of Object.entries(raw)) {
+        let t = v;
+        if (t !== null && typeof t === "object" && !Array.isArray(t))
+            t = t.target ?? t.model;
+        if (typeof t === "string" && t.trim() !== "")
+            out[k] = t.trim();
+    }
+    return out;
+}
+/** Key-order-independent structural equality over JSON values (the yq view is JSON). */
+export function jsonDeepEqual(a, b) {
+    if (a === b)
+        return true;
+    if (a === null || b === null || typeof a !== "object" || typeof b !== "object")
+        return false;
+    if (Array.isArray(a) !== Array.isArray(b))
+        return false;
+    if (Array.isArray(a)) {
+        const bb = b;
+        return a.length === bb.length && a.every((x, i) => jsonDeepEqual(x, bb[i]));
+    }
+    const ka = Object.keys(a);
+    const kb = Object.keys(b);
+    if (ka.length !== kb.length)
+        return false;
+    return ka.every((k) => Object.hasOwn(b, k) && jsonDeepEqual(a[k], b[k]));
+}
+/** One dotted-key segment for a refusal line: a plain name as-is, anything else JSON-quoted and bounded (head text). */
+function driftSegment(name) {
+    return /^[A-Za-z0-9_.@+-]{1,64}$/.test(name) ? name : JSON.stringify(name.slice(0, 64));
+}
+/** The per-entry differences of two mappings (absent ⇒ `{}`); a non-mapping on either side is the whole key. */
+function mappingDrift(prefix, head, trusted, out) {
+    const h = head ?? {};
+    const t = trusted ?? {};
+    const isMap = (x) => x !== null && typeof x === "object" && !Array.isArray(x);
+    if (!isMap(h) || !isMap(t)) {
+        if (!jsonDeepEqual(h, t))
+            out.push(prefix);
+        return;
+    }
+    const hm = h;
+    const tm = t;
+    const names = [...new Set([...Object.keys(hm), ...Object.keys(tm)])].sort();
+    for (const n of names) {
+        const inH = Object.hasOwn(hm, n);
+        const inT = Object.hasOwn(tm, n);
+        if (!inH || !inT || !jsonDeepEqual(hm[n], tm[n]))
+            out.push(`${prefix}.${driftSegment(n)}`);
+    }
+}
+/**
+ * audit a257-1 MEDIUM-A2 (pure): the dotted keys that differ between the PR head's view and the trusted view —
+ * `hounfour.providers.<name>` (every field: endpoint, auth template, models, opt-ins), `hounfour.aliases.<alias>`,
+ * `hounfour.locality` (absent ⇒ `hosted`), `hounfour.secret_env_allowlist` and a root `secret_env_allowlist` (absent ⇒
+ * `[]`). An absent head file reads as all defaults; an unparsable head is drift on `.loa.config.yaml` itself (fail
+ * closed: cheval's YAML reader might accept what yq refused).
+ */
+export function computeHeadDrift(head, trusted, headUnreadable = false) {
+    if (headUnreadable)
+        return [".loa.config.yaml (unreadable in the PR head)"];
+    const h = head ?? {};
+    const out = [];
+    mappingDrift("hounfour.providers", h.providers, trusted.providers, out);
+    mappingDrift("hounfour.aliases", h.aliases, trusted.aliases, out);
+    if (!jsonDeepEqual(h.locality ?? "hosted", trusted.locality ?? "hosted"))
+        out.push("hounfour.locality");
+    if (!jsonDeepEqual(h.allowlist ?? [], trusted.allowlist ?? []))
+        out.push("hounfour.secret_env_allowlist");
+    if (!jsonDeepEqual(h.rootAllowlist ?? [], trusted.rootAllowlist ?? []))
+        out.push("secret_env_allowlist");
+    return out;
+}
+/** Where the trusted config came from, in words, for the drift refusal. */
+export function trustedSourceDescription(t) {
+    if (t.source === "base-ref")
+        return `the trusted config (base-ref ${t.ref ?? "unknown"})`;
+    if (t.source === "repository-settings")
+        return `the trusted config (${TRUSTED_CONFIG_ENV})`;
+    if (t.source === "none")
+        return "the trusted config (none could be read)";
+    return `the trusted config (${t.source})`;
+}
+/** Exit code for a multi-model run refused by trusted-config drift (distinct from 0, 3 DEGRADED and 4 FAILED). */
+export const EXIT_TRUSTED_CONFIG_DRIFT = 5;
+/**
+ * The refusal decision for the multi-model run (pure; main.ts prints and exits): the stderr line, or undefined when the
+ * run may proceed (local mode, or no drift).
+ */
+export function headDriftRefusal(t) {
+    const drift = t.mode === "pull-request" ? (t.headDrift ?? []) : [];
+    if (drift.length === 0)
+        return undefined;
+    return `[bridgebuilder] trusted config drift refused: ${drift.join(", ")} differ between the PR head and ` +
+        `${trustedSourceDescription(t)}; merge the base branch into the head or set ${TRUSTED_CONFIG_ENV}`;
~~~~

## H53 — .claude/skills/bridgebuilder-review/dist/config.js — head lines 651–664

Head context (head/.claude/skills/bridgebuilder-review/dist/config.js, lines 639–676):

~~~~text
   639 |             warnings.push(`[bridgebuilder] bridgebuilder.exit_on_degraded: invalid value ${JSON.stringify(view.exit)} (expected an integer 0..125) — using ${DEFAULT_EXIT_ON_DEGRADED}`);
   640 |         }
   641 |     }
   642 |     return { mode, source, ...(ref ? { ref } : {}), providers, headOnlyRefused, locality, exitOnDegraded, warnings };
   643 | }
   644 | /** One startup line naming where the trusted config was read from (main.ts prints it with the warnings). */
   645 | export function trustedConfigStartupLine(t) {
   646 |     const where = t.source === "base-ref" ? `base-ref ${t.ref}` : t.source;
   647 |     const keyless = Object.entries(t.providers).filter(([, d]) => d.keyless).map(([n]) => n);
   648 |     return `[bridgebuilder] Trusted config: ${where} (mode: ${t.mode}); locality: ${t.locality}; exit_on_degraded: ${t.exitOnDegraded}` +
   649 |         (keyless.length > 0 ? `; keyless providers: ${keyless.join(", ")}` : "");
   650 | }
>  651 | /**
>  652 |  * True when the trusted config marks this voice's provider `dispatch_group: local` (D-8.0): the model's own entry when
>  653 |  * declared, else the provider-level key, else every declared model of the provider. Anything undeclared is hosted.
>  654 |  */
>  655 | export function isLocalVoice(provider, modelId, trusted) {
>  656 |     const decl = Object.hasOwn(trusted.providers, provider) ? trusted.providers[provider] : undefined;
>  657 |     if (!decl)
>  658 |         return false;
>  659 |     if (Object.hasOwn(decl.modelGroups, modelId) && decl.modelGroups[modelId] !== undefined)
>  660 |         return decl.modelGroups[modelId] === "local";
>  661 |     if (decl.dispatchGroup !== undefined)
>  662 |         return decl.dispatchGroup === "local";
>  663 |     const groups = Object.values(decl.modelGroups);
>  664 |     return groups.length > 0 && groups.every((g) => g === "local");
   665 | }
   666 | /**
   667 |  * D-8.1: under `hounfour.locality: local_voices` drop every planned voice whose provider is not local, each with the named
   668 |  * reason; never reroute. `hosted` (the default) returns the list unchanged.
   669 |  */
   670 | export function applyLocality(models, trusted) {
   671 |     if (trusted.locality !== "local_voices")
   672 |         return { kept: models, refused: [] };
   673 |     const kept = [];
   674 |     const refused = [];
   675 |     for (const m of models) {
   676 |         if (isLocalVoice(m.provider, m.model_id, trusted))
~~~~

The change from head to the fix:

~~~~diff
@@ -651,14 +787,151 @@
+/** The local-hop rule's wording, shared with cheval (endpoint_policy.LOCAL_RULE_TEXT) and the planner. */
+export const LOCAL_RULE_TEXT = "a loopback or RFC1918 IP literal or localhost";
+function ipv4Octets(host) {
+    const m = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(host);
+    if (!m)
+        return undefined;
+    const parts = m.slice(1).map((s) => (s.length > 1 && s.startsWith("0") ? NaN : Number(s))); // no leading zeros, as Python ipaddress
+    return parts.every((n) => Number.isInteger(n) && n >= 0 && n <= 255) ? parts : undefined;
+}
 /**
- * True when the trusted config marks this voice's provider `dispatch_group: local` (D-8.0): the model's own entry when
- * declared, else the provider-level key, else every declared model of the provider. Anything undeclared is hosted.
+ * The local-hop rule (D-8.1, review round r257-1) on a provider endpoint: `ok` when it is an http(s) URL whose host is an
+ * IP literal in a loopback (127.0.0.0/8, ::1) or RFC1918 (10/8, 172.16/12, 192.168/16) range, or the literal `localhost`.
+ * Link-local, metadata, unique-local IPv6, public ranges and every other DNS name fail. A stdlib mirror of the canonical
+ * validator's `check_insecure_optin` host acceptance (the generated TypeScript port does not export it): the authority is
+ * split by hand, not by WHATWG `URL`, so a host such as `0x7f.1` stays a DNS name here exactly as it does in Python.
+ * `host` is the canonical host for a refusal message ("" when there is no endpoint).
  */
-export function isLocalVoice(provider, modelId, trusted) {
+export function localEndpointHost(endpoint) {
+    if (typeof endpoint !== "string" || endpoint.trim() === "")
+        return { ok: false, host: "" };
+    const m = /^([A-Za-z][A-Za-z0-9+.-]*):\/\/([^/?#]*)/.exec(endpoint.trim());
+    if (!m)
+        return { ok: false, host: "unparseable" };
+    const scheme = m[1].toLowerCase();
+    let authority = m[2];
+    const at = authority.lastIndexOf("@");
+    if (at >= 0)
+        authority = authority.slice(at + 1);
+    let host;
+    let port;
+    if (authority.startsWith("[")) {
+        const close = authority.indexOf("]");
+        if (close < 0)
+            return { ok: false, host: "unparseable" };
+        host = authority.slice(1, close);
+        port = authority.slice(close + 1);
+    }
+    else {
+        const colon = authority.indexOf(":");
+        host = colon >= 0 ? authority.slice(0, colon) : authority;
+        port = colon >= 0 ? authority.slice(colon) : "";
+    }
+    if (port !== "" && !/^:\d*$/.test(port))
+        return { ok: false, host: "unparseable" };
+    if (port.length > 1 && Number(port.slice(1)) > 65535)
+        return { ok: false, host: "unparseable" };
+    host = host.toLowerCase();
+    if (host.endsWith(".") && !host.endsWith(".."))
+        host = host.slice(0, -1);
+    if (host === "")
+        return { ok: false, host: "unparseable" };
+    if (scheme !== "http" && scheme !== "https")
+        return { ok: false, host };
+    if (host === "localhost")
+        return { ok: true, host };
+    const v4 = ipv4Octets(host);
+    if (v4) {
+        const [a, b] = v4;
+        const ok = a === 127 || a === 10 || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168);
+        return { ok, host: v4.join(".") };
+    }
+    if (isIPv6(host)) {
+        let canonical = host;
+        try {
+            canonical = new URL(`http://[${host}]/`).hostname.replace(/^\[|\]$/g, "");
+        }
+        catch {
+            return { ok: false, host };
+        }
+        return { ok: canonical === "::1", host: canonical };
+    }
+    return { ok: false, host };
+}
+/**
+ * The locality decision for one voice. `declared`: the trusted config marks it `dispatch_group: local` (the model's own
+ * entry when declared, else the provider-level key, else every declared model of the provider). `local`: declared AND
+ * the provider honours it — not a CLI provider, and its endpoint host passes the local-hop rule (D-8.1, r257-1: a
+ * declared locality is enforced, not trusted). `reason` names why a declared voice is still hosted.
+ */
+export function localVoiceDecision(provider, modelId, trusted) {
+    return localVoiceDecisionAt(provider, modelId, trusted, 0, new Set());
+}
+/** The fallback walk's depth bound (audit a257-1 MEDIUM-A1 (c); endpoint_policy.LOCAL_FALLBACK_MAX_DEPTH). */
+export const LOCAL_FALLBACK_MAX_DEPTH = 8;
+/**
+ * A `fallback_chain` entry as `[provider, model]`: a `provider:model` pin, or an alias followed through the TRUSTED
+ * `hounfour.aliases` (depth-limited, cycle-safe). Undefined when it does not resolve — the caller treats that as hosted.
+ */
+export function resolveFallbackSpec(spec, aliases) {
+    let current = spec.trim();
+    const seen = new Set();
+    for (let i = 0; i <= LOCAL_FALLBACK_MAX_DEPTH; i += 1) {
+        if (current === "")
+            return undefined;
+        const colon = current.indexOf(":");
+        if (colon >= 0) {
+            const p = current.slice(0, colon);
+            const m = current.slice(colon + 1);
+            return p !== "" && m !== "" ? [p, m] : undefined;
+        }
+        if (seen.has(current))
+            return undefined;
+        seen.add(current);
+        current = aliases && Object.hasOwn(aliases, current) ? aliases[current] : "";
+    }
+    return undefined;
+}
+function localVoiceDecisionAt(provider, modelId, trusted, depth, seen) {
     const decl = Object.hasOwn(trusted.providers, provider) ? trusted.providers[provider] : undefined;
     if (!decl)
-        return false;
+        return { local: false, declared: false };
+    let declared;
     if (Object.hasOwn(decl.modelGroups, modelId) && decl.modelGroups[modelId] !== undefined)
-        return decl.modelGroups[modelId] === "local";
-    if (decl.dispatchGroup !== undefined)
-        return decl.dispatchGroup === "local";
-    const groups = Object.values(decl.modelGroups);
-    return groups.length > 0 && groups.every((g) => g === "local");
+        declared = decl.modelGroups[modelId] === "local";
+    else if (decl.dispatchGroup !== undefined)
+        declared = decl.dispatchGroup === "local";
+    else {
+        const groups = Object.values(decl.modelGroups);
+        declared = groups.length > 0 && groups.every((g) => g === "local");
+    }
+    if (!declared)
+        return { local: false, declared: false };
+    const head = `locality: local_voices refuses hosted hop ${modelId} (${provider}): dispatch_group local but`;
+    if (decl.cli === true)
+        return { local: false, declared: true, reason: `${head} ${provider} is a CLI provider` };
+    const verdict = localEndpointHost(decl.endpoint);
+    if (!verdict.ok) {
+        return { local: false, declared: true, reason: `${head} endpoint host ${verdict.host || "(none declared)"} is not ${LOCAL_RULE_TEXT}` };
+    }
+    // audit a257-1 MEDIUM-A1 (c): cheval walks the model's own fallback_chain inside one call, so the voice is local only
+    // when every entry is (by this same rule, recursively; depth-limited, a cycle back to a voice on the walk is not new).
+    const key = `${provider}:${modelId}`;
+    if (seen.has(key))
+        return { local: true, declared: true };
+    seen.add(key);
+    const chain = decl.modelFallbacks && Object.hasOwn(decl.modelFallbacks, modelId) ? decl.modelFallbacks[modelId] : [];
+    for (const entry of chain) {
+        const hosted = { local: false, declared: true, reason: `${head} its fallback_chain reaches hosted hop ${entry || "(unreadable entry)"}` };
+        if (depth >= LOCAL_FALLBACK_MAX_DEPTH)
+            return hosted;
+        const target = resolveFallbackSpec(entry, trusted.aliases);
+        if (target === undefined)
+            return hosted;
+        if (!localVoiceDecisionAt(target[0], target[1], trusted, depth + 1, seen).local)
+            return hosted;
+    }
+    return { local: true, declared: true };
+}
+/** True when the voice is local by `localVoiceDecision` (declared `dispatch_group: local` AND the endpoint honours it). */
+export function isLocalVoice(provider, modelId, trusted) {
+    return localVoiceDecision(provider, modelId, trusted).local;
~~~~

## H54 — .claude/skills/bridgebuilder-review/dist/config.js — head lines 676–679

Head context (head/.claude/skills/bridgebuilder-review/dist/config.js, lines 664–691):

~~~~text
   664 |     return groups.length > 0 && groups.every((g) => g === "local");
   665 | }
   666 | /**
   667 |  * D-8.1: under `hounfour.locality: local_voices` drop every planned voice whose provider is not local, each with the named
   668 |  * reason; never reroute. `hosted` (the default) returns the list unchanged.
   669 |  */
   670 | export function applyLocality(models, trusted) {
   671 |     if (trusted.locality !== "local_voices")
   672 |         return { kept: models, refused: [] };
   673 |     const kept = [];
   674 |     const refused = [];
   675 |     for (const m of models) {
>  676 |         if (isLocalVoice(m.provider, m.model_id, trusted))
>  677 |             kept.push(m);
>  678 |         else
>  679 |             refused.push({ provider: m.provider, modelId: m.model_id, reason: localityRefusal(m.model_id, m.provider) });
   680 |     }
   681 |     return { kept, refused };
   682 | }
   683 | /**
   684 |  * The provider of a single-model `model` value for the locality check: `provider:model`, a generated-registry id, or a
   685 |  * model the trusted config declares; undefined when none says.
   686 |  */
   687 | export function resolveModelProvider(model, trusted) {
   688 |     const colon = model.indexOf(":");
   689 |     if (colon > 0)
   690 |         return model.slice(0, colon);
   691 |     if (Object.hasOwn(GENERATED_MODEL_REGISTRY, model))
~~~~

The change from head to the fix:

~~~~diff
@@ -676,4 +949,5 @@
-        if (isLocalVoice(m.provider, m.model_id, trusted))
+        const d = localVoiceDecision(m.provider, m.model_id, trusted);
+        if (d.local)
             kept.push(m);
         else
-            refused.push({ provider: m.provider, modelId: m.model_id, reason: localityRefusal(m.model_id, m.provider) });
+            refused.push({ provider: m.provider, modelId: m.model_id, reason: d.reason ?? localityRefusal(m.model_id, m.provider) });
~~~~

## H55 — .claude/skills/bridgebuilder-review/dist/config.js — head lines 708–710

Head context (head/.claude/skills/bridgebuilder-review/dist/config.js, lines 696–722):

~~~~text
   696 |     }
   697 |     return undefined;
   698 | }
   699 | /**
   700 |  * Under `local_voices`, the single-model path's voice must be local too: returns the refusal text, or undefined when the
   701 |  * voice may run (or the posture is hosted).
   702 |  */
   703 | export function singleModelLocalityRefusal(model, trusted) {
   704 |     if (trusted.locality !== "local_voices")
   705 |         return undefined;
   706 |     const provider = resolveModelProvider(model, trusted);
   707 |     const bare = provider !== undefined && model.startsWith(`${provider}:`) ? model.slice(provider.length + 1) : model;
>  708 |     if (provider !== undefined && isLocalVoice(provider, bare, trusted))
>  709 |         return undefined;
>  710 |     return localityRefusal(model, provider ?? "unresolved provider");
   711 | }
   712 | /**
   713 |  * The startup lines for the agy gate (r251-2 K7f): the read error and the type warning each said once, unconditionally —
   714 |  * not only when a voice is not planned — and the not-planned voices. main.ts prints them; the pipeline says its own once
   715 |  * per review.
   716 |  */
   717 | export function agyGateStartupLines(gate, keyStatus) {
   718 |     const lines = [];
   719 |     if (gate.readError !== undefined) {
   720 |         lines.push(`[bridgebuilder] agy gate: Loa config unreadable (${gate.readError}) — failing closed: google voices are not planned (hounfour.headless.agy_opt_in)`);
   721 |     }
   722 |     if (gate.typeWarning !== undefined)
~~~~

The change from head to the fix:

~~~~diff
@@ -708,3 +982,6 @@
-    if (provider !== undefined && isLocalVoice(provider, bare, trusted))
+    if (provider === undefined)
+        return localityRefusal(model, "unresolved provider");
+    const d = localVoiceDecision(provider, bare, trusted);
+    if (d.local)
         return undefined;
-    return localityRefusal(model, provider ?? "unresolved provider");
+    return d.reason ?? localityRefusal(model, provider);
~~~~

## H56 — .claude/skills/bridgebuilder-review/dist/config.js.map — head line 1

Head context (head/.claude/skills/bridgebuilder-review/dist/config.js.map, lines 1–1):

~~~~text
>    1 | {"version":3,"file":"config.js","sourceRoot":"","sources":["../resources/config.ts"],"names":[],"mappings":"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"}
~~~~

The change from head to the fix:

~~~~diff
@@ -1 +1 @@
-{"version":3,"file":"config.js","sourceRoot":"","sources":["../resources/config.ts"],"names":[],"mappings":"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"}
\ No newline at end of file
+{"version":3,"file":"config.js","sourceRoot":"","sources":["../resources/config.ts"],"names":[],"mappings":"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"}
\ No newline at end of file
~~~~

## H57 — .claude/skills/bridgebuilder-review/dist/core/types.d.ts — insertion after head line 75

Head context (head/.claude/skills/bridgebuilder-review/dist/core/types.d.ts, lines 64–87):

~~~~text
    64 | /** One `hounfour.providers.<name>` declaration as Bridgebuilder reads it (cycle-129 D-7.5, D-8.0 canonical keys). */
    65 | export interface ProviderDecl {
    66 |     /** `keyless: true`, or a literal `auth` value (normalised to keyless, D-8.0): no credential env var is required. */
    67 |     keyless: boolean;
    68 |     /** `allow_insecure_endpoint` is set (any non-null, non-false value). */
    69 |     insecure: boolean;
    70 |     /** The env var named by an `auth: "{env:VAR}"` template, when the declaration has one. */
    71 |     authEnv?: string;
    72 |     /** Provider-level `dispatch_group`, when declared. */
    73 |     dispatchGroup?: string;
    74 |     /** `models.<model_id>.dispatch_group` per declared model. */
    75 |     modelGroups: Record<string, string | undefined>;
    76 | }
    77 | /** Where the trusted provider configuration was read from. */
    78 | export type TrustedConfigSource = "working-tree" | "base-ref" | "repository-settings" | "none";
    79 | /** The trusted configuration view (cycle-129 D-7.5, D-7.7, D-8.1). */
    80 | export interface TrustedConfig {
    81 |     /** `pull-request` when run on a PR (`--pr`, `GITHUB_EVENT_NAME`, `GITHUB_BASE_REF`); `local` otherwise. */
    82 |     mode: "local" | "pull-request";
    83 |     source: TrustedConfigSource;
    84 |     /** The git ref the base config was read from (`source: base-ref`). */
    85 |     ref?: string;
    86 |     /** `hounfour.providers` from the trusted source only. */
    87 |     providers: Record<string, ProviderDecl>;
~~~~

The change from head to the fix:

~~~~diff
@@ -75,0 +76,9 @@
+    /** The declared `endpoint` (a string), when there is one — the local-hop rule reads its host (D-8.1, r257-1). */
+    endpoint?: string;
+    /** A CLI provider (`type: *-headless`, or every model `kind: cli`): never local (D-8.1, r257-1). */
+    cli?: boolean;
+    /**
+     * `models.<model_id>.fallback_chain` per declared model that has one (audit a257-1 MEDIUM-A1 (c)): cheval walks it
+     * inside one call, so a local voice is local only when every entry is. A non-string entry is kept as "" (unresolvable).
+     */
+    modelFallbacks?: Record<string, string[]>;
~~~~

## H58 — .claude/skills/bridgebuilder-review/dist/core/types.d.ts — insertion after head line 95

Head context (head/.claude/skills/bridgebuilder-review/dist/core/types.d.ts, lines 84–107):

~~~~text
    84 |     /** The git ref the base config was read from (`source: base-ref`). */
    85 |     ref?: string;
    86 |     /** `hounfour.providers` from the trusted source only. */
    87 |     providers: Record<string, ProviderDecl>;
    88 |     /** Providers the head checkout declares keyless or insecure that the trusted source does not: refused by name. */
    89 |     headOnlyRefused: string[];
    90 |     /** `hounfour.locality` (default `hosted`). */
    91 |     locality: "hosted" | "local_voices";
    92 |     /** `bridgebuilder.exit_on_degraded` (default 3; 0 restores the pre-cycle-129 exit). */
    93 |     exitOnDegraded: number;
    94 |     /** Lines to log once at startup (read failures, refusals, invalid values). */
    95 |     warnings: string[];
    96 | }
    97 | /** Multi-model provider configuration entry. */
    98 | export interface MultiModelProviderEntry {
    99 |     provider: string;
   100 |     model_id: string;
   101 |     role: "primary" | "reviewer";
   102 | }
   103 | /** Multi-model Bridgebuilder configuration. */
   104 | export interface MultiModelConfig {
   105 |     enabled: boolean;
   106 |     models: MultiModelProviderEntry[];
   107 |     iteration_strategy: "every" | "final" | number[];
~~~~

The change from head to the fix:

~~~~diff
@@ -95,0 +105,9 @@
+    /** `hounfour.aliases` from the trusted source (string targets only) — resolves `fallback_chain` aliases (MEDIUM-A1 (c)). */
+    aliases?: Record<string, string>;
+    /**
+     * Pull-request mode only (audit a257-1 MEDIUM-A2): the dotted keys among `hounfour.providers.<name>`,
+     * `hounfour.aliases.<alias>`, `hounfour.locality` and the secret allowlists that differ between the PR head and the
+     * trusted source. cheval reads the checkout's configuration for the dispatch, so a non-empty list refuses the
+     * multi-model run (main.ts, exit 5). Always `[]` in local mode.
+     */
+    headDrift?: string[];
~~~~

## H59 — .claude/skills/bridgebuilder-review/dist/core/types.d.ts.map — head line 1

Head context (head/.claude/skills/bridgebuilder-review/dist/core/types.d.ts.map, lines 1–1):

~~~~text
>    1 | {"version":3,"file":"types.d.ts","sourceRoot":"","sources":["../../resources/core/types.ts"],"names":[],"mappings":"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"}
~~~~

The change from head to the fix:

~~~~diff
@@ -1 +1 @@
-{"version":3,"file":"types.d.ts","sourceRoot":"","sources":["../../resources/core/types.ts"],"names":[],"mappings":"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"}
\ No newline at end of file
+{"version":3,"file":"types.d.ts","sourceRoot":"","sources":["../../resources/core/types.ts"],"names":[],"mappings":"AAAA,OAAO,KAAK,EAAE,WAAW,EAAE,eAAe,EAAE,MAAM,0BAA0B,CAAC;AAE7E,MAAM,WAAW,mBAAmB;IAClC,KAAK,EAAE,KAAK,CAAC;QAAE,KAAK,EAAE,MAAM,CAAC;QAAC,IAAI,EAAE,MAAM,CAAA;KAAE,CAAC,CAAC;IAC9C,KAAK,EAAE,MAAM,CAAC;IACd,MAAM,EAAE,MAAM,CAAC;IACf,aAAa,EAAE,MAAM,CAAC;IACtB,YAAY,EAAE,MAAM,CAAC;IACrB,cAAc,EAAE,MAAM,CAAC;IACvB,eAAe,EAAE,MAAM,CAAC;IACxB,UAAU,EAAE,MAAM,EAAE,CAAC;IACrB,YAAY,EAAE,MAAM,CAAC;IACrB,gBAAgB,EAAE,MAAM,CAAC;IACzB,MAAM,EAAE,OAAO,CAAC;IAChB,eAAe,EAAE,MAAM,EAAE,CAAC;IAC1B,aAAa,EAAE,SAAS,GAAG,QAAQ,CAAC;IACpC,iBAAiB,EAAE,MAAM,CAAC;IAC1B,iFAAiF;IACjF,QAAQ,CAAC,EAAE,MAAM,CAAC;IAClB,+FAA+F;IAC/F,QAAQ,CAAC,EAAE,OAAO,CAAC;IACnB;;;;;;;;;;;;;;OAcG;IACH,UAAU,CAAC,EAAE,OAAO,CAAC;IACrB,2DAA2D;IAC3D,QAAQ,CAAC,EAAE,MAAM,CAAC;IAClB,iDAAiD;IACjD,OAAO,CAAC,EAAE,MAAM,CAAC;IACjB,gCAAgC;IAChC,eAAe,CAAC,EAAE,MAAM,CAAC;IACzB,2EAA2E;IAC3E,eAAe,CAAC,EAAE,OAAO,CAAC;IAC1B,gFAAgF;IAChF,UAAU,EAAE,UAAU,GAAG,aAAa,CAAC;IACvC,2FAA2F;IAC3F,oBAAoB,CAAC,EAAE,MAAM,CAAC;IAC9B,0DAA0D;IAC1D,UAAU,CAAC,EAAE;QAAE,OAAO,EAAE,OAAO,CAAA;KAAE,CAAC;IAClC,0FAA0F;IAC1F,UAAU,CAAC,EAAE,gBAAgB,CAAC;IAC9B;;;OAGG;IACH,OAAO,CAAC,EAAE,aAAa,CAAC;CACzB;AAED,qHAAqH;AACrH,MAAM,WAAW,YAAY;IAC3B,oHAAoH;IACpH,OAAO,EAAE,OAAO,CAAC;IACjB,wEAAwE;IACxE,QAAQ,EAAE,OAAO,CAAC;IAClB,0FAA0F;IAC1F,OAAO,CAAC,EAAE,MAAM,CAAC;IACjB,sDAAsD;IACtD,aAAa,CAAC,EAAE,MAAM,CAAC;IACvB,6DAA6D;IAC7D,WAAW,EAAE,MAAM,CAAC,MAAM,EAAE,MAAM,GAAG,SAAS,CAAC,CAAC;IAChD,iHAAiH;IACjH,QAAQ,CAAC,EAAE,MAAM,CAAC;IAClB,oGAAoG;IACpG,GAAG,CAAC,EAAE,OAAO,CAAC;IACd;;;OAGG;IACH,cAAc,CAAC,EAAE,MAAM,CAAC,MAAM,EAAE,MAAM,EAAE,CAAC,CAAC;CAC3C;AAED,8DAA8D;AAC9D,MAAM,MAAM,mBAAmB,GAAG,cAAc,GAAG,UAAU,GAAG,qBAAqB,GAAG,MAAM,CAAC;AAE/F,sEAAsE;AACtE,MAAM,WAAW,aAAa;IAC5B,2GAA2G;IAC3G,IAAI,EAAE,OAAO,GAAG,cAAc,CAAC;IAC/B,MAAM,EAAE,mBAAmB,CAAC;IAC5B,sEAAsE;IACtE,GAAG,CAAC,EAAE,MAAM,CAAC;IACb,yDAAyD;IACzD,SAAS,EAAE,MAAM,CAAC,MAAM,EAAE,YAAY,CAAC,CAAC;IACxC,kHAAkH;IAClH,eAAe,EAAE,MAAM,EAAE,CAAC;IAC1B,8CAA8C;IAC9C,QAAQ,EAAE,QAAQ,GAAG,cAAc,CAAC;IACpC,uFAAuF;IACvF,cAAc,EAAE,MAAM,CAAC;IACvB,8EAA8E;IAC9E,QAAQ,EAAE,MAAM,EAAE,CAAC;IACnB,4HAA4H;IAC5H,OAAO,CAAC,EAAE,MAAM,CAAC,MAAM,EAAE,MAAM,CAAC,CAAC;IACjC;;;;;OAKG;IACH,SAAS,CAAC,EAAE,MAAM,EAAE,CAAC;CACtB;AAED,gDAAgD;AAChD,MAAM,WAAW,uBAAuB;IACtC,QAAQ,EAAE,MAAM,CAAC;IACjB,QAAQ,EAAE,MAAM,CAAC;IACjB,IAAI,EAAE,SAAS,GAAG,UAAU,CAAC;CAC9B;AAED,+CAA+C;AAC/C,MAAM,WAAW,gBAAgB;IAC/B,OAAO,EAAE,OAAO,CAAC;IACjB,MAAM,EAAE,uBAAuB,EAAE,CAAC;IAClC,kBAAkB,EAAE,OAAO,GAAG,OAAO,GAAG,MAAM,EAAE,CAAC;IACjD,YAAY,EAAE,UAAU,GAAG,QAAQ,CAAC;IACpC,SAAS,EAAE;QACT,OAAO,EAAE,OAAO,CAAC;QACjB,kBAAkB,EAAE;YAClB,cAAc,EAAE,MAAM,CAAC;YACvB,cAAc,EAAE,MAAM,CAAC;YACvB,SAAS,EAAE,MAAM,CAAC;YAClB,OAAO,EAAE,MAAM,CAAC;SACjB,CAAC;KACH,CAAC;IACF,YAAY,EAAE;QACZ,SAAS,EAAE,MAAM,GAAG,IAAI,CAAC;QACzB,KAAK,EAAE,MAAM,GAAG,IAAI,CAAC;KACtB,CAAC;IACF,KAAK,EAAE;QACL,oBAAoB,EAAE,OAAO,CAAC;QAC9B,sBAAsB,EAAE,MAAM,CAAC;QAC/B,sBAAsB,EAAE,OAAO,CAAC;QAChC,mBAAmB,EAAE,OAAO,CAAC;QAC7B;;;;WAIG;QACH,SAAS,CAAC,EAAE,MAAM,CAAC;KACpB,CAAC;IACF,UAAU,EAAE;QACV,WAAW,EAAE,OAAO,CAAC;QACrB,WAAW,EAAE,MAAM,EAAE,CAAC;QACtB,yFAAyF;QACzF,cAAc,EAAE,MAAM,EAAE,CAAC;KAC1B,CAAC;IACF,MAAM,EAAE;QACN,OAAO,EAAE,OAAO,CAAC;QACjB,eAAe,EAAE,MAAM,CAAC;QACxB,qBAAqB,EAAE,OAAO,CAAC;KAChC,CAAC;IACF,QAAQ,EAAE;QACR,OAAO,EAAE,OAAO,CAAC;KAClB,CAAC;IACF,eAAe,CAAC,EAAE,MAAM,CAAC;IACzB,UAAU,CAAC,EAAE,MAAM,CAAC,MAAM,EAAE;QAAE,KAAK,EAAE,MAAM,CAAC;QAAC,MAAM,EAAE,MAAM,CAAA;KAAE,CAAC,CAAC;CAChE;AAED,MAAM,WAAW,UAAU;IACzB,KAAK,EAAE,MAAM,CAAC;IACd,IAAI,EAAE,MAAM,CAAC;IACb,EAAE,EAAE,WAAW,CAAC;IAChB,KAAK,EAAE,eAAe,EAAE,CAAC;IACzB,IAAI,EAAE,MAAM,CAAC;CACd;AAED,MAAM,MAAM,aAAa,GAAG,WAAW,GAAG,WAAW,GAAG,SAAS,CAAC;AAElE,MAAM,WAAW,WAAW;IAC1B,IAAI,EAAE,MAAM,CAAC;IACb,OAAO,EAAE,MAAM,CAAC;IAChB,QAAQ,EAAE,aAAa,CAAC;IACxB,SAAS,EAAE,OAAO,CAAC;IACnB,MAAM,EAAE,QAAQ,GAAG,KAAK,GAAG,WAAW,GAAG,UAAU,CAAC;CACrD;AAED,2CAA2C;AAC3C,MAAM,WAAW,gBAAgB;IAC/B,KAAK,EAAE,MAAM,CAAC;IACd,MAAM,EAAE,MAAM,CAAC;IACf,QAAQ,EAAE,MAAM,CAAC;CAClB;AAED,MAAM,WAAW,YAAY;IAC3B,IAAI,EAAE,UAAU,CAAC;IACjB,MAAM,EAAE,OAAO,CAAC;IAChB,OAAO,EAAE,OAAO,CAAC;IACjB,UAAU,CAAC,EAAE,MAAM,CAAC;IACpB,WAAW,CAAC,EAAE,MAAM,CAAC;IACrB,YAAY,CAAC,EAAE,MAAM,CAAC;IACtB,KAAK,CAAC,EAAE,WAAW,CAAC;IACpB,gEAAgE;IAChE,WAAW,CAAC,EAAE,MAAM,CAAC;IACrB,+DAA+D;IAC/D,WAAW,CAAC,EAAE,gBAAgB,CAAC;IAC/B,8DAA8D;IAC9D,WAAW,CAAC,EAAE,gBAAgB,CAAC;IAC/B,uEAAuE;IACvE,oBAAoB,CAAC,EAAE;QAAE,GAAG,EAAE,MAAM,CAAC;QAAC,GAAG,EAAE,MAAM,CAAC;QAAC,IAAI,EAAE,MAAM,CAAC;QAAC,KAAK,EAAE,MAAM,CAAA;KAAE,CAAC;IACjF,qEAAqE;IACrE,SAAS,CAAC,EAAE,MAAM,CAAC;IACnB,kEAAkE;IAClE,WAAW,CAAC,EAAE,MAAM,CAAC;IACrB,kEAAkE;IAClE,aAAa,CAAC,EAAE,OAAO,CAAC;IACxB,uEAAuE;IACvE,OAAO,CAAC,EAAE,iBAAiB,GAAG,SAAS,GAAG,SAAS,GAAG,SAAS,CAAC;IAChE,eAAe,CAAC,EAAE,MAAM,GAAG,IAAI,CAAC;IAChC,YAAY,CAAC,EAAE,OAAO,CAAC;CACxB;AAED,MAAM,WAAW,UAAU;IACzB,QAAQ,EAAE,MAAM,CAAC;IACjB,OAAO,EAAE,MAAM,CAAC;IAChB,MAAM,EAAE,MAAM,CAAC;IACf,SAAS,EAAE,MAAM,CAAC;IAClB,OAAO,EAAE,MAAM,CAAC;IAChB,KAAK,EAAE,MAAM,CAAC;IACd,OAAO,EAAE,YAAY,EAAE,CAAC;CACzB;AAED,MAAM,WAAW,gBAAgB;IAC/B,QAAQ,EAAE,eAAe,EAAE,CAAC;IAC5B,QAAQ,EAAE,KAAK,CAAC;QAAE,QAAQ,EAAE,MAAM,CAAC;QAAC,KAAK,EAAE,MAAM,CAAA;KAAE,CAAC,CAAC;IACrD,UAAU,EAAE,MAAM,CAAC;IACnB,gFAAgF;IAChF,WAAW,CAAC,EAAE,OAAO,CAAC;IACtB,kDAAkD;IAClD,SAAS,CAAC,EAAE,MAAM,CAAC;IACnB,gCAAgC;IAChC,QAAQ,CAAC,EAAE;QAAE,aAAa,EAAE,MAAM,CAAC;QAAC,UAAU,EAAE,MAAM,CAAA;KAAE,CAAC;IACzD;;;;;;;;;;;OAWG;IACH,gBAAgB,EAAE,OAAO,CAAC;IAC1B;;;;;;;;;OASG;IACH,eAAe,EAAE,UAAU,GAAG,QAAQ,GAAG,UAAU,CAAC;IACpD,wEAAwE;IACxE,eAAe,CAAC,EAAE,CAAC,GAAG,CAAC,GAAG,CAAC,CAAC;IAC5B,wDAAwD;IACxD,oBAAoB,CAAC,EAAE,MAAM,CAAC;CAC/B;AAED,MAAM,WAAW,kBAAkB;IACjC,KAAK,EAAE,OAAO,CAAC;IACf,OAAO,CAAC,EAAE,MAAM,CAAC;IACjB,MAAM,EAAE,MAAM,GAAG,iBAAiB,CAAC;CACpC;AAED,2EAA2E;AAC3E,MAAM,WAAW,oBAAoB;IACnC,OAAO,EAAE,MAAM,CAAC;IAChB,QAAQ,EAAE,MAAM,CAAC;IACjB,SAAS,EAAE,MAAM,CAAC;CACnB;AAED,wCAAwC;AACxC,MAAM,WAAW,WAAW;IAC1B,QAAQ,EAAE,MAAM,CAAC;IACjB,SAAS,EAAE,MAAM,CAAC;IAClB,WAAW,EAAE,MAAM,CAAC;CACrB;AAED,yDAAyD;AACzD,MAAM,WAAW,2BAA2B;IAC1C,OAAO,EAAE,OAAO,CAAC;IACjB,KAAK,CAAC,EAAE,CAAC,GAAG,CAAC,GAAG,CAAC,CAAC;IAClB,KAAK,EAAE,eAAe,EAAE,CAAC;IACzB,QAAQ,EAAE,KAAK,CAAC;QAAE,QAAQ,EAAE,MAAM,CAAC;QAAC,KAAK,EAAE,MAAM,CAAA;KAAE,CAAC,CAAC;IACrD,UAAU,EAAE,MAAM,CAAC;IACnB,UAAU,CAAC,EAAE,MAAM,CAAC;IACpB,aAAa,CAAC,EAAE,sBAAsB,CAAC;CACxC;AAED,4DAA4D;AAC5D,MAAM,WAAW,eAAe;IAC9B,EAAE,EAAE,MAAM,CAAC;IACX,OAAO,EAAE,MAAM,CAAC;IAChB,IAAI,EAAE,MAAM,CAAC;CACd;AAED,gFAAgF;AAChF,MAAM,WAAW,gBAAgB;IAC/B,QAAQ,EAAE,KAAK,CAAC;QAAE,IAAI,EAAE,MAAM,CAAC;QAAC,EAAE,CAAC,EAAE,MAAM,CAAC;QAAC,OAAO,EAAE,MAAM,CAAC;QAAC,UAAU,EAAE,MAAM,CAAA;KAAE,CAAC,CAAC;IACpF,WAAW,EAAE,MAAM,CAAC;CACrB;AAED,gFAAgF;AAChF,MAAM,WAAW,iBAAiB;IAChC,aAAa,EAAE,MAAM,CAAC;IACtB,UAAU,EAAE,MAAM,CAAC;CACpB;AAED,kGAAkG;AAClG,MAAM,WAAW,iBAAiB;IAChC,YAAY,EAAE,MAAM,CAAC;IACrB,IAAI,EAAE,UAAU,CAAC;IACjB,OAAO,EAAE,MAAM,CAAC;IAChB,iBAAiB,CAAC,EAAE,iBAAiB,CAAC;IACtC,eAAe,CAAC,EAAE,eAAe,CAAC;IAClC,gBAAgB,CAAC,EAAE,gBAAgB,CAAC;IACpC;;;;OAIG;IACH,WAAW,CAAC,EAAE,YAAY,EAAE,CAAC;IAC7B;;;OAGG;IACH,gBAAgB,CAAC,EAAE,gBAAgB,CAAC;CACrC;AAED;;;GAGG;AACH,MAAM,WAAW,YAAY;IAC3B,EAAE,EAAE,MAAM,CAAC;IACX,IAAI,EAAE,MAAM,CAAC;IACb,KAAK,EAAE,MAAM,CAAC;IACd,OAAO,EAAE,MAAM,CAAC;IAChB,MAAM,CAAC,EAAE,MAAM,CAAC;IAChB,IAAI,CAAC,EAAE,MAAM,EAAE,CAAC;CACjB;AAED,uEAAuE;AACvE,MAAM,WAAW,sBAAsB;IACrC,OAAO,EAAE,MAAM,CAAC;IAChB,QAAQ,EAAE,MAAM,CAAC;IACjB,QAAQ,EAAE,MAAM,CAAC;IACjB,KAAK,EAAE,MAAM,CAAC;IACd,KAAK,EAAE,MAAM,CAAC;CACf;AAED;;;GAGG;AACH,MAAM,WAAW,gBAAgB;IAC/B,IAAI,EAAE,MAAM,CAAC;IACb,EAAE,EAAE,MAAM,CAAC;IACX,OAAO,EAAE,MAAM,CAAC;IAChB,UAAU,EAAE,MAAM,CAAC;IACnB,aAAa,EAAE,MAAM,CAAC;IACtB,UAAU,EAAE,MAAM,GAAG,SAAS,CAAC;CAChC;AAED;;;;GAIG;AACH,MAAM,WAAW,oBAAoB;IACnC,IAAI,EAAE,MAAM,CAAC;IACb,OAAO,EAAE,MAAM,CAAC;IAChB,IAAI,EAAE,MAAM,CAAC;IACb,WAAW,EAAE,MAAM,CAAC;IACpB,UAAU,EAAE,MAAM,EAAE,CAAC;IACrB,YAAY,CAAC,EAAE,MAAM,EAAE,CAAC;CACzB"}
\ No newline at end of file
~~~~

## H60 — .claude/skills/bridgebuilder-review/dist/main.d.ts.map — head line 1

Head context (head/.claude/skills/bridgebuilder-review/dist/main.d.ts.map, lines 1–1):

~~~~text
>    1 | {"version":3,"file":"main.d.ts","sourceRoot":"","sources":["../resources/main.ts"],"names":[],"mappings":"AA0BA,OAAO,KAAK,EAAE,mBAAmB,EAAc,MAAM,iBAAiB,CAAC;AAoBvE;;;GAGG;AACH,wBAAgB,uBAAuB,CAAC,GAAG,EAAE,MAAM,GAAG;IAAE,OAAO,EAAE,MAAM,CAAC;IAAC,KAAK,CAAC,EAAE,MAAM,CAAA;CAAE,CAexF;AAED;;;GAGG;AACH,wBAAsB,gBAAgB,IAAI,OAAO,CAAC,MAAM,EAAE,CAAC,CAU1D;AAED;;;;;GAKG;AACH,wBAAsB,gBAAgB,CAAC,QAAQ,EAAE,MAAM,GAAG,OAAO,CAAC,MAAM,CAAC,CAWxE;AAED;;;;;GAKG;AACH,MAAM,WAAW,qBAAqB;IACpC,KAAK,EAAE,MAAM,CAAC;IACd,IAAI,EAAE,MAAM,CAAC;IACb,KAAK,EAAE,QAAQ,GAAG,MAAM,GAAG,QAAQ,GAAG,SAAS,CAAC;IAChD,KAAK,CAAC,EAAE,MAAM,CAAC;IACf,MAAM,CAAC,EAAE,MAAM,CAAC;CACjB;AAED,wBAAsB,eAAe,CACnC,MAAM,EAAE,mBAAmB,GAC1B,OAAO,CAAC,qBAAqB,EAAE,CAAC,CAqHlC;AAED;;GAEG;AACH,wBAAgB,qBAAqB,CAAC,KAAK,EAAE,qBAAqB,EAAE,GAAG,MAAM,CAiB5E;AAED;;;;;;;;;GASG;AACH,wBAAsB,WAAW,CAC/B,MAAM,EAAE,mBAAmB,EAC3B,MAAM,CAAC,EAAE;IAAE,IAAI,EAAE,CAAC,GAAG,EAAE,MAAM,KAAK,IAAI,CAAA;CAAE,GACvC,OAAO,CAAC;IAAE,OAAO,EAAE,MAAM,CAAC;IAAC,MAAM,EAAE,MAAM,CAAC;IAAC,KAAK,CAAC,EAAE,MAAM,CAAA;CAAE,CAAC,CA2E9D"}
~~~~

The change from head to the fix:

~~~~diff
@@ -1 +1 @@
-{"version":3,"file":"main.d.ts","sourceRoot":"","sources":["../resources/main.ts"],"names":[],"mappings":"AA0BA,OAAO,KAAK,EAAE,mBAAmB,EAAc,MAAM,iBAAiB,CAAC;AAoBvE;;;GAGG;AACH,wBAAgB,uBAAuB,CAAC,GAAG,EAAE,MAAM,GAAG;IAAE,OAAO,EAAE,MAAM,CAAC;IAAC,KAAK,CAAC,EAAE,MAAM,CAAA;CAAE,CAexF;AAED;;;GAGG;AACH,wBAAsB,gBAAgB,IAAI,OAAO,CAAC,MAAM,EAAE,CAAC,CAU1D;AAED;;;;;GAKG;AACH,wBAAsB,gBAAgB,CAAC,QAAQ,EAAE,MAAM,GAAG,OAAO,CAAC,MAAM,CAAC,CAWxE;AAED;;;;;GAKG;AACH,MAAM,WAAW,qBAAqB;IACpC,KAAK,EAAE,MAAM,CAAC;IACd,IAAI,EAAE,MAAM,CAAC;IACb,KAAK,EAAE,QAAQ,GAAG,MAAM,GAAG,QAAQ,GAAG,SAAS,CAAC;IAChD,KAAK,CAAC,EAAE,MAAM,CAAC;IACf,MAAM,CAAC,EAAE,MAAM,CAAC;CACjB;AAED,wBAAsB,eAAe,CACnC,MAAM,EAAE,mBAAmB,GAC1B,OAAO,CAAC,qBAAqB,EAAE,CAAC,CAqHlC;AAED;;GAEG;AACH,wBAAgB,qBAAqB,CAAC,KAAK,EAAE,qBAAqB,EAAE,GAAG,MAAM,CAiB5E;AAED;;;;;;;;;GASG;AACH,wBAAsB,WAAW,CAC/B,MAAM,EAAE,mBAAmB,EAC3B,MAAM,CAAC,EAAE;IAAE,IAAI,EAAE,CAAC,GAAG,EAAE,MAAM,KAAK,IAAI,CAAA;CAAE,GACvC,OAAO,CAAC;IAAE,OAAO,EAAE,MAAM,CAAC;IAAC,MAAM,EAAE,MAAM,CAAC;IAAC,KAAK,CAAC,EAAE,MAAM,CAAA;CAAE,CAAC,CA2E9D"}
\ No newline at end of file
+{"version":3,"file":"main.d.ts","sourceRoot":"","sources":["../resources/main.ts"],"names":[],"mappings":"AA4BA,OAAO,KAAK,EAAE,mBAAmB,EAAc,MAAM,iBAAiB,CAAC;AAoBvE;;;GAGG;AACH,wBAAgB,uBAAuB,CAAC,GAAG,EAAE,MAAM,GAAG;IAAE,OAAO,EAAE,MAAM,CAAC;IAAC,KAAK,CAAC,EAAE,MAAM,CAAA;CAAE,CAexF;AAED;;;GAGG;AACH,wBAAsB,gBAAgB,IAAI,OAAO,CAAC,MAAM,EAAE,CAAC,CAU1D;AAED;;;;;GAKG;AACH,wBAAsB,gBAAgB,CAAC,QAAQ,EAAE,MAAM,GAAG,OAAO,CAAC,MAAM,CAAC,CAWxE;AAED;;;;;GAKG;AACH,MAAM,WAAW,qBAAqB;IACpC,KAAK,EAAE,MAAM,CAAC;IACd,IAAI,EAAE,MAAM,CAAC;IACb,KAAK,EAAE,QAAQ,GAAG,MAAM,GAAG,QAAQ,GAAG,SAAS,CAAC;IAChD,KAAK,CAAC,EAAE,MAAM,CAAC;IACf,MAAM,CAAC,EAAE,MAAM,CAAC;CACjB;AAED,wBAAsB,eAAe,CACnC,MAAM,EAAE,mBAAmB,GAC1B,OAAO,CAAC,qBAAqB,EAAE,CAAC,CAqHlC;AAED;;GAEG;AACH,wBAAgB,qBAAqB,CAAC,KAAK,EAAE,qBAAqB,EAAE,GAAG,MAAM,CAiB5E;AAED;;;;;;;;;GASG;AACH,wBAAsB,WAAW,CAC/B,MAAM,EAAE,mBAAmB,EAC3B,MAAM,CAAC,EAAE;IAAE,IAAI,EAAE,CAAC,GAAG,EAAE,MAAM,KAAK,IAAI,CAAA;CAAE,GACvC,OAAO,CAAC;IAAE,OAAO,EAAE,MAAM,CAAC;IAAC,MAAM,EAAE,MAAM,CAAC;IAAC,KAAK,CAAC,EAAE,MAAM,CAAA;CAAE,CAAC,CA2E9D"}
\ No newline at end of file
~~~~

## H61 — .claude/skills/bridgebuilder-review/dist/main.js — head line 6

Head context (head/.claude/skills/bridgebuilder-review/dist/main.js, lines 1–18):

~~~~text
     1 | import { readFile, readdir } from "node:fs/promises";
     2 | import { resolve, dirname } from "node:path";
     3 | import { fileURLToPath } from "node:url";
     4 | import { ReviewPipeline, PRReviewTemplate, BridgebuilderContext, } from "./core/index.js";
     5 | import { createLocalAdapters } from "./adapters/index.js";
>    6 | import { parseCLIArgs, resolveConfig, resolveRepos, formatEffectiveConfig, loadMultiModelConfig, validateApiKeys, readAgyGate, agyGateStartupLines, loaConfigPathFor, loadTrustedConfig, trustedConfigStartupLine, applyLocality, singleModelLocalityRefusal, } from "./config.js";
     7 | import { summarizeVoices, totalVoices, decideExitCode, degradedWarnLine } from "./core/run-outcome.js";
     8 | import { executeMultiModelReview } from "./core/multi-model-pipeline.js";
     9 | import { DEFAULT_LORE_PATH, loadLoreEntries } from "./core/lore-loader.js";
    10 | import { detectRefs, parseManualRefs, fetchCrossRepoContext } from "./core/cross-repo.js";
    11 | import { renderCrossRepoSection } from "./core/cross-repo-render.js";
    12 | import { ProgressReporter } from "./core/progress.js";
    13 | import { buildRatingPrompt, storeRating, createRatingEntry, readRatingWithTimeout, } from "./core/rating.js";
    14 | import { truncateFiles, deriveCallConfig } from "./core/truncation.js";
    15 | const __dirname = dirname(fileURLToPath(import.meta.url));
    16 | /** Persona pack directory relative to this module. */
    17 | const PERSONAS_DIR = resolve(__dirname, "personas");
    18 | /**
~~~~

The change from head to the fix:

~~~~diff
@@ -6 +6 @@
-import { parseCLIArgs, resolveConfig, resolveRepos, formatEffectiveConfig, loadMultiModelConfig, validateApiKeys, readAgyGate, agyGateStartupLines, loaConfigPathFor, loadTrustedConfig, trustedConfigStartupLine, applyLocality, singleModelLocalityRefusal, } from "./config.js";
+import { parseCLIArgs, resolveConfig, resolveRepos, formatEffectiveConfig, loadMultiModelConfig, validateApiKeys, readAgyGate, agyGateStartupLines, loaConfigPathFor, loadTrustedConfig, trustedConfigStartupLine, applyLocality, singleModelLocalityRefusal, headDriftRefusal, EXIT_TRUSTED_CONFIG_DRIFT, } from "./config.js";
~~~~

## H62 — .claude/skills/bridgebuilder-review/dist/main.js — insertion after head line 390

Head context (head/.claude/skills/bridgebuilder-review/dist/main.js, lines 379–402):

~~~~text
   379 |     console.error(formatEffectiveConfig(config, provenance));
   380 |     // cycle-129 D-7.5 (DEC-0170): provider declarations, locality and the DEGRADED exit key come from TRUSTED configuration
   381 |     // only — the base branch's config (or repository settings) on a pull request, the working tree locally.
   382 |     const trusted = loadTrustedConfig({
   383 |         pr: cliArgs.pr,
   384 |         repoRoot: config.repoRoot,
   385 |         repo: config.repos.length === 1 ? `${config.repos[0].owner}/${config.repos[0].repo}` : undefined,
   386 |     });
   387 |     config.trusted = trusted;
   388 |     console.error(trustedConfigStartupLine(trusted));
   389 |     for (const line of trusted.warnings)
   390 |         console.error(line);
   391 |     // Load persona via 5-level precedence chain
   392 |     const personaResult = await loadPersona(config, {
   393 |         warn: (msg) => console.error(`[bridgebuilder] WARN: ${msg}`),
   394 |     });
   395 |     const persona = personaResult.content;
   396 |     console.error(`[bridgebuilder] Persona: ${personaResult.source}`);
   397 |     // Apply persona model override (V3-2): persona model wins unless CLI --model was explicit
   398 |     if (personaResult.model && provenance.model !== "cli") {
   399 |         config.model = personaResult.model;
   400 |         console.error(`[bridgebuilder] Model override: ${personaResult.model} (from persona:${personaResult.source})`);
   401 |     }
   402 |     // Load multi-model config (Sprint 1: T1.4)
~~~~

The change from head to the fix:

~~~~diff
@@ -390,0 +391,8 @@
+    // audit a257-1 MEDIUM-A2: cheval (every voice's transport) reads the CHECKOUT's configuration, so on a pull request a
+    // head whose providers, aliases, locality or secret allowlist differ from the trusted source's is refused by name
+    // before any voice is planned — exit 5, distinct from 0, 3 (DEGRADED) and 4 (FAILED). Local mode is unchanged.
+    const driftRefusal = headDriftRefusal(trusted);
+    if (driftRefusal !== undefined) {
+        console.error(driftRefusal);
+        process.exit(EXIT_TRUSTED_CONFIG_DRIFT);
+    }
~~~~

## H63 — .claude/skills/bridgebuilder-review/dist/main.js.map — head line 1

Head context (head/.claude/skills/bridgebuilder-review/dist/main.js.map, lines 1–1):

~~~~text
>    1 | {"version":3,"file":"main.js","sourceRoot":"","sources":["../resources/main.ts"],"names":[],"mappings":"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"}
~~~~

The change from head to the fix:

~~~~diff
@@ -1 +1 @@
-{"version":3,"file":"main.js","sourceRoot":"","sources":["../resources/main.ts"],"names":[],"mappings":"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"}
\ No newline at end of file
+{"version":3,"file":"main.js","sourceRoot":"","sources":["../resources/main.ts"],"names":[],"mappings":"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"}
\ No newline at end of file
~~~~

## H64 — .claude/skills/bridgebuilder-review/resources/__tests__/trusted-config.test.ts — head line 13

Head context (head/.claude/skills/bridgebuilder-review/resources/__tests__/trusted-config.test.ts, lines 1–25):

~~~~text
     1 | // cycle-129 Sprint 3 Task 3.4 / 3.5 (SDD D-7.5, D-8.1; DEC-0170): Bridgebuilder reads hounfour.providers, the locality
     2 | // switch and bridgebuilder.exit_on_degraded ONLY from trusted configuration — the base branch's config or repository
     3 | // settings on a pull request, the working tree locally. A keyless or insecure provider only the PR head declares is refused
     4 | // by name; an undeclared provider is still "Unknown provider".
     5 | import { describe, it, mock } from "node:test";
     6 | import assert from "node:assert/strict";
     7 | import { execFileSync } from "node:child_process";
     8 | import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
     9 | import { tmpdir } from "node:os";
    10 | import { join } from "node:path";
    11 | import {
    12 |   applyLocality,
>   13 |   defaultTrustedConfigDeps,
    14 |   headOnlyRefusal,
    15 |   isLocalVoice,
    16 |   isPullRequestContext,
    17 |   isSafeRefName,
    18 |   loadTrustedConfig,
    19 |   localityRefusal,
    20 |   providerKeyEnv,
    21 |   singleModelLocalityRefusal,
    22 |   validateApiKeys,
    23 |   yqTrustedView,
    24 |   type AgyGate,
    25 |   type TrustedConfigDeps,
~~~~

The change from head to the fix:

~~~~diff
@@ -13 +13,8 @@
+  computeHeadDrift,
   defaultTrustedConfigDeps,
+  EXIT_TRUSTED_CONFIG_DRIFT,
+  headDriftRefusal,
+  jsonDeepEqual,
+  LOCAL_FALLBACK_MAX_DEPTH,
+  localVoiceDecision,
+  resolveFallbackSpec,
~~~~

## H65 — .claude/skills/bridgebuilder-review/resources/__tests__/trusted-config.test.ts — insertion after head line 18

Head context (head/.claude/skills/bridgebuilder-review/resources/__tests__/trusted-config.test.ts, lines 7–30):

~~~~text
     7 | import { execFileSync } from "node:child_process";
     8 | import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
     9 | import { tmpdir } from "node:os";
    10 | import { join } from "node:path";
    11 | import {
    12 |   applyLocality,
    13 |   defaultTrustedConfigDeps,
    14 |   headOnlyRefusal,
    15 |   isLocalVoice,
    16 |   isPullRequestContext,
    17 |   isSafeRefName,
    18 |   loadTrustedConfig,
    19 |   localityRefusal,
    20 |   providerKeyEnv,
    21 |   singleModelLocalityRefusal,
    22 |   validateApiKeys,
    23 |   yqTrustedView,
    24 |   type AgyGate,
    25 |   type TrustedConfigDeps,
    26 | } from "../config.js";
    27 | import { ChevalDelegateAdapter } from "../adapters/cheval-delegate.js";
    28 | import { executeMultiModelReview } from "../core/multi-model-pipeline.js";
    29 | import type { BridgebuilderConfig, MultiModelConfig, ReviewItem, TrustedConfig } from "../core/types.js";
    30 | import type { PRReviewTemplate } from "../core/template.js";
~~~~

The change from head to the fix:

~~~~diff
@@ -18,0 +26 @@
+  localEndpointHost,
~~~~

## H66 — .claude/skills/bridgebuilder-review/resources/__tests__/trusted-config.test.ts — insertion after head line 298

Head context (head/.claude/skills/bridgebuilder-review/resources/__tests__/trusted-config.test.ts, lines 287–310):

~~~~text
   287 |     } finally {
   288 |       rmSync(repo, { recursive: true, force: true });
   289 |     }
   290 |   });
   291 | });
   292 | 
   293 | describe("hounfour.locality: local_voices in Bridgebuilder (D-8.1)", () => {
   294 |   const yaml = [
   295 |     "hounfour:",
   296 |     "  locality: local_voices",
   297 |     "  providers:",
   298 |     "    local-vllm:",
   299 |     "      keyless: true",
   300 |     "      models:",
   301 |     "        qwen3-coder:",
   302 |     "          dispatch_group: local",
   303 |     "    lan-box:",
   304 |     "      keyless: true",
   305 |     "      dispatch_group: local",
   306 |     "    openai:",
   307 |     "      models:",
   308 |     "        gpt-5.5:",
   309 |     "          dispatch_group: openai-gpt",
   310 |     "",
~~~~

The change from head to the fix:

~~~~diff
@@ -298,0 +307 @@
+    "      endpoint: \"http://127.0.0.1:8000/v1\"",
~~~~

## H67 — .claude/skills/bridgebuilder-review/resources/__tests__/trusted-config.test.ts — insertion after head line 303

Head context (head/.claude/skills/bridgebuilder-review/resources/__tests__/trusted-config.test.ts, lines 292–315):

~~~~text
   292 | 
   293 | describe("hounfour.locality: local_voices in Bridgebuilder (D-8.1)", () => {
   294 |   const yaml = [
   295 |     "hounfour:",
   296 |     "  locality: local_voices",
   297 |     "  providers:",
   298 |     "    local-vllm:",
   299 |     "      keyless: true",
   300 |     "      models:",
   301 |     "        qwen3-coder:",
   302 |     "          dispatch_group: local",
   303 |     "    lan-box:",
   304 |     "      keyless: true",
   305 |     "      dispatch_group: local",
   306 |     "    openai:",
   307 |     "      models:",
   308 |     "        gpt-5.5:",
   309 |     "          dispatch_group: openai-gpt",
   310 |     "",
   311 |   ].join("\n");
   312 | 
   313 |   it("drops every hosted voice with the named reason and keeps the local ones; never reroutes", () => {
   314 |     const t = loadTrustedConfig({}, fakeDeps({ head: yaml }));
   315 |     assert.equal(t.locality, "local_voices");
~~~~

The change from head to the fix:

~~~~diff
@@ -303,0 +313 @@
+    "      endpoint: \"https://192.168.1.10:8443/v1\"",
~~~~

## H68 — .claude/skills/bridgebuilder-review/resources/__tests__/trusted-config.test.ts — insertion after head line 366

Head context (head/.claude/skills/bridgebuilder-review/resources/__tests__/trusted-config.test.ts, lines 355–378):

~~~~text
   355 | 
   356 |   it("a provider with no dispatch_group is hosted; the single-model voice obeys the switch", () => {
   357 |     const t = loadTrustedConfig({}, fakeDeps({ head: yaml }));
   358 |     assert.equal(isLocalVoice("local-vllm", "qwen3-coder", t), true);
   359 |     assert.equal(isLocalVoice("local-vllm", "unlisted-alias", t), true, "every declared model is local");
   360 |     assert.equal(isLocalVoice("openai", "gpt-5.5", t), false);
   361 |     assert.equal(isLocalVoice("nobody", "x", t), false);
   362 |     assert.equal(singleModelLocalityRefusal("local-vllm:qwen3-coder", t), undefined);
   363 |     assert.match(singleModelLocalityRefusal("opus", t) ?? "", /^locality: local_voices refuses hosted hop opus \(/);
   364 |     const hosted: TrustedConfig = { ...t, locality: "hosted" };
   365 |     assert.equal(singleModelLocalityRefusal("opus", hosted), undefined);
   366 |   });
   367 | });
   368 | 
   369 | describe("the pipeline dispatches a trusted keyless voice with no key (D-7.5)", () => {
   370 |   it("a keyless provider from the trusted config reaches cheval; a head-only one does not", async () => {
   371 |     const repoRoot = mkdtempSync(join(tmpdir(), "bb-keyless-"));
   372 |     const seen: string[] = [];
   373 |     const stub = mock.method(ChevalDelegateAdapter.prototype, "generateReview", async function (this: unknown) {
   374 |       seen.push(String((this as { opts?: { model?: string } }).opts?.model ?? ""));
   375 |       return {
   376 |         content: "<!-- bridge-findings-start -->\n```json\n" + JSON.stringify({ schema_version: 1, findings: [] }) + "\n```\n<!-- bridge-findings-end -->",
   377 |         inputTokens: 1, outputTokens: 1, model: "fixture",
   378 |       };
~~~~

The change from head to the fix:

~~~~diff
@@ -366,0 +377,59 @@
+
+  it("a dispatch_group local voice whose endpoint host is not local (or a CLI provider) is hosted and dropped by name (r257-1)", () => {
+    const mislabelled = yaml + [
+      "    hostedbox:",
+      "      endpoint: \"https://api.acme.example/v1\"",
+      "      models:",
+      "        qwen-hosted:",
+      "          dispatch_group: local",
+      "    metabox:",
+      "      endpoint: \"https://169.254.169.254/v1\"",
+      "      dispatch_group: local",
+      "    noend:",
+      "      models:",
+      "        n1:",
+      "          dispatch_group: local",
+      "    clibox:",
+      "      type: claude-headless",
+      "      models:",
+      "        c1:",
+      "          dispatch_group: local",
+      "",
+    ].join("\n");
+    const t = loadTrustedConfig({}, fakeDeps({ head: mislabelled }));
+    assert.equal(t.providers.hostedbox.endpoint, "https://api.acme.example/v1", "the trusted reader carries the endpoint");
+    const models = mm([
+      { provider: "hostedbox", model_id: "qwen-hosted" },
+      { provider: "metabox", model_id: "m" },
+      { provider: "noend", model_id: "n1" },
+      { provider: "clibox", model_id: "c1" },
+      { provider: "local-vllm", model_id: "qwen3-coder" },
+    ]).models;
+    const r = applyLocality(models, t);
+    assert.deepEqual(r.kept.map((m) => `${m.provider}/${m.model_id}`), ["local-vllm/qwen3-coder"]);
+    assert.deepEqual(r.refused.map((x) => x.reason), [
+      "locality: local_voices refuses hosted hop qwen-hosted (hostedbox): dispatch_group local but endpoint host api.acme.example is not a loopback or RFC1918 IP literal or localhost",
+      "locality: local_voices refuses hosted hop m (metabox): dispatch_group local but endpoint host 169.254.169.254 is not a loopback or RFC1918 IP literal or localhost",
+      "locality: local_voices refuses hosted hop n1 (noend): dispatch_group local but endpoint host (none declared) is not a loopback or RFC1918 IP literal or localhost",
+      "locality: local_voices refuses hosted hop c1 (clibox): dispatch_group local but clibox is a CLI provider",
+    ]);
+    assert.match(singleModelLocalityRefusal("hostedbox:qwen-hosted", t) ?? "", /endpoint host api\.acme\.example is not a loopback/);
+  });
+
+  it("the local-hop host rule matches the cheval validator's ranges (localEndpointHost)", () => {
+    const local = [
+      "http://127.0.0.1:8000/v1", "https://127.9.9.9/v1", "http://[::1]:8000/v1", "https://[0:0:0:0:0:0:0:1]/v1",
+      "http://localhost:11434/v1", "http://LOCALHOST./v1", "https://10.0.0.5/v1", "https://172.16.0.1/v1",
+      "https://172.31.255.255/v1", "https://192.168.1.10:8443/v1",
+    ];
+    for (const e of local) assert.equal(localEndpointHost(e).ok, true, e);
+    const hosted = [
+      "https://api.acme.example/v1", "https://169.254.169.254/v1", "https://169.254.1.1/v1", "http://[fe80::1]/v1",
+      "http://[fd12::1]/v1", "https://203.0.113.5/v1", "https://8.8.8.8/v1", "https://172.32.0.1/v1",
+      "https://0x7f.1/v1", "https://127.000.0.1/v1", "http://[::ffff:127.0.0.1]/v1", "ftp://127.0.0.1/v1",
+      "https://localhost.example/v1", "not a url", "", "http://127.0.0.1:99999/v1",
+    ];
+    for (const e of hosted) assert.equal(localEndpointHost(e).ok, false, e);
+    assert.equal(localEndpointHost(undefined).host, "");
+    assert.equal(localEndpointHost("https://[0:0:0:0:0:0:0:1]:8443/v1").host, "::1");
+  });
~~~~

## H69 — .claude/skills/bridgebuilder-review/resources/__tests__/trusted-config.test.ts — insertion after head line 411

Head context (head/.claude/skills/bridgebuilder-review/resources/__tests__/trusted-config.test.ts, lines 400–411):

~~~~text
   400 |         logger: { info() {}, warn() {}, error() {}, debug() {} },
   401 |       });
   402 |       assert.ok(seen.includes("qwen3-coder"), `dispatched ${JSON.stringify(seen)}`);
   403 |       assert.ok(!seen.includes("x"), "the head-only provider is never dispatched");
   404 |       assert.deepEqual(result.voicesPlanned, ["local-vllm/qwen3-coder", "evil/x"]);
   405 |       assert.equal(result.reviewVerdict.mergeBlocked, true, "a refused planned voice never clears a merge");
   406 |     } finally {
   407 |       stub.mock.restore();
   408 |       rmSync(repoRoot, { recursive: true, force: true });
   409 |     }
   410 |   });
   411 | });
~~~~

The change from head to the fix:

~~~~diff
@@ -411,0 +481,188 @@
+
+// audit a257-1 MEDIUM-A1 (c): under local_voices a local voice whose own fallback_chain reaches a hosted hop is hosted —
+// cheval walks that chain inside one call. The trusted reader carries per-model fallback_chain and the trusted aliases.
+describe("a local voice's fallback_chain under local_voices (audit a257-1 MEDIUM-A1 (c))", () => {
+  const yaml = [
+    "hounfour:",
+    "  locality: local_voices",
+    "  aliases:",
+    "    lb: \"local-vllm:qwen-b\"",
+    "    hosted-alias: \"openai:gpt-5.5\"",
+    "    loop-a: \"loop-b\"",
+    "    loop-b: \"loop-a\"",
+    "  providers:",
+    "    local-vllm:",
+    "      endpoint: \"http://127.0.0.1:8000/v1\"",
+    "      keyless: true",
+    "      models:",
+    "        qwen-a:",
+    "          dispatch_group: local",
+    "          fallback_chain: [\"local-vllm:qwen-b\", \"lb\"]",
+    "        qwen-b:",
+    "          dispatch_group: local",
+    "          fallback_chain: [\"local-vllm:qwen-a\"]",
+    "        qwen-pin:",
+    "          dispatch_group: local",
+    "          fallback_chain: [\"openai:gpt-5.5\"]",
+    "        qwen-alias:",
+    "          dispatch_group: local",
+    "          fallback_chain: [\"hosted-alias\"]",
+    "        qwen-unresolved:",
+    "          dispatch_group: local",
+    "          fallback_chain: [\"loop-a\"]",
+    "        qwen-deep:",
+    "          dispatch_group: local",
+    "          fallback_chain: [\"local-vllm:qwen-pin\"]",
+    "    openai:",
+    "      models:",
+    "        gpt-5.5:",
+    "          dispatch_group: openai-gpt",
+    "",
+  ].join("\n");
+
+  it("the trusted reader carries fallback_chain per model and the trusted aliases", () => {
+    const t = loadTrustedConfig({}, fakeDeps({ head: yaml }));
+    assert.deepEqual(t.providers["local-vllm"].modelFallbacks?.["qwen-a"], ["local-vllm:qwen-b", "lb"]);
+    assert.equal(t.aliases?.lb, "local-vllm:qwen-b");
+  });
+
+  it("a local voice whose fallbacks are local (pin, alias, a cycle back) stays local", () => {
+    const t = loadTrustedConfig({}, fakeDeps({ head: yaml }));
+    assert.deepEqual(localVoiceDecision("local-vllm", "qwen-a", t), { local: true, declared: true });
+    assert.equal(isLocalVoice("local-vllm", "qwen-b", t), true);
+  });
+
+  it("a hosted pin, a hosted alias, an unresolvable entry or a hosted hop deeper on the walk makes the voice hosted, by name", () => {
+    const t = loadTrustedConfig({}, fakeDeps({ head: yaml }));
+    const r = applyLocality(mm([
+      { provider: "local-vllm", model_id: "qwen-pin" },
+      { provider: "local-vllm", model_id: "qwen-alias" },
+      { provider: "local-vllm", model_id: "qwen-unresolved" },
+      { provider: "local-vllm", model_id: "qwen-deep" },
+      { provider: "local-vllm", model_id: "qwen-a" },
+    ]).models, t);
+    assert.deepEqual(r.kept.map((m) => m.model_id), ["qwen-a"]);
+    assert.deepEqual(r.refused.map((x) => x.reason), [
+      "locality: local_voices refuses hosted hop qwen-pin (local-vllm): dispatch_group local but its fallback_chain reaches hosted hop openai:gpt-5.5",
+      "locality: local_voices refuses hosted hop qwen-alias (local-vllm): dispatch_group local but its fallback_chain reaches hosted hop hosted-alias",
+      "locality: local_voices refuses hosted hop qwen-unresolved (local-vllm): dispatch_group local but its fallback_chain reaches hosted hop loop-a",
+      "locality: local_voices refuses hosted hop qwen-deep (local-vllm): dispatch_group local but its fallback_chain reaches hosted hop local-vllm:qwen-pin",
+    ]);
+    assert.equal(resolveFallbackSpec("loop-a", t.aliases), undefined, "an alias cycle does not resolve");
+    assert.deepEqual(resolveFallbackSpec("lb", t.aliases), ["local-vllm", "qwen-b"]);
+  });
+
+  it("the walk is depth-limited", () => {
+    const lines = ["hounfour:", "  locality: local_voices", "  providers:", "    p:", "      endpoint: \"http://127.0.0.1:1/v1\"", "      models:"];
+    for (let i = 0; i <= LOCAL_FALLBACK_MAX_DEPTH + 1; i += 1) {
+      lines.push(`        m${i}:`, "          dispatch_group: local", `          fallback_chain: ["p:m${i + 1}"]`);
+    }
+    lines.push(`        m${LOCAL_FALLBACK_MAX_DEPTH + 2}:`, "          dispatch_group: local", "");
+    const t = loadTrustedConfig({}, fakeDeps({ head: lines.join("\n") }));
+    const d = localVoiceDecision("p", "m0", t);
+    assert.equal(d.local, false);
+    assert.match(d.reason ?? "", /its fallback_chain reaches hosted hop p:m1$/);
+    assert.equal(localVoiceDecision("p", "m3", t).local, true, "a chain within the bound is local");
+  });
+});
+
+// audit a257-1 MEDIUM-A2: cheval reads the checkout's configuration for the dispatch, so on a pull request a head whose
+// providers, aliases, locality or secret allowlist differ from the trusted source's is drift, refused before any voice.
+describe("trusted config drift on a pull request (audit a257-1 MEDIUM-A2)", () => {
+  const base = [
+    "hounfour:",
+    "  secret_env_allowlist:",
+    "    - \"^AZURE_OPENAI_KEY$\"",
+    "  aliases:",
+    "    reviewer: \"azure-openai:gpt-5-azure\"",
+    "  providers:",
+    "    azure-openai:",
+    "      type: openai",
+    "      endpoint: \"https://myorg.openai.azure.com/openai/deployments/gpt-5\"",
+    "      auth: \"{env:AZURE_OPENAI_KEY}\"",
+    "      models:",
+    "        gpt-5-azure:",
+    "          dispatch_group: azure",
+    "bridgebuilder:",
+    "  exit_on_degraded: 3",
+    "",
+  ].join("\n");
+  const pr = (head: string | undefined, env: Record<string, string> = { GITHUB_BASE_REF: "main" }) =>
+    loadTrustedConfig({ pr: 9 }, fakeDeps({ env, head, refs: { "refs/remotes/origin/main": base } }));
+
+  it("an identical head (key order and formatting aside) is no drift, and the run proceeds", () => {
+    const reordered = base.replace("    reviewer: \"azure-openai:gpt-5-azure\"", "    reviewer: azure-openai:gpt-5-azure");
+    for (const head of [base, reordered]) {
+      const t = pr(head);
+      assert.deepEqual(t.headDrift, []);
+      assert.equal(headDriftRefusal(t), undefined);
+    }
+  });
+
+  it("an endpoint re-point is drift on that provider", () => {
+    const t = pr(base.replace("https://myorg.openai.azure.com/openai/deployments/gpt-5", "https://collector.attacker.example/v1"));
+    assert.deepEqual(t.headDrift, ["hounfour.providers.azure-openai"]);
+  });
+
+  it("an auth template re-bound to another variable is drift", () => {
+    const t = pr(base.replace("auth: \"{env:AZURE_OPENAI_KEY}\"", "auth: \"{env:LOA_OTHER_SECRET}\""));
+    assert.deepEqual(t.headDrift, ["hounfour.providers.azure-openai"]);
+  });
+
+  it("an alias re-point is drift on that alias", () => {
+    const t = pr(base.replace("reviewer: \"azure-openai:gpt-5-azure\"", "reviewer: \"evilbox:m\""));
+    assert.deepEqual(t.headDrift, ["hounfour.aliases.reviewer"]);
+  });
+
+  it("an allowlist widening is drift (hounfour's list, and a root-level list)", () => {
+    const widened = base.replace("    - \"^AZURE_OPENAI_KEY$\"", "    - \"^AZURE_OPENAI_KEY$\"\n    - \"^GITHUB_TOKEN$\"");
+    assert.deepEqual(pr(widened).headDrift, ["hounfour.secret_env_allowlist"]);
+    assert.deepEqual(pr(base + "secret_env_allowlist:\n  - \"^AWS_.*$\"\n").headDrift, ["secret_env_allowlist"]);
+  });
+
+  it("a locality change is drift; an explicit hosted equals the absent default", () => {
+    assert.deepEqual(pr(base.replace("hounfour:\n", "hounfour:\n  locality: local_voices\n")).headDrift, ["hounfour.locality"]);
+    assert.deepEqual(pr(base.replace("hounfour:\n", "hounfour:\n  locality: hosted\n")).headDrift, []);
+  });
+
+  it("a head-only provider, a removed provider, an absent head file and an unparsable head are drift", () => {
+    const extra = base.replace("  providers:\n", "  providers:\n    evilbox:\n      endpoint: \"https://x.example/v1\"\n");
+    assert.deepEqual(pr(extra).headDrift, ["hounfour.providers.evilbox"]);
+    assert.deepEqual(pr("hounfour: {}\n").headDrift,
+      ["hounfour.providers.azure-openai", "hounfour.aliases.reviewer", "hounfour.secret_env_allowlist"]);
+    assert.deepEqual(pr(undefined).headDrift,
+      ["hounfour.providers.azure-openai", "hounfour.aliases.reviewer", "hounfour.secret_env_allowlist"]);
+    assert.deepEqual(pr("hounfour: [\n").headDrift, [".loa.config.yaml (unreadable in the PR head)"]);
+  });
+
+  it("the refusal names the keys and the trusted source and says how to clear it; exit 5 is distinct from 0, 3 and 4", () => {
+    const t = pr(base.replace("reviewer: \"azure-openai:gpt-5-azure\"", "reviewer: \"evilbox:m\"")
+      .replace("https://myorg.openai.azure.com/openai/deployments/gpt-5", "https://collector.attacker.example/v1"));
+    assert.equal(headDriftRefusal(t),
+      "[bridgebuilder] trusted config drift refused: hounfour.providers.azure-openai, hounfour.aliases.reviewer differ " +
+      "between the PR head and the trusted config (base-ref refs/remotes/origin/main); merge the base branch into the head " +
+      "or set BRIDGEBUILDER_TRUSTED_CONFIG");
+    assert.equal(EXIT_TRUSTED_CONFIG_DRIFT, 5);
+    assert.ok(![0, 3, 4].includes(EXIT_TRUSTED_CONFIG_DRIFT));
+    const viaSettings = pr("hounfour: {}\n", { GITHUB_BASE_REF: "main", BRIDGEBUILDER_TRUSTED_CONFIG: base });
+    assert.match(headDriftRefusal(viaSettings) ?? "", /the PR head and the trusted config \(BRIDGEBUILDER_TRUSTED_CONFIG\);/);
+    assert.equal(pr(base, { GITHUB_BASE_REF: "main", BRIDGEBUILDER_TRUSTED_CONFIG: base }).headDrift?.length, 0);
+  });
+
+  it("local mode computes no drift and never refuses", () => {
+    const t = loadTrustedConfig({}, fakeDeps({ head: base.replace("reviewer: \"azure-openai:gpt-5-azure\"", "reviewer: \"evilbox:m\"") }));
+    assert.equal(t.mode, "local");
+    assert.deepEqual(t.headDrift, []);
+    assert.equal(headDriftRefusal(t), undefined);
+    assert.equal(headDriftRefusal({ ...t, headDrift: ["hounfour.locality"] }), undefined, "the decision is pull-request only");
+  });
+
+  it("computeHeadDrift is a pure function of the two views", () => {
+    const v = { providers: { a: { endpoint: "https://a.example" } }, locality: null, exit: null };
+    assert.deepEqual(computeHeadDrift(v, { ...v, providers: { a: { endpoint: "https://a.example" } } }), []);
+    assert.deepEqual(computeHeadDrift({ ...v, providers: { a: { endpoint: "https://b.example" } } }, v), ["hounfour.providers.a"]);
+    assert.deepEqual(computeHeadDrift({ ...v, providers: ["not", "a", "map"] }, v), ["hounfour.providers"]);
+    assert.equal(jsonDeepEqual({ x: [1, { y: 2 }] }, { x: [1, { y: 2 }] }), true);
+    assert.equal(jsonDeepEqual({ x: [1, 2] }, { x: [2, 1] }), false);
+  });
+});
~~~~

## H70 — .claude/skills/bridgebuilder-review/resources/config.ts — insertion after head line 4

Head context (head/.claude/skills/bridgebuilder-review/resources/config.ts, lines 1–16):

~~~~text
     1 | import { execFile, execFileSync, execSync } from "node:child_process";
     2 | import { promisify } from "node:util";
     3 | import { readFile } from "node:fs/promises";
     4 | import { closeSync, existsSync, fstatSync, openSync, readFileSync, statSync } from "node:fs";
     5 | import { join } from "node:path";
     6 | import { z } from "zod/v4";
     7 | import type {
     8 |   BridgebuilderConfig,
     9 |   MultiModelConfig,
    10 |   MultiModelProviderEntry,
    11 |   ProviderDecl,
    12 |   TrustedConfig,
    13 |   TrustedConfigSource,
    14 | } from "./core/types.js";
    15 | import { GENERATED_MODEL_REGISTRY } from "./config.generated.js";
    16 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -4,0 +5 @@
+import { isIPv6 } from "node:net";
~~~~

## H71 — .claude/skills/bridgebuilder-review/resources/config.ts — insertion after head line 456

Head context (head/.claude/skills/bridgebuilder-review/resources/config.ts, lines 445–468):

~~~~text
   445 |   return trusted?.providers[provider]?.authEnv;
   446 | }
   447 | 
   448 | /** Default `bridgebuilder.exit_on_degraded` (DEC-0150): exit 3 when the consensus verdict is DEGRADED. */
   449 | export const DEFAULT_EXIT_ON_DEGRADED = 3;
   450 | 
   451 | /** The lenient shape of one provider entry (unknown keys pass through: cheval owns the full schema). */
   452 | const ProviderEntrySchema = z.looseObject({
   453 |   keyless: z.unknown().optional(),
   454 |   auth: z.unknown().optional(),
   455 |   allow_insecure_endpoint: z.unknown().optional(),
   456 |   dispatch_group: z.unknown().optional(),
   457 |   models: z.unknown().optional(),
   458 | });
   459 | 
   460 | const ENV_AUTH_RE = /^\{env:([A-Za-z_][A-Za-z0-9_]*)\}$/;
   461 | 
   462 | /**
   463 |  * Normalise `hounfour.providers` (any JSON) into declarations. A non-mapping value or an entry that is not a mapping is
   464 |  * dropped with a warning — never admitted. D-8.0: `keyless: true` or a literal `auth` (one without `{env:`) is keyless.
   465 |  */
   466 | export function parseProviderDecls(raw: unknown, label: string, warnings: string[]): Record<string, ProviderDecl> {
   467 |   const out: Record<string, ProviderDecl> = {};
   468 |   if (raw === null || raw === undefined) return out;
~~~~

The change from head to the fix:

~~~~diff
@@ -456,0 +458,2 @@
+  endpoint: z.unknown().optional(),
+  type: z.unknown().optional(),
~~~~

## H72 — .claude/skills/bridgebuilder-review/resources/config.ts — insertion after head line 483

Head context (head/.claude/skills/bridgebuilder-review/resources/config.ts, lines 472–495):

~~~~text
   472 |   }
   473 |   for (const [name, entry] of Object.entries(raw as Record<string, unknown>)) {
   474 |     const parsed = ProviderEntrySchema.safeParse(entry);
   475 |     if (!parsed.success) {
   476 |       warnings.push(`[bridgebuilder] ${label}: hounfour.providers.${name} is not a mapping — ignored`);
   477 |       continue;
   478 |     }
   479 |     const e = parsed.data;
   480 |     const auth = typeof e.auth === "string" ? e.auth : undefined;
   481 |     const envMatch = auth !== undefined ? ENV_AUTH_RE.exec(auth) : null;
   482 |     const literalAuth = auth !== undefined && auth !== "" && !auth.includes("{env:");
   483 |     const modelGroups: Record<string, string | undefined> = {};
   484 |     if (e.models !== null && typeof e.models === "object" && !Array.isArray(e.models)) {
   485 |       for (const [mid, m] of Object.entries(e.models as Record<string, unknown>)) {
   486 |         const g = m !== null && typeof m === "object" ? (m as { dispatch_group?: unknown }).dispatch_group : undefined;
   487 |         modelGroups[mid] = typeof g === "string" ? g : undefined;
   488 |       }
   489 |     }
   490 |     out[name] = {
   491 |       keyless: e.keyless === true || literalAuth,
   492 |       insecure: e.allow_insecure_endpoint !== undefined && e.allow_insecure_endpoint !== null && e.allow_insecure_endpoint !== false,
   493 |       ...(envMatch ? { authEnv: envMatch[1] } : {}),
   494 |       ...(typeof e.dispatch_group === "string" ? { dispatchGroup: e.dispatch_group } : {}),
   495 |       modelGroups,
~~~~

The change from head to the fix:

~~~~diff
@@ -483,0 +487,3 @@
+    const modelFallbacks: Record<string, string[]> = {};
+    let modelCount = 0;
+    let cliModels = 0;
~~~~

## H73 — .claude/skills/bridgebuilder-review/resources/config.ts — head lines 488–489

Head context (head/.claude/skills/bridgebuilder-review/resources/config.ts, lines 476–501):

~~~~text
   476 |       warnings.push(`[bridgebuilder] ${label}: hounfour.providers.${name} is not a mapping — ignored`);
   477 |       continue;
   478 |     }
   479 |     const e = parsed.data;
   480 |     const auth = typeof e.auth === "string" ? e.auth : undefined;
   481 |     const envMatch = auth !== undefined ? ENV_AUTH_RE.exec(auth) : null;
   482 |     const literalAuth = auth !== undefined && auth !== "" && !auth.includes("{env:");
   483 |     const modelGroups: Record<string, string | undefined> = {};
   484 |     if (e.models !== null && typeof e.models === "object" && !Array.isArray(e.models)) {
   485 |       for (const [mid, m] of Object.entries(e.models as Record<string, unknown>)) {
   486 |         const g = m !== null && typeof m === "object" ? (m as { dispatch_group?: unknown }).dispatch_group : undefined;
   487 |         modelGroups[mid] = typeof g === "string" ? g : undefined;
>  488 |       }
>  489 |     }
   490 |     out[name] = {
   491 |       keyless: e.keyless === true || literalAuth,
   492 |       insecure: e.allow_insecure_endpoint !== undefined && e.allow_insecure_endpoint !== null && e.allow_insecure_endpoint !== false,
   493 |       ...(envMatch ? { authEnv: envMatch[1] } : {}),
   494 |       ...(typeof e.dispatch_group === "string" ? { dispatchGroup: e.dispatch_group } : {}),
   495 |       modelGroups,
   496 |     };
   497 |   }
   498 |   return out;
   499 | }
   500 | 
   501 | /** The subtree Bridgebuilder reads from a Loa config, as one yq program (the same yq the agy gate uses). */
~~~~

The change from head to the fix:

~~~~diff
@@ -488,2 +494,11 @@
+        modelCount += 1;
+        if (m !== null && typeof m === "object" && (m as { kind?: unknown }).kind === "cli") cliModels += 1;
+        // (audit a257-1 MEDIUM-A1 (c): the chain cheval walks inside one call; a scalar is a one-entry chain, as in
+        // endpoint_policy.validate_local_fallbacks, and a non-string entry is "" — unresolvable, so hosted)
+        const fb = m !== null && typeof m === "object" ? (m as { fallback_chain?: unknown }).fallback_chain : undefined;
+        if (fb !== undefined && fb !== null) {
+          modelFallbacks[mid] = (Array.isArray(fb) ? fb : [fb]).map((x) => (typeof x === "string" ? x : ""));
+        }
       }
     }
+    const cli = (typeof e.type === "string" && e.type.endsWith("-headless")) || (modelCount > 0 && cliModels === modelCount);
~~~~

## H74 — .claude/skills/bridgebuilder-review/resources/config.ts — insertion after head line 495

Head context (head/.claude/skills/bridgebuilder-review/resources/config.ts, lines 484–507):

~~~~text
   484 |     if (e.models !== null && typeof e.models === "object" && !Array.isArray(e.models)) {
   485 |       for (const [mid, m] of Object.entries(e.models as Record<string, unknown>)) {
   486 |         const g = m !== null && typeof m === "object" ? (m as { dispatch_group?: unknown }).dispatch_group : undefined;
   487 |         modelGroups[mid] = typeof g === "string" ? g : undefined;
   488 |       }
   489 |     }
   490 |     out[name] = {
   491 |       keyless: e.keyless === true || literalAuth,
   492 |       insecure: e.allow_insecure_endpoint !== undefined && e.allow_insecure_endpoint !== null && e.allow_insecure_endpoint !== false,
   493 |       ...(envMatch ? { authEnv: envMatch[1] } : {}),
   494 |       ...(typeof e.dispatch_group === "string" ? { dispatchGroup: e.dispatch_group } : {}),
   495 |       modelGroups,
   496 |     };
   497 |   }
   498 |   return out;
   499 | }
   500 | 
   501 | /** The subtree Bridgebuilder reads from a Loa config, as one yq program (the same yq the agy gate uses). */
   502 | const TRUSTED_VIEW_YQ =
   503 |   '{"providers": (.hounfour.providers // null), "locality": (.hounfour.locality // null), "exit": (.bridgebuilder.exit_on_degraded // null)}';
   504 | 
   505 | export interface TrustedView {
   506 |   providers: unknown;
   507 |   locality: unknown;
~~~~

The change from head to the fix:

~~~~diff
@@ -495,0 +511,3 @@
+      ...(typeof e.endpoint === "string" ? { endpoint: e.endpoint } : {}),
+      ...(cli ? { cli: true } : {}),
+      ...(Object.keys(modelFallbacks).length > 0 ? { modelFallbacks } : {}),
~~~~

## H75 — .claude/skills/bridgebuilder-review/resources/config.ts — head line 503

Head context (head/.claude/skills/bridgebuilder-review/resources/config.ts, lines 491–515):

~~~~text
   491 |       keyless: e.keyless === true || literalAuth,
   492 |       insecure: e.allow_insecure_endpoint !== undefined && e.allow_insecure_endpoint !== null && e.allow_insecure_endpoint !== false,
   493 |       ...(envMatch ? { authEnv: envMatch[1] } : {}),
   494 |       ...(typeof e.dispatch_group === "string" ? { dispatchGroup: e.dispatch_group } : {}),
   495 |       modelGroups,
   496 |     };
   497 |   }
   498 |   return out;
   499 | }
   500 | 
   501 | /** The subtree Bridgebuilder reads from a Loa config, as one yq program (the same yq the agy gate uses). */
   502 | const TRUSTED_VIEW_YQ =
>  503 |   '{"providers": (.hounfour.providers // null), "locality": (.hounfour.locality // null), "exit": (.bridgebuilder.exit_on_degraded // null)}';
   504 | 
   505 | export interface TrustedView {
   506 |   providers: unknown;
   507 |   locality: unknown;
   508 |   exit: unknown;
   509 | }
   510 | 
   511 | /** Parse Loa config text (YAML or JSON) into the trusted view with yq; throws with yq's first stderr line on failure. */
   512 | export function yqTrustedView(text: string): TrustedView {
   513 |   try {
   514 |     const out = execFileSync("yq", ["eval", "-o=json", "-I=0", TRUSTED_VIEW_YQ, "-"], {
   515 |       encoding: "utf8", timeout: 5000, input: text, stdio: ["pipe", "pipe", "pipe"],
~~~~

The change from head to the fix:

~~~~diff
@@ -503 +521,2 @@
-  '{"providers": (.hounfour.providers // null), "locality": (.hounfour.locality // null), "exit": (.bridgebuilder.exit_on_degraded // null)}';
+  '{"providers": (.hounfour.providers // null), "locality": (.hounfour.locality // null), "exit": (.bridgebuilder.exit_on_degraded // null), ' +
+  '"aliases": (.hounfour.aliases // null), "allowlist": (.hounfour.secret_env_allowlist // null), "rootAllowlist": (.secret_env_allowlist // null)}';
~~~~

## H76 — .claude/skills/bridgebuilder-review/resources/config.ts — insertion after head line 508

Head context (head/.claude/skills/bridgebuilder-review/resources/config.ts, lines 497–520):

~~~~text
   497 |   }
   498 |   return out;
   499 | }
   500 | 
   501 | /** The subtree Bridgebuilder reads from a Loa config, as one yq program (the same yq the agy gate uses). */
   502 | const TRUSTED_VIEW_YQ =
   503 |   '{"providers": (.hounfour.providers // null), "locality": (.hounfour.locality // null), "exit": (.bridgebuilder.exit_on_degraded // null)}';
   504 | 
   505 | export interface TrustedView {
   506 |   providers: unknown;
   507 |   locality: unknown;
   508 |   exit: unknown;
   509 | }
   510 | 
   511 | /** Parse Loa config text (YAML or JSON) into the trusted view with yq; throws with yq's first stderr line on failure. */
   512 | export function yqTrustedView(text: string): TrustedView {
   513 |   try {
   514 |     const out = execFileSync("yq", ["eval", "-o=json", "-I=0", TRUSTED_VIEW_YQ, "-"], {
   515 |       encoding: "utf8", timeout: 5000, input: text, stdio: ["pipe", "pipe", "pipe"],
   516 |     });
   517 |     const parsed = JSON.parse(out) as Partial<TrustedView> | null;
   518 |     return { providers: parsed?.providers ?? null, locality: parsed?.locality ?? null, exit: parsed?.exit ?? null };
   519 |   } catch (err) {
   520 |     const e = err as { stderr?: unknown; message?: string };
~~~~

The change from head to the fix:

~~~~diff
@@ -508,0 +528,6 @@
+  /** `hounfour.aliases` (audit a257-1: resolves fallback aliases; compared for head drift). */
+  aliases?: unknown;
+  /** `hounfour.secret_env_allowlist` — the list cheval's loader reads (compared for head drift). */
+  allowlist?: unknown;
+  /** A root-level `secret_env_allowlist` (compared for head drift too: it is the shape the docs once showed). */
+  rootAllowlist?: unknown;
~~~~

## H77 — .claude/skills/bridgebuilder-review/resources/config.ts — head line 518

Head context (head/.claude/skills/bridgebuilder-review/resources/config.ts, lines 506–530):

~~~~text
   506 |   providers: unknown;
   507 |   locality: unknown;
   508 |   exit: unknown;
   509 | }
   510 | 
   511 | /** Parse Loa config text (YAML or JSON) into the trusted view with yq; throws with yq's first stderr line on failure. */
   512 | export function yqTrustedView(text: string): TrustedView {
   513 |   try {
   514 |     const out = execFileSync("yq", ["eval", "-o=json", "-I=0", TRUSTED_VIEW_YQ, "-"], {
   515 |       encoding: "utf8", timeout: 5000, input: text, stdio: ["pipe", "pipe", "pipe"],
   516 |     });
   517 |     const parsed = JSON.parse(out) as Partial<TrustedView> | null;
>  518 |     return { providers: parsed?.providers ?? null, locality: parsed?.locality ?? null, exit: parsed?.exit ?? null };
   519 |   } catch (err) {
   520 |     const e = err as { stderr?: unknown; message?: string };
   521 |     const stderr = typeof e.stderr === "string" ? e.stderr.trim() : "";
   522 |     throw new Error((stderr || e.message || String(err)).split("\n")[0].slice(0, 300));
   523 |   }
   524 | }
   525 | 
   526 | /** A branch name safe to place in `refs/remotes/origin/<name>` for `git show` (no option, no `..`, no control chars). */
   527 | export function isSafeRefName(name: string): boolean {
   528 |   return /^[A-Za-z0-9][A-Za-z0-9._/-]{0,199}$/.test(name) && !name.includes("..") && !name.endsWith(".lock") && !name.endsWith("/");
   529 | }
   530 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -518 +543,4 @@
-    return { providers: parsed?.providers ?? null, locality: parsed?.locality ?? null, exit: parsed?.exit ?? null };
+    return {
+      providers: parsed?.providers ?? null, locality: parsed?.locality ?? null, exit: parsed?.exit ?? null,
+      aliases: parsed?.aliases ?? null, allowlist: parsed?.allowlist ?? null, rootAllowlist: parsed?.rootAllowlist ?? null,
+    };
~~~~

## H78 — .claude/skills/bridgebuilder-review/resources/config.ts — head lines 602–603

Head context (head/.claude/skills/bridgebuilder-review/resources/config.ts, lines 590–615):

~~~~text
   590 |   return (env.GITHUB_BASE_REF ?? "") !== "";
   591 | }
   592 | 
   593 | /** The env var a workflow sets from a repository variable to supply trusted config text (YAML or JSON). */
   594 | export const TRUSTED_CONFIG_ENV = "BRIDGEBUILDER_TRUSTED_CONFIG";
   595 | 
   596 | /**
   597 |  * Load the trusted configuration (D-7.5, DEC-0170). Precedence:
   598 |  *   local (no PR context):  the working tree's `.loa.config.yaml`.
   599 |  *   pull request:           `BRIDGEBUILDER_TRUSTED_CONFIG` (repository settings) when set, else `.loa.config.yaml` at
   600 |  *                           `refs/remotes/origin/<base>` (base from `GITHUB_BASE_REF`, else the PR metadata), else at
   601 |  *                           `refs/remotes/origin/main`; when none can be read, no provider declaration is trusted.
>  602 |  * The head checkout is read on a pull request only to find keyless / insecure declarations the trusted source lacks,
>  603 |  * which are refused by name. Throws on an invalid `hounfour.locality` (a posture typo never runs hosted silently).
   604 |  */
   605 | export function loadTrustedConfig(
   606 |   opts: { pr?: number; repoRoot?: string; repo?: string },
   607 |   deps: TrustedConfigDeps = defaultTrustedConfigDeps,
   608 | ): TrustedConfig {
   609 |   const warnings: string[] = [];
   610 |   const mode: TrustedConfig["mode"] = isPullRequestContext(opts.pr, deps.env) ? "pull-request" : "local";
   611 |   const wtPath = loaConfigPathFor(opts.repoRoot);
   612 |   let source: TrustedConfigSource = "none";
   613 |   let ref: string | undefined;
   614 |   let text: string | undefined;
   615 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -602,2 +630,3 @@
- * The head checkout is read on a pull request only to find keyless / insecure declarations the trusted source lacks,
- * which are refused by name. Throws on an invalid `hounfour.locality` (a posture typo never runs hosted silently).
+ * The head checkout is read on a pull request to find keyless / insecure declarations the trusted source lacks, which
+ * are refused by name, and (audit a257-1 MEDIUM-A2) to compute `headDrift` — the keys cheval would read differently from
+ * the checkout than the trusted source says; main.ts refuses the run on any. Throws on an invalid `hounfour.locality` (a posture typo never runs hosted silently).
~~~~

## H79 — .claude/skills/bridgebuilder-review/resources/config.ts — head lines 671–674

Head context (head/.claude/skills/bridgebuilder-review/resources/config.ts, lines 659–686):

~~~~text
   659 |   if (text !== undefined) {
   660 |     try {
   661 |       view = deps.parse(text);
   662 |     } catch (err) {
   663 |       warnings.push(`[bridgebuilder] trusted config (${source}${ref ? ` ${ref}` : ""}) unreadable: ${err instanceof Error ? err.message : String(err)} — no provider declaration is trusted`);
   664 |       source = "none";
   665 |     }
   666 |   }
   667 |   const providers = parseProviderDecls(view.providers, `trusted config (${source})`, warnings);
   668 | 
   669 |   // Head-only refusal: on a PR the head checkout is attacker-controlled.
   670 |   const headOnlyRefused: string[] = [];
>  671 |   if (mode === "pull-request") {
>  672 |     const headText = deps.readWorkingTree(wtPath);
>  673 |     if (headText !== undefined) {
>  674 |       let headView: TrustedView | undefined;
   675 |       try {
   676 |         headView = deps.parse(headText);
   677 |       } catch {
   678 |         headView = undefined;   // (an unparsable head declares nothing Bridgebuilder would admit)
   679 |       }
   680 |       const headWarnings: string[] = [];
   681 |       const head = headView ? parseProviderDecls(headView.providers, "head config", headWarnings) : {};
   682 |       for (const [name, decl] of Object.entries(head)) {
   683 |         const t = Object.hasOwn(providers, name) ? providers[name] : undefined;
   684 |         const keylessOnlyInHead = decl.keyless && t?.keyless !== true;
   685 |         const insecureOnlyInHead = decl.insecure && t?.insecure !== true;
   686 |         if (keylessOnlyInHead || insecureOnlyInHead) {
~~~~

The change from head to the fix:

~~~~diff
@@ -671,4 +700,6 @@
+  let headDrift: string[] = [];
   if (mode === "pull-request") {
     const headText = deps.readWorkingTree(wtPath);
+    let headView: TrustedView | undefined;
+    let headUnreadable = false;
     if (headText !== undefined) {
-      let headView: TrustedView | undefined;
~~~~

## H80 — .claude/skills/bridgebuilder-review/resources/config.ts — head line 679

Head context (head/.claude/skills/bridgebuilder-review/resources/config.ts, lines 667–691):

~~~~text
   667 |   const providers = parseProviderDecls(view.providers, `trusted config (${source})`, warnings);
   668 | 
   669 |   // Head-only refusal: on a PR the head checkout is attacker-controlled.
   670 |   const headOnlyRefused: string[] = [];
   671 |   if (mode === "pull-request") {
   672 |     const headText = deps.readWorkingTree(wtPath);
   673 |     if (headText !== undefined) {
   674 |       let headView: TrustedView | undefined;
   675 |       try {
   676 |         headView = deps.parse(headText);
   677 |       } catch {
   678 |         headView = undefined;   // (an unparsable head declares nothing Bridgebuilder would admit)
>  679 |       }
   680 |       const headWarnings: string[] = [];
   681 |       const head = headView ? parseProviderDecls(headView.providers, "head config", headWarnings) : {};
   682 |       for (const [name, decl] of Object.entries(head)) {
   683 |         const t = Object.hasOwn(providers, name) ? providers[name] : undefined;
   684 |         const keylessOnlyInHead = decl.keyless && t?.keyless !== true;
   685 |         const insecureOnlyInHead = decl.insecure && t?.insecure !== true;
   686 |         if (keylessOnlyInHead || insecureOnlyInHead) {
   687 |           headOnlyRefused.push(name);
   688 |           warnings.push(`[bridgebuilder] ${headOnlyRefusal(name)} (${[keylessOnlyInHead ? "keyless" : "", insecureOnlyInHead ? "allow_insecure_endpoint" : ""].filter(Boolean).join(", ")} is declared in the PR head, not in the trusted config)`);
   689 |         }
   690 |       }
   691 |     }
~~~~

The change from head to the fix:

~~~~diff
@@ -679 +710,7 @@
+        headUnreadable = true;
       }
+    }
+    // audit a257-1 MEDIUM-A2: cheval reads the CHECKOUT's configuration for the dispatch, so on a pull request every
+    // difference in what it would read (providers, aliases, locality, the secret allowlist) is drift, refused by name.
+    headDrift = computeHeadDrift(headView, view, headUnreadable);
+    if (headText !== undefined) {
~~~~

## H81 — .claude/skills/bridgebuilder-review/resources/config.ts — head line 711

Head context (head/.claude/skills/bridgebuilder-review/resources/config.ts, lines 699–723):

~~~~text
   699 |   }
   700 | 
   701 |   // bridgebuilder.exit_on_degraded
   702 |   let exitOnDegraded = DEFAULT_EXIT_ON_DEGRADED;
   703 |   if (view.exit !== null && view.exit !== undefined) {
   704 |     if (typeof view.exit === "number" && Number.isInteger(view.exit) && view.exit >= 0 && view.exit <= 125) {
   705 |       exitOnDegraded = view.exit;
   706 |     } else {
   707 |       warnings.push(`[bridgebuilder] bridgebuilder.exit_on_degraded: invalid value ${JSON.stringify(view.exit)} (expected an integer 0..125) — using ${DEFAULT_EXIT_ON_DEGRADED}`);
   708 |     }
   709 |   }
   710 | 
>  711 |   return { mode, source, ...(ref ? { ref } : {}), providers, headOnlyRefused, locality, exitOnDegraded, warnings };
   712 | }
   713 | 
   714 | /** One startup line naming where the trusted config was read from (main.ts prints it with the warnings). */
   715 | export function trustedConfigStartupLine(t: TrustedConfig): string {
   716 |   const where = t.source === "base-ref" ? `base-ref ${t.ref}` : t.source;
   717 |   const keyless = Object.entries(t.providers).filter(([, d]) => d.keyless).map(([n]) => n);
   718 |   return `[bridgebuilder] Trusted config: ${where} (mode: ${t.mode}); locality: ${t.locality}; exit_on_degraded: ${t.exitOnDegraded}` +
   719 |     (keyless.length > 0 ? `; keyless providers: ${keyless.join(", ")}` : "");
   720 | }
   721 | 
   722 | /**
   723 |  * True when the trusted config marks this voice's provider `dispatch_group: local` (D-8.0): the model's own entry when
~~~~

The change from head to the fix:

~~~~diff
@@ -711 +748,96 @@
-  return { mode, source, ...(ref ? { ref } : {}), providers, headOnlyRefused, locality, exitOnDegraded, warnings };
+  return {
+    mode, source, ...(ref ? { ref } : {}), providers, headOnlyRefused, locality, exitOnDegraded, warnings,
+    aliases: stringAliases(view.aliases), headDrift,
+  };
+}
+
+/** `hounfour.aliases` as a string map (non-string targets — cheval's dict form included — read through `target`/`model`). */
+function stringAliases(raw: unknown): Record<string, string> {
+  const out: Record<string, string> = {};
+  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) return out;
+  for (const [k, v] of Object.entries(raw as Record<string, unknown>)) {
+    let t: unknown = v;
+    if (t !== null && typeof t === "object" && !Array.isArray(t)) t = (t as { target?: unknown; model?: unknown }).target ?? (t as { model?: unknown }).model;
+    if (typeof t === "string" && t.trim() !== "") out[k] = t.trim();
+  }
+  return out;
+}
+
+/** Key-order-independent structural equality over JSON values (the yq view is JSON). */
+export function jsonDeepEqual(a: unknown, b: unknown): boolean {
+  if (a === b) return true;
+  if (a === null || b === null || typeof a !== "object" || typeof b !== "object") return false;
+  if (Array.isArray(a) !== Array.isArray(b)) return false;
+  if (Array.isArray(a)) {
+    const bb = b as unknown[];
+    return a.length === bb.length && a.every((x, i) => jsonDeepEqual(x, bb[i]));
+  }
+  const ka = Object.keys(a as object);
+  const kb = Object.keys(b as object);
+  if (ka.length !== kb.length) return false;
+  return ka.every((k) => Object.hasOwn(b as object, k) && jsonDeepEqual((a as Record<string, unknown>)[k], (b as Record<string, unknown>)[k]));
+}
+
+/** One dotted-key segment for a refusal line: a plain name as-is, anything else JSON-quoted and bounded (head text). */
+function driftSegment(name: string): string {
+  return /^[A-Za-z0-9_.@+-]{1,64}$/.test(name) ? name : JSON.stringify(name.slice(0, 64));
+}
+
+/** The per-entry differences of two mappings (absent ⇒ `{}`); a non-mapping on either side is the whole key. */
+function mappingDrift(prefix: string, head: unknown, trusted: unknown, out: string[]): void {
+  const h = head ?? {};
+  const t = trusted ?? {};
+  const isMap = (x: unknown) => x !== null && typeof x === "object" && !Array.isArray(x);
+  if (!isMap(h) || !isMap(t)) {
+    if (!jsonDeepEqual(h, t)) out.push(prefix);
+    return;
+  }
+  const hm = h as Record<string, unknown>;
+  const tm = t as Record<string, unknown>;
+  const names = [...new Set([...Object.keys(hm), ...Object.keys(tm)])].sort();
+  for (const n of names) {
+    const inH = Object.hasOwn(hm, n);
+    const inT = Object.hasOwn(tm, n);
+    if (!inH || !inT || !jsonDeepEqual(hm[n], tm[n])) out.push(`${prefix}.${driftSegment(n)}`);
+  }
+}
+
+/**
+ * audit a257-1 MEDIUM-A2 (pure): the dotted keys that differ between the PR head's view and the trusted view —
+ * `hounfour.providers.<name>` (every field: endpoint, auth template, models, opt-ins), `hounfour.aliases.<alias>`,
+ * `hounfour.locality` (absent ⇒ `hosted`), `hounfour.secret_env_allowlist` and a root `secret_env_allowlist` (absent ⇒
+ * `[]`). An absent head file reads as all defaults; an unparsable head is drift on `.loa.config.yaml` itself (fail
+ * closed: cheval's YAML reader might accept what yq refused).
+ */
+export function computeHeadDrift(head: TrustedView | undefined, trusted: TrustedView, headUnreadable = false): string[] {
+  if (headUnreadable) return [".loa.config.yaml (unreadable in the PR head)"];
+  const h: Partial<TrustedView> = head ?? {};
+  const out: string[] = [];
+  mappingDrift("hounfour.providers", h.providers, trusted.providers, out);
+  mappingDrift("hounfour.aliases", h.aliases, trusted.aliases, out);
+  if (!jsonDeepEqual(h.locality ?? "hosted", trusted.locality ?? "hosted")) out.push("hounfour.locality");
+  if (!jsonDeepEqual(h.allowlist ?? [], trusted.allowlist ?? [])) out.push("hounfour.secret_env_allowlist");
+  if (!jsonDeepEqual(h.rootAllowlist ?? [], trusted.rootAllowlist ?? [])) out.push("secret_env_allowlist");
+  return out;
+}
+
+/** Where the trusted config came from, in words, for the drift refusal. */
+export function trustedSourceDescription(t: TrustedConfig): string {
+  if (t.source === "base-ref") return `the trusted config (base-ref ${t.ref ?? "unknown"})`;
+  if (t.source === "repository-settings") return `the trusted config (${TRUSTED_CONFIG_ENV})`;
+  if (t.source === "none") return "the trusted config (none could be read)";
+  return `the trusted config (${t.source})`;
+}
+
+/** Exit code for a multi-model run refused by trusted-config drift (distinct from 0, 3 DEGRADED and 4 FAILED). */
+export const EXIT_TRUSTED_CONFIG_DRIFT = 5;
+
+/**
+ * The refusal decision for the multi-model run (pure; main.ts prints and exits): the stderr line, or undefined when the
+ * run may proceed (local mode, or no drift).
+ */
+export function headDriftRefusal(t: TrustedConfig): string | undefined {
+  const drift = t.mode === "pull-request" ? (t.headDrift ?? []) : [];
+  if (drift.length === 0) return undefined;
+  return `[bridgebuilder] trusted config drift refused: ${drift.join(", ")} differ between the PR head and ` +
+    `${trustedSourceDescription(t)}; merge the base branch into the head or set ${TRUSTED_CONFIG_ENV}`;
~~~~

## H82 — .claude/skills/bridgebuilder-review/resources/config.ts — head lines 722–732

Head context (head/.claude/skills/bridgebuilder-review/resources/config.ts, lines 710–744):

~~~~text
   710 | 
   711 |   return { mode, source, ...(ref ? { ref } : {}), providers, headOnlyRefused, locality, exitOnDegraded, warnings };
   712 | }
   713 | 
   714 | /** One startup line naming where the trusted config was read from (main.ts prints it with the warnings). */
   715 | export function trustedConfigStartupLine(t: TrustedConfig): string {
   716 |   const where = t.source === "base-ref" ? `base-ref ${t.ref}` : t.source;
   717 |   const keyless = Object.entries(t.providers).filter(([, d]) => d.keyless).map(([n]) => n);
   718 |   return `[bridgebuilder] Trusted config: ${where} (mode: ${t.mode}); locality: ${t.locality}; exit_on_degraded: ${t.exitOnDegraded}` +
   719 |     (keyless.length > 0 ? `; keyless providers: ${keyless.join(", ")}` : "");
   720 | }
   721 | 
>  722 | /**
>  723 |  * True when the trusted config marks this voice's provider `dispatch_group: local` (D-8.0): the model's own entry when
>  724 |  * declared, else the provider-level key, else every declared model of the provider. Anything undeclared is hosted.
>  725 |  */
>  726 | export function isLocalVoice(provider: string, modelId: string, trusted: TrustedConfig): boolean {
>  727 |   const decl = Object.hasOwn(trusted.providers, provider) ? trusted.providers[provider] : undefined;
>  728 |   if (!decl) return false;
>  729 |   if (Object.hasOwn(decl.modelGroups, modelId) && decl.modelGroups[modelId] !== undefined) return decl.modelGroups[modelId] === "local";
>  730 |   if (decl.dispatchGroup !== undefined) return decl.dispatchGroup === "local";
>  731 |   const groups = Object.values(decl.modelGroups);
>  732 |   return groups.length > 0 && groups.every((g) => g === "local");
   733 | }
   734 | 
   735 | /**
   736 |  * D-8.1: under `hounfour.locality: local_voices` drop every planned voice whose provider is not local, each with the named
   737 |  * reason; never reroute. `hosted` (the default) returns the list unchanged.
   738 |  */
   739 | export function applyLocality(
   740 |   models: MultiModelProviderEntry[],
   741 |   trusted: TrustedConfig,
   742 | ): { kept: MultiModelProviderEntry[]; refused: Array<{ provider: string; modelId: string; reason: string }> } {
   743 |   if (trusted.locality !== "local_voices") return { kept: models, refused: [] };
   744 |   const kept: MultiModelProviderEntry[] = [];
~~~~

The change from head to the fix:

~~~~diff
@@ -722,11 +854,144 @@
+/** The local-hop rule's wording, shared with cheval (endpoint_policy.LOCAL_RULE_TEXT) and the planner. */
+export const LOCAL_RULE_TEXT = "a loopback or RFC1918 IP literal or localhost";
+
+function ipv4Octets(host: string): number[] | undefined {
+  const m = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(host);
+  if (!m) return undefined;
+  const parts = m.slice(1).map((s) => (s.length > 1 && s.startsWith("0") ? NaN : Number(s)));  // no leading zeros, as Python ipaddress
+  return parts.every((n) => Number.isInteger(n) && n >= 0 && n <= 255) ? parts : undefined;
+}
+
 /**
- * True when the trusted config marks this voice's provider `dispatch_group: local` (D-8.0): the model's own entry when
- * declared, else the provider-level key, else every declared model of the provider. Anything undeclared is hosted.
+ * The local-hop rule (D-8.1, review round r257-1) on a provider endpoint: `ok` when it is an http(s) URL whose host is an
+ * IP literal in a loopback (127.0.0.0/8, ::1) or RFC1918 (10/8, 172.16/12, 192.168/16) range, or the literal `localhost`.
+ * Link-local, metadata, unique-local IPv6, public ranges and every other DNS name fail. A stdlib mirror of the canonical
+ * validator's `check_insecure_optin` host acceptance (the generated TypeScript port does not export it): the authority is
+ * split by hand, not by WHATWG `URL`, so a host such as `0x7f.1` stays a DNS name here exactly as it does in Python.
+ * `host` is the canonical host for a refusal message ("" when there is no endpoint).
  */
-export function isLocalVoice(provider: string, modelId: string, trusted: TrustedConfig): boolean {
+export function localEndpointHost(endpoint: unknown): { ok: boolean; host: string } {
+  if (typeof endpoint !== "string" || endpoint.trim() === "") return { ok: false, host: "" };
+  const m = /^([A-Za-z][A-Za-z0-9+.-]*):\/\/([^/?#]*)/.exec(endpoint.trim());
+  if (!m) return { ok: false, host: "unparseable" };
+  const scheme = m[1].toLowerCase();
+  let authority = m[2];
+  const at = authority.lastIndexOf("@");
+  if (at >= 0) authority = authority.slice(at + 1);
+  let host: string;
+  let port: string;
+  if (authority.startsWith("[")) {
+    const close = authority.indexOf("]");
+    if (close < 0) return { ok: false, host: "unparseable" };
+    host = authority.slice(1, close);
+    port = authority.slice(close + 1);
+  } else {
+    const colon = authority.indexOf(":");
+    host = colon >= 0 ? authority.slice(0, colon) : authority;
+    port = colon >= 0 ? authority.slice(colon) : "";
+  }
+  if (port !== "" && !/^:\d*$/.test(port)) return { ok: false, host: "unparseable" };
+  if (port.length > 1 && Number(port.slice(1)) > 65535) return { ok: false, host: "unparseable" };
+  host = host.toLowerCase();
+  if (host.endsWith(".") && !host.endsWith("..")) host = host.slice(0, -1);
+  if (host === "") return { ok: false, host: "unparseable" };
+  if (scheme !== "http" && scheme !== "https") return { ok: false, host };
+  if (host === "localhost") return { ok: true, host };
+  const v4 = ipv4Octets(host);
+  if (v4) {
+    const [a, b] = v4;
+    const ok = a === 127 || a === 10 || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168);
+    return { ok, host: v4.join(".") };
+  }
+  if (isIPv6(host)) {
+    let canonical = host;
+    try {
+      canonical = new URL(`http://[${host}]/`).hostname.replace(/^\[|\]$/g, "");
+    } catch {
+      return { ok: false, host };
+    }
+    return { ok: canonical === "::1", host: canonical };
+  }
+  return { ok: false, host };
+}
+
+/**
+ * The locality decision for one voice. `declared`: the trusted config marks it `dispatch_group: local` (the model's own
+ * entry when declared, else the provider-level key, else every declared model of the provider). `local`: declared AND
+ * the provider honours it — not a CLI provider, and its endpoint host passes the local-hop rule (D-8.1, r257-1: a
+ * declared locality is enforced, not trusted). `reason` names why a declared voice is still hosted.
+ */
+export function localVoiceDecision(
+  provider: string,
+  modelId: string,
+  trusted: TrustedConfig,
+): { local: boolean; declared: boolean; reason?: string } {
+  return localVoiceDecisionAt(provider, modelId, trusted, 0, new Set<string>());
+}
+
+/** The fallback walk's depth bound (audit a257-1 MEDIUM-A1 (c); endpoint_policy.LOCAL_FALLBACK_MAX_DEPTH). */
+export const LOCAL_FALLBACK_MAX_DEPTH = 8;
+
+/**
+ * A `fallback_chain` entry as `[provider, model]`: a `provider:model` pin, or an alias followed through the TRUSTED
+ * `hounfour.aliases` (depth-limited, cycle-safe). Undefined when it does not resolve — the caller treats that as hosted.
+ */
+export function resolveFallbackSpec(spec: string, aliases: Record<string, string> | undefined): [string, string] | undefined {
+  let current = spec.trim();
+  const seen = new Set<string>();
+  for (let i = 0; i <= LOCAL_FALLBACK_MAX_DEPTH; i += 1) {
+    if (current === "") return undefined;
+    const colon = current.indexOf(":");
+    if (colon >= 0) {
+      const p = current.slice(0, colon);
+      const m = current.slice(colon + 1);
+      return p !== "" && m !== "" ? [p, m] : undefined;
+    }
+    if (seen.has(current)) return undefined;
+    seen.add(current);
+    current = aliases && Object.hasOwn(aliases, current) ? aliases[current] : "";
+  }
+  return undefined;
+}
+
+function localVoiceDecisionAt(
+  provider: string,
+  modelId: string,
+  trusted: TrustedConfig,
+  depth: number,
+  seen: Set<string>,
+): { local: boolean; declared: boolean; reason?: string } {
   const decl = Object.hasOwn(trusted.providers, provider) ? trusted.providers[provider] : undefined;
-  if (!decl) return false;
-  if (Object.hasOwn(decl.modelGroups, modelId) && decl.modelGroups[modelId] !== undefined) return decl.modelGroups[modelId] === "local";
-  if (decl.dispatchGroup !== undefined) return decl.dispatchGroup === "local";
-  const groups = Object.values(decl.modelGroups);
-  return groups.length > 0 && groups.every((g) => g === "local");
+  if (!decl) return { local: false, declared: false };
+  let declared: boolean;
+  if (Object.hasOwn(decl.modelGroups, modelId) && decl.modelGroups[modelId] !== undefined) declared = decl.modelGroups[modelId] === "local";
+  else if (decl.dispatchGroup !== undefined) declared = decl.dispatchGroup === "local";
+  else {
+    const groups = Object.values(decl.modelGroups);
+    declared = groups.length > 0 && groups.every((g) => g === "local");
+  }
+  if (!declared) return { local: false, declared: false };
+  const head = `locality: local_voices refuses hosted hop ${modelId} (${provider}): dispatch_group local but`;
+  if (decl.cli === true) return { local: false, declared: true, reason: `${head} ${provider} is a CLI provider` };
+  const verdict = localEndpointHost(decl.endpoint);
+  if (!verdict.ok) {
+    return { local: false, declared: true, reason: `${head} endpoint host ${verdict.host || "(none declared)"} is not ${LOCAL_RULE_TEXT}` };
+  }
+  // audit a257-1 MEDIUM-A1 (c): cheval walks the model's own fallback_chain inside one call, so the voice is local only
+  // when every entry is (by this same rule, recursively; depth-limited, a cycle back to a voice on the walk is not new).
+  const key = `${provider}:${modelId}`;
+  if (seen.has(key)) return { local: true, declared: true };
+  seen.add(key);
+  const chain = decl.modelFallbacks && Object.hasOwn(decl.modelFallbacks, modelId) ? decl.modelFallbacks[modelId] : [];
+  for (const entry of chain) {
+    const hosted = { local: false, declared: true, reason: `${head} its fallback_chain reaches hosted hop ${entry || "(unreadable entry)"}` };
+    if (depth >= LOCAL_FALLBACK_MAX_DEPTH) return hosted;
+    const target = resolveFallbackSpec(entry, trusted.aliases);
+    if (target === undefined) return hosted;
+    if (!localVoiceDecisionAt(target[0], target[1], trusted, depth + 1, seen).local) return hosted;
+  }
+  return { local: true, declared: true };
+}
+
+/** True when the voice is local by `localVoiceDecision` (declared `dispatch_group: local` AND the endpoint honours it). */
+export function isLocalVoice(provider: string, modelId: string, trusted: TrustedConfig): boolean {
+  return localVoiceDecision(provider, modelId, trusted).local;
~~~~

## H83 — .claude/skills/bridgebuilder-review/resources/config.ts — head lines 747–748

Head context (head/.claude/skills/bridgebuilder-review/resources/config.ts, lines 735–760):

~~~~text
   735 | /**
   736 |  * D-8.1: under `hounfour.locality: local_voices` drop every planned voice whose provider is not local, each with the named
   737 |  * reason; never reroute. `hosted` (the default) returns the list unchanged.
   738 |  */
   739 | export function applyLocality(
   740 |   models: MultiModelProviderEntry[],
   741 |   trusted: TrustedConfig,
   742 | ): { kept: MultiModelProviderEntry[]; refused: Array<{ provider: string; modelId: string; reason: string }> } {
   743 |   if (trusted.locality !== "local_voices") return { kept: models, refused: [] };
   744 |   const kept: MultiModelProviderEntry[] = [];
   745 |   const refused: Array<{ provider: string; modelId: string; reason: string }> = [];
   746 |   for (const m of models) {
>  747 |     if (isLocalVoice(m.provider, m.model_id, trusted)) kept.push(m);
>  748 |     else refused.push({ provider: m.provider, modelId: m.model_id, reason: localityRefusal(m.model_id, m.provider) });
   749 |   }
   750 |   return { kept, refused };
   751 | }
   752 | 
   753 | /**
   754 |  * The provider of a single-model `model` value for the locality check: `provider:model`, a generated-registry id, or a
   755 |  * model the trusted config declares; undefined when none says.
   756 |  */
   757 | export function resolveModelProvider(model: string, trusted: TrustedConfig): string | undefined {
   758 |   const colon = model.indexOf(":");
   759 |   if (colon > 0) return model.slice(0, colon);
   760 |   if (Object.hasOwn(GENERATED_MODEL_REGISTRY, model)) return GENERATED_MODEL_REGISTRY[model].provider;
~~~~

The change from head to the fix:

~~~~diff
@@ -747,2 +1012,3 @@
-    if (isLocalVoice(m.provider, m.model_id, trusted)) kept.push(m);
-    else refused.push({ provider: m.provider, modelId: m.model_id, reason: localityRefusal(m.model_id, m.provider) });
+    const d = localVoiceDecision(m.provider, m.model_id, trusted);
+    if (d.local) kept.push(m);
+    else refused.push({ provider: m.provider, modelId: m.model_id, reason: d.reason ?? localityRefusal(m.model_id, m.provider) });
~~~~

## H84 — .claude/skills/bridgebuilder-review/resources/config.ts — head lines 775–776

Head context (head/.claude/skills/bridgebuilder-review/resources/config.ts, lines 763–788):

~~~~text
   763 |   }
   764 |   return undefined;
   765 | }
   766 | 
   767 | /**
   768 |  * Under `local_voices`, the single-model path's voice must be local too: returns the refusal text, or undefined when the
   769 |  * voice may run (or the posture is hosted).
   770 |  */
   771 | export function singleModelLocalityRefusal(model: string, trusted: TrustedConfig): string | undefined {
   772 |   if (trusted.locality !== "local_voices") return undefined;
   773 |   const provider = resolveModelProvider(model, trusted);
   774 |   const bare = provider !== undefined && model.startsWith(`${provider}:`) ? model.slice(provider.length + 1) : model;
>  775 |   if (provider !== undefined && isLocalVoice(provider, bare, trusted)) return undefined;
>  776 |   return localityRefusal(model, provider ?? "unresolved provider");
   777 | }
   778 | 
   779 | /**
   780 |  * The startup lines for the agy gate (r251-2 K7f): the read error and the type warning each said once, unconditionally —
   781 |  * not only when a voice is not planned — and the not-planned voices. main.ts prints them; the pipeline says its own once
   782 |  * per review.
   783 |  */
   784 | export function agyGateStartupLines(gate: AgyGate, keyStatus: ReturnType<typeof validateApiKeys>): string[] {
   785 |   const lines: string[] = [];
   786 |   if (gate.readError !== undefined) {
   787 |     lines.push(`[bridgebuilder] agy gate: Loa config unreadable (${gate.readError}) — failing closed: google voices are not planned (hounfour.headless.agy_opt_in)`);
   788 |   }
~~~~

The change from head to the fix:

~~~~diff
@@ -775,2 +1041,4 @@
-  if (provider !== undefined && isLocalVoice(provider, bare, trusted)) return undefined;
-  return localityRefusal(model, provider ?? "unresolved provider");
+  if (provider === undefined) return localityRefusal(model, "unresolved provider");
+  const d = localVoiceDecision(provider, bare, trusted);
+  if (d.local) return undefined;
+  return d.reason ?? localityRefusal(model, provider);
~~~~

## H85 — .claude/skills/bridgebuilder-review/resources/core/types.ts — insertion after head line 72

Head context (head/.claude/skills/bridgebuilder-review/resources/core/types.ts, lines 61–84):

~~~~text
    61 | /** One `hounfour.providers.<name>` declaration as Bridgebuilder reads it (cycle-129 D-7.5, D-8.0 canonical keys). */
    62 | export interface ProviderDecl {
    63 |   /** `keyless: true`, or a literal `auth` value (normalised to keyless, D-8.0): no credential env var is required. */
    64 |   keyless: boolean;
    65 |   /** `allow_insecure_endpoint` is set (any non-null, non-false value). */
    66 |   insecure: boolean;
    67 |   /** The env var named by an `auth: "{env:VAR}"` template, when the declaration has one. */
    68 |   authEnv?: string;
    69 |   /** Provider-level `dispatch_group`, when declared. */
    70 |   dispatchGroup?: string;
    71 |   /** `models.<model_id>.dispatch_group` per declared model. */
    72 |   modelGroups: Record<string, string | undefined>;
    73 | }
    74 | 
    75 | /** Where the trusted provider configuration was read from. */
    76 | export type TrustedConfigSource = "working-tree" | "base-ref" | "repository-settings" | "none";
    77 | 
    78 | /** The trusted configuration view (cycle-129 D-7.5, D-7.7, D-8.1). */
    79 | export interface TrustedConfig {
    80 |   /** `pull-request` when run on a PR (`--pr`, `GITHUB_EVENT_NAME`, `GITHUB_BASE_REF`); `local` otherwise. */
    81 |   mode: "local" | "pull-request";
    82 |   source: TrustedConfigSource;
    83 |   /** The git ref the base config was read from (`source: base-ref`). */
    84 |   ref?: string;
~~~~

The change from head to the fix:

~~~~diff
@@ -72,0 +73,9 @@
+  /** The declared `endpoint` (a string), when there is one — the local-hop rule reads its host (D-8.1, r257-1). */
+  endpoint?: string;
+  /** A CLI provider (`type: *-headless`, or every model `kind: cli`): never local (D-8.1, r257-1). */
+  cli?: boolean;
+  /**
+   * `models.<model_id>.fallback_chain` per declared model that has one (audit a257-1 MEDIUM-A1 (c)): cheval walks it
+   * inside one call, so a local voice is local only when every entry is. A non-string entry is kept as "" (unresolvable).
+   */
+  modelFallbacks?: Record<string, string[]>;
~~~~

## H86 — .claude/skills/bridgebuilder-review/resources/core/types.ts — insertion after head line 94

Head context (head/.claude/skills/bridgebuilder-review/resources/core/types.ts, lines 83–106):

~~~~text
    83 |   /** The git ref the base config was read from (`source: base-ref`). */
    84 |   ref?: string;
    85 |   /** `hounfour.providers` from the trusted source only. */
    86 |   providers: Record<string, ProviderDecl>;
    87 |   /** Providers the head checkout declares keyless or insecure that the trusted source does not: refused by name. */
    88 |   headOnlyRefused: string[];
    89 |   /** `hounfour.locality` (default `hosted`). */
    90 |   locality: "hosted" | "local_voices";
    91 |   /** `bridgebuilder.exit_on_degraded` (default 3; 0 restores the pre-cycle-129 exit). */
    92 |   exitOnDegraded: number;
    93 |   /** Lines to log once at startup (read failures, refusals, invalid values). */
    94 |   warnings: string[];
    95 | }
    96 | 
    97 | /** Multi-model provider configuration entry. */
    98 | export interface MultiModelProviderEntry {
    99 |   provider: string;
   100 |   model_id: string;
   101 |   role: "primary" | "reviewer";
   102 | }
   103 | 
   104 | /** Multi-model Bridgebuilder configuration. */
   105 | export interface MultiModelConfig {
   106 |   enabled: boolean;
~~~~

The change from head to the fix:

~~~~diff
@@ -94,0 +104,9 @@
+  /** `hounfour.aliases` from the trusted source (string targets only) — resolves `fallback_chain` aliases (MEDIUM-A1 (c)). */
+  aliases?: Record<string, string>;
+  /**
+   * Pull-request mode only (audit a257-1 MEDIUM-A2): the dotted keys among `hounfour.providers.<name>`,
+   * `hounfour.aliases.<alias>`, `hounfour.locality` and the secret allowlists that differ between the PR head and the
+   * trusted source. cheval reads the checkout's configuration for the dispatch, so a non-empty list refuses the
+   * multi-model run (main.ts, exit 5). Always `[]` in local mode.
+   */
+  headDrift?: string[];
~~~~

## H87 — .claude/skills/bridgebuilder-review/resources/entry.sh — insertion after head line 123

Head context (head/.claude/skills/bridgebuilder-review/resources/entry.sh, lines 112–124):

~~~~text
   112 |   echo "The compiled app (dist/) imports zod at runtime, and node_modules/ is" >&2
   113 |   echo "not tracked. Install once per clone:" >&2
   114 |   echo "" >&2
   115 |   echo "  cd ${SKILL_DIR} && npm ci" >&2
   116 |   echo "" >&2
   117 |   echo "(package-lock.json is tracked; zod is the only production dependency.)" >&2
   118 |   # (exit 4, not 3: since cycle-129 D-7.7 exit 3 means "the review completed, DEGRADED" — a missing dependency is a
   119 |   # failure to run and must never read as a completed review)
   120 |   exit 4
   121 | fi
   122 | 
   123 | # Run compiled TypeScript via Node (no npx tsx — SKP-002)
   124 | exec node "${SKILL_DIR}/dist/main.js" "$@"
~~~~

The change from head to the fix:

~~~~diff
@@ -123,0 +124,3 @@
+# Exit codes: 0 the review completed; 3 completed DEGRADED (bridgebuilder.exit_on_degraded, cycle-129 D-7.7); 4 failed
+# to run (above); 5 refused before any voice was planned because the PR head's hounfour providers, aliases, locality or
+# secret allowlist differ from the trusted config (audit a257-1 MEDIUM-A2: cheval reads the checkout's configuration).
~~~~

## H88 — .claude/skills/bridgebuilder-review/resources/main.ts — insertion after head line 24

Head context (head/.claude/skills/bridgebuilder-review/resources/main.ts, lines 13–36):

~~~~text
    13 |   resolveConfig,
    14 |   resolveRepos,
    15 |   formatEffectiveConfig,
    16 |   loadMultiModelConfig,
    17 |   validateApiKeys,
    18 |   readAgyGate,
    19 |   agyGateStartupLines,
    20 |   loaConfigPathFor,
    21 |   loadTrustedConfig,
    22 |   trustedConfigStartupLine,
    23 |   applyLocality,
    24 |   singleModelLocalityRefusal,
    25 | } from "./config.js";
    26 | import { summarizeVoices, totalVoices, decideExitCode, degradedWarnLine, type VoiceOutcome } from "./core/run-outcome.js";
    27 | import type { BridgebuilderConfig, RunSummary } from "./core/types.js";
    28 | import { executeMultiModelReview } from "./core/multi-model-pipeline.js";
    29 | import { DEFAULT_LORE_PATH, loadLoreEntries } from "./core/lore-loader.js";
    30 | import type { LoreEntry } from "./core/template.js";
    31 | import { detectRefs, parseManualRefs, fetchCrossRepoContext } from "./core/cross-repo.js";
    32 | import { renderCrossRepoSection } from "./core/cross-repo-render.js";
    33 | import { ProgressReporter } from "./core/progress.js";
    34 | import {
    35 |   buildRatingPrompt,
    36 |   storeRating,
~~~~

The change from head to the fix:

~~~~diff
@@ -24,0 +25,2 @@
+  headDriftRefusal,
+  EXIT_TRUSTED_CONFIG_DRIFT,
~~~~

## H89 — .claude/skills/bridgebuilder-review/resources/main.ts — insertion after head line 466

Head context (head/.claude/skills/bridgebuilder-review/resources/main.ts, lines 455–478):

~~~~text
   455 |   console.error(formatEffectiveConfig(config, provenance));
   456 | 
   457 |   // cycle-129 D-7.5 (DEC-0170): provider declarations, locality and the DEGRADED exit key come from TRUSTED configuration
   458 |   // only — the base branch's config (or repository settings) on a pull request, the working tree locally.
   459 |   const trusted = loadTrustedConfig({
   460 |     pr: cliArgs.pr,
   461 |     repoRoot: config.repoRoot,
   462 |     repo: config.repos.length === 1 ? `${config.repos[0].owner}/${config.repos[0].repo}` : undefined,
   463 |   });
   464 |   config.trusted = trusted;
   465 |   console.error(trustedConfigStartupLine(trusted));
   466 |   for (const line of trusted.warnings) console.error(line);
   467 | 
   468 |   // Load persona via 5-level precedence chain
   469 |   const personaResult = await loadPersona(config, {
   470 |     warn: (msg: string) => console.error(`[bridgebuilder] WARN: ${msg}`),
   471 |   });
   472 |   const persona = personaResult.content;
   473 |   console.error(`[bridgebuilder] Persona: ${personaResult.source}`);
   474 | 
   475 |   // Apply persona model override (V3-2): persona model wins unless CLI --model was explicit
   476 |   if (personaResult.model && provenance.model !== "cli") {
   477 |     config.model = personaResult.model;
   478 |     console.error(`[bridgebuilder] Model override: ${personaResult.model} (from persona:${personaResult.source})`);
~~~~

The change from head to the fix:

~~~~diff
@@ -466,0 +469,8 @@
+  // audit a257-1 MEDIUM-A2: cheval (every voice's transport) reads the CHECKOUT's configuration, so on a pull request a
+  // head whose providers, aliases, locality or secret allowlist differ from the trusted source's is refused by name
+  // before any voice is planned — exit 5, distinct from 0, 3 (DEGRADED) and 4 (FAILED). Local mode is unchanged.
+  const driftRefusal = headDriftRefusal(trusted);
+  if (driftRefusal !== undefined) {
+    console.error(driftRefusal);
+    process.exit(EXIT_TRUSTED_CONFIG_DRIFT);
+  }
~~~~

## H90 — .claude/skills/scheduled-cycle-template/contracts/session-cap-bb/dispatcher.sh — head lines 76–89

Head context (head/.claude/skills/scheduled-cycle-template/contracts/session-cap-bb/dispatcher.sh, lines 64–92):

~~~~text
    64 | # BB's stdout (its run JSON) is kept in the handoff dir and replayed, so a DEGRADED run can name its voices.
    65 | BB_OUT="${HANDOFF_DIR}/bb-stdout.json"
    66 | rc=0
    67 | if [[ -x "$BB_ENTRY" ]]; then
    68 |     "$BB_ENTRY" --repo "$repo" >"$BB_OUT" || rc=$?
    69 | else
    70 |     bash "$BB_ENTRY" --repo "$repo" >"$BB_OUT" || rc=$?
    71 | fi
    72 | cat "$BB_OUT"
    73 | 
    74 | # cycle-129 D-7.7 (DEC-0150): exit 3 = the review COMPLETED with a DEGRADED consensus (bridgebuilder.exit_on_degraded;
    75 | # 0 restores the old exit). Not a failure: one WARN naming the incomplete voices, `degraded: true` in the handoff, exit 0.
>   76 | degraded=false
>   77 | voices=""
>   78 | if [[ "$rc" -eq 3 ]]; then
>   79 |     degraded=true
>   80 |     voices=$(jq -r '[.verdicts[]?.voices.incomplete[]?] | unique | join(", ")' "$BB_OUT" 2>/dev/null) || voices=""
>   81 |     echo "dispatcher: WARN: bridgebuilder completed DEGRADED (exit 3): incomplete voices: ${voices:-none named (degraded verdict quality)}" >&2
>   82 | fi
>   83 | 
>   84 | write_out "$(jq -nc --arg cid "$cycle_id" --arg sid "$schedule_id" \
>   85 |     --arg repo "$repo" --argjson ec "$rc" --argjson degraded "$degraded" --arg voices "$voices" \
>   86 |     '{cycle_id:$cid, schedule_id:$sid, dispatched:true, repo:$repo,
>   87 |       bb_exit_code:$ec, degraded:$degraded}
>   88 |      + (if $degraded then {incomplete_voices: $voices} else {} end)')"
>   89 | if [[ "$rc" -eq 3 ]]; then
    90 |     exit 0
    91 | fi
    92 | exit "$rc"
~~~~

The change from head to the fix:

~~~~diff
@@ -76,14 +76,22 @@
+# Bridgebuilder PR #1282 F-001: exit 3 is "completed, degraded" ONLY when the run JSON is there to prove it — a
+# non-empty stdout that parses with a `verdicts` array. An exit 3 with no run JSON (a wrapper, a shell error inside
+# entry.sh, a reassigned exit code) stays a failure: the handoff records it and the dispatcher exits 3.
 degraded=false
-voices=""
+voices_json="[]"
 if [[ "$rc" -eq 3 ]]; then
-    degraded=true
-    voices=$(jq -r '[.verdicts[]?.voices.incomplete[]?] | unique | join(", ")' "$BB_OUT" 2>/dev/null) || voices=""
-    echo "dispatcher: WARN: bridgebuilder completed DEGRADED (exit 3): incomplete voices: ${voices:-none named (degraded verdict quality)}" >&2
+    if [[ -s "$BB_OUT" ]] && jq -e '.verdicts | type == "array"' "$BB_OUT" >/dev/null 2>&1; then
+        degraded=true
+        voices_json=$(jq -c '[.verdicts[]?.voices.incomplete[]? | strings] | unique' "$BB_OUT" 2>/dev/null) || voices_json="[]"
+        voices=$(jq -r 'join(", ")' <<<"$voices_json" 2>/dev/null) || voices=""
+        echo "dispatcher: WARN: bridgebuilder completed DEGRADED (exit 3): incomplete voices: ${voices:-none named (degraded verdict quality)}" >&2
+    else
+        echo "dispatcher: ERROR: bridgebuilder exited 3 without a run JSON (no verdicts array on stdout) — not a completed review; treated as a failure" >&2
+    fi
 fi
 
 write_out "$(jq -nc --arg cid "$cycle_id" --arg sid "$schedule_id" \
-    --arg repo "$repo" --argjson ec "$rc" --argjson degraded "$degraded" --arg voices "$voices" \
+    --arg repo "$repo" --argjson ec "$rc" --argjson degraded "$degraded" --argjson voices "$voices_json" \
     '{cycle_id:$cid, schedule_id:$sid, dispatched:true, repo:$repo,
       bb_exit_code:$ec, degraded:$degraded}
      + (if $degraded then {incomplete_voices: $voices} else {} end)')"
-if [[ "$rc" -eq 3 ]]; then
+if [[ "$rc" -eq 3 && "$degraded" == true ]]; then
~~~~

## H91 — .loa.config.yaml.example — head lines 1229–1230

Head context (head/.loa.config.yaml.example, lines 1217–1242):

~~~~text
  1217 | #           context_window: 400000
  1218 | #           max_output_tokens: 16000
  1219 | #           pricing:
  1220 | #             input_per_mtok: 10000000
  1221 | #             output_per_mtok: 30000000
  1222 | #   aliases:
  1223 | #     reviewer: "azure-openai:gpt-5-azure"
  1224 | # @example-end
  1225 | #
  1226 | # Example 4: Local OpenAI-compatible server (vLLM, llama.cpp, Ollama, LM Studio)
  1227 | # Threat model: plain http is admitted only to the one host named in
  1228 | # allow_insecure_endpoint, an IP literal or localhost in a loopback or RFC1918
> 1229 | # range that is never resolved through DNS, so the prompt does not cross a
> 1230 | # public network unencrypted and the name cannot be rebound. For this provider
  1231 | # cheval ignores proxy environment variables, refuses redirects and keeps every
  1232 | # request under the declared endpoint path, while every other provider keeps the
  1233 | # https, loopback and private-range refusals.
  1234 | # keyless: true sends no credential (a literal auth: "local" means the same).
  1235 | # secret_env_allowlist: if your server does want a key, use
  1236 | # auth: "{env:LOCAL_LLM_KEY}" instead of keyless and add "^LOCAL_LLM_KEY$" to
  1237 | # secret_env_allowlist; an environment variable outside the allowlist is refused.
  1238 | # A prompt over the declared context_window refuses the hop by name and is never
  1239 | # truncated; the zero prices record the hop at cost 0.
  1240 | # @example-begin local-openai-compatible
  1241 | # hounfour:
  1242 | #   providers:
~~~~

The change from head to the fix:

~~~~diff
@@ -1229,2 +1229,4 @@
-# range that is never resolved through DNS, so the prompt does not cross a
-# public network unencrypted and the name cannot be rebound. For this provider
+# range. IP literals are never resolved, so the prompt does not cross a public
+# network unencrypted and the address cannot be rebound; localhost is resolved
+# and checked at request time, and any address that is not loopback (or a
+# resolver failure) refuses the request by name. For this provider
~~~~

## H92 — .loa.config.yaml.example — head lines 2511–2512

Head context (head/.loa.config.yaml.example, lines 2499–2524):

~~~~text
  2499 |     - test-coverage
  2500 | 
  2501 |   # HTML comment marker for idempotency detection
  2502 |   review_marker: "bridgebuilder-review"
  2503 | 
  2504 |   # Path to persona override (project-specific reviewer personality).
  2505 |   # Falls back to built-in resources/BEAUVOIR.md if file not found.
  2506 |   persona_path: "grimoires/bridgebuilder/BEAUVOIR.md"
  2507 | 
  2508 |   # Exit code of a multi-model run whose consensus is DEGRADED: fewer voices completed than planned, or a
  2509 |   # degraded verdict-quality band (cycle-129, DEC-0150). The JSON and the PR comments are written first;
  2510 |   # callers treat 3 as "completed, degraded" and print a WARN naming the voices. 0 restores the pre-cycle-129
> 2511 |   # exit (rollback key). Integer 0..125. On a pull request this key is read from the trusted config
> 2512 |   # (the base branch's .loa.config.yaml or BRIDGEBUILDER_TRUSTED_CONFIG), never from the PR head.
  2513 |   exit_on_degraded: 3
  2514 | 
  2515 | # =============================================================================
  2516 | # QMD Context Query — Unified context retrieval with three-tier fallback
  2517 | # =============================================================================
  2518 | # Controls the qmd-context-query.sh script that provides semantic search
  2519 | # across grimoires, skills, notes, and reality files.
  2520 | # Three-tier fallback: QMD (semantic) → CK (code knowledge) → grep (text)
  2521 | 
  2522 | qmd_context:
  2523 |   # Master switch — set to false to disable all context injection
  2524 |   enabled: true
~~~~

The change from head to the fix:

~~~~diff
@@ -2511,2 +2513,8 @@
-  # exit (rollback key). Integer 0..125. On a pull request this key is read from the trusted config
+  # exit (rollback key). Two values are meaningful to the callers (spiral-harness.sh, the session-cap dispatcher):
+  # 3 and 0; any other integer 0..125 is accepted but reported by them as "the review did not complete" (4 is
+  # entry.sh's missing-dependency preflight). On a pull request this key is read from the trusted config
   # (the base branch's .loa.config.yaml or BRIDGEBUILDER_TRUSTED_CONFIG), never from the PR head.
+  # Trusted config drift: cheval reads the checkout's configuration for the dispatch, so a pull request whose
+  # head changes hounfour.providers, hounfour.aliases, hounfour.locality or the secret allowlist is refused by
+  # name before any voice is planned (exit 5): merge the base branch into the head, or set
+  # BRIDGEBUILDER_TRUSTED_CONFIG to the configuration you vouch for.
~~~~

## H93 — tests/unit/adversarial-review-advisory.bats — insertion after head line 53

Head context (head/tests/unit/adversarial-review-advisory.bats, lines 42–65):

~~~~text
    42 |     result=$(s3_run review)
    43 |     [ "$(cat "$T/rc")" = "0" ] || { cat "$T/stderr.log"; return 1; }
    44 |     env="$OUT_DIR/adversarial-review.json"
    45 |     # the counted voices are untouched: primary + companion, nothing advisory at the top level
    46 |     [ "$(jq '.findings | length' "$env")" = "2" ]
    47 |     [ "$(jq '[.findings[] | select(.voice == "advisory")] | length' "$env")" = "0" ]
    48 |     [ "$(jq '.verdict_quality.voices_planned' "$env")" = "2" ]
    49 |     # the block
    50 |     [ "$(jq '.advisory_voices | length' "$env")" = "1" ]
    51 |     [ "$(jq -r '.advisory_voices[0].alias' "$env")" = "adv-two" ]
    52 |     [ "$(jq -r '.advisory_voices[0].status' "$env")" = "succeeded" ]
    53 |     [ "$(jq -r '.advisory_voices[0].counted_as' "$env")" = "advisory_voice" ]
    54 |     [ "$(jq '.advisory_voices[0].findings | length' "$env")" = "3" ]
    55 |     [ "$(jq -r '[.advisory_voices[0].findings[].voice] | unique | join(",")' "$env")" = "advisory" ]
    56 |     [ "$(jq -r '[.advisory_voices[0].findings[].id] | join(",")' "$env")" = "DISS-A1-001,DISS-A1-002,DISS-A1-003" ]
    57 |     # same file, overlapping lines (9-12 over 10), same category → the counted primary finding; else null
    58 |     [ "$(jq -r '.advisory_voices[0].findings[0].duplicate_of' "$env")" = "DISS-001" ]
    59 |     [ "$(jq -r '.advisory_voices[0].findings[1].duplicate_of' "$env")" = "null" ]   # (line 40: no overlap)
    60 |     [ "$(jq -r '.advisory_voices[0].findings[2].duplicate_of' "$env")" = "null" ]   # (same line, another category)
    61 |     [ "$(jq -r '.advisory_voices[0].findings[0].answered_by' "$env")" = "adv-two" ]
    62 |     grep -qx "adv-two" "$CALLS"
    63 |     # stdout carries the same envelope
    64 |     [ "$(jq '.advisory_voices | length' <<<"$result")" = "1" ]
    65 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -53,0 +54,3 @@
+    # (r257-2 LOW-3) the advisory voice's own spend is recorded on its entry; the counted envelope's cost is the counted voices' alone
+    [ "$(jq -r '.advisory_voices[0].cost_usd' "$env")" = "0.002" ]
+    [ "$(jq '((.metadata.cost_usd // 0) * 10000 | round) as $c | ($c == 123 or $c == 246)' "$env")" = "true" ]   # the stub's counted voices cost 0.0123 each; never + the advisory 0.002
~~~~

## H94 — tests/unit/adversarial-review-budget.bats — insertion after head line 27

Head context (head/tests/unit/adversarial-review-budget.bats, lines 16–39):

~~~~text
    16 | 
    17 | _cfg() {  # <model> <budget> <companion_voice> [extra code_review lines]
    18 |     s3_config "hounfour:
    19 |   providers:
    20 |     openai:
    21 |       models:
    22 |         fixture-priced:
    23 |           pricing: {input_per_mtok: 2000000, output_per_mtok: 8000000}
    24 |     fixturelocal:
    25 |       models:
    26 |         fixture-zero:
    27 |           pricing: {input_per_mtok: 0, output_per_mtok: 0}
    28 |         fixture-stale:
    29 |           price_date: \"2000-01-01\"
    30 |           pricing: {input_per_mtok: 1000000, output_per_mtok: 1000000}
    31 | flatline_protocol:
    32 |   code_review:
    33 |     enabled: true
    34 |     model: $1
    35 |     budget_cents: $2
    36 |     timeout_seconds: 30
    37 |     companion_voice: $3
    38 |     fallback_chain: []
    39 | ${4:-}"
~~~~

The change from head to the fix:

~~~~diff
@@ -27,0 +28,3 @@
+        fixture-zero-ow:
+          open_weight: true
+          pricing: {input_per_mtok: 0, output_per_mtok: 0}
~~~~

## H95 — tests/unit/adversarial-review-budget.bats — insertion after head line 77

Head context (head/tests/unit/adversarial-review-budget.bats, lines 66–89):

~~~~text
    66 |     [ "$(jq -r '.metadata.estimate_voices[0].pricing_source' <<<"$result")" = "fallback" ]
    67 |     grep -qF "budget: no catalog price for mystery-model-x (primary) — the fixed 10 / 30 USD per Mtok applies to this voice" "$T/stderr.log"
    68 |     [ "$(grep -c "no catalog price" "$T/stderr.log")" = "1" ]
    69 | }
    70 | 
    71 | @test "BUD-3 a zero-priced entry estimates 0c and is said: a 0-cent budget admits it, where the fixed rate would refuse" {
    72 |     _cfg fixture-zero 0 false
    73 |     s3_run review >/dev/null
    74 |     [ "$(cat "$T/rc")" = "0" ] || { cat "$T/stderr.log"; return 1; }
    75 |     grep -qF "budget: fixture-zero (primary) is zero-priced in the catalog — estimated 0c" "$T/stderr.log"
    76 |     grep -qF "budget: estimate 0c over 1 planned voice(s) (primary fixture-zero 0c)" "$T/stderr.log"
    77 |     grep -qx "fixture-zero" "$CALLS"
    78 |     # the same run priced at the fixed rate is refused (the regression this replaces: 2000 output tokens × 30 = 6c > 0)
    79 |     _cfg mystery-model-x 0 false
    80 |     s3_run review >/dev/null
    81 |     [ "$(cat "$T/rc")" = "4" ]
    82 | }
    83 | 
    84 | @test "BUD-4 the gate sums every planned voice: primary + the companion's first hop + each advisory voice" {
    85 |     _big_diff
    86 |     _cfg fixture-priced 1 true "    advisory_voices: [fixture-zero, mystery-model-x]"
    87 |     result=$(s3_run review)
    88 |     [ "$(cat "$T/rc")" = "4" ] || { cat "$T/stderr.log"; return 1; }
    89 |     [ "$(jq -r '[.metadata.estimate_voices[] | "\(.role)=\(.alias)"] | join(" ")' <<<"$result")" = "primary=fixture-priced companion=claude-headless advisory=fixture-zero advisory=mystery-model-x" ]
~~~~

The change from head to the fix:

~~~~diff
@@ -77,0 +81,2 @@
+    # audit a257-1 LOW-A3: the zero price is on an entry not marked open_weight — said by name (the estimate is unchanged)
+    grep -qF "budget: zero price on fixture-zero (primary), not marked open_weight — check the pricing overlay" "$T/stderr.log"
~~~~

## H96 — tests/unit/adversarial-review-budget.bats — insertion after head line 123

Head context (head/tests/unit/adversarial-review-budget.bats, lines 112–123):

~~~~text
   112 | @test "BUD-6 with no price CLI answer at all every voice falls back and is said (the gate never prices from nothing)" {
   113 |     _cfg fixture-priced 1000 false
   114 |     # a PYTHONPATH that cannot import the package: the CLI fails, every planned voice is unknown
   115 |     local real patched
   116 |     real="$(declare -f _adv_budget_estimate)"
   117 |     patched="${real/PYTHONPATH=\"\$PROJECT_ROOT\/.claude\/adapters\"/PYTHONPATH=/nonexistent}"
   118 |     [ "$patched" != "$real" ]   # (the seam was found: the CLI really cannot be imported in this run)
   119 |     eval "$patched"
   120 |     s3_run review >/dev/null
   121 |     [ "$(cat "$T/rc")" = "0" ]
   122 |     grep -qF "budget: no catalog price for fixture-priced (primary)" "$T/stderr.log"
   123 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -123,0 +129,9 @@
+
+@test "BUD-7 a zero-priced entry marked open_weight estimates 0c with no overlay warning (audit a257-1 LOW-A3)" {
+    _cfg fixture-zero-ow 0 false
+    s3_run review >/dev/null
+    [ "$(cat "$T/rc")" = "0" ] || { cat "$T/stderr.log"; return 1; }
+    grep -qF "budget: fixture-zero-ow (primary) is zero-priced in the catalog — estimated 0c" "$T/stderr.log"
+    ! grep -qF "budget: zero price on fixture-zero-ow" "$T/stderr.log" || { echo "an open_weight entry was warned"; return 1; }
+    grep -qx "fixture-zero-ow" "$CALLS"
+}
~~~~

## H97 — tests/unit/adversarial-review-locality.bats — head line 18

Head context (head/tests/unit/adversarial-review-locality.bats, lines 6–30):

~~~~text
     6 | # Under hounfour.locality: local_voices, adversarial-review.sh plans only hops whose provider has dispatch_group: local in
     7 | # the merged config (catalog + the project's hounfour.providers) and refuses every hosted hop of its inventory at plan time
     8 | # by name — primary chain, companion chain, advisory voices, the KF-004 repair chain (tiny, claude-headless, any pin; the
     9 | # chain is the answering voice). With one local family the audit is DEGRADED_SECURITY_REVIEW, the gate and verdict-derive
    10 | # treat the envelope as today, and the output says so. The default (hosted) is unchanged. Mock mode: the harness stub.
    11 | # =============================================================================
    12 | 
    13 | load adversarial-review-s3-helpers
    14 | 
    15 | setup() { export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR"; s3_setup sprint-s3loc; }   # (the CLI lock is this test's own — CMP-121)
    16 | teardown() { s3_teardown; }
    17 | 
>   18 | # one hosted provider (openai, the catalog's) and one local provider (localbox, declared here)
    19 | _cfg() {  # <locality value | absent> [extra code_review / security_audit lines]
    20 |     local loc=""; [[ "$1" == absent ]] || loc="  locality: $1"
    21 |     s3_config "hounfour:
    22 | $loc
    23 |   providers:
    24 |     localbox:
    25 |       type: openai_compat
    26 |       endpoint: \"http://127.0.0.1:8000/v1\"
    27 |       models:
    28 |         qwen-local:
    29 |           dispatch_group: local
    30 |           pricing: {input_per_mtok: 0, output_per_mtok: 0}
~~~~

The change from head to the fix:

~~~~diff
@@ -18 +18,3 @@
-# one hosted provider (openai, the catalog's) and one local provider (localbox, declared here)
+# one hosted provider (openai, the catalog's) and one local provider (localbox, declared here — a provider the cheval
+# loader itself admits: keyless, opted in to its loopback host, every model with endpoint_family/auth_type/context_window;
+# LOC-10 loads it through loa_cheval.config.loader)
~~~~

## H98 — tests/unit/adversarial-review-locality.bats — head lines 27–36

Head context (head/tests/unit/adversarial-review-locality.bats, lines 15–48):

~~~~text
    15 | setup() { export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR"; s3_setup sprint-s3loc; }   # (the CLI lock is this test's own — CMP-121)
    16 | teardown() { s3_teardown; }
    17 | 
    18 | # one hosted provider (openai, the catalog's) and one local provider (localbox, declared here)
    19 | _cfg() {  # <locality value | absent> [extra code_review / security_audit lines]
    20 |     local loc=""; [[ "$1" == absent ]] || loc="  locality: $1"
    21 |     s3_config "hounfour:
    22 | $loc
    23 |   providers:
    24 |     localbox:
    25 |       type: openai_compat
    26 |       endpoint: \"http://127.0.0.1:8000/v1\"
>   27 |       models:
>   28 |         qwen-local:
>   29 |           dispatch_group: local
>   30 |           pricing: {input_per_mtok: 0, output_per_mtok: 0}
>   31 |         qwen-local-b:
>   32 |           dispatch_group: local
>   33 |           pricing: {input_per_mtok: 0, output_per_mtok: 0}
>   34 |         qwen-local-c:
>   35 |           dispatch_group: local
>   36 |         qwen-leaky:
    37 |           dispatch_group: local
    38 |           fallback_chain: [\"openai:gpt-5.5\"]
    39 |   aliases:
    40 |     lq: \"localbox:qwen-local\"
    41 |     lqb: \"localbox:qwen-local-b\"
    42 |     lqc: \"localbox:qwen-local-c\"
    43 | flatline_protocol:
    44 |   code_review:
    45 |     enabled: true
    46 |     model: gpt-5.5
    47 |     budget_cents: 500
    48 |     timeout_seconds: 30
~~~~

The change from head to the fix:

~~~~diff
@@ -27,10 +29,24 @@
+      allow_insecure_endpoint: \"127.0.0.1\"
+      keyless: true
       models:
         qwen-local:
+          endpoint_family: chat
+          auth_type: http_api
+          context_window: 32768
           dispatch_group: local
           pricing: {input_per_mtok: 0, output_per_mtok: 0}
         qwen-local-b:
+          endpoint_family: chat
+          auth_type: http_api
+          context_window: 32768
           dispatch_group: local
           pricing: {input_per_mtok: 0, output_per_mtok: 0}
         qwen-local-c:
+          endpoint_family: chat
+          auth_type: http_api
+          context_window: 32768
           dispatch_group: local
         qwen-leaky:
+          endpoint_family: chat
+          auth_type: http_api
+          context_window: 32768
~~~~

## H99 — tests/unit/adversarial-review-locality.bats — insertion after head line 85

Head context (head/tests/unit/adversarial-review-locality.bats, lines 74–97):

~~~~text
    74 |     [ "$(sort -u "$CALLS" | tr '\n' ' ')" = "lq " ]
    75 |     [ "$(jq -r '.metadata.final_model' "$env")" = "lq" ]
    76 |     [ "$(jq -r '.metadata.model_attempts | join(",")' "$env")" = "lq:reviewed" ]
    77 |     # each refusal named: the hosted primary, the companion's default hop, the repair chain's two hosted hops
    78 |     grep -qxF "[adversarial-review] locality: local_voices refuses hosted hop gpt-5.5 (openai)" "$T/stderr.log"
    79 |     grep -qxF "[adversarial-review] locality: local_voices refuses hosted hop claude-headless (anthropic)" "$T/stderr.log"
    80 |     grep -qxF "[adversarial-review] locality: local_voices refuses hosted hop tiny (anthropic)" "$T/stderr.log"
    81 |     # the companion was not planned: its chain had no local hop — never rerouted
    82 |     [ "$(jq -r '.metadata.companion_voice.planned' "$env")" = "false" ]
    83 |     [ "$(jq -r '.metadata.companion_voice.reason' "$env")" = "locality_refused" ]
    84 |     # the envelope names the posture and each refusal with its role
    85 |     [ "$(jq -r '.metadata.locality.mode' "$env")" = "local_voices" ]
    86 |     [ "$(jq -r '[.metadata.locality.refused[] | "\(.role):\(.alias):\(.provider)"] | sort | join(" ")' "$env")" = \
    87 |       "companion:claude-headless:anthropic primary:gpt-5.5:openai repair:claude-headless:anthropic repair:tiny:anthropic" ]
    88 |     [ "$(jq '.verdict_quality.voices_planned' "$env")" = "1" ]
    89 | }
    90 | 
    91 | @test "LOC-2 the repair chain is pinned to the answering local voice: no tiny, no claude-headless, no pin — even with an Anthropic key" {
    92 |     _cfg local_voices
    93 |     export ANTHROPIC_API_KEY="fixture-not-a-key"   # (tiny would lead the hosted chain with a key present)
    94 |     export LOA_ADVERSARIAL_REPAIR_MODEL="tiny claude-headless"
    95 |     load_adversarial_config review
    96 |     [ "$CONF_LOCALITY" = "local_voices" ]
    97 |     [ "$(_repair_model_chain lq)" = "lq" ]
~~~~

The change from head to the fix:

~~~~diff
@@ -85,0 +102,3 @@
+    # audit a257-1 LOW-A2: a review envelope is not a degraded security review, and carries no audit sentence
+    [ "$(jq -r '.metadata.locality.degraded_security_review' "$env")" = "false" ]
+    jq -e '.metadata.locality | has("note") | not' "$env" >/dev/null
~~~~

## H100 — tests/unit/adversarial-review-locality.bats — insertion after head line 144

Head context (head/tests/unit/adversarial-review-locality.bats, lines 133–156):

~~~~text
   133 | }
   134 | 
   135 | @test "LOC-4 one local family on the audit gate: the companion is duplicate_voice, the DEGRADED sentence is in the output, and the gate and verdict-derive treat the envelope as today" {
   136 |     _cfg local_voices "" "    companion_chain:
   137 |       anthropic: [lqb]"
   138 |     s3_run audit >/dev/null
   139 |     [ "$(cat "$T/rc")" = "0" ] || { cat "$T/stderr.log"; return 1; }
   140 |     env="$OUT_DIR/adversarial-audit.json"
   141 |     [ "$(jq -r '.metadata.companion_voice.counted_as' "$env")" = "duplicate_voice" ]
   142 |     local s="locality: local_voices — with one local family the companion is not an independent second voice (duplicate_voice, or not planned), so every security audit is DEGRADED_SECURITY_REVIEW; adversarial-review-gate.sh and verdict-derive.sh treat this envelope exactly as they treat any other."
   143 |     grep -qxF "[adversarial-review] $s" "$T/stderr.log"
   144 |     [ "$(jq -r '.metadata.locality.note' "$env")" = "$s" ]
   145 |     # the config comment carries the same sentence
   146 |     grep -qF "$s" "$PROJECT_ROOT/.loa.config.yaml.example"
   147 |     # the COMPLETED gate opens on it (presence + metadata.type/model — today's check)
   148 |     local hook="$PROJECT_ROOT/.claude/hooks/safety/adversarial-review-gate.sh" cfg="$T/gate.yaml" rc=0
   149 |     printf 'flatline_protocol:\n  security_audit:\n    enabled: true\n' > "$cfg"
   150 |     printf '{"tool_name":"Write","tool_input":{"file_path":"%s/COMPLETED"}}' "$OUT_DIR" \
   151 |         | env -u LOA_ADVERSARIAL_REVIEW_ENFORCE LOA_CONFIG_PATH_OVERRIDE="$cfg" bash "$hook" >/dev/null 2>&1 || rc=$?
   152 |     [ "$rc" -eq 0 ]
   153 |     # verdict-derive reads it like any envelope: an approved audit with the DEGRADED marker is consistent
   154 |     printf '%s\n' "APPROVED - LET'S FUCKING GO" '' 'DEGRADED_SECURITY_REVIEW: one local family (locality: local_voices).' \
   155 |         '<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-x","ts":"2026-10-14T00:00:00Z"} -->' \
   156 |         > "$OUT_DIR/auditor-sprint-feedback.md"
~~~~

The change from head to the fix:

~~~~diff
@@ -144,0 +164,2 @@
+    # audit a257-1 LOW-A2: the one-family case is machine-readable on the audit envelope
+    [ "$(jq -r '.metadata.locality.degraded_security_review' "$env")" = "true" ]
~~~~

## H101 — tests/unit/adversarial-review-locality.bats — insertion after head line 213

Head context (head/tests/unit/adversarial-review-locality.bats, lines 202–213):

~~~~text
   202 |     [ "$(sed -n 4p <<<"$output" | cut -f3)" = "hosted" ]
   203 |     [ "$(sed -n 5p <<<"$output" | cut -f2-4)" = "unknown	hosted	unresolved" ]
   204 |     # an unreadable config is fail-closed: every hop hosted
   205 |     printf ':\n  - [\n' > "$T/broken.yaml"
   206 |     run python3 -I "$PROJECT_ROOT/.claude/scripts/lib/hop-locality.py" --catalog "$PROJECT_ROOT/.claude/defaults/model-config.yaml" --config "$T/broken.yaml" -- lq
   207 |     [ "$(cut -f3-4 <<<"${lines[-1]}")" = "hosted	config_unreadable" ]
   208 | }
   209 | 
   210 | @test "LOC-8 the multi-model reference says the Claude Code session model is exempt and remains the platform" {
   211 |     grep -q "hounfour.locality: local_voices" "$PROJECT_ROOT/.claude/loa/reference/multi-model-reference.md"
   212 |     grep -qi "Claude Code session model is exempt" "$PROJECT_ROOT/.claude/loa/reference/multi-model-reference.md"
   213 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -213,0 +235,76 @@
+
+@test "LOC-9 a declared dispatch_group local on a hosted DNS endpoint (or a CLI provider) is hosted and refused by name (r257-1)" {
+    _cfg local_voices
+    yq -i '.hounfour.providers.hostedbox = {"type": "openai_compat", "endpoint": "https://api.acme.example/v1",
+             "models": {"qwen-hosted": {"dispatch_group": "local", "endpoint_family": "chat", "auth_type": "http_api", "context_window": 32768}}}
+           | .hounfour.providers.blockbox = {"type": "openai_compat", "endpoint": "https://203.0.113.5/v1", "dispatch_group": "local",
+             "models": {"qwen-b": {"dispatch_group": "local", "endpoint_family": "chat", "auth_type": "http_api", "context_window": 32768}}}
+           | .hounfour.providers.clibox = {"type": "claude-headless", "models": {"c1": {"kind": "cli", "dispatch_group": "local"}}}
+           | .hounfour.providers.noend = {"type": "openai_compat", "models": {"n1": {"dispatch_group": "local"}}}
+           | .hounfour.aliases.hb = "hostedbox:qwen-hosted"
+           | .flatline_protocol.code_review.fallback_chain = ["hb", "lq"]' "$CONFIG_FILE"
+    run python3 -I "$PROJECT_ROOT/.claude/scripts/lib/hop-locality.py" --catalog "$PROJECT_ROOT/.claude/defaults/model-config.yaml" \
+        --config "$CONFIG_FILE" -- hb blockbox:qwen-b clibox:c1 noend:n1 lq "localbox:qwen-local"
+    [ "$status" -eq 0 ]
+    [ "$(sed -n 1p <<<"$output" | cut -f2-4)" = "hostedbox	hosted	endpoint_not_local:api.acme.example" ] || { echo "$output"; return 1; }
+    [ "$(sed -n 2p <<<"$output" | cut -f2-4)" = "blockbox	hosted	endpoint_not_local:203.0.113.5" ]
+    [ "$(sed -n 3p <<<"$output" | cut -f2-4)" = "clibox	hosted	cli_provider" ]
+    [ "$(sed -n 4p <<<"$output" | cut -f2-4)" = "noend	hosted	endpoint_missing" ]
+    [ "$(sed -n 5p <<<"$output" | cut -f2-4)" = "localbox	local	dispatch_group=local" ]
+    [ "$(sed -n 6p <<<"$output" | cut -f3)" = "local" ]
+    # two layers, same config (r257-2 LOW-2): the planner refuses the mislabelled hop by name at plan time and never
+    # dispatches it (shown under the harness stub, which stands in for cheval) …
+    result=$(s3_run review)
+    grep -qxF "[adversarial-review] locality: local_voices refuses hosted hop hb (hostedbox)" "$T/stderr.log" || { cat "$T/stderr.log"; return 1; }
+    ! grep -qx "hb" "$CALLS" || { echo "the mislabelled hosted hop was dispatched"; return 1; }
+    # … and in production cheval's loader refuses the WHOLE config by name at the first dispatch, so no hop of this
+    # config — local ones included — answers until the label or the endpoint is fixed (the outcome an operator sees).
+    mkdir -p "$T/proj9/.claude/defaults"
+    cp "$PROJECT_ROOT/.claude/defaults/model-config.yaml" "$T/proj9/.claude/defaults/"
+    cp "$CONFIG_FILE" "$T/proj9/.loa.config.yaml"
+    # (clibox and noend are classifier-only shapes: the loader's older field checks would refuse them first; the two
+    # complete HTTP providers reach the local-label rule itself)
+    yq -i 'del(.hounfour.providers.clibox) | del(.hounfour.providers.noend)' "$T/proj9/.loa.config.yaml"
+    run python3 -I -c 'import sys; sys.path.insert(0, sys.argv[2] + "/.claude/adapters")
+from loa_cheval.config.loader import load_config
+try:
+    load_config(project_root=sys.argv[1])
+except Exception as exc:
+    print(exc); sys.exit(3)
+print("loaded"); sys.exit(0)' "$T/proj9" "$PROJECT_ROOT"
+    [ "$status" -eq 3 ] || { echo "the loader admitted a mislabelled provider: $output"; return 1; }
+    [[ "$output" == *"[CONFIG-INVALID] providers."*"dispatch_group local"* ]] || { echo "$output"; return 1; }
+}
+
+@test "LOC-10 the suite's localbox fixture is a provider the cheval loader admits (LOW-1, r257-1); under local_voices the loader refuses qwen-leaky's hosted fallback by name (audit a257-1 MEDIUM-A1 (b))" {
+    _load10() {
+        run python3 -I -c 'import sys; sys.path.insert(0, sys.argv[2] + "/.claude/adapters")
+from loa_cheval.config.loader import load_config
+try:
+    merged, _ = load_config(project_root=sys.argv[1])
+except Exception as exc:
+    print(exc); sys.exit(3)
+p = merged["providers"]["localbox"]
+assert p["keyless"] is True and p["allow_insecure_endpoint"] == "127.0.0.1", p
+print("loaded", " ".join(sorted(p["models"])))' "$T/proj" "$PROJECT_ROOT"
+    }
+    mkdir -p "$T/proj/.claude/defaults"
+    cp "$PROJECT_ROOT/.claude/defaults/model-config.yaml" "$T/proj/.claude/defaults/"
+    # under hosted a local model may still fall back to the cloud: the whole fixture loads
+    _cfg hosted
+    cp "$CONFIG_FILE" "$T/proj/.loa.config.yaml"
+    _load10
+    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
+    [[ "$output" == *"loaded qwen-leaky qwen-local qwen-local-b qwen-local-c"* ]]
+    # under local_voices the loader refuses the local model whose fallback_chain reaches a hosted hop, by name …
+    _cfg local_voices
+    cp "$CONFIG_FILE" "$T/proj/.loa.config.yaml"
+    _load10
+    [ "$status" -eq 3 ] || { echo "the loader admitted qwen-leaky under local_voices: $output"; return 1; }
+    [[ "$output" == *"[CONFIG-INVALID] providers.localbox.models.qwen-leaky: under hounfour.locality local_voices the fallback_chain reaches a hosted hop openai:gpt-5.5"* ]] || { echo "$output"; return 1; }
+    # … and the rest of the fixture loads
+    yq -i 'del(.hounfour.providers.localbox.models.qwen-leaky)' "$T/proj/.loa.config.yaml"
+    _load10
+    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
+    [[ "$output" == *"loaded qwen-local qwen-local-b qwen-local-c"* ]]
+}
~~~~

## H102 — tests/unit/bb-exit-degraded-callers.bats — head line 46

Head context (head/tests/unit/bb-exit-degraded-callers.bats, lines 34–58):

~~~~text
    34 |     DISPATCHER_JSON="$handoff/dispatcher.json"
    35 |     run env TMPDIR="$WORK/tmp" LOA_SESSION_CAP_BB_ENTRY="$STUB" LOA_SESSION_CAP_BB_REPO="fixture/repo" \
    36 |         bash "$PROJECT_ROOT/.claude/skills/scheduled-cycle-template/contracts/session-cap-bb/dispatcher.sh" "$cid" sched-1 0 '[]'
    37 | }
    38 | 
    39 | @test "dispatcher: Bridgebuilder exit 3 is completed-degraded — WARN names the voice, handoff degraded, exit 0" {
    40 |     make_stub 3
    41 |     run_dispatcher a
    42 |     [ "$status" -eq 0 ]
    43 |     [[ "$output" == *"WARN: bridgebuilder completed DEGRADED (exit 3): incomplete voices: openai/gpt-5.5"* ]]
    44 |     [ "$(jq -r '.bb_exit_code' "$DISPATCHER_JSON")" = "3" ]
    45 |     [ "$(jq -r '.degraded' "$DISPATCHER_JSON")" = "true" ]
>   46 |     [ "$(jq -r '.incomplete_voices' "$DISPATCHER_JSON")" = "openai/gpt-5.5" ]
    47 | }
    48 | 
    49 | @test "dispatcher: Bridgebuilder's run JSON still reaches stdout" {
    50 |     make_stub 3
    51 |     run_dispatcher b
    52 |     [ "$status" -eq 0 ]
    53 |     [[ "$output" == *'"mode":"multi-model"'* ]]
    54 | }
    55 | 
    56 | @test "dispatcher: exit 0 stays 0 with degraded false and no WARN" {
    57 |     make_stub 0
    58 |     run_dispatcher c
~~~~

The change from head to the fix:

~~~~diff
@@ -46 +46 @@
-    [ "$(jq -r '.incomplete_voices' "$DISPATCHER_JSON")" = "openai/gpt-5.5" ]
+    [ "$(jq -c '.incomplete_voices' "$DISPATCHER_JSON")" = '["openai/gpt-5.5"]' ]   # (PR #1282 F-001: an array, never a joined string)
~~~~

## H103 — tests/unit/bb-exit-degraded-callers.bats — insertion after head line 72

Head context (head/tests/unit/bb-exit-degraded-callers.bats, lines 61–84):

~~~~text
    61 |     [ "$(jq -r '.degraded' "$DISPATCHER_JSON")" = "false" ]
    62 |     [ "$(jq -r 'has("incomplete_voices")' "$DISPATCHER_JSON")" = "false" ]
    63 | }
    64 | 
    65 | @test "dispatcher: any other non-zero exit is still a failure" {
    66 |     make_stub 1
    67 |     run_dispatcher d
    68 |     [ "$status" -eq 1 ]
    69 |     [ "$(jq -r '.bb_exit_code' "$DISPATCHER_JSON")" = "1" ]
    70 |     [ "$(jq -r '.degraded' "$DISPATCHER_JSON")" = "false" ]
    71 | }
    72 | 
    73 | # --- spiral-harness.sh _gate_bridgebuilder ---------------------------------------------------------------------------
    74 | 
    75 | # run_gate <exit_code>: source the harness, point it at a fake skills tree holding the stub, run the gate
    76 | run_gate() {
    77 |     make_stub "$1"
    78 |     mkdir -p "$WORK/fake/scripts" "$WORK/fake/skills/bridgebuilder-review/resources" "$WORK/evidence"
    79 |     cp "$STUB" "$WORK/fake/skills/bridgebuilder-review/resources/entry.sh"
    80 |     run bash -c '
    81 |         cd "$1" || exit 99
    82 |         source "$2/.claude/scripts/spiral-harness.sh"
    83 |         set +e
    84 |         SCRIPT_DIR="$1/fake/scripts"
~~~~

The change from head to the fix:

~~~~diff
@@ -72,0 +73,16 @@
+@test "dispatcher: exit 3 without a run JSON is NOT completed-degraded — ERROR said, degraded false, exit 3 (PR #1282 F-001)" {
+    cat > "$STUB" <<'STUB_EOF'
+#!/usr/bin/env bash
+echo "bridgebuilder: something went wrong before any voice ran" >&2
+exit 3
+STUB_EOF
+    chmod +x "$STUB"
+    run_dispatcher e
+    [ "$status" -eq 3 ]
+    [[ "$output" == *"ERROR: bridgebuilder exited 3 without a run JSON"* ]]
+    [[ "$output" != *"completed DEGRADED"* ]]
+    [ "$(jq -r '.bb_exit_code' "$DISPATCHER_JSON")" = "3" ]
+    [ "$(jq -r '.degraded' "$DISPATCHER_JSON")" = "false" ]
+    [ "$(jq -r 'has("incomplete_voices")' "$DISPATCHER_JSON")" = "false" ]
+}
+
~~~~

## H104 — tests/unit/flatline-locality.bats — head lines 26–27

Head context (head/tests/unit/flatline-locality.bats, lines 14–39):

~~~~text
    14 | setup() {
    15 |     umask 022
    16 |     REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    17 |     source "$REPO/.claude/scripts/flatline-orchestrator.sh"
    18 |     CONFIG_FILE="$BATS_TEST_TMPDIR/loa.config.yaml"
    19 |     unset LOA_HEADLESS_MODE LOA_MODEL_CONFIG
    20 | }
    21 | 
    22 | _cfg() {  # <locality | absent> <primary> <secondary> [tertiary] [extra top-level yaml]
    23 |     {
    24 |         printf 'hounfour:\n'
    25 |         [[ "$1" == absent ]] || printf '  locality: %s\n' "$1"
>   26 |         printf '  providers:\n    localbox:\n      type: openai_compat\n      endpoint: "http://127.0.0.1:8000/v1"\n      models:\n'
>   27 |         printf '        qwen-local:\n          dispatch_group: local\n        qwen-local-b:\n          dispatch_group: local\n'
    28 |         printf '  aliases:\n    lq: "localbox:qwen-local"\n    lqb: "localbox:qwen-local-b"\n'
    29 |         printf 'flatline_protocol:\n  enabled: true\n  models:\n    primary: %s\n    secondary: %s\n' "$2" "$3"
    30 |         [[ -z "${4:-}" ]] || printf '    tertiary: %s\n' "$4"
    31 |         [[ -z "${5:-}" ]] || printf '%s\n' "$5"
    32 |     } > "$CONFIG_FILE"
    33 |     _FLATLINE_LOCALITY_RESULT=""; _CACHED_TERTIARY_MODEL_SET=false; _CACHED_STAGE_ROUTING_SCORER_SET=false
    34 | }
    35 | 
    36 | @test "FLL-1 hosted primary and secondary voices are refused by name; the run is refused" {
    37 |     _cfg local_voices opus gpt-5.5
    38 |     run --separate-stderr flatline_locality_gate
    39 |     [ "$status" -eq 1 ]
~~~~

The change from head to the fix:

~~~~diff
@@ -26,2 +26,8 @@
-        printf '  providers:\n    localbox:\n      type: openai_compat\n      endpoint: "http://127.0.0.1:8000/v1"\n      models:\n'
-        printf '        qwen-local:\n          dispatch_group: local\n        qwen-local-b:\n          dispatch_group: local\n'
+        # a localbox the cheval loader itself admits (LOW-1, r257-1; FLL-9 loads it through loa_cheval.config.loader)
+        printf '  providers:\n    localbox:\n      type: openai_compat\n      endpoint: "http://127.0.0.1:8000/v1"\n'
+        printf '      allow_insecure_endpoint: "127.0.0.1"\n      keyless: true\n      models:\n'
+        local m
+        for m in qwen-local qwen-local-b; do
+            printf '        %s:\n          endpoint_family: chat\n          auth_type: http_api\n' "$m"
+            printf '          context_window: 32768\n          dispatch_group: local\n'
+        done
~~~~

## H105 — tests/unit/flatline-locality.bats — insertion after head line 121

Head context (head/tests/unit/flatline-locality.bats, lines 110–121):

~~~~text
   110 |     [ "$status" -eq 1 ]
   111 |     [ "$(jq -r '.status' <<<"$output")" = "locality_refused" ]
   112 |     [[ "$stderr" == *"refuses hosted hop opus (anthropic)"* ]]
   113 |     _cfg local_voices lq lqb
   114 |     run --separate-stderr bash -c 'source "$1/.claude/scripts/flatline-orchestrator.sh"; CONFIG_FILE="$2"; main --doc "$3" --phase prd --mode red-team --dry-run --json' _ "$REPO" "$CONFIG_FILE" "$doc"
   115 |     [ "$status" -eq 1 ]
   116 |     [[ "$stderr" == *"does not cover the red-team pipeline"* ]]
   117 |     # the local plan passes the gate and reaches the dry run
   118 |     run --separate-stderr bash -c 'source "$1/.claude/scripts/flatline-orchestrator.sh"; CONFIG_FILE="$2"; main --doc "$3" --phase prd --dry-run --json' _ "$REPO" "$CONFIG_FILE" "$doc"
   119 |     [ "$status" -eq 0 ] || { echo "$stderr" | tail; return 1; }
   120 |     [ "$(jq -r '.status' <<<"$output")" = "dry_run" ]
   121 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -121,0 +128,38 @@
+
+@test "FLL-8 a voice labelled dispatch_group local on a hosted DNS endpoint is hosted and refused by name (r257-1)" {
+    _cfg local_voices hb lqb lqc
+    yq -i '.hounfour.providers.hostedbox = {"type": "openai_compat", "endpoint": "https://api.acme.example/v1",
+             "models": {"qwen-hosted": {"dispatch_group": "local"}}}
+           | .hounfour.providers.localbox.models.qwen-local-c = {"dispatch_group": "local"}
+           | .hounfour.providers.localbox.endpoint = "https://api.acme.example/v1"
+           | .hounfour.aliases.hb = "hostedbox:qwen-hosted"
+           | .hounfour.aliases.lqc = "localbox:qwen-local-c"' "$CONFIG_FILE"
+    run python3 -I "$REPO/.claude/scripts/lib/hop-locality.py" --catalog "$REPO/.claude/defaults/model-config.yaml" \
+        --config "$CONFIG_FILE" -- hb lqb
+    [ "$(sed -n 1p <<<"$output" | cut -f2-4)" = "hostedbox	hosted	endpoint_not_local:api.acme.example" ] || { echo "$output"; return 1; }
+    [ "$(sed -n 2p <<<"$output" | cut -f2-4)" = "localbox	hosted	endpoint_not_local:api.acme.example" ]
+    run --separate-stderr flatline_locality_gate
+    [ "$status" -eq 1 ]
+    [[ "$stderr" == *"locality: local_voices refuses hosted hop hb (hostedbox)"* ]] || { echo "$stderr"; return 1; }
+    [[ "$stderr" == *"locality: local_voices refuses hosted hop lqb (localbox)"* ]]
+    [[ "$stderr" == *"refuses a hosted Flatline primary or secondary voice — nothing was dispatched"* ]]
+    # the same voices on the loopback endpoint are planned
+    _cfg local_voices lq lqb
+    flatline_locality_gate 2> "$BATS_TEST_TMPDIR/err"
+    ! grep -q "refuses hosted hop" "$BATS_TEST_TMPDIR/err" || { cat "$BATS_TEST_TMPDIR/err"; return 1; }
+}
+
+@test "FLL-9 the suite's localbox fixture is a provider the cheval loader admits (LOW-1, r257-1)" {
+    _cfg local_voices lq lqb
+    mkdir -p "$BATS_TEST_TMPDIR/proj/.claude/defaults"
+    cp "$REPO/.claude/defaults/model-config.yaml" "$BATS_TEST_TMPDIR/proj/.claude/defaults/"
+    cp "$CONFIG_FILE" "$BATS_TEST_TMPDIR/proj/.loa.config.yaml"
+    run python3 -I -c 'import sys; sys.path.insert(0, sys.argv[2] + "/.claude/adapters")
+from loa_cheval.config.loader import load_config
+merged, _ = load_config(project_root=sys.argv[1])
+p = merged["providers"]["localbox"]
+assert p["keyless"] is True and p["allow_insecure_endpoint"] == "127.0.0.1", p
+print("loaded", " ".join(sorted(p["models"])))' "$BATS_TEST_TMPDIR/proj" "$REPO"
+    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
+    [[ "$output" == *"loaded qwen-local qwen-local-b"* ]]
+}
~~~~
