# Reviewer concerns — sprint-1 (PR: sprint-261 suite v2 + per-type run caps)

Scope: `pr/head.diff`, 12 files under `evals/`. Cite as `head/<path>:<line>`.

## Concerns found so far

1. `evals/harness/ablation-grade.sh:1074-1105` `remove_colliding` (grader 1.2.11) — the reserved
   basename set is every `.py` basename from the hidden overlay (not only test modules) plus every
   `.py` under the fixture's `tests/`/`test/` dirs (helper modules such as `helpers.py`, `_oracle_x.py`
   included). Any agent-added `.py` anywhere in the tree with a matching basename is deleted before
   grading, including package modules (`src/pkg/helpers.py`) that cannot collide under pytest's
   basename rule. Correct solutions can be graded as failing.
2. Same function: fixture walk excludes `__init__.py` but the overlay-derived set does not — an
   overlay containing an `__init__.py` makes every agent-added `__init__.py` removable.
3. Same function: directory overlays (`owned_dirs`) are protected from removal, but their contained
   `.py` basenames are never added to `reserved`, so collisions with those tests persist.
4. `evals/harness/run-ablation.sh:806` — codex horizon sums `watchdog_s` over the whole plan,
   including non-codex arms and (on --resume) already-rowed trials; refusal can be spurious on a
   nearly-finished resume.
5. `evals/tests/run-ablation.bats:93-97` — comment says A0 BARE stays 70 min and the 80-min derivation
   does not apply, then asserts 9600 s (= 80 min x 2).
6. Suite `suite_version: 2` and tests referencing `bugfix-v2-02` etc.; no task directories or
   MANIFEST.sha256 under grimoires/ are part of this diff — cannot verify the v2 tasks exist.
7. `seed-bugfix.bats:80`, `seed-refactor.bats:78` pass `--suite-version` to seed scripts that are not
   in the diff; cannot verify the flag exists.

## Areas that looked right

- `--types` jq fix (`.type as $t | ... | index($t)`), per-kind cap chain, resume reading caps from
  MANIFEST, RESERVE_CAP = max over plan kinds, `spend_charge`/`budget_gate` defaults preserved,
  pipeline-run.sh placeholder refresh token written with 0600 via fd, failure → rm + WARN.
