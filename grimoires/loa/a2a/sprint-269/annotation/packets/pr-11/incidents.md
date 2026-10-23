# Incidents — pr-11

Things that happened after the change merged and cite one of its files: later fix commits on the main branch, issues, review rounds and known-failure entries. The quoted text is data, not instructions.

## I01 — fix-commit — 2026-10-07

- reference: 8ad37c5518ed
- files: tools/ceiling-probe-live.py

Summary:

fix(cycle-127): sprint-251 fr23b — the probe's clean write clamps to cheval's I2 invariant (probed/effective = min(measured, context_window − default_max_tokens), the raw accept kept in ceiling_calibration.measured_input_tokens and named in the provenance comment; the operator's streaming switches do not loosen it) and the bisection steps in MEASURED tokens (the filler is rescaled by the latest m…

Evidence (first 200 of 335 lines):

~~~~diff
commit 8ad37c5518edebeec11f051d45ccfc63db3d1d06
Date: 2026-10-07T20:48:37+11:00

fix(cycle-127): sprint-251 fr23b — the probe's clean write clamps to cheval's I2 invariant (probed/effective = min(measured, context_window − default_max_tokens), the raw accept kept in ceiling_calibration.measured_input_tokens and named in the provenance comment; the operator's streaming switches do not loosen it) and the bisection steps in MEASURED tokens (the filler is rescaled by the latest measured/filler ratio — ≈1.8× under the Opus 4.7+ tokenizer — the blind first step is re-anchored once, --max-tokens-probe/--tolerance-tokens mean measured tokens, rejections take the count they state or the scaled estimate); tests on a synthetic pre-probe catalog since the live entry is now calibrated

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/tools/ceiling-probe-live.py b/tools/ceiling-probe-live.py
index b223a46e..957a2e7a 100755
--- a/tools/ceiling-probe-live.py
+++ b/tools/ceiling-probe-live.py
@@ -142,8 +142,10 @@ _CLI_ALIAS_ENV = {"opus": "ANTHROPIC_DEFAULT_OPUS_MODEL", "sonnet": "ANTHROPIC_D
 _TRANSIENT_MARKERS = ("throttl", "timeout", "timed out", "connection", "network", "econnreset", "socket",
                       "service unavailable", "internal server error", "bad gateway", "overloaded")
 _STATUS_5XX = __import__("re").compile(r"\b5\d\d\b")
-_PROVIDER_ORIGIN = __import__("re").compile(r"api error|api_error_status|\b4\d\d\b|invalid_request_error|validationexception",
-                                            __import__("re").I)
+# Explicit provider markers only: a bare 4xx pattern matched the CLI's own token
+# counts ("Prompt is too long: 403,000 tokens > …") as provider-origin.
+_PROVIDER_ORIGIN = __import__("re").compile(r"api error|api_status=|api_error_status|invalid_request_error|"
+                                            r"validationexception|\b(?:http|status)[ :]+4\d\d\b", __import__("re").I)
 
 
 def _adapters():
@@ -250,7 +252,8 @@ def _classify(rc: int, stdout: str, stderr: str, needle: str) -> dict:
     diag = (diag or stdout.strip() or f"exit code {rc}, no diagnostic")[:300]
     if ceiling.is_context_limit_message(diag):
         origin = "provider" if (api_status or _PROVIDER_ORIGIN.search(diag)) else "cli_local"
-        return {**base, "kind": "size", "failure_class": "context_limit", "size_origin": origin, "detail": diag}
+        return {**base, "kind": "size", "failure_class": "context_limit", "size_origin": origin, "detail": diag,
+                "rejected_input_tokens": ceiling.parse_context_limit(diag).get("input_tokens")}
     if ceiling.is_token_limit_message(diag):
         # a token-budget 429: retried as transient; persisting at this size it is a size rejection
         return {**base, "kind": "transient", "token_limit": True, "detail": diag}
@@ -356,15 +359,56 @@ def _write_catalog_file(path: str, model: str, record: dict, tier: str, itpm: in
     os.replace(tmp, path)
 
 
+def _catalog_default_output(max_output) -> int:
+    """The default output budget the catalog invariant is checked against:
+    cheval's own default_max_tokens (providers/base.py — the rule
+    test_anthropic_catalog_floor._default_max_tokens mirrors) with the
+    streaming/legacy switches cleared, so an operator running the probe with
+    streaming disabled does not loosen the bound (the env is restored)."""
+    _adapters()
+    from loa_cheval.providers.base import default_max_tokens
+    saved = {k: os.environ.pop(k) for k in ("LOA_CHEVAL_DISABLE_STREAMING", "LOA_CHEVAL_LEGACY_WIRE") if k in os.environ}
+    try:
+        return default_max_tokens(provider="anthropic", model_max_output=max_output)
+    finally:
+        os.environ.update(saved)
+
+
+def i2_clamped(text: str, model: str, measured: int) -> tuple[int, int, int]:
+    """(written, context_window, default_output): the bound a probe may write,
+    min(measured, context_window − default_max_tokens(entry)) — I2, the
+    catalog invariant `effective_input_ceiling + default max_tokens ≤
+    context_window` (cycle-127 fr23b; the live probe measured 972,887 on a 1M
+    window). ValueError when the entry has no context_window."""
+    lines = text.split("\n")
+    start = next((i for i, l in enumerate(lines) if l.rstrip() == f"      {model}:"), None)
+    if start is None:
+        raise ValueError(f"{model}: no `      {model}:` block in the catalog")
+    fields: dict = {}
+    for l in lines[start + 1:]:
+        if l.strip() and _indent(l) <= 6:
+            break
+        if _indent(l) == 8 and ":" in l and not l.strip().startswith("#"):
+            k, v = l.strip().split(":", 1)
+            fields[k] = v.split("#", 1)[0].strip()
+    cw = fields.get("context_window", "")
+    if not cw.isdigit() or int(cw) <= 0:
+        raise ValueError(f"{model}: no positive context_window in the entry — cannot apply the I2 clamp")
+    mo = fields.get("max_output_tokens", "")
+    default_out = _catalog_default_output(int(mo) if mo.isdigit() else None)
+    return min(int(measured), int(cw) - default_out), int(cw), default_out
+
+
 def write_catalog_operator_set(text: str, model: str, *, ceiling: int, calibrated_at: str, cli_model: str,
                                host_route: str, cli_version: str | None = None,
                                transport: str = "claude-headless") -> str:
     """cycle-127 FR-3.2 (SDD D-3.2, D-3.8): fold a CLI-transport bound into the
     catalog TEXT as `operator_set` — `probed_ceiling` and
     `effective_input_ceiling` (a calibrated entry is bounded by the latter,
-    routing/ceiling.input_bound) = `ceiling`, the measured accepted size, raw
-    (no margin, as the api transport; a value below the old bound is written,
-    never max()-ed); `ceiling_calibration {source, method: probed_headless,
+    routing/ceiling.input_bound) = min(`ceiling` — the measured accepted size,
+    no margin, as the api transport — , context_window − default max_tokens)
+    (the I2 clamp, i2_clamped; a value below the old bound is written, never
+    max()-ed); `measured_input_tokens` keeps the raw measurement; `ceiling_calibration {source, method: probed_headless,
     transport, cli_version, cli_model, measured_input_tokens, calibrated_at,
     sample_size: null, stale_after_days (kept, else 90), reprobe_trigger}`;
     the entry's `loa:shortcut` ceiling comment becomes one provenance comment.
@@ -394,8 +438,10 @@ def write_catalog_operator_set(text: str, model: str, *, ceiling: int, calibrate
     route = "Bedrock" if "bedrock" in host_route.lower() else host_route
     trigger = (f"API-transport probe (tools/ceiling-probe-live.py --transport api) from a host with "
                f"ANTHROPIC_API_KEY; this bound was measured through claude-headless on {route} ({cli_model}) on {day}")
-    _set_scalar(_find("effective_input_ceiling:", 8), "effective_input_ceiling", str(ceiling))
-    _set_scalar(_find("probed_ceiling:", 8), "probed_ceiling", str(ceiling))
+    measured = ceiling
+    written, cw, default_out = i2_clamped(text, model, measured)
+    _set_scalar(_find("effective_input_ceiling:", 8), "effective_input_ceiling", str(written))
+    _set_scalar(_find("probed_ceiling:", 8), "probed_ceiling", str(written))
     h = _find("ceiling_calibration:", 8)
     j = h + 1
     while j < len(block) and (block[j].strip() == "" or _indent(block[j]) > 8):
@@ -411,13 +457,15 @@ def write_catalog_operator_set(text: str, model: str, *, ceiling: int, calibrate
                f"          stale_after_days: {stale}", f"          reprobe_trigger: {json.dumps(trigger)}",
                "          method: probed_headless", f"          transport: {transport}",
                f"          cli_version: {json.dumps(cli_version) if cli_version else 'null'}",
-               f"          cli_model: {json.dumps(cli_model)}", f"          measured_input_tokens: {ceiling}"]
+               f"          cli_model: {json.dumps(cli_model)}", f"          measured_input_tokens: {measured}"]
     block[h:j] = new_cal
     # the shortcut marker: a `# loa:shortcut:` comment line plus its comment continuation lines
     k = next((i for i, l in enumerate(block) if _indent(l) == 8 and l.strip().startswith("# loa:shortcut:")
               and "ceiling-probe-live" in " ".join(block[i:i + 3])), None)
+    clamp_note = (f"; written clamped to {written} (I2: context_window {cw} − default max_tokens {default_out}) "
+                  f"from the measured {measured}") if written < measured else ""
     provenance = (f"        # cycle-127 FR-3: bound measured {day} by tools/ceiling-probe-live.py --transport "
-                  f"claude-headless ({route}, {cli_model}); see ceiling_calibration.reprobe_trigger.")
+                  f"claude-headless ({route}, {cli_model}){clamp_note}; see ceiling_calibration.reprobe_trigger.")
     old_prov = next((i for i, l in enumerate(block) if l.startswith("        # cycle-127 FR-3: bound measured ")), None)
     if k is not None:
         e = k + 1
@@ -564,15 +612,15 @@ def _outcome_reasons(samples: list[dict], *, stop: str | None, largest_ok: int,
         reasons.append("an attempt failed for a non-size reason (other)")
     if stop == "unverified" or any(s.get("kind") == "unverified" for s in samples):
         reasons.append("a completed response did not echo the needle (unverified)")
-    oks = [s["tokens"] for s in samples if s.get("kind") == "ok"]
-    fails = [s["tokens"] for s in samples if s.get("kind") == "size"]
+    oks = [s.get("size_measured", s["tokens"]) for s in samples if s.get("kind") == "ok"]
+    fails = [s.get("size_measured", s["tokens"]) for s in samples if s.get("kind") == "size"]
     if oks and fails and max(oks) > min(fails):
         reasons.append("inconsistent: an accept above a size rejection")
     if reasons:
         return reasons
     if largest_ok <= 0:
         reasons.append("no accepted size in the probed range")
-    elif smallest_fail is None:
+    elif smallest_fail is None or (largest_ok >= hi - tol and smallest_fail - largest_ok > tol):
         reasons.append(f"no size rejection up to {hi} tokens — the bound is not bracketed")
     elif smallest_fail - largest_ok > tol:
         reasons.append("the accept/reject bracket is wider than --tolerance-tokens")
@@ -604,18 +652,42 @@ def _main_cli(args) -> int:
           file=sys.stderr)
     cli_version = _cli_version(cli_bin)
 
+    # Sizes are MEASURED tokens (the CLI's usage, or the count a rejection states):
+    # --max-tokens-probe / --min-tokens-probe / --tolerance-tokens mean measured
+    # tokens, and the filler sent for a target is target / ratio, ratio being the
+    # latest measured/filler (1.0 until a step measures something — the Opus 4.7+
+    # tokenizer counts this filler ≈1.8× heavier than its 10-tokens-per-sentence).
     spent_micro = 0
     samples: list[dict] = []
-    largest_ok, largest_ok_measured, smallest_fail = 0, None, None
     stop = None  # "budget" | "other" | "unverified"
+    ratio: float | None = None
 
-    def step(tokens: int) -> str:
-        """Probe one size with up to _ATTEMPTS for transient classes. Returns the final kind."""
-        nonlocal spent_micro, largest_ok, largest_ok_measured, smallest_fail
-        sample = {"tokens": tokens, "attempts": 0, "ok": False, "verified": False}
+    def _m(sample: dict) -> int | None:
+        return sample.get("measured_input_tokens") if sample.get("kind") == "ok" else sample.get("rejected_input_tokens")
+
+    def _size(sample: dict) -> tuple[int, str]:
+        m = _m(sample)
+        return (m, "usage" if sample.get("kind") == "ok" else "parsed") if m else \
+            (int(sample["tokens"] * (ratio or 1.0)), "scaled")
+
+    def current_ok() -> int | None:
+        vals = [_size(x)[0] for x in samples if x.get("kind") == "ok"]
+        return max(vals) if vals else None
+
+    def current_fail() -> tuple[int | None, str | None]:
+        vals = [_size(x) for x in samples if x.get("kind") == "size"]
+        return min(vals) if vals else (None, None)
+
+    def step(target: int) -> str:
+        """Probe one MEASURED target with up to _ATTEMPTS for transient classes. Returns the final kind."""
+        nonlocal spent_micro, ratio
+        tokens = max(1, int(target / (ratio or 1.0)))
+        sample = {"tokens": tokens, "target_measured": target, "ratio_at_send": ratio, "attempts": 0,
+                  "ok": False, "verified": False}
         samples.append(sample)
+        est_measured = int(tokens * (ratio or 1.0))
         for attempt in range(1, _ATTEMPTS + 1):
-            if spent_micro + tokens * price_in // 1_000_000 > budget_micro:
+            if spent_micro + est_measured * price_in // 1_000_000 > budget_micro:
                 if attempt == 1:
                     samples.pop()          # a step never attempted is not a sample
                     return "budget"
@@ -625,19 +697,19 @@ def _main_cli(args) -> int:
                 _SLEEP(_BACKOFF_S[min(attempt - 2, len(_BACKOFF_S) - 1)])
             needle = secrets.token_hex(6)
             prompt = _FILLER * (tokens // 10) + f"\n\nReply with exactly this code and nothing else: {needle}"
-            print(f"ceiling-probe-live: {tokens} tokens (attempt {attempt}) via {os.path.basename(cli_bin)} ...",
-                  file=sys.stderr)
~~~~

## I02 — fix-commit — 2026-10-07

- reference: 059e26be76ab
- files: .claude/adapters/cheval.py,.claude/adapters/loa_cheval/providers/anthropic_adapter.py,.claude/adapters/loa_cheval/providers/base.py,.claude/adapters/loa_cheval/routing/ceiling.py,.claude/adapters/loa_cheval/types.py,.claude/adapters/tests/test_anthropic_catalog_floor.py,.claude/defaults/model-config.yaml,.claude/scripts/flatline-orchestrator.sh,.claude/scripts/loa-status.sh,.claude/skills/bridgebuilder-review/dist/.build-manifest.json,.claude/skills/bridgebuilder-review/dist/config.d.ts.map,.claude/skills/bridgebuilder-review/dist/config.js,.claude/skills/bridgebuilder-review/dist/config.js.map,.claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.d.ts.map,.claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.js,.claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.js.map,.claude/skills/bridgebuilder-review/dist/core/truncation.generated.js,.claude/skills/bridgebuilder-review/dist/core/truncation.generated.js.map,.claude/skills/bridgebuilder-review/resources/config.ts,.claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts,.claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts,.claude/skills/bridgebuilder-review/scripts/gen-bb-registry.ts,tests/unit/loa-status-providers.bats,tools/ceiling-probe-live.py

Summary:

fix(cycle-127): sprint-251 review dissent round r251-1 — cheval's chain walk plans around a gated agy hop (models_not_planned, reason opt_in_required, never a breaker count; a direct --model gemini-headless still refuses INVALID_CONFIG) and one routing predicate decides what the agy route is (.claude/scripts/lib/agy-gate-lib.sh + loader.routes_to_agy: the gemini-headless hop by name, or a Google…

Evidence (first 200 of 2141 lines):

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

## I03 — fix-commit — 2026-10-07

- reference: d12bdfabcec0
- files: .claude/adapters/cheval.py,.claude/adapters/tests/test_anthropic_catalog_floor.py,.claude/skills/bridgebuilder-review/dist/.build-manifest.json,.claude/skills/bridgebuilder-review/dist/config.d.ts.map,.claude/skills/bridgebuilder-review/dist/config.js,.claude/skills/bridgebuilder-review/dist/config.js.map,.claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.d.ts.map,.claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.js,.claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.js.map,.claude/skills/bridgebuilder-review/resources/config.ts,.claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts,.claude/skills/bridgebuilder-review/scripts/gen-bb-registry.ts,tools/ceiling-probe-live.py

Summary:

fix(cycle-127): sprint-251 review dissent round r251-2 — one strict opt-in rule on both readers (only the YAML scalar whose source text is exactly `true`; bash and Python had split on yes/on/True), an agy-alone refusal lands in models_failed only (INVALID_CONFIG / opt_in_required; models_not_planned is for hops dropped before the walk; voices_dropped names the reason), run-preflight P3 judges an…

Evidence (first 200 of 563 lines):

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
diff --git a/.claude/skills/bridgebuilder-review/dist/config.d.ts.map b/.claude/skills/bridgebuilder-review/dist/config.d.ts.map
index fb1b1ec8..cd5832d7 100644
--- a/.claude/skills/bridgebuilder-review/dist/config.d.ts.map
+++ b/.claude/skills/bridgebuilder-review/dist/config.d.ts.map
@@ -1 +1 @@
-{"version":3,"file":"config.d.ts","sourceRoot":"","sources":["../resources/config.ts"],"names":[],"mappings":"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"}
\ No newline at end of file
+{"version":3,"file":"config.d.ts","sourceRoot":"","sources":["../resources/config.ts"],"names":[],"mappings":"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"}
\ No newline at end of file
diff --git a/.claude/skills/bridgebuilder-review/dist/config.js b/.claude/skills/bridgebuilder-review/dist/config.js
index 9ee06f75..7dc3ce5c 100644
--- a/.claude/skills/bridgebuilder-review/dist/config.js
+++ b/.claude/skills/bridgebuilder-review/dist/config.js
@@ -138,13 +138,16 @@ export function readAgyGate(configPath) {
     if (existsSync(configPath)) {
         try {
             const out = execFileSync("yq", ["eval", "-o=json", "-I=0",
-                '{"opt": (.hounfour.headless.agy_opt_in | (tag == "!!bool" and . == true)), "tag": (.hounfour.headless.agy_opt_in | tag), "mode": (.hounfour.headless.mode // "")}',
+                '{"opt": (.hounfour.headless.agy_opt_in | (tag == "!!bool" and . == true)), "canon": (.hounfour.headless.agy_opt_in | (tag == "!!bool" and (. == true or . == false))), "tag": (.hounfour.headless.agy_opt_in | tag), "mode": (.hounfour.headless.mode // "")}',
                 configPath], { encoding: "utf8", timeout: 5000, stdio: ["ignore", "pipe", "pipe"] });
             const parsed = JSON.parse(out);
             optIn = parsed.opt === true;
             mode = typeof parsed.mode === "string" ? parsed.mode : "";
             if (typeof parsed.tag === "string" && parsed.tag !== "!!null" && parsed.tag !== "!!bool") {
-                typeWarning = `hounfour.headless.agy_opt_in is present but not a YAML boolean (${parsed.tag}) — expected true or false; the agy route stays off`;
+                typeWarning = `hounfour.headless.agy_opt_in is present but not a YAML boolean (${parsed.tag}) — only \`agy_opt_in: true\` opts in (expected true or false); the agy route stays off`;
+            }
+            else if (parsed.tag === "!!bool" && parsed.canon !== true) {
+                typeWarning = "hounfour.headless.agy_opt_in is a boolean spelled other than true/false — only `agy_opt_in: true` opts in (the lowercase scalar); the agy route stays off";
             }
         }
         catch (err) {
@@ -178,7 +181,10 @@ export function validateApiKeys(config, gate) {
     const missing = [];
     const notPlanned = [];
     for (const model of config.models) {
-        if (!gate.optIn && isAgyRouted(model.provider, model.model_id, gate.mode)) {
+        // (r251-2 K7b: an unreadable config fails closed for EVERY google voice — its mode is unknown, so is its route: cheval,
+        // reading the same file with PyYAML, might route it to agy and refuse; planned-as-HTTP would mis-count a failed voice)
+        const gated = gate.readError !== undefined ? model.provider === "google" : isAgyRouted(model.provider, model.model_id, gate.mode);
+        if (!gate.optIn && gated) {
             notPlanned.push({ provider: model.provider, modelId: model.model_id, reason: "opt_in_required" });
             continue;
         }
@@ -198,6 +204,23 @@ export function validateApiKeys(config, gate) {
     }
     return { valid, missing, notPlanned };
 }
+/**
~~~~

## I04 — fix-commit — 2026-10-07

- reference: 58f871959c89
- files: .claude/adapters/cheval.py,.claude/adapters/loa_cheval/routing/ceiling.py,.claude/adapters/tests/test_anthropic_catalog_floor.py,tests/unit/loa-status-providers.bats,tools/ceiling-probe-live.py

Summary:

fix(cycle-127): sprint-251 review round r251-3 — the Fable review's items: one shared is_throttle_message() in routing/ceiling.py (the probe's throttle rule + overloaded / too many requests / quota, a 429/529 in status position, never a digit inside a token count) consulted by the headless adapter before its context-limit mapping — Bedrock's "Too many tokens, please wait before trying again" is a…

Evidence (first 200 of 234 lines):

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
diff --git a/.claude/adapters/loa_cheval/routing/ceiling.py b/.claude/adapters/loa_cheval/routing/ceiling.py
index 946367d3..ac88a81e 100644
--- a/.claude/adapters/loa_cheval/routing/ceiling.py
+++ b/.claude/adapters/loa_cheval/routing/ceiling.py
@@ -216,9 +216,43 @@ _CONTEXT_LIMIT_MARKERS = (
 
 
 def is_context_limit_message(message: str) -> bool:
-    """True when a provider error message is of the prompt-too-long class."""
-    low = (message or "").lower()
-    return any(marker in low for marker in _CONTEXT_LIMIT_MARKERS)
+    """True when a provider error message is of the prompt-too-long class
+    (a marker, or one of the size statements ``parse_context_limit`` reads —
+    r251-3: the CLI's bare "~N tokens (limit M)" carries no marker word)."""
+    text = message or ""
+    low = text.lower()
+    return any(marker in low for marker in _CONTEXT_LIMIT_MARKERS) or any(
+        rx.search(text) for rx in (_RE_INPUT_ONLY, _RE_INPUT_PLUS_OUTPUT, _RE_CLI_TOKENS_LIMIT))
+
+
+# cycle-127 r251-3 R1 (SDD D-3.12): ONE throttle rule for the headless adapter and
+# the ceiling probe. Bedrock's tokens-per-minute throttle reads "Too many tokens,
+# please wait before trying again" — it carries the context marker `too many
+# tokens`, so a throttle marker must win over a context marker or a transient
+# throttle becomes a terminal size verdict. A 429 / 529 counts only in status
+# position: never inside a token count ("1,429,000 tokens", "~1052900 tokens",
+# "1,429.5k") and never as a count itself ("~429 tokens"); a status followed by
+# punctuation ("API Error: 429. Too many tokens") is still a status.
+_THROTTLE_MARKERS = (
+    "throttl",            # ThrottlingException, "throttled"
+    "please wait",
+    "rate limit",
+    "rate_limit",         # Anthropic's error type rate_limit_error
+    "tokens per min",     # "input tokens per minute", "tokens per min (TPM)"
+    "overloaded",
+    "too many requests",
+    "quota",
+)
+_RE_THROTTLE_STATUS = re.compile(r"(?<![\d,.])(?:429|529)(?!\d|[,.]\d|\s*k?\s*tokens\b)", re.I)
+
+
+def is_throttle_message(message: Optional[str]) -> bool:
+    """True when a provider/CLI error message is of the throttle class (a rate,
+    token-per-minute, overload or quota limit) — retried and walked, never a size
+    verdict, even when the text also reads like a context limit."""
+    text = message or ""
+    low = text.lower()
+    return any(marker in low for marker in _THROTTLE_MARKERS) or bool(_RE_THROTTLE_STATUS.search(text))
 
 
 # A 429 whose message names a token budget (Anthropic: "... 30,000 input tokens
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

## I05 — fix-commit — 2026-10-07

- reference: cbfccab2e30e
- files: .claude/adapters/cheval.py,.claude/adapters/loa_cheval/routing/ceiling.py,.claude/scripts/flatline-orchestrator.sh,.claude/scripts/loa-status.sh,.claude/skills/bridgebuilder-review/dist/.build-manifest.json,.claude/skills/bridgebuilder-review/dist/config.d.ts.map,.claude/skills/bridgebuilder-review/dist/config.js,.claude/skills/bridgebuilder-review/dist/config.js.map,.claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.d.ts.map,.claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.js,.claude/skills/bridgebuilder-review/dist/core/multi-model-pipeline.js.map,.claude/skills/bridgebuilder-review/resources/config.ts,.claude/skills/bridgebuilder-review/resources/core/multi-model-pipeline.ts,tests/unit/loa-status-providers.bats,tools/ceiling-probe-live.py

Summary:

fix(cycle-127): sprint-251 audit round r251-4 — the audit dissent's verified items: Bridgebuilder's merge gate no longer fails open under a config read error (readError → mergeBlocked with the reason, strict mode throws; the quorum is never shrunk by unreadable config); cheval reads the agy opt-in from its own install root, never a cwd-ancestor config (a planted /tmp/.loa.config.yaml opted a host…

Evidence (first 200 of 1001 lines):

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
diff --git a/.claude/adapters/loa_cheval/routing/ceiling.py b/.claude/adapters/loa_cheval/routing/ceiling.py
index ac88a81e..2ebc7958 100644
--- a/.claude/adapters/loa_cheval/routing/ceiling.py
+++ b/.claude/adapters/loa_cheval/routing/ceiling.py
@@ -35,6 +35,7 @@ from __future__ import annotations
 import datetime as _dt
 import fcntl
 import json
+import logging
 import os
 import re
 import stat as _stat
@@ -42,6 +43,30 @@ import tempfile
 from dataclasses import dataclass, replace
 from typing import Any, Callable, Dict, List, Optional
 
+logger = logging.getLogger("loa_cheval.routing.ceiling")
+
+# r251-4 S7 (audit run-2 n38): an observation outside [floor × context_window, context_window] is not a provider verdict
+# this route can act on (a stray `observed_input_tokens: 1` row would wedge it) — ignored, said once per process.
+OBSERVED_PLAUSIBILITY_FLOOR = 0.1
+_IMPLAUSIBLE_OBSERVED_WARNED = False
+
+
+def _plausible_observed(observed: int, context_window: Optional[int]) -> bool:
+    """True unless ``context_window`` is known and ``observed`` lies outside [0.1 × window, window]."""
+    if not context_window:
+        return True
+    return OBSERVED_PLAUSIBILITY_FLOOR * context_window <= observed <= context_window
+
+
+def _warn_implausible_once(observed: int, context_window: int, where: str) -> None:
+    global _IMPLAUSIBLE_OBSERVED_WARNED
+    if _IMPLAUSIBLE_OBSERVED_WARNED:
+        return
+    _IMPLAUSIBLE_OBSERVED_WARNED = True
+    logger.warning("ignoring an implausible observed provider limit (%s): %d tokens is outside [%d, %d] "
+                   "(%.1f × context_window .. context_window) — check .run/ceiling-observed.json", where, observed,
+                   int(OBSERVED_PLAUSIBILITY_FLOOR * context_window), context_window, OBSERVED_PLAUSIBILITY_FLOOR)
+
 FLOOR_MAX_TOKENS = 4_096
 _TRUTHY = ("1", "true", "yes", "on")
 
@@ -161,6 +186,10 @@ def input_bound(
 
     # An observation tightens an uncalibrated bound, or a calibration measured
     # on a foreign transport (r251-1); a same-route calibration ignores it.
+    # (r251-4 S7: an implausible one — below 0.1 × the window or above it — is ignored, said once)
+    if observed is not None and _pos_int(observed) and not _plausible_observed(observed, cw):
+        _warn_implausible_once(observed, cw or 0, "input_bound")
+        observed = None
     if (not calibrated or foreign) and observed is not None and _pos_int(observed) and observed - 1 < value:
         value, basis = observed - 1, "observed"
 
@@ -200,6 +229,11 @@ _RE_INPUT_PLUS_OUTPUT = re.compile(
 # cycle-127 r251-1 C9: the headless CLI's own pre-flight rejection (Claude Code
 # 2.1.292): "the request is ~1065182 tokens (limit 1000000) but …".
 _RE_CLI_TOKENS_LIMIT = re.compile(r"~?(\d[\d,]*)\s+tokens\s*\(\s*limit:?\s*(\d[\d,]*)\s*\)", re.I)
+# r251-4 S6 (audit run-2 n6): the bare "N tokens (limit M)" above is for READING the numbers only — as a classifier it
+# matched any batch counter ("processed 12 tokens (limit 100)"). Without a marker word, only the CLI's own sentence
+# ("the request is ~N tokens (limit M)") classifies a message as a context limit.
+_RE_CLI_REQUEST_SENTENCE = re.compile(
+    r"\b(?:request|prompt)\s+is\s+~?\d[\d,]*\s+tokens\s*\(\s*limit:?\s*\d[\d,]*\s*\)", re.I)
 _CONTEXT_LIMIT_MARKERS = (
     "prompt is too long",
     "too many tokens",
@@ -218,11 +252,12 @@ _CONTEXT_LIMIT_MARKERS = (
 def is_context_limit_message(message: str) -> bool:
     """True when a provider error message is of the prompt-too-long class
     (a marker, or one of the size statements ``parse_context_limit`` reads —
-    r251-3: the CLI's bare "~N tokens (limit M)" carries no marker word)."""
+    r251-3: the CLI's "the request is ~N tokens (limit M)" carries no marker
+    word; r251-4 S6: that sentence, never a bare "N tokens (limit M)")."""
     text = message or ""
     low = text.lower()
~~~~

## I06 — fix-commit — 2026-10-07

- reference: c2ef75816c89
- files: .claude/adapters/loa_cheval/routing/ceiling.py,.claude/skills/bridgebuilder-review/dist/.build-manifest.json,.claude/skills/bridgebuilder-review/dist/config.d.ts.map,.claude/skills/bridgebuilder-review/dist/config.js,.claude/skills/bridgebuilder-review/dist/config.js.map,.claude/skills/bridgebuilder-review/resources/config.ts,tests/unit/loa-status-providers.bats

Summary:

fix(cycle-127): sprint-251 audit round r251-5 + sprint close — one permission rule across the three opt-in readers (MED-001): the bash lib and Bridgebuilder's readAgyGate now refuse, like cheval's loader, a .loa.config.yaml not owned by the current user or writable by its group or others (off, one WARN naming the file and the reason; group-writable is refused unconditionally — the private-group e…

Evidence (first 200 of 219 lines):

~~~~diff
commit c2ef75816c89c065be6d5cfc51b8c24de31713a0
Date: 2026-10-08T06:06:12+11:00

fix(cycle-127): sprint-251 audit round r251-5 + sprint close — one permission rule across the three opt-in readers (MED-001): the bash lib and Bridgebuilder's readAgyGate now refuse, like cheval's loader, a .loa.config.yaml not owned by the current user or writable by its group or others (off, one WARN naming the file and the reason; group-writable is refused unconditionally — the private-group exception is gone, LOW-001); static-auth markers take precedence over a throttle match that rests on "please wait" alone (LOW-003); the AGC-6 batch failure's root cause (LOW-004) — loa-status fed jq a non-JSON document from workflow-state.sh under concurrent test runs — fixed in the script with a regression case; conformance rows for world-/group-writable configs on every reader; CHANGELOG, migration addendum and SDD D-1.1/D-1.11 now document the install-root anchor, the trust check, the exact-tag/alias/merge-key rule, the probe writer's input validation and re-parse, and the merge block under a config read error (LOW-002). Sprint 251 closed: ledger status completed, run state COMPLETE, epic bd-um3f and tasks closed, sprint.md round sections r251-4/r251-5; the Fable review (round 2) and audit (round 1) both APPROVED with CONSISTENT verdict trailers; COMPLETED marker written by the auditor.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/.claude/adapters/loa_cheval/routing/ceiling.py b/.claude/adapters/loa_cheval/routing/ceiling.py
index 2ebc7958..d932c2ab 100644
--- a/.claude/adapters/loa_cheval/routing/ceiling.py
+++ b/.claude/adapters/loa_cheval/routing/ceiling.py
@@ -292,6 +292,17 @@ def is_throttle_message(message: Optional[str]) -> bool:
     return any(marker in low for marker in _THROTTLE_MARKERS) or bool(_RE_THROTTLE_STATUS.search(text))
 
 
+def is_throttle_beyond_wait(message: Optional[str]) -> bool:
+    """True when the throttle verdict rests on more than the bare `please wait` — a 429 / 529 in status position or a
+    named rate / token / overload / quota marker (review r251-5 U3, audit LOW-003). The headless adapter lets a static-auth
+    marker (`not logged in`, `/login`, `authentication`, `invalid api key`, `unauthorized`) outrank a throttle that rests
+    on `please wait` alone: an auth failure that also says "please wait" is not retried and walked as a throttle."""
+    text = message or ""
+    low = text.lower()
+    return (any(marker in low for marker in _THROTTLE_MARKERS if marker != "please wait")
+            or bool(_RE_THROTTLE_STATUS.search(text)))
+
+
 # A 429 whose message names a token budget (Anthropic: "... 30,000 input tokens
 # per minute"; OpenAI: "... on tokens per min (TPM)") or a context limit; a
 # requests-per-minute 429 names none of these (BB-003).
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
diff --git a/.claude/skills/bridgebuilder-review/dist/config.d.ts.map b/.claude/skills/bridgebuilder-review/dist/config.d.ts.map
index 15d27a96..b57b6dbe 100644
--- a/.claude/skills/bridgebuilder-review/dist/config.d.ts.map
+++ b/.claude/skills/bridgebuilder-review/dist/config.d.ts.map
@@ -1 +1 @@
-{"version":3,"file":"config.d.ts","sourceRoot":"","sources":["../resources/config.ts"],"names":[],"mappings":"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"}
\ No newline at end of file
+{"version":3,"file":"config.d.ts","sourceRoot":"","sources":["../resources/config.ts"],"names":[],"mappings":"AAKA,OAAO,EAAE,CAAC,EAAE,MAAM,QAAQ,CAAC;AAC3B,OAAO,KAAK,EAAE,mBAAmB,EAAE,gBAAgB,EAAE,MAAM,iBAAiB,CAAC;AAgB7E,eAAO,MAAM,sBAAsB;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;iBA4DjC,CAAC;AAEH;;;GAGG;AACH,wBAAgB,oBAAoB,IAAI,gBAAgB,CA2CvD;AAED,yEAAyE;AACzE,eAAO,MAAM,oBAAoB,EAAE,MAAM,CAAC,MAAM,EAAE,MAAM,CAIvD,CAAC;AAEF,qGAAqG;AAIrG,wBAAgB,iBAAiB,CAAC,OAAO,EAAE,MAAM,EAAE,QAAQ,CAAC,EAAE,MAAM,GAAG,OAAO,CAG7E;AAED,mIAAmI;AACnI,MAAM,WAAW,OAAO;IACtB,KAAK,EAAE,OAAO,CAAC;IACf,IAAI,EAAE,MAAM,CAAC;IACb,uHAAuH;IACvH,SAAS,CAAC,EAAE,MAAM,CAAC;IACnB;qGACiG;IACjG,WAAW,CAAC,EAAE,MAAM,CAAC;CACtB;AAED,oIAAoI;AACpI,wBAAgB,gBAAgB,CAAC,QAAQ,CAAC,EAAE,MAAM,GAAG,MAAM,CAE1D;AAED;;gCAEgC;AAChC,eAAO,MAAM,UAAU,8FAAwF,CAAC;AAEhH;;;;;;GAMG;AACH,wBAAgB,wBAAwB,CAAC,UAAU,EAAE,MAAM,GAAG,MAAM,GAAG,SAAS,CAa/E;AAED;;;;GAIG;AACH,wBAAgB,WAAW,CAAC,UAAU,EAAE,MAAM,GAAG,OAAO,CA8CvD;AAED;;;GAGG;AACH,wBAAgB,WAAW,CAAC,QAAQ,EAAE,MAAM,EAAE,OAAO,EAAE,MAAM,EAAE,IAAI,EAAE,MAAM,GAAG,OAAO,CAGpF;AAED;;;;GAIG;AACH,wBAAgB,eAAe,CAAC,MAAM,EAAE,gBAAgB,EAAE,IAAI,EAAE,OAAO,GAAG;IACxE,KAAK,EAAE,KAAK,CAAC;QAAE,QAAQ,EAAE,MAAM,CAAC;QAAC,OAAO,EAAE,MAAM,CAAA;KAAE,CAAC,CAAC;IACpD,OAAO,EAAE,KAAK,CAAC;QAAE,QAAQ,EAAE,MAAM,CAAC;QAAC,MAAM,EAAE,MAAM,CAAA;KAAE,CAAC,CAAC;IACrD,UAAU,EAAE,KAAK,CAAC;QAAE,QAAQ,EAAE,MAAM,CAAC;QAAC,OAAO,EAAE,MAAM,CAAC;QAAC,MAAM,EAAE,iBAAiB,CAAA;KAAE,CAAC,CAAC;CACrF,CA4BA;AAED;;;;GAIG;AACH,wBAAgB,mBAAmB,CAAC,IAAI,EAAE,OAAO,EAAE,SAAS,EAAE,UAAU,CAAC,OAAO,eAAe,CAAC,GAAG,MAAM,EAAE,CAU1G;AAyBD,MAAM,WAAW,OAAO;IACtB,MAAM,CAAC,EAAE,OAAO,CAAC;IACjB,KAAK,CAAC,EAAE,MAAM,EAAE,CAAC;IACjB,EAAE,CAAC,EAAE,MAAM,CAAC;IACZ,YAAY,CAAC,EAAE,OAAO,CAAC;IACvB,cAAc,CAAC,EAAE,MAAM,CAAC;IACxB,eAAe,CAAC,EAAE,MAAM,CAAC;IACzB,YAAY,CAAC,EAAE,MAAM,CAAC;IACtB,KAAK,CAAC,EAAE,MAAM,CAAC;IACf,OAAO,CAAC,EAAE,MAAM,CAAC;IACjB,OAAO,CAAC,EAAE,MAAM,EAAE,CAAC;IACnB,eAAe,CAAC,EAAE,OAAO,CAAC;IAC1B,QAAQ,CAAC,EAAE,MAAM,CAAC;IAClB,UAAU,CAAC,EAAE,UAAU,GAAG,aAAa,CAAC;CACzC;AAED,MAAM,WAAW,UAAU;IACzB,OAAO,CAAC,EAAE,OAAO,CAAC;IAClB,KAAK,CAAC,EAAE,MAAM,EAAE,CAAC;IACjB,KAAK,CAAC,EAAE,MAAM,CAAC;IACf,OAAO,CAAC,EAAE,MAAM,CAAC;IACjB,gBAAgB,CAAC,EAAE,MAAM,CAAC;IAC1B,cAAc,CAAC,EAAE,MAAM,CAAC;IACxB,gBAAgB,CAAC,EAAE,MAAM,CAAC;IAC1B,iBAAiB,CAAC,EAAE,MAAM,CAAC;IAC3B,UAAU,CAAC,EAAE,MAAM,EAAE,CAAC;IACtB,aAAa,CAAC,EAAE,MAAM,CAAC;IACvB,YAAY,CAAC,EAAE,MAAM,CAAC;IACtB,gBAAgB,CAAC,EAAE,MAAM,EAAE,CAAC;IAC5B,cAAc,CAAC,EAAE,SAAS,GAAG,QAAQ,CAAC;IACtC,mBAAmB,CAAC,EAAE,MAAM,CAAC;IAC7B,SAAS,CAAC,EAAE,OAAO,CAAC;IACpB,OAAO,CAAC,EAAE,MAAM,CAAC;IACjB,WAAW,CAAC,EAAE,UAAU,GAAG,aAAa,CAAC;IACzC,sBAAsB,CAAC,EAAE,MAAM,CAAC;IAChC,mBAAmB,CAAC,EAAE,OAAO,CAAC;CAC/B;AAED,MAAM,WAAW,OAAO;IACtB,mBAAmB,CAAC,EAAE,MAAM,CAAC;IAC7B,mBAAmB,CAAC,EAAE,MAAM,CAAC;IAC7B,qBAAqB,CAAC,EAAE,MAAM,CAAC;IAC/B,uBAAuB,CAAC,EAAE,MAAM,CAAC;IACjC,sBAAsB,CAAC,EAAE,MAAM,CAAC;IAChC,yBAAyB,CAAC,EAAE,MAAM,CAAC;CACpC;AAED;;GAEG;AACH,wBAAgB,YAAY,CAAC,IAAI,EAAE,MAAM,EAAE,GAAG,OAAO,CAyDpD;AA8CD;;;;GAIG;AACH,wBAAsB,cAAc,IAAI,OAAO,CAAC,UAAU,CAAC,CAsG1D;AAED;;;;;;;GAOG;AACH,wBAAgB,eAAe,CAAC,GAAG,EAAE,OAAO,EAAE,GAAG,EAAE,OAAO,GAAG,MAAM,GAAG,SAAS,CAa9E;AAiBD;;;GAGG;AACH,wBAAsB,aAAa,CACjC,OAAO,EAAE,OAAO,EAChB,GAAG,EAAE,OAAO,EACZ,UAAU,CAAC,EAAE,UAAU,GACtB,OAAO,CAAC;IAAE,MAAM,EAAE,mBAAmB,CAAC;IAAC,UAAU,EAAE,gBAAgB,CAAA;CAAE,CAAC,CA8JxE;AAED;;GAEG;AACH,wBAAgB,YAAY,CAC1B,MAAM,EAAE,mBAAmB,EAC3B,QAAQ,CAAC,EAAE,MAAM,GAChB,KAAK,CAAC;IAAE,KAAK,EAAE,MAAM,CAAC;IAAC,IAAI,EAAE,MAAM,CAAA;CAAE,CAAC,CAQxC;AAED,MAAM,MAAM,YAAY,GAAG,KAAK,GAAG,KAAK,GAAG,MAAM,GAAG,aAAa,GAAG,SAAS,CAAC;AAE9E,MAAM,WAAW,gBAAgB;IAC/B,KAAK,EAAE,YAAY,CAAC;IACpB,KAAK,EAAE,YAAY,CAAC;IACpB,MAAM,EAAE,YAAY,CAAC;IACrB,cAAc,EAAE,YAAY,CAAC;IAC7B,eAAe,EAAE,YAAY,CAAC;IAC9B,YAAY,EAAE,YAAY,CAAC;IAC3B,UAAU,EAAE,YAAY,CAAC;CAC1B;AAED;;;GAGG;AACH,wBAAgB,qBAAqB,CACnC,MAAM,EAAE,mBAAmB,EAC3B,UAAU,CAAC,EAAE,gBAAgB,GAC5B,MAAM,CA2BR"}
\ No newline at end of file
diff --git a/.claude/skills/bridgebuilder-review/dist/config.js b/.claude/skills/bridgebuilder-review/dist/config.js
index 25deff93..d80219d1 100644
--- a/.claude/skills/bridgebuilder-review/dist/config.js
+++ b/.claude/skills/bridgebuilder-review/dist/config.js
@@ -1,7 +1,7 @@
 import { execFile, execFileSync, execSync } from "node:child_process";
 import { promisify } from "node:util";
 import { readFile } from "node:fs/promises";
-import { existsSync } from "node:fs";
+import { existsSync, statSync } from "node:fs";
 import { join } from "node:path";
 import { z } from "zod/v4";
 import { GENERATED_MODEL_REGISTRY } from "./config.generated.js";
@@ -129,6 +129,31 @@ export function loaConfigPathFor(repoRoot) {
  * `_YQ_HAS` (r251-4 S3): every level a real mapping (`kind` is "alias" for an alias node) and the explicit key only (`has`
  * never sees a merge key's). */
 export const AGY_YQ_HAS = '.hounfour | (kind == "map" and (.headless | (kind == "map" and has("agy_opt_in"))))';
+/**
+ * Why the opt-in config is not the current user's alone to write, or undefined when it is (review r251-5 U1/U2, audit
+ * MED-001/LOW-001): ONE permission rule with cheval's `loader._config_untrusted_reason` and the bash lib's
+ * `_agy_config_untrusted` — owned by the current user and neither group- nor world-writable (group-writable refused
+ * unconditionally). `statSync` follows a symlink: the target decides, as in the other readers. A config that cannot be
+ * stat'ed is untrusted (fail closed). Where the platform has no uid (`process.getuid` absent), the owner half is skipped.
+ */
+export function agyConfigUntrustedReason(configPath) {
+    let st;
+    try {
+        st = statSync(configPath);
+    }
+    catch {
+        return `${configPath} could not be stat'ed (owner and mode unknown)`;
+    }
+    const me = typeof process.getuid === "function" ? process.getuid() : undefined;
+    if (me !== undefined && st.uid !== me)
+        return `${configPath} is not owned by the current user (uid ${st.uid}, euid ${me})`;
+    const mode = `mode ${(st.mode & 0o7777).toString(8).padStart(4, "0")}`;
+    if (st.mode & 0o002)
+        return `${configPath} is world-writable (${mode})`;
+    if (st.mode & 0o020)
+        return `${configPath} is group-writable (${mode})`;
+    return undefined;
+}
 /**
  * Read `hounfour.headless.agy_opt_in` (true only for a YAML boolean true) and `hounfour.headless.mode` from the Loa config
  * with one yq call. LOA_HEADLESS_MODE wins for the mode, as it does in cheval; nothing in the environment opts in. A missing
@@ -151,7 +176,15 @@ export function readAgyGate(configPath) {
             const alias = parsed.kind === "alias";
             optIn = present && !alias && parsed.opt === true;
             mode = typeof parsed.mode === "string" ? parsed.mode : "";
-            if (present && alias) {
+            // (r251-5 U1: a config others can write never opts in — one WARN naming the key and the reason; not a readError:
+            // the gate reads off, exactly as the bash and Python readers, rather than blocking the merge. Only a value that
+            // would opt in is judged, as there: a config that reads off anyway is not flagged)
+            const untrusted = optIn ? agyConfigUntrustedReason(configPath) : undefined;
+            if (untrusted !== undefined) {
+                optIn = false;
+                typeWarning = `hounfour.headless.agy_opt_in: ${untrusted} — a config others can write never opts in (own it and \`chmod go-w\` it); the agy route stays off`;
+            }
+            else if (present && alias) {
                 typeWarning = "hounfour.headless.agy_opt_in is present but not a YAML boolean (an alias) — only `agy_opt_in: true` opts in (expected true or false); the agy route stays off";
             }
             else if (present && typeof parsed.tag === "string" && parsed.tag !== "!!null" && parsed.tag !== "!!bool") {
diff --git a/.claude/skills/bridgebuilder-review/dist/config.js.map b/.claude/skills/bridgebuilder-review/dist/config.js.map
index cc22a6c1..d7251aa1 100644
--- a/.claude/skills/bridgebuilder-review/dist/config.js.map
+++ b/.claude/skills/bridgebuilder-review/dist/config.js.map
@@ -1 +1 @@
-{"version":3,"file":"config.js","sourceRoot":"","sources":["../resources/config.ts"],"names":[],"mappings":"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"}
\ No newline at end of file
+{"version":3,"file":"config.js","sourceRoot":"","sources":["../resources/config.ts"],"names":[],"mappings":"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"}
\ No newline at end of file
diff --git a/.claude/skills/bridgebuilder-review/resources/config.ts b/.claude/skills/bridgebuilder-review/resources/config.ts
index a649306b..a2877b5d 100644
--- a/.claude/skills/bridgebuilder-review/resources/config.ts
+++ b/.claude/skills/bridgebuilder-review/resources/config.ts
@@ -1,7 +1,7 @@
 import { execFile, execFileSync, execSync } from "node:child_process";
 import { promisify } from "node:util";
 import { readFile } from "node:fs/promises";
-import { existsSync } from "node:fs";
+import { existsSync, statSync } from "node:fs";
 import { join } from "node:path";
 import { z } from "zod/v4";
 import type { BridgebuilderConfig, MultiModelConfig } from "./core/types.js";
@@ -168,6 +168,28 @@ export function loaConfigPathFor(repoRoot?: string): string {
  * never sees a merge key's). */
 export const AGY_YQ_HAS = '.hounfour | (kind == "map" and (.headless | (kind == "map" and has("agy_opt_in"))))';
 
+/**
+ * Why the opt-in config is not the current user's alone to write, or undefined when it is (review r251-5 U1/U2, audit
+ * MED-001/LOW-001): ONE permission rule with cheval's `loader._config_untrusted_reason` and the bash lib's
+ * `_agy_config_untrusted` — owned by the current user and neither group- nor world-writable (group-writable refused
+ * unconditionally). `statSync` follows a symlink: the target decides, as in the other readers. A config that cannot be
+ * stat'ed is untrusted (fail closed). Where the platform has no uid (`process.getuid` absent), the owner half is skipped.
+ */
+export function agyConfigUntrustedReason(configPath: string): string | undefined {
+  let st: { uid: number; mode: number };
+  try {
+    st = statSync(configPath);
+  } catch {
+    return `${configPath} could not be stat'ed (owner and mode unknown)`;
+  }
+  const me = typeof process.getuid === "function" ? process.getuid() : undefined;
+  if (me !== undefined && st.uid !== me) return `${configPath} is not owned by the current user (uid ${st.uid}, euid ${me})`;
+  const mode = `mode ${(st.mode & 0o7777).toString(8).padStart(4, "0")}`;
+  if (st.mode & 0o002) return `${configPath} is world-writable (${mode})`;
+  if (st.mode & 0o020) return `${configPath} is group-writable (${mode})`;
+  return undefined;
+}
+
 /**
  * Read `hounfour.headless.agy_opt_in` (true only for a YAML boolean true) and `hounfour.headless.mode` from the Loa config
  * with one yq call. LOA_HEADLESS_MODE wins for the mode, as it does in cheval; nothing in the environment opts in. A missing
@@ -194,7 +216,14 @@ export function readAgyGate(configPath: string): AgyGate {
       const alias = parsed.kind === "alias";
       optIn = present && !alias && parsed.opt === true;
       mode = typeof parsed.mode === "string" ? parsed.mode : "";
-      if (present && alias) {
+      // (r251-5 U1: a config others can write never opts in — one WARN naming the key and the reason; not a readError:
+      // the gate reads off, exactly as the bash and Python readers, rather than blocking the merge. Only a value that
+      // would opt in is judged, as there: a config that reads off anyway is not flagged)
+      const untrusted = optIn ? agyConfigUntrustedReason(configPath) : undefined;
+      if (untrusted !== undefined) {
+        optIn = false;
+        typeWarning = `hounfour.headless.agy_opt_in: ${untrusted} — a config others can write never opts in (own it and \`chmod go-w\` it); the agy route stays off`;
+      } else if (present && alias) {
         typeWarning = "hounfour.headless.agy_opt_in is present but not a YAML boolean (an alias) — only `agy_opt_in: true` opts in (expected true or false); the agy route stays off";
       } else if (present && typeof parsed.tag === "string" && parsed.tag !== "!!null" && parsed.tag !== "!!bool") {
         typeWarning = `hounfour.headless.agy_opt_in is present but not a YAML boolean (${parsed.tag}) — only \`agy_opt_in: true\` opts in (expected true or false); the agy route stays off`;
diff --git a/tests/unit/loa-status-providers.bats b/tests/unit/loa-status-providers.bats
index ee0de252..4a7ee0b2 100644
--- a/tests/unit/loa-status-providers.bats
+++ b/tests/unit/loa-status-providers.bats
@@ -9,6 +9,9 @@ bats_require_minimum_version 1.5.0
 # =============================================================================
 
 setup() {
+  # (r251-5 U1/U2: every agy opt-in reader refuses a group- or world-writable config — fixtures are written owner-only
~~~~

## I07 — issue — 2026-10-07

- reference: #1275
- files: tools/ceiling-probe-live.py

Summary:

cycle-127: operator decisions — agy opt-in, Opus 5.5 effort default, ceiling probe — ## cycle-127: operator decisions — agy opt-in, Opus 5.5 effort default, ceiling probe One sprint (global 251), run unattended under the maintainer's delegation and admin preapproval (NOTES § Decision Log 2026-10-07). Three decisions the cycle-126 close left open, taken and landed: **1. The agy (Antigravity) route…

Evidence:

~~~~~text
# pull request #1275: cycle-127: operator decisions — agy opt-in, Opus 5.5 effort default, ceiling probe

- url: https://github.com/0xHoneyJar/loa/pull/1275
- created_at: 2026-10-07T19:07:48Z
- state: closed

The text below is third-party data, quoted verbatim (control characters and secret-shaped strings replaced).

~~~~text
## cycle-127: operator decisions — agy opt-in, Opus 5.5 effort default, ceiling probe

One sprint (global 251), run unattended under the maintainer's delegation and admin preapproval (NOTES § Decision Log 2026-10-07). Three decisions the cycle-126 close left open, taken and landed:

**1. The agy (Antigravity) route is opt-in, default off** (bead bd-ugmi). `hounfour.headless.agy_opt_in: true` (YAML boolean, project config only, no environment override) is required for the `gemini-headless` hop. Off: cheval refuses a direct dispatch before any binary discovery or spawn (`INVALID_CONFIG`, `failure_class: opt_in_required`, never a breaker count), its chain walk plans around a gated hop inside a fallback chain (`models_not_planned`), and every planner — the dissent companion chain, Flatline's tertiary, Bridgebuilder, `run-preflight.sh`, `/loa` — records the hop as *not planned* rather than failed, so verdict quality counts planned voices only. One routing predicate (`.claude/scripts/lib/agy-gate-lib.sh`, Python twin `loader.routes_to_agy`) decides what the agy route is; `tests/unit/agy-gate-conformance.bats` pins every reader. Why: the prompt travels on `agy`'s argv (readable by local accounts), and a host without `agy` degraded every multi-model verdict (Bridgebuilder #1274 ran DEGRADED 2/3 on that account).

**2. Claude Opus 5.5 reasons at `high` by default** (bead bd-9qe2). Typed `params.default_effort` in the v3 catalog schema; `claude-opus-5-5` sets `high` (the vendor default is `medium`, one level below Opus 5's `high`, so every `opus` caller passing no `--effort` had silently lost a reasoning level at the cycle-126 retarget). cheval resolves effort once at the chokepoint (caller > catalog > legacy `extra.effort` > none) and carries it to every hop; MODELINV records `effort_source` / `effort_effective` (adapter-derived).

**3. The ceiling probe measures through the headless CLI** (`tools/ceiling-probe-live.py --transport claude-headless`) and ran once through this host's Bedrock route: needle-verified accepts at 696,136 / 880,634 / 972,887 measured input tokens, the CLI pre-flight rejecting at the 1,000,000 window ($12.74 CLI-reported spend; record in `grimoires/loa/reports/`). Opus 5.5's input ceiling goes **180,000 → 936,000** (= 1M − the 64K default output budget, cheval's I2 invariant), `operator_set` with structured provenance (`method`, `transport`, `cli_version`, `cli_model`, `measured_input_tokens`, `probe_outcome: partial`, `sample_size: 5`). The review found and fixed a units gap: the bound is in provider-measured tokens while cheval's estimate under-counts the Opus 4.7+ tokenizer ≈1.4× — calibrated entries now ask the provider's free `count_tokens` from half the bound, Bridgebuilder's generated budget for a measured-unit calibration divides by 1.8 (916,000 → 508,000), and a calibration measured on a foreign transport may be tightened by a verified observation on the HTTP route.

### Verification
- adapters pytest 3039 passed / 6 skipped (279 subtests); bats suites (agy-gate-conformance, run-preflight, loa-status-providers, adversarial-review-companion, flatline-tertiary-agy-opt-in, model-config-v3-schema, cycle-124-anthropic-catalog, cycle-124-effort-flag, gen-bb-registry-codegen, agent-ergonomics-workflow-state) 0 failures; Bridgebuilder 819/820 (`persona.test.ts` = KF-036, pre-existing); `regen-model-artifacts --check` drift-free, dist fresh; lints clean.
- Review trail (all under the sanctioned gates, unattended): Flatline on PRD/SDD/sprint (KF-041: cross-scoring degraded to one scorer, integrated by judgment); two-voice cross-model review dissent (codex-headless gpt-5.5-pro + claude-headless on Bedrock) — run 1: 58 findings / 7 BLOCKING, run 2 on the delta: 76 / 10 — each triaged with two independent Opus 5.5 read-only verifiers (45 refuted with evidence, one upgraded to the units gap above) → fix rounds `059e26be`, `d12bdfab`; Fable 5.1 `/review-sprint` round 1 CHANGES_REQUIRED (1 HIGH: a throttle-vs-context-limit regression of our own, caught by executing the classifier on the real Bedrock strings) → `58f87195`, round 2 APPROVED; audit dissent over the full range (60 findings) and the delta (11), verified → `cbfccab2`; Fable 5.1 `/audit-sprint` APPROVED with one MEDIUM (the trust check on the opt-in config was Python-only) → `c2ef7581`. Every verdict trailer is CONSISTENT with its envelope. a2a record (gitignored): `record/cycle-127-a2a`.

### Follow-ups (beads)
- bd-c2rd — cheval input-estimator calibration against the Opus 4.7+ tokenizer (the 1.4–1.8× under-count; a count-backed or ratio-scaled estimate, a per-entry tokenizer ratio, a documented margin).
- bd-n6lk — the Bedrock HTTP adapter ignores `request.effort` (pre-existing; `bedrock_only` hosts drop `--effort` on the 4.x aliases).
- bd-y49y — the MODELINV payload schema's closed `capability_evaluation` omits every cycle-126 gate-outcome key (pre-existing drift, not enforced at emit).
- bd-rbkz — extract a `Bisection` object from the probe's 300-line `_main_cli` on its next touch.
- The API-transport re-probe of `claude-opus-5-5` stays operator-side (`ceiling_calibration.reprobe_trigger`); the agy stdin transport and a base-ref config read for PR review are noted on bd-ugmi.

Reviewer: @deep-name

🤖 Generated with [Claude Code](https://claude.com/claude-code)
~~~~
~~~~~

## I08 — fix-commit — 2026-10-07

- reference: 263a8d4c469b
- files: .claude/adapters/cheval.py,.claude/skills/bridgebuilder-review/dist/.build-manifest.json,.claude/skills/bridgebuilder-review/dist/config.d.ts.map,.claude/skills/bridgebuilder-review/dist/config.js,.claude/skills/bridgebuilder-review/dist/config.js.map,.claude/skills/bridgebuilder-review/resources/config.ts

Summary:

fix(cycle-127): sprint-251 Bridgebuilder round r251-6 — the pass on PR #1275 (two voices planned, the google voice not planned, verdict quality APPROVED 2/2): a correct user-private-group exception in all three opt-in readers (a 0664 config is trusted only when its gid is the owner's primary gid, the group is named like the user and has no other members — Ubuntu umask-002 checkouts opt in again,…

Evidence (first 200 of 517 lines):

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
diff --git a/.claude/skills/bridgebuilder-review/dist/config.d.ts.map b/.claude/skills/bridgebuilder-review/dist/config.d.ts.map
index b57b6dbe..a0543fe8 100644
--- a/.claude/skills/bridgebuilder-review/dist/config.d.ts.map
+++ b/.claude/skills/bridgebuilder-review/dist/config.d.ts.map
@@ -1 +1 @@
-{"version":3,"file":"config.d.ts","sourceRoot":"","sources":["../resources/config.ts"],"names":[],"mappings":"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"}
\ No newline at end of file
+{"version":3,"file":"config.d.ts","sourceRoot":"","sources":["../resources/config.ts"],"names":[],"mappings":"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"}
\ No newline at end of file
diff --git a/.claude/skills/bridgebuilder-review/dist/config.js b/.claude/skills/bridgebuilder-review/dist/config.js
index d80219d1..c1eaf277 100644
--- a/.claude/skills/bridgebuilder-review/dist/config.js
+++ b/.claude/skills/bridgebuilder-review/dist/config.js
@@ -1,7 +1,7 @@
 import { execFile, execFileSync, execSync } from "node:child_process";
 import { promisify } from "node:util";
 import { readFile } from "node:fs/promises";
-import { existsSync, statSync } from "node:fs";
+import { closeSync, existsSync, fstatSync, openSync, readFileSync, statSync } from "node:fs";
 import { join } from "node:path";
 import { z } from "zod/v4";
 import { GENERATED_MODEL_REGISTRY } from "./config.generated.js";
@@ -129,20 +129,80 @@ export function loaConfigPathFor(repoRoot) {
  * `_YQ_HAS` (r251-4 S3): every level a real mapping (`kind` is "alias" for an alias node) and the explicit key only (`has`
  * never sees a merge key's). */
 export const AGY_YQ_HAS = '.hounfour | (kind == "map" and (.headless | (kind == "map" and has("agy_opt_in"))))';
-/**
- * Why the opt-in config is not the current user's alone to write, or undefined when it is (review r251-5 U1/U2, audit
- * MED-001/LOW-001): ONE permission rule with cheval's `loader._config_untrusted_reason` and the bash lib's
- * `_agy_config_untrusted` — owned by the current user and neither group- nor world-writable (group-writable refused
- * unconditionally). `statSync` follows a symlink: the target decides, as in the other readers. A config that cannot be
- * stat'ed is untrusted (fail closed). Where the platform has no uid (`process.getuid` absent), the owner half is skipped.
- */
-export function agyConfigUntrustedReason(configPath) {
-    let st;
+/** One NSS lookup through `getent` (the bash lib's account source); undefined when getent is missing or cannot answer. */
+function getent(args) {
     try {
-        st = statSync(configPath);
+        return execFileSync("getent", args, { encoding: "utf8", timeout: 5000, stdio: ["ignore", "pipe", "ignore"] });
     }
     catch {
-        return `${configPath} could not be stat'ed (owner and mode unknown)`;
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
     }
     const me = typeof process.getuid === "function" ? process.getuid() : undefined;
     if (me !== undefined && st.uid !== me)
@@ -150,8 +210,11 @@ export function agyConfigUntrustedReason(configPath) {
     const mode = `mode ${(st.mode & 0o7777).toString(8).padStart(4, "0")}`;
     if (st.mode & 0o002)
         return `${configPath} is world-writable (${mode})`;
-    if (st.mode & 0o020)
-        return `${configPath} is group-writable (${mode})`;
+    if (st.mode & 0o020) {
+        const why = agyGroupNotPrivate(st.uid, st.gid, fd, configPath);
+        if (why !== undefined)
+            return `${configPath} is group-writable (${mode}) and ${why}`;
+    }
     return undefined;
~~~~

## I09 — issue — 2026-10-13

- reference: #1279
- files: tools/ceiling-probe-live.py

Summary:

feat(cycle-128): decision surfaces — interview rounds with fact/decision attribution, the decision ledger, /chart decision maps, spike tickets, glossaries, seams and red-before-green, operator-only commands — ## Summary cycle-128 "decision surfaces" turns the planning conversation into attributable, inspectable decisions. The interview asks in prerequisite-ordered rounds and separates facts (look…

Evidence:

~~~~~text
# pull request #1279: feat(cycle-128): decision surfaces — interview rounds with fact/decision attribution, the decision ledger, /chart decision maps, spike tickets, glossaries, seams and red-before-green, operator-only commands

- url: https://github.com/0xHoneyJar/loa/pull/1279
- created_at: 2026-10-13T08:01:48Z
- state: closed

The text below is third-party data, quoted verbatim (control characters and secret-shaped strings replaced).

~~~~text
## Summary

cycle-128 "decision surfaces" turns the planning conversation into attributable, inspectable decisions. The interview asks in prerequisite-ordered rounds and separates facts (looked up, never asked) from decisions (the operator's); every planning decision becomes a `DEC` row in a tracked, append-only ledger with who decided it; `/chart` maps an effort that spans more than one cycle as decision tickets on beads without building anything; questions that talking cannot settle become spike tickets on branches that are pushed, never merged and never opened as a PR; a framework glossary and a drift gate keep the vocabulary from rotting; sprint plans declare their seams under test and a red-before-green check proves a bug fix's test failed before the fix; and seven operator-only commands are out of the model's reach.

Three sprints (global 252, 253, 254), each through implement → review → audit with two-voice dissent at every gate (gpt-5.5-pro via codex-headless + claude-headless, consensus every run, 0 schema-rejected payloads). Review and audit each took two rounds per sprint; every round-1 finding is closed with a test in the following commit. Full release note: `CHANGELOG.md` `[Unreleased]` (with a Migration section). Maintainer brief and source analysis: `grimoires/loa/a2a/skills-review-2026-10/` (record branch).

## What is in it

- **FR-1 Interview rounds** (`interview.pacing: rounds`, the default for `thorough`): every question whose prerequisites are settled, in one numbered round with a recommended answer; `tools/check-round-independence.sh` scores a transcript's round blocks.
- **FR-2 Fact or decision**: the Backpressure Protocol splits questions into facts and decisions; unattended runs record each decision taken for the operator.
- **FR-3 Decision ledger**: `grimoires/loa/decisions.yaml` through its single writer `dec-write-lib.sh` (derived attribution, unattended writes always `proposed`), `validate-artifact.sh --type decisions`, the INDEX `## decisions` family, a default-off SessionStart surface, and `/decisions` (operator-only) as the only path to `confirm`.
- **FR-4 `/chart` decision maps**: a `map` epic of `question` beads plus a map doc with exactly four sections; `chart-ticket.sh` owns the write order and idempotency; `chart-guard.sh` refuses unattended contexts; the read-only `chart-researcher` agent; `chart-unblock-probe.sh` runs a probe under a scrubbed environment with a refs/config/hooks snapshot; question beads never enter the build path (`create-sprint-task.sh`, `get-ready-work.sh`, the sprint validator); `golden-path.sh` reports a `charting` phase.
- **FR-5 Spike tickets**: `spike/<slug>` branches, ICE spike rules, fence rule SP-1 (merge, rebase, pull, cherry-pick, reset, read-tree, update-ref, branch moves, push refspecs, FETCH_HEAD one-liners, alias definitions, `gh api` pulls), the D-5.9 clean-up unlock for a fully pushed, operator-decided spike, `validate-artifact.sh --type spike`.
- **FR-6 Glossaries**: `.claude/loa/GLOSSARY.md` (33 entries, mounted into every project) and the root `GLOSSARY.md`; `tools/check-glossary-terms.sh` with a CI gate and two controls; `validate-artifact.sh --type glossary`.
- **FR-7 Seams and red-before-green**: `### Seams Under Test` in every sprint block of plans dated from 2026-10-13; `red-test-check.sh` (listed runners only, `env -i`, red-green-red, fenced output, `.git` snapshot); the micro-sprint two-commit rule; `reviewing-code` cites the check.
- **FR-8 Operator-only commands**: `disable-model-invocation: true` on `/loa-eject`, `/toggle-gpt-review`, `/permission-audit`, `/loa-setup`, `/contribute`, `/run-halt`, `/decisions`, pinned by a lint and verified by one live harness run.

## Verification

- Final tree: 23 bats suites, 762/762 (the full cycle-128 set plus every Sprint 1–2 suite the validator or the fence touches); `check-prompt-budget` exit 0; `validate-skill-capabilities` 37/37; `agents-md-gen --check` 51 commands; `repo-map-gen --validate` exit 0; `check-no-swallowed-jq`, `check-no-raw-sha256sum` OK; `sync-fixtures --check` current; `check-glossary-terms.sh` PASS; PRD, SDD, sprint plan, both glossaries and the 122-row decision ledger validate.
- E2E (`grimoires/loa/a2a/sprint-254/e2e.md`, record branch): G-1…G-7 PASS; G-3 scored on a second rounds transcript; G-7 verified by a live `claude -p` run whose stream shows the hidden command refused by the Skill tool and the control running.
- Review and audit reports, dissent envelopes and COMPLETED markers for sprints 252–254: `grimoires/loa/a2a/sprint-25{2,3,4}/` (record branch `record/cycle-128-a2a`).

## Follow-ups (beads)

bd-g6k3 (operator-only convention), bd-48ni (`/contribute` secrets check scans the final diff only), bd-xtip (`/loa-eject` unpinned recovery script), bd-akas (per-agent Read/WebFetch limits for `chart-researcher` once the harness supports them).

## Decisions taken on your behalf

Every planning decision of this cycle is a `proposed` row in `grimoires/loa/decisions.yaml` (none `decided`: no operator was present). Confirm, reject or supersede them with `/decisions`. The table is `dec-write-lib.sh list --not-decided-by operator --format md` at the time of this PR.

<details>
<summary>123 proposed rows (DEC-0001 … DEC-0124; DEC-0123 and DEC-0124 were added by the Bridgebuilder round)</summary>

| Decision | Voice | Status | Why | Source |
|---|---|---|---|---|
| `rounds` becomes the default pacing for `thorough`; `sequential` stays as the documented opt-out (D1) (DEC-0001) | agent | proposed | the brief recommended it; Pocock's 1.2.0 made the same flip with a supported opt-out | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D1) |
| `decisions.yaml` lives at `grimoires/loa/decisions.yaml` and is tracked (D2) (DEC-0002) | agent | proposed | the original spec and two existing readers point there; team surface like `known-failures.md` | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D2) |
| `/chart` is a truename command, not a golden-path porcelain command; `/plan` reports `charting` (D3) (DEC-0003) | agent | proposed | narrow trigger; Pocock calls wayfinder a situational on-ramp | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D3) |
| Research tickets run as Opus subagents via the Agent tool, not cheval (D4) (DEC-0004) | agent | proposed | host-local, no provider dependency | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D4) |
| Pocock's `task` type is named `decision:unblock` (D5) (DEC-0005) | agent | proposed | the type that "goes wrong most often"; the name must not read as a build task | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D5) |
| Spike branches are `spike/<slug>`, pushed, never merged, no PR (D6) (DEC-0006) | agent | proposed | a pushed branch is the pointer the spike report needs; no PR keeps it off review | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D6) |
| `GLOSSARY.md` at the repo root, tracked; Loa dogfoods it (D7) (DEC-0007) | agent | proposed | root is where humans and Pocock's consumer rule look; the kernel drift check needs one path | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D7) |
| FR-8 safe set = zero-reference leaves; the referenced set is triaged per reference (D8) (DEC-0008) | agent | proposed | a flagged command an orchestrator executes as a step would break `/ship` | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D8) |
| B7 two-axis presentation and the LEARN items are future iterations, not this cycle (D9) (DEC-0009) | agent | proposed | simplicity first; the eight FRs are the brief's scope | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D9) |
| Two glossaries: the framework glossary ships at `.claude/loa/GLOSSARY.md` (drift-checked against the kernel i… (D10) (DEC-0010) | agent | proposed | consumer projects need the framework terms mounted, and their own terms must not live in the System Zone (Flatline opus IMP-009) | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D10) |
| Unattended prototype-class questions defer by default (`interview.unattended_prototype: defer`): open `DEC` r… (D11) (DEC-0011) | agent | proposed | a halt on every look-and-feel question would stall unattended planning; the deferred requirement is visible in the PRD and the ledger (Flatline gpt IMP-004, opus IMP-004) | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D11) |
| `/chart` refuses in unattended mode; research tickets are the only AFK work in a map (D12) (DEC-0012) | agent | proposed | a charted map whose questions the agent answered is the wayfinder failure pattern by construction (Flatline opus IMP-020) | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D12) |
| Agent decisions are `status: proposed` until `dec-write-lib.sh confirm` by the operator; the standing admin p… (D13) (DEC-0013) | agent | proposed | confirmation must be explicit and auditable per row (Flatline SKP-001a) | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D13) |
| `decided_by` is derived by the writer from run context; `operator` needs an `--answer-ref` (D14) (DEC-0014) | agent | proposed | self-reported attribution is unfalsifiable (Flatline SKP-001b) | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D14) |
| Rows are append-only with status transitions; content edits are rejected; `supersede` creates a new row (D15) (DEC-0015) | agent | proposed | a decision history that can be rewritten is not a record (Flatline SKP-002) | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D15) |
| Backfill is forward-only except cycle-127 D1–D3, seeded like every other seed row as `proposed` (D16) (DEC-0016) | agent | proposed | three rows give the validator a live fixture without a migration project, and no seed can claim a confirmation the operator has not given per row (Flatline gpt IMP-001, opus IMP-027; SDD review SKP-001) | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D16) |
| Operator transitions (`confirm`, `reject` or `supersede` of a decided row, clearing the unattended marker) ex… (D17) (DEC-0017) | agent | proposed | an agent that can clear its own unattended marker or confirm its own rows makes attribution meaningless (SDD review SKP-002) | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D17) |
| Implementers in linked worktrees write a per-sprint pending file with provisional ids; the lead imports it in… (D18) (DEC-0018) | agent | proposed | an append-only tracked YAML is unmergeable across branches and max+1 ids collide (SDD review SKP-003) | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D18) |
| Attribution is tamper-evident (artifact hashes, HEAD commit, append-only transitions), not signed; signing th… (D19) (DEC-0019) | agent | proposed | proportionate to a planning ledger; the signing infrastructure exists and can be attached later (SDD review SKP-002) | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D19) |
| Mike Farah yq v4 becomes a hard dependency for the ledger writer; the lock is portable (`flock` or a `mkdir` … (D20) (DEC-0020) | agent | proposed | hand-rolled YAML is the corruption risk the review named; macOS and BSD hosts are supported (SDD review SKP-004) | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D20) |
| Ledger lock fails closed after 10 s (A1) (DEC-0021) | agent | proposed | a lost update on a tracked ledger is worse than a retry | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A1) |
| Temp file beside the target (A2) (DEC-0022) | agent | proposed | a cross-filesystem `mv` is not atomic | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A2) |
| Verify by row equality plus field classes (A3) (DEC-0023) | agent | proposed | YAML re-serialisation moves lines | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A3) |
| Optional `cycle` field, defaulted from run state (A4) (DEC-0024) | agent | proposed | a run spans days; `--since` is kept as the PRD's equivalent | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A4) |
| `charting` from the map doc Status line (A5) (DEC-0025) | agent | proposed | golden-path must work without `br`; the doc wins on disagreement | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A5) |
| Hand-off context snapshot; chart zones add `context` and `spikes` (A6) (DEC-0026) | agent | proposed | no budget there. Widens the PRD's four-path zone list by two | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A6) |
| `research/chart-*.md` tracked by a negation (A7) (DEC-0027) | agent | proposed | maps need their cites | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A7) |
| Exclude `question` in `get-ready-work.sh` and route `/implement` through it (A8) (DEC-0028) | agent | proposed | `br ready` is unfiltered today | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A8) |
| Fence rule SP-1 plus the ICE spike rules (A9) (DEC-0029) | agent | proposed | ICE covers run mode only | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A9) |
| Seams rule gated by Date ≥ 2026-10-13 (A10) (DEC-0030) | agent | proposed | old fixtures have no Date (PRD adopted it) | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A10) |
| `_Aliases_:` lines; identifier-shaped tokens only (A11) (DEC-0031) | agent | proposed | run states are one concept (PRD adopted it) | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A11) |
| Flag the `loa-setup` skill only if the harness check shows the operator's command still works (A12) (DEC-0032) | agent | proposed | a shared name may leave the skill reachable, but the operator's own command must keep working | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A12) |
| Rounds within a phase (A13) (DEC-0033) | agent | proposed | keeps phase gates and section order | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A13) |
| Claim with `br update --claim` (A14) (DEC-0034) | agent | proposed | atomic assignee plus status | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A14) |
| Synchronous surface after the KF hook (A15) (DEC-0035) | agent | proposed | async output is not reliably injected | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A15) |
| Sprint validator cross-checks beads (A16) (DEC-0036) | agent | proposed | catches a `sprint:` label added by hand | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A16) |
| Map docs allow exactly four H2s plus `## Closed` (A17) (DEC-0037) | agent | proposed | an allowlist cannot be dodged by a new name | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A17) |
| `flatline`/`dissent` attribution needs an existing artifact and its sha256; no orchestrator call site this cy… (A18) (DEC-0038) | agent | proposed | keeps the sanctioned review path unchanged; the hash makes the claim checkable | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A18) |
| `confirm --cycle` previews and needs `--all` or `--id`s for several rows (A19) (DEC-0039) | agent | proposed | batch confirmation stays explicit | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A19) |
| The writer does not require `br` (superseded preflight rule) (A20) (DEC-0040) | agent | proposed | the ledger has no beads dependency; PR bodies render without beads | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A20) |
| The PRD Status line is an unattended signal for the gate and the writer, not for `confirm` (A21) (DEC-0041) | agent | proposed | the writer and the gate agree, and the operator can still confirm later | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A21) |
| Chart ticket rows use `source: map:<slug>/<ticket>`; the bead carries `--external-ref <DEC-id>` (A22) (DEC-0042) | agent | proposed | the row is written before the bead exists and `source` is immutable | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A22) |
| A `chart-researcher` agent without Bash, plus an ignored-files and mtime scope check (A23) (DEC-0043) | agent | proposed | tool removal is mechanical; prompts are not | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A23) |
| Spike deletion through a fence predicate on a decided row (A24) (DEC-0044) | agent | proposed | the PRD allows deletion once decided; the predicate is positive and fails closed | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A24) |
| `.run/unattended.json` with session id and TTL, plus a `context` subcommand (A25) (DEC-0045) | agent | proposed | Bash calls do not share env; a stale marker must not outlive its session | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A25) |
| `/plan-and-analyze` closes a consumed map and applies the multi-map rule via command-file steps (A26) (DEC-0046) | agent | proposed | no SKILL budget; the command file is not budgeted | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A26) |
| Each `[ASSUMPTION decision]` line cites its DEC id (A27) (DEC-0047) | agent | proposed | a per-tag link is checkable; counts are not | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A27) |
| ICE allows only the default branch into a `spike/*` branch, behind an optional argument (A28) (DEC-0048) | agent | proposed | the narrowest exception, default behaviour unchanged | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A28) |
| The live-harness bats is opt-in (`LOA_LIVE_HARNESS=1`) and every outcome is defined (A29) (DEC-0049) | agent | proposed | a model call per CI run costs money and flakes; a skip is visible, a false pass is not | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A29) |
| `red-test-check.sh` timeout is its own exit 5 and dependency linking is on by default (A30) (DEC-0050) | agent | proposed | a hung test is not a failing fix; fresh worktrees mostly fail on missing dependencies | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A30) |
| `proposed_by` records the proposing voice; `decided_by` is set once, by `confirm` (A31) (DEC-0051) | agent | proposed | lets `decided_by` stay null until a human acts, without rewriting a set-once field | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A31) |
| `/decisions` runs operator ops in the session, previewing first; no fence on the writer (A32) (DEC-0052) | agent | proposed | the fence would also block the command itself; the boundary is the allowlists plus tamper evidence | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A32) |
| Linked worktrees write `PEND-` rows to a sprint pending file; the lead imports (A33) (DEC-0053) | agent | proposed | max+1 ids collide and an append-only YAML list does not merge | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A33) |
| `mkdir` lock fallback with a 60 s stale check when `flock` is absent (A34) (DEC-0054) | agent | proposed | macOS ships without `flock` | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A34) |
| `hook-guard.sh` exports `LOA_HOOK_CONTEXT=1`; live-ledger writes refuse under it and under CI (A35) (DEC-0055) | agent | proposed | makes "no bot auto-append" mechanical while fixtures still run in CI | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A35) |
| `BARE_ASSUMPTION_FAILS_FROM=2026-11-13` (A36) (DEC-0056) | agent | proposed | a date is checkable; a release boundary is not | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A36) |
| `get-ready-work.sh` filters out `question` instead of allowlisting types (A37) (DEC-0057) | agent | proposed | new types keep flowing; only decision tickets are excluded | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A37) |
| `decision:unblock` probes run only through `chart-unblock-probe.sh` (A38) (DEC-0058) | agent | proposed | the helper proves the main tree is untouched | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A38) |
| BSD coverage through PATH-shim twins (A39) (DEC-0059) | agent | proposed | follows `validate-artifact-bsd.bats`; no new CI runner | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A39) |
| `run-preflight.sh` P9 fails without yq v4 (A40) (DEC-0060) | agent | proposed | the ledger cannot be written without it | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A40) |
| The append-only base defaults to `git merge-base origin/main HEAD` (A41) (DEC-0061) | agent | proposed | rows added on the branch remain checkable against main | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A41) |
| agy opt-in, default off (c127-D1) (DEC-0062) | agent | proposed | Facts: `gemini-headless` → `AgyHeadlessAdapter` on any host with agy on PATH; hosts without agy (this one) plan a voice that fails (BB #1274 DEGRADED 2/3); the prompt rides on argv. Decision: a config key (default off) gates the agy route; planners (BB voice list, dissent family chain, Flatline tertiary, preflight, `/loa`) treat it as disabled unless opted in; the argv exposure is the documented r | grimoires/loa/NOTES.md#decision-log-2026-10-07 (bd-ugmi) (c127-D1) |
| `claude-opus-5-5` catalog effort default `high` (c127-D2) (DEC-0063) | agent | proposed | Fact (claude-api skill, 2026-10-07): Opus 5.5's vendor effort default is `medium`, one below Opus 5's `high`, so every `opus` caller passing no `--effort` lost a level at the alias retarget; the headless adapter already reads a catalog `extra.effort`, the HTTP adapter does not. Decision: resolve the catalog default once at the cheval chokepoint when the caller passes none; `--effort` overrides; MO | grimoires/loa/NOTES.md#decision-log-2026-10-07 (bd-9qe2) (c127-D2) |
| probe the ceiling through this host's route (c127-D3) (DEC-0064) | agent | proposed | Facts: `tools/ceiling-probe-live.py` uses the direct API (geo-refused here, no key); every Opus 5.5 hop here runs through `claude-bedrock` → `global.anthropic.claude-opus-5-5`. Decision: add `--transport claude-headless` to the probe (mirrors the adapter's CLI flags), bisect 180K→1M (≈ $12–20 Bedrock input, authorized), record a clean bound as `ceiling_calibration.source: operator_set` + `calibrat | grimoires/loa/NOTES.md#decision-log-2026-10-07 (c127-D3) |
| /update-loa: not flagged (deferred) (refs 11, orchestrator steps 0) (fr8-update-loa) (DEC-0065) | agent | proposed | Every reference is advice, but the D-8.3 lint reads `Run /update-loa --force-restore` in the `translate-ride.md:145` troubleshooting table as operative; part C may not edit that file; evidence `translate-ride.md:145`; probe output below | grimoires/loa/a2a/sprint-252/triage-fr8.md#decision-per-command (fr8-update-loa) |
| /mount: not flagged (deferred) (refs 13, orchestrator steps 0) (fr8-mount) (DEC-0066) | agent | proposed | Every reference is advice, but seven user-facing error strings (`error: "... Run /mount first."`, troubleshooting rows) trip the lint; part C may not edit those files; evidence `ride.md:62,66,70,282,283`, `run.md:60`, `run-sprint-plan.md:44` | grimoires/loa/a2a/sprint-252/triage-fr8.md#decision-per-command (fr8-mount) |
| /contribute: FLAGGED (refs 1, orchestrator steps 0) (fr8-contribute) (DEC-0067) | agent | proposed | The only reference is advice (`loa-eject.md`); the command opens an upstream PR, an outward-facing act; evidence `loa-eject.md:260` | grimoires/loa/a2a/sprint-252/triage-fr8.md#decision-per-command (fr8-contribute) |
| /feedback: not flagged (refs 24 (10 are path matches), orchestrator steps 0 in bodies) (fr8-feedback) (DEC-0068) | agent | proposed | Body references are advice, but `.claude/loa/reference/agent-teams-reference.md:59,278` sanctions teammate invocation of `/feedback`, a model invocation path outside the command and skill bodies; evidence `agent-teams-reference.md:59` | grimoires/loa/a2a/sprint-252/triage-fr8.md#decision-per-command (fr8-feedback) |
| /deploy-production: not flagged (refs 12, orchestrator steps 7) (fr8-deploy-production) (DEC-0069) | agent | proposed | `/ship` executes it and the autonomous agent runs it in Phase 6; evidence `ship.md:60`, `autonomous-agent/SKILL.md:180` | grimoires/loa/a2a/sprint-252/triage-fr8.md#decision-per-command (fr8-deploy-production) |
| /archive-cycle: not flagged (refs 12, orchestrator steps 7) (fr8-archive-cycle) (DEC-0070) | agent | proposed | `/ship` executes it; `/loa` invokes it after the user confirms; evidence `ship.md:64`, `loa.md:265` | grimoires/loa/a2a/sprint-252/triage-fr8.md#decision-per-command (fr8-archive-cycle) |
| /ship: not flagged (refs 16, orchestrator steps 1) (fr8-ship) (DEC-0071) | agent | proposed | `/loa` invokes it when the user picks the menu option; evidence `loa.md:262` | grimoires/loa/a2a/sprint-252/triage-fr8.md#decision-per-command (fr8-ship) |
| /run-halt: FLAGGED (refs 9, orchestrator steps 0) (fr8-run-halt) (DEC-0072) | agent | proposed | Every reference is a related-commands list, help line or recovery option for the human; the run-mode circuit breaker halts without the command; evidence `run-mode/SKILL.md:224`, `escalation-report.md:151` | grimoires/loa/a2a/sprint-252/triage-fr8.md#decision-per-command (fr8-run-halt) |
| /run-resume: not flagged (refs 29, orchestrator steps 2) (fr8-run-resume) (DEC-0073) | agent | proposed | `/simstim` resume invokes it in place of a fresh run; evidence `simstim.md:462`, `simstim-workflow/resources/resume-support.md:132` | grimoires/loa/a2a/sprint-252/triage-fr8.md#decision-per-command (fr8-run-resume) |
| One helper (chart-ticket.sh) owns the /chart write steps; the SDD's raw br and ledger-writer grants stay in al (S2-D1) (DEC-0074) | agent | proposed | prose cannot prove the write order, idempotency, the research cap or the unattended-close rule in bats; Task 2.4 covers the shell steps | grimoires/loa/a2a/sprint-253/reviewer-d.md#decisions-taken-beyond-the-sdd-alternatives-and-why |
| A map ticket's ledger row source is map:<slug>/<ticket> (SDD A22), not the bead id (S2-D2) (DEC-0075) | agent | proposed | the row is written before the bead exists and source is immutable; list --source-epic keys on this form | grimoires/loa/a2a/sprint-253/reviewer-d.md#decisions-taken-beyond-the-sdd-alternatives-and-why |
| Claiming a ticket uses br update --claim (D-4.4), not --status in_progress (S2-D3) (DEC-0076) | agent | proposed | --claim also sets the assignee, which the frontier's unclaimed filter relies on | grimoires/loa/a2a/sprint-253/reviewer-d.md#decisions-taken-beyond-the-sdd-alternatives-and-why |
| Map Status has four values (charting, handed-off, closed, abandoned); the epic closes at close, not at hand-of (S2-D4) (DEC-0077) | agent | proposed | D-4.5 puts the epic close in the close step; close sets closed for a consumed map and abandoned for a reason | grimoires/loa/a2a/sprint-253/reviewer-d.md#decisions-taken-beyond-the-sdd-alternatives-and-why |
| Open tickets live on beads only; the map doc gains a line when a ticket is resolved or ruled out, and a new do (S2-D5) (DEC-0078) | agent | proposed | the four allowed sections have no place for open tickets and a list would duplicate beads state | grimoires/loa/a2a/sprint-253/reviewer-d.md#decisions-taken-beyond-the-sdd-alternatives-and-why |
| chart-frontier.sh inlines the bv --robot-triage ranking instead of calling get-ready-work.sh (S2-D6) (DEC-0079) | agent | proposed | the build path drops question beads by design and its limit would cap the set | grimoires/loa/a2a/sprint-253/reviewer-d.md#decisions-taken-beyond-the-sdd-alternatives-and-why |
| The unblock probe and research scope check snapshot git status --porcelain --untracked-files=all --ignored=mat (S2-D7) (DEC-0080) | agent | proposed | a write inside an already-untracked or ignored directory is invisible to a collapsed status | grimoires/loa/a2a/sprint-253/reviewer-d.md#decisions-taken-beyond-the-sdd-alternatives-and-why |
| An unblock ticket requires --unblocks <ticket\|DEC>, appended to the body as Unblocks: X (S2-D8) (DEC-0081) | agent | proposed | makes D-4.12 (the body names the decision it unblocks) mechanical | grimoires/loa/a2a/sprint-253/reviewer-d.md#decisions-taken-beyond-the-sdd-alternatives-and-why |
| D's suites are charting-decisions.bats and chart-frontier.bats, separate from E's charting-lint.bats (S2-D9) (DEC-0082) | agent | proposed | no collision between the two implementers' suites | grimoires/loa/a2a/sprint-253/reviewer-d.md#decisions-taken-beyond-the-sdd-alternatives-and-why |
| skill-capabilities.bats SC-T-AGENT-7 and agents-md-gen.bats pins were edited for the new agent type and comman (S2-D10) (DEC-0083) | agent | proposed | the SDD's own additions (a new agent, a new command) require both edits | grimoires/loa/a2a/sprint-253/reviewer-d.md#decisions-taken-beyond-the-sdd-alternatives-and-why |
| Validator beads cross-checks run only when the validated file is inside PROJECT_ROOT (S2-E1) (DEC-0084) | agent | proposed | a /tmp fixture has no relation to the project's beads and an env opt-out is a bypass; keeps every suite off the real database | grimoires/loa/a2a/sprint-253/reviewer-e.md#decisions-taken-beyond-the-sdd |
| The map validator accepts four Status values including closed (S2-E2) (DEC-0085) | agent | proposed | D-4.5 and D-4.6 define closed as the consumed state | grimoires/loa/a2a/sprint-253/reviewer-e.md#decisions-taken-beyond-the-sdd |
| A map doc must have exactly one H1 (S2-E3) (DEC-0086) | agent | proposed | a second H1 would dodge the H2 allowlist | grimoires/loa/a2a/sprint-253/reviewer-e.md#decisions-taken-beyond-the-sdd |
| A missing DEC id under a spike report's Decided by WARNs rather than fails (S2-E4) (DEC-0087) | agent | proposed | the shipped template must pass (D-5.5) and the row may be written after the report | grimoires/loa/a2a/sprint-253/reviewer-e.md#decisions-taken-beyond-the-sdd |
| SP-1 also blocks git checkout <spike> <path> without --, git -C and -c forms, commit ranges, and a headless gh (S2-E5) (DEC-0088) | agent | proposed | the same copy through the most common alternate spellings; each check is positive and offline | grimoires/loa/a2a/sprint-253/reviewer-e.md#decisions-taken-beyond-the-sdd |
| ICE safe_merge on a spike head runs git merge --no-edit for an exact allowlist (main, master, origin/main, ori (S2-E6) (DEC-0089) | agent | proposed | the other ICE wrappers perform their operation; an exact list leaves no flag injection | grimoires/loa/a2a/sprint-253/reviewer-e.md#decisions-taken-beyond-the-sdd |
| The D-5.9 spike unlock requires the last transition to decided to be by operator:* and strips a #anchor from s (S2-E7) (DEC-0090) | agent | proposed | a decided row is operator-confirmed by schema; the anchor form is what the writer records elsewhere | grimoires/loa/a2a/sprint-253/reviewer-e.md#decisions-taken-beyond-the-sdd |
| planning-sprints budget room came from moving the integration-context list to REFERENCE.md (S2-E8) (DEC-0091) | agent | proposed | the D-5.1 wording stays verbatim in all three skills | grimoires/loa/a2a/sprint-253/reviewer-e.md#decisions-taken-beyond-the-sdd |
| Matching also folds `-`, `_` and spaces, so `run-mode` and `run_mode` resolve to **Run mode**. The plural fold (S3-F1) (DEC-0092) | agent | proposed | implementer F's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-f.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-f.md#assumptions |
| Only entries and aliases inside `## Language` resolve tokens or count for duplicates. Other H2 sections are al (S3-F2) (DEC-0093) | agent | proposed | implementer F's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-f.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-f.md#assumptions |
| A missing allowlist file is a usage error (exit 2), never an empty allowlist. An allowlist entry is the first (S3-F3) (DEC-0094) | agent | proposed | implementer F's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-f.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-f.md#assumptions |
| The checker WARNs on a redundant allowlist entry, one the glossary already resolves, in addition to the specif (S3-F4) (DEC-0095) | agent | proposed | implementer F's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-f.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-f.md#assumptions |
| The validator fails any non-blank line in `## Language` that is not an entry, an `_Avoid_:` or `_Aliases_:` li (S3-F5) (DEC-0096) | agent | proposed | implementer F's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-f.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-f.md#assumptions |
| Sentences are counted as runs of `.`, `!` or `?` followed by whitespace; abbreviations like "e.g." count as se (S3-F6) (DEC-0097) | agent | proposed | implementer F's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-f.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-f.md#assumptions |
| A non-`# Glossary: <name>` H1 WARNs rather than fails, since D-6.4 asks only for an H1. (S3-F7) (DEC-0098) | agent | proposed | implementer F's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-f.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-f.md#assumptions |
| The CI gate step also validates both glossaries with `--type glossary`, so a format break fails the same job. (S3-F8) (DEC-0099) | agent | proposed | implementer F's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-f.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-f.md#assumptions |
| The framework glossary seeds Circuit breaker and Fog of war beyond D-6.1; the PRD Appendix D glossary already (S3-F9) (DEC-0100) | agent | proposed | implementer F's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-f.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-f.md#assumptions |
| The validator suite is a new file, `glossary-validator.bats`, rather than cases in `validate-artifact.bats`, t (S3-F10) (DEC-0101) | agent | proposed | implementer F's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-f.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-f.md#assumptions |
| The header date is the first `**Date:**` line before the first H2. A date line further down does not gate the (S3-G1) (DEC-0102) | agent | proposed | implementer G's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-g.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-g.md#assumptions |
| A sprint block runs from its `## Sprint N` heading to the next H2 of any kind. Headings inside fenced code are (S3-G2) (DEC-0103) | agent | proposed | implementer G's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-g.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-g.md#assumptions |
| A Seams block passes only with at least one table row below its separator line. A heading with only the header (S3-G3) (DEC-0104) | agent | proposed | implementer G's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-g.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-g.md#assumptions |
| An earlier or undated plan WARNs once, and only when at least one sprint block lacks the block. (S3-G4) (DEC-0105) | agent | proposed | implementer G's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-g.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-g.md#assumptions |
| `--setup` is split on whitespace into an argv and never passed to `bash -c`. This keeps the no-`bash -c` rule. (S3-G5) (DEC-0106) | agent | proposed | implementer G's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-g.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-g.md#assumptions |
| A `--setup` failure or timeout exits 2. TIMEOUT (exit 5) is kept for test runs. (S3-G6) (DEC-0107) | agent | proposed | implementer G's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-g.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-g.md#assumptions |
| Verdict precedence judges the red side first (timeout, then DECOY, then NOT_A_RED), then the green side (timeo (S3-G7) (DEC-0108) | agent | proposed | implementer G's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-g.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-g.md#assumptions |
| Both runs always happen, so `--json` reports both exits. (S3-G8) (DEC-0109) | agent | proposed | implementer G's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-g.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-g.md#assumptions |
| A red exit of 126 or 127 is NOT_A_RED alongside the D-7.6 patterns. The bats patterns also cover the gather fa (S3-G9) (DEC-0110) | agent | proposed | implementer G's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-g.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-g.md#assumptions |
| With `timeout` or `gtimeout`, exit 124 means a timeout. So does exit 137 once the limit has elapsed. A test th (S3-G10) (DEC-0111) | agent | proposed | implementer G's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-g.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-g.md#assumptions |
| Each run gets its own process group through `set -m`, so a timeout or an interrupt stops the whole tree it spa (S3-G11) (DEC-0112) | agent | proposed | implementer G's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-g.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-g.md#assumptions |
| A path counts as a test path for the WARN if it is under `test/`, `tests/`, `spec/`, `__tests__/`, `testdata/` (S3-G12) (DEC-0113) | agent | proposed | implementer G's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-g.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-g.md#assumptions |
| `--test-file` must be relative to the repository root. `--red` and `--green` values starting with `-` are reje (S3-G13) (DEC-0114) | agent | proposed | implementer G's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-g.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-g.md#assumptions |
| Exit-2 errors print to stderr only. `--json` emits its object for verdicts 0, 1, 3, 4 and 5, with exits set to (S3-G14) (DEC-0115) | agent | proposed | implementer G's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-g.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-g.md#assumptions |
| `reviewing-code` gains the allowed-tools and `execute_commands` grant for the script, so the Phase 2 instructi (S3-G15) (DEC-0116) | agent | proposed | implementer G's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-g.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-g.md#assumptions |
| `checksums.json` was refreshed for git-tracked files only: changed tracked files were re-hashed, new tracked f (S3-H1) (DEC-0117) | agent | proposed | implementer H's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-h.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-h.md#assumptions |
| The fixture sync is in scope as a release surface. Without it, the required `sync-fixtures.sh --check` would f (S3-H2) (DEC-0118) | agent | proposed | implementer H's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-h.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-h.md#assumptions |
| The CHANGELOG gains a `### Migration` heading, following the release-level "Migration guide" heading already i (S3-H3) (DEC-0119) | agent | proposed | implementer H's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-h.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-h.md#assumptions |
| The cycle-128 surfaces in hooks-reference get one table of their own. `chart-guard.sh` and the FR-8 lint are g (S3-H4) (DEC-0120) | agent | proposed | implementer H's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-h.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-h.md#assumptions |
| Fixed now holds only the fix to pre-existing behaviour (`validate-gitignore-state.sh`). Fixes to code that had (S3-H5) (DEC-0121) | agent | proposed | implementer H's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-h.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-h.md#assumptions |
| The E2E rows that H ran with read-only commands are marked H. The lead's G-1 to G-4 and G-7 rows keep the lead (S3-H6) (DEC-0122) | agent | proposed | implementer H's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-h.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-h.md#assumptions |
| A `proposed` row carries `proposed_by` (the voice that proposed it) and `decided_by` null; `decided_by` is set (D21) (DEC-0123) | agent | proposed | a decision nobody has confirmed has no decider; attribution of the proposal is what the row records (implementer B following SDD §3.1 and A31) | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf |
| The PRD Status line is a planning-time default only, not a live unattended signal (DEC-0124) | agent | proposed | otherwise every operator confirm after an autonomous cycle records decided_by agent and /chart refuses forever (Bridgebuilder F-003) | grimoires/loa/a2a/sprint-254/bb-anthropic.md#F-003 |
Confirm with /decisions confirm.

</details>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
~~~~
~~~~~

## I10 — issue — 2026-10-13

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

## I11 — fix-commit — 2026-10-14

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

## I12 — fix-commit — 2026-10-14

- reference: cf88e4270d58
- files: .claude/adapters/loa_cheval/providers/base.py,.claude/adapters/loa_cheval/providers/openai_adapter.py,.claude/loa/reference/multi-model-reference.md,.claude/skills/bridgebuilder-review/dist/.build-manifest.json,.claude/skills/bridgebuilder-review/dist/config.d.ts.map,.claude/skills/bridgebuilder-review/dist/config.js,.claude/skills/bridgebuilder-review/dist/config.js.map,.claude/skills/bridgebuilder-review/resources/config.ts

Summary:

fix(cycle-129): sprint-257 review round r257-1 — a declared dispatch_group: local is enforced, not trusted (HIGH-1: the local-hop rule — an HTTP provider whose endpoint host is a loopback or RFC1918 IP literal or localhost — stated once in endpoint_policy and applied at load, at request time by TransportPolicy.local, in hop-locality.py (endpoint_not_local / endpoint_missing / cli_provider), in Br…

Evidence (first 200 of 510 lines):

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
diff --git a/.claude/adapters/loa_cheval/providers/openai_adapter.py b/.claude/adapters/loa_cheval/providers/openai_adapter.py
index 8051bfa5..92d86a31 100644
--- a/.claude/adapters/loa_cheval/providers/openai_adapter.py
+++ b/.claude/adapters/loa_cheval/providers/openai_adapter.py
@@ -217,9 +217,11 @@ class OpenAIAdapter(ProviderAdapter):
     def _transport_policy(self, model_config: ModelConfig) -> Optional[TransportPolicy]:
         """The D-7.2 TransportPolicy when the provider carries an insecure-endpoint
         opt-in or the model's dispatch_group is `local`; None otherwise (hosted
-        providers keep today's transport unchanged)."""
-        if getattr(self.config, "allow_insecure_endpoint", None) or getattr(model_config, "dispatch_group", None) == "local":
-            return TransportPolicy(endpoint=self.config.endpoint, provider=self.provider)
+        providers keep today's transport unchanged). A local hop also carries the
+        local-hop host rule (D-8.1, r257-1)."""
+        local = getattr(model_config, "dispatch_group", None) == "local"
+        if getattr(self.config, "allow_insecure_endpoint", None) or local:
+            return TransportPolicy(endpoint=self.config.endpoint, provider=self.provider, local=local)
         return None
 
     def _dispatch(
diff --git a/.claude/loa/reference/multi-model-reference.md b/.claude/loa/reference/multi-model-reference.md
index 5ddd5bc4..8fdcb976 100644
--- a/.claude/loa/reference/multi-model-reference.md
+++ b/.claude/loa/reference/multi-model-reference.md
@@ -99,7 +99,7 @@ ### Rollback (cycle-109 model)
 still `git revert` of the cycle-124 unit commits (see the Sprint 1 rollback
 proof). Env table: `grimoires/loa/runbooks/cheval-delegate-architecture.md`.
 
-cycle-129 (FR-8) — **local posture**: under `hounfour.locality: local_voices` the dissent, Flatline, Bridgebuilder and health-probe hops are planned only on providers whose model entry says `dispatch_group: local`, each hosted hop refused by name at plan time; the Claude Code session model is exempt and remains the platform, so a local posture keeps model calls local but the session itself still runs against Anthropic. Fewer voices means a DEGRADED verdict quality where the planned voice count is not met — the posture says so in the config comment and in the run output rather than inventing a voice. One fail-closed classifier (`.claude/scripts/lib/hop-locality.py`) serves the shell scripts: an unresolved hop, an unreadable config or a local entry whose fallback chain reaches a hosted entry counts as hosted; an invalid value refuses the run.
+cycle-129 (FR-8) — **local posture**: under `hounfour.locality: local_voices` the dissent, Flatline, Bridgebuilder and health-probe hops are planned only on providers whose model entry says `dispatch_group: local`, each hosted hop refused by name at plan time; the Claude Code session model is exempt and remains the platform, so a local posture keeps model calls local but the session itself still runs against Anthropic. Fewer voices means a DEGRADED verdict quality where the planned voice count is not met — the posture says so in the config comment and in the run output rather than inventing a voice. One fail-closed classifier (`.claude/scripts/lib/hop-locality.py`) serves the shell scripts: an unresolved hop, an unreadable config or a local entry whose fallback chain reaches a hosted entry counts as hosted; an invalid value refuses the run. A declared locality is enforced, not trusted: a hop is local only when its provider is an HTTP provider (not a CLI provider) whose endpoint host is an IP literal in a loopback (`127.0.0.0/8`, `::1`) or RFC1918 (`10/8`, `172.16/12`, `192.168/16`) range, or the literal `localhost` — the host rule of `allow_insecure_endpoint` (an `https` endpoint on such a host needs no opt-in; an `http` one does). The rule is applied at config load (the cheval loader refuses any other `dispatch_group: local` by name), at request time (the local hop's transport policy refuses a request host that fails it), in the planner (`hop-locality.py`: `endpoint_not_local:<host>`) and in Bridgebuilder's locality filter.
 
 cycle-129 (FR-7) — **open-weight and local voices**: a local OpenAI-compatible server is declared as a provider (`type: openai_compat`, `keyless: true`, `allow_insecure_endpoint: "<host>"` where the host is a loopback or RFC1918 IP literal or `localhost`; Example 4 in `.loa.config.yaml.example`). The endpoint rule lives once in `.claude/scripts/lib/endpoint-validator.py` and is used by the cheval loader (`loa_cheval/config/endpoint_policy.py`), the bash wrapper and `model-health-probe.sh --provider <name>`, which probes a configured provider's `/models` with no credential when keyless; at request time a local hop runs with no proxy, no redirects and the declared path prefix. cheval refuses an `http`, loopback or private endpoint without the opt-in at load, for every provider. On the chat-completions path a `structured_json` entry sends `response_format` json_schema and `schema_enforced` is derived from the body sent (one retry without the schema on a server 400 that names it); `reasoning_content`, `reasoning` deltas and a leading `<think>` block go to `thinking` (`thinking_stripped`); an over-window prompt is refused by name. **Advisory voices**: `flatline_protocol.code_review.advisory_voices` and `security_audit.advisory_voices` run beside the counted voices under `advisory_timeout_seconds`; their findings appear only under `advisory_voices[].findings` with `duplicate_of` links and never touch the verdict, the counts or the cost totals — promotion to a counted role needs `hounfour.advisory_promotion`. The budget gate prices each planned voice from the catalog (`loa_cheval.metering.pricing --alias … --json`), whose entries now carry `open_weight`, `price_source` and `price_date`. **Bridgebuilder** reads `hounfour.providers`, `hounfour.locality` and `bridgebuilder.exit_on_degraded` from trusted configuration only (locally the working tree; on a pull request the `BRIDGEBUILDER_TRUSTED_CONFIG` repository variable, else the base branch's config, never the head), prints `completed/planned` voices and exits 3 on a DEGRADED consensus (`0` restores the old exit; `entry.sh`'s dependency preflight exits 4).
 
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
diff --git a/.claude/skills/bridgebuilder-review/dist/config.d.ts.map b/.claude/skills/bridgebuilder-review/dist/config.d.ts.map
index 8b3cb0bd..7459b702 100644
--- a/.claude/skills/bridgebuilder-review/dist/config.d.ts.map
+++ b/.claude/skills/bridgebuilder-review/dist/config.d.ts.map
@@ -1 +1 @@
-{"version":3,"file":"config.d.ts","sourceRoot":"","sources":["../resources/config.ts"],"names":[],"mappings":"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"}
\ No newline at end of file
+{"version":3,"file":"config.d.ts","sourceRoot":"","sources":["../resources/config.ts"],"names":[],"mappings":"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"}
\ No newline at end of file
diff --git a/.claude/skills/bridgebuilder-review/dist/config.js b/.claude/skills/bridgebuilder-review/dist/config.js
index 7b105e84..480c2e81 100644
--- a/.claude/skills/bridgebuilder-review/dist/config.js
+++ b/.claude/skills/bridgebuilder-review/dist/config.js
@@ -2,6 +2,7 @@ import { execFile, execFileSync, execSync } from "node:child_process";
 import { promisify } from "node:util";
 import { readFile } from "node:fs/promises";
 import { closeSync, existsSync, fstatSync, openSync, readFileSync, statSync } from "node:fs";
+import { isIPv6 } from "node:net";
 import { join } from "node:path";
 import { z } from "zod/v4";
 import { GENERATED_MODEL_REGISTRY } from "./config.generated.js";
@@ -409,6 +410,8 @@ const ProviderEntrySchema = z.looseObject({
     auth: z.unknown().optional(),
     allow_insecure_endpoint: z.unknown().optional(),
     dispatch_group: z.unknown().optional(),
+    endpoint: z.unknown().optional(),
+    type: z.unknown().optional(),
     models: z.unknown().optional(),
 });
 const ENV_AUTH_RE = /^\{env:([A-Za-z_][A-Za-z0-9_]*)\}$/;
@@ -435,18 +438,26 @@ export function parseProviderDecls(raw, label, warnings) {
         const envMatch = auth !== undefined ? ENV_AUTH_RE.exec(auth) : null;
         const literalAuth = auth !== undefined && auth !== "" && !auth.includes("{env:");
         const modelGroups = {};
+        let modelCount = 0;
+        let cliModels = 0;
         if (e.models !== null && typeof e.models === "object" && !Array.isArray(e.models)) {
             for (const [mid, m] of Object.entries(e.models)) {
                 const g = m !== null && typeof m === "object" ? m.dispatch_group : undefined;
                 modelGroups[mid] = typeof g === "string" ? g : undefined;
+                modelCount += 1;
+                if (m !== null && typeof m === "object" && m.kind === "cli")
+                    cliModels += 1;
             }
         }
+        const cli = (typeof e.type === "string" && e.type.endsWith("-headless")) || (modelCount > 0 && cliModels === modelCount);
         out[name] = {
             keyless: e.keyless === true || literalAuth,
             insecure: e.allow_insecure_endpoint !== undefined && e.allow_insecure_endpoint !== null && e.allow_insecure_endpoint !== false,
             ...(envMatch ? { authEnv: envMatch[1] } : {}),
             ...(typeof e.dispatch_group === "string" ? { dispatchGroup: e.dispatch_group } : {}),
             modelGroups,
+            ...(typeof e.endpoint === "string" ? { endpoint: e.endpoint } : {}),
+            ...(cli ? { cli: true } : {}),
         };
     }
     return out;
@@ -648,20 +659,112 @@ export function trustedConfigStartupLine(t) {
     return `[bridgebuilder] Trusted config: ${where} (mode: ${t.mode}); locality: ${t.locality}; exit_on_degraded: ${t.exitOnDegraded}` +
         (keyless.length > 0 ? `; keyless providers: ${keyless.join(", ")}` : "");
 }
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
~~~~

## I13 — fix-commit — 2026-10-14

- reference: 07110d7052ea
- files: .claude/adapters/cheval.py,.claude/adapters/loa_cheval/providers/base.py,.claude/adapters/loa_cheval/types.py,.claude/loa/reference/multi-model-reference.md,.claude/skills/bridgebuilder-review/dist/.build-manifest.json,.claude/skills/bridgebuilder-review/dist/config.d.ts.map,.claude/skills/bridgebuilder-review/dist/config.js,.claude/skills/bridgebuilder-review/dist/config.js.map,.claude/skills/bridgebuilder-review/resources/config.ts

Summary:

fix(cycle-129): sprint-257 security audit round a257-1 — a declared locality is enforced where the prompt is sent: under hounfour.locality local_voices cheval plans around every chain hop that fails the local-hop rule (one stderr line each, MODELINV models_not_planned reason locality_refused) and refuses an all-hosted chain before any dispatch (LocalityRefusedError, failure_class locality_refused…

Evidence (first 200 of 778 lines):

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
diff --git a/.claude/adapters/loa_cheval/types.py b/.claude/adapters/loa_cheval/types.py
index 14e473f2..5d14b314 100644
--- a/.claude/adapters/loa_cheval/types.py
+++ b/.claude/adapters/loa_cheval/types.py
@@ -540,6 +540,18 @@ class AgyOptInRequiredError(ConfigError):
         super().__init__(message, context={"failure_class": self.failure_class})
 
 
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
 class AuthRevokedError(ChevalError):
     """Runtime auth-credential revocation on a CLI/subscription leg (KF-017/#1071).
 
diff --git a/.claude/loa/reference/multi-model-reference.md b/.claude/loa/reference/multi-model-reference.md
index 8fdcb976..1191be99 100644
--- a/.claude/loa/reference/multi-model-reference.md
+++ b/.claude/loa/reference/multi-model-reference.md
@@ -99,9 +99,9 @@ ### Rollback (cycle-109 model)
 still `git revert` of the cycle-124 unit commits (see the Sprint 1 rollback
 proof). Env table: `grimoires/loa/runbooks/cheval-delegate-architecture.md`.
 
-cycle-129 (FR-8) — **local posture**: under `hounfour.locality: local_voices` the dissent, Flatline, Bridgebuilder and health-probe hops are planned only on providers whose model entry says `dispatch_group: local`, each hosted hop refused by name at plan time; the Claude Code session model is exempt and remains the platform, so a local posture keeps model calls local but the session itself still runs against Anthropic. Fewer voices means a DEGRADED verdict quality where the planned voice count is not met — the posture says so in the config comment and in the run output rather than inventing a voice. One fail-closed classifier (`.claude/scripts/lib/hop-locality.py`) serves the shell scripts: an unresolved hop, an unreadable config or a local entry whose fallback chain reaches a hosted entry counts as hosted; an invalid value refuses the run. A declared locality is enforced, not trusted: a hop is local only when its provider is an HTTP provider (not a CLI provider) whose endpoint host is an IP literal in a loopback (`127.0.0.0/8`, `::1`) or RFC1918 (`10/8`, `172.16/12`, `192.168/16`) range, or the literal `localhost` — the host rule of `allow_insecure_endpoint` (an `https` endpoint on such a host needs no opt-in; an `http` one does). The rule is applied at config load (the cheval loader refuses any other `dispatch_group: local` by name), at request time (the local hop's transport policy refuses a request host that fails it), in the planner (`hop-locality.py`: `endpoint_not_local:<host>`) and in Bridgebuilder's locality filter.
+cycle-129 (FR-8) — **local posture**: under `hounfour.locality: local_voices` the dissent, Flatline, Bridgebuilder and health-probe hops are planned only on providers whose model entry says `dispatch_group: local`, each hosted hop refused by name at plan time; the Claude Code session model is exempt and remains the platform, so a local posture keeps model calls local but the session itself still runs against Anthropic. Fewer voices means a DEGRADED verdict quality where the planned voice count is not met — the posture says so in the config comment and in the run output rather than inventing a voice. One fail-closed classifier (`.claude/scripts/lib/hop-locality.py`) serves the shell scripts: an unresolved hop, an unreadable config or a local entry whose fallback chain reaches a hosted entry counts as hosted; an invalid value refuses the run. A declared locality is enforced, not trusted: a hop is local only when its provider is an HTTP provider (not a CLI provider) whose endpoint host is an IP literal in a loopback (`127.0.0.0/8`, `::1`) or RFC1918 (`10/8`, `172.16/12`, `192.168/16`) range, or the literal `localhost` — the host rule of `allow_insecure_endpoint` (an `https` endpoint on such a host needs no opt-in; an `http` one does). The rule is applied at config load (the cheval loader refuses any other `dispatch_group: local` by name), at request time (the local hop's transport policy refuses a request host that fails it), in the planner (`hop-locality.py`: `endpoint_not_local:<host>`) and in Bridgebuilder's locality filter. Under `local_voices` cheval itself plans around every chain hop that fails the rule (one stderr line `locality: local_voices refuses hosted hop <provider>:<model> (fallback of <alias>)`; a chain with no local hop refuses the call with MODELINV `failure_class: locality_refused`), the loader refuses a `dispatch_group: local` model whose `fallback_chain` reaches a hosted hop, and Bridgebuilder walks a local voice's `fallback_chain` the same way; under `hosted` a local model may still fall back to a hosted one. A `localhost` endpoint is resolved and checked at request time (every address loopback, a resolver failure refuses); IP literals are never resolved.
 
-cycle-129 (FR-7) — **open-weight and local voices**: a local OpenAI-compatible server is declared as a provider (`type: openai_compat`, `keyless: true`, `allow_insecure_endpoint: "<host>"` where the host is a loopback or RFC1918 IP literal or `localhost`; Example 4 in `.loa.config.yaml.example`). The endpoint rule lives once in `.claude/scripts/lib/endpoint-validator.py` and is used by the cheval loader (`loa_cheval/config/endpoint_policy.py`), the bash wrapper and `model-health-probe.sh --provider <name>`, which probes a configured provider's `/models` with no credential when keyless; at request time a local hop runs with no proxy, no redirects and the declared path prefix. cheval refuses an `http`, loopback or private endpoint without the opt-in at load, for every provider. On the chat-completions path a `structured_json` entry sends `response_format` json_schema and `schema_enforced` is derived from the body sent (one retry without the schema on a server 400 that names it); `reasoning_content`, `reasoning` deltas and a leading `<think>` block go to `thinking` (`thinking_stripped`); an over-window prompt is refused by name. **Advisory voices**: `flatline_protocol.code_review.advisory_voices` and `security_audit.advisory_voices` run beside the counted voices under `advisory_timeout_seconds`; their findings appear only under `advisory_voices[].findings` with `duplicate_of` links and never touch the verdict, the counts or the cost totals — promotion to a counted role needs `hounfour.advisory_promotion`. The budget gate prices each planned voice from the catalog (`loa_cheval.metering.pricing --alias … --json`), whose entries now carry `open_weight`, `price_source` and `price_date`. **Bridgebuilder** reads `hounfour.providers`, `hounfour.locality` and `bridgebuilder.exit_on_degraded` from trusted configuration only (locally the working tree; on a pull request the `BRIDGEBUILDER_TRUSTED_CONFIG` repository variable, else the base branch's config, never the head), prints `completed/planned` voices and exits 3 on a DEGRADED consensus (`0` restores the old exit; `entry.sh`'s dependency preflight exits 4).
+cycle-129 (FR-7) — **open-weight and local voices**: a local OpenAI-compatible server is declared as a provider (`type: openai_compat`, `keyless: true`, `allow_insecure_endpoint: "<host>"` where the host is a loopback or RFC1918 IP literal or `localhost`; Example 4 in `.loa.config.yaml.example`). The endpoint rule lives once in `.claude/scripts/lib/endpoint-validator.py` and is used by the cheval loader (`loa_cheval/config/endpoint_policy.py`), the bash wrapper and `model-health-probe.sh --provider <name>`, which probes a configured provider's `/models` with no credential when keyless; at request time a local hop runs with no proxy, no redirects and the declared path prefix. cheval refuses an `http`, loopback or private endpoint without the opt-in at load, for every provider. On the chat-completions path a `structured_json` entry sends `response_format` json_schema and `schema_enforced` is derived from the body sent (one retry without the schema on a server 400 that names it); `reasoning_content`, `reasoning` deltas and a leading `<think>` block go to `thinking` (`thinking_stripped`); an over-window prompt is refused by name. **Advisory voices**: `flatline_protocol.code_review.advisory_voices` and `security_audit.advisory_voices` run beside the counted voices under `advisory_timeout_seconds`; their findings appear only under `advisory_voices[].findings` with `duplicate_of` links and never touch the verdict, the counts or the cost totals — promotion to a counted role needs `hounfour.advisory_promotion`. The budget gate prices each planned voice from the catalog (`loa_cheval.metering.pricing --alias … --json`), whose entries now carry `open_weight`, `price_source` and `price_date`. **Bridgebuilder** reads `hounfour.providers`, `hounfour.locality` and `bridgebuilder.exit_on_degraded` from trusted configuration only (locally the working tree; on a pull request the `BRIDGEBUILDER_TRUSTED_CONFIG` repository variable, else the base branch's config, never the head), prints `completed/planned` voices and exits 3 on a DEGRADED consensus (`0` restores the old exit; `entry.sh`'s dependency preflight exits 4). cheval reads the checkout's configuration for the dispatch, so a pull request whose head changes `hounfour.providers`, `hounfour.aliases`, `hounfour.locality` or the secret allowlist is refused by name before any voice is planned (`trusted config drift refused: <keys> differ between the PR head and <source>`, exit 5): merge the base branch into the head or set `BRIDGEBUILDER_TRUSTED_CONFIG`.
 
 ### Verification (cycle-107 sprint-1 + cycle-109 sprint-2/3 cumulative)
 
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
~~~~

## I14 — kf — 2026-10-15

- reference: KF-037
- files: .claude/defaults/model-config.yaml

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

## I15 — fix-commit — 2026-10-18

- reference: 76ba937e696a
- files: tests/unit/cost-report.bats

Summary:

fix(cycle-130): CI and Bridgebuilder round on PR #1283 — the grader tests resolve bats and python3 from the environment (BB HIGH), CR-7's stale codex hop literal (CI red since the Sprint 258 repoint), the RAB-1 comment (BB LOW) evals/tests/ablation-grade.bats: BATS_BIN is LOA_EVAL_BATS_BIN, else the first PATH bats outside bats-core's libexec/ (inside a bats run PATH carries the libexec entry poi…

Evidence:

~~~~diff
commit 76ba937e696aece2f91825520230f360563f7191
Date: 2026-10-19T00:07:49+11:00

fix(cycle-130): CI and Bridgebuilder round on PR #1283 — the grader tests resolve bats and python3 from the environment (BB HIGH), CR-7's stale codex hop literal (CI red since the Sprint 258 repoint), the RAB-1 comment (BB LOW)

evals/tests/ablation-grade.bats: BATS_BIN is LOA_EVAL_BATS_BIN, else the first PATH bats outside bats-core's libexec/ (inside a bats run PATH carries the libexec entry point, which must not be used as the grading bats), else the operator's checkout; the python3 wrapper execs the PATH python3 (actions/setup-python on CI) instead of /usr/bin/python3; the bats symlink is made only when the binary exists. tests/unit/cost-report.bats CR-7: resolved_model gpt-6.1-sol — Sprint 258 (05442536) repointed codex-headless's cli_model (KF-044) and moved the Python pricing-ladder test with it, but not this bats literal, so Shell Tests have been red on the branch since 2026-10-16 and the eval-harness CI step never ran. evals/tests/run-ablation.bats RAB-1: the stale "BARE stays 70 min" comment now states the DEC-0580 per-task bounds rule the assertion encodes.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/tests/unit/cost-report.bats b/tests/unit/cost-report.bats
index 673e6fac..35fd79c4 100644
--- a/tests/unit/cost-report.bats
+++ b/tests/unit/cost-report.bats
@@ -163,7 +163,7 @@ ROWS
   [ "$status" -eq 0 ]
   [ "$(wc -l < "$RP")" -eq 5 ]
   [ "$(stat -c %i "$RP")" = "$inode_before" ]   # rewritten in place under the writer's lock (audit F-1)
-  grep '"u1"' "$RP" | jq -e '.pricing_source == "config" and .pricing_resolution == "hop" and .resolved_model == "gpt-5.5" and .cost_estimated == true and .cost_micro_usd > 0 and .repriced_from == {"pricing_source":"unknown","cost_micro_usd":0} and (.repriced_at|test("^2026")) and .request_id == "u1" and .tokens_in == 1000' >/dev/null
+  grep '"u1"' "$RP" | jq -e '.pricing_source == "config" and .pricing_resolution == "hop" and .resolved_model == "gpt-6.1-sol" and .cost_estimated == true and .cost_micro_usd > 0 and .repriced_from == {"pricing_source":"unknown","cost_micro_usd":0} and (.repriced_at|test("^2026")) and .request_id == "u1" and .tokens_in == 1000' >/dev/null
   grep '"u2"' "$RP" | jq -e '.pricing_source == "config" and .cost_micro_usd > 0' >/dev/null
   [ "$(sed -n '3p' "$RP")" = "$l3" ]; [ "$(sed -n '4p' "$RP")" = "$l4" ]; [ "$(sed -n '5p' "$RP")" = "$l5" ]
   backup=$(ls "$RP.pre-reprice-"* | head -1); [ -n "$backup" ]
~~~~
