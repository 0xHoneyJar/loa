# Security analysis working file — sprint-1 (review-r23), 2026-10-21

Scope: `pr/head.diff` (16 files; evals/harness, evals/tests, evals/fixtures). No `src/`, `lib/`, `app/`
or `.claude/` file is touched. Trust model from the grader header (head/evals/harness/ablation-grade.sh:35-42):
the agent-written `sandbox/` and everything derived from it (snapshots, transcripts, test output) is UNTRUSTED;
the task directory, MANIFEST.sha256, run_dir/eval/, snapshots/index.json are harness-written (trusted).

## Sources (untrusted entry points)

| # | Source | Trust | Reaches | Status |
|---|--------|-------|---------|--------|
| S1 | `sandbox/` tree (files, symlinks, conftest.py, ini files) → `copy_tree` :1076 | agent | docker `-v tree:/workspace:rw` :507, host `cwd=tree` :515 | CONFIRMED (forgeable results; symlink chmod) |
| S2 | test-command stdout/stderr → `parse_pytest` :546 / `parse_tap` :600 | agent code in-process | `hidden_tests`, `all_pass`, `verdict_accuracy` | CONFIRMED (forged summary reproduced) |
| S3 | pytest node ids in output → `def_line` :533, coll_err expansion :574-581 | agent | `open(tree/<path>)` | CONFIRMED (reads outside tree; low impact) |
| S4 | snapshot bundles → `git bundle unbundle` / `git archive` / tarfile :694-714 | agent commits, harness-bundled | grading/<label> tree | SAFE (safe_rel + data_filter; but data_filter absent on 3.11.2 → TypeError) |
| S5 | `sandbox/review.md`, a2a feedback files → `citations` :818, `gate_verdict` :764 | agent | recall, verdict | SAFE (regex only, no exec) |
| S6 | transcripts events-*.jsonl → `contamination` :1010 | agent-influenced tool inputs | `contaminated` | SAFE (regex only); substring FP on "hidden" |
| S7 | `run_dir/eval/adversarial-*.json` → `envelope_texts` :854 | harness | recall | SAFE; shape mismatch drops citations |
| S8 | task.yaml / hidden/manifest.json / reference.patch → `load_task` :319, `patch` :1175 | frozen suite | trees | SAFE (safe_rel on every path) |
| S9 | git history paths → seed_tasks.py `safe_path` :57, `put_from` :147 | own repo history | stage dir | SAFE (relative, no .., no symlink blobs, mount-owned refused) |
| S10 | wrapper `"$@"` → argparse (last `--no-secrets` wins) :77-78 | operator | secrets scan on/off | PARTIAL (silent disable) |
| S11 | labels TSV / head files → seed-corpus-from-record.sh `generated_path` :205 | corpus authors | fix_regions | SAFE |

## Sinks

| # | Sink | Guard | Status |
|---|------|-------|--------|
| K1 | `docker run` argv :506-508 | list argv; `:`/`,` refused in run_dir :1050; `--network none --read-only --user uid:gid` | PARTIAL — no `--pids-limit`, `--memory`, `--cpus`, `--cap-drop`, `no-new-privileges`, no `--name`/kill on outer timeout |
| K2 | host `env -i … timeout` :513-515 | PATH passed through; agent code runs with the grader's uid | PARTIAL — documented mode, no warning |
| K3 | `os.chmod` in `remove_path` :242 | none (follows symlinks) | CONFIRMED (medium) |
| K4 | `shutil.rmtree` :245 | fd-based, top-level link unlinked first | SAFE |
| K5 | `tf.extractall(filter=keep)` :714 | safe_rel + data_filter | SAFE when available; TypeError on < 3.11.4 |
| K6 | `subprocess.run(["yq"…])`, `["git"…]`, `["patch"…]`, `["bash", freeze.sh]`, `["bash", recall-vs-defects.sh]` | list argv, trusted inputs | SAFE |
| K7 | `write_grade` :1154 tmp+replace under run_dir | run_dir not agent-writable | SAFE |
| K8 | seed `write_file` :138 under private stage | safe_path | SAFE |
| K9 | seed `run_tests` :201 executes repo-history tests on host | own repo | SAFE (trusted) |

## Second-order flows

- Agent symlinks copied verbatim (:283, :294) → survive into grading/final → re-grade `fresh_dir` :1041 → `remove_path` chmod follows them (K3). CONFIRMED.
- Agent-added root `conftest.py` / `pyproject.toml` not in `grader_protected` → loaded by the hidden-test run → S2. CONFIRMED.
- Agent-added test files under the swept directory → counted in `hidden_tests` (:1080). CONFIRMED (review H2).

## Deferred / scope limits

- `pipeline-run.sh`, `freeze.sh`, `recall-vs-defects.sh`, `no-secrets.sh` are not in the PR; their behaviour is inferred from callers and `docker-stub.sh:56` (flag list).
- The sixteen tasks and `MANIFEST.sha256` the PR title names are not in the diff; unable to assess the freeze.
- No documentation-coherence subagent reports exist in this workspace (PR files are the entire input).
