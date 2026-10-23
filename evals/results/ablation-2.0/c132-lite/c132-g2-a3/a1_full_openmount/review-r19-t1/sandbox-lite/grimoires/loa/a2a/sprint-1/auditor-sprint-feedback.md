# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Change under audit:** `pr/head.diff` — sprint-255, "guard register with origin and yield, pre-registered control arms on a record corpus, task kinds, path-scoped rule files" (81 files, 8,031 diff lines)

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

The change adds four things: a guard register generator (`guard-yield.sh`) with its origin map and floor file, a `kind:` tag rule for sprint task lines plus a release-notes ratio tool, pre-registered control arms for the eval harness (toggles in `execute-agent.sh`, the `run-arms.sh` batch driver, `arms-report.py`, the record-corpus seeder), and `paths:` scoping on two rule files. The fence hook (`block-destructive-bash.sh`) changes only by comment markers and a `replay` flag; no pattern, action or exit code moved. Secrets, injection and privacy are handled well: ids are regex-gated before they reach a path or jq, every embedded Python runs under `python3 -I`, the yield outputs carry no command, cwd or model text (probed), and the seeder fails closed when its secret scanner is missing.

The blocking defect is in the control-arm contract. The harness states that "a toggle that cannot take effect is exit 2 (an arm never silently runs as its baseline)" (`head/evals/harness/execute-agent.sh:65-66`) and the README repeats it ("fails the trial (exit 2) when a toggle cannot take effect", `head/evals/README.md:509-510`). The `rule_files` toggle does not honour it, and I found two more routes to the same null experiment: a declared arm whose suite entry has no `toggles` key resolves to `{}` and runs as the baseline under its own id, and an ambient `LOA_EVAL_ARM_TOGGLES` in the operator's shell overrides every arm of a batch. Because the pre-registered verdict ("no recall loss") is documented as licence to remove a control, a null experiment is the most expensive silent failure this harness can have. Alongside: the guard-register generator can exit 0 having written nothing (reproduced), the floor leaves the fence's hook registration unprotected while the CI backstop for that gap skips on every pull request, and the new CI gates do not run for pull requests that touch only the files they guard.

What was executed, not just read: the head files were composed over a framework checkout and the new scripts and suites were run. `guard-yield.sh --hooks-table` regenerates the committed hooks table byte for byte and `--check` then reports in sync (95 guards); `guard-yield.bats` 11/11, `guard-origins.bats` 15/15, `validate-artifact-sprint-kinds.bats` 11/11, `rule-paths.bats` 6/6, `cycle-ratio.bats` 6/6, `loa-status-guards.bats` 3/3, `arm-toggles.bats` 11/11, `arms-report.bats` 7/7, `execute-agent.bats` 10/12 (EA-8/9 need `review-pr-09`, not in this change set), `recall-baseline-freshness.bats` 12/13 (BF-4 needs the committed baseline), `eval-recall-grader.bats` 26/28 (RG-16/17 need the review-prs manifests), `sprint-seams.bats` 11/12 (SEAMS-9 needs the cycle-127 fixture). `floor-snapshot.bats` skipped all four tests (no `origin/main` in the composed tree), and `run-arms.bats`, `seed-corpus.bats` and `prompt-budget.bats` need fixtures or tools outside the change set (`review-prs/pr-01`, `no-secrets.sh`, `tools/check-prompt-budget.sh`). Three defects below were reproduced directly: the generator's silent exit, the `.lock` segment and the numeric `pattern_id` abort.

**Process notes.** (1) The review gate verdict for this sprint is CHANGES_REQUIRED, not "All good"; the skill's Phase 0 would stop here. The task brief mandates an autonomous audit of the frozen PR, so the audit ran and this deviation is recorded. (2) No documentation-coherence subagent reports exist in this frozen fixture; the documentation checks below were done by hand. (3) `grimoires/loa/known-failures.md` is absent (the surface is degraded); triage ran without it.

**Security Issues Found:**

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 13 |
| Low | 22 |

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] `rule_files` control-arm toggle runs the arm as its baseline when the rules are absent

**Severity:** HIGH (confidence: high) — confirmed independently; the review's Changes Required §1
**File:** `head/evals/harness/execute-agent.sh:266` (the loop at 260-267; the contract at 65-66; rule materialisation at 146)
**Issue:** The toggle removes the two rule files only if they exist, then records success either way:
```bash
for r in stash-safety.md skill-invariants.md; do
  if [[ -e "$WORKSPACE/.claude/rules/$r" ]]; then rm -f "$WORKSPACE/.claude/rules/$r"; gone="$gone $r"; fi
  [[ ! -e "$WORKSPACE/.claude/rules/$r" ]] || { echo "ERROR: rule_files toggle: $r still present" >&2; return 2; }
done
_evidence rule_files "removed:${gone:- none present}"
```
Rules are copied into the sandbox only when the prompt tree has them: `if [[ -d "$PROMPT_TREE/.claude/rules" ]]` (`head/evals/harness/execute-agent.sh:146`). A `--source-commit` that predates the two rule files, or a tree without `.claude/rules/`, makes the toggle a no-op; the post-check at line 264 asserts absence, which is then trivially true. The other three toggles (`companion_voice` 243-247, `karpathy_block` 249-253, `audit_delta_instruction` 271-273) return 2 when they find nothing to remove. `arm-toggles.bats` AT-9 (170-179) covers that fail-closed path for them, not for `rule_files`.
**Impact:** The `no_rule_files` arm runs identically to `baseline`; `arms-report.py` reads "no recall loss"; `arm_evidence` never reaches the report. The README says the verdict may license removing a control, so a null experiment licenses deleting the two rule files. This is exactly the failure the "never silently runs as its baseline" invariant exists to prevent.
**Fix:**
```bash
[[ -n "$gone" ]] || { echo "ERROR: rule_files toggle: no rule file present in the sandbox .claude/rules/" >&2; return 2; }
_evidence rule_files "removed:$gone"
```
and add the AT-9-style case for this toggle.
**Reference:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html

