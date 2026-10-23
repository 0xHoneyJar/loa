# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)
**Change under review:** pr/head.diff — "feat(cycle-129): sprint-256 — inert controls repaired or retired, file-authoritative run position, fail-closed heredoc classifier, profiles, prose-diet fallback" (68 files)

---

## Overall Assessment

This is a large, well-tested sprint and most of it holds up under execution, not just reading. On a copy of the head tree (bats 1.x, jq 1.6 and jq 1.7.1, mikefarah yq v4.40.5):

- Fence corpus (`tests/fixtures/fence-corpus/run-corpus.sh`): benign 89/89, dangerous 142/142 with the classifier on; knob-off reproduces exactly the six pre-change misses the corpus documents (D122, D123, D127, D131, D136, D141) plus the new benign row B88.
- `profile-lib.bats` 17/17, `lint-invariants.bats` 9/9 (including the lint self-test), `karpathy-surgical-diff.bats` 11/11, `karpathy-surgical-diff-hook.bats` 6/6, `karpathy-trajectory-event.bats` 4/4, `prompt-budget.bats` 9/10 (PB-8 needs CI sentinel fixtures not in the PR), `skill-capabilities.bats` 42/43 (the one failure is a pre-existing agent-types case), `implement-gate.bats` IG-24…IG-33 (the full mode × claims × sanction × cache matrix) all pass; IG-1…IG-8/IG-12 need `tests/fixtures/pretooluse-payloads/`, which is outside the PR.
- `run-checkpoint-derive.bats` 22/22 and `run-checkpoint-record-round.bats` 8/8 pass on jq 1.7.1; on jq 1.6 nineteen of those thirty cases fail (see Changes Required / Observations).
- `generate-skill-includes.sh --check`, `validate-constraints.sh`, `validate-skill-capabilities.sh` (37/37), `tools/check-knob-readers.sh` and `tools/check-prompt-budget.sh` are clean on the head tree; `CLAUDE.loa.md` is 9,189 B under the new 9,445 B cap and its header hash verifies.

One finding blocks the merge. The "fail-closed" heredoc classifier (`block-destructive-bash.sh`) fails open for a shape the base fence blocks: a heredoc written to a plain file and then executed in the same command through `$(cat f)`, `<(cat f)` or `bash -c "$(cat f)"`. Both cross-model dissent voices found it independently (DISS-001, DISS-C-001) and I reproduced it against the base and head hooks: base blocks (FR-SZ2-COPY), head allows, head with `heredoc_classifier: false` blocks again. The remaining findings are medium (two jq-1.6 portability failures in `run-checkpoint.sh`, a 10× latency increase in the per-write karpathy hook) and low.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Security — heredoc classifier drops a body that the same command executes

- **HIGH** (confidence: high) `head/.claude/hooks/safety/block-destructive-bash.sh:625` — `_bdb_hd_same_line_exec` compares each token's quote-stripped basename to the heredoc target literally, so a target consumed inside a substitution is never matched: `eval "$(cat n)"` tokenises as one word whose stripped form `$(cat n)` ≠ `n`, and `source <(cat n)` splits at `(`/`)` into a segment `cat n` whose command word `cat` is a safe reader. The heredoc stays `nonexec`, `_bdb_hd_scan_body` (`head/.claude/hooks/safety/block-destructive-bash.sh:593`) keeps only segments whose command word is on the fence-verb list (`head/.claude/hooks/safety/block-destructive-bash.sh:216`), and `cp`/`mv`/`ln`/`tee`/`sed -i` are not on it. The System-Zone write in the body disappears before the FR-SZ rules run.

**File:** `head/.claude/hooks/safety/block-destructive-bash.sh:608-631` (`_bdb_hd_same_line_exec`), `:576-604` (`_bdb_hd_scan_body`), `:214-219` (`_bdb_hd_is_destructive`)
**Issue:** Reproduced with the head hook (`LOA_REPO_ROOT` set, default knob) against the base hook from `pr/base/`:

```text
cat > n <<'EOF'
cp evil.sh .claude/hooks/x.sh
EOF
source <(cat n)            base: exit 2 BLOCKED [FR-SZ2-COPY]   head: exit 0 (allowed)

cat > n <<'EOF'
cp evil.sh .claude/hooks/x.sh
EOF
eval "$(cat n)"            base: exit 2 BLOCKED [FR-SZ2-COPY]   head: exit 0 (allowed)

tee /tmp/p <<'EOF'
cp /tmp/r .claude/settings.json
EOF
bash -c "$(cat /tmp/p)"    base: exit 2 BLOCKED [FR-SZ2-COPY]   head: exit 0 (allowed)
```

