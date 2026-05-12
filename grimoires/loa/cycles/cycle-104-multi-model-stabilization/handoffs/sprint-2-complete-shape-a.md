---
schema_version: 1.0
from: opus-4-7-cycle-104-sprint-2-e-g-continuator
to: cycle-104-sprint-2-pr-merge-operator
topic: sprint-2-complete-shape-a
status: ready
provenance:
  cycle: cycle-104-multi-model-stabilization
  sprint: sprint-2
  predecessor_pr: 849
  branch: feature/cycle-104-sprint-2-fallback-chains-headless
  commits: [241c703e, 42857c72, 7f9d7bbe, 5bb606fe, e3023d27, 7fca3be8, bd7edec9, ddf525a2, 2fd5749d]
last_updated: 2026-05-12T13:35:00Z
tags: [cycle-104, sprint-2, shape-a, e-g-complete, operator-review]
---

# Cycle-104 Sprint 2 — substantive scope COMPLETE (Shape A) → operator-merge window

## TL;DR

Shape A continuation landed Group E (partial — T2.8 voice-drop) + Group G
(T2.12 runbooks + T2.13 parity test + T2.14 dead-env-var removal) on
`feature/cycle-104-sprint-2-fallback-chains-headless`. 10/14 sprint
tasks shipped across 9 commits. Branch ready for review/merge to main.

The remaining 4 tasks are **operator-gated only** — they require
infrastructure (live API budget, CLI binaries on PATH) that the
autonomous run cannot provide.

## Group / task status table (final)

| Group | Tasks | Status | Commits |
|-------|-------|--------|---------|
| A — Routing substrate | T2.1 chain_resolver + T2.2 capability_gate | ✅ SHIPPED | `241c703e` |
| B — Config layer | T2.3 fallback_chain + T2.4 headless aliases | ✅ SHIPPED | `42857c72` |
| C — Integration | T2.5 cheval.invoke + T2.6 MODELINV v1.1 | ✅ SHIPPED | `5bb606fe` |
| D — Operator control | T2.7 hounfour.headless.mode + cheval consumption | ✅ SHIPPED | `7f9d7bbe` + `5bb606fe` |
| **E — Cross-company repurpose** | **T2.8 voice-drop wiring** | ✅ **SHIPPED this resume** | **`7fca3be8`** |
| E — code_review revert | T2.9 — gated on T2.10 R8 | ⏸ DEFERRED | — |
| F — Empirical + e2e | T2.10 KF-003 replay + T2.11 cli-only e2e | 🚫 OPERATOR-GATED | — |
| **G — Docs + cleanup** | **T2.12 runbooks + T2.13 parity + T2.14 env-var removal** | ✅ **SHIPPED this resume** | **`bd7edec9` + `ddf525a2` + `2fd5749d`** |

10/14 substantive tasks shipped. 4 tasks remain (T2.9, T2.10, T2.11
operator-gated; T2.12 done).

## What this resume delivered

### T2.8 — voice-drop wiring (Group E)

Repurposes `flatline_protocol.models.{secondary, tertiary}` cross-
company defaults per SDD §6.5: when a voice's within-company chain
exhausts (cheval exit 12 = `CHAIN_EXHAUSTED`), the flatline
orchestrator DROPS the voice from consensus rather than substituting
another company's model. The cycle-102 T1B.4 cross-company-swap
anti-pattern is structurally retired.

- `.claude/scripts/lib/voice-drop-classifier.sh` — pure classifier
  (success / dropped / failed); `--self-test` passes
- `.claude/scripts/flatline-orchestrator.sh` — `emit_voice_dropped`
  helper + Phase 1 / Phase 2 wait-loop classification + all-voices-
  unavailable diagnostic distinguishing failed vs chain-exhausted
- `tests/unit/voice-drop-classifier.bats` (11 tests)
- `tests/integration/flatline-orchestrator-voice-drop.bats` (6 tests)
  — VDO-T6 pins that exit 11 (NO_ELIGIBLE_ADAPTER) NEVER silently
  drops — config errors must surface

