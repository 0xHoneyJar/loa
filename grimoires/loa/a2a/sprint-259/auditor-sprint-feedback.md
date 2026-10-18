APPROVED - LET'S FUCKING GO

# Sprint 259 security audit — round 2 (cycle-130 Sprint 2) — APPROVED

**Auditor:** Paranoid Cypherpunk Auditor (Claude Fable 5.1, `global.anthropic.claude-fable-5-1`)
**Date:** 2026-10-15
**Implementation:** `05830914` (audit fix round a259-1 by implementer s2afix on `75d84262`; base `4374c446`); review APPROVED (`engineer-feedback.md`, round 2); round 1 audit kept as `auditor-sprint-feedback-r1.md`
**Dissent:** `adversarial-audit.json` (round 1, two voices, consensus, 0 rejected payloads) — the sprint's three dissent runs are spent (review r1, review r2, audit r1); this round is the auditor's direct verification of the fix against the tree, as in Sprints 257 and 258.
**Suites on `05830914`:** `evals/tests/` 328/328 (6 new cases, each shown failing on `75d84262` through exported copies of the pre-fix grader: `reviewer-afix.md`), image self-check 36/36 PASS under the hardened container flags (`--init --cap-drop ALL --security-opt no-new-privileges --pids-limit 256 --memory 2g --cpus 2`, proven against the real `loa-ablation:258`), `freeze.sh --smoke --check` OK (158 files, `30e1f2ad…`; the frozen suite is unchanged by this round), `validate-suite.sh --smoke` 18 valid, trust-boundary scan clean.

## Round 1 items, verified against the tree

- **HIGH-A1 closed.** `remove_harness` runs at the end of `prepare()` on every grading tree (final, base, implement, fix1): `conftest.py` at any depth, `pytest.ini`, `.pytest.ini`, `pyproject.toml`, `setup.cfg`, `tox.ini`, `setup_suite.bash`, any `*helper*.bash`/`.sh` and any `.bash` under `tests/` or `test/` are removed unless a hidden overlay dest or byte-identical (`filecmp.cmp(shallow=False)` on two regular files) to the fixture's copy at the same path; a symlink at such a path is always removed; the count is `grade.json.harness_files_removed` and the paths go to `grading/<label>.harness-removed.txt` beside the tree. pytest runs with `-o addopts=`. AG-23 shows a root `conftest.py` hookwrapper, a `tests/acceptance/conftest.py` hookwrapper and a `pyproject.toml` `addopts` plugin each removed with the hidden tests red as they should be (1.1.0 graded them 7/7), and a bats `setup_suite.bash` gone while the fixture's helper survives.
- **MEDIUM-A1 closed.** `exec_in_tree` runs `timeout --signal=TERM --kill-after=10 <T>` inside `docker run --rm --init --name ablgrade-<run>-<label>-<pid>-<n> … --pids-limit 256 --memory 2g --cpus 2 --cap-drop ALL --security-opt no-new-privileges`; the client has its own deadline (T + 10 + max(5, min(60, T/2))) after which the process group is SIGKILLed and `docker kill`/`docker rm -f` run by name; stdout is drained in 64 KiB chunks and capped at 4 MiB keeping the head and the tail (`output_truncated` on the result and in every summary). AG-24 and AG-25 cover the argv, the hung client (killed and removed by name within the test's 29 s) and the 10 MiB output. The real-image self-check proves the flags do not break pytest or bats.
- **MEDIUM-A2 closed.** `node_text` reads the grader-owned copy (hidden overlay source or protected fixture file) first and otherwise requires `safe_rel`, `is_within(tree)` and `read_regular` (`O_RDONLY | O_NOFOLLOW | O_NONBLOCK`, `fstat` `S_ISREG`, 1 MiB); `def_line` and the collection-error expansion both go through it. AG-26: `ERROR /dev/zero`, `ERROR ../../etc/passwd::test_x` and a FIFO created in the tree leave the grader alive with ids assigned.
- **MEDIUM-A3 closed.** `copy_tree` and the snapshot tar filter skip regular files above 16 MiB (`oversized_files_skipped`); `churn` lstat-checks and never reads an oversized file; `sandbox_text`/`read_regular` bound every feedback, `review.md` and envelope read at 2 MiB, refuse symlinks and require the path to resolve inside the sandbox; a symlinked feedback file is verdict `none` (gate ran, no readable trailer). AG-27 covers the sparse 20 MiB file and the symlinked readers.
- **LOW-A1 closed.** `host_gate` runs first in `main`: `--executor host` is exit 2 with the risk named unless `LOA_EVAL_ALLOW_HOST_GRADING=1`, and allowed runs print a WARNING and record `executor_mode: host` (AG-28; the bats `setup()` sets the variable).
- **LOW-A2 closed.** `allowed_roots` exempts no path under `~`; `~/`, `$HOME/` and `${HOME}/` words are always outside; `/proc/<pid|self|thread-self>/{environ,cmdline,maps,mem}` and `/var/run` are flagged inside the allowed system roots; a one-component `/x/` word is a regex only after `s`, `y`, `=`, `~` or a single quote, so `cd /root/` is a path. AG-10 and AG-11 gained nine rows (`cat ~/.aws/credentials`, `cat $HOME/.ssh/id_rsa`, `cat /proc/self/environ`, `cd /root/ && cat .ssh/id_rsa`, host `~/.claude/settings.json` …) and keep `sed s/x/y/`, `awk '/LOA-VERDICT/'`, `/proc/cpuinfo` and `/var/log` clean.

## Rejected dissent payloads

None: 0 schema-rejected payloads in `adversarial-audit.json` (`rejected_count: 0`; the listed sidecar `adversarial-rejected-audit.jsonl` is empty).

## Residual observations (not findings)

- Code under test can still monkeypatch pytest at import time from the agent's own package modules, or add `.bats` files under `tests/` that `bats tests` runs; the hidden tests' own outcomes are what the grade reads, and `-o addopts=` plus the harness removal close the configuration vectors. A `-p no:…`-style allowlist of plugins is a Sprint 260 option if the smoke shows abuse (`bd-m0hw7`-class follow-up; none filed, the agents are not adversarial by brief).
- `/home/evaluser/…` stays an allowed absolute root in container mode while `~/` is flagged; the container home holds only the per-run codex copy and the CLI's session store, both the agent's own.
- The implementer's note that the before-proof for `/dev/zero` had to run under `ulimit -v` records how real the 1.1.0 hazard was.
- Accepted risks of round 1 stand (public hidden tests with `WebFetch` → `bd-eriso`; planted-PR ceiling → DEC-0507/0509; the grader on the host by design, now reading only bounded, validated agent bytes).

## Security checklist

Credential handling ✓ · sandbox inputs ✓ · hidden material never materialised ✓ · fairness proofs ✓ · freeze ✓ · grading container isolation and limits ✓ · harness files the agent left never load ✓ · host-side interpretation of agent bytes bounded and symlink-free ✓ · host executor gated ✓ · contamination telemetry without credential exemptions ✓ · supply chain unchanged ✓ · trust boundary ✓.

## Verdict

APPROVED — Sprint 259 is complete; Sprint 260 (the runs) may begin.

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-259","ts":"2026-10-15T07:30:00Z"} -->
