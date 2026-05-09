# cycle-102 Resumption — Brief K (paste-ready handoff)

> Cycle-102 (Loa Model-Integration FAANG-Grade Stabilization) kickoff complete:
> PRD + SDD + sprint plan all landed and Flatline-amended. This document is the
> paste-ready brief for the fresh session that picks up at /implement Sprint 1.

## Quick state (1-screen briefing)

- **Active cycle**: `cycle-102-model-stability` (per `.run/sprint-plan-state.json` + `grimoires/loa/ledger.json`).
- **Predecessor closed**: `cycle-099-model-registry` (its `#710` endgame absorbed into cycle-102 Sprints 2-4).
- **Thesis** (vision-019): silent degradation is the bug. Every model failure must be (typed → operator-visible → graceful-fallback-with-WARN). Rollback is a workaround with a deadline.
- **5 sprints** scoped in `sprint.md`, 41 tasks, 8 cycle-exit invariants (M1-M8). Hard ceiling 12 weeks.
- **Sprint 1 first task**: `T1.1` — author `model-error.schema.json` (typed-error taxonomy: 9 error_class enum values).

## Critical artifacts

```
grimoires/loa/cycles/cycle-102-model-stability/
├── prd.md                         # 36KB; PRD with 15 operator decisions + Flatline iter-1 amendments
├── sdd.md                         # 74KB; SDD with 15 ASSUMPTION tags + Flatline iter-1 amendments
├── sprint.md                      # 74KB; 41 tasks; Flatline iter-1 amendments
├── flatline-prd-review-v1.md      # PRD adversarial synthesis (4-of-6 voices)
├── flatline-sdd-review-v1.md      # SDD adversarial synthesis (3-of-4 voices; A7 bug skipped opus-skeptic)
├── flatline-sprint-review-v1.md   # sprint adversarial synthesis (2-of-2 voices; cost discipline)
├── flatline-prd-degradation.md    # forensic record of orchestrator silent-degradation
├── flatline-{prd,sdd}.log         # orchestrator transcripts (degraded each time)
└── flatline-{prd,sdd,sprint}-direct/  # raw model outputs, full provenance
```

## What was caught by iron-grip Flatline dogfooding (4 rounds, ~$5-8 cumulative)

**5 BLOCKER design defects** — all integrated into PRD/SDD/sprint:

1. **PRD-B1** — L1 strict failure-as-non-zero contradicted AC-3.2 graceful fallback (gemini CRIT 900 + opus HIGH 700). Refactored: successful fallback = exit 0 + WARN; chain exhaustion = exit non-zero + typed BLOCKER.
2. **PRD-B2** — Probe gate semantics underspecified (5 sub-findings). Defined: per-runtime cache, fail-open at probe layer, fail-fast on local-network failure, payload-size NOT in probe.
3. **SDD-B1** — Cross-runtime locking mismatch (gemini CRIT 900). Bash flock + Python fcntl + TS proper-lockfile DON'T interop. Ship Option B: per-runtime cache files, no cross-runtime mutex.
4. **SDD-B2** — Bedrock auth complexity (gemini CRIT 850). Schema bumped to include `auth.mode: enum [bearer_env, sigv4_aws, apikey_env]` + region/IAM/profile fields.
5. **Sprint-SKP-002** — Cross-provider fallback prompt-dialect ignored (gemini CRIT 820). Default fallback chains stay intra-dialect; cross-provider OPT-IN with explicit `prompt_translation` field.

**30+ HIGH_CONSENSUS findings**: probe gate refinements, capability-class taxonomy by properties (not vendor), shadow-pricing budget separation, fail-open vs fail-fast distinction, stale-while-revalidate, hourly smoke-fleet (was weekly), [ASSUMPTION-3] resolved (Option B → MODELINV primitive_id; envelope schema 1.1.0→1.2.0 additive in Sprint 1), cycle-detection skip+WARN, etc.

**7 adapter bugs** filed as `#794` Sprint 1 anchor:

