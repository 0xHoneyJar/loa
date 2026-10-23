# Sprint 1 Security Audit

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md (task review-r19)
**Change under audit:** `pr/head.diff` — feat(cycle-129): sprint-255 — guard register with origin and yield, pre-registered control arms on a record corpus, task kinds, path-scoped rule files (81 files)
**Review feedback:** grimoires/loa/a2a/sprint-1/engineer-feedback.md (CHANGES_REQUIRED, 0 critical / 1 high / 5 medium / 9 low, excluded 0)
**Dissent envelope:** grimoires/loa/a2a/sprint-1/adversarial-audit.json (primary `gpt-5.5-pro` via codex-headless: clean; companion `claude-headless`: 1 MEDIUM, 4 LOW; 0 rejected payloads; `degraded: false`)
**Methodology:** Systematic 5-category review (Security, Architecture, Code Quality, DevOps; Blockchain n/a)

---

## Prerequisite deviation

The audit skill's Phase 0 requires `engineer-feedback.md` to say "All good". It says CHANGES REQUIRED. The task directive for review-r19 orders the audit to run regardless and to write this file, so the audit proceeded; the review's one HIGH is re-examined below rather than assumed. No `COMPLETED` marker is written. Guardrails pre-check: `PROCEED`. Beads (`br`) is not installed; no bead comment or label was recorded.

## Scope limits

- The fixture holds the 81 touched files only. `grimoires/loa/guards.md`, the eight record fixtures under `evals/fixtures/review-prs/pr-11…pr-18`, their hidden labels, `SHA256SUMS`, `evals/harness/sandbox.sh`, `grade.sh`, `no-secrets.sh` and `tools/check-prompt-budget.sh` are not present and could not be audited. Nothing below claims a defect in them.
- `run-arms.bats` and `seed-corpus.bats` were not executed (they need the absent helpers); the HIGH below was confirmed by tracing the code path, not by running it.
- No `grimoires/loa/a2a/subagent-reports/documentation-coherence-*.md` exists for this sprint; the documentation check below was done by hand against the diff.

---

## Executive Summary

The change adds a guard register generated from the repository (`guard-yield.sh`, `guard-origins.yaml`, `floor.yaml`), a control-arm driver and report for the review/audit recall evals (`run-arms.sh`, `arms-report.py`, arm toggles in `execute-agent.sh`), a seeder that turns shipped sprints into record fixtures (`seed-corpus-from-record.sh`), a `kind:` task tag validator, and `paths:` frontmatter on two rule files. Input handling across the new scripts is good: every id, batch name, commit, model and fixture argument is regex-gated, YAML lookups go through `strenv`, JSON through `--arg`/`--argjson`, Python runs with `-I`, and the yield writer leaks no command text, cwd or model name (GY-5). No hardcoded secret, injection path or privilege escalation was found.

One finding blocks. `run-arms.sh` admits a second run into a batch that already holds results for the same source commit and model, re-plans every trial, appends duplicate rows to `<arm>/results.jsonl`, overwrites per-trial artifacts and restarts the STATUS counters at zero. `arms-report.py` counts every row, so the pre-registered verdict that may license deleting a guard can be computed over duplicated trials while STATUS.json reads `complete`. The default batch name is deterministic, so a re-run after the documented `partial` exit lands exactly here. The review found this; the audit confirms it independently as HIGH (data-integrity of a safety-relevant decision input, CWE-345).

Five MEDIUMs follow: the floor pins guard identifiers but not the fence body or the deny list that implements two thirds of the floor guards; `guard-yield.sh` sources the heredoc classifier into its own process; `implementing-tasks/SKILL.md` widens its app-zone permission with no rationale; `stash-safety.md` becomes conditional on the files in play; and `run-arms.sh` uses a GNU-only `date` form that fails every trial on the BSD platform its own comments claim to support. Eleven LOWs are listed. The review's trailer excludes no high, so `excluded_confirmed` is 0.

**Overall Risk Level:** MODERATE

**Key Statistics:**

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 5 |
| Low | 11 |

---

## Category Scores (Rubric-Based Assessment)

**Scoring Method:** Each dimension scored 1-5 per `resources/RUBRICS.md`

