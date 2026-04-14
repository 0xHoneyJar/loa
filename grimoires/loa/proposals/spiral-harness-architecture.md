# Proposal: Spiral Harness Architecture — Evidence-Gated Orchestrator

**Date**: 2026-04-14
**Author**: cycle-070 design session
**Status**: Draft
**Supersedes**: Monolithic `claude -p` dispatch (cycle-070 Sprint 1)

---

## Problem

Cycle-070's E2E test proved the spiral can dispatch and produce working code autonomously. But the autonomous subprocess skipped every quality gate — Flatline, Bridgebuilder, Red Team, Review, and Audit all show as "completed" in 4 seconds with no actual execution. The LLM agent self-certified its own work.

This is the **fox-guarding-the-henhouse antipattern**: the same agent that writes code decides whether to review it.

## Insight: Harness Engineering

Frontier labs (Anthropic, OpenAI, Google DeepMind) build model evaluation and training systems using a pattern called **harness engineering**:

- **Anthropic's Claude Code**: A Node.js harness that mediates every tool call. The LLM proposes actions, the harness validates and executes. The LLM never directly controls the filesystem — it goes through tool gates.
- **OpenAI's Evals Framework**: Each evaluation is a pipeline of discrete steps. Each step has defined inputs, expected outputs, and scoring criteria. The harness runs steps; the model fills in the blanks within each step.
- **Google's Tricorder** (ISSTA 2018): Composable analysis passes where each pass produces typed findings that cascade to later passes. The orchestrator owns sequencing.

The common principle: **the orchestrator controls the loop, the model does targeted work within bounded tasks**. Models are workers, not supervisors.

## Architecture: Phase-as-Subprocess, Gate-as-Script

```
spiral-harness.sh (bash — THE orchestrator)
│
│  PHASE 1: DISCOVERY
├── claude -p "Write PRD for: {task}. Include ## Assumptions section."
│   └── OUTPUT: grimoires/loa/prd.md
│   └── EVIDENCE: sha256 checksum, file size > 500 bytes, contains "PRD"
│
│  GATE 1: FLATLINE PRD (bash — NOT the LLM)
├── flatline-orchestrator.sh --doc prd.md --phase prd --mode review --json
│   └── OUTPUT: .run/spiral-evidence/flatline-prd.json
│   └── EVIDENCE: valid JSON, high_consensus_count >= 0
│   └── ARBITER: if blockers > 0, invoke arbiter (phase 3)
│   └── INTEGRATION: pipe accepted findings back to next claude -p call
│
│  PHASE 2: ARCHITECTURE
├── claude -p "Write SDD from PRD + Flatline findings: {findings_summary}"
│   └── OUTPUT: grimoires/loa/sdd.md
│   └── EVIDENCE: sha256, size > 500, contains "SDD"
│
│  GATE 2: FLATLINE SDD
├── flatline-orchestrator.sh --doc sdd.md --phase sdd --mode review --json
│   └── (same evidence pattern)
│
│  GATE 2.5: BRIDGEBUILDER DESIGN REVIEW (optional)
├── [Bridgebuilder agent review of SDD — agent subagent, not LLM self-review]
│
│  PHASE 3: PLANNING
├── claude -p "Write Sprint Plan from PRD + SDD + Flatline findings"
│   └── OUTPUT: grimoires/loa/sprint.md
│
│  GATE 3: FLATLINE SPRINT
├── flatline-orchestrator.sh --doc sprint.md --phase sprint --mode review --json
│
│  PHASE 4: IMPLEMENTATION
├── claude -p "Implement sprint plan. Run tests. Commit."
│   └── OUTPUT: code changes, test results
│   └── EVIDENCE: git diff --stat, test exit code 0
│
│  GATE 4: REVIEW (separate claude -p session — fresh eyes)
├── claude -p "Review this implementation against sprint.md acceptance criteria"
│   └── OUTPUT: engineer-feedback.md
│   └── EVIDENCE: contains "All good" OR "CHANGES_REQUIRED"
│   └── If CHANGES_REQUIRED: loop back to Phase 4 (max 3 iterations)
│
│  GATE 5: AUDIT (separate claude -p session — adversarial)
├── claude -p "Security audit this implementation. OWASP checklist."
│   └── OUTPUT: auditor-sprint-feedback.md
│   └── EVIDENCE: contains "APPROVED"
│   └── If CHANGES_REQUIRED: loop back to Phase 4
│
│  PHASE 5: PR CREATION
├── gh pr create (bash — deterministic, not LLM-decided)
│
│  GATE 6: BRIDGEBUILDER PR REVIEW
├── bridgebuilder entry.sh --pr {number}
│
│  RECORD: write cycle-outcome.json sidecar
└── DONE
```

