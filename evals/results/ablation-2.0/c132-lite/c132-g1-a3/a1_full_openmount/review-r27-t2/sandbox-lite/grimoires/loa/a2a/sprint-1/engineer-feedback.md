# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Change under review:** `pr/head.diff` — feat(cycle-131): sprint-263 — closed review-catch mount, grader 1.3.0 with three results and an oracle detector, dissent line anchors + budget_scale, curated multi-site labels, versioned re-grade (35 files)

---

## Overall Assessment

The closed mount (`lib/sandbox-mount.sh` overlay, pre-launch check, took-effect `oracle_closed`), the budget scaling and numeric anchors in `adversarial-review.sh`, the report 1.3 partitions/sensitivities and the row writer 1.4 fields are well structured, heavily tested and, where I could run them, pass their suites: `sandbox-mount.bats` 11/11 (+1 skip), `eval-recall-grader.bats` 37/39 (the two failures need corpus fixtures absent from this snapshot), `ablation-report.bats` AR-48..AR-52 all pass (AR-33/AR-34 fail identically on the base tree, so they are pre-existing and environmental). `ablation-grade.bats`, `took-effect.bats`, `pipeline-run.bats`, `run-ablation.bats` and the two `tests/unit/*.bats` files need suite roots, run fixtures or helper libraries that are not in the PR snapshot and could not be executed here.

Three defects block the merge, all in the sprint's two headline graders:

1. The oracle detector's diff form discards every tool result flagged `is_error`, but Claude Code flags a non-zero Bash exit as `is_error` while keeping the output, and `diff` exits 1 exactly when the files differ. A bare `diff pr/head/X X` — the canonical oracle probe — is therefore never counted, and a test pins that behaviour as correct.
2. Grader 1.3.0's same-scope rule mis-detects bash function headers: any zero-argument method call (`out.pop()`, `conn.close()`) inside the Python heredocs that dominate this repository's `.sh` files registers as a bash definition and splits the enclosing function's scope. Reproduced: a site and a citation inside the same function, separated by such a line, get no credit.
3. The Python branch of end-of-definition detection ends a function at the continuation line of a multi-line signature (`def f(\n    x,\n):`), excluding the whole body from its scope. Reproduced.

Both grader defects move `recall` — the report's new decision statistic — silently, without any error. The `_pm3` results are unaffected.