| Category | Score | Dimensions |
|----------|-------|------------|
| Security | 4.0/5 | IV:4 AZ:4 CI:4 IN:5 AV:3 |
| Architecture | 3.8/5 | MO:4 SC:4 RE:3 CX:4 ST:4 |
| Code Quality | 3.8/5 | RD:4 TC:4 EH:3 TS:4 DC:4 |
| DevOps | 3.6/5 | AU:4 OB:4 RC:3 AC:4 DS:3 |
| Blockchain | n/a | not applicable |
| **Overall** | **3.8/5** | *Security weighted highest* |

**Machine-Parseable Output:** `grimoires/loa/a2a/audits/2026-10-21/findings.jsonl`

---

## Critical Issues (Fix Immediately)

None.

---

## High Priority Issues (Fix Before Production)

### [HIGH-001] Control-arm driver re-runs a batch in place: duplicate trial rows feed the pre-registered verdict

**Severity:** HIGH | **Confidence:** high
**Component:** `head/evals/harness/run-arms.sh:251-257` (admission), `:126` (deterministic default batch), `:264-265` (counters restart at 0), `:408` (rows appended), `head/evals/harness/arms-report.py:135`, `:239` (every row is a cell)
**Criterion:** SEC-AV / ARCH-RE (integrity of a decision input)

**Reasoning Trace:**
> `run-arms.sh:126` builds the default batch as `batch-${FIXTURES[0]}-${FIXTURES[last]}-n${#FIXTURES[@]}`, a pure function of the fixture list. The pre-flight at `:251-256` reads the existing MANIFEST.json and dies only when `prev_src != SRC_FULL || prev_model != MODEL`; with the same pair it falls through to `write_manifest` at `:257`, which overwrites MANIFEST.json. `PLAN` is rebuilt from scratch at `:160-165`, `DONE`/`FAILED` are zeroed at `:265`, and `collect()` appends each new row with `>>` at `:408` without reading what the file already holds. `keep_artifacts` at `:387` writes to `trial-$4$5`, the same path as the previous run, so artifacts are overwritten while both rows survive. `arms-report.py:135` appends every completed row to `cells[fx]`; `coverage_gaps` at `:239` counts `len(arm.cells[fx])`, so duplicates satisfy `trials_required`. The exit contract at `:41-43` ("1 partial … results kept") invites exactly this re-run. `run-arms.bats` RA-3 (`:110`, `:123`) re-runs only with fresh `--batch` names, and RA-5 (`:144`) covers only the different-model refusal; no test exercises a same-batch re-run.

**Description:** A second invocation with the same source commit and model on an existing batch is admitted, duplicates every (arm, fixture, trial) cell, breaks the row/artifact pairing and resets the per-arm counters, so STATUS.json and `results.jsonl` describe different experiments.

**Impact:** `arms-report.py` is the gate that licenses removing a control (SDD D-2.3). After a re-run, `fixture_means` and `trial_means` are biased toward whichever run was duplicated, `trials done` exceeds `trials_planned`, the missed-label counts double, and STATUS.json still reads `complete`. A guard deletion could be justified by a verdict computed over duplicated data. Unlikely to be adversarial, but the failure is silent and the default path leads straight into it.

**Proof of Concept:**
```
run-arms.sh --suite review-recall --arms baseline,no_rule_files --fixtures pr-11,pr-12 --trials 3 --source-commit <sha>
# one trial fails twice -> exit 1 "partial"; operator re-runs the same command to fill the gap
run-arms.sh --suite review-recall --arms baseline,no_rule_files --fixtures pr-11,pr-12 --trials 3 --source-commit <sha>
# admitted (same source/model); baseline/results.jsonl now holds 2 rows per cell; STATUS trials_done counts only run 2
```

**Remediation:** Either refuse a batch whose `<arm>/results.jsonl` already exists (same shape and message as `:255`, "use another --batch"), or implement a real resume: read existing rows, skip cells that already hold a `completed` row, seed `DONE`/`FAILED` from them and keep MANIFEST.json. Add an RA test that re-runs the same batch and asserts one row per (arm, fixture, trial).

**References:** CWE-345 Insufficient Verification of Data Authenticity — https://cwe.mitre.org/data/definitions/345.html ; CWE-1288 Improper Validation of Consistency within Input — https://cwe.mitre.org/data/definitions/1288.html

---

## Medium Priority Issues (Address in Next Sprint)

