# Multi-Model Activation Reference (cheval substrate)

Full migration state, rollback model, and verification history for the cheval Python substrate. Moved out of `CLAUDE.loa.md`; the per-turn rules live there in compressed form.

## Multi-Model Activation (cycle-109 sprint-3)

The cheval Python substrate is the **unconditional** dispatch path for all
multi-model consumers (BB, Flatline orchestrator, Red-team pipeline,
adversarial-review, bridgebuilder-review, flatline-readiness,
red-team-model-adapter, post-pr-triage). The pre-cycle-109
`hounfour.flatline_routing` runtime flag is being phased out across the
T3.6→T3.7→T3.8 sequence.

| Status (cycle-109 sprint-3 state) | BB | Flatline | Red-team |
|---|---|---:|---:|
| **Post-T3.6 (commit C — current)** | cheval (unchanged) | cheval (unconditional) | cheval (unconditional) |
| **Post-T3.7 (commit D — gated by C109.OP-S3)** | cheval | cheval | cheval (legacy file DELETED) |
| **Post-T3.8 (commit E)** | cheval | cheval | cheval (`hounfour.flatline_routing` flag REMOVED) |

BB has used `ChevalDelegateAdapter` unconditionally since cycle-103 PR #846.
Cycle-109 T3.6 (commit C, this sprint) removed the conditional branches at
the FL orchestrator + model-adapter main() entrypoints; cheval is now
operator-facing unconditional. Mock-mode delegation at model-adapter.sh:519-526
remains until T3.7 + T3.8 land mock-mode migration under operator approval.

All consumers benefit from:
- **Chain-walk**: cheval walks the within-company `fallback_chain` (e.g. gpt-5.5-pro → gpt-5.5 → gpt-5.3-codex → codex-headless) on retryable errors (EmptyContent, RateLimited, ProviderOutage, RetriesExhausted).
- **Voice-drop**: when a voice's chain exhausts, flatline-orchestrator DROPS that voice from consensus instead of substituting another company's model. Audit log: `consensus.voice_dropped`.
- **MODELINV v1.3 envelope**: per-invocation audit record at `.run/model-invoke.jsonl` with `final_model_id`, `transport`, `config_observed`, `models_failed[]`, `models_requested[]`, `capability_evaluation`, `verdict_quality`.
- **Verdict-quality envelope** (cycle-109 Sprint 2): every substrate output carries a `verdict_quality` envelope describing voices succeeded/dropped, chain health, blocker_risk, confidence floor, rationale. `status: clean | APPROVED` is definitionally impossible when verdict quality is degraded (NFR-Rel-1).

### Rollback (cycle-109 model)

**There is no runtime-flag rollback path post-cycle-109.** The
`hounfour.flatline_routing` flag is being removed in T3.8 because the
legacy adapter it gated is being deleted in T3.7 under explicit
operator-approval marker C109.OP-S3. Once Sprint 3 lands on main, the
canonical rollback path is:

  **`git revert` of the cycle-109 sprint-3 merge commits.**

A full rollback runbook lives at
`grimoires/loa/runbooks/cycle-109-rollback.md` — covers per-commit revert,
config restoration, baseline comparison against
`grimoires/loa/cycles/cycle-109-substrate-hardening/baselines/legacy-final-baseline.json`,
and CI re-validation. Operators do NOT need to flip a runtime flag; they
revert.

### Verification (cycle-107 sprint-1 + cycle-109 sprint-2/3 cumulative)

- FL 3-model run: 549s, 3 voices' MODELINV envelopes recorded, chains populated, all primaries succeeded
- RT review: 1 MODELINV envelope, cheval audit signature confirmed
- BB: verified via cycle-104 sprint-3 T3.4 (4/4 trials at 297-539KB clean)
- **cycle-109 Sprint 2**: 234 new tests; verdict-quality envelope wired through 7/7 IMP-004 consumers; 5 canonical regression fixtures (#807/#809/#823/#868/KF-002 PRD-review) locked in conformance matrix.
- **cycle-109 Sprint 3 progress**: T3.1 matrix scaffold + T3.2-T3.5 Cluster B fixes (#864/#863/#793/#820) + T3.6 feature-flag removal + T3.10 activation regression CI workflow. 810-cell matrix wired into `.github/workflows/activation-regression.yml`.
