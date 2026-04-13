# Proposal: Close the Bridgebuilder Feedback Loop in Loa Orchestration

**Status**: DRAFT
**Author**: Derived from HITL observation during PR #463 session (2026-04-13)
**Proposed scope**: Framework-level amendment to `/simstim`, `/review-sprint`, `/audit-sprint`, `/run-bridge`
**Related**: PR #463, bug-20260413-enrich

---

## Problem Statement

The Loa framework has three distinct review layers but they don't form a closed loop:

| Layer | Who | When | Output | Consumed by |
|-------|-----|------|--------|-------------|
| `/review-sprint` | Internal senior lead | Pre-PR | `engineer-feedback.md` | `/audit-sprint` |
| `/audit-sprint` | Internal security auditor | Pre-PR | `auditor-sprint-feedback.md`, `COMPLETED` marker | PR creation |
| **Bridgebuilder** | **External adversarial reviewer** | **Post-PR** | **GitHub PR comments** | **nothing** |

The Bridgebuilder's findings — even when they identify real defects missed by internal review — do not automatically feed back into any Loa workflow. A HITL must manually read the PR comments and decide what to action.

### Evidence from PR #463

In this session, PR #463 went through `/review-sprint` + `/audit-sprint` + approved, then the multi-model Bridgebuilder was manually run against the PR. It posted 38 findings (1 CRITICAL, 6 HIGH, 16 MEDIUM, 6 LOW, 8 PRAISE, 1 REFRAME). Triage showed:
- 5 real actionable findings missed by internal review
- 7 false positives (mostly from diff-only context)
- 8 PRAISE items worth mining into lore

**Without this manual triage session, all 38 findings would have been ignored.** The framework provided no mechanism to surface, classify, or act on them.

---

## Why NOT fold Bridgebuilder into `/review-sprint` / `/audit-sprint`

The obvious solution is to run Bridgebuilder as part of internal review. This is wrong:

1. **Defeats the "fresh eyes" purpose** — Bridgebuilder's value is being *outside* the internal loop. Folding it in creates echo-chamber validation.
2. **Requires PR to exist** — `/review-sprint` runs BEFORE PR creation. Bridgebuilder reviews PRs.
3. **Conflates concerns** — Internal review checks "does this match our acceptance criteria?" Bridgebuilder asks "what would a stranger think?"
4. **Timing** — Internal review is fast (<1min). Bridgebuilder is slow (2-5min with real models). Folding slows the inner loop.

**Keep Bridgebuilder external. Bridge its output into Loa state through a new phase.**

---

## Proposed Architecture (3-tier review)

```
TIER 1 — Pre-PR Internal Validation (unchanged):
  /implement → /review-sprint → /audit-sprint → create PR draft
  
TIER 2 — Post-PR External Validation (NEW closed loop):
  PR created → /run-bridge (auto) OR manual → Bridgebuilder posts findings
                                                  ↓
                                          bridge-findings-parser.sh
                                                  ↓
                                  Classify findings by action needed:
                                  ├─ BLOCKER (>N severity) → /bug auto-triage → /implement
                                  ├─ HIGH_CONSENSUS → HITL decision prompt
                                  ├─ DISPUTED → log for review, don't block
                                  ├─ PRAISE → mine into lore registry
                                  └─ REFRAME → vision registry entry
  
TIER 3 — Pattern Aggregation (NEW meta-layer):
  Across N completed PRs → identify recurring finding themes
                           ↓
                  Feed into /plan-and-analyze OR /architect as "cross-cutting concern"
                           
  Example: "4 of last 5 PRs had missing-error-handling findings"
           → next sprint's /architect phase adds this as explicit architectural constraint
```

### Why this works

- **Separation of concerns preserved**: Internal review checks acceptance criteria; Bridgebuilder checks unseen-eyes quality; pattern aggregation surfaces systemic issues
- **Closed loop at every tier**: BLOCKERs auto-trigger work; HIGH surfaces to humans; PRAISE/REFRAME feed knowledge base
- **Backwards compatible**: `/review-sprint` and `/audit-sprint` unchanged. New behavior opt-in via existing `/run-bridge`.
- **False-positive tolerant**: HITL decision point for HIGH means we don't auto-triage noisy findings

---

## Concrete Amendments

### Amendment 1: Extend `/simstim` Phase 7.5 (Post-PR Validation)

The existing `simstim-workflow` SKILL.md already has a "Phase 7.5: POST-PR VALIDATION" section that runs `post-pr-orchestrator.sh`. **Proposal**: integrate `/run-bridge` as a sub-phase of 7.5:

```yaml
# .loa.config.yaml
simstim:
  post_pr_validation:
    enabled: true
    phases:
      - bridgebuilder_review      # NEW — invoke /run-bridge
      - blocker_triage             # NEW — parse findings, trigger /bug
      - e2e_testing                # Existing
      - flatline_pr                # Existing (opt-in)
```

**Implementation**: 
- Modify `.claude/scripts/post-pr-orchestrator.sh` to call `.claude/scripts/bridge-orchestrator.sh` as a step
- Parse `.run/bridge-reviews/*.json` for BLOCKER findings
- If BLOCKERs exist: auto-invoke `/bug` with the finding as input
- Loop until no BLOCKERs OR circuit breaker trips

### Amendment 2: `/review-sprint` awareness of Bridgebuilder state

**Not**: fold Bridgebuilder INTO `/review-sprint`.
**Instead**: `/review-sprint` checks if a prior Bridgebuilder review exists and cross-references.

