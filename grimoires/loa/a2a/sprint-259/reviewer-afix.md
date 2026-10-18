# Sprint 259 audit fix round 1 (implementer s2afix): grader 1.2.0

Worktree `/home/merlin/Documents/thj/code/loa-wt-s2afix` at `75d84262`. Patch `~/.cache/loa/cycle-130/patches/s2-afix.patch` (+ `.stat`). Files: `evals/harness/ablation-grade.sh`, `evals/tests/ablation-grade.bats`, `evals/tests/fixtures/docker-stub.sh`, `grimoires/loa/evals/ablation-2.0/README.md` (one paragraph). No task file, manifest, `.claude/`, CHANGELOG, ledger or decisions touched.

## What was changed (per finding)

- **HIGH-A1 (harness files).** `is_harness` (ablation-grade.sh:955) and `remove_harness` (:976) run at the end of `prepare()`, so before every `run_suite` on every tree (final, base, implement, fix1). They remove `conftest.py` at any depth, `pytest.ini`, `.pytest.ini`, `pyproject.toml`, `setup.cfg`, `tox.ini`, `setup_suite.bash`, any `*helper*.bash`/`*helper*.sh`, and any `.bash` under a `tests/` or `test/` directory. A file survives when it is a hidden-overlay dest (or under a directory overlay) or when `same_as_fixture` holds: lstat regular on both sides and `filecmp.cmp(shallow=False)`. A symlink is always removed. The count goes to `grade.json.harness_files_removed` (summed over all trees). The paths go to `grading/<label>.harness-removed.txt`. pytest gets `-o addopts=` (:653).
- **MEDIUM-A1 (container).** `exec_in_tree` (:706) runs `docker run --rm --init --name ablgrade-<run>-<label>-<pid>-<n> … --pids-limit 256 --memory 2g --cpus 2 --cap-drop ALL --security-opt no-new-privileges … <image> timeout --signal=TERM --kill-after=10 <T> <cmd>`. `container_name` is at :667. Host mode uses the same timeout prefix. Popen runs in a new session. The client deadline is T + 10 + `OUTER_GRACE_S` (60 at T=120, minimum 5). When the deadline passes, or the grader fails mid-run, the process group is SIGKILLed and `docker_cleanup` (:697) runs `docker kill <name>` then `docker rm -f <name>`. `drain` (:674) reads stdout in 64 KiB chunks and keeps the first and the last 2 MiB. `output_truncated` is set on the result, `hidden_tests` and `regressions.base/final`. `LOA_EVAL_GRADE_TIMEOUT_S` (1–9999) overrides T (:242). rc 124, or rc 137 after T, counts as `timed_out`.
- **MEDIUM-A2 (node paths).** `node_text` (:770) reads the grader-owned copy first. `GRADER_SOURCES` maps overlay dests to their hidden sources and protected paths to their fixture files. For any other path it requires `safe_rel` and `is_within(tree)`, then `read_regular` (:343): `O_RDONLY|O_NOFOLLOW|O_NONBLOCK`, fstat `S_ISREG`, at most 1 MiB. Anything else gets def line `10**9` and no collection-error expansion. `def_line` and the expansion loop both use it.
- **MEDIUM-A3 (sizes, symlinks).** `copy_tree` skips regular files above 16 MiB by lstat size (:450). Snapshot tar members above 16 MiB are skipped too (:1039). Both count in `oversized_files_skipped`. `churn` (:1057) lstats each file: a file above the cap on either side counts once as changed and is not read. Non-regular files read as empty. `sandbox_text` (:1114) reads at most 2 MiB through `read_regular` with `root=sandbox/`. `gate_verdict` (:1120), `review_md_verdict` and `combined_findings` use it. `envelope_texts` reads at most 2 MiB and refuses symlinks.
- **LOW-A1 (host gate).** `host_gate` (:1635), called first in `main`, refuses `--executor host` with exit 2 unless `LOA_EVAL_ALLOW_HOST_GRADING=1`. The message names the risk. When allowed it prints a WARNING, and `executor_mode: host` stays. The header documents both environment variables.
- **LOW-A2 (contamination).** `allowed_roots` (:1319) no longer exempts `~/.aws`, `~/.codex`, `~/.claude.json` or `~/.claude`. `HOME_WORD` (:1309) and `outside` (:1327) treat `~/`, `$HOME/` and `${HOME}/` as always outside, in Bash words and in path fields. `SENSITIVE` (:1312) flags `/proc/<digits|self|thread-self>/{environ,cmdline,maps,mem}` and `/var/run`. A one-component `/x/` word is skipped only after `s`, `y`, `=`, `~` or `'` (:1359).
- **Version.** `GRADER_VERSION = "1.2.0"` (:239). The header carries a 1.2.0 paragraph, the new fields in the grade.json schema, the new docker argv and the new reading rules.
- **docker-stub.sh.** It now accepts `--init`, `--cap-drop` and `--security-opt`, and logs `rm` to `rm.log` (`kill` already went to `kill.log`). `DOCKER_STUB_HANG=1` drops a leading `timeout [opts] T` from the command.
- **README.** The grading paragraph now says that harness files are removed, that pytest runs with `-o addopts=`, that the container has a deadline and limits, that files above 16 MiB are not copied, and that host mode is opt-in.

