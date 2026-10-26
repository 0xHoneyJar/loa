#!/usr/bin/env bash
# =============================================================================
# seed-refactor-tasks.sh — cycle-130 refactor task seeder (SDD §5.14, Sprint 259 Task 2.3)
#
# Turns Loa refactor commits into candidate refactor tasks for the ablation
# suite. Lists the commits since DATE whose subject starts with `refactor`,
# `chore`, `style` or `perf`, that touch at least two source files, all under
# the allowed roots, and NO test file (a path under a `tests/` directory,
# `test_*.py`, `*_test.py` or `*.bats`; such a commit is skipped with the
# reason); refuses by name any candidate touching .claude/, CLAUDE.md,
# .loa.config.yaml, grimoires/ or .run/. For each selected candidate (the
# first N, newest first) it writes <out>/tasks/<prefix>-NN/ (next free number;
# the prefix is `refactor`, or the --id-prefix given):
#   fixture/    from the PARENT commit: the touched source files, the other
#               non-test files in their directories (--fixture-scope roots: every
#               file under the allowed roots instead, as seed-bugfix-tasks.sh), the tests
#               under the allowed roots that name a touched file (its basename,
#               or a Python module's stem; at most 20), and their infrastructure
#               (conftest.py up to the root, __init__.py, *.bash and *helper*
#               files beside each test, root runner configs) — a plain tree;
#               a file of git mode 100755 keeps its executable bit
#   hidden/     reference.patch = the commit's diff (a/ b/ prefixes, patch -p1),
#               manifest.json {"files": []} until the structural check exists
#   task.yaml   source {kind: loa-history, fix_commit, base_commit, date,
#               churn: {files, insertions, deletions}} (git diff --numstat of
#               the commit); test_command = the covering tests; structural_check
#               null — the structural assertion is authored BY HAND (then listed
#               in manifest.json and set in structural_check; validate-suite.sh
#               refuses a refactor task without one); roots scope: test_command
#               names the covering test files and grader_protected adds every
#               file under a top-level fixture/tests/
#   TASK.md     the subject line and the test command; never the diff
# The proof — the fixture's own covering tests green at base AND green with
# the reference patch, run under `env -i PATH HOME=<fresh tmp> LC_ALL=C` plus
# PYTHONUSERBASE and PYTHONDONTWRITEBYTECODE=1 — and a clean
# evals/graders/no-secrets.sh scan come before the task is moved into place.
#
# Usage:
#   seed-refactor-tasks.sh --since DATE [--select N] --out DIR [--repo DIR]
#                          [--paths CSV] [--suite-version N] [--id-prefix P]
#                          [--fixture-scope touched|roots] [--rev REV] [--dry-run]
#
#   options as seed-bugfix-tasks.sh (--rev likewise; --select default 4; a commit without a
#   covering test is skipped and does not count; --id-prefix default refactor);
#   LOA_SEED_BATS likewise
#
# Output (stdout, one line each):
#   candidate <sha12> <date> <subject>
#   refused <sha12>: <path>
#   skipped <sha12>: <reason>          (touches a test file: <path> | touches N
#                                       source file(s), want at least 2 | …)
#   proof <prefix>-NN <sha12>: green at base (N passed) / green at reference (M passed)
#   churn <prefix>-NN: files F, insertions I, deletions D
#   todo <prefix>-NN: author the structural check …
#   proof-failed <sha12>: <reason>
#   wrote <dir>
#   seed-refactor: C candidate(s), R refused, S skipped; selected X, written W, proof failed F
#
# Exit: 0 done; 1 a selected candidate failed its proof; 2 usage.
# Tested by evals/tests/seed-refactor.bats.
# =============================================================================
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

usage() { sed -n '2,/^# =====.*$/p' "$0" | sed '1d;$d' | sed 's/^# \{0,1\}//'; exit "${1:-2}"; }
for a in "$@"; do [[ "$a" == "--help" || "$a" == "-h" ]] && usage 0; done
[[ $# -gt 0 ]] || usage 2
for tool in git python3; do command -v "$tool" >/dev/null 2>&1 || { echo "seed-refactor: missing tool: $tool" >&2; exit 2; }; done

exec python3 -I "$SCRIPT_DIR/lib/seed_tasks.py" refactor --repo-default "$REPO_ROOT" \
  --no-secrets "$REPO_ROOT/evals/graders/no-secrets.sh" "$@"