```
Phase 0.5 (NEW): Cross-Reference with External Review
  IF .run/bridge-reviews/ has findings for the current PR:
    - Read findings
    - For each internal concern I raised:
      - Did Bridgebuilder also raise this? → strengthen confidence
      - Did Bridgebuilder NOT raise this? → flag for consideration
    - For each Bridgebuilder finding:
      - Do I agree on severity? → if not, log disagreement
  
  This is cross-model validation, not replacement.
```

**Value**: Internal reviewer sees where they agree/disagree with external reviewer. Disagreement is signal (either reviewer could be wrong). Agreement strengthens confidence.

### Amendment 3: Pattern Aggregation via Lore Mining

**Goal**: Recurring findings across PRs become systemic insights.

**Mechanism**: 
- Every completed Bridgebuilder review stores findings in `.run/bridge-reviews/{pr-id}.json`
- New skill: `/bridgebuilder-aggregate` — runs over N historical reviews
- Identifies finding patterns (e.g., "15 of 20 PRs had missing-null-check findings")
- Emits lore entries: `grimoires/loa/lore/patterns.yaml`
- `/plan-and-analyze` and `/architect` load lore → inform future sprints

**Example lore entry generated from aggregation**:
```yaml
- id: pattern-missing-error-handling
  term: Missing Error Handling
  short: Recurring issue across 15 PRs
  context: |
    Bridgebuilder findings aggregated 2026-Q2 show 15 of 20 recent PRs
    flagged missing try/catch on async operations. Consider architectural
    constraint in next cycle.
  source: bridgebuilder-aggregate-2026-Q2
  tags: [error-handling, async, cross-cutting]
```

---

## False-Positive Mitigation

Triage of PR #463 findings revealed an 18% false-positive rate. Main causes:

1. **Diff-only context**: Reviewer asserts method doesn't exist based on diff alone
2. **Stale API knowledge**: Training cutoff doesn't know current API shapes
3. **Duplicated framings**: Same issue counted twice with different wording

**Proposed mitigations** (in Bridgebuilder skill, not core framework):

- Add system prompt directive: "If you reference a method/API, verify it appears in the diff. If not, say 'I cannot verify this from the diff' rather than asserting non-existence."
- Pass current date in context so model calibrates training cutoff
- Add deduplication pass over findings (same file + similar title → merge)

These are **Bridgebuilder-level improvements**, not framework-level. Should land as a separate bug-triage.

---

## Migration Path

Rollout is progressive and opt-in:

### Phase 1 (immediate, low-risk)
- Document this proposal (this file)
- Create follow-up `/bug` sprints for the 5 real findings from PR #463 triage
- No code changes to `/review-sprint` or `/audit-sprint`

### Phase 2 (next cycle)
- Implement Amendment 1: `/simstim` Phase 7.5 calls `/run-bridge`
- Behind feature flag `simstim.post_pr_validation.bridgebuilder_review: false` (default off)
- Test on 2-3 PRs, measure false-positive rate, iterate

### Phase 3 (after Phase 2 proves out)
- Enable Amendment 1 by default
- Implement Amendment 2: `/review-sprint` cross-references
- Optional: Amendment 3 if aggregation proves valuable

### Phase 4 (longer-term)
- Lore mining from aggregated findings
- Integration into `/plan-and-analyze` and `/architect`

---

## Design Decisions (resolved by HITL 2026-04-13)

1. **Autonomous operation with logged reasoning**: In autonomous mode (simstim, /run, /run-bridge), the framework MAY act on BLOCKER findings without HITL approval, **provided every decision is logged with explicit reasoning**. HITL retains right to review decisions post-hoc. In interactive mode, HITL still gates.
   - **Logging requirement**: Every auto-triage decision emits a trajectory entry with: finding ID, classification, action taken, reasoning for the action. Target location: `grimoires/loa/a2a/trajectory/bridge-triage-{date}.jsonl`
2. **False positives acceptable**: No target FP-rate threshold. False positives are cost of doing business during experimentation. Revisit if signal-to-noise degrades beyond usefulness.
3. **Circuit breaker depth**: Accept existing `/run-bridge` default of `depth: 5`.
4. **No cost gating (for now)**: Experimental phase — collect real usage data first, introduce budgets later if needed.
5. **Production monitoring supported**: Framework must support both (a) post-merge scheduled runs and (b) manual invocation on arbitrary PRs. Scheduling primitives exist in `/schedule` skill.

---

## Success Criteria

This proposal is successful when:

- [x] PR #463 demonstrates the gap (✓ this session)
- [x] Triage document shows real value from Bridgebuilder findings (✓ `pr-463-bridgebuilder-triage.md`)
- [ ] Amendment 1 prototype passes E2E test on 3 PRs
- [ ] False-positive rate reduces below 10% after Bridgebuilder improvements
- [ ] First pattern extracted via aggregation lands in a plan artifact

---

## References

- Session that triggered this proposal: multi-model bridgebuilder work on PR #463 (2026-04-13)
- Related `/bug` sprints: `bug-20260413-9f9b39` (format contract), `bug-20260413-enrich` (readability)
- Existing infrastructure: `/run-bridge`, `post-pr-orchestrator.sh`, `bridge-orchestrator.sh`, `bridge-findings-parser.sh`
- Triage outcomes: `grimoires/loa/a2a/bug-20260413-enrich/pr-463-bridgebuilder-triage.md`
