# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)

Scope: the pull request in `pr/` (sprint-263: closed review-catch mount, grader 1.3.0, oracle detector, dissent line anchors + budget_scale, report 1.3, row writer 1.4). 35 files, 5,873 diff lines. All citations are `head/<path>:<line>` with line numbers from `pr/head/`.

---

## Overall Assessment

The dissent-side work (`adversarial-review.sh` numeric anchors and `budget_scale`, the two schemas, the config example, the skill docs) is sound: the jq filter and the budget formula were exercised directly against edge inputs and behave as documented, and the companion-voice run of this very review used `budget_scale: diff` end to end. The closed-mount library is carefully written (symlink-safe writes, header parsing, clauses (a)–(d)); its own suite passes 12/12 here, and the three `oracle_closed` took-effect tests pass with the real library.

The eval harness around it is not ready to merge. Seven high findings, each with a reproduced or code-confirmed failure path:

- the pre-launch closed-mount check runs after the arm toggles, so the live `a7_effort_medium` arm is refused on every review-catch fixture that touches a `SKILL.md` or `model-config.yaml` (reproduced);
- one ungraded review-catch row, or any two grader rules in a suite version, fractures the report's partitions so the build rows become the primary and the catch-rate evidence is sidelined (reproduced);
- the oracle detector produces false "exposed" / "exposed_unknown" labels on ordinary commands (`2>&1 | wc -l`, `cd pr/head && diff …`, `… && echo SAME || echo DIFFERENT`), and those labels drive cell exclusion;
- the KF-046 exemption excuses real upstream-repository probes (`WebFetch` of the GitHub URL, `git clone`) whenever any fixture line contains the URL;
- the new `dissent_absent_reason` classifier records `api_failure` / `malformed_response` gates as `none` (both dissent voices flagged this independently);
- grader 1.3.0's end-of-definition rule ends a Python function at a multi-line signature, so its body has no scope.

The PR description carries no `## AC Verification` walkthrough and no CHANGELOG entry; the frozen tree lacks the fixtures and helper files most of the PR's own bats suites need, so those suites were run where possible (see Test Evidence) rather than taken from the report.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Closed mount — ordering against the arm toggles

- **HIGH** (confidence: high) `head/evals/harness/pipeline-run.sh:565-578` — `check_mount_closed` runs after `apply_arm_toggles`; a toggle that rewrites an answer path makes clause (c) fail and the trial is `infrastructure_error` before any phase.
**File:** `head/evals/harness/pipeline-run.sh:565-578`, `head/evals/harness/lib/sandbox-mount.sh:357-389` (effort toggle), `:315-348` (karpathy_block, rule_files, audit_delta_instruction)
**Issue:** The order is overlay → `apply_arm_toggles` → eval config → grimoire → beads → manifest → `check_mount_closed`. The `effort` toggle strips `effort:` from every `.claude/skills/*/SKILL.md` and rewrites `.claude/defaults/model-config.yaml`; `karpathy_block` edits `CLAUDE.loa.md`; `rule_files` deletes `.claude/rules/*.md`. Any of those that is an answer-bearing path of the fixture (a Loa PR touching a SKILL.md is the common case) no longer matches its `overlay_sha256`, so the check fails. Reproduced with the real library: overlay → `apply_arm_toggles '{"effort":"medium"}'` → `check_mount_closed` prints `FAIL (c) .claude/skills/s2/SKILL.md: mount_mutated=…` (exit 2). `a7_effort_medium` has `task_types: [all]` (`head/evals/suites/ablation-2.0.yaml:88`), so every review-catch trial of that arm on such a fixture is refused; the only test of toggles-after-overlay (`head/evals/tests/sandbox-mount.bats:302-309`) uses `dissent: false`, which edits a file outside the answer set.
**Why This Matters:** FR-1 is meant to close the oracle while every arm keeps running; as wired, the mount is closed by refusing the arm. The A7 component silently loses tasks and the batch's per-arm counts diverge.
**Required Fix:** Decide the contract explicitly: either (a) record the toggle's rewrite as the expected post-toggle state (re-hash answer paths after the toggles, or exempt toggle-owned paths from clause (c) and record them as `toggle_edited=`), or (b) refuse toggles that edit answer paths at `resolve_arm_toggles` time with a clear reason. Add a sandbox-mount.bats case: overlay → `effort: medium` on a fixture whose answer set holds a SKILL.md → check passes (or is refused with the intended message).

