# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Change under review:** `pr/head.diff` (35 files, +4469/−119); citations are `head/<path>:<line>` with line numbers from `pr/head/`.

---

## Overall Assessment

The change is large and mostly careful: the closed mount (`overlay_answer_paths` / `check_mount_closed` / `oracle_closed`) shares one Python core across the overlay, the pre-launch check and the post-run rule; the grader 1.3.0 same-scope rule keeps the 1.2.0 results beside it; the budget scaling and the numeric anchors are fail-closed and well tested (BSC-1..10, NRM-68..74). The eval-side test coverage is extensive.

Four defects block the merge. Two are grader-integrity holes in the very detectors the sprint ships: the oracle detector skips every `diff` tool result that Claude Code marks `is_error` (which is every `diff` that found a difference), and the KF-046 class 7 exemption lets an upstream probe through whenever its text appears verbatim in the PR fixture (a WebFetch of an issue URL quoted in a doc, an install one-liner). The third is the cross-model dissent's BLOCKING finding: `budget_cents_max: false` fails open to the 600c ceiling instead of `fixed`. The fourth is scope: the report's title claims curated multi-site labels and a versioned re-grade, and AG-50/AG-51/RAB-c131-1 depend on `fixtures/c131-oracle/`, `manifests/v1/`, the curated manifests and the replication suite root, none of which is in the diff.

Process: `reviewer.md` carries no `## AC Verification` section (it is the PR description verbatim), which is an automatic CHANGES_REQUIRED under Phase 4 on its own.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Oracle detector — a `diff` that found differences is never read

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:2390` — the detector drops every tool_result whose `is_error` is true before reading its content. Claude Code marks any non-zero exit as `is_error: true` while keeping the stdout in the content (this session's own transcript shows `Exit code 1` followed by the full output). `diff`, `sdiff` and `git diff --no-index` exit 1 whenever the files differ, so the canonical oracle probe `diff pr/head/.claude/scripts/x.sh .claude/scripts/x.sh` is skipped on every real transcript; AG-47 only passes because its fixtures hand-set `is_error` false.
**File:** `head/evals/harness/ablation-grade.sh:2390`
**Issue:** `if blk.get("is_error") is True: continue` conflates "the tool refused / a hook blocked" with "the command exited non-zero but printed".
**Why This Matters:** `oracle_exposed_defects` is the sprint's new integrity signal (D-1.3, KF-049) and feeds the report's oracle-exposed sensitivity and `--exclude-oracle-exposed`. With the diff form blind to the common case the signal under-reports systematically, and the "LOWER BOUND" caveat does not cover a bias this large.
**Required Fix:** Do not skip on `is_error`. Strip a leading `Exit code N` line and read the body as before; skip only when the body is empty after `ERR_LINE` filtering (which already handles refusals and hook blocks). Add an AG-47 case with `is_error: true` and a real normal-diff body that must expose d1. Re-check AG-50's pins against the real transcripts once the skip is gone (new hits may appear).

### 2. KF-046 class 7 exemption — a probe that quotes fixture text is exempt

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:1995` — the exemption unit (a backtick span, else the whole stripped line) is accepted when it is a *substring* of any PR-fixture line carrying the token. A WebFetch with `url: https://github.com/0xHoneyJar/loa/issues/553` is exempt when any head file or head.diff line contains that URL (Loa docs link upstream issues routinely, e.g. `.claude/rules/skill-invariants.md` carries `https://github.com/0xHoneyJar/loa/issues/553`), and a Bash `curl … raw.githubusercontent.com/0xHoneyJar/loa/…` is exempt when the README's install one-liner is in the fixture. `check_value` then finds no other pattern for WebFetch (`FIELDS` gives it only `url`) and returns clean.
**File:** `head/evals/harness/ablation-grade.sh:1995` (and `:1812` where the scan continues past the exemption)
**Issue:** The rule is meant for an agent *quoting* PR content (`if: github.repository == '0xHoneyJar/loa'`); the substring test also exempts an agent *executing* fixture content against the upstream.
**Why This Matters:** `contaminated` is the one hard integrity gate on a review-catch row; fetching the upstream issue or the merged fix for the PR under review is exactly the leakage it exists to catch.
**Required Fix:** Never exempt a token in a fetch/exec position: no exemption for `WebFetch`/`WebSearch` fields, nor for a Bash segment whose executable is `gh`, `curl`, `wget`, `git` or `pip`/`npm` (reuse `split_segments`/`seg_words`). For the remaining fields require the unit to equal a fixture line (after strip), not merely to be a substring. Extend AG-51 with a WebFetch of a URL present in pr-18's head and a `curl` of one; both must stay `repo_name` hits.

