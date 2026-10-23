# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Review Feedback:** grimoires/loa/a2a/sprint-1/engineer-feedback.md (APPROVED; 0 critical, 0 high, 3 medium, 8 low, 0 excluded)
**Change under audit:** `pr/head.diff` — sprint-255 (cycle-129): guard register with origin and yield, pre-registered control arms on a record corpus, task kinds, path-scoped rule files (81 files)

---

## Verdict: APPROVED - LET'S FUCKING GO

---

## Executive Summary

The change adds four surfaces: the guard register and its host yield (`guard-yield.sh`, `guard-origins.yaml`, `floor.yaml`, the generated hooks table), the control-arm harness (`execute-agent.sh` toggles, `run-arms.sh`, `arms-report.py`, `compare-ab.py` control-arm validity, `recall-vs-defects.sh` 1.2.0), the record-corpus seeder (`seed-corpus-from-record.sh`), and the task-kind rule (`validate-artifact.sh`, `cycle-ratio.sh`, templates, rule-file `paths:` frontmatter). I read every shell and Python entry point in the head tree in full and the diff hunks of every other touched file; the untrusted inputs are the audit-log rows, the record-branch feedback files, the model's result stream, and the arm toggles; the sinks are the `source` of an optional library in `guard-yield.sh`, the `git` and `jq`/`yq` invocations, and the files the seeder writes into the committed corpus.

Security posture is sound. Every identifier that reaches a path or a command is regex-validated (guard ids, arm ids, fixture ids, model ids, batch names, commit shas, `--by`), the yield writes no command text, cwd, hostname or model name (GY-5 pins it), untrusted audit rows are only read through `jq` with `try fromjson`, the seeder redacts secret-shaped strings and fails closed on `no-secrets.sh` (SC-2), Python is run with `-I` and a quoted heredoc everywhere, the executor runs `--restricted --tools Read,Grep,Glob,Write` with the operator's GitHub, OpenAI and AWS credentials unset and the parent Claude Code session decoupled, and the floor files are pinned to `origin/main` and by sha256. The fence's registration and call-site lists are unchanged (FS-3, FS-4); the `# @guard` markers are comments only.

No critical or high finding. Three medium findings (robustness and evaluation validity, each confirmed from the review) and twelve low findings follow. None blocks merge.

**DEGRADED_SECURITY_REVIEW.** The cross-model dissent did not run: `adversarial-review.sh --type audit --sprint-id sprint-1 --diff-file pr/head.diff --json` refused before dispatch with `status: budget_exceeded` (estimate 627c over two voices, gpt-5.5-pro 472c and claude-headless 155c, against the `budget_scale: diff` effective cap of 600c). The refusal is recorded by the script itself at `grimoires/loa/a2a/sprint-1/adversarial-audit.json` (`--record-fallback budget_exceeded`, `--since 2026-10-21T09:03:56Z`); it names no model, so the `COMPLETED` marker cannot be written from this envelope and this audit is single-voice. `rejected_summary` is empty and no sidecar exists, so there is no rejected dissent payload to triage. The review's dissent refused on the same estimate.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 3 |
| Low | 12 |

Scope totals (`security-audit-scope.sh --json` from `pr/head`): 5 source files, 4 sink files, 0 auth files, 0 LLM/AI files.

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

None.

---

## Medium/Low Priority Issues

### [MED-001] guard-yield.sh sources an optional library in the main shell

