# Sprint Plan: Cycle-072 — Spiral Cost Optimization + Mechanical Dispatch

**PRD**: `grimoires/loa/prd.md`
**SDD**: `grimoires/loa/sdd.md`
**Date**: 2026-04-15

---

## Flatline AUTO-INTEGRATED Findings

Integrated from PRD Flatline (6 HIGH_CONSENSUS + 5 accepted blockers) and SDD Flatline (6 HIGH_CONSENSUS + 4 accepted blockers). Key impacts on sprint:

| Finding | Sprint Impact |
|---------|--------------|
| Auto-escalation at startup, not post-impl (HIGH-1) | T1.2 revised |
| Cost authority boundary (HIGH-2) | T1.4 added |
| Rate-limit headers deferred (CRITICAL-1) | T1.4 descoped to local accounting |
| Idempotent PR creation (SKP-006) | T1.3 added |
| Secret scanning with gitleaks/allowlist governance (SKP-007) | T2.2 enhanced |
| flock-based locking (IMP-005) | T3.1 enhanced |

---

## Sprint 1: Pipeline Profiles + Pre-Checks + Harness Enhancements

**Goal**: Conditional pipeline, deterministic pre-checks, idempotent PR creation, cost sidecar — the highest-impact cost reduction features.

### Task 1.1: Pipeline Profile Resolver + Conditional Flatline

**Files**: `.claude/scripts/spiral-harness.sh` (modify)
**Description**: Add `full`/`standard`/`light` profile system with `_resolve_profile()`, `_should_run_flatline()`, `--profile` CLI flag. Modify `main()` to conditionally skip Flatline gates based on profile. Log profile and skipped gates to flight recorder.

**AC**:
- [ ] `_resolve_profile` sets correct `FLATLINE_GATES` for each profile
- [ ] `_should_run_flatline "sprint"` returns true for `standard`, true for `full`, false for `light`
- [ ] `_should_run_flatline "prd"` returns false for `standard`, true for `full`, false for `light`
- [ ] `light` profile sets `ADVISOR_MODEL` to `$EXECUTOR_MODEL` (Sonnet reviews)
- [ ] Unknown profile falls back to `standard` with logged warning
- [ ] `--profile` CLI flag overrides config default
- [ ] CONFIG action in flight recorder logs profile, gates, advisor model

---

### Task 1.2: Auto-Escalation Classifier

**Files**: `.claude/scripts/spiral-harness.sh` (modify)
**Depends on**: T1.1
**Description**: `_auto_escalate_profile()` checks task keywords and sprint plan references at startup. Escalates `light`/`standard` to `full` when security/system/schema paths detected. Conservative default: if diff unavailable at startup, escalate `light` → `standard`.

**AC**:
- [ ] Task keyword "auth" or "crypto" or "secret" triggers escalation to `full`
- [ ] Sprint plan reference to `.claude/scripts/` triggers escalation
- [ ] Escalation logged to flight recorder with `from`, `to`, `reason`
- [ ] When diff unavailable, `light` escalates to `standard` (conservative default)
- [ ] Explicit `--profile` overrides auto-escalation (operator has final say) with `escalation_overridden` logged to flight recorder (Flatline SKP-002 audit trail)
- [ ] Post-implementation: if diff touches escalation paths missed at startup, log WARNING

---

### Task 1.3: Idempotent PR Creation

**Files**: `.claude/scripts/spiral-harness.sh` (modify)
**Description**: Before `gh pr create`, check if PR already exists for the branch. Reuse if present, create if not. Log `reused_pr` or `create_pr` action.

**AC**:
- [ ] `gh pr list --head $BRANCH` check runs before creation
- [ ] Existing PR reused with updated body
- [ ] New PR created when none exists
- [ ] Flight recorder distinguishes `reused_pr` from `create_pr`

---

### Task 1.4: Cost Sidecar + Cross-Cycle Reconciliation

**Files**: `.claude/scripts/spiral-harness.sh` (modify), `.claude/scripts/spiral-evidence.sh` (modify)
**Description**: At cycle end, harness writes `cycle-cost.json` sidecar with total spend. Atomic write (write to tmp, rename). Orchestrator reads this for cross-cycle budget enforcement.

**AC**:
- [ ] `cycle-cost.json` written atomically at cycle finalization
- [ ] Contains `cycle_cost_usd` and `source: "flight_recorder"`
- [ ] Missing/malformed file treated as UNKNOWN — blocks new cycles unless `--force-cost-override` flag used (fail-closed per Flatline SKP-001)
- [ ] Override logged to flight recorder with `cost_override` action

---

## Sprint 2: Deterministic Pre-Checks + Secret Scanning

**Goal**: Zero-cost fail-fast before expensive LLM sessions.

