"""evals/harness/spend.sh dedup (bd-um8ol, Sprint 270 review dissent DISS-C-006; cycle-133 sdd.md C-7).

A run row is identified by (run_id, batch); a row without a run_id ("anonymous") is identified by its content, so
the same anonymous row in the tracked copy and in the live runs.jsonl counts once, while two anonymous rows in
one file still count individually. Lives here because spend.bats is outside this task's ownership; the cases run
the real script with explicit --runs files and an empty ledger (no repository state is read)."""
import json
import os
import shutil
import subprocess
import tempfile
import unittest

import _path

SPEND = os.path.join(os.path.dirname(_path.ANALYSIS_DIR), "harness", "spend.sh")
TS = "2026-10-21T01:00:00Z"


def _rows(path, rows):
    with open(path, "w", encoding="utf-8") as f:
        for r in rows:
            f.write((r if isinstance(r, str) else json.dumps(r, sort_keys=True)) + "\n")


@unittest.skipUnless(shutil.which("bash"), "spend.sh needs bash")
class SpendDedupTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="c132-spend-")
        self.ledger = os.path.join(self.tmp, "ledger.jsonl")
        open(self.ledger, "w").close()

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def spend(self, *files):
        p = subprocess.run(["bash", SPEND, "--since", "2026-10-20", "--cap", "100", "--reserve", "0", "--json",
                            "--ledger", self.ledger, "--runs"] + list(files), capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stderr)
        return json.loads(p.stdout), p.stderr

    def test_same_anonymous_row_in_two_files_counts_once(self):
        anon = json.dumps({"batch": "b1", "cost_usd": 4, "started": TS}, sort_keys=True)
        a, b = os.path.join(self.tmp, "tracked.jsonl"), os.path.join(self.tmp, "live.jsonl")
        _rows(a, [anon, {"run_id": "r1", "batch": "b1", "cost_usd": 1, "started": TS}])
        _rows(b, [anon])
        doc, err = self.spend(a, b)
        self.assertEqual(doc["runs_usd"], 5)                 # 4 once + 1, not 4 + 4 + 1
        self.assertEqual(doc["runs_rows_no_run_id"], 1)
        self.assertEqual(doc["runs_rows_deduped"], 1)

    def test_two_anonymous_rows_in_one_file_still_count_individually(self):
        a = os.path.join(self.tmp, "one.jsonl")
        row = json.dumps({"batch": "b1", "cost_usd": 2, "started": TS}, sort_keys=True)
        _rows(a, [row, row])
        doc, _err = self.spend(a)
        self.assertEqual(doc["runs_usd"], 4)
        self.assertEqual(doc["runs_rows_no_run_id"], 2)

    def test_the_same_run_id_in_two_batches_is_two_runs(self):
        a = os.path.join(self.tmp, "r.jsonl")
        _rows(a, [{"run_id": "r-t1", "batch": "b1", "cost_usd": 3, "started": TS},
                  {"run_id": "r-t1", "batch": "b2", "cost_usd": 5, "started": TS},
                  {"run_id": "r-t1", "batch": "b2", "cost_usd": 2, "started": TS}])
        doc, _err = self.spend(a)
        self.assertEqual(doc["runs_usd"], 8)                 # b1 3 + b2 max(5, 2)
        self.assertEqual(doc["runs_rows"], 2)
        self.assertEqual(doc["runs_rows_deduped"], 1)


if __name__ == "__main__":
    unittest.main()
