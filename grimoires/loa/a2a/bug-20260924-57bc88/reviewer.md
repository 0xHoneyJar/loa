# Implementation Report — sprint-bug-245 (bug 20260924-57bc88, bead `bd-ypbg`)

**Sprint**: sprint-bug-245 — the cost-budget enforcer halts permanently on historical unpriced ledger rows
**Branch**: `fix/cycle-125-followups` (from `main` `5f4a58a5`, `v2.0.0-rc.2`)
**Triage**: `grimoires/loa/a2a/bug-20260924-57bc88/triage.md` · **Plan**: `grimoires/loa/a2a/bug-20260924-57bc88/sprint.md`

## Executive Summary

The FR-5 guard (`halt-uncertainty: unpriced_share`) compared the ledger's *all-time* unpriced share against 5 %, so a repository whose ledger carried rows written before the pricing ladder (this one: 37 of 54, `openai/codex-headless`, `pricing_source: unknown`, cost 0) could never be certified `allow` again, for any day. Two root-cause fixes, test-first:

1. **The guard measures the day it certifies.** `cost-report.sh --json --window-day <YYYY-MM-DD>` adds a `window {day, entry_count, unpriced_rows, unpriced_share}` object next to the unchanged all-time fields; `_l2_unpriced_share_json <utc_day>` asks for the verdict's day, compares the window share (an unpriced row inside the window still halts), falls back to the all-time share when the report has no window (older shape — conservative), and carries `unpriced_window` in the allow payload and `window_day` / `unpriced_share_all_time` / `unpriced_rows_all_time` in the halt diagnostic. Payload schemas extended additively.
2. **History is re-priced only explicitly.** New `loa_cheval.metering.reprice` (`is_unpriced`, `reprice_row`, `reprice_rows`) prices an unpriced row exactly as `create_ledger_entry` would price a fresh row with the same tokens (ladder + `calculate_total_cost`) and marks it (`repriced_at`, `repriced_from`, `cost_estimated: true`, `pricing_resolution`, `resolved_model`); `cost-report.sh --reprice [--dry-run]` drives it — symlinked ledger refused, priced/unresolvable rows and corrupt lines kept byte-for-byte, byte copy to `<ledger>.pre-reprice-<UTC>`, atomic replace, receipt `.run/cost-ledger-reprice-<UTC>[-N].json` (counts and sha256s, never row contents), idempotent (a second run re-prices 0, makes no backup, still leaves a receipt). No new configuration key.

Red → green: UP-6/UP-7/UP-9 (enforcer), CR-6/CR-7 (report) and the seven `test_reprice_rows.py` cases failed on the pre-fix tree (`scratchpad/bug245-red.tap`: `not ok 6, 7, 9, 17, 18`; pytest "1 error during collection") and pass now; UP-8 is a regression guard for the conservative fallback (passes before and after by design).

## AC Verification (sprint.md)

