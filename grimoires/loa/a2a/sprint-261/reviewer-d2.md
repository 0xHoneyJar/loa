# Sprint 261 (cycle-130 Sprint 4) Task 4.3 — suite v2 author D2 report

Author: D2 (Claude Opus 5.5), 2026-10-17. Worktree `/home/merlin/Documents/thj/code/loa-wt-s4d` at `4c279606`. D2 authored bugfix-v2-01 and bugfix-v2-02 directly. Two forks of D2 authored bugfix-v2-03/04 and feature-v2-01/02 under the same brief. D2 reran every proof below independently with one script. Nothing outside the six task directories and this report copy was written. Nothing was committed, and no docker or model CLI was run.

## Survey

`bash evals/harness/seed-bugfix-tasks.sh --since 2026-06-01 --dry-run --out "$(mktemp -d)"` printed `8 candidate(s), 243 refused, 12 skipped; dry run, nothing written`. None of the 8 candidates is usable:
- **Six are this cycle's own harness fixes.** bf155cc7, 6c454de7, d8bb0bbe and 2ef83aa8 fix `ablation-grade.sh`; 41a71297 and eec592d5 fix `run-ablation.sh`. They are 1–2 files each, so they miss the 3–6 interacting-files target. Their fixtures would be the 84–89 KB grader or runner scripts that grade this very ablation. That is self-referential, and the fixed versions ship at the pinned arm commit.
- **b6802e4f (cycle-129)** touches three harness files plus `tests/unit/floor-snapshot.bats`. That test reads the `.claude/` floor, so it cannot be self-contained without the System Zone.
- **4406815a (2026-07-30)** predates the 2026-08-01 post-cutoff floor. It is also a 2-file change.

All six tasks are therefore synthetic, as Sprint 259 found.

## Tasks authored

The proof script is `/tmp/d2proof.sh`. For each side it copies `fixture/` fresh, overlays every `manifest.json` entry at its `dest` and, for the reference side, runs `patch -p1` after a clean dry run. It then runs `PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider tests`, and again with `--ignore=tests/acceptance`. Every task's `test_command` and `regression_command` are the brief's. Every `grader_protected` is `tests/conftest.py` plus every fixture test file. Every `bounds` is `{max_turns: {IMPLEMENT: 80}, timeout_min: {IMPLEMENT: 35}}`, every `suite_version` is 2, and every `source.kind` is synthetic, dated 2026-10-17.

| task | package (code lines, files) | fixture cases | acceptance cases | reference (changed lines / files) | fixture size |
|---|---|---|---|---|---|
| bugfix-v2-01 | stockroom (271, 8) | 19 | 11 | 104 / 5 | 60K |
| bugfix-v2-02 | kvconf (191, 7) | 27 | 11 | 90 / 5 | 56K |
| bugfix-v2-03 | jobq (209, 7) | 14 | 12 | 95 / 4 | 60K |
| bugfix-v2-04 | batchkit (192, 8) | 11 | 11 | 82 / 6 | 60K |
| feature-v2-01 | textpipe (208, 9) | 15 | 16 | 156 / 5 | 68K |
| feature-v2-02 | tally (196, 9) | 14 | 15 | 165 / 4 | 64K |

Proof tails (base / reference; full = `tests`, reg = `--ignore=tests/acceptance`):
```
bugfix-v2-01  [base] full 10 failed, 20 passed | reg 19 passed   [ref] full 34 passed | reg 23 passed
bugfix-v2-02  [base] full 9 failed, 29 passed  | reg 27 passed   [ref] full 42 passed | reg 31 passed
bugfix-v2-03  [base] full 11 failed, 15 passed | reg 14 passed   [ref] full 26 passed | reg 14 passed
bugfix-v2-04  [base] full 10 failed, 12 passed | reg 11 passed   [ref] full 22 passed | reg 11 passed
feature-v2-01 [base] full 16 failed, 15 passed | reg 15 passed   [ref] full 31 passed | reg 15 passed
feature-v2-02 [base] full 15 failed, 14 passed | reg 14 passed   [ref] full 29 passed | reg 14 passed
```
The reference regression counts for bugfix-v2-01 and v2-02 include the 4 regression tests the reference patch adds.

