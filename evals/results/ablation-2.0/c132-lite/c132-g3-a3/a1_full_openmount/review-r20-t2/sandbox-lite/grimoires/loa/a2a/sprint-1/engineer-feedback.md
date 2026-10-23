# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-23
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)

---

## Overall Assessment

The change under review is sprint-256 of cycle-129: implement-gate modes (ask/telemetry/deny with marker and derived-cache sanctions), the file-authoritative run position in `run-checkpoint.sh` (`derive`, `record-round`, `mark`), the fail-closed heredoc consumer classifier in the Bash fence, the `loa.profile` resolver (`profile-lib.sh`), the per-task Karpathy surgical hook, the Agent Teams table pruning and the prose diet. The design is coherent and most of it is well tested: the implement-gate matrix (IG-24..33), `profile-lib.bats` (17/17), `lint-invariants.bats` (9/9), the fence corpus (benign 89/89, dangerous 142/142, p95 76 ms) and the karpathy suites all pass on the head tree.

Two defects block the merge. First, the heredoc classifier has a same-command execution bypass: a heredoc written to a plain file and executed in the *same* Bash command through a glob, `cat file | bash`, `bash <(cat file)`, `bash -c "$(cat file)"`, an indirect variable or `make` is classified non-executing, and `_bdb_hd_scan_body` then drops every body segment that does not start with a fence verb. Six such commands that the base fence blocks (FR-SZ2-REDIR, a floor fence) are allowed by the head fence. Second, `run-checkpoint.sh derive` and `record-round` are broken on jq 1.6: the per-sprint jq uses `$label` (a jq keyword, rejected by jq 1.6) and `fb_parse` relies on `jq -e` exiting non-zero on empty input (jq 1.6 exits 0), so `derive` exits 3 on every ledger and `record-round` exits 2 on any trailer-less feedback file. The derive suite fails 17/22 and `record-round` 1/8 in this environment (jq-1.6, Debian). The repository states no jq floor, and every other script in the tree runs on 1.6.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Security — heredoc classifier: same-command execution bypass of a floor fence

- **HIGH** (confidence: high) `head/.claude/hooks/safety/block-destructive-bash.sh:608` — `_bdb_hd_same_line_exec` only recognises an executing reference when a later token's literal basename equals the heredoc target; a glob (`bash ./ru[n]`, `bash n.m?`), a pipe from a safe reader (`cat n.md | bash`), a process or command substitution (`bash <(cat n.md)`, `bash -c "$(cat n.md)"`), an indirect variable (`f=n.md; bash $f`) or a consumer that does not name the file (`make` after `cat > Makefile`) is missed, the heredoc stays `nonexec`, and `_bdb_hd_scan_body` (`:576`) drops every body line whose command word is not a fence verb. The written body then executes in the same command unseen.
**File:** `head/.claude/hooks/safety/block-destructive-bash.sh:608-639` (`_bdb_hd_same_line_exec`), `:222-227` (`_bdb_hd_is_safe_reader` lists `cat`, `git`, `gh`), `:576-600` (`_bdb_hd_scan_body`), `:538-574` (`_bdb_hd_segword` does not strip `if/then/do/else/elif/while/until` or case arms)
**Issue:** Reproduced end to end by feeding Bash-tool payloads to the head and base hooks (exit 0 = allow, 2 = block):

```
head=0 base=2 | cat > run <<'EOF' / echo pwned > .claude/settings.json / EOF / bash ./ru[n]
head=0 base=2 | cat <<'EOF' > n.md / echo pwned > .claude/settings.json / EOF / cat n.md | bash
head=0 base=2 | cat <<'EOF' > n.md / … / EOF / bash <(cat n.md)
head=0 base=2 | cat <<'EOF' > n.md / … / EOF / bash -c "$(cat n.md)"
head=0 base=2 | cat <<'EOF' > n.md / … / EOF / f=n.md; bash $f
head=0 base=2 | cat > Makefile <<'EOF' / all: / <tab>cp x .claude/hooks/x.sh / EOF / make
head=2 base=2 | control: … / EOF / bash n.md            (D119 shape, caught)
head=2 base=2 | control: body `rm -rf src` is kept as a fence-verb segment
```

