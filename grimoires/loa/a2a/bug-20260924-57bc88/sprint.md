# Sprint Plan: Bug Fix — The cost-budget enforcer halts permanently on historical unpriced ledger rows (all-time share, no sanctioned re-pricing pass)

**Type**: bugfix
**Bug ID**: 20260924-57bc88
**Source**: /bug (triage) — follow-up bead `bd-ypbg` from cycle-125 sprint-244 E2E G-5; maintainer instruction "proceed as you suggest" (2026-09-24)
**Sprint**: sprint-bug-245

---

## sprint-bug-245: The cost-budget enforcer halts permanently on historical unpriced ledger rows

### Sprint Goal
Fix the reported bug with failing tests proving the fix: the enforcer measures the unpriced share over the UTC day it certifies (an unpriced row inside that day still halts; a report without a window keeps the all-time share), and `cost-report.sh --reprice` is an explicit, opt-in, receipted pass that re-prices the historical rows the ladder can now resolve, marking each changed row instead of rewriting history silently.

### Deliverables
- [x] Failing tests that reproduce the bug (`tests/unit/cost-budget-enforcer-unpriced.bats` UP-6..UP-9, `tests/unit/cost-report.bats` CR-6..CR-7, `.claude/adapters/tests/test_reprice_rows.py`)
- [x] Source code fix (`cost-report.sh --window-day` / `--reprice`, `loa_cheval/metering/reprice.py`, enforcer window + seams, additive payload schema fields)
- [x] All existing tests pass (no regressions)
- [x] Triage analysis document

### Technical Tasks

#### Task 1: Write Failing Tests [G-5]
- Create unit tests reproducing the bug
- Verify tests fail with current code
- Test files: `tests/unit/cost-budget-enforcer-unpriced.bats` (4 cases), `tests/unit/cost-report.bats` (2 cases), `.claude/adapters/tests/test_reprice_rows.py` (5 cases)

**Acceptance Criteria**:
- Tests fail with current code, proving the bug exists: a report with all-time share 0.685 and window share 0 still halts; no `window` object in `cost-report.sh --json`; `--reprice` is an unknown option; `loa_cheval.metering.reprice` does not exist
- Test names clearly describe the bug scenario
- Tests are isolated (temp ledgers under `--ledger` / `LOA_RUN_DIR`; the repository's `.run/cost-ledger.jsonl` and `grimoires/loa/a2a/cost-ledger.jsonl` are byte-identical after every case; enforcer cases stay hermetic under bats)

#### Task 2: Implement Fix [G-1, G-2]
- Fix root cause in `.claude/scripts/lib/cost-budget-enforcer-lib.sh` (window-scoped share with all-time fallback; `--window-day <utc_day>` passed; diagnostic + allow payload fields; bats-gated stub-script seam), `.claude/scripts/cost-report.sh` (`--window-day`, `--reprice [--dry-run]`), new `.claude/adapters/loa_cheval/metering/reprice.py`, the two budget payload schemas (additive)
- Verify failing tests now pass
- Run the touched suites and the neighbours: `cost-budget-enforcer-*.bats`, `cost-report.bats`, `test_pricing_resolution_ladder.py`, `test_pricing_extended.py`, `test_cli_reported_cost.py`, `test_reprice_rows.py`

**Acceptance Criteria**:
- Failing tests now pass
- No regressions in existing tests
- Fix addresses root cause (the guard measures the day it certifies; history is re-priced only explicitly, with marks and a receipt), not just symptoms (no threshold change, no ledger hand-edit)

#### Task 3: Documentation and record
- Migration guide "Your pre-2.0 cost history" paragraph (per-day rule, `--reprice`), `cost-report.sh` header, CHANGELOG `[Unreleased]` entry
- `repo-map-gen.sh` regen + `--validate` (+ `.checksum` sidecar), `.claude/checksums.json` regen, `bash -n` on touched scripts
- `reviewer.md` with `## AC Verification` (file:line per row) and the E2E: `budget_verdict` on a copy of this repository's ledger allows for a clean day, and `--reprice --dry-run` on that copy reports the 37 resolvable rows

### Acceptance Criteria
- [x] Bug is no longer reproducible: on a copy of this repository's ledger the verdict for a day without unpriced rows is `allow`; a day with unpriced rows above 5 % still halts; `--reprice` on the copy re-prices the 37 `codex-headless` rows through the hop with marks and a receipt, and a second run re-prices 0
- [x] Failing test proves the fix
- [x] No regressions in existing tests
- [x] Fix addresses root cause (not just symptoms)

### Triage Reference
See: grimoires/loa/a2a/bug-20260924-57bc88/triage.md
