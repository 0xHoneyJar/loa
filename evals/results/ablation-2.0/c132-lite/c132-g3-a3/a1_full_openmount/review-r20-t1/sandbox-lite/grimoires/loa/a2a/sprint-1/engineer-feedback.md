# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-23
**Sprint Reference:** grimoires/loa/sprint.md (Task 1.1: the change in `pr/head.diff`, cycle-129 sprint-256, 68 files)
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (carries only the PR title and file count)

---

## Overall Assessment

The PR delivers five pieces. It adds implement-gate modes (`ask | telemetry | deny`) and a file-derived run position (`run-checkpoint.sh derive / record-round / mark / unmark`). It adds a heredoc consumer classifier to the destructive-command fence and a `loa.profile` resolver (`profile-lib.sh`) that every knob reader now uses. It also moves the Agent Teams table out of the kernel.

Much of it is solid. The new implement-gate matrix (IG-24 to IG-33) passes on this host. The deny reply follows the PreToolUse contract, and trust-input writes ask in every mode. The profile resolver handles an explicit `false`, floor keys and a missing profiles file correctly. The fence corpus passes every benign row and every dangerous row.

Three defects block the merge:

1. **The fence classifier is not fail-closed.** Some commands that the base hook blocks are now allowed. The primary dissent voice found the same class on its own (DISS-001).
2. **`run-checkpoint.sh derive` fails on jq 1.6.** It uses `$label` as a jq variable name, which is reserved in jq 1.6, so it never writes `derived_at`. With that missing, the whole FR-5 feature is inert on any host with jq 1.6.
3. **`record-round` crashes on legacy feedback with no trailer** under jq 1.6.

On top of that, the implementation report has no `## AC Verification` section, which triggers CHANGES_REQUIRED automatically under this skill.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Security: the heredoc classifier lets a body through when the same command later executes it

- **HIGH** (confidence: high) `head/.claude/hooks/safety/block-destructive-bash.sh:608-640` — `_bdb_hd_same_line_exec` decides whether a heredoc's target file is executed later in the same command. It only looks at the command word of the segment that names the file (line 631). It does not look at where that segment's output goes. A safe reader whose output reaches an interpreter on another line of the same command therefore leaves the heredoc `nonexec`. `_bdb_hd_scan_body` (`:576-604`) then drops the body lines. The fence (`:1062-1063`) never sees the destructive text, and the call is allowed.

**File:** `head/.claude/hooks/safety/block-destructive-bash.sh:608-640`
**Issue:** I replayed seven crafted commands of this class through both hooks in a scratch directory. The base hook blocked all seven. The head hook allowed five, and the two it still blocks are the shapes the corpus already covers. The header comment and `head/.claude/loa/reference/hooks-reference.md:294` both promise that naming the target elsewhere "outside a safe reader" forces a full scan. That promise does not hold once the reader's output feeds an interpreter. This is a regression against the base fence, not a gap it already had.
**Why This Matters:** The fence is the only check on destructive Bash for autonomous agents (CWE-184, incomplete list of disallowed inputs). The PR presents this classifier as fail-closed.
**Required Fix:** If any other line of the command names the heredoc's target, judge that line's whole pipeline or statement, not just the segment's command word. That covers pipe targets, a command substitution or `eval`, and a glob that can match the target. Any interpreter or runner anywhere on such a line should force `interpreter` class. The simplest fail-closed version: if any line outside the heredoc holds an interpreter word, a substitution or an unquoted glob, fall back to a full scan. Add corpus `D` rows for each pipeline and substitution shape, and re-run `run-corpus.sh --knob-off --rows` against the base hook to confirm nothing goes from blocked to allowed.
**Reference:** OWASP ASVS V5 (input validation, deny by default); CWE-184.

### 2. Functionality: `derive` cannot compile its jq program on jq 1.6

- **HIGH** (confidence: high) `head/.claude/scripts/run-checkpoint.sh:378-380` — the per-sprint jq program binds `--arg label` and reads `$label`. In jq 1.6 `label` is a keyword, so the call fails to compile and `cmd_derive` exits 3 under `set -e`.

**File:** `head/.claude/scripts/run-checkpoint.sh:378-389`
**Issue:** The failure reproduces here (jq 1.6):

```
jq: error: syntax error, unexpected label, expecting IDENT or __loc__ ... line 2:
      def mine: type == "string" and length > 0 and (. == "sprint-\($gid)" or ($label != "" and . == $label));
```

