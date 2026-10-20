# Sprint 263 (cycle-131 Sprint 1) — implementation report for the reviewer

**Lead:** Fable 5.1 (main session) · **Review rounds:** r1a `596627f4`, r1b `baea8024` (dissent runs 1 and 2; see `engineer-feedback.md`) · **Implementers:** four Opus 5.5 subagents in linked worktrees (A: Tasks 1.1/1.2/1.7, B: 1.3/1.4/1.6, C: 1.8, D: 1.5), patches applied with `git apply --3way --index` · **Lead tasks:** 1.9, 1.10, 1.11, 1.12 · **Commits:** `bb03e931` (sprint), `596627f4` (r1a), `baea8024` (r1b), `cddec367` (audit r1c) on `feature/cycle-131-honest-measurement` (plan `7600bd7d`) · **Date:** 2026-10-19

Implementer reports (verbatim, under `~/.cache/loa/cycle-131/reports/s1-{a,b,c,d}.md`, copied to this directory as `reviewer-{a,b,c,d}.md` for the record branch). Lead records: `regrade-c131.md` (Task 1.9), `adjudication/result.md` (Task 1.10), `anchors-curation.md` (Task 1.5, D). Decisions DEC-0626 … DEC-0639; KF-049 recurrence 4; KF-050 new.

## What changed (by file)

| Area | Files | Owner |
|---|---|---|
| Closed mount, toggles, eval config | `evals/harness/lib/sandbox-mount.sh` (+632), `evals/harness/pipeline-run.sh`, `evals/suites/ablation-2.0.yaml` | A |
| took-effect rules | `evals/harness/took-effect.sh` (`oracle_closed` a–d, `oracle_open_recorded`, `bare_model_fable`, `review_only_phases`, `no_review_dissent_envelope`; `--task-yaml`, `--source-repo`) | A |
| `--allow-partial` | `evals/harness/run-ablation.sh` (freeze check, grader argv, `MANIFEST.json.allow_partial`, resume semantics) | A |
| Grader 1.3.0 | `evals/graders/recall-vs-defects.sh` (rule `pm3_or_same_function`, three results), `evals/harness/ablation-grade.sh` (oracle detector, KF-046 class 7, `corpus_sha256`, anchor_line reduction) | B |
| Row writer 1.4 / report 1.3 | `evals/harness/ablation-row.sh`, `evals/harness/ablation-report.py` | B |
| Dissent anchors, budget_scale | `.claude/scripts/adversarial-review.sh`, `.claude/schemas/adversarial-finding.schema.json`, `.claude/schemas/wire/dissent-{review,audit}.wire.json`, two `ADVERSARIAL-REVIEW.md`, `.loa.config.yaml.example`, `.claude/checksums.json` (regenerated) | C (+ lead) |
| Corpus labels | `evals/fixtures/review-prs/manifests/v1/*.json` (18, byte-identical to the ba11b860 pin), `manifests/pr-11 … pr-18.json` (curated anchors), `SHA256SUMS` | D |
| Smoke root | `grimoires/loa/evals/ablation-2.0-smoke-c131/` (seven review-catch smoke tasks, frozen, 20 files) | lead |
| Re-grade rows | `grimoires/loa/reports/ablation-2.0/regrade-c131/rows.jsonl` (36 rows) | lead |
| Tests | `evals/tests/{sandbox-mount,took-effect,pipeline-run,run-ablation,ablation-grade,ablation-row,ablation-report,eval-recall-grader}.bats`, fixtures (`c131-oracle/`, stubs), `tests/unit/adversarial-review-{budget-scale,normalise}.bats`, 5 kf004 fixtures | A, B, C |
| Docs | `CHANGELOG.md` `[Unreleased]`, `grimoires/loa/evals/ablation-2.0/README.md` | lead |

## AC Verification

Every acceptance criterion of `grimoires/loa/sprint.md` § Sprint 1, verbatim, with evidence.

### "PRD FR-1 AC 1–6 (overlay, evidence before the first phase, `oracle_closed` clauses a–d, detector forms a–b, detector validation flags exactly the three known runs, bats, seven-PR smoke)"

