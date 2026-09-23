# run-mode state-file schemas (cycle-121 split from SKILL.md)

Exact JSON shapes for .run/ state files. SKILL.md's procedures reference these by section name; write files with these exact keys.

## run-state-schema

```json
{
  "run_id": "run-20260119-abc123",
  "target": "sprint-1",
  "branch": "feature/sprint-1",
  "state": "JACK_IN",
  "phase": "INIT",
  "timestamps": {
    "started": "2026-01-19T10:00:00Z",
    "last_activity": "2026-01-19T11:30:00Z"
  },
  "cycles": {
    "current": 0,
    "limit": 20,
    "history": []
  },
  "metrics": {
    "files_changed": 0,
    "files_deleted": 0,
    "commits": 0,
    "findings_fixed": 0
  },
  "options": {
    "max_cycles": 20,
    "timeout_hours": 8,
    "dry_run": false,
    "local_mode": false,
    "confirm_push": false,
    "push_mode": "AUTO"
  },
  "completion": {
    "pushed": false,
    "pr_created": false,
    "pr_url": null,
    "skipped_reason": null
  }
}
```

## circuit-breaker-schema

```json
{
  "state": "CLOSED",
  "triggers": {
    "same_issue": {"count": 0, "threshold": 3, "last_hash": null},
    "no_progress": {"count": 0, "threshold": 5},
    "cycle_count": {"current": 0, "limit": 20},
    "timeout": {"started": "2026-01-19T10:00:00Z", "limit_hours": 8}
  },
  "history": []
}
```

## red-team-code-state

```json
{
  "red_team_code": {
    "cycles": 0,
    "max_cycles": 2,
    "findings_total": 0,
    "divergences_found": 0,
    "last_findings_hash": null
  }
}
```

## sprint-plan-state-schema

```json
{
  "schema_version": 2,
  "plan_id": "plan-20260119-abc123",
  "branch": "feature/release",
  "state": "RUNNING",
  "timestamps": {"started": "2026-01-19T10:00:00Z", "last_activity": "2026-01-19T14:30:00Z"},
  "checkpoint": {"sprint": "sprint-3", "task": "bd-a1b2", "phase": "IMPLEMENT", "ts": "2026-01-19T14:30:00Z"},
  "sprints": {
    "total": 4,
    "completed": 2,
    "current": "sprint-3",
    "list": [
      {"id": "sprint-1", "status": "completed", "cycles": 2},
      {"id": "sprint-2", "status": "completed", "cycles": 3},
      {"id": "sprint-3", "status": "in_progress", "cycles": 1},
      {"id": "sprint-4", "status": "pending"}
    ]
  },
  "options": {"from": 1, "to": 4, "max_cycles": 20, "timeout_hours": 8},
  "metrics": {"total_cycles": 6, "total_files_changed": 45, "total_findings_fixed": 12}
}
```

`schema_version` 2 (cycle-125 FR-3) adds `checkpoint` — written only by
`.claude/scripts/run-checkpoint.sh write` (atomic, locked); `task` is the last CLOSED bead
(`null` for a phase-only checkpoint). Readers accept 1 and 2; a missing or discarded checkpoint
means sprint granularity (resume at the first open bead of `sprints.current`).

## bug-state-schema

```json
{
  "schema_version": 1,
  "bug_id": "20260211-a3f2b1",
  "bug_title": "Login fails with + in email",
  "sprint_id": "sprint-bug-3",
  "state": "IMPLEMENTING",
  "mode": "autonomous",
  "created_at": "2026-02-11T10:00:00Z",
  "updated_at": "2026-02-11T10:30:00Z",
  "circuit_breaker": {
    "cycle_count": 1,
    "same_issue_count": 0,
    "no_progress_count": 0,
    "last_finding_hash": null
  },
  "confidence": {
    "reproduction_strength": "strong",
    "test_type": "unit",
    "risk_level": "low",
    "files_changed": 3,
    "lines_changed": 42
  }
}
```

Allowed state transitions (reject anything else):
```
TRIAGE → IMPLEMENTING       (triage complete)
IMPLEMENTING → REVIEWING    (implementation complete)
REVIEWING → IMPLEMENTING    (review found issues)
REVIEWING → AUDITING        (review passed)
AUDITING → IMPLEMENTING     (audit found issues)
AUDITING → COMPLETED        (audit passed)
ANY → HALTED                (circuit breaker or manual halt)
```

## configuration-yaml

```yaml
run_mode:
  enabled: true  # Required to use /run
  defaults:
    max_cycles: 20
    timeout_hours: 8
  rate_limiting:
    calls_per_hour: 100
  circuit_breaker:
    same_issue_threshold: 3
    no_progress_threshold: 5
  git:
    branch_prefix: "feature/"
    create_draft_pr: true
    auto_push: true    # true | false | prompt
    base_branch: "main"                     # Branch to diff against (git-aware sync fallback)
    sprint_commit_pattern: '^feat\(sprint-' # grep -E pattern for sprint commits
  sprint_plan:
    branch_prefix: "feature/"
    default_branch_name: "release"
    consolidate_pr: true           # Create single PR for all sprints (default)
    commit_prefix: "feat"          # Prefix for sprint commits
    include_commits_by_sprint: true  # Group commits by sprint in PR
```

## git-aware-state-sync

### Git-Aware State Sync (cycle-056, Issue #474)

When context compaction or session loss leaves `.run/sprint-plan-state.json` stuck at
`state: "RUNNING"` with `0` completed sprints — even though git history shows all sprint commits
already landed — `simstim-orchestrator.sh --sync-run-mode` cross-references git as a secondary
source of truth before returning `still_running`.

**When the fallback fires** (all three must hold):
1. `sprint-plan-state.json` shows `state: "RUNNING"` (the normal trigger)
2. `sprints.total` (or `sprints.list` length) resolves to a positive integer
3. `git log ${base_branch}..HEAD` shows at least `sprints.total` commits matching
   `run_mode.git.sprint_commit_pattern`

When satisfied: updates `.run/sprint-plan-state.json` to `state: "JACKED_OUT"` with
`git_inferred: true` and an ISO-8601 `git_inferred_at` timestamp; returns
`{ "synced": true, "reason": "git_inferred_completion", "commits_found": N, "commits_expected": M, "base_branch": "main" }`.

**When it does NOT fire**: in-flight runs with no commits yet, or partial runs
(`commits_found < commits_expected`) → existing `still_running` preserved; state already
`JACKED_OUT`/`HALTED` → existing validation flow.

**Known limitation**: counts matching commits, so a sprint that produced multiple matching commits
(e.g. review-feedback fix commits with the same prefix) can cause early satisfaction. Empirically
rare — squash-merge workflows produce one commit per sprint. Consider `br list --status closed`
as an authoritative alternative if this becomes a problem.

Replaces the previous requirement to use `--force-phase complete --yes` as a last-resort escape
hatch after session loss.

