# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Change under audit:** `pr/head.diff` — cycle-131 sprint-263: closed review-catch mount, grader 1.3.0 (three results, oracle detector), dissent line anchors + budget_scale, curated multi-site labels, versioned re-grade; 35 files
**Task:** review-r27

---

## Verdict: CHANGES_REQUIRED

---

## Scope and prerequisites

- **Prerequisite deviation (recorded).** Phase 0 of this skill expects `engineer-feedback.md` to read "All good" before an audit runs. The review's verdict is CHANGES_REQUIRED (2 HIGH). The task brief instructs the audit to run regardless and autonomously, so it ran; the review's two HIGH findings were re-verified independently here (one by an executable reproduction) rather than carried over.
- **Inputs read.** `pr/head.diff` in full; every touched file under `pr/head/` where a finding sits; `pr/base/` for the before-state of `adversarial-review.sh`, the grader and the pipeline; `grimoires/loa/a2a/sprint-1/engineer-feedback.md` and `adversarial-review.json` (the review's dissent, 7 findings, 0 rejected); the security dissent envelope written by this audit. `grimoires/loa/known-failures.md` is unreadable in this workspace (session hook warning); triage ran without it.
- **Executable evidence.** The workspace holds no `tests/` or `evals/` tree, so 9 of the 10 bats suites the PR touches cannot run here (their helpers and fixtures are absent). `evals/tests/sandbox-mount.bats` needs only the mount library, git, yq and python3, so it was run on a copy of `pr/head/`: 11 ok, 1 skipped (the real-corpus case, no clone). A two-case reproduction suite was appended to the same fixture builders (see HIGH-001). The grader's Python scope code, the oracle detector's `split_segments`, the class 7 exemption and the yq `//` read were each executed in isolation with the inputs named in the findings.
- **Trust assumptions.** The PR fixture (`evals/fixtures/review-prs/pr-NN/`), the suite root, the source tree and `meta/arm-evidence.txt` are harness-owned and trusted. Everything under `<run-dir>/sandbox/` (including `sandbox/pr/`, `sandbox/.loa.config.yaml`, `sandbox/.git`) is agent-writable and UNTRUSTED. The dissent voices' payloads are untrusted model output.
- **Scope limits.** `Unable to assess`: whether the container executor leaves the sandbox owned by another uid (which would make the post-run `git` reads in clause (d) fail on `safe.directory`); no run directory is available here. Noted under Observations, not tallied.

## Executive Summary

The security posture of the change is sound where it defends the trust boundary it names: the overlay never follows a symlink, the fixture is read with `O_NOFOLLOW` and size caps, `git` runs with an isolated config and `core.fsmonitor=false`, paths are normalised before use and `.claude/checksums.json` stays harness-owned. The budget scaling is off by default and the envelope is byte-identical without the key. No secrets, no injection path and no network sink were introduced.

Two defects block the merge and both were confirmed by execution. The closed-mount wiring records the answer-path digests, then lets `apply_arm_toggles` rewrite `SKILL.md` frontmatter and `model-config.yaml`, then verifies against the recorded digests: on arm `a7_effort_medium` any review-catch PR whose answer set holds a skill with an `effort:` line is refused as `infrastructure_error` before a phase runs (reproduced: `FAIL (c) .claude/skills/s1/SKILL.md: mount_mutated`). The grader's 1.3.0 same-scope rule ends a Python definition at the `):` of a multi-line signature, so black-formatted functions have no scope and the decision statistic under-credits on a common code shape (reproduced: a three-line signature's def "ends" on line 3).

Six MEDIUM findings follow, three of them trust-boundary issues the eval harness explicitly set out to close: the row writer classifies a missing dissent as "planned" from the agent-writable sandbox config; the new KF-046 class 7 exemption treats a live `WebFetch` of an upstream URL as "quoting PR content" whenever that URL appears in a fixture file; and the `diff` budget scaling silently undoes the documented fail-closed 0-cent spend cap. Fourteen LOW findings complete the list.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 6 |
| Low | 14 |

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] Arm toggles rewrite overlaid answer paths after their digests are recorded and before the closed-mount check