---

## Medium Priority Issues

### [MED-001] A declared arm with no `toggles` key resolves to `{}` and runs as the baseline under its own id

- **File:** `head/evals/harness/execute-agent.sh:178-186` (confidence: high)
- **Issue:** `t="$(ARM="$ARM" yq -o=json -I=0 '[.ab.arms[] | select(.id == strenv(ARM))][0].toggles // {}' "$suite_file")"` followed by `if [[ "$found" -eq 0 || -z "$t" || "$t" == "null" ]]`. A found arm whose entry lacks `toggles:` (or spells it `toggle:`) yields `found=1`, `t={}`, so `apply_toggles` loops zero times and the trial exits 0. Same contract violated as HIGH-001, by configuration rather than by tree state. AT-10 (`arm-toggles.bats`) covers an undeclared arm and an unknown toggle, not an empty toggle set.
- **Scenario:** A future suite edit mistypes the key; a whole batch of "arms" runs identically and the report prints a clean verdict.
- **Fix:** After resolution: `[[ "$ARM" == baseline || "$t" != "{}" ]] || { echo "ERROR: arm '$ARM' declares no toggles" >&2; return 2; }`.
- **Reference:** CWE-754 — https://cwe.mitre.org/data/definitions/754.html

### [MED-002] An ambient `LOA_EVAL_ARM_TOGGLES` overrides every arm of a `run-arms.sh` batch

- **File:** `head/evals/harness/run-arms.sh:336-340` with `head/evals/harness/execute-agent.sh:163-167` (confidence: medium)
- **Issue:** `resolve_toggles` prefers the environment whenever it is non-empty: `if [[ -n "${LOA_EVAL_ARM_TOGGLES:-}" ]]; then ... return 0; fi`. The batch driver sets `LOA_EVAL_ARM="$arm" LOA_EVAL_SUITE_FILE="$SUITE_FILE" LOA_EVAL_SOURCE_COMMIT="$SRC_FULL" LOA_AUDIT_REPLAY=1` for each trial but never clears `LOA_EVAL_ARM_TOGGLES`. `run-arms.bats:31` unsets it in `setup()`, so the suite cannot observe this.
- **Scenario:** An operator exports the variable for an AT-11-style manual trial, then launches a batch: `baseline`, `no_karpathy` and `no_rule_files` all run with the exported toggle set while every row still carries the plan's arm id. `arms-report.py` keys on `arm` (never on `arm_toggles`) and compares identical configurations. The rows do record `arm_toggles`, so the error is detectable after the fact, which is why this is MEDIUM rather than HIGH.
- **Fix:** Pass `LOA_EVAL_ARM_TOGGLES=` explicitly in the per-trial environment at line 336 (or `unset` it at batch start), and have `arms-report.py` refuse when two arms in one batch share a toggle set.
- **Reference:** CWE-15 External Control of System or Configuration Setting — https://cwe.mitre.org/data/definitions/15.html

### [MED-003] `audit_delta_instruction` removes only the first matching paragraph and never verifies the needle is gone

- **File:** `head/evals/harness/execute-agent.sh:216-224` and `:271-273` (confidence: medium)
- **Issue:** The embedded Python exits on the first hit: `if needle.lower() in paras[i].lower(): removed = paras[i]; del paras[i:i + 2]; ...; sys.exit(0)`. The toggle then records bytes removed without re-checking the file. The header says every toggle "is verified absent afterwards" (lines 64-65); `companion_voice` (247) and `karpathy_block` (251) are, this one is not.
- **Scenario:** A later SKILL.md mentions "look for what the review did not" in an introductory sentence and again in the operative paragraph; the intro is dropped, the arm runs with the instruction intact, and the report reads a clean delta.
- **Fix:** After `_drop_paragraph`, `grep -qiF` both needles in `$s` and `return 2` on a hit, or remove every matching paragraph.
- **Reference:** CWE-393 Return of Wrong Status Code — https://cwe.mitre.org/data/definitions/393.html

### [MED-004] The refuted-share rule is silently skipped when `findings_cited` is absent, yet the verdict can read "no recall loss"

- **File:** `head/evals/harness/arms-report.py:296` (confidence: high)
- **Issue:** `if rs is not None and base_ref is not None and rs > base_ref + refuted_rise:` — a `None` share passes. The two recall rules treat `None` as a violation (`if hi is None or hi > max_drop`, line 292; `if mn is None or base_min is None or ...`, line 294); the third does not. The header promises "no recall loss: every rule holds" (lines 24-27). `arms-report.bats` `row()` always supplies `cited=4` (31-43), so the path is untested.
- **Scenario:** Rows graded by a grader version without `findings_cited`, or an arm whose completed trials cite nothing, get a verdict with one of three pre-registered rules unevaluated.
- **Fix:** Treat `rs is None or base_ref is None` as a coverage reason (inconclusive), mirroring lines 292 and 294.
- **Reference:** CWE-754 — https://cwe.mitre.org/data/definitions/754.html