**Key principle**: Flatline, Bridgebuilder, Review, Audit, and PR creation run **in bash**, not inside an LLM session. The LLM can't skip them because it's not the LLM's decision.

## The Flight Recorder: Immutable Audit Trail

Every action appended to `.run/spiral-flight-recorder.jsonl` — the black box:

```jsonl
{"seq":1,"ts":"2026-04-14T10:00:00Z","phase":"DISCOVERY","actor":"claude-opus","action":"write_prd","input_checksum":null,"output_checksum":"sha256:abc123","output_path":"grimoires/loa/prd.md","output_bytes":2847,"duration_ms":36000,"cost_usd":0.85,"verdict":null}
{"seq":2,"ts":"2026-04-14T10:00:36Z","phase":"GATE_FLATLINE_PRD","actor":"flatline-orchestrator","action":"multi_model_review","input_checksum":"sha256:abc123","output_checksum":"sha256:def456","output_path":".run/spiral-evidence/flatline-prd.json","duration_ms":223000,"cost_usd":0.25,"verdict":"5 HIGH_CONSENSUS, 3 BLOCKERS"}
{"seq":3,"ts":"2026-04-14T10:04:19Z","phase":"GATE_FLATLINE_PRD","actor":"arbiter-opus","action":"arbiter_decision","input_checksum":"sha256:def456","output_checksum":"sha256:ghi789","findings_accepted":2,"findings_rejected":1,"duration_ms":15000,"cost_usd":0.50,"verdict":"2 accepted, 1 rejected"}
{"seq":4,"ts":"2026-04-14T10:04:34Z","phase":"ARCHITECTURE","actor":"claude-opus","action":"write_sdd","input_checksum":"sha256:abc123+sha256:ghi789","output_checksum":"sha256:jkl012","output_path":"grimoires/loa/sdd.md","output_bytes":4521,"duration_ms":19000,"cost_usd":0.90,"verdict":null}
...
```

**Properties**:
- **Append-only**: New entries appended, never modified (same pattern as event-bus DLQ)
- **Content-addressed**: Input/output checksums create a verifiable chain
- **Sequence-numbered**: Monotonic `seq` field detects gaps/tampering
- **Actor-tagged**: Every entry identifies who did the work (which model, which script)
- **Cost-tracked**: Per-action cost enables accurate budget enforcement
- **Reconstructable**: Given the flight recorder, you can replay the entire spiral decisions

## Evidence Verification

Each gate checks evidence before allowing progression:

```bash
_verify_evidence() {
    local phase="$1" artifact="$2" min_bytes="${3:-500}"
    
    # 1. File exists
    [[ -f "$artifact" ]] || { _record_failure "$phase" "MISSING_ARTIFACT" "$artifact"; return 1; }
    
    # 2. Non-trivial size
    local bytes=$(wc -c < "$artifact")
    [[ "$bytes" -ge "$min_bytes" ]] || { _record_failure "$phase" "ARTIFACT_TOO_SMALL" "$bytes < $min_bytes"; return 1; }
    
    # 3. Content-addressed checksum
    local checksum=$(sha256sum "$artifact" | awk '{print $1}')
    
    # 4. Record to flight recorder
    _record_evidence "$phase" "$artifact" "$checksum" "$bytes"
    
    echo "$checksum"
}

_verify_flatline_output() {
    local phase="$1" flatline_json="$2"
    
    # Must be valid JSON
    jq empty "$flatline_json" 2>/dev/null || { _record_failure "$phase" "INVALID_JSON"; return 1; }
    
    # Must have consensus_summary
    jq -e '.consensus_summary' "$flatline_json" >/dev/null 2>&1 || { _record_failure "$phase" "NO_CONSENSUS"; return 1; }
    
    # Record metrics
    local high=$(jq '.consensus_summary.high_consensus_count // 0' "$flatline_json")
    local blockers=$(jq '.consensus_summary.blocker_count // 0' "$flatline_json")
    _record_evidence "$phase" "$flatline_json" "$(sha256sum "$flatline_json" | awk '{print $1}')" "" "high=$high blockers=$blockers"
}

_verify_review_verdict() {
    local phase="$1" feedback="$2"
    
    if grep -qi "All good\|APPROVED" "$feedback"; then
        _record_evidence "$phase" "$feedback" "" "" "verdict=APPROVED"
        return 0
    elif grep -qi "CHANGES_REQUIRED" "$feedback"; then
        _record_evidence "$phase" "$feedback" "" "" "verdict=CHANGES_REQUIRED"
        return 1
    else
        _record_failure "$phase" "NO_VERDICT" "$feedback"
        return 1
    fi
}
```

