# Security analysis working file — cycle-132 Sprint 271 (global 271) audit, 2026-10-23

Scope: `git diff 03e12ed0 3407ba63` restricted to the sprint's code and drivers (`evals/analysis/c132/`, `evals/tests/c132-report.bats`, `reports/review-catch-c132/scripts/`), plus the operational artefacts the sprint produced: the public record branch `record/cycle-132-conclusive-review-catch` (stage 1 `b15e546e`, stage 1b `3be895f2`), the reproducer's fresh-clone run and live rerun, the exploratory judge sessions, the release metadata commit `3407ba63`.

## Recon — untrusted sources (trust level)

| # | Source | Trust | Reaches |
|---|---|---|---|
| S1 | recorded run directories under `evals/results/ablation-2.0/c132-*` (agent-written sandboxes, transcripts, meta) | agent output, UNTRUSTED text | `record_lite.py plan_run_dir/scan_sandbox` (paths, bytes hashed, lite copies), `regrade_labels.py copy_cell` (hard links), the grader |
| S2 | `sandbox-manifest.json` / `sandbox-lite/` of the record (public branch) | produced by S1 via our tool; untrusted when cloned by a third party | `record_lite.py reconstruct_run_dir` (paths, symlink targets) |
| S3 | key manifests `evals/fixtures/review-prs/manifests/{,c131,v1,review}/pr-NN.json` and `task.yaml` | tracked, operator-curated | `defect_files`, `task_info`, `regrade_labels.key_for/task_manifest` |
| S4 | `rows.jsonl`, `INPUTS.json`, `REGISTRATION-*.json` | tracked analysis inputs | reads, reproduce engine, `reproduce.sh` (`jq -r`) |
| S5 | blind judge `labels.json` (model output) | UNTRUSTED (model) | `judge_defects.aggregate` (merged, validated against the key's item ids and verdict vocabulary) |
| S6 | judge packets (agent finding text + head lines + descriptions) | agent output, UNTRUSTED text shown to the judge model | the blind judge (prompt-injection surface, exploratory read only) |
| S7 | `cell.json` session lists (runner output) | runner-written | `regrade_labels.plan` (`run_dir` regex), `record_lite.sessions_of` |
| S8 | the Docker image and the pinned worktree | operator-controlled | `reproduce.sh` env check (digest vs registration) |

## Recon — dangerous sinks

| # | Sink | Guard |
|---|---|---|
| K1 | file writes under `--out/--work/--roots/--scratch` | `check_paths` refuses inside the results or suite roots; `safe_rel` on manifest paths; `write_atomic`; `remove_tree`/`safe_rmtree` bounded to the work root |
| K2 | hard links into work copies (`cp -al`) | `grading/` and `grade.json` excluded (the only paths the grader writes); same-filesystem check; evidence: rows re-derived byte-identically after the re-grades |
| K3 | `os.symlink(target)` in reconstruction (scratch only) | target unvalidated → LOW finding; the grader drops symlinks |
| K4 | `subprocess.run([...])` → `ablation-grade.sh`, `freeze.sh`, `ablation-row.sh`, `reads-c132.py`, `run-ablation.sh` | argument lists, no shell; paths refused with `:`/`,`; timeout 1800 s on grades |
| K5 | `git` operations by the stage-1 script (temporary index, `update-ref`, ICE push) | runs outside the repo's index; secret scan before commit; ICE blocks protected branches |
| K6 | public record branch contents | secret scan over 3,680 added paths (clean); no sandboxes/snapshots/grading/pr; lite set = agent outputs + defect-file copies + differing pr/ files + manifests (paths and hashes) |
| K7 | blind judge sessions (`blind-session.sh`, container, packet-only) | no credential copy; taint check (10/10 false); `--spend-row` metering |
| K8 | live rerun (`run-ablation.sh` at the pin, operator credentials from the environment) | the runner's own gates (DEC-0435 self-check log, spend gate, KF-048 token horizon); cap 110 |
| K9 | release metadata writes into `.claude/` by `update-loa-bump-version.sh` | bounded framework marker (scope, reason, 2 h expiry), deleted after; checksums regenerated and checked |

## Investigate pass — results

- S1→K1/K2: every write lands under the work/out roots; the record's `meta/`, `eval/`, transcripts unchanged (the 140 rows re-derived byte for byte after the re-grades); the one lead probe that touched a recorded `grading/` regenerated identical bytes (reviewed, NOTES 11:25Z).
- S2→K3: a manifest symlink `target` is recreated without `safe_rel` — LOW (scratch sandbox; no read follows a link; the record is ours).
- S3/S4: trusted, tracked; `reproduce.sh` reads them with `jq -r` and quotes every path.
- S5: labels validated (unknown item ids and verdict vocabulary refused; an item in two sessions refused); exploratory read only.
- S6: prompt injection from agent text into the blind judge is possible in principle; the judge prompt binds verdicts to the item vocabulary, every label is validated, and the read decides nothing (exploratory, post hoc) — LOW, residual.
- S7: `run_dir` anchored regex + isdir + not-symlink.
- K6: the sweep below (lite tree names; manifests list paths only).
- K8: the first live attempt was refused by the runner's gate (no spend); the second ran clean under the cap (USD 51.33).
- K9: marker written and removed within one command; the integrity hash of CLAUDE.loa.md unchanged (only the version stamp).
