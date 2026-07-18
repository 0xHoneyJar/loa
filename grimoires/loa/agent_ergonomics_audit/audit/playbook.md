# Agent-Ergonomics Playbook — loa pass 1 (top recommendations)

Pre-pass baseline (87 surfaces dual-scored so far): **median 550/1000**.
Worst dimensions: `intent_inference` **400**, `output_parseability` **460**,
`error_pedagogy`/`safety_with_recovery`/`self_documentation` **500**.
Intent stress: 40 wrong-but-legible invocations → **23 useful_hint,
17 useless_error, 0 recovered** (no typo inference exists anywhere).

Fable-verified anchor findings (all with live evidence): see
`phase0_scope_decision.md` §Seed findings + `recommendations.jsonl`.

## The narrative

loa's *newer* scripts (cycle-116+: verdict-derive, kf-write-lib,
classify-merge-pr) already practice good CLI hygiene — usage-on-bare, exit-2
contracts, `--help`. The debt clusters in three places:

1. **The highest-frequency surfaces are the worst offenders.** `loa-status.sh`
   (THE status surface) silently swallows unknown flags (`--jsno` → human
   prose, exit 0), ignores `NO_COLOR` and non-TTY, and has zero test coverage.
   `golden-path.sh` silently no-ops (exit 0, zero output) on every direct
   invocation shape an agent would try.
2. **Errors reject instead of teaching.** 17/40 wrong invocations produced
   bare `Unknown option: X` with no usage echo and no suggestion — including
   `beads-health.sh --help` ("Unknown option: --help"), a `$2: unbound
   variable` raw bash leak, and one crash with **zero output on both streams**.
   The educational-error helper (`lib/dx-utils.sh`) already exists and is used
   by none of them.
3. **Two live production incidents were ergonomics failures.** The
   FR-2-AMBIGUOUS hook message teaches a fix its own matcher rejects
   (hidden-dir gap, 2026-07-10); `classify-merge-pr.sh` misclassified the
   v1.196.0 release merge → wrong auto-tag requiring manual repair.

## Operator-stack mapping (skill §Operator Stacks)

| Stack | Recs |
|-------|------|
| C — Intent-Recovery Triad (⟁ 🩹 🚫) | R-001, R-008, R-009, R-010, R-012 |
| B — Output-Contract Quartet (🪧 🚦 🔢 🌐) | R-001, R-004, R-011 |
| D — Safety Pair (🛡 🩹) | R-002 |
| A — Mega-Command Triple (Σ 📜 📖 🧪) | R-006, R-007 |
| ① First-Try-Inevitability | R-003, R-005, R-013 |

## Ambition-bar coverage

- mega-command: **R-007** (`loa-status --triage --json`)
- capabilities/robot-docs: **R-006** (`loa-capabilities.sh --json`)
- `--json` on read-side: R-007 triage envelope (new read-side JSON)
- error rewrite naming exact fix: **R-002** (+R-008/R-009/R-010/R-012)
- intent-inference handler: **R-008** (did-you-mean, Levenshtein-1)
- dimensions touched: ≥6 of 11 across R-001..R-013

## Sequencing (Phase 5)

1. R-002 first (Fable-authored, security-sensitive, message+matcher+tests).
2. R-001, R-013 (worst high-frequency surfaces).
3. R-008 helper (lib/dx-utils.sh) then its 5 wirings; R-009, R-010, R-012 ride
   the same error-path idiom.
4. R-011 color guards (mechanical, 5 scripts, one commit).
5. R-003, R-004, R-005 (truthful health, truthful counters, truthful classify).
6. R-006, R-007 last (new surfaces composed from now-fixed parts).

Every commit: one rec, one bats regression test in `.claude/scripts/tests/`
(pointer manifest in `audit/regression_tests/`), suite run before commit.
Guardrail: exit codes and blocking decisions on security paths are
byte-preserved except where a rec explicitly re-specifies them (R-002 allows a
previously-blocked SAFE form; never the reverse).
