head/evals/harness/execute-agent.sh:266 — HIGH: the `rule_files` toggle records `removed: none present` and continues when neither rule file exists in the sandbox (rules are only materialised when the prompt tree has `.claude/rules/`, line 146), so the `no_rule_files` arm silently runs as `baseline`, contradicting the exit-2 contract stated at line 65; `arms-report.py` can then read `no recall loss` for a null experiment
head/.claude/scripts/guard-yield.sh:470 — MEDIUM: `source "$HEREDOC_LIB"` runs the optional library in-process; a library whose top level exits ends the generator with exit 0, no output and no files written (reproduced with the later-cycle heredoc-classifier.sh)
head/.claude/data/guard-origins.yaml:163 — MEDIUM: the fence hook row is `floor: false` while its sixteen fence rows are floor; dropping the hook registration and row together passes --check, guard-origins.bats and the corpus replay, leaving the floor fences inert
head/.claude/rules/stash-safety.md:2 — MEDIUM: the `paths:` scope ties a rule about Bash `git stash` usage to sessions that touch shell files; sessions editing only prose lose the rule entirely
head/evals/harness/arms-report.py:176 — MEDIUM: `suite_report` is 168 lines, nesting over three deep with no early returns; split the per-arm verdict from the rendering
head/.claude/scripts/validate-artifact.sh:976 — MEDIUM: `validate_sprint_kinds` is 89 lines and its awk task-line scanner duplicates tools/cycle-ratio.sh:46-66; the two will drift
head/.github/workflows/bats-tests.yml:159 — MEDIUM (low confidence): the new `guard-yield.sh --check` gate exits 1 when grimoires/loa/guards.md is absent, and that tracked register is not in this change set (fixture scope excludes grimoires/)
head/.claude/scripts/guard-yield.sh:523 — LOW: `"fence:" + .pattern_id` on a numeric pattern_id aborts the whole jq join (exit 3) for one odd audit row
head/.claude/scripts/guard-yield.sh:443 — LOW: `"$AUDIT_LOG".*` also reads lock/tmp files beside the log as audit segments
head/.claude/scripts/guard-yield.sh:8 — LOW: header says one hooks row per unique script; the generated table emits one row per registration
head/evals/harness/run-arms.sh:319 — LOW: `run_trial` is 66 lines with a four-deep retry loop
head/.claude/scripts/loa-status.sh:956 — LOW: a present but malformed guard-yield.json is reported as "no yield file"
head/evals/harness/run-arms.sh:314 — LOW: the transport-failure grep matches `network` or `5[0-9][0-9] ` anywhere in agent output, turning agent failures into 300 s retries
head/.claude/skills/implementing-tasks/SKILL.md:28 — LOW: app zone flipped from read to read-write with no mention in the PR (SURGICAL)
head/.github/workflows/check-prompt-budget.yml:5 — LOW (low confidence): budget constants in the comment changed while tools/check-prompt-budget.sh is not in the change set
head/.claude/hooks/safety/block-destructive-bash.sh:528 — LOW: ambient LOA_AUDIT_REPLAY marks every live block as replay and the yield under-reports real catches
head/evals/tasks/review-recall/review-pr-11.yaml:5 — LOW (low confidence): the sixteen new tasks reference fixtures pr-11…pr-18 and hidden manifests absent from this change set; run-arms.sh refuses a missing fixture
Verdict: CHANGES_REQUIRED
