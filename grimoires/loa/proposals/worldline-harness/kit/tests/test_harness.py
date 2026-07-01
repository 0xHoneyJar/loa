import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "bin" / "loa_harness.py"
POLICY = ROOT / "config" / "policy.example.json"


class HarnessTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="loa-harness-test-"))
        (self.tmp / ".loa-harness" / "bin").mkdir(parents=True)
        shutil.copy2(SCRIPT, self.tmp / ".loa-harness" / "bin" / "loa_harness.py")
        shutil.copy2(POLICY, self.tmp / ".loa-harness" / "policy.json")
        (self.tmp / "CLAUDE.md").write_text("# Project Instructions\nUse LOA.\n", encoding="utf-8")

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def run_h(self, *args, stdin=None):
        return subprocess.run(
            [sys.executable, str(self.tmp / ".loa-harness" / "bin" / "loa_harness.py"), *args],
            input=stdin,
            text=True,
            cwd=self.tmp,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

    def test_blocks_destructive_bash(self):
        self.assertEqual(self.run_h("init").returncode, 0)
        payload = {"tool_name": "Bash", "tool_input": {"command": "rm -rf /"}}
        p = self.run_h("hook", "--event", "PreToolUse", stdin=json.dumps(payload))
        self.assertEqual(p.returncode, 0)
        out = json.loads(p.stdout)
        self.assertEqual(out["hookSpecificOutput"]["permissionDecision"], "deny")

    def test_transition_advances_on_stop(self):
        self.assertEqual(self.run_h("init").returncode, 0)
        self.assertEqual(self.run_h("request-transition", "--to", "ORIENTING", "--reason", "bootstrap").returncode, 0)
        p = self.run_h("hook", "--event", "Stop", stdin=json.dumps({"hook_event_name":"Stop"}))
        self.assertEqual(p.returncode, 0)
        status = json.loads(self.run_h("status").stdout)
        self.assertEqual(status["state"], "ORIENTING")
        verify = json.loads(self.run_h("verify").stdout)
        self.assertTrue(verify["ok"])

    def test_blocks_system_write(self):
        self.assertEqual(self.run_h("init").returncode, 0)
        payload = {"tool_name": "Write", "tool_input": {"file_path": ".claude/settings.json"}}
        p = self.run_h("hook", "--event", "PreToolUse", stdin=json.dumps(payload))
        out = json.loads(p.stdout)
        self.assertEqual(out["hookSpecificOutput"]["permissionDecision"], "deny")


if __name__ == "__main__":
    unittest.main()
