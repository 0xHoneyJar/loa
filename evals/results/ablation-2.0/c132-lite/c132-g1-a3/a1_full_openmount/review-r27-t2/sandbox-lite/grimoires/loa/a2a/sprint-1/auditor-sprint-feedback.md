# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Change under audit:** `pr/head.diff` — feat(cycle-131): sprint-263 — closed review-catch mount, grader 1.3.0 with three results and an oracle detector, dissent line anchors + budget_scale, curated multi-site labels, versioned re-grade (35 files)

---

## Verdict: CHANGES_REQUIRED

---

## Pre-flight and scope

- Phase 0 prerequisite: `engineer-feedback.md` says CHANGES REQUIRED, not "All good". The task instruction orders this audit to run regardless; the deviation is recorded here and in NOTES.md. The review's `adversarial-review.json` carries `metadata.model` (gpt-5.5-pro), so the review's own dissent gate is satisfied.
- Guardrails pre-check: `guardrails-orchestrator.sh --skill auditing-security` returned PROCEED.
- `known-failures.md` is absent from this workspace (hook warning); triaged without it.
- Scope: the 35 files of `pr/head.diff` (Loa framework scripts, eval harness, tests, docs). `security-audit-scope.sh` scans the live tree only, so Phase 0.5 was done by hand: the sources are the agent-writable sandbox (`sandbox/**`, `sandbox/pr/**`, `sandbox/.loa.config.yaml`, the sandbox `.git`) and the dissenter model's JSON; the sinks are the grader's verdict fields (`recall`, `oracle_exposed_*`, `contaminated`, `dissent_absent_reason`), the overlay's filesystem writes, and `git` run inside the sandbox repository.
- Grounding: every finding below was read in the `pr/head/` files; the three grader defects were reproduced by running the head grader (`evals/graders/recall-vs-defects.sh`) on constructed fixtures, and the transcript premise of the oracle finding was checked against a real Claude Code transcript on this host.
- `br` is not installed: no beads sync or audit comment.

---

## Executive Summary

The closed mount is the strongest part of the sprint: one Python core (`_sm_oracle_py`) drives the overlay, the pre-launch check and the post-run rule; sandbox writes refuse symlink components and use `O_NOFOLLOW|O_EXCL`; `git` inside the agent-controlled sandbox repository runs with a scrubbed environment, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`, `--no-pager`, `--literal-pathspecs` and `core.fsmonitor=false`; answer paths are normalised and confined to `.claude/`. The budget-scale parser fails closed and sanitises what it logs; the numeric-anchor filter drops anything that is not a whole line number without opening a repair hop.

The sprint fails the audit on the integrity of its own measurement. Grader 1.3.0's decision statistic (`recall`, the report's `defect_catch_rate`) is computed by regex scope detection that mis-parses the dominant shapes of this repository's `.sh` and `.py` files — a zero-argument method call inside a Python heredoc becomes a bash function header, and a multi-line `def` signature ends a Python function at its second line — and the oracle detector discards every `tool_result` flagged `is_error`, which is exactly how Claude Code records a `diff` that found a difference. All three move the headline numbers silently. Beneath them, two trust-boundary inversions let the agent-writable sandbox steer harness fields the harness header promises never to read (the grader's `pr/head` fallback and the row writer's `dissent_absent_reason`), and two fail-open paths report "nothing exposed" when the detector could not run.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 3 |
| Medium | 6 |
| Low | 11 |

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] Oracle detector drops every `is_error` result, so a differing `diff` is never counted

**Severity:** HIGH (confidence: high)
**File:** `head/evals/harness/ablation-grade.sh:2390`; the behaviour is pinned as correct by `head/evals/tests/ablation-grade.bats:1500` (AG-48 case 9)
**Issue:** `oracle_scan` does `if blk.get("is_error") is True: continue  # the tool failed … nothing printed`. `diff`, `sdiff` and `git diff --no-index` exit 1 exactly when the operands differ, and Claude Code records a non-zero Bash exit as `is_error: true` with the output kept in `content`. Verified on a transcript on this host: `{"is_error": true, "content": "Exit code 1\n.claude/skills/reviewing-code/resources:\nADVERSARIAL-REVIEW.md\n…"}`. The canonical oracle probe `diff pr/head/X X` is therefore invisible to the detector; only a diff whose exit status is neutralised (`| head`, `|| true`, inside a loop) is seen.
**Impact:** `oracle_exposed_defects` / `oracle_exposed_unknown` under-report by construction; the report's "oracle-exposed cells excluded" sensitivity and `--exclude-oracle-exposed true` keep contaminated cells. The detector is documented as a lower bound, but this bound excludes the most likely event.
**Fix:** Treat `is_error` as "nothing printed" only when the content carries no diff body: skip when `content` is empty or every line matches `ERR_LINE` / `^Exit code \d+$`; otherwise strip the `Exit code N` line and parse as today. Flip AG-48 case 9 to expect `diff=d1` and add a Claude Code-shaped case (`Exit code 1\n20c20\n< a\n---\n> b`, `is_error` true). Keep the skip for a hook block or refused command.
**Reference:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html

