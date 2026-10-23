# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)
**Scope:** `pr/head.diff` (35 files, sprint-263: closed review-catch mount, grader 1.3.0, oracle detector, dissent line anchors + `budget_scale`, row writer 1.4, report 1.3). Citations are `head/<path>:<line>` with lines from `pr/head/`.

---

## Verdict: CHANGES_REQUIRED

---

## Process notes

- Phase 0 prerequisite: `engineer-feedback.md` does not say "All good" (the review verdict is CHANGES_REQUIRED, 0 critical / 2 high). The harness instruction for this evaluation is to run the audit regardless and write this file; the audit therefore ran on an unapproved sprint and its findings include the review's two HIGHs, independently reproduced below.
- `grimoires/loa/known-failures.md` is unreadable (SessionStart warning); triage ran without the known-failures surface.
- No beads database (`br` absent), no documentation-coherence reports under `grimoires/loa/a2a/subagent-reports/`; documentation checked manually (see Documentation Audit).
- Input guardrails: PROCEED (`injection_detection` reported ERROR, fail-open per the skill).
- The App Zone here is the frozen `pr/` tree; nothing under `pr/` was changed.

---

## Executive Summary

The security posture of the closed-mount library is good: the answer set is computed from the immutable fixture, sandbox writes use `O_NOFOLLOW` with symlink-component refusal, fixture symlinks are never followed, git runs with a scrubbed environment and no config, paths are normalised against `..`/absolute/control characters, and the grader's `head_lines` is realpath-rooted with an `O_NOFOLLOW` open and a 4 MiB cap. The `budget_scale` arithmetic validates every operand before `(( ))`, logs sanitised config values, and defaults the envelope to the pre-cycle-131 shape when the key is absent. No secrets, no injection sinks fed by untrusted input, no unbounded reads.

The blocking issues are correctness defects in the sprint's decision statistic, not exploits. The grader's new same-scope rule (`pm3_or_same_function`) ends a definition's scope early for two ordinary shapes, a Python `def` whose multi-line signature closes with a dedented `):` and a bash function whose header comment contains `{…}`, so the body silently loses its scope and clause (ii) never credits. Both were reproduced against `head/evals/graders/recall-vs-defects.sh` with controls that credit as documented. `defect_catch_rate` is therefore not reproducible from the documented rule across the live `.claude/` corpus (51 Python files carry the `):` shape, `adversarial-review.sh` has four brace-commented headers).

Two trust-boundary gaps are MEDIUM: the grader falls back to the agent-writable `<workspace>/pr/head` for scope spans when no fixture `head/` resolves (confirmed by the companion dissent voice), and the row writer reads the agent-writable sandbox `.loa.config.yaml` to label a missing dissent envelope as a planned `disabled` absence (companion voice). Both contradict the harness's own "never the agent-writable sandbox" rule stated in this diff.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 7 |
| Low | 10 |

Cross-model security dissent: two voices ran (`gpt-5.5-pro` primary: `status: clean`, 0 findings; `claude-headless` companion: 3 findings, `counted_as: independent_voice`), `voices_succeeded 2`, `degraded: false`, no `degraded_security_review` marker, 0 rejected payloads. Not a DEGRADED_SECURITY_REVIEW.

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] Grader 1.3.0: a Python def with a multi-line signature ends its scope before its body

**Severity:** HIGH (confidence: high)
**File:** `head/evals/graders/recall-vs-defects.sh:308`
**Issue:** The python branch of `close_line` returns `last` at the first non-blank, non-comment line indented `<= lv`:
```python
            if len(t.expandtabs(8)) - len(t.expandtabs(8).lstrip()) <= lv:
                return last
```
For `def f(\n    a,\n    b,\n):` the `):` line is at the def's indentation, so the recorded scope ends on line 3 and the body is top-level. Reproduced with the head grader (`/tmp/audit/g`): site `m.py:5`, citation `m.py:12` → `missed: ["PY-multiline"]`; the identical body under a one-line `def g(a, b):` is `detected` (`recall 0.5`, `credits_function_only []`).
**Impact:** The sprint's decision statistic (`defect_catch_rate`, grader rule `pm3_or_same_function`) silently degrades to the ±3 rule for every defect planted in such a function; 51 live `.claude/` Python files have the `^\s*\):\s*$` shape (`.claude/adapters/cheval.py` among them). The documented rule ("the enclosing definition of the site … identified by its header line") is not what runs. `recall_pm3` / `recall_pm3_v1` are unaffected.
**Fix:** After the header, consume the signature until paren depth returns to zero (or a line ends in `:`) before applying the dedent test; or take `def` spans from `ast` (`end_lineno`, Python ≥ 3.8). Add a bats case with a multi-line signature (RG-37 covers only one-line defs).
**Reference:** Quality/correctness — CWE-682 Incorrect Calculation, https://cwe.mitre.org/data/definitions/682.html. Confirmed by cross-model review (review-gate dissent DISS-002; the audit-gate voices did not raise it).

