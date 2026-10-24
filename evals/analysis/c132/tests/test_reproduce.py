"""evals/analysis/c132/reproduce.sh: the worktree attestation and the live-sample gate (cycle-133 sdd.md C-7, § 5.4;
beads bd-jat0z, bd-161zz; Sprint 271 audit DO-001, SEC-001).

Each case copies the real reproduce.sh into a throwaway git repository (its own user.name/email) shaped like the
record: the pipeline paths, the suite root, the registration, the lite INDEX.json, rows.jsonl, plus the real
evals/analysis/c132/common.py (the live table's validity filter). The engine (record_lite.py), the runner
(run-ablation.sh) and docker are stubs: no container, no model call, no network."""
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import unittest

import _path

SCRIPT = os.path.join(_path.ANALYSIS_DIR, "c132", "reproduce.sh")
COMMON = os.path.join(_path.ANALYSIS_DIR, "c132", "common.py")
SUITE = "grimoires/loa/evals/ablation-2.0-c132"
IMG = "sha256:" + "4e" * 32

ENGINE = r'''import os, sys
a = sys.argv[1:]
rep = a[a.index("--report") + 1]
os.makedirs(os.path.dirname(rep) or ".", exist_ok=True)
with open(rep, "w") as f:
    f.write("# stub engine report\n")
with open(os.environ["STUB_LOG"], "a") as f:
    f.write("engine %s\n" % " ".join(a))
sys.exit(int(os.environ.get("STUB_ENGINE_RC", "0")))
'''
RUNNER = r'''#!/usr/bin/env bash
set -euo pipefail
printf 'runner' >> "$STUB_LOG"; for x in "$@"; do printf ' [%s]' "$x" >> "$STUB_LOG"; done; echo >> "$STUB_LOG"
res=""; while (( $# )); do [[ "$1" == --results-root ]] && res="$2"; shift; done
mkdir -p "$res"; printf '%s' "${STUB_LIVE:-}" > "$res/runs.jsonl"
exit "${STUB_RUNNER_RC:-0}"
'''
DOCKER = '#!/usr/bin/env bash\n[ "$1 $2" = "image inspect" ] || exit 1\necho "${STUB_IMG:-missing}"\n'


def _w(p, text, mode=None):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8") as f:
        f.write(text)
    if mode:
        os.chmod(p, mode)


def _row(arm, trial, v, **kw):
    r = {"batch": "c132-g3-a1", "arm": arm, "task_id": "review-r24", "trial": trial, "status": "completed",
         "contaminated": None, "oracle_exposed_defects": [], "defects_seeded": 9, "defects_missed_pm3": [],
         "defect_catch_rate_pm3": v, "phases": [{"refusal_fallbacks": []}], "run_id": "rec-%s-%d" % (arm, trial)}
    if arm.endswith("_matched"):
        r.update(bare_sessions=11, sessions_valid=11)
    r.update(kw)
    return r


