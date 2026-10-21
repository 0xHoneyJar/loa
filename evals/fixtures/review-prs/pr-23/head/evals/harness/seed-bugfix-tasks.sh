#!/usr/bin/env bash
# =============================================================================
# seed-bugfix-tasks.sh — cycle-130 bug-fix task seeder (SDD §5.14, Sprint 259 Task 2.2)
#
# Turns Loa fix commits into candidate bug-fix tasks for the ablation suite.
# Lists the commits since DATE whose subject starts with `fix` or `bug`, whose
# diff touched a test file (a path under a `tests/` directory, `test_*.py`,
# `*_test.py` or `*.bats`) and whose touched files all lie under the allowed
# roots; refuses by name any candidate touching .claude/, CLAUDE.md,
# .loa.config.yaml, grimoires/ or .run/ (a path component equal to one of
# those). For each selected candidate (the first N, newest first) it writes
# <out>/tasks/bugfix-NN/ (next free number):
#   fixture/    from the PARENT commit: the touched non-test files, the other
#               non-test files in their directories (the modules they most
#               likely use), the base version of each changed test, and the
#               test infrastructure the tests rely on (conftest.py up to the
#               root, __init__.py, *.bash and *helper* files beside each test,
#               root pytest.ini / pyproject.toml / setup.cfg / tox.ini) — a
#               plain tree, no .git
#   hidden/     tests/<path> = each added or changed test at the commit,
#               manifest.json {"files":[{src, dest}]}, reference.patch = the
#               commit's diff of the non-test files (a/ b/ prefixes, patch -p1)
#   task.yaml   source {kind: loa-history, fix_commit, base_commit, date};
#               grader_protected = the infrastructure files; regression_command
#               null; test_command = python3 -m pytest -q <test dirs> | bats <test dirs>
#   TASK.md     the subject line, the observed failure count, the test command;
#               never the diff, never a test name (the subject is sanitised:
#               no paths, file names, test names or the word for grader files)
# A task is built in a private temporary directory and moved into place only
# after its proof passed: the test command, with the hidden tests overlaid, is
# red at base and green with the reference patch, run on the host under
# `env -i PATH HOME=<fresh tmp> LC_ALL=C` plus PYTHONUSERBASE (the host's user
# base, so a user-site pytest is found) and PYTHONDONTWRITEBYTECODE=1, and
# evals/graders/no-secrets.sh passes on the whole task directory (a hit is a
# refusal). The selecting lead still rewrites TASK.md's observed behaviour and
# the criterion by hand before a task is frozen.
#
# Usage:
#   seed-bugfix-tasks.sh --since DATE [--select N] --out DIR [--repo DIR]
#                        [--paths CSV] [--suite-version N] [--dry-run]
#
#   --since DATE       YYYY-MM-DD; commits whose committer date is on or after it
#   --select N         tasks to materialise (default 4); refusals and skips do not
#                      count, a failed proof does
#   --out DIR          suite root; tasks go to DIR/tasks/<id>/
#   --repo DIR         git repository to read (default: this checkout)
#   --paths CSV        allowed roots (default tools,evals/harness,evals/graders,
#                      tests/unit,evals/tests); a mount-owned root is refused
#   --suite-version N  suite_version written to task.yaml (default 1)
#   --dry-run          list candidates, refusals and skips; write nothing
#   LOA_SEED_BATS      bats binary used for the proof when bats is not on PATH
#
# Output (stdout, one line each):
#   candidate <sha12> <date> <subject>
#   refused <sha12>: <path>                 (or: a secret pattern in the materialised task)
#   skipped <sha12>: <reason>
#   proof bugfix-NN <sha12>: red N failed / green M passed
#   proof-failed <sha12>: <reason>
#   wrote <dir>
#   seed-bugfix: C candidate(s), R refused, S skipped; selected X, written W, proof failed F
#
# Exit: 0 done (also when nothing qualified); 1 a selected candidate failed its
#       proof; 2 usage (bad option or date, not a git repository, bad --paths).
# Tested by evals/tests/seed-bugfix.bats.
# =============================================================================
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

usage() { sed -n '2,/^# =====.*$/p' "$0" | sed '1d;$d' | sed 's/^# \{0,1\}//'; exit "${1:-2}"; }
for a in "$@"; do [[ "$a" == "--help" || "$a" == "-h" ]] && usage 0; done
[[ $# -gt 0 ]] || usage 2
for tool in git python3; do command -v "$tool" >/dev/null 2>&1 || { echo "seed-bugfix: missing tool: $tool" >&2; exit 2; }; done

exec python3 -I "$SCRIPT_DIR/lib/seed_tasks.py" bugfix --repo-default "$REPO_ROOT" \
  --no-secrets "$REPO_ROOT/evals/graders/no-secrets.sh" "$@"
