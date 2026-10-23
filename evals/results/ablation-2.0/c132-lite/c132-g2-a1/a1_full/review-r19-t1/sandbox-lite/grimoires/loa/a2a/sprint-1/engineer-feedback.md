All good

Sprint 1 has been reviewed and approved. Observations documented and non-blocking. See Observations below.

# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md (task brief: grimoires/loa/context/task-brief.md)
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)
**Change under review:** pr/head.diff — feat(cycle-129): sprint-255, 81 files

---

## Overall Assessment

The change is coherent and well tested. The guard register (`guard-yield.sh`, `guard-origins.yaml`, `floor.yaml`, the `# @guard` markers in the fence and the validator) is a pure function of the repository and the drift gate holds: on a synthetic head tree the generated hooks table is byte-identical to the one committed in `head/.claude/loa/reference/hooks-reference.md`, `guard-yield.sh --check` reports "in sync (95 guards)", and the `floor.yaml` sha256 pin in `guard-origins.bats` matches the shipped file. The control-arm harness applies toggles to the sandbox copy only and verifies each took effect (exit 2 otherwise); the record-corpus seeder enforces the fix-touches-file rule and keeps labels out of the sandbox; the `kind:` validator is date-gated exactly like the seams rule and its fixtures cover the token grammar edge cases.

