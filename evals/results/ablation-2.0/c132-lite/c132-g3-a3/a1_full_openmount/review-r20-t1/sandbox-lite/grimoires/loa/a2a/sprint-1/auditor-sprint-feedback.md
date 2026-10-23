# Security Audit: sprint-1 (PR cycle-129 sprint-256)

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-23
**Task:** review-r20
**Scope:** `pr/head.diff` (68 files). Base files are in `pr/base/`, head files in `pr/head/`. The implementation report is `pr/PR.md`, mirrored in `grimoires/loa/a2a/sprint-1/reviewer.md`.
**Review gate input:** `grimoires/loa/a2a/sprint-1/engineer-feedback.md` (verdict CHANGES_REQUIRED, excluded 0)

## Verdict

**CHANGES_REQUIRED**

The tally has four high findings, and any high forces this verdict. The heredoc classifier fails open against shapes the base fence blocked. Two run-position paths crash on jq 1.6. The default profile silently turns off two security controls that used to default on.

## Prerequisites and scope limits

- **Review gate not passed.** Phase 0 requires `engineer-feedback.md` to say "All good". It says CHANGES_REQUIRED with three high findings. Normally the audit would stop here. The phase instruction requires a feedback file, so the audit ran in full and this report records the result.
- **Adversarial review present.** `adversarial-review.json` carries `metadata.model: gpt-5.5-pro`, as the gate requires.
- **Integrity pre-check.** `detect-drift.sh` reports no significant drift. `integrity_enforcement` is not set in `.loa.config.yaml`.
- **Input guardrails.** The orchestrator returned `PROCEED`.
- **Scope script.** `security-audit-scope.sh` scans the installed repository, not the frozen PR, so the PR files were catalogued by hand. The diff touches System Zone hooks, scripts, skills, tests and one CI workflow. It does not touch `src/`, `lib/` or `app/`.
- **No live replay of fence bypasses.** The classifier findings come from reading the code paths, not from running crafted destructive payloads.
- **Not assessed.** The reviewer reported that the PF-5 floor test in `head/tests/unit/profile-floor.bats:141` fails. This audit did not reproduce it, and it is not tallied here.
- **Host.** jq 1.6, bats and yq are installed.

## Security dissenter analysis (Phase 1C)

`adversarial-review.sh --type audit --sprint-id sprint-1 --diff-file pr/head.diff --json` finished with status `reviewed`. The primary voice was gpt-5.5-pro. The companion voice, claude-headless, succeeded and counted as an independent voice. The run reports `degraded: false` with no degraded-security-review marker. It wrote `adversarial-audit.json` with eight findings, and `adversarial-rejected-audit.jsonl` is empty.

| Dissent finding | Disposition |
|-----------------|-------------|
| DISS-001 (HIGH): a glob reference to a heredoc target escapes the same-line exec check | Confirmed by reading the code. Merged into finding H-1 |
| DISS-C-001 (HIGH): danger-level enforcement defaults off | Confirmed. Merged into H-4 |
| DISS-C-002 (HIGH): input guardrails default off under `standard` | Confirmed. Merged into H-4 |
| DISS-C-003 (MEDIUM): the implement marker is self-issued and not bound to a session | Confirmed. M-4 |
| DISS-C-004 (MEDIUM): C-TEAM constraints deleted | Partly confirmed. The hooks still enforce the rules from hardcoded logic and never read `constraints.json`. Downgraded to L-3 |
| DISS-C-005 (MEDIUM): the hand-written tokenizer can diverge from bash | Same root cause as H-1. Merged into H-1 |
| DISS-C-006 (LOW): the knob path falls back to the working directory | Dismissed. Turning the knob off only restores the stricter pre-cycle scrub (`head/.claude/hooks/safety/block-destructive-bash.sh:730-748`), so a planted config can only tighten |
| DISS-C-007 (LOW): a mistyped gate mode silently falls back to ask | Confirmed. L-4 |

## Rejected dissent payloads

None. `metadata.rejected_count` is 0, `rejected_summary` is empty and the sidecar file has no rows.

## Findings

### HIGH

**H-1. The heredoc classifier drops the body when a pipeline or glob later executes the target.** Severity high, confidence high. Category: Security. Matches the reviewer's item 1 and DISS-001.