The body content that disappears is exactly the class the fence-verb keep does not cover: `echo … > .claude/settings.json` (FR-SZ2-REDIR), `cp x .claude/hooks/x.sh` (FR-SZ-COPY), `tee`, `ln`, `sed -i` into the System Zone, and any destructive segment prefixed by a shell keyword (`if true; then rm -rf src; fi`, `for f in src; do rm -rf $f; done` — both scrub to nothing, verified with `_bdb_heredoc_scrub`). FR-SZ and FR-SZ2 are `floor_guards` in `.claude/data/floor.yaml`; the hooks-reference "Remaining gap" (`head/.claude/loa/reference/hooks-reference.md:298`) covers only execution by a *later* command, so this is a regression inside the fence's own stated scope, not the documented gap.
**Why This Matters:** The classifier is on by default (`destructive_command_guard.heredoc_classifier: true`). An autonomous agent that writes a helper file with a heredoc and runs it in the same command no longer has its body scanned, and the pre-cycle fence did scan it. The corpus (D119–D121) only covers the literal-basename shapes.
**Required Fix:** (1) In `_bdb_hd_same_line_exec`, treat any non-body line holding `$(`, a backtick, `<(` or `>(`, a glob character in a token, or a `$`-prefixed token as executing (return 0), mirroring `_bdb_hd_ctx_bad`; remove `cat`, `git` and `gh` from `_bdb_hd_is_safe_reader` when the segment is a pipeline member feeding an interpreter, or simply fall back to the full scan whenever any later segment's command word is an interpreter/wrapper (`_bdb_hd_is_interp`) regardless of whether it names the target. (2) In `_bdb_hd_segword`, strip the shell keywords (`if then else elif fi while until do done case esac select in coproc function`) and a leading case-arm pattern before reading the command word, or set `_hd_full=1` in `_bdb_hd_scan_body` when a segment's command word is a keyword. (3) Add corpus rows for each of the six shapes above (expect `block`) and for `cat <<EOF > notes.md` with an `if …; then rm -rf …; fi` body.
**Reference:** CWE-693 (Protection Mechanism Failure); the fence's own posture note (`hooks-reference.md:287`) accepts subshell wrapping as a bypass class for the *whole command*, not for a heredoc body the fence previously scanned.

### 2. Functionality — `run-checkpoint.sh derive` / `record-round` fail on jq 1.6

