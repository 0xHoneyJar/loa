# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)

---

## Overall Assessment

The PR (sprint-263: closed review-catch mount, grader 1.3.0, dissent line anchors + `budget_scale`, row writer 1.4, report 1.3) is large, carefully documented and well covered by bats tests; the closed-mount library, the row writer and the report partitions read correctly and the test fixtures exercise real edge cases (quoted diff paths, symlinks, removed `--- a/` hunk lines, git object-store checks).

The blocking problem is in the sprint's core deliverable, the grader's new same-scope rule (`pm3_or_same_function`). Its end-of-definition detection misfires on two ordinary shapes that both occur in the real `.claude/` corpus the review-catch tasks grade against: a Python `def` whose multi-line signature closes with a dedented `):` (51 files in the live `.claude/` tree, `cheval.py` among them) and a bash function whose header comment contains `{…}` (four headers in `adversarial-review.sh`). In both cases the whole body silently loses its scope and clause (ii) never credits, so `defect_catch_rate` is not reproducible from the documented rule. Both were reproduced against `head/evals/graders/recall-vs-defects.sh` with synthetic fixtures (controls with a one-line signature / plain header credit as documented). The cross-model dissent raised the Python case as BLOCKING; the bash case came from its companion voice and from my own read.

Everything else is non-blocking: a post-run closed-mount clause that pauses an arm on benign agent git activity, a partitioning rule that strands build rows during a partial re-grade, a `yq //` default that swallows `false` before the fail-closed validation, a test that asserts a property of the operator's untracked config, and assorted low items.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Grader 1.3.0 — end-of-definition detection drops the scope of ordinary functions

- **HIGH** (confidence: high) `head/evals/graders/recall-vs-defects.sh:308` — a Python `def` whose signature spans several lines and closes with `):` at the def's indentation ends its recorded scope on the line before `):`; the body is top-level, so clause (ii) never credits a citation inside it.
**File:** `head/evals/graders/recall-vs-defects.sh:302-311`
**Issue:** `close_line` for python returns `last` at the first non-blank, non-comment line indented `<= lv`. For
```python
def f(
    a,
    b,
):
    x1 = 1      # site, line 5
    ...
    x8 = 8      # citation, line 12
```
the `):` line (indent 0) terminates the span at line 3, before the body. Reproduced: manifest site `m.py:5`, review cites `m.py:12` → `missed: ["PY-multiline"]`, while the same body under a one-line `def g(a, b):` is `detected` via `credits_function_only`.
**Why This Matters:** The corpus answer paths live under `.claude/`; the live tree has 51 Python files with this exact `^\s*\):\s*$` shape (`.claude/adapters/cheval.py` ×8). For every defect planted in such a function the new decision statistic silently degrades to the old ±3 rule, so `defect_catch_rate` under `pm3_or_same_function` is not what the header documents ("the enclosing definition of the site … identified by its header line") and differs between functions for a formatting reason. `recall_pm3` is unaffected.
**Required Fix:** Track signature continuation: after the header, skip lines until paren depth returns to zero (or until a line ends with `:` at any indentation) before applying the dedent test; or use `ast`/`tokenize` on the head file to get `def` spans (`end_lineno` is available on 3.8+). Add a bats case with a multi-line signature.
**Reference:** SDD §5.2 D-2.1 (same-scope rule, header-line identification).

- **HIGH** (confidence: high) `head/evals/graders/recall-vs-defects.sh:295` — `CLOSE_ONE` (`\{.*\}\s*(?:#.*)?$`) is searched over the whole header line, so a bash function whose header comment contains a brace pair (`foo() {  # expands ${X}`) is classified as a one-line function and its entire body has no scope.
**File:** `head/evals/graders/recall-vs-defects.sh:287,295-296`
**Issue:** `if CLOSE_ONE.search(lines[h - 1]) and "{" in lines[h - 1]: return h` — any `{…}` anywhere on the header line (including inside a trailing `#` comment) ends the definition on its header. Reproduced: `foo() {  # expands ${X}` with site at line 2 and citation at line 9 → `missed: ["SH-brace-comment"]`.
**Why This Matters:** `head/.claude/scripts/adversarial-review.sh` alone has four function headers of this shape, and it is the file the review-catch corpus PRs touch most. Same consequence as above: the scope clause is silently withheld for those functions.
**Required Fix:** Strip a trailing `#…` comment (outside quotes) from the header before the one-liner test, then require the `{` that follows `()` and a `}` after it on the same line (e.g. `re.search(r'\(\)\s*\{.*\}\s*$', stripped)`). Add a bats case.
**Reference:** SDD §5.2 D-2.1.

---

## Observations

### 1. Closed mount / took-effect