### 2. Report partitions — build rows separated from review rows

- **HIGH** (confidence: high) `head/evals/harness/ablation-report.py:1129-1156` — `part_rule` reads a review-catch row without `grader_rule` as `"pm3"`, so one ungraded review row (or a genuine two-rule version) makes `rules` two-valued and `part_split` sends every build row to a `"<v> · rule n/a"` partition that becomes the primary.
**File:** `head/evals/harness/ablation-report.py:1129-1156`, `:1193-1196` (largest partition wins), `head/evals/harness/ablation-row.sh:540-541` (`grader_rule` null when ungraded)
**Issue:** The row writer emits `grader_rule: null` for every review-catch row with no `recall` (agent_error, transport_error, cap_failure without grade). `part_rule` turns that null into `"pm3"`. With the rest of the batch graded under `pm3_or_same_function`, `part_split` sees two rules and keys every row by rule; build rows (rule None) land in `"3 · rule n/a"`. Reproduced on the c131 fixture plus the `main` fixture's build rows with the same pin: partitions `3 · rule n/a` (312 rows, primary, H1 catch n=0), `3 · rule pm3` (1 row), `3 · rule pm3_or_same_function` (47 rows, the only catch evidence, "reported separately"). Also reproduced for a legitimate two-rule pin: three partitions each "H1: established" on partial evidence. `--suite-version` cannot select across them.
**Why This Matters:** The report is the decision instrument; the headline H1/A4/component decisions silently lose `defect_catch_rate` whenever a single review trial errored out, which is the normal state of a live batch. AR-50 (`head/evals/tests/ablation-report.bats:800-816`) only covers a fixture with no build rows, so the test cannot see this.
**Required Fix:** Rows without a rule must not create a rule value: treat `grader_rule` null as "no rule" (excluded from the rule set, placed in every rule partition of its version, or kept with the version's single rule), and keep build rows in every rule partition of their pin. Add an AR test with build rows + one ungraded review row and assert one partition.

### 3. Oracle detector — false "exposed" labels on ordinary commands

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:2159-2161` — `split_segments` splits on every `&`, so `2>&1`, `&>` and `>&` sever the redirect from the diff segment and the silent-sink / `/dev/null` tests at `:2481-2483` never see the pipe; the non-empty, range-less result then marks every defect of the file `exposed_unknown` (`:2409-2420`).
**File:** `head/evals/harness/ablation-grade.sh:2159-2161`, `:2409-2420`, `:2481-2483`, `ERR_LINE :2060-2061`
**Issue:** `diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh 2>&1 | wc -l` is segmented as `diff … 2>` / `1` / `wc -l`; the diff segment's separator is `;`, so `SILENT_SINK` is not consulted and the result `4` marks d1, d2 `exposed_unknown`. `… &>/dev/null; echo $?` likewise. Independently, the `exposed_unknown` rule fires on any body that is neither a hunk nor an `ERR_LINE`: results `DIFFERENT` (from `&& echo SAME || echo DIFFERENT`), `exit code: 1`, an md5sum, `bash: diff: command not found`, `Command timed out after …`, `Command blocked by hook: …` (ERR_LINE's `BLOCKED` is case-sensitive). The header (`:2034-2035`) promises the opposite.
**Why This Matters:** `oracle_exposed_unknown` is a row field (`head/evals/harness/ablation-row.sh:536`) that excludes the cell pairwise in the oracle sensitivity, and in the main reads under `--exclude-oracle-exposed true`. The detector is documented as a lower bound; false positives are not covered by that caveat and shrink the valid-cell count toward the new `insufficient` threshold.
**Required Fix:** Treat `>&`, `&>`, `2>&1`, `|&` as redirection tokens in `split_segments` (do not split inside them); restrict `exposed_unknown` to results that look like diff bodies (a `DIFF_BODY` line present) and widen `ERR_LINE` (case-insensitive, `bash:`, `Command timed out`, `exit code:`). Add the four cases above to AG-48.

### 4. Oracle detector — operand side misread when cwd is inside pr/head

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:2484-2494` — `segment_tokens` PATHISH-matches the executable word itself; with cwd `/workspace/pr/head`, `classify("diff")` is `("pr","head","diff")`, so index 0 is a pr operand and `heads[0] < ws_ops[0]` is always true: the side is `left` whatever the real operand order.
**File:** `head/evals/harness/ablation-grade.sh:2484-2494`, `:2211-2237` (classify), `:2240-2248` (segment_tokens)
**Issue:** `cd pr/head && diff -u ../../.claude/scripts/g.sh .claude/scripts/g.sh` with result `@@ -19,3 +100,3 @@`: the head side is the right operand (line 100, far from every site) but the left range 19-21 is read as head coordinates and d1 is marked exposed. The same command issued from `/workspace` exposes nothing.
**Why This Matters:** A false `oracle_exposed_defects` entry on a run that only diffed its own PR copy against the sandbox excludes a valid cell and mis-attributes an oracle read to the agent.
**Required Fix:** Exclude the command word (and options) from `toks` before computing `pr_ops` / `ws_ops`; derive the side from operand positions only. Add the `cd pr/head && diff ../../X X` case with a right-side hunk to AG-47.

### 5. KF-046 class 7 — the exemption excuses upstream-repository probes

- **HIGH** (confidence: high) `head/evals/harness/ablation-grade.sh:1808-1812`, `:1980-1999` — a repo-name occurrence is exempt when its unit (backtick span, else the whole stripped line) is a substring of any fixture line; a bare URL or token is therefore exempt whenever any `head/**` or `head.diff` line contains that URL, for every tool and field.
**File:** `head/evals/harness/ablation-grade.sh:1808-1812`, `:1946-1978`, `:1980-1999`
**Issue:** With a fixture README line `git clone https://github.com/0xHoneyJar/loa.git && cd loa` or a doc line holding `https://github.com/0xHoneyJar/loa/blob/main/README.md`, the following all pass as "PR content": `WebFetch url="https://github.com/0xHoneyJar/loa"`, `WebSearch query="0xHoneyJar/loa"`, `Grep pattern="0xHoneyJar/loa"`, Bash `git clone https://github.com/0xHoneyJar/loa.git`. `check_value` applies the exemption before the tool is considered, and the substring rule accepts any line that merely contains the token. These are probes of the upstream repository by definition (`:1931-1933` describes the intended exemption as quoting PR content).
**Why This Matters:** `contaminated` is the eval's integrity gate for a review-catch run; an agent that fetches the fixed upstream file is the exact scenario the scan exists to catch, and it now reports clean with an `contamination_exempt` record.
**Required Fix:** Apply the exemption only to tools/fields that carry text the agent is quoting (Write content, Edit strings, Bash `echo`/heredoc bodies), never to `WebFetch`, `WebSearch`, `Grep pattern`, or Bash segments whose executable is `git`, `curl`, `gh`, `wget`; require the unit to be a full fixture line (or a backtick span), not a substring. Extend AG-51 with the WebFetch and `git clone` negatives.

### 6. Row writer — `dissent_absent_reason` misses `api_failure` / `malformed_response`

- **HIGH** (confidence: high) `head/evals/harness/ablation-row.sh:475-479` — the classifier recognises `budget_exceeded`, a status naming `preflight`, `failed` and `recorded_by: record-fallback`; the gate's own failure statuses `api_failure` and `malformed_response` (`head/.claude/scripts/adversarial-review.sh:1426`, `:1441`, `:1471`, `:1578`, `:1595`; enum at `head/.claude/schemas/adversarial-finding.schema.json:229-230`) fall to `else "none"`.
**File:** `head/evals/harness/ablation-row.sh:475-479`
**Issue:** A REVIEW or AUDIT gate whose dissenter call failed at the API, or returned an unparseable payload, is rowed as `dissent_absent_reason.<gate>: "none"` ("the dissent ran") and omitted from `dissent_absent_gates`; `--validate` accepts it. Both dissent voices (gpt-5.5-pro DISS-003, claude-headless DISS-C-001) found this independently.
**Why This Matters:** The field exists to feed the report's "dissent-absent gates excluded" sensitivity (`head/evals/harness/ablation-report.py:593-598`); the most common unplanned absence class is invisible to it, so the sensitivity excludes nothing for exactly the runs it was built to flag.
**Required Fix:** Map `api_failure` and `malformed_response` (and any status not in `clean|reviewed`) to `"error"`; add RW14-3 cases for both statuses.

### 7. Grader 1.3.0 — a multi-line Python signature ends the definition

- **HIGH** (confidence: high) `head/evals/graders/recall-vs-defects.sh:303-311` — for `def f(\n    arg,\n):` the `):` line is indented no deeper than the `def`, so `close_line` returns the last signature line and the function body has no scope; clause (ii) never credits a citation inside it.
**File:** `head/evals/graders/recall-vs-defects.sh:303-311` (python branch), header rule `:68-70`
**Issue:** The spec ("the last line before the first later non-blank, non-comment line indented no deeper than the def") is applied to the signature's closing paren. For a site at body line 12 and a valid citation at body line 6 of the same function, `recall` reports a miss while the function is plainly one scope. Multi-line signatures are standard Python formatting (black, ruff).
**Why This Matters:** `recall` is the decision statistic from this sprint on (row writer 1.4 `defect_catch_rate`); a deterministic under-credit tied to code formatting changes the headline metric by fixture layout, not reviewer behaviour, and `credits_function_only` cannot reveal a lost credit.
**Required Fix:** Start the end-of-definition scan after the signature closes (track paren depth from the `def` line until the line ending in `:`), then apply the indentation rule. Add an RG test with a multi-line signature.

---

## Observations

### 1. Dissent gate (`adversarial-review.sh`, schemas)

- **MEDIUM** (confidence: high) `head/.claude/scripts/adversarial-review.sh:181` — `budget_cents_max // 600` in yq replaces a boolean `false` with 600 before validation, so `budget_cents_max: false` keeps `budget_scale: diff` active with the default ceiling instead of "said and fixed applies". Confirmed with yq 4.40 (`.a // 600` on `a: false` → 600). Read the tag first, as `budget_scale` does.
- **MEDIUM** (confidence: high) `head/.claude/schemas/adversarial-finding.schema.json:224-268` — metadata keeps `additionalProperties: false` and a `status` enum of `api_failure|malformed_response|clean|reviewed`, yet the PR adds `reason: "budget"` to the `budget_exceeded` envelope (`head/.claude/scripts/adversarial-review.sh:4445`) beside the pre-existing undeclared `budget_exceeded`, `estimated_cents`, `estimate_voices`. The schema edit in this PR was the moment to declare them (dissent DISS-C-003).
- **LOW** (confidence: high) `head/.claude/scripts/adversarial-review.sh:4750` — `_budget_meta` is merged once, late in `main()`; the `api_failure` / `malformed_response` envelopes written between the budget gate and that line never carry `budget_scale`/`budget_cents_effective`, although the header (`:20-26`) says the envelope carries them whenever the key is written (dissent DISS-C-004).
- **LOW** (confidence: medium) `head/.claude/scripts/adversarial-review.sh:164-166` — a yq failure yields `_bt="unreadable"`, which sets `CONF_BUDGET_SCALE_SET=true`; the envelope then names a scaling the config never wrote.

### 2. Grader 1.3.0 (`recall-vs-defects.sh`)

- **MEDIUM** (confidence: high) `head/evals/graders/recall-vs-defects.sh:283` vs `:299` — `headers()` measures indentation with `expandtabs(8)`, `close_line()` compares the raw `len(t) - len(t.lstrip())`; a tab-indented nested function's `\t}` never matches, its span runs to the outer's end and overwrites the outer's remaining lines (over- and under-credit; executed by the scout on a tab-indented fixture).
- **MEDIUM** (confidence: high) `head/evals/graders/recall-vs-defects.sh:287`, `:295` — `CLOSE_ONE` plus `"{" in line` reads `main() { local d=${1:-}` as a one-line function; the body becomes top-level and has no scope.
- **MEDIUM** (confidence: high) `head/evals/graders/recall-vs-defects.sh:297-301` — the first `}` at the header's indentation ends a bash function; this repository's scripts routinely embed heredocs (`python3 - <<'PY'`, jq programs, JSON) with a `}` at column 0 inside top-level functions, so everything after it is "top-level" and loses clause (ii). Documented behaviour, wrong for this corpus (dissent DISS-C-002).
- **MEDIUM** (confidence: high) `head/evals/graders/recall-vs-defects.sh:352-357` — validity is applied before `RANGE_CAP`: `file:40-120` in a 100-line head file credits nothing under `recall` while `recall_pm3` credits it, and the same text credits when head/ did not resolve (dissent DISS-C-006).
- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:1599-1612` — `false_positives` keeps the ±3 rule while `recall` credits same-scope citations, so a citation credited by scope is simultaneously counted as a false positive; `precision` (true defects / (caught + fp)) double-counts it.
- **LOW** (confidence: high) `head/evals/graders/recall-vs-defects.sh:214`, `:272` — `#` lines inside fenced code blocks are markdown headings (no fence tracking).
- **LOW** (confidence: high) `head/evals/graders/recall-vs-defects.sh:303-311` — a trailing indented `# comment` is outside the Python def (doc says "non-comment line" ends it); `:261-262` the shebang fallback is unreachable because `CITE` (`:156`) requires an extension before `:`.
- **LOW** (confidence: medium) `head/evals/graders/recall-vs-defects.sh:137-141` — `EVAL_HEAD_DIR` falls back to `<workspace>/pr/head`; in the ablation grader the workspace is the grading copy of the agent-writable sandbox `pr/`, reached when `resolve_pr_fixture` fails (`head/evals/harness/ablation-grade.sh:1628-1635` swallows `GradeError`).

### 3. Oracle detector and grade (`ablation-grade.sh`)

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:1569-1571` — a numeric anchor is dropped when the symbol anchor is a bare path with no `:` (`{"anchor": ".claude/scripts/g.sh", "anchor_line": 20}` cites nothing), and when the path part has no extension and `file` is absent.
- **LOW** (confidence: high) `head/evals/harness/ablation-grade.sh:2388` — `blk.get("tool_use_id") in uses` raises `TypeError` for a list/dict id and aborts the grade; the rest of the scan is `isinstance`-defensive.
- **LOW** (confidence: high) `head/evals/harness/ablation-grade.sh:2153-2158`, `:2448` — `(cd pr/head && diff …)` (parens kept as one segment) and a `cd` in a previous Bash tool call (cwd reset per tool_use) are not seen; documented lower bound, but a cheap oracle read.

### 4. Closed mount (`sandbox-mount.sh`, `took-effect.sh`, suite)

- **MEDIUM** (confidence: high) `head/evals/suites/ablation-2.0.yaml:77` — `oracle_closed` is listed for `a1_full` only; `a3_one_voice` and `a7_effort_medium` run the closed mount on review-catch tasks but are never post-run verified.
- **MEDIUM** (confidence: high) `head/evals/harness/lib/sandbox-mount.sh:996-1010` — clause (b) flags any regular file byte-equal to a later-only pinned blob of a *different* answer path (`FAIL (b) .claude/dup1/same.md: byte-equal to the pinned .claude/dup2/same.md` reproduced by the scout); legitimate duplicate content refuses the trial.
- **MEDIUM** (confidence: medium) `head/evals/harness/lib/sandbox-mount.sh:1016-1017`, `:1051` — (b) prunes only top-level `pr` and `.git`, and (d) queries only the sandbox's own object store; a nested clone of the pinned tree (`sandbox/tmp-clone/.git`, zlib-compressed objects) passes both. Relevant with network or host-executor filesystem access.
- **MEDIUM** (confidence: high) `head/evals/harness/lib/sandbox-mount.sh:860-870`, `:923-925` — a fixture whose `head/` is missing (or lacks a touched file) makes `expected()` None and the overlay silently deletes the PR's paths from the mount, exit 0, `overlay_removed=N`; no consistency check against a `diff --git` header that is not a deletion.
- **LOW** (confidence: high) `head/evals/harness/lib/sandbox-mount.sh:899-903`, `:714-716`, `:756` — `remove()` rmtree's a directory named by an answer path; `header_names` splits an unquoted rename at the first `" b/"` and the `Binary files (.+) and (.+)` regex is greedy, producing bogus answer paths that are then removed.
- **LOW** (confidence: high) `head/evals/harness/lib/sandbox-mount.sh:1079-1086` — `_sm_copy_source` reports a clean HEAD while `git status -- .claude` ignores gitignored files that `mount_prompt_surface` copies (`:166`).
- **LOW** (confidence: high) `head/evals/harness/took-effect.sh:384-389` — the first repo holding `source_commit` is used; a shallow checkout lacking `fix_commit` shrinks the answer set and the run fails `(a) mount_overlay names N paths, the fixture's answer set has M` with the `fix_commit_unavailable` note discarded by `2>/dev/null`.
- **LOW** (confidence: high) `head/evals/harness/lib/sandbox-mount.sh:408-410`, `:418-424` — `bare_model=fable` evidence is written for arms with no BARE phase (contract says exit 2 when a toggle cannot take effect); the `oracle_open` refusal only reads `ARM_EVIDENCE_FILE` and in pipeline order runs after `mount_overlay=none` is written, so it never fires.

### 5. Report 1.3 and row writer 1.4

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-report.py:1840`, `:1852`, `:1284` — on a split partition `h1a4` receives the partition key, so `h1.suite_version`, `a4.suite_version`, `budget_matched.suite_version` and the `by_suite_version` keys become strings like `"2 · pin 2222… · rule pm3"` while `REPORT_SCHEMA` stays 1 and `provenance.suite_versions` stays `["2"]`.
- **MEDIUM** (confidence: high) `head/evals/harness/ablation-row.sh:392-394`, `:465-467` — the `disabled` reason (which outranks every other) is decided from `sandbox/.loa.config.yaml`, agent-writable; an agent that flips `flatline_protocol.enabled` converts a missing-envelope row into a planned absence (dissent DISS-C-005). `ablation-grade.sh`'s header (`:46-50`) refuses sandbox copies for this reason.

---

## Cross-Model Observations

Envelope `grimoires/loa/a2a/sprint-1/adversarial-review.json`: status `reviewed`, primary gpt-5.5-pro, companion claude-headless (`counted_as: independent_voice`), `budget_scale: diff`, effective 620c. Nine findings: DISS-001 (→ Observations §1, budget_cents_max false), DISS-002 (→ Changes Required #7), DISS-003 and DISS-C-001 (→ Changes Required #6), DISS-C-002 (→ Observations §2 heredoc `}` and tabs), DISS-C-003 / DISS-C-004 (→ Observations §1), DISS-C-005 (→ Observations §5), DISS-C-006 (→ Observations §2 valid_cite). Each was verified in the head code before being counted; severities above are the reviewer's.

## Rejected dissent payloads

None. `metadata.rejected_summary` is empty and the named sidecar `adversarial-rejected-review.jsonl` is 0 bytes; no companion sidecar was produced.

---

## Test Evidence

| Suite | Result here | Note |
|-------|-------------|------|
| `evals/tests/sandbox-mount.bats` | 12/12 pass (1 skip: corpus commits absent) | run from `pr/head` |
| `evals/tests/took-effect.bats` cycle-131 rules | `oracle_closed` 3/3 pass with the real library | other rules need `fixtures/ablation-runs/` (absent from the frozen tree) |
| `evals/tests/ablation-report.bats` AR-48…52, `ablation-row.bats` RW14-1…4, `run-ablation.bats` RAB-c131-* | pass | run from an executable copy (frozen tree has no exec bits; `/tmp` is `noexec`) |
| `evals/tests/eval-recall-grader.bats` | 37/39 pass; RG-16/17 need `evals/fixtures/review-prs` | — |
| `evals/tests/pipeline-run.bats`, `ablation-grade.bats` | not runnable here (`fingerprint.sh`, suite fixtures absent) | — |
| `tests/unit/adversarial-review-{normalise,budget-scale}.bats` | not runnable here (`adversarial-review-s3-helpers.bash` not in the PR) | the jq filter, `_adv_conf_budget_scale` and `_adv_budget_effective` were exercised directly and match the documented contract |

Reproductions performed for this review: Changes Required #1 (real library, `/tmp/a7/run.sh`), #2 (`ablation-report.py` on the c131 rows plus build rows), the numeric-anchor jq filter (15 edge inputs), the budget-scale reader (10 scale spellings, 8 maxima).

---

## Documentation Verification

- No `## AC Verification` section in the implementation report (`pr/PR.md` is one line); per the skill this alone is CHANGES_REQUIRED on a sprint with a plan. No CHANGELOG entry is in the diff.
- `.loa.config.yaml.example`, both `ADVERSARIAL-REVIEW.md` copies (identical new section) and the header comments of every harness script are updated. The `pipeline-run.sh` `--help` range (`:181`, `2,144p`) is hard-coded and will drift; `took-effect.sh`/`ablation-row.sh` now compute it.

