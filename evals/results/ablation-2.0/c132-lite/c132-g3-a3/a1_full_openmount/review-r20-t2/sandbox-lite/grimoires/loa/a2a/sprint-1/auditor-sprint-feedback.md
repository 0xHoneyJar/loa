# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-23
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Scope:** `pr/head.diff` — sprint-256 (cycle-129): implement-gate modes, file-authoritative run position (`run-checkpoint.sh derive`), fail-closed heredoc consumer classifier, `loa.profile` resolver, per-task Karpathy surgical hook, Agent Teams table pruning, prose diet. 68 files.

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

The sprint tightens the implement gate (tighten-only claims, deny mode with fail-ask on unknown position, trust-input asks), keeps floor keys unreachable from profiles, and ships a fence classifier that is fail-closed on every parse failure. The fence corpus (benign 89/89, dangerous 142/142, p95 57 ms), `profile-lib.bats` (17/17) and `lint-invariants.bats` (9/9) pass on the head tree in this environment.

Two defects block the merge. The heredoc classifier's "non-executing" path drops body segments the pre-cycle fence scanned, and its same-command execution detection is a literal-basename match, so a body written by an allowlisted consumer and executed in the same command through a non-literal reference (glob, pipe from a safe reader, substitution, indirect variable, an implicit consumer such as `make`), or a body whose destructive segment is prefixed by a shell keyword or split by a backslash-newline continuation, reaches execution unscanned. This regresses two floor fences (FR-SZ2-REDIR, FR-SZ-COPY) inside the fence's own per-command scope. Second, `run-checkpoint.sh derive` and `record-round` fail on jq 1.6 (the version installed here and the only one the repository has ever required), so the file-authoritative run position this sprint introduces is inert on such hosts and the deny mode can never reach a known position.

Pre-flight note: Phase 0 of this skill expects `engineer-feedback.md` to read "All good". It reads CHANGES REQUIRED (2 HIGH); the audit ran anyway on the task's instruction, and its findings are independent of the review's.

**Security Issues Found:**

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 5 |
| Low | 8 |

Cross-model dissent: two voices (primary `gpt-5.5-pro` answered by `codex-headless`, companion `claude-headless`), `consensus_outcome: consensus`, 2/2 succeeded, `rejected_summary: []`, `degraded: false`. Not a DEGRADED_SECURITY_REVIEW.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] Heredoc classifier: non-executing path drops body content that executes in the same command

**Severity:** HIGH · **Confidence:** high · Confirmed by cross-model review (DISS-001, DISS-C-001, DISS-C-002 of the review round; DISS-001 and DISS-C-001 of this round)
**File:** `head/.claude/hooks/safety/block-destructive-bash.sh:608` (`_bdb_hd_same_line_exec`), `:538` (`_bdb_hd_segword`), `:576` (`_bdb_hd_scan_body`), `:222` (`_bdb_hd_is_safe_reader`)
**Issue:** When a heredoc's consumer classifies `nonexec`, `_bdb_hd_scan_body` (:576) keeps only body segments whose command word is a fence verb and drops every other segment. Four gaps let a body that the pre-cycle fence scanned in full reach execution unscanned:

