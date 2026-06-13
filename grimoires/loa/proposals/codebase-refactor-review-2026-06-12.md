# Loa Codebase Refactor Review — 2026-06-12

**Method**: 15-agent parallel review (12 subsystem readers + 3 cross-cutting sweeps),
1.37M subagent tokens, every finding grounded in `file:line`. 119 raw findings;
this document keeps the high-leverage set, folding findings that multiple agents
surfaced independently (convergence = confidence).

**Scope discipline**: these are *refactors* (structure/debt), not features. None is a
live user-facing bug **except** the one already filed as **#1016** (chunked-path
MODELINV field-drop). Effort S/M/L/XL; risk = chance the refactor itself breaks
something.

**Convergence signal** (how many of the 15 agents independently raised it):
- Headless provider registry sync — **5 agents**
- `routing/chains.py` dead — **3 agents**
- Output-swallowing (`2>/dev/null || echo`) — **3 agents**
- `chunking/` package dead/dormant — **3 agents**

---

## Tier 1 — Single-source-of-truth consolidations (highest leverage)

### R1. Derive the headless-provider registries from one declarative table  ⟦M, low risk⟧
**Convergence: 5 agents** (cheval-core, cheval-providers, cheval-config-routing, cheval-periphery, xc-duplication).
Adding a headless provider type today requires hand-editing **3–4** out-of-band registries:
- `_ADAPTER_REGISTRY` — `.claude/adapters/loa_cheval/providers/__init__.py:28-37`
- `_HEADLESS_TYPE_INFERENCE` — `config/loader.py:433-437` (its own comment at `:424` says "Keys MUST match _ADAPTER_REGISTRY" — a MUST enforced only by prose)
- `_CLI_ADAPTER_BY_PROVIDER` — `cheval.py:204-208`
- `_PROBE_TABLE` — `doctor.py:65-88` (auth-probe specs)