Suites run against a synthetic root (framework copy + `pr/head/` files), all green: `tests/unit/{guard-yield,guard-origins,validate-artifact-sprint-kinds,cycle-ratio,loa-status-guards,rule-paths}.bats`, `evals/tests/{arm-toggles,arms-report,seed-corpus}.bats` (no-secrets.sh stubbed), `evals/tests/execute-agent.bats` EA-1..EA-12 (EA-8/EA-9 need `run-eval.sh`'s sandbox and grader, not in the tree). `sprint-seams.bats` SEAMS-9 and `run-arms.bats`, `recall-baseline-freshness.bats`, `eval-recall-grader.bats`, `floor-snapshot.bats`, `prompt-budget.bats` need corpus files, `origin/main` or `tools/check-prompt-budget.sh` that this PR snapshot does not carry and were not run.

No critical or high finding. Three medium and seven low observations follow; the first medium (silent exit of the register generator when its optional classifier library exits) is the one I would fix before the FR-6 classifier lands.

Simplicity pass: `net: 0 lines possible` on the shipped scripts; the awk/jq pipelines are the minimum for what they check. Lean already. Ship.

**Verdict:** APPROVED

---

## Observations

### 1. Robustness — guard register generator

- **MEDIUM** (confidence: medium) `head/.claude/scripts/guard-yield.sh:388` — `source "$HEREDOC_LIB"` runs in the main shell under `set -euo pipefail`. When the optional classifier (or anything it sources) calls `exit`, the generator exits 0 having written nothing: no `grimoires/loa/guards.md`, no `.run/guard-yield.{md,json}`, no "wrote" line, no hooks-table update.
**File:** `head/.claude/scripts/guard-yield.sh:385-404`
**Issue:** Reproduced on the synthetic tree with the later framework's `heredoc-classifier.sh`, which sources the fence hook with `BDB_LIB_ONLY=1`; the head fence has no lib-only mode (`grep -c BDB_LIB_ONLY` = 0 in `head/.claude/hooks/safety/block-destructive-bash.sh`), so the hook runs on an empty stdin and exits, taking the generator with it. `--check` is unaffected (it exits before the yield section), so CI would stay green while `/loa`'s Guards line reads a stale yield.
**Suggestion:** Source and call the classifier in a subshell (or `bash -c`) with the row index piped in, or at least `set +e` around the `source` and treat a non-zero/absent `heredoc_nonexec` as "no classifier"; print the `wrote …` line only after `install_file` succeeds.
**Benefit:** The FR-6 classifier cannot silently disable the yield when it lands.

### 2. Scope — unexplained permission change

- **MEDIUM** (confidence: medium) `head/.claude/skills/implementing-tasks/SKILL.md:28` — `zones.app.permission` moves from `read` to `read-write` in a PR whose description names the guard register, control arms, task kinds and rule files only. `head/.claude/skills/reviewing-code/SKILL.md:135` now makes the frontmatter `zones:` block authoritative, so the widening is now the source of truth. The dissent (DISS-C-002) raised the same point.
**Suggestion:** `SURGICAL:` state the change in the PR description (or a DEC row): /implement does write the App Zone, so the old `read` was wrong, but a permission widening should not travel unannounced inside an unrelated sprint.

### 3. Process — implementation report

- **MEDIUM** (confidence: high) `grimoires/loa/a2a/sprint-1/reviewer.md:1-4` — the report is the PR title plus "81 file(s) in scope"; it carries no `## AC Verification` walkthrough and states no assumptions. The task brief says to skip pre-flight steps that need an implementation report, so this does not decide the verdict here; in a normal sprint it is an automatic CHANGES_REQUIRED (Think Before Coding).

### 4. Low observations

- **LOW** (confidence: high) `head/.claude/scripts/loa-status.sh:952-955` — a present but malformed `.run/guard-yield.json` prints `30 d: no yield file (.run/guard-yield.json)`; the operator is sent to regenerate when the file exists and is unreadable (DISS-C-004). Print `yield file unreadable` for the `-f && !jq` case.
- **LOW** (confidence: medium) `head/evals/harness/run-arms.sh:299-300` — `is_transport_failure` greps `agent-output.json` for `network|socket hang up|5[0-9][0-9] `; a failed trial whose result text mentions networking or an HTTP status is classified as a transport failure, retried after `--retry-wait`, and recorded as `transport_error` rather than `agent_error`. Restrict the grep to `agent-stderr.log` and the CLI's `api_error_status`/`subtype` fields.
- **LOW** (confidence: high) `head/.claude/scripts/guard-yield.sh:466-469` — the burst rule is computed from `block` rows but applied via `replay($burst)` to every in-window row, so an implement-gate `telemetry`/`ask` row that shares a UTC minute with a fixture replay burst is dropped from `telemetry_30d`.
- **LOW** (confidence: medium) `head/evals/harness/run-arms.sh:366-369` — on corpus drift `collect` exits 3 from the parent; `cleanup` kills the running trial jobs but their sandboxes (`sandbox.sh create`) are never destroyed.
- **LOW** (confidence: low) `head/evals/suites/review-recall.yaml:7` / `head/evals/tasks/review-recall/review-pr-11.yaml:5` — the suites and the sixteen `*-pr-1[1-8].yaml` tasks reference `evals/fixtures/review-prs/pr-11…pr-18`, `labels/`, `manifests/`, `record-pairs.tsv`, `corpus.tsv` and `SHA256SUMS`, none of which are in this diff. If they are not already on the branch, `run-arms.sh` refuses (`fixture not found`) and `eval-recall-grader.bats` RG-17 fails. Probably an artefact of how this PR snapshot was cut (the README and `.gitignore:32-33` assume the fixture trees exist); verify before merge.
- **LOW** (confidence: low) `head/.claude/rules/stash-safety.md:2-6` — path-scoping the stash rule to `**/*.sh`, `**/*.bats`, `.claude/scripts/**`, `.claude/hooks/**` means a session on a Python/TS project never loads it, while the hazard (stash push/pop around pre-commit hooks) is shell-usage, not file-type, specific (DISS-C-001). This follows SDD D-3.1 / DEC-0129 and `rule-paths.bats` RP-2 pins the globs, so it is a recorded design decision; noting the residual gap.
- **LOW** (speculative, confidence: low) `head/.claude/skills/planning-sprints/resources/templates/sprint-template.md:58-60` — the task line now ends `⇐ <blockers> · kind: <kind>`; no script in `.claude/scripts` parses `⇐` (the model builds `--deps` from the line), so the risk DISS-C-003 names is to model reading only. A one-line note in the template comment that `· kind:` is not part of the blocker list would remove the ambiguity.

---

## Cross-Model Observations

Adversarial review (`adversarial-review.sh --type review --sprint-id sprint-1 --diff-file pr/head.diff`): status `clean`, primary `gpt-5.5-pro` (no findings), companion `claude-headless` succeeded as an independent voice with five ADVISORY findings DISS-C-001…005, all `anchor_status: valid`. DISS-C-001, -002, -003 and -004 are folded into the Observations above. DISS-C-005 (`head/.claude/hooks/safety/block-destructive-bash.sh:528-529`: replay tagging rides on the inherited `LOA_AUDIT_REPLAY` env var, and pre-change corpus rows carry no flag) is noted as accepted: DEC-0167 chose the env-var marker, and `guard-yield.sh` already excludes unflagged replays by cwd prefix and by the ten-rows-a-minute burst rule (`guard-yield.bats` GY-1). Not counted.

## Rejected dissent payloads

- none — `metadata.rejected_summary` is `[]` and no `adversarial-rejected-review*.jsonl` sidecar exists beside the envelope.

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| Review the pull request | Pass | every one of the 81 files read; scripts exercised on a synthetic head tree |
| Report each defect with file and line | Pass | observations above, cited `head/<path>:<line>` |
| Give a merge verdict | Pass | APPROVED, zero critical/high |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (seed script redacts secret shapes; no-secrets scan over every written file)
- [x] Input validation and sanitization present (ids `^[A-Za-z0-9._/:-]+$`, arm ids, fixture ids, commit ids, canonical hook schema; GFM cells control-stripped)
- [x] Authentication/authorization correct (n/a; permission widening noted under Observation 2)
- [x] No SQL/XSS injection vulnerabilities (jq `--arg` everywhere; `python3 -I`; no eval)
- [x] Dependencies secure (stdlib Python; jq/yq v4 preflight)
- [x] Error messages don't leak sensitive data (yield outputs carry no command text, cwd, host or model; GY-5)

---

## Code Quality Summary

**Strengths:**
- The register is derived, not declared: hooks from `settings.json`, fences from `# @guard` markers cross-checked both ways against `emit_block` sites and `pattern_id` constants, validators from markers; every gap is exit 5 with a named guard.
- Every toggle in `execute-agent.sh` is verified absent after application and the appended system prompt is cut from the toggled sandbox copy.
- Pre-registered thresholds live in the suite files and `arms-report.py` refuses to write a verdict on an incomplete run.

**Areas for Improvement:**
- Run optional foreign libraries in a subshell (Observation 1).
- Name every out-of-scope change in the PR description (Observation 2).

---

## Next Steps

1. `/audit-sprint sprint-1`
2. Before the FR-6 classifier lands, harden the `source` in `guard-yield.sh` (Observation 1).

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":3,"low":7},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T07:21:50Z"} -->