### [MED-001] The floor pins guard identifiers, not the code that implements most floor guards

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `head/.claude/data/floor.yaml:46-50` (floor_files), `:42` (`implement_gate.*` floor key), `head/.claude/data/guard-origins.yaml:163` (`hook:safety/block-destructive-bash.sh` floor: false), `:208` and `:810` (implement-gate rows floor: false), `:884` (`policy:permission-deny-list` script is `settings.deny.json`)
**Criterion:** SEC-AZ / DEVOPS-RC

**Description:** Sixteen of the twenty-one `floor_guards` are `fence:FR-SZ*` and `fence:FR-1.2b` rows implemented only by `block-destructive-bash.sh` and armed by the `PreToolUse:Bash` registration. `floor_files` pins neither the fence nor `.claude/settings.json`. `floor-snapshot.bats` FS-3 pins the hook registrations and FS-4 pins the ordered `emit_block`/`pattern_id` call-site list, and `floor_corpus` pins the expected verdict of the existing corpus rows, so removing a guard or a registration is caught. A new allow branch inside the fence body (another env-var bypass, a widened `_c2_authorized` check) changes no call site and is exercised by no existing corpus row, so it passes every floor suite while the register still prints `floor: yes`. Likewise `policy:permission-deny-list` is enforced by `permissions.deny` in `.claude/settings.json` (62 entries on this host), which is not pinned; `settings.deny.json` is the template. And `implement_gate.*` is a floor key while both implement-gate rows are `floor: false`. Raised by the review and by the companion dissent (DISS-C-001).

**Impact:** A cycle task can weaken a floor guard's behaviour without any floor test going red; the floor's documented promise ("no profile, knob or cycle task may weaken") is narrower than its wording.

**Remediation:** Add `.claude/hooks/safety/block-destructive-bash.sh` to `floor_files` (or pin its sha in `guard-origins.bats` beside the floor.yaml pin and bump deliberately), diff `.claude/settings.json` `permissions.deny` against `settings.deny.json` in FS-3, and make `floor_keys` and the `floor:` rows agree on implement-gate.

**References:** CWE-693 Protection Mechanism Failure — https://cwe.mitre.org/data/definitions/693.html

### [MED-002] guard-yield.sh sources the heredoc classifier into its own process

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `head/.claude/scripts/guard-yield.sh:468-470`
**Criterion:** CQ-EH

**Description:** `source "$HEREDOC_LIB"` runs the library in the generator's shell. The live `heredoc-classifier.sh` sources the fence with `BDB_LIB_ONLY=1` (lib line 19), so the head state works, but a lib whose fence does not honour library mode runs the fence as a hook and ends `guard-yield.sh` with exit 0 and nothing written (observed by the review on a composite root). `--check` exits before this section and cannot detect it.

**Impact:** A silent no-op generation that reports success; the yield files go stale without a signal.

**Remediation:** Call `heredoc_nonexec` through a subshell (`( source "$HEREDOC_LIB"; heredoc_nonexec "$cmd" )`), or probe the lib in a subshell first and treat a missing summary line as exit 3.

**References:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html

### [MED-003] implementing-tasks app-zone permission widened without rationale

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `head/.claude/skills/implementing-tasks/SKILL.md:28`
**Criterion:** SEC-AZ

**Description:** `zones.app.permission` changes from `read` to `read-write`. The PR title names the guard register, control arms, task kinds and path-scoped rule files; this hunk is none of them and the diff carries no comment, DEC row or test. `/implement` is the sanctioned writer of app code, so the value is probably a correction, but it is a security-relevant declaration moving silently. `reviewing-code/SKILL.md:135` now points at the frontmatter `zones:` as the zone source, which raises the weight of that key. Raised by the review and the companion dissent (DISS-C-003).

**Impact:** Any future consumer of `zones.app.permission` inherits an unaudited grant; a later audit cannot distinguish it from drift.

**Remediation:** Add a one-line rationale (or DEC row) and a bats assertion that only `implementing-tasks` carries `app: read-write`.

**References:** CWE-250 Execution with Unnecessary Privileges — https://cwe.mitre.org/data/definitions/250.html

### [MED-004] stash-safety.md becomes conditional on which files are edited

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `head/.claude/rules/stash-safety.md:2-6`
**Criterion:** SEC-AV (prose guard coverage)