## Tests added or changed (evals/tests/ablation-grade.bats)

Every new or extended case was run against the untouched 75d84262 grader, in an exported copy with the new bats file and stub. All of them fail there (10/10 not ok). A probe file printed each sub-case's 1.1.0 value:

| Case | 1.1.0 (before) | 1.2.0 (after) |
|---|---|---|
| AG-23 root conftest hookwrapper | hidden 7/7 | 5/7, removed 2 (final + implement), review accuracy false |
| AG-23 tests/acceptance/conftest.py | 7/7 | 5/7 |
| AG-23 tests/pyproject.toml `-p no:terminal` | 0/5 parse_error true | 5/7 parse_error false |
| AG-23 bats setup_suite.bash writes the fix | 3/3 | 2/3 (t1); helpers.bash and corpus-helper.bash survive |
| AG-24 argv flags, name, 124 timeout; hung client then kill and rm -f by name | no flags, no name, no output_truncated | pass (hung case finishes under 29 s) |
| AG-25 10 MiB output | no output_truncated field | 1/1, truncated true, row writes |
| AG-26 ERROR /dev/zero, ../../etc/passwd, FIFO | FIFO-only probe: timeout 124; /dev/zero: unbounded read (run under ulimit -v) | exit 0, 1/4 t1,t2,t3; grader-owned order 1/2 t2 |
| AG-27 20 MiB sparse file; symlinked feedback / review.md / parent | oversized null; review APPROVED read through the link | skipped 1; review none; review.md no verdict; audit none |
| AG-28 host without opt-in | exit 0 | exit 2 with the risk message; allowed: WARNING, host |
| AG-10 nine new rows (`~/`, `$HOME/`, `${HOME}/`, /proc/self/environ, /proc/1/cmdline, /proc/self/maps, /var/run, `cd /root/`, Read `~/…`) | each null | each outside_path |
| AG-11 host `~/.claude/settings.json`, `~/.aws`, `~/.codex/`, `$HOME/.claude.json` | null (exempt) | outside_path; `sed s/x/y/`, `sed -i 's/a/b/'`, /proc/cpuinfo, /var/log stay clean |

Also updated: AG-1 pins the new docker argv, and AG-7 the new timeout prefix. `setup()` exports `LOA_EVAL_ALLOW_HOST_GRADING=1`.

## Counts and checks

| Check | Before (75d84262) | After |
|---|---|---|
| `bats evals/tests/` | 322/322 | 328/328 (ablation-grade.bats rerun twice after the last edit: 28/28) |
| `bats evals/tests/ablation-grade.bats` | 22/22 | 28/28 |
| self-check, 16 frozen tasks, docker stub with host pytest, frozen (no --allow-unfrozen) | n/a | 36/36 PASS |
| `validate-suite.sh --smoke` | 18 valid | 18 valid |
| `freeze.sh --smoke --check` | OK, 158 files, 30e1f2ad… | same |
| eval.yml trust-boundary scan (graders/ + harness/) | 0 | 0 |

