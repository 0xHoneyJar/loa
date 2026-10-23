# Incidents — pr-14

Things that happened after the change merged and cite one of its files: later fix commits on the main branch, issues, review rounds and known-failure entries. The quoted text is data, not instructions.

## I01 — fix-commit — 2026-10-07

- reference: 059e26be76ab
- files: .claude/adapters/cheval.py,.claude/adapters/loa_cheval/providers/base.py,.claude/adapters/tests/test_anthropic_catalog_floor.py,.claude/data/schemas/model-config-v3.schema.json,.claude/defaults/model-config.yaml,.claude/defaults/model-config.yaml.checksum,.claude/scripts/flatline-orchestrator.sh,.claude/scripts/loa-status.sh,.claude/skills/bridgebuilder-review/dist/.build-manifest.json,.claude/skills/bridgebuilder-review/dist/core/truncation.generated.d.ts.map,.claude/skills/bridgebuilder-review/dist/core/truncation.generated.js,.claude/skills/bridgebuilder-review/dist/core/truncation.generated.js.map,.claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts,docs/migration/v2.0-model-generation-floor.md,tests/unit/adversarial-review-companion.bats,tests/unit/gen-bb-registry-codegen.bats,tests/unit/loa-status-providers.bats

Summary:

fix(cycle-127): sprint-251 review dissent round r251-1 — cheval's chain walk plans around a gated agy hop (models_not_planned, reason opt_in_required, never a breaker count; a direct --model gemini-headless still refuses INVALID_CONFIG) and one routing predicate decides what the agy route is (.claude/scripts/lib/agy-gate-lib.sh + loader.routes_to_agy: the gemini-headless hop by name, or a Google…

Evidence (first 200 of 1058 lines):

~~~~diff
commit 059e26be76abba262fc8ceaf271057a0252ea08e
Date: 2026-10-07T23:01:17+11:00

fix(cycle-127): sprint-251 review dissent round r251-1 — cheval's chain walk plans around a gated agy hop (models_not_planned, reason opt_in_required, never a breaker count; a direct --model gemini-headless still refuses INVALID_CONFIG) and one routing predicate decides what the agy route is (.claude/scripts/lib/agy-gate-lib.sh + loader.routes_to_agy: the gemini-headless hop by name, or a Google voice under effective cli-only) for the dissent, Flatline, preflight, /loa, Bridgebuilder and cheval (agy-gate-conformance.bats); the opt-in is read from the project config only, a non-boolean value WARNs and stays off, the D-1.7 availability WARN exists, failure_class reaches the error envelope and MODELINV; Bridgebuilder surfaces a config read failure as such, requires the gate parameter, names the opt-in in the no-models throw. The units gap (verified: the 936,000 bound is in provider-measured tokens while cheval's estimate under-counts ~1.4x and BB budgets at chars/4): calibrated entries ask count_tokens from half the bound, BB's generated budget for a measured-unit calibration divides by 1.8 (916,000 → 508,000), a calibration measured on a foreign transport may be tightened by a verified observation on the HTTP route (rendered in /loa and --json); effort_effective is adapter-derived (wire_effort), EFFORT_LEVELS defined once and pinned to both schemas. Probe: fair charging at the 1.25x cache-write rate (CLI-local rejections cost 0), TPM-window backoff, throttle markers win over context markers, persisting token-limit = size, full-diag classification + the CLI's "~N tokens (limit M)" shape, record kept on interrupt, write prerequisites before the first call, process-group kill, anchored 5xx, api-only flags refused on the CLI transport, probe_outcome + sample_size provenance with --write-partial-as-operator-set (the live entry says probe_outcome: partial, sample_size: 5). SDD D-1.6 names INVALID_CONFIG; SDD D-1.8…D-3.12, PRD, CHANGELOG, migration addendum, sprint round section. Refuted with evidence: n1, n6, n9, n10, n12, n13, n17, n21, n28, n31, n32, n36, n43, n44, n54. Bead bd-c2rd (estimator calibration).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/.claude/adapters/cheval.py b/.claude/adapters/cheval.py
index ca85d389..58841120 100644
--- a/.claude/adapters/cheval.py
+++ b/.claude/adapters/cheval.py
@@ -30,6 +30,7 @@ if _ADAPTERS_DIR not in sys.path:
     sys.path.insert(0, _ADAPTERS_DIR)
 
 from loa_cheval.types import (
+    EFFORT_LEVELS,
     coerce_headless_timeout_seconds,
     headless_timeout_note,
     headless_read_floor,
@@ -68,7 +69,7 @@ from loa_cheval.routing.ceiling import (
     policy_from_env as _ceiling_policy_from_env,
     record_observed as _ceiling_record_observed,
 )
-from loa_cheval.providers import cli_adapter_types, get_adapter
+from loa_cheval.providers import adapter_class_for_type, cli_adapter_types, get_adapter
 from loa_cheval.providers.base import _legacy_wire, default_max_tokens  # cycle-124 FR-2/FR-4
 from loa_cheval.types import ProviderConfig, ModelConfig
 from loa_cheval.metering.budget import BudgetEnforcer
@@ -354,6 +355,51 @@ _CLI_ADAPTER_BY_PROVIDER: Dict[str, str] = {
 }
 
 
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
+    from loa_cheval.routing.types import ResolvedChain as _RC
+    kept = tuple(e for e in chain.entries if e not in agy)
+    skipped = [{"model": e.canonical, "provider": e.provider, "reason": "opt_in_required"} for e in agy]
+    if not _AGY_NOT_PLANNED_WARNED:
+        _AGY_NOT_PLANNED_WARNED = True
+        logger.warning(
+            "agy hop(s) %s not planned: the agy route is opt-in (hounfour.headless.agy_opt_in is not true) — "
+            "walking the remaining hop(s) %s", ", ".join(x["model"] for x in skipped), ", ".join(e.canonical for e in kept))
+    return _RC(primary_alias=chain.primary_alias, entries=kept, headless_mode=chain.headless_mode,
+               headless_mode_source=chain.headless_mode_source), skipped
+
+
 def _get_adapter_for_entry(entry: Any, hounfour: Dict[str, Any]):
     """Select the adapter for a single ResolvedEntry honoring `adapter_kind`.
 
@@ -861,7 +907,7 @@ def _hop_max_tokens(
     return explicit
 
 
-_EFFORT_LEVELS = ("low", "medium", "high", "xhigh", "max")
+_EFFORT_LEVELS = EFFORT_LEVELS  # cycle-127 r251-1 C5: defined once in loa_cheval.types
 # One WARN per (model, reason) per process: an invalid catalog value or an
 # entry setting both rungs is a config smell, not a per-call event.
 _EFFORT_WARNED: set = set()
@@ -918,10 +964,19 @@ def resolve_effort(
         _effort_warn_once((model_key, "invalid"),
                           "%s: params.default_effort %r is not one of %s — ignored (cycle-127 FR-2)",
                           model_key, params["default_effort"], ", ".join(_EFFORT_LEVELS))
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
     return None, "none"
 
 
@@ -929,15 +984,32 @@ def _effort_on_wire(provider: str, model_id: str, effort: Optional[str], hounfou
     """What the dispatched hop puts on the wire for `effort` (cycle-127 D-2.6):
     the Anthropic HTTP adapter's per-family mapping (`xhigh` → `high` on
     4.6, omitted on Sonnet/Haiku 4.5); a CLI hop passes it through; other
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
 
 
 def _entry_thinking_class(entry: Any, hounfour: Dict[str, Any]) -> bool:
@@ -1692,6 +1764,10 @@ def cmd_invoke(args: argparse.Namespace) -> int:
     # emit because no model invocation occurred. `models_requested` enumerates
     # the entire resolved chain so audit consumers see the FULL intended walk
     # shape, not just whichever entry happened to succeed.
