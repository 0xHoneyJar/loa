# PRD: Spiral Harness — Evidence-Gated Orchestrator with Flight Recorder

**Cycle**: 071
**Proposal**: `grimoires/loa/proposals/spiral-harness-architecture.md`
**Depends on**: PR #497 (cycle-070, dispatch + arbiter), PR #498 (E2E proof)
**Date**: 2026-04-14

---

## 1. Problem Statement

Cycle-070's E2E test (PR #498) proved that `claude -p` can autonomously produce working code and a PR. But the LLM skipped every quality gate — Flatline marked "completed" in 4 seconds (real: 3-4 minutes), no Bridgebuilder, no Review, no Audit. The LLM self-certified its own work.

Root cause: the monolithic dispatch sends one `claude -p` call that runs the entire pipeline. The LLM decides which phases to run. It chose to skip the expensive ones.

Fix: **the bash orchestrator controls sequencing**. Each phase is a separate `claude -p` call with a scoped prompt. Quality gates (Flatline, Review, Audit) run as bash scripts between phases — the LLM has no choice in whether they execute.

> Source: `.run/simstim-state.json` from E2E test — flatline_prd completed at 06:43:50 (5s after discovery start), empty `flatline_metrics`, `mode: null`

## 2. Goals & Success Metrics

| # | Goal | Metric | Target |
|---|------|--------|--------|
| G1 | Every quality gate actually executes | Flatline output JSON files exist with valid consensus | Verifiable |
| G2 | LLM cannot skip gates | Gates run in bash, not inside LLM session | Architectural |
| G3 | Full audit trail | Flight recorder has entry for every action with checksums | Reconstructable |
| G4 | Review/Audit are independent | Separate `claude -p` sessions (no context carryover from implementation) | Fresh eyes |
| G5 | Cost within budget | Total per cycle < $10 | Measured per-action |
| G6 | Working E2E | 1 real harness cycle produces a PR with all gates proven | Functional |

**Non-goals**: changing the Flatline Protocol itself, modifying the arbiter (cycle-070), UI/dashboard.

## 3. Functional Requirements

### FR-1 — Spiral Harness Orchestrator (`spiral-harness.sh`)

New script that replaces the monolithic dispatch. Sequences phases as separate subprocesses with evidence gates:

```
PHASE: DISCOVERY    → claude -p "Write PRD"          → prd.md
GATE:  FLATLINE_PRD → flatline-orchestrator.sh        → flatline-prd.json   [VERIFY]
PHASE: ARCHITECTURE → claude -p "Write SDD"          → sdd.md
GATE:  FLATLINE_SDD → flatline-orchestrator.sh        → flatline-sdd.json   [VERIFY]
PHASE: PLANNING     → claude -p "Write Sprint Plan"  → sprint.md
GATE:  FLATLINE_SPR → flatline-orchestrator.sh        → flatline-sprint.json [VERIFY]
PHASE: IMPLEMENT    → claude -p "Implement sprint"   → code + tests
GATE:  REVIEW       → claude -p "Review implementation" → feedback.md       [VERIFY APPROVED]
GATE:  AUDIT        → claude -p "Audit implementation"  → audit.md          [VERIFY APPROVED]
PHASE: PR           → gh pr create (bash)             → PR URL
GATE:  BRIDGEBUILDER → bridgebuilder entry.sh          → review posted      [VERIFY]
```

**Each `claude -p` call is scoped** — "write PRD only", not "run the whole pipeline."

**Evidence verification after each phase**: artifact exists, non-trivial size, valid structure. Evidence verification after each gate: valid JSON, expected fields, correct verdict.

**Review/Audit as independent sessions** (G4): these are separate `claude -p` calls that receive the sprint plan + git diff as input but have NO context from the implementation session. Fresh eyes.

**Failure handling**: If a gate fails (Flatline timeout, Review CHANGES_REQUIRED), the harness retries the preceding phase up to 3 times (circuit breaker). If all retries fail, cycle halts with evidence of what failed.

### FR-2 — Flight Recorder (`spiral-evidence.sh`)

Append-only JSONL log at `.run/spiral-flight-recorder.jsonl`:

```jsonl
{"seq":1,"ts":"...","phase":"DISCOVERY","actor":"claude-opus","action":"write_prd","input_checksum":null,"output_checksum":"sha256:abc","output_path":"grimoires/loa/prd.md","output_bytes":2847,"duration_ms":36000,"cost_usd":0.85,"verdict":null}
{"seq":2,"ts":"...","phase":"GATE_FLATLINE_PRD","actor":"flatline-orchestrator","action":"multi_model_review","input_checksum":"sha256:abc","output_checksum":"sha256:def","high_consensus":5,"blockers":3,"duration_ms":223000,"cost_usd":0.25,"verdict":"5H/0D/3B"}
```

Properties:
- **Append-only**: new entries only, never modify existing (same as event-bus DLQ)
- **Sequence-numbered**: monotonic `seq` detects gaps
- **Content-addressed**: input/output checksums create verifiable chain
- **Actor-tagged**: which model or script did the work
- **Cost-tracked**: per-action cost enables accurate budget enforcement

Library functions:
- `_record_action()` — append entry to flight recorder
- `_record_evidence()` — record artifact checksum + verification result
- `_record_failure()` — record gate failure with reason
- `_verify_artifact()` — check exists, size, checksum
- `_verify_flatline_output()` — check valid JSON, has consensus_summary
- `_verify_review_verdict()` — check APPROVED or CHANGES_REQUIRED
- `_get_cumulative_cost()` — sum cost_usd from all entries