### [MED-005] Re-running into an existing batch with a different arm or fixture set overwrites `MANIFEST.json` and orphans the earlier arms' results

- **File:** `head/evals/harness/run-arms.sh:251-257` and `:264-265` (confidence: high)
- **Issue:** Only source and model are compared: `[[ "$prev_src" == "$SRC_FULL" && "$prev_model" == "$MODEL" ]] || die ...`; then `write_manifest "$BATCH_DIR/MANIFEST.json" false` and `DONE=() FAILED=() PLANNED=()` reset the counters. RA-5 (`run-arms.bats:144-150`) tests only the model mismatch.
- **Scenario:** Batch B runs `baseline,no_karpathy`; the operator re-runs B with `--arms no_rule_files` to add an arm. The manifest now lists one arm, `arms-report.py:206-211` reads `results.jsonl` only for arms the manifest names, the batch's own baseline vanishes from the report (or is silently excluded when another batch supplies one) and `STATUS.json` loses the earlier counters.
- **Fix:** Refuse (or merge) when `.arms`, `.fixtures` or `.trials` differ from the standing manifest; never reset counters for arms already present.
- **Reference:** CWE-20 Improper Input Validation — https://cwe.mitre.org/data/definitions/20.html

### [MED-006] `verify_corpus` hashes only the files `SHA256SUMS` lists; an unlisted file in a fixture is copied into every sandbox as "verified"

- **File:** `head/evals/harness/run-arms.sh:143-149` (confidence: high)
- **Issue:** `for line in raw.decode("utf-8").splitlines(): ... digest, rel = line.split("  ", 1) ... if not os.path.isfile(p) or hashlib.sha256(...) != digest: bad.append(rel)`. There is no walk of the fixture directory, unlike the seeder's own check (`head/evals/harness/seed-corpus-from-record.sh:155-160`, which flags "not listed"). The header promises a drift "stops the batch (state failed, exit 3)" (lines 17-21), and every row asserts `fixture_verified: true`.
- **Scenario:** A stray `NOTES.md` or second instructions file left in `pr-11/` reaches the sandbox of every trial; the model may read it; the rows claim the frozen fixture.
- **Fix:** Walk `corpus/<only>/` (or the whole corpus) in `verify_corpus` and treat unlisted regular files as drift.
- **Reference:** CWE-354 Improper Validation of Integrity Check Value — https://cwe.mitre.org/data/definitions/354.html

### [MED-007] The generator sources an optional library in-process; a library whose top level exits ends the run with exit 0 and nothing written (reproduced)

- **File:** `head/.claude/scripts/guard-yield.sh:470` (confidence: high)
- **Issue:** `if source "$HEREDOC_LIB" 2>/dev/null && declare -F heredoc_nonexec >/dev/null; then`. The library named at line 118 (`.claude/scripts/lib/heredoc-classifier.sh`) is not in this change set; the later-cycle file by that name sources the fence in "library mode", and this PR's fence has no such mode, so sourcing it runs the whole hook, which reads an empty stdin and exits 0.
- **Reproduced:** with the classifier present, `guard-yield.sh --hooks-table` printed only the "no audit log" warning, exited 0, and wrote neither `grimoires/loa/guards.md` nor `.run/guard-yield.json`; with the classifier moved aside, the same command wrote both and `--check` reported "in sync (95 guards)". The script trusts a file it does not own; a top-level `exit`, `set -e` failure or `return` in that file terminates the generator while the exit code says success, and `--check` in CI keeps passing because it never reaches the yield section.
- **Fix:** Evaluate the classifier in a subshell (`( source "$HEREDOC_LIB"; ... )` or a `bash -c` helper that prints the indices) and assert `[[ -f "$YIELD_DIR/guard-yield.json" ]]` before the success line.
- **Reference:** CWE-829 Inclusion of Functionality from Untrusted Control Sphere — https://cwe.mitre.org/data/definitions/829.html ; CWE-390 Detection of Error Condition Without Action — https://cwe.mitre.org/data/definitions/390.html

### [MED-008] Floor gap: the fence's hook row is `floor: false` while its sixteen fence rows are `floor: true` (confirmed by cross-model review, both rounds)

- **File:** `head/.claude/data/guard-origins.yaml:163` with `head/.claude/data/floor.yaml:14-30, 46-50` (confidence: medium)
- **Issue:** `- id: hook:safety/block-destructive-bash.sh ... floor: false ... registrations: ["PreToolUse:Bash"]`. `floor_guards` lists `fence:FR-1.2b` and the fifteen `fence:FR-SZ*` rows but not the hook that arms them; `floor_files` pins `verdict-derive.sh`, `adversarial-review-gate.sh`, `settings.deny.json` and `user-invoked-commands.txt`, not the fence script or `.claude/settings.json`.
- **Scenario:** A change drops the `PreToolUse:Bash` registration from `settings.json` and the hook row from the map together. `guard-yield.sh --check` passes (no dangling row), `guard-origins.bats` passes (floor rows unchanged, markers still resolve), the corpus replay passes (it executes the script directly). Only `floor-snapshot.bats` FS-3 would catch it, and that suite skips in CI (MED-009). All sixteen floor fences go inert while every floor check stays green.
- **Fix:** Add `hook:safety/block-destructive-bash.sh` (with its registration) to `floor_guards` and the fence script and `.claude/settings.json` (or a jq-extracted digest of its `hooks` and `permissions.deny`) to `floor_files`; or make `guard-yield.sh` refuse when a floor fence's owning hook has no registration.
- **Reference:** CWE-693 Protection Mechanism Failure — https://cwe.mitre.org/data/definitions/693.html

