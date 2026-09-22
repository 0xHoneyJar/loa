# Reviewer concern notes — Sprint 1 (cycle-124), review ROUND 2, Phase 2 input to the cross-model dissenter

Scope of this round: the round-1 fix commits 19ffd850..632d0961 (`0f8c1df6` adapter, `fcc31c5e` ledger, `77f9180f` gates, `16b88d56` tooling, `632d0961` repo-map). The diff you receive is that range only; the full sprint diff (80be4b0f..HEAD, ~900 KB) was dissented in round 1 (clean) and is the audit dissent's input.

Round-1 verdict was CHANGES_REQUIRED with 5 high / 9 medium / 9 low, all accepted and fixed. The reviewer wants an independent opinion on whether the FIXES are complete and did not open new holes:

1. `cheval._persona_messages` (.claude/adapters/cheval.py:219-260): the persona-less `--system` payload now carries `cache_control`. Is there any caller for which marking the whole system payload is wrong (a per-call, non-stable system file that would now write a cache entry on every call at 1.25× and never read it)? Look at `model-adapter.sh` and `flatline-orchestrator.sh` `--system` usage.
2. `_entry_thinking_class` (cheval.py:737) treats `temperature_supported: false` as "thinking on". Is there a catalog entry where that is false-positive (an entry with temperature unsupported but no thinking) that would now flag a legitimate `max_tokens` stop? Check `.claude/defaults/model-config.yaml` params per Anthropic entry.
3. `claude_headless_adapter._resolve_effort` (claude_headless_adapter.py:251-275): `request.effort` is now the first candidate. Does an unsupported level reach the CLI unchanged (the adapter's `_ALLOWED_EFFORTS` filter) and can a metadata `effort` still override it anywhere else in the chain?
4. `_is_model_not_found` (anthropic_adapter.py:61): the walk is gated on the message starting with `model:`. Are there real Anthropic 404 shapes for a not-served model that do NOT start with `model:` (Bedrock/Vertex paths, proxies) which would now be terminal again?
5. `golden-path.sh` `_gp_trailer_int` (:117-135) and the review gate on the audit path (:180-186): can a review file with TWO trailers (one clean, one with `excluded`) be read differently by `_gp_trailer_int` (LAST trailer) and `verdict-derive.sh` (which rejects multiple trailers)? Is the failure still closed?
6. `resolve_cost_ledger_path` (metering/ledger.py:49-100): the project-root anchoring uses `Path(__file__).resolve().parents[4]`. Is that correct when the adapters package is installed/imported from a location other than `.claude/adapters/loa_cheval/` (symlinked checkout, vendored copy, `PROJECT_ROOT` env set)? Does a FIFO or socket at the target pass `S_ISREG`?
7. `rollup.default_ledger_path()` (metering/rollup.py:46) now calls `load_config()`; any side effects (env overlays, `_find_project_root` walking from CWD) that could make the reader resolve a DIFFERENT root than the writer when cheval is run from a subdirectory?
8. `cost-report.sh` (.claude/scripts/cost-report.sh:26-36) shells into python at startup; failure modes when `.venv/bin/python` exists but lacks PyYAML; is the fallback path correct and does `set -euo pipefail` survive the `$(...) || ...` construct?
9. `tools/regen-model-artifacts.sh` `precheck_toolchain` (:55-66) runs before `--check`; is exit 3 handled by every caller (CI workflow `bats-tests.yml`, `cycle-124-anthropic-catalog.bats`, `check-bb-dist-fresh`)?
10. `progressiveTruncate` (truncation.ts:887-897): `model in TOKEN_BUDGETS && model !== "default"` — is `"__proto__"`/prototype-key lookup a concern for `in` here, and is the `GENERATED_TOKEN_BUDGETS` object a plain object?
11. Test-quality: `test_thinking_truncation_sets_operator_visible_warn` patches `resolve_execution`/`get_adapter`; confirm `_entry_thinking_class` reads the same `hounfour` dict the real path passes (not a MagicMock attribute that is always truthy).
12. The mixed cost-ledger fixture (`tests/fixtures/metering/mixed-cost-ledger.jsonl`): are the three post-cache rows' `cost_micro_usd` values actually what `calculate_total_cost` would produce at the catalog's cache rates (opus-5 in 5.0/out 25.0/read 0.5/write 6.25 per MTok; fable-5-1 in 10/out 50/read 0.25)? Say so if a row is inconsistent.

## Round 2, second pass (after the first round-2 dissent)

Your first pass returned DISS-001 (BLOCKING): `rollup.default_ledger_path()` swallowed `ConfigError` and silently read `.run/cost-ledger.jsonl`. Fixed in `12b6067e`: the reader raises, the rollup CLI exits 2, `cost-report.sh` resolves the default after argument parsing and exits 2 on a resolver refusal (falls back to the literal only when the Python substrate is unavailable). Also `e14b3e7c`: own-key lookup in `getTokenBudget`/`progressiveTruncate` (concern 10). Please verify both fixes and re-check concerns 1–12 against the current diff.

## Round 2, third pass

After the second pass (clean), the audit dissent surfaced a HIGH via its rejected-payload sidecar: `live-floor-check.yml` handed `ANTHROPIC_API_KEY` to pytest on `pull_request`. Fixed in `44e1feab` (workflow_dispatch-only + `environment: live-floor`). Verify that fix and re-check the rest one last time.

## Round 2, fourth pass (after the audit-phase fixes)

The audit slices added `2b43baf4` (ledger: unconditional test isolation, sidecar O_NOFOLLOW, readers refuse on unloadable config), `1991390f` (adapter: budget-aware non-streaming timeout, ModelNotFoundError bypasses the breaker) and `4670b22f` (BB retry from the clamped budget, typed pricing schema). Verify these three and re-check concerns 1-12 one last time.
