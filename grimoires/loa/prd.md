# Product Requirements Document: Spiral Cost Optimization + Mechanical Dispatch

**Date**: 2026-04-15
**Cycle**: 072
**Status**: Flatline-reviewed
**Depends on**: v1.88.0 (spiral harness shipped), PR #507 (dispatch guard merged)

---

## Flatline AUTO-INTEGRATED Findings

These findings were accepted during Flatline PRD review (100% model agreement, 3-model panel) and are incorporated into the requirements below.

| ID | Finding | Impact | Resolution |
|----|---------|--------|------------|
| IMP-001 | Gate failure behavior must be explicitly defined | Runtime determinism | FR-2: added retry/abort state transitions per profile |
| IMP-002 | Target costs need hard caps with live metering | Unattended cost safety | FR-4: added per-cycle and per-window hard caps |
| IMP-003 | Secret check needs concrete detector + false-positive handling | Security reliability | FR-3: use gitleaks/trufflehog if available, regex fallback, allowlist |
| IMP-005 | PID-only guards fragile — need lock lifecycle + stale recovery | Scheduler reliability | FR-4: flock-based locking with lease timeout, stale lock recovery |
| IMP-007 | Unattended runs need event notifications | Operational visibility | FR-4: log events to trajectory, optional notification hook |
| IMP-010 | Benchmark needs controlled comparison criteria | Decision quality | FR-5: defined comparison dimensions and statistical controls |
| SKP-002 | Quality target incompatible with profiles skipping gates | Quality risk | FR-2: auto-escalation rules + per-profile quality SLOs |
| SKP-003 | Task complexity classification undefined | Misrouting risk | FR-2: file-pattern classifier for automatic profile escalation |
| SKP-004 | Rate-limit headers missing on some call paths | False confidence | FR-4: fallback local token accounting when headers absent |
| SKP-006 | Resume/idempotency underspecified for HALTED spirals | Duplicate PR risk | FR-4: idempotent PR creation + run IDs + replay-safe checkpoints |
| SKP-007 | Secret scanning regex-only is insufficient | Security gap | FR-3: gitleaks/trufflehog integration with regex fallback |