### [HIGH-002] Grader 1.3.0 reads a zero-argument method call as a bash function header

**Severity:** HIGH (confidence: high)
**File:** `head/evals/graders/recall-vs-defects.sh:210` (`BASH_HDR[0]`), span computation at `:334-337`
**Issue:** `^(\s*)(?:function\s+)?[A-Za-z_][A-Za-z0-9_.:-]*\s*\(\)\s*\{?` admits `.` in the name and makes the brace optional, so `out.pop()`, `conn.close()`, `f.flush()` match as definition headers. `headers()` runs on every line with no heredoc awareness, and this repository's harness scripts embed large Python heredocs (the grader itself has `out.pop()` at `:243`). Reproduced with the head grader: a function `alpha() { python3 - <<PY … out.pop() … PY }` with the site at line 5 and the citation at line 20 → `detected: []` (deflation). The bogus inner header's span is clipped only by a `}` at its own indentation, which a heredoc never has, so it runs past `alpha`'s closing brace to the next header at indentation ≤ 4: a citation at line 20 inside `alpha` credited a top-level site at line 24 after `alpha` (`credits_function_only: ["A2-toplevel"]`, inflation). Dissent DISS-C-001 of the review round described the same inflation.
**Impact:** `recall`, `defects_caught`, `missed` and `credits_function_only` drift from the documented rule without an error in the dominant fixture file type; `recall_pm3*` are unaffected.
**Fix:** Disallow `.` in the function name (`[A-Za-z_][A-Za-z0-9_:-]*`), require `{` on the header line or as the first token of the next non-blank line, and clip every nested span to its enclosing span's end (`min(end, parent_end)`). Add an RG case with a Python heredoc containing `x.pop()` inside a bash function and a top-level site after it.
**Reference:** CWE-20 Improper Input Validation — https://cwe.mitre.org/data/definitions/20.html

### [HIGH-003] Grader 1.3.0 ends a Python function at the continuation line of a multi-line signature

**Severity:** HIGH (confidence: high)
**File:** `head/evals/graders/recall-vs-defects.sh:302-309`
**Issue:** The Python branch of `close_line` returns `last` at the first later non-blank, non-comment line indented no deeper than the `def`. For `def check(\n    value,\n):` the `):` line has indentation 0, so the definition is lines 1–2 and the whole body is top-level (scope `None`). Reproduced with the head grader: site at line 6, citation at line 18 of such a function → `detected: []`; the same body with a one-line signature → `detected: ["B1"]`. A dedented line inside a multi-line string literal ends the span the same way. (Review dissent DISS-001, BLOCKING, verified there and here.)
**Impact:** A citation inside the function body more than 3 lines from the site receives no same-scope credit, lowering `recall` and failing reviews that satisfy the documented rule.
**Fix:** Derive Python spans with `ast` (`FunctionDef.lineno` / `end_lineno`, `tokenize` fallback for files that do not parse), or at least carry the header through balanced parentheses to the line ending in `:` before applying the dedent rule. Add an RG case with a multi-line signature.
**Reference:** CWE-20 Improper Input Validation — https://cwe.mitre.org/data/definitions/20.html

