# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-23
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md
**Change under review:** `pr/head.diff` (sprint-256: inert controls repaired or retired, file-authoritative run position, fail-closed heredoc classifier, profiles, prose-diet fallback; 68 files)

---

## Overall Assessment

The sprint lands a large amount of well-structured work: the implement-gate mode matrix (33 bats cases, the new matrix IG-24..IG-33 passes here), the profile library (17/17 bats cases pass), the Agent Teams table prune with its lint invariant (lint-invariants 9/9, test-lint-invariants 18/18), the per-task surgical-diff state (10/11 cases pass; the one failure is a `noexec` /tmp artifact of this environment), and a fence corpus that replays clean on the new hook (benign 89/89, dangerous 142/142, p95 62 ms).

Two of the headline features do not hold up under verification, and both are fences:

1. **The heredoc consumer classifier opens a bypass class the base hook did not have.** A heredoc body written to a plain file and executed *on the same command* through a pipe, a substitution or an argument-executing option (`cat t | bash`, `sh -c "$(cat t)"`, `source <(cat t)`, `cat t | xargs sh -c`, `git -c core.pager=./t log`, `make` after `cat > Makefile`) is classified `nonexec`, and every body line that starts with a shell keyword (`if`, `then`, `else`, `do`, a `case` arm, a function definition) is dropped before the rules run. I replayed eleven such commands through `pr/head` and `pr/base`: the base hook blocks all eleven (exit 2), the head hook allows all eleven (exit 0). The companion dissent voice found the same gap independently (DISS-C-001, DISS-C-002) and the primary voice found the path-normalisation variant (DISS-001); both are confirmed below.
2. **`run-checkpoint.sh derive` and `record-round` abort on jq 1.6**, which is the jq installed in this environment (and the jq Debian 12 and Ubuntu 22.04 ship; the repository pins no jq minimum). `--arg label` collides with jq's `label` keyword, and `jq -e` exits 0 on empty input, so a trailer-less feedback file turns into an invalid `--argjson`. The PR's own suites show it: run-checkpoint-derive 20 of 22 cases fail, record-round RCR-7 fails. With `derive` failing, no cache ever gains `derived_at`, so `implement_gate.mode: deny` never sees a known position and always asks — the new fence is inert — and the `/loa` Run line silently disappears.

The implementation report (`reviewer.md`) is the PR description alone and carries no `## AC Verification` section, which is an automatic CHANGES_REQUIRED on its own.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Security — heredoc classifier: same-command execution through a pipe or substitution is accepted as non-executing, and keyword-led body lines are dropped

- **HIGH** (confidence: high) `head/.claude/hooks/safety/block-destructive-bash.sh:631` — `_bdb_hd_same_line_exec` judges each pipeline segment alone, so a target named under a safe reader (`cat t`) that is piped into `bash` never flips the class; combined with `_bdb_hd_segword` (`:538`, `:552`) returning `if`/`then`/`else`/`do`/`f()` as the command word and `_bdb_hd_scan_body` (`:593`) dropping every segment whose word is not a fence verb, the destructive line inside the body is removed before any rule runs.
**File:** `head/.claude/hooks/safety/block-destructive-bash.sh:631` (pipeline-blind same-line check), `:538`–`:552` (keywords not stripped), `:593` (keyword-led segments dropped)
**Issue:** Verified by replaying the following through both hooks (`LOA_REPO_ROOT` set, `LOA_AUDIT_REPLAY=1`); every row is `head=0 base=2`, class `nonexec`:

```
cat <<EOF > x.txt\nif :; then rm -rf src; fi\nEOF\ncat x.txt | bash
cat <<EOF > x.txt\nif :; then rm -rf src; fi\nEOF\nsh -c "$(cat x.txt)"
cat <<EOF > x.txt\nif :; then rm -rf src; fi\nEOF\nsource <(cat x.txt)
cat <<EOF > x.txt\nif :; then rm -rf src; fi\nEOF\ncat x.txt | xargs -0 sh -c
cat <<EOF > x.txt\nif false; then :; else rm -rf src; fi\nEOF\ncat x.txt | bash
cat <<EOF > x.txt\nfor d in src; do rm -rf \$d; done\nEOF\ncat x.txt | sh
cat <<EOF > x.txt\nf() { rm -rf src; }\nf\nEOF\ncat x.txt | bash
cat <<EOF > t\ncase x in x) rm -rf src;; esac\nEOF\ncat t | bash
cat <<'EOF' > t\n$(rm -rf src)\nEOF\ncat t | bash          # quoted delimiter exempts the $( fallback (:582)
cat <<'EOF' > t\nif :; then rm -rf src; fi\nEOF\ngit -c core.pager=./t log   # git is a safe reader (:222) but runs the pager
cat <<'EOF' > Makefile\nall:\n\tif :; then rm -rf src; fi\nEOF\nmake
```

