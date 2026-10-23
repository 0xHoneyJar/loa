# Security analysis working file — sprint-1 audit (PR in pr/, 2026-10-22)

Scope: the 16 files of `pr/head.diff`. Trust model: the graded agent's sandbox, the snapshots it
produced, its transcripts and any code the hidden tests import are UNTRUSTED; task.yaml, hidden/,
the fixture, the suite MANIFEST and Loa git history are TRUSTED (operator-authored, frozen).

## Sources (untrusted entry points)

| # | Source | file:line | Trust | Status |
|---|--------|-----------|-------|--------|
| S1 | `<run-dir>/sandbox/` tree copied to grading/final (symlinks preserved) | head/evals/harness/ablation-grade.sh:271-296, :1076 | untrusted | CONFIRMED → H3 (symlink chmod), H7 (agent conftest loaded) |
| S2 | agent code executed by the hidden-test run, stdout parsed | :502-521, :546-594 | untrusted | CONFIRMED → H7, H5; PARTIAL → M5 (no resource limits) |
| S3 | `snapshots/*.bundle` + `index.json` (harness-written) | :682-716 | semi-trusted | SAFE (git_env isolates config; data_filter) but CONFIRMED H2 (API floor) |
| S4 | `transcripts/events-*.jsonl` tool_use inputs | :1000-1037 | untrusted | CONFIRMED → H1, M1 (false positives, not injection) |
| S5 | `sandbox/review.md`, a2a feedback files, `eval/adversarial-*.json` | :869-884 | untrusted text | SAFE (regex parse only); CONFIRMED H4 (shape mismatch) |
| S6 | task.yaml fields (fixture, manifest src/dest, grader_protected, commands) | :319-432 | trusted | SAFE (safe_rel everywhere) except review_catch.manifest/fixture → L8 |
| S7 | Loa git history (paths, blobs, subjects) read by the seeder | head/evals/harness/lib/seed_tasks.py:97-156 | trusted-ish | SAFE (safe_path, symlink refusal, argv git, sanitise) |
| S8 | `--out`, `--run-dir`, `--suite-root` argv | :180-200, :1240-1282 | operator | SAFE |

## Sinks (dangerous operations)

| # | Sink | file:line | Status |
|---|------|-----------|--------|
| K1 | `os.chmod(..., 0o700)` on walked dirs (follows symlinks) | ablation-grade.sh:239-244 | CONFIRMED (PoC: 0755 → 0700 on a target outside the tree) |
| K2 | `docker run … -v <tree>:/workspace:rw … timeout 120 <argv>` | :506-510 | PARTIAL: network none / read-only / tmpfs / uid present; no pids/memory/cap-drop; orphan on outer timeout |
| K3 | `env -i … timeout 120 <argv>` on the host (`--executor host`) | :511-516 | N/A by design (documented), noted L9 |
| K4 | `tarfile.extractall(filter=keep)` | :705-714 | SAFE on ≥3.12; CONFIRMED crash on 3.11.2 (H2) |
| K5 | `shutil.rmtree` / `os.unlink` under run-dir and SCRATCH | :235-247, :1039-1042, :1293-1296 | CONFIRMED via K1 |
| K6 | `subprocess.run([... recall-vs-defects.sh ...])`, `freeze.sh`, `yq` | :452-462, :887-889, :209 | SAFE (argv, no shell) |
| K7 | `shutil.move(staged task → tasks/<id>)`, `write_file` | seed_tasks.py:138-144, :589 | SAFE (safe_path gate) |
| K8 | `patch -s -p1 … -i` in the seeder proof tree | seed_tasks.py:225-230 | SAFE for security; L2 (may prompt) |
| K9 | `bash no-secrets.sh <tdir>` | seed_tasks.py:502-506 | SAFE (fail-closed); L10 (misleading message when missing) |

## Second-order flows

- Agent plants `evil -> <host dir>` in sandbox OR in the rw-mounted grading tree during the hidden run → K1 on the next `fresh_dir(grading)` (`:1053`) or, host mode, on `remove_path(SCRATCH)` in the same process (`:1295`). CONFIRMED.
- Agent adds `conftest.py` / `pytest.ini` at an unprotected path → loaded by `pytest --rootdir /workspace` → hooks rewrite outcomes → `all_pass` true. CONFIRMED (PoC 2/2 passed on two failing hidden tests).
- Dissent envelope `anchor:"path:symbol"` + `anchor_line` → `envelope_texts` emits no `path:line` → `citations()` empty → recall under-counted. CONFIRMED against the live envelope (8 findings, 0 citations).

Deferred: none. Overflow: none.