**Description:** The new `paths:` globs (`**/*.sh`, `**/*.bats`, `.claude/scripts/**`, `.claude/hooks/**`) load the rule only when a shell file is in play, but `git stash push/pop` is typed into Bash regardless of the files being edited. In an app-code session only the harness regex FR-1.2b remains, and it fires only on the swallowed-output shape. `rule-paths.bats` attributes the globs to SDD D-3.1 / DEC-0129, so this is a recorded decision; recorded here as residual risk. Raised by the review and the companion dissent (DISS-C-005).

**Impact:** A plain `git stash push && … && git stash pop` while editing Python or Markdown runs without the rule in context and without a fence.

**Remediation:** Record in the DEC row that the fence, not the prose, is the only stash guard outside shell sessions, or widen the globs.

### [MED-005] GNU-only millisecond clock breaks every trial on BSD/macOS

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `head/evals/harness/run-arms.sh:326`, `:366`, `:374`
**Criterion:** DEVOPS-DS

**Description:** `date +%s%N | cut -c1-13` relies on GNU `%N`; BSD `date` prints a literal `N`, so `start_ms` is `1729500000N` and `$(( end_ms - start_ms ))` at `:374` is an arithmetic error inside the background job under `set -e`. No row is written and `collect()` records `FAILED (no row written)` for every trial. The script's own comment at `:263` claims bash 3.2 (macOS) compatibility.

**Impact:** A whole batch fails on the platform the script says it supports; the failure mode looks like an executor problem.

**Remediation:** `python3 -c 'import time;print(int(time.time()*1000))'` (python3 is already required at `:95`), or seconds via `date +%s`.

---

## Low Priority Issues (Technical Debt)

### [LOW-001] Replay flag is taken on trust from the environment

**Severity:** LOW | **Confidence:** medium
**Component:** `head/.claude/hooks/safety/block-destructive-bash.sh:528-529`, `:782`, `:1367`, `:1520`; `head/evals/harness/run-arms.sh:337`; `head/.claude/scripts/guard-yield.sh:499`
**Description:** Four audit-row writers stamp `replay: true` whenever `LOA_AUDIT_REPLAY == "1"`; nothing ties the flag to the corpus runner. `guard-yield.sh:499` excludes flagged rows from the 30-day yield. If the variable leaks into an interactive Claude Code session (a `settings.json` `env` block, a shell profile, a leftover export from a corpus run), real blocks disappear from the yield that operators read to judge whether a guard earns its keep. The burst rule at `:518-519` has the same shape: ten blocks in one UTC minute hide all ten. Raised by the companion dissent (DISS-C-002). Low because the yield is advisory and the heuristics are documented in the header.
**Remediation:** Have the replaying suites write to a separate audit log (`LOA_REPO_ROOT` already points them at a scratch root), or key the flag on a nonce the runner alone holds; report `replay_rows_by_rule.flag` in the `/loa` Guards line so a non-zero count outside a test run is visible.
**References:** CWE-807 Reliance on Untrusted Inputs in a Security Decision — https://cwe.mitre.org/data/definitions/807.html

### [LOW-002] Transport-failure heuristic reads the model's own text

**Severity:** LOW | **Confidence:** medium
**Component:** `head/evals/harness/run-arms.sh:314-315`
**Description:** `is_transport_failure` greps `agent-output.json` (the result text) for `network` and `5[0-9][0-9] `; a review that mentions a network call or a line number followed by a space classifies a genuine agent error as transport and spends the single retry.
**Remediation:** Match the stderr log and the structured `api_error_status` / `subtype` fields only.

### [LOW-003] Unquoted `find` and unvalidated `--results-dir`

**Severity:** LOW | **Confidence:** high
**Component:** `head/evals/harness/run-arms.sh:301`, `:79`
**Description:** `aggregate_status` passes `$(find …)` unquoted to `jq -s`, and `--results-dir` is not validated; a path with a space breaks the suite STATUS.json silently (`2>/dev/null`).
**Remediation:** Validate `--results-dir` like `--batch`, or feed the list through `find -print0 | xargs -0`.

### [LOW-004] Arm mode clobbers the fixture's config and creates a constraints key

**Severity:** LOW | **Confidence:** medium
**Component:** `head/evals/harness/execute-agent.sh:158`, `:256`
**Description:** In arm mode the prompt tree's `.loa.config.yaml` is copied over whatever the fixture carried; `(.constraints // []) |=` creates a `constraints` key in a `constraints.json` that had none.
**Remediation:** Copy only when the sandbox has no config (or record the clobber in `arm_evidence`); guard the jq edit with `if has("constraints")`.

