# Bug Triage: The cost-budget enforcer halts permanently on historical unpriced ledger rows — the unpriced share is measured over all time instead of the enforcement day, and there is no sanctioned re-pricing pass

## Metadata
- **schema_version**: 1
- **bug_id**: 20260924-57bc88
- **classification**: logic_bug (wrong measurement window in a fail-closed guard) + missing sanctioned operation (no explicit, auditable re-pricing of historical rows)
- **severity**: high
- **eligibility_score**: 4
- **eligibility_reasoning**: Reproducible steps with exact output (+2): on this repository `budget_verdict 5.00` returns `halt-uncertainty` / `uncertainty_reason: unpriced_share` with `unpriced_share 0.685` (37 of 54 rows) although every row written since the pricing ladder landed is priced; the same verdict reproduces from a two-day fixture ledger. Error payload from the observed run (+1): cycle-125 sprint-244 E2E G-5 recorded the halt with the share in `diagnostic`. Regression from a known baseline (+1): the guard was introduced by cycle-125 FR-5 (`6c9d77e2`, released in `v2.0.0-rc.2`); before it the enforcer could certify `allow` on this ledger. No disqualifier: no new endpoint, UI, schema or configuration key (the re-pricing pass is an explicit flag on an existing script, off unless invoked).
- **test_type**: unit
- **risk_level**: high
- **created**: 2026-09-24T01:16:15Z

Risk note: the suspected files are the spend guard (`billing` / `budget` keywords → high per the analysis table). The fix never weakens the guard for the day it certifies — an unpriced row inside the enforcement window still halts — and the re-pricing pass is opt-in, marks every changed row, keeps a byte copy of the previous ledger and writes a receipt. The maintainer's standing instruction for this session ("proceed as you suggest", 2026-09-24, after the rc.2 close-out listed bead `bd-ypbg`) stands in for `--allow-high`; this is recorded in `grimoires/loa/NOTES.md`.

## Reproduction
### Steps
1. In a temp dir, write a ledger with 37 rows dated `2026-09-22` for `openai/codex-headless` with `pricing_source: "unknown"`, `cost_micro_usd: 0` and real token counts, plus 17 priced rows (`pricing_source: "config"` or `"cli_reported"`) dated `2026-09-23`; point `LOA_COST_LEDGER_PATH` at it. (This is the shape of `.run/cost-ledger.jsonl` on this repository on 2026-09-24: 37 unknown / 13 cli_reported / 4 config.)
2. `source .claude/scripts/lib/cost-budget-enforcer-lib.sh` with `LOA_BUDGET_DAILY_CAP_USD=50 LOA_BUDGET_TEST_NOW=2026-09-24T12:00:00.000000Z` (no rows on that day, or only priced rows) and run `budget_verdict 5.00`.
3. Run `.claude/scripts/cost-report.sh --json` and read `unpriced_share`; run `cost-report.sh --help`.

### Expected Behavior
- Step 2: `allow` — the verdict certifies the UTC day `2026-09-24`; that day has no unpriced spend, so nothing about it is uncertain. A day that does contain unpriced rows above 5 % still halts.
- Step 3: the report exposes the share for a named day next to the all-time share, and offers an explicit, opt-in way to re-price historical rows that the ladder can now resolve (`codex-headless` → its configured `extra.cli_model`), marking each changed row (`repriced_at`, what it was before) and leaving a receipt — never rewriting history silently, never touching rows it cannot price.