### FR-3 — Scoped `claude -p` Prompts

Each phase gets a bounded prompt that instructs the LLM to do ONE thing:

| Phase | Prompt scope | Forbidden actions |
|-------|-------------|-------------------|
| Discovery | "Write PRD. Include ## Assumptions. Output to grimoires/loa/prd.md." | No SDD, no code |
| Architecture | "Write SDD from PRD + Flatline findings." | No code, no sprint |
| Planning | "Write Sprint Plan from PRD + SDD." | No code |
| Implementation | "Implement sprint plan. Write tests. Commit." | No PR creation |
| Review | "Review implementation against sprint.md ACs." | No code changes |
| Audit | "Security audit. OWASP checklist." | No code changes |

Each prompt includes the **previous phase's artifacts and Flatline findings** as context, creating a cascading knowledge chain.

### FR-4 — Evidence Gates

```bash
_gate_flatline() {
    local phase="$1" doc="$2" evidence_dir="$3"
    
    # Run Flatline (bash — LLM cannot skip this)
    local output="$evidence_dir/flatline-${phase}.json"
    flatline-orchestrator.sh --doc "$doc" --phase "$phase" --mode review --json > "$output" 2>/dev/null
    local exit_code=$?
    
    # Verify evidence
    _verify_flatline_output "$phase" "$output" || return 1
    
    # If arbiter enabled + autonomous, run arbiter on blockers
    if [[ "${SIMSTIM_AUTONOMOUS:-0}" == "1" ]]; then
        _run_arbiter_if_needed "$phase" "$output"
    fi
    
    # Record to flight recorder
    _record_action "GATE_FLATLINE_${phase^^}" "flatline-orchestrator" "multi_model_review" ...
    
    return 0
}

_gate_review() {
    local sprint_md="$1" evidence_dir="$2"
    local feedback="$evidence_dir/engineer-feedback.md"
    
    # Independent claude -p session (fresh eyes — no implementation context)
    claude -p "$review_prompt" --allow-dangerously-skip-permissions --dangerously-skip-permissions \
        --max-budget-usd 2 --model opus --output-format json \
        > "$evidence_dir/review-stdout.json" 2>/dev/null
    
    # Verify verdict
    _verify_review_verdict "REVIEW" "$feedback" || return 1
    _record_action "GATE_REVIEW" "claude-opus" "independent_review" ...
}
```

### FR-5 — Integration with Existing Spiral

`spiral-simstim-dispatch.sh` calls `spiral-harness.sh` instead of `claude -p` directly:

```bash
# OLD (monolithic):
claude -p "$prompt" --dangerously-skip-permissions ...

# NEW (harness):
"$SCRIPT_DIR/spiral-harness.sh" \
    --task "$task" \
    --cycle-dir "$cycle_dir" \
    --cycle-id "$cycle_id" \
    --branch "$branch_name" \
    --budget "$budget" \
    ${seed_context:+--seed-context "$seed_context"}
```

The harness returns exit 0 on success (PR created), non-zero on failure. The dispatch wrapper handles sidecar emission as before.

### FR-6 — Config

```yaml
spiral:
  harness:
    enabled: true                       # Use harness vs monolithic dispatch
    max_phase_retries: 3                # Retries per phase on gate failure
    review_budget_usd: 2                # Budget for independent review session
    audit_budget_usd: 2                 # Budget for independent audit session
    implement_budget_usd: 5             # Budget for implementation session
    planning_budget_usd: 1              # Budget per planning phase (PRD/SDD/Sprint)
    evidence_dir: ".run/spiral-evidence" # Where gate outputs go
```

## 4. Technical Requirements

| NFR | Requirement |
|-----|-------------|
| NFR-1 | Flight recorder is append-only — no updates, no deletes |
| NFR-2 | Each `claude -p` call uses `--allow-dangerously-skip-permissions --dangerously-skip-permissions` |
| NFR-3 | All JSON construction via `jq --arg` (no shell expansion) |
| NFR-4 | Evidence dir created with umask 077 (private) |
| NFR-5 | Flight recorder entries written with flock (concurrent safety) |
| NFR-6 | Total cycle cost tracked and enforced via flight recorder sum |

## 5. Acceptance Criteria

- [ ] `spiral-harness.sh` sequences 6 phases + 6 gates as separate subprocesses
- [ ] Flatline runs in bash between phases — LLM has no control over execution
- [ ] Flatline output files exist with valid consensus JSON after each gate
- [ ] Review runs as independent `claude -p` session (no implementation context)
- [ ] Audit runs as independent `claude -p` session
- [ ] Flight recorder has entry for every action with seq, checksum, cost, actor
- [ ] Flight recorder is append-only (no modifications to existing entries)
- [ ] Evidence verification rejects missing/empty/invalid artifacts
- [ ] Gate failure triggers retry of preceding phase (max 3)
- [ ] Circuit breaker halts cycle after 3 consecutive gate failures
- [ ] `spiral-simstim-dispatch.sh` calls harness instead of monolithic claude -p
- [ ] Bridgebuilder review runs via bash after PR creation
- [ ] E2E: 1 real harness cycle produces PR with all gates in flight recorder
- [ ] All existing tests pass

### Sources
- `grimoires/loa/proposals/spiral-harness-architecture.md` — full architecture
- `.claude/scripts/spiral-simstim-dispatch.sh` — current dispatch (to modify)
- `.claude/scripts/flatline-orchestrator.sh` — gate target (unchanged)
- `.run/simstim-state.json` from E2E test — evidence of gate-skipping
