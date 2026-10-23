# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Review Feedback:** grimoires/loa/a2a/sprint-1/engineer-feedback.md ("All good", APPROVED, 0 critical, 0 high, 3 medium, 7 low, excluded 0)
**Dissent Envelope:** grimoires/loa/a2a/sprint-1/adversarial-audit.json (status `clean`, primary gpt-5.5-pro, companion claude-headless, 2/2 voices, `diff_sha256` equals `sha256sum pr/head.diff`)

---

## Verdict: APPROVED - LET'S FUCKING GO

---

## Executive Summary

The change under audit is the 81-file pull request in `pr/` (`pr/head.diff`): the guard register and its host yield (`guard-yield.sh`, `guard-origins.yaml`, `floor.yaml`, `# @guard` markers in the fence and the validator, the generated hooks table, the `/loa` Guards line), pre-registered control arms on a record corpus (`execute-agent.sh` toggles, `run-arms.sh`, `arms-report.py`, `seed-corpus-from-record.sh`, grader 1.2.0), task kinds (`validate-artifact.sh` kind rule, `tools/cycle-ratio.sh`, template and glossary) and path-scoped rule files.

Every new or changed script was read in full from `pr/head/` (guard-yield.sh, run-arms.sh, seed-corpus-from-record.sh, arms-report.py, cycle-ratio.sh) and every other file as its diff hunks. The scope scan (`security-audit-scope.sh --json` over `pr/head`) classifies 5 source files and 4 sink files, no auth and no LLM files. The trust boundaries this change adds are: the audit log rows the yield reads (hook-written, command text is untrusted and is never emitted — verified in the jq program at `head/.claude/scripts/guard-yield.sh:485-576` and by GY-5), the sandbox copy the arm toggles edit (applied after materialisation to `$WORKSPACE` only, verified absent afterwards, AT-4/AT-6), and the record-branch feedback text the seed script parses (control-stripped, secret-pattern dropped, every written file scanned by no-secrets.sh, SC-2). None of these boundaries leaks or widens anything exploitable.

No critical or high finding. Three medium findings, all confirmed independently against this checkout: the register generator terminates silently when the optional heredoc classifier is sourced (reproduced below), the 30-day yield assumes a rotation scheme the repository does not implement, and an undocumented app-zone permission widening travels in the PR. Twelve low findings follow, of which three fold in the cross-model companion's advisories after independent verification (one confirmed, two confirmed in part). The review trailer excluded no high finding, so there is nothing to confirm or re-tally (`excluded_confirmed: 0`).

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 3 |
| Low | 12 |

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

None.

---

## Medium/Low Priority Issues

### [MED-001] guard-yield.sh exits 0 with no output when the optional heredoc classifier is sourced

- **Severity:** MEDIUM · **Confidence:** high
- **File:** `head/.claude/scripts/guard-yield.sh:470` (block 465-483)
- **Issue:** The optional FR-6 library is sourced in the main shell: `if source "$HEREDOC_LIB" 2>/dev/null && declare -F heredoc_nonexec >/dev/null; then` (guard-yield.sh:470). In this checkout the library exists and does `BDB_LIB_ONLY=1 source "$_hc_fence"` (`.claude/scripts/lib/heredoc-classifier.sh:19`), but the PR's fence has no library-only branch (no `BDB_LIB_ONLY` anywhere in `head/.claude/hooks/safety/block-destructive-bash.sh`; the base checkout's fence has it at its line 771). The fence therefore runs as a hook on the register generator's stdin, finds no command, and `exit 0`s — inside the sourcing shell, which is guard-yield.sh itself. Reproduced here: `bash -c 'source pr/head/.claude/hooks/safety/block-destructive-bash.sh </dev/null; echo REACHED'` prints nothing and returns 0, with and without `BDB_LIB_ONLY=1`; the same command against the base checkout's fence prints `REACHED`. `set -euo pipefail` offers no protection because the exit status is 0.
- **Impact:** `grimoires/loa/guards.md`, `.run/guard-yield.md` and `.run/guard-yield.json` are not written, no diagnostic is printed, and the caller sees success. `--check` is unaffected (it exits at line 437 before the yield stage), so CI stays green while the host yield that Sprint 2 reads to judge guards is stale or absent. The review reproduced the same with the bats suite (7 of 11 guard-yield.bats cases fail with the library present).
- **Fix:** Probe in a subshell before sourcing, and fail loudly: `( source "$HEREDOC_LIB" && declare -F heredoc_nonexec ) >/dev/null 2>&1 || die 3 "heredoc classifier present but not loadable"`; or run the classification loop (lines 474-480) in a subshell that sources the library. Separately, give this PR's fence the `BDB_LIB_ONLY` guard the library relies on, since the two will meet on main.
- **Reference:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html