### Actual Behavior
- Step 2 (observed 2026-09-24 on this repository's ledger): exit 1, last event `budget.halt_uncertainty`, payload `verdict: halt-uncertainty`, `uncertainty_reason: unpriced_share`, `diagnostic.unpriced_share: 0.685185`, `diagnostic.unpriced_rows: 37`, `threshold: 0.05` — for every `utc_day`, forever, because `_l2_unpriced_share_json` runs `cost-report.sh --json` and takes the all-time `unpriced_share` (`cost-budget-enforcer-lib.sh:1233-1236`, `:1270-1295`). The same ledger with the 37 rows re-dated to any past day gives the same verdict for today.
- Step 3: `unpriced_share` is `unpriced_rows / len(entries)` over every row (`cost-report.sh:382`); no per-day field exists. `--help` lists `--migrate-legacy` and `--include-legacy` only; a historical `unknown` row can only be changed by hand-editing the ledger, which the writer contract forbids.

### Environment
Linux 6.16, bash 5, jq 1.7, python 3 with the cheval substrate (`.claude/adapters/loa_cheval`); repository at `main` `5f4a58a5` (`v2.0.0-rc.2` published); `.run/cost-ledger.jsonl` 54 rows spanning 2026-09-22T09:19Z → 2026-09-23T06:08Z; `.loa.config.yaml` has no `cost_budget_enforcer` block (the enforcer is exercised through its library, as the E2E did).

## Analysis
### Suspected Files
| File | Line(s) | Confidence | Reason |
|------|---------|------------|--------|
| `.claude/scripts/lib/cost-budget-enforcer-lib.sh` | 1225-1262 | high | the FR-5 guard compares the all-time share against 0.05 and halts; the verdict it protects is for `utc_day` |
| `.claude/scripts/lib/cost-budget-enforcer-lib.sh` | 1270-1295 | high | `_l2_unpriced_share_json` runs `cost-report.sh --json` with no window; the bats seam (`LOA_BUDGET_COST_REPORT_JSON`) mirrors the all-time shape |
| `.claude/scripts/cost-report.sh` | 236-330, 382-395 | high | one `unpriced_share` over `entries`; no per-day counters; `--days` only scopes cost totals |
| `.claude/scripts/cost-report.sh` | 138-230 | medium | `--migrate-legacy` is the pattern to mirror for an auditable pass (receipt, sha256 before/after, idempotence) — but it appends; re-pricing must rewrite marked rows |
| `.claude/adapters/loa_cheval/metering/pricing.py` | 279-330, 103-135 | medium | `find_pricing` ladder (exact → dated → alias → hop) and `calculate_total_cost` — the re-pricing pass must price exactly as a fresh row would |
| `.claude/adapters/loa_cheval/metering/ledger.py` | 109-212 | medium | row shape and the `pricing_source` / `pricing_resolution` / `cost_estimated` / `resolved_model` fields the pass must set; `append_ledger` symlink refusal to mirror |
| `.claude/data/trajectory-schemas/budget-events/budget-allow.payload.schema.json`, `budget-halt-uncertainty.payload.schema.json` | `additionalProperties: false` | medium | the payload gains the window day (additive) |
| `docs/migration/v2.0-model-generation-floor.md` | 200-211 | low | "Your pre-2.0 cost history" must name the re-pricing pass and the per-day rule |

### Related Tests
| Test File | Coverage |
|-----------|----------|
| `tests/unit/cost-budget-enforcer-unpriced.bats` | UP-1..UP-5: share > 5 % halts, ≤ 5 % allows with the share in the payload, unavailable report allows with null, hermetic seam — all against the all-time shape |
| `tests/unit/cost-report.bats` | CR-1..CR-5: totals, unpriced/unclassified counts, `--include-legacy`, `--migrate-legacy` receipt + idempotence, symlink refusal, ledger isolation |
| `.claude/adapters/tests/test_pricing_resolution_ladder.py` | 14 cases: exact/dated/alias/hop resolution and `pricing_resolution` |
| `tests/unit/cost-budget-enforcer-state-machine.bats` | the verdict state machine the guard sits in (must keep passing) |

### Test Target
Failing first:
- `cost-budget-enforcer-unpriced.bats`: (UP-6) a report whose all-time share is 0.685 but whose `window.unpriced_share` for the verdict's `utc_day` is 0 → `allow`, payload carries `unpriced_share 0` and `unpriced_window "2026-05-04"`; (UP-7) `window.unpriced_share 0.2` → `halt-uncertainty` with `diagnostic.window_day` and `diagnostic.unpriced_share_all_time`; (UP-8) a report without a `window` object (older shape) keeps the all-time share (conservative); (UP-9) the production path passes `--window-day <utc_day>` — bats-gated stub script seam `LOA_BUDGET_COST_REPORT_SCRIPT` records its argv.
- `cost-report.bats`: (CR-6) `--window-day 2026-09-23` on a two-day ledger → JSON `window {day, entry_count, unpriced_rows, unpriced_share}` and a markdown line; the all-time fields are unchanged; (CR-7) `--reprice --dry-run` changes nothing and reports what would change; `--reprice` re-prices the resolvable `unknown` rows (hop → `extra.cli_model`) with `repriced_at`, `repriced_from`, `cost_estimated: true`, `pricing_resolution`, leaves unresolvable and already-priced rows byte-identical, writes a backup copy and a receipt with counts and sha256s, is idempotent, refuses a symlinked ledger; the repository's ledgers stay byte-identical (teardown guard).
- `.claude/adapters/tests/test_reprice_rows.py`: the pure function — a `codex-headless` unknown row priced through the hop with the marks set; an unknown model stays unknown; a row with `repriced_at` is skipped; `config` / `cli_reported` rows untouched; token math equals `create_ledger_entry` for the same tokens.

### Constraints
- Never weaken the guard for the day it certifies: an unpriced row inside the enforcement window still counts; a report without a window falls back to the all-time share; an unavailable report still allows with null (unchanged).
- No new configuration key. `--window-day` and `--reprice [--dry-run]` are flags on `cost-report.sh`; the enforcer passes the day it already computes.
- The re-pricing pass is explicit and opt-in, prices exactly as `create_ledger_entry` would price a fresh row with the same tokens (ladder + `calculate_total_cost`), marks every changed row (`repriced_at`, `repriced_from: {pricing_source, cost_micro_usd}`, `cost_estimated: true`), never touches rows it cannot price or rows already priced, keeps a byte copy of the previous ledger next to it, writes a receipt under `.run/` with counts and sha256s (never row contents), replaces the file atomically, refuses a symlinked ledger, and is idempotent.
- Payload schema changes are additive (`unpriced_window`, diagnostic fields); `budget-events` consumers keep validating.
- `.claude/` edits under the framework marker; regenerate `grimoires/loa/REPO-MAP.md` (+ `.checksum` sidecar) and `.claude/checksums.json` together; prompt budgets untouched (no skill text changes).

## Fix Strategy
1. `cost-report.sh` gains `--window-day YYYY-MM-DD`: the Python aggregation also counts rows whose `ts` falls on that UTC day and emits `window: {day, entry_count, unpriced_rows, unpriced_share}` in the JSON envelope (and one markdown line). All existing fields keep their all-time meaning.
2. `_l2_unpriced_share_json` takes the verdict's `utc_day` and calls `cost-report.sh --json --window-day <day>`; it returns `{unpriced_share, unpriced_rows, unpriced_share_all_time, window_day, ledger}` where `unpriced_share` is the window share when the report has one, else the all-time share. The guard compares that value; the halt diagnostic carries `window_day` and `unpriced_share_all_time`; the allow payload carries `unpriced_window`. Under bats the seam file stays the only input, plus a bats-gated `LOA_BUDGET_COST_REPORT_SCRIPT` stub path that proves the argv.
3. New `loa_cheval/metering/reprice.py` with `reprice_rows(rows, config, now_iso)` → `(rows, stats)`: for each row with `pricing_source == "unknown"` and no `repriced_at`, resolve `(provider, model)` (then `resolved_model` if present) through `find_pricing`; when found, recompute the cost from the row's tokens with `calculate_total_cost` and set `cost_micro_usd`, `pricing_source: "config"`, `pricing_resolution`, `resolved_model` (the hop's target when it differs), `cost_estimated: true`, `repriced_at`, `repriced_from`. `cost-report.sh --reprice [--dry-run]` drives it: refuses a symlinked ledger, copies the file to `<ledger>.pre-reprice-<UTC>`, writes the new rows to a temp file in the same directory and `os.replace`s it, writes `.run/cost-ledger-reprice-<UTC>[-N].json` (rows scanned / repriced / still unpriced / skipped, backup path, sha256 before/after, catalog source), then prints the normal report. `--dry-run` prints the counts and touches nothing.
4. Docs: migration guide "Your pre-2.0 cost history" paragraph (per-day rule + `--reprice`), `cost-report.sh` header, CHANGELOG `[Unreleased]` entry.