## DECISION bullets

- DECISION: the removed-path list is written to `grading/<label>.harness-removed.txt`, beside the tree and not inside it. The brief says both "`grading/<label>/.harness-removed.txt`" and "next to the tree". A file inside the tree would sit in the mount the code under test can rewrite.
- DECISION: `harness_files_removed` sums every tree graded (final, implement, fix1, base). Base is always 0 because it is a fixture copy.
- DECISION: hidden-overlay dests, and every path under a directory-overlay dest, are exempt from the harness removal. They are grader-owned and were just written by `prepare()`. No frozen task overlays a directory today.
- DECISION: harness names match at any depth, including ini files, because pytest takes the ini file nearest the test arguments. AG-23 shows `tests/pyproject.toml` overriding the protected root `pytest.ini`.
- DECISION: container names carry a per-grade sequence number (`ablgrade-<run>-<label>-<pid>-<n>`), so the regression and hidden runs on one tree never reuse a name while `--rm` removal is still pending.
- DECISION: the client deadline is T + 10 + max(5, min(60, T/2)): 190 s at T=120, as before plus the kill-after. A client-deadline kill reports rc 124 and `timed_out: true`. rc 137 counts as timed out only when T has elapsed, so an OOM kill below the deadline is not a timeout.
- DECISION: the 4 MiB output cap keeps the first and the last 2 MiB with a `[output truncated]` marker. The pytest summary and the `-rA` outcome lines come last, so a cut keeps the parse.
- DECISION: a symlinked or non-regular feedback file, or one behind a symlinked parent, gives verdict `"none"`: the gate ran and left no readable trailer, so per-gate accuracy is false. A symlinked `review.md` gives no verdict (null) and no citations. Readers take the first 2 MiB.
- DECISION: the 16 MiB cap also applies to snapshot tar members. An oversized file absent from the final tree is not counted as churn; `oversized_files_skipped` records it.
- DECISION: a one-component `/x/` word is also skipped after a single quote, beside the brief's `s`, `y`, `=`, `~`. Without it, `awk '/LOA-VERDICT/ {print}'`, an existing clean case in AG-11 and a common agent command, would be flagged. The accepted gap is `cd '/root/'` (quoted, trailing slash), which stays unflagged.
- DECISION: `~/`, `$HOME/` and `${HOME}/` are outside in container mode too, although `/home/evaluser` (the container home) stays an allowed absolute root. The brief says they are always outside. The asymmetry is listed for the lead below.
- DECISION: the host gate runs before anything else, for self-check and review-catch too, so host mode is never silently used.

## Could not do / limitations

- No docker: the image self-check must be rerun by the lead. The stub run of all 16 tasks (36/36) is host pytest 9.0.2 on Python 3.13, not the image.
- The before proof for `/dev/zero` ran under `ulimit -v 6000000`, because the 1.1.0 grader reads it without bound.
- The hung-container proof uses the stub's `DOCKER_STUB_HANG`. Against real docker, `docker kill` and `rm -f` by name are the same calls but are untested here.
- Not closed, and outside this finding set: code under test can still monkeypatch pytest at import time from the agent's own package modules, or install extra `.bats` files under `tests/` that `bats tests` runs. Absolute `/home/evaluser/...` stays allowed in container mode.

## Handoff notes for the lead

- Rerun the image self-check (`--self-check base|reference[|noisy]` × 16 inside `loa-ablation:258`). The new docker flags (`--init`, limits, `--cap-drop ALL`, `no-new-privileges`) are the part the stub cannot prove. `--cap-drop ALL` with `--user <uid>:<gid>` should be harmless for pytest and bats.
- `grader_version` is 1.2.0. Grades from 1.1.0 differ only where a harness file was removed, a file was skipped, or a symlinked reader file existed. The new fields are additive. `ablation-row.sh` writes rows unchanged (AG-25, AG-18, AG-20).
- The README paragraph is outside MANIFEST.sha256, so the freeze is unchanged.