- **Severity:** MEDIUM (confidence: medium) — Confirmed by the review (Observation 1).
- **File:** `head/.claude/scripts/guard-yield.sh:468-470`
- **Issue:** `if source "$HEREDOC_LIB" 2>/dev/null && declare -F heredoc_nonexec >/dev/null; then` runs the library's top level in the script's own process, gated only by `grep -q '^heredoc_nonexec[[:space:]]*()'` at line 468. A library revision that runs to an `exit` instead of only defining functions ends `guard-yield.sh` there under `set -e`: exit 0, no `guards.md`, no `.run/guard-yield.{md,json}`, no summary line. The mount in this workspace reproduces it: the later-cycle `.claude/scripts/lib/heredoc-classifier.sh` sources the fence with `BDB_LIB_ONLY=1`, which this PR's fence does not honour, so the fence's main body runs on an empty stdin and exits 0. At PR head the library does not exist, so the shipped tree is unaffected; `--check` returns before this point, so CI stays green while every host yield vanishes.
- **Impact:** A register whose yield silently produces nothing with exit 0 is the failure the register exists to catch. Not exploitable: the library path is inside `.claude/scripts/lib/`, the System Zone, and `--root` is operator-controlled.
- **Fix:** Probe in a subshell first — `( source "$HEREDOC_LIB" >/dev/null 2>&1 && declare -F heredoc_nonexec >/dev/null )` — and fall back to the `<<` heuristic with a WARN when the probe fails; add a GY case with a stub library whose body calls `exit 0`.
- **Reference:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html

### [MED-002] The constraints.json surface of the karpathy_block toggle is neither checked nor verified

- **Severity:** MEDIUM (confidence: high) — Confirmed by the review (Observation 3).
- **File:** `head/evals/harness/execute-agent.sh:256`
- **Issue:** `jq '(.constraints // []) |= map(select((tostring | test("karpathy"; "i")) | not))' "$cj" > "$cj.tmp" && mv "$cj.tmp" "$cj"` is an `&&` list, so a jq failure (a `constraints.json` whose top level is not an object, or whose `constraints` is not an array) is not caught by `set -e`; the sandbox keeps its Karpathy rows, an empty `constraints.json.tmp` is left beside them, the trial proceeds, and `executor.json` records `arm: no_karpathy` with `arm_evidence` naming only `CLAUDE.loa.md`. The header at lines 63-66 promises every toggle "is verified absent afterwards and a toggle that cannot take effect is exit 2"; the `CLAUDE.loa.md` branch honours it at lines 251-253, this surface does not. AT-5 covers only the well-formed file.
- **Impact:** An arm runs as a partial baseline and is reported as the arm: the invariant the pre-registered comparison rests on.
- **Fix:** Check the jq exit status explicitly, then `jq -e '[.constraints[]? | select(tostring | test("karpathy"; "i"))] | length == 0'` and `return 2` otherwise, as the section branch does.
- **Reference:** CWE-252 Unchecked Return Value — https://cwe.mitre.org/data/definitions/252.html

### [MED-003] Any auxiliary model with output tokens reads as executor skew

- **Severity:** MEDIUM (confidence: medium) — Confirmed by the review (Observation 2); confidence raised from the review's low because the executor's own comment anticipates the input.
- **File:** `head/evals/harness/arms-report.py:144-146` and `head/evals/harness/arms-report.py:280-282`; the same rule in `head/evals/harness/compare-ab.py:71`
- **Issue:** `for mid, out in ((row.get("executor") or {}).get("models_used") or {}).items(): if out: self.models.add(mid)` joins every `modelUsage` key with output tokens into the arm's model set, and `if len(mods) > 1: reasons.append("model skew: …")` makes a set of size two `inconclusive`. `execute-agent.sh:411-413` itself expects "a haiku helper call" in `modelUsage` and picks `model_id` by max output tokens for that reason, and only `CLAUDE_CODE_SUBAGENT_MODEL` is pinned (line 349). If the CLI reports any helper model with output tokens in a normal `-p` run, every non-baseline arm reads `inconclusive` on every batch and the comparison can never conclude; `compare-ab.py` likewise returns exit 2 (invalid) for the same rows. AR-7 and EA-11 test the fallback case only.
- **Impact:** Evaluation validity, not confidentiality or integrity: the pre-registered verdicts become unreachable rather than wrong.
- **Fix:** Decide skew on `model_id` plus `refusal_fallbacks` (both already recorded), or ignore auxiliary models below a small output share; keep the full `models_used` list in the report as information.
- **Reference:** CWE-697 Incorrect Comparison — https://cwe.mitre.org/data/definitions/697.html

