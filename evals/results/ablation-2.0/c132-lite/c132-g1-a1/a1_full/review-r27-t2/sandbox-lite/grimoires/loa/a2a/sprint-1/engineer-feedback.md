# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)

---

## Overall Assessment

The change (cycle-131 sprint-263; 35 files, 5,873 diff lines) is well-structured and heavily tested: the closed-mount overlay and its check share one Python core, the budget scaling fails closed, the numeric anchor is dropped silently and never rejected, and the new bats suites cover the stated edge cases. All head shell files pass `bash -n`, the Python compiles, and the JSON/YAML parses.

Three findings block the merge. The PR's own unit test BSC-9 asserts a property of the operator's live config that the PR's example config contradicts. AG-50 depends on `evals/tests/fixtures/c131-oracle/*` transcripts and curated `manifests/pr-17.json` / `manifests/v1/` snapshots that are not in the change, which also means the "curated multi-site labels, versioned re-grade" in the title has no files behind it. And the grader's Python end-of-definition rule ends a definition on the argument line of any wrapped signature, so the same-scope clause never credits inside such functions (confirmed by reproduction; also raised as BLOCKING by the gpt-5.5-pro dissent voice).

The implementation report is a one-line title with no `## AC Verification` walkthrough and no CHANGELOG entry is in the diff; per the skill this alone would prevent approval, but the verdict here follows the finding counts.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Testing — a unit test reads the operator's live config

- **HIGH** (confidence: high) `head/tests/unit/adversarial-review-budget-scale.bats:196` — BSC-9 asserts `.flatline_protocol.code_review.budget_scale` (and `security_audit`, line 197) is `absent` in the live `.loa.config.yaml`; the same PR writes `budget_scale: fixed` into `.loa.config.yaml.example` (`head/.loa.config.yaml.example:1643`, `:1707`) whose header says "Copy sections you need to your .loa.config.yaml file".
**File:** `head/tests/unit/adversarial-review-budget-scale.bats:195-198`
**Issue:** The test's outcome depends on an untracked, operator-owned file. Copying the example's flatline section (the documented way to configure the gate), or enabling `diff` as this workspace's live config does (`budget_scale: diff`, `budget_cents_max: 1200` on both gates), makes `[ "fixed" = "absent" ]` fail and the PR's own suite red.
**Why This Matters:** A red unit suite blocks every downstream gate for any operator who follows the PR's own documentation; the assertion verifies nothing about the change.
**Required Fix:** Delete lines 195-198, or point the assertion at a fixture config the test writes itself.

### 2. Testing / Scope — AG-50 depends on fixtures and manifests not in the change

- **HIGH** (confidence: medium) `head/evals/tests/ablation-grade.bats:1544` — `real_run` copies `evals/tests/fixtures/c131-oracle/<run>/transcripts` (and `task`, `dotclaude/`) for four cycle-130 runs, and AG-50 (`:1558`) pins "nine sites under the curated anchors (eight under manifests/v1)" for pr-17 (DEC-0626). None of `evals/tests/fixtures/c131-oracle/*`, `evals/fixtures/review-prs/manifests/*.json`, `manifests/v1/*` or `SHA256SUMS` are among the 35 files in `head.diff`.
**File:** `head/evals/tests/ablation-grade.bats:1543-1576`
**Issue:** On the change as submitted `cp -a "$fx/transcripts" "$rd/"` fails (no such directory) and AG-50 errors; the pinned d-position sets depend on manifest curation that is not here. The PR title and report claim "curated multi-site labels, versioned re-grade" with no corresponding files.
**Why This Matters:** Either the deliverable is missing from the sprint, or the test is bound to files from another change and the report must say so; as written the new suite cannot pass from this change alone, and the grader's `recall_pm3_v1` path (`manifests/v1/`) is untested against real data.
**Required Fix:** Add the fixture directories and curated manifests (with the SHA256SUMS update RG-17 checks) to the change, or remove AG-50 / the title claim and state in the report where they land.

### 3. Grader correctness — wrapped Python signatures end the definition early

