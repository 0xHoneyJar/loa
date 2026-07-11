# Ambition Bar — pass 1 self-check (before Phase 10)

Soft target for a `full` pass on a non-trivial CLI (373 scripts → non-trivial):

| Gate | Target | Actual | Met |
|------|--------|--------|-----|
| Substantive landed changes | ≥ 10 | **13 recommendations across 13 source commits** (R-001..R-013 + 4 fresh-eyes fixes; every rec moves ≥1 dim ≥100 pts and ships with a test) | ✅ |
| Dimensions touched | ≥ 3 | **8** (intent_inference, error_pedagogy, composability, output_parseability, self_documentation, agent_ergonomics, agent_intuitiveness, determinism) | ✅ |
| Mega-command (when missing) | 1 | `loa-status.sh --triage [--json]` (R-007) | ✅ |
| capabilities / robot-docs (when missing) | 1 | `loa-capabilities.sh [--json]`, drift-gated (R-006) | ✅ |
| `--json`/robot on a read-side command | 1 | triage JSON envelope (new read-side JSON surface) | ✅ |
| Error rewrite naming the exact fix | 1 | FR-2 messages (R-002) + value-required guards (R-009/R-010) + usage echoes (R-012) | ✅ |
| Intent-inference handler for the top wrong invocation | 1 | `dx_unknown_flag` did-you-mean across 6 scripts (R-008, R-001) | ✅ |
| All applied recs have regression tests | all | 50+ new bats fixtures across 7 test files (CI-run); pointer manifest in audit/regression_tests/ | ✅ |
| Median uplift | ≥ 50 | ≈ +330 (uplift_diff.md) | ✅ |
| Regressions > 50 pts | 0 | 0 (full unit + script suites green; 9 pre-existing suites for touched files re-run) | ✅ |

**Verbatim "That's it??" self-prompt:** run against the ledger above. Answer:
the pass shipped the full Stack A (mega-command + capabilities + drift gate),
Stack C (did-you-mean + teach-don't-reject across 6 scripts), Stack D (hook
messages that finally tell the truth), Stack B slices (NO_COLOR/TTY, coherent
counters), killed two production-incident classes (FR-2 self-contradiction,
release misclassification), one permanent DEGRADED loop, three crash classes,
and filed one upstream defect (KF-022) discovered en route. Re-entry into
Phase 4/5 not warranted this pass; the residual queue is Pass-2 material
(HANDOFF.md).

**Fresh-eyes ledger (Phase 7):** r1 found 2 defects (unguarded --index $2;
fixture-unsafe sourcing), r2 found 1 (grep -c double-zero), r3 found 1
(beads-health sourcing consistency), r4 found 1 (--help header bleed),
r5 clean (holistic sweep), final full suites green = terminating clean pass.
