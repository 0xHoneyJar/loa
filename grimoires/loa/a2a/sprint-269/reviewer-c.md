# Implementer C — Sprint 1 (global 269), Tasks 1.7a, 1.7b, 1.7c

Model: global.anthropic.claude-opus-5-5. Worktree `loa-wt-s1c` at 346dbb87; patch `~/.cache/loa/cycle-132/patches/s1-c.patch`.

## What was built
- 1.7a: `evals/harness/run-ablation.sh` (matched cells as k session units, attempt limit, session records, cell finalisation, `--batch-context`, rerun attempt bound); `evals/harness/pipeline-run.sh` (`--batch-context`, `mount_cheval` probe and exit-3 refusal, vocabulary-derived `config_edits`); `evals/harness/lib/sandbox-mount.sh` (`print_toggle_vocabulary`, `bare_sessions` toggle); `evals/harness/validate-suite.sh` (vocabulary from the lib, k keys); `evals/suites/ablation-2.0.yaml` (two matched arms, `mount_cheval_ok`); `evals/harness/took-effect.sh` (`mount_cheval_ok`, `bare_sessions_matched`, cell mode).
- 1.7b: `evals/harness/ablation-grade.sh` 1.3.2 (`--union`, `false_positive_rule`, `multi_credit_citations`, egress class 9); `evals/harness/ablation-row.sh` 1.5 (cell rows, the 1.5 fields, evidence-only `disabled`); `evals/harness/ablation-report.py` 1.4 (label partitions, matched section, intention to run).
- 1.7c: `evals/analysis/c132/registration.py` (new: build/verify); `run-ablation.sh --registration`, `--spend-since`, `--spend-bin` (bindings, MANIFEST fields, resume refusal, derived `--max-usd`).
- Tests: the eight listed bats files, new `evals/tests/registration.bats`, new `evals/analysis/c132/tests/test_registration.py`; fixtures `evals/tests/fixtures/{ablation-pipeline-stub.sh, ablation-grade-stub.sh, mount-lib-stub.sh}`.

## How it was tested
`~/.cache/loa/cycle-128/s2d/bin/bats <file>`; `python3 -m unittest discover -s evals/analysis/c132/tests`.
| file | cases |
|---|---|
| run-ablation.bats | 58 (11 RAB-c132 + RAB-19, RAB-c131-5 updated) |
| pipeline-run.bats | 87 (6 PR-c132; eval_only cases moved to the flag) |
| ablation-grade.bats | 61 (5 AG-c132; AG-10/13/18/33/45/51/54/56 updated) |
| ablation-row.bats | 45 (4 RW15; RW14-1/3 updated) |
| ablation-report.bats | 55 (3 AR-c132) |
| took-effect.bats | 33 (3 TE-c132) |
| arm-toggles.bats | 26 (2 AT-c132; AT-13 updated) |
| validate-suite.bats | 19 (2 VS-c132) |
| registration.bats (new) | 4 |
| test_registration.py | 6 |
Full `evals/tests/`: 581 cases, 581 ok (535 + 46 new). `bash -n` on every changed script and `tools/check-no-{raw-sha256sum,swallowed-jq,raw-curl}.sh`: clean. c131 root dry runs (default arms and the six c131 arms): stdout byte-identical to 346dbb87; MANIFEST only gains the new keys.

