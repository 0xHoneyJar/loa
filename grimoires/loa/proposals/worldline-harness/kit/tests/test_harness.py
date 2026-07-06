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

    def test_context_message_carries_world_and_next_gate(self):
        # AC1: continuity injection carries the WORLD (world, zone legend) and the
        # concrete next-gate evidence — not the FSM skeleton / prose slogan.
        self.assertEqual(self.run_h("init").returncode, 0)
        p = self.run_h("hook", "--event", "SessionStart", stdin=json.dumps({"hook_event_name": "SessionStart"}))
        self.assertEqual(p.returncode, 0)
        ctx = json.loads(p.stdout)["additionalContext"]
        self.assertIn("world:", ctx)
        self.assertIn("zones", ctx.lower())
        # at INIT the only gate is INIT->ORIENTING via CLAUDE.md — must be concrete, not a slogan
        self.assertIn("ORIENTING", ctx)
        self.assertIn("CLAUDE.md", ctx)

    def test_events_record_zone_and_world(self):
        # AC2: every event is spatially addressable — zone derived from the touched
        # path, world from the repo root. system/state/app classify correctly.
        self.assertEqual(self.run_h("init").returncode, 0)
        self.run_h("hook", "--event", "PreToolUse",
                   stdin=json.dumps({"tool_name": "Write", "tool_input": {"file_path": ".claude/settings.json"}}))
        self.run_h("hook", "--event", "PreToolUse",
                   stdin=json.dumps({"tool_name": "Write", "tool_input": {"file_path": "grimoires/loa/x.md"}}))
        self.run_h("hook", "--event", "PreToolUse",
                   stdin=json.dumps({"tool_name": "Write", "tool_input": {"file_path": "src/app.ts"}}))
        events_path = self.tmp / ".loa-harness" / "runtime" / "events.jsonl"
        recs = [json.loads(l) for l in events_path.read_text(encoding="utf-8").splitlines() if l.strip()]
        writes = [r for r in recs if r["hook_event_name"] == "PreToolUse"]
        zones = [r.get("zone") for r in writes]
        self.assertIn("system", zones)
        self.assertIn("state", zones)
        self.assertIn("app", zones)
        worlds = {r.get("world") for r in writes}
        self.assertEqual(worlds, {self.tmp.name})  # world = repo root basename, non-null
        # AC3: new columns do not break the hash chain
        self.assertTrue(json.loads(self.run_h("verify").stdout)["ok"])


    def test_denial_recall_in_continuity(self):
        # Move 2 / denial-recall: after a command is denied, the continuity injection must
        # surface it ("the wall remembers") so a weak model stops resubmitting it.
        self.assertEqual(self.run_h("init").returncode, 0)
        self.run_h("hook", "--event", "PreToolUse",
                   stdin=json.dumps({"tool_name": "Bash", "tool_input": {"command": "rm -rf /"}}))
        p = self.run_h("hook", "--event", "SessionStart", stdin=json.dumps({"hook_event_name": "SessionStart"}))
        ctx = json.loads(p.stdout)["additionalContext"]
        self.assertIn("recent denials", ctx.lower())
        self.assertIn("LOA harness policy", ctx)  # the deny reason is recalled

    def test_policy_floor_evidence_cannot_be_weakened(self):
        # Decision #2: the policy default_transition_evidence is a FLOOR. A request that
        # self-authors trivial (empty) evidence must NOT bypass it — the substrate holds the
        # gate, not the model's self-authored request (closes BB F2/F3, Thompson F8).
        self.assertEqual(self.run_h("init").returncode, 0)
        (self.tmp / "CLAUDE.md").unlink()  # the INIT->ORIENTING floor requires CLAUDE.md
        req_path = self.tmp / ".loa-harness" / "runtime" / "transition.request.json"
        req_path.write_text(json.dumps({
            "schema_version": "loa-harness.transition-request/v0.1",
            "from": "INIT", "to": "ORIENTING", "reason": "trivial",
            "evidence": [],  # attempt to self-author an empty passing gate
        }), encoding="utf-8")
        self.run_h("hook", "--event", "Stop", stdin=json.dumps({"hook_event_name": "Stop"}))
        status = json.loads(self.run_h("status").stdout)
        self.assertEqual(status["state"], "INIT", "policy floor bypassed by empty request evidence")

    def test_concurrent_appends_no_duplicate_seq(self):
        # Regression: concurrent hooks must serialize on seq allocation, not race to a
        # duplicate seq (the collision that corrupted a real ledger under fast cursor-gate
        # calls). Fire N hooks in parallel; assert unique contiguous seqs + verify green.
        self.assertEqual(self.run_h("init").returncode, 0)
        N = 12
        script = str(self.tmp / ".loa-harness" / "bin" / "loa_harness.py")
        payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": "ls"}})
        procs = [
            subprocess.Popen(
                [sys.executable, script, "hook", "--event", "PreToolUse"],
                stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                text=True, cwd=self.tmp,
            )
            for _ in range(N)
        ]
        for p in procs:
            p.communicate(input=payload)
        events_path = self.tmp / ".loa-harness" / "runtime" / "events.jsonl"
        seqs = [json.loads(l)["seq"] for l in events_path.read_text(encoding="utf-8").splitlines() if l.strip()]
        self.assertEqual(len(seqs), len(set(seqs)), f"duplicate seq under concurrency: {seqs}")
        self.assertEqual(sorted(seqs), list(range(1, len(seqs) + 1)), "seqs not contiguous 1..N")
        self.assertTrue(json.loads(self.run_h("verify").stdout)["ok"], "chain broke under concurrency")

    def test_evidence_path_traversal_rejected(self):
        # F2 (codex/BB): validate_evidence_item is repo-scoped. An absolute path
        # or a ../ escape must be REJECTED, not silently satisfied by a file
        # outside the project. Direct unit test of the guarded resolution.
        import importlib.util
        spec = importlib.util.spec_from_file_location("loa_harness", str(SCRIPT))
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        outside = self.tmp.parent / f"loa-f2-outside-{self.tmp.name}.txt"
        outside.write_text("x" * 200, encoding="utf-8")
        self.addCleanup(lambda: outside.unlink(missing_ok=True))
        _, policy = mod.load_policy(self.tmp, str(POLICY))
        h = mod.Harness(self.tmp, POLICY, policy)
        ok_abs, msg_abs = h.validate_evidence_item({"path": str(outside), "min_bytes": 1})
        self.assertFalse(ok_abs, f"absolute evidence path accepted: {msg_abs}")
        ok_rel, msg_rel = h.validate_evidence_item({"path": f"../{outside.name}", "min_bytes": 1})
        self.assertFalse(ok_rel, f"traversal evidence path accepted: {msg_rel}")
        (self.tmp / "prd.md").write_text("y" * 200, encoding="utf-8")
        ok_in, _ = h.validate_evidence_item({"path": "prd.md", "min_bytes": 1})
        self.assertTrue(ok_in, "legit in-repo evidence path rejected")


if __name__ == "__main__":
    unittest.main()
