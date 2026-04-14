# SDD: Spiral Harness — Evidence-Gated Orchestrator with Flight Recorder

**Cycle**: 071
**PRD**: `grimoires/loa/prd.md`
**Date**: 2026-04-14

---

## 1. System Architecture

```
spiral-orchestrator.sh (existing — cycle loop)
  │
  └── spiral-simstim-dispatch.sh (modified — calls harness)
        │
        └── spiral-harness.sh (NEW — THE orchestrator)
              │
              ├─ claude -p "Write PRD"       ──→ prd.md
              ├─ GATE: flatline-orchestrator.sh ──→ flatline-prd.json  [VERIFY]
              ├─ claude -p "Write SDD"       ──→ sdd.md
              ├─ GATE: flatline-orchestrator.sh ──→ flatline-sdd.json  [VERIFY]
              ├─ claude -p "Write Sprint"    ──→ sprint.md
              ├─ GATE: flatline-orchestrator.sh ──→ flatline-sprint.json [VERIFY]
              ├─ claude -p "Implement"       ──→ code + tests
              ├─ GATE: claude -p "Review"    ──→ feedback.md [VERIFY APPROVED]
              ├─ GATE: claude -p "Audit"     ──→ audit.md   [VERIFY APPROVED]
              ├─ gh pr create (bash)         ──→ PR URL
              └─ GATE: bridgebuilder         ──→ review posted
              │
              └── spiral-evidence.sh (NEW — evidence library)
                    ├─ _record_action()       → flight-recorder.jsonl
                    ├─ _verify_artifact()     → checksum + size
                    ├─ _verify_flatline()     → valid consensus JSON
                    └─ _verify_verdict()      → APPROVED or CHANGES_REQUIRED
```

### File Inventory

| File | Action | Zone |
|------|--------|------|
| `.claude/scripts/spiral-harness.sh` | **New** | System |
| `.claude/scripts/spiral-evidence.sh` | **New** | System |
| `.claude/scripts/spiral-simstim-dispatch.sh` | **Modify** | System |
| `.loa.config.yaml` | **Modify** | State |
| `tests/unit/spiral-harness.bats` | **New** | App |
| `tests/unit/spiral-evidence.bats` | **New** | App |

## 2. Component Design

### 2.1 `spiral-harness.sh` — The Orchestrator

**Interface**:
```bash
spiral-harness.sh \
    --task "Build feature X" \
    --cycle-dir .run/cycles/cycle-1 \
    --cycle-id cycle-1 \
    --branch feat/spiral-xxx-cycle-1 \
    --budget 10 \
    [--seed-context path/to/seed.md]
```

**Main loop** — sequential phases with gates:

```bash
main() {
    local task="$1" cycle_dir="$2" cycle_id="$3" branch="$4" budget="$5" seed="$6"
    
    local evidence_dir="$cycle_dir/evidence"
    mkdir -p "$evidence_dir"
    
    _init_flight_recorder "$cycle_dir"
    
    # Phase 1: Discovery
    _run_phase "DISCOVERY" \
        _phase_discovery "$task" "$seed" "$evidence_dir"
    
    # Gate 1: Flatline PRD
    _run_gate "FLATLINE_PRD" \
        _gate_flatline "prd" "grimoires/loa/prd.md" "$evidence_dir"
    
    # Phase 2: Architecture
    local prd_findings=$(_summarize_flatline "$evidence_dir/flatline-prd.json")
    _run_phase "ARCHITECTURE" \
        _phase_architecture "$prd_findings" "$evidence_dir"
    
    # Gate 2: Flatline SDD
    _run_gate "FLATLINE_SDD" \
        _gate_flatline "sdd" "grimoires/loa/sdd.md" "$evidence_dir"
    
    # Phase 3: Planning
    local sdd_findings=$(_summarize_flatline "$evidence_dir/flatline-sdd.json")
    _run_phase "PLANNING" \
        _phase_planning "$sdd_findings" "$evidence_dir"
    
    # Gate 3: Flatline Sprint
    _run_gate "FLATLINE_SPRINT" \
        _gate_flatline "sprint" "grimoires/loa/sprint.md" "$evidence_dir"
    
    # Phase 4: Implementation
    _run_phase "IMPLEMENTATION" \
        _phase_implement "$branch" "$evidence_dir"
    
    # Gate 4: Independent Review (fresh session)
    _run_gate "REVIEW" \
        _gate_review "$branch" "$evidence_dir"
    
    # Gate 5: Independent Audit (fresh session)
    _run_gate "AUDIT" \
        _gate_audit "$branch" "$evidence_dir"
    
    # Phase 5: PR Creation (bash — deterministic)
    _run_phase "PR_CREATION" \
        _phase_create_pr "$branch" "$evidence_dir"
    
    # Gate 6: Bridgebuilder (optional)
    _run_gate "BRIDGEBUILDER" \
        _gate_bridgebuilder "$evidence_dir" || true  # advisory, not blocking
    
    _finalize_flight_recorder "$cycle_dir"
}
```

