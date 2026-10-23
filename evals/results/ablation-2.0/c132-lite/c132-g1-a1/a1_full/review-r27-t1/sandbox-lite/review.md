head/evals/harness/ablation-grade.sh:2390 — the oracle detector skips every tool_result with is_error true; Claude Code marks any non-zero exit (every `diff` that found a difference exits 1) is_error while keeping the output, so the diff form never fires on a real transcript
head/evals/harness/ablation-grade.sh:1995 — KF-046 class 7 exemption accepts a substring match against fixture lines, so a WebFetch of an upstream URL or a `curl` of an install one-liner quoted in the PR fixture passes the contamination scan
head/.claude/scripts/adversarial-review.sh:179 — `yq '… // 600'` swallows `budget_cents_max: false` before validation; a malformed maximum reads as 600 and scales the budget instead of failing closed to fixed
head/evals/tests/ablation-grade.bats:1544 — AG-50/AG-51 read fixtures/c131-oracle, manifests/v1 and the curated manifests; none is in the change, and the report title claims the curated labels and the versioned re-grade
head/evals/tests/run-ablation.bats:1127 — RAB-c131-1/2 depend on grimoires/loa/evals/ablation-2.0-replication, which the change does not carry
head/evals/harness/lib/sandbox-mount.sh:1041 — post-run clause (d) fails oracle_closed on any extra sandbox commit or unreachable object, so an agent `git add`/`git stash`/commit rows infrastructure_error and pauses the arm
head/evals/harness/ablation-row.sh:394 — dissent_absent_reason reads the agent-writable sandbox .loa.config.yaml and ranks `disabled` highest, so a sandbox-side edit relabels a run or an error as a planned absence
head/evals/graders/recall-vs-defects.sh:135 — the head directory falls back to <workspace>/pr/head, the grading copy of the agent-writable tree, when the fixture head does not resolve
head/evals/graders/recall-vs-defects.sh:295 — CLOSE_ONE treats any header line holding a `}` (e.g. `f() { local x="${1:-}"`) as a one-line function, scoping it to its header
head/evals/graders/recall-vs-defects.sh:299 — the closer scan measures indentation without expandtabs(8) while headers() uses it, so tab-indented bash functions never find their `}`
head/evals/harness/ablation-grade.sh:2312 — oracle_scan is 121 lines at five nesting levels; cmd_check in sandbox-mount.sh:958 is 101 lines (complexity rule: over 50 lines needs justification)
head/evals/harness/ablation-report.py:1138 — part_split keys build rows as `rule n/a` when review rows hold two rules, so no partition pairs a build and a review contrast
head/.claude/scripts/adversarial-review.sh:164 — a yq failure yields `unreadable`, which is read as a written key: spurious WARN and budget keys in the envelope
head/.claude/schemas/adversarial-finding.schema.json:268 — metadata has additionalProperties false without `reason`, `estimated_cents`, `estimate_voices` or the `budget_exceeded` status the change documents
head/evals/harness/ablation-report.py:984 — precision_planted_per_flag can exceed 1 (AR-52 asserts 1.5); it is not a precision
head/evals/harness/lib/sandbox-mount.sh:1010 — clause (b) byte-equality with tiny pinned boilerplate files can fail a clean sandbox
head/evals/harness/ablation-grade.sh:2088 — answer_paths re-implements the mount library's diff_paths without hunk skipping or Binary-files lines
head/evals/harness/lib/sandbox-mount.sh:954 — evidence readers disagree on first vs last occurrence (read_evidence first, ablation-row.sh:419 last, took-effect.sh:345 first, pipeline-run.sh:560 last)
Verdict: CHANGES_REQUIRED
