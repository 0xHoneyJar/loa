# Hunks — pr-11

The later fix changed 18 region(s) in 6 of the change's 65 file(s). Line numbers are head-side (the code under review). Each entry shows up to 12 head lines before and after the region; `>` marks a head line the fix changed.

## H01 — .claude/adapters/cheval.py — insertion after head line 1992

Head context (head/.claude/adapters/cheval.py, lines 1981–2004):

~~~~text
  1981 |     _modelinv_emit_required = True
  1982 |     _result = None
  1983 |     _final_entry = None
  1984 |     # cycle-104 backward-compat: for single-entry chains (no fallback declared),
  1985 |     # `for-else` exhaustion should surface the ORIGINAL cycle-103 exit code
  1986 |     # (RETRIES_EXHAUSTED / RATE_LIMITED / PROVIDER_UNAVAILABLE) rather than the
  1987 |     # new CHAIN_EXHAUSTED — external consumers still grep for the legacy codes.
  1988 |     # Multi-entry chains use CHAIN_EXHAUSTED because the operator explicitly
  1989 |     # opted into a chain shape; the new signal is informative for them.
  1990 |     _last_walk_exit_code: int = EXIT_CODES["CHAIN_EXHAUSTED"]
  1991 |     _last_walk_exception: Optional[Exception] = None
  1992 |     _last_walk_extra: Dict[str, Any] = {}
  1993 | 
  1994 |     def _calibration_needed_exit(
  1995 |         _entry: Any, _entry_target: str, _exc: ChevalError, *, error_class: str,
  1996 |         observed: Optional[int], provider_limit: Optional[int], exit_code: int,
  1997 |     ) -> int:
  1998 |         """cycle-126 D-1.1b: the provider's own size verdict ends the call —
  1999 |         it is never walked (the next voice would get the same payload). The
  2000 |         observation is appended to `.run/ceiling-observed.json` (only the two
  2001 |         context classes lower the bound; a 429 while unverified is recorded
  2002 |         without lowering it), the envelope carries `calibration_needed`, and
  2003 |         the operator sees the probe command."""
  2004 |         nonlocal _last_walk_exit_code
~~~~

The change from head to the fix:

~~~~diff
@@ -1992,0 +1993 @@
+    _hop_unverified = False  # cycle-126 D-1.1b: THIS hop runs above its own probed bound (set per hop below)
~~~~

## H02 — .claude/adapters/cheval.py — insertion after head line 2004

Head context (head/.claude/adapters/cheval.py, lines 1993–2016):

