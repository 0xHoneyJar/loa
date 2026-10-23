# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)

---

## Overall Assessment

The change under review is the sprint-263 pull request: the closed review-catch mount (`overlay_answer_paths` / `check_mount_closed` / took-effect `oracle_closed`), grader 1.3.0 with three recall results and the same-scope rule, the oracle detector and KF-046 class 7 exemption in `ablation-grade.sh`, numeric dissent anchors plus `budget_scale` in `adversarial-review.sh`, row writer 1.4, report 1.3, `--allow-partial`, and the cycle-131 toggles. 35 files, +4469/−119.

The engineering is careful in most places: the mount library's overlay and check share one Python core, symlinks are refused on every sandbox write and read, the budget scaling fails closed to `fixed`, the wire schemas keep strict mode, and the bats coverage is broad (sandbox-mount.bats is new, RG-29..39, AG-45..51, AR-48..52, BSC-1..10, NRM-68..74).

Three defects block the merge, two in the grader's new decision rule and one in the row writer. The rule "pm3_or_same_function" identifies bash definitions with a regex whose closing brace is optional and whose end is unanchored, so any line of the form `name()` inside a Python heredoc is read as a bash function header. Running the PR's own `recall-vs-defects.sh` against the PR's own head tree, a defect planted at `recall-vs-defects.sh:300` is credited by a citation at `:480` (180 lines away) and one at `ablation-grade.sh:2320` by a citation at `:2540` (220 lines away), both under `credits_function_only`. The review corpus is Loa PRs, whose scripts are bash wrappers around Python heredocs, so the decision statistic (`defect_catch_rate`, report 1.3) over-credits on exactly the file shape it will be scored on. In the other direction, the Python end-of-definition rule ends a `def` at its own parameter list when the signature spans several lines, so the body gets no scope at all (reproduced). Both were corroborated by the cross-model dissent, which also found that the new `dissent_absent_reason` row field reads a dissent that ended in `api_failure` or `malformed_response` as "none" (ran fine). `recall_pm3` / `recall_pm3_v1` are unaffected by the grader findings.

Process: `reviewer.md` is the two-line PR description. It carries no `## AC Verification` walkthrough, no self-check or test-run evidence, and no stated assumptions (Think Before Coding). That alone is an automatic CHANGES_REQUIRED under this skill; it is recorded here but the verdict rests on the finding above.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Grader correctness — the same-scope rule credits across spurious bash "definitions"

- **HIGH** (confidence: high) `head/evals/graders/recall-vs-defects.sh:210` — `BASH_HDR[0]` is `^(\s*)(?:function\s+)?NAME\s*\(\)\s*\{?` with the brace optional and no end anchor, so a Python call line such as `    flush()`, `    out.pop()`, `    ds.sort()` or `    EXEMPT_BUF.clear()` inside a bash heredoc is a definition header; `headers()` (`head/evals/graders/recall-vs-defects.sh:279`) feeds those into `scope_map()` (`:318`), which then hands `hit_new()` (`:372`) spans of hundreds of lines that credit any citation inside them.
**File:** `head/evals/graders/recall-vs-defects.sh:210` (regex), `:279` (match), `:318-346` (span computation), `:372-399` (credit)
**Issue:** Reproduced with the PR's grader on the PR's head tree (manifest: X1 at `evals/graders/recall-vs-defects.sh:300`, X2 at `evals/harness/ablation-grade.sh:2320`; review citing `:480` and `:2540`):
```
{"pass":true,"score":100,"detected":["X1","X2"],"detected_pm3":[],
 "credits_function_only":["X1","X2"],"rule":"pm3_or_same_function"}
```
The spurious spans the grader builds on those two files: `out.pop()` at recall-vs-defects.sh:241 → scope 241..492 (252 lines); `flush()` at ablation-grade.sh:2308 → 2308..2554 (247 lines); `ds.sort()` at :1964 → 1964..2302 (339 lines); `docker_ready()` at :2562 → 2562..2638; `host_gate()` at :2757 → 2757..2816. Neither file has a real bash function at those lines (ablation-grade.sh has zero `name() {` headers; its whole body is a Python heredoc). The fallback ±20 for "long" definitions does not help: these spans are under 400 lines, so a citation anywhere in them credits a site anywhere else in them.
**Why This Matters:** `recall` under this rule is the eval's decision statistic (`ablation-report.py` report 1.3: `defect_catch_rate` decides H1 and the component decisions; `_pm3` / `_pm3_v1` are "beside" and decide nothing). The corpus fixtures are Loa PRs, where the gate scripts and harness are bash files holding Python heredocs — the file shape that triggers the bug. A reviewer who cites a line in the right heredoc but 200 lines from the planted site is scored as catching it; the metric that the whole cycle-131 pre-registration turns on is inflated in a direction that favours any arm that cites more lines. The tests RG-29..39 cover hand-made bash with real `name() {` headers only; none has a `name()` call line or a heredoc.
**Required Fix:** Require the opening brace for a bash header: match `\(\)\s*\{\s*(#.*)?$` on the header line, or `\(\)\s*$` followed by a line that is `\{` at the same indentation (the two-line form); drop the `.`/`:` from the name class unless preceded by `function`. Add an RG test whose `.sh` file is a bash wrapper around a `python3 - <<'PY'` heredoc containing `    flush()` / `    x.pop()` lines, asserting that a citation 30+ lines from the site in that heredoc credits nothing. Re-run the AG-50 detector pins and the replication grades after the fix, since `recall` on existing runs will move.
**Reference:** Karpathy GOAL-DRIVEN — the rule's own header comment (`:61-62`) states the regex it implements; the check that would fail when the regex over-matches is missing.

