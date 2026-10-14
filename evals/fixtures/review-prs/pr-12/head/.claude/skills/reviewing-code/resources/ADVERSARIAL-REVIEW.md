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

## Two voices and the rejected-payload contract (cycle-126 FR-2)

**Companion voice (D-2.1).** Every dissent plans a second chain from the *other* provider
family — the primary configured on the block decides: an OpenAI-family primary gets the
Anthropic chain (`opus` → `claude-headless`), an Anthropic-family primary gets the OpenAI chain
(`gpt-5.5-pro` → `gpt-5.5` → `codex-headless`). Credential *presence* (env → `.env.local` →
`.env`; the value is never read) decides only where the companion chain starts — with no key it
starts at the CLI hop. Both chains walk in parallel; the two completed envelopes are aggregated
(`verdict_quality.voices_planned: 2`, `voices_succeeded_ids` lists only completed voices). The
companion's findings arrive re-numbered `DISS-C-NNN` with a `voice` field; the primary's carry
`voice` too. `metadata.companion_voice` records `{planned, family, family_basis, chain, model,
status: succeeded|failed, failure_class: auth|model_unavailable|quota|timeout|malformed|null,
cost_cents, attempts}`; a companion whose chain fails is a dropped voice (degraded for an audit,
never blocking a review). Opt-out per block: `flatline_protocol.{code_review,security_audit}.companion_voice: false`.

**Tolerant schema (D-2.2).** A finding missing only `failure_mode` is no longer dropped: the
first sentence of its `description` (≤ 200 chars) becomes `failure_mode` and the finding is
marked `failure_mode_derived: true` (a missing `id` is filled positionally, `id_derived: true`).
Severity, category and description are never touched. Payloads that still fail go to the
sidecar (`adversarial-rejected-<type>.jsonl`, `-companion` suffix for the second voice) **and**
to `metadata.rejected_summary[]` as `{severity, title, anchor, reason, description_head}`.

**The contract (D-2.3).** When `rejected_summary` is non-empty the feedback file MUST contain a
`## Rejected dissent payloads` section with one line per entry — `- <title> (<severity>, <anchor>)
— <reason>: triaged as <real defect → counted under the matching heading | not a defect → why>`.
`verdict-derive.sh` reads the sibling envelope (`adversarial-<gate>.json`, or `--envelope <path>`)
and marks the trailer INCONSISTENT (exit 1) when the section is missing. Reading a sidecar row:
`payload` is the model's finding as normalised, `reject_reason` the clause it failed, and
`repair_attempted` / `repair_succeeded` whether the bounded repair round-trip ran.

**Repair loop (D-2.4).** The one bounded repair round-trip goes to `tiny` when an Anthropic
credential is present, else to `claude-headless` (`LOA_ADVERSARIAL_REPAIR_MODEL` pins it) — no
longer to the voice that produced the malformed finding. KF-004 evidence: the three real rejected
payloads under `tests/fixtures/dissent-rejected/` now pass without a repair.