## Security Checklist

- [x] No hardcoded secrets or credentials
- [x] Input validation at trust boundaries present (sandbox write path is symlink-safe; path normalisation rejects `..`)
- [ ] Contamination gate — the KF-046 exemption bypass (Changes Required #5) weakens it
- [ ] Trust boundary — row writer reads the agent-writable sandbox config for `disabled` (Observations §5)
- [x] Error messages don't leak sensitive data

## Code Quality Summary

**Strengths:** one Python core shared by overlay, pre-launch check and took-effect; hunk-aware diff header parsing; fail-closed budget parsing; thorough header contracts; the dissent envelope now carries `anchor_line` so graders can cite lines.

**Areas for Improvement:** the oracle detector's shell model (segment splitting, operand classification) needs a tokenizer that understands redirections and command words; the report's partitioning needs a rule for rows without a rule; the closed mount and the toggle set need an explicit joint contract.

**Complexity:** `oracle_scan` (`head/evals/harness/ablation-grade.sh:2317-2433`, ~115 lines) and `cmd_check` (`head/evals/harness/lib/sandbox-mount.sh:957-1065`, ~110 lines) exceed 50 lines; both are justified by the number of clauses they implement but would benefit from splitting the per-result handling out of the transcript loop. `net: ~0 lines possible` — lean already on the dissent side.

## Next Steps

1. Address the seven Changes Required items above, each with the named test case.
2. Re-run `evals/tests/*.bats` and `tests/unit/adversarial-review-*.bats` in a tree with the fixtures present.
3. Add an `## AC Verification` walkthrough to the implementation report.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":7,"medium":14,"low":11},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T03:30:00Z"} -->