- **bugfix-v2-01 (stale derived state).** *Hard because:* the index keys on `revision`, which a remove does not move and a batch defers, and the summary keys on store size. Bumping in `pop` makes pop+put moves count twice, and bumping inside a batch breaks a fixture test. The fix needs a per-change generation apart from the public revision, plus a no-op-aware update path, across store, index, stats and inventory.
- **bugfix-v2-02 (round-trip asymmetry).** *Hard because:* the writer leaves trailing whitespace and `#`/`;` bare, and the decoder is a `str.replace` chain no reordering can fix. The reader folds key case, and the model's `set`/`add_section` compare exact spelling while `get` folds case, so the merge symptom's cause is in the model. Quoting everything regresses the fixture layout test.
- **bugfix-v2-03 (ties and stability).** *Hard because:* ties break wrongly in two places, by name in `order_key` and by ready-time in the bucket queue, and fixing either alone leaves the other's cases red. The reprioritise requeue and the `drain` snapshot loop are further sites of the same contract.
- **bugfix-v2-04 (lifecycle and partial failure).** *Hard because:* journalling per item without ledger rollback makes retries look idempotent while balances stay wrong. Releasing locks only in the batch leaves a partly taken lease locked, and the fixture's `NotHeld` contract punishes a blanket release.
- **feature-v2-01 (registry with precedence, textpipe).** *Hard because:* the base config loader checks `apply` against the built-ins at load time, so a registry added in one module leaves config-applied definitions rejected. The listing helper crashes on an empty registry, duplicate config keys need `object_pairs_hook`, and the `config: ` prefix depends on a value's source.
- **feature-v2-02 (grouped aggregation, tally).** *Hard because:* aggregate columns must pass the existing numeric, alignment and empty-last sort rules, so an all-empty group is left-aligned and sorts last, and ties compare as decimals. The non-numeric error's line number counts unfiltered lines while only kept rows are read.

Each one-line criterion is the `criterion` field of the task's `task.yaml`.

## Staging-root validation

The common-rules staging root (review-01…04 plus the six tasks plus README) was checked against the real suite file:
```
validate-suite: 6 violation(s) over 10 task(s)   (each: schema: suite_version 2 differs from the suite file's 1)
```
It was then checked against a temporary suite file copy with `suite_version: 2`, with the staged review `task.yaml` copies set to 2 in staging only:
```
validate-suite: OK — 10 task(s) valid in /tmp/tmp.CBqxTga5jd/suite (partial: type counts not enforced)
```
`bash evals/graders/no-secrets.sh <fixture>` exits 0 for all six. No `__pycache__` or `.pytest_cache` is in any task tree.

## DECISION bullets