---

## Medium/Low Priority Issues

### [MED-001] `dissent_absent_reason` maps `api_failure` and the other failure statuses to "none"
- **Severity:** MEDIUM (confidence: high)
- **File:** `head/evals/harness/ablation-row.sh:468-479`
- **Issue:** `reason()` recognises `budget_exceeded`, a status containing "preflight", `failed`, and `recorded_by: record-fallback`; everything else is `"none"` ("the dissent ran"). `adversarial-review.sh` writes `status: "api_failure"` directly with no `recorded_by` (`head/.claude/scripts/adversarial-review.sh:1426`, `:4739`), and also `refused`, `ceded`, `fold_failed`, `malformed_response`. Such an envelope rows as `none`, so the "dissent-absent gates excluded" sensitivity keeps exactly the rows it exists to exclude. (Confirmed by cross-model review: the review round's dissent raised the same class.)
- **Fix:** Map every status that is not `reviewed` / `clean` to `error`, and add RW14-3 cases for `api_failure`, `malformed_response`, `refused`, `ceded`, `fold_failed`.

### [MED-002] The "disabled" reason is read from the agent-writable sandbox config
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/harness/ablation-row.sh:393-395` (read), `:465-467` (use)
- **Issue:** `$flp` is `yq -o=json '.flatline_protocol' sandbox/.loa.config.yaml`, parsed after the run. The same file's header calls the sandbox tamperable and names `eval/` as authoritative. An agent that writes `flatline_protocol.code_review.enabled: false` after a failed gate turns an `error` absence into a planned `disabled` one, which the report never excludes; `pipeline.json.mount_integrity` (the config's sha256 at mount and at finish) is not consulted, and the YAML is parsed without a size bound. Confirmed by cross-model review (DISS-C-002, LOW in the dissent; raised here because the field feeds an exclusion rule).
- **Fix:** Derive `disabled` from harness-owned evidence only — `dissent=false` in `meta/arm-evidence.txt`, or a mount-time copy of the config — or honour the sandbox file only when `mount_integrity.loa_config` reports it unchanged. Fail to `error` otherwise.
- **Reference:** CWE-807 Reliance on Untrusted Inputs in a Security Decision — https://cwe.mitre.org/data/definitions/807.html

### [MED-003] Closed-mount clause (d) fails on any sandbox git activity, pausing the arm
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/harness/lib/sandbox-mount.sh:1040` (`revs != [base]`), `:1047` (`fsck --unreachable`)
- **Issue:** `cmd_check` fails `oracle_closed` when `git rev-list --all` is anything but the base commit, or when `fsck --unreachable --no-reflogs` prints anything. A `git commit`, `git stash` (creates `refs/stash`), or `git stash` + `drop` (unreachable commits) by the reviewing agent rows the trial `infrastructure_error` and pauses the whole arm (DEC-0418) although no later blob entered the store. The leakage signal that matters — the later-only pinned blob check at `:1049-1051` — stands on its own.
- **Fix:** Keep "no remote, no alternates, no later-only blob" as fail clauses; require only that `base_commit` is an ancestor of every ref, and report extra commits or unreachable objects as evidence rather than failing the run.

### [MED-004] Markdown heading detection has no fence awareness
- **Severity:** MEDIUM (confidence: high)
- **File:** `head/evals/graders/recall-vs-defects.sh:214` (`MD_HDR`)
- **Issue:** `^(#{1,6})(?:\s|$)` matches `# comment` lines inside fenced ```` ``` ```` bash blocks, which are common in `.claude/**/*.md`. Reproduced: a site at line 3 and a citation at line 13 of the same `## Section`, separated by a fence holding `# a comment inside fence` → `detected: []`; the same file without the comment → detected. The heading hierarchy below the fence is reset as well.
- **Fix:** Skip lines between fences in `headers()` for markdown; add an RG case.

### [MED-005] The grader's head-directory fallback is the agent-writable `$workspace/pr/head`
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/graders/recall-vs-defects.sh:135`; reached from `head/evals/harness/ablation-grade.sh:1629-1635` (`EVAL_HEAD_DIR` is popped and set only when `resolve_pr_fixture` succeeds; a `GradeError` is swallowed)
- **Issue:** When `EVAL_HEAD_DIR` is unset and `<manifest dir>/../<fixture>/head` does not exist, the grader reads the sandbox copy of `pr/head` for the validity rule (file length) and the scope map. Reproduced with the head grader: a `pr/head/x/scripts/c.sh` rewritten as one unclosed function, site at line 3, citation at line 29 → `detected: ["C1"]`; with `EVAL_HEAD_DIR` pointing at an immutable directory → `detected: []`. The harness header (`ablation-grade.sh:46-49`) promises the grader never reads the sandbox `pr/`. Confirmed by cross-model review (DISS-C-001, MEDIUM, which shows the same inflation vector); the companion also notes that `CLOSE_ONE`'s `\{.*\}` is quadratic on a header line of many `{` and no `}`, which matters only once the head file is agent-controlled (DISS-C-003).
- **Fix:** In `grade_recall`, raise `GradeError` when the fixture does not resolve instead of letting the grader fall back; in the grader, drop the `$workspace/pr/head` fallback (or keep it only behind an explicit `--allow-sandbox-head` for standalone use) and behave as "no head file" otherwise.
- **Reference:** CWE-807 — https://cwe.mitre.org/data/definitions/807.html

### [MED-006] The oracle detector fails open to "nothing exposed" when the fixture does not resolve
- **Severity:** MEDIUM (confidence: high)
- **File:** `head/evals/harness/ablation-grade.sh:2313-2316`
- **Issue:** `oracle_scan` returns `[], [], [], {"diff": [], "read": []}` on `GradeError`, and `grade()` (`:2626-2628`) stores these as the row's `oracle_exposed_defects` / `oracle_exposed_unknown`. A review-catch run whose fixture could not be found is indistinguishable from a verified-clean run; build tasks get `null`. The same resolution failure drives MED-005, so one missing fixture directory both opens the grader to the sandbox and certifies the run oracle-clean.
- **Fix:** Return `None` for the four fields (as build tasks do) or raise, and make the row writer / report treat `null` on a review-catch row as "not checked" rather than "clean".
- **Reference:** CWE-636 Not Failing Securely — https://cwe.mitre.org/data/definitions/636.html

### [LOW-001] Bash close-brace check ignores tabs
- **File:** `head/evals/graders/recall-vs-defects.sh:299`
- **Issue:** The bash branch compares `len(t) - len(t.lstrip())` with `lv`, but `lv` was computed with `expandtabs(8)` (`:275`), so a tab-indented function never finds its `}`; its span runs to the next header at the same or lower indentation, or to end of file (top-level lines then inherit the function's scope).
- **Fix:** Use `expandtabs(8)` on both sides.

### [LOW-002] `CLOSE_ONE` treats a `}` in a trailing comment as a one-line function
- **File:** `head/evals/graders/recall-vs-defects.sh:287`, used at `:295`
- **Issue:** `\{.*\}\s*(?:#.*)?$` reads `f() {  # see } below` as `f() { …; }`, ending the function on its header. The pattern is also quadratic on a long header line with many `{` and no `}` (cross-model DISS-C-003, LOW).
- **Fix:** Strip the trailing comment before matching and use `\{[^{}]*\}\s*$`.

### [LOW-003] KF-046 class 7: a backticked token is its own exemption unit
- **File:** `head/evals/harness/ablation-grade.sh:1991-1995`
- **Issue:** For a backticked occurrence the unit is the span's content; for `` `0xHoneyJar/loa` `` that is the token itself, a substring of every fixture line holding it. Once the PR fixture mentions the repository anywhere, any Write/Edit/Grep value quoting the name in backticks is exempt regardless of context. AG-51's negative case covers only a fixture without the token.
- **Fix:** When the backtick span is just the token, fall back to the whole line as the unit, or require the unit to be longer than the token.

### [LOW-004] Numeric anchor on an extensionless path loses its file
- **File:** `head/evals/harness/ablation-grade.sh:1570`
- **Issue:** The anchor's path part is used only when it ends in a 1–6 character extension; `Makefile`, `Dockerfile`, `.envrc` or a suffix-less script fall back to the finding's `file`, which dissent findings rarely carry, so the citation is dropped.
- **Fix:** Accept a path part that contains `/` or matches a basename the fixture holds.

### [LOW-005] Under `budget_scale: diff` only `budget_cents_max` is enforced
- **File:** `head/.claude/scripts/adversarial-review.sh:189-199`
- **Issue:** `effective = min(max(conf, ceil(est × 1.2)), max)`; since `ceil(est × 1.2) ≥ est`, the refuse test `est > effective` reduces to `est > budget_cents_max`. `budget_cents`, `--budget` and the 1.2 factor never change the decision, and `budget_cents_effective` is a function of the estimate rather than a limit applied. This matches SDD D-4.2 and BSC-3/BSC-4 pin it, so it is a design observation; the example config and both ADVERSARIAL-REVIEW.md pages present `budget_cents` as a meaningful floor under `diff`. (Cross-model DISS-C-003 of the review round.)
- **Fix:** Document that under `diff` the enforced limit is `budget_cents_max`, or make the ceiling `max(budget_cents, budget_cents_max)`.

### [LOW-006] A yq read failure is reported as a written key
- **File:** `head/.claude/scripts/adversarial-review.sh:164-172`
- **Issue:** When `yq` cannot read the config the tag is `unreadable`, which is neither `!!null` nor empty, so `CONF_BUDGET_SCALE_SET` becomes true and the WARN names the value `(a unreadable, not a string)`; the envelope then carries `budget_scale` metadata for a config that never wrote the key. Reachable only with a malformed YAML file.
- **Fix:** Treat `unreadable` like absent (return early with a WARN).

### [LOW-007] The envelope schema does not admit the `budget_exceeded` envelope the gate writes
- **File:** `head/.claude/schemas/adversarial-finding.schema.json:226-231` (status enum), `:245-259` (new metadata keys), `:268` (`additionalProperties: false`)
- **Issue:** `metadata.status` lacks `budget_exceeded`, and the closed metadata object declares neither the new `reason` nor the existing `estimated_cents` / `budget_cents` / `estimate_voices`, so the envelope written at `head/.claude/scripts/adversarial-review.sh:4446-4451` violates the documented contract while `ablation-row.sh` keys on that status. Partly pre-existing (the base enum lacked it too); NRM-72 validates only the success-path metadata.
- **Fix:** Add `budget_exceeded` to the enum and the five keys to `$defs.metadata`; validate the refusal envelope in NRM-72.

### [LOW-008] Tests depend on fixtures the PR does not add
- **File:** `head/evals/tests/ablation-grade.bats:1544` (AG-50 reads `evals/tests/fixtures/c131-oracle/*`), `head/evals/tests/run-ablation.bats:1127` (RAB-c131-1/2 read `grimoires/loa/evals/ablation-2.0-replication`)
- **Issue:** Neither directory is among the 35 files, and neither exists in this workspace, so AG-50, AG-51 and RAB-c131-1/2 cannot run from the PR alone; the sprint's detector validation pins (the trimmed cycle-130 transcripts) are therefore unverifiable here.
- **Fix:** Add the fixtures to the PR or `skip` the tests when the directories are absent, naming the dependency.

### [LOW-009] No CHANGELOG entry for four version bumps
- **File:** `head/evals/harness/ablation-grade.sh:349` (`GRADER_VERSION = "1.3.0"`); also report 1.3 (`ablation-report.py`), row writer 1.4 (`ablation-row.sh`), grader 1.3.0 (`recall-vs-defects.sh`)
- **Issue:** The diff carries no CHANGELOG entry and `pr/PR.md` is a title only; `grimoires/loa/a2a/subagent-reports/` holds no documentation-coherence report. The in-file headers, the two ADVERSARIAL-REVIEW.md pages and `.loa.config.yaml.example` were updated and read as consistent with the code, so this is a process gap rather than a documentation defect.
- **Fix:** Add the CHANGELOG entry naming the grader rule change (recall is not comparable to 1.2.x grades) and the budget_scale keys.

### [LOW-010] `state()` reads each sandbox answer path unbounded
- **File:** `head/evals/harness/lib/sandbox-mount.sh:873-887`
- **Issue:** `sha(open(full, "rb").read())` on an agent-writable file with no size cap, for every answer path, in both the pre-launch check and the post-run `oracle_closed` rule; clause (b) (`:1023-1036`) filters by size first and the grader uses `FILE_CAP`. A multi-gigabyte replacement stalls or OOMs took-effect, which rows `infrastructure_error` and pauses the arm — the same outcome a mutation already earns, so the impact is the resource use.
- **Fix:** Hash in chunks with a size ceiling and report `oversized` as a non-file state.
- **Reference:** CWE-400 Uncontrolled Resource Consumption — https://cwe.mitre.org/data/definitions/400.html

### [LOW-011] The oracle detector's `live` gate reads the post-run sandbox copy
- **File:** `head/evals/harness/ablation-grade.sh:2330-2336`
- **Issue:** `live[f] = cur is not None and cur != hd and cur != bs` reads `sandbox/<answer path>` after the run; a path whose final sandbox copy equals the fixture's head or base is skipped for every event, and the read form's later-only lines (`later[f]`) come from the same copy. An agent that restores the head version after diffing the later copy (`cp pr/head/X X`) erases its own exposure. Moot under the closed mount (the copy already equals head); matters for the open-mount arm and legacy re-grades, where the rows are reported rather than excluded.
- **Fix:** Derive `live` and the later-only lines from the pinned source version (`git show <source_commit>:X`, as clause (b) does) or from the pre-run `overlay_sha256` evidence, not from the sandbox's final state.
- **Reference:** CWE-807 — https://cwe.mitre.org/data/definitions/807.html

---

## Cross-Model Security Observations

The security dissent ran with two voices: `gpt-5.5-pro` primary (answered by `codex-headless`, status `clean`) and `claude-headless` companion (`counted_as: independent_voice`, `voices_succeeded: 2/2`, `degraded: false`). Envelope: `grimoires/loa/a2a/sprint-1/adversarial-audit.json`. No DEGRADED_SECURITY_REVIEW marker applies.

- DISS-C-001 (MEDIUM, `recall-vs-defects.sh:136`) — the agent-writable `pr/head` fallback with a whole-file-function inflation vector: **Confirmed by cross-model review**, merged into MED-005 and reproduced here.
- DISS-C-002 (LOW, `ablation-row.sh:393-396`) — `dissent_absent_reason` trusts the sandbox config; unbounded yq parse: **Confirmed by cross-model review**, merged into MED-002 (raised to MEDIUM because the field feeds an exclusion rule).
- DISS-C-003 (LOW, `recall-vs-defects.sh:287`) — `CLOSE_ONE` quadratic on a crafted header line: recorded under LOW-002 and MED-005; reachable only through the MED-005 fallback.

## Rejected dissent payloads

None. `metadata.rejected_summary` is empty, `rejected_sidecars` is empty and no `adversarial-rejected-audit*.jsonl` exists beside the envelope.

---

## Notes and accepted risks (not tallied)

- **Gate scripts at PR version.** The closed mount deliberately runs the review-catch PR's own `.claude/scripts/`, `.claude/hooks/` and `SKILL.md` versions inside the sandbox (`gate_scripts_at_pr_version`, DEC-0613/DEC-0622). A planted defect in a safety hook (the corpus's pr-17 touches `block-destructive-bash.sh`) is therefore live during the trial; with `--executor host` it runs on the operator's machine. This is recorded design, and the evidence names the paths; the corpus must stay trusted.
- **`git` in the agent-controlled sandbox repository.** `cmd_check` runs `rev-list`, `remote`, `fsck` and `cat-file` inside a `.git` the agent could have rewritten. The hardening (fresh env, no global or system config, `--no-pager`, `--literal-pathspecs`, `core.fsmonitor=false`, no network commands) covers the known config-driven execution paths for these subcommands; what remains is git's object-parser surface on a hostile repository, which is the operator's accepted risk for an eval of a non-malicious agent.
- **Review demotions.** The review trailer carries `excluded: 0`; there is nothing to confirm or re-tally (`excluded_confirmed: 0`).

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added
- [x] Input validation on new entry points — path normalisation, symlink refusal, bounded reads in the overlay, grader and detector; budget keys validated as whole numbers; log text sanitised
- [x] Authentication required where needed — n/a
- [x] No SQL/XSS injection vulnerabilities — jq `--arg`/`--argjson`, `yq strenv`, no string-built commands
- [x] Error handling doesn't leak info — `lib_call` surfaces 300 characters of library stderr into `pipeline.json`, harness-owned paths only
- [ ] Trust boundary — the grader (MED-005), the row writer (MED-002) and the detector gate (LOW-011) read agent-writable sandbox state; two fail-open paths (MED-006, HIGH-001)
- [ ] Tests cover security paths — AG-48 case 9 pins the wrong `is_error` behaviour; AG-50/RAB-c131 fixtures absent

