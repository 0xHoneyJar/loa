# Phase Mechanics — exact invocations, exit codes, and schemas

Conditionally-needed detail for `autonomous-agent`'s SKILL.md phases: the exact scripts, exit
codes, and schemas the phase summaries there point to. Consult the section for the phase you're
running; you don't need the others in the same turn.

## Phase 0.0 — Workspace Cleanup exit-code handling

```bash
CLEANUP_RESULT=$(.claude/scripts/workspace-cleanup.sh --grimoire grimoires/loa --yes --json 2>&1)
CLEANUP_EXIT=$?

case $CLEANUP_EXIT in
  0)
    # Success - check for partial state
    if echo "$CLEANUP_RESULT" | jq -e '.partial_state != null' > /dev/null 2>&1; then
      PARTIAL=$(echo "$CLEANUP_RESULT" | jq -r '.partial_state[]? // empty')
      if [[ -n "$PARTIAL" ]]; then
        echo "HALT: Partial archive state detected - manual intervention required"
        echo "Found: $PARTIAL"
        exit 1
      fi
    fi
    echo "✓ Workspace cleanup complete"
    ;;
  3)
    # Security validation failure - HALT
    echo "HALT: Workspace cleanup security validation failed"
    exit 1
    ;;
  *)
    # Other error - log and continue
    echo "WARNING: Workspace cleanup failed (exit $CLEANUP_EXIT), continuing..."
    ;;
esac
```

## Phase 5.5 — Post-PR Orchestrator

Exit codes from `.claude/scripts/post-pr-orchestrator.sh --pr-url <pr_url> --mode autonomous`:

| Exit | State  | Meaning                          |
|------|--------|-----------------------------------|
| 0    | READY_FOR_HITL | Success                    |
| 1    | HALTED | Error — log it                    |
| 2    | HALTED | Timeout — escalate                |
| 3    | HALTED | Phase failure — check findings    |
| 4    | HALTED | Flatline blocker found            |
| 5    | HALTED | User intervention required        |

The orchestrator runs these phases in sequence:

| Phase | Description | Fix Loop |
|-------|-------------|----------|
| POST_PR_AUDIT | Consolidated security/quality audit | Yes (max 5) |
| CONTEXT_CLEAR | Checkpoint, prompt user to `/clear` | No |
| E2E_TESTING | Fresh-eyes build and test verification | Yes (max 3) |
| FLATLINE_PR | Optional multi-model review (~$1.50) | No |

Configuration:

```yaml
# .loa.config.yaml
post_pr_validation:
  enabled: true
  phases:
    audit: { enabled: true, max_iterations: 5 }
    context_clear: { enabled: true }
    e2e: { enabled: true, max_iterations: 3 }
    flatline: { enabled: false }  # Opt-in, ~$1.50 cost
```

Full command specification: `.claude/commands/post-pr-validation.md`.

## Exit Criteria by Phase

| Phase | Required to advance |
|---|---|
| 0 Preflight | Workspace cleanup completed (or skipped with warning); no partial archive state detected; NOTES.md read or created; no CRITICAL blockers; System Zone verified; work item selected; trajectory started |
| 1 Discovery | PRD complete and verified; all claims grounded (file:line or `[ASSUMPTION]`); Flatline review passed (if enabled); trajectory logged |
| 2 Design | SDD complete; sprint plan ready; Flatline SDD and Sprint reviews passed (if enabled); design traces to requirements |
| 3 Implementation | All sprint tasks complete; all tests passing; changes committed (not pushed); no lint errors; attention budget respected |
| 4 Audit | All dimension scores ≥ `audit_threshold` (folded into the Gate Decision in the phase itself) |
| 4.5 Remediation | All scores ≥ threshold, or escalated after `max_remediation_loops` |
| 5 Submission | Branch pushed; PR created; trajectory logged |
| 5.5 Post-PR Validation | Post-PR audit passed (or disabled); E2E tests passed (or disabled); Flatline review passed (or disabled); state = `READY_FOR_HITL` |
| 6 Deployment | Deployment complete; `audit-deploy` passed OR rollback executed |
| 7 Learning | Learnings extracted; PRD iteration check complete; feedback captured for upstream; structured notes created; trajectory archived; work item marked complete; ready for next cycle |