~~~~text
  1993 | 
  1994 |     def _calibration_needed_exit(
  1995 |         _entry: Any, _entry_target: str, _exc: ChevalError, *, error_class: str,
  1996 |         observed: Optional[int], provider_limit: Optional[int], exit_code: int,
  1997 |     ) -> int:
  1998 |         """cycle-126 D-1.1b: the provider's own size verdict ends the call —
  1999 |         it is never walked (the next voice would get the same payload). The
  2000 |         observation is appended to `.run/ceiling-observed.json` (only the two
  2001 |         context classes lower the bound; a 429 while unverified is recorded
  2002 |         without lowering it), the envelope carries `calibration_needed`, and
  2003 |         the operator sees the probe command."""
  2004 |         nonlocal _last_walk_exit_code
  2005 |         _obs = int(observed) if isinstance(observed, int) and observed > 0 else int(_walk_estimate or 0)
  2006 |         try:
  2007 |             _ceiling_record_observed(
  2008 |                 provider=_entry.provider, model=_entry.model_id, observed_input_tokens=_obs,
  2009 |                 error_class=error_class, estimated_input_tokens=_walk_estimate, provider_limit=provider_limit,
  2010 |             )
  2011 |         except Exception as _rec_err:  # noqa: BLE001 — the record must never mask the typed exit
  2012 |             print(f"[preflight] observed-bound record failed: {type(_rec_err).__name__}", file=sys.stderr)
  2013 |         _calib = {
  2014 |             "provider": _entry.provider, "model": _entry.model_id, "observed_input_tokens": _obs,
  2015 |             "provider_limit": provider_limit, "error_class": error_class,
  2016 |             "calibrate": _PROBE_COMMAND.format(model=_entry.model_id), "store": _observed_store_path(),
~~~~

The change from head to the fix:

~~~~diff
@@ -2004,0 +2006,5 @@
+        # audit sprint-247: the provider's text is sanitised at the adapter already; pass it
+        # through the redaction helper again here (defence in depth) before it is recorded
+        # under `message_redacted` or printed.
+        from loa_cheval.redaction import sanitize_provider_error_message as _sanitize
+        _msg = _sanitize(str(_exc))
~~~~

## H03 — .claude/adapters/cheval.py — head line 2022

Head context (head/.claude/adapters/cheval.py, lines 2010–2034):

~~~~text
  2010 |             )
  2011 |         except Exception as _rec_err:  # noqa: BLE001 — the record must never mask the typed exit
  2012 |             print(f"[preflight] observed-bound record failed: {type(_rec_err).__name__}", file=sys.stderr)
  2013 |         _calib = {
  2014 |             "provider": _entry.provider, "model": _entry.model_id, "observed_input_tokens": _obs,
  2015 |             "provider_limit": provider_limit, "error_class": error_class,
  2016 |             "calibrate": _PROBE_COMMAND.format(model=_entry.model_id), "store": _observed_store_path(),
  2017 |         }
  2018 |         if isinstance(_modelinv_state.get("capability_evaluation"), dict):
  2019 |             _modelinv_state["capability_evaluation"]["calibration_needed"] = _calib
  2020 |         _modelinv_state["models_failed"].append({
  2021 |             "model": _entry_target, "provider": _entry.provider, "error_class": error_class,
> 2022 |             "message_redacted": str(_exc), "observed_input_tokens": _obs, "provider_limit": provider_limit,
  2023 |         })
  2024 |         _modelinv_state["operator_visible_warn"] = True
  2025 |         print(
  2026 |             f"[preflight] calibration_needed model={_entry_target} class={error_class} "
  2027 |             f"observed_input_tokens={_obs} — not walked (cycle-126 D-1.1b); run: {_calib['calibrate']}",
  2028 |             file=sys.stderr,
  2029 |         )
  2030 |         print(_error_json(
  2031 |             _exc.code,
  2032 |             f"{_exc} — not walked: the same payload would fail the next voice; calibrate: {_calib['calibrate']}",
  2033 |             retryable=False, calibration_needed=True, error_class=error_class,
  2034 |             observed_input_tokens=_obs, provider_limit=provider_limit,
~~~~

The change from head to the fix:

~~~~diff
@@ -2022 +2028 @@
-            "message_redacted": str(_exc), "observed_input_tokens": _obs, "provider_limit": provider_limit,
+            "message_redacted": _msg, "observed_input_tokens": _obs, "provider_limit": provider_limit,
~~~~

## H04 — .claude/adapters/cheval.py — head line 2032

Head context (head/.claude/adapters/cheval.py, lines 2020–2044):

~~~~text
  2020 |         _modelinv_state["models_failed"].append({
  2021 |             "model": _entry_target, "provider": _entry.provider, "error_class": error_class,
  2022 |             "message_redacted": str(_exc), "observed_input_tokens": _obs, "provider_limit": provider_limit,
  2023 |         })
  2024 |         _modelinv_state["operator_visible_warn"] = True
  2025 |         print(
  2026 |             f"[preflight] calibration_needed model={_entry_target} class={error_class} "
  2027 |             f"observed_input_tokens={_obs} — not walked (cycle-126 D-1.1b); run: {_calib['calibrate']}",
  2028 |             file=sys.stderr,
  2029 |         )
  2030 |         print(_error_json(
  2031 |             _exc.code,
> 2032 |             f"{_exc} — not walked: the same payload would fail the next voice; calibrate: {_calib['calibrate']}",
  2033 |             retryable=False, calibration_needed=True, error_class=error_class,
  2034 |             observed_input_tokens=_obs, provider_limit=provider_limit,
  2035 |         ), file=sys.stderr)
  2036 |         _last_walk_exit_code = exit_code
  2037 |         return exit_code
  2038 | 
  2039 |     try:
  2040 |         for _idx, _entry in enumerate(_chain.entries):
  2041 |             _entry_target = _entry.canonical
  2042 | 
  2043 |             # 1. Capability gate — skip-and-walk per cycle-104 §1.4.2 contract.
  2044 |             #    A request that needs `tools` against a chat-only headless
~~~~

The change from head to the fix:

~~~~diff
@@ -2032 +2038 @@
-            f"{_exc} — not walked: the same payload would fail the next voice; calibrate: {_calib['calibrate']}",
+            f"{_msg} — not walked: the same payload would fail the next voice; calibrate: {_calib['calibrate']}",
~~~~

## H05 — .claude/adapters/cheval.py — insertion after head line 2110

Head context (head/.claude/adapters/cheval.py, lines 2099–2122):

~~~~text
  2099 |                         ),
  2100 |                     })
  2101 |                     if _verbose:
  2102 |                         print(f"[cheval] skip {_entry_target} (i1: no room for the output floor)", file=sys.stderr)
  2103 |                     continue
  2104 |                 if _fit.shrunk_from is not None:
  2105 |                     _hop_budget = _fit.max_tokens
  2106 |                     if isinstance(_modelinv_state.get("capability_evaluation"), dict):
  2107 |                         _modelinv_state["capability_evaluation"]["max_tokens_shrunk"] = {
  2108 |                             "from": _fit.shrunk_from, "to": _fit.max_tokens, "hop": _entry_target,
  2109 |                         }
  2110 | 
  2111 |             if not os.environ.get("LOA_CHEVAL_DISABLE_INPUT_GATE"):
  2112 |                 _input_threshold = _lookup_max_input_tokens(
  2113 |                     _entry.provider, _entry.model_id, hounfour,
  2114 |                     cli_override=getattr(args, "max_input_tokens", None),
  2115 |                     max_tokens=_hop_budget,
  2116 |                 )
  2117 |                 if _input_threshold is not None:
  2118 |                     from loa_cheval.providers.base import estimate_tokens
  2119 |                     _estimated = estimate_tokens(messages)
  2120 |                     if _estimated > _input_threshold:
  2121 |                         _modelinv_state["models_failed"].append({
  2122 |                             "model": _entry_target,
~~~~

The change from head to the fix:

~~~~diff
@@ -2110,0 +2117,18 @@
+            # cycle-126 D-1.1b (review sprint-247 DISS-001): "above the probed
+            # bound" is a property of THIS hop's entry and budget, never
+            # inherited from the head — a fallback whose bound is calibrated
+            # (or larger) runs the same payload verified, so its 429 walks and
+            # its provider verdict is the catalog's error, not an unverified one.
+            _hop_unverified = False
+            if (
+                _ceiling_policy == "derived"
+                and any(k in _hop_entry for k in ("effective_input_ceiling", "probed_ceiling"))
+                and not os.environ.get("LOA_CHEVAL_DISABLE_INPUT_GATE")
+            ):
+                _hop_decision = _ceiling_input_bound(
+                    _hop_entry, max_tokens=_hop_budget,
+                    observed=_observed_for(_entry.provider, _entry.model_id), policy=_ceiling_policy,
+                )
+                if _hop_decision is not None and not _hop_decision.calibrated and _hop_decision.probed:
+                    _hop_unverified = (_walk_estimate or 0) > _hop_decision.probed
+
~~~~

## H06 — .claude/adapters/cheval.py — head line 2256

Head context (head/.claude/adapters/cheval.py, lines 2244–2268):

~~~~text
  2244 |                 })
  2245 |                 print(_error_json(_e.code, str(_e)), file=sys.stderr)
  2246 |                 return EXIT_CODES["BUDGET_EXCEEDED"]
  2247 |             except ProviderContextLimitError as _e:
  2248 |                 # cycle-126 D-1.1b: the PROVIDER refused the payload (HTTP 400
  2249 |                 # prompt-too-long class / 413) — after the retry layer's single
  2250 |                 # output-budget shrink. Not walked. Above the probed bound the
  2251 |                 # class is CEILING_UNVERIFIED_LIMIT; otherwise the catalog bound
  2252 |                 # itself was wrong (PROVIDER_CONTEXT_LIMIT). Either lowers the
  2253 |                 # bound for this entry until calibration.
  2254 |                 return _calibration_needed_exit(
  2255 |                     _entry, _entry_target, _e,
> 2256 |                     error_class=("CEILING_UNVERIFIED_LIMIT" if _ceiling_unverified else "PROVIDER_CONTEXT_LIMIT"),
  2257 |                     observed=_e.input_tokens, provider_limit=_e.limit,
  2258 |                     exit_code=EXIT_CODES["CONTEXT_TOO_LARGE"],
  2259 |                 )
  2260 |             except ContextTooLargeError as _e:
  2261 |                 # Walk to next entry — a different entry may have a different
  2262 |                 # max_input_tokens ceiling. (cheval's OWN estimate against the
  2263 |                 # hop's window — walkable, unlike the provider's verdict above.)
  2264 |                 _modelinv_state["models_failed"].append({
  2265 |                     "model": _entry_target,
  2266 |                     "provider": _entry.provider,
  2267 |                     "error_class": "ROUTING_MISS",
  2268 |                     "message_redacted": str(_e),
~~~~

The change from head to the fix:

~~~~diff
@@ -2256 +2280 @@
-                    error_class=("CEILING_UNVERIFIED_LIMIT" if _ceiling_unverified else "PROVIDER_CONTEXT_LIMIT"),
+                    error_class=("CEILING_UNVERIFIED_LIMIT" if _hop_unverified else "PROVIDER_CONTEXT_LIMIT"),
~~~~

## H07 — .claude/adapters/cheval.py — head line 2297

Head context (head/.claude/adapters/cheval.py, lines 2285–2309):

~~~~text
  2285 |                     "message_redacted": str(_e),
  2286 |                 })
  2287 |                 _last_walk_exit_code = EXIT_CODES["API_ERROR"]
  2288 |                 _last_walk_exception = _e
  2289 |                 if _verbose:
  2290 |                     print(
  2291 |                         f"[cheval] fallback {_entry_target} -> next "
  2292 |                         f"(empty_content)",
  2293 |                         file=sys.stderr,
  2294 |                     )
  2295 |                 continue
  2296 |             except RateLimitError as _e:
