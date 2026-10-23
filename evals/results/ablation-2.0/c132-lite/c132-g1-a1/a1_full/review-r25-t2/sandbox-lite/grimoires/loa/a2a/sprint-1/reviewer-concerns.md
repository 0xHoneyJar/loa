# Reviewer concerns — sprint-1 (PR: sprint-261 suite v2 + per-type run caps + KF-048 + grader 1.2.11)

Scope: `pr/head.diff` — evals/harness/{ablation-grade.sh, lib/arms-common.sh, pipeline-run.sh, run-ablation.sh}, evals/suites/ablation-2.0.yaml, evals/tests/*.bats, the pipeline stub.

## Concerns found so far (Phase 2)

1. `ablation-grade.sh` `remove_colliding` (1.2.11) is broader than the pytest failure it fixes. `reserved` holds every `.py` basename under the fixture's `tests/`/`test/` dirs (helpers, `_oracle_x.py`, …) and every overlay `.py` basename, and any agent-added `.py` anywhere in the tree with that basename is unlinked. pytest only collides on collected test modules (`test_*.py`, `*_test.py`, conftest) in package-less dirs; a `src/pkg/helpers.py` beside a fixture `tests/helpers.py` is fine for pytest but the grader deletes it and the agent's package breaks. Verified empirically.
2. Same function: overlay basenames are not filtered for `__init__.py` (fixture walk is), so an overlay `tests/__init__.py` would make every agent-added package `__init__.py` a removal target.
3. Same function: directory overlays (`os.path.isdir(f)`) contribute nothing to `reserved`, so a collision with a file inside a directory overlay is not fixed.
4. `run-ablation.sh` codex pre-flight on `--resume`: `codex_arms` is derived from the whole recorded plan, so a resume that only re-rows (`--rerow`) or resumes a completed batch is refused on an expired token although no pipeline call would run.
5. `uses_codex` treats every arm with `loa_mount != false` as codex-using; arms without gates (a4_no_gates) never run the dissent, so a4-only batches are refused needlessly.
6. RAB-1 comment contradicts its own assertion (says A0 BARE stays 70 min, asserts 9600 s = 80 min × 2).
7. Seed tests pass `--suite-version` to seed scripts that are not in the diff; validate-suite/RAB tests reference `bugfix-v2-*` tasks and MANIFEST.sha256 under grimoires/ that are not in the diff — unverifiable here.

## Things checked and found OK
- `--types` jq fix precedence; cap chain (`--run-cap` > suite per-kind > config > suite run_usd > 12); resume reads caps from MANIFEST; reserve = max cap over plan kinds; `spend_charge`/`budget_gate` keep RUN_CAP defaults for other callers; auth.json placeholder written 0600 with host file untouched; no token value in refusal/argv.