### Task 2.1: Pre-Implementation Check

**Files**: `.claude/scripts/spiral-evidence.sh` (modify)
**Description**: `_pre_check_implementation()` validates planning artifacts exist before $5 implementation session.

**AC**:
- [ ] Fails when `grimoires/loa/prd.md` missing
- [ ] Fails when `grimoires/loa/sdd.md` missing
- [ ] Fails when `grimoires/loa/sprint.md` missing
- [ ] Warns when sprint.md has no checkbox pattern (non-blocking)
- [ ] Records PRE_CHECK action to flight recorder with PASS/FAIL

---

### Task 2.2: Pre-Review Check + Secret Scanning

**Files**: `.claude/scripts/spiral-evidence.sh` (modify)
**Description**: `_pre_check_review()` validates implementation output before $2-4 review/audit. Secret scanning chain: gitleaks → trufflehog → regex fallback → allowlist.

**AC**:
- [ ] Fails when no commits ahead of main
- [ ] Fails when git diff is empty
- [ ] Warns when no test files in diff (non-blocking)
- [ ] Blocks when secret pattern matched (after allowlist check)
- [ ] Uses `gitleaks` if on PATH, falls back to regex
- [ ] Allowlist at `.claude/data/secret-scan-allowlist.yaml` (YAML with owner/reason/expires per SDD 4.1)
- [ ] Expired allowlist entries ignored with warning
- [ ] Records PRE_CHECK action with PASS/FAIL and detail

---

## Sprint 3: Off-Hours Scheduling

**Goal**: Run spiral cycles during AFK/sleep windows.

### Task 3.1: Scheduler Wrapper

**Files**: `.claude/scripts/spiral-scheduler.sh` (new)
**Description**: Cron/trigger entry point with flock-based locking, window check, resume/start logic. Three strategies: `fill`, `single`, `continuous`.

**AC**:
- [ ] Exits 2 when `scheduling.enabled: false`
- [ ] Exits 2 when `spiral.enabled: false`
- [ ] flock-based exclusive lock on `.run/spiral-scheduler.lock`
- [ ] Stale lock reclaimed only when holder PID dead AND lock older than 5 minutes (conservative, per Flatline SKP-004)
- [ ] Lock file includes PID + hostname + timestamp fingerprint
- [ ] `_in_window()` returns true when within configured hours
- [ ] `_in_window()` always returns true for `strategy: continuous`
- [ ] Resumes HALTED spiral via `--resume`
- [ ] Starts new spiral when previous COMPLETED/FAILED
- [ ] Exits 3 when spiral already RUNNING
- [ ] Trajectory events logged: `scheduler_started`, `scheduler_resumed`, etc.

---

### Task 3.2: Token Window Stopping Condition

**Files**: `.claude/scripts/spiral-orchestrator.sh` (modify)
**Description**: `check_token_window()` — 7th stopping condition. Halts when current time passes window end. Bypassed by `strategy: continuous`.

**AC**:
- [ ] Returns STOP (0) when past `end_utc`
- [ ] Returns CONTINUE (1) when no window configured
- [ ] Returns CONTINUE (1) when `strategy: continuous`
- [ ] Handles both GNU date and BSD date formats
- [ ] Wired into `evaluate_stopping_conditions()` after `wall_clock_exhausted`

---

## Sprint 4: Benchmark Framework + Comparison Report

**Goal**: Data-driven comparison of raw-Claude vs harness output.

### Task 4.1: Benchmark Comparison Tool

