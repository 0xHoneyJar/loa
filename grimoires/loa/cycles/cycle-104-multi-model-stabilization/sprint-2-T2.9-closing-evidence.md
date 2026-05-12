---
schema_version: 1.0
from: opus-4-7-cycle-104-sprint-2-T2.9-closer
to: cycle-104-archive
topic: sprint-2-T2.9-closing-evidence
status: ready
provenance:
  cycle: cycle-104-multi-model-stabilization
  sprint: sprint-2
  task: T2.9
  date: 2026-05-12
tags: [cycle-104, sprint-2, T2.9, code_review-revert, KF-003-closure]
---

# Cycle-104 Sprint 2 T2.9 — Closing Evidence

## Decision

**Revert `flatline_protocol.code_review.model` (and `security_audit.model`)
from `claude-opus-4-7` back to `gpt-5.5-pro`.**

The cycle-102 Sprint 1B T1B.4 swap is retired. The chain is the new
absorption primitive.

## Why now (the SDD R8 gate)

SDD R8 gated T2.9 on T2.10 evidence that the chain absorbs KF-003.
T2.10 ran clean (25/25 trials, 2026-05-12, zero KF-003 surfaces).
That outcome ALONE didn't unblock T2.9 — "we couldn't measure
absorption because the failure didn't happen" is not the same as
"absorption was measured high."

The unblock comes from combining T2.10 with the **fault-injection
test that was already green from sprint-2 T2.5+T2.6**. That test
mocks the primary to return `EmptyContentError` and asserts the
chain walks to the next entry. It proves the ABSORPTION MECHANISM
under synthetic conditions, while T2.10 proves the FAILURE CLASS is
currently rare/absent at OpenAI.

The combination is sufficient for the revert:

- **Architecture works** (fault-injection green) → if KF-003 happens,
  the chain catches it.
- **Failure is rare** (T2.10 25/25 clean) → the workaround was costing
  cross-model dissent diversity without much current upside.

If KF-003 returns at scale, the chain absorbs it. If it returns AND
the chain exhausts, T2.8 voice-drop keeps consensus available with
the remaining voices. Worst-case behavior is no worse than the
pre-T1B.4 state.

## Files changed

`.loa.config.yaml` (operator-local; gitignored):

```diff
-    # cycle-102 Sprint 1B T1B.4 (2026-05-09): swapped from gpt-5.5-pro to claude-opus-4-7. ...
-    model: claude-opus-4-7
+    # cycle-104 Sprint 2 T2.9 (2026-05-12): REVERTED to gpt-5.5-pro per SDD R8. ...
+    model: gpt-5.5-pro

# Same revert applied to security_audit.model (shared T1B.4 rationale).
```

Note: `.loa.config.yaml` is gitignored, so this revert is operator-local
only. Other operators with cycle-102-era local configs should mirror the
revert per the rationale in `.loa.config.yaml`'s new inline comment.

## Closing-evidence test artifacts (already shipped, this commit references them)

| Artifact | Purpose | Sprint origin |
|----------|---------|---------------|
| `.claude/adapters/tests/test_chain_walk_audit_envelope.py::test_primary_empty_content_walks_to_fallback` | Fault-injection: mocked primary EMPTY_CONTENT → chain walks to fallback (PASS) | Sprint 2 T2.5+T2.6 (`5bb606fe`) |
| `.claude/adapters/tests/test_chain_walk_audit_envelope.py::test_chain_exhausted_when_every_entry_fails` | All entries EMPTY_CONTENT → CHAIN_EXHAUSTED (exit 12) (PASS) | Sprint 2 T2.5+T2.6 |
| `grimoires/loa/cycles/cycle-104-multi-model-stabilization/sprint-2-replay-corpus/kf003-results-20260512T041527Z.jsonl` | T2.10 25-trial live replay; 25/25 primary-success, 0 KF-003 surfaces | Sprint 2 T2.10 (`18379643`) |

## What if KF-003 returns?

Three layers of defense, in order:

1. **Within-company chain walk** — `gpt-5.5-pro → gpt-5.5 → gpt-5.3-codex → codex-headless`. If primary empties, walk continues until one entry succeeds or all exhaust.
2. **Voice-drop on chain exhaust** — if the entire OpenAI chain exhausts, T2.8 drops that voice from consensus rather than substituting a different company's model. The drop emits `consensus.voice_dropped` to the trajectory log.
3. **`LOA_HEADLESS_MODE=prefer-cli`** — operator override that promotes `codex-headless` (CLI subscription, no HTTP empty-content failure class) to the front of the chain.

The cycle-102 workaround `model: claude-opus-4-7` did none of these — it was a brittle single-point swap. The revert moves the absorption responsibility from operator config (one swap per failure class) to the chain (one mechanism for many failure classes).

## Status

**T2.9 CLOSED 2026-05-12.** Cycle-104 sprint-2 substantive scope is now
14/14 tasks shipped (was 13/14 with T2.9 as the carry-over).

KF-003 attempts row in `known-failures.md` updated to reference this
closing-evidence document.

🤖 Generated as part of cycle-104 sprint-2 T2.9 closure, 2026-05-12.
