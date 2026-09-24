# Security & Quality Audit — sprint-bug-245: the cost-budget enforcer halts permanently on historical unpriced ledger rows — round 1

**Auditor:** Paranoid Cypherpunk Auditor (Fable 5.1 lead acting as gate; independent input: cross-model security dissent gpt-5.5-pro over the diff only, no context file — `adversarial-audit.json`, status `reviewed`, 0 schema-valid findings, **1 schema-rejected payload hand-triaged below and confirmed**)
**Date:** 2026-09-24
**Scope:** `58016ae6` + the review round-1 fix over `main` `5f4a58a5` — `.claude/scripts/lib/cost-budget-enforcer-lib.sh`, `.claude/scripts/cost-report.sh` (`--window-day`, `--reprice`), new `.claude/adapters/loa_cheval/metering/reprice.py`, two payload schemas, two bats suites, one pytest suite, migration guide, CHANGELOG
**Prerequisite:** `engineer-feedback.md` reads `All good` (review round 1, trailer consistent: 0/0/0/3, `excluded: 0`)
**Methodology:** sources → sinks over the diff (1A/1B), independent dissent with hand-triage of the rejected sidecar (1C), five-category pass (Security, Architecture, Code Quality, DevOps; Blockchain n/a)

---

## Executive Summary

The window half of the fix is sound: the enforcer's new input is the same report it already trusted, scoped by a regex-validated day, with a fallback that can only make the guard stricter, and the seams stay bats-gated. The **re-pricing half writes the live cost ledger**, and its write path has two real defects: it replaces the ledger's inode without taking the writer's lock, so a concurrent `append_ledger` can land on the orphaned old inode and be lost; and its backup and receipt writes follow a pre-planted dangling symlink. The dissent's rejected payload adds a third, smaller point: the row's own `resolved_model` is used as a pricing authority. None of this is exploitable without local write access to the repository, but the ledger is the artefact the budget enforcer certifies from, and a maintenance pass must not be able to lose or misprice its rows. **CHANGES_REQUIRED** — three fixes, each with a test.