## Scoped `claude -p` Prompts

Each phase gets a **focused, bounded prompt** — not "run the whole pipeline":

### Phase 1: Discovery
```
Write a Product Requirements Document for this task:

{task_description}

{seed_context if available}

Requirements:
- Include ## Assumptions section listing what you assumed
- Include ## Goals & Success Metrics with measurable criteria
- Include ## Acceptance Criteria as checkboxes
- Output to: grimoires/loa/prd.md
- Do NOT implement code. Do NOT create an SDD. Only write the PRD.
```

### Phase 2: Architecture (receives Flatline findings)
```
Write a Software Design Document based on this PRD and Flatline review findings.

PRD: {prd content}

Flatline findings integrated:
{accepted findings summary}

Flatline findings rejected:
{rejected findings summary}

Requirements:
- Address each accepted Flatline finding in the design
- Include component architecture, data model, security design
- Output to: grimoires/loa/sdd.md
- Do NOT implement code. Only write the SDD.
```

### Phase 4: Implementation (receives all context)
```
Implement the sprint plan. The PRD, SDD, and Sprint Plan are in grimoires/loa/.

Requirements:
- Create a feature branch: {branch_name}
- Implement all sprint tasks
- Write tests for each task
- Run tests and verify they pass
- Commit with conventional commit messages
- Do NOT create a PR (the orchestrator will do that)
```

### Gate 4: Review (fresh session — independent)
```
You are a senior tech lead reviewer. Review the implementation on branch {branch_name}.

Read:
- grimoires/loa/sprint.md (acceptance criteria)
- The git diff: git diff main...HEAD

For each acceptance criterion, verify it is met with file:line evidence.

Output your review to grimoires/loa/a2a/{sprint_dir}/engineer-feedback.md.
Write "All good" if approved, or "CHANGES_REQUIRED" with specific issues.
```

## Cost Model

| Phase | Actor | Estimated Cost |
|-------|-------|---------------|
| Discovery (PRD) | claude -p | $0.50-1.00 |
| Flatline PRD | 3 models × 2 passes | $0.25 |
| Architecture (SDD) | claude -p | $0.50-1.00 |
| Flatline SDD | 3 models × 2 passes | $0.25 |
| Planning (Sprint) | claude -p | $0.30-0.50 |
| Flatline Sprint | 3 models × 2 passes | $0.25 |
| Arbiter (3 phases) | 1 model per phase | $0.50 |
| Implementation | claude -p | $2.00-5.00 |
| Review | claude -p | $0.50-1.00 |
| Audit | claude -p | $0.50-1.00 |
| Bridgebuilder | Node.js + API | $0.25 |
| **Total per cycle** | | **$5.80-10.00** |

Fits within the $10/cycle budget.

## Comparison: Monolithic vs Harness

| Aspect | Monolithic (current) | Harness (proposed) |
|--------|---------------------|-------------------|
| Quality gates | LLM can skip | Bash-enforced, unskippable |
| Audit trail | LLM-written state (untrusted) | Append-only flight recorder (verifiable) |
| Cost tracking | Self-reported | Per-action measurement |
| Failure recovery | Opaque (what did it do?) | Replay from any checkpoint |
| Review independence | Same session reviews own work | Fresh session, no context carryover |
| Flatline | LLM decides whether to run | Bash runs it, LLM has no choice |

## Relationship to Existing Loa Patterns

- **Flight recorder** = existing `audit.jsonl` pattern + WAL from checkpoint protocol
- **Evidence gates** = existing `vision_validate_entry()` pattern applied to pipeline phases
- **Scoped claude -p** = existing Agent Teams pattern where teammates get focused tasks
- **Arbiter** = existing deliberative council lore pattern
- **Content-addressed chain** = existing simstim artifact checksums

## Implementation Scope

**New file**: `.claude/scripts/spiral-harness.sh` — the orchestrator
**Modify**: `spiral-simstim-dispatch.sh` — calls harness instead of single claude -p
**New file**: `.claude/scripts/spiral-evidence.sh` — evidence verification + flight recorder
**Modify**: `flatline-orchestrator.sh` — no changes (already correct interface)
**New file**: `tests/unit/spiral-harness.bats` — evidence verification tests

Estimated: 2 sprints. Sprint 1: harness orchestrator + flight recorder + evidence gates. Sprint 2: review/audit as independent sessions + Bridgebuilder integration + E2E test.
