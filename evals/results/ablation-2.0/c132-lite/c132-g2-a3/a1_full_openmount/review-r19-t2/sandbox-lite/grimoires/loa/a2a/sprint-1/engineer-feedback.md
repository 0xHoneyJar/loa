All good

Observations documented and non-blocking. See Observations below.

# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)

---

## Overall Assessment

The change under review is the pull request in `pr/` (81 files): the guard register with origins and yield (`guard-yield.sh`, `guard-origins.yaml`, `floor.yaml`, fence and validator markers, the generated hooks table, the `/loa` Guards line), pre-registered control arms on a record corpus (`execute-agent.sh` toggles, `run-arms.sh`, `arms-report.py`, `seed-corpus-from-record.sh`, grader 1.2.0 refuted share), task kinds (`validate-artifact.sh` kind rule, `tools/cycle-ratio.sh`, template and glossary), and path-scoped rule files.

The code was read, not the report. Every new script and its tests were read in full; the PR's bats suites were run from an overlay of the head files on this framework checkout (the `/tmp` mount here is noexec, so the overlay sits under the home directory):

| Suite | Result | Note |
|-------|--------|------|
| tests/unit/guard-origins.bats + guard-yield.bats | 26/26 | with the heredoc classifier library absent, as in the PR's own tree (see Observation 1) |
| tests/unit/validate-artifact-sprint-kinds, cycle-ratio, sprint-seams, rule-paths | 34/35 | SEAMS-9 needs the archived cycle-127 plan, not in this change set |
| evals/tests/arms-report.bats + recall-baseline-freshness.bats | 19/20 | BF-4 needs real repository history for the floor-commit descent check |
| evals/tests/execute-agent.bats + arm-toggles.bats | 21/23 | EA-8/EA-9 drive run-eval.sh, whose sandbox/grade dependencies are outside this change set |
| evals/tests/golden-path.bats | 33/33 | |
| tests/unit/loa-status-guards.bats | 3/3 | |

Also verified: `guard-yield.sh` cross-checks the head fence and validator markers against the head origin map with no error; the committed hooks-reference table is byte-identical to what `--hooks-table` generates; `validate-artifact.sh --type glossary` passes on the head GLOSSARY.md; `validate-rule-lifecycle.sh --json` passes on both path-scoped rules; `bash -n` and `py_compile` pass on every new script; the floor.yaml sha256 pin (GO-2) matches.

`reviewer.md` here is the PR description and carries no `## AC Verification` walkthrough; the sprint definition (`grimoires/loa/sprint.md`, task-brief) names the PR files as the entire input and asks for a defect list and a merge verdict, so that rule is recorded as inapplicable rather than applied.

**Task kinds:** the sprint plan under review here has no `kind:` tags (it is the eval harness plan, dated before the rule); not assessed.

**Fast-gate parity:** no formatter or type checker applies to this shell/Python/Markdown change; the repository's fast gates are the bats suites and the prompt budget, covered above.

No critical or high finding. Three medium findings sit in Observations with concrete failure scenarios; the first two should be fixed before Sprint 2 relies on the host yield to judge guards. Seven low findings. Approval is the reviewer's call under the one-way rule and is given.

**Verdict:** APPROVED

---

## Observations

### 1. Silent exit when the optional heredoc classifier is sourced

- **MEDIUM** (confidence: high) `head/.claude/scripts/guard-yield.sh:470` — the optional classifier library is sourced in the main shell; a library whose load path exits terminates guard-yield.sh with status 0, no diagnostic, and neither `grimoires/loa/guards.md` nor the yield files written.
**File:** `head/.claude/scripts/guard-yield.sh:468-483`
**Suggestion:** The FR-6 classifier (`.claude/scripts/lib/heredoc-classifier.sh`, present in this checkout) sources `block-destructive-bash.sh` with `BDB_LIB_ONLY=1`; this PR's fence (`head/.claude/hooks/safety/block-destructive-bash.sh`) has no library-only mode, so the fence runs as a hook on empty input and exits, taking guard-yield.sh with it. Reproduced: with the library present, `bash guard-yield.sh` printed nothing, exited 0 and wrote nothing (7 of 11 guard-yield.bats cases fail); with the library moved aside, 26/26 pass. Probe the library in a subshell first (`( source "$HEREDOC_LIB" && declare -F heredoc_nonexec ) >/dev/null 2>&1`), or run the classification in a subshell, and fail loudly (exit 3) if the probe exits.
**Benefit:** The register generator never reports success without writing its outputs; `--check` in CI is unaffected today because it exits before this stage, which is why CI would not catch it.

### 2. The 30-day window assumes rotated segments that nothing writes