**Severity:** HIGH — **Confidence:** high (reproduced)
**File:** `head/evals/harness/pipeline-run.sh:566` (order); `head/evals/harness/lib/sandbox-mount.sh:356-361` (mutation); `head/evals/harness/lib/sandbox-mount.sh:986` (refusal)
**Issue:** `pipeline-run.sh` runs `lib_call overlay_answer_paths` (:559), which prints one `overlay_sha256=<path>=<sha>` line per answer path, then `lib_call apply_arm_toggles "$WS" "$TOGGLES" "$ARM"` (:566), then `lib_call check_mount_closed` (:577). The `effort` toggle rewrites every sandbox skill in place:
```bash
      effort)
        local f total=0 stripped=0 still=""
        for f in "$ws"/.claude/skills/*/SKILL.md; do
          ...
          if [[ "$(_sm_strip_frontmatter_effort "$f")" == "1" ]]; then stripped=$((stripped + 1)); fi
```
(`head/evals/harness/lib/sandbox-mount.sh:356-361`) and `yq -i` edits `.claude/defaults/model-config.yaml` (:373). Clause (c) of `cmd_check` then compares the current state with the recorded digest and, because the recorded digest equals the fixture's version, reports the toggle's edit as tampering:
```python
            if rec[p] == want:
                fails.append(("c", p, "mount_mutated=%s (pre-run %s, now %s)" % (p, rec[p][:12], got[:12])))
```
(`head/evals/harness/lib/sandbox-mount.sh:985-986`). `lib_call` turns the non-zero exit into `infra` (`head/evals/harness/pipeline-run.sh:469`).
**Reproduction:** appended to the PR's own `sandbox-mount.bats` fixture builders (a `SKILL.md` answer path with `effort: high` in its frontmatter): overlay → `apply_arm_toggles '{"effort":"medium"}'` → `check_mount_closed` exits 2 with `ERROR: check_mount_closed: FAIL (c) .claude/skills/s1/SKILL.md: mount_mutated=.claude/skills/s1/SKILL.md (pre-run a77faa5262bf, now ae57fcfa6cc5)`; the control case without the toggle passes.
**Impact:** `a7_effort_medium` has `task_types: [all]` (`head/evals/suites/ablation-2.0.yaml:89`). Six skills in this tree carry an `effort:` line (auditing-security, bridgebuilder-review, designing-architecture, implementing-tasks, red-teaming, reviewing-code); any review-catch PR touching one of them (the AG-50 test names `auditing-security/SKILL.md` in pr-04's answer set) or `model-config.yaml` makes every A7 trial an `infrastructure_error` with no phase run. The pre-registered A7 contrast silently loses those cells; `took-effect` pauses nothing because no run exists. The same class applies to `audit_delta_instruction` (rewrites `auditing-security/SKILL.md`, :340-346), `karpathy_block` (`.claude/loa/CLAUDE.loa.md`, :316) and `rule_files` (`.claude/rules/*`, :336) on any arm that carries them for a review-catch task. The only test of toggle/overlay interaction (`head/evals/tests/sandbox-mount.bats:302`) uses `dissent: false`, which edits `.loa.config.yaml`, outside the answer set. The header comment "the checked surface is the launched one" (`head/evals/harness/pipeline-run.sh:575`) shows the ordering is deliberate, so this is a design conflict rather than a slip.
**Fix:** Have `check_mount_closed` accept a toggle-declared exemption: `apply_arm_toggles` records `overlay_toggled=<path>=<new sha>` for every answer path it lawfully rewrote (the effort, audit-delta, karpathy and rule toggles know their targets), and clause (c) compares against the toggled digest when one exists, still requiring the pre-toggle digest to have equalled the fixture's version (so the toggle operated on the PR's copy). Mirror the same in `took-effect.sh oracle_closed`, which reads the same evidence. Add the reproduction above as a passing bats case.
**Reference:** CWE-696 Incorrect Behavior Order — https://cwe.mitre.org/data/definitions/696.html

### [HIGH-002] Grader 1.3.0: a Python definition ends at the `):` of a multi-line signature, so black-formatted functions have no scope