With `destructive_command_guard.heredoc_classifier: false` the head hook blocks all three again, so this is a regression introduced by the classifier, not a pre-existing gap. The pre-change #1245 scrub only dropped a *standalone* quoted `cat` heredoc; these multi-line commands were scanned in full. The header comment's invariant ("a target's basename appears elsewhere in the command outside the safe readers → interpreter") does not hold for substitution consumers, and the "documented gap" in the header (a body executed by a *later* command) does not cover this: the execution is in the same Bash tool call.
**Why This Matters:** The fence is the only mechanical protection for `.claude/` (System Zone) writes from Bash, and the PR's own docs call the classifier fail-closed. A single tool call can now install a hook or rewrite `settings.json` through a heredoc, where the base fence refused it. CWE-693 (Protection Mechanism Failure); CWE-184 (Incomplete List of Disallowed Inputs) for the keep-list.
**Required Fix:**
1. In `_bdb_hd_same_line_exec`, before tokenising a candidate line, return 0 (interpreter) when the line contains the target basename and any of `$(`, a backtick, `<(` or `>(`; alternatively compare with substring match (`[[ "$u" == *"$b"* ]]`) whenever the token holds a substitution opener. The same `$(`/`<(` test that `_bdb_hd_ctx_bad` applies to earlier lines should apply to later lines that name the target.
2. Keep body segments for the FR-SZ verbs as well (`cp mv ln tee sed install chmod chown`), or keep any segment whose text contains `.claude/` or `.git/`, so the System-Zone rules still see a dropped body.
3. Add the three commands above to `tests/fixtures/fence-corpus/corpus.jsonl` as `expect: block` rows (and `bash <(cat n)`, `. <(cat n)`), and re-run `run-corpus.sh` with the knob on and off.

---

## Observations

### 1. Portability — `run-checkpoint.sh derive` does not compile on jq 1.6

- **MEDIUM** (confidence: high) `head/.claude/scripts/run-checkpoint.sh:378` — `--arg label "$label"` binds `$label`, and `label` is a jq keyword; jq 1.6 rejects the program (`syntax error, unexpected label, expecting IDENT or __loc__` at `head/.claude/scripts/run-checkpoint.sh:380` and `:388`). Under `set -e` the script exits 3, so `derive`, `mark` and the post-`write` refresh never produce a derived cache on jq 1.6; `write` prints the jq error on every checkpoint and returns 0. Verified: 19 of 30 `run-checkpoint-*.bats` cases fail on jq 1.6 and all 30 pass on jq 1.7.1. The repository states no jq floor, although `ledger-lib.sh` already uses `$label` in a jq program, so the fix is a rename (`--arg lbl`) or a documented jq ≥ 1.7 requirement.
**Benefit:** The file-authoritative run position (FR-5) works on Debian 12 / Ubuntu 22.04 hosts, which ship jq 1.6.

### 2. Portability — empty trailer makes `fb_parse` abort on jq 1.6

- **MEDIUM** (confidence: high) `head/.claude/scripts/run-checkpoint.sh:226` — `jq -e 'type == "object"' <<<"$pj" || pj='{}'` relies on `jq -e` exiting non-zero on *empty* input. jq 1.6 exits 0 there (1.7.1 exits 4), so for a feedback file without a `LOA-VERDICT` trailer `$pj` stays empty, `--argjson p ''` fails, `fb_parse` prints nothing and `record-round`/`derive` abort (RCR-7 reproduces: `jq: invalid JSON text passed to --argjson`). The documented no-trailer fallback hash is unreachable on jq 1.6.
**Suggestion:** Test `[[ -n "$pj" ]] &&` before the `jq -e` check (same for `$vj`).

### 3. Performance — the per-write karpathy hook is ~10× slower

- **MEDIUM** (confidence: medium) `head/.claude/hooks/quality/karpathy-surgical-diff-check.sh:131` — the PostToolUse hook now forks `run-checkpoint.sh read --json` (four jq calls plus `br show` when beads is installed) and resolves two knobs through `profile-lib.sh` (`:72-78`) on every Write/Edit/NotebookEdit. Measured on the head tree, five writes: base hook 0.14 s (~27 ms/write); head hook 1.15 s without a checkpoint (~230 ms/write) and 1.8 s with one (~360 ms/write, `run-checkpoint.sh read` alone ~145 ms). The design note explains why the state caches went, but not the cost of the new fork; a session with a few hundred edits pays a minute or more. `br show` latency (not measurable here) adds to it.
**Suggestion:** Read `.checkpoint.task`/`.checkpoint.sprint` directly from the state file with one jq (the hook only needs the key, not the beads-confirmed resume point), and read both knobs in one `loa_effective_json` call.

### 4. Classifier — shell keywords hide fence verbs in a kept body (cross-model DISS-C-002)

