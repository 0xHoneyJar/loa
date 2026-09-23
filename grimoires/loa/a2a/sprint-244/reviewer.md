# Implementation Report — Sprint 4 (Final): Provider health, cost accounting, docs and E2E (cycle-125, global sprint 244)

**Cycle:** cycle-125 friction-floor · **PRD:** `grimoires/loa/prd.md` FR-4, FR-5, §Success Criteria · **SDD:** `grimoires/loa/sdd.md` §1.5, §1.6, §8 · **Plan:** `grimoires/loa/sprint.md` Sprint 4
**Implementer:** Fable 5.1 lead (`/run sprint-plan`, run-20260923-282c32ce, unattended) · **Date:** 2026-09-23 · **Epic:** bd-bhpk (tasks bd-0wsg, bd-s0wx, bd-plz8, bd-mrna, bd-gxys, bd-3yke, bd-j0qz)

## Summary

Usage mining (F4) found provider breakers OPEN in a dozen mounts with nobody able to see them, and (F5, corrected) 79 % of the current-path cost rows unpriced because the ids the fleet actually invokes — dated releases, aliases, CLI-hop names — are not catalog keys. This sprint makes provider health one glance in `/loa` (breakers with age and probe timing, credential presence, CLI hops), gives operators a journaled reset, proves that an OPEN bucket walks the within-company chain to the CLI hop without calling the provider, seeds the known-failures ledger on mount, prices the fleet's ids through a four-rung ladder with the rung recorded on the row, makes the pre-2.0 ledger readable and migratable through the validated writer, prints the unpriced share on every report, and stops the budget enforcer from calling a day "under budget" while more than 5 % of rows are unpriced. Docs for the whole cycle landed (CHANGELOG FR-1…FR-5, README rc.2 paragraph, migration addendum). Every PRD goal is validated below with the command that proves it.

Assumptions (Karpathy rule 1): credential *presence* is read from the environment only and never the value (the `/loa` block and the breaker CLI print `present`/`absent`); a breaker reset is an operator action, so its journal marker is written before the state file; the pricing ladder never re-prices history — a row already written stays as written (`pricing_snapshot` semantics), so this repository's own historical unpriced rows keep the enforcer in `halt-uncertainty` until an explicit re-pricing pass exists (bead bd-ypbg); an exact catalog entry for a dated id always beats the stripped base id (Flatline SKP-018); the CLI hop's `extra.cli_model` is "the id the hop actually ran" for attribution — the adapter records it and the ladder resolves it (`fable` → `claude-fable-5-1`); under bats the enforcer's report seam is hermetic so no suite ever reads the repository's live ledger.

## Changes