**Severity:** HIGH — **Confidence:** high (reproduced)
**File:** `head/evals/graders/recall-vs-defects.sh:308` (end detection); `:212` (header regex)
**Issue:** `PY_HDR` matches `def NAME(` without the closing parenthesis, and `close_line` ends the definition at the first later non-blank, non-comment line indented no deeper than the `def`:
```python
            if len(t.expandtabs(8)) - len(t.expandtabs(8).lstrip()) <= lv:
                return last
```
(`head/evals/graders/recall-vs-defects.sh:308-309`). For `def f(\n    a,\n    b,\n):` the `):` line has the def's indentation, so the definition "ends" on its own signature and the body is top-level (`scope None`); clause (ii) of `hit_new` (`:356-371`) then credits nothing inside it.
**Reproduction:** the grader's `headers`/`close_line` executed on that shape: `headers [(1, 0), (8, 0)]`, `def at 1 ends 3`, `def at 8 ends 10` — the first function's scope is lines 1–3 (its signature), its body lines 5–7 have no scope.
**Impact:** `recall` is the decision statistic of report 1.3 (`defect_catch_rate`). A defect site inside a black-formatted function and a valid citation 4+ lines away in the same function credit nothing under `recall` while `recall_pm3` is unaffected, so the "same scope" clause misreports exactly where it was meant to help, on a shape the review corpus contains in volume (the review counted 206 such signatures under `.claude/adapters`). RG-37 only covers one-line `def` headers.
**Fix:** In `close_line` for Python, first advance past the signature: track the parenthesis depth from the header line until the line whose `)` closes the header's `(` (optionally followed by `-> T`) and `:`, then apply the dedent test from the following line. Add an RG case with a multi-line signature and a citation six lines into the body.
**Reference:** CWE-682 Incorrect Calculation — https://cwe.mitre.org/data/definitions/682.html

---

## Medium Priority Issues

### [MED-001] `budget_cents_max // 600` coerces an explicit `false` into 600, so a malformed maximum keeps `diff` scaling instead of failing closed

- **Severity:** MEDIUM — **Confidence:** high (reproduced)
- **File:** `head/.claude/scripts/adversarial-review.sh:179`
- **Issue:** `_bm=$(yq eval ".flatline_protocol.${config_key}.budget_cents_max // 600" ...)` — yq's `//` treats `false` (and `null`) as absent. With `budget_scale: diff` and `budget_cents_max: false`, `yq` prints `600` (verified), the whole-number check at `:180` passes, and the run scales to 600c instead of falling back to `fixed` as the header (`:25-26`), the example config and both ADVERSARIAL-REVIEW.md pages promise. The same file documents this pitfall for `companion_voice` (`:261`). Raised by the review's dissent as DISS-001 (BLOCKING); the damage is bounded by the 600c default, so MEDIUM.
- **Fix:** Read the tag first, as `_adv_conf_budget_scale` does for the scale (`:164`): `!!null`/absent → 600; `!!int` → validate the raw value; anything else → WARN and `fixed`.
- **Reference:** CWE-1287 Improper Validation of Specified Type of Input — https://cwe.mitre.org/data/definitions/1287.html

### [MED-002] Under `budget_scale: diff` the configured budget can never refuse a run, which undoes the documented fail-closed 0-cent spend cap

- **Severity:** MEDIUM — **Confidence:** high
- **File:** `head/.claude/scripts/adversarial-review.sh:194-197` (`_adv_budget_effective`); `:259` (the fail-closed read)
- **Issue:** `scaled=$(( (est * 12 + 9) / 10 ))` is always ≥ `est`, and `eff = max(conf, scaled)` capped at `budget_cents_max`, so under `diff` the configured `budget_cents` (and `--budget`) is only a floor; the only cap is `budget_cents_max`. That is the documented formula. What it silently removes is the hardening on the line above it: a malformed `budget_cents` "fails CLOSED: 0 cents" (`:259`, "sixteenth run, a1 C-004") so that every dispatch is refused; under `diff`, `max(0, scaled) = scaled` and both voices dispatch up to 600c. The eval harness forces `diff` on every mounted arm (`apply_eval_config_variant`), so in the harness the fail-closed rule is dead code. Security dissent DISS-C-001, confirmed.
- **Fix:** In `_adv_budget_effective`, keep `fixed` semantics when `CONF_BUDGET_CENTS` came from the fail-closed default (have `_conf_uint` export a `_MALFORMED` flag, or compare the raw value), and WARN that `diff` was not applied. Document that `budget_cents` is a floor under `diff`.
- **Reference:** CWE-770 Allocation of Resources Without Limits or Throttling — https://cwe.mitre.org/data/definitions/770.html

### [MED-003] Row writer 1.4 classifies an absent dissent as planned ("disabled") from the agent-writable sandbox config

- **Severity:** MEDIUM — **Confidence:** medium
- **File:** `head/evals/harness/ablation-row.sh:394` (the read); `:468-480` (`reason`)
- **Issue:** `yq -o=json '.flatline_protocol // null' "$RUN_DIR/sandbox/.loa.config.yaml"` feeds `gate_off`, and `reason` returns `"disabled"` before it looks at the envelope. The sandbox config is the agent's to edit mid-run; the grader header in this same PR calls the sandbox copies "tamperable" and refuses to read them for envelopes. An agent (or a hook misfire) that flips `flatline_protocol.enabled: false` both suppresses the gate and gets the absence filed under the planned bucket, which `dissent_reason` in report 1.3 never excludes (`head/evals/harness/ablation-report.py:596-600`). The `! -L` guard stops a symlink, not an edit. Security dissent DISS-C-003 and the review's Observation 2, confirmed.
- **Fix:** Derive `disabled` from harness evidence only (`dissent=false`, `flatline=…`, `gates=…` in `meta/arm-evidence.txt`), or trust the sandbox config only when `pipeline.json.mount_integrity` says `loa_config_sha256` is unchanged at finish. Otherwise classify as `error`.
- **Reference:** CWE-807 Reliance on Untrusted Inputs in a Security Decision — https://cwe.mitre.org/data/definitions/807.html