> 2297 |                 if _ceiling_unverified:
  2298 |                     # cycle-126 D-1.1b: a 429 on a request that proceeded above
  2299 |                     # the probed bound (the token-limit class) is not walked and
  2300 |                     # is recorded for calibration; the bound is NOT lowered from
  2301 |                     # a 429 (a request-rate limit must not poison it). The
  2302 |                     # transport layer already retried it with backoff.
  2303 |                     return _calibration_needed_exit(
  2304 |                         _entry, _entry_target, _e, error_class="RATE_LIMIT_UNVERIFIED",
  2305 |                         observed=None, provider_limit=None, exit_code=EXIT_CODES["RATE_LIMITED"],
  2306 |                     )
  2307 |                 _modelinv_state["models_failed"].append({
  2308 |                     "model": _entry_target,
  2309 |                     "provider": _entry.provider,
~~~~

The change from head to the fix:

~~~~diff
@@ -2297 +2321 @@
-                if _ceiling_unverified:
+                if _hop_unverified:
~~~~

## H08 — .claude/adapters/loa_cheval/metering/pricing.py — insertion after head line 111

Head context (head/.claude/adapters/loa_cheval/metering/pricing.py, lines 100–123):

~~~~text
   100 |     if product > MAX_SAFE_PRODUCT:
   101 |         raise ValueError(
   102 |             f"BUDGET_OVERFLOW: tokens({tokens}) * price({price_micro_per_million}) "
   103 |             f"= {product} exceeds MAX_SAFE_PRODUCT"
   104 |         )
   105 | 
   106 |     cost_micro = product // 1_000_000
   107 |     remainder_micro = product % 1_000_000
   108 | 
   109 |     return cost_micro, remainder_micro
   110 | 
   111 | 
   112 | def calculate_total_cost(
   113 |     input_tokens: int,
   114 |     output_tokens: int,
   115 |     reasoning_tokens: int,
   116 |     pricing: PricingEntry,
   117 |     cache_read_tokens: int = 0,
   118 |     cache_creation_tokens: int = 0,
   119 | ) -> CostBreakdown:
   120 |     """Calculate total cost for a completion in micro-USD.
   121 | 
   122 |     Handles three pricing modes:
   123 |     - "token": Standard per-token pricing (default)
~~~~

The change from head to the fix:

~~~~diff
@@ -111,0 +112,22 @@
+def _premium_cost_micro(tokens: int, price_micro_per_million: int, multiplier: float) -> tuple:
+    """cycle-126 FR-1.9 (review sprint-247): the long-context premium is applied
+    to the product BEFORE flooring — floor(tokens × rate × multiplier / 1e6) —
+    with the multiplier as an exact decimal (`Fraction(str(m))`), never to an
+    already-floored per-category cost. Returns (cost_micro, remainder_micro)
+    with the remainder scaled to the same 0..999,999 range as
+    `calculate_cost_micro`; the overflow guard is the same product check."""
+    from fractions import Fraction
+    product = tokens * price_micro_per_million
+    if product > MAX_SAFE_PRODUCT:
+        raise ValueError(
+            f"BUDGET_OVERFLOW: tokens({tokens}) * price({price_micro_per_million}) "
+            f"= {product} exceeds MAX_SAFE_PRODUCT"
+        )
+    frac = Fraction(str(multiplier))
+    num = product * frac.numerator
+    den = 1_000_000 * frac.denominator
+    cost_micro = num // den
+    remainder_micro = (num % den) * 1_000_000 // den
+    return cost_micro, remainder_micro
+
+
~~~~

## H09 — .claude/adapters/loa_cheval/metering/pricing.py — head line 165

Head context (head/.claude/adapters/loa_cheval/metering/pricing.py, lines 153–177):

~~~~text
   153 | 
   154 |     if pricing.cache_read_per_mtok and cache_read_tokens:
   155 |         cr_cost, cr_rem = calculate_cost_micro(cache_read_tokens, pricing.cache_read_per_mtok)
   156 |     else:
   157 |         cr_cost, cr_rem = 0, 0
   158 |     if pricing.cache_write_per_mtok and cache_creation_tokens:
   159 |         cw_cost, cw_rem = calculate_cost_micro(cache_creation_tokens, pricing.cache_write_per_mtok)
   160 |     else:
   161 |         cw_cost, cw_rem = 0, 0
   162 | 
   163 |     # cycle-126 FR-1.9: long-context premium — above the threshold the whole
   164 |     # request is billed at the multiplied rates (input-side: input + cache
>  165 |     # traffic; output-side: output + reasoning).
   166 |     long_context_applied = False
   167 |     threshold = pricing.long_context_threshold
   168 |     if threshold is not None and input_tokens > threshold:
   169 |         long_context_applied = True
   170 |         im, om = pricing.long_context_input_multiplier, pricing.long_context_output_multiplier
   171 |         inp_cost = int(inp_cost * im)
   172 |         cr_cost = int(cr_cost * im)
   173 |         cw_cost = int(cw_cost * im)
   174 |         out_cost = int(out_cost * om)
   175 |         reas_cost = int(reas_cost * om)
   176 | 
   177 |     token_total = inp_cost + out_cost + reas_cost + cr_cost + cw_cost
~~~~

The change from head to the fix:

~~~~diff
@@ -165 +187,3 @@
-    # traffic; output-side: output + reasoning).
+    # traffic; output-side: output + reasoning), each category recomputed from
+    # tokens × rate × multiplier before flooring (review sprint-247 DISS-001:
+    # multiplying the floored costs underbilled by the discarded remainders).
~~~~

## H10 — .claude/adapters/loa_cheval/metering/pricing.py — head lines 171–175

Head context (head/.claude/adapters/loa_cheval/metering/pricing.py, lines 159–187):

~~~~text
   159 |         cw_cost, cw_rem = calculate_cost_micro(cache_creation_tokens, pricing.cache_write_per_mtok)
   160 |     else:
   161 |         cw_cost, cw_rem = 0, 0
   162 | 
   163 |     # cycle-126 FR-1.9: long-context premium — above the threshold the whole
   164 |     # request is billed at the multiplied rates (input-side: input + cache
   165 |     # traffic; output-side: output + reasoning).
   166 |     long_context_applied = False
   167 |     threshold = pricing.long_context_threshold
   168 |     if threshold is not None and input_tokens > threshold:
   169 |         long_context_applied = True
   170 |         im, om = pricing.long_context_input_multiplier, pricing.long_context_output_multiplier
>  171 |         inp_cost = int(inp_cost * im)
>  172 |         cr_cost = int(cr_cost * im)
>  173 |         cw_cost = int(cw_cost * im)
>  174 |         out_cost = int(out_cost * om)
>  175 |         reas_cost = int(reas_cost * om)
   176 | 
   177 |     token_total = inp_cost + out_cost + reas_cost + cr_cost + cw_cost
   178 | 
   179 |     # Hybrid: add flat per-task cost on top of token cost
   180 |     if pricing.pricing_mode == "hybrid":
   181 |         token_total += pricing.per_task_micro_usd
   182 | 
   183 |     return CostBreakdown(
   184 |         input_cost_micro=inp_cost,
   185 |         output_cost_micro=out_cost,
   186 |         reasoning_cost_micro=reas_cost,
   187 |         total_cost_micro=token_total,
~~~~

The change from head to the fix:

~~~~diff
@@ -171,5 +195,8 @@
-        inp_cost = int(inp_cost * im)
-        cr_cost = int(cr_cost * im)
-        cw_cost = int(cw_cost * im)
-        out_cost = int(out_cost * om)
-        reas_cost = int(reas_cost * om)
+        inp_cost, inp_rem = _premium_cost_micro(input_tokens, pricing.input_per_mtok, im)
+        out_cost, out_rem = _premium_cost_micro(output_tokens, pricing.output_per_mtok, om)
+        if pricing.reasoning_per_mtok and reasoning_tokens:
+            reas_cost, reas_rem = _premium_cost_micro(reasoning_tokens, pricing.reasoning_per_mtok, om)
+        if pricing.cache_read_per_mtok and cache_read_tokens:
+            cr_cost, cr_rem = _premium_cost_micro(cache_read_tokens, pricing.cache_read_per_mtok, im)
+        if pricing.cache_write_per_mtok and cache_creation_tokens:
+            cw_cost, cw_rem = _premium_cost_micro(cache_creation_tokens, pricing.cache_write_per_mtok, im)
~~~~

## H11 — .claude/adapters/loa_cheval/metering/pricing.py — insertion after head line 290

Head context (head/.claude/adapters/loa_cheval/metering/pricing.py, lines 279–302):

~~~~text
   279 |     )
   280 | 
   281 | 
   282 | def _long_context_fields(block: Any) -> Dict[str, Any]:
   283 |     """cycle-126 FR-1.9: parse `pricing.long_context` (threshold + multipliers);
   284 |     a malformed or absent block means no premium tier."""
   285 |     if not isinstance(block, dict):
   286 |         return {}
   287 |     threshold = block.get("threshold_tokens")
   288 |     if isinstance(threshold, bool) or not isinstance(threshold, int) or threshold <= 0:
   289 |         return {}
   290 |     def _mult(value: Any) -> float:
   291 |         try:
   292 |             m = float(value)
   293 |         except (TypeError, ValueError):
   294 |             return 1.0
   295 |         return m if m > 0 else 1.0
   296 |     return {
   297 |         "long_context_threshold": threshold,
   298 |         "long_context_input_multiplier": _mult(block.get("input_multiplier", 1.0)),
   299 |         "long_context_output_multiplier": _mult(block.get("output_multiplier", 1.0)),
   300 |     }
   301 | 
   302 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -290,0 +318,6 @@
+        # review sprint-247 round 2: a non-finite value (`.inf`, `nan`, `1e309`)
+        # passed `> 0` and later crashed `Fraction(str(m))` in the cost path —
+        # finite and positive, or the multiplier is 1.0 (the contract).
+        import math
+        if isinstance(value, bool):
+            return 1.0
~~~~

## H12 — .claude/adapters/loa_cheval/metering/pricing.py — head line 295

Head context (head/.claude/adapters/loa_cheval/metering/pricing.py, lines 283–307):

~~~~text
   283 |     """cycle-126 FR-1.9: parse `pricing.long_context` (threshold + multipliers);
   284 |     a malformed or absent block means no premium tier."""
   285 |     if not isinstance(block, dict):
   286 |         return {}
   287 |     threshold = block.get("threshold_tokens")
   288 |     if isinstance(threshold, bool) or not isinstance(threshold, int) or threshold <= 0:
   289 |         return {}
   290 |     def _mult(value: Any) -> float:
   291 |         try:
   292 |             m = float(value)
   293 |         except (TypeError, ValueError):
   294 |             return 1.0
>  295 |         return m if m > 0 else 1.0
   296 |     return {
   297 |         "long_context_threshold": threshold,
   298 |         "long_context_input_multiplier": _mult(block.get("input_multiplier", 1.0)),
   299 |         "long_context_output_multiplier": _mult(block.get("output_multiplier", 1.0)),
   300 |     }
   301 | 
   302 | 
   303 | # cycle-125 FR-5 (SDD §1.6): the resolution ladder. Fleet ledgers carried
   304 | # 79 % `pricing_source: unknown` on the current path because the ids that
   305 | # actually get invoked are dated releases, aliases and CLI-hop names, none of
   306 | # which is a `providers.<p>.models` key.
   307 | _DATED_SUFFIX_RE = re.compile(r"^(?P<base>.+?)-\d{4}-\d{2}-\d{2}$")
~~~~

The change from head to the fix:

~~~~diff
@@ -295 +328 @@
-        return m if m > 0 else 1.0
+        return m if (math.isfinite(m) and m > 0) else 1.0
~~~~

## H13 — .claude/adapters/loa_cheval/routing/ceiling.py — insertion after head line 30

Head context (head/.claude/adapters/loa_cheval/routing/ceiling.py, lines 19–42):

~~~~text
    19 |             the self-correction) caps an uncalibrated bound at
    20 |             ``observed − 1`` until calibration;
    21 |         ``LOA_CHEVAL_MAX_INPUT_TOKENS`` lowers any bound (basis ``guard``);
    22 |         ``LOA_CHEVAL_LEGACY_CEILING=1`` → today's single literal, no I1.
    23 | 
    24 | Every basis is named in the decision so the envelope, the log line and the
    25 | tests can say why a request was allowed or refused. Entries without any
    26 | ceiling field (v2 shapes, CLI hops) have no bound here (``None``).
    27 | """
    28 | from __future__ import annotations
    29 | 
    30 | import datetime as _dt
    31 | import json
    32 | import os
    33 | import re
    34 | import tempfile
    35 | from dataclasses import dataclass, replace
    36 | from typing import Any, Callable, Dict, List, Optional
    37 | 
    38 | FLOOR_MAX_TOKENS = 4_096
    39 | _TRUTHY = ("1", "true", "yes", "on")
    40 | 
    41 | 
    42 | @dataclass(frozen=True)
~~~~

The change from head to the fix:

~~~~diff
@@ -30,0 +31 @@
+import fcntl
~~~~

## H14 — .claude/adapters/loa_cheval/routing/ceiling.py — insertion after head line 278

Head context (head/.claude/adapters/loa_cheval/routing/ceiling.py, lines 267–290):

~~~~text
   267 |     model: str,
   268 |     observed_input_tokens: int,
   269 |     error_class: str,
   270 |     estimated_input_tokens: Optional[int] = None,
   271 |     provider_limit: Optional[int] = None,
   272 |     path: Optional[str] = None,
   273 | ) -> Dict[str, Any]:
   274 |     """Append one observation atomically (write-to-temp + ``os.replace``)
   275 |     and return the row. The store is append-only history; ``observed_for``
   276 |     reduces it. The parent directory is created (``.run/`` may not exist on a
   277 |     fresh mount)."""
   278 |     path = path or observed_store_path()
   279 |     data = load_observed(path)
   280 |     row = {
   281 |         "provider": provider,
   282 |         "model": model,
   283 |         "observed_input_tokens": int(observed_input_tokens),
   284 |         "estimated_input_tokens": estimated_input_tokens,
   285 |         "provider_limit": provider_limit,
   286 |         "error_class": error_class,
   287 |         "ts": _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
   288 |         "calibrate": PROBE_COMMAND.format(model=model),
   289 |     }
   290 |     data.setdefault("entries", []).append(row)
~~~~

The change from head to the fix:

~~~~diff
@@ -278,0 +280,24 @@
+    directory = os.path.dirname(os.path.abspath(path)) or "."
+    os.makedirs(directory, exist_ok=True)
+    # Review sprint-247 DISS-001: the read → append → replace cycle is held
+    # under an interprocess lock on a sibling lock file, so two chevals that
+    # hit a provider limit at once cannot each load the same old store and
+    # have the later replace discard the earlier row. The temp + os.replace
+    # still makes every write atomic for readers, which take no lock.
+    lock_path = path + ".lock"
+    # O_NOFOLLOW: a symlink planted at the lock path is refused, never followed
+    # (the repo's atomic-write symlink defence; the caller fails soft).
+    lock_fd = os.open(lock_path, os.O_RDWR | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0), 0o644)
+    try:
+        fcntl.flock(lock_fd, fcntl.LOCK_EX)
+        return _record_observed_locked(path, directory, provider, model, observed_input_tokens,
+                                       error_class, estimated_input_tokens, provider_limit)
+    finally:
+        try:
+            fcntl.flock(lock_fd, fcntl.LOCK_UN)
+        finally:
+            os.close(lock_fd)
+
+
+def _record_observed_locked(path, directory, provider, model, observed_input_tokens,
+                            error_class, estimated_input_tokens, provider_limit) -> Dict[str, Any]:
~~~~

