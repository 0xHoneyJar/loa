# SDD: Spiral Cost Optimization + Mechanical Dispatch

**Cycle**: 072
**PRD**: `grimoires/loa/prd.md`
**Date**: 2026-04-15

---

## Bridgebuilder Design Review Integrations

| Finding | Severity | Resolution |
|---------|----------|------------|
| CRITICAL-1: Rate-limit header data path doesn't exist (flatline-orchestrator.sh not authorized) | CRITICAL | Descoped to local-accounting fallback. Headers deferred to follow-up cycle requiring flatline-orchestrator.sh modification. AC-13 rewritten. |
| HIGH-1: Auto-escalation fires too late to add Flatline gates retroactively | HIGH | Fixed: classify at startup from task keywords + sprint plan references, not post-implementation git diff. Section 2.2 revised. |
| HIGH-2: Dual cost-tracking (orchestrator vs harness) with no reconciliation | HIGH | Fixed: defined cost authority boundary. Harness writes cycle cost to sidecar, orchestrator reads it. Section 2.4 revised. |
| REFRAME-1: "Mechanical dispatch" is three layers of asking nicely | REFRAME | AC-1 rewritten to "three-layer soft enforcement with negative test." Hard gate (PreToolUse hook) noted as future work. |
| PRAISE-1: Pre-checks are exactly right | PRAISE | Shipped as designed. |
| SPECULATION-1: Profiles may be premature abstraction | SPECULATION | Kept as DX convenience; documented as syntactic sugar over `flatline_gates` + `advisor_model` primitives. |

---

## 1. System Architecture

### 1.1 Component Overview

```
User invokes /spiraling with task
  │
  ├── SKILL.md dispatch guard (agent-level, layer 1)
  │     "You MUST invoke spiral-harness.sh"
  │
  ├── C-PROC-017 constraint (agent-level, layer 2)
  │     "NEVER implement directly"
  │
  └── spiral-harness.sh (mechanical, layer 3)
        │
        ├── Profile resolver (full/standard/light)
        │     └── Auto-escalation classifier
        │
        ├── Pipeline phases (conditional on profile)
        │     ├── DISCOVERY → claude -p (PRD)
        │     ├── GATE: Flatline PRD [if profile=full]
        │     ├── ARCHITECTURE → claude -p (SDD)
        │     ├── GATE: Flatline SDD [if profile=full]
        │     ├── PLANNING → claude -p (Sprint)
        │     ├── GATE: Flatline Sprint [if profile=full|standard]
        │     ├── PRE-CHECK: implementation artifacts
        │     ├── IMPLEMENTATION → claude -p (code)
        │     ├── PRE-CHECK: review readiness + secret scan
        │     ├── REVIEW → claude -p (fresh session, advisor model)
        │     └── AUDIT → claude -p (fresh session, advisor model)
        │
        ├── PR creation (idempotent — check before create)
        ├── Bridgebuilder (advisory)
        └── Flight recorder (append-only JSONL with profile + rate-limit data)

spiral-scheduler.sh (cron/trigger entry point)
  │
  ├── Window check (or continuous bypass)
  ├── flock-based exclusive lock
  ├── Resume HALTED or start new
  └── spiral-orchestrator.sh --start/--resume
        └── check_token_window() stopping condition
        └── check_rate_limit() stopping condition

spiral-benchmark.sh (comparison tool)
  └── Reads two flight-recorder.jsonl files → Markdown report
```

### 1.2 File Map

| File | Action | Lines (est.) | Purpose |
|------|--------|-------------|---------|
| `.claude/scripts/spiral-harness.sh` | Modify | +120 | Pipeline profiles, auto-escalation, pre-checks, idempotent PR, rate-limit logging |
| `.claude/scripts/spiral-evidence.sh` | Modify | +80 | Pre-check functions, secret scanning, rate-limit header parsing |
| `.claude/scripts/spiral-orchestrator.sh` | Modify | +40 | `check_token_window()`, `check_rate_limit()` stopping conditions |
| `.claude/scripts/spiral-scheduler.sh` | New | ~160 | Scheduling wrapper with flock, window check, resume/start logic |
| `.claude/scripts/spiral-benchmark.sh` | New | ~120 | Flight recorder comparison → Markdown report |
| `.claude/skills/spiraling/SKILL.md` | Modify | +60 | Mechanical dispatch instructions, profiles, scheduling docs |
| `.claude/skills/spiraling/index.yaml` | Modify | +10 | Add task input, profile input, harness script reference |
| `.loa.config.yaml` | Modify | +15 | Pipeline profile, scheduling config |
| `.loa.config.yaml.example` | Modify | +40 | Full documented config sections |
| `tests/unit/spiral-profiles.bats` | New | ~150 | Profile resolution, auto-escalation, gate skipping |
| `tests/unit/spiral-prechecks.bats` | New | ~120 | Pre-check functions, secret scanning |
| `tests/unit/spiral-scheduler.bats` | New | ~100 | Scheduler logic, window check, locking |
| `tests/unit/spiral-benchmark.bats` | New | ~80 | Benchmark comparison tool |

