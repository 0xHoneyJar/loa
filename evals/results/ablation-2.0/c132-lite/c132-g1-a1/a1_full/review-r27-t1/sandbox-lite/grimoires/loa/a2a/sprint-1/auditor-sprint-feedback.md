# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Change under audit:** `pr/head.diff` (35 files). Citations are `head/<path>:<line>` with line numbers from `pr/head/`.
**Task:** review-r27

---

## Verdict: CHANGES_REQUIRED

---

## Pre-flight notes

- **Phase 0 prerequisite not met.** `engineer-feedback.md` ends `CHANGES_REQUIRED` (4 high), not "All good". The audit ran anyway on the task's explicit instruction; this report is therefore an audit of the change as reviewed, not of a fixed round. `adversarial-review.json` carries `metadata.model: gpt-5.5-pro`, `status: reviewed`.
- **Known-failures surface degraded.** `grimoires/loa/known-failures.md` does not exist (the SessionStart hook said so); triage ran without it.
- **Scope analysis** (`security-audit-scope.sh`): the repository-wide counts (197 command-exec sinks, 157 file-op sinks) are the host repo's; this audit is scoped to the 35 files of `pr/head.diff`. Trust boundaries assumed: the PR fixture (`pr/head`, `pr/base`, `head.diff`, manifests) and `meta/arm-evidence.txt` are harness-owned and trusted; everything under the run's `sandbox/` (including `sandbox/pr/`, `sandbox/.loa.config.yaml`, `sandbox/.git`) is written by the evaluated agent and untrusted; `.loa.config.yaml` of the host repo is operator-owned.
- **Input guardrails:** `guardrails-orchestrator.sh` → `PROCEED`.
- **Security dissenter (Phase 1C):** ran with `--type audit --sprint-id sprint-1 --diff-file pr/head.diff --json`, no context file. Envelope `grimoires/loa/a2a/sprint-1/adversarial-audit.json`: primary `gpt-5.5-pro` `status: clean`, companion `claude-headless` `status: succeeded`, `counted_as: independent_voice`, `degraded: false`, `budget_scale: diff`, effective 620c of 1200c, 4 companion findings (1 MEDIUM, 3 LOW), 0 rejected. Not a DEGRADED_SECURITY_REVIEW.

---

## Executive Summary

The change ships three integrity mechanisms for the review-catch evaluation — a closed mount over the PR's answer paths, an oracle-exposure detector, and a line-level contamination exemption — plus grader 1.3.0, numeric dissent anchors, a diff-scaled dissent budget and report 1.3. The mount core is careful: one Python implementation serves overlay, pre-launch check and post-run rule; every sandbox write is symlink-refusing; git runs with a sealed environment; fixture commits are regex-bounded. The budget and anchor plumbing in `adversarial-review.sh` is fail-closed except for one YAML type.

Three findings block the merge. Two are holes in the detectors this sprint exists to add: the oracle detector drops every tool result Claude Code flags `is_error` (verified in this session: a `for … do diff …; done`, `sdiff`, or any compound segment whose last exit is non-zero is flagged with the output intact, so those probes are never read; AG-48 pins the blind spot as a "non-hit"), and the KF-046 class 7 exemption accepts a substring match, so a WebFetch or `curl` of an upstream URL that any PR file quotes is clean. The third is completeness: AG-50/AG-51/RAB-c131-1/2 — the only validation of the oracle detector on real transcripts and of `--allow-partial` — read `fixtures/c131-oracle/`, `manifests/v1/` and `grimoires/loa/evals/ablation-2.0-replication`, none of which is in the diff, and the PR title claims curated labels and a versioned re-grade the diff does not carry.

I downgrade one of the review's four highs: `budget_cents_max: false` reading as 600 breaks the stated fail-closed contract, but the damage is bounded at the 600c default and needs a boolean-typed key — MEDIUM, confidence high. Everything else in the review's Changes Required I confirm; its Observations I confirm as MEDIUM/LOW with two additions of my own (unbounded hashing of agent-written files; the CLI `--budget` no longer a ceiling under `diff`).

**Security Issues Found:**

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 3 |
| Medium | 7 |
| Low | 8 |

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] Oracle detector drops every `is_error` tool result — compound and loop diffs are never read