### [MED-004] Oracle detector: `split_segments` splits on a bare `&`, so `2>&1` breaks a diff segment and the count output marks every defect of the file `exposed_unknown`

- **Severity:** MEDIUM — **Confidence:** high (reproduced)
- **File:** `head/evals/harness/ablation-grade.sh:2159` (the split); `:2418-2420` (`exposed_unknown`)
- **Issue:** `elif depth == 0 and ch in "\n;&|":` — executed: `split_segments("diff pr/head/X .claude/X 2>&1 | wc -l")` → `[('diff pr/head/X .claude/X 2>', ';'), ('1', '|'), ('wc -l', ';')]`. The diff segment's separator is `;`, so `oracle_plan` never sees the pipe into `wc` (`:2481`), `DEVNULL` does not match, and the plan carries a `diff:` target. The tool result `4` is not an `ERR_LINE`, yields no ranges and no `must_match`, so `oracle_scan` records `exposed_unknown` for every defect of that file. `2>&1` is routine in agent commands; AG-48's `| wc -l` case passes only without the redirection. The same split turns `&>` and `>&` into separate segments.
- **Impact:** false oracle-exposure flags leave valid cells out of the "oracle-exposed cells excluded" sensitivity and, with `--exclude-oracle-exposed true`, out of the main reads.
- **Fix:** Treat `N>&M`, `&>`, `>&` and `&>>` as part of the word (look behind for `>` or `<` and ahead for `>`), and split on `&` only when it is `&&` or a lone `&` followed by whitespace/end. Add the `2>&1 | wc -l` case to AG-48.
- **Reference:** CWE-697 Incorrect Comparison — https://cwe.mitre.org/data/definitions/697.html

### [MED-005] KF-046 class 7 exemption also exempts live `WebFetch`/`WebSearch` probes and backtick-wrapped tokens whenever the text appears in a fixture line

- **Severity:** MEDIUM — **Confidence:** high (mechanism reproduced; the trigger needs a fixture file carrying an upstream URL, which Loa's `.claude/` tree routinely does)
- **File:** `head/evals/harness/ablation-grade.sh:1808-1812` (the exemption applies to every tool); `:1989-1994` (the unit rule); `:1697-1699` (`FIELDS` includes `WebFetch.url` and `WebSearch.query`)
- **Issue:** `check_value` runs the same `repo_name_exempt(val)` for every tool and field. The unit for an occurrence is "the backtick span holding it, else the whole line", exempt when it is a substring of one fixture line. Executed with a fixture line `- Defect: [#555](https://github.com/0xHoneyJar/loa/issues/555) — …` (the text of `.claude/rules/stash-safety.md`, an in-scope answer path when a PR touches it): `repo_name_exempt("https://github.com/0xHoneyJar/loa/issues/555")` → exempt. A `WebFetch` of that URL is a live read of the upstream repository (the issue or PR page may hold the fix), yet the scan now records it in `contamination_exempt` instead of `contaminated`. Likewise a Bash value whose only token occurrence sits inside any backtick pair (`` gh repo view `0xHoneyJar/loa` `` → exempt), because the span regex ignores shell quoting and every fixture line with the token contains the bare token. The scan is a documented lower bound, but this is a new, specific false negative added by the PR on the one tool that always reaches the network.
- **Fix:** Never apply the exemption to `WebFetch.url` or `WebSearch.query`; for Bash, require the unit to be the whole line (drop the backtick-span rule, or require the span to be inside single quotes). Add a negative AG-51 case for a `WebFetch` of a fixture URL.
- **Reference:** CWE-693 Protection Mechanism Failure — https://cwe.mitre.org/data/definitions/693.html

### [MED-006] Process: no AC verification and no test-run evidence for ten bats suites that cannot be run here

- **Severity:** MEDIUM — **Confidence:** high
- **File:** `grimoires/loa/a2a/sprint-1/reviewer.md:1` (the report is `pr/PR.md`: the title and "35 file(s) in scope")
- **Issue:** The PR adds or edits ten bats suites (`sandbox-mount`, `took-effect`, `pipeline-run`, `run-ablation`, `ablation-grade`, `ablation-row`, `ablation-report`, `eval-recall-grader`, `adversarial-review-budget-scale`, `adversarial-review-normalise`) and carries no `## AC Verification` and no summary line showing they ran green. Nine of them cannot run in this workspace (no `tests/` or `evals/` tree). Only `sandbox-mount.bats` was runnable and passed (11 ok, 1 skipped). No documentation-coherence report exists under `grimoires/loa/a2a/subagent-reports/`. For a change that redefines the decision statistic and the trust boundary of the harness, the test evidence is the acceptance criterion.
- **Fix:** Add the walkthrough and paste the ten bats summary lines into the implementation report; include the two reproductions above as regression cases.
- **Reference:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html

---

## Low Priority Issues

### [LOW-001] `MD_HDR` reads `#` comment lines inside fenced code blocks as markdown headings
- **Severity:** LOW — **Confidence:** high
- **File:** `head/evals/graders/recall-vs-defects.sh:214`
- **Issue:** `MD_HDR = re.compile(r'^(#{1,6})(?:\s|$)')` matches any line starting with `#`, including a shell comment inside a ```` ``` ```` block in a `.md` file, which splits a section at a code comment and loses same-section credit after it.
- **Fix:** Track fence state (toggle on a line starting with ```` ``` ```` or `~~~`) and skip header matching inside it.
- **Reference:** CWE-185 Incorrect Regular Expression — https://cwe.mitre.org/data/definitions/185.html