**PR #966 (cursor-headless) shipped config-dead** by updating only `_ADAPTER_REGISTRY` — the documented proof of this failure class.
**Target shape**: each headless adapter class declares `provider_type`, `provider_family`, `dispatch_group`, `kind="cli"`, and a probe spec as class attributes; the other three maps become projections computed by iterating a single `HEADLESS_ADAPTERS` list. Adding a provider = one class edit.
**Cheap interim** (do first, ~30 min): `test_model_auth_metadata_validator.py:362` already asserts `_HEADLESS_TYPE_INFERENCE ⊆ _ADAPTER_REGISTRY`; add the missing assertion that `_CLI_ADAPTER_BY_PROVIDER` keys+values are registered types (the exact registry PR #966 missed). That converts the next #966 into a red test immediately, before the full refactor lands.

### R2. One model registry + pricing path, not parallel bash and Python  ⟦L, medium risk⟧
**Convergence: bash-orchestration, xc-duplication, cheval-periphery.** The same `model-config.yaml` is read by two codegen toolchains emitting overlapping registries — `gen-adapter-maps.sh:49` (bash `yq+jq` → `generated-model-maps.sh` MODEL_PROVIDERS/IDS/COST) and `gen-bb-registry.ts:5-9` (TS `yq` → `config.generated.ts`). Pricing is computed twice with **incompatible units**: YAML stores micro-USD/Mtok (`model-config.yaml:39`); Python keeps it integer (`metering/pricing.py:159-173`); bash converts to USD-per-1K via `awk` float (`gen-adapter-maps.sh:91`) — two rounding regimes over one source = silent cost-attribution divergence.
**Target shape**: consolidate codegen on the Python `loa_cheval/codegen` package (it already emits TS via Jinja2 with content-hash drift gates — the strong pattern); make the Python micro-USD integer path the canonical pricing source; bash cost lookups call a tiny `python3` shim instead of carrying COST_INPUT/COST_OUTPUT maps. **Gate behind R7** (legacy bash adapter removal) since that's what still consumes the bash maps.

### R3. Promote `_modelinv_state` to a typed dataclass; one envelope-emit site  ⟦M, low risk — fixes #1016⟧
**Convergence: cheval-core (2 findings).** Two MODELINV emit sites have **already diverged** (#1016): the chunked-path emit (`cheval.py:1568-1630`) omits advisor (v1.2) + auth-type (v1.4) fields the finally-block emit (`:2320-2353`) passes. Root cause: `_modelinv_state` is a stringly-typed dict (67 bracket accesses) feeding a 25-kwarg emitter (`modelinv.py:398-443`), so a new field has **four** touch points.
**Target shape**: `@dataclass ModelinvState` with `to_emit_kwargs()`; both emit sites call one `_emit_audit_envelope(state, ...)`. New fields get two touch points; the two sites become structurally incapable of drifting. Pin with a golden-envelope test before refactoring. **#1016 is filed; this refactor is its proper fix.**

---

## Tier 2 — Dead-code deletions (low risk, immediate clarity)

### R4. Delete `routing/chains.py` (316 LoC + 4 test files)  ⟦S–M, low risk⟧
**Convergence: 3 agents** (cheval-core, cheval-config-routing, xc-dead-code). Superseded by `chain_resolver.resolve` (the cycle-095 per-call walk, `cheval.py:1152-1174`). `walk_downgrade_chain`/`walk_fallback_chain`/`validate_chains` have **zero production callers** — only `routing/__init__.py` re-exports and test files. Re-home any still-relevant test assertions against `chain_resolver` first, then delete the module + drop the `__all__` entries.

### R5. Resolve the `chunking/` package fork (971 LoC + 1,516 LoC tests, unreachable)  ⟦M, low risk⟧
**Convergence: 3 agents** (cheval-periphery, xc-duplication, xc-dead-code) **+ a ledger correction**. The chunk branch is gated on `effective_input_ceiling` being a positive int (`cheval.py:502-505`), set only from `--max-input-tokens` (`:1462`) — which the sole production caller (`cheval-delegate.ts:142-159`) never passes, and `model-config.yaml` sets zero times. So `from loa_cheval.chunking...` at `cheval.py:1558` **never executes**. Worse: **KF-002 in `known-failures.md:228` certifies it "wired in production"** on the strength of a *source-string grep test* (`test_chunking_cheval_integration.py:94` asserts `"loa_cheval.chunking" in cheval.py`'s text), masking the dead branch and telling future agents not to re-triage the large-input class.
**Decision required (#937)**: (a) wire it — have a production caller pass a real `--max-input-tokens`, add a *behavioral* integration test that drives input past the ceiling; or (b) delete the package + 6 test files + the `cheval.py:1485-1700` branch and reopen KF-002 layer-1(a). Either way, replace the two grep "wiring check" tests and update the KF-002 attempts table. **Operator call.**

### R6. Sweep the small dead artifacts  ⟦S, low risk — batchable⟧
- `tier_groups.py` — `apply_tier_groups` never landed, module unexported (cheval-config-routing).
- `metering/rollup.py`, `rate_limiter.py`, `pre_call_atomic`, session-cap trio, `RemainderAccumulator` — zero production callers (cheval-periphery).
- `core/cross-scorer.ts` (183 ln) — exercised only by its own test (bridgebuilder-ts).
- `dx-utils.sh` error-registry half (8 of 18 functions) dead (bash-libs).
- `context-isolation-lib.sh.cycle-100-baseline` — committed byte-identical backup file; `.bak.cycle-NNN` sprawl (bash-libs, state-zone).
- `is_flatline_routing_enabled`/`HOUNFOUR_FLATLINE_ROUTING` — vestigial flag; cheval is the unconditional path per CLAUDE.loa.md (xc-pattern-drift).
- 9× `cycle099-*.yml` + `cycle-108-schema-guard` workflows still fire on path filters (xc-dead-code) — **verify each drift gate is duplicated elsewhere before removing** (medium risk; the codegen gates may be load-bearing).
- 3 unwired hook scripts: `bb-dist-check.sh`, `cycle-108-rollout-watch.sh`, `memory-writer.sh` (xc-dead-code, hooks).

---

## Tier 3 — Duplication extractions

### R7. Collapse the legacy bash model-adapter stack into a cheval shim  ⟦L, high risk⟧
`model-adapter.sh.legacy` (24KB) + `red-team-model-adapter.sh` (652 ln) reimplement the role→agent + model→provider routing that `loa_cheval/routing/resolver.py` owns; `model-adapter.sh:18` documents the legacy path as the **default**. ~50KB of duplicated routing/pricing bash. **High risk**: may be load-bearing offline/no-API-key. Gate deletion behind verification that all callers tolerate the cheval path; unblocks R2.

### R8. `HeadlessCLIAdapter` template-method base (3 adapters are ~75% clones)  ⟦L, medium risk⟧
**cheval-providers**: 1,563 lines where ~700 would do; `_build_prompt`/`health_check`/`_compute_timeout` are md5-identical across claude/codex/gemini modulo names; the `complete()` scaffolding repeats near-verbatim. PR #966's cursor adapter is a 4th 448-line clone. Extract a base driven by class attributes; subclasses keep only `_build_command`/`_parse_output`/`_classify_error` (~120 ln each). The 108 existing tests pin behavior — **do this before merging cursor-headless** so the 4th adapter lands at ~150 ln. Companion: collapse the 3 clone test suites into one parametrized suite (test-debt finding).

### R9. One secret-redaction canon; one config-getter; one logger  ⟦M–L, mixed⟧
- **Redaction** (bash-libs, xc-duplication): 5+ independent secret-shape implementations; AKIA alone has 3 different output sentinels, so a leak-scanner grepping one sentinel misses secrets redacted by another. Make `lib/log-redactor.py` canonical (it has the only cross-runtime parity test); others delegate via subprocess (the pattern `endpoint-validator.sh` already uses). One sentinel grammar `[REDACTED-<CLASS>]`.
- **Config reading** (xc-pattern-drift): 5 private `get_config_value`/`_config_get` helpers + 345 raw `yq eval` sites + 115 redundant `command -v yq` checks. Add `config_get`/`config_get_bool` to a sourced lib beside path-lib's getters.
- **Logging** (xc-pattern-drift): 183 per-file logger defs, two naming conventions, only 1 of 183 honors a log level. Add `log/log_info/log_warn/log_error/die` to a log-lib sourced from `bootstrap.sh`.

### R10. Split `base.py` (891 ln = 4 libraries) by consumer group  ⟦M, low risk⟧
HTTP transport, CLI-subprocess engine, env scrub, token estimation, and the ABC are one module; `audit/modelinv.py:44` even reaches into a providers-layer underscore-private (`_streaming_disabled`). Split into `providers/http_transport.py` + `providers/cli_subprocess.py`; base.py keeps the ABC. Pure file moves with re-exports for one release. Also: two parallel flock-semaphore implementations (`providers/concurrency.py` vs `loa_cheval/adapters/headless_concurrency.py`) — consolidate on the latter, retire the misnamed `loa_cheval/adapters/` pseudo-package.

---

## Tier 4 — Pattern-drift normalization (correctness-adjacent)

### R11. Guard the output-swallowing class structurally  ⟦L, medium risk — highest correctness payoff⟧
**Convergence: 3 agents** (state-zone, xc-duplication, xc-pattern-drift). 328 `jq ... 2>/dev/null || echo <default>` sites turn parse errors into clean defaults — **this is the literal mechanism behind KF-004 (recurrence ≥20) and KF-015**. The repo already forbids the shape for `git stash` (`stash-safety.md`, after #555) but nothing enforces it for verdict/finding/count-bearing jq. Add a `jq_strict`/`jq_or_die` helper (uses `jq -e`, propagates non-zero, logs to stderr) + a CI scanner modeled on the existing `tools/check-no-raw-sha256sum.sh` (KF-012 precedent). Migrate the gate scripts first (adversarial-review, flatline-orchestrator, red-team-*, post-pr-triage, scoring-engine).

### R12. Fix `health.py` window filter (silent all-time aggregation)  ⟦M, low risk⟧
**cheval-periphery**: the audit writer emits `ts_utc` (`audit_envelope.py:349`) but `health.py:103` reads `envelope.get("timestamp") or envelope.get("ts")` — always None, so the `since` window filter **never excludes anything** and every "24h" health report is all-time. `economy.py:114` has the fixed `ts_utc` lookup (copied later); the test fixture uses the wrong key (`test_substrate_health.py:25`), masking it. Extract one shared envelope-iterator both consume; regenerate the fixture through the real emitter so shape can't drift again.

### R13. Unify state-write locking + the `.run/` JSONL/ledger writers  ⟦L, medium risk⟧
**state-zone-dataflow**: 4+ ledger writers hand-roll `jq` read-modify-write, only one uses the locked `_write_ledger`; `.run/` writers split between flock'd and unlocked `jq>tmp>mv`; no shared JSONL-append primitive. Race-prone under the autonomous `/run` + post-merge concurrency. Route all through `path-lib`'s `append_jsonl` + a locked ledger mutator.

### R14. Close the test-architecture gaps  ⟦M, low risk⟧
- **135 integration bats files, CI runs 2** (`bats-tests.yml`) — a permanently-dark test directory (test-architecture, dead-code). Decide: wire a curated subset into CI or stop calling them tests.
- Template↔live hook-settings parity now enforced (sprint-bug-199 W1-W9); extend the diff test to the full hook command set (hooks finding).
- The #628 not-natively-sourceable pattern: tests `sed`-rewrite scripts to source them. A `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi` convention would let tests source directly.

---

## Suggested sequencing

1. **Now, cheap, high-value** (S, low risk): R1-interim (the `_CLI_ADAPTER_BY_PROVIDER` parity test), R4 (delete chains.py), R6 batch (dead artifacts), R12 (health.py window bug). Each is its own `/bug` micro-sprint.
2. **The #1016 fix**: R3 (ModelinvState dataclass + single emit site) — already filed.
3. **Operator decisions gate these**: R5 (#937 chunking fork), R7 (legacy bash adapter removal — confirm offline path), then R2 (codegen/pricing consolidation) which R7 unblocks.
4. **Structural, schedule deliberately**: R11 (output-swallowing guard — the KF-004/KF-015 structural close, highest correctness payoff), R8 (HeadlessCLIAdapter — **before** cursor-headless #966 merges), R10 (base.py split), R9/R13/R14 (shared-lib + state + test consolidations).

## Operator decisions embedded here
- **R5/#937**: wire or delete the chunking package (dormant since cycle-110).
- **R7**: is `model-adapter.sh.legacy` still load-bearing in any offline/no-API-key deployment?
- **R6 workflows**: confirm the `cycle099-*` codegen drift gates are duplicated before deleting.

Full 119-finding dataset: workflow run `wf_8033d076-eab` (15 agents).