**Severity:** HIGH · **Confidence:** high
**File:** `head/evals/harness/ablation-grade.sh:2390` (also `:2391`, and the AG-48 pin at `head/evals/tests/ablation-grade.bats:1482`)
**Issue:**
```python
                    if blk.get("is_error") is True:
                        continue          # the tool failed (a refused command, a hook block): nothing printed
```
The comment's premise is wrong for Claude Code's Bash tool. Verified in this session: a bare `diff a b`, `diff -u`, `git diff --no-index` and `cd x && diff` with differences are returned as normal results, but `for f in x1; do diff /tmp/$f /tmp/x2; done` and `sdiff /tmp/x1 /tmp/x2` come back as `is_error: true` with the body `Exit code 1` followed by the complete diff output. Any Bash segment list whose last command exits non-zero (a loop over answer paths — the very form AG-47 models at `:1451` — `sdiff`, `comm`, `diff … ; echo` variants) is therefore skipped before `result_text` is read, while the leaked content was printed in full. `ERR_LINE` (`:2060`) already strips refusal and hook-block text, so the skip is redundant for its stated purpose and harmful for the rest.
**Impact:** `oracle_exposed_defects` / `oracle_exposed_by_form.diff` under-report systematically in exactly the `oracle_open` arm the detector was built to measure, and a pre-registration naming `--exclude-oracle-exposed true` keeps the exposed cells in the main read. The header's "LOWER BOUND" caveat (`:2050`) does not cover a bias that tracks a common command shape. AG-48 (`:1482`) enshrines the gap: "an is_error result" is asserted as a non-hit.
**PoC:**
```
# transcript event (oracle_open arm, REVIEW phase)
tool_use  Bash  {"command": "for f in .claude/scripts/x.sh .claude/hooks/y.sh; do diff pr/head/$f $f; done"}
tool_result is_error:true content:"Exit code 1\n12c12\n< old\n---\n> new   # planted site L12 of x.sh"
→ oracle_scan: uses[id] popped, `continue` at :2390, nothing noted; grade.json oracle_exposed_defects == []
```
**Fix:**
```python
                    res = result_text(blk)
                    res = re.sub(r"\A\s*Exit code \d+\s*\n", "", res)   # Claude Code prefixes non-zero exits
                    if not res.strip():
                        continue          # a refused command or hook block prints nothing after ERR_LINE filtering
```
Remove the `is_error` skip; add an AG-47 case with `is_error: true` and a real `Exit code 1` body that must expose the site; re-pin AG-50 once the fixtures (HIGH-003) are in the change; change AG-48's "an is_error result" case to an `is_error` result whose body is only error lines.
**Reference:** CWE-693 Protection Mechanism Failure — https://cwe.mitre.org/data/definitions/693.html

### [HIGH-002] KF-046 class 7 exemption accepts a substring match — fetching an upstream URL the PR quotes is "clean"