- **HIGH** (confidence: high) `head/.claude/scripts/run-checkpoint.sh:378` — the per-sprint jq program binds `--arg label` and reads `$label` (`:380`, `:389`); `label` is a jq keyword and jq 1.6 rejects it (`syntax error, unexpected label, expecting IDENT or __loc__`), so `cmd_derive` exits 3 before producing any report, on every ledger.
**File:** `head/.claude/scripts/run-checkpoint.sh:378-395` and `:225-226`
**Issue:** Reproduced with the RCD-1 fixture (`bash -x`): `jq: error: syntax error, unexpected label … line 2: def mine: … $label` → `sj=` → exit 3. Minimal: `jq -n --arg label x '$label'` fails on jq-1.6 and works on 1.7. A second 1.6 incompatibility sits in `fb_parse` (`:225-226`): for a feedback file without a trailer `pj` is empty, and `jq -e 'type == "object"' <<<"$pj"` exits 0 on empty input under jq 1.6 (verified: `printf '' | jq -e 'type == "object"'; echo $?` → 0), so `pj` stays `""`, `--argjson p ''` fails with `invalid JSON text passed to --argjson`, `fb_parse` prints nothing and `record-round` exits 2 (`set -e`) on any legacy feedback file; `derive` would hit the same path on RCD-3. Test evidence on the head tree (jq-1.6): `run-checkpoint-derive.bats` 17/22 fail (RCD-1..12, 14, 15, 17, R1, R4, R5), `run-checkpoint-record-round.bats` RCR-7 fails; the RCR-1..6 cases that never reach a legacy file pass.
**Why This Matters:** `derive` is the file-authoritative run position this sprint ships. On a jq 1.6 host it is inert: every `run-checkpoint.sh write` and `mark` prints the derive error to stderr (`:174`, `:541`), `/loa`'s Run line is silently skipped, `/run-resume` step 0a gets exit 3 (its contract handles only 4), and the implement gate's `deny` mode never sees a `derived_at`, so it can only ever ask. The repository documents no jq minimum, and the rest of the tree (including the implement gate and the fence) runs on 1.6.
**Required Fix:** Rename the binding (`--arg lbl` / `$lbl`, or `--arg local_label`) and avoid other jq keywords as variable names; replace the `jq -e` emptiness probe with an explicit test (`[[ -n "$pj" ]] && jq -e 'type == "object"' <<<"$pj" >/dev/null 2>&1 || pj='{}'`); either declare a jq ≥ 1.7 floor in the framework prerequisites and have `run-checkpoint.sh` fail loudly with a named reason below it, or keep 1.6 compatibility (preferred — nothing else in the tree needs 1.7). Run `run-checkpoint-derive.bats` and `run-checkpoint-record-round.bats` under jq 1.6 in CI.

---

## Observations

### 1. Fence — generic exec-flag check defeats the classifier for common consumers

- **MEDIUM** (confidence: high) `head/.claude/hooks/safety/block-destructive-bash.sh:363` — `_bdb_hd_re_exflag='^-[A-Za-z]*[cex][A-Za-z]*$'` (`:187`) is applied to every allowlisted consumer before its own grammar, so `jq -c`, `jq -e`, `jq -rc`, `yq -e`, `grep -c`, `grep -x`, `sed -n -e p`, `cat -e` and `echo -e` all classify `interpreter` and fall back to the full scan.
**Suggestion:** Apply the generic check only to consumers without a dedicated argv grammar, or whitelist the harmless short flags per command (`jq`/`yq`: `-c -e -r -S -s`; `grep`: `-c -x -E`) before the `[cex]` test. Add a corpus `allow` row for `jq -c '…' <<'EOF'` with a destructive string in the body.
**Benefit:** The #1245 false-positive class the classifier exists to remove still fires for the most common heredoc consumers in this codebase.

### 2. Karpathy hook — latency regression on every Write/Edit

- **MEDIUM** (confidence: high) `head/.claude/hooks/quality/karpathy-surgical-diff-check.sh:131` — the PostToolUse hook now forks `run-checkpoint.sh read --json` (bash + five jq calls, plus `br show` when beads is installed) and sources `profile-lib.sh` for two `loa_knob` reads on every Write/Edit/NotebookEdit. Measured on this host: head ≈ 280 ms per invocation without a checkpoint and ≈ 590 ms with one, versus ≈ 45 ms for the base hook; the hooks-reference budgets shell hooks at < 100 ms (`head/.claude/loa/reference/hooks-reference.md:229`).
**Suggestion:** Read the checkpoint task straight from `.run/sprint-plan-state.json` with one jq (the hook does not need the beads verification `read` performs), cache the two knob values in the summary file, or run the checkpoint lookup only when the summary's `task` is older than the state file's mtime.
**Benefit:** Keeps the per-tool-call hook cost inside the documented budget; the design note's "per-task files are small" argument does not account for the new fork.

### 3. Karpathy hook — the "task" key is the last closed bead, not the active one