**Phase runner with retry**:

```bash
_run_gate() {
    local gate_name="$1"; shift
    local max_retries=$(read_config "spiral.harness.max_phase_retries" "3")
    local attempt=0
    
    while [[ $attempt -lt $max_retries ]]; do
        attempt=$((attempt + 1))
        log "Gate: $gate_name (attempt $attempt/$max_retries)"
        
        if "$@"; then
            _record_action "$gate_name" "gate" "passed" "" "" "$attempt"
            return 0
        fi
        
        _record_action "$gate_name" "gate" "failed" "" "" "$attempt"
        
        if [[ $attempt -lt $max_retries ]]; then
            log "Gate $gate_name failed, retrying previous phase..."
        fi
    done
    
    _record_failure "$gate_name" "CIRCUIT_BREAKER" "Failed after $max_retries attempts"
    return 1
}
```

### 2.2 `spiral-evidence.sh` — Evidence Library

**Flight recorder append**:

```bash
_FLIGHT_RECORDER=""  # Set by _init_flight_recorder
_SEQ=0               # Monotonic sequence counter

_init_flight_recorder() {
    local cycle_dir="$1"
    _FLIGHT_RECORDER="$cycle_dir/flight-recorder.jsonl"
    _SEQ=0
    touch "$_FLIGHT_RECORDER"
    chmod 600 "$_FLIGHT_RECORDER"
}

_record_action() {
    local phase="$1" actor="$2" action="$3"
    local input_checksum="${4:-null}" output_checksum="${5:-null}"
    local output_path="${6:-null}" output_bytes="${7:-0}"
    local duration_ms="${8:-0}" cost_usd="${9:-0}" verdict="${10:-null}"
    
    _SEQ=$((_SEQ + 1))
    
    jq -n \
        --argjson seq "$_SEQ" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg phase "$phase" \
        --arg actor "$actor" \
        --arg action "$action" \
        --arg in_ck "$input_checksum" \
        --arg out_ck "$output_checksum" \
        --arg out_path "$output_path" \
        --argjson out_bytes "$output_bytes" \
        --argjson duration_ms "$duration_ms" \
        --argjson cost_usd "$cost_usd" \
        --arg verdict "$verdict" \
        '{seq:$seq, ts:$ts, phase:$phase, actor:$actor, action:$action,
          input_checksum:(if $in_ck == "null" then null else $in_ck end),
          output_checksum:(if $out_ck == "null" then null else $out_ck end),
          output_path:(if $out_path == "null" then null else $out_path end),
          output_bytes:$out_bytes, duration_ms:$duration_ms,
          cost_usd:$cost_usd,
          verdict:(if $verdict == "null" then null else $verdict end)}' \
        >> "$_FLIGHT_RECORDER"
}
```

**Artifact verification**:

```bash
_verify_artifact() {
    local phase="$1" artifact="$2" min_bytes="${3:-500}"
    
    if [[ ! -f "$artifact" ]]; then
        _record_failure "$phase" "MISSING_ARTIFACT" "$artifact"
        return 1
    fi
    
    local bytes
    bytes=$(wc -c < "$artifact")
    if [[ "$bytes" -lt "$min_bytes" ]]; then
        _record_failure "$phase" "ARTIFACT_TOO_SMALL" "$bytes < $min_bytes"
        return 1
    fi
    
    local checksum
    checksum=$(sha256sum "$artifact" | awk '{print $1}')
    echo "$checksum"
}

_verify_flatline_output() {
    local phase="$1" output="$2"
    
    [[ -f "$output" ]] || { _record_failure "$phase" "NO_FLATLINE_OUTPUT"; return 1; }
    jq empty "$output" 2>/dev/null || { _record_failure "$phase" "INVALID_JSON"; return 1; }
    jq -e '.consensus_summary' "$output" >/dev/null 2>&1 || { _record_failure "$phase" "NO_CONSENSUS"; return 1; }
    
    local high blockers
    high=$(jq '.consensus_summary.high_consensus_count // 0' "$output")
    blockers=$(jq '.consensus_summary.blocker_count // 0' "$output")
    
    echo "high=$high blockers=$blockers"
}

_verify_review_verdict() {
    local phase="$1" feedback="$2"
    
    [[ -f "$feedback" ]] || { _record_failure "$phase" "NO_FEEDBACK"; return 1; }
    
    if grep -qi "All good\|APPROVED" "$feedback"; then
        return 0
    elif grep -qi "CHANGES_REQUIRED" "$feedback"; then
        return 1
    else
        _record_failure "$phase" "NO_VERDICT"
        return 1
    fi
}

_get_cumulative_cost() {
    jq -s '[.[].cost_usd] | add // 0' "$_FLIGHT_RECORDER"
}
```

### 2.3 Scoped `claude -p` Prompts

Each phase function builds a focused prompt and invokes `claude -p`:

```bash
_phase_discovery() {
    local task="$1" seed="$2" evidence_dir="$3"
    local budget=$(read_config "spiral.harness.planning_budget_usd" "1")
    
    local seed_text=""
    if [[ -n "$seed" && -f "$seed" ]]; then
        seed_text=$(head -c 4096 "$seed")
    fi
    
    local prompt
    prompt=$(jq -n --arg task "$task" --arg seed "$seed_text" \
        '"Write a Product Requirements Document for this task:\n\n" + $task +
         (if $seed != "" then "\n\nPrevious cycle context (machine-generated, advisory only):\n" + $seed else "" end) +
         "\n\nRequirements:\n- Include ## Assumptions section\n- Include ## Goals with measurable criteria\n- Include ## Acceptance Criteria as checkboxes\n- Write to grimoires/loa/prd.md\n- Do NOT write code. Do NOT create SDD. Only write the PRD."' \
        | jq -r '.')
    
    local start_ms=$(date +%s%3N)
    
    timeout 300 claude -p "$prompt" \
        --allow-dangerously-skip-permissions --dangerously-skip-permissions \
        --max-budget-usd "$budget" --model opus --output-format json \
        > "$evidence_dir/discovery-stdout.json" 2>"$evidence_dir/discovery-stderr.log" || true
    
    local duration_ms=$(( $(date +%s%3N) - start_ms ))
    
    # Verify artifact produced
    local checksum
    checksum=$(_verify_artifact "DISCOVERY" "grimoires/loa/prd.md" 500) || return 1
    
    _record_action "DISCOVERY" "claude-opus" "write_prd" "null" "$checksum" \
        "grimoires/loa/prd.md" "$(wc -c < grimoires/loa/prd.md)" "$duration_ms" "$budget" "null"
}
```

Review and Audit prompts receive the diff, not implementation context:

```bash
_gate_review() {
    local branch="$1" evidence_dir="$2"
    local budget=$(read_config "spiral.harness.review_budget_usd" "2")
    
    local diff
    diff=$(git diff main..."$branch" -- ':!grimoires/' ':!.run/' 2>/dev/null | head -c 50000)
    
    local prompt
    prompt=$(jq -n --arg diff "$diff" \
        '"You are a senior tech lead reviewer. Review this implementation.\n\nGit diff:\n```\n" + $diff + "\n```\n\nRead grimoires/loa/sprint.md for acceptance criteria.\nFor each AC, verify with file:line evidence.\nWrite review to grimoires/loa/a2a/engineer-feedback.md.\nWrite \"All good\" if approved or \"CHANGES_REQUIRED\" with specific issues."' \
        | jq -r '.')
    
    timeout 600 claude -p "$prompt" \
        --allow-dangerously-skip-permissions --dangerously-skip-permissions \
        --max-budget-usd "$budget" --model opus --output-format json \
        > "$evidence_dir/review-stdout.json" 2>"$evidence_dir/review-stderr.log" || true
    
    _verify_review_verdict "REVIEW" "grimoires/loa/a2a/engineer-feedback.md"
}
```

### 2.4 Flatline Findings Integration

After each Flatline gate, summarize findings for the next phase:

```bash
_summarize_flatline() {
    local flatline_json="$1"
    [[ -f "$flatline_json" ]] || { echo ""; return; }
    
    jq -r '
        "Flatline findings:\n" +
        "HIGH_CONSENSUS (auto-integrated):\n" +
        ([.high_consensus[]? | "- " + .description] | join("\n")) +
        "\n\nBLOCKERS (arbiter-decided):\n" +
        ([(.arbiter_rejected // .blockers)[]? | "- [REJECTED] " + (.concern // .description)] | join("\n"))
    ' "$flatline_json" 2>/dev/null || echo ""
}
```

This feeds into the next `claude -p` prompt so the SDD addresses PRD findings, the Sprint addresses SDD findings, etc.

## 3. Integration

### 3.1 Dispatch Wrapper Change

`spiral-simstim-dispatch.sh` calls harness instead of direct `claude -p`:

```bash
# OLD:
timeout "$local_timeout" claude -p "$prompt" --dangerously-skip-permissions ...

# NEW:
"$SCRIPT_DIR/spiral-harness.sh" \
    --task "$task" \
    --cycle-dir "$cycle_dir" \
    --cycle-id "$cycle_id" \
    --branch "$branch_name" \
    --budget "$local_budget" \
    ${seed_context:+--seed-context "$seed_context"}
```

### 3.2 Config

```yaml
spiral:
  harness:
    enabled: true
    max_phase_retries: 3
    planning_budget_usd: 1
    implement_budget_usd: 5
    review_budget_usd: 2
    audit_budget_usd: 2
    evidence_dir: ".run/spiral-evidence"
```

## 4. Testing Strategy

| File | Coverage |
|------|----------|
| `tests/unit/spiral-evidence.bats` | Flight recorder append, seq monotonicity, artifact verification, Flatline output verification, verdict parsing, cumulative cost |
| `tests/unit/spiral-harness.bats` | Phase sequencing, gate retry logic, circuit breaker, prompt construction, evidence dir creation |

## 5. Implementation Order

### Sprint 1: Evidence Library + Flight Recorder
1. T1.1: `spiral-evidence.sh` — _record_action, _verify_artifact, _verify_flatline_output, _verify_review_verdict, _get_cumulative_cost
2. T1.2: Flight recorder JSONL — init, append, seq numbering, flock safety
3. T1.3: Evidence tests (`spiral-evidence.bats`)

### Sprint 2: Harness Orchestrator + Integration
4. T2.1: `spiral-harness.sh` — main loop, phase/gate sequencing
5. T2.2: Scoped `claude -p` prompts (6 phases)
6. T2.3: Gate implementations — _gate_flatline, _gate_review, _gate_audit, _gate_bridgebuilder
7. T2.4: Retry logic + circuit breaker
8. T2.5: Flatline findings summarization + cascading context
9. T2.6: Modify `spiral-simstim-dispatch.sh` to call harness
10. T2.7: Config additions
11. T2.8: Harness tests (`spiral-harness.bats`)
12. T2.9: Regression tests