The adversarial dissent ran with two voices (gpt-5.5-pro primary, claude-headless companion): one BLOCKING finding (item 3 above, verified) and four ADVISORY findings (item 2 above, verified and promoted; the other three recorded under Observations). No rejected payloads.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Oracle detector — the diff form never sees a differing `diff`

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:2390` — `oracle_scan` skips a `tool_result` whose `is_error` is true ("the tool failed … nothing printed"). `diff`, `sdiff` and `git diff --no-index` exit 1 when the operands differ, and the Claude Code transcript records a non-zero Bash exit as `is_error: true` with the output still in `content` (verified on this session's own transcript: `{"is_error":true,"content":"Exit code 1\n<output>…"}`). So the detector drops exactly the result that exposes the later copy; only a `diff` whose exit code is neutralised (`| head`, `|| true`, a loop whose last command succeeds) is counted.
**File:** `head/evals/harness/ablation-grade.sh:2390`; the behaviour is pinned as correct by `head/evals/tests/ablation-grade.bats:1500` (AG-48 case 9: a differing `20c20` result with `is_error` true must expose nothing).
**Issue:** The documented lower bound is far looser than described: the headline probe (`diff pr/head/.claude/x.sh .claude/x.sh`) is invisible, so `oracle_exposed_defects` under-reports and the report's oracle-exposed sensitivity (and `--exclude-oracle-exposed true`) keeps contaminated cells.
**Required Fix:** Treat `is_error` as "nothing printed" only when the content carries no diff body — e.g. skip when `content` is empty, or when every line matches `ERR_LINE` / `^Exit code \d+$`, and otherwise parse the content as today. Flip AG-48 case 9 to expect `diff=d1` and add a case with the Claude Code shape (`Exit code 1\n20c20\n< a\n---\n> b`, `is_error` true). Keep the skip for a hook block / refused command (content that is only the error text).

### 2. Grader 1.3.0 — a zero-argument method call is a bash function header

- **HIGH** (confidence: high) `head/evals/graders/recall-vs-defects.sh:210` — `BASH_HDR[0]` is `^(\s*)(?:function\s+)?[A-Za-z_][A-Za-z0-9_.:-]*\s*\(\)\s*\{?`: the name class admits `.` and the brace is optional, so `out.pop()`, `conn.close()`, `f.flush()`, `lst.sort()` match as definition headers. `headers()` (`:266`) runs on every line of a `.sh` file with no heredoc awareness, and this repository's harness scripts embed large Python heredocs (the grader itself has `out.pop()` at `:243`).
**Issue:** Reproduced with the head grader: a function `alpha() { python3 - <<PY … out.pop() … PY }`, defect site at line 5, citation at line 20 (both inside `alpha`) → `detected: []`, `credits_function_only: []`. The bogus header splits the real scope (deflation); an indented method call whose span is not clipped by a `}` at its own indentation also runs past the enclosing function's end and gives top-level sites a scope they should not have (inflation, per the dissent DISS-C-001). `recall` and `credits_function_only` drift from the documented rule without an error, in the dominant fixture file type.
**Required Fix:** Disallow `.` in the function name (`[A-Za-z_][A-Za-z0-9_:-]*`), require a `{` on the header line or as the first token of the next line, and clip each nested span to its enclosing span's end (`min(end, parent_end)`). Add an RG case with a Python heredoc containing `x.pop()` inside a bash function.

### 3. Grader 1.3.0 — a multi-line Python signature ends the function at line 2

- **HIGH** (confidence: high) `head/evals/graders/recall-vs-defects.sh:302-309` — the Python branch of `close_line` returns `last` at the first later non-blank, non-comment line indented no deeper than the `def`. For `def check(\n    value,\n):` the `):` line has indentation 0 ≤ `lv`, so the definition is lines 1–2 and the whole body is top-level (scope `None`). Dedented lines inside multi-line string literals end the span the same way.
**Issue:** Reproduced with the head grader: site at line 6, citation at line 18 of such a function → `detected: []`. A citation inside the function body more than 3 lines from the site receives no same-scope credit, lowering `recall` and failing reviews that satisfy the documented rule. (Dissent DISS-001, BLOCKING, verified.)
**Required Fix:** Determine Python spans with `ast` (`FunctionDef.lineno`/`end_lineno`, `tokenize` fallback for files that do not parse), or at least continue the header through balanced parentheses to the line ending in `:` before applying the dedent rule. Add an RG case with a multi-line signature.

---

## Observations

### 1. Row writer 1.4 — dissent absence classification

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-row.sh:478-479` — `reason()` maps an envelope to `budget` (status `budget_exceeded`), `preflight` (status or record-fallback reason naming it), `error` (status `failed` or `recorded_by: record-fallback`) and otherwise `none`. `adversarial-review.sh` writes `status: "api_failure"` directly (no `recorded_by`) when every hop fails (`head/.claude/scripts/adversarial-review.sh` lines 1426 and 4739), and also `refused`, `ceded`, `fold_failed`, `malformed_response`; none of those contain "preflight", so such an envelope is rowed `dissent_absent_reason: none` ("the dissent ran"). The dissent-absent sensitivity then keeps exactly the rows it is meant to exclude.
**Suggestion:** Map `api_failure`, `malformed_response`, `refused`, `ceded`, `fold_failed` (and any status that is not `reviewed`/`clean`) to `error`, and add RW14-3 cases for them.

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-row.sh:393-394` and `:466` — the `disabled` reason is derived from `$RUN_DIR/sandbox/.loa.config.yaml`, the agent-writable surface that `ablation-grade.sh`'s header calls tamperable. An agent that sets `flatline_protocol.code_review.enabled: false` after the gate failed turns `error` into a planned `disabled` absence; `mount_integrity` records the config change elsewhere but this field does not consult it. (Dissent DISS-C-002.)
**Suggestion:** Derive `disabled` from harness-owned evidence only (`dissent=false`, a mount-time copy of the config, or the gate flags `apply_arm_toggles` wrote), or honour the sandbox file only when `pipeline.json.mount_integrity.loa_config` reports it unchanged.

### 2. Closed mount — clause (d) and the agent's own git activity

- **MEDIUM** (confidence: medium) `head/evals/harness/lib/sandbox-mount.sh:1040` — `cmd_check` fails `oracle_closed` when `git rev-list --all` is anything but `[base_commit]`. Any commit or stash the reviewing agent makes in the sandbox (Loa skills `git add`/`commit`; `git stash` creates `refs/stash`) rows the trial `infrastructure_error` and pauses the arm (DEC-0418) although no later blob entered the store. The leakage signal that matters — the later-only pinned blob check at `:1050-1052` — stands on its own.
**Suggestion:** Keep "no remote, no alternates, no later-only blob" as the fail clauses; report extra commits/refs as evidence (or require only that `base_commit` is an ancestor of every ref) instead of failing the run.

### 3. Grader 1.3.0 — further scope-detection gaps

- **MEDIUM** (confidence: medium) `head/evals/graders/recall-vs-defects.sh:214` — `MD_HDR` (`^(#{1,6})(?:\s|$)`) has no fence awareness, so `# comment` lines inside fenced bash blocks in `.md` files (common in `.claude/**/*.md`) are level-1 headings: a site and a citation in the same prose section separated by a code block with a `#` line are in different scopes, and the heading hierarchy below the fence is reset.
**Suggestion:** Skip lines between ``` fences in `headers()` for markdown.

- **MEDIUM** (confidence: low) `head/evals/graders/recall-vs-defects.sh:135` — the head-directory fallback is `$workspace/pr/head`, the copy the graded agent can write. `ablation-grade.sh` sets `EVAL_HEAD_DIR` only when `resolve_pr_fixture` succeeds (`head/evals/harness/ablation-grade.sh:1633-1634`); when it raises, the grader reads the sandbox copy (`grading/pr/head`) and the agent controls the validity rule (file length) and the scope map.
**Suggestion:** In `grade_recall`, fail the grade (GradeError) when the fixture does not resolve instead of letting the grader fall back; standalone use keeps the fallback.

- **LOW** (confidence: medium) `head/evals/graders/recall-vs-defects.sh:299` — the bash close check compares `len(t) - len(t.lstrip())` with `lv`, but `lv` was computed with `expandtabs(8)` (`:283`), so a tab-indented function never finds its `}` and runs to the next header.

- **LOW** (confidence: medium) `head/evals/graders/recall-vs-defects.sh:287` and `:295` — `CLOSE_ONE` (`\{.*\}\s*(?:#.*)?$`) reads a header like `f() {  # see } below` as a one-line function, since the `}` inside the comment satisfies the pattern.

### 4. Oracle detector and KF-046 exemption — smaller gaps

- **LOW** (confidence: high) `head/evals/harness/ablation-grade.sh:1991` — for a backticked occurrence the exemption unit is the backtick span's content, which for `` `0xHoneyJar/loa` `` is the token itself and is a substring of every fixture line holding the token. Once the PR fixture mentions the repository anywhere, any Write/Edit/Grep value quoting the name in backticks is exempt regardless of context (AG-51's negative case covers only a fixture without the token).
**Suggestion:** Require the unit to be the whole line when the span is just the token, or require a minimum unit length beyond the token.