### Fix Hints
Structured hints for multi-model handoff (each hint targets one file change):

| File | Action | Target | Constraint |
|------|--------|--------|------------|
| `.claude/scripts/cost-report.sh` | add | `--window-day` flag → `window` object in the JSON envelope + markdown line | additive; all-time fields unchanged |
| `.claude/scripts/cost-report.sh` | add | `--reprice [--dry-run]` driving `loa_cheval.metering.reprice` with backup, atomic replace, receipt, symlink refusal | opt-in; never touches priced or unresolvable rows; idempotent |
| `.claude/adapters/loa_cheval/metering/reprice.py` | add | pure `reprice_rows(rows, config, now_iso)` using `find_pricing` + `calculate_total_cost` | marks `repriced_at` / `repriced_from` / `cost_estimated`; deterministic |
| `.claude/scripts/lib/cost-budget-enforcer-lib.sh` | fix | `_l2_unpriced_share_json <utc_day>` → `--window-day`; guard reads the window share, falls back to all-time; diag + allow payload fields | bats-hermetic seam kept; new bats-gated stub-script seam |
| `.claude/data/trajectory-schemas/budget-events/budget-allow.payload.schema.json` | add | `unpriced_window` (string, YYYY-MM-DD or null) | additive |
| `.claude/data/trajectory-schemas/budget-events/budget-halt-uncertainty.payload.schema.json` | fix | diagnostic description names `window_day`, `unpriced_share_all_time` | additive (diagnostic already open) |
| `docs/migration/v2.0-model-generation-floor.md` | fix | cost-history paragraph: per-day rule, `--reprice` | rc.2 addendum section |
| `tests/unit/cost-budget-enforcer-unpriced.bats`, `tests/unit/cost-report.bats`, `.claude/adapters/tests/test_reprice_rows.py` | add | UP-6..UP-9, CR-6..CR-7, pytest cases | failing first; repository ledgers byte-identical |
