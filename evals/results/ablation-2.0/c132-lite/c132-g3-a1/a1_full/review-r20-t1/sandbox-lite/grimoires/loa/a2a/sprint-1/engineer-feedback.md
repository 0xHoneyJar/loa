# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)

---

## Overall Assessment

The change under review is sprint-256 (`pr/head.diff`, 68 files): the implement gate's three modes and marker sanction, the file-authoritative run position in `run-checkpoint.sh` (`derive`, `record-round`, `mark`), the heredoc consumer classifier in the Bash fence, the `loa.profile` resolver, the C-TEAM rows moved out of the kernel, and the per-task surgical-diff hook. The design is coherent and the test matrices are thorough. In a scratch head tree the fence corpus passes completely with the classifier on (89/89 benign, 142/142 dangerous), the implement-gate mode matrix passes (IG-24 to IG-33, 10/10), `profile-lib.bats` passes 17/17, `lint-invariants.bats` 9/9, `karpathy-trajectory-event.bats` 4/4, the managed-header hash of `CLAUDE.loa.md` verifies, `validate-constraints.sh` reports 0 errors, `check-knob-readers.sh` is clean, and the kernel fits the new 9,445 B cap (9,189 B).

Three defects block the merge. First, the classifier's `nonexec` class drops heredoc bodies for write targets it does not recognise as executable, and two command shapes the base hook blocked now pass (a cron drop-in reached through a `..` path segment, and a `package.json` scripts entry executed by a following `npm run`). Second, `run-checkpoint.sh derive` does not run at all on jq 1.6 (the version installed here, and in Debian 12 / Ubuntu 22.04) because the per-sprint jq program binds `$label`, which jq's lexer rejects as a keyword; 13 of 22 `run-checkpoint-derive.bats` cases fail and every `write` prints jq errors. Third, the breaker recompute counts trailer-less "All good" rounds as changes-required rounds with identical hashes, so three legacy approved files in the active sprint directory trip the breaker and flip a RUNNING run to HALTED on its first checkpoint (demonstrated with a patched copy whose trailer fallback works).

Verification limits: the eval workspace carries no `tests/` tree, so suites that need fixtures outside the PR (`pretooluse-payloads/`, `guard-origins.bats`, `constraint-rationales-pre-diet.json`, the skill-capabilities and prompt-budget helpers) and the two karpathy suites (whose secret literal the snapshot redacted into a bash syntax error) could not be run to completion; the validator and the prompt-budget tool were exercised by hand and behaved as their new tests expect. `reviewer.md` is the bare PR title and carries no `## AC Verification` section; the sprint's single criterion is this review itself, so that is noted rather than counted.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Safety fence: `nonexec` heredoc bodies are dropped for targets the classifier does not recognise as executable (regression against the base hook)

