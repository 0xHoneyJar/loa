# KF-017 / KF-018 / claude -p billing — implementation-ready designs

> **Date:** 2026-06-22 · **Status:** designs complete, adversarial-verify pending (rate-limited)
> Produced by the `kf017-kf018-billing-design` ultracode workflow (3 design agents). The 3
> adversarial-verify agents hit the session rate limit and must be re-run before the
> System-Zone cheval code changes (KF-017, KF-018) are implemented/merged. The KF-020
> billing entry (docs) and tracking are landed now; cheval code is held for the verify.

## KF-017 / issue #1071 — prefer-api fallback chain hard-aborts when a leading CLI leg raises INVALID_CONFIG (ConfigError), instead of walking to a valid HTTP leg. Design the safest fix that distinguishes RUNTIME auth-revocation (walkable) from STATIC misconfig (still hard-abort).

**Effort:** M

**Summary:** Verified the 3-hop chain exactly as grounded. The fix introduces a NEW walkable typed exception `AuthRevokedError(ChevalError)` with code `AUTH_REVOKED` (retryable, exit-code mapped to a walk-eligible class). All four `*_headless_adapter.py` files split their existing single auth branch into (a) RUNTIME revocation phrases → `AuthRevokedError` (server invalidated a previously-valid token: "invalidated", "token has been invalidated", "401 unauthorized", "session expired", "token expired", "permission_denied") vs (b) STATIC misconfig → existing `ConfigError`/INVALID_CONFIG (operator never logged in / no key: "not authenticated", "not logged in", "codex login", "auth.json", "settings.json", "set an auth", env-var names). cheval.py's chain-walk loop gains a new `except AuthRevokedError: ... continue` arm placed ABOVE the existing `except ChevalError: return` hard-abort, so a dead CLI leg walks to the next chain entry while a genuine ConfigError STILL hard-aborts (operator config errors are never silently masked — the #1095 safety constraint). `AuthRevokedError` is a direct `ChevalError` subclass (NOT a ProviderUnavailableError subclass), so it threads through retry.py via the existing `except ChevalError: raise` (line 453-455) unchanged — exactly the propagation path `EmptyContentError` already uses. No new EXIT_CODE number is consumed for the walk-continue path; the new code maps to exit 1 (walk-eligible family). Effort: M (1 type + 4 adapter splits + 1 cheval arm + tests; surgical, additive).


### Grounding

- Chain-walk loop hard-aborts on any ChevalError not caught by an earlier arm: `except ChevalError as _e: ... return EXIT_CODES.get(_e.code, 1)` is the catch-all below the walk-eligible arms (ContextTooLarge/EmptyContent/RateLimit/ProviderUnavailable/RetriesExhausted all `continue`). — `.claude/adapters/cheval.py:1869-1878`
- retry.py re-raises non-retryable typed errors immediately via `except ChevalError: raise`, placed AFTER the RateLimitError/ProviderUnavailableError/ConnectionLostError arms — so a standalone ChevalError subclass (not ProviderUnavailableError) propagates straight up to the cheval chain-walk loop. — `.claude/adapters/loa_cheval/providers/retry.py:453-455`
- codex classifies auth-shaped stderr as ConfigError/INVALID_CONFIG, conflating static misconfig ("not authenticated", "codex login", "auth.json") with runtime revocation ("unauthorized", which matches the KF-017 "401 Unauthorized: token invalidated" string). — `.claude/adapters/loa_cheval/providers/codex_headless_adapter.py:587-598`
- gemini, claude, cursor headless adapters all share the identical conflation: an auth branch that lumps "unauthorized" (runtime) together with static misconfig phrases and raises ConfigError. — `.claude/adapters/loa_cheval/providers/gemini_headless_adapter.py:474-488; .claude/adapters/loa_cheval/providers/claude_headless_adapter.py:561-573; .claude/adapters/loa_cheval/providers/cursor_headless_adapter.py:495-509`
- ConfigError and InvalidConfigError both carry code INVALID_CONFIG, retryable=False; EXIT_CODES maps INVALID_CONFIG->2. The walk-eligible families (RATE_LIMITED/PROVIDER_UNAVAILABLE/RETRIES_EXHAUSTED/API_ERROR) all map to exit 1. — `.claude/adapters/loa_cheval/types.py:306-311,323-327; .claude/adapters/cheval.py:91-114`
- EmptyContentError is a ChevalError subclass (retryable=True) NOT caught by any retry.py arm, so it propagates via `except ChevalError: raise` and is caught by cheval.py `except _EmptyContentError: ... continue` (line 1787) — the exact walkable-disposition pattern the new auth-revocation error must replicate. — `.claude/adapters/loa_cheval/routing/types.py:220-257; .claude/adapters/cheval.py:1787-1803`
- prefer-api ordering returns http+cli (HTTP first), confirming the resolver intends HTTP-before-CLI; KF-017 documents the observed dispatch was nonetheless LED BY codex-headless and its INVALID_CONFIG hard-aborted before the working gpt-5.5 HTTP leg was tried. — `.claude/adapters/loa_cheval/routing/chain_resolver.py:298-301; grimoires/loa/known-failures.md KF-017 "Compounding routing/resilience defect (filed as #1071)"`
- Adapter wiring ConfigError at _get_adapter_for_entry is intentionally surfaced (return), NOT walked — this is the precedent that genuine config errors hard-abort, which the fix must preserve for STATIC misconfig. — `.claude/adapters/cheval.py:1670-1685`

### Design

EXACT CODE SHAPE (4 edit sites + tests):

(1) NEW EXCEPTION — `.claude/adapters/loa_cheval/types.py`, insert immediately AFTER `class ConfigError` (after line 311):
```python
class AuthRevokedError(ChevalError):
    \"\"\"Runtime auth-credential revocation on a CLI/subscription leg.

    Distinct from ConfigError (INVALID_CONFIG / static misconfig). A token
    that WAS valid and is now server-side-invalidated (KF-017: codex
    \"401 Unauthorized: token invalidated\", expired session) makes THIS leg
    unusable but says nothing about the operator's other legs. Classified
    retryable=True and code AUTH_REVOKED so the cheval chain-walk loop walks
    to the next entry (e.g. a valid HTTP leg) rather than hard-aborting the
    whole dispatch. NOT a ProviderUnavailableError subclass: it must reach
    cheval.py via retry.py's `except ChevalError: raise`, like EmptyContentError.
    \"\"\"

    def __init__(self, provider: str, message: str):
        super().__init__(
            \"AUTH_REVOKED\",
            f\"auth credential revoked for {provider}: {message}\",
            retryable=True,
            context={\"provider\": provider},
        )
        self.provider = provider
```