1. `_bdb_hd_same_line_exec` (:608) recognises an executing reference only when a later token's literal basename equals the heredoc's write target (`[[ "$u" == "$b" ]]`, :627). A glob, a process or command substitution, an indirect variable, a pipe from a reader, or a consumer that reads the file implicitly (`make` after writing a Makefile) is not a match, so the heredoc stays `nonexec`.
2. `_bdb_hd_is_safe_reader` (:222) lists `cat`, `git` and `gh`. A pipeline that feeds the written file from `cat` into a shell, or a `git -c core.sshCommand=…` / `gh extension install` naming it, counts as a read.
3. `_bdb_hd_segword` (:538) strips wrapper words and assignments but not shell keywords (`if then else elif fi while until do done case esac`), so a destructive command after `then` or `do` has command word `then`/`do` and is dropped rather than kept. The review verified both an `if …; then rm -rf …; fi` and a `for …; do rm -rf …; done` body scrub to nothing.
4. `_bdb_hd_scan_body` scans body lines individually and never folds a backslash-newline continuation. In an unquoted heredoc, Bash joins such lines, so a `$(` split across two lines is a command substitution at runtime that the per-line `*'$('*` probe (:583) never sees; combined with (3) its contents are dropped (this round's DISS-001).

The review reproduced six same-command shapes end to end: each exits 0 on the head fence and 2 on the base fence, with bodies writing into `.claude/settings.json` (FR-SZ2-REDIR) and copying into `.claude/hooks/` (FR-SZ-COPY), both `floor_guards`. The documented "Remaining gap" (`head/.claude/loa/reference/hooks-reference.md:298`) covers execution by a *later* command only, so this is a regression inside the fence's stated scope, and the classifier is on by default (`destructive_command_guard.heredoc_classifier: true`).
**Impact:** An autonomous agent (or an injected instruction) writes a helper through an allowlisted consumer and runs it in the same Bash call; the body's System-Zone writes and `rm -rf` segments are never matched. Blast radius: hook scripts, `settings.json`, project source.
**Fix:**
- In `_bdb_hd_same_line_exec`, return 0 (executing) when any non-body line holds `$(`, a backtick, `<(`, `>(`, a glob character inside a token, or a `$`-prefixed token, mirroring `_bdb_hd_ctx_bad`; and whenever any later segment's command word is an interpreter or wrapper (`_bdb_hd_is_interp`) regardless of whether it names the target. Drop `cat`, `git`, `gh` from the safe-reader list when the segment is a pipeline member feeding an interpreter.
- In `_bdb_hd_segword`, strip shell keywords and case-arm patterns before reading the command word, or set `_hd_full=1` in `_bdb_hd_scan_body` when the word is a keyword.
- In `_bdb_hd_scan_body`, when the delimiter is unquoted, fold backslash-newline continuations (or set `_hd_full=1` on any body line ending in a backslash) before the `$(` probe.
- Add corpus rows (expect `block`) for each shape above; add a `make`/`Makefile` row.
**Reference:** CWE-693 Protection Mechanism Failure — https://cwe.mitre.org/data/definitions/693.html ; CWE-184 Incomplete List of Disallowed Inputs — https://cwe.mitre.org/data/definitions/184.html

### [HIGH-002] `run-checkpoint.sh derive` / `record-round` fail on jq 1.6: the file-authoritative run position is inert

**Severity:** HIGH · **Confidence:** high (reproduced)
**File:** `head/.claude/scripts/run-checkpoint.sh:378` (`--arg label` … `$label`), `:225-226` (`fb_parse` empty-trailer probe)
**Issue:** The per-sprint jq program binds `--arg label` and reads `$label` (:380, :389); `label` is a reserved word in jq 1.6, which rejects it:

```
jq: error: syntax error, unexpected label, expecting IDENT or __loc__ … line 2:
      def mine: type == "string" and length > 0 and (. == "sprint-\($gid)" or ($label != "" and . == $label));
jq: 2 compile errors
rc=3
```

(`bash .claude/scripts/run-checkpoint.sh derive --json` on the head tree with this repository's ledger; `jq -n --arg label x '$label'` alone fails the same way.) A second 1.6 incompatibility: `fb_parse` relies on `jq -e 'type == "object"' <<<"$pj"` exiting non-zero on empty input (:226); jq 1.6 exits 0 (verified: `printf '' | jq -e 'type == "object"'; echo $?` → 0), so `pj` stays empty, `--argjson p ''` fails, `fb_parse` prints nothing, and `record-round` exits 2 on any feedback file without a LOA-VERDICT trailer. On the head tree here: `run-checkpoint-derive.bats` 18/22 fail, `run-checkpoint-record-round.bats` RCR-7 fails. The repository declares no jq floor; the implement gate and the fence run on 1.6.
**Impact:** Every `write` and `mark` prints the derive error; `/loa` skips the Run line; `/run-resume` step 0a receives an unhandled exit 3; the implement gate's `deny` mode requires a `derived_at` it never gets, so the only enforcing mode falls back to ask on every write (fail-ask, so not fail-open — but the control the operator opted into never engages, silently).
**Fix:** Rename the binding (`--arg lbl`/`$lbl`) and avoid other jq reserved words as variable names; replace the emptiness probe with `[[ -n "$pj" ]] && jq -e … || pj='{}'`; either keep jq 1.6 compatibility (preferred; nothing else in the tree needs 1.7) or declare and check a jq ≥ 1.7 floor and fail `derive` loudly below it. Run both suites under jq 1.6 in CI.
**Reference:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html ; CWE-1357 Reliance on Insufficiently Trustworthy Component (version drift) — https://cwe.mitre.org/data/definitions/1357.html

---

## Medium Priority Issues

### [MED-001] Guardrail enforcement flips from default-on and fail-closed to default-off and fail-open

- **Severity:** MEDIUM · **Confidence:** high · Confirmed by cross-model review (DISS-C-003)
- **File:** `head/.claude/scripts/danger-level-enforcer.sh:141`, `head/.claude/scripts/guardrails-orchestrator.sh:110`, `head/.claude/data/profiles.yaml:40-41`, `head/.loa.config.yaml.example:1358`
- **Issue:** The base enforcer read `.guardrails.danger_level.enforce // true` and returned enabled when the config was absent or unreadable ("Default to enabled"); the head calls `loa_knob guardrails.danger_level.enforce false` and the `standard` profile defines the key `false`. Verified: with an unparseable config, or with `yq` absent from PATH, the head prints `false` where the base printed `true`. The same flip applies to `guardrails.input.enabled`. The change is a recorded decision (DEC-0161, evidence in the example comment: 82 events, nothing caught, seven false blocks on sanctioned skills), so it is deliberate — but an upgrading installation whose config does not set the keys loses "critical skills always blocked in autonomous mode" with no warning row, no CHANGELOG entry, and no migration note outside the example file.
- **Fix:** Emit one WARN (or a trajectory row) from the enforcer and the orchestrator the first time a run resolves the key from the profile rather than an explicit config value; add the CHANGELOG/migration note; consider keeping `danger_level.enforce` fail-closed on *resolution error* (config unparseable, yq missing) even when the profile default is off.
- **Reference:** CWE-636 Not Failing Securely ('Failing Open') — https://cwe.mitre.org/data/definitions/636.html ; CWE-1188 Insecure Default Initialization of Resource — https://cwe.mitre.org/data/definitions/1188.html

### [MED-002] `LOA_IMPLEMENT_GATE_OVERRIDE=1` sanctions App-Zone writes in every mode, including `deny`

- **Severity:** MEDIUM · **Confidence:** medium · Confirmed by cross-model review (DISS-C-004)
- **File:** `head/.claude/hooks/compliance/implement-gate.sh:590`; documented at `head/.claude/loa/reference/hooks-reference.md:248`
- **Issue:** The variable is new in this PR (absent from the base hook). Any value `1` in the hook's environment allows every App-Zone write with one `allow/override` row and no ask, including under `deny`, the mode the reference calls a fence. The sibling fence states that "an environment variable can never switch the fence off" (`block-destructive-bash.sh:757-760`, library-mode guard). The model cannot set the hook's environment from a tool call, so the threat is a launcher, a CI runner or a settings `env` block carrying the variable; still, a fence whose off switch is an environment variable is weaker than its documentation implies.
- **Fix:** Scope the override to `ask`/`telemetry` (never `deny`), or require it to name the sprint it covers and expire like the marker; print one stderr line when it fires.
- **Reference:** CWE-807 Reliance on Untrusted Inputs in a Security Decision — https://cwe.mitre.org/data/definitions/807.html

### [MED-003] Generic exec-flag test defeats the classifier for the most common heredoc consumers

- **Severity:** MEDIUM · **Confidence:** high · Confirmed by cross-model review (review round DISS-C-003)
- **File:** `head/.claude/hooks/safety/block-destructive-bash.sh:363` (`_bdb_hd_re_exflag`, defined :187)
- **Issue:** `^-[A-Za-z]*[cex][A-Za-z]*$` runs before each consumer's own grammar, so `jq -c`, `jq -e`, `grep -c`, `grep -x`, `sed -n -e p`, `echo -e` classify `interpreter` and fall back to the full scan. Not a bypass (it only tightens), but the #1245 false-positive class the classifier exists to remove still fires for these forms.
- **Fix:** Apply the generic test only to consumers without a dedicated argv grammar, or whitelist the harmless short flags per command before it; add an `allow` corpus row for `jq -c` with a destructive string in the body.

### [MED-004] Karpathy hook latency: ~5× over the base and above the documented budget

- **Severity:** MEDIUM · **Confidence:** high (measured)
- **File:** `head/.claude/hooks/quality/karpathy-surgical-diff-check.sh:131`
- **Issue:** Each Write/Edit now forks `run-checkpoint.sh read --json` (bash plus several jq calls, plus `br show` when beads is installed) and sources `profile-lib.sh` for two knob reads. Measured here over five invocations with a three-line Write payload and no checkpoint file:

| Hook | Mean per invocation |
|------|---------------------|
| base | 28 ms |
| head | 155 ms |

The hooks-reference budgets shell hooks at < 100 ms (`head/.claude/loa/reference/hooks-reference.md:229`); the review measured ≈590 ms with a checkpoint present.
- **Fix:** Read `.checkpoint.task` with one jq straight from `.run/sprint-plan-state.json` (the hook needs no beads verification), and cache the two knob values alongside the summary.

### [MED-005] The per-task key is the last *closed* bead or the sprint, not the active task

- **Severity:** MEDIUM · **Confidence:** medium
- **File:** `head/.claude/hooks/quality/karpathy-surgical-diff-check.sh:131-138`; `head/.claude/skills/reviewing-code/SKILL.md:220`
- **Issue:** `run-checkpoint.sh read --json` returns `.checkpoint.task` only when beads confirms the task **closed** (`cmd_read`, `run-checkpoint.sh:196-205`); otherwise it discards the checkpoint and returns `{checkpoint: null, reason, sprint}`, and the hook falls to `.sprint`. During implementation the key is therefore the bead that just closed, or the sprint whenever `br` is absent or the task is open. The reviewing-code skill tells reviewers to read `<bead>.jsonl` as that bead's diff, which it is not.
- **Fix:** Key on the active bead (first open bead of the sprint, or `.checkpoint.task` without the closed check), and align the SKILL line and the hook header.

---

## Low Priority Issues

### [LOW-001] The marker sanction is self-issuable through Bash and sanctions in `deny`

- **File:** `head/.claude/hooks/compliance/implement-gate.sh:545`; `head/.claude/scripts/run-checkpoint.sh:535` (`cmd_mark` has no run check)
- **Issue:** `.run/implement-active.json` is a trust input for Write/Edit only; `run-checkpoint.sh mark` (or any Bash redirect) can create it outside any run and sanction two hours of App-Zone writes in every mode. The hooks-reference records the class as an accepted gap ("The sanctions trust `.run/` files a Bash command can write", :270). The dissenter rated this HIGH (DISS-C-002); downgraded here because the gate has never seen Bash-path App-Zone writes at all (the C-PROC-001 accepted gap), so the marker adds no capability an agent lacked. The "fence" wording (:234) should say "against Write/Edit".
- **Fix:** Have `mark` refuse when the derived cache is not RUNNING; qualify the fence claim in the reference and the hook header.

### [LOW-002] The deny reason tells the model which key to flip

- **File:** `head/.claude/hooks/compliance/implement-gate.sh:574-576` · Confirmed by cross-model review (DISS-C-006)
- **Issue:** `deny_reason` ends with "or set implement_gate.mode: ask". The reason is rendered to the model; it steers a blocked agent toward weakening the control. The config write asks (trust input), which bounds the risk.
- **Fix:** Point at the sanctioned path only (`/implement`, `/bug`); leave the configuration hint for the operator-facing reference.

### [LOW-003] Agent Teams rules leave the always-loaded kernel

- **File:** `head/.claude/loa/reference/agent-teams-reference.md:32-44`; `head/.claude/data/constraints.json` (C-TEAM-001…005 removed); `head/.claude/loa/CLAUDE.loa.md` (table pruned)
- **Issue:** The five C-TEAM rows, including C-TEAM-005 (teammates never modify `.claude/`, severity critical from a prior incident), are deleted from `constraints.json` and the kernel and now live in the reference only (DEC-0140). The three team hooks stay registered (`.claude/settings.json:613`) and do not read `constraints.json`, so mechanical enforcement is unchanged; but it is armed only by `LOA_TEAM_MEMBER`, and a teammate spawned without that variable and without the reference in its prompt now sees no rule at all. The dissenter rated this MEDIUM (DISS-C-005); downgraded since the hook layer is intact.
- **Fix:** Have the team spawn path inject the "Rules and arming" section (or fail when `LOA_TEAM_MEMBER` is unset); keep C-TEAM-005 in the kernel as a one-row floor.

### [LOW-004] Retrospective postlude passes no fallback

- **File:** `head/.claude/data/skill-includes/retrospective_postlude.md:1`
- **Issue:** `profile-lib.sh knob invisible_retrospective.enabled` has no fallback argument (unlike `input_guardrails.md`); with `profiles.yaml` missing, `loa_knob` prints the empty fallback and the postlude never runs under `standard`.
- **Fix:** `knob invisible_retrospective.enabled true`, then re-render the skills.

### [LOW-005] Stale warning text

- **File:** `head/.claude/hooks/quality/karpathy-surgical-diff-check.sh:193`
- **Issue:** The warning still says "Session diff total" for a per-task total.
- **Fix:** "Task diff total … (task ${KEY})".

### [LOW-006] `_bdb_hd_exec_dest` misses common persistence targets

- **File:** `head/.claude/hooks/safety/block-destructive-bash.sh:303`
- **Issue:** `~/.config/systemd/user/*.service`, `~/.config/autostart/*.desktop`, cron spools outside `/etc`, `Makefile`/`GNUmakefile` are not treated as executable content, so a unit file with an `ExecStart=` payload written by `cat … >` is `nonexec` and its body dropped (covered only by the later-command gap).
- **Fix:** Extend `_bdb_hd_re_sys` with `\.config/(systemd|autostart)/`, `(^|/)G?NUmakefile$|(^|/)Makefile$`, `/var/spool/cron`.

### [LOW-007] The profile cache in `.run/` is trusted over the configuration without integrity

- **File:** `head/.claude/scripts/lib/profile-lib.sh:67` (cache path), `:232-245` (warm path reads knob values from the cache)
- **Issue:** `loa_knob`'s warm path returns a knob value straight from `.run/effective-config.json` whenever its `id` (paths plus mtime and size of the three inputs, all readable) matches. `.run/` is agent-writable through Bash and is not an implement-gate trust input, so a forged cache flips any profile key (`guardrails.*`, `karpathy_principles.*`, the session-start surfaces) without touching `.loa.config.yaml`. Floor keys are correctly excluded from `knobs` and always read live, which bounds this to non-floor knobs; an agent can also rewrite the config itself via Bash, so the capability is not new, only quieter.
- **Fix:** Include a content hash of the inputs in the id, or read security-relevant knobs (`guardrails.*`) live and cache only the display-oriented ones.
- **Reference:** CWE-349 Acceptance of Extraneous Untrusted Data With Trusted Data — https://cwe.mitre.org/data/definitions/349.html

### [LOW-008] Implementation report and changelog

- **File:** `pr/PR.md:1`
- **Issue:** The report is the title plus "68 file(s) in scope": no AC walkthrough mapping DEC-0140/0141/0143/0152/0161/0163/0166/0167/0168 to `file:line`, and the change touches no CHANGELOG although it adds a deny mode, flips two guardrail defaults and replaces the fence's heredoc scan. The skill's documentation audit lists "a CHANGELOG omitting security changes" as a blocker; recorded at LOW here because the task brief declares the PR files the whole input.
- **Fix:** Add the AC walkthrough and a CHANGELOG entry per security-relevant change before re-audit.

---

## Observations

None excluded. Every HIGH above is tallied; no finding is marked speculative with low confidence.

Review demotions: the review trailer carries `excluded: 0`; nothing to confirm (`excluded_confirmed: 0`).

---

## Cross-Model Security Observations

Dissent envelope `grimoires/loa/a2a/sprint-1/adversarial-audit.json`: `metadata.type: audit`, `metadata.model: gpt-5.5-pro`, `status: reviewed`, `degraded: false`, `verdict_quality.voices_succeeded: 2/2` (`codex-headless`, `claude-headless`), `rejected_count: 0`. Triage:

- DISS-001 (HIGH, backslash-newline continuation in an unquoted body hides a `$(`) — real; folded into HIGH-001 item 4.
- DISS-C-001 (HIGH, literal-basename executor match; keywords not stripped) — real; HIGH-001 items 1 and 3.
- DISS-C-002 (HIGH, marker self-issuable via Bash defeats `deny`) — real mechanism, documented accepted gap, no new capability over Bash-path writes; LOW-001.
- DISS-C-003 (MEDIUM, guardrails default-on → default-off and fail-open) — real; MED-001.
- DISS-C-004 (MEDIUM, `LOA_IMPLEMENT_GATE_OVERRIDE` in every mode) — real and new in this PR; MED-002.
- DISS-C-005 (MEDIUM, C-TEAM constraints deleted) — prose moved to the reference, hooks intact and unchanged; LOW-003.
- DISS-C-006 (LOW, deny reason steers toward `mode: ask`) — real; LOW-002.

## Rejected dissent payloads

- None: `metadata.rejected_summary` is empty and the sidecar `adversarial-rejected-audit.jsonl` holds no rows.

---

## Test Results (head tree overlaid on this checkout; bash 5.2, jq 1.6, yq 4.40, bats 1.13; exec-capable overlay under `/home/evaluser/rt`)

| Check | Result | Notes |
|-------|--------|-------|
| `tests/fixtures/fence-corpus/run-corpus.sh` | benign 89/89, dangerous 142/142, residual 0/5, p95 57 ms | the corpus holds no same-command non-literal execution rows (HIGH-001) |
| `run-checkpoint.sh derive --json` | exit 3, jq compile error on `$label` | HIGH-002 |
| `tests/unit/run-checkpoint-derive.bats` | 4/22 | HIGH-002 |
| `tests/unit/run-checkpoint-record-round.bats` | 7/8 | RCR-7 (legacy trailer-less file), HIGH-002 |
| `tests/unit/profile-lib.bats` | 17/17 | |
| `tests/unit/lint-invariants.bats` | 9/9 | |
| `tests/unit/implement-gate.bats` | 24/33 | IG-24..33 (mode matrix) pass; IG-1..8 need `tests/fixtures/pretooluse-payloads/`, absent from the PR snapshot (environment) |
| `tests/unit/profile-floor.bats` | 5/7 | PF-1 needs `guard-origins.bats` (not in snapshot); PF-5 depends on the checkout's unchanged gate script (environment, unverified) |
| `tests/unit/karpathy-surgical-diff-hook.bats` | not run | the snapshot's redacted `secret=` fixture line breaks bats parsing (environment; the review restored it locally and reports 6/6) |
| Karpathy hook latency, 5 runs | base 28 ms, head 155 ms | MED-004 |
| `profile-lib.sh knob guardrails.danger_level.enforce false` with an unparseable config / no yq | `false` (base: `true`) | MED-001 |

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added (the one secret-scan redaction in the dissent input is the eval fixture line)
- [ ] Input validation on all new surfaces — the classifier's same-command execution model and keyword handling are incomplete (HIGH-001)
- [x] Authorization: implement-gate sanctions are tighten-only on model-authored claims; path canonicalisation and trust-input asks hold (IG-24..33 pass); marker and env override are documented gaps (LOW-001, MED-002)
- [x] Injection: jq programs take values via `--arg`/`--argjson`; key paths are regex-checked before reaching yq (`profile-lib.sh:222`); audit rows are `jq -a` escaped and 256-byte cut
- [ ] Error handling fails safely — guardrail knobs now fail open on resolution error (MED-001); `derive` fails loudly but its callers swallow the exit (HIGH-002)
- [x] Error messages don't leak sensitive data
- [ ] Tests cover security paths — the fence corpus lacks the bypass shapes; the derive suite does not run on jq 1.6

---

## Rubric Scores

| Dimension | Score | Basis |
|-----------|-------|-------|
| SEC-IV Input validation | 3 | classifier grammar is careful but its executor detection is incomplete (HIGH-001) |
| SEC-AZ Authorization | 4 | tighten-only gate, trust-input asks; env override and marker gaps |
| SEC-CI Confidentiality/Integrity | 4 | control-stripped, escaped audit rows; profile cache lacks integrity (LOW-007) |
| SEC-IN Injection prevention | 5 | parameterised jq/yq throughout |
| SEC-AV Availability/Resilience | 2 | the run position is inert on jq 1.6 (HIGH-002); hook latency (MED-004) |
| ARCH-MO Modularity | 3 | 300-line jq programs embedded in strings; classifier shares one file with the fence by design |
| CQ Code quality | 4 | Bash 3.2 care, atomic writes, fail-closed parsing; stale wording, missing fallback |
| DevOps | 3 | no jq floor declared or checked; CI does not run the new suites on 1.6 |

---

## Next Steps

**CHANGES_REQUIRED:**
1. Fix HIGH-001 (executor detection, keyword stripping, continuation folding, safe-reader list) and add the corpus rows; fix HIGH-002 (jq 1.6 dialect or a declared, checked floor) and run both suites on jq 1.6.
2. Address MED-001 (warn on profile-resolved guardrail defaults; migration note), MED-002 (scope the env override), MED-003..005 as time allows.
3. Add the AC walkthrough and CHANGELOG (LOW-008), then `/implement sprint-1` fixes and re-run `/review-sprint sprint-1` and `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":5,"low":8},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-23T03:48:34Z"} -->