### FR-4 — provider health
| File | Change |
|---|---|
| `.claude/adapters/loa_cheval/routing/circuit_breaker.py` | `bucket_snapshot(run_dir, reset_timeout)` (`list_buckets` + `age_s` + `probe_due_in_s`), `reset_bucket(provider, auth_type=None, …)` (journal marker `operator_reset` BEFORE `_write_state(_default_state)`; resets one bucket or all of a provider's; validates names), `_cli` (`--list [--json]`, `--reset P[:A]`, `--reason`, `--run-dir`, `--reset-timeout`), `__main__`, `__all__` |
| `.claude/adapters/loa_cheval/routing/breaker_cli.py` (new) | warning-free entry point (`python -m loa_cheval.routing.circuit_breaker` works but runpy warns because the package imports the module eagerly) |
| `.claude/adapters/cheval.py` | `--reset-breaker PROVIDER[:AUTH_TYPE]` (+ `--reset-reason`), `cmd_reset_breaker` routed before the other utility commands; exit 0 reset / 1 nothing matched / 2 bad spec |
| `.claude/scripts/loa-status.sh` | `Providers` block (`display_providers_section`, `get_providers_json`, `_providers_snapshot` via `breaker_cli --list --json` with a jq fallback over the files, `_provider_key_present`, `_provider_hop`), `--json .providers`; bats-gated `LOA_STATUS_RUN_DIR` seam |
| `.claude/templates/known-failures.md.template` (new) | header, schema block, empty Index table, kf-write-lib pointer |
| `.claude/scripts/mount-submodule.sh`, `.claude/scripts/mount-loa.sh` | `seed_known_failures_ledger` called from `init_state_zone` / `init_structured_memory`; never overwrites; warns when the template is missing |
| `.claude/scripts/check-loa.sh` | `check_memory` warns when `known-failures.md` is absent (with the `cp` remedy) |
| `.claude/adapters/tests/test_circuit_breaker_cli.py` (new, 12) | snapshot arithmetic and symlink exclusion; OPEN → HALF_OPEN after the cooldown via `check_state` and `probe_due_in_s == 0` before it; reset journals-before-write with previous state in the marker; reset-all-of-provider; bad names; CLI text/JSON/empty/usage/exit codes; no credential value in output |
| `.claude/adapters/tests/test_breaker_open_walks_to_cli_hop.py` (new, 2) | `cheval.cmd_invoke` with the REAL retry/breaker path: `anthropic/http_api` OPEN in a temp `.run/` → the HTTP adapter's `complete` is never called, the `claude-headless` entry succeeds, MODELINV records `models_failed[0]` "Circuit open" and `models_succeeded == ["anthropic:claude-headless"]`; CLOSED control case |
| `tests/unit/loa-status-providers.bats` (new, 3) | block shape with fixture buckets, `--json` mirror, no-breaker provider, credential value never printed |
| `tests/unit/known-failures-seed.bats` (new, 5) | template shape; both seeders (created, logged once, never overwritten, template-missing warning); `kf-write-lib.sh new` appends to a seeded ledger; `check-loa` warning |

### FR-5 — cost accounting
| File | Change |
|---|---|
| `.claude/adapters/loa_cheval/metering/pricing.py` | `PricingEntry.resolution` (default `exact`); `_exact_pricing`; `find_pricing` ladder exact → dated (`-YYYY-MM-DD` stripped only when the base exists) → alias (`aliases` / `backward_compat_aliases`, the alias's provider wins) → hop (`kind: cli` or a known `*-headless` name prices as its `extra.cli_model`, recursively, depth-capped) |
| `.claude/adapters/loa_cheval/metering/ledger.py` | `create_ledger_entry(resolved_model=, transport=)`; config-priced rows carry `pricing_resolution`; `cost_estimated: true` when priced from counted tokens; `resolved_model` fallback for pricing; `unknown` stays unknown at cost 0 |
| `.claude/adapters/loa_cheval/metering/budget.py` | passes `metadata.resolved_model` / `metadata.transport` into the row |
| `.claude/adapters/loa_cheval/providers/{claude,codex}_headless_adapter.py` | result metadata `transport` (`cli:claude` / `cli:codex`), `requested_model`, `resolved_model` (= `extra.cli_model` when it differs); `model` keeps its meaning (actual, else requested) |
| `.claude/scripts/cost-report.sh` | `--include-legacy` (de-duplicated by `request_id`, rows tagged `legacy`), `--migrate-legacy` (appends through `loa_cheval.metering.ledger.append_ledger` — O_NOFOLLOW — tagging `legacy: true`, receipt `.run/cost-ledger-migration-<UTC>[-N].json` with counts and sha256s, idempotent), `--legacy-ledger`; `Unpriced rows: N (S %)` + `Pricing resolution:` line; JSON `unpriced_rows`, `unpriced_share`, `estimated_rows`, `legacy_rows`, `pricing_resolution` |
| `.claude/scripts/lib/cost-budget-enforcer-lib.sh` | after the hard caps and before `allow`: `_l2_unpriced_share_json` (from `cost-report.sh --json`, capture-then-parse; bats-hermetic seam `LOA_BUDGET_COST_REPORT_JSON`); share > 0.05 → `halt-uncertainty` with `uncertainty_reason: unpriced_share` and a diagnostic; unavailable report → `unpriced_share: null` and no block; `allow` payload carries `unpriced_share` |
| `.claude/data/trajectory-schemas/budget-events/budget-{allow,halt-uncertainty}.payload.schema.json` | `unpriced_share` property; `unpriced_share` in the reason enum |
| `.claude/adapters/tests/test_pricing_resolution_ladder.py` (new, 14) | the eight fleet ids (`gpt-5.5-2026-04-23` dated, `gpt-5.2-2025-12-11` dated, `gemini-2.5-pro` exact, `codex-headless` hop, `claude-headless` hop → `claude-fable-5-1`, `fable` alias, …) each resolve with the expected rung against the real catalog; unknown stays unknown; exact dated beats stripping; base-must-exist; cross-provider alias; hop self-loop terminates; ledger rows carry resolution/transport/estimate; `resolved_model` fallback; cli_reported still wins |
| `.claude/adapters/tests/test_headless_resolved_model_metadata.py` (new, 4) | claude/codex adapters record the hop and `resolved_model`; reported model still preferred |
| `tests/unit/cost-report.bats` (new, 5) | totals vs hand computation (10,500 µ$), unpriced line/JSON, include-legacy de-dup, migrate-legacy through the writer with receipt + idempotence, symlinked target refused, missing legacy exit 2, empty envelope; ledger isolation asserted in `teardown` (repository ledgers byte-identical after every test) |
| `tests/unit/cost-budget-enforcer-unpriced.bats` (new, 5) | > 5 % → halt-uncertainty with diagnostic; ≤ 5 % → allow with share; unavailable/malformed → allow with null; hard cap still wins; production path calls `cost-report.sh --json` |

### Docs, FR-1 follow-through, regen
| File | Change |
|---|---|
| `CHANGELOG.md` `[Unreleased]` | FR-4 and FR-5 entries (FR-1…FR-3 landed in their sprints) |
| `README.md` | "Landing in `2.0.0-rc.2`" paragraph under What's new |
| `docs/migration/v2.0-model-generation-floor.md` rc.2 addendum | preflight, provider health / breaker reset / KF seeding, legacy cost ledger |
| `.claude/hooks/safety/block-destructive-bash.sh` | dogfooding catch: `notes-guard.sh read --file …` inside a command voided the mktemp proof because `read` matched anywhere; rebinding builtins now count only in command position (statement start, after `&&`/`||`/`(`/`{`, reserved words, `command`/`builtin`, assignment prefixes); corpus B48–B49 / D56–D60; fence suite 281/281, corpus 49/49 + 60/60 |
| `grimoires/loa/REPO-MAP.md` (+checksum), `.claude/checksums.json` | regenerated (validate consistent; 3272 tracked, 0 drift) |

## Test-first record

- Task 4.1 tests (breaker CLI, chain walk, status block, KF seeding) and Task 4.3 tests (pricing ladder, adapter metadata, cost-report, enforcer) were written before their implementations; each suite was red by construction (missing module / flag / template) and went green with the implementation.
- Pricing ladder probed against the real catalog before the tests were finalised: `gpt-5.5-2026-04-23 → dated gpt-5.5`, `gpt-5.2-2025-12-11 → dated gpt-5.2`, `codex-headless → hop gpt-5.5`, `claude-headless → hop claude-fable-5-1` (through the `fable` alias), `fable → alias`, `gemini-2.5-pro → exact`.
- Two defects found by the tests and fixed in-sprint: the migration receipt name collided when two migrations ran in the same second (now `-N` suffixed, CR-3 idempotence case); the enforcer's `budget.allow` payload failed schema validation because `unpriced_share` was not a declared property, and `halt-uncertainty` rejected the new reason — the schemas were extended and the state-machine / remediation suites went back to green (57/57 across the three enforcer suites). A third: the first full-suite attempt showed the enforcer consulting this repository's live ledger under bats (74 % unpriced) — the seam is now hermetic under the bats marker.
- The first full `tests/unit/` attempt with `GIT_CONFIG_GLOBAL=/dev/null` alone turned 113 bridge tests red ("Please tell me who you are"): the isolated config drops the git identity too. The recorded run sets `GIT_AUTHOR_*` / `GIT_COMMITTER_*` alongside it (KF-034 refinement, noted for the runbook).
- pytest: `test_circuit_breaker_cli` 12, `test_breaker_open_walks_to_cli_hop` 2, `test_pricing_resolution_ladder` 14, `test_headless_resolved_model_metadata` 4, plus `test_circuit_breaker`, `test_claude_headless_adapter`, `test_codex_headless_adapter`, `test_cli_reported_cost`, `test_cache_read_pricing`, `test_chain_walk_audit_envelope` → 153 passed, 2 skipped (pre-existing skips). bats: `loa-status-providers` 3, `known-failures-seed` 5, `cost-report` 5, `cost-budget-enforcer-unpriced` 5, `cost-budget-enforcer-state-machine` + `-remediation` + `circuit-breaker` + `circuit-breaker-auth-type` green; `block-destructive-bash` 281.
- Full `tests/unit/` run with ledger hashes before/after (Task 4.6, KF-033): **see §Close-out below** (filled when the run completed).

## AC Verification (sprint.md)

### Breaker bats/pytest: `--list` shape, reset journals, OPEN → HALF_OPEN after cooldown; status snapshot prints state/age/credential presence/hop and never a value (prd.md FR-4 AC 1–2)
- **Status**: ✓ Met
- **Evidence**: `test_circuit_breaker_cli.py::test_cli_list_text_and_json` (shape), `::test_reset_bucket_journals_before_writing_default_state` (marker precedes the write, previous state recorded), `::test_check_state_moves_open_to_half_open_after_reset_timeout` (`circuit_breaker.py:check_state` + `bucket_snapshot`), `::test_cli_output_carries_no_credential_values`; `loa-status-providers.bats` LSP-1/2 (`key present|absent`, `hop codex`, `http_api OPEN 2h (probe overdue → HALF_OPEN on next call)`, `sk-test-…` absent from output).

### Chain-walk test: OPEN `anthropic/http_api` fixture → the alias resolves to the CLI hop in a dry-run trace (prd.md FR-4 AC 3)
- **Status**: ✓ Met (mechanism differs, stated)
- **Evidence**: `test_breaker_open_walks_to_cli_hop.py::test_open_http_api_breaker_walks_to_the_cli_hop` runs `cmd_invoke` through the real `invoke_with_retry` (`retry.py:373-380` skips the OPEN bucket without a call; the exhausted entry surfaces as `RetriesExhaustedError`, which `cheval.py:2110` walks) — the primary adapter's `complete` count is 0, the fallback's is 1, MODELINV names both. `--dry-run` itself resolves only the primary (`cheval.py:1368`) and never consults breakers, so the SDD's "dry-run trace" is realised as the MODELINV trace with mocked adapters and a real breaker file (the SDD's own fallback wording).

### Mount tests assert the seeded `known-failures.md` (prd.md FR-4 AC 4)
- **Status**: ✓ Met
- **Evidence**: `known-failures-seed.bats` KFS-2 (mount-submodule), KFS-3 (mount-loa + missing-template warning), KFS-4 (`kf-write-lib.sh new` on a seeded ledger), KFS-5 (`check-loa` warning); seeding code `mount-submodule.sh:seed_known_failures_ledger`, `mount-loa.sh:seed_known_failures_ledger`.

### Pricing pytest over the fleet ids: each resolves; unknown ids stay `unknown` and are counted; per-hop adapter test pins the resolved id (prd.md FR-5 AC 1–2)
- **Status**: ✓ Met
- **Evidence**: `test_pricing_resolution_ladder.py::test_fleet_ids_resolve_with_the_expected_rung` (8 parametrised ids), `::test_unknown_ids_stay_unknown`, `::test_ledger_rows_carry_resolution_transport_and_estimate_flags` (`unknown` row: `pricing_source: unknown`, cost 0, no resolution); `test_headless_resolved_model_metadata.py` (claude `resolved_model: fable`, codex `resolved_model: gpt-5.5`, transport recorded); `cost-report.bats` CR-1 counts `unpriced_rows`.

### `cost-report.bats`: totals match a hand computation; legacy include/migrate/receipt; unpriced share printed (prd.md FR-5 AC 3); ledger isolation preserved (prd.md FR-5 AC 4)
- **Status**: ✓ Met
- **Evidence**: CR-1 (10,500 µ$ = 8,000 + 0 + 2,500; `Unpriced rows: 1 (33.3 %)`), CR-2 (include-legacy 12,000 µ$, duplicate skipped, files unchanged), CR-3 (migrate: 1 appended with `legacy: true`, receipt counts/hashes, second run migrates 0), CR-4 (symlinked target refused by the writer), CR-5; `teardown` asserts the repository's `.run/cost-ledger.jsonl` and `grimoires/loa/a2a/cost-ledger.jsonl` hashes are unchanged after every test; the full-suite ledger hashes are in §Close-out.

### All PRD goals validated in Task 4.E2E with documented evidence
- **Status**: ✓ Met
- **Evidence**: table below (commands run 2026-09-23 on this repository, script kept at the session scratchpad `e2e-evidence.sh`).

## Task 4.E2E — End-to-End Goal Validation

| Goal | Validation action | Result | Verdict |
|---|---|---|---|
| G-1 fence precision without losing a catch | `bash tests/fixtures/fence-corpus/run-corpus.sh`; `bats tests/unit/block-destructive-bash.bats` | `benign 49/49 dangerous 60/60 residual 0/5 runtime_ms 3594`; 281/281 | ✓ |
| G-2 artefacts readable by section | `notes-guard.sh read --file grimoires/loa/prd.md --section 'Functional Requirements' \| wc -c`; `--index` on sdd.md; `tools/check-prompt-budget.sh` | 8,504 B block (≤ 100 KiB); index 12 lines = 12 H2 in sdd.md; 0 budget FAIL lines | ✓ |
| G-3 runs fail loud / resume | `run-preflight.sh --unattended --json` on this repo; HALTED fixture → surface | `{"ok":false,"pass":5,"warn":2,"fail":1,"ids":[P1…P8],"fails":["P6"]}` (P6 correctly refuses: this run is RUNNING); fixture: `Run: sprint-plan HALTED (29h ago) → /run-resume` | ✓ |
| G-4 provider health visible | `loa-status.sh` Providers block (live buckets); chain-walk test | `anthropic key absent hop claude · headless OPEN 1h (probe overdue → HALF_OPEN on next call) · http_api CLOSED` / `google key present hop - · http_api OPEN 79d …` / `openai key present hop codex · …`; `test_breaker_open_walks_to_cli_hop` 2/2 | ✓ |
| G-5 fleet ids priced | pytest ladder over the fleet ids; `cost-report.sh --include-legacy --json` on a fixture | 14/14; fixture `{"total_micro_usd":32500,"entry_count":4,"unpriced_rows":0,"unpriced_share":0.0,"legacy_rows":1,"pricing_resolution":{"dated":1,"hop":2,"config":1}}` — unpriced share 0 % (< 5 %). Live repository ledger: `entry_count 50, unpriced 37 (74 %)` — all historical rows written before the ladder; new rows price through it; re-pricing history is explicitly not done (bead bd-ypbg) | ✓ (with the stated caveat) |

Integration points verified: the preflight reads `notes-guard.sh check` (P5) and the breaker files (P4); `/loa` reads the Artefacts sizes, the run surface and the provider snapshot in one invocation (LSA/LSP suites + live run above).

## Deviations from the plan, stated

- The warning-free operator entry is `python3 -m loa_cheval.routing.breaker_cli`; `python3 -m loa_cheval.routing.circuit_breaker` (the SDD's spelling) also works but runpy prints a RuntimeWarning because `loa_cheval.routing` imports the module eagerly.
- The "dry-run trace" for the chain walk is the MODELINV trace from a mocked-adapter `cmd_invoke` (real breaker + retry path), not `--dry-run` output, which never reaches the chain.
- The enforcer consults the all-time unpriced share of the current ledger (not a window); on this repository that is 74 % from pre-ladder history, so the enforcer halts here until an explicit re-pricing pass exists (bd-ypbg). This is the SDD's intended direction (unknown spend is unknown), stated plainly rather than hidden by a window.
- One FR-1 refinement landed in this sprint (rebinding builtins in command position only) because Sprint 4's own evidence command was blocked by the fence; it is corpus-gated like every other relaxation.

## Close-out (2026-09-23, after the full run)

- **Full `tests/unit/` run** (388 files, serial, `GIT_CONFIG_GLOBAL=/dev/null` + `GIT_AUTHOR_*`/`GIT_COMMITTER_*`, exit captured to file): **5,681 ok / 12 not ok**, classified:
  - 8 licence grace-period cases (`test_pack_support` 3, `test_license_validator` 3, `test_constructs_loader` 2) — pre-existing class: the gitignored `tests/fixtures/*_license.json` age past their 24 h window; `tests/fixtures/ensure_license_fixtures.sh` regenerates them (recorded in cycle-124 as well).
  - 1 `template-safety: all vision entries use ISO 8601 with time format` — pre-existing red (file untouched since 2026-02).
  - 1 `repo-map: --validate passes against the committed REPO-MAP.md` — real, caused by this sprint: the hook-header and status edits after the last regeneration; REPO-MAP regenerated and committed (`repo-map-gen.bats` 6/6 in isolation).
  - 2 `loa-status-providers` LSP-1/LSP-2 — load-induced: the serial run overlapped with parallel pytest/bats executions and `loa-status` (which performs a cached-upstream worktree check) exceeded its budget; 12/12 green across three isolated re-runs; the suite now passes `--no-stale-check` (`01437730`). No other new suite failed.
- **Ledger isolation (KF-033):** `.run/model-invoke.jsonl` and `.run/cost-ledger.jsonl` hashes changed across the run — by exactly two rows each, at `05:43:32Z` and `05:46:18Z`, i.e. the sprint-244 review dissent and audit dissent invocations that ran concurrently (agent `codex-headless`), not test writes. Every suite that touches ledgers passed explicit temp paths (CR-1…CR-5 assert the repository ledgers byte-identical in `teardown`; the enforcer seam is hermetic under bats). Incidentally those two rows are the first live proof of FR-5: `openai:codex-headless src=config res=hop` — the same hop id that was `pricing_source: unknown` in every earlier row.
- Follow-up beads filed this sprint: bd-ypbg (explicit re-pricing pass for historical unpriced rows), bd-n7v3 (from Sprint 3, `check-permissions.sh` settings scope).