---

## 2. Component Design

### 2.1 Pipeline Profile Resolver

**Location**: `spiral-harness.sh`, after config read, before argument parsing

```bash
# Profile resolution: config default → CLI override → auto-escalation
PIPELINE_PROFILE=$(_read_harness_config "spiral.harness.pipeline_profile" "standard")

_resolve_profile() {
    case "$PIPELINE_PROFILE" in
        full)    FLATLINE_GATES="prd,sdd,sprint" ;;
        standard) FLATLINE_GATES="sprint" ;;
        light)   FLATLINE_GATES=""; ADVISOR_MODEL="$EXECUTOR_MODEL" ;;
        *)       PIPELINE_PROFILE="standard"; FLATLINE_GATES="sprint" ;;
    esac
}

_should_run_flatline() {
    local phase="$1"
    [[ ",$FLATLINE_GATES," == *",$phase,"* ]]
}
```

### 2.2 Auto-Escalation Classifier

**Location**: `spiral-harness.sh`, after profile resolution, uses task description + git state

```bash
_auto_escalate_profile() {
    local task="$1"
    local escalation_reason=""
    
    # Pattern-based escalation from task description
    if echo "$task" | grep -qiE 'auth|crypto|secret|token|key|cert|permission'; then
        escalation_reason="security-keyword-in-task"
    fi
    
    # File-pattern escalation from git state (if branch exists)
    if git diff "main...${BRANCH}" --name-only 2>/dev/null | \
        grep -qiE '(auth|crypto|secrets|\.claude/scripts|\.claude/protocols|schema\.json|migrations|deploy)'; then
        escalation_reason="security-path-in-diff"
    fi
    
    if [[ -n "$escalation_reason" && "$PIPELINE_PROFILE" != "full" ]]; then
        log "Auto-escalating profile: $PIPELINE_PROFILE → full (reason: $escalation_reason)"
        _record_action "CONFIG" "auto-escalation" "profile_escalated" "" "" "" 0 0 0 \
            "from=$PIPELINE_PROFILE to=full reason=$escalation_reason"
        PIPELINE_PROFILE="full"
        _resolve_profile
    fi
}
```

**Timing** (revised per Bridgebuilder HIGH-1): Both checks run at startup, BEFORE any Flatline gates:
- Task-keyword check: runs immediately from `$TASK` string
- Sprint-plan path check: if `grimoires/loa/sprint.md` exists, scan it for security-path references
- Post-implementation verification: after implementation, if git diff touches escalation paths that weren't caught at startup, log a WARNING to flight recorder (advisory, does not retroactively add gates)

This ensures escalation from `light` → `full` adds all three Flatline gates before any are skipped.

### 2.3 Deterministic Pre-Checks

**Location**: `spiral-evidence.sh`, new section before Finalization

**`_pre_check_implementation()`**:
- Validates: prd.md exists, sdd.md exists, sprint.md exists
- Validates: sprint.md contains `- [` checkbox pattern (AC present)
- Returns: 0 (pass) or 1 (fail)
- Records: `PRE_CHECK` action to flight recorder

**`_pre_check_review()`**:
- Validates: commits ahead of main > 0
- Validates: git diff non-empty
- Warns: no test files in diff (non-blocking)
- Blocks: secret scan match
- Secret scanning chain:
  1. `gitleaks detect --no-git --source <(git diff main...HEAD)` if available
  2. `trufflehog filesystem --directory . --since-commit main` if available
  3. Regex fallback: `grep -qiE '(password|secret|api_key|private_key)\s*[:=]\s*["\x27][^"\x27]{8,}'`
  4. Allowlist: skip matches found in `.claude/data/secret-scan-allowlist.txt`
- Returns: 0 (pass) or 1 (fail with issue count)
- Records: `PRE_CHECK` action to flight recorder with PASS/FAIL and detail

### 2.4 Cost Tracking & Rate-Limit Awareness