### [MED-009] `floor-snapshot.bats` skips on every CI pull-request run and is vacuous on push

- **File:** `head/tests/unit/floor-snapshot.bats:17-19` with `head/.github/workflows/bats-tests.yml:90` (confidence: high)
- **Issue:** `if ! git -C "$ROOT" rev-parse --verify -q 'origin/main^{commit}' >/dev/null 2>&1; then skip "origin/main is not reachable ..."`. The checkout step `- uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1` sets no `fetch-depth`, so a pull-request checkout has depth 1 and no `origin/main`; all four tests skip (green). On `push: main`, HEAD equals `origin/main`, so byte-identity holds trivially. In my composed tree all four skipped for the same reason.
- **Scenario:** FS-1 (floor files unchanged), FS-2 (floor corpus rows), FS-3 (hook registrations unchanged) and FS-4 (fence call sites) are the only mechanical backstop for MED-008 and for the floor-files promise in `floor.yaml:45`; none of them ever bites.
- **Fix:** `fetch-depth: 0` (or a `git fetch origin main:refs/remotes/origin/main` step) in the workflow, and fail instead of skip when `CI` is set and the ref is missing.
- **Reference:** CWE-693 — https://cwe.mitre.org/data/definitions/693.html

### [MED-010] The new CI gates do not run for pull requests that touch only the files they guard

- **File:** `head/.github/workflows/bats-tests.yml:57` (pull_request filter; the push filter at :31 has the same gap) (confidence: high)
- **Issue:** The `paths:` lists include `.claude/data/schemas/**`, `.claude/scripts/**`, `.claude/hooks/**`, `.claude/settings.json`, `tests/unit/**` but not `.claude/data/guard-origins.yaml`, `.claude/data/floor.yaml`, `.claude/loa/reference/hooks-reference.md`, `grimoires/loa/guards.md`, `.claude/rules/**` or `tools/cycle-ratio.sh`.
- **Scenario:** A PR that only flips a `floor:` flag or hand-edits the generated hooks table skips the job; `guard-yield.sh --check` (158-159), `guard-origins.bats` (sha pin GO-2, floor set GO-7), `floor-snapshot.bats` and `rule-paths.bats` are all bypassed, and the drift surfaces on the next unrelated script PR, blaming the wrong author.
- **Fix:** Add those paths to both filter lists.
- **Reference:** CWE-693 — https://cwe.mitre.org/data/definitions/693.html

### [MED-011] `stash-safety.md` is scoped to shell-file sessions although it governs a Bash command issued in any session (confirmed by cross-model review, both rounds)

- **File:** `head/.claude/rules/stash-safety.md:2-6` (confidence: medium)
- **Issue:** `paths: - "**/*.sh" - "**/*.bats" - ".claude/scripts/**" - ".claude/hooks/**"`. The rule warns against `git stash push/pop` wrapped with output swallowing, which the model can issue while editing only Markdown or YAML; in those sessions the rule is out of context and only the FR-1.2b fence (the swallowed-output shapes it matches) remains. The existing precedents (`zone-system.md`, `zone-state.md`) scope by the files the rule is about; this rule is about a command.
- **Fix:** Keep the rule unscoped, or add a broad glob and record in DEC-0129 that the unswallowed guidance is now fence-only and covered by the `no_rule_files` arm.
- **Reference:** CWE-693 — https://cwe.mitre.org/data/definitions/693.html

### [MED-012] `suite_report` is 168 lines, nested more than three deep, with no early return

- **File:** `head/evals/harness/arms-report.py:176-343` (confidence: high)
- **Issue:** `for a in order` → `else` → `if reasons ... else` → `if not violated ... elif`. The per-arm verdict (247-305) and the table and missed-labels rendering share one function; MED-004 sits in the deepest branch, which is where such gaps hide.
- **Fix:** Split the verdict into a function returning `(verdict, reasons)` and the rendering into another.
- **Reference:** CWE-1121 Excessive McCabe Cyclomatic Complexity — https://cwe.mitre.org/data/definitions/1121.html

### [MED-013] `validate_sprint_kinds` is 89 lines and its awk task-line scanner is duplicated in `tools/cycle-ratio.sh`; the two already share a gap

- **File:** `head/.claude/scripts/validate-artifact.sh:1004-1020` and `head/tools/cycle-ratio.sh:87-98` (confidence: high)
- **Issue:** Both carry the same `insp`/`sec` state machine and token regex (`/^## / { insp = ($0 ~ /^## Sprint [0-9]/); ...`, `/^### Technical Tasks[[:space:]]*$/`, `!sec || $0 !~ /^- \[[ xX]\] /`). LOW-020 shows the same blind spot in both, which is what duplication produces.
- **Fix:** Factor the scanner into `lib/` beside `md-fence.awk` so the validator and the release-notes tool cannot drift.
- **Reference:** CWE-1041 Use of Redundant Code — https://cwe.mitre.org/data/definitions/1041.html