- **HIGH** (confidence: high) `head/.claude/hooks/safety/block-destructive-bash.sh:303-325` — `_bdb_hd_exec_dest` judges the write target by literal prefix and extension only; a target that a following command in the same Bash call executes, but that is not a script extension, rc file, `.claude/hooks`, `.git/hooks`, a literal `/etc/` prefix or a PATH directory, is classed non-executing, its body is reduced to fence-verb segments (`:576-604`), and destructive content inside it is never scanned.
**File:** `head/.claude/hooks/safety/block-destructive-bash.sh:303-325` (the lists at `:189-190`, the unnormalised `/etc` prefix test at `:312`, the segment drop at `:593`)
**Issue:** Replayed through both hooks in scratch trees (head and base), two shapes flip from block (exit 2) to allow (exit 0):
  - a `tee` into a cron drop-in whose path reaches `/etc/cron.d` through a `/tmp/../` segment; the prefix test at `:312` does not normalise the path, and the body line begins with the schedule field, not a verb, so the recursive delete it carries is dropped (the primary dissent voice's DISS-001, confirmed here);
  - a `cat` redirect into `package.json` whose `scripts` entry carries a recursive delete, followed on the next line by `npm run` of that script; `package.json` is not in `_bdb_hd_re_ext` or `_bdb_hd_re_sys`, the JSON line's command word reduces to an empty string in `_bdb_hd_segword`, and the body is dropped although the same command runs it.
  The same gap covers `Makefile` + `make`, `.mcp.json`, `Dockerfile`, `Justfile`, and any build or task manifest; the header comment's "Documented gap" at `:175-176` claims only a *later* command is out of reach, but these executors are in the same command.
**Why This Matters:** The classifier replaces a full scan that caught these; the PR documents the hook as the fence against routine destructive mistakes, and the "fail-closed" claim in the title and `hooks-reference.md:294` does not hold for these shapes.
**Required Fix:** Normalise the destination (collapse `.`/`..`, expand `~`, resolve against the payload cwd) before the prefix, rc and PATH tests, and treat an un-normalisable path as executable content; add the build/task manifests (`Makefile`, `GNUmakefile`, `*.mk`, `Justfile`, `Rakefile`, `package.json`, `.mcp.json`, `Dockerfile`, `Procfile`, `*.service`, `crontab`) to `_bdb_hd_re_sys`, or, more robustly, fall back to the full scan whenever a later segment of the same command runs an interpreter or build tool (`make`, `npm`, `yarn`, `pnpm`, `just`, `docker`, `systemctl`, `crontab`). Add the two replayed shapes to `tests/fixtures/fence-corpus/corpus.jsonl` as `block` rows.
**Reference:** CWE-184 (incomplete list of disallowed inputs), CWE-22 (path traversal in the destination test).

### 2. `run-checkpoint.sh derive` fails to compile its per-sprint jq program on jq 1.6

- **HIGH** (confidence: high) `head/.claude/scripts/run-checkpoint.sh:378-389` — the `sj=$(jq -nc … --arg label "$label" …)` program references `$label`; `label` is a jq keyword and jq 1.6 rejects `$label` with `syntax error, unexpected label, expecting IDENT or __loc__`, so `cmd_derive` never produces a sprint row.
**File:** `head/.claude/scripts/run-checkpoint.sh:378-389`
**Issue:** On this machine (jq-1.6) `derive --json` exits non-zero with two compile errors, `write` (which now runs `derive --write` at `:174`) prints the jq errors on every checkpoint, `mark` does the same (`:541`), and the `/loa` Run line (`loa-status.sh:1016-1021`) never appears. In the scratch head tree 13 of the 22 `run-checkpoint-derive.bats` cases fail (RCD-1 to RCD-12, RCD-14). Nothing in the repository pins jq ≥ 1.7; the rest of the framework, including the adversarial review that ran for this feedback, works on 1.6.
**Why This Matters:** The file-authoritative run position is the sprint's central feature; on a common jq it is dead on arrival and the gate's `derived_at`-based position is never written, so `implement_gate.mode: deny` degrades to ask everywhere.
**Required Fix:** Rename the binding (`--arg lbl` / `$lbl`, mirroring `--arg status`), grep the new jq programs for other keyword-named bindings, and either pin jq ≥ 1.7 in the preflight or run the derive suite under 1.6 in CI.

### 3. Legacy approved rounds trip the derived breaker and HALT a running run

- **HIGH** (confidence: high) `head/.claude/scripts/run-checkpoint.sh:276-284` — `recompute` counts every round whose `approved` is false, and `fb_parse` marks any trailer-less file unapproved (`:233-238`) with a hash taken from its findings section (`:230`); an "All good" file without a trailer has no findings section, so every such file hashes to the md5 of the empty string, three of them give `same_issue` 3, `merge_breaker` opens the breaker (`:300-311`), and `resolve` derives HALTED.
**File:** `head/.claude/scripts/run-checkpoint.sh:276-284` (hash at `:230`, automatic `derive --write` from `write` at `:174` and from `mark` at `:541`)
**Issue:** Reproduced with a copy of the script whose `$label` and empty-trailer fallbacks were patched so the code path runs: a fixture repo with one in-progress sprint, three legacy `engineer-feedback-rN.md` files reading "All good", a current approved file with a trailer, and a fresh RUNNING cache; `derive --write` reports `breaker.recomputed {cycle_count: 3, same_issue: 3}`, writes `state: OPEN`, `trigger: same_issue`, and rewrites the cache to HALTED. Because `write` now runs `derive --write` on every checkpoint, a repository whose active cycle holds any pre-trailer sprint (which can never derive `complete`, so it stays the active sprint) halts at its first checkpoint for history that is not a failure.
**Why This Matters:** A false HALTED needs an operator and `/run-resume --reset-ice`; the control plane reports a loop that did not happen, and the same logic inflates `cycle_count` with approved rounds.
**Required Fix:** In `recompute`, exclude rounds with `trailer: false` (they already surface under `legacy_feedback`), or at least exclude a legacy file whose findings-section hash is the empty-input md5 and whose first line is the approval phrase; never let two legacy files with no findings section compare equal. Add an RCD case with three trailer-less "All good" rounds asserting the breaker stays CLOSED.

---

## Observations

### 1. `--file` outside a `.run/` directory writes the repository's own breaker

- **MEDIUM** (confidence: high) `head/.claude/scripts/run-checkpoint.sh:108-117` — when `--file` does not sit in a directory named `.run`, `root` falls back to the script's checkout and `breaker` to that checkout's `.run/circuit-breaker.json`, so `write --file /tmp/x/state.json …` (reproduced) creates and updates the real repository's breaker from the real ledger while the caller believes it is working on a scratch file.
**File:** `head/.claude/scripts/run-checkpoint.sh:108-117`, the derive call at `:174`
**Suggestion:** Derive `run_dir` from the directory of `--file` whatever its name, or refuse `derive --write` when `--file` and `run_dir` disagree.
**Benefit:** No cross-contamination of live run state from tests or ad-hoc calls.

### 2. The trailer and verdict-derive fallbacks rely on `jq -e` failing on empty input

- **MEDIUM** (confidence: high) `head/.claude/scripts/run-checkpoint.sh:226` (and `:223`) — `jq -e 'type == "object"' <<<"$pj" || pj='{}'` never fires when `$pj` is empty, because `jq -e` exits 0 with no input (verified on jq 1.6); a trailer-less file then reaches `--argjson p ""`, `fb_parse` emits nothing, the round silently vanishes from `rounds_of`, and `record-round` on a legacy file exits 3 (`RCR-7` fails here). The `vj` guard at `:223` has the same hole if `verdict-derive.sh` prints nothing.
**Suggestion:** Test `[[ -n "$pj" ]]` before the `jq -e` check (same for `$vj`).
**Benefit:** Deterministic behaviour across jq versions; legacy rounds are either counted or excluded by design, never dropped by accident.

### 3. The fence-verb list and the same-line executor check are narrower than the contract states

- **MEDIUM** (confidence: medium) `head/.claude/hooks/safety/block-destructive-bash.sh:214-220` — `_bdb_hd_is_destructive` is a hand-maintained list described as "command words the fence's own rules match", yet the rule set also keys on `sed -i`, `cp`, `mv`, redirections into `.claude/`, `docker`, `npm`, `make` and others; a `nonexec` body carrying those words is dropped before the normal rules run. `_bdb_hd_same_line_exec` (`:608-640`) also treats `cat` as a safe reader inside process substitution, so a target fed to `source <(cat target)` on a later line is not recognised as executed (companion dissent DISS-C-004 and DISS-C-005).
**Suggestion:** Derive the verb list from the rule table (or assert equality in `run-corpus.sh`), and in `_bdb_hd_same_line_exec` return interpreter-class when a line naming the target also holds `$(`, a backtick, `<(` or `>(`, mirroring `_bdb_hd_ctx_bad`.
**Benefit:** The classifier's fail-closed contract holds as rules evolve.

### 4. "Turning the classifier off only tightens" is not what the corpus shows

- **LOW** (confidence: high) `head/.loa.config.yaml.example:1243` and `head/.claude/hooks/safety/block-destructive-bash.sh:732` — with `--knob-off`, `run-corpus.sh` reports 4 dangerous rows allowed that the classifier blocks (D127, D131, D136, D141) and 5 benign rows blocked; the rollback key is looser in one direction and tighter in the other.
**Suggestion:** Reword to "restores the pre-cycle scan" and list the four FR-6 rows the pre-cycle scan misses.
**Benefit:** An operator rolling back knows what coverage they lose.

### 5. The profile cache in `.run/` is consulted before the configuration

- **LOW** (confidence: medium) `head/.claude/scripts/lib/profile-lib.sh:67` and `:219-243` — `loa_knob` serves `.run/effective-config.json` whenever its id matches the config's stat line; a Bash-written cache with the right id flips any profile key (both guardrail knobs included) without touching `.loa.config.yaml`. Same trust class as the other `.run/` inputs the PR documents (bd-taee), but not named anywhere.
**Suggestion:** Document the cache under the accepted `.run/` gaps, or key the id on a content hash of the config rather than its mtime and size.
**Benefit:** The trust boundary of the profile layer is stated where the others are.

### 6. The surgical-diff hook forks `run-checkpoint.sh read` (and `br show`) on every Write/Edit

- **LOW** (confidence: medium) `head/.claude/hooks/quality/karpathy-surgical-diff-check.sh:131` — each counted write spawns bash + the checkpoint reader, which itself runs `br show` when a task checkpoint exists; the design note says the perf caches were removed because per-task files are small, but this new per-write fork is the larger cost.
**Suggestion:** Cache the resolved key in the summary file keyed on the checkpoint file's mtime, or read `.checkpoint.task` with one jq and skip the beads confirmation in the hook (the review's SURGICAL axis is advisory).
**Benefit:** Keeps the PostToolUse path within the hook latency budget.