### [LOW-005] Redaction counter over-reports

**Severity:** LOW | **Confidence:** high
**Component:** `head/evals/harness/seed-corpus-from-record.sh:128`, `:331`, `:736`, `:740`
**Description:** `REDACTED[0]` is incremented for the diff text and again for every base/head file written with the default `count=True`, so the `dropped.txt` note over-reports by up to 3x.
**Remediation:** Pass `count=False` at `:736` and `:740`.

### [LOW-006] Abbreviated rename form mis-parsed in binary detection

**Severity:** LOW | **Confidence:** medium
**Component:** `head/evals/harness/seed-corpus-from-record.sh:312`
**Description:** `p.split(" => ")[-1].strip("{}")` turns git's `dir/{old => new}/file` into `new}/file`, so a renamed binary is not excluded from the fixture scope.
**Remediation:** Expand `{a => b}` with a regex, or take renames from the `--name-status -M` pass already parsed at `:314`.

### [LOW-007] `sorted()` over None and str

**Severity:** LOW | **Confidence:** medium
**Component:** `head/evals/harness/arms-report.py:219-220`
**Description:** A manifest lacking `source_commit` or `model_id` puts `None` beside strings and `sorted()` raises `TypeError`. Every manifest `run-arms.sh` writes carries both, so only a hand-edited or foreign manifest trips it.
**Remediation:** Filter `None` before sorting (the join already does).

### [LOW-008] Audit-log sibling files read as segments; replay prefix can be `/`

**Severity:** LOW | **Confidence:** medium
**Component:** `head/.claude/scripts/guard-yield.sh:443`, `:457-458`, `:500`
**Description:** `"$AUDIT_LOG".*` also matches `audit.jsonl.lock` and `.bak`, inflating `audit_rows_unparseable`; the replay cwd prefix is the generator's own `TMPDIR`, so `TMPDIR=/` classifies every row as replay.
**Remediation:** Restrict segments to `audit.jsonl.[0-9]*`; skip the prefix rule when it resolves to `/`.

### [LOW-009] Prompt-budget header pin not verifiable here

**Severity:** LOW | **Confidence:** low
**Component:** `head/.github/workflows/check-prompt-budget.yml:5`, `head/tests/unit/prompt-budget.bats:113`
**Description:** The header now states 160,000 / 114,688 B and PB-10 pins it to the constants line of `tools/check-prompt-budget.sh`, which is not in the change. If the tool's constants were not updated in the same merge, PB-10 is red.
**Remediation:** None if the tool already carries these constants.

### [LOW-010] Red-flag enumeration removed from the reviewer prompt

**Severity:** LOW | **Confidence:** low
**Component:** `head/.claude/skills/reviewing-code/SKILL.md:135`, `:284`
**Description:** The inline list (private keys, SQL concatenation, unvalidated input, empty catch blocks, missing tests, N+1) is replaced by a pointer to `resources/REFERENCE.md`. Phase 2 at `:216` still directs the reviewer to `REFERENCE.md §Security`, so the list stays reachable, but it is no longer in the always-loaded prompt. Raised by the companion dissent (DISS-C-004). Low; a prompt-budget trade-off, not a defect.
**Remediation:** Keep a one-line enumeration if the budget allows, or make the §Security read an explicit Phase 2 step.

### [LOW-011] Implementation report has no acceptance-criteria walkthrough

**Severity:** LOW | **Confidence:** high
**Component:** `grimoires/loa/a2a/sprint-1/reviewer.md`
**Description:** The report is the PR title and a file count; no `## AC Verification`, no fast-gate (shellcheck/bats) evidence, no stated assumptions. Not counted against the code; the verdict rests on HIGH-001.
**Remediation:** Add the walkthrough and the bats/shellcheck evidence in the next round.

---

## Observations

None demoted. The review trailer carries `excluded: 0`; there was no speculative low-confidence HIGH to confirm or re-tally, so `excluded_confirmed` is 0.

