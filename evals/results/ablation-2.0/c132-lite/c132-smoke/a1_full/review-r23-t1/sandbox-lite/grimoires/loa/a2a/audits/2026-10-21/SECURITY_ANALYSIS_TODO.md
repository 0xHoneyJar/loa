# Security analysis working file — sprint-1 audit (pr/head.diff), 2026-10-21

Scope: 16 files; code = evals/harness/ablation-grade.sh, evals/harness/lib/seed_tasks.py, the two seeder wrappers,
seed-corpus-from-record.sh (generated-path rule), validate-suite.sh (source.churn), bats suites, docker-stub.sh.
App-zone scope analysis script (security-audit-scope.sh) scans the checkout, which holds no evals/ tree here (PR files only) — skipped.

## Sources (untrusted → trust level)

| # | Source | Trust | Reaches | Status |
|---|--------|-------|---------|--------|
| S1 | `<run-dir>/sandbox/` tree (agent-written) | UNTRUSTED | copy_tree → grading/final; churn; pytest/bats execution (ablation-grade.sh:1076-1080) | CONFIRMED (root conftest.py forges hidden result; mode-000 file aborts; no size cap) |
| S2 | `sandbox/review.md`, `a2a/sprint-1/*.md` (agent-written) | UNTRUSTED | gate_verdict / review_md_verdict / citations() regex (ablation-grade.sh:764-837) | CONFIRMED (CITE quadratic; verdict sentinel "none") |
| S3 | `transcripts/events-*.jsonl` tool inputs (agent-chosen text) | UNTRUSTED | contamination() regexes (ablation-grade.sh:939-984) | CONFIRMED (GIT_HIST cubic backtracking; ABS_WORD false positives) |
| S4 | `snapshots/*.bundle` + index.json (harness-written, agent-authored content) | SEMI-TRUSTED | git bundle unbundle / git archive / tarfile.extractall(filter=) (682-715) | PARTIAL (filter guard needs Py 3.12; .gitattributes export-ignore can hide files) |
| S5 | `eval/adversarial-*.json` (harness copies) | TRUSTED (harness) | envelope_texts | SAFE (anchor shape mismatch is a functional gap, not a security one) |
| S6 | task.yaml / hidden/manifest.json / grader_protected (suite author, frozen) | TRUSTED | load_task; safe_rel on fixture, overlay, protected, reference_patch; NOT on review_catch.manifest/fixture (407, 436) | PARTIAL (low) |
| S7 | git history of the seeded repo (commit paths, blobs, subjects) | SEMI-TRUSTED | seed_tasks.py safe_path / mount_owned / sanitise / write_file | SAFE (symlink blobs refused; `..` refused; subjects sanitised) |
| S8 | CLI args (--out, --since, --paths, task id, run dir) | OPERATOR | parse(); task id regex; ':'/',' refused in run dir | SAFE |

## Sinks

| # | Sink | Guard | Status |
|---|------|-------|--------|
| K1 | `docker run … -v <tree>:/workspace:rw … timeout 120 <argv>` (506-508) | --network none, --read-only, tmpfs, --user; NO --pids-limit/--memory/--cpus; timeout without -k; TimeoutExpired kills client only | CONFIRMED (resource caps absent, container leak on client timeout) |
| K2 | host executor `env -i … timeout 120 <argv>` cwd=tree (513-515) | env scrubbed only; runs agent tree code as the operator uid with full fs access | CONFIRMED (documented mode; medium) |
| K3 | `tarfile.extractall(tree, filter=keep)` (714) | data_filter + safe_rel/EXCLUDE | PARTIAL (TypeError < 3.12; no fallback → no grade) |
| K4 | `shutil.copyfile` in copy_tree (296) | S_ISREG only; symlinks reproduced not followed | CONFIRMED (PermissionError abort; unbounded size) |
| K5 | `patch -p1` / `git apply -p1` in seeder proof (seed_tasks.py:225-230) | none on git fallback | CONFIRMED (false proof outcome when cwd under a repo) |
| K6 | `subprocess.run(["bash", no_secrets, tdir])`, `yq`, `freeze.sh`, `recall-vs-defects.sh` | argv vectors, trusted scripts | SAFE |
| K7 | `write_file()` in seeder (138-144) | safe_path | SAFE |
| K8 | `remove_path()`/`fresh_dir(grading)` (235-247, 1039-1042) | unlink symlinks, never follow | SAFE |
| K9 | pytest/bats configuration discovery inside graded tree (prepare, 657-674) | only paths in grader_protected restored/removed | CONFIRMED (CWE-807) |

## Deferred / unable to assess
- `evals/graders/recall-vs-defects.sh` and `freeze.sh` are not in pr/ and the checkout holds no evals/ tree: how cited paths with `..` in gates-combined.md are handled there is unassessed.
- Container image contents (loa-ablation:258) not available.
