# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description `pr/PR.md`: sprint-255, cycle-129, 81 files)
**Senior review:** grimoires/loa/a2a/sprint-1/engineer-feedback.md (CHANGES_REQUIRED: 0 critical, 1 high, 2 medium, 11 low, 0 excluded)

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

Prerequisite note: the skill's Phase 0 expects the senior review to read "All good". It reads CHANGES REQUIRED. The task brief mandates this audit on the PR as submitted, so the audit ran and records that deviation here; the review's verdict stands alongside this one.

The change is well engineered at its trust boundaries. The guard register parses every hook command against one canonical schema and fails closed (exit 5) on anything outside it, ids are pattern-checked, table cells are control-stripped, and no command text, cwd, host or model name reaches `grimoires/loa/guards.md`, `.run/guard-yield.{md,json}` or the hooks table (GY-5 pins it; confirmed by reading the `jq` program at `head/.claude/scripts/guard-yield.sh:485-576`, which emits only ids, counts and day strings). The record-corpus seeder redacts secret shapes, drops any finding whose text matches one, and refuses to keep anything that fails `no-secrets.sh`. The executor strips the parent session's coupling and non-CLI credentials, confines the agent to `Read,Grep,Glob,Write`, and the arm driver refuses skewed comparisons.

One finding blocks: the PR turns on a CI drift gate whose reference artefact, the tracked register `grimoires/loa/guards.md`, is not in the change, so the gate and test GO-9 are red on the PR's own tree. I reproduced this in a scratch root built from this workspace's framework plus the PR head: `--check` exits 1 before generation, `--hooks-table` writes a 95-guard register, `--check` then exits 0 and only `grimoires/` is untracked (the committed hooks table is already in sync). Three medium findings follow: a control-arm toggle that silently runs as its baseline (reproduced), a `source` of an external library that can end the yield run with exit 0 having written nothing (reproduced with the later classifier present), and an app-zone permission widening in a skill manifest with no origin, decision row or test (confirmed by the cross-model dissent). The rest is low.

Suites run in the scratch root (`/workspace/.eval/tmp/evalroot`; `/tmp` is noexec here): GO-1…15 (GO-9 fails without the register, passes with it), GY-1…11, LSG-1…3, RP-1…6, KINDS-1…11, CR-1…6, FS-1…4, AT-1…11, AR-1…7, EA-1…7 and EA-10…12 pass. RA-1…5, EA-8/9 and SC-1…6 could not be exercised: `evals/fixtures/review-prs/`, `sandbox.sh`, `grade.sh` and `no-secrets.sh` are repository files outside the change and absent from this mount (`run-arms: fixture not found: …/review-prs/pr-01`). Those are unverified, not failed.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 3 |
| Low | 15 |

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] The new CI drift gate is red on the PR's own tree: the tracked register it compares against is not in the change

**Severity:** HIGH (confidence: high; reproduced)
**File:** `head/.github/workflows/bats-tests.yml:159`, `head/.claude/scripts/guard-yield.sh:422`, `head/tests/unit/guard-origins.bats:120`
**Issue:** The workflow adds `run: bash .claude/scripts/guard-yield.sh --check` (`bats-tests.yml:159`). `--check` compares the generated register with `$OUT` (default `grimoires/loa/guards.md`): `if [[ ! -f "$OUT" ]] || ! cmp -s "$REGISTER_NEW" "$OUT"; then … drift=1` (`guard-yield.sh:422-425`) and exits 1. The script header calls the file "tracked, STRUCTURAL ONLY … --check gates it" (`guard-yield.sh:19-20`) and `hooks-reference.md:168` points readers at it, but none of the 81 files in `pr/head.diff` is `grimoires/loa/guards.md`, and the head `.gitignore` does not ignore it (no pattern matches; `grimoires/loa/*.md` is not ignored as a class). GO-9 runs the same command (`guard-origins.bats:120`, `run bash "$GY" --check`) and asserts exit 0.
**Reproduction:** scratch root = workspace framework + PR head, no register present: `guard-yield.sh --check` → `drift: …/grimoires/loa/guards.md differs from the generated register`, exit 1; `bats tests/unit/guard-origins.bats` → 14 ok, `not ok 9 GO-9`. After `guard-yield.sh --hooks-table` (writes 130 lines, 95 guards): `--check` → `in sync (95 guards)`, exit 0; GO-1…15 all pass; `git status --porcelain` shows only `?? grimoires/`, so `hooks-reference.md` as committed already matches the generator and only the register is missing.
**Impact:** Merged as is, every subsequent CI run fails at this step until someone regenerates and commits the register; `/loa` prints `Guards: no register` (`head/.claude/scripts/loa-status.sh:658-660`); the sprint's own quality gate reads as broken rather than as protection.
**Fix:** Run `.claude/scripts/guard-yield.sh --hooks-table` on the PR tree and commit `grimoires/loa/guards.md`. Add the path to the tracked-state list `validate-gitignore-state.sh` checks, and an explicit `!grimoires/loa/guards.md` beside the other `grimoires/loa/` un-ignores so a future wildcard cannot swallow it. Re-run `tests/unit/guard-origins.bats`.
**Reference:** CWE-684 Incorrect Provision of Specified Functionality — https://cwe.mitre.org/data/definitions/684.html