### [LOW-001] Header describes a scope the replay heuristics do not have

- **Severity:** LOW (confidence: high) — Confirmed by the review (Observation 4).
- **File:** `head/.claude/scripts/guard-yield.sh:29-31` vs `head/.claude/scripts/guard-yield.sh:499-501`
- **Issue:** The header says the cwd and burst rules apply "for rows that predate the flag"; `def replay($burst)` applies them to every row. A live session that trips ten blocks in one minute, or a checkout under `$TMPDIR`, is excluded as replay even when its rows carry no `replay` key.
- **Fix:** Scope the heuristics to rows without a `replay` key (`has("replay") | not`), or reword the header.
- **Reference:** CWE-1116 Inaccurate Comments — https://cwe.mitre.org/data/definitions/1116.html

### [LOW-002] Transport-failure classification greps the model's result text

- **Severity:** LOW (confidence: medium) — Confirmed by the review (Observation 5).
- **File:** `head/evals/harness/run-arms.sh:314-315`
- **Issue:** `grep -qiE 'rate.?limit|overloaded|…|network|socket hang up|5[0-9][0-9] ' "$err" "$out"` also reads `agent-output.json`, which embeds the final assistant text. A review that mentions "network" or a count such as "1500 " turns an exit-1 agent error into `transport_error`: one retry spent, the arm `partial` instead of `agent_error` recorded.
- **Fix:** Match the structured fields (`exit_code`, `subtype`, `api_error_status`) and the stderr log only.
- **Reference:** CWE-185 Incorrect Regular Expression — https://cwe.mitre.org/data/definitions/185.html

### [LOW-003] The redaction counter over-counts

- **Severity:** LOW (confidence: high) — Confirmed by the review (Observation 6).
- **File:** `head/evals/harness/seed-corpus-from-record.sh:127-128`
- **Issue:** `REDACTED[0] += n if count else 0` accumulates across the `head.diff` pass (line 331, `count=True`) and every `base/` and `head/` write (lines 736 and 740, `count=True`), so one secret-shaped string in a modified file is counted up to three times; the `.dropped.txt` header at line 756 overstates the redactions.
- **Fix:** Count in one pass, or count distinct `(path, line)` hits.
- **Reference:** CWE-682 Incorrect Calculation — https://cwe.mitre.org/data/definitions/682.html

### [LOW-004] Brace-form renames escape the binary filter

- **Severity:** LOW (confidence: medium) — Confirmed by the review (Observation 7).
- **File:** `head/evals/harness/seed-corpus-from-record.sh:312`
- **Issue:** `binary.add(p.split(" => ")[-1].strip("{}"))` handles `old => new` but turns `dir/{a => b}/f.bin` into `b}/f.bin`, so a renamed binary is not excluded at line 321 and its bytes, decoded with `errors="replace"` at line 336 and re-encoded by `redact()`, land in `head/` corrupted.
- **Fix:** Parse `--numstat -z`, or normalise the brace form before stripping.
- **Reference:** CWE-20 Improper Input Validation — https://cwe.mitre.org/data/definitions/20.html

### [LOW-005] App-zone permission widened in a skill the PR does not describe

- **Severity:** LOW (confidence: high) — Confirmed by the review (Observation 8).
- **File:** `head/.claude/skills/implementing-tasks/SKILL.md:28`
- **Issue:** `permission: read-write` replaces `read` for the app zone in the frontmatter. The body already granted Read/Write, and the mechanical gate is `implement-gate.sh`, not this key, so the effective permission does not change; but it is a permission declaration in a skill outside the four features the PR body names, and the body does not mention it. Named here so the audit trail shows it was intended.
- **Fix:** One line in the PR description.
- **Reference:** CWE-269 Improper Privilege Management — https://cwe.mitre.org/data/definitions/269.html

### [LOW-006] The suite-level status aggregation gives up silently

