APPROVED - LET'S FUCKING GO

# Security & Quality Audit — sprint-bug-245: the cost-budget enforcer halts permanently on historical unpriced ledger rows — round 2 (final)

**Auditor:** Paranoid Cypherpunk Auditor (Fable 5.1 lead acting as gate; independent input: cross-model security dissent gpt-5.5-pro over the diff only, no context file — three runs: round 1 `adversarial-audit-r1.json` (1 schema-rejected payload, hand-confirmed as F-3), round 2 over the F-1..F-4 fixes (1 schema-rejected payload, hand-confirmed and fixed in-round: negative token counts), round 3 over the committed final diff `adversarial-audit.json`: status `reviewed`, 0 findings, 0 rejected payloads, `verdict_quality.status APPROVED`, `chain_health ok`)
**Date:** 2026-09-24
**Scope:** `58016ae6` + `e577f66f` + the round-2 fix commit over `main` `5f4a58a5` — enforcer lib, cost-report (`--window-day`, `--reprice`), `loa_cheval.metering.reprice` (pure functions + `reprice_ledger_file`), two payload schemas, two bats suites, two pytest suites, migration guide, CHANGELOG
**Prerequisite:** `engineer-feedback.md` reads `All good` (review round 1, trailer consistent: 0/0/0/3, `excluded: 0`); round-1 audit `auditor-sprint-feedback-r1.md` CHANGES_REQUIRED (1 HIGH, 2 MEDIUM, 1 LOW) — all four verified fixed below
**Methodology:** sources → sinks over the final diff (1A/1B), three independent dissents with hand-triage of every rejected payload (1C), five-category pass

---

## Executive Summary

Round 1 found the re-pricing pass replacing the ledger inode without the writer's lock (F-1 HIGH), following planted symlinks on its backup and receipt writes (F-2 MEDIUM), taking a pricing authority from the row it was repairing (F-3 MEDIUM), and the same symlink shape in the older migration receipt (F-4 LOW). Round 2 verified each fix in code and test, and the second dissent surfaced one more input-validation hole (a negative token count would have become a negative priced cost) that was closed in-round with a test. The third dissent over the committed final diff is clean. The window half of the fix was sound from the start and is unchanged. The pass now holds the same `flock` the writer holds, rewrites the same inode, creates every side file `O_EXCL|O_NOFOLLOW`, prices only through config-owned mappings, and refuses to write anything it cannot price non-negatively. **APPROVED.**

**Overall Risk Level:** LOW

---

## Round-1 findings — verification

| Finding | Fix (file:line) | Proof |
|---|---|---|
| F-1 HIGH — inode replaced without the writer's lock | `reprice_ledger_file` opens `O_RDWR\|O_NOFOLLOW` and takes `flock(LOCK_EX)` on that fd before reading (`.claude/adapters/loa_cheval/metering/reprice.py:236-241`), rewrites the same inode with `lseek`/`ftruncate`/write/`fsync` (`:280-284`), releases in `finally` (`:290-293`); dry-run takes `LOCK_SH` (`:239`) | `test_reprice_ledger_file.py::test_holds_the_writers_lock_and_a_later_append_survives` (the pass blocks while the test holds `LOCK_EX`; a real `append_ledger` row lands third afterwards), `::test_rewrites_the_same_inode_in_place_and_keeps_untouched_lines_verbatim`; `cost-report.bats` CR-7 asserts the inode is unchanged |
| F-2 MEDIUM — backup/receipt followed a dangling symlink | `_create_exclusive` (`reprice.py:167-180`: `O_WRONLY\|O_CREAT\|O_EXCL\|O_NOFOLLOW`, next `-N` on `EEXIST`), `write_receipt` (`:183-198`: `lexists` loop, exclusive temp, `os.replace`), backup fsynced before the in-place write (`:266-273`) | `::test_backup_and_receipt_never_follow_a_planted_symlink` (dangling symlinks at the computed backup and receipt names: targets never appear, files land under `-2`, plants untouched), `::test_symlinked_ledger_is_refused_before_any_write` |
| F-3 MEDIUM — row-supplied `resolved_model` as pricing authority | fallback removed; only `find_pricing(provider, model, config)` decides (`reprice.py:93-95`) | `test_reprice_rows.py::test_resolved_model_hint_on_the_row_is_never_a_pricing_authority`, `test_reprice_ledger_file.py::test_row_supplied_resolved_model_is_not_a_pricing_authority` |
| F-4 LOW — migration receipt temp file | `--migrate-legacy` writes its receipt through the shared `write_receipt` (`.claude/scripts/cost-report.sh`, migration block) | CR-3 / CR-3b unchanged and green |

