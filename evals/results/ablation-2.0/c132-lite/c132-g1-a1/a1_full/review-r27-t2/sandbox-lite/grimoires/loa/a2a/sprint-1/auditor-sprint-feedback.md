# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)
**Change under audit:** `pr/head.diff` (cycle-131 sprint-263; 35 files, 5,873 diff lines). Citations are `head/<path>:<line>` with lines from `pr/head/`.

---

## Verdict: CHANGES_REQUIRED

---

## Pre-flight notes

- **Phase 0 prerequisite not met, audit run anyway by task direction.** `engineer-feedback.md` ends `CHANGES_REQUIRED` (counts high 3 / medium 7 / low 8, `excluded` 0), not "All good". The task for review-r27 directs this audit to run regardless, so the gate order deviation is recorded here rather than halting. `adversarial-review.json` carries `metadata.model: gpt-5.5-pro` (the review's dissent completed).
- **Known-failures surface degraded.** `grimoires/loa/known-failures.md` does not exist (session hook `KF-SURFACE` warning); triage ran without it.
- **Guardrails pre-check:** `guardrails-orchestrator.sh --skill auditing-security` returned `PROCEED`.
- **Scope analysis:** `security-audit-scope.sh --json` over `pr/head/`: sources 0, sinks 4 (command_exec 2, file_operations 2), auth files 2, LLM files 2. The change is harness, grader and gate shell/Python; there are no network endpoints. Trust boundaries that matter here: (1) the agent-writable sandbox (`<run>/sandbox/**`, including `pr/` and `.loa.config.yaml`) read by harness code after the run; (2) the operator's `.loa.config.yaml` read by the gate; (3) model output (dissent findings) normalised by the gate.
- **No `.reviewignore`** in the repository; nothing excluded.
- `br` is not installed; no beads comments or labels were written.

---

## Executive Summary

The change builds a closed review-catch mount (overlay, pre-launch check, post-run `oracle_closed`), grader 1.3.0 with a same-scope recall rule and an oracle detector, numeric dissent anchors plus `budget_scale`, and row/report fields. The security posture of the new harness code is good: the overlay writes with `O_EXCL|O_NOFOLLOW` after refusing symlinked ancestors (`head/evals/harness/lib/sandbox-mount.sh:889-908`), every Python core runs `python3 -I`, git in the agent-written sandbox repository runs with `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`, `-c core.fsmonitor=false`, `--no-pager`, `HOME=/nonexistent` and a 300 s timeout (`:639-651`), the budget knobs fail closed to `fixed`, and the grader's own reads are capped and symlink-refusing (`head/evals/harness/ablation-grade.sh:453`). No secrets, no injection sinks, no new network calls.

Three HIGH defects block the merge, all confirmed independently here: the grader's Python end-of-definition rule closes a wrapped-signature `def` on its argument line (reproduced: a 7-line function closes at line 3), so the same-scope clause can never credit inside such functions; the AG-50 test and the "curated multi-site labels, versioned re-grade" deliverable depend on `fixtures/c131-oracle/*` and `manifests/v1/*` files that are not in the change; and unit test BSC-9 asserts a property of the operator's live `.loa.config.yaml` that this very workspace's config violates (`budget_scale: diff` on both gates), so the PR's suite is red here today. Six MEDIUM and twelve LOW findings follow, mostly trust-boundary and fail-direction issues in the grader and harness; none is exploitable for code execution or data exfiltration.

**Security Issues Found:**

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 3 |
| Medium | 6 |
| Low | 12 |

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] Wrapped Python signature ends the definition on its argument line; the same-scope clause never credits inside it

**Severity:** HIGH (confidence: high)
**File:** `head/evals/graders/recall-vs-defects.sh:308`
**Issue:** `close_line` for python returns `last` at the first non-blank, non-comment line indented no deeper than the `def` (`:302-311`). For

```python
def f(
    a,
    b,
):
    x = 1
    return x
```

