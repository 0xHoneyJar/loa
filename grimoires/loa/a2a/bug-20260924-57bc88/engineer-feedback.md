All good

Observations documented and non-blocking. See Observations below.

# sprint-bug-245 Review Feedback — round 1

**Reviewer:** Senior Tech Lead Reviewer Agent (Fable 5.1 lead acting as gate; independent input: cross-model dissent gpt-5.5-pro through the `codex-headless` voice over the sprint diff plus the triage as context — `adversarial-review.json`, status `clean`, 0 findings, 0 schema-rejected payloads, `verdict_quality.status APPROVED`, `chain_health ok`)
**Date:** 2026-09-24
**Bug:** 20260924-57bc88 — the cost-budget enforcer halts permanently on historical unpriced ledger rows · **Bead:** `bd-ypbg` · **Plan:** `grimoires/loa/a2a/bug-20260924-57bc88/sprint.md`
**Implementation Report:** `grimoires/loa/a2a/bug-20260924-57bc88/reviewer.md`
**Range:** `58016ae6` over `main` `5f4a58a5` (`v2.0.0-rc.2`) — enforcer lib, cost-report, new `loa_cheval.metering.reprice`, two payload schemas, two bats suites, one pytest suite, migration guide, CHANGELOG, ledger, plus regenerated REPO-MAP + sidecar + checksums

---

## Overall Assessment

The bug is real and reproduced against this repository's own ledger: the FR-5 guard took `cost-report.sh --json`'s all-time `unpriced_share` (0.685 here) and halted every verdict, for every day, with no sanctioned way to change the historical rows. The fix goes to both roots and does not move the threshold.

- **The guard now measures what it certifies.** `budget_check` passes its own `utc_day` (`.claude/scripts/lib/cost-budget-enforcer-lib.sh:1237`); `_l2_unpriced_share_json` asks the report for that day (`:1280`, `:1290`/`:1296` via `--json --window-day`) and takes the `window` share only when the report actually carries a numeric one (`:1299-1305`) — otherwise the all-time share, so an older report or a seam file in the old shape can only make the guard *stricter*, never looser (UP-8). An unpriced row inside the window still halts (UP-7; E2E 2026-09-22 → `halt-uncertainty`, `unpriced_share 0.724`, `window_day 2026-09-22`, `unpriced_share_all_time 0.685`). The allow payload carries `unpriced_window` (`:1256`), the diagnostic carries the window day and the all-time numbers (`:1243-1244`); both schema changes are additive (`budget-allow.payload.schema.json:85`, `budget-halt-uncertainty.payload.schema.json:79`) and the state-machine and remediation suites that validate payloads stay green (61/61).
- **Seams stay bats-gated.** The new `LOA_BUDGET_COST_REPORT_SCRIPT` stub path is honoured only under the bats marker (`:1284-1286`); UP-9 proves both the argv contract (`--json --window-day 2026-05-04`) and that the production path ignores the stub (`argv.txt` stays empty, the real report answers with `window_day`). The array expansion uses the `${a[@]+"${a[@]}"}` guard, so `set -u` callers are safe when no day is passed (UP-5 still calls the helper with no argument).
- **The report is additive.** `--window-day` only adds a `window` object / one markdown line (`.claude/scripts/cost-report.sh:562-568`, `:595`); every existing JSON field keeps its all-time meaning (CR-1..CR-5 unchanged, CR-6 asserts the all-time counts next to the window). The day format is validated before any file is touched (`:146-149`, `yesterday` → exit 2).
- **The pass is explicit and reversible.** `--reprice` is opt-in; `--dry-run` writes nothing (CR-7 sha check, no receipt). `reprice_row` prices through the same ladder and cost function as a fresh row and `test_hop_row_is_repriced_with_marks_and_the_fresh_row_cost` pins equality with `create_ledger_entry` (`.claude/adapters/tests/test_reprice_rows.py:52`); `reprice_rows` returns the *same object* for every untouched row (`reprice.py:106`, `:111`) and the file writer only re-serialises lines whose object identity changed, in the writer's own compact format with the original line ending (`cost-report.sh:333-336`), so priced rows, unresolvable rows and corrupt lines stay byte-identical (CR-7 `l3/l4/l5`). Symlink refused in bash before Python and again in Python; byte copy before the write (`:328`); temp file in the ledger's directory, fsynced, mode-preserved, `os.replace`d (`:341`); receipt holds counts and sha256s only (CR-7 `! grep tokens_in`); a second pass re-prices 0, makes no backup and still leaves a receipt (idempotence proven).
- **Repository ledgers untouched.** Every bats case runs on temp ledgers with `LOA_RUN_DIR` redirected; `cost-report.bats` teardown asserts both repository ledgers byte-identical after each case; the E2E ran on a copy and the live ledger's sha256 was unchanged.
- **Karpathy.** Assumptions stated in `reviewer.md` (UTC calendar day = `utc_day`; today's rate for the hop's current `cli_model`, marked `cost_estimated`; catalog from the project root, deliberately no `--config`). No new configuration key.

**Verdict:** APPROVED

---

## Observations

### 1. Exit-code capture under `set -e` (resolved in this round)

- **LOW** (confidence: high) `.claude/scripts/cost-report.sh:289` — as first submitted the `--reprice` heredoc was followed by `_rp_rc=$?`; under the script's `set -euo pipefail` a non-zero Python exit ends the script before that line, so the "a failed pass never replaces the ledger" message could never print (the exit code was still non-zero, and CR-7's symlink case is caught by the bash `-L` guard first). Resolved in-round: `_rp_rc=0; … <<'PYREP' || _rp_rc=$?` — the message is reachable and the exit code is preserved. The older `--migrate-legacy` block carries the same pre-existing pattern; left alone here (out of this bug's scope), noted for the audit.

### 2. Flag-without-value handling (pre-existing pattern)

- **LOW** (confidence: high) `.claude/scripts/cost-report.sh:111-113` — `--window-day` as the last argument sets `WINDOW_DAY=""` and then `shift 2` fails under `set -e` with bash's own message, like every other value-taking flag in this script (`--ledger`, `--days`, `--top`, `--legacy-ledger`). A malformed value is rejected cleanly (`:146-149`, exit 2 with the expected format). Not worth a special case in this bug.

### 3. What the window does not cover (documented)

- **LOW** (confidence: high) `.claude/scripts/cost-report.sh:500-507` — a row whose `ts` does not parse falls in no window (it stays in the all-time counts). Such rows are not produced by the writer; the behaviour is the honest one (no day → no membership) and is listed under Known Limitations in `reviewer.md`.

---

## Next Steps

1. `/audit-sprint sprint-bug-245` — independent dissent (no context file).
2. Commit the round-1 fix (`_rp_rc` capture) with the review record; then sprint-bug-246.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":3},"excluded":0,"sprint_id":"sprint-bug-245","ts":"2026-09-24T01:40:00Z"} -->