### [MED-002] The 30-day yield reads rotated segments that no writer produces, and silently undercounts after truncation

- **Severity:** MEDIUM · **Confidence:** high
- **File:** `head/.claude/scripts/guard-yield.sh:443` (block 441-455; header claim at 26-27; output at 551-553)
- **Issue:** `for f in "$AUDIT_LOG" "$AUDIT_LOG".*; do` (guard-yield.sh:443) implements the header's "rows of .run/audit.jsonl and its rotated segments .run/audit.jsonl.*" (lines 26-27). The only rotation in the repository is `.claude/hooks/audit/mutation-logger.sh:193-194`: `tail -n 1000 .run/audit.jsonl > .run/audit.jsonl.tmp && mv .run/audit.jsonl.tmp .run/audit.jsonl` — an in-place truncation to the last 1000 rows at 10 MB that never creates a numbered segment. GY-2 ("the rotated segment is read") tests a fixture `audit.jsonl.1` that nothing in the repository writes.
- **Impact:** After a truncation every earlier block in the window is gone from the log while the yield still reports `window_days: 30` and `audit_segments: 1` (lines 551-553) with no truncation marker; block rows are a small fraction of the audit rows, so the undercount is large and biased toward "this guard caught nothing", which is the deletion signal Sprint 2 acts on. The glob also matches the transient `audit.jsonl.tmp` written mid-truncation, which is then read as a segment and double-counts up to 1000 rows (`replay`/`burst` logic cannot distinguish the duplicate).
- **Fix:** Match `"$AUDIT_LOG".[0-9]*` only; compute the earliest parseable `ts` across the segments and, when it is inside the window, emit `truncated: true` / `window_effective_from` in the JSON, the markdown header and the `/loa` Guards line; or make mutation-logger rotate into `audit.jsonl.1` so the header claim becomes true.
- **Reference:** CWE-223 Omission of Security-relevant Information — https://cwe.mitre.org/data/definitions/223.html; CWE-778 Insufficient Logging — https://cwe.mitre.org/data/definitions/778.html

### [MED-003] SURGICAL: app-zone permission widened from `read` to `read-write` without a decision record

- **Severity:** MEDIUM · **Confidence:** high
- **File:** `head/.claude/skills/implementing-tasks/SKILL.md:28`
- **Issue:** The diff hunk changes `permission: read` to `permission: read-write` under `zones.app` in a PR whose description (`pr/PR.md`) names the guard register, control arms, task kinds and rule paths and says nothing about zones. No DEC row accompanies it; CLAUDE.loa.md and the GLOSSARY entry edited in this same PR still describe the App zone as "needs confirmation before a write". The companion `reviewing-code/SKILL.md:135` rewording ("Zones per the frontmatter `zones:`") makes the frontmatter the stated source of truth, which raises the stakes of an unexplained edit to it.
- **Impact:** Verified that no script reads a skill's `zones:` block: `zone-write-guard.sh` reads `grimoires/loa/zones.yaml`, `review-scope.sh` and `classify-commit-zone.sh` read `.loa-version.json`; the effect today is prose-only and arguably corrects a declaration that contradicted the skill's purpose. It is still an undocumented policy change riding an unrelated PR, which is the pattern the floor and the register exist to make visible. Confirmed by cross-model review (DISS-C-003, both the review's and this audit's dissent).
- **Fix:** Add one sentence to the PR description and a DEC row (or split the hunk into its own change) naming why `/implement` declares read-write while CLAUDE.loa.md keeps confirm-writes; keep the GLOSSARY "Zone" entry consistent with it.
- **Reference:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html