- **LOW** (confidence: high) `head/.claude/hooks/safety/block-destructive-bash.sh:545-547` — `_bdb_hd_segword` strips wrappers but not shell keywords, so a body segment `do rm -rf "$d"` or `then git push --force` yields `_hd_w=do`/`then`, which is neither destructive nor interpreter, and the segment is dropped. Only exploitable together with finding 1 (or the documented later-execution gap), since a genuinely non-executing body is not run.
**Suggestion:** Skip `if then else elif do while until for case select function time` as prefixes in `_bdb_hd_segword`, or set `_hd_full=1` when a segment starts with a shell keyword.

### 5. Classifier — knob comment is wrong; config path falls back to the cwd (cross-model DISS-C-004)

- **LOW** (confidence: high) `head/.claude/hooks/safety/block-destructive-bash.sh:731-736` — the comment says turning `heredoc_classifier` off "only tightens", but knob-off restores the #1245 scrub, which the corpus shows misses D122, D123, D127, D131, D136 and D141 that the classifier catches (and, per finding 1, catches three shapes the classifier misses). The knob file is `${LOA_REPO_ROOT:-${CLAUDE_PROJECT_DIR:-.}}/.loa.config.yaml`; the `.` fallback follows the process cwd, the same MED-001 concern `implement-gate.sh` documents.
**Suggestion:** Correct the comment (the knob is a rollback, not a tightening) and resolve the root from `BASH_SOURCE` as the implement gate does.

### 6. Classifier — unnormalised paths escape `_bdb_hd_exec_dest` (cross-model DISS-C-003)

- **LOW** (confidence: medium) `head/.claude/hooks/safety/block-destructive-bash.sh:309-322` — `.claude//hooks/x`, `.git/./hooks/pre-commit` and `./x` with `.` on PATH are matched literally against `_bdb_hd_re_sys` and the PATH loop, so they are not recognised as executable destinations. The header line still reaches the FR-SZ rules, so this is hardening rather than a direct bypass.
**Suggestion:** Collapse `//` and `/./` and resolve `..` before matching; add corpus rows.

### 7. Portability — GNU-only alternation in the legacy hash

- **LOW** (confidence: low) `head/.claude/scripts/run-checkpoint.sh:230` — `grep -A 100 "## Findings\|## Issues\|## Changes Required"` uses GNU BRE `\|`; the script otherwise caters to macOS (`md5 -q`, no `flock`). On BSD grep the fallback hash is computed over nothing.
**Suggestion:** `grep -E -A 100 "## Findings|## Issues|## Changes Required"`.

### 8. Tests — guard-yield expectation disagrees with the register in this checkout

- **LOW** (confidence: low) `head/tests/unit/guard-yield.bats:34` — the FR-SZ2-REDIR row is now a complete heredoc and GY-3 (`:85`) expects it to count as a likely false positive, but `guard-yield.sh` in this checkout excludes System-Zone rows from the heredoc heuristic ("sprint-256 audit MEDIUM-A2"), so GY-1, GY-3 and GY-8 fail here. `guard-yield.sh` is not in the PR and appears to post-date it, so this could not be verified either way; confirm the suite is green in CI.

### 9. Tests — PF-5 depends on the adversarial gate's yq flavour

- **LOW** (confidence: low) `head/tests/unit/profile-floor.bats:136-141` — the case expects `adversarial-review-gate.sh` to exit 2; with mikefarah yq v4 the gate's own `yq -r '... | tostring | sub(...)'` expression errors, `code_review_enabled` reads false and the gate exits 0, so PF-5 fails in this environment. The gate is outside the PR; noting it so the floor pin is confirmed in CI.

### 10. Report hygiene

- **LOW** (confidence: high) `grimoires/loa/a2a/sprint-1/reviewer.md:1-4` — the implementation report is the PR title and a file count: no `## AC Verification` walkthrough, no per-task evidence, no test-run summary, and the PR touches no CHANGELOG. The sprint plan for this review defines the task as the diff itself, so I did not apply the automatic CHANGES_REQUIRED rule for a missing AC section, but the next round's report should carry the AC table and the commands run.

### 11. Cross-model advisory — deny with a stale RUNNING cache (DISS-C-006)

- **LOW** (confidence: low) `head/.claude/hooks/compliance/implement-gate.sh:628-634` — under `deny`, a cache with `.state: RUNNING`, a fresh `derived_at` but a `last_activity` older than 24 h denies with the reason "no active implementation run (derived position: RUNNING)". In the shipped flow `write` stamps both fields together and `derive` turns a >12 h-stale run into INTERRUPTED, so the shape needs a hand-edited cache; worth a clearer reason or an `ask` when the position says RUNNING.

### 12. Cross-model advisory — guardrail defaults flip off without a signal (DISS-C-007)