- **Severity:** LOW (confidence: medium) — Confirmed by the review (Observation 9).
- **File:** `head/evals/harness/run-arms.sh:287` and `head/evals/harness/run-arms.sh:301-302`
- **Issue:** `until mkdir "$lockd" 2>/dev/null; do …; [[ $n -gt 50 ]] && return 0; …` returns success after 5 s without the lock, and the `jq -s … 2>/dev/null && mv` list hides a failed aggregation; the suite `STATUS.json` then lags the batch files and `report.sh --arms` refuses or reports stale counts without a hint. The unquoted `$(find …)` at line 301 also word-splits a `--results-dir` containing spaces.
- **Fix:** Log the skipped or failed aggregation; retry once before `set_state`; quote the file list (`-print0` + array).
- **Reference:** CWE-392 Missing Report of Error Condition — https://cwe.mitre.org/data/definitions/392.html

### [LOW-007] The audit-segment glob is permissive

- **Severity:** LOW (confidence: medium) — Confirmed by the review (Observation 10).
- **File:** `head/.claude/scripts/guard-yield.sh:443-445`
- **Issue:** `for f in "$AUDIT_LOG" "$AUDIT_LOG".*` also matches `audit.jsonl.lock` or `audit.jsonl.tmp`; a text sibling is parsed as rows (inflating `audit_rows_unparseable`), an unreadable one is `die 3`. `-f` follows symlinks, but nothing from a row reaches an output, so no disclosure path exists.
- **Fix:** Match rotated segments only (`"$AUDIT_LOG".[0-9]*` or a date suffix).
- **Reference:** CWE-20 Improper Input Validation — https://cwe.mitre.org/data/definitions/20.html

### [LOW-008] SIMPLICITY: three linear functions over the 50-line guide

- **Severity:** LOW (confidence: high) — Confirmed by the review (Observation 11).
- **File:** `head/evals/harness/arms-report.py:176-343` (`suite_report`, 168 lines); `head/.claude/scripts/validate-artifact.sh:976-1064` (`validate_sprint_kinds`, 89 lines); `head/evals/harness/run-arms.sh:319-384` (`run_trial`, 66 lines)
- **Issue:** Each is one linear pipeline covered by bats (AR-1 … AR-7, KINDS-1 … KINDS-11, RA-1 … RA-5). Recorded, not blocking; the verdict rule at `arms-report.py:273-310` is the first extraction.
- **Reference:** CWE-1121 Excessive McCabe Cyclomatic Complexity — https://cwe.mitre.org/data/definitions/1121.html

### [LOW-009] The audit_delta_instruction toggle is not verified absent afterwards

- **Severity:** LOW (confidence: high)
- **File:** `head/evals/harness/execute-agent.sh:271-273`
- **Issue:** `_drop_paragraph "$s" "$eval_dir/arm-removed.txt"` removes the FIRST paragraph holding a needle (`execute-agent.sh:214-222`, `sys.exit(0)` after one deletion) and the branch records evidence without re-reading the file; unlike the `karpathy_block` branch (`grep -q '^## Karpathy Principles'` at line 251) there is no post-check. A SKILL.md revision that states the delta instruction twice (the Coverage paragraph plus a reminder elsewhere) keeps the second copy in the sandbox and in the appended system prompt, and the arm still records `audit_delta_instruction: false`. At `864069f2` the needle occurs once (AT-7 passes); the header's promise at lines 63-66 is what this breaks.
- **Fix:** After the drop, `grep -qiF` each needle and `return 2` on a hit, mirroring line 251.
- **Reference:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html

### [LOW-010] Toggles are applied without an arm id and the row is labelled baseline