### 2. Grader correctness — a multi-line Python signature ends the definition at its parameter list

- **HIGH** (confidence: high) `head/evals/graders/recall-vs-defects.sh:308` — the python branch of `close_line` returns `last` at the first later non-blank, non-comment line indented no deeper than the `def`; for a signature written `def process(\n    argument,\n):` the `):` line sits at the def's indentation, so the span ends on the parameter line and the whole body has no scope.
**File:** `head/evals/graders/recall-vs-defects.sh:302-311`
**Issue:** Reproduced with the PR's grader: P1 planted at `m.py:6` inside such a function, citation at `:13` (7 lines away, same body) → `detected: []`, `credits_function_only: []`; the same file with a one-line signature → `detected: ["P1"]`. Multi-line signatures are the default output of black/ruff-format and are common in `.claude/` Python (cheval, adapters). Raised by the dissent (DISS-001, gpt-5.5-pro) and verified here.
**Why This Matters:** For those functions the new clause silently never applies, so `recall` degrades to the ±3 rule while the row still says `rule: pm3_or_same_function`; the decision statistic under-credits in a file-shape-dependent way, the mirror image of finding 1.
**Required Fix:** In `close_line`'s python branch, skip lines until the signature closes (track `(`/`)` depth from the header, or require the first body line to be the one after a line ending in `:`); better, compute Python spans with `ast` (`end_lineno`) when the file parses and fall back to the indentation rule otherwise. Add an RG test with a multi-line `def`.
**Reference:** Karpathy GOAL-DRIVEN — RG-37/RG-39 cover one-line `def` headers only.

### 3. Row writer — `dissent_absent_reason` reads a failed dissent as "none"