- **LOW** (confidence: medium) `head/evals/harness/ablation-grade.sh:1570` — the numeric anchor is cited on the anchor's path part only when it ends in a 1–6 character extension; an anchor on an extensionless file (`Makefile`, `Dockerfile`, `.envrc`, a script without suffix) falls back to the finding's `file`, which dissent findings rarely carry, so the citation is lost.

### 5. adversarial-review.sh — budget scaling

- **LOW** (confidence: high) `head/.claude/scripts/adversarial-review.sh:189-199` — under `diff`, `effective = min(max(conf, ceil(est×1.2)), max)`; since `ceil(est×1.2) ≥ est`, the gate reduces to `est ≤ budget_cents_max`: `budget_cents`, `--budget` and the 1.2 factor never change the refuse/allow decision, and `budget_cents_effective` is a function of the estimate rather than a limit that was applied. This matches the SDD D-4.2 formula, so it is a design observation, but the example config and both ADVERSARIAL-REVIEW.md pages present `budget_cents` as a meaningful floor under `diff`. (Dissent DISS-C-003.)
**Suggestion:** Document that under `diff` the only enforced limit is `budget_cents_max`, or make the ceiling `max(budget_cents, budget_cents_max)` so an explicit budget is never lowered.

- **LOW** (confidence: low) `head/.claude/scripts/adversarial-review.sh:164-172` — when `yq` cannot read the config the tag is `unreadable`, which is neither `!!null` nor empty, so `CONF_BUDGET_SCALE_SET` becomes true and the WARN names the value as `(a unreadable, not a string)`; the envelope then carries `budget_scale` metadata for a config that never wrote the key. Reachable only with a malformed YAML file (the missing-file case returns earlier).

- **LOW** (confidence: medium) `head/.claude/schemas/adversarial-finding.schema.json:226-231` — `$defs.metadata` has `additionalProperties: false` and a `status` enum of `api_failure|malformed_response|clean|reviewed`; the PR adds `budget_scale`/`budget_cents_effective`/`budget_cents_max` but not `budget_exceeded`, the new `reason`, nor the existing `estimated_cents`/`budget_cents`/`estimate_voices`, so the `budget_exceeded` envelope the gate writes (`head/.claude/scripts/adversarial-review.sh:4445`) violates the documented contract and `ablation-row.sh` keys on a status the schema says cannot occur. Partly pre-existing (the base enum lacked it too). (Dissent DISS-C-004.)