---

## Low Priority Issues

### [LOW-001] A numeric `pattern_id` aborts the whole yield join (reproduced)
- **File:** `head/.claude/scripts/guard-yield.sh:523` (confidence: high)
- **Issue:** `then ["fence:" + .pattern_id]` after a guard that only tests `tostring`. One row with `"pattern_id": 5` gives `jq: error ... string ("fence:") and number (5) cannot be added` and exit 3 ("the audit log could not be joined").
- **Fix:** `["fence:" + (.pattern_id | tostring)]`.
- **Reference:** CWE-704 Incorrect Type Conversion — https://cwe.mitre.org/data/definitions/704.html

### [LOW-002] Lock and temp files beside the audit log are read as rotated segments (reproduced)
- **File:** `head/.claude/scripts/guard-yield.sh:443` (confidence: high)
- **Issue:** `for f in "$AUDIT_LOG" "$AUDIT_LOG".*; do`. With an `audit.jsonl.lock` holding one junk line and one block row, the run reported `audit_segments: 2`, `audit_rows_unparseable: 1` and credited the lock's row to `fence:P4`.
- **Fix:** Restrict to rotated segments, e.g. `"$AUDIT_LOG".[0-9]*`.
- **Reference:** CWE-20 — https://cwe.mitre.org/data/definitions/20.html

### [LOW-003] Header says one hooks row per unique script; the generated table emits one row per registration
- **File:** `head/.claude/scripts/guard-yield.sh:8` (confidence: high)
- **Issue:** `# ... one row per unique script` versus `render_hooks_block` (`($hooks[] | ...)`, line 383), which GY-8 asserts emits `write-mutation-logger.sh` twice.
- **Fix:** Correct the comment.
- **Reference:** CWE-1116 Inaccurate Comments — https://cwe.mitre.org/data/definitions/1116.html

### [LOW-004] Transport-failure detection greps the model's own output
- **File:** `head/evals/harness/run-arms.sh:314-315` (confidence: medium)
- **Issue:** `is_transport_failure` matches `network` or `5[0-9][0-9] ` anywhere in `agent-output.json`, which `execute-agent.sh:358-362` writes verbatim from the `result` event including the model's final text. A review that says "network" or cites "line 503 " turns a genuine agent failure into a `--retry-wait` (default 300 s) retry. Only the stub's stderr "socket hang up" is tested (`claude-stub.sh:26`).
- **Fix:** Anchor the patterns to the CLI's own error lines in stderr.
- **Reference:** CWE-185 Incorrect Regular Expression — https://cwe.mitre.org/data/definitions/185.html

### [LOW-005] `run_trial` is 66 lines with a four-deep retry loop
- **File:** `head/evals/harness/run-arms.sh:319-384` (confidence: high)
- **Fix:** Extract the attempt body.
- **Reference:** CWE-1121 — https://cwe.mitre.org/data/definitions/1121.html

### [LOW-006] A present but malformed `guard-yield.json` is reported as "no yield file"
- **File:** `head/.claude/scripts/loa-status.sh:956` (confidence: high)
- **Issue:** Every `jq -er` failure at 953 falls to `echo -e "${BOLD}Guards:${NC} $counts · 30 d: no yield file (.run/guard-yield.json) · $hint"`; LSG-3 pins the wording. A writer/reader schema drift reads as a missing file and the operator regenerates in vain.
- **Fix:** Say "unreadable yield file" when `-f "$yf"`.
- **Reference:** CWE-390 — https://cwe.mitre.org/data/definitions/390.html

### [LOW-007] App zone widened from `read` to `read-write` with no rationale in the PR (cross-model DISS-C-002, kept LOW)
- **File:** `head/.claude/skills/implementing-tasks/SKILL.md:28` (confidence: high)
- **Issue:** `permission: read` → `permission: read-write` in a PR about the guard register. No script consumes `zones.*.permission` (declarative only; `run-bridge/SKILL.md:28` already says `read-write`), so the damage is a misdocumented boundary, not a bypass; the GLOSSARY in the same diff still says the App zone "needs confirmation before a write". SURGICAL: state it in the PR or move it to its own change.
- **Reference:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html

### [LOW-008] Budget constants in the workflow comment changed while the tool is not in the change set
- **File:** `head/.github/workflows/check-prompt-budget.yml:5` (confidence: low)
- **Issue:** `protocols total ≤ 160,000 B (warn > 114,688 B)` replaced `200,000 / 143,360`. PB-10 (`head/tests/unit/prompt-budget.bats:113-124`) pins the comment to `tools/check-prompt-budget.sh`, which is outside this fixture; a defect only if the tool still carries the old numbers. Unable to assess here.
- **Reference:** CWE-1116 — https://cwe.mitre.org/data/definitions/1116.html