- DECISION: all six tasks are synthetic. The seeder dry run since 2026-06-01 gave 8 candidates and none is clean: six are 1–2-file fixes to this cycle's own grader or runner, b6802e4f needs the `.claude/` floor in its test, and 4406815a predates 2026-08-01.
- DECISION: bugfix-v2-01 uses suggested class 1, stale derived state. A grouped `batch()` and an exactly-once revision rule deepen the interaction.
- DECISION: bugfix-v2-02 uses suggested class 2, round-trip asymmetry. The comparison helper is the model's exact-spelling `set`/`add_section` against its case-folding `get`. The unknown-escape refusal is part of the decoder alignment and is stated in Bug (observed) and Expected.
- DECISION: bugfix-v2-03 uses suggested class 3. The one defect is that dispatch order is not keyed on submission position everywhere: the key tie-break, the bucket queue, the reprioritise requeue and the snapshot loop in `drain`.
- DECISION: bugfix-v2-04 uses suggested class 4. The one defect is that a batch has no all-or-nothing lifecycle: no rollback, the journal written only at the end, locks unreleased on failure and on a partial lease, the report counting the failed item, and repeated ids applied twice.
- DECISION: feature-v2-01 uses suggested feature 1 as a line-filter tool. The sources are the built-ins, the config file's `filters`/`disable`, and `--define`/`--undefine`. Steps name built-in filters only, which removes cycle and nesting ambiguity. Config-sourced errors carry a `config: ` prefix, and the config `apply` list is checked against the complete registry even when `--apply` is given.
- DECISION: feature-v2-02 uses suggested feature 2 as a CSV table tool. `--limit` applies to ungrouped rows too, with the same tie rule. Aggregate headers are `count` and `func(FIELD)`. The error's line number counts the header as line 1. An assertion that depended on unstated scan order was rewritten to have a single bad cell.
- DECISION: the bugfix-v2-01 and v2-02 reference patches include a small regression test file of 4 cases. TASK.md asks the agent for regression tests, and the reference models that. The file counts in the 5 files touched.
- DECISION: the 4–8 module bound counts `__init__.py` as a module for bugfix-v2-01 (8 files) and v2-04 (8 files). For feature-v2-01 and v2-02 (9 files each), `__init__.py` is counted as the package marker, with 8 code modules.
- DECISION: `grep -ri hidden` outside `hidden/` matches only each `task.yaml`'s grader-facing `success_criterion` and `reference_patch` fields, as in every v1 task. TASK.md, `criterion` and the fixtures are clean, and validate-suite's leakage check passes.
- DECISION: validation needs a staged suite file at `suite_version: 2`, because the real `evals/suites/ablation-2.0.yaml` still says 1 and the lead owns it. Against the real file the only violations are the six expected version mismatches.
- DECISION: the bugfix-v2-03 reference also makes `start()` refuse a paused job. This follows "a paused job is not dispatched", but no acceptance case depends on it.
- DECISION: the bugfix-v2-04 reference rolls back by snapshotting and restoring the ledger. TASK.md requires only that every change is undone, so any design that achieves that passes.
- DECISION: reference patches were generated with `diff -ruN` between the base and a fixed scratch copy, with the timestamps stripped from the `---`/`+++` headers. All apply with `patch -p1` from the fixture root.

## Could not do / limitations

- Proofs ran on host Python 3.13 with pytest 9 only. The binding rerun inside `loa-ablation:258` (Python 3.11) is the lead's. No construct beyond 3.8-era stdlib is used knowingly. feature-v2-02 uses `decimal` and the textpipe config uses `json` `object_pairs_hook`, both of which are in 3.11.
- Hardness is a design intent, not a measurement. Only the calibration smoke can show a0_bare ≤ 0.5 per task. The tasks with the narrowest margins are probably bugfix-v2-02 (a careful agent can find all four sites from the symptoms) and bugfix-v2-04.
- Pre-existing, gitignored `__pycache__` directories under the worktree's `.claude/adapters/` were left alone. They are outside D2's ownership and are not in the patch.

## Handoff notes for the lead

- **For the fairness reviewer:**
  - In bugfix-v2-01, check the exactly-once revision rule against the batch grouping, and the no-op and refused-operation cases. Also check that `rebuilds` counts are stated ("after a change each rebuilds once, on its next lookup").
  - In bugfix-v2-02, check that every value in the round-trip lists falls inside the stated alphabet. The brief excludes other control characters and Unicode line separators, and none is tested.
  - In feature-v2-02, check the decimal-places rule for sums and the `--limit` tie rule.
  - In bugfix-v2-03, check the "dispatches one job at a time" sentence.
- The lead should rerun the proofs in-image with `ablation-grade.sh --self-check base|reference`. The expected counts are in the table above, and each `success_criterion` records them.
- Removing the v1 build task directories, the suite file's `suite_version: 2` and `MANIFEST.sha256` are left to the lead at integration, as the brief says.