---

## Medium Priority Issues

### [MED-001] The `rule_files` toggle records "removed: none present" and continues, so the `no_rule_files` arm can run as its baseline

- **Severity:** MEDIUM (confidence: high; reproduced)
- **File:** `head/evals/harness/execute-agent.sh:266` (contract at `head/evals/harness/execute-agent.sh:65`)
- **Issue:** The header promises "a toggle that cannot take effect is exit 2 (an arm never silently runs as its baseline)" (`execute-agent.sh:64-66`). `companion_voice`, `karpathy_block` and `audit_delta_instruction` honour it (`:243-244`, `:251-253`, `:271-272`). `rule_files` does not: the loop at `:262-265` removes whatever exists and then `_evidence rule_files "removed:${gone:- none present}"` (`:266`) returns 0 when `gone` is empty. Reproduced: a prompt tree whose `.claude/rules/` holds only `zone-state.md`, `LOA_EVAL_ARM=no_rule_files` → exit 0, `executor.json` `arm_evidence.rule_files = "removed: none present"`.
- **Impact:** A renamed rule file, or a pinned source commit from before the two rules existed, yields a "no recall loss" verdict for a control that was never removed; `arms-report.py` has no way to tell, since it reads only the grader figures. That verdict is what licenses deleting the control (SDD D-2.3).
- **Fix:** After the loop: `[[ -n "$gone" ]] || { echo "ERROR: rule_files toggle: neither rule file present in the sandbox" >&2; return 2; }`, and extend AT-9 with this case.
- **Reference:** CWE-392 Missing Report of Error Condition — https://cwe.mitre.org/data/definitions/392.html

### [MED-002] `source "$HEREDOC_LIB"` runs an external library in the `set -euo pipefail` main shell with diagnostics discarded; a library whose source chain exits ends the run with status 0 and nothing written