### [LOW-002] `CLOSE_ONE` matches a `}` inside a trailing header comment, making the function one line long
- **Severity:** LOW — **Confidence:** medium (reproduced on a synthetic header; no such header in the tree today)
- **File:** `head/evals/graders/recall-vs-defects.sh:287`, `:295`
- **Issue:** `CLOSE_ONE = re.compile(r'\{.*\}\s*(?:#.*)?$')` searched on the whole header line: `g() {  # reads ${X}` → executed `close_line` returns the header line itself, so the body is top-level.
- **Fix:** Strip a trailing `#…` comment (outside quotes) before testing for a one-line body.
- **Reference:** CWE-185 — https://cwe.mitre.org/data/definitions/185.html

### [LOW-003] bash `close_line` compares raw indentation while `headers` uses `expandtabs(8)`
- **Severity:** LOW — **Confidence:** medium
- **File:** `head/evals/graders/recall-vs-defects.sh:299` vs `:283`
- **Issue:** `len(t) - len(t.lstrip()) == lv` where `lv` was computed from the expanded header; a tab-indented function header never matches its closing brace and the scope runs to the next header.
- **Fix:** Use `t.expandtabs(8)` on both sides as the Python branch does (`:308`).
- **Reference:** CWE-697 — https://cwe.mitre.org/data/definitions/697.html

### [LOW-004] `json.load` of the v1 manifest is unguarded
- **Severity:** LOW — **Confidence:** high
- **File:** `head/evals/graders/recall-vs-defects.sh:143`
- **Issue:** `man_v1 = json.load(open(manifest_v1_path)) if manifest_v1_path else man` — a malformed `v1/<fixture>.json` is a traceback and exit 1, not the documented exit 2 with `err()` JSON. `grade_recall` raises `GradeError` on the empty stdout (`head/evals/harness/ablation-grade.sh:1639`), so no silent mis-grade. Security dissent of the review DISS-C-004.
- **Fix:** Wrap in `try/except (OSError, ValueError)` → `err("v1 manifest unreadable")`.
- **Reference:** CWE-755 Improper Handling of Exceptional Conditions — https://cwe.mitre.org/data/definitions/755.html

### [LOW-005] Head-dir fallback to the agent-writable `$workspace/pr/head`, and quadratic scope mapping on a hostile file
- **Severity:** LOW — **Confidence:** low (reachable only when `EVAL_HEAD_DIR` is unset and the corpus fixture is absent, which also fails `resolve_pr_fixture`)
- **File:** `head/evals/graders/recall-vs-defects.sh:135`; `:329-342` (`scope_map`)
- **Issue:** `elif [[ -d "$workspace/pr/head" ]]; then head_dir="$workspace/pr/head"` — `grade()` copies `sandbox/pr` into `grading/pr`, so this is the agent's copy. Were it reached, an agent that wraps a head file in one definition makes every citation in it credit every defect in it; and `scope_map`'s `for h2 in hs[k+1:]` plus the per-span line loop is O(headers² + lines × depth) over a 4 MiB file, so a crafted file can stall the grader to its deadline. Security dissent DISS-C-002. Both the grader header and `grade_recall` say the sandbox `pr/` is never read; the fallback contradicts that.
- **Fix:** Drop the fallback; with no `EVAL_HEAD_DIR` and no corpus fixture, set `head_dir=""` (clause (ii) never credits) and note it in `details`.
- **Reference:** CWE-807 — https://cwe.mitre.org/data/definitions/807.html; CWE-407 Inefficient Algorithmic Complexity — https://cwe.mitre.org/data/definitions/407.html