### [LOW-001] Transport-failure classifier over-matches agent output

- **Severity:** LOW · **Confidence:** medium
- **File:** `head/evals/harness/run-arms.sh:314` (block 308-317)
- **Issue:** `grep -qiE 'rate.?limit|overloaded|session limit|usage limit|out of extra usage|ECONNRESET|ETIMEDOUT|network|socket hang up|5[0-9][0-9] ' "$err" "$out"` runs over `agent-stderr.log` and `agent-output.json`. The latter holds the agent's own result text, so a review that mentions "network", "overloaded" or any three-digit number starting with 5 followed by a space (a token count, a line number) turns an `agent_error` (executor exit 1) into a `transport_error` that is retried after `--retry-wait`.
- **Impact:** A real agent failure is hidden behind a transport label, `attempts` is inflated and the arm's row set drifts from the plan; RA-3 covers only the stub's literal "socket hang up".
- **Fix:** Grep only `agent-stderr.log` for the free-text alternatives, anchor the status form (`HTTP/[0-9.]+ 5[0-9][0-9]`, `"status": *5[0-9][0-9]`) and rely on `api_error_status` (line 313) for the JSON.
- **Reference:** CWE-185 Incorrect Regular Expression — https://cwe.mitre.org/data/definitions/185.html

### [LOW-002] Approval gate defaults open when a manifest lacks the `approved` key

- **Severity:** LOW · **Confidence:** medium
- **File:** `head/evals/harness/run-arms.sh:115`
- **Issue:** `jq -r 'if has("approved") then .approved else true end'` treats a manifest without the key as approved. The seed script always writes the key (`seed-corpus-from-record.sh:235`), so this exists for the planted fixtures pr-01…pr-10 that `build-review-corpus.sh` writes without it; but a hand-edited or partially migrated record manifest that loses the key passes the gate the README says `run-arms.sh refuses unapproved fixtures` enforces.
- **Impact:** Unapproved labels grade an arm run without `--allow-unapproved`, and the row's `fixture_verified: true` gives no hint.
- **Fix:** Default closed for record fixtures: `if has("approved") then .approved elif (.record // null) != null then false else true end`, or have build-review-corpus.sh write `approved: true` for planted fixtures and default to `false`.
- **Reference:** CWE-636 Not Failing Securely — https://cwe.mitre.org/data/definitions/636.html

### [LOW-003] Suite-status lock gives up silently and is never cleaned on interruption

- **Severity:** LOW · **Confidence:** medium
- **File:** `head/evals/harness/run-arms.sh:287` (block 285-304; cleanup 244-248)
- **Issue:** `until mkdir "$lockd" 2>/dev/null; do n=$((n + 1)); [[ $n -gt 50 ]] && return 0; sleep 0.1; done` returns success after about five seconds without aggregating. `cleanup()` removes the batch lock and jobs dir but not `$SUITE_DIR/.status.lock`, so a run killed between `mkdir` and `rmdir` leaves the directory behind and every later `aggregate_status` call in every batch silently skips.
- **Impact:** The suite-level `STATUS.json` that `arms-report.py` and the Sprint 2 gate read goes stale with no log line; the failure direction is safe (the report refuses or reads `inconclusive`) but the cause is invisible.
- **Fix:** Log when the wait is abandoned; remove the status lock in `cleanup()`; or write the aggregate with a `mv` over a per-pid temp file and drop the lock entirely.
- **Reference:** CWE-667 Improper Locking — https://cwe.mitre.org/data/definitions/667.html

### [LOW-004] Fence floor rows are pinned only through corpus rows and the call-site list