**Overridden**: SKP-001 (mechanical dispatch is still soft-control) — platform limitation. Claude Code has no PreSkillExecution hook. Three-layer defense (SKILL.md + C-PROC-017 + PR #507 guard) is the best available within current platform constraints. Negative tests added to AC to prove guard fires.

---

## Problem Statement

Three problems, all load-bearing:

1. **Quality gate bypass**: `/spiraling` loads as context, not as an orchestrator. When invoked with a task, the agent can (and did, PR #506) implement code directly in conversation — bypassing Flatline, independent Review, independent Audit, Bridgebuilder, and flight recorder. The dispatch guard (PR #507) adds agent-level instructions, but the only reliable fix is mechanical dispatch.

2. **Cost**: A single spiral cycle costs ~$15-20 ($12 harness budget + $3-4 Flatline API). For a 3-cycle spiral, that's $45-60. Every cycle runs the full 9-phase pipeline regardless of task complexity. A simple flag addition gets the same treatment as an architectural refactoring.

3. **Idle time**: The user has dead windows (AFK, asleep) where Claude could be running against included token allowances instead of burning paid API overage. No scheduling infrastructure exists to utilize these windows.

## Goals & Success Metrics

| Goal | Metric | Target |
|------|--------|--------|
| Mechanical dispatch | `/spiraling` with task routes through `spiral-harness.sh` as subprocess | 100% — never falls back to in-conversation implementation |
| Cost reduction (standard) | Per-cycle cost for typical feature work | $10-13 (was $15-20), >=30% reduction |
| Cost reduction (light) | Per-cycle cost for bug fixes/flags | $6-8 (was $15-20), >=55% reduction |
| Quality preservation | Review + Audit APPROVED rate | Same as benchmark (100% first-try for bounded tasks) |
| Off-hours utilization | Token spend during configured sleep windows | >0 (currently 0) |
| Rate limit awareness | Harness reads Anthropic rate-limit headers | Tokens-remaining tracked per API call |
| Benchmark comparison | Raw-Claude (#506) vs harness output | Comparison report with evidence diff |
| Test coverage | BATS tests for new harness features | >=20 test cases |

## Assumptions

- The spiral harness (`spiral-harness.sh`, `spiral-evidence.sh`) is stable and proven (7 E2E runs, 2 benchmark runs)
- Anthropic API rate-limit response headers (`anthropic-ratelimit-tokens-remaining`, `anthropic-ratelimit-tokens-reset`) are available on all API responses including from Flatline orchestrator calls
- Claude Code's `CronCreate` and `RemoteTrigger` tools are functional for scheduling
- The user is on Anthropic API Tier 2+ (based on usage patterns) with Claude Team account for interactive use

## Non-Goals

- Modifying Flatline orchestrator internals for prompt caching (deferred to follow-up cycle — saves ~$1.15/cycle but requires API call restructuring)
- Replacing Flatline's 3-model panel with fewer models (quality tradeoff not justified)
- Building a custom token billing dashboard (Anthropic Console covers this)

---

## Functional Requirements

### FR-1: Mechanical Dispatch (Primary)

When `/spiraling` is invoked with a task:

1. The skill MUST invoke `spiral-harness.sh` as a subprocess, not implement in conversation
2. The skill MUST pass the task description, profile, and budget to the harness
3. The skill MUST surface the flight recorder summary and PR URL back to the user
4. If the harness is unavailable or `spiral.harness.enabled: false`, the skill MUST refuse with an error — it MUST NOT fall back to in-conversation implementation
5. Research-only invocations (no task, just questions about spiral state) remain conversational

**Acceptance**: Invoke `/spiraling` with a task -> harness runs -> flight recorder produced -> PR created -> Review+Audit artifacts on PR. Agent never writes application code in conversation.

### FR-2: Pipeline Profiles

Three profiles that match pipeline intensity to task complexity:

| Profile | Flatline Gates | Advisor Model | Budget | Use For |
|---------|----------------|---------------|--------|---------|
| `full` | PRD + SDD + Sprint | Opus | $15 | Architecture, security-critical |
| `standard` | Sprint only | Opus | $12 | Most features (default) |
| `light` | None | Sonnet | $8 | Bug fixes, flags, config |

**Configuration**:
```yaml
spiral.harness.pipeline_profile: standard  # default
```

**CLI override**: `--profile light` on `spiral-harness.sh`

**Auto-escalation rules** (Flatline SKP-002, SKP-003):
Profile auto-escalates to `full` when any of these file patterns appear in the task or diff:
- Security paths: `**/auth/**`, `**/crypto/**`, `**/secrets/**`, `**/*token*`
- System Zone: `.claude/scripts/**`, `.claude/protocols/**`
- Schema changes: `**/*.schema.json`, `**/migrations/**`
- Infrastructure: `**/deploy/**`, `**/*.yaml` (CI/CD configs)

Auto-escalation is advisory (logged to flight recorder) — operator can override with explicit `--profile`.

**Per-profile quality SLOs** (Flatline SKP-002):

| Profile | Quality Target | Acceptable Failure Rate |
|---------|---------------|------------------------|
| `full` | APPROVED first try (Review + Audit) | 0% — retry on failure |
| `standard` | APPROVED first try (Review + Audit) | 10% — one retry allowed |
| `light` | APPROVED within 2 tries | 20% — two retries allowed |

**Gate failure behavior** (Flatline IMP-001):
- Gate fails → retry up to `max_phase_retries` (default 3)
- All retries exhausted → circuit breaker fires → cycle HALTED with `gate_failure` reason
- Flight recorder logs each retry with attempt number and failure detail

**Acceptance**:
- `standard` profile skips PRD/SDD Flatline gates, runs Sprint Flatline
- `light` profile skips all Flatline gates and uses Sonnet for Review/Audit
- `full` profile runs all gates (regression: identical to current behavior)
- Auto-escalation triggers when security/system/schema paths detected
- Profile logged to flight recorder for audit trail
- Skipped gates recorded as `skipped` actions in flight recorder

### FR-3: Deterministic Pre-Checks

Bash pre-checks before expensive LLM sessions to fail fast at $0:

**Pre-implementation check** (`_pre_check_implementation`):
- `grimoires/loa/prd.md` exists
- `grimoires/loa/sdd.md` exists
- `grimoires/loa/sprint.md` exists
- Sprint plan contains acceptance criteria checkboxes

**Pre-review check** (`_pre_check_review`):
- Branch has commits ahead of main
- Git diff is non-empty
- Tests exist in the diff (warn, not block)
- Secret scanning (Flatline IMP-003, SKP-007):
  - If `gitleaks` or `trufflehog` available on PATH: run against diff (authoritative)
  - Fallback: regex patterns for `password|secret|api_key|private_key` with value assignment
  - Allowlist: `.claude/data/secret-scan-allowlist.txt` (one pattern per line) for known false positives
  - Block on match, log finding to flight recorder

**Acceptance**: Pre-check failure prevents the subsequent LLM invocation. Failure reason logged to flight recorder. Cost avoided: $2-4 per failed cycle.

### FR-4: Off-Hours Scheduling

**Scheduler wrapper** (`spiral-scheduler.sh`):
- Entry point for cron/trigger invocations
- Checks for HALTED spiral to resume, or starts new
- Locking (Flatline IMP-005): `flock`-based exclusive lock on `.run/spiral-scheduler.lock` with 60-second stale timeout. If lock holder PID is dead, reclaim lock automatically. Prevents double execution across concurrent cron triggers.
- Window-aware: only runs within configured time bounds (unless `strategy: continuous`)
- Event notification (Flatline IMP-007): log scheduler events to trajectory JSONL (`scheduler_started`, `scheduler_resumed`, `scheduler_halted`, `scheduler_window_expired`)

**Token window stopping condition** (`check_token_window`):
- New stopping condition in `spiral-orchestrator.sh`
- Halts gracefully when current time passes configured window end
- Skipped entirely when `strategy: continuous`
- Spiral resumes next window via `--resume`

**Rate-limit header tracking**:
- Parse `anthropic-ratelimit-tokens-remaining` and `anthropic-ratelimit-tokens-reset` from Flatline API responses
- Log to flight recorder per Flatline gate call
- When tokens-remaining drops below configurable threshold (default 10%), emit warning
- When tokens-remaining reaches 0, halt cycle gracefully (new stopping condition: `rate_limit_exhausted`)
- Fallback (Flatline SKP-004): when headers absent (e.g., `claude -p` subprocess paths), use local token accounting from flight recorder cumulative cost as budget guard. Log `rate_limit_source: "estimated"` vs `"header"` in flight recorder.

**Idempotent PR creation** (Flatline SKP-006):
- Before `gh pr create`, check if PR already exists for the branch: `gh pr list --head $BRANCH --json number`
- If PR exists, reuse it (update body with latest flight recorder summary)
- If not, create new
- Flight recorder logs run ID for each cycle to prevent replay confusion
- Resume from HALTED verifies last action sequence number in flight recorder before continuing

**Scheduling strategies**:

| Strategy | Behavior |
|----------|----------|
| `fill` | Run cycles within configured window, halt at `end_utc` |
| `single` | Run one cycle per window |
| `continuous` | Ignore window — run until cost/cycles/wall-clock/HITL/rate-limit stops it |

**Configuration**:
```yaml
spiral:
  scheduling:
    enabled: false
    windows:
      - start_utc: "02:00"
        end_utc: "08:00"
        days: [mon, tue, wed, thu, fri]
    strategy: fill
    max_cycles_per_window: 3
    rate_limit_warn_threshold_pct: 10
```

**Acceptance**:
- Cron fires at window start -> scheduler resumes or starts spiral -> halts at window end -> resumes next window
- `strategy: continuous` ignores windows, runs indefinitely
- Rate-limit headers parsed and logged per Flatline API call
- Rate-limit exhaustion triggers graceful halt

### FR-5: Benchmark Framework

**Flight recorder comparison tool** (`spiral-benchmark.sh`):
- Compares two flight recorder JSONL files side-by-side
- Reports: phase durations, costs, gate verdicts, blocker counts, retry counts
- Produces Markdown comparison table

**PR #506 vs harness comparison**:
- This cycle's harness output compared against the raw-Claude PR #506 code
- Comparison report produced as `grimoires/loa/reports/spiral-benchmark-comparison.md`
- Dimensions: quality gate evidence (present/absent), code diff, cost, time, Flatline findings

**Acceptance**: Running `spiral-benchmark.sh --a .run/cycles/X --b .run/cycles/Y` produces a Markdown comparison report. Comparison of this cycle vs PR #506 is included in the cycle deliverables.

### FR-6: System Zone Authorization

All scripts in scope are in `.claude/scripts/` (System Zone). This PRD grants **explicit cycle-level System Zone write authorization** for:
- `.claude/scripts/spiral-harness.sh` (modify)
- `.claude/scripts/spiral-evidence.sh` (modify)
- `.claude/scripts/spiral-orchestrator.sh` (modify)
- `.claude/scripts/spiral-scheduler.sh` (new)
- `.claude/scripts/spiral-benchmark.sh` (new)
- `.claude/skills/spiraling/SKILL.md` (modify)
- `.claude/skills/spiraling/index.yaml` (modify if needed)

---

## Acceptance Criteria

- [ ] AC-1: `/spiraling` with task invokes `spiral-harness.sh` — three-layer soft enforcement (SKILL.md + C-PROC-017 + guard) with negative test proving guard fires
- [ ] AC-2: `/spiraling` without task remains conversational (status queries, research)
- [ ] AC-3: `spiral-harness.sh --profile standard` skips PRD/SDD Flatline, runs Sprint Flatline
- [ ] AC-4: `spiral-harness.sh --profile light` skips all Flatline, uses Sonnet advisor
- [ ] AC-5: `spiral-harness.sh --profile full` runs all gates (regression test)
- [ ] AC-6: `_pre_check_implementation` fails when planning artifacts missing
- [ ] AC-7: `_pre_check_review` fails when no commits ahead of main
- [ ] AC-8: `_pre_check_review` fails when secrets detected in diff
- [ ] AC-9: `spiral-scheduler.sh` exits 2 when scheduling disabled
- [ ] AC-10: `spiral-scheduler.sh` resumes HALTED spiral
- [ ] AC-11: `check_token_window` returns STOP when past window end
- [ ] AC-12: `check_token_window` returns CONTINUE when `strategy: continuous`
- [ ] AC-13: Cost tracking uses local accounting with cross-cycle reconciliation via sidecar file (rate-limit headers deferred — requires flatline-orchestrator.sh modification)
- [ ] AC-14: `spiral-benchmark.sh` produces Markdown comparison from two flight recorders
- [ ] AC-15: Comparison report: this cycle vs PR #506 raw output
- [ ] AC-16: >=20 BATS test cases covering profiles, pre-checks, scheduling, benchmark
- [ ] AC-17: `.loa.config.yaml.example` updated with all new config sections
- [ ] AC-18: SKILL.md documents mechanical dispatch, profiles, scheduling
- [ ] AC-19: Flight recorder logs profile, skipped gates, rate-limit data
- [ ] AC-20: All scripts pass `bash -n` syntax check
- [ ] AC-21: Auto-escalation triggers `full` profile when security/system paths detected in diff
- [ ] AC-22: Secret scanning uses gitleaks/trufflehog when available, regex fallback
- [ ] AC-23: Scheduler uses flock-based locking with stale lock recovery
- [ ] AC-24: PR creation is idempotent — reuses existing PR for branch if present
- [ ] AC-25: Harness writes cycle-cost.json sidecar; orchestrator reads it for cross-cycle budget
- [ ] AC-26: Negative test: dispatch guard prevents in-conversation implementation when task provided

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Anthropic rate-limit headers not available from `claude -p` subprocess | Harness calls Flatline API directly (headers available). For `claude -p` subprocess calls, rate-limit headers are not directly exposed — track via Flatline responses only. |
| Scheduling requires active Claude session (CronCreate) or remote trigger | Document both options. CronCreate for "leave terminal open overnight", RemoteTrigger for truly offline execution. |
| Mechanical dispatch from SKILL.md may not force subprocess execution | The SKILL.md instructs the agent to execute the bash script. If the agent doesn't comply, the C-PROC-017 constraint fires as a second layer. Three-layer defense: SKILL.md instruction > constraint > PR #507 guard. |
| Profile selection wrong for task complexity | Default to `standard`. User can override with `--profile`. Flight recorder logs profile for post-hoc analysis. |

---

## Sources

- [Anthropic Rate Limits Documentation](https://platform.claude.com/docs/en/api/rate-limits) — response headers for tokens-remaining
- [Anthropic Usage API Feature Request](https://github.com/anthropics/claude-quickstarts/issues/276) — no dedicated endpoint exists
- PR #506 (closed) — raw-Claude benchmark artifact
- PR #507 (merged) — dispatch guard (agent-level fix)
- `grimoires/loa/proposals/spiral-cost-optimization.md` — design proposal
- `grimoires/loa/reports/spiral-harness-benchmark-report.md` — Sonnet vs Opus benchmark data
- `.claude/plans/sorted-watching-eclipse.md` — approved plan from research session