(2) EXIT_CODES — `.claude/adapters/cheval.py`, in the dict at line 91, add after `\"CONNECTION_LOST\": 1,` (line 97):
```python
    \"AUTH_REVOKED\": 1,  # KF-017/#1071: runtime token revocation — walk-eligible
```
(Maps to exit 1, the walk-eligible family. No new exit *number* is consumed; AUTH_REVOKED reuses 1 like API_ERROR/RATE_LIMITED. This is the single-entry backward-compat surface value.)

(3) CHAIN-WALK ARM — `.claude/adapters/cheval.py`, INSERT a new arm BETWEEN the `except RetriesExhaustedError` arm (ends line 1868 with its `continue`) and the catch-all `except ChevalError as _e:` (line 1869). It must import AuthRevokedError at the top of cmd_invoke's import block (alongside the EmptyContentError import near line 1160) OR reference via the module-level types import. New arm:
```python
            except AuthRevokedError as _e:
                # KF-017/#1071: a leg's credential was server-side revoked
                # (was valid, now invalidated). The leg is unusable NOW but
                # the operator's other legs (e.g. a valid HTTP key) may work.
                # Walk to the next chain entry rather than hard-aborting.
                # STATIC misconfig (ConfigError/INVALID_CONFIG) still falls
                # through to the hard-abort arm below — operator config errors
                # are NEVER silently masked (#1095 safety constraint).
                _modelinv_state[\"models_failed\"].append({
                    \"model\": _entry_target,
                    \"provider\": _entry.provider,
                    \"error_class\": \"AUTH_REVOKED\",
                    \"message_redacted\": str(_e),
                })
                _last_walk_exit_code = EXIT_CODES[\"AUTH_REVOKED\"]
                _last_walk_exception = _e
                if _verbose:
                    print(
                        f\"[cheval] fallback {_entry_target} -> next \"
                        f\"(auth_revoked)\",
                        file=sys.stderr,
                    )
                continue
```
Placement is load-bearing: Python evaluates except arms top-down; AuthRevokedError MUST precede `except ChevalError` (its base) or it is shadowed. The existing `except ChevalError: ... return` (1869-1878) is UNCHANGED and remains the hard-abort for ConfigError/INVALID_CONFIG static misconfig — the safety guarantee.

(4) ADAPTER CLASSIFICATION SPLIT — for EACH of the 4 headless adapters, split the single auth branch into runtime-revocation-first (AuthRevokedError) then static-misconfig (ConfigError). Runtime phrases (was-valid-now-dead): `invalidated`, `has been invalidated`, `token expired`, `session expired`, `401`, `unauthorized` (HTTP 401 from server = revocation, not a never-logged-in shape), `permission_denied` (gemini/grpc revocation). Static phrases keep ConfigError: `not authenticated`, `not logged in`, `codex login`/`/login`/`cursor-agent login`, `auth.json`/`settings.json`, `set an auth`, `please log in`, `press any key to sign in`, the env-var names. Add `AuthRevokedError` to each adapter's `from loa_cheval.types import (...)` block.

  4a) codex `.claude/adapters/loa_cheval/providers/codex_headless_adapter.py:587-598` — REPLACE the single `if (... \"unauthorized\" ...): raise ConfigError(...)` with:
```python
        # Runtime revocation (was valid, server-invalidated) → walkable.
        if (
            \"invalidated\" in stderr_lower
            or \"token has been invalidated\" in stderr_lower
            or \"401\" in stderr
            or (\"unauthorized\" in stderr_lower and \"not authenticated\" not in stderr_lower)
            or \"session expired\" in stderr_lower
            or \"token expired\" in stderr_lower
        ):
            raise AuthRevokedError(
                self.provider,
                f\"codex token revoked/expired — re-auth with `codex login`. \"
                f\"(stderr: {safe_stderr[:300]})\",
            )
        # Static misconfig (never authenticated) → hard-abort (operator config).
        if (
            \"not authenticated\" in stderr_lower
            or \"auth.json\" in stderr_lower
            or \"codex login\" in stderr_lower
        ):
            raise ConfigError(
                f\"codex CLI not authenticated. Run: codex login. \"
                f\"(Auth file: {_CODEX_AUTH_FILE}; stderr: {safe_stderr[:300]})\"
            )
```
  Note: `\"unauthorized\" and not \"not authenticated\"` guard prevents double-matching when codex emits both; revocation check runs first.

  4b) gemini `gemini_headless_adapter.py:474-488` — split the auth branch: move `\"unauthorized\"`, `\"permission_denied\"`, and add `\"401\"`/`\"invalidated\"`/`\"token expired\"` into an AuthRevokedError branch placed FIRST; keep `\"auth method\"`/`\"set an auth\"`/`\"settings.json\"`/`\"gemini_api_key\"`/`\"google_genai_use\"` in the ConfigError branch.

  4c) claude `claude_headless_adapter.py:561-573` — AuthRevokedError branch first for `\"unauthorized\"`/`\"401\"`/`\"invalidated\"`/`\"token expired\"`/`\"session expired\"`; ConfigError branch keeps `\"not logged in\"`/`\"/login\"`/`\"authentication\"`/`\"credential\"`.

  4d) cursor `cursor_headless_adapter.py:495-509` — AuthRevokedError branch first for `\"unauthorized\"`/`\"401\"`/`\"invalidated\"`/`\"session expired\"`; ConfigError branch keeps `\"not logged in\"`/`\"press any key to sign in\"`/`\"please log in\"`.

retry.py: NO CHANGE. AuthRevokedError (ChevalError, not ProviderUnavailableError) falls to `except ChevalError: raise` (453-455) and propagates to cheval — identical to EmptyContentError. Verified: arms above it (RateLimitError/ProviderUnavailableError/ConnectionLostError) don't match a direct ChevalError subclass.