### [LOW-009] Replay tagging trusts the ambient `LOA_AUDIT_REPLAY` with no scope (cross-model DISS-C-003, confirmed)
- **File:** `head/.claude/hooks/safety/block-destructive-bash.sh:528` (also 782, 1367, 1520) (confidence: medium)
- **Issue:** `--arg replay "${LOA_AUDIT_REPLAY:-}"` ... `+ (if $replay == "1" then {replay: true} else {} end)`. A shell profile or parent process that exports it marks every live block as replay and the yield under-reports real catches; CLAUDE.loa.md asks that test-mode env overrides be bats-gated.
- **Fix:** Require a second marker only the harness sets (the sandbox-cwd rule already in `guard-yield.sh`), or warn once per session when the flag is set, as `LOA_GIT_TAG_BYPASS_WARNED` does.
- **Reference:** CWE-15 — https://cwe.mitre.org/data/definitions/15.html

### [LOW-010] The CI drift gate exits 1 when the tracked register is absent, and the register is not in this change set
- **File:** `head/.github/workflows/bats-tests.yml:159` with `head/.claude/scripts/guard-yield.sh:422-435` (confidence: low)
- **Issue:** `run: bash .claude/scripts/guard-yield.sh --check`; in my composed tree without `grimoires/loa/guards.md` it exited 1 ("drift"). The seeder excludes `grimoires/` from fixtures (`seed-corpus-from-record.sh:307`), so the real PR very likely carries it; confirm it is committed and in sync or the first CI run after merge is red.
- **Reference:** CWE-1059 — https://cwe.mitre.org/data/definitions/1059.html

### [LOW-011] Sixteen new tasks reference fixtures and hidden manifests absent from the change set
- **File:** `head/evals/tasks/review-recall/review-pr-11.yaml:5` (and pr-12 … pr-18, both suites) (confidence: low)
- **Issue:** `fixture: review-prs/pr-11`; `run-arms.sh` refuses a missing fixture (`run-arms: fixture not found`, observed in RA-1). Same fixture-scope caveat as LOW-010.
- **Reference:** CWE-1059 — https://cwe.mitre.org/data/definitions/1059.html

### [LOW-012] The only record of why a failed trial exited 2 is deleted
- **File:** `head/evals/harness/run-arms.sh:416` (confidence: high)
- **Issue:** `rm -f "$JOBS_DIR/$jid".*` removes `$jid.exec.log`, which holds `execute-agent.sh`'s stderr (e.g. "ERROR: karpathy_block toggle: no '## Karpathy Principles' section removed"). An exit-2 toggle failure writes no `executor.json`, so `keep_artifacts` keeps nothing explanatory; the row says only "execute-agent exit 2".
- **Fix:** Copy `$jid.exec.log` into the trial's artifacts directory before the `rm`.
- **Reference:** CWE-778 Insufficient Logging — https://cwe.mitre.org/data/definitions/778.html

### [LOW-013] `cleanup` kills the trial subshells but not their executor grandchildren
- **File:** `head/evals/harness/run-arms.sh:244-248` (confidence: medium)
- **Issue:** `for p in $(jobs -p 2>/dev/null); do kill "$p" 2>/dev/null || true; done`. On INT the subshells die while `execute-agent.sh` keeps running `timeout … claude` for up to `per_trial` (3,600 s on record fixtures) with the lock already removed.
- **Fix:** Run each trial in its own process group (`setsid`) and kill the group, or record and kill the executor pid.
- **Reference:** CWE-404 Improper Resource Shutdown or Release — https://cwe.mitre.org/data/definitions/404.html

### [LOW-014] A renamed binary is not recognised as binary and is written through `redact()` as corrupted text
- **File:** `head/evals/harness/seed-corpus-from-record.sh:309-312` (confidence: high)
- **Issue:** `binary.add(p.split(" => ")[-1].strip("{}"))` turns `scripts/{a.bin => b.bin}` into `b.bin`, while `--name-status` yields `scripts/b.bin`, so `new in binary` is false and the blob passes through `redact()` (line 740), which decodes with replacement, contradicting "without binaries" (line 33). The seed fixtures contain no binaries or renames.
- **Fix:** Reconstruct the brace form (`prefix{old => new}suffix`) or use `--numstat -z` and compare full paths.
- **Reference:** CWE-20 — https://cwe.mitre.org/data/definitions/20.html

### [LOW-015] Paths git quotes are silently dropped from `base/`, `head/` and `head.diff` while still counted as in scope
- **File:** `head/evals/harness/seed-corpus-from-record.sh:314-321` (confidence: high)
- **Issue:** `parts = l.split("\t")` keeps the quoted form (`"scripts/caf\303\251.sh"`); `git show HEAD:"..."` fails, `show()` returns `None` and the file is skipped (738-740), yet `fix_touched` holds the quoted name so a finding citing that file is dropped as "not part of this fixture" (546-548).
- **Fix:** Use `-z` on the `--numstat`/`--name-status`/`--name-only` calls or `-c core.quotePath=false`.
- **Reference:** CWE-20 — https://cwe.mitre.org/data/definitions/20.html

### [LOW-016] The manifest and the two task YAMLs are written after the no-secrets scan
- **File:** `head/evals/harness/seed-corpus-from-record.sh:764-792` (confidence: high)
- **Issue:** `ok, msg = scan(fdir)` runs before `man = build_manifest(fx)` (776) and the task writes (784-791). Today their content derives from scanned fields, so the gap is contractual ("every file passes evals/graders/no-secrets.sh", line 46); a future manifest field (a finding title) would bypass the scan.
- **Fix:** Scan after `build_manifest` and include `manifests/<fx>.json` and the task files.
- **Reference:** CWE-200 Exposure of Sensitive Information — https://cwe.mitre.org/data/definitions/200.html