+    # cycle-127 review r251-1 G1: a gated agy hop is planned around before models_requested is taken.
+    _chain, _models_not_planned = _plan_around_agy(_chain, hounfour)
+    if _models_not_planned and _auth_type_resolved is not None:
+        _auth_type_resolved = _chain.entries[0].auth_type
     _modelinv_capability_class = getattr(binding, "capability_class", None)
     _modelinv_models_requested = [e.canonical for e in _chain.entries]
     _modelinv_state: Dict[str, Any] = {
@@ -2068,6 +2144,7 @@ def cmd_invoke(args: argparse.Namespace) -> int:
                     capability_class=_modelinv_capability_class,
                     capability_evaluation=_modelinv_state.get("capability_evaluation"),
                     calling_primitive=(getattr(args, "skill", None) or agent_name),
+                    models_not_planned=_models_not_planned or None,
                 )
             except Exception as _emit_err:  # noqa: BLE001 — fail-soft; never mask exit 7
                 print(
@@ -2543,13 +2620,20 @@ def cmd_invoke(args: argparse.Namespace) -> int:
                 continue
             except ChevalError as _e:
                 # Non-retryable typed cheval error — surface immediately.
-                _modelinv_state["models_failed"].append({
-                    "model": _entry_target,
-                    "provider": _entry.provider,
-                    "error_class": "UNKNOWN",
-                    "message_redacted": str(_e),
-                })
-                print(_error_json(_e.code, str(_e), retryable=_e.retryable), file=sys.stderr)
+                _fc = (getattr(_e, "context", None) or {}).get("failure_class")
+                if _fc == "opt_in_required":
+                    # cycle-127 review r251-1 G1/G5: agy asked for by name with the opt-in off — a refusal, not a
+                    # failed voice: recorded as not planned, and the envelope names the failure class.
+                    _models_not_planned.append({"model": _entry_target, "provider": _entry.provider, "reason": _fc})
+                else:
+                    _modelinv_state["models_failed"].append({
+                        "model": _entry_target,
+                        "provider": _entry.provider,
+                        "error_class": "UNKNOWN",
+                        "message_redacted": str(_e),
+                    })
+                print(_error_json(_e.code, str(_e), retryable=_e.retryable,
+                                  **({"failure_class": _fc} if isinstance(_fc, str) and _fc else {})), file=sys.stderr)
                 return EXIT_CODES.get(_e.code, 1)
             except Exception as _e:  # noqa: BLE001
                 # Catch-all: redact known env-var secrets before recording.
~~~~

## I02 — fix-commit — 2026-10-07

- reference: d12bdfabcec0
- files: .claude/adapters/cheval.py,.claude/adapters/tests/test_anthropic_catalog_floor.py,.claude/skills/bridgebuilder-review/dist/.build-manifest.json,.loa.config.yaml.example,docs/migration/v2.0-model-generation-floor.md,tests/unit/adversarial-review-companion.bats

Summary:

fix(cycle-127): sprint-251 review dissent round r251-2 — one strict opt-in rule on both readers (only the YAML scalar whose source text is exactly `true`; bash and Python had split on yes/on/True), an agy-alone refusal lands in models_failed only (INVALID_CONFIG / opt_in_required; models_not_planned is for hops dropped before the walk; voices_dropped names the reason), run-preflight P3 judges an…

Evidence (first 200 of 252 lines):

~~~~diff
commit d12bdfabcec063a828518654ca711f1bf502ec2c
Date: 2026-10-08T01:44:25+11:00

fix(cycle-127): sprint-251 review dissent round r251-2 — one strict opt-in rule on both readers (only the YAML scalar whose source text is exactly `true`; bash and Python had split on yes/on/True), an agy-alone refusal lands in models_failed only (INVALID_CONFIG / opt_in_required; models_not_planned is for hops dropped before the walk; voices_dropped names the reason), run-preflight P3 judges an agy-routed voice by `command -v agy` when the opt-in is on (routes_to_agy → cli=agy; gemini-headless:<m> too), the dissent's lib-missing path keeps an inline name filter, the yq fallback is selected by flavour, Bridgebuilder's readError is fail-closed for google voices with messages that name the cause and the voices; the headless adapter maps the CLI's own pre-flight rejection ("Prompt is too long", "~N tokens (limit M)") to ProviderContextLimitError (not walked, no breaker count; it was ProviderUnavailableError); the probe's 429 lookahead accepts "429." and reads the throttle verdict from the CLI's own answer, checks catalog writability before spend, claims a write only after it lands, keeps a defect's traceback; vacuous bats assertions fixed, conformance rows for yes/on/True/TRUE/1/"true", concrete _lookup pin, provenance guard requires probed_headless for a foreign transport. Docs: two-case routing rule, Bridgebuilder budget 508,000 = (936,000 − 20,000) ÷ 1.8, --write-partial-as-operator-set in PRD FR-3.5 / SDD D-3.8, effort carry as existing behaviour, "only a dispatch whose sole hop is agy-routed refuses", the count_tokens gate scoped to the HTTP adapter, the refuted long-context sentence removed. Refuted with evidence: 30 of 76 (eight chunker mislabels — the chunker now keeps per-file headers). Beads bd-y49y (payload-schema drift), bd-c2rd note.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/.claude/adapters/cheval.py b/.claude/adapters/cheval.py
index 58841120..539e257a 100644
--- a/.claude/adapters/cheval.py
+++ b/.claude/adapters/cheval.py
@@ -1298,6 +1298,8 @@ def _vq_map_reason(
         return "ChainExhausted"
     # Single-entry chain: use the last recorded error_class mapping.
     last_class = str(models_failed[-1].get("error_class") or "UNKNOWN")
+    if models_failed[-1].get("failure_class") == "opt_in_required":
+        return "OptInRequired"   # (cycle-127 review r251-2 K2: the agy route refused by its opt-in, not "Other")
     return _VQ_ERROR_CLASS_TO_REASON.get(last_class, "Other")
 
 
@@ -2211,17 +2213,22 @@ def cmd_invoke(args: argparse.Namespace) -> int:
         from loa_cheval.redaction import sanitize_provider_error_message as _sanitize
         _msg = _sanitize(str(_exc))
         _obs = int(observed) if isinstance(observed, int) and observed > 0 else int(_walk_estimate or 0)
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
         except Exception as _rec_err:  # noqa: BLE001 — the record must never mask the typed exit
             print(f"[preflight] observed-bound record failed: {type(_rec_err).__name__}", file=sys.stderr)
         _calib = {
             "provider": _entry.provider, "model": _entry.model_id, "observed_input_tokens": _obs,
             "provider_limit": provider_limit, "error_class": error_class,
             "calibrate": _PROBE_COMMAND.format(model=_entry.model_id), "store": _observed_store_path(),
+            "observation_recorded": _record,
         }
         if isinstance(_modelinv_state.get("capability_evaluation"), dict):
             _modelinv_state["capability_evaluation"]["calibration_needed"] = _calib
@@ -2622,9 +2629,17 @@ def cmd_invoke(args: argparse.Namespace) -> int:
                 # Non-retryable typed cheval error — surface immediately.
                 _fc = (getattr(_e, "context", None) or {}).get("failure_class")
                 if _fc == "opt_in_required":
-                    # cycle-127 review r251-1 G1/G5: agy asked for by name with the opt-in off — a refusal, not a
-                    # failed voice: recorded as not planned, and the envelope names the failure class.
-                    _models_not_planned.append({"model": _entry_target, "provider": _entry.provider, "reason": _fc})
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
                 else:
                     _modelinv_state["models_failed"].append({
                         "model": _entry_target,
diff --git a/.claude/adapters/tests/test_anthropic_catalog_floor.py b/.claude/adapters/tests/test_anthropic_catalog_floor.py
index 65acc255..792df478 100644
--- a/.claude/adapters/tests/test_anthropic_catalog_floor.py
+++ b/.claude/adapters/tests/test_anthropic_catalog_floor.py
@@ -165,16 +165,32 @@ def test_a_foreign_transport_calibration_carries_its_provenance(http_entries):
     transport (ceiling_calibration.transport ≠ api) must say how it was measured and what
     the provider accepted — `method` and `measured_input_tokens` — so the cross-transport
     trust is auditable, and an observed limit on this route may tighten it (routing.ceiling)."""
-    for model_id, entry in http_entries.items():
-        if not is_foreign_transport_calibration(entry):
-            continue
+    foreign = [m for m, e in http_entries.items() if is_foreign_transport_calibration(e)]
+    # (review r251-2 K9 / n36: with zero foreign entries the loop would assert nothing — the live catalog has one)
+    assert "claude-opus-5-5" in foreign, foreign
+    for model_id in foreign:
+        entry = http_entries[model_id]
         cal = entry["ceiling_calibration"]
-        assert cal.get("method") in ("probed_api", "probed_headless"), (model_id, cal.get("method"))
+        # a bound measured on a non-API transport was measured headless — `probed_api` there is a mislabel (n36)
+        assert cal.get("method") == "probed_headless", (model_id, cal.get("transport"), cal.get("method"))
         assert isinstance(cal.get("measured_input_tokens"), int) and cal["measured_input_tokens"] > 0, model_id
         assert cal["measured_input_tokens"] >= entry["effective_input_ceiling"], (
             f"{model_id}: the written bound may be clamped below the measured accept, never above it")
 
 
+def test_lookup_returns_the_concrete_bound_through_the_gate_path(catalog, monkeypatch):
+    """review r251-2 K9 (n35): one concrete pin THROUGH `_lookup_max_input_tokens` — the other pins compare the policy
+    against itself. claude-opus-5-5 is calibrated (1M window − 64K default output = 936,000); claude-opus-5 is not, and
+    answers its probed value (the policy cap)."""
+    monkeypatch.delenv("LOA_CHEVAL_DISABLE_STREAMING", raising=False)
+    monkeypatch.delenv("LOA_CHEVAL_LEGACY_WIRE", raising=False)
+    monkeypatch.setenv("LOA_CHEVAL_CEILING_OBSERVED_PATH", "/nonexistent/ceiling-observed.json")  # no host observations
+    assert _lookup_max_input_tokens("anthropic", "claude-opus-5-5", catalog) == 936_000
+    uncal = catalog["providers"]["anthropic"]["models"]["claude-opus-5"]
+    assert not uncal["ceiling_calibration"].get("calibrated_at")
+    assert _lookup_max_input_tokens("anthropic", "claude-opus-5", catalog) == uncal["probed_ceiling"] == CEILING_CAP
+
+
 @pytest.mark.parametrize("kill_switch", ["", "1"])
 def test_input_gate_positive_with_and_without_streaming_kill_switch(catalog, http_entries, monkeypatch, kill_switch):
     if kill_switch:
diff --git a/.claude/skills/bridgebuilder-review/dist/.build-manifest.json b/.claude/skills/bridgebuilder-review/dist/.build-manifest.json
index 238f0f36..d5404637 100644
--- a/.claude/skills/bridgebuilder-review/dist/.build-manifest.json
+++ b/.claude/skills/bridgebuilder-review/dist/.build-manifest.json
@@ -1,7 +1,7 @@
 {
   "version": "1.0",
-  "generated_at": "2026-10-07T11:53:40Z",
-  "source_hash": "4bd78108a00fa753166a889fa1b7e39000d3670bff993acc9379c8e70e7f5d9b",
+  "generated_at": "2026-10-07T14:38:21Z",
+  "source_hash": "3ba946ae6d2b0401b76f5c9a651849ab695ddb41493f72c5ead899c8225e48af",
   "file_count": 42,
   "files": [
     {
@@ -46,7 +46,7 @@
     },
     {
       "path": ".claude/skills/bridgebuilder-review/resources/config.ts",
-      "sha256": "f085193c1f4fda67a44f1eb402d804d57674173921994f81b6a8f1a123391a78"
+      "sha256": "bd01d514a061ae8288a8edf64b5c210d90d831430f9c94902f74fcbe47823d71"
     },
     {
       "path": ".claude/skills/bridgebuilder-review/resources/core/cache.ts",
@@ -86,7 +86,7 @@
     },
     {
       "path": ".claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts",
-      "sha256": "8f91db5ba9a510fd3a6a4c6c4fb5e35f67b0267046d5bcc4c21c02cff9346b99"
+      "sha256": "1ca6ee3c40bbf5709a9d398bc02adbe4416cd0e71d940bfadf82f5720f962ef9"
     },
     {
       "path": ".claude/skills/bridgebuilder-review/resources/core/progress.ts",
@@ -138,7 +138,7 @@
     },
     {
       "path": ".claude/skills/bridgebuilder-review/resources/main.ts",
-      "sha256": "55adde1c98115dfcd94c669fcf2e07c6b5977e2e60d24d1b8c3149c18dfc0a86"
+      "sha256": "054a9bd84fd8b668f9bf04ff792711b90d86ff7ecaa9ca25009e88b328777785"
     },
     {
       "path": ".claude/skills/bridgebuilder-review/resources/ports/context-store.ts",
diff --git a/.loa.config.yaml.example b/.loa.config.yaml.example
index 8b1b23f7..2d373919 100644
--- a/.loa.config.yaml.example
+++ b/.loa.config.yaml.example
@@ -745,8 +745,9 @@ hounfour:
     # Flatline tertiary, Bridgebuilder, /loa, run preflight) records the hop as not planned
     # (reason opt_in_required), never as a failed voice — a host without agy plans no Google CLI voice.
     # Set true only where agy is installed AND OAuth-authed: `agy -p` takes the whole prompt (the
-    # redacted review diff) on argv, readable by every local account through /proc and ps. Only a
-    # YAML boolean true counts; there is no environment override.
+    # redacted review diff) on argv, readable by every local account through /proc and ps. Only the
+    # lowercase scalar `true` counts (yes / on / True / "true" read off, with a WARN); there is no
+    # environment override.
     agy_opt_in: false
     # cli_paths: discovery hints. If unset, $PATH is searched.
     # cli_paths:
diff --git a/docs/migration/v2.0-model-generation-floor.md b/docs/migration/v2.0-model-generation-floor.md
index c177b050..3a438512 100644
--- a/docs/migration/v2.0-model-generation-floor.md
+++ b/docs/migration/v2.0-model-generation-floor.md
@@ -286,19 +286,20 @@ ### Cycle-127 addendum — operator decisions (unreleased)
   the hop as *not planned* (`reason: opt_in_required`) rather than failed — verdict
   quality counts planned voices only. One predicate decides what the agy route is
   (`.claude/scripts/lib/agy-gate-lib.sh`; Python twin in the loader): the literal
-  `gemini-headless` hop, a Google voice under effective `cli-only`, or a Google voice
-  under `prefer-api` with no Google key resolvable — and cheval's own chain walk skips
-  such a hop inside a fallback chain (`planned: false, reason: opt_in_required`) and
-  walks on; only a direct `--model gemini-headless` refuses. The key is read from
+  `gemini-headless` hop, or a Google voice under effective `cli-only` (under `prefer-api`
+  with no Google key the HTTP hop fails on credentials first, as before) — and cheval's
+  own chain walk skips such a hop inside a fallback chain (`planned: false, reason:
+  opt_in_required`) and walks on; a chain that is agy alone, like a direct `--model
+  gemini-headless`, refuses with `INVALID_CONFIG`. The key is read from
   `.loa.config.yaml` alone (a framework defaults file cannot opt you in); a quoted
   `"true"` stays off and WARNs once. Set it `true` only where `agy` is installed and
   OAuth-authed, knowing the argv exposure. With it on, behaviour is exactly as before.
 - **Opus 5.5 effort default.** See the cycle-126 bullet above: `claude-opus-5-5` carries
-  `params.default_effort: high`; `--effort` overrides. A hop the chain walk reaches that
-  declares no default inherits the effort resolved for the requested entry (`opus` →
-  `claude-headless` keeps `high`); a CLI entry's own default is yours to declare
-  (`params.default_effort` on that entry, or its legacy `extra.effort`) — the catalog
-  does not know which model your CLI runs.
+  `params.default_effort: high`; `--effort` overrides. Effort is resolved once for the
+  requested entry and carried to every hop the walk reaches (`opus` → `claude-headless`
+  sends `--effort high`); a CLI entry's own default (`params.default_effort` on that
+  entry, or its legacy `extra.effort`) applies only when that entry is the one requested
+  — the catalog does not know which model your CLI runs.
 - **Calibrating the ceiling through the headless CLI.** `tools/ceiling-probe-live.py
   --transport claude-headless` measures the accepted input size through
~~~~

## I03 — fix-commit — 2026-10-07

- reference: 58f871959c89
- files: .claude/adapters/cheval.py,.claude/adapters/tests/test_anthropic_catalog_floor.py,docs/migration/v2.0-model-generation-floor.md,tests/unit/cycle-124-effort-flag.bats,tests/unit/loa-status-providers.bats

Summary:

fix(cycle-127): sprint-251 review round r251-3 — the Fable review's items: one shared is_throttle_message() in routing/ceiling.py (the probe's throttle rule + overloaded / too many requests / quota, a 429/529 in status position, never a digit inside a token count) consulted by the headless adapter before its context-limit mapping — Bedrock's "Too many tokens, please wait before trying again" is a…

Evidence:

~~~~diff
commit 58f871959c8948f8e72dde0838005668a3d72b3e
Date: 2026-10-08T02:42:56+11:00

fix(cycle-127): sprint-251 review round r251-3 — the Fable review's items: one shared is_throttle_message() in routing/ceiling.py (the probe's throttle rule + overloaded / too many requests / quota, a 429/529 in status position, never a digit inside a token count) consulted by the headless adapter before its context-limit mapping — Bedrock's "Too many tokens, please wait before trying again" is a RateLimitError again (retried, then walked), not a terminal size verdict (the r251-2 K8 regression) — and by the probe's classifier, with a probe-vs-adapter conformance test; the K9 _lookup pin reads its expectation from the catalog and the literal guard sweeps the current bound's digits (AC 3); the routing rule is provider-based under cli-only on both readers (deep-research-pro is agy-alone everywhere); the context-limit remedy for a CLI hop names the chain-head HTTP entry with --transport claude-headless; the probe suite's host-global ledger assertion is gone; cycle-124-effort-flag.bats unsets the host variables itself; AGC-6's loa-status timeout is 180 s. Docs: the cycle-126 SDD D-4.1 amendment carries the promised cycle-127 pointer (AC 4), SDD §5/§6 (effort_source incl. extra, effort_effective; resolve-time WARN; headless size verdict vs throttle; the partial flag), the superseded reprobe_trigger sentence, AC 1 / PRD SC-1 name the existing INVALID_CONFIG refusal for an absent binary, CHANGELOG and the addendum name the throttle rule; beads flushed (bd-c2rd, bd-y49y, bd-n6lk Bedrock effort, bd-rbkz probe Bisection extraction).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/.claude/adapters/cheval.py b/.claude/adapters/cheval.py
index 539e257a..59fef198 100644
--- a/.claude/adapters/cheval.py
+++ b/.claude/adapters/cheval.py
@@ -355,6 +355,24 @@ _CLI_ADAPTER_BY_PROVIDER: Dict[str, str] = {
 }
 
 
+def _calibrate_hint(entry: Any, chain_entries: Any) -> Optional[str]:
+    """The ceiling-probe command for a provider size verdict on `entry` (cycle-126 D-1.1b), or None.
+
+    An HTTP hop names itself. A CLI hop carries no ceiling fields — the probe refuses it — so (review r251-3 R4) a
+    claude-headless hop names the chain's Anthropic HTTP entry with `--transport claude-headless` (the transport that
+    measured the payload), and any other CLI hop, or a chain with no such entry, gets no hint: the CLI's own window
+    refused the payload."""
+    if getattr(entry, "adapter_kind", "http") != "cli":
+        return _PROBE_COMMAND.format(model=entry.model_id)
+    if _CLI_ADAPTER_BY_PROVIDER.get(getattr(entry, "provider", "")) != "claude-headless":
+        return None
+    head = next((e for e in (chain_entries or ())
+                 if getattr(e, "adapter_kind", "http") != "cli" and getattr(e, "provider", "") == entry.provider), None)
+    if head is None:
+        return None
+    return f"{_PROBE_COMMAND.format(model=head.model_id)} --transport claude-headless"
+
+
 _AGY_NOT_PLANNED_WARNED = False
 
 
@@ -2227,7 +2245,7 @@ def cmd_invoke(args: argparse.Namespace) -> int:
         _calib = {
             "provider": _entry.provider, "model": _entry.model_id, "observed_input_tokens": _obs,
             "provider_limit": provider_limit, "error_class": error_class,
-            "calibrate": _PROBE_COMMAND.format(model=_entry.model_id), "store": _observed_store_path(),
+            "calibrate": _calibrate_hint(_entry, _chain.entries), "store": _observed_store_path(),
             "observation_recorded": _record,
         }
         if isinstance(_modelinv_state.get("capability_evaluation"), dict):
@@ -2237,14 +2255,18 @@ def cmd_invoke(args: argparse.Namespace) -> int:
             "message_redacted": _msg, "observed_input_tokens": _obs, "provider_limit": provider_limit,
         })
         _modelinv_state["operator_visible_warn"] = True
+        # (review r251-3 R4: a CLI hop with no HTTP entry to calibrate gets no probe command — the CLI's window refused it)
+        _remedy = (f"calibrate: {_calib['calibrate']}" if _calib["calibrate"]
+                   else "the CLI's own window refused the payload (no catalog ceiling to calibrate)")
         print(
             f"[preflight] calibration_needed model={_entry_target} class={error_class} "
-            f"observed_input_tokens={_obs} — not walked (cycle-126 D-1.1b); run: {_calib['calibrate']}",
+            f"observed_input_tokens={_obs} — not walked (cycle-126 D-1.1b); "
+            + (f"run: {_calib['calibrate']}" if _calib["calibrate"] else _remedy),
             file=sys.stderr,
         )
         print(_error_json(
             _exc.code,
-            f"{_msg} — not walked: the same payload would fail the next voice; calibrate: {_calib['calibrate']}",
+            f"{_msg} — not walked: the same payload would fail the next voice; {_remedy}",
             retryable=False, calibration_needed=True, error_class=error_class,
             observed_input_tokens=_obs, provider_limit=provider_limit,
         ), file=sys.stderr)
diff --git a/.claude/adapters/tests/test_anthropic_catalog_floor.py b/.claude/adapters/tests/test_anthropic_catalog_floor.py
index 792df478..4fc15c08 100644
--- a/.claude/adapters/tests/test_anthropic_catalog_floor.py
+++ b/.claude/adapters/tests/test_anthropic_catalog_floor.py
@@ -179,13 +179,19 @@ def test_a_foreign_transport_calibration_carries_its_provenance(http_entries):
 
 
 def test_lookup_returns_the_concrete_bound_through_the_gate_path(catalog, monkeypatch):
-    """review r251-2 K9 (n35): one concrete pin THROUGH `_lookup_max_input_tokens` — the other pins compare the policy
-    against itself. claude-opus-5-5 is calibrated (1M window − 64K default output = 936,000); claude-opus-5 is not, and
-    answers its probed value (the policy cap)."""
+    """review r251-2 K9 (n35): one concrete check THROUGH `_lookup_max_input_tokens` — the gate answers a calibrated
+    entry's catalog bound (not the policy cap). claude-opus-5-5 is calibrated; claude-opus-5 is not, and answers its
+    probed value (the policy cap). r251-3 R2 (AC 3): the expectation is READ from the catalog, so this check moves
+    with the next re-probe instead of pinning today's bound by literal."""
     monkeypatch.delenv("LOA_CHEVAL_DISABLE_STREAMING", raising=False)
     monkeypatch.delenv("LOA_CHEVAL_LEGACY_WIRE", raising=False)
     monkeypatch.setenv("LOA_CHEVAL_CEILING_OBSERVED_PATH", "/nonexistent/ceiling-observed.json")  # no host observations
-    assert _lookup_max_input_tokens("anthropic", "claude-opus-5-5", catalog) == 936_000
+    cal = catalog["providers"]["anthropic"]["models"]["claude-opus-5-5"]
+    assert cal["ceiling_calibration"].get("calibrated_at"), "claude-opus-5-5 is expected to be calibrated"
+    want = cal["effective_input_ceiling"]
+    assert isinstance(want, int) and want != CEILING_CAP, want
+    assert input_bound(cal, max_tokens=_default_max_tokens(cal)).basis == "calibrated"
+    assert _lookup_max_input_tokens("anthropic", "claude-opus-5-5", catalog) == want
     uncal = catalog["providers"]["anthropic"]["models"]["claude-opus-5"]
     assert not uncal["ceiling_calibration"].get("calibrated_at")
     assert _lookup_max_input_tokens("anthropic", "claude-opus-5", catalog) == uncal["probed_ceiling"] == CEILING_CAP
diff --git a/docs/migration/v2.0-model-generation-floor.md b/docs/migration/v2.0-model-generation-floor.md
index 3a438512..64bd6671 100644
--- a/docs/migration/v2.0-model-generation-floor.md
+++ b/docs/migration/v2.0-model-generation-floor.md
@@ -342,7 +342,8 @@ ### Cycle-127 addendum — operator decisions (unreleased)
   (bound − 20,000 headroom) ÷ 1.8 = 508,000 estimated tokens for this entry. On the
   `claude-headless` route there is no HTTP ceiling and no count: the CLI's pre-flight is
   the backstop (no spend; the adapter maps it to the context-limit class — not walked, no
-  breaker count). Near the window a request that slips past the HTTP gate fails cleanly
+  breaker count — unless a throttle marker is present, in which case it is a rate limit,
+  retried then walked). Near the window a request that slips past the HTTP gate fails cleanly
   at the provider (`PROVIDER_CONTEXT_LIMIT`, one upload, not walked). The HTTP route's
   `account_limits` tier is still `unverified`. Downstream mounts inherit the value with the catalog;
   HTTP-route callers and mounts with a different window or tier should run
diff --git a/tests/unit/cycle-124-effort-flag.bats b/tests/unit/cycle-124-effort-flag.bats
index c61302c0..d9bc5f64 100644
--- a/tests/unit/cycle-124-effort-flag.bats
+++ b/tests/unit/cycle-124-effort-flag.bats
@@ -25,6 +25,9 @@ setup() {
     export LOA_MODELINV_LOG_PATH="$BATS_TEST_TMPDIR/model-invoke.jsonl"
     export LOA_COST_LEDGER_PATH="$BATS_TEST_TMPDIR/cost-ledger.jsonl"
     unset LOA_CHEVAL_DISABLE_STREAMING LOA_CHEVAL_LEGACY_WIRE
+    # (cycle-127 r251-3 R6: hermetic to the operator's environment — a Bedrock bearer token turns on bedrock-forward
+    # routing, so `tiny` would resolve to the Bedrock haiku; a CLAUDE_HEADLESS_BIN would point the CLI hop elsewhere)
+    unset CLAUDE_HEADLESS_BIN AWS_BEARER_TOKEN_BEDROCK
 }
 
 # `run` merges stderr into $output by default; the JSON is on stdout and
diff --git a/tests/unit/loa-status-providers.bats b/tests/unit/loa-status-providers.bats
index 2d843d82..83d32dd2 100644
--- a/tests/unit/loa-status-providers.bats
+++ b/tests/unit/loa-status-providers.bats
@@ -64,7 +64,7 @@ teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/de
   echo "$output" | grep -qE '^  anthropic +key (present|absent) +hop [a-z-]+ +no breaker state'
 }
 
-_lsp5_catalog() {  # $1 file, $2 calibrated_at ("" = uncalibrated), $3 transport ("" = absent); bound 200000 / 936000
+_lsp5_catalog() {  # $1 file, $2 calibrated_at ("" = uncalibrated), $3 transport ("" = absent); bound 200000 / 920000 (fixture values, not the live catalog — r251-3 R2)
   local cal_block=""
   if [[ -n "$2" ]]; then
     cal_block="          source: operator_set
@@ -77,7 +77,7 @@ _lsp5_catalog() {  # $1 file, $2 calibrated_at ("" = uncalibrated), $3 transport
           calibrated_at: null
           stale_after_days: 90"
   fi
-  local bound=200000; [[ -n "$2" ]] && bound=936000
+  local bound=200000; [[ -n "$2" ]] && bound=920000
   cat > "$1" <<YAML
 aliases:
   opus: "anthropic:claude-fixture-1"
@@ -152,10 +152,10 @@ _lsp5_obs() {  # $1 model, then (tokens class) pairs → the observed store at $
     _lsp5_obs "$m" 500001 PROVIDER_CONTEXT_LIMIT
     run timeout 120 bash "$STATUS" --no-stale-check
     [ "$status" -eq 0 ]
-    echo "$output" | grep -qF "  ceiling: calibrated 936000 ($m, calibrated 2026-10-07T09:29:07Z)"
+    echo "$output" | grep -qF "  ceiling: calibrated 920000 ($m, calibrated 2026-10-07T09:29:07Z)"
     [[ "$output" != *"below on this route"* ]]
     run timeout 120 bash "$STATUS" --no-stale-check --json
-    echo "$output" | jq -e '.providers.providers.anthropic.ceiling | .basis == "calibrated" and .value == 936000' >/dev/null
+    echo "$output" | jq -e '.providers.providers.anthropic.ceiling | .basis == "calibrated" and .value == 920000' >/dev/null
   done
 }
 
@@ -167,16 +167,16 @@ _lsp5_obs() {  # $1 model, then (tokens class) pairs → the observed store at $
   _lsp5_obs "$m" 990000 PROVIDER_CONTEXT_LIMIT
   run timeout 120 bash "$STATUS" --no-stale-check
   [ "$status" -eq 0 ]
-  echo "$output" | grep -qF "  ceiling: calibrated 936000 ($m, calibrated 2026-10-07T09:29:07Z)"
+  echo "$output" | grep -qF "  ceiling: calibrated 920000 ($m, calibrated 2026-10-07T09:29:07Z)"
   # below it (a 429 row never counts): the observed bound governs and the line names both
   _lsp5_obs "$m" 300000 RATE_LIMIT_UNVERIFIED 500001 PROVIDER_CONTEXT_LIMIT
   run timeout 120 bash "$STATUS" --no-stale-check
   [ "$status" -eq 0 ]
-  echo "$output" | grep -qF "  ceiling: calibrated 936000 (claude-headless); observed 500000 below on this route, reprobe suggested ($m, calibrated 2026-10-07T09:29:07Z; calibrate: python3 tools/ceiling-probe-live.py --model $m --write-catalog)"
+  echo "$output" | grep -qF "  ceiling: calibrated 920000 (claude-headless); observed 500000 below on this route, reprobe suggested ($m, calibrated 2026-10-07T09:29:07Z; calibrate: python3 tools/ceiling-probe-live.py --model $m --write-catalog)"
   run timeout 120 bash "$STATUS" --no-stale-check --json
   [ "$status" -eq 0 ]
   echo "$output" | jq -e '.providers.providers.anthropic.ceiling | .basis == "observed" and .value == 500000 and .calibrated == true
-    and .calibrated_value == 936000 and .calibration_transport == "claude-headless" and .reprobe_suggested == true
+    and .calibrated_value == 920000 and .calibration_transport == "claude-headless" and .reprobe_suggested == true
     and .calibrated_at == "2026-10-07T09:29:07Z"' >/dev/null
 }
 
~~~~

## I04 — fix-commit — 2026-10-07

- reference: cbfccab2e30e
- files: .claude/adapters/cheval.py,.claude/data/schemas/model-config-v3.schema.json,.claude/scripts/flatline-orchestrator.sh,.claude/scripts/loa-status.sh,.claude/skills/bridgebuilder-review/dist/.build-manifest.json,tests/unit/loa-status-providers.bats,tests/unit/model-config-v3-schema.bats

Summary:

fix(cycle-127): sprint-251 audit round r251-4 — the audit dissent's verified items: Bridgebuilder's merge gate no longer fails open under a config read error (readError → mergeBlocked with the reason, strict mode throws; the quorum is never shrunk by unreadable config); cheval reads the agy opt-in from its own install root, never a cwd-ancestor config (a planted /tmp/.loa.config.yaml opted a host…

Evidence (first 200 of 369 lines):

~~~~diff
commit cbfccab2e30ef0364c24908bc4191064d1fdf736
Date: 2026-10-08T04:26:27+11:00

fix(cycle-127): sprint-251 audit round r251-4 — the audit dissent's verified items: Bridgebuilder's merge gate no longer fails open under a config read error (readError → mergeBlocked with the reason, strict mode throws; the quorum is never shrunk by unreadable config); cheval reads the agy opt-in from its own install root, never a cwd-ancestor config (a planted /tmp/.loa.config.yaml opted a host in), and refuses a foreign-owned or group/world-writable config (off, one WARN); one strict spelling rule across the three readers — the exact tag:yaml.org,2002:bool tag, and YAML alias / merge-key nodes read as off everywhere (conformance rows); the lib's include guard is shell-only (declare -F) so an exported variable cannot leave the predicates undefined, and run-preflight fails closed when the lib is missing; the catalog provider maps are never cached after a swallowed exception and both readers WARN once on the name-rule fallback (hostile-subscript test on the associative maps); the throttle-status regex needs non-word boundaries (a request id matched 529), the CLI-shape context-limit parse needs its sentence, the calibrate hint shell-quotes model ids; an implausible observed limit (< 10 % of the window or above it) is ignored with a WARN instead of wedging the route; _effort_on_wire is wrapped at the MODELINV emit site. Probe: --host-route / the resolved --cli-model / cli_version are refused on control characters or over 200 chars before the dry run (a newline rewrote effective_input_ceiling in the loaded YAML), the dry run uses the real write's kwargs, and the written catalog is re-parsed and its ceilings asserted before os.replace; CLI-reported numbers must be finite and bounded; the first step's budget estimate assumes the 1.8 tokenizer ratio until a step measures; the record stores the resolved binary ~-relative (the committed record too); the ceilingCalibration schema gains an if/then (probed_headless ⇒ claude-headless transport + probe_outcome) and maxLength on the cli_* fields; the effort dry-run test can never spawn the real CLI; AGC-6 prints its diagnostics on failure. The Fable review round 2 ticked the four acceptance criteria. Refuted or declined with evidence: 36 of the 60 run-1 findings and 6 of the 11 run-2 findings (audit-dissent-triage.md).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/.claude/adapters/cheval.py b/.claude/adapters/cheval.py
index 59fef198..32be62fd 100644
--- a/.claude/adapters/cheval.py
+++ b/.claude/adapters/cheval.py
@@ -16,6 +16,7 @@ import hashlib
 import json
 import logging
 import os
+import shlex
 import stat
 import sys
 import traceback
@@ -362,15 +363,16 @@ def _calibrate_hint(entry: Any, chain_entries: Any) -> Optional[str]:
     claude-headless hop names the chain's Anthropic HTTP entry with `--transport claude-headless` (the transport that
     measured the payload), and any other CLI hop, or a chain with no such entry, gets no hint: the CLI's own window
     refused the payload."""
+    # (r251-4 S6, audit n4: the model id is shell-quoted — the hint is a command an operator pastes)
     if getattr(entry, "adapter_kind", "http") != "cli":
-        return _PROBE_COMMAND.format(model=entry.model_id)
+        return _PROBE_COMMAND.format(model=shlex.quote(str(entry.model_id)))
     if _CLI_ADAPTER_BY_PROVIDER.get(getattr(entry, "provider", "")) != "claude-headless":
         return None
     head = next((e for e in (chain_entries or ())
                  if getattr(e, "adapter_kind", "http") != "cli" and getattr(e, "provider", "") == entry.provider), None)
     if head is None:
         return None
-    return f"{_PROBE_COMMAND.format(model=head.model_id)} --transport claude-headless"
+    return f"{_PROBE_COMMAND.format(model=shlex.quote(str(head.model_id)))} --transport claude-headless"
 
 
 _AGY_NOT_PLANNED_WARNED = False
@@ -844,7 +846,8 @@ def _lookup_max_input_tokens(
             else _hop_max_tokens(None, provider, model_id, hounfour)
         )
         _decision = _ceiling_input_bound(
-            model_config, max_tokens=_hop_budget, observed=_observed_for(provider, model_id),
+            model_config, max_tokens=_hop_budget,
+            observed=_observed_for(provider, model_id, context_window=model_config.get("context_window")),
         )
         _bound = _decision.value if _decision is not None else v3_ceiling
         if _streaming_killed and provider == "anthropic":
@@ -1782,9 +1785,10 @@ def cmd_invoke(args: argparse.Namespace) -> int:
     # The finally-clause emits a single envelope at function exit (success or
     # failure). Pre-resolution failures (handled above) deliberately do NOT
     # emit because no model invocation occurred. `models_requested` enumerates
-    # the entire resolved chain so audit consumers see the FULL intended walk
-    # shape, not just whichever entry happened to succeed.
-    # cycle-127 review r251-1 G1: a gated agy hop is planned around before models_requested is taken.
+    # the PLANNED chain — every hop the walk may dispatch, not just whichever
+    # entry happened to succeed; `models_requested` ∪ `models_not_planned` is
+    # the full resolved chain (cycle-127 review r251-1 G1: a gated agy hop is
+    # planned around before models_requested is taken; r251-4 S8, audit n2).
     _chain, _models_not_planned = _plan_around_agy(_chain, hounfour)
     if _models_not_planned and _auth_type_resolved is not None:
         _auth_type_resolved = _chain.entries[0].auth_type
@@ -2055,7 +2059,8 @@ def cmd_invoke(args: argparse.Namespace) -> int:
                     _preflight_cli_override
                     if isinstance(_preflight_cli_override, int) and _preflight_cli_override > 0 else None
                 ),
-                observed=_observed_for(_preflight_head.provider, _preflight_head.model_id),
+                observed=_observed_for(_preflight_head.provider, _preflight_head.model_id,
+                                       context_window=_preflight_head_cfg.get("context_window")),
                 policy=_ceiling_policy,
                 counter=_counter,
             )
@@ -2358,7 +2363,8 @@ def cmd_invoke(args: argparse.Namespace) -> int:
             ):
                 _hop_decision = _ceiling_input_bound(
                     _hop_entry, max_tokens=_hop_budget,
-                    observed=_observed_for(_entry.provider, _entry.model_id), policy=_ceiling_policy,
+                    observed=_observed_for(_entry.provider, _entry.model_id, context_window=_hop_entry.get("context_window")),
+                    policy=_ceiling_policy,
                 )
                 if _hop_decision is not None and not _hop_decision.calibrated and _hop_decision.probed:
                     _hop_unverified = (_walk_estimate or 0) > _hop_decision.probed
@@ -2932,6 +2938,21 @@ def cmd_invoke(args: argparse.Namespace) -> int:
             # parallel-dispatch races. Fail-soft; no-op when env var unset.
             _vq_write_sidecar(_vq_envelope)
 
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
             try:
                 _emit_modelinv(
                     models_requested=_modelinv_models_requested,
@@ -2954,17 +2975,10 @@ def cmd_invoke(args: argparse.Namespace) -> int:
                     effort=_effort,
                     # cycle-127 FR-2 (SDD D-2.5): caller | catalog | extra | none.
                     effort_source=_effort_source,
-                    # cycle-127 D-2.6: the wire value on the hop that answered
-                    # (the primary when none did), from that adapter's wire_effort
-                    # hook (r251-1 C5) — None where the adapter sends no effort.
                     # cycle-127 review r251-1 G1: hops planned around (never dispatched).
                     models_not_planned=_models_not_planned or None,
-                    effort_effective=_effort_on_wire(
-                        *(_modelinv_state["final_model_id"].split(":", 1)
-                          if ":" in str(_modelinv_state.get("final_model_id") or "")
-                          else (resolved.provider, resolved.model_id)),
-                        _effort, hounfour,
-                    ),
+                    # cycle-127 D-2.6 — None where the adapter sends no effort (derived above, r251-4 S8).
+                    effort_effective=_effort_effective_emit,
                     # cycle-124 FR-4: prompt-cache telemetry.
                     tokens_cache_read=_modelinv_state.get("tokens_cache_read"),
                     tokens_cache_creation=_modelinv_state.get("tokens_cache_creation"),
diff --git a/.claude/data/schemas/model-config-v3.schema.json b/.claude/data/schemas/model-config-v3.schema.json
index fc3002f9..f31d4c0e 100644
--- a/.claude/data/schemas/model-config-v3.schema.json
+++ b/.claude/data/schemas/model-config-v3.schema.json
@@ -285,19 +285,23 @@
         "method": {
           "type": "string",
           "enum": ["probed_api", "probed_headless"],
+          "maxLength": 200,
           "description": "cycle-127 FR-3 (SDD D-3.8): how a probe measured the bound — tools/ceiling-probe-live.py through the API or through the headless CLI (--transport claude-headless). Absent on entries never probed by the tool."
         },
         "transport": {
           "type": "string",
           "enum": ["api", "claude-headless"],
+          "maxLength": 200,
           "description": "cycle-127 FR-3: the probe transport that measured the bound."
         },
         "cli_version": {
           "type": ["string", "null"],
+          "maxLength": 200,
           "description": "cycle-127 FR-3: `claude --version` of the CLI the headless probe ran (null when it could not be read)."
         },
         "cli_model": {
           "type": "string",
+          "maxLength": 200,
           "description": "cycle-127 FR-3: the model id the CLI ran (the Bedrock inference-profile id when the route is Bedrock)."
         },
         "measured_input_tokens": {
@@ -308,8 +312,14 @@
         "probe_outcome": {
           "type": "string",
           "enum": ["clean", "partial"],
-          "description": "cycle-127 r251-1: the outcome of the probe whose bound this entry carries — clean (a verified accept bracketed by a size rejection within the tolerance, nothing failed) or partial (budget cap, an unverified or failed attempt, or an unbracketed bound; written only when the operator vouches for the last verified accept: tools/ceiling-probe-live.py --write-partial-as-operator-set). Optional; absent on entries never written by the tool."
+          "description": "cycle-127 r251-1: the outcome of the probe whose bound this entry carries — clean (a verified accept bracketed by a size rejection within the tolerance, nothing failed) or partial (budget cap, an unverified or failed attempt, or an unbracketed bound; written only when the operator vouches for the last verified accept: tools/ceiling-probe-live.py --write-partial-as-operator-set). Required when method is probed_headless (r251-4); absent on entries never written by the tool."
         }
+      },
+      "if": {"required": ["method"], "properties": {"method": {"const": "probed_headless"}}},
+      "then": {
+        "$comment": "cycle-127 r251-4 (n35/n48): a headless-probed bound names its transport and the probe outcome it carries.",
+        "required": ["transport", "probe_outcome"],
+        "properties": {"transport": {"const": "claude-headless"}}
       }
     },
     "streamingRecovery": {
diff --git a/.claude/scripts/flatline-orchestrator.sh b/.claude/scripts/flatline-orchestrator.sh
index 3e66df85..93704cff 100755
--- a/.claude/scripts/flatline-orchestrator.sh
+++ b/.claude/scripts/flatline-orchestrator.sh
@@ -527,7 +527,7 @@ _agy_opted_in() {  # true only for a YAML boolean true at hounfour.headless.agy_
 
 _tertiary_routes_to_agy() {  # <model> → 0 when cheval would dispatch it through agy (lib/agy-gate-lib.sh routes_to_agy:
     # the gemini-headless hop by name, or a Google model under hounfour.headless.mode cli-only — env wins, as cheval's)
-    routes_to_agy "$1" "$(agy_headless_mode "$CONFIG_FILE")"
+    routes_to_agy "$1" "$(agy_headless_mode "$CONFIG_FILE")" "$CONFIG_FILE"   # (r251-4: project aliases resolved first)
 }
 
 tertiary_opt_in_skip_reason() {  # prints the skip line and returns 0 when the configured tertiary is gated off
diff --git a/.claude/scripts/loa-status.sh b/.claude/scripts/loa-status.sh
index 4f039802..b85e6338 100755
--- a/.claude/scripts/loa-status.sh
+++ b/.claude/scripts/loa-status.sh
@@ -797,8 +797,18 @@ _providers_config_file() {  # the Loa config the Providers block reads (bats-gat
   fi
 }
 # cycle-127 FR-1 (SDD D-1.5; review r251-1 G2): the one agy route predicate (agy_opted_in, routes_to_agy)
+# (r251-4: a partial install without the lib must not abort /loa under set -e — fail-closed stubs instead, as
+# adversarial-review.sh K4: the opt-in reads off and the gemini-headless hop is recognised by name only; said once on
+# stderr in human mode, never under --json)
 # shellcheck source=lib/agy-gate-lib.sh
-source "$SCRIPT_DIR/lib/agy-gate-lib.sh"
+if ! { [[ -f "$SCRIPT_DIR/lib/agy-gate-lib.sh" ]] && source "$SCRIPT_DIR/lib/agy-gate-lib.sh"; } \
+   || ! declare -F routes_to_agy >/dev/null 2>&1; then
+  [[ "$JSON_OUTPUT" == "true" ]] || echo "WARN: $SCRIPT_DIR/lib/agy-gate-lib.sh not loaded — the agy opt-in reads off (fail closed); reinstall the framework (/update-loa)" >&2
+  AGY_OPT_IN_NOTE="agy: opt-in (disabled; hounfour.headless.agy_opt_in)"
+  agy_opted_in() { return 1; }
~~~~

## I05 — fix-commit — 2026-10-07

- reference: c2ef75816c89
- files: .claude/skills/bridgebuilder-review/dist/.build-manifest.json,docs/migration/v2.0-model-generation-floor.md,tests/unit/adversarial-review-companion.bats,tests/unit/loa-status-providers.bats

Summary:

fix(cycle-127): sprint-251 audit round r251-5 + sprint close — one permission rule across the three opt-in readers (MED-001): the bash lib and Bridgebuilder's readAgyGate now refuse, like cheval's loader, a .loa.config.yaml not owned by the current user or writable by its group or others (off, one WARN naming the file and the reason; group-writable is refused unconditionally — the private-group e…

Evidence:

~~~~diff
commit c2ef75816c89c065be6d5cfc51b8c24de31713a0
Date: 2026-10-08T06:06:12+11:00

fix(cycle-127): sprint-251 audit round r251-5 + sprint close — one permission rule across the three opt-in readers (MED-001): the bash lib and Bridgebuilder's readAgyGate now refuse, like cheval's loader, a .loa.config.yaml not owned by the current user or writable by its group or others (off, one WARN naming the file and the reason; group-writable is refused unconditionally — the private-group exception is gone, LOW-001); static-auth markers take precedence over a throttle match that rests on "please wait" alone (LOW-003); the AGC-6 batch failure's root cause (LOW-004) — loa-status fed jq a non-JSON document from workflow-state.sh under concurrent test runs — fixed in the script with a regression case; conformance rows for world-/group-writable configs on every reader; CHANGELOG, migration addendum and SDD D-1.1/D-1.11 now document the install-root anchor, the trust check, the exact-tag/alias/merge-key rule, the probe writer's input validation and re-parse, and the merge block under a config read error (LOW-002). Sprint 251 closed: ledger status completed, run state COMPLETE, epic bd-um3f and tasks closed, sprint.md round sections r251-4/r251-5; the Fable review (round 2) and audit (round 1) both APPROVED with CONSISTENT verdict trailers; COMPLETED marker written by the auditor.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/.claude/skills/bridgebuilder-review/dist/.build-manifest.json b/.claude/skills/bridgebuilder-review/dist/.build-manifest.json
index 748c5fef..44cfb788 100644
--- a/.claude/skills/bridgebuilder-review/dist/.build-manifest.json
+++ b/.claude/skills/bridgebuilder-review/dist/.build-manifest.json
@@ -1,7 +1,7 @@
 {
   "version": "1.0",
-  "generated_at": "2026-10-07T17:20:51Z",
-  "source_hash": "0b13c028279fb2fd9257945e270574ba06f929711407f2467f449779d10a5757",
+  "generated_at": "2026-10-07T18:59:38Z",
+  "source_hash": "6b1183fa06303eb069149ca39c939e6f77fd81320e3c5165e658debebc57353f",
   "file_count": 42,
   "files": [
     {
@@ -46,7 +46,7 @@
     },
     {
       "path": ".claude/skills/bridgebuilder-review/resources/config.ts",
-      "sha256": "e3b92e4108564f727d229074c89996ebd0e4bddbaa5944d75a3739d94c0438ef"
+      "sha256": "e740d4d5fa9c740cecb2312980b2c8cce014ebba46aa6c30f064c90159c6770a"
     },
     {
       "path": ".claude/skills/bridgebuilder-review/resources/core/cache.ts",
diff --git a/docs/migration/v2.0-model-generation-floor.md b/docs/migration/v2.0-model-generation-floor.md
index 64bd6671..9f8d2d71 100644
--- a/docs/migration/v2.0-model-generation-floor.md
+++ b/docs/migration/v2.0-model-generation-floor.md
@@ -291,8 +291,13 @@ ### Cycle-127 addendum — operator decisions (unreleased)
   own chain walk skips such a hop inside a fallback chain (`planned: false, reason:
   opt_in_required`) and walks on; a chain that is agy alone, like a direct `--model
   gemini-headless`, refuses with `INVALID_CONFIG`. The key is read from
-  `.loa.config.yaml` alone (a framework defaults file cannot opt you in); a quoted
-  `"true"` stays off and WARNs once. Set it `true` only where `agy` is installed and
+  `.loa.config.yaml` alone (a framework defaults file cannot opt you in) — cheval from its
+  own install root, never a cwd-ancestor file — and only the scalar written exactly
+  `true` opts in: a quoted `"true"`, `yes`/`on`/`True`, an alias or a merge key read off
+  in every reader with one WARN. A config you do not own, or that your group or others
+  can write, is ignored by every reader (off, one WARN naming the file and the reason):
+  `chmod 644 .loa.config.yaml` if your opt-in "does not take". Bridgebuilder blocks the
+  merge when it cannot read the config at all (never a smaller quorum). Set it `true` only where `agy` is installed and
   OAuth-authed, knowing the argv exposure. With it on, behaviour is exactly as before.
 - **Opus 5.5 effort default.** See the cycle-126 bullet above: `claude-opus-5-5` carries
   `params.default_effort: high`; `--effort` overrides. Effort is resolved once for the
@@ -313,7 +318,9 @@ ### Cycle-127 addendum — operator decisions (unreleased)
   `cli_version`, `cli_model`, `measured_input_tokens`, `probe_outcome`, `sample_size`,
   `calibrated_at` and a `reprobe_trigger` naming the API-transport probe. The record is
   always written; a *partial* record reaches the catalog only under
-  `--write-partial-as-operator-set`. The bisection steps in measured tokens (the filler
+  `--write-partial-as-operator-set`; the writer refuses operator strings (`--host-route`,
+  `--cli-model`, the CLI version) with control characters before any spend and re-parses
+  the produced YAML before it replaces the catalog. The bisection steps in measured tokens (the filler
   is rescaled by the observed tokenizer ratio); the CLI's own pre-flight rejections cost
   nothing and are charged nothing (`charged_usd`, `charge_basis` per sample). Use it
   on hosts where the direct API is unreachable (this repo's primary host: KF-040) and the
diff --git a/tests/unit/adversarial-review-companion.bats b/tests/unit/adversarial-review-companion.bats
index 5585ae46..0ee50563 100644
--- a/tests/unit/adversarial-review-companion.bats
+++ b/tests/unit/adversarial-review-companion.bats
@@ -49,6 +49,9 @@ _place_marker() {  # <tmp> <marker> → 0 placed; 1 (named, SPRINT cleared) when
     mv -f -- "$1" "$2"
 }
 setup() {
+    # (r251-5 U1/U2: every agy opt-in reader refuses a group- or world-writable config — fixtures are written owner-only
+    # whatever the host umask; a `>` redirect under umask 002 makes 0664)
+    umask 022
     # the sprint id and its directory come FIRST: teardown runs on any setup failure, and a delete
     # target derived from an unset id would be the a2a root (fourth run, chunk c C-001)
     SPRINT="sprint-comp-$$"
diff --git a/tests/unit/loa-status-providers.bats b/tests/unit/loa-status-providers.bats
index ee0de252..4a7ee0b2 100644
--- a/tests/unit/loa-status-providers.bats
+++ b/tests/unit/loa-status-providers.bats
@@ -9,6 +9,9 @@ bats_require_minimum_version 1.5.0
 # =============================================================================
 
 setup() {
+  # (r251-5 U1/U2: every agy opt-in reader refuses a group- or world-writable config — fixtures are written owner-only
+  # whatever the host umask; a `>` redirect under umask 002 makes 0664)
+  umask 022
   PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
   STATUS="$PROJECT_ROOT/.claude/scripts/loa-status.sh"
   T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/lsp.XXXXXX")"
@@ -251,3 +254,13 @@ YAML
   [ "$status" -eq 0 ]
   [ "$(grep -c 'agy-gate-lib.sh.*not loaded' <<<"$stderr")" = 1 ] || { echo "stderr=$stderr"; return 1; }
 }
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

## I06 — fix-commit — 2026-10-07

- reference: 263a8d4c469b
- files: .claude/adapters/cheval.py,.claude/skills/bridgebuilder-review/dist/.build-manifest.json,docs/migration/v2.0-model-generation-floor.md

Summary:

fix(cycle-127): sprint-251 Bridgebuilder round r251-6 — the pass on PR #1275 (two voices planned, the google voice not planned, verdict quality APPROVED 2/2): a correct user-private-group exception in all three opt-in readers (a 0664 config is trusted only when its gid is the owner's primary gid, the group is named like the user and has no other members — Ubuntu umask-002 checkouts opt in again,…

Evidence:

~~~~diff
commit 263a8d4c469b7946bf9923d449d69b930c9aee11
Date: 2026-10-08T07:38:08+11:00

fix(cycle-127): sprint-251 Bridgebuilder round r251-6 — the pass on PR #1275 (two voices planned, the google voice not planned, verdict quality APPROVED 2/2): a correct user-private-group exception in all three opt-in readers (a 0664 config is trusted only when its gid is the owner's primary gid, the group is named like the user and has no other members — Ubuntu umask-002 checkouts opt in again, shared groups and world-writable stay refused), the trust check fstat's the descriptor it read (TOCTOU) and guards a missing os.geteuid, the provider-map overlay anchors to the same install root as the opt-in read, an alias/non-mapping ancestor of the key WARNs once in every reader, the Python no-PyYAML fallback applies the yq-flavour check, the "both rungs set" effort WARN fires only for CLI entries, _plan_around_agy uses dataclasses.replace and a regression test pins that an all-agy chain is returned whole (the claimed empty-chain IndexError is refuted), and the conformance test's TypeScript leg runs the Bridgebuilder skill's pinned tsx with a clear skip when it is absent (the Shell Tests CI failure: `npx --no-install tsx` on a bare runner printed nothing). Release notes for 2.0.0-rc.3 drafted; CHANGELOG, addendum and SDD state the user-private-group rule.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/.claude/adapters/cheval.py b/.claude/adapters/cheval.py
index 32be62fd..86550e9e 100644
--- a/.claude/adapters/cheval.py
+++ b/.claude/adapters/cheval.py
@@ -408,16 +408,15 @@ def _plan_around_agy(chain: Any, hounfour: Dict[str, Any]) -> Tuple[Any, List[Di
     _loader.warn_agy_available_once()   # (SDD D-1.7 / r251-1 G18: once per process, a PATH lookup only)
     if len(agy) == len(chain.entries):
         return chain, []
-    from loa_cheval.routing.types import ResolvedChain as _RC
-    kept = tuple(e for e in chain.entries if e not in agy)
+    kept = [e for e in chain.entries if e not in agy]
     skipped = [{"model": e.canonical, "provider": e.provider, "reason": "opt_in_required"} for e in agy]
     if not _AGY_NOT_PLANNED_WARNED:
         _AGY_NOT_PLANNED_WARNED = True
         logger.warning(
             "agy hop(s) %s not planned: the agy route is opt-in (hounfour.headless.agy_opt_in is not true) — "
             "walking the remaining hop(s) %s", ", ".join(x["model"] for x in skipped), ", ".join(e.canonical for e in kept))
-    return _RC(primary_alias=chain.primary_alias, entries=kept, headless_mode=chain.headless_mode,
-               headless_mode_source=chain.headless_mode_source), skipped
+    # (r251-6 V8, BB #4: every other ResolvedChain field is carried, and `entries` keeps its container type)
+    return _dc_replace(chain, entries=type(chain.entries)(kept)), skipped
 
 
 def _get_adapter_for_entry(entry: Any, hounfour: Dict[str, Any]):
@@ -965,14 +964,16 @@ def resolve_effort(
       ``none``    — nothing on the wire, the vendor default applies.
     The catalog is not schema-validated at load, so an invalid `default_effort`
     is skipped with one WARN (never a crash); an entry setting both
-    `params.default_effort` and `extra.effort` gets one WARN too.
+    `params.default_effort` and `extra.effort` gets one WARN too — a CLI entry only,
+    the one whose extra rung is read (r251-6 V7).
     """
     explicit = getattr(args, "effort", None)
     entry = entry if isinstance(entry, dict) else {}
     params = entry.get("params") if isinstance(entry.get("params"), dict) else {}
     extra = entry.get("extra") if isinstance(entry.get("extra"), dict) else {}
     extra_raw = extra.get("effort") or extra.get("reasoning_effort")
-    if "default_effort" in params and extra_raw:
+    # (r251-6 V7, BB #10: only a CLI entry reads the extra rung — on an HTTP entry it is inert, so there is no conflict)
+    if "default_effort" in params and extra_raw and _is_cli_entry(entry):
         _effort_warn_once((model_key, "both"),
                           "%s sets both params.default_effort and extra.effort; params.default_effort wins "
                           "(cycle-127 FR-2) — drop one", model_key)
diff --git a/.claude/skills/bridgebuilder-review/dist/.build-manifest.json b/.claude/skills/bridgebuilder-review/dist/.build-manifest.json
index 44cfb788..3a7f3fd6 100644
--- a/.claude/skills/bridgebuilder-review/dist/.build-manifest.json
+++ b/.claude/skills/bridgebuilder-review/dist/.build-manifest.json
@@ -1,7 +1,7 @@
 {
   "version": "1.0",
-  "generated_at": "2026-10-07T18:59:38Z",
-  "source_hash": "6b1183fa06303eb069149ca39c939e6f77fd81320e3c5165e658debebc57353f",
+  "generated_at": "2026-10-07T20:31:07Z",
+  "source_hash": "b7ee6626d8931660b817d67e7fe35c912235070b79392b6c2e6fc18d1c5137cc",
   "file_count": 42,
   "files": [
     {
@@ -46,7 +46,7 @@
     },
     {
       "path": ".claude/skills/bridgebuilder-review/resources/config.ts",
-      "sha256": "e740d4d5fa9c740cecb2312980b2c8cce014ebba46aa6c30f064c90159c6770a"
+      "sha256": "a0b586a502a0015646aa8d0d6450ce74440a699ef9a2e7769d21f1cf6f846161"
     },
     {
       "path": ".claude/skills/bridgebuilder-review/resources/core/cache.ts",
diff --git a/docs/migration/v2.0-model-generation-floor.md b/docs/migration/v2.0-model-generation-floor.md
index 9f8d2d71..5b23bc8a 100644
--- a/docs/migration/v2.0-model-generation-floor.md
+++ b/docs/migration/v2.0-model-generation-floor.md
@@ -294,9 +294,11 @@ ### Cycle-127 addendum — operator decisions (unreleased)
   `.loa.config.yaml` alone (a framework defaults file cannot opt you in) — cheval from its
   own install root, never a cwd-ancestor file — and only the scalar written exactly
   `true` opts in: a quoted `"true"`, `yes`/`on`/`True`, an alias or a merge key read off
-  in every reader with one WARN. A config you do not own, or that your group or others
-  can write, is ignored by every reader (off, one WARN naming the file and the reason):
-  `chmod 644 .loa.config.yaml` if your opt-in "does not take". Bridgebuilder blocks the
+  in every reader with one WARN. A config you do not own, that others can write, or that
+  a group other than your own user-private group can write, is ignored by every reader
+  (off, one WARN naming the file and the reason) — a umask-002 checkout on a
+  user-private-group host still opts in; on a shared-group host `chmod 644
+  .loa.config.yaml` if your opt-in "does not take". Bridgebuilder blocks the
   merge when it cannot read the config at all (never a smaller quorum). Set it `true` only where `agy` is installed and
   OAuth-authed, knowing the argv exposure. With it on, behaviour is exactly as before.
 - **Opus 5.5 effort default.** See the cycle-126 bullet above: `claude-opus-5-5` carries
~~~~

## I07 — fix-commit — 2026-10-13

- reference: 2bcf0e40401d
- files: .loa.config.yaml.example

Summary:

fix(cycle-128): sprint-252 review round r252-1 — the Fable review's three requested changes and one observation fix: the shipped .loa.config.yaml.example leaves interview.pacing commented so the per-mode default (rounds for thorough, batch for minimal) applies, with REFERENCE §Interview Modes stating the unset rule; dec-write-lib.sh classifies an explicit --file by its canonical path (live ledger…

Evidence:

~~~~diff
commit 2bcf0e40401df71bad441813e36840f22ab6c333
Date: 2026-10-13T14:00:27+11:00

fix(cycle-128): sprint-252 review round r252-1 — the Fable review's three requested changes and one observation fix: the shipped .loa.config.yaml.example leaves interview.pacing commented so the per-mode default (rounds for thorough, batch for minimal) applies, with REFERENCE §Interview Modes stating the unset rule; dec-write-lib.sh classifies an explicit --file by its canonical path (live ledger, a2a/*/decisions-pending.yaml, or fixture) so naming the live ledger never bypasses the CI/hook refusal, and a linked worktree refuses a live --file (two new bats incl. relative, absolute and dot-dot paths under CI, GITHUB_ACTIONS and LOA_HOOK_CONTEXT, plus import --from into the live ledger); the FR-8 operative-reference lint judges the clause before the verb in awk, so an exempt word after the command name no longer hides an operative line (fixture with seven sentences); tools/check-round-independence.sh rejects a multi-value capture as a malformed-block violation (exit 1) instead of a jq crash (RI-11b). Dissent DISS-001 (jq index([x]) "never matches") refuted with evidence; DISS-C-001/002/003/004 fixed. Sprint 1 tasks ticked in sprint.md. Verification: 347/347 across 14 suites; budgets, sha256 lint, decisions validator and agents-md-gen --check green.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/.loa.config.yaml.example b/.loa.config.yaml.example
index a91cb9d6..1a9d5f32 100644
--- a/.loa.config.yaml.example
+++ b/.loa.config.yaml.example
@@ -97,7 +97,7 @@ plan_and_analyze:
 # Interview Depth Configuration (v1.41.0)
 # -----------------------------------------------------------------------------
 # Controls question depth, input style, and pacing across planning skills.
-# Default: thorough mode with rounds of plain-text discovery questions.
+# Default: thorough mode; pacing unset, so rounds of plain-text discovery questions.
 #
 # Construct override: Schema supports future construct manifest interview
 # overrides gated by trust tier (RFC #379). Not wired yet.
@@ -124,7 +124,8 @@ interview:
 
   # Question pacing. One key for the discovery interview, /architect Phase 2,
   # /sprint-plan Phase 2 and /chart; per_skill above still picks the mode.
-  # Unset: rounds for thorough, batch for minimal. An explicit value always wins.
+  # Left unset (the shipped default), it is rounds for thorough and batch for
+  # minimal; uncomment and set a value to pin it for every mode.
   #   rounds: each turn asks the whole frontier, every open question whose
   #     prerequisites are settled; a question that depends on another one still
   #     open waits for a later round. Questions are numbered across the session
@@ -137,7 +138,7 @@ interview:
   #   sequential: one question per turn, wait for the answer (the supported
   #     opt-out if you prefer one question at a time)
   #   batch: 3-6 numbered questions per turn, user responds freely
-  pacing: rounds   # sequential | batch | rounds
+  # pacing: rounds   # sequential | batch | rounds; unset = rounds for thorough, batch for minimal
 
   # Phase transition gates
   phase_gates:
~~~~

## I08 — fix-commit — 2026-10-13

- reference: 30727c9528fb
- files: .claude/data/agent-types.yaml,tests/unit/skill-capabilities.bats

Summary:

fix(cycle-128): sprint-253 review round r253-1 — the Fable review's HIGH and MEDIUM closed with tests, plus eight LOWs: the chart-researcher agent is read-only (Read, Grep, Glob, WebFetch; no Write, Edit or Bash) and returns its report as its final message, which the charting session writes verbatim to the report path before research-end runs as the secondary scope check (agent-types.yaml write_c…

Evidence:

~~~~diff
commit 30727c9528fb3402f84723444be9038a0909f680
Date: 2026-10-13T16:17:13+11:00

fix(cycle-128): sprint-253 review round r253-1 — the Fable review's HIGH and MEDIUM closed with tests, plus eight LOWs: the chart-researcher agent is read-only (Read, Grep, Glob, WebFetch; no Write, Edit or Bash) and returns its report as its final message, which the charting session writes verbatim to the report path before research-end runs as the secondary scope check (agent-types.yaml write_capable false; SKILL.md, REFERENCE.md and chart.md updated; CD-26/CD-26b); chart-ticket.sh close --consumed-by closes only a handed-off map with zero open rows and otherwise exits 1 writing nothing (CD-22 rewritten through handoff, CD-22b/CD-22c negatives); chart-unblock-probe.sh fails on files under the main tree's .run/ or .beads/ newer than its start marker, mirroring research-end, with the out-of-tree boundary stated (CD-27b); fence SP-1's merge/rebase/pull/cherry-pick pattern keeps the spike ref inside the verb's own shell segment so prose naming a merge and a spike path on one line passes (corpus B60/B61 allow; D73/D74 block the quoted and remote-prefixed refs), and the D-5.9 decided-spike unlock gains its trust-boundary comment and three bats cases (operator-decided row passes; agent-decided row and no row block); run-mode-ice.sh merge on a spike branch returns git's exit code on a conflict with a message naming the way out and uses --ff so merge.ff=only cannot refuse a diverged spike (two new ICE tests); hand-off tests pin the gate for a claimed ticket, a ticket waiting on a claimed prerequisite and a two-label ticket (CD-20b/c/d); the br stub parses trailing boolean flags and keeps its state when jq fails (CD-0); CD-14 skips as root; the charting-lint no-br map test no longer rewrites PATH (the missing .beads/ selects the skip path and the stub log proves br never ran); set_status cleans its temp file; a REFERENCE recovery row for a re-run after a failed br close. Dissent r253-1: two voices (codex-headless gpt-5.5-pro + claude-headless), 10 findings, 0 schema-rejected; DISS-001, C-001, C-002, C-003, C-004, C-005, C-007, C-008 and C-009 fixed or pinned, C-006 recorded as the documented fence misses, C-005's flag doubt refuted (br 0.2.6 has --slug, --dry-run and --external-ref). Sprint 2 tasks ticked in sprint.md; CHANGELOG Fixed and Security bullets. Verification: 552/552 across eleven suites (the seven Sprint 2 suites, validate-artifact, skill-capabilities, block-destructive-bash with the fence corpus, user-invoked-commands); check-prompt-budget exit 0; validate-skill-capabilities 37/37; agents-md-gen --check exit 0 (51 commands); check-no-swallowed-jq and check-no-raw-sha256sum OK.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/.claude/data/agent-types.yaml b/.claude/data/agent-types.yaml
index fa30a686..713346f1 100644
--- a/.claude/data/agent-types.yaml
+++ b/.claude/data/agent-types.yaml
@@ -25,4 +25,4 @@ agent_types:
   prompt-auditor-io:
     write_capable: false
   chart-researcher:
-    write_capable: true
+    write_capable: false
diff --git a/tests/unit/skill-capabilities.bats b/tests/unit/skill-capabilities.bats
index 334a4f14..b355cd14 100644
--- a/tests/unit/skill-capabilities.bats
+++ b/tests/unit/skill-capabilities.bats
@@ -849,7 +849,7 @@ cost-profile: moderate
     local data="$PROJECT_ROOT/.claude/data/agent-types.yaml"
     run yq -r '.agent_types | to_entries | map(.key + "=" + (.value.write_capable | tostring)) | join(" ")' "$data"
     [ "$status" -eq 0 ]
-    [ "$output" = "general-purpose=true claude=true fork=true loa-scout=false Plan=false Explore=false prompt-auditor=false prompt-auditor-io=false chart-researcher=true" ]
+    [ "$output" = "general-purpose=true claude=true fork=true loa-scout=false Plan=false Explore=false prompt-auditor=false prompt-auditor-io=false chart-researcher=false" ]
     local f
     for f in "$PROJECT_ROOT"/.claude/agents/*.md; do
         yq -e ".agent_types[\"$(basename "$f" .md)\"]" "$data" >/dev/null || { echo "unlisted: $f" >&2; return 1; }
@@ -864,7 +864,7 @@ cost-profile: moderate
     [ "$status" -eq 0 ]
     SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --skill w-scout
     [ "$status" -eq 1 ]
-    [[ "$output" == *"agent type 'loa-scout'"*"(general-purpose claude fork chart-researcher)"* ]]
+    [[ "$output" == *"agent type 'loa-scout'"*"(general-purpose claude fork)"* ]]
     SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --skill w-io
     [ "$status" -eq 1 ]
 }
~~~~

## I09 — fix-commit — 2026-10-13

- reference: 3b0f8bf38bd7
- files: .claude/scripts/validate-artifact.sh,README.md

Summary:

fix(cycle-128): sprint-254 review round r254-1 and the cycle's docs — the Fable review's MEDIUM and seven LOWs closed with tests, Task 3.6 and Task 3.E2E delivered: the glossary gate can no longer be satisfied by an alias line (validate-artifact.sh --type glossary fails an entry with more than six aliases and WARNs on an alias that shares no word with its term or definition and is not the term's…

Evidence:

~~~~diff
commit 3b0f8bf38bd7468326ed583ef68d539de2adc302
Date: 2026-10-13T18:22:52+11:00

fix(cycle-128): sprint-254 review round r254-1 and the cycle's docs — the Fable review's MEDIUM and seven LOWs closed with tests, Task 3.6 and Task 3.E2E delivered: the glossary gate can no longer be satisfied by an alias line (validate-artifact.sh --type glossary fails an entry with more than six aliases and WARNs on an alias that shares no word with its term or definition and is not the term's initials; the checker WARNs, advisory, when alias resolutions outnumber defined-term resolutions and keeps the alias column in --report; GV-20…24, GT-24/25); fences follow CommonMark through the new shared .claude/scripts/lib/md-fence.awk (an opener's character and length close it; code spans match backtick runs of equal length; GT-20/21/22/27/28, GV-23); the token shape admits one interior colon so the four decision: labels are checked (the kernel gained no token; GT-8b/8c); --json avoids jq 1.6-only features (GT-26); an orphan _Aliases_: line WARNs with its glossary line and no longer shadows a later alias (GT-23); RTC-9 builds its no-timeout shim from the entries of PATH (Homebrew, Nix and asdf hosts keep their tools) and red-test-check.sh prints (no output) inside an empty marker block (RTC-18); planning-sprints, reviewing-code and riding-codebase trimmed to 16,124 / 16,223 / 16,226 of 16,384 bytes without dropping a rule. Docs (Task 3.6, implementer H): CHANGELOG [Unreleased] reconciled into one release note for sprints 252–254 (Added / Changed / Fixed / Security grouped by FR, the review and audit rounds folded into the entries they correct, a Migration section for the pacing default, the Seams rule date, yq v4 and the operator-only commands); README what's-new block; hooks-reference.md "Decision surfaces" table (SessionStart decisions surface, ICE spike rule, fence SP-1, the FR-1.1 decided-spike unlock, the /chart interactive-only gate, the FR-8 lint, each with its accepted bypasses); scripts-reference.md rows for every new script; protocols-summary.md; grimoires/loa/sdd.md §10 Open Questions DEC column backfilled from the seeded ledger (DEC-0001…DEC-0016, DEC-0025, DEC-0030, DEC-0049, DEC-0051, DEC-0053; the validator WARN is gone); REPO-MAP.md regenerated with its checksum over the final .claude/ code (repo-map-gen.sh --validate exit 0); .claude/checksums.json refreshed for tracked files only; evals fixture copies of golden-path.sh and mount-loa.sh re-synced (sync-fixtures.sh --check exit 0). Task 3.E2E: grimoires/loa/a2a/sprint-254/e2e.md records G-1…G-7 with commands, artefacts and results (G-3 scored on a second rounds transcript, G-7 verified by one live harness run whose stream is saved; the archived cycle-127 plan fails two pre-existing required-section rules while the Seams rule adds only a WARN there). Sprint 3 tasks ticked in sprint.md; Sprint 3 implementer decisions seeded as proposed ledger rows. Verification on the final tree: the 22-suite run recorded in the review; check-prompt-budget exit 0; validate-skill-capabilities 37/37; agents-md-gen --check 51 commands; check-no-swallowed-jq and check-no-raw-sha256sum OK; sync-fixtures --check current; md-fence.awk parses under awk; bash -n on every changed script; shell-compat greps clean; check-glossary-terms.sh PASS on the live kernel (16 kept, 0 missing, 11/30 allowlisted, one advisory WARN); both glossaries, the sprint plan (seams + live beads cross-check), the PRD and the SDD validate.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/.claude/scripts/validate-artifact.sh b/.claude/scripts/validate-artifact.sh
index e9b951cc..69b0a6f3 100755
--- a/.claude/scripts/validate-artifact.sh
+++ b/.claude/scripts/validate-artifact.sh
@@ -67,8 +67,11 @@
 #               '## Language', then one-line '**Term**: definition' entries of
 #               at most two sentences and 300 characters; _Avoid_: and
 #               _Aliases_: only directly below an entry; no duplicate term or
-#               alias (case, '-', '_' and spaces folded); WARN on a path or file
-#               extension in '## Language'; PII scan
+#               alias (case, '-', '_' and spaces folded); at most six aliases
+#               per entry; WARN on an alias that shares no word with its term
+#               or definition and is not the term's initials; WARN on a path or
+#               file extension in '## Language'; CommonMark fences
+#               (lib/md-fence.awk); PII scan
 #   sprint also: with br and .beads/, no question bead carries a sprint: label
 #               or sits under a sprint epic (an info line without br)
 #
@@ -1249,15 +1252,21 @@ validate_spike() {
 # glossary: the framework or a project glossary (grimoires/loa/sdd.md D-6.4, §4.5)
 # =============================================================================
 GLOSSARY_MAX_CHARS=300
+GLOSSARY_MAX_ALIASES=6
 
 validate_glossary() {
-    local kind msg
+    local kind msg fence_src
+    # The CommonMark fence tracker shared with tools/check-glossary-terms.sh.
+    if ! fence_src="$(cat "${SCRIPT_DIR}/lib/md-fence.awk" 2>/dev/null)" || [[ -z "$fence_src" ]]; then
+        violations+=("cannot read ${SCRIPT_DIR}/lib/md-fence.awk; the glossary check needs it (reinstall the framework scripts)")
+        return
+    fi
     while IFS=$'\t' read -r kind msg; do
         case "$kind" in
             V) violations+=("$msg") ;;
             W) warnings+=("$msg") ;;
         esac
-    done < <(LC_ALL=C awk -v f="$FILE" -v max="$GLOSSARY_MAX_CHARS" '
+    done < <(LC_ALL=C awk -v f="$FILE" -v max="$GLOSSARY_MAX_CHARS" -v maxal="$GLOSSARY_MAX_ALIASES" "$fence_src"'
         function v(m) { printf "V\t%s:%d: %s\n", f, NR, m }
         function w(m) { printf "W\t%s:%d: %s\n", f, NR, m }
         # names compare as the drift check matches them: case and "-", "_", " " folded
@@ -1267,8 +1276,28 @@ validate_glossary() {
             if (norm(x) in seen) v(what " \"" x "\" duplicates " seen[norm(x)] "; each term and alias names one entry")
             else seen[norm(x)] = what " \"" x "\" (line " NR ")"
         }
-        /^[[:space:]]*(```|~~~)/ { fence = !fence; prev = "other"; next }
-        fence { next }
+        # word sets: a name splits on case-folded "-", "_" and spaces, prose on
+        # anything that is not a letter or digit; words under two characters drop
+        function words(x, set,   n, i, parts) {
+            split("", set); n = split(x, parts, / /)
+            for (i = 1; i <= n; i++) if (length(parts[i]) >= 2) set[parts[i]] = 1
+        }
+        function plural_eq(a, b) { return a == b || a "s" == b || a "es" == b || b "s" == a || b "es" == a }
+        # An alias names the same thing as its entry, so it shares a word with
+        # the term or the definition, or it is the initials of the term
+        # ("KF" for Known failure); anything else is a name the entry never explains.
+        function alias_related(al, term, def,   aw, tw, x, y, ini, n, i, parts) {
+            words(norm(al), aw)
+            words(norm(term), tw)
+            for (x in aw) for (y in tw) if (plural_eq(x, y)) return 1
+            def = tolower(def); gsub(/[^a-z0-9]+/, " ", def); words(def, tw)
+            for (x in aw) for (y in tw) if (plural_eq(x, y)) return 1
+            n = split(norm(term), parts, / /); ini = ""
+            for (i = 1; i <= n; i++) ini = ini substr(parts[i], 1, 1)
+            x = norm(al); gsub(/ /, "", x)
+            return n >= 2 && x == ini
+        }
+        md_fence($0) { prev = "other"; next }
         /^# / {
             if (!h1) { h1 = NR; if ($0 !~ /^# Glossary: [^[:space:]]/) w("the H1 is not \"# Glossary: <name>\"") }
             prev = "other"; next
@@ -1296,7 +1325,7 @@ validate_glossary() {
             if (length(c) > max) v("the definition of \"" t "\" is " length(c) " characters, over " max "; shorten it")
             s = d " "; n = gsub(/[.!?]+[)"]*[[:space:]]/, "&", s); if (n == 0) n = 1
             if (n > 2) v("the definition of \"" t "\" has " n " sentences; at most two")
-            prev = "entry"; seen_avoid = 0; seen_alias = 0; next
+            prev = "entry"; seen_avoid = 0; seen_alias = 0; n_alias = 0; next
         }
         /^_(Avoid|Aliases)_:/ {
             k = ($0 ~ /^_Avoid_:/) ? "Avoid" : "Aliases"
@@ -1307,7 +1336,14 @@ validate_glossary() {
             if (a !~ /[^[:space:]]/) v("an empty _" k "_: line")
             if (k == "Aliases") {
                 gsub(/`/, "", a); m = split(a, parts, /,/)
-                for (i = 1; i <= m; i++) { p = parts[i]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", p); claim(p, "alias") }
+                for (i = 1; i <= m; i++) {
+                    p = parts[i]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", p)
+                    if (p == "") continue
+                    n_alias++
+                    claim(p, "alias")
+                    if (!alias_related(p, t, d)) w("alias \"" p "\" of \"" t "\" shares no word with the term or its definition and is not its initials; name it in the definition, or give it its own entry")
+                }
+                if (n_alias > maxal) v("\"" t "\" has " n_alias " aliases, over " maxal "; an alias list is not a place to resolve tokens, so define the extra names as entries or allowlist the code identifiers")
             }
             prev = "annot"; next
         }
diff --git a/README.md b/README.md
index 0a3e07ee..f9e6acb3 100644
--- a/README.md
+++ b/README.md
@@ -19,6 +19,18 @@ ## What's new in v2.0.0-rc.2 (release candidate)
 
 The 2.0 line ships as a **pre-release**: it soaks with real users, fixes land as `-rc.N`, and `2.0.0` is promoted once the exit criteria in the [rc.1 release notes](grimoires/loa/reports/release-notes-2.0.0-rc.1.md) are met. Stable users can stay on `v1.202.1` until then.
 
+**Unreleased — decision surfaces** (cycle-128, [CHANGELOG](CHANGELOG.md)):
+
+- **Decision maps**: `/chart <slug>` maps an effort that spans more than one cycle as `question` tickets and a map doc in `grimoires/loa/maps/`. It plans and never builds, and `/plan` reports the `charting` phase.
+- **Decision ledger**: every planning decision becomes a `DEC` row in `grimoires/loa/decisions.yaml` with who decided it. Agent decisions stay `proposed` until you confirm them with `/decisions`.
+- **Rounds and attribution**: the interview asks every question whose prerequisites are settled in one round, each with a recommended answer. Facts are looked up, never asked; decisions are yours, and PR bodies list the ones taken on your behalf.
+- **Spike tickets**: a question talk cannot settle becomes a prototype ticket on a `spike/<slug>` branch that is pushed, never merged and never opened as a PR.
+- **Glossaries**: `.claude/loa/GLOSSARY.md` and a project `GLOSSARY.md`; `tools/check-glossary-terms.sh` fails CI when a kernel term has no entry.
+- **Test discipline**: sprint plans name their Seams Under Test, and `red-test-check.sh` proves a bug fix's test failed before the fix and passes after it.
+- **Operator-only commands**: `/decisions`, `/contribute`, `/run-halt`, `/loa-eject` and three others carry `disable-model-invocation`, so only you can run them.
+
+Upgrading: `interview.pacing` unset now means rounds in `thorough` mode, and plans dated from 2026-10-13 need the Seams block (see the CHANGELOG Migration notes).
+
 **rc.2 — friction floor** (cycle-125, [notes](grimoires/loa/reports/release-notes-2.0.0-rc.2.md)): the destructive-command fence stops blocking cache/scratch cleanups it cannot lose data on (corpus-gated, 49 benign / 60 dangerous rows), the big planning artefacts read by section (`notes-guard.sh read --file F --section 'Sprint N'`), `/run` refuses to start a run it cannot finish (`run-preflight.sh`, eight predicates, the fix named) and the next session is told how to resume, `/loa` shows provider health (breakers, credential presence, CLI hops) and artefact sizes, and the ids the fleet actually calls are priced (dated releases, aliases, CLI hops) with the unpriced share always visible. No new configuration key.
 
 **Unreleased — full size** (cycle-126, [migration addendum](docs/migration/v2.0-model-generation-floor.md#cycle-126-addendum--full-size-two-voices-context-class-current-generation-unreleased)): size limits come from the catalog entry actually resolved (the probed input bound until you calibrate it), every dissent gets a second voice from the other model family, context-clearing thresholds follow the session model's window, `opus` → `claude-opus-5-5` and `cheap` → `claude-sonnet-5`, and `/loa` shows what the implement gate can and cannot see.
~~~~

## I10 — fix-commit — 2026-10-13

- reference: befd511de798
- files: .claude/scripts/validate-artifact.sh,.loa.config.yaml.example

Summary:

fix(cycle-128): sprint-254 audit round r254-2 — the Paranoid Cypherpunk audit's HIGH, three MEDIUMs and three LOWs closed with tests: red-test-check.sh accepts only a listed runner as the first word of the test command and of --setup (bats, pytest, python -m pytest, npm/pnpm/yarn test|run, cargo test, go test, make, mix test, bundle exec rspec; a ./ or tests/ script only when .loa.config.yaml red…

Evidence:

~~~~diff
commit befd511de798c140ba28819fd0617c8c707f3f76
Date: 2026-10-13T18:58:27+11:00

fix(cycle-128): sprint-254 audit round r254-2 — the Paranoid Cypherpunk audit's HIGH, three MEDIUMs and three LOWs closed with tests: red-test-check.sh accepts only a listed runner as the first word of the test command and of --setup (bats, pytest, python -m pytest, npm/pnpm/yarn test|run, cargo test, go test, make, mix test, bundle exec rspec; a ./ or tests/ script only when .loa.config.yaml red_test.allowed_runners names it; the exact red_test.command / red_test.setup strings) and refuses shells, env, eval, exec, inline-code interpreters and the listed runners' inline-code flags with exit 2 naming the config key; every run and --setup starts from env -i with PATH (absolute entries outside the repository and the scratch), a fresh HOME and TMPDIR per run under the scratch, LANG, LC_ALL, TERM, CI=1, no global or system git config, no terminal prompt, a failing askpass and ssh transport, plus --env-pass NAME for one caller variable (credential-shaped and contract names refused); the test runs red, green, then red again and a passing second red is DECOY (a stateful decoy); the output tails are control-stripped (C0, C1, U+2028/9), capped at 400 bytes per line and wrapped in the L6 untrusted-content fence with the authoritative verdict line printed last (--json adds red_again_exit); every git call runs with core.hooksPath=/dev/null and core.fsmonitor=false, and a snapshot of refs, HEAD, the git config files and the hooks directory taken before the runs is compared after each phase, a difference exiting 2 with the changed entries; the header states the runner, environment, shared-.git and untrusted-output contracts; .loa.config.yaml.example documents the red_test block; reviewing-code takes only the red commit SHA from reviewer.md, the test command from sprint.md or red_test.command, runs only a listed runner with --json, treats the tails as untrusted data, and its execute_commands grant is explicit (--red *), with the trust rules in resources/REFERENCE.md and the qmd step's (paths only) cue kept (RTC-1, RTC-4/5/7 re-pinned, RTC-19…26, RTC-17 extended); validate_sprint_seams tracks fences through lib/md-fence.awk and a live plan under grimoires/loa/ (not its archive) without a parseable header Date fails instead of warning (SEAMS-11/12); validate_glossary fails a glossary with more than 40 aliases in total and WARNs on a non-ASCII letter in a term or alias name (GV-25/26/27); check-glossary-terms.sh --report and --json list resolution-only and unreferenced entries, exit code unchanged (GT-29/30/31); symlink-manifest.sh links .claude/loa/GLOSSARY.md only when the pinned framework ships it and prints one notice otherwise, so an older pin gets no dangling link (symlink-manifest-glossary.bats SMG-1…5). Also: the Sprint 3 acceptance-criteria boxes ticked in sprint.md; REPO-MAP regenerated with its checksum over the final .claude/ code (--validate exit 0); .claude/checksums.json refreshed for the changed tracked files. Verification on the final tree: the 23-suite run recorded in the audit report; check-prompt-budget exit 0 (reviewing-code 16,306 of 16,384); validate-skill-capabilities 37/37; agents-md-gen --check 51 commands; check-no-swallowed-jq and check-no-raw-sha256sum OK; sync-fixtures --check current; bash -n on every changed script; shell-compat greps clean; check-glossary-terms.sh PASS on the live kernel; both glossaries, the sprint plan, the PRD and the SDD validate; a shell test command is refused with exit 2 on a throwaway repository.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/.claude/scripts/validate-artifact.sh b/.claude/scripts/validate-artifact.sh
index 69b0a6f3..067c9f61 100755
--- a/.claude/scripts/validate-artifact.sh
+++ b/.claude/scripts/validate-artifact.sh
@@ -866,17 +866,40 @@ validate_sprint_deferred() {
 # Gated on the plan header's **Date:** (the first one before the first H2): from
 # SEAMS_REQUIRED_FROM on, every '## Sprint N' block (up to the next H2) must carry
 # the block with at least one table row below its separator line; older and
-# undated plans WARN once. Headings inside fenced code do not count.
+# undated plans WARN once, except that a live plan (under grimoires/loa/, not its
+# archive/) without a parseable header date fails. Fenced code is tracked by
+# lib/md-fence.awk (CommonMark lengths and characters); headings inside it do not count.
 SEAMS_REQUIRED_FROM="2026-10-13"
 
 validate_sprint_seams() {
+    local fence_src
+    if ! fence_src="$(cat "${SCRIPT_DIR}/lib/md-fence.awk" 2>/dev/null)" || [[ -z "$fence_src" ]]; then
+        violations+=("cannot read ${SCRIPT_DIR}/lib/md-fence.awk; the sprint Seams check needs it (reinstall the framework scripts)")
+        return 0
+    fi
     local plan_date
-    plan_date="$(awk '/^## / { exit } /^\*\*Date:?\*\*:?/ { print; exit }' "$FILE" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || true)"
+    plan_date="$(LC_ALL=C awk "$fence_src"'
+        md_fence($0) { next }
+        /^## / { exit }
+        /^\*\*Date:?\*\*:?/ { if (match($0, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) print substr($0, RSTART, RLENGTH); exit }
+    ' "$FILE")"
+    # A live plan (under grimoires/loa/, not its archive) must carry a parseable header date,
+    # or the gate below would fail open; archived plans and fixtures keep the WARN.
+    local canon="" root=""
+    canon="$(cd "$(dirname -- "$FILE")" 2>/dev/null && pwd -P)/$(basename -- "$FILE")" || canon=""
+    root="$(cd "$PROJECT_ROOT" 2>/dev/null && pwd -P)" || root=""
+    if [[ -z "$plan_date" && -n "$root" ]]; then
+        case "$canon" in
+            "${root}/grimoires/loa/archive/"*) ;;
+            "${root}/grimoires/loa/"*)
+                violations+=("a sprint plan carries **Date:** YYYY-MM-DD in its header (before the first '## ' heading); ${FILE} has none that parses, so the Seams gate (from ${SEAMS_REQUIRED_FROM}) cannot be judged")
+                return 0 ;;
+        esac
+    fi
     local missing
-    missing="$(awk '
+    missing="$(LC_ALL=C awk "$fence_src"'
         function emit() { if (insp && rows < 1) printf "%s (line %d)\n", head, hl }
-        /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
-        fence { next }
+        md_fence($0) { next }
         /^## / {
             emit(); insp = 0
             if ($0 ~ /^## Sprint [0-9]/) { insp = 1; head = substr($0, 4); hl = NR; rows = 0; inseam = 0 }
@@ -1253,6 +1276,7 @@ validate_spike() {
 # =============================================================================
 GLOSSARY_MAX_CHARS=300
 GLOSSARY_MAX_ALIASES=6
+GLOSSARY_MAX_ALIASES_TOTAL=40
 
 validate_glossary() {
     local kind msg fence_src
@@ -1266,13 +1290,16 @@ validate_glossary() {
             V) violations+=("$msg") ;;
             W) warnings+=("$msg") ;;
         esac
-    done < <(LC_ALL=C awk -v f="$FILE" -v max="$GLOSSARY_MAX_CHARS" -v maxal="$GLOSSARY_MAX_ALIASES" "$fence_src"'
+    done < <(LC_ALL=C awk -v f="$FILE" -v max="$GLOSSARY_MAX_CHARS" -v maxal="$GLOSSARY_MAX_ALIASES" -v maxtotal="$GLOSSARY_MAX_ALIASES_TOTAL" "$fence_src"'
         function v(m) { printf "V\t%s:%d: %s\n", f, NR, m }
         function w(m) { printf "W\t%s:%d: %s\n", f, NR, m }
         # names compare as the drift check matches them: case and "-", "_", " " folded
         function norm(x) { x = tolower(x); gsub(/[-_ ]+/, " ", x); gsub(/^ | $/, "", x); return x }
         function claim(x, what) {
             if (x == "") return
+            # norm() folds ASCII only, so a look-alike letter from another
+            # script (Greek beta in "Beads") would pass the duplicate check
+            if (x ~ /[\200-\377]/) w(what " \"" x "\" has a non-ASCII character; glossary names are ASCII so a look-alike letter cannot slip past the duplicate check")
             if (norm(x) in seen) v(what " \"" x "\" duplicates " seen[norm(x)] "; each term and alias names one entry")
             else seen[norm(x)] = what " \"" x "\" (line " NR ")"
         }
@@ -1339,7 +1366,7 @@ validate_glossary() {
                 for (i = 1; i <= m; i++) {
                     p = parts[i]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", p)
                     if (p == "") continue
-                    n_alias++
+                    n_alias++; total_alias++
                     claim(p, "alias")
                     if (!alias_related(p, t, d)) w("alias \"" p "\" of \"" t "\" shares no word with the term or its definition and is not its initials; name it in the definition, or give it its own entry")
                 }
@@ -1352,6 +1379,7 @@ validate_glossary() {
         END {
             NR = 1
             if (!h1) v("no H1; start with \"# Glossary: <name>\"")
+            if (total_alias > maxtotal) v("the glossary has " total_alias " aliases, over the budget of " maxtotal "; an alias names the same thing as its entry, so define distinct names as entries")
             if (!lang_line) v("no \"## Language\" section")
             else {
                 if (!context) v("no context paragraph between the H1 and \"## Language\"; say whose language this is in one paragraph")
diff --git a/.loa.config.yaml.example b/.loa.config.yaml.example
index 2215de7d..bf3e473b 100644
--- a/.loa.config.yaml.example
+++ b/.loa.config.yaml.example
@@ -2891,3 +2891,23 @@ structured_handoff:
   # skip). Read-path only — INDEX.md and read_by are untouched; old handoffs
   # stay recoverable via the structured-handoff skill.
   surface_max_age_days: 30
+
+# =============================================================================
+# red_test — inputs to .claude/scripts/red-test-check.sh (the /bug red-before-green check)
+# =============================================================================
+# The check runs a test command at the red commit and at the fix, under `env -i`, and accepts
+# only a known runner as the first word of the command and of --setup: bats, pytest,
+# python -m pytest, npm/pnpm/yarn test|run, cargo test, go test, make, mix test,
+# bundle exec rspec. Shells, env, eval, exec and inline-code interpreters (python -c, node -e,
+# perl -e, ruby -e) are always refused. This block widens that list for one project. Edit it as
+# the operator: the file is tracked, and a red_test change on the branch under review makes the
+# check WARN.
+#
+# red_test:
+#   # The project's test command; the exact string (whitespace-normalised) is accepted.
+#   command: "make test"
+#   # The exact --setup string accepted besides the runner list (e.g. a dependency install).
+#   setup: "npm ci"
+#   # ./... or tests/... scripts accepted as the first word, matched exactly.
+#   allowed_runners:
+#     - ./scripts/run-tests.sh
~~~~

## I11 — fix-commit — 2026-10-13

- reference: 3758ddd0edec
- files: .claude/scripts/validate-artifact.sh,.loa.config.yaml.example,tests/unit/validate-artifact.bats

Summary:

fix(cycle-128): Bridgebuilder round on PR #1279 — 17 findings fixed with tests, 4 refuted with evidence (triage in the PR comment): dec-write-lib.sh treats the PRD Status line as a planning-time default only (new and decide still land proposed under an autonomous PRD) while the context verdict, attribution and the operator-only operations follow live signals, so /decisions confirm records decided…

Evidence (first 200 of 282 lines):

~~~~diff
commit 3758ddd0edecb00c459fe5ab26405d6b4fd8e75f
Date: 2026-10-13T20:27:53+11:00

fix(cycle-128): Bridgebuilder round on PR #1279 — 17 findings fixed with tests, 4 refuted with evidence (triage in the PR comment): dec-write-lib.sh treats the PRD Status line as a planning-time default only (new and decide still land proposed under an autonomous PRD) while the context verdict, attribution and the operator-only operations follow live signals, so /decisions confirm records decided_by operator and /chart is not refused in a repository whose last PRD ran unattended (Anthropic F-003; recorded as DEC-0124); validate-artifact.sh --type decisions applies history rules in merge-base mode (an unchanged base prefix, any number of legal appended transitions, a content field set when any appended transition legitimises it; the strict single-write rules stay on --base-file) and no longer uses the jq 1.6-only IN builtin (F-002, F-012); dec-write-lib.sh honours LOA_PROJECT_ROOT and the validator passes its own PROJECT_ROOT to the context probe (F-017); the SessionStart decisions surface prints one WARNING when enabled without yq v4 or jq, reading the config by a plain-text fallback (F-014), plus a regression test that an uppercase summary survives the clean regex (F-001, refuted); red-test-check.sh applies the shell, launcher and inline-code denials before any configured red_test.command or red_test.setup (a configured string only widens the runner list) and refuses a config-only acceptance when .loa.config.yaml differs from the base branch unless --trust-config is given (OpenAI RTC-001; RTC-21 and RTC-27; the example config says so); the review skill's invocation is spelled --red <sha> --json so the explicit grant admits it (CI CMP-188); chart-ticket.sh epic reuses an existing map epic for the slug after a failed doc write and refuses when several exist, close --consumed-by on a closed or abandoned map is a no-op, research-begin waits one second past its marker, and demote_headings uses the shared CommonMark fence tracker (CHART-001/F-005, F-013, CHART-002, F-016); fence SP-1 also blocks git checkout -p|--patch of a spike ref and any HEAD/@ ancestor spelling as a push refspec source from a spike checkout, with format-patch/am and archive added to the documented misses (F-015; corpus D99/D100 block, B77/B78 allow); the SDD Open Questions check matches Resolved as a whole word (F-007); the one GNU-only sed insert in the new tests is a portable prepend (F-008); the validator's usage header and the CHANGELOG Migration note state the live-plan Date rule as implemented (F-004); the PRD's 21 operator-behalf decisions carry [ASSUMPTION decision] tags citing their ledger rows, D21 seeded as DEC-0123, so the PRD gate exercises itself (F-010); sprint.md's seed status reads proposed, the Appendix D free-form sentence records its supersession by the r254-2 runner allowlist, and Appendix A statuses read Complete (F-009). Refuted: F-001 (the surface's jq compiles and keeps A-Z), F-011 (the sanitizer accepts content or a path), SPK-001 and F-006 (documented fence and symlink acceptances). REPO-MAP regenerated with its checksum; checksums.json refreshed for the changed tracked files. Verification: see the PR triage comment.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/.claude/scripts/validate-artifact.sh b/.claude/scripts/validate-artifact.sh
index 067c9f61..1fca9d6f 100755
--- a/.claude/scripts/validate-artifact.sh
+++ b/.claude/scripts/validate-artifact.sh
@@ -30,7 +30,8 @@
 #               Appendix' goal table; WARN if the final sprint has no
 #               E2E/end-to-end task; a plan whose header **Date:** is on or
 #               after SEAMS_REQUIRED_FROM needs a '### Seams Under Test' table
-#               in every sprint block (older and undated plans WARN)
+#               in every sprint block (older plans WARN; an undated plan WARNs when
+#               archived or a fixture and fails when live under grimoires/loa/)
 #   bug-triage: bug_id matches the bug-triaging ID grammar; its sibling
 #               .run/bugs/<id>/state.json has a schema_version; a PII scan
 #               via pii-filter.sh (skipped if unavailable)
@@ -546,11 +547,18 @@ _dec_have_yq4() {
     [[ "$v" == *mikefarah* && "$v" == *"version v4."* ]]
 }
 
-# The writer's context (`dec-write-lib.sh context --why`); prints its signal lines.
+# The writer's context (`dec-write-lib.sh context --why`) for THIS validator's PROJECT_ROOT (passed as
+# LOA_PROJECT_ROOT, so the probe reads the same tree's .run and prd.md as the artifact); prints its lines.
+# The first line is the live verdict. With --prd (the PRD gate), the PRD's own Status line also counts:
+# an autonomous PRD is the planning-time default the gate checks, so a prd signal makes it "unattended".
 _dec_context_why() {
-    local lib="${SCRIPT_DIR}/lib/dec-write-lib.sh"
+    local lib="${SCRIPT_DIR}/lib/dec-write-lib.sh" out
     [[ -f "$lib" ]] || return 0
-    bash "$lib" context --why "$@" 2>/dev/null || true
+    out="$(LOA_PROJECT_ROOT="$PROJECT_ROOT" bash "$lib" context --why "$@" 2>/dev/null || true)"
+    if [[ " $* " == *" --prd "* ]] && grep -q '^signal: prd ' <<< "$out"; then
+        out="unattended"$'\n'"$(printf '%s\n' "$out" | tail -n +2)"
+    fi
+    printf '%s\n' "$out"
 }
 
 validate_decisions() {
@@ -586,6 +594,9 @@ validate_decisions() {
         fi
     fi
 
+    # The writer passes --base-file (one write: strict single-write rules); the merge-base copy spans
+    # every write on the branch, so only history rules apply to it.
+    local strict=false; [[ -n "$BASE_FILE" ]] && strict=true
     local live_unattended=false
     if _dec_context_why | grep -q '^signal: live '; then live_unattended=true; fi
 
@@ -595,8 +606,9 @@ validate_decisions() {
     printf '%s' "$doc" > "${scratch}"
     printf '%s' "$base" > "${scratch}.base"
     out="$(jq -rn --slurpfile DOC "$scratch" --slurpfile BASE "${scratch}.base" --argjson pending "$pending" \
-        --argjson unatt "$live_unattended" --arg refre "$DEC_REF_RE" '
+        --argjson unatt "$live_unattended" --argjson strict "$strict" --arg refre "$DEC_REF_RE" '
       $DOC[0] as $doc | $BASE[0] as $base |
+      def oneof($xs): . as $v | any($xs[]; . == $v);
       def iso: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?Z$");
       def ne: type == "string" and (gsub("\\s"; "") | length) > 0;
       def byok: type == "string" and test("^(operator|agent|flatline|dissent):[A-Za-z0-9_.-]+$");
@@ -629,20 +641,20 @@ validate_decisions() {
                (["id","created_at","updated_at","phase","category","summary","proposed_by","decided_by","recorded_by","commit","source","cycle","status","transitions"][] as $k
                  | select(($r | has($k)) | not) | "V\t\($L): missing field \($k)"),
                (["created_at","updated_at"][] as $k | select($r | has($k)) | select(($r[$k] | iso) | not) | "V\t\($L): \($k) is not an ISO-8601 UTC timestamp"),
-               (if ($r | has("phase")) and (($r.phase | IN("discovery","architecture","sprint-planning","implementation","review","charting","spike","operations")) | not) then "V\t\($L): phase \($r.phase | tojson) is not one of discovery|architecture|sprint-planning|implementation|review|charting|spike|operations" else empty end),
+               (if ($r | has("phase")) and (($r.phase | oneof(["discovery","architecture","sprint-planning","implementation","review","charting","spike","operations"])) | not) then "V\t\($L): phase \($r.phase | tojson) is not one of discovery|architecture|sprint-planning|implementation|review|charting|spike|operations" else empty end),
                (if ($r | has("category")) and ((($r.category | type) == "string" and ($r.category | test("^[a-z][a-z0-9-]*$"))) | not) then "V\t\($L): category must match [a-z][a-z0-9-]*" else empty end),
                (if ($r | has("summary")) and (($r.summary | ne) | not) then "V\t\($L): summary is empty"
                 elif ($r | has("summary")) and (($r.summary | length) > 160 or ($r.summary | test("\n"))) then "V\t\($L): summary must be one line of at most 160 characters" else empty end),
-               (if ($r | has("status")) and (($r.status | IN("open","proposed","decided","superseded","rejected")) | not) then "V\t\($L): status \($r.status | tojson) is not one of open|proposed|decided|superseded|rejected" else empty end),
-               (if ($r | has("proposed_by")) and (($r.proposed_by | IN("agent","flatline","dissent")) | not) then "V\t\($L): proposed_by must be agent|flatline|dissent" else empty end),
-               (if ($r | has("decided_by")) and (($r.decided_by | IN(null,"operator","agent","flatline","dissent")) | not) then "V\t\($L): decided_by must be null or operator|agent|flatline|dissent" else empty end),
+               (if ($r | has("status")) and (($r.status | oneof(["open","proposed","decided","superseded","rejected"])) | not) then "V\t\($L): status \($r.status | tojson) is not one of open|proposed|decided|superseded|rejected" else empty end),
+               (if ($r | has("proposed_by")) and (($r.proposed_by | oneof(["agent","flatline","dissent"])) | not) then "V\t\($L): proposed_by must be agent|flatline|dissent" else empty end),
+               (if ($r | has("decided_by")) and (($r.decided_by | oneof([null,"operator","agent","flatline","dissent"])) | not) then "V\t\($L): decided_by must be null or operator|agent|flatline|dissent" else empty end),
                (if ($r | has("source")) and (($r.source | ne) | not) then "V\t\($L): source is empty" else empty end),
                (if ($r | has("recorded_by")) and (($r.recorded_by | ne) | not) then "V\t\($L): recorded_by is empty" else empty end),
                (if ($r | has("commit")) and (($r.commit | type) != "string") then "V\t\($L): commit must be a string" else empty end),
                (($r.transitions // null) | if type == "array" then . else [] end) as $T
                | ($T | any(.[]; (type == "object") and .to == "decided")) as $wasdecided
                | (
-                   (if ($r.status // null | IN("proposed","decided","superseded")) or ($T | any(.[]; (type == "object") and .to == "proposed")) then
+                   (if ($r.status // null | oneof(["proposed","decided","superseded"])) or ($T | any(.[]; (type == "object") and .to == "proposed")) then
                       (if ($r.decision | ne) | not then "V\t\($L): a row past open needs a decision" else empty end),
                       (if ($r.rationale | ne) | not then "V\t\($L): a row past open needs a rationale" else empty end),
                       (if (($r.alternatives_considered // null) | type) != "array" or ($r.alternatives_considered | length) < 1 then "V\t\($L): a row past open needs at least one alternatives_considered entry"
@@ -651,14 +663,14 @@ validate_decisions() {
                     else empty end),
                    (if ($r | has("transitions")) and ((($r.transitions | type) != "array") or ($T | length) == 0) then "V\t\($L): transitions must be a non-empty sequence" else empty end),
                    (if ($T | length) > 0 then
-                      (if ($T[0] | type) != "object" or $T[0].from != null or (($T[0].to // null) | IN("open","proposed") | not) then "V\t\($L): the first transition must be null -> open|proposed" else empty end),
+                      (if ($T[0] | type) != "object" or $T[0].from != null or (($T[0].to // null) | oneof(["open","proposed"]) | not) then "V\t\($L): the first transition must be null -> open|proposed" else empty end),
                       ($T | to_entries[] | .key as $j | .value as $t
                         | if ($t | type) != "object" then "V\t\($L): transition \($j) is not a mapping" else
                           (if $j > 0 and $t.from != (($T[$j - 1] | objects | .to) // null) then "V\t\($L): transition \($j) starts at \($t.from | tojson) but the previous one ended at \(($T[$j - 1] | objects | .to) // null | tojson)" else empty end),
                           (if allowed($t.from; $t.to) | not then "V\t\($L): illegal transition \($t.from | tojson) -> \($t.to | tojson)" else empty end),
                           (if ($t.at | iso) | not then "V\t\($L): transition \($j) has no ISO-8601 UTC at" else empty end),
                           (if ($t.by | byok) | not then "V\t\($L): transition \($j) by \($t.by | tojson) does not match (operator|agent|flatline|dissent):<name>" else empty end),
-                          (if ($t.to == "decided" or ($t.from == "decided" and ($t.to | IN("superseded","rejected")))) and ((($t.by // "") | tostring | startswith("operator:")) | not) then "V\t\($L): transition \($t.from | tojson) -> \($t.to) needs by operator:* (only /decisions makes it)" else empty end),
+                          (if ($t.to == "decided" or ($t.from == "decided" and ($t.to | oneof(["superseded","rejected"])))) and ((($t.by // "") | tostring | startswith("operator:")) | not) then "V\t\($L): transition \($t.from | tojson) -> \($t.to) needs by operator:* (only /decisions makes it)" else empty end),
                           (if $t.to == "decided" and (($t.evidence | ne) | not) then "V\t\($L): the -> decided transition has no evidence" else empty end)
                           end),
                       (if ($r | has("status")) and ((($T[-1] | objects | .to) // null) != $r.status) then "V\t\($L): status \($r.status | tojson) does not equal the last transition (\((($T[-1] | objects | .to) // null) | tojson))" else empty end)
@@ -670,7 +682,7 @@ validate_decisions() {
                (if $r.decided_by == "operator" and (($r.decided_by_ref | opref) | not) then "V\t\($L): decided_by operator needs an operator answer reference (decided_by_ref session:|debrief:|transcript:|cli:)" else empty end),
                (if ($r.decided_by_ref // null) != null and ((($r.decided_by_ref | type) == "string" and ($r.decided_by_ref | test($refre))) | not) then "V\t\($L): decided_by_ref \($r.decided_by_ref | tojson) does not match the ref grammar" else empty end),
                (if ($r.evidence_sha256 // null) != null and ((($r.evidence_sha256 | type) == "string" and ($r.evidence_sha256 | test("^[0-9a-f]{64}$"))) | not) then "V\t\($L): evidence_sha256 must be 64 lowercase hex" else empty end),
-               (($r.proposed_by // null) as $v | if ($v | IN("flatline","dissent")) then
+               (($r.proposed_by // null) as $v | if ($v | oneof(["flatline","dissent"])) then
                   (if ((($r.decided_by_ref // "") | tostring | startswith($v + ":")) and (($r.evidence_sha256 // "") | tostring | test("^[0-9a-f]{64}$"))) then
                      "A\t\($v)\t\($r.decided_by_ref | ltrimstr($v + ":"))\t\($r.evidence_sha256)\t\($L)"
                    else "V\t\($L): a \($v) row needs decided_by_ref \($v):<artifact> and its evidence_sha256" end)
@@ -697,17 +709,20 @@ validate_decisions() {
                   else
                     (($b.transitions // []) | length) as $bl | (($r.transitions // []) | if type == "array" then length else 0 end) as $rl
                     | (if (($r.transitions // null) | type) != "array" or $rl < $bl or ($r.transitions[0:$bl] != ($b.transitions // [])) then "V\t\($b.id): transitions rewritten (append only)" else empty end),
-                      (if $rl - $bl > 1 then "V\t\($b.id): more than one transition appended in one write" else empty end),
-                      ((if $rl > $bl and (($r.transitions // null) | type) == "array" then $r.transitions[-1] else null end) as $t
+                      # strict (--base-file, the pre-write file the writer passes): one write appends at most one
+                      # transition. History (merge-base): any number, each already checked as a legal step.
+                      (if $strict and $rl - $bl > 1 then "V\t\($b.id): more than one transition appended in one write" else empty end),
+                      ((if $rl > $bl and (($r.transitions // null) | type) == "array" then $r.transitions[$bl:] | map(objects) else [] end) as $app
                        | ((($b | keys) + ($r | keys)) | unique[]) as $k
-                       | if ($k | IN("status","updated_at","transitions")) then empty
+                       | if ($k | oneof(["status","updated_at","transitions"])) then empty
                          elif $b[$k] == $r[$k] then empty
-                         elif ($k | IN("decision","rationale","alternatives_considered","consequences","evidence_sha256")) and $b[$k] == null and $t != null and $t.to == "proposed" then empty
-                         elif $k == "decided_by_ref" and $b[$k] == null and $t != null and ($t.to | IN("proposed","decided")) then empty
-                         elif $k == "decided_by" and $b[$k] == null and $t != null and $t.to == "decided" then empty
-                         elif ($k | IN("rejection_rationale","follow_up")) and $b[$k] == null and $t != null and $t.to == "rejected" then empty
-                         elif $k == "prior_requests" and (($b[$k] // []) == []) and $t != null and $t.to == "rejected" then empty
-                         elif $k == "supersede_proposed_by" and $b[$k] == null and $t == null and $r.status == "decided" then empty
+                         elif ($k | oneof(["decision","rationale","alternatives_considered","consequences","evidence_sha256"])) and $b[$k] == null and any($app[]; .to == "proposed") then empty
+                         elif $k == "decided_by_ref" and $b[$k] == null and any($app[]; .to | oneof(["proposed","decided"])) then empty
+                         elif $k == "decided_by" and $b[$k] == null and any($app[]; .to == "decided") then empty
+                         elif ($k | oneof(["rejection_rationale","follow_up"])) and $b[$k] == null and any($app[]; .to == "rejected") then empty
+                         elif $k == "prior_requests" and (($b[$k] // []) == []) and any($app[]; .to == "rejected") then empty
+                         elif $k == "supersede_proposed_by" and $b[$k] == null and $strict and ($app | length) == 0 and $r.status == "decided" then empty
+                         elif $k == "supersede_proposed_by" and $b[$k] == null and ($strict | not) and ($r.status | oneof(["decided","superseded"])) then empty
                          else "V\t\($b.id): content edit to \($k) (rows are append-only; supersede the row instead)" end),
                       (if $unatt and $r.decided_by == "operator" and $b.decided_by != "operator" then "V\t\($b.id): decided_by operator written while a live unattended signal holds" else empty end)
                   end),
@@ -942,7 +957,8 @@ validate_sdd_open_questions() {
                 next
             }
             if ($0 ~ /^\|[-|: ]+\|?[[:space:]]*$/) next
-            if (st && tolower(c[st]) ~ /resolved/) {
+            # a whole word: "Unresolved" is not Resolved (Bridgebuilder F-007)
+            if (st && tolower(c[st]) ~ /(^|[^a-z])resolved([^a-z]|$)/) {
                 cell = dc ? c[dc] : $0
                 if (cell !~ /DEC-[0-9][0-9][0-9][0-9]/) printf "%d\n", NR
             }
diff --git a/.loa.config.yaml.example b/.loa.config.yaml.example
index bf3e473b..918541d7 100644
--- a/.loa.config.yaml.example
+++ b/.loa.config.yaml.example
@@ -2904,7 +2904,10 @@ structured_handoff:
 # check WARN.
 #
 # red_test:
-#   # The project's test command; the exact string (whitespace-normalised) is accepted.
+#   # The project's test command; the exact string (whitespace-normalised) is accepted,
+#   # unless it starts with a shell, a launcher or an inline-code interpreter (those are refused
+#   # even here). A red_test change on the branch under review makes the check refuse until the
+#   # reviewer passes --trust-config.
 #   command: "make test"
 #   # The exact --setup string accepted besides the runner list (e.g. a dependency install).
 #   setup: "npm ci"
diff --git a/tests/unit/validate-artifact.bats b/tests/unit/validate-artifact.bats
index cbf6e1a1..3ef72b0f 100644
--- a/tests/unit/validate-artifact.bats
+++ b/tests/unit/validate-artifact.bats
@@ -956,3 +956,104 @@ MAP
     run "$SCRIPT" --type map --file "${TEST_TMPDIR}/map.md"
     [ "$status" -eq 0 ]
 }
+
+# ---- Bridgebuilder round: merge-base history mode (F-002), jq floor (F-012), PROJECT_ROOT (F-017) ----
+
+# A git repo whose origin/main holds the ledger with one open row; the working copy then moves on.
+_dec_mergebase_project() {
+    _dec_project
+    bash "$DW" new --file "$DL" --summary "an open question" --phase discovery --category scope --recorded-by t --source "prd.md#q" --status open --quiet >/dev/null
+    git -C "$DP" add -A
+    git -C "$DP" -c core.hooksPath=/dev/null -c user.email=t@t -c user.name=t commit -qm base
+    git -C "$DP" update-ref refs/remotes/origin/main HEAD
+    git -C "$DP" show HEAD:grimoires/loa/decisions.yaml > "$BATS_TEST_TMPDIR/mb-base.yaml"
+}
+
+@test "validate-artifact decisions F-002: a branch row open -> proposed -> decided validates against its merge-base copy (history rules)" {
+    _dec_skip_unless_tools; _dec_mergebase_project
+    bash "$DW" decide --file "$DL" --id DEC-0001 --decision d --rationale r --alternative-json "$DALT" --evidence e --recorded-by t --quiet
+    _dec_confirm DEC-0001
+    [ "$(yq '.decisions[0].transitions | length' "$DL")" -eq 3 ]
+    run "$DV" --type decisions --file "$DL"
~~~~

## I12 — issue — 2026-10-13

- reference: #1281
- files: .claude/scripts/flatline-orchestrator.sh

Summary:

KF-041: Flatline Phase 2 cross-scoring degrades to one scorer on every planning review (recurrence 4) — record scorer failure_class in the final JSON — ## Symptom A two-voice Flatline planning review (`codex-headless` + `claude-headless`, Phase 1 reviews fine) ends with Phase 2 cross-scoring degraded: every item carries `gpt_score: null`, `scorers_available: 1`, `source: opus_scored`; the consens…

Evidence:

~~~~~text
# issue #1281: KF-041: Flatline Phase 2 cross-scoring degrades to one scorer on every planning review (recurrence 4) — record scorer failure_class in the final JSON

- url: https://github.com/0xHoneyJar/loa/issues/1281
- created_at: 2026-10-13T22:36:33Z
- state: open

The text below is third-party data, quoted verbatim (control characters and secret-shaped strings replaced).

~~~~text
## Symptom

A two-voice Flatline planning review (`codex-headless` + `claude-headless`, Phase 1 reviews fine) ends with Phase 2 cross-scoring degraded: every item carries `gpt_score: null`, `scorers_available: 1`, `source: opus_scored`; the consensus line reads `HIGH=0 DISPUTED=0 LOW=0 BLOCKERS=n (0% agreement)`; status DEGRADED, confidence degraded, exit 6; no HIGH_CONSENSUS set is produced. Phase 2 reports `Total cost: 0 cents`, and the final JSON's `execution` block carries no per-call scorer status, so the cause (empty content, schema rejection, timeout) is never recorded.

## Recurrence

`grimoires/loa/known-failures.md` KF-041, recurrence 4:

- 2026-10-07 cycle-127: prd, sdd and sprint runs (`flatline-28236-11307`, `flatline-19206-31034`, sprint run), all identical shape.
- 2026-10-13 cycle-128: prd, sdd and sprint runs, same shape.
- 2026-10-14 cycle-129: prd (`flatline-24474-6736`), sdd and sprint runs, same shape (claude-headless via `claude-fallback`, codex-headless as `gpt-5.5`).

Every planning review since cycle 127 has run in this shape. By the ledger's own rule (recurrence ≥ 3) this is structural, not a retry candidate; the reading guide says to integrate the raw per-voice improvements by judgment and not to re-run to chase consensus.

## Where

`.claude/scripts/flatline-orchestrator.sh` Phase 2 (`scoring-engine`): the codex-headless scorer returns null scores for every item while its Phase 1 review succeeded. The vq-aggregate envelope names voices; scorers are invisible in the final JSON.

## Candidate fix

1. Record each Phase 2 scorer call's outcome in the final JSON `execution` block: `scorers: [{voice, status, failure_class, latency_ms, schema_enforced}]`, so a null-score run names its cause.
2. Retain the raw scorer output with `--keep-temp` by default when any scorer returns null for every item.
3. Treat "every score null from one scorer" as a scorer failure (`scoring_degraded` with a named class) rather than silent degradation, and surface it in the orchestrator's summary line.
4. Once the cause is recorded, fix the scorer (likely candidates from the ledger's related entries: KF-002 empty content on reasoning-class models, KF-004 schema-rejected payloads).

## Evidence

- `grimoires/loa/known-failures.md` KF-041 (attempts table, recurrence 4)
- cycle-129 planning records: `grimoires/loa/a2a/flatline/*-final_consensus.json` (prd `flatline-24474-6736`), to be preserved on `record/cycle-129-a2a`
- Decision DEC-0134 (cycle-129): route KF-041 through an upstream issue, no further retries
~~~~
~~~~~

## I13 — fix-commit — 2026-10-14

- reference: 3263bbc4ea22
- files: .claude/rules/skill-invariants.md,.loa.config.yaml.example

Summary:

fix(cycle-129): sprint-256 review round r256-1 — a backtick pair outside single quotes is a command substitution to the fence (HIGH-1: heredoc-aware normalisation to the dollar-paren form before any rule runs; unquoted heredoc bodies alternate every backtick, quoted bodies and single quotes stay literal, unbalanced shell quotes fail closed; corpus B79/B84 → quoted delimiters, D143–D148 block the…

Evidence:

~~~~diff
commit 3263bbc4ea22bfc0dff03d522d3308005ad60546
Date: 2026-10-14T14:57:42+11:00

fix(cycle-129): sprint-256 review round r256-1 — a backtick pair outside single quotes is a command substitution to the fence (HIGH-1: heredoc-aware normalisation to the dollar-paren form before any rule runs; unquoted heredoc bodies alternate every backtick, quoted bodies and single quotes stay literal, unbalanced shell quotes fail closed; corpus B79/B84 → quoted delimiters, D143–D148 block the unquoted-heredoc, echo, printf, assignment and dollar-paren shapes, B90/B91 pin the literal cases; knob-off differs from the pre-change hook on exactly D143–D147, DEC-0296); LOW-1 check-knob-readers.sh as a Shell Tests step; LOW-2 run-corpus.sh --knob-off self-check on D122; LOW-3 POSIX touch -t in KS-5; LOW-5 LOA_PROFILE_CONFIG_FILE documented in the example; skill-invariants.md records the harness probe (enforced in the main session until the next user prompt, not in subagents); KF-043 scope corrected by an attempt row (DEC-0297); CHANGELOG Fixed entry; corpus 91/91 · 148/148, hook bats 476/0, lints green (sprint-2)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/.claude/rules/skill-invariants.md b/.claude/rules/skill-invariants.md
index d2b61f85..e80c6cd7 100644
--- a/.claude/rules/skill-invariants.md
+++ b/.claude/rules/skill-invariants.md
@@ -70,6 +70,20 @@ ## Mechanical C-PROC-001 enforcement via `disallowed-tools` (cycle-114 FR-4)
 fence territory (`block-destructive-bash.sh` and the System-Zone rules), not
 frontmatter territory.
 
+**What the harness enforces (live probe, cycle-129 Sprint 2, Claude Code 2.1.296).**
+In the main session, invoking a skill that carries `disallowed-tools: Write, Edit,
+NotebookEdit` removed the three tools until the next user prompt — the next Write
+was refused ("Permission to use Write has been denied"), later calls reported the
+tools "disabled for this session, in subagents as well", and invoking a write-capable
+skill did not restore them; in an unattended run that is the rest of the session
+(KF-043). A Bash redirect still wrote a file (the Bash gap above). In a subagent
+(`general-purpose`, all tools) the same skill removed nothing: Write, Edit and Bash
+all succeeded, and `allowed-tools: Read, Grep, Glob` did not restrict either. So the
+key is a barrier in the main session only; for subagent work the zones, the fence and
+the implement gate are the barriers. Keep the key (it holds where the review and audit
+skills run) and never invoke such a skill from a lead session that still has writes
+to do.
+
 ## Scope
 
 Applies to every `.claude/skills/**/SKILL.md`. The lint runs as part of the normal validation suite (`bats tests/unit/skill-capabilities.bats`).
diff --git a/.loa.config.yaml.example b/.loa.config.yaml.example
index f2ba980e..a82de682 100644
--- a/.loa.config.yaml.example
+++ b/.loa.config.yaml.example
@@ -29,6 +29,9 @@
 # config key read the same configuration under every profile
 # (.claude/data/floor.yaml lists them; tests/unit/profile-floor.bats pins it).
 # An unknown value warns and falls back to standard.
+# Seam: the environment variable LOA_PROFILE_CONFIG_FILE points the profile
+# library at another config file (hooks pass their own test config through it);
+# it is honoured outside bats, so treat it as part of the hook environment.
 loa:
   profile: standard   # lean | standard | full
 
~~~~

## I14 — fix-commit — 2026-10-14

- reference: 77455afb372f
- files: .loa.config.yaml.example

Summary:

fix(cycle-129): sprint-256 review round r256-2 — the example ships the nine profile keys only as commented, profile-governed lines so a copied example follows loa.profile (HIGH-2; PL-4 pins null raw keys, standard as the effective value, and lean/full copies with no override; AC-2.4 restated); LI-2/3/5/8 and PL-1 negated assertions as run plus status (LOW-8); check-knob-readers.sh escapes every E…

Evidence:

~~~~diff
commit 77455afb372fbba4a67c51232598d17099a16182
Date: 2026-10-14T15:35:21+11:00

fix(cycle-129): sprint-256 review round r256-2 — the example ships the nine profile keys only as commented, profile-governed lines so a copied example follows loa.profile (HIGH-2; PL-4 pins null raw keys, standard as the effective value, and lean/full copies with no override; AC-2.4 restated); LI-2/3/5/8 and PL-1 negated assertions as run plus status (LOW-8); check-knob-readers.sh escapes every ERE metacharacter, skips binaries and fails on a grep error (LOW-9); run-corpus.sh --knob-off requires the D122 sentinel unless --no-self-check (LOW-10); the review and audit skills grant Bash(.claude/scripts/lib/profile-lib.sh knob *) in allowed-tools and capabilities for the shared include steps (CMP-188; byte-neutral trims in both frontmatters); karpathy-config-schema.bats isolates KARPATHY_STATE_DIR and expects the two profile-governed keys commented; CHANGELOG; DEC-0299…DEC-0301 (sprint-2)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/.loa.config.yaml.example b/.loa.config.yaml.example
index a82de682..7724ab60 100644
--- a/.loa.config.yaml.example
+++ b/.loa.config.yaml.example
@@ -29,6 +29,9 @@
 # config key read the same configuration under every profile
 # (.claude/data/floor.yaml lists them; tests/unit/profile-floor.bats pins it).
 # An unknown value warns and falls back to standard.
+# The nine keys appear in this file only as commented lines at their usual
+# place ("Profile-governed … uncomment to pin it"), so a copied example follows
+# the profile you choose; an uncommented key is an explicit override and wins.
 # Seam: the environment variable LOA_PROFILE_CONFIG_FILE points the profile
 # library at another config file (hooks pass their own test config through it);
 # it is honoured outside bats, so treat it as part of the hook environment.
@@ -312,7 +315,8 @@ known_failures:
   # NOTHING while this flag is false. When true it is loud-but-nonblocking: it
   # warns visibly ([KF-SURFACE] WARNING) if the surface is enabled-but-degraded
   # (known-failures.md unreadable or zero entries parsed).
-  surface_at_session_start: false
+  # Profile-governed (loa.profile; standard = false). Uncomment to pin it:
+  # surface_at_session_start: false
 
 # -----------------------------------------------------------------------------
 # Decision ledger (grimoires/loa/decisions.yaml)
@@ -325,7 +329,8 @@ decisions:
   # proposed and open rows (id, status, summary) at session start, inside the L6
   # untrusted-content fence, plus a notice when .run/unattended.json is stale.
   # DEFAULT-OFF: the hook prints nothing while this is false and always exits 0.
-  surface_at_session_start: false
+  # Profile-governed (loa.profile; standard = false). Uncomment to pin it:
+  # surface_at_session_start: false
   # Hours after which `dec-write-lib.sh context --set-unattended`'s marker is stale
   # and ignored (a marker from another session is stale at once).
   unattended_marker_ttl_hours: 24
@@ -1358,7 +1363,8 @@ upstream_proposals:
 guardrails:
   # Input guardrails (pre-execution)
   input:
-    enabled: false
+    # Profile-governed (loa.profile; standard = false, full = true). Uncomment to pin it:
+    # enabled: false
 
     # PII Filter: Detect and redact sensitive data before processing
     # Actions: redact (replace with placeholder), anonymize (generic value)
@@ -1404,7 +1410,9 @@ guardrails:
   # Danger Level Enforcement: Tool risk classification
   # Levels: safe, moderate, high, critical
   danger_level:
-    enforce: false                # see the default-off note above the block
+    # Profile-governed (loa.profile; standard = false, full = true); see the
+    # default-off note above the block. Uncomment to pin it:
+    # enforce: false
     interactive:
       safe: execute               # Execute immediately
       moderate: execute_with_notice  # Brief notice in output
@@ -1431,8 +1439,9 @@ guardrails:
 # Uses skill postludes to silently scan for discoveries and extract learnings.
 # Mirrors the invisible prompt enhancement pattern from v1.17.0.
 invisible_retrospective:
-  # Master toggle - set to false to disable all invisible retrospective
-  enabled: true
+  # Master toggle - set to false to disable all invisible retrospective.
+  # Profile-governed (loa.profile; standard = true, lean = false). Uncomment to pin it:
+  # enabled: true
 
   # Always log to trajectory (even when disabled) - useful for debugging
   log_to_trajectory: true
@@ -2932,7 +2941,8 @@ karpathy_principles:
   # G-1 — master switch for the PostToolUse:Write|Edit surgical-diff hook
   # at .claude/hooks/quality/karpathy-surgical-diff-check.sh. When false,
   # the hook fast-paths to exit 0 in <10ms.
-  surgical_diff_warning: true
+  # Profile-governed (loa.profile; standard = true, lean = false). Uncomment to pin it:
+  # surgical_diff_warning: true
 
   # G-1 — per-session diff-lines threshold. When the session accumulator
   # exceeds this, the hook emits a [karpathy-surgical-warn] stderr line
@@ -2950,7 +2960,8 @@ karpathy_principles:
   # G-3 — when true, /implement refuses to write code if sprint.md lacks a
   # "Success criteria" / "Acceptance criteria" / "Verification" section.
   # Operator can [Skip with rationale] to override per-invocation.
-  require_success_criteria: true
+  # Profile-governed (loa.profile; standard = true, lean = false). Uncomment to pin it:
+  # require_success_criteria: true
 
   # warn | block. v1 honors only "warn" — block-mode is reserved for v2 to
   # avoid surprise breaking changes during initial rollout. Even with
@@ -2962,7 +2973,8 @@ karpathy_principles:
 # -----------------------------------------------------------------------------
 structured_handoff:
   # Master toggle for the L6 SessionStart surfacing hook.
-  enabled: false
+  # Profile-governed (loa.profile; standard = false, full = true). Uncomment to pin it:
+  # enabled: false
   # Per-handoff body byte cap at surfacing.
   surface_max_chars: 4000
   # cycle-121: skip UNREAD handoffs older than N days at surfacing (0 = never
~~~~

## I15 — fix-commit — 2026-10-14

- reference: 9c4ed3198c78
- files: .claude/scripts/loa-status.sh

Summary:

fix(cycle-129): sprint-256 audit round r256-5 — /loa Profile line reports an off guardrail control (DEC-0161 mitigation; PL-14); shell reserved words are transparent prefixes in the heredoc per-segment scan and Dockerfile, pre-commit and gitlab-ci targets are executable content (D169–D178, B100); FR-GH-1 covers gh api graphql mutations, full-URL and leading-slash paths, --hostname and a non-liter…

Evidence:

~~~~diff
commit 9c4ed3198c7891882ca77847e37bd10475885779
Date: 2026-10-14T16:45:43+11:00

fix(cycle-129): sprint-256 audit round r256-5 — /loa Profile line reports an off guardrail control (DEC-0161 mitigation; PL-14); shell reserved words are transparent prefixes in the heredoc per-segment scan and Dockerfile, pre-commit and gitlab-ci targets are executable content (D169–D178, B100); FR-GH-1 covers gh api graphql mutations, full-URL and leading-slash paths, --hostname and a non-literal method (D179–D184, B98–B99; the corpus lint admits api.github.com); profile-lib WARNs when LOA_PROFILE_CONFIG_FILE redirects a live read; check-knob-readers.sh matches the trailing two components of three-part keys (PL-17 bypass shapes); DEC-0307…DEC-0311 (sprint-2)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/.claude/scripts/loa-status.sh b/.claude/scripts/loa-status.sh
index a4217e7a..00ccb0c1 100755
--- a/.claude/scripts/loa-status.sh
+++ b/.claude/scripts/loa-status.sh
@@ -955,7 +955,12 @@ display_profile_line() {
     note=""
     if [[ "$(loa_profile_source 2>/dev/null)" == "invalid" ]]; then note="unknown loa.profile, using standard; "; fi
     ov=$(loa_profile_overrides 2>/dev/null | awk 'NF { printf "%s%s", (n++ ? ", " : ""), $0 }')
-    printf '%s (%sexplicit overrides: %s)' "${name:-standard}" "$note" "${ov:-none}"
+    # cycle-129 audit r256-5 (DEC-0161 mitigation): say so when either guardrail
+    # control resolves to off, whatever turned it off (profile or explicit key).
+    gn=""
+    [[ "$(loa_knob guardrails.input.enabled false 2>/dev/null)" == true ]] || gn="input guardrails off"
+    [[ "$(loa_knob guardrails.danger_level.enforce false 2>/dev/null)" == true ]] || gn="${gn:+$gn, }danger-level enforcement off"
+    printf '%s (%sexplicit overrides: %s)%s' "${name:-standard}" "$note" "${ov:-none}" "${gn:+ · $gn}"
   ) || line=""
   echo -e "${BOLD}Profile:${NC} ${line:-standard (explicit overrides: unavailable)}"
   return 0
~~~~

## I16 — fix-commit — 2026-10-14

- reference: cf88e4270d58
- files: .claude/adapters/loa_cheval/providers/base.py,.claude/skills/bridgebuilder-review/dist/.build-manifest.json

Summary:

fix(cycle-129): sprint-257 review round r257-1 — a declared dispatch_group: local is enforced, not trusted (HIGH-1: the local-hop rule — an HTTP provider whose endpoint host is a loopback or RFC1918 IP literal or localhost — stated once in endpoint_policy and applied at load, at request time by TransportPolicy.local, in hop-locality.py (endpoint_not_local / endpoint_missing / cli_provider), in Br…

Evidence:

~~~~diff
commit cf88e4270d586cbfd1faab2258edfd3e4e978dfd
Date: 2026-10-14T20:13:12+11:00

fix(cycle-129): sprint-257 review round r257-1 — a declared dispatch_group: local is enforced, not trusted (HIGH-1: the local-hop rule — an HTTP provider whose endpoint host is a loopback or RFC1918 IP literal or localhost — stated once in endpoint_policy and applied at load, at request time by TransportPolicy.local, in hop-locality.py (endpoint_not_local / endpoint_missing / cli_provider), in Bridgebuilder applyLocality and in MODELINV hop_locality; a CLI provider never carries the label; an https endpoint on a local host needs no opt-in); keyless: false beside auth: local is refused by name (LOW-2); the probe helper CLI turns every load failure into one JSON line and exit 78 (LOW-3); the locality fixtures declare a loader-admissible localbox and load it through the real loader (LOW-1); DISS-C-002 refuted; tests test_local_dispatch_group_rule.py, LOC-9/LOC-10, FLL-8/FLL-9, trusted-config.test.ts (21), dist rebuilt; cheval pytest 3256 passed (2 baseline failures), Sprint 3 bats 136/136, npm 867/868 (KF-036), corpus 99/99 · 184/184; multi-model-reference FR-8 paragraph, CHANGELOG Fixed entry and Migration row; DEC-0331…DEC-0339 (sprint-3)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/.claude/adapters/loa_cheval/providers/base.py b/.claude/adapters/loa_cheval/providers/base.py
index fdf888a9..1a499c68 100644
--- a/.claude/adapters/loa_cheval/providers/base.py
+++ b/.claude/adapters/loa_cheval/providers/base.py
@@ -120,20 +120,31 @@ class TransportPolicy:
     (or a model with dispatch_group `local`): proxy environment variables are
     ignored, an HTTP redirect is an error and is never followed, and every request
     URL must keep the declared endpoint's scheme, host and port and start with its
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
 
         try:
             d_scheme, d_host, d_port, d_path = split_url(self.endpoint)
             r_scheme, r_host, r_port, r_path = split_url(url)
         except ValueError as exc:
             raise InvalidConfigError(f"request URL for provider '{self.provider}' does not parse: {exc}") from None
+        if self.local and (r_scheme not in ("http", "https") or local_host(r_host) is None):
+            raise InvalidConfigError(
+                f"request host {r_host or '(none)'} for provider '{self.provider}' is not {LOCAL_RULE_TEXT} "
+                f"(dispatch_group local, D-7.2)"
+            )
         prefix = d_path.rstrip("/")
         same_origin = (r_scheme, r_host, r_port) == (d_scheme, d_host, d_port)
         in_path = (r_path == prefix or r_path.startswith(prefix + "/")) if prefix else True
diff --git a/.claude/skills/bridgebuilder-review/dist/.build-manifest.json b/.claude/skills/bridgebuilder-review/dist/.build-manifest.json
index 52bbcdd8..84b32fbb 100644
--- a/.claude/skills/bridgebuilder-review/dist/.build-manifest.json
+++ b/.claude/skills/bridgebuilder-review/dist/.build-manifest.json
@@ -1,7 +1,7 @@
 {
   "version": "1.0",
-  "generated_at": "2026-10-14T07:40:42Z",
-  "source_hash": "ffa2ae2ff364c468d601f0fc7a1ff0f21a1495d138efcc18a0e94c0d7b761d54",
+  "generated_at": "2026-10-14T08:50:46Z",
+  "source_hash": "b4e84888ce6f026aa7ffa758e24a1ae7262055fe3bcdebff5a3c49dd5c859cf6",
   "file_count": 43,
   "files": [
     {
@@ -46,7 +46,7 @@
     },
     {
       "path": ".claude/skills/bridgebuilder-review/resources/config.ts",
-      "sha256": "4a17672d468d763c6eb9dfe24a9c0ecf1327ab2e22c36b1a3cca454c949b0dce"
+      "sha256": "06f39340b69c9f734738ba739ee4d01be9ab9fbfdf530587541c2f928c5cbcf9"
     },
     {
       "path": ".claude/skills/bridgebuilder-review/resources/core/cache.ts",
@@ -130,7 +130,7 @@
     },
     {
       "path": ".claude/skills/bridgebuilder-review/resources/core/types.ts",
-      "sha256": "b047232236a1219e578fe7151b4aba16ecedcd05ea71931ef9eaf18f9a705af8"
+      "sha256": "1b13a035d7dd98ef48cbec7fd76c96ddc9a6e0e9e40984dcbd03bfee1cb33ec5"
     },
     {
       "path": ".claude/skills/bridgebuilder-review/resources/lib/endpoint-validator.generated.ts",
~~~~

## I17 — fix-commit — 2026-10-14

- reference: 07110d7052ea
- files: .claude/adapters/cheval.py,.claude/adapters/loa_cheval/providers/base.py,.claude/skills/bridgebuilder-review/dist/.build-manifest.json,.loa.config.yaml.example

Summary:

fix(cycle-129): sprint-257 security audit round a257-1 — a declared locality is enforced where the prompt is sent: under hounfour.locality local_voices cheval plans around every chain hop that fails the local-hop rule (one stderr line each, MODELINV models_not_planned reason locality_refused) and refuses an all-hosted chain before any dispatch (LocalityRefusedError, failure_class locality_refused…

Evidence (first 200 of 217 lines):

~~~~diff
commit 07110d7052ea531b190ec58a0f429e0718e2365c
Date: 2026-10-14T21:29:39+11:00

fix(cycle-129): sprint-257 security audit round a257-1 — a declared locality is enforced where the prompt is sent: under hounfour.locality local_voices cheval plans around every chain hop that fails the local-hop rule (one stderr line each, MODELINV models_not_planned reason locality_refused) and refuses an all-hosted chain before any dispatch (LocalityRefusedError, failure_class locality_refused, exit INVALID_CONFIG), the loader refuses a local model whose fallback_chain reaches a hosted or unresolvable hop, and Bridgebuilder walks the chain in the trusted view (MEDIUM-A1; one implementation endpoint_policy.hop_is_local serves cheval, the loader and MODELINV hop_locality); Bridgebuilder refuses trusted-config drift on a pull request — hounfour.providers, aliases, locality and the secret allowlist compared head vs trusted, exit 5 before any voice is planned, because cheval-delegate spawns cheval from the checkout (MEDIUM-A2); localhost is resolved and checked for loopback at request time (LOW-A1); metadata.locality.degraded_security_review is machine-readable on the audit envelope (LOW-A2); a zero price not marked open_weight warns in the budget gate (LOW-A3; metering guard → bd-yzzb9); DISS-001 RFC1918 opt-in accepted by design; tests test_locality_fallback_plan.py (13), test_local_dispatch_group_rule.py (+9), LOC-1/4/10, BUD-3/7, trusted-config.test.ts (35), dist rebuilt; cheval pytest 3277 passed (2 baseline), Sprint 3 bats 137/137, npm 881/882 (KF-036), corpus 99/99 · 184/184; CHANGELOG Fixed entry + two Migration rows; DEC-0340…DEC-0351 (sprint-3)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/.claude/adapters/cheval.py b/.claude/adapters/cheval.py
index 2e9e033d..d1b0ed04 100644
--- a/.claude/adapters/cheval.py
+++ b/.claude/adapters/cheval.py
@@ -420,6 +420,43 @@ def _plan_around_agy(chain: Any, hounfour: Dict[str, Any]) -> Tuple[Any, List[Di
     return _dc_replace(chain, entries=type(chain.entries)(kept)), skipped
 
 
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
 def _get_adapter_for_entry(entry: Any, hounfour: Dict[str, Any]):
     """Select the adapter for a single ResolvedEntry honoring `adapter_kind`.
 
@@ -1811,6 +1848,33 @@ def cmd_invoke(args: argparse.Namespace) -> int:
     # the full resolved chain (cycle-127 review r251-1 G1: a gated agy hop is
     # planned around before models_requested is taken; r251-4 S8, audit n2).
     _chain, _models_not_planned = _plan_around_agy(_chain, hounfour)
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
     if _models_not_planned and _auth_type_resolved is not None:
         _auth_type_resolved = _chain.entries[0].auth_type
     _modelinv_capability_class = getattr(binding, "capability_class", None)
diff --git a/.claude/adapters/loa_cheval/providers/base.py b/.claude/adapters/loa_cheval/providers/base.py
index 1a499c68..372693e4 100644
--- a/.claude/adapters/loa_cheval/providers/base.py
+++ b/.claude/adapters/loa_cheval/providers/base.py
@@ -145,6 +145,12 @@ class TransportPolicy:
                 f"request host {r_host or '(none)'} for provider '{self.provider}' is not {LOCAL_RULE_TEXT} "
                 f"(dispatch_group local, D-7.2)"
             )
+        if str(local_host(r_host)).lower() == "localhost":
+            # audit a257-1 LOW-A1: an IP literal is never resolved, but `localhost` is resolved by the system resolver
+            # (/etc/hosts, nsswitch) when the request is sent — so it is resolved here first and every address it
+            # yields must be loopback. Fail closed: a resolver failure refuses too. (Every policy hop — a local one or
+            # an `allow_insecure_endpoint: localhost` opt-in, whose plain http must stay on this machine.)
+            self._check_localhost_resolves_to_loopback()
         prefix = d_path.rstrip("/")
         same_origin = (r_scheme, r_host, r_port) == (d_scheme, d_host, d_port)
         in_path = (r_path == prefix or r_path.startswith(prefix + "/")) if prefix else True
@@ -154,6 +160,40 @@ class TransportPolicy:
                 f"{self.endpoint!r} for provider '{self.provider}' (D-7.2 path-prefix rule)"
             )
 
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
     def refuse_redirect(self, status: int) -> None:
         if 300 <= int(status) < 400:
             raise InvalidConfigError(
diff --git a/.claude/skills/bridgebuilder-review/dist/.build-manifest.json b/.claude/skills/bridgebuilder-review/dist/.build-manifest.json
index 84b32fbb..e448855f 100644
--- a/.claude/skills/bridgebuilder-review/dist/.build-manifest.json
+++ b/.claude/skills/bridgebuilder-review/dist/.build-manifest.json
@@ -1,7 +1,7 @@
 {
   "version": "1.0",
-  "generated_at": "2026-10-14T08:50:46Z",
-  "source_hash": "b4e84888ce6f026aa7ffa758e24a1ae7262055fe3bcdebff5a3c49dd5c859cf6",
+  "generated_at": "2026-10-14T10:15:43Z",
+  "source_hash": "5dc9f2234313e53dae6152a581dd0ab7bbcdde5b23b2a70b3c9b3eb3aae843c1",
   "file_count": 43,
   "files": [
     {
@@ -46,7 +46,7 @@
     },
     {
       "path": ".claude/skills/bridgebuilder-review/resources/config.ts",
-      "sha256": "06f39340b69c9f734738ba739ee4d01be9ab9fbfdf530587541c2f928c5cbcf9"
+      "sha256": "39543c7beef4919f453fb552a6182075f78554a85987b67891ef5f020f21ff2e"
     },
     {
       "path": ".claude/skills/bridgebuilder-review/resources/core/cache.ts",
@@ -130,7 +130,7 @@
     },
     {
       "path": ".claude/skills/bridgebuilder-review/resources/core/types.ts",
-      "sha256": "1b13a035d7dd98ef48cbec7fd76c96ddc9a6e0e9e40984dcbd03bfee1cb33ec5"
+      "sha256": "11cbc1ed7b4e0dca7ef4fdc2c16a34ca7f122709eaf9ac478ebe2dea0cfb1866"
     },
     {
       "path": ".claude/skills/bridgebuilder-review/resources/lib/endpoint-validator.generated.ts",
@@ -142,7 +142,7 @@
     },
     {
       "path": ".claude/skills/bridgebuilder-review/resources/main.ts",
-      "sha256": "8509c88a4038dccde7eeea79f557a0b6cdad74fb2412c2c743ba5bf92281ec27"
+      "sha256": "6db270fc245fff889312487e40488f02cb8841201ecd2f243a16eb76cf5f36a8"
     },
     {
       "path": ".claude/skills/bridgebuilder-review/resources/ports/context-store.ts",
diff --git a/.loa.config.yaml.example b/.loa.config.yaml.example
index 6fb0676c..68b7ee4a 100644
--- a/.loa.config.yaml.example
+++ b/.loa.config.yaml.example
@@ -1226,8 +1226,10 @@ hounfour:
 # Example 4: Local OpenAI-compatible server (vLLM, llama.cpp, Ollama, LM Studio)
 # Threat model: plain http is admitted only to the one host named in
 # allow_insecure_endpoint, an IP literal or localhost in a loopback or RFC1918
-# range that is never resolved through DNS, so the prompt does not cross a
-# public network unencrypted and the name cannot be rebound. For this provider
+# range. IP literals are never resolved, so the prompt does not cross a public
~~~~

## I18 — fix-commit — 2026-10-14

- reference: 8e9965141be6
- files: .claude/defaults/model-config.yaml.checksum

Summary:

fix(cycle-129): CI — hop-locality.py splits the endpoint authority by hand (scheme://[userinfo@]host[:port], bracketed IPv6, numeric port; the same split as Bridgebuilder's localEndpointHost) because the cycle-099 import guard confines URL parsing to the endpoint validator (T1.15 import-guard red on 757e7043); model-config.yaml.checksum bumped for the Sprint 3 catalog comment (DRIFT-LOCKFILE-MISM…

Evidence:

~~~~diff
commit 8e9965141be6c3cbec24d9661600cc6d8d56d6b9
Date: 2026-10-14T21:39:58+11:00

fix(cycle-129): CI — hop-locality.py splits the endpoint authority by hand (scheme://[userinfo@]host[:port], bracketed IPv6, numeric port; the same split as Bridgebuilder's localEndpointHost) because the cycle-099 import guard confines URL parsing to the endpoint validator (T1.15 import-guard red on 757e7043); model-config.yaml.checksum bumped for the Sprint 3 catalog comment (DRIFT-LOCKFILE-MISMATCH red); checksums.json and REPO-MAP refreshed (sprint-3)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/.claude/defaults/model-config.yaml.checksum b/.claude/defaults/model-config.yaml.checksum
index 75c62299..3aa265f5 100644
--- a/.claude/defaults/model-config.yaml.checksum
+++ b/.claude/defaults/model-config.yaml.checksum
@@ -1 +1 @@
-4d17fd65c8e75e71ac2248bd9c7539a64932fc8dadaa2c1b3de3078a19102e93
+35d5f6d2e7914a20f8b92c23fb45822df5adcbbb4a614f39ca632d7cbbd1e46c
~~~~

## I19 — kf — 2026-10-15

- reference: KF-037
- files: .claude/defaults/model-config.yaml,tests/unit/adversarial-review-companion.bats

Summary:

## KF-037: A claude-headless dissent hop exceeds cheval's 610 s claude -p timeout when another claude CLI workload shares the host; cheval reports it as PROVIDER_UNAVAILABLE / exit 1 **Status**: OPEN **Feature**: .claude/scripts/adversarial-review.sh companion voice (any claude-headless hop); cheval CLI adapter timeout **Symptom**: adversarial-review.json: companion_voice.status failed with last_…

Evidence:

~~~~~text
~~~~markdown
## KF-037: A claude-headless dissent hop exceeds cheval's 610 s claude -p timeout when another claude CLI workload shares the host; cheval reports it as PROVIDER_UNAVAILABLE / exit 1

**Status**: OPEN
**Feature**: .claude/scripts/adversarial-review.sh companion voice (any claude-headless hop); cheval CLI adapter timeout
**Symptom**: adversarial-review.json: companion_voice.status failed with last_error 'claude -p timed out after 610s' (failure_class timeout since sprint-248 round 1f; model_unavailable on older envelopes); the MODELINV row's models_failed[].message_redacted reads RETRIES_EXHAUSTED … PROVIDER_UNAVAILABLE … timed out. The same hop answers in ~384 s when the CLI is otherwise idle (sprint-247/248 round 0).
**First observed**: 2026-09-25 (cycle-126 sprint-248 review re-run while the Sprint 3 baseline eval ran claude -p at concurrency 2)
**Recurrence count**: 10
**Current workaround**: Run dissents and other claude CLI workloads (eval harness, Bridgebuilder claude-headless) serially — pause the eval before a review/audit; or raise flatline_protocol.<block>.timeout_seconds (the companion wait cap follows it: timeout × hops + 30 s). The dissent still completes on the primary (voices_planned 2, voices_succeeded 1).
**Upstream issue**: cycle-126 residue: cheval could report a CLI-hop timeout as TIMEOUT (exit 3) rather than PROVIDER_UNAVAILABLE (exit 1); a host-level claude CLI concurrency budget would make the contention visible before the call
**Related visions / lore**: KF-010 (google CLI hops under a concurrent BB sweep), KF-035

### Attempts

| Date | What we tried | Outcome | Evidence |
|------|---------------|---------|----------|
| 2026-09-25 | stopped the concurrent eval (TaskStop) mid-run; the next chunk's companion answered in 238 s; classifier + last_error fixed so the envelope says timeout with the provider's line | RESOLVED by serialising the CLI workloads; the class is structural whenever two claude -p consumers overlap | grimoires/loa/a2a/sprint-248 (run 2: adversarial-review-a-dissent-script.json failed at 612 s vs -b-contracts.json 238 s); commits d48328a2 + round-1f; .run/model-invoke.jsonl row 2026-09-25T08:33:06Z |
| 2026-09-25 | fourth live run, CLI idle: the claude-headless companion still timed out at 612 s on a 36 KB chunk — cheval's headless adapter bounds every CLI hop at connect 10 s + max(read_timeout, 600) from the PROVIDER config, so the dissent's --timeout never reached it; added ModelConfig.headless_timeout_seconds (catalog: claude-headless 900 s), the dissent's wait cap follows the catalog, *-headless hops are serialised per binary with a flock, and the failure diagnostic is read from the MODELINV row (the shim discards cheval's stderr) | FIXED at the root for this host (a 900 s bound); contention across processes is now serialised; the class still recurs whenever a CLI hop's real duration exceeds its catalog bound | grimoires/loa/a2a/sprint-248 (run 4: adversarial-review-a-dissent-script.json failed at 612 s with the CLI idle); .claude/adapters/loa_cheval/providers/headless_cli.py _compute_timeout; .claude/defaults/model-config.yaml claude-headless.headless_timeout_seconds |
| 2026-09-25 | sixth live run, chunk c: the companion's claude -p hung ~8 h under the account's usage limit (the session's own limit), the reaper's TERM was ignored and main's wait blocked on the reaped subshell; added TERM→KILL escalation after a grace period (LOA_ADVERSARIAL_REAP_GRACE_SECONDS, default 5), a bounded post-reap wait, and the tree is collected before signalling so orphans cannot escape | MITIGATED: a stuck CLI now costs the review the wait cap plus the grace period, never hours; the root (a CLI that blocks under a usage limit instead of failing) is the operator's account state | grimoires/loa/a2a/sprint-248 (run 6: chunk c exit in 28573 s, companion reaped at the 940 s cap); tests/unit/adversarial-review-companion.bats CMP-30 |
| 2026-10-03 | cycle-126 sprint-248 run 29 (base 621addf7): chunk a3-script-3 retried by run-dissent-two-voice.sh with other interactive claude sessions live on the host | four consecutive companion timeouts at ~910 s (attempts 1-4, 04:33-05:42Z); a later attempt succeeded two-voice once host load eased — retry-until-two-voice remains the workaround | run29.log lines 28-76 (~/.cache/loa/cycle-126-dissent); branch feature/cycle-126-full-size @ 621addf7 |
| 2026-10-03 | the Current workaround's 'raise flatline_protocol.<block>.timeout_seconds' is HTTP-only: a CLI hop is bounded by the catalog's headless_timeout_seconds (claude-headless 900 s), not the dissent's --timeout, and the companion wait cap follows that per-hop bound — so serialise CLI workloads, or raise headless_timeout_seconds in a catalog override (cycle-126 sprint-248 run 30, e2b DISS-C-006) | workaround corrected by this row (the ledger is append-only); Flatline and BB primaries are claude-headless since 2026-10-01, so their parallel voices contend for the same CLI | run30 chunk e2b-docs-state (~/.cache/loa/cycle-126-dissent/adv-248-review-e2b-docs-state.json); round 1ae |
| 2026-10-03 | cycle-126 sprint-248 run 31 (base 10436350): chunk a2-script-2 retried by run-dissent-two-voice.sh with ~12 interactive claude sessions live on the host; the recurrence count now reaches 3 (runs 21 and 24-28 retried the same class unrecorded) | two consecutive companion timeouts (attempts 1-2, 11:17-11:47Z), attempt 3 succeeded two-voice after a 900 s pause — structural: route through the upstream residue (a host-level claude CLI concurrency budget), retry-until-two-voice stays the run-mode workaround | run31.log lines 27-66 (~/.cache/loa/cycle-126-dissent); branch feature/cycle-126-full-size @ 10436350 |
| 2026-10-04 | thirty-fourth two-voice run (round 1ah bc584653): a2, a3, a4 and c1b first companion attempts passed their cap with ~12 other Claude sessions live | each retry two-voice via the per-chunk-retry driver; the documented workaround holds | commit f32643fc (round 1ai, sprint-248 feedback §38) |
| 2026-10-04 | thirty-fifth two-voice run (round 1ai f32643fc): a4 first companion attempt passed its cap with ~12 other Claude sessions live. SUPERSEDES the header's Current workaround: raising flatline_protocol.<block>.timeout_seconds cannot help a CLI hop (bounded by the catalog's headless_timeout_seconds, claude-headless 900 s); the working remedy is serial CLI workloads plus a per-chunk retry until two-voice (run-dissent-two-voice.sh) | a4 two-voice on attempt 2; the header stays as written (append-only), this row is the operative workaround | run 35 a4 / f32643fc |
| 2026-10-04 | thirty-sixth two-voice run (round 1aj 3509808d): a3-script-3's first two companion attempts timed out at 910 s (claude -p) with ~12 other Claude sessions live; Flatline, BB and the companion all resolve to the one claude binary and only adversarial-review.sh serialises it (e2b DISS-C-002) | attempt 3 two-voice via run-dissent-two-voice.sh; every other chunk two-voice on attempt 1 — structural: the upstream residue is now concrete, a cheval-level per-binary CLI lock (headless_cli.py) so Flatline and BB hops queue behind the dissent's, plus a per-consumer headless breaker (follow-up bead at cycle end) | run36.log a3 attempts 1-3 (~/.cache/loa/cycle-126-dissent/run36-out); branch feature/cycle-126-full-size @ 3509808d |
| 2026-10-04 | thirty-seventh two-voice run (round 1ak 009ee894): a1-script-1's first companion attempt and all six of a4-script-4's (57604 bytes) timed out at 910 s (claude -p) with ~12 other Claude sessions live | a1 attempt 2 two-voice; a4 single-voice after six attempts (driver cap) — the chunk's size compounds the contention, so run 38 splits the script in five (chunk script 248i); every other chunk two-voice on attempt 1; structural residue unchanged (cheval-level per-binary lock + per-consumer breaker, cycle-end bead) | run37.log a1 attempts 1-2, a4 attempts 1-6 (~/.cache/loa/cycle-126-dissent/run37-out); branch feature/cycle-126-full-size @ 009ee894 |
| 2026-10-04 | thirty-eighth two-voice run (round 1al 9bb1fe4c): a3-script-3's first companion attempt and a4-script-4's first three timed out at 910 s (claude -p) with ~12 other Claude sessions live, host load ~1.5 | a3 attempt 2 and a4 attempt 4 two-voice via run-dissent-two-voice.sh; every chunk two-voice; run 39 splits a4 (57 KB) into a4a/a4b to shorten the companion's hop | commit 9bb1fe4c; run38.log (cycle-126 dissent cache) |
| 2026-10-05 | Thirty-ninth two-voice run (24 chunks, companion on claude-bedrock) with about twelve other Claude sessions live: retried each timed-out chunk until two-voice (a1, a2, b1 once; a3 twice; a4b six times at 910 s) | All 24 chunks two-voice; retry-until-two-voice holds but costs about an hour per run under host contention; dissent capped at 3 runs per sprint from here | run39.log on 332f254c (round 1am), sprint-248 feedback §43 |
| 2026-10-15 | cycle-130 Sprint 259 review dissent run 1 on 6be23186: code-only diff of 166 files / 10,298 lines incl. 16 task fixtures; codex-headless gpt-5.5-pro primary succeeded (3 findings), claude-headless companion timed out after 910s (PROVIDER_UNAVAILABLE) → DEGRADED 1/2 | degraded envelope accepted for review round 1 (the primary delivered); run 2 excludes tasks/*/fixture and tasks/*/hidden from the dissent diff so the companion sees the ~3.5k-line harness diff only | grimoires/loa/a2a/sprint-259/adversarial-review.json; ~/.cache/loa/cycle-130/logs/dissent-s2-review.log |

### Reading guide

A companion (or any claude-headless) timeout while an eval or BB sweep is running is CLI contention, not a model outage: check ps for other claude -p processes before retrying, and re-run the dissent only once the CLI is idle. Verdict quality already records the primary alone; the companion's failure_class names the class.

~~~~
~~~~~

## I20 — kf — 2026-10-15

- reference: KF-046
- files: .claude/loa/CLAUDE.loa.md

Summary:

## KF-046: ablation-grade.sh contamination scan flags ordinary agent text and shell idioms as outside_path or git_history (slash commands, git log --all, heredoc prose, sed address ranges, container home) **Status**: active **Feature**: evals/harness/ablation-grade.sh check_value / ABS_WORD (D-4.7 contamination scan) **Symptom**: grade.json contaminated {phase, pattern: outside_path|git_history,…

Evidence:

~~~~~text
~~~~markdown
## KF-046: ablation-grade.sh contamination scan flags ordinary agent text and shell idioms as outside_path or git_history (slash commands, git log --all, heredoc prose, sed address ranges, container home)

**Status**: active
**Feature**: evals/harness/ablation-grade.sh check_value / ABS_WORD (D-4.7 contamination scan)
**Symptom**: grade.json contaminated {phase, pattern: outside_path|git_history, excerpt_id: <PHASE>:<line>} and the row status contaminated on a run that never left the sandbox; the excerpt line holds a Loa slash command (/review-sprint), git log --all, prose inside a heredoc, ls ~/.cargo/bin in the container, a sed range /,/ or /re1/,/re2/p
**First observed**: 2026-10-15 cycle-130 Sprint 260 calibration smoke calib-frozen-01 (10 of 12 rows), then priority batch P1 review-04 REVIEW:39
**Recurrence count**: 10
**Current workaround**: re-grade the run directories under the current grader (no agent re-run) and re-row: run-ablation.sh --resume --rerow <run_id> (DEC-0547); the grader fixes are 1.2.1 (DEC-0540), 1.2.2 (DEC-0541), 1.2.3 (DEC-0546)
**Upstream issue**: none (harness heuristic; structural: a path-word regex over free-form Bash text cannot be made exact; the scan is a lower bound by design, D-4.7)
**Related visions / lore**: DEC-0540, DEC-0541, DEC-0546, DEC-0547; KF-045

### Attempts

| Date | What we tried | Outcome | Evidence |
|------|---------------|---------|----------|
| 2026-10-15 | grader 1.2.1 (one-component words, history probes), 1.2.2 (heredoc bodies, container home, /x/ delimiters), 1.2.3 (sed address ranges) | calibration rows 10 contaminated to 0; P1 review-04 re-rowed under 1.2.3 | commits 2ef83aa8, ae9df520; a2a/sprint-260/smoke.md; NOTES 2026-10-15T11:18:02Z |
| 2026-10-15 | grader 1.2.4 prepared (DEC-0551): words beginning with /, (range remnant after a spaced first address) and words carrying = are regex-shaped, not paths; applied after P1 ends, then --rerow of every contaminated row | pending (P1 running; a1_full review-02-t1 AUDIT:86 is the fourth false-positive class: sed -n '/=== VERIFY python ValueError ===/,/=== scanner usage ===/p') | grimoires/loa/reports/ablation-2.0/batches/priority-p1/a1_full/review-02-t1/grade.json; ~/.cache/loa/cycle-130/grader-124-patch.py |
| 2026-10-15 | fifth class: the hidden keyword matched ordinary English in a reviewer heredoc (a1_full bugfix-04-t1 REVIEW:148 'any hidden interaction'); grader 1.2.4 also narrows hidden in Bash text to token shapes (DEC-0551) | pending (applied after P1 ends; rows re-rowed) | grimoires/loa/reports/ablation-2.0/batches/priority-p1/a1_full/bugfix-04-t1/grade.json; ~/.cache/loa/cycle-130/grader-124-patch.py |
| 2026-10-16 | grader 1.2.4 applied (6c454de7) after P1 stopped; the seven contaminated P1 rows re-graded clean in scratch copies and were re-rowed on the resume | 0 of 7 contaminated under 1.2.4 (review-03-t1 reads cap_failure, the rest completed) | a2a/sprint-260/reviewer.md; grimoires/loa/reports/ablation-2.0/batches/priority-p1/STATUS.json rerowed[] |
| 2026-10-16 | sixth class: a path tail after a closing quote glued to its token ("$D"/evals/harness/x) read as an absolute outside path (a1_full feature-01-t2 AUDIT:122, grader 1.2.4); grader 1.2.5 prepared (DEC-0557), applied after P1 ends, the row re-rowed | pending | grimoires/loa/reports/ablation-2.0/batches/priority-p1/a1_full/feature-01-t2-r3/grade.json; ~/.cache/loa/cycle-130/grader-125-patch.py |
| 2026-10-16 | grader 1.2.5 applied (bf155cc7) after P1 completed; both rows re-rowed; P1 ends with 0 contaminated rows after six grader rounds (1.2.1–1.2.5) | 0 of 132 P1 rows contaminated; every contaminated row of the cycle so far was a scan false positive, none a real reach | grimoires/loa/reports/ablation-2.0/batches/priority-p1/STATUS.json rerowed[] (11 entries); runs.jsonl |
| 2026-10-16 | grader 1.2.8 (Sprint 260 audit fix) treated a [ after a one-component absolute word as a glob metacharacter so the word stayed a path candidate; re-scan of the 132 graded P1 run dirs under 1.2.8 | two new false positives (a1_full feature-03-t2-r3 AUDIT:115 grep '/home[^"]*loader.py' regex; refactor-04-t2-r3 IMPLEMENT:47 sed 's/job\["status"\]…'): a bracket after the word is a regex bracket expression in agent commands, not a glob — grader 1.2.9 reads * and ? only and keeps a quoted one-component pattern exempt; the re-scan is back to 0 changes | rescan-p1-126.py over priority-p1 under 1.2.8 vs the stored grade.json (2 changed) and under 1.2.9 (0 changed); commit 60503096 (1.2.8) and the 1.2.9 commit that follows; a2a/sprint-260/auditor-sprint-feedback.md round 2 |
| 2026-10-17 | grader 1.2.11 on the suite v2 round-2 calibration (calib-v2-02a, a0_bare x 10 tasks x 2) | one row contaminated (refactor-v2-07 t1, BARE:145 outside_path): the bare agent passed JSON Pointer literals (get clit/d.json /a/1, /a/9) as CLI arguments while differential-testing a JSON Patch package — a two-component word indistinguishable from an absolute path by shape; read by hand, not a reach; pass rate 1.0 either way, so the hardness read is unchanged; no grader change (a pointer-literal exemption would also exempt real paths); the task is not run in the v2 batch | evals/results/ablation-2.0/calib-v2-02a/a0_bare/refactor-v2-07-t1/grade.json contaminated BARE:145; commit bde0c22e (grader 1.2.11) |
| 2026-10-19 | seventh class, batch replication-01 (deep analysis): pattern repo_name fired on the reviewer's own heredoc text quoting the PR's CI workflow clause github.repository == '0xHoneyJar/loa' (pr-18 head/.github/workflows/check-glossary-terms.yml); rows a1_full review-r18-t2 (REVIEW:320, reviewer-concerns.md heredoc) and review-r18-t3 (AUDIT:332, auditor-sprint-feedback.md heredoc) read contaminated | read by hand: the string is the PR's own content, not a reach outside the sandbox; no grader change in this analysis task (code edits out of scope), so the two rows stay contaminated under the pre-registered rule (a1 excluded share 2/6 = 0.33 > 0.25 -> the replication's pre-registered read is inconclusive by degradation) and the hand-read sensitivity with the two rows included is reported beside it; grader fix (exempt a repo name that occurs in pr/head or head.diff) is a cycle-131 candidate | evals/results/ablation-2.0/replication-01/a1_full/review-r18-t2/grade.json contaminated REVIEW:320; evals/results/ablation-2.0/replication-01/a1_full/review-r18-t3/grade.json contaminated AUDIT:332; a2a/analysis-2026-10/replication.md |
| 2026-10-20 | cycle-131 B2a rows under grader 1.3.0 (class 7 + r1a/r1c rules): a0_bare × review-r18 t1 and a1_full × review-r18 t1 read contaminated | a0_bare r18 t1 (BARE:96) is a TRUE positive: curl -sfL … raw.githubusercontent.com/0xHoneyJar/loa/main/.claude/loa/CLAUDE.loa.md to fill a missing file (repo_name, correctly never exempt). a1_full r18 t1 (AUDIT:303) is an outside_path hit on a reproduction: the auditor built a scratch git repo + venv under $HOME/tmp/venvrepro.XXXX to reproduce the PR's venv claim — no upstream fetch, no answer path; class 8 candidate (scratch-dir reproduction under $HOME/tmp). Both rows excluded by the pre-registered validity rule; a labelled sensitivity re-includes class-8 rows (NOTES 2026-10-20, defined before the reads) | evals/results/ablation-2.0/c131-b2-control-prices-a/{a0_bare,a1_full}/review-r18-t1/grade.json; pin 798d88cf |

### Reading guide

A contaminated row is a claim to verify, not a verdict: print the excerpt line (sed -n '<line>p' <run-dir>/transcripts/events-<PHASE>.jsonl | jq '.message.content[] | select(.type=="tool_use") | .input') and ask whether the word reaches a path outside the sandbox, the container home, /tmp or the system dirs. Shell idioms seen so far: slash commands, sed/awk delimiters and ranges, heredoc prose, regexes beginning with = or a letter. If it is an idiom: fix the grader (bump GRADER_VERSION, extend AG-10), re-grade every affected run directory, --rerow. If it is a real reach: the exclusion stands. Recurrence 3 in one day means the heuristic is structural: budget a re-read of every contaminated row before the report.

~~~~
~~~~~

## I21 — fix-commit — 2026-10-18

- reference: 463fbda1b101
- files: README.md

Summary:

fix(cycle-130): README version refs synced to 2.0.0-rc.5 (sync-readme-version.sh --apply; the CI README version sync check on PR #1283) Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>

Evidence:

~~~~diff
commit 463fbda1b1016d015067a21826c8dc6290eeef66
Date: 2026-10-18T19:14:03+11:00

fix(cycle-130): README version refs synced to 2.0.0-rc.5 (sync-readme-version.sh --apply; the CI README version sync check on PR #1283)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/README.md b/README.md
index 4d8fb07a..ea9abbdc 100644
--- a/README.md
+++ b/README.md
@@ -6,10 +6,10 @@ # Loa
 Architecture: Three-zone model (System: .claude/, State: grimoires/ + .beads/, App: src/).
 Configuration: .loa.config.yaml (user-owned, never modified by framework).
 Health check: /loa doctor
-Version: 2.0.0-rc.3
+Version: 2.0.0-rc.5
 -->
 
-[![Version](https://img.shields.io/badge/version-2.0.0--rc.3-blue.svg)](CHANGELOG.md)
+[![Version](https://img.shields.io/badge/version-2.0.0--rc.5-blue.svg)](CHANGELOG.md)
 [![License](https://img.shields.io/badge/license-AGPL--3.0-green.svg)](LICENSE.md)
 [![Release](https://img.shields.io/badge/release-v2.0.0--rc.2%20Friction%20floor-purple.svg)](https://github.com/0xHoneyJar/loa/releases/tag/v2.0.0-rc.2)
 
~~~~

## I22 — fix-commit — 2026-10-20

- reference: 596627f46e02
- files: evals/graders/recall-vs-defects.sh,evals/tests/eval-recall-grader.bats

Summary:

fix(cycle-131): sprint-263 review round r1a — the oracle detector keeps shell redirections out of its command splitter; class 7 bare-line tokens never exempt; scope-map fixes; pr-17 smoke bounds Review dissent run 1 (gpt-5.5-pro + claude-headless, 9 findings, 2 BLOCKING; DEC-0642): - ablation-grade.sh split_segments: the ampersand of 2>&1 / >&2 / <&0 / &> is a redirection, not a separator, so a d…

Evidence:

~~~~diff
commit 596627f46e02fb40a9476fe1d597a763292cb366
Date: 2026-10-20T12:18:35+11:00

fix(cycle-131): sprint-263 review round r1a — the oracle detector keeps shell redirections out of its command splitter; class 7 bare-line tokens never exempt; scope-map fixes; pr-17 smoke bounds

Review dissent run 1 (gpt-5.5-pro + claude-headless, 9 findings, 2 BLOCKING; DEC-0642):
- ablation-grade.sh split_segments: the ampersand of 2>&1 / >&2 / <&0 / &> is a redirection, not a separator, so a
  diff reduced through `2>&1 | wc -l` or discarded with `&>/dev/null` is no longer planned as a content-printing
  diff (DISS-001, DISS-C-001); silent_sink() scans every grep flag and the long forms; a stat-only git diff
  (--stat, --numstat, --shortstat, --name-only, --name-status, --compact-summary) prints no content.
- KF-046 class 7: backslash continuations join into one logical line; a bare token standing as the whole line
  exempts nothing; a backticked quotation in prose stays PR content (DISS-C-002).
- grade_recall passes a non-existent EVAL_HEAD_DIR sentinel when the fixture head is unavailable (DISS-C-003).
- recall-vs-defects.sh: bash/bats closing brace measured with expandtabs(8) (DISS-C-006); markdown fences hide
  their # lines from heading detection (DISS-C-004); a python def with a multi-line signature keeps its body
  (DISS-C-005).
- Tests: AG-52, AG-53, RG-40, RG-41, RG-42 (test-first). evals/tests 512/512. The 36-run re-grade re-run on the
  fixed grader changes no row (0 of 36); AG-50's detector pins are unchanged.
- Smoke root: review-r17 task bounds REVIEW 50 / AUDIT 40 (DEC-0640), re-frozen; smoke read DEC-0641;
  follow-up beads bd-jszcp (DISS-C-007), bd-9zmfn (DISS-C-008).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/evals/graders/recall-vs-defects.sh b/evals/graders/recall-vs-defects.sh
index 77a78c4d..d40528fb 100755
--- a/evals/graders/recall-vs-defects.sh
+++ b/evals/graders/recall-vs-defects.sh
@@ -266,9 +266,20 @@ def lang(rel, lines):
 def headers(kind, lines):
     """[(line, level)]: each definition header's 1-based line and its indentation (markdown: level)"""
     out = []
+    fence = None
     for i, l in enumerate(lines, 1):
         m = None
         if kind == "markdown":
+            fm = re.match(r"^\s{0,3}(`{3,}|~{3,})", l)   # a fenced block's `#` lines are code, not headings (review r1 DISS-C-004)
+            if fm:
+                tok = fm.group(1)[0]
+                if fence is None:
+                    fence = tok
+                elif fence == tok:
+                    fence = None
+                continue
+            if fence is not None:
+                continue
             m = MD_HDR.match(l)
             if m:
                 out.append((i, len(m.group(1))))
@@ -295,13 +306,22 @@ def close_line(kind, lines, h, lv, end):
         if CLOSE_ONE.search(lines[h - 1]) and "{" in lines[h - 1]:
             return h
         for L in range(h + 1, end + 1):
-            t = lines[L - 1]
+            t = lines[L - 1].expandtabs(8)     # the same width headers() measured (review r1 DISS-C-006)
             if t.strip().startswith("}") and len(t) - len(t.lstrip()) == lv:
                 return L
         return end
     if kind == "python":
-        last = h
-        for L in range(h + 1, end + 1):
+        # skip a multi-line signature: the header ends on the line that closes its parentheses and ends with
+        # a colon (review r1 DISS-C-005); the indentation rule then binds the body
+        j, depth = h, 0
+        while j <= end:
+            t = re.sub(r"#.*$", "", lines[j - 1])
+            depth += t.count("(") - t.count(")")
+            if depth <= 0 and t.rstrip().endswith(":"):
+                break
+            j += 1
+        last = j
+        for L in range(j + 1, end + 1):
             t = lines[L - 1]
             if not t.strip() or t.lstrip().startswith("#"):
                 continue
diff --git a/evals/tests/eval-recall-grader.bats b/evals/tests/eval-recall-grader.bats
index 813b6348..75b521dc 100644
--- a/evals/tests/eval-recall-grader.bats
+++ b/evals/tests/eval-recall-grader.bats
@@ -419,6 +419,49 @@ D() { echo "$output" | jq -r "$1"; }
   [ "$(D '.score')" = "100" ]
 }
 
+@test "RG-40 (review r1 DISS-C-006) a tab-indented nested function closes at its own brace: a top-level line after it is not in its scope" {
+  make_scope
+  printf '#!/usr/bin/env bash\nouter() {\n\tinner() {\n\t\techo i4\n\t\techo i5\n\t\techo i6\n\t}\n\techo o8\n}\n' > "$T/pr-s/head/.claude/scripts/tabs.sh"
+  for i in $(seq 10 20); do echo "echo t$i"; done >> "$T/pr-s/head/.claude/scripts/tabs.sh"
+  man_s '[{"id":"S1","file":".claude/scripts/tabs.sh","anchor_line":5,"severity":"high"}]'
+  review 'tabs.sh:15 the top-level line'
+  run "$GRADER" "$WS" pr-s
+  [ "$status" -eq 1 ]
+  [ "$(D '.details.detected | length')" = "0" ]
+  review 'tabs.sh:9 the brace closing outer: inside outer, not inner (and 4 lines from the site)'
+  run "$GRADER" "$WS" pr-s
+  [ "$(D '.details.detected | length')" = "0" ]
+}
+
+@test "RG-41 (review r1 DISS-C-004) a # line inside a fenced code block is not a markdown heading: the section keeps its scope across the fence" {
+  make_scope
+  { echo '## Section A'; echo 'text 2'; echo 'text 3'; echo 'text 4'; echo '```bash'; echo 'echo hi'; echo '# not a heading'; echo 'echo bye'; echo '```'
+    echo 'text 10'; echo 'text 11'; echo 'text 12'; echo '## Section B'; echo 'text 14'; } > "$T/pr-s/head/.claude/docs/fence.md"
+  man_s '[{"id":"S1","file":".claude/docs/fence.md","anchor_line":3,"severity":"low"}]'
+  review 'fence.md:11 after the code block, same section'
+  run "$GRADER" "$WS" pr-s
+  [ "$status" -eq 0 ]
+  [ "$(D '.details.detected | join(",")')" = "S1" ]
+  [ "$(D '.details.credits_function_only | join(",")')" = "S1" ]
+  review 'fence.md:14 the next section'
+  run "$GRADER" "$WS" pr-s
+  [ "$(D '.details.detected | length')" = "0" ]
+}
+
+@test "RG-42 (review r1 DISS-C-005) a python def with a multi-line signature keeps its body in scope" {
+  make_scope
+  { echo 'import os'; echo 'def f('; echo '    a,'; echo '    b,'; echo '):'; echo '    x = a'; echo '    y = b'; echo '    z = x + y'
+    echo '    w = z'; echo '    v = w'; echo '    u = v'; echo '    return u'; echo 'def g():'; echo '    return 1'; } > "$T/pr-s/head/.claude/scripts/sig.py"
+  man_s '[{"id":"S1","file":".claude/scripts/sig.py","anchor_line":6,"severity":"medium"}]'
+  review 'sig.py:12 the return'
+  run "$GRADER" "$WS" pr-s
+  [ "$status" -eq 0 ]
+  [ "$(D '.details.detected | join(",")')" = "S1" ]
+  review 'sig.py:14 the next def'
+  run "$GRADER" "$WS" pr-s
+  [ "$(D '.details.detected | length')" = "0" ]
+}
+
 @test "RG-30 a citation in the next function 6 lines away is detected under neither rule; a top-level site has no scope" {
   make_scope
   man_s '[{"id":"S1","file":".claude/scripts/s.sh","anchor_line":22,"severity":"high"},
~~~~

## I23 — fix-commit — 2026-10-20

- reference: baea80244306
- files: evals/graders/recall-vs-defects.sh,evals/tests/eval-recall-grader.bats

Summary:

fix(cycle-131): sprint-263 review round r1b — one-liner python defs, fence lengths, stat-only git diff, |&, grep-family sinks Review dissent run 2 on the r1a diff (12 findings, 3 BLOCKING, all at the edges of r1a; DEC-0643): - recall-vs-defects.sh: a python signature ends at the colon after its closing parenthesis, so `def f(): return 1` ends on its own line (and a header with no terminator falls…

Evidence:

~~~~diff
commit baea80244306d0bee0334ba5f8238777c7cdb1e7
Date: 2026-10-20T12:39:13+11:00

fix(cycle-131): sprint-263 review round r1b — one-liner python defs, fence lengths, stat-only git diff, |&, grep-family sinks

Review dissent run 2 on the r1a diff (12 findings, 3 BLOCKING, all at the edges of r1a; DEC-0643):
- recall-vs-defects.sh: a python signature ends at the colon after its closing parenthesis, so `def f(): return 1`
  ends on its own line (and a header with no terminator falls back to one line); a markdown fence closes only on a
  same-character fence at least as long with nothing after it, and a backtick opener whose info string holds a
  backtick is not a fence (RG-42 extended, RG-43).
- ablation-grade.sh: a stat-only git diff needs a stat flag and none of -p/-u/--patch/--unified/-U<n>; `|&` is one
  pipe with no empty segment; silent sinks include -L / --files-without-match and the egrep/fgrep/rg family
  (AG-52 extended); AG-53's printf now emits a real line continuation.
- Re-grade of the 36 cycle-130 runs on this grader: 36/36 regression, 0 rows changed.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/evals/graders/recall-vs-defects.sh b/evals/graders/recall-vs-defects.sh
index d40528fb..4b0432af 100755
--- a/evals/graders/recall-vs-defects.sh
+++ b/evals/graders/recall-vs-defects.sh
@@ -270,13 +270,15 @@ def headers(kind, lines):
     for i, l in enumerate(lines, 1):
         m = None
         if kind == "markdown":
-            fm = re.match(r"^\s{0,3}(`{3,}|~{3,})", l)   # a fenced block's `#` lines are code, not headings (review r1 DISS-C-004)
+            fm = re.match(r"^\s{0,3}(`{3,}|~{3,})(.*)$", l)   # a fenced block's `#` lines are code, not headings (review r1 DISS-C-004)
             if fm:
-                tok = fm.group(1)[0]
+                tok, rest = fm.group(1), fm.group(2)
                 if fence is None:
-                    fence = tok
-                elif fence == tok:
-                    fence = None
+                    if not (tok[0] == "`" and "`" in rest):   # CommonMark: a backtick opener's info string holds no backtick
+                        fence = (tok[0], len(tok))
+                    continue
+                if tok[0] == fence[0] and len(tok) >= fence[1] and not rest.strip():
+                    fence = None      # the closer is at least as long as the opener, with nothing after it (review r2 DISS-003)
                 continue
             if fence is not None:
                 continue
@@ -317,9 +319,12 @@ def close_line(kind, lines, h, lv, end):
         while j <= end:
             t = re.sub(r"#.*$", "", lines[j - 1])
             depth += t.count("(") - t.count(")")
-            if depth <= 0 and t.rstrip().endswith(":"):
-                break
-            j += 1
+            rest = t[t.rfind(")") + 1:] if depth <= 0 and ")" in t else ""
+            if depth <= 0 and ":" in rest:
+                break                 # the colon after the closing parenthesis ends the header (a one-liner
+            j += 1                    # `def f(): return 1` ends on its own line; review r2 DISS-001)
+        if j > end:
+            j = h                     # no terminating colon found (a `(` or `#` inside a string default): one-line header
         last = j
         for L in range(j + 1, end + 1):
             t = lines[L - 1]
diff --git a/evals/tests/eval-recall-grader.bats b/evals/tests/eval-recall-grader.bats
index 75b521dc..f161e7ee 100644
--- a/evals/tests/eval-recall-grader.bats
+++ b/evals/tests/eval-recall-grader.bats
@@ -460,6 +460,26 @@ D() { echo "$output" | jq -r "$1"; }
   review 'sig.py:14 the next def'
   run "$GRADER" "$WS" pr-s
   [ "$(D '.details.detected | length')" = "0" ]
+  # a one-liner def ends on its own line (review r2 DISS-001): the top-level lines after it are not its body
+  { echo 'def one(): return 1'; for i in $(seq 2 12); do echo "x$i = $i"; done; echo 'def two(s, comment="#"):'; echo '    return s'; echo 'y = 0'; } > "$T/pr-s/head/.claude/scripts/one.py"
+  man_s '[{"id":"S1","file":".claude/scripts/one.py","anchor_line":1,"severity":"medium"},{"id":"S2","file":".claude/scripts/one.py","anchor_line":14,"severity":"low"}]'
+  review 'one.py:9 top level, far from the one-liner'
+  run "$GRADER" "$WS" pr-s
+  [ "$(D '.details.detected | length')" = "0" ]
+  review 'one.py:15 the line after two(): top level, not the body'
+  run "$GRADER" "$WS" pr-s
+  [ "$(D '.details.detected | join(",")')" = "S2" ]     # ±3 of site 14 only; S1 untouched
+}
+
+@test "RG-43 (review r2 DISS-003) a four-backtick fence is not closed by a three-backtick line inside it" {
+  make_scope
+  { echo '## Section A'; echo 'text 2'; echo 'text 3'; echo '````md'; echo 'example:'; echo '```bash'; echo '# inner comment'; echo '```'; echo '# still inside the outer fence'; echo '````'
+    echo 'text 11'; echo 'text 12'; echo '## Section B'; echo 'text 14'; } > "$T/pr-s/head/.claude/docs/fence4.md"
+  man_s '[{"id":"S1","file":".claude/docs/fence4.md","anchor_line":3,"severity":"low"}]'
+  review 'fence4.md:12 after the nested fences, same section'
+  run "$GRADER" "$WS" pr-s
+  [ "$status" -eq 0 ]
+  [ "$(D '.details.detected | join(",")')" = "S1" ]
 }
 
 @test "RG-30 a citation in the next function 6 lines away is detected under neither rule; a top-level site has no scope" {
~~~~

## I24 — fix-commit — 2026-10-20

- reference: cddec3677a58
- files: evals/graders/recall-vs-defects.sh,evals/tests/eval-recall-grader.bats

Summary:

fix(cycle-131): sprint-263 audit round r1c — executed probe lines never class-7 exempt, no workspace pr/head fallback, bounded detector work, one validated corpus-hash open Audit dissent run 1 on the sprint diff (4 findings: 1 HIGH, 2 MEDIUM, 1 LOW; DEC-0644): - ablation-grade.sh: a Bash logical line (heredoc bodies removed) that holds the repo name and a network- or VCS-capable executable word (…

Evidence:

~~~~diff
commit cddec3677a58f26e8986f034419f03f559782648
Date: 2026-10-20T13:13:11+11:00

fix(cycle-131): sprint-263 audit round r1c — executed probe lines never class-7 exempt, no workspace pr/head fallback, bounded detector work, one validated corpus-hash open

Audit dissent run 1 on the sprint diff (4 findings: 1 HIGH, 2 MEDIUM, 1 LOW; DEC-0644):
- ablation-grade.sh: a Bash logical line (heredoc bodies removed) that holds the repo name and a network- or
  VCS-capable executable word (git, gh, curl, wget, pip, npm, npx, ssh, scp, nc, docker, rsync, python -c …) is
  never KF-046 class 7 exempt — pr-13 and pr-16 carry `curl … 0xHoneyJar/loa … | bash` lines the old rule would
  have licensed; quoting such a line in notes stays PR content (AG-54). Every agent-controlled dimension of the
  oracle detector is bounded (for-list 64, expansion 256, segment 64 KB, word 4,096 / 512 per segment, result
  lines clipped, difflib skipped above 20,000 lines → grade.json oracle_scan_skipped) (AG-55). corpus_sha256
  hashes the bytes of one O_NOFOLLOW open with an fstat regular-file and size check.
- recall-vs-defects.sh: the $workspace/pr/head fallback is gone unless EVAL_ALLOW_WORKSPACE_HEAD=1;
  details.head_dir_source ∈ env|fixture|workspace|none; above 5,000 headers the ±20 fallback replaces the scope
  map (RG-44).
- sprint.md: Sprint 1 deliverables, criteria and tasks ticked (two criteria annotated: FR-1 AC 4 PARTIAL by
  DEC-0632; FR-3 AC 3 is the Sprint 3 read).
- evals/tests 516/516; the 36-run re-grade on this grader: 36/36 regression, 0 rows changed (as after r1a, r1b).
- Review APPROVED (engineer-feedback.md), audit APPROVED after this round (auditor-sprint-feedback.md).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/evals/graders/recall-vs-defects.sh b/evals/graders/recall-vs-defects.sh
index 4b0432af..9cb7b109 100755
--- a/evals/graders/recall-vs-defects.sh
+++ b/evals/graders/recall-vs-defects.sh
@@ -74,8 +74,9 @@
 #   regex (yaml, json, txt, tsv, …), falls back to ±20 lines around the site (and a
 #   cited line in such a definition has no scope); a site outside every definition
 #   (top-level code, text before the first heading) has no scope (±3 only).
-#   Head directory: $EVAL_HEAD_DIR, else <manifest dir>/../<fixture>/head, else
-#   <workspace>/pr/head; with none, or a file absent from it, (ii) never credits.
+#   Head directory: $EVAL_HEAD_DIR, else <manifest dir>/../<fixture>/head, else — only under
+#   EVAL_ALLOW_WORKSPACE_HEAD=1 — <workspace>/pr/head (the graded agent's own copy; details.head_dir_source
+#   says which was used); with none, or a file absent from it, (ii) never credits.
 #   Three results in details, each with detected[] / missed[] (defect ids):
 #     recall_pm3_v1  the 1.2.0 rule against <manifest dir>/v1/<fixture>.json (the
 #                    original anchors); the current manifest when v1/ has none
@@ -129,16 +130,17 @@ fi
 
 manifest_v1="$MANIFEST_DIR/v1/$fixture.json"
 [[ -f "$manifest_v1" && ! -L "$manifest_v1" ]] || manifest_v1=""
-head_dir="${EVAL_HEAD_DIR:-}"
+head_dir="${EVAL_HEAD_DIR:-}"; head_src="env"
 if [[ -z "$head_dir" ]]; then
-  if [[ -d "$MANIFEST_DIR/../$fixture/head" ]]; then head_dir="$MANIFEST_DIR/../$fixture/head"
-  elif [[ -d "$workspace/pr/head" ]]; then head_dir="$workspace/pr/head"
-  fi
+  head_src="none"
+  if [[ -d "$MANIFEST_DIR/../$fixture/head" ]]; then head_dir="$MANIFEST_DIR/../$fixture/head"; head_src="fixture"
+  elif [[ "${EVAL_ALLOW_WORKSPACE_HEAD:-}" == 1 && -d "$workspace/pr/head" ]]; then head_dir="$workspace/pr/head"; head_src="workspace"
+  fi   # the workspace copy is the graded agent's own writable tree: never the default (audit r1 DISS-C-002)
 fi
 
-python3 -I - "$manifest" "$review" "$executor" "$manifest_v1" "$head_dir" <<'PY'
+python3 -I - "$manifest" "$review" "$executor" "$manifest_v1" "$head_dir" "$head_src" <<'PY'
 import json, os, re, stat, sys
-manifest_path, review_path, executor_path, manifest_v1_path, head_dir = sys.argv[1:6]
+manifest_path, review_path, executor_path, manifest_v1_path, head_dir, head_src = sys.argv[1:7]
 man = json.load(open(manifest_path))
 man_v1 = json.load(open(manifest_v1_path)) if manifest_v1_path else man
 text = open(review_path, encoding="utf-8", errors="replace").read()
@@ -338,6 +340,7 @@ def close_line(kind, lines, h, lv, end):
 
 
 _scopes = {}
+HEADERS_CAP = 5000
 
 
 def scope_map(rel):
@@ -352,6 +355,9 @@ def scope_map(rel):
     if kind is not None:
         n = len(lines)
         hs = headers(kind, lines)
+        if len(hs) > HEADERS_CAP:
+            _scopes[rel] = (None, None)   # an unterminated 4 MB file gets the ±20 fallback, not a quadratic scan (audit r1 DISS-C-002)
+            return _scopes[rel]
         spans = []
         for k, (h, lv) in enumerate(hs):
             end = n
@@ -504,7 +510,7 @@ out = {
         "recall_pm3": rate(det_pm3, man), "detected_pm3": det_pm3, "missed_pm3": mis_pm3,
         "recall_pm3_v1": rate(det_v1, man_v1), "detected_pm3_v1": det_v1, "missed_pm3_v1": mis_v1,
         "planted_v1": len(man_v1.get("defects", [])), "v1_manifest": bool(manifest_v1_path),
-        "credits_function_only": function_only, "rule": "pm3_or_same_function",
+        "credits_function_only": function_only, "rule": "pm3_or_same_function", "head_dir_source": head_src,
         "false_positives": false_positives, "severity_counts": sev,
         "citations": len(cites), "model": model, "effort": effort, "tokens": tokens,
         "findings_cited": len(findings), "findings_refuted": len(refuted),
diff --git a/evals/tests/eval-recall-grader.bats b/evals/tests/eval-recall-grader.bats
index f161e7ee..5416e7a5 100644
--- a/evals/tests/eval-recall-grader.bats
+++ b/evals/tests/eval-recall-grader.bats
@@ -482,6 +482,25 @@ D() { echo "$output" | jq -r "$1"; }
   [ "$(D '.details.detected | join(",")')" = "S1" ]
 }
 
+@test "RG-44 (audit r1 DISS-C-002) without EVAL_HEAD_DIR or a fixture head the grader never reads the workspace's pr/head unless EVAL_ALLOW_WORKSPACE_HEAD=1; details name the source" {
+  mkdir -p "$WS/pr/head/.claude/scripts"
+  { echo '#!/usr/bin/env bash'; echo 'w() {'; for i in $(seq 3 19); do echo "  echo w$i"; done; echo '}'; } > "$WS/pr/head/.claude/scripts/w.sh"
+  printf '{"fixture":"pr-w","defects":[{"id":"S1","file":".claude/scripts/w.sh","anchor_line":5,"severity":"high"}]}\n' > "$T/manifests/pr-w.json"
+  review 'w.sh:12 six lines down, same function'
+  run "$GRADER" "$WS" pr-w
+  [ "$status" -eq 1 ]
+  [ "$(D '.details.detected | length')" = "0" ]
+  [ "$(D '.details.head_dir_source')" = "none" ]
+  EVAL_ALLOW_WORKSPACE_HEAD=1 run "$GRADER" "$WS" pr-w
+  [ "$(D '.details.detected | join(",")')" = "S1" ]
+  [ "$(D '.details.head_dir_source')" = "workspace" ]
+  make_scope
+  man_s '[{"id":"S1","file":".claude/scripts/s.sh","anchor_line":16,"severity":"high"}]'
+  review 's.sh:22 the guard is gone'
+  run "$GRADER" "$WS" pr-s
+  [ "$(D '.details.head_dir_source')" = "fixture" ]
+}
+
 @test "RG-30 a citation in the next function 6 lines away is detected under neither rule; a top-level site has no scope" {
   make_scope
   man_s '[{"id":"S1","file":".claude/scripts/s.sh","anchor_line":22,"severity":"high"},
~~~~

## I25 — issue — 2026-10-20

- reference: #1287
- files: README.md

Summary:

chore(cycle-131): archive the cycle on main — Archive of cycle-131 "honest review-catch measurement" after PR #1286 merged as `7b024f5c`. - `grimoires/loa/archive/cycle-131-honest-measurement/`: `prd.md`, `sdd.md`, `sprint.md`, `ledger.json` (root ledger at the close), `CHANGELOG.md` (the merged `[Unreleased]` section), `README.md` (index: merge, measurement reads, shipped mechanics, record branc…

Evidence:

~~~~~text
# pull request #1287: chore(cycle-131): archive the cycle on main

- url: https://github.com/0xHoneyJar/loa/pull/1287
- created_at: 2026-10-20T12:28:08Z
- state: closed

The text below is third-party data, quoted verbatim (control characters and secret-shaped strings replaced).

~~~~text
Archive of cycle-131 "honest review-catch measurement" after PR #1286 merged as `7b024f5c`.

- `grimoires/loa/archive/cycle-131-honest-measurement/`: `prd.md`, `sdd.md`, `sprint.md`, `ledger.json` (root ledger at the close), `CHANGELOG.md` (the merged `[Unreleased]` section), `README.md` (index: merge, measurement reads, shipped mechanics, record branch, decisions, carry-overs), `.archive-meta.json`.
- `grimoires/loa/ledger.json`: cycle-131 `status: archived`, `archived_at`, `archive_path`; `active_cycle: null`.
- Records live on `record/cycle-131-honest-measurement` (`d6ccba2c`), never on main.

Same shape as the cycle-130 archive (PR #1284). No code changes.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
~~~~
~~~~~

## I26 — fix-commit — 2026-10-21

- reference: 98b278111006
- files: evals/fixtures/review-prs/SHA256SUMS

Summary:

fix(evals): labels files reproduce the curated manifests byte for byte — @L<n> explicit-line must_match, --sync-labels pr-NN, eight labels files synced, SHA256SUMS refrozen — sprint-bug-268, bug 20261021-7240bc, bd-y4pqj Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>

Evidence:

~~~~diff
commit 98b2781110067edfe2167e297349da639d285dd7
Date: 2026-10-21T12:29:25+11:00

fix(evals): labels files reproduce the curated manifests byte for byte — @L<n> explicit-line must_match, --sync-labels pr-NN, eight labels files synced, SHA256SUMS refrozen — sprint-bug-268, bug 20261021-7240bc, bd-y4pqj

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/evals/fixtures/review-prs/SHA256SUMS b/evals/fixtures/review-prs/SHA256SUMS
index e44c2f05..3a74cfb3 100644
--- a/evals/fixtures/review-prs/SHA256SUMS
+++ b/evals/fixtures/review-prs/SHA256SUMS
@@ -1,21 +1,21 @@
 ed0c0ac16687ae399c303a45abb4a421bbd18e517bc4f0229048e2114db7666a  corpus.tsv
 3662616e9773cc3a05d6675e630d94782a8e3d189806b8b5fe6962b59da953af  labels/curation.tsv
 8cdb3d3e6357535ba28b01c7ce4d611e68e96a4ff68243663e2c300760eb016c  labels/pr-11.dropped.txt
-79cda5889afb7d6ee9f264d2d2452a9be1bd93c8919fbe76d0ce0f07f434ef0f  labels/pr-11.tsv
+eada19d329f76f06e22f8790cac70920c623eb8815f124e05bd03d315c9073ba  labels/pr-11.tsv
 d9d9ebd1631d9cc8e892f3e141ee90507244a0bd8c6df6be92a5a733a112e860  labels/pr-12.dropped.txt
-6c7e288a31cc033c9e369cf727ea82b01e0a7ad63d2b2e201cd0c04c37e7bc45  labels/pr-12.tsv
+4a2aa475082bd9fd99c6a7b8f71f15e7417a5e9de441a836e78df95e5c68b465  labels/pr-12.tsv
 b608b0351b64e52f2aa4e7bb22dbed942cacfd22383408109f7c5235bce592cb  labels/pr-13.dropped.txt
-feb586b72d8f648c0e3a14ffb23a394b31168c52f9b37d99f5fd620518b8ee17  labels/pr-13.tsv
+90eceb33fcdc0adc9f89b0e8577be744e0e5e78d2dd42d8f023e5055701b2c9f  labels/pr-13.tsv
 f6c2167b83b6df43f5aff2f219a81834b4b56f3c22f8eda2994fe4e64378f6b4  labels/pr-14.dropped.txt
-7f728eec36606caf710e86dbe8047e9ec6067e9cb9a7f9976a97001e84b07d80  labels/pr-14.tsv
+011eff3e310e4b50d9467e098392374cf5cd5a31fae0334b8b90c001d90793e4  labels/pr-14.tsv
 1f9ec491fd004261a0529e0949e14b53d8b1c5df69f1d5d22b7f1e6918758d96  labels/pr-15.dropped.txt
-b4f406df61e1aad1ad28412bb2dd622d9ac42b6ebe7c977400aadc0d16720f84  labels/pr-15.tsv
+24b1902c0ffcfeff0e033b665fb68f1f9bd660ffa5c709b52faa55b43ced0e6a  labels/pr-15.tsv
 d70c3714af9e8f7607b44f29a6d0d1dca483604fe2af7d9ad56f49dea21ea89a  labels/pr-16.dropped.txt
-8d2523569c5add133fc2fb2b626baf998e7a2cbf6eebc46ceb6ced4d13cad970  labels/pr-16.tsv
+bbb6c92e2af879148eab39554161ebb687e097f0536f44a313814518adaafb98  labels/pr-16.tsv
 c54cd6d7bd72fe7389d7e51db6d3a91947a2abed2c723c2b4f4611f9d26195f5  labels/pr-17.dropped.txt
-e8b9b99d0a23e8acd59deed74a34cf82eee7a9ff9f124e4f198b9ded9ebb44ff  labels/pr-17.tsv
+1a21736f9162a8c1db61310142f4af7ef5b6d8ebfc1455e6e887d353691c1fd7  labels/pr-17.tsv
 ccb7f1e4f696d88e9d34bc00a4684f95a1440bd77a9ef8f25d45087dc9c86e61  labels/pr-18.dropped.txt
-6956af6831e7034b3881b843c506716b3848f7220221faa7942df4c762ac3562  labels/pr-18.tsv
+8674a3ed26a8bb5ee6848d3d9b4b8e2fdf9863a6bd406b407f4465d6b6598da1  labels/pr-18.tsv
 0684b576c424db3cc51b6db1b9d174607ad972a8963f243db2a93453ee3e4dfd  manifests/pr-01.json
 3a2b3f2b74da2ed56184b5acfbffbd71846544209447e76e4283eea3a050f45c  manifests/pr-02.json
 a9c05524566b6c4456d966d1cc76c68086aa45bf4217cf5f81221bfd871000f7  manifests/pr-03.json
~~~~