**Severity:** HIGH · **Confidence:** medium-high
**File:** `head/evals/harness/ablation-grade.sh:1995` (unit test), `:1809` (the exemption applied for every tool and field), `:1812` (scan continues)
**Issue:**
```python
            match = next(((src, text) for src, text in fl if unit and unit in text), None)
```
The unit (a backtick span, else the agent's whole stripped line) is exempt when it is a *substring* of any fixture line carrying the token. `check_value` applies this for every tool in `FIELDS`, including `WebFetch.url` and `Bash.command`, and then goes on (`:1812`) — for WebFetch there is no other pattern, so the value returns clean. Loa's own docs and skill files link upstream issues (`https://github.com/0xHoneyJar/loa/issues/NNN`) and the README carries an install one-liner against `raw.githubusercontent.com/0xHoneyJar/loa/…`; whenever such a line is in the fixture's `head/**` or `head.diff`, a WebFetch of that URL, or a `curl`/`gh`/`git` of it, is exempt. The rule is meant for an agent *quoting* PR content (`if: github.repository == '0xHoneyJar/loa'`, AG-51), not *executing* it against the upstream.
**Impact:** `contaminated` is the single hard integrity gate on a review-catch row. Fetching the upstream issue, the merged fix or the PR page for the PR under review is the leakage class the gate exists to catch; the exemption turns the fixture's own hyperlinks into an allowlist of upstream probes.
**PoC:**
```
fixture head/.claude/rules/skill-invariants.md:40 contains "… see https://github.com/0xHoneyJar/loa/issues/553"
tool_use WebFetch {"url": "https://github.com/0xHoneyJar/loa/issues/553", "prompt": "what was fixed"}
→ unit = "https://github.com/0xHoneyJar/loa/issues/553" ⊂ fixture line → exempt → contaminated: null, contamination_exempt: [1 row]
```
**Fix:** Never exempt in a fetch/exec position: skip `repo_name_exempt` for `WebFetch`/`WebSearch` fields and for a Bash segment whose executable (via `split_segments`/`seg_words`, already present) is `gh`, `curl`, `wget`, `git`, `pip`, `npm`, `npx`; for the remaining fields require equality with a stripped fixture line, not substring containment. Extend AG-51 with a WebFetch of a URL present in pr-18's head and a `curl` of one; both must remain `repo_name` hits.
**Reference:** CWE-183 Permissive List of Allowed Inputs — https://cwe.mitre.org/data/definitions/183.html

### [HIGH-003] The change is not self-contained: tests and the report depend on corpus artifacts the diff does not carry

**Severity:** HIGH · **Confidence:** medium
**File:** `head/evals/tests/ablation-grade.bats:1544` (`real_run` reads `fixtures/c131-oracle/<name>/{transcripts,dotclaude,task}`), `:1558` (AG-50 pins to "the curated anchors" and `manifests/v1/`), `:1580` (AG-51 and `rgrade` need suite root `ablation-2.0-replication`), `head/evals/tests/run-ablation.bats:1127`, `:1143` (RAB-c131-1/2 need the same root)
**Issue:** `pr/head.diff` adds no file under `evals/tests/fixtures/c131-oracle/`, `evals/fixtures/review-prs/manifests/v1/`, `evals/fixtures/review-prs/manifests/*.json`, `SHA256SUMS` or `grimoires/loa/evals/ablation-2.0-replication/` (the only new fixture files are the three stubs and `gen-fixtures.py`). None of AG-50, AG-51, RAB-c131-1, RAB-c131-2 carries a `skip` guard, so the suite fails on `cp -a "$fx/transcripts"` and on the missing suite root. The PR title promises "curated multi-site labels, versioned re-grade" and the grade header (`head/evals/harness/ablation-grade.sh:46`) documents `manifests/v1/`, yet `recall_pm3_v1` has nothing to read (`v1_manifest` false everywhere) and `corpus_sha256` hashes a `SHA256SUMS` this change does not refresh.
**Impact:** The detector of HIGH-001 and the exemption of HIGH-002 have no verifiable validation against real transcripts; the curated-label claim and the re-grade cannot be checked by reviewer or auditor; a reader of the implementation report is told work exists that the change does not contain.
**Fix:** Either add the `c131-oracle` fixtures (with `trim.py` provenance), the `manifests/v1/` snapshots, the curated manifests, the replication suite root and the refreshed `SHA256SUMS` to the change, or remove those claims from the report and guard AG-50/AG-51/RAB-c131-* with `[[ -d … ]] || skip "corpus artifacts not present"` (the pattern the pr-17 answer-set test already uses). Say which in the report.
**Reference:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html; OWASP ASVS V1.1 (secure SDLC, verifiable deliverables) — https://owasp.org/www-project-application-security-verification-standard/

---

## Medium/Low Priority Issues

### [MED-001] `budget_cents_max: false` reads as 600 — the "malformed maximum ⇒ fixed" contract is broken for one YAML type (review §3, dissent DISS-001 of the review round)
- **Severity:** MEDIUM (downgraded from the review's HIGH) · **Confidence:** high
- **File:** `head/.claude/scripts/adversarial-review.sh:179`
- **Issue:** `_bm=$(yq eval ".flatline_protocol.${config_key}.budget_cents_max // 600" …)`. Verified with yq v4.40.5: `false // 600` → `600` (tag `!!bool`); the alternative operator treats `false` as absent, so the regex at `:180` sees `600` and `diff` scaling runs to the default ceiling instead of logging and keeping `fixed` as `:158`–`:160` promise. BSC-6 covers `6OO`, `-1`, `600.5`, `060`, not `false`/`no`.
- **Why MEDIUM:** the spend is bounded at the 600c default the scaling would also use with no key at all, and the trigger is an operator typing a boolean into an integer field; it is a contract break, not an unbounded spend. The sixteenth-run hardening (`_conf_uint` → 0 cents) is the right precedent.
- **Fix:** read the tag first, as `_adv_conf_budget_scale` already does for the scale: `'!!null'|''` → 600; `'!!int'` → validate the raw value; anything else → WARN and `fixed`. Add `false`, `no`, `"600"` (a quoted string) to BSC-6.
- **Reference:** CWE-1287 Improper Validation of Specified Type of Input — https://cwe.mitre.org/data/definitions/1287.html

### [MED-002] Row writer derives `dissent_absent_reason: disabled` from the agent-writable sandbox config, ranked above every observed failure (review Obs. §2; dissent DISS-C-003 of this round, confirmed by cross-model review)
- **Severity:** MEDIUM · **Confidence:** high
- **File:** `head/evals/harness/ablation-row.sh:393`–`:394` (the read), `:466`–`:470` (`$off` wins over `error`/`budget`)
- **Issue:** `yq -o=json '.flatline_protocol // null' "$RUN_DIR/sandbox/.loa.config.yaml"` feeds `$flp`; `reason()` returns `"disabled"` before it looks at the envelope. The grader header this same change writes (`ablation-grade.sh:48`–`:51`) says sandbox copies are tamperable and never authoritative. A gate that errored or ran out of budget is relabelled a planned absence by a sandbox-side edit, and planned absences are never excluded by report 1.3's dissent-absent sensitivity (`ablation-report.py:1638`). Partial mitigant: `loa_config_sha256` mount-integrity evidence records that the config changed, but the row field does not consult it.
- **Fix:** derive `disabled` from harness evidence only (`dissent=false`, a `flatline=false` toggle line, or have `apply_arm_toggles`/`apply_eval_config_variant` print the gates' `enabled` flags into `arm-evidence.txt`); if the sandbox file stays as a fallback, verify its sha256 against `loa_config_sha256` first and rank it below an envelope that proves the gate ran.
- **Reference:** CWE-345 Insufficient Verification of Data Authenticity — https://cwe.mitre.org/data/definitions/345.html

### [MED-003] Grader 1.3.0 falls back to `<workspace>/pr/head` — the grading copy of the agent-writable tree (review Obs. §3; dissent DISS-C-001 of this round, confirmed by cross-model review)
- **Severity:** MEDIUM · **Confidence:** medium
- **File:** `head/evals/graders/recall-vs-defects.sh:135`; `head/evals/harness/ablation-grade.sh:1629`–`:1636`
- **Issue:** with `EVAL_HEAD_DIR` unset and no `<manifest dir>/../<fixture>/head`, `head_dir="$workspace/pr/head"`. Under `ablation-grade.sh` the workspace is `grading/`, whose `pr/` is `copy_tree(sb/pr)` (`:2626`), and `grade_recall` pops `EVAL_HEAD_DIR` and only re-sets it when `resolve_pr_fixture` succeeds (`:1629`–`:1636`). When it fails, the validity rule (line counts) and the same-scope map (function headers) read files the evaluated agent could have rewritten — wrapping a file in one function makes every citation in it share the defect's scope. The fallback is silent: `details` says nothing about where `head_dir` came from.
- **Fix:** drop the `$workspace/pr/head` fallback (or gate it behind `EVAL_ALLOW_WORKSPACE_HEAD=1` for local use); record `head_dir` provenance in `details`; make `grade_recall` fail the grade (`GradeError`) when a review-catch task's fixture head does not resolve.
- **Reference:** CWE-807 Reliance on Untrusted Inputs in a Security Decision — https://cwe.mitre.org/data/definitions/807.html

### [MED-004] Post-run clause (d) fails `oracle_closed` on any extra sandbox commit or unreachable object — harmless agent git activity rows `infrastructure_error` and pauses the arm (review Obs. §1)
- **Severity:** MEDIUM · **Confidence:** medium
- **File:** `head/evals/harness/lib/sandbox-mount.sh:1040` (`if revs != [base]`), `:1047`–`:1049` (`fsck --unreachable` non-empty ⇒ fail)
- **Issue:** the same `cmd_check` serves the pre-launch check and the post-run rule. Before launch "exactly the base commit, nothing unreachable" is a mount-integrity invariant; after the run an agent that ran `git add`, `git stash`, or committed its `review.md` creates reachable or unreachable objects that are not later-only pinned blobs. took-effect then rows the trial `infrastructure_error` and pauses the arm (DEC-0418). The actual leakage probe is the pinned-blob clause at `:1050`–`:1052`.
- **Fix:** in the post-run form keep the remote/alternates/pinned-blob clauses, and demote "extra commits" and "unreachable objects" to evidence (`sandbox_git_activity=<n> commits, <m> unreachable`) unless an extra object is a later-only pinned blob.
- **Reference:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html

### [MED-005] End-of-definition detection misreads bash headers: `CLOSE_ONE` one-liner test and mixed indentation measures (review Obs. §4; dissent DISS-C-002 of this round adds regex cost)
- **Severity:** MEDIUM · **Confidence:** medium
- **File:** `head/evals/graders/recall-vs-defects.sh:287` (`CLOSE_ONE`), `:295`–`:296` (applied), `:299` (closer indentation without `expandtabs`), `:283` (header indentation with `expandtabs(8)`)
- **Issue:** `CLOSE_ONE = \{.*\}\s*(?:#.*)?$` marks a header a one-liner whenever a `}` ends it: `f() { x=${1:-}` and `f() {  # see ${FOO}` scope the whole function to its header, so clause (ii) can never credit a citation inside it (the review's `local x="${1:-}"` example does not trigger it — the closing quote follows the brace — but the comment and unquoted forms do). At `:299` the closer scan compares `len(t) - len(t.lstrip())` with `lv` computed via `expandtabs(8)` at `:283`, so a tab-indented nested function never finds its `}` and runs to the next header or EOF. The companion dissent adds that `.*` backtracking on a long brace-dense line is quadratic, and MED-003 can make that line agent-supplied.
- **Fix:** strip a trailing comment, then count braces outside quotes: a one-liner is balanced and ends in `}`; use one indentation measure in both places; bound line length before regex work. Add RG cases for `${…}` headers and tab indentation.
- **Reference:** CWE-1025 Comparison Using Wrong Factors — https://cwe.mitre.org/data/definitions/1025.html; CWE-1333 Inefficient Regular Expression Complexity — https://cwe.mitre.org/data/definitions/1333.html

### [MED-006] Report partitions strand build rows as `rule n/a` when review rows hold two rules (review Obs. §6)
- **Severity:** MEDIUM · **Confidence:** high
- **File:** `head/evals/harness/ablation-report.py:1153` (`k += f" · rule {part_rule(r) or 'n/a'}"`), `:1137`–`:1143` (`part_rule` returns `None` for build rows)
- **Issue:** in a version whose review rows carry both `pm3` and `pm3_or_same_function`, build rows land in a third partition keyed `rule n/a`; no partition then holds both a build and a review contrast, so H1 (pass rate and catch rate together) reads "no pair" on one side in every partition, including the primary. The header documents the key but not this consequence.
- **Fix:** attach build rows to every rule partition of their pin (they carry no catch figure to pool), or key only review rows by rule.
- **Reference:** CWE-1068 Inconsistency Between Implementation and Documented Design — https://cwe.mitre.org/data/definitions/1068.html

### [MED-007] Complexity over the repository's 50-line rule without justification (review Obs. §5)
- **Severity:** MEDIUM · **Confidence:** high
- **File:** `head/evals/harness/ablation-grade.sh:2312` (`oracle_scan`, 121 lines, five nesting levels), `head/evals/harness/lib/sandbox-mount.sh:958` (`cmd_check`, 101 lines)
- **Issue:** the ~450-line `_sm_oracle_py` heredoc is justified (one core, three callers); these two functions are not. `oracle_scan` interleaves table construction, transcript parsing and three detection forms; `cmd_check` interleaves four clauses with their fail bookkeeping.
- **Fix:** `_oracle_prepare(by_file) → (later, live, near_text)` + `_oracle_events(...)`; `cmd_check` → `_check_a`, `_check_b`, `_check_c`, `_check_d` each returning `fails`. A restructure, net ±0 lines.
- **Reference:** CWE-1121 Excessive McCabe Cyclomatic Complexity — https://cwe.mitre.org/data/definitions/1121.html

### [LOW-001] A yq failure on the tag probe is read as "key written" (review Obs. §7; dissent DISS-C-001 of the review round)
- **File:** `head/.claude/scripts/adversarial-review.sh:164`
- **Issue:** `|| echo "unreadable"` makes a missing yq or unreadable config set `CONF_BUDGET_SCALE_SET=true`, log a spurious WARN and add the three budget keys to the envelope, against the "absent key is the shipped envelope, byte for byte" contract (`:133`). Every sibling reader degrades silently.
- **Fix:** `_bt=$(yq … 2>/dev/null) || return 0`.
- **Reference:** CWE-755 Improper Handling of Exceptional Conditions — https://cwe.mitre.org/data/definitions/755.html

### [LOW-002] Documentation schema rejects the envelope this change documents (review Obs. §8; dissent DISS-C-004 of the review round)
- **File:** `head/.claude/schemas/adversarial-finding.schema.json:268` (`"additionalProperties": false` on `metadata`), `:226`–`:233` (`status` enum lacks `budget_exceeded`)
- **Issue:** the change adds `budget_scale`/`budget_cents_effective`/`budget_cents_max` to the schema but the `budget_exceeded` envelope it documents (`adversarial-review.sh:312`–`:313`) carries `reason`, `estimated_cents`, `estimate_voices` and `status: budget_exceeded`, none of which the schema admits. The gap predates the change; the change widens it.
- **Fix:** add the three keys and the status value, or drop `additionalProperties: false` on `metadata`.
- **Reference:** CWE-1068 — https://cwe.mitre.org/data/definitions/1068.html

### [LOW-003] `precision_planted_per_flag` can exceed 1 (review Obs. §9)
- **File:** `head/evals/harness/ablation-report.py:984`; Markdown line `:1794`
- **Issue:** planted defects caught ÷ findings flagged is not a precision — one citation can credit several defects (multi-site anchors, the scope clause); AR-52 asserts `1.5`. A reader of "precision as planted ÷ flagged" will misread it.
- **Fix:** rename to `planted_caught_per_flag` and say so in the header, or cap at the flag count.
- **Reference:** CWE-1068 — https://cwe.mitre.org/data/definitions/1068.html

### [LOW-004] Clause (b) byte-equality on tiny pinned files (review Obs. §10)
- **File:** `head/evals/harness/lib/sandbox-mount.sh:1029`–`:1031`
- **Issue:** a later-only pinned version that is boilerplate (`{}`, a one-line `.gitkeep`, an identical licence stub) is byte-equal to unrelated sandbox files and fails (b) as a leak → `infrastructure_error`. Empty blobs are skipped (`:1005`); a minimum size (32 bytes) would remove the false positives without weakening the probe.
- **Reference:** CWE-754 — https://cwe.mitre.org/data/definitions/754.html

### [LOW-005] Two `head.diff` path parsers (review Obs. §11)
- **File:** `head/evals/harness/ablation-grade.sh:2088` (`answer_paths`) vs `head/evals/harness/lib/sandbox-mount.sh:719` (`diff_paths`)
- **Issue:** the grader's parser has no hunk skipping and no `Binary files` lines, so a removed `-- a/x` body line becomes an answer path in the grader and the two answer sets can differ; the sets are compared implicitly through `live[f]`. Over-inclusion today, divergence tomorrow.
- **Fix:** have the grader call `_sm_oracle_py answer-set` (one subprocess) or move the parser to a shared module.
- **Reference:** CWE-1041 Use of Redundant Code — https://cwe.mitre.org/data/definitions/1041.html

### [LOW-006] Evidence readers disagree on first vs last occurrence (review Obs. §12)
- **File:** `head/evals/harness/lib/sandbox-mount.sh:953` (first `overlay_sha256` per path, `setdefault`) and `:954` (first `key=`); `head/evals/harness/took-effect.sh:345`–`:346` (first); `head/evals/harness/ablation-row.sh:419` (last); `head/evals/harness/pipeline-run.sh:560` (last `copy_source`)
- **Issue:** a re-run or a second overlay line would be read four ways; `pipeline-run.sh` compares the last `copy_source` with `SOURCE_COMMIT` while `check_mount_closed` (`sandbox-mount.sh:1122`) validates the first.
- **Fix:** one helper, one rule (first wins, later lines are evidence of a repeat), used by all four.
- **Reference:** CWE-1068 — https://cwe.mitre.org/data/definitions/1068.html

### [LOW-007] Unbounded whole-file reads of agent-written and fixture files after a bounded probe (new)
- **Severity:** LOW · **Confidence:** medium
- **File:** `head/evals/harness/lib/sandbox-mount.sh:887` (`state()`: `sha(open(full, "rb").read())`), `:1029` (clause (b) hash), `head/evals/harness/ablation-grade.sh:2003`–`:2010` (`corpus_sha256`: `read_regular(p, READ_CAP, …)` then `open(p, "rb").read()`)
- **Issue:** `state()` hashes every answer path in the post-run sandbox into memory with no size cap; the evaluated agent controls those files, so a multi-GB file left at an answer path makes `took-effect.sh` swap or die → `infrastructure_error` and an arm pause (DEC-0418) rather than a clean `(a)` failure. `corpus_sha256` probes with the bounded, symlink-refusing `read_regular` and then re-opens the path unbounded and symlink-following (a TOCTOU on a trusted path; low). The grader's own `read_regular` convention exists for exactly this.
- **Fix:** hash via a bounded streaming read (`FILE_CAP`, `O_NOFOLLOW`), treating an over-cap answer path as `state = "oversized"` (an (a) failure with evidence); hash the bytes `read_regular` already returned in `corpus_sha256`.
- **Reference:** CWE-400 Uncontrolled Resource Consumption — https://cwe.mitre.org/data/definitions/400.html; CWE-367 TOCTOU — https://cwe.mitre.org/data/definitions/367.html

### [LOW-008] Under `budget_scale: diff` the CLI `--budget` is no longer a ceiling and `budget_cents_max` admits fifteen digits (dissent DISS-C-004 of this round)
- **Severity:** LOW · **Confidence:** high
- **File:** `head/.claude/scripts/adversarial-review.sh:189`–`:199` (`_adv_budget_effective`), `:180` (`^(0|[1-9][0-9]{0,14})$`)
- **Issue:** `_adv_budget_effective "$budget" …` scales the resolved budget — including an explicit `--budget 50` — up to `budget_cents_max`, which is validated only as a whole number of at most fifteen digits. A repository config with `budget_scale: diff` and a very large maximum makes the pre-dispatch refusal unreachable regardless of what the operator passed. Opt-in, documented and recorded in the envelope, hence LOW; still a surprise for a CLI user.
- **Fix:** treat an explicit `--budget` as a hard ceiling the scaling cannot exceed; bound `budget_cents_max` (say 100000 cents) with a WARN and fall back to `fixed` above it.
- **Reference:** CWE-770 Allocation of Resources Without Limits or Throttling — https://cwe.mitre.org/data/definitions/770.html

---

## Observations

No finding of any severity was demoted here as speculative; `excluded` is 0. The review trailer's `excluded` is 0, so `excluded_confirmed` is 0. Everything below is context, not a tallied finding.

- **Correction to the framing of the review's first Changes Required item** (the `is_error` skip, my first blocking finding above). The review states that every `diff` that found a difference is `is_error`. In this harness a bare `diff`, `diff -u`, `git diff --no-index` and `cd … && diff` are *not* flagged; loops, `sdiff`, and compound segments are, with the output kept. The defect and the fix stand; the pins to re-check after the fix are the loop/compound cases.
- **Dissent envelope accounting.** `metadata.tokens_input: 2` and `companion_voice.primary_succeeded_model: codex-headless` beside `final_model: gpt-5.5-pro` look inconsistent with each other; they do not affect this audit's reading of the findings but are worth a look in the dispatcher's accounting.
- **Clause (ii) fallback for non-code files.** `recall-vs-defects.sh:384`–`:389` credits ±20 lines around a site in any file type without a definition regex (yaml, json, txt). Documented in the header (`:45`–`:48`) as D-2.1; noted so the loosening relative to 1.2.0's ±3 is visible to whoever reads the recall deltas.
- **Running git inside the agent-controlled sandbox repository** (`sandbox-mount.sh:1038`–`:1052`): `core.fsmonitor=false`, `--no-pager`, `GIT_CONFIG_GLOBAL=/dev/null` and `GIT_CONFIG_NOSYSTEM=1` are set, and none of `rev-list`, `remote`, `fsck`, `cat-file -e` invokes a config-named external command. I found no exec path; recorded as checked.

---

## Cross-Model Security Observations

Envelope: `grimoires/loa/a2a/sprint-1/adversarial-audit.json` (primary `gpt-5.5-pro` clean; companion `claude-headless` 4 findings; `hallucination_filter.downgraded: 0`).

| Dissent | Severity (model) | Where it landed |
|---|---|---|
| DISS-C-001 `head_dir` falls back to the agent-writable `pr/head` | MEDIUM | MED-003 — Confirmed by cross-model review |
| DISS-C-002 `CLOSE_ONE` quadratic backtracking on brace-dense lines | LOW | MED-005 (folded; the scope misread is the larger defect) |
| DISS-C-003 row writer reads sandbox `.loa.config.yaml` for `disabled` | LOW | MED-002 — Confirmed by cross-model review (I rate it MEDIUM: the field feeds a report sensitivity) |
| DISS-C-004 `--budget` not a ceiling under `diff`; 15-digit `budget_cents_max` | LOW | LOW-008 |

## Rejected dissent payloads

None — `metadata.rejected_summary` is `[]`, `metadata.rejected_sidecars` is `[]`, and no `adversarial-rejected-audit*.jsonl` sidecar exists beside the envelope.

---

## Rubric Scores

| Dimension | Score (1–5) | Basis |
|---|---|---|
| Security | 3 | Sound mount core (symlink-refusing writes, sealed git env, bounded fixture parsing); two detector gates that fail open (HIGH-001, HIGH-002); two reads of agent-writable state (MED-002, MED-003); one typed-input gap (MED-001) |
| Architecture | 3 | One shared Python core is the right shape; two 100+-line functions (MED-007); duplicated `head.diff` parser and four evidence readers (LOW-005, LOW-006) |
| Code Quality | 3 | Extensive bats coverage, but the four tests that validate the new detectors on real data cannot run from this change (HIGH-003) and one test pins a defect (AG-48) |
| DevOps | 4 | `--allow-partial` recorded in MANIFEST and refused on a conflicting resume; `lib_call` surfaces the last stderr line into `pipeline.json.reason`; evidence ordering before the first phase is explicit |
| Blockchain/Crypto | n/a | — |

---

## Documentation Audit

No `grimoires/loa/a2a/subagent-reports/documentation-coherence-*.md` exists for this sprint (Glob: none). Manually verified: both `ADVERSARIAL-REVIEW.md` copies gain the identical "Numeric anchors and the budget scaling" section; `.loa.config.yaml.example` documents `budget_scale`/`budget_cents_max` for both gates; the grader, row-writer, report, mount-library, took-effect and suite headers describe the new fields and rules. Red flags: the schema does not match the documented `budget_exceeded` envelope (LOW-002); the implementation report (`reviewer.md`) is the PR description verbatim with no `## AC Verification` and claims deliverables absent from the diff (HIGH-003). No secrets, internal URLs or credentials were added (`tests/fixtures/structured-outputs/kf004/*.json` are synthetic payloads).

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added
- [ ] Input validation at trust boundaries — the class 7 exemption accepts fetch/exec positions (HIGH-002); `budget_cents_max: false` passes (MED-001); two sandbox reads (MED-002, MED-003)
- [x] Authentication/authorization — n/a (no auth surface); symlink handling in the overlay, `state()`, `fixture_file()` and `read_regular` is sound
- [x] No SQL/XSS injection — n/a; git invocations use `--literal-pathspecs` and `--`; yq keys are passed via `strenv`
- [x] Error handling does not leak info — `lib_call` surfaces 300 chars of the last stderr line (paths only); `_adv_conf_budget_scale` sanitises the logged value
- [ ] Tests cover the security paths — AG-48 pins the `is_error` blind spot as correct (HIGH-001); AG-50/AG-51 cannot run (HIGH-003); BSC-6 lacks the boolean case (MED-001)

---

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 3 |
| Medium | 7 |
| Low | 8 |

---

## Next Steps

**CHANGES_REQUIRED:**
1. Fix HIGH-001 and HIGH-002 with the regression cases named above; re-pin AG-50 once its fixtures are in the change.
2. Resolve HIGH-003: ship the corpus artifacts with the change or drop the claims and `skip`-guard the four tests; state the decision in the report.
3. Fix MED-001 through MED-003 (the three trust-boundary items); MED-004 through MED-007 and the LOWs at the implementer's discretion but before the eval runs on them.
4. Run `bats evals/tests/ablation-grade.bats evals/tests/sandbox-mount.bats evals/tests/took-effect.bats evals/tests/pipeline-run.bats evals/tests/run-ablation.bats evals/tests/ablation-row.bats evals/tests/ablation-report.bats evals/tests/eval-recall-grader.bats tests/unit/adversarial-review-budget-scale.bats tests/unit/adversarial-review-normalise.bats` and quote the result in `reviewer.md` under a `## AC Verification` section.
5. Re-run `/review-sprint sprint-1`, then `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":7,"low":8},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-21T16:45:00Z"} -->