- **HIGH** (confidence: high) `head/evals/harness/ablation-row.sh:478` — the classifier returns `error` only for `status == "failed"` or a record-fallback; every other non-success status falls through to `none` ("the dissent ran").
**File:** `head/evals/harness/ablation-row.sh:468-479`
**Issue:** `adversarial-review.sh` writes envelopes with `status` `api_failure` (`head/.claude/scripts/adversarial-review.sh:1426`), `malformed_response` (`:1441`), `fold_failed` (`:4811`), `ceded` (`:3475`) and `refused` (`:4120`); none is `failed`, so a gate whose dissent died on the API or on an unparseable payload rows as `none`, is left out of `dissent_absent_gates`, and stays in the report's "dissent-absent gates excluded" sensitivity. The row writer's own header (`:91-93`) defines `error` as "status failed, any other record-fallback, or no envelope although the gate ran", which already does not match the producer's status vocabulary. Raised by the dissent (DISS-002, gpt-5.5-pro) and verified against the emitted statuses.
**Why This Matters:** The field exists to separate planned from unplanned dissent absence for the ablation's sensitivity analysis; the most common unplanned failure modes are the ones it misses, so gate failure rates per arm are under-counted exactly when the dissent infrastructure misbehaves.
**Required Fix:** Enumerate the success statuses (`reviewed`, `clean`) → `none`; `budget_exceeded` → `budget`; preflight as now; everything else (including `api_failure`, `malformed_response`, `fold_failed`, `ceded`, `refused`, an unknown status) → `error`. Add an RW14 case with an `api_failure` envelope asserting `dissent_absent_reason.review == "error"` and `dissent_absent_gates == ["review"]`.
**Reference:** `head/.claude/schemas/adversarial-finding.schema.json:229` lists `api_failure` in the status enum.

---

## Observations

### 1. Eval integrity / calibration

- **MEDIUM** (confidence: medium) `head/evals/harness/lib/sandbox-mount.sh:1040` — clause (d) fails when `rev-list --all` is not exactly the base commit and (`:1047`) when `fsck --unreachable --no-reflogs` prints anything. Post-run this is `took-effect.sh oracle_closed` (`head/evals/harness/took-effect.sh:368`), which `run-ablation.sh` rows as `infrastructure_error` and pauses the arm. The sandbox `.git/info/exclude` (pipeline-run.sh:543) leaves `review.md` and any other agent file trackable, so an agent-side `git add`, `git stash` or `git commit` in the REVIEW/AUDIT phase (nothing in the mount prevents it) pauses the whole a1_full arm as an "infrastructure" failure. The later-blob check (`:1050-1052`) already covers the oracle risk; "exactly the base commit over every ref, nothing unreachable" conflates agent behaviour with mount integrity.
**Suggestion:** Keep the alternates, remote and later-blob checks in (d); downgrade "extra commits / unreachable objects" to evidence (`sandbox_git_mutated=<detail>`) rather than a FAIL, or restrict the ref check to `refs/remotes/*` and the object check to the pinned blobs.
**Benefit:** oracle_closed stays a mount-integrity verdict; agent behaviour cannot pause an arm.

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:1991` — the exemption unit for a repo-name occurrence is the backtick span, and (`:1995`) a unit is exempt when it is a substring of any fixture line holding the token. A bare `` `0xHoneyJar/loa` `` span is therefore a substring of every such fixture line: once a PR fixture mentions the repository anywhere, every backticked bare repo name in an agent's Bash/Write input is exempt, including in commands that are probes (`echo \`0xHoneyJar/loa\``, a quoted token inside a `gh api` call). AG-51's k2 case covers only a fixture WITHOUT the token.
**Suggestion:** Require the unit to be at least the surrounding line's clause (e.g. the whole line when the span is just the token), or require the fixture line's own context (the ≥ 12-character text around the token) to be present in the agent's line, as the oracle detector already does for `must_match`.
**Benefit:** the class 7 exemption stays limited to quoting PR content.

- **MEDIUM** (confidence: medium) `head/evals/graders/recall-vs-defects.sh:299` — the bash branch of `close_line` compares the `}` line's raw indentation (`len(t) - len(t.lstrip())`) with `lv`, which `headers()` (`:283`) measured after `expandtabs(8)`. A tab-indented nested function never finds its brace, so its span runs to the next header at or below its level and overwrites the enclosing function's tags (over-credit). The same loop closes a top-level function at the first `}` at column 0 inside a heredoc body (a jq, JSON or Python literal in a bash function, as in `_sm_oracle_py` itself), so later sites in that function fall back to ±3 (under-credit). Raised by the dissent (DISS-C-001, claude-headless); verified by reading. Use the same `expandtabs(8)` width in both places and skip heredoc bodies (`<<'TAG'` … `TAG`) before testing for the brace.

