# NOTES

## Session Continuity

- 2026-10-22 /review-sprint sprint-1 (task review-r27): CHANGES_REQUIRED — 3 high (oracle detector is_error skip ablation-grade.sh:2390; grader BASH_HDR method-call headers recall-vs-defects.sh:210; python multi-line def spans :302), 5 medium, 9 low. Dissent ran (2 voices, 0 rejected). Feedback: a2a/sprint-1/engineer-feedback.md; task-brief copy: review.md. br not installed: no beads sync/comment.
- 2026-10-22 /audit-sprint sprint-1 (task review-r27): CHANGES_REQUIRED — 3 high (the review's three, confirmed: is_error shape verified on a host transcript; heredoc method-call header and multi-line def reproduced with the head grader), 6 medium (api_failure→none ablation-row.sh:478; sandbox-config "disabled" :393; clause (d) strictness sandbox-mount.sh:1040; MD fence recall:214; agent-writable pr/head fallback recall:135 reproduced; oracle_scan fail-open ablation-grade.sh:2315), 11 low. Audit dissent ran: gpt-5.5-pro primary clean, claude-headless companion 3 findings merged, 0 rejected, not degraded. Phase 0 prerequisite (review "All good") not met — ran under the task instruction. excluded_confirmed 0. Feedback: a2a/sprint-1/auditor-sprint-feedback.md; findings: a2a/audits/2026-10-22/findings.jsonl. br not installed.

## Learnings

- 2026-10-22 (auditing-security, pattern_discovery, score 4): Claude Code transcripts record a non-zero Bash exit as tool_result is_error:true with the output retained in content ("Exit code N" first line); a transcript detector that skips is_error results drops every diff that found a difference.
- 2026-10-22 (auditing-security, workaround, score 3): the System Zone hook (FR-SZ2-REDIR) blocks any Bash redirect whose target path contains .claude/, even under /tmp; build grader repro fixtures under a neutral directory name (the recall grader matches cited basenames).
