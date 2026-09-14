"""Issue #1245/#1172 regressions; execution fixtures write harmless markers only."""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
HOOK = ROOT / ".claude/hooks/safety/block-destructive-bash.sh"
SETTINGS = (ROOT / ".claude/hooks/settings.hooks.json", ROOT / ".claude/settings.json")


class CarrierTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="loa-carriers-")
        self.addCleanup(self.tmp.cleanup)
        self.env = dict(os.environ, LOA_REPO_ROOT=self.tmp.name,
                        LOA_ZONE_GUARD_AUTH_FILE="/dev/null")
        self.env.pop("LOA_ALLOW_STATE_ZONE_EXEC_WRITE", None)

    def check_command(self, command, expected, pattern=None):
        result = subprocess.run(
            ["bash", str(HOOK)], input=json.dumps({"tool_input": {"command": command}}),
            text=True, capture_output=True, env=self.env, cwd=self.tmp.name,
        )
        self.assertEqual(result.returncode, expected, (command, result.stderr))
        if pattern:
            self.assertIn(pattern, result.stderr)

    def test_bead_description_is_inert_for_system_zone(self):
        self.check_command('br create --description "example: echo x > .claude/hooks/x"', 0)

    def test_commit_description_is_inert_even_beside_a_state_path(self):
        self.check_command(
            "git commit -m 'example: tee .run/cron.d/job.sh' -- .run/cron.d/other.sh", 0)

    def test_sed_range_does_not_become_an_rm_operand(self):
        self.check_command("echo 'rm -rf'; sed -n '335,350p' script.sh", 0)

    def test_quoted_cat_heredoc_is_data(self):
        self.check_command(
            "cat <<'EOF' > grimoires/loa/NOTES.md\n"
            "git push --force origin main\n"
            "rm -rf /\n"
            "echo x > .claude/hooks/x\nEOF", 0)

    def test_double_quoted_tab_stripped_heredoc_is_data(self):
        self.check_command(
            'cat > "notes with spaces.md" <<-"EOF"\n\tgit reset --hard HEAD\n\tEOF', 0)

    def test_quoted_heredoc_substitution_text_is_literal(self):
        self.check_command("cat <<'EOF'\n$(rm -rf /)\n`rm -rf /`\nEOF", 0)

    def test_protected_heredoc_destinations_remain_blocked(self):
        for path, pattern in ((".claude/hooks/x", "FR-SZ2-REDIR"),
                              (".run/cron.d/x.sh", "FR-SZ-REDIR")):
            with self.subTest(path=path):
                self.check_command(f"cat <<'EOF' > {path}\nsafe\nEOF", 2, pattern)

    def test_unquoted_heredoc_substitutions_execute(self):
        self.check_command("cat <<EOF\n$(rm -rf /)\nEOF", 2, "FR-2")

    def test_backtick_substitutions_execute(self):
        for cmd in ('br create --description "`rm -rf /`"',
                    "cat <<EOF\n`rm -rf /`\nEOF"):
            with self.subTest(command=cmd):
                self.check_command(cmd, 2, "FR-2")

    def test_flag_substitutions_remain_active(self):
        for cmd in ('br create --description "$(rm -rf /)"',
                    'br create --description "$(echo x > .claude/hooks/x)"',
                    'git commit -m "$(echo x > .run/cron.d/x.sh)"'):
            with self.subTest(command=cmd):
                self.check_command(cmd, 2)

    def test_execution_after_carrier_remains_blocked(self):
        for cmd in (
            'br create --description "safe" && echo x > .claude/hooks/x',
            "cat <<'EOF'\nsafe\nEOF\nrm -rf /",
            "cat <<'EOF' > script.sh\nrm -rf /\nEOF\nbash script.sh",
        ):
            with self.subTest(command=cmd):
                self.check_command(cmd, 2)

    def test_interpreter_and_pipeline_heredocs_are_not_exempt(self):
        for cmd in (
            "bash <<'EOF'\nrm -rf /\nEOF",
            "psql <<'EOF'\nDROP TABLE users;\nEOF",
            "cat <<'EOF' | bash\nrm -rf /\nEOF",
            "python3 <<'PY'\nimport os\nos.system('rm -rf /')\nPY",
        ):
            with self.subTest(command=cmd):
                self.check_command(cmd, 2)

    def test_incomplete_or_nested_heredocs_are_not_exempt(self):
        for cmd in (
            "cat <<'EOF'\nrm -rf /\n",
            'bash -c "cat <<\'EOF\'\n$(rm -rf /)\nEOF"',
            "cat <<'EOF' <<SECOND\nsafe\nEOF\n$(rm -rf /)\nSECOND",
        ):
            with self.subTest(command=cmd):
                self.check_command(cmd, 2)

    def test_all_existing_catastrophic_and_bounded_controls(self):
        for arg in ("/", "~", "$HOME", ".", "./.ssh"):
            with self.subTest(arg=arg):
                self.check_command("rm -rf " + arg, 2)
        for flags in ("-rf", "-fr", "-rfi"):
            with self.subTest(flags=flags):
                self.check_command(f"rm {flags} /tmp/foo", 0)

    def test_complete_print_only_loop_is_data(self):
        self.check_command(
            "for c in 'rm -rf /' 'rm -rf ~' 'mv .claude backup'; "
            "do printf '%s\\n' \"$c\"; done", 0)
        self.check_command(
            "for cmd in '$(rm -rf /)' '`rm -rf /`';\n"
            "do printf '%s\\n' \"$cmd\"; done", 0)

    def test_literal_only_python_program_is_data(self):
        for source in (
            '["git reset --hard origin/main"]',
            'cases = ["git reset --hard origin/main"]',
            'cases = ["git reset --hard origin/main", "mv .claude backup"]; print(cases)',
            'commands = ["$(rm -rf /)", "`rm -rf /`",]; print(commands)',
        ):
            with self.subTest(source=source):
                self.check_command("python3 -c '" + source + "'", 0)

    def test_loop_execution_and_unrecognized_bodies_keep_matching(self):
        for command in (
            "for c in 'rm -rf /'; do $c; done",
            "for c in 'rm -rf /'; do eval \"$c\"; done",
            "for c in 'rm -rf /'; do bash -c \"$c\"; done",
            "for c in 'rm -rf /'; do printf '%s\\n' \"$c\" | bash; done",
            "for c in 'rm -rf /'; do printf '%s\\n' \"$other\"; done",
            "for c in 'rm -rf /'; do printf '%s\\n' \"$c\"; done; rm -rf /",
            "for c in 'rm -rf /'; do printf '%s\\n' \"$c\"; done > .claude/hooks/x",
        ):
            with self.subTest(command=command):
                self.check_command(command, 2)

    def test_python_execution_is_not_a_literal_carrier(self):
        for source in (
            'import os; os.system("git reset --hard origin/main")',
            'cases = ["git reset --hard origin/main"]; __import__("os").system(cases[0])',
            'cases = ["git reset --hard origin/main"]; exec(cases[0])',
            'cases = [__import__("os").system("git reset --hard origin/main")]',
            'cases = [f"git reset --hard origin/main {__import__(chr(111)+chr(115)).system(chr(105))}"]',
        ):
            with self.subTest(source=source):
                self.check_command("python3 -c '" + source + "'", 2)
        self.check_command(
            """python3 -c 'cases = ["git reset --hard origin/main"]; print(cases)' """
            "> .claude/hooks/x", 2)
        self.check_command(
            """python3 -c 'cases = ["git reset --hard origin/main"]'; rm -rf /""", 2)

    def test_expansions_in_loop_and_python_shell_arguments_stay_active(self):
        for command in (
            'for c in "$(rm -rf /)"; do printf \'%s\\n\' "$c"; done',
            'for c in "`rm -rf /`"; do printf \'%s\\n\' "$c"; done',
            """python3 -c "cases = ['$(rm -rf /)']; print(cases)" """,
            """python3 -c "cases = ['`rm -rf /`']; print(cases)" """,
            """python3 -c "cases = ['$(printf x > .claude/hooks/x)']; print(cases)" """,
        ):
            with self.subTest(command=command):
                self.check_command(command, 2)

    def test_inert_and_executing_programs_have_distinct_shell_effects(self):
        marker = Path(self.tmp.name) / ".claude/hooks/probe"
        marker.parent.mkdir(parents=True)
        for command, expected in (
            ("for c in '$(printf marker > .claude/hooks/probe)'; "
             "do printf '%s\\n' \"$c\"; done", 0),
            ('for c in "$(printf marker > .claude/hooks/probe)"; '
             "do printf '%s\\n' \"$c\"; done", 2),
            ("""python3 -c 'cases = ["$(printf marker > .claude/hooks/probe)"]; print(cases)'""", 0),
            ("""python3 -c "cases = ['$(printf marker > .claude/hooks/probe)']; print(cases)" """, 2),
            ("""python3 -c 'cases = ["printf marker > .claude/hooks/probe"]; print(cases)'""", 0),
            ("""python3 -c 'import os; os.system("printf marker > .claude/hooks/probe")'""", 2),
        ):
            with self.subTest(command=command):
                self.check_command(command, expected)
                env = dict(self.env)
                env.pop("BASH_ENV", None)
                result = subprocess.run(
                    ["bash", "--noprofile", "--norc", "-c", command],
                    text=True, capture_output=True, cwd=self.tmp.name, env=env,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(marker.exists(), expected == 2)
                if marker.exists():
                    self.assertEqual(marker.read_text(), "marker")
                    marker.unlink()

    def test_escaped_quotes_cannot_hide_live_redirects(self):
        for prefix, flag in (("git commit", "-m"),
                             ("br create", "--description"),
                             ("gh pr create", "--body")):
            for target in (".claude/hooks/probe", ".run/cron.d/probe.sh"):
                command = (prefix + " " + flag + r' "abc\" ' + flag
                           + ' " && printf marker > ' + target + ' #"')
                with self.subTest(command=command):
                    self.check_command(command, 2)

    def test_echo_inside_flag_data_cannot_remove_a_quote_boundary(self):
        for text in ("echo label", "printf label", r"echo escaped\\label"):
            command = ('git commit -m "example; ' + text
                       + '" && printf marker > .claude/hooks/probe #"')
            with self.subTest(command=command):
                self.check_command(command, 2)

    def test_nested_carrier_words_do_not_hide_execution(self):
        for command in (
            'br create --description "git commit -m " && printf marker > .claude/hooks/probe #"',
            'echo "git commit -m " && printf marker > .claude/hooks/probe #"',
            'git commit -m "example; br create -d " && printf marker > .claude/hooks/probe #"',
            'eval git commit -m "safe; printf marker > .claude/hooks/probe"',
        ):
            with self.subTest(command=command):
                self.check_command(command, 2)

    def test_escaped_inert_metadata_and_real_command_positions_still_allow(self):
        for command in (
            r'git commit -m "example \"printf x > .claude/hooks/probe\""',
            r'br create --description "example \"mv .claude backup\""',
            r'gh pr create --body "example \"rm -rf /\""',
            'echo ready && git commit -m "example: printf x > .claude/hooks/probe"',
            'git status; br create --description "example: printf x > .run/cron.d/x.sh"',
        ):
            with self.subTest(command=command):
                self.check_command(command, 0)


class HookPathTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(prefix="loa-hook-paths-")
        cls.main = Path(cls.tmp.name) / "project with spaces"
        subprocess.run(["git", "clone", "-q", "--shared", "--no-checkout",
                        str(ROOT), str(cls.main)], check=True, capture_output=True)
        cls.nested = cls.main / ".claude/worktrees/nested tree"
        subprocess.run(["git", "-C", str(cls.main), "worktree", "add", "-q",
                        "--detach", "--no-checkout", str(cls.nested), "HEAD"],
                       check=True, capture_output=True)
        cls.commands = {}
        for settings in SETTINGS:
            data = json.loads(settings.read_text())
            cls.commands[settings] = [
                h["command"] for groups in data["hooks"].values()
                for group in groups for h in group["hooks"] if h["type"] == "command"
            ]
        paths = {path for commands in cls.commands.values() for cmd in commands
                 for path in re.findall(r"\.claude/[\w./-]+\.sh", cmd)}
        for root in (cls.main, cls.nested):
            (root / ".claude/worktrees").mkdir(parents=True, exist_ok=True)
            for path in paths:
                target = root / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(
                    "#!/usr/bin/env python3\n"
                    "import json, os, sys\n"
                    "print(json.dumps({'file': __file__, 'args': sys.argv[1:], "
                    "'cwd': os.getcwd(), 'stdin': sys.stdin.read()}))\n"
                )
                target.chmod(0o755)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_every_command_resolves_from_each_cwd_and_preserves_input(self):
        for settings, commands in self.commands.items():
            for root in (self.main, self.nested):
                for cwd in (root, root / ".claude", root / ".claude/worktrees"):
                    for cmd in commands:
                        with self.subTest(settings=settings.name, cwd=cwd, command=cmd):
                            result = subprocess.run(
                                ["sh", "-c", cmd], cwd=cwd, input="exact stdin\n",
                                text=True, capture_output=True,
                                env=dict(os.environ, CLAUDE_PROJECT_DIR="/wrong/anchor"),
                            )
                            self.assertEqual(result.returncode, 0, result.stderr)
                            record = json.loads(result.stdout)
                            paths = re.findall(r"\.claude/[\w./-]+\.sh", cmd)
                            self.assertEqual(record["file"], str(root / paths[0]))
                            self.assertEqual(record["cwd"], str(cwd))
                            self.assertEqual(record["stdin"], "exact stdin\n")
                            if len(paths) > 1:
                                self.assertEqual(record["args"][0], str(root / paths[1]))
                            if cmd.endswith(" --notify"):
                                self.assertEqual(record["args"], ["--notify"])

    def test_real_wrapped_fence_still_blocks_from_nested_cwd(self):
        with tempfile.TemporaryDirectory(prefix="loa-real-hook-") as tmp:
            root = Path(tmp) / "real project"
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            for relative in ("hook-guard.sh", "safety/block-destructive-bash.sh"):
                target = root / ".claude/hooks" / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(ROOT / ".claude/hooks" / relative, target)
            cwd = root / ".claude/worktrees"
            cwd.mkdir()
            for settings, commands in self.commands.items():
                cmd = next(c for c in commands if "block-destructive-bash.sh" in c)
                with self.subTest(settings=settings.name):
                    result = subprocess.run(
                        ["sh", "-c", cmd], cwd=cwd, text=True, capture_output=True,
                        input=json.dumps({"tool_input": {"command": "rm -rf /"}}),
                        env=dict(os.environ, LOA_REPO_ROOT=str(root)),
                    )
                    self.assertEqual(result.returncode, 2, result.stderr)
                    self.assertIn("FR-2-BLOCK", result.stderr)


class WriteGuardDiagnosisTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="loa-write-guards-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / ".run").mkdir()
        self.env = dict(os.environ, LOA_PROJECT_ROOT=str(self.root),
                        PROJECT_ROOT=str(self.root), RUN_DIR=str(self.root / ".run"),
                        LOA_ZONE_GUARD_AUTH_FILE="/dev/null",
                        LOA_ZONE_GUARD_TRAJECTORY_DIR=str(self.root / "trajectory"))
        for name in ("LOA_ZONE_GUARD_BYPASS", "LOA_ZONE_GUARD_DISABLE",
                     "LOA_TEAM_MEMBER", "CLAUDE_TOOL_FILE_PATH", "LOA_ACTOR"):
            self.env.pop(name, None)

    def invoke(self, hook, path):
        return subprocess.run(
            ["bash", str(hook)], cwd=self.root, env=self.env, text=True,
            input=json.dumps({"tool_name": "Write", "tool_input": {"file_path": path}}),
            capture_output=True,
        )

    def test_spiral_relative_state_paths_match_absolute_paths(self):
        (self.root / ".run/spiral-dispatch-active").touch()
        hook = ROOT / ".claude/hooks/safety/spiral-dispatch-guard.sh"
        for relative in ("grimoires/loa/a2a/bug-case/engineer-feedback.md",
                         ".run/state.json", ".beads/issues.jsonl", ".claude/plans/plan.md"):
            for path in (relative, str(self.root / relative)):
                with self.subTest(path=path):
                    result = self.invoke(hook, path)
                    self.assertEqual(result.returncode, 0, result.stderr)

    def test_identical_app_payload_depends_on_spiral_state(self):
        hook = ROOT / ".claude/hooks/safety/spiral-dispatch-guard.sh"
        path = "scripts/lib/segment-emitter.py"
        self.assertEqual(self.invoke(hook, path).returncode, 0)
        (self.root / ".run/spiral-dispatch-active").touch()
        result = self.invoke(hook, path)
        self.assertEqual(result.returncode, 2)
        self.assertIn("spiral-dispatch-guard", result.stderr)
        (self.root / ".run/spiral-harness-dispatched").touch()
        self.assertEqual(self.invoke(hook, path).returncode, 0)

    def test_spiral_traversal_does_not_gain_state_exemption(self):
        (self.root / ".run/spiral-dispatch-active").touch()
        hook = ROOT / ".claude/hooks/safety/spiral-dispatch-guard.sh"
        for path in ("grimoires/../scripts/lib/x.py", ".run/../src/x.py"):
            with self.subTest(path=path):
                self.assertEqual(self.invoke(hook, path).returncode, 2)

    def prepare_zone_guard(self):
        if not shutil.which("yq"):
            self.skipTest("yq required to exercise the actual YAML reader")
        hook = self.root / ".claude/hooks/safety/zone-write-guard.sh"
        hook.parent.mkdir(parents=True)
        shutil.copy2(ROOT / ".claude/hooks/safety/zone-write-guard.sh", hook)
        zones = self.root / "zones.yaml"
        zones.write_text('zones:\n  framework:\n    tracked_paths:\n      - ".claude/**"\n')
        self.env["LOA_ZONES_FILE"] = str(zones)
        return hook, zones

    def test_zone_guard_parses_yaml_with_installed_yq(self):
        hook, _ = self.prepare_zone_guard()
        result = self.invoke(hook, ".claude/hooks/protected.sh")
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("framework-zone", result.stderr)
        self.assertEqual(self.invoke(hook, "grimoires/loa/NOTES.md").returncode, 0)

    def test_zone_guard_does_not_reuse_old_failed_parse_cache(self):
        hook, zones = self.prepare_zone_guard()
        stat = subprocess.run(
            ["stat", "-Lc", "%y:%s", "--", str(zones)], text=True, capture_output=True)
        if stat.returncode:
            self.skipTest("GNU stat cache identity unavailable; hook uses uncached parsing")
        identity = stat.stdout.strip()
        cache = self.root / ".run/perf-cache/zone-write-guard.v1.rows"
        cache.parent.mkdir()
        cache.write_text(f"{identity}:{zones}\n")
        result = self.invoke(hook, ".claude/hooks/protected.sh")
        self.assertEqual(result.returncode, 2, result.stderr)


class HookLintTests(unittest.TestCase):
    def test_cache_hygiene_scans_anchored_hook_without_executing_it(self):
        with tempfile.TemporaryDirectory(prefix="loa-hook-lint-") as tmp:
            root = Path(tmp)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            hook = root / ".claude/hooks/clock.sh"
            hook.parent.mkdir(parents=True)
            hook.write_text('#!/usr/bin/env bash\necho "$(date)"\ntouch SHOULD_NOT_EXECUTE\n')
            hook.chmod(0o755)
            settings = {"hooks": {"SessionStart": [{"matcher": "", "hooks": [{
                "type": "command",
                "command": '"$(git rev-parse --show-toplevel)"/.claude/hooks/clock.sh',
            }]}]}}
            (root / ".claude/settings.json").write_text(json.dumps(settings))
            result = subprocess.run(
                ["bash", str(ROOT / ".claude/scripts/lint-invariants.sh")],
                cwd=root, text=True, capture_output=True,
            )
            self.assertIn("hook-cache-hygiene: .claude/hooks/clock.sh:", result.stdout)
            self.assertFalse((root / "SHOULD_NOT_EXECUTE").exists())


if __name__ == "__main__":
    unittest.main()