Running the PR's own `tests/unit/run-checkpoint-derive.bats` on a head overlay tree fails 13 of 22 cases (RCD-1 to RCD-12 and RCD-14), all with this error. Every caller hides it. `write` and `mark` swallow derive failures (lines 174 and 541), `loa-status.sh` discards stderr, and `halt-resume.md` step 0a treats a non-zero exit as no drift. As a result, `derived_at` is never written, and `implement_gate.mode: deny` always falls back to ask with "cache not derived". The breaker is never recomputed and `/loa` never prints the Run line.
**Required Fix:** Rename the variable (for example `--arg lbl` and `$lbl` at lines 378, 380 and 389). Add a CI job, or a bats `setup` guard, that runs the suite under jq 1.6. Debian 12 and Ubuntu 22.04 still ship jq 1.6.

### 3. Functionality: `record-round` crashes on a feedback file without a trailer

- **HIGH** (confidence: high) `head/.claude/scripts/run-checkpoint.sh:224-226` — for a feedback file without an `LOA-VERDICT` trailer, `tl` is empty and `pj` becomes an empty string. On jq 1.6, `jq -e 'type == "object"' <<<""` exits 0, so the `|| pj='{}'` fallback never fires. `jq --argjson p ""` at line 232 then aborts with "invalid JSON text passed to --argjson", and `record-round` exits 2.

**File:** `head/.claude/scripts/run-checkpoint.sh:224-232`
**Issue:** This reproduces outside bats on a trailer-less review file. `tests/unit/run-checkpoint-record-round.bats` RCR-7 fails for this reason. The run-mode skill (`head/.claude/skills/run-mode/SKILL.md:110`) now sends every review and audit round through `record-round`. On jq 1.6, a legacy-format round therefore stops the run loop where it should count as findings. The same empty-input guard is used at line 223 for `vj`, and `rounds_of` and `derive` reach `fb_parse` too.
**Required Fix:** Test for non-empty input before the type check, for example `[[ -n "$pj" ]] && jq -e 'type == "object"' <<<"$pj" >/dev/null 2>&1 || pj='{}'`, and do the same for `vj`. Add a bats case that runs a trailer-less file under jq 1.6.

---

## Observations

### 1. Skill allowlists

- **MEDIUM** (confidence: high) `head/.claude/skills/reviewing-code/SKILL.md:6` — the regenerated includes at lines 69 and 297 tell the skill to run `.claude/scripts/lib/profile-lib.sh knob …`. The `allowed-tools` line has no `Bash(.claude/scripts/lib/profile-lib.sh knob *)` grant, and `deny_raw_shell: true` is set. The harness refuses the call, so the guardrail check and the retrospective postlude never run. The retrospective defaults to on under `standard`. `head/.claude/skills/auditing-security/SKILL.md:6` (includes at lines 67 and 285) has the same gap.
**Suggestion:** Add the grant to both frontmatters and their `capabilities.execute_commands`. Have `validate-skill-capabilities.sh` check that every command an include tells the skill to run is in its allowlist.

### 2. Implement gate (deny mode)

- **MEDIUM** (confidence: high) `head/.claude/hooks/compliance/implement-gate.sh:558-569` — `read_position` treats the position as known whenever `derived_at` is fresh, and it never looks at `timestamps.last_activity`. A RUNNING cache whose activity stamp is older than 24 hours gets no sanction from `check_implementation_active` (line 505). It is still denied, with the self-contradicting reason "derived position: RUNNING". This reproduces with `run_mode.stale_hours: 48` and `last_activity` 30 hours old. Matches DISS-C-001.
- **MEDIUM** (confidence: medium) `head/.claude/hooks/compliance/implement-gate.sh:545-552` — the marker sanction expires 7200 seconds after `started_at`, and nothing refreshes it (`run-checkpoint.sh write` does not touch the marker). An `/implement` or `/bug` session longer than two hours starts asking on every write, or being denied under `deny`. Matches DISS-C-002.
- **LOW** (confidence: medium) `head/.claude/hooks/compliance/implement-gate.sh:510` — the new `_ig_derived_ok` check also applies in the default `ask` mode. A RUNNING cache whose `derived_at` is older than 12 hours loses its sanction even when activity is fresh. The header (lines 9-10) says ask behaves "exactly as before". Matches DISS-C-006.
- **LOW** (confidence: medium) `head/.claude/hooks/compliance/implement-gate.sh:586-589` — the marker sanction can be created by the model itself through the Bash tool (`run-checkpoint.sh mark`), so `deny` depends on the model choosing not to mark. `hooks-reference.md` lists the trust in `.run/` files as an accepted gap. It should name this marker path explicitly. Matches DISS-C-003.

### 3. Guardrail defaults

