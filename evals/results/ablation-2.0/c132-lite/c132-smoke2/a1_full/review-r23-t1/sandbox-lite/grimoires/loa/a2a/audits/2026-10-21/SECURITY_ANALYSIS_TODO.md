# Security analysis working file — sprint-1 audit (PR: sprint-259 grader, seeders, freeze, bd-8o5rx) — 2026-10-21

Trust levels: SANDBOX = agent-controlled (untrusted); RUN = harness-written (semi-trusted); SUITE = task author, frozen (trusted when MANIFEST.sha256 checks); OPERATOR = argv/env.

| # | Source / Sink | file:line | Trust | Status | Note |
|---|---------------|-----------|-------|--------|------|
| S1 | sandbox/ tree copied into grading/final | ablation-grade.sh:1076 (copy_tree 271-297) | SANDBOX | SAFE | lstat; symlinks re-created, FIFOs/devices skipped; no error handling on unreadable file (MED, DISS-C-006) |
| S2 | sandbox feedback files → gate_verdict/review_md_verdict | ablation-grade.sh:1055-1063, 764-790 | SANDBOX | SAFE | regex/json parse only |
| S3 | sandbox review.md + a2a feedback → citations() | ablation-grade.sh:871-889 | SANDBOX | SAFE | regex only; anchor_line never read from envelopes (HIGH, functional) |
| S4 | pytest/TAP stdout → parse_pytest/parse_tap | ablation-grade.sh:546-621 | SANDBOX (test code prints) | CONFIRMED | stdout trusted for PASSED lines + summary; agent-authored conftest/plugins run in-process (HIGH) |
| S5 | pytest node ids → def_line/coll_err open() | ablation-grade.sh:533-543, 574-581 | SANDBOX | SAFE | read-only, inside tree join, no content leaves |
| S6 | transcripts/events-*.jsonl → contamination() | ablation-grade.sh:1010-1035 | RUN | SAFE | json parse; `hidden` substring FP class (MED) |
| S7 | snapshots/*.bundle → git bundle unbundle / git archive → tarfile | ablation-grade.sh:682-715 | RUN | PARTIAL | safe_rel + data_filter; API needs py>=3.11.4/3.12, crash otherwise (HIGH availability) |
| S8 | task.yaml via yq | ablation-grade.sh:212-219, 319-419 | SUITE | SAFE | safe_rel on every path; fixture must be inside task dir |
| S9 | review_catch.manifest / fixture paths | ablation-grade.sh:407-413, 434-440 | SUITE | PARTIAL | absolute paths accepted (os.path.join) — escapes suite root; task author controlled (LOW) |
| S10 | hidden/manifest.json → put_file | ablation-grade.sh:346-359, 673-674 | SUITE | SAFE | safe_rel on src and dest; ensure_parent de-symlinks parents |
| S11 | docker run argv | ablation-grade.sh:506-508 | OPERATOR+RUN | SAFE | argv list; --network none --read-only; ':'/',' in run_dir rejected (1050) |
| S12 | host executor env -i | ablation-grade.sh:511-515 | OPERATOR | SAFE | by design (DEC-0491 container default) |
| S13 | recall-vs-defects.sh subprocess | ablation-grade.sh:920-922 | SUITE | SAFE | argv; env inherits os.environ |
| S14 | timeout without -k | ablation-grade.sh:508, 514 | SANDBOX | CONFIRMED | SIGTERM only (LOW) |
| K1 | seed: --repo / history paths → write_file | seed_tasks.py:57-60, 138-144 | OPERATOR repo | SAFE | safe_path; symlink blobs refused (152) |
| K2 | seed: git env | seed_tasks.py:51-54 | OPERATOR | SAFE | argv; GIT_CONFIG_NOSYSTEM; --no-ext-diff on diffs |
| K3 | seed: apply_patch git-apply fallback | seed_tasks.py:225-230 | OPERATOR | CONFIRMED | silent no-op in work tree subdir (HIGH, reproduced) |
| K4 | seed: run_tests host execution of history code | seed_tasks.py:201-222 | OPERATOR repo | SAFE | documented design; env -i |
| K5 | seed: counts() last-line parse | seed_tasks.py:191-198 | — | CONFIRMED | 0/0 on trailing stderr (MED) |
| K6 | seed: grader_protected = existing infra only | seed_tasks.py:158-177, 384, 457; validate-suite.sh:280 | — | CONFIRMED | feeds S4 (HIGH) |
| K7 | seed: task_yaml string assembly | seed_tasks.py:269-290 | history subject | SAFE | json.dumps quoting; sanitise() strips paths/test names |
| K8 | seed: no-secrets scan | seed_tasks.py:502-506 | — | SAFE | bash argv |
| C1 | corpus: generated_path order vs head-missing | seed-corpus-from-record.sh:232-236 | fixture | CONFIRMED | LOW |
| T1 | tests: operator-specific BATS_BIN, /usr/bin/python3 | ablation-grade.bats:16, 46, 48 | — | CONFIRMED | HIGH (CI unverifiable) / LOW |
| T2 | docker-stub DOCKER_STUB_PATH | docker-stub.sh:76-79 | test fixture | SAFE | test-only |
| M1 | manifests pr-14/pr-15 + SHA256SUMS | fixtures | — | SAFE | sha256 verified byte-for-byte; defects arrays identical; removed rows all generated paths |

Deferred: none. Scope limits: smoke suite, freeze.sh, recall-vs-defects.sh, no-secrets.sh, pipeline-run.sh are outside the PR slice and were not re-read.