### [LOW-006] A yq read failure yields `unreadable`, which sets `CONF_BUDGET_SCALE_SET=true`
- **Severity:** LOW — **Confidence:** medium
- **File:** `head/.claude/scripts/adversarial-review.sh:164-168`
- **Issue:** `|| echo "unreadable"` is not `!!null`/empty, so an unparseable config logs a WARN about a key never written and puts `budget_scale`/`budget_cents_effective`/`budget_cents_max` in the envelope, against the "absent key is byte for byte the shipped envelope" contract. Security dissent of the review DISS-C-001.
- **Fix:** Treat `unreadable` like absent (return 0 before setting `_SET`).
- **Reference:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html

### [LOW-007] `budget_cents_max: 0` is accepted; under `diff` every run then refuses with `budget_exceeded`
- **Severity:** LOW — **Confidence:** high
- **File:** `head/.claude/scripts/adversarial-review.sh:180`
- **Issue:** `^(0|[1-9][0-9]{0,14})$` admits 0. Fail-closed, but silent; worth a WARN.
- **Fix:** Require ≥ 1 (reuse `_conf_uint` with floor 1) or WARN on 0.
- **Reference:** CWE-20 Improper Input Validation — https://cwe.mitre.org/data/definitions/20.html

### [LOW-008] The finding schema's `metadata` is `additionalProperties: false` and lacks the `reason` key the budget_exceeded envelope now writes
- **Severity:** LOW — **Confidence:** high
- **File:** `head/.claude/schemas/adversarial-finding.schema.json:268` (the closing rule); `head/.claude/scripts/adversarial-review.sh:4445` (`reason: "budget"`)
- **Issue:** The PR adds `budget_scale`, `budget_cents_effective`, `budget_cents_max` to `metadata` but not `reason`; `status` lacks `budget_exceeded` (pre-existing). The schema is not enforced at runtime in this tree, so this is drift, not a failure. The `anchor_line` description also omits the 10,000,000 cap the normaliser applies. Security dissent of the review DISS-C-002.
- **Fix:** Add `reason` (string) and the cap to the schema.
- **Reference:** CWE-1068 Inconsistency Between Implementation and Documented Design — https://cwe.mitre.org/data/definitions/1068.html

### [LOW-009] Schema-enforced branch falls back to the unfiltered finding when the numeric-anchor jq filter fails
- **Severity:** LOW — **Confidence:** medium
- **File:** `head/.claude/scripts/adversarial-review.sh:1706-1707`
- **Issue:** `candidate=$(_adv_keep_numeric_anchor <<<"$finding") || candidate="$finding"; [[ -n "$candidate" ]] || candidate="$finding"` — on a jq error the finding passes through with whatever `anchor_line` the wire schema admitted (it allows `null`), so a non-integer line can reach the envelope and the harness's `path:line` reduction. Rare (jq on already-parsed JSON). Security dissent DISS-C-004.
- **Fix:** On filter failure, `del(.anchor_line, .anchor_line_end)` rather than keep the raw finding.
- **Reference:** CWE-755 — https://cwe.mitre.org/data/definitions/755.html

### [LOW-010] `took-effect.sh resolve_fixture` with `--task-yaml` omits the `$SOURCE_TREE/evals/fixtures` root and never falls back to the `overlay_fixture` evidence
- **Severity:** LOW — **Confidence:** medium
- **File:** `head/evals/harness/took-effect.sh:356`
- **Issue:** The candidate list is `"$td/$rel" "$td/../../$rel" "$REPO_ROOT/$rel" "$REPO_ROOT/evals/fixtures/$rel"`; `pipeline-run.sh resolve_rel` (`head/evals/harness/pipeline-run.sh:508`) also accepts `$SOURCE_TREE/evals/fixtures/$rel`. A run whose fixture lives only in the source tree FAILs `oracle_closed` ("does not resolve") although the overlay recorded where it is, and a `took-effect` FAIL pauses the arm.
- **Fix:** Try the evidence's `overlay_fixture` when the `--task-yaml` candidates miss (still refusing a path inside the run dir).
- **Reference:** CWE-1068 — https://cwe.mitre.org/data/definitions/1068.html