- **MEDIUM** (confidence: low) `head/evals/graders/recall-vs-defects.sh:135` — the third `head_dir` fallback is `$workspace/pr/head`. Under `ablation-grade.sh` the workspace is the grading directory, into which `grade_recall` copies the sandbox's `pr/` (`head/evals/harness/ablation-grade.sh:2624`), so when the fixture resolves but has no `head/` (or `resolve_pr_fixture` raises) the scope map and the line-count validity rule are read from the agent-writable tree. The grader header (`ablation-grade.sh:45-49`) says the grade never reads sandbox `pr/`. Raised by the dissent (DISS-C-002); the precondition is a misconfigured corpus, hence low confidence. Drop the fallback, or report `head_dir_source` in `details` and let `ablation-grade.sh` refuse a sandbox source.

- **LOW** (confidence: high) `head/evals/graders/recall-vs-defects.sh:214` — `MD_HDR` (`^(#{1,6})(?:\s|$)`) matches `#` comment lines inside fenced code blocks in markdown (every `# comment` in a bash example becomes a level-1 heading), so sections in docs with code fences get cut at comment lines. Track fence state (``` toggles) before matching headings.

- **LOW** (confidence: medium) `head/evals/graders/recall-vs-defects.sh:287` — `CLOSE_ONE` (`\{.*\}\s*(?:#.*)?$`) reads a multi-line function whose header line ends in a parameter expansion (`foo() { local x=${1}` is unusual but `foo() { [[ -n ${x} ]]` is not) as a one-liner; its body is then top-level (no scope). Match `\{.*;\s*\}\s*$` or require the `}` to be preceded by `;`/whitespace rather than a `$`-expansion.

- **LOW** (confidence: high) `head/evals/graders/recall-vs-defects.sh:212` — `PY_HDR` requires `def`; `async def` definitions are no scope. Minor for this corpus.

- **LOW** (confidence: medium) `head/evals/harness/ablation-grade.sh:1656` — `positions(..., fallback=pos_v1)` labels a v1-only id with its v1 position, which may equal a current-manifest position label for a different defect; `missed_pm3_v1` can then carry a `dN` that names two different defects across the row's lists. Prefix v1-only positions (`v1:d3`) or drop them with a note.

- **LOW** (confidence: high) `head/evals/harness/ablation-grade.sh:2010` — `corpus_sha256` guards the path with `read_regular` (symlink-refusing) and then re-opens it with a plain `open(p, "rb")`, which follows a symlink; hash the bytes `read_regular` already returned (or hash through the same fd).

- **LOW** (speculative, confidence: low) `head/evals/harness/lib/sandbox-mount.sh:1014` — clause (b) at pre-launch walks the whole sandbox for any regular file byte-equal to a pinned answer-path version. Two identical files under `.claude/` where the PR touched only one (a skill-include rendered into several SKILL.md files, duplicated resources) refuse the trial as `FAIL (b)`. Not seen in this corpus; worth a note in the evidence rather than a refusal when the equal file is itself at the pinned path's own sibling.

### 2. adversarial-review.sh (budget_scale, numeric anchors)

- **LOW** (confidence: high) `head/.claude/scripts/adversarial-review.sh:164` — when `yq … | tag` fails, `_bt` is `unreadable`, which is neither `!!null` nor empty, so `CONF_BUDGET_SCALE_SET=true` and the envelope names `budget_scale: fixed` for a config that never wrote the key. Treat a yq failure like an absent key (return before setting `_SET`).

- **LOW** (confidence: high) `head/.claude/schemas/adversarial-finding.schema.json:113` — the schema admits any integer ≥ 1 while the normaliser (`head/.claude/scripts/adversarial-review.sh:614`) drops lines above 10,000,000 and the header (`:29`) documents that bound; add `"maximum": 10000000` so the schema and the filter agree.

- **LOW** (confidence: medium) `head/.claude/scripts/adversarial-review.sh:614` — `_adv_line_ok` accepts an integral float (`42.0`: `type == "number" and . == floor`). jq 1.6 (this host) rewrites it to `42`, but jq 1.7+ preserves number literals, so `anchor_line: 42.0` reaches the envelope and the grader's `isinstance(al, int)` (`head/evals/harness/ablation-grade.sh:1567`) drops it silently. Normalise with `.anchor_line |= floor` after the test. Raised by the dissent (DISS-C-004).

- **LOW** (confidence: low) `head/.claude/scripts/adversarial-review.sh:196` — under `diff`, a `budget_cents_max` below `budget_cents` (or below `--budget`) makes `diff` stricter than `fixed` with no WARN; the example config (`head/.loa.config.yaml.example:1639`) documents the clamp, so this is a usability note only. Raised by the dissent (DISS-C-005).

### 3. Complexity (required pass)

- **MEDIUM** (confidence: high) `head/evals/harness/ablation-grade.sh:2312-2432` — `oracle_scan` is 121 lines with four levels of nesting inside the transcript loop; `oracle_plan` (`:2435-2500`) is 66 lines; `cmd_check` (`head/evals/harness/lib/sandbox-mount.sh:958-1058`) is ~100 lines and carries all four clauses inline. `SIMPLICITY[shrink]`: split `oracle_scan` into `_later_lines(f)`, `_scan_diff_result(...)`, `_scan_read_result(...)`; split `cmd_check` per clause. No justification comment is present on any of the three.
  Over-engineering pass: the per-file duplication of the head.diff header parser (`answer_paths` in ablation-grade.sh `:2088-2128` and `diff_paths` in sandbox-mount.sh `:719-783`, plus `header_names`/`unquote_c`) is two implementations of one grammar; one would do, but the grader-trust boundary (no shared source between the grader and the mount library) is a stated reason. `net: -60 lines possible` (the oracle_scan/cmd_check splits are moves, not deletions).

### 4. Report and tests

- **LOW** (confidence: medium) `head/evals/harness/ablation-grade.sh:2368` — the transcript file handle in `oracle_scan` is never closed (iterating `open(...)` directly); harmless under CPython, a ResourceWarning elsewhere. Use `with`.

- **LOW** (confidence: medium) `head/evals/harness/ablation-row.sh:394` — `disabled` in `dissent_absent_reason` is derived from the sandbox `.loa.config.yaml`, which the agent can write; the harness records `loa_config_sha256` at materialisation and finish for this reason, but the row writer does not consult `pipeline.json.mount_integrity`. An agent that flips `flatline_protocol.enabled` mid-run makes an `error` row read as a planned absence. Prefer `meta/arm-evidence.txt` (`dissent=false`, `gates=false`) as the source, or trust the sandbox read only when the config sha is unchanged. Raised by the dissent (DISS-C-003).

- **LOW** (confidence: high) `grimoires/loa/a2a/sprint-1/reviewer.md:1-4` — the implementation report is the PR title and a file count. No `## AC Verification`, no `file:line` evidence per acceptance criterion, no record of the bats runs (`FAST-GATE:` — no formatter or test-run evidence is cited), no stated assumptions. Resubmit with the walkthrough.

### 5. Verified clean (for the record)

Checked and found consistent: `--allow-partial` is accepted by `ablation-grade.sh` (argparse `:388`) and forwarded to freeze.sh; `tyaml` is bound in `post_run`; `KIND`, `FIXTURE_DIR`, `SOURCE_COMMIT`, `_sm_cfg_set_false`, `_SM_REPO_ROOT`, `read_regular(…, whole=, root=)`, `safe_rel`, `transcripts`, `strip_heredocs`, `resolve_pr_fixture`, `missed_consistent(…, None)`, `CONTROL`/`BARE`, `need`/`numn`/`strn` all exist in head; `main` is bound in `build()` before `main.min_cells`; `extra_json` is defined before `version_json` is called; the `--help` sed ranges in ablation-row.sh (`2,/^# ====/`), pipeline-run.sh (`2,144`) and took-effect.sh (awk) end at the header; `_adv_conf_budget_scale` runs only inside the `-f "$CONFIG_FILE"` guard; `_adv_budget_effective` integer ceil is correct for all BSC-7 cases; the schema-enforced branch applies the same numeric-anchor filter; `_sm_evidence` writes to `ARM_EVIDENCE_FILE` directly so `lib_call` does not duplicate lines; the `check_mount_closed` call runs after `regen_sandbox_manifest` and `checksums.json` is outside the answer set; `EXEMPT_BUF` is cleared around its only caller; `FIXTURE_TASK` is reset per grade.

---

## Cross-Model Observations

Phase 2.5 ran `adversarial-review.sh --type review --sprint-id sprint-1 --diff-file pr/head.diff --context-file grimoires/loa/a2a/sprint-1/reviewer-concerns.md --json`: status `reviewed`, primary voice gpt-5.5-pro (answered by codex-headless), companion voice claude-headless `succeeded`, `parse_path: normalized`, `rejected_count: 0`. Envelope: `grimoires/loa/a2a/sprint-1/adversarial-review.json`.

| Dissent id | Voice | Severity | Disposition |
|---|---|---|---|
| DISS-001 | gpt-5.5-pro | BLOCKING | Verified by reproduction → Changes Required §2 (HIGH) |
| DISS-002 | gpt-5.5-pro | BLOCKING | Verified against emitted statuses → Changes Required §3 (HIGH) |
| DISS-C-001 | claude-headless | ADVISORY | Verified by reading → Observations §1 (MEDIUM) |
| DISS-C-002 | claude-headless | ADVISORY | Verified (grading dir holds a sandbox pr/ copy) → Observations §1 (MEDIUM, low confidence) |
| DISS-C-003 | claude-headless | ADVISORY | Plausible, by design per the row header → Observations §4 (LOW) |
| DISS-C-004 | claude-headless | ADVISORY | Holds on jq ≥ 1.7; this host's jq 1.6 normalises → Observations §2 (LOW) |
| DISS-C-005 | claude-headless | ADVISORY | Documented behaviour; usability note → Observations §2 (LOW) |

## Rejected dissent payloads

- None. `metadata.rejected_summary` is empty, `rejected_count` is 0, and the sidecar `grimoires/loa/a2a/sprint-1/adversarial-rejected-review.jsonl` is present but empty (0 rows). No repair hop ran.

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| review the pull request | Pass | every touched file and its tests read; grader rule exercised live |
| report each defect it introduces with the file and line it sits on | Pass | three HIGH (grader over-credit, grader under-credit on multi-line `def`, row-writer status classification), observations above, all cited `head/<path>:<line>` |
| give a merge verdict | Pass | CHANGES_REQUIRED |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [x] Input validation and sanitization present (paths normalised and `.claude/`-scoped; symlinks refused on sandbox reads/writes; yq values validated; numeric anchors bounded)
- [x] Authentication/authorization correct (n/a — no auth surface)
- [x] No SQL/XSS injection vulnerabilities (git runs with `--literal-pathspecs`, no shell interpolation of paths; jq `--arg` throughout)
- [x] Dependencies secure (stdlib only; `python3 -I`)
- [ ] Error messages don't leak sensitive data — fixture paths and commit shas appear in evidence lines by design (CWE-209 not applicable: evidence is harness-internal)

---

## Code Quality Summary

**Strengths:**
- One Python core (`_sm_oracle_py`) serves the overlay, the pre-launch check and the post-run rule, so the launched surface and the verdict use the same comparison.
- Fail-closed configuration reads (`budget_scale`, `budget_cents_max`), strict wire schemas, kept byte-for-byte envelopes when the key is absent (BSC-1, BSC-8).
- Oracle detector is a declared lower bound with real-transcript pins (AG-50).

**Areas for Improvement:**
- Heuristic parsers (bash/markdown headers, diff-output sectioning) need adversarial fixtures drawn from the real corpus, not only hand-built minimal files.
- Three functions over 50 lines without justification (Complexity, above).

---

## Next Steps

1. Fix `BASH_HDR` (require the brace / two-line form) and the python `close_line` signature handling; add the heredoc and multi-line `def` regression tests; re-run RG/AG suites and re-grade the replication runs.
2. Fix the `dissent_absent_reason` classifier to treat every non-success envelope status as `error`; add the `api_failure` row test.
3. Decide the clause (d) scope for agent-side git writes and the backtick exemption unit (Observations 1).
4. Resubmit `reviewer.md` with an `## AC Verification` walkthrough and the bats run output.
5. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*
<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":5,"low":13},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T05:12:00Z"} -->