- `head/.claude/hooks/safety/block-destructive-bash.sh:612` skips any line that does not contain the literal basename: `[[ "${_bdb_hd_L[k]}" == *"$b"* ]] || continue`. A glob or variable that expands to the target never matches, so that line is never inspected.
- `head/.claude/hooks/safety/block-destructive-bash.sh:626-631` checks only the command word of the segment that names the target: `_bdb_hd_segword "${_bdb_hd_tok[*]:start:j-start}"` then `if ! _bdb_hd_is_safe_reader "$cw" ...`. Segments are split on `|`. When a safe reader reads the target and pipes it into an interpreter in a later segment, the interpreter segment never names the target and is never judged.
- In both cases the class stays `nonexec`. `_bdb_hd_scan_body` (`head/.claude/hooks/safety/block-destructive-bash.sh:576-604`) then keeps only fence-verb segments, and with a quoted delimiter a destructive command nested inside another command's arguments is dropped. The scrubbed copy at `head/.claude/hooks/safety/block-destructive-bash.sh:1063` hides the destructive text from every later rule.
- **Failure scenario.** An autonomous agent writes a destructive body to a plain-named file through a non-executing heredoc. Later in the same Bash call it runs that file through a glob or a reader-to-interpreter pipe. The base hook scanned the whole body and blocked. The head hook allows it. The reviewer replayed this class and saw five of seven shapes go from blocked to allowed.
- The design comment and `head/.claude/loa/reference/hooks-reference.md:294` both promise a full scan whenever the target is named outside a safe reader. The code does not keep that promise, so this is a regression and not the documented later-command gap.
- **Reference.** CWE-184, Incomplete List of Disallowed Inputs: https://cwe.mitre.org/data/definitions/184.html. CWE-636, Not Failing Securely: https://cwe.mitre.org/data/definitions/636.html
- **Remediation.** Fail closed. If any non-body line holds an interpreter or runner word, a substitution, an unquoted glob or a variable expansion, classify the heredoc as `interpreter` and scan the full body. Add corpus `D` rows for the pipe and glob shapes. Run `run-corpus.sh --rows` against the base hook to confirm that no row goes from blocked to allowed.

**H-2. `run-checkpoint.sh derive` cannot compile on jq 1.6, which leaves the run position inert.** Severity high, confidence high. Category: Code Quality and DevOps. Matches the reviewer's item 2.

- `head/.claude/scripts/run-checkpoint.sh:378-380` binds `--arg label "$label"` and reads `$label` inside the program. `label` is a keyword in jq 1.6. Reproduced on this host:

```
$ jq -nc --arg label x '$label'
jq: error: syntax error, unexpected label, expecting IDENT or __loc__
```

- **Failure scenario.** Every caller swallows the error, so `derived_at` is never written. `implement_gate.mode: deny` then always degrades to ask with "cache not derived", the breaker is never recomputed, and `/loa` never shows the run line. This is a silent failure of a control on Debian 12 and Ubuntu 22.04, which still ship jq 1.6.
- **Reference.** CWE-754, Improper Check for Unusual or Exceptional Conditions: https://cwe.mitre.org/data/definitions/754.html
- **Remediation.** Rename the variable at lines 378, 380 and 389 to something like `lbl`. Run the bats suites under jq 1.6 in CI.

**H-3. `fb_parse` aborts on a feedback file without a trailer under jq 1.6.** Severity high, confidence high. Category: Code Quality. Matches the reviewer's item 3.

- `head/.claude/scripts/run-checkpoint.sh:224-226`: with no trailer, `tl` and then `pj` are empty. `jq -e 'type == "object"' <<<"$pj"` exits 0 on empty input in jq 1.6, so the `|| pj='{}'` fallback never fires. `head/.claude/scripts/run-checkpoint.sh:232` then fails with `jq: invalid JSON text passed to --argjson`, which reproduces on this host.
- **Failure scenario.** `head/.claude/skills/run-mode/SKILL.md:110` and `:132` route every review and audit round through `record-round`. A legacy feedback file stops the run loop instead of counting as findings. `derive` calls `fb_parse` for both gates at `head/.claude/scripts/run-checkpoint.sh:370-371`, so it fails on the same input.
- **Reference.** CWE-754: https://cwe.mitre.org/data/definitions/754.html
- **Remediation.** Change the guard to `[[ -n "$pj" ]] && jq -e 'type == "object"' <<<"$pj" ... || pj='{}'`, and apply the same guard to `vj` at line 223. Add a bats case for a trailer-less file.

**H-4. The default profile silently turns off input guardrails and danger-level enforcement.** Severity high, confidence high. Category: Security and DevOps. Matches the reviewer's guardrail-defaults observation and DISS-C-001 and DISS-C-002, raised to high.