- **MEDIUM** (confidence: medium) `head/.claude/hooks/quality/karpathy-surgical-diff-check.sh:131-138` — `run-checkpoint.sh read --json` returns `.checkpoint.task` only when beads confirms that task is **closed** (otherwise it discards the checkpoint and returns `{checkpoint: null, sprint}`), so during implementation the key is either the bead that just closed or, whenever `br` is absent or the task is still open, the sprint. Reproduced: with `checkpoint.task = bd-1` and no `br`, the summary reads `"task":"sprint-1"`. `head/.claude/skills/reviewing-code/SKILL.md:220` tells reviewers to read `.run/karpathy-surgical/<bead>.jsonl` for the sprint beads, which will hold the lines written while the *next* bead was in progress.
**Suggestion:** Key on the active bead (first open bead of the sprint from `br ready`, or `.checkpoint.task` without the closed-check) and say so in the hook header and in the reviewing-code SKILL line; or rename the key to `after-<bead>` so the reviewer reads it correctly.
**Benefit:** The SURGICAL axis attributes diff size to the right task.

### 4. Implement gate — the marker sanction is self-issuable through Bash

- **LOW** (confidence: high) `head/.claude/hooks/compliance/implement-gate.sh:545` — `check_implement_marker` sanctions every App-Zone write for two hours in every mode, including `deny`, on a `.run/implement-active.json` that `run-checkpoint.sh mark` (or a `printf` through the Bash tool) can create outside any run; the trust-input list only guards Write/Edit. The hooks-reference records this as an accepted gap (`:273`), so it is not blocking, but the `deny` documentation calls the gate "a fence only in this mode" without qualifying "against Write/Edit".
**Suggestion:** Have `mark` refuse when the derived cache is not RUNNING, or state the Write/Edit-only scope next to the word "fence" in the hook header and the reference.
**Benefit:** Operators turning on `deny` know what it does and does not fence.

### 5. Skill include — retrospective postlude passes no fallback

- **LOW** (confidence: medium) `head/.claude/data/skill-includes/retrospective_postlude.md:1` — the include runs `profile-lib.sh knob invisible_retrospective.enabled` with no fallback, unlike `input_guardrails.md`. When `profiles.yaml` is missing or unreadable `loa_knob` falls to `_loa_pl_live` and prints the empty fallback, so the postlude silently never runs under the `standard` profile (whose value is `true`).
**Suggestion:** Pass the fallback (`knob invisible_retrospective.enabled true`) in the include and re-render the skills.
**Benefit:** The example's default survives a missing profiles file.

### 6. Karpathy hook — stale wording in the warning

- **LOW** (confidence: high) `head/.claude/hooks/quality/karpathy-surgical-diff-check.sh:193` — the warning still says "Session diff total" although the total is now per task; the state path it prints is the per-task file.
**Suggestion:** "Task diff total ${RUNNING} lines (task ${KEY}) exceeds …".
**Benefit:** The operator reading the warning is not told the wrong scope.

### 7. Fence — autostart content written through a non-executing consumer

- **LOW** (confidence: medium) `head/.claude/hooks/safety/block-destructive-bash.sh:303` — `_bdb_hd_exec_dest` does not treat `~/.config/systemd/user/*.service`, `~/.config/autostart/*.desktop`, cron spool paths outside `/etc`, or a `Makefile` as executable content, so `cat <<'EOF' > ~/.config/systemd/user/x.service` with an `ExecStart=/bin/rm -rf …` body is `nonexec` and its body is dropped (verified with `_bdb_heredoc_consumer_class`). The documented later-command gap covers the execution, but the targets are a short list worth adding.
**Suggestion:** Extend `_bdb_hd_re_sys` with `\.config/(systemd|autostart)/`, `(^|/)Makefile$`, `(^|/)GNUmakefile$`, `/var/spool/cron`.
**Benefit:** Closes the cheapest persistence targets without touching the grammar.

### 8. Process — implementation report and changelog