### [HIGH-002] Grader 1.3.0: a bash header whose comment holds `{…}` is read as a one-line function

**Severity:** HIGH (confidence: high)
**File:** `head/evals/graders/recall-vs-defects.sh:295`
**Issue:**
```python
CLOSE_ONE = re.compile(r'\{.*\}\s*(?:#.*)?$')
…
        if CLOSE_ONE.search(lines[h - 1]) and "{" in lines[h - 1]:
            return h
```
`CLOSE_ONE` is searched over the whole header line, including a trailing `#` comment, so `foo() {  # expands ${X}` ends its definition on its header and the body has no scope. Reproduced: site `s.sh:3`, citation `s.sh:10` → `missed: ["SH-brace-comment"]`; the same body under a plain `bar() {` header is `detected`.
**Impact:** Same as HIGH-001 for bash: `head/.claude/scripts/adversarial-review.sh` alone has four such headers (`_adv_resolve_run_tag`, `_adv_scope_json`, `_adv_cont_watchdog`, `_adv_locality_refused_json`), and it is the file the review-catch corpus touches most.
**Fix:** Strip a trailing unquoted `#…` comment before the one-liner test, then require the `{` that follows `()` and a `}` after it on the same line (e.g. `re.search(r'\(\)\s*\{.*\}\s*$', stripped)`). Add a bats case.
**Reference:** CWE-682, https://cwe.mitre.org/data/definitions/682.html. Confirmed by cross-model review (review-gate companion DISS-C-003).

---

## Medium/Low Priority Issues

### [MED-001] Grader reads scope spans from the agent-writable `<workspace>/pr/head` when no fixture head/ resolves
- **Severity:** MEDIUM (confidence: medium) — trust boundary
- **File:** `head/evals/graders/recall-vs-defects.sh:135`
- **Issue:** `elif [[ -d "$workspace/pr/head" ]]; then head_dir="$workspace/pr/head"`. `$workspace` is the grading dir whose `pr/` is a copy of the sandbox `pr/` (agent-writable). With `EVAL_HEAD_DIR` unset and a fixture lacking `head/`, clause (ii) and the citation-validity rule read definition spans and line counts from agent-controlled files, contradicting `head/evals/harness/ablation-grade.sh:46-49` ("never the agent-writable sandbox pr/"). An agent could rewrite `pr/head/<file>` into one ≤400-line function holding every site, cite any line in it, and be credited. Reachability is low today: `grade_recall` passes the fixture `head/` via `EVAL_HEAD_DIR` and the corpus fixtures carry `head/`.
- **Fix:** Drop the fallback (or gate it behind an explicit self-check flag) and have the grader fail or warn when no trusted head directory exists instead of silently enabling clause (ii) on tamperable input.
- **Reference:** CWE-807 Reliance on Untrusted Inputs in a Security Decision, https://cwe.mitre.org/data/definitions/807.html. Confirmed by cross-model review (audit companion DISS-C-001).