- **Severity:** LOW (confidence: high)
- **File:** `head/evals/harness/execute-agent.sh:154-155`, `head/evals/harness/execute-agent.sh:163-166`, `head/evals/harness/execute-agent.sh:188`
- **Issue:** `ARM="${LOA_EVAL_ARM:-baseline}"` and `resolve_toggles` honours `LOA_EVAL_ARM_TOGGLES` whenever it is set, regardless of `ARM_MODE`. With `LOA_EVAL_ARM_TOGGLES='{"rule_files":false}'` and no `LOA_EVAL_ARM`, the sandbox is toggled, `.loa.config.yaml` is not materialised (line 157 is gated on `ARM_MODE`), and `executor.json` records `arm: baseline` with non-empty `arm_toggles`; `arms-report.py` keys on `arm` and would fold a toggled trial into the reference. AT-11 sets both variables, so the path is untested.
- **Fix:** Refuse explicit toggles when `LOA_EVAL_ARM` is unset or `baseline` (`exit 2`), or derive `ARM_MODE` from either variable.
- **Reference:** CWE-20 Improper Input Validation — https://cwe.mitre.org/data/definitions/20.html

### [LOW-011] TERM/HUP cleanup reaps the trial subshells, not the executors

- **Severity:** LOW (confidence: medium)
- **File:** `head/evals/harness/run-arms.sh:244-249` and `head/evals/harness/run-arms.sh:426`
- **Issue:** `cleanup` sends `kill "$p"` to each `jobs -p` pid, the `run_trial` subshells; the `execute-agent.sh → timeout → claude` chain below them is not signalled. A TERM to the driver (a supervisor, a session cap) leaves up to `--concurrency` executors running, each spending model budget until its own `--timeout` (up to 3600 s for the record tasks) while STATUS reads `failed` and their rows are never collected. Terminal INT reaches the whole process group and is unaffected.
- **Fix:** Run each trial with `setsid` (or record `$!` and `kill -- -"$pgid"`), or have `run_trial` trap TERM and forward it to its child.
- **Reference:** CWE-404 Improper Resource Shutdown or Release — https://cwe.mitre.org/data/definitions/404.html

### [LOW-012] The `.yml` isolation comment overstates what the extension keeps out

- **Severity:** LOW (confidence: medium)
- **File:** `head/evals/tasks/review-recall/review-kind-01.yml:6-9`
- **Issue:** The comment says the `.yml` extension keeps the task out of the suite "so no suite, arm run or CI job picks it up". The suite path holds: `run-eval.sh --suite review-recall` expands `tasks/review-recall/**/*.yaml` with globstar and only falls back to a `find` of both extensions when the glob matches nothing (`head/evals/harness/run-eval.sh:245`). The skill-filter and all-tasks paths do not: `find "$TASKS_DIR" -name '*.yaml' -o -name '*.yml'` at `head/evals/harness/run-eval.sh:198` and `:283` loads it for `--skill reviewing-code` and for a bare run, where its `pattern-match.sh` grader and the `review-kinds/kind-01` fixture run unreviewed.
- **Fix:** Add the file to the suite's `tasks.exclude` or move it under a directory no `--skill`/all run scans, and correct the comment.
- **Reference:** CWE-1116 Inaccurate Comments — https://cwe.mitre.org/data/definitions/1116.html

---

## Observations (not tallied)

- **Replay flag is an environment convention.** `head/.claude/hooks/safety/block-destructive-bash.sh:528`, `:782`, `:1367` and `:1520` stamp `replay: true` whenever `LOA_AUDIT_REPLAY=1` is in the hook's environment. The block itself is unaffected, so this is not a bypass of any fence; it does mean a session env (profile, `settings.local.json` `env`) can mark every real block as replay and zero a guard's `real_blocks_30d`. The yield is documented as host-local telemetry and a deletion "requires the lead to read that arm's missed labels", so the consequence is bounded; worth a line in `guards.md`'s header so a reader of the yield knows the flag is advisory.
- **`heredoc_nonexec "$cmd"`** (`head/.claude/scripts/guard-yield.sh:477`) hands untrusted audit-row command text to a library function that does not exist at PR head. Unable to assess at head; the later-cycle library in this workspace defines the function without `eval`, and the argument is passed positionally, so the forward hook is safe as long as the library stays that way.
- **Record fixtures un-ignore a built `dist/`** (`head/.gitignore:32-33`): the pr-11 … pr-18 fixtures will carry `bridgebuilder-review/dist/` JavaScript copied from the repository's own history into the committed corpus. The sandbox agent has no code-running tool and the seeder's `no-secrets.sh` gate covers the files, so no new execution or disclosure surface; noted because committed build artefacts are a review-attention item.