## AC evidence
- FR-3 AC1 dry run shows k sessions: PASS RAB-c132-1.
- FR-3 AC2 stub k=3, per-session transcripts, summed cost: PASS RAB-c132-2.
- FR-3 AC3 union credits once, `recall_session1`: PASS AG-c132-1, AG-c132-3.
- FR-3 AC4 took-effect pass/fail, row validate, report partitions, suite validate: PASS TE-c132-2/3, RW15-2/4, AR-c132-1/2, VS-c132-1.
- D-7.3 session validity, attempt limit, intention-to-run: PASS RAB-c132-3/4/5/11, AR-c132-3.
- FR-7 AC1 `--registration` recorded and resume-bound: PASS RAB-c132-8/9, REG-4.
- Spend gate (SKP-003b) concurrent launches, retries, resume: PASS RAB-c132-10, RAB-c132-4, RAB-c132-3.
- registration.py verify catches a changed corpus sum: PASS REG-3, test_registration.
- bd-9zmfn: PASS AG-c132-1/3 (`false_positive_rule`). bd-eriso: PASS AG-c132-4. bd-56nn6: PASS PR-c132-1/2/3, RAB-c132-7, TE-c132-1. bd-jszcp: PASS RW14-3. bd-st02i: PASS PR-c132-4, RAB-c132-6, RAB-c131-5. bd-gdl5s: PASS AT-c132-1, PR-c132-5.
- 1.3.1 outputs unchanged: PASS AG-c132-5 (the 346dbb87 grader re-grades the same run; recall, FPs, contamination, verdicts equal).