### [MED-002] Row writer 1.4 derives `dissent_absent_reason: disabled` from the agent-writable sandbox config
- **Severity:** MEDIUM (confidence: medium) — trust boundary
- **File:** `head/evals/harness/ablation-row.sh:394`
- **Issue:** `yq -o=json '.flatline_protocol // null' "$RUN_DIR/sandbox/.loa.config.yaml"` feeds `gate_off(...)`, which labels a missing envelope `disabled` (a planned absence the report never excludes) rather than `error`. An agent that sets `flatline_protocol.enabled: false` mid-run both suppresses its own gate and has the absence recorded as benign; `mount_changed`/`loa_config_sha256` record the hash change elsewhere on the row but `dissent_absent_reason` does not consult them. The diff's own policy (`ablation-grade.sh` header) is that sandbox copies are tamperable and `eval/`/`meta/` are authoritative.
- **Fix:** Derive `disabled` from harness-owned evidence only (`meta/arm-evidence.txt` `dissent=false`, arm toggles `flatline`/`gates`); if the sandbox config must be read, compare its sha256 to the pre-launch `loa_config_sha256` and fall through to `error` on mismatch.
- **Reference:** CWE-807, https://cwe.mitre.org/data/definitions/807.html. Confirmed by cross-model review (audit companion DISS-C-002).

### [MED-003] `budget_cents_max // 600` replaces a `false` maximum before the fail-closed validation
- **Severity:** MEDIUM (confidence: high)
- **File:** `head/.claude/scripts/adversarial-review.sh:179`
- **Issue:** `_bm=$(yq eval ".flatline_protocol.${config_key}.budget_cents_max // 600" …)`. Verified: `budget_cents_max: false` → `600` (tag `!!bool`), so `budget_scale: diff` stays on with ceiling 600 instead of the documented "a malformed maximum is said and fixed applies" (`:150-152`, example config). Spend stays bounded by 600c, so this is a contract deviation, not an unbounded-spend path. The same file already reads `companion_voice` raw for exactly this reason (`:261-263`).
- **Fix:** Read the raw value with `| tag` as `_adv_conf_budget_scale` does for the scale; default only on `!!null`/absent; validate everything else.
- **Reference:** CWE-1188 Insecure Default Initialization of Resource, https://cwe.mitre.org/data/definitions/1188.html. (Review-gate dissent DISS-001 raised it as BLOCKING; triaged MEDIUM for the bounded outcome.)

### [MED-004] Post-run `oracle_closed` clause (d) fails on benign agent git activity and pauses the arm
- **Severity:** MEDIUM (confidence: high) — availability of the evaluation
- **File:** `head/evals/harness/lib/sandbox-mount.sh:1040` (via `head/evals/harness/took-effect.sh:389`)
- **Issue:** `if revs != [base]: fails.append(("d", …))` requires `git rev-list --all` of the sandbox to be exactly the base commit. Verified: a `git stash` yields 3 commits in `rev-list --all` (fsck clean); a `git commit` yields 2. An A1 review-catch agent that stashes or commits (ordinary hygiene, not a later-version leak) makes `oracle_closed` FAIL, rows the trial `infrastructure_error` and pauses the arm (DEC-0418).
- **Fix:** Post-run, keep the clauses that evidence a leak (no remote, no alternates, no later-only pinned blob, fsck clean) and report extra commits as evidence rather than FAIL, or confine the exact-commit test to the pre-launch `check_mount_closed`.
- **Reference:** CWE-754 Improper Check for Unusual or Exceptional Conditions, https://cwe.mitre.org/data/definitions/754.html.