### 7. `_ig_within` rejects ISO timestamps with a UTC offset

- **LOW** (confidence: medium) `head/.claude/hooks/compliance/implement-gate.sh:475-481` — `fromdateiso8601` parses only a trailing `Z`; a `derived_at` or `started_at` written as `+00:00` is treated as stale, so a sanction silently disappears (companion dissent DISS-C-002). Every writer in this PR uses `Z`, so no live path fails today.
**Suggestion:** Normalise `+00:00` / `-00:00` to `Z` before parsing.
**Benefit:** Robust against other writers of the same state files.

### 8. Two safety defaults flip to off with no migration notice

- **LOW** (confidence: high) `head/.claude/data/profiles.yaml:36-38` and `head/.claude/scripts/danger-level-enforcer.sh:139-143` — `guardrails.input.enabled` and `guardrails.danger_level.enforce` now resolve to false for every repository that never set them (DEC-0161 is cited; the change is intentional), and nothing at session start or on the `/loa` Profile line tells an upgrading operator that enforcement they had is now off (companion dissent DISS-C-003).
**Suggestion:** Print a one-time note on the Profile line when `loa.profile` is unset and neither key is explicit.
**Benefit:** The default flip is visible where the operator looks.

---

## Cross-Model Observations

Two voices answered (`gpt-5.5-pro` via codex-headless, companion `claude-headless`; consensus, 2/2 succeeded). DISS-001 (BLOCKING) is incorporated as Changes Required 1 after confirming it against both hooks. DISS-C-004 and DISS-C-005 are Observation 3, DISS-C-002 is Observation 7, DISS-C-003 is Observation 8. DISS-C-001 (a Bash-written marker self-sanctions under `deny`) is already recorded as an accepted gap at `head/.claude/loa/reference/hooks-reference.md:273` and is not counted. DISS-C-006 (the C-TEAM rows vanish) is not a defect: the five rules and their rationales now live at `head/.claude/loa/reference/agent-teams-reference.md:32-45`, the team hooks stay registered as dormant, and `instruction-diet-revert.bats` was updated to read them there.

