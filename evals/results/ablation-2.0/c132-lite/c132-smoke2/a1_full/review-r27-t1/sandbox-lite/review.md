head/evals/harness/pipeline-run.sh:566 — apply_arm_toggles runs after overlay_answer_paths recorded the overlay_sha256 digests and before check_mount_closed verifies them; the effort toggle (lib/sandbox-mount.sh:358-371) rewrites SKILL.md frontmatter and model-config.yaml in place, so arm a7_effort_medium is refused as infrastructure_error (clause (c) mount_mutated, sandbox-mount.sh:986) on every review-catch PR whose answer set holds a SKILL.md with an effort: line (e.g. auditing-security/SKILL.md in pr-04)
head/evals/graders/recall-vs-defects.sh:308 — Python end-of-definition detection treats the `):` of a multi-line signature as the dedent that ends the def, so black-formatted functions have no scope and clause (ii) of the 1.3.0 rule never credits citations inside them (206 such signatures under .claude/adapters)
head/.claude/scripts/adversarial-review.sh:179 — budget_cents_max read with `// 600` turns an explicit `false` into 600, so a malformed maximum keeps diff scaling instead of failing closed to fixed as documented
head/evals/harness/ablation-row.sh:394 — dissent_absent_reason classifies a gate as planned `disabled` from the agent-writable sandbox/.loa.config.yaml rather than harness evidence
head/evals/harness/ablation-grade.sh:2159 — split_segments splits on a bare `&`, so `diff … 2>&1 | wc -l` loses its pipe-sink check and the count output marks every defect of the file exposed_unknown
head/evals/harness/ablation-grade.sh:2312 — oracle_scan (~120 lines), oracle_plan (:2435) and sandbox-mount.sh cmd_check (:958) exceed the 50-line guideline with no justification
head/evals/graders/recall-vs-defects.sh:214 — MD_HDR reads `#` comment lines inside fenced code blocks as markdown headings, splitting sections
head/evals/graders/recall-vs-defects.sh:287 — CLOSE_ONE matches a `}` inside a trailing header comment, making the function one line long
head/evals/graders/recall-vs-defects.sh:299 — bash close_line compares raw indentation while headers use expandtabs(8); tab-indented functions never find their closing brace
head/evals/graders/recall-vs-defects.sh:143 — json.load of the v1 manifest is unguarded: a malformed snapshot is a traceback and exit 1, not the documented exit 2 + error JSON
head/evals/graders/recall-vs-defects.sh:135 — head-dir fallback `$workspace/pr/head` is the agent-writable sandbox copy when EVAL_HEAD_DIR is unset
head/.claude/scripts/adversarial-review.sh:164 — a yq read failure yields `unreadable`, which sets CONF_BUDGET_SCALE_SET=true and emits a misleading WARN plus envelope budget metadata for a key never written
head/.claude/scripts/adversarial-review.sh:180 — budget_cents_max: 0 is accepted; under diff every run then refuses with budget_exceeded
head/.claude/schemas/adversarial-finding.schema.json:248 — metadata is additionalProperties:false and gains the three budget keys but not the `reason` key the budget_exceeded envelope now writes (adversarial-review.sh:4445)
head/evals/harness/took-effect.sh:356 — resolve_fixture with --task-yaml omits $SOURCE_TREE/evals/fixtures and never falls back to the overlay_fixture evidence, so oracle_closed FAILs "does not resolve" on such runs
head/evals/harness/ablation-grade.sh:2010 — corpus_sha256 re-opens the file by path (no O_NOFOLLOW) after read_regular already read it
head/evals/harness/ablation-row.sh:536 — poslist nulls the whole defects_missed_pm3_v1 list when one v1-only id's position exceeds defects_seeded
Verdict: CHANGES_REQUIRED