- **Severity:** MEDIUM (confidence: medium; reproduced with the library the line is written for)
- **File:** `head/.claude/scripts/guard-yield.sh:470` (guard at `:468`, outputs at `:610-612`)
- **Issue:** `if source "$HEREDOC_LIB" 2>/dev/null && declare -F heredoc_nonexec >/dev/null; then` (`guard-yield.sh:470`). The library this is written for, `.claude/scripts/lib/heredoc-classifier.sh` (a later cycle-129 sprint), does `BDB_LIB_ONLY=1 source "$_hc_fence"`. The fence shipped in this PR has no `BDB_LIB_ONLY` branch (`grep -c BDB_LIB_ONLY head/.claude/hooks/safety/block-destructive-bash.sh` → 0), so when sourced it reads an empty stdin and reaches its own `exit 0`, which terminates `guard-yield.sh` itself after `--check` (`:419-438`) and before the yield join and `install_file` (`:610-612`). Reproduced in the scratch root with the classifier present: exit 0, stdout 0 bytes, stderr empty, `--yield-dir` empty; with the classifier absent (this PR's repository state) GY-1…11 pass.
- **Impact:** The register and yield are not regenerated and nothing says so; an operator running `guard-yield.sh --hooks-table` after editing the origin map gets exit 0 and a stale register (the CI gate catches the register, nothing catches the yield). The trigger is not in this change, hence medium confidence; the hazard is the line's design.
- **Fix:** Probe in a subshell before sourcing (`( source "$HEREDOC_LIB" </dev/null && declare -F heredoc_nonexec ) >/dev/null 2>&1 || HEREDOC_LIB=""`), or call the classifier through `bash -c` per row; land the fence's lib-only early return in the same change as the library.
- **Reference:** CWE-705 Incorrect Control Flow Scoping — https://cwe.mitre.org/data/definitions/705.html

### [MED-003] App-zone permission of `implementing-tasks` widened `read` → `read-write` with no origin, decision row, test or mention in the description

- **Severity:** MEDIUM (confidence: medium) — Confirmed by cross-model review (DISS-C-001, claude-headless, MEDIUM/authz)
- **File:** `head/.claude/skills/implementing-tasks/SKILL.md:28`
- **Issue:** The frontmatter `zones.app.permission` changes from `read` to `permission: read-write` (`SKILL.md:28`) inside a sprint about guards, control arms, task kinds and rule paths. `pr/PR.md` is the title only. The GLOSSARY entry added in the same diff still says the App zone "needs confirmation before a write" (`head/.claude/loa/GLOSSARY.md:91`), and `reviewing-code/SKILL.md:135` now defers to the frontmatter for zone rules, so the manifest is becoming the authority at the moment it is widened unannounced. The change is plausibly correct (implementing-tasks is the skill that writes application code, and `implement-gate.sh` still asks on app-zone writes outside `/implement`), but a permission widening in a security-relevant manifest is exactly what the surgical-change rule and the DEC ledger exist to record.
- **Impact:** Policy drift without an audit trail: the only skill with app read-write is now so by a drive-by, and nothing asserts that every other skill stays `read`.
- **Fix:** Name the widening in the PR description and a DEC row (or revert it to a dedicated change); add a bats assertion in `validate-skill-capabilities.sh` or `tests/unit/` that only `implementing-tasks` declares app `read-write`; reconcile the GLOSSARY Zone entry.
- **Reference:** CWE-250 Execution with Unnecessary Privileges — https://cwe.mitre.org/data/definitions/250.html ; OWASP A01:2021 Broken Access Control — https://owasp.org/Top10/A01_2021-Broken_Access_Control/

---

## Low Priority Issues

### [LOW-001] Transport-failure classifier matches ordinary model output
- **File:** `head/evals/harness/run-arms.sh:314`
- **Issue:** `grep -qiE 'rate.?limit|overloaded|…|network|socket hang up|5[0-9][0-9] ' "$err" "$out"` runs over `agent-output.json`, which carries the model's own result text. Any 500–599 followed by a space, or the word "network", classifies an agent error as transport, costing a `--retry-wait` sleep, a second CLI call and `attempts: 2`.
- **Fix:** Anchor to an HTTP-status context (`(status|HTTP|error)[^0-9]{0,8}5[0-9][0-9]\b`) and grep stderr only for the free-text markers.
- **Reference:** CWE-185 Incorrect Regular Expression — https://cwe.mitre.org/data/definitions/185.html

### [LOW-002] The `replay: true` audit tag is taken from an unauthenticated environment variable
- **File:** `head/.claude/hooks/safety/block-destructive-bash.sh:529` (also `:782`, `:1366`, `:1521`); consumer `head/.claude/scripts/guard-yield.sh:499`
- **Issue:** `--arg replay "${LOA_AUDIT_REPLAY:-}"` … `+ (if $replay == "1" then {replay: true} else {} end)`. `guard-yield.sh` excludes every flagged row from `real_blocks_30d`. If `LOA_AUDIT_REPLAY=1` reaches the hook environment of a live session (a settings `env` block, a shell profile, a CI job that forgot to unset it) every real block and every FR-SZ/FR-MERGE-2 override is recorded as replay. Mitigation already present: the yield reports the excluded count per rule (`replay_rows_by_rule.flag`), so the drop is visible, not silent. (Cross-model DISS-C-003, LOW; the model's own `export` inside a Bash tool call does not reach the hook process.)
- **Fix:** Have the replay harnesses point `LOA_REPO_ROOT` at a scratch dir (run-corpus.sh already does, `head/tests/fixtures/fence-corpus/run-corpus.sh:34`) and treat the flag as secondary; or record the hook's parent pid/cwd so replay can be inferred without trusting the variable.
- **Reference:** CWE-807 Reliance on Untrusted Inputs in a Security Decision — https://cwe.mitre.org/data/definitions/807.html

### [LOW-003] Sixteen floor guards are fence rows whose behaviour is not byte-pinned
- **File:** `head/.claude/data/floor.yaml:46` (floor_files) vs `:15-30` (floor_guards)
- **Issue:** `floor_files` lists `verdict-derive.sh`, `adversarial-review-gate.sh`, `settings.deny.json`, `user-invoked-commands.txt`; it omits `block-destructive-bash.sh` (which implements every `fence:FR-SZ*` and `fence:FR-1.2b` floor row and is edited by this very PR), `settings.json` (the registration that arms it) and `guard-origins.yaml` (where `floor: true` lives). FS-2…FS-4 pin corpus rows, registrations and the call-site list, so a regex relaxation that keeps every call site passes unless `run-corpus.sh` runs in CI, which this change does not add. (Cross-model DISS-C-002, MEDIUM/config; triaged LOW: FS-3/FS-4 already cover registration and call-site removal, leaving regex weakening as the residual gap.)
- **Fix:** Add `tests/fixtures/fence-corpus/run-corpus.sh` to `bats-tests.yml`, or state in `floor.yaml` that fence rows are behaviour-pinned via the corpus and add the fence's registration assertion to the floor text. Document that `LOA_ALLOW_STATE_ZONE_EXEC_WRITE` is an audited bypass outside `floor_keys`' reach.
- **Reference:** CWE-693 Protection Mechanism Failure — https://cwe.mitre.org/data/definitions/693.html

### [LOW-004] `floor_keys` names a config namespace nothing in the change reads
- **File:** `head/.claude/data/floor.yaml:41`
- **Issue:** `"destructive_command_guard.*"` is listed, but the head fence has no such key and `head/.claude/data/guard-origins.yaml:162` says `knob: none` for the fence row. A forward reference to a later sprint's knob; until it lands the two tracked files read as a contradiction.
- **Fix:** A one-line comment naming the sprint that introduces the key.
- **Reference:** CWE-1068 Inconsistency Between Implementation and Documented Design — https://cwe.mitre.org/data/definitions/1068.html

### [LOW-005] Byte identity to `origin/main` leaves no path for a deliberate floor edit
- **File:** `head/tests/unit/floor-snapshot.bats:25`
- **Issue:** FS-1…FS-4 compare floor files to `origin/main`; by construction any PR that intentionally changes `verdict-derive.sh` or a registration is red until merged and the suite is vacuous on `main`. The first legitimate floor edit will be made with the test skipped or deleted.
- **Fix:** Document the intended path (an env override checked alongside the `FLOOR_SHA256` pin, or a skip when the PR carries a DEC row naming the floor change).
- **Reference:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html

### [LOW-006] `outside_repo` compares the row's logical cwd to physical roots
- **File:** `head/.claude/scripts/guard-yield.sh:502`
- **Issue:** `ROOT` and `MAIN_ROOT` are `pwd -P` (`:113`, `:461`); the audit row's `cwd` is the hook's logical `$PWD`. On a checkout reached through a symlinked path every live block classifies as outside the repository and therefore as a likely false positive, deflating `real_blocks_30d` to zero.
- **Fix:** Compare against both the logical and physical root, or `realpath` the row's cwd when it still exists.
- **Reference:** CWE-706 Use of Incorrectly-Resolved Name or Reference — https://cwe.mitre.org/data/definitions/706.html

### [LOW-007] Hook rows are keyed by script basename
- **File:** `head/.claude/scripts/guard-yield.sh:510`
- **Issue:** `$hookid` maps `.rel | split("/") | last | sub("\\.sh$"; "")` → id, because audit rows carry only `hook: "<basename>"`. Two registered hooks sharing a basename in different directories collapse to whichever `from_entries` keeps last and the other's blocks are misattributed. No collision among today's 30 registrations.
- **Fix:** A duplicate-basename check in the cross-check section (exit 5), so the invariant is enforced rather than assumed.
- **Reference:** CWE-694 Use of Multiple Resources with Duplicate Identifier — https://cwe.mitre.org/data/definitions/694.html

### [LOW-008] The burst rule erases a live retry loop
- **File:** `head/.claude/scripts/guard-yield.sh:519`
- **Issue:** `map(select(length >= $burst_rows) | .[0] | minute)` drops every block row in any UTC minute with ten or more, whatever its cwd. A live session that trips the fence ten times in a minute vanishes from the yield as replay; only `replay_rows_by_rule.burst` records it.
- **Fix:** Require the burst rows to share a cwd under `$tmp` or a test marker, or exempt rows whose cwd is the repository root.
- **Reference:** CWE-1023 Incomplete Comparison with Missing Factors — https://cwe.mitre.org/data/definitions/1023.html

### [LOW-009] Two parsers of the `kind:` token disagree
- **File:** `head/.claude/scripts/validate-artifact.sh:1023` vs `head/tools/cycle-ratio.sh:100`
- **Issue:** The validator strips inline code spans before counting tokens (`gsub(/`[^`]*`/, "", t)`); `cycle-ratio.sh` matches the raw line. A backticked `` `kind: mechanical` `` fails validation (KINDS-8) but is counted in the release-notes line.
- **Fix:** Extract the token rule into one awk function both scripts source (the `md-fence.awk` pattern exists), or add the code-span strip to `cycle-ratio.sh`.
- **Reference:** CWE-436 Interpretation Conflict — https://cwe.mitre.org/data/definitions/436.html

### [LOW-010] The reviewer prompt loses its enumerated security red flags
- **File:** `head/.claude/skills/reviewing-code/SKILL.md:284`
- **Issue:** "Checklists, Red Flags and Mermaid standards: `resources/REFERENCE.md`." replaces the inline list (private keys, SQL concatenation, unvalidated input, empty catch blocks, missing tests, N+1 queries). Whether REFERENCE.md is loaded now depends on the model following the pointer. (Cross-model DISS-C-004, LOW; a prompt-budget cut, PB-9 pins the budget.)
- **Fix:** Keep a one-line enumerated list (a few dozen bytes) or declare REFERENCE.md under `inputs:` so it loads mechanically.
- **Reference:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html

### [LOW-011] Path-scoping the stash rule narrows the prose guard
- **File:** `head/.claude/rules/stash-safety.md:3`
- **Issue:** `paths:` limits the rule to `**/*.sh`, `**/*.bats`, `.claude/scripts/**`, `.claude/hooks/**`. A session editing only Markdown or YAML that runs `git stash push/pop` through Bash no longer loads the prose guard; the mechanical floor (`fence:FR-1.2b`) covers only the output-swallowing form. RP-2 pins the globs to the SDD, so this is the SDD's decision; recorded so the trade-off is visible when the `no_rule_files` arm reports.
- **Fix:** None required; note the trade-off in the rule's Origin section.
- **Reference:** CWE-693 Protection Mechanism Failure — https://cwe.mitre.org/data/definitions/693.html

### [LOW-012] A failed `jq` in the Karpathy toggle is swallowed and leaves a `.tmp`
- **File:** `head/evals/harness/execute-agent.sh:256`
- **Issue:** `jq '…' "$cj" > "$cj.tmp" && mv "$cj.tmp" "$cj"` inside `apply_toggles`, which the caller invokes as `apply_toggles || exit 2`, so `set -e` is suspended; a malformed `constraints.json` leaves the Karpathy rows in place and a stray `.tmp`, with no evidence entry and no exit 2. Today the sandbox never holds `.claude/data/constraints.json` (only the skill, rules and CLAUDE.loa.md are materialised, `:139-149`), so the branch is dormant.
- **Fix:** `|| { echo "ERROR: karpathy_block toggle: constraints.json edit failed" >&2; return 2; }` and record the row count removed.
- **Reference:** CWE-392 Missing Report of Error Condition — https://cwe.mitre.org/data/definitions/392.html

### [LOW-013] A manifest without an `approved` key is treated as approved
- **File:** `head/evals/harness/run-arms.sh:115`
- **Issue:** `jq -r 'if has("approved") then .approved else true end'`. The planted-defect manifests (pr-01…pr-10, built by `build-review-corpus.sh`) carry no key and are meant to pass; a record manifest assembled by hand without the key passes the approval gate too, and the README says only that "run-arms.sh refuses unapproved fixtures" (`head/evals/README.md:521`).
- **Fix:** Key the default on `corpus.tsv`'s `kind` column (`record` rows require the key) or have `build-review-corpus.sh` write `approved: true` explicitly.
- **Reference:** CWE-1188 Initialization of a Resource with an Insecure Default — https://cwe.mitre.org/data/definitions/1188.html

### [LOW-014] A flag-shaped record ref reaches `git`
- **File:** `head/evals/harness/seed-corpus-from-record.sh:271`
- **Issue:** `re.match(r"^[A-Za-z0-9._/-]+$", args.record_ref)` admits a leading `-`, so `--all`-shaped values are passed to `git rev-parse --verify --quiet <ref>` (`:302`) and `git show <ref>:<path>` (`:102`) as options. Every observed shape fails closed (rev-parse rejects an option where it needs one revision), and this is an operator-run local tool, but `tools/cycle-ratio.sh:81-82` guards the same class explicitly, so the two are inconsistent.
- **Fix:** Reject a leading `-` (`^[A-Za-z0-9._][A-Za-z0-9._/-]*$`) and pass refs after `--` where git accepts it.
- **Reference:** CWE-88 Improper Neutralization of Argument Delimiters in a Command — https://cwe.mitre.org/data/definitions/88.html

### [LOW-015] No operator note that the register is a tracked artefact to regenerate
- **File:** `head/evals/README.md:504` (the only new prose for the sprint), `head/.claude/loa/reference/hooks-reference.md:168`
- **Issue:** The register's regenerate rule lives in the `guard-origins.yaml` header and the script header; nothing in `CLAUDE.loa.md`'s scripts reference or a CHANGELOG entry says that editing `guard-origins.yaml` or `settings.json` now requires `guard-yield.sh --hooks-table` before CI passes, nor that the permission widening in MED-003 happened. (CHANGELOG.md is release-pipeline owned in this repository, per the seeder's exclusion list at `seed-corpus-from-record.sh:307`, so its absence is not a blocker.)
- **Fix:** One line in `scripts-reference.md` and the PR description.
- **Reference:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html

---

## Observations (not tallied)

- `head/evals/harness/run-arms.sh:301` — `$(find …)` unquoted (SC2046 acknowledged inline); a `--results-dir` with spaces breaks the suite aggregate. Operator-controlled path; noted only.
- `head/.claude/scripts/guard-yield.sh:457-458` — `TMP_PREFIX` of `/` (TMPDIR=/) would class every row as replay; implausible configuration, noted only.
- Review demotions: the review trailer's `excluded` is 0; there is nothing to confirm or re-tally (`excluded_confirmed: 0`).

---

## Cross-Model Security Observations

`adversarial-audit.json`: status `clean`, primary `gpt-5.5-pro` returned no findings; companion `claude-headless` (independent voice, succeeded) returned four: DISS-C-001 (MEDIUM, authz) → adopted as MED-003; DISS-C-002 (MEDIUM, config) → triaged LOW-003 (FS-3/FS-4 already pin registration and call sites; the residual is regex weakening); DISS-C-003 (LOW) → LOW-002; DISS-C-004 (LOW) → LOW-010. `degraded: false`; no DEGRADED_SECURITY_REVIEW marker. Primary and companion both ran on `--diff-file pr/head.diff` (sha256 `5b9a64da…`).

## Rejected dissent payloads

- none: `adversarial-audit.json` `metadata.rejected_summary` is `[]`, `rejected_sidecars` is `[]`, and no `adversarial-rejected-audit*.jsonl` sidecar sits beside the envelope.

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added — secret-shape scan over `pr/head` (AWS, OpenAI, GitHub, Anthropic, Slack, PEM) found nothing; the only key-shaped string is assembled at test time in SC-2
- [x] Input validation on all new entry points — hook commands parsed against one schema with control-character rejection (`guard-yield.sh:192-209`); `--now`, `--window-days`, arm ids, fixture ids, SHAs, `--by`, `--batch`, `--model` pattern-checked; table cells sanitised (`JQ_DEFS cell`)
- [x] Authentication/authorization — N/A for the scripts; the executor confines the agent (`--restricted --tools Read,Grep,Glob,Write`) and strips non-CLI credentials and session coupling (EA-10/11); MED-003 records the one permission change
- [x] No injection vulnerabilities — all JSON built with `jq --arg/--argjson`; Python runs under `-I`; `yq` queries use `strenv`; `--by` is pattern-restricted (SC-4 proves `x;$(id)` is refused)
- [x] Error handling doesn't leak info — yield outputs carry no command text, cwd, host or model (GY-5); hidden labels never enter the sandbox copy
- [x] Tests cover security paths — GO-10…14, GY-5, AT-9/10, SC-2/4/6, RG-27 exercise the refusal and privacy paths; gaps noted in MED-001 (rule_files exit-2 case) and LOW-007

---

## Rubric Scores

| Dimension | Score | Basis |
|-----------|-------|-------|
| SEC-IV Input Validation | 5 | allowlist patterns at every CLI and data boundary; fail-closed schema parse of hook commands |
| SEC-AZ Authorization | 4 | executor confinement sound; one unrecorded permission widening (MED-003) |
| SEC-CI Confidentiality | 5 | privacy boundary tested; secret redaction and no-secrets scan fail closed |
| SEC-IN Injection | 5 | no string-built JSON or shell; `python3 -I` throughout |
| SEC-AV Resilience | 3 | one toggle fails open (MED-001); one `source` can silently end a run (MED-002) |
| ARCH-MO Modularity | 4 | register / yield / arms / seeder cleanly separated; two `kind:` parsers (LOW-009) |
| CQ-TC Test Coverage | 4 | every seam has a suite; the register itself and the rule_files exit-2 case are untested |
| DEVOPS-CI | 2 | the new gate is red on the PR tree (HIGH-001) |

---

## Documentation Audit

No `documentation-coherence-*.md` reports exist under `grimoires/loa/a2a/subagent-reports/` (the directory is not present in this evaluation mount); verified manually. `evals/README.md:504-532` documents the arms, seeder, approval and report path; `hooks-reference.md:168` documents the generated table; `GLOSSARY.md` gains the four task-kind terms and `validate-artifact.sh --type glossary` accepts it (KINDS/GO runs). Gaps: LOW-015 (regenerate rule for operators) and MED-003 (permission widening unmentioned). No secrets or internal URLs in docs or comments.

---

## Scope Limits

- `evals/fixtures/review-prs/` (pr-01…pr-18, manifests, labels, SHA256SUMS), `evals/harness/sandbox.sh`, `evals/harness/grade.sh`, `evals/graders/no-secrets.sh` and `tools/check-prompt-budget.sh` are repository files outside the change and absent from this mount; RA-1…5, EA-8/9, SC-1…6, RG-16/17, BF-4, PB-1…9 and SEAMS-9 are therefore unverified here. A stub `tools/check-prompt-budget.sh` was placed only so GO-6's existence check could run.
- The scratch root uses this workspace's `.claude/settings.json` and hooks (a newer Loa than the PR base); GO-3/GO-8 passing against it means the PR's origin map matches that newer registration set, which is what `--check` in CI will see.

---

## Next Steps

1. Generate and commit `grimoires/loa/guards.md`; confirm `guard-yield.sh --check` and GO-9 are green on the PR tree (HIGH-001).
2. Make the `rule_files` toggle fail closed and add the AT-9 case (MED-001); probe the heredoc library in a subshell (MED-002); record the permission widening or revert it (MED-003).
3. Address the low findings as convenient; add an `## AC Verification` walkthrough to the implementation report.
4. Run `/implement sprint-1` for the fixes, then `/review-sprint sprint-1` and `/audit-sprint sprint-1` again.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":3,"low":15},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-22T08:05:00Z"} -->