@unittest.skipUnless(shutil.which("git") and shutil.which("jq") and shutil.which("bash"), "needs git, jq, bash")
class ReproduceTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="c132-repro-")
        self.repo = os.path.join(self.tmp, "repo")
        self.bin = os.path.join(self.tmp, "bin")
        self.log = os.path.join(self.tmp, "stub.log")
        r = self.repo
        _w(os.path.join(r, "evals/analysis/c132/reproduce.sh"), open(SCRIPT).read(), 0o755)
        _w(os.path.join(r, "evals/analysis/c132/record_lite.py"), ENGINE)
        _w(os.path.join(r, "evals/analysis/c132/__init__.py"), "")
        _w(os.path.join(r, "evals/analysis/c132/common.py"), open(COMMON).read())
        _w(os.path.join(r, "evals/harness/run-ablation.sh"), RUNNER, 0o755)
        _w(os.path.join(r, "evals/harness/judge-sample.sh"), "# analysis-side tool\n")
        _w(os.path.join(r, "evals/suites/ablation-2.0.yaml"), "suite: 1\n")
        _w(os.path.join(r, "evals/fixtures/review-prs/pr-24/PR.md"), "# PR\n")
        _w(os.path.join(r, SUITE, "tasks/review-r24/task.yaml"), "id: review-r24\n")
        _w(os.path.join(r, SUITE, "MANIFEST.sha256"), "x\n")
        self.reg = os.path.join(r, SUITE, "REGISTRATION-15.json")
        _w(self.reg, json.dumps({"image_digest": IMG, "pin": "p"}, sort_keys=True))
        _w(os.path.join(r, "evals/results/ablation-2.0/c132-lite/INDEX.json"), "{}\n")
        rows = [_row("a1_full", 1, 0.6667), _row("a1_full", 2, 0.7778),
                _row("a1_full", 3, 0.0, status="contaminated"),          # invalid: never widens the range
                _row("a0_bare_matched", 1, 0.5556), _row("a0_bare_matched", 2, 0.6667),
                _row("a1_review_only", 1, 0.4444), _row("a1_review_only", 2, 0.5556)]
        _w(os.path.join(r, "grimoires/loa/reports/review-catch-c132/rows.jsonl"),
           "".join(json.dumps(x, sort_keys=True) + "\n" for x in rows))
        _w(os.path.join(self.bin, "docker"), DOCKER, 0o755)
        self.git("init", "-q")
        self.git("config", "user.name", "t")
        self.git("config", "user.email", "t@example.invalid")
        self.git("add", "-A")
        self.git("commit", "-q", "-m", "pin")
        self.pin = self.git("rev-parse", "HEAD").strip()
        self.scratch = os.path.join(self.tmp, "scratch")
        self.report = os.path.join(self.tmp, "report.md")

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def git(self, *a):
        return subprocess.run(["git", "-C", self.repo] + list(a), check=True, capture_output=True, text=True).stdout

    def run_repro(self, *extra, engine_rc=0, runner_rc=0, img=IMG, live=None, cwd=None):
        env = dict(os.environ, PATH=self.bin + os.pathsep + os.environ["PATH"], STUB_LOG=self.log,
                   STUB_ENGINE_RC=str(engine_rc), STUB_RUNNER_RC=str(runner_rc), STUB_IMG=img,
                   STUB_LIVE="".join(json.dumps(x, sort_keys=True) + "\n" for x in (live or [])))
        env.pop("REPRO_SCRATCH", None)
        argv = ["bash", os.path.join(self.repo, "evals/analysis/c132/reproduce.sh"), "--pin", self.pin,
                "--analysis-pin", self.pin, "--scratch", self.scratch, "--report", self.report] + list(extra)
        return subprocess.run(argv, capture_output=True, text=True, env=env, cwd=cwd or self.tmp)

    def env_json(self):
        with open(os.path.join(self.scratch, "environment.json")) as f:
            return json.load(f)

    def stub_log(self):
        return open(self.log).read() if os.path.exists(self.log) else ""

    # ---------------------------------------------------------------- the attestation (bd-jat0z)
    def test_clean_worktree_at_the_pin_passes_and_is_attested(self):
        p = self.run_repro()
        self.assertEqual(p.returncode, 0, p.stderr)
        e = self.env_json()
        self.assertIs(e["pinned_trees_identical_to_worktree"], True)
        self.assertIs(e["pipeline_tree_identical_to_pin"], True)
        self.assertIs(e["analysis_tree_identical_to_pin"], True)
        self.assertIs(e["worktree_clean"], True)
        self.assertEqual(e["env_check"], "passed")
        self.assertTrue(self.pin.startswith(e["git_describe"]), e["git_describe"])   # --always: the abbreviated sha, no -dirty
        self.assertNotIn("pin_tree_identical_to_head", e)

    def test_an_uncommitted_edit_to_a_pipeline_file_is_refused_before_any_write(self):
        with open(os.path.join(self.repo, "evals/suites/ablation-2.0.yaml"), "a") as f:
            f.write("edited: 1\n")
        p = self.run_repro()
        self.assertEqual(p.returncode, 2, p.stdout + p.stderr)
        self.assertIn("worktree", p.stderr)
        self.assertFalse(os.path.exists(self.scratch), "exit 2 is a refusal before any write")
        self.assertNotIn("engine", self.stub_log())

    def test_an_uncommitted_edit_to_the_analysis_tree_is_refused(self):
        with open(os.path.join(self.repo, "evals/analysis/c132/common.py"), "a") as f:
            f.write("# edited\n")
        self.assertEqual(self.run_repro().returncode, 2)

    def test_an_untracked_file_under_a_compared_path_is_refused(self):
        _w(os.path.join(self.repo, "evals/harness/new-tool.sh"), "echo hi\n")
        p = self.run_repro()
        self.assertEqual(p.returncode, 2)
        self.assertIn("not clean", p.stderr)

    def test_bytecode_caches_do_not_dirty_the_worktree(self):
        _w(os.path.join(self.repo, "evals/analysis/c132/__pycache__/common.cpython-313.pyc"), "x")
        _w(os.path.join(self.repo, "evals/analysis/c132/tests/.pytest_cache/v"), "x")
        self.assertEqual(self.run_repro().returncode, 0)

    def test_a_committed_pipeline_change_after_the_pin_is_refused(self):
        with open(os.path.join(self.repo, "evals/fixtures/review-prs/pr-24/PR.md"), "a") as f:
            f.write("more\n")
        self.git("commit", "-qam", "drift")
        p = self.run_repro()
        self.assertEqual(p.returncode, 2)
        self.assertIn("pipeline tree differs", p.stderr)

    def test_a_committed_analysis_change_is_refused_against_the_analysis_pin(self):
        with open(os.path.join(self.repo, "evals/harness/judge-sample.sh"), "a") as f:
            f.write("# analysis-side tool changed\n")
        self.git("commit", "-qam", "analysis drift")
        p = self.run_repro()
        self.assertEqual(p.returncode, 2)
        self.assertIn("analysis tree differs", p.stderr)

    def test_no_env_check_records_the_mismatch_and_never_asserts_a_match(self):
        with open(os.path.join(self.repo, "evals/suites/ablation-2.0.yaml"), "a") as f:
            f.write("edited: 1\n")
        p = self.run_repro("--no-env-check", img="sha256:other")
        self.assertEqual(p.returncode, 0, p.stderr)
        e = self.env_json()
        self.assertEqual(e["env_check"], "skipped")
        for k in ("pinned_trees_identical_to_worktree", "worktree_clean", "image_matches", "environment_matches"):
            self.assertIs(e[k], False, k)
        self.assertTrue(e["git_describe"].endswith("-dirty"), e["git_describe"])

    def test_usage_is_exit_2(self):
        self.assertEqual(self.run_repro("--bogus").returncode, 2)
        self.assertEqual(self.run_repro("--pin", "not-a-sha").returncode, 2)

    def test_runs_from_any_cwd(self):
        self.assertEqual(self.run_repro(cwd="/").returncode, 0)

    # ---------------------------------------------------------------- the exit table and the live gate (bd-161zz)
    def test_an_engine_difference_is_exit_1(self):
        self.assertEqual(self.run_repro(engine_rc=1).returncode, 1)

    def test_an_engine_failure_refuses_the_live_sample_exit_3(self):
        p = self.run_repro("--live-sample", engine_rc=1)
        self.assertEqual(p.returncode, 3, p.stdout + p.stderr)
        self.assertNotIn("runner", self.stub_log(), "the paid sample never starts after an engine failure")
        text = open(self.report).read()
        self.assertIn("not run", text)
        self.assertIn("engine exit 1", text)

    def test_an_environment_mismatch_refuses_the_live_sample_exit_3(self):
        p = self.run_repro("--live-sample", "--no-env-check", img="sha256:other")
        self.assertEqual(p.returncode, 3)
        self.assertNotIn("runner", self.stub_log())
        self.assertIn("image_matches false", open(self.report).read())

    def test_a_runner_failure_is_exit_3(self):
        self.assertEqual(self.run_repro("--live-sample", runner_rc=1).returncode, 3)

    def live_rows(self, full=0.7, bare=0.6, ro=0.5):
        return [dict(_row(a, 1, v), batch="c132-repro-live") for a, v in
                (("a1_full", full), ("a0_bare_matched", bare), ("a1_review_only", ro))]

    def test_live_sample_uses_the_registration_hash_valid_rows_and_marks_the_environment(self):
        p = self.run_repro("--live-sample", live=self.live_rows())
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        log = self.stub_log()
        want = hashlib.sha256(open(self.reg, "rb").read()).hexdigest()
        self.assertIn("sha256 %s" % want, log)
        self.assertNotIn("REGISTRATION-16", log)
        self.assertIn("[--source-commit] [%s]" % self.pin, log)
        text = open(self.report).read()
        self.assertIn("| a1_full | 0.6667, 0.7778 | [0.6667, 0.7778] | 0.7000 | completed | yes |", text)
        self.assertIn("1 invalid recorded row(s) left out of the range", text)
        self.assertIn("environment: env_check passed; image_matches true; pinned_trees_identical_to_worktree true", text)

    def test_a_live_grade_outside_the_range_is_named_not_a_failure(self):
        p = self.run_repro("--live-sample", live=self.live_rows(full=0.99))
        self.assertEqual(p.returncode, 0)
        self.assertIn("| a1_full | 0.6667, 0.7778 | [0.6667, 0.7778] | 0.9900 | completed | NO |", open(self.report).read())

    def test_a_missing_live_row_is_exit_3(self):
        p = self.run_repro("--live-sample", live=self.live_rows()[:2])
        self.assertEqual(p.returncode, 3)
        self.assertIn("| a1_review_only |", open(self.report).read())


if __name__ == "__main__":
    unittest.main()