## Rejected dissent payloads

- none — `rejected_summary` is empty and `adversarial-rejected-review.jsonl` holds no rows.

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict | Pass | This file; defects cited as `head/<path>:<line>`; verdict below |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [ ] Input validation and sanitization present — the destination test in the heredoc classifier does not normalise paths (Changes Required 1)
- [x] Authentication/authorization correct — the marker sanction's trust model is documented as accepted
- [x] No SQL/XSS injection vulnerabilities — key paths are regex-checked before reaching yq; jq values are passed with `--arg`
- [x] Dependencies secure (no known CVEs)
- [x] Error messages don't leak sensitive data — paths are control-stripped and cut to 256 bytes

---

## Code Quality Summary

**Strengths:**
- The implement-gate matrix (modes × claims × write class × sanction × cache state) is complete and passes; the `--effective-mode` parser is shared with `/loa`.
- The profile resolver honours explicit `false`, refuses floor keys with a WARN, and never caches a seam config over the repository cache.
- The fence corpus covers 53 new FR-6 rows and the knob-off replay exists for A/B comparison.
- The C-TEAM removal is mechanised end to end (optional table prune, invariant 4b, keeplist, budget cap).

**Areas for Improvement:**
- `run-checkpoint.sh` grew from a 100-line checkpoint writer to a 550-line state engine with `set -e` and large inline jq programs; the jq programs want their own files (`jq -f`) and a jq-1.6 run in CI.
- The classifier's executable-destination judgement is a denylist; the safer shape is "full scan unless the target is a known data sink and nothing in the command runs it".

---

## Next Steps

1. Address Changes Required 1 to 3 (fence destination handling, the `$label` binding, legacy rounds in `recompute`).
2. Run `tests/unit/run-checkpoint-derive.bats` and `run-checkpoint-record-round.bats` under jq 1.6 and 1.7; re-run `tests/fixtures/fence-corpus/run-corpus.sh` with the two new block rows.
3. Update the report in `grimoires/loa/a2a/sprint-1/reviewer.md`
4. Request another review via `/review-sprint sprint-1`

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":3,"low":5},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T19:20:00Z"} -->
