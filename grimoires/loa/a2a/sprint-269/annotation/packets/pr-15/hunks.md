# Hunks — pr-15

The later fix changed 227 region(s) in 42 of the change's 45 file(s). Line numbers are head-side (the code under review). Each entry shows up to 12 head lines before and after the region; `>` marks a head line the fix changed.

## H01 — .claude/adapters/cheval.py — insertion after head line 18

Head context (head/.claude/adapters/cheval.py, lines 7–30):

~~~~text
     7 |   Exit codes: 0=success, 1=API error, 2=invalid input/config, 3=timeout,
     8 |               4=missing API key, 5=invalid response, 6=budget exceeded, 7=context too large
     9 | """
    10 | 
    11 | from __future__ import annotations
    12 | 
    13 | import argparse
    14 | import datetime
    15 | import hashlib
    16 | import json
    17 | import logging
    18 | import os
    19 | import stat
    20 | import sys
    21 | import traceback
    22 | from dataclasses import dataclass
    23 | from dataclasses import replace as _dc_replace
    24 | from pathlib import Path
    25 | from typing import Any, Dict, List, Optional, Tuple
    26 | 
    27 | # Add the adapters directory to Python path for imports
    28 | _ADAPTERS_DIR = os.path.dirname(os.path.abspath(__file__))
    29 | if _ADAPTERS_DIR not in sys.path:
    30 |     sys.path.insert(0, _ADAPTERS_DIR)
~~~~

The change from head to the fix:

~~~~diff
@@ -18,0 +19 @@
+import shlex
~~~~

## H02 — .claude/adapters/cheval.py — insertion after head line 32

Head context (head/.claude/adapters/cheval.py, lines 21–44):

~~~~text
    21 | import traceback
    22 | from dataclasses import dataclass
    23 | from dataclasses import replace as _dc_replace
    24 | from pathlib import Path
    25 | from typing import Any, Dict, List, Optional, Tuple
    26 | 
    27 | # Add the adapters directory to Python path for imports
    28 | _ADAPTERS_DIR = os.path.dirname(os.path.abspath(__file__))
    29 | if _ADAPTERS_DIR not in sys.path:
    30 |     sys.path.insert(0, _ADAPTERS_DIR)
    31 | 
    32 | from loa_cheval.types import (
    33 |     coerce_headless_timeout_seconds,
    34 |     headless_timeout_note,
    35 |     headless_read_floor,
    36 |     usable_headless_timeout,
    37 |     report_headless_timeout_once,
    38 |     BudgetExceededError,
    39 |     ChevalError,
    40 |     CompletionRequest,
    41 |     ConfigError,
    42 |     AuthRevokedError,
    43 |     ContextTooLargeError,
    44 |     InvalidInputError,
~~~~

The change from head to the fix:

~~~~diff
@@ -32,0 +34 @@
+    EFFORT_LEVELS,
~~~~

## H03 — .claude/adapters/cheval.py — head line 71

Head context (head/.claude/adapters/cheval.py, lines 59–83):

~~~~text
    59 | from loa_cheval.routing.ceiling import (
    60 |     FLOOR_MAX_TOKENS as _FLOOR_MAX_TOKENS,
    61 |     PROBE_COMMAND as _PROBE_COMMAND,
    62 |     GateEstimate as _GateEstimate,
    63 |     fit_max_tokens as _fit_max_tokens,
    64 |     gate as _ceiling_gate,
    65 |     input_bound as _ceiling_input_bound,
    66 |     observed_for as _observed_for,
    67 |     observed_store_path as _observed_store_path,
    68 |     policy_from_env as _ceiling_policy_from_env,
    69 |     record_observed as _ceiling_record_observed,
    70 | )
>   71 | from loa_cheval.providers import cli_adapter_types, get_adapter
    72 | from loa_cheval.providers.base import _legacy_wire, default_max_tokens  # cycle-124 FR-2/FR-4
    73 | from loa_cheval.types import ProviderConfig, ModelConfig
    74 | from loa_cheval.metering.budget import BudgetEnforcer
    75 | 
    76 | # cycle-102 Sprint 1D / T1.7 — MODELINV audit envelope emitter.
    77 | # Lazy at use-site: the import lives at module scope so test runs that exercise
    78 | # cmd_invoke() get the same code path as production, but environments without
    79 | # audit-envelope dependencies see deferred ImportError handled inside the
    80 | # emitter (logs [AUDIT-EMIT-FAILED] and returns).
    81 | from loa_cheval.audit.modelinv import (
    82 |     RedactionFailure as _ModelinvRedactionFailure,
    83 |     emit_model_invoke_complete as _emit_modelinv,
~~~~

The change from head to the fix:

~~~~diff
@@ -71 +73 @@
-from loa_cheval.providers import cli_adapter_types, get_adapter
+from loa_cheval.providers import adapter_class_for_type, cli_adapter_types, get_adapter
~~~~

## H04 — .claude/adapters/cheval.py — insertion after head line 356

Head context (head/.claude/adapters/cheval.py, lines 345–368):

~~~~text
   345 | # Map keyed by provider name (which corresponds to the provider block in
   346 | # model-config.yaml) to the CLI adapter class registered in
   347 | # loa_cheval.providers._ADAPTER_REGISTRY. Adding a new (provider, kind=cli)
   348 | # pair = add a row here + a kind:cli entry in model-config.yaml. No change
   349 | # to chain_resolver or get_adapter needed.
   350 | _CLI_ADAPTER_BY_PROVIDER: Dict[str, str] = {
   351 |     "anthropic": "claude-headless",
   352 |     "openai": "codex-headless",
   353 |     "google": "gemini-headless",
   354 | }
   355 | 
   356 | 
   357 | def _get_adapter_for_entry(entry: Any, hounfour: Dict[str, Any]):
   358 |     """Select the adapter for a single ResolvedEntry honoring `adapter_kind`.
   359 | 
   360 |     For `kind: http` entries, this is `get_adapter(_build_provider_config(...))`
   361 |     — the legacy path that selects via `provider.type`.
   362 | 
   363 |     For `kind: cli` entries, this looks up the CLI adapter type via
   364 |     `_CLI_ADAPTER_BY_PROVIDER[entry.provider]` and constructs it directly
   365 |     against the SAME provider block (so the operator's endpoint / auth
   366 |     declarations are preserved for the HTTP siblings under the same
   367 |     provider, but the CLI adapter never calls `_get_auth_header()`).
   368 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -356,0 +359,63 @@
+def _calibrate_hint(entry: Any, chain_entries: Any) -> Optional[str]:
+    """The ceiling-probe command for a provider size verdict on `entry` (cycle-126 D-1.1b), or None.
+
+    An HTTP hop names itself. A CLI hop carries no ceiling fields — the probe refuses it — so (review r251-3 R4) a
+    claude-headless hop names the chain's Anthropic HTTP entry with `--transport claude-headless` (the transport that
+    measured the payload), and any other CLI hop, or a chain with no such entry, gets no hint: the CLI's own window
+    refused the payload."""
+    # (r251-4 S6, audit n4: the model id is shell-quoted — the hint is a command an operator pastes)
+    if getattr(entry, "adapter_kind", "http") != "cli":
+        return _PROBE_COMMAND.format(model=shlex.quote(str(entry.model_id)))
+    if _CLI_ADAPTER_BY_PROVIDER.get(getattr(entry, "provider", "")) != "claude-headless":
+        return None
+    head = next((e for e in (chain_entries or ())
+                 if getattr(e, "adapter_kind", "http") != "cli" and getattr(e, "provider", "") == entry.provider), None)
+    if head is None:
+        return None
+    return f"{_PROBE_COMMAND.format(model=shlex.quote(str(head.model_id)))} --transport claude-headless"
+
+
+_AGY_NOT_PLANNED_WARNED = False
+
+
+def _entry_routes_to_agy(entry: Any, hounfour: Dict[str, Any]) -> bool:
+    """True when THIS resolved hop would dispatch through agy (cycle-127 review r251-1 G1/G2): the hop is named
+    `gemini-headless` (loader.routes_to_agy, the rule the bash planners share), or it is a kind:cli hop whose CLI adapter
+    is gemini-headless (the Google CLI hop), or its provider block is itself `type: gemini-headless`."""
+    from loa_cheval.config.loader import routes_to_agy
+    if routes_to_agy(getattr(entry, "canonical", "") or ""):
+        return True
+    provider = getattr(entry, "provider", "")
+    ptype = ((hounfour.get("providers") or {}).get(provider) or {}).get("type") if isinstance(hounfour, dict) else None
+    if ptype == "gemini-headless":
+        return True
+    return getattr(entry, "adapter_kind", "http") == "cli" and _CLI_ADAPTER_BY_PROVIDER.get(provider) == "gemini-headless"
+
+
+def _plan_around_agy(chain: Any, hounfour: Dict[str, Any]) -> Tuple[Any, List[Dict[str, Any]]]:
+    """cycle-127 review r251-1 G1 (SDD D-1.3/D-1.6): with hounfour.headless.agy_opt_in off, the agy hops of a chain that
+    also holds another hop are NOT PLANNED — dropped before the walk (never dispatched, never a breaker count, not in
+    models_requested) and returned as `[{model, provider, reason: opt_in_required}]` for MODELINV `models_not_planned`;
+    one WARN per process. A chain that is agy alone (`--model gemini-headless`, or a Google voice under cli-only) is left
+    whole: the operator asked for agy, and the adapter's INVALID_CONFIG refusal is the answer."""
+    global _AGY_NOT_PLANNED_WARNED
+    agy = [e for e in chain.entries if _entry_routes_to_agy(e, hounfour)]
+    if not agy:
+        return chain, []
+    from loa_cheval.config import loader as _loader
+    if _loader.agy_opt_in_enabled():
+        return chain, []
+    _loader.warn_agy_available_once()   # (SDD D-1.7 / r251-1 G18: once per process, a PATH lookup only)
+    if len(agy) == len(chain.entries):
+        return chain, []
+    kept = [e for e in chain.entries if e not in agy]
+    skipped = [{"model": e.canonical, "provider": e.provider, "reason": "opt_in_required"} for e in agy]
+    if not _AGY_NOT_PLANNED_WARNED:
+        _AGY_NOT_PLANNED_WARNED = True
+        logger.warning(
+            "agy hop(s) %s not planned: the agy route is opt-in (hounfour.headless.agy_opt_in is not true) — "
+            "walking the remaining hop(s) %s", ", ".join(x["model"] for x in skipped), ", ".join(e.canonical for e in kept))
+    # (r251-6 V8, BB #4: every other ResolvedChain field is carried, and `entries` keeps its container type)
+    return _dc_replace(chain, entries=type(chain.entries)(kept)), skipped
+
+
~~~~

## H05 — .claude/adapters/cheval.py — head line 783

Head context (head/.claude/adapters/cheval.py, lines 771–795):

~~~~text
   771 |     v3_ceiling = model_config.get("effective_input_ceiling")
   772 |     if isinstance(v3_ceiling, int) and v3_ceiling > 0:
   773 |         # cycle-126 D-1.1: the per-hop bound is the same policy the pre-flight
   774 |         # applies — I1 with this hop's output budget, I2 (probed by default;
   775 |         # calibrated value; derived only under the opt-in), an observed
   776 |         # provider limit, the env guard — never the literal alone, except
   777 |         # under LOA_CHEVAL_LEGACY_CEILING=1 (the module returns the literal).
   778 |         _hop_budget = (
   779 |             max_tokens if isinstance(max_tokens, int) and not isinstance(max_tokens, bool) and max_tokens > 0
   780 |             else _hop_max_tokens(None, provider, model_id, hounfour)
   781 |         )
   782 |         _decision = _ceiling_input_bound(
>  783 |             model_config, max_tokens=_hop_budget, observed=_observed_for(provider, model_id),
   784 |         )
   785 |         _bound = _decision.value if _decision is not None else v3_ceiling
   786 |         if _streaming_killed and provider == "anthropic":
   787 |             return min(_bound, _LEGACY_TRANSPORT_INPUT_WALL)
   788 |         return _bound
   789 | 
   790 |     preferred_field = (
   791 |         "legacy_max_input_tokens" if _streaming_killed
   792 |         else "streaming_max_input_tokens"
   793 |     )
   794 | 
   795 |     threshold = model_config.get(preferred_field)
~~~~

The change from head to the fix:

~~~~diff
@@ -783 +848,2 @@
-            model_config, max_tokens=_hop_budget, observed=_observed_for(provider, model_id),
+            model_config, max_tokens=_hop_budget,
+            observed=_observed_for(provider, model_id, context_window=model_config.get("context_window")),
~~~~

## H06 — .claude/adapters/cheval.py — head line 864

Head context (head/.claude/adapters/cheval.py, lines 852–876):

~~~~text
   852 |     model_max = _lookup_max_output_tokens(provider, model_id, hounfour)
   853 |     if explicit is None:
   854 |         return default_max_tokens(provider=provider, model_max_output=model_max)
   855 |     if model_max is not None and explicit > model_max:
   856 |         logger.warning(
   857 |             "max_tokens %d exceeds %s:%s max_output_tokens %d — clamped",
   858 |             explicit, provider, model_id, model_max,
   859 |         )
   860 |         return model_max
   861 |     return explicit
   862 | 
   863 | 
>  864 | _EFFORT_LEVELS = ("low", "medium", "high", "xhigh", "max")
   865 | # One WARN per (model, reason) per process: an invalid catalog value or an
   866 | # entry setting both rungs is a config smell, not a per-call event.
   867 | _EFFORT_WARNED: set = set()
   868 | 
   869 | 
   870 | def _effort_warn_once(key: Tuple[str, str], msg: str, *fmt: Any) -> None:
   871 |     if key in _EFFORT_WARNED:
   872 |         return
   873 |     _EFFORT_WARNED.add(key)
   874 |     logger.warning(msg, *fmt)
   875 | 
   876 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -864 +930 @@
-_EFFORT_LEVELS = ("low", "medium", "high", "xhigh", "max")
+_EFFORT_LEVELS = EFFORT_LEVELS  # cycle-127 r251-1 C5: defined once in loa_cheval.types
~~~~

## H07 — .claude/adapters/cheval.py — head line 901

Head context (head/.claude/adapters/cheval.py, lines 889–913):

~~~~text
   889 | 
   890 |     One chokepoint, four rungs, first match wins:
   891 |       ``caller``  — an explicit `--effort` (no request-metadata path feeds the
   892 |                     cheval CLI; argparse already validated the level);
   893 |       ``catalog`` — the RESOLVED entry's `params.default_effort` (aliases are
   894 |                     strings and carry no params: `opus` is resolved to
   895 |                     claude-opus-5-5 before this is called);
   896 |       ``extra``   — a CLI entry's legacy `extra.effort` / `extra.reasoning_effort`
   897 |                     (the headless adapter's own rung; HTTP entries never read it);
   898 |       ``none``    — nothing on the wire, the vendor default applies.
   899 |     The catalog is not schema-validated at load, so an invalid `default_effort`
   900 |     is skipped with one WARN (never a crash); an entry setting both
>  901 |     `params.default_effort` and `extra.effort` gets one WARN too.
   902 |     """
   903 |     explicit = getattr(args, "effort", None)
   904 |     entry = entry if isinstance(entry, dict) else {}
   905 |     params = entry.get("params") if isinstance(entry.get("params"), dict) else {}
   906 |     extra = entry.get("extra") if isinstance(entry.get("extra"), dict) else {}
   907 |     extra_raw = extra.get("effort") or extra.get("reasoning_effort")
   908 |     if "default_effort" in params and extra_raw:
   909 |         _effort_warn_once((model_key, "both"),
   910 |                           "%s sets both params.default_effort and extra.effort; params.default_effort wins "
   911 |                           "(cycle-127 FR-2) — drop one", model_key)
   912 |     if explicit:
   913 |         return explicit, "caller"
~~~~

The change from head to the fix:

~~~~diff
@@ -901 +967,2 @@
-    `params.default_effort` and `extra.effort` gets one WARN too.
+    `params.default_effort` and `extra.effort` gets one WARN too — a CLI entry only,
+    the one whose extra rung is read (r251-6 V7).
~~~~

## H08 — .claude/adapters/cheval.py — head line 908

Head context (head/.claude/adapters/cheval.py, lines 896–920):

~~~~text
   896 |       ``extra``   — a CLI entry's legacy `extra.effort` / `extra.reasoning_effort`
   897 |                     (the headless adapter's own rung; HTTP entries never read it);
   898 |       ``none``    — nothing on the wire, the vendor default applies.
   899 |     The catalog is not schema-validated at load, so an invalid `default_effort`
   900 |     is skipped with one WARN (never a crash); an entry setting both
   901 |     `params.default_effort` and `extra.effort` gets one WARN too.
   902 |     """
   903 |     explicit = getattr(args, "effort", None)
   904 |     entry = entry if isinstance(entry, dict) else {}
   905 |     params = entry.get("params") if isinstance(entry.get("params"), dict) else {}
   906 |     extra = entry.get("extra") if isinstance(entry.get("extra"), dict) else {}
   907 |     extra_raw = extra.get("effort") or extra.get("reasoning_effort")
>  908 |     if "default_effort" in params and extra_raw:
   909 |         _effort_warn_once((model_key, "both"),
   910 |                           "%s sets both params.default_effort and extra.effort; params.default_effort wins "
   911 |                           "(cycle-127 FR-2) — drop one", model_key)
   912 |     if explicit:
   913 |         return explicit, "caller"
   914 |     if "default_effort" in params:
   915 |         value = _valid_effort(params["default_effort"])
   916 |         if value is not None:
   917 |             return value, "catalog"
   918 |         _effort_warn_once((model_key, "invalid"),
   919 |                           "%s: params.default_effort %r is not one of %s — ignored (cycle-127 FR-2)",
   920 |                           model_key, params["default_effort"], ", ".join(_EFFORT_LEVELS))
~~~~

The change from head to the fix:

~~~~diff
@@ -908 +975,2 @@
-    if "default_effort" in params and extra_raw:
+    # (r251-6 V7, BB #10: only a CLI entry reads the extra rung — on an HTTP entry it is inert, so there is no conflict)
+    if "default_effort" in params and extra_raw and _is_cli_entry(entry):
~~~~

## H09 — .claude/adapters/cheval.py — head lines 921–924

Head context (head/.claude/adapters/cheval.py, lines 909–936):

~~~~text
   909 |         _effort_warn_once((model_key, "both"),
   910 |                           "%s sets both params.default_effort and extra.effort; params.default_effort wins "
   911 |                           "(cycle-127 FR-2) — drop one", model_key)
   912 |     if explicit:
   913 |         return explicit, "caller"
   914 |     if "default_effort" in params:
   915 |         value = _valid_effort(params["default_effort"])
   916 |         if value is not None:
   917 |             return value, "catalog"
   918 |         _effort_warn_once((model_key, "invalid"),
   919 |                           "%s: params.default_effort %r is not one of %s — ignored (cycle-127 FR-2)",
   920 |                           model_key, params["default_effort"], ", ".join(_EFFORT_LEVELS))
>  921 |     if _is_cli_entry(entry) and extra_raw:
>  922 |         value = _valid_effort(str(extra_raw).strip().lower())
>  923 |         if value is not None:
>  924 |             return value, "extra"
   925 |     return None, "none"
   926 | 
   927 | 
   928 | def _effort_on_wire(provider: str, model_id: str, effort: Optional[str], hounfour: Dict[str, Any]) -> Optional[str]:
   929 |     """What the dispatched hop puts on the wire for `effort` (cycle-127 D-2.6):
   930 |     the Anthropic HTTP adapter's per-family mapping (`xhigh` → `high` on
   931 |     4.6, omitted on Sonnet/Haiku 4.5); a CLI hop passes it through; other
   932 |     providers' adapters do not read CompletionRequest.effort (None)."""
   933 |     if effort is None:
   934 |         return None
   935 |     if _is_cli_entry(_raw_model_entry(provider, model_id, hounfour)):
   936 |         return effort
~~~~

The change from head to the fix:

~~~~diff
@@ -921,4 +989,13 @@
-    if _is_cli_entry(entry) and extra_raw:
-        value = _valid_effort(str(extra_raw).strip().lower())
-        if value is not None:
-            return value, "extra"
+    if _is_cli_entry(entry):
+        # (review r251-1 G7: both keys, in the headless adapter's order — an invalid one is said once and does not hide
+        # a valid one after it)
+        for _key in ("effort", "reasoning_effort"):
+            _raw = extra.get(_key)
+            if not _raw:
+                continue
+            value = _valid_effort(str(_raw).strip().lower())
+            if value is not None:
+                return value, "extra"
+            _effort_warn_once((model_key, f"invalid_extra_{_key}"),
+                              "%s: extra.%s %r is not one of %s — ignored (cycle-127 FR-2)",
+                              model_key, _key, _raw, ", ".join(_EFFORT_LEVELS))
~~~~

## H10 — .claude/adapters/cheval.py — head lines 932–940

Head context (head/.claude/adapters/cheval.py, lines 920–952):

~~~~text
   920 |                           model_key, params["default_effort"], ", ".join(_EFFORT_LEVELS))
   921 |     if _is_cli_entry(entry) and extra_raw:
   922 |         value = _valid_effort(str(extra_raw).strip().lower())
   923 |         if value is not None:
   924 |             return value, "extra"
   925 |     return None, "none"
   926 | 
   927 | 
   928 | def _effort_on_wire(provider: str, model_id: str, effort: Optional[str], hounfour: Dict[str, Any]) -> Optional[str]:
   929 |     """What the dispatched hop puts on the wire for `effort` (cycle-127 D-2.6):
   930 |     the Anthropic HTTP adapter's per-family mapping (`xhigh` → `high` on
   931 |     4.6, omitted on Sonnet/Haiku 4.5); a CLI hop passes it through; other
>  932 |     providers' adapters do not read CompletionRequest.effort (None)."""
>  933 |     if effort is None:
>  934 |         return None
>  935 |     if _is_cli_entry(_raw_model_entry(provider, model_id, hounfour)):
>  936 |         return effort
>  937 |     if provider == "anthropic":
>  938 |         from loa_cheval.providers.anthropic_adapter import _effort_for_model
>  939 |         return _effort_for_model(model_id, effort)
>  940 |     return None
   941 | 
   942 | 
   943 | def _entry_thinking_class(entry: Any, hounfour: Dict[str, Any]) -> bool:
   944 |     """True iff this hop's model reasons before answering (cycle-124 FR-1).
   945 | 
   946 |     Two catalog shapes mean "thinking on": `params.thinking_adaptive: true`
   947 |     (the 4.6–4.8 family and Opus 5 / Sonnet 5, where the adapter requests it)
   948 |     and `params.temperature_supported: false` without the flag (Fable 5 /
   949 |     5.1, where thinking is always on and the param must be omitted).
   950 |     """
   951 |     try:
   952 |         models = (hounfour.get("providers", {}) or {}).get(entry.provider, {}).get("models", {}) or {}
~~~~

The change from head to the fix:

~~~~diff
@@ -932,9 +1009,26 @@
-    providers' adapters do not read CompletionRequest.effort (None)."""
+    providers' adapters do not read CompletionRequest.effort (None).
+
+    r251-1 C5: adapter-derived. The adapter type is selected the way dispatch
+    selects it (`_get_adapter_for_entry`: a kind:cli entry → the provider's
+    CLI adapter; otherwise ``providers.<key>.type``, falling back to the key
+    for a block without ``type``), and that adapter's ``wire_effort`` hook
+    answers from its own resolver — the Anthropic HTTP mapping, claude-headless
+    `--effort`, codex/grok only their extra.reasoning_effort, the rest None."""
     if effort is None:
         return None
+    cls = adapter_class_for_type(_adapter_type_for(provider, model_id, hounfour))
+    if cls is None:
+        return None
+    extra = _raw_model_entry(provider, model_id, hounfour).get("extra")
+    return cls.wire_effort(model_id, effort, extra if isinstance(extra, dict) else None)
+
+
+def _adapter_type_for(provider: str, model_id: str, hounfour: Dict[str, Any]) -> str:
+    """The adapter registry type a (provider, model) dispatches through — the
+    same selection as `_get_adapter_for_entry` without building a config."""
+    prov = (hounfour.get("providers", {}) or {}).get(provider, {}) if isinstance(hounfour, dict) else {}
+    ptype = prov.get("type") if isinstance(prov, dict) else None
+    ptype = ptype if isinstance(ptype, str) and ptype else provider
     if _is_cli_entry(_raw_model_entry(provider, model_id, hounfour)):
-        return effort
-    if provider == "anthropic":
-        from loa_cheval.providers.anthropic_adapter import _effort_for_model
-        return _effort_for_model(model_id, effort)
-    return None
+        return _CLI_ADAPTER_BY_PROVIDER.get(provider) or ptype
+    return ptype
~~~~

## H11 — .claude/adapters/cheval.py — insertion after head line 1228

Head context (head/.claude/adapters/cheval.py, lines 1217–1240):

~~~~text
  1217 |     case). Single-entry exhaustion falls back to the last error_class
  1218 |     mapping so the reason captures the actual root cause.
  1219 |     """
  1220 |     if succeeded:
  1221 |         return "Other"  # caller MUST NOT consult reason when succeeded
  1222 |     if not models_failed:
  1223 |         return "Other"
  1224 |     # Multi-entry walked entirely → ChainExhausted is the canonical reason.
  1225 |     if chain_size >= 2:
  1226 |         return "ChainExhausted"
  1227 |     # Single-entry chain: use the last recorded error_class mapping.
  1228 |     last_class = str(models_failed[-1].get("error_class") or "UNKNOWN")
  1229 |     return _VQ_ERROR_CLASS_TO_REASON.get(last_class, "Other")
  1230 | 
  1231 | 
  1232 | def _vq_derive_chain_health(
  1233 |     *,
  1234 |     succeeded: bool,
  1235 |     final_model_id: Optional[str],
  1236 |     primary_canonical: Optional[str],
  1237 | ) -> str:
  1238 |     """``ok`` = primary chain entry succeeded; ``degraded`` = walked to a
  1239 |     fallback that succeeded; ``exhausted`` = no entry succeeded."""
  1240 |     if not succeeded:
~~~~

The change from head to the fix:

~~~~diff
@@ -1228,0 +1323,2 @@
+    if models_failed[-1].get("failure_class") == "opt_in_required":
+        return "OptInRequired"   # (cycle-127 review r251-2 K2: the agy route refused by its opt-in, not "Other")
~~~~

## H12 — .claude/adapters/cheval.py — head lines 1693–1694

Head context (head/.claude/adapters/cheval.py, lines 1681–1706):

~~~~text
  1681 |         logger.warning(
  1682 |             "[CYCLE-110-WIRE-UP-DEGRADED] dispatch_filter module not "
  1683 |             "found (%s) — falling back to pre-cycle-110 chain behavior. "
  1684 |             "advisor_strategy.dispatch_preference is ignored on this "
  1685 |             "invocation. Run substrate doctor to verify install state.",
  1686 |             _exc,
  1687 |         )
  1688 | 
  1689 |     # cycle-102 Sprint 1D / T1.7 + cycle-104 Sprint 2 T2.6: MODELINV emit-state.
  1690 |     # The finally-clause emits a single envelope at function exit (success or
  1691 |     # failure). Pre-resolution failures (handled above) deliberately do NOT
  1692 |     # emit because no model invocation occurred. `models_requested` enumerates
> 1693 |     # the entire resolved chain so audit consumers see the FULL intended walk
> 1694 |     # shape, not just whichever entry happened to succeed.
  1695 |     _modelinv_capability_class = getattr(binding, "capability_class", None)
  1696 |     _modelinv_models_requested = [e.canonical for e in _chain.entries]
  1697 |     _modelinv_state: Dict[str, Any] = {
  1698 |         "models_succeeded": [],
  1699 |         "models_failed": [],
  1700 |         "operator_visible_warn": False,
  1701 |         "invocation_latency_ms": None,
  1702 |         "cost_micro_usd": None,
  1703 |         # cycle-103 T3.2 / AC-3.2: observed-streaming. None = adapter didn't
  1704 |         # report → emit falls back to env-derived value. True/False = actual
  1705 |         # transport observed on this call.
  1706 |         "streaming": None,
~~~~

The change from head to the fix:

~~~~diff
@@ -1693,2 +1789,7 @@
-    # the entire resolved chain so audit consumers see the FULL intended walk
-    # shape, not just whichever entry happened to succeed.
+    # the PLANNED chain — every hop the walk may dispatch, not just whichever
+    # entry happened to succeed; `models_requested` ∪ `models_not_planned` is
+    # the full resolved chain (cycle-127 review r251-1 G1: a gated agy hop is
+    # planned around before models_requested is taken; r251-4 S8, audit n2).
+    _chain, _models_not_planned = _plan_around_agy(_chain, hounfour)
+    if _models_not_planned and _auth_type_resolved is not None:
+        _auth_type_resolved = _chain.entries[0].auth_type
~~~~

## H13 — .claude/adapters/cheval.py — head line 1962

Head context (head/.claude/adapters/cheval.py, lines 1950–1974):

~~~~text
  1950 |                         return None
  1951 |             _preflight_outcome = _ceiling_gate(
  1952 |                 dict(_preflight_head_cfg, model_id=_preflight_head.model_id),
  1953 |                 estimate=_GateEstimate(
  1954 |                     tokens=_preflight_estimated, method=_preflight_est_obj.method,
  1955 |                     uncertainty=_preflight_est_obj.uncertainty, chars=_preflight_est_obj.chars,
  1956 |                 ),
  1957 |                 requested_max_tokens=base_request.max_tokens,
  1958 |                 cli_override=(
  1959 |                     _preflight_cli_override
  1960 |                     if isinstance(_preflight_cli_override, int) and _preflight_cli_override > 0 else None
  1961 |                 ),
> 1962 |                 observed=_observed_for(_preflight_head.provider, _preflight_head.model_id),
  1963 |                 policy=_ceiling_policy,
  1964 |                 counter=_counter,
  1965 |             )
  1966 |             _preflight_estimated = _preflight_outcome.estimate.tokens
  1967 |             _walk_estimate = _preflight_estimated
  1968 |             _ceiling_unverified = _preflight_outcome.unverified
  1969 |             if _preflight_outcome.shrunk_from is not None:
  1970 |                 base_request.max_tokens = _preflight_outcome.max_tokens
  1971 |             if _preflight_outcome.action == "preempt":
  1972 |                 _preflight_decision = PreflightDecision(
  1973 |                     action="preempt",
  1974 |                     exit_code=EXIT_CODES["CONTEXT_TOO_LARGE"],
~~~~

The change from head to the fix:

~~~~diff
@@ -1962 +2063,2 @@
-                observed=_observed_for(_preflight_head.provider, _preflight_head.model_id),
+                observed=_observed_for(_preflight_head.provider, _preflight_head.model_id,
+                                       context_window=_preflight_head_cfg.get("context_window")),
~~~~

## H14 — .claude/adapters/cheval.py — insertion after head line 2070

Head context (head/.claude/adapters/cheval.py, lines 2059–2082):

~~~~text
  2059 |             # later), so emit a minimal self-contained envelope directly from the
  2060 |             # 4 required fields + the pre-flight capability context. Fail-soft:
  2061 |             # an emitter error must NEVER mask the exit-7 result.
  2062 |             try:
  2063 |                 _emit_modelinv(
  2064 |                     models_requested=_modelinv_models_requested,
  2065 |                     models_succeeded=_modelinv_state["models_succeeded"],
  2066 |                     models_failed=_modelinv_state["models_failed"],
  2067 |                     operator_visible_warn=_modelinv_state["operator_visible_warn"],
  2068 |                     capability_class=_modelinv_capability_class,
  2069 |                     capability_evaluation=_modelinv_state.get("capability_evaluation"),
  2070 |                     calling_primitive=(getattr(args, "skill", None) or agent_name),
  2071 |                 )
  2072 |             except Exception as _emit_err:  # noqa: BLE001 — fail-soft; never mask exit 7
  2073 |                 print(
  2074 |                     f"[AUDIT-EMIT-FAILED] {type(_emit_err).__name__}: {_emit_err}",
  2075 |                     file=sys.stderr,
  2076 |                 )
  2077 |             return EXIT_CODES["CONTEXT_TOO_LARGE"]
  2078 | 
  2079 |         # #937 / sprint-bug-211: the chunked-dispatch branch (action=="chunk")
  2080 |         # was removed here — it was permanently unreachable (no production
  2081 |         # caller set effective_input_ceiling) and fail-closed by design. The
  2082 |         # only MODELINV emit is now the finally-block below (single site;
~~~~

The change from head to the fix:

~~~~diff
@@ -2070,0 +2173 @@
+                    models_not_planned=_models_not_planned or None,
~~~~

## H15 — .claude/adapters/cheval.py — head lines 2137–2141

Head context (head/.claude/adapters/cheval.py, lines 2125–2153):

~~~~text
  2125 |         it is never walked (the next voice would get the same payload). The
  2126 |         observation is appended to `.run/ceiling-observed.json` (only the two
  2127 |         context classes lower the bound; a 429 while unverified is recorded
  2128 |         without lowering it), the envelope carries `calibration_needed`, and
  2129 |         the operator sees the probe command."""
  2130 |         nonlocal _last_walk_exit_code
  2131 |         # audit sprint-247: the provider's text is sanitised at the adapter already; pass it
  2132 |         # through the redaction helper again here (defence in depth) before it is recorded
  2133 |         # under `message_redacted` or printed.
  2134 |         from loa_cheval.redaction import sanitize_provider_error_message as _sanitize
  2135 |         _msg = _sanitize(str(_exc))
  2136 |         _obs = int(observed) if isinstance(observed, int) and observed > 0 else int(_walk_estimate or 0)
> 2137 |         try:
> 2138 |             _ceiling_record_observed(
> 2139 |                 provider=_entry.provider, model=_entry.model_id, observed_input_tokens=_obs,
> 2140 |                 error_class=error_class, estimated_input_tokens=_walk_estimate, provider_limit=provider_limit,
> 2141 |             )
  2142 |         except Exception as _rec_err:  # noqa: BLE001 — the record must never mask the typed exit
  2143 |             print(f"[preflight] observed-bound record failed: {type(_rec_err).__name__}", file=sys.stderr)
  2144 |         _calib = {
  2145 |             "provider": _entry.provider, "model": _entry.model_id, "observed_input_tokens": _obs,
  2146 |             "provider_limit": provider_limit, "error_class": error_class,
  2147 |             "calibrate": _PROBE_COMMAND.format(model=_entry.model_id), "store": _observed_store_path(),
  2148 |         }
  2149 |         if isinstance(_modelinv_state.get("capability_evaluation"), dict):
  2150 |             _modelinv_state["capability_evaluation"]["calibration_needed"] = _calib
  2151 |         _modelinv_state["models_failed"].append({
  2152 |             "model": _entry_target, "provider": _entry.provider, "error_class": error_class,
  2153 |             "message_redacted": _msg, "observed_input_tokens": _obs, "provider_limit": provider_limit,
~~~~

The change from head to the fix:

~~~~diff
@@ -2137,5 +2240,9 @@
+        # cycle-127 review r251-2 K8: a CLI hop's size rejection is the CLI's own pre-flight against ITS window — it
+        # carries no HTTP ceiling, so it is not recorded as an observation (it would lower the HTTP route's bound).
+        _record = getattr(_entry, "adapter_kind", "http") != "cli"
         try:
-            _ceiling_record_observed(
-                provider=_entry.provider, model=_entry.model_id, observed_input_tokens=_obs,
-                error_class=error_class, estimated_input_tokens=_walk_estimate, provider_limit=provider_limit,
-            )
+            if _record:
+                _ceiling_record_observed(
+                    provider=_entry.provider, model=_entry.model_id, observed_input_tokens=_obs,
+                    error_class=error_class, estimated_input_tokens=_walk_estimate, provider_limit=provider_limit,
+                )
~~~~

## H16 — .claude/adapters/cheval.py — head line 2147

Head context (head/.claude/adapters/cheval.py, lines 2135–2159):

~~~~text
  2135 |         _msg = _sanitize(str(_exc))
  2136 |         _obs = int(observed) if isinstance(observed, int) and observed > 0 else int(_walk_estimate or 0)
  2137 |         try:
  2138 |             _ceiling_record_observed(
  2139 |                 provider=_entry.provider, model=_entry.model_id, observed_input_tokens=_obs,
  2140 |                 error_class=error_class, estimated_input_tokens=_walk_estimate, provider_limit=provider_limit,
  2141 |             )
  2142 |         except Exception as _rec_err:  # noqa: BLE001 — the record must never mask the typed exit
  2143 |             print(f"[preflight] observed-bound record failed: {type(_rec_err).__name__}", file=sys.stderr)
  2144 |         _calib = {
  2145 |             "provider": _entry.provider, "model": _entry.model_id, "observed_input_tokens": _obs,
  2146 |             "provider_limit": provider_limit, "error_class": error_class,
> 2147 |             "calibrate": _PROBE_COMMAND.format(model=_entry.model_id), "store": _observed_store_path(),
  2148 |         }
  2149 |         if isinstance(_modelinv_state.get("capability_evaluation"), dict):
  2150 |             _modelinv_state["capability_evaluation"]["calibration_needed"] = _calib
  2151 |         _modelinv_state["models_failed"].append({
  2152 |             "model": _entry_target, "provider": _entry.provider, "error_class": error_class,
  2153 |             "message_redacted": _msg, "observed_input_tokens": _obs, "provider_limit": provider_limit,
  2154 |         })
  2155 |         _modelinv_state["operator_visible_warn"] = True
  2156 |         print(
  2157 |             f"[preflight] calibration_needed model={_entry_target} class={error_class} "
  2158 |             f"observed_input_tokens={_obs} — not walked (cycle-126 D-1.1b); run: {_calib['calibrate']}",
  2159 |             file=sys.stderr,
~~~~

The change from head to the fix:

~~~~diff
@@ -2147 +2254,2 @@
-            "calibrate": _PROBE_COMMAND.format(model=_entry.model_id), "store": _observed_store_path(),
+            "calibrate": _calibrate_hint(_entry, _chain.entries), "store": _observed_store_path(),
+            "observation_recorded": _record,
~~~~

## H17 — .claude/adapters/cheval.py — head lines 2156–2158

Head context (head/.claude/adapters/cheval.py, lines 2144–2170):

~~~~text
  2144 |         _calib = {
  2145 |             "provider": _entry.provider, "model": _entry.model_id, "observed_input_tokens": _obs,
  2146 |             "provider_limit": provider_limit, "error_class": error_class,
  2147 |             "calibrate": _PROBE_COMMAND.format(model=_entry.model_id), "store": _observed_store_path(),
  2148 |         }
  2149 |         if isinstance(_modelinv_state.get("capability_evaluation"), dict):
  2150 |             _modelinv_state["capability_evaluation"]["calibration_needed"] = _calib
  2151 |         _modelinv_state["models_failed"].append({
  2152 |             "model": _entry_target, "provider": _entry.provider, "error_class": error_class,
  2153 |             "message_redacted": _msg, "observed_input_tokens": _obs, "provider_limit": provider_limit,
  2154 |         })
  2155 |         _modelinv_state["operator_visible_warn"] = True
> 2156 |         print(
> 2157 |             f"[preflight] calibration_needed model={_entry_target} class={error_class} "
> 2158 |             f"observed_input_tokens={_obs} — not walked (cycle-126 D-1.1b); run: {_calib['calibrate']}",
  2159 |             file=sys.stderr,
  2160 |         )
  2161 |         print(_error_json(
  2162 |             _exc.code,
  2163 |             f"{_msg} — not walked: the same payload would fail the next voice; calibrate: {_calib['calibrate']}",
  2164 |             retryable=False, calibration_needed=True, error_class=error_class,
  2165 |             observed_input_tokens=_obs, provider_limit=provider_limit,
  2166 |         ), file=sys.stderr)
  2167 |         _last_walk_exit_code = exit_code
  2168 |         return exit_code
  2169 | 
  2170 |     try:
~~~~

The change from head to the fix:

~~~~diff
@@ -2156,3 +2264,7 @@
+        # (review r251-3 R4: a CLI hop with no HTTP entry to calibrate gets no probe command — the CLI's window refused it)
+        _remedy = (f"calibrate: {_calib['calibrate']}" if _calib["calibrate"]
+                   else "the CLI's own window refused the payload (no catalog ceiling to calibrate)")
         print(
             f"[preflight] calibration_needed model={_entry_target} class={error_class} "
-            f"observed_input_tokens={_obs} — not walked (cycle-126 D-1.1b); run: {_calib['calibrate']}",
+            f"observed_input_tokens={_obs} — not walked (cycle-126 D-1.1b); "
+            + (f"run: {_calib['calibrate']}" if _calib["calibrate"] else _remedy),
~~~~

## H18 — .claude/adapters/cheval.py — head line 2163

Head context (head/.claude/adapters/cheval.py, lines 2151–2175):

~~~~text
  2151 |         _modelinv_state["models_failed"].append({
  2152 |             "model": _entry_target, "provider": _entry.provider, "error_class": error_class,
  2153 |             "message_redacted": _msg, "observed_input_tokens": _obs, "provider_limit": provider_limit,
  2154 |         })
  2155 |         _modelinv_state["operator_visible_warn"] = True
  2156 |         print(
  2157 |             f"[preflight] calibration_needed model={_entry_target} class={error_class} "
  2158 |             f"observed_input_tokens={_obs} — not walked (cycle-126 D-1.1b); run: {_calib['calibrate']}",
  2159 |             file=sys.stderr,
  2160 |         )
  2161 |         print(_error_json(
  2162 |             _exc.code,
> 2163 |             f"{_msg} — not walked: the same payload would fail the next voice; calibrate: {_calib['calibrate']}",
  2164 |             retryable=False, calibration_needed=True, error_class=error_class,
  2165 |             observed_input_tokens=_obs, provider_limit=provider_limit,
  2166 |         ), file=sys.stderr)
  2167 |         _last_walk_exit_code = exit_code
  2168 |         return exit_code
  2169 | 
  2170 |     try:
  2171 |         for _idx, _entry in enumerate(_chain.entries):
  2172 |             _entry_target = _entry.canonical
  2173 | 
  2174 |             # 1. Capability gate — skip-and-walk per cycle-104 §1.4.2 contract.
  2175 |             #    A request that needs `tools` against a chat-only headless
~~~~

The change from head to the fix:

~~~~diff
@@ -2163 +2275 @@
-            f"{_msg} — not walked: the same payload would fail the next voice; calibrate: {_calib['calibrate']}",
+            f"{_msg} — not walked: the same payload would fail the next voice; {_remedy}",
~~~~

## H19 — .claude/adapters/cheval.py — head line 2255

Head context (head/.claude/adapters/cheval.py, lines 2243–2267):

~~~~text
  2243 |             # bound" is a property of THIS hop's entry and budget, never
  2244 |             # inherited from the head — a fallback whose bound is calibrated
  2245 |             # (or larger) runs the same payload verified, so its 429 walks and
  2246 |             # its provider verdict is the catalog's error, not an unverified one.
  2247 |             _hop_unverified = False
  2248 |             if (
  2249 |                 _ceiling_policy == "derived"
  2250 |                 and any(k in _hop_entry for k in ("effective_input_ceiling", "probed_ceiling"))
  2251 |                 and not os.environ.get("LOA_CHEVAL_DISABLE_INPUT_GATE")
  2252 |             ):
  2253 |                 _hop_decision = _ceiling_input_bound(
  2254 |                     _hop_entry, max_tokens=_hop_budget,
> 2255 |                     observed=_observed_for(_entry.provider, _entry.model_id), policy=_ceiling_policy,
  2256 |                 )
  2257 |                 if _hop_decision is not None and not _hop_decision.calibrated and _hop_decision.probed:
  2258 |                     _hop_unverified = (_walk_estimate or 0) > _hop_decision.probed
  2259 | 
  2260 |             if not os.environ.get("LOA_CHEVAL_DISABLE_INPUT_GATE"):
  2261 |                 _input_threshold = _lookup_max_input_tokens(
  2262 |                     _entry.provider, _entry.model_id, hounfour,
  2263 |                     cli_override=getattr(args, "max_input_tokens", None),
  2264 |                     max_tokens=_hop_budget,
  2265 |                 )
  2266 |                 if _input_threshold is not None:
  2267 |                     from loa_cheval.providers.base import estimate_tokens
~~~~

The change from head to the fix:

~~~~diff
@@ -2255 +2367,2 @@
-                    observed=_observed_for(_entry.provider, _entry.model_id), policy=_ceiling_policy,
+                    observed=_observed_for(_entry.provider, _entry.model_id, context_window=_hop_entry.get("context_window")),
+                    policy=_ceiling_policy,
~~~~

## H20 — .claude/adapters/cheval.py — head lines 2546–2552

Head context (head/.claude/adapters/cheval.py, lines 2534–2564):

~~~~text
  2534 |                     "message_redacted": str(_e),
  2535 |                 })
  2536 |                 _last_walk_exit_code = EXIT_CODES["AUTH_REVOKED"]
  2537 |                 _last_walk_exception = _e
  2538 |                 if _verbose:
  2539 |                     print(
  2540 |                         f"[cheval] fallback {_entry_target} -> next (auth_revoked)",
  2541 |                         file=sys.stderr,
  2542 |                     )
  2543 |                 continue
  2544 |             except ChevalError as _e:
  2545 |                 # Non-retryable typed cheval error — surface immediately.
> 2546 |                 _modelinv_state["models_failed"].append({
> 2547 |                     "model": _entry_target,
> 2548 |                     "provider": _entry.provider,
> 2549 |                     "error_class": "UNKNOWN",
> 2550 |                     "message_redacted": str(_e),
> 2551 |                 })
> 2552 |                 print(_error_json(_e.code, str(_e), retryable=_e.retryable), file=sys.stderr)
  2553 |                 return EXIT_CODES.get(_e.code, 1)
  2554 |             except Exception as _e:  # noqa: BLE001
  2555 |                 # Catch-all: redact known env-var secrets before recording.
  2556 |                 # Sets retryable=True in operator JSON to keep cycle-102
  2557 |                 # behavior for unexpected errors.
  2558 |                 _msg = str(_e)
  2559 |                 for _env_key in [
  2560 |                     "OPENAI_API_KEY", "ANTHROPIC_API_KEY",
  2561 |                     "MOONSHOT_API_KEY", "GOOGLE_API_KEY",
  2562 |                 ]:
  2563 |                     _val = os.environ.get(_env_key)
  2564 |                     if _val and _val in _msg:
~~~~

The change from head to the fix:

~~~~diff
@@ -2546,7 +2659,22 @@
-                _modelinv_state["models_failed"].append({
-                    "model": _entry_target,
-                    "provider": _entry.provider,
-                    "error_class": "UNKNOWN",
-                    "message_redacted": str(_e),
-                })
-                print(_error_json(_e.code, str(_e), retryable=_e.retryable), file=sys.stderr)
+                _fc = (getattr(_e, "context", None) or {}).get("failure_class")
+                if _fc == "opt_in_required":
+                    # cycle-127 review r251-1 G1/G5, r251-2 K2: agy asked for by name (the chain is agy alone) with the
+                    # opt-in off — dispatched to the adapter, which refused before any discovery or spawn. The operator
+                    # asked for it, so it stays in models_requested and is a failed hop with its typed class; it is NOT
+                    # models_not_planned (that list holds only the hops _plan_around_agy dropped before the walk).
+                    _modelinv_state["models_failed"].append({
+                        "model": _entry_target,
+                        "provider": _entry.provider,
+                        "error_class": "INVALID_CONFIG",
+                        "failure_class": _fc,
+                        "message_redacted": str(_e),
+                    })
+                else:
+                    _modelinv_state["models_failed"].append({
+                        "model": _entry_target,
+                        "provider": _entry.provider,
+                        "error_class": "UNKNOWN",
+                        "message_redacted": str(_e),
+                    })
+                print(_error_json(_e.code, str(_e), retryable=_e.retryable,
+                                  **({"failure_class": _fc} if isinstance(_fc, str) and _fc else {})), file=sys.stderr)
~~~~

## H21 — .claude/adapters/cheval.py — insertion after head line 2813

Head context (head/.claude/adapters/cheval.py, lines 2802–2825):

~~~~text
  2802 |                     f"[verdict-quality-build-failed] "
  2803 |                     f"{type(_vqe).__name__}: {_vqe}",
  2804 |                     file=sys.stderr,
  2805 |                 )
  2806 | 
  2807 |             # cycle-109 Sprint 2 T2.4 — sidecar transport for FL CONSUMER #2.
  2808 |             # When LOA_VERDICT_QUALITY_SIDECAR is set, write the envelope JSON
  2809 |             # to that path so flatline-orchestrator.sh (and other bash callers)
  2810 |             # can read it back without scraping the shared MODELINV log under
  2811 |             # parallel-dispatch races. Fail-soft; no-op when env var unset.
  2812 |             _vq_write_sidecar(_vq_envelope)
  2813 | 
  2814 |             try:
  2815 |                 _emit_modelinv(
  2816 |                     models_requested=_modelinv_models_requested,
  2817 |                     models_succeeded=_modelinv_state["models_succeeded"],
  2818 |                     models_failed=_modelinv_state["models_failed"],
  2819 |                     operator_visible_warn=_modelinv_state["operator_visible_warn"],
  2820 |                     capability_class=_modelinv_capability_class,
  2821 |                     # Cycle-112 D-6 (#931): propagate caller identity for
  2822 |                     # /loa status --economy attribution. Same fallback chain
  2823 |                     # as the chunked-path emit above.
  2824 |                     calling_primitive=(getattr(args, "skill", None) or agent_name),
  2825 |                     invocation_latency_ms=_modelinv_state["invocation_latency_ms"],
~~~~

The change from head to the fix:

~~~~diff
@@ -2813,0 +2942,15 @@
+            # cycle-127 D-2.6: the wire value on the hop that answered (the primary when none did), from that adapter's
+            # wire_effort hook (r251-1 C5). r251-4 S8 (audit n29/n30): evaluated in its OWN try — an exception here
+            # used to fall into the emit's handler and lose the whole envelope; now the field records None, said once.
+            try:
+                _effort_effective_emit = _effort_on_wire(
+                    *(_modelinv_state["final_model_id"].split(":", 1)
+                      if ":" in str(_modelinv_state.get("final_model_id") or "")
+                      else (resolved.provider, resolved.model_id)),
+                    _effort, hounfour,
+                )
+            except Exception as _ee:  # noqa: BLE001 — one field never costs the envelope
+                _effort_effective_emit = None
+                logger.warning("MODELINV effort_effective could not be derived (%s: %s) — recorded as None",
+                               type(_ee).__name__, _ee)
+
~~~~

## H22 — .claude/adapters/cheval.py — head lines 2834–2843

Head context (head/.claude/adapters/cheval.py, lines 2822–2855):

~~~~text
  2822 |                     # /loa status --economy attribution. Same fallback chain
  2823 |                     # as the chunked-path emit above.
  2824 |                     calling_primitive=(getattr(args, "skill", None) or agent_name),
  2825 |                     invocation_latency_ms=_modelinv_state["invocation_latency_ms"],
  2826 |                     cost_micro_usd=_modelinv_state["cost_micro_usd"],
  2827 |                     # Cycle-112 D-7 (#948): post-flight token counts.
  2828 |                     # Same source-of-truth as chunked-path emit above.
  2829 |                     tokens_input=_modelinv_state.get("tokens_input"),
  2830 |                     tokens_output=_modelinv_state.get("tokens_output"),
  2831 |                     # cycle-124 FR-2: requested effort (schema field since cycle-114
  2832 |                     # FR-8, never populated before this cycle).
  2833 |                     effort=_effort,
> 2834 |                     # cycle-127 FR-2: caller | catalog | none.
> 2835 |                     effort_source=_effort_source,
> 2836 |                     # cycle-127 D-2.6: the wire value on the hop that answered
> 2837 |                     # (the primary when none did).
> 2838 |                     effort_effective=_effort_on_wire(
> 2839 |                         *(_modelinv_state["final_model_id"].split(":", 1)
> 2840 |                           if ":" in str(_modelinv_state.get("final_model_id") or "")
> 2841 |                           else (resolved.provider, resolved.model_id)),
> 2842 |                         _effort, hounfour,
> 2843 |                     ),
  2844 |                     # cycle-124 FR-4: prompt-cache telemetry.
  2845 |                     tokens_cache_read=_modelinv_state.get("tokens_cache_read"),
  2846 |                     tokens_cache_creation=_modelinv_state.get("tokens_cache_creation"),
  2847 |                     # cycle-124 FR-7: structured-output telemetry (schema requested only).
  2848 |                     schema_enforced=_modelinv_state.get("schema_enforced"),
  2849 |                     output_schema_sha256=_modelinv_state.get("output_schema_sha256"),
  2850 |                     streaming=_modelinv_state["streaming"],
  2851 |                     final_model_id=_modelinv_state["final_model_id"],
  2852 |                     transport=_modelinv_state["transport"],
  2853 |                     config_observed=_modelinv_state["config_observed"],
  2854 |                     pricing_snapshot=_modelinv_state["pricing_snapshot"],
  2855 |                     capability_evaluation=_modelinv_state["capability_evaluation"],
~~~~

The change from head to the fix:

~~~~diff
@@ -2834,10 +2977,6 @@
-                    # cycle-127 FR-2: caller | catalog | none.
+                    # cycle-127 FR-2 (SDD D-2.5): caller | catalog | extra | none.
                     effort_source=_effort_source,
-                    # cycle-127 D-2.6: the wire value on the hop that answered
-                    # (the primary when none did).
-                    effort_effective=_effort_on_wire(
-                        *(_modelinv_state["final_model_id"].split(":", 1)
-                          if ":" in str(_modelinv_state.get("final_model_id") or "")
-                          else (resolved.provider, resolved.model_id)),
-                        _effort, hounfour,
-                    ),
+                    # cycle-127 review r251-1 G1: hops planned around (never dispatched).
+                    models_not_planned=_models_not_planned or None,
+                    # cycle-127 D-2.6 — None where the adapter sends no effort (derived above, r251-4 S8).
+                    effort_effective=_effort_effective_emit,
~~~~

## H23 — .claude/adapters/cheval.py — head line 3046

Head context (head/.claude/adapters/cheval.py, lines 3034–3058):

~~~~text
  3034 |     parser.add_argument(
  3035 |         "--max-tokens", type=int, default=None, dest="max_tokens",
  3036 |         help=(
  3037 |             "Maximum output tokens. Default (cycle-124 FR-2, cycle-126 FR-1.3): per "
  3038 |             "model — Anthropic hops min(64000 streaming | 16000 with "
  3039 |             "LOA_CHEVAL_DISABLE_STREAMING, catalog max_output_tokens); other providers "
  3040 |             "min(16000, catalog max_output_tokens); 4096 for an entry without "
  3041 |             "max_output_tokens or under LOA_CHEVAL_LEGACY_WIRE. Explicit values are "
  3042 |             "clamped to the catalog max_output_tokens; 0 is rejected."
  3043 |         ),
  3044 |     )
  3045 |     parser.add_argument(
> 3046 |         "--effort", choices=["low", "medium", "high", "xhigh", "max"], default=None,
  3047 |         help=(
  3048 |             "Anthropic output_config.effort (cycle-124 FR-2). Omitted on models that "
  3049 |             "predate the control; xhigh is downgraded to high on the 4.6 generation."
  3050 |         ),
  3051 |     )
  3052 |     parser.add_argument(
  3053 |         "--json-schema", dest="json_schema", metavar="FILE", default=None,
  3054 |         help=(
  3055 |             "JSON Schema file the answer must conform to (cycle-124 FR-7). Enforced "
  3056 |             "on Anthropic `structured_json` entries (output_config.format) and on "
  3057 |             "claude-headless (--json-schema); other hops run unenforced and the "
  3058 |             "MODELINV envelope records schema_enforced=false. Object root, <= 64 KB."
~~~~

The change from head to the fix:

~~~~diff
@@ -3046 +3185 @@
-        "--effort", choices=["low", "medium", "high", "xhigh", "max"], default=None,
+        "--effort", choices=EFFORT_LEVELS, default=None,
~~~~

## H24 — .claude/adapters/loa_cheval/audit/modelinv.py — head lines 498–502

Head context (head/.claude/adapters/loa_cheval/audit/modelinv.py, lines 486–514):

~~~~text
   486 |     #   - Gemini:     usageMetadata.promptTokenCount / candidatesTokenCount
   487 |     # Together with the existing pricing_snapshot field these enable
   488 |     # honest cost-per-clean-output in /loa status --economy (replacing
   489 |     # the Phase A pre-flight capability_evaluation.estimated_input_tokens
   490 |     # proxy). Optional/additive — legacy callers omitting them produce
   491 |     # shape-identical envelopes (no `tokens_*` keys in payload).
   492 |     tokens_input: Optional[int] = None,
   493 |     tokens_output: Optional[int] = None,
   494 |     # cycle-124 FR-2 — requested reasoning effort (schema field since
   495 |     # cycle-114 FR-8; first populated this cycle). Optional/additive.
   496 |     effort: Optional[str] = None,
   497 |     # cycle-127 FR-2 (SDD D-2.3) — where `effort` came from:
>  498 |     # caller | catalog | none. Optional/additive.
>  499 |     effort_source: Optional[str] = None,
>  500 |     # cycle-127 D-2.6 — the value the answering hop put on the wire (after
>  501 |     # the adapter's per-family mapping). Optional/additive.
>  502 |     effort_effective: Optional[str] = None,
   503 |     # cycle-124 FR-4 — prompt-cache telemetry (U0 schema fields).
   504 |     tokens_cache_read: Optional[int] = None,
   505 |     tokens_cache_creation: Optional[int] = None,
   506 |     # cycle-124 FR-7 — structured-output telemetry (U0 schema fields); present
   507 |     # only when a schema was requested for the call.
   508 |     schema_enforced: Optional[bool] = None,
   509 |     output_schema_sha256: Optional[str] = None,
   510 | ) -> None:
   511 |     """Emit a model.invoke.complete envelope to the MODELINV audit chain.
   512 | 
   513 |     Pipeline:
   514 |       1. Build payload conforming to model-invoke-complete.payload.schema.json.
~~~~

The change from head to the fix:

~~~~diff
@@ -498,5 +498,11 @@
-    # caller | catalog | none. Optional/additive.
+    # caller | catalog | extra | none (SDD D-2.5). Optional/additive.
     effort_source: Optional[str] = None,
-    # cycle-127 D-2.6 — the value the answering hop put on the wire (after
-    # the adapter's per-family mapping). Optional/additive.
+    # cycle-127 D-2.6 — the value the answering hop put on the wire (the
+    # adapter's ``wire_effort`` hook: per-family mapping on Anthropic HTTP,
+    # absent where the adapter sends none). Optional/additive.
     effort_effective: Optional[str] = None,
+    # cycle-127 review r251-1 G1 — hops cheval's planner dropped before the walk (never dispatched, never in
+    # models_requested): [{model, provider, reason}]. An agy-ALONE chain is not here: it is dispatched to the adapter,
+    # which refuses, and lands in models_failed (error_class INVALID_CONFIG, failure_class opt_in_required; r251-2 K2).
+    # Optional/additive.
+    models_not_planned: Optional[List[Dict[str, Any]]] = None,
~~~~

## H25 — .claude/adapters/loa_cheval/audit/modelinv.py — head line 526

Head context (head/.claude/adapters/loa_cheval/audit/modelinv.py, lines 514–538):

~~~~text
   514 |       1. Build payload conforming to model-invoke-complete.payload.schema.json.
   515 |       2. `redact_payload_strings(payload)` — field-level redaction.
   516 |       3. `assert_no_secret_shapes_remain(json.dumps(payload))` — gate check.
   517 |          RAISES RedactionFailure if any secret shape remains.
   518 |       4. `audit_emit(MODELINV, model.invoke.complete, payload, log_path)`.
   519 | 
   520 |     Caller contract:
   521 |       - `models_requested`: list of `provider:model_id` strings; MUST have
   522 |         at least one entry per schema.
   523 |       - `models_succeeded`: subset of models_requested that produced a usable
   524 |         response. Empty on failure-only paths.
   525 |       - `models_failed`: list of dicts with keys (model, error_class,
>  526 |         message_redacted, [fallback_from, fallback_to, retryable]).
   527 |         `message_redacted` MAY contain raw upstream content; it WILL be
   528 |         redacted in step 2.
   529 |       - `operator_visible_warn`: did the operator see a WARN line on this
   530 |         call? Required for vision-019 M1 silent-degradation audit query.
   531 |       - `kill_switch_active`: derived from env (LOA_FORCE_LEGACY_MODELS).
   532 | 
   533 |     Failures:
   534 |       - RedactionFailure: gate rejected the payload. Caller MAPS to exit
   535 |         code STRICT_VIOLATION (see cheval.py main()).
   536 |       - Other exceptions (audit_emit failure, schema invalid, lock timeout):
   537 |         logged to cheval stderr with [AUDIT-EMIT-FAILED] marker; NOT
   538 |         re-raised by default (audit failure should not break user-facing
~~~~

The change from head to the fix:

~~~~diff
@@ -526 +532,2 @@
-        message_redacted, [fallback_from, fallback_to, retryable]).
+        message_redacted, [fallback_from, fallback_to, retryable, provider,
+        failure_class]).
~~~~

## H26 — .claude/adapters/loa_cheval/audit/modelinv.py — insertion after head line 586

Head context (head/.claude/adapters/loa_cheval/audit/modelinv.py, lines 575–598):

~~~~text
   575 |     # Cycle-112 Phase A.1 D-7 (#948) — post-flight token attribution.
   576 |     # Caller is responsible for validation (provider responses occasionally
   577 |     # contain nulls / negatives on partial-stream failures); we accept the
   578 |     # value verbatim and let the JSON-schema gate catch out-of-range.
   579 |     if tokens_input is not None:
   580 |         payload["tokens_input"] = tokens_input
   581 |     if effort is not None:
   582 |         payload["effort"] = effort
   583 |     if effort_source is not None:
   584 |         payload["effort_source"] = effort_source
   585 |     if effort_effective is not None:
   586 |         payload["effort_effective"] = effort_effective
   587 |     if tokens_cache_read is not None:
   588 |         payload["tokens_cache_read"] = tokens_cache_read
   589 |     if tokens_cache_creation is not None:
   590 |         payload["tokens_cache_creation"] = tokens_cache_creation
   591 |     if schema_enforced is not None:
   592 |         payload["schema_enforced"] = bool(schema_enforced)
   593 |     if output_schema_sha256 is not None:
   594 |         payload["output_schema_sha256"] = output_schema_sha256
   595 |     if tokens_output is not None:
   596 |         payload["tokens_output"] = tokens_output
   597 |     # cycle-114 FR-11 (sprint-4): per-iteration cost telemetry from the
   598 |     # orchestrator env. Optional — absent for one-shot (non-loop) calls so the
~~~~

The change from head to the fix:

~~~~diff
@@ -586,0 +594,2 @@
+    if models_not_planned:
+        payload["models_not_planned"] = list(models_not_planned)
~~~~

## H27 — .claude/adapters/loa_cheval/config/loader.py — insertion after head line 22

Head context (head/.claude/adapters/loa_cheval/config/loader.py, lines 11–34):

~~~~text
    11 |    config flag is set, replace `aliases:` with the pre-cycle-095 snapshot.
    12 | B. Endpoint-family strict validation (SDD §3.4): every providers.openai.models.*
    13 |    entry MUST declare `endpoint_family: chat | responses`.
    14 | """
    15 | 
    16 | from __future__ import annotations
    17 | 
    18 | import copy
    19 | import json
    20 | import logging
    21 | import os
    22 | import re
    23 | import sys
    24 | from pathlib import Path
    25 | from typing import Any, Dict, List, Optional, Tuple
    26 | 
    27 | from loa_cheval.config.interpolation import interpolate_config, redact_config
    28 | from loa_cheval.types import ConfigError
    29 | 
    30 | logger = logging.getLogger("loa_cheval.config.loader")
    31 | 
    32 | # Module-level guard so the force-legacy-aliases WARN fires at most once per
    33 | # process even when load_config() is invoked multiple times (cache-clear,
    34 | # tests, --print-effective-config).
~~~~

The change from head to the fix:

~~~~diff
@@ -22,0 +23 @@
+import stat
~~~~

## H28 — .claude/adapters/loa_cheval/config/loader.py — insertion after head line 47

Head context (head/.claude/adapters/loa_cheval/config/loader.py, lines 36–59):

~~~~text
    36 | _endpoint_family_default_warned: set[str] = set()
    37 | 
    38 | 
    39 | def _reset_warning_state_for_tests() -> None:
    40 |     """Reset module-level warning trackers. Used only by test fixtures."""
    41 |     global _force_legacy_warned
    42 |     _force_legacy_warned = False
    43 |     _endpoint_family_default_warned.clear()
    44 | 
    45 | # Try yaml import — pyyaml optional, yq fallback
    46 | try:
    47 |     import yaml
    48 | 
    49 |     def _load_yaml(path: str) -> Dict[str, Any]:
    50 |         with open(path) as f:
    51 |             return yaml.safe_load(f) or {}
    52 | except ImportError:
    53 |     import subprocess
    54 | 
    55 |     def _load_yaml(path: str) -> Dict[str, Any]:
    56 |         """Fallback: use yq to convert YAML to JSON, then parse.
    57 | 
    58 |         SAFETY: path comes from _find_project_root() or hardcoded defaults,
    59 |         never from user input. If config paths become user-configurable,
~~~~

The change from head to the fix:

~~~~diff
@@ -47,0 +49 @@
+    _HAS_YAML = True
~~~~

## H29 — .claude/adapters/loa_cheval/config/loader.py — insertion after head line 53

Head context (head/.claude/adapters/loa_cheval/config/loader.py, lines 42–65):

~~~~text
    42 |     _force_legacy_warned = False
    43 |     _endpoint_family_default_warned.clear()
    44 | 
    45 | # Try yaml import — pyyaml optional, yq fallback
    46 | try:
    47 |     import yaml
    48 | 
    49 |     def _load_yaml(path: str) -> Dict[str, Any]:
    50 |         with open(path) as f:
    51 |             return yaml.safe_load(f) or {}
    52 | except ImportError:
    53 |     import subprocess
    54 | 
    55 |     def _load_yaml(path: str) -> Dict[str, Any]:
    56 |         """Fallback: use yq to convert YAML to JSON, then parse.
    57 | 
    58 |         SAFETY: path comes from _find_project_root() or hardcoded defaults,
    59 |         never from user input. If config paths become user-configurable,
    60 |         this subprocess call will need input sanitization.
    61 |         """
    62 |         try:
    63 |             result = subprocess.run(
    64 |                 ["yq", "-o", "json", ".", path],
    65 |                 capture_output=True,
~~~~

The change from head to the fix:

~~~~diff
@@ -53,0 +56 @@
+    _HAS_YAML = False
~~~~

## H30 — .claude/adapters/loa_cheval/config/loader.py — head lines 113–126

Head context (head/.claude/adapters/loa_cheval/config/loader.py, lines 101–138):

~~~~text
   101 |     return {}
   102 | 
   103 | 
   104 | def load_project_config(project_root: str) -> Dict[str, Any]:
   105 |     """Layer 2: Project config from .loa.config.yaml (hounfour: section)."""
   106 |     config_path = Path(project_root) / ".loa.config.yaml"
   107 |     if config_path.exists():
   108 |         full = _load_yaml(str(config_path))
   109 |         return full.get("hounfour", {})
   110 |     return {}
   111 | 
   112 | 
>  113 | def agy_opt_in_enabled(project_root: Optional[str] = None) -> bool:
>  114 |     """`hounfour.headless.agy_opt_in` (cycle-127 FR-1): True only for a YAML boolean `true`, default False.
>  115 | 
>  116 |     Read through the project-config layer merged over the System defaults, from the root cheval itself resolves (the cwd
>  117 |     walk). No environment override — a planner is never talked into the agy voice by ambient env. A config that cannot be
>  118 |     read reads as off: the gate fails closed, and the adapter's refusal names the key.
>  119 |     """
>  120 |     root = project_root or _find_project_root()
>  121 |     try:
>  122 |         merged = _deep_merge(load_system_defaults(root), load_project_config(root))
>  123 |     except Exception:  # noqa: BLE001 — fail closed
>  124 |         return False
>  125 |     headless = merged.get("headless") if isinstance(merged, dict) else None
>  126 |     return isinstance(headless, dict) and headless.get("agy_opt_in") is True
   127 | 
   128 | 
   129 | def load_env_overrides() -> Dict[str, Any]:
   130 |     """Layer 3: Environment variable overrides (limited scope).
   131 | 
   132 |     Only LOA_MODEL (alias override) is supported.
   133 |     Env vars cannot override routing, pricing, or agent bindings.
   134 |     """
   135 |     overrides = {}
   136 |     model = os.environ.get("LOA_MODEL")
   137 |     if model:
   138 |         overrides["env_model_override"] = model
~~~~

The change from head to the fix:

~~~~diff
@@ -113,14 +116,436 @@
-def agy_opt_in_enabled(project_root: Optional[str] = None) -> bool:
-    """`hounfour.headless.agy_opt_in` (cycle-127 FR-1): True only for a YAML boolean `true`, default False.
+_AGY_TYPE_WARNED = False
+_AGY_TRUST_WARNED = False
+_AGY_READ_WARNED = False
+_AGY_AVAILABLE_WARNED = False
+_AGY_OPT_IN_KEY = "hounfour.headless.agy_opt_in"
 
-    Read through the project-config layer merged over the System defaults, from the root cheval itself resolves (the cwd
-    walk). No environment override — a planner is never talked into the agy voice by ambient env. A config that cannot be
-    read reads as off: the gate fails closed, and the adapter's refusal names the key.
-    """
-    root = project_root or _find_project_root()
+
+_AGY_OPT_IN_ACCEPTED = "agy_opt_in: true"
+_YAML_BOOL_TAG = "tag:yaml.org,2002:bool"
+_YAML_CORE_PREFIX = "tag:yaml.org,2002:"
+
+# The adapters directory this cheval runs from, symlinks resolved (r251-4 S2: the identity a project root must match).
+_ADAPTERS_DIR = Path(__file__).resolve().parents[2]
+
+
+class _UntrustedConfig(Exception):
+    """The project config exists but is not the current user's alone to write (r251-4 S2): the opt-in reads as off."""
+
+
+def _install_root() -> str:
+    """The repo root these adapters belong to: the directory holding `.claude/adapters` (r251-4 S2). The LOGICAL path
+    (no symlink resolution) — under a submodule mount the project's `.claude/adapters` is a symlink into the submodule."""
+    return str(Path(os.path.abspath(__file__)).parents[4])
+
+
+def _opt_in_root() -> str:
+    """The root the opt-in is read from when the caller names none (review r251-4 S2, audit n6): the cwd walk's root ONLY
+    when its `.claude/adapters` is this cheval (same directory, symlinks resolved — the vendored and the submodule mount
+    alike); anything else — a planted `/tmp/.loa.config.yaml`, another project's tree — falls back to cheval's own
+    install root. The opt-in is an operator decision about THIS install; a cwd ancestor never makes it."""
+    walked = _find_project_root()
     try:
-        merged = _deep_merge(load_system_defaults(root), load_project_config(root))
+        if (Path(walked) / ".claude" / "adapters").resolve() == _ADAPTERS_DIR:
+            return walked
+    except OSError:
+        pass
+    return _install_root()
+
+
+def _not_private_group(st: os.stat_result, fd: Optional[int] = None) -> Optional[str]:
+    """None when the file's group is its owner's USER-PRIVATE group (r251-6 V1, BB #1); else why not. ONE rule with the
+    bash lib's `_agy_group_not_private` and Bridgebuilder's `agyGroupNotPrivate`: the file's gid is the owner's primary gid,
+    the group is NAMED for the owner (a shared `users` / macOS `staff` fails here — its member list is empty for primary
+    members, so emptiness alone never proved privacy: audit LOW-001), no account but the owner is a listed member, no other
+    account has it as its primary group (enumerated last: under sssd / LDAP the walk can be long and lists only what is
+    enumerable — the name check is what holds there), and no POSIX ACL makes the group bits a mask over named grants. The
+    headless workspace's `_group_private` is the same rule for directories. An account database that cannot answer is
+    no proof: not private."""
+    try:
+        import grp
+        import pwd
+    except ImportError:
+        return "its group cannot be looked up on this platform"
+    try:
+        owner = pwd.getpwuid(st.st_uid)
+    except (KeyError, OSError):
+        return f"its owner uid {st.st_uid} could not be looked up"
+    try:
+        group = grp.getgrgid(st.st_gid)
+    except (KeyError, OSError):
+        return f"its group could not be looked up (gid {st.st_gid})"
+    name = group.gr_name
+    if st.st_gid != owner.pw_gid:
+        return f"its group {name!r} (gid {st.st_gid}) is not the owner's primary group"
+    if name != owner.pw_name:
+        return f"its group {name!r} is not named for the owner {owner.pw_name!r} (not a user-private group)"
+    others = [m for m in group.gr_mem if m != owner.pw_name]
+    if others:
+        return f"its group {name!r} has other members ({', '.join(others)})"
+    try:
+        accounts = pwd.getpwall()
+    except OSError:
+        return f"the accounts of group {name!r} could not be enumerated"
+    primary = [a.pw_name for a in accounts if a.pw_gid == st.st_gid and a.pw_uid != st.st_uid]
+    if primary:
+        return f"its group {name!r} is the primary group of another account ({', '.join(primary)})"
+    if _acl_extended(fd):
+        return "it carries an extended ACL (the group bits are the ACL mask over other accounts' grants)"
+    return None
+
+
+def _acl_extended(fd: Optional[int]) -> bool:
+    """The open file carries a POSIX / NFSv4 access ACL (any `system.*acl*` xattr) — the headless workspace's
+    `_acl_extended` on the read's own fd. No xattr support → none; any other failure → assume one (no proof)."""
+    if fd is None or not hasattr(os, "listxattr"):
+        return False
+    import errno
+    try:
+        return any(n.startswith("system.") and "acl" in n for n in os.listxattr(fd))
+    except OSError as exc:
+        return exc.errno not in (errno.ENOTSUP, errno.EOPNOTSUPP)
+
+
+def _config_untrusted_reason(path: Path, st: Optional[os.stat_result] = None, fd: Optional[int] = None) -> Optional[str]:
+    """None when only the current user can write `path`; else why not (r251-4 S2). ONE permission rule with the bash lib's
+    `_agy_config_untrusted` and Bridgebuilder's `agyConfigUntrustedReason` (r251-5 U1/U2, r251-6 V1): owned by the euid,
+    never world-writable, and group-writable only for the owner's user-private group (`_not_private_group` — Ubuntu's
+    umask 002 makes every checkout 0664). `st` / `fd` are the read's own open file (r251-6 V3, BB #2: the bytes read and
+    the stat judged are one inode); without them the path is stat'ed through symlinks — the target decides. With no
+    `os.geteuid` (non-POSIX, r251-6 V2) the owner half is skipped and the mode half still applies."""
+    if st is None:
+        st = path.stat()
+    geteuid = getattr(os, "geteuid", None)
+    if geteuid is not None:
+        me = geteuid()
+        if st.st_uid != me:
+            return f"not owned by the current user (uid {st.st_uid}, euid {me})"
+    mode = f"mode {st.st_mode & 0o7777:04o}"
+    if st.st_mode & 0o002:
+        return f"world-writable ({mode})"
+    if st.st_mode & 0o020:
+        why = _not_private_group(st, fd)
+        if why:
+            return f"group-writable ({mode}) and {why}"
+    return None
+
+
+if _HAS_YAML:
+    class _OptInNodeLoader(yaml.SafeLoader):
+        """compose() with every ALIAS replaced by a sentinel node (r251-4 S3, audit n17): an alias on the opt-in's path
+        reads as off here, as it does under go yq and Bridgebuilder."""
+
+        def compose_node(self, parent, index):  # noqa: D401 — PyYAML hook
+            if self.check_event(yaml.AliasEvent):
+                self.get_event()
+                return yaml.ScalarNode("!loa/alias", "")
+            return super().compose_node(parent, index)
+
+
+def _tag_kind(tag: str) -> str:
+    """`bool` only for the EXACT core tag (r251-4 S3, audit n5: `!<x:bool>` is not a boolean); the core short name for
+    the other core tags; else the tag itself."""
+    if tag == _YAML_BOOL_TAG:
+        return "bool"
+    if tag == "!loa/alias":
+        return "alias"
+    if tag.startswith(_YAML_CORE_PREFIX):
+        return tag[len(_YAML_CORE_PREFIX):]
+    return tag or "?"
+
+
+class _UnreadableOptIn(Exception):
+    """The opt-in cannot be read on this host (no PyYAML and no mikefarah yq — r251-6 V6): it reads off, said once."""
+
+
+def _agy_opt_in_raw(project_root: Optional[str]) -> Tuple[bool, str, str]:
+    """(present, kind, text) of `agy_opt_in` in the PROJECT config only (r251-1 G9: an operator decision — framework-
+    shipped System defaults never satisfy it). `kind` is `bool` only for the exact tag `tag:yaml.org,2002:bool`, `alias`
+    for an alias node, else the tag's short name (str / int / null / map …) and `text` the scalar's SOURCE text — the
+    node, not the constructed value (review r251-2 K1: PyYAML resolves YAML 1.1, so `yes` / `on` / `True` construct to
+    True; the source text tells them from `true`). A merge key (`<<: *b`) is not the key: absent (r251-4 S3). An alias or
+    a non-mapping on an ANCESTOR (`hounfour`, `hounfour.headless`) is kind `ancestor`, text `<path>:<alias|kind>`
+    (r251-6 V5). The file is opened ONCE: its bytes are parsed and its fstat judged (r251-6 V3). Raises on an unreadable
+    config and `_UntrustedConfig` when a value that would opt in sits in a config others can write; callers fail
+    closed."""
+    root = project_root or _opt_in_root()
+    config_path = Path(root) / ".loa.config.yaml"
+    try:
+        f = open(config_path, "rb")
+    except FileNotFoundError:
+        return False, "", ""
+    with f:
+        st = os.fstat(f.fileno())
+        if not stat.S_ISREG(st.st_mode):
+            raise ConfigError(f"{config_path} is not a regular file")
+        data = f.read()
+        result = _agy_opt_in_node_of_bytes(data)
+        # (r251-5 U1: the permission rule decides only a value that would opt in — a config that reads off anyway is not
+        # flagged, so a umask-002 host that never opted in hears nothing; the same order in the bash and TS readers)
+        if result == (True, "bool", "true"):
+            why = _config_untrusted_reason(config_path, st, f.fileno())
+            if why:
+                raise _UntrustedConfig(f"{config_path} is {why}")
+    return result
+
+
+def _agy_opt_in_node_of(config_path: Path) -> Tuple[bool, str, str]:
+    """(present, kind, text) of `agy_opt_in` in `config_path` (an existing file) — the node read, no permission rule."""
+    with open(config_path, "rb") as f:
+        return _agy_opt_in_node_of_bytes(f.read())
+
+
+def _agy_opt_in_node_of_bytes(data: bytes) -> Tuple[bool, str, str]:
+    """(present, kind, text) of `agy_opt_in` in a config document's bytes — the node read, no permission rule."""
+    if not _HAS_YAML:
+        return _agy_opt_in_raw_yq(data)
+    node = yaml.compose(data, Loader=_OptInNodeLoader)
+    path: List[str] = []
+    for key in ("hounfour", "headless", "agy_opt_in"):
+        if not isinstance(node, yaml.MappingNode):
+            return False, "", ""
+        found = None
+        for k, v in node.value:  # the last duplicate wins, as in safe_load
+            if isinstance(k, yaml.ScalarNode) and k.tag != "tag:yaml.org,2002:merge" and k.value == key:
+                found = v
+        if found is None:
+            return False, "", ""
+        path.append(key)
+        if key != "agy_opt_in" and not isinstance(found, yaml.MappingNode):
+            kind = _tag_kind(found.tag or "")
+            if kind == "null":
+                return False, "", ""
+            # (r251-6 V5, BB #5: an alias / non-mapping ancestor is said, never read silently as absent)
+            return True, "ancestor", f"{'.'.join(path)}:{kind}"
+        node = found
+    kind = _tag_kind(node.tag or "")
+    text = node.value if isinstance(node, yaml.ScalarNode) else ""
+    return True, kind, text
+
+
+# ONE yq program for the go-yq readers (the bash lib's `_agy_opt_in_node` and Bridgebuilder's `readAgyGate` carry the
+# same): `kind` is "alias" for an alias node (r251-4 S3), and `has` sees the explicit key only — never a merge key's.
+_YQ_HAS = '.hounfour | (kind == "map" and (.headless | (kind == "map" and has("agy_opt_in"))))'
+_YQ_KIND = '.hounfour.headless.agy_opt_in | kind'
+# (r251-6 V5: the ancestors' kind and tag, one level at a time — a level below a non-mapping is never traversed)
+_YQ_ANCESTOR = '{path} | kind + " " + tag'
+
+
+def _yq_flavour() -> str:
+    """`yq --version`'s line; raises `_UnreadableOptIn` when there is no yq or it is not mikefarah's (r251-6 V6, BB #6: the
+    go-yq program is never run under python yq, whose jq syntax cannot see a tag or the source text — the bash lib selects
+    its reader the same way, review r251-2 K5)."""
+    import subprocess as _sp
+    try:
+        r = _sp.run(["yq", "--version"], capture_output=True, text=True, timeout=5)
+    except (FileNotFoundError, OSError):
+        raise _UnreadableOptIn("PyYAML is not installed and no yq is on PATH")
+    line = ((r.stdout or "") + (r.stderr or "")).strip().splitlines()
+    line = line[0][:120] if line else "?"
+    if r.returncode != 0 or "mikefarah" not in line:
+        raise _UnreadableOptIn(f"PyYAML is not installed and yq is not mikefarah/yq ({line})")
+    return line
+
+
+def _agy_opt_in_raw_yq(data: bytes) -> Tuple[bool, str, str]:
+    """The no-PyYAML fallback: go yq (mikefarah) keeps the source text and the YAML 1.2 tag — the bash reader's view. The
+    document is fed on stdin (r251-6 V3: the bytes already read, never the path again)."""
+    import subprocess as _sp
+    _yq_flavour()
+
+    def _yq(expr: str) -> str:
+        r = _sp.run(["yq", "eval", expr, "-"], input=data, capture_output=True, timeout=5)
+        if r.returncode != 0:
+            raise ConfigError(f"yq failed on the config: {r.stderr.decode('utf-8', 'replace')}")
+        return r.stdout.decode("utf-8", "replace").strip()
+    if _yq(_YQ_HAS) != "true":
+        for path, dotted in ((".hounfour", "hounfour"), (".hounfour.headless", "hounfour.headless")):
+            kind, _, tag = _yq(_YQ_ANCESTOR.format(path=path)).partition(" ")
+            if kind == "map":
+                continue
+            if kind == "alias":
+                return True, "ancestor", f"{dotted}:alias"
+            if tag == "!!null" or not tag:
+                return False, "", ""
+            return True, "ancestor", f"{dotted}:{tag[2:] if tag.startswith('!!') else tag}"
+        return False, "", ""
+    if _yq(_YQ_KIND) == "alias":
+        return True, "alias", ""
+    tag = _yq(".hounfour.headless.agy_opt_in | tag")
+    kind = "bool" if tag == "!!bool" else (tag[2:] if tag.startswith("!!") else (tag or "?"))
+    return True, kind, _yq(".hounfour.headless.agy_opt_in")
+
+
+def agy_opt_in_enabled(project_root: Optional[str] = None) -> bool:
+    """`hounfour.headless.agy_opt_in` (cycle-127 FR-1): True only for the YAML boolean scalar written exactly `true`,
+    default False.
+
+    ONE strict rule with the bash reader (`.claude/scripts/lib/agy-gate-lib.sh` `agy_opted_in`) and Bridgebuilder's
+    `readAgyGate` (review r251-2 K1, r251-4 S3): the node's tag is EXACTLY `tag:yaml.org,2002:bool` AND its source text
+    is `true`. PyYAML's other YAML 1.1 truthy spellings (`yes`, `on`, `True`, `TRUE`) read off — as they do under go yq —
+    and so do `1`, the string `"true"`, a foreign tag (`!<x:bool> true`), an alias (`*t`) and a merge key (`<<: *b`).
+
+    Read from the project config (`.loa.config.yaml`) only — never the System defaults (review r251-1 G9). With no
+    `project_root`, the root is this cheval's project (`_opt_in_root`: the cwd walk's root only when its
+    `.claude/adapters` is this cheval, else the install root — r251-4 S2), and a config others can write (not owned by
+    the euid, world-writable, or group-writable for any group but the owner's user-private one — r251-5 U2, r251-6 V1)
+    reads as off with one WARN; the bash and TS readers apply the same rule (r251-5 U1). An alias or non-mapping
+    ancestor of the key (r251-6 V5), or no way to read the config strictly (no PyYAML and no mikefarah yq — V6), reads
+    off with one WARN. No environment override — a
+    planner is never talked into the agy voice by ambient env. A config that cannot be read reads as off: the gate fails
+    closed, and the adapter's refusal names the key. A present value not written exactly `true` / `false` reads as off
+    with one WARN per process naming the key and the accepted spelling (G12, K1).
+    """
+    global _AGY_TYPE_WARNED, _AGY_TRUST_WARNED, _AGY_READ_WARNED
+    try:
+        # (review r251-1 G4: the root walk sits inside the fail-closed try — a discovery failure reads as off)
+        present, kind, text = _agy_opt_in_raw(project_root)
+    except _UnreadableOptIn as e:
+        if not _AGY_READ_WARNED:
+            _AGY_READ_WARNED = True
+            logger.warning("%s cannot be read: %s — install PyYAML or mikefarah/yq; the agy route stays off",
+                           _AGY_OPT_IN_KEY, e)
+        return False
+    except _UntrustedConfig as e:
+        if not _AGY_TRUST_WARNED:
+            _AGY_TRUST_WARNED = True
+            logger.warning("%s: %s — a config others can write never opts in (own it and `chmod go-w` it); "
+                           "the agy route stays off", _AGY_OPT_IN_KEY, e)
+        return False
     except Exception:  # noqa: BLE001 — fail closed
         return False
-    headless = merged.get("headless") if isinstance(merged, dict) else None
-    return isinstance(headless, dict) and headless.get("agy_opt_in") is True
+    on = present and kind == "bool" and text == "true"
+    if kind == "ancestor":
+        if not _AGY_TYPE_WARNED:
+            _AGY_TYPE_WARNED = True
+            where, _, what = text.rpartition(":")
+            logger.warning("%s is %s — %s cannot be read through an alias or merge node (write the mapping inline); "
+                           "the agy route stays off", where,
+                           "a YAML alias" if what == "alias" else f"not a mapping ({what})", _AGY_OPT_IN_KEY)
+        return False
+    canonical = (kind == "bool" and text in ("true", "false")) or kind == "null"
+    if present and not canonical and not _AGY_TYPE_WARNED:
+        _AGY_TYPE_WARNED = True
+        what = ("a boolean spelled other than true/false" if kind == "bool"
+                else "a YAML alias (an alias never opts in)" if kind == "alias" else "not a YAML boolean")
+        logger.warning("%s is %r (%s), %s — only `%s` opts in (the lowercase scalar, as the bash reader requires); "
+                       "the agy route stays off", _AGY_OPT_IN_KEY, text, kind or "?", what, _AGY_OPT_IN_ACCEPTED)
+    return on
+
+
+def warn_agy_available_once(project_root: Optional[str] = None) -> None:
+    """SDD D-1.7 (review r251-1 G18): with the opt-in off while the route looks usable here — `agy` on PATH, or a Gemini /
+    Google key set — say ONCE per process that the route is gated and why. Nothing is spawned for the PATH lookup; reading
+    the opt-in may run `yq` (up to four times) when PyYAML is absent (r251-4 S8, audit n4)."""
+    global _AGY_AVAILABLE_WARNED
+    if _AGY_AVAILABLE_WARNED or agy_opt_in_enabled(project_root):
+        return
+    import shutil
+    why = []
+    if shutil.which(os.environ.get("AGY_HEADLESS_BIN", "agy")):
+        why.append("agy on PATH")
+    if os.environ.get("GOOGLE_API_KEY") or os.environ.get("GEMINI_API_KEY"):
+        why.append("a Google/Gemini key is set")
+    if not why:
+        return
+    _AGY_AVAILABLE_WARNED = True
+    logger.warning("the agy route is available here (%s) but not planned: %s is not true — opt in only knowingly "
+                   "(the prompt travels on the CLI's argv, readable by local users; the CLI must be OAuth-authed)",
+                   ", ".join(why), _AGY_OPT_IN_KEY)
+
+
+_CATALOG_PROVIDERS_CACHE: Dict[str, Tuple[Dict[str, str], Dict[str, str]]] = {}
+_CATALOG_MAPS_WARNED = False
+
+
+def _catalog_provider_maps() -> Tuple[Dict[str, str], Dict[str, str]]:
+    """(model id → provider, alias → provider) from the System catalog (`.claude/defaults/model-config.yaml`, beside this
+    package — the file `generated-model-maps.sh` is generated from) overlaid with the project config's providers/aliases
+    from the opt-in's own root (`_opt_in_root`, r251-6 V4 / BB #3: one trust anchor for the gate and the routing it
+    gates — a planted cwd-ancestor config never changes whether a bare name is judged Google). Cached per project root — but only a COMPLETE read (r251-4 S5, audit run-2 n1/n8): a layer
+    that fails to read leaves the maps it could read for this call, is said once per process (the caller falls back to
+    the `gemini*` name rule for what is missing), and is retried on the next call."""
+    global _CATALOG_MAPS_WARNED
+    try:
+        root = _opt_in_root()
+    except Exception:  # noqa: BLE001
+        root = ""
+    if root in _CATALOG_PROVIDERS_CACHE:
+        return _CATALOG_PROVIDERS_CACHE[root]
+    merged: Dict[str, Any] = {}
+    system = Path(__file__).resolve().parents[3] / "defaults" / "model-config.yaml"   # .claude/defaults
+    failures: List[str] = []
+
+    def _system() -> Dict[str, Any]:
+        if not system.is_file():
+            raise ConfigError(f"System catalog missing: {system}")
+        return _load_yaml(str(system))
+    for read in (_system, lambda: load_project_config(root) if root else {}):
+        try:
+            layer = read()
+        except Exception as e:  # noqa: BLE001 — fail soft, said once below
+            failures.append(f"{type(e).__name__}: {e}"[:300])
+            layer = {}
+        if isinstance(layer, dict):
+            merged = _deep_merge(merged, {k: layer[k] for k in ("providers", "aliases") if isinstance(layer.get(k), dict)})
+    models: Dict[str, str] = {}
+    for prov, block in (merged.get("providers") or {}).items():
+        for mid in ((block or {}).get("models") or {}) if isinstance(block, dict) else ():
+            models.setdefault(str(mid), str(prov))
+    aliases: Dict[str, str] = {}
+    for name, target in (merged.get("aliases") or {}).items():
+        if isinstance(target, dict):
+            target = target.get("target") or target.get("model") or ""
+        if isinstance(target, str) and ":" in target:
+            aliases[str(name)] = target.split(":", 1)[0]
+        elif isinstance(target, str) and target in models:
+            aliases[str(name)] = models[target]
+    if failures:
+        if not _CATALOG_MAPS_WARNED:
+            _CATALOG_MAPS_WARNED = True
+            logger.warning("the model catalog could not be read for agy routing (%s) — falling back to the gemini* name "
+                           "rule for what is missing; a catalog-only Google alias (deep-research-pro, researcher) is not "
+                           "recognised until it reads", "; ".join(failures))
+    else:
+        _CATALOG_PROVIDERS_CACHE[root] = (models, aliases)
+    return models, aliases
+
+
+def catalog_provider_of(model: str) -> str:
+    """The provider cheval resolves `model` to: a `provider:` prefix, else the catalog alias, else the catalog model id,
+    else the `gemini*` name (→ google); "" when none applies (r251-3 R3)."""
+    m = (model or "").strip()
+    if not m:
+        return ""
+    if ":" in m:
+        return m.split(":", 1)[0]
+    models, aliases = _catalog_provider_maps()
+    if m in aliases:
+        return aliases[m]
+    if m in models:
+        return models[m]
+    return "google" if m.startswith("gemini") else ""
+
+
+def routes_to_agy(model: str, mode: Optional[str] = None) -> bool:
+    """True when cheval would dispatch `model` through agy (cycle-127 review r251-1 G2) — the Python twin of
+    `.claude/scripts/lib/agy-gate-lib.sh` `routes_to_agy`, one rule for every reader:
+
+      * the `gemini-headless` hop by name — bare, provider-prefixed (`google:gemini-headless`) or as a provider
+        (`gemini-headless:<model>`), in any headless mode;
+      * a Google model under `hounfour.headless.mode: cli-only`, where the chain resolver keeps only the CLI hop (the
+        caller resolves the mode — env `LOA_HEADLESS_MODE` wins, as in cheval). r251-3 R3: "Google" is the PROVIDER the
+        model resolves to (`catalog_provider_of`: the `google:` prefix, the catalog alias or model id — e.g.
+        `deep-research-pro`, `researcher` — with the `gemini*` name as the fallback), as in cheval's
+        `_entry_routes_to_agy` and Bridgebuilder's `isAgyRouted`.
+
+    Under `prefer-cli` a Google model is NOT agy-routed: its API hop stays planned (cheval's walk skips the gated hop).
+    """
+    m = (model or "").strip()
+    if not m:
+        return False
+    if m == "gemini-headless" or m.endswith(":gemini-headless") or m.startswith("gemini-headless:"):
+        return True
+    if mode != "cli-only":
+        return False
+    return catalog_provider_of(m) == "google"
~~~~

## H31 — .claude/adapters/loa_cheval/providers/agy_headless_adapter.py — head lines 261–262

Head context (head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py, lines 249–274):

~~~~text
   249 |             )
   250 | 
   251 |         return self._build_result(
   252 |             stdout=proc.stdout or "",
   253 |             requested_model=request.model,
   254 |             messages=request.messages,
   255 |             latency_ms=latency_ms,
   256 |         )
   257 | 
   258 |     def validate_config(self) -> List[str]:
   259 |         """Validate that the agy CLI is on PATH. Auth is best-effort (CLI enforces)."""
   260 |         errors: List[str] = []
>  261 |         if not agy_opt_in_enabled():   # (cycle-127 FR-1)
>  262 |             errors.append(f"Provider '{self.provider}': {AgyOptInRequiredError.MESSAGE}")
   263 |         if self.config.type != "gemini-headless":
   264 |             errors.append(
   265 |                 f"Provider '{self.provider}': type must be 'gemini-headless' "
   266 |                 f"(the agy repoint keeps the registry key; got '{self.config.type}')"
   267 |             )
   268 | 
   269 |         bin_name = self._cli_bin()
   270 |         if not shutil.which(bin_name):
   271 |             errors.append(
   272 |                 f"Provider '{self.provider}': '{bin_name}' CLI not found on PATH. "
   273 |                 f"Install + OAuth-authenticate the Antigravity CLI on the cheval host."
   274 |             )
~~~~

The change from head to the fix:

~~~~diff
@@ -261,2 +261,3 @@
-        if not agy_opt_in_enabled():   # (cycle-127 FR-1)
+        if not agy_opt_in_enabled():   # (cycle-127 FR-1; review r251-1 G6: the binary is irrelevant while the route is off)
             errors.append(f"Provider '{self.provider}': {AgyOptInRequiredError.MESSAGE}")
+            return errors
~~~~

## H32 — .claude/adapters/loa_cheval/providers/claude_headless_adapter.py — insertion after head line 72

Head context (head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py, lines 61–84):

~~~~text
    61 | from typing import Any, Dict, List, Optional
    62 | 
    63 | from loa_cheval.metering.pricing import cli_cost_micro_usd
    64 | from loa_cheval.providers.headless_cli import CLIInvocation, HeadlessCLIAdapter, private_workspace
    65 | from loa_cheval.providers.base import (
    66 |     run_subprocess_pgkill,
    67 | )
    68 | from loa_cheval.types import (
    69 |     CompletionRequest,
    70 |     CompletionResult,
    71 |     AuthRevokedError,
    72 |     ConfigError,
    73 |     ProviderUnavailableError,
    74 |     RateLimitError,
    75 |     Usage,
    76 | )
    77 | 
    78 | logger = logging.getLogger("loa_cheval.providers.claude_headless")
    79 | _CLI_COST_WARNED = False
    80 | _CLI_COST_WARN_LOCK = threading.Lock()
    81 | 
    82 | # cycle-126 sprint-248: the prompt goes on stdin (`claude -p` with no positional prompt reads it from there), at every size.
    83 | # An argv prompt failed with E2BIG over MAX_ARG_STRLEN (twenty-second run) and was readable by every local user through
    84 | # /proc/<pid>/cmdline while the process ran (thirtieth run, e1 DISS-C-001).
~~~~

The change from head to the fix:

~~~~diff
@@ -72,0 +73 @@
+    ProviderContextLimitError,
~~~~

## H33 — .claude/adapters/loa_cheval/providers/claude_headless_adapter.py — head line 131

Head context (head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py, lines 119–143):

~~~~text
   119 | 
   120 | # claude CLI binary name (override via CLAUDE_HEADLESS_BIN env var for testing)
   121 | _CLAUDE_BIN_DEFAULT = "claude"
   122 | 
   123 | # Auth indicator (Claude Code manages this internally; operator runs `claude /login`)
   124 | _CLAUDE_LOGIN_HINT = "claude /login"
   125 | 
   126 | 
   127 | def build_headless_argv(
   128 |     cli_bin: str,
   129 |     cli_model: str,
   130 |     *,
>  131 |     prompt: Optional[str] = None,
   132 |     effort: Optional[str] = None,
   133 |     max_turns: Optional[int] = None,
   134 | ) -> List[str]:
   135 |     """The headless `claude -p` argv: JSON output, plan mode (read-only), no
   136 |     session persistence, every tool disabled (`--tools ""` is the documented
   137 |     "disable all" sentinel), the model, then `--effort` when set.
   138 |     ``prompt=None``: the prompt travels on stdin. ``max_turns`` is for callers
   139 |     outside the adapter (tools/ceiling-probe-live.py pins 1); the adapter does
   140 |     not pass it. cycle-127 D-3.9: one builder, so the probe measures the shape
   141 |     the adapter dispatches."""
   142 |     cmd: List[str] = [
   143 |         cli_bin,
~~~~

The change from head to the fix:

~~~~diff
@@ -131 +131,0 @@
-    prompt: Optional[str] = None,
~~~~

## H34 — .claude/adapters/loa_cheval/providers/claude_headless_adapter.py — head line 138

Head context (head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py, lines 126–150):

~~~~text
   126 | 
   127 | def build_headless_argv(
   128 |     cli_bin: str,
   129 |     cli_model: str,
   130 |     *,
   131 |     prompt: Optional[str] = None,
   132 |     effort: Optional[str] = None,
   133 |     max_turns: Optional[int] = None,
   134 | ) -> List[str]:
   135 |     """The headless `claude -p` argv: JSON output, plan mode (read-only), no
   136 |     session persistence, every tool disabled (`--tools ""` is the documented
   137 |     "disable all" sentinel), the model, then `--effort` when set.
>  138 |     ``prompt=None``: the prompt travels on stdin. ``max_turns`` is for callers
   139 |     outside the adapter (tools/ceiling-probe-live.py pins 1); the adapter does
   140 |     not pass it. cycle-127 D-3.9: one builder, so the probe measures the shape
   141 |     the adapter dispatches."""
   142 |     cmd: List[str] = [
   143 |         cli_bin,
   144 |         "-p",
   145 |         *([] if prompt is None else [prompt]),
   146 |         "--output-format",
   147 |         "json",
   148 |         "--permission-mode",
   149 |         "plan",
   150 |         "--no-session-persistence",
~~~~

The change from head to the fix:

~~~~diff
@@ -138 +138,2 @@
-    ``prompt=None``: the prompt travels on stdin. ``max_turns`` is for callers
+    The prompt travels on stdin — the builder takes none (r251-4 S8, audit
+    n26: a prompt here would sit where an option is parsed). ``max_turns`` is for callers
~~~~

## H35 — .claude/adapters/loa_cheval/providers/claude_headless_adapter.py — head line 145

Head context (head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py, lines 133–157):

~~~~text
   133 |     max_turns: Optional[int] = None,
   134 | ) -> List[str]:
   135 |     """The headless `claude -p` argv: JSON output, plan mode (read-only), no
   136 |     session persistence, every tool disabled (`--tools ""` is the documented
   137 |     "disable all" sentinel), the model, then `--effort` when set.
   138 |     ``prompt=None``: the prompt travels on stdin. ``max_turns`` is for callers
   139 |     outside the adapter (tools/ceiling-probe-live.py pins 1); the adapter does
   140 |     not pass it. cycle-127 D-3.9: one builder, so the probe measures the shape
   141 |     the adapter dispatches."""
   142 |     cmd: List[str] = [
   143 |         cli_bin,
   144 |         "-p",
>  145 |         *([] if prompt is None else [prompt]),
   146 |         "--output-format",
   147 |         "json",
   148 |         "--permission-mode",
   149 |         "plan",
   150 |         "--no-session-persistence",
   151 |         "--tools",
   152 |         "",
   153 |         "--model",
   154 |         cli_model,
   155 |     ]
   156 |     if effort:
   157 |         cmd.extend(["--effort", effort])
~~~~

The change from head to the fix:

~~~~diff
@@ -145 +145,0 @@
-        *([] if prompt is None else [prompt]),
~~~~

## H36 — .claude/adapters/loa_cheval/providers/claude_headless_adapter.py — insertion after head line 162

Head context (head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py, lines 151–174):

~~~~text
   151 |         "--tools",
   152 |         "",
   153 |         "--model",
   154 |         cli_model,
   155 |     ]
   156 |     if effort:
   157 |         cmd.extend(["--effort", effort])
   158 |     if max_turns is not None:
   159 |         cmd.extend(["--max-turns", str(int(max_turns))])
   160 |     return cmd
   161 | 
   162 | 
   163 | class ClaudeHeadlessAdapter(HeadlessCLIAdapter):
   164 |     """Adapter that routes inference through `claude -p` (non-interactive).
   165 | 
   166 |     Provider config (no auth field — OAuth-managed):
   167 | 
   168 |         providers:
   169 |           claude-headless:
   170 |             type: claude-headless
   171 |             connect_timeout: 10.0
   172 |             read_timeout: 600.0
   173 |             models:
   174 |               claude-opus-5-5:
~~~~

The change from head to the fix:

~~~~diff
@@ -162,0 +163,4 @@
+# r251-5 U3: the static-auth markers that outrank a `please wait`-only throttle match in _raise_for_error
+_STATIC_AUTH_MARKERS = ("not logged in", "/login", "authentication", "invalid api key", "unauthorized")
+
+
~~~~

## H37 — .claude/adapters/loa_cheval/providers/claude_headless_adapter.py — insertion after head line 186

Head context (head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py, lines 175–198):

~~~~text
   175 |                 context_window: 1000000
   176 |                 pricing: {input_per_mtok: 0, output_per_mtok: 0}
   177 |                 extra:
   178 |                   effort: high
   179 | 
   180 |     Aliases bind to provider:model-id like other adapters:
   181 | 
   182 |         aliases:
   183 |           opus: claude-headless:claude-opus-5-5
   184 |           cheap: claude-headless:claude-sonnet-5
   185 |     """
   186 | 
   187 |     # Cycle-110 FR-2.3 — subscription-CLI dispatch; circuit-breaker writes
   188 |     # route to the (anthropic, headless) bucket.
   189 |     auth_type: str = "headless"
   190 | 
   191 |     _cli_type = "claude-headless"
   192 |     _cli_name = "claude"
   193 |     _command_label = "claude -p"
   194 |     _install_hint = 'Install with: npm install -g @anthropic-ai/claude-code'
   195 |     _logger = logger
   196 | 
   197 |     def _run_subprocess(self, command, **kwargs):
   198 |         # Keep the provider's subprocess seam available to callers and tests.
~~~~

The change from head to the fix:

~~~~diff
@@ -186,0 +191,9 @@
+    @classmethod
+    def wire_effort(cls, model_id, effort, extra=None):
+        """cycle-127 r251-1 C5: `--effort` (request.effort first, then the entry extra.effort) — the adapter's own resolver over a request
+        carrying ``effort`` and no metadata (cheval sets none), so the record
+        follows the argv builder."""
+        import types as _types
+        req = CompletionRequest(messages=[], model=model_id, effort=effort)
+        return cls._resolve_effort(cls.__new__(cls), req, _types.SimpleNamespace(extra=dict(extra or {})))
+
~~~~

## H38 — .claude/adapters/loa_cheval/providers/claude_headless_adapter.py — head lines 298–300

Head context (head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py, lines 286–312):

~~~~text
   286 |         self,
   287 |         request: CompletionRequest,
   288 |         model_config,
   289 |         prompt: Optional[str],
   290 |     ) -> List[str]:
   291 |         """Build the claude argv. Headless, plan-mode (read-only), no tools. ``prompt=None``: the prompt is on stdin."""
   292 |         # cycle-104 sprint-2 T2.11 amendment: when the chain entry is a
   293 |         # kind:cli alias (e.g. `claude-headless`) the CLI binary doesn't
   294 |         # recognize the Loa alias as a model name. Honor `extra.cli_model`
   295 |         # if declared so the operator can map the alias to a real CLI
   296 |         # model identifier (e.g. `sonnet`, `opus`).
   297 |         cli_model = (model_config.extra or {}).get("cli_model") or request.model
>  298 |         cmd = build_headless_argv(
>  299 |             self._cli_bin(), cli_model, prompt=prompt, effort=self._resolve_effort(request, model_config),
>  300 |         )
   301 | 
   302 |         # cycle-124 FR-7: forward the schema compactly when the CLI knows the
   303 |         # flag; otherwise the call proceeds unenforced (schema_enforced false).
   304 |         if request.output_schema is not None and _cli_supports_json_schema(self._cli_bin()):
   305 |             cmd.extend(["--json-schema", json.dumps(request.output_schema, separators=(",", ":"))])
   306 | 
   307 |         extra = (model_config.extra or {})
   308 | 
   309 |         # System prompt overrides — `system_prompt` REPLACES the default
   310 |         # Claude Code agent prompt (saves ~14K cache tokens but loses agent
   311 |         # context). `append_system_prompt` ADDS to the default. Mutually
   312 |         # compatible with the CLI; we pass whichever is set.
~~~~

The change from head to the fix:

~~~~diff
@@ -298,3 +311 @@
-        cmd = build_headless_argv(
-            self._cli_bin(), cli_model, prompt=prompt, effort=self._resolve_effort(request, model_config),
-        )
+        cmd = build_headless_argv(self._cli_bin(), cli_model, effort=self._resolve_effort(request, model_config))
~~~~

## H39 — .claude/adapters/loa_cheval/providers/claude_headless_adapter.py — insertion after head line 341

Head context (head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py, lines 330–353):

~~~~text
   330 | 
   331 |         # Forward additional `claude` flags an operator may need but we
   332 |         # haven't promoted to first-class fields. Format: list of strings or
   333 |         # [flag, value] pairs.
   334 |         extra_flags = extra.get("claude_extra_flags")
   335 |         if isinstance(extra_flags, list):
   336 |             for entry in extra_flags:
   337 |                 if isinstance(entry, str):
   338 |                     cmd.append(entry)
   339 |                 elif isinstance(entry, list):
   340 |                     cmd.extend(str(x) for x in entry)
   341 | 
   342 |         return cmd
   343 | 
   344 |     def _resolve_effort(
   345 |         self,
   346 |         request: CompletionRequest,
   347 |         model_config,
   348 |     ) -> Optional[str]:
   349 |         """Resolve effort with explicit precedence (matches codex pattern).
   350 | 
   351 |         Priority:
   352 |           1. request.effort (cheval --effort, cycle-124)
   353 |           2. request.metadata["effort"] OR ["reasoning_effort"]
~~~~

The change from head to the fix:

~~~~diff
@@ -341,0 +353,4 @@
+        # (r251-4 S8, audit n26: an argv prompt — the adapter itself sends none — goes LAST, after the option terminator,
+        # so a prompt that starts with "-" is never parsed as a flag)
+        if prompt is not None:
+            cmd.extend(["--", prompt])
~~~~

## H40 — .claude/adapters/loa_cheval/providers/claude_headless_adapter.py — head lines 543–553

Head context (head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py, lines 531–565):

~~~~text
   531 |         We prefer that over stderr when present.
   532 |         """
   533 |         if parsed and isinstance(parsed, dict) and parsed.get("is_error"):
   534 |             err_msg = str(parsed.get("result") or "")
   535 |             api_status = parsed.get("api_error_status")
   536 |             full_diag = f"{err_msg}" + (f" (api_status={api_status})" if api_status else "")
   537 |         else:
   538 |             err_msg = stderr
   539 |             full_diag = stderr.strip() or f"exit code {returncode}"
   540 | 
   541 |         diag_lower = full_diag.lower()
   542 | 
>  543 |         # Rate-limit / overload — Anthropic returns 429 + "rate limit" or
>  544 |         # 529 + "overloaded" when the org / subscription quota is saturated.
>  545 |         if (
>  546 |             "rate limit" in diag_lower
>  547 |             or "429" in full_diag
>  548 |             or "529" in full_diag
>  549 |             or "overloaded" in diag_lower
>  550 |             or "too many requests" in diag_lower
>  551 |             or "quota" in diag_lower
>  552 |         ):
>  553 |             raise RateLimitError(self.provider)
   554 | 
   555 |         # Runtime auth revocation → WALKABLE (KF-017/#1071). Ambiguous
   556 |         # "unauthorized"/"401" walkable only when no static-misconfig marker.
   557 |         _static_auth = (
   558 |             "not logged in" in diag_lower
   559 |             or "/login" in diag_lower
   560 |         )
   561 |         if (
   562 |             "invalidated" in diag_lower
   563 |             or "session expired" in diag_lower
   564 |             or "token expired" in diag_lower
   565 |             or (("unauthorized" in diag_lower or "401" in full_diag) and not _static_auth)
~~~~

The change from head to the fix:

~~~~diff
@@ -543,11 +558,31 @@
-        # Rate-limit / overload — Anthropic returns 429 + "rate limit" or
-        # 529 + "overloaded" when the org / subscription quota is saturated.
-        if (
-            "rate limit" in diag_lower
-            or "429" in full_diag
-            or "529" in full_diag
-            or "overloaded" in diag_lower
-            or "too many requests" in diag_lower
-            or "quota" in diag_lower
-        ):
-            raise RateLimitError(self.provider)
+        # cycle-127 review r251-2 K8 (n65): the CLI's own pre-flight size rejection ("Prompt is too long", "the request
+        # is ~1065182 tokens (limit 1000000)") is the provider's size verdict on the payload — not walked (the next voice
+        # would get the same payload), never a breaker count. r251-3 R1: unless a throttle marker is present — ONE rule
+        # with the ceiling probe (routing.ceiling.is_throttle_message, SDD D-3.12): Bedrock's tokens-per-minute throttle
+        # "Too many tokens, please wait before trying again" carries the context marker `too many tokens`, and a
+        # 429 / 529 counts only in status position (never digits inside a stated token count).
+        from loa_cheval.routing.ceiling import (
+            is_context_limit_message, is_throttle_beyond_wait, is_throttle_message, is_token_limit_message,
+            parse_context_limit,
+        )
+        _throttle = is_throttle_message(full_diag)
+        # r251-5 U3 (audit LOW-003): a static-auth marker outranks a throttle that rests on `please wait` alone ("Not
+        # logged in · please wait, then run /login" is an auth failure, never retried and walked); a 429 / 529 status or
+        # a named rate / token / overload / quota marker still wins as the throttle.
+        if _throttle and any(m in diag_lower for m in _STATIC_AUTH_MARKERS) and not is_throttle_beyond_wait(full_diag):
+            _throttle = False
+        if is_context_limit_message(full_diag) and not _throttle:
+            _nums = parse_context_limit(full_diag)
+            raise ProviderContextLimitError(
+                self.provider,
+                f"claude CLI refused the prompt as too large: {full_diag[:500]}",
+                input_tokens=_nums.get("input_tokens"),
+                limit=_nums.get("limit"),
+                max_tokens=_nums.get("max_tokens"),
+            )
+
+        # Rate-limit / overload / quota / token throttle — Anthropic returns 429 + "rate limit" or 529 + "overloaded"
+        # when the org / subscription quota is saturated; Bedrock "Too many tokens, please wait". token_limited marks
+        # the token class (cheval's D-1.1b arm reads it only for a hop above its probed bound; a CLI hop has none).
+        if _throttle:
+            raise RateLimitError(self.provider, token_limited=is_token_limit_message(full_diag))
~~~~

## H41 — .claude/adapters/loa_cheval/providers/claude_headless_adapter.py — insertion after head line 577

Head context (head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py, lines 566–589):

~~~~text
   566 |         ):
   567 |             raise AuthRevokedError(
   568 |                 self.provider,
   569 |                 f"claude token revoked/expired — re-auth with {_CLAUDE_LOGIN_HINT}. "
   570 |                 f"(diagnostic: {full_diag[:300]})",
   571 |             )
   572 | 
   573 |         # Static misconfig (never authenticated / no key) → hard-abort.
   574 |         # Auth failure — Claude Code's most common first-run failure
   575 |         if (
   576 |             "not logged in" in diag_lower
   577 |             or "/login" in diag_lower
   578 |             or "unauthorized" in diag_lower
   579 |             or "401" in full_diag
   580 |             or "authentication" in diag_lower
   581 |             or "credential" in diag_lower
   582 |         ):
   583 |             raise ConfigError(
   584 |                 f"claude CLI not authenticated. Run: {_CLAUDE_LOGIN_HINT}. "
   585 |                 f"(diagnostic: {full_diag[:300]})"
   586 |             )
   587 | 
   588 |         snippet = full_diag[:500] or f"exit code {returncode}, no diagnostic"
   589 |         raise ProviderUnavailableError(
~~~~

The change from head to the fix:

~~~~diff
@@ -577,0 +613 @@
+            or "invalid api key" in diag_lower   # (r251-5 U3: one of the static-auth markers above)
~~~~

## H42 — .claude/adapters/loa_cheval/types.py — insertion after head line 9

Head context (head/.claude/adapters/loa_cheval/types.py, lines 1–21):

~~~~text
     1 | """Hounfour canonical types — extracted from loa-finn types.ts (SDD §4.2.3)."""
     2 | 
     3 | from __future__ import annotations
     4 | 
     5 | import threading
     6 | from dataclasses import dataclass, field
     7 | from typing import Any, Dict, List, Literal, Optional
     8 | 
     9 | 
    10 | # --- Completion Request/Result ---
    11 | 
    12 | 
    13 | @dataclass
    14 | class CompletionRequest:
    15 |     """Canonical request sent to any provider adapter."""
    16 | 
    17 |     messages: List[Dict[str, Any]]  # [{"role": "system"|"user"|"assistant"|"tool", "content": str}]
    18 |     model: str  # Provider-specific model ID (e.g., "gpt-5.2")
    19 |     # cycle-126 FR-1.3 (SDD D-1.3): unset by default — the wire carries no
    20 |     # sampling parameter unless a caller sets one (thinking models reject it,
    21 |     # the rest use the provider default). LOA_CHEVAL_LEGACY_WIRE restores the
~~~~

The change from head to the fix:

~~~~diff
@@ -9,0 +10,8 @@
+# cycle-127 r251-1 C5: the reasoning-effort levels, defined once. cheval's
+# resolver and its `--effort` choices, the Anthropic adapter's validation, the
+# v3 catalog schema (`params.default_effort`) and the MODELINV payload schema
+# (`effort` / `effort_effective`) all use this set
+# (tests/test_effort_levels_single_source.py pins the schemas to it).
+EFFORT_LEVELS = ("low", "medium", "high", "xhigh", "max")
+
+
~~~~

## H43 — .claude/adapters/loa_cheval/types.py — head lines 499–500

Head context (head/.claude/adapters/loa_cheval/types.py, lines 487–512):

~~~~text
   487 |                 "transport_class": transport_class,
   488 |                 "request_size_bytes": request_size_bytes,
   489 |             },
   490 |         )
   491 |         self.provider = provider
   492 |         self.transport_class = transport_class
   493 |         self.request_size_bytes = request_size_bytes
   494 | 
   495 | 
   496 | class ConfigError(ChevalError):
   497 |     """Invalid configuration."""
   498 | 
>  499 |     def __init__(self, message: str):
>  500 |         super().__init__("INVALID_CONFIG", message, retryable=False)
   501 | 
   502 | 
   503 | class AgyOptInRequiredError(ConfigError):
   504 |     """The agy (Antigravity) headless route is opt-in and `hounfour.headless.agy_opt_in` is not `true` (cycle-127 FR-1).
   505 | 
   506 |     An INVALID_CONFIG refusal raised before any binary discovery or spawn; `failure_class` (also in `context`) is the
   507 |     machine-readable seam planners read as "not planned", never as a failed voice.
   508 |     """
   509 | 
   510 |     failure_class = "opt_in_required"
   511 |     MESSAGE = ("agy headless route is opt-in: set hounfour.headless.agy_opt_in: true (the prompt travels on the CLI's "
   512 |                "argv, readable by local users; the CLI must be OAuth-authed)")
~~~~

The change from head to the fix:

~~~~diff
@@ -499,2 +507,2 @@
-    def __init__(self, message: str):
-        super().__init__("INVALID_CONFIG", message, retryable=False)
+    def __init__(self, message: str, context: Optional[Dict[str, Any]] = None):
+        super().__init__("INVALID_CONFIG", message, retryable=False, context=context)
~~~~

## H44 — .claude/adapters/loa_cheval/types.py — head lines 515–516

Head context (head/.claude/adapters/loa_cheval/types.py, lines 503–528):

~~~~text
   503 | class AgyOptInRequiredError(ConfigError):
   504 |     """The agy (Antigravity) headless route is opt-in and `hounfour.headless.agy_opt_in` is not `true` (cycle-127 FR-1).
   505 | 
   506 |     An INVALID_CONFIG refusal raised before any binary discovery or spawn; `failure_class` (also in `context`) is the
   507 |     machine-readable seam planners read as "not planned", never as a failed voice.
   508 |     """
   509 | 
   510 |     failure_class = "opt_in_required"
   511 |     MESSAGE = ("agy headless route is opt-in: set hounfour.headless.agy_opt_in: true (the prompt travels on the CLI's "
   512 |                "argv, readable by local users; the CLI must be OAuth-authed)")
   513 | 
   514 |     def __init__(self, message: str = MESSAGE):
>  515 |         super().__init__(message)
>  516 |         self.context = {"failure_class": self.failure_class}
   517 | 
   518 | 
   519 | class AuthRevokedError(ChevalError):
   520 |     """Runtime auth-credential revocation on a CLI/subscription leg (KF-017/#1071).
   521 | 
   522 |     Distinct from ConfigError (INVALID_CONFIG / static misconfig). A token that
   523 |     WAS valid and is now server-side-invalidated ("401 Unauthorized: token
   524 |     invalidated", expired session) makes THIS leg unusable but says nothing
   525 |     about the operator's other legs. retryable=True, code AUTH_REVOKED so the
   526 |     cheval chain-walk loop walks to the next entry (e.g. a valid HTTP leg)
   527 |     rather than hard-aborting. NOT a ProviderUnavailableError subclass: it must
   528 |     reach cheval.py via retry.py's `except ChevalError: raise`, like
~~~~

The change from head to the fix:

~~~~diff
@@ -515,2 +523,2 @@
-        super().__init__(message)
-        self.context = {"failure_class": self.failure_class}
+        # (review r251-1 G5: through the base constructor — cheval's error envelope and MODELINV read `context`)
+        super().__init__(message, context={"failure_class": self.failure_class})
~~~~

## H45 — .claude/adapters/tests/test_agy_opt_in_gate.py — insertion after head line 9

Head context (head/.claude/adapters/tests/test_agy_opt_in_gate.py, lines 1–21):

~~~~text
     1 | """cycle-127 FR-1 — the agy (Antigravity) headless route is opt-in, default off.
     2 | 
     3 | `hounfour.headless.agy_opt_in` (a YAML boolean in .loa.config.yaml, default false) is read through the project-config layer.
     4 | Off: AgyHeadlessAdapter refuses before any binary discovery or spawn with INVALID_CONFIG, retryable false, failure_class
     5 | opt_in_required, naming the key and the reason. On: today's path (discovery, the one-time argv WARN, dispatch).
     6 | """
     7 | 
     8 | from __future__ import annotations
     9 | 
    10 | import subprocess
    11 | import sys
    12 | from pathlib import Path
    13 | from unittest.mock import MagicMock, patch
    14 | 
    15 | import pytest
    16 | 
    17 | sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    18 | 
    19 | from loa_cheval.config.loader import agy_opt_in_enabled
    20 | from loa_cheval.providers import get_adapter
    21 | from loa_cheval.types import AgyOptInRequiredError, ConfigError, ModelConfig, ProviderConfig, CompletionRequest
~~~~

The change from head to the fix:

~~~~diff
@@ -9,0 +10 @@
+import os
~~~~

## H46 — .claude/adapters/tests/test_agy_opt_in_gate.py — insertion after head line 22

Head context (head/.claude/adapters/tests/test_agy_opt_in_gate.py, lines 11–34):

~~~~text
    11 | import sys
    12 | from pathlib import Path
    13 | from unittest.mock import MagicMock, patch
    14 | 
    15 | import pytest
    16 | 
    17 | sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    18 | 
    19 | from loa_cheval.config.loader import agy_opt_in_enabled
    20 | from loa_cheval.providers import get_adapter
    21 | from loa_cheval.types import AgyOptInRequiredError, ConfigError, ModelConfig, ProviderConfig, CompletionRequest
    22 | 
    23 | _MOD = "loa_cheval.providers.agy_headless_adapter"
    24 | _REFUSAL = ("agy headless route is opt-in: set hounfour.headless.agy_opt_in: true (the prompt travels on the CLI's argv, "
    25 |             "readable by local users; the CLI must be OAuth-authed)")
    26 | 
    27 | 
    28 | def _adapter():
    29 |     return get_adapter(ProviderConfig(
    30 |         name="gemini-headless", type="gemini-headless", endpoint="", auth=None,
    31 |         models={"gemini-3-pro": ModelConfig(context_window=1048576, extra={"cli_model": "Gemini 3.1 Pro (High)"})},
    32 |     ))
    33 | 
    34 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -22,0 +24,12 @@
+@pytest.fixture(autouse=True)
+def _owner_only_umask():
+    """The fixtures' configs are written owner-only (umask 022): under a host umask of 002 a written config is
+    group-writable, which never opts in (r251-5 U2) — these tests are about the key, not the permission rule
+    (test_agy_opt_in_r251_4.py holds that)."""
+    old = os.umask(0o022)
+    try:
+        yield
+    finally:
+        os.umask(old)
+
+
~~~~

## H47 — .claude/adapters/tests/test_agy_opt_in_gate.py — insertion after head line 56

Head context (head/.claude/adapters/tests/test_agy_opt_in_gate.py, lines 45–68):

~~~~text
    45 | 
    46 | # --- the key, read through the project-config layer -----------------------------------------------------------------
    47 | 
    48 | @pytest.mark.parametrize("body,expected", [
    49 |     (None, False),                                                         # no .loa.config.yaml
    50 |     ("hounfour: {}\n", False),                                             # absent key
    51 |     ("hounfour:\n  headless:\n    mode: prefer-api\n", False),
    52 |     ("hounfour:\n  headless:\n    agy_opt_in: false\n", False),
    53 |     ("hounfour:\n  headless:\n    agy_opt_in: \"true\"\n", False),         # a string is not the boolean
    54 |     ("hounfour:\n  headless:\n    agy_opt_in: 1\n", False),
    55 |     ("hounfour:\n  headless: on-a-string\n", False),
    56 |     ("hounfour:\n  headless:\n    agy_opt_in: true\n", True),
    57 | ])
    58 | def test_the_key_is_a_yaml_boolean_default_false(tmp_path, body, expected):
    59 |     assert agy_opt_in_enabled(_project(tmp_path, body)) is expected
    60 | 
    61 | 
    62 | def test_an_unparsable_config_reads_as_off(tmp_path):
    63 |     assert agy_opt_in_enabled(_project(tmp_path, "hounfour: [unclosed\n")) is False
    64 | 
    65 | 
    66 | def test_no_environment_override(tmp_path, monkeypatch):
    67 |     for k in ("LOA_AGY_OPT_IN", "AGY_OPT_IN", "LOA_HOUNFOUR_HEADLESS_AGY_OPT_IN"):
    68 |         monkeypatch.setenv(k, "true")
~~~~

The change from head to the fix:

~~~~diff
@@ -56,0 +70,8 @@
+    # review r251-2 K1: ONE strict rule with the bash reader — only the scalar written exactly `true` opts in; PyYAML's
+    # YAML 1.1 truthy spellings (yes / on / True / TRUE) read off here as they do under go yq
+    ("hounfour:\n  headless:\n    agy_opt_in: yes\n", False),
+    ("hounfour:\n  headless:\n    agy_opt_in: on\n", False),
+    ("hounfour:\n  headless:\n    agy_opt_in: True\n", False),
+    ("hounfour:\n  headless:\n    agy_opt_in: TRUE\n", False),
+    ("hounfour:\n  headless:\n    agy_opt_in: !!bool true\n", True),
+    ("hounfour:\n  headless: {agy_opt_in: true}\n", True),
~~~~

## H48 — .claude/adapters/tests/test_agy_opt_in_gate.py — head lines 72–73

Head context (head/.claude/adapters/tests/test_agy_opt_in_gate.py, lines 60–85):

~~~~text
    60 | 
    61 | 
    62 | def test_an_unparsable_config_reads_as_off(tmp_path):
    63 |     assert agy_opt_in_enabled(_project(tmp_path, "hounfour: [unclosed\n")) is False
    64 | 
    65 | 
    66 | def test_no_environment_override(tmp_path, monkeypatch):
    67 |     for k in ("LOA_AGY_OPT_IN", "AGY_OPT_IN", "LOA_HOUNFOUR_HEADLESS_AGY_OPT_IN"):
    68 |         monkeypatch.setenv(k, "true")
    69 |     assert agy_opt_in_enabled(_project(tmp_path, "hounfour: {}\n")) is False
    70 | 
    71 | 
>   72 | def test_the_project_root_defaults_to_the_cwd_walk(tmp_path, monkeypatch):
>   73 |     root = _project(tmp_path, "hounfour:\n  headless:\n    agy_opt_in: true\n")
    74 |     (tmp_path / "sub").mkdir()
    75 |     monkeypatch.chdir(tmp_path / "sub")
    76 |     assert agy_opt_in_enabled() is True
    77 |     assert Path(root).is_dir()
    78 | 
    79 | 
    80 | # --- the adapter refuses before discovery ---------------------------------------------------------------------------
    81 | 
    82 | def test_off_refuses_before_any_discovery_or_spawn(monkeypatch):
    83 |     monkeypatch.setattr(f"{_MOD}.agy_opt_in_enabled", lambda *a, **k: False)
    84 |     which, pgkill, run, ws = MagicMock(return_value="/usr/bin/agy"), MagicMock(), MagicMock(), MagicMock(return_value="/x")
    85 |     with patch(f"{_MOD}.shutil.which", which), patch(f"{_MOD}.run_subprocess_pgkill", pgkill), \
~~~~

The change from head to the fix:

~~~~diff
@@ -72,2 +93,9 @@
+def _this_cheval(tmp_path):
+    """(r251-4 S2) the cwd walk's root is honoured only when its .claude/adapters IS this cheval (the submodule mount's
+    symlink shape); a bare .claude/ is someone else's tree and the opt-in falls back to cheval's install root."""
+    (tmp_path / ".claude" / "adapters").symlink_to(Path(__file__).resolve().parent.parent, target_is_directory=True)
+
+
 def test_the_project_root_defaults_to_the_cwd_walk(tmp_path, monkeypatch):
     root = _project(tmp_path, "hounfour:\n  headless:\n    agy_opt_in: true\n")
+    _this_cheval(tmp_path)
~~~~

## H49 — .claude/adapters/tests/test_agy_opt_in_gate.py — insertion after head line 146

Head context (head/.claude/adapters/tests/test_agy_opt_in_gate.py, lines 135–154):

~~~~text
   135 | 
   136 | def test_on_dispatches_as_today(monkeypatch):
   137 |     monkeypatch.setattr(f"{_MOD}.agy_opt_in_enabled", lambda *a, **k: True)
   138 |     pgkill = MagicMock(return_value=subprocess.CompletedProcess(["agy"], 0, "APPROVED", ""))
   139 |     with patch(f"{_MOD}.run_subprocess_pgkill", pgkill):
   140 |         assert _adapter().complete(_req()).content == "APPROVED"
   141 |     assert pgkill.call_args[0][0][:2] == ["agy", "-p"]
   142 | 
   143 | 
   144 | def test_the_adapter_reads_the_real_project_config(tmp_path, monkeypatch):
   145 |     """No monkeypatch of the reader: a project whose config carries no key refuses; `true` dispatches."""
   146 |     _project(tmp_path, "hounfour:\n  headless:\n    mode: prefer-api\n")
   147 |     monkeypatch.chdir(tmp_path)
   148 |     pgkill = MagicMock(return_value=subprocess.CompletedProcess(["agy"], 0, "APPROVED", ""))
   149 |     with patch(f"{_MOD}.run_subprocess_pgkill", pgkill):
   150 |         with pytest.raises(AgyOptInRequiredError):
   151 |             _adapter().complete(_req())
   152 |         pgkill.assert_not_called()
   153 |         (tmp_path / ".loa.config.yaml").write_text("hounfour:\n  headless:\n    agy_opt_in: true\n")
   154 |         assert _adapter().complete(_req()).content == "APPROVED"
~~~~

The change from head to the fix:

~~~~diff
@@ -146,0 +175 @@
+    _this_cheval(tmp_path)
~~~~

## H50 — .claude/adapters/tests/test_agy_opt_in_gate.py — insertion after head line 154

Head context (head/.claude/adapters/tests/test_agy_opt_in_gate.py, lines 143–154):

~~~~text
   143 | 
   144 | def test_the_adapter_reads_the_real_project_config(tmp_path, monkeypatch):
   145 |     """No monkeypatch of the reader: a project whose config carries no key refuses; `true` dispatches."""
   146 |     _project(tmp_path, "hounfour:\n  headless:\n    mode: prefer-api\n")
   147 |     monkeypatch.chdir(tmp_path)
   148 |     pgkill = MagicMock(return_value=subprocess.CompletedProcess(["agy"], 0, "APPROVED", ""))
   149 |     with patch(f"{_MOD}.run_subprocess_pgkill", pgkill):
   150 |         with pytest.raises(AgyOptInRequiredError):
   151 |             _adapter().complete(_req())
   152 |         pgkill.assert_not_called()
   153 |         (tmp_path / ".loa.config.yaml").write_text("hounfour:\n  headless:\n    agy_opt_in: true\n")
   154 |         assert _adapter().complete(_req()).content == "APPROVED"
~~~~

The change from head to the fix:

~~~~diff
@@ -154,0 +184,219 @@
+
+
+# --- review r251-1 ---------------------------------------------------------------------------------------------------
+
+def test_g4_a_root_discovery_failure_reads_as_off(monkeypatch):
+    """finding 3: the root walk sits inside the fail-closed try."""
+    import loa_cheval.config.loader as loader
+
+    def _boom():
+        raise OSError("cwd vanished")
+    monkeypatch.setattr(loader, "_find_project_root", _boom)
+    assert agy_opt_in_enabled() is False
+
+
+def test_g5_the_refusal_carries_its_failure_class_through_the_base_constructor():
+    """finding 5: context is passed to ChevalError, not patched on after it."""
+    import inspect
+    from loa_cheval.types import ChevalError
+    err = AgyOptInRequiredError()
+    assert err.context == {"failure_class": "opt_in_required"}
+    assert "self.context =" not in inspect.getsource(AgyOptInRequiredError)
+    # a plain ConfigError still constructs with an empty context
+    assert ConfigError("x").context == {}
+    assert isinstance(err, ChevalError) and err.code == "INVALID_CONFIG"
+
+
+def test_g6_off_validate_config_reports_only_the_opt_in(monkeypatch):
+    """finding 4: the binary is irrelevant while the route is off — no PATH lookup, no 'CLI not found' line."""
+    monkeypatch.setattr(f"{_MOD}.agy_opt_in_enabled", lambda *a, **k: False)
+    which = MagicMock(return_value=None)
+    with patch(f"{_MOD}.shutil.which", which):
+        errs = _adapter().validate_config()
+    assert len(errs) == 1 and "hounfour.headless.agy_opt_in" in errs[0], errs
+    which.assert_not_called()
+
+
+def test_g6_on_validate_config_still_checks_the_binary(monkeypatch):
+    monkeypatch.setattr(f"{_MOD}.agy_opt_in_enabled", lambda *a, **k: True)
+    with patch(f"{_MOD}.shutil.which", return_value=None):
+        errs = _adapter().validate_config()
+    assert any("CLI not found on PATH" in e for e in errs)
+    assert not any("hounfour.headless.agy_opt_in" in e for e in errs)
+
+
+# --- review r251-1 G2: the Python twin of the bash routes_to_agy predicate ------------------------------------------
+
+@pytest.mark.parametrize("model,mode,expected", [
+    ("gemini-headless", None, True),
+    ("google:gemini-headless", None, True),
+    ("gemini-headless:any", None, True),
+    ("gemini-headless", "prefer-api", True),
+    ("gemini-2.5-pro", "prefer-api", False),
+    ("gemini-2.5-pro", None, False),
+    ("gemini-2.5-pro", "cli-only", True),
+    ("google:gemini-3.1-pro", "cli-only", True),
+    ("gemini-2.5-pro", "prefer-cli", False),
+    ("claude-headless", "cli-only", False),
+    ("gpt-5.5", "cli-only", False),
+    ("", "cli-only", False),
+    # r251-3 R3: under cli-only the PROVIDER decides (resolved through the catalog, aliases included), as in cheval's
+    # _entry_routes_to_agy and Bridgebuilder's isAgyRouted — deep-research-pro is a Google model without the prefix
+    ("deep-research-pro", "cli-only", True),
+    ("google:deep-research-pro", "cli-only", True),
+    ("researcher", "cli-only", True),
+    ("deep-research-pro", "prefer-api", False),
+    ("deep-research-pro", "prefer-cli", False),
+    ("opus", "cli-only", False),
+    ("claude-opus-5-5", "cli-only", False),
+    ("anthropic:claude-opus-5-5", "cli-only", False),
+])
+def test_routes_to_agy_matches_the_bash_rule(model, mode, expected):
+    from loa_cheval.config.loader import routes_to_agy
+    assert routes_to_agy(model, mode) is expected
+
+
+# --- review r251-1 G9: the opt-in is operator-only (project config), never satisfied by framework defaults -------------
+
+def test_g9_system_defaults_alone_never_opt_in(tmp_path):
+    root = _project(tmp_path, "hounfour:\n  headless:\n    mode: prefer-api\n")
+    (tmp_path / ".claude" / "defaults").mkdir(parents=True)
+    (tmp_path / ".claude" / "defaults" / "model-config.yaml").write_text("headless:\n  agy_opt_in: true\n")
+    assert agy_opt_in_enabled(root) is False
+    (tmp_path / ".loa.config.yaml").write_text("hounfour:\n  headless:\n    agy_opt_in: true\n")
+    assert agy_opt_in_enabled(root) is True
+
+
+# --- review r251-1 G12: a present non-boolean value reads off and is said once, naming the key and the type ------------
+
+def test_g12_a_string_true_reads_off_with_one_warn(tmp_path, monkeypatch, caplog):
+    import logging
+    import loa_cheval.config.loader as loader
+    monkeypatch.setattr(loader, "_AGY_TYPE_WARNED", False, raising=False)
+    root = _project(tmp_path, "hounfour:\n  headless:\n    agy_opt_in: \"true\"\n")
+    with caplog.at_level(logging.WARNING):
+        for _ in range(3):
+            assert agy_opt_in_enabled(root) is False
+    warns = [r for r in caplog.records if "hounfour.headless.agy_opt_in" in r.getMessage()]
+    assert len(warns) == 1, [r.getMessage() for r in caplog.records]
+    assert "boolean" in warns[0].getMessage() and "str" in warns[0].getMessage()
+
+
+def test_g12_absent_and_boolean_values_never_warn(tmp_path, monkeypatch, caplog):
+    import logging
+    import loa_cheval.config.loader as loader
+    monkeypatch.setattr(loader, "_AGY_TYPE_WARNED", False, raising=False)
+    with caplog.at_level(logging.WARNING):
+        for body in ("hounfour: {}\n", "hounfour:\n  headless:\n    agy_opt_in: false\n", "hounfour:\n  headless:\n    agy_opt_in: true\n"):
+            sub = tmp_path / str(abs(hash(body)))
+            sub.mkdir()
+            agy_opt_in_enabled(_project(sub, body))
+    assert not [r for r in caplog.records if "hounfour.headless.agy_opt_in" in r.getMessage()]
+
+
+@pytest.mark.parametrize("spelling", ["yes", "on", "True", "TRUE", "1", '"true"', "False", "no"])
+def test_k1_a_non_canonical_spelling_reads_off_with_one_warn_naming_the_accepted_spelling(tmp_path, monkeypatch, caplog,
+                                                                                         spelling):
+    """review r251-2 K1 (n16): the Python reader used to accept PyYAML's truthy spellings while the bash reader (go yq,
+    tag !!bool and the literal true) refused them — a split-brain on the security-relevant route. Now both refuse, and a
+    present value not written exactly `true` / `false` is said once, naming the key and the accepted spelling."""
+    import logging
+    import loa_cheval.config.loader as loader
+    monkeypatch.setattr(loader, "_AGY_TYPE_WARNED", False, raising=False)
+    root = _project(tmp_path, f"hounfour:\n  headless:\n    agy_opt_in: {spelling}\n")
+    with caplog.at_level(logging.WARNING):
+        for _ in range(3):
+            assert agy_opt_in_enabled(root) is False
+    warns = [r.getMessage() for r in caplog.records if "hounfour.headless.agy_opt_in" in r.getMessage()]
+    assert len(warns) == 1, [r.getMessage() for r in caplog.records]
+    assert "agy_opt_in: true" in warns[0], warns[0]
+
+
+def test_k1_the_strict_rule_holds_without_pyyaml(tmp_path, monkeypatch):
+    """The yq fallback (no PyYAML) applies the same strict rule: the typed go-yq expression, never `== true` alone."""
+    import shutil
+    import loa_cheval.config.loader as loader
+    if not shutil.which("yq"):
+        pytest.skip("yq not installed")
+    monkeypatch.setattr(loader, "_HAS_YAML", False, raising=False)
+    monkeypatch.setattr(loader, "_AGY_TYPE_WARNED", True, raising=False)
+    for spelling, want in (("true", True), ("True", False), ('"true"', False), ("yes", False), ("false", False)):
+        sub = tmp_path / f"s{abs(hash(spelling))}"
+        sub.mkdir()
+        assert agy_opt_in_enabled(_project(sub, f"hounfour:\n  headless:\n    agy_opt_in: {spelling}\n")) is want, spelling
+
+
+# --- review r251-1 G18 (SDD D-1.7): the route is available here but not opted in — one WARN per process --------------
+
+def _fake_agy(tmp_path, monkeypatch):
+    bindir = tmp_path / "bin"
+    bindir.mkdir()
+    marker = tmp_path / "spawned"
+    agy = bindir / "agy"
+    agy.write_text(f"#!/bin/sh\necho spawned > {marker}\n")
+    agy.chmod(0o755)
+    monkeypatch.setenv("PATH", f"{bindir}:/usr/bin:/bin")
+    return marker
+
+
+def test_g18_agy_on_path_with_the_opt_in_off_warns_once_and_spawns_nothing(tmp_path, monkeypatch, caplog):
+    import logging
+    import loa_cheval.config.loader as loader
+    monkeypatch.setattr(loader, "_AGY_AVAILABLE_WARNED", False, raising=False)
+    for k in ("GOOGLE_API_KEY", "GEMINI_API_KEY"):
+        monkeypatch.delenv(k, raising=False)
+    marker = _fake_agy(tmp_path, monkeypatch)
+    root = _project(tmp_path, "hounfour: {}\n")
+    with caplog.at_level(logging.WARNING):
+        for _ in range(3):
+            loader.warn_agy_available_once(root)
+    warns = [r for r in caplog.records if "hounfour.headless.agy_opt_in" in r.getMessage()]
+    assert len(warns) == 1, [r.getMessage() for r in caplog.records]
+    assert "argv" in warns[0].getMessage() and "agy on PATH" in warns[0].getMessage()
+    assert not marker.exists()
+
+
+def test_g18_a_gemini_key_alone_warns_too_and_the_opt_in_on_is_silent(tmp_path, monkeypatch, caplog):
+    import logging
+    import loa_cheval.config.loader as loader
+    monkeypatch.setenv("PATH", "/usr/bin:/bin")
+    monkeypatch.setenv("GEMINI_API_KEY", "fixture-not-a-key")
+    monkeypatch.setattr(loader, "_AGY_AVAILABLE_WARNED", False, raising=False)
+    root = _project(tmp_path, "hounfour: {}\n")
+    with caplog.at_level(logging.WARNING):
+        loader.warn_agy_available_once(root)
+    assert len([r for r in caplog.records if "hounfour.headless.agy_opt_in" in r.getMessage()]) == 1
+    caplog.clear()
+    monkeypatch.setattr(loader, "_AGY_AVAILABLE_WARNED", False, raising=False)
+    (tmp_path / ".loa.config.yaml").write_text("hounfour:\n  headless:\n    agy_opt_in: true\n")
+    with caplog.at_level(logging.WARNING):
+        loader.warn_agy_available_once(root)
+    assert not [r for r in caplog.records if "hounfour.headless.agy_opt_in" in r.getMessage()]
+
+
+def test_g18_nothing_available_is_silent(tmp_path, monkeypatch, caplog):
+    import logging
+    import loa_cheval.config.loader as loader
+    monkeypatch.setenv("PATH", "/usr/bin:/bin")
+    for k in ("GOOGLE_API_KEY", "GEMINI_API_KEY"):
+        monkeypatch.delenv(k, raising=False)
+    monkeypatch.setattr(loader, "_AGY_AVAILABLE_WARNED", False, raising=False)
+    import shutil
+    if shutil.which("agy"):
+        pytest.skip("agy is on the system PATH")
+    with caplog.at_level(logging.WARNING):
+        loader.warn_agy_available_once(_project(tmp_path, "hounfour: {}\n"))
+    assert not [r for r in caplog.records if "hounfour.headless.agy_opt_in" in r.getMessage()]
+
+
+# --- review r251-1 G5 (extended, D-1.6): an opt-in refusal never touches the circuit breaker ---------------------------
+
+def test_g5_an_opt_in_refusal_leaves_the_breaker_count_unchanged(monkeypatch):
+    from loa_cheval.providers import retry
+    monkeypatch.setattr(f"{_MOD}.agy_opt_in_enabled", lambda *a, **k: False)
+    recorded = MagicMock()
+    monkeypatch.setattr(retry, "_record_failure", recorded)
+    monkeypatch.setattr(retry, "_check_circuit_breaker", lambda *a, **k: "CLOSED")
+    with pytest.raises(AgyOptInRequiredError):
+        retry.invoke_with_retry(_adapter(), _req(), {"routing": {}, "retry": {"max_retries": 2}})
+    recorded.assert_not_called()
~~~~

## H51 — .claude/adapters/tests/test_anthropic_catalog_floor.py — head line 24

Head context (head/.claude/adapters/tests/test_anthropic_catalog_floor.py, lines 12–36):

~~~~text
    12 | 
    13 | import sys
    14 | from pathlib import Path
    15 | 
    16 | import pytest
    17 | import yaml
    18 | 
    19 | sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    20 | 
    21 | from cheval import _LEGACY_TRANSPORT_INPUT_WALL, _lookup_max_input_tokens  # noqa: E402
    22 | from loa_cheval.providers.anthropic_adapter import _BETA_HEADER_RE  # noqa: E402
    23 | from loa_cheval.providers.base import default_max_tokens  # noqa: E402
>   24 | from loa_cheval.routing.ceiling import input_bound  # noqa: E402
    25 | 
    26 | REPO_ROOT = Path(__file__).resolve().parents[3]
    27 | CATALOG = REPO_ROOT / ".claude" / "defaults" / "model-config.yaml"
    28 | LOA_CONFIG = REPO_ROOT / ".loa.config.yaml"
    29 | LOA_CONFIG_EXAMPLE = REPO_ROOT / ".loa.config.yaml.example"
    30 | 
    31 | # SDD §2.1 entry table.
    32 | FAMILY_1M = {
    33 |     "claude-fable-5-1",
    34 |     "claude-fable-5",
    35 |     "claude-opus-5-5",
    36 |     "claude-opus-5",
~~~~

The change from head to the fix:

~~~~diff
@@ -24 +24 @@
-from loa_cheval.routing.ceiling import input_bound  # noqa: E402
+from loa_cheval.routing.ceiling import input_bound, is_foreign_transport_calibration  # noqa: E402
~~~~

## H52 — .claude/adapters/tests/test_anthropic_catalog_floor.py — head lines 144–147

Head context (head/.claude/adapters/tests/test_anthropic_catalog_floor.py, lines 132–159):

~~~~text
   132 |         assert isinstance(cal.get("stale_after_days"), int) and cal["stale_after_days"] > 0, model_id
   133 | 
   134 | 
   135 | def _measured(entry: dict) -> bool:
   136 |     """cycle-127 FR-3.4: a calibrated entry (operator_set / empirical_probe with
   137 |     calibrated_at) carries its own measured bound — the 180K cap is the
   138 |     uncalibrated policy, so the test follows the catalog value there."""
   139 |     cal = entry.get("ceiling_calibration") or {}
   140 |     return bool(cal.get("calibrated_at")) and cal.get("source") in ("operator_set", "empirical_probe")
   141 | 
   142 | 
   143 | def test_ceiling_is_the_computed_value_per_entry(http_entries):
>  144 |     """SDD §2.1: ceiling = min(180000, context_window − default_max_tokens(entry)) — computed, not a constant."""
>  145 |     for model_id, entry in http_entries.items():
>  146 |         cap = entry["effective_input_ceiling"] if _measured(entry) else CEILING_CAP
>  147 |         expected = min(cap, entry["context_window"] - _default_max_tokens(entry))
   148 |         assert entry["effective_input_ceiling"] == expected, (model_id, entry["effective_input_ceiling"], expected)
   149 |         assert entry["effective_input_ceiling"] + _default_max_tokens(entry) <= entry["context_window"], model_id
   150 | 
   151 | 
   152 | @pytest.mark.parametrize("kill_switch", ["", "1"])
   153 | def test_input_gate_positive_with_and_without_streaming_kill_switch(catalog, http_entries, monkeypatch, kill_switch):
   154 |     if kill_switch:
   155 |         monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", kill_switch)
   156 |     else:
   157 |         monkeypatch.delenv("LOA_CHEVAL_DISABLE_STREAMING", raising=False)
   158 |     for model_id in http_entries:
   159 |         threshold = _lookup_max_input_tokens("anthropic", model_id, catalog)
~~~~

The change from head to the fix:

~~~~diff
@@ -144,4 +144,15 @@
-    """SDD §2.1: ceiling = min(180000, context_window − default_max_tokens(entry)) — computed, not a constant."""
+    """SDD §2.1: ceiling = min(180000, context_window − default_max_tokens(entry)) — computed, not a constant.
+    cycle-127 r251-1 (finding 33): a measured entry recording its raw accept is computed from it —
+    min(measured_input_tokens, context_window − default_max_tokens(entry)) (cheval's I2 clamp) — in
+    both fields; never the entry's own ceiling compared with itself."""
     for model_id, entry in http_entries.items():
-        cap = entry["effective_input_ceiling"] if _measured(entry) else CEILING_CAP
-        expected = min(cap, entry["context_window"] - _default_max_tokens(entry))
+        room = entry["context_window"] - _default_max_tokens(entry)
+        cal = entry.get("ceiling_calibration") or {}
+        if _measured(entry) and isinstance(cal.get("measured_input_tokens"), int):
+            expected = min(cal["measured_input_tokens"], room)
+            assert entry["probed_ceiling"] == entry["effective_input_ceiling"], model_id
+        elif _measured(entry):
+            # an API-transport probe write records no raw count: only the invariant is checkable
+            expected = min(entry["effective_input_ceiling"], room)
+        else:
+            expected = min(CEILING_CAP, room)
~~~~

## H53 — .claude/adapters/tests/test_anthropic_catalog_floor.py — insertion after head line 151

Head context (head/.claude/adapters/tests/test_anthropic_catalog_floor.py, lines 140–163):

~~~~text
   140 |     return bool(cal.get("calibrated_at")) and cal.get("source") in ("operator_set", "empirical_probe")
   141 | 
   142 | 
   143 | def test_ceiling_is_the_computed_value_per_entry(http_entries):
   144 |     """SDD §2.1: ceiling = min(180000, context_window − default_max_tokens(entry)) — computed, not a constant."""
   145 |     for model_id, entry in http_entries.items():
   146 |         cap = entry["effective_input_ceiling"] if _measured(entry) else CEILING_CAP
   147 |         expected = min(cap, entry["context_window"] - _default_max_tokens(entry))
   148 |         assert entry["effective_input_ceiling"] == expected, (model_id, entry["effective_input_ceiling"], expected)
   149 |         assert entry["effective_input_ceiling"] + _default_max_tokens(entry) <= entry["context_window"], model_id
   150 | 
   151 | 
   152 | @pytest.mark.parametrize("kill_switch", ["", "1"])
   153 | def test_input_gate_positive_with_and_without_streaming_kill_switch(catalog, http_entries, monkeypatch, kill_switch):
   154 |     if kill_switch:
   155 |         monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", kill_switch)
   156 |     else:
   157 |         monkeypatch.delenv("LOA_CHEVAL_DISABLE_STREAMING", raising=False)
   158 |     for model_id in http_entries:
   159 |         threshold = _lookup_max_input_tokens("anthropic", model_id, catalog)
   160 |         assert isinstance(threshold, int) and threshold > 0, (model_id, kill_switch, threshold)
   161 | 
   162 | 
   163 | def test_legacy_wall_applies_only_to_anthropic_under_the_kill_switch(catalog, http_entries, monkeypatch):
~~~~

The change from head to the fix:

~~~~diff
@@ -151,0 +163,37 @@
+def test_a_foreign_transport_calibration_carries_its_provenance(http_entries):
+    """cycle-127 r251-1 (finding 32): an HTTP entry trusting a bound measured on another
+    transport (ceiling_calibration.transport ≠ api) must say how it was measured and what
+    the provider accepted — `method` and `measured_input_tokens` — so the cross-transport
+    trust is auditable, and an observed limit on this route may tighten it (routing.ceiling)."""
+    foreign = [m for m, e in http_entries.items() if is_foreign_transport_calibration(e)]
+    # (review r251-2 K9 / n36: with zero foreign entries the loop would assert nothing — the live catalog has one)
+    assert "claude-opus-5-5" in foreign, foreign
+    for model_id in foreign:
+        entry = http_entries[model_id]
+        cal = entry["ceiling_calibration"]
+        # a bound measured on a non-API transport was measured headless — `probed_api` there is a mislabel (n36)
+        assert cal.get("method") == "probed_headless", (model_id, cal.get("transport"), cal.get("method"))
+        assert isinstance(cal.get("measured_input_tokens"), int) and cal["measured_input_tokens"] > 0, model_id
+        assert cal["measured_input_tokens"] >= entry["effective_input_ceiling"], (
+            f"{model_id}: the written bound may be clamped below the measured accept, never above it")
+
+
+def test_lookup_returns_the_concrete_bound_through_the_gate_path(catalog, monkeypatch):
+    """review r251-2 K9 (n35): one concrete check THROUGH `_lookup_max_input_tokens` — the gate answers a calibrated
+    entry's catalog bound (not the policy cap). claude-opus-5-5 is calibrated; claude-opus-5 is not, and answers its
+    probed value (the policy cap). r251-3 R2 (AC 3): the expectation is READ from the catalog, so this check moves
+    with the next re-probe instead of pinning today's bound by literal."""
+    monkeypatch.delenv("LOA_CHEVAL_DISABLE_STREAMING", raising=False)
+    monkeypatch.delenv("LOA_CHEVAL_LEGACY_WIRE", raising=False)
+    monkeypatch.setenv("LOA_CHEVAL_CEILING_OBSERVED_PATH", "/nonexistent/ceiling-observed.json")  # no host observations
+    cal = catalog["providers"]["anthropic"]["models"]["claude-opus-5-5"]
+    assert cal["ceiling_calibration"].get("calibrated_at"), "claude-opus-5-5 is expected to be calibrated"
+    want = cal["effective_input_ceiling"]
+    assert isinstance(want, int) and want != CEILING_CAP, want
+    assert input_bound(cal, max_tokens=_default_max_tokens(cal)).basis == "calibrated"
+    assert _lookup_max_input_tokens("anthropic", "claude-opus-5-5", catalog) == want
+    uncal = catalog["providers"]["anthropic"]["models"]["claude-opus-5"]
+    assert not uncal["ceiling_calibration"].get("calibrated_at")
+    assert _lookup_max_input_tokens("anthropic", "claude-opus-5", catalog) == uncal["probed_ceiling"] == CEILING_CAP
+
+
~~~~

## H54 — .claude/adapters/tests/test_anthropic_catalog_floor.py — head lines 167–168

Head context (head/.claude/adapters/tests/test_anthropic_catalog_floor.py, lines 155–180):

~~~~text
   155 |         monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", kill_switch)
   156 |     else:
   157 |         monkeypatch.delenv("LOA_CHEVAL_DISABLE_STREAMING", raising=False)
   158 |     for model_id in http_entries:
   159 |         threshold = _lookup_max_input_tokens("anthropic", model_id, catalog)
   160 |         assert isinstance(threshold, int) and threshold > 0, (model_id, kill_switch, threshold)
   161 | 
   162 | 
   163 | def test_legacy_wall_applies_only_to_anthropic_under_the_kill_switch(catalog, http_entries, monkeypatch):
   164 |     """SDD §3.2: 180K was probed under streaming; killing streaming re-applies the 36K KF-002 wall."""
   165 |     assert _LEGACY_TRANSPORT_INPUT_WALL == 36_000
   166 |     monkeypatch.delenv("LOA_CHEVAL_DISABLE_STREAMING", raising=False)
>  167 |     for model_id, entry in http_entries.items():
>  168 |         want = entry["effective_input_ceiling"] if _measured(entry) else CEILING_CAP
   169 |         assert _lookup_max_input_tokens("anthropic", model_id, catalog) == want, model_id
   170 |     monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
   171 |     for model_id in http_entries:
   172 |         assert _lookup_max_input_tokens("anthropic", model_id, catalog) == _LEGACY_TRANSPORT_INPUT_WALL, model_id
   173 |     # Non-Anthropic entries keep their own v2 split fields (openai legacy 24K), untouched by the constant.
   174 |     assert _lookup_max_input_tokens("openai", "gpt-5.5", catalog) == 24_000
   175 | 
   176 | 
   177 | def test_thinking_adaptive_exactly_on_the_adaptive_set(anthropic):
   178 |     flagged = {m for m, e in anthropic.items() if (e.get("params") or {}).get("thinking_adaptive") is True}
   179 |     assert flagged == ADAPTIVE
   180 |     # Any non-boolean value is a misspelling the schema cannot catch —
~~~~

The change from head to the fix:

~~~~diff
@@ -167,2 +215,4 @@
+    monkeypatch.setenv("LOA_CHEVAL_CEILING_OBSERVED_PATH", "/nonexistent/ceiling-observed.json")  # no host observations
     for model_id, entry in http_entries.items():
-        want = entry["effective_input_ceiling"] if _measured(entry) else CEILING_CAP
+        # r251-1 (finding 33): the policy decides the bound, not a test-local mirror of it
+        want = input_bound(entry, max_tokens=_default_max_tokens(entry)).value
~~~~

## H55 — .claude/adapters/tests/test_anthropic_catalog_floor.py — insertion after head line 364

Head context (head/.claude/adapters/tests/test_anthropic_catalog_floor.py, lines 353–368):

~~~~text
   353 | 
   354 | def test_opus_5_5_has_the_1m_window_at_standard_pricing(anthropic):
   355 |     """cycle-126 bd-2fti: the vendor pricing page puts 4.6-and-later on the full 1M window at
   356 |     standard pricing, so 5.5 carries no long_context tier; its ceiling is the conservative
   357 |     default until a probe measures it (cycle-127 FR-3.4: either state, each with its shape)."""
   358 |     entry = anthropic["claude-opus-5-5"]
   359 |     assert "long_context" not in entry["pricing"]
   360 |     cal = entry["ceiling_calibration"]
   361 |     if _measured(entry):
   362 |         # a probe wrote it: the measured bound is both values, with its provenance
   363 |         assert entry["probed_ceiling"] == entry["effective_input_ceiling"]
   364 |         assert isinstance(cal.get("reprobe_trigger"), str) and cal["reprobe_trigger"]
   365 |     else:
   366 |         assert cal["source"] == "conservative_default"
   367 |         assert cal["calibrated_at"] is None
   368 |     assert entry["fallback_chain"][0] == "anthropic:claude-opus-5"
~~~~

The change from head to the fix:

~~~~diff
@@ -364,0 +415,4 @@
+        # r251-1 C4: the probe's own outcome and the number of samples taken are structured, not comment-only
+        if cal.get("method") == "probed_headless":
+            assert cal.get("probe_outcome") in ("clean", "partial"), cal.get("probe_outcome")
+            assert isinstance(cal.get("sample_size"), int) and cal["sample_size"] > 0, cal.get("sample_size")
~~~~

## H56 — .claude/adapters/tests/test_ceiling_probe_cli_transport.py — head line 33

Head context (head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py, lines 21–45):

~~~~text
    21 | import subprocess
    22 | import sys
    23 | import textwrap
    24 | from pathlib import Path
    25 | 
    26 | import pytest
    27 | import yaml
    28 | 
    29 | ROOT = Path(__file__).resolve().parents[3]
    30 | TOOL = ROOT / "tools" / "ceiling-probe-live.py"
    31 | CATALOG = ROOT / ".claude" / "defaults" / "model-config.yaml"
    32 | SCHEMA_V3 = ROOT / ".claude" / "data" / "schemas" / "model-config-v3.schema.json"
>   33 | MODELINV_LOG = ROOT / ".run" / "model-invoke.jsonl"
    34 | 
    35 | # The filler is ≈10 tokens per 45 characters; the fake compares stdin characters.
    36 | CHARS_PER_TOKEN = 4.5
    37 | OVERHEAD = 3000          # the fake's "system prompt" share of the measured usage
    38 | 
    39 | FAKE = textwrap.dedent('''\
    40 |     #!{python}
    41 |     import json, os, re, sys
    42 |     if sys.argv[1:] == ["--version"]:
    43 |         print("9.9.9 (Fake Claude)")
    44 |         sys.exit(0)
    45 |     data = sys.stdin.read()
~~~~

The change from head to the fix:

~~~~diff
@@ -33 +32,0 @@
-MODELINV_LOG = ROOT / ".run" / "model-invoke.jsonl"
~~~~

## H57 — .claude/adapters/tests/test_ceiling_probe_cli_transport.py — insertion after head line 61

Head context (head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py, lines 50–73):

~~~~text
    50 |     calls = sum(1 for _ in open(log))
    51 |     m = re.search(r"code and nothing else: ([0-9a-f]{{12}})$", data)
    52 |     needle = m.group(1) if m else "NO-NEEDLE"
    53 |     mode = os.environ.get("FAKE_MODE", "limit")
    54 |     limit = int(os.environ.get("FAKE_LIMIT_TOKENS", "1000000000"))     # in MEASURED tokens
    55 |     ratio = float(os.environ.get("FAKE_RATIO", "1.0"))                 # tokenizer: measured per filler token
    56 |     measured = int(len(data) / 4.5 * ratio) + {overhead}
    57 | 
    58 |     def err(msg, status=None):
    59 |         body = {{"type": "result", "is_error": True, "result": msg}}
    60 |         if status:
    61 |             body["api_error_status"] = status
    62 |         print(json.dumps(body))
    63 |         sys.exit(1)
    64 | 
    65 |     if mode == "other":
    66 |         err("Not logged in · Please run /login")
    67 |     if mode == "garbage":
    68 |         print("not json at all")
    69 |         sys.exit(0)
    70 |     if mode == "throttle":
    71 |         err("API Error: ThrottlingException: Too many requests, please wait before trying again.")
    72 |     if mode == "5xx":
    73 |         err("API Error: 500 internal server error")
~~~~

The change from head to the fix:

~~~~diff
@@ -61,0 +61,2 @@
+        if os.environ.get("FAKE_ERR_COST"):
+            body["total_cost_usd"] = float(os.environ["FAKE_ERR_COST"])
~~~~

## H58 — .claude/adapters/tests/test_ceiling_probe_cli_transport.py — head lines 76–78

Head context (head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py, lines 64–90):

~~~~text
    64 | 
    65 |     if mode == "other":
    66 |         err("Not logged in · Please run /login")
    67 |     if mode == "garbage":
    68 |         print("not json at all")
    69 |         sys.exit(0)
    70 |     if mode == "throttle":
    71 |         err("API Error: ThrottlingException: Too many requests, please wait before trying again.")
    72 |     if mode == "5xx":
    73 |         err("API Error: 500 internal server error")
    74 |     if mode == "flaky" and calls <= 2:
    75 |         err("API Error: 529 overloaded")
>   76 |     if measured > limit:
>   77 |         if mode == "tpm":
>   78 |             err("API Error: 429 This request would exceed your organization's rate limit of 300,000 input tokens per minute")
    79 |         if os.environ.get("FAKE_ORIGIN") == "cli":
    80 |             err(f"Prompt is too long: {{measured:,}} tokens > {{limit:,}} maximum")
    81 |         if os.environ.get("FAKE_BARE"):
    82 |             err("API Error: 400 prompt is too long", status=400)
    83 |         err(f"API Error: 400 prompt is too long: {{measured}} tokens > {{limit}} maximum", status=400)
    84 |     result = "ok" if mode == "noneedle" else needle
    85 |     body = {{"type": "result", "subtype": "success", "is_error": False, "result": result, "stop_reason": "end_turn",
    86 |              "usage": {{"input_tokens": 5, "cache_creation_input_tokens": measured - 5,
    87 |                        "cache_read_input_tokens": 0, "output_tokens": 3}}}}
    88 |     if os.environ.get("FAKE_COST"):
    89 |         body["total_cost_usd"] = float(os.environ["FAKE_COST"])
    90 |     print(json.dumps(body))
~~~~

The change from head to the fix:

~~~~diff
@@ -76,3 +77,13 @@
+    BEDROCK_THROTTLE = "Too many tokens, please wait before trying again."
+    if mode == "bedrock_flaky" and calls <= 1:
+        err(BEDROCK_THROTTLE)
+    if mode == "huge":
+        sys.stdout.write("x" * (2 << 20))
+        sys.exit(0)
     if measured > limit:
+        if mode == "bedrock_tpm":
+            err(BEDROCK_THROTTLE)
         if mode == "tpm":
-            err("API Error: 429 This request would exceed your organization's rate limit of 300,000 input tokens per minute")
+            hint = os.environ.get("FAKE_RETRY_AFTER")
+            err("API Error: 429 This request would exceed your organization's rate limit of 300,000 input tokens "
+                "per minute" + (f" (retry-after: {{hint}})" if hint else ""))
~~~~

## H59 — .claude/adapters/tests/test_ceiling_probe_cli_transport.py — head lines 94–104

Head context (head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py, lines 82–116):

~~~~text
    82 |             err("API Error: 400 prompt is too long", status=400)
    83 |         err(f"API Error: 400 prompt is too long: {{measured}} tokens > {{limit}} maximum", status=400)
    84 |     result = "ok" if mode == "noneedle" else needle
    85 |     body = {{"type": "result", "subtype": "success", "is_error": False, "result": result, "stop_reason": "end_turn",
    86 |              "usage": {{"input_tokens": 5, "cache_creation_input_tokens": measured - 5,
    87 |                        "cache_read_input_tokens": 0, "output_tokens": 3}}}}
    88 |     if os.environ.get("FAKE_COST"):
    89 |         body["total_cost_usd"] = float(os.environ["FAKE_COST"])
    90 |     print(json.dumps(body))
    91 | ''')
    92 | 
    93 | 
>   94 | def _stat(p: Path):
>   95 |     return (p.stat().st_size, p.stat().st_mtime_ns) if p.exists() else None
>   96 | 
>   97 | 
>   98 | @pytest.fixture(scope="module", autouse=True)
>   99 | def _zero_live_spend():
>  100 |     """No test in this module may reach a model: the ledger cheval appends on
>  101 |     every invoke is byte-for-byte where it was."""
>  102 |     before = _stat(MODELINV_LOG)
>  103 |     yield
>  104 |     assert _stat(MODELINV_LOG) == before, ".run/model-invoke.jsonl changed — a live call escaped the fake"
   105 | 
   106 | 
   107 | @pytest.fixture(scope="module")
   108 | def tool():
   109 |     spec = importlib.util.spec_from_file_location("ceiling_probe_live_cli", TOOL)
   110 |     mod = importlib.util.module_from_spec(spec)
   111 |     sys.modules["ceiling_probe_live_cli"] = mod
   112 |     spec.loader.exec_module(mod)
   113 |     return mod
   114 | 
   115 | 
   116 | def _write_fake(path: Path) -> Path:
~~~~

The change from head to the fix:

~~~~diff
@@ -94,11 +105,21 @@
-def _stat(p: Path):
-    return (p.stat().st_size, p.stat().st_mtime_ns) if p.exists() else None
+@pytest.fixture(autouse=True)
+def _zero_live_spend(_isolate_ledgers):
+    """No test in this module may reach a model through cheval: the test's OWN MODELINV ledger (conftest
+    _isolate_ledgers points LOA_MODELINV_LOG_PATH at the test's tmp_path) stays unwritten. r251-3 R5: scoped per test —
+    the host-global .run/model-invoke.jsonl grows under any concurrent cheval run on the host."""
+    yield
+    log = Path(os.environ["LOA_MODELINV_LOG_PATH"])
+    assert not log.exists() or log.stat().st_size == 0, f"{log} written — a live call escaped the fake"
 
 
 @pytest.fixture(scope="module", autouse=True)
-def _zero_live_spend():
-    """No test in this module may reach a model: the ledger cheval appends on
-    every invoke is byte-for-byte where it was."""
-    before = _stat(MODELINV_LOG)
-    yield
-    assert _stat(MODELINV_LOG) == before, ".run/model-invoke.jsonl changed — a live call escaped the fake"
+def _no_real_cli(tmp_path_factory):
+    """r251-1 P11 — fail-closed: this transport spawns ${CLAUDE_HEADLESS_BIN:-claude}
+    directly, so a real `claude -p` would never show in cheval's MODELINV ledger
+    (the per-test guard above). Every test starts with CLAUDE_HEADLESS_BIN at a path that
+    does not exist; only the `fake` fixture points it at the recording fake."""
+    sentinel = tmp_path_factory.mktemp("loa-probe-no-real-cli") / "claude-must-not-run"
+    with pytest.MonkeyPatch.context() as mp:
+        mp.setenv("CLAUDE_HEADLESS_BIN", str(sentinel))
+        yield sentinel
+    assert not sentinel.exists()
~~~~

## H60 — .claude/adapters/tests/test_ceiling_probe_cli_transport.py — head line 129

Head context (head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py, lines 117–141):

~~~~text
   117 |     path.write_text(FAKE.format(python=sys.executable, overhead=OVERHEAD))
   118 |     path.chmod(path.stat().st_mode | stat.S_IXUSR)
   119 |     return path
   120 | 
   121 | 
   122 | @pytest.fixture
   123 | def fake(tmp_path, monkeypatch, tool):
   124 |     bin_path = _write_fake(tmp_path / "fake-claude")
   125 |     log = tmp_path / "calls.jsonl"
   126 |     monkeypatch.setenv("CLAUDE_HEADLESS_BIN", str(bin_path))
   127 |     monkeypatch.setenv("FAKE_LOG", str(log))
   128 |     for var in ("ANTHROPIC_API_KEY", "ANTHROPIC_DEFAULT_OPUS_MODEL", "FAKE_MODE", "FAKE_LIMIT_TOKENS",
>  129 |                 "FAKE_RATIO", "FAKE_BARE", "FAKE_ORIGIN", "FAKE_COST", "AWS_REGION", "ANTHROPIC_BEDROCK_REGION_PREFIX",
   130 |                 "CLAUDE_CODE_USE_BEDROCK"):
   131 |         monkeypatch.delenv(var, raising=False)
   132 |     sleeps: list = []
   133 |     monkeypatch.setattr(tool, "_SLEEP", sleeps.append)
   134 | 
   135 |     def calls():
   136 |         if not log.exists():
   137 |             return []
   138 |         return [json.loads(l) for l in log.read_text().splitlines() if l.strip()]
   139 | 
   140 |     return {"bin": str(bin_path), "calls": calls, "dir": tmp_path, "sleeps": sleeps}
   141 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -129 +150 @@
-                "FAKE_RATIO", "FAKE_BARE", "FAKE_ORIGIN", "FAKE_COST", "AWS_REGION", "ANTHROPIC_BEDROCK_REGION_PREFIX",
+                "FAKE_RATIO", "FAKE_BARE", "FAKE_ORIGIN", "FAKE_COST", "FAKE_ERR_COST", "FAKE_RETRY_AFTER", "AWS_REGION", "ANTHROPIC_BEDROCK_REGION_PREFIX",
~~~~

## H61 — .claude/adapters/tests/test_ceiling_probe_cli_transport.py — head line 148

Head context (head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py, lines 136–160):

~~~~text
   136 |         if not log.exists():
   137 |             return []
   138 |         return [json.loads(l) for l in log.read_text().splitlines() if l.strip()]
   139 | 
   140 |     return {"bin": str(bin_path), "calls": calls, "dir": tmp_path, "sleeps": sleeps}
   141 | 
   142 | 
   143 | def _limit(monkeypatch, tokens: int):
   144 |     """The fake's provider limit, in MEASURED tokens (what the CLI's usage reports)."""
   145 |     monkeypatch.setenv("FAKE_LIMIT_TOKENS", str(tokens))
   146 | 
   147 | 
>  148 | def _run(tool, monkeypatch, tmp_path, *extra):
   149 |     out = tmp_path / "record.json"
   150 |     argv = ["ceiling-probe-live.py", "--model", "claude-opus-5-5", "--transport", "claude-headless",
   151 |             "--min-tokens-probe", "100000", "--max-tokens-probe", "400000", "--budget-usd", "20",
   152 |             "--output", str(out), *extra]
   153 |     monkeypatch.setattr(sys, "argv", argv)
   154 |     code = tool.main()
   155 |     record = json.loads(out.read_text()) if out.exists() else None
   156 |     return code, record
   157 | 
   158 | 
   159 | # A two-entry catalog shaped like the pre-probe claude-opus-5-5 block: the writer
   160 | # tests must hold in a tree whose live catalog is already calibrated.
~~~~

The change from head to the fix:

~~~~diff
@@ -148 +169,4 @@
-def _run(tool, monkeypatch, tmp_path, *extra):
+def _run(tool, monkeypatch, tmp_path, *extra, expect_calls: bool = True):
+    """Run the probe in-process. r251-1 P11: a probe-running test proves the
+    recording fake was called (at least once) — or, with expect_calls=False,
+    that no CLI ran at all."""
~~~~

## H62 — .claude/adapters/tests/test_ceiling_probe_cli_transport.py — insertion after head line 155

Head context (head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py, lines 144–167):

~~~~text
   144 |     """The fake's provider limit, in MEASURED tokens (what the CLI's usage reports)."""
   145 |     monkeypatch.setenv("FAKE_LIMIT_TOKENS", str(tokens))
   146 | 
   147 | 
   148 | def _run(tool, monkeypatch, tmp_path, *extra):
   149 |     out = tmp_path / "record.json"
   150 |     argv = ["ceiling-probe-live.py", "--model", "claude-opus-5-5", "--transport", "claude-headless",
   151 |             "--min-tokens-probe", "100000", "--max-tokens-probe", "400000", "--budget-usd", "20",
   152 |             "--output", str(out), *extra]
   153 |     monkeypatch.setattr(sys, "argv", argv)
   154 |     code = tool.main()
   155 |     record = json.loads(out.read_text()) if out.exists() else None
   156 |     return code, record
   157 | 
   158 | 
   159 | # A two-entry catalog shaped like the pre-probe claude-opus-5-5 block: the writer
   160 | # tests must hold in a tree whose live catalog is already calibrated.
   161 | SYNTH = textwrap.dedent("""\
   162 |     providers:
   163 |       anthropic:
   164 |         models:
   165 |           claude-opus-5-5:
   166 |             context_window: 1000000
   167 |             max_output_tokens: 128000
~~~~

The change from head to the fix:

~~~~diff
@@ -155,0 +180,4 @@
+    log = Path(os.environ.get("FAKE_LOG", "/nonexistent"))
+    ran = log.exists() and log.read_text().strip() != ""
+    assert ran is expect_calls, f"fake called: {ran}, expected {expect_calls} (CLAUDE_HEADLESS_BIN=" \
+                                f"{os.environ.get('CLAUDE_HEADLESS_BIN')})"
~~~~

## H63 — .claude/adapters/tests/test_ceiling_probe_cli_transport.py — head lines 219–224

Head context (head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py, lines 207–236):

~~~~text
   207 |     sys.path.insert(0, str(ROOT / ".claude" / "adapters"))
   208 |     from loa_cheval.providers.claude_headless_adapter import ClaudeHeadlessAdapter, build_headless_argv
   209 |     from loa_cheval.types import CompletionRequest, ModelConfig, ProviderConfig
   210 |     adapter = ClaudeHeadlessAdapter(ProviderConfig(name="claude-headless", type="claude-headless", endpoint="",
   211 |                                                    auth="", connect_timeout=1.0, read_timeout=600.0,
   212 |                                                    models={"m": ModelConfig(context_window=1)}))
   213 |     req = CompletionRequest(messages=[{"role": "user", "content": "x"}], model="opus", max_tokens=16, effort="low")
   214 |     adapter_argv = adapter._build_command(req, ModelConfig(context_window=1), None)
   215 |     assert adapter_argv == build_headless_argv(adapter_argv[0], "opus", effort="low")
   216 |     assert tool._cli_command(adapter_argv[0], "opus") == adapter_argv + ["--max-turns", "1"]
   217 | 
   218 | 
>  219 | def test_runs_from_another_cwd_under_python_isolated_mode(tmp_path, monkeypatch):
>  220 |     bin_path = _write_fake(tmp_path / "fake-claude")
>  221 |     out = tmp_path / "r.json"
>  222 |     env = {k: v for k, v in os.environ.items() if k not in ("ANTHROPIC_API_KEY", "PYTHONPATH")}
>  223 |     env.update(CLAUDE_HEADLESS_BIN=str(bin_path), FAKE_LOG=str(tmp_path / "c.jsonl"),
>  224 |                FAKE_LIMIT_TOKENS="250000")
   225 |     proc = subprocess.run([sys.executable, "-I", str(TOOL), "--model", "claude-opus-5-5", "--transport",
   226 |                            "claude-headless", "--min-tokens-probe", "100000", "--max-tokens-probe", "400000",
   227 |                            "--budget-usd", "20", "--output", str(out)],
   228 |                           cwd=str(tmp_path), env=env, capture_output=True, text=True, timeout=300)
   229 |     assert proc.returncode == 0, proc.stderr
   230 |     assert json.loads(out.read_text())["outcome"] == "clean"
   231 | 
   232 | 
   233 | def test_default_binary_is_claude_on_path(tool, fake, monkeypatch, tmp_path):
   234 |     bindir = tmp_path / "bin"
   235 |     bindir.mkdir()
   236 |     _write_fake(bindir / "claude")
~~~~

The change from head to the fix:

~~~~diff
@@ -219,6 +247,9 @@
-def test_runs_from_another_cwd_under_python_isolated_mode(tmp_path, monkeypatch):
-    bin_path = _write_fake(tmp_path / "fake-claude")
+def test_runs_from_another_cwd_under_python_isolated_mode(fake, tmp_path, monkeypatch):
+    # r251-1 P11: the same recording fake as every other test (CLAUDE_HEADLESS_BIN and
+    # FAKE_LOG come from the `fake` fixture), and a PATH with no `claude` on it
     out = tmp_path / "r.json"
+    empty = tmp_path / "empty-path"
+    empty.mkdir()
     env = {k: v for k, v in os.environ.items() if k not in ("ANTHROPIC_API_KEY", "PYTHONPATH")}
-    env.update(CLAUDE_HEADLESS_BIN=str(bin_path), FAKE_LOG=str(tmp_path / "c.jsonl"),
-               FAKE_LIMIT_TOKENS="250000")
+    env.update(FAKE_LIMIT_TOKENS="250000", PATH=str(empty))
+    assert env["CLAUDE_HEADLESS_BIN"] == fake["bin"]
~~~~

## H64 — .claude/adapters/tests/test_ceiling_probe_cli_transport.py — insertion after head line 230

Head context (head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py, lines 219–242):

~~~~text
   219 | def test_runs_from_another_cwd_under_python_isolated_mode(tmp_path, monkeypatch):
   220 |     bin_path = _write_fake(tmp_path / "fake-claude")
   221 |     out = tmp_path / "r.json"
   222 |     env = {k: v for k, v in os.environ.items() if k not in ("ANTHROPIC_API_KEY", "PYTHONPATH")}
   223 |     env.update(CLAUDE_HEADLESS_BIN=str(bin_path), FAKE_LOG=str(tmp_path / "c.jsonl"),
   224 |                FAKE_LIMIT_TOKENS="250000")
   225 |     proc = subprocess.run([sys.executable, "-I", str(TOOL), "--model", "claude-opus-5-5", "--transport",
   226 |                            "claude-headless", "--min-tokens-probe", "100000", "--max-tokens-probe", "400000",
   227 |                            "--budget-usd", "20", "--output", str(out)],
   228 |                           cwd=str(tmp_path), env=env, capture_output=True, text=True, timeout=300)
   229 |     assert proc.returncode == 0, proc.stderr
   230 |     assert json.loads(out.read_text())["outcome"] == "clean"
   231 | 
   232 | 
   233 | def test_default_binary_is_claude_on_path(tool, fake, monkeypatch, tmp_path):
   234 |     bindir = tmp_path / "bin"
   235 |     bindir.mkdir()
   236 |     _write_fake(bindir / "claude")
   237 |     monkeypatch.delenv("CLAUDE_HEADLESS_BIN", raising=False)
   238 |     monkeypatch.setenv("PATH", f"{bindir}{os.pathsep}{os.environ['PATH']}")
   239 |     _limit(monkeypatch, 250_000)
   240 |     code, record = _run(tool, monkeypatch, tmp_path)
   241 |     assert code == 0 and record["cli_bin"] == "claude"
   242 |     assert fake["calls"]() and record["cli_version"] == "9.9.9 (Fake Claude)"
~~~~

The change from head to the fix:

~~~~diff
@@ -230,0 +262 @@
+    assert fake["calls"](), "the isolated-mode run did not go through the recording fake"
~~~~

## H65 — .claude/adapters/tests/test_ceiling_probe_cli_transport.py — head lines 238–241

Head context (head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py, lines 226–253):

~~~~text
   226 |                            "claude-headless", "--min-tokens-probe", "100000", "--max-tokens-probe", "400000",
   227 |                            "--budget-usd", "20", "--output", str(out)],
   228 |                           cwd=str(tmp_path), env=env, capture_output=True, text=True, timeout=300)
   229 |     assert proc.returncode == 0, proc.stderr
   230 |     assert json.loads(out.read_text())["outcome"] == "clean"
   231 | 
   232 | 
   233 | def test_default_binary_is_claude_on_path(tool, fake, monkeypatch, tmp_path):
   234 |     bindir = tmp_path / "bin"
   235 |     bindir.mkdir()
   236 |     _write_fake(bindir / "claude")
   237 |     monkeypatch.delenv("CLAUDE_HEADLESS_BIN", raising=False)
>  238 |     monkeypatch.setenv("PATH", f"{bindir}{os.pathsep}{os.environ['PATH']}")
>  239 |     _limit(monkeypatch, 250_000)
>  240 |     code, record = _run(tool, monkeypatch, tmp_path)
>  241 |     assert code == 0 and record["cli_bin"] == "claude"
   242 |     assert fake["calls"]() and record["cli_version"] == "9.9.9 (Fake Claude)"
   243 | 
   244 | 
   245 | # --- classification, measurement, outcome -----------------------------------
   246 | 
   247 | def test_clean_bisection_measures_and_brackets_the_bound(tool, fake, monkeypatch, tmp_path, capsys):
   248 |     _limit(monkeypatch, 250_000)
   249 |     code, record = _run(tool, monkeypatch, tmp_path)
   250 |     assert code == 0
   251 |     assert record["outcome"] == "clean" and record["reasons"] == [] and record["partial"] is False
   252 |     ok, fail = record["largest_ok_input_tokens"], record["smallest_failed_input_tokens"]
   253 |     assert ok < 250_000 <= fail and fail - ok <= 16_000
~~~~

The change from head to the fix:

~~~~diff
@@ -238,4 +270,5 @@
-    monkeypatch.setenv("PATH", f"{bindir}{os.pathsep}{os.environ['PATH']}")
+    monkeypatch.setenv("PATH", str(bindir))     # r251-1 P11: no real `claude` is reachable
     _limit(monkeypatch, 250_000)
     code, record = _run(tool, monkeypatch, tmp_path)
-    assert code == 0 and record["cli_bin"] == "claude"
+    # r251-4 T4 (n43): the record names the binary that ran, resolved on PATH
+    assert code == 0 and record["cli_bin"] == str(bindir / "claude")
~~~~

## H66 — .claude/adapters/tests/test_ceiling_probe_cli_transport.py — head line 274

Head context (head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py, lines 262–286):

~~~~text
   262 |     assert all(s["verified"] for s in record["samples"] if s["kind"] == "ok")
   263 |     # record provenance
   264 |     assert record["transport"] == "claude-headless" and record["method"] == "probed_headless"
   265 |     assert record["source"] == "operator_set" and record["pricing_basis"] == "catalog_estimate"
   266 |     assert record["bounds_tested"] == {"min": 100_000, "max": 400_000} and record["budget_usd"] == 20
   267 |     assert record["tolerance_tokens"] == 16_000 and record["started_at"] and record["calibrated_at"]
   268 |     assert record["cli_version"] == "9.9.9 (Fake Claude)" and record["cli_model"] == "claude-opus-5-5"
   269 |     assert record["route_env"] == {"AWS_REGION": None, "ANTHROPIC_BEDROCK_REGION_PREFIX": None,
   270 |                                    "CLAUDE_CODE_USE_BEDROCK": False}
   271 |     assert len(fake["calls"]()) == record["sample_size"]
   272 |     # worst-case step cost and how many fit, printed before the first live call
   273 |     err = capsys.readouterr().err
>  274 |     assert "worst-case step ≈ $1.60" in err and "12 such steps fit in $20" in err
   275 |     assert err.index("worst-case step") < err.index("tokens (attempt 1)")
   276 | 
   277 | 
   278 | def test_cli_local_preflight_rejection_counts_as_size(tool, fake, monkeypatch, tmp_path):
   279 |     _limit(monkeypatch, 250_000)
   280 |     monkeypatch.setenv("FAKE_ORIGIN", "cli")
   281 |     code, record = _run(tool, monkeypatch, tmp_path)
   282 |     assert code == 0 and record["outcome"] == "clean"
   283 |     assert {s["size_origin"] for s in record["samples"] if s["kind"] == "size"} == {"cli_local"}
   284 | 
   285 | 
   286 | def test_tolerance_tokens_sets_the_stop(tool, fake, monkeypatch, tmp_path):
~~~~

The change from head to the fix:

~~~~diff
@@ -274 +307,10 @@
-    assert "worst-case step ≈ $1.60" in err and "12 such steps fit in $20" in err
+    # r251-4 T3 (n58): until a step measures, the estimate assumes the 1.8 tokenizer ratio
+    # (400K filler tokens ≈ 720K measured × $5/MTok)
+    assert "worst-case step ≈ $3.60" in err and "5 such steps fit in $20" in err
+    assert "estimate assumes the Opus 4.7+ tokenizer ratio 1.8 until the first measured accept" in err
+    assert "$4.00/MTok input × 1.25 cache-write rate = $5.00/MTok" in err and "Bedrock bills separately" in err
+    assert record["estimate_rate"] == "input × 1.25 (cache-write rate)"
+    # accepted steps without a CLI cost are charged at the measured size × the cache-write rate
+    for s in record["samples"]:
+        if s["kind"] == "ok":
+            assert s["charged_usd"] == pytest.approx(s["measured_input_tokens"] * 5e-6, abs=1e-5)
~~~~

## H67 — .claude/adapters/tests/test_ceiling_probe_cli_transport.py — head line 298

Head context (head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py, lines 286–310):

~~~~text
   286 | def test_tolerance_tokens_sets_the_stop(tool, fake, monkeypatch, tmp_path):
   287 |     _limit(monkeypatch, 250_000)
   288 |     code, record = _run(tool, monkeypatch, tmp_path, "--tolerance-tokens", "2000")
   289 |     assert code == 0
   290 |     assert record["smallest_failed_input_tokens"] - record["largest_ok_input_tokens"] <= 2000
   291 |     code2, wide = _run(tool, monkeypatch, tmp_path, "--tolerance-tokens", "60000")
   292 |     assert wide["sample_size"] < record["sample_size"]
   293 | 
   294 | 
   295 | def test_a_completion_without_the_needle_is_unverified_and_partial(tool, fake, monkeypatch, tmp_path):
   296 |     monkeypatch.setenv("FAKE_MODE", "noneedle")
   297 |     catalog = tmp_path / "model-config.yaml"
>  298 |     catalog.write_text(CATALOG.read_text())
   299 |     code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog))
   300 |     assert code == 3
   301 |     assert record["outcome"] == "partial" and record["unverified"] is True
   302 |     assert record["largest_ok_input_tokens"] == 0, "an unverified completion is never counted as OK"
   303 |     assert any("unverified" in r for r in record["reasons"])
   304 |     assert catalog.read_text() == CATALOG.read_text()
   305 | 
   306 | 
   307 | def test_top_accepted_without_a_rejection_is_not_clean(tool, fake, monkeypatch, tmp_path):
   308 |     code, record = _run(tool, monkeypatch, tmp_path)
   309 |     assert code == 3 and record["outcome"] == "partial"
   310 |     assert any("not bracketed" in r for r in record["reasons"])
~~~~

The change from head to the fix:

~~~~diff
@@ -298 +340 @@
-    catalog.write_text(CATALOG.read_text())
+    catalog.write_text(SYNTH)
~~~~

## H68 — .claude/adapters/tests/test_ceiling_probe_cli_transport.py — head line 304

Head context (head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py, lines 292–316):

~~~~text
   292 |     assert wide["sample_size"] < record["sample_size"]
   293 | 
   294 | 
   295 | def test_a_completion_without_the_needle_is_unverified_and_partial(tool, fake, monkeypatch, tmp_path):
   296 |     monkeypatch.setenv("FAKE_MODE", "noneedle")
   297 |     catalog = tmp_path / "model-config.yaml"
   298 |     catalog.write_text(CATALOG.read_text())
   299 |     code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog))
   300 |     assert code == 3
   301 |     assert record["outcome"] == "partial" and record["unverified"] is True
   302 |     assert record["largest_ok_input_tokens"] == 0, "an unverified completion is never counted as OK"
   303 |     assert any("unverified" in r for r in record["reasons"])
>  304 |     assert catalog.read_text() == CATALOG.read_text()
   305 | 
   306 | 
   307 | def test_top_accepted_without_a_rejection_is_not_clean(tool, fake, monkeypatch, tmp_path):
   308 |     code, record = _run(tool, monkeypatch, tmp_path)
   309 |     assert code == 3 and record["outcome"] == "partial"
   310 |     assert any("not bracketed" in r for r in record["reasons"])
   311 | 
   312 | 
   313 | def test_transient_classes_retry_with_backoff_and_count_every_attempt(tool, fake, monkeypatch, tmp_path):
   314 |     _limit(monkeypatch, 250_000)
   315 |     monkeypatch.setenv("FAKE_MODE", "flaky")       # the first two calls answer 529 overloaded
   316 |     code, record = _run(tool, monkeypatch, tmp_path)
~~~~

The change from head to the fix:

~~~~diff
@@ -304 +346 @@
-    assert catalog.read_text() == CATALOG.read_text()
+    assert catalog.read_text() == SYNTH
~~~~

## H69 — .claude/adapters/tests/test_ceiling_probe_cli_transport.py — head lines 321–323

Head context (head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py, lines 309–335):

~~~~text
   309 |     assert code == 3 and record["outcome"] == "partial"
   310 |     assert any("not bracketed" in r for r in record["reasons"])
   311 | 
   312 | 
   313 | def test_transient_classes_retry_with_backoff_and_count_every_attempt(tool, fake, monkeypatch, tmp_path):
   314 |     _limit(monkeypatch, 250_000)
   315 |     monkeypatch.setenv("FAKE_MODE", "flaky")       # the first two calls answer 529 overloaded
   316 |     code, record = _run(tool, monkeypatch, tmp_path)
   317 |     assert code == 0 and record["outcome"] == "clean"
   318 |     top = record["samples"][0]
   319 |     assert top["tokens"] == 400_000 and top["attempts"] == 3
   320 |     assert fake["sleeps"] == [5, 15]
>  321 |     # three attempts at 400K are all paid for (two rejected at the requested size, one measured)
>  322 |     assert top["cost_usd"] >= 3 * 1.6 - 0.01
>  323 |     assert record["spent_usd"] == pytest.approx(sum(s["cost_usd"] for s in record["samples"]), abs=1e-3)
   324 | 
   325 | 
   326 | @pytest.mark.parametrize("mode", ["throttle", "5xx"])
   327 | def test_a_transient_class_that_persists_is_other_after_three_attempts(tool, fake, monkeypatch, tmp_path, mode):
   328 |     monkeypatch.setenv("FAKE_MODE", mode)
   329 |     catalog = tmp_path / "model-config.yaml"
   330 |     catalog.write_text(CATALOG.read_text())
   331 |     code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog))
   332 |     assert code == 1 and record["outcome"] == "partial" and record["error"]
   333 |     assert len(fake["calls"]()) == 3 and record["samples"][0]["attempts"] == 3
   334 |     assert catalog.read_text() == CATALOG.read_text()
   335 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -321,3 +363,8 @@
-    # three attempts at 400K are all paid for (two rejected at the requested size, one measured)
-    assert top["cost_usd"] >= 3 * 1.6 - 0.01
-    assert record["spent_usd"] == pytest.approx(sum(s["cost_usd"] for s in record["samples"]), abs=1e-3)
+    # r251-1 P1: the two 529s and the third attempt's size rejection (400K > the 250K limit)
+    # are provider-side rejections the CLI reported no cost for — none is billed
+    assert [a["kind"] for a in top["attempt_log"]] == ["transient", "transient", "size"]
+    assert [a["charge_basis"] for a in top["attempt_log"]] == ["provider_rejection_unbilled"] * 3
+    assert top["charged_usd"] == 0
+    ok = [s for s in record["samples"] if s["kind"] == "ok"]
+    assert ok and all(s["charge_basis"] == "completion" and s["charged_usd"] > 0 for s in ok)
+    assert record["spent_usd"] == pytest.approx(sum(s["charged_usd"] for s in record["samples"]), abs=1e-3)
~~~~

## H70 — .claude/adapters/tests/test_ceiling_probe_cli_transport.py — head lines 330–334

Head context (head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py, lines 318–346):

~~~~text
   318 |     top = record["samples"][0]
   319 |     assert top["tokens"] == 400_000 and top["attempts"] == 3
   320 |     assert fake["sleeps"] == [5, 15]
   321 |     # three attempts at 400K are all paid for (two rejected at the requested size, one measured)
   322 |     assert top["cost_usd"] >= 3 * 1.6 - 0.01
   323 |     assert record["spent_usd"] == pytest.approx(sum(s["cost_usd"] for s in record["samples"]), abs=1e-3)
   324 | 
   325 | 
   326 | @pytest.mark.parametrize("mode", ["throttle", "5xx"])
   327 | def test_a_transient_class_that_persists_is_other_after_three_attempts(tool, fake, monkeypatch, tmp_path, mode):
   328 |     monkeypatch.setenv("FAKE_MODE", mode)
   329 |     catalog = tmp_path / "model-config.yaml"
>  330 |     catalog.write_text(CATALOG.read_text())
>  331 |     code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog))
>  332 |     assert code == 1 and record["outcome"] == "partial" and record["error"]
>  333 |     assert len(fake["calls"]()) == 3 and record["samples"][0]["attempts"] == 3
>  334 |     assert catalog.read_text() == CATALOG.read_text()
   335 | 
   336 | 
   337 | def test_a_token_budget_429_that_persists_at_a_size_is_a_size_rejection(tool, fake, monkeypatch, tmp_path):
   338 |     _limit(monkeypatch, 300_000)
   339 |     monkeypatch.setenv("FAKE_MODE", "tpm")
   340 |     code, record = _run(tool, monkeypatch, tmp_path)
   341 |     assert code == 0, record["reasons"]
   342 |     failed = [s for s in record["samples"] if s["kind"] == "size"]
   343 |     assert failed and all(s["failure_class"] == "token_limit" and s["attempts"] == 3 for s in failed)
   344 |     assert record["largest_ok_input_tokens"] < 300_000 <= record["smallest_failed_input_tokens"]
   345 | 
   346 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -330,5 +377,6 @@
-    catalog.write_text(CATALOG.read_text())
+    catalog.write_text(SYNTH)
     code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog))
     assert code == 1 and record["outcome"] == "partial" and record["error"]
     assert len(fake["calls"]()) == 3 and record["samples"][0]["attempts"] == 3
-    assert catalog.read_text() == CATALOG.read_text()
+    assert fake["sleeps"] == [5, 15]          # the short schedule: not a token-budget 429
+    assert catalog.read_text() == SYNTH
~~~~

## H71 — .claude/adapters/tests/test_ceiling_probe_cli_transport.py — head lines 341–344

Head context (head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py, lines 329–356):

~~~~text
   329 |     catalog = tmp_path / "model-config.yaml"
   330 |     catalog.write_text(CATALOG.read_text())
   331 |     code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog))
   332 |     assert code == 1 and record["outcome"] == "partial" and record["error"]
   333 |     assert len(fake["calls"]()) == 3 and record["samples"][0]["attempts"] == 3
   334 |     assert catalog.read_text() == CATALOG.read_text()
   335 | 
   336 | 
   337 | def test_a_token_budget_429_that_persists_at_a_size_is_a_size_rejection(tool, fake, monkeypatch, tmp_path):
   338 |     _limit(monkeypatch, 300_000)
   339 |     monkeypatch.setenv("FAKE_MODE", "tpm")
   340 |     code, record = _run(tool, monkeypatch, tmp_path)
>  341 |     assert code == 0, record["reasons"]
>  342 |     failed = [s for s in record["samples"] if s["kind"] == "size"]
>  343 |     assert failed and all(s["failure_class"] == "token_limit" and s["attempts"] == 3 for s in failed)
>  344 |     assert record["largest_ok_input_tokens"] < 300_000 <= record["smallest_failed_input_tokens"]
   345 | 
   346 | 
   347 | @pytest.mark.parametrize("mode", ["other", "garbage"])
   348 | def test_any_other_failure_exits_1_with_the_error_recorded_and_writes_nothing(tool, fake, monkeypatch, tmp_path, mode):
   349 |     monkeypatch.setenv("FAKE_MODE", mode)
   350 |     catalog = tmp_path / "model-config.yaml"
   351 |     catalog.write_text(CATALOG.read_text())
   352 |     code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog))
   353 |     assert code == 1
   354 |     assert record["error"] and record["outcome"] == "partial"
   355 |     assert catalog.read_text() == CATALOG.read_text()
   356 |     assert len(fake["calls"]()) == 1   # not retried: neither size nor transient
~~~~

The change from head to the fix:

~~~~diff
@@ -341,4 +389,9 @@
-    assert code == 0, record["reasons"]
+    # verifier r251-1: a bound bracketed by a token-budget rejection is not a context limit — partial
+    assert code == 3 and record["outcome"] == "partial"
+    assert any("token_limit" in r and "context_limit" in r for r in record["reasons"])
     failed = [s for s in record["samples"] if s["kind"] == "size"]
-    assert failed and all(s["failure_class"] == "token_limit" and s["attempts"] == 3 for s in failed)
+    assert failed and all(s["failure_class"] == "token_limit" and s["attempts"] == 4 for s in failed)
+    assert all(s["retry_wait_s"] >= tool._TPM_WINDOW_S for s in failed)
     assert record["largest_ok_input_tokens"] < 300_000 <= record["smallest_failed_input_tokens"]
+    # r251-1 P2: each failed step waited out the tokens-per-minute window, 5 s / 15 s never could
+    assert fake["sleeps"] == [20, 45, 75] * len(failed)
~~~~

## H72 — .claude/adapters/tests/test_ceiling_probe_cli_transport.py — head lines 351–355

Head context (head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py, lines 339–367):

~~~~text
   339 |     monkeypatch.setenv("FAKE_MODE", "tpm")
   340 |     code, record = _run(tool, monkeypatch, tmp_path)
   341 |     assert code == 0, record["reasons"]
   342 |     failed = [s for s in record["samples"] if s["kind"] == "size"]
   343 |     assert failed and all(s["failure_class"] == "token_limit" and s["attempts"] == 3 for s in failed)
   344 |     assert record["largest_ok_input_tokens"] < 300_000 <= record["smallest_failed_input_tokens"]
   345 | 
   346 | 
   347 | @pytest.mark.parametrize("mode", ["other", "garbage"])
   348 | def test_any_other_failure_exits_1_with_the_error_recorded_and_writes_nothing(tool, fake, monkeypatch, tmp_path, mode):
   349 |     monkeypatch.setenv("FAKE_MODE", mode)
   350 |     catalog = tmp_path / "model-config.yaml"
>  351 |     catalog.write_text(CATALOG.read_text())
>  352 |     code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog))
>  353 |     assert code == 1
>  354 |     assert record["error"] and record["outcome"] == "partial"
>  355 |     assert catalog.read_text() == CATALOG.read_text()
   356 |     assert len(fake["calls"]()) == 1   # not retried: neither size nor transient
   357 | 
   358 | 
   359 | def test_missing_binary_is_other(tool, fake, monkeypatch, tmp_path):
   360 |     monkeypatch.setenv("CLAUDE_HEADLESS_BIN", str(tmp_path / "no-such-claude"))
   361 |     code, record = _run(tool, monkeypatch, tmp_path)
   362 |     assert code == 1 and record["error"] and record["cli_version"] is None
   363 | 
   364 | 
   365 | def test_inconsistent_classifications_are_partial(tool):
   366 |     samples = [{"tokens": 300_000, "kind": "ok"}, {"tokens": 250_000, "kind": "size"}]
   367 |     reasons = tool._outcome_reasons(samples, stop=None, largest_ok=300_000, measured=303_000,
~~~~

The change from head to the fix:

~~~~diff
@@ -351,5 +404,5 @@
-    catalog.write_text(CATALOG.read_text())
+    catalog.write_text(SYNTH)
     code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog))
     assert code == 1
     assert record["error"] and record["outcome"] == "partial"
-    assert catalog.read_text() == CATALOG.read_text()
+    assert catalog.read_text() == SYNTH
~~~~

## H73 — .claude/adapters/tests/test_ceiling_probe_cli_transport.py — head line 361

Head context (head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py, lines 349–373):

~~~~text
   349 |     monkeypatch.setenv("FAKE_MODE", mode)
   350 |     catalog = tmp_path / "model-config.yaml"
   351 |     catalog.write_text(CATALOG.read_text())
   352 |     code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog))
   353 |     assert code == 1
   354 |     assert record["error"] and record["outcome"] == "partial"
   355 |     assert catalog.read_text() == CATALOG.read_text()
   356 |     assert len(fake["calls"]()) == 1   # not retried: neither size nor transient
   357 | 
   358 | 
   359 | def test_missing_binary_is_other(tool, fake, monkeypatch, tmp_path):
   360 |     monkeypatch.setenv("CLAUDE_HEADLESS_BIN", str(tmp_path / "no-such-claude"))
>  361 |     code, record = _run(tool, monkeypatch, tmp_path)
   362 |     assert code == 1 and record["error"] and record["cli_version"] is None
   363 | 
   364 | 
   365 | def test_inconsistent_classifications_are_partial(tool):
   366 |     samples = [{"tokens": 300_000, "kind": "ok"}, {"tokens": 250_000, "kind": "size"}]
   367 |     reasons = tool._outcome_reasons(samples, stop=None, largest_ok=300_000, measured=303_000,
   368 |                                     smallest_fail=250_000, hi=400_000, tol=16_000)
   369 |     assert any("inconsistent" in r for r in reasons)
   370 |     clean = [{"tokens": 240_000, "kind": "ok"}, {"tokens": 250_000, "kind": "size"}]
   371 |     assert tool._outcome_reasons(clean, stop=None, largest_ok=240_000, measured=243_000,
   372 |                                  smallest_fail=250_000, hi=400_000, tol=16_000) == []
   373 |     assert tool._outcome_reasons(clean, stop=None, largest_ok=240_000, measured=None,
~~~~

The change from head to the fix:

~~~~diff
@@ -361 +414 @@
-    code, record = _run(tool, monkeypatch, tmp_path)
+    code, record = _run(tool, monkeypatch, tmp_path, expect_calls=False)
~~~~

## H74 — .claude/adapters/tests/test_ceiling_probe_cli_transport.py — head line 370

Head context (head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py, lines 358–382):

~~~~text
   358 | 
   359 | def test_missing_binary_is_other(tool, fake, monkeypatch, tmp_path):
   360 |     monkeypatch.setenv("CLAUDE_HEADLESS_BIN", str(tmp_path / "no-such-claude"))
   361 |     code, record = _run(tool, monkeypatch, tmp_path)
   362 |     assert code == 1 and record["error"] and record["cli_version"] is None
   363 | 
   364 | 
   365 | def test_inconsistent_classifications_are_partial(tool):
   366 |     samples = [{"tokens": 300_000, "kind": "ok"}, {"tokens": 250_000, "kind": "size"}]
   367 |     reasons = tool._outcome_reasons(samples, stop=None, largest_ok=300_000, measured=303_000,
   368 |                                     smallest_fail=250_000, hi=400_000, tol=16_000)
   369 |     assert any("inconsistent" in r for r in reasons)
>  370 |     clean = [{"tokens": 240_000, "kind": "ok"}, {"tokens": 250_000, "kind": "size"}]
   371 |     assert tool._outcome_reasons(clean, stop=None, largest_ok=240_000, measured=243_000,
   372 |                                  smallest_fail=250_000, hi=400_000, tol=16_000) == []
   373 |     assert tool._outcome_reasons(clean, stop=None, largest_ok=240_000, measured=None,
   374 |                                  smallest_fail=250_000, hi=400_000, tol=16_000)
   375 | 
   376 | 
   377 | # --- budget -----------------------------------------------------------------
   378 | 
   379 | def test_budget_cap_stops_with_partial_and_writes_nothing(tool, fake, monkeypatch, tmp_path):
   380 |     _limit(monkeypatch, 150_000)
   381 |     catalog = tmp_path / "model-config.yaml"
   382 |     catalog.write_text(CATALOG.read_text())
~~~~

The change from head to the fix:

~~~~diff
@@ -370 +423 @@
-    clean = [{"tokens": 240_000, "kind": "ok"}, {"tokens": 250_000, "kind": "size"}]
+    clean = [{"tokens": 240_000, "kind": "ok"}, {"tokens": 250_000, "kind": "size", "failure_class": "context_limit"}]
~~~~

## H75 — .claude/adapters/tests/test_ceiling_probe_cli_transport.py — head lines 379–393

Head context (head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py, lines 367–405):

~~~~text
   367 |     reasons = tool._outcome_reasons(samples, stop=None, largest_ok=300_000, measured=303_000,
   368 |                                     smallest_fail=250_000, hi=400_000, tol=16_000)
   369 |     assert any("inconsistent" in r for r in reasons)
   370 |     clean = [{"tokens": 240_000, "kind": "ok"}, {"tokens": 250_000, "kind": "size"}]
   371 |     assert tool._outcome_reasons(clean, stop=None, largest_ok=240_000, measured=243_000,
   372 |                                  smallest_fail=250_000, hi=400_000, tol=16_000) == []
   373 |     assert tool._outcome_reasons(clean, stop=None, largest_ok=240_000, measured=None,
   374 |                                  smallest_fail=250_000, hi=400_000, tol=16_000)
   375 | 
   376 | 
   377 | # --- budget -----------------------------------------------------------------
   378 | 
>  379 | def test_budget_cap_stops_with_partial_and_writes_nothing(tool, fake, monkeypatch, tmp_path):
>  380 |     _limit(monkeypatch, 150_000)
>  381 |     catalog = tmp_path / "model-config.yaml"
>  382 |     catalog.write_text(CATALOG.read_text())
>  383 |     # 400K top ($1.60) fits; the first mid (250K, $1.00) does not fit in $2
>  384 |     code, record = _run(tool, monkeypatch, tmp_path, "--budget-usd", "2", "--write-catalog", str(catalog),
>  385 |                         "--allow-partial")
>  386 |     assert code == 3
>  387 |     assert record["outcome"] == "partial" and any("budget" in r for r in record["reasons"])
>  388 |     assert record["spent_usd"] <= 2
>  389 |     assert catalog.read_text() == CATALOG.read_text(), "a partial CLI-transport record is never written"
>  390 | 
>  391 | 
>  392 | def test_budget_below_the_first_call_makes_no_call(tool, fake, monkeypatch, tmp_path):
>  393 |     code, record = _run(tool, monkeypatch, tmp_path, "--budget-usd", "0.5")
   394 |     assert code == 3 and record["partial"] is True and record["sample_size"] == 0
   395 |     assert fake["calls"]() == []
   396 | 
   397 | 
   398 | def test_spend_is_the_larger_of_the_cli_cost_and_the_catalog_estimate(tool, fake, monkeypatch, tmp_path):
   399 |     _limit(monkeypatch, 250_000)
   400 |     monkeypatch.setenv("FAKE_COST", "9.0")          # an implausibly high CLI-reported cost wins
   401 |     code, record = _run(tool, monkeypatch, tmp_path, "--budget-usd", "40")
   402 |     ok_steps = [s for s in record["samples"] if s["kind"] == "ok"]
   403 |     assert ok_steps and all(s["cost_usd"] >= 9.0 for s in ok_steps)
   404 | 
   405 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -379,15 +432,17 @@
-def test_budget_cap_stops_with_partial_and_writes_nothing(tool, fake, monkeypatch, tmp_path):
-    _limit(monkeypatch, 150_000)
+def test_budget_cap_stops_with_partial_and_writes_nothing(tool, fake, monkeypatch, tmp_path, capsys):
+    _limit(monkeypatch, 350_000)
     catalog = tmp_path / "model-config.yaml"
-    catalog.write_text(CATALOG.read_text())
-    # 400K top ($1.60) fits; the first mid (250K, $1.00) does not fit in $2
-    code, record = _run(tool, monkeypatch, tmp_path, "--budget-usd", "2", "--write-catalog", str(catalog),
-                        "--allow-partial")
+    catalog.write_text(SYNTH)
+    # the 400K top (est $3.60: the 1.8 prior × the cache-write rate, r251-4 T3) is rejected (free);
+    # ≈251K is accepted (≈$1.26), ≈327K accepted (≈$1.64); the next mid (≈365K, est ≈$1.83) no
+    # longer fits in $3.60 — the pre-check uses the estimate
+    code, record = _run(tool, monkeypatch, tmp_path, "--budget-usd", "3.6", "--write-catalog", str(catalog))
     assert code == 3
     assert record["outcome"] == "partial" and any("budget" in r for r in record["reasons"])
-    assert record["spent_usd"] <= 2
-    assert catalog.read_text() == CATALOG.read_text(), "a partial CLI-transport record is never written"
+    assert 0 < record["spent_usd"] <= 3.6
+    assert catalog.read_text() == SYNTH, "a partial CLI-transport record is never written"
+    assert (tmp_path / "record.json").exists()
 
 
 def test_budget_below_the_first_call_makes_no_call(tool, fake, monkeypatch, tmp_path):
-    code, record = _run(tool, monkeypatch, tmp_path, "--budget-usd", "0.5")
+    code, record = _run(tool, monkeypatch, tmp_path, "--budget-usd", "0.5", expect_calls=False)
~~~~

## H76 — .claude/adapters/tests/test_ceiling_probe_cli_transport.py — head line 403

Head context (head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py, lines 391–415):

~~~~text
   391 | 
   392 | def test_budget_below_the_first_call_makes_no_call(tool, fake, monkeypatch, tmp_path):
   393 |     code, record = _run(tool, monkeypatch, tmp_path, "--budget-usd", "0.5")
   394 |     assert code == 3 and record["partial"] is True and record["sample_size"] == 0
   395 |     assert fake["calls"]() == []
   396 | 
   397 | 
   398 | def test_spend_is_the_larger_of_the_cli_cost_and_the_catalog_estimate(tool, fake, monkeypatch, tmp_path):
   399 |     _limit(monkeypatch, 250_000)
   400 |     monkeypatch.setenv("FAKE_COST", "9.0")          # an implausibly high CLI-reported cost wins
   401 |     code, record = _run(tool, monkeypatch, tmp_path, "--budget-usd", "40")
   402 |     ok_steps = [s for s in record["samples"] if s["kind"] == "ok"]
>  403 |     assert ok_steps and all(s["cost_usd"] >= 9.0 for s in ok_steps)
   404 | 
   405 | 
   406 | # --- cli_model / host_route / env -------------------------------------------
   407 | 
   408 | def test_cli_model_alias_resolves_through_the_wrapper_env_when_visible(tool, fake, monkeypatch, tmp_path):
   409 |     _limit(monkeypatch, 250_000)
   410 |     monkeypatch.setenv("ANTHROPIC_DEFAULT_OPUS_MODEL", "global.anthropic.claude-opus-5-5")
   411 |     monkeypatch.setenv("AWS_REGION", "us-east-1")
   412 |     monkeypatch.setenv("ANTHROPIC_BEDROCK_REGION_PREFIX", "global")
   413 |     monkeypatch.setenv("CLAUDE_CODE_USE_BEDROCK", "1")
   414 |     code, record = _run(tool, monkeypatch, tmp_path, "--cli-model", "opus")
   415 |     assert code == 0
~~~~

The change from head to the fix:

~~~~diff
@@ -403 +458,2 @@
-    assert ok_steps and all(s["cost_usd"] >= 9.0 for s in ok_steps)
+    assert ok_steps and all(s["charged_usd"] >= 9.0 for s in ok_steps)
+    assert all(s["charge_basis"] == "completion" for s in ok_steps)
~~~~

## H77 — .claude/adapters/tests/test_ceiling_probe_cli_transport.py — head lines 440–444

Head context (head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py, lines 428–456):

~~~~text
   428 |     assert code == 0
   429 |     assert record["cli_model"] == "opus" and record["host_route"] == "bedrock us-east-1 global"
   430 | 
   431 | 
   432 | # --- helpers ----------------------------------------------------------------
   433 | 
   434 | def test_attempt_timeout_scales_with_size_and_is_capped(tool):
   435 |     assert tool._attempt_timeout(0) == 120
   436 |     assert tool._attempt_timeout(400_000) == 320
   437 |     assert tool._attempt_timeout(10_000_000) == 1800
   438 | 
   439 | 
>  440 | def test_captured_output_is_capped_at_1mb(tool):
>  441 |     rc, out, err = tool._run_capped([sys.executable, "-c",
>  442 |                                      "import sys; sys.stdout.write('x' * 3000000); sys.stderr.write('y' * 2000000)"],
>  443 |                                     "", 60)
>  444 |     assert rc == 0 and len(out) == 1 << 20 and len(err) == 1 << 20
   445 | 
   446 | 
   447 | # --- the operator_set write -------------------------------------------------
   448 | 
   449 | def _w(tool, text, ceiling, **kw):
   450 |     args = dict(calibrated_at="2026-10-07T12:00:00Z", cli_model="global.anthropic.claude-opus-5-5",
   451 |                 host_route="bedrock (claude-bedrock)", cli_version="2.1.292 (Claude Code)")
   452 |     args.update(kw)
   453 |     return tool.write_catalog_operator_set(text, "claude-opus-5-5", ceiling=ceiling, **args)
   454 | 
   455 | 
   456 | def test_write_operator_set_changes_only_the_entry_and_replaces_the_shortcut(tool):
~~~~

The change from head to the fix:

~~~~diff
@@ -440,5 +496,16 @@
-def test_captured_output_is_capped_at_1mb(tool):
-    rc, out, err = tool._run_capped([sys.executable, "-c",
-                                     "import sys; sys.stdout.write('x' * 3000000); sys.stderr.write('y' * 2000000)"],
-                                    "", 60)
-    assert rc == 0 and len(out) == 1 << 20 and len(err) == 1 << 20
+def test_output_past_the_1mb_cap_raises_and_kills_the_group(tool):
+    # verifier r251-1 (P7): the probe runs through loa_cheval's run_subprocess_pgkill, which
+    # raises past its byte cap instead of truncating — a truncated answer never classifies
+    tool._adapters()                       # the tool's own import seam (verifier n46)
+    from loa_cheval.providers.base import SubprocessOutputCapExceeded
+    with pytest.raises(SubprocessOutputCapExceeded):
+        tool._run_capped([sys.executable, "-c", "import sys; sys.stdout.write('x' * 3000000)"], "", 60)
+    rc, out, err = tool._run_capped([sys.executable, "-c", "import sys; sys.stdout.write('x' * 1000)"], "", 60)
+    assert rc == 0 and len(out) == 1000
+
+
+def test_an_oversized_cli_answer_is_other(tool, fake, monkeypatch, tmp_path):
+    monkeypatch.setenv("FAKE_MODE", "huge")
+    code, record = _run(tool, monkeypatch, tmp_path)
+    assert code == 1 and record["samples"][0]["kind"] == "other"
+    assert "1 MB" in record["samples"][0]["detail"] and record["samples"][0]["attempts"] == 1
~~~~

## H78 — .claude/adapters/tests/test_ceiling_probe_cli_transport.py — head line 451

Head context (head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py, lines 439–463):

~~~~text
   439 | 
   440 | def test_captured_output_is_capped_at_1mb(tool):
   441 |     rc, out, err = tool._run_capped([sys.executable, "-c",
   442 |                                      "import sys; sys.stdout.write('x' * 3000000); sys.stderr.write('y' * 2000000)"],
   443 |                                     "", 60)
   444 |     assert rc == 0 and len(out) == 1 << 20 and len(err) == 1 << 20
   445 | 
   446 | 
   447 | # --- the operator_set write -------------------------------------------------
   448 | 
   449 | def _w(tool, text, ceiling, **kw):
   450 |     args = dict(calibrated_at="2026-10-07T12:00:00Z", cli_model="global.anthropic.claude-opus-5-5",
>  451 |                 host_route="bedrock (claude-bedrock)", cli_version="2.1.292 (Claude Code)")
   452 |     args.update(kw)
   453 |     return tool.write_catalog_operator_set(text, "claude-opus-5-5", ceiling=ceiling, **args)
   454 | 
   455 | 
   456 | def test_write_operator_set_changes_only_the_entry_and_replaces_the_shortcut(tool):
   457 |     before = CATALOG.read_text()
   458 |     if "# loa:shortcut: Opus 5's measured bound, not probed on 5.5" not in before:
   459 |         pytest.skip("the catalog is already calibrated (the lead's probe write landed)")
   460 |     after = _w(tool, before, 640_000)
   461 |     b, a = yaml.safe_load(before), yaml.safe_load(after)
   462 |     entry = a["providers"]["anthropic"]["models"]["claude-opus-5-5"]
   463 |     assert entry["probed_ceiling"] == 640_000
~~~~

The change from head to the fix:

~~~~diff
@@ -451 +518,2 @@
-                host_route="bedrock (claude-bedrock)", cli_version="2.1.292 (Claude Code)")
+                host_route="bedrock (claude-bedrock)", cli_version="2.1.292 (Claude Code)",
+                probe_outcome="clean", sample_size=5)
~~~~

## H79 — .claude/adapters/tests/test_ceiling_probe_cli_transport.py — head lines 457–459

Head context (head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py, lines 445–471):

~~~~text
   445 | 
   446 | 
   447 | # --- the operator_set write -------------------------------------------------
   448 | 
   449 | def _w(tool, text, ceiling, **kw):
   450 |     args = dict(calibrated_at="2026-10-07T12:00:00Z", cli_model="global.anthropic.claude-opus-5-5",
   451 |                 host_route="bedrock (claude-bedrock)", cli_version="2.1.292 (Claude Code)")
   452 |     args.update(kw)
   453 |     return tool.write_catalog_operator_set(text, "claude-opus-5-5", ceiling=ceiling, **args)
   454 | 
   455 | 
   456 | def test_write_operator_set_changes_only_the_entry_and_replaces_the_shortcut(tool):
>  457 |     before = CATALOG.read_text()
>  458 |     if "# loa:shortcut: Opus 5's measured bound, not probed on 5.5" not in before:
>  459 |         pytest.skip("the catalog is already calibrated (the lead's probe write landed)")
   460 |     after = _w(tool, before, 640_000)
   461 |     b, a = yaml.safe_load(before), yaml.safe_load(after)
   462 |     entry = a["providers"]["anthropic"]["models"]["claude-opus-5-5"]
   463 |     assert entry["probed_ceiling"] == 640_000
   464 |     # a calibrated entry is bounded by effective_input_ceiling (routing/ceiling.input_bound),
   465 |     # so the measured value lands there too — otherwise the write would be inert
   466 |     assert entry["effective_input_ceiling"] == 640_000
   467 |     cal = entry["ceiling_calibration"]
   468 |     assert cal["source"] == "operator_set" and cal["method"] == "probed_headless"
   469 |     assert cal["transport"] == "claude-headless" and cal["cli_version"] == "2.1.292 (Claude Code)"
   470 |     assert cal["cli_model"] == "global.anthropic.claude-opus-5-5" and cal["measured_input_tokens"] == 640_000
   471 |     assert cal["calibrated_at"] == "2026-10-07T12:00:00Z"
~~~~

The change from head to the fix:

~~~~diff
@@ -457,3 +525,4 @@
-    before = CATALOG.read_text()
-    if "# loa:shortcut: Opus 5's measured bound, not probed on 5.5" not in before:
-        pytest.skip("the catalog is already calibrated (the lead's probe write landed)")
+    # r251-1 P9: on the synthetic pre-probe catalog — the live entry is calibrated, and a
+    # skip here would leave the shortcut-replacement path untested
+    before = SYNTH
+    assert "# loa:shortcut: Opus 5's measured bound, not probed on 5.5" in before
~~~~

## H80 — .claude/adapters/tests/test_ceiling_probe_cli_transport.py — head line 472

Head context (head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py, lines 460–484):

~~~~text
   460 |     after = _w(tool, before, 640_000)
   461 |     b, a = yaml.safe_load(before), yaml.safe_load(after)
   462 |     entry = a["providers"]["anthropic"]["models"]["claude-opus-5-5"]
   463 |     assert entry["probed_ceiling"] == 640_000
   464 |     # a calibrated entry is bounded by effective_input_ceiling (routing/ceiling.input_bound),
   465 |     # so the measured value lands there too — otherwise the write would be inert
   466 |     assert entry["effective_input_ceiling"] == 640_000
   467 |     cal = entry["ceiling_calibration"]
   468 |     assert cal["source"] == "operator_set" and cal["method"] == "probed_headless"
   469 |     assert cal["transport"] == "claude-headless" and cal["cli_version"] == "2.1.292 (Claude Code)"
   470 |     assert cal["cli_model"] == "global.anthropic.claude-opus-5-5" and cal["measured_input_tokens"] == 640_000
   471 |     assert cal["calibrated_at"] == "2026-10-07T12:00:00Z"
>  472 |     assert cal["sample_size"] is None and cal["stale_after_days"] == 90
   473 |     assert cal["reprobe_trigger"].startswith("API-transport probe (tools/ceiling-probe-live.py --transport api) "
   474 |                                              "from a host with ANTHROPIC_API_KEY;")
   475 |     assert "through claude-headless on Bedrock (global.anthropic.claude-opus-5-5) on 2026-10-07" in cal["reprobe_trigger"]
   476 |     for prov, pv in b["providers"].items():
   477 |         for mid, me in (pv.get("models") or {}).items():
   478 |             if (prov, mid) != ("anthropic", "claude-opus-5-5"):
   479 |                 assert a["providers"][prov]["models"][mid] == me, (prov, mid)
   480 |     be = b["providers"]["anthropic"]["models"]["claude-opus-5-5"]
   481 |     for k in set(be) | set(entry):
   482 |         if k not in ("probed_ceiling", "effective_input_ceiling", "ceiling_calibration"):
   483 |             assert entry.get(k) == be.get(k), k
   484 |     assert a["aliases"] == b["aliases"]
~~~~

The change from head to the fix:

~~~~diff
@@ -472 +541 @@
-    assert cal["sample_size"] is None and cal["stale_after_days"] == 90
+    assert cal["sample_size"] == 5 and cal["probe_outcome"] == "clean" and cal["stale_after_days"] == 90
~~~~

## H81 — .claude/adapters/tests/test_ceiling_probe_cli_transport.py — head line 484

Head context (head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py, lines 472–496):

~~~~text
   472 |     assert cal["sample_size"] is None and cal["stale_after_days"] == 90
   473 |     assert cal["reprobe_trigger"].startswith("API-transport probe (tools/ceiling-probe-live.py --transport api) "
   474 |                                              "from a host with ANTHROPIC_API_KEY;")
   475 |     assert "through claude-headless on Bedrock (global.anthropic.claude-opus-5-5) on 2026-10-07" in cal["reprobe_trigger"]
   476 |     for prov, pv in b["providers"].items():
   477 |         for mid, me in (pv.get("models") or {}).items():
   478 |             if (prov, mid) != ("anthropic", "claude-opus-5-5"):
   479 |                 assert a["providers"][prov]["models"][mid] == me, (prov, mid)
   480 |     be = b["providers"]["anthropic"]["models"]["claude-opus-5-5"]
   481 |     for k in set(be) | set(entry):
   482 |         if k not in ("probed_ceiling", "effective_input_ceiling", "ceiling_calibration"):
   483 |             assert entry.get(k) == be.get(k), k
>  484 |     assert a["aliases"] == b["aliases"]
   485 |     assert "loa:shortcut: Opus 5's measured bound" not in after
   486 |     assert sum(1 for l in after.splitlines() if l.strip().startswith("#")) == \
   487 |         sum(1 for l in before.splitlines() if l.strip().startswith("#")) - 1
   488 |     prov_lines = [l for l in after.splitlines() if "cycle-127 FR-3" in l and "claude-headless" in l]
   489 |     assert len(prov_lines) == 1 and prov_lines[0].startswith("        # ")
   490 |     bl, al = before.splitlines(), after.splitlines()
   491 |     start = bl.index("      claude-opus-5-5:")
   492 |     assert bl[:start] == al[:start]
   493 |     assert bl[bl.index("      claude-opus-5:"):] == al[al.index("      claude-opus-5:"):]
   494 |     sys.path.insert(0, str(ROOT / ".claude" / "adapters"))
   495 |     from loa_cheval.routing.ceiling import input_bound
   496 |     d = input_bound(entry, max_tokens=64_000)
~~~~

The change from head to the fix:

~~~~diff
@@ -484 +553 @@
-    assert a["aliases"] == b["aliases"]
+    assert a.get("aliases") == b.get("aliases")
~~~~

## H82 — .claude/adapters/tests/test_ceiling_probe_cli_transport.py — head line 525

Head context (head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py, lines 513–537):

~~~~text
   513 |     entry = yaml.safe_load(once)["providers"]["anthropic"]["models"]["claude-opus-5-5"]
   514 |     assert entry["ceiling_calibration"]["stale_after_days"] == 45
   515 |     assert entry["ceiling_calibration"]["cli_version"] is None
   516 |     assert "through claude-headless on claude CLI (opus) on 2026-10-07" in entry["ceiling_calibration"]["reprobe_trigger"]
   517 |     assert _w(tool, once, 500_000, cli_model="opus", host_route="claude CLI", cli_version=None) == once
   518 |     rewritten = _w(tool, once, 450_000, cli_model="opus", host_route="claude CLI", cli_version=None)
   519 |     assert sum(1 for l in rewritten.splitlines() if "cycle-127 FR-3: bound measured" in l) == 1
   520 |     for bad in (0, -1, True, "500000"):
   521 |         with pytest.raises(ValueError):
   522 |             _w(tool, text, bad)
   523 |     with pytest.raises(ValueError):
   524 |         tool.write_catalog_operator_set(text, "claude-nope-9", ceiling=1, calibrated_at="2026-10-07T00:00:00Z",
>  525 |                                         cli_model="x", host_route="y")
   526 | 
   527 | 
   528 | def test_cli_write_catalog_end_to_end_on_a_temp_copy(tool, fake, monkeypatch, tmp_path):
   529 |     _limit(monkeypatch, 250_000)
   530 |     catalog = tmp_path / "model-config.yaml"
   531 |     catalog.write_text(SYNTH)
   532 |     code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog), "--host-route", "bedrock")
   533 |     assert code == 0 and record["outcome"] == "clean"
   534 |     entry = yaml.safe_load(catalog.read_text())["providers"]["anthropic"]["models"]["claude-opus-5-5"]
   535 |     assert entry["probed_ceiling"] == record["measured_input_tokens"] == entry["effective_input_ceiling"]
   536 |     cal = entry["ceiling_calibration"]
   537 |     assert cal["source"] == "operator_set" and cal["calibrated_at"] == record["calibrated_at"]
~~~~

The change from head to the fix:

~~~~diff
@@ -525 +594 @@
-                                        cli_model="x", host_route="y")
+                                        cli_model="x", host_route="y", probe_outcome="clean", sample_size=1)
~~~~

## H83 — .claude/adapters/tests/test_ceiling_probe_cli_transport.py — insertion after head line 675

Head context (head/.claude/adapters/tests/test_ceiling_probe_cli_transport.py, lines 664–675):

~~~~text
   664 | def test_unknown_transport_is_a_usage_error(tool, monkeypatch):
   665 |     monkeypatch.setattr(sys, "argv", ["ceiling-probe-live.py", "--model", "m", "--transport", "carrier-pigeon"])
   666 |     with pytest.raises(SystemExit) as e:
   667 |         tool.main()
   668 |     assert e.value.code == 2
   669 | 
   670 | 
   671 | def test_opus_5_5_has_its_catalog_input_price(tool):
   672 |     assert tool._PRICE_IN["claude-opus-5-5"] == 4_000_000
   673 |     cat = yaml.safe_load(CATALOG.read_text())
   674 |     assert cat["providers"]["anthropic"]["models"]["claude-opus-5-5"]["pricing"]["input_per_mtok"] == \
   675 |         tool._PRICE_IN["claude-opus-5-5"]
~~~~

The change from head to the fix:

~~~~diff
@@ -675,0 +745,742 @@
+
+
+# --- r251-1 (cross-model review of 8ad37c55) --------------------------------
+
+def test_p1_a_cli_local_rejection_is_never_charged(tool, fake, monkeypatch, tmp_path):
+    _limit(monkeypatch, 250_000)
+    monkeypatch.setenv("FAKE_ORIGIN", "cli")
+    code, record = _run(tool, monkeypatch, tmp_path)
+    assert code == 0
+    rejected = [s for s in record["samples"] if s["kind"] == "size"]
+    assert rejected and all(s["charged_usd"] == 0 and s["charge_basis"] == "cli_local_rejection" for s in rejected)
+    ok = [s for s in record["samples"] if s["kind"] == "ok"]
+    assert record["spent_usd"] == pytest.approx(sum(s["charged_usd"] for s in ok), abs=1e-4)
+
+
+def test_p1_a_cli_local_rejection_alone_spends_nothing(tool, fake, monkeypatch, tmp_path):
+    _limit(monkeypatch, 1)                       # every size rejected, by the CLI's own pre-flight
+    monkeypatch.setenv("FAKE_ORIGIN", "cli")
+    code, record = _run(tool, monkeypatch, tmp_path)
+    assert record["samples"] and record["spent_usd"] == 0
+
+
+def test_p1_a_provider_rejection_is_free_unless_the_cli_reports_a_cost(tool, fake, monkeypatch, tmp_path):
+    _limit(monkeypatch, 250_000)
+    code, record = _run(tool, monkeypatch, tmp_path)
+    rejected = [s for s in record["samples"] if s["kind"] == "size"]
+    assert rejected and all(s["size_origin"] == "provider" for s in rejected)
+    assert all(s["charged_usd"] == 0 and s["charge_basis"] == "provider_rejection_unbilled" for s in rejected)
+    monkeypatch.setenv("FAKE_ERR_COST", "0.25")
+    code, record = _run(tool, monkeypatch, tmp_path)
+    rejected = [s for s in record["samples"] if s["kind"] == "size"]
+    assert all(s["charged_usd"] == 0.25 and s["charge_basis"] == "cli_reported" for s in rejected)
+    assert record["spent_usd"] == pytest.approx(sum(s["charged_usd"] for s in record["samples"]), abs=1e-4)
+
+
+def test_p1_the_budget_precheck_still_uses_the_estimate(tool, fake, monkeypatch, tmp_path):
+    """A free rejection does not make the next attempt free in advance: the cap
+    is checked against the estimate before any attempt."""
+    _limit(monkeypatch, 1)
+    monkeypatch.setenv("FAKE_ORIGIN", "cli")
+    code, record = _run(tool, monkeypatch, tmp_path, "--budget-usd", "1.0", expect_calls=False)
+    # 400K filler ≈ 720K measured (the 1.8 prior, r251-4 T3) ≈ $3.60 estimated > $1.00: never
+    # attempted although it would have cost nothing
+    assert code == 3 and record["sample_size"] == 0 and fake["calls"]() == []
+    # the estimate is the cache-write rate: $3.00 would have fit at the plain input price ($2.88)
+    code, record = _run(tool, monkeypatch, tmp_path, "--budget-usd", "3.0", expect_calls=False)
+    assert code == 3 and record["sample_size"] == 0
+    # and the 1.8 prior: $2.50 would have fit at the filler count ($2.00)
+    code, record = _run(tool, monkeypatch, tmp_path, "--budget-usd", "2.5", expect_calls=False)
+    assert code == 3 and record["sample_size"] == 0
+
+
+def test_p2_a_retry_after_hint_is_honoured_and_the_total_wait_capped(tool, fake, monkeypatch, tmp_path):
+    _limit(monkeypatch, 300_000)
+    monkeypatch.setenv("FAKE_MODE", "tpm")
+    monkeypatch.setenv("FAKE_RETRY_AFTER", "100")
+    code, record = _run(tool, monkeypatch, tmp_path)
+    failed = [s for s in record["samples"] if s["kind"] == "size"]
+    assert failed
+    for s in failed:
+        assert s["retry_wait_s"] <= tool._RETRY_WAIT_CAP_S
+    # the hint (100 s) beats the 20 s schedule; the cap (180 s) truncates the second wait
+    assert fake["sleeps"][:2] == [100, 80]
+
+
+def test_p2_the_short_backoff_is_kept_for_5xx(tool, fake, monkeypatch, tmp_path):
+    _limit(monkeypatch, 250_000)
+    monkeypatch.setenv("FAKE_MODE", "flaky")
+    _run(tool, monkeypatch, tmp_path)
+    assert fake["sleeps"] == [5, 15]
+
+
+def test_p3_a_token_limit_that_persists_without_the_window_cleared_is_other(tool, fake, monkeypatch, tmp_path):
+    _limit(monkeypatch, 300_000)
+    monkeypatch.setenv("FAKE_MODE", "tpm")
+    monkeypatch.setattr(tool, "_RETRY_WAIT_CAP_S", 30)       # the window (60 s) can never be waited out
+    code, record = _run(tool, monkeypatch, tmp_path)
+    assert code == 1 and record["samples"][0]["kind"] == "other"
+    assert "window" in record["samples"][0]["detail"]
+
+
+def test_p3_classification_unit(tool):
+    s = tool._persisted_transient({"kind": "transient", "token_limit": True, "detail": "429 tpm"},
+                                  attempt_kinds=["token_limit"] * 4, waited=140.0)
+    assert s["kind"] == "size" and s["failure_class"] == "token_limit" and s["size_origin"] == "provider"
+    s = tool._persisted_transient({"kind": "transient", "token_limit": True, "detail": "429 tpm"},
+                                  attempt_kinds=["transient", "token_limit", "token_limit"], waited=140.0)
+    assert s["kind"] == "other"                                # not every attempt was the token-limit class
+    s = tool._persisted_transient({"kind": "transient", "detail": "503"}, attempt_kinds=["transient"] * 3, waited=20)
+    assert s["kind"] == "other" and "persisted" in s["detail"]
+
+
+def test_p4_classification_reads_the_full_diagnostic(tool):
+    stderr = "x" * 400 + " Prompt is too long: 500,000 tokens > 400,000 maximum"
+    res = tool._classify(1, "", stderr, "abcdefabcdef")
+    assert res["kind"] == "size" and res["rejected_input_tokens"] == 500_000
+    assert len(res["detail"]) <= 300                       # truncated for the record only
+    tpm = "y" * 400 + " API Error: 429 rate limit of 300,000 input tokens per minute"
+    res = tool._classify(1, json.dumps({"type": "result", "is_error": True, "result": tpm}), "", "abcdefabcdef")
+    assert res["kind"] == "transient" and res["token_limit"] is True
+
+
+def test_p4_the_full_text_is_capped_at_the_capture_size(tool):
+    huge = "z" * (3 << 20) + " Prompt is too long"
+    # beyond the 1 MB capture the marker is never seen — the classifier never reads more than was captured
+    res = tool._classify(1, "", huge, "abcdefabcdef")
+    assert res["kind"] != "size"
+
+
+def test_p5_a_classifier_exception_is_other_and_the_record_survives(tool, fake, monkeypatch, tmp_path):
+    _limit(monkeypatch, 250_000)
+    _, ceiling, _ = tool._adapters()
+
+    def boom(_msg):
+        raise RuntimeError("parse exploded")
+    monkeypatch.setattr(ceiling, "parse_context_limit", boom)
+    code, record = _run(tool, monkeypatch, tmp_path)
+    assert code == 1 and record is not None and record["outcome"] == "partial"
+    bad = [s for s in record["samples"] if s["kind"] == "other"]
+    assert bad and "parse exploded" in bad[0]["detail"] and "RuntimeError" in bad[0]["detail"]
+    assert "parse exploded" in record["error"]
+
+
+@pytest.mark.parametrize("mutate,why", [
+    (lambda t: t.replace("      claude-opus-5-5:\n", "      claude-opus-5-4:\n", 1), "no `      claude-opus-5-5:` block"),
+    (lambda t: t.replace("        context_window: 1000000\n", "", 1), "context_window"),
+    (lambda t: t.replace("        context_window: 1000000\n", "        context_window: 0\n", 1), "context_window"),
+    (lambda t: t.replace("        probed_ceiling: 180000\n", "", 1), "probed_ceiling"),
+])
+def test_p6_write_prerequisites_fail_fast_with_no_spend(tool, fake, monkeypatch, tmp_path, capsys, mutate, why):
+    _limit(monkeypatch, 250_000)
+    catalog = tmp_path / "model-config.yaml"
+    bad = mutate(SYNTH)
+    catalog.write_text(bad)
+    code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog), expect_calls=False)
+    assert code == 2 and record is None
+    # no model call; `--version` (no spend) now runs first so the dry run sees the real
+    # cli_version (r251-4 T1) — the fake does not log it
+    assert fake["calls"]() == []
+    assert why in capsys.readouterr().err
+    assert catalog.read_text() == bad
+
+
+def test_p6_a_missing_catalog_file_fails_fast(tool, fake, monkeypatch, tmp_path):
+    code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(tmp_path / "nope.yaml"), expect_calls=False)
+    assert code == 2 and fake["calls"]() == []
+
+
+GRANDCHILD = textwrap.dedent("""\
+    import os, subprocess, sys, time
+    child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(300)"])
+    open(sys.argv[1], "w").write(f"{os.getpid()} {child.pid}")
+    time.sleep(300)
+    """)
+
+
+def _alive(pid: int) -> bool:
+    try:
+        with open(f"/proc/{pid}/stat") as fh:
+            return fh.read().split(")")[-1].split()[0] != "Z"
+    except FileNotFoundError:
+        return False
+
+
+def _cmdline_has(pid: int, marker: str) -> bool:
+    try:
+        with open(f"/proc/{pid}/cmdline", "rb") as fh:
+            return marker in fh.read().replace(b"\0", b" ").decode(errors="replace")
+    except OSError:
+        return False
+
+
+@pytest.mark.skipif(not os.path.isdir("/proc"), reason="needs /proc to observe the grandchild")
+def test_p7_a_timeout_kills_the_whole_process_group(tool, tmp_path):
+    import time
+    script = tmp_path / "wrapper.py"
+    script.write_text(GRANDCHILD)
+    pidfile = tmp_path / "gc.pid"
+    # verifier n49: a 5 s cap leaves the wrapper ample time to write the pidfile, and a
+    # missing pidfile fails with a message rather than a FileNotFoundError
+    with pytest.raises(subprocess.TimeoutExpired):
+        tool._run_capped([sys.executable, str(script), str(pidfile)], "prompt on stdin", 5)
+    deadline = time.time() + 10
+    while not pidfile.exists() and time.time() < deadline:
+        time.sleep(0.05)
+    assert pidfile.exists(), "the wrapper never wrote its pidfile within the 5 s cap — the test proved nothing"
+    wrapper, gc = (int(x) for x in pidfile.read_text().split())
+    while (_alive(gc) or _alive(wrapper)) and time.time() < deadline:
+        time.sleep(0.1)
+    survivors = [p for p in (wrapper, gc) if _alive(p)]
+    # r251-4 T7 (n46): kill only a PID whose cmdline is still ours (a reused PID is left alone)
+    for p, marker in ((wrapper, str(script)), (gc, "time.sleep(300)")):
+        if p in survivors and _cmdline_has(p, marker):
+            os.kill(p, 9)
+    assert not survivors, f"the timeout left {survivors} alive (wrapper {wrapper}, grandchild {gc})"
+
+
+def test_p7_stdin_is_delivered_and_the_child_leads_its_own_group(tool):
+    rc, out, err = tool._run_capped([sys.executable, "-c",
+                                     "import os, sys; d = sys.stdin.read(); "
+                                     "print(len(d), os.getpgid(0) == os.getpid())"], "x" * 3_000_000, 60)
+    assert rc == 0 and out.split() == ["3000000", "True"]
+
+
+@pytest.mark.parametrize("text,transient", [
+    ("Request took 503 ms and then failed: something odd", False),
+    ("retrying 3 of 500 items", False),
+    ("API Error: 503", True),
+    ("HTTP 502 from upstream", True),
+    ("status 504", True),
+])
+def test_p8_the_5xx_heuristic_needs_a_status_context(tool, text, transient):
+    res = tool._classify(1, json.dumps({"type": "result", "is_error": True, "result": text}), "", "abcdefabcdef")
+    assert (res["kind"] == "transient") is transient, res
+
+
+def test_p8_api_status_field_counts(tool):
+    body = {"type": "result", "is_error": True, "result": "upstream trouble", "api_error_status": 503}
+    assert tool._classify(1, json.dumps(body), "", "abcdefabcdef")["kind"] == "transient"
+
+
+@pytest.mark.parametrize("flags", [["--allow-partial"], ["--tier", "3"], ["--itpm", "100000"]])
+def test_p9_api_only_flags_are_a_usage_error_on_the_headless_transport(tool, fake, monkeypatch, tmp_path, capsys, flags):
+    catalog = tmp_path / "model-config.yaml"
+    catalog.write_text(SYNTH)
+    code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog), *flags, expect_calls=False)
+    assert code == 2 and record is None and catalog.read_text() == SYNTH
+    assert f"{flags[0]} is an api-transport flag" in capsys.readouterr().err
+
+
+def test_p9_the_headless_only_flag_is_a_usage_error_on_the_api_transport(tool, fake, monkeypatch, capsys):
+    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-never-used")
+    monkeypatch.setattr(sys, "argv", ["ceiling-probe-live.py", "--model", "claude-opus-5-5", "--write-catalog",
+                                      "/nonexistent", "--write-partial-as-operator-set"])
+    assert tool.main() == 2
+    assert "--write-partial-as-operator-set applies to --transport claude-headless only" in capsys.readouterr().err
+
+
+def test_p10_the_docstring_describes_the_i2_clamp(tool):
+    doc = tool.__doc__
+    assert "raw — the api transport applies no safety margin either" not in doc
+    assert "min(measured, context_window − default_max_tokens)" in doc
+    assert "size_unit" in doc and "written_ceiling" in doc
+
+
+# --- r251-1 P11: the zero-spend guard is fail-closed for this transport -----
+
+def test_p11_the_module_default_binary_is_a_sentinel_that_does_not_exist():
+    """Without the `fake` fixture, CLAUDE_HEADLESS_BIN points at a path under a
+    tmp dir that does not exist: a probe test that forgets the fake fails on
+    spawn instead of reaching a real `claude -p`."""
+    sentinel = os.environ.get("CLAUDE_HEADLESS_BIN", "")
+    assert sentinel and "loa-probe-no-real-cli" in sentinel and not os.path.exists(sentinel)
+
+
+def test_p11_a_probe_without_the_fake_fails_on_spawn(tool, monkeypatch, tmp_path):
+    out = tmp_path / "r.json"
+    monkeypatch.setattr(sys, "argv", ["ceiling-probe-live.py", "--model", "claude-opus-5-5", "--transport",
+                                      "claude-headless", "--min-tokens-probe", "100000", "--max-tokens-probe",
+                                      "400000", "--budget-usd", "20", "--output", str(out)])
+    assert tool.main() == 1
+    record = json.loads(out.read_text())
+    assert "loa-probe-no-real-cli" in record["error"] and record["samples"][0]["charge_basis"] == "not_sent"
+
+
+# --- r251-1 P12: probe_outcome / sample_size provenance --------------------
+
+def _validate_cal(cal):
+    import jsonschema
+    schema = json.loads(SCHEMA_V3.read_text())
+    jsonschema.validate(cal, {**schema["$defs"]["ceilingCalibration"], "$defs": schema["$defs"]})
+
+
+def test_p12_a_clean_write_carries_probe_outcome_and_the_sample_count(tool):
+    after = _w(tool, SYNTH, 640_000, sample_size=7)
+    cal = yaml.safe_load(after)["providers"]["anthropic"]["models"]["claude-opus-5-5"]["ceiling_calibration"]
+    assert cal["probe_outcome"] == "clean" and cal["sample_size"] == 7
+    _validate_cal(cal)
+
+
+def test_p12_a_partial_record_is_refused_without_force(tool):
+    with pytest.raises(ValueError, match="partial"):
+        _w(tool, SYNTH, 640_000, probe_outcome="partial")
+    for bad in ("maybe", None, ""):
+        with pytest.raises(ValueError):
+            _w(tool, SYNTH, 640_000, probe_outcome=bad)
+    for bad in (-1, True, "5", None):
+        with pytest.raises(ValueError):
+            _w(tool, SYNTH, 640_000, sample_size=bad)
+
+
+def test_p12_a_forced_partial_write_says_partial(tool):
+    after = _w(tool, SYNTH, 972_887, probe_outcome="partial", sample_size=5, force_partial=True)
+    entry = yaml.safe_load(after)["providers"]["anthropic"]["models"]["claude-opus-5-5"]
+    cal = entry["ceiling_calibration"]
+    assert cal["probe_outcome"] == "partial" and cal["sample_size"] == 5
+    assert cal["measured_input_tokens"] == 972_887 and entry["effective_input_ceiling"] == 936_000
+    assert "partial" in next(l for l in after.splitlines() if "cycle-127 FR-3: bound measured" in l)
+    _validate_cal(cal)
+    # forcing a clean record is a no-op flag
+    assert _w(tool, SYNTH, 640_000, force_partial=True) == _w(tool, SYNTH, 640_000)
+
+
+def test_p12_the_schema_probe_outcome_is_optional_and_closed(tool):
+    import jsonschema
+    base = {"source": "operator_set", "calibrated_at": "2026-10-07T00:00:00Z", "sample_size": 5,
+            "stale_after_days": 90}
+    _validate_cal(base)                                          # optional: absent is valid
+    _validate_cal({**base, "probe_outcome": "partial"})
+    with pytest.raises(jsonschema.ValidationError):
+        _validate_cal({**base, "probe_outcome": "maybe"})
+    schema = json.loads(SCHEMA_V3.read_text())
+    cc = schema["$defs"]["ceilingCalibration"]
+    assert "probe_outcome" not in cc.get("required", [])     # required only under probed_headless (r251-4 T5)
+    assert "number of probe samples taken (accepted + rejected)" in cc["properties"]["sample_size"]["description"]
+
+
+def test_p12_the_clean_cli_path_writes_probe_outcome_clean(tool, fake, monkeypatch, tmp_path):
+    _limit(monkeypatch, 250_000)
+    catalog = tmp_path / "model-config.yaml"
+    catalog.write_text(SYNTH)
+    code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog))
+    assert code == 0 and record["outcome"] == "clean"
+    cal = yaml.safe_load(catalog.read_text())["providers"]["anthropic"]["models"]["claude-opus-5-5"]["ceiling_calibration"]
+    assert cal["probe_outcome"] == "clean" and cal["sample_size"] == record["sample_size"] == len(record["samples"])
+    _validate_cal(cal)
+
+
+def test_p12_write_partial_as_operator_set_writes_a_budget_capped_record(tool, fake, monkeypatch, tmp_path, capsys):
+    _limit(monkeypatch, 350_000)
+    catalog = tmp_path / "model-config.yaml"
+    catalog.write_text(SYNTH)
+    # $3.60 fits the first step's 1.8-prior estimate and two accepts, then caps (r251-4 T3)
+    code, record = _run(tool, monkeypatch, tmp_path, "--budget-usd", "3.6", "--write-catalog", str(catalog),
+                        "--write-partial-as-operator-set")
+    assert code == 3 and record["outcome"] == "partial"     # the exit code still reports the partial probe
+    entry = yaml.safe_load(catalog.read_text())["providers"]["anthropic"]["models"]["claude-opus-5-5"]
+    cal = entry["ceiling_calibration"]
+    assert cal["probe_outcome"] == "partial" and cal["sample_size"] == record["sample_size"]
+    assert cal["measured_input_tokens"] == record["measured_input_tokens"] == entry["effective_input_ceiling"]
+    assert record["written_ceiling"] == entry["effective_input_ceiling"]
+    _validate_cal(cal)
+    assert "operator vouches" in capsys.readouterr().err
+
+
+def test_p12_write_partial_needs_a_verified_accept(tool, fake, monkeypatch, tmp_path):
+    monkeypatch.setenv("FAKE_MODE", "noneedle")
+    catalog = tmp_path / "model-config.yaml"
+    catalog.write_text(SYNTH)
+    code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog), "--write-partial-as-operator-set")
+    assert code == 3 and catalog.read_text() == SYNTH and "no verified accept" in record["error"]
+
+
+def test_p12_write_partial_without_write_catalog_is_a_usage_error(tool, fake, monkeypatch, tmp_path):
+    code, record = _run(tool, monkeypatch, tmp_path, "--write-partial-as-operator-set", expect_calls=False)
+    assert code == 2 and record is None
+
+
+# --- verifier additions (r251-1) -------------------------------------------
+
+BEDROCK_THROTTLE = "Too many tokens, please wait before trying again."
+
+
+@pytest.mark.parametrize("text", [
+    BEDROCK_THROTTLE,
+    "ThrottlingException: Too many tokens, please wait before trying again.",
+    "API Error: 429 prompt is too long for your rate limit",
+    "too many tokens per minute",
+])
+def test_a_throttle_marker_beats_a_context_marker(tool, text):
+    res = tool._classify(1, json.dumps({"type": "result", "is_error": True, "result": text}), "", "abcdefabcdef")
+    assert res["kind"] == "transient" and res.get("token_limit") is True, res
+
+
+def test_a_token_count_of_429_thousand_is_not_a_429(tool):
+    msg = "Prompt is too long: 429,000 tokens > 400,000 maximum"
+    res = tool._classify(1, json.dumps({"type": "result", "is_error": True, "result": msg}), "", "abcdefabcdef")
+    assert res["kind"] == "size" and res["rejected_input_tokens"] == 429_000
+
+
+def test_bedrock_throttle_is_retried_on_the_tpm_schedule(tool, fake, monkeypatch, tmp_path):
+    _limit(monkeypatch, 250_000)
+    monkeypatch.setenv("FAKE_MODE", "bedrock_flaky")      # the first call answers Bedrock's throttle
+    code, record = _run(tool, monkeypatch, tmp_path)
+    assert code == 0 and record["outcome"] == "clean", record["reasons"]
+    top = record["samples"][0]
+    assert top["attempts"] == 2 and top["attempt_log"][0]["kind"] == "token_limit"
+    assert top["failure_class"] == "context_limit"          # the real bracket, after the retry
+    assert fake["sleeps"] == [20]
+
+
+def test_a_persisting_bedrock_throttle_never_writes_a_clean_bound(tool, fake, monkeypatch, tmp_path):
+    _limit(monkeypatch, 250_000)
+    monkeypatch.setenv("FAKE_MODE", "bedrock_tpm")
+    catalog = tmp_path / "model-config.yaml"
+    catalog.write_text(SYNTH)
+    code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog))
+    assert code == 3 and record["outcome"] == "partial"
+    assert any("token_limit" in r for r in record["reasons"])
+    assert all(s["failure_class"] == "token_limit" and s["attempts"] == 4
+               for s in record["samples"] if s["kind"] == "size")
+    assert catalog.read_text() == SYNTH
+
+
+def test_outcome_reasons_flag_a_non_context_bracket(tool):
+    samples = [{"tokens": 240_000, "kind": "ok"}, {"tokens": 250_000, "kind": "size", "failure_class": "token_limit"}]
+    reasons = tool._outcome_reasons(samples, stop=None, largest_ok=240_000, measured=243_000,
+                                    smallest_fail=250_000, hi=400_000, tol=16_000)
+    assert any("token_limit" in r for r in reasons)
+
+
+@pytest.mark.parametrize("exc,code", [(KeyboardInterrupt, 130), (RuntimeError, 1)])
+def test_an_interrupt_after_paid_steps_still_writes_the_record(tool, fake, monkeypatch, tmp_path, capsys, exc, code):
+    _limit(monkeypatch, 250_000)
+    real = tool._run_capped
+    n = {"calls": 0}
+
+    def flaky(*a, **kw):
+        n["calls"] += 1
+        if n["calls"] == 2:
+            raise exc("operator pressed ^C" if exc is KeyboardInterrupt else "unexpected boom")
+        return real(*a, **kw)
+    monkeypatch.setattr(tool, "_run_capped", flaky)
+    got, record = _run(tool, monkeypatch, tmp_path)
+    assert got == code and record is not None
+    assert record["outcome"] == "partial" and record["stop"] == "interrupted"
+    assert exc.__name__ in record["interrupted"] and exc.__name__ in " ".join(record["reasons"])
+    first, second = record["samples"][:2]
+    assert first["kind"] in ("ok", "size") and second["kind"] == "interrupted"
+    assert second["charge_basis"] == "interrupted_estimate" and second["charged_usd"] > 0
+    assert record["spent_usd"] == pytest.approx(sum(s["charged_usd"] for s in record["samples"]), abs=1e-4)
+    # r251-2 Q5 (verifier n62): a defect keeps its traceback on stderr; ^C stays quiet
+    err = capsys.readouterr().err
+    if exc is KeyboardInterrupt:
+        assert "Traceback" not in err
+    else:
+        assert "Traceback" in err and "unexpected boom" in err and "flaky" in err
+
+
+# --- review dissent run 2 (r251-2) -----------------------------------------
+
+def _cls(tool, result, stderr=""):
+    return tool._classify(1, json.dumps({"type": "result", "is_error": True, "result": result}), stderr,
+                          "abcdefabcdef")
+
+
+@pytest.mark.parametrize("text", ["API Error: 429. Too many tokens", "API Error: 429, too many tokens",
+                                  "API Error: 429 Too many tokens"])
+def test_q1_a_429_followed_by_punctuation_is_a_throttle(tool, text):
+    res = _cls(tool, text)
+    assert res["kind"] == "transient" and res.get("token_limit") is True, res
+
+
+@pytest.mark.parametrize("text", ["Prompt is too long: 429,000 tokens > 400,000 maximum",
+                                  "Prompt is too long: 1,429.5k tokens > 1,000,000 maximum"])
+def test_q1_a_429_inside_a_number_is_still_not_a_status(tool, text):
+    assert _cls(tool, text)["kind"] == "size"
+
+
+def test_q1_a_stale_stderr_throttle_does_not_turn_a_context_result_transient(tool):
+    res = _cls(tool, "Prompt is too long: 1,065,182 tokens > 1,000,000 maximum",
+               stderr="warning: earlier rate limit hit, please wait before retrying")
+    assert res["kind"] == "size" and res["failure_class"] == "context_limit", res
+    assert res["rejected_input_tokens"] == 1_065_182
+
+
+def test_q1_stderr_decides_the_throttle_when_the_result_is_empty(tool):
+    res = tool._classify(1, "", "Too many tokens, please wait before trying again.", "abcdefabcdef")
+    assert res["kind"] == "transient" and res.get("token_limit") is True, res
+
+
+@pytest.mark.skipif(hasattr(os, "geteuid") and os.geteuid() == 0, reason="root ignores the permission bits")
+@pytest.mark.parametrize("lock", ["dir", "file"])
+def test_q2_an_unwritable_catalog_fails_before_any_spend(tool, fake, monkeypatch, tmp_path, capsys, lock):
+    _limit(monkeypatch, 250_000)
+    d = tmp_path / "cat"
+    d.mkdir()
+    catalog = d / "model-config.yaml"
+    catalog.write_text(SYNTH)
+    target = d if lock == "dir" else catalog
+    mode = target.stat().st_mode
+    target.chmod(0o555 if lock == "dir" else 0o444)
+    try:
+        code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog), expect_calls=False)
+    finally:
+        target.chmod(mode)
+    assert code == 2 and record is None and fake["calls"]() == []
+    err = capsys.readouterr().err
+    assert "not writable" in err and "nothing spent" in err
+    assert catalog.read_text() == SYNTH
+
+
+@pytest.mark.parametrize("partial", [False, True])
+def test_q3_a_failed_catalog_write_leaves_no_written_claim(tool, fake, monkeypatch, tmp_path, capsys, partial):
+    _limit(monkeypatch, 350_000 if partial else 250_000)
+    catalog = tmp_path / "model-config.yaml"
+    catalog.write_text(SYNTH)
+
+    def boom(path, new):
+        raise OSError(28, "No space left on device")
+    monkeypatch.setattr(tool, "_write_text_atomic", boom)
+    extra = ("--budget-usd", "3.6", "--write-partial-as-operator-set") if partial else ()
+    code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog), *extra)
+    assert code == 1
+    assert record["outcome"] == ("partial" if partial else "clean")
+    assert "written_ceiling" not in record and "written_probe_outcome" not in record, record
+    assert "catalog not written" in record["error"] and "No space left" in record["error"]
+    assert catalog.read_text() == SYNTH
+    assert "No space left" in capsys.readouterr().err
+
+
+def test_q3_a_landed_write_is_claimed_in_the_record(tool, fake, monkeypatch, tmp_path):
+    _limit(monkeypatch, 250_000)
+    catalog = tmp_path / "model-config.yaml"
+    catalog.write_text(SYNTH)
+    code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog))
+    entry = yaml.safe_load(catalog.read_text())["providers"]["anthropic"]["models"]["claude-opus-5-5"]
+    assert code == 0 and record["written_ceiling"] == entry["effective_input_ceiling"]
+    assert record["written_probe_outcome"] == "clean" and "error" not in record
+
+
+def test_q4_a_skipped_forced_write_keeps_the_first_probe_error(tool, fake, monkeypatch, tmp_path, capsys):
+    monkeypatch.setenv("FAKE_MODE", "other")
+    catalog = tmp_path / "model-config.yaml"
+    catalog.write_text(SYNTH)
+    code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog), "--write-partial-as-operator-set")
+    assert code == 1 and catalog.read_text() == SYNTH
+    assert "Not logged in" in record["error"]                    # errors[0], not overwritten
+    assert "no verified accept" in record["write_skipped"]
+    assert "no verified accept" in capsys.readouterr().err
+
+
+def test_q7_the_tpm_schedule_clears_the_window_by_construction(tool):
+    assert sum(tool._TPM_BACKOFF_S) >= tool._TPM_WINDOW_S
+    src = TOOL.read_text()
+    assert "sum(_TPM_BACKOFF_S) < _TPM_WINDOW_S" in src            # the import-time guard exists
+
+
+# --- r251-4 (audit dissent run 1, verifier F) -----------------------------------
+
+_INJECT = "x\n        effective_input_ceiling: 1"
+
+
+@pytest.mark.parametrize("route", [_INJECT, "a\rb", "a\x00b", "a\x1bb", "a\x7fb", "a\x85b", "a
+                                   "x" * 201])
+@pytest.mark.parametrize("write", [True, False])
+def test_t1_an_unsafe_host_route_is_a_usage_error_before_any_spend(tool, fake, monkeypatch, tmp_path, capsys,
+                                                                   route, write):
+    """n52: --host-route reaches the catalog's provenance comment; a line break there
+    overrides `effective_input_ceiling` in the loaded YAML. Refused (exit 2) before
+    the dry run and before any model call, with or without --write-catalog."""
+    _limit(monkeypatch, 250_000)
+    catalog = tmp_path / "model-config.yaml"
+    catalog.write_text(SYNTH)
+    extra = ("--write-catalog", str(catalog)) if write else ()
+    code, record = _run(tool, monkeypatch, tmp_path, "--host-route", route, *extra, expect_calls=False)
+    assert code == 2 and record is None and fake["calls"]() == []
+    assert "--host-route" in capsys.readouterr().err
+    assert catalog.read_text() == SYNTH
+
+
+def test_t1_an_unsafe_resolved_cli_model_from_the_env_is_refused(tool, fake, monkeypatch, tmp_path, capsys):
+    """n52/n57: the RESOLVED cli_model (ANTHROPIC_DEFAULT_OPUS_MODEL feeds `opus`) is validated."""
+    catalog = tmp_path / "model-config.yaml"
+    catalog.write_text(SYNTH)
+    monkeypatch.setenv("ANTHROPIC_DEFAULT_OPUS_MODEL", "opus\n        effective_input_ceiling: 1")
+    code, record = _run(tool, monkeypatch, tmp_path, "--cli-model", "opus", "--write-catalog", str(catalog),
+                        expect_calls=False)
+    assert code == 2 and record is None and fake["calls"]() == []
+    err = capsys.readouterr().err
+    assert "cli_model" in err and "ANTHROPIC_DEFAULT_OPUS_MODEL" in err
+    assert catalog.read_text() == SYNTH
+
+
+def test_t1_an_unsafe_cli_version_is_refused(tool, fake, monkeypatch, tmp_path, capsys):
+    monkeypatch.setattr(tool, "_cli_version", lambda _bin: "2.1\x1b[31m (Claude Code)")
+    code, record = _run(tool, monkeypatch, tmp_path, expect_calls=False)
+    assert code == 2 and record is None and "cli_version" in capsys.readouterr().err
+
+
+def test_t1_the_dry_run_uses_the_real_writes_resolved_kwargs(tool, fake, monkeypatch, tmp_path):
+    """n57: the pre-spend dry run passes the resolved cli_model, the host route and the
+    cli_version the real write will pass."""
+    _limit(monkeypatch, 250_000)
+    monkeypatch.setenv("ANTHROPIC_DEFAULT_OPUS_MODEL", "global.anthropic.claude-opus-5-5")
+    catalog = tmp_path / "model-config.yaml"
+    catalog.write_text(SYNTH)
+    seen: list = []
+    real = tool.write_catalog_operator_set
+
+    def spy(text, model, **kw):
+        seen.append(kw)
+        return real(text, model, **kw)
+
+    monkeypatch.setattr(tool, "write_catalog_operator_set", spy)
+    code, record = _run(tool, monkeypatch, tmp_path, "--cli-model", "opus", "--host-route", "bedrock",
+                        "--write-catalog", str(catalog))
+    assert code == 0 and len(seen) == 2
+    dry, real_kw = seen
+    for k in ("cli_model", "host_route", "cli_version"):
+        assert dry[k] == real_kw[k], k
+    assert dry["cli_model"] == "global.anthropic.claude-opus-5-5" and dry["cli_version"] == "9.9.9 (Fake Claude)"
+
+
+@pytest.mark.parametrize("field", ["host_route", "cli_model", "cli_version"])
+def test_t1_the_writer_refuses_control_characters_itself(tool, field):
+    with pytest.raises(ValueError, match=field):
+        _w(tool, SYNTH, 640_000, **{field: _INJECT})
+
+
+def test_t1_the_writer_reparses_its_output_before_returning(tool, monkeypatch):
+    """n52 (c): a template defect that would corrupt the entry raises instead of writing."""
+    monkeypatch.setattr(tool, "_PROVENANCE", tool._PROVENANCE + "\n        effective_input_ceiling: 1")
+    with pytest.raises(ValueError, match="re-parse"):
+        _w(tool, SYNTH, 640_000)
+
+
+def test_t1_the_reparse_catches_a_change_outside_the_entry(tool, monkeypatch):
+    monkeypatch.setattr(tool, "_PROVENANCE", tool._PROVENANCE + "\n        context_window: 5")
+    with pytest.raises(ValueError, match="re-parse"):
+        _w(tool, SYNTH, 640_000)
+
+
+def test_t1_a_reparse_failure_on_the_real_write_leaves_the_catalog(tool, fake, monkeypatch, tmp_path):
+    """The dry run passes (ceiling 1) but the real write's text is corrupt: nothing lands."""
+    _limit(monkeypatch, 250_000)
+    catalog = tmp_path / "model-config.yaml"
+    catalog.write_text(SYNTH)
+    real = tool.write_catalog_operator_set
+    calls = {"n": 0}
+
+    def corrupt_second(text, model, **kw):
+        calls["n"] += 1
+        if calls["n"] == 2:
+            monkeypatch.setattr(tool, "_PROVENANCE", tool._PROVENANCE + "\n        effective_input_ceiling: 1")
+        return real(text, model, **kw)
+
+    monkeypatch.setattr(tool, "write_catalog_operator_set", corrupt_second)
+    code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog))
+    assert code == 1 and record["write_failed"] is True and "re-parse" in record["error"]
+    assert "written_ceiling" not in record
+    assert catalog.read_text() == SYNTH
+
+
+@pytest.mark.parametrize("value", ["Infinity", "NaN", "-Infinity", "1e9"])
+def test_t2_a_non_finite_or_absurd_cli_cost_is_dropped(tool, fake, monkeypatch, tmp_path, value):
+    """n56: json.loads accepts Infinity / NaN; int(inf * 1e6) raised OverflowError outside
+    the attempt's try, losing the charge and the run. The value is dropped and noted."""
+    _limit(monkeypatch, 250_000)
+    monkeypatch.setenv("FAKE_COST", value)
+    code, record = _run(tool, monkeypatch, tmp_path)
+    assert code == 0 and record["outcome"] == "clean"
+    for s in record["samples"]:
+        if s["kind"] == "ok":
+            assert s["cli_reported_cost_usd"] is None
+            assert any("cli_reported_cost_usd" in n for n in s["dropped_values"])
+            assert s["charged_usd"] == pytest.approx(s["measured_input_tokens"] * 5e-6, abs=1e-5)
+    assert json.loads(json.dumps(record["spent_usd"])) == record["spent_usd"]
+
+
+def test_t2_absurd_token_counts_and_retry_hints_are_dropped(tool):
+    out = json.dumps({"type": "result", "is_error": False, "result": "abcdef012345", "total_cost_usd": 0.5,
+                      "usage": {"input_tokens": 10 ** 12}})
+    res = tool._classify(0, out, "", "abcdef012345")
+    assert res["kind"] == "ok" and res["measured_input_tokens"] is None and res["cli_reported_cost_usd"] == 0.5
+    assert any("measured_input_tokens" in n for n in res["dropped_values"])
+    err = json.dumps({"type": "result", "is_error": True, "result": "API Error: 429 rate limit, retry-after: 99999"})
+    res = tool._classify(1, err, "", "abcdef012345")
+    assert res["kind"] == "transient" and "retry_after_s" not in res
+    assert any("retry_after_s" in n for n in res["dropped_values"])
+    ok = tool._classify(1, json.dumps({"type": "result", "is_error": True,
+                                       "result": "API Error: 429 rate limit, retry-after: 30"}), "", "x")
+    assert ok["retry_after_s"] == 30.0 and "dropped_values" not in ok
+
+
+def test_t2_charge_never_overflows(tool):
+    for bad in (float("inf"), float("nan"), 10 ** 400):
+        assert tool._charge({"kind": "ok", "measured_input_tokens": 1000, "cli_reported_cost_usd": bad},
+                            est_micro=7, price_in=5_000_000)[0] == 5_000     # 1000 tokens × $5/MTok, in micro-USD
+
+
+def test_t4_the_record_names_paths_under_home_tilde_relative(tool, fake, monkeypatch, tmp_path):
+    """n40/n43: the committed record must not carry the operator's home directory."""
+    _limit(monkeypatch, 250_000)
+    monkeypatch.setenv("HOME", str(fake["dir"]))
+    code, record = _run(tool, monkeypatch, tmp_path)
+    assert code == 0
+    assert record["cli_bin"] == "~/fake-claude" and record["argv"][0] == "~/fake-claude"
+    assert record["argv"][1:] == PINNED
+    assert str(fake["dir"]) not in json.dumps(record["cli_bin"]) + json.dumps(record["argv"])
+
+
+def test_t4_home_rendering_is_prefix_exact(tool, monkeypatch):
+    monkeypatch.setenv("HOME", "/home/op")
+    assert tool._home_rel("/home/op/.local/bin/claude-bedrock") == "~/.local/bin/claude-bedrock"
+    assert tool._home_rel("/home/operator/bin/claude") == "/home/operator/bin/claude"
+    assert tool._home_rel("claude") == "claude"
+    monkeypatch.setenv("HOME", "/")
+    assert tool._home_rel("/usr/bin/claude") == "/usr/bin/claude"
+
+
+def test_t4_the_committed_probe_record_carries_no_home_path():
+    rec = ROOT / "grimoires" / "loa" / "reports" / "2026-10-07-opus-5-5-ceiling-probe-cli.json"
+    data = json.loads(rec.read_text())
+    assert data["cli_bin"] == "~/.local/bin/claude-bedrock" and data["argv"][0] == "~/.local/bin/claude-bedrock"
+    assert "/home/" not in rec.read_text()
+
+
+_HEADLESS_CAL = {"source": "operator_set", "calibrated_at": "2026-10-07T00:00:00Z", "sample_size": 5,
+                 "stale_after_days": 90, "method": "probed_headless", "transport": "claude-headless",
+                 "probe_outcome": "partial", "cli_model": "global.anthropic.claude-opus-5-5",
+                 "cli_version": "2.1.292 (Claude Code)", "measured_input_tokens": 972_887}
+
+
+@pytest.mark.parametrize("mutate", [
+    lambda c: {k: v for k, v in c.items() if k != "probe_outcome"},
+    lambda c: {k: v for k, v in c.items() if k != "transport"},
+    lambda c: {**c, "transport": "api"},
+    lambda c: {**c, "cli_model": "m" * 201},
+    lambda c: {**c, "cli_version": "v" * 201},
+])
+def test_t5_the_schema_ties_probed_headless_to_its_transport_and_outcome(tool, mutate):
+    import jsonschema
+    _validate_cal(_HEADLESS_CAL)
+    with pytest.raises(jsonschema.ValidationError):
+        _validate_cal(mutate(_HEADLESS_CAL))
+
+
+def test_t5_the_schema_still_accepts_an_api_probe_without_probe_outcome(tool):
+    _validate_cal({"source": "empirical_probe", "calibrated_at": "2026-10-07T00:00:00Z", "sample_size": 5,
+                   "stale_after_days": 90, "method": "probed_api", "transport": "api"})
+
+
+def test_t5_the_live_catalog_entries_satisfy_the_hardened_calibration_schema():
+    cat = yaml.safe_load(CATALOG.read_text())
+    seen = 0
+    for prov in cat["providers"].values():
+        for mid, entry in (prov.get("models") or {}).items():
+            if isinstance(entry, dict) and isinstance(entry.get("ceiling_calibration"), dict):
+                _validate_cal(entry["ceiling_calibration"])
+                seen += entry["ceiling_calibration"].get("method") == "probed_headless"
+    assert seen >= 1
~~~~

## H84 — .claude/adapters/tests/test_effort_catalog_default.py — head lines 176–178

Head context (head/.claude/adapters/tests/test_effort_catalog_default.py, lines 164–190):

~~~~text
   164 | 
   165 | def test_effort_on_wire_follows_the_adapter_mapping(catalog):
   166 |     assert cheval._effort_on_wire("anthropic", "claude-opus-4-6", "xhigh", catalog) == "high"
   167 |     assert cheval._effort_on_wire("anthropic", "claude-opus-5-5", "high", catalog) == "high"
   168 |     assert cheval._effort_on_wire("anthropic", "claude-haiku-4-5-20251001", "high", catalog) is None
   169 |     assert cheval._effort_on_wire("anthropic", "claude-headless", "xhigh", catalog) == "xhigh"
   170 |     assert cheval._effort_on_wire("openai", "gpt-5.5", "high", catalog) is None
   171 |     assert cheval._effort_on_wire("anthropic", "claude-opus-5-5", None, catalog) is None
   172 | 
   173 | 
   174 | # --- dry-run over the LIVE catalog (alias resolution included) ---------------
   175 | 
>  176 | def _dry(*argv: str) -> subprocess.CompletedProcess:
>  177 |     env = {k: v for k, v in os.environ.items()
>  178 |            if k not in ("ANTHROPIC_API_KEY", "AWS_BEARER_TOKEN_BEDROCK", "CLAUDE_HEADLESS_BIN")}
   179 |     return subprocess.run(
   180 |         [sys.executable, str(CHEVAL), "--agent", "reviewing-code", "--prompt", "c127-effort",
   181 |          "--dry-run", "--json-errors", *argv],
   182 |         capture_output=True, text=True, env=env, cwd=str(REPO_ROOT), timeout=120,
   183 |     )
   184 | 
   185 | 
   186 | def test_dry_run_opus_without_effort_reports_the_catalog_high():
   187 |     proc = _dry("--model", "opus")
   188 |     assert proc.returncode == 0, proc.stderr
   189 |     out = json.loads(proc.stdout)
   190 |     # the alias resolves first; only then is the entry's default read
~~~~

The change from head to the fix:

~~~~diff
@@ -176,3 +176,15 @@
+def _no_claude_path() -> str:
+    """The host PATH minus every directory that holds a `claude` / `claude-bedrock`."""
+    keep = [d for d in os.environ.get("PATH", "").split(os.pathsep)
+            if d and not any(os.path.exists(os.path.join(d, n)) for n in ("claude", "claude-bedrock"))]
+    return os.pathsep.join(keep) or os.defpath
+
+
 def _dry(*argv: str) -> subprocess.CompletedProcess:
-    env = {k: v for k, v in os.environ.items()
-           if k not in ("ANTHROPIC_API_KEY", "AWS_BEARER_TOKEN_BEDROCK", "CLAUDE_HEADLESS_BIN")}
+    # r251-4 T6 (n31): a regressed --dry-run that walks to the headless hop must never
+    # reach the real CLI — CLAUDE_HEADLESS_BIN points at a path that does not exist and
+    # no PATH directory holds a `claude`
+    env = {k: v for k, v in os.environ.items() if k not in ("ANTHROPIC_API_KEY", "AWS_BEARER_TOKEN_BEDROCK")}
+    env["CLAUDE_HEADLESS_BIN"] = str(REPO_ROOT / ".run" / "loa-test-claude-must-not-run")
+    env["PATH"] = _no_claude_path()
+    assert not os.path.exists(env["CLAUDE_HEADLESS_BIN"])
~~~~

## H85 — .claude/adapters/tests/test_effort_catalog_default.py — insertion after head line 185

Head context (head/.claude/adapters/tests/test_effort_catalog_default.py, lines 174–197):

~~~~text
   174 | # --- dry-run over the LIVE catalog (alias resolution included) ---------------
   175 | 
   176 | def _dry(*argv: str) -> subprocess.CompletedProcess:
   177 |     env = {k: v for k, v in os.environ.items()
   178 |            if k not in ("ANTHROPIC_API_KEY", "AWS_BEARER_TOKEN_BEDROCK", "CLAUDE_HEADLESS_BIN")}
   179 |     return subprocess.run(
   180 |         [sys.executable, str(CHEVAL), "--agent", "reviewing-code", "--prompt", "c127-effort",
   181 |          "--dry-run", "--json-errors", *argv],
   182 |         capture_output=True, text=True, env=env, cwd=str(REPO_ROOT), timeout=120,
   183 |     )
   184 | 
   185 | 
   186 | def test_dry_run_opus_without_effort_reports_the_catalog_high():
   187 |     proc = _dry("--model", "opus")
   188 |     assert proc.returncode == 0, proc.stderr
   189 |     out = json.loads(proc.stdout)
   190 |     # the alias resolves first; only then is the entry's default read
   191 |     assert out["resolved_provider"] == "anthropic" and out["resolved_model"] == "claude-opus-5-5"
   192 |     assert out["effort"] == "high" and out["effort_effective"] == "high"
   193 |     assert out["effort_source"] == "catalog"
   194 |     assert "effort: high (catalog default)" in proc.stderr
   195 | 
   196 | 
   197 | def test_dry_run_explicit_effort_reports_the_caller_value():
~~~~

The change from head to the fix:

~~~~diff
@@ -185,0 +198,6 @@
+def test_dry_env_cannot_reach_a_real_claude():
+    import shutil
+    path = _no_claude_path()
+    assert shutil.which("claude", path=path) is None and shutil.which("claude-bedrock", path=path) is None
+
+
~~~~

## H86 — .claude/adapters/tests/test_effort_catalog_default.py — insertion after head line 395

Head context (head/.claude/adapters/tests/test_effort_catalog_default.py, lines 384–395):

~~~~text
   384 |     assert cmd[cmd.index("--effort") + 1] == "low"   # legacy rung still applies when nothing is resolved
   385 | 
   386 | 
   387 | # --- MODELINV schema --------------------------------------------------------
   388 | 
   389 | def test_modelinv_schema_declares_effort_source():
   390 |     schema_path = REPO_ROOT / ".claude" / "data" / "trajectory-schemas" / "model-events" / \
   391 |         "model-invoke-complete.payload.schema.json"
   392 |     schema = json.loads(schema_path.read_text())
   393 |     assert schema["properties"]["effort_source"]["enum"] == ["caller", "catalog", "extra", "none"]
   394 |     assert schema["properties"]["effort_effective"]["enum"] == ["low", "medium", "high", "xhigh", "max"]
   395 |     assert not {"effort_source", "effort_effective"} & set(schema.get("required", []))
~~~~

The change from head to the fix:

~~~~diff
@@ -395,0 +414,47 @@
+
+
+# --- review r251-1 G7 (finding 25): an invalid CLI extra.effort is not silently skipped -------------------------------
+
+@pytest.mark.parametrize("key", ["effort", "reasoning_effort"])
+def test_invalid_extra_effort_warns_once_per_model_and_reason(key, caplog):
+    entry = {"kind": "cli", "extra": {key: "ultra"}}
+    with caplog.at_level("WARNING"):
+        for _ in range(3):
+            assert cheval.resolve_effort(_ns(None), entry, model_key="anthropic:claude-headless") == (None, "none")
+    warns = [r for r in caplog.records if "extra." in r.getMessage() and "ignored" in r.getMessage()]
+    assert len(warns) == 1, [r.getMessage() for r in caplog.records]
+    assert "anthropic:claude-headless" in warns[0].getMessage() and "'ultra'" in warns[0].getMessage()
+
+
+def test_invalid_extra_effort_on_an_http_entry_is_not_read_and_not_warned(caplog):
+    with caplog.at_level("WARNING"):
+        assert cheval.resolve_effort(_ns(None), {"auth_type": "http_api", "extra": {"effort": "ultra"}}) == (None, "none")
+    assert not [r for r in caplog.records if "extra." in r.getMessage()]
+
+
+def test_extra_rung_iterates_both_keys_in_the_adapter_order(caplog):
+    """r251-1 G7 (refined): like ClaudeHeadlessAdapter._resolve_effort — extra.effort, then extra.reasoning_effort — an
+    invalid first key does not hide a valid second one, and the invalid one is said once."""
+    entry = {"kind": "cli", "extra": {"effort": "ultra", "reasoning_effort": "low"}}
+    with caplog.at_level("WARNING"):
+        for _ in range(2):
+            assert cheval.resolve_effort(_ns(None), entry, model_key="anthropic:claude-headless") == ("low", "extra")
+    warns = [r for r in caplog.records if "extra.effort" in r.getMessage() and "ignored" in r.getMessage()]
+    assert len(warns) == 1, [r.getMessage() for r in caplog.records]
+    assert cheval.resolve_effort(_ns(None), {"kind": "cli", "extra": {"effort": "high", "reasoning_effort": "low"}}) == ("high", "extra")
+
+
+def test_r251_4_a_wire_effort_failure_never_loses_the_modelinv_envelope(monkeypatch, caplog):
+    """r251-4 S8 (audit n29/n30): `_effort_on_wire` runs inside the MODELINV emit's try — an exception there used to lose
+    the whole envelope ([AUDIT-EMIT-FAILED]). It is now evaluated in its own try: the field records None, one WARN."""
+    import logging
+    def _boom(*_a, **_k):
+        raise RuntimeError("wire_effort exploded")
+    monkeypatch.setattr(cheval, "_effort_on_wire", _boom)
+    with caplog.at_level(logging.WARNING):
+        code, seen, captured = _invoke(monkeypatch)
+    assert code == 0
+    assert captured.get("effort") == "high" and captured.get("effort_source") == "catalog", captured
+    assert captured.get("effort_effective") is None
+    assert any("effort_effective" in r.getMessage() and "wire_effort exploded" in r.getMessage() for r in caplog.records), \
+        [r.getMessage() for r in caplog.records]
~~~~

## H87 — .claude/adapters/tests/test_no_literal_opus55_ceiling_pins.py — head line 2

Head context (head/.claude/adapters/tests/test_no_literal_opus55_ceiling_pins.py, lines 1–14):

~~~~text
     1 | """cycle-127 FR-3.4 guard (SDD D-3.4): the suites whose Opus 5.5 ceiling pins
>    2 | were swept to read the catalog must not grow a literal 180K back.
     3 | 
     4 | The uncalibrated policy cap (`CEILING_CAP = 180_000`, the 4.x/5-family
     5 | entries' bound until a probe calibrates them) is the one literal allowed, and
     6 | it is allowed only as that named constant and in its SDD §2.1 docstring. Every
     7 | other `180000` / `180_000` / `180,000` in these files fails this test — a
     8 | literal there would turn red when the probe writes the measured Opus 5.5 bound.
     9 | """
    10 | from __future__ import annotations
    11 | 
    12 | import re
    13 | from pathlib import Path
    14 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -2 +2,2 @@
-were swept to read the catalog must not grow a literal 180K back.
+were swept to read the catalog must not grow a literal 180K back — nor pin the
+current calibrated bound (936K, r251-3 R2).
~~~~

## H88 — .claude/adapters/tests/test_no_literal_opus55_ceiling_pins.py — head line 18

Head context (head/.claude/adapters/tests/test_no_literal_opus55_ceiling_pins.py, lines 6–30):

~~~~text
     6 | it is allowed only as that named constant and in its SDD §2.1 docstring. Every
     7 | other `180000` / `180_000` / `180,000` in these files fails this test — a
     8 | literal there would turn red when the probe writes the measured Opus 5.5 bound.
     9 | """
    10 | from __future__ import annotations
    11 | 
    12 | import re
    13 | from pathlib import Path
    14 | 
    15 | import pytest
    16 | 
    17 | ROOT = Path(__file__).resolve().parents[3]
>   18 | LITERAL = re.compile(r"(?<![\d_,])180[_,]?000(?![\d_,])")
    19 | 
    20 | # file → the exact lines allowed to carry the literal (the policy cap, not the Opus 5.5 value)
    21 | SWEPT = {
    22 |     ".claude/adapters/tests/test_anthropic_catalog_floor.py": {
    23 |         "CEILING_CAP = 180_000",
    24 |         '"""SDD §2.1: ceiling = min(180000, context_window − default_max_tokens(entry)) — computed, not a constant."""',
    25 |     },
    26 |     "tests/unit/loa-status-providers.bats": set(),
    27 | }
    28 | 
    29 | 
    30 | @pytest.mark.parametrize("rel", sorted(SWEPT))
~~~~

The change from head to the fix:

~~~~diff
@@ -18 +19,3 @@
-LITERAL = re.compile(r"(?<![\d_,])180[_,]?000(?![\d_,])")
+# r251-3 R2: also the CURRENT calibrated bound (936,000 since the cycle-127 Task 1.5 probe) — a literal of the live
+# value turns red at the next re-probe exactly like a literal 180K would. Nothing is allow-listed for it.
+LITERAL = re.compile(r"(?<![\d_,])(?:180|936)[_,]?000(?![\d_,])")
~~~~

## H89 — .claude/adapters/tests/test_no_literal_opus55_ceiling_pins.py — insertion after head line 50

Head context (head/.claude/adapters/tests/test_no_literal_opus55_ceiling_pins.py, lines 39–54):

~~~~text
    39 |     assert offenders == [], "read the catalog instead of pinning the Opus 5.5 bound:\n" + "\n".join(offenders)
    40 | 
    41 | 
    42 | def test_the_policy_cap_is_never_compared_against_the_opus_5_5_entry_directly():
    43 |     text = (ROOT / ".claude/adapters/tests/test_anthropic_catalog_floor.py").read_text()
    44 |     for line in text.splitlines():
    45 |         if "CEILING_CAP" in line and "claude-opus-5-5" in line:
    46 |             pytest.fail(f"CEILING_CAP pinned against claude-opus-5-5: {line.strip()}")
    47 | 
    48 | 
    49 | @pytest.mark.parametrize("line, hit", [
    50 |     ("x == 180000", True), ("x == 180_000", True), ("probed 180,000 tokens", True),
    51 |     ("1800000000", False), ("180_000_000", False), ("1180000", False), ("18000", False),
    52 | ])
    53 | def test_the_guard_pattern(line, hit):
    54 |     assert bool(LITERAL.search(line)) is hit
~~~~

The change from head to the fix:

~~~~diff
@@ -50,0 +54 @@
+    ("x == 936000", True), ("x == 936_000", True), ("= 936,000", True), ("9360000", False), ("936_000_000", False),
~~~~

## H90 — .claude/data/schemas/model-config-v3.schema.json — head line 274

Head context (head/.claude/data/schemas/model-config-v3.schema.json, lines 262–286):

~~~~text
   262 |           "type": "string",
   263 |           "enum": ["empirical_probe", "kf_derived", "operator_set", "conservative_default"],
   264 |           "description": "How the ceiling value was determined. empirical_probe is the gold standard (per FR-1.6 5×5 binary-search protocol); conservative_default falls back to SDD §3.1.2 formula."
   265 |         },
   266 |         "calibrated_at": {
   267 |           "type": ["string", "null"],
   268 |           "format": "date-time",
   269 |           "description": "ISO 8601 timestamp of last calibration. Cheval compares against now() + stale_after_days for staleness detection. null when source=conservative_default (no probe has run; staleness check evaluates non-stale per SDD §3.1.2)."
   270 |         },
   271 |         "sample_size": {
   272 |           "type": ["integer", "null"],
   273 |           "minimum": 0,
>  274 |           "description": "Number of probe runs that informed the ceiling. null when source != empirical_probe."
   275 |         },
   276 |         "stale_after_days": {
   277 |           "type": "integer",
   278 |           "minimum": 1,
   279 |           "description": "Days after calibrated_at when ceiling is considered stale. Cheval emits ceiling_stale warning to MODELINV envelope past this threshold and routes through chunked path defensively (FR-4)."
   280 |         },
   281 |         "reprobe_trigger": {
   282 |           "type": "string",
   283 |           "description": "Human-readable description of conditions that should re-fire the probe (e.g., 'first KF entry referencing model OR 30d elapsed OR operator-forced')."
   284 |         },
   285 |         "method": {
   286 |           "type": "string",
~~~~

The change from head to the fix:

~~~~diff
@@ -274 +274 @@
-          "description": "Number of probe runs that informed the ceiling. null when source != empirical_probe."
+          "description": "The number of probe samples taken (accepted + rejected) that informed the ceiling (cycle-127: tools/ceiling-probe-live.py writes the count of its record's samples for both transports). null when no probe ran (e.g. conservative_default, or an operator_set value not taken from a probe)."
~~~~

## H91 — .claude/data/schemas/model-config-v3.schema.json — insertion after head line 287

Head context (head/.claude/data/schemas/model-config-v3.schema.json, lines 276–299):

~~~~text
   276 |         "stale_after_days": {
   277 |           "type": "integer",
   278 |           "minimum": 1,
   279 |           "description": "Days after calibrated_at when ceiling is considered stale. Cheval emits ceiling_stale warning to MODELINV envelope past this threshold and routes through chunked path defensively (FR-4)."
   280 |         },
   281 |         "reprobe_trigger": {
   282 |           "type": "string",
   283 |           "description": "Human-readable description of conditions that should re-fire the probe (e.g., 'first KF entry referencing model OR 30d elapsed OR operator-forced')."
   284 |         },
   285 |         "method": {
   286 |           "type": "string",
   287 |           "enum": ["probed_api", "probed_headless"],
   288 |           "description": "cycle-127 FR-3 (SDD D-3.8): how a probe measured the bound — tools/ceiling-probe-live.py through the API or through the headless CLI (--transport claude-headless). Absent on entries never probed by the tool."
   289 |         },
   290 |         "transport": {
   291 |           "type": "string",
   292 |           "enum": ["api", "claude-headless"],
   293 |           "description": "cycle-127 FR-3: the probe transport that measured the bound."
   294 |         },
   295 |         "cli_version": {
   296 |           "type": ["string", "null"],
   297 |           "description": "cycle-127 FR-3: `claude --version` of the CLI the headless probe ran (null when it could not be read)."
   298 |         },
   299 |         "cli_model": {
~~~~

The change from head to the fix:

~~~~diff
@@ -287,0 +288 @@
+          "maxLength": 200,
~~~~

## H92 — .claude/data/schemas/model-config-v3.schema.json — insertion after head line 292

Head context (head/.claude/data/schemas/model-config-v3.schema.json, lines 281–304):

~~~~text
   281 |         "reprobe_trigger": {
   282 |           "type": "string",
   283 |           "description": "Human-readable description of conditions that should re-fire the probe (e.g., 'first KF entry referencing model OR 30d elapsed OR operator-forced')."
   284 |         },
   285 |         "method": {
   286 |           "type": "string",
   287 |           "enum": ["probed_api", "probed_headless"],
   288 |           "description": "cycle-127 FR-3 (SDD D-3.8): how a probe measured the bound — tools/ceiling-probe-live.py through the API or through the headless CLI (--transport claude-headless). Absent on entries never probed by the tool."
   289 |         },
   290 |         "transport": {
   291 |           "type": "string",
   292 |           "enum": ["api", "claude-headless"],
   293 |           "description": "cycle-127 FR-3: the probe transport that measured the bound."
   294 |         },
   295 |         "cli_version": {
   296 |           "type": ["string", "null"],
   297 |           "description": "cycle-127 FR-3: `claude --version` of the CLI the headless probe ran (null when it could not be read)."
   298 |         },
   299 |         "cli_model": {
   300 |           "type": "string",
   301 |           "description": "cycle-127 FR-3: the model id the CLI ran (the Bedrock inference-profile id when the route is Bedrock)."
   302 |         },
   303 |         "measured_input_tokens": {
   304 |           "type": "integer",
~~~~

The change from head to the fix:

~~~~diff
@@ -292,0 +294 @@
+          "maxLength": 200,
~~~~

## H93 — .claude/data/schemas/model-config-v3.schema.json — insertion after head line 296

Head context (head/.claude/data/schemas/model-config-v3.schema.json, lines 285–308):

~~~~text
   285 |         "method": {
   286 |           "type": "string",
   287 |           "enum": ["probed_api", "probed_headless"],
   288 |           "description": "cycle-127 FR-3 (SDD D-3.8): how a probe measured the bound — tools/ceiling-probe-live.py through the API or through the headless CLI (--transport claude-headless). Absent on entries never probed by the tool."
   289 |         },
   290 |         "transport": {
   291 |           "type": "string",
   292 |           "enum": ["api", "claude-headless"],
   293 |           "description": "cycle-127 FR-3: the probe transport that measured the bound."
   294 |         },
   295 |         "cli_version": {
   296 |           "type": ["string", "null"],
   297 |           "description": "cycle-127 FR-3: `claude --version` of the CLI the headless probe ran (null when it could not be read)."
   298 |         },
   299 |         "cli_model": {
   300 |           "type": "string",
   301 |           "description": "cycle-127 FR-3: the model id the CLI ran (the Bedrock inference-profile id when the route is Bedrock)."
   302 |         },
   303 |         "measured_input_tokens": {
   304 |           "type": "integer",
   305 |           "minimum": 1,
   306 |           "description": "cycle-127 FR-3: the accepted input size the provider reported (usage input + cache creation + cache read) on the largest verified step — the value written to probed_ceiling / effective_input_ceiling."
   307 |         }
   308 |       }
~~~~

The change from head to the fix:

~~~~diff
@@ -296,0 +299 @@
+          "maxLength": 200,
~~~~

## H94 — .claude/data/schemas/model-config-v3.schema.json — insertion after head line 300

Head context (head/.claude/data/schemas/model-config-v3.schema.json, lines 289–312):

~~~~text
   289 |         },
   290 |         "transport": {
   291 |           "type": "string",
   292 |           "enum": ["api", "claude-headless"],
   293 |           "description": "cycle-127 FR-3: the probe transport that measured the bound."
   294 |         },
   295 |         "cli_version": {
   296 |           "type": ["string", "null"],
   297 |           "description": "cycle-127 FR-3: `claude --version` of the CLI the headless probe ran (null when it could not be read)."
   298 |         },
   299 |         "cli_model": {
   300 |           "type": "string",
   301 |           "description": "cycle-127 FR-3: the model id the CLI ran (the Bedrock inference-profile id when the route is Bedrock)."
   302 |         },
   303 |         "measured_input_tokens": {
   304 |           "type": "integer",
   305 |           "minimum": 1,
   306 |           "description": "cycle-127 FR-3: the accepted input size the provider reported (usage input + cache creation + cache read) on the largest verified step — the value written to probed_ceiling / effective_input_ceiling."
   307 |         }
   308 |       }
   309 |     },
   310 |     "streamingRecovery": {
   311 |       "type": "object",
   312 |       "additionalProperties": false,
~~~~

The change from head to the fix:

~~~~diff
@@ -300,0 +304 @@
+          "maxLength": 200,
~~~~

## H95 — .claude/data/schemas/model-config-v3.schema.json — head lines 306–307

Head context (head/.claude/data/schemas/model-config-v3.schema.json, lines 294–319):

~~~~text
   294 |         },
   295 |         "cli_version": {
   296 |           "type": ["string", "null"],
   297 |           "description": "cycle-127 FR-3: `claude --version` of the CLI the headless probe ran (null when it could not be read)."
   298 |         },
   299 |         "cli_model": {
   300 |           "type": "string",
   301 |           "description": "cycle-127 FR-3: the model id the CLI ran (the Bedrock inference-profile id when the route is Bedrock)."
   302 |         },
   303 |         "measured_input_tokens": {
   304 |           "type": "integer",
   305 |           "minimum": 1,
>  306 |           "description": "cycle-127 FR-3: the accepted input size the provider reported (usage input + cache creation + cache read) on the largest verified step — the value written to probed_ceiling / effective_input_ceiling."
>  307 |         }
   308 |       }
   309 |     },
   310 |     "streamingRecovery": {
   311 |       "type": "object",
   312 |       "additionalProperties": false,
   313 |       "description": "cycle-109 FR-4.4: streaming-with-recovery thresholds per model. SDD §3.1.1 + §3.1.2 default policy. Distinct from effective_input_ceiling (which is the preemptive gate); these are the runtime recovery knobs once dispatch has started.",
   314 |       "properties": {
   315 |         "first_token_deadline_seconds": {
   316 |           "type": "integer",
   317 |           "minimum": 1,
   318 |           "description": "Time-to-first-token before stream is considered hung. Default 30s for non-reasoning, 60s for reasoning_class (per SDD §3.1.2)."
   319 |         },
~~~~

The change from head to the fix:

~~~~diff
@@ -306,2 +310,13 @@
-          "description": "cycle-127 FR-3: the accepted input size the provider reported (usage input + cache creation + cache read) on the largest verified step — the value written to probed_ceiling / effective_input_ceiling."
+          "description": "cycle-127 FR-3: the accepted input size the provider reported (usage input + cache creation + cache read) on the largest verified step — the raw value; probed_ceiling / effective_input_ceiling carry min(this, context_window − default max_tokens) (cheval's I2 invariant)."
+        },
+        "probe_outcome": {
+          "type": "string",
+          "enum": ["clean", "partial"],
+          "description": "cycle-127 r251-1: the outcome of the probe whose bound this entry carries — clean (a verified accept bracketed by a size rejection within the tolerance, nothing failed) or partial (budget cap, an unverified or failed attempt, or an unbracketed bound; written only when the operator vouches for the last verified accept: tools/ceiling-probe-live.py --write-partial-as-operator-set). Required when method is probed_headless (r251-4); absent on entries never written by the tool."
         }
+      },
+      "if": {"required": ["method"], "properties": {"method": {"const": "probed_headless"}}},
+      "then": {
+        "$comment": "cycle-127 r251-4 (n35/n48): a headless-probed bound names its transport and the probe outcome it carries.",
+        "required": ["transport", "probe_outcome"],
+        "properties": {"transport": {"const": "claude-headless"}}
~~~~

## H96 — .claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json — insertion after head line 64

Head context (head/.claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json, lines 53–76):

~~~~text
    53 |           },
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
    65 |           "provider": {
    66 |             "description": "cycle-104 Sprint 2 (T2.6 / FR-S2.3). Provider key for this entry (e.g. openai, anthropic, google). Optional for backward compat; new emitters MUST populate.",
    67 |             "type": "string",
    68 |             "minLength": 1
    69 |           },
    70 |           "missing_capabilities": {
    71 |             "description": "cycle-104 Sprint 2 (FR-S2.7). Populated when error_class=CAPABILITY_MISS; lists the capabilities the request required that this entry does not declare.",
    72 |             "type": "array",
    73 |             "items": {
    74 |               "type": "string",
    75 |               "minLength": 1
    76 |             }
~~~~

The change from head to the fix:

~~~~diff
@@ -64,0 +65,4 @@
+          "failure_class": {
+            "description": "cycle-127 review r251-2 K2. A finer class under error_class; today only opt_in_required (an agy-alone chain refused by hounfour.headless.agy_opt_in, error_class INVALID_CONFIG). Optional/additive.",
+            "enum": ["opt_in_required"]
+          },
~~~~

## H97 — .claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json — insertion after head line 510

Head context (head/.claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json, lines 499–522):

~~~~text
   499 |                 "pattern": "^[A-Za-z0-9._-]+$"
   500 |               },
   501 |               "reason": {
   502 |                 "enum": [
   503 |                   "EmptyContent",
   504 |                   "RateLimited",
   505 |                   "ProviderUnavailable",
   506 |                   "RetriesExhausted",
   507 |                   "ContextTooLarge",
   508 |                   "NoEligibleAdapter",
   509 |                   "ChainExhausted",
   510 |                   "InteractionPending",
   511 |                   "Other"
   512 |                 ]
   513 |               },
   514 |               "exit_code": {
   515 |                 "type": "integer",
   516 |                 "minimum": 0,
   517 |                 "maximum": 255
   518 |               },
   519 |               "blocker_risk": {
   520 |                 "enum": [
   521 |                   "unknown",
   522 |                   "low",
~~~~

The change from head to the fix:

~~~~diff
@@ -510,0 +515 @@
+                  "OptInRequired",
~~~~

## H98 — .claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json — insertion after head line 754

Head context (head/.claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json, lines 743–766):

~~~~text
   743 |       "type": "boolean"
   744 |     },
   745 |     "effort": {
   746 |       "description": "Cycle-114 FR-8: reasoning-effort level requested for this invocation (Anthropic output_config.effort on Opus 4.5+/Sonnet 4.6). Optional \u2014 absent on calls that did not set effort (model default = high). Lets the Empirical Model Economy roll-up report cost-per-clean-output by (skill x model x effort).",
   747 |       "enum": [
   748 |         "low",
   749 |         "medium",
   750 |         "high",
   751 |         "xhigh",
   752 |         "max"
   753 |       ]
   754 |     },
   755 |     "effort_source": {
   756 |       "description": "Cycle-127 FR-2 (SDD D-2.3/D-2.5): where `effort` came from \u2014 `caller` (explicit --effort), `catalog` (the resolved entry's params.default_effort), `extra` (a CLI entry's legacy extra.effort) or `none` (nothing sent; vendor default). Optional/additive.",
   757 |       "enum": [
   758 |         "caller",
   759 |         "catalog",
   760 |         "extra",
   761 |         "none"
   762 |       ]
   763 |     },
   764 |     "effort_effective": {
   765 |       "description": "Cycle-127 FR-2 (SDD D-2.6): the effort the answering hop put on the wire after the adapter's per-family mapping (e.g. xhigh \u2192 high on Opus 4.6). Absent when nothing was sent. Optional/additive.",
   766 |       "enum": [
~~~~

The change from head to the fix:

~~~~diff
@@ -754,0 +760,27 @@
+    "models_not_planned": {
+      "description": "Cycle-127 review r251-1 G1 (SDD D-1.3/D-1.6): chain hops cheval did NOT plan \u2014 never dispatched, not in models_requested, not a failure (verdict quality counts planned hops only; no circuit-breaker count). `opt_in_required`: an agy (gemini-headless) hop while hounfour.headless.agy_opt_in is not true. Also present on a direct agy call refused by the opt-in. Optional/additive.",
+      "type": "array",
+      "items": {
+        "type": "object",
+        "required": [
+          "model",
+          "reason"
+        ],
+        "additionalProperties": false,
+        "properties": {
+          "model": {
+            "type": "string",
+            "minLength": 1
+          },
+          "provider": {
+            "type": "string",
+            "minLength": 1
+          },
+          "reason": {
+            "enum": [
+              "opt_in_required"
+            ]
+          }
+        }
+      }
+    },
~~~~

## H99 — .claude/defaults/model-config.yaml — head lines 495–501

Head context (head/.claude/defaults/model-config.yaml, lines 483–513):

~~~~text
   483 |         auth_type: http_api
   484 |         dispatch_group: anthropic-claude
   485 |         capabilities: [chat, tools, function_calling, thinking_traces, structured_json]
   486 |         context_window: 1000000
   487 |         token_param: max_tokens
   488 |         # Within-company chain: 5.5 → 5 → Sonnet 5 → headless.
   489 |         fallback_chain:
   490 |           - anthropic:claude-opus-5
   491 |           - anthropic:claude-sonnet-5
   492 |           - anthropic:claude-headless
   493 |         max_output_tokens: 128000
   494 |         effective_input_ceiling: 936000   # cycle-124 FR-3 (SDD §2.1): see claude-fable-5-1
>  495 |         # cycle-127 FR-3: bound measured 2026-10-07 by tools/ceiling-probe-live.py --transport claude-headless (Bedrock, global.anthropic.claude-opus-5-5); see ceiling_calibration.reprobe_trigger.
>  496 |         # operator_set (lead, maintainer delegation 2026-10-07): the tool's own outcome was `partial` — the $20 budget cap stopped the
>  497 |         # bisection before the 16K tolerance (the filler under-counts ~1.8x under the Opus 4.7+ tokenizer) — but the largest accept
>  498 |         # (972,887 measured input tokens, needle-verified; ceiling_calibration.measured_input_tokens) and the CLI pre-flight rejection
>  499 |         # at ~1,065,182 (stated limit 1,000,000) bound the route. Written as 936,000 = context_window 1,000,000 − the 64,000 default
>  500 |         # output budget (cheval's I2 invariant: input ceiling + default max_tokens ≤ context_window), below the measured accept.
>  501 |         # Record: grimoires/loa/reports/2026-10-07-opus-5-5-ceiling-probe-cli.json
   502 |         probed_ceiling: 936000
   503 |         ceiling_calibration:
   504 |           source: operator_set
   505 |           calibrated_at: "2026-10-07T09:29:07Z"
   506 |           sample_size: null
   507 |           stale_after_days: 90
   508 |           reprobe_trigger: "API-transport probe (tools/ceiling-probe-live.py --transport api) from a host with ANTHROPIC_API_KEY; this bound was measured through claude-headless on Bedrock (global.anthropic.claude-opus-5-5) on 2026-10-07"
   509 |           method: probed_headless
   510 |           transport: claude-headless
   511 |           cli_version: "2.1.292 (Claude Code)"
   512 |           cli_model: "global.anthropic.claude-opus-5-5"
   513 |           measured_input_tokens: 972887
~~~~

The change from head to the fix:

~~~~diff
@@ -495,7 +495,6 @@
-        # cycle-127 FR-3: bound measured 2026-10-07 by tools/ceiling-probe-live.py --transport claude-headless (Bedrock, global.anthropic.claude-opus-5-5); see ceiling_calibration.reprobe_trigger.
-        # operator_set (lead, maintainer delegation 2026-10-07): the tool's own outcome was `partial` — the $20 budget cap stopped the
-        # bisection before the 16K tolerance (the filler under-counts ~1.8x under the Opus 4.7+ tokenizer) — but the largest accept
-        # (972,887 measured input tokens, needle-verified; ceiling_calibration.measured_input_tokens) and the CLI pre-flight rejection
-        # at ~1,065,182 (stated limit 1,000,000) bound the route. Written as 936,000 = context_window 1,000,000 − the 64,000 default
-        # output budget (cheval's I2 invariant: input ceiling + default max_tokens ≤ context_window), below the measured accept.
-        # Record: grimoires/loa/reports/2026-10-07-opus-5-5-ceiling-probe-cli.json
+        # cycle-127 FR-3: measured 2026-10-07 through claude-headless on Bedrock; operator_set, clamped to cheval's I2
+        # invariant (context_window − the default output budget). Provenance is structured in ceiling_calibration
+        # (probe_outcome, measured_input_tokens, method, transport, cli_*); record:
+        # grimoires/loa/reports/2026-10-07-opus-5-5-ceiling-probe-cli.json (SDD §1.6)
+        # Units: provider-measured tokens; cheval counts exactly above half the bound on calibrated entries;
+        # Bridgebuilder's budget divides by 1.8.
~~~~

## H100 — .claude/defaults/model-config.yaml — head line 506

Head context (head/.claude/defaults/model-config.yaml, lines 494–518):

~~~~text
   494 |         effective_input_ceiling: 936000   # cycle-124 FR-3 (SDD §2.1): see claude-fable-5-1
   495 |         # cycle-127 FR-3: bound measured 2026-10-07 by tools/ceiling-probe-live.py --transport claude-headless (Bedrock, global.anthropic.claude-opus-5-5); see ceiling_calibration.reprobe_trigger.
   496 |         # operator_set (lead, maintainer delegation 2026-10-07): the tool's own outcome was `partial` — the $20 budget cap stopped the
   497 |         # bisection before the 16K tolerance (the filler under-counts ~1.8x under the Opus 4.7+ tokenizer) — but the largest accept
   498 |         # (972,887 measured input tokens, needle-verified; ceiling_calibration.measured_input_tokens) and the CLI pre-flight rejection
   499 |         # at ~1,065,182 (stated limit 1,000,000) bound the route. Written as 936,000 = context_window 1,000,000 − the 64,000 default
   500 |         # output budget (cheval's I2 invariant: input ceiling + default max_tokens ≤ context_window), below the measured accept.
   501 |         # Record: grimoires/loa/reports/2026-10-07-opus-5-5-ceiling-probe-cli.json
   502 |         probed_ceiling: 936000
   503 |         ceiling_calibration:
   504 |           source: operator_set
   505 |           calibrated_at: "2026-10-07T09:29:07Z"
>  506 |           sample_size: null
   507 |           stale_after_days: 90
   508 |           reprobe_trigger: "API-transport probe (tools/ceiling-probe-live.py --transport api) from a host with ANTHROPIC_API_KEY; this bound was measured through claude-headless on Bedrock (global.anthropic.claude-opus-5-5) on 2026-10-07"
   509 |           method: probed_headless
   510 |           transport: claude-headless
   511 |           cli_version: "2.1.292 (Claude Code)"
   512 |           cli_model: "global.anthropic.claude-opus-5-5"
   513 |           measured_input_tokens: 972887
   514 |         account_limits:
   515 |           tier: unverified
   516 |           itpm: null
   517 |         params:
   518 |           temperature_supported: false
~~~~

The change from head to the fix:

~~~~diff
@@ -506 +505 @@
-          sample_size: null
+          sample_size: 5
~~~~

## H101 — .claude/defaults/model-config.yaml — insertion after head line 513

Head context (head/.claude/defaults/model-config.yaml, lines 502–525):

~~~~text
   502 |         probed_ceiling: 936000
   503 |         ceiling_calibration:
   504 |           source: operator_set
   505 |           calibrated_at: "2026-10-07T09:29:07Z"
   506 |           sample_size: null
   507 |           stale_after_days: 90
   508 |           reprobe_trigger: "API-transport probe (tools/ceiling-probe-live.py --transport api) from a host with ANTHROPIC_API_KEY; this bound was measured through claude-headless on Bedrock (global.anthropic.claude-opus-5-5) on 2026-10-07"
   509 |           method: probed_headless
   510 |           transport: claude-headless
   511 |           cli_version: "2.1.292 (Claude Code)"
   512 |           cli_model: "global.anthropic.claude-opus-5-5"
   513 |           measured_input_tokens: 972887
   514 |         account_limits:
   515 |           tier: unverified
   516 |           itpm: null
   517 |         params:
   518 |           temperature_supported: false
   519 |           thinking_adaptive: true
   520 |           beta_headers: []
   521 |           # cycle-127 D-2: the vendor effort default is `medium` since Opus 5.5
   522 |           # (Opus 5 was `high`; claude-api reference 2026-10-07). cheval sends
   523 |           # this when the caller passes no --effort; an explicit --effort wins.
   524 |           default_effort: high
   525 |         pricing:
~~~~

The change from head to the fix:

~~~~diff
@@ -513,0 +513 @@
+          probe_outcome: partial
~~~~

## H102 — .claude/defaults/model-config.yaml.checksum — head line 1

Head context (head/.claude/defaults/model-config.yaml.checksum, lines 1–1):

~~~~text
>    1 | 17f75f07918c3c349c826a3be42a35f5b1a2f9b47375858219a0121fc71f0b08
~~~~

The change from head to the fix:

~~~~diff
@@ -1 +1 @@
-17f75f07918c3c349c826a3be42a35f5b1a2f9b47375858219a0121fc71f0b08
+4d17fd65c8e75e71ac2248bd9c7539a64932fc8dadaa2c1b3de3078a19102e93
~~~~

## H103 — .claude/scripts/adversarial-review.sh — insertion after head line 81

Head context (head/.claude/scripts/adversarial-review.sh, lines 70–93):

~~~~text
    70 | # The `|| true` allows eval-based test sourcing where BASH_SOURCE[0] resolves
    71 | # to a temp dir. Tests pre-source lib-content.sh; the double-source guard prevents
    72 | # duplicate loading. See: Bridgebuilder Review Finding #1 (PR #235)
    73 | source "$_LIB_CONTENT_PATH" 2>/dev/null || true
    74 | 
    75 | # cycle-117 item D (#1177): shared DEGRADED/FAILED trajectory + page helper.
    76 | # Same defensive `|| true` soft-source as the libs above — sourcing must not
    77 | # fail under eval-based test sourcing or on a downstream repo mid-update.
    78 | _DEGRADED_VERDICT_LIB_PATH="$SCRIPT_DIR/lib/degraded-verdict-lib.sh"
    79 | # shellcheck source=lib/degraded-verdict-lib.sh
    80 | source "$_DEGRADED_VERDICT_LIB_PATH" 2>/dev/null || true
    81 | 
    82 | # Token budgets (with 80% safety margin per D-009)
    83 | DEFAULT_PRIMARY_TOKEN_BUDGET=24000    # 80% of 30k — non-Anthropic dissenters
    84 | DEFAULT_SECONDARY_TOKEN_BUDGET=12000  # 80% of 15k
    85 | MAX_ESCALATED_FILES=3                 # Per D-011
    86 | # cycle-124 FR-2/FR-3 (SDD §3.2): Anthropic dissenters take the catalog's
    87 | # 180K effective_input_ceiling minus 20K headroom (same figure BB codegen
    88 | # derives), so an Opus-class dissenter sees the whole diff instead of the
    89 | # 24K slice sized for the 2026-05 non-streaming wall.
    90 | _ANTHROPIC_DISPATCH_INPUT_BUDGET=160000
    91 | DISSENT_MAX_OUTPUT_TOKENS=16000       # bounded findings document (cheval --max-tokens)
    92 | 
    93 | # Resolve the primary input budget for the dissenter model's company.
~~~~

The change from head to the fix:

~~~~diff
@@ -81,0 +82,8 @@
+# cycle-127 FR-1 (SDD D-1.5; review r251-1 G2): the one agy route predicate (agy_opted_in, agy_headless_mode, routes_to_agy).
+# Same soft-source as the libs above. If the lib did not load, the planner below fails closed on what it can still tell
+# without it: the opt-in reads off and every hop that names gemini-headless is not planned (opt_in_required); a Google model
+# under cli-only cannot be told apart there, and cheval's own gate refuses that hop (review r251-2 K4).
+_AGY_GATE_LIB_PATH="$SCRIPT_DIR/lib/agy-gate-lib.sh"
+# shellcheck source=lib/agy-gate-lib.sh
+source "$_AGY_GATE_LIB_PATH" 2>/dev/null || true
+
~~~~

## H104 — .claude/scripts/adversarial-review.sh — head lines 2350–2360

Head context (head/.claude/scripts/adversarial-review.sh, lines 2338–2372):

~~~~text
  2338 | 
  2339 | _adv_cli_present() {  # <family> → 0 when the family's CLI hop binary is on PATH (bats seam: LOA_ADVERSARIAL_CLI_PROBE)
  2340 |   local fam="$1" bin=""
  2341 |   case "$fam" in anthropic) bin=claude ;; openai) bin=codex ;; google) bin=agy ;; *) return 1 ;; esac
  2342 |   if [[ -n "${BATS_TEST_FILENAME:-}${BATS_VERSION:-}" && -n "${LOA_ADVERSARIAL_CLI_PROBE:-}" ]]; then
  2343 |     case "$LOA_ADVERSARIAL_CLI_PROBE" in both|"$bin") return 0 ;; *) return 1 ;; esac
  2344 |   fi
  2345 |   command -v "$bin" >/dev/null 2>&1
  2346 | }
  2347 | 
  2348 | # cycle-127 FR-1: the agy (Antigravity) route — the `gemini-headless` hop — is opt-in. Read from the config with yq, never by
  2349 | # spawning cheval: true only for a YAML boolean true at hounfour.headless.agy_opt_in (absent, false, a string — off). No env override.
> 2350 | _adv_agy_opted_in() {
> 2351 |   local v=""
> 2352 |   [[ -f "${CONFIG_FILE:-}" ]] && command -v yq >/dev/null 2>&1 || return 1
> 2353 |   v=$(yq eval '.hounfour.headless.agy_opt_in | (tag == "!!bool" and . == true)' "$CONFIG_FILE" 2>/dev/null) || v=""
> 2354 |   [[ "$v" == "true" ]]
> 2355 | }
> 2356 | _adv_agy_filter_chain() {  # <config key> <family> <chain…> → the chain without its agy hops when the opt-in is off; each drop is said once
> 2357 |   local key="$1" fam="$2" h out=""; shift 2
> 2358 |   if _adv_agy_opted_in; then printf '%s' "$*"; return 0; fi
> 2359 |   for h in "$@"; do
> 2360 |     if [[ "$(_adv_hop_canon "$h" 2>/dev/null || printf '%s' "$h")" == "gemini-headless" ]]; then
  2361 |       log "WARN: companion hop ${h} not planned: the agy route is opt-in (hounfour.headless.agy_opt_in is not true) — named by flatline_protocol.${key}.companion_chain.${fam}"
  2362 |     else out+="$h "; fi
  2363 |   done
  2364 |   printf '%s' "${out% }"
  2365 | }
  2366 | 
  2367 | _companion_chain() {  # <family> → space-separated chain, credential presence deciding the start; "" = no route
  2368 |   local fam="$1" configured=""
  2369 |   case "$fam" in
  2370 |     anthropic) configured="${CONF_COMPANION_CHAIN_ANTHROPIC:-}" ;;
  2371 |     openai)    configured="${CONF_COMPANION_CHAIN_OPENAI:-}" ;;
  2372 |   esac
~~~~

The change from head to the fix:

~~~~diff
@@ -2350,11 +2358,33 @@
+_adv_agy_lib() {  # 0 when the shared predicate is loaded (sourced lazily from PROJECT_ROOT under eval-based test sourcing)
+  declare -F routes_to_agy >/dev/null && return 0
+  [[ -f "${PROJECT_ROOT:-}/.claude/scripts/lib/agy-gate-lib.sh" ]] && source "$PROJECT_ROOT/.claude/scripts/lib/agy-gate-lib.sh" 2>/dev/null
+  declare -F routes_to_agy >/dev/null
+}
 _adv_agy_opted_in() {
-  local v=""
-  [[ -f "${CONFIG_FILE:-}" ]] && command -v yq >/dev/null 2>&1 || return 1
-  v=$(yq eval '.hounfour.headless.agy_opt_in | (tag == "!!bool" and . == true)' "$CONFIG_FILE" 2>/dev/null) || v=""
-  [[ "$v" == "true" ]]
+  _adv_agy_lib || return 1   # (lib missing: off — fail closed)
+  agy_opted_in "${CONFIG_FILE:-}"
 }
 _adv_agy_filter_chain() {  # <config key> <family> <chain…> → the chain without its agy hops when the opt-in is off; each drop is said once
-  local key="$1" fam="$2" h out=""; shift 2
+  # (review r251-1 G2: a hop is agy-routed by the shared routes_to_agy — by name, alias-resolved, or a Google model under
+  # hounfour.headless.mode cli-only — tested on the hop as written and on its catalog id)
+  # (the once-per-shell gate WARN is the caller's, from a top-level planning point — inside $(...) it would be lost)
+  local key="$1" fam="$2" h c out="" mode; shift 2
   if _adv_agy_opted_in; then printf '%s' "$*"; return 0; fi
+  if ! _adv_agy_lib; then
+    # (review r251-2 K4: no predicate to plan with — fail closed on the name: every gemini-headless hop is not planned.
+    # A Google model under cli-only is not recognisable here; cheval's own gate refuses that hop.)
+    log "WARN: lib/agy-gate-lib.sh not loaded — the agy opt-in reads off; companion hops naming gemini-headless are not planned"
+    for h in "$@"; do
+      c=$(_adv_hop_canon "$h" 2>/dev/null || printf '%s' "$h")
+      case "$h $c" in
+        gemini-headless\ *|*:gemini-headless\ *|gemini-headless:*|*\ gemini-headless|*\ *:gemini-headless|*\ gemini-headless:*)
+          log "WARN: companion hop ${h} not planned (opt_in_required): the agy route is opt-in (hounfour.headless.agy_opt_in) — named by flatline_protocol.${key}.companion_chain.${fam}" ;;
+        *) out+="$h " ;;
+      esac
+    done
+    printf '%s' "${out% }"; return 0
+  fi
+  mode=$(agy_headless_mode "${CONFIG_FILE:-}")
   for h in "$@"; do
-    if [[ "$(_adv_hop_canon "$h" 2>/dev/null || printf '%s' "$h")" == "gemini-headless" ]]; then
+    c=$(_adv_hop_canon "$h" 2>/dev/null || printf '%s' "$h")
+    if routes_to_agy "$h" "$mode" "${CONFIG_FILE:-}" || routes_to_agy "$c" "$mode" "${CONFIG_FILE:-}"; then   # (r251-4: project aliases)
~~~~

## H105 — .claude/scripts/adversarial-review.sh — insertion after head line 4081

Head context (head/.claude/scripts/adversarial-review.sh, lines 4070–4093):

~~~~text
  4070 |     exit 2
  4071 |   done
  4072 |   if [[ "${CONF_COMPANION_VOICE:-true}" == "true" && ( -z "${_ADVERSARIAL_WORKDIR:-}" || ! -d "${_ADVERSARIAL_WORKDIR:-}" ) ]]; then
  4073 |     # round 1 (third run, C-006): the companion needs the run's workdir; without one it is not planned
  4074 |     companion_skip_reason="no_workdir"; companion_family=$(_companion_family "$(_adv_family_of "$model")")
  4075 |     log "Companion voice not planned ($companion_family family): no_workdir"
  4076 |   elif [[ "${CONF_COMPANION_VOICE:-true}" == "true" ]]; then
  4077 |     companion_family=$(_companion_family "$(_adv_family_of "$model")")
  4078 |     local companion_chain_str
  4079 |     companion_chain_str=$(_companion_chain "$companion_family")
  4080 |     # cycle-127 FR-1: an agy hop with the opt-in off is not planned; a chain left empty by that is opt_in_required, not no_route
  4081 |     local _agy_pre="$companion_chain_str"
  4082 |     # shellcheck disable=SC2086  # (a space-separated hop list, as everywhere it is walked)
  4083 |     [[ -z "$companion_chain_str" ]] || companion_chain_str=$(_adv_agy_filter_chain "$([[ "$type" == "audit" ]] && echo security_audit || echo code_review)" "$companion_family" $companion_chain_str)
  4084 |     if [[ -z "$companion_chain_str" && -n "$_agy_pre" ]]; then
  4085 |       companion_skip_reason="opt_in_required"
  4086 |     elif [[ -z "$companion_chain_str" ]]; then
  4087 |       companion_skip_reason="no_route"
  4088 |     else
  4089 |       # review sprint-248 C-005 (round 1, live re-run): a hop the primary chain also holds — typically
  4090 |       # the other family's CLI as the primary's last resort — STAYS in the companion chain (a keyless
  4091 |       # primary usually answers earlier, and the second voice is worth having); it is recorded under
  4092 |       # companion_voice.shared_hops and independence is judged after the walk from the voices that
  4093 |       # actually answered (a same-family companion counts as a dropped voice in verdict quality).
~~~~

The change from head to the fix:

~~~~diff
@@ -4081,0 +4112 @@
+    if _adv_agy_lib; then agy_gate_warn_once "${CONFIG_FILE:-}"; fi   # (r251-1 G12/G18: once per run, on stderr — top level, not in $(...))
~~~~

## H106 — .claude/scripts/flatline-orchestrator.sh — insertion after head line 56

Head context (head/.claude/scripts/flatline-orchestrator.sh, lines 45–68):

~~~~text
    45 | #   7 - Silent no-op detected (no findings/attacks produced; see --no-silent-noop-detect)
    46 | # =============================================================================
    47 | 
    48 | set -euo pipefail
    49 | 
    50 | SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    51 | source "$SCRIPT_DIR/bootstrap.sh"
    52 | source "$SCRIPT_DIR/compat-lib.sh"
    53 | source "$SCRIPT_DIR/lib/normalize-json.sh"
    54 | source "$SCRIPT_DIR/lib/verdict-quality.sh"
    55 | source "$SCRIPT_DIR/lib/invoke-diagnostics.sh"
    56 | source "$SCRIPT_DIR/lib/context-isolation-lib.sh"
    57 | # cycle-099 Sprint 1B parity (mirrors red-team-model-adapter.sh): exposes
    58 | # `resolve_provider_id` from generated-model-maps.sh so flatline picks up
    59 | # new model registry entries (gpt-5.5, gpt-5.5-pro, gemini-3.1-pro-preview,
    60 | # etc.) without needing edits to the local MODEL_TO_PROVIDER_ID fallback.
    61 | # shellcheck source=lib/model-resolver.sh
    62 | source "$SCRIPT_DIR/lib/model-resolver.sh"
    63 | 
    64 | # cycle-117 item D (#1177): shared DEGRADED/FAILED trajectory + page helper.
    65 | # Soft-sourced — a downstream repo mid-update (lib file absent) must not
    66 | # break flatline; the degraded_verdict_maybe_emit call below is itself
    67 | # guarded by a declare -F check.
    68 | # shellcheck source=lib/degraded-verdict-lib.sh
~~~~

The change from head to the fix:

~~~~diff
@@ -56,0 +57,2 @@
+# cycle-127 FR-1 (SDD D-1.5; review r251-1 G2): the one agy route predicate (agy_opted_in, agy_headless_mode, routes_to_agy)
+source "$SCRIPT_DIR/lib/agy-gate-lib.sh"
~~~~

## H107 — .claude/scripts/flatline-orchestrator.sh — head lines 522–536

Head context (head/.claude/scripts/flatline-orchestrator.sh, lines 510–548):

~~~~text
   510 |     echo "$model"
   511 | }
   512 | 
   513 | _get_model_tertiary_configured() {  # the configured tertiary, before the agy opt-in gate
   514 |     local model
   515 |     model=$(read_config '.hounfour.flatline_tertiary_model' '')
   516 |     if [[ -z "$model" ]]; then
   517 |         model=$(read_config '.flatline_protocol.models.tertiary' '')
   518 |     fi
   519 |     echo "$model"
   520 | }
   521 | 
>  522 | _agy_opted_in() {  # true only for a YAML boolean true at hounfour.headless.agy_opt_in (read with yq, no env override)
>  523 |     local v=""
>  524 |     [[ -f "$CONFIG_FILE" ]] && command -v yq &> /dev/null || return 1
>  525 |     v=$(yq eval '.hounfour.headless.agy_opt_in | (tag == "!!bool" and . == true)' "$CONFIG_FILE" 2>/dev/null) || v=""
>  526 |     [[ "$v" == "true" ]]
>  527 | }
>  528 | 
>  529 | _tertiary_routes_to_agy() {  # <model> → 0 when cheval would dispatch it through agy: the gemini-headless hop by name
>  530 |     # (bare, provider-prefixed, or as a provider), or a Google model under hounfour.headless.mode cli-only (env wins, as cheval's)
>  531 |     local m="$1" mode
>  532 |     case "$m" in gemini-headless|*:gemini-headless|gemini-headless:*) return 0 ;; esac
>  533 |     mode="${LOA_HEADLESS_MODE:-$(read_config '.hounfour.headless.mode' 'prefer-api')}"
>  534 |     [[ "$mode" == "cli-only" ]] || return 1
>  535 |     case "${m#google:}" in gemini*) return 0 ;; esac
>  536 |     return 1
   537 | }
   538 | 
   539 | tertiary_opt_in_skip_reason() {  # prints the skip line and returns 0 when the configured tertiary is gated off
   540 |     local m
   541 |     m=$(_get_model_tertiary_configured)
   542 |     [[ -n "$m" ]] && _tertiary_routes_to_agy "$m" && ! _agy_opted_in || return 1
   543 |     echo "Tertiary model '$m' not planned: disabled by opt-in (the agy route needs hounfour.headless.agy_opt_in: true) — 2-model Flatline, not a degraded voice"
   544 | }
   545 | 
   546 | get_tertiary_status() {  # active | disabled | disabled_by_opt_in
   547 |     if [[ -n "$(get_model_tertiary)" ]]; then echo "active"
   548 |     elif tertiary_opt_in_skip_reason >/dev/null; then echo "disabled_by_opt_in"
~~~~

The change from head to the fix:

~~~~diff
@@ -522,15 +524,7 @@
-_agy_opted_in() {  # true only for a YAML boolean true at hounfour.headless.agy_opt_in (read with yq, no env override)
-    local v=""
-    [[ -f "$CONFIG_FILE" ]] && command -v yq &> /dev/null || return 1
-    v=$(yq eval '.hounfour.headless.agy_opt_in | (tag == "!!bool" and . == true)' "$CONFIG_FILE" 2>/dev/null) || v=""
-    [[ "$v" == "true" ]]
+_agy_opted_in() {  # true only for a YAML boolean true at hounfour.headless.agy_opt_in (lib/agy-gate-lib.sh; no env override)
+    agy_opted_in "$CONFIG_FILE"
 }
 
-_tertiary_routes_to_agy() {  # <model> → 0 when cheval would dispatch it through agy: the gemini-headless hop by name
-    # (bare, provider-prefixed, or as a provider), or a Google model under hounfour.headless.mode cli-only (env wins, as cheval's)
-    local m="$1" mode
-    case "$m" in gemini-headless|*:gemini-headless|gemini-headless:*) return 0 ;; esac
-    mode="${LOA_HEADLESS_MODE:-$(read_config '.hounfour.headless.mode' 'prefer-api')}"
-    [[ "$mode" == "cli-only" ]] || return 1
-    case "${m#google:}" in gemini*) return 0 ;; esac
-    return 1
+_tertiary_routes_to_agy() {  # <model> → 0 when cheval would dispatch it through agy (lib/agy-gate-lib.sh routes_to_agy:
+    # the gemini-headless hop by name, or a Google model under hounfour.headless.mode cli-only — env wins, as cheval's)
+    routes_to_agy "$1" "$(agy_headless_mode "$CONFIG_FILE")" "$CONFIG_FILE"   # (r251-4: project aliases resolved first)
~~~~

## H108 — .claude/scripts/flatline-orchestrator.sh — insertion after head line 2456

Head context (head/.claude/scripts/flatline-orchestrator.sh, lines 2445–2468):

~~~~text
  2445 |         if mode_result=$("$mode_detect_script" $mode_flag --json 2>/dev/null); then
  2446 |             execution_mode=$(echo "$mode_result" | jq -r '.mode // "interactive"')
  2447 |             mode_reason=$(echo "$mode_result" | jq -r '.reason // "unknown"')
  2448 |             log "Execution mode: $execution_mode (reason: $mode_reason)"
  2449 |         else
  2450 |             log "Warning: Mode detection failed, defaulting to interactive"
  2451 |         fi
  2452 |     else
  2453 |         log "Warning: Mode detection script not found, defaulting to interactive"
  2454 |     fi
  2455 | 
  2456 |     # FR-1 (cycle-045): Log tertiary model status for observability
  2457 |     local tertiary_model_check
  2458 |     tertiary_model_check=$(get_model_tertiary)
  2459 |     if [[ -n "$tertiary_model_check" ]]; then
  2460 |         log "Tertiary model: $tertiary_model_check (active)"
  2461 |     elif [[ "$(get_tertiary_status)" == "disabled_by_opt_in" ]]; then
  2462 |         log "Tertiary model: none (disabled by opt-in: hounfour.headless.agy_opt_in)"
  2463 |     else
  2464 |         log "Tertiary model: none (disabled)"
  2465 |     fi
  2466 | 
  2467 |     log "Document: $doc"
  2468 |     log "Phase: $phase"
~~~~

The change from head to the fix:

~~~~diff
@@ -2456,0 +2451 @@
+    agy_gate_warn_once "$CONFIG_FILE"   # (cycle-127 r251-1 G12/G18: once per run, on stderr)
~~~~

## H109 — .claude/scripts/loa-status.sh — insertion after head line 619

Head context (head/.claude/scripts/loa-status.sh, lines 608–631):

~~~~text
   608 |     # Combine workflow state and version info into single JSON
   609 |     local workflow_json version_json
   610 | 
   611 |     if [[ -x "$WORKFLOW_STATE_SCRIPT" ]]; then
   612 |       workflow_json=$("$WORKFLOW_STATE_SCRIPT" --json 2>/dev/null || echo '{}')
   613 |     else
   614 |       workflow_json='{}'
   615 |     fi
   616 |     workflow_json=$(annotate_workflow_status "$workflow_json")
   617 | 
   618 |     version_json=$(get_version_info_json)
   619 |     agent_network_json=$(get_agent_network_json)
   620 |     providers_json=$(get_providers_json)
   621 | 
   622 |     # Merge the JSON objects: workflow base + framework + agent_network + providers
   623 |     jq -s '.[0] * { "framework": .[1], "agent_network": .[2], "providers": .[3] }' \
   624 |       <(echo "$workflow_json") \
   625 |       <(echo "$version_json") \
   626 |       <(echo "$agent_network_json") \
   627 |       <(echo "$providers_json")
   628 |   else
   629 |     # Human-readable combined output
   630 |     echo "═══════════════════════════════════════════════════════════════"
   631 |     echo -e " ${BOLD}Loa Status${NC}"
~~~~

The change from head to the fix:

~~~~diff
@@ -619,0 +620 @@
+    # (machine mode stays silent on stderr — callers merge streams; the gate is in .providers.*.cli_hop_note)
~~~~

## H110 — .claude/scripts/loa-status.sh — head lines 798–806

Head context (head/.claude/scripts/loa-status.sh, lines 786–818):

~~~~text
   786 |       if grep -qE "^[[:space:]]*(export[[:space:]]+)?${v}=[\"']?[^\"'[:space:]#]" "$envdir/$f" 2>/dev/null; then echo "present ($f)"; return 0; fi
   787 |     done
   788 |   done
   789 |   echo absent
   790 | }
   791 | _providers_config_file() {  # the Loa config the Providers block reads (bats-gated seam: LOA_STATUS_CONFIG_FILE)
   792 |   if [[ -n "${BATS_TEST_FILENAME:-}${BATS_VERSION:-}" && -n "${LOA_STATUS_CONFIG_FILE:-}" ]]; then
   793 |     echo "$LOA_STATUS_CONFIG_FILE"
   794 |   else
   795 |     echo "$CONFIG_FILE"
   796 |   fi
   797 | }
>  798 | _agy_opted_in() {  # cycle-127 FR-1: true only for a YAML boolean true at hounfour.headless.agy_opt_in (no env override)
>  799 |   local cfg v=""; cfg=$(_providers_config_file)
>  800 |   [[ -f "$cfg" ]] && command -v yq >/dev/null 2>&1 || return 1
>  801 |   v=$(yq eval '.hounfour.headless.agy_opt_in | (tag == "!!bool" and . == true)' "$cfg" 2>/dev/null) || v=""
>  802 |   [[ "$v" == "true" ]]
>  803 | }
>  804 | _AGY_OPT_IN_NOTE="agy: opt-in (disabled; hounfour.headless.agy_opt_in)"
>  805 | _provider_hop_note() {  # $1 provider → the hop note when its CLI route is gated off, else ""
>  806 |   [[ "$1" == "google" ]] && ! _agy_opted_in && echo "$_AGY_OPT_IN_NOTE" || echo ""
   807 | }
   808 | _provider_hop() {  # $1 provider → hop binary name or "" (the agy hop is "" while its opt-in is off — cycle-127 FR-1)
   809 |   local bin=""
   810 |   case "$1" in anthropic) bin=claude ;; openai) bin=codex ;; google) bin=agy ;; esac
   811 |   [[ "$bin" == agy ]] && ! _agy_opted_in && { echo ""; return 0; }
   812 |   [[ -n "$bin" ]] && command -v "$bin" >/dev/null 2>&1 && echo "$bin" || echo ""
   813 | }
   814 | _fmt_age_s() { local s="$1"; if [[ ! "$s" =~ ^[0-9]+$ ]]; then echo "-"; elif (( s >= 86400 )); then echo "$(( s / 86400 ))d"; elif (( s >= 3600 )); then echo "$(( s / 3600 ))h"; else echo "$(( s / 60 ))m"; fi; }
   815 | _anthropic_ceiling_json() {  # cycle-126 FR-1.1 (SDD D-1.1b): the input bound the `opus` target runs under
   816 |   # {basis: calibrated|observed|probed, value, model, calibrate[, calibrated_at]} or null.
   817 |   # Sources: the catalog entry (yq) and the observed store cheval writes on a
   818 |   # provider context verdict (.run/ceiling-observed.json, or the same
~~~~

The change from head to the fix:

~~~~diff
@@ -798,9 +799,20 @@
-_agy_opted_in() {  # cycle-127 FR-1: true only for a YAML boolean true at hounfour.headless.agy_opt_in (no env override)
-  local cfg v=""; cfg=$(_providers_config_file)
-  [[ -f "$cfg" ]] && command -v yq >/dev/null 2>&1 || return 1
-  v=$(yq eval '.hounfour.headless.agy_opt_in | (tag == "!!bool" and . == true)' "$cfg" 2>/dev/null) || v=""
-  [[ "$v" == "true" ]]
+# cycle-127 FR-1 (SDD D-1.5; review r251-1 G2): the one agy route predicate (agy_opted_in, routes_to_agy)
+# (r251-4: a partial install without the lib must not abort /loa under set -e — fail-closed stubs instead, as
+# adversarial-review.sh K4: the opt-in reads off and the gemini-headless hop is recognised by name only; said once on
+# stderr in human mode, never under --json)
+# shellcheck source=lib/agy-gate-lib.sh
+if ! { [[ -f "$SCRIPT_DIR/lib/agy-gate-lib.sh" ]] && source "$SCRIPT_DIR/lib/agy-gate-lib.sh"; } \
+   || ! declare -F routes_to_agy >/dev/null 2>&1; then
+  [[ "$JSON_OUTPUT" == "true" ]] || echo "WARN: $SCRIPT_DIR/lib/agy-gate-lib.sh not loaded — the agy opt-in reads off (fail closed); reinstall the framework (/update-loa)" >&2
+  AGY_OPT_IN_NOTE="agy: opt-in (disabled; hounfour.headless.agy_opt_in)"
+  agy_opted_in() { return 1; }
+  routes_to_agy() { case "${1:-}" in gemini-headless|*:gemini-headless|gemini-headless:*) return 0 ;; esac; return 1; }
+  agy_gate_warn_once() { return 0; }
+fi
+_agy_opted_in() {  # true only for a YAML boolean true at hounfour.headless.agy_opt_in (no env override)
+  agy_opted_in "$(_providers_config_file)"
 }
-_AGY_OPT_IN_NOTE="agy: opt-in (disabled; hounfour.headless.agy_opt_in)"
+_AGY_OPT_IN_NOTE="$AGY_OPT_IN_NOTE"
+_provider_cli_model() { case "$1" in anthropic) echo claude-headless ;; openai) echo codex-headless ;; google) echo gemini-headless ;; esac; }
 _provider_hop_note() {  # $1 provider → the hop note when its CLI route is gated off, else ""
-  [[ "$1" == "google" ]] && ! _agy_opted_in && echo "$_AGY_OPT_IN_NOTE" || echo ""
+  routes_to_agy "$(_provider_cli_model "$1")" && ! _agy_opted_in && echo "$_AGY_OPT_IN_NOTE" || echo ""
~~~~

## H111 — .claude/scripts/loa-status.sh — head lines 811–814

Head context (head/.claude/scripts/loa-status.sh, lines 799–826):

~~~~text
   799 |   local cfg v=""; cfg=$(_providers_config_file)
   800 |   [[ -f "$cfg" ]] && command -v yq >/dev/null 2>&1 || return 1
   801 |   v=$(yq eval '.hounfour.headless.agy_opt_in | (tag == "!!bool" and . == true)' "$cfg" 2>/dev/null) || v=""
   802 |   [[ "$v" == "true" ]]
   803 | }
   804 | _AGY_OPT_IN_NOTE="agy: opt-in (disabled; hounfour.headless.agy_opt_in)"
   805 | _provider_hop_note() {  # $1 provider → the hop note when its CLI route is gated off, else ""
   806 |   [[ "$1" == "google" ]] && ! _agy_opted_in && echo "$_AGY_OPT_IN_NOTE" || echo ""
   807 | }
   808 | _provider_hop() {  # $1 provider → hop binary name or "" (the agy hop is "" while its opt-in is off — cycle-127 FR-1)
   809 |   local bin=""
   810 |   case "$1" in anthropic) bin=claude ;; openai) bin=codex ;; google) bin=agy ;; esac
>  811 |   [[ "$bin" == agy ]] && ! _agy_opted_in && { echo ""; return 0; }
>  812 |   [[ -n "$bin" ]] && command -v "$bin" >/dev/null 2>&1 && echo "$bin" || echo ""
>  813 | }
>  814 | _fmt_age_s() { local s="$1"; if [[ ! "$s" =~ ^[0-9]+$ ]]; then echo "-"; elif (( s >= 86400 )); then echo "$(( s / 86400 ))d"; elif (( s >= 3600 )); then echo "$(( s / 3600 ))h"; else echo "$(( s / 60 ))m"; fi; }
   815 | _anthropic_ceiling_json() {  # cycle-126 FR-1.1 (SDD D-1.1b): the input bound the `opus` target runs under
   816 |   # {basis: calibrated|observed|probed, value, model, calibrate[, calibrated_at]} or null.
   817 |   # Sources: the catalog entry (yq) and the observed store cheval writes on a
   818 |   # provider context verdict (.run/ceiling-observed.json, or the same
   819 |   # LOA_CHEVAL_CEILING_OBSERVED_PATH redirect cheval honours). Only the two
   820 |   # context classes lower the bound — a 429 row never does (same rule as
   821 |   # loa_cheval.routing.ceiling.observed_for).
   822 |   local cfg="$PROJECT_ROOT/.claude/defaults/model-config.yaml" model eff probed cal store obs=null
   823 |   command -v yq >/dev/null 2>&1 && [[ -f "$cfg" ]] || { echo null; return 0; }
   824 |   model=$(yq eval -r '.aliases.opus // ""' "$cfg" 2>/dev/null); model="${model#anthropic:}"
   825 |   [[ -n "$model" ]] || { echo null; return 0; }
   826 |   eff=$(yq eval -r ".providers.anthropic.models.\"$model\".effective_input_ceiling // \"\"" "$cfg" 2>/dev/null)
~~~~

The change from head to the fix:

~~~~diff
@@ -811,4 +823,11 @@
-  [[ "$bin" == agy ]] && ! _agy_opted_in && { echo ""; return 0; }
+  routes_to_agy "$(_provider_cli_model "$1")" && ! _agy_opted_in && { echo ""; return 0; }
   [[ -n "$bin" ]] && command -v "$bin" >/dev/null 2>&1 && echo "$bin" || echo ""
 }
 _fmt_age_s() { local s="$1"; if [[ ! "$s" =~ ^[0-9]+$ ]]; then echo "-"; elif (( s >= 86400 )); then echo "$(( s / 86400 ))d"; elif (( s >= 3600 )); then echo "$(( s / 3600 ))h"; else echo "$(( s / 60 ))m"; fi; }
+_providers_model_config() {  # the model catalog the ceiling line reads (bats-gated seam: LOA_STATUS_MODEL_CONFIG)
+  if [[ -n "${BATS_TEST_FILENAME:-}${BATS_VERSION:-}" && -n "${LOA_STATUS_MODEL_CONFIG:-}" ]]; then
+    echo "$LOA_STATUS_MODEL_CONFIG"
+  else
+    echo "$PROJECT_ROOT/.claude/defaults/model-config.yaml"
+  fi
+}
~~~~

## H112 — .claude/scripts/loa-status.sh — head lines 821–842

Head context (head/.claude/scripts/loa-status.sh, lines 809–854):

~~~~text
   809 |   local bin=""
   810 |   case "$1" in anthropic) bin=claude ;; openai) bin=codex ;; google) bin=agy ;; esac
   811 |   [[ "$bin" == agy ]] && ! _agy_opted_in && { echo ""; return 0; }
   812 |   [[ -n "$bin" ]] && command -v "$bin" >/dev/null 2>&1 && echo "$bin" || echo ""
   813 | }
   814 | _fmt_age_s() { local s="$1"; if [[ ! "$s" =~ ^[0-9]+$ ]]; then echo "-"; elif (( s >= 86400 )); then echo "$(( s / 86400 ))d"; elif (( s >= 3600 )); then echo "$(( s / 3600 ))h"; else echo "$(( s / 60 ))m"; fi; }
   815 | _anthropic_ceiling_json() {  # cycle-126 FR-1.1 (SDD D-1.1b): the input bound the `opus` target runs under
   816 |   # {basis: calibrated|observed|probed, value, model, calibrate[, calibrated_at]} or null.
   817 |   # Sources: the catalog entry (yq) and the observed store cheval writes on a
   818 |   # provider context verdict (.run/ceiling-observed.json, or the same
   819 |   # LOA_CHEVAL_CEILING_OBSERVED_PATH redirect cheval honours). Only the two
   820 |   # context classes lower the bound — a 429 row never does (same rule as
>  821 |   # loa_cheval.routing.ceiling.observed_for).
>  822 |   local cfg="$PROJECT_ROOT/.claude/defaults/model-config.yaml" model eff probed cal store obs=null
>  823 |   command -v yq >/dev/null 2>&1 && [[ -f "$cfg" ]] || { echo null; return 0; }
>  824 |   model=$(yq eval -r '.aliases.opus // ""' "$cfg" 2>/dev/null); model="${model#anthropic:}"
>  825 |   [[ -n "$model" ]] || { echo null; return 0; }
>  826 |   eff=$(yq eval -r ".providers.anthropic.models.\"$model\".effective_input_ceiling // \"\"" "$cfg" 2>/dev/null)
>  827 |   probed=$(yq eval -r ".providers.anthropic.models.\"$model\".probed_ceiling // \"\"" "$cfg" 2>/dev/null)
>  828 |   cal=$(yq eval -r ".providers.anthropic.models.\"$model\".ceiling_calibration.calibrated_at // \"\"" "$cfg" 2>/dev/null)
>  829 |   store="${LOA_CHEVAL_CEILING_OBSERVED_PATH:-$PROJECT_ROOT/.run/ceiling-observed.json}"
>  830 |   if [[ -f "$store" ]]; then
>  831 |     obs=$(jq -r --arg m "$model" '[.entries[]? | select(.provider == "anthropic" and .model == $m
>  832 |             and (.error_class == "CEILING_UNVERIFIED_LIMIT" or .error_class == "PROVIDER_CONTEXT_LIMIT"))
>  833 |             | ([.observed_input_tokens, (if .provider_limit then .provider_limit + 1 else empty end)] | min)] | min // null' "$store" 2>/dev/null)
>  834 |     [[ "$obs" =~ ^[0-9]+$ ]] || obs=null
>  835 |   fi
>  836 |   jq -cn --arg m "$model" --arg eff "$eff" --arg probed "$probed" --arg cal "$cal" --argjson obs "$obs" '
>  837 |     ($eff | if . == "" then null else tonumber end) as $e | ($probed | if . == "" then null else tonumber end) as $p
>  838 |     | (if $cal != "" then {basis: "calibrated", value: $e, calibrated_at: $cal}
>  839 |        elif $obs != null and ($p == null or ($obs - 1) < $p) then {basis: "observed", value: ($obs - 1)}
>  840 |        else {basis: "probed", value: ($p // $e)} end)
>  841 |     + {model: $m, observed: (if $obs == null then null else $obs - 1 end),
>  842 |        calibrate: ("python3 tools/ceiling-probe-live.py --model " + $m + " --write-catalog")}' 2>/dev/null || echo null
   843 | }
   844 | get_providers_json() {
   845 |   local snap provs p
   846 |   snap=$(_providers_snapshot)
   847 |   provs=$(printf '%s' "$snap" | jq -r '.buckets | keys[]' 2>/dev/null; printf 'anthropic\nopenai\ngoogle\n')
   848 |   local out='{}'
   849 |   for p in $(printf '%s\n' $provs | sort -u); do
   850 |     out=$(printf '%s' "$out" | jq -c --arg p "$p" --arg key "$(_provider_key_present "$p")" --arg hop "$(_provider_hop "$p")" \
   851 |       --arg note "$(_provider_hop_note "$p")" \
   852 |       --argjson buckets "$(printf '%s' "$snap" | jq -c --arg p "$p" '.buckets[$p] // {}')" \
   853 |       '.[$p] = ({credential:$key, cli_hop:(if $hop == "" then null else $hop end), breakers:$buckets}
   854 |                 + (if $note == "" then {} else {cli_hop_note:$note} end))')
~~~~

The change from head to the fix:

~~~~diff
@@ -821,22 +840,41 @@
-  # loa_cheval.routing.ceiling.observed_for).
-  local cfg="$PROJECT_ROOT/.claude/defaults/model-config.yaml" model eff probed cal store obs=null
+  # loa_cheval.routing.ceiling.observed_for). cycle-127 r251-1: a calibration
+  # measured on a FOREIGN transport (ceiling_calibration.transport present and
+  # not api/http — same rule as routing.ceiling.is_foreign_transport_calibration)
+  # is tightened by an observation below it: basis observed, calibrated true,
+  # calibrated_value / calibration_transport / reprobe_suggested carried.
+  local cfg model eff probed cal transport cw store obs=null
+  cfg=$(_providers_model_config)
   command -v yq >/dev/null 2>&1 && [[ -f "$cfg" ]] || { echo null; return 0; }
   model=$(yq eval -r '.aliases.opus // ""' "$cfg" 2>/dev/null); model="${model#anthropic:}"
   [[ -n "$model" ]] || { echo null; return 0; }
-  eff=$(yq eval -r ".providers.anthropic.models.\"$model\".effective_input_ceiling // \"\"" "$cfg" 2>/dev/null)
-  probed=$(yq eval -r ".providers.anthropic.models.\"$model\".probed_ceiling // \"\"" "$cfg" 2>/dev/null)
-  cal=$(yq eval -r ".providers.anthropic.models.\"$model\".ceiling_calibration.calibrated_at // \"\"" "$cfg" 2>/dev/null)
+  # (r251-4 S8, audit n11: the model reaches yq as a VALUE through strenv — never spliced into the expression text)
+  eff=$(M="$model" yq eval -r '.providers.anthropic.models[strenv(M)].effective_input_ceiling // ""' "$cfg" 2>/dev/null)
+  probed=$(M="$model" yq eval -r '.providers.anthropic.models[strenv(M)].probed_ceiling // ""' "$cfg" 2>/dev/null)
+  cal=$(M="$model" yq eval -r '.providers.anthropic.models[strenv(M)].ceiling_calibration.calibrated_at // ""' "$cfg" 2>/dev/null)
+  transport=$(M="$model" yq eval -r '.providers.anthropic.models[strenv(M)].ceiling_calibration.transport // ""' "$cfg" 2>/dev/null)
+  cw=$(M="$model" yq eval -r '.providers.anthropic.models[strenv(M)].context_window // ""' "$cfg" 2>/dev/null)
+  [[ "$cw" =~ ^[0-9]+$ ]] || cw=0
   store="${LOA_CHEVAL_CEILING_OBSERVED_PATH:-$PROJECT_ROOT/.run/ceiling-observed.json}"
   if [[ -f "$store" ]]; then
-    obs=$(jq -r --arg m "$model" '[.entries[]? | select(.provider == "anthropic" and .model == $m
+    # (r251-4 S7 parity with routing.ceiling.observed_for: with a known window, a candidate outside
+    # [0.1 × context_window, context_window] is not a verdict this route acts on)
+    obs=$(jq -r --arg m "$model" --argjson cw "$cw" '[.entries[]? | select(.provider == "anthropic" and .model == $m
             and (.error_class == "CEILING_UNVERIFIED_LIMIT" or .error_class == "PROVIDER_CONTEXT_LIMIT"))
-            | ([.observed_input_tokens, (if .provider_limit then .provider_limit + 1 else empty end)] | min)] | min // null' "$store" 2>/dev/null)
+            | (.observed_input_tokens, (if .provider_limit then .provider_limit + 1 else empty end))
+            | select(type == "number" and . > 0 and ($cw == 0 or (. >= 0.1 * $cw and . <= $cw)))] | min // null' "$store" 2>/dev/null)
     [[ "$obs" =~ ^[0-9]+$ ]] || obs=null
   fi
-  jq -cn --arg m "$model" --arg eff "$eff" --arg probed "$probed" --arg cal "$cal" --argjson obs "$obs" '
+  jq -cn --arg m "$model" --arg eff "$eff" --arg probed "$probed" --arg cal "$cal" --arg tr "$transport" --argjson obs "$obs" '
     ($eff | if . == "" then null else tonumber end) as $e | ($probed | if . == "" then null else tonumber end) as $p
-    | (if $cal != "" then {basis: "calibrated", value: $e, calibrated_at: $cal}
+    | ($tr | gsub("^\\s+|\\s+$"; "")) as $t
+    | ($cal != "" and $t != "" and (($t | ascii_downcase) as $l | ($l != "api" and $l != "http"))) as $foreign
+    | (if $cal != "" and $foreign and $obs != null and $e != null and ($obs - 1) < $e
+         then {basis: "observed", value: ($obs - 1), calibrated: true, calibrated_value: $e, calibrated_at: $cal,
+               calibration_transport: $t, reprobe_suggested: true}
+       elif $cal != "" then {basis: "calibrated", value: $e, calibrated_at: $cal}
+           + (if $t != "" then {calibration_transport: $t} else {} end)
        elif $obs != null and ($p == null or ($obs - 1) < $p) then {basis: "observed", value: ($obs - 1)}
        else {basis: "probed", value: ($p // $e)} end)
     + {model: $m, observed: (if $obs == null then null else $obs - 1 end),
-       calibrate: ("python3 tools/ceiling-probe-live.py --model " + $m + " --write-catalog")}' 2>/dev/null || echo null
+       calibrate: ("python3 tools/ceiling-probe-live.py --model "
+                   + (if ($m | test("^[A-Za-z0-9._:@+/-]+$")) then $m else ($m | @sh) end) + " --write-catalog")}' 2>/dev/null || echo null
~~~~

## H113 — .claude/scripts/loa-status.sh — insertion after head line 860

Head context (head/.claude/scripts/loa-status.sh, lines 849–872):

~~~~text
   849 |   for p in $(printf '%s\n' $provs | sort -u); do
   850 |     out=$(printf '%s' "$out" | jq -c --arg p "$p" --arg key "$(_provider_key_present "$p")" --arg hop "$(_provider_hop "$p")" \
   851 |       --arg note "$(_provider_hop_note "$p")" \
   852 |       --argjson buckets "$(printf '%s' "$snap" | jq -c --arg p "$p" '.buckets[$p] // {}')" \
   853 |       '.[$p] = ({credential:$key, cli_hop:(if $hop == "" then null else $hop end), breakers:$buckets}
   854 |                 + (if $note == "" then {} else {cli_hop_note:$note} end))')
   855 |   done
   856 |   out=$(printf '%s' "$out" | jq -c --argjson c "$(_anthropic_ceiling_json)" 'if has("anthropic") then .anthropic.ceiling = $c else . end')
   857 |   printf '%s' "$out" | jq -c --argjson rt "$(printf '%s' "$snap" | jq '.reset_timeout_seconds // 60')" '{reset_timeout_seconds:$rt, providers:.}'
   858 | }
   859 | display_providers_section() {
   860 |   local pj p key hop line auth st age due
   861 |   pj=$(get_providers_json)
   862 |   echo -e "${BOLD}Providers${NC}"
   863 |   while IFS= read -r p; do
   864 |     [[ -n "$p" ]] || continue
   865 |     key=$(printf '%s' "$pj" | jq -r --arg p "$p" '.providers[$p].credential'); hop=$(printf '%s' "$pj" | jq -r --arg p "$p" '.providers[$p].cli_hop_note // .providers[$p].cli_hop // "-"')
   866 |     line=$(printf '  %-10s key %-20s hop %-7s' "$p" "$key" "$hop")
   867 |     local buckets; buckets=$(printf '%s' "$pj" | jq -r --arg p "$p" '.providers[$p].breakers | to_entries[] | "\(.key) \(.value.state) \(.value.age_s // "-") \(.value.probe_due_in_s // "-")"')
   868 |     if [[ -z "$buckets" ]]; then line+=" no breaker state"; else
   869 |       while read -r auth st age due; do
   870 |         [[ -n "$auth" ]] || continue
   871 |         if [[ "$st" == "OPEN" ]]; then
   872 |           if [[ "$due" == "0" ]]; then line+=" · $auth OPEN $(_fmt_age_s "$age") (probe overdue → HALF_OPEN on next call)"; else line+=" · $auth OPEN $(_fmt_age_s "$age") (probe due in ${due}s)"; fi
~~~~

The change from head to the fix:

~~~~diff
@@ -860,0 +899 @@
+  agy_gate_warn_once "$(_providers_config_file)"   # (cycle-127 r251-1 G12/G18: once, on stderr)
~~~~

## H114 — .claude/scripts/loa-status.sh — insertion after head line 880

Head context (head/.claude/scripts/loa-status.sh, lines 869–892):

~~~~text
   869 |       while read -r auth st age due; do
   870 |         [[ -n "$auth" ]] || continue
   871 |         if [[ "$st" == "OPEN" ]]; then
   872 |           if [[ "$due" == "0" ]]; then line+=" · $auth OPEN $(_fmt_age_s "$age") (probe overdue → HALF_OPEN on next call)"; else line+=" · $auth OPEN $(_fmt_age_s "$age") (probe due in ${due}s)"; fi
   873 |         else line+=" · $auth $st"; fi
   874 |       done <<<"$buckets"
   875 |     fi
   876 |     echo "$line"
   877 |     if [[ "$p" == "anthropic" ]]; then
   878 |       # cycle-126 FR-1.1: the input bound the `opus` target runs under, and how to tighten it.
   879 |       local cl; cl=$(printf '%s' "$pj" | jq -r '.providers.anthropic.ceiling // empty | if .basis == "calibrated"
   880 |         then "  ceiling: calibrated \(.value) (\(.model), calibrated \(.calibrated_at))"
   881 |         else "  ceiling: \(.basis) \(.value) (\(.model);\(if .observed != null and .basis != "observed" then " observed \(.observed) under the opt-in;" else "" end) calibrate: \(.calibrate))" end')
   882 |       [[ -n "$cl" ]] && echo "$cl"
   883 |     fi
   884 |   done < <(printf '%s' "$pj" | jq -r '.providers | keys[]')
   885 |   echo "  reset: cheval --reset-breaker <provider>[:<auth_type>] · list: python3 -m loa_cheval.routing.breaker_cli --list"
   886 |   return 0
   887 | }
   888 | 
   889 | # cycle-126 FR-3.1 (SDD D-3.1): the context class this session runs under, as the
   890 | # SessionStart hook recorded it in .run/context-class (`--show` never rewrites it).
   891 | display_context_line() {
   892 |   local hook="${SCRIPT_DIR}/../hooks/session-start/loa-context-class.sh" line
~~~~

The change from head to the fix:

~~~~diff
@@ -880,0 +920,2 @@
+        elif .calibrated == true and .basis == "observed"
+        then "  ceiling: calibrated \(.calibrated_value) (\(.calibration_transport)); observed \(.value) below on this route, reprobe suggested (\(.model), calibrated \(.calibrated_at); calibrate: \(.calibrate))"
~~~~

## H115 — .claude/scripts/run-preflight.sh — head line 38

Head context (head/.claude/scripts/run-preflight.sh, lines 26–50):

~~~~text
    26 | #   P6 run state — .run/state.json, sprint-plan-state.json, simstim-state.json:
    27 | #      RUNNING fresh = "already in progress" (fail); RUNNING/INTERRUPTED older
    28 | #      than 12 h or HALTED = fail with the resume command; JACKED_OUT/absent pass.
    29 | #      --resume inverts P6: a resumable state passes, nothing to resume fails.
    30 | #   P7 beads — beads-health.sh --quick --json: HEALTHY pass, DEGRADED warn,
    31 | #      else fail unless beads.autonomous.requires_beads=false or
    32 | #      LOA_BEADS_AUTONOMOUS_OVERRIDE=true (then warn).
    33 | #   P8 branch — run-mode-ice.sh validate (pass-through).
    34 | #
    35 | # Output: `[PASS|WARN|FAIL] Pn <name>: <detail> → fix: <fix>` per predicate, then
    36 | # `run-preflight (<mode>): N pass, N warn, N fail`. --json: one object
    37 | # {mode, ok, pass, warn, fail, checks:[{id,name,status,detail,fix}], ts}.
>   38 | # Exit: 0 no FAIL · 1 any FAIL · 2 usage. Reads settings, env and state only;
    39 | # writes nothing; no network; never prints a credential value.
    40 | # Test seam (bats-gated): LOA_PREFLIGHT_HELPERS_DIR overrides the directory of
    41 | # the composed helper scripts so fixtures can drive P2/P7/P8.
    42 | # =============================================================================
    43 | set -uo pipefail
    44 | export LC_ALL=C
    45 | 
    46 | SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    47 | MODE="interactive"; RESUME=0; JSON=0; ROOT=""
    48 | usage() { sed -n '3,/^# Output:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
    49 | while [[ $# -gt 0 ]]; do
    50 |   case "$1" in
~~~~

The change from head to the fix:

~~~~diff
@@ -38 +38 @@
-# Exit: 0 no FAIL · 1 any FAIL · 2 usage. Reads settings, env and state only;
+# Exit: 0 no FAIL · 1 any FAIL · 2 usage, or the agy-gate lib missing. Reads settings, env and state only;
~~~~

## H116 — .claude/scripts/run-preflight.sh — insertion after head line 46

Head context (head/.claude/scripts/run-preflight.sh, lines 35–58):

~~~~text
    35 | # Output: `[PASS|WARN|FAIL] Pn <name>: <detail> → fix: <fix>` per predicate, then
    36 | # `run-preflight (<mode>): N pass, N warn, N fail`. --json: one object
    37 | # {mode, ok, pass, warn, fail, checks:[{id,name,status,detail,fix}], ts}.
    38 | # Exit: 0 no FAIL · 1 any FAIL · 2 usage. Reads settings, env and state only;
    39 | # writes nothing; no network; never prints a credential value.
    40 | # Test seam (bats-gated): LOA_PREFLIGHT_HELPERS_DIR overrides the directory of
    41 | # the composed helper scripts so fixtures can drive P2/P7/P8.
    42 | # =============================================================================
    43 | set -uo pipefail
    44 | export LC_ALL=C
    45 | 
    46 | SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    47 | MODE="interactive"; RESUME=0; JSON=0; ROOT=""
    48 | usage() { sed -n '3,/^# Output:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
    49 | while [[ $# -gt 0 ]]; do
    50 |   case "$1" in
    51 |     --unattended) MODE="unattended"; shift ;;
    52 |     --resume) RESUME=1; shift ;;
    53 |     --json) JSON=1; shift ;;
    54 |     --root) [[ $# -ge 2 && -d "${2:-}" ]] || usage; ROOT="$(cd "$2" && pwd)"; shift 2 ;;
    55 |     -h|--help) usage ;;
    56 |     *) usage ;;
    57 |   esac
    58 | done
~~~~

The change from head to the fix:

~~~~diff
@@ -46,0 +47,7 @@
+# cycle-127 FR-1 (SDD D-1.5; review r251-1 G2): the one agy route predicate — agy_opted_in, agy_headless_mode, routes_to_agy
+# (review r251-4 S4, audit n15: fail closed — without the predicate P3 would report an agy-routed voice as usable)
+# shellcheck source=lib/agy-gate-lib.sh
+if ! source "$SCRIPT_DIR/lib/agy-gate-lib.sh" || ! declare -F routes_to_agy >/dev/null 2>&1; then
+  echo "run-preflight: cannot load $SCRIPT_DIR/lib/agy-gate-lib.sh (the agy route predicate) — reinstall the framework (/update-loa); refusing to judge the voices without it" >&2
+  exit 2
+fi
~~~~

## H117 — .claude/scripts/run-preflight.sh — head lines 153–159

Head context (head/.claude/scripts/run-preflight.sh, lines 141–171):

~~~~text
   141 |   local v f val
   142 |   for v in "${vars[@]}"; do [[ -n "${!v:-}" ]] && return 0; done
   143 |   for f in "$ROOT/.env.local" "$ROOT/.env"; do
   144 |     [[ -f "$f" ]] || continue
   145 |     for v in "${vars[@]}"; do
   146 |       # presence = a non-empty value after stripping one layer of quotes; the value itself never leaves this function
   147 |       val=$(grep -E "^[[:space:]]*(export[[:space:]]+)?${v}=" "$f" 2>/dev/null | tail -1 | sed -e 's/^[^=]*=//' -e "s/^[\"']//" -e "s/[\"'][[:space:]]*$//" -e 's/[[:space:]]*#.*$//')
   148 |       [[ -n "$val" ]] && return 0
   149 |     done
   150 |   done
   151 |   return 1
   152 | }
>  153 | cli_for() { case "$1" in claude-headless) echo claude ;; codex-headless) echo codex ;; gemini-headless) echo agy ;; *) echo "" ;; esac; }
>  154 | agy_opted_in() {  # cycle-127 FR-1: true only for a YAML boolean true at hounfour.headless.agy_opt_in (no env override)
>  155 |   local v=""
>  156 |   have_yq && [[ -f "$ROOT/.loa.config.yaml" ]] || return 1
>  157 |   if [[ "$YQ_FLAVOUR" == "go" ]]; then v=$(yq eval '.hounfour.headless.agy_opt_in | (tag == "!!bool" and . == true)' "$ROOT/.loa.config.yaml" 2>/dev/null) || v=""
>  158 |   else v=$(yq '.hounfour.headless.agy_opt_in == true' "$ROOT/.loa.config.yaml" 2>/dev/null) || v=""; fi
>  159 |   [[ "$v" == "true" ]]
   160 | }
   161 | provider_of() {  # $1 = model id → openai|anthropic|google|""
   162 |   local id="$1" alias="" cat=""
   163 |   # Only catalog-shaped ids reach the yq expression (config text is operator-owned but is still input).
   164 |   [[ "$id" =~ ^[A-Za-z0-9][A-Za-z0-9._:/-]*$ ]] || { echo ""; return; }
   165 |   if [[ -f "$ROOT/.claude/defaults/model-config.yaml" ]]; then cat="$ROOT/.claude/defaults/model-config.yaml"
   166 |   elif [[ -f "$SCRIPT_DIR/../defaults/model-config.yaml" ]]; then cat="$SCRIPT_DIR/../defaults/model-config.yaml"; fi
   167 |   if have_yq && [[ -n "$cat" ]]; then alias=$(yq_read ".aliases.\"$id\"" "$cat" | head -1); fi
   168 |   [[ "$alias" == *:* ]] && { echo "${alias%%:*}"; return; }
   169 |   case "$id" in
   170 |     openai:*|anthropic:*|google:*) echo "${id%%:*}" ;;
   171 |     gpt*|o[0-9]*|codex*) echo openai ;;
~~~~

The change from head to the fix:

~~~~diff
@@ -153,7 +160,3 @@
-cli_for() { case "$1" in claude-headless) echo claude ;; codex-headless) echo codex ;; gemini-headless) echo agy ;; *) echo "" ;; esac; }
-agy_opted_in() {  # cycle-127 FR-1: true only for a YAML boolean true at hounfour.headless.agy_opt_in (no env override)
-  local v=""
-  have_yq && [[ -f "$ROOT/.loa.config.yaml" ]] || return 1
-  if [[ "$YQ_FLAVOUR" == "go" ]]; then v=$(yq eval '.hounfour.headless.agy_opt_in | (tag == "!!bool" and . == true)' "$ROOT/.loa.config.yaml" 2>/dev/null) || v=""
-  else v=$(yq '.hounfour.headless.agy_opt_in == true' "$ROOT/.loa.config.yaml" 2>/dev/null) || v=""; fi
-  [[ "$v" == "true" ]]
+cli_for() {  # $1 = model id (bare or provider-prefixed) → the CLI binary of a *-headless hop, else ""
+  local m="$1"; case "$m" in anthropic:*|openai:*|google:*) m="${m#*:}" ;; esac
+  case "$m" in claude-headless) echo claude ;; codex-headless) echo codex ;; gemini-headless) echo agy ;; *) echo "" ;; esac
~~~~

## H118 — .claude/scripts/run-preflight.sh — head line 174

Head context (head/.claude/scripts/run-preflight.sh, lines 162–186):

~~~~text
   162 |   local id="$1" alias="" cat=""
   163 |   # Only catalog-shaped ids reach the yq expression (config text is operator-owned but is still input).
   164 |   [[ "$id" =~ ^[A-Za-z0-9][A-Za-z0-9._:/-]*$ ]] || { echo ""; return; }
   165 |   if [[ -f "$ROOT/.claude/defaults/model-config.yaml" ]]; then cat="$ROOT/.claude/defaults/model-config.yaml"
   166 |   elif [[ -f "$SCRIPT_DIR/../defaults/model-config.yaml" ]]; then cat="$SCRIPT_DIR/../defaults/model-config.yaml"; fi
   167 |   if have_yq && [[ -n "$cat" ]]; then alias=$(yq_read ".aliases.\"$id\"" "$cat" | head -1); fi
   168 |   [[ "$alias" == *:* ]] && { echo "${alias%%:*}"; return; }
   169 |   case "$id" in
   170 |     openai:*|anthropic:*|google:*) echo "${id%%:*}" ;;
   171 |     gpt*|o[0-9]*|codex*) echo openai ;;
   172 |     claude*) echo anthropic ;;
   173 |     gemini*) echo google ;;
>  174 |     *) echo "" ;;
   175 |   esac
   176 | }
   177 | declare -A USABLE_PROVIDERS=()   # providers that have a usable voice in any stage
   178 | declare -A STAGE_ONLY=()         # stage → the single usable provider (for P4)
   179 | p3_status="PASS"; p3_detail=""; p3_fail_stages=""; p3_warn=""; p3_usable=""; p3_optin=""
   180 | if ! have_yq || [[ ! -f "$ROOT/.loa.config.yaml" ]]; then
   181 |   p3_status="WARN"; p3_detail="yq or .loa.config.yaml missing: voices unchecked"
   182 | else
   183 |   for stage in code_review security_audit; do
   184 |     en=$(cfg ".flatline_protocol.$stage.enabled"); [[ "$en" == "true" ]] || continue
   185 |     models=$(cfg ".flatline_protocol.$stage.model"); chain=$(cfg ".flatline_protocol.$stage.fallback_chain[]" | tr '\n' ' ')
   186 |     usable=0; missing=""; provs=""; usable_names=""
~~~~

The change from head to the fix:

~~~~diff
@@ -174 +177,3 @@
-    *) echo "" ;;
+    # (review r251-3 R3: a catalog model id without a family prefix — deep-research-pro — resolves through the
+    # generated maps, the same lookup routes_to_agy uses)
+    *) if declare -F agy_catalog_provider >/dev/null; then agy_catalog_provider "$id"; else echo ""; fi ;;
~~~~

## H119 — .claude/scripts/run-preflight.sh — head line 179

Head context (head/.claude/scripts/run-preflight.sh, lines 167–191):

~~~~text
   167 |   if have_yq && [[ -n "$cat" ]]; then alias=$(yq_read ".aliases.\"$id\"" "$cat" | head -1); fi
   168 |   [[ "$alias" == *:* ]] && { echo "${alias%%:*}"; return; }
   169 |   case "$id" in
   170 |     openai:*|anthropic:*|google:*) echo "${id%%:*}" ;;
   171 |     gpt*|o[0-9]*|codex*) echo openai ;;
   172 |     claude*) echo anthropic ;;
   173 |     gemini*) echo google ;;
   174 |     *) echo "" ;;
   175 |   esac
   176 | }
   177 | declare -A USABLE_PROVIDERS=()   # providers that have a usable voice in any stage
   178 | declare -A STAGE_ONLY=()         # stage → the single usable provider (for P4)
>  179 | p3_status="PASS"; p3_detail=""; p3_fail_stages=""; p3_warn=""; p3_usable=""; p3_optin=""
   180 | if ! have_yq || [[ ! -f "$ROOT/.loa.config.yaml" ]]; then
   181 |   p3_status="WARN"; p3_detail="yq or .loa.config.yaml missing: voices unchecked"
   182 | else
   183 |   for stage in code_review security_audit; do
   184 |     en=$(cfg ".flatline_protocol.$stage.enabled"); [[ "$en" == "true" ]] || continue
   185 |     models=$(cfg ".flatline_protocol.$stage.model"); chain=$(cfg ".flatline_protocol.$stage.fallback_chain[]" | tr '\n' ' ')
   186 |     usable=0; missing=""; provs=""; usable_names=""
   187 |     for m in $models $chain; do
   188 |       prov=$(provider_of "$m"); cli=$(cli_for "$m"); ok=0
   189 |       # (an agy hop whose opt-in is off is not a voice on any host — never usable, never "missing a CLI")
   190 |       if [[ "$cli" == agy ]] && ! agy_opted_in; then [[ " $p3_optin " == *" $m(agy: opt-in (disabled; hounfour.headless.agy_opt_in)) "* ]] || p3_optin+="$m(agy: opt-in (disabled; hounfour.headless.agy_opt_in)) "; continue; fi
   191 |       if [[ -n "$cli" ]] && command -v "$cli" >/dev/null 2>&1; then ok=1
~~~~

The change from head to the fix:

~~~~diff
@@ -179 +184,4 @@
-p3_status="PASS"; p3_detail=""; p3_fail_stages=""; p3_warn=""; p3_usable=""; p3_optin=""
+p3_status="PASS"; p3_detail=""; p3_fail_stages=""; p3_warn=""; p3_usable=""; p3_optin=""; p3_optin_stages=""
+p3_mode=$(agy_headless_mode "$ROOT/.loa.config.yaml")   # (env LOA_HEADLESS_MODE wins, as in cheval)
+p3_agy_on=0; agy_opted_in "$ROOT/.loa.config.yaml" && p3_agy_on=1
+(( JSON )) || agy_gate_warn_once "$ROOT/.loa.config.yaml"   # (r251-1 G12/G18: said once, on stderr; --json stays quiet)
~~~~

## H120 — .claude/scripts/run-preflight.sh — head lines 186–190

Head context (head/.claude/scripts/run-preflight.sh, lines 174–202):

~~~~text
   174 |     *) echo "" ;;
   175 |   esac
   176 | }
   177 | declare -A USABLE_PROVIDERS=()   # providers that have a usable voice in any stage
   178 | declare -A STAGE_ONLY=()         # stage → the single usable provider (for P4)
   179 | p3_status="PASS"; p3_detail=""; p3_fail_stages=""; p3_warn=""; p3_usable=""; p3_optin=""
   180 | if ! have_yq || [[ ! -f "$ROOT/.loa.config.yaml" ]]; then
   181 |   p3_status="WARN"; p3_detail="yq or .loa.config.yaml missing: voices unchecked"
   182 | else
   183 |   for stage in code_review security_audit; do
   184 |     en=$(cfg ".flatline_protocol.$stage.enabled"); [[ "$en" == "true" ]] || continue
   185 |     models=$(cfg ".flatline_protocol.$stage.model"); chain=$(cfg ".flatline_protocol.$stage.fallback_chain[]" | tr '\n' ' ')
>  186 |     usable=0; missing=""; provs=""; usable_names=""
>  187 |     for m in $models $chain; do
>  188 |       prov=$(provider_of "$m"); cli=$(cli_for "$m"); ok=0
>  189 |       # (an agy hop whose opt-in is off is not a voice on any host — never usable, never "missing a CLI")
>  190 |       if [[ "$cli" == agy ]] && ! agy_opted_in; then [[ " $p3_optin " == *" $m(agy: opt-in (disabled; hounfour.headless.agy_opt_in)) "* ]] || p3_optin+="$m(agy: opt-in (disabled; hounfour.headless.agy_opt_in)) "; continue; fi
   191 |       if [[ -n "$cli" ]] && command -v "$cli" >/dev/null 2>&1; then ok=1
   192 |       elif [[ -z "$cli" && -n "$prov" ]] && cred_present "$prov"; then ok=1; fi
   193 |       if (( ok )); then usable=$((usable + 1)); USABLE_PROVIDERS["${prov:-$m}"]=1; provs+="${prov:-$m} "; usable_names+="$m${cli:+(cli $cli)} "
   194 |       else missing+="$m${cli:+(cli $cli)} "; fi
   195 |     done
   196 |     provs_u=$(printf '%s\n' $provs | sort -u | tr '\n' ' ')
   197 |     if (( usable == 0 )); then p3_fail_stages+="$stage "
   198 |     else
   199 |       [[ $(printf '%s\n' $provs | sort -u | wc -l) -eq 1 ]] && STAGE_ONLY["$stage"]="${provs_u% }"
   200 |       p3_usable+="$stage usable: ${usable_names% }; "
   201 |       [[ -n "$missing" ]] && p3_warn+="$stage missing: ${missing% }; "
   202 |     fi
~~~~

The change from head to the fix:

~~~~diff
@@ -186,5 +194,12 @@
-    usable=0; missing=""; provs=""; usable_names=""
+    usable=0; missing=""; provs=""; usable_names=""; n_voices=0; n_gated=0
     for m in $models $chain; do
-      prov=$(provider_of "$m"); cli=$(cli_for "$m"); ok=0
-      # (an agy hop whose opt-in is off is not a voice on any host — never usable, never "missing a CLI")
-      if [[ "$cli" == agy ]] && ! agy_opted_in; then [[ " $p3_optin " == *" $m(agy: opt-in (disabled; hounfour.headless.agy_opt_in)) "* ]] || p3_optin+="$m(agy: opt-in (disabled; hounfour.headless.agy_opt_in)) "; continue; fi
+      prov=$(provider_of "$m"); cli=$(cli_for "$m"); ok=0; n_voices=$((n_voices + 1))
+      # (an agy-routed voice — the gemini-headless hop, or a Google model under cli-only — whose opt-in is off is not a
+      # voice on any host: never usable on its credential, never "missing a CLI"; review r251-1 G2: the shared predicate)
+      if (( ! p3_agy_on )) && routes_to_agy "$m" "$p3_mode" "$ROOT/.loa.config.yaml"; then   # (r251-4: project aliases resolved)
+        n_gated=$((n_gated + 1))
+        [[ " $p3_optin " == *" $m($AGY_OPT_IN_NOTE) "* ]] || p3_optin+="$m($AGY_OPT_IN_NOTE) "; continue
+      fi
+      # (review r251-2 K3: opted in, an agy-routed voice — a Google model under cli-only, any gemini-headless form — runs
+      # on the agy CLI, so the agy binary decides its usability, never the Google credential)
+      routes_to_agy "$m" "$p3_mode" "$ROOT/.loa.config.yaml" && cli=agy
~~~~

## H121 — .claude/scripts/run-preflight.sh — head line 197

Head context (head/.claude/scripts/run-preflight.sh, lines 185–209):

~~~~text
   185 |     models=$(cfg ".flatline_protocol.$stage.model"); chain=$(cfg ".flatline_protocol.$stage.fallback_chain[]" | tr '\n' ' ')
   186 |     usable=0; missing=""; provs=""; usable_names=""
   187 |     for m in $models $chain; do
   188 |       prov=$(provider_of "$m"); cli=$(cli_for "$m"); ok=0
   189 |       # (an agy hop whose opt-in is off is not a voice on any host — never usable, never "missing a CLI")
   190 |       if [[ "$cli" == agy ]] && ! agy_opted_in; then [[ " $p3_optin " == *" $m(agy: opt-in (disabled; hounfour.headless.agy_opt_in)) "* ]] || p3_optin+="$m(agy: opt-in (disabled; hounfour.headless.agy_opt_in)) "; continue; fi
   191 |       if [[ -n "$cli" ]] && command -v "$cli" >/dev/null 2>&1; then ok=1
   192 |       elif [[ -z "$cli" && -n "$prov" ]] && cred_present "$prov"; then ok=1; fi
   193 |       if (( ok )); then usable=$((usable + 1)); USABLE_PROVIDERS["${prov:-$m}"]=1; provs+="${prov:-$m} "; usable_names+="$m${cli:+(cli $cli)} "
   194 |       else missing+="$m${cli:+(cli $cli)} "; fi
   195 |     done
   196 |     provs_u=$(printf '%s\n' $provs | sort -u | tr '\n' ' ')
>  197 |     if (( usable == 0 )); then p3_fail_stages+="$stage "
   198 |     else
   199 |       [[ $(printf '%s\n' $provs | sort -u | wc -l) -eq 1 ]] && STAGE_ONLY["$stage"]="${provs_u% }"
   200 |       p3_usable+="$stage usable: ${usable_names% }; "
   201 |       [[ -n "$missing" ]] && p3_warn+="$stage missing: ${missing% }; "
   202 |     fi
   203 |   done
   204 |   if [[ -n "$p3_fail_stages" ]]; then p3_status="FAIL"; p3_detail="no usable voice for ${p3_fail_stages% }: no credential present and no CLI hop on PATH"
   205 |   elif [[ -n "$p3_warn" ]]; then p3_status="WARN"; p3_detail="${p3_usable}${p3_warn%; }"
   206 |   else p3_detail="every configured voice has a credential or CLI hop (${p3_usable%; })"; fi
   207 |   # (cycle-127 FR-1: a hop not planned by its opt-in is said, never counted as a missing voice)
   208 |   [[ -z "$p3_optin" ]] || p3_detail+="; not planned: ${p3_optin% }"
   209 | fi
~~~~

The change from head to the fix:

~~~~diff
@@ -197 +212,3 @@
-    if (( usable == 0 )); then p3_fail_stages+="$stage "
+    if (( usable == 0 )); then
+      # (review r251-1 G8: every configured voice gated off by the opt-in is said as such — still FAIL, no voice runs)
+      if (( n_voices > 0 && n_gated == n_voices )); then p3_optin_stages+="$stage "; else p3_fail_stages+="$stage "; fi
~~~~

## H122 — .claude/scripts/run-preflight.sh — head line 204

Head context (head/.claude/scripts/run-preflight.sh, lines 192–216):

~~~~text
   192 |       elif [[ -z "$cli" && -n "$prov" ]] && cred_present "$prov"; then ok=1; fi
   193 |       if (( ok )); then usable=$((usable + 1)); USABLE_PROVIDERS["${prov:-$m}"]=1; provs+="${prov:-$m} "; usable_names+="$m${cli:+(cli $cli)} "
   194 |       else missing+="$m${cli:+(cli $cli)} "; fi
   195 |     done
   196 |     provs_u=$(printf '%s\n' $provs | sort -u | tr '\n' ' ')
   197 |     if (( usable == 0 )); then p3_fail_stages+="$stage "
   198 |     else
   199 |       [[ $(printf '%s\n' $provs | sort -u | wc -l) -eq 1 ]] && STAGE_ONLY["$stage"]="${provs_u% }"
   200 |       p3_usable+="$stage usable: ${usable_names% }; "
   201 |       [[ -n "$missing" ]] && p3_warn+="$stage missing: ${missing% }; "
   202 |     fi
   203 |   done
>  204 |   if [[ -n "$p3_fail_stages" ]]; then p3_status="FAIL"; p3_detail="no usable voice for ${p3_fail_stages% }: no credential present and no CLI hop on PATH"
   205 |   elif [[ -n "$p3_warn" ]]; then p3_status="WARN"; p3_detail="${p3_usable}${p3_warn%; }"
   206 |   else p3_detail="every configured voice has a credential or CLI hop (${p3_usable%; })"; fi
   207 |   # (cycle-127 FR-1: a hop not planned by its opt-in is said, never counted as a missing voice)
   208 |   [[ -z "$p3_optin" ]] || p3_detail+="; not planned: ${p3_optin% }"
   209 | fi
   210 | record P3 voices "$p3_status" "$p3_detail" "export OPENAI_API_KEY / ANTHROPIC_API_KEY / GOOGLE_API_KEY (or put them in .env.local), or install a CLI hop (claude, codex, agy) named in the stage's fallback_chain"
   211 | 
   212 | # --- P4 breakers ----------------------------------------------------------------
   213 | p4_status="PASS"; p4_detail="no OPEN provider breaker"; p4_open=""; p4_fail=""
   214 | for f in "$ROOT"/.run/circuit-breaker-*.json; do
   215 |   [[ -f "$f" && ! -L "$f" ]] || continue
   216 |   b=$(basename "$f" .json); b="${b#circuit-breaker-}"; prov="${b%%-*}"; auth="${b#*-}"; [[ "$auth" == "$b" ]] && auth="legacy"
~~~~

The change from head to the fix:

~~~~diff
@@ -204 +221,4 @@
-  if [[ -n "$p3_fail_stages" ]]; then p3_status="FAIL"; p3_detail="no usable voice for ${p3_fail_stages% }: no credential present and no CLI hop on PATH"
+  if [[ -n "$p3_fail_stages$p3_optin_stages" ]]; then
+    p3_status="FAIL"
+    [[ -z "$p3_fail_stages" ]] || p3_detail="no usable voice for ${p3_fail_stages% }: no credential present and no CLI hop on PATH"
+    [[ -z "$p3_optin_stages" ]] || p3_detail+="${p3_detail:+; }no usable voice for ${p3_optin_stages% }: every configured voice is not planned (the agy route is opt-in: set $AGY_OPT_IN_KEY: true)"
~~~~

## H123 — .claude/skills/bridgebuilder-review/dist/.build-manifest.json — head lines 3–4

Head context (head/.claude/skills/bridgebuilder-review/dist/.build-manifest.json, lines 1–16):

~~~~text
     1 | {
     2 |   "version": "1.0",
>    3 |   "generated_at": "2026-10-07T09:33:28Z",
>    4 |   "source_hash": "acae22d4e85d5326c2345955bfe50c8161f496403c5d07bc3ca6fc1d416d046e",
     5 |   "file_count": 42,
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
-  "generated_at": "2026-10-07T09:33:28Z",
-  "source_hash": "acae22d4e85d5326c2345955bfe50c8161f496403c5d07bc3ca6fc1d416d046e",
+  "generated_at": "2026-10-07T20:31:07Z",
+  "source_hash": "b7ee6626d8931660b817d67e7fe35c912235070b79392b6c2e6fc18d1c5137cc",
~~~~

## H124 — .claude/skills/bridgebuilder-review/dist/.build-manifest.json — head line 49

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
>   49 |       "sha256": "e1caf5ec5bb6438f13e997e49493269b3a8dd4ae32f3cbb7743b342114bb7ef0"
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
-      "sha256": "e1caf5ec5bb6438f13e997e49493269b3a8dd4ae32f3cbb7743b342114bb7ef0"
+      "sha256": "a0b586a502a0015646aa8d0d6450ce74440a699ef9a2e7769d21f1cf6f846161"
~~~~

## H125 — .claude/skills/bridgebuilder-review/dist/.build-manifest.json — head line 89

Head context (head/.claude/skills/bridgebuilder-review/dist/.build-manifest.json, lines 77–101):

~~~~text
    77 |       "sha256": "3c0b1545ea34d01b624426f4278c2db1df9b5157f6a43e14bb2321bb1e1dee2e"
    78 |     },
    79 |     {
    80 |       "path": ".claude/skills/bridgebuilder-review/resources/core/index.ts",
    81 |       "sha256": "9c87e1c3631d30adfcaee302d52989d6d24e60a8739effbe074bf13b6c9610fa"
    82 |     },
    83 |     {
    84 |       "path": ".claude/skills/bridgebuilder-review/resources/core/lore-loader.ts",
    85 |       "sha256": "1d583fa261198a1877228672383921c5d9fd83ca8c7d93545240607d33bd0493"
    86 |     },
    87 |     {
    88 |       "path": ".claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts",
>   89 |       "sha256": "0c489f789420863a6f144b115ede53c4d0946a40f203201b855835ffcd1bd7d2"
    90 |     },
    91 |     {
    92 |       "path": ".claude/skills/bridgebuilder-review/resources/core/progress.ts",
    93 |       "sha256": "c36a76a459ad2b2365c021d9f581a63685bc61ae4170c9c0593f97b8345afeac"
    94 |     },
    95 |     {
    96 |       "path": ".claude/skills/bridgebuilder-review/resources/core/rating.ts",
    97 |       "sha256": "322cb2bfe26b7c132d6e998520bfbf852b8cf5d6190a847d80c01073795a7dee"
    98 |     },
    99 |     {
   100 |       "path": ".claude/skills/bridgebuilder-review/resources/core/review-verdict.ts",
   101 |       "sha256": "be87841aa516aae732397ab2f1c469e3ca78c206bf4d04206641078bc92475ea"
~~~~

The change from head to the fix:

~~~~diff
@@ -89 +89 @@
-      "sha256": "0c489f789420863a6f144b115ede53c4d0946a40f203201b855835ffcd1bd7d2"
+      "sha256": "752c6c67d0e690cd565e99c027745e81216327476707540a745691979eb2dfbe"
~~~~

## H126 — .claude/skills/bridgebuilder-review/dist/.build-manifest.json — head line 101

Head context (head/.claude/skills/bridgebuilder-review/dist/.build-manifest.json, lines 89–113):

~~~~text
    89 |       "sha256": "0c489f789420863a6f144b115ede53c4d0946a40f203201b855835ffcd1bd7d2"
    90 |     },
    91 |     {
    92 |       "path": ".claude/skills/bridgebuilder-review/resources/core/progress.ts",
    93 |       "sha256": "c36a76a459ad2b2365c021d9f581a63685bc61ae4170c9c0593f97b8345afeac"
    94 |     },
    95 |     {
    96 |       "path": ".claude/skills/bridgebuilder-review/resources/core/rating.ts",
    97 |       "sha256": "322cb2bfe26b7c132d6e998520bfbf852b8cf5d6190a847d80c01073795a7dee"
    98 |     },
    99 |     {
   100 |       "path": ".claude/skills/bridgebuilder-review/resources/core/review-verdict.ts",
>  101 |       "sha256": "be87841aa516aae732397ab2f1c469e3ca78c206bf4d04206641078bc92475ea"
   102 |     },
   103 |     {
   104 |       "path": ".claude/skills/bridgebuilder-review/resources/core/reviewer.ts",
   105 |       "sha256": "89b94a402f6591836537b0b23c807c0400ff74177bc56ff54435238644d2e01f"
   106 |     },
   107 |     {
   108 |       "path": ".claude/skills/bridgebuilder-review/resources/core/schemas.ts",
   109 |       "sha256": "ad1503e6fc1031e2b137b5e2866cf6b13fc27dd6045cc64422cf3b1f8a3ae048"
   110 |     },
   111 |     {
   112 |       "path": ".claude/skills/bridgebuilder-review/resources/core/scoring.ts",
   113 |       "sha256": "69942be01495aa8f12fe1f9266594bd3bbf42bb87456e4cbd33410a25750d9e0"
~~~~

The change from head to the fix:

~~~~diff
@@ -101 +101 @@
-      "sha256": "be87841aa516aae732397ab2f1c469e3ca78c206bf4d04206641078bc92475ea"
+      "sha256": "819bc7019a60a01564de366ffadb8aa28fe06b2ad906849de773f1af1a44cf4d"
~~~~

## H127 — .claude/skills/bridgebuilder-review/dist/.build-manifest.json — head line 121

Head context (head/.claude/skills/bridgebuilder-review/dist/.build-manifest.json, lines 109–133):

~~~~text
   109 |       "sha256": "ad1503e6fc1031e2b137b5e2866cf6b13fc27dd6045cc64422cf3b1f8a3ae048"
   110 |     },
   111 |     {
   112 |       "path": ".claude/skills/bridgebuilder-review/resources/core/scoring.ts",
   113 |       "sha256": "69942be01495aa8f12fe1f9266594bd3bbf42bb87456e4cbd33410a25750d9e0"
   114 |     },
   115 |     {
   116 |       "path": ".claude/skills/bridgebuilder-review/resources/core/template.ts",
   117 |       "sha256": "9b0163d3aca18196e5701fe27575e5d27249763b42f59ea09680719e978b215f"
   118 |     },
   119 |     {
   120 |       "path": ".claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts",
>  121 |       "sha256": "fe2fb1b03f10232c7c5d52387a679f478be1a5eacc82e32aa0f50f90781f5a33"
   122 |     },
   123 |     {
   124 |       "path": ".claude/skills/bridgebuilder-review/resources/core/truncation.ts",
   125 |       "sha256": "5ed9bd99a13564cc0a65e2a8117e258e557d002b05f31887398fbec22112b249"
   126 |     },
   127 |     {
   128 |       "path": ".claude/skills/bridgebuilder-review/resources/core/types.ts",
   129 |       "sha256": "b2550acecccd39fe9c14583742f19870db0835e543995f1208543f82283318fe"
   130 |     },
   131 |     {
   132 |       "path": ".claude/skills/bridgebuilder-review/resources/lib/endpoint-validator.generated.ts",
   133 |       "sha256": "d77e64398c184401f8fb1b22ac6868f50c301cc50c38c3d658887738acbee25e"
~~~~

The change from head to the fix:

~~~~diff
@@ -121 +121 @@
-      "sha256": "fe2fb1b03f10232c7c5d52387a679f478be1a5eacc82e32aa0f50f90781f5a33"
+      "sha256": "16512a332df1ac467337fd70a34b2904c3576cc4ff55c58d3ece30f9c668de6b"
~~~~

## H128 — .claude/skills/bridgebuilder-review/dist/.build-manifest.json — head line 141

Head context (head/.claude/skills/bridgebuilder-review/dist/.build-manifest.json, lines 129–153):

~~~~text
   129 |       "sha256": "b2550acecccd39fe9c14583742f19870db0835e543995f1208543f82283318fe"
   130 |     },
   131 |     {
   132 |       "path": ".claude/skills/bridgebuilder-review/resources/lib/endpoint-validator.generated.ts",
   133 |       "sha256": "d77e64398c184401f8fb1b22ac6868f50c301cc50c38c3d658887738acbee25e"
   134 |     },
   135 |     {
   136 |       "path": ".claude/skills/bridgebuilder-review/resources/lib/model-resolver.generated.ts",
   137 |       "sha256": "5f32f6e734a27195962bb69de704d6d0b7eb9c24415f4a008800346f4711bb45"
   138 |     },
   139 |     {
   140 |       "path": ".claude/skills/bridgebuilder-review/resources/main.ts",
>  141 |       "sha256": "09ef7aedea7d9fb528bab348641c1b04efe93607d2da2353db68580be7dcb360"
   142 |     },
   143 |     {
   144 |       "path": ".claude/skills/bridgebuilder-review/resources/ports/context-store.ts",
   145 |       "sha256": "f944e87b3e9ace803ef9b75786e0523af0e35aa4f51fe8586a615c931de409d8"
   146 |     },
   147 |     {
   148 |       "path": ".claude/skills/bridgebuilder-review/resources/ports/git-provider.ts",
   149 |       "sha256": "fe1150762a666f6c09beb204218f284d7a1535c7179ab2c9bc1c839419574b1e"
   150 |     },
   151 |     {
   152 |       "path": ".claude/skills/bridgebuilder-review/resources/ports/hasher.ts",
   153 |       "sha256": "4af765b36cc296550e4be7c02c4e00f0a9567c1fbb9916cec3b2c9f801924e12"
~~~~

The change from head to the fix:

~~~~diff
@@ -141 +141 @@
-      "sha256": "09ef7aedea7d9fb528bab348641c1b04efe93607d2da2353db68580be7dcb360"
+      "sha256": "054a9bd84fd8b668f9bf04ff792711b90d86ff7ecaa9ca25009e88b328777785"
~~~~

## H129 — .claude/skills/bridgebuilder-review/dist/config.d.ts — head lines 72–79

Head context (head/.claude/skills/bridgebuilder-review/dist/config.d.ts, lines 60–91):

~~~~text
    60 |  * Load multi-model configuration from .loa.config.yaml using yq CLI (SDD Section 2.7).
    61 |  * Falls back to defaults (enabled: false) if yq is missing or config absent.
    62 |  */
    63 | export declare function loadMultiModelConfig(): MultiModelConfig;
    64 | /** Environment variable to API key mapping for multi-model providers. */
    65 | export declare const PROVIDER_API_KEY_ENV: Record<string, string>;
    66 | /** A `*-headless` model id: a kind:cli alias, whose CLI hop needs no API key in BB's environment. */
    67 | export declare function isHeadlessModelId(modelId: string, provider?: string): boolean;
    68 | /** cycle-127 FR-1: the agy (Antigravity) route's opt-in and the headless mode that decides whether a google voice routes to it. */
    69 | export interface AgyGate {
    70 |     optIn: boolean;
    71 |     mode: string;
>   72 | }
>   73 | /**
>   74 |  * Read `hounfour.headless.agy_opt_in` (true only for a YAML boolean true) and `hounfour.headless.mode` from the Loa config
>   75 |  * with one yq call. LOA_HEADLESS_MODE wins for the mode, as it does in cheval; nothing in the environment opts in. A missing
>   76 |  * file, a missing yq or an unreadable config reads as off — the gate fails closed.
>   77 |  */
>   78 | export declare function readAgyGate(configPath?: string): AgyGate;
>   79 | /** A voice cheval would dispatch through agy: the gemini-headless id, or any google model when headless mode is cli-only. */
    80 | export declare function isAgyRouted(provider: string, modelId: string, mode: string): boolean;
    81 | /**
    82 |  * Validate API keys for configured multi-model providers.
    83 |  * Returns available and missing provider lists, and the voices not planned because their agy route's opt-in is off
    84 |  * (cycle-127 FR-1: neither valid nor missing — a voice that cannot exist on this host is never counted as a failed one).
    85 |  */
    86 | export declare function validateApiKeys(config: MultiModelConfig, gate?: AgyGate): {
    87 |     valid: Array<{
    88 |         provider: string;
    89 |         modelId: string;
    90 |     }>;
    91 |     missing: Array<{
~~~~

The change from head to the fix:

~~~~diff
@@ -72,8 +72,48 @@
+    /** The config could not be read (yq missing, unparsable YAML): the gate failed closed for this reason (r251-1 G14). */
+    readError?: string;
+    /** `agy_opt_in` is present but not written exactly `true` / `false` (the string "true", `True`, `yes` …): it reads off,
+     * said once (r251-1 G12, r251-2 K1 — the bash and Python readers apply the same strict rule). */
+    typeWarning?: string;
 }
+/** The Loa config the agy gate reads: the repo root's when one is known, else the cwd's (r251-1 G15 — one path for all callers). */
+export declare function loaConfigPathFor(repoRoot?: string): string;
+/** The go-yq "is the key present" program — the same text as the bash lib's `_AGY_YQ_HAS` and the Python loader's
+ * `_YQ_HAS` (r251-4 S3): every level a real mapping (`kind` is "alias" for an alias node) and the explicit key only (`has`
+ * never sees a merge key's). */
+export declare const AGY_YQ_HAS = ".hounfour | (kind == \"map\" and (.headless | (kind == \"map\" and has(\"agy_opt_in\"))))";
+/**
+ * Why the file's group is not its owner's USER-PRIVATE group, or undefined when it is (review r251-6 V1, BB #1). ONE rule with
+ * cheval's `loader._not_private_group` and the bash lib's `_agy_group_not_private`: the file's gid is the owner's primary gid,
+ * the group is NAMED for the owner (a shared `users` / macOS `staff` fails — their member lists are empty for primary members,
+ * so emptiness alone never proved privacy: audit LOW-001), no account but the owner is a listed member, no other account has
+ * it as its primary group (enumerated last), and no ACL makes the group bits a mask over named grants (`ls -ldL`'s `+`, on
+ * the read's own descriptor when one is given). Accounts come from `getent`; a host without it, or one that cannot answer,
+ * is no proof: not private.
+ */
+export declare function agyGroupNotPrivate(uid: number, gid: number, fd?: number, configPath?: string): string | undefined;
+/**
+ * Why the opt-in config is not the current user's alone to write, or undefined when it is (review r251-5 U1/U2, r251-6 V1):
+ * ONE permission rule with cheval's `loader._config_untrusted_reason` and the bash lib's `_agy_config_untrusted` — owned by
+ * the current user, never world-writable, and group-writable only for the owner's user-private group (`agyGroupNotPrivate`;
+ * Ubuntu's umask 002 makes every checkout 0664). `st` / `fd` are the read's own open file (r251-6 V3, BB #2: the bytes read
+ * and the inode judged are one); without them `statSync` follows a symlink: the target decides, as in the other readers. A
+ * config that cannot be stat'ed is untrusted (fail closed). Where the platform has no uid (`process.getuid` absent), the
+ * owner half is skipped.
+ */
+export declare function agyConfigUntrustedReason(configPath: string, st?: {
+    uid: number;
+    gid: number;
+    mode: number;
+}, fd?: number): string | undefined;
 /**
  * Read `hounfour.headless.agy_opt_in` (true only for a YAML boolean true) and `hounfour.headless.mode` from the Loa config
  * with one yq call. LOA_HEADLESS_MODE wins for the mode, as it does in cheval; nothing in the environment opts in. A missing
- * file, a missing yq or an unreadable config reads as off — the gate fails closed.
+ * file reads as off; a missing yq or an unreadable config reads as off too (the gate fails closed) and carries `readError`.
+ */
+export declare function readAgyGate(configPath: string): AgyGate;
+/** The ancestors' kind and tag (r251-6 V5): `hounfour`, and `hounfour.headless` only below a real mapping. */
+export declare const AGY_YQ_ANCESTORS = "\"k1\": (.hounfour | kind), \"t1\": (.hounfour | tag), \"k2\": ((.hounfour | select(kind == \"map\") | .headless | kind) // \"\"), \"t2\": ((.hounfour | select(kind == \"map\") | .headless | tag) // \"\")";
+/**
+ * A voice cheval would dispatch through agy: a google headless id of the generated registry (today `gemini-headless`), or
+ * any google model when the effective headless mode is cli-only (the bash/Python predicate's shape — lib/agy-gate-lib.sh).
  */
-export declare function readAgyGate(configPath?: string): AgyGate;
-/** A voice cheval would dispatch through agy: the gemini-headless id, or any google model when headless mode is cli-only. */
~~~~

## H130 — .claude/skills/bridgebuilder-review/dist/config.d.ts — head line 86

Head context (head/.claude/skills/bridgebuilder-review/dist/config.d.ts, lines 74–98):

~~~~text
    74 |  * Read `hounfour.headless.agy_opt_in` (true only for a YAML boolean true) and `hounfour.headless.mode` from the Loa config
    75 |  * with one yq call. LOA_HEADLESS_MODE wins for the mode, as it does in cheval; nothing in the environment opts in. A missing
    76 |  * file, a missing yq or an unreadable config reads as off — the gate fails closed.
    77 |  */
    78 | export declare function readAgyGate(configPath?: string): AgyGate;
    79 | /** A voice cheval would dispatch through agy: the gemini-headless id, or any google model when headless mode is cli-only. */
    80 | export declare function isAgyRouted(provider: string, modelId: string, mode: string): boolean;
    81 | /**
    82 |  * Validate API keys for configured multi-model providers.
    83 |  * Returns available and missing provider lists, and the voices not planned because their agy route's opt-in is off
    84 |  * (cycle-127 FR-1: neither valid nor missing — a voice that cannot exist on this host is never counted as a failed one).
    85 |  */
>   86 | export declare function validateApiKeys(config: MultiModelConfig, gate?: AgyGate): {
    87 |     valid: Array<{
    88 |         provider: string;
    89 |         modelId: string;
    90 |     }>;
    91 |     missing: Array<{
    92 |         provider: string;
    93 |         envVar: string;
    94 |     }>;
    95 |     notPlanned: Array<{
    96 |         provider: string;
    97 |         modelId: string;
    98 |         reason: "opt_in_required";
~~~~

The change from head to the fix:

~~~~diff
@@ -86 +126 @@
-export declare function validateApiKeys(config: MultiModelConfig, gate?: AgyGate): {
+export declare function validateApiKeys(config: MultiModelConfig, gate: AgyGate): {
~~~~

## H131 — .claude/skills/bridgebuilder-review/dist/config.d.ts — insertion after head line 100

Head context (head/.claude/skills/bridgebuilder-review/dist/config.d.ts, lines 89–112):

~~~~text
    89 |         modelId: string;
    90 |     }>;
    91 |     missing: Array<{
    92 |         provider: string;
    93 |         envVar: string;
    94 |     }>;
    95 |     notPlanned: Array<{
    96 |         provider: string;
    97 |         modelId: string;
    98 |         reason: "opt_in_required";
    99 |     }>;
   100 | };
   101 | export interface CLIArgs {
   102 |     dryRun?: boolean;
   103 |     repos?: string[];
   104 |     pr?: number;
   105 |     noAutoDetect?: boolean;
   106 |     maxInputTokens?: number;
   107 |     maxOutputTokens?: number;
   108 |     maxDiffBytes?: number;
   109 |     model?: string;
   110 |     persona?: string;
   111 |     exclude?: string[];
   112 |     forceFullReview?: boolean;
~~~~

The change from head to the fix:

~~~~diff
@@ -100,0 +141,6 @@
+/**
+ * The startup lines for the agy gate (r251-2 K7f): the read error and the type warning each said once, unconditionally —
+ * not only when a voice is not planned — and the not-planned voices. main.ts prints them; the pipeline says its own once
+ * per review.
+ */
+export declare function agyGateStartupLines(gate: AgyGate, keyStatus: ReturnType<typeof validateApiKeys>): string[];
~~~~

## H132 — .claude/skills/bridgebuilder-review/dist/config.d.ts.map — head line 1

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

## H133 — .claude/skills/bridgebuilder-review/dist/config.js — insertion after head line 3

Head context (head/.claude/skills/bridgebuilder-review/dist/config.js, lines 1–15):

~~~~text
     1 | import { execFile, execFileSync, execSync } from "node:child_process";
     2 | import { promisify } from "node:util";
     3 | import { readFile } from "node:fs/promises";
     4 | import { z } from "zod/v4";
     5 | import { GENERATED_MODEL_REGISTRY } from "./config.generated.js";
     6 | const execFileAsync = promisify(execFile);
     7 | /**
     8 |  * Zod schema for multi-model configuration (SDD Section 2.7).
     9 |  * Validated at startup; all fields have sensible defaults so partial config works.
    10 |  */
    11 | const ScoringThresholdsSchema = z.object({
    12 |     high_consensus: z.number().default(700),
    13 |     disputed_delta: z.number().default(300),
    14 |     low_value: z.number().default(400),
    15 |     blocker: z.number().default(700),
~~~~

The change from head to the fix:

~~~~diff
@@ -3,0 +4,2 @@
+import { closeSync, existsSync, fstatSync, openSync, readFileSync, statSync } from "node:fs";
+import { join } from "node:path";
~~~~

## H134 — .claude/skills/bridgebuilder-review/dist/config.js — head lines 122–147

Head context (head/.claude/skills/bridgebuilder-review/dist/config.js, lines 110–159):

~~~~text
   110 |     openai: "OPENAI_API_KEY",
   111 |     google: "GOOGLE_API_KEY",
   112 | };
   113 | /** A `*-headless` model id: a kind:cli alias, whose CLI hop needs no API key in BB's environment. */
   114 | // (case-sensitive, as cheval's alias lookup is — `Claude-Headless` resolves to nothing: thirty-eighth run, e4 DISS-C-002)
   115 | // (and a catalog entry, under its own provider when one is named — a suffix alone admitted a typo or a pairing cheval has no
   116 | // alias for, past the key gate's fail-fast: thirty-ninth run, e4 DISS-C-002)
   117 | export function isHeadlessModelId(modelId, provider) {
   118 |     if (typeof modelId !== "string" || !/-headless$/.test(modelId) || !Object.hasOwn(GENERATED_MODEL_REGISTRY, modelId))
   119 |         return false;
   120 |     return provider === undefined || GENERATED_MODEL_REGISTRY[modelId].provider === provider;
   121 | }
>  122 | /**
>  123 |  * Read `hounfour.headless.agy_opt_in` (true only for a YAML boolean true) and `hounfour.headless.mode` from the Loa config
>  124 |  * with one yq call. LOA_HEADLESS_MODE wins for the mode, as it does in cheval; nothing in the environment opts in. A missing
>  125 |  * file, a missing yq or an unreadable config reads as off — the gate fails closed.
>  126 |  */
>  127 | export function readAgyGate(configPath = ".loa.config.yaml") {
>  128 |     let optIn = false;
>  129 |     let mode = "";
>  130 |     try {
>  131 |         const out = execFileSync("yq", ["eval", "-o=json", "-I=0",
>  132 |             '{"opt": (.hounfour.headless.agy_opt_in | (tag == "!!bool" and . == true)), "mode": (.hounfour.headless.mode // "")}',
>  133 |             configPath], { encoding: "utf8", timeout: 5000, stdio: ["ignore", "pipe", "ignore"] });
>  134 |         const parsed = JSON.parse(out);
>  135 |         optIn = parsed.opt === true;
>  136 |         mode = typeof parsed.mode === "string" ? parsed.mode : "";
>  137 |     }
>  138 |     catch {
>  139 |         // (fail closed: no opt-in)
>  140 |     }
>  141 |     return { optIn, mode: process.env.LOA_HEADLESS_MODE || mode || "prefer-api" };
>  142 | }
>  143 | /** A voice cheval would dispatch through agy: the gemini-headless id, or any google model when headless mode is cli-only. */
>  144 | export function isAgyRouted(provider, modelId, mode) {
>  145 |     if (provider !== "google")
>  146 |         return false;
>  147 |     return modelId === "gemini-headless" || mode === "cli-only";
   148 | }
   149 | /**
   150 |  * Validate API keys for configured multi-model providers.
   151 |  * Returns available and missing provider lists, and the voices not planned because their agy route's opt-in is off
   152 |  * (cycle-127 FR-1: neither valid nor missing — a voice that cannot exist on this host is never counted as a failed one).
   153 |  */
   154 | export function validateApiKeys(config, gate = readAgyGate()) {
   155 |     const valid = [];
   156 |     const missing = [];
   157 |     const notPlanned = [];
   158 |     for (const model of config.models) {
   159 |         if (!gate.optIn && isAgyRouted(model.provider, model.model_id, gate.mode)) {
~~~~

The change from head to the fix:

~~~~diff
@@ -122,26 +124,209 @@
+/** The Loa config the agy gate reads: the repo root's when one is known, else the cwd's (r251-1 G15 — one path for all callers). */
+export function loaConfigPathFor(repoRoot) {
+    return repoRoot ? join(repoRoot, ".loa.config.yaml") : ".loa.config.yaml";
+}
+/** The go-yq "is the key present" program — the same text as the bash lib's `_AGY_YQ_HAS` and the Python loader's
+ * `_YQ_HAS` (r251-4 S3): every level a real mapping (`kind` is "alias" for an alias node) and the explicit key only (`has`
+ * never sees a merge key's). */
+export const AGY_YQ_HAS = '.hounfour | (kind == "map" and (.headless | (kind == "map" and has("agy_opt_in"))))';
+/** One NSS lookup through `getent` (the bash lib's account source); undefined when getent is missing or cannot answer. */
+function getent(args) {
+    try {
+        return execFileSync("getent", args, { encoding: "utf8", timeout: 5000, stdio: ["ignore", "pipe", "ignore"] });
+    }
+    catch {
+        return undefined;
+    }
+}
+/**
+ * Why the file's group is not its owner's USER-PRIVATE group, or undefined when it is (review r251-6 V1, BB #1). ONE rule with
+ * cheval's `loader._not_private_group` and the bash lib's `_agy_group_not_private`: the file's gid is the owner's primary gid,
+ * the group is NAMED for the owner (a shared `users` / macOS `staff` fails — their member lists are empty for primary members,
+ * so emptiness alone never proved privacy: audit LOW-001), no account but the owner is a listed member, no other account has
+ * it as its primary group (enumerated last), and no ACL makes the group bits a mask over named grants (`ls -ldL`'s `+`, on
+ * the read's own descriptor when one is given). Accounts come from `getent`; a host without it, or one that cannot answer,
+ * is no proof: not private.
+ */
+export function agyGroupNotPrivate(uid, gid, fd, configPath) {
+    const pw = (getent(["passwd", String(uid)]) ?? "").split("\n")[0].split(":");
+    const owner = pw[0] ?? "";
+    const pgid = pw[3] ?? "";
+    if (!owner || !/^\d+$/.test(pgid))
+        return `its owner uid ${uid} could not be looked up`;
+    const gr = (getent(["group", String(gid)]) ?? "").split("\n")[0].split(":");
+    const gname = gr[0] ?? "";
+    if (!gname)
+        return `its group could not be looked up (gid ${gid})`;
+    if (String(gid) !== pgid)
+        return `its group '${gname}' (gid ${gid}) is not the owner's primary group`;
+    if (gname !== owner)
+        return `its group '${gname}' is not named for the owner '${owner}' (not a user-private group)`;
+    const members = (gr[3] ?? "").split(",").map((m) => m.trim()).filter((m) => m && m !== owner);
+    if (members.length)
+        return `its group '${gname}' has other members (${members.join(", ")})`;
+    const all = getent(["passwd"]);
+    if (all === undefined)
+        return `the accounts of group '${gname}' could not be enumerated`;
+    const primary = all.split("\n").map((l) => l.split(":")).filter((f) => f.length > 3 && f[3] === String(gid) && f[2] !== String(uid)).map((f) => f[0]);
+    if (primary.length)
+        return `its group '${gname}' is the primary group of another account (${primary.join(", ")})`;
+    let ls = "";
+    try {
+        ls = fd !== undefined
+            ? execFileSync("ls", ["-ldL", "/dev/stdin"], { encoding: "utf8", timeout: 5000, stdio: [fd, "pipe", "ignore"] })
+            : execFileSync("ls", ["-ldL", "--", configPath ?? ""], { encoding: "utf8", timeout: 5000, stdio: ["ignore", "pipe", "ignore"] });
+    }
+    catch {
+        ls = "";
+    }
+    const lsMode = ls.split(" ")[0] ?? "";
+    if (lsMode.length < 10)
+        return "its ACL could not be read";
+    if (lsMode[10] === "+")
+        return "it carries an extended ACL (the group bits are the ACL mask over other accounts' grants)";
+    return undefined;
+}
+/**
+ * Why the opt-in config is not the current user's alone to write, or undefined when it is (review r251-5 U1/U2, r251-6 V1):
+ * ONE permission rule with cheval's `loader._config_untrusted_reason` and the bash lib's `_agy_config_untrusted` — owned by
+ * the current user, never world-writable, and group-writable only for the owner's user-private group (`agyGroupNotPrivate`;
+ * Ubuntu's umask 002 makes every checkout 0664). `st` / `fd` are the read's own open file (r251-6 V3, BB #2: the bytes read
+ * and the inode judged are one); without them `statSync` follows a symlink: the target decides, as in the other readers. A
+ * config that cannot be stat'ed is untrusted (fail closed). Where the platform has no uid (`process.getuid` absent), the
+ * owner half is skipped.
+ */
+export function agyConfigUntrustedReason(configPath, st, fd) {
+    if (st === undefined) {
+        try {
+            st = statSync(configPath);
+        }
+        catch {
+            return `${configPath} could not be stat'ed (owner and mode unknown)`;
+        }
+    }
+    const me = typeof process.getuid === "function" ? process.getuid() : undefined;
+    if (me !== undefined && st.uid !== me)
+        return `${configPath} is not owned by the current user (uid ${st.uid}, euid ${me})`;
+    const mode = `mode ${(st.mode & 0o7777).toString(8).padStart(4, "0")}`;
+    if (st.mode & 0o002)
+        return `${configPath} is world-writable (${mode})`;
+    if (st.mode & 0o020) {
+        const why = agyGroupNotPrivate(st.uid, st.gid, fd, configPath);
+        if (why !== undefined)
+            return `${configPath} is group-writable (${mode}) and ${why}`;
+    }
+    return undefined;
+}
 /**
  * Read `hounfour.headless.agy_opt_in` (true only for a YAML boolean true) and `hounfour.headless.mode` from the Loa config
  * with one yq call. LOA_HEADLESS_MODE wins for the mode, as it does in cheval; nothing in the environment opts in. A missing
- * file, a missing yq or an unreadable config reads as off — the gate fails closed.
+ * file reads as off; a missing yq or an unreadable config reads as off too (the gate fails closed) and carries `readError`.
  */
-export function readAgyGate(configPath = ".loa.config.yaml") {
+export function readAgyGate(configPath) {
     let optIn = false;
     let mode = "";
+    let readError;
+    let typeWarning;
+    if (existsSync(configPath)) {
+        let fd;
+        let content;
+        try {
+            // (r251-6 V3, BB #2: the config is opened ONCE — yq parses the bytes read from this descriptor on stdin and the trust
+            // rule judges its fstat, so a swap of the path between read and check changes nothing)
+            fd = openSync(configPath, "r");
+            const st = fstatSync(fd);
+            if (!st.isFile())
+                throw new Error(`${configPath} is not a regular file`);
+            content = readFileSync(fd);
+            const out = execFileSync("yq", ["eval", "-o=json", "-I=0",
+                `{"has": (${AGY_YQ_HAS}), "kind": (.hounfour.headless.agy_opt_in | kind), "opt": (.hounfour.headless.agy_opt_in | (tag == "!!bool" and . == true)), "canon": (.hounfour.headless.agy_opt_in | (tag == "!!bool" and (. == true or . == false))), "tag": (.hounfour.headless.agy_opt_in | tag), "mode": (.hounfour.headless.mode // ""), ${AGY_YQ_ANCESTORS}}`,
+                "-"], { encoding: "utf8", timeout: 5000, input: content, stdio: ["pipe", "pipe", "pipe"] });
+            const parsed = JSON.parse(out);
+            // (r251-4 S3: the key must be written at hounfour.headless itself — every level a real mapping, never an alias or a
+            // merge key's value — and its node a plain scalar of the exact bool tag; one rule with the bash and Python readers)
+            const present = parsed.has === true;
+            const alias = parsed.kind === "alias";
+            optIn = present && !alias && parsed.opt === true;
+            mode = typeof parsed.mode === "string" ? parsed.mode : "";
+            const ancestor = present ? undefined : agyAncestorProblem(parsed);
+            // (r251-5 U1: a config others can write never opts in — one WARN naming the key and the reason; not a readError:
+            // the gate reads off, exactly as the bash and Python readers, rather than blocking the merge. Only a value that
+            // would opt in is judged, as there: a config that reads off anyway is not flagged)
+            const untrusted = optIn ? agyConfigUntrustedReason(configPath, st, fd) : undefined;
+            if (untrusted !== undefined) {
+                optIn = false;
+                typeWarning = `hounfour.headless.agy_opt_in: ${untrusted} — a config others can write never opts in (own it and \`chmod go-w\` it); the agy route stays off`;
+            }
+            else if (ancestor !== undefined) {
+                typeWarning = `${ancestor} — hounfour.headless.agy_opt_in cannot be read through an alias or merge node (write the mapping inline); the agy route stays off`;
+            }
+            else if (present && alias) {
+                typeWarning = "hounfour.headless.agy_opt_in is present but not a YAML boolean (an alias) — only `agy_opt_in: true` opts in (expected true or false); the agy route stays off";
+            }
+            else if (present && typeof parsed.tag === "string" && parsed.tag !== "!!null" && parsed.tag !== "!!bool") {
+                typeWarning = `hounfour.headless.agy_opt_in is present but not a YAML boolean (${parsed.tag}) — only \`agy_opt_in: true\` opts in (expected true or false); the agy route stays off`;
+            }
+            else if (present && parsed.tag === "!!bool" && parsed.canon !== true) {
+                typeWarning = "hounfour.headless.agy_opt_in is a boolean spelled other than true/false — only `agy_opt_in: true` opts in (the lowercase scalar); the agy route stays off";
+            }
+        }
+        catch (err) {
+            // (fail closed: no opt-in — and say why, rather than reading as a plain "opt-in off")
+            const e = err;
+            const stderr = typeof e.stderr === "string" ? e.stderr.trim() : Buffer.isBuffer(e.stderr) ? e.stderr.toString("utf8").trim() : "";
+            optIn = false;
+            // (r251-6 V5: a non-mapping ancestor yq cannot index below — `headless: [1]` — is the ancestor warning the bash and
+            // Python readers give, not a host read error; the same bytes, the guarded ancestors-only program)
+            const ancestor = content !== undefined ? agyAncestorOnly(content) : undefined;
+            if (ancestor !== undefined) {
+                typeWarning = `${ancestor} — hounfour.headless.agy_opt_in cannot be read through an alias or merge node (write the mapping inline); the agy route stays off`;
+            }
+            else {
+                readError = (stderr || e.message || String(err)).split("\n")[0].slice(0, 300);
+            }
+        }
+        finally {
+            if (fd !== undefined)
+                closeSync(fd);
+        }
+    }
+    return {
+        optIn, mode: process.env.LOA_HEADLESS_MODE || mode || "prefer-api",
+        ...(readError !== undefined ? { readError } : {}), ...(typeWarning !== undefined ? { typeWarning } : {}),
+    };
+}
+/** The ancestors' kind and tag (r251-6 V5): `hounfour`, and `hounfour.headless` only below a real mapping. */
+export const AGY_YQ_ANCESTORS = '"k1": (.hounfour | kind), "t1": (.hounfour | tag), "k2": ((.hounfour | select(kind == "map") | .headless | kind) // ""), "t2": ((.hounfour | select(kind == "map") | .headless | tag) // "")';
+/** The ancestors-only read of `content` (never errors on a non-mapping level: each level is guarded); undefined on any failure. */
+function agyAncestorOnly(content) {
     try {
-        const out = execFileSync("yq", ["eval", "-o=json", "-I=0",
-            '{"opt": (.hounfour.headless.agy_opt_in | (tag == "!!bool" and . == true)), "mode": (.hounfour.headless.mode // "")}',
-            configPath], { encoding: "utf8", timeout: 5000, stdio: ["ignore", "pipe", "ignore"] });
-        const parsed = JSON.parse(out);
-        optIn = parsed.opt === true;
-        mode = typeof parsed.mode === "string" ? parsed.mode : "";
+        const out = execFileSync("yq", ["eval", "-o=json", "-I=0", `{${AGY_YQ_ANCESTORS}}`, "-"], { encoding: "utf8", timeout: 5000, input: content, stdio: ["pipe", "pipe", "pipe"] });
+        return agyAncestorProblem(JSON.parse(out));
     }
     catch {
-        // (fail closed: no opt-in)
+        return undefined;
     }
-    return { optIn, mode: process.env.LOA_HEADLESS_MODE || mode || "prefer-api" };
 }
-/** A voice cheval would dispatch through agy: the gemini-headless id, or any google model when headless mode is cli-only. */
+/** `<path> is a YAML alias` / `<path> is not a mapping (<kind>)` for an alias or non-mapping ancestor of the key — one WARN,
+ * never a silent absent (r251-6 V5, BB #5; the bash and Python readers say the same); undefined when every ancestor is a
+ * mapping, absent or null. */
+function agyAncestorProblem(p) {
+    for (const [path, k, t] of [["hounfour", p.k1, p.t1], ["hounfour.headless", p.k2, p.t2]]) {
+        if (k === "map")
+            continue;
+        if (k === "alias")
+            return `${path} is a YAML alias`;
+        if (typeof t !== "string" || t === "" || t === "!!null")
+            return undefined;
+        return `${path} is not a mapping (${t.replace(/^!!/, "")})`;
+    }
+    return undefined;
+}
+/**
+ * A voice cheval would dispatch through agy: a google headless id of the generated registry (today `gemini-headless`), or
+ * any google model when the effective headless mode is cli-only (the bash/Python predicate's shape — lib/agy-gate-lib.sh).
+ */
 export function isAgyRouted(provider, modelId, mode) {
     if (provider !== "google")
         return false;
-    return modelId === "gemini-headless" || mode === "cli-only";
+    return isHeadlessModelId(modelId, "google") || mode === "cli-only";
~~~~

## H135 — .claude/skills/bridgebuilder-review/dist/config.js — head line 154

Head context (head/.claude/skills/bridgebuilder-review/dist/config.js, lines 142–166):

~~~~text
   142 | }
   143 | /** A voice cheval would dispatch through agy: the gemini-headless id, or any google model when headless mode is cli-only. */
   144 | export function isAgyRouted(provider, modelId, mode) {
   145 |     if (provider !== "google")
   146 |         return false;
   147 |     return modelId === "gemini-headless" || mode === "cli-only";
   148 | }
   149 | /**
   150 |  * Validate API keys for configured multi-model providers.
   151 |  * Returns available and missing provider lists, and the voices not planned because their agy route's opt-in is off
   152 |  * (cycle-127 FR-1: neither valid nor missing — a voice that cannot exist on this host is never counted as a failed one).
   153 |  */
>  154 | export function validateApiKeys(config, gate = readAgyGate()) {
   155 |     const valid = [];
   156 |     const missing = [];
   157 |     const notPlanned = [];
   158 |     for (const model of config.models) {
   159 |         if (!gate.optIn && isAgyRouted(model.provider, model.model_id, gate.mode)) {
   160 |             notPlanned.push({ provider: model.provider, modelId: model.model_id, reason: "opt_in_required" });
   161 |             continue;
   162 |         }
   163 |         const envVar = PROVIDER_API_KEY_ENV[model.provider];
   164 |         if (!envVar) {
   165 |             missing.push({ provider: model.provider, envVar: `Unknown provider: ${model.provider}` });
   166 |             continue;
~~~~

The change from head to the fix:

~~~~diff
@@ -154 +339 @@
-export function validateApiKeys(config, gate = readAgyGate()) {
+export function validateApiKeys(config, gate) {
~~~~

## H136 — .claude/skills/bridgebuilder-review/dist/config.js — head line 159

Head context (head/.claude/skills/bridgebuilder-review/dist/config.js, lines 147–171):

~~~~text
   147 |     return modelId === "gemini-headless" || mode === "cli-only";
   148 | }
   149 | /**
   150 |  * Validate API keys for configured multi-model providers.
   151 |  * Returns available and missing provider lists, and the voices not planned because their agy route's opt-in is off
   152 |  * (cycle-127 FR-1: neither valid nor missing — a voice that cannot exist on this host is never counted as a failed one).
   153 |  */
   154 | export function validateApiKeys(config, gate = readAgyGate()) {
   155 |     const valid = [];
   156 |     const missing = [];
   157 |     const notPlanned = [];
   158 |     for (const model of config.models) {
>  159 |         if (!gate.optIn && isAgyRouted(model.provider, model.model_id, gate.mode)) {
   160 |             notPlanned.push({ provider: model.provider, modelId: model.model_id, reason: "opt_in_required" });
   161 |             continue;
   162 |         }
   163 |         const envVar = PROVIDER_API_KEY_ENV[model.provider];
   164 |         if (!envVar) {
   165 |             missing.push({ provider: model.provider, envVar: `Unknown provider: ${model.provider}` });
   166 |             continue;
   167 |         }
   168 |         // (a `*-headless` entry is a cheval CLI hop that authenticates itself — every voice dispatches through cheval — so
   169 |         // it needs no key; the gate dropped the keyless host's claude-headless entry: cycle-126 thirty-seventh run, e2b DISS-C-003)
   170 |         if (isHeadlessModelId(model.model_id, model.provider) || process.env[envVar]) {
   171 |             valid.push({ provider: model.provider, modelId: model.model_id });
~~~~

The change from head to the fix:

~~~~diff
@@ -159 +344,4 @@
-        if (!gate.optIn && isAgyRouted(model.provider, model.model_id, gate.mode)) {
+        // (r251-2 K7b: an unreadable config fails closed for EVERY google voice — its mode is unknown, so is its route: cheval,
+        // reading the same file with PyYAML, might route it to agy and refuse; planned-as-HTTP would mis-count a failed voice)
+        const gated = gate.readError !== undefined ? model.provider === "google" : isAgyRouted(model.provider, model.model_id, gate.mode);
+        if (!gate.optIn && gated) {
~~~~

## H137 — .claude/skills/bridgebuilder-review/dist/config.js — insertion after head line 178

Head context (head/.claude/skills/bridgebuilder-review/dist/config.js, lines 167–190):

~~~~text
   167 |         }
   168 |         // (a `*-headless` entry is a cheval CLI hop that authenticates itself — every voice dispatches through cheval — so
   169 |         // it needs no key; the gate dropped the keyless host's claude-headless entry: cycle-126 thirty-seventh run, e2b DISS-C-003)
   170 |         if (isHeadlessModelId(model.model_id, model.provider) || process.env[envVar]) {
   171 |             valid.push({ provider: model.provider, modelId: model.model_id });
   172 |         }
   173 |         else {
   174 |             missing.push({ provider: model.provider, envVar });
   175 |         }
   176 |     }
   177 |     return { valid, missing, notPlanned };
   178 | }
   179 | /** Built-in defaults per PRD FR-4 (lowest priority). */
   180 | const DEFAULTS = {
   181 |     repos: [],
   182 |     // cycle-126 FR-1.5 (SDD D-1.5): the `opus` alias (resolved by cheval's alias
   183 |     // path, so the default follows the catalog's retarget instead of pinning a
   184 |     // snapshot); the input default matches the 200K-class payload the 5-family
   185 |     // reviews take, the output default the BB_OUTPUT_CAP of the generated table.
   186 |     model: "opus",
   187 |     maxPrs: 10,
   188 |     maxFilesPerPr: 50,
   189 |     maxDiffBytes: 512_000,
   190 |     maxInputTokens: 200_000,
~~~~

The change from head to the fix:

~~~~diff
@@ -178,0 +367,17 @@
+/**
+ * The startup lines for the agy gate (r251-2 K7f): the read error and the type warning each said once, unconditionally —
+ * not only when a voice is not planned — and the not-planned voices. main.ts prints them; the pipeline says its own once
+ * per review.
+ */
+export function agyGateStartupLines(gate, keyStatus) {
+    const lines = [];
+    if (gate.readError !== undefined) {
+        lines.push(`[bridgebuilder] agy gate: Loa config unreadable (${gate.readError}) — failing closed: google voices are not planned (hounfour.headless.agy_opt_in)`);
+    }
+    if (gate.typeWarning !== undefined)
+        lines.push(`[bridgebuilder] ${gate.typeWarning}`);
+    if (keyStatus.notPlanned.length > 0) {
+        lines.push(`[bridgebuilder] Not planned (agy opt-in, hounfour.headless.agy_opt_in): ${keyStatus.notPlanned.map((n) => `${n.provider}/${n.modelId}`).join(", ")}`);
+    }
+    return lines;
+}
~~~~

## H138 — .claude/skills/bridgebuilder-review/dist/config.js.map — head line 1

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

## H139 — .claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.d.ts — head line 167

Head context (head/.claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.d.ts, lines 155–179):

~~~~text
   155 |         chain_health?: string;
   156 |     };
   157 | }>): "APPROVED" | "DEGRADED" | "FAILED" | null;
   158 | export declare function formatVerdictQualityHeader(perModelResults: Array<{
   159 |     provider: string;
   160 |     modelId: string;
   161 |     verdictQuality?: {
   162 |         status?: string;
   163 |         voices_succeeded?: number;
   164 |         voices_planned?: number;
   165 |         chain_health?: string;
   166 |     };
>  167 | }>): string;
   168 | /**
   169 |  * A degraded-verdict trajectory record — byte-compatible with the record
   170 |  * shape written by degraded-verdict-lib.sh (cycle-117 item D). Field set and
   171 |  * ordering intentionally mirror that bash writer and the schema at
   172 |  * .claude/data/trajectory-schemas/degraded-verdict.schema.json
   173 |  * (additionalProperties: false — do NOT add fields).
   174 |  */
   175 | export interface DegradedVerdictRecord {
   176 |     gate: string;
   177 |     verdict_band: "DEGRADED" | "FAILED";
   178 |     degradation_reason: string;
   179 |     degraded_legs?: string[];
~~~~

The change from head to the fix:

~~~~diff
@@ -167 +167,4 @@
-}>): string;
+}>, notPlanned?: ReadonlyArray<{
+    provider: string;
+    modelId: string;
+}>, notPlannedReason?: string): string;
~~~~

## H140 — .claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.d.ts.map — head line 1

Head context (head/.claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.d.ts.map, lines 1–1):

~~~~text
>    1 | {"version":3,"file":"multi-model-pipeline.d.ts","sourceRoot":"","sources":["../../resources/core/multi-model-pipeline.ts"],"names":[],"mappings":"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"}
~~~~

The change from head to the fix:

~~~~diff
@@ -1 +1 @@
-{"version":3,"file":"multi-model-pipeline.d.ts","sourceRoot":"","sources":["../../resources/core/multi-model-pipeline.ts"],"names":[],"mappings":"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"}
\ No newline at end of file
+{"version":3,"file":"multi-model-pipeline.d.ts","sourceRoot":"","sources":["../../resources/core/multi-model-pipeline.ts"],"names":[],"mappings":"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"}
\ No newline at end of file
~~~~

## H141 — .claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.js — head line 13

Head context (head/.claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.js, lines 1–25):

~~~~text
     1 | /**
     2 |  * MultiModelPipeline — orchestrates parallel multi-model reviews with consensus scoring.
     3 |  *
     4 |  * Executes N model reviews in parallel via Promise.allSettled(), scores findings
     5 |  * using dual-track consensus (convergence + diversity), and posts per-model
     6 |  * comments followed by a consensus summary.
     7 |  */
     8 | import { appendFile, mkdir } from "node:fs/promises";
     9 | import path from "node:path";
    10 | import { summarizeReviewVerdict } from "./review-verdict.js";
    11 | import { scoreFindings } from "./scoring.js";
    12 | import { createAdapter } from "../adapters/adapter-factory.js";
>   13 | import { PROVIDER_API_KEY_ENV, isHeadlessModelId, readAgyGate, validateApiKeys } from "../config.js";
    14 | import { GENERATED_MODEL_REGISTRY, GENERATED_REASONING } from "../config.generated.js";
    15 | /**
    16 |  * Per-model timeout derivation — reasoning-class predicate (multi-provider).
    17 |  *
    18 |  * History:
    19 |  *   - cycle-100 sprint-bug-143 (#789a) introduced the 1_800_000ms (30-min)
    20 |  *     budget for OpenAI `gpt-*-pro` after gpt-5.5-pro hung past 900s on a
    21 |  *     95k-token diff (most of the budget is spent on internal reasoning
    22 |  *     before any visible tokens emit).
    23 |  *   - cycle-111 sprint-bug-165 (#921) extended the predicate to the rest
    24 |  *     of the BB triad. Claude Opus + Gemini Pro are reasoning-class too —
    25 |  *     they were silently SIGTERMing at the 300_000ms ceiling on realistic
~~~~

The change from head to the fix:

~~~~diff
@@ -13 +13 @@
-import { PROVIDER_API_KEY_ENV, isHeadlessModelId, readAgyGate, validateApiKeys } from "../config.js";
+import { PROVIDER_API_KEY_ENV, isHeadlessModelId, loaConfigPathFor, readAgyGate, validateApiKeys } from "../config.js";
~~~~

## H142 — .claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.js — head lines 97–99

Head context (head/.claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.js, lines 85–111):

~~~~text
    85 |  *
    86 |  * @param item - The PR review item
    87 |  * @param systemPrompt - The system prompt (same for all models)
    88 |  * @param userPrompt - The user prompt (same for all models)
    89 |  * @param config - Full bridgebuilder config (includes multiModel)
    90 |  * @param adapters - Shared adapters (poster, sanitizer, logger)
    91 |  * @returns Multi-model review result with per-model responses and consensus
    92 |  */
    93 | export async function executeMultiModelReview(item, systemPrompt, userPrompt, config, adapters, enrichment) {
    94 |     const multiConfig = config.multiModel;
    95 |     const { poster, sanitizer, logger } = adapters;
    96 |     // Validate API keys (cycle-127 FR-1: and the agy opt-in, read from the repo's Loa config)
>   97 |     const keyStatus = validateApiKeys(multiConfig, readAgyGate(config.repoRoot ? path.join(config.repoRoot, ".loa.config.yaml") : ".loa.config.yaml"));
>   98 |     for (const np of keyStatus.notPlanned) {
>   99 |         logger.info(`${np.provider} voice not planned: agy opt-in off (hounfour.headless.agy_opt_in)`);
   100 |     }
   101 |     if (multiConfig.api_key_mode === "strict" && keyStatus.missing.length > 0) {
   102 |         throw new Error(`Strict mode: missing API keys for providers: ${keyStatus.missing.map((m) => m.provider).join(", ")}`);
   103 |     }
   104 |     // Create adapters for available providers
   105 |     const modelAdapters = [];
   106 |     for (const entry of keyStatus.valid) {
   107 |         const envVar = PROVIDER_API_KEY_ENV[entry.provider];
   108 |         // (a headless entry is valid without a key — validateApiKeys — and cheval's CLI hop never reads one)
   109 |         const apiKey = (envVar ? process.env[envVar] : undefined) ?? "";
   110 |         if (!apiKey && !isHeadlessModelId(entry.modelId, entry.provider))
   111 |             continue;
~~~~

The change from head to the fix:

~~~~diff
@@ -97,3 +97,27 @@
-    const keyStatus = validateApiKeys(multiConfig, readAgyGate(config.repoRoot ? path.join(config.repoRoot, ".loa.config.yaml") : ".loa.config.yaml"));
+    const agyGate = readAgyGate(loaConfigPathFor(config.repoRoot));
+    const keyStatus = validateApiKeys(multiConfig, agyGate);
+    // (r251-1 G12/G14: an unreadable config or a non-boolean opt-in is said once, with its reason — not as "opt-in off")
+    const notPlannedList = keyStatus.notPlanned.map((np) => `${np.provider}/${np.modelId}`).join(", ");
+    if (agyGate.readError !== undefined) {
+        // (r251-2 K7d: the strict per-voice warn is skipped under a read error, so this one names the voices)
+        logger.warn(`[multi-model] agy gate unreadable (${agyGate.readError}) — failing closed: google voices are not planned (hounfour.headless.agy_opt_in)` +
+            (notPlannedList ? `; will not run: ${notPlannedList}` : ""));
+    }
+    if (agyGate.typeWarning !== undefined)
+        logger.warn(`[multi-model] ${agyGate.typeWarning}`);
     for (const np of keyStatus.notPlanned) {
-        logger.info(`${np.provider} voice not planned: agy opt-in off (hounfour.headless.agy_opt_in)`);
+        // (review r251-1 G3, finding 20: strict mode promises every configured voice — one the gate removes is said at warn,
+        // never thrown: the voice cannot exist on this host, it is not a missing key)
+        if (agyGate.readError !== undefined)
+            continue; // (already said, with the reason)
+        if (multiConfig.api_key_mode === "strict") {
+            logger.warn(`[multi-model] strict mode: configured voice ${np.provider}/${np.modelId} will not run — not planned: the agy route is opt-in (hounfour.headless.agy_opt_in is not true)`);
+        }
+        else {
+            logger.info(`${np.provider} voice not planned: agy opt-in off (hounfour.headless.agy_opt_in)`);
+        }
+    }
+    // (r251-4 S1, audit n22: a read error is a HOST fault, not a decision — strict mode promised every configured voice, so a
+    // voice the failed read removed refuses the review; graceful mode runs the rest but never clears the merge, below)
+    if (multiConfig.api_key_mode === "strict" && agyGate.readError !== undefined && keyStatus.notPlanned.length > 0) {
+        throw new Error(`Strict mode: the Loa config is unreadable (${agyGate.readError}) — the agy gate failed closed and configured voices will not run: ${notPlannedList} (hounfour.headless.agy_opt_in)`);
~~~~

## H143 — .claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.js — head line 127

Head context (head/.claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.js, lines 115–139):

~~~~text
   115 |             modelId: entry.modelId,
   116 |             apiKey,
   117 |             timeoutMs: deriveTimeoutMs(entry.provider, entry.modelId, config),
   118 |             costRates,
   119 |         });
   120 |         modelAdapters.push({
   121 |             provider: entry.provider,
   122 |             modelId: entry.modelId,
   123 |             adapter,
   124 |         });
   125 |     }
   126 |     if (modelAdapters.length === 0) {
>  127 |         throw new Error("No models available for multi-model review (all API keys missing)");
   128 |     }
   129 |     // Limit concurrency
   130 |     const concurrency = Math.min(modelAdapters.length, multiConfig.max_concurrency ?? 3);
   131 |     logger.info("[multi-model] Starting parallel review", {
   132 |         models: modelAdapters.map((m) => `${m.provider}/${m.modelId}`),
   133 |         concurrency,
   134 |     });
   135 |     // Execute reviews in parallel with concurrency limit
   136 |     const request = {
   137 |         systemPrompt,
   138 |         userPrompt,
   139 |         maxOutputTokens: config.maxOutputTokens,
~~~~

The change from head to the fix:

~~~~diff
@@ -127 +151,14 @@
-        throw new Error("No models available for multi-model review (all API keys missing)");
+        // (r251-2 K7c: ONE message, the not-planned voices and the missing keys listed separately — the reason for a not-planned
+        // voice is the read error when the config could not be read, else the opt-in)
+        const parts = [];
+        if (keyStatus.notPlanned.length > 0) {
+            parts.push(agyGate.readError !== undefined
+                ? `not planned: ${notPlannedList} (the agy gate failed closed: Loa config unreadable — ${agyGate.readError}; hounfour.headless.agy_opt_in)`
+                : `not planned: ${notPlannedList} (the agy route is opt-in: set hounfour.headless.agy_opt_in: true)`);
+        }
+        if (keyStatus.missing.length > 0) {
+            parts.push(`missing API keys: ${keyStatus.missing.map((m) => `${m.provider} (${m.envVar})`).join(", ")}`);
+        }
+        throw new Error(parts.length > 0 && keyStatus.missing.length > 0 && keyStatus.notPlanned.length === 0
+            ? `No models available for multi-model review (all API keys missing): ${parts.join("; ")}`
+            : `No models available for multi-model review — ${parts.length > 0 ? parts.join("; ") : "no configured voice is usable"}`);
~~~~

## H144 — .claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.js — head line 235

Head context (head/.claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.js, lines 223–247):

~~~~text
   223 |     // Pass-2 enrichment: generate human-readable consensus review (Option C).
   224 |     // When enrichment context provided, the first primary model writes a prose
   225 |     // review over the consensus findings. Falls back to stats-only if enrichment
   226 |     // fails or is disabled.
   227 |     // cycle-109 Sprint 2 T2.6 — prepend the verdict_quality header
   228 |     // (FR-2.8) before the consensus stats table. Returns empty string when
   229 |     // no per-model envelopes carry verdictQuality (legacy / pre-T2.3
   230 |     // cheval), so legacy review surfaces are unchanged.
   231 |     const verdictHeader = formatVerdictQualityHeader(modelResults.map((r) => ({
   232 |         provider: r.provider,
   233 |         modelId: r.model,
   234 |         verdictQuality: r.response?.verdictQuality,
>  235 |     })));
   236 |     // cycle-118 bd-bb-degraded-verdict-ts — append a DEGRADED/FAILED trajectory
   237 |     // record (same channel/schema as the 3 bash gate writers). No-op when the
   238 |     // aggregate band is APPROVED/clean. Fire-and-forget: never throws.
   239 |     await emitDegradedVerdictTrajectory(item, modelResults.map((r) => ({ verdictQuality: r.response?.verdictQuality })), { repoRoot: config.repoRoot });
   240 |     let consensusBody = verdictHeader + formatConsensusSummary(consensus, modelAdapters);
   241 |     if (enrichment && findingsPerModel.length > 0 && modelAdapters.length > 0) {
   242 |         try {
   243 |             logger.info("[multi-model] Generating enriched consensus review...");
   244 |             const enrichedContent = await generateEnrichedConsensusReview(item, consensus, modelAdapters, config, enrichment, adapters.sanitizer, adapters.logger);
   245 |             if (enrichedContent) {
   246 |                 // Prepend stats to enriched prose for quick-scan visibility
   247 |                 consensusBody = verdictHeader + formatEnrichedConsensusSummary(consensus, modelAdapters, enrichedContent);
~~~~

The change from head to the fix:

~~~~diff
@@ -235 +272,3 @@
-    })));
+    })), 
+    // (r251-4 S8, audit n21: the posted line names the voices that were not planned, and why)
+    keyStatus.notPlanned.map((np) => ({ provider: np.provider, modelId: np.modelId })), agyGate.readError !== undefined ? "Loa config unreadable — the agy gate failed closed" : "agy opt-in off: hounfour.headless.agy_opt_in");
~~~~

## H145 — .claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.js — head lines 288–289

Head context (head/.claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.js, lines 276–301):

~~~~text
   276 |         }
   277 |     }
   278 |     const combinedContent = modelResults
   279 |         .filter((r) => r.response)
   280 |         .map((r) => r.response.content)
   281 |         .join("\n\n---\n\n");
   282 |     const findings = findingsPerModel.flatMap((result) => result.findings);
   283 |     let reviewVerdict = summarizeReviewVerdict(combinedContent, findings);
   284 |     // Enrichment may surface a blocker; it cannot approve unparsed reviews.
   285 |     if (summarizeReviewVerdict(consensusBody).verdict === "REQUEST_CHANGES") {
   286 |         reviewVerdict = summarizeReviewVerdict(combinedContent + "\n" + consensusBody, findings);
   287 |     }
>  288 |     // Incomplete or degraded participation can never clear a merge.
>  289 |     if (modelResults.length !== multiConfig.models.length - keyStatus.notPlanned.length ||
   290 |         modelResults.some((result) => result.error || !result.response) ||
   291 |         computeVerdictBand(modelResults.map((result) => ({ verdictQuality: result.response?.verdictQuality }))) !== "APPROVED") {
   292 |         reviewVerdict.mergeBlocked = true;
   293 |     }
   294 |     return {
   295 |         modelResults,
   296 |         consensus,
   297 |         posted: overallPosted || modelResults.some((r) => r.posted),
   298 |         combinedContent,
   299 |         reviewVerdict,
   300 |         notPlanned: keyStatus.notPlanned,
   301 |     };
~~~~

The change from head to the fix:

~~~~diff
@@ -288,2 +327,7 @@
-    // Incomplete or degraded participation can never clear a merge.
-    if (modelResults.length !== multiConfig.models.length - keyStatus.notPlanned.length ||
+    // Incomplete or degraded participation can never clear a merge. A voice the opt-in decision removed is not expected; a
+    // voice a READ ERROR removed still is (r251-4 S1, audit n22: a host fault never shrinks the quorum).
+    if (agyGate.readError !== undefined && keyStatus.notPlanned.length > 0) {
+        reviewVerdict.mergeBlocked = true;
+        reviewVerdict.mergeBlockedReason = `Loa config unreadable (${agyGate.readError}): the agy gate failed closed and ${notPlannedList} did not run`;
+    }
+    if (modelResults.length !== multiConfig.models.length - (agyGate.readError !== undefined ? 0 : keyStatus.notPlanned.length) ||
~~~~

## H146 — .claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.js — head line 433

Head context (head/.claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.js, lines 421–445):

~~~~text
   421 |     const anyDegraded = withEnvelope.some((r) => r.verdictQuality?.status === "DEGRADED" || r.verdictQuality?.chain_health === "degraded");
   422 |     const allApproved = withEnvelope.every((r) => r.verdictQuality?.status === "APPROVED");
   423 |     // Promote to FAILED if any voice failed OR if not all voices ran (we
   424 |     // never received envelopes for the missing ones, suggesting they
   425 |     // didn't reach cheval) AND the responding voices are degraded.
   426 |     const missingVoices = total - withEnvelope.length;
   427 |     if (anyFailed || missingVoices === total)
   428 |         return "FAILED";
   429 |     if (anyDegraded || missingVoices > 0 || !allApproved)
   430 |         return "DEGRADED";
   431 |     return "APPROVED";
   432 | }
>  433 | export function formatVerdictQualityHeader(perModelResults) {
   434 |     const band = computeVerdictBand(perModelResults);
   435 |     if (band === null)
   436 |         return "";
   437 |     // Aggregate stats from per-voice envelopes. Each cheval cmd_invoke
   438 |     // produces a SINGLE-voice envelope (voices_planned=1). For the BB
   439 |     // multi-voice cohort we count the number of envelopes that ended in
   440 |     // each status.
   441 |     const total = perModelResults.length;
   442 |     const withEnvelope = perModelResults.filter((r) => r.verdictQuality);
   443 |     const succeeded = withEnvelope.filter((r) => r.verdictQuality?.status === "APPROVED" || r.verdictQuality?.status === "DEGRADED").length;
   444 |     let banner;
   445 |     if (band === "FAILED") {
~~~~

The change from head to the fix:

~~~~diff
@@ -433 +477 @@
-export function formatVerdictQualityHeader(perModelResults) {
+export function formatVerdictQualityHeader(perModelResults, notPlanned = [], notPlannedReason = "agy opt-in off: hounfour.headless.agy_opt_in") {
~~~~

## H147 — .claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.js — head line 454

Head context (head/.claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.js, lines 442–466):

~~~~text
   442 |     const withEnvelope = perModelResults.filter((r) => r.verdictQuality);
   443 |     const succeeded = withEnvelope.filter((r) => r.verdictQuality?.status === "APPROVED" || r.verdictQuality?.status === "DEGRADED").length;
   444 |     let banner;
   445 |     if (band === "FAILED") {
   446 |         banner = `❌ FAILED — ${succeeded}/${total} voices succeeded; verdict unsafe`;
   447 |     }
   448 |     else if (band === "DEGRADED") {
   449 |         banner = `⚠ DEGRADED — ${succeeded}/${total} voices succeeded`;
   450 |     }
   451 |     else {
   452 |         banner = `✓ APPROVED — ${succeeded}/${total} voices, chain ok`;
   453 |     }
>  454 |     return `**Verdict Quality**: ${banner}\n\n`;
   455 | }
   456 | /**
   457 |  * Append a degraded-verdict trajectory record when BB's aggregate multi-model
   458 |  * verdict band is DEGRADED or FAILED. No-op for APPROVED/clean/no-envelope
   459 |  * runs — mirrors degraded_verdict_maybe_emit's guard in the bash lib.
   460 |  *
   461 |  * The record is the SAME shape the 3 bash gate writers emit (adversarial-
   462 |  * review.sh, red-team-code-vs-design.sh, flatline-orchestrator.sh via
   463 |  * degraded-verdict-lib.sh) into the SAME date-sharded trajectory file, so a
   464 |  * downstream reader sees one homogeneous channel regardless of runtime.
   465 |  *
   466 |  * Scope (per bd-bb-degraded-verdict-ts-b5bu): trajectory-record emit only.
~~~~

The change from head to the fix:

~~~~diff
@@ -454 +498,4 @@
-    return `**Verdict Quality**: ${banner}\n\n`;
+    const np = notPlanned.length > 0
+        ? ` · not planned: ${notPlanned.map((n) => `${n.provider}/${n.modelId}`).join(", ")} (${notPlannedReason})`
+        : "";
+    return `**Verdict Quality**: ${banner}${np}\n\n`;
~~~~

## H148 — .claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.js.map — head line 1

Head context (head/.claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.js.map, lines 1–1):

~~~~text
>    1 | {"version":3,"file":"multi-model-pipeline.js","sourceRoot":"","sources":["../../resources/core/multi-model-pipeline.ts"],"names":[],"mappings":"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"}
~~~~

The change from head to the fix:

~~~~diff
@@ -1 +1 @@
-{"version":3,"file":"multi-model-pipeline.js","sourceRoot":"","sources":["../../resources/core/multi-model-pipeline.ts"],"names":[],"mappings":"AAAA;;;;;;GAMG;AACH,OAAO,EAAE,UAAU,EAAE,KAAK,EAAE,MAAM,kBAAkB,CAAC;AACrD,OAAO,IAAI,MAAM,WAAW,CAAC;AAa7B,OAAO,EAAE,sBAAsB,EAAsB,MAAM,qBAAqB,CAAC;AACjF,OAAO,EAAE,aAAa,EAAE,MAAM,cAAc,CAAC;AAE7C,OAAO,EAAE,aAAa,EAAE,MAAM,gCAAgC,CAAC;AAC/D,OAAO,EAAE,oBAAoB,EAAE,iBAAiB,EAAE,WAAW,EAAE,eAAe,EAAE,MAAM,cAAc,CAAC;AACrG,OAAO,EAAE,wBAAwB,EAAE,mBAAmB,EAAE,MAAM,wBAAwB,CAAC;AAGvF;;;;;;;;;;;;;;;;;;;;;;;;;GAyBG;AACH,SAAS,gBAAgB,CAAC,QAAgB,EAAE,OAAe;IACzD,gFAAgF;IAChF,8EAA8E;IAC9E,0EAA0E;IAC1E,yDAAyD;IACzD,IAAI,mBAAmB,CAAC,OAAO,CAAC,KAAK,IAAI,IAAI,wBAAwB,CAAC,OAAO,CAAC,EAAE,QAAQ,KAAK,QAAQ;QAAE,OAAO,IAAI,CAAC;IACnH,IAAI,aAAa,CAAC,IAAI,CAAC,OAAO,CAAC;QAAE,OAAO,IAAI,CAAC;IAC7C,IAAI,QAAQ,KAAK,QAAQ,IAAI,wBAAwB,CAAC,IAAI,CAAC,OAAO,CAAC;QAAE,OAAO,IAAI,CAAC;IACjF,IAAI,QAAQ,KAAK,WAAW,IAAI,OAAO,CAAC,IAAI,CAAC,OAAO,CAAC;QAAE,OAAO,IAAI,CAAC;IACnE,IAAI,QAAQ,KAAK,QAAQ,IAAI,0BAA0B,CAAC,IAAI,CAAC,OAAO,CAAC;QAAE,OAAO,IAAI,CAAC;IACnF,OAAO,KAAK,CAAC;AACf,CAAC;AAED,MAAM,UAAU,eAAe,CAC7B,QAAgB,EAChB,OAAe,EACf,MAA2B;IAE3B,IAAI,gBAAgB,CAAC,QAAQ,EAAE,OAAO,CAAC,EAAE,CAAC;QACxC,OAAO,SAAS,CAAC,CAAC,aAAa;IACjC,CAAC;IACD,kDAAkD;IAClD,OAAO,MAAM,CAAC,cAAc,GAAG,OAAO,CAAC,CAAC,CAAC,OAAO,CAAC,CAAC;QAC3C,MAAM,CAAC,cAAc,GAAG,MAAM,CAAC,CAAC,CAAC,OAAO,CAAC,CAAC;YAC1C,OAAO,CAAC;AACjB,CAAC;AA4BD;;;;;;GAMG;AACH,MAAM,UAAU,iBAAiB,CAC/B,MAAqB,EACrB,MAA2B,EAC3B,MAAe,EACf,OAAe;IAEf,IAAI,MAAM,CAAC,MAAM;QAAE,OAAO,KAAK,CAAC;IAChC,IAAI,CAAC,MAAM,CAAC,WAAW,EAAE,CAAC;QACxB,MAAM,CAAC,IAAI,CAAC,wDAAwD,OAAO,UAAU,CAAC,CAAC;QACvF,OAAO,KAAK,CAAC;IACf,CAAC;IACD,OAAO,IAAI,CAAC;AACd,CAAC;AAsBD;;;;;;;;;GASG;AACH,MAAM,CAAC,KAAK,UAAU,uBAAuB,CAC3C,IAAgB,EAChB,YAAoB,EACpB,UAAkB,EAClB,MAA2B,EAC3B,QAA0B,EAC1B,UAA8B;IAE9B,MAAM,WAAW,GAAG,MAAM,CAAC,UAAW,CAAC;IACvC,MAAM,EAAE,MAAM,EAAE,SAAS,EAAE,MAAM,EAAE,GAAG,QAAQ,CAAC;IAE/C,0FAA0F;IAC1F,MAAM,SAAS,GAAG,eAAe,CAAC,WAAW,EAAE,WAAW,CAAC,MAAM,CAAC,QAAQ,CAAC,CAAC,CAAC,IAAI,CAAC,IAAI,CAAC,MAAM,CAAC,QAAQ,EAAE,kBAAkB,CAAC,CAAC,CAAC,CAAC,kBAAkB,CAAC,CAAC,CAAC;IACnJ,KAAK,MAAM,EAAE,IAAI,SAAS,CAAC,UAAU,EAAE,CAAC;QACtC,MAAM,CAAC,IAAI,CAAC,GAAG,EAAE,CAAC,QAAQ,mEAAmE,CAAC,CAAC;IACjG,CAAC;IACD,IAAI,WAAW,CAAC,YAAY,KAAK,QAAQ,IAAI,SAAS,CAAC,OAAO,CAAC,MAAM,GAAG,CAAC,EAAE,CAAC;QAC1E,MAAM,IAAI,KAAK,CACb,gDAAgD,SAAS,CAAC,OAAO,CAAC,GAAG,CAAC,CAAC,CAAC,EAAE,EAAE,CAAC,CAAC,CAAC,QAAQ,CAAC,CAAC,IAAI,CAAC,IAAI,CAAC,EAAE,CACtG,CAAC;IACJ,CAAC;IAED,0CAA0C;IAC1C,MAAM,aAAa,GAId,EAAE,CAAC;IAER,KAAK,MAAM,KAAK,IAAI,SAAS,CAAC,KAAK,EAAE,CAAC;QACpC,MAAM,MAAM,GAAG,oBAAoB,CAAC,KAAK,CAAC,QAAQ,CAAC,CAAC;QACpD,qGAAqG;QACrG,MAAM,MAAM,GAAG,CAAC,MAAM,CAAC,CAAC,CAAC,OAAO,CAAC,GAAG,CAAC,MAAM,CAAC,CAAC,CAAC,CAAC,SAAS,CAAC,IAAI,EAAE,CAAC;QAChE,IAAI,CAAC,MAAM,IAAI,CAAC,iBAAiB,CAAC,KAAK,CAAC,OAAO,EAAE,KAAK,CAAC,QAAQ,CAAC;YAAE,SAAS;QAE3E,MAAM,SAAS,GAAG,WAAW,CAAC,UAAU,EAAE,CAAC,KAAK,CAAC,QAAQ,CAAC,CAAC;QAC3D,MAAM,OAAO,GAAG,aAAa,CAAC;YAC5B,QAAQ,EAAE,KAAK,CAAC,QAAQ;YACxB,OAAO,EAAE,KAAK,CAAC,OAAO;YACtB,MAAM;YACN,SAAS,EAAE,eAAe,CAAC,KAAK,CAAC,QAAQ,EAAE,KAAK,CAAC,OAAO,EAAE,MAAM,CAAC;YACjE,SAAS;SACV,CAAC,CAAC;QAEH,aAAa,CAAC,IAAI,CAAC;YACjB,QAAQ,EAAE,KAAK,CAAC,QAAQ;YACxB,OAAO,EAAE,KAAK,CAAC,OAAO;YACtB,OAAO;SACR,CAAC,CAAC;IACL,CAAC;IAED,IAAI,aAAa,CAAC,MAAM,KAAK,CAAC,EAAE,CAAC;QAC/B,MAAM,IAAI,KAAK,CAAC,mEAAmE,CAAC,CAAC;IACvF,CAAC;IAED,oBAAoB;IACpB,MAAM,WAAW,GAAG,IAAI,CAAC,GAAG,CAC1B,aAAa,CAAC,MAAM,EACpB,WAAW,CAAC,eAAe,IAAI,CAAC,CACjC,CAAC;IAEF,MAAM,CAAC,IAAI,CAAC,wCAAwC,EAAE;QACpD,MAAM,EAAE,aAAa,CAAC,GAAG,CAAC,CAAC,CAAC,EAAE,EAAE,CAAC,GAAG,CAAC,CAAC,QAAQ,IAAI,CAAC,CAAC,OAAO,EAAE,CAAC;QAC9D,WAAW;KACZ,CAAC,CAAC;IAEH,qDAAqD;IACrD,MAAM,OAAO,GAAkB;QAC7B,YAAY;QACZ,UAAU;QACV,eAAe,EAAE,MAAM,CAAC,eAAe;KACxC,CAAC;IAEF,MAAM,OAAO,GAAG,MAAM,sBAAsB,CAC1C,aAAa,EACb,KAAK,EAAE,EAAE,EAAE,EAAE;QACX,MAAM,CAAC,IAAI,CAAC,gBAAgB,EAAE,CAAC,QAAQ,sBAAsB,CAAC,CAAC;QAC/D,MAAM,OAAO,GAAG,IAAI,CAAC,GAAG,EAAE,CAAC;QAC3B,MAAM,QAAQ,GAAG,MAAM,EAAE,CAAC,OAAO,CAAC,cAAc,CAAC,OAAO,CAAC,CAAC;QAC1D,MAAM,SAAS,GAAG,IAAI,CAAC,GAAG,EAAE,GAAG,OAAO,CAAC;QACvC,MAAM,CAAC,IAAI,CAAC,gBAAgB,EAAE,CAAC,QAAQ,YAAY,EAAE;YACnD,SAAS;YACT,WAAW,EAAE,QAAQ,CAAC,WAAW;YACjC,YAAY,EAAE,QAAQ,CAAC,YAAY;SACpC,CAAC,CAAC;QACH,OAAO,QAAQ,CAAC;IAClB,CAAC,EACD,WAAW,CACZ,CAAC;IAEF,kBAAkB;IAClB,MAAM,YAAY,GAA2C,EAAE,CAAC;IAChE,MAAM,gBAAgB,GAAoB,EAAE,CAAC;IAE7C,KAAK,IAAI,CAAC,GAAG,CAAC,EAAE,CAAC,GAAG,aAAa,CAAC,MAAM,EAAE,CAAC,EAAE,EAAE,CAAC;QAC9C,MAAM,EAAE,GAAG,aAAa,CAAC,CAAC,CAAC,CAAC;QAC5B,MAAM,MAAM,GAAG,OAAO,CAAC,CAAC,CAAC,CAAC;QAE1B,IAAI,MAAM,CAAC,MAAM,KAAK,WAAW,EAAE,CAAC;YAClC,MAAM,QAAQ,GAAG,MAAM,CAAC,KAAK,CAAC;YAE9B,WAAW;YACX,MAAM,SAAS,GAAG,SAAS,CAAC,QAAQ,CAAC,QAAQ,CAAC,OAAO,CAAC,CAAC;YACvD,MAAM,YAAY,GAAG,SAAS,CAAC,IAAI,CAAC,CAAC,CAAC,QAAQ,CAAC,OAAO,CAAC,CAAC,CAAC,SAAS,CAAC,gBAAgB,CAAC;YAEpF,gCAAgC;YAChC,MAAM,QAAQ,GAAG,0BAA0B,CAAC,YAAY,CAAC,CAAC;YAE1D,gBAAgB,CAAC,IAAI,CAAC;gBACpB,QAAQ,EAAE,EAAE,CAAC,QAAQ;gBACrB,KAAK,EAAE,EAAE,CAAC,OAAO;gBACjB,QAAQ;aACT,CAAC,CAAC;YAEH,yBAAyB;YACzB,IAAI,MAAM,GAAG,KAAK,CAAC;YACnB,IAAI,iBAAiB,CAAC,MAAM,EAAE,MAAM,EAAE,MAAM,EAAE,mBAAmB,CAAC,IAAI,MAAM,CAAC,WAAW,EAAE,CAAC;gBACzF,IAAI,CAAC;oBACH,MAAM,WAAW,GAAG,kBAAkB,CACpC,EAAE,CAAC,QAAQ,EACX,EAAE,CAAC,OAAO,EACV,YAAY,EACZ,CAAC,GAAG,CAAC,EACL,aAAa,CAAC,MAAM,CACrB,CAAC;oBACF,MAAM,GAAG,MAAM,MAAM,CAAC,WAAW,CAAC;wBAChC,KAAK,EAAE,IAAI,CAAC,KAAK;wBACjB,IAAI,EAAE,IAAI,CAAC,IAAI;wBACf,QAAQ,EAAE,IAAI,CAAC,EAAE,CAAC,MAAM;wBACxB,IAAI,EAAE,WAAW;qBAClB,CAAC,CAAC;gBACL,CAAC;gBAAC,OAAO,GAAG,EAAE,CAAC;oBACb,MAAM,CAAC,IAAI,CAAC,gBAAgB,EAAE,CAAC,QAAQ,0BAA0B,EAAE;wBACjE,KAAK,EAAG,GAAa,CAAC,OAAO;qBAC9B,CAAC,CAAC;gBACL,CAAC;YACH,CAAC;YAED,YAAY,CAAC,IAAI,CAAC;gBAChB,QAAQ,EAAE,EAAE,CAAC,QAAQ;gBACrB,KAAK,EAAE,EAAE,CAAC,OAAO;gBACjB,QAAQ;gBACR,MAAM;aACP,CAAC,CAAC;QACL,CAAC;aAAM,CAAC;YACN,MAAM,KAAK,GAAgB;gBACzB,IAAI,EAAE,gBAAgB;gBACtB,OAAO,EAAE,MAAM,CAAC,MAAM,YAAY,KAAK,CAAC,CAAC,CAAC,MAAM,CAAC,MAAM,CAAC,OAAO,CAAC,CAAC,CAAC,MAAM,CAAC,MAAM,CAAC,MAAM,CAAC;gBACvF,QAAQ,EAAE,WAAW;gBACrB,SAAS,EAAE,IAAI;gBACf,MAAM,EAAE,KAAK;aACd,CAAC;YAEF,MAAM,CAAC,IAAI,CAAC,gBAAgB,EAAE,CAAC,QAAQ,iBAAiB,EAAE;gBACxD,KAAK,EAAE,KAAK,CAAC,OAAO;aACrB,CAAC,CAAC;YAEH,YAAY,CAAC,IAAI,CAAC;gBAChB,QAAQ,EAAE,EAAE,CAAC,QAAQ;gBACrB,KAAK,EAAE,EAAE,CAAC,OAAO;gBACjB,KAAK;gBACL,MAAM,EAAE,KAAK;aACd,CAAC,CAAC;QACL,CAAC;IACH,CAAC;IAED,+BAA+B;IAC/B,MAAM,SAAS,GAAG,aAAa,CAC7B,gBAAgB,EAChB,WAAW,CAAC,SAAS,CAAC,kBAAkB,CACzC,CAAC;IAEF,MAAM,CAAC,IAAI,CAAC,0CAA0C,EAAE;QACtD,cAAc,EAAE,SAAS,CAAC,KAAK,CAAC,cAAc;QAC9C,QAAQ,EAAE,SAAS,CAAC,KAAK,CAAC,QAAQ;QAClC,OAAO,EAAE,SAAS,CAAC,KAAK,CAAC,OAAO;QAChC,MAAM,EAAE,SAAS,CAAC,KAAK,CAAC,MAAM;KAC/B,CAAC,CAAC;IAEH,0EAA0E;IAC1E,2EAA2E;IAC3E,6EAA6E;IAC7E,wBAAwB;IACxB,+DAA+D;IAC/D,uEAAuE;IACvE,iEAAiE;IACjE,oDAAoD;IACpD,MAAM,aAAa,GAAG,0BAA0B,CAC9C,YAAY,CAAC,GAAG,CAAC,CAAC,CAAC,EAAE,EAAE,CAAC,CAAC;QACvB,QAAQ,EAAE,CAAC,CAAC,QAAQ;QACpB,OAAO,EAAE,CAAC,CAAC,KAAK;QAChB,cAAc,EAAE,CAAC,CAAC,QAAQ,EAAE,cAAc;KAC3C,CAAC,CAAC,CACJ,CAAC;IACF,4EAA4E;IAC5E,0EAA0E;IAC1E,mEAAmE;IACnE,MAAM,6BAA6B,CACjC,IAAI,EACJ,YAAY,CAAC,GAAG,CAAC,CAAC,CAAC,EAAE,EAAE,CAAC,CAAC,EAAE,cAAc,EAAE,CAAC,CAAC,QAAQ,EAAE,cAAc,EAAE,CAAC,CAAC,EACzE,EAAE,QAAQ,EAAE,MAAM,CAAC,QAAQ,EAAE,CAC9B,CAAC;IACF,IAAI,aAAa,GAAG,aAAa,GAAG,sBAAsB,CAAC,SAAS,EAAE,aAAa,CAAC,CAAC;IAErF,IAAI,UAAU,IAAI,gBAAgB,CAAC,MAAM,GAAG,CAAC,IAAI,aAAa,CAAC,MAAM,GAAG,CAAC,EAAE,CAAC;QAC1E,IAAI,CAAC;YACH,MAAM,CAAC,IAAI,CAAC,uDAAuD,CAAC,CAAC;YACrE,MAAM,eAAe,GAAG,MAAM,+BAA+B,CAC3D,IAAI,EACJ,SAAS,EACT,aAAa,EACb,MAAM,EACN,UAAU,EACV,QAAQ,CAAC,SAAS,EAClB,QAAQ,CAAC,MAAM,CAChB,CAAC;YACF,IAAI,eAAe,EAAE,CAAC;gBACpB,4DAA4D;gBAC5D,aAAa,GAAG,aAAa,GAAG,8BAA8B,CAAC,SAAS,EAAE,aAAa,EAAE,eAAe,CAAC,CAAC;gBAC1G,MAAM,CAAC,IAAI,CAAC,mCAAmC,EAAE;oBAC/C,aAAa,EAAE,eAAe,CAAC,MAAM;iBACtC,CAAC,CAAC;YACL,CAAC;QACH,CAAC;QAAC,OAAO,GAAG,EAAE,CAAC;YACb,MAAM,CAAC,IAAI,CAAC,2DAA2D,EAAE;gBACvE,KAAK,EAAG,GAAa,CAAC,OAAO;aAC9B,CAAC,CAAC;QACL,CAAC;IACH,CAAC;IAED,iCAAiC;IACjC,IAAI,aAAa,GAAG,KAAK,CAAC;IAC1B,IACE,iBAAiB,CAAC,MAAM,EAAE,MAAM,EAAE,MAAM,EAAE,mBAAmB,CAAC;QAC9D,MAAM,CAAC,WAAW;QAClB,gBAAgB,CAAC,MAAM,GAAG,CAAC,EAC3B,CAAC;QACD,IAAI,CAAC;YACH,aAAa,GAAG,MAAM,MAAM,CAAC,WAAW,CAAC;gBACvC,KAAK,EAAE,IAAI,CAAC,KAAK;gBACjB,IAAI,EAAE,IAAI,CAAC,IAAI;gBACf,QAAQ,EAAE,IAAI,CAAC,EAAE,CAAC,MAAM;gBACxB,IAAI,EAAE,aAAa;aACpB,CAAC,CAAC;QACL,CAAC;QAAC,OAAO,GAAG,EAAE,CAAC;YACb,MAAM,CAAC,IAAI,CAAC,gDAAgD,EAAE;gBAC5D,KAAK,EAAG,GAAa,CAAC,OAAO;aAC9B,CAAC,CAAC;QACL,CAAC;IACH,CAAC;IAED,MAAM,eAAe,GAAG,YAAY;SACjC,MAAM,CAAC,CAAC,CAAC,EAAE,EAAE,CAAC,CAAC,CAAC,QAAQ,CAAC;SACzB,GAAG,CAAC,CAAC,CAAC,EAAE,EAAE,CAAC,CAAC,CAAC,QAAS,CAAC,OAAO,CAAC;SAC/B,IAAI,CAAC,aAAa,CAAC,CAAC;IACvB,MAAM,QAAQ,GAAG,gBAAgB,CAAC,OAAO,CAAC,CAAC,MAAM,EAAE,EAAE,CAAC,MAAM,CAAC,QAAQ,CAAC,CAAC;IACvE,IAAI,aAAa,GAAG,sBAAsB,CAAC,eAAe,EAAE,QAAQ,CAAC,CAAC;IACtE,wEAAwE;IACxE,IAAI,sBAAsB,CAAC,aAAa,CAAC,CAAC,OAAO,KAAK,iBAAiB,EAAE,CAAC;QACxE,aAAa,GAAG,sBAAsB,CAAC,eAAe,GAAG,IAAI,GAAG,aAAa,EAAE,QAAQ,CAAC,CAAC;IAC3F,CAAC;IACD,gEAAgE;IAChE,IAAI,YAAY,CAAC,MAAM,KAAK,WAAW,CAAC,MAAM,CAAC,MAAM,GAAG,SAAS,CAAC,UAAU,CAAC,MAAM;QAC/E,YAAY,CAAC,IAAI,CAAC,CAAC,MAAM,EAAE,EAAE,CAAC,MAAM,CAAC,KAAK,IAAI,CAAC,MAAM,CAAC,QAAQ,CAAC;QAC/D,kBAAkB,CAAC,YAAY,CAAC,GAAG,CAAC,CAAC,MAAM,EAAE,EAAE,CAAC,CAAC,EAAE,cAAc,EAAE,MAAM,CAAC,QAAQ,EAAE,cAAc,EAAE,CAAC,CAAC,CAAC,KAAK,UAAU,EAAE,CAAC;QAC3H,aAAa,CAAC,YAAY,GAAG,IAAI,CAAC;IACpC,CAAC;IAED,OAAO;QACL,YAAY;QACZ,SAAS;QACT,MAAM,EAAE,aAAa,IAAI,YAAY,CAAC,IAAI,CAAC,CAAC,CAAC,EAAE,EAAE,CAAC,CAAC,CAAC,MAAM,CAAC;QAC3D,eAAe;QACf,aAAa;QACb,UAAU,EAAE,SAAS,CAAC,UAAU;KACjC,CAAC;AACJ,CAAC;AAED;;GAEG;AACH,KAAK,UAAU,sBAAsB,CACnC,KAAU,EACV,EAA2B,EAC3B,WAAmB;IAEnB,IAAI,KAAK,CAAC,MAAM,IAAI,WAAW,EAAE,CAAC;QAChC,OAAO,OAAO,CAAC,UAAU,CAAC,KAAK,CAAC,GAAG,CAAC,EAAE,CAAC,CAAC,CAAC;IAC3C,CAAC;IAED,MAAM,OAAO,GAA8B,IAAI,KAAK,CAAC,KAAK,CAAC,MAAM,CAAC,CAAC;IACnE,IAAI,SAAS,GAAG,CAAC,CAAC;IAElB,KAAK,UAAU,MAAM;QACnB,OAAO,SAAS,GAAG,KAAK,CAAC,MAAM,EAAE,CAAC;YAChC,MAAM,KAAK,GAAG,SAAS,EAAE,CAAC;YAC1B,IAAI,CAAC;gBACH,OAAO,CAAC,KAAK,CAAC,GAAG,EAAE,MAAM,EAAE,WAAW,EAAE,KAAK,EAAE,MAAM,EAAE,CAAC,KAAK,CAAC,KAAK,CAAC,CAAC,EAAE,CAAC;YAC1E,CAAC;YAAC,OAAO,MAAM,EAAE,CAAC;gBAChB,OAAO,CAAC,KAAK,CAAC,GAAG,EAAE,MAAM,EAAE,UAAU,EAAE,MAAM,EAAE,CAAC;YAClD,CAAC;QACH,CAAC;IACH,CAAC;IAED,MAAM,OAAO,GAAG,KAAK,CAAC,IAAI,CAAC,EAAE,MAAM,EAAE,IAAI,CAAC,GAAG,CAAC,WAAW,EAAE,KAAK,CAAC,MAAM,CAAC,EAAE,EAAE,GAAG,EAAE,CAAC,MAAM,EAAE,CAAC,CAAC;IAC5F,MAAM,OAAO,CAAC,GAAG,CAAC,OAAO,CAAC,CAAC;IAE3B,OAAO,OAAO,CAAC;AACjB,CAAC;AAED;;;GAGG;AACH,MAAM,UAAU,0BAA0B,CAAC,OAAe;IAWxD,MAAM,KAAK,GAAG,OAAO,CAAC,KAAK,CACzB,iGAAiG,CAClG,CAAC;IACF,IAAI,CAAC,KAAK;QAAE,OAAO,EAAE,CAAC;IAEtB,IAAI,CAAC;QACH,MAAM,MAAM,GAAG,IAAI,CAAC,KAAK,CAAC,KAAK,CAAC,CAAC,CAAC,CAAC,CAAC;QACpC,IAAI,MAAM,CAAC,QAAQ,IAAI,KAAK,CAAC,OAAO,CAAC,MAAM,CAAC,QAAQ,CAAC,EAAE,CAAC;YACtD,OAAO,MAAM,CAAC,QAAQ,CAAC;QACzB,CAAC;IACH,CAAC;IAAC,MAAM,CAAC;QACP,oCAAoC;IACtC,CAAC;IAED,OAAO,EAAE,CAAC;AACZ,CAAC;AAED;;GAEG;AACH;;;;;;;;;;;;;;;;;;;;;GAqBG;AACH;;;;;;;;;;GAUG;AACH,MAAM,UAAU,6BAA6B,CAC3C,eAUE;IAEF,MAAM,OAAO,GAAG,eAAe,CAAC,MAAM,CAAC,CAAC,CAAC,EAAE,EAAE,CAAC,CAAC,CAAC,aAAa,EAAE,OAAO,KAAK,IAAI,CAAC,CAAC;IACjF,IAAI,OAAO,CAAC,MAAM,KAAK,CAAC;QAAE,OAAO,EAAE,CAAC;IAEpC,gDAAgD;IAChD,MAAM,WAAW,GAAG,OAAO,CAAC,MAAM,CAChC,CAAC,GAAG,EAAE,CAAC,EAAE,EAAE,CAAC,GAAG,GAAG,CAAC,CAAC,CAAC,aAAa,EAAE,eAAe,IAAI,CAAC,CAAC,EAAE,CAAC,CAC7D,CAAC;IACF,MAAM,YAAY,GAAG,OAAO,CAAC,MAAM,CACjC,CAAC,GAAG,EAAE,CAAC,EAAE,EAAE,CAAC,GAAG,GAAG,CAAC,CAAC,CAAC,aAAa,EAAE,cAAc,IAAI,CAAC,CAAC,EAAE,CAAC,CAC5D,CAAC;IACF,MAAM,iBAAiB,GAAG,OAAO,CAAC,MAAM,CACtC,CAAC,GAAG,EAAE,CAAC,EAAE,EAAE,CAAC,GAAG,GAAG,CAAC,CAAC,CAAC,aAAa,EAAE,oBAAoB,IAAI,CAAC,CAAC,EAAE,CAAC,CAClE,CAAC;IACF,MAAM,iBAAiB,GAAG,OAAO,CAAC,IAAI,CACpC,CAAC,CAAC,EAAE,EAAE,CAAC,CAAC,CAAC,aAAa,EAAE,gBAAgB,KAAK,IAAI,CAClD,CAAC;IAEF,MAAM,KAAK,GAAa;QACtB,uBAAuB,OAAO,CAAC,MAAM,SAAS,OAAO,CAAC,MAAM,GAAG,CAAC,CAAC,CAAC,CAAC,GAAG,CAAC,CAAC,CAAC,EAAE,+DAA+D;QAC1I,4BAA4B,WAAW,EAAE;YACvC,CAAC,YAAY,GAAG,CAAC,CAAC,CAAC,CAAC,OAAO,YAAY,WAAW,CAAC,CAAC,CAAC,EAAE,CAAC;YACxD,MAAM,iBAAiB,oBAAoB;KAC9C,CAAC;IACF,IAAI,iBAAiB,EAAE,CAAC;QACtB,KAAK,CAAC,IAAI,CAAC,yDAAyD,CAAC,CAAC;IACxE,CAAC;IACD,OAAO,KAAK,CAAC,IAAI,CAAC,IAAI,CAAC,GAAG,MAAM,CAAC;AACnC,CAAC;AAED;;;;;;;;;;GAUG;AACH,MAAM,UAAU,kBAAkB,CAChC,eAEE;IAEF,IAAI,eAAe,CAAC,MAAM,KAAK,CAAC;QAAE,OAAO,IAAI,CAAC;IAE9C,MAAM,YAAY,GAAG,eAAe,CAAC,MAAM,CAAC,CAAC,CAAC,EAAE,EAAE,CAAC,CAAC,CAAC,cAAc,CAAC,CAAC;IACrE,IAAI,YAAY,CAAC,MAAM,KAAK,CAAC;QAAE,OAAO,IAAI,CAAC;IAE3C,MAAM,KAAK,GAAG,eAAe,CAAC,MAAM,CAAC;IACrC,MAAM,SAAS,GAAG,YAAY,CAAC,IAAI,CAAC,CAAC,CAAC,EAAE,EAAE,CAAC,CAAC,CAAC,cAAc,EAAE,MAAM,KAAK,QAAQ,CAAC,CAAC;IAClF,MAAM,WAAW,GAAG,YAAY,CAAC,IAAI,CACnC,CAAC,CAAC,EAAE,EAAE,CAAC,CAAC,CAAC,cAAc,EAAE,MAAM,KAAK,UAAU,IAAI,CAAC,CAAC,cAAc,EAAE,YAAY,KAAK,UAAU,CAChG,CAAC;IACF,MAAM,WAAW,GAAG,YAAY,CAAC,KAAK,CAAC,CAAC,CAAC,EAAE,EAAE,CAAC,CAAC,CAAC,cAAc,EAAE,MAAM,KAAK,UAAU,CAAC,CAAC;IAEvF,qEAAqE;IACrE,iEAAiE;IACjE,+DAA+D;IAC/D,MAAM,aAAa,GAAG,KAAK,GAAG,YAAY,CAAC,MAAM,CAAC;IAElD,IAAI,SAAS,IAAI,aAAa,KAAK,KAAK;QAAE,OAAO,QAAQ,CAAC;IAC1D,IAAI,WAAW,IAAI,aAAa,GAAG,CAAC,IAAI,CAAC,WAAW;QAAE,OAAO,UAAU,CAAC;IACxE,OAAO,UAAU,CAAC;AACpB,CAAC;AAED,MAAM,UAAU,0BAA0B,CACxC,eASE;IAEF,MAAM,IAAI,GAAG,kBAAkB,CAAC,eAAe,CAAC,CAAC;IACjD,IAAI,IAAI,KAAK,IAAI;QAAE,OAAO,EAAE,CAAC;IAE7B,mEAAmE;IACnE,kEAAkE;IAClE,oEAAoE;IACpE,eAAe;IACf,MAAM,KAAK,GAAG,eAAe,CAAC,MAAM,CAAC;IACrC,MAAM,YAAY,GAAG,eAAe,CAAC,MAAM,CAAC,CAAC,CAAC,EAAE,EAAE,CAAC,CAAC,CAAC,cAAc,CAAC,CAAC;IACrE,MAAM,SAAS,GAAG,YAAY,CAAC,MAAM,CACnC,CAAC,CAAC,EAAE,EAAE,CAAC,CAAC,CAAC,cAAc,EAAE,MAAM,KAAK,UAAU,IAAI,CAAC,CAAC,cAAc,EAAE,MAAM,KAAK,UAAU,CAC1F,CAAC,MAAM,CAAC;IAET,IAAI,MAAc,CAAC;IACnB,IAAI,IAAI,KAAK,QAAQ,EAAE,CAAC;QACtB,MAAM,GAAG,cAAc,SAAS,IAAI,KAAK,mCAAmC,CAAC;IAC/E,CAAC;SAAM,IAAI,IAAI,KAAK,UAAU,EAAE,CAAC;QAC/B,MAAM,GAAG,gBAAgB,SAAS,IAAI,KAAK,mBAAmB,CAAC;IACjE,CAAC;SAAM,CAAC;QACN,MAAM,GAAG,gBAAgB,SAAS,IAAI,KAAK,mBAAmB,CAAC;IACjE,CAAC;IAED,OAAO,wBAAwB,MAAM,MAAM,CAAC;AAC9C,CAAC;AAmBD;;;;;;;;;;;;;;;;;;;;;GAqBG;AACH,MAAM,CAAC,KAAK,UAAU,6BAA6B,CACjD,IAA6D,EAC7D,eAAmE,EACnE,IAA2C;IAE3C,MAAM,IAAI,GAAG,kBAAkB,CAAC,eAAe,CAAC,CAAC;IACjD,IAAI,IAAI,KAAK,UAAU,IAAI,IAAI,KAAK,QAAQ;QAAE,OAAO;IAErD,4EAA4E;IAC5E,uEAAuE;IACvE,2EAA2E;IAC3E,4EAA4E;IAC5E,MAAM,UAAU,GAAG,eAAe,CAAC,OAAO,CAAC,CAAC,CAAC,EAAE,EAAE,CAAC,CAAC,CAAC,cAAc,EAAE,cAAc,IAAI,EAAE,CAAC,CAAC;IAC1F,MAAM,YAAY,GAAG,UAAU,CAAC,MAAM,GAAG,CAAC,CAAC,CAAC,CAAC,UAAU,CAAC,GAAG,CAAC,CAAC,CAAC,EAAE,EAAE,CAAC,CAAC,CAAC,KAAK,CAAC,CAAC,CAAC,CAAC,SAAS,CAAC;IACxF,MAAM,iBAAiB,GAAG,UAAU,CAAC,CAAC,CAAC,EAAE,MAAM,IAAI,SAAS,CAAC;IAC7D,MAAM,aAAa,GAAG,UAAU,CAAC,CAAC,CAAC,EAAE,SAAS,IAAI,IAAI,CAAC;IACvD,MAAM,IAAI,GAAG,IAAI,EAAE,IAAI,IAAI,2BAA2B,CAAC;IACvD,MAAM,QAAQ,GAAG,GAAG,IAAI,CAAC,KAAK,IAAI,IAAI,CAAC,IAAI,IAAI,IAAI,CAAC,EAAE,CAAC,MAAM,EAAE,CAAC;IAEhE,MAAM,MAAM,GAA0B;QACpC,IAAI;QACJ,YAAY,EAAE,IAAI;QAClB,kBAAkB,EAAE,iBAAiB;QACrC,GAAG,CAAC,YAAY,CAAC,CAAC,CAAC,EAAE,aAAa,EAAE,YAAY,EAAE,CAAC,CAAC,CAAC,EAAE,CAAC;QACxD,eAAe,EAAE,aAAa;QAC9B,SAAS,EAAE,QAAQ;QACnB,EAAE,EAAE,IAAI,IAAI,EAAE,CAAC,WAAW,EAAE;KAC7B,CAAC;IAEF,MAAM,GAAG,GACP,OAAO,CAAC,GAAG,CAAC,wBAAwB;QACpC,IAAI,CAAC,IAAI,CAAC,IAAI,EAAE,QAAQ,IAAI,OAAO,CAAC,GAAG,EAAE,EAAE,8BAA8B,CAAC,CAAC;IAC7E,MAAM,SAAS,GAAG,IAAI,IAAI,EAAE,CAAC,WAAW,EAAE,CAAC,KAAK,CAAC,CAAC,EAAE,EAAE,CAAC,CAAC;IACxD,MAAM,IAAI,GAAG,IAAI,CAAC,IAAI,CAAC,GAAG,EAAE,oBAAoB,SAAS,QAAQ,CAAC,CAAC;IACnE,IAAI,CAAC;QACH,MAAM,KAAK,CAAC,GAAG,EAAE,EAAE,SAAS,EAAE,IAAI,EAAE,CAAC,CAAC;QACtC,MAAM,UAAU,CAAC,IAAI,EAAE,IAAI,CAAC,SAAS,CAAC,MAAM,CAAC,GAAG,IAAI,CAAC,CAAC;IACxD,CAAC;IAAC,MAAM,CAAC;QACP,2EAA2E;IAC7E,CAAC;AACH,CAAC;AAED,SAAS,kBAAkB,CACzB,QAAgB,EAChB,OAAe,EACf,OAAe,EACf,KAAa,EACb,KAAa;IAEb,MAAM,MAAM,GAAG,KAAK,GAAG,CAAC;QACtB,CAAC,CAAC,MAAM,KAAK,IAAI,KAAK,GAAG,CAAC,eAAe,QAAQ,KAAK,OAAO,SAAS;QACtE,CAAC,CAAC,eAAe,QAAQ,KAAK,OAAO,SAAS,CAAC;IAEjD,OAAO,MAAM,GAAG,OAAO,CAAC;AAC1B,CAAC;AAED;;GAEG;AACH,SAAS,sBAAsB,CAC7B,MAAqB,EACrB,MAAoD;IAEpD,MAAM,KAAK,GAAa,EAAE,CAAC;IAC3B,MAAM,KAAK,GAAG,MAAM,CAAC,MAAM,GAAG,CAAC,CAAC,CAAC,wBAAwB;IAEzD,KAAK,CAAC,IAAI,CAAC,MAAM,KAAK,IAAI,KAAK,mCAAmC,CAAC,CAAC;IACpE,KAAK,CAAC,IAAI,CAAC,EAAE,CAAC,CAAC;IACf,KAAK,CAAC,IAAI,CAAC,WAAW,MAAM,CAAC,GAAG,CAAC,CAAC,CAAC,EAAE,EAAE,CAAC,GAAG,CAAC,CAAC,QAAQ,IAAI,CAAC,CAAC,OAAO,EAAE,CAAC,CAAC,IAAI,CAAC,IAAI,CAAC,EAAE,CAAC,CAAC;IACpF,KAAK,CAAC,IAAI,CAAC,EAAE,CAAC,CAAC;IAEf,cAAc;IACd,KAAK,CAAC,IAAI,CAAC,4BAA4B,CAAC,CAAC;IACzC,KAAK,CAAC,IAAI,CAAC,WAAW,CAAC,CAAC;IACxB,KAAK,CAAC,IAAI,CAAC,sBAAsB,MAAM,CAAC,KAAK,CAAC,cAAc,IAAI,CAAC,CAAC;IAClE,KAAK,CAAC,IAAI,CAAC,gBAAgB,MAAM,CAAC,KAAK,CAAC,QAAQ,IAAI,CAAC,CAAC;IACtD,KAAK,CAAC,IAAI,CAAC,eAAe,MAAM,CAAC,KAAK,CAAC,OAAO,IAAI,CAAC,CAAC;IACpD,KAAK,CAAC,IAAI,CAAC,iBAAiB,MAAM,CAAC,KAAK,CAAC,SAAS,IAAI,CAAC,CAAC;IACxD,KAAK,CAAC,IAAI,CAAC,2BAA2B,MAAM,CAAC,KAAK,CAAC,MAAM,IAAI,CAAC,CAAC;IAC/D,KAAK,CAAC,IAAI,CAAC,EAAE,CAAC,CAAC;IAEf,mBAAmB;IACnB,MAAM,QAAQ,GAAG,MAAM,CAAC,WAAW,CAAC,MAAM,CAAC,CAAC,CAAC,EAAE,EAAE,CAAC,CAAC,CAAC,cAAc,KAAK,SAAS,CAAC,CAAC;IAClF,IAAI,QAAQ,CAAC,MAAM,GAAG,CAAC,EAAE,CAAC;QACxB,KAAK,CAAC,IAAI,CAAC,cAAc,CAAC,CAAC;QAC3B,KAAK,MAAM,CAAC,IAAI,QAAQ,EAAE,CAAC;YACzB,KAAK,CAAC,IAAI,CAAC,OAAO,CAAC,CAAC,OAAO,CAAC,KAAK,OAAO,CAAC,CAAC,OAAO,CAAC,IAAI,IAAI,SAAS,iBAAiB,CAAC,CAAC,eAAe,CAAC,IAAI,CAAC,IAAI,CAAC,EAAE,CAAC,CAAC;QACtH,CAAC;QACD,KAAK,CAAC,IAAI,CAAC,EAAE,CAAC,CAAC;IACjB,CAAC;IAED,0BAA0B;IAC1B,MAAM,aAAa,GAAG,MAAM,CAAC,WAAW,CAAC,MAAM,CAAC,CAAC,CAAC,EAAE,EAAE,CAAC,CAAC,CAAC,cAAc,KAAK,gBAAgB,CAAC,CAAC;IAC9F,IAAI,aAAa,CAAC,MAAM,GAAG,CAAC,EAAE,CAAC;QAC7B,KAAK,CAAC,IAAI,CAAC,oBAAoB,CAAC,CAAC;QACjC,KAAK,MAAM,CAAC,IAAI,aAAa,EAAE,CAAC;YAC9B,MAAM,MAAM,GAAG,CAAC,CAAC,eAAe,CAAC,MAAM,GAAG,CAAC,CAAC,CAAC,CAAC,KAAK,CAAC,CAAC,eAAe,CAAC,IAAI,CAAC,IAAI,CAAC,GAAG,CAAC,CAAC,CAAC,EAAE,CAAC;YACxF,KAAK,CAAC,IAAI,CAAC,OAAO,CAAC,CAAC,OAAO,CAAC,QAAQ,OAAO,CAAC,CAAC,OAAO,CAAC,KAAK,GAAG,MAAM,EAAE,CAAC,CAAC;QACzE,CAAC;QACD,KAAK,CAAC,IAAI,CAAC,EAAE,CAAC,CAAC;IACjB,CAAC;IAED,oBAAoB;IACpB,MAAM,QAAQ,GAAG,MAAM,CAAC,WAAW,CAAC,MAAM,CAAC,CAAC,CAAC,EAAE,EAAE,CAAC,CAAC,CAAC,cAAc,KAAK,UAAU,CAAC,CAAC;IACnF,IAAI,QAAQ,CAAC,MAAM,GAAG,CAAC,EAAE,CAAC;QACxB,KAAK,CAAC,IAAI,CAAC,cAAc,CAAC,CAAC;QAC3B,KAAK,MAAM,CAAC,IAAI,QAAQ,EAAE,CAAC;YACzB,KAAK,CAAC,IAAI,CAAC,OAAO,CAAC,CAAC,OAAO,CAAC,KAAK,qBAAqB,CAAC,CAAC,WAAW,KAAK,CAAC,CAAC,eAAe,CAAC,IAAI,CAAC,MAAM,CAAC,GAAG,CAAC,CAAC;QAC7G,CAAC;QACD,KAAK,CAAC,IAAI,CAAC,EAAE,CAAC,CAAC;IACjB,CAAC;IAED,OAAO,KAAK,CAAC,IAAI,CAAC,IAAI,CAAC,CAAC;AAC1B,CAAC;AAED;;;;;;;;GAQG;AACH,KAAK,UAAU,+BAA+B,CAC5C,IAAgB,EAChB,SAAwB,EACxB,aAAkF,EAClF,MAA2B,EAC3B,UAA6B,EAC7B,SAA2B,EAC3B,MAAe;IAEf,6EAA6E;IAC7E,MAAM,WAAW,GAAG,MAAM,CAAC,UAAW,CAAC;IACvC,MAAM,YAAY,GAAG,WAAW,CAAC,MAAM,CAAC,IAAI,CAAC,CAAC,CAAC,EAAE,EAAE,CAAC,CAAC,CAAC,IAAI,KAAK,SAAS,CAAC,CAAC;IAC1E,MAAM,YAAY,GAAG,YAAY,IAAI,WAAW,CAAC,MAAM,CAAC,CAAC,CAAC,CAAC;IAC3D,MAAM,MAAM,GAAG,aAAa,CAAC,IAAI,CAC/B,CAAC,CAAC,EAAE,EAAE,CAAC,CAAC,CAAC,QAAQ,KAAK,YAAY,CAAC,QAAQ,IAAI,CAAC,CAAC,OAAO,KAAK,YAAY,CAAC,QAAQ,CACnF,IAAI,aAAa,CAAC,CAAC,CAAC,CAAC;IAEtB,IAAI,CAAC,MAAM,EAAE,CAAC;QACZ,MAAM,CAAC,IAAI,CAAC,wDAAwD,CAAC,CAAC;QACtE,OAAO,IAAI,CAAC;IACd,CAAC;IAED,yDAAyD;IACzD,sDAAsD;IACtD,MAAM,qBAAqB,GAAG,SAAS,CAAC,WAAW,CAAC,GAAG,CAAC,CAAC,MAAqB,EAAE,EAAE,CAAC,CAAC;QAClF,GAAG,MAAM,CAAC,OAAO;QACjB,gDAAgD;QAChD,eAAe,EAAE,MAAM,CAAC,eAAe;QACvC,wBAAwB,EAAE,MAAM,CAAC,cAAc;KAChD,CAAC,CAAC,CAAC;IAEJ,MAAM,YAAY,GAAG,IAAI,CAAC,SAAS,CACjC,EAAE,cAAc,EAAE,CAAC,EAAE,QAAQ,EAAE,qBAAqB,EAAE,EACtD,IAAI,EACJ,CAAC,CACF,CAAC;IAEF,MAAM,EAAE,YAAY,EAAE,UAAU,EAAE,GAAG,UAAU,CAAC,QAAQ,CAAC,qBAAqB,CAAC;QAC7E,YAAY;QACZ,IAAI;QACJ,OAAO,EAAE,UAAU,CAAC,OAAO;QAC3B,qEAAqE;QACrE,8DAA8D;QAC9D,WAAW,EAAE,UAAU,CAAC,WAAW;QACnC,gBAAgB,EAAE,WAAW;KAC9B,CAAC,CAAC;IAEH,MAAM,CAAC,IAAI,CAAC,oCAAoC,MAAM,CAAC,QAAQ,IAAI,MAAM,CAAC,OAAO,EAAE,CAAC,CAAC;IACrF,MAAM,QAAQ,GAAG,MAAM,MAAM,CAAC,OAAO,CAAC,cAAc,CAAC;QACnD,YAAY;QACZ,UAAU;QACV,eAAe,EAAE,MAAM,CAAC,eAAe;KACxC,CAAC,CAAC;IAEH,yBAAyB;IACzB,MAAM,SAAS,GAAG,SAAS,CAAC,QAAQ,CAAC,QAAQ,CAAC,OAAO,CAAC,CAAC;IACvD,OAAO,SAAS,CAAC,IAAI,CAAC,CAAC,CAAC,QAAQ,CAAC,OAAO,CAAC,CAAC,CAAC,SAAS,CAAC,gBAAgB,CAAC;AACxE,CAAC;AAED;;GAEG;AACH,SAAS,8BAA8B,CACrC,MAAqB,EACrB,MAAoD,EACpD,eAAuB;IAEvB,MAAM,KAAK,GAAa,EAAE,CAAC;IAC3B,MAAM,KAAK,GAAG,MAAM,CAAC,MAAM,GAAG,CAAC,CAAC;IAEhC,KAAK,CAAC,IAAI,CAAC,MAAM,KAAK,IAAI,KAAK,kCAAkC,CAAC,CAAC;IACnE,KAAK,CAAC,IAAI,CAAC,EAAE,CAAC,CAAC;IACf,KAAK,CAAC,IAAI,CAAC,WAAW,MAAM,CAAC,GAAG,CAAC,CAAC,CAAC,EAAE,EAAE,CAAC,GAAG,CAAC,CAAC,QAAQ,IAAI,CAAC,CAAC,OAAO,EAAE,CAAC,CAAC,IAAI,CAAC,IAAI,CAAC,EAAE,CAAC,CAAC;IACpF,KAAK,CAAC,IAAI,CAAC,EAAE,CAAC,CAAC;IAEf,iCAAiC;IACjC,KAAK,CAAC,IAAI,CAAC,WAAW,CAAC,CAAC;IACxB,KAAK,CAAC,IAAI,CAAC,yCAAyC,CAAC,CAAC;IACtD,KAAK,CAAC,IAAI,CAAC,EAAE,CAAC,CAAC;IACf,KAAK,CAAC,IAAI,CAAC,4BAA4B,CAAC,CAAC;IACzC,KAAK,CAAC,IAAI,CAAC,WAAW,CAAC,CAAC;IACxB,KAAK,CAAC,IAAI,CAAC,sBAAsB,MAAM,CAAC,KAAK,CAAC,cAAc,IAAI,CAAC,CAAC;IAClE,KAAK,CAAC,IAAI,CAAC,gBAAgB,MAAM,CAAC,KAAK,CAAC,QAAQ,IAAI,CAAC,CAAC;IACtD,KAAK,CAAC,IAAI,CAAC,eAAe,MAAM,CAAC,KAAK,CAAC,OAAO,IAAI,CAAC,CAAC;IACpD,KAAK,CAAC,IAAI,CAAC,iBAAiB,MAAM,CAAC,KAAK,CAAC,SAAS,IAAI,CAAC,CAAC;IACxD,KAAK,CAAC,IAAI,CAAC,2BAA2B,MAAM,CAAC,KAAK,CAAC,MAAM,IAAI,CAAC,CAAC;IAC/D,KAAK,CAAC,IAAI,CAAC,EAAE,CAAC,CAAC;IACf,KAAK,CAAC,IAAI,CAAC,YAAY,CAAC,CAAC;IACzB,KAAK,CAAC,IAAI,CAAC,EAAE,CAAC,CAAC;IACf,KAAK,CAAC,IAAI,CAAC,KAAK,CAAC,CAAC;IAClB,KAAK,CAAC,IAAI,CAAC,EAAE,CAAC,CAAC;IACf,KAAK,CAAC,IAAI,CAAC,eAAe,CAAC,CAAC;IAE5B,OAAO,KAAK,CAAC,IAAI,CAAC,IAAI,CAAC,CAAC;AAC1B,CAAC"}
\ No newline at end of file
+{"version":3,"file":"multi-model-pipeline.js","sourceRoot":"","sources":["../../resources/core/multi-model-pipeline.ts"],"names":[],"mappings":"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"}
\ No newline at end of file
~~~~

## H149 — .claude/skills/bridgebuilder-review/dist/core/truncation.generated.js — insertion after head line 14

Head context (head/.claude/skills/bridgebuilder-review/dist/core/truncation.generated.js, lines 3–26):

~~~~text
     3 | // Source: .claude/defaults/model-config.yaml
     4 | //
     5 | // Per-provider defaults applied at codegen time (yaml tracks API context_window
     6 | // only; maxOutput + coefficient are BB-skill truncation heuristics):
     7 | //   anthropic / bedrock / google: maxOutput=8192, coefficient=0.25
     8 | //   openai:                       maxOutput=4096, coefficient=0.23
     9 | //   default fallback:             maxInput=100000, maxOutput=4096, coefficient=0.25
    10 | //
    11 | // maxInput = effective_input_ceiling − 20000 when the yaml entry carries the
    12 | // v3 ceiling (cycle-124 FR-3 / SDD §2.1: BB truncates below cheval's pre-flight
    13 | // gate instead of dispatching what exit 7 would reject), else context_window.
    14 | //
    15 | // GENERATED_MODEL_ALIASES maps the catalog's `aliases:` block to bare model
    16 | // ids (provider-qualified targets only; self-maps dropped) so an alias such as
    17 | // `opus` gets its target's budget. An operator alias overlay in
    18 | // .loa.config.yaml is NOT reflected — pin a concrete model or set
    19 | // max_input_tokens (cycle-126 sprint-250).
    20 | //
    21 | // cycle-099 sprint-1 (T1.1). See SDD §1.4.3 + §5.3.
    22 | export const GENERATED_TOKEN_BUDGETS = {
    23 |     "claude-fable-5": { maxInput: 160000, maxOutput: 32000, coefficient: 0.25 },
    24 |     "claude-fable-5-1": { maxInput: 160000, maxOutput: 32000, coefficient: 0.25 },
    25 |     "claude-haiku-4-5-20251001": { maxInput: 160000, maxOutput: 8192, coefficient: 0.25 },
    26 |     "claude-headless": { maxInput: 1000000, maxOutput: 8192, coefficient: 0.25 },
~~~~

The change from head to the fix:

~~~~diff
@@ -14,0 +15,7 @@
+// Units (cycle-127 r251-1): a calibrated entry whose ceiling_calibration records
+// measured_input_tokens carries its ceiling in provider-measured tokens, while
+// maxInput is in BB's estimate units (coefficient tokens/char), which under-count
+// the Opus 4.7+ tokenizer — so for those entries
+// maxInput = floor((effective_input_ceiling − 20000) / MEASURED_TO_ESTIMATE_SAFETY / 1000) × 1000,
+// with MEASURED_TO_ESTIMATE_SAFETY = 1.8.
+//
~~~~

## H150 — .claude/skills/bridgebuilder-review/dist/core/truncation.generated.js — head line 31

Head context (head/.claude/skills/bridgebuilder-review/dist/core/truncation.generated.js, lines 19–43):

~~~~text
    19 | // max_input_tokens (cycle-126 sprint-250).
    20 | //
    21 | // cycle-099 sprint-1 (T1.1). See SDD §1.4.3 + §5.3.
    22 | export const GENERATED_TOKEN_BUDGETS = {
    23 |     "claude-fable-5": { maxInput: 160000, maxOutput: 32000, coefficient: 0.25 },
    24 |     "claude-fable-5-1": { maxInput: 160000, maxOutput: 32000, coefficient: 0.25 },
    25 |     "claude-haiku-4-5-20251001": { maxInput: 160000, maxOutput: 8192, coefficient: 0.25 },
    26 |     "claude-headless": { maxInput: 1000000, maxOutput: 8192, coefficient: 0.25 },
    27 |     "claude-opus-4-6": { maxInput: 160000, maxOutput: 32000, coefficient: 0.25 },
    28 |     "claude-opus-4-7": { maxInput: 160000, maxOutput: 32000, coefficient: 0.25 },
    29 |     "claude-opus-4-8": { maxInput: 160000, maxOutput: 32000, coefficient: 0.25 },
    30 |     "claude-opus-5": { maxInput: 160000, maxOutput: 32000, coefficient: 0.25 },
>   31 |     "claude-opus-5-5": { maxInput: 916000, maxOutput: 32000, coefficient: 0.25 },
    32 |     "claude-sonnet-4-5-20250929": { maxInput: 160000, maxOutput: 8192, coefficient: 0.25 },
    33 |     "claude-sonnet-4-6": { maxInput: 160000, maxOutput: 32000, coefficient: 0.25 },
    34 |     "claude-sonnet-5": { maxInput: 160000, maxOutput: 32000, coefficient: 0.25 },
    35 |     "us.anthropic.claude-haiku-4-5-20251001-v1:0": { maxInput: 200000, maxOutput: 8192, coefficient: 0.25 },
    36 |     "us.anthropic.claude-opus-4-7": { maxInput: 200000, maxOutput: 8192, coefficient: 0.25 },
    37 |     "us.anthropic.claude-opus-4-8": { maxInput: 200000, maxOutput: 8192, coefficient: 0.25 },
    38 |     "us.anthropic.claude-sonnet-4-6": { maxInput: 200000, maxOutput: 8192, coefficient: 0.25 },
    39 |     "composer-2.5": { maxInput: 200000, maxOutput: 4096, coefficient: 0.25 },
    40 |     "composer-2.5-fast": { maxInput: 200000, maxOutput: 4096, coefficient: 0.25 },
    41 |     "deep-research-pro": { maxInput: 1048576, maxOutput: 8192, coefficient: 0.25 },
    42 |     "gemini-2.0-flash": { maxInput: 1048576, maxOutput: 8192, coefficient: 0.25 },
    43 |     "gemini-2.5-flash": { maxInput: 1048576, maxOutput: 8192, coefficient: 0.25 },
~~~~

The change from head to the fix:

~~~~diff
@@ -31 +38 @@
-    "claude-opus-5-5": { maxInput: 916000, maxOutput: 32000, coefficient: 0.25 },
+    "claude-opus-5-5": { maxInput: 508000, maxOutput: 32000, coefficient: 0.25 },
~~~~

## H151 — .claude/skills/bridgebuilder-review/resources/__tests__/multi-model-agy-opt-in.test.ts — head lines 3–6

Head context (head/.claude/skills/bridgebuilder-review/resources/__tests__/multi-model-agy-opt-in.test.ts, lines 1–18):

~~~~text
     1 | import { describe, it, mock } from "node:test";
     2 | import assert from "node:assert/strict";
>    3 | import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
>    4 | import { tmpdir } from "node:os";
>    5 | import { join } from "node:path";
>    6 | import { MultiModelConfigSchema, validateApiKeys, readAgyGate, isAgyRouted } from "../config.js";
     7 | import { ChevalDelegateAdapter } from "../adapters/cheval-delegate.js";
     8 | import { executeMultiModelReview } from "../core/multi-model-pipeline.js";
     9 | import type { BridgebuilderConfig, MultiModelConfig, ReviewItem } from "../core/types.js";
    10 | import type { PRReviewTemplate } from "../core/template.js";
    11 | 
    12 | // cycle-127 FR-1: the agy (Antigravity) route — the gemini-headless hop — is opt-in (hounfour.headless.agy_opt_in, default
    13 | // false). A google voice whose route is agy (the gemini-headless model id, or any google model under headless mode cli-only)
    14 | // is NOT PLANNED with the opt-in off: never registered, never dispatched, and verdict quality counts the planned voices only.
    15 | 
    16 | function withConfig(body: string | null, fn: (path: string, root: string) => void | Promise<void>) {
    17 |   const root = mkdtempSync(join(tmpdir(), "bb-agy-gate-"));
    18 |   const path = join(root, ".loa.config.yaml");
~~~~

The change from head to the fix:

~~~~diff
@@ -3,4 +3,7 @@
-import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
+import { chmodSync, mkdirSync, mkdtempSync, renameSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
+import { execFileSync } from "node:child_process";
 import { tmpdir } from "node:os";
 import { join } from "node:path";
-import { MultiModelConfigSchema, validateApiKeys, readAgyGate, isAgyRouted } from "../config.js";
+import { readFileSync } from "node:fs";
+import { MultiModelConfigSchema, validateApiKeys, readAgyGate, isAgyRouted, loaConfigPathFor, agyGateStartupLines, agyConfigUntrustedReason, agyGroupNotPrivate } from "../config.js";
+import { GENERATED_MODEL_REGISTRY } from "../config.generated.js";
~~~~

## H152 — .claude/skills/bridgebuilder-review/resources/__tests__/multi-model-agy-opt-in.test.ts — head lines 19–22

Head context (head/.claude/skills/bridgebuilder-review/resources/__tests__/multi-model-agy-opt-in.test.ts, lines 7–34):

~~~~text
     7 | import { ChevalDelegateAdapter } from "../adapters/cheval-delegate.js";
     8 | import { executeMultiModelReview } from "../core/multi-model-pipeline.js";
     9 | import type { BridgebuilderConfig, MultiModelConfig, ReviewItem } from "../core/types.js";
    10 | import type { PRReviewTemplate } from "../core/template.js";
    11 | 
    12 | // cycle-127 FR-1: the agy (Antigravity) route — the gemini-headless hop — is opt-in (hounfour.headless.agy_opt_in, default
    13 | // false). A google voice whose route is agy (the gemini-headless model id, or any google model under headless mode cli-only)
    14 | // is NOT PLANNED with the opt-in off: never registered, never dispatched, and verdict quality counts the planned voices only.
    15 | 
    16 | function withConfig(body: string | null, fn: (path: string, root: string) => void | Promise<void>) {
    17 |   const root = mkdtempSync(join(tmpdir(), "bb-agy-gate-"));
    18 |   const path = join(root, ".loa.config.yaml");
>   19 |   if (body !== null) writeFileSync(path, body);
>   20 |   return Promise.resolve(fn(path, root)).finally(() => rmSync(root, { recursive: true, force: true }));
>   21 | }
>   22 | 
    23 | describe("readAgyGate", () => {
    24 |   for (const [label, body, optIn, mode] of [
    25 |     ["no config file", null, false, "prefer-api"],
    26 |     ["absent key", "hounfour:\n  headless:\n    mode: cli-only\n", false, "cli-only"],
    27 |     ["false", "hounfour:\n  headless:\n    agy_opt_in: false\n", false, "prefer-api"],
    28 |     ["a string", "hounfour:\n  headless:\n    agy_opt_in: \"true\"\n", false, "prefer-api"],
    29 |     ["true", "hounfour:\n  headless:\n    agy_opt_in: true\n    mode: prefer-cli\n", true, "prefer-cli"],
    30 |   ] as const) {
    31 |     it(`reads ${label}`, async () => {
    32 |       const saved = process.env.LOA_HEADLESS_MODE;
    33 |       delete process.env.LOA_HEADLESS_MODE;
    34 |       try {
~~~~

The change from head to the fix:

~~~~diff
@@ -19,4 +22,38 @@
-  if (body !== null) writeFileSync(path, body);
+  // (r251-5 U1/U2: owner-only, whatever the host umask — a group-writable config never opts in, and these tests are about
+  // the key; the permission rule has its own describe below)
+  if (body !== null) { writeFileSync(path, body); chmodSync(path, 0o644); }
   return Promise.resolve(fn(path, root)).finally(() => rmSync(root, { recursive: true, force: true }));
 }
 
+/** A fake `getent` first on PATH for the duration of `fn` (r251-6 V1): this user is `loa-me` (uid / primary gid = the
+ * process's), the file's group is `group` with the listed `members`, and `othersPrimary` adds an account whose primary group
+ * is the same gid. The real account database cannot be bent without root; the bash and TS readers both read it via getent. */
+async function withGetent(
+  opts: { group?: string; members?: string; othersPrimary?: boolean; pgid?: number },
+  fn: () => void | Promise<void>,
+) {
+  const dir = mkdtempSync(join(tmpdir(), "bb-getent-"));
+  const uid = process.getuid!();
+  const gid = process.getgid!();
+  const me = `loa-me:x:${uid}:${opts.pgid ?? gid}::/nonexistent:/bin/sh`;
+  const other = opts.othersPrimary ? `staffer:x:${uid + 1}:${gid}::/nonexistent:/bin/sh` : "";
+  writeFileSync(join(dir, "getent"), [
+    "#!/bin/sh",
+    'case "$1" in',
+    `  passwd) if [ -n "$2" ]; then [ "$2" = "${uid}" ] && echo '${me}' || exit 2; else echo '${me}'; ${other ? `echo '${other}';` : ""} fi ;;`,
+    `  group) [ "$2" = "${gid}" ] && echo '${opts.group ?? "loa-me"}:x:${gid}:${opts.members ?? ""}' || exit 2 ;;`,
+    "  *) exit 1 ;;",
+    "esac",
+    "",
+  ].join("\n"));
+  chmodSync(join(dir, "getent"), 0o755);
+  const saved = process.env.PATH;
+  process.env.PATH = `${dir}:${saved ?? ""}`;
+  try {
+    await fn();
+  } finally {
+    process.env.PATH = saved;
+    rmSync(dir, { recursive: true, force: true });
+  }
+}
+
~~~~

## H153 — .claude/skills/bridgebuilder-review/resources/__tests__/multi-model-agy-opt-in.test.ts — head line 35

Head context (head/.claude/skills/bridgebuilder-review/resources/__tests__/multi-model-agy-opt-in.test.ts, lines 23–47):

~~~~text
    23 | describe("readAgyGate", () => {
    24 |   for (const [label, body, optIn, mode] of [
    25 |     ["no config file", null, false, "prefer-api"],
    26 |     ["absent key", "hounfour:\n  headless:\n    mode: cli-only\n", false, "cli-only"],
    27 |     ["false", "hounfour:\n  headless:\n    agy_opt_in: false\n", false, "prefer-api"],
    28 |     ["a string", "hounfour:\n  headless:\n    agy_opt_in: \"true\"\n", false, "prefer-api"],
    29 |     ["true", "hounfour:\n  headless:\n    agy_opt_in: true\n    mode: prefer-cli\n", true, "prefer-cli"],
    30 |   ] as const) {
    31 |     it(`reads ${label}`, async () => {
    32 |       const saved = process.env.LOA_HEADLESS_MODE;
    33 |       delete process.env.LOA_HEADLESS_MODE;
    34 |       try {
>   35 |         await withConfig(body, (path) => assert.deepEqual(readAgyGate(path), { optIn, mode }));
    36 |       } finally {
    37 |         if (saved !== undefined) process.env.LOA_HEADLESS_MODE = saved;
    38 |       }
    39 |     });
    40 |   }
    41 | 
    42 |   it("LOA_HEADLESS_MODE wins for the mode, as in cheval; nothing in the environment opts in", async () => {
    43 |     const saved = process.env.LOA_HEADLESS_MODE;
    44 |     process.env.LOA_HEADLESS_MODE = "cli-only";
    45 |     process.env.LOA_AGY_OPT_IN = "true";
    46 |     try {
    47 |       await withConfig("hounfour:\n  headless:\n    mode: prefer-api\n", (path) =>
~~~~

The change from head to the fix:

~~~~diff
@@ -35 +72,5 @@
-        await withConfig(body, (path) => assert.deepEqual(readAgyGate(path), { optIn, mode }));
+        await withConfig(body, (path) => {
+          const g = readAgyGate(path);
+          assert.deepEqual({ optIn: g.optIn, mode: g.mode }, { optIn, mode });
+          assert.equal(g.readError, undefined, "a readable config (or none) is not a read error");
+        });
~~~~

## H154 — .claude/skills/bridgebuilder-review/resources/__tests__/multi-model-agy-opt-in.test.ts — insertion after head line 159

Head context (head/.claude/skills/bridgebuilder-review/resources/__tests__/multi-model-agy-opt-in.test.ts, lines 148–168):

~~~~text
   148 |         const item = { owner: "fixture", repo: "repo", pr: { number: 22, headSha: "fixture" }, files: [], hash: "fixture" } as ReviewItem;
   149 |         const result = await executeMultiModelReview(item, "fixture", "fixture", config, {
   150 |           poster: { postReview: async () => true, hasExistingReview: async () => false, postComment: async (c: { body: string }) => { bodies.push(c.body); return true; } },
   151 |           sanitizer: { sanitize: (content) => ({ safe: true, sanitizedContent: content, redactedPatterns: [] }) },
   152 |           logger: { info(m: string) { infos.push(m); }, warn() {}, error() {}, debug() {} },
   153 |         }, { template: { buildEnrichmentPrompt: () => ({ systemPrompt: "fixture", userPrompt: "fixture" }) } as unknown as PRReviewTemplate, persona: "fixture" });
   154 |         assert.ok(!seen.includes("gemini-3.1-pro-preview"), `dispatched ${JSON.stringify(seen)}`);
   155 |         assert.deepEqual(result.modelResults.map((r) => r.provider), ["anthropic", "openai"]);
   156 |         assert.deepEqual(result.notPlanned, [{ provider: "google", modelId: "gemini-3.1-pro-preview", reason: "opt_in_required" }]);
   157 |         assert.equal(infos.filter((m) => m === "google voice not planned: agy opt-in off (hounfour.headless.agy_opt_in)").length, 1);
   158 |         const summary = bodies.find((b) => b.includes("**Verdict Quality**"));
   159 |         assert.ok(summary && summary.includes("✓ APPROVED — 2/2 voices"), `summary: ${summary}`);
   160 |         assert.ok(!result.reviewVerdict.mergeBlocked, "a not-planned voice never blocks the merge as a missing one would");
   161 |       } finally {
   162 |         stub.mock.restore();
   163 |         if (savedKey === undefined) delete process.env.GOOGLE_API_KEY; else process.env.GOOGLE_API_KEY = savedKey;
   164 |         if (savedMode !== undefined) process.env.LOA_HEADLESS_MODE = savedMode;
   165 |       }
   166 |     });
   167 |   });
   168 | });
~~~~

The change from head to the fix:

~~~~diff
@@ -159,0 +201,2 @@
+        // (r251-4 S8, audit n21: the posted Verdict Quality line names the voice that was not planned, and why)
+        assert.ok(summary && /\*\*Verdict Quality\*\*:[^\n]*not planned: google\/gemini-3\.1-pro-preview \(agy opt-in off/.test(summary), `summary: ${summary}`);
~~~~

## H155 — .claude/skills/bridgebuilder-review/resources/__tests__/multi-model-agy-opt-in.test.ts — insertion after head line 168

Head context (head/.claude/skills/bridgebuilder-review/resources/__tests__/multi-model-agy-opt-in.test.ts, lines 157–168):

~~~~text
   157 |         assert.equal(infos.filter((m) => m === "google voice not planned: agy opt-in off (hounfour.headless.agy_opt_in)").length, 1);
   158 |         const summary = bodies.find((b) => b.includes("**Verdict Quality**"));
   159 |         assert.ok(summary && summary.includes("✓ APPROVED — 2/2 voices"), `summary: ${summary}`);
   160 |         assert.ok(!result.reviewVerdict.mergeBlocked, "a not-planned voice never blocks the merge as a missing one would");
   161 |       } finally {
   162 |         stub.mock.restore();
   163 |         if (savedKey === undefined) delete process.env.GOOGLE_API_KEY; else process.env.GOOGLE_API_KEY = savedKey;
   164 |         if (savedMode !== undefined) process.env.LOA_HEADLESS_MODE = savedMode;
   165 |       }
   166 |     });
   167 |   });
   168 | });
~~~~

The change from head to the fix:

~~~~diff
@@ -168,0 +212,559 @@
+
+// --- review r251-1 G3 (findings 20, 21) ------------------------------------------------------------------------------
+
+function pipelineFixture(models: MultiModelConfig["models"], mode: "graceful" | "strict", repoRoot: string) {
+  const multiModel = { enabled: true, models, api_key_mode: mode, consensus: { enabled: true, scoring_thresholds: {} } } as MultiModelConfig;
+  const config = {
+    repos: [], repoRoot, model: "fixture", maxPrs: 1, maxFilesPerPr: 1, maxDiffBytes: 1000,
+    maxInputTokens: 1000, maxOutputTokens: 1000, dimensions: [], reviewMarker: "fixture",
+    repoOverridePath: "", dryRun: false, excludePatterns: [], sanitizerMode: "default",
+    maxRuntimeMinutes: 1, multiModel,
+  } as BridgebuilderConfig;
+  const item = { owner: "fixture", repo: "repo", pr: { number: 22, headSha: "fixture" }, files: [], hash: "fixture" } as ReviewItem;
+  const infos: string[] = [];
+  const warns: string[] = [];
+  const adapters = {
+    poster: { postReview: async () => true, hasExistingReview: async () => false, postComment: async () => true },
+    sanitizer: { sanitize: (content: string) => ({ safe: true, sanitizedContent: content, redactedPatterns: [] }) },
+    logger: { info(m: string) { infos.push(m); }, warn(m: string) { warns.push(m); }, error() {}, debug() {} },
+  };
+  const enrichment = { template: { buildEnrichmentPrompt: () => ({ systemPrompt: "fixture", userPrompt: "fixture" }) } as unknown as PRReviewTemplate, persona: "fixture" };
+  return { config, item, adapters, enrichment, infos, warns };
+}
+
+describe("executeMultiModelReview edge cases (r251-1 G3)", () => {
+  it("every configured voice gated off: refuses with the opt-in named, never 'all API keys missing' and never a clear", async () => {
+    await withConfig("hounfour:\n  headless:\n    mode: cli-only\n", async (_p, repoRoot) => {
+      const savedMode = process.env.LOA_HEADLESS_MODE; delete process.env.LOA_HEADLESS_MODE;
+      const stub = mock.method(ChevalDelegateAdapter.prototype, "generateReview", async () => { throw new Error("dispatched"); });
+      try {
+        const f = pipelineFixture([{ provider: "google", model_id: "gemini-3.1-pro-preview", role: "primary" }] as MultiModelConfig["models"], "graceful", repoRoot);
+        await assert.rejects(
+          executeMultiModelReview(f.item, "fixture", "fixture", f.config, f.adapters as never, f.enrichment),
+          (err: Error) => /not planned/.test(err.message) && /hounfour\.headless\.agy_opt_in/.test(err.message) && !/all API keys missing/.test(err.message),
+        );
+        assert.equal(stub.mock.callCount(), 0);
+      } finally {
+        stub.mock.restore();
+        if (savedMode !== undefined) process.env.LOA_HEADLESS_MODE = savedMode;
+      }
+    });
+  });
+
+  it("strict mode: a configured voice removed by the gate WARNs (it will not run) and does not throw", async () => {
+    await withConfig("hounfour:\n  headless:\n    mode: cli-only\n", async (_p, repoRoot) => {
+      const savedMode = process.env.LOA_HEADLESS_MODE; delete process.env.LOA_HEADLESS_MODE;
+      const stub = mock.method(ChevalDelegateAdapter.prototype, "generateReview", async () => ({
+        content: "<!-- bridge-findings-start -->\n```json\n" + JSON.stringify({ schema_version: 1, findings: [] }) + "\n```\n<!-- bridge-findings-end -->\n\nVerdict: APPROVE",
+        inputTokens: 1, outputTokens: 1, model: "fixture",
+        verdictQuality: { status: "APPROVED", voices_planned: 1, voices_succeeded: 1, chain_health: "ok" },
+      }));
+      try {
+        const f = pipelineFixture([
+          { provider: "anthropic", model_id: "claude-headless", role: "primary" },
+          { provider: "google", model_id: "gemini-3.1-pro-preview", role: "reviewer" },
+        ] as MultiModelConfig["models"], "strict", repoRoot);
+        const result = await executeMultiModelReview(f.item, "fixture", "fixture", f.config, f.adapters as never, f.enrichment);
+        const w = f.warns.filter((m) => m.includes("gemini-3.1-pro-preview") && m.includes("strict") && m.includes("hounfour.headless.agy_opt_in"));
+        assert.equal(w.length, 1, JSON.stringify(f.warns));
+        assert.deepEqual(result.modelResults.map((r) => r.provider), ["anthropic"]);
+      } finally {
+        stub.mock.restore();
+        if (savedMode !== undefined) process.env.LOA_HEADLESS_MODE = savedMode;
+      }
+    });
+  });
+});
+
+// --- review r251-1 G12/G14/G15/G16 ------------------------------------------------------------------------------------
+
+describe("readAgyGate states (r251-1 G12, G14)", () => {
+  it("a present non-boolean agy_opt_in (the string \"true\") reads off and is flagged for one WARN naming the key", async () => {
+    await withConfig("hounfour:\n  headless:\n    agy_opt_in: \"true\"\n", (path) => {
+      const g = readAgyGate(path);
+      assert.equal(g.optIn, false);
+      assert.match(String(g.typeWarning), /hounfour\.headless\.agy_opt_in/);
+      assert.match(String(g.typeWarning), /boolean/);
+    });
+    await withConfig("hounfour:\n  headless:\n    agy_opt_in: true\n", (path) => assert.equal(readAgyGate(path).typeWarning, undefined));
+    await withConfig("hounfour: {}\n", (path) => assert.equal(readAgyGate(path).typeWarning, undefined));
+  });
+
+  it("an unreadable config fails closed but says why: readError carries the underlying error", async () => {
+    await withConfig("hounfour: [unclosed\n", (path) => {
+      const g = readAgyGate(path);
+      assert.equal(g.optIn, false);
+      assert.ok(g.readError && g.readError.length > 0, JSON.stringify(g));
+    });
+  });
+
+  it("a missing config file is no error (no Loa config: the opt-in is simply off)", async () => {
+    await withConfig(null, (path) => assert.equal(readAgyGate(path).readError, undefined));
+  });
+});
+
+describe("validateApiKeys takes the gate explicitly (r251-1 G15)", () => {
+  it("the gate parameter decides: an OFF gate wins over an opted-in config in the process cwd (r251-2 K7a)", async () => {
+    // (behavioural, not an arity check: an optional `gate?` with an in-body cwd default would also have length 2)
+    await withConfig("hounfour:\n  headless:\n    mode: cli-only\n    agy_opt_in: true\n", (_p, root) => {
+      const cwd = process.cwd();
+      process.chdir(root);
+      try {
+        const models = MultiModelConfigSchema.parse({ enabled: true, models: [{ provider: "google", model_id: "gemini-3.1-pro-preview" }] });
+        const r = validateApiKeys(models, { optIn: false, mode: "cli-only" });
+        assert.deepEqual(r.notPlanned, [{ provider: "google", modelId: "gemini-3.1-pro-preview", reason: "opt_in_required" }]);
+        assert.deepEqual(r.valid, []);
+      } finally {
+        process.chdir(cwd);
+      }
+    });
+  });
+  it("loaConfigPathFor resolves the repo root's .loa.config.yaml, and the cwd file only without a root", () => {
+    assert.equal(loaConfigPathFor("/x/repo"), join("/x/repo", ".loa.config.yaml"));
+    assert.equal(loaConfigPathFor(undefined), ".loa.config.yaml");
+  });
+});
+
+describe("isAgyRouted reads the generated registry (r251-1 G16)", () => {
+  it("every google headless id in the registry is agy-routed on any mode; other providers' headless ids never are", () => {
+    const ids = Object.entries(GENERATED_MODEL_REGISTRY).filter(([id, e]) => /-headless$/.test(id) && e.provider === "google").map(([id]) => id);
+    assert.ok(ids.length > 0);
+    for (const id of ids) assert.equal(isAgyRouted("google", id, "prefer-api"), true, id);
+    for (const [id, e] of Object.entries(GENERATED_MODEL_REGISTRY)) {
+      if (/-headless$/.test(id) && e.provider !== "google") assert.equal(isAgyRouted(e.provider, id, "cli-only"), false, id);
+    }
+    assert.equal(isAgyRouted("google", "not-a-registry-headless", "prefer-api"), false);
+  });
+});
+
+describe("executeMultiModelReview gate diagnostics (r251-1 G12, G14)", () => {
+  for (const [label, body, want] of [
+    ["unreadable config", "hounfour: [unclosed\n", /agy gate unreadable/],
+    ["string opt-in", "hounfour:\n  headless:\n    mode: cli-only\n    agy_opt_in: \"true\"\n", /hounfour\.headless\.agy_opt_in.*boolean/],
+  ] as const) {
+    it(`${label}: one warn with the reason, the google voice not planned`, async () => {
+      await withConfig(body, async (_p, repoRoot) => {
+        const savedMode = process.env.LOA_HEADLESS_MODE; process.env.LOA_HEADLESS_MODE = "cli-only";
+        const stub = mock.method(ChevalDelegateAdapter.prototype, "generateReview", async () => ({
+          content: "<!-- bridge-findings-start -->\n```json\n" + JSON.stringify({ schema_version: 1, findings: [] }) + "\n```\n<!-- bridge-findings-end -->\n\nVerdict: APPROVE",
+          inputTokens: 1, outputTokens: 1, model: "fixture",
+          verdictQuality: { status: "APPROVED", voices_planned: 1, voices_succeeded: 1, chain_health: "ok" },
+        }));
+        try {
+          const f = pipelineFixture([
+            { provider: "anthropic", model_id: "claude-headless", role: "primary" },
+            { provider: "google", model_id: "gemini-3.1-pro-preview", role: "reviewer" },
+          ] as MultiModelConfig["models"], "graceful", repoRoot);
+          const result = await executeMultiModelReview(f.item, "fixture", "fixture", f.config, f.adapters as never, f.enrichment);
+          assert.equal(f.warns.filter((m) => want.test(m)).length, 1, JSON.stringify(f.warns));
+          assert.deepEqual(result.modelResults.map((r) => r.provider), ["anthropic"]);
+        } finally {
+          stub.mock.restore();
+          if (savedMode === undefined) delete process.env.LOA_HEADLESS_MODE; else process.env.LOA_HEADLESS_MODE = savedMode;
+        }
+      });
+    });
+  }
+});
+
+// --- review r251-2 K7 (findings n19, n20, n22, n23, n25, n26) -------------------------------------------------------
+
+describe("the agy gate under a read error fails closed for google voices (r251-2 K7b)", () => {
+  it("readAgyGate pins the mode (env, else prefer-api) and validateApiKeys plans no google voice, even an HTTP one", async () => {
+    const saved = process.env.LOA_HEADLESS_MODE; delete process.env.LOA_HEADLESS_MODE;
+    const savedKey = process.env.GOOGLE_API_KEY; process.env.GOOGLE_API_KEY = "fixture-not-a-key";
+    try {
+      await withConfig("hounfour: [unclosed\n  headless:\n    mode: cli-only\n", (path) => {
+        const g = readAgyGate(path);
+        assert.ok(g.readError, JSON.stringify(g));
+        assert.equal(g.optIn, false);
+        assert.equal(g.mode, "prefer-api");
+        const models = MultiModelConfigSchema.parse({ enabled: true, models: [
+          { provider: "anthropic", model_id: "claude-headless" },
+          { provider: "google", model_id: "gemini-3.1-pro-preview" },
+        ] });
+        const r = validateApiKeys(models, g);
+        assert.deepEqual(r.notPlanned, [{ provider: "google", modelId: "gemini-3.1-pro-preview", reason: "opt_in_required" }]);
+        assert.deepEqual(r.valid.map((v) => v.provider), ["anthropic"]);
+      });
+    } finally {
+      if (saved !== undefined) process.env.LOA_HEADLESS_MODE = saved;
+      if (savedKey === undefined) delete process.env.GOOGLE_API_KEY; else process.env.GOOGLE_API_KEY = savedKey;
+    }
+  });
+});
+
+describe("executeMultiModelReview with no voice left (r251-2 K7c/K7d)", () => {
+  const ok = async () => ({
+    content: "<!-- bridge-findings-start -->\n```json\n" + JSON.stringify({ schema_version: 1, findings: [] }) + "\n```\n<!-- bridge-findings-end -->\n\nVerdict: APPROVE",
+    inputTokens: 1, outputTokens: 1, model: "fixture",
+    verdictQuality: { status: "APPROVED", voices_planned: 1, voices_succeeded: 1, chain_health: "ok" },
+  });
+
+  it("an unreadable config: the throw is built from the read error, not the opt-in hint", async () => {
+    await withConfig("hounfour: [unclosed\n", async (_p, repoRoot) => {
+      const savedMode = process.env.LOA_HEADLESS_MODE; delete process.env.LOA_HEADLESS_MODE;
+      const stub = mock.method(ChevalDelegateAdapter.prototype, "generateReview", async () => { throw new Error("dispatched"); });
+      try {
+        const f = pipelineFixture([{ provider: "google", model_id: "gemini-3.1-pro-preview", role: "primary" }] as MultiModelConfig["models"], "graceful", repoRoot);
+        await assert.rejects(
+          executeMultiModelReview(f.item, "fixture", "fixture", f.config, f.adapters as never, f.enrichment),
+          (err: Error) => /unreadable/.test(err.message) && /google\/gemini-3\.1-pro-preview/.test(err.message)
+            && !/set hounfour\.headless\.agy_opt_in: true/.test(err.message) && !/all API keys missing/.test(err.message),
+        );
+        assert.equal(stub.mock.callCount(), 0);
+      } finally {
+        stub.mock.restore();
+        if (savedMode !== undefined) process.env.LOA_HEADLESS_MODE = savedMode;
+      }
+    });
+  });
+
+  it("some voices not planned and the rest missing keys: ONE message lists both, never 'all API keys missing'", async () => {
+    await withConfig("hounfour:\n  headless:\n    mode: cli-only\n", async (_p, repoRoot) => {
+      const savedMode = process.env.LOA_HEADLESS_MODE; delete process.env.LOA_HEADLESS_MODE;
+      const savedKey = process.env.OPENAI_API_KEY; delete process.env.OPENAI_API_KEY;
+      const stub = mock.method(ChevalDelegateAdapter.prototype, "generateReview", async () => { throw new Error("dispatched"); });
+      try {
+        const f = pipelineFixture([
+          { provider: "google", model_id: "gemini-3.1-pro-preview", role: "primary" },
+          { provider: "openai", model_id: "gpt-5.5", role: "reviewer" },
+        ] as MultiModelConfig["models"], "graceful", repoRoot);
+        await assert.rejects(
+          executeMultiModelReview(f.item, "fixture", "fixture", f.config, f.adapters as never, f.enrichment),
+          (err: Error) => /not planned: google\/gemini-3\.1-pro-preview/.test(err.message) && /hounfour\.headless\.agy_opt_in/.test(err.message)
+            && /missing API keys: openai \(OPENAI_API_KEY\)/.test(err.message) && !/all API keys missing/.test(err.message),
+        );
+        assert.equal(stub.mock.callCount(), 0);
+      } finally {
+        stub.mock.restore();
+        if (savedMode !== undefined) process.env.LOA_HEADLESS_MODE = savedMode;
+        if (savedKey !== undefined) process.env.OPENAI_API_KEY = savedKey;
+      }
+    });
+  });
+
+  it("strict mode under a read error: the warn names the voices that will not run, then the review refuses (r251-4 S1)", async () => {
+    await withConfig("hounfour: [unclosed\n", async (_p, repoRoot) => {
+      const stub = mock.method(ChevalDelegateAdapter.prototype, "generateReview", ok);
+      try {
+        const f = pipelineFixture([
+          { provider: "anthropic", model_id: "claude-headless", role: "primary" },
+          { provider: "google", model_id: "gemini-3.1-pro-preview", role: "reviewer" },
+        ] as MultiModelConfig["models"], "strict", repoRoot);
+        await assert.rejects(
+          executeMultiModelReview(f.item, "fixture", "fixture", f.config, f.adapters as never, f.enrichment),
+          (err: Error) => /[Ss]trict mode/.test(err.message) && /unreadable/.test(err.message) && /google\/gemini-3\.1-pro-preview/.test(err.message),
+        );
+        const w = f.warns.filter((m) => /agy gate unreadable/.test(m));
+        assert.equal(w.length, 1, JSON.stringify(f.warns));
+        assert.match(w[0], /google\/gemini-3\.1-pro-preview/);
+        assert.equal(stub.mock.callCount(), 0, "strict mode refuses before any dispatch");
+      } finally {
+        stub.mock.restore();
+      }
+    });
+  });
+});
+
+describe("startup diagnostics (r251-2 K7f)", () => {
+  it("agyGateStartupLines says the read error and the type warning once each, with or without a not-planned voice", () => {
+    const none = { valid: [], missing: [], notPlanned: [] };
+    const lines = agyGateStartupLines({ optIn: false, mode: "prefer-api", readError: "boom", typeWarning: "tw" }, none);
+    assert.equal(lines.filter((l) => l.includes("boom")).length, 1, JSON.stringify(lines));
+    assert.equal(lines.filter((l) => l.includes("tw")).length, 1, JSON.stringify(lines));
+    assert.deepEqual(agyGateStartupLines({ optIn: false, mode: "prefer-api" }, none), []);
+    const np = { ...none, notPlanned: [{ provider: "google", modelId: "gemini-headless", reason: "opt_in_required" as const }] };
+    assert.equal(agyGateStartupLines({ optIn: false, mode: "prefer-api" }, np).filter((l) => l.includes("google/gemini-headless")).length, 1);
+  });
+
+  it("main.ts prints them through the helper, outside any not-planned condition", () => {
+    const src = readFileSync(join(import.meta.dirname, "..", "main.ts"), "utf8");
+    assert.match(src, /for \(const line of agyGateStartupLines\(agyGate, keyStatus\)\) console\.error\(/);
+  });
+});
+
+describe("the truncation header names the safety factor from its constant (r251-2 K7e)", () => {
+  it("HEADER_TRUNCATION interpolates MEASURED_TO_ESTIMATE_SAFETY and the generated header matches it", () => {
+    const gen = readFileSync(join(import.meta.dirname, "..", "..", "scripts", "gen-bb-registry.ts"), "utf8");
+    const value = /const MEASURED_TO_ESTIMATE_SAFETY = ([\d.]+);/.exec(gen)?.[1];
+    assert.ok(value, "the constant is defined");
+    const header = gen.slice(gen.indexOf("const HEADER_TRUNCATION"), gen.indexOf("`;", gen.indexOf("const HEADER_TRUNCATION")));
+    assert.match(header, /with MEASURED_TO_ESTIMATE_SAFETY = \$\{MEASURED_TO_ESTIMATE_SAFETY\}\./);
+    const generated = readFileSync(join(import.meta.dirname, "..", "core", "truncation.generated.ts"), "utf8");
+    assert.ok(generated.includes(`with MEASURED_TO_ESTIMATE_SAFETY = ${value}.`), "the generated header carries the constant's value");
+  });
+});
+
+describe("readAgyGate spelling (r251-2 K1: one strict rule with the bash and Python readers)", () => {
+  for (const spelling of ["True", "TRUE", "False", "yes", "on"]) {
+    it(`${spelling} reads off and is flagged for one WARN naming the accepted spelling`, async () => {
+      await withConfig(`hounfour:\n  headless:\n    agy_opt_in: ${spelling}\n`, (path) => {
+        const g = readAgyGate(path);
+        assert.equal(g.optIn, false);
+        assert.match(String(g.typeWarning), /agy_opt_in: true/);
+      });
+    });
+  }
+});
+
+// --- review r251-4 (the audit dissent) ---------------------------------------------------------------------------------
+
+describe("a host fault never shrinks the quorum (r251-4 S1, audit n22)", () => {
+  const ok = async () => ({
+    content: "<!-- bridge-findings-start -->\n```json\n" + JSON.stringify({ schema_version: 1, findings: [] }) + "\n```\n<!-- bridge-findings-end -->\n\nVerdict: APPROVE",
+    inputTokens: 1, outputTokens: 1, model: "fixture",
+    verdictQuality: { status: "APPROVED", voices_planned: 1, voices_succeeded: 1, chain_health: "ok" },
+  });
+
+  it("graceful mode under a read error: the remaining voices APPROVE, yet the merge stays blocked and the summary says why", async () => {
+    await withConfig("hounfour: [unclosed\n", async (_p, repoRoot) => {
+      const savedKey = process.env.GOOGLE_API_KEY; process.env.GOOGLE_API_KEY = "fixture-not-a-key";
+      const stub = mock.method(ChevalDelegateAdapter.prototype, "generateReview", ok);
+      try {
+        const bodies: string[] = [];
+        const f = pipelineFixture([
+          { provider: "anthropic", model_id: "claude-headless", role: "primary" },
+          { provider: "openai", model_id: "codex-headless", role: "reviewer" },
+          { provider: "google", model_id: "gemini-3.1-pro-preview", role: "reviewer" },
+        ] as MultiModelConfig["models"], "graceful", repoRoot);
+        (f.adapters.poster as { postComment: (c: { body: string }) => Promise<boolean> }).postComment = async (c) => { bodies.push(c.body); return true; };
+        const result = await executeMultiModelReview(f.item, "fixture", "fixture", f.config, f.adapters as never, f.enrichment);
+        assert.deepEqual(result.modelResults.map((r) => r.provider), ["anthropic", "openai"]);
+        assert.equal(result.reviewVerdict.mergeBlocked, true, "a read-error not-planned voice must not be subtracted from the quorum");
+        assert.ok(result.reviewVerdict.mergeBlockedReason && /unreadable/.test(result.reviewVerdict.mergeBlockedReason), JSON.stringify(result.reviewVerdict));
+        const summary = bodies.find((b) => b.includes("**Verdict Quality**"));
+        assert.ok(summary && /not planned: google\/gemini-3\.1-pro-preview \(Loa config unreadable/.test(summary), `summary: ${summary}`);
+      } finally {
+        stub.mock.restore();
+        if (savedKey === undefined) delete process.env.GOOGLE_API_KEY; else process.env.GOOGLE_API_KEY = savedKey;
+      }
+    });
+  });
+
+  it("a read error with no google voice configured changes nothing: the full cohort still clears", async () => {
+    await withConfig("hounfour: [unclosed\n", async (_p, repoRoot) => {
+      const stub = mock.method(ChevalDelegateAdapter.prototype, "generateReview", ok);
+      try {
+        const f = pipelineFixture([
+          { provider: "anthropic", model_id: "claude-headless", role: "primary" },
+          { provider: "openai", model_id: "codex-headless", role: "reviewer" },
+        ] as MultiModelConfig["models"], "graceful", repoRoot);
+        const result = await executeMultiModelReview(f.item, "fixture", "fixture", f.config, f.adapters as never, f.enrichment);
+        assert.equal(result.reviewVerdict.mergeBlocked, false, JSON.stringify(result.reviewVerdict));
+      } finally {
+        stub.mock.restore();
+      }
+    });
+  });
+});
+
+describe("readAgyGate shapes (r251-4 S3: the exact bool tag; an alias or a merge key reads off — one rule with bash and Python)", () => {
+  for (const [label, body, want] of [
+    ["foreign tag !<x:bool>", "hounfour:\n  headless:\n    agy_opt_in: !<x:bool> true\n", false],
+    ["local tag !bool", "hounfour:\n  headless:\n    agy_opt_in: !bool true\n", false],
+    ["alias", "x: &t true\nhounfour:\n  headless:\n    agy_opt_in: *t\n", false],
+    ["merge key", "b: &b\n  agy_opt_in: true\nhounfour:\n  headless:\n    <<: *b\n", false],
+    ["aliased headless", "h: &h\n  agy_opt_in: true\nhounfour:\n  headless: *h\n", false],
+    ["full tag", "hounfour:\n  headless:\n    agy_opt_in: !<tag:yaml.org,2002:bool> true\n", true],
+    ["anchored definition", "hounfour:\n  headless:\n    agy_opt_in: &a true\n", true],
+  ] as const) {
+    it(`${label} → ${want ? "on" : "off"}`, async () => {
+      await withConfig(body, (path) => {
+        const g = readAgyGate(path);
+        assert.equal(g.optIn, want, JSON.stringify(g));
+        assert.equal(g.readError, undefined);
+      });
+    });
+  }
+
+  it("a foreign bool tag and an alias are flagged for one WARN as not a YAML boolean", async () => {
+    for (const body of ["hounfour:\n  headless:\n    agy_opt_in: !<x:bool> true\n", "x: &t true\nhounfour:\n  headless:\n    agy_opt_in: *t\n"]) {
+      await withConfig(body, (path) => assert.match(String(readAgyGate(path).typeWarning), /not a YAML boolean/));
+    }
+  });
+});
+
+describe("readAgyGate permissions (r251-5 U1/U2, audit MED-001/LOW-001: one rule with the bash and Python readers)", () => {
+  const ON = "hounfour:\n  headless:\n    agy_opt_in: true\n";
+  for (const [mode, reason] of [[0o666, "world-writable"], [0o646, "world-writable"], [0o664, "group-writable"], [0o660, "group-writable"], [0o620, "group-writable"]] as const) {
+    it(`a ${mode.toString(8).padStart(4, "0")} true config reads off with one warning naming the key and ${reason}`, async () => {
+      // (r251-6 V1: the group is a shared `users` — a user-private group is the exception, pinned below)
+      await withGetent({ group: "users" }, () => withConfig(ON, (path) => {
+        chmodSync(path, mode);
+        const g = readAgyGate(path);
+        assert.equal(g.optIn, false, JSON.stringify(g));
+        assert.equal(g.readError, undefined, "an untrusted config reads off; it is not a read error (no merge block)");
+        assert.match(String(g.typeWarning), /^hounfour\.headless\.agy_opt_in: .* is (world|group)-writable \(mode 0\d{3}\)/);
+        assert.match(String(g.typeWarning), new RegExp(reason));
+        assert.equal(agyGateStartupLines(g, { valid: [], missing: [], notPlanned: [] }).filter((l) => /agy_opt_in/.test(l)).length, 1);
+      }));
+    });
+  }
+
+  for (const mode of [0o644, 0o600, 0o444]) {
+    it(`an owned ${mode.toString(8).padStart(4, "0")} true config opts in, silently`, async () => {
+      await withConfig(ON, (path) => {
+        chmodSync(path, mode);
+        assert.deepEqual({ optIn: readAgyGate(path).optIn, w: readAgyGate(path).typeWarning }, { optIn: true, w: undefined });
+      });
+    });
+  }
+
+  it("a symlink to a world-writable target: the target decides", async () => {
+    await withConfig(null, (path, root) => {
+      writeFileSync(join(root, "target.yaml"), ON);
+      chmodSync(join(root, "target.yaml"), 0o666);
+      symlinkSync("target.yaml", path);
+      const g = readAgyGate(path);
+      assert.equal(g.optIn, false);
+      assert.match(String(g.typeWarning), /world-writable/);
+    });
+  });
+
+  it("a config owned by another user reads off (process.getuid mocked: ownership cannot be faked without root)", async () => {
+    if (typeof process.getuid !== "function") return;
+    const real = process.getuid();
+    const stub = mock.method(process, "getuid", () => real + 1);
+    try {
+      await withConfig(ON, (path) => {
+        const g = readAgyGate(path);
+        assert.equal(g.optIn, false);
+        assert.match(String(g.typeWarning), /not owned by the current user/);
+      });
+    } finally {
+      stub.mock.restore();
+    }
+  });
+
+  it("only a value that would opt in is judged: a 0664 config with the key absent, false or \"true\" is never flagged", async () => {
+    for (const body of ["hounfour: {}\n", "hounfour:\n  headless:\n    agy_opt_in: false\n", 'hounfour:\n  headless:\n    agy_opt_in: "true"\n']) {
+      await withConfig(body, (path) => {
+        chmodSync(path, 0o664);
+        const g = readAgyGate(path);
+        assert.equal(g.optIn, false);
+        assert.doesNotMatch(String(g.typeWarning ?? ""), /writable/);
+      });
+    }
+  });
+
+  it("agyConfigUntrustedReason: a missing file is untrusted (fail closed); an owned 0644 file is trusted", async () => {
+    await withConfig(ON, (path, root) => {
+      assert.equal(agyConfigUntrustedReason(path), undefined);
+      assert.match(String(agyConfigUntrustedReason(join(root, "nope.yaml"))), /could not be stat'ed/);
+    });
+  });
+});
+
+describe("readAgyGate: the user-private-group exception (r251-6 V1, BB #1 — one rule with the bash and Python readers)", () => {
+  const ON = "hounfour:\n  headless:\n    agy_opt_in: true\n";
+  const hasIds = typeof process.getuid === "function" && typeof process.getgid === "function";
+
+  for (const mode of [0o664, 0o660, 0o620]) {
+    it(`a ${mode.toString(8).padStart(4, "0")} true config of the owner's private group opts in, silently`, async () => {
+      if (!hasIds) return;
+      await withGetent({}, () => withConfig(ON, (path) => {
+        chmodSync(path, mode);
+        const g = readAgyGate(path);
+        assert.deepEqual({ optIn: g.optIn, w: g.typeWarning, e: g.readError }, { optIn: true, w: undefined, e: undefined });
+      }));
+    });
+  }
+
+  for (const [label, opts, needle] of [
+    ["another member", { members: "bob" }, "'loa-me' has other members (bob)"],
+    ["named differently (a shared users)", { group: "users" }, "'users' is not named for the owner 'loa-me'"],
+    ["another account's primary group", { othersPrimary: true }, "the primary group of another account (staffer)"],
+    ["not the owner's primary group", { pgid: 4242424 }, "is not the owner's primary group"],
+  ] as const) {
+    it(`0664 + ${label}: off, one warning naming the group`, async () => {
+      if (!hasIds) return;
+      await withGetent(opts, () => withConfig(ON, (path) => {
+        chmodSync(path, 0o664);
+        const g = readAgyGate(path);
+        assert.equal(g.optIn, false, JSON.stringify(g));
+        assert.match(String(g.typeWarning), /group-writable \(mode 0664\) and /);
+        assert.ok(String(g.typeWarning).includes(needle), String(g.typeWarning));
+      }));
+    });
+  }
+
+  it("the owner listed as its own member is still private", async () => {
+    if (!hasIds) return;
+    await withGetent({ members: "loa-me" }, () => withConfig(ON, (path) => {
+      chmodSync(path, 0o664);
+      assert.equal(readAgyGate(path).optIn, true);
+    }));
+  });
+
+  it("0666 stays refused for a private group; no getent on PATH refuses a group-writable config", async () => {
+    if (!hasIds) return;
+    await withGetent({}, () => withConfig(ON, (path) => {
+      chmodSync(path, 0o666);
+      assert.match(String(readAgyGate(path).typeWarning), /world-writable/);
+    }));
+    assert.match(String(agyGroupNotPrivate(process.getuid!(), 4242424)), /could not be looked up/);
+  });
+
+  it("an ACL on a private-group config is refused (the group bits are the mask)", async () => {
+    if (!hasIds) return;
+    try { execFileSync("setfacl", ["--version"], { stdio: "ignore" }); } catch { return; }
+    await withGetent({}, () => withConfig(ON, (path) => {
+      chmodSync(path, 0o600);
+      try { execFileSync("setfacl", ["-m", "u:nobody:rw", path], { stdio: "ignore" }); } catch { return; }
+      const g = readAgyGate(path);
+      assert.equal(g.optIn, false);
+      assert.match(String(g.typeWarning), /extended ACL/);
+    }));
+  });
+});
+
+describe("readAgyGate reads one open file (r251-6 V3, BB #2)", () => {
+  it("a config swapped for an owned 0644 file while yq parses is judged on the file that was read (off)", async () => {
+    let realYq = "";
+    try { realYq = execFileSync("sh", ["-c", "command -v yq"], { encoding: "utf8" }).trim(); } catch { return; }
+    await withConfig("hounfour:\n  headless:\n    agy_opt_in: true\n", (path, root) => {
+      chmodSync(path, 0o666);
+      const bin = join(root, "bin");
+      mkdirSync(bin);
+      writeFileSync(join(root, "repl.yaml"), "hounfour:\n  headless:\n    agy_opt_in: true\n");
+      chmodSync(join(root, "repl.yaml"), 0o644);
+      writeFileSync(join(bin, "yq"), `#!/bin/sh\n"${realYq}" "$@"; rc=$?\nmv "${join(root, "repl.yaml")}" "${path}"\nexit $rc\n`);
+      chmodSync(join(bin, "yq"), 0o755);
+      const saved = process.env.PATH;
+      process.env.PATH = `${bin}:${saved ?? ""}`;
+      try {
+        const g = readAgyGate(path);
+        assert.equal(g.optIn, false, JSON.stringify(g));
+        assert.match(String(g.typeWarning), /world-writable/);
+      } finally {
+        process.env.PATH = saved;
+      }
+    });
+  });
+});
+
+describe("readAgyGate: an alias / non-mapping ancestor is said once (r251-6 V5, BB #5)", () => {
+  for (const [label, body, msg] of [
+    ["aliased headless", "h: &h\n  agy_opt_in: true\nhounfour:\n  headless: *h\n", /^hounfour\.headless is a YAML alias — hounfour\.headless\.agy_opt_in cannot be read/],
+    ["aliased hounfour", "h: &h\n  headless:\n    agy_opt_in: true\nhounfour: *h\n", /^hounfour is a YAML alias — /],
+    ["a sequence headless", "hounfour:\n  headless: [1]\n", /^hounfour\.headless is not a mapping \(seq\) — /],
+    ["a string hounfour", "hounfour: foo\n", /^hounfour is not a mapping \(str\) — /],
+  ] as const) {
+    it(`${label}: off with the ancestor warning`, async () => {
+      await withConfig(body, (path) => {
+        const g = readAgyGate(path);
+        assert.equal(g.optIn, false);
+        assert.equal(g.readError, undefined, JSON.stringify(g));
+        assert.match(String(g.typeWarning), msg);
+        assert.match(String(g.typeWarning), /write the mapping inline/);
+      });
+    });
+  }
+
+  for (const body of ["hounfour: {}\n", "hounfour:\n  headless:\n", "x: 1\n"]) {
+    it(`${JSON.stringify(body)}: silent`, async () => {
+      await withConfig(body, (path) => assert.equal(readAgyGate(path).typeWarning, undefined));
+    });
+  }
+});
~~~~

## H156 — .claude/skills/bridgebuilder-review/resources/config.ts — insertion after head line 3

Head context (head/.claude/skills/bridgebuilder-review/resources/config.ts, lines 1–15):

~~~~text
     1 | import { execFile, execFileSync, execSync } from "node:child_process";
     2 | import { promisify } from "node:util";
     3 | import { readFile } from "node:fs/promises";
     4 | import { z } from "zod/v4";
     5 | import type { BridgebuilderConfig, MultiModelConfig } from "./core/types.js";
     6 | import { GENERATED_MODEL_REGISTRY } from "./config.generated.js";
     7 | 
     8 | const execFileAsync = promisify(execFile);
     9 | 
    10 | /**
    11 |  * Zod schema for multi-model configuration (SDD Section 2.7).
    12 |  * Validated at startup; all fields have sensible defaults so partial config works.
    13 |  */
    14 | const ScoringThresholdsSchema = z.object({
    15 |   high_consensus: z.number().default(700),
~~~~

The change from head to the fix:

~~~~diff
@@ -3,0 +4,2 @@
+import { closeSync, existsSync, fstatSync, openSync, readFileSync, statSync } from "node:fs";
+import { join } from "node:path";
~~~~

## H157 — .claude/skills/bridgebuilder-review/resources/config.ts — insertion after head line 151

Head context (head/.claude/skills/bridgebuilder-review/resources/config.ts, lines 140–163):

~~~~text
   140 | // (case-sensitive, as cheval's alias lookup is — `Claude-Headless` resolves to nothing: thirty-eighth run, e4 DISS-C-002)
   141 | // (and a catalog entry, under its own provider when one is named — a suffix alone admitted a typo or a pairing cheval has no
   142 | // alias for, past the key gate's fail-fast: thirty-ninth run, e4 DISS-C-002)
   143 | export function isHeadlessModelId(modelId: string, provider?: string): boolean {
   144 |   if (typeof modelId !== "string" || !/-headless$/.test(modelId) || !Object.hasOwn(GENERATED_MODEL_REGISTRY, modelId)) return false;
   145 |   return provider === undefined || GENERATED_MODEL_REGISTRY[modelId].provider === provider;
   146 | }
   147 | 
   148 | /** cycle-127 FR-1: the agy (Antigravity) route's opt-in and the headless mode that decides whether a google voice routes to it. */
   149 | export interface AgyGate {
   150 |   optIn: boolean;
   151 |   mode: string;
   152 | }
   153 | 
   154 | /**
   155 |  * Read `hounfour.headless.agy_opt_in` (true only for a YAML boolean true) and `hounfour.headless.mode` from the Loa config
   156 |  * with one yq call. LOA_HEADLESS_MODE wins for the mode, as it does in cheval; nothing in the environment opts in. A missing
   157 |  * file, a missing yq or an unreadable config reads as off — the gate fails closed.
   158 |  */
   159 | export function readAgyGate(configPath = ".loa.config.yaml"): AgyGate {
   160 |   let optIn = false;
   161 |   let mode = "";
   162 |   try {
   163 |     const out = execFileSync(
~~~~

The change from head to the fix:

~~~~diff
@@ -151,0 +154,93 @@
+  /** The config could not be read (yq missing, unparsable YAML): the gate failed closed for this reason (r251-1 G14). */
+  readError?: string;
+  /** `agy_opt_in` is present but not written exactly `true` / `false` (the string "true", `True`, `yes` …): it reads off,
+   * said once (r251-1 G12, r251-2 K1 — the bash and Python readers apply the same strict rule). */
+  typeWarning?: string;
+}
+
+/** The Loa config the agy gate reads: the repo root's when one is known, else the cwd's (r251-1 G15 — one path for all callers). */
+export function loaConfigPathFor(repoRoot?: string): string {
+  return repoRoot ? join(repoRoot, ".loa.config.yaml") : ".loa.config.yaml";
+}
+
+/** The go-yq "is the key present" program — the same text as the bash lib's `_AGY_YQ_HAS` and the Python loader's
+ * `_YQ_HAS` (r251-4 S3): every level a real mapping (`kind` is "alias" for an alias node) and the explicit key only (`has`
+ * never sees a merge key's). */
+export const AGY_YQ_HAS = '.hounfour | (kind == "map" and (.headless | (kind == "map" and has("agy_opt_in"))))';
+
+/** One NSS lookup through `getent` (the bash lib's account source); undefined when getent is missing or cannot answer. */
+function getent(args: string[]): string | undefined {
+  try {
+    return execFileSync("getent", args, { encoding: "utf8", timeout: 5000, stdio: ["ignore", "pipe", "ignore"] });
+  } catch {
+    return undefined;
+  }
+}
+
+/**
+ * Why the file's group is not its owner's USER-PRIVATE group, or undefined when it is (review r251-6 V1, BB #1). ONE rule with
+ * cheval's `loader._not_private_group` and the bash lib's `_agy_group_not_private`: the file's gid is the owner's primary gid,
+ * the group is NAMED for the owner (a shared `users` / macOS `staff` fails — their member lists are empty for primary members,
+ * so emptiness alone never proved privacy: audit LOW-001), no account but the owner is a listed member, no other account has
+ * it as its primary group (enumerated last), and no ACL makes the group bits a mask over named grants (`ls -ldL`'s `+`, on
+ * the read's own descriptor when one is given). Accounts come from `getent`; a host without it, or one that cannot answer,
+ * is no proof: not private.
+ */
+export function agyGroupNotPrivate(uid: number, gid: number, fd?: number, configPath?: string): string | undefined {
+  const pw = (getent(["passwd", String(uid)]) ?? "").split("\n")[0].split(":");
+  const owner = pw[0] ?? "";
+  const pgid = pw[3] ?? "";
+  if (!owner || !/^\d+$/.test(pgid)) return `its owner uid ${uid} could not be looked up`;
+  const gr = (getent(["group", String(gid)]) ?? "").split("\n")[0].split(":");
+  const gname = gr[0] ?? "";
+  if (!gname) return `its group could not be looked up (gid ${gid})`;
+  if (String(gid) !== pgid) return `its group '${gname}' (gid ${gid}) is not the owner's primary group`;
+  if (gname !== owner) return `its group '${gname}' is not named for the owner '${owner}' (not a user-private group)`;
+  const members = (gr[3] ?? "").split(",").map((m) => m.trim()).filter((m) => m && m !== owner);
+  if (members.length) return `its group '${gname}' has other members (${members.join(", ")})`;
+  const all = getent(["passwd"]);
+  if (all === undefined) return `the accounts of group '${gname}' could not be enumerated`;
+  const primary = all.split("\n").map((l) => l.split(":")).filter((f) => f.length > 3 && f[3] === String(gid) && f[2] !== String(uid)).map((f) => f[0]);
+  if (primary.length) return `its group '${gname}' is the primary group of another account (${primary.join(", ")})`;
+  let ls = "";
+  try {
+    ls = fd !== undefined
+      ? execFileSync("ls", ["-ldL", "/dev/stdin"], { encoding: "utf8", timeout: 5000, stdio: [fd, "pipe", "ignore"] })
+      : execFileSync("ls", ["-ldL", "--", configPath ?? ""], { encoding: "utf8", timeout: 5000, stdio: ["ignore", "pipe", "ignore"] });
+  } catch {
+    ls = "";
+  }
+  const lsMode = ls.split(" ")[0] ?? "";
+  if (lsMode.length < 10) return "its ACL could not be read";
+  if (lsMode[10] === "+") return "it carries an extended ACL (the group bits are the ACL mask over other accounts' grants)";
+  return undefined;
+}
+
+/**
+ * Why the opt-in config is not the current user's alone to write, or undefined when it is (review r251-5 U1/U2, r251-6 V1):
+ * ONE permission rule with cheval's `loader._config_untrusted_reason` and the bash lib's `_agy_config_untrusted` — owned by
+ * the current user, never world-writable, and group-writable only for the owner's user-private group (`agyGroupNotPrivate`;
+ * Ubuntu's umask 002 makes every checkout 0664). `st` / `fd` are the read's own open file (r251-6 V3, BB #2: the bytes read
+ * and the inode judged are one); without them `statSync` follows a symlink: the target decides, as in the other readers. A
+ * config that cannot be stat'ed is untrusted (fail closed). Where the platform has no uid (`process.getuid` absent), the
+ * owner half is skipped.
+ */
+export function agyConfigUntrustedReason(
+  configPath: string, st?: { uid: number; gid: number; mode: number }, fd?: number,
+): string | undefined {
+  if (st === undefined) {
+    try {
+      st = statSync(configPath);
+    } catch {
+      return `${configPath} could not be stat'ed (owner and mode unknown)`;
+    }
+  }
+  const me = typeof process.getuid === "function" ? process.getuid() : undefined;
+  if (me !== undefined && st.uid !== me) return `${configPath} is not owned by the current user (uid ${st.uid}, euid ${me})`;
+  const mode = `mode ${(st.mode & 0o7777).toString(8).padStart(4, "0")}`;
+  if (st.mode & 0o002) return `${configPath} is world-writable (${mode})`;
+  if (st.mode & 0o020) {
+    const why = agyGroupNotPrivate(st.uid, st.gid, fd, configPath);
+    if (why !== undefined) return `${configPath} is group-writable (${mode}) and ${why}`;
+  }
+  return undefined;
~~~~

## H158 — .claude/skills/bridgebuilder-review/resources/config.ts — head lines 157–182

Head context (head/.claude/skills/bridgebuilder-review/resources/config.ts, lines 145–194):

~~~~text
   145 |   return provider === undefined || GENERATED_MODEL_REGISTRY[modelId].provider === provider;
   146 | }
   147 | 
   148 | /** cycle-127 FR-1: the agy (Antigravity) route's opt-in and the headless mode that decides whether a google voice routes to it. */
   149 | export interface AgyGate {
   150 |   optIn: boolean;
   151 |   mode: string;
   152 | }
   153 | 
   154 | /**
   155 |  * Read `hounfour.headless.agy_opt_in` (true only for a YAML boolean true) and `hounfour.headless.mode` from the Loa config
   156 |  * with one yq call. LOA_HEADLESS_MODE wins for the mode, as it does in cheval; nothing in the environment opts in. A missing
>  157 |  * file, a missing yq or an unreadable config reads as off — the gate fails closed.
>  158 |  */
>  159 | export function readAgyGate(configPath = ".loa.config.yaml"): AgyGate {
>  160 |   let optIn = false;
>  161 |   let mode = "";
>  162 |   try {
>  163 |     const out = execFileSync(
>  164 |       "yq",
>  165 |       ["eval", "-o=json", "-I=0",
>  166 |         '{"opt": (.hounfour.headless.agy_opt_in | (tag == "!!bool" and . == true)), "mode": (.hounfour.headless.mode // "")}',
>  167 |         configPath],
>  168 |       { encoding: "utf8", timeout: 5000, stdio: ["ignore", "pipe", "ignore"] },
>  169 |     );
>  170 |     const parsed = JSON.parse(out) as { opt?: unknown; mode?: unknown };
>  171 |     optIn = parsed.opt === true;
>  172 |     mode = typeof parsed.mode === "string" ? parsed.mode : "";
>  173 |   } catch {
>  174 |     // (fail closed: no opt-in)
>  175 |   }
>  176 |   return { optIn, mode: process.env.LOA_HEADLESS_MODE || mode || "prefer-api" };
>  177 | }
>  178 | 
>  179 | /** A voice cheval would dispatch through agy: the gemini-headless id, or any google model when headless mode is cli-only. */
>  180 | export function isAgyRouted(provider: string, modelId: string, mode: string): boolean {
>  181 |   if (provider !== "google") return false;
>  182 |   return modelId === "gemini-headless" || mode === "cli-only";
   183 | }
   184 | 
   185 | /**
   186 |  * Validate API keys for configured multi-model providers.
   187 |  * Returns available and missing provider lists, and the voices not planned because their agy route's opt-in is off
   188 |  * (cycle-127 FR-1: neither valid nor missing — a voice that cannot exist on this host is never counted as a failed one).
   189 |  */
   190 | export function validateApiKeys(config: MultiModelConfig, gate: AgyGate = readAgyGate()): {
   191 |   valid: Array<{ provider: string; modelId: string }>;
   192 |   missing: Array<{ provider: string; envVar: string }>;
   193 |   notPlanned: Array<{ provider: string; modelId: string; reason: "opt_in_required" }>;
   194 | } {
~~~~

The change from head to the fix:

~~~~diff
@@ -157,26 +252,108 @@
- * file, a missing yq or an unreadable config reads as off — the gate fails closed.
+ * file reads as off; a missing yq or an unreadable config reads as off too (the gate fails closed) and carries `readError`.
  */
-export function readAgyGate(configPath = ".loa.config.yaml"): AgyGate {
+export function readAgyGate(configPath: string): AgyGate {
   let optIn = false;
   let mode = "";
-  try {
-    const out = execFileSync(
-      "yq",
-      ["eval", "-o=json", "-I=0",
-        '{"opt": (.hounfour.headless.agy_opt_in | (tag == "!!bool" and . == true)), "mode": (.hounfour.headless.mode // "")}',
-        configPath],
-      { encoding: "utf8", timeout: 5000, stdio: ["ignore", "pipe", "ignore"] },
-    );
-    const parsed = JSON.parse(out) as { opt?: unknown; mode?: unknown };
-    optIn = parsed.opt === true;
-    mode = typeof parsed.mode === "string" ? parsed.mode : "";
-  } catch {
-    // (fail closed: no opt-in)
+  let readError: string | undefined;
+  let typeWarning: string | undefined;
+  if (existsSync(configPath)) {
+    let fd: number | undefined;
+    let content: Buffer | undefined;
+    try {
+      // (r251-6 V3, BB #2: the config is opened ONCE — yq parses the bytes read from this descriptor on stdin and the trust
+      // rule judges its fstat, so a swap of the path between read and check changes nothing)
+      fd = openSync(configPath, "r");
+      const st = fstatSync(fd);
+      if (!st.isFile()) throw new Error(`${configPath} is not a regular file`);
+      content = readFileSync(fd);
+      const out = execFileSync(
+        "yq",
+        ["eval", "-o=json", "-I=0",
+          `{"has": (${AGY_YQ_HAS}), "kind": (.hounfour.headless.agy_opt_in | kind), "opt": (.hounfour.headless.agy_opt_in | (tag == "!!bool" and . == true)), "canon": (.hounfour.headless.agy_opt_in | (tag == "!!bool" and (. == true or . == false))), "tag": (.hounfour.headless.agy_opt_in | tag), "mode": (.hounfour.headless.mode // ""), ${AGY_YQ_ANCESTORS}}`,
+          "-"],
+        { encoding: "utf8", timeout: 5000, input: content, stdio: ["pipe", "pipe", "pipe"] },
+      );
+      const parsed = JSON.parse(out) as {
+        has?: unknown; kind?: unknown; opt?: unknown; canon?: unknown; tag?: unknown; mode?: unknown;
+        k1?: unknown; t1?: unknown; k2?: unknown; t2?: unknown;
+      };
+      // (r251-4 S3: the key must be written at hounfour.headless itself — every level a real mapping, never an alias or a
+      // merge key's value — and its node a plain scalar of the exact bool tag; one rule with the bash and Python readers)
+      const present = parsed.has === true;
+      const alias = parsed.kind === "alias";
+      optIn = present && !alias && parsed.opt === true;
+      mode = typeof parsed.mode === "string" ? parsed.mode : "";
+      const ancestor = present ? undefined : agyAncestorProblem(parsed);
+      // (r251-5 U1: a config others can write never opts in — one WARN naming the key and the reason; not a readError:
+      // the gate reads off, exactly as the bash and Python readers, rather than blocking the merge. Only a value that
+      // would opt in is judged, as there: a config that reads off anyway is not flagged)
+      const untrusted = optIn ? agyConfigUntrustedReason(configPath, st, fd) : undefined;
+      if (untrusted !== undefined) {
+        optIn = false;
+        typeWarning = `hounfour.headless.agy_opt_in: ${untrusted} — a config others can write never opts in (own it and \`chmod go-w\` it); the agy route stays off`;
+      } else if (ancestor !== undefined) {
+        typeWarning = `${ancestor} — hounfour.headless.agy_opt_in cannot be read through an alias or merge node (write the mapping inline); the agy route stays off`;
+      } else if (present && alias) {
+        typeWarning = "hounfour.headless.agy_opt_in is present but not a YAML boolean (an alias) — only `agy_opt_in: true` opts in (expected true or false); the agy route stays off";
+      } else if (present && typeof parsed.tag === "string" && parsed.tag !== "!!null" && parsed.tag !== "!!bool") {
+        typeWarning = `hounfour.headless.agy_opt_in is present but not a YAML boolean (${parsed.tag}) — only \`agy_opt_in: true\` opts in (expected true or false); the agy route stays off`;
+      } else if (present && parsed.tag === "!!bool" && parsed.canon !== true) {
+        typeWarning = "hounfour.headless.agy_opt_in is a boolean spelled other than true/false — only `agy_opt_in: true` opts in (the lowercase scalar); the agy route stays off";
+      }
+    } catch (err) {
+      // (fail closed: no opt-in — and say why, rather than reading as a plain "opt-in off")
+      const e = err as { stderr?: unknown; message?: string };
+      const stderr = typeof e.stderr === "string" ? e.stderr.trim() : Buffer.isBuffer(e.stderr) ? e.stderr.toString("utf8").trim() : "";
+      optIn = false;
+      // (r251-6 V5: a non-mapping ancestor yq cannot index below — `headless: [1]` — is the ancestor warning the bash and
+      // Python readers give, not a host read error; the same bytes, the guarded ancestors-only program)
+      const ancestor = content !== undefined ? agyAncestorOnly(content) : undefined;
+      if (ancestor !== undefined) {
+        typeWarning = `${ancestor} — hounfour.headless.agy_opt_in cannot be read through an alias or merge node (write the mapping inline); the agy route stays off`;
+      } else {
+        readError = (stderr || e.message || String(err)).split("\n")[0].slice(0, 300);
+      }
+    } finally {
+      if (fd !== undefined) closeSync(fd);
+    }
   }
-  return { optIn, mode: process.env.LOA_HEADLESS_MODE || mode || "prefer-api" };
+  return {
+    optIn, mode: process.env.LOA_HEADLESS_MODE || mode || "prefer-api",
+    ...(readError !== undefined ? { readError } : {}), ...(typeWarning !== undefined ? { typeWarning } : {}),
+  };
 }
 
-/** A voice cheval would dispatch through agy: the gemini-headless id, or any google model when headless mode is cli-only. */
+/** The ancestors' kind and tag (r251-6 V5): `hounfour`, and `hounfour.headless` only below a real mapping. */
+export const AGY_YQ_ANCESTORS = '"k1": (.hounfour | kind), "t1": (.hounfour | tag), "k2": ((.hounfour | select(kind == "map") | .headless | kind) // ""), "t2": ((.hounfour | select(kind == "map") | .headless | tag) // "")';
+
+/** The ancestors-only read of `content` (never errors on a non-mapping level: each level is guarded); undefined on any failure. */
+function agyAncestorOnly(content: Buffer): string | undefined {
+  try {
+    const out = execFileSync("yq", ["eval", "-o=json", "-I=0", `{${AGY_YQ_ANCESTORS}}`, "-"],
+      { encoding: "utf8", timeout: 5000, input: content, stdio: ["pipe", "pipe", "pipe"] });
+    return agyAncestorProblem(JSON.parse(out));
+  } catch {
+    return undefined;
+  }
+}
+
+/** `<path> is a YAML alias` / `<path> is not a mapping (<kind>)` for an alias or non-mapping ancestor of the key — one WARN,
+ * never a silent absent (r251-6 V5, BB #5; the bash and Python readers say the same); undefined when every ancestor is a
+ * mapping, absent or null. */
+function agyAncestorProblem(p: { k1?: unknown; t1?: unknown; k2?: unknown; t2?: unknown }): string | undefined {
+  for (const [path, k, t] of [["hounfour", p.k1, p.t1], ["hounfour.headless", p.k2, p.t2]] as const) {
+    if (k === "map") continue;
+    if (k === "alias") return `${path} is a YAML alias`;
+    if (typeof t !== "string" || t === "" || t === "!!null") return undefined;
+    return `${path} is not a mapping (${t.replace(/^!!/, "")})`;
+  }
+  return undefined;
+}
+
+/**
+ * A voice cheval would dispatch through agy: a google headless id of the generated registry (today `gemini-headless`), or
+ * any google model when the effective headless mode is cli-only (the bash/Python predicate's shape — lib/agy-gate-lib.sh).
+ */
 export function isAgyRouted(provider: string, modelId: string, mode: string): boolean {
   if (provider !== "google") return false;
-  return modelId === "gemini-headless" || mode === "cli-only";
+  return isHeadlessModelId(modelId, "google") || mode === "cli-only";
~~~~

## H159 — .claude/skills/bridgebuilder-review/resources/config.ts — head line 190

Head context (head/.claude/skills/bridgebuilder-review/resources/config.ts, lines 178–202):

~~~~text
   178 | 
   179 | /** A voice cheval would dispatch through agy: the gemini-headless id, or any google model when headless mode is cli-only. */
   180 | export function isAgyRouted(provider: string, modelId: string, mode: string): boolean {
   181 |   if (provider !== "google") return false;
   182 |   return modelId === "gemini-headless" || mode === "cli-only";
   183 | }
   184 | 
   185 | /**
   186 |  * Validate API keys for configured multi-model providers.
   187 |  * Returns available and missing provider lists, and the voices not planned because their agy route's opt-in is off
   188 |  * (cycle-127 FR-1: neither valid nor missing — a voice that cannot exist on this host is never counted as a failed one).
   189 |  */
>  190 | export function validateApiKeys(config: MultiModelConfig, gate: AgyGate = readAgyGate()): {
   191 |   valid: Array<{ provider: string; modelId: string }>;
   192 |   missing: Array<{ provider: string; envVar: string }>;
   193 |   notPlanned: Array<{ provider: string; modelId: string; reason: "opt_in_required" }>;
   194 | } {
   195 |   const valid: Array<{ provider: string; modelId: string }> = [];
   196 |   const missing: Array<{ provider: string; envVar: string }> = [];
   197 |   const notPlanned: Array<{ provider: string; modelId: string; reason: "opt_in_required" }> = [];
   198 | 
   199 |   for (const model of config.models) {
   200 |     if (!gate.optIn && isAgyRouted(model.provider, model.model_id, gate.mode)) {
   201 |       notPlanned.push({ provider: model.provider, modelId: model.model_id, reason: "opt_in_required" });
   202 |       continue;
~~~~

The change from head to the fix:

~~~~diff
@@ -190 +367 @@
-export function validateApiKeys(config: MultiModelConfig, gate: AgyGate = readAgyGate()): {
+export function validateApiKeys(config: MultiModelConfig, gate: AgyGate): {
~~~~

## H160 — .claude/skills/bridgebuilder-review/resources/config.ts — head line 200

Head context (head/.claude/skills/bridgebuilder-review/resources/config.ts, lines 188–212):

~~~~text
   188 |  * (cycle-127 FR-1: neither valid nor missing — a voice that cannot exist on this host is never counted as a failed one).
   189 |  */
   190 | export function validateApiKeys(config: MultiModelConfig, gate: AgyGate = readAgyGate()): {
   191 |   valid: Array<{ provider: string; modelId: string }>;
   192 |   missing: Array<{ provider: string; envVar: string }>;
   193 |   notPlanned: Array<{ provider: string; modelId: string; reason: "opt_in_required" }>;
   194 | } {
   195 |   const valid: Array<{ provider: string; modelId: string }> = [];
   196 |   const missing: Array<{ provider: string; envVar: string }> = [];
   197 |   const notPlanned: Array<{ provider: string; modelId: string; reason: "opt_in_required" }> = [];
   198 | 
   199 |   for (const model of config.models) {
>  200 |     if (!gate.optIn && isAgyRouted(model.provider, model.model_id, gate.mode)) {
   201 |       notPlanned.push({ provider: model.provider, modelId: model.model_id, reason: "opt_in_required" });
   202 |       continue;
   203 |     }
   204 |     const envVar = PROVIDER_API_KEY_ENV[model.provider];
   205 |     if (!envVar) {
   206 |       missing.push({ provider: model.provider, envVar: `Unknown provider: ${model.provider}` });
   207 |       continue;
   208 |     }
   209 |     // (a `*-headless` entry is a cheval CLI hop that authenticates itself — every voice dispatches through cheval — so
   210 |     // it needs no key; the gate dropped the keyless host's claude-headless entry: cycle-126 thirty-seventh run, e2b DISS-C-003)
   211 |     if (isHeadlessModelId(model.model_id, model.provider) || process.env[envVar]) {
   212 |       valid.push({ provider: model.provider, modelId: model.model_id });
~~~~

The change from head to the fix:

~~~~diff
@@ -200 +377,4 @@
-    if (!gate.optIn && isAgyRouted(model.provider, model.model_id, gate.mode)) {
+    // (r251-2 K7b: an unreadable config fails closed for EVERY google voice — its mode is unknown, so is its route: cheval,
+    // reading the same file with PyYAML, might route it to agy and refuse; planned-as-HTTP would mis-count a failed voice)
+    const gated = gate.readError !== undefined ? model.provider === "google" : isAgyRouted(model.provider, model.model_id, gate.mode);
+    if (!gate.optIn && gated) {
~~~~

## H161 — .claude/skills/bridgebuilder-review/resources/config.ts — insertion after head line 220

Head context (head/.claude/skills/bridgebuilder-review/resources/config.ts, lines 209–232):

~~~~text
   209 |     // (a `*-headless` entry is a cheval CLI hop that authenticates itself — every voice dispatches through cheval — so
   210 |     // it needs no key; the gate dropped the keyless host's claude-headless entry: cycle-126 thirty-seventh run, e2b DISS-C-003)
   211 |     if (isHeadlessModelId(model.model_id, model.provider) || process.env[envVar]) {
   212 |       valid.push({ provider: model.provider, modelId: model.model_id });
   213 |     } else {
   214 |       missing.push({ provider: model.provider, envVar });
   215 |     }
   216 |   }
   217 | 
   218 |   return { valid, missing, notPlanned };
   219 | }
   220 | 
   221 | /** Built-in defaults per PRD FR-4 (lowest priority). */
   222 | const DEFAULTS: BridgebuilderConfig = {
   223 |   repos: [],
   224 |   // cycle-126 FR-1.5 (SDD D-1.5): the `opus` alias (resolved by cheval's alias
   225 |   // path, so the default follows the catalog's retarget instead of pinning a
   226 |   // snapshot); the input default matches the 200K-class payload the 5-family
   227 |   // reviews take, the output default the BB_OUTPUT_CAP of the generated table.
   228 |   model: "opus",
   229 |   maxPrs: 10,
   230 |   maxFilesPerPr: 50,
   231 |   maxDiffBytes: 512_000,
   232 |   maxInputTokens: 200_000,
~~~~

The change from head to the fix:

~~~~diff
@@ -220,0 +401,17 @@
+/**
+ * The startup lines for the agy gate (r251-2 K7f): the read error and the type warning each said once, unconditionally —
+ * not only when a voice is not planned — and the not-planned voices. main.ts prints them; the pipeline says its own once
+ * per review.
+ */
+export function agyGateStartupLines(gate: AgyGate, keyStatus: ReturnType<typeof validateApiKeys>): string[] {
+  const lines: string[] = [];
+  if (gate.readError !== undefined) {
+    lines.push(`[bridgebuilder] agy gate: Loa config unreadable (${gate.readError}) — failing closed: google voices are not planned (hounfour.headless.agy_opt_in)`);
+  }
+  if (gate.typeWarning !== undefined) lines.push(`[bridgebuilder] ${gate.typeWarning}`);
+  if (keyStatus.notPlanned.length > 0) {
+    lines.push(`[bridgebuilder] Not planned (agy opt-in, hounfour.headless.agy_opt_in): ${keyStatus.notPlanned.map((n) => `${n.provider}/${n.modelId}`).join(", ")}`);
+  }
+  return lines;
+}
+
~~~~

## H162 — .claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts — head line 26

Head context (head/.claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts, lines 14–38):

~~~~text
    14 | import type { ILogger } from "../ports/logger.js";
    15 | import type {
    16 |   BridgebuilderConfig,
    17 |   MultiModelConfig,
    18 |   ReviewItem,
    19 |   ReviewResult,
    20 |   ReviewError,
    21 | } from "./types.js";
    22 | import { summarizeReviewVerdict, type ReviewVerdict } from "./review-verdict.js";
    23 | import { scoreFindings } from "./scoring.js";
    24 | import type { ModelFindings, ScoredFinding, ScoringResult } from "./scoring.js";
    25 | import { createAdapter } from "../adapters/adapter-factory.js";
>   26 | import { PROVIDER_API_KEY_ENV, isHeadlessModelId, readAgyGate, validateApiKeys } from "../config.js";
    27 | import { GENERATED_MODEL_REGISTRY, GENERATED_REASONING } from "../config.generated.js";
    28 | import type { LoreEntry, PRReviewTemplate } from "./template.js";
    29 | 
    30 | /**
    31 |  * Per-model timeout derivation — reasoning-class predicate (multi-provider).
    32 |  *
    33 |  * History:
    34 |  *   - cycle-100 sprint-bug-143 (#789a) introduced the 1_800_000ms (30-min)
    35 |  *     budget for OpenAI `gpt-*-pro` after gpt-5.5-pro hung past 900s on a
    36 |  *     95k-token diff (most of the budget is spent on internal reasoning
    37 |  *     before any visible tokens emit).
    38 |  *   - cycle-111 sprint-bug-165 (#921) extended the predicate to the rest
~~~~

The change from head to the fix:

~~~~diff
@@ -26 +26 @@
-import { PROVIDER_API_KEY_ENV, isHeadlessModelId, readAgyGate, validateApiKeys } from "../config.js";
+import { PROVIDER_API_KEY_ENV, isHeadlessModelId, loaConfigPathFor, readAgyGate, validateApiKeys } from "../config.js";
~~~~

## H163 — .claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts — head lines 172–174

Head context (head/.claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts, lines 160–186):

~~~~text
   160 | export async function executeMultiModelReview(
   161 |   item: ReviewItem,
   162 |   systemPrompt: string,
   163 |   userPrompt: string,
   164 |   config: BridgebuilderConfig,
   165 |   adapters: PipelineAdapters,
   166 |   enrichment?: EnrichmentContext,
   167 | ): Promise<MultiModelReviewResult> {
   168 |   const multiConfig = config.multiModel!;
   169 |   const { poster, sanitizer, logger } = adapters;
   170 | 
   171 |   // Validate API keys (cycle-127 FR-1: and the agy opt-in, read from the repo's Loa config)
>  172 |   const keyStatus = validateApiKeys(multiConfig, readAgyGate(config.repoRoot ? path.join(config.repoRoot, ".loa.config.yaml") : ".loa.config.yaml"));
>  173 |   for (const np of keyStatus.notPlanned) {
>  174 |     logger.info(`${np.provider} voice not planned: agy opt-in off (hounfour.headless.agy_opt_in)`);
   175 |   }
   176 |   if (multiConfig.api_key_mode === "strict" && keyStatus.missing.length > 0) {
   177 |     throw new Error(
   178 |       `Strict mode: missing API keys for providers: ${keyStatus.missing.map((m) => m.provider).join(", ")}`,
   179 |     );
   180 |   }
   181 | 
   182 |   // Create adapters for available providers
   183 |   const modelAdapters: Array<{
   184 |     provider: string;
   185 |     modelId: string;
   186 |     adapter: ILLMProvider;
~~~~

The change from head to the fix:

~~~~diff
@@ -172,3 +172,26 @@
-  const keyStatus = validateApiKeys(multiConfig, readAgyGate(config.repoRoot ? path.join(config.repoRoot, ".loa.config.yaml") : ".loa.config.yaml"));
+  const agyGate = readAgyGate(loaConfigPathFor(config.repoRoot));
+  const keyStatus = validateApiKeys(multiConfig, agyGate);
+  // (r251-1 G12/G14: an unreadable config or a non-boolean opt-in is said once, with its reason — not as "opt-in off")
+  const notPlannedList = keyStatus.notPlanned.map((np) => `${np.provider}/${np.modelId}`).join(", ");
+  if (agyGate.readError !== undefined) {
+    // (r251-2 K7d: the strict per-voice warn is skipped under a read error, so this one names the voices)
+    logger.warn(`[multi-model] agy gate unreadable (${agyGate.readError}) — failing closed: google voices are not planned (hounfour.headless.agy_opt_in)` +
+      (notPlannedList ? `; will not run: ${notPlannedList}` : ""));
+  }
+  if (agyGate.typeWarning !== undefined) logger.warn(`[multi-model] ${agyGate.typeWarning}`);
   for (const np of keyStatus.notPlanned) {
-    logger.info(`${np.provider} voice not planned: agy opt-in off (hounfour.headless.agy_opt_in)`);
+    // (review r251-1 G3, finding 20: strict mode promises every configured voice — one the gate removes is said at warn,
+    // never thrown: the voice cannot exist on this host, it is not a missing key)
+    if (agyGate.readError !== undefined) continue;   // (already said, with the reason)
+    if (multiConfig.api_key_mode === "strict") {
+      logger.warn(`[multi-model] strict mode: configured voice ${np.provider}/${np.modelId} will not run — not planned: the agy route is opt-in (hounfour.headless.agy_opt_in is not true)`);
+    } else {
+      logger.info(`${np.provider} voice not planned: agy opt-in off (hounfour.headless.agy_opt_in)`);
+    }
+  }
+  // (r251-4 S1, audit n22: a read error is a HOST fault, not a decision — strict mode promised every configured voice, so a
+  // voice the failed read removed refuses the review; graceful mode runs the rest but never clears the merge, below)
+  if (multiConfig.api_key_mode === "strict" && agyGate.readError !== undefined && keyStatus.notPlanned.length > 0) {
+    throw new Error(
+      `Strict mode: the Loa config is unreadable (${agyGate.readError}) — the agy gate failed closed and configured voices will not run: ${notPlannedList} (hounfour.headless.agy_opt_in)`,
+    );
~~~~

## H164 — .claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts — head line 212

Head context (head/.claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts, lines 200–224):

~~~~text
   200 |       timeoutMs: deriveTimeoutMs(entry.provider, entry.modelId, config),
   201 |       costRates,
   202 |     });
   203 | 
   204 |     modelAdapters.push({
   205 |       provider: entry.provider,
   206 |       modelId: entry.modelId,
   207 |       adapter,
   208 |     });
   209 |   }
   210 | 
   211 |   if (modelAdapters.length === 0) {
>  212 |     throw new Error("No models available for multi-model review (all API keys missing)");
   213 |   }
   214 | 
   215 |   // Limit concurrency
   216 |   const concurrency = Math.min(
   217 |     modelAdapters.length,
   218 |     multiConfig.max_concurrency ?? 3,
   219 |   );
   220 | 
   221 |   logger.info("[multi-model] Starting parallel review", {
   222 |     models: modelAdapters.map((m) => `${m.provider}/${m.modelId}`),
   223 |     concurrency,
   224 |   });
~~~~

The change from head to the fix:

~~~~diff
@@ -212 +235,16 @@
-    throw new Error("No models available for multi-model review (all API keys missing)");
+    // (r251-2 K7c: ONE message, the not-planned voices and the missing keys listed separately — the reason for a not-planned
+    // voice is the read error when the config could not be read, else the opt-in)
+    const parts: string[] = [];
+    if (keyStatus.notPlanned.length > 0) {
+      parts.push(agyGate.readError !== undefined
+        ? `not planned: ${notPlannedList} (the agy gate failed closed: Loa config unreadable — ${agyGate.readError}; hounfour.headless.agy_opt_in)`
+        : `not planned: ${notPlannedList} (the agy route is opt-in: set hounfour.headless.agy_opt_in: true)`);
+    }
+    if (keyStatus.missing.length > 0) {
+      parts.push(`missing API keys: ${keyStatus.missing.map((m) => `${m.provider} (${m.envVar})`).join(", ")}`);
+    }
+    throw new Error(
+      parts.length > 0 && keyStatus.missing.length > 0 && keyStatus.notPlanned.length === 0
+        ? `No models available for multi-model review (all API keys missing): ${parts.join("; ")}`
+        : `No models available for multi-model review — ${parts.length > 0 ? parts.join("; ") : "no configured voice is usable"}`,
+    );
~~~~

## H165 — .claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts — insertion after head line 352

Head context (head/.claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts, lines 341–364):

~~~~text
   341 |   // review over the consensus findings. Falls back to stats-only if enrichment
   342 |   // fails or is disabled.
   343 |   // cycle-109 Sprint 2 T2.6 — prepend the verdict_quality header
   344 |   // (FR-2.8) before the consensus stats table. Returns empty string when
   345 |   // no per-model envelopes carry verdictQuality (legacy / pre-T2.3
   346 |   // cheval), so legacy review surfaces are unchanged.
   347 |   const verdictHeader = formatVerdictQualityHeader(
   348 |     modelResults.map((r) => ({
   349 |       provider: r.provider,
   350 |       modelId: r.model,
   351 |       verdictQuality: r.response?.verdictQuality,
   352 |     })),
   353 |   );
   354 |   // cycle-118 bd-bb-degraded-verdict-ts — append a DEGRADED/FAILED trajectory
   355 |   // record (same channel/schema as the 3 bash gate writers). No-op when the
   356 |   // aggregate band is APPROVED/clean. Fire-and-forget: never throws.
   357 |   await emitDegradedVerdictTrajectory(
   358 |     item,
   359 |     modelResults.map((r) => ({ verdictQuality: r.response?.verdictQuality })),
   360 |     { repoRoot: config.repoRoot },
   361 |   );
   362 |   let consensusBody = verdictHeader + formatConsensusSummary(consensus, modelAdapters);
   363 | 
   364 |   if (enrichment && findingsPerModel.length > 0 && modelAdapters.length > 0) {
~~~~

The change from head to the fix:

~~~~diff
@@ -352,0 +391,3 @@
+    // (r251-4 S8, audit n21: the posted line names the voices that were not planned, and why)
+    keyStatus.notPlanned.map((np) => ({ provider: np.provider, modelId: np.modelId })),
+    agyGate.readError !== undefined ? "Loa config unreadable — the agy gate failed closed" : "agy opt-in off: hounfour.headless.agy_opt_in",
~~~~

## H166 — .claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts — head lines 421–422

Head context (head/.claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts, lines 409–434):

~~~~text
   409 |   }
   410 | 
   411 |   const combinedContent = modelResults
   412 |     .filter((r) => r.response)
   413 |     .map((r) => r.response!.content)
   414 |     .join("\n\n---\n\n");
   415 |   const findings = findingsPerModel.flatMap((result) => result.findings);
   416 |   let reviewVerdict = summarizeReviewVerdict(combinedContent, findings);
   417 |   // Enrichment may surface a blocker; it cannot approve unparsed reviews.
   418 |   if (summarizeReviewVerdict(consensusBody).verdict === "REQUEST_CHANGES") {
   419 |     reviewVerdict = summarizeReviewVerdict(combinedContent + "\n" + consensusBody, findings);
   420 |   }
>  421 |   // Incomplete or degraded participation can never clear a merge.
>  422 |   if (modelResults.length !== multiConfig.models.length - keyStatus.notPlanned.length ||
   423 |       modelResults.some((result) => result.error || !result.response) ||
   424 |       computeVerdictBand(modelResults.map((result) => ({ verdictQuality: result.response?.verdictQuality }))) !== "APPROVED") {
   425 |     reviewVerdict.mergeBlocked = true;
   426 |   }
   427 | 
   428 |   return {
   429 |     modelResults,
   430 |     consensus,
   431 |     posted: overallPosted || modelResults.some((r) => r.posted),
   432 |     combinedContent,
   433 |     reviewVerdict,
   434 |     notPlanned: keyStatus.notPlanned,
~~~~

The change from head to the fix:

~~~~diff
@@ -421,2 +462,7 @@
-  // Incomplete or degraded participation can never clear a merge.
-  if (modelResults.length !== multiConfig.models.length - keyStatus.notPlanned.length ||
+  // Incomplete or degraded participation can never clear a merge. A voice the opt-in decision removed is not expected; a
+  // voice a READ ERROR removed still is (r251-4 S1, audit n22: a host fault never shrinks the quorum).
+  if (agyGate.readError !== undefined && keyStatus.notPlanned.length > 0) {
+    reviewVerdict.mergeBlocked = true;
+    reviewVerdict.mergeBlockedReason = `Loa config unreadable (${agyGate.readError}): the agy gate failed closed and ${notPlannedList} did not run`;
+  }
+  if (modelResults.length !== multiConfig.models.length - (agyGate.readError !== undefined ? 0 : keyStatus.notPlanned.length) ||
~~~~

## H167 — .claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts — insertion after head line 628

Head context (head/.claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts, lines 617–640):

~~~~text
   617 | 
   618 | export function formatVerdictQualityHeader(
   619 |   perModelResults: Array<{
   620 |     provider: string;
   621 |     modelId: string;
   622 |     verdictQuality?: {
   623 |       status?: string;
   624 |       voices_succeeded?: number;
   625 |       voices_planned?: number;
   626 |       chain_health?: string;
   627 |     };
   628 |   }>,
   629 | ): string {
   630 |   const band = computeVerdictBand(perModelResults);
   631 |   if (band === null) return "";
   632 | 
   633 |   // Aggregate stats from per-voice envelopes. Each cheval cmd_invoke
   634 |   // produces a SINGLE-voice envelope (voices_planned=1). For the BB
   635 |   // multi-voice cohort we count the number of envelopes that ended in
   636 |   // each status.
   637 |   const total = perModelResults.length;
   638 |   const withEnvelope = perModelResults.filter((r) => r.verdictQuality);
   639 |   const succeeded = withEnvelope.filter(
   640 |     (r) => r.verdictQuality?.status === "APPROVED" || r.verdictQuality?.status === "DEGRADED",
~~~~

The change from head to the fix:

~~~~diff
@@ -628,0 +675,2 @@
+  notPlanned: ReadonlyArray<{ provider: string; modelId: string }> = [],
+  notPlannedReason = "agy opt-in off: hounfour.headless.agy_opt_in",
~~~~

## H168 — .claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts — head line 652

Head context (head/.claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts, lines 640–664):

~~~~text
   640 |     (r) => r.verdictQuality?.status === "APPROVED" || r.verdictQuality?.status === "DEGRADED",
   641 |   ).length;
   642 | 
   643 |   let banner: string;
   644 |   if (band === "FAILED") {
   645 |     banner = `❌ FAILED — ${succeeded}/${total} voices succeeded; verdict unsafe`;
   646 |   } else if (band === "DEGRADED") {
   647 |     banner = `⚠ DEGRADED — ${succeeded}/${total} voices succeeded`;
   648 |   } else {
   649 |     banner = `✓ APPROVED — ${succeeded}/${total} voices, chain ok`;
   650 |   }
   651 | 
>  652 |   return `**Verdict Quality**: ${banner}\n\n`;
   653 | }
   654 | 
   655 | /**
   656 |  * A degraded-verdict trajectory record — byte-compatible with the record
   657 |  * shape written by degraded-verdict-lib.sh (cycle-117 item D). Field set and
   658 |  * ordering intentionally mirror that bash writer and the schema at
   659 |  * .claude/data/trajectory-schemas/degraded-verdict.schema.json
   660 |  * (additionalProperties: false — do NOT add fields).
   661 |  */
   662 | export interface DegradedVerdictRecord {
   663 |   gate: string;
   664 |   verdict_band: "DEGRADED" | "FAILED";
~~~~

The change from head to the fix:

~~~~diff
@@ -652 +700,4 @@
-  return `**Verdict Quality**: ${banner}\n\n`;
+  const np = notPlanned.length > 0
+    ? ` · not planned: ${notPlanned.map((n) => `${n.provider}/${n.modelId}`).join(", ")} (${notPlannedReason})`
+    : "";
+  return `**Verdict Quality**: ${banner}${np}\n\n`;
~~~~

## H169 — .claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts — insertion after head line 14

Head context (head/.claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts, lines 3–26):

~~~~text
     3 | // Source: .claude/defaults/model-config.yaml
     4 | //
     5 | // Per-provider defaults applied at codegen time (yaml tracks API context_window
     6 | // only; maxOutput + coefficient are BB-skill truncation heuristics):
     7 | //   anthropic / bedrock / google: maxOutput=8192, coefficient=0.25
     8 | //   openai:                       maxOutput=4096, coefficient=0.23
     9 | //   default fallback:             maxInput=100000, maxOutput=4096, coefficient=0.25
    10 | //
    11 | // maxInput = effective_input_ceiling − 20000 when the yaml entry carries the
    12 | // v3 ceiling (cycle-124 FR-3 / SDD §2.1: BB truncates below cheval's pre-flight
    13 | // gate instead of dispatching what exit 7 would reject), else context_window.
    14 | //
    15 | // GENERATED_MODEL_ALIASES maps the catalog's `aliases:` block to bare model
    16 | // ids (provider-qualified targets only; self-maps dropped) so an alias such as
    17 | // `opus` gets its target's budget. An operator alias overlay in
    18 | // .loa.config.yaml is NOT reflected — pin a concrete model or set
    19 | // max_input_tokens (cycle-126 sprint-250).
    20 | //
    21 | // cycle-099 sprint-1 (T1.1). See SDD §1.4.3 + §5.3.
    22 | 
    23 | import type { TokenBudget } from "./types.js";
    24 | 
    25 | export const GENERATED_TOKEN_BUDGETS: Record<string, TokenBudget> = {
    26 |   "claude-fable-5": { maxInput: 160000, maxOutput: 32000, coefficient: 0.25 },
~~~~

The change from head to the fix:

~~~~diff
@@ -14,0 +15,7 @@
+// Units (cycle-127 r251-1): a calibrated entry whose ceiling_calibration records
+// measured_input_tokens carries its ceiling in provider-measured tokens, while
+// maxInput is in BB's estimate units (coefficient tokens/char), which under-count
+// the Opus 4.7+ tokenizer — so for those entries
+// maxInput = floor((effective_input_ceiling − 20000) / MEASURED_TO_ESTIMATE_SAFETY / 1000) × 1000,
+// with MEASURED_TO_ESTIMATE_SAFETY = 1.8.
+//
~~~~

## H170 — .claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts — head line 34

Head context (head/.claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts, lines 22–46):

~~~~text
    22 | 
    23 | import type { TokenBudget } from "./types.js";
    24 | 
    25 | export const GENERATED_TOKEN_BUDGETS: Record<string, TokenBudget> = {
    26 |   "claude-fable-5": { maxInput: 160000, maxOutput: 32000, coefficient: 0.25 },
    27 |   "claude-fable-5-1": { maxInput: 160000, maxOutput: 32000, coefficient: 0.25 },
    28 |   "claude-haiku-4-5-20251001": { maxInput: 160000, maxOutput: 8192, coefficient: 0.25 },
    29 |   "claude-headless": { maxInput: 1000000, maxOutput: 8192, coefficient: 0.25 },
    30 |   "claude-opus-4-6": { maxInput: 160000, maxOutput: 32000, coefficient: 0.25 },
    31 |   "claude-opus-4-7": { maxInput: 160000, maxOutput: 32000, coefficient: 0.25 },
    32 |   "claude-opus-4-8": { maxInput: 160000, maxOutput: 32000, coefficient: 0.25 },
    33 |   "claude-opus-5": { maxInput: 160000, maxOutput: 32000, coefficient: 0.25 },
>   34 |   "claude-opus-5-5": { maxInput: 916000, maxOutput: 32000, coefficient: 0.25 },
    35 |   "claude-sonnet-4-5-20250929": { maxInput: 160000, maxOutput: 8192, coefficient: 0.25 },
    36 |   "claude-sonnet-4-6": { maxInput: 160000, maxOutput: 32000, coefficient: 0.25 },
    37 |   "claude-sonnet-5": { maxInput: 160000, maxOutput: 32000, coefficient: 0.25 },
    38 |   "us.anthropic.claude-haiku-4-5-20251001-v1:0": { maxInput: 200000, maxOutput: 8192, coefficient: 0.25 },
    39 |   "us.anthropic.claude-opus-4-7": { maxInput: 200000, maxOutput: 8192, coefficient: 0.25 },
    40 |   "us.anthropic.claude-opus-4-8": { maxInput: 200000, maxOutput: 8192, coefficient: 0.25 },
    41 |   "us.anthropic.claude-sonnet-4-6": { maxInput: 200000, maxOutput: 8192, coefficient: 0.25 },
    42 |   "composer-2.5": { maxInput: 200000, maxOutput: 4096, coefficient: 0.25 },
    43 |   "composer-2.5-fast": { maxInput: 200000, maxOutput: 4096, coefficient: 0.25 },
    44 |   "deep-research-pro": { maxInput: 1048576, maxOutput: 8192, coefficient: 0.25 },
    45 |   "gemini-2.0-flash": { maxInput: 1048576, maxOutput: 8192, coefficient: 0.25 },
    46 |   "gemini-2.5-flash": { maxInput: 1048576, maxOutput: 8192, coefficient: 0.25 },
~~~~

The change from head to the fix:

~~~~diff
@@ -34 +41 @@
-  "claude-opus-5-5": { maxInput: 916000, maxOutput: 32000, coefficient: 0.25 },
+  "claude-opus-5-5": { maxInput: 508000, maxOutput: 32000, coefficient: 0.25 },
~~~~

## H171 — .loa.config.yaml.example — head lines 748–749

Head context (head/.loa.config.yaml.example, lines 736–761):

~~~~text
   736 |   # to issue HTTPS when the resolved chain is CLI-only (defense-in-depth,
   737 |   # SDD §1.9). Operator runbooks (cycle-104 T2.12):
   738 |   #   grimoires/loa/runbooks/headless-mode.md            # 4-mode reference
   739 |   #   grimoires/loa/runbooks/headless-capability-matrix.md  # feature × adapter
   740 |   #   grimoires/loa/runbooks/chain-walk-debugging.md     # LOA_HEADLESS_VERBOSE + envelope queries
   741 |   headless:
   742 |     mode: prefer-api                         # prefer-api | prefer-cli | api-only | cli-only
   743 |     # agy_opt_in: the agy (Antigravity) CLI route — the `gemini-headless` hop — is opt-in (cycle-127).
   744 |     # Off (the default), cheval refuses an agy dispatch before any spawn and every planner (dissent,
   745 |     # Flatline tertiary, Bridgebuilder, /loa, run preflight) records the hop as not planned
   746 |     # (reason opt_in_required), never as a failed voice — a host without agy plans no Google CLI voice.
   747 |     # Set true only where agy is installed AND OAuth-authed: `agy -p` takes the whole prompt (the
>  748 |     # redacted review diff) on argv, readable by every local account through /proc and ps. Only a
>  749 |     # YAML boolean true counts; there is no environment override.
   750 |     agy_opt_in: false
   751 |     # cli_paths: discovery hints. If unset, $PATH is searched.
   752 |     # cli_paths:
   753 |     #   claude: /usr/local/bin/claude
   754 |     #   codex: /usr/local/bin/codex
   755 |     #   gemini: /usr/local/bin/gemini
   756 | 
   757 |   # Provider registry — override endpoints, auth, or add new providers
   758 |   # Providers not listed here use system defaults from model-config.yaml
   759 |   providers:
   760 |     openai:
   761 |       # type: openai                    # Provider SDK type
~~~~

The change from head to the fix:

~~~~diff
@@ -748,2 +748,3 @@
-    # redacted review diff) on argv, readable by every local account through /proc and ps. Only a
-    # YAML boolean true counts; there is no environment override.
+    # redacted review diff) on argv, readable by every local account through /proc and ps. Only the
+    # lowercase scalar `true` counts (yes / on / True / "true" read off, with a WARN); there is no
+    # environment override.
~~~~

## H172 — docs/migration/v2.0-model-generation-floor.md — head lines 287–290

Head context (head/docs/migration/v2.0-model-generation-floor.md, lines 275–302):

~~~~text
   275 |   `hounfour.providers.*.models` overlay, or pass `--effort low|medium` on a call.
   276 | ### Cycle-127 addendum — operator decisions (unreleased)
   277 | 
   278 | - **The agy (Antigravity) route is opt-in, default off.** `gemini-headless` dispatches
   279 |   through `agy -p`, whose prompt — the redacted review diff — travels on argv, readable
   280 |   by every local account through `/proc` and `ps`; and on a host without `agy` the voice
   281 |   simply failed, degrading every multi-model verdict (Bridgebuilder #1274 ran DEGRADED
   282 |   2/3 for that reason). Now `hounfour.headless.agy_opt_in: true` (a YAML boolean; no
   283 |   environment override) is required: without it cheval refuses the dispatch before any
   284 |   spawn (`INVALID_CONFIG`, `failure_class: opt_in_required`, never a breaker trip), and
   285 |   the dissent, Flatline's tertiary, Bridgebuilder, `run-preflight.sh` and `/loa` record
   286 |   the hop as *not planned* (`reason: opt_in_required`) rather than failed — verdict
>  287 |   quality counts planned voices only. Set it `true` only where `agy` is installed and
>  288 |   OAuth-authed, knowing the argv exposure. With it on, behaviour is exactly as before.
>  289 | - **Opus 5.5 effort default.** See the cycle-126 bullet above: `claude-opus-5-5` carries
>  290 |   `params.default_effort: high`; `--effort` overrides.
   291 | - **Calibrating the ceiling through the headless CLI.** `tools/ceiling-probe-live.py
   292 |   --transport claude-headless` measures the accepted input size through
   293 |   `${CLAUDE_HEADLESS_BIN:-claude}` (the adapter's own argv plus `--effort low
   294 |   --max-turns 1`, prompt on stdin), verifies each accepted step with a random needle the
   295 |   reply must echo, measures the size from the CLI's `usage`, retries transient failures,
   296 |   and writes the catalog only on a *clean* outcome — `probed_ceiling` and
   297 |   `effective_input_ceiling` to the measured bound (a bound below the old one is written,
   298 |   never kept), `ceiling_calibration.source: operator_set` with `method: probed_headless`,
   299 |   `transport`, `cli_version`, `cli_model`, `measured_input_tokens`, `calibrated_at` and a
   300 |   `reprobe_trigger` naming the API-transport probe. The record is always written. Use it
   301 |   on hosts where the direct API is unreachable (this repo's primary host: KF-040) and the
   302 |   CLI route is what your hops actually use; `--transport api` is unchanged.
~~~~

The change from head to the fix:

~~~~diff
@@ -287,4 +287,23 @@
-  quality counts planned voices only. Set it `true` only where `agy` is installed and
+  quality counts planned voices only. One predicate decides what the agy route is
+  (`.claude/scripts/lib/agy-gate-lib.sh`; Python twin in the loader): the literal
+  `gemini-headless` hop, or a Google voice under effective `cli-only` (under `prefer-api`
+  with no Google key the HTTP hop fails on credentials first, as before) — and cheval's
+  own chain walk skips such a hop inside a fallback chain (`planned: false, reason:
+  opt_in_required`) and walks on; a chain that is agy alone, like a direct `--model
+  gemini-headless`, refuses with `INVALID_CONFIG`. The key is read from
+  `.loa.config.yaml` alone (a framework defaults file cannot opt you in) — cheval from its
+  own install root, never a cwd-ancestor file — and only the scalar written exactly
+  `true` opts in: a quoted `"true"`, `yes`/`on`/`True`, an alias or a merge key read off
+  in every reader with one WARN. A config you do not own, that others can write, or that
+  a group other than your own user-private group can write, is ignored by every reader
+  (off, one WARN naming the file and the reason) — a umask-002 checkout on a
+  user-private-group host still opts in; on a shared-group host `chmod 644
+  .loa.config.yaml` if your opt-in "does not take". Bridgebuilder blocks the
+  merge when it cannot read the config at all (never a smaller quorum). Set it `true` only where `agy` is installed and
   OAuth-authed, knowing the argv exposure. With it on, behaviour is exactly as before.
 - **Opus 5.5 effort default.** See the cycle-126 bullet above: `claude-opus-5-5` carries
-  `params.default_effort: high`; `--effort` overrides.
+  `params.default_effort: high`; `--effort` overrides. Effort is resolved once for the
+  requested entry and carried to every hop the walk reaches (`opus` → `claude-headless`
+  sends `--effort high`); a CLI entry's own default (`params.default_effort` on that
+  entry, or its legacy `extra.effort`) applies only when that entry is the one requested
+  — the catalog does not know which model your CLI runs.
~~~~

## H173 — docs/migration/v2.0-model-generation-floor.md — head lines 297–300

Head context (head/docs/migration/v2.0-model-generation-floor.md, lines 285–312):

~~~~text
   285 |   the dissent, Flatline's tertiary, Bridgebuilder, `run-preflight.sh` and `/loa` record
   286 |   the hop as *not planned* (`reason: opt_in_required`) rather than failed — verdict
   287 |   quality counts planned voices only. Set it `true` only where `agy` is installed and
   288 |   OAuth-authed, knowing the argv exposure. With it on, behaviour is exactly as before.
   289 | - **Opus 5.5 effort default.** See the cycle-126 bullet above: `claude-opus-5-5` carries
   290 |   `params.default_effort: high`; `--effort` overrides.
   291 | - **Calibrating the ceiling through the headless CLI.** `tools/ceiling-probe-live.py
   292 |   --transport claude-headless` measures the accepted input size through
   293 |   `${CLAUDE_HEADLESS_BIN:-claude}` (the adapter's own argv plus `--effort low
   294 |   --max-turns 1`, prompt on stdin), verifies each accepted step with a random needle the
   295 |   reply must echo, measures the size from the CLI's `usage`, retries transient failures,
   296 |   and writes the catalog only on a *clean* outcome — `probed_ceiling` and
>  297 |   `effective_input_ceiling` to the measured bound (a bound below the old one is written,
>  298 |   never kept), `ceiling_calibration.source: operator_set` with `method: probed_headless`,
>  299 |   `transport`, `cli_version`, `cli_model`, `measured_input_tokens`, `calibrated_at` and a
>  300 |   `reprobe_trigger` naming the API-transport probe. The record is always written. Use it
   301 |   on hosts where the direct API is unreachable (this repo's primary host: KF-040) and the
   302 |   CLI route is what your hops actually use; `--transport api` is unchanged.
   303 | - **`claude-opus-5-5` input bound: 180,000 → 936,000 on this route.** Measured 2026-10-07
   304 |   through `claude-bedrock` (`global.anthropic.claude-opus-5-5`, CLI 2.1.292): accepted and
   305 |   verified at 972,887 input tokens, rejected by the CLI's pre-flight at the 1,000,000 window;
   306 |   written as 936,000 = 1,000,000 − the 64,000 default output budget (cheval's I2 invariant),
   307 |   `ceiling_calibration.source: operator_set`, `method: probed_headless`,
   308 |   `measured_input_tokens: 972887`. cheval now preempts above 936,000 instead of 180,000 for
   309 |   `opus`, and Bridgebuilder's budget for it is 916,000 input tokens. Record:
   310 |   `grimoires/loa/reports/2026-10-07-opus-5-5-ceiling-probe-cli.json`. Downstream mounts
   311 |   inherit the value with the catalog; re-probe through your own route if it differs.
   312 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -297,4 +316,12 @@
-  `effective_input_ceiling` to the measured bound (a bound below the old one is written,
-  never kept), `ceiling_calibration.source: operator_set` with `method: probed_headless`,
-  `transport`, `cli_version`, `cli_model`, `measured_input_tokens`, `calibrated_at` and a
-  `reprobe_trigger` naming the API-transport probe. The record is always written. Use it
+  `effective_input_ceiling` to the measured bound clamped to cheval's I2 invariant
+  (`min(measured, context_window − the default output budget)`; the raw accept stays in
+  `measured_input_tokens`; a bound below the old one is written, never kept),
+  `ceiling_calibration.source: operator_set` with `method: probed_headless`, `transport`,
+  `cli_version`, `cli_model`, `measured_input_tokens`, `probe_outcome`, `sample_size`,
+  `calibrated_at` and a `reprobe_trigger` naming the API-transport probe. The record is
+  always written; a *partial* record reaches the catalog only under
+  `--write-partial-as-operator-set`; the writer refuses operator strings (`--host-route`,
+  `--cli-model`, the CLI version) with control characters before any spend and re-parses
+  the produced YAML before it replaces the catalog. The bisection steps in measured tokens (the filler
+  is rescaled by the observed tokenizer ratio); the CLI's own pre-flight rejections cost
+  nothing and are charged nothing (`charged_usd`, `charge_basis` per sample). Use it
~~~~

## H174 — docs/migration/v2.0-model-generation-floor.md — head lines 310–311

Head context (head/docs/migration/v2.0-model-generation-floor.md, lines 298–317):

~~~~text
   298 |   never kept), `ceiling_calibration.source: operator_set` with `method: probed_headless`,
   299 |   `transport`, `cli_version`, `cli_model`, `measured_input_tokens`, `calibrated_at` and a
   300 |   `reprobe_trigger` naming the API-transport probe. The record is always written. Use it
   301 |   on hosts where the direct API is unreachable (this repo's primary host: KF-040) and the
   302 |   CLI route is what your hops actually use; `--transport api` is unchanged.
   303 | - **`claude-opus-5-5` input bound: 180,000 → 936,000 on this route.** Measured 2026-10-07
   304 |   through `claude-bedrock` (`global.anthropic.claude-opus-5-5`, CLI 2.1.292): accepted and
   305 |   verified at 972,887 input tokens, rejected by the CLI's pre-flight at the 1,000,000 window;
   306 |   written as 936,000 = 1,000,000 − the 64,000 default output budget (cheval's I2 invariant),
   307 |   `ceiling_calibration.source: operator_set`, `method: probed_headless`,
   308 |   `measured_input_tokens: 972887`. cheval now preempts above 936,000 instead of 180,000 for
   309 |   `opus`, and Bridgebuilder's budget for it is 916,000 input tokens. Record:
>  310 |   `grimoires/loa/reports/2026-10-07-opus-5-5-ceiling-probe-cli.json`. Downstream mounts
>  311 |   inherit the value with the catalog; re-probe through your own route if it differs.
   312 | 
   313 | ## Non-goals / explicitly unchanged
   314 | 
   315 | - No change to the audit-envelope chain semantics, the zone model, or the
   316 |   hook wiring contract (the upstream hook hardening is fail-loud tightening, not a new surface).
   317 | - The per-sprint a2a record of the cycle is on the branch `record/cycle-124-a2a`, not on `main`.
~~~~

The change from head to the fix:

~~~~diff
@@ -310,2 +337,24 @@
-  `grimoires/loa/reports/2026-10-07-opus-5-5-ceiling-probe-cli.json`. Downstream mounts
-  inherit the value with the catalog; re-probe through your own route if it differs.
+  `grimoires/loa/reports/2026-10-07-opus-5-5-ceiling-probe-cli.json`. The tool's outcome
+  was *partial* (the budget cap stopped the bisection before the 16K tolerance); the entry
+  was written by the operator and says so (`probe_outcome: partial`, `sample_size: 5`).
+  The measurement was taken on the headless transport and governs the HTTP entry too (same
+  model and window; the 180,000 it replaces was a conservative cycle-126 shortcut, not a
+  measured HTTP rejection). Safeguard: on a route other than the one recorded in
+  `ceiling_calibration.transport`, a verified provider context-limit observation tightens
+  the bound (`.run/ceiling-observed.json`; `/loa` shows `calibrated 936000
+  (claude-headless); observed N below on this route`), so a narrower HTTP route self-heals.
+  The bound is in provider-measured tokens; every pre-dispatch estimate is a character
+  heuristic that under-counts the Opus 4.7+ tokenizer (cheval's chars/3.5 by ≈1.4×,
+  chars/4-class estimates by ≈1.8×). On the HTTP transport a calibrated entry asks the
+  provider's free `count_tokens` once the estimate passes half the bound and gates on the
+  exact count; Bridgebuilder, which builds the prompt before any count, budgets
+  (bound − 20,000 headroom) ÷ 1.8 = 508,000 estimated tokens for this entry. On the
+  `claude-headless` route there is no HTTP ceiling and no count: the CLI's pre-flight is
+  the backstop (no spend; the adapter maps it to the context-limit class — not walked, no
+  breaker count — unless a throttle marker is present, in which case it is a rate limit,
+  retried then walked). Near the window a request that slips past the HTTP gate fails cleanly
+  at the provider (`PROVIDER_CONTEXT_LIMIT`, one upload, not walked). The HTTP route's
+  `account_limits` tier is still `unverified`. Downstream mounts inherit the value with the catalog;
+  HTTP-route callers and mounts with a different window or tier should run
+  `tools/ceiling-probe-live.py --transport api` before relying on 936,000 (bead bd-c2rd
+  tracks the estimator itself).
~~~~

## H175 — tests/unit/adversarial-review-companion.bats — insertion after head line 51

Head context (head/tests/unit/adversarial-review-companion.bats, lines 40–63):

~~~~text
    40 | }
    41 | _place_marker() {  # <tmp> <marker> → 0 placed; 1 (named, SPRINT cleared) when a run on another host or pid namespace holds it
    42 |     # (thirty-eighth run, c2a DISS-C-001: a host and its devcontainer over one checkout can hold one namespace-local pid at once —
    43 |     # a rename over the marker gave both runs one sprint directory. A link never replaces: a marker that stands is replaced only
    44 |     # when it was written HERE, where this pid is this run or a dead one of ours; no link support falls back to the rename)
    45 |     ln -- "$1" "$2" 2>/dev/null && { rm -f -- "$1"; return 0; }
    46 |     if [[ -e "$2" || -L "$2" ]] && _sweep_foreign "$2"; then
    47 |         rm -f -- "$1"; echo "setup: $2 is held by a run of this suite on another host or pid namespace"; SPRINT=""; return 1
    48 |     fi
    49 |     mv -f -- "$1" "$2"
    50 | }
    51 | setup() {
    52 |     # the sprint id and its directory come FIRST: teardown runs on any setup failure, and a delete
    53 |     # target derived from an unset id would be the a2a root (fourth run, chunk c C-001)
    54 |     SPRINT="sprint-comp-$$"
    55 |     SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    56 |     PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    57 |     export PROJECT_ROOT
    58 |     OUT_DIR="$PROJECT_ROOT/grimoires/loa/a2a/$SPRINT"
    59 |     _claim_sprint_dir "$OUT_DIR" || return 1
    60 |     # this suite's own: the stale sweep deletes only marked dirs — written whole, by a rename (thirty-seventh run, c1a DISS-C-001)
    61 |     local _om="${OUT_DIR%/*}/.$SPRINT.owner.tmp" _mk="${OUT_DIR%/*}/.$SPRINT.owner"
    62 |     mkdir -p "${OUT_DIR%/*}" && _sweep_where > "$_om" || return 1
    63 |     _place_marker "$_om" "$_mk" || return 1
~~~~

The change from head to the fix:

~~~~diff
@@ -51,0 +52,3 @@
+    # (r251-5 U1/U2: every agy opt-in reader refuses a group- or world-writable config — fixtures are written owner-only
+    # whatever the host umask; a `>` redirect under umask 002 makes 0664)
+    umask 022
~~~~

## H176 — tests/unit/adversarial-review-companion.bats — head lines 5979–5981

Head context (head/tests/unit/adversarial-review-companion.bats, lines 5967–5993):

~~~~text
  5967 |     [ "$rc" = "0" ]
  5968 |     grep -q "Companion voice diagnostic (claude-headless): \[31mboom: ppp" "$T/cut-err" || { cat "$T/cut-err"; return 1; }
  5969 |     if grep -qF "$k" "$T/cut-err" || grep -qF "${body:0:8}" "$T/cut-err"; then echo "part of the key reached stderr"; cat "$T/cut-err"; return 1; fi
  5970 |     if grep -F 'Companion voice diagnostic' "$T/cut-err" | LC_ALL=C grep -q $'[\001-\010\013-\037\177]'; then echo "a control character reached stderr"; return 1; fi
  5971 |     [[ "$out" != *"$k"* && "$out" != *"${body:0:8}"* ]]
  5972 |     # the line is still cut: at most 300 characters after the prefix
  5973 |     [ "$(grep -F 'Companion voice diagnostic' "$T/cut-err" | sed 's/^.*Companion voice diagnostic (claude-headless): //' | wc -c)" -le 301 ]
  5974 | }
  5975 | 
  5976 | # cycle-127 FR-1: the agy (Antigravity) route — the `gemini-headless` hop — is opt-in (hounfour.headless.agy_opt_in, default
  5977 | # false). With it off, an operator companion_chain naming the hop does not plan it: read from the config, before any dispatch.
  5978 | _cmp_agy_chain() {  # <anthropic chain YAML list> [agy_opt_in YAML value | "absent"]
> 5979 |     python3 -I - "$CONFIG_FILE" "$1" "${2:-absent}" <<'PY'
> 5980 | import sys; p, chain, opt = sys.argv[1:4]; s = open(p, encoding="utf-8").read()
> 5981 | s = s.replace("  code_review:\n    enabled: true\n", "  code_review:\n    enabled: true\n    companion_chain:\n      anthropic: " + chain + "\n", 1)
  5982 | if opt != "absent":
  5983 |     s = "hounfour:\n  headless:\n    agy_opt_in: " + opt + "\n" + s
  5984 | open(p, "w", encoding="utf-8").write(s)
  5985 | PY
  5986 | }
  5987 | 
  5988 | @test "CMP-284 an operator companion_chain naming gemini-headless with the agy opt-in off → planned false, reason opt_in_required, never dispatched, a WARN naming both keys; verdict quality counts the planned voice only" {
  5989 |     local opt
  5990 |     for opt in absent false '"true"'; do
  5991 |         cp "$T/loa.config.yaml" "$T/loa.config.yaml.orig" 2>/dev/null || true
  5992 |         _cmp_agy_chain '[gemini-headless]' "$opt"
  5993 |         : > "$CALLS"
~~~~

The change from head to the fix:

~~~~diff
@@ -5979,3 +5982,7 @@
+    # (review r251-1 G13: exactly one anchor is replaced — a fixture that drifted fails here, never writes a no-op config)
     python3 -I - "$CONFIG_FILE" "$1" "${2:-absent}" <<'PY'
 import sys; p, chain, opt = sys.argv[1:4]; s = open(p, encoding="utf-8").read()
-s = s.replace("  code_review:\n    enabled: true\n", "  code_review:\n    enabled: true\n    companion_chain:\n      anthropic: " + chain + "\n", 1)
+anchor = "  code_review:\n    enabled: true\n"
+if s.count(anchor) != 1:
+    sys.exit(f"_cmp_agy_chain: expected exactly one code_review anchor in {p}, found {s.count(anchor)}")
+s = s.replace(anchor, anchor + "    companion_chain:\n      anthropic: " + chain + "\n", 1)
~~~~

## H177 — tests/unit/adversarial-review-companion.bats — head lines 5990–5991

Head context (head/tests/unit/adversarial-review-companion.bats, lines 5978–6003):

~~~~text
  5978 | _cmp_agy_chain() {  # <anthropic chain YAML list> [agy_opt_in YAML value | "absent"]
  5979 |     python3 -I - "$CONFIG_FILE" "$1" "${2:-absent}" <<'PY'
  5980 | import sys; p, chain, opt = sys.argv[1:4]; s = open(p, encoding="utf-8").read()
  5981 | s = s.replace("  code_review:\n    enabled: true\n", "  code_review:\n    enabled: true\n    companion_chain:\n      anthropic: " + chain + "\n", 1)
  5982 | if opt != "absent":
  5983 |     s = "hounfour:\n  headless:\n    agy_opt_in: " + opt + "\n" + s
  5984 | open(p, "w", encoding="utf-8").write(s)
  5985 | PY
  5986 | }
  5987 | 
  5988 | @test "CMP-284 an operator companion_chain naming gemini-headless with the agy opt-in off → planned false, reason opt_in_required, never dispatched, a WARN naming both keys; verdict quality counts the planned voice only" {
  5989 |     local opt
> 5990 |     for opt in absent false '"true"'; do
> 5991 |         cp "$T/loa.config.yaml" "$T/loa.config.yaml.orig" 2>/dev/null || true
  5992 |         _cmp_agy_chain '[gemini-headless]' "$opt"
  5993 |         : > "$CALLS"
  5994 |         result=$(_run_main review)
  5995 |         [ "$(jq -r '.metadata.companion_voice | [.planned, .reason, .family] | map(tostring) | join(",")' <<<"$result")" = "false,opt_in_required,anthropic" ] || { echo "opt=$opt"; jq -c '.metadata.companion_voice' <<<"$result"; return 1; }
  5996 |         [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "1" ]
  5997 |         [ "$(jq -r '.verdict_quality.status' <<<"$result")" != "DEGRADED" ]
  5998 |         [ "$(jq '[.verdict_quality.voices_dropped[]? | select(.voice | test("gemini"))] | length' <<<"$result")" = "0" ]
  5999 |         ! grep -q 'gemini-headless' "$CALLS" || { echo "unexpected: grep -q 'gemini-headless' '$CALLS'"; return 1; }
  6000 |         grep -q 'hounfour.headless.agy_opt_in' "$T/stderr.log"
  6001 |         grep 'hounfour.headless.agy_opt_in' "$T/stderr.log" | grep -q 'flatline_protocol.code_review.companion_chain.anthropic'
  6002 |         mv -f "$T/loa.config.yaml.orig" "$T/loa.config.yaml"
  6003 |     done
~~~~

The change from head to the fix:

~~~~diff
@@ -5990,2 +5997,3 @@
+    local orig="$BATS_TEST_TMPDIR/cmp284-config.orig"
+    cp -- "$CONFIG_FILE" "$orig"   # (review r251-1 G13: save/restore the file the helper edits — $CONFIG_FILE — and fail loudly)
     for opt in absent false '"true"'; do
-        cp "$T/loa.config.yaml" "$T/loa.config.yaml.orig" 2>/dev/null || true
~~~~

## H178 — tests/unit/adversarial-review-companion.bats — head line 6002

Head context (head/tests/unit/adversarial-review-companion.bats, lines 5990–6014):

~~~~text
  5990 |     for opt in absent false '"true"'; do
  5991 |         cp "$T/loa.config.yaml" "$T/loa.config.yaml.orig" 2>/dev/null || true
  5992 |         _cmp_agy_chain '[gemini-headless]' "$opt"
  5993 |         : > "$CALLS"
  5994 |         result=$(_run_main review)
  5995 |         [ "$(jq -r '.metadata.companion_voice | [.planned, .reason, .family] | map(tostring) | join(",")' <<<"$result")" = "false,opt_in_required,anthropic" ] || { echo "opt=$opt"; jq -c '.metadata.companion_voice' <<<"$result"; return 1; }
  5996 |         [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "1" ]
  5997 |         [ "$(jq -r '.verdict_quality.status' <<<"$result")" != "DEGRADED" ]
  5998 |         [ "$(jq '[.verdict_quality.voices_dropped[]? | select(.voice | test("gemini"))] | length' <<<"$result")" = "0" ]
  5999 |         ! grep -q 'gemini-headless' "$CALLS" || { echo "unexpected: grep -q 'gemini-headless' '$CALLS'"; return 1; }
  6000 |         grep -q 'hounfour.headless.agy_opt_in' "$T/stderr.log"
  6001 |         grep 'hounfour.headless.agy_opt_in' "$T/stderr.log" | grep -q 'flatline_protocol.code_review.companion_chain.anthropic'
> 6002 |         mv -f "$T/loa.config.yaml.orig" "$T/loa.config.yaml"
  6003 |     done
  6004 | }
  6005 | 
  6006 | @test "CMP-285 with the agy opt-in off, a companion_chain's gemini-headless hop is dropped and the rest of the chain is planned" {
  6007 |     _cmp_agy_chain '[gemini-headless, claude-headless]'
  6008 |     result=$(_run_main review)
  6009 |     [ "$(jq -r '.metadata.companion_voice.planned' <<<"$result")" = "true" ]
  6010 |     [ "$(jq -r '.metadata.companion_voice.chain | join(",")' <<<"$result")" = "claude-headless" ]
  6011 |     [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "succeeded" ]
  6012 |     [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "2" ]
  6013 |     ! grep -q 'gemini-headless' "$CALLS" || { echo "unexpected: grep -q 'gemini-headless' '$CALLS'"; return 1; }
  6014 |     grep -q 'gemini-headless.*hounfour.headless.agy_opt_in' "$T/stderr.log"
~~~~

The change from head to the fix:

~~~~diff
@@ -6002 +6010 @@
-        mv -f "$T/loa.config.yaml.orig" "$T/loa.config.yaml"
+        cp -- "$orig" "$CONFIG_FILE"
~~~~

## H179 — tests/unit/adversarial-review-companion.bats — insertion after head line 6027

Head context (head/tests/unit/adversarial-review-companion.bats, lines 6016–6027):

~~~~text
  6016 | 
  6017 | @test "CMP-286 with the agy opt-in true, a gemini-headless companion hop is planned and dispatched, and its failure is a dropped voice as before" {
  6018 |     _cmp_agy_chain '[gemini-headless]' true
  6019 |     BEHAVIOUR[gemini-headless]=unavailable
  6020 |     result=$(_run_main review)
  6021 |     [ "$(jq -r '.metadata.companion_voice.planned' <<<"$result")" = "true" ]
  6022 |     [ "$(jq -r '.metadata.companion_voice.chain | join(",")' <<<"$result")" = "gemini-headless" ]
  6023 |     [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "failed" ]
  6024 |     grep -qx 'gemini-headless' "$CALLS"
  6025 |     [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "2" ]
  6026 |     ! grep -q 'hounfour.headless.agy_opt_in' "$T/stderr.log" || { echo "unexpected: grep -q 'hounfour.headless.agy_opt_in' '$T/stderr.log'"; return 1; }
  6027 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -6027,0 +6036,17 @@
+
+@test "CMP-287 (review r251-2 K4) with the agy gate lib missing the dissent planner still drops a literal gemini-headless hop (fail closed, reason opt_in_required)" {
+    local empty="$T/no-lib-root" cfg="$T/agy-off.yaml"
+    mkdir -p "$empty"
+    printf 'hounfour:\n  headless:\n    mode: prefer-api\n    agy_opt_in: true\n' > "$cfg"   # (even an on config: no lib, no opt-in read)
+    run bash -c '
+        exec 2>"$4"; source "$1"
+        unset -f routes_to_agy agy_opted_in agy_headless_mode agy_route_planned agy_gate_warn_once 2>/dev/null
+        PROJECT_ROOT="$2"; CONFIG_FILE="$3"; log() { echo "$*" >&2; }
+        _adv_agy_filter_chain code_review anthropic gemini-headless claude-headless google:gemini-headless gemini-headless:gemini-3-pro gemini-2.5-pro
+    ' _ "$ADVERSARIAL_REVIEW" "$empty" "$cfg" "$T/k4.err"
+    local stderr; stderr=$(cat "$T/k4.err")
+    [ "$status" -eq 0 ] || { echo "status=$status stderr=$stderr"; return 1; }
+    [ "$output" = "claude-headless gemini-2.5-pro" ] || { echo "out=$output stderr=$stderr"; return 1; }
+    grep -q 'agy-gate-lib.sh not loaded' <<<"$stderr" || { echo "stderr=$stderr"; return 1; }
+    grep -q 'gemini-headless not planned.*opt_in_required' <<<"$stderr" || { echo "stderr=$stderr"; return 1; }
+}
~~~~

## H180 — tests/unit/cycle-124-effort-flag.bats — insertion after head line 27

Head context (head/tests/unit/cycle-124-effort-flag.bats, lines 16–39):

~~~~text
    16 | setup() {
    17 |     SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    18 |     PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    19 |     CHEVAL_PY="$PROJECT_ROOT/.claude/adapters/cheval.py"
    20 |     if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
    21 |         PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    22 |     else
    23 |         PYTHON_BIN="$(command -v python3)"
    24 |     fi
    25 |     export LOA_MODELINV_LOG_PATH="$BATS_TEST_TMPDIR/model-invoke.jsonl"
    26 |     export LOA_COST_LEDGER_PATH="$BATS_TEST_TMPDIR/cost-ledger.jsonl"
    27 |     unset LOA_CHEVAL_DISABLE_STREAMING LOA_CHEVAL_LEGACY_WIRE
    28 | }
    29 | 
    30 | # `run` merges stderr into $output by default; the JSON is on stdout and
    31 | # diagnostics (persona warnings, the clamp warning) on stderr, so keep them apart.
    32 | _dry_run() {  # <extra args...> — $output = stdout (the JSON), $stderr = diagnostics
    33 |     run --separate-stderr env -u ANTHROPIC_API_KEY "$PYTHON_BIN" "$CHEVAL_PY" \
    34 |         --agent reviewing-code --prompt "cycle-124-effort" --dry-run --json-errors "$@"
    35 | }
    36 | 
    37 | _field() {  # <json> <field>
    38 |     printf '%s' "$1" | "$PYTHON_BIN" -c "import json,sys; print(json.load(sys.stdin)$2)"
    39 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -27,0 +28,3 @@
+    # (cycle-127 r251-3 R6: hermetic to the operator's environment — a Bedrock bearer token turns on bedrock-forward
+    # routing, so `tiny` would resolve to the Bedrock haiku; a CLAUDE_HEADLESS_BIN would point the CLI hop elsewhere)
+    unset CLAUDE_HEADLESS_BIN AWS_BEARER_TOKEN_BEDROCK
~~~~

## H181 — tests/unit/flatline-tertiary-agy-opt-in.bats — insertion after head line 11

Head context (head/tests/unit/flatline-tertiary-agy-opt-in.bats, lines 1–23):

~~~~text
     1 | #!/usr/bin/env bats
     2 | # =============================================================================
     3 | # flatline-tertiary-agy-opt-in.bats — cycle-127 FR-1. The agy (Antigravity) route is opt-in
     4 | # (hounfour.headless.agy_opt_in, default false). A Flatline tertiary routed to agy with the opt-in off
     5 | # is not planned: skipped as "disabled by opt-in" (2-model mode, tertiary status disabled_by_opt_in),
     6 | # never dispatched and never a DEGRADED voice. No model is called.
     7 | # =============================================================================
     8 | 
     9 | bats_require_minimum_version 1.5.0
    10 | 
    11 | setup() {
    12 |     REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    13 |     source "$REPO/.claude/scripts/flatline-orchestrator.sh"
    14 |     CONFIG_FILE="$BATS_TEST_TMPDIR/loa.config.yaml"
    15 |     unset LOA_HEADLESS_MODE
    16 | }
    17 | 
    18 | _cfg() {  # <tertiary> [agy_opt_in value|absent] [headless mode]
    19 |     {
    20 |         printf 'hounfour:\n  headless:\n'
    21 |         printf '    mode: %s\n' "${3:-prefer-api}"
    22 |         [[ "${2:-absent}" == absent ]] || printf '    agy_opt_in: %s\n' "$2"
    23 |         printf 'flatline_protocol:\n  models:\n    primary: opus\n    secondary: gpt-5.5\n    tertiary: %s\n' "$1"
~~~~

The change from head to the fix:

~~~~diff
@@ -11,0 +12,3 @@
+    # (r251-5 U1/U2: every agy opt-in reader refuses a group- or world-writable config — fixtures are written owner-only
+    # whatever the host umask; a `>` redirect under umask 002 makes 0664)
+    umask 022
~~~~

## H182 — tests/unit/flatline-tertiary-agy-opt-in.bats — insertion after head line 45

Head context (head/tests/unit/flatline-tertiary-agy-opt-in.bats, lines 34–57):

~~~~text
    34 |             run tertiary_opt_in_skip_reason
    35 |             [ "$status" -eq 0 ]
    36 |             [[ "$output" == *"$t"*"disabled by opt-in"*"hounfour.headless.agy_opt_in"* ]] || { echo "$output"; return 1; }
    37 |         done
    38 |     done
    39 | }
    40 | 
    41 | @test "FTA-2 under hounfour.headless.mode cli-only a Google tertiary is agy-routed and gated too; under prefer-api it is planned" {
    42 |     _cfg gemini-3.1-pro absent cli-only
    43 |     [ "$(get_model_tertiary)" = "" ]
    44 |     [ "$(get_tertiary_status)" = "disabled_by_opt_in" ]
    45 |     _cfg gemini-3.1-pro absent prefer-api
    46 |     [ "$(get_model_tertiary)" = "gemini-3.1-pro" ]
    47 |     [ "$(get_tertiary_status)" = "active" ]
    48 |     run tertiary_opt_in_skip_reason
    49 |     [ "$status" -eq 1 ]
    50 | }
    51 | 
    52 | @test "FTA-3 with the opt-in true an agy tertiary is planned as before" {
    53 |     _cfg gemini-headless true
    54 |     [ "$(get_model_tertiary)" = "gemini-headless" ]
    55 |     [ "$(get_tertiary_status)" = "active" ]
    56 |     run tertiary_opt_in_skip_reason
    57 |     [ "$status" -eq 1 ]
~~~~

The change from head to the fix:

~~~~diff
@@ -45,0 +49,2 @@
+    _CACHED_TERTIARY_MODEL_SET=false
+    export GOOGLE_API_KEY="fixture-not-a-key"   # (hygiene: a prefer-api Google tertiary is an HTTP voice — it has a key)
~~~~

## H183 — tests/unit/flatline-tertiary-agy-opt-in.bats — insertion after head line 77

Head context (head/tests/unit/flatline-tertiary-agy-opt-in.bats, lines 66–82):

~~~~text
    66 |     [ "$(get_tertiary_status)" = "disabled" ]
    67 | }
    68 | 
    69 | @test "FTA-5 Phase 1 with a gated agy tertiary runs 2-model: no tertiary dispatch, the skip is logged, not a dropped voice" {
    70 |     _cfg gemini-headless
    71 |     TEMP_DIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TEMP_DIR"
    72 |     CALLS="$BATS_TEST_TMPDIR/calls"; : > "$CALLS"
    73 |     set_state() { :; }; log_trajectory() { :; }
    74 |     call_model() { echo "$1 $2" >> "$CALLS"; printf '{"content":"{\\"improvements\\":[]}","cost_usd":0}\n'; }
    75 |     log() { echo "$*" >&2; }
    76 |     printf '# doc\n' > "$BATS_TEST_TMPDIR/doc.md"
    77 |     run --separate-stderr run_phase1 "$BATS_TEST_TMPDIR/doc.md" prd "" 30 100
    78 |     ! grep -q gemini-headless "$CALLS" || { echo "unexpected: grep -q gemini-headless '$CALLS'"; return 1; }
    79 |     [ "$(grep -c '' "$CALLS")" = "4" ]
    80 |     [[ "$stderr" == *"disabled by opt-in"*"hounfour.headless.agy_opt_in"* ]] || { echo "$stderr"; return 1; }
    81 |     [[ "$stderr" != *"Voice dropped"* ]]
    82 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -77,0 +83,6 @@
+    # (review r251-1 G13: Phase 1 succeeded and wrote its four artefacts; no tertiary artefact)
+    [ "$status" -eq 0 ] || { echo "run_phase1 rc=$status"; echo "$stderr" | tail -20; return 1; }
+    local f
+    for f in gpt-review opus-review gpt-skeptic opus-skeptic; do [ -s "$TEMP_DIR/$f.json" ] || { echo "missing $f.json"; ls "$TEMP_DIR"; return 1; }; done
+    [ ! -e "$TEMP_DIR/tertiary-review.json" ] || { echo "tertiary-review.json written"; return 1; }
+    [ ! -e "$TEMP_DIR/tertiary-skeptic.json" ] || { echo "tertiary-skeptic.json written"; return 1; }
~~~~

## H184 — tests/unit/loa-status-providers.bats — insertion after head line 1

Head context (head/tests/unit/loa-status-providers.bats, lines 1–13):

~~~~text
     1 | #!/usr/bin/env bats
     2 | # =============================================================================
     3 | # tests/unit/loa-status-providers.bats — cycle-125 Sprint 4 (PRD FR-4 AC 2)
     4 | # `/loa` Providers block: per provider the credential PRESENCE (never the
     5 | # value), the CLI hop on PATH, and every breaker bucket with state / age /
     6 | # probe timing; `--json` mirrors it. Fixture run dir via the bats-gated
     7 | # LOA_STATUS_RUN_DIR seam.
     8 | # =============================================================================
     9 | 
    10 | setup() {
    11 |   PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    12 |   STATUS="$PROJECT_ROOT/.claude/scripts/loa-status.sh"
    13 |   T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/lsp.XXXXXX")"
~~~~

The change from head to the fix:

~~~~diff
@@ -1,0 +2 @@
+bats_require_minimum_version 1.5.0
~~~~

## H185 — tests/unit/loa-status-providers.bats — insertion after head line 10

Head context (head/tests/unit/loa-status-providers.bats, lines 1–22):

~~~~text
     1 | #!/usr/bin/env bats
     2 | # =============================================================================
     3 | # tests/unit/loa-status-providers.bats — cycle-125 Sprint 4 (PRD FR-4 AC 2)
     4 | # `/loa` Providers block: per provider the credential PRESENCE (never the
     5 | # value), the CLI hop on PATH, and every breaker bucket with state / age /
     6 | # probe timing; `--json` mirrors it. Fixture run dir via the bats-gated
     7 | # LOA_STATUS_RUN_DIR seam.
     8 | # =============================================================================
     9 | 
    10 | setup() {
    11 |   PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    12 |   STATUS="$PROJECT_ROOT/.claude/scripts/loa-status.sh"
    13 |   T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/lsp.XXXXXX")"
    14 |   mkdir -p "$T/run"
    15 |   export LOA_STATUS_RUN_DIR="$T/run"
    16 |   now=$(date +%s)
    17 |   printf '{"provider":"google","auth_type":"http_api","state":"OPEN","failure_count":5,"opened_at":%d,"half_open_probes":0}\n' $(( now - 7200 )) > "$T/run/circuit-breaker-google-http_api.json"
    18 |   printf '{"provider":"openai","auth_type":"http_api","state":"CLOSED","failure_count":0,"opened_at":null,"half_open_probes":0}\n' > "$T/run/circuit-breaker-openai-http_api.json"
    19 |   printf '{"state":"CLOSED"}\n' > "$T/run/circuit-breaker.json"   # run-mode ICE breaker: not a provider bucket
    20 |   export OPENAI_API_KEY="sk-test-value-must-never-print"
    21 |   unset GOOGLE_API_KEY GEMINI_API_KEY ANTHROPIC_API_KEY
    22 |   mkdir -p "$T/env"; export LOA_STATUS_ENV_DIR="$T/env"   # bats-gated dotenv dir (no .env files → absent unless env)
~~~~

The change from head to the fix:

~~~~diff
@@ -10,0 +12,3 @@
+  # (r251-5 U1/U2: every agy opt-in reader refuses a group- or world-writable config — fixtures are written owner-only
+  # whatever the host umask; a `>` redirect under umask 002 makes 0664)
+  umask 022
~~~~

## H186 — tests/unit/loa-status-providers.bats — head lines 66–69

Head context (head/tests/unit/loa-status-providers.bats, lines 54–81):

~~~~text
    54 |   echo "$output" | jq -e '.providers.providers.openai.credential == "present (env)" and .providers.providers.openai.breakers.http_api.state == "CLOSED"' >/dev/null
    55 |   echo "$output" | jq -e '.providers.providers | has("anthropic")' >/dev/null
    56 |   [[ "$output" != *"sk-test-value-must-never-print"* ]]
    57 | }
    58 | 
    59 | @test "LSP-3 a provider with no breaker state is still listed (credential and hop only)" {
    60 |   rm "$T/run"/circuit-breaker-*.json
    61 |   run timeout 120 bash "$STATUS" --no-stale-check
    62 |   [ "$status" -eq 0 ]
    63 |   echo "$output" | grep -qE '^  anthropic +key (present|absent) +hop [a-z-]+ +no breaker state'
    64 | }
    65 | 
>   66 | @test "LSP-5 the anthropic row carries the input bound the opus target runs under: probed by default, observed after a provider verdict, never a 429 (cycle-126 FR-1.1)" {
>   67 |   # cycle-127 FR-3.4: the values follow the catalog (the probe may calibrate the opus target);
>   68 |   # the policy is pinned per state — uncalibrated: probed, lowered only by a context-class
>   69 |   # observation below it; calibrated: the measured bound, observations never lower it.
    70 |   local cfg="$PROJECT_ROOT/.claude/defaults/model-config.yaml" m probed eff cal
    71 |   m="$(yq -r '.aliases.opus' "$cfg")"; m="${m#anthropic:}"
    72 |   probed="$(yq -r ".providers.anthropic.models.\"$m\".probed_ceiling" "$cfg")"
    73 |   eff="$(yq -r ".providers.anthropic.models.\"$m\".effective_input_ceiling" "$cfg")"
    74 |   cal="$(yq -r ".providers.anthropic.models.\"$m\".ceiling_calibration.calibrated_at // \"\"" "$cfg")"
    75 |   [[ "$probed" =~ ^[0-9]+$ && "$eff" =~ ^[0-9]+$ ]]
    76 |   local above=$(( probed + 232000 )) below=$(( probed - 30000 ))
    77 |   unset LOA_CHEVAL_CEILING_OBSERVED_PATH
    78 |   export LOA_CHEVAL_CEILING_OBSERVED_PATH="$T/none.json"   # no store → the catalog's bound
    79 |   run timeout 120 bash "$STATUS" --no-stale-check
    80 |   [ "$status" -eq 0 ]
    81 |   if [[ -n "$cal" ]]; then
~~~~

The change from head to the fix:

~~~~diff
@@ -66,4 +70,40 @@
-@test "LSP-5 the anthropic row carries the input bound the opus target runs under: probed by default, observed after a provider verdict, never a 429 (cycle-126 FR-1.1)" {
-  # cycle-127 FR-3.4: the values follow the catalog (the probe may calibrate the opus target);
-  # the policy is pinned per state — uncalibrated: probed, lowered only by a context-class
-  # observation below it; calibrated: the measured bound, observations never lower it.
+_lsp5_catalog() {  # $1 file, $2 calibrated_at ("" = uncalibrated), $3 transport ("" = absent); bound 200000 / 920000 (fixture values, not the live catalog — r251-3 R2)
+  local cal_block=""
+  if [[ -n "$2" ]]; then
+    cal_block="          source: operator_set
+          calibrated_at: \"$2\"
+          stale_after_days: 90"
+    [[ -n "$3" ]] && cal_block+="
+          transport: $3"
+  else
+    cal_block="          source: conservative_default
+          calibrated_at: null
+          stale_after_days: 90"
+  fi
+  local bound=200000; [[ -n "$2" ]] && bound=920000
+  cat > "$1" <<YAML
+aliases:
+  opus: "anthropic:claude-fixture-1"
+providers:
+  anthropic:
+    models:
+      claude-fixture-1:
+        context_window: 1000000
+        effective_input_ceiling: $bound
+        probed_ceiling: $bound
+        ceiling_calibration:
+$cal_block
+YAML
+}
+_lsp5_obs() {  # $1 model, then (tokens class) pairs → the observed store at $T/obs.json
+  local m="$1" rows="" sep=""; shift
+  while (( $# >= 2 )); do
+    rows+="$sep{\"provider\":\"anthropic\",\"model\":\"$m\",\"observed_input_tokens\":$1,\"error_class\":\"$2\"}"; sep=","; shift 2
+  done
+  printf '{"version":1,"entries":[%s]}\n' "$rows" > "$T/obs.json"
+  export LOA_CHEVAL_CEILING_OBSERVED_PATH="$T/obs.json"
+}
+
+@test "LSP-5a the anthropic row carries the committed catalog's input bound for the opus target (cycle-126 FR-1.1, cycle-127 FR-3.4)" {
+  # The committed entry, whatever its state (the probe may calibrate it; a rollback may not):
+  # one assertion per state. Both states also run on every pass against fixtures (LSP-5b/5c/5d).
~~~~

## H187 — tests/unit/loa-status-providers.bats — head lines 76–77

Head context (head/tests/unit/loa-status-providers.bats, lines 64–89):

~~~~text
    64 | }
    65 | 
    66 | @test "LSP-5 the anthropic row carries the input bound the opus target runs under: probed by default, observed after a provider verdict, never a 429 (cycle-126 FR-1.1)" {
    67 |   # cycle-127 FR-3.4: the values follow the catalog (the probe may calibrate the opus target);
    68 |   # the policy is pinned per state — uncalibrated: probed, lowered only by a context-class
    69 |   # observation below it; calibrated: the measured bound, observations never lower it.
    70 |   local cfg="$PROJECT_ROOT/.claude/defaults/model-config.yaml" m probed eff cal
    71 |   m="$(yq -r '.aliases.opus' "$cfg")"; m="${m#anthropic:}"
    72 |   probed="$(yq -r ".providers.anthropic.models.\"$m\".probed_ceiling" "$cfg")"
    73 |   eff="$(yq -r ".providers.anthropic.models.\"$m\".effective_input_ceiling" "$cfg")"
    74 |   cal="$(yq -r ".providers.anthropic.models.\"$m\".ceiling_calibration.calibrated_at // \"\"" "$cfg")"
    75 |   [[ "$probed" =~ ^[0-9]+$ && "$eff" =~ ^[0-9]+$ ]]
>   76 |   local above=$(( probed + 232000 )) below=$(( probed - 30000 ))
>   77 |   unset LOA_CHEVAL_CEILING_OBSERVED_PATH
    78 |   export LOA_CHEVAL_CEILING_OBSERVED_PATH="$T/none.json"   # no store → the catalog's bound
    79 |   run timeout 120 bash "$STATUS" --no-stale-check
    80 |   [ "$status" -eq 0 ]
    81 |   if [[ -n "$cal" ]]; then
    82 |     echo "$output" | grep -qF "  ceiling: calibrated $eff ($m, calibrated $cal)"
    83 |   else
    84 |     echo "$output" | grep -qE "^  ceiling: probed $probed \($m; calibrate: python3 tools/ceiling-probe-live.py --model $m --write-catalog\)"
    85 |   fi
    86 |   printf '{"version":1,"entries":[{"provider":"anthropic","model":"%s","observed_input_tokens":%d,"error_class":"RATE_LIMIT_UNVERIFIED"},{"provider":"anthropic","model":"%s","observed_input_tokens":%d,"error_class":"CEILING_UNVERIFIED_LIMIT"}]}\n' "$m" $(( above + 88000 )) "$m" "$above" > "$T/obs.json"
    87 |   export LOA_CHEVAL_CEILING_OBSERVED_PATH="$T/obs.json"
    88 |   run timeout 120 bash "$STATUS" --no-stale-check
    89 |   [ "$status" -eq 0 ]
~~~~

The change from head to the fix:

~~~~diff
@@ -76,2 +115,0 @@
-  local above=$(( probed + 232000 )) below=$(( probed - 30000 ))
-  unset LOA_CHEVAL_CEILING_OBSERVED_PATH
~~~~

## H188 — tests/unit/loa-status-providers.bats — head lines 84–111

Head context (head/tests/unit/loa-status-providers.bats, lines 72–123):

~~~~text
    72 |   probed="$(yq -r ".providers.anthropic.models.\"$m\".probed_ceiling" "$cfg")"
    73 |   eff="$(yq -r ".providers.anthropic.models.\"$m\".effective_input_ceiling" "$cfg")"
    74 |   cal="$(yq -r ".providers.anthropic.models.\"$m\".ceiling_calibration.calibrated_at // \"\"" "$cfg")"
    75 |   [[ "$probed" =~ ^[0-9]+$ && "$eff" =~ ^[0-9]+$ ]]
    76 |   local above=$(( probed + 232000 )) below=$(( probed - 30000 ))
    77 |   unset LOA_CHEVAL_CEILING_OBSERVED_PATH
    78 |   export LOA_CHEVAL_CEILING_OBSERVED_PATH="$T/none.json"   # no store → the catalog's bound
    79 |   run timeout 120 bash "$STATUS" --no-stale-check
    80 |   [ "$status" -eq 0 ]
    81 |   if [[ -n "$cal" ]]; then
    82 |     echo "$output" | grep -qF "  ceiling: calibrated $eff ($m, calibrated $cal)"
    83 |   else
>   84 |     echo "$output" | grep -qE "^  ceiling: probed $probed \($m; calibrate: python3 tools/ceiling-probe-live.py --model $m --write-catalog\)"
>   85 |   fi
>   86 |   printf '{"version":1,"entries":[{"provider":"anthropic","model":"%s","observed_input_tokens":%d,"error_class":"RATE_LIMIT_UNVERIFIED"},{"provider":"anthropic","model":"%s","observed_input_tokens":%d,"error_class":"CEILING_UNVERIFIED_LIMIT"}]}\n' "$m" $(( above + 88000 )) "$m" "$above" > "$T/obs.json"
>   87 |   export LOA_CHEVAL_CEILING_OBSERVED_PATH="$T/obs.json"
>   88 |   run timeout 120 bash "$STATUS" --no-stale-check
>   89 |   [ "$status" -eq 0 ]
>   90 |   if [[ -n "$cal" ]]; then
>   91 |     echo "$output" | grep -qF "  ceiling: calibrated $eff ($m, calibrated $cal)"
>   92 |   else
>   93 |     # an observation above the probed bound: the default bound stands, the observation is shown for the opt-in
>   94 |     echo "$output" | grep -qE "^  ceiling: probed $probed \($m; observed $(( above - 1 )) under the opt-in; calibrate: python3 tools/ceiling-probe-live.py"
>   95 |   fi
>   96 |   run timeout 120 bash "$STATUS" --no-stale-check --json
>   97 |   [ "$status" -eq 0 ]
>   98 |   if [[ -n "$cal" ]]; then
>   99 |     echo "$output" | jq -e --argjson e "$eff" '.providers.providers.anthropic.ceiling.basis == "calibrated" and .providers.providers.anthropic.ceiling.value == $e and .providers.providers.openai.ceiling == null' >/dev/null
>  100 |   else
>  101 |     echo "$output" | jq -e --argjson o "$(( above - 1 ))" '.providers.providers.anthropic.ceiling.basis == "probed" and .providers.providers.anthropic.ceiling.observed == $o and .providers.providers.openai.ceiling == null' >/dev/null
>  102 |   fi
>  103 |   # an observation BELOW the probed bound becomes the bound (uncalibrated) / never lowers a calibrated one
>  104 |   printf '{"version":1,"entries":[{"provider":"anthropic","model":"%s","observed_input_tokens":%d,"error_class":"PROVIDER_CONTEXT_LIMIT"}]}\n' "$m" "$below" > "$T/obs.json"
>  105 |   run timeout 120 bash "$STATUS" --no-stale-check
>  106 |   [ "$status" -eq 0 ]
>  107 |   if [[ -n "$cal" ]]; then
>  108 |     echo "$output" | grep -qF "  ceiling: calibrated $eff ($m, calibrated $cal)"
>  109 |   else
>  110 |     echo "$output" | grep -qE "^  ceiling: observed $(( below - 1 )) \($m; calibrate: python3 tools/ceiling-probe-live.py"
>  111 |   fi
   112 | }
   113 | 
   114 | @test "LSP-AGY the google hop reads agy: opt-in (disabled; hounfour.headless.agy_opt_in) while the opt-in is off, today's hop text when it is true (cycle-127 FR-1)" {
   115 |   mkdir -p "$T/bin"; printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/agy"; chmod +x "$T/bin/agy"
   116 |   export PATH="$T/bin:$PATH"
   117 |   printf 'hounfour:\n  headless:\n    mode: cli-only\n' > "$T/loa.config.yaml"
   118 |   export LOA_STATUS_CONFIG_FILE="$T/loa.config.yaml"
   119 |   run timeout 120 bash "$STATUS" --no-stale-check
   120 |   [ "$status" -eq 0 ] || { echo "rc=$status"; echo "$output" | tail -20; return 1; }
   121 |   echo "$output" | grep -qE '^  google +key absent +hop agy: opt-in \(disabled; hounfour\.headless\.agy_opt_in\)'
   122 |   run timeout 120 bash "$STATUS" --no-stale-check --json
   123 |   echo "$output" | jq -e '.providers.providers.google.cli_hop == null and .providers.providers.google.cli_hop_note == "agy: opt-in (disabled; hounfour.headless.agy_opt_in)"' >/dev/null
~~~~

The change from head to the fix:

~~~~diff
@@ -84,28 +122,62 @@
-    echo "$output" | grep -qE "^  ceiling: probed $probed \($m; calibrate: python3 tools/ceiling-probe-live.py --model $m --write-catalog\)"
+    echo "$output" | grep -qF "  ceiling: probed $probed ($m; calibrate: python3 tools/ceiling-probe-live.py --model $m --write-catalog)"
   fi
-  printf '{"version":1,"entries":[{"provider":"anthropic","model":"%s","observed_input_tokens":%d,"error_class":"RATE_LIMIT_UNVERIFIED"},{"provider":"anthropic","model":"%s","observed_input_tokens":%d,"error_class":"CEILING_UNVERIFIED_LIMIT"}]}\n' "$m" $(( above + 88000 )) "$m" "$above" > "$T/obs.json"
-  export LOA_CHEVAL_CEILING_OBSERVED_PATH="$T/obs.json"
+}
+
+@test "LSP-5b an uncalibrated entry (fixture catalog): probed by default, observed after a provider verdict below it, never a 429" {
+  _lsp5_catalog "$T/catalog.yaml" "" ""
+  export LOA_STATUS_MODEL_CONFIG="$T/catalog.yaml"
+  local m=claude-fixture-1
+  export LOA_CHEVAL_CEILING_OBSERVED_PATH="$T/none.json"
   run timeout 120 bash "$STATUS" --no-stale-check
   [ "$status" -eq 0 ]
-  if [[ -n "$cal" ]]; then
-    echo "$output" | grep -qF "  ceiling: calibrated $eff ($m, calibrated $cal)"
-  else
-    # an observation above the probed bound: the default bound stands, the observation is shown for the opt-in
-    echo "$output" | grep -qE "^  ceiling: probed $probed \($m; observed $(( above - 1 )) under the opt-in; calibrate: python3 tools/ceiling-probe-live.py"
-  fi
+  echo "$output" | grep -qF "  ceiling: probed 200000 ($m; calibrate: python3 tools/ceiling-probe-live.py --model $m --write-catalog)"
+  # an observation above the probed bound: the default bound stands, the observation is shown for the opt-in; a 429 row never counts
+  _lsp5_obs "$m" 500000 RATE_LIMIT_UNVERIFIED 412000 CEILING_UNVERIFIED_LIMIT
+  run timeout 120 bash "$STATUS" --no-stale-check
+  [ "$status" -eq 0 ]
+  echo "$output" | grep -qF "  ceiling: probed 200000 ($m; observed 411999 under the opt-in; calibrate: python3 tools/ceiling-probe-live.py --model $m --write-catalog)"
   run timeout 120 bash "$STATUS" --no-stale-check --json
   [ "$status" -eq 0 ]
-  if [[ -n "$cal" ]]; then
-    echo "$output" | jq -e --argjson e "$eff" '.providers.providers.anthropic.ceiling.basis == "calibrated" and .providers.providers.anthropic.ceiling.value == $e and .providers.providers.openai.ceiling == null' >/dev/null
-  else
-    echo "$output" | jq -e --argjson o "$(( above - 1 ))" '.providers.providers.anthropic.ceiling.basis == "probed" and .providers.providers.anthropic.ceiling.observed == $o and .providers.providers.openai.ceiling == null' >/dev/null
-  fi
-  # an observation BELOW the probed bound becomes the bound (uncalibrated) / never lowers a calibrated one
-  printf '{"version":1,"entries":[{"provider":"anthropic","model":"%s","observed_input_tokens":%d,"error_class":"PROVIDER_CONTEXT_LIMIT"}]}\n' "$m" "$below" > "$T/obs.json"
+  echo "$output" | jq -e '.providers.providers.anthropic.ceiling | .basis == "probed" and .value == 200000 and .observed == 411999' >/dev/null
+  echo "$output" | jq -e '.providers.providers.openai.ceiling == null' >/dev/null
+  # an observation BELOW the probed bound becomes the bound
+  _lsp5_obs "$m" 150000 PROVIDER_CONTEXT_LIMIT
   run timeout 120 bash "$STATUS" --no-stale-check
   [ "$status" -eq 0 ]
-  if [[ -n "$cal" ]]; then
-    echo "$output" | grep -qF "  ceiling: calibrated $eff ($m, calibrated $cal)"
-  else
-    echo "$output" | grep -qE "^  ceiling: observed $(( below - 1 )) \($m; calibrate: python3 tools/ceiling-probe-live.py"
-  fi
+  echo "$output" | grep -qF "  ceiling: observed 149999 ($m; calibrate: python3 tools/ceiling-probe-live.py --model $m --write-catalog)"
+}
+
+@test "LSP-5c a same-route calibration (transport api or absent, fixture catalog) is never lowered by an observation" {
+  local m=claude-fixture-1 t
+  for t in api ""; do
+    _lsp5_catalog "$T/catalog.yaml" "2026-10-07T09:29:07Z" "$t"
+    export LOA_STATUS_MODEL_CONFIG="$T/catalog.yaml"
+    _lsp5_obs "$m" 500001 PROVIDER_CONTEXT_LIMIT
+    run timeout 120 bash "$STATUS" --no-stale-check
+    [ "$status" -eq 0 ]
+    echo "$output" | grep -qF "  ceiling: calibrated 920000 ($m, calibrated 2026-10-07T09:29:07Z)"
+    [[ "$output" != *"below on this route"* ]]
+    run timeout 120 bash "$STATUS" --no-stale-check --json
+    echo "$output" | jq -e '.providers.providers.anthropic.ceiling | .basis == "calibrated" and .value == 920000' >/dev/null
+  done
+}
+
+@test "LSP-5d a foreign-transport calibration (claude-headless, fixture catalog) is tightened by an observation below it on this route and says so (cycle-127 r251-1)" {
+  local m=claude-fixture-1
+  _lsp5_catalog "$T/catalog.yaml" "2026-10-07T09:29:07Z" claude-headless
+  export LOA_STATUS_MODEL_CONFIG="$T/catalog.yaml"
+  # an observation above the calibrated bound: the calibration stands
+  _lsp5_obs "$m" 990000 PROVIDER_CONTEXT_LIMIT
+  run timeout 120 bash "$STATUS" --no-stale-check
+  [ "$status" -eq 0 ]
+  echo "$output" | grep -qF "  ceiling: calibrated 920000 ($m, calibrated 2026-10-07T09:29:07Z)"
+  # below it (a 429 row never counts): the observed bound governs and the line names both
+  _lsp5_obs "$m" 300000 RATE_LIMIT_UNVERIFIED 500001 PROVIDER_CONTEXT_LIMIT
+  run timeout 120 bash "$STATUS" --no-stale-check
+  [ "$status" -eq 0 ]
+  echo "$output" | grep -qF "  ceiling: calibrated 920000 (claude-headless); observed 500000 below on this route, reprobe suggested ($m, calibrated 2026-10-07T09:29:07Z; calibrate: python3 tools/ceiling-probe-live.py --model $m --write-catalog)"
+  run timeout 120 bash "$STATUS" --no-stale-check --json
+  [ "$status" -eq 0 ]
+  echo "$output" | jq -e '.providers.providers.anthropic.ceiling | .basis == "observed" and .value == 500000 and .calibrated == true
+    and .calibrated_value == 920000 and .calibration_transport == "claude-headless" and .reprobe_suggested == true
+    and .calibrated_at == "2026-10-07T09:29:07Z"' >/dev/null
~~~~

## H189 — tests/unit/loa-status-providers.bats — head lines 122–124

Head context (head/tests/unit/loa-status-providers.bats, lines 110–131):

~~~~text
   110 |     echo "$output" | grep -qE "^  ceiling: observed $(( below - 1 )) \($m; calibrate: python3 tools/ceiling-probe-live.py"
   111 |   fi
   112 | }
   113 | 
   114 | @test "LSP-AGY the google hop reads agy: opt-in (disabled; hounfour.headless.agy_opt_in) while the opt-in is off, today's hop text when it is true (cycle-127 FR-1)" {
   115 |   mkdir -p "$T/bin"; printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/agy"; chmod +x "$T/bin/agy"
   116 |   export PATH="$T/bin:$PATH"
   117 |   printf 'hounfour:\n  headless:\n    mode: cli-only\n' > "$T/loa.config.yaml"
   118 |   export LOA_STATUS_CONFIG_FILE="$T/loa.config.yaml"
   119 |   run timeout 120 bash "$STATUS" --no-stale-check
   120 |   [ "$status" -eq 0 ] || { echo "rc=$status"; echo "$output" | tail -20; return 1; }
   121 |   echo "$output" | grep -qE '^  google +key absent +hop agy: opt-in \(disabled; hounfour\.headless\.agy_opt_in\)'
>  122 |   run timeout 120 bash "$STATUS" --no-stale-check --json
>  123 |   echo "$output" | jq -e '.providers.providers.google.cli_hop == null and .providers.providers.google.cli_hop_note == "agy: opt-in (disabled; hounfour.headless.agy_opt_in)"' >/dev/null
>  124 |   echo "$output" | jq -e '.providers.providers.openai | has("cli_hop_note") | not' >/dev/null
   125 |   printf 'hounfour:\n  headless:\n    agy_opt_in: true\n' > "$T/loa.config.yaml"
   126 |   run timeout 120 bash "$STATUS" --no-stale-check
   127 |   [ "$status" -eq 0 ]
   128 |   echo "$output" | grep -qE '^  google +key absent +hop agy +· http_api OPEN'
   129 |   run timeout 120 bash "$STATUS" --no-stale-check --json
   130 |   echo "$output" | jq -e '.providers.providers.google.cli_hop == "agy" and (.providers.providers.google | has("cli_hop_note") | not)' >/dev/null
   131 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -122,3 +194,9 @@
-  run timeout 120 bash "$STATUS" --no-stale-check --json
+  run --separate-stderr timeout 120 bash "$STATUS" --no-stale-check --json
   echo "$output" | jq -e '.providers.providers.google.cli_hop == null and .providers.providers.google.cli_hop_note == "agy: opt-in (disabled; hounfour.headless.agy_opt_in)"' >/dev/null
   echo "$output" | jq -e '.providers.providers.openai | has("cli_hop_note") | not' >/dev/null
+  # (review r251-1 G12: the string "true" is not the boolean — off, and one WARN naming the key and the type)
+  printf 'hounfour:\n  headless:\n    agy_opt_in: "true"\n' > "$T/loa.config.yaml"
+  run --separate-stderr timeout 120 bash "$STATUS" --no-stale-check
+  [ "$status" -eq 0 ]
+  echo "$output" | grep -qE '^  google +key absent +hop agy: opt-in \(disabled; hounfour\.headless\.agy_opt_in\)'
+  [ "$(grep -c 'hounfour.headless.agy_opt_in.*not a YAML boolean' <<<"$stderr")" = 1 ] || { echo "stderr=$stderr"; return 1; }
~~~~

## H190 — tests/unit/loa-status-providers.bats — head lines 129–131

Head context (head/tests/unit/loa-status-providers.bats, lines 117–131):

~~~~text
   117 |   printf 'hounfour:\n  headless:\n    mode: cli-only\n' > "$T/loa.config.yaml"
   118 |   export LOA_STATUS_CONFIG_FILE="$T/loa.config.yaml"
   119 |   run timeout 120 bash "$STATUS" --no-stale-check
   120 |   [ "$status" -eq 0 ] || { echo "rc=$status"; echo "$output" | tail -20; return 1; }
   121 |   echo "$output" | grep -qE '^  google +key absent +hop agy: opt-in \(disabled; hounfour\.headless\.agy_opt_in\)'
   122 |   run timeout 120 bash "$STATUS" --no-stale-check --json
   123 |   echo "$output" | jq -e '.providers.providers.google.cli_hop == null and .providers.providers.google.cli_hop_note == "agy: opt-in (disabled; hounfour.headless.agy_opt_in)"' >/dev/null
   124 |   echo "$output" | jq -e '.providers.providers.openai | has("cli_hop_note") | not' >/dev/null
   125 |   printf 'hounfour:\n  headless:\n    agy_opt_in: true\n' > "$T/loa.config.yaml"
   126 |   run timeout 120 bash "$STATUS" --no-stale-check
   127 |   [ "$status" -eq 0 ]
   128 |   echo "$output" | grep -qE '^  google +key absent +hop agy +· http_api OPEN'
>  129 |   run timeout 120 bash "$STATUS" --no-stale-check --json
>  130 |   echo "$output" | jq -e '.providers.providers.google.cli_hop == "agy" and (.providers.providers.google | has("cli_hop_note") | not)' >/dev/null
>  131 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -129,3 +207,60 @@
-  run timeout 120 bash "$STATUS" --no-stale-check --json
+  run --separate-stderr timeout 120 bash "$STATUS" --no-stale-check --json
   echo "$output" | jq -e '.providers.providers.google.cli_hop == "agy" and (.providers.providers.google | has("cli_hop_note") | not)' >/dev/null
 }
+
+@test "LSP-6 (r251-4 S8, audit n11) the opus target reaches yq as a value, never as expression text" {
+  # an alias crafted to rewrite the old interpolated expression into `… // 777 // …`
+  cat > "$T/catalog.yaml" <<'YAML'
+aliases:
+  opus: 'anthropic:zz" // 777 // ."zz'
+providers:
+  anthropic:
+    models:
+      claude-fixture-1:
+        context_window: 1000000
+        effective_input_ceiling: 200000
+        probed_ceiling: 200000
+YAML
+  export LOA_STATUS_MODEL_CONFIG="$T/catalog.yaml"
+  export LOA_CHEVAL_CEILING_OBSERVED_PATH="$T/none.json"
+  run timeout 120 bash "$STATUS" --no-stale-check --json
+  [ "$status" -eq 0 ]
+  echo "$output" | jq -e '.providers.providers.anthropic.ceiling.value != 777' >/dev/null || { echo "$output" | jq -c '.providers.providers.anthropic.ceiling'; return 1; }
+  # (and the printed probe command quotes the id, as cheval's hint does — audit n4)
+  echo "$output" | jq -e '.providers.providers.anthropic.ceiling.calibrate == ("python3 tools/ceiling-probe-live.py --model " + ("zz\" // 777 // .\"zz" | @sh) + " --write-catalog")' >/dev/null || { echo "$output" | jq -c '.providers.providers.anthropic.ceiling'; return 1; }
+}
+
+@test "LSP-7 (r251-4 S7 parity with routing.ceiling) an implausible observation (below 0.1 × the window) never becomes the displayed bound" {
+  _lsp5_catalog "$T/catalog.yaml" "" ""
+  export LOA_STATUS_MODEL_CONFIG="$T/catalog.yaml"
+  local m=claude-fixture-1
+  _lsp5_obs "$m" 1 PROVIDER_CONTEXT_LIMIT 150000 PROVIDER_CONTEXT_LIMIT
+  run timeout 120 bash "$STATUS" --no-stale-check --json
+  [ "$status" -eq 0 ]
+  echo "$output" | jq -e '.providers.providers.anthropic.ceiling | .basis == "observed" and .value == 149999' >/dev/null || { echo "$output" | jq -c '.providers.providers.anthropic.ceiling'; return 1; }
+  _lsp5_obs "$m" 1 PROVIDER_CONTEXT_LIMIT
+  run timeout 120 bash "$STATUS" --no-stale-check --json
+  echo "$output" | jq -e '.providers.providers.anthropic.ceiling | .basis == "probed" and .value == 200000' >/dev/null || { echo "$output" | jq -c '.providers.providers.anthropic.ceiling'; return 1; }
+}
+
+@test "LSP-8 (r251-4, sibling of S4) without lib/agy-gate-lib.sh /loa still answers: exit 0, the agy route reads off (fail closed), one WARN in human mode, --json quiet" {
+  local S="$T/copy/.claude/scripts"; mkdir -p "$S"
+  cp -- "$STATUS" "$S/loa-status.sh"   # (no lib/ beside it — a partial install)
+  run --separate-stderr timeout 120 bash "$S/loa-status.sh" --no-stale-check --json
+  [ "$status" -eq 0 ] || { echo "status=$status stderr=$stderr"; return 1; }
+  echo "$output" | jq -e '.providers.providers.google.cli_hop == null and .providers.providers.google.cli_hop_note == "agy: opt-in (disabled; hounfour.headless.agy_opt_in)"' >/dev/null || { echo "$output" | jq -c '.providers.providers.google'; return 1; }
+  [[ "$stderr" != *"agy-gate-lib"* ]] || { echo "--json warned: $stderr"; return 1; }
+  run --separate-stderr timeout 120 bash "$S/loa-status.sh" --no-stale-check
+  [ "$status" -eq 0 ]
+  [ "$(grep -c 'agy-gate-lib.sh.*not loaded' <<<"$stderr")" = 1 ] || { echo "stderr=$stderr"; return 1; }
+}
+
+@test "LSP-COLD (r251-5 U4, audit LOW-004) loa-status --json on a cold workflow-state cache is one valid JSON document" {
+  # (the AGC-6 batch flake: the first --json call after a grimoire edit missed the workflow-state cache, cache-manager's
+  # "v Cached result for key" line led workflow-state's stdout, and the final jq merge exited 5 — no retry hides it here:
+  # CACHE_DIR is a fresh directory, so this call is always the miss)
+  run --separate-stderr env CACHE_DIR="$T/cold-cache" LOA_STATUS_RUN_DIR="$T/run" LOA_STATUS_ENV_DIR="$T/env" \
+      timeout 180 bash "$STATUS" --no-stale-check --json
+  [ "$status" -eq 0 ] || { echo "status=$status stderr=$stderr"; return 1; }
+  jq -e '.providers.providers | type == "object"' >/dev/null <<<"$output" || { printf '%s\n' "$output" | head -5 | cat -v; return 1; }
+}
~~~~

## H191 — tests/unit/model-config-v3-schema.bats — head line 540

Head context (head/tests/unit/model-config-v3-schema.bats, lines 528–552):

~~~~text
   528 |     for ok in low medium high xhigh max; do
   529 |         run validate_v3 "$(_c126_model "{\"context_window\": 1000000, \"params\": {\"default_effort\": \"$ok\"}}")"
   530 |         [ "$status" -eq 0 ] || { echo "refused default_effort: $ok ($output)" >&2; return 1; }
   531 |     done
   532 |     for bad in '"ultra"' '"HIGH"' '""' 3 true null '["high"]'; do
   533 |         run validate_v3 "$(_c126_model "{\"context_window\": 1000000, \"params\": {\"default_effort\": $bad}}")"
   534 |         [ "$status" -ne 0 ] || { echo "accepted default_effort: $bad" >&2; return 1; }
   535 |     done
   536 | }
   537 | 
   538 | # cycle-127 FR-3 (SDD D-3.8): the headless probe's provenance inside ceiling_calibration.
   539 | @test "V3-add (c127): ceiling_calibration carries the probe provenance (method, transport, cli_version, cli_model, measured_input_tokens)" {
>  540 |     local ok='{"source": "operator_set", "calibrated_at": "2026-10-07T12:00:00Z", "sample_size": null, "stale_after_days": 90, "reprobe_trigger": "x", "method": "probed_headless", "transport": "claude-headless", "cli_version": "2.1.292 (Claude Code)", "cli_model": "global.anthropic.claude-opus-5-5", "measured_input_tokens": 640000}'
   541 |     run validate_v3 "$(_c126_model "{\"context_window\": 1000000, \"ceiling_calibration\": $ok}")"
   542 |     [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
   543 |     run validate_v3 "$(_c126_model '{"context_window": 1000000, "ceiling_calibration": {"source": "operator_set", "cli_version": null}}')"
   544 |     [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
   545 |     for bad in '"method": "guessed"' '"transport": "smoke-signal"' '"measured_input_tokens": 0' \
   546 |                '"measured_input_tokens": "640000"' '"cli_model": 5' '"source": "probed_headless"'; do
   547 |         run validate_v3 "$(_c126_model "{\"context_window\": 1000000, \"ceiling_calibration\": {\"source\": \"operator_set\", $bad}}")"
   548 |         [ "$status" -ne 0 ] || { echo "accepted ceiling_calibration: $bad" >&2; return 1; }
   549 |     done
   550 | }
   551 | 
   552 | @test "Live (c124): production model-config.yaml migrated with --to-v3 validates against v3 and keeps the catalog's own ceiling" {
~~~~

The change from head to the fix:

~~~~diff
@@ -540 +540 @@
-    local ok='{"source": "operator_set", "calibrated_at": "2026-10-07T12:00:00Z", "sample_size": null, "stale_after_days": 90, "reprobe_trigger": "x", "method": "probed_headless", "transport": "claude-headless", "cli_version": "2.1.292 (Claude Code)", "cli_model": "global.anthropic.claude-opus-5-5", "measured_input_tokens": 640000}'
+    local ok='{"source": "operator_set", "calibrated_at": "2026-10-07T12:00:00Z", "sample_size": null, "stale_after_days": 90, "reprobe_trigger": "x", "method": "probed_headless", "transport": "claude-headless", "cli_version": "2.1.292 (Claude Code)", "cli_model": "global.anthropic.claude-opus-5-5", "measured_input_tokens": 640000, "probe_outcome": "clean"}'
~~~~

## H192 — tests/unit/model-config-v3-schema.bats — head lines 545–546

Head context (head/tests/unit/model-config-v3-schema.bats, lines 533–558):

~~~~text
   533 |         run validate_v3 "$(_c126_model "{\"context_window\": 1000000, \"params\": {\"default_effort\": $bad}}")"
   534 |         [ "$status" -ne 0 ] || { echo "accepted default_effort: $bad" >&2; return 1; }
   535 |     done
   536 | }
   537 | 
   538 | # cycle-127 FR-3 (SDD D-3.8): the headless probe's provenance inside ceiling_calibration.
   539 | @test "V3-add (c127): ceiling_calibration carries the probe provenance (method, transport, cli_version, cli_model, measured_input_tokens)" {
   540 |     local ok='{"source": "operator_set", "calibrated_at": "2026-10-07T12:00:00Z", "sample_size": null, "stale_after_days": 90, "reprobe_trigger": "x", "method": "probed_headless", "transport": "claude-headless", "cli_version": "2.1.292 (Claude Code)", "cli_model": "global.anthropic.claude-opus-5-5", "measured_input_tokens": 640000}'
   541 |     run validate_v3 "$(_c126_model "{\"context_window\": 1000000, \"ceiling_calibration\": $ok}")"
   542 |     [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
   543 |     run validate_v3 "$(_c126_model '{"context_window": 1000000, "ceiling_calibration": {"source": "operator_set", "cli_version": null}}')"
   544 |     [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
>  545 |     for bad in '"method": "guessed"' '"transport": "smoke-signal"' '"measured_input_tokens": 0' \
>  546 |                '"measured_input_tokens": "640000"' '"cli_model": 5' '"source": "probed_headless"'; do
   547 |         run validate_v3 "$(_c126_model "{\"context_window\": 1000000, \"ceiling_calibration\": {\"source\": \"operator_set\", $bad}}")"
   548 |         [ "$status" -ne 0 ] || { echo "accepted ceiling_calibration: $bad" >&2; return 1; }
   549 |     done
   550 | }
   551 | 
   552 | @test "Live (c124): production model-config.yaml migrated with --to-v3 validates against v3 and keeps the catalog's own ceiling" {
   553 |     MIGRATE="$PROJECT_ROOT/.claude/scripts/loa-migrate-model-config.py"
   554 |     "$PYTHON_BIN" -c "import ruamel.yaml" 2>/dev/null || skip "ruamel.yaml not available in $PYTHON_BIN"
   555 |     run "$PYTHON_BIN" "$MIGRATE" "$PROJECT_ROOT/.claude/defaults/model-config.yaml" \
   556 |         -o "$WORK_DIR/live-v3.yaml" --to-v3 \
   557 |         --model-permissions "$PROJECT_ROOT/.claude/data/model-permissions.yaml" \
   558 |         --report-format json
~~~~

The change from head to the fix:

~~~~diff
@@ -545,2 +545,5 @@
+    # r251-4 T5: a probed_headless method needs transport claude-headless AND a probe_outcome (schema if/then)
     for bad in '"method": "guessed"' '"transport": "smoke-signal"' '"measured_input_tokens": 0' \
-               '"measured_input_tokens": "640000"' '"cli_model": 5' '"source": "probed_headless"'; do
+               '"measured_input_tokens": "640000"' '"cli_model": 5' '"source": "probed_headless"' \
+               '"method": "probed_headless", "transport": "claude-headless"' \
+               '"method": "probed_headless", "transport": "api", "probe_outcome": "clean"'; do
~~~~

## H193 — tests/unit/run-preflight.bats — insertion after head line 1

Head context (head/tests/unit/run-preflight.bats, lines 1–13):

~~~~text
     1 | #!/usr/bin/env bats
     2 | # =============================================================================
     3 | # tests/unit/run-preflight.bats — cycle-125 Sprint 3 (PRD FR-3 AC 1, SDD D-3.1)
     4 | #
     5 | # .claude/scripts/run-preflight.sh [--unattended] [--resume] [--json] [--root DIR]
     6 | # composes the run-mode pre-flight into one checklist: P1 defaultMode, P2 allow
     7 | # rules, P3 voices, P4 breakers, P5 NOTES size, P6 run state, P7 beads,
     8 | # P8 branch. One passing and one failing fixture per predicate; the checklist
     9 | # names the predicate and the fix; exit 1 on any FAIL; --json shape.
    10 | #
    11 | # Fixtures are synthetic project roots. The composed helper scripts
    12 | # (check-permissions.sh, beads/beads-health.sh, run-mode-ice.sh) read the real
    13 | # repository, so they are stubbed through the bats-gated LOA_PREFLIGHT_HELPERS_DIR
~~~~

The change from head to the fix:

~~~~diff
@@ -1,0 +2 @@
+bats_require_minimum_version 1.5.0
~~~~

## H194 — tests/unit/run-preflight.bats — insertion after head line 17

Head context (head/tests/unit/run-preflight.bats, lines 6–29):

~~~~text
     6 | # composes the run-mode pre-flight into one checklist: P1 defaultMode, P2 allow
     7 | # rules, P3 voices, P4 breakers, P5 NOTES size, P6 run state, P7 beads,
     8 | # P8 branch. One passing and one failing fixture per predicate; the checklist
     9 | # names the predicate and the fix; exit 1 on any FAIL; --json shape.
    10 | #
    11 | # Fixtures are synthetic project roots. The composed helper scripts
    12 | # (check-permissions.sh, beads/beads-health.sh, run-mode-ice.sh) read the real
    13 | # repository, so they are stubbed through the bats-gated LOA_PREFLIGHT_HELPERS_DIR
    14 | # seam; notes-guard.sh is pure and runs for real.
    15 | # =============================================================================
    16 | 
    17 | setup() {
    18 |   PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    19 |   PF="$PROJECT_ROOT/.claude/scripts/run-preflight.sh"
    20 |   GEN="$PROJECT_ROOT/tests/fixtures/notes/make-large-notes.sh"
    21 |   T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/pf.XXXXXX")"
    22 |   R="$T/root"
    23 |   mkdir -p "$R/.claude" "$R/.run" "$R/grimoires/loa" "$T/home/.claude" "$T/helpers/beads" "$T/bin"
    24 |   export HOME="$T/home"
    25 |   export LOA_PREFLIGHT_HELPERS_DIR="$T/helpers"
    26 |   unset OPENAI_API_KEY ANTHROPIC_API_KEY GOOGLE_API_KEY GEMINI_API_KEY LOA_BEADS_AUTONOMOUS_OVERRIDE
    27 |   # PATH: $T/bin first, then only the directories that hold the tools the script
    28 |   # needs (yq, jq, git, date) plus the system dirs — never the operator's
    29 |   # ~/.local/bin or npm bin where claude/codex/agy may live.
~~~~

The change from head to the fix:

~~~~diff
@@ -17,0 +19,3 @@
+  # (r251-5 U1/U2: every agy opt-in reader refuses a group- or world-writable config — fixtures are written owner-only
+  # whatever the host umask; a `>` redirect under umask 002 makes 0664)
+  umask 022
~~~~

## H195 — tests/unit/run-preflight.bats — insertion after head line 305

Head context (head/tests/unit/run-preflight.bats, lines 294–305):

~~~~text
   294 |   line_of P3 | grep -q '^\[FAIL\] P3 .*code_review'
   295 |   line_of P3 | grep -qF 'gemini-headless(agy: opt-in (disabled; hounfour.headless.agy_opt_in))'
   296 |   printf 'hounfour:\n  headless:\n    agy_opt_in: "true"\n' >> "$R/.loa.config.yaml"   # a string is not the boolean
   297 |   pf --unattended
   298 |   [ "$status" -eq 1 ]
   299 |   line_of P3 | grep -qF 'agy: opt-in (disabled; hounfour.headless.agy_opt_in)'
   300 |   python3 -I -c 'import sys; p=sys.argv[1]; s=open(p).read().replace("agy_opt_in: \"true\"", "agy_opt_in: true"); open(p,"w").write(s)' "$R/.loa.config.yaml"
   301 |   pf --unattended
   302 |   [ "$status" -eq 0 ]
   303 |   line_of P3 | grep -qF 'gemini-headless(cli agy)'
   304 |   ! line_of P3 | grep -q 'opt-in' || { echo "unexpected: line_of P3 | grep -q 'opt-in'"; return 1; }
   305 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -305,0 +310,147 @@
+
+@test "PF-AGY-2 P3 (review r251-1 G2): under hounfour.headless.mode cli-only a Google voice routes through agy — with the opt-in off it is not planned, not usable on its credential; under prefer-api the credential makes it usable" {
+  printf 'GOOGLE_API_KEY=not-a-real-key\n' > "$R/.env.local"
+  cat > "$R/.loa.config.yaml" <<'YAML'
+run_mode:
+  enabled: true
+hounfour:
+  headless:
+    mode: cli-only
+flatline_protocol:
+  code_review:
+    enabled: true
+    model: gemini-2.5-pro
+YAML
+  pf --unattended
+  [ "$status" -eq 1 ]
+  line_of P3 | grep -q '^\[FAIL\] P3 '
+  line_of P3 | grep -qF 'gemini-2.5-pro(agy: opt-in (disabled; hounfour.headless.agy_opt_in))'
+  ! line_of P3 | grep -q 'usable: gemini-2.5-pro' || { echo "unexpected: usable"; line_of P3; return 1; }
+  python3 -I -c 'import sys; p=sys.argv[1]; s=open(p).read().replace("mode: cli-only", "mode: prefer-api"); open(p,"w").write(s)' "$R/.loa.config.yaml"
+  pf --unattended
+  [ "$status" -eq 0 ]
+  line_of P3 | grep -qF 'usable: gemini-2.5-pro'
+  ! line_of P3 | grep -q 'opt-in' || { echo "unexpected: opt-in"; line_of P3; return 1; }
+}
+
+@test "PF-AGY-6 P3 (review r251-3 R3): under cli-only a Google voice is recognised by its PROVIDER, not the gemini* name — deep-research-pro with the opt-in off is not planned; under prefer-api its Google credential makes it usable" {
+  printf 'GOOGLE_API_KEY=not-a-real-key\n' > "$R/.env.local"
+  cat > "$R/.loa.config.yaml" <<'YAML'
+run_mode:
+  enabled: true
+hounfour:
+  headless:
+    mode: cli-only
+flatline_protocol:
+  code_review:
+    enabled: true
+    model: deep-research-pro
+YAML
+  pf --unattended
+  [ "$status" -eq 1 ]
+  line_of P3 | grep -q '^\[FAIL\] P3 '
+  line_of P3 | grep -qF 'deep-research-pro(agy: opt-in (disabled; hounfour.headless.agy_opt_in))' || { line_of P3; return 1; }
+  ! line_of P3 | grep -q 'usable: deep-research-pro' || { echo "unexpected: usable"; line_of P3; return 1; }
+  python3 -I -c 'import sys; p=sys.argv[1]; s=open(p).read().replace("mode: cli-only", "mode: prefer-api"); open(p,"w").write(s)' "$R/.loa.config.yaml"
+  pf --unattended
+  [ "$status" -eq 0 ] || { line_of P3; return 1; }
+  line_of P3 | grep -qF 'usable: deep-research-pro'
+  ! line_of P3 | grep -q 'opt-in' || { echo "unexpected: opt-in"; line_of P3; return 1; }
+}
+
+@test "PF-AGY-3 P3 (review r251-1 G8): a stage whose every voice is a gated agy hop stays FAIL and says the voices are not planned, naming the key — not 'no credential present and no CLI hop on PATH'" {
+  rm -f "$R/.env.local"
+  cat > "$R/.loa.config.yaml" <<'YAML'
+run_mode:
+  enabled: true
+flatline_protocol:
+  code_review:
+    enabled: true
+    model: gemini-headless
+    fallback_chain: [google:gemini-headless]
+YAML
+  pf --unattended
+  [ "$status" -eq 1 ]
+  line_of P3 | grep -q '^\[FAIL\] P3 .*code_review'
+  line_of P3 | grep -q 'every configured voice is not planned.*hounfour.headless.agy_opt_in' || { line_of P3; return 1; }
+  ! line_of P3 | grep -q 'no credential present and no CLI hop on PATH' || { echo "unexpected wording"; line_of P3; return 1; }
+  # a stage with a gated hop AND an ordinary missing voice keeps the ordinary wording (plus the not-planned note)
+  python3 -I -c 'import sys; p=sys.argv[1]; s=open(p).read().replace("[google:gemini-headless]", "[google:gemini-headless, gpt-5.5]"); open(p,"w").write(s)' "$R/.loa.config.yaml"
+  pf --unattended
+  [ "$status" -eq 1 ]
+  line_of P3 | grep -q 'no credential present and no CLI hop on PATH'
+  line_of P3 | grep -qF 'not planned: gemini-headless(agy: opt-in'
+}
+
+@test "PF-AGY-5 P3 (review r251-2 K3): with the opt-in ON an agy-routed voice is judged by the agy binary, never by its Google credential — cli-only gemini-2.5-pro and gemini-headless:any" {
+  printf 'GOOGLE_API_KEY=not-a-real-key\n' > "$R/.env.local"
+  cat > "$R/.loa.config.yaml" <<'YAML'
+run_mode:
+  enabled: true
+hounfour:
+  headless:
+    mode: cli-only
+    agy_opt_in: true
+flatline_protocol:
+  code_review:
+    enabled: true
+    model: gemini-2.5-pro
+YAML
+  # no agy on PATH: the key does not make the voice usable — cheval would route it to an absent agy
+  pf --unattended
+  [ "$status" -eq 1 ] || { echo "status=$status"; line_of P3; return 1; }
+  line_of P3 | grep -q '^\[FAIL\] P3 ' || { line_of P3; return 1; }
+  ! line_of P3 | grep -q 'usable: gemini-2.5-pro' || { echo "false PASS on the credential"; line_of P3; return 1; }
+  # a fake agy on PATH: usable, labelled as the agy CLI hop
+  printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/agy"; chmod +x "$T/bin/agy"
+  pf --unattended
+  [ "$status" -eq 0 ] || { echo "status=$status"; line_of P3; return 1; }
+  line_of P3 | grep -qF 'usable: gemini-2.5-pro(cli agy)' || { line_of P3; return 1; }
+  # the provider-form hop under prefer-api: the same — agy decides, not the key
+  rm -f "$T/bin/agy"
+  python3 -I -c 'import sys; p=sys.argv[1]; s=open(p).read().replace("mode: cli-only", "mode: prefer-api").replace("model: gemini-2.5-pro", "model: gemini-headless:any"); open(p,"w").write(s)' "$R/.loa.config.yaml"
+  pf --unattended
+  [ "$status" -eq 1 ] || { echo "status=$status"; line_of P3; return 1; }
+  ! line_of P3 | grep -q 'usable: gemini-headless:any' || { echo "false PASS on the credential"; line_of P3; return 1; }
+  printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/agy"; chmod +x "$T/bin/agy"
+  pf --unattended
+  [ "$status" -eq 0 ] || { echo "status=$status"; line_of P3; return 1; }
+  line_of P3 | grep -qF 'usable: gemini-headless:any(cli agy)' || { line_of P3; return 1; }
+}
+
+@test "PF-AGY-4 (review r251-1 G12): a string agy_opt_in reads off with one WARN naming the key and the type; --json stays quiet on stderr" {
+  printf 'hounfour:\n  headless:\n    agy_opt_in: "true"\n' >> "$R/.loa.config.yaml"
+  run --separate-stderr bash "$PF" --root "$R" --unattended
+  [ "$(grep -c 'hounfour.headless.agy_opt_in is present but not a YAML boolean (str)' <<<"$stderr")" = 1 ] || { echo "stderr=$stderr"; return 1; }
+  run --separate-stderr bash "$PF" --root "$R" --unattended --json
+  ! grep -q WARN <<<"$stderr" || { echo "json stderr=$stderr"; return 1; }
+  echo "$output" | jq -e . >/dev/null
+}
+
+@test "PF-AGY-7 (review r251-4 S4, audit n15): without the agy-gate lib run-preflight fails closed — exit 2, the lib named, no P3 verdict" {
+  local S="$T/scripts-copy"; mkdir -p "$S/lib"
+  cp -- "$PF" "$S/run-preflight.sh"   # (no lib/agy-gate-lib.sh beside it)
+  run --separate-stderr bash "$S/run-preflight.sh" --root "$R" --unattended
+  [ "$status" -eq 2 ] || { echo "status=$status out=$output"; return 1; }
+  [[ "$stderr" == *"agy-gate-lib.sh"* ]] || { echo "stderr=$stderr"; return 1; }
+  ! grep -q 'P3' <<<"$output" || { echo "a P3 verdict without the predicate: $output"; return 1; }
+}
+
+@test "PF-AGY-8 (review r251-4 S8, audit n14): a project alias of gemini-headless is an agy-routed voice — not planned with the opt-in off" {
+  rm -f "$R/.env.local"
+  cat > "$R/.loa.config.yaml" <<'YAML'
+run_mode:
+  enabled: true
+hounfour:
+  aliases:
+    myg: "google:gemini-headless"
+flatline_protocol:
+  code_review:
+    enabled: true
+    model: myg
+YAML
+  printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/agy"; chmod +x "$T/bin/agy"
+  pf --unattended
+  [ "$status" -eq 1 ]
+  line_of P3 | grep -qF 'myg(agy: opt-in (disabled; hounfour.headless.agy_opt_in))' || { line_of P3; return 1; }
+}
~~~~

## H196 — tools/ceiling-probe-live.py — head lines 33–37

Head context (head/tools/ceiling-probe-live.py, lines 21–49):

~~~~text
    21 |       --transport claude-headless --cli-model opus [--host-route TEXT] \
    22 |       [--tolerance-tokens 16000] [--write-catalog]
    23 | 
    24 | Each attempt runs the headless adapter's own argv (claude_headless_adapter.
    25 | build_headless_argv) plus `--effort low --max-turns 1` — the probe bypasses
    26 | cheval, so FR-2's catalog effort default does NOT apply; low effort and one
    27 | turn keep the output side negligible. The prompt goes on stdin, the cwd is a
    28 | private empty directory, auto memory is off. The prompt ends with a random
    29 | 12-hex needle; an attempt is ACCEPTED only when the completed JSON `result`
    30 | echoes it (a completed turn without it is `unverified`, never OK). The
    31 | accepted size is MEASURED from the CLI's JSON usage (input_tokens +
    32 | cache_creation_input_tokens + cache_read_input_tokens), not the filler size.
>   33 | A context-limit message (the provider's, or the CLI's own pre-flight check)
>   34 | is a size rejection; throttling / 429 / 5xx / network is retried up to 3
>   35 | attempts with backoff; anything else is `other`. Spend is cumulative over
>   36 | every attempt: max(the CLI's total_cost_usd, measured tokens × the catalog
>   37 | input price) — Bedrock bills separately (`pricing_basis: catalog_estimate`).
    38 | 
    39 | Outcome `clean` = the largest accepted step is verified, a size rejection
    40 | sits within --tolerance-tokens above it, and nothing was `other`,
    41 | unverified, budget-capped or inconsistent; anything else is `partial`
    42 | (exit 3; exit 1 when an `other` failure stopped it). The record is always
    43 | written; only `clean` with `--write-catalog` touches the catalog:
    44 | `probed_ceiling` and `effective_input_ceiling` = the measured accepted size
    45 | (raw — the api transport applies no safety margin either; a bound below
    46 | 180K is written as measured, never kept) and `ceiling_calibration`
    47 | {source: operator_set, method: probed_headless, transport, cli_version,
    48 | cli_model, measured_input_tokens, …}.
    49 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -33,5 +33,57 @@
-A context-limit message (the provider's, or the CLI's own pre-flight check)
-is a size rejection; throttling / 429 / 5xx / network is retried up to 3
-attempts with backoff; anything else is `other`. Spend is cumulative over
-every attempt: max(the CLI's total_cost_usd, measured tokens × the catalog
-input price) — Bedrock bills separately (`pricing_basis: catalog_estimate`).
+Every size is in MEASURED tokens (`size_unit: measured_tokens` in the
+record): --max-tokens-probe / --min-tokens-probe / --tolerance-tokens, the
+bisection targets, `largest_ok_input_tokens` and
+`smallest_failed_input_tokens`; the filler actually sent per step is rescaled
+by the latest measured/filler ratio and recorded beside it (`tokens`).
+
+The classifier reads the FULL diagnostic (at most the 1 MB capture; only
+the record's `detail` is truncated to 300 chars). A context-limit message
+(the provider's, or the CLI's own pre-flight check) is a size rejection.
+Throttling / 429 / 5xx (a status in context: `API Error: 5xx`, `HTTP 5xx`,
+`status 5xx`, `api_status=5xx`) / network is retried up to 3 attempts after
+5 s / 15 s; a token-budget 429 (tokens per minute) up to 4 attempts after
+20 s / 45 s / 75 s so the 60 s window clears, a `retry-after` hint honoured
+when longer, the total wait per step capped at 180 s. A token-budget 429 that
+persists over every attempt once the window was waited out is a size
+rejection (`failure_class: token_limit`); any other persisting transient,
+and anything else, is `other`. An exception inside the classifier is
+`other` with its text — never a traceback that loses the record; a ^C or
+an unexpected exception during the bisection still writes the record
+(`stop: interrupted`, `interrupted`: the exception, outcome `partial`, exit
+130 / 1, never a catalog write). A throttle marker (`throttl`, `please wait`,
+a 429 status, `rate limit`, `tokens per min`) on a message that also names
+tokens or a context limit — Bedrock's "Too many tokens, please wait before
+trying again" — is a token-budget transient, never a size rejection; a bound
+bracketed by anything but a context-limit rejection is `partial`. A
+timeout kills the CLI's whole process group (the route is a wrapper around
+`claude`; loa_cheval's run_subprocess_pgkill), and output past the 1 MB cap
+is `other`, never truncated into a classification. --allow-partial / --tier
+/ --itpm are api-transport flags: a usage error here (exit 2, no call).
+
+Spend (`spent_usd`, per sample `charged_usd` + `charge_basis`) is what each
+attempt plausibly cost, at the catalog input price × 1.25 — the cache-write
+rate the CLI is billed at for the prompt (`pricing_basis: catalog_estimate`,
+`estimate_rate`; Bedrock bills separately):
+  completion (ok / unverified)      max(CLI total_cost_usd, measured × price)
+  cli_local_rejection               0 (the CLI's own pre-flight; never sent)
+  provider rejection / transient    the CLI-reported cost if > 0, else 0
+                                    (`cli_reported` / `provider_rejection_unbilled`)
+  a failure carrying usage          max(CLI cost, measured × price) (`usage_reported`)
+  timeout / classifier error /      the estimate (the request may have run)
+  output past the cap / interrupted
+  not sent (spawn failed)           0
+The budget cap is checked BEFORE every attempt against the estimate
+(filler × ratio × price): what an attempt will cost is unknown until it
+returns. Until a step measures a ratio the estimate (only) assumes the Opus
+4.7+ tokenizer's 1.8 — the first step's filler is still sent blind. A CLI
+cost, token count or retry-after that is not a finite number in a sane range
+(cost < $1000, tokens < 10^9, retry-after < 3600 s) is dropped and noted in
+the sample's `dropped_values`.
+
+--host-route, the resolved --cli-model (an alias resolves through the
+wrapper's ANTHROPIC_DEFAULT_*_MODEL) and the CLI's --version reach the
+catalog's provenance text: a control or line-break character, or more than
+200 characters, is a usage error (exit 2) before any call. The writer
+re-parses the text it produced and refuses (nothing written) unless the
+entry's ceilings and calibration load as written and nothing else changed.
+The record names the binary resolved on PATH, `~`-relative under $HOME.
~~~~

## H197 — tools/ceiling-probe-live.py — head lines 43–48

Head context (head/tools/ceiling-probe-live.py, lines 31–60):

~~~~text
    31 | accepted size is MEASURED from the CLI's JSON usage (input_tokens +
    32 | cache_creation_input_tokens + cache_read_input_tokens), not the filler size.
    33 | A context-limit message (the provider's, or the CLI's own pre-flight check)
    34 | is a size rejection; throttling / 429 / 5xx / network is retried up to 3
    35 | attempts with backoff; anything else is `other`. Spend is cumulative over
    36 | every attempt: max(the CLI's total_cost_usd, measured tokens × the catalog
    37 | input price) — Bedrock bills separately (`pricing_basis: catalog_estimate`).
    38 | 
    39 | Outcome `clean` = the largest accepted step is verified, a size rejection
    40 | sits within --tolerance-tokens above it, and nothing was `other`,
    41 | unverified, budget-capped or inconsistent; anything else is `partial`
    42 | (exit 3; exit 1 when an `other` failure stopped it). The record is always
>   43 | written; only `clean` with `--write-catalog` touches the catalog:
>   44 | `probed_ceiling` and `effective_input_ceiling` = the measured accepted size
>   45 | (raw — the api transport applies no safety margin either; a bound below
>   46 | 180K is written as measured, never kept) and `ceiling_calibration`
>   47 | {source: operator_set, method: probed_headless, transport, cli_version,
>   48 | cli_model, measured_input_tokens, …}.
    49 | 
    50 | Exit codes: 0 probe completed · 1 a call failed for a non-size reason ·
    51 | 2 usage · 3 the budget cap stopped the bisection (`partial: true` — the
    52 | record is still written but is NOT full evidence). A call is OK when the
    53 | stream reaches `message_stop`
    54 | without an error event — NOT when a text block arrives: default-on thinking
    55 | (Opus 5 / Fable) can spend a small `max_tokens` entirely on reasoning, which
    56 | is a budget outcome, not a size failure (review round-1 medium 7). Each call
    57 | asks for up to 1024 output tokens and records `stop_reason`; the cost is
    58 | still dominated by input: 200K tokens on Opus 5 ≈ $1.00 per call; the budget
    59 | cap stops the search (largest OK so far is still reported, `partial: true`,
    60 | exit 3).
~~~~

The change from head to the fix:

~~~~diff
@@ -43,6 +95,18 @@
-written; only `clean` with `--write-catalog` touches the catalog:
-`probed_ceiling` and `effective_input_ceiling` = the measured accepted size
-(raw — the api transport applies no safety margin either; a bound below
-180K is written as measured, never kept) and `ceiling_calibration`
-{source: operator_set, method: probed_headless, transport, cli_version,
-cli_model, measured_input_tokens, …}.
+written; only `clean` with `--write-catalog` touches the catalog — unless --write-partial-as-operator-set says the
+operator vouches for the last verified accept (the entry then carries
+`probe_outcome: partial`; the exit code still reports the partial probe).
+Every write records `ceiling_calibration.probe_outcome` (clean | partial) and
+`sample_size` = the record's sample count (accepted + rejected). With --write-catalog the entry's write
+prerequisites (the block, a positive `context_window`, `probed_ceiling`,
+`effective_input_ceiling`, `ceiling_calibration`) are checked before the
+first call — exit 2, no spend, when one is missing. The write is the I2
+clamp of the measured accept:
+  written = min(measured, context_window − default_max_tokens)
+(cheval's invariant `effective_input_ceiling + default max_tokens ≤
+context_window`, default_max_tokens from the entry's max_output_tokens, the
+streaming default regardless of the operator's switches; no other margin; a
+bound below 180K is written as measured, never kept) into `probed_ceiling`
+and `effective_input_ceiling` — the record's `written_ceiling` — with the raw
+accept kept in `ceiling_calibration.measured_input_tokens` and
+`ceiling_calibration` {source: operator_set, method: probed_headless,
+transport, cli_version, cli_model, measured_input_tokens, …}.
~~~~

## H198 — tools/ceiling-probe-live.py — head line 70

Head context (head/tools/ceiling-probe-live.py, lines 58–82):

~~~~text
    58 | still dominated by input: 200K tokens on Opus 5 ≈ $1.00 per call; the budget
    59 | cap stops the search (largest OK so far is still reported, `partial: true`,
    60 | exit 3).
    61 | 
    62 | Never run this from a test without LOA_RUN_LIVE_TESTS=1 — it spends money.
    63 | """
    64 | 
    65 | from __future__ import annotations
    66 | 
    67 | import argparse
    68 | import datetime as dt
    69 | import json
>   70 | import os
    71 | import shutil
    72 | import subprocess
    73 | import sys
    74 | import tempfile
    75 | import urllib.error
    76 | import urllib.request
    77 | 
    78 | API = "https://api.anthropic.com/v1/messages"
    79 | # micro-USD per input MTok (the catalog's pricing.input_per_mtok). Bedrock bills
    80 | # separately; the CLI transport records `pricing_basis: catalog_estimate`.
    81 | _PRICE_IN = {"claude-opus-5-5": 4_000_000, "claude-opus-5": 5_000_000, "claude-fable-5-1": 10_000_000, "claude-sonnet-5": 2_000_000,
    82 |              "claude-opus-4-8": 5_000_000, "claude-haiku-4-5-20251001": 1_000_000}
~~~~

The change from head to the fix:

~~~~diff
@@ -70 +134,3 @@
+import math
 import os
+import re
~~~~

## H199 — tools/ceiling-probe-live.py — insertion after head line 74

Head context (head/tools/ceiling-probe-live.py, lines 63–86):

~~~~text
    63 | """
    64 | 
    65 | from __future__ import annotations
    66 | 
    67 | import argparse
    68 | import datetime as dt
    69 | import json
    70 | import os
    71 | import shutil
    72 | import subprocess
    73 | import sys
    74 | import tempfile
    75 | import urllib.error
    76 | import urllib.request
    77 | 
    78 | API = "https://api.anthropic.com/v1/messages"
    79 | # micro-USD per input MTok (the catalog's pricing.input_per_mtok). Bedrock bills
    80 | # separately; the CLI transport records `pricing_basis: catalog_estimate`.
    81 | _PRICE_IN = {"claude-opus-5-5": 4_000_000, "claude-opus-5": 5_000_000, "claude-fable-5-1": 10_000_000, "claude-sonnet-5": 2_000_000,
    82 |              "claude-opus-4-8": 5_000_000, "claude-haiku-4-5-20251001": 1_000_000}
    83 | _FILLER = "The quick brown fox jumps over the lazy dog. "  # ≈ 10 tokens
    84 | 
    85 | 
    86 | def _probe_once(model: str, tokens: int, key: str) -> tuple[bool, str, str | None]:
~~~~

The change from head to the fix:

~~~~diff
@@ -74,0 +141 @@
+import traceback
~~~~

## H200 — tools/ceiling-probe-live.py — head line 134

Head context (head/tools/ceiling-probe-live.py, lines 122–146):

~~~~text
   122 |     except urllib.error.HTTPError as e:
   123 |         detail = e.read().decode(errors="replace")[:300]
   124 |         if e.code in (400, 413) and ("too long" in detail or "exceed" in detail or "maximum" in detail):
   125 |             return False, f"HTTP {e.code}: {detail}", None
   126 |         raise RuntimeError(f"HTTP {e.code} (non-size failure): {detail}")
   127 |     except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
   128 |         return False, f"transport: {e}", None
   129 | 
   130 | 
   131 | _ADAPTERS_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".claude", "adapters")
   132 | _CAPTURE_CAP = 1 << 20          # bytes kept of a CLI's stdout / stderr
   133 | _ATTEMPTS = 3                   # per step, for transient classes only
>  134 | _BACKOFF_S = (5, 15)            # sleep before attempt 2, 3
   135 | _SLEEP = __import__("time").sleep
   136 | # `opus` / `sonnet` / `haiku` are resolved by the claude CLI itself from these
   137 | # pins (the claude-bedrock wrapper exports them); recorded when visible.
   138 | _CLI_ALIAS_ENV = {"opus": "ANTHROPIC_DEFAULT_OPUS_MODEL", "sonnet": "ANTHROPIC_DEFAULT_SONNET_MODEL",
   139 |                   "haiku": "ANTHROPIC_DEFAULT_HAIKU_MODEL"}
   140 | # Beyond the adapter's own RateLimitError class: ProviderUnavailableError is the
   141 | # adapter's catch-all, transient only when the diagnostic names one of these.
   142 | _TRANSIENT_MARKERS = ("throttl", "timeout", "timed out", "connection", "network", "econnreset", "socket",
   143 |                       "service unavailable", "internal server error", "bad gateway", "overloaded")
   144 | _STATUS_5XX = __import__("re").compile(r"\b5\d\d\b")
   145 | # Explicit provider markers only: a bare 4xx pattern matched the CLI's own token
   146 | # counts ("Prompt is too long: 403,000 tokens > …") as provider-origin.
~~~~

The change from head to the fix:

~~~~diff
@@ -134 +201,17 @@
-_BACKOFF_S = (5, 15)            # sleep before attempt 2, 3
+_BACKOFF_S = (5, 15)            # 5xx / network / throttling: sleep before attempt 2, 3
+# A token-budget 429 (tokens per minute) cannot clear in 5 s / 15 s: wait the
+# 60 s window out (r251-1 P2), honour a longer retry-after hint, cap the total.
+_TPM_ATTEMPTS = 4
+_TPM_BACKOFF_S = (20, 45, 75)   # sleep before attempt 2, 3, 4 (cumulative 140 s)
+_TPM_WINDOW_S = 60
+if sum(_TPM_BACKOFF_S) < _TPM_WINDOW_S:  # r251-2 Q7: the schedule alone clears the window
+    raise RuntimeError("ceiling-probe-live: _TPM_BACKOFF_S must sum to at least _TPM_WINDOW_S")
+_RETRY_WAIT_CAP_S = 180         # total sleep per step, every class
+_PRIOR_RATIO = 1.8              # measured/filler before any step measures (estimates only, r251-4 T3)
+_RETRY_AFTER = re.compile(r"retry[-_ ]after\W{0,4}(\d+(?:\.\d+)?)", re.I)
+# A throttle marker (verifier r251-1) wins over a context marker: Bedrock's token
+# throttle reads "Too many tokens, please wait before trying again" — it carries
+# the context marker `too many tokens`, so without the rule the first throttle is
+# a size rejection with no retry. r251-3 R1: the rule lives in ONE place,
+# loa_cheval.routing.ceiling.is_throttle_message, shared with the headless
+# adapter (a 429 / 529 only in status position, never inside a token count).
~~~~

## H201 — tools/ceiling-probe-live.py — head line 144

Head context (head/tools/ceiling-probe-live.py, lines 132–156):

~~~~text
   132 | _CAPTURE_CAP = 1 << 20          # bytes kept of a CLI's stdout / stderr
   133 | _ATTEMPTS = 3                   # per step, for transient classes only
   134 | _BACKOFF_S = (5, 15)            # sleep before attempt 2, 3
   135 | _SLEEP = __import__("time").sleep
   136 | # `opus` / `sonnet` / `haiku` are resolved by the claude CLI itself from these
   137 | # pins (the claude-bedrock wrapper exports them); recorded when visible.
   138 | _CLI_ALIAS_ENV = {"opus": "ANTHROPIC_DEFAULT_OPUS_MODEL", "sonnet": "ANTHROPIC_DEFAULT_SONNET_MODEL",
   139 |                   "haiku": "ANTHROPIC_DEFAULT_HAIKU_MODEL"}
   140 | # Beyond the adapter's own RateLimitError class: ProviderUnavailableError is the
   141 | # adapter's catch-all, transient only when the diagnostic names one of these.
   142 | _TRANSIENT_MARKERS = ("throttl", "timeout", "timed out", "connection", "network", "econnreset", "socket",
   143 |                       "service unavailable", "internal server error", "bad gateway", "overloaded")
>  144 | _STATUS_5XX = __import__("re").compile(r"\b5\d\d\b")
   145 | # Explicit provider markers only: a bare 4xx pattern matched the CLI's own token
   146 | # counts ("Prompt is too long: 403,000 tokens > …") as provider-origin.
   147 | _PROVIDER_ORIGIN = __import__("re").compile(r"api error|api_status=|api_error_status|invalid_request_error|"
   148 |                                             r"validationexception|\b(?:http|status)[ :]+4\d\d\b", __import__("re").I)
   149 | 
   150 | 
   151 | def _adapters():
   152 |     """The one import seam into cheval (tools/ is not a package): the adapters
   153 |     directory is located from THIS file and put on sys.path explicitly, so the
   154 |     probe works from any cwd and under `python3 -I` (never via cwd)."""
   155 |     if _ADAPTERS_DIR not in sys.path:
   156 |         sys.path.insert(0, _ADAPTERS_DIR)
~~~~

The change from head to the fix:

~~~~diff
@@ -144 +227,3 @@
-_STATUS_5XX = __import__("re").compile(r"\b5\d\d\b")
+# A 5xx only in a status context (r251-1 P8): a bare 3-digit number ("took 503 ms") is not one.
+_STATUS_5XX = re.compile(r"(?:\bapi error\b|\bhttp(?:/[\d.]+)?|\bstatus(?:[ _]code)?|api_status=|"
+                         r"api_error_status[\"']?)[\s:=]*5\d\d\b", re.I)
~~~~

## H202 — tools/ceiling-probe-live.py — insertion after head line 166

Head context (head/tools/ceiling-probe-live.py, lines 155–178):

~~~~text
   155 |     if _ADAPTERS_DIR not in sys.path:
   156 |         sys.path.insert(0, _ADAPTERS_DIR)
   157 |     from loa_cheval.providers import claude_headless_adapter
   158 |     from loa_cheval.routing import ceiling
   159 |     from loa_cheval import types as cheval_types
   160 |     return claude_headless_adapter, ceiling, cheval_types
   161 | 
   162 | 
   163 | def _cli_bin() -> str:
   164 |     return os.environ.get("CLAUDE_HEADLESS_BIN") or "claude"
   165 | 
   166 | 
   167 | def _cli_command(cli_bin: str, cli_model: str) -> list[str]:
   168 |     """The adapter's argv (prompt on stdin) + the probe's pins: --effort low --max-turns 1."""
   169 |     cha, _, _ = _adapters()
   170 |     return cha.build_headless_argv(cli_bin, cli_model, effort="low", max_turns=1)
   171 | 
   172 | 
   173 | def _resolved_cli_model(cli_model: str) -> str:
   174 |     env = _CLI_ALIAS_ENV.get(cli_model)
   175 |     return (os.environ.get(env) or cli_model) if env else cli_model
   176 | 
   177 | 
   178 | def _default_host_route(cli_bin: str) -> str:
~~~~

The change from head to the fix:

~~~~diff
@@ -166,0 +252,33 @@
+def _home_rel(path: str) -> str:
+    """r251-4 T4 (n40): a path under the operator's home, rendered `~/…` for the record."""
+    home = os.path.expanduser("~").rstrip("/")
+    if home and path.startswith(home + "/"):
+        return "~" + path[len(home):]
+    return path
+
+
+def _recorded_bin(cli_bin: str) -> str:
+    """r251-4 T4 (n43): the binary that ran — resolved on PATH when bare — `~`-relative."""
+    return _home_rel(shutil.which(cli_bin) or cli_bin)
+
+
+# r251-4 T1 (n52): values that reach the catalog's provenance comment must be one
+# short line. C0 controls, DEL, C1 controls (NEL \x85 is a YAML line break) and the
+# Unicode line / paragraph separators all end a YAML comment.
+_UNSAFE_CHARS = re.compile("[\x00-\x1f\x7f-\x9f\u2028\u2029]")
+_FIELD_MAX = 200
+
+
+def _unsafe_field(value) -> str | None:
+    """Why `value` may not reach the catalog text, or None when it may."""
+    if value is None:
+        return None
+    if not isinstance(value, str):
+        return f"not a string ({type(value).__name__})"
+    if _UNSAFE_CHARS.search(value):
+        return "contains a control or line-break character"
+    if len(value) > _FIELD_MAX:
+        return f"is {len(value)} characters (max {_FIELD_MAX})"
+    return None
+
+
~~~~

## H203 — tools/ceiling-probe-live.py — head lines 215–225

Head context (head/tools/ceiling-probe-live.py, lines 203–237):

~~~~text
   203 | 
   204 | 
   205 | def _measured(usage) -> int | None:
   206 |     if not isinstance(usage, dict):
   207 |         return None
   208 |     total = sum(v for k, v in usage.items()
   209 |                 if k in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens")
   210 |                 and isinstance(v, int) and not isinstance(v, bool))
   211 |     return total or None
   212 | 
   213 | 
   214 | def _run_capped(cmd: list[str], prompt: str, timeout: int) -> tuple[int, str, str]:
>  215 |     """Run with stdout/stderr spooled to temp files and read back capped at 1 MB."""
>  216 |     workspace = tempfile.mkdtemp(prefix="loa-ceiling-probe-")
>  217 |     env = {**os.environ, "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1"}
>  218 |     try:
>  219 |         with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
>  220 |             proc = subprocess.run(cmd, input=prompt.encode("utf-8"), stdout=out, stderr=err,
>  221 |                                   cwd=workspace, env=env, timeout=timeout)
>  222 |             out.seek(0)
>  223 |             err.seek(0)
>  224 |             return (proc.returncode, out.read(_CAPTURE_CAP).decode("utf-8", errors="replace"),
>  225 |                     err.read(_CAPTURE_CAP).decode("utf-8", errors="replace"))
   226 |     finally:
   227 |         shutil.rmtree(workspace, ignore_errors=True)
   228 | 
   229 | 
   230 | def _classify(rc: int, stdout: str, stderr: str, needle: str) -> dict:
   231 |     """One attempt → {kind: ok|unverified|size|transient|other, …}."""
   232 |     cha, ceiling, t = _adapters()
   233 |     try:
   234 |         parsed = json.loads(stdout) if stdout.strip() else None
   235 |     except json.JSONDecodeError:
   236 |         parsed = None
   237 |     usage = parsed.get("usage") if isinstance(parsed, dict) else None
~~~~

The change from head to the fix:

~~~~diff
@@ -215,11 +333,15 @@
-    """Run with stdout/stderr spooled to temp files and read back capped at 1 MB."""
+    """Run through loa_cheval's run_subprocess_pgkill (r251-1 P7): the child
+    leads its own process group and a timeout (or any exception, ^C included)
+    SIGKILLs the GROUP — the route is usually a wrapper (claude-bedrock) around
+    `claude`, and subprocess.run(timeout=) kills only the direct child. Output
+    past the 1 MB per-stream cap raises SubprocessOutputCapExceeded (the group
+    killed first) instead of truncating: a truncated answer never classifies;
+    the step maps it to `other`."""
+    _adapters()
+    from loa_cheval.providers.base import run_subprocess_pgkill
     workspace = tempfile.mkdtemp(prefix="loa-ceiling-probe-")
     env = {**os.environ, "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1"}
     try:
-        with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
-            proc = subprocess.run(cmd, input=prompt.encode("utf-8"), stdout=out, stderr=err,
-                                  cwd=workspace, env=env, timeout=timeout)
-            out.seek(0)
-            err.seek(0)
-            return (proc.returncode, out.read(_CAPTURE_CAP).decode("utf-8", errors="replace"),
-                    err.read(_CAPTURE_CAP).decode("utf-8", errors="replace"))
+        proc = run_subprocess_pgkill(cmd, input=prompt, timeout=timeout, env=env, max_bytes=_CAPTURE_CAP,
+                                     cwd=workspace)
+        return proc.returncode, proc.stdout, proc.stderr
~~~~

## H204 — tools/ceiling-probe-live.py — head lines 230–232

Head context (head/tools/ceiling-probe-live.py, lines 218–244):

~~~~text
   218 |     try:
   219 |         with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
   220 |             proc = subprocess.run(cmd, input=prompt.encode("utf-8"), stdout=out, stderr=err,
   221 |                                   cwd=workspace, env=env, timeout=timeout)
   222 |             out.seek(0)
   223 |             err.seek(0)
   224 |             return (proc.returncode, out.read(_CAPTURE_CAP).decode("utf-8", errors="replace"),
   225 |                     err.read(_CAPTURE_CAP).decode("utf-8", errors="replace"))
   226 |     finally:
   227 |         shutil.rmtree(workspace, ignore_errors=True)
   228 | 
   229 | 
>  230 | def _classify(rc: int, stdout: str, stderr: str, needle: str) -> dict:
>  231 |     """One attempt → {kind: ok|unverified|size|transient|other, …}."""
>  232 |     cha, ceiling, t = _adapters()
   233 |     try:
   234 |         parsed = json.loads(stdout) if stdout.strip() else None
   235 |     except json.JSONDecodeError:
   236 |         parsed = None
   237 |     usage = parsed.get("usage") if isinstance(parsed, dict) else None
   238 |     base = {"measured_input_tokens": _measured(usage),
   239 |             "cli_reported_cost_usd": parsed.get("total_cost_usd") if isinstance(parsed, dict) else None,
   240 |             "stop_reason": parsed.get("stop_reason") if isinstance(parsed, dict) else None}
   241 |     if rc == 0 and isinstance(parsed, dict) and not parsed.get("is_error"):
   242 |         result = str(parsed.get("result") or "")
   243 |         if needle in result:
   244 |             return {**base, "kind": "ok", "detail": ""}
~~~~

The change from head to the fix:

~~~~diff
@@ -230,3 +352,38 @@
+_DETAIL_CHARS = 300             # the record's `detail`; classification reads the full text
+# r251-4 T2 (n56): numbers the CLI's JSON reports are kept only when finite and sane —
+# json.loads accepts Infinity / NaN, and int(inf * 1e6) raised OverflowError in _charge.
+_MAX_COST_USD = 1000
+_MAX_TOKENS = 10 ** 9
+_MAX_RETRY_AFTER_S = 3600
+
+
+def _bounded(name: str, value, upper, dropped: list) -> int | float | None:
+    """`value` when it is a finite number in [0, upper), else None (noted in `dropped`)."""
+    if value is None:
+        return None
+    if isinstance(value, bool) or not isinstance(value, (int, float)):
+        dropped.append(f"{name}={value!r:.60}: not a number")
+        return None
+    if isinstance(value, float) and not math.isfinite(value):
+        dropped.append(f"{name}={value!r}: not finite")
+        return None
+    if not 0 <= value < upper:
+        dropped.append(f"{name}={value!r:.60}: outside [0, {upper})")
+        return None
+    return value
+
+
 def _classify(rc: int, stdout: str, stderr: str, needle: str) -> dict:
-    """One attempt → {kind: ok|unverified|size|transient|other, …}."""
+    """One attempt → {kind: ok|unverified|size|transient|other, …}. Never raises
+    (r251-1 P5): an exception inside classification is `other` with its text."""
+    try:
+        return _classify_unguarded(rc, stdout, stderr, needle)
+    except Exception as e:  # noqa: BLE001 — the record must survive any classifier defect
+        return {"kind": "other", "classifier_error": True, "measured_input_tokens": None,
+                "cli_reported_cost_usd": None, "stop_reason": None,
+                "detail": f"classifier error: {type(e).__name__}: {e}"[:_DETAIL_CHARS]}
+
+
+def _classify_unguarded(rc: int, stdout: str, stderr: str, needle: str) -> dict:
     cha, ceiling, t = _adapters()
+    stdout, stderr = stdout[:_CAPTURE_CAP], stderr[:_CAPTURE_CAP]
~~~~

## H205 — tools/ceiling-probe-live.py — head lines 238–240

Head context (head/tools/ceiling-probe-live.py, lines 226–252):

~~~~text
   226 |     finally:
   227 |         shutil.rmtree(workspace, ignore_errors=True)
   228 | 
   229 | 
   230 | def _classify(rc: int, stdout: str, stderr: str, needle: str) -> dict:
   231 |     """One attempt → {kind: ok|unverified|size|transient|other, …}."""
   232 |     cha, ceiling, t = _adapters()
   233 |     try:
   234 |         parsed = json.loads(stdout) if stdout.strip() else None
   235 |     except json.JSONDecodeError:
   236 |         parsed = None
   237 |     usage = parsed.get("usage") if isinstance(parsed, dict) else None
>  238 |     base = {"measured_input_tokens": _measured(usage),
>  239 |             "cli_reported_cost_usd": parsed.get("total_cost_usd") if isinstance(parsed, dict) else None,
>  240 |             "stop_reason": parsed.get("stop_reason") if isinstance(parsed, dict) else None}
   241 |     if rc == 0 and isinstance(parsed, dict) and not parsed.get("is_error"):
   242 |         result = str(parsed.get("result") or "")
   243 |         if needle in result:
   244 |             return {**base, "kind": "ok", "detail": ""}
   245 |         return {**base, "kind": "unverified", "detail": f"completed without the needle: {result[:120]!r}"}
   246 |     if not isinstance(parsed, dict):
   247 |         if rc == 0:
   248 |             return {**base, "kind": "other", "detail": f"non-JSON output: {stdout.strip()[:200]!r}"}
   249 |     result = str(parsed.get("result") or "") if isinstance(parsed, dict) and parsed.get("is_error") else ""
   250 |     api_status = parsed.get("api_error_status") if isinstance(parsed, dict) else None
   251 |     diag = " ".join(x for x in (result, f"(api_status={api_status})" if api_status else "", stderr.strip()) if x)
   252 |     diag = (diag or stdout.strip() or f"exit code {rc}, no diagnostic")[:300]
~~~~

The change from head to the fix:

~~~~diff
@@ -238,3 +395,8 @@
-    base = {"measured_input_tokens": _measured(usage),
-            "cli_reported_cost_usd": parsed.get("total_cost_usd") if isinstance(parsed, dict) else None,
+    dropped: list[str] = []
+    base = {"measured_input_tokens": _bounded("measured_input_tokens", _measured(usage), _MAX_TOKENS, dropped),
+            "cli_reported_cost_usd": _bounded("cli_reported_cost_usd",
+                                              parsed.get("total_cost_usd") if isinstance(parsed, dict) else None,
+                                              _MAX_COST_USD, dropped),
             "stop_reason": parsed.get("stop_reason") if isinstance(parsed, dict) else None}
+    if dropped:
+        base["dropped_values"] = dropped
~~~~

## H206 — tools/ceiling-probe-live.py — head lines 251–257

Head context (head/tools/ceiling-probe-live.py, lines 239–269):

~~~~text
   239 |             "cli_reported_cost_usd": parsed.get("total_cost_usd") if isinstance(parsed, dict) else None,
   240 |             "stop_reason": parsed.get("stop_reason") if isinstance(parsed, dict) else None}
   241 |     if rc == 0 and isinstance(parsed, dict) and not parsed.get("is_error"):
   242 |         result = str(parsed.get("result") or "")
   243 |         if needle in result:
   244 |             return {**base, "kind": "ok", "detail": ""}
   245 |         return {**base, "kind": "unverified", "detail": f"completed without the needle: {result[:120]!r}"}
   246 |     if not isinstance(parsed, dict):
   247 |         if rc == 0:
   248 |             return {**base, "kind": "other", "detail": f"non-JSON output: {stdout.strip()[:200]!r}"}
   249 |     result = str(parsed.get("result") or "") if isinstance(parsed, dict) and parsed.get("is_error") else ""
   250 |     api_status = parsed.get("api_error_status") if isinstance(parsed, dict) else None
>  251 |     diag = " ".join(x for x in (result, f"(api_status={api_status})" if api_status else "", stderr.strip()) if x)
>  252 |     diag = (diag or stdout.strip() or f"exit code {rc}, no diagnostic")[:300]
>  253 |     if ceiling.is_context_limit_message(diag):
>  254 |         origin = "provider" if (api_status or _PROVIDER_ORIGIN.search(diag)) else "cli_local"
>  255 |         return {**base, "kind": "size", "failure_class": "context_limit", "size_origin": origin, "detail": diag,
>  256 |                 "rejected_input_tokens": ceiling.parse_context_limit(diag).get("input_tokens")}
>  257 |     if ceiling.is_token_limit_message(diag):
   258 |         # a token-budget 429: retried as transient; persisting at this size it is a size rejection
   259 |         return {**base, "kind": "transient", "token_limit": True, "detail": diag}
   260 |     try:
   261 |         cha.ClaudeHeadlessAdapter._raise_for_error(__import__("types").SimpleNamespace(provider="claude-headless"),
   262 |                                                    returncode=rc, stderr=stderr, parsed=parsed)
   263 |     except t.RateLimitError:
   264 |         return {**base, "kind": "transient", "detail": diag}
   265 |     except t.ProviderUnavailableError:
   266 |         low = diag.lower()
   267 |         if any(m in low for m in _TRANSIENT_MARKERS) or _STATUS_5XX.search(diag):
   268 |             return {**base, "kind": "transient", "detail": diag}
   269 |         return {**base, "kind": "other", "detail": diag}
~~~~

The change from head to the fix:

~~~~diff
@@ -251,7 +413,24 @@
-    diag = " ".join(x for x in (result, f"(api_status={api_status})" if api_status else "", stderr.strip()) if x)
-    diag = (diag or stdout.strip() or f"exit code {rc}, no diagnostic")[:300]
-    if ceiling.is_context_limit_message(diag):
-        origin = "provider" if (api_status or _PROVIDER_ORIGIN.search(diag)) else "cli_local"
+    full = " ".join(x for x in (result, f"(api_status={api_status})" if api_status else "", stderr.strip()) if x)
+    full = (full or stdout.strip() or f"exit code {rc}, no diagnostic")[:_CAPTURE_CAP]
+    diag = full[:_DETAIL_CHARS]          # for the record only (r251-1 P4)
+    hint = _RETRY_AFTER.search(full)
+    if hint:
+        wait_hint = _bounded("retry_after_s", float(hint.group(1)), _MAX_RETRY_AFTER_S, dropped)
+        if wait_hint is not None:
+            base["retry_after_s"] = wait_hint
+        if dropped:
+            base["dropped_values"] = dropped
+    # r251-2 Q1: the throttle verdict reads the CLI's own answer (result + api_status);
+    # stderr decides only when there is no result, so a stale "rate limit … please
+    # wait" line on stderr cannot turn a genuine context-limit result into a transient
+    throttle_text = " ".join(x for x in (result, f"(api_status={api_status})" if api_status else "") if x) \
+        if result else full
+    if ceiling.is_throttle_message(throttle_text) and (ceiling.is_context_limit_message(full)
+                                            or ceiling.is_token_limit_message(full)):
+        # a token throttle, even when it also reads like a context limit: retried on the TPM schedule
+        return {**base, "kind": "transient", "token_limit": True, "detail": diag}
+    if ceiling.is_context_limit_message(full):
+        origin = "provider" if (api_status or _PROVIDER_ORIGIN.search(full)) else "cli_local"
         return {**base, "kind": "size", "failure_class": "context_limit", "size_origin": origin, "detail": diag,
-                "rejected_input_tokens": ceiling.parse_context_limit(diag).get("input_tokens")}
-    if ceiling.is_token_limit_message(diag):
+                "rejected_input_tokens": ceiling.parse_context_limit(full).get("input_tokens")}
+    if ceiling.is_token_limit_message(full):
~~~~

## H207 — tools/ceiling-probe-live.py — head lines 266–267

Head context (head/tools/ceiling-probe-live.py, lines 254–279):

~~~~text
   254 |         origin = "provider" if (api_status or _PROVIDER_ORIGIN.search(diag)) else "cli_local"
   255 |         return {**base, "kind": "size", "failure_class": "context_limit", "size_origin": origin, "detail": diag,
   256 |                 "rejected_input_tokens": ceiling.parse_context_limit(diag).get("input_tokens")}
   257 |     if ceiling.is_token_limit_message(diag):
   258 |         # a token-budget 429: retried as transient; persisting at this size it is a size rejection
   259 |         return {**base, "kind": "transient", "token_limit": True, "detail": diag}
   260 |     try:
   261 |         cha.ClaudeHeadlessAdapter._raise_for_error(__import__("types").SimpleNamespace(provider="claude-headless"),
   262 |                                                    returncode=rc, stderr=stderr, parsed=parsed)
   263 |     except t.RateLimitError:
   264 |         return {**base, "kind": "transient", "detail": diag}
   265 |     except t.ProviderUnavailableError:
>  266 |         low = diag.lower()
>  267 |         if any(m in low for m in _TRANSIENT_MARKERS) or _STATUS_5XX.search(diag):
   268 |             return {**base, "kind": "transient", "detail": diag}
   269 |         return {**base, "kind": "other", "detail": diag}
   270 |     except Exception:  # noqa: BLE001 — auth / config classes: not transient, not size
   271 |         return {**base, "kind": "other", "detail": diag}
   272 |     return {**base, "kind": "other", "detail": diag}
   273 | 
   274 | 
   275 | _DEFAULT_CATALOG = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
   276 |                                 ".claude", "defaults", "model-config.yaml")
   277 | _TIERS = ("unverified", "1", "2", "3", "4", "custom")
   278 | 
   279 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -266,2 +445,2 @@
-        low = diag.lower()
-        if any(m in low for m in _TRANSIENT_MARKERS) or _STATUS_5XX.search(diag):
+        low = full.lower()
+        if any(m in low for m in _TRANSIENT_MARKERS) or _STATUS_5XX.search(full):
~~~~

## H208 — tools/ceiling-probe-live.py — head lines 403–404

Head context (head/tools/ceiling-probe-live.py, lines 391–416):

~~~~text
   391 |         if _indent(l) == 8 and ":" in l and not l.strip().startswith("#"):
   392 |             k, v = l.strip().split(":", 1)
   393 |             fields[k] = v.split("#", 1)[0].strip()
   394 |     cw = fields.get("context_window", "")
   395 |     if not cw.isdigit() or int(cw) <= 0:
   396 |         raise ValueError(f"{model}: no positive context_window in the entry — cannot apply the I2 clamp")
   397 |     mo = fields.get("max_output_tokens", "")
   398 |     default_out = _catalog_default_output(int(mo) if mo.isdigit() else None)
   399 |     return min(int(measured), int(cw) - default_out), int(cw), default_out
   400 | 
   401 | 
   402 | def write_catalog_operator_set(text: str, model: str, *, ceiling: int, calibrated_at: str, cli_model: str,
>  403 |                                host_route: str, cli_version: str | None = None,
>  404 |                                transport: str = "claude-headless") -> str:
   405 |     """cycle-127 FR-3.2 (SDD D-3.2, D-3.8): fold a CLI-transport bound into the
   406 |     catalog TEXT as `operator_set` — `probed_ceiling` and
   407 |     `effective_input_ceiling` (a calibrated entry is bounded by the latter,
   408 |     routing/ceiling.input_bound) = min(`ceiling` — the measured accepted size,
   409 |     no margin, as the api transport — , context_window − default max_tokens)
   410 |     (the I2 clamp, i2_clamped; a value below the old bound is written, never
   411 |     max()-ed); `measured_input_tokens` keeps the raw measurement; `ceiling_calibration {source, method: probed_headless,
   412 |     transport, cli_version, cli_model, measured_input_tokens, calibrated_at,
   413 |     sample_size: null, stale_after_days (kept, else 90), reprobe_trigger}`;
   414 |     the entry's `loa:shortcut` ceiling comment becomes one provenance comment.
   415 |     Line-level, inside the model's block only; ValueError when a field is missing."""
   416 |     lines = text.split("\n")
~~~~

The change from head to the fix:

~~~~diff
@@ -403,2 +582,3 @@
-                               host_route: str, cli_version: str | None = None,
-                               transport: str = "claude-headless") -> str:
+                               host_route: str, probe_outcome: str, sample_size: int,
+                               cli_version: str | None = None, transport: str = "claude-headless",
+                               force_partial: bool = False) -> str:
~~~~

## H209 — tools/ceiling-probe-live.py — head lines 413–415

Head context (head/tools/ceiling-probe-live.py, lines 401–427):

~~~~text
   401 | 
   402 | def write_catalog_operator_set(text: str, model: str, *, ceiling: int, calibrated_at: str, cli_model: str,
   403 |                                host_route: str, cli_version: str | None = None,
   404 |                                transport: str = "claude-headless") -> str:
   405 |     """cycle-127 FR-3.2 (SDD D-3.2, D-3.8): fold a CLI-transport bound into the
   406 |     catalog TEXT as `operator_set` — `probed_ceiling` and
   407 |     `effective_input_ceiling` (a calibrated entry is bounded by the latter,
   408 |     routing/ceiling.input_bound) = min(`ceiling` — the measured accepted size,
   409 |     no margin, as the api transport — , context_window − default max_tokens)
   410 |     (the I2 clamp, i2_clamped; a value below the old bound is written, never
   411 |     max()-ed); `measured_input_tokens` keeps the raw measurement; `ceiling_calibration {source, method: probed_headless,
   412 |     transport, cli_version, cli_model, measured_input_tokens, calibrated_at,
>  413 |     sample_size: null, stale_after_days (kept, else 90), reprobe_trigger}`;
>  414 |     the entry's `loa:shortcut` ceiling comment becomes one provenance comment.
>  415 |     Line-level, inside the model's block only; ValueError when a field is missing."""
   416 |     lines = text.split("\n")
   417 |     start = next((i for i, l in enumerate(lines) if l.rstrip() == f"      {model}:"), None)
   418 |     if start is None:
   419 |         raise ValueError(f"{model}: no `      {model}:` block in the catalog")
   420 |     if isinstance(ceiling, bool) or not isinstance(ceiling, int) or ceiling <= 0:
   421 |         raise ValueError(f"{model}: ceiling must be a positive integer, got {ceiling!r}")
   422 |     end = start + 1
   423 |     while end < len(lines) and (lines[end].strip() == "" or _indent(lines[end]) > 6):
   424 |         end += 1
   425 |     block = lines[start:end]
   426 | 
   427 |     def _find(prefix: str, indent: int, lo: int = 0, hi: int | None = None) -> int:
~~~~

The change from head to the fix:

~~~~diff
@@ -413,3 +593,21 @@
-    sample_size: null, stale_after_days (kept, else 90), reprobe_trigger}`;
+    sample_size, probe_outcome, stale_after_days (kept, else 90), reprobe_trigger}`;
     the entry's `loa:shortcut` ceiling comment becomes one provenance comment.
-    Line-level, inside the model's block only; ValueError when a field is missing."""
+    Line-level, inside the model's block only; ValueError when a field is missing.
+
+    r251-1 P12: `probe_outcome` (clean | partial) and `sample_size` (the record's
+    sample count, accepted + rejected) are REQUIRED — no caller can claim a clean
+    probe by default. A `partial` record is refused unless `force_partial=True`
+    (--write-partial-as-operator-set: the operator vouches for the last verified
+    accept, and the entry says `probe_outcome: partial`)."""
+    if probe_outcome not in ("clean", "partial"):
+        raise ValueError(f"{model}: probe_outcome must be 'clean' or 'partial', got {probe_outcome!r}")
+    if probe_outcome == "partial" and not force_partial:
+        raise ValueError(f"{model}: a partial probe record is not written as operator_set without "
+                         f"force_partial=True (--write-partial-as-operator-set)")
+    if isinstance(sample_size, bool) or not isinstance(sample_size, int) or sample_size < 0:
+        raise ValueError(f"{model}: sample_size must be a non-negative integer, got {sample_size!r}")
+    for field, value in (("host_route", host_route), ("cli_model", cli_model), ("cli_version", cli_version),
+                         ("transport", transport)):
+        why = _unsafe_field(value)
+        if why or (field in ("host_route", "cli_model", "transport") and not value):
+            raise ValueError(f"{model}: {field} {why or 'is empty'} — refused before it reaches the catalog text")
~~~~

## H210 — tools/ceiling-probe-live.py — head lines 456–460

Head context (head/tools/ceiling-probe-live.py, lines 444–472):

~~~~text
   444 |     _set_scalar(_find("probed_ceiling:", 8), "probed_ceiling", str(written))
   445 |     h = _find("ceiling_calibration:", 8)
   446 |     j = h + 1
   447 |     while j < len(block) and (block[j].strip() == "" or _indent(block[j]) > 8):
   448 |         j += 1
   449 |     stale = 90
   450 |     try:
   451 |         raw = block[_find("stale_after_days:", 10, h + 1, j)].split(":", 1)[1].split("#", 1)[0].strip()
   452 |         stale = int(raw) if raw.isdigit() and int(raw) > 0 else 90
   453 |     except ValueError:
   454 |         pass
   455 |     new_cal = ["        ceiling_calibration:", "          source: operator_set",
>  456 |                f'          calibrated_at: "{calibrated_at}"', "          sample_size: null",
>  457 |                f"          stale_after_days: {stale}", f"          reprobe_trigger: {json.dumps(trigger)}",
>  458 |                "          method: probed_headless", f"          transport: {transport}",
>  459 |                f"          cli_version: {json.dumps(cli_version) if cli_version else 'null'}",
>  460 |                f"          cli_model: {json.dumps(cli_model)}", f"          measured_input_tokens: {measured}"]
   461 |     block[h:j] = new_cal
   462 |     # the shortcut marker: a `# loa:shortcut:` comment line plus its comment continuation lines
   463 |     k = next((i for i, l in enumerate(block) if _indent(l) == 8 and l.strip().startswith("# loa:shortcut:")
   464 |               and "ceiling-probe-live" in " ".join(block[i:i + 3])), None)
   465 |     clamp_note = (f"; written clamped to {written} (I2: context_window {cw} − default max_tokens {default_out}) "
   466 |                   f"from the measured {measured}") if written < measured else ""
   467 |     provenance = (f"        # cycle-127 FR-3: bound measured {day} by tools/ceiling-probe-live.py --transport "
   468 |                   f"claude-headless ({route}, {cli_model}){clamp_note}; see ceiling_calibration.reprobe_trigger.")
   469 |     old_prov = next((i for i, l in enumerate(block) if l.startswith("        # cycle-127 FR-3: bound measured ")), None)
   470 |     if k is not None:
   471 |         e = k + 1
   472 |         while e < len(block) and _indent(block[e]) == 8 and block[e].strip().startswith("#") \
~~~~

The change from head to the fix:

~~~~diff
@@ -456,5 +654,6 @@
-               f'          calibrated_at: "{calibrated_at}"', "          sample_size: null",
+               f'          calibrated_at: "{calibrated_at}"', f"          sample_size: {sample_size}",
                f"          stale_after_days: {stale}", f"          reprobe_trigger: {json.dumps(trigger)}",
                "          method: probed_headless", f"          transport: {transport}",
                f"          cli_version: {json.dumps(cli_version) if cli_version else 'null'}",
-               f"          cli_model: {json.dumps(cli_model)}", f"          measured_input_tokens: {measured}"]
+               f"          cli_model: {json.dumps(cli_model)}", f"          measured_input_tokens: {measured}",
+               f"          probe_outcome: {probe_outcome}"]
~~~~

## H211 — tools/ceiling-probe-live.py — head lines 467–468

Head context (head/tools/ceiling-probe-live.py, lines 455–480):

~~~~text
   455 |     new_cal = ["        ceiling_calibration:", "          source: operator_set",
   456 |                f'          calibrated_at: "{calibrated_at}"', "          sample_size: null",
   457 |                f"          stale_after_days: {stale}", f"          reprobe_trigger: {json.dumps(trigger)}",
   458 |                "          method: probed_headless", f"          transport: {transport}",
   459 |                f"          cli_version: {json.dumps(cli_version) if cli_version else 'null'}",
   460 |                f"          cli_model: {json.dumps(cli_model)}", f"          measured_input_tokens: {measured}"]
   461 |     block[h:j] = new_cal
   462 |     # the shortcut marker: a `# loa:shortcut:` comment line plus its comment continuation lines
   463 |     k = next((i for i, l in enumerate(block) if _indent(l) == 8 and l.strip().startswith("# loa:shortcut:")
   464 |               and "ceiling-probe-live" in " ".join(block[i:i + 3])), None)
   465 |     clamp_note = (f"; written clamped to {written} (I2: context_window {cw} − default max_tokens {default_out}) "
   466 |                   f"from the measured {measured}") if written < measured else ""
>  467 |     provenance = (f"        # cycle-127 FR-3: bound measured {day} by tools/ceiling-probe-live.py --transport "
>  468 |                   f"claude-headless ({route}, {cli_model}){clamp_note}; see ceiling_calibration.reprobe_trigger.")
   469 |     old_prov = next((i for i, l in enumerate(block) if l.startswith("        # cycle-127 FR-3: bound measured ")), None)
   470 |     if k is not None:
   471 |         e = k + 1
   472 |         while e < len(block) and _indent(block[e]) == 8 and block[e].strip().startswith("#") \
   473 |                 and not block[e].strip().startswith("# loa:"):
   474 |             e += 1
   475 |         block[k:e] = [provenance]
   476 |     elif old_prov is not None:
   477 |         block[old_prov] = provenance
   478 |     else:
   479 |         block.insert(_find("probed_ceiling:", 8), provenance)
   480 |     return "\n".join(lines[:start] + block + lines[end:])
~~~~

The change from head to the fix:

~~~~diff
@@ -467,2 +666,4 @@
-    provenance = (f"        # cycle-127 FR-3: bound measured {day} by tools/ceiling-probe-live.py --transport "
-                  f"claude-headless ({route}, {cli_model}){clamp_note}; see ceiling_calibration.reprobe_trigger.")
+    partial_note = ("; probe outcome partial — the operator vouches for the last verified accept"
+                    if probe_outcome == "partial" else "")
+    provenance = _PROVENANCE.format(day=day, route=route, cli_model=cli_model, clamp_note=clamp_note,
+                                    partial_note=partial_note)
~~~~

## H212 — tools/ceiling-probe-live.py — head line 480

Head context (head/tools/ceiling-probe-live.py, lines 468–492):

~~~~text
   468 |                   f"claude-headless ({route}, {cli_model}){clamp_note}; see ceiling_calibration.reprobe_trigger.")
   469 |     old_prov = next((i for i, l in enumerate(block) if l.startswith("        # cycle-127 FR-3: bound measured ")), None)
   470 |     if k is not None:
   471 |         e = k + 1
   472 |         while e < len(block) and _indent(block[e]) == 8 and block[e].strip().startswith("#") \
   473 |                 and not block[e].strip().startswith("# loa:"):
   474 |             e += 1
   475 |         block[k:e] = [provenance]
   476 |     elif old_prov is not None:
   477 |         block[old_prov] = provenance
   478 |     else:
   479 |         block.insert(_find("probed_ceiling:", 8), provenance)
>  480 |     return "\n".join(lines[:start] + block + lines[end:])
   481 | 
   482 | 
   483 | def _write_text_atomic(path: str, new: str) -> None:
   484 |     fd, tmp = tempfile.mkstemp(prefix=".model-config.", suffix=".tmp", dir=os.path.dirname(os.path.abspath(path)))
   485 |     with os.fdopen(fd, "w", encoding="utf-8") as fh:
   486 |         fh.write(new)
   487 |     os.replace(tmp, path)
   488 | 
   489 | 
   490 | def main() -> int:
   491 |     ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
   492 |     ap.add_argument("--model", required=True)
~~~~

The change from head to the fix:

~~~~diff
@@ -480 +681,60 @@
-    return "\n".join(lines[:start] + block + lines[end:])
+    new = "\n".join(lines[:start] + block + lines[end:])
+    _verify_operator_set(text, new, model, written=written, measured=measured, probe_outcome=probe_outcome)
+    return new
+
+
+# The one provenance comment line of an operator_set write (a template so a test can
+# prove the re-parse below catches a defect in it).
+_PROVENANCE = ("        # cycle-127 FR-3: bound measured {day} by tools/ceiling-probe-live.py --transport "
+               "claude-headless ({route}, {cli_model}){clamp_note}{partial_note}; "
+               "see ceiling_calibration.reprobe_trigger.")
+_WRITTEN_KEYS = ("probed_ceiling", "effective_input_ceiling", "ceiling_calibration")
+
+
+def _verify_operator_set(before: str, after: str, model: str, *, written: int, measured: int,
+                         probe_outcome: str) -> None:
+    """r251-4 T1 (n52 c): re-parse the produced catalog text before it is returned (and
+    so before any write): the entry's ceilings are `written`, its calibration says
+    operator_set / probed_headless / `probe_outcome` / `measured`, and nothing outside
+    the three written keys of this one entry changed. ValueError otherwise."""
+    import yaml
+
+    def fail(why: str):
+        raise ValueError(f"{model}: re-parse of the written catalog failed — {why}; nothing written")
+
+    try:
+        b, a = yaml.safe_load(before), yaml.safe_load(after)
+    except yaml.YAMLError as e:
+        fail(f"not YAML: {str(e).splitlines()[0] if str(e) else type(e).__name__}")
+
+    def entries(doc):
+        provs = doc.get("providers") if isinstance(doc, dict) else None
+        return [(p, (pv.get("models") or {})) for p, pv in (provs or {}).items() if isinstance(pv, dict)]
+
+    hits = [(p, ms[model]) for p, ms in entries(a) if isinstance(ms, dict) and isinstance(ms.get(model), dict)]
+    if len(hits) != 1:
+        fail(f"{len(hits)} `{model}` entries after the edit")
+    entry = hits[0][1]
+    cal = entry.get("ceiling_calibration")
+    for key in ("probed_ceiling", "effective_input_ceiling"):
+        if entry.get(key) != written or isinstance(entry.get(key), bool):
+            fail(f"{key} loads as {entry.get(key)!r}, expected {written}")
+    if not isinstance(cal, dict):
+        fail("ceiling_calibration is not a mapping")
+    want = {"source": "operator_set", "method": "probed_headless", "probe_outcome": probe_outcome,
+            "measured_input_tokens": measured}
+    for key, value in want.items():
+        if cal.get(key) != value:
+            fail(f"ceiling_calibration.{key} loads as {cal.get(key)!r}, expected {value!r}")
+
+    def strip(doc):
+        import copy
+        doc = copy.deepcopy(doc)
+        for _, ms in entries(doc):
+            if isinstance(ms, dict) and isinstance(ms.get(model), dict):
+                for key in _WRITTEN_KEYS:
+                    ms[model].pop(key, None)
+        return doc
+
+    if strip(a) != strip(b):
+        fail("a key outside the entry's probed_ceiling / effective_input_ceiling / ceiling_calibration changed")
~~~~

## H213 — tools/ceiling-probe-live.py — head lines 501–503

Head context (head/tools/ceiling-probe-live.py, lines 489–515):

~~~~text
   489 | 
   490 | def main() -> int:
   491 |     ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
   492 |     ap.add_argument("--model", required=True)
   493 |     ap.add_argument("--max-tokens-probe", type=int, default=200_000)
   494 |     ap.add_argument("--min-tokens-probe", type=int, default=32_000)
   495 |     ap.add_argument("--budget-usd", type=float, default=1.5)
   496 |     ap.add_argument("--output", default="-")
   497 |     # cycle-126 FR-1.1 (SDD D-1.1): one operator run sets calibrated_at, the
   498 |     # calibrated value and account_limits in the catalog (refused on a partial
   499 |     # bisection unless --allow-partial says the operator accepts it).
   500 |     ap.add_argument("--write-catalog", nargs="?", const=_DEFAULT_CATALOG, default=None, metavar="PATH")
>  501 |     ap.add_argument("--tier", default="unverified", choices=_TIERS)
>  502 |     ap.add_argument("--itpm", type=int, default=None)
>  503 |     ap.add_argument("--allow-partial", action="store_true")
   504 |     # cycle-127 FR-3 (SDD D-3.1): the headless-CLI transport (default api, unchanged).
   505 |     ap.add_argument("--transport", choices=("api", "claude-headless"), default="api")
   506 |     ap.add_argument("--cli-model", default=None, help="model passed to the CLI (default: --model)")
   507 |     ap.add_argument("--host-route", default=None, help="free-text route note for the record")
   508 |     ap.add_argument("--tolerance-tokens", type=int, default=16_000,
   509 |                     help="claude-headless: stop when the accept/reject bracket is this narrow (default 16000)")
   510 |     args = ap.parse_args()
   511 | 
   512 |     if args.transport == "claude-headless":
   513 |         return _main_cli(args)
   514 | 
   515 |     key = os.environ.get("ANTHROPIC_API_KEY")
~~~~

The change from head to the fix:

~~~~diff
@@ -501,3 +761,9 @@
-    ap.add_argument("--tier", default="unverified", choices=_TIERS)
+    ap.add_argument("--tier", default=None, choices=_TIERS, help="api transport (default unverified)")
     ap.add_argument("--itpm", type=int, default=None)
-    ap.add_argument("--allow-partial", action="store_true")
+    ap.add_argument("--allow-partial", action="store_true",
+                    help="api transport: write a budget-capped partial bisection to the catalog "
+                         "(a usage error with --transport claude-headless: see --write-partial-as-operator-set)")
+    ap.add_argument("--write-partial-as-operator-set", action="store_true",
+                    help="claude-headless, with --write-catalog: write a PARTIAL record anyway — the operator "
+                         "vouches for the last verified accept; the entry carries probe_outcome: partial "
+                         "(the exit code still reports the partial probe)")
~~~~

## H214 — tools/ceiling-probe-live.py — head line 513

Head context (head/tools/ceiling-probe-live.py, lines 501–525):

~~~~text
   501 |     ap.add_argument("--tier", default="unverified", choices=_TIERS)
   502 |     ap.add_argument("--itpm", type=int, default=None)
   503 |     ap.add_argument("--allow-partial", action="store_true")
   504 |     # cycle-127 FR-3 (SDD D-3.1): the headless-CLI transport (default api, unchanged).
   505 |     ap.add_argument("--transport", choices=("api", "claude-headless"), default="api")
   506 |     ap.add_argument("--cli-model", default=None, help="model passed to the CLI (default: --model)")
   507 |     ap.add_argument("--host-route", default=None, help="free-text route note for the record")
   508 |     ap.add_argument("--tolerance-tokens", type=int, default=16_000,
   509 |                     help="claude-headless: stop when the accept/reject bracket is this narrow (default 16000)")
   510 |     args = ap.parse_args()
   511 | 
   512 |     if args.transport == "claude-headless":
>  513 |         return _main_cli(args)
   514 | 
   515 |     key = os.environ.get("ANTHROPIC_API_KEY")
   516 |     if not key:
   517 |         print("ceiling-probe-live: ANTHROPIC_API_KEY is required", file=sys.stderr)
   518 |         return 2
   519 |     if args.min_tokens_probe >= args.max_tokens_probe:
   520 |         print("ceiling-probe-live: --min-tokens-probe must be below --max-tokens-probe", file=sys.stderr)
   521 |         return 2
   522 | 
   523 |     price_in = _PRICE_IN.get(args.model, 10_000_000)
   524 |     spent_micro = 0
   525 |     lo, hi = args.min_tokens_probe, args.max_tokens_probe
~~~~

The change from head to the fix:

~~~~diff
@@ -513 +779,14 @@
+        # verifier r251-1: the api-only flags are refused, never silently ignored
+        for flag, used in (("--allow-partial", args.allow_partial), ("--tier", args.tier is not None),
+                           ("--itpm", args.itpm is not None)):
+            if used:
+                print(f"ceiling-probe-live: {flag} is an api-transport flag — --transport claude-headless does not "
+                      f"read it (a partial record is written only with --write-partial-as-operator-set; "
+                      f"account_limits are left alone); no call made", file=sys.stderr)
+                return 2
         return _main_cli(args)
+    if args.write_partial_as_operator_set:
+        print("ceiling-probe-live: --write-partial-as-operator-set applies to --transport claude-headless only",
+              file=sys.stderr)
+        return 2
+    args.tier = args.tier or "unverified"
~~~~

## H215 — tools/ceiling-probe-live.py — insertion after head line 618

Head context (head/tools/ceiling-probe-live.py, lines 607–630):

~~~~text
   607 |     above a rejection."""
   608 |     reasons: list[str] = []
   609 |     if stop == "budget":
   610 |         reasons.append("budget cap stopped the bisection")
   611 |     if stop == "other" or any(s.get("kind") == "other" for s in samples):
   612 |         reasons.append("an attempt failed for a non-size reason (other)")
   613 |     if stop == "unverified" or any(s.get("kind") == "unverified" for s in samples):
   614 |         reasons.append("a completed response did not echo the needle (unverified)")
   615 |     oks = [s.get("size_measured", s["tokens"]) for s in samples if s.get("kind") == "ok"]
   616 |     fails = [s.get("size_measured", s["tokens"]) for s in samples if s.get("kind") == "size"]
   617 |     if oks and fails and max(oks) > min(fails):
   618 |         reasons.append("inconsistent: an accept above a size rejection")
   619 |     if reasons:
   620 |         return reasons
   621 |     if largest_ok <= 0:
   622 |         reasons.append("no accepted size in the probed range")
   623 |     elif smallest_fail is None or (largest_ok >= hi - tol and smallest_fail - largest_ok > tol):
   624 |         reasons.append(f"no size rejection up to {hi} tokens — the bound is not bracketed")
   625 |     elif smallest_fail - largest_ok > tol:
   626 |         reasons.append("the accept/reject bracket is wider than --tolerance-tokens")
   627 |     elif not measured:
   628 |         reasons.append("the accepted step reported no usage — nothing measured")
   629 |     return reasons
   630 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -618,0 +898,7 @@
+    elif fails:
+        bracket = min((s for s in samples if s.get("kind") == "size"), key=lambda s: s.get("size_measured", s["tokens"]))
+        fc = bracket.get("failure_class")
+        if fc != "context_limit":
+            # verifier r251-1: a token-budget / throttle rejection bounds the account's rate, not the window
+            reasons.append(f"the bracketing rejection is {fc or 'unclassified'}, not context_limit — "
+                           f"a throttle or token budget, not the context window")
~~~~

## H216 — tools/ceiling-probe-live.py — insertion after head line 631

Head context (head/tools/ceiling-probe-live.py, lines 620–643):

~~~~text
   620 |         return reasons
   621 |     if largest_ok <= 0:
   622 |         reasons.append("no accepted size in the probed range")
   623 |     elif smallest_fail is None or (largest_ok >= hi - tol and smallest_fail - largest_ok > tol):
   624 |         reasons.append(f"no size rejection up to {hi} tokens — the bound is not bracketed")
   625 |     elif smallest_fail - largest_ok > tol:
   626 |         reasons.append("the accept/reject bracket is wider than --tolerance-tokens")
   627 |     elif not measured:
   628 |         reasons.append("the accepted step reported no usage — nothing measured")
   629 |     return reasons
   630 | 
   631 | 
   632 | def _main_cli(args) -> int:
   633 |     """The bisection, through the headless CLI (cycle-127 FR-3.1, D-3.5…D-3.9)."""
   634 |     import secrets
   635 | 
   636 |     if args.min_tokens_probe >= args.max_tokens_probe or args.tolerance_tokens <= 0:
   637 |         print("ceiling-probe-live: need --min-tokens-probe < --max-tokens-probe and --tolerance-tokens > 0",
   638 |               file=sys.stderr)
   639 |         return 2
   640 |     started_at = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
   641 |     cli_bin = _cli_bin()
   642 |     cli_arg = args.cli_model or args.model
   643 |     host_route = args.host_route or _default_host_route(cli_bin)
~~~~

The change from head to the fix:

~~~~diff
@@ -631,0 +918,56 @@
+def _charge(res: dict, *, est_micro: int, price_in: int) -> tuple[int, str]:
+    """(micro-USD, basis) one attempt is charged (r251-1 P1; the table in the module docstring)."""
+    measured = res.get("measured_input_tokens")
+    reported = res.get("cli_reported_cost_usd")
+    rep = int(reported * 1_000_000) if isinstance(reported, (int, float)) and not isinstance(reported, bool) \
+        and 0 < reported < _MAX_COST_USD else 0     # a range test: NaN / ±inf / a huge int all fail it
+    if res.get("not_sent"):
+        return 0, "not_sent"
+    if res.get("timed_out"):
+        return est_micro, "timeout_estimate"
+    if res.get("classifier_error"):
+        return est_micro, "classifier_error_estimate"
+    if res.get("output_cap"):
+        return est_micro, "output_cap_estimate"
+    usage_micro = measured * price_in // 1_000_000 if measured else None
+    if res["kind"] in ("ok", "unverified"):
+        return max(usage_micro if usage_micro is not None else est_micro, rep), "completion"
+    if res["kind"] == "size" and res.get("size_origin") == "cli_local":
+        return 0, "cli_local_rejection"
+    if usage_micro is not None:
+        return max(usage_micro, rep), "usage_reported"
+    if rep:
+        return rep, "cli_reported"
+    return 0, ("provider_rejection_unbilled" if res["kind"] in ("size", "transient") else "failed_unbilled")
+
+
+def _retry_wait(res: dict, attempt: int, waited: float) -> float:
+    """Seconds to sleep before attempt `attempt + 1` (0 ⇒ the retry budget is spent)."""
+    schedule = _TPM_BACKOFF_S if res.get("token_limit") else _BACKOFF_S
+    wait = float(schedule[min(attempt - 1, len(schedule) - 1)])
+    hint = res.get("retry_after_s")
+    if isinstance(hint, (int, float)) and hint > wait:
+        wait = float(hint)
+    return max(0.0, min(wait, _RETRY_WAIT_CAP_S - waited))
+
+
+def _persisted_transient(res: dict, *, attempt_kinds: list[str], waited: float) -> dict:
+    """The final classification of a step whose transient class outlived its
+    retries (r251-1 P3): a token-budget 429 on EVERY attempt, once the 60 s
+    window was waited out, says this size does not fit the budget — a size
+    rejection (`token_limit`), and the bisection continues downward; anything
+    else is `other`."""
+    out = {k: v for k, v in res.items() if k not in ("token_limit", "retry_after_s")}
+    n = len(attempt_kinds)
+    if res.get("token_limit") and attempt_kinds and all(k == "token_limit" for k in attempt_kinds):
+        if waited >= _TPM_WINDOW_S:
+            out.update(kind="size", failure_class="token_limit", size_origin="provider")
+            return out
+        out.update(kind="other", detail=(f"token-limit 429 persisted over {n} attempts but only {waited:g}s were "
+                                         f"waited — the {_TPM_WINDOW_S}s tokens-per-minute window was not cleared: "
+                                         f"{res.get('detail', '')}")[:_DETAIL_CHARS * 2])
+        return out
+    out.update(kind="other", detail=f"transient class persisted over {n} attempts: {res.get('detail', '')}")
+    return out
+
+
~~~~

## H217 — tools/ceiling-probe-live.py — insertion after head line 639

Head context (head/tools/ceiling-probe-live.py, lines 628–651):

~~~~text
   628 |         reasons.append("the accepted step reported no usage — nothing measured")
   629 |     return reasons
   630 | 
   631 | 
   632 | def _main_cli(args) -> int:
   633 |     """The bisection, through the headless CLI (cycle-127 FR-3.1, D-3.5…D-3.9)."""
   634 |     import secrets
   635 | 
   636 |     if args.min_tokens_probe >= args.max_tokens_probe or args.tolerance_tokens <= 0:
   637 |         print("ceiling-probe-live: need --min-tokens-probe < --max-tokens-probe and --tolerance-tokens > 0",
   638 |               file=sys.stderr)
   639 |         return 2
   640 |     started_at = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
   641 |     cli_bin = _cli_bin()
   642 |     cli_arg = args.cli_model or args.model
   643 |     host_route = args.host_route or _default_host_route(cli_bin)
   644 |     argv = _cli_command(cli_bin, cli_arg)
   645 |     price_in = _PRICE_IN.get(args.model, 10_000_000)
   646 |     lo, hi, tol = args.min_tokens_probe, args.max_tokens_probe, args.tolerance_tokens
   647 |     budget_micro = int(args.budget_usd * 1_000_000)
   648 |     worst_micro = hi * price_in // 1_000_000
   649 |     print(f"ceiling-probe-live: worst-case step ≈ ${worst_micro / 1e6:.2f} at the catalog price "
   650 |           f"(${price_in / 1e6:.2f}/MTok × {hi} tokens); {budget_micro // worst_micro if worst_micro else 0} "
   651 |           f"such steps fit in ${args.budget_usd:g} (spend is cumulative over every attempt and retry)",
~~~~

The change from head to the fix:

~~~~diff
@@ -639,0 +982,3 @@
+    if args.write_partial_as_operator_set and not args.write_catalog:
+        print("ceiling-probe-live: --write-partial-as-operator-set needs --write-catalog", file=sys.stderr)
+        return 2
~~~~

## H218 — tools/ceiling-probe-live.py — head lines 644–653

Head context (head/tools/ceiling-probe-live.py, lines 632–665):

~~~~text
   632 | def _main_cli(args) -> int:
   633 |     """The bisection, through the headless CLI (cycle-127 FR-3.1, D-3.5…D-3.9)."""
   634 |     import secrets
   635 | 
   636 |     if args.min_tokens_probe >= args.max_tokens_probe or args.tolerance_tokens <= 0:
   637 |         print("ceiling-probe-live: need --min-tokens-probe < --max-tokens-probe and --tolerance-tokens > 0",
   638 |               file=sys.stderr)
   639 |         return 2
   640 |     started_at = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
   641 |     cli_bin = _cli_bin()
   642 |     cli_arg = args.cli_model or args.model
   643 |     host_route = args.host_route or _default_host_route(cli_bin)
>  644 |     argv = _cli_command(cli_bin, cli_arg)
>  645 |     price_in = _PRICE_IN.get(args.model, 10_000_000)
>  646 |     lo, hi, tol = args.min_tokens_probe, args.max_tokens_probe, args.tolerance_tokens
>  647 |     budget_micro = int(args.budget_usd * 1_000_000)
>  648 |     worst_micro = hi * price_in // 1_000_000
>  649 |     print(f"ceiling-probe-live: worst-case step ≈ ${worst_micro / 1e6:.2f} at the catalog price "
>  650 |           f"(${price_in / 1e6:.2f}/MTok × {hi} tokens); {budget_micro // worst_micro if worst_micro else 0} "
>  651 |           f"such steps fit in ${args.budget_usd:g} (spend is cumulative over every attempt and retry)",
>  652 |           file=sys.stderr)
>  653 |     cli_version = _cli_version(cli_bin)
   654 | 
   655 |     # Sizes are MEASURED tokens (the CLI's usage, or the count a rejection states):
   656 |     # --max-tokens-probe / --min-tokens-probe / --tolerance-tokens mean measured
   657 |     # tokens, and the filler sent for a target is target / ratio, ratio being the
   658 |     # latest measured/filler (1.0 until a step measures something — the Opus 4.7+
   659 |     # tokenizer counts this filler ≈1.8× heavier than its 10-tokens-per-sentence).
   660 |     spent_micro = 0
   661 |     samples: list[dict] = []
   662 |     stop = None  # "budget" | "other" | "unverified"
   663 |     ratio: float | None = None
   664 | 
   665 |     def _m(sample: dict) -> int | None:
~~~~

The change from head to the fix:

~~~~diff
@@ -644,10 +989,56 @@
+    cli_model = _resolved_cli_model(cli_arg)
+    # `--version` costs nothing; it runs first so the checks and the dry run below see
+    # the value the real write will carry (r251-4 T1 / n57)
+    cli_version = _cli_version(cli_bin)
+    # r251-4 T1 (n52): every value that reaches the catalog's provenance text is one short
+    # line — refused here, before the dry run and before any spend
+    alias_env = _CLI_ALIAS_ENV.get(cli_arg)
+    for flag, value in (("--host-route", host_route),
+                        (f"cli_model (resolved from {alias_env})" if alias_env and os.environ.get(alias_env)
+                         else "cli_model (--cli-model / --model)", cli_model),
+                        (f"cli_version (`{os.path.basename(cli_bin)} --version`)", cli_version)):
+        why = _unsafe_field(value)
+        if why:
+            print(f"ceiling-probe-live: {flag} {why} — no call made, nothing spent", file=sys.stderr)
+            return 2
+    if args.write_catalog:
+        # r251-1 P6: a write that cannot land must fail before any spend — dry-run
+        # the writer (block, positive context_window for the I2 clamp, fields) with
+        # the same resolved kwargs as the real write (r251-4 T1 / n57).
+        try:
+            with open(args.write_catalog, "r", encoding="utf-8") as fh:
+                write_catalog_operator_set(fh.read(), args.model, ceiling=1, calibrated_at=started_at,
+                                           cli_model=cli_model, host_route=host_route, cli_version=cli_version,
+                                           probe_outcome="clean", sample_size=0)
+            # r251-2 Q2: the atomic write needs the directory (mkstemp + replace) and an
+            # operator-writable file; a read-only catalog must fail here, not after spend
+            cat_dir = os.path.dirname(os.path.abspath(args.write_catalog))
+            for what, path in (("directory", cat_dir), ("file", args.write_catalog)):
+                if not os.access(path, os.W_OK):
+                    raise OSError(f"catalog {what} {path} is not writable")
+        except (OSError, ValueError) as e:
+            print(f"ceiling-probe-live: --write-catalog {args.write_catalog}: {e} — no call made, nothing spent",
+                  file=sys.stderr)
+            return 2
     argv = _cli_command(cli_bin, cli_arg)
-    price_in = _PRICE_IN.get(args.model, 10_000_000)
+    _adapters()
+    from loa_cheval.providers.base import SubprocessOutputCapExceeded
+    # The CLI writes the whole prompt to the prompt cache: the live record shows
+    # $4.99/MTok billed for 972,887 tokens on a $4 input price — 1.25×, the
+    # cache-write rate. Estimates (the pre-check, the worst-case line, the floor
+    # of an accepted step's charge) use it.
+    price_in = _PRICE_IN.get(args.model, 10_000_000) * 5 // 4
     lo, hi, tol = args.min_tokens_probe, args.max_tokens_probe, args.tolerance_tokens
     budget_micro = int(args.budget_usd * 1_000_000)
-    worst_micro = hi * price_in // 1_000_000
+    # r251-4 T3 (n58): the first step sends `hi` filler tokens blind, which the Opus 4.7+
+    # tokenizer measures ≈1.8× heavier — the estimate (only) assumes that ratio until a
+    # step measures one; the filler sent is unchanged
+    worst_micro = int(hi * _PRIOR_RATIO) * price_in // 1_000_000
     print(f"ceiling-probe-live: worst-case step ≈ ${worst_micro / 1e6:.2f} at the catalog price "
-          f"(${price_in / 1e6:.2f}/MTok × {hi} tokens); {budget_micro // worst_micro if worst_micro else 0} "
-          f"such steps fit in ${args.budget_usd:g} (spend is cumulative over every attempt and retry)",
-          file=sys.stderr)
-    cli_version = _cli_version(cli_bin)
+          f"(${price_in * 4 / 5 / 1e6:.2f}/MTok input × 1.25 cache-write rate = ${price_in / 1e6:.2f}/MTok, "
+          f"catalog estimate × {hi} filler tokens × {_PRIOR_RATIO:g}; the estimate assumes the Opus 4.7+ "
+          f"tokenizer ratio {_PRIOR_RATIO:g} until the first measured accept (or a rejection that states its "
+          f"count); Bedrock bills separately); "
+          f"{budget_micro // worst_micro if worst_micro else 0} such steps fit in ${args.budget_usd:g} (the cap "
+          f"is checked against this estimate before every attempt; a size rejection is charged $0 unless the "
+          f"CLI reports a cost)", file=sys.stderr)
~~~~

## H219 — tools/ceiling-probe-live.py — head lines 682–690

Head context (head/tools/ceiling-probe-live.py, lines 670–702):

~~~~text
   670 |         return (m, "usage" if sample.get("kind") == "ok" else "parsed") if m else \
   671 |             (int(sample["tokens"] * (ratio or 1.0)), "scaled")
   672 | 
   673 |     def current_ok() -> int | None:
   674 |         vals = [_size(x)[0] for x in samples if x.get("kind") == "ok"]
   675 |         return max(vals) if vals else None
   676 | 
   677 |     def current_fail() -> tuple[int | None, str | None]:
   678 |         vals = [_size(x) for x in samples if x.get("kind") == "size"]
   679 |         return min(vals) if vals else (None, None)
   680 | 
   681 |     def step(target: int) -> str:
>  682 |         """Probe one MEASURED target with up to _ATTEMPTS for transient classes. Returns the final kind."""
>  683 |         nonlocal spent_micro, ratio
>  684 |         tokens = max(1, int(target / (ratio or 1.0)))
>  685 |         sample = {"tokens": tokens, "target_measured": target, "ratio_at_send": ratio, "attempts": 0,
>  686 |                   "ok": False, "verified": False}
>  687 |         samples.append(sample)
>  688 |         est_measured = int(tokens * (ratio or 1.0))
>  689 |         for attempt in range(1, _ATTEMPTS + 1):
>  690 |             if spent_micro + est_measured * price_in // 1_000_000 > budget_micro:
   691 |                 if attempt == 1:
   692 |                     samples.pop()          # a step never attempted is not a sample
   693 |                     return "budget"
   694 |                 sample.update(kind="budget", detail="budget cap before a retry")
   695 |                 return "budget"
   696 |             if attempt > 1:
   697 |                 _SLEEP(_BACKOFF_S[min(attempt - 2, len(_BACKOFF_S) - 1)])
   698 |             needle = secrets.token_hex(6)
   699 |             prompt = _FILLER * (tokens // 10) + f"\n\nReply with exactly this code and nothing else: {needle}"
   700 |             print(f"ceiling-probe-live: target {target} measured tokens → filler {tokens} tokens (attempt {attempt}) "
   701 |                   f"via {os.path.basename(cli_bin)} ...", file=sys.stderr)
   702 |             try:
~~~~

The change from head to the fix:

~~~~diff
@@ -682,9 +1073,17 @@
-        """Probe one MEASURED target with up to _ATTEMPTS for transient classes. Returns the final kind."""
+        """Probe one MEASURED target, retrying transient classes. Returns the final kind."""
         nonlocal spent_micro, ratio
         tokens = max(1, int(target / (ratio or 1.0)))
         sample = {"tokens": tokens, "target_measured": target, "ratio_at_send": ratio, "attempts": 0,
-                  "ok": False, "verified": False}
+                  "ok": False, "verified": False, "charged_usd": 0.0, "charge_basis": None, "retry_wait_s": 0,
+                  "attempt_log": []}
         samples.append(sample)
-        est_measured = int(tokens * (ratio or 1.0))
-        for attempt in range(1, _ATTEMPTS + 1):
-            if spent_micro + est_measured * price_in // 1_000_000 > budget_micro:
+        est_measured = int(tokens * (ratio or _PRIOR_RATIO))
+        est_micro = est_measured * price_in // 1_000_000
+        charged_micro, waited, wait, kinds = 0, 0.0, 0.0, []
+        attempt = 0
+        while True:
+            attempt += 1
+            # The cap is checked against the ESTIMATE before every attempt — what an
+            # attempt will cost is unknown until it returns (a rejection is charged $0
+            # after the fact, an accept its usage); this is the cap's whole purpose.
+            if spent_micro + est_micro > budget_micro:
~~~~

## H220 — tools/ceiling-probe-live.py — head line 697

Head context (head/tools/ceiling-probe-live.py, lines 685–709):

~~~~text
   685 |         sample = {"tokens": tokens, "target_measured": target, "ratio_at_send": ratio, "attempts": 0,
   686 |                   "ok": False, "verified": False}
   687 |         samples.append(sample)
   688 |         est_measured = int(tokens * (ratio or 1.0))
   689 |         for attempt in range(1, _ATTEMPTS + 1):
   690 |             if spent_micro + est_measured * price_in // 1_000_000 > budget_micro:
   691 |                 if attempt == 1:
   692 |                     samples.pop()          # a step never attempted is not a sample
   693 |                     return "budget"
   694 |                 sample.update(kind="budget", detail="budget cap before a retry")
   695 |                 return "budget"
   696 |             if attempt > 1:
>  697 |                 _SLEEP(_BACKOFF_S[min(attempt - 2, len(_BACKOFF_S) - 1)])
   698 |             needle = secrets.token_hex(6)
   699 |             prompt = _FILLER * (tokens // 10) + f"\n\nReply with exactly this code and nothing else: {needle}"
   700 |             print(f"ceiling-probe-live: target {target} measured tokens → filler {tokens} tokens (attempt {attempt}) "
   701 |                   f"via {os.path.basename(cli_bin)} ...", file=sys.stderr)
   702 |             try:
   703 |                 rc, out, err = _run_capped(argv, prompt, _attempt_timeout(est_measured))
   704 |                 res = _classify(rc, out, err, needle)
   705 |             except subprocess.TimeoutExpired:
   706 |                 res = {"kind": "transient", "detail": f"no answer within {_attempt_timeout(est_measured)}s",
   707 |                        "measured_input_tokens": None, "cli_reported_cost_usd": None, "stop_reason": None}
   708 |             except OSError as e:
   709 |                 res = {"kind": "other", "detail": f"cannot run {cli_bin}: {e}",
~~~~

The change from head to the fix:

~~~~diff
@@ -697 +1096,2 @@
-                _SLEEP(_BACKOFF_S[min(attempt - 2, len(_BACKOFF_S) - 1)])
+                _SLEEP(wait)
+                waited += wait
~~~~

## H221 — tools/ceiling-probe-live.py — head lines 705–727

Head context (head/tools/ceiling-probe-live.py, lines 693–739):

~~~~text
   693 |                     return "budget"
   694 |                 sample.update(kind="budget", detail="budget cap before a retry")
   695 |                 return "budget"
   696 |             if attempt > 1:
   697 |                 _SLEEP(_BACKOFF_S[min(attempt - 2, len(_BACKOFF_S) - 1)])
   698 |             needle = secrets.token_hex(6)
   699 |             prompt = _FILLER * (tokens // 10) + f"\n\nReply with exactly this code and nothing else: {needle}"
   700 |             print(f"ceiling-probe-live: target {target} measured tokens → filler {tokens} tokens (attempt {attempt}) "
   701 |                   f"via {os.path.basename(cli_bin)} ...", file=sys.stderr)
   702 |             try:
   703 |                 rc, out, err = _run_capped(argv, prompt, _attempt_timeout(est_measured))
   704 |                 res = _classify(rc, out, err, needle)
>  705 |             except subprocess.TimeoutExpired:
>  706 |                 res = {"kind": "transient", "detail": f"no answer within {_attempt_timeout(est_measured)}s",
>  707 |                        "measured_input_tokens": None, "cli_reported_cost_usd": None, "stop_reason": None}
>  708 |             except OSError as e:
>  709 |                 res = {"kind": "other", "detail": f"cannot run {cli_bin}: {e}",
>  710 |                        "measured_input_tokens": None, "cli_reported_cost_usd": None, "stop_reason": None}
>  711 |             measured = res.get("measured_input_tokens")
>  712 |             est = (measured or est_measured) * price_in // 1_000_000
>  713 |             reported = res.get("cli_reported_cost_usd")
>  714 |             rep_micro = int(reported * 1_000_000) if isinstance(reported, (int, float)) and not isinstance(reported, bool) else 0
>  715 |             cost = max(est, rep_micro) if res["kind"] in ("ok", "unverified") or measured else est
>  716 |             spent_micro += cost
>  717 |             sample["attempts"] = attempt
>  718 |             sample["cost_usd"] = round(sample.get("cost_usd", 0) + cost / 1e6, 6)
>  719 |             sample.update({k: v for k, v in res.items() if k != "token_limit"})
>  720 |             if res["kind"] == "transient":
>  721 |                 if attempt < _ATTEMPTS:
>  722 |                     continue
>  723 |                 if res.get("token_limit"):
>  724 |                     sample.update(kind="size", failure_class="token_limit", size_origin="provider")
>  725 |                 else:
>  726 |                     sample["kind"] = "other"
>  727 |                     sample["detail"] = f"transient class persisted over {_ATTEMPTS} attempts: {res['detail']}"
   728 |             break
   729 |         if sample["kind"] == "ok":
   730 |             sample.update(ok=True, verified=True)
   731 |         m = _m(sample) or (sample.get("measured_input_tokens") if sample["kind"] == "unverified" else None)
   732 |         if m:
   733 |             ratio = m / tokens
   734 |         return sample["kind"]
   735 | 
   736 |     def next_target() -> int | None:
   737 |         first = samples[0]
   738 |         if first["ratio_at_send"] is None and _m(first) and abs(_m(first) - hi) > tol \
   739 |                 and not any(x["target_measured"] == hi for x in samples[1:]):
~~~~

The change from head to the fix:

~~~~diff
@@ -705,23 +1105,45 @@
+            except SubprocessOutputCapExceeded as e:
+                res = {"kind": "other", "output_cap": True,
+                       "detail": f"the CLI's output passed the 1 MB capture cap (process group killed): {e}"[:300],
+                       "measured_input_tokens": None, "cli_reported_cost_usd": None, "stop_reason": None}
             except subprocess.TimeoutExpired:
-                res = {"kind": "transient", "detail": f"no answer within {_attempt_timeout(est_measured)}s",
+                res = {"kind": "transient", "timed_out": True,
+                       "detail": f"no answer within {_attempt_timeout(est_measured)}s (process group killed)",
                        "measured_input_tokens": None, "cli_reported_cost_usd": None, "stop_reason": None}
             except OSError as e:
-                res = {"kind": "other", "detail": f"cannot run {cli_bin}: {e}",
+                res = {"kind": "other", "not_sent": True, "detail": f"cannot run {cli_bin}: {e}",
                        "measured_input_tokens": None, "cli_reported_cost_usd": None, "stop_reason": None}
-            measured = res.get("measured_input_tokens")
-            est = (measured or est_measured) * price_in // 1_000_000
-            reported = res.get("cli_reported_cost_usd")
-            rep_micro = int(reported * 1_000_000) if isinstance(reported, (int, float)) and not isinstance(reported, bool) else 0
-            cost = max(est, rep_micro) if res["kind"] in ("ok", "unverified") or measured else est
+            except BaseException as e:
+                # ^C or an unexpected defect mid-attempt: the request may have run — charge the
+                # estimate, mark the sample, and let the bisection's handler write the record
+                spent_micro += est_micro
+                charged_micro += est_micro
+                sample["attempt_log"].append({"attempt": attempt, "kind": "interrupted",
+                                              "wait_before_s": wait if attempt > 1 else 0,
+                                              "charged_usd": round(est_micro / 1e6, 6),
+                                              "charge_basis": "interrupted_estimate"})
+                sample.update(kind="interrupted", attempts=attempt, charged_usd=round(charged_micro / 1e6, 6),
+                              charge_basis="interrupted_estimate", retry_wait_s=waited,
+                              detail=f"{type(e).__name__}: {e}"[:300])
+                raise
+            cost, basis = _charge(res, est_micro=est_micro, price_in=price_in)
             spent_micro += cost
+            charged_micro += cost
+            kinds.append("token_limit" if res.get("token_limit") else res["kind"])
+            sample["attempt_log"].append({"attempt": attempt, "kind": kinds[-1], "wait_before_s": wait if attempt > 1 else 0,
+                                          "charged_usd": round(cost / 1e6, 6), "charge_basis": basis})
             sample["attempts"] = attempt
-            sample["cost_usd"] = round(sample.get("cost_usd", 0) + cost / 1e6, 6)
-            sample.update({k: v for k, v in res.items() if k != "token_limit"})
+            sample["charged_usd"] = round(charged_micro / 1e6, 6)
+            sample["charge_basis"] = basis
+            sample["retry_wait_s"] = waited
+            sample.update({k: v for k, v in res.items()
+                           if k not in ("token_limit", "retry_after_s", "timed_out", "not_sent", "classifier_error",
+                                        "output_cap")})
             if res["kind"] == "transient":
-                if attempt < _ATTEMPTS:
+                limit = _TPM_ATTEMPTS if res.get("token_limit") else _ATTEMPTS
+                wait = _retry_wait(res, attempt, waited) if attempt < limit else 0.0
+                if wait > 0:
                     continue
-                if res.get("token_limit"):
-                    sample.update(kind="size", failure_class="token_limit", size_origin="provider")
-                else:
-                    sample["kind"] = "other"
-                    sample["detail"] = f"transient class persisted over {_ATTEMPTS} attempts: {res['detail']}"
+                sample.update(_persisted_transient(res, attempt_kinds=kinds, waited=waited))
+                for k in ("timed_out", "not_sent", "classifier_error", "output_cap"):
+                    sample.pop(k, None)
~~~~

## H222 — tools/ceiling-probe-live.py — head lines 751–762

Head context (head/tools/ceiling-probe-live.py, lines 739–774):

~~~~text
   739 |                 and not any(x["target_measured"] == hi for x in samples[1:]):
   740 |             return hi          # the top was sent blind and missed: re-anchor it in measured tokens, once
   741 |         ok_m, (fail_m, _) = current_ok(), current_fail()
   742 |         if ok_m is not None and ok_m >= hi - tol:
   743 |             return None        # accepted at the top of the range
   744 |         if fail_m is None:
   745 |             return None
   746 |         lower = max(ok_m or 0, lo)
   747 |         if fail_m - lower <= tol:
   748 |             return None
   749 |         return (lower + fail_m) // 2
   750 | 
>  751 |     kind = step(hi)
>  752 |     if kind in ("budget", "other", "unverified"):
>  753 |         stop = kind
>  754 |     tried: set = set()
>  755 |     while stop is None and len(samples) < 40:
>  756 |         target = next_target()
>  757 |         if target is None or (target, int(target / (ratio or 1.0))) in tried:
>  758 |             break
>  759 |         tried.add((target, int(target / (ratio or 1.0))))
>  760 |         kind = step(target)
>  761 |         if kind in ("budget", "other", "unverified"):
>  762 |             stop = kind
   763 | 
   764 |     for x in samples:
   765 |         if x.get("kind") in ("ok", "size"):
   766 |             x["size_measured"], x["size_basis"] = _size(x)
   767 |     largest_ok = current_ok() or 0
   768 |     smallest_fail, fail_basis = current_fail()
   769 |     best = max((x for x in samples if x.get("kind") == "ok"), key=lambda x: x["size_measured"], default=None)
   770 |     largest_ok_measured = best.get("measured_input_tokens") if best else None
   771 |     reasons = _outcome_reasons(samples, stop=stop, largest_ok=largest_ok, measured=largest_ok_measured,
   772 |                                smallest_fail=smallest_fail, hi=hi, tol=tol)
   773 |     outcome = "partial" if reasons else "clean"
   774 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -751,12 +1173,19 @@
-    kind = step(hi)
-    if kind in ("budget", "other", "unverified"):
-        stop = kind
-    tried: set = set()
-    while stop is None and len(samples) < 40:
-        target = next_target()
-        if target is None or (target, int(target / (ratio or 1.0))) in tried:
-            break
-        tried.add((target, int(target / (ratio or 1.0))))
-        kind = step(target)
+    interrupted: BaseException | None = None
+    try:
+        kind = step(hi)
         if kind in ("budget", "other", "unverified"):
             stop = kind
+        tried: set = set()
+        while stop is None and len(samples) < 40:
+            target = next_target()
+            if target is None or (target, int(target / (ratio or 1.0))) in tried:
+                break
+            tried.add((target, int(target / (ratio or 1.0))))
+            kind = step(target)
+            if kind in ("budget", "other", "unverified"):
+                stop = kind
+    except BaseException as e:  # noqa: BLE001 — ^C / a defect after paid steps must not lose the record
+        stop, interrupted = "interrupted", e
+        if not isinstance(e, KeyboardInterrupt):
+            traceback.print_exc()           # r251-2 Q5: a defect keeps its traceback
+    interrupted_text = f"{type(interrupted).__name__}: {interrupted}" if interrupted is not None else None
~~~~

## H223 — tools/ceiling-probe-live.py — insertion after head line 772

Head context (head/tools/ceiling-probe-live.py, lines 761–784):

~~~~text
   761 |         if kind in ("budget", "other", "unverified"):
   762 |             stop = kind
   763 | 
   764 |     for x in samples:
   765 |         if x.get("kind") in ("ok", "size"):
   766 |             x["size_measured"], x["size_basis"] = _size(x)
   767 |     largest_ok = current_ok() or 0
   768 |     smallest_fail, fail_basis = current_fail()
   769 |     best = max((x for x in samples if x.get("kind") == "ok"), key=lambda x: x["size_measured"], default=None)
   770 |     largest_ok_measured = best.get("measured_input_tokens") if best else None
   771 |     reasons = _outcome_reasons(samples, stop=stop, largest_ok=largest_ok, measured=largest_ok_measured,
   772 |                                smallest_fail=smallest_fail, hi=hi, tol=tol)
   773 |     outcome = "partial" if reasons else "clean"
   774 | 
   775 |     record = {
   776 |         "model": args.model,
   777 |         "transport": "claude-headless",
   778 |         "source": "operator_set",
   779 |         "method": "probed_headless",
   780 |         "outcome": outcome,
   781 |         "reasons": reasons,
   782 |         "calibrated_at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
   783 |         "started_at": started_at,
   784 |         "sample_size": len(samples),
~~~~

The change from head to the fix:

~~~~diff
@@ -772,0 +1202,2 @@
+    if interrupted is not None:
+        reasons.insert(0, f"the bisection was interrupted ({interrupted_text})")
~~~~

## H224 — tools/ceiling-probe-live.py — head lines 799–802

Head context (head/tools/ceiling-probe-live.py, lines 787–814):

~~~~text
   787 |         "measured_input_tokens": largest_ok_measured,
   788 |         "smallest_failed_input_tokens": smallest_fail,
   789 |         "smallest_failed_basis": fail_basis,
   790 |         "tokenizer_ratio": round(ratio, 4) if ratio else None,
   791 |         "size_unit": "measured_tokens",
   792 |         "tolerance_tokens": tol,
   793 |         "bounds_tested": {"min": lo, "max": hi},
   794 |         "partial": outcome != "clean",
   795 |         "unverified": any(s.get("kind") == "unverified" for s in samples),
   796 |         "budget_usd": args.budget_usd,
   797 |         "spent_usd": round(spent_micro / 1_000_000, 4),
   798 |         "pricing_basis": "catalog_estimate",
>  799 |         "cli_bin": cli_bin,
>  800 |         "cli_version": cli_version,
>  801 |         "cli_model": _resolved_cli_model(cli_arg),
>  802 |         "argv": argv,
   803 |         "host_route": host_route,
   804 |         "route_env": _route_env(),
   805 |         "samples": samples,
   806 |     }
   807 |     errors = [s["detail"] for s in samples if s.get("kind") == "other"]
   808 |     if errors:
   809 |         record["error"] = errors[0]
   810 |     new_catalog = None
   811 |     if outcome == "clean" and args.write_catalog:
   812 |         try:
   813 |             with open(args.write_catalog, "r", encoding="utf-8") as fh:
   814 |                 current = fh.read()
~~~~

The change from head to the fix:

~~~~diff
@@ -799,4 +1230,8 @@
-        "cli_bin": cli_bin,
+        "estimate_rate": "input × 1.25 (cache-write rate)",
+        "estimate_usd_per_mtok": price_in / 1e6,
+        "stop": stop,
+        "interrupted": interrupted_text,
+        "cli_bin": _recorded_bin(cli_bin),
         "cli_version": cli_version,
-        "cli_model": _resolved_cli_model(cli_arg),
-        "argv": argv,
+        "cli_model": cli_model,
+        "argv": [_home_rel(argv[0]), *argv[1:]],
~~~~

## H225 — tools/ceiling-probe-live.py — head lines 811–821

Head context (head/tools/ceiling-probe-live.py, lines 799–833):

~~~~text
   799 |         "cli_bin": cli_bin,
   800 |         "cli_version": cli_version,
   801 |         "cli_model": _resolved_cli_model(cli_arg),
   802 |         "argv": argv,
   803 |         "host_route": host_route,
   804 |         "route_env": _route_env(),
   805 |         "samples": samples,
   806 |     }
   807 |     errors = [s["detail"] for s in samples if s.get("kind") == "other"]
   808 |     if errors:
   809 |         record["error"] = errors[0]
   810 |     new_catalog = None
>  811 |     if outcome == "clean" and args.write_catalog:
>  812 |         try:
>  813 |             with open(args.write_catalog, "r", encoding="utf-8") as fh:
>  814 |                 current = fh.read()
>  815 |             record["written_ceiling"] = i2_clamped(current, args.model, int(largest_ok_measured))[0]
>  816 |             new_catalog = write_catalog_operator_set(
>  817 |                 current, args.model, ceiling=int(largest_ok_measured), calibrated_at=record["calibrated_at"],
>  818 |                 cli_model=record["cli_model"], host_route=host_route, cli_version=cli_version)
>  819 |         except (OSError, ValueError) as e:
>  820 |             record["error"] = f"catalog not written: {e}"
>  821 |             errors.append(record["error"])
   822 |     text = json.dumps(record, indent=2)
   823 |     if args.output == "-":
   824 |         print(text)
   825 |     else:
   826 |         with open(args.output, "w") as fh:
   827 |             fh.write(text + "\n")
   828 |         print(f"ceiling-probe-live: wrote {args.output} (outcome={outcome}, measured={largest_ok_measured}, "
   829 |               f"spent≈${record['spent_usd']} catalog estimate)", file=sys.stderr)
   830 |     if outcome != "clean":
   831 |         print(f"ceiling-probe-live: partial ({'; '.join(reasons)}) — nothing written to the catalog", file=sys.stderr)
   832 |         return 1 if errors else 3
   833 |     if args.write_catalog:
~~~~

The change from head to the fix:

~~~~diff
@@ -811,11 +1246,27 @@
-    if outcome == "clean" and args.write_catalog:
-        try:
-            with open(args.write_catalog, "r", encoding="utf-8") as fh:
-                current = fh.read()
-            record["written_ceiling"] = i2_clamped(current, args.model, int(largest_ok_measured))[0]
-            new_catalog = write_catalog_operator_set(
-                current, args.model, ceiling=int(largest_ok_measured), calibrated_at=record["calibrated_at"],
-                cli_model=record["cli_model"], host_route=host_route, cli_version=cli_version)
-        except (OSError, ValueError) as e:
-            record["error"] = f"catalog not written: {e}"
-            errors.append(record["error"])
+    forced = outcome != "clean" and args.write_partial_as_operator_set and interrupted is None
+    if args.write_catalog and (outcome == "clean" or forced):
+        if forced and not (best and largest_ok_measured):
+            # nothing to vouch for: not an `other` failure of the probe, the exit stays 3
+            # r251-2 Q4: a separate key — the probe's own first error (errors[0]) stays in `error`
+            record["write_skipped"] = ("catalog not written: --write-partial-as-operator-set but no verified "
+                                       "accept to vouch for")
+            record.setdefault("error", record["write_skipped"])
+        else:
+            try:
+                with open(args.write_catalog, "r", encoding="utf-8") as fh:
+                    current = fh.read()
+                written = i2_clamped(current, args.model, int(largest_ok_measured))[0]
+                new_catalog = write_catalog_operator_set(
+                    current, args.model, ceiling=int(largest_ok_measured), calibrated_at=record["calibrated_at"],
+                    cli_model=record["cli_model"], host_route=host_route, cli_version=cli_version,
+                    probe_outcome=outcome, sample_size=len(samples), force_partial=bool(forced))
+                # r251-2 Q3: the catalog lands BEFORE the record is serialized, and the
+                # record claims a write only once it has landed
+                _write_text_atomic(args.write_catalog, new_catalog)
+                record["written_ceiling"] = written
+                record["written_probe_outcome"] = outcome
+            except (OSError, ValueError) as e:
+                new_catalog = None
+                record["write_failed"] = True
+                record["error"] = f"catalog not written: {e}"
+                errors.append(record["error"])
~~~~

## H226 — tools/ceiling-probe-live.py — head lines 830–831

Head context (head/tools/ceiling-probe-live.py, lines 818–843):

~~~~text
   818 |                 cli_model=record["cli_model"], host_route=host_route, cli_version=cli_version)
   819 |         except (OSError, ValueError) as e:
   820 |             record["error"] = f"catalog not written: {e}"
   821 |             errors.append(record["error"])
   822 |     text = json.dumps(record, indent=2)
   823 |     if args.output == "-":
   824 |         print(text)
   825 |     else:
   826 |         with open(args.output, "w") as fh:
   827 |             fh.write(text + "\n")
   828 |         print(f"ceiling-probe-live: wrote {args.output} (outcome={outcome}, measured={largest_ok_measured}, "
   829 |               f"spent≈${record['spent_usd']} catalog estimate)", file=sys.stderr)
>  830 |     if outcome != "clean":
>  831 |         print(f"ceiling-probe-live: partial ({'; '.join(reasons)}) — nothing written to the catalog", file=sys.stderr)
   832 |         return 1 if errors else 3
   833 |     if args.write_catalog:
   834 |         if new_catalog is None:
   835 |             print(f"ceiling-probe-live: {record['error']}", file=sys.stderr)
   836 |             return 1
   837 |         try:
   838 |             _write_text_atomic(args.write_catalog, new_catalog)
   839 |         except OSError as e:
   840 |             print(f"ceiling-probe-live: catalog not written: {e}", file=sys.stderr)
   841 |             return 1
   842 |         print(f"ceiling-probe-live: {args.write_catalog}: {args.model} probed_ceiling=effective_input_ceiling="
   843 |               f"{record['written_ceiling']} (measured {largest_ok_measured}; operator_set, probed_headless, "
~~~~

The change from head to the fix:

~~~~diff
@@ -830,2 +1281,17 @@
+    if interrupted is not None:
+        print(f"ceiling-probe-live: interrupted ({interrupted_text}) — record kept, nothing written to the "
+              f"catalog", file=sys.stderr)
+        return 130 if isinstance(interrupted, KeyboardInterrupt) else 1
     if outcome != "clean":
-        print(f"ceiling-probe-live: partial ({'; '.join(reasons)}) — nothing written to the catalog", file=sys.stderr)
+        if record.get("write_failed"):
+            print(f"ceiling-probe-live: {record['error']}", file=sys.stderr)
+            return 1
+        if forced and new_catalog is not None:
+            print(f"ceiling-probe-live: partial ({'; '.join(reasons)}) — written anyway as operator_set "
+                  f"(--write-partial-as-operator-set: the operator vouches for the last verified accept): "
+                  f"{args.model} effective_input_ceiling={record['written_ceiling']} (measured {largest_ok_measured}), "
+                  f"probe_outcome: partial, sample_size {len(samples)}", file=sys.stderr)
+        else:
+            why = f" ({record['write_skipped']})" if record.get("write_skipped") else ""
+            print(f"ceiling-probe-live: partial ({'; '.join(reasons)}) — nothing written to the catalog{why}",
+                  file=sys.stderr)
~~~~

## H227 — tools/ceiling-probe-live.py — head lines 837–841

Head context (head/tools/ceiling-probe-live.py, lines 825–851):

~~~~text
   825 |     else:
   826 |         with open(args.output, "w") as fh:
   827 |             fh.write(text + "\n")
   828 |         print(f"ceiling-probe-live: wrote {args.output} (outcome={outcome}, measured={largest_ok_measured}, "
   829 |               f"spent≈${record['spent_usd']} catalog estimate)", file=sys.stderr)
   830 |     if outcome != "clean":
   831 |         print(f"ceiling-probe-live: partial ({'; '.join(reasons)}) — nothing written to the catalog", file=sys.stderr)
   832 |         return 1 if errors else 3
   833 |     if args.write_catalog:
   834 |         if new_catalog is None:
   835 |             print(f"ceiling-probe-live: {record['error']}", file=sys.stderr)
   836 |             return 1
>  837 |         try:
>  838 |             _write_text_atomic(args.write_catalog, new_catalog)
>  839 |         except OSError as e:
>  840 |             print(f"ceiling-probe-live: catalog not written: {e}", file=sys.stderr)
>  841 |             return 1
   842 |         print(f"ceiling-probe-live: {args.write_catalog}: {args.model} probed_ceiling=effective_input_ceiling="
   843 |               f"{record['written_ceiling']} (measured {largest_ok_measured}; operator_set, probed_headless, "
   844 |               f"calibrated_at={record['calibrated_at']}); "
   845 |               f"regenerate: bash .claude/scripts/gen-adapter-maps.sh && "
   846 |               f"npm --prefix .claude/skills/bridgebuilder-review run build", file=sys.stderr)
   847 |     return 0
   848 | 
   849 | 
   850 | if __name__ == "__main__":
   851 |     sys.exit(main())
~~~~

The change from head to the fix:

~~~~diff
@@ -837,5 +1302,0 @@
-        try:
-            _write_text_atomic(args.write_catalog, new_catalog)
-        except OSError as e:
-            print(f"ceiling-probe-live: catalog not written: {e}", file=sys.stderr)
-            return 1
~~~~
