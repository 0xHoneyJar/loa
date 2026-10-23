# Reviewer concerns — sprint-1 (PR: cycle-131 sprint-263)

Scope: pr/head.diff (35 files). Cite as head/<path>:<line>.

1. ablation-grade.sh oracle detector skips every tool_result with is_error true
   (oracle_scan). diff / sdiff / git diff --no-index exit 1 when the files differ and
   Claude Code marks a non-zero Bash exit as is_error with the output still present, so a
   bare `diff pr/head/X X` is never counted. AG-48 case 9 pins this.
2. ablation-row.sh dissent_absent_reason: an envelope with status api_failure (written
   directly by adversarial-review.sh, no recorded_by) maps to "none" (the dissent ran).
   Only budget_exceeded, failed, record-fallback and a status containing "preflight" are
   recognised.
3. sandbox-mount.sh _sm_oracle_py check clause (d): any extra commit or stash ref in the
   sandbox repository fails oracle_closed → infrastructure_error and the arm is paused,
   conflating the agent's own git activity with oracle leakage.
4. recall-vs-defects.sh MD_HDR treats `# comment` lines inside fenced code blocks as
   markdown headings, mis-splitting scopes in .md files; bash close_line compares
   indentation without expandtabs while headers() uses expandtabs(8).
5. recall-vs-defects.sh head_dir fallback `$workspace/pr/head` is the agent-writable copy
   when EVAL_HEAD_DIR is unset and the fixture does not resolve.
6. repo_name_exempt: a backticked token's unit is the token itself, so any value quoting
   `0xHoneyJar/loa` in backticks is exempt once the fixture holds the token anywhere.
7. envelope_texts numeric anchor: an anchor path without a 1–6 char extension falls back
   to f.file; extensionless paths lose the anchor's path.
8. _adv_conf_budget_scale: a yq read failure ("unreadable") sets CONF_BUDGET_SCALE_SET
   and logs a misleading WARN naming the value "(a unreadable, not a string)".
9. AG-50 depends on evals/tests/fixtures/c131-oracle/ which the PR does not add.