- **LOW** (confidence: high) `pr/PR.md:1` — the implementation report is the PR title plus "68 file(s) in scope"; there is no `## AC Verification` walkthrough, no per-task evidence, and the change touches no CHANGELOG. The task brief says the PR files are the whole input, so this is recorded rather than used as the automatic-fail trigger the skill prescribes.
**Suggestion:** Add the AC walkthrough (DEC-0140/0141/0143/0152/0161/0163/0166/0167/0168 each mapped to `file:line`) and a CHANGELOG entry per task before the audit.
**Benefit:** The audit gate can trace each decision to its evidence.

---

## Cross-Model Observations

Adversarial review ran with two voices (primary `gpt-5.5-pro` answered by `codex-headless`, companion `claude-headless`; `consensus_outcome: consensus`, 2/2 voices, `rejected_summary: []`). Triage:

- DISS-001 (BLOCKING, glob execution `bash /tmp/payloa?` after a `tee` heredoc; `if … then … fi` segments dropped) — real defect, counted under Changes Required §1.
- DISS-C-001 (BLOCKING, `_bdb_hd_segword` does not strip shell keywords; `then rm -rf /` segment dropped) — real defect, the second half of Changes Required §1.
- DISS-C-002 (ADVISORY, `_bdb_hd_same_line_exec` misses quoted substitutions; `git`/`gh` on the safe-reader list run files via `-c core.sshCommand=` / `gh extension install`) — real, folded into the fix list of §1.
- DISS-C-003 (ADVISORY, `_bdb_hd_re_exflag` matches `jq -c`, `grep -c`, `echo -e`) — real, Observation §1.
- DISS-C-004 (ADVISORY, bare `check_implement_marker; marker_rc=$?` under errexit) — not a defect: the hook sets no `set -e` (verified, no `set -` line in `implement-gate.sh`); the idiom is safe as written.
- DISS-C-005 (ADVISORY, marker self-issuable through Bash) — accepted gap already documented in hooks-reference; Observation §4.
- DISS-C-006 (ADVISORY, postlude omits the fallback argument; exec bit / CLI contract of profile-lib.sh) — the CLI contract holds (`profile-lib.sh knob <key> [fallback]` verified, mode 100755 in the diff); the missing fallback is Observation §5.

## Rejected dissent payloads

- None: `metadata.rejected_summary` is empty and the sidecar `adversarial-rejected-review.jsonl` holds no rows.

---

## Test Results (head tree, this environment: bash 5.2, jq 1.6, mikefarah yq 4.40, bats 1.x)

The PR's touched files were overlaid on the framework checkout and executed from an exec-capable directory (`/tmp` is mounted `noexec` here, which produced spurious "Permission denied" failures in an earlier pass; those are excluded below).