## H15 — .claude/adapters/loa_cheval/routing/ceiling.py — head lines 292–293

Head context (head/.claude/adapters/loa_cheval/routing/ceiling.py, lines 280–305):

~~~~text
   280 |     row = {
   281 |         "provider": provider,
   282 |         "model": model,
   283 |         "observed_input_tokens": int(observed_input_tokens),
   284 |         "estimated_input_tokens": estimated_input_tokens,
   285 |         "provider_limit": provider_limit,
   286 |         "error_class": error_class,
   287 |         "ts": _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
   288 |         "calibrate": PROBE_COMMAND.format(model=model),
   289 |     }
   290 |     data.setdefault("entries", []).append(row)
   291 |     data["version"] = 1
>  292 |     directory = os.path.dirname(os.path.abspath(path)) or "."
>  293 |     os.makedirs(directory, exist_ok=True)
   294 |     fd, tmp = tempfile.mkstemp(prefix=".ceiling-observed.", suffix=".tmp", dir=directory)
   295 |     try:
   296 |         with os.fdopen(fd, "w", encoding="utf-8") as fh:
   297 |             json.dump(data, fh, indent=2, sort_keys=True)
   298 |             fh.write("\n")
   299 |         os.replace(tmp, path)
   300 |     except BaseException:
   301 |         try:
   302 |             os.unlink(tmp)
   303 |         except OSError:
   304 |             pass
   305 |         raise