**Cost authority boundary** (revised per Bridgebuilder HIGH-2):
- **Harness** (`spiral-harness.sh`): owns within-cycle cost. Tracks via `_get_cumulative_cost()` in flight recorder. Enforces per-phase budget caps.
- **Orchestrator** (`spiral-orchestrator.sh`): owns cross-cycle cost. Reads harness cost from cycle outcome sidecar (`.run/cycles/{id}/cycle-cost.json`). Enforces spiral-level budget.
- **Reconciliation**: At cycle end, harness writes `cycle-cost.json` with total spend. Orchestrator reads it and adds to cumulative `budget.cost_cents` in spiral state.

```bash
# Harness writes at finalization:
jq -n --argjson cost "$total_cost" '{cycle_cost_usd: $cost, source: "flight_recorder"}' \
    > "$CYCLE_DIR/cycle-cost.json"
```

**Rate-limit tracking** (revised per Bridgebuilder CRITICAL-1):
- `flatline-orchestrator.sh` does not currently expose Anthropic response headers, and modifying it is out of scope for this cycle (not in FR-6 authorized file list).
- **This cycle**: Rate-limit awareness uses local token accounting only — cumulative cost from flight recorder as budget guard via existing `_check_budget()`.
- **Future cycle**: Modify `flatline-orchestrator.sh` to pass `--dump-header` and expose headers to caller. Then `_parse_rate_limit_headers()` can provide real-time data.
- The `rate_limit_exhausted` stopping condition is **deferred** — it requires header data. For now, `cost_budget_exhausted` serves as the budget safety net.

**What ships this cycle**: Local cost accounting, per-phase budget caps, cross-cycle cost reconciliation via sidecar file. No Anthropic header parsing.

### 2.5 Idempotent PR Creation

**Location**: `spiral-harness.sh`, replace current PR creation block

```bash
# Check if PR already exists for this branch
existing_pr=$(gh pr list --head "$BRANCH" --json number,url --jq '.[0].url // empty' 2>/dev/null)

if [[ -n "$existing_pr" ]]; then
    pr_url="$existing_pr"
    log "Reusing existing PR: $pr_url"
    # Update PR body with latest flight recorder summary
    local pr_number
    pr_number=$(echo "$pr_url" | grep -oE '[0-9]+$')
    gh api "repos/{owner}/{repo}/pulls/$pr_number" -X PATCH \
        -f body="Autonomous spiral cycle (updated). Profile: $PIPELINE_PROFILE. See flight recorder." \
        --jq '.html_url' 2>/dev/null || true
    _record_action "PR_CREATION" "gh-cli" "reused_pr" "" "" "" 0 0 0 "$pr_url"
else
    pr_url=$(gh pr create --title "..." --body "..." --draft 2>/dev/null || true)
    # ... existing creation logic
fi
```

### 2.6 Scheduler with flock Locking

**Location**: `spiral-scheduler.sh` (new file)

Uses the existing `flatline-lock.sh` pattern for flock-based locking:

```bash
LOCK_FILE="${PROJECT_ROOT:-.}/.run/spiral-scheduler.lock"
LOCK_TIMEOUT=60  # seconds

# Acquire exclusive lock
exec 200>"$LOCK_FILE"
if ! flock -w "$LOCK_TIMEOUT" 200; then
    # Check if lock holder is alive
    local holder_pid
    holder_pid=$(cat "$LOCK_FILE.pid" 2>/dev/null || echo "")
    if [[ -n "$holder_pid" ]] && ! kill -0 "$holder_pid" 2>/dev/null; then
        log "Stale lock from dead PID $holder_pid, reclaiming"
        flock -w 5 200 || { error "Cannot reclaim lock"; exit 3; }
    else
        log "Lock held by PID $holder_pid, exiting"
        exit 3
    fi
fi
echo "$$" > "$LOCK_FILE.pid"
trap 'rm -f "$LOCK_FILE.pid"; exec 200>&-' EXIT
```

### 2.7 Token Window Stopping Condition

**Location**: `spiral-orchestrator.sh`, alongside existing stopping conditions

```bash
check_token_window() {
    local strategy
    strategy=$(read_config "spiral.scheduling.strategy" "fill")
    [[ "$strategy" == "continuous" ]] && return 1  # Never triggers

    local window_end_utc
    window_end_utc=$(read_config "spiral.scheduling.windows[0].end_utc" "")
    [[ -z "$window_end_utc" ]] && return 1  # No window configured

    # Parse HH:MM into today's epoch (macOS + Linux compat)
    local today_date now_epoch end_epoch
    today_date=$(date -u +%Y-%m-%d)
    now_epoch=$(date -u +%s)
    end_epoch=$(date -u -d "${today_date}T${window_end_utc}:00Z" +%s 2>/dev/null \
        || date -u -j -f "%Y-%m-%dT%H:%MZ" "${today_date}T${window_end_utc}Z" +%s 2>/dev/null \
        || echo "0")
    [[ "$end_epoch" -eq 0 ]] && return 1
    [[ "$now_epoch" -ge "$end_epoch" ]]
}
```