### [LOW-011] `corpus_sha256` re-opens the file by path after `read_regular` already read it
- **Severity:** LOW — **Confidence:** high
- **File:** `head/evals/harness/ablation-grade.sh:2010`
- **Issue:** `read_regular(p, READ_CAP, whole=True)` opens with `O_NOFOLLOW` and a cap, then `with open(p, "rb") as f: return hashlib.sha256(f.read())` re-opens by path without either guard. The corpus is harness-owned, so the window is theoretical.
- **Fix:** Hash the bytes `read_regular` returned (return bytes, or hash inside it).
- **Reference:** CWE-367 Time-of-check Time-of-use — https://cwe.mitre.org/data/definitions/367.html

### [LOW-012] `poslist` nulls the whole `defects_missed_pm3_v1` list when one v1-only id's position exceeds `defects_seeded`
- **Severity:** LOW — **Confidence:** medium
- **File:** `head/evals/harness/ablation-row.sh:536`; `:421-422`
- **Issue:** The grader maps a v1-only id to its position in the v1 manifest (`head/evals/harness/ablation-grade.sh:1649-1656`), which may exceed the current key's count; `positions_rule($seeded)` then rejects the list and the row loses the field entirely.
- **Fix:** Validate `_pm3_v1` positions against `planted_v1` (carry it into the row), not `defects_seeded`.
- **Reference:** CWE-682 — https://cwe.mitre.org/data/definitions/682.html

### [LOW-013] Post-run closed-mount check reads agent-writable files by path and without a size cap
- **Severity:** LOW — **Confidence:** medium
- **File:** `head/evals/harness/lib/sandbox-mount.sh:887` (`state`); `:1029` (clause (b))
- **Issue:** `return sha(open(full, "rb").read())` after `os.path.islink`/`isfile` checks, and `h = sha(open(full, "rb").read())` in the sandbox walk, read whole files into memory with no cap and no `O_NOFOLLOW`. Post-run (`took-effect.sh oracle_closed`) the sandbox is the agent's: a multi-GB regular file left at an answer path exhausts the checker's memory (a FAIL/crash, not a bypass; the lstat gate excludes FIFOs). Pre-launch the same code runs on a harness-built tree, where it is fine.
- **Fix:** Reuse `read_regular`-style bounded `O_NOFOLLOW` reads; hash in chunks; treat an over-cap file as a state of its own ("oversized").
- **Reference:** CWE-400 Uncontrolled Resource Consumption — https://cwe.mitre.org/data/definitions/400.html

### [LOW-014] Functions well over the 50-line guideline with no justification
- **Severity:** LOW — **Confidence:** high
- **File:** `head/evals/harness/ablation-grade.sh:2312` (`oracle_scan`, ~120 lines, four nested loops with inner closures); `:2435` (`oracle_plan`, ~65); `head/evals/harness/lib/sandbox-mount.sh:958` (`cmd_check`, ~100, clauses (a)–(d) in one body)
- **Issue:** Review-resistant code at the harness's trust boundary; MED-004 hid inside `oracle_plan`'s pipe handling.
- **Fix:** Split `oracle_scan` into `later_lines(f)`, `scan_diff_result(...)`, `scan_read_result(...)`; split `cmd_check` per clause.
- **Reference:** CWE-1120 Excessive Code Complexity — https://cwe.mitre.org/data/definitions/1120.html

---

## Observations