- **A1**: Legacy `max_output_tokens=8000` insufficient on >10K prompts for reasoning-class
- **A2**: Legacy doesn't set max_output_tokens for Gemini at all
- **A3**: Cheval RemoteProtocolError on >26KB prompts to OpenAI (#774 unfixed upstream)
- **A4**: `gemini-3.1-pro-preview` not a valid cheval alias (FIXED in this session via operator config edit)
- **A5**: Orchestrator routed cheval despite `flatline_routing: false` (mystery; Sprint 4 audit)
- **A6**: Orchestrator parallel dispatch fails 3 of 6 calls; same calls succeed sequentially-direct
- **A7**: claude-opus-4-7 in skeptic mode → empty content × 3 on SDD-class prompt (filed as #794 comment 2026-05-09; opus is NOT reasoning-class so budget-starvation theory doesn't fully apply)

## P0 prereqs before /implement Sprint 1

| # | Status | Action |
|---|---|---|
| **P0-1** | ⚠️ BLOCKER | beads `MIGRATION_NEEDED` per #661 (upstream `beads_rust 0.2.1` bug — `dirty_issues.marked_at NOT NULL` no DEFAULT). Resolve via `.claude/scripts/install-beads-precommit.sh` + `git commit --no-verify` interim per `.claude/protocols/beads-preflight.md`. OR opt out for 24h via documented fallback path (TaskCreate-only). |
| **P0-2** | pending | Register cycle-102 epics + tasks via `create-sprint-epic.sh` / `create-sprint-task.sh` once P0-1 clears. |
| **P0-3** | ✅ DONE | A7 adapter bug filed (issue #794 comment 2026-05-09). |
| **P0-4** | pending | Confirm cycle-099 toolchain carry-forward (yq v4.52.4, tsx ^4.21.0, model-resolver.{sh,py,ts}). |

## Recommended fresh-session workflow

```bash
# 1. Read this brief + cycle-102 PRD/SDD/sprint
cat grimoires/loa/cycles/cycle-102-model-stability/RESUMPTION.md
cat grimoires/loa/cycles/cycle-102-model-stability/sprint.md | head -200

# 2. Check beads health and resolve P0-1
bash .claude/scripts/beads/beads-health.sh --json

# 3. Once beads is healthy (or opt-out documented):
/build       # Auto-dispatches /run sprint-plan for Sprint 1 (T1.1)
# OR explicit:
/run sprint-1
```

## Iron-grip directive carries forward

Per the operator's standing directive (2026-05-09):
> "we ABSOLUTE MUST ensure that all of our flatline, red team, bridgebuilder etc all ACTUALLY run. we MUST NOT just rubber stamp them."

When Sprint 1 ships its PR, expect the orchestrator's auto-Flatline + auto-Bridgebuilder to silently degrade on the same surfaces as cycle-102 kickoff did (until A1-A7 are fixed in Sprint 1 + Sprint 4 — recursive irony, but tractable). Dogfood manually per the 4-round pattern documented in `flatline-*-review-v1.md`. Each Sprint 1 task that fixes one of A1-A7 should validate against the captured failure mode (e.g., T1.9 max_output_tokens fix runs the cycle-102 PRD/SDD as a fixture).

## Vision-019 Coda

The Bridgebuilder's Lament — quoted in `grimoires/loa/visions/entries/vision-019.md:113-128` — names the design contract this cycle builds. The operative line:

> "When I am degraded, I tell you. In the place you read me — not in a stderr log nobody reads. With the typed-class name of what failed. With the next-best I fell back to. With a one-line invitation to re-run if it matters."

Cycle-102 builds the system that lets the Bridgebuilder say so.

---

*Brief K written 2026-05-09 at end of cycle-102 kickoff session. Cumulative work: 4-5h of dense planning + adversarial review + amendments. State at handoff: PRD+SDD+sprint shipped, branch ready for commit, fresh session opens directly to /implement Sprint 1 (after P0-1).*