**Evaluation order** in `evaluate_stopping_conditions()`:
1. `hitl_halt` (immediate operator override)
2. `quality_gate_failure` (both gates failed)
3. `cycle_budget_exhausted` (max cycles)
4. `flatline_convergence` (plateau)
5. `cost_budget_exhausted` (dollar limit)
6. `wall_clock_exhausted` (time limit)
7. `token_window_exhausted` (scheduling window end) — **new**

Note: `rate_limit_exhausted` is **deferred** — requires Anthropic header data from `flatline-orchestrator.sh` modification (future cycle).

### 2.8 Benchmark Comparison Tool

**Location**: `spiral-benchmark.sh` (new file)

**Input**: Two flight recorder JSONL paths
**Output**: Markdown comparison to stdout (redirect to file)

**Comparison dimensions**:

| Dimension | Source | Comparison Method |
|-----------|--------|-------------------|
| Phase durations | `duration_ms` per entry | Side-by-side table |
| Costs | `cost_usd` per entry | Sum + per-phase |
| Gate verdicts | `verdict` field | Present/absent/value |
| Blocker counts | Flatline `high=N blockers=M` | Numeric comparison |
| Retry counts | Count of same-phase entries | Numeric |
| Profile used | CONFIG action `profile=X` | String comparison |
| Evidence artifacts | Count of files in evidence dir | Numeric |
| Code output | Git diff stat (if branches available) | Lines added/removed |

**For PR #506 comparison**: Since #506 has no flight recorder (raw-Claude), the benchmark tool handles missing data gracefully — reports "N/A" for absent dimensions and highlights the gap.

### 2.9 Mechanical Dispatch in SKILL.md

The spiraling skill cannot execute bash directly — it's loaded as context for the agent. The mechanical dispatch works via explicit instruction at the top of SKILL.md:

```markdown
## DISPATCH GUARD — READ THIS FIRST

When this skill is invoked with a task, execute:

\```bash
.claude/scripts/spiral-harness.sh \
  --task "$TASK" \
  --cycle-dir .run/cycles/cycle-072 \
  --cycle-id cycle-072 \
  --branch feat/spiral-cost-opt-cycle-072 \
  --budget 15 \
  --profile standard
\```

Do NOT implement in conversation. Route through the harness.
```

**Why this is "mechanical enough"**: The agent reads the SKILL.md and sees an explicit bash command to execute. Combined with C-PROC-017 (NEVER rule) and the PR #507 guard, there are three independent layers that must all fail for bypass to occur. The negative test (AC-26) verifies the guard fires.

---

## 3. Data Model

### 3.1 Flight Recorder Extensions

New fields in flight recorder JSONL entries:

```jsonl
{"seq":1,"ts":"...","phase":"CONFIG","actor":"spiral-harness","action":"profile",
 "verdict":"profile=standard gates=sprint advisor=opus"}
{"seq":2,"ts":"...","phase":"CONFIG","actor":"auto-escalation","action":"profile_escalated",
 "verdict":"from=standard to=full reason=security-path-in-diff"}
{"seq":N,"ts":"...","phase":"GATE_prd","actor":"spiral-harness","action":"skipped",
 "verdict":"profile=standard"}
{"seq":N,"ts":"...","phase":"PRE_CHECK","actor":"evidence-gate","action":"review_ready",
 "verdict":"PASS"}
{"seq":N,"ts":"...","phase":"RATE_LIMIT","actor":"flatline-orchestrator","action":"header_parsed",
 "verdict":"remaining=450000 reset=2026-04-15T01:00:00Z source=header"}
```

### 3.2 Scheduling Config Schema

```yaml
spiral:
  harness:
    pipeline_profile: standard        # full | standard | light
    # ... existing fields ...
  scheduling:
    enabled: false                     # Master switch
    windows:
      - start_utc: "02:00"            # HH:MM UTC
        end_utc: "08:00"
        days: [mon, tue, wed, thu, fri]
    strategy: fill                     # fill | single | continuous
    max_cycles_per_window: 3
    rate_limit_warn_threshold_pct: 10  # Warn when tokens-remaining < 10%
```

---

## 4. Security Design

### 4.1 Secret Scanning