### 3. Budget scaling — `budget_cents_max: false` fails open (cross-model dissent DISS-001, BLOCKING)

- **HIGH** (confidence: high) `head/.claude/scripts/adversarial-review.sh:179` — `yq eval ".flatline_protocol.<gate>.budget_cents_max // 600"` applies the alternative operator *before* validation, and `//` treats `false` as absent. `budget_cents_max: false` (and any YAML false) therefore reads as 600 and passes the whole-number regex, so under `budget_scale: diff` the gate scales up to 600c instead of saying the value is malformed and keeping `fixed` as the header comment at `:158` promises.
**File:** `head/.claude/scripts/adversarial-review.sh:179`
**Issue:** Fail-closed contract broken for one YAML type; BSC-6 covers `6OO`, `-1`, `600.5`, `060` but not `false`/`no`.
**Why This Matters:** This is the spend cap of a model dispatch; a misconfiguration that silently lifts it to USD 6.00 per run is the class of error the sixteenth-run a1 C-004 hardening (`_conf_uint` fails CLOSED to 0 cents) was written against.
**Required Fix:** Read the tag first as `_adv_conf_budget_scale` already does for the scale: `'!!null'|''` → 600; `'!!int'` → validate the raw value; anything else → WARN and `fixed`. Add `false` and `no` to BSC-6.

### 4. Tests and the report depend on corpus artifacts that are not in the change

- **HIGH** (confidence: medium) `head/evals/tests/ablation-grade.bats:1544` — `real_run` reads `fixtures/c131-oracle/<name>/{transcripts,dotclaude,task}`; AG-50 (`:1558`) pins its expectations to "the curated anchors" of pr-17 (DEC-0626) and to `manifests/v1/`; AG-51 (`:1580`) and RAB-c131-1/2 (`head/evals/tests/run-ablation.bats:1127`) run against `grimoires/loa/evals/ablation-2.0-replication`. None of these appears in `pr/head.diff`, nor does any `evals/fixtures/review-prs/manifests/*.json`, `manifests/v1/*.json` or `SHA256SUMS` change, although the report's title promises "curated multi-site labels, versioned re-grade". Either the artifacts are in a separate commit (then the report is not this change's) or the suite fails on `real_run`'s missing directory and the `rgrade` suite root.
**File:** `head/evals/tests/ablation-grade.bats:1544`, `:1558`, `:1580`; `head/evals/tests/run-ablation.bats:1127`
**Issue:** The change is not self-contained and the implementation report claims deliverables the diff does not carry.
**Why This Matters:** Reviewers and the audit cannot verify AG-50's detector pins (the only validation of the oracle detector on real runs) or the curated-label claim; `recall_pm3_v1` is meaningless without a `v1/` snapshot (`v1_manifest` would be false everywhere).
**Required Fix:** Include the `c131-oracle` fixtures (with their `trim.py` provenance), the `manifests/v1/` snapshots, the curated manifests and the refreshed `SHA256SUMS` in the change, or drop the claims from the report and guard AG-50/AG-51 with a `skip` when the fixtures are absent (as the pr-17 answer-set test already does). State in the report which it is.