### T2.12 — runbooks (Group G)

Three operator runbooks linked from `.loa.config.yaml.example`:

- `grimoires/loa/runbooks/headless-mode.md` — 4 modes + when-to-use +
  voice-drop section
- `grimoires/loa/runbooks/headless-capability-matrix.md` — feature ×
  adapter table + capability-gate behavior
- `grimoires/loa/runbooks/chain-walk-debugging.md` — `LOA_HEADLESS_VERBOSE`
  stderr contract + MODELINV envelope jq queries + 5 common
  diagnostic patterns

### T2.13 — cross-runtime parity (Group G)

Three YAML readers (bash yq+jq, Python PyYAML, Node `yaml` package)
emit byte-equal canonical JSON for every `kind: cli` adapter entry in
`model-config.yaml`. Catches the silent-drift class where a future
runtime parser would silently mishandle the new `kind` discriminator.

`tests/integration/kind-cli-cross-runtime.bats` — 6 tests including
all-three-aliases-present (claude/codex/gemini), non-empty capabilities
arrays, and NO pricing block (CLI bills against operator subscription).

### T2.14 — LOA_BB_FORCE_LEGACY_FETCH removal (Group G)

The env-hatch's rollback target (the legacy fetch path) was already
gone after cycle-103. The hatch only produced a guided-rollback
message and carried no actual rollback capability — removing it is
non-functional pruning.

- `cheval-delegate.ts` constructor check + companion test removed
- `dist/` regenerated via `npm run build`; drift gate passes
- `entry.sh` TODO updated to drop the dead gate-1 reference

## Test deltas this resume

| Suite | New tests | Pass | Pre-existing failures |
|-------|-----------|------|----------------------|
| `tests/unit/voice-drop-classifier.bats` | 11 | 11/11 | — |
| `tests/integration/flatline-orchestrator-voice-drop.bats` | 6 | 6/6 | — |
| `tests/integration/kind-cli-cross-runtime.bats` | 6 | 6/6 | — |
| BB cheval-delegate tsx tests | (−1) | 34/34 | — |
| **Resume total** | **+23 / −1 = +22** | **all green** | — |
| Cumulative sprint-2 | 91 | all green | 3 (`test_flatline_routing.py` per Group C handoff) + 1 (BB `persona.test.ts` rate-limit + retry mock, pre-existing on HEAD) + 1 (`flatline-orchestrator-max-tokens.bats:140` legacy warning string drift, pre-existing) |

`.claude/adapters pytest`: **1184 passed**, **3 pre-existing failures**
(`test_flatline_routing.py::TestModelAdapterShim::test_shim_legacy_mock_mode`,
`test_feature_flag_toggle`, `TestValidateBindingsCLI::test_validate_bindings_includes_new_agents`).
All 3 documented in Group C handoff as pre-existing on HEAD.

## What's left (all operator-gated)

| Task | Gate | Action needed |
|------|------|---------------|
| **T2.9** code_review revert (`flatline_protocol.code_review.model` → `gpt-5.5-pro`) | Per R8: depends on T2.10 KF-003 evidence that the chain absorbs EMPTY_CONTENT | **STAYS GATED — T2.10 ran clean (no KF-003 surfaces) so the chain's absorption rate is unmeasured.** Either refresh the prompt corpus to real-document shape OR write a fault-injection alternative test (mock primary → EMPTY_CONTENT). |
| **T2.10** KF-003 chain replay (live API) | `LOA_RUN_LIVE_TESTS=1` + ≤$3 budget approval | ✅ **EXECUTED 2026-05-12.** 25/25 trials all succeeded on primary; zero KF-003 surfaces. ~$2.50 spent. KF-003 may be provider-side fixed at OpenAI; see KF-003 row in `known-failures.md` for full evidence. |
| **T2.11** cli-only zero-API-key e2e | `claude` / `codex` / `gemini` CLI binaries on `$PATH` + strace available | ✅ **EXECUTED 2026-05-12.** Surfaced a real 2-layer architecture gap (adapter routing + cli_model translation); both fixed in commit `5d0dca8f`. T2.11-3 audit-envelope cross-check passes (load-bearing structural proof); T2.11-1/T2.11-2 skip on hardened kernel (`ptrace_scope=2`). |