### [MED-005] Report 1.3: build rows strand in a `rule n/a` partition during a partial re-grade
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/harness/ablation-report.py:1153`
- **Issue:** `k += f" · rule {part_rule(r) or 'n/a'}"` — when one suite version holds review rows under two grader rules, build rows (`part_rule` None) get their own `rule n/a` partition; no partition then has both pass-rate and catch-rate pairs, H1 is undecidable in every partition and "largest partition is primary" may pick the build-only one.
- **Fix:** Build rows have no grader rule; attach them to every rule partition (or the primary) and keep `n/a` for the pin split only.
- **Reference:** CWE-682, https://cwe.mitre.org/data/definitions/682.html.

### [MED-006] BSC-9 asserts a property of the operator's untracked live config
- **Severity:** MEDIUM (confidence: high) — test determinism
- **File:** `head/tests/unit/adversarial-review-budget-scale.bats:196`
- **Issue:** `[ "$(yq eval '.flatline_protocol.code_review.budget_scale // "absent"' "$PROJECT_ROOT/.loa.config.yaml")" = "absent" ]` — fails in any checkout whose live config sets the key. This workspace's `.loa.config.yaml` sets `budget_scale: diff` for both gates (lines 392 and 406); the dissent envelopes for this very review and audit ran under `budget_scale: diff, budget_cents_max: 1200`.
- **Fix:** Delete lines 195-198 (the example-config assertions above are the versioned contract) or point the check at a fixture.
- **Reference:** CWE-1164 Irrelevant Code / flaky test, https://cwe.mitre.org/data/definitions/1164.html.

### [MED-007] Tests depend on fixtures and curated manifests absent from the diff
- **Severity:** MEDIUM (confidence: low)
- **File:** `head/evals/tests/ablation-grade.bats:1558` (AG-50; also AG-51 `:1578`, `head/evals/tests/run-ablation.bats:1126` RAB-c131-1)
- **Issue:** AG-50/AG-51 read `evals/tests/fixtures/c131-oracle/*` (`:1544`), RAB-c131 reads the `grimoires/loa/evals/ablation-2.0-replication` root, and the PR title's "curated multi-site labels" (`manifests/pr-17.json` anchors, `manifests/v1/`) has no file in the 35-file diff. If these are not already committed, the suite fails and the detector validation pins are unverified. Unable to assess here: this workspace has no `evals/` tree.
- **Fix:** Confirm the fixtures and curated manifests are in the tree (this PR or an already-merged one) and say so in the PR description.
- **Reference:** CWE-1059 Insufficient Technical Documentation, https://cwe.mitre.org/data/definitions/1059.html.

### [LOW-001] Closing-brace indentation measured on the raw line while headers used `expandtabs(8)`
- **File:** `head/evals/graders/recall-vs-defects.sh:299` — `len(t) - len(t.lstrip()) == lv`; a tab-indented nested bash function never finds its `}` and its scope runs to the next header (over-credit from the outer function's tail). No tab-indented `.sh` in the live `.claude/` tree, hence LOW. Fix: `expandtabs(8)` on both sides. (Review-gate DISS-C-003.)

### [LOW-002] Markdown `#` lines inside fenced code blocks count as headings
- **File:** `head/evals/graders/recall-vs-defects.sh:214` — `MD_HDR` has no fence state; a shell snippet in a `.md` creates spurious scopes. Fix: skip lines between ``` fences.

### [LOW-003] `precision_planted_per_flag` can exceed 1
- **File:** `head/evals/harness/ablation-report.py:984` — caught ÷ flags (AR-52 expects `1.5`); a "precision" above 1 misleads. Rename (`planted_caught_per_flag`) or annotate.

### [LOW-004] Test symlink dangles, so the "never followed" assertion tests less than intended
- **File:** `head/evals/tests/sandbox-mount.bats:76` — `ln -s ../../../../outside-secret` from `$FX/head/.claude/skills/s1/` resolves to `$FX/outside-secret`, not `$T/outside-secret` written at `:75`. The overlay still refuses the symlink (the library never follows it), but the SECRET-not-copied check exercises a dangling link. Use five `..` or an absolute target.

### [LOW-005] `split_segments` splits on the `&` of `2>&1`
- **File:** `head/evals/harness/ablation-grade.sh:2159` — `ch in "\n;&|"` cuts `diff a b 2>&1 | wc -l` into `diff a b 2>` / `1` / `wc -l`; the diff loses its pipe separator and is read as content-printing (over-detection). Treat `>&`, `<&`, `&>` as part of the word.

### [LOW-006] Schema still rejects the `budget_exceeded` envelope the script writes
- **File:** `head/.claude/schemas/adversarial-finding.schema.json:248` — metadata gains the three budget keys, but `additionalProperties: false` (`:268`) and the `status` enum (`:226-234`) still reject `reason`, `estimated_cents`, `estimate_voices` and `status: budget_exceeded`. Pre-existing gap, widened by the new `reason` key. (Review-gate DISS-C-005.)

### [LOW-007] Under `diff`, an explicit budget above the maximum is lowered silently
- **File:** `head/.claude/scripts/adversarial-review.sh:197` — `(( eff > max )) && eff=max`. Documented and pinned by BSC-7; a one-line WARN when `conf > max` would make the lowering visible to the operator who passed `--budget`.

### [LOW-008] Evidence readers disagree on duplicate keys
- **File:** `head/evals/harness/lib/sandbox-mount.sh:953` — `setdefault` keeps the FIRST `overlay_sha256`/`mount_overlay` line; `head/evals/harness/ablation-row.sh:419` `evkv` takes the LAST. One overlay per run today; pick one convention before a second writer appears.

### [LOW-009] Schema-enforced branch keeps the unfiltered finding when the anchor filter fails
- **File:** `head/.claude/scripts/adversarial-review.sh:1706` — `candidate=$(_adv_keep_numeric_anchor <<<"$finding") || candidate="$finding"`; on a jq failure a null or out-of-range `anchor_line` admitted by the wire schema (`anyOf integer|null`) reaches the envelope against the published `minimum: 1` contract. jq failing on a parsed object is improbable, hence LOW. Fix: on failure `del(.anchor_line, .anchor_line_end)` instead. (Audit companion DISS-C-003.)

### [LOW-010] KF-046 class-7 exemption unit is a bare substring match
- **File:** `head/evals/harness/ablation-grade.sh:1995` — `unit in text`; a backticked bare token (`` `0xHoneyJar/loa` ``) is exempt whenever the fixture mentions the repository anywhere. By design (D-3.2) but loose; require the token plus a neighbouring word.

---

## Cross-Model Security Observations

Envelope: `grimoires/loa/a2a/sprint-1/adversarial-audit.json` (`--type audit`, `--diff-file pr/head.diff`, no `--context-file`). Primary `gpt-5.5-pro` answered `status: clean` (0 findings); companion `claude-headless` (`counted_as: independent_voice`, `status: succeeded`) returned three findings; `verdict_quality.voices_succeeded 2 / planned 2`; `budget_scale: diff`, estimate 516c, effective 620c (max 1200c). No `metadata.locality.degraded_security_review`. Advisory voices: none.

| Dissent | Severity | Triage |
|---|---|---|
| DISS-C-001 `recall-vs-defects.sh:133-138` `<workspace>/pr/head` fallback | MEDIUM | Verified by reading; counted as MED-001 |
| DISS-C-002 `ablation-row.sh:393` sandbox config → `dissent_absent_reason` | MEDIUM | Verified by reading (`:393-395`); counted as MED-002 |
| DISS-C-003 `adversarial-review.sh:1704` enforced-branch fallback keeps the raw finding | LOW | Verified by reading (`:1706`); counted as LOW-009 |

## Rejected dissent payloads

None. `metadata.rejected_summary` is empty, `rejected_count` 0, and no `adversarial-rejected-audit*.jsonl` sidecar exists beside the envelope.

## Review demotions

The review trailer carries `excluded: 0`; there are no demoted highs to confirm (`excluded_confirmed: 0`).

---

## Sources and Sinks (Phase 1A/1B)

| Source (trust) | Sink | Path | Status |
|---|---|---|---|
| PR fixture `head.diff` / `head/` / `base/` / `fixture.yaml` (harness, immutable) | `_sm_oracle_py` overlay writes under sandbox `.claude/` | `sandbox-mount.sh` `norm`, `in_scope`, `safe_dst`, `O_EXCL|O_NOFOLLOW` | SAFE — `..`, absolute, backslash, control chars rejected; symlink/non-dir ancestors refuse; fixture symlinks never followed (bats-verified) |
| `fixture.yaml` commit ids | `git show`/`ls-tree`/`cat-file` argv | regex `[0-9a-f]{7,64}`, `--literal-pathspecs`, `--` before paths | SAFE |
| Sandbox `.git` (agent-writable) | `git rev-list/remote/fsck/cat-file` in `cmd_check` | scrubbed env, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`, `core.fsmonitor=false`, `--no-pager`, 300 s timeout | SAFE for leak detection; over-fails on benign commits (MED-004) |
| Sandbox files (agent-writable) | clause (b) size-filtered sha256 scan; `state()` reads | `lstat` + `S_ISREG`, symlinks never followed, `pr/` and `.git/` skipped | SAFE |
| Sandbox `pr/head` (agent-writable) | grader scope spans / line counts | `recall-vs-defects.sh:135` fallback | CONFIRMED (MED-001) |
| Sandbox `.loa.config.yaml` (agent-writable) | row field `dissent_absent_reason` | `ablation-row.sh:394` | CONFIRMED (MED-002) |
| Sandbox `.loa.config.yaml` | took-effect `no_review_dissent_envelope` | `took-effect.sh` rule | SAFE — the agent can only make the rule FAIL |
| Operator `.loa.config.yaml` `budget_scale` / `budget_cents_max` | `(( ))` arithmetic, log lines | regex-validated before arithmetic; log values `tr -cd` sanitised and cut | SAFE; default swallows `false` (MED-003) |
| Model output `anchor_line` / `anchor_line_end` | envelope, grader `path:line` reduction | `_ADV_NUMERIC_ANCHOR_JQ` 1..10,000,000, end ≥ start; enforced branch fallback (LOW-009) | SAFE / PARTIAL |
| Transcripts (agent-produced text) | oracle detector regexes, `shlex.split` | bounded reads via `read_regular`, `is_error` skipped | SAFE — heuristic lower bound by design |
| `task.yaml` `review_catch.overlay_mode` (harness) | `overlay_answer_paths` mode | validated `head|base` in `pipeline-run.sh` | SAFE |
| `--pin` CLI (operator) | row filter | `[0-9a-f]{4,40}` | SAFE |

Deferred: none. Unable to assess: the c131 fixtures and curated manifests (MED-007) are not in this workspace.

---

## Rubric Scores

| Dimension | Score | Basis |
|---|---|---|
| SEC-IV Input Validation | 4 | Path normalisation, O_NOFOLLOW, bounded reads; two agent-writable inputs reach decisions (MED-001, MED-002) |
| SEC-AZ Authorization | n/a | No auth surface |
| SEC-CI Confidentiality/Integrity | 4 | Closed mount integrity clauses (a)-(d); evidence written before launch |
| SEC-IN Injection Prevention | 5 | yq/jq via `--arg`/`strenv`; git with `--literal-pathspecs` and `--`; no eval |
| SEC-AV Availability | 3 | Clause (d) pauses arms on benign git activity |
| ARCH-CX Complexity | 3 | `oracle_scan` ~120 lines / five nesting levels; `cmd_check` ~100 lines |
| CQ-TC Test Coverage | 4 | Broad bats coverage; one brittle live-config assertion, one dangling-symlink fixture, fixtures outside the diff |
| CQ-EH Error Handling | 4 | Fail-closed defaults; `false` maximum slips through |
| CQ-DC Documentation | 4 | Headers, example config and both skill docs updated; schema lags the `budget_exceeded` envelope |

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added (the dissent's secret scan applied 1 redaction on the diff context; none found in the files themselves)
- [x] Input validation on new entry points (paths, modes, commit ids, `--pin`, budget keys)
- [x] Authentication required where needed — n/a
- [x] No injection vulnerabilities (yq/jq `--arg`, git `--literal-pathspecs`)
- [x] Error handling doesn't leak info (budget warnings sanitise config values)
- [ ] Tests cover security paths — mostly; the dangling-symlink fixture (LOW-004) under-tests the never-followed assertion

## Documentation Audit

No documentation-coherence reports exist; verified manually: the two skill copies of the new "Numeric anchors and the budget scaling" section are byte-identical (CMP-138 holds); the example config documents both keys under both gates; file headers (`recall-vs-defects.sh`, `sandbox-mount.sh`, `took-effect.sh`, `pipeline-run.sh`, `ablation-row.sh`, `ablation-report.py`) describe the shipped behaviour. Red flags: the finding schema does not match the `budget_exceeded` envelope the script writes (LOW-006); the PR description names "curated multi-site labels" with no file in the diff (MED-007).

---

## Next Steps

1. Fix the Python multi-line signature and bash header-comment cases in `close_line` (HIGH-001, HIGH-002), with a bats case per shape; fix the tab indentation (LOW-001) while there.
2. Remove the `<workspace>/pr/head` fallback (MED-001) and derive `disabled` from harness-owned evidence (MED-002).
3. Default `budget_cents_max` only on a null tag (MED-003); decide the post-run clause (d) policy (MED-004) and the `rule n/a` partition (MED-005); drop the live-config assertion from BSC-9 (MED-006); confirm the c131 fixtures and curated manifests are committed (MED-007).
4. Run `/implement sprint-1` to fix, `/review-sprint sprint-1`, then re-run `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":7,"low":10},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-21T23:30:00Z"} -->