---

## Observations

### 1. Closed mount, post-run clause (d) conflates agent git activity with leakage

- **MEDIUM** (confidence: medium) `head/evals/harness/lib/sandbox-mount.sh:1041` and `:1047` — after the run, `rev-list --all != [base]` and any `fsck --unreachable` output fail `oracle_closed`. An agent that runs `git add`, `git stash` or commits its `review.md` creates reachable or unreachable objects that are not later-only blobs; took-effect then rows the trial `infrastructure_error` and pauses the arm (DEC-0418). The leakage test is the pinned-blob probe two lines below; the commit-count and fsck clauses are mount-integrity checks that belong to the pre-launch form only.
**Suggestion:** In the post-run check, keep (d)'s remote/alternates/pinned-blob clauses and demote "extra commits" and "unreachable objects" to evidence (`sandbox_git_activity=…`) unless an extra object is a later-only pinned blob.
**Benefit:** No arm pause on harmless agent behaviour; the rule stays about the oracle.

### 2. Row writer reads the agent-writable sandbox config for `dissent_absent_reason` (dissent DISS-C-003)

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-row.sh:394` — `flp.json` comes from `sandbox/.loa.config.yaml`, and `disabled` has the highest precedence in `reason()` (`:435`). The grader header in this same change says sandbox copies are tamperable and never authoritative. A gate that dispatched or errored is relabelled a planned absence by a sandbox-side edit, and planned absences are never excluded by the report.
**Suggestion:** Derive `disabled` from harness-written evidence only (`dissent=false`, the `flatline` toggle's line, or a harness snapshot of the launched config); if the sandbox file is kept as a fallback, rank it below an envelope that proves the gate ran.

### 3. Grader 1.3.0 falls back to the grading copy of the agent's `pr/head`

- **MEDIUM** (confidence: medium) `head/evals/graders/recall-vs-defects.sh:135` — with `EVAL_HEAD_DIR` unset and no `<manifest dir>/../<fixture>/head`, the head directory becomes `<workspace>/pr/head`. Under ablation-grade that is `grading/pr/head`, a copy of the sandbox's `pr/` (the agent-writable tree), and ablation-grade pops `EVAL_HEAD_DIR` when `resolve_pr_fixture` fails (`head/evals/harness/ablation-grade.sh:1631`). The validity rule and the scope map would then read files the agent could have edited.
**Suggestion:** Drop the `$workspace/pr/head` fallback (or allow it only when `EVAL_ALLOW_WORKSPACE_HEAD=1`), and make ablation-grade fail the grade when the fixture head does not resolve for a review-catch task.

### 4. End-of-definition detection misreads common bash headers (dissent DISS-C-002)

- **MEDIUM** (confidence: high) `head/evals/graders/recall-vs-defects.sh:295` — `CLOSE_ONE = \{.*\}\s*(?:#.*)?$` marks a header as a one-liner whenever the line holds any `}` after the `{`: `main() { local x="${1:-}"` and `f() {  # see ${FOO}` scope the whole function to its header line, so clause (ii) can never credit a citation inside it. At `:299` the closer scan measures indentation without `expandtabs(8)` while `headers()` (`:284`) uses it, so a tab-indented function never finds its `}` and runs to the next header.
**Suggestion:** Count braces outside quotes after stripping a trailing comment; a one-liner is balanced and ends in `}`. Use the same indentation measure in both places. Add RG cases for `${…}` headers and tab indentation.

### 5. Complexity — SIMPLICITY[shrink]

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:2312` — `oracle_scan` is 121 lines with five nesting levels; `head/evals/harness/lib/sandbox-mount.sh:958` — `cmd_check` is 101 lines; the `_sm_oracle_py` heredoc is ~450 lines of Python inside a bash function. The repo's rule blocks approval over 50 lines without justification; here the justification (one core shared by three callers) is sound for the heredoc but not for the two functions.
**Suggestion:** Split `oracle_scan` into `_oracle_prepare(by_file)` (the later/live/near_text tables) and `_oracle_events(...)`; split `cmd_check` into the four clauses. `net: -0 lines possible` (a restructure, not a deletion). Everything else in the change is lean already.

### 6. Report partitions strand build rows when review rows hold two rules

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-report.py:1138` — `part_split` keys build rows (`part_rule` None) as `rule n/a`, so in a version whose review rows carry both `pm3` and `pm3_or_same_function` the build rows land in a third partition. No partition then holds both a build and a review contrast, so H1 (pass rate and catch rate together) is "no pair" on one side in every partition, including the primary. The header documents the key shape but not this consequence.
**Suggestion:** Attach build rows to every rule partition of their pin (they carry no catch figure to pool), or key only review rows by rule.

### 7. yq failure is read as "key written" (dissent DISS-C-001)

- **LOW** (confidence: high) `head/.claude/scripts/adversarial-review.sh:164` — `|| echo "unreadable"` on the tag probe makes a missing yq or an unreadable config set `CONF_BUDGET_SCALE_SET=true`, log a spurious WARN and add the three budget keys to the envelope, against the "absent key is the shipped envelope, byte for byte" contract. Every sibling reader degrades silently.
**Suggestion:** `_bt=$(yq … 2>/dev/null) || return 0`.

### 8. Documentation schema rejects the envelope this change documents (dissent DISS-C-004)

- **LOW** (confidence: high) `head/.claude/schemas/adversarial-finding.schema.json:268` — `metadata` has `additionalProperties: false`, its `status` enum lacks `budget_exceeded`, and `reason`, `estimated_cents`, `estimate_voices` are absent, while the change adds `budget_scale`/`budget_cents_effective`/`budget_cents_max` and documents `reason: budget`. The gap predates the change but the change widens it.
**Suggestion:** Add the three keys and the status value, or drop `additionalProperties: false` on metadata.

### 9. `precision_planted_per_flag` exceeds 1

- **LOW** (confidence: high) `head/evals/harness/ablation-report.py:984` — planted defects caught ÷ findings flagged is not a precision: one citation can credit several defects (multi-site anchors, the scope clause), and AR-52 asserts `1.5`. A reader of the Markdown line (`:1794`) will misread it.
**Suggestion:** Rename to `planted_caught_per_flag` (or cap at the number of flags) and say so in the header.

### 10. Clause (b) byte-equality on tiny pinned files

- **LOW** (confidence: medium) `head/evals/harness/lib/sandbox-mount.sh:1010` — a later-only pinned version of an answer path that is tiny boilerplate (`{}`, a one-line `.gitkeep`, an identical licence stub) is byte-equal to unrelated sandbox files and fails (b) as a leak → `infrastructure_error`. Empty blobs are skipped; a minimum size (say 32 bytes) would remove the false positives without weakening the probe.

### 11. Two head.diff path parsers

- **LOW** (confidence: high) `head/evals/harness/ablation-grade.sh:2088` — `answer_paths` re-implements `diff_paths` from the mount library (`head/evals/harness/lib/sandbox-mount.sh:719`) without hunk skipping or `Binary files` lines, so the grader's answer set can differ from the mount's (a removed `-- a/x` body line becomes an answer path in the grader). Harmless today (over-inclusion), but the two sets are compared implicitly through `live[f]`.
**Suggestion:** Have the grader call `_sm_oracle_py answer-set` (one subprocess) or move the parser to a shared module.

### 12. Evidence readers disagree on first vs last occurrence

- **LOW** (confidence: high) `head/evals/harness/lib/sandbox-mount.sh:954` keeps the first `key=` line and `:953` the first `overlay_sha256` per path; `head/evals/harness/took-effect.sh:345` reads the first; `head/evals/harness/ablation-row.sh:419` reads the last; `head/evals/harness/pipeline-run.sh:560` reads the last `copy_source`. A re-run or a second overlay line would be read four ways.
**Suggestion:** One helper, one rule (first wins, later lines are evidence of a repeat), used by all four.

---

## Cross-Model Observations

Adversarial review ran on `pr/head.diff` (primary `gpt-5.5-pro`, companion `claude-headless` succeeded, `status: reviewed`, `budget_scale: diff`, 5 findings, 0 rejected). Triage:

| Dissent | Severity | Where it landed |
|---|---|---|
| DISS-001 `budget_cents_max: false` → 600 | BLOCKING | Changes Required §3 (verified: `//` swallows false) |
| DISS-C-001 yq failure sets the key | ADVISORY | Observations §7 |
| DISS-C-002 `CLOSE_ONE` and tab indentation | ADVISORY | Observations §4 |
| DISS-C-003 sandbox config read by the row writer | ADVISORY | Observations §2 |
| DISS-C-004 schema rejects the documented envelope | ADVISORY | Observations §8 |

## Rejected dissent payloads

None — `metadata.rejected_summary` is `[]` and `adversarial-rejected-review.jsonl` holds 0 rows.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | Fixes to Changes Required §1–§4; the corpus artifacts (or the claims) per §4 |

---

## Acceptance Criteria Check

### Task 1.1: review the pull request, report each defect with file and line, give a merge verdict

| Criterion | Status | Notes |
|-----------|--------|-------|
| Each defect reported with file and line | Pass | Every entry above cites `head/<path>:<line>` |
| Merge verdict | Pass | CHANGES_REQUIRED (4 high) |
| `reviewer.md` carries `## AC Verification` | Fail | The report is the PR description; no AC walkthrough |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [ ] Input validation and sanitization present — the class 7 exemption (§2) and the `//` default (§3) accept inputs they document refusing
- [x] Authentication/authorization correct — n/a (no auth surface); symlink handling in the overlay and `read_regular` is sound
- [x] No SQL/XSS injection vulnerabilities — n/a
- [x] Dependencies secure — stdlib Python, jq, yq, git only
- [x] Error messages don't leak sensitive data — `lib_call` now surfaces the last stderr line (300 chars) into `pipeline.json.reason`; paths only

---

## Code Quality Summary

**Strengths:**
- One Python core for overlay, pre-launch check and post-run rule; the launched surface is the checked one (manifest before check).
- Symlink-refusing, size-bounded reads everywhere new files are opened; C-quoted and CRLF diff headers handled and tested.
- The 1.2.0 grading rule is preserved beside the new one, so prior grades remain reproducible (`recall_pm3_v1`).
- Budget scaling is opt-in per gate, envelope shape unchanged when the key is absent (BSC-1, BSC-8).

**Areas for Improvement:**
- Heuristic detectors (oracle, contamination) need adversarial cases drawn from real transcripts, not only hand-set fixtures (§1, §2).
- Several readers of `arm-evidence.txt` and two parsers of `head.diff` (Observations §11, §12).

---

## Next Steps

1. Fix Changes Required §1–§4 (and add the regression cases named there).
2. Run `bats evals/tests/ablation-grade.bats evals/tests/sandbox-mount.bats evals/tests/took-effect.bats evals/tests/pipeline-run.bats evals/tests/run-ablation.bats evals/tests/ablation-row.bats evals/tests/ablation-report.bats evals/tests/eval-recall-grader.bats tests/unit/adversarial-review-budget-scale.bats tests/unit/adversarial-review-normalise.bats` and quote the result in the report.
3. Update `grimoires/loa/a2a/sprint-1/reviewer.md` with a `## AC Verification` walkthrough (`file:line` + symbol per AC) and the artifact decision from §4.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":4,"medium":6,"low":6},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T16:40:00Z"} -->