## Round-2 dissent payload (schema-rejected, hand-confirmed, fixed in-round)

- **MEDIUM** (confidence: high) `reprice.py:96-109` — a crafted unpriced row with a negative `tokens_*` field would have been re-priced into a **negative** `cost_micro_usd` (`calculate_total_cost` multiplies), lowering certified totals; an overflowing count would have raised out of the pass. Fixed: any negative token field, any pricing exception (`BUDGET_OVERFLOW`), or a negative computed total leaves the row unpriced; one bad row never aborts the pass. Test: `test_reprice_rows.py::test_negative_or_overflowing_token_counts_stay_unpriced_and_never_price_negative` (negative input, negative cache, 10^30 tokens: all three stay `unknown` at cost 0 while the good row is priced). Recorded here rather than as a fourth round because the fix is a pure guard with its own test and the round-3 dissent ran over the tree that contains it.

## Phase 1A/1B — Sources and sinks in the final diff

| # | Source (trust) | Sink | Guard on the path | Status |
|---|---|---|---|---|
| S1 | `utc_day` | `cost-report.sh --json --window-day` argv | `^\d{4}-\d{2}-\d{2}$` before any file is touched; one argv word | SAFE |
| S2 | report JSON | `jq` window extraction | typed predicate; malformed → null shape; no window → all-time (stricter) | SAFE |
| S3 | `LOA_BUDGET_COST_REPORT_SCRIPT` / `_JSON` (env) | stub exec / file read | bats marker required (UP-9 proves production ignores them) | SAFE (test-only) |
| S4 | `--ledger` path (operator) | `os.open(O_RDWR\|O_NOFOLLOW)` + `flock` + in-place rewrite | symlink → `RepriceRefused` before any write; lock held read→write; same inode | SAFE |
| S5 | backup / receipt names | `_create_exclusive` | `O_EXCL\|O_NOFOLLOW`, `-N` on collision, `lexists` loops, rename-into-place | SAFE |
| S6 | row fields (`provider`, `model`, tokens) | ladder + `calculate_total_cost` | catalog keys only; ints; negatives/overflow/negative totals → row stays unpriced; `resolved_model` ignored | SAFE |
| S7 | merged config | rates | the writer's own trust | SAFE |
| S8 | receipt | `.run/` JSON | counts, paths, sha256s, lock note — no row contents (CR-7, pytest) | SAFE |

## Category pass

| Category | Notes |
|---|---|
| Security | No secrets, no network, no privilege change. The write path now matches the writer's own discipline (lock + `O_NOFOLLOW`) and adds exclusive creation for side files. |
| Architecture | File handling lives beside the pure functions in `loa_cheval.metering.reprice` with an injectable `stamp` — unit-testable; the bash block is a thin caller. Window scoping is additive to the report. |
| Code Quality | Untouched lines verbatim; writer-format serialisation; `_rp_rc` reachable; stats keys fixed and asserted. |
| DevOps | REPO-MAP + sidecar + checksums regenerated together; CHANGELOG `[Unreleased]` and the migration guide describe the lock, the no-follow creation and the authority rule. |

## Documentation audit

CHANGELOG `[Unreleased]` › Fixed describes both halves and the write-path guarantees; `docs/migration/v2.0-model-generation-floor.md` (rc.2 addendum, cost-history paragraph) tells operators the per-day rule, `--reprice --dry-run` → `--reprice`, that the pass holds the writer's lock and where the recovery copy is; `cost-report.sh --help` and header list the new flags.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":0},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-bug-245","ts":"2026-09-24T01:55:00Z"} -->