## DECISION bullets
- DECISION: trials keep their one in-line transport retry (the a1_full path is unchanged); the 3-attempt limit binds reruns (a replacement counts the old row's attempts; `--rerun` refuses a row at 3, `--rerun-status` skips it). Rejected: in-line re-runs of cap_failure/interrupted trials. RAB-19 updated.
- DECISION: validate-suite checks `bare_sessions_matched(_fable)` only when present; run-ablation refuses to plan a matched arm on a task without it. Rejected: requiring it on every review-catch task (the frozen c131 root would fail).
- DECISION: `--union` reads `<cell>/meta/cell.json`, the grader's one meta/ read; cell.json holds no arm id and no run_id (it embeds the arm); the row writer takes the run_id from session 1.
- DECISION: union verdict fields are null (per_session carries each); label_set/labels_meta come from the first valid session's grade.
- DECISION: recall_session1 uses the union recall's rule; recall_pm3_session1 sits beside it; precision_session1 = pm3 caught ÷ (caught + false_positives).
- DECISION: bd-9zmfn — false_positives already used ±3 on the manifest, the rule of recall_pm3 (decision statistic, DEC-0638); `false_positive_rule: "pm3"` states it and the numbers stay. Rejected: recomputing under pm3_or_same_function (a non-decision rule).
- DECISION: class 9 is read first; gh naming the repository counts (it reaches api.github.com unnamed); heredoc bodies only when fed to an interpreter (KF-046). curl/gh of the repo now read network_egress, not repo_name (AG-51/54 updated).
- DECISION: the mount_cheval probe is host `python3 -I -B` importing `loa_cheval` and `loa_cheval.providers` (KF-050) before any agent runs. Rejected: a docker probe (shifts every container test's calls).
- DECISION: dissent-enabled = mounted, gates not false, and AUDIT, or REVIEW without dissent: false; `mount_cheval_ok` added to a1_full, a2, a3, a5, a6, a7, a1_review_only, a1_no_dissent, a1_full_openmount.
- DECISION: bd-jszcp — "disabled" comes from the harness evidence lines dissent=false (review), gates= and flatline= (both gates); the brief named dissent=false only, but the other two are the same harness evidence and keep A4/A5 reading disabled.
- DECISION: the vocabulary has three columns (key, values, config edits) so config_edits derive from it; the mount stub's copy is pinned byte-equal (AT-c132-1).
- DECISION: a refused launch (exit 3) is status infrastructure_error (excluded, never re-run).
- DECISION: a cell is completed with ≥ 1 valid session, degraded below ⌈k/2⌉; with none, infrastructure_error (contaminated when a session was). A clean agent_error session is valid.
- DECISION: each session is charged when it ends (every attempt; the trial charge rules); the cell row adds counters only; STATUS spend gains `sessions_usd` for plans with cells; --resume recharges from the records.
- DECISION: `--batch-context` defaults to the batch name; another id on --resume is refused.
- DECISION: the spend gate is derived at launch only (`--spend-since`, else the registration's `kickoff`; the smaller of it and a given --max-usd); --resume keeps the MANIFEST cap. registration.py gained optional `--kickoff` and `--image-digest`.
- DECISION: the registration pre-flight refuses a mismatched suite manifest, corpus sums, pin or image digest.
- DECISION: registration.py canonicalises through `lib/jcs.sh` (rfc8785, on CI); paths relative to `--repo`; k_by_task over the grouped tasks; analysis_tree_sha256 is the git tree id (SDD name kept).
- DECISION: MANIFEST `bare_sessions_by_task` is {arm: {task: k}} (the arms' k differ).
- DECISION: report 1.4 keeps matched arms out of the components (still 9); new sections render only when they have content.
- DECISION: edited fixtures outside the listed test files: `evals/tests/fixtures/{ablation-pipeline-stub.sh, ablation-grade-stub.sh, mount-lib-stub.sh}` (they reject unknown flags).

## CHANGELOG entry text (### Added)
- Compute-matched bare arms `a0_bare_matched` and `a0_bare_fable_matched` (cycle-132 FR-3): `run-ablation.sh` ran each cell as k BARE session units with a 2-re-run attempt limit, session records, `meta/cell.json`, a union grade and one row; `--resume` re-ran only the sessions without a record.
- `ablation-grade.sh` 1.3.2 added `--union` cell grading, `multi_credit_citations`, `false_positive_rule` and contamination class 9 `network_egress` (git, curl, wget, gh or python toward GitHub hosts; WebFetch and WebSearch naming the repository).
- `ablation-row.sh` 1.5 added matched-cell rows, `all_spend_usd`, the session-1 figures, `label_set`, `batch_context`, `mount_cheval` and `registration_sha256`; `ablation-report.py` 1.4 added label-set partitions, a matched-arm section and an intention-to-run table.
- `evals/analysis/c132/registration.py` built and verified the JCS-canonical `REGISTRATION.json`; `run-ablation.sh --registration` bound a batch to it, refused a resume after a change, and derived `--max-usd` from the registered cap minus the cycle meter.
- `pipeline-run.sh --batch-context` replaced the `LOA_ABLATION_BATCH_CONTEXT` variable; a pre-launch `mount_cheval` probe refused a dissent-enabled arm on a broken mount; took-effect gained `bare_sessions_matched` and `mount_cheval_ok`.
- `lib/sandbox-mount.sh print_toggle_vocabulary` became the one toggle table that `validate-suite.sh` and the dry run's config edits read.

## What the lead must do
- Apply the patch. Implementer B also edits `ablation-grade.sh` (label_set/labels_meta) and `ablation-grade.bats`; my hunks are the GRADER_VERSION line (1.3.2), two argparse lines, new functions before `def transcripts` and `def structural_command`, three lines in `grade()`, the `--union` branch in `main()`, and a header paragraph. A conflict is possible only if B also bumped the version line.
- If B's move touches `grimoires/loa/evals/ablation-2.0`, rerun `run-ablation.bats` and `registration.bats` (they copy it).
- Add the CHANGELOG text above; close bd-9zmfn, bd-eriso, bd-56nn6, bd-jszcp, bd-st02i, bd-gdl5s with the AC evidence; KF-050's workaround can now name the `mount_cheval` line.
- Register with `--pin` = the Sprint 2 pin and `--kickoff 2026-10-21T00:23:00Z`; run-ablation refuses a pin mismatch.
- `registration.py` needs rfc8785 for `lib/jcs.sh` (CI installs it; the tests skip without it).
- No `.claude/` file changed.

## Round 1
Incremental patch `~/.cache/loa/cycle-132/patches/s1-c-r1.patch`, diffed against tree a798b909 (the round-0 tree); the result is tree 33abff3f.
- **spend.sh `--since` covers run rows.** A run row now counts only when its `started` (else `finished`) is at or after TS. A row with no timestamp, or one that does not parse, still counts and gets one stderr note per file. The JSON gains `runs_rows_before_since` and `runs_rows_undated`, and the header now states these semantics. The spend fixtures gained `started`, and SP-10 is new. run-ablation.sh's gate was unchanged and already passes `--since`.
- **Rows carry `took_effect`.** I chose the runner side over re-running took-effect inside the row writer, because the row writer then needs no suite file. took-effect.sh gained `--json-out F` (`--run-dir` only; the text output is unchanged). run-ablation.sh writes `meta/took-effect.json` for every trial and session and for the cell, removing any stale copy first. ablation-row.sh 1.5 rows it as `{rule: bool}` and writes null when no record exists. An unreadable record reads `{took_effect_record: false}` so the filter fails it. `--validate` requires the field on 1.5 rows (object or null) with boolean values.
- DECISION: an unreadable took-effect record fails closed (`{took_effect_record: false}`) rather than null, because the analysis treats null as "not recorded" and passes it.
- DECISION: a custom `--took-effect-bin` must now accept `--json-out` (documented in the runner header).
- **Tests:** spend.bats 10, ablation-row.bats 46 (RW15-5 new), took-effect.bats 34 (TE-c132-4 new), run-ablation.bats 58 (RAB-c132-2 and RAB-c132-7 assert `took_effect`), registration.bats 4. All green. `bash -n` and `tools/check-no-swallowed-jq.sh` are clean.

## Round 2
Incremental patch `~/.cache/loa/cycle-132/patches/s1-c-r2.patch`, diffed against tree 33abff3f (my round-1 tree); the result is tree 7af8543a. It also applies cleanly on caf88c33, which already holds B's recall-vs-defects.sh change; I checked with git apply on an export.
- **Cause:** CITE required a path extension of at most 6 characters, so `head/.loa.config.yaml.example:127` and `head/evals/harness/Dockerfile.ablation:19` never parsed. That is why the reference self-check failed on review-r16, r20 and r22: I reproduced recall 0.8333, 0.9 and 0.9 on caf88c33.
- **Fix:** the extension class is now {1,12} in both copies of CITE (evals/graders/recall-vs-defects.sh, now grader 1.3.1, and evals/harness/ablation-grade.sh, now 1.3.3), and in the grader's numeric-anchor path check, which has the same limit. Every other boundary rule is unchanged. A text that parsed before parses to the same citations, because the greedy path still splits at its last dot before the colon. Both headers document the bump. Rows take grader_version from grade.json; the report partitions by rule, not by version.
- DECISION: the oracle detector's FILEISH token rule keeps {1,6}. It decides which tokens a Bash command reads, not citations, so changing it would move the oracle fields outside this fix.
- **Proof:** with the patched grader, all 14 tasks of ablation-2.0-c132 at caf88c33 pass `--self-check reference` at recall 1.0. AG-c132-5 (re-grading a run with the 346dbb87 grader) still gives the identical recall block. RG-c132-1 cites .loa.config.yaml.example, Dockerfile.ablation, .generated.ts and .markdown, and checks that a 13-character extension, a URL and a date still do not cite. AG-c132-6 runs a reference self-check on a synthetic long-extension task (PASS 2/2) and credits a numeric dissent anchor on Dockerfile.ablation.
- **Tests:** eval-recall-grader.bats + ablation-grade.bats + recall-baseline-freshness.bats 120 of 120; seed-corpus, arms-report and run-arms 39 of 39. bash -n is clean. RG-17 and three AG version pins were updated.

## Round 3 (Sprint 269 dissent findings)
Incremental patch `~/.cache/loa/cycle-132/patches/s1-c-r3.patch`, diffed against tree 7af8543a (my round-2 tree); the result is tree fb8db13e. `git apply --check` passes on an export of the branch HEAD 2ab4ca72, which carries B's grader hunks.
1. **DISS-001/C-001/C-003, class 9 per simple command (grader 1.3.4).** The command is now read with its heredoc bodies stripped and split by split_segments (newline, ;, &&, ||, | outside quotes). Each command is judged by the program in command position (via seg_words): curl/wget, git fetch|clone|pull|ls-remote, gh api|pr|issue|repo, python -c with urllib/requests and a host, and curl/wget inside $( … ) or backticks. A heredoc body counts only when fed to an interpreter: a python body needs urllib/requests plus a host; a bash or sh body is read command by command. Reviewer prose, words spread across separate commands, and grep/rg/echo naming a host are clean (AG-c132-7, 12 cases). AG-c132-4, AG-51 and AG-54 are unchanged and pass. AG-c132-5's recorded-run equality holds.
2. **DISS-002, spend.sh.** A row now counts its numeric `all_spend_usd` (every attempt and every session), else `cost_usd`; the larger figure per run_id still wins. Documented; SP-11 is new.
3. **DISS-003, fail closed.** The jq step that sets the row's `took_effect` (it is in ablation-row.sh, not the runner) now requires its output to be an object. An empty, `null`, array or string record reads `{took_effect_record: false}` (RW15-6).
4. **DISS-C-006, contract text.** The cell.json contract now lists every written field in both the grader header and the runner header, and says there is no run_id.
5. **DISS-C-007, validity.** The row takes cell validity from cell.json alone. A valid session whose pipeline.json is unreadable, or holds no BARE record, stays valid and counted. It is listed in the new `sessions_meta_unreadable` field ([] on a cell, null on an ordinary row; --validate checks the type). The cell's run_id is taken from the first readable session with any `-s<i>` suffix removed (RW15-7).
- DECISION: node, perl and ruby heredoc bodies are not read for egress, which keeps class 9 a stated lower bound; adding them would mean guessing their HTTP APIs.
- **Tests:** ablation-grade.bats 63, run-ablation.bats 58, took-effect.bats 34, registration.bats 4 (159 of 159), spend.bats 11, ablation-row.bats 48. bash -n and check-no-swallowed-jq are clean.

## Round 4 (Sprint 269 audit A1–A4; grader 1.3.5)
Incremental patch `~/.cache/loa/cycle-132/patches/s1-c-r4.patch`, diffed against tree 9cf5fd50 (my tree after copying 23842ff7's ablation-grade.sh and ablation-grade.bats into it); the result is tree 90f3ba4e. Two files change, +166 −27.
- **A1:** a bash, sh, zsh, dash or ksh command with -c (or combined flags such as -lc) has its string read with the same rules, recursively up to depth 3.
- **A2:** EGRESS_HOST now matches any host ending in github.com, githubusercontent.com or github.io, subdomains included. EGRESS_PYLIB adds urllib3, http.client, httpx, aiohttp, pycurl and socket.
- **A3:** class 9 reads command words with egress_words, which strips leading shell keywords and the listed wrappers with their options. <( … ) is read like $( … ). A heredoc piped into an interpreter (cat <<'EOF' | bash) counts as fed to it. A host plus a fetcher token anywhere in one heredoc-stripped simple command is egress; the fetchers are curl, wget, git fetch|clone|pull|ls-remote, gh api|pr|issue|repo, and pip/npm/go install. A pipeline whose curl or wget stage gets a host from another stage (echo url | xargs curl) is also egress.
- **A4:** --union refuses a valid session whose grade.json grader_version is not this grader's, and per_session[] records each session's grader_version.
- DECISION: the keyword and wrapper stripping lives in egress_words, used by class 9 only. seg_words, which the oracle detector also uses, is unchanged, so oracle fields cannot move.
- DECISION: the pipeline rule counts curl and wget stages only. git and gh stages would flag `git log | grep github.com`.
- **Tests:** AG-c132-8 covers 28 bypass forms that are now egress, plus 6 negatives that stay clean: the round-3 prose heredoc, separate commands, grep|grep, rg, `git log | grep github.com`, and echo of github.io. AG-c132-9 covers the stale-version union. The full ablation-grade.bats on an export of 23842ff7 with the patch applied gives 70 of 70; AG-c132-5 is skipped there because the export has no history. In my worktree AG-c132-5's recall-block equality passes. My worktree lacks B's moved manifests, so B's AG-LS1–4 can only run on the export. bash -n is clean.
