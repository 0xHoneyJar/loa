# Security analysis working file — sprint-1 audit (PR: sprint-259 grader + seeders)

Scope: `pr/head.diff`, 16 files under `evals/`. Trust levels: OPERATOR (task.yaml, suite root, CLI args),
HARNESS (run-dir layout, transcripts, eval/ envelopes, snapshots), AGENT (sandbox/ contents, test stdout,
review.md, feedback files, git history of the sandbox), HISTORY (the seeded repository's commits).

## Sources (untrusted entry points)

| # | Source | File:line | Trust | Status |
|---|--------|-----------|-------|--------|
| S1 | test/pytest/bats stdout parsed for pass/fail counts | ablation-grade.sh:546-621 | AGENT | CONFIRMED → HIGH-001 |
| S2 | pytest node ids used as file paths (`coll_err`, `def_line`) | ablation-grade.sh:533-543, 574-581 | AGENT | CONFIRMED → MED-008 |
| S3 | sandbox review.md / feedback files → `citations()` | ablation-grade.sh:818-837, 871-889 | AGENT | CONFIRMED (quadratic regex) → MED-011 |
| S4 | sandbox feedback files → `gate_verdict` (symlink followed) | ablation-grade.sh:764-790 | AGENT | CONFIRMED → LOW-002 |
| S5 | sandbox tree copied to grading/final (symlinks replicated) | ablation-grade.sh:271-298, 1076 | AGENT | SAFE (ensure_parent unlinks symlinked parents; container mount) |
| S6 | snapshot bundles → tar extraction | ablation-grade.sh:682-715 | AGENT | SAFE (`tarfile.data_filter`, EXCLUDE_TOP) — Python ≥3.11.4 only (MED-002) |
| S7 | transcripts events-*.jsonl → contamination scan | ablation-grade.sh:987-1035 | HARNESS | SAFE (read only; regex FP → HIGH-006, allowlist → MED-009) |
| S8 | task.yaml fields (commands, paths) | ablation-grade.sh:319-419 | OPERATOR | SAFE (safe_rel on every path; argv commands) |
| S9 | git history paths/blobs materialised into fixtures | seed_tasks.py:57-60, 138-155 | HISTORY | SAFE (safe_path, symlink blobs refused) |
| S10 | repository test commands run on the host during the proof | seed_tasks.py:201-222 | HISTORY | N/A (own repository; documented) |
| S11 | commit subject → TASK.md / task.yaml | seed_tasks.py:251-262, 269-290 | HISTORY | SAFE (control chars stripped, JSON-encoded scalars) |
| S12 | CLI args (--paths, --since, --repo) | seed_tasks.py:513-544 | OPERATOR | SAFE |

## Sinks (dangerous operations)

| # | Sink | File:line | Status |
|---|------|-----------|--------|
| K1 | `docker run -v <tree>:/workspace` + `timeout 120 <cmd>` | ablation-grade.sh:506-508 | SAFE (network none, read-only, uid mapped); no `-k` → MED-004 |
| K2 | host executor `env -i … <cmd>` in the agent's tree | ablation-grade.sh:511-515 | PARTIAL → MED-010 (no isolation, documented) |
| K3 | `open(os.path.join(tree, <node id>))` | ablation-grade.sh:536, 576 | CONFIRMED → MED-008 |
| K4 | `remove_path` / `fresh_dir` under run-dir | ablation-grade.sh:235-247, 1039-1042 | SAFE (lexists/islink checked first) |
| K5 | `patch -p1 -i reference.patch` in self-check | ablation-grade.sh:1175 | SAFE (OPERATOR input); no tool check → LOW-001 |
| K6 | `recall-vs-defects.sh` with agent citations file | ablation-grade.sh:921 | SAFE (argv; file content only) |
| K7 | `shutil.move(stage/tid → tasks/tid)` | seed_tasks.py:604 | PARTIAL → HIGH-001(review) stage collision |
| K8 | `git apply` fallback | seed_tasks.py:229 | CONFIRMED → HIGH-002(review) |
| K9 | `bash no-secrets.sh <tdir>` | seed_tasks.py:505 | SAFE (fail-closed; misleading message when missing → LOW-006) |
| K10 | `write_file` into staging | seed_tasks.py:138-144 | SAFE |

## Deferred / unable to assess

- `evals/graders/no-secrets.sh`, `evals/harness/freeze.sh`, `evals/graders/recall-vs-defects.sh`, the smoke tasks: not in the PR; behaviour assumed from the callers.
- The bats suites were not executed here: Python 3.11.2 lacks `tarfile.data_filter`, `patch` is absent, `/tmp` is noexec.