The same command with `bash x.txt`, `bash < x.txt` or `source x.txt` on the last line is caught (class `interpreter`), so the gap is specifically the pipeline / substitution form plus the keyword drop. `hooks-reference.md:294` documents the opposite ("Naming the target elsewhere on the same command outside a safe reader has the same effect"), and the corpus has no row for any of these shapes (nearest: `tests/fixtures/fence-corpus/corpus.jsonl:212` D119, `bash x.sh`).
**Why This Matters:** This is a regression against the base fence on a same-command execution, not the documented "later command" gap (`:175`, `hooks-reference.md:298`). The classifier is sold as fail-closed; here it drops the only line the fence exists to see.
**Required Fix:** (a) In `_bdb_hd_same_line_exec`, judge a pipeline as a unit: when any segment of a pipeline names the target and any member of that pipeline is not a safe reader (or the line holds `$(`, backtick, `<(` or `>(` anywhere), return 0. (b) In `_bdb_hd_segword`, strip the shell keywords `if then else elif do while until case esac time !` and a `word)` case arm and an `f() {` definition before taking the command word, or treat a keyword-led segment as `_hd_full=1`. (c) Add the eleven commands above to the corpus as `block` rows. (d) Correct `hooks-reference.md:294` to match whatever the code does.
**Reference:** CWE-184 (incomplete list of disallowed inputs), CWE-693 (protection mechanism failure); DISS-C-001, DISS-C-002.

### 2. Security — heredoc classifier: write-target path is judged without normalisation

- **HIGH** (confidence: high) `head/.claude/hooks/safety/block-destructive-bash.sh:321` — `_bdb_hd_exec_dest` compares the raw dirname against `PATH` entries and the raw path against `_bdb_hd_re_sys` (`:190`), so `/usr/local/bin/./helper` matches neither (`bin/./helper` fails `s?bin/[^/]+$`; `/usr/local/bin/.` ≠ `/usr/local/bin`) and a heredoc that overwrites a command on `PATH` is classified `nonexec`.
**File:** `head/.claude/hooks/safety/block-destructive-bash.sh:303`–`:321`
**Issue:** Verified: `tee /usr/local/bin/./helper <<'EOF'\nif true; then rm -rf src; fi\nEOF` is `head=0 base=2`; the same command with `/usr/local/bin/helper` is `head=2` (class `interpreter`). `/../`, `//` and `~user` forms have the same shape.
**Why This Matters:** Overwriting an executable on `PATH` with a body whose destructive lines were dropped (finding 1) is exactly the "executable content" the destination check exists to catch.
**Required Fix:** Either canonicalise the literal path before judging (collapse `//`, `/./`, resolve `..` textually, expand `~/`) or, simpler and fail-closed, treat any literal path containing `/./`, `/../`, `//` or starting with `~` other than `~/` as non-literal (class `interpreter`). Add a corpus row.
**Reference:** CWE-41 (improper resolution of path equivalence); DISS-001.

### 3. Functionality — `run-checkpoint.sh derive` aborts on jq 1.6: `label` is a jq keyword

- **HIGH** (confidence: high) `head/.claude/scripts/run-checkpoint.sh:378` — `--arg label "$label"` and `$label` inside the per-sprint jq program: jq 1.6 (installed here) refuses to compile it (`syntax error, unexpected label, expecting IDENT or __loc__`), the assignment fails under `set -euo pipefail` and `cmd_derive` exits 3 for any ledger with at least one sprint in the active cycle.
**File:** `head/.claude/scripts/run-checkpoint.sh:378`
**Issue:** Reproduced on a minimal fixture (one completed sprint, RUNNING cache): `derive --json` exits 3 with the compile error. In the overlay, 20 of the 22 `tests/unit/run-checkpoint-derive.bats` cases fail (`RCD-1`, `:80`, fails at `[ "$status" -eq 0 ]`). Consequences downstream: `write` and `mark` run `derive --write` and only print the error (`:175`, `:542`), so no cache ever carries `derived_at`; `implement-gate.sh` `read_position` therefore never finds a known position and `implement_gate.mode: deny` degrades to ask on every write (the fence the sprint introduces is inert); `loa-status.sh:1019` discards the failure and prints no Run line. `jq -n --arg lbl x '$lbl'` works on the same jq, so the fix is a rename.
**Why This Matters:** The file-authoritative run position (FR-5) and the deny fence (FR-4a) are the sprint's headline controls; both are non-functional on a jq the repository does not exclude (no jq minimum is declared anywhere under `.claude/`).
**Required Fix:** Rename the binding (`--arg lbl "$label"` / `$lbl`), re-run `tests/unit/run-checkpoint-derive.bats` on jq 1.6 and 1.7, and either declare a jq minimum in the compat layer or keep the scripts 1.6-clean.

### 4. Functionality — `fb_parse` breaks on every trailer-less feedback file on jq 1.6

- **HIGH** (confidence: high) `head/.claude/scripts/run-checkpoint.sh:226` — `jq -e 'type == "object"' <<<"$pj" || pj='{}'` relies on `-e` exiting non-zero for empty input; jq 1.6 exits 0 there, so `pj` stays empty and the following `--argjson p "$pj"` is "invalid JSON text", aborting `fb_parse` under `set -e`.
**File:** `head/.claude/scripts/run-checkpoint.sh:226` (`fb_parse`, `:218`)
**Issue:** Reproduced: `record-round --gate review --file <legacy file without trailer>` exits 2 with `jq: invalid JSON text passed to --argjson` (`tests/unit/run-checkpoint-record-round.bats:133` RCR-7 fails here). `derive` hits the same path for any sprint whose current or `-rN` feedback lacks a trailer, so one legacy file in the active cycle aborts the whole derivation.
**Why This Matters:** Legacy feedback is explicitly a supported input ("a file without a trailer is legacy", `:26`); on this jq it is a crash.
**Required Fix:** Default before the probe: `[[ -n "$pj" ]] && jq -e 'type == "object"' <<<"$pj" >/dev/null 2>&1 || pj='{}'` (and the same guard for `vj`). Add a jq-1.6 run to CI or pin the minimum.

---

## Observations

### 1. Run position — legacy rounds inflate the breaker recompute

- **MEDIUM** (confidence: high) `head/.claude/scripts/run-checkpoint.sh:280` — `recompute` keeps every round with `approved == false`; a trailer-less file is `approved: false` (verdict-derive exits 2 with `verdict: null`), so an old "All good" review without a trailer counts as a changes-required round, its `counts: null` repeats as `"null"` so `no_progress` climbs, and its hash (md5 of an empty findings grep) repeats so three such files in the active sprint trip `same_issue` and the derivation halts the run.
**File:** `head/.claude/scripts/run-checkpoint.sh:276`–`:280`
**Suggestion:** Exclude `.trailer == false` rounds from `recompute` (they are already listed under `derivation.legacy_feedback`), matching the header's "legacy: no verdict" (`:26`).
**Benefit:** A derived HALTED is sticky; a false trip costs an operator `/run-resume --reset-ice`.

### 2. Implement gate — the marker sanction is a model-writable allow

- **MEDIUM** (confidence: high) `head/.claude/hooks/compliance/implement-gate.sh:545` — `check_implement_marker` grants `allow/sanctioned_marker` in every mode, including `deny`, on a file the model writes through Bash (`run-checkpoint.sh mark`, or a plain `printf > .run/implement-active.json`), which neither this gate nor the Bash fence sees; the file's own header calls model-authored claims tighten-only.
**File:** `head/.claude/hooks/compliance/implement-gate.sh:545`–`:589`
**Suggestion:** Already listed as an accepted gap in `hooks-reference.md` (bd-taee), so not blocking; consider having `mark` require a RUNNING cache or a `/run` session id, or logging the marker's writer, so `deny` cannot be lifted for two hours by one Bash call. Cross-model DISS-C-003.
**Benefit:** Keeps the deny fence's "fence" claim honest.

### 3. Guardrails — unconditional `source` and a silent default flip

- **MEDIUM** (confidence: medium) `head/.claude/scripts/danger-level-enforcer.sh:138` — `source "$SCRIPT_DIR/lib/profile-lib.sh"` under `set -euo pipefail` (`:16`) with no existence check; a mount that lacks the new lib kills the enforcer before `is_enforcement_enabled` runs, and the skill include treats a non-zero script as fail-open. `guardrails-orchestrator.sh:107` is the same. Separately, `.loa.config.yaml.example:1358` and `:1404` flip both guardrail defaults to false and `profiles.yaml` `standard` follows, so an install that never set the keys loses both controls on upgrade with nothing surfaced (DISS-C-004).
**Suggestion:** Guard the source (`[[ -f ... ]] && source ... || { echo "profile-lib missing"; exit 1-with-a-BLOCK-shaped-reason; }`), and print a one-time notice (or a `/loa` line) when a guardrail key is unset and the profile default differs from the pre-cycle default.
**Benefit:** The DEC-0161 decision stays deliberate per host instead of silent.

### 4. Documentation and corpus — the classifier's stated guarantee is wider than the code

- **MEDIUM** (confidence: high) `head/.claude/loa/reference/hooks-reference.md:294` — states that naming the target elsewhere on the same command outside a safe reader flips the class; finding 1 shows the pipeline and substitution forms do not. The corpus (`tests/fixtures/fence-corpus/corpus.jsonl:212`–`:236`) has no row for a piped execution, a keyword-led body line, a `/./` path or a `git -c core.pager=` consumer.
**Suggestion:** Fix the sentence with the code and add the rows from findings 1 and 2 (and `tee x | bash`, `. <(cat x)`) so the corpus pins the fail-closed claim.
**Benefit:** The corpus is the only mechanical check of the classifier's safety property.

### 5. Performance — the surgical-diff hook spawns the checkpoint reader on every write

- **LOW** (confidence: high) `head/.claude/hooks/quality/karpathy-surgical-diff-check.sh:131` — every Write/Edit now runs `run-checkpoint.sh read --json`, which under `set -e` runs jq several times and, when a task checkpoint exists, `br show`; the hook's previous budget was single-digit milliseconds.
**Suggestion:** Read `.checkpoint.task`/`.sprint` from the state file directly with one jq (the bead-closed check is a recovery concern, not a counting one), or cache the key in the summary file keyed on the state file's mtime.
**Benefit:** Keeps the PostToolUse path cheap on long implementation sessions.

### 6. Wording — the per-task warning still says "Session"

- **LOW** (confidence: high) `head/.claude/hooks/quality/karpathy-surgical-diff-check.sh:193` — the total is per task now; the message (pinned by KS-4) still reads "Session diff total".
**Suggestion:** Say "Task diff total" and update KS-4 together.

### 7. Observability — `/loa` hides a failing derivation

- **LOW** (confidence: high) `head/.claude/scripts/loa-status.sh:1019` — a non-zero `derive` (as in finding 3) is swallowed (`2>/dev/null`, `&&` chain) and the Run line is simply absent; an operator cannot tell "in sync" from "derive crashed".
**Suggestion:** On an exit other than 0 or 4, print `Run: derive failed (<first stderr line>)`.

---

## Cross-Model Observations

Two voices ran (`gpt-5.5-pro` primary, `claude-headless` companion, `counted_as: independent_voice`); six findings, all triaged:

- DISS-001 (BLOCKING, primary) — path normalisation in `_bdb_hd_exec_dest`: confirmed by probe; counted as Changes Required 2.
- DISS-C-001 (BLOCKING, companion) — keyword-led body lines dropped from a nonexec body: confirmed by probe; folded into Changes Required 1.
- DISS-C-002 (ADVISORY) — `git`/`gh` on the safe-reader list run helpers (`git -c core.pager=./t`): confirmed by probe (`head=0 base=2`); folded into Changes Required 1.
- DISS-C-003 (ADVISORY) — marker sanction lifts deny via Bash: real, documented as accepted; Observation 2.
- DISS-C-004 (ADVISORY) — silent guardrail default flip and unconditional `source`: real; Observation 3.
- DISS-C-005 (ADVISORY) — C-TEAM removal might orphan the team hooks: not a defect. The three team hooks reference the ids only in comments and block messages, stay registered as `dormant` (armed by `LOA_TEAM_MEMBER`), and the rules moved verbatim to `agent-teams-reference.md`.

## Rejected dissent payloads

None: `metadata.rejected_summary` is empty and both sidecars (`adversarial-rejected-review.jsonl`, `adversarial-rejected-review-companion.jsonl`) hold zero rows.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | Changes Required 1–4 above; `reviewer.md` has no `## AC Verification` walkthrough |

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| "review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict" (sprint.md Success Criteria) | Fail | Four high findings with `head/<path>:<line>` citations above; verdict below |
| `reviewer.md` carries `## AC Verification` | Fail | The report is the PR description only (automatic CHANGES_REQUIRED per the review protocol) |

### Verification run (overlay of `pr/head` on this checkout; jq 1.6, yq 4.40.5, bats)

| Check | Result |
|-------|--------|
| fence corpus (`run-corpus.sh`) | benign 89/89, dangerous 142/142, p95 62 ms |
| `profile-lib.bats` | 17/17 |
| `lint-invariants.bats`, `test-lint-invariants.sh` | 9/9, 18/18 |
| `implement-gate.bats` IG-24..IG-33 (new matrix) | pass (IG-1..IG-12 need fixtures absent from this checkout) |
| `karpathy-surgical-diff.bats` | 10/11 (KS-11 fails only because /tmp is mounted `noexec` here; the hook exits 0 when run through `bash`) |
| `run-checkpoint-derive.bats` | 2/22 — findings 3 and 4 |
| `run-checkpoint-record-round.bats` | 7/8 — finding 4 |
| `guard-yield.bats` GY-1/GY-3 | fail, not attributable: this checkout's `guard-yield.sh` carries a later "System-Zone block is never a false positive" rule than the PR's test row assumes |
| `profile-floor.bats` PF-1, PF-5; `skill-capabilities.bats`; `prompt-budget.bats` | not verifiable here (`guard-origins.bats` absent; `noexec` /tmp; the validator and the budget tool pass when invoked through `bash`) |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [ ] Input validation and sanitization present — the heredoc classifier's path and pipeline handling (Changes Required 1, 2)
- [x] Authentication/authorization correct — n/a
- [x] No SQL/XSS injection vulnerabilities — n/a (shell; key paths validated before reaching yq)
- [x] Dependencies secure (no known CVEs) — n/a
- [x] Error messages don't leak sensitive data — paths are control-stripped and cut to 256 bytes

---

## Code Quality Summary

**Strengths:**
- The implement-gate rewrite is careful: one yq read, tighten-only claims, `jq fromdateiso8601` for portable time, trust inputs ask in every mode, and the 4-mode matrix is tested exhaustively.
- `profile-lib.sh` resolves explicit > profile > fallback with floor keys mechanically excluded, caches on mtime+size, and never writes the repository cache from a seam config.
- The surgical-diff hook shrank from 848 lines of perf caching to 208 lines of per-task state with the same safety invariants.
- The fence corpus replay is clean and the knob-off path reproduces the pre-cycle scan exactly where expected.

**Areas for Improvement:**
- Fail-closed claims need adversarial corpus rows before the prose asserts them.
- Shell scripts that must run on operator machines should be exercised on jq 1.6 as well as 1.7, or the repository should declare a minimum.
- `SIMPLICITY[shrink]`: `_bdb_hd_segword`'s wrapper-stripping loop and `_bdb_hd_same_line_exec`'s manual segmenting re-implement what `_bdb_hd_tokenize` already produces; after the fix in Changes Required 1, consider one tokenised walk per line. Lean enough otherwise. `net: -40 lines possible`.

---

## Next Steps

1. Fix Changes Required 1–4 (classifier pipeline/keyword/path handling; `run-checkpoint.sh` jq-1.6 compatibility), add the corpus rows, and re-run `run-checkpoint-derive.bats`, `run-checkpoint-record-round.bats` and `run-corpus.sh`.
2. Decide Observations 1–3 (legacy rounds in the recompute, marker sanction, guardrail default flip) and record the decisions in NOTES.md.
3. Add an `## AC Verification` section to `grimoires/loa/a2a/sprint-1/reviewer.md`.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":4,"medium":4,"low":3},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-23T08:05:00Z"} -->