### 6. Tests and documentation

- **LOW** (confidence: low) `head/evals/tests/ablation-grade.bats:1544` — AG-50 reads `evals/tests/fixtures/c131-oracle/<name>/{transcripts,dotclaude,task}`, which this PR does not add (not among the 35 files); if the fixtures are not already on the base, the test errors at `cp -a`. AG-50 and AG-51 also depend on `grimoires/loa/evals/ablation-2.0-replication` and `evals/fixtures/review-prs/pr-18`, outside the diff. Could not be verified here.

- **LOW** (confidence: high) `head/evals/harness/ablation-grade.sh:349` — no CHANGELOG entry is part of the diff (grader 1.3.0, report 1.3, row writer 1.4, grader schema additions). The documentation-verification rule asks for one per task; `pr/PR.md` carries a title only.

### Dissent findings not promoted

DISS-C-001, DISS-C-002, DISS-C-003 and DISS-C-004 are recorded above (items 2, Observations 1, 5, 5). DISS-001 (BLOCKING) is Changes Required item 3.

---

## Rejected dissent payloads

None. `metadata.rejected_summary` is empty and `adversarial-rejected-review.jsonl` holds 0 rows (two voices: gpt-5.5-pro primary, claude-headless companion, both succeeded).

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

Sprint success criterion: "review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict".

| Criterion | Status | Notes |
|-----------|--------|-------|
| Closed mount overlay / pre-launch check / `oracle_closed` | Pass | `sandbox-mount.bats` 11/11 here; clause (d) scope concern under Observations |
| Grader 1.3.0 three results and same-scope rule | Fail | Changes Required 2 and 3: header and span detection mis-scope common code shapes |
| Oracle detector (diff and read forms) | Fail | Changes Required 1: `is_error` results skipped |
| Numeric anchors and `budget_scale` in `adversarial-review.sh` | Pass | Schema/doc gaps under Observations |
| Report 1.3 partitions, beside figures, sensitivities, 4-cell minimum | Pass | AR-48..AR-52 pass here |
| Row writer 1.4 fields and `--validate` | Pass with gaps | `dissent_absent_reason` classification under Observations |
| `--allow-partial` plumbing | Not run | `run-ablation.bats` needs fixtures absent here; wiring reads correct |

`reviewer.md` carries no `## AC Verification` section (it is the PR title), which the skill also treats as CHANGES_REQUIRED.

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [x] Input validation and sanitization present (path normalisation, symlink refusal, bounded reads in the overlay and detector)
- [x] Authentication/authorization — n/a
- [x] No SQL/XSS injection vulnerabilities
- [x] Dependencies secure — stdlib only
- [x] Error messages don't leak sensitive data
- [ ] Trust boundary: the row writer reads the agent-writable sandbox config (Observation 1) and the grader can fall back to the agent-writable `pr/head` (Observation 3)

---

## Code Quality Summary

**Strengths:**
- One Python core (`_sm_oracle_py`) serves overlay, pre-launch check and post-run rule, so the launched surface and the verdict use the same comparison.
- Fail-closed configuration parsing (`budget_scale`, `budget_cents_max`), byte-for-byte unchanged envelope when the key is absent, and explicit `_pm3`/`_pm3_v1` results so 1.2.x grades stay reproducible.
- Extensive bats coverage with negative cases; the sandbox-mount suite is self-contained and green.

**Areas for Improvement:**
- Regex-based definition detection for bash/python/markdown is the sprint's weak point: heredocs, method calls, multi-line signatures and fenced code all break it. Either tokenise properly or document the rule as "indentation-and-regex scope" and accept the drift in the SDD.
- The oracle detector's error-result rule contradicts the executor's transcript format; add a transcript-shape fixture from a real run to the unit tests.

**Complexity:** `oracle_scan` (~120 lines) and `cmd_check` (~100 lines) exceed the 50-line guideline; both are linear and commented, no circular dependencies. `SIMPLICITY`: Lean already for the overlay; the grader could drop `BATS_HDR` (the bash forms already cover `setup()`/`teardown()`; `@test` needs its own) — net: ~0 lines. Ship after the fixes.

---

## Next Steps

1. Fix the three Changes Required items (oracle `is_error` rule; bash header regex and span clipping; Python multi-line signature spans) with the named regression cases.
2. Re-run `evals/tests/eval-recall-grader.bats`, `evals/tests/ablation-grade.bats` AG-45..AG-51 and `evals/tests/ablation-row.bats` RW14-*.
3. Update the report in `grimoires/loa/a2a/sprint-1/reviewer.md` with an `## AC Verification` walkthrough.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":5,"low":9},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T00:20:00Z"} -->