~~~~

The change from head to the fix:

~~~~diff
@@ -292,2 +316,0 @@
-    directory = os.path.dirname(os.path.abspath(path)) or "."
-    os.makedirs(directory, exist_ok=True)
~~~~

## H16 — .claude/adapters/tests/test_ceiling_e2e.py — insertion after head line 267

Head context (head/.claude/adapters/tests/test_ceiling_e2e.py, lines 256–267):

~~~~text
   256 |     assert code == cheval.EXIT_CODES["SUCCESS"] and len(dispatched) == 2 and _classes(cap) == ["PROVIDER_OUTAGE"]
   257 | 
   258 | 
   259 | def test_170k_on_a_200k_entry_shrinks_the_output_budget_instead_of_failing(capsys):
   260 |     code, dispatched, cap = _run(_prompt_of_tokens(170_000), config=_config(head=_entry(context_window=200_000)))
   261 |     err = capsys.readouterr().err
   262 |     assert code == cheval.EXIT_CODES["SUCCESS"], err
   263 |     # the prompt calibrates to ≤ 170K tokens, so the room is 30K plus the calibration slack
   264 |     assert len(dispatched) == 1 and 30_000 <= dispatched[0].max_tokens <= 31_000
   265 |     shrunk = _cap(cap)["max_tokens_shrunk"]
   266 |     assert shrunk["from"] == 64_000 and shrunk["to"] == dispatched[0].max_tokens
   267 |     assert "[preflight] max_tokens shrunk 64000" in err