### [LOW-017] `LOA_EVAL_SOURCE_COMMIT` is recorded without checking it against the prompt tree's HEAD
- **File:** `head/evals/harness/execute-agent.sh:401` (confidence: high)
- **Issue:** `--arg source_commit "${LOA_EVAL_SOURCE_COMMIT:-$prompt_tree_commit}"`. Both `compare-ab.py:153-156` and `arms-report.py:283-285` use `source_commit` as the skew sentinel; a stale value makes rows from two trees look like one pinned source (AT-11 records `864069f2` against an unrelated synthetic tree).
- **Fix:** When both are set, require `prompt_tree_commit` to start with the given value, else exit 2.
- **Reference:** CWE-20 — https://cwe.mitre.org/data/definitions/20.html

### [LOW-018] `--allow-unapproved` leaves no trace in `MANIFEST.json` or the rows
- **File:** `head/evals/harness/run-arms.sh:115-119` and `:178-204` (confidence: high)
- **Issue:** `die "$f: labels.tsv is not approved yet (...), or pass --allow-unapproved"` is the only place the flag matters; a report cannot distinguish approved-label runs from unapproved ones.
- **Fix:** Record `allow_unapproved` and per-fixture `approved_by` in the manifest.
- **Reference:** CWE-778 — https://cwe.mitre.org/data/definitions/778.html

### [LOW-019] The arm report ignores `prompt_tree_dirty` and `prompt_tree_sha`, which `compare-ab.py` treats as invalidating
- **File:** `head/evals/harness/arms-report.py:123-157` (confidence: high)
- **Issue:** `Arm.add` collects `model_id`, `models_used`, `source_commit` and `refusal_fallbacks` only; `compare-ab.py:142-150` refuses a dirty or skewed prompt tree. `run-arms.sh` checks pristineness once (229-232); a worktree edited mid-batch yields rows with `prompt_tree_dirty: true` that `report.sh --arms` still verdicts.
- **Fix:** Collect both fields per arm and add "dirty prompt tree" / "prompt tree skew" to `reasons`.
- **Reference:** CWE-754 — https://cwe.mitre.org/data/definitions/754.html

### [LOW-020] Task lines not written exactly as `- [ ] ` at column 0 are invisible to the `kind:` rule (reproduced)
- **File:** `head/.claude/scripts/validate-artifact.sh:1019` and `head/tools/cycle-ratio.sh:97-98` (confidence: high)
- **Issue:** `!sec || $0 !~ /^- \[[ xX]\] / { next }`. A dated plan whose Technical Tasks use `* [ ] Task 1.1 …` or a two-space-indented `- [ ] Task 1.2 …` produced no `kind:` message at all (the plan failed only on unrelated sections); replacing one bullet with `- [ ]` produced the expected "a task line has no kind: token". The ratio tool mirrors the filter and reports `untagged 0`. KINDS-1..11 have no bullet or indent case.
- **Fix:** Treat `^[[:space:]]*[-*+][[:space:]]+\[[ xX]\]` as task-shaped and fail it as "not a top-level `- [ ]` task line"; fail a dated plan whose Technical Tasks section yields zero task lines.
- **Reference:** CWE-20 — https://cwe.mitre.org/data/definitions/20.html

### [LOW-021] No ordering check on the ratio window
- **File:** `head/tools/cycle-ratio.sh:125-131` (confidence: high)
- **Issue:** `FROM_TS="$(git show -s --format=%ct "$FROM_SHA")"`, `TO_TS=...`, then `select(. != null and . >= $lo and . <= $hi)`. Swapped `--from/--to` exits 0 with a reversed diff and `model calls 0`, no WARN; rows whose `ts_utc` carries a non-`+00:00` offset are dropped silently.
- **Fix:** `(( FROM_TS <= TO_TS )) || die 2 ...` and WARN with the count of unparseable `ts_utc` rows.
- **Reference:** CWE-20 — https://cwe.mitre.org/data/definitions/20.html

