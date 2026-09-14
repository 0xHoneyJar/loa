"""Execute the workflow gates with local process/API fixtures."""

import fnmatch
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[2]
HEAD = "a" * 40
OPERATOR = "deep-name"


def workflow(name):
    return yaml.load(
        (ROOT / ".github/workflows" / name).read_text(),
        Loader=yaml.BaseLoader,
    )


def run_step(document, job, name):
    return next(
        step["run"] for step in document["jobs"][job]["steps"]
        if step.get("name") == name
    )


def render(script, values):
    return re.sub(
        r"\$\{\{\s*(.*?)\s*\}\}",
        lambda match: values[match[1]],
        script,
    )


class EvalGateTests(unittest.TestCase):
    def gate(self, framework, regression):
        document = workflow("eval.yml")
        job = next(iter(document["jobs"]))
        script = render(run_step(document, job, "Check for regressions"), {
            "steps.framework.outputs.exit_code": framework,
            "steps.regression.outputs.exit_code": regression,
        })
        return subprocess.run(
            ["bash", "--noprofile", "--norc", "-e", "-o", "pipefail", "-c", script],
            env=dict(os.environ, FRAMEWORK_EXIT=framework, REGRESSION_EXIT=regression),
            capture_output=True, text=True, check=False,
        )

    def test_success_requires_both_suites_to_pass(self):
        result = self.gate("0", "0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("All eval suites passed", result.stdout)

    def test_documented_infrastructure_outcome_is_explicitly_advisory(self):
        for pair in (("2", "0"), ("0", "2"), ("2", "2")):
            with self.subTest(pair=pair):
                result = self.gate(*pair)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("::warning::", result.stdout)
                self.assertNotIn("All eval suites passed", result.stdout)

    def test_regressions_fail(self):
        for pair in (("1", "0"), ("0", "1"), ("1", "2"), ("2", "1")):
            with self.subTest(pair=pair):
                self.assertNotEqual(self.gate(*pair).returncode, 0)

    def test_missing_and_unexpected_outcomes_fail(self):
        for bad in ("", "126", "127", "137", "garbage", "-1", "00", "256"):
            for pair in ((bad, "0"), ("0", bad), (bad, "2"), ("2", bad)):
                with self.subTest(pair=pair):
                    result = self.gate(*pair)
                    self.assertNotEqual(result.returncode, 0, result.stdout)
                    self.assertNotIn("All eval suites passed", result.stdout)


def review(state, number=1, *, head=HEAD, login=OPERATOR):
    return {
        "id": number,
        "user": {"login": login},
        "state": state,
        "commit_id": head,
        "submitted_at": f"2026-09-14T12:{number:02d}:00Z",
    }


class OperatorReviewTests(unittest.TestCase):
    def gate(self, reviews, *, author="contributor", protected=True,
             files=..., changed_files=1):
        document = workflow("cycle-108-schema-guard.yml")
        script = render(
            run_step(document, "reviewer-check", "Verify designated operator is an approver"),
            {
                "github.event.pull_request.number": "7",
                "github.repository": "fixture/repo",
                "github.event.pull_request.user.login": author,
            },
        )
        with tempfile.TemporaryDirectory(prefix="loa-ci-review-") as directory:
            root = Path(directory)
            fixture = {
                "pr": {
                    "head": {"sha": HEAD}, "user": {"login": author},
                    "changed_files": changed_files,
                },
                "files": [{
                    "filename": ".claude/skills/reviewing-code/SKILL.md"
                    if protected else "README.md",
                    "status": "modified",
                }] if files is ... else files,
                "reviews": reviews,
            }
            (root / "fixture.json").write_text(json.dumps(fixture))
            gh = root / "gh"
            gh.write_text("""#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
fixture = json.loads(Path(os.environ["GH_FIXTURE"]).read_text())
args = sys.argv[1:]
if args[:2] == ["pr", "view"]:
    print(json.dumps(sorted({
        row["user"]["login"] for row in fixture["reviews"]
        if row["state"] == "APPROVED"
    })))
elif args[0] == "api":
    endpoint = next(arg for arg in args[1:] if "repos/" in arg)
    if endpoint.endswith("/reviews"):
        # Exercise the real CLI's concatenated paginated response shape.
        for row in fixture["reviews"]:
            print(json.dumps([row]))
        if not fixture["reviews"]:
            print("[]")
    elif endpoint.endswith("/files"):
        files = fixture["files"]
        if isinstance(files, list) and files:
            for offset in range(0, len(files), 30):
                print(json.dumps(files[offset:offset + 30]))
        else:
            print(json.dumps(files))
    else:
        print(json.dumps(fixture["pr"]))
else:
    raise SystemExit("unexpected gh invocation")
""")
            gh.chmod(0o700)
            return subprocess.run(
                ["bash", "--noprofile", "--norc", "-e", "-o", "pipefail", "-c", script],
                cwd=root,
                env=dict(
                    os.environ, PATH=f"{root}:{os.environ['PATH']}",
                    GH_FIXTURE=str(root / "fixture.json"), GH_REPO="fixture/repo",
                    PR_NUMBER="7", OPERATOR_LOGIN=OPERATOR,
                ),
                capture_output=True, text=True, check=False,
            )

    def test_current_head_approval_passes(self):
        self.assertEqual(self.gate([review("APPROVED")]).returncode, 0)

    def test_missing_approval_fails(self):
        self.assertNotEqual(self.gate([]).returncode, 0)

    def test_stale_head_approval_fails(self):
        self.assertNotEqual(self.gate([review("APPROVED", head="b" * 40)]).returncode, 0)

    def test_later_changes_requested_supersedes_approval(self):
        self.assertNotEqual(self.gate([
            review("APPROVED"), review("CHANGES_REQUESTED", 2),
        ]).returncode, 0)

    def test_dismissed_approval_fails(self):
        self.assertNotEqual(self.gate([review("DISMISSED")]).returncode, 0)

    def test_comment_does_not_dismiss_approval(self):
        result = self.gate([review("APPROVED"), review("COMMENTED", 2)])
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_exact_operator_identity_is_required(self):
        self.assertNotEqual(
            self.gate([review("APPROVED", login="other-deep-name")]).returncode, 0,
        )

    def test_existing_operator_author_policy_is_preserved(self):
        self.assertEqual(self.gate([], author=OPERATOR).returncode, 0)

    def test_unprotected_review_event_does_not_require_operator(self):
        self.assertEqual(self.gate([], protected=False).returncode, 0)

    def test_rename_from_protected_path_requires_current_approval(self):
        files = [{
            "filename": "docs/reviewing-code.md", "status": "renamed",
            "previous_filename": ".claude/skills/reviewing-code/SKILL.md",
        }]
        self.assertNotEqual(self.gate([], files=files).returncode, 0)
        self.assertEqual(
            self.gate([review("APPROVED")], files=files).returncode, 0,
        )

    def test_complete_paginated_files_include_later_protected_paths(self):
        files = [
            {"filename": f"docs/{index}.md", "status": "modified"}
            for index in range(35)
        ]
        self.assertEqual(
            self.gate([], files=files, changed_files=35).returncode, 0,
        )
        files[-1]["filename"] = ".claude/skills/reviewing-code/SKILL.md"
        self.assertNotEqual(
            self.gate([], files=files, changed_files=35).returncode, 0,
        )

    def test_truncated_file_list_never_reports_unprotected(self):
        files = [
            {"filename": f"docs/{index}.md", "status": "modified"}
            for index in range(3000)
        ]
        result = self.gate([], files=files, changed_files=3001)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("No cycle-108 protected surfaces changed", result.stdout)

    def test_invalid_file_arrays_fail_before_the_unprotected_exit(self):
        for files in (
            None, {}, [None], [{}], [{"filename": ""}],
            [{"filename": 7}], [{"filename": "README.md\n"}],
            [{"filename": "README.md", "previous_filename": None}],
            [{"filename": "README.md", "previous_filename": 7}],
            [{"filename": "README.md", "previous_filename": ""}],
            [{"filename": "README.md", "status": "renamed"}],
        ):
            with self.subTest(files=files):
                result = self.gate([], files=files)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("No cycle-108 protected surfaces changed", result.stdout)

    def test_count_mismatch_or_duplicate_files_fail(self):
        for files, count in (
            ([], 1),
            ([{"filename": "README.md"}], 0),
            ([{"filename": "README.md"}, {"filename": "README.md"}], 2),
        ):
            with self.subTest(files=files, count=count):
                self.assertNotEqual(
                    self.gate([], files=files, changed_files=count).returncode, 0,
                )

    def test_changed_file_count_must_be_a_nonnegative_integer(self):
        for count in (None, "1", -1, 1.5, True):
            with self.subTest(count=count):
                self.assertNotEqual(
                    self.gate([], protected=False, changed_files=count).returncode, 0,
                )
        self.assertEqual(self.gate([], files=[], changed_files=0).returncode, 0)

    def test_review_lifecycle_events_recompute_the_gate(self):
        document = workflow("cycle-108-schema-guard.yml")
        self.assertEqual(
            set(document["on"].get("pull_request_review", {}).get("types", [])),
            {"submitted", "edited", "dismissed"},
        )
        self.assertIn("pull_request_review", document["jobs"]["reviewer-check"]["if"])


class WorkflowCoverageTests(unittest.TestCase):
    def test_required_shell_check_is_scheduled_for_every_main_pr(self):
        trigger = workflow("bats-tests.yml")["on"]["pull_request"]
        self.assertIn("main", trigger["branches"])
        self.assertNotIn("paths", trigger)
        self.assertNotIn("paths-ignore", trigger)

    def test_production_contract_dependencies_trigger_main_validation(self):
        paths = workflow("bats-tests.yml")["on"]["push"]["paths"]
        for path in (
            ".claude/skills/auditing-security/SKILL.md",
            ".claude/skills/reviewing-code/SKILL.md",
            ".claude/skills/implementing-tasks/SKILL.md",
            ".claude/rules/skill-invariants.md",
            ".loa.config.yaml",
            "grimoires/loa/known-failures.md",
            "grimoires/loa/REPO-MAP.md",
            ".github/workflows/eval.yml",
            ".github/workflows/cycle-108-schema-guard.yml",
            ".github/workflows/repo-map-drift.yml",
        ):
            with self.subTest(path=path):
                self.assertTrue(any(fnmatch.fnmatchcase(path, pattern) for pattern in paths))

    def test_security_bats_directory_is_executed(self):
        script = run_step(
            workflow("bats-tests.yml"), "bats", "Run security Bats regressions",
        )
        with tempfile.TemporaryDirectory(prefix="loa-ci-discovery-") as directory:
            root = Path(directory)
            log = root / "selected.json"
            bats = root / "bats"
            bats.write_text(
                "#!/usr/bin/env python3\nimport json, os, sys\n"
                "from pathlib import Path\n"
                "Path(os.environ['SELECTED']).write_text(json.dumps(sys.argv[1:]))\n"
            )
            bats.chmod(0o700)
            result = subprocess.run(
                ["bash", "-e", "-c", script], cwd=ROOT,
                env=dict(os.environ, PATH=f"{root}:{os.environ['PATH']}", SELECTED=str(log)),
                capture_output=True, text=True, check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("tests/security/", json.loads(log.read_text()))

    def test_repository_map_drift_fails_the_actual_workflow_step(self):
        script = run_step(
            workflow("repo-map-drift.yml"), "regen-diff", "Reject regeneration drift",
        )
        with tempfile.TemporaryDirectory(prefix="loa-ci-map-") as directory:
            root = Path(directory)
            generator = root / ".claude/scripts/repo-map-gen.sh"
            generator.parent.mkdir(parents=True)
            for exit_code in (0, 1, 127):
                generator.write_text(f"#!/bin/bash\nexit {exit_code}\n")
                result = subprocess.run(
                    ["bash", "-e", "-c", script], cwd=root,
                    capture_output=True, text=True, check=False,
                )
                with self.subTest(exit_code=exit_code):
                    self.assertEqual(result.returncode == 0, exit_code == 0)


if __name__ == "__main__":
    unittest.main()