---

## Rubric Scores

| Dimension | Score | Basis |
|-----------|-------|-------|
| Security — input validation | 4 | overlay/detector/parser hardening; MED-005/MED-002 fallbacks |
| Security — fail-safe defaults | 2 | HIGH-001, MED-006, MED-001 fail open |
| Architecture — modularity | 4 | one Python core for overlay/check/rule; regex scope detection is the weak module |
| Code quality — correctness | 2 | three reproduced grader defects in the decision statistic |
| DevOps — tests | 3 | broad bats coverage; four tests depend on absent fixtures; one pins a defect |

---

## Next Steps

**CHANGES_REQUIRED:**
1. Fix HIGH-001 (treat `is_error` content with a diff body as output; flip AG-48 case 9), HIGH-002 (header regex, brace requirement, nested-span clipping) and HIGH-003 (`ast`-based or paren-aware Python spans), each with the named regression case.
2. Close the trust-boundary and fail-open items: MED-001, MED-002, MED-005, MED-006 (make a missing fixture a `GradeError`, drop the sandbox head fallback, map every non-success dissent status to `error`, read `disabled` from harness evidence).
3. Re-run `evals/tests/eval-recall-grader.bats`, `evals/tests/ablation-grade.bats` AG-45..AG-51 and `evals/tests/ablation-row.bats` RW14-*; add the AG-50 / RAB-c131 fixtures or skip those tests when absent.
4. Request another review via `/review-sprint sprint-1`, then `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":6,"low":11},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-22T00:31:00Z"} -->