Points verified clean while tracing (not findings): fixture and arm ids, batch names, model ids and commit ids are regex-gated (`run-arms.sh:89-94`, `:106`, `:111`, `:127`); YAML lookups use `strenv` (`:107`, `execute-agent.sh:175`, `:179`); JSON is built with `--arg`/`--argjson` throughout; Python runs with `-I` (`run-arms.sh:135`, `seed-corpus-from-record.sh:57`, `execute-agent.sh:_drop_paragraph`, `report.sh --arms`); `--out` must sit directly under the corpus and fixture ids match `^pr-[0-9]{2}$` before any `rmtree` (`seed-corpus-from-record.sh:289-292`, `:713`, `:730`); the executor strips cloud and GitHub credentials and decouples the parent session (`execute-agent.sh:339`, `:346-349`); `install_file` writes atomically with mode 0644 (`guard-yield.sh:402-409`); the fence diff is marker comments plus the replay field only, FS-4 confirms the call-site list is unchanged; `loa-status.sh` reads only numerals and a sanitised scope from the yield files; the CI drift gate runs with a sha-pinned `yq`.

---

## Rejected dissent payloads

None. `adversarial-audit.json` carries `rejected_summary: []` and `rejected_sidecars: []`; both voices returned well-formed payloads (primary `gpt-5.5-pro`: clean; companion `claude-headless`: five findings). The companion findings are triaged above: DISS-C-001 → MED-001, DISS-C-002 → LOW-001, DISS-C-003 → MED-003, DISS-C-004 → LOW-010, DISS-C-005 → MED-004.

---

## Security Checklist Status

### Secrets & Credentials
- [x] No hardcoded secrets (the seeder redacts secret shapes at `:111-129` and runs `no-secrets.sh` over every written file at `:761-774`; the bats fixture assembles its fake key at runtime)
- [x] Executor drops operator credentials before the agent under test starts (`execute-agent.sh:339`)
- [ ] `no-secrets.sh` itself not in scope — unable to assess its pattern coverage

### Authentication & Authorization
- [x] No new privileged path; arm toggles touch the sandbox copy only and verify themselves (`execute-agent.sh:223-271`)
- [ ] Floor completeness: MED-001
- [ ] Zone declaration widened without rationale: MED-003

### Input Validation
- [x] All CLI arguments regex-gated at trust boundaries
- [x] Hook commands parsed against the canonical schema; control characters rejected (`guard-yield.sh:192-209`)
- [ ] `--results-dir` unvalidated: LOW-003

### Data Integrity
- [ ] Batch re-run duplicates verdict inputs: HIGH-001
- [x] Corpus verified against SHA256SUMS before the batch and per trial (`run-arms.sh:134-157`, `:327`)
- [ ] Replay flag self-declared: LOW-001

### Error Handling & Information Disclosure
- [x] No command text, cwd, hostname or model name in register or yield outputs (GY-5)
- [ ] Silent no-op on heredoc lib failure: MED-002

### Code Quality
- [x] Bats suites accompany every new script; the review ran guard-origins 15/15, guard-yield 11/11, sprint-kinds 11/11, cycle-ratio 6/6, loa-status-guards 3/3, arms-report 7/7, arm-toggles 11/11 green against the head files
- [ ] No test for a same-batch re-run (HIGH-001)

---

## Documentation Audit

No `documentation-coherence-*.md` report exists for this sprint and `/validate docs` is not runnable here. By hand: the new scripts carry header documentation stating usage, exit codes and the tests that cover them; `GLOSSARY.md`, `evals/README.md`, `hooks-reference.md` and the sprint template are updated in the diff; the fence's new behaviour (replay field) is commented at the top of `guard-yield.sh`. `CHANGELOG.md` is excluded from record fixtures by design (`seed-corpus-from-record.sh:307`), so its entry could not be checked. Security-relevant declaration changes without an in-diff rationale: MED-003, MED-004.

---

## Verdict

**CHANGES_REQUIRED**

One HIGH (HIGH-001) forces the verdict under the one-way rule. The HIGH is a data-integrity defect in the driver whose output licenses guard deletion, not an exploitable security hole; once fixed and covered by a same-batch re-run test, the remaining findings are MEDIUM/LOW and would not block.

### Next Steps

1. Fix `run-arms.sh` admission (refuse an existing `<arm>/results.jsonl`, or resume) and add the RA test.
2. Decide MED-001, MED-003 and MED-004 with a DEC row each, or revert; pin the fence (or its sha) in the floor.
3. Replace the GNU-only clock at `run-arms.sh:326`/`:366`; subshell the heredoc lib at `guard-yield.sh:470`.
4. Re-run `/review-sprint sprint-1`, then `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":5,"low":11},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-21T10:36:19Z"} -->