- **HIGH** (confidence: high) `head/evals/graders/recall-vs-defects.sh:308` — `close_line` for python returns `last` at the first non-blank, non-comment line indented no deeper than the `def`; for `def f(\n    argument,\n):` the `):` line has the header's indentation, so the definition ends on line h+1 and every body line gets no scope. Reproduced: the span for a 6-line function closes at line 2.
**File:** `head/evals/graders/recall-vs-defects.sh:302-311`
**Issue:** For any Python function with a multi-line signature, the same-scope clause (ii) can never credit a defect; a citation in the right function more than three lines from the site is a miss, contradicting the rule the header documents (lines 60-70) and the `credits_function_only` diagnostic. Raised independently as BLOCKING by the gpt-5.5-pro dissent voice (DISS-001).
**Why This Matters:** `defect_catch_rate` is the ablation's decision statistic (report 1.3); a systematic under-credit on one file class biases it in a way `recall_pm3_v1` will not reveal.
**Required Fix:** Advance past the signature before testing dedentation (e.g. skip lines until the one ending in `:` with balanced parentheses, or use `ast` to get the function's `end_lineno`); add a RG test with a wrapped signature.

---

## Observations

### 1. Grader scope heuristics (recall-vs-defects.sh)

- **MEDIUM** (confidence: medium) `head/evals/graders/recall-vs-defects.sh:295` — `CLOSE_ONE` (`\{.*\}\s*(?:#.*)?$`) plus `"{" in header` treats a header whose trailing comment contains `}` (e.g. `f() {  # writes ${OUT}`) as a one-line function, so its body gets no scope and clause (ii) under-credits. Companion voice DISS-C-003 raised the same point.
**Suggestion:** Strip the `#…` comment before the one-line test, or require the `}` to be followed only by `;`/whitespace.
**Benefit:** Headers with `${VAR}` in their comment are common in this repository's own scripts.

- **LOW** (confidence: high) `head/evals/graders/recall-vs-defects.sh:299` — the `}` indentation is `len(t) - len(t.lstrip())` while `headers()` used `expandtabs(8)` (line 283); a tab-indented nested function never finds its closing brace and its scope runs to the next header.
**Suggestion:** Use the same `expandtabs(8)` measure on both sides.

- **MEDIUM** (confidence: medium) `head/evals/graders/recall-vs-defects.sh:135` — with `EVAL_HEAD_DIR` unset and no `<manifest dir>/../<fixture>/head`, the grader reads `$workspace/pr/head`, the agent-writable sandbox copy, for citation validity (line counts) and definition scopes. An agent that rewrites a file there into one ≤400-line function makes any citation in it credit every defect of that file. The ablation harness sets `EVAL_HEAD_DIR` to the immutable fixture (ablation-grade.sh:1631-1636), but the standalone grader path does not. (Companion voice DISS-C-004.)
**Suggestion:** Drop the sandbox fallback, or disable clause (ii) and the length rule when it is used and record `head_dir_source` in details.

- **LOW** (confidence: high) `head/evals/graders/recall-vs-defects.sh:355` — a range whose end is past EOF credits nothing even when its first line is valid (`file:40-9999` in a 60-line file), while `file:40` credits; the EOF rule runs before the `RANGE_CAP` first-line reduction. Documented order, but it penalises the more informative citation.
**Suggestion:** Apply the cap first, then the EOF test on the reduced range.

- **LOW** (confidence: medium) `head/evals/graders/recall-vs-defects.sh:272` — `BASH_HDR[0]` matches any `name()` / `x.y()` with empty arguments at line start, so Python lines inside heredocs in `.sh` files (e.g. `ds.sort()` in ablation-grade.sh) open spurious nested "bash functions" that fragment the enclosing scope.
**Suggestion:** Require `{` on the header line or the next non-blank line, or skip heredoc bodies as the contamination scanner already does.

### 2. Closed mount and took-effect (sandbox-mount.sh, took-effect.sh)

- **MEDIUM** (confidence: medium) `head/evals/harness/lib/sandbox-mount.sh:1038` — clause (d) requires `rev-list --all` to equal exactly the base commit and `fsck --unreachable --no-reflogs` to report nothing. Any `git commit`, `git stash`, or `git add` followed by `git reset` by the agent in the sandbox fails `oracle_closed` post-run → infrastructure_error → the a1_full arm is paused (`head/evals/suites/ablation-2.0.yaml:77`), although only the later-blob (line 1049), remote and alternates checks bear on the oracle.
**Suggestion:** Keep (d) to "no later-only pinned blob in the object store, no remote, no alternates"; report extra commits as evidence rather than FAIL, or restrict the commit check to refs other than the agent's own.
**Benefit:** A control-arm pause from benign agent git use halts the whole batch (DEC-0418).

- **MEDIUM** (confidence: high) `head/evals/harness/lib/sandbox-mount.sh:958` — `cmd_check` is 190 lines carrying four clauses in one body; `oracle_scan` (`head/evals/harness/ablation-grade.sh:2312`) is ~120 lines and `oracle_plan` (`:2435`) 68. COMPLEXITY: over the 50-line bound with no justification comment.
**Suggestion:** Split per clause / per form (`check_a_c`, `check_b`, `check_d`; `scan_diff_result`, `scan_read_result`). `net: 0 lines possible` — this is a structure, not a size, concern.

- **LOW** (confidence: high) `head/evals/harness/ablation-row.sh:419` — `evkv` reads the LAST `key=` evidence line; `took-effect.sh evidence_line` (`head/evals/harness/took-effect.sh:345`), `read_evidence` (`head/evals/harness/lib/sandbox-mount.sh:954`) and `check_mount_closed` (`:1122`) read the FIRST; `pipeline-run.sh` (`head/evals/harness/pipeline-run.sh:560`) the last. A duplicated key (RW14-2 deliberately appends one) yields different values per consumer.
**Suggestion:** One rule (first wins, as the harness appends) in all five readers.

### 3. Grader contamination and oracle detector (ablation-grade.sh)

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:1991` — the KF-046 class 7 unit is the backtick span holding the token, so a bare `` `0xHoneyJar/loa` `` is a substring of any fixture line holding the token and is exempt whenever the fixture has one. `gh api repos/\`0xHoneyJar/loa\`/pulls/1283` passes the contamination scan on pr-18 (AG-51's own second case only passes because it has no backticks).
**Suggestion:** Require the unit to be at least the whole fixture line (or ≥ the token plus surrounding context), and never exempt a unit equal to the bare token.

- **LOW** (confidence: high) `head/evals/harness/ablation-grade.sh:2418` — `exposed_unknown` is emitted only when no range and no `must_match` hit anywhere in the section; the header (`:2031-2032`) says such a section "marks every other defect of that file exposed_unknown". A section that hit one defect leaves the others unrecorded.
**Suggestion:** Align the code or the comment (mark the non-hit defects unknown when the section had body but no ranges).

### 4. Adversarial review budget scaling (adversarial-review.sh, example config, schema)

- **MEDIUM** (confidence: high) `head/.claude/scripts/adversarial-review.sh:163` — when `yq eval … | tag` fails (no `.loa.config.yaml`, unparsable YAML, `yq` missing) the fallback is the literal `unreadable`, which is neither `!!null` nor empty, so line 168 sets `CONF_BUDGET_SCALE_SET=true`, a WARN reading `budget_scale='(a unreadable, not a string)'` is logged, and the envelope gains the three budget keys and `reason`. Every other read in `load_adversarial_config` degrades silently to its default on yq failure (e.g. `:258`). (Companion voice DISS-C-001.)
**Suggestion:** `|| echo '!!null'`, or return 0 when `$CONFIG_FILE` is not a readable file.

- **LOW** (confidence: high) `head/.loa.config.yaml.example:1643` — writing `budget_scale: fixed` explicitly (and `:1707`) means every operator who copies the example flips `CONF_BUDGET_SCALE_SET` (`head/.claude/scripts/adversarial-review.sh:168`) and gets the extended envelope shape plus `reason: budget`, while the PR documents the absent key as "the shipped gate, byte for byte".
**Suggestion:** Comment the keys out in the example (`# budget_scale: fixed`) as the documented default, or make `fixed` written and absent indistinguishable in the envelope.

- **LOW** (confidence: medium) `head/.claude/schemas/adversarial-finding.schema.json:248` — the metadata block keeps `additionalProperties: false` and gains the three budget keys but not `reason`, so the documented schema rejects the `budget_exceeded` envelope this change emits when the key is set. The block already lacks `rejected_summary`, `companion_voice`, `estimated_cents` and others, so this extends pre-existing drift rather than introducing it. (Companion voice DISS-C-005.)
**Suggestion:** Add `reason` (and the other live keys) or relax `additionalProperties` on metadata.

### 5. Row writer

- **LOW** (confidence: high) `head/evals/harness/ablation-row.sh:546` — an unknown `config_variant=` evidence value (RW14-2's `bogus`) is silently written as `shipped`, misreporting a run under an unexpected variant.
**Suggestion:** Write `null` (or the raw value) and let `--validate` reject it.

### 6. Process / documentation

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:360` — no CHANGELOG entry anywhere in the 35-file change for grader 1.3.0, row writer 1.4, report 1.3, the closed mount, or the dissent anchors; `pr/PR.md` (the implementation report) is a one-line title with no `## AC Verification` walkthrough and no self-check (fast-gate) evidence. FAST-GATE: no record that the bats suites or shellcheck ran.
**Suggestion:** Add the CHANGELOG entries per task and an AC walkthrough with `file:line` evidence and the test run output.

---

## Cross-Model Observations

Two voices answered (`verdict_quality.voices_succeeded: 2`; primary gpt-5.5-pro, companion claude-headless, `counted_as: independent_voice`). The run truncated the 352 KB diff to 13 of 35 files (24,000-token budget), so the dissent did not see the row writer, report, suite, took-effect or test files. Envelope: `grimoires/loa/a2a/sprint-1/adversarial-review.json`.

| Finding | Voice | Triage |
|---------|-------|--------|
| DISS-001 BLOCKING — wrapped Python signatures end the definition early (`recall-vs-defects.sh:308`) | gpt-5.5-pro | Confirmed by reproduction; counted as Changes Required #3 |
| DISS-C-001 ADVISORY — yq failure reads as `unreadable` and flips `CONF_BUDGET_SCALE_SET` | claude-headless | Confirmed (no `-f` guard in `load_adversarial_config`); Observations §4 MEDIUM |
| DISS-C-002 ADVISORY — `_budget_meta` may be unset at envelope assembly | claude-headless | Not a defect: `local _budget_meta="{}"` at `:4435` is unconditional in `main` and the only exit between it and `:4750` (dry-run, `:4486`) returns before the envelope |
| DISS-C-003 ADVISORY — CLOSE_ONE one-liner and tab indentation | claude-headless | Same as my Observations §1 (MEDIUM + LOW) |
| DISS-C-004 ADVISORY — `$workspace/pr/head` fallback is agent-writable | claude-headless | Confirmed; Observations §1 MEDIUM |
| DISS-C-005 ADVISORY — schema metadata lacks `reason` under `additionalProperties: false` | claude-headless | Confirmed but pre-existing drift (other live keys also absent); Observations §4 LOW |

## Rejected dissent payloads

- None: `metadata.rejected_summary` is empty and the named sidecar `adversarial-rejected-review.jsonl` has zero rows.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | The `c131-oracle` test fixtures and the curated / v1 manifests the title and AG-50 name; CHANGELOG entries; an AC walkthrough in the report |

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff` (the PR's own claimed deliverables)

| Criterion | Status | Notes |
|-----------|--------|-------|
| Closed review-catch mount (overlay, pre-launch check, took-effect `oracle_closed`) | Pass with observations | `sandbox-mount.sh:1088-1133`, `pipeline-run.sh:553-578`, `took-effect.sh:368-392`; clause (d) strictness (Obs §2) |
| Grader 1.3.0 with three results and same-scope rule | Fail | Python wrapped-signature scope bug (CR #3); CLOSE_ONE / tabs (Obs §1) |
| Oracle detector (diff and read forms) | Pass with observations | `ablation-grade.sh:2312-2492`; `exposed_unknown` doc/code mismatch |
| Dissent line anchors (`anchor_line`, `anchor_line_end`) | Pass | `adversarial-review.sh:605-630`, `:1702-1707`; wire schemas, prompts, NRM-68..74 |
| `budget_scale` + `budget_cents_max` | Pass with observations | Gate at `adversarial-review.sh:4433-4453`; `unreadable` fallback (Obs §4); BSC-9 (CR #1) |
| Row writer 1.4 / report 1.3 | Pass | `ablation-row.sh:529-548`, `ablation-report.py` partitions, beside figures, 4-cell minimum |
| Curated multi-site labels, versioned re-grade | Fail | No manifest or `manifests/v1/` files in the change (CR #2) |
| `--allow-partial` plumbing | Pass | `run-ablation.sh`; grader already accepts the flag (`ablation-grade.sh:388`) |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [x] Input validation and sanitization present (path normalisation, symlink refusal, `python3 -I`, hardened git env)
- [x] Authentication/authorization correct (n/a)
- [x] No SQL/XSS injection vulnerabilities (n/a)
- [x] Dependencies secure (stdlib only; `jsonschema` optional in tests)
- [x] Error messages don't leak sensitive data (secret scan redaction kept; `last_error` allowlist untouched)

---

## Code Quality Summary

**Strengths:**
- One Python core (`_sm_oracle_py`) serves overlay, pre-launch check and post-run rule, so the launched surface and the verdict use the same comparison.
- Fail-closed numeric parsing for the budget knobs; numeric anchors never cause a rejection or repair hop; symbol anchor untouched.
- Extensive, scenario-driven bats coverage, including the real-library wiring test and the two-partition report fixture.

**Areas for Improvement:**
- Heuristic scope detection needs the signature/comment edge cases above and tests for them.
- Two functions near 200 and 120 lines; split per clause/form.
- Tests must not read operator-owned files or fixtures outside the change.

---

## Next Steps

1. Fix the three Changes Required (BSC-9 assertion, missing fixtures/manifests or the claim, Python signature scope).
2. Address the MEDIUM observations or record the accepted ones in NOTES.md.
3. Run the bats suites and record the output in `grimoires/loa/a2a/sprint-1/reviewer.md` with an `## AC Verification` walkthrough.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":7,"low":8},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T17:45:00Z"} -->