chain_resolver.py: NO CHANGE. The resolver already orders http+cli for prefer-api; the bug is purely the walk-vs-abort disposition, not ordering.

### Test plan

- test_chain_walk_audit_envelope.py::test_auth_revoked_leg_walks_to_http_fallback — REGRESSION test for #1071. Use _multi_entry_config() but make the FIRST entry the CLI leg and second the HTTP leg (or keep order and have primary raise AuthRevokedError). _retry_side raises AuthRevokedError(provider='openai', message='401 Unauthorized: token invalidated') on call 1, returns fallback_result on call 2. Assert: exit_code==SUCCESS, calls['n']==2 (walked, did NOT abort), models_failed[0]['error_class']=='AUTH_REVOKED', models_succeeded==[fallback], final_model_id==fallback. This is the exact KF-017 scenario: dead CLI leg → valid HTTP leg.
- test_chain_walk_audit_envelope.py::test_static_misconfig_still_hard_aborts — SAFETY test (#1095 constraint). _retry_side raises ConfigError('codex CLI not authenticated. Run: codex login.') on call 1. Assert: exit_code==EXIT_CODES['INVALID_CONFIG'] (2, NOT success, NOT chain-exhausted), calls['n']==1 (did NOT walk to entry 2 — operator config error surfaced immediately), stderr JSON code=='INVALID_CONFIG'. Pins that genuine misconfig is never silently masked.
- test_chain_walk_audit_envelope.py::test_auth_revoked_all_legs_exhausts — every leg raises AuthRevokedError → chain exhausts cleanly (multi-entry → CHAIN_EXHAUSTED exit 12), models_failed has both entries with error_class AUTH_REVOKED, no models_succeeded. Confirms walk semantics terminate correctly when no leg recovers.
- test_codex_headless_adapter.py::test_runtime_token_revocation_raises_auth_revoked — adapter unit test. mock_run.return_value=_fail_proc(1, '401 Unauthorized: Your authentication token has been invalidated'); pytest.raises(AuthRevokedError); assert 'codex login' in message (still actionable). The literal KF-017 codex stderr string.
- test_codex_headless_adapter.py::test_static_not_authenticated_still_raises_config_error — keep/adapt existing test_auth_failure_raises_config_error: _fail_proc(1, 'Error: not authenticated. Run codex login.') → pytest.raises(ConfigError). Pins the split didn't regress static misconfig classification (no 'unauthorized'/'401' in this string, so it must NOT become AuthRevokedError).
- test_gemini_headless_adapter.py / test_claude_headless_adapter.py / test_cursor_headless_adapter.py — one pair each: (a) revocation phrase ('unauthorized'/'401'/'permission_denied' for gemini) → AuthRevokedError; (b) static phrase ('set an auth'/'not logged in'/'press any key to sign in') → ConfigError. Mirrors the codex pair to prove uniform behavior across all 4 adapters.
- test_cheval_exception_scoping.py — add an assertion that AuthRevokedError is importable from loa_cheval.types, is a ChevalError subclass, is NOT a ProviderUnavailableError subclass (guards the retry.py propagation contract), and .retryable is True / .code=='AUTH_REVOKED'.

### Safety risks & guards

- Over-broad runtime classification could silently mask a genuine operator misconfig (the #1095 constraint). GUARD: the runtime branch matches ONLY revocation-shaped phrases (invalidated/401/session-expired/token-expired/permission_denied), and the codex `unauthorized` match is guarded with `and "not authenticated" not in stderr_lower`. The static-misconfig branch (not authenticated / not logged in / login-command / auth.json/settings.json / env-var names) keeps ConfigError → still hits cheval.py's UNCHANGED `except ChevalError: return` hard-abort at 1869. A never-logged-in operator still gets exit 2, surfaced immediately. The test_static_misconfig_still_hard_aborts + test_static_not_authenticated_still_raises_config_error tests pin this invariant.
- AuthRevokedError accidentally made a subclass of ProviderUnavailableError would change retry semantics (retry.py:407 would `break` per-provider into RetriesExhausted rather than letting it propagate). GUARD: it is a DIRECT ChevalError subclass; test_cheval_exception_scoping asserts `not issubclass(AuthRevokedError, ProviderUnavailableError)`.
- Except-arm ordering regression: if a future edit moves `except ChevalError` above `except AuthRevokedError`, the base shadows the subclass and the walk silently reverts to hard-abort. GUARD: the regression test test_auth_revoked_leg_walks_to_http_fallback fails loudly (exit != SUCCESS, calls['n']==1) if shadowing returns; comment in the arm flags the ordering dependency.
- A degraded/revoked leg walking to a fallback could mask a fleet-wide auth outage (all legs dead) as a quieter failure. GUARD: when ALL legs raise AuthRevokedError the chain still exhausts to CHAIN_EXHAUSTED (multi-entry) with every leg recorded AUTH_REVOKED in models_failed — operator-visible in MODELINV, not silently swallowed; test_auth_revoked_all_legs_exhausts pins it. The walk only succeeds when a genuinely-valid leg exists, which is the desired KF-017 behavior.
- Cross-company chain-walk is forbidden (chain_resolver enforces within-company at :270-279). This fix does NOT touch chain composition — AuthRevokedError walks only within the operator-declared within-company chain, so no cross-company substitution is introduced.

### Open questions

- Should AuthRevokedError additionally trip the (provider, auth_type) circuit breaker via retry.py's _record_failure? Currently it propagates through `except ChevalError: raise` WITHOUT recording a failure (retry.py's record-failure happens only in the RateLimit/ProviderUnavailable/ConnectionLost/generic arms). Recording the failure would open the CLI bucket's breaker after repeated revocations (helpful), but the chain-walk already routes around it per-invocation. Recommend deferring breaker-integration to keep this fix surgical; note it as a follow-up if revocation-storms are observed.
- Phrase-list completeness: the runtime-vs-static phrase split is heuristic (string matching on CLI stderr, same brittleness the adapters already carry). The codex KF-017 string ('token has been invalidated', '401 Unauthorized') is covered with certainty; gemini/claude/cursor revocation strings are inferred from their existing 'unauthorized' handling and not yet observed live in KF-017. Acceptable because the fail-safe direction is correct: an unrecognized auth phrase still falls through to ProviderUnavailableError (already walkable) or ConfigError (hard-abort, safe). Worth a follow-up to capture real revocation stderr from the other three CLIs.
- Should the single-entry backward-compat path surface AUTH_REVOKED (exit 1) or keep the legacy INVALID_CONFIG (exit 2) for a lone revoked CLI leg with no fallback? The design surfaces AUTH_REVOKED→exit 1 (walk-eligible family) via _last_walk_exit_code, which is a behavior change for single-entry chains (was exit 2). This is arguably more correct (it's a transient revocation, not a config error) but external consumers grepping exit 2 for 'misconfig' would see exit 1. Confirm with operator whether single-entry revocation should keep exit 2 for consumer compat.

---

## KF-018 fix: real-auth (tier-death) health probe for headless CLI adapters

**Effort:** M

**Summary:** The KF-018 grounding holds with one correction about WHERE the fix belongs. The adapter `health_check()` methods (claude/codex/gemini/cursor) all run `<bin> --version` (binary-presence only) and have ZERO programmatic callers — they are effectively dead code. The real operator-facing readiness probe is `doctor.py` (`loa-substrate-doctor.sh`), which ALREADY does real-inference "no-op-dispatch" (`claude -p ping`, `gemini -p ping`) for claude+gemini and `codex login status` for codex. So real inference already happens — the two actual KF-018 gaps are: (1) doctor's `_classify()` deliberately refuses to read stderr/stdout, so a tier-dead gemini (IneligibleTierError, which only fires on real inference) collapses to `auth_state: "unknown"` indistinguishable from a transient provider error — there is NO tier-death verdict; (2) doctor has NO cache/rate-limit, so every invocation burns a fresh real inference (acceptable today only because it is operator-invoked, not on the hot path — but the moment anything calls it programmatically it would burn quota per call). cursor and grok are also absent from doctor's `_PROBE_TABLE` (grok is HTTP-only `grok_adapter`, not headless, so out of scope; cursor IS headless and should be added). DESIGN: keep the `--version` fast-path untouched in adapter health_check (binary-missing still fails fast & free via `shutil.which`), and land the tier-death detection + cache/rate-limit in doctor.py because that is the single existing real-inference probe with an established schema, hint taxonomy, and hardened subprocess capture. Recommended scope: a tier-death classifier branch + a `.run/`-backed verdict cache, plus adding cursor to the probe table. This is best done in doctor.py (NOT the base adapter class and NOT per-adapter health_check), because doctor.py already owns the real-inference probe path, the byte-capped subprocess capture, the verdict schema, and the fixed-template hint discipline; duplicating that into 4 adapter health_check methods would re-introduce 4 copies of the subprocess-hardening + caching logic.


### Grounding

- All 4 headless adapter health_check() run only `<bin> --version` with timeout=5.0 and return proc.returncode==0 — binary-presence probe, no inference — `.claude/adapters/loa_cheval/providers/gemini_headless_adapter.py:239-254 (and claude:247-262, codex:289-299, cursor:273-288)`
- health_check() has zero programmatic callers in the adapter package — only a passing mention in bedrock_adapter comment; the abstract contract is declared but nothing consumes the boolean — `.claude/adapters/loa_cheval/providers/base.py:859-861 (abstract def) + grep of `health_check\b` callers (only bedrock_adapter.py:672 comment)`
- doctor.py ALREADY runs real-inference no-op-dispatch: `claude -p ping --max-budget-usd 0.001 ...` and `gemini -p ping -o text --skip-trust`, plus `codex login status` (status-command) — `.claude/adapters/loa_cheval/doctor.py:65-88 (_PROBE_TABLE)`
- doctor._classify() maps no-op-dispatch non-zero exit to auth_state='unknown' and EXPLICITLY does not interpolate stdout/stderr ('without interpolation we cannot distinguish') — so tier-death is invisible — `.claude/adapters/loa_cheval/doctor.py:294-313 + the comment at 296-298`
- doctor has no caching: aggregate() re-runs every probe on each call; auth_state taxonomy is ok|needs-login|unreachable|unknown only — `.claude/adapters/loa_cheval/doctor.py:346-372 (aggregate) + ProbeResult:107-112`
- No adapter or doctor has any tier-death / IneligibleTier / 'Code Assist' / deprecation branch — grep across all provider .py finds none; gemini _raise_for_error only classifies rate-limit/auth/generic — `.claude/adapters/loa_cheval/providers/gemini_headless_adapter.py:443-494`
- MEMORY confirms KF-018: gemini-headless `--version` PASSES while the auth tier is dead; IneligibleTierError fires only on real inference; real-auth probe deferred to bd-yohy — `/home/merlin/.claude/projects/-home-merlin-Documents-thj-code-loa/memory/MEMORY.md:8 (#1089 nuance) + bd-yohy (br show: 'flatline-readiness: probe headless-CLI health')`
- .run/ is the State zone (read/write) and already holds per-provider state files (circuit-breaker-*.json) — appropriate home for a probe-verdict cache — `CLAUDE.loa.md Three-Zone Model + ls .run/ shows circuit-breaker-google-headless.json etc.`
- doctor.py uses a hardened byte-capped streaming subprocess capture with process-group SIGKILL on timeout (C2/C6) — the pattern that would have to be duplicated if the probe lived in per-adapter health_check — `.claude/adapters/loa_cheval/doctor.py:118-186 (_capture_with_byte_cap), 192-268 (_run_probe)`
- doctor probe table has only claude/codex/gemini — no cursor (headless, should be added) and no grok (grok is HTTP grok_adapter, not headless — correctly out of scope) — `.claude/adapters/loa_cheval/doctor.py:65-88 + providers/ listing has no grok_headless_adapter.py`
- doctor tests pin _classify cells incl. test_unknown_via_noop_dispatch asserting auth_state=='unknown' for non-zero no-op-dispatch — these must be extended, not broken — `.claude/adapters/tests/test_doctor.py:78-81`
- KF-018 is referenced by #1089 deprecation doc but is NOT yet a numbered entry in known-failures.md (last formal entry is KF-017) — `grimoires/loa/known-failures.md:1048 (KF-017 is last); grep KF-018 finds no header`

### Design

PLACEMENT: doctor.py (NOT base adapter, NOT per-adapter health_check). Keep all 4 health_check() `--version` methods UNCHANGED — they remain the free binary-presence fast-path. Land the tier-death real-auth probe in the existing doctor.py no-op-dispatch path.

(1) NEW verdict taxonomy — extend ProbeResult.auth_state. At doctor.py:109 add a new state value `"tier-dead"` to the docstring enum and at the verdict/render layer. ProbeResult stays frozen dataclass (no new fields needed if we add a LOCAL diagnostic-classification step before the schema boundary).

(2) TIER-DEATH CLASSIFIER — new fn `_classify_tier_death(stdout_bytes, stderr_bytes) -> bool` near doctor.py:271. _run_probe currently discards stderr_bytes after _capture_with_byte_cap (doctor.py:247) — change the call site to pass BOTH stdout AND stderr into a new local classification step. Per-vendor markers (lowercased substring match, never interpolated into hint):
  - gemini: "ineligibletier", "code assist", "free tier", "is not eligible", "gemini for google" (the IneligibleTierError surface)
  - claude: not a tier model today; reserve the branch but leave markers empty (Claude-Max death surfaces as auth/quota, already covered)
  - codex: status-command path — `codex login status` exit-0 means logged in; tier-death would surface on real dispatch. For codex keep status-command (cheap) but note codex tier issues are out-of-scope for the ping (no real inference for codex).
  - cursor (new): "resource_exhausted", "free tier without composer" (mirrors cursor_headless_adapter.py:480-481 existing comment).
Modify _classify (doctor.py:271-313): for method=="no-op-dispatch" with returncode!=0, FIRST check `_classify_tier_death(...)`; if true → auth_state="tier-dead" with a NEW fixed-template hint; else fall through to the existing "unknown". This keeps SKP-003 (no user-content in hint) — the markers are matched LOCALLY, only the fixed template is emitted. Add hint templates at doctor.py:316 `_HINT_TEMPLATES`: `("no-op-dispatch","tier-dead"): "{cli} authenticated but subscription tier is dead/deprecated (real-inference probe rejected); migrate provider or switch to api-only mode"`.

(3) CACHE / RATE-LIMIT — new module-level cache backed by State zone. Add `_PROBE_CACHE_PATH = Path(os.environ.get("LOA_RUN_DIR", ".run")) / "substrate-probe-cache.json"` and `_PROBE_CACHE_TTL_S = int(os.environ.get("LOA_PROBE_CACHE_TTL_S", "900"))` (15 min default) at doctor.py:90. Shape: `{"<cli>": {"auth_state": "...", "ts_epoch": <float>, "hint": "...", "probe_method": "..."}}`. In `aggregate()` (doctor.py:356-360) loop: before calling `_run_probe`, read cache; if `now - ts_epoch < TTL` reuse the cached ProbeResult (rebuild from the dict). Only the no-op-dispatch (real-inference) methods are cached — `unreachable`/`binary-not-on-path` (free `shutil.which`) results are NOT cached (binary-missing must always fail fast & free; a fresh binary install must be seen immediately). After a fresh _run_probe of a no-op-dispatch CLI, write its result back to the cache (atomic write: tmp+os.replace, matching the circuit-breaker write pattern). Add a `--no-cache` / `--force` CLI flag (doctor.py:392 _cli_main) so operators can force a fresh probe; and `--cache-ttl N`. Cache write is best-effort (wrap in try/except OSError → log + proceed uncached) so a read-only .run never breaks the probe.

(4) ADD CURSOR to _PROBE_TABLE (doctor.py:65): `"cursor": {"provider":"cursor","cli_name":"cursor-headless","method":"no-op-dispatch","cmd":["cursor-agent","-p","ping","--output-format","json","--mode","plan","--sandbox","enabled","--trust"]}` — mirrors cursor_headless_adapter._build_command:303-315 (read-only, sandboxed). Add "cursor" to the --provider choices at doctor.py:403.

(5) KEEP IT CHEAP: ping prompt stays the 1-token "ping"; claude already caps `--max-budget-usd 0.001`; gemini/cursor use the smallest plan-mode read-only invocation; TTL cache means at most 1 real inference per CLI per 15 min; status-command (codex) is free. Binary-missing short-circuits before any subprocess (doctor.py:212-220), preserving the free fast-path.

(6) KF DOC: append a formal `## KF-018: headless CLI --version / status probe cannot detect subscription tier-death` entry to grimoires/loa/known-failures.md after KF-017 (line 1048), with the Symptom (gemini --version + `codex login status` pass while tier dead), Recurrence, and the Attempts row pointing at this fix's PR/sprint. Update bd-yohy to in-progress/closed on landing.

### Test plan

- test_classify_tier_dead_gemini (test_doctor.py): `_classify` (via the modified path that receives stderr) returns auth_state=='tier-dead' when gemini stderr/stdout contains 'IneligibleTierError' / 'Gemini Code Assist' / 'free tier' — proves a dead tier is now detected (the KF-018 regression target)
- test_classify_tier_dead_cursor (test_doctor.py): cursor no-op-dispatch with 'resource_exhausted' in probe text → auth_state=='tier-dead' (not 'unknown')
- test_healthy_tier_passes (test_doctor.py): no-op-dispatch returncode==0 still → auth_state=='ok' (no tier-dead false-positive); and a non-zero exit WITHOUT any tier marker still → 'unknown' (existing test_unknown_via_noop_dispatch must keep passing, only narrowed)
- test_cache_prevents_repeat_probe (test_doctor.py): monkeypatch `_run_probe` to count calls; first aggregate() invokes it, second aggregate() within TTL reuses cache and does NOT call _run_probe again; assert call_count==1
- test_cache_expires_after_ttl (test_doctor.py): with a tiny/zeroed TTL (or injected `now`), the second aggregate() DOES re-probe — guards against a stale 'ok' masking a tier that died mid-window
- test_binary_absent_fails_fast_and_is_not_cached (test_doctor.py): shutil.which→None yields auth_state=='unreachable' with NO subprocess spawn (free fast-path preserved) and is NOT written to the verdict cache (a later install is seen immediately)
- test_version_fastpath_unchanged (existing adapter tests): adapter health_check() still returns False on missing binary and True on `--version` exit-0 — assert no behavioral change to the free binary-presence path
- test_cache_write_failure_is_nonfatal (test_doctor.py): point LOA_RUN_DIR at a read-only path; aggregate() still returns a live verdict (cache write swallowed, probe runs uncached)
- test_hint_has_no_user_content_for_tier_dead (test_doctor.py): tier-dead hint is the fixed template only — attacker-controlled stderr markers never appear in ProbeResult.hint (SKP-003 invariant preserved), mirroring existing test_no_stdout_in_hint_for_known_state
- test_cursor_added_to_probe_table (test_doctor.py): aggregate(provider_filter='cursor') produces exactly one cursor-headless probe

### Safety risks & guards

- Tier-death false-positive could blackhole a healthy voice: if a tier-dead marker substring ('free tier', 'resource_exhausted') appears in a legitimate model RESPONSE, doctor might mislabel a working CLI as tier-dead. GUARD: classification runs ONLY on the no-op-dispatch ping path where the response is a fixed 'ping' reply (no user content) AND only on returncode!=0 (a returncode==0 round-trip is always 'ok' first, never reclassified) — exactly mirroring cursor_headless_adapter's _transport_probe_text discipline (cursor:452-458) where the model's own result is excluded from the classifier.
- Cache staleness could mask a tier that dies mid-window: a cached 'ok' verdict could hide a tier that died after the cache was written. GUARD: TTL default 15 min (short), `--no-cache`/`--force` operator override, and the cache is advisory for the readiness REPORT only — it never gates live dispatch (live dispatch already self-heals via the circuit-breaker + chain-walk + voice-drop in retry.py). doctor is a pre-flight advisory, not a routing gate, so a stale verdict cannot mis-route a real request.
- SKP-003 hint-injection regression: feeding stderr into the new classifier risks leaking attacker/provider content into the schema-boundary hint. GUARD: stderr is consumed LOCALLY for substring matching only; ProbeResult.hint remains a fixed-template lookup (doctor.py:331-340) — the existing test_no_stdout_in_hint_for_known_state pattern is extended to the tier-dead state.
- Cache file in .run/ written non-atomically could corrupt under concurrent doctor invocations. GUARD: atomic tmp+os.replace write (same pattern as circuit-breaker-*.json), best-effort try/except so a write failure degrades to uncached rather than crashing; reads tolerate malformed JSON (json.JSONDecodeError → treat as cache-miss).
- Adding cursor real-inference probe must not execute tools: GUARD: cursor probe cmd reuses the adapter's hardened argv (--mode plan --sandbox enabled --trust, NEVER -f/--yolo) per cursor_headless_adapter:303-315 — pure inference, OS-sandboxed, matching the existing security contract verified in #966.

### Open questions

- Should adapter health_check() be left as-is (dead but harmless --version probe) or deprecated/redirected to call doctor's probe? Recommendation: leave as-is this sprint (surgical scope; it is the free fast-path and has no callers to break), note the redundancy separately.
- Exact gemini IneligibleTierError surface string is inferred from #1089/KF-018 notes, not from a live capture (the tier is dead so we cannot reproduce locally). The marker list ('ineligibletier','code assist','free tier','is not eligible') should be confirmed against the gemini-cli error source or a captured stderr before landing; designed as an easily-extended tuple so additional markers are a one-line add.
- Should codex (status-command) gain a real-inference tier probe too? Codex tier-death would not surface from `codex login status` (auth-only). Out of scope for the ping-based design unless operator wants a codex `codex exec` micro-probe — adds cost; recommend deferring.
- Does any programmatic consumer (cron/scheduled-cycle, post-pr-validation, flatline readiness) want to CALL doctor.aggregate() now? If yes, the cache becomes load-bearing for cost; if it stays purely operator-CLI-invoked, the cache is a nice-to-have. bd-yohy frames it as 'flatline-readiness' which implies a future programmatic caller — the cache should land regardless.
- Should the formal KF-018 known-failures.md entry land in this same PR or separately? Recommend same PR so the fix and its operational log are atomic.

---

## claude -p billing exposure: loa's claude_headless_adapter routes Claude voices through `claude -p` on subscription OAuth, which Anthropic's Apr-4-2026 policy meters as per-token "extra usage" — not flat-rate plan quota. Design as a tracked bug + KF-020.

**Effort:** S

**Summary:** CONFIRMED and material. loa's `claude_headless_adapter.py` constructs almost exactly the command in the canonical reproduction of upstream claude-code #43333: it strips ANTHROPIC_API_KEY (`build_headless_subprocess_env`, base.py:533) and runs `claude -p <prompt> --output-format json --permission-mode plan --no-session-persistence --tools "" --model fable` (claude_headless_adapter.py:285-300). Upstream #43333 reproduction is `env -u ANTHROPIC_API_KEY claude -p --output-format json "say hi"` — issue is CLOSED, sibling #37686 reports $1,800+ in 2 days. Anthropic's policy (Apr-4-2026, multiple corroborating sources) moved third-party-harness OAuth usage — including programmatic/headless — into a separate per-token "extra usage" pool; usage NO LONGER draws on flat-rate Pro/Max limits. The reinstatement (VentureBeat) re-permitted third-party tools but the "catch" is exactly this metered billing.\n\nEXPOSURE SURFACE in loa is large and SILENT: `claude-headless` is the within-company chain TERMINAL for EVERY Anthropic model (model-config.yaml: claude-opus-4-8:386-388, 4-7:411-413, 4-6:457-458, fable-5:360-362, sonnet:482-484, haiku:521) AND the council/BB "claude voice". `cli_model: fable` (line 554) pins the TOP tier (most expensive per-token). So any time the Anthropic HTTP API path fails or is unavailable (the exact KF-017 condition: ANTHROPIC_API_KEY valid but $0 credits → chain-walk to claude-headless), loa silently spends real money per-token at Opus/Fable rates against the operator's "extra usage" balance, while the adapter docstring and config comments STILL assume flat-rate Max economics ("quota-cost only", claude_headless_adapter.py:30; "informational on Max", :443; "No pricing entry — CLI uses operator's Claude Code subscription", model-config.yaml:540).\n\nDETECTABILITY: GOOD NEWS — the signal already exists and is already captured. `claude -p --output-format json` returns `total_cost_usd` and per-model `modelUsage[].costUSD`; the adapter already parses `total_cost_usd` into `metadata` (claude_headless_adapter.py:482-484). Under the new policy that value is the actual extra-usage charge (it was always "API-equivalent cost", now it's the real bill). Separately, because `claude-headless` has NO `pricing` block (model-config.yaml:540), the metering rollup ALREADY flags every such call as `unpriced_calls` / "$0" blind-spot (rollup.py:25-27, :143). So loa can both (a) read the per-call dollar cost the CLI reports and (b) already knows these calls are unpriced in its own ledger.\n\nHONEST FIRST MOVE: this is primarily MEASURE-then-MITIGATE, not a one-shot code fix. The right initial change is small and surfacing-only: (1) plumb `total_cost_usd` into the MODELINV/cost-ledger so headless spend stops being a $0 blind spot, and (2) add a loud operator-facing warning + a documented `headless_mode: api-only` posture for cost-sensitive operators. A hard "disable claude headless if metered" flag is tempting but the adapter cannot reliably tell metered-vs-covered a priori — only post-hoc via `total_cost_usd > 0` after the call. Plus KF-017 already documents `api-only` as the escape hatch and the legitimate cost-vs-resilience tradeoff. So: file the bug, ship the telemetry + warning + doc, and gate any auto-disable behind measured data.


### Grounding

- Adapter strips ANTHROPIC_API_KEY so claude -p uses OAuth subscription, not API mode — matching the exact upstream repro condition — `.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:161-164`
- build_headless_subprocess_env pops ANTHROPIC_API_KEY (and other auth vars) from the subprocess env by default — `.claude/adapters/loa_cheval/providers/base.py:496,533-534`
- Command is `claude -p <prompt> --output-format json --permission-mode plan --no-session-persistence --tools "" --model <cli_model>` — nearly identical to upstream #43333 repro — `.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:285-300`
- Docstring assumes flat-rate Max economics: system-prompt overhead is 'quota-cost only' on Max — `.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:28-30`
- total_cost_usd is documented as 'API-equivalent cost (informational on Max)' — premise invalidated by the new policy — `.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:443`
- Adapter already parses total_cost_usd from the JSON output into metadata (the detection signal exists) — `.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:482-484`
- claude-headless is the within-company fallback_chain TERMINAL for every Anthropic model (opus-4-8/4-7/4-6, fable-5, sonnet, haiku) — `.claude/defaults/model-config.yaml:360-362,386-388,411-413,457-458,482-484,521`
- claude-headless has NO pricing block — 'CLI uses operator's Claude Code subscription' — so every call is metered as $0 in loa's own ledger — `.claude/defaults/model-config.yaml:540`
- cli_model pinned to 'fable' — the TOP intelligence tier — applies to every claude-headless consumer (BB, council claude voice, chain-walk fallbacks) — `.claude/defaults/model-config.yaml:545-554`
- Metering rollup already flags pricing_source != config calls as unpriced ($0) blind-spots — the cost column UNDERSTATES — `.claude/adapters/loa_cheval/metering/rollup.py:25-27,143`
- api-only mode filters the chain to HTTP adapters only, excluding claude-headless (the existing escape hatch) — `.claude/adapters/loa_cheval/routing/chain_resolver.py:306-307`
- KF-017 already documents the exact trigger (ANTHROPIC_API_KEY valid but $0 credits → chain-walk reaches claude-headless) and notes api-only as remediation, including 'HTTP API is metered per-token vs the flat-rate CLI subscription — a cost posture choice' — `grimoires/loa/known-failures.md:1056,1061`
- Upstream anthropics/claude-code #43333: claude -p on active Max sub bills at per-token API rates despite OAuth even with ANTHROPIC_API_KEY unset; repro `env -u ANTHROPIC_API_KEY claude -p --output-format json`; status CLOSED; sibling #37686 reports $1,800+ in 2 days — `https://github.com/anthropics/claude-code/issues/43333`
- Anthropic Apr-4-2026 policy: third-party-harness OAuth usage moved to a separate per-token 'extra usage' pool, no longer drawing on flat-rate Pro/Team allowance; later reinstated 'with a catch' (the metered billing) — `https://fazm.ai/blog/anthropic-subscription-auth-warning-third-party-extra-usage ; https://venturebeat.com/technology/anthropic-reinstates-openclaw-and-third-party-agent-usage-on-claude-subscriptions-with-a-catch`
- KF schema header format: `## KF-{NNN}: title` + Status/Feature/Symptom/First observed/Recurrence count/Current workaround/Upstream issue/Related + Attempts table + Reading guide; highest on-disk entry is KF-017 — `grimoires/loa/known-failures.md:19-42,1048`

### Design

No production code change is REQUIRED to ground/file this; the recommended deliverable is a small surfacing-only patch plus docs. Exact shapes:

1) KF entry (STATE zone, no gate): append `## KF-020: claude -p subscription OAuth metered as per-token 'extra usage', not flat-rate Max quota` to `grimoires/loa/known-failures.md` after KF-017 (line 1064), AND add an index row. NOTE id reconciliation in open_questions — on-disk highest is KF-017, prompt says KF-020. Header fields:
   - Status: OPEN (external-upstream; not loa-fixable, mitigation-only)
   - Feature: cheval claude-headless adapter (claude_headless_adapter.py) — within-company Anthropic chain terminal + council/BB claude voice
   - Symptom: claude -p invocations on a Max/Pro subscription are billed per-token as 'extra usage' (not against flat-rate plan limits) since Anthropic's 2026-04-04 policy; loa's adapter + config assume flat-rate economics, so chain-walk fallback to claude-headless silently spends real money at Fable/Opus per-token rates.
   - First observed: 2026-06-22 (investigation; grounded against upstream #43333 + #37686 + Anthropic policy sources)
   - Recurrence count: 0 (documented pre-emptively; no in-loa cost incident yet observed)
   - Current workaround: set `hounfour.cheval.headless.mode: api-only` (or export `LOA_HEADLESS_MODE=api-only`) for cost-sensitive operators — excludes claude-headless from the chain (chain_resolver.py:306-307). For resilience-first operators who keep claude-headless, monitor `metadata.total_cost_usd` per call.
   - Upstream issue: anthropics/claude-code#43333 (CLOSED) + #37686; loa tracker = the new beads/GH bug below.
   - Related: KF-017 (same chain-walk-to-headless trigger; api-only remediation), KF-013 (headless OAuth env hygiene).
   - Attempts table seed row: 2026-06-22 | grounded adapter + consumers + verified upstream policy | DOCUMENTED-NOT-LOA-FIXABLE (external billing); mitigation = telemetry + warning + api-only doc | this investigation; #43333; claude_headless_adapter.py:482-484.
   - Reading guide: if an operator reports surprise Anthropic charges while on a Max/Pro plan and loa is configured with the default chains, suspect claude-headless chain-walk. Do NOT treat the subscription as flat-rate. Read `metadata.total_cost_usd` from MODELINV; route cost-sensitive operators to api-only.

2) Telemetry plumb (SMALL, App-adjacent cheval lib, requires /implement gate): the adapter already stores `metadata['total_cost_usd']` (claude_headless_adapter.py:482-484). Wire it into the cost-ledger/MODELINV emit so headless spend is no longer an `unpriced_calls` $0 blind spot (rollup.py:25-27). Minimal: ensure the ledger writer reads `result.metadata['total_cost_usd']` for headless adapters and records it as actual cost (pricing_source='cli_reported') instead of $0.

3) Operator warning (SMALL): in `_parse_json_output` (claude_headless_adapter.py:482-484), when `total_cost_usd` is present and > 0, `logger.warning` once-per-process that headless Claude spend is metered as extra-usage under Anthropic's 2026-04 policy and is NOT flat-rate — with the api-only pointer. Keep it a WARN, not an error (the call already succeeded; this is cost-posture surfacing).

