# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (pr/PR.md)

---

## Overall Assessment

The change under review is cycle-129 sprint-256: 68 files, a 7,124-line diff. It rewrites the surgical-diff hook to per-task files, adds `implement_gate.mode` (ask | telemetry | deny) with a marker sanction, adds `run-checkpoint.sh derive | record-round | mark | unmark` (file-authoritative run position and a derived circuit breaker), adds a 650-line heredoc consumer classifier to the Bash fence, introduces `loa.profile` with `profile-lib.sh`, removes the C-TEAM rows from the kernel, and changes the guardrail defaults.

The work is thorough and well tested where it runs. I rebuilt the head tree with the PR's test files and ran the suites: profile-lib 17/17, implement-gate matrix IG-24..33 10/10, lint-invariants 9/9, karpathy per-task hook 10/11 (the one failure is an exec-bit artifact of this host), fence corpus benign 89/89 and dangerous 142/142 with p95 59 ms, and the knob-reader lint and prompt budget both clean.

Three defects block the merge:

1. `run-checkpoint.sh derive` does not run on jq 1.6, which `dec-write-lib.sh` names as the floor ("install jq 1.6+"): the jq program binds `--arg label`, and `label` is a jq keyword, so every `derive`, `write` and `mark` prints a compile error and the caches never gain `derived_at`. On this host 18 of 22 derive tests fail for this reason alone; the `deny` gate mode is inert because the run position is never "known".
2. `fb_parse` relies on `jq -e` returning non-zero for empty input; jq 1.6 returns 0, so the empty-string guard never fires and `--argjson ''` aborts the function. `record-round` exits 2 on any trailer-less (legacy) feedback file and `derive` aborts for any sprint carrying one. With both spots patched locally the derive and record-round suites pass 29/30 (the remaining one needs an executable workflow-state script this host cannot provide).
3. The heredoc classifier's executable-destination check compares paths textually, so `tee .git/objects/../hooks/pre-commit <<'EOF'` (or `.git//hooks/pre-commit`) is a plain-file write, and the per-segment body scan drops `if …; then <destructive>; fi` because the segments start with keywords. The base fence blocked this command; the head fence allows it. The cross-model dissenter raised the same case as its one BLOCKING finding (DISS-001), and I reproduced it.

Beyond those, the derived breaker can halt a healthy run (approvals never break a streak, and a pre-cycle-129 breaker reset has no `reset_at`), the two-hour implement marker is never refreshed so `deny` mode cuts off a long `/implement`, the surgical-diff hook now costs roughly ten times the base per Write/Edit, and two more fence regressions versus base (`bash -c "$(cat f)"` on the same command; `~/.bash_aliases` and `~/.ssh/config` as destinations) sit under Observations.

Process note: `reviewer.md` is the PR description only and carries no `## AC Verification` section; that alone would force CHANGES_REQUIRED under the skill's automatic rule.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Portability: `derive` cannot compile on jq 1.6

- **HIGH** (confidence: high) `head/.claude/scripts/run-checkpoint.sh:378` — the per-sprint jq program is invoked with `--arg label "$label"` and reads `$label`; `label` is a jq keyword (`label $out | …`), and jq 1.6 rejects `$label` with `syntax error, unexpected label, expecting IDENT or __loc__`. jq 1.7 accepts keywords as variable names, which is why the suite is green on the author's machine and red on Debian 12 / Ubuntu 22.04 hosts.
**File:** `head/.claude/scripts/run-checkpoint.sh:378` (the `def mine:` and `local_label: $label` lines at 380 and 389 are the two uses)
**Issue:** `cmd_derive` fails on its first sprint row, so `derive`, `derive --write`, and the derive step that `write` and `mark` now run on every checkpoint all fail. `cmd_write` swallows the exit and prints the jq error to stderr at each checkpoint; the cache never gains `derived_at`.
**Why This Matters:** The PR's centrepiece ("file-authoritative run position") is dead on the declared jq floor (`.claude/scripts/lib/dec-write-lib.sh:208` says "install jq 1.6+"). Downstream: `implement_gate.mode: deny` never denies because `read_position` requires a fresh `derived_at` (always "cache not derived", so it asks); the `/loa` Run drift line never appears; `tests/unit/run-checkpoint-derive.bats` fails 18 of 22 cases on this host (reproduced; with only this and the next fix applied locally the suite passes 21 of 22).
**Required Fix:** Rename the binding (for example `--arg lbl "$label"` and `$lbl` in the program), and grep the other new jq programs for keyword-named variables. Add jq 1.6 to the CI matrix or raise the documented floor to 1.7 in `dec-write-lib.sh` and the install docs; do not leave the two disagreeing.
**Reference:** jq 1.6 manual, "label $name | …"; CWE-1127 (compilation with incompatible toolchain assumptions).

### 2. Portability: the empty-input guards in `fb_parse` never fire on jq 1.6

- **HIGH** (confidence: high) `head/.claude/scripts/run-checkpoint.sh:223` — `jq -e 'type == "object"' >/dev/null 2>&1 <<<"$vj" || vj='{…}'` assumes `jq -e` exits non-zero when it produces no output; jq 1.6 exits 0 on empty input (jq 1.7 exits 4), so an empty `$vj` or `$pj` passes straight into `--argjson`, which aborts with `invalid JSON text passed to --argjson`. Under `set -e` the whole script dies.
**File:** `head/.claude/scripts/run-checkpoint.sh:223` and `:226`
**Issue:** `$pj` is empty for every feedback file without a `LOA-VERDICT` trailer (the legacy class the PR explicitly supports via `derivation.legacy_feedback` and the no-trailer hash). Reproduced: `record-round --gate review --file <trailer-less file>` exits 2 with the jq error and records nothing; `derive` aborts for any sprint whose `engineer-feedback.md` or `auditor-sprint-feedback.md` lacks a trailer. `tests/unit/run-checkpoint-record-round.bats` RCR-7 fails on this host for this reason.
**Why This Matters:** In the run loop the SKILL now says "exit 10 has already written OPEN and HALTED"; an exit 2 is neither, so the breaker silently stops counting the moment a legacy feedback file is in play, which is the exact situation the no-trailer fallback hash was written for. On hosts with jq 1.6 the circuit breaker is unreliable.
**Required Fix:** Guard on the string before calling jq, for example `{ [[ -n "$vj" ]] && jq -e … <<<"$vj"; } || vj=…` (same for `$pj`), and audit the other `jq -e … <<<"$x" || default` idioms added in this PR (`cmd_derive` line 333 is safe because it reads a file). Add a legacy-feedback case to the derive suite that runs under jq 1.6.
**Reference:** jq issue "jq -e exits 0 on empty input" (fixed in 1.7); CWE-754 (improper check for unusual conditions).

### 3. Fence: executable-destination check does not normalise paths, and keyword-prefixed body lines are dropped

- **HIGH** (confidence: high) `head/.claude/hooks/safety/block-destructive-bash.sh:303` — `_bdb_hd_exec_dest` tests the literal path against `_bdb_hd_re_sys` (line 190), so `.git/objects/../hooks/pre-commit` and `.git//hooks/pre-commit` do not match `\.git/hooks(/|$)` and are classified as plain files; `_bdb_hd_scan_body` (line 576) then drops `if true; then <verb>; fi` because each segment's command word is `if`, `then` or `fi`, and the body is never scanned. Reproduced against head and base: `tee .git/objects/../hooks/pre-commit <<'EOF' / if true; then git push --force origin main; fi / EOF` → head exit 0, base exit 2; the same with `.git//hooks/pre-commit` → head 0, base 2; `./.git/hooks/pre-commit` and `.git/hooks/pre-commit` → both 2 (so the regex is the gap, not the design).
**File:** `head/.claude/hooks/safety/block-destructive-bash.sh:303` (function), `:190` (`_bdb_hd_re_sys`), `:576`–`:600` (segment scan)
**Issue:** The classifier's documented guarantee ("a write target is executable content … `.git/hooks`, `.claude/hooks`, `.claude/settings*.json`, rc/profile files, `/etc`, a bin dir or a directory on PATH") can be defeated by `..` or a doubled slash in the path, and the body that then reaches the hook is one `git commit` away from executing. The same two weaknesses also reach `.claude/hooks/` through `.claude/./hooks/x.sh` style paths (the `.sh` extension catches that one, but a shebang-less, extension-less hook would not be caught).
**Why This Matters:** This is the one BLOCKING finding of the cross-model dissent (DISS-001) and it is a regression versus the base fence for the exact class ("executable content") the PR says it fails closed on. The fence is a mistake-catcher, not a security boundary, so the realistic risk is an agent copying a hook path from a transcript with a `..` in it; still, "fail-closed heredoc classifier" is in the PR title.
**Required Fix:** Canonicalise the destination before the regex (collapse `//`, resolve `.` and `..` segments lexically, strip a leading `./`), and treat any path still containing `..` as "cannot be judged" (return 0). In `_bdb_hd_scan_body`, when a segment's command word is a shell keyword (`if then else elif fi for while until do done case esac function time ! {`), re-run `_bdb_hd_segword` on the remainder instead of dropping the segment, so `then rm -rf src` is kept as `rm -rf src`. Add D-rows for `.git/objects/../hooks/x`, `.git//hooks/x` and an `if … then <verb>; fi` body to the corpus.
**Reference:** CWE-22 (path traversal) applied to an allow/deny decision; CWE-180 (incorrect behaviour order: validate before canonicalise).

---

## Observations

### 1. Fence: same-command execution through `bash -c "$(cat <target>)"` is not recognised

- **MEDIUM** (confidence: high) `head/.claude/hooks/safety/block-destructive-bash.sh:625` — `_bdb_hd_same_line_exec` strips quotes and the directory from each token and compares for equality with the target's basename; the token `"$(cat notes.md)"` becomes `notes.md)` and never matches, so `cat > notes.md <<'EOF' … EOF` followed by `bash -c "$(cat notes.md)"` is classified `nonexec`. Reproduced: with the body `if true; then git push --force origin main; fi` (or `x() { …; }; x`) head exits 0, base exits 2. `bash notes.md`, `sh < notes.md`, `. ./notes.md`, `bash "$PWD/notes.md"` and `eval "$(cat notes.md)"` are all caught (the last only because the body line starts with the verb).
**File:** `head/.claude/hooks/safety/block-destructive-bash.sh:625`
**Suggestion:** Match the basename as a token substring (`[[ "$u" == *"$b"* ]]`) rather than equality, and treat a later line that holds `$(`, a backtick or `<(` and names the target as interpreter-class, mirroring `_bdb_hd_ctx_bad` for earlier lines.
**Benefit:** Closes the only same-command executor shape I found that the scan misses, and keeps the "a target named elsewhere on the command" claim true.

### 2. Fence: rc-file list omits `.bash_aliases` and `.ssh/config`

- **MEDIUM** (confidence: high) `head/.claude/hooks/safety/block-destructive-bash.sh:191` — `_bdb_hd_re_rc` lists `.bashrc`, `.profile`, `.zshrc`, `.envrc` and friends but not `.bash_aliases` (sourced by the default Debian/Ubuntu `.bashrc`) nor `.ssh/config` (`ProxyCommand` / `LocalCommand` run a shell on the next ssh or `git push`). `cat >> ~/.bash_aliases <<'EOF' / alias gp='git push --force origin main' / EOF` and `cat >> ~/.ssh/config <<'EOF' / Host x / ProxyCommand git push --force origin main / EOF` are both `nonexec` on head (exit 0) and were blocked by base (exit 2).
**File:** `head/.claude/hooks/safety/block-destructive-bash.sh:191`
**Suggestion:** Add `bash_aliases`, `zsh_aliases`, `ssh/config`, `tmux.conf`, `vimrc|exrc|nvim/init.*` to the executable-destination patterns, and consider `Makefile|GNUmakefile|Justfile|Rakefile` (recipes run on the next `make`), which both base and head allow today.
**Benefit:** Keeps the "rc/profile files" promise and removes two regressions versus the base fence.

### 3. Derived breaker: approvals never break a streak and HALTED outranks COMPLETE

- **MEDIUM** (confidence: high) `head/.claude/scripts/run-checkpoint.sh:280` — `recompute` does `map(select(.approved | not))` before computing consecutive same-hash and no-progress runs, so an APPROVED round between or after changes-required rounds does not reset the streak; `resolve` (line 324) ranks `breaker_open` above `all_complete` (line 325); and a breaker reset without `reset_at` (every reset made before this PR, or any hand reset) does not filter the history. Reproduced with the suite's own helpers: (a) a cycle whose three sprints are all complete, where the last sprint has three identical CR rounds followed by APPROVED and a COMPLETED marker, derives `HALTED` and `--write` flips the breaker to OPEN with `history: [same_issue]`; (b) an in-flight run whose active sprint has three identical past CR rounds and a zeroed breaker (no `reset_at`) goes `RUNNING → HALTED` on the very next `run-checkpoint.sh write` checkpoint.
**File:** `head/.claude/scripts/run-checkpoint.sh:280`, `:324`
**Suggestion:** Compute streaks over the full ordered round list and reset `same`/`np` on an approved round; when the cached breaker is CLOSED with zero counters and no `reset_at`, treat the newest round's `ts` as the implicit reset point (or write `reset_at` during the upgrade); and rank `all_complete` above a derived (not cached) OPEN so a finished cycle never reports HALTED.
**Benefit:** Prevents spurious halts on upgrade and on completed cycles; the breaker then only trips on live repetition, which is what record-round already guarantees.

### 4. Implement gate: the two-hour marker is never refreshed

- **MEDIUM** (confidence: high) `head/.claude/hooks/compliance/implement-gate.sh:550` — `check_implement_marker` sanctions only while `started_at` is under 7,200 s, and nothing in `implementing-tasks/SKILL.md:229` or `bug-triaging/SKILL.md:435` refreshes it (`mark` at the start, `unmark` at the end). Under `deny`, `mark` itself runs `derive --write`, which stamps `derived_at` on the cache, so the position is "known"; a direct `/implement` (no RUNNING cache) that outlives two hours is then denied on every App-Zone write for the rest of the sprint. Under `ask` it starts prompting on every write. The cross-model dissent raised this as DISS-C-002.
**File:** `head/.claude/hooks/compliance/implement-gate.sh:550`
**Suggestion:** Have `run-checkpoint.sh mark` be idempotent and re-run it at each task boundary in the implement loop (or extend the window to `run_mode.stale_hours`), and log a `stale_marker` row that names the remedy.
**Benefit:** Long sprints do not fail halfway under `deny`, which is the mode this repository plans to run.

### 5. Performance: the surgical-diff hook and the checkpoint write are an order of magnitude slower

- **MEDIUM** (confidence: high) `head/.claude/hooks/quality/karpathy-surgical-diff-check.sh:131` — every Write/Edit now sources `profile-lib.sh`, runs two `loa_knob` reads (one of which is a live yq+jq read because `diff_lines_per_task` is not a profile key), spawns `bash run-checkpoint.sh read --json` (several jq calls plus `br show` per call) and three more jq processes. Measured on this host, ten invocations each: head 270 ms per write with no run and 379 ms with a checkpoint (br stubbed at 20 ms); base 32 ms. `run-checkpoint.sh write` now runs a full `derive` (two `verdict-derive.sh` calls and one `git log` per sprint) at every checkpoint: 2.1 s per write on a one-sprint fixture.
**File:** `head/.claude/hooks/quality/karpathy-surgical-diff-check.sh:131`, `head/.claude/scripts/run-checkpoint.sh:160`
**Suggestion:** Resolve the task key once per checkpoint (have `write`/`mark` drop a tiny `.run/karpathy-task` file the hook reads with `$(<file)`), read both knobs in one `loa_effective_json` pass, and consider deriving only on `mark`, `record-round` and phase changes rather than every `write`.
**Benefit:** Restores the sub-100 ms budget the base header documented for a PostToolUse hook that fires on every edit.

### 6. Test suite: PF-5 depends on an adversarial gate that fails open on yq 4.40

- **LOW** (confidence: medium) `head/tests/unit/profile-floor.bats:141` — the assertion that `adversarial-review-gate.sh` exits 2 holds only when the gate's own yq expression (`… | tostring | sub(…)`) evaluates; on yq 4.40.5 that expression errors and the gate falls through to `exit 0`. The gate is outside this diff, but the new test pins it, so the suite is red on that yq.
**Suggestion:** Pin the yq floor the test needs, or assert on the gate's stderr/decision rather than exit 2 alone.
**Benefit:** Keeps the floor suite green where the floor itself is unchanged.

### 7. Wording: the warning still says "Session diff total"

- **LOW** (confidence: high) `head/.claude/hooks/quality/karpathy-surgical-diff-check.sh:193` — the total is now per task (and the summary field is `task`), but the stderr line still reads "Session diff total N lines", and `tests/unit/karpathy-surgical-diff.bats` KS-4 pins that wording.
**Suggestion:** "Task <key> diff total N lines …" and update KS-4.
**Benefit:** The operator reads the right scope.

### 8. Guardrail readers resolve to "off" when the config cannot be read

- **LOW** (confidence: medium) `head/.claude/scripts/danger-level-enforcer.sh:141` — `loa_knob guardrails.danger_level.enforce false` (and the skill include at `head/.claude/data/skill-includes/input_guardrails.md:3`) return the fallback `false` whenever `profile-lib.sh` cannot resolve (no yq, unparseable YAML, lib not found), even when the operator wrote `enforce: true`. The base read `// true` in those cases. Raised by the dissent as DISS-C-004/005.
**Suggestion:** When the explicit key is present but the lib fails, fall back to a direct read; or have `loa_knob` return a distinct status for "unresolvable" and let safety readers default on.
**Benefit:** An explicit opt-in to a safety control is never silently dropped.

### 9. Knob reader parses block-style YAML only

- **LOW** (confidence: medium) `head/.claude/hooks/safety/block-destructive-bash.sh:733` — `_bdb_heredoc_knob_on` recognises `heredoc_classifier:` only as an indented line under a top-level `destructive_command_guard:`; a flow mapping, a quoted key or an anchor/merge is not seen and the classifier stays on. Turning it off is the tightening direction, so the miss is safe, but the rollback key the docs advertise does not always work. (DISS-C-008.)
**Suggestion:** Fall back to one `yq` read when the fast parse finds the substring but no match.
**Benefit:** The documented rollback key is reliable.

### 10. Derived-cache freshness window is narrower than the activity window

- **LOW** (confidence: low) `head/.claude/hooks/compliance/implement-gate.sh:514` — `_ig_derived_ok` requires `derived_at` within `run_mode.stale_hours` (12 h) while `_ig_fresh` allows 24 h of `last_activity`; a run that checkpointed 13 h ago but was active since loses its sanction. Low impact because `write` refreshes `derived_at` at each checkpoint. (DISS-C-003.)
**Suggestion:** Use one window for both, or document the asymmetry.
**Benefit:** Fewer surprise asks.

### 11. Complexity

- **LOW** (confidence: high) `head/.claude/scripts/run-checkpoint.sh:331` — `cmd_derive` is about 150 lines, `_bdb_hd_member` (`block-destructive-bash.sh:329`) about 140 and `_bdb_heredoc_scrub` (`:644`) about 75. Each implements one grammar or decision table and is commented; no duplicate blocks or circular dependencies were found. SIMPLICITY: justified by the grammar; the gh/git/br allowlists in `_bdb_hd_member` could be table-driven. Lean enough for what it implements; net: -0 lines possible.

---

## Cross-Model Observations

Adversarial dissent ran with `--diff-file pr/head.diff` and the reviewer concerns file: primary `gpt-5.5-pro` (status reviewed), companion `claude-headless` (succeeded, independent family). Ten findings, zero rejected payloads. Triage:

| Id | Severity | Disposition |
|----|----------|-------------|
| DISS-001 `.git/objects/../hooks/pre-commit` path normalisation | BLOCKING | Reproduced; counted as Changes Required §3 (HIGH) |
| DISS-C-001 `check_implement_marker` under `set -e` | ADVISORY | Not a defect: the hook sets no `set -e` (verified; the IG matrix exercises the rc-1 and rc-2 paths) |
| DISS-C-002 two-hour marker never refreshed | ADVISORY | Confirmed; Observation §4 (MEDIUM) |
| DISS-C-003 `derived_at` 12 h vs activity 24 h | ADVISORY | Observation §10 (LOW) |
| DISS-C-004 danger-level enforcement resolves off when the lib cannot read | ADVISORY | Observation §8 (LOW) |
| DISS-C-005 input-guardrail include runs only on a printed `true` | ADVISORY | Folded into Observation §8 (LOW); `profile-lib.sh` is 100755 in the diff |
| DISS-C-006 `enabled` unset in kf/decisions surfaces | ADVISORY | Not a defect: both hooks initialise `enabled="false"` (`loa-kf-surface.sh:53`, `loa-decisions-surface.sh:43`) |
| DISS-C-007 LC_ALL only in the lib entry point | ADVISORY | Not a defect: the hook exports `LC_ALL=C` at line 810, before the scrub call |
| DISS-C-008 knob reader block-style only | ADVISORY | Observation §9 (LOW) |
| DISS-C-009 C-TEAM rows removed from the kernel | ADVISORY | Product decision DEC-0140 with the rules relocated and the arming note added; not a code defect |

## Rejected dissent payloads

- none — `metadata.rejected_summary` is empty and `adversarial-rejected-review.jsonl` holds no rows.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Reviewed | Three blocking defects above; `reviewer.md` carries no `## AC Verification` walkthrough |

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| Each defect the PR introduces is reported with file and line | Pass | Changes Required §1–3 and Observations §1–11 cite `head/<path>:<line>` |
| A merge verdict is given | Pass | CHANGES_REQUIRED (trailer below) |
| Sprint-256 claims hold on the declared tool floor (jq 1.6+) | Fail | `derive`/`record-round` do not run on jq 1.6 (§1, §2) |
| "Fail-closed heredoc classifier" | Fail | Executable-destination bypass via `..`/`//` (§3); same-command `$(cat f)` executor and rc-list gaps (Obs §1, §2) |
| Profiles (`loa.profile`, `profile-lib.sh`) | Pass | 17/17 profile-lib tests, 5/6 floor tests (PF-5 is environment-dependent), knob-reader lint clean |
| Implement gate modes and sanctions | Pass | IG-24..33 matrix 10/10; deny mode is inert until §1 is fixed because the position is never known |
| Per-task surgical-diff state and summary | Pass with concerns | 10/11 (KS-11 is an exec-bit artifact here); latency regression (Obs §5) and stale wording (Obs §7) |
| C-TEAM rows out of the kernel, optional table pruned | Pass | lint-invariants 9/9; CLAUDE.loa.md 9,189 B under the new 9,445 B cap |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [x] Input validation and sanitization present (task keys sanitised; audit rows control-stripped and cut to 256 B; paths canonicalised in the gate) — but not in `_bdb_hd_exec_dest` (§3)
- [x] Authentication/authorization correct (n/a; hook decisions follow the documented PreToolUse contract)
- [ ] No injection vulnerabilities — fence regressions versus base in §3 and Observations §1–2
- [x] Dependencies secure (no new dependencies; jq/yq version assumptions are the issue, §1–2)
- [x] Error messages don't leak sensitive data (content never reaches state or trajectory; verified by KS-9)

---

## Code Quality Summary

**Strengths:**
- The implement-gate mode matrix is exhaustively tested (mode × claims × write class × sanction × cache state) and every cell passed here.
- The fence corpus grew by 62 rows with a `--knob-off` replay and a p95 measurement; all 231 rows decide as declared.
- `profile-lib.sh` handles explicit `false` correctly, caches atomically, refuses floor keys, and the oracle fixture pins `standard` to pre-change behaviour.
- The TSV `-` placeholder in `cmd_derive` and the symlink checks in the surgical hook show care for the edge cases.

**Areas for Improvement:**
- Run the suites on the oldest supported jq and yq; two of the three blocking defects are version assumptions.
- Canonicalise before classifying in the fence, and never drop a body segment because it starts with a shell keyword.
- Treat approvals and pre-existing breaker resets as streak boundaries in `recompute`.
- Budget the hot hooks: the base hook's header documented a 10 ms target; the new one costs 270–380 ms per edit here.

---

## Next Steps

1. Fix the three Changes Required items (jq keyword binding, empty-input guards, destination canonicalisation plus keyword-prefixed segments) and add jq 1.6 to CI or raise the documented floor.
2. Decide on Observations §3–§5 before the deny-mode flip; §3 can halt an upgraded in-flight run at its next checkpoint.
3. Add an `## AC Verification` walkthrough to `grimoires/loa/a2a/sprint-1/reviewer.md`.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":5,"low":6},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T11:20:00Z"} -->