**Overall Risk Level:** MEDIUM (write path of a maintenance pass over the enforcer's evidence)

---

## Phase 1A/1B — Sources and sinks in the diff

| # | Source (trust) | Sink | Guard on the path | Status |
|---|---|---|---|---|
| S1 | `utc_day` (enforcer-computed, or `LOA_BUDGET_TEST_NOW` under test) | `cost-report.sh --json --window-day` argv (`cost-budget-enforcer-lib.sh:1280`) | regex `^\d{4}-\d{2}-\d{2}$` at the report (`cost-report.sh:146-149`); passed as one argv word | SAFE |
| S2 | report JSON (repository script output) | `jq` window extraction (`:1299-1305`) | typed predicate (`window.unpriced_share` must be a number) else all-time; malformed → null shape | SAFE |
| S3 | `LOA_BUDGET_COST_REPORT_SCRIPT` (env) | `bash <path>` (`:1285-1286`) | bats marker required; UP-9 proves it is ignored otherwise | SAFE (test-only) |
| S4 | `--ledger` path (operator) | read + **in-place replacement** (`cost-report.sh:271-352`) | `-L` refusal in bash and `islink` in Python; `os.replace` of a temp file | **DEFECTIVE — see F-1** |
| S5 | `<ledger>.pre-reprice-<stamp>` (computed name in a directory the operator controls) | `shutil.copy2` (`:328`) | `os.path.exists` loop — does not see a dangling symlink; `copy2` follows it | **DEFECTIVE — see F-2** |
| S6 | `.run/cost-ledger-reprice-<stamp>.json.tmp.<pid>` | `open(tmp, "w")` (`:347`) then `os.replace` | none on the temp open | **DEFECTIVE — see F-2** |
| S7 | ledger row fields (`provider`, `model`, `resolved_model`, tokens) | `find_pricing` / `calculate_total_cost` (`reprice.py:62-75`) | provider/model are catalog keys, tokens coerced to int; `resolved_model` is taken from the row as a second lookup key | **F-3** |
| S8 | merged config (`load_config(project_root)`) | pricing rates | same trust as the writer | SAFE |
| S9 | receipt contents | `.run/` JSON | counts, paths and sha256s only (CR-7 asserts no row contents) | SAFE |

## Findings

### F-1 — HIGH (confidence: high) `.claude/scripts/cost-report.sh:337-341` — the pass replaces the ledger inode without the writer's lock; a concurrent append can be lost

`append_ledger` (`loa_cheval/metering/ledger.py:212-236`) opens the ledger with `O_APPEND|O_NOFOLLOW`, then takes `flock(LOCK_EX)` on that fd and writes. The pass reads the file with a plain `open()`, computes for as long as the config load and the ladder take, then `os.replace(tmp, ledger)` — never holding the lock. Two failure shapes: (a) a row appended between the read and the replace is dropped from the new file; (b) an appender that opened the old inode before the replace and locks after it writes to the orphaned inode — the row is gone even though `append_ledger` returned success. Failure scenario: `cost-report.sh --reprice` run on a mount while `cheval` is dispatching (the normal state of a mount) silently loses the in-flight rows, and the enforcer certifies the next day from a ledger missing spend. **Fix:** open the ledger `O_RDWR|O_NOFOLLOW`, take `flock(LOCK_EX)` on that fd, read and parse *under the lock*, write the backup, then `ftruncate` + write + `fsync` **the same inode** and release — the writer's own discipline, so an appender blocks and then appends after the new content; the byte copy taken first (fsynced) is the crash-recovery point named in the receipt. `--dry-run` takes `LOCK_SH`. Test: the pass blocks while a test holds `LOCK_EX` on the ledger, the inode is unchanged afterwards, and a row appended through `append_ledger` after the pass is present.

### F-2 — MEDIUM (confidence: high) `.claude/scripts/cost-report.sh:324-328` and `:344-349` — backup and receipt writes follow a pre-planted dangling symlink

`while os.path.exists(backup)` skips a *dangling* symlink (exists() follows and returns False), and `shutil.copy2(ledger, backup)` then opens the symlink for writing — the ledger's bytes are written wherever the link points. The receipt temp file `open(tmp, "w")` has the same shape (the migration receipt at `:196-200` too — pre-existing, same class). Failure scenario: a local actor who can create files in the ledger's directory or `.run/` plants `cost-ledger.jsonl.pre-reprice-<next stamp>` → `~/.bashrc`; the operator's pass overwrites it. **Fix:** create the backup and the receipt temp with `os.open(path, O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW, mode)` (EEXIST for a symlink of any kind → try the next `-N` name), use `os.path.lexists` in the name loops, and `os.replace` the temp onto the receipt name (rename never follows). Apply the same to the migration receipt while there. Test: a dangling symlink planted at the computed backup name and at the receipt name (stamp injected) is not followed — its target never appears; the files land under the next `-N` name.

### F-3 — MEDIUM (confidence: medium) `.claude/adapters/loa_cheval/metering/reprice.py:62-64` — the row's own `resolved_model` is a pricing authority (dissent payload, schema-rejected for a missing `failure_mode`, hand-confirmed)

When `find_pricing(provider, model)` fails, the pass retries with `row["resolved_model"]` and then stamps the row `pricing_source: config`. The hint is ledger content: a row that names an unresolvable `model` but carries `resolved_model: "gpt-5.5"` becomes a config-priced row for a catalog id that the config never mapped it to. `create_ledger_entry` does the same at write time, but there the hint comes from the adapter that made the call; here it comes from the file being repaired. Every row this pass exists for (`codex-headless` etc.) resolves through the config-owned hop mapping without any hint, and rows that carry `resolved_model` at all post-date the ladder and are already priced — the hint path adds risk and no reach. Failure scenario: a hand-edited or corrupted historical row is converted into trusted priced spend (or trusted *cheap* spend) by the operator's pass, changing `unpriced_rows` and the certified totals. **Fix:** drop the hint fallback; price only through `find_pricing(provider, model, config)` (config-owned exact/dated/alias/hop). Test: an unresolvable `model` with a `resolved_model` hint stays unpriced.

### F-4 — LOW (confidence: high) `.claude/scripts/cost-report.sh:196-200` — migration receipt temp file has the F-2 shape (pre-existing)

Same class as F-2, in the block this sprint mirrored. Fix alongside with the shared receipt writer; noted so the class is closed in one place.

## Category pass

| Category | Notes |
|---|---|
| Security | F-1..F-4 above. No secrets, no network, no privilege change; env seams bats-gated; `--window-day` validated; receipt carries no row contents. |
| Architecture | Window-scoped measurement with a stricter-only fallback is the right shape; the pass belongs in `loa_cheval.metering` (pure function) with the file handling next to it — after F-1/F-2 the file handling should live there too (unit-testable with an injected stamp) rather than in a heredoc. |
| Code Quality | Byte discipline for untouched lines is good; `json.dumps(separators=(",", ":"))` matches the writer; `_rp_rc` capture fixed in review. |
| DevOps | REPO-MAP + sidecar + checksums regenerated together; CHANGELOG `[Unreleased]` and migration guide updated; the migration guide should say the pass takes the writer's lock and is safe against a live writer once F-1 lands. |

## Verdict

CHANGES_REQUIRED — F-1 (HIGH) must land with its test; F-2 and F-3 (MEDIUM) and F-4 (LOW) are cheap to close in the same round. Re-audit with a fresh dissent over the new diff.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":2,"low":1},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-bug-245","ts":"2026-09-24T01:48:00Z"} -->