- **Severity:** LOW · **Confidence:** medium
- **File:** `head/.claude/data/floor.yaml:46` (floor_files 46-50; floor_corpus 54-58)
- **Issue:** `floor_files` pins `verdict-derive.sh`, `adversarial-review-gate.sh`, `settings.deny.json` and `user-invoked-commands.txt` byte-for-byte (FS-1), while the sixteen `fence:*` floor rows are backed by FS-2 (corpus rows for `FR-1.2b` and `FR-SZ*`) and FS-4 (the fence's `emit_block`/`pattern_id` call-site list, in order). A loosening of the `_sz_file` or `_c2_file` alternation that no existing corpus row exercises passes all four tests while the register still shows `floor: yes`.
- **Impact:** The documented floor guarantee ("no profile, knob or cycle task may weaken") is weaker for the fence rows than for the gate and policy rows, and the asymmetry is not stated. This very PR edits the fence (markers, `replay` field), which is why pinning its bytes would have failed here. Confirmed by cross-model review (DISS-C-001 in both dissent rounds).
- **Fix:** State the asymmetry in the floor.yaml header and in guards.md, or pin the fence and accept deliberate pin updates; a cheaper middle: pin the `_sz_*`/`_c2_*` variable block by sha256 in floor-snapshot.bats.
- **Reference:** CWE-353 Missing Support for Integrity Check — https://cwe.mitre.org/data/definitions/353.html

### [LOW-005] The deny-list floor pins the template, not the enforced list

- **Severity:** LOW · **Confidence:** medium
- **File:** `head/.claude/data/floor.yaml:49`; policy row `script: .claude/hooks/settings.deny.json` in `head/.claude/data/guard-origins.yaml`
- **Issue:** `policy:permission-deny-list` is `floor: true` and names `.claude/hooks/settings.deny.json`, the template. The list Claude Code enforces is `permissions.deny` in `.claude/settings.json` (62 entries in this checkout). FS-3 pins only `.hooks` of settings.json (`jq -c '.hooks'`, floor-snapshot.bats:45), so a deny entry can be removed from the live file without failing the floor; `verify-deny-rules.sh` exists but is not part of the floor test. The companion's claim that hook registrations are unpinned is refuted by FS-3; the deny-list half stands. Partially confirmed by cross-model review (DISS-C-002).
- **Impact:** The register reports the deny list as floor while its enforced copy is outside the snapshot.
- **Fix:** Extend FS-3 to `jq -c '.permissions.deny | sort'` or run `verify-deny-rules.sh` from floor-snapshot.bats; note in the policy row that the template is pinned and parity is verified separately.
- **Reference:** CWE-353 Missing Support for Integrity Check — https://cwe.mitre.org/data/definitions/353.html

### [LOW-006] Replay tagging keys on a bare environment variable

- **Severity:** LOW · **Confidence:** medium
- **File:** `head/.claude/hooks/safety/block-destructive-bash.sh:528` (also 782, 1367, 1520)
- **Issue:** `--arg replay "${LOA_AUDIT_REPLAY:-}"` with `(if $replay == "1" then {replay: true} else {} end)` tags every block, bypass, override and marker row as a replay whenever the variable is `1`, with no check that a corpus run or an eval sandbox is in progress. `run-corpus.sh:35`, `floor-snapshot.bats:14` and `run-arms.sh:337` set it; a shell profile or CI env that leaks it into an interactive session tags real blocks as replays.
- **Impact:** The yield's `real_blocks_30d` and the `/loa` Guards line drop those rows. The companion's "silently" is refuted: guard-yield.sh reports them under `replay_rows_by_rule.flag` (lines 558-562) and the markdown header, so an operator who reads the header sees the count; but nothing warns when the flag share is implausibly high. Partially confirmed by cross-model review (DISS-C-004).
- **Fix:** Have guard-yield.sh warn when `flag` rows exceed, say, half of the window's block rows outside a replay cwd; or scope the flag to a nonce file the corpus runner creates under `.run/` and the fence checks for.
- **Reference:** CWE-15 External Control of System or Configuration Setting — https://cwe.mitre.org/data/definitions/15.html

### [LOW-007] Path scoping narrows where the stash rule is loaded, without saying so

- **Severity:** LOW · **Confidence:** medium
- **File:** `head/.claude/rules/stash-safety.md:2` (frontmatter 1-11)
- **Issue:** `paths:` restricts loading to `**/*.sh`, `**/*.bats`, `.claude/scripts/**`, `.claude/hooks/**`. A pure-Bash session that runs `git stash push … | tail -1` without reading or editing such a file never loads the prose rule and relies on fence FR-1.2b alone. This is the SDD D-3.1 decision the `no_rule_files` arm exists to measure, but the rule body does not say so.
- **Impact:** The next reader re-opens the question; the harness fence remains the always-on floor, so no destructive path opens.
- **Fix:** One sentence in the body: scoping is deliberate (D-3.1), FR-1.2b is the floor.
- **Reference:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html

### [LOW-008] The CI drift gate depends on a tracked file outside this change set

- **Severity:** LOW · **Confidence:** low
- **File:** `head/.github/workflows/bats-tests.yml:159` (step 155-159)
- **Issue:** `bash .claude/scripts/guard-yield.sh --check` exits 1 unless `grimoires/loa/guards.md` exists and equals the generated register (guard-yield.sh:422). `grimoires/loa/guards.md` is not among the 81 files (the record-fixture scope excludes `grimoires/`), and it does not exist in this checkout.
- **Impact:** The gate's green state cannot be established from the PR; a missing or stale committed register makes the first CI run red.
- **Fix:** Confirm the register is committed on the branch and GO-9 passes there.
- **Reference:** OWASP A05:2021 Security Misconfiguration — https://owasp.org/Top10/A05_2021-Security_Misconfiguration/

### [LOW-009] The `kind:` token follows the blockers segment the template calls machine-parsed

- **Severity:** LOW · **Confidence:** medium
- **File:** `head/.claude/skills/planning-sprints/resources/templates/sprint-template.md:58` (comment 52-56)
- **Issue:** The comment says the `⇐` segment "becomes the --deps flag when the task is created as a bead", and the new ` · kind: mechanical` token is appended after it. No script parses `⇐` (verified: none under `.claude/scripts` or `.claude/hooks`), so the parse is the model's, and the comment does not say where the blockers segment ends. Confirmed by cross-model review in the review round (DISS-C-002 there).
- **Impact:** `none · kind: mechanical` read as a dependency list by a model following the comment literally.
- **Fix:** Extend the comment: the blockers segment ends at ` · kind:`.
- **Reference:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html

### [LOW-010] Prompt-budget constants restated without the gate in scope

- **Severity:** LOW · **Confidence:** low
- **File:** `head/.github/workflows/check-prompt-budget.yml:5`; `head/tests/unit/prompt-budget.bats:112-124`
- **Issue:** The header now says "protocols total ≤ 160,000 B (warn > 114,688 B)" and PB-10 asserts the same, but `tools/check-prompt-budget.sh` is not in the change set, so the two cannot be checked against the gate here.
- **Impact:** A stale header comment, the class PB-10 was written to catch.
- **Fix:** None beyond running PB-10 on the branch.
- **Reference:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html

### [LOW-011] Record ref accepts a leading dash and reaches git as an option

- **Severity:** LOW · **Confidence:** high
- **File:** `head/evals/harness/seed-corpus-from-record.sh:271` (also `rev()` at 95-99)
- **Issue:** `re.match(r"^[A-Za-z0-9._/-]+$", args.record_ref)` admits `-foo`, which is then passed as `git rev-parse --verify --quiet -foo` (line 302) and `git show -foo:path` (line 102); `rev()` passes `--base/--head/--fix` values with no leading-dash check at all. `tools/cycle-ratio.sh:80-82` in this same PR guards exactly this class ("A leading '-' would reach git as an option").
- **Impact:** Argument injection into a local developer tool from operator-supplied arguments; no privilege crossing, but inconsistent with the PR's own hardening and a confusing failure mode.
- **Fix:** Reject values starting with `-` (or pass `--` before the ref / use `--end-of-options`).
- **Reference:** CWE-88 Improper Neutralization of Argument Delimiters in a Command — https://cwe.mitre.org/data/definitions/88.html

### [LOW-012] Hook-script symlink check resolves one level only

- **Severity:** LOW · **Confidence:** low
- **File:** `head/.claude/scripts/guard-yield.sh:221` (block 220-229)
- **Issue:** `tgt="$(readlink "$abs")"` resolves the registered path once; the directory is canonicalised with `pwd -P` but the final basename is not, so a symlink whose target is itself a symlink leaving `.claude/` passes the "leaves .claude/" check (line 227) and `-f "$abs"` (line 230) follows it.
- **Impact:** The register is a reporting surface, not a boundary (settings.json is pinned by FS-3), so the effect is a misattributed row.
- **Fix:** Use `realpath -e` / `readlink -f` when available, or loop `readlink` until stable.
- **Reference:** CWE-59 Improper Link Resolution Before File Access — https://cwe.mitre.org/data/definitions/59.html

---

## Cross-Model Security Observations

Dissent: `.claude/scripts/adversarial-review.sh --type audit --sprint-id sprint-1 --diff-file pr/head.diff --json`; envelope `grimoires/loa/a2a/sprint-1/adversarial-audit.json`, `metadata.status: clean`, `metadata.model: gpt-5.5-pro`, `companion_voice.status: succeeded` (claude-headless, `counted_as: independent_voice`), `verdict_quality.voices_succeeded: 2/2`, `degraded: false`, `locality: null` (not a DEGRADED_SECURITY_REVIEW). The primary voice returned no finding at the BLOCKING/ADVISORY bar; the companion returned four, none CRITICAL/HIGH, so none changes the tally on its own:

- DISS-C-001 (MEDIUM, floor.yaml:46, fence not in floor_files) — verified, rated LOW here because FS-2/FS-4 and the corpus do cover the existing rows; folded as LOW-004. Confirmed by cross-model review.
- DISS-C-002 (MEDIUM, floor.yaml:49, settings.json not pinned) — half refuted: FS-3 pins the hook registrations; the `permissions.deny` half stands; folded as LOW-005.
- DISS-C-003 (LOW, implementing-tasks/SKILL.md:28) — duplicates MED-003. Confirmed by cross-model review.
- DISS-C-004 (LOW, block-destructive-bash.sh:528, bare replay env var) — "silently dropped" refuted (the yield reports `replay_rows_by_rule.flag`); the leak scenario stands; folded as LOW-006.

## Rejected dissent payloads

None. The envelope records `rejected_summary: []`, `rejected_count: 0`, `rejected_sidecars: []`, `companion_voice.rejected_sidecar: null`, and no `adversarial-rejected-audit*.jsonl` sits beside it.

---

## Review Demotions Check

The review trailer (`engineer-feedback.md`) carries `excluded: 0` and its Observations hold no HIGH finding, so there is no demotion to confirm: `excluded_confirmed: 0`. The review's three mediums are each confirmed above as MED-001, MED-002 and MED-003 with independent evidence from this checkout (library source line, mutation-logger rotation lines, zone-reader grep).

---

## Scope Notes (not tallied)

- **Hidden labels are hidden from the sandbox copy, not from the executor's Read tool.** `seed-corpus-from-record.sh` writes `labels/pr-NN.tsv` and `manifests/pr-NN.json` beside the fixture ("HIDDEN (never copied into a sandbox)", header lines 23-26; SC-1 asserts the find), and `execute-agent.sh` runs the executor with `Read,Grep,Glob,Write` after `cd "$WORKSPACE"` (execute-agent.sh:332) with no path confinement. An agent that guesses the repository path can read the labels by absolute path. This boundary predates the PR (`manifests/` worked the same way), so it is recorded, not counted; the fix belongs to the harness (a settings deny for `evals/fixtures/review-prs/labels/**` and `manifests/**` in the sandbox, or a sandbox on a copy of the fixture outside the repository).
- **Not assessable here:** `evals/graders/` (no-secrets.sh, verdict-consistency.sh, pattern-match.sh), `evals/harness/sandbox.sh`, `tools/check-prompt-budget.sh`, `grimoires/loa/guards.md` and the pr-11…pr-18 fixture trees are outside the change set and absent from this checkout; the review ran the bats suites from an overlay and its table is taken as the test evidence. `.gitignore:32-33` un-ignores `bridgebuilder-review/dist/**` under record fixtures; no such file is in this checkout to inspect.
- **Design choices read and accepted:** `review-kind-01.yml` uses `.yml` to stay out of the suite glob (documented in the file); `arms-report.py` treats any auxiliary `models_used` entry as model skew (documented, deliberate); `run-arms.sh` passes `LOA_AUDIT_REPLAY=1` to the executor so sandbox blocks never reach the host yield (consistent with MED-002's accounting).

---

## Documentation Audit

No `grimoires/loa/a2a/subagent-reports/documentation-coherence-*.md` exists in this workspace (no `/implement` ran here; the PR files are the entire input), so the report check is recorded as inapplicable rather than failed. Manually verified: `evals/README.md` documents the record corpus, hidden labels, approval and arms; `GLOSSARY.md` gains Judgment, Kind counts, Mechanical, Operator and Volume ratio (the review ran the glossary validator clean); `hooks-reference.md` carries the generated table (byte-identical per the review); the sprint template carries the kind token (KINDS-11). Security-critical code is commented (the `# @guard fence:<id>` markers sit on their sites). No secrets or internal URLs in docs or comments. CHANGELOG.md is outside the change set. The one documentation blocker candidate is MED-003 (a permission change without a rationale), counted above.

---

## Rubric Scores

| Dimension | Score | Basis |
|-----------|-------|-------|
| Security | 4/5 | Inputs validated at every CLI boundary (run-arms arg regexes, seed path/ref checks, `python3 -I`); privacy of the yield enforced by GY-5; no secrets; LOW-011 and LOW-006 are the only input-handling gaps |
| Architecture | 4/5 | Register is a pure function of the repository with an independent bats enumeration; arms applied post-materialisation and verified; LOW-004/LOW-005 pin asymmetry |
| Code Quality | 4/5 | Long jq stages named and commented; MED-001 (sourcing in the main shell) and MED-002 (assumed rotation) are the two environment assumptions |
| DevOps | 3/5 | New CI gate depends on a file outside the change set (LOW-008); `--check` cannot exercise the yield path that MED-001 breaks |
| Blockchain/Crypto | n/a | Not applicable |

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added (seed redacts secret shapes; test key assembled at runtime; SC-2)
- [x] Input validation on all new entry points (run-arms.sh:89-127, seed-corpus-from-record.sh:269-299, guard-yield.sh:101-139, cycle-ratio.sh:80-84) — LOW-011 noted
- [x] No command text, cwd, hostname or model name in register or yield outputs (GY-5; jq program emits counts only)
- [x] Python invoked with `-I` where it reads untrusted trees (seed script, verify_corpus, report.sh → arms-report.py, grader)
- [x] Sandbox toggles never touch the source tree (AT-4, AT-6, RA-2)
- [x] Error messages do not leak sensitive data
- [x] Tests cover security paths (guard-origins 15, guard-yield 11, arm-toggles 11, seed-corpus 6, run-arms 5, floor-snapshot 4)

---

## Next Steps

**APPROVED:**
1. Sprint is cleared; fix MED-001 and MED-002 before Sprint 2 reads the host yield to judge any guard, and record MED-003 in a DEC row.
2. Move to the next sprint or `/deploy-production`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":3,"low":12},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-22T13:55:00Z"} -->
