All good

# Sprint 261 review — round 3 (cycle-130 Sprint 4) — APPROVED

**Reviewer:** Senior Technical Lead (Claude Fable 5.1, `global.anthropic.claude-fable-5-1`)
**Date:** 2026-10-18 (2026-10-18T10:27:39Z)
**Implementation:** `4434d450..631d628f` (round 3: grader 1.2.13 `631d628f` by implementer G2, `reviewer-g2.md`; the pre-flight round-3 refinements `2036083f` by implementer P2, `reviewer-p2.md`; DEC-0599 `498f72ed`). Rounds 1 and 2 archived as `engineer-feedback-r1.md` and `engineer-feedback-r2.md`.
**Dissent:** the sprint's three runs are spent — run 1 (review, 6 findings) and run 2 (review on the round-2 fixes, 6 findings) all accepted and closed; run 3 is the audit (`adversarial-audit.json`, the full harness-only sprint diff `4434d450..631d628f`, 22 files / 4,598 lines; status `clean`, two voices). Round 3 is therefore verified by the lead directly, reading the two patches against their briefs and the dissent findings they close, and by the audit dissent on the final code.
**Local checks:** `evals/tests/` **430/430** on `631d628f`; `ablation-grade.bats` 44/44, `run-ablation.bats` 42/42 in isolation; the official image self-check **36/36 under grader 1.2.13** (`self-check-image-v2-grader-1.2.13.log`); the blind re-grade of every run directory under 1.2.13 (`~/.cache/loa/cycle-130/regrade-1213/summary.txt`): 132 v1 + 24 + 9 v2 run directories identical to the inline grades on every key, `colliding_tests_removed` 0 on all 165, the only new keys being the additive `collision_rule` (and `heredoc_interpreters` on v1).

## Round 2 items

- **MEDIUM-1 closed** (1.2.13: protected and candidate modules compared by pytest import name under prepend mode — the dotted path from the first ancestor without `__init__.py`; AG-41: the packaged pair `pkg.test_x` removed, `other.test_x` kept; the implementer confirmed the physics with pytest 9.0.2 in a scratch directory).
- **MEDIUM-2 closed** (`required_until = now + 2 × max(Σ w / concurrency, max w)`; RAB-39 at concurrency 3 with one trial of 16,800 s; RAB-30's expected horizon moved from 17,600 s — the bug — to 33,600 s).
- **MEDIUM-3 closed** (`CODEX_PF_JSON`, `null` before pre-flight 6, passed by `--argjson` to `write_manifest` and `write_status`; P2 listed every call site: all after the pre-flight, the trap armed after the first write; RAB-40 reproduces the reachable case — the scratch directory gone before a later write — and asserts STATUS.json stays valid with `state partial`).
- **LOW-1 closed** (`rerun_pending` counted minus `--rerow` ids; RAB-41; the superset is documented as the safe direction).
- **LOW-2 closed** (`python_files` from `-o`/`-c` in `test_command`, else `pytest.ini`, `.pytest.ini`, `pyproject.toml` via tomllib, `tox.ini`, `setup.cfg` in pytest's order; `grade.json collision_rule {python_files, source}`; AG-43/AG-44).
- **LOW-3 closed** (a package-less agent helper whose stem equals a protected sibling module's is removed together with the unowned collectable modules of its directory, only when that directory holds a collectable test module; AG-42 — the lead accepts G2's DECISION that removing the helper alone would turn an agent test's import into a collection-aborting ImportError, which pytest 9.0.2 confirmed).

## Lead verification of round 3

- The 1.2.13 rule is pytest's own: import names computed on the overlay-or-fixture view for protected modules and on the tree's real `__init__.py` files for candidates; owned paths (overlay dests, directory-overlay contents, fixture paths) are never candidates; `__init__.py` and `conftest.py` are never reserved; the helper rule needs three conditions (package-less, protected helper reachable by bare import, a collectable test module beside the candidate). Limitations stated by G2 (an agent `__init__.py` that changes a protected module's real import name; package-name shadowing) are recorded here as accepted gaps for a future grader, not blockers: no frozen hidden dest is packaged and no agent run produced such a shape (165 re-grades, 0 removals).
- The pre-flight's horizon, writer and counting changes are bounded (26 + 73 lines) and each carries a case that fails on the pre-fix script; the refusal text names the rule; nothing secret is printed (RAB-35's dummy key check still holds).
- Fairness: the grader changes affect only agent-added files that would abort pytest collection or shadow a protected import; the self-check and the re-grade show no effect on any recorded row; the arms were never read by the re-grade.
- Security: no `eval` with `$`, no `.claude/` sourcing, no secret in argv or logs, host credential never written.

## Acceptance criteria (AC-4.1 … AC-4.9)

Met as evidenced in `reviewer.md` (finalised at close) and `reads-v2.md`: the pre-registration timestamps precede their rows (AC-4.1); the dry-run MANIFEST fields including the per-type caps, `suite_version` 2, the manifest hash and `codex_token_exp` (AC-4.2); the self-check 36/36 and sixteen REVIEW.md PASS (AC-4.3); the hardness criterion's two rounds and the cap-fit reads recorded (AC-4.4); every v2 row carries `attempts`, `suite_version` 2 and the manifest hash, 165 rows validate (AC-4.5); `reads-v2.md` records H1 and A4 with intervals and the action under both the halt (DEC-0592) and the continuation (DEC-0597) (AC-4.6).

## Verdict

APPROVED — Sprint 261 proceeds to the security audit (dissent run 3 of 3, `--type audit`, on the full sprint diff; its envelope is already in `adversarial-audit.json`).

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"excluded":0,"sprint_id":"sprint-261","ts":"2026-10-18T10:27:39Z"} -->
