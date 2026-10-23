# Security analysis working file — sprint-1 audit (task review-r23), 2026-10-21

Scope: `pr/head.diff` (16 files). Trust model: the suite root (task.yaml, hidden/, fixture/, MANIFEST) and `<run-dir>/{snapshots,transcripts,eval}` are harness-owned; `<run-dir>/sandbox/` is agent-controlled; `--repo` history is operator-supplied.

## Sources (untrusted entry points)

| # | Source | Trust | Status |
|---|--------|-------|--------|
| S1 | `sandbox/` tree copied to `grading/final` (`ablation-grade.sh:1076`) | agent | CONFIRMED (M3 sparse/huge files; M6 forged summary) |
| S2 | `sandbox/review.md`, `a2a/sprint-1/{engineer,auditor}-feedback.md` (`:1055-1063`, `:875-876`) | agent | CONFIRMED (M4 verdict tamper; citations: SAFE — regex-extracted) |
| S3 | `snapshots/<L>.bundle` + `index.json` (`:682-715`) | harness-written from agent repo | PARTIAL (L1 export-ignore; M5 data_filter floor) |
| S4 | `transcripts/events-*.jsonl` (`:1010-1035`) | harness | SAFE (json.loads, ids only) — M8 false positives |
| S5 | `eval/adversarial-*.json` (`:854-868`) | harness | SAFE for safety; H2 correctness |
| S6 | task.yaml / hidden/manifest.json (`:319-419`) | suite (frozen) | SAFE (safe_rel on every path) |
| S7 | git history via `--repo` (`seed_tasks.py:43-134`) | operator | SAFE paths (safe_path, symlink refusal); L3 global gitconfig; L8 code execution on host |
| S8 | `labels/*.tsv` rows (`seed-corpus-from-record.sh:235`) | corpus | SAFE; L9 ordering |

## Sinks (dangerous operations)

| # | Sink | Status |
|---|------|--------|
| K1 | `docker run … -v <tree>:/workspace:rw` (`:506-508`) | CONFIRMED M1 (no pids/memory/cpus caps), M2 (timeout w/o -k, no --name) |
| K2 | `tarfile.extractall(filter=keep)` (`:713-714`) | SAFE when available; M5 availability |
| K3 | `shutil.copyfile`/`open().read()` on agent files (`:296`, `:732`) | CONFIRMED M3 |
| K4 | `git archive <commit>` in scratch bare repo (`:700`) | PARTIAL L1 |
| K5 | `subprocess.run(["bash", recall-vs-defects.sh …])` (`:921`) | SAFE (argv; gates-combined.md is `path:line` only) |
| K6 | `run_tests` on operator host (`seed_tasks.py:212`) | L8 (design) |
| K7 | `patch -s -p1 -i` (`seed_tasks.py:227`) | L4 |
| K8 | `write_file` from history (`seed_tasks.py:138-144`) | SAFE (safe_path; mode 120000 refused) |
| K9 | `remove_path`/`fresh_dir` on `<run-dir>/grading` (`:1039-1053`) | SAFE (run-dir harness-owned; rmtree does not follow links) |

## Test controls that cannot fire

| Where | What | Status |
|-------|------|--------|
| `pipeline-run.bats:498,503` | hidden-byte leak guard (AC-2.6/AC-5.5) | CONFIRMED H1 (bats 1.13 repro) |
| `ablation-grade.bats:501,502,505` | DEC-0413 ids-only | CONFIRMED M10 |
| `ablation-grade.bats:512,513` | no `source`/`eval` in grader | CONFIRMED M10 |
| `seed-corpus.bats:189` | SC-7 real file not excluded | CONFIRMED M10 |

## Verified by reproduction (this host)

- bats 1.13.0: mid-test `! grep -q x <<<"x"` passes; as last command / `run !` / `|| false` fails.
- Python 3.11.2: `hasattr(tarfile, "data_filter")` → False.
- `shutil.copyfile` of a 300 MB sparse file → 300 MB on disk.
- `git archive HEAD` drops a file marked `export-ignore` in the commit's `.gitattributes`.
- `timeout 1 bash -c 'trap "" TERM; sleep 3'` runs 3 s, rc 124.
- `sha256sum -c SHA256SUMS --ignore-missing`: pr-14.json, pr-15.json OK; only generated-path `fix_regions` removed.
- Real dissent envelope (`a2a/sprint-1/adversarial-review.json`): every finding has `anchor` = `file:symbol` + `anchor_line`, none has `file`/`line`.

Deferred: AG-18 dependencies (`pipeline-run.sh`, `freeze.sh`, `no-secrets.sh`, smoke tasks) are not in the PR — not assessable here.