- **MEDIUM** (confidence: medium) `head/evals/harness/lib/sandbox-mount.sh:1040` — post-run clause (d) requires `git rev-list --all` of the sandbox to be exactly the base commit; an agent that runs `git stash` or `git commit` during a review-catch run (benign, and not a mount leak) makes `oracle_closed` FAIL in `head/evals/harness/took-effect.sh:389`, which rows the trial `infrastructure_error` and pauses the arm (DEC-0418).
**File:** `head/evals/harness/lib/sandbox-mount.sh:1038-1041`, `head/evals/harness/took-effect.sh:368-391`
**Suggestion:** Verified with git: a `stash` adds two commits to `rev-list --all`, a commit adds one; a plain `git add` leaves `fsck --unreachable` clean. Post-run, (d) should keep the parts that evidence a later-version leak (no remote, no alternates, no later-only pinned blob in the object store) and report extra commits as evidence rather than a FAIL, or restrict the exact-commit test to the pre-launch `check_mount_closed`.
**Benefit:** A1 review-catch arms are not paused by agent-side git hygiene.

- **MEDIUM** (confidence: medium) `head/evals/graders/recall-vs-defects.sh:135` — when `EVAL_HEAD_DIR` is unset and the corpus fixture has no `head/`, the grader falls back to `<workspace>/pr/head`, the agent-writable tree (the grading dir's `pr/` is a copy of sandbox `pr/`); clause (ii) and the citation-validity rule then read definition spans and line counts from agent-controlled files, contradicting `head/evals/harness/ablation-grade.sh:46-49` ("never the agent-writable sandbox pr/").
**Suggestion:** Drop the `$workspace/pr/head` fallback (keep it only behind an explicit self-check flag) and have `grade_recall` fail or warn when the fixture has no `head/` instead of letting the grader fall through. (Dissent DISS-C-004, verified.)
**Benefit:** Recall cannot be inflated by rewriting `pr/head/<file>` into one 400-line function.

### 2. Report 1.3

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-report.py:1153` — when a suite version holds review rows under two grader rules (a partial re-grade), build rows get their own `rule n/a` partition; no partition then holds both pass-rate and catch-rate pairs, so H1 is undecidable in every partition and the "largest partition is primary" rule may pick the build-only one.
**Suggestion:** Build rows have no grader rule, so including them in each rule partition pools nothing; attach them to every rule key (or at least to the primary) and keep the `n/a` key only for the pin split.
**Benefit:** A partially re-graded version still yields an H1 read per rule.

### 3. Adversarial review (`budget_scale`)

- **MEDIUM** (confidence: high) `head/.claude/scripts/adversarial-review.sh:179` — `yq eval '… budget_cents_max // 600'` replaces a `false` (or any YAML-falsy) maximum with 600 before the whole-number validation, so `budget_scale: diff` stays on with ceiling 600 instead of the documented "malformed maximum is said and fixed applies" (`:150-152`, example config). Verified: `budget_cents_max: false` → `600`, tag `!!bool`.
**Suggestion:** Read the raw value with `| tag` as `_adv_conf_budget_scale` already does for the scale, default only on `!!null`/absent, and validate everything else. Triaged from the dissent's BLOCKING (DISS-001) to MEDIUM: the outcome equals an absent key and spend stays bounded by 600c; it is a contract deviation, not an unbounded-spend path.
**Benefit:** The fail-closed guarantee holds for every spelling.

### 4. Tests

- **MEDIUM** (confidence: high) `head/tests/unit/adversarial-review-budget-scale.bats:196` — BSC-9 asserts that the operator's live `.loa.config.yaml` (untracked, hence the `-f` guard) sets neither `budget_scale`; the assertion fails in any checkout whose local config does — this workspace's sets `diff` / `budget_cents_max: 1200` for both gates (the dissent envelope for this very review carries `budget_scale: diff, budget_cents_max: 1200`).
**Suggestion:** Delete lines 195-198 (the example-config assertions above them are the versioned contract), or point the check at a fixture.
**Benefit:** The unit suite does not depend on operator state.

- **MEDIUM** (confidence: low) `head/evals/tests/ablation-grade.bats:1544` — AG-50/AG-51 and RAB-c131-1/2 read fixtures that are not in this diff: `evals/tests/fixtures/c131-oracle/*` (trimmed transcripts + `dotclaude/*.fx`), the `grimoires/loa/evals/ablation-2.0-replication` root, the curated `manifests/pr-17.json` multi-site anchors and `manifests/v1/`. The PR title's "curated multi-site labels" has no file in the 35-file diff; if those artefacts are not already in the tree these tests fail and the detector validation pins (AG-50) are unverified.
**Suggestion:** Confirm the fixtures and curated manifests are committed (same PR or an already-merged one) and state it in the PR description.

### 5. Complexity (SIMPLICITY)

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:2312` — `oracle_scan` is ~122 lines with five nesting levels (phase → event → block → target → section → defect); `oracle_plan` (`:2435`) is ~67. Justified in part by the heuristic nature of the detector, but the per-result handling (`:2440-2497` region of the loop body) is a self-contained unit.
**Suggestion:** `SIMPLICITY[shrink]`: extract the tool_result handling into `oracle_result(label, i0, plan, res, …)` and the "loose text corroboration" into its own helper; net: -0 lines, but nesting drops to 3. Not blocking on its own.

### 6. Low

- **LOW** (confidence: high) `head/evals/graders/recall-vs-defects.sh:299` — the closing-brace test measures indentation on the raw line while `headers()` used `expandtabs(8)`, so a tab-indented nested function never finds its `}` and runs to the next header; reproduced (`SH-tab-inner` over-credited from the outer function's tail). The live `.claude/` tree has no tab-indented `.sh`, hence LOW. Fix with the same `expandtabs(8)` on both sides.
- **LOW** (confidence: high) `head/evals/graders/recall-vs-defects.sh:214` — `MD_HDR` treats `#` lines inside fenced code blocks as headings; a markdown file with a shell snippet gets spurious scopes. Skip lines between ``` fences.
- **LOW** (confidence: high) `head/evals/harness/ablation-report.py:984` — `precision_planted_per_flag` = caught ÷ flags can exceed 1 (AR-52 expects `1.5` for `a1_full`); a "precision" above 1 misleads a reader. Name it `planted_caught_per_flag` or cap/annotate.
- **LOW** (confidence: high) `head/evals/tests/sandbox-mount.bats:76` — `ln -s ../../../../outside-secret` from `$FX/head/.claude/skills/s1/` resolves to `$FX/outside-secret`, not `$T/outside-secret` (written at `:75`), so the symlink dangles and the "never followed / SECRET never copied" assertions at `:160-162` test less than intended. Use five `..` or an absolute target.
- **LOW** (confidence: medium) `head/evals/harness/ablation-grade.sh:2159` — `split_segments` splits on a bare `&`, so `2>&1` cuts `diff a b 2>&1 | wc -l` into `diff a b 2>` / `1` / `wc -l`; the diff segment loses its pipe separator and is read as a content-printing diff (over-detection). Treat `>&`, `<&`, `&>` as part of the word.
- **LOW** (confidence: medium) `head/evals/harness/ablation-grade.sh:1995` — the KF-046 class-7 unit is matched as a substring of a fixture line, so a bare backticked token (`` `0xHoneyJar/loa` ``) is exempt whenever the fixture mentions the repository anywhere. By design (D-3.2) but loose; consider requiring the unit to be at least the token plus one neighbouring word.
- **LOW** (confidence: high) `head/.claude/schemas/adversarial-finding.schema.json:248` — metadata gains the three budget keys but the `budget_exceeded` envelope the same change writes (`reason: "budget"`, `estimated_cents`, `budget_cents`, `estimate_voices`, status `budget_exceeded`) is still rejected by the contract (`additionalProperties: false`, status enum lacks it). Pre-existing gap, widened by `reason`. (Dissent DISS-C-005.)
- **LOW** (confidence: high) `head/.claude/scripts/adversarial-review.sh:197` — under `diff`, a `budget_cents` or `--budget` above `budget_cents_max` is silently lowered to the maximum. Documented in the example config and pinned by BSC-7, so not a defect; a one-line WARN when `conf > max` would make the lowering visible. (Dissent DISS-C-002.)
- **LOW** (confidence: high) `head/evals/harness/lib/sandbox-mount.sh:953` — `read_evidence` keeps the FIRST `mount_overlay=`/`copy_source=` line (and `check_mount_closed` `:1122`, `took-effect.sh:345` likewise) while `pipeline-run.sh:560` and `ablation-row.sh` `evkv` take the LAST. One overlay per run today, so harmless; pick one convention.
- **LOW** (confidence: high) `head/evals/harness/lib/sandbox-mount.sh:958` — `cmd_check` is ~102 lines; linear and clause-labelled, so readable, but each clause could be its own function. `SIMPLICITY[shrink]`.

Over-engineering pass: net: -0 lines possible; the detector and the mount check are inherently rule-heavy. Ship after the two HIGH fixes.

---

## Cross-Model Observations

Two voices ran on `pr/head.diff` (primary `gpt-5.5-pro`, companion `claude-headless`, `counted_as: independent_voice`, both succeeded; envelope `grimoires/loa/a2a/sprint-1/adversarial-review.json`, `status: reviewed`, 8 findings, `budget_scale: diff`, `budget_cents_effective: 620`).

| Dissent | Voice | Triage |
|---|---|---|
| DISS-001 BLOCKING `_adv_conf_budget_scale` `// 600` swallows `false` | gpt-5.5-pro | Verified (yq → 600, tag `!!bool`); counted as MEDIUM above (bounded outcome equals an absent key) |
| DISS-002 BLOCKING python multi-line signature ends the scope | gpt-5.5-pro | Verified and reproduced; HIGH #1 |
| DISS-C-001 ADVISORY yq failure → `unreadable` stamps metadata | claude-headless | Refuted: `load_adversarial_config` returns before `_adv_conf_budget_scale` when the config file is absent (`:234-237`) or yq is missing (`:239`); the path needs yq present and a file yq cannot parse, where every other read degrades too |
| DISS-C-002 ADVISORY ceiling lowers an explicit budget | claude-headless | Documented behaviour; LOW (suggest WARN) |
| DISS-C-003 ADVISORY `CLOSE_ONE` braces / tab indentation | claude-headless | Both reproduced; HIGH #2 and LOW |
| DISS-C-004 ADVISORY `<workspace>/pr/head` fallback | claude-headless | Verified; MEDIUM |
| DISS-C-005 ADVISORY schema lacks `reason` / `budget_exceeded` | claude-headless | Verified, pre-existing gap; LOW |
| DISS-C-006 ADVISORY `--help` sentinel missing | claude-headless | Refuted: `ablation-row.sh` line 2 and line 139 are `# ====` rules; `--help` prints 138 lines ending at the closing rule |

## Rejected dissent payloads

None. `metadata.rejected_summary` is empty and the listed sidecar `adversarial-rejected-review.jsonl` has zero rows; the companion's `rejected_sidecar` is null.

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion (PR title claims) | Status | Notes |
|-----------|--------|-------|
| Closed review-catch mount (overlay, pre-launch check, took-effect `oracle_closed`) | Pass | Library, pipeline wiring and bats cover head/base modes, symlinks, fix-commit paths; post-run clause (d) over-fails on agent git activity (MEDIUM) |
| Grader 1.3.0: three results + same-scope rule | **Fail** | Scope detection drops Python multi-line signatures and brace-commented bash headers (HIGH ×2); `_pm3`/`_pm3_v1` results correct |
| Oracle detector (diff + read forms) | Pass | Heuristic lower bound as documented; `2>&1` splitting (LOW) |
| Dissent line anchors (`anchor_line`/`anchor_line_end`) | Pass | Normaliser, enforced branch, prompts, wire + doc schemas consistent; NRM-68..74 verify |
| `budget_scale` / `budget_cents_max` | Pass with note | Formula and envelope correct; `false` maximum bypasses fail-closed (MEDIUM); BSC-9 brittle (MEDIUM) |
| Row writer 1.4 / report 1.3 (versioned re-grade, partitions, sensitivities) | Pass with note | Build rows stranded in `rule n/a` on a partial re-grade (MEDIUM) |
| Curated multi-site labels | Unverifiable | No manifest or `v1/` file in the diff |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [x] Input validation and sanitization present (path normalisation, symlink refusal, `O_NOFOLLOW`, bounded reads)
- [x] Trust boundary: grader reads the immutable fixture — except the `<workspace>/pr/head` fallback (MEDIUM above)
- [x] No injection: `yq`/`jq` take values via `--arg`/`strenv`; git runs with `--literal-pathspecs`, no config, no prompt
- [x] Error messages don't leak sensitive data (budget warnings sanitise the config value)

---

## Code Quality Summary

**Strengths:**
- The closed-mount Python core is shared between overlay, pre-launch check and took-effect, so the launched surface and the verdict use one comparison.
- Fail-closed defaults nearly everywhere; evidence lines are explicit and tested end to end (real-library pipeline test, took-effect on a real overlay).
- Three-result grading keeps a 1.2.x-reproducible figure beside the new rule.

**Areas for Improvement:**
- Regex-based definition detection needs the two signature/header shapes fixed and a test per shape.
- Post-run oracle clause (d) conflates "later version leaked" with "agent touched git".
- FAST-GATE: no evidence in the report that `shellcheck`/the bats suites ran; not counted here (no implementation report in this evaluation), but the unverifiable fixtures make a CI run the only way to know AG-50/AG-51/RAB-c131 pass.

---

## Next Steps

1. Fix the Python signature and bash header-comment cases in `close_line` (and the tab indentation while there); add bats cases for each shape.
2. Decide the post-run clause (d) policy and the `rule n/a` partition behaviour.
3. Default `budget_cents_max` only on a null tag; drop the live-config assertion from BSC-9.
4. Confirm the c131 fixtures and curated manifests are in the tree; update the report and request `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":7,"low":10},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T23:15:00Z"} -->
