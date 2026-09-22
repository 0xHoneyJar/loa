# Adversarial Cross-Model Review — Phase 2.5 mechanics

Referenced from `reviewing-code/SKILL.md` Phase 2.5. Runs when
`flatline_protocol.code_review.enabled: true` in `.loa.config.yaml`.

**Objective**: Invoke a cross-model dissenter to catch reviewer blind spots before the final decision.

**Steps**:
1. Prepare git diff of sprint changes: `git diff main...HEAD > /tmp/adversarial-diff.txt`
2. Invoke adversarial review:
   ```bash
   findings=$(.claude/scripts/adversarial-review.sh \
     --type review \
     --sprint-id "$sprint_id" \
     --diff-file /tmp/adversarial-diff.txt \
     --context-file "$reviewer_concerns_file" \
     --json)
   ```
3. Parse findings:
   - If `findings` array is empty or invocation failed: log and continue to Phase 3
   - If BLOCKING findings exist: incorporate into Phase 4 decision (forces CHANGES_REQUIRED)
   - If ADVISORY findings only: append as "Cross-Model Observations" section in feedback
4. Clean up temp files

**Failure must produce a record.** If `adversarial-review.sh` fails (timeout, API error, budget exceeded), write `grimoires/loa/a2a/{sprint_id}/adversarial-review.json` with `{"findings": [], "metadata": {"status": "failed", "reason": "..."}}` BEFORE proceeding. Do NOT silently skip — the gate hook has no way to distinguish "not attempted" from "attempted and failed", and the distinction matters for audit trail.

**Parameter Derivation**:
| Script Parameter | SKILL Derivation |
|-----------------|-----------------|
| `--sprint-id` | From SKILL invocation args, resolved via ledger |
| `--diff-file` | `git diff main...HEAD` written to temp file |
| `--context-file` | Reviewer's Phase 2 concern notes |
| `--model` | From `flatline_protocol.code_review.model` config |
| `--budget` | From `flatline_protocol.code_review.budget_cents` config |
| `--timeout` | From `flatline_protocol.code_review.timeout_seconds` config |

**Output**: Findings written to `grimoires/loa/a2a/{sprint_id}/adversarial-review.json`

**Failure mode**: If adversarial review is unavailable (timeout, API error, budget exceeded), proceed with single-model assessment and log warning. No DEGRADED marker for review (only audit).