~~~~

The change from head to the fix:

~~~~diff
@@ -267,0 +268,41 @@
+
+
+def test_unverified_status_is_per_hop_not_inherited_from_the_head(monkeypatch):
+    """Review DISS-001: the head runs above its probed bound under the opt-in; it fails for a
+    walkable reason; the fallback is CALIBRATED at 900K (so the same payload is verified there).
+    An ordinary 429 on the fallback must walk / end as PROVIDER_OUTAGE — never as
+    RATE_LIMIT_UNVERIFIED, and never write a calibration record."""
+    monkeypatch.setenv("LOA_CHEVAL_UNCALIBRATED_CEILING", "derived")
+    cal = {"source": "empirical_probe", "calibrated_at": "2026-09-25T00:00:00Z", "stale_after_days": 90}
+    cfg = _config(head=_entry(chain=["anthropic:claude-opus-4-8"]))
+    cfg["providers"]["anthropic"]["models"]["claude-opus-4-8"] = _entry(ceiling=900_000, cal=cal)
+    from loa_cheval.types import ProviderUnavailableError
+    code, dispatched, cap = _run(SIX, config=cfg, errors=[ProviderUnavailableError("anthropic", "503"), RateLimitError("anthropic")])
+    assert len(dispatched) == 2, "the fallback hop is tried"
+    classes = _classes(cap)
+    assert "RATE_LIMIT_UNVERIFIED" not in classes and classes.count("PROVIDER_OUTAGE") == 2, classes
+    assert "calibration_needed" not in _cap(cap)
+    assert code == cheval.EXIT_CODES["CHAIN_EXHAUSTED"]
+    assert len(load_observed(observed_store_path())["entries"]) == 0
+    # the head's own envelope flag still says the head ran unverified
+    assert _cap(cap)["ceiling_unverified"] is True
+    # and a provider verdict on the CALIBRATED fallback is classed as the catalog's error, not unverified
+    limit = ProviderContextLimitError("anthropic", "HTTP 400 context-limit: prompt is too long: 612000 tokens > 600000 maximum",
+                                      status=400, input_tokens=612_000, limit=600_000)
+    code, dispatched, cap = _run(SIX, config=cfg, errors=[ProviderUnavailableError("anthropic", "503"), limit])
+    assert _classes(cap) == ["PROVIDER_OUTAGE", "PROVIDER_CONTEXT_LIMIT"] and len(dispatched) == 2
+
+
+def test_calibration_exit_redacts_secret_shapes_in_the_recorded_message(capsys):
+    """Audit sprint-247 (rejected payload, chunk b): the provider verdict's text is passed through the
+    redaction helper before it lands in models_failed / stderr JSON — a secret-shaped fragment in a
+    provider error body never reaches the envelope or the operator log."""
+    leak = ProviderContextLimitError("anthropic", "HTTP 400 context-limit: prompt is too long (key REDACTED-TEST-SECRET echoed)",
+                                     status=400, input_tokens=150_000, limit=120_000)
+    code, dispatched, cap = _run(_prompt_of_tokens(150_000), errors=[leak])
+    err = capsys.readouterr().err
+    assert code == cheval.EXIT_CODES["CONTEXT_TOO_LARGE"]
+    recorded = [f for f in cap.get("models_failed", []) if f.get("error_class") == "PROVIDER_CONTEXT_LIMIT"][0]
+    assert "REDACTED-TEST-SECRET" not in recorded["message_redacted"]
+    assert "REDACTED-TEST-SECRET" not in err
+    assert "context-limit" in recorded["message_redacted"], "the useful part of the message survives"
~~~~