- **Not tallied (speculative, no defect observed).** Clause (d) runs `git rev-list`, `remote`, `fsck` and `cat-file` inside the agent-written `sandbox/.git` (`head/evals/harness/lib/sandbox-mount.sh:1041-1056`). The hostile-repo config vectors are handled (`-c core.fsmonitor=false`, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`, `--no-pager`, no hook-running or network subcommands, a 300 s timeout). What I could not assess is `safe.directory`: if the container executor leaves the sandbox owned by another uid, every `git()` call returns `None`, clause (d) FAILs with `<unreadable>`, and `took-effect` pauses the arm. Worth one smoke run under the container executor before the batch.
- **Verified safe.** Path normalisation in `norm()`/`safe_rel` (no absolute, `..`, backslash or control characters; `.claude/` only; `checksums.json` excluded); symlink-refusing overlay (`safe_dst`, `O_EXCL | O_NOFOLLOW`); the `oracle_open` toggle refuses after an overlay; `apply_eval_config_variant` verifies its writes; `--pin` grammar validated; `_ADV_NUMERIC_ANCHOR_JQ` drops rather than rejects; the `budget_exceeded` path still exits 4; log strings are sanitised with `tr -cd` before printing config values.

## Security Dissenter (Phase 1C)

Envelope: `grimoires/loa/a2a/sprint-1/adversarial-audit.json` — status `clean`, primary `gpt-5.5-pro`, companion `claude-headless` (`independent_voice`, succeeded), `budget_scale: diff`, `degraded: false`, `locality: null` (no DEGRADED_SECURITY_REVIEW). The dissent ran on `--diff-file pr/head.diff` (the task's instruction; the skill's default `--diff-range main...HEAD` has no PR commits in this workspace). The context assembler truncated the 117k-token diff to 13 files (the top-priority `ablation-grade.sh` shown partially), so the voices did not see the grader's Python scope code or the oracle detector. Four findings, all advisory-severity from the companion, triaged:

| Id | Voice | Dissent severity | Triage |
|----|-------|------------------|--------|
| DISS-C-001 | claude-headless | MEDIUM | Confirmed; MED-002 |
| DISS-C-002 | claude-headless | MEDIUM | Confirmed mechanism, low reachability; LOW-005 |
| DISS-C-003 | claude-headless | MEDIUM | Confirmed; MED-003 |
| DISS-C-004 | claude-headless | LOW | Confirmed; LOW-009 |

## Rejected dissent payloads

- None — `metadata.rejected_count` is 0, `metadata.rejected_summary` is empty, and no `adversarial-rejected-audit.jsonl` sidecar was written.

## Review cross-check

The review trailer counts `excluded: 0` (no HIGH demoted as speculative), so there is nothing to confirm or re-tally: `excluded_confirmed: 0`. Both review HIGHs were re-derived here (HIGH-001 by a bats reproduction against the PR's own library, HIGH-002 by executing the grader's scope code). Of the review's five MEDIUMs, three stand (MED-001, MED-003, MED-004), the process item stands (MED-006), and the complexity item is re-rated LOW (LOW-014, code quality without a security scenario). MED-002 and MED-005 are new.

## Rubric scores (1–5)

| Dimension | Score | Basis |
|-----------|-------|-------|
| SEC-IV Input validation | 4 | Allowlisted paths, tag-checked YAML reads; gaps at MED-001, LOW-006/007 |
| SEC-CI Confidentiality/Integrity | 3 | Closed mount is well built, but MED-003/MED-005 and LOW-005 re-open reads of agent-writable data the PR set out to close |
| SEC-IN Injection | 5 | argv-only subprocesses, `--literal-pathspecs`, no eval, sanitised logs |
| SEC-AV Availability | 3 | HIGH-001 refuses whole arms; LOW-005/LOW-013 unbounded work on hostile inputs |
| ARCH-MO Modularity | 4 | One Python core shared by overlay/check/took-effect is the right shape; toggle/overlay ordering lacks a model (HIGH-001) |
| CQ Code quality | 3 | LOW-014; heuristics in the grader need signature/fence/tab awareness before they are the decision statistic |
| DevOps | 3 | Test evidence absent from the report (MED-006); the one runnable suite passes |

## Security Checklist for This Sprint

- [x] No hardcoded secrets added (dissent secret scan: 1 redaction in the assembled prompt, none in the diff)
- [x] Input validation at trust boundaries present on the new mount surface — with the exceptions in MED-003, MED-005, LOW-005, LOW-013
- [x] No command injection (argv-only `subprocess.run`, isolated git env, `yq` with `strenv`)
- [x] No SQL/XSS surface
- [x] Error handling does not leak sensitive data (digests and key=value evidence only)
- [ ] Tests cover security paths — the toggle/overlay interaction on an answer path and the `WebFetch` exemption have no test; nine suites could not be run here

## Next Steps

1. Fix HIGH-001 (toggle-declared exemption in clause (c), mirrored in `took-effect.sh`) and HIGH-002 (signature-aware Python end detection), each with the reproduction as a bats case.
2. Address MED-001 through MED-005 or record an explicit deferral per item; MED-003 and MED-005 are trust-boundary regressions and should not be deferred.
3. Run the ten bats suites and record the summaries plus an `## AC Verification` walkthrough in `grimoires/loa/a2a/sprint-1/reviewer.md` (MED-006).
4. Re-run `/review-sprint sprint-1`, then `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":6,"low":14},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-21T12:38:00Z"} -->