- **MEDIUM** (confidence: high) `head/.claude/scripts/danger-level-enforcer.sh:138-143` — `is_enforcement_enabled` no longer reads `$CONFIG_FILE` (line 26). Its default also flips from on to off when the key is absent, so a project without `.loa.config.yaml` silently loses danger-level enforcement. DEC-0161 intends the flip. It is an upgrade-visible behaviour change and needs a migration note or CHANGELOG entry. Matches DISS-C-004.

### 4. Tests

- **MEDIUM** (confidence: medium) `head/tests/unit/karpathy-surgical-diff.bats:165` — `local REDACTED-TEST-SECRET"` does not parse, so bats reports `bats-gather-tests` failed and none of the 11 new KS cases run. The same line was already in base at `tests/unit/karpathy-surgical-diff-hook.bats:134`, so it may be an artifact of the frozen snapshot. Either way, the per-task layout rewrite of `karpathy-surgical-diff-check.sh` ships with no test that ran here.
- **LOW** (confidence: low) `head/tests/unit/profile-floor.bats:141` — PF-5 (the adversarial-review gate decides the same under `lean` and `standard`) fails on this host. I did not find the cause. It may be environmental, but it is the floor-invariance test for the profile feature.

### 5. Documentation and wording

- **LOW** (confidence: high) `head/.claude/hooks/quality/karpathy-surgical-diff-check.sh:193` — the warning still says "Session diff total", but the total is now per task.
- **LOW** (confidence: medium) `head/.claude/loa/reference/agent-teams-reference.md:32-45` — the C-TEAM rules leave the always-loaded kernel (DEC-0140). C-TEAM-002, 003 and 004 have no hook unless `LOA_TEAM_MEMBER` is exported, so a teammate that is never pointed at this page gets none of the single-writer rules. Matches DISS-C-007.

---

## Cross-Model Observations

The adversarial review ran with `--diff-file pr/head.diff`. It reported status `reviewed`, primary voice gpt-5.5-pro, companion voice claude-headless (`independent_voice`), eight findings and no rejected payloads. The primary voice's input was truncated to 14 of 68 files.

| Finding | Disposition |
|---------|-------------|
| DISS-001 (BLOCKING) fence classifier misses later execution | Confirmed by replay. Counted as Changes Required item 1 |
| DISS-C-001 `read_position` ignores `last_activity` | Confirmed. Observation 2, medium |
| DISS-C-002 marker expires after two hours | Observation 2, medium |
| DISS-C-003 model can self-sanction through the marker | Observation 2, low |
| DISS-C-004 danger-level default and config path | Observation 3, medium |
| DISS-C-005 `enabled` left unset when the profile lib fails | Not a defect: `enabled="false"` is preset at `head/.claude/hooks/loa-kf-surface.sh:53` and `head/.claude/hooks/session-start/loa-decisions-surface.sh:43` |
| DISS-C-006 `derived_at` check also applies in ask mode | Observation 2, low |
| DISS-C-007 C-TEAM rules leave the kernel | Observation 5, low |

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | `reviewer.md` has no `## AC Verification` walkthrough, which triggers CHANGES_REQUIRED automatically. The three high findings above. No CHANGELOG entry for the five features. |

---

## Acceptance Criteria Check

### Task 1.1

| Criterion | Status | Notes |
|-----------|--------|-------|
| Review the pull request, report each defect with file and line, give a merge verdict | Pass | This file |
| Implementation report carries AC verification | Fail | `reviewer.md` holds only the title |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [ ] Input validation and sanitization present (the fence classifier lets some executing commands through; item 1)
- [x] Authentication/authorization correct (the implement gate only tightens under the claims modifier)
- [x] No SQL/XSS injection vulnerabilities (key paths validated before yq in `profile-lib.sh`; jq `--arg` used throughout)
- [x] Dependencies secure
- [x] Error messages don't leak sensitive data (paths and claims control-stripped before stderr)

---

## Code Quality Summary

**Strengths:**
- The implement-gate matrix test covers mode × claims × write class × sanction × cache state, and it passes.
- `profile-lib.sh` reads explicit `false` correctly, keeps floor keys out of profiles, and validates key paths before yq.
- `atomic_update` does tmp + validate + mv under flock, and readers accept the old schema.

**Areas for Improvement:**
- Run the suites under jq 1.6 in CI; two of the three high findings only show up there.
- Classifier allowlists need adversarial corpus rows for each shape the safe-reader exemption permits.
- `run-checkpoint.sh` `cmd_derive` is about 150 lines. Splitting the per-sprint facts, the breaker recompute and the write step would make it reviewable. SIMPLICITY[shrink].

---

## Next Steps

1. Fix the three Changes Required items and add the regression tests named there.
2. Add the `## AC Verification` section and a CHANGELOG entry to `reviewer.md` and the PR description.
3. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*
<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":5,"low":5},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-23T03:30:00Z"} -->