- **LOW** (confidence: medium) `head/.claude/scripts/danger-level-enforcer.sh:139-143`, `head/.claude/data/profiles.yaml:38-39` — installs without an explicit `guardrails.*` key move from enforced (`// true`) to the `standard` profile's `false` after this change (DEC-0161, intended). Nothing at runtime says so: the `/loa` Profile line lists explicit overrides only. A one-time notice or a Profile-line hint for the two flipped keys would make the migration visible.

### Triaged, not counted

- DISS-C-005 (a Bash-written `.run/implement-active.json` sanctions writes for two hours under `deny`) is accurate but is the documented accepted gap in `hooks-reference.md` ("the sanctions trust `.run/` files a Bash command can write, bead bd-taee"); no new finding.

---

## Rejected dissent payloads

- None: `metadata.rejected_summary` is empty (`rejected_count: 0`) and the sidecar `adversarial-rejected-review.jsonl` holds no rows.

## Cross-Model Observations

Two voices completed (`gpt-5.5-pro` answered by `codex-headless`; companion `claude-headless`, counted as an independent voice; `verdict_quality.status: APPROVED`, `consensus`). Findings and triage: DISS-001 and DISS-C-001 (BLOCKING) → reproduced, counted as the HIGH above; DISS-C-002, C-003, C-004, C-006, C-007 (ADVISORY) → Observations 4, 6, 5, 11, 12; DISS-C-005 → documented accepted gap, not counted.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | The heredoc classifier must not drop a body the same command executes (Changes Required 1) |

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| Heredoc classifier is fail-closed (FR-6) | Fail | Three shapes blocked by the base fence are allowed by the head fence (Changes Required 1); corpus 231/231 otherwise |
| File-authoritative run position (FR-5) | Pass on jq 1.7.1 | 30/30 `run-checkpoint-*.bats`; fails to compile on jq 1.6 (Observations 1, 2) |
| Implement gate modes ask/telemetry/deny + sanctions (FR-4a) | Pass | IG-24…IG-33 matrix green; deny falls back to ask on an unknown position |
| Profiles and `loa_knob` precedence (FR-9) | Pass | `profile-lib.bats` 17/17; floor keys unreachable (PF-2, PF-3, PF-4, PF-6, PF-7) |
| Per-task karpathy state and summary (D-4.3) | Pass, perf regression | 11/11 and 6/6; ~10× slower per write (Observation 3) |
| Agent Teams table retired, optional-table lint (D-4.5) | Pass | `lint-invariants.bats` 9/9; kernel 9,189 B ≤ 9,445 B |
| Pure-review skills strip Write/Edit/NotebookEdit (D-4.2) | Pass | `skill-capabilities.bats` c129-D4.2 cases green |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [ ] Input validation and sanitization present — the heredoc classifier's same-line execution check misses substitution consumers (Changes Required 1)
- [x] Authentication/authorization correct — n/a beyond the fence and gate
- [x] No SQL/XSS injection vulnerabilities — jq programs take values through `--arg`/`--argjson`; key paths validated before reaching yq
- [x] Dependencies secure (no known CVEs) — jq/yq/bash only
- [x] Error messages don't leak sensitive data — paths and claims are control-stripped and cut to 256 bytes

---

## Code Quality Summary

**Strengths:**
- Every new behaviour ships with a runnable check: the fence corpus, the implement-gate decision matrix, the profile oracle, the derive decision table; the suites run clean on jq 1.7.1.
- `profile-lib.sh` handles the yq `//`-reads-false-as-absent trap explicitly and is lint-enforced (`check-knob-readers.sh`).
- The implement gate stays fail-safe: unknown position asks, trust inputs ask in every mode, the claims modifier is tighten-only.

**Areas for Improvement:**
- The classifier's keep-list and same-line-execution check are the two places where "fail-closed" is asserted by comment rather than by construction; both need the conservative branch (Changes Required 1, Observations 4–6).
- `run-checkpoint.sh` grew from 100 to 550 lines of bash+jq; a stated jq floor (or a `jq --version` probe) would turn the portability findings into a documented requirement.

---

## Next Steps

1. Fix the heredoc classifier (Changes Required 1) and add the three bypass shapes to the fence corpus as `block` rows.
2. Rename `$label` in `cmd_derive` and guard the empty-trailer path in `fb_parse` (or declare jq ≥ 1.7).
3. Re-run `tests/fixtures/fence-corpus/run-corpus.sh`, `bats tests/unit/run-checkpoint-*.bats tests/unit/guard-yield.bats tests/unit/profile-floor.bats`, and update the report in `grimoires/loa/a2a/sprint-1/reviewer.md` with an AC Verification table.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":3,"low":9},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T15:10:00Z"} -->