## PR readiness

Branch state on `feature/cycle-104-sprint-2-fallback-chains-headless`:

```
2fd5749d test(cycle-104 sprint-2 T2.13): cross-runtime parity for kind:cli adapter entries
ddf525a2 docs(cycle-104 sprint-2 T2.12): headless mode + chain-walk debugging runbooks
bd7edec9 feat(cycle-104 sprint-2 T2.14): remove LOA_BB_FORCE_LEGACY_FETCH dead env var
7fca3be8 feat(cycle-104 sprint-2 T2.8): voice-drop wiring in flatline-orchestrator
e3023d27 docs(cycle-104 sprint-2): group-c handoff + NOTES decision log + run state HALTED
5bb606fe feat(cycle-104 sprint-2 T2.5+T2.6): cheval chain walk + MODELINV v1.1
7f9d7bbe docs(cycle-104 sprint-2 T2.7-partial): hounfour.headless.mode example + partial handoff
42857c72 feat(cycle-104 sprint-2 T2.3+T2.4): populate fallback_chain + headless aliases
241c703e feat(cycle-104 sprint-2 T2.1+T2.2): within-company chain_resolver + capability_gate
```

9 commits above main. No divergence. Predecessor PR #849 (sprint-1)
still OPEN + MERGEABLE — sprint-2 PR will need #849 to merge first or
be retargeted at #849's head.

## Iron-grip gate reminders for the merge-operator

- **AC-2.1 lint + T2.5/T2.6/T2.8 contract tests are now load-bearing**.
  Any future edit to `model-config.yaml` / `cheval.cmd_invoke` /
  `flatline-orchestrator.sh`'s wait loops must keep these green:
  - `pytest .claude/adapters/tests/test_model_config_fallback_chain_invariants.py test_chain_walk_audit_envelope.py test_modelinv_envelope_chain_walk.py`
  - `bats tests/unit/voice-drop-classifier.bats tests/integration/flatline-orchestrator-voice-drop.bats tests/integration/kind-cli-cross-runtime.bats`
- **Don't refactor retry.py.** Chain walk catches `EmptyContentError`
  at the right layer (SDD §10 Q6).
- **Cross-company substitution is structurally retired.** Re-introducing
  it would regress voice-drop and invite the cycle-102 T1B.4 failure.

## Risks observed but not realized this resume

| Risk | Status |
|------|--------|
| Voice-drop wiring regresses partial-tolerance for Phase 1 | Mitigated — VDO-T1 / VDO-T6 pin that 1 drop + 1 success exits 0 |
| Cross-runtime parity test fails on a future YAML parser update | Mitigated — byte-equal assertion catches drift at CI time |
| T2.14 removal breaks operators relying on guided rollback | Mitigated — the rollback target was already gone; operators received an error pointing to docs, nothing more |
| Run state corrupted by accidental stash pop during testing | **Realized + recovered** — `git stash pop` accidentally popped stash@{0} (unrelated cycle-095 work). Recovered via `git restore HEAD --` on the conflict set. Stash@{0} kept per git's note ("entry kept in case you need it again"). No commits lost. See related NOTES.md addition under `.claude/rules/stash-safety.md` heuristic. |

---

**Status**: READY. Sprint-2 substantive scope shipped end-to-end on
this branch. Awaiting operator review window for PR + Group F unblock.

🤖 Generated as part of cycle-104 Sprint 2 E+G continuation run, 2026-05-12