## H17 — .claude/adapters/tests/test_ceiling_policy.py — insertion after head line 272

Head context (head/.claude/adapters/tests/test_ceiling_policy.py, lines 261–272):

~~~~text
   261 | def test_gate_cli_override_observed_and_legacy(monkeypatch):
   262 |     assert gate(FIVE, estimate=GateEstimate(tokens=150_000), requested_max_tokens=64_000, cli_override=100_000).basis == "cli_override"
   263 |     v2 = gate(V2, estimate=GateEstimate(tokens=150_000), requested_max_tokens=4_096, cli_override=100_000)
   264 |     assert v2.action == "preempt" and v2.basis == "cli_override", "--max-input-tokens binds an entry without a catalog ceiling too"
   265 |     assert gate(V2, estimate=GateEstimate(tokens=150_000), requested_max_tokens=4_096).action == "dispatch"
   266 |     monkeypatch.setenv("LOA_CHEVAL_UNCALIBRATED_CEILING", "derived")
   267 |     out = gate(FIVE, estimate=GateEstimate(tokens=500_000, uncertainty="low"), requested_max_tokens=64_000, observed=412_000)
   268 |     assert out.action == "preempt" and out.basis == "observed" and out.bound == 411_999
   269 |     monkeypatch.setenv("LOA_CHEVAL_LEGACY_CEILING", "1")
   270 |     out = gate(TWO_HUNDRED, estimate=GateEstimate(tokens=170_000), requested_max_tokens=64_000, counter=lambda: 1)
   271 |     assert out.action == "dispatch" and out.shrunk_from is None and out.policy == "legacy" and out.estimate.method == "heuristic", \
   272 |         "legacy: no I1, no count, the literal"
~~~~

The change from head to the fix:

~~~~diff
@@ -272,0 +273,38 @@
+
+
+def test_record_observed_is_serialised_across_processes(tmp_path, monkeypatch):
+    """Review sprint-247 DISS-001 (chunk a): concurrent writers must not lose rows —
+    the read/append/replace cycle is held under an interprocess lock."""
+    import multiprocessing as mp
+    path = tmp_path / "ceiling-observed.json"
+    monkeypatch.setenv(OBSERVED_PATH_ENV, str(path))
+
+    ctx = mp.get_context("fork")
+    procs = [ctx.Process(target=_append_many, args=(str(path), w, 25)) for w in range(4)]
+    for pr in procs:
+        pr.start()
+    for pr in procs:
+        pr.join(60)
+    assert all(pr.exitcode == 0 for pr in procs), [pr.exitcode for pr in procs]
+    data = load_observed(str(path))
+    assert len(data["entries"]) == 100, len(data["entries"])
+    assert sorted(row["observed_input_tokens"] for row in data["entries"]) == sorted(1000 * w + i for w in range(4) for i in range(25))
+    assert not [p for p in tmp_path.iterdir() if p.suffix == ".tmp"], "no temp file left behind"
+
+
+def _append_many(path, worker, n):
+    for i in range(n):
+        record_observed(provider="anthropic", model="claude-opus-5", observed_input_tokens=1000 * worker + i,
+                        error_class="PROVIDER_CONTEXT_LIMIT", path=path)
+
+
+def test_record_observed_never_follows_a_planted_symlink_at_the_lock_path(tmp_path, monkeypatch):
+    """Audit hardening (atomic-write symlink defenses): the lock file is opened O_NOFOLLOW, so a
+    symlink planted at `<store>.lock` is refused (OSError) instead of being followed."""
+    path = tmp_path / "ceiling-observed.json"
+    target = tmp_path / "elsewhere.txt"
+    target.write_text("keep")
+    (tmp_path / "ceiling-observed.json.lock").symlink_to(target)
+    with pytest.raises(OSError):
+        record_observed(provider="anthropic", model="m", observed_input_tokens=1, error_class="PROVIDER_CONTEXT_LIMIT", path=str(path))
+    assert target.read_text() == "keep" and not path.exists()
~~~~

## H18 — .claude/adapters/tests/test_long_context_pricing.py — insertion after head line 66

Head context (head/.claude/adapters/tests/test_long_context_pricing.py, lines 55–66):

~~~~text
    55 |     assert c.input_cost_micro == 600_000 * 5 * 2
    56 |     assert c.output_cost_micro == int(10_000 * 25 * 1.5)
    57 |     assert c.total_cost_micro == c.input_cost_micro + c.output_cost_micro
    58 |     # exactly at the threshold is NOT above it
    59 |     assert calculate_total_cost(200_000, 1, 0, big).long_context_applied is False
    60 | 
    61 | 
    62 | def test_missing_multipliers_default_to_one():
    63 |     entry = PricingEntry(provider="p", model="m", input_per_mtok=1_000_000, output_per_mtok=1_000_000,
    64 |                          long_context_threshold=100)
    65 |     c = calculate_total_cost(1_000, 1_000, 0, entry)
    66 |     assert c.long_context_applied is True and c.total_cost_micro == 2_000
~~~~

The change from head to the fix:

~~~~diff
@@ -66,0 +67,31 @@
+
+
+def test_premium_is_applied_before_flooring_not_to_rounded_categories():
+    """Review sprint-247 DISS-001 (chunk c): floor(tokens × rate × multiplier / 1e6), never
+    floor(floor(tokens × rate / 1e6) × multiplier)."""
+    entry = PricingEntry(provider="p", model="m", input_per_mtok=1_250_000, output_per_mtok=1_250_000,
+                         long_context_threshold=1, long_context_input_multiplier=1.5, long_context_output_multiplier=1.5)
+    c = calculate_total_cost(3, 3, 0, entry)
+    assert c.long_context_applied is True
+    assert c.output_cost_micro == 5, "3 × 1.25 × 1.5 = 5.625 → 5 (the rounded-first path gives floor(3 × 1.5) = 4)"
+    assert c.input_cost_micro == 5 and c.total_cost_micro == 10
+    # remainders are kept for the premium path too (no silent loss)
+    assert c.remainder_input > 0 and c.remainder_output > 0
+    # multipliers are exact decimals, not binary floats: 0.1 × 10 tokens × 1e6 rate → 1 exactly
+    e2 = PricingEntry(provider="p", model="m", input_per_mtok=1_000_000, output_per_mtok=1_000_000,
+                      long_context_threshold=1, long_context_input_multiplier=1.1, long_context_output_multiplier=1.0)
+    assert calculate_total_cost(10, 0, 0, e2).input_cost_micro == 11
+
+
+def test_non_finite_or_absurd_multipliers_are_ignored_not_fatal():
+    """Review sprint-247 round 2 (chunk c): a catalog typo (`.inf`, `nan`, `1e309`, a negative
+    or zero value) must fall back to 1.0 per the parser's contract — never raise inside cost
+    calculation, never zero or explode a bill."""
+    for bad in (float("inf"), float("nan"), "1e309", "-2", 0, "abc", None):
+        cfg = {"providers": {"anthropic": {"models": {"m": {"pricing": {
+            "input_per_mtok": 1_000_000, "output_per_mtok": 1_000_000,
+            "long_context": {"threshold_tokens": 1, "input_multiplier": bad, "output_multiplier": bad}}}}}}}
+        entry = find_pricing("anthropic", "m", cfg)
+        assert entry.long_context_input_multiplier == 1.0 and entry.long_context_output_multiplier == 1.0, bad
+        c = calculate_total_cost(10, 10, 0, entry)
+        assert c.long_context_applied is True and c.total_cost_micro == 20, bad
~~~~