| AC | Status | Evidence |
|---|---|---|
| FR-1 AC 1 overlay before the first phase | ✓ Met | `evals/harness/pipeline-run.sh:551-577` (`mount_prompt_surface` → `overlay_answer_paths` → toggles → `apply_eval_config_variant` → … → `check_mount_closed` before the first `-p` launch); `evals/tests/pipeline-run.bats` real-library case snapshots the evidence and the gate script at head at the first launch; smoke trials show `mount_closed=pre-launch head:N …` in `meta/arm-evidence.txt` |
| FR-1 AC 2 `oracle_closed` clauses a–d | ✓ Met | `evals/harness/took-effect.sh` `rule_oracle_closed` → `_sm_oracle_py check` (`evals/harness/lib/sandbox-mount.sh` `cmd_check`: (a) fixture version or absent, (b) no byte-equal later-only pinned version outside pr/ and .git/, (c) `mount_mutated`, (d) sandbox git = base commit, no remote, no alternates, `fsck --unreachable` empty, no pinned blob); `evals/tests/took-effect.bats` fails on each clause and passes otherwise |
| FR-1 AC 3 detector forms a–b | ✓ Met | `evals/harness/ablation-grade.sh` `oracle_scan` / `oracle_plan` (diff form: head-side ranges by operand order; read form: later-only lines near a site; Bash, Read, Grep; tool_use↔tool_result correlation; `exposed_unknown`); `evals/tests/ablation-grade.bats` AG-47/48/49 |
| FR-1 AC 4 detector validation flags exactly the three known runs | ⚠ PARTIAL (recorded, DEC-0632) | Diff form: review-04 t2 (d1–d4), r17 t1 (nine sites under the curated anchors, eight under v1), r18 t1 (d7) — AG-50 — plus two genuine later-copy diffs the analysis missed (r17-t2 REVIEW 144, r17-t3 REVIEW 137; KF-049 rec 4). Read form adds incidental later-copy reads on seven more full-arm runs. Ruling: the union stays the exclusion set as specified, `oracle_exposed_by_form` keeps the split, diff-only is a labelled sensitivity; the AC's "exactly three" was written against a weaker detector and narrowing after seeing the cells would be the post-hoc move this cycle exists to stop |
| FR-1 AC 5 bats | ✓ Met | `evals/tests/` 507/507 on `bb03e931` (`~/.cache/loa/cycle-131/logs/bats-evals-final.log`, exit 0); new: sandbox-mount 12, took-effect 8, pipeline-run 9, run-ablation 4, ablation-grade 7, ablation-row 4, ablation-report 5, eval-recall-grader 11 |
| FR-1 AC 6 seven-PR smoke | ✓ Met (two per-task fallbacks recorded) | batch `smoke-c131-20261019T075011Z` (pr-05, 08, 12, 13, 16, 17, 18; `a1_full` × 1; pinned `bb03e931`); first three trials: `mount_closed` pre-launch OK, `gate_scripts_at_pr_version` per PR recorded; pre-registered expected-dissent table (NOTES 06:08:48Z) and the pr-12 amendment (07:04:12Z; KF-050, DEC-0631). Read to follow in this file's § Smoke when the batch ends |

### "PRD FR-2 AC 1–4 (grader 1.3 outputs and tests; versioned re-grade with every `recall_pm3_v1` equal to the stored value; adjudication protocol run with kappa and share reported)"

| AC | Status | Evidence |
|---|---|---|
| FR-2 AC 1 grader 1.3 outputs | ✓ Met | `evals/graders/recall-vs-defects.sh` header (1.3.0 rule), `details.{recall, recall_pm3, recall_pm3_v1, detected*, missed*, credits_function_only, rule, v1_manifest}`; `ablation-grade.sh` `GRADER_VERSION 1.3.0`, `corpus_sha256`; RG-29 … RG-39, AG-45 |
| FR-2 AC 2 tests of the rule | ✓ Met | RG-29 (6 lines away, same function), RG-30 (next function), RG-31 (nesting → innermost), RG-32 (500-line function → ±20), RG-33 (40-line range → first line), RG-34 (markdown), RG-35 (multi-site), RG-36 (v1 and fallback), RG-39 (end of definition) |
| FR-2 AC 3 versioned re-grade, `recall_pm3_v1` == stored | ✓ Met | `regrade-c131.md`: 36/36 OK, 0 grade failures; rows `grimoires/loa/reports/ablation-2.0/regrade-c131/rows.jsonl` (36, `ablation-row.sh --validate` OK); step 0: `manifests/v1/` byte-equals `git show ba11b860:…` for all 18 (D's report, lead re-check) |
| FR-2 AC 4 adjudication with kappa and share | ✓ Met — rule NOT adopted | `adjudication/result.md`: two Opus labelers, 17 packets, agreement 1.000, kappa 1.000; (a) 2/7 labelled (0.286 [0.082, 0.641]) < 80 % → `recall_pm3` is the decision statistic (DEC-0638); (b) 6/10 (0.600 [0.313, 0.832]) reported |

### "PRD FR-3 AC 1–3 (`--allow-partial` dry run passes on the replication root; the two replication rows re-graded clean into the versioned file; the re-take DEC beside DEC-0604)"

| AC | Status | Evidence |
|---|---|---|
| FR-3 AC 1 dry run on the replication root | ✓ Met | A's report (dry run against a pristine clone at 7600bd7d with `--allow-partial`; refused without it, RAB-c131 cases); the lead's smoke dry run on the partial smoke root passed (`plan: 1 arms, 7 tasks, 7 trials`) |
| FR-3 AC 2 the two replication rows re-graded clean | ✓ Met | rows `replication-01-a1_full-review-r18-t2` / `-t3`: `contaminated` null, one `contamination_exempt` each (AG-51; `regrade-c131.md`) |
| FR-3 AC 3 re-take DEC beside DEC-0604 | ⏸ Sprint 3 | the replication re-take read (DEC-0604's pre-registered read on the versioned rows, with the r17-t2/r17-t3 exposures) is a Sprint 265 read per the sprint plan's Task 3.1; the rows and the detector findings it needs are in place (DEC-0632 names them) |

### "PRD FR-4 AC 1–3 (anchors and budget change with tests; example config; shipped default `fixed`)"

| AC | Status | Evidence |
|---|---|---|
| FR-4 AC 1 anchors and budget with tests | ✓ Met | `.claude/scripts/adversarial-review.sh` `_ADV_NUMERIC_ANCHOR_JQ`, `_adv_conf_budget_scale`, `_adv_budget_effective`; NRM-68 … NRM-74, BSC-1 … BSC-10; wire schemas nullable-required (DEC-0625/0633); `tests/unit` adversarial-review set 652/652, wire fixture pytest 11/11 |
| FR-4 AC 2 example config | ✓ Met | `.loa.config.yaml.example` `budget_scale: fixed`, `budget_cents_max: 600` under both gates (BSC-9 also checks the live config untouched) |
| FR-4 AC 3 shipped default `fixed` | ✓ Met | absent key → envelope byte-identical (BSC-1); eval variant written only by the harness (`apply_eval_config_variant`, `config_variant=eval` evidence in the smoke trials) |

### "`evals/tests/` (447 + new) and `tests/unit/` green; `bash -n` on every changed script; `validate-suite.sh` on both suite roots"

| Check | Status | Evidence |
|---|---|---|
| `evals/tests/` | ✓ 507/507 | `bats-evals-final.log` exit 0 (447 + 60 new) |
| `tests/unit/` | ✓ (touched suites) | adversarial-review set 652/652 (`bats-unit-c.log`), the 19 suites reading the example config / schemas / checksums 172/172 (`bats-unit-related.log`); full `tests/unit/` not re-run end to end (hour-scale); CI runs it on the PR |
| `bash -n` | ✓ | every changed `.sh` (A, B, C, lead) |
| `validate-suite.sh` | ✓ | `ablation-2.0` and `ablation-2.0-replication` (A), `ablation-2.0-smoke-c131` (freeze: 7 tasks valid, partial) |
| `tools/gen-checksums.sh --check` | ✓ | 1973 entries match |

## Deviations and decisions the reviewer should know

1. **Same-scope rule not adopted** (DEC-0638): the grader still writes `recall`; `recall_pm3` decides. Cycle-130 R2 withdrawn.
2. **AC4 PARTIAL** (DEC-0632): detector flags more than three runs; union kept, split reported.
3. **pr-12 import skew under the closed mount** (KF-050, DEC-0631): predicted before the smoke; pr-12 is re-grade-only.
4. **Rows path** (DEC-0639): tracked under `grimoires/loa/reports/…` because `evals/results/*` is gitignored.
5. **AG-50 expectation** updated by the lead for the curated anchors (comment in the test).
6. **Wire schemas** extended under DEC-0625 in the nullable-required form (DEC-0633); five kf004 fixtures gained null keys.
7. **Label text source** for the adjudication packets: `source` (record branch) rather than the gate-name field `label_source` (NOTES 07:37Z).

## Smoke (Task 1.11) — batch `smoke-c131-20261019T075011Z`, complete 2026-10-19T09:15:51Z

Pin `bb03e931`, seven `a1_full` trials, USD 91.45 (estimate 56; the priced-in dissent adds ≈ USD 4–6 per run on the large PRs). Read against the pre-registered expected-dissent table (NOTES 06:08:48Z) and its pr-12 amendment (07:04Z).

```
task       status        degr oracle   overlay cfg   | review voices/budget/anchors audit voices/budget/anchors | new   pm3   pm3v1 |    USD  min
review-01  completed     false OK       head    eval  | 2/2 diff/200c anch 11/11 2/2 diff/200c anch 4/4 | 1.0   1.0   1.0   |   9.60   22
review-02  completed     false OK       head    eval  | 2/2 diff/200c anch 10/10 2/2 diff/200c anch 5/5 | 1.0   1.0   1.0   |  10.81   27
review-03  completed     true OK       head    eval  | 0/1 -/-c anch 0/0      0/1 -/-c anch 0/0      | 1.0   0.875 0.5   |  11.39   34
review-04  completed     false OK       head    eval  | 2/2 diff/440c anch 8/12 2/2 diff/440c anch 2/2 | 0.8   0.8   0.6   |  13.94   33
review-r16 completed     false OK       head    eval  | 2/2 diff/423c anch 6/6 2/2 diff/423c anch 5/5 | 0.5   0.5   0.5   |  18.73   35
review-r17 agent_error   false OK       head    eval  | null/null no envelope  null/null no envelope  | 0.0   0.0   0.0   |   9.40   30
review-r18 completed     false OK       head    eval  | 2/2 diff/257c anch 5/5 2/2 diff/257c anch 6/6 | 0.75  0.75  0.75  |  17.58   38

total USD 91.45160824999999 over 7 rows
```

- **Closed mount:** `oracle_closed OK` on 7/7 (pre-launch `check_mount_closed` and took-effect), `oracle_exposed_defects` empty and `contaminated` null on every row; `gate_scripts_at_pr_version` recorded per PR (pr-12: 6 answer paths are gate scripts, run at the PR's head version).
- **Dissent:** both voices on both gates on pr-05, pr-08, pr-13, pr-16, pr-18 under `budget_scale: diff` (effective 200/200/440/423/257 c; nothing refused — in cycle-130 pr-13/17/18 were refused at 200 c). Numeric-anchor share 62/66 = 0.94 (≥ 0.80 met in aggregate); the one gate under is pr-13 review 8/12 = 0.67.
- **pr-12 (KF-050, DEC-0631):** every voice `api_failure` on both gates (the PR-era `adversarial-review.sh` at head, mounted cheval import skew), row `degraded` with 0/1 voices per gate; both gates completed; catch 1.0.
- **pr-17 (DEC-0640):** `agent_error` — REVIEW phase cap 30 min after the reviewer ran the PR's bats and waited on the background dissent; cycle-130's REVIEW phases on this PR took 21–23 min with a refused dissent. Fallback pre-registered: task bounds REVIEW 50 / AUDIT 40 on pr-17 and pr-18; one re-smoke trial of pr-17 under the bound (`~/.cache/loa/cycle-131/scripts/resmoke-r17.sh`) before Sprint 264. Result appended below when it lands.
- **Row-writer semantics noted:** a gate whose envelope exists with every voice failed reads `degraded` (0/N completed), not `dissent_absent_gates`; the Sprint 264 sensitivity is defined over the union (NOTES 08:29Z).
- FR-1 AC 6 → ✓ Met for the closed mount on all seven PRs; the two per-task failures are recorded with their fallbacks (DEC-0631, DEC-0640).

### pr-17 re-smoke under the DEC-0640 bounds

Batch `smoke-c131-r17b-20261019T093946Z` (one `a1_full` trial, bounds REVIEW 50 / AUDIT 40, pin `bb03e931`, smoke root re-frozen `dde9ba78…`): REVIEW 24 min / 63 turns and AUDIT 17 min / 69 turns both completed; both gates ran both voices (`budget_scale: diff`, effective 406 c); 27/27 dissent findings carry `anchor_line`; `oracle_closed OK` (head:24, 18 later-only pinned versions); catch 0.75 / pm3 0.8 / pm3_v1 0.75; `oracle_exposed_defects` []. Row status `cap_failure` (phase AUDIT): USD 22.46 against the review-catch per-run cap of USD 20, reached after the last phase — the run is complete and graded; the cap guard fired. Re-derived `a1_full` cost under the closed mount with the priced-in dissent: pr-05/08 ≈ 10–11, pr-12 ≈ 11, pr-13 ≈ 14, pr-16 ≈ 19, pr-18 ≈ 18, pr-17 ≈ 22 (about double cycle-130's). Sprint 264 pre-registration carries the bounds, a review-catch per-run cap of USD 30 for the large PRs, and a B1/B2 budget re-derived from these costs (NOTES 2026-10-20T01:04:59Z).
