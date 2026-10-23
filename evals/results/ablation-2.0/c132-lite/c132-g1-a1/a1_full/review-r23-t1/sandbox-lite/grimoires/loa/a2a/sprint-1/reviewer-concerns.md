# Reviewer concerns — sprint-1 (PR: sprint-259 grader + seeders)

Scope: pr/head.diff (16 files under evals/). Cite as head/<path>:<line>.

Concerns found in the first pass, for the dissenting voice to confirm or refute:

1. head/evals/tests/ablation-grade.bats:16 — BATS_BIN is a hard-coded personal path
   ($HOME/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats); the symlink made at :48 dangles
   on any other machine, so AG-2 (bf-sh) and AG-7 (bats TAP) cannot pass outside the author's box.
2. head/evals/harness/lib/seed_tasks.py:457 — refactor tasks leave the covering tests
   (the "suite stays green" oracle) editable by the agent: only conftest/helpers are grader_protected
   and hidden/manifest.json is empty, so weakened assertions grade green. SR-1 (:92) locks it in.
3. head/evals/harness/lib/seed_tasks.py:570 vs the wrapper headers (seed-refactor-tasks.sh:115-116,
   seed-bugfix-tasks.sh:43-44): build-time skips (no covering test) and refusals (secret) consume a
   --select slot; fewer than N tasks are written while exit is 0.
4. head/evals/harness/ablation-grade.sh:710-714 — tarfile.data_filter / extractall(filter=) need
   Python >= 3.11.4; on 3.11.2 every snapshot extraction raises and the grade exits 2. No guard.
5. head/evals/harness/ablation-grade.sh:1122-1130 — refactor verdict_accuracy uses the covering
   suite only (green at base by construction), never the structural check: CHANGES_REQUIRED on an
   untouched tree is scored wrong.
6. head/evals/harness/lib/seed_tasks.py:196-198 — pytest counts read only the last line of
   stdout+stderr; a trailing stderr line (warning) zeroes the counts and fails the proof.
7. Report/diff mismatch: PR.md describes sixteen tasks under grimoires/loa/evals/ablation-2.0/tasks/
   and a freeze; neither is in the diff.

Please look especially for: off-by-one in citation windows (ablation-grade.sh:900-912), id ordering
(:583-594, :617-621), the regression newly_failing logic (:1091-1095), and anything in the
seed-corpus generated-path rule (seed-corpus-from-record.sh:202-213, :235-236, :709-713).
