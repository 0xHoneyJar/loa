# Implementer B — Sprint 263 Tasks 1.3, 1.4, 1.6 (cycle-131)

## What was built
- **Task 1.4, `recall-vs-defects.sh` 1.3.0** (`evals/graders/recall-vs-defects.sh`). Rule `pm3_or_same_function`: citation validity (positive, ordered, inside the head file) and the 25-line range cap, then ±3 or same scope. Scope = enclosing definition by header line (bash, bats, python, markdown), innermost on nesting, with end-of-definition detection. A definition over 400 lines, or a file type with no regex, falls back to ±20. Three results (`recall`, `recall_pm3`, `recall_pm3_v1` from `manifests/v1/<pr>.json`, else `v1_manifest:false`), plus `credits_function_only` and `rule`.
- **Task 1.3 and grader wiring** (`evals/harness/ablation-grade.sh`, `GRADER_VERSION 1.3.0`):
  - `recall.*` carries the three results, the missed lists, credits and rule, as positions.
  - `corpus_sha256` is written.
  - The envelope reduction reads `anchor_line`/`anchor_line_end`.
  - The oracle detector writes `oracle_exposed_defects`, `oracle_exposed_unknown`, `oracle_exposed_events` and `oracle_exposed_by_form {diff, read}`.
  - KF-046 class 7 writes `contamination_exempt[]`.
- **Task 1.6, row writer 1.4** (`evals/harness/ablation-row.sh`): every SDD §3.2 field, plus `row_writer_version`, `oracle_exposed_unknown` and `oracle_open`. `--validate` requires the 1.4 fields on 1.4 rows and checks their enums and id rules.
- **Task 1.6, report 1.3** (`evals/harness/ablation-report.py`):
  - Partitions by version × pin × rule, never pooled, plus `--pin`.
  - `_pm3`/`_pm3_v1` printed beside every catch read.
  - The two labelled sensitivities, with excluded rows per arm.
  - `min_valid_cells` 4 ("insufficient").
  - Finding volume and planted÷flagged precision.
  - `--exclude-oracle-exposed`.
- **Tests and fixtures:**
  - `evals/tests/{eval-recall-grader,ablation-grade,ablation-row,ablation-report}.bats`.
  - `evals/tests/fixtures/ablation-report/gen-fixtures.py` gains the scenarios `c131` and `c131-mixed`.
  - New `evals/tests/fixtures/c131-oracle/`: four trimmed transcripts, each under 140 KB, line numbers preserved, later copies stored as `*.fx`. `trim.py` there is the one-off provenance script.

## How it was tested
| file | cases (new) |
|---|---|
| eval-recall-grader.bats | 39 (11) |
| ablation-grade.bats | 51 (7) |
| ablation-row.bats | 41 (4) |
| ablation-report.bats | 52 (5) |
| whole `evals/tests/` | 474 = 447 + 27, 474 ok, 0 not ok (final run, exit 0) |

```
bash -c '~/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats evals/tests/'
```

Other checks:
- `bash -n` on the three changed scripts and `ast.parse` on the report both pass.
- The eval.yml trust-boundary patterns find nothing in the changed files.
- AG-13 still holds: one `meta/` mention, no `sha256sum`, no `.claude/scripts`.

36-run validation: hardlinked copies of the 36 run directories under `~/.cache/loa/cycle-131/s1b-scratch.*`, graded by the worktree grader with `--allow-partial`. No main-checkout file was written.

## AC evidence
- **FR-2 AC1: PASS.** The header documents the rule, boundaries, caps and range rule. The detail fields, the grader's `recall.*` fields, and the row's three rates and missed lists all exist (RG-29…39, AG-45, RW14-1). The report prints all three with the decision statistic named (AR-48).
- **FR-2 AC2: PASS.** RG-29 covers 6 lines away in the same function; RG-30 the next function; RG-31 nesting; RG-32 the 500-line function; RG-33 the 40-line range; RG-34 markdown; RG-35 multi-site anchors; RG-36 v1 and the fallback; RG-39 end of definition.
- **Regression precondition for Task 1.9: PASS.** `recall_pm3_v1` equals the stored `recall` on 36 of 36 runs, through the full grader.
- **FR-1 AC3 (detector forms): PASS.** The diff form, the read form, `exposed_unknown`, Bash, Read and Grep, and id correlation are covered (AG-47/48/49). Covering diff and later-line read hit; `diff -q` and `cat pr/head.diff` do not.
- **FR-1 AC4 (exactly the three runs, 4/9/1): PARTIAL.** See the findings below. AG-50 pins the diff form at review-04 t2 d1–d4, r17 t1 eight sites and r18 t1 d7, with the bare run empty.
- **FR-3 (b): PASS.** The replication r18-t2 and r18-t3 rows re-grade clean with one exemption each (36-run table). AG-51 uses the real pr-18 line, and a token not in the fixture is still flagged.
- **FR-3 (c): PASS** for `dissent_absent_gates` and `dissent_absent_reason` (RW14-3) and the report's labelled sensitivity with planned absence kept (AR-49).
- **SDD §3.2 row and report fields: PASS** (RW14-1/2/4, AR-48…52).

## Findings (the 36-run detector validation)
- **Diff form.** It flags the three known runs:
  - review-04 t2: d1–d4, which matches.
  - r18 t1: d7, which matches.
  - r17 t1: 8 sites, against the analysis's 9. The ninth (d10) was a later-side coincidence (`43a65` beside site 66).