4) Docs (STATE zone): update the adapter docstring lines 28-30 and 443, and model-config.yaml:540 comment, to replace 'quota-cost only on Max' / 'informational on Max' with the post-2026-04 reality + a pointer to KF-020. (Docstring edits to .claude/ are System-Zone — route through the normal cycle authorization, or land in the same /implement that does #2/#3.)

### Test plan

- test_headless_cost_recorded_not_zero (cheval metering): given a claude_headless CompletionResult whose metadata.total_cost_usd=0.12, the cost-ledger row records 0.12 with pricing_source='cli_reported', NOT an unpriced $0 row — asserts the blind-spot is closed (new test in tests for metering/rollup or ledger)
- test_headless_metered_warning_emitted (cheval providers): _parse_json_output with total_cost_usd>0 emits exactly one logger.warning containing 'extra usage' / 'api-only' and does NOT raise — asserts surfacing without breaking the success path (extend the existing claude_headless adapter test module)
- test_headless_no_cost_no_warning: total_cost_usd absent/None → no warning, no ledger cost row regression — guards against false alarms on older CLI output shapes
- test_api_only_excludes_claude_headless (chain_resolver): resolving an Anthropic alias under mode=api-only yields a chain with NO kind:cli claude-headless entry — pins the documented escape hatch (assert against _apply_mode_transform / chain_resolver.py:306-307)
- doc/lint check: known-failures.md KF-020 entry parses against the schema (Status/Feature/Symptom/First observed/Recurrence count/Current workaround/Upstream issue + Attempts table + Reading guide) and the Index table has a matching row

### Safety risks & guards

- Auto-disabling the claude headless voice when metered could break the Anthropic within-company resilience guarantee: claude-headless is the chain TERMINAL for every Anthropic model (model-config.yaml:386-388 etc). If a naive cost-guard removes it, an operator whose ANTHROPIC_API_KEY is exhausted (KF-017) loses the Anthropic voice entirely → multi-voice consensus silently drops to fewer voices (the exact KF-002/KF-015/KF-016 silent-quorum-degradation class). GUARD: do NOT auto-disable; keep claude-headless in the chain by default, surface cost via WARN + ledger, and make api-only an explicit operator opt-in (it already is). Any future auto-disable must emit a DEGRADED-voice envelope, never a silent clean verdict.
- Detection is post-hoc only: the adapter cannot know metered-vs-covered BEFORE the call — `total_cost_usd` is only in the response. A pre-call 'is this metered?' gate would be a guess and could wrongly block legitimate covered usage. GUARD: scope detection to post-hoc surfacing (ledger + WARN); never gate dispatch on an unverifiable pre-call prediction.
- Changing the cost-ledger to record cli_reported cost must not double-count: the HTTP AnthropicAdapter prices from config (pricing block) while headless would price from total_cost_usd. If a single logical call chain-walks HTTP→headless, ensure only the leg that actually ran (headless) records cost. GUARD: record cost on the successful leg only, keyed by the MODELINV per-leg record, not the alias.

### Open questions

- KF id reconciliation: the prompt says next id = KF-020 (operator memory references KF-018/KF-019), but the on-disk grimoires/loa/known-failures.md highest entry is KF-017 — KF-018 and KF-019 are NOT in the file body or index. Likely committed on another branch or planned but not landed. Filer must confirm the correct next id before appending (use KF-020 per instruction, but verify KF-018/KF-019 land first or renumber to KF-018).
- Does the installed claude CLI version on operators' machines still emit total_cost_usd under the new extra-usage billing, and does that value now equal the real extra-usage charge (vs the old 'API-equivalent' estimate)? Needs a live `claude -p --output-format json` probe on a current CLI + a Max account with extra-usage enabled to confirm the field is the authoritative bill before relying on it for the ledger.
- Is there a per-call field distinguishing 'covered by remaining plan headroom' vs 'extra usage' in the JSON (e.g. a billing_type/usage_pool field), or is total_cost_usd>0 the only available discriminator? If a discrete flag exists in newer CLI output it would be a cleaner signal than inferring from a non-zero cost. Needs a live probe / current `claude -p` schema check.
- Operator cost-posture default: should loa flip the shipped default to api-only for Anthropic chains (cost-safe) or keep prefer-api with claude-headless terminal (resilience-safe)? This is an operator policy decision, not a pure engineering call — recommend keeping current default + loud surfacing, but flag for operator sign-off.