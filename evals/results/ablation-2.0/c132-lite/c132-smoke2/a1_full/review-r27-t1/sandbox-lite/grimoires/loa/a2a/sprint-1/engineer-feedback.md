# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md
**Change under review:** `pr/head.diff` — cycle-131 sprint-263 (closed review-catch mount, grader 1.3.0, oracle detector, dissent line anchors + budget_scale, row writer 1.4, report 1.3), 35 files

---

## Overall Assessment

The PR is large but well-tested in the parts it tests: the numeric-anchor normaliser, the budget scaling, the overlay/check core, the row writer and the report partitions each ship with bats coverage, and the cross-model dissent produced no rejected payloads. The adversarial-review.sh changes are sound (the estimate is integer, the config guard precedes the new reads, the schema-enforced branch holds the anchor to the same rule).

Two defects block merge. First, the closed-mount wiring in `pipeline-run.sh` records the overlay digests, then runs the arm toggles, then verifies the surface against those digests; the `effort` toggle rewrites every `SKILL.md` frontmatter and `model-config.yaml`, so arm `a7_effort_medium` is refused at launch on any review-catch PR whose answer set contains such a file (the auditing-security skill, which carries `effort:`, is in the pr-04 answer set the PR's own test names). Second, the 1.3.0 same-scope rule's Python end-of-definition detection ends a function at the `):` of a multi-line signature, so black-formatted functions (206 in `.claude/adapters` alone) get no scope clause at all.

The implementation report is the PR title and a file count; it carries no `## AC Verification` walkthrough and no test-run evidence (I could not run the PR's bats suites: `pr/` holds only touched files, not the fixtures they load). That is an automatic CHANGES_REQUIRED under this skill's rules and is recorded as a MEDIUM below.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Closed mount — toggles mutate answer paths after the digests are recorded

- **HIGH** (confidence: high) `head/evals/harness/pipeline-run.sh:566` — `apply_arm_toggles` runs after `overlay_answer_paths` (:559) wrote `overlay_sha256=` lines, and `check_mount_closed` (:577) then compares the sandbox to those lines; the `effort` toggle (`head/evals/harness/lib/sandbox-mount.sh:358-371`) rewrites every `.claude/skills/*/SKILL.md` frontmatter in place (`_sm_strip_frontmatter_effort`, :261-272) and `.claude/defaults/model-config.yaml`, so clause (c) at `head/evals/harness/lib/sandbox-mount.sh:986` reports `mount_mutated=<path>` and `lib_call` turns it into `infrastructure_error` before any phase.
**File:** `head/evals/harness/pipeline-run.sh:566` (order), `head/evals/harness/lib/sandbox-mount.sh:358` (mutation), `head/evals/harness/lib/sandbox-mount.sh:986` (refusal)
**Issue:** Arm `a7_effort_medium` has `task_types: [all]` (`head/evals/suites/ablation-2.0.yaml:89`), so on every review-catch task it goes overlay → effort toggle → check. Any answer path that is a `SKILL.md` with an `effort:` frontmatter line (6 of 37 skills in this tree, including `auditing-security/SKILL.md`, which the PR's own AG-50 test says is in pr-04's answer set: "d5: the audit skill reads its own later SKILL.md") or `.claude/defaults/model-config.yaml` has a post-toggle sha that differs from the recorded one while the recorded one equals the fixture's, which is exactly the clause (c) branch. The same class applies to `karpathy_block` (`CLAUDE.loa.md`, `constraints.json`), `rule_files` and `audit_delta_instruction` should an arm ever carry them on a review-catch task. The only test of toggle/overlay interaction (`head/evals/tests/sandbox-mount.bats:5096`) uses `dissent: false`, which edits `.loa.config.yaml` outside the answer set.
**Why This Matters:** A7 on review-catch becomes a guaranteed `infrastructure_error` for every task whose PR touches a skill with an effort line, with no phase run and no row that reads as a model result; the pre-registered A7 contrast silently loses those cells. The PR header comment ("the checked surface is the launched one") describes the ordering as intended, so this is a design conflict, not a typo.
**Required Fix:** Either (a) record the `overlay_sha256` baseline after `apply_arm_toggles` (re-run the digest step, or have `check_mount_closed` accept a toggle-declared exemption list for paths a toggle lawfully rewrote, recording `overlay_toggled=<path>` evidence), or (b) apply the effort/karpathy/rule/audit-delta toggles to answer paths only through the overlay source (i.e. make the toggle operate on the fixture copy so the digest reflects it), and add a bats case: overlay → `{"effort":"medium"}` on a fixture whose answer set includes a `SKILL.md` with `effort:` → `check_mount_closed` passes.

### 2. Grader 1.3.0 — Python scope ends at a multi-line signature

- **HIGH** (confidence: high) `head/evals/graders/recall-vs-defects.sh:308` — `close_line` for Python returns at the first later non-blank, non-comment line indented no deeper than the `def`; for `def f(\n    a,\n):` the `):` line has the def's indentation, so the definition ends on the signature and the whole body is top-level (scope `None`), and clause (ii) of `hit_new` never credits a citation inside it.
**File:** `head/evals/graders/recall-vs-defects.sh:302-309`
**Issue:** Raised by the dissent as DISS-002 and confirmed by reading: `PY_HDR` (:213) matches `def NAME(` without requiring the closing paren, and the end detection does not track parentheses. `.claude/adapters` has 206 functions written this way (black style), and the review corpus is Loa PRs that touch them. A defect site inside such a body and a valid citation 4+ lines away inside the same function credit nothing under `recall` (the decision statistic), while `recall_pm3` is unaffected, so the rule's documented contract (header :422-460) is false for this common shape. The RG-37 test only covers one-line `def` headers.
**Why This Matters:** `recall` feeds `defect_catch_rate`, the pre-registered decision statistic of report 1.3; a systematic under-credit on a common code shape makes the "same scope" clause misreport exactly where it was meant to help.
**Required Fix:** In `close_line` (python), skip signature lines until the line containing the `):` (or `) -> T:`) that closes the header's open paren count before applying the dedent test; add an RG case with a multi-line signature and a citation 6 lines into the body.

---

## Observations

### 1. Budget scaling (dissent DISS-001, triaged MEDIUM)

- **MEDIUM** (confidence: high) `head/.claude/scripts/adversarial-review.sh:179` — `budget_cents_max // 600` turns an explicit YAML `false` into 600 before the whole-number check at :180, so `budget_scale: diff` with `budget_cents_max: false` keeps diff scaling capped at 600 instead of falling back to `fixed` as the example config (:395-396) and ADVERSARIAL-REVIEW.md promise. The file already notes the `//` pitfall for `companion_voice` (:212). The dissent rated this BLOCKING; the damage is bounded by the 600c default, so I hold it at MEDIUM.
**Suggestion:** read the raw value with `| tag` as `_adv_conf_budget_scale` does for the scale, and treat anything but `!!null`/absent and a valid `!!int` as malformed.

### 2. Row writer 1.4 reads the agent-writable config (dissent DISS-C-005)

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-row.sh:394` — `dissent_absent_reason` classifies a gate as `disabled` (a planned absence the report never excludes) from `sandbox/.loa.config.yaml`, which the agent can edit mid-run; the grader header in the same PR calls the sandbox tamperable. An in-run flip of `flatline_protocol.enabled` both suppresses the gate and records the absence as planned.
**Suggestion:** derive `disabled` from harness evidence only (`dissent=false`, `flatline=off`, `gates=false` lines in `meta/arm-evidence.txt`), or trust the sandbox config only when `loa_config_sha256` at finish equals the materialised one.

### 3. Oracle detector — `2>&1` splits the segment

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:2159` — `split_segments` splits on a bare `&`, so `diff pr/head/X .claude/X 2>&1 | wc -l` becomes the segments `diff … 2>`, `1`, `wc -l`; the diff segment's separator is `;`, the pipe-sink check in `oracle_plan` (:2481) is skipped, and the result `4` (not an `ERR_LINE`, no ranges) marks every defect of the file `exposed_unknown` at :2420. AG-48's `| wc -l` case passes only without the redirection.
**Suggestion:** treat `N>&M`, `&>` and `>&` as part of the word in `split_segments` (only `&&` and a lone `&` followed by whitespace/newline are separators).

### 4. Process — no AC verification, no test evidence

- **MEDIUM** (confidence: high) `grimoires/loa/a2a/sprint-1/reviewer.md:1` — the implementation report is the PR title and "35 file(s) in scope"; no `## AC Verification`, no `file:line` evidence per criterion, no statement that the ten touched/added bats suites ran green. The sprint's single task is the PR itself, so this is the only place the engineer could have shown the suites pass; I could not run them here (`pr/` lacks the fixture trees the suites load).
**Suggestion:** add the walkthrough and paste the bats summary lines (`eval-recall-grader`, `ablation-grade`, `ablation-row`, `ablation-report`, `sandbox-mount`, `took-effect`, `pipeline-run`, `run-ablation`, `adversarial-review-normalise`, `adversarial-review-budget-scale`).

### 5. Complexity

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:2312` — `SIMPLICITY[shrink]`: `oracle_scan` is ~120 lines with four nested loops and inner closures; `oracle_plan` (:2435, ~65 lines) and `cmd_check` in `head/evals/harness/lib/sandbox-mount.sh:958` (~100 lines, clauses (a)–(d) in one body) are over the 50-line guideline with no justification comment. Over-engineering pass: the only redundancy found is the double read in `corpus_sha256` (below); `net: -4 lines possible`.
**Suggestion:** split `oracle_scan` into `later_lines(f)`, `scan_diff_result(...)` and `scan_read_result(...)`; split `cmd_check` per clause.

### 6. Grader 1.3.0 scope heuristics (low)

- **LOW** (confidence: high) `head/evals/graders/recall-vs-defects.sh:214` — `MD_HDR` treats any `#` line as a heading, including `# comment` lines inside fenced code blocks in `.md` files, which splits a section at a code comment and loses same-section credit for citations after it.
- **LOW** (confidence: medium) `head/evals/graders/recall-vs-defects.sh:287` — (dissent DISS-C-003, confirmed) `CLOSE_ONE` is searched on the whole header line, so a trailing comment holding a `}` (e.g. `f() {  # reads ${X}`) makes the function one line long and its body top-level. No such header exists in the head tree today.
- **LOW** (confidence: medium) `head/evals/graders/recall-vs-defects.sh:299` — bash `close_line` compares raw indentation (`len(t) - len(t.lstrip())`) while `headers` uses `expandtabs(8)` (:283); a tab-indented function never matches its closing brace and its scope runs to the next header.
- **LOW** (confidence: high) `head/evals/graders/recall-vs-defects.sh:143` — (dissent DISS-C-004) `json.load` on the v1 manifest has no error handling: a malformed `v1/<fixture>.json` is a traceback and exit 1 rather than the header's exit 2 + `err()` JSON. Not a scoring risk: `grade_recall` (`head/evals/harness/ablation-grade.sh:1639`) raises `GradeError` on the empty stdout.
- **LOW** (confidence: low) `head/evals/graders/recall-vs-defects.sh:135` — the head-dir fallback `$workspace/pr/head` is the agent-writable sandbox copy; it is reached only when `EVAL_HEAD_DIR` is unset and the corpus fixture dir is absent, which `grade_recall` (:1631) leaves unset when `resolve_pr_fixture` fails. Defensive: refuse rather than fall back.

### 7. adversarial-review.sh (low)

- **LOW** (confidence: medium) `head/.claude/scripts/adversarial-review.sh:164` — (dissent DISS-C-001) a yq failure yields `unreadable`, which is not the absent case, so an unparseable config sets `CONF_BUDGET_SCALE_SET=true`, logs a WARN about a key never written, and puts budget metadata in the envelope, against the "absent key is byte for byte the shipped envelope" contract.
- **LOW** (confidence: high) `head/.claude/scripts/adversarial-review.sh:180` — `budget_cents_max: 0` passes the regex; under `diff` every run then refuses with `budget_exceeded` (fail-closed, but worth a WARN).
- **LOW** (confidence: high) `head/.claude/schemas/adversarial-finding.schema.json:248` — (dissent DISS-C-002) `metadata` has `additionalProperties: false` and the PR adds three budget keys but not the `reason` key the SET branch now writes (`head/.claude/scripts/adversarial-review.sh:4445`); `status` also lacks `budget_exceeded` (pre-existing). The `anchor_line` description omits the 10,000,000 cap the normaliser applies.

### 8. Harness plumbing (low)

- **LOW** (confidence: medium) `head/evals/harness/took-effect.sh:356` — `resolve_fixture` with `--task-yaml` tries four roots but not `$SOURCE_TREE/evals/fixtures/<rel>`, which `pipeline-run.sh resolve_rel` accepts, and does not fall back to the `overlay_fixture` evidence, so a run whose fixture lives only in the source tree FAILs `oracle_closed` with "does not resolve" although the overlay recorded where it is.
- **LOW** (confidence: high) `head/evals/harness/ablation-grade.sh:2010` — `corpus_sha256` reads the file through `read_regular` (O_NOFOLLOW, size-capped) and then re-opens it by path to hash; hash the bytes already read.
- **LOW** (confidence: medium) `head/evals/harness/ablation-row.sh:536` — `poslist` nulls the whole `defects_missed_pm3_v1` list when one v1-only id's position exceeds `defects_seeded` (the grader maps such ids to their v1 position, `head/evals/harness/ablation-grade.sh:1649-1656`); a v1 manifest with more defects than the current key loses the field entirely.

---

## Cross-Model Observations

Dissent envelope: `grimoires/loa/a2a/sprint-1/adversarial-review.json` — status `reviewed`, primary `gpt-5.5-pro`, companion `claude-headless` (`independent_voice`), `budget_scale: diff`, effective 620c. Seven findings, triaged above:

| Id | Voice | Dissent severity | Triage |
|----|-------|------------------|--------|
| DISS-001 | gpt-5.5-pro | BLOCKING | Confirmed (yq `false // 600` → 600); held at MEDIUM, Observation 1 |
| DISS-002 | gpt-5.5-pro | BLOCKING | Confirmed; HIGH, Changes Required 2 |
| DISS-C-001 | claude-headless | ADVISORY | Confirmed; LOW, Observation 7 |
| DISS-C-002 | claude-headless | ADVISORY | Confirmed (schema lacks `reason`); LOW, Observation 7 |
| DISS-C-003 | claude-headless | ADVISORY | Confirmed scenario, no instance in tree; LOW, Observation 6 |
| DISS-C-004 | claude-headless | ADVISORY | Partly: traceback/exit 1 real, but `grade_recall` raises `GradeError`, so no silent model-miss; LOW, Observation 6 |
| DISS-C-005 | claude-headless | ADVISORY | Confirmed; MEDIUM, Observation 2 |

## Rejected dissent payloads

None — `metadata.rejected_summary` is empty and the named sidecar `adversarial-rejected-review.jsonl` has zero rows.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | The two HIGH defects above; AC Verification and test evidence in the report |

---

## Acceptance Criteria Check

### Task 1.1: review the pull request

| Criterion | Status | Notes |
|-----------|--------|-------|
| "review the pull request, report each defect it introduces with the file and line it sits on" (sprint.md Success Criteria) | Done (this file) | Every finding cites `head/<path>:<line>` |
| "give a merge verdict" | Done | CHANGES_REQUIRED: two HIGH defects |
| Implementation report carries `## AC Verification` | Fail | `reviewer.md` is the PR title only |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (dissent secret scan: 1 redaction applied to the prompt, none in the diff itself)
- [x] Input validation at trust boundaries present (path normalisation in `answer_set`/`safe_rel`, O_NOFOLLOW reads, symlink-refusing overlay) — see Observation 2 for the one sandbox read that bypasses it
- [x] No command injection: `_sm_oracle_py` passes paths as argv; `git` runs with `--literal-pathspecs`, no pager, isolated env
- [x] No SQL/XSS surface
- [x] Dependencies unchanged (stdlib Python, jq, yq)
- [x] Error messages do not leak sensitive data (evidence lines are key=value, digests only)

---

## Code Quality Summary

**Strengths:**
- The overlay/check/took-effect trio share one Python core, so pre-launch and post-run read the same comparison.
- The numeric anchor is additive and byte-neutral for symbol-only findings (NRM-70 proves it); the budget scaling is off by default and the envelope changes only when the key is written (BSC-1/BSC-8).
- Report 1.3 fixed a latent shared-row mutation (`row = dict(row)`) while adding the sensitivities.
- Tests are deliberate about trust boundaries (fixture outside the run dir, agent-writable `pr/` never read).

**Areas for Improvement:**
- Toggle/overlay ordering (Changes Required 1) needs an explicit model of which toggles may lawfully touch answer paths.
- The scope heuristics in the grader need signature/comment/tab awareness before they are the decision statistic.
- Functions over 100 lines in the grader and the mount core.

---

## Next Steps

1. Fix the two HIGH items (toggle/overlay ordering with a test; Python signature handling with a test).
2. Address or explicitly defer the MEDIUM items (DISS-001 `//` read; sandbox-config read in the row writer; `2>&1` segmenting).
3. Run the ten bats suites and record the summaries plus an `## AC Verification` walkthrough in `grimoires/loa/a2a/sprint-1/reviewer.md`.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":5,"low":11},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T12:17:30Z"} -->