**Files**: `.claude/scripts/spiral-benchmark.sh` (new)
**Description**: Reads two flight recorder JSONL files, produces Markdown comparison table. Handles missing data gracefully (for PR #506 which has no flight recorder).

**AC**:
- [ ] `--a` and `--b` flags accept flight recorder paths
- [ ] Outputs Markdown table to stdout
- [ ] Compares: phase durations, costs, gate verdicts, blocker counts, retry counts, profile
- [ ] Missing flight recorder → "N/A" for all dimensions
- [ ] `bash -n` passes

---

### Task 4.2: PR #506 vs Harness Comparison Report

**Files**: `grimoires/loa/reports/spiral-benchmark-comparison.md` (new)
**Description**: Produce comparison report between this cycle's harness output and the raw-Claude PR #506.

**AC**:
- [ ] Report covers: evidence trail (present/absent), code quality, cost, time, Flatline findings
- [ ] Dimensions from SDD Section 2.8
- [ ] Highlights what the harness adds that raw-Claude didn't have

---

## Sprint 5: Documentation + Config + Dispatch Guard + Tests

**Goal**: Complete the package — docs, config, SKILL.md update, test suite.

### Task 5.1: SKILL.md Mechanical Dispatch Update

**Files**: `.claude/skills/spiraling/SKILL.md` (modify), `.claude/skills/spiraling/index.yaml` (modify)
**Description**: Update dispatch guard with explicit harness invocation command. Add `task` input and `profile` input to index.yaml. Document profiles, scheduling, benchmark.

**AC**:
- [ ] Dispatch guard contains explicit `spiral-harness.sh` command with all flags
- [ ] index.yaml has `task` input (string) and `profile` input (string, default: standard)
- [ ] Pipeline profiles documented with table
- [ ] Scheduling documented with config example
- [ ] All three strategies documented

---

### Task 5.2: Config Updates

**Files**: `.loa.config.yaml` (modify), `.loa.config.yaml.example` (modify)
**Description**: Add pipeline_profile, scheduling config, rate_limit_warn_threshold_pct.

**AC**:
- [ ] `.loa.config.yaml` has `pipeline_profile: standard` and `scheduling:` block
- [ ] `.loa.config.yaml.example` has full documented config with comments
- [ ] `yq` reads all new config keys correctly

---

### Task 5.3: Test Suite (26 cases)

**Files**: `tests/unit/spiral-profiles.bats` (new), `tests/unit/spiral-prechecks.bats` (new), `tests/unit/spiral-scheduler.bats` (new), `tests/unit/spiral-benchmark.bats` (new)

**Test cases**:

| # | File | Test | AC |
|---|------|------|-----|
| 1 | spiral-profiles.bats | standard profile resolves to sprint-only gates | AC-3 |
| 2 | spiral-profiles.bats | full profile resolves to all gates | AC-5 |
| 3 | spiral-profiles.bats | light profile resolves to no gates + Sonnet advisor | AC-4 |
| 4 | spiral-profiles.bats | unknown profile falls back to standard | AC-3 |
| 5 | spiral-profiles.bats | --profile CLI overrides config default | AC-3 |
| 6 | spiral-profiles.bats | auto-escalation triggers on auth keyword | AC-21 |
| 7 | spiral-profiles.bats | auto-escalation triggers on .claude/scripts path | AC-21 |
| 8 | spiral-profiles.bats | explicit --profile overrides auto-escalation | AC-21 |
| 9 | spiral-prechecks.bats | pre-impl fails when prd.md missing | AC-6 |
| 10 | spiral-prechecks.bats | pre-impl fails when sprint.md missing | AC-6 |
| 11 | spiral-prechecks.bats | pre-impl passes when all artifacts exist | AC-6 |
| 12 | spiral-prechecks.bats | pre-review fails when no commits ahead | AC-7 |
| 13 | spiral-prechecks.bats | pre-review fails on secret pattern match | AC-8 |
| 14 | spiral-prechecks.bats | pre-review passes with allowlist exclusion | AC-22 |
| 15 | spiral-prechecks.bats | pre-review warns but passes without test files | AC-7 |
| 16 | spiral-scheduler.bats | exits 2 when scheduling disabled | AC-9 |
| 17 | spiral-scheduler.bats | exits 2 when spiral disabled | AC-9 |
| 18 | spiral-scheduler.bats | _in_window returns true during window | AC-11 |
| 19 | spiral-scheduler.bats | _in_window returns false outside window | AC-11 |
| 20 | spiral-scheduler.bats | _in_window returns true for continuous strategy | AC-12 |
| 21 | spiral-scheduler.bats | check_token_window stops when past end | AC-11 |
| 22 | spiral-scheduler.bats | check_token_window continues when no window | AC-12 |
| 23 | spiral-benchmark.bats | produces markdown output from two recorders | AC-14 |
| 24 | spiral-benchmark.bats | handles missing flight recorder gracefully | AC-14 |
| 25 | spiral-benchmark.bats | comparison includes all required dimensions | AC-14 |
| 26 | spiral-profiles.bats | SKILL.md dispatch guard contains harness route | AC-26 |

---

### Task 5.4: Syntax Validation

**Description**: All scripts pass `bash -n`. All YAML passes `yq` validation.

**AC**:
- [ ] `bash -n` passes on all 5 scripts (harness, evidence, orchestrator, scheduler, benchmark)
- [ ] `yq eval '.spiral.harness.pipeline_profile'` reads correctly from both config files

---

## Summary

| Sprint | Tasks | New/Modified Files | Estimated Lines |
|--------|-------|-------------------|-----------------|
| 1 | 4 | 2 modified | +200 |
| 2 | 2 | 1 modified | +80 |
| 3 | 2 | 1 new, 1 modified | +200 |
| 4 | 2 | 1 new, 1 new report | +200 |
| 5 | 4 | 6 modified, 4 new test files | +550 |
| **Total** | **14 tasks** | **13 files** | **~1230 lines** |