| Suite | Result | Notes |
|-------|--------|-------|
| `tests/unit/implement-gate.bats` | 24/33 pass | IG-24..33 (the new mode matrix) all pass; IG-1..8, IG-12 fail only because `tests/fixtures/pretooluse-payloads/` is not part of the PR snapshot (environment) |
| `tests/unit/run-checkpoint-derive.bats` | 5/22 pass | 17 failures, all from the jq 1.6 defects in Changes Required §2 |
| `tests/unit/run-checkpoint-record-round.bats` | 7/8 pass | RCR-7 fails on the legacy-file path (§2) |
| `tests/unit/profile-lib.bats` | 17/17 pass | |
| `tests/unit/profile-floor.bats` | 5/7 pass | PF-1 needs `guard-origins.bats` (not in snapshot); PF-5 asserts the adversarial-review gate exits 2 without an envelope, but the checkout's gate (unchanged by the PR) exits 0 for that invocation in head and base alike — environment/version mismatch, unverified |
| `tests/unit/karpathy-surgical-diff.bats`, `-hook.bats`, `karpathy-trajectory-event.bats` | 11/11, 6/6, 4/4 pass | the two `secret=` fixture lines are redacted in this snapshot and were restored locally to run the suites |
| `tests/unit/lint-invariants.bats` | 9/9 pass | includes the live self-test `test-lint-invariants.sh` |
| `tests/unit/skill-capabilities.bats` | 42/43 pass | SC-T-AGENT-7 fails on a yq expression in a pre-existing test (yq version) |
| `tests/unit/prompt-budget.bats` | 9/10 pass | PB-8 needs the CI sentinel fixture trees (not in snapshot) |
| `tests/unit/guard-yield.bats` | 8/11 pass | GY-1, GY-3, GY-8 fail; the PR-base copy of this suite fails 7/11 on the base tree here, so the checkout's `guard-yield.sh` (unchanged by the PR) is not the PR's base version — environment, unverified. The classifier library itself resolves the GY-3 row to `nonexec` under `set -euo pipefail` |
| `tests/unit/golden-path-c8-verdict-trailer.bats` | 32/33 pass | #23 fails identically on the base tree (golden-path.sh version) |
| `tests/fixtures/fence-corpus/run-corpus.sh` | benign 89/89, dangerous 142/142, residual 0/5, p95 76 ms | knob-off replay fails the FR-6 rows by design |
| `tools/check-knob-readers.sh` | pass | 9 keys, no direct reads |
| kernel header hash (`marker-utils.sh verify_hash`) | VALID | 9,189 B, under the new 9,445 B cap |

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| Report each defect it introduces with file and line | Done | two HIGH, eight observations above |
| Merge verdict | Fail | CHANGES_REQUIRED: floor-fence bypass (§1) and `derive` inert on jq 1.6 (§2) |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [ ] Input validation and sanitization present — heredoc classifier's same-command execution detection is incomplete (Changes Required §1)
- [x] Authentication/authorization correct — implement-gate sanctions behave per the matrix (IG-24..33 pass); marker forgeability is a documented gap
- [x] No SQL/XSS injection vulnerabilities — n/a (shell); jq programs take values through `--arg/--argjson`
- [x] Dependencies secure — jq/yq only; a jq ≥ 1.7 dependency is introduced silently (§2)
- [x] Error messages don't leak sensitive data — paths are control-stripped and cut to 256 bytes in the gate

---

## Code Quality Summary

**Strengths:**
- The implement-gate rewrite is tighten-only end to end, with a full mode × claims × write × sanction × cache matrix test that passes.
- `profile-lib.sh` resolves explicit-false correctly, caches atomically, and refuses floor keys; `check-knob-readers.sh` keeps readers honest.
- `generate-constraints.sh` prunes the optional table deterministically and `lint-invariants.sh` enforces presence both ways.
- The fence classifier is Bash 3.2 compatible, fail-closed on every parse failure, and keeps the fence's p95 under 80 ms.

**Areas for Improvement:**
- The classifier's "same command" execution model needs to be as conservative as its header parsing (any interpreter/wrapper later in the command → full scan).
- New jq programs must stay inside the jq 1.6 dialect or the framework must declare and check a floor.
- `run-checkpoint.sh` grew from 100 to 540 lines with 300-line jq programs embedded in strings; SIMPLICITY[shrink]: move `JQ_DEFS` and the per-sprint program into `.claude/scripts/lib/*.jq` files loaded with `-f`/`-L` so they can be unit-tested and linted. `net: -40 lines possible`.

---

## Next Steps

1. Fix the classifier's same-command execution detection and keyword stripping; add the six corpus rows.
2. Fix the jq 1.6 incompatibilities in `run-checkpoint.sh` (or declare and check a jq floor); run the derive and record-round suites on jq 1.6.
3. Address the observations as time allows (exec-flag whitelist, hook latency, task key).
4. Update the report in `grimoires/loa/a2a/sprint-1/reviewer.md` with an AC walkthrough.
5. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":3,"low":5},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-23T03:27:00Z"} -->