- `head/.claude/data/profiles.yaml:40-41` sets `guardrails.input.enabled: false` and `guardrails.danger_level.enforce: false` under `standard`, which is the profile used when `loa.profile` is unset.
- `head/.claude/scripts/guardrails-orchestrator.sh:110` now reads `loa_knob guardrails.input.enabled false`. The base read `get_config ".guardrails.input.enabled" "true"` at `base/.claude/scripts/guardrails-orchestrator.sh:106`.
- `head/.claude/scripts/danger-level-enforcer.sh:139-143` now reads `loa_knob guardrails.danger_level.enforce false`. The base read `// true` and returned "Default to enabled" when no config file existed.
- `head/.claude/data/skill-includes/input_guardrails.md:3` now runs the pre-execution guardrails only when the knob prints `true`. The base ran them unless the key was explicitly `false`.
- **Failure scenario.** Any install that never set these keys upgrades and loses prompt-injection and PII screening on every skill that includes the guardrails, plus danger-level gating of high-risk skills in autonomous mode. Nothing is printed. The profiles file calls this "a migration item" (DEC-0161), but the PR ships no CHANGELOG entry, migration note or upgrade warning. The documentation audit treats a CHANGELOG that omits a security change as a blocker.
- **Reference.** CWE-1188, Initialization of a Resource with an Insecure Default: https://cwe.mitre.org/data/definitions/1188.html. CWE-636: https://cwe.mitre.org/data/definitions/636.html
- **Remediation.** Either keep both keys `true` in `standard`, or ship the flip with a CHANGELOG security entry and a one-time upgrade warning for installs that do not set the keys. Consider listing both keys in `floor.yaml` so that `lean` cannot lower them with one line.

### MEDIUM

**M-1. The audit and review skill allowlists do not grant the knob reader that their includes run.** Severity medium, confidence high. Category: Architecture. Matches the reviewer's skill-allowlist observation.

- `head/.claude/skills/auditing-security/SKILL.md:6` and `head/.claude/skills/reviewing-code/SKILL.md:6` do not grant `Bash(.claude/scripts/lib/profile-lib.sh knob *)`. Both set `deny_raw_shell: true`, at lines 35 and 39. Their regenerated includes tell the skill to run that command, at lines 67 and 285 in the audit skill and lines 69 and 297 in the review skill.
- **Failure scenario.** The harness refuses the call, so the input-guardrail check and the retrospective postlude never run in the two gate skills. The retrospective defaults on under `standard`. The installed copy of the audit skill in this workspace already carries the grant, which shows the fix is known but missing from the PR.
- **Reference.** CWE-1068, Inconsistency Between Implementation and Documented Design: https://cwe.mitre.org/data/definitions/1068.html
- **Remediation.** Add the grant to both frontmatters and their `capabilities.execute_commands`. Make `validate-skill-capabilities.sh` check that every command an include tells the skill to run is in its allowlist.

**M-2. Deny mode denies a RUNNING cache that the sanction check calls stale.** Severity medium, confidence high. Category: Security (authorization logic). Matches DISS-C-001 from the review dissent.

- `head/.claude/hooks/compliance/implement-gate.sh:557-569`: `read_position` treats the position as known whenever `derived_at` is fresh. It never checks `timestamps.last_activity`, which `check_implementation_active` requires at `head/.claude/hooks/compliance/implement-gate.sh:504-507`.
- **Failure scenario.** A run cache with `derived_at` inside `stale_hours` and `last_activity` older than 24 hours gets no sanction. It is denied with the contradictory reason "derived position: RUNNING". This fails closed, but it blocks a legitimate run with a misleading message.
- **Reference.** CWE-1068: https://cwe.mitre.org/data/definitions/1068.html
- **Remediation.** Use one freshness rule in both functions. Have `derive` always stamp `last_activity`.

**M-3. The implement marker expires after two hours and nothing refreshes it.** Severity medium, confidence medium. Category: Code Quality.

- `head/.claude/hooks/compliance/implement-gate.sh:550` reads `_ig_within 7200 "$started" || return 2`. `run-checkpoint.sh write` never touches the marker.
- **Failure scenario.** An `/implement` or `/bug` session that runs past two hours starts asking on every App Zone write, or is denied under `deny`.
- **Remediation.** Refresh `started_at` on each `run-checkpoint.sh write`, or key the window on a heartbeat field.

**M-4. The new marker sanction can be issued by the model itself and is not bound to a session.** Severity medium, confidence high. Category: Security (authorization). Matches DISS-C-003 and the reviewer's low-severity note, raised to medium.

- `head/.claude/hooks/compliance/implement-gate.sh:545-552` accepts any well-formed `.run/implement-active.json` with a recent `started_at`. The skills write it with `run-checkpoint.sh mark` through Bash, and the Write and Edit trust-input guard does not see that path.
- **Failure scenario.** In the default `ask` mode, an agent that runs `mark` from Bash gets two hours of silent App Zone writes without `/implement`. The base gate asked on every such write. Under `deny` the same step turns the new fence into an allow. The trust in `.run/` sprint-state files is a documented accepted gap, but this is a new and cheaper sanction path that the hooks reference does not name.
- **Reference.** CWE-345, Insufficient Verification of Data Authenticity: https://cwe.mitre.org/data/definitions/345.html
- **Remediation.** Bind the marker to the session, for example with a session id from the hook payload. Name the path explicitly in the accepted-gap list in `hooks-reference.md`.