Detection chain (ordered by reliability):
1. **gitleaks** (if on PATH): `gitleaks detect --no-git --pipe < <(git diff main...HEAD)` — entropy + pattern-based, industry standard
2. **trufflehog** (if on PATH): `trufflehog git file://. --since-commit $(git merge-base main HEAD) --only-verified` — verified credentials only
3. **Regex fallback**: High-confidence patterns only — `(password|secret|api_key|private_key|aws_access_key_id)\s*[:=]\s*["'][^"']{8,}`
4. **Allowlist**: `.claude/data/secret-scan-allowlist.txt` — YAML format with governance fields:
   ```yaml
   - pattern: "test_api_key.*=.*fake"
     owner: "@janitooor"
     reason: "Test fixture, not a real key"
     expires: "2026-12-31"
   ```
   Expired entries are ignored with a warning. Entries without `owner` or `reason` are rejected.

### 4.2 System Zone Authorization

This cycle modifies files in `.claude/scripts/` (System Zone). Per PRD FR-6, authorization is **scoped to specific files** listed in the PRD. The harness `--append-system-prompt` override grants `.claude/scripts/` access to `claude -p` subprocesses only during this cycle.

### 4.3 Scheduler Security

- flock prevents concurrent execution
- PID tracking enables stale lock recovery
- Window bounds limit unattended execution time
- Cost budget, cycle budget, and rate-limit conditions provide defense-in-depth against runaway spend
- Trajectory logging records all scheduler events for audit

---

## 5. Test Design

### 5.1 Test Files

| File | Tests | Covers |
|------|-------|--------|
| `tests/unit/spiral-profiles.bats` | 8 | Profile resolution, auto-escalation, gate conditional, flight recorder logging |
| `tests/unit/spiral-prechecks.bats` | 7 | Pre-impl check, pre-review check, secret scanning, allowlist |
| `tests/unit/spiral-scheduler.bats` | 6 | Window check, continuous bypass, flock, resume detection, disabled config |
| `tests/unit/spiral-benchmark.bats` | 5 | Comparison output, missing data handling, dimension coverage |

**Total: 26 test cases** (exceeds AC-16 target of 20)

### 5.2 Test Strategy

Tests source the scripts being tested and validate function behavior in isolation:

```bash
# Example: profile resolution test
@test "standard profile resolves to sprint-only gates" {
    PIPELINE_PROFILE="standard"
    _resolve_profile
    [[ "$FLATLINE_GATES" == "sprint" ]]
}

@test "auto-escalation triggers on auth keyword in task" {
    PIPELINE_PROFILE="light"
    BRANCH="test-branch"
    _auto_escalate_profile "Implement authentication middleware"
    [[ "$PIPELINE_PROFILE" == "full" ]]
}

@test "pre-check review fails when no commits ahead" {
    # Mock git to return 0 commits ahead
    run _pre_check_review
    [[ "$status" -ne 0 ]]
}
```

### 5.3 Negative Test: Dispatch Guard (AC-26)

Verify that the dispatch guard text is present in SKILL.md and contains the expected routing instruction:

```bash
@test "SKILL.md dispatch guard routes to spiral-harness.sh" {
    local skill_md=".claude/skills/spiraling/SKILL.md"
    grep -q "DISPATCH GUARD" "$skill_md"
    grep -q "spiral-harness.sh" "$skill_md"
    grep -q "MUST NOT implement code directly" "$skill_md"
}
```

---

## 6. Error Handling

| Error | Handler | Recovery |
|-------|---------|----------|
| Profile unknown | Fall back to `standard`, log warning | Automatic |
| Pre-check fails | Record failure, skip phase, exit 1 | Operator fixes issue, re-runs |
| Flatline gate timeout | Record skip, continue pipeline | Advisory only |
| Secret detected | Block review, exit 1 | Operator removes secret, re-runs |
| Lock contention | Wait up to 60s, then stale-check | Reclaim stale lock or exit 3 |
| 429 from Flatline API | Exponential backoff (existing retry.py) | Automatic, max 3 retries |
| PR already exists | Reuse PR, update body | Automatic |
| gitleaks/trufflehog not found | Fall back to regex | Automatic, logged |
| Window end reached | Graceful halt at phase boundary | Resume next window |

---

## 7. Migration Notes

**Backward compatible.** All new features are opt-in:
- `pipeline_profile: standard` is the default — matches current behavior minus PRD/SDD Flatline (which the benchmark proved are insurance, not load-bearing)
- `scheduling.enabled: false` is the default — no scheduling unless configured
- Pre-checks are additive — they prevent wasted spend but don't change the happy path
- Rate-limit tracking is passive — logs data but doesn't change behavior unless threshold exceeded
- Benchmark tool is standalone — doesn't affect any existing workflow