### [LOW-022] Only the template learned the `· kind:` grammar; the planning skill's prose does not mention it
- **File:** `head/.claude/skills/planning-sprints/resources/templates/sprint-template.md:58-60` (the skill's `SKILL.md` is untouched and has no `kind:` text) (confidence: medium)
- **Issue:** A planner that follows the skill text rather than copying the template writes untagged lines on a dated plan and fails the end-of-phase validator. Fail-closed, so a nuisance, not a bypass.
- **Fix:** One sentence in the planning skill naming the grammar and the three values.
- **Reference:** CWE-1059 — https://cwe.mitre.org/data/definitions/1059.html

---

## Cross-Model Security Observations

The dissent ran on `pr/head.diff` (`--type audit`): primary `gpt-5.5-pro` (answered via `codex-headless`), companion `claude-headless`, `counted_as: independent_voice`, `voices_succeeded: 2/2`, `status: clean`, `degraded: false`, no `locality.degraded_security_review` marker. Not a degraded review. Input was truncated to 11 of 81 files by the token budget (the fence script and the origin map were size-capped), so the voices did not see the harness code where HIGH-001 and MED-001..006 sit. Five advisory findings, none BLOCKING:

- DISS-C-001 (MEDIUM) floor gap: fence script and `settings.json` not pinned, hook row `floor: false` — Confirmed by cross-model review; adopted as MED-008 (and the CI consequence as MED-009).
- DISS-C-002 (MEDIUM) app zone `read` → `read-write` — adopted at LOW (LOW-007): the frontmatter is declarative, no script consumes it, so the damage is misdocumentation.
- DISS-C-003 (LOW) ambient `LOA_AUDIT_REPLAY` — Confirmed; adopted as LOW-009.
- DISS-C-004 (LOW) `reviewing-code/SKILL.md:135, 284` zone-constraint and Red Flags prose trimmed — not adopted as a defect: the trimmed text defers to `resources/REFERENCE.md`, which Phase 2 of that skill still instructs the reviewer to read, and the harness fences are unchanged. Noted for the prompt-budget owners: keep a one-line "never edit `.claude/`" statement in the block.
- DISS-C-005 (LOW) `stash-safety.md` scoping — Confirmed; adopted as MED-011, matching the review's rating.

## Rejected dissent payloads

None: `metadata.rejected_summary` is empty, `rejected_count` is 0, and no `adversarial-rejected-audit*.jsonl` sidecar was written.

---

## Review demotions

The review trailer carries `excluded: 0`; there are no demoted highs to confirm. `excluded_confirmed: 0`.

---

## Documentation Audit

No `documentation-coherence-*.md` reports exist in this frozen fixture; verified by hand:

- `evals/README.md` gains the control-arm section and states the exit-2 contract the code must honour (HIGH-001, MED-001 contradict it).
- `GLOSSARY.md` gains Judgment, Kind counts, Mechanical, Operator, Volume ratio; its Zone entry still says the App zone needs confirmation (LOW-007).
- `hooks-reference.md` generated block matches `settings.json` one for one (regenerated byte-identical).
- `guard-yield.sh` header line 8 is inaccurate (LOW-003); `check-prompt-budget.yml` comment unverifiable here (LOW-008).
- No CHANGELOG in fixture scope (the seeder excludes it); the PR body is a title and a file count with no AC walkthrough and no mention of the zone-permission change.
- No secrets or internal URLs in docs or comments; the seed fixtures assemble fake key shapes at test time only.

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added (seeder redacts secret shapes and fails closed when `no-secrets.sh` is missing — observed in SC-1; the two task YAMLs and manifest are written after the scan, LOW-016)
- [x] Input validation at trust boundaries (`guard-yield.sh` canonical hook schema, `badpath`, symlink containment, id regexes; `run-arms.sh` and `execute-agent.sh` argument regexes; `seed-corpus` path checks; `python3 -I` everywhere)
- [x] No shell injection from data (all git calls are argv lists; audit-row text reaches only jq string ops and a function argument; `cell` strips control characters and escapes pipes)
- [x] Privacy: yield outputs carry no command text, cwd, hostname, user or model name (probed with crafted rows: zero leaks)
- [x] Error messages do not leak sensitive data
- [ ] Tests cover security paths: gaps named in HIGH-001 (no AT-9 case for `rule_files`), MED-001, MED-002 (`run-arms.bats` unsets the variable), MED-004, MED-005, MED-009 (suite skips in CI), LOW-020
- [x] Fence unchanged in behaviour: diff of `block-destructive-bash.sh` filtered of `# @guard` comments leaves only the four `replay` additions

## Rubric scores

| Dimension | Score | Basis |
|-----------|-------|-------|
| SEC-IV Input Validation | 4 | allowlist regexes on every id; gaps LOW-001, LOW-002, LOW-015 |
| SEC-AZ Authorization | 4 | zone declaration widened without rationale (LOW-007); floor row gap (MED-008) |
| SEC-CI Confidentiality/Integrity | 4 | privacy probe clean; integrity gaps MED-006, LOW-014 |
| SEC-IN Injection Prevention | 5 | no eval, no shell-from-data, `python3 -I`, argv git |
| SEC-AV Availability/Resilience | 4 | retries and locks present; LOW-004, LOW-013 |
| ARCH-MO Modularity | 3 | duplicated scanner (MED-013), 168-line report function (MED-012) |
| Code Quality | 3 | thorough suites, but every blocking path found here is untested |
| DevOps | 3 | new gate wired into CI, but path filters and shallow checkout make three gates inert (MED-009, MED-010) |

---

## Next Steps

1. Fix HIGH-001 (fail closed when no rule file was removed) and add the AT-9-style case; fix MED-001 and MED-002 in the same pass so no route to a null experiment remains, and MED-003/MED-004 so a verdict never rests on an unevaluated rule.
2. Make the generator robust to its optional library (MED-007) and assert the files it claims to write.
3. Close the floor gap and make its backstops real: MED-008 (floor the hook row and pin the fence/settings), MED-009 (`fetch-depth: 0`, fail not skip), MED-010 (path filters).
4. Address or explicitly accept MED-005, MED-006, MED-011..013 and the lows.
5. Confirm `grimoires/loa/guards.md`, the pr-11…pr-18 fixtures and `tools/check-prompt-budget.sh` are in the real change set (LOW-008, LOW-010, LOW-011).
6. Run `/implement sprint-1` with the fixes, then `/review-sprint sprint-1` and `/audit-sprint sprint-1` again.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":13,"low":22},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-22T13:52:00Z"} -->