the `):` line has the header's indentation, so the definition is closed at line 3 and lines 4-6 get no scope. Reproduced in this audit with the head file's regexes: `wrapped-signature def ends at line 3 of 7`. Every Python function with a multi-line signature therefore has an empty scope, and clause (ii) of the documented rule (`:57-61`) can never credit a citation inside it; `credits_function_only` under-reports for one whole file class. The dissent voice gpt-5.5-pro flagged this as BLOCKING in the review phase (DISS-001).
**Impact:** `defect_catch_rate` is the ablation's decision statistic; a systematic under-credit on wrapped-signature Python biases arm comparisons in a way `recall_pm3_v1` cannot reveal.
**Fix:** Advance past the signature before testing dedentation (skip lines until the header's parentheses balance and the line ends with `:`), or use `ast.parse` and `end_lineno`; add an RG test with a wrapped signature.
**Reference:** CWE-682 Incorrect Calculation — https://cwe.mitre.org/data/definitions/682.html

### [HIGH-002] AG-50 and the "curated labels / versioned re-grade" deliverable depend on fixtures and manifests that are not in the change

**Severity:** HIGH (confidence: medium)
**File:** `head/evals/tests/ablation-grade.bats:1546` (`cp -a "$fx/transcripts" "$rd/"`; `real_run` at `:1543-1555`; AG-50 at `:1558`)
**Issue:** `real_run` copies `evals/tests/fixtures/c131-oracle/<run>/{transcripts,task,dotclaude}` for four cycle-130 runs and AG-50 pins exact exposure sets against the curated `manifests/pr-17.json` ("nine sites under the curated anchors") and `manifests/v1/` ("eight"). `pr/head/evals/tests/fixtures/` holds only `ablation-grade-stub.sh`, `ablation-pipeline-stub.sh`, `ablation-report/` and `mount-lib-stub.sh`; no `evals/fixtures/` path is among the 35 files although `c131-oracle`, `manifests/v1` and `manifests/pr-17` are named 13 times in the diff. On the change as submitted `cp -a` fails and AG-50 errors; the grader's `recall_pm3_v1` path and the row writer's `defect_catch_rate_pm3_v1` are untested against real data.
**Impact:** Either the sprint's deliverable is missing, or the suite is bound to files from another change and the report does not say so. Confidence is medium because the fixtures could already exist upstream; the PR title claims them as part of this change.
**Fix:** Add the fixture directories, curated manifests and the `SHA256SUMS` update (RG-17 checks it) to the change, or drop AG-50 and the title claim and record where they land.
**Reference:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html

### [HIGH-003] Unit test BSC-9 asserts the operator's live config, which this repository already violates

**Severity:** HIGH (confidence: high)
**File:** `head/tests/unit/adversarial-review-budget-scale.bats:196` (and `:197`)
**Issue:**

```bash
if [[ -f "$PROJECT_ROOT/.loa.config.yaml" ]]; then
    [ "$(yq eval '.flatline_protocol.code_review.budget_scale // "absent"' "$PROJECT_ROOT/.loa.config.yaml")" = "absent" ]
    [ "$(yq eval '.flatline_protocol.security_audit.budget_scale // "absent"' "$PROJECT_ROOT/.loa.config.yaml")" = "absent" ]
fi
```

The outcome depends on an untracked, operator-owned file. This workspace's `.loa.config.yaml` sets `budget_scale: diff` and `budget_cents_max: 1200` on both gates (read during this audit), so `[ "diff" = "absent" ]` fails and the PR's own suite is red here. The same PR writes `budget_scale: fixed` into `head/.loa.config.yaml.example:1643` and `:1707`, whose header tells operators to copy sections into the live file; following that documentation also turns the test red.
**Impact:** A deterministic red unit suite blocks every downstream gate for any operator who enables the feature or follows the example; the assertion verifies nothing about the change.
**Fix:** Delete `:195-198`, or point the assertion at a fixture config the test writes itself under `$BATS_TEST_TMPDIR`.
**Reference:** CWE-1164 Irrelevant Code / brittle test — https://cwe.mitre.org/data/definitions/1164.html

---

## Medium Priority Issues

### [MED-001] The standalone grader reads the agent-writable sandbox `pr/head` for validity and scope; the harness silently falls back to it

- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/graders/recall-vs-defects.sh:135`; `head/evals/harness/ablation-grade.sh:1634`
- **Issue:** With `EVAL_HEAD_DIR` unset and no `<manifest dir>/../<fixture>/head`, `head_dir` becomes `$workspace/pr/head` (`:133-137`). `head_lines`, `scope_map` and `valid_cite` then read the graded party's own tree: padding a file defeats the `b > len(lines)` rule, deleting it removes the bound (`head_lines` returns None and `valid_cite` skips the check, `:354-356`), and rewriting a file into one ≤400-line function makes any citation in it credit every defect of that file via clause (ii). In the harness, `grade_recall` copies the sandbox `pr/` into `grading/pr/` and calls the grader with `grading` as workspace; `EVAL_HEAD_DIR` is set only when `resolve_pr_fixture` succeeds, and a `GradeError` is swallowed with `pass` (`ablation-grade.sh:1629-1635`), so a non-resolving fixture engages the sandbox fallback silently. The header of `ablation-grade.sh:46-49` states the sandbox `pr/` is "never" read; this path contradicts it. Confirmed by cross-model review (DISS-C-001, which also notes `scope_map`'s O(lines × headers) span fill on a crafted multi-megabyte file).
- **Fix:** Drop the `$workspace/pr/head` fallback; when neither `EVAL_HEAD_DIR` nor the fixture head exists, disable clause (ii) and the length rule and record `head_dir_source` in `details`. In `grade_recall`, raise (or record `recall.degraded`) instead of `pass`.
- **Reference:** CWE-807 Reliance on Untrusted Inputs in a Security Decision — https://cwe.mitre.org/data/definitions/807.html

### [MED-002] KF-046 class 7 exemption: a bare backticked repository token is exempt whenever the fixture holds the token anywhere

- **Severity:** MEDIUM (confidence: high)
- **File:** `head/evals/harness/ablation-grade.sh:1991` (`unit = span.group(0)[1:-1].strip()`)
- **Issue:** The exemption unit for an occurrence inside backticks is the backtick span; for `` `0xHoneyJar/loa` `` the unit is the bare token, which is a substring of every fixture line that holds the token, so `repo_name_exempt` returns a match whenever the fixture has one (`:1980-1999`). A probe that survives is any command whose only repository-name occurrence sits in backticks that are not shell-evaluated, e.g. a `python3 - <<'EOF'` heredoc building `"https://api.github.com/repos/" + "`0xHoneyJar/loa`".strip("`")`: the contamination scan records it as `contamination_exempt` and goes on. The guard exists to detect an agent reaching for the upstream repository; this weakens it for exactly the fixtures (pr-18) where the token is present. AG-51's second case passes only because it has no backticks.
- **Fix:** Never exempt a unit equal to the bare token; require the unit to be at least the whole stripped line (or the token plus surrounding context ≥ N characters) and to match a fixture line as a whole.
- **Reference:** CWE-693 Protection Mechanism Failure — https://cwe.mitre.org/data/definitions/693.html

### [MED-003] Clause (d) fails `oracle_closed` on any agent git activity, pausing the control arm

- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/harness/lib/sandbox-mount.sh:1038` (`rev-list --all`), `:1047` (`fsck --unreachable --no-reflogs`)
- **Issue:** `cmd_check` requires `sorted(set(rev-list --all)) == [base]` and an empty `fsck --unreachable` (`:1036-1048`). A `git commit`, `git stash`, or `git add` followed by `git reset` by the agent inside the sandbox (Loa run mode and `br sync` paths do commit) violates (d), so post-run `oracle_closed` FAILs, the trial rows `infrastructure_error` and the arm is paused (`head/evals/suites/ablation-2.0.yaml:77` adds `oracle_closed` to `a1_full`, the control arm; DEC-0418). Only the later-only pinned blob (`:1049-1051`), remote and alternates checks bear on the oracle; a sandbox commit of the agent's own work does not open it. The direction is fail-closed, so this is availability and validity of the eval, not an escape.
- **Positive note:** git runs in an agent-controlled repository with `-c core.fsmonitor=false`, `--no-pager`, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1` (`:639-645`); `.git` as a symlink or gitfile is refused (`:1033-1034`). The known repo-config execution vectors for `rev-list`, `remote`, `fsck` and `cat-file` are covered. With `HOME=/nonexistent`, a sandbox `.git` owned by another uid (container executor) will be refused as "dubious ownership" and read as `<unreadable>` → FAIL (d); verify ownership in the container path.
- **Fix:** Keep (d) to "no later-only pinned blob, no remote, no alternates"; report extra commits as evidence (`sandbox_commits=<n>`) rather than FAIL, or require only that the base commit is an ancestor of every ref.
- **Reference:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html

### [MED-004] A failed `yq` read is treated as a written `budget_scale`, changing the envelope shape and breaking the documented contract

- **Severity:** MEDIUM (confidence: high)
- **File:** `head/.claude/scripts/adversarial-review.sh:164` (fallback `echo "unreadable"`), `:168` (`CONF_BUDGET_SCALE_SET="true"`)
- **Issue:** `_adv_conf_budget_scale` reads the key's YAML tag with `|| echo "unreadable"`; the `case` at `:165-167` returns only on `!!null` or empty, so when `.loa.config.yaml` is absent, unparsable, or `yq` is missing, `_SET` becomes true, a WARN `budget_scale='(a unreadable, not a string)'` is logged, and the envelope gains `budget_scale`, `budget_cents_effective`, `budget_cents_max` and (on refusal) `reason` (`:4433-4451`, `:4749-4750`). The header promises "an absent key is the shipped gate, envelope unchanged" (`:20-21`); every other read in `load_adversarial_config` degrades silently to its default. The added metadata also fails the documented schema (see LOW-009). Confirmed by cross-model review in the review phase (DISS-C-001 there).
- **Fix:** `|| echo '!!null'`, or `[[ -r "$CONFIG_FILE" ]] || return 0` at the top of the function.
- **Reference:** CWE-755 Improper Handling of Exceptional Conditions — https://cwe.mitre.org/data/definitions/755.html

### [MED-005] The mount check reads agent-written sandbox files without a size cap; a crash is reported without its cause

- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/harness/lib/sandbox-mount.sh:887` (`return sha(open(full, "rb").read())` in `state()`); `head/evals/harness/took-effect.sh:389` (`2>/dev/null`)
- **Issue:** `state()` is symlink-refusing but reads the whole file into memory for every answer path, post-run, on the agent-writable sandbox. A multi-gigabyte (or sparse) file placed at an answer path under `.claude/` makes the Python core raise `MemoryError` or be OOM-killed; `rule_oracle_closed` discards stderr and reports only `the check failed (exit 1)`, the trial rows `infrastructure_error` and the arm is paused. The grader side is explicitly bounded (`ablation-grade.sh:453` `read_regular(path, cap, …)`, header `:48-49` "bounded, symlink-refusing"); the mount library is not. Clause (b)'s hash at `:1029` is gated by a size match and is fine. Fail direction is closed, so the damage is a denial of the evaluation and an unexplained FAIL, not an escape.
- **Fix:** In `state()`, `fstat` first and return `too-large` above a cap (the fixture file sizes bound what a correct state can be); capture the Python stderr in `rule_oracle_closed` into `EVID` (first line, truncated) as `lib_call` now does in `pipeline-run.sh:463-467`.
- **Reference:** CWE-400 Uncontrolled Resource Consumption — https://cwe.mitre.org/data/definitions/400.html

### [MED-006] Gate, schema and config changes ship without a CHANGELOG entry, AC walkthrough or documentation-coherence report

- **Severity:** MEDIUM (confidence: high)
- **File:** `head/.claude/scripts/adversarial-review.sh:20-29` (the new FR-4 contract in the header is the only user-facing documentation of `budget_scale` / `anchor_line`)
- **Issue:** The 35-file change edits a quality gate (`adversarial-review.sh`), its documented schema, two wire schemas, two skill resources and the example config, and bumps grader 1.3.0 / row writer 1.4 / report 1.3, with zero `CHANGELOG` lines in `head.diff`. `pr/PR.md` (the implementation report) is a one-line title: no `## AC Verification`, no record that the bats suites or shellcheck ran. No `grimoires/loa/a2a/subagent-reports/documentation-coherence-*` reports exist. Per the documentation-audit checklist an unverified missing report and a CHANGELOG omitting gate changes are blockers; they are tallied MEDIUM here because the HIGH count already drives the verdict.
- **Fix:** Add CHANGELOG entries per task (gate: `budget_scale`, `budget_cents_max`, `anchor_line`; harness: closed mount, eval config variant; grader 1.3.0; row 1.4; report 1.3), an AC walkthrough with `file:line` evidence, and the suite run output.
- **Reference:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html

---

## Low Priority Issues

### [LOW-001] One-line-function detection misfires on a trailing comment containing `}`
- **File:** `head/evals/graders/recall-vs-defects.sh:295` (`CLOSE_ONE` at `:287`)
- **Issue:** `f() {  # writes ${OUT}` satisfies `\{.*\}\s*(?:#.*)?$` and `"{" in header`, so the function is closed on its header and its body has no scope (reproduced: `one-liner misfire: True`). Headers with `${VAR}` in the comment are common in this repository's scripts.
- **Fix:** Strip `#…` before the one-line test, or require `}` to be followed only by `;`/whitespace.

### [LOW-002] Closing-brace indentation is compared raw while header indentation used `expandtabs(8)`
- **File:** `head/evals/graders/recall-vs-defects.sh:299` (vs `:283`)
- **Issue:** A tab-indented nested bash function never finds its `}` and its scope runs to the next header.
- **Fix:** Use `len(t.expandtabs(8)) - len(t.expandtabs(8).lstrip())` on both sides.

### [LOW-003] Bash header regex matches Python method calls inside heredocs in `.sh` files
- **File:** `head/evals/graders/recall-vs-defects.sh:210` (`BASH_HDR[0]`)
- **Issue:** `^\s*(?:function\s+)?NAME\s*\(\)\s*\{?` matches `    ds.sort()` (reproduced), so Python heredoc bodies in `ablation-grade.sh`-style scripts open spurious nested scopes that fragment the enclosing bash function.
- **Fix:** Require `{` on the header line or the next non-blank line, or skip heredoc bodies as the contamination scanner does (`strip_heredocs`).

### [LOW-004] A range past EOF credits nothing while its valid first line alone would
- **File:** `head/evals/graders/recall-vs-defects.sh:355`
- **Issue:** The EOF test runs before the `RANGE_CAP` first-line reduction (`:357-358`), so `file:40-9999` in a 60-line file is dropped while `file:40` credits; the more informative citation is penalised.
- **Fix:** Apply the cap first, then test EOF on the reduced range.

### [LOW-005] `exposed_unknown` is emitted only when nothing in the section hit; the header promises every other defect
- **File:** `head/evals/harness/ablation-grade.sh:2420` (vs the contract at `:2031-2032`)
- **Issue:** `if not rs and not hit_any:` leaves the non-hit defects of a section that hit one defect unrecorded.
- **Fix:** Mark the non-hit defects of a non-error section `exposed_unknown` when the section had body, or amend the header.

### [LOW-006] Five evidence readers disagree on first-wins vs last-wins
- **File:** `head/evals/harness/ablation-row.sh:419` (`evkv` → `last`); first-wins at `head/evals/harness/took-effect.sh:345`, `head/evals/harness/lib/sandbox-mount.sh:943-955` (`read_evidence`), `:1118` (`check_mount_closed`); last-wins at `head/evals/harness/pipeline-run.sh:560`
- **Issue:** `meta/arm-evidence.txt` is harness-owned, so this is not a tampering path, but a duplicated key (RW14-2 appends one deliberately) yields different values per consumer.
- **Fix:** One rule in all five readers (first wins, since the harness appends).

### [LOW-007] An unknown `config_variant` evidence value is written as `shipped`
- **File:** `head/evals/harness/ablation-row.sh:546`
- **Issue:** `if $v == "eval" then "eval" else "shipped"` misreports a run under an unexpected variant as the shipped one.
- **Fix:** Write `null` (or the raw value) and let `--validate` reject it.

### [LOW-008] The row writer reads the agent-writable sandbox config to classify a missing dissent as planned
- **File:** `head/evals/harness/ablation-row.sh:393-396`
- **Issue:** `dissent_absent_reason` becomes `disabled` when `sandbox/.loa.config.yaml` sets `flatline_protocol.enabled` or the gate's `.enabled` false (`:465-467`). An agent that silences its own gate from inside the sandbox is reported as a planned absence; the authoritative harness-written signal (`dissent=false` in evidence) is only one of three disjuncts. Compensating control: `rule_integrity_clean` / `loa_config_sha256` catches the config change post-run. Raised by cross-model review (DISS-C-002).
- **Fix:** Derive `disabled` from the arm toggles / evidence only; if the sandbox config must be read, compare its sha256 with the recorded value and classify a mismatch as `error`.

### [LOW-009] The documented schema rejects the envelope the gate now emits
- **File:** `head/.claude/schemas/adversarial-finding.schema.json:268` (`additionalProperties: false`; new keys at `:248-262`)
- **Issue:** `metadata` gains `budget_scale`, `budget_cents_effective`, `budget_cents_max` but not `reason`, which `adversarial-review.sh:4443` emits on `budget_exceeded` when the key is set. The block already lacks `rejected_summary`, `companion_voice`, `estimated_cents` and others, so this extends pre-existing drift.
- **Fix:** Add `reason` (and the other live keys) or relax `additionalProperties` on `metadata`.

### [LOW-010] The example config writes `budget_scale: fixed` explicitly, flipping the "written" branch for every copier
- **File:** `head/.loa.config.yaml.example:1643` (and `:1707`)
- **Issue:** The gate distinguishes written from absent (`adversarial-review.sh:168`); an operator who copies the example gets the extended envelope and `reason: budget` while the PR documents the absent key as "the shipped gate, byte for byte". This is also what breaks HIGH-003.
- **Fix:** Comment the keys out in the example (`# budget_scale: fixed`), or make written-`fixed` and absent indistinguishable in the envelope.

### [LOW-011] Under `diff`, `budget_cents` stops being a ceiling and `budget_cents_max` admits 15 digits
- **File:** `head/.claude/scripts/adversarial-review.sh:180`
- **Issue:** `_adv_budget_effective` makes the operative cap `budget_cents_max` alone (`:196-203`); the regex admits up to 999,999,999,999,999 cents. In the eval the sandbox config is agent-writable, so an agent could raise the cap for the gates that review its own work. Exposure is not new: `budget_cents` was equally writable before, run-level USD caps in `run-ablation.sh` bound the spend, and the mount-integrity hash flags the edit. Raised by cross-model review (DISS-C-003).
- **Fix:** Bound `budget_cents_max` (e.g. ≤ 10,000 cents) and fail closed to `fixed` above it; say in the example that `budget_cents` is a floor under `diff`.

### [LOW-012] The closed mount leaves `.loa.config.yaml` open, and the eval variant writes a key this PR introduces
- **File:** `head/evals/harness/lib/sandbox-mount.sh:605` (answer set "kept only under .claude/ … CLAUDE.md and .loa.config.yaml (outside .claude/)"); `:1140` (`apply_eval_config_variant` writes `budget_scale`)
- **Issue:** The sandbox `.loa.config.yaml` is the source tree's live config at `source_commit` (`mount_prompt_surface`, `:159`), and every mounted arm then gets `budget_scale: diff` / `budget_cents_max: 600` written into it. For any future fixture built from a PR that introduces a config key (this PR introduces `budget_scale`), the sandbox config carries the answer. This is the documented D-1.1 scope choice, recorded here as a residual oracle, not a defect in the implementation.
- **Fix:** Note the residual in the suite header, or extend clause (b) to also compare the sandbox config's keys against the fixture's `.loa.config.yaml.example` delta.

---

## Observations (not tallied)

- **DISS-C-004 (companion voice, LOW, speculative):** on the schema-enforced branch a `jq` failure in `_adv_keep_numeric_anchor` restores the raw finding (`head/.claude/scripts/adversarial-review.sh:1706-1708`), so a null `anchor_line` admitted by the wire schema (`head/.claude/schemas/wire/dissent-review.wire.json` anyOf integer|null) could pass through. The finding is already parsed JSON, so `jq` failing on it is near-impossible; not tallied.
- **Positive controls observed:** `safe_dst` refuses symlink and non-directory ancestors before any write (`sandbox-mount.sh:889-897`); `norm()` rejects absolute, `..`, empty, backslash and control-character path components (`:655-661`); `resolve_fixture` refuses a fixture inside the run dir (`took-effect.sh:361`); `OVERLAY_MODE` is validated against `head|base` (`pipeline-run.sh:226-227`); numeric anchors are dropped silently and never cause a rejection or repair hop (`adversarial-review.sh:613-621`); heredoc bodies are stripped before the oracle detector's command parsing.
- **Scope limit:** `ablation-report.py` (647 diff lines) was scanned for `subprocess`, `eval`, `exec`, `open(`, `pickle`, `yaml.load` and `shell=True` — none added; it was not line-audited. The `kf004` structured-output fixtures only add `anchor_line` values.

---

## Cross-Model Security Observations

Security dissenter run: `adversarial-review.sh --type audit --sprint-id sprint-1 --diff-file pr/head.diff --json` (no `--context-file`). Envelope: `grimoires/loa/a2a/sprint-1/adversarial-audit.json`. Primary gpt-5.5-pro: `status: clean` (zero findings). Companion claude-headless: `succeeded`, `counted_as: independent_voice`, four findings. `verdict_quality.voices_succeeded: 2`, `consensus`, not degraded; `metadata.locality` null (no DEGRADED_SECURITY_REVIEW). The run truncated the 117k-token diff to 13 of 35 files (24,000-token budget), so neither voice saw the row writer, report, suites, took-effect or test files; `budget_scale: diff` applied (`budget_cents_effective` 620 of max 1200).

| Finding | Voice | Triage |
|---------|-------|--------|
| DISS-C-001 MEDIUM — grader `head_dir` fallback to the sandbox `pr/head` | claude-headless | Confirmed by cross-model review; tallied as MED-001 |
| DISS-C-002 LOW — row writer reads sandbox config for `dissent_absent_reason` | claude-headless | Confirmed; tallied as LOW-008 with the compensating integrity control noted |
| DISS-C-003 LOW — `budget_cents_max` unbounded, `budget_cents` no longer caps under `diff` | claude-headless | Confirmed as LOW-011; exposure equivalent to the pre-existing `budget_cents` |
| DISS-C-004 LOW — enforced-branch filter failure restores the raw finding | claude-headless | Not tallied: near-impossible on parsed JSON; listed under Observations |

## Rejected dissent payloads

- None: `metadata.rejected_summary` is `[]`, `rejected_count` 0, `rejected_sidecars` `[]`, and no `adversarial-rejected-audit*.jsonl` exists beside the envelope.

---

## Review demotions confirmed

The review trailer carries `excluded: 0`; there are no demoted HIGH findings to confirm. `excluded_confirmed: 0`.

---

## Rubric Scores

| Dimension | Score (1-5) | Basis |
|-----------|-------------|-------|
| Security | 4 | Hardened file and git handling throughout; two trust-boundary leaks (MED-001, LOW-008) and one weakened detector (MED-002); nothing exploitable for execution or exfiltration |
| Architecture | 3 | One Python core for overlay/check/rule is sound; `cmd_check` (190 lines) and `oracle_scan` (~120) exceed the complexity bound without justification |
| Code Quality | 3 | Heuristic scope detection has four edge-case defects (HIGH-001, LOW-001..003); evidence readers inconsistent |
| DevOps | 2 | Suite red on this repository (HIGH-003); fixtures missing (HIGH-002); no CHANGELOG or AC walkthrough (MED-006) |
| Blockchain/Crypto | n/a | — |

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added (dissent secret scan: 1 redaction applied to the diff context, no secret in head files)
- [x] Input validation on new trust boundaries (path normalisation, symlink refusal, `python3 -I`, hardened git env, `OVERLAY_MODE` and toggle value validation)
- [x] Authentication required where needed (n/a — no endpoints)
- [x] No SQL/XSS injection vulnerabilities (n/a)
- [x] Error handling doesn't leak info (`last_error` allowlist untouched; `lib_call` truncates stderr to 300 chars)
- [ ] Tests cover security paths — BSC-9 reads the live config (HIGH-003); AG-50 cannot run (HIGH-002); no test for a wrapped Python signature (HIGH-001), a tab-indented or comment-braced bash header (LOW-001/002), or an oversized sandbox answer path (MED-005)

---

## Next Steps

1. Fix HIGH-001 (Python end-of-definition), HIGH-002 (add the fixtures/manifests or drop AG-50 and the title claim), HIGH-003 (delete or fixture-ize BSC-9's live-config assertions).
2. Address MED-001..MED-005; record any accepted MEDIUM in `grimoires/loa/NOTES.md`.
3. Add CHANGELOG entries and an AC walkthrough with test output to `grimoires/loa/a2a/sprint-1/reviewer.md` (MED-006).
4. Re-run `/review-sprint sprint-1`, then `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":6,"low":12},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-21T17:52:00Z"} -->