- **MEDIUM** (confidence: high) `head/.claude/scripts/guard-yield.sh:443` — the yield reads `.run/audit.jsonl` and `.run/audit.jsonl.*`, but the only rotation in the repository (`.claude/hooks/audit/mutation-logger.sh`, "if file exceeds 10MB, keep last 1000 entries") truncates in place and never creates a segment; after a truncation the 30-day counts silently drop every earlier block while the JSON still reports `window_days: 30` and `audit_segments: 1`.
**File:** `head/.claude/scripts/guard-yield.sh:26-27, 443-455, 551-553`
**Suggestion:** Detect truncation (the earliest parseable row's `ts` inside the window) and write `window_effective_from` or `truncated: true` into the yield header and the `/loa` line, or make mutation-logger rotate into `audit.jsonl.1`. The glob also matches the transient `audit.jsonl.tmp` written during that truncation, which would be read as a segment and double-count rows.
**Benefit:** The yield is the figure Sprint 2 uses to decide whether a non-floor guard earns its keep; an undercount biases toward deletion and today carries no marker.

### 3. SURGICAL: unexplained zone-permission widening

- **MEDIUM** (confidence: high) `head/.claude/skills/implementing-tasks/SKILL.md:28` — the app-zone permission changes from `read` to `read-write` in a PR about the guard register, control arms, task kinds and rule paths; the PR description does not mention it and no DEC row accompanies it, while CLAUDE.loa.md still describes the App zone as confirm-writes.
**File:** `head/.claude/skills/implementing-tasks/SKILL.md:28`
**Suggestion:** No script reads a skill's `zones:` block (checked `.claude/scripts` and `.claude/hooks`), so the effect is prose-only and arguably corrects a declaration that contradicted the skill's purpose; it still belongs in the PR description with a DEC row, or in its own change, together with the matching `reviewing-code/SKILL.md` wording change ("Zones per the frontmatter").
**Benefit:** Keeps the frontmatter-is-truth change reviewable on its own terms; the adversarial companion raised the same point (DISS-C-003).

### 4. Transport-failure classifier over-matches

- **LOW** (confidence: medium) `head/evals/harness/run-arms.sh:314` — the regex alternative `5[0-9][0-9] ` is grepped across `agent-stderr.log` and `agent-output.json`; any three-digit number beginning with 5 followed by a space (a token count, a duration, a line number in a stack trace) classifies an agent error as a transport error and triggers the retry.
**File:** `head/evals/harness/run-arms.sh:309-317`
**Suggestion:** Anchor the status pattern (`HTTP/[0-9.]+ 5[0-9][0-9]`, `"status": 5[0-9][0-9]`, `api_error_status`) or drop the bare form.
**Benefit:** A retried agent error inflates `attempts` and hides a real agent failure behind a transport label.

### 5. Fence floor rows pinned only through the corpus

- **LOW** (confidence: low) `head/.claude/data/floor.yaml:46` — the sixteen `fence:*` floor rows are protected by floor_corpus rows and the FS-4 call-site list, not by pinning the fence's bytes as `floor_files` does for the gate and policy rows; a weakening of FR-SZ or FR-SZ2 matching that no existing corpus row exercises passes `floor-snapshot.bats`.
**File:** `head/.claude/data/floor.yaml:46-58`
**Suggestion:** State the asymmetry in the floor.yaml header (this very PR edits the fence to add markers, so pinning its bytes would have failed here), or pin the fence and accept deliberate pin updates. Raised by the adversarial companion (DISS-C-001).
**Benefit:** Readers of the floor know exactly what "the fence cannot be weakened" is backed by.

### 6. Path scoping narrows where the stash rule is loaded

- **LOW** (confidence: medium) `head/.claude/rules/stash-safety.md:2` — with `paths:` the rule is loaded only when a `*.sh`, `*.bats`, `.claude/scripts/**` or `.claude/hooks/**` file is read or edited; a pure-Bash session that runs `git stash push … | tail -1` without touching such a file never loads it and relies on fence FR-1.2b alone.
**File:** `head/.claude/rules/stash-safety.md:1-11`
**Suggestion:** This is the SDD D-3.1 / DEC-0129 decision and the `no_rule_files` arm exists to measure it; add one sentence to the rule body saying the scoping is deliberate and that FR-1.2b is the always-on floor. Raised by the adversarial companion (DISS-C-004).
**Benefit:** The next reader does not re-open the question.

### 7. CI drift gate depends on a file outside this change set

- **LOW** (confidence: low) `head/.github/workflows/bats-tests.yml:159` — `guard-yield.sh --check` exits 1 unless a tracked `grimoires/loa/guards.md` exists and matches the generator; that file is not among the 81 files here (the record-fixture scope excludes `grimoires/`), so the gate's green state cannot be verified from the PR alone.
**File:** `head/.github/workflows/bats-tests.yml:155-159`
**Suggestion:** Confirm `grimoires/loa/guards.md` is committed on the branch and that `guard-origins.bats` GO-9 passes there (in this overlay it passes once the register is generated).
**Benefit:** Avoids a red CI on the first run of the new step.

### 8. The `kind:` token sits after the blockers segment

- **LOW** (confidence: medium) `head/.claude/skills/planning-sprints/resources/templates/sprint-template.md:58` — the template comment says the `⇐` segment becomes the bead `--deps` flag, and the new ` · kind: …` token now follows it; no script parses `⇐` (only prose does, verified), so the reading is the model's, but the comment does not say where the blockers segment ends.
**File:** `head/.claude/skills/planning-sprints/resources/templates/sprint-template.md:52-60`
**Suggestion:** Extend the comment: "the blockers segment ends at ` · kind:`". Raised by the adversarial companion (DISS-C-002).
**Benefit:** Prevents `none · kind: mechanical` being passed as a dependency list.

### 9. Prompt-budget constants restated without the tool in scope

- **LOW** (confidence: low) `head/.github/workflows/check-prompt-budget.yml:5` — the header comment and `prompt-budget.bats` PB-10 now state protocols ≤ 160,000 B (warn > 114,688 B); `tools/check-prompt-budget.sh` is not in this change set, so the constants cannot be confirmed here and PB-10 is the only proof they agree.
**File:** `head/.github/workflows/check-prompt-budget.yml:5`, `head/tests/unit/prompt-budget.bats:112-124`
**Suggestion:** None beyond running PB-10 on the branch; recorded so the mismatch class is visible.
**Benefit:** A stale header comment is what PB-10 was written to catch.

### 10. Segment glob catches the rotation temp file

- **LOW** (confidence: medium) `head/.claude/scripts/guard-yield.sh:443` — `"$AUDIT_LOG".*` matches `audit.jsonl.tmp` while mutation-logger is mid-truncation, so a run that coincides with a rotation counts its rows twice.
**File:** `head/.claude/scripts/guard-yield.sh:443-447`
**Suggestion:** Match `"$AUDIT_LOG".[0-9]*` only.
**Benefit:** Segment arithmetic stays exact; folds into Observation 2.

---

## Rejected dissent payloads

None. The envelope `grimoires/loa/a2a/sprint-1/adversarial-review.json` records `rejected_summary: []`, `rejected_count: 0`, `rejected_sidecars: []`, and no `adversarial-rejected-review*.jsonl` sits beside it. Status `clean`; the primary voice (gpt-5.5-pro) returned no finding at the BLOCKING/ADVISORY bar, the companion voice (claude-headless) returned four ADVISORY findings (DISS-C-001 … 004), each triaged above as Observations 5, 8, 3 and 6.

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| Report each defect the change introduces with file and line | Pass | Ten observations above, each cited `head/<path>:<line>`; mirrored one-per-line in `review.md` at the repository root per the task brief |
| Give a merge verdict | Pass | APPROVED; no critical or high finding |
| Guard register: every guard has an origin row, floor set equals floor.yaml | Pass | guard-origins.bats 15/15; head fence and validator markers cross-check clean; floor sha256 pin matches |
| Host yield: replay exclusion, FP heuristic, --check gate, privacy | Pass with Observations 1, 2, 10 | guard-yield.bats 11/11 with the classifier library absent |
| Control arms applied to the sandbox only, verified, recorded | Pass | arm-toggles.bats 11/11, execute-agent.bats EA-11/EA-12 pass |
| Record corpus seeding, labels hidden, approval gate | Read, not run | seed-corpus.bats needs `no-secrets.sh`, outside this change set; the Python was read in full |
| Pre-registered verdict report | Pass | arms-report.bats 7/7 |
| Task kinds rule and release-notes lines | Pass | validate-artifact-sprint-kinds.bats 11/11, cycle-ratio.bats 6/6, glossary validator passes |
| Path-scoped rule files | Pass | rule-paths.bats 6/6, validate-rule-lifecycle passes |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (seed script redacts secret shapes and runs no-secrets.sh over every written file; test key is assembled at runtime)
- [x] Input validation at trust boundaries (guard-yield rejects non-canonical hook commands, `..` paths and symlinks leaving `.claude/`; run-arms validates every argument; seed script refuses unsafe paths and `--out` outside the corpus)
- [x] No command text, cwd, hostname or model name in register or yield outputs (GY-5)
- [x] Python invoked with `-I` where it reads untrusted trees (seed script, arms-report via report.sh, grader parser)
- [x] Sandbox toggles never touch the source tree (AT-4, AT-6, RA-2 verify)
- [x] Error messages do not leak sensitive data

---

## Code Quality Summary

**Strengths:**
- The register is a pure function of the repository with an independent bats enumeration that would catch a generator bug; every failure mode has a fixture test.
- Control arms are applied after materialisation, verified absent, and refuse to run as a silent baseline; the arm comparison records source commit, arm id, models used and refusal fallbacks.
- The record-corpus labelling rule (fix touches the cited file) and the hidden labels directory are enforced by code and tests, not convention.
- Complexity: the long jq programs in guard-yield.sh are each a single named stage with comments; `validate_sprint_kinds` mirrors `validate_sprint_seams` exactly. Lean already. Ship.

**Areas for Improvement:**
- Sourcing an optional library in the main shell (Observation 1) and assuming a rotation scheme the repository does not have (Observation 2) are the two places the new tool trusts its environment without checking.
- One out-of-theme permission change travelled with the PR (Observation 3).

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":3,"low":7},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T13:45:00Z"} -->
