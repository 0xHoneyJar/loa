"""Local caller regressions for #1195, #1213 and #1233; no host/model calls."""
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class Callers(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="loa-lifecycle-")
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.root = self.base / "consumer repo"
        self.root.mkdir()
        self.env = {k: os.environ[k] for k in ("HOME", "PATH") if k in os.environ}
        self.env.update(TMPDIR=str(self.base), PYTHONDONTWRITEBYTECODE="1",
                        LANG="C.UTF-8", LC_ALL="C.UTF-8", GIT_CONFIG_NOSYSTEM="1",
                        GIT_CONFIG_GLOBAL="/dev/null", GIT_OPTIONAL_LOCKS="0")
        self.call(["git", "init", "-qb", "main"])
        self.write(".loa.config.yaml", "{}\n")

    def call(self, args, cwd=None, payload=None, check=True, env=None):
        p = subprocess.run(args, cwd=cwd or self.root, env=env or self.env,
                           input=payload, text=True, capture_output=True, timeout=60)
        if check:
            self.assertEqual(p.returncode, 0, f"{args}\n{p.stdout}\n{p.stderr}")
        return p

    def write(self, path, text, root=None):
        p = (root or self.root) / path
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)
        return p

    def copy(self, relative):
        dst = self.root / relative
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / relative, dst)

    def scripts(self, *names):
        for name in names:
            self.copy(".claude/scripts/" + name)

    def commit(self):
        self.call(["git", "add", "."])
        self.call(["git", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                   "-c", "core.hooksPath=/dev/null", "-c", "commit.gpgSign=false",
                   "commit", "-qm", "fixture"])

    def hook_fixture(self):
        settings = json.loads((ROOT / ".claude/settings.json").read_text())
        self.hooks = [h["command"] for group in settings["hooks"]["PreToolUse"]
                      if "Write" in group["matcher"] for h in group["hooks"]]
        for command in self.hooks:
            for path in re.findall(r"\.claude/hooks/[\w/.-]+\.sh", command):
                self.copy(path)
        self.scripts("compat-lib.sh")
        self.write("grimoires/loa/zones.yaml",
                   "zones:\n  framework:\n    tracked_paths: ['.claude/**']\n"
                   "  project:\n    tracked_paths: ['src/**']\n"
                   "  shared:\n    tracked_paths: ['grimoires/**']\n")
        self.write(".run/platform-features.json", '{"active_skill_available":false}')
        (self.root / "grimoires/loa/a2a/sprint-1").mkdir(parents=True)
        (self.root / "src").mkdir()
        (self.root / "grimoires/loa/app-link").symlink_to(self.root / "src")

    def decisions(self, skill, path, tool="Write", cwd=None):
        tool_input = {"file_path": path, "content": "fixture"}
        if skill is not None:
            tool_input["active_skill"] = skill
        payload = json.dumps({"tool_name": tool, "tool_input": tool_input})
        return [self.call(["bash", "-c", cmd], cwd=cwd, payload=payload, check=False)
                for cmd in self.hooks]

    def test_review_write_boundary_through_configured_hooks(self):
        self.hook_fixture()
        for skill in ("review-sprint", "/review-sprint", "reviewing-code",
                      "audit", "/audit-sprint", "auditing-security"):
            self.write(".run/state.json", '{"state":"RUNNING","phase":"IMPLEMENT"}')
            for tool in ("Write", "Edit", "MultiEdit"):
                for path in ("src/probe.py", ".claude/scripts/probe.sh", "README.md",
                             "grimoires/loa/../../src/probe.py",
                             "grimoires/loa/app-link/probe.py", "../outside.txt"):
                    with self.subTest(skill=skill, tool=tool, denied=path):
                        results = self.decisions(skill, str(self.root / path), tool)
                        self.assertTrue(any(p.returncode == 2 for p in results),
                                        [(p.returncode, p.stdout, p.stderr) for p in results])
                for path in ("grimoires/loa/a2a/engineer-feedback.md",
                             "grimoires/loa/sprint.md", ".beads/feedback.jsonl",
                             ".run/review/prompt.txt", "grimoires/loa/a2a/sprint-1/COMPLETED"):
                    with self.subTest(skill=skill, tool=tool, allowed=path):
                        results = self.decisions(skill, str(self.root / path), tool)
                        self.assertTrue(all(p.returncode == 0 and not p.stdout.strip()
                                            for p in results), [p.stderr for p in results])

    def test_review_phase_fallback_and_nested_cwd(self):
        self.hook_fixture()
        nested = self.root / "src"
        # A running plan must not override its current REVIEW/AUDIT phase.
        for statefile in ("state.json", "sprint-plan-state.json", "simstim-state.json"):
            for phase in ("REVIEW", "AUDIT", "reviewing", "auditing"):
                self.write(".run/" + statefile,
                           json.dumps({"state": "RUNNING", "plan_id": "fixture", "phase": phase}))
                for path in ("probe.py", "../grimoires/loa/app-link/probe.py"):
                    with self.subTest(statefile=statefile, phase=phase, path=path):
                        results = self.decisions(None, path, cwd=nested)
                        self.assertTrue(any(p.returncode == 2 for p in results))
                results = self.decisions(None, "../grimoires/loa/a2a/feedback.md", cwd=nested)
                self.assertTrue(all(p.returncode == 0 and not p.stdout.strip() for p in results))
                self.assertTrue(any(p.returncode == 2 for p in
                                    self.decisions("run", "probe.py", cwd=nested)))
                (self.root / ".run" / statefile).unlink()
        self.write(".run/state.json", '{"state":"RUNNING","phase":"IMPLEMENT"}')
        self.assertTrue(all(p.returncode == 0 and not p.stdout.strip()
                            for p in self.decisions("implement", str(nested / "probe.py"))))

    def test_review_repair_transitions_and_retained_state(self):
        self.hook_fixture()
        target = str(self.root / "src/probe.py")
        for state in ("RUNNING", "COMPLETE", "JACKED_OUT", "INTERRUPTED"):
            for phase in ("REVIEW", "AUDIT"):
                for role in ("implement", "/implement", "implementing-tasks"):
                    with self.subTest(state=state, phase=phase, role=role):
                        self.write(".run/state.json", json.dumps({"state": state, "phase": phase}))
                        self.assertTrue(all(p.returncode == 0 for p in self.decisions(role, target)))
                # Explicit review is still restricted, even after completion.
                self.assertTrue(any(p.returncode == 2 for p in self.decisions("review-sprint", target)))
                results = self.decisions("run", target)
                self.assertEqual(any(p.returncode == 2 for p in results), state == "RUNNING")
        for statefile in ("sprint-plan-state.json", "simstim-state.json"):
            self.write(".run/state.json", '{"state":"RUNNING","phase":"IMPLEMENT"}')
            for state in ("JACKED_OUT", "RUNNING"):
                self.write(".run/" + statefile, json.dumps({"state": state, "phase": "AUDIT"}))
                for role in (None, "run", "implement"):
                    self.assertTrue(all(p.returncode == 0 for p in self.decisions(role, target)))
            self.write(".run/state.json", '{"state":"RUNNING","phase":"REVIEW"}')
            self.write(".run/" + statefile, '{"state":"RUNNING","phase":"IMPLEMENT"}')
            self.assertTrue(any(p.returncode == 2 for p in self.decisions("run", target)))
            (self.root / ".run" / statefile).unlink()

    def test_review_git_wrapper_has_only_stdout_authority(self):
        self.hook_fixture()
        self.scripts("review-git.sh")
        settings = json.loads((ROOT / ".claude/settings.json").read_text())
        bash_hooks = [h["command"] for group in settings["hooks"]["PreToolUse"]
                      if group["matcher"] == "Bash" for h in group["hooks"]]
        for command in bash_hooks:
            for path in re.findall(r"\.claude/hooks/[\w/.-]+\.sh", command):
                self.copy(path)
        self.write("src/input.txt", "original\n")
        self.write("src/review-output.diff", "sentinel\n")
        self.commit()
        self.call(["git", "checkout", "-qb", "review-fixture"])
        self.write("src/input.txt", "changed\n")
        self.commit()
        self.write(".run/state.json", '{"state":"RUNNING","phase":"AUDIT"}')
        sentinel = self.root / "src/review-output.diff"
        for args, expected in (
            (["diff"], 0), (["log"], 0),
            (["diff", "--output=src/review-output.diff"], 2),
            (["log", "--output=src/review-output.diff"], 2),
            (["diff", "HEAD", "--output=src/review-output.diff", "--", "src/input.txt"], 2),
        ):
            command = shlex.join([".claude/scripts/review-git.sh", *args])
            payload = json.dumps({"tool_name": "Bash", "tool_input": {
                "command": command, "active_skill": "audit"}})
            for hook in bash_hooks:
                self.assertEqual(self.call(["bash", "-c", hook], payload=payload, check=False).returncode, 0)
            result = self.call(["bash", ".claude/scripts/review-git.sh", *args], check=False)
            self.assertEqual(result.returncode, expected, result.stderr)
            self.assertEqual(sentinel.read_text(), "sentinel\n")
            if expected == 0:
                self.assertTrue(result.stdout.strip())
            else:
                self.assertFalse(result.stdout)
        self.assertTrue(any(p.returncode == 2 for p in self.decisions("audit", str(sentinel))))
        self.assertTrue(all(p.returncode == 0 for p in
                            self.decisions("audit", str(self.root / ".run/review/diff.txt"))))

    def status_fixture(self):
        self.scripts("loa-status.sh", "golden-path.sh", "workflow-state.sh",
                     "bootstrap.sh", "path-lib.sh", "compat-lib.sh", "cache-manager.sh",
                     "lib/normalize-json.sh")
        helper = ROOT / ".claude/scripts/lib/stale-worktree.sh"
        if helper.exists():
            self.copy(".claude/scripts/lib/stale-worktree.sh")
        self.write(".loa-version.json", '{"framework_version":"1.0.0","history":[]}')
        self.write(".gitignore", ".claude/cache/\n.run/\n")
        self.write("grimoires/loa/prd.md", "# PRD\n")
        self.write("grimoires/loa/sdd.md", "# SDD\n")
        self.write("grimoires/loa/sprint.md", "## Sprint 1\n")
        self.write("grimoires/loa/a2a/sprint-1/COMPLETED", "fixture\n")
        self.write("grimoires/loa/ledger.json",
                   '{"active_cycle":"cycle-fixture","cycles":[{"id":"cycle-fixture","status":"active"}]}')

    def test_workflow_json_with_cold_and_warm_cache(self):
        self.status_fixture()
        for attempt in ("cold", "warm"):
            with self.subTest(cache=attempt):
                output = self.call(["bash", ".claude/scripts/workflow-state.sh", "--json"]).stdout
                self.assertEqual(json.loads(output)["state"], "complete")
                output = self.call(["bash", ".claude/scripts/loa-status.sh", "--json"]).stdout
                self.assertEqual(json.loads(output)["state"], "complete")

    def test_documented_loa_sequence_respects_stale_cycle(self):
        self.status_fixture()
        self.commit()
        parked = self.base / "parked worktree"
        self.call(["git", "worktree", "add", "-q", "--detach", str(parked)])
        self.write("grimoires/loa/ledger.json",
                   '{"active_cycle":null,"cycles":[{"id":"cycle-fixture","status":"archived"}]}')
        self.commit()
        self.call(["git", "update-ref", "refs/remotes/origin/main", "HEAD"])
        self.write("dirty.txt", "preserve me\n", root=parked)
        before = self.call(["git", "status", "--porcelain"], cwd=parked).stdout
        status = json.loads(self.call(["bash", ".claude/scripts/loa-status.sh", "--json"],
                                     cwd=parked).stdout)
        self.assertEqual(status["suggested_command"], "git worktree list")
        result = self.call(["bash", "-c", 'source .claude/scripts/golden-path.sh; '
                            'golden_suggest_command; golden_menu_options --json'], cwd=parked)
        suggestion, menu = result.stdout.split("\n", 1)
        self.assertEqual(suggestion, "git worktree list")
        options = json.loads(menu)
        self.assertEqual(options[0]["action"], "worktree-list")
        self.assertTrue(options[0]["recommended"])
        self.assertFalse(any(x["action"] in ("ship", "build", "archive-cycle") for x in options))
        gate = self.call(["bash", "-c", 'source .claude/scripts/golden-path.sh; '
                          'golden_check_ship_ready'], cwd=parked, check=False)
        self.assertEqual(gate.returncode, 1)
        self.assertIn("cycle-fixture", gate.stdout)
        journey = self.call(["bash", "-c", 'source .claude/scripts/golden-path.sh; '
                             'golden_format_journey'], cwd=parked).stdout
        self.assertIn("stale snapshot", journey)
        self.assertNotIn("/ship", journey)
        local_only = self.call(["bash", "-c", 'source .claude/scripts/golden-path.sh; '
                                'STALE_CHECK=false golden_suggest_command'], cwd=parked)
        self.assertEqual(local_only.stdout.strip(), "/ship")
        self.assertEqual(before, self.call(["git", "status", "--porcelain"], cwd=parked).stdout)
        # Exact matching record is required; null active_cycle alone is insufficient.
        self.write("grimoires/loa/ledger.json",
                   '{"active_cycle":null,"cycles":[{"id":"other-cycle","status":"archived"}]}')
        self.commit()
        self.call(["git", "update-ref", "refs/remotes/origin/main", "HEAD"])
        self.assertEqual(self.call(["bash", "-c", 'source .claude/scripts/golden-path.sh; '
                                    'golden_suggest_command'], cwd=parked).stdout.strip(), "/ship")

    def scheduler_fixture(self, mounted=False):
        rel = ".claude/skills/scheduled-cycle-template/contracts/session-cap-bb"
        self.contract = self.root / rel
        for name in ("reader.sh", "decider.sh", "dispatcher.sh"):
            self.copy(f"{rel}/{name}")
        self.scripts("bash-version-guard.sh", "lib/env-loader.sh")
        bb = ".claude/skills/bridgebuilder-review"
        self.copy(f"{bb}/resources/entry.sh")
        # Only config and its imported support modules run. main.js never runs.
        shutil.copytree(ROOT / bb / "dist", self.root / bb / "dist")
        self.copy(f"{bb}/package.json")
        modules = os.environ.get("LOA_TEST_BB_NODE_MODULES", str(ROOT / bb / "node_modules"))
        self.assertTrue((Path(modules) / "zod").is_dir(),
                        "Set LOA_TEST_BB_NODE_MODULES to installed BB dependencies for the real config test")
        (self.root / bb / "node_modules").symlink_to(Path(modules).resolve())
        if mounted:
            (self.root / ".loa").mkdir()
            shutil.move(str(self.root / ".claude"), self.root / ".loa/.claude")
            (self.root / ".claude").mkdir()
            (self.root / ".claude/skills").symlink_to("../.loa/.claude/skills")
            self.contract = self.contract.resolve()
        self.call(["git", "remote", "add", "origin", "https://github.com/fixture/intended.git"])
        self.write(".run/session-limit-state.json",
                   '{"active_run_state_snapshot":{"sprint_plan":{"state":"RUNNING"}}}')
        self.write(".env", "LOA_FIXTURE_ORIGIN=intended\n")
        outside = self.base / "unrelated caller"
        outside.mkdir()
        self.write(".env", "LOA_FIXTURE_ORIGIN=unrelated\n", root=outside)
        self.write(".loa.config.yaml", "bridgebuilder:\n  enabled: true\n", root=outside)
        node = shutil.which("node")
        self.assertIsNotNone(node)
        # Replace only the final Node main handoff with actual resolveConfig.
        runner = self.write("config-probe.mjs", """
import {pathToFileURL} from 'node:url';
const main = process.argv[2];
const {resolveConfig} = await import(pathToFileURL(main.replace(/main.js$/, 'config.js')));
let record = {cwd:process.cwd(), origin:process.env.LOA_FIXTURE_ORIGIN};
try {
  const config = await resolveConfig({repos:[process.argv[4]]}, process.env);
  record.accepted = true;
} catch (error) {
  record.accepted = false; record.error = error.message; process.exitCode = 17;
}
console.log(JSON.stringify(record));
""", root=self.base)
        wrapper = self.write("bin/node", "#!/usr/bin/env bash\n"
                             f"exec {shlex.quote(node)} {shlex.quote(str(runner))} \"$@\"\n",
                             root=self.base)
        wrapper.chmod(0o755)
        self.env["PATH"] = str(wrapper.parent) + os.pathsep + self.env["PATH"]
        return outside

    def test_scheduler_real_entry_and_config_use_consumer_cwd(self):
        outside = self.scheduler_fixture()
        self.check_scheduler_config(outside)

    def test_scheduler_mounted_entry_and_config_use_consumer_cwd(self):
        outside = self.scheduler_fixture(mounted=True)
        self.check_scheduler_config(outside)

    def check_scheduler_config(self, outside):
        for enabled in (False, True):
            self.write(".loa.config.yaml", f"bridgebuilder:\n  enabled: {str(enabled).lower()}\n")
            cycle = "config-" + str(enabled)
            for name in ("reader", "decider"):
                self.call(["bash", str(self.contract / f"{name}.sh"), cycle, "sched", "0", "[]"],
                          cwd=outside)
            p = self.call(["bash", str(self.contract / "dispatcher.sh"), cycle, "sched", "2", "[]"],
                          cwd=outside, check=False)
            record, receipt = [json.loads(x) for x in p.stdout.splitlines()]
            self.assertEqual(record["cwd"], str(self.root))
            self.assertEqual(record["origin"], "intended")
            self.assertEqual(record["accepted"], enabled)
            self.assertEqual(p.returncode, 0 if enabled else 17)
            self.assertEqual(receipt["bb_exit_code"], p.returncode)
            self.assertEqual(receipt["repo"], "fixture/intended")

    def test_scheduler_preserves_relative_entry_override(self):
        outside = self.scheduler_fixture()
        self.write("override.sh", "#!/usr/bin/env bash\nprintf '%s\\n' \"$PWD\"\n",
                   root=outside)
        # Non-executable overrides still use bash.
        self.env["LOA_SESSION_CAP_BB_ENTRY"] = "./override.sh"
        self.env["LOA_SESSION_CAP_BB_REPO"] = "explicit/repo"
        self.write("loa-session-cap-bb.override/decider.json", '{"action":"dispatch"}', root=self.base)
        p = self.call(["bash", str(self.contract / "dispatcher.sh"), "override", "sched", "2", "[]"],
                      cwd=outside)
        cwd, receipt = p.stdout.split("\n", 1)
        self.assertEqual(cwd, str(self.root))
        self.assertEqual(json.loads(receipt)["repo"], "explicit/repo")


if __name__ == "__main__":
    unittest.main()