### LOW

**L-1. The derived-cache check also applies in ask mode.** Severity low, confidence medium.
`head/.claude/hooks/compliance/implement-gate.sh:510` calls `_ig_derived_ok` in every mode. A cache whose `derived_at` is older than `stale_hours` loses its run sanction even when activity is fresh. The header at `head/.claude/hooks/compliance/implement-gate.sh:9-10` says ask behaves "exactly as before". Reference: CWE-1068, https://cwe.mitre.org/data/definitions/1068.html

**L-2. The size warning still says "Session diff total".** Severity low, confidence high.
`head/.claude/hooks/quality/karpathy-surgical-diff-check.sh:193` keeps the old wording, but the total is now counted per task.

**L-3. The C-TEAM rules left the always-loaded kernel.** Severity low, confidence medium.
`head/.claude/loa/reference/agent-teams-reference.md:32-45` now holds the five rules that `constraints.json` used to carry. The team hooks still enforce C-TEAM-001, 003 and 005 from hardcoded logic, but only when `LOA_TEAM_MEMBER` is exported. C-TEAM-002 and 004 are prose-only, and a teammate that never loads this page never sees them.

**L-4. A mistyped gate mode falls back to ask with no warning.** Severity low, confidence high.
`head/.claude/hooks/compliance/implement-gate.sh:184-198` accepts only `ask`, `telemetry` or `deny` and silently keeps `ask` for anything else. An operator who means to enable `deny` gets weaker enforcement with no message. Ask is a safe fallback, but the gate should print one stderr warning.

## Observations (not tallied)

- **Pre-existing test parse error.** `head/tests/unit/karpathy-surgical-diff.bats:165` contains `local REDACTED-TEST-SECRET"`, which does not parse, so none of the KS cases run. The same line exists in `base/tests/unit/karpathy-surgical-diff-hook.bats:134`. It looks like a redaction artifact of the frozen snapshot, not a defect this PR introduced. The per-task rewrite of the surgical-diff hook still ships with no test that ran here.
- **Reporting-only classifier use.** `.claude/scripts/guard-yield.sh` uses the classifier only to label blocks as likely false positives in a report. It never relaxes enforcement.
- **Library mode is safe.** The fence sets no shell options before the library-mode return at `head/.claude/hooks/safety/block-destructive-bash.sh:762-764`. That return honours `BDB_LIB_ONLY=1` only when the file is sourced, so an environment variable cannot switch the fence off.

## Verified safe

- **Key paths.** `head/.claude/scripts/lib/profile-lib.sh:222` validates key paths against `^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)*$` before they reach a yq expression. The resolved values go through jq `--arg`.
- **Floor and cache.** `profile-lib.sh` ignores profile keys that name floor keys, and the floor file exists in the repository. The cache write is atomic, using a temp file and `mv`.
- **CI workflow.** `head/.github/workflows/check-prompt-budget.yml` triggers on `pull_request` with no secrets, pins both actions by SHA and interpolates no event fields.
- **Deny reply.** The deny reply follows the PreToolUse contract, built with `jq --arg` at `head/.claude/hooks/compliance/implement-gate.sh:571-573`.
- **No secrets.** No hardcoded secrets or internal URLs appear in the diff.

## Documentation audit

- No documentation-coherence report exists under `grimoires/loa/a2a/subagent-reports/`, and none was verified by hand.
- The implementation report has no AC verification section.
- No CHANGELOG entry covers the security default change in H-4, which is a blocker under this skill.

## Review demotions

The review trailer counts `excluded: 0`, so no high-severity finding was demoted to confirm. `excluded_confirmed` is 0.

## Rubric scores

| Dimension | Score (1-5) | Basis |
|-----------|-------------|-------|
| Security | 2 | H-1 fence regression, H-4 insecure defaults, M-4 self-issued sanction |
| Architecture | 3 | Sound resolver and gate design, inconsistent freshness rules (M-2, L-1) |
| Code Quality | 2 | H-2 and H-3 crash on a supported jq version, and the new tests did not run on it |
| DevOps | 3 | Pinned CI actions, no jq 1.6 job, no migration note |
| Blockchain/Crypto | N/A | Not applicable |

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 4 |
| Medium | 4 |
| Low | 4 |

## Required before re-audit

1. Fix H-1 through H-4 and add the regression tests and corpus rows named above.
2. Fix M-1 so that both gate skills can run their own includes.
3. Get the review gate to "All good", then run `/audit-sprint sprint-1` again.

**Verdict:** CHANGES_REQUIRED

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":4,"medium":4,"low":4},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-23T04:00:00Z"} -->