### Bug is no longer reproducible: on a copy of this repository's ledger the verdict for a day without unpriced rows is `allow`; a day with unpriced rows above 5 % still halts; `--reprice` on the copy re-prices the 37 `codex-headless` rows through the hop with marks and a receipt, and a second run re-prices 0
- **Status**: ✓ Met
- **Evidence**: E2E on `scratchpad/ledger-copy.jsonl` (a byte copy; the repository ledger's sha256 was identical afterwards): `cost-report.sh --json --window-day 2026-09-24` → `entry_count 54, unpriced_rows 37, unpriced_share 0.685185, window {day 2026-09-24, entry_count 0, unpriced_rows 0, unpriced_share 0}`; production-path `budget_verdict 5.00` (no bats marker, `LOA_COST_LEDGER_PATH` = the copy) → `verdict allow, unpriced_share 0.0, unpriced_window 2026-09-24`; the same with `LOA_BUDGET_TEST_NOW=2026-09-22T12:00Z` → `halt-uncertainty / unpriced_share`, diagnostic `unpriced_share 0.724138, unpriced_rows 21, window_day 2026-09-22, unpriced_share_all_time 0.685185` (the day that holds the unpriced rows still halts); `--reprice --dry-run` → "37 of 37 unpriced row(s) would be re-priced"; `--reprice` → "re-priced 37 of 37 … (0 still unpriced)", report `unpriced_rows 0, repriced_rows 37, estimated_rows 37, pricing_resolution {hop 41, cli_reported 13}`, receipt `scratchpad/e2e-run/cost-ledger-reprice-20260924T013108Z.json`; a second `--reprice --dry-run` → "0 of 0". Code: `.claude/scripts/lib/cost-budget-enforcer-lib.sh:1237` (the guard passes `$utc_day`), `.claude/scripts/lib/cost-budget-enforcer-lib.sh:1299` (window share with all-time fallback), `.claude/scripts/cost-report.sh:562` (the `window` object), `.claude/scripts/cost-report.sh:271` (the `--reprice` pass), `.claude/adapters/loa_cheval/metering/reprice.py:54` (`reprice_row`).

### Failing test proves the fix
- **Status**: ✓ Met
- **Evidence**: red record `scratchpad/bug245-red.tap` — `not ok 6` UP-6, `not ok 7` UP-7, `not ok 9` UP-9, `not ok 17` CR-6, `not ok 18` CR-7; `pytest tests/test_reprice_rows.py` → "Interrupted: 1 error during collection" (no `loa_cheval.metering.reprice`). Green record `scratchpad/bug245-green.tap` — `1..18`, 18 ok; pytest 7 passed. Cases: `tests/unit/cost-budget-enforcer-unpriced.bats:95` (UP-6 clean window → allow with `unpriced_window`), `tests/unit/cost-budget-enforcer-unpriced.bats:107` (UP-7 unpriced row inside the window still halts, `window_day` + `unpriced_share_all_time` in the diagnostic), `tests/unit/cost-budget-enforcer-unpriced.bats:121` (UP-8 no window → all-time fallback), `tests/unit/cost-budget-enforcer-unpriced.bats:132` (UP-9 argv `--json --window-day 2026-05-04` through the bats-gated stub seam; without the marker the stub is ignored and the real report answers with `window_day`), `tests/unit/cost-report.bats:126` (CR-6 window object for three days + markdown line + `yesterday` → exit 2), `tests/unit/cost-report.bats:141` (CR-7 dry-run writes nothing; marks; byte-identical other lines; backup sha = before; receipt counts/sha256s/no row contents; report counts; idempotent second pass with `backup null` and one backup file; symlink refused with the file unchanged), `.claude/adapters/tests/test_reprice_rows.py:52` (hop row priced equal to `create_ledger_entry`, marks, input not mutated), `:78` (unresolvable row is the same object), `:87` (config / cli_reported / pre-metadata-priced rows untouched), `:99` (pre-metadata cost-0 row eligible), `:108` (idempotent), `:116` (`resolved_model` hint), `:124` (absent tokens → 0; cache tokens priced like a fresh row). Isolation: every bats case uses `--ledger` under `mktemp -d` with `LOA_RUN_DIR` redirected; `cost-report.bats` teardown asserts the repository's two ledgers are byte-identical after every case; enforcer cases never read the live ledger under bats (hermetic seams).

### No regressions in existing tests
- **Status**: ✓ Met
- **Evidence**: `tests/unit/cost-budget-enforcer-remediation.bats` + `cost-budget-enforcer-state-machine.bats` + `cost-budget-enforcer-unpriced.bats` → `1..61`, 61 ok (`scratchpad/bug245-neighbours.tap`); `cost-report.bats` 9/9 inside the 18-case run; pytest `test_reprice_rows.py` + `test_pricing_resolution_ladder.py` + `test_pricing_extended.py` + `test_cli_reported_cost.py` + `test_headless_resolved_model_metadata.py` → 87 passed. UP-1..UP-5 (the all-time shape, unavailable report, halt-100 ordering, production seam) unchanged and green; `repo-map-gen.sh --validate` consistent; `bash -n` clean on `cost-report.sh` and the enforcer lib.

### Fix addresses root cause (not just symptoms)
- **Status**: ✓ Met
- **Evidence**: the threshold (0.05) is untouched; the measurement is scoped to the object the verdict certifies (`utc_day`, `.claude/scripts/lib/cost-budget-enforcer-lib.sh:1237`) and a day that contains unpriced spend still halts (UP-7, E2E 2026-09-22); the fallback keeps the old behaviour whenever the report cannot say (`.claude/scripts/lib/cost-budget-enforcer-lib.sh:1299`); history changes only through an explicit pass that marks every row (`.claude/adapters/loa_cheval/metering/reprice.py:89`), never touches priced or unresolvable rows (`.claude/adapters/loa_cheval/metering/reprice.py:106`, `:111`), keeps a byte copy (`.claude/scripts/cost-report.sh:328`) and replaces atomically (`.claude/scripts/cost-report.sh:341`). No ledger hand-edit, no per-repository workaround.

## Tasks Completed

| Task | Status | Where |
|------|--------|-------|
| 1 Failing tests | done | `tests/unit/cost-budget-enforcer-unpriced.bats:95-146` (UP-6..UP-9), `tests/unit/cost-report.bats:126-193` (CR-6, CR-7), `.claude/adapters/tests/test_reprice_rows.py` (7 cases) |
| 2 Fix | done | `.claude/scripts/lib/cost-budget-enforcer-lib.sh:1236-1257` (guard: day, diagnostic, allow payload), `:1263-1306` (`_l2_unpriced_share_json [<utc_day>]`, stub-script seam, window extraction); `.claude/scripts/cost-report.sh:111-122` (flags), `:146-149` (day format), `:265-352` (`--reprice` pass), `:497-507` (counters), `:562-568` (JSON `window`), `:595` (markdown); `.claude/adapters/loa_cheval/metering/reprice.py` (new); `budget-allow.payload.schema.json:85` (`unpriced_window`), `budget-halt-uncertainty.payload.schema.json:79` (diagnostic fields) |
| 3 Docs + record | done | `docs/migration/v2.0-model-generation-floor.md:210-221`, `CHANGELOG.md:12` (`[Unreleased]` › Fixed), `cost-report.sh` header; REPO-MAP + `.checksum` sidecar + `.claude/checksums.json` regenerated together; this report |

## Technical Highlights

- **Window, not threshold.** The verdict is for one UTC day; the uncertainty that can invalidate "under budget" is that day's unpriced spend. The all-time share stays visible (`unpriced_share_all_time`) and remains the fallback when a report cannot provide a window, so an older `cost-report.sh` or a seam file in the old shape never makes the guard more permissive.
- **Prices exactly like a fresh row.** `reprice_row` uses the same `find_pricing` ladder (with the `resolved_model` hint, like `create_ledger_entry`) and `calculate_total_cost` with the row's `tokens_in` / `tokens_out` / `tokens_reasoning` / `tokens_cache_read` / `tokens_cache_creation`; `test_hop_row_is_repriced_with_marks_and_the_fresh_row_cost` pins equality with `create_ledger_entry` for the same tokens. A re-priced row is `cost_estimated: true` because it is priced after the fact at current catalog rates.
- **Byte discipline in the pass.** Only parseable lines that changed are re-serialised (`json.dumps(..., separators=(",", ":"))`, the writer's own format, original line ending kept); corrupt lines and unchanged rows are written back verbatim; the temp file is created in the ledger's directory, fsynced, mode-preserved and `os.replace`d; a failed pass unlinks the temp file and never touches the ledger. The bash guard refuses a symlink before Python runs and Python refuses again.
- **Seams stay bats-gated.** `LOA_BUDGET_COST_REPORT_SCRIPT` (new) and `LOA_BUDGET_COST_REPORT_JSON` are honoured only under the bats marker; UP-9 proves the production path ignores the stub and that it passes `--json --window-day <utc_day>`.

## Testing Summary

| Suite | Result |
|-------|--------|
| `tests/unit/cost-budget-enforcer-unpriced.bats` (UP-1..UP-9) + `tests/unit/cost-report.bats` (CR-1..CR-7) | 18/18 |
| `cost-budget-enforcer-remediation` + `-state-machine` + `-unpriced` | 61/61 |
| pytest `test_reprice_rows` + ladder + extended + cli_reported + headless metadata | 87 passed |
| E2E on a copy of this repository's ledger | allow for a clean day; halt for 2026-09-22; 37 rows re-priced once; repository ledger byte-identical |

## Known Limitations

- A re-priced row is priced at **today's** catalog rate for the hop's **current** `extra.cli_model`; the row records that (`cost_estimated: true`, `pricing_resolution: hop`, `resolved_model`) but the true historical rate is unknowable from the row. This is the documented meaning of the pass.
- `--reprice` loads the merged config from the project root (`load_config`), so the pass prices with the catalog of the repository it runs in; there is no `--config` override (deliberately: the same catalog the writer would use).
- The window is a UTC calendar day, matching the enforcer's `utc_day`; the report's `--days` totals are unchanged and unrelated.

## Verification Steps

```bash
bats tests/unit/cost-budget-enforcer-unpriced.bats tests/unit/cost-report.bats
(cd .claude/adapters && python -m pytest -q tests/test_reprice_rows.py tests/test_pricing_resolution_ladder.py)
cp .run/cost-ledger.jsonl /tmp/ledger-copy.jsonl
.claude/scripts/cost-report.sh --ledger /tmp/ledger-copy.jsonl --json --window-day "$(date -u +%Y-%m-%d)" | jq '{unpriced_share, window}'
LOA_RUN_DIR=/tmp/rp-run .claude/scripts/cost-report.sh --ledger /tmp/ledger-copy.jsonl --reprice --dry-run --json >/dev/null
```

## Files Changed

`.claude/scripts/lib/cost-budget-enforcer-lib.sh`, `.claude/scripts/cost-report.sh`, `.claude/adapters/loa_cheval/metering/reprice.py` (new), `.claude/data/trajectory-schemas/budget-events/budget-allow.payload.schema.json`, `.claude/data/trajectory-schemas/budget-events/budget-halt-uncertainty.payload.schema.json`, `tests/unit/cost-budget-enforcer-unpriced.bats`, `tests/unit/cost-report.bats`, `.claude/adapters/tests/test_reprice_rows.py` (new), `docs/migration/v2.0-model-generation-floor.md`, `CHANGELOG.md`, `grimoires/loa/REPO-MAP.md` + `.checksum`, `.claude/checksums.json`, `grimoires/loa/ledger.json` (bugfix cycle registration).
