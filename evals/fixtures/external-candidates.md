# External corpus candidates (cycle-133 Sprint 3 Task 3.3)

Three public pull requests dry-run through `evals/harness/seed-corpus-from-external.sh` on 2026-10-24.
These were network reads of public GitHub only: `gh api` and a blobless `git clone` with one batched blob fetch.
No model was called. Nothing was written to the corpus. Each dry-run left only a temporary tree and its report.

## Selection criteria

- **Post-cutoff fix.** The fix commit is dated after the Fable 5.1 knowledge cutoff (2026-06).
- **Documented defect.** The fix PR names the introducing PR, and the fix touches a file that PR changed. The seeder refuses a fix that does not.
- **Size bounds.** The fetched files fit `--max-files 5000` and `--max-bytes 200M`, checked from tree metadata before any blob is fetched.
- **Harness language.** Python, TypeScript or shell. The fixtures run with `runtime: none`.
- **Permissive licence.** The GitHub licence API reports an SPDX id in the allowlist: MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause or ISC.

## Candidates

| Fixture id (dry-run) | Reviewed PR | Fix | Language | Licence | Fix date |
|---|---|---|---|---|---|
| pr-90 | https://github.com/keras-team/keras/pull/23938 | https://github.com/keras-team/keras/pull/24056 (`d7b8ca0c`, "Fix floor_divide regression from #23938") | Python | Apache-2.0 | 2026-10-23 |
| pr-91 | https://github.com/transitmatters/t-performance-dash/pull/1180 | https://github.com/transitmatters/t-performance-dash/pull/1191 (`5a298926`, "Fix stripmap stuck loading forever (regression from #1180)") | TypeScript | MIT | 2026-09-24 |
| pr-92 | https://github.com/ionic-bond/twitter-monitor/pull/22 | https://github.com/ionic-bond/twitter-monitor/pull/24 (`dbc86a89`, "Prevent main tweet text overwrite by nested note_tweet nodes (Regression from #22)") | Python | MIT | 2026-10-23 |

The commands, one per candidate:

```
seed-corpus-from-external.sh https://github.com/keras-team/keras 23938 --fix d7b8ca0c007e3e624f2bb4058802ae44871b86da --dry-run --out pr-90
seed-corpus-from-external.sh https://github.com/transitmatters/t-performance-dash 1180 --fix 5a298926890bac000cc6edb271282ee2990b7674 --dry-run --out pr-91
seed-corpus-from-external.sh https://github.com/ionic-bond/twitter-monitor 22 --fix dbc86a8999e5702db5477592ec58832c3efb296c --dry-run --out pr-92
```

## Results

```
pr-90 keras-team/keras#23938: 2 head file(s), 2 base file(s), diff 3037 B, 2 fix row(s), licence Apache-2.0, fix 2026-10-23 (after the 2026-06 cutoff), trees committed, 0 skipped; SHA256SUMS 20 files
  limits: 8 file(s), 1542395 byte(s) fetched (bounds 5000 / 209715200); fix diff 681 B
  --check: corpus OK: 20 files match SHA256SUMS / external OK: 1 external fixture(s)
pr-91 transitmatters/t-performance-dash#1180: 1 head file(s), 1 base file(s), diff 1149 B, 3 fix row(s), licence MIT, fix 2026-09-24 (after the 2026-06 cutoff), trees committed, 0 skipped; SHA256SUMS 18 files
  limits: 5 file(s), 10433 byte(s) fetched; fix diff 898 B
  --check: corpus OK: 18 files match SHA256SUMS / external OK: 1 external fixture(s)
pr-92 ionic-bond/twitter-monitor#22: 1 head file(s), 1 base file(s), diff 696 B, 3 fix row(s), licence MIT, fix 2026-10-23 (after the 2026-06 cutoff), trees committed, 0 skipped; SHA256SUMS 18 files
  limits: 4 file(s), 19881 byte(s) fetched; fix diff 810 B
  --check: corpus OK: 18 files match SHA256SUMS / external OK: 1 external fixture(s)
```

`seed-corpus-from-record.sh --corpus <temporary corpus> --check` also passed on all three trees.

**No model call.** The dry-runs ran from 2026-10-24T08:33:34Z to 08:34:53Z with `claude`, `codex` and `cheval` shimmed on PATH to log and fail. The log holds 21 `gh api` reads and no model-CLI call. The cost ledger gained no row in that window:

```
spend.sh --since 2026-10-24T08:33:34Z --ledger .run/cost-ledger.jsonl
cycle spend USD 0.00 (runs 0.00 + ledger 0.00 since 2026-10-24T08:33:34Z)
```

## Rejected

https://github.com/Meliox/PVE-mods/pull/357, with the fix https://github.com/Meliox/PVE-mods/pull/363 (`c1b1067c`), was refused with exit 2. The fix edits `PveMods_pvemanagerlib.js`, a file the PR never changed, so the PR is not where the fixed defect was introduced.