---

## Cross-Model Security Observations

None: the dissent refused before dispatch (DEGRADED_SECURITY_REVIEW above); no advisory findings were produced.

---

## Review Demotions Confirmed

The review trailer records `excluded: 0`; no demoted high to confirm. `excluded_confirmed: 0`.

---

## Scope limits

Outside the review snapshot and therefore not verified from this workspace: `grimoires/loa/guards.md` (the tracked register the new CI step `guard-yield.sh --check` compares against); `tools/check-prompt-budget.sh` (PB-10 and the workflow header's four constants); the record fixtures pr-11 … pr-18 with `labels/`, `manifests/`, `corpus.tsv`, `record-pairs.tsv` and `SHA256SUMS`; `evals/harness/sandbox.sh`, `grade.sh`, `evals/graders/no-secrets.sh` and `pattern-match.sh`; `CHANGELOG.md`. Test suites were not re-run for this audit; the review's Test Evidence table records the runs against the head tree (guard-yield 11/11, guard-origins 15/15, sprint-kinds 11/11, rule-paths 6/6, cycle-ratio 6/6, loa-status-guards 3/3, arm-toggles 11/11, arms-report 7/7, execute-agent 10/12, recall-grader 26/28, freshness 12/13; run-arms and seed-corpus not runnable without the sandbox and corpus). No `documentation-coherence-*` subagent report exists under `grimoires/loa/a2a/subagent-reports/`; the documentation changes were verified by reading: `hooks-reference.md` table regenerated in sync, five GLOSSARY entries pass the validator, `evals/README.md` and the sprint template updated, `skill-invariants.md` and `stash-safety.md` keep their bodies (RP-5).

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added (seeder drops secret-shaped findings, redacts fixture copies, and fails closed on `no-secrets.sh`; stubs carry fake ids only)
- [x] Input validation on all new entry points (guard ids `^[A-Za-z0-9._/:-]+$`, arm ids `^[a-z][a-z0-9_]{0,63}$`, fixture ids `^pr-[0-9]{2}$`, shas `^[0-9a-f]{7,40}$`, model ids, batch names, `--by`, `--now`, `--window-days`; table cells control-stripped and pipe-escaped)
- [x] Authentication/authorization unchanged (no hook registration, deny list or floor file changes: FS-1 … FS-4; floor.yaml pinned by sha256)
- [x] No injection vulnerabilities (jq/yq values by `--arg`, Python `-I` with quoted heredocs, git refs validated or passed after `--`, awk programs are literals)
- [x] Error handling doesn't leak info (yield outputs carry no command text, cwd, hostname or model name — GY-5; seeder titles control-stripped and capped)
- [x] Tests cover security paths (GY-5 privacy, SC-2 secret rejection, AT-9/AT-10 toggle refusals, RA-4/RA-5 usage refusals, FS-1 … FS-4 floor snapshot, RG-27 forged-module isolation retained)

---

## Next Steps

**APPROVED:**
1. The feedback file is written; per the task instructions this run stops here. The `COMPLETED` marker is not written: the dissent envelope is a budget-refusal record without `metadata.model`, which `adversarial-review-gate.sh` refuses, and the task scope ends at this file.
2. Carry MED-001, MED-002 and MED-003 into the next sprint of this cycle; each has a one-line test (a library stub that exits, a malformed `constraints.json`, a `models_used` row with a helper model on every arm).
3. Fix LOW-009 and LOW-010 alongside MED-002: all three are the same "a toggle must verify itself" invariant.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":3,"low":12},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-21T09:25:00Z"} -->
