# Sprint 273 Task 2.2 — implementer B (sdd.md C-7, FR-7)

Worktree loa-wt-s2b, 38640409e. Patch: `~/.cache/loa/cycle-133/patches/s2-b.{patch,stat}`.

## Incident
My red run of the OLD `final.sh` changed one tracked file in the lead's tree. The old script hard-codes `cd /home/merlin/Documents/thj/code/loa`, and the test HOME held a valid registration.txt. The file is `grimoires/loa/reports/ablation-2.0/c132-final/INPUTS.json`, whose `pin` now reads f×40 (one line). `rows.jsonl` was rewritten byte-identically. Nothing else changed, and no model call ran. The lead was messaged. Restore with `git -C /home/merlin/Documents/thj/code/loa checkout -- grimoires/loa/reports/ablation-2.0/c132-final/INPUTS.json`.

## What was built
- **`reproduce.sh` (bd-jat0z, bd-161zz)**. The pipeline paths are diffed against the pin at :84. The analysis paths plus the two analysis-side tools are diffed against ANALYSIS_PIN 6f01e57d (REGISTRATION-17's `analysis_tree`) at :51 and :85.
  - The porcelain check covers untracked files, with bytecode caches excepted (:79, :86). `git describe --always --dirty` is recorded (:81).
  - environment.json fields: `pinned_trees_identical_to_worktree`, `environment_matches`, `env_check`.
  - Exit 2 refuses before any write, with one stderr line (:106). The exit table is 0/1/2/3.
  - The live sample is gated on engine exit 0 and a matched environment; otherwise a "not run" section and exit 3 (:130).
  - `--pre-registration-ref` names `$REG` and its sha256 (:146). The range uses valid rows only, through `common.build_cell` on the row plus its grade (:171), and the invalid rows are named. The table carries an environment line.
  - Outside the range: exit 0, named. Runner failure or a missing arm: exit 3. A heredoc failure no longer aborts under `set -e`.
  - Flags `--pin`, `--analysis-pin`, `--registration`. Hashing uses hashlib, not sha256sum.
- **`record_lite.py` (bd-ombvn)**. `sha256_file(verify=)` at :92: realpath plus a following stat with ctime as the key, and verify bypasses the cache.
  - Verify is used by the copy check (:401), reconstruct's lite files (:504) and pr/ files (:523, hashed fresh), and `file_sha` (:568).
  - An unsafe symlink target raises Mismatch (:515). The docstring names INDEX-only.json.
- **`judge_defects.py` (bd-xr3uq)**.
  - Sampling: `sample_id_of`, `with_sample_id` and `stamp_packet` (:72–88). `write_sample(force=)` at :509, with the CLI flag `--force`. Packet line 3 reads ``Sample: `<id>` ``.
  - Aggregation: `load_labels` needs a sample_id. `bind` at :594, `load_grades` at :610, `run(…, grades)` at :684. `aggregate --results-root` is required.
- **`final.sh` (bd-o3a5h)**. The root comes from BASH_SOURCE (:15). It takes flags or parses the file by whitelist (:29), validates REG, PIN and REG_SHA, and checks REG_SHA against the file.
- **`run-judge-defects.sh` (bd-o3a5h, bd-xr3uq)**. The root comes from BASH_SOURCE (:16). The chunk dir is named by the key sha and holds KEY_SHA256 (:34).
  - It refuses packets that lack the key's sample_id. It stamps labels.json and moves stale sessions aside and reruns them (:52). New flags `--cache` and `--prompt`.
- **`spend.sh` (bd-um8ol C-006)**. Dedup by `(run_id, batch)` (:191). Anonymous rows dedup across files by content (:148, :182).
- **`tests/synth.py` (bd-qxwrm)**. `power_mini_diffs` (:110) and the CLI `power-mini-diffs --seed 20261023`. The four committed head.diff files (4,976 lines) are removed. `test_power.py` generates them in setUpModule and AC-4 into `$T/fx`.
- **REPRODUCE.md**. A new § 0 says which tooling reproduces cycle-132 and names INDEX.json and INDEX-only.json. No other change.
- **evals/tests**. AC-1 pins its count from `tests/COUNT` (215). MV-1 drops the `main:` clause.

## Tests
| suite | before | after |
|---|---|---|
| pytest evals/analysis/c132/tests | 182 | 232 passed |
| unittest discover (AC-1) | 176 | 215 OK |
| spend.bats | 12/12 | 12/12 |
| evals/tests bats, whole dir | AC-1, MV-1 red | 702/702, exit 0 |

Every new case was run red first, then green.
- `test_reproduce.py`: 17 cases, 15 red. Dirty, untracked and committed drift against both pins; caches ignored; `--no-env-check` never asserts a match; engine failure, environment mismatch, runner failure and a missing arm each exit 3; the `$REG` hash; the valid-row range; outside-range exit 0; any cwd.
- `test_record_lite.py`: 11 new, 9 red. verify; same-size same-mtime rewrites of a lite file and of a fixture file; compare hashes fresh; four unsafe targets; a safe target recreated; INDEX-only. The symlink-key case passed on the old code and is a regression guard.
- `test_judge_defects.py`: 5 new and 3 reworked, 8 red. The sample_id in the key and packets; `--force`; stale labels on a new key; grade-loaded validity; `--results-root` required; a session without a sample_id; an edited key.
- `test_drivers.py`: 10 cases, 10 red. Any cwd with no cache; the whitelist parse; five shell-code or unknown-token files refused with nothing executed; REG_SHA mismatch; chunks by key sha; stamped labels; a stale rerun; bad packets, bad key and a foreign chunk dir refused.
- `test_synth_power_mini.py`: 5 cases, red. Legacy headers match the removed files' sha256. Correct headers keep the body sha256s. `git apply --check` accepts the generated diffs and rejects the legacy ones. Before removal `cmp` matched all four, and `power.py` output was identical on both.
- `test_spend.py`: 3 cases, 2 red.

## Acceptance criteria (FR-7)
- **Each item has a test: Met.** Dirty worktree refused; engine exit refuses the live sample; same-size same-mtime rewrite caught; absolute and `..` targets refused; stale labels rejected; drivers run from any cwd without the cache file; `git apply --check` accepts.
- **Record REPRODUCE.md and tracked reads unchanged: Met in the patch.** The record branch, `evals/results/**` and the read numbers are untouched. The main REPRODUCE.md gains only § 0. The lead tree needs the INPUTS.json restore above.
- **Version notes on the new scripts: Met.**

## Judgment calls
- **Analysis reference.** The analysis paths are compared with 6f01e57d, REGISTRATION-17's `analysis_tree`, which equals the record. The literal SDD diff against `fbd36a0c` fails on every tree, because that commit lacks the reproduction tooling.
- **REPRODUCE.md § 0 wording.** It says to run in a worktree of the record branch, whose pipeline is `fbd36a0c`. A bare `fbd36a0c` worktree cannot run the reproduction.
- **Exit codes.** An engine failure gives 1. With `--live-sample` it gives 3, per FR-7, not bd-161zz's 2. There is no `--live-anyway`, because a paid override is not in the SDD.
- **Bytecode caches.** `__pycache__/`, `*.pyc` and `.pytest_cache/` are excluded from the porcelain. The engine writes them, and only the operator's global gitignore hides them.
- **Refusals write nothing.** On exit 2 the environment goes to stdout only. `--dry-run` with `--live-sample` skips the sample and keeps the engine exit.
- **Live range.** It uses `common.build_cell` on the row plus its recorded grade, the reads' filter.
- **Digest cache.** Both bead options are applied: verification bypasses the cache, and the key is realpath plus a stat with ctime. Reconstruct also hashes fixture pr/ files fresh.
- **Unsafe symlinks.** An unsafe pr/ symlink target is a Mismatch, never dropped, because the grader counts pr/ symlinks. A strict `safe_rel` also refuses inside-pointing `..` targets. The record has no pr/ symlinks.
- **Labels binding.** The driver stamps the sample_id from the verified chunk packets; the judge prompt is not mine. The new `aggregate` refuses pre-cycle-133 keys and labels.
- **Aggregate validity.** `--results-root` is required, so validity cannot diverge from the sampler. The key's sample_id is recomputed, so an edited key is rejected. `--force` replaces only D*.md packets and key.json.
- **Chunk directory.** It is named `chunks-<key sha 16 hex>`, holds KEY_SHA256, and is built atomically. The prompt defaults to the tracked `prompts/judge.md`.
- **final.sh values.** All three values are required and REG_SHA is checked against the file. REG is limited to `[A-Za-z0-9][A-Za-z0-9._-]*`, because the bead's class allowed `..`. Tokens are split on whitespace because the real file holds all three on one line.
- **Power-mini diffs.** All four are generated, because all four had wrong headers. A legacy-header mode keeps the byte-identity proof through full-file sha256 pins. The seed 20261023 is recorded, but the fixed bodies do not draw from it. The fixtures are built in `setUpModule`, which both runners honour.
- **AC-1 count.** It comes from a one-line `tests/COUNT` (215, the unittest count). Deriving it from collection could never catch a lost test.
- **MV-1.** The `main:` clause is dropped, since the c131 digests are pinned.
- **spend.sh dedup.** Rows dedup by `(run_id, batch)`. Rows without a run_id dedup across files by canonical JSON but never within one file, which errs toward overcounting. The test lives in `test_spend.py`, since `spend.bats` is not mine.

## What the lead must do
1. Restore the lead tree's INPUTS.json (see Incident).
2. Drivers outside my ownership still hard-code the lead tree. `look.sh` sources registration.txt. `register*.sh`, `run-judge.sh`, `batch-c132.sh`, `smoke-check.sh` and `run-annotation.sh` cd into the lead path. `scripts/README.md` line 3 ("paths are absolute") is now stale for final.sh and run-judge-defects.sh.
3. On main the new reproduce.sh refuses cycle-132 by design (exit 2). Reproduce in a record worktree, which keeps the record's tooling, so Task 3.3b need not rerun for this patch.
4. `spend.sh` is a pipeline path. This patch moves the pipeline past `fbd36a0c`, as the next version.
5. CHANGELOG, DEC rows, and the closures of bd-jat0z, bd-161zz, bd-ombvn, bd-xr3uq, bd-o3a5h, bd-qxwrm and bd-um8ol.
6. bd-161zz's fresh DEC-0435 self-check is not built; the tracked log is still passed. It belongs to Task 2.4/2.5.