- **Two more diffs, read by hand.** Replication **r17-t2** (REVIEW event 144: `for f in …; do diff <(cat "pr/head/$f") "$f"`) and **r17-t3** (REVIEW 137: `diff -u pr/head/$f $f`) genuinely diff head against the later copy and print planted-site hunks. `oracle_scan.py` missed them because it cannot resolve `$f`.
- **Read form.** It adds incidental later-copy reads on seven more full-arm runs:
  - review-04 t1/t2/t3: the audit skill `cat`s its own later SKILL.md (d5).
  - review-01 t2/t3: a repo-wide grep (d2).
  - review-02 t2/t3: d3.
  - review-03 t2: d1.
- **No bare run is flagged.**

## DECISION bullets
- DECISION: `_pm3` and `_pm3_v1` keep the 1.2.0 rule exactly. Validity and the 25-line cap bind `recall` only. With the cap applied, 2 of 36 runs (p1b review-02 t1-r2, replication a0 r17-t3) failed the regression.
- DECISION: End-of-definition detection caps the "next header" span. Bash and bats end at the first `}` at the header's indentation, and a one-line function ends on its header. Python ends before the first dedented line.
- DECISION: A site outside every definition has no scope (±3 only). A cited line inside a definition over 400 lines has no scope.
- DECISION: Head directory: `EVAL_HEAD_DIR`, else `<manifest dir>/../<pr>/head`, else `<ws>/pr/head`. The grader passes the immutable fixture `head/`, never the sandbox `pr/`.
- DECISION: `flags`, `findings_cited`, the refuted share and false positives keep reading raw citations, so they are unchanged.
- DECISION: The detector reads ranges on the head side, chosen from operand order; a `pr/base` operand reads both sides. "Either side" would give r18 t1 2 defects (`+133,21`).
- DECISION: The detector skips a path whose sandbox copy byte-equals the fixture's head or base, so a closed mount in either mode never fires.
- DECISION: A later-only line must be in neither head nor base and at least 8 characters. Multi-file reads credit only result lines that name the file. `must_match` needs at least 12 characters.
- DECISION: Text in a multi-target command that no header attributes needs corroboration. That is a range near the site plus the head file's own text near it, or `must_match`.
- DECISION: A diff to `/dev/null`, piped to `wc`, `grep -c/-q/-l` or `cmp`, or with an `is_error` result, never exposes.
- DECISION: BARE transcripts are scanned too.
- DECISION: `oracle_exposed_defects` is the diff and read union, as specified. `oracle_exposed_by_form` lets the lead pick. Unknown exposures are a separate list that the report counts as exposed.
- DECISION: The class 7 unit is the backtick span holding the token, else its line. The exemption holds when the unit is a substring of a fixture line. Whole-line equality would clear neither replication row; both are prose.
- DECISION: A 1.2.x review row gets `grader_rule:"pm3"` and null new rates; nothing is inferred.
- DECISION: `row_writer_version:"1.4"` gates the `--validate` requirement, so legacy rows still validate.
- DECISION: Dissent precedence is disabled > budget > preflight > error > none. Disabled comes from the sandbox config or `dissent=false` evidence. A gate that did not run is null, and `dissent_absent_gates` includes disabled.
- DECISION: Report main reads keep oracle-exposed cells by default (the brief's labelled sensitivity). `--exclude-oracle-exposed true` applies FR-6's exclusion.
- DECISION: Valid cells are, per task, the smaller of the two arms' valid trial counts. `rules.min_valid_cells` defaults to 4 and is checked after the degenerate check. AR-29's degenerate-ids now reads insufficient.
- DECISION: Partition keys are `<v> · pin <12> · rule <r>`, split only when a version holds more than one pin or rule. The primary is the highest version's largest partition.
- DECISION: `corpus_sha256` hashes the SHA256SUMS above the key's `manifests/`. It is null for build tasks.
- DECISION: `overlay_mode` is the prefix of `mount_overlay` (head, base or none, per implementer A); an empty `gate_scripts_at_pr_version` is `[]`.
- DECISION: A numeric anchor uses the anchor's path part when it has a file extension, else the finding's `file`. The end is used only when it is greater than the start.

## What the lead must do
- Decide the FR-1 AC4 outcome. Either keep the union, or restrict exclusion to the diff form by setting `oracle_exposed_defects = by_form["diff"]` (a one-line change in `oracle_scan`'s return). Then record r17-t2 and r17-t3 as KF-049 findings.
- The Task 1.9 replication re-take should consider excluding r17-t2 and r17-t3 as well.
- Sprint 2 pre-registrations must say whether oracle-exposed cells are excluded in the main read; FR-6 says yes.
- Integration points:
  - Implementer D: `manifests/v1/` is read when present.
  - Implementer A: evidence keys `config_variant`, `mount_overlay`, `gate_scripts_at_pr_version`, `oracle_open` and `dissent` are consumed as specified.
  - Implementer C: `anchor_line` and `anchor_line_end`.
- CHANGELOG and README entries are yours (Task 1.12).
- Scratch to delete: `~/.cache/loa/cycle-131/s1b-scratch.*`, `s1b-grades/` and `s1b-validate.sh`, all under `~/.cache/loa/cycle-131/`.
