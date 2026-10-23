# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-23
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)

---

## Overall Assessment

The PR (cycle-129 sprint-256, 68 files) delivers five things: implement-gate modes, the file-authoritative run position (`run-checkpoint.sh derive` / `record-round` / `mark`), the per-task surgical-diff hook, the `loa.profile` resolver, and the fail-closed heredoc consumer classifier in the Bash fence. The design is sound, the test matrices are thorough (implement-gate IG-24 to IG-33, profile-lib PL-1 to PL-17, corpus rows B79 to D142 all pass here), and the documentation (hooks-reference, state-schemas, the example config) is updated in step.

Verification method: the PR head tree was replayed in a scratch root with the PR's own bats suites, the fence corpus, and hand-built probes run through both the base and the head fence hook. Several defects are reproduced by execution, not inferred.

What blocks the merge:

- `run-checkpoint.sh` does not run on jq 1.6. The per-sprint jq program binds `$label`, a jq keyword, so `derive` exits 3 and every `write` prints compile errors. 18 of 23 cases in `run-checkpoint-derive.bats` fail under jq 1.6; with only that identifier renamed, 21 of 22 pass. A second jq-1.6 trap (`jq -e` on empty input exits 0) breaks `record-round` and `derive` on any feedback file without a trailer (RCR-7 and RCD-3 fail). The repository otherwise keeps bash 3.2 compatibility, so a silent jq 1.7 floor is a regression in posture; either pin the floor explicitly or write the two lines portably.
- `derive --write` creates `.run/circuit-breaker.json` without the schema skeleton when none exists, so the timeout trigger can never fire for that run.
- The heredoc classifier opens three bypasses that the base fence caught: a same-command execution whose target is named inside a quoted argument or a substitution (`sh -c 'bash x'`, `bash $(echo x)`), and an executable destination spelled with dot components, reached through a `cd` on the same command, or living in `.husky/`. Each is reproduced below as base BLOCK, head ALLOW. The cross-model dissent found the `.git/./hooks` variant independently (DISS-001, BLOCKING).
- No CHANGELOG entry accompanies the default flips (guardrails off, new `implement_gate`, `loa.profile`, `run_mode.file_authoritative`), and the implementation report carries no `## AC Verification` section.

The karpathy hook's per-task key is the last CLOSED bead, so every write is attributed to the previous task; the summary the review's SURGICAL axis reads names the wrong task. Non-blocking, recorded under Observations with the other medium and low items.

Karpathy: `SURGICAL:` the diff is scoped to its five features; `SIMPLICITY:` the classifier is 650 lines of bash parsing inside a PreToolUse hook and its per-character tokenizer is 35× slower than the base hook on a long line (Observations); `GOAL-DRIVEN:` every feature ships a runnable check, but the derive suite was evidently run only on jq 1.7.

Fast-gate parity: shell-only change, no formatter or type checker applies; shellcheck is not available in this environment and its run is not recorded in the report.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Portability: run-checkpoint.sh fails on jq 1.6

- **HIGH** (confidence: high) `head/.claude/scripts/run-checkpoint.sh:378` — the per-sprint jq program is invoked with `--arg label "$label"` and reads `$label`; `label` is a jq keyword, and jq 1.6 rejects the program with `unexpected label, expecting IDENT or __loc__`, so `derive` exits 3 and never writes a derived cache or breaker.
**File:** `head/.claude/scripts/run-checkpoint.sh:378` (also `:380`, `:389`)
**Issue:** Reproduced with jq-1.6: `derive --root R --json` prints two compile errors and exits 3; `write --sprint … --phase …` prints the same errors plus `jq: invalid JSON text passed to --argjson` three times and the misleading line `run-checkpoint: …/sprint-plan-state.json is not valid JSON — not written` (the file is valid; `$facts` is empty), then returns 0 with no `derived_at`. Under jq 1.6, 18 of the 23 `run-checkpoint-derive.bats` cases fail; renaming the binding to `$lbl` in a scratch copy makes 21 of 22 pass.
**Why This Matters:** FR-5 is dead on jq 1.6 (the Debian 12 default): the `/loa` Run line, run-resume step 0a, `mark`, and the implement gate's "known position" never see a derived cache. The failure is noisy on every checkpoint but never fatal, so a run keeps going with stale caches while printing jq errors.
**Required Fix:** Rename the binding (for example `--arg lbl "$label"` and `$lbl` inside the program). If jq ≥ 1.7 is intended as the floor, state it in the script header and the prerequisites, and have the script check `jq --version` once.

- **HIGH** (confidence: high) `head/.claude/scripts/run-checkpoint.sh:226` — `jq -e 'type == "object"' <<<"$pj" || pj='{}'` relies on `jq -e` failing on empty input; jq 1.6 exits 0 on empty input, so for a feedback file without a trailer `pj` stays empty and the following `--argjson p "$pj"` (`:232`) aborts `fb_parse`.
**File:** `head/.claude/scripts/run-checkpoint.sh:226` (same pattern at `:223` for `$vj`)
**Issue:** Reproduced: `record-round --gate review --file <no-trailer file>` prints `jq: invalid JSON text passed to --argjson` and exits 2; `derive` hits the same path for any sprint with legacy feedback. RCR-7 and RCD-3 fail for this reason even after the `$label` rename. The repository's own shell rule (`.claude/rules/shell-conventions.md`, "JSON Construction Safety") requires validating a value before `--argjson`.
**Why This Matters:** The no-trailer fallback is an explicit feature of D-4.6 ("no trailer: md5 of the first 50 lines"); on jq 1.6 it crashes instead, and `record-round` returning 2 mid-loop leaves the breaker unrecorded.
**Required Fix:** Test emptiness before the jq call: `[[ -n "$pj" ]] && jq -e 'type == "object"' <<<"$pj" >/dev/null 2>&1 || pj='{}'`, and the same for `$vj`.

### 2. Functionality: derive creates a breaker without its schema

- **HIGH** (confidence: high) `head/.claude/scripts/run-checkpoint.sh:456` — `derive --write` calls `atomic_update "$breaker"` on a repo with no breaker file; `atomic_update` feeds `{}` to `merge_breaker`, whose fallback (`:295`, `if type == "object" then . else skeleton`) accepts `{}` as an object, so the written breaker has no `threshold`, `limit`, `timeout.started` or `limit_hours`.
**File:** `head/.claude/scripts/run-checkpoint.sh:456` and `:295`
**Issue:** Reproduced (with the `$label` rename applied): the breaker on disk after `derive --write` is `{"triggers":{"cycle_count":{"current":1},"same_issue":{"count":1,"last_hash":…},"no_progress":{…}},"state":"CLOSED"}`. The next `record-round` prints `cycle 2/null, same_issue 2/null, no_progress 1/null`, and the timeout trigger (`:506`, `$start` is null) can never fire. The in-memory report shows the skeleton because `$bcache` is `null` there, so `--json` hides the defect. `record-round` itself guards this correctly (`:496`, `(.triggers | type) == "object"`), and RCR-7 pins it; `derive` has no such test.
**Why This Matters:** Any run whose first breaker write comes from `derive` (a `mark` or `write` before the run-mode init step, a direct `/implement` with a leftover cache) runs with the 8-hour timeout silently disabled and prints `null` limits.
**Required Fix:** Use the same guard as `record-round` in `merge_breaker` (`if type == "object" and (.triggers | type) == "object" then . else skeleton($th; $ts) end`), or have `atomic_update` feed `null` instead of `{}` when the file is absent. Add a derive case that asserts the created breaker carries the thresholds.

### 3. Security: the heredoc classifier drops bodies the base fence scanned

- **HIGH** (confidence: high) `head/.claude/hooks/safety/block-destructive-bash.sh:625-626` — `_bdb_hd_same_line_exec` recognises the heredoc's target only as a whole token after quote stripping and `##*/`; a target named inside a quoted argument or a substitution is invisible, so a same-command execution is classified `nonexec` and the body is reduced to fence-verb segments.
**File:** `head/.claude/hooks/safety/block-destructive-bash.sh:625-626` (consumer: `_bdb_hd_scan_body:576-606`)
**Issue:** Probes run through the base and head hooks (0 = allow, 2 = block):
```
cat > x <<'EOF'            cat > x <<'EOF'            cat > x <<'EOF'
echo $(rm -rf src)         echo $(rm -rf src)         echo $(rm -rf src)
EOF                        EOF                        EOF
sh -c 'bash x'             sh -c "bash x"             bash $(echo x)
base=2 head=0              base=2 head=0              base=2 head=0
```
`_bdb_heredoc_consumer_class` reports `nonexec` for all three. The same body with `bash x` on its own line is caught (base=2, head=2), so the quoted and substituted spellings are the gap. Under a quoted delimiter the `$(` check in `_bdb_hd_scan_body` (`:582`) is skipped by design, and `echo $(rm -rf src)` has command word `echo`, so the segment is dropped.
**Why This Matters:** This is a regression against the base fence, not a pre-existing gap: the base scanned these bodies in full and blocked. The PR's stated contract ("a target's basename appears elsewhere in the command outside the safe readers" forces the interpreter class) does not hold for the most common way to run a just-written file.
**Required Fix:** In `_bdb_hd_same_line_exec`, match the basename inside quoted tokens too (`[[ "$u" == *"$b"* ]]` after quote stripping, or tokenise the inside of a `-c` string), and treat any token holding `$(`, a backtick or `<(` on a non-body line as naming the target. Add the three probes above as `D` rows in the corpus.
**Reference:** CWE-184 (incomplete list of disallowed inputs); the fence's own posture note (hooks-reference.md:287).

- **HIGH** (confidence: high) `head/.claude/hooks/safety/block-destructive-bash.sh:311` — `_bdb_hd_exec_dest` judges the destination on its literal spelling (`_bdb_hd_re_sys` at `:190` needs `\.git/hooks(/|$)` verbatim and resolves relative paths against the hook's PWD), so `.git/./hooks/pre-commit`, a `cd .git/hooks &&` earlier on the same command, and git-hook managers outside `.git/hooks` are classified as plain files and their bodies are dropped.
**File:** `head/.claude/hooks/safety/block-destructive-bash.sh:311` (function `:303-324`; `_bdb_hd_re_sys:190`)
**Issue:** Probes (0 = allow, 2 = block):
```
tee .git/./hooks/pre-commit <<'EOF' … EOF; git commit --allow-empty -m test   base=2 head=0
cd .git/hooks && cat > pre-commit <<'EOF' … EOF                               base=2 head=0
tee .husky/pre-commit <<'EOF' … EOF                                            base=2 head=0
cat > .git/hooks/pre-commit <<'EOF' … EOF                                      base=0 head=2
```
(body `echo $(rm -rf src)` in each). The first row is the dissent's DISS-001 (BLOCKING, gpt-5.5-pro), confirmed here; in that scenario the commit on the same command runs the overwritten hook. The last row shows the check works on the canonical spelling, which makes the first three bypasses rather than omissions.
**Why This Matters:** The design treats `.git/hooks` as executable content precisely because git runs it later; a path-spelling or `cd` variant defeats that with no change in effect. The base fence blocked all three.
**Required Fix:** Normalise the destination before matching (collapse `./`, `../`, repeated slashes; resolve against a `cd` found earlier in the same statement list, or treat any heredoc statement preceded by `cd` as interpreter-class), and add `.husky/`, `.git-hooks/`, `.pre-commit-config.yaml` and `.github/workflows/` to the executable-destination set. DISS-C-003's point about case-insensitive filesystems (macOS, which the bash 3.2 target implies) belongs to the same normalisation step.
**Reference:** CWE-22 (path equivalence), CWE-184.

### 4. Documentation and report gates

- **HIGH** (confidence: high) `head/.loa.config.yaml.example:1358` — the PR flips `guardrails.input.enabled` and `guardrails.danger_level.enforce` (`:1404`) to `false` by default, adds `loa.profile` (`:33`), `implement_gate` (`:636`), `run_mode.file_authoritative` (`:582`) and `destructive_command_guard.heredoc_classifier` (`:1245`), and none of the 68 touched files is `CHANGELOG.md`; the implementation report (`pr/PR.md`) is a one-line description with no `## AC Verification` section.
**File:** `head/.loa.config.yaml.example:1358`
**Issue:** The reviewing-code skill's documentation gate requires a CHANGELOG entry per task and an `## AC Verification` walkthrough in the report; both are absent. The dissent's DISS-C-001 makes the operational point: an installation without an explicit key loses danger-level enforcement and input guardrails on upgrade, and the only notice is a comment inside the example file.
**Why This Matters:** Default flips of two safety knobs and three new config surfaces without a changelog line is exactly the silent behaviour change the gate exists to catch.
**Required Fix:** Add CHANGELOG entries for the five features, naming the two default flips and the `heredoc_classifier: false` / `file_authoritative: false` rollback keys; add the `## AC Verification` section to the report with `file:line` evidence per acceptance criterion.

---

## Observations

### 1. Attribution and lifecycle

- **MEDIUM** (confidence: high) `head/.claude/hooks/quality/karpathy-surgical-diff-check.sh:131-133` — the per-task key is `.checkpoint.task` from `run-checkpoint.sh read --json`, and that field is by contract the last CLOSED bead (`head/.claude/skills/run-mode/resources/state-schemas.md:107`; `read` discards an open task). Every write made while implementing task N+1 lands in task N's file and in a summary whose `task` field names N; the review's SURGICAL axis then reads the wrong task's line count. KS-1 pins this with a fake `br` that reports every bead closed.
**Suggestion:** Key on the sprint plus the bead that beads reports `in_progress` (`get-ready-work.sh` or `br list --status in_progress`), or have `/implement` write the checkpoint with the task it is starting and let the hook accept an open task for this purpose.
**Benefit:** The summary and `.run/karpathy-surgical/<bead>.jsonl` name the task whose lines they count.

- **MEDIUM** (confidence: medium) `head/.claude/hooks/compliance/implement-gate.sh:550` — the implementing-skill marker sanctions for 7200 s from `started_at` and nothing re-marks it; `implementing-tasks/SKILL.md:229` marks at the start and unmarks at the end only. A direct `/implement` longer than two hours under `mode: deny` with a known position is denied mid-sprint; under `ask` it starts asking.
**Suggestion:** Re-mark after each `br close` (the skill already checkpoints there), or have the gate accept a marker whose `started_at` is older when `.run/implement-active.json` itself was modified within the window.
**Benefit:** Long sprints do not degrade into asks or denials without an operator present.

### 2. Performance

- **MEDIUM** (confidence: high) `head/.claude/hooks/safety/block-destructive-bash.sh:232` — `_bdb_hd_tokenize` walks every character of every non-body line with `${s:i:1}`, and `_bdb_hd_ctx_bad` runs it on each non-heredoc line. Measured here: a command holding one 20 KB line plus a three-line heredoc takes 1092 ms in the head hook against 30 ms in the base hook (a plain heredoc stays at 33 ms). The fence corpus p95 is 86 ms in this environment against the documented budget of p95 < 80 ms (`hooks-reference.md:287`); the knob-off replay measures 68 ms. DISS-C-004 raised the locale point; the hook does run under `LC_ALL=C`, so the cost is linear, but about 50 µs per character.
**Suggestion:** Skip `_bdb_hd_ctx_bad` for lines that hold none of `( ) { } | & ; <<` (a glob test before tokenising), and cap tokenised line length (treat longer lines as interpreter-class, which is the fail-closed direction).
**Benefit:** Keeps the PreToolUse latency budget on commands that embed large JSON or long one-liners.

### 3. Complexity

- **MEDIUM** (confidence: high) `head/.claude/hooks/safety/block-destructive-bash.sh:329` — `_bdb_hd_member` runs to about 140 lines, `_bdb_heredoc_scrub` (`:644`) to about 90, and `cmd_derive` (`head/.claude/scripts/run-checkpoint.sh:331`) to about 145, all over the 50-line threshold. The header block comments justify the grammar and the decision table, so this is noted rather than blocked; the allowlist arms of `_bdb_hd_member` could be table-driven (command → accepted flags → stdin marker) at a saving of roughly 60 lines. `SIMPLICITY[shrink]`, net: -60 lines possible.

### 4. Minor

- **LOW** (confidence: high) `head/.claude/scripts/loa-status.sh:1019` — every `/loa` runs a full `derive` (two `verdict-derive.sh` calls and one `git log` per sprint of the active cycle). Fine for small cycles; worth a `--quick` path or a cache-age check before the status line grows slow.
- **LOW** (confidence: high) `head/.claude/hooks/quality/karpathy-surgical-diff-check.sh:131` — every Write/Edit now forks `run-checkpoint.sh read --json`, which forks `br show` whenever a task is named, after the old perf caches were removed; the PR records no latency measurement for the PostToolUse path.
- **LOW** (confidence: medium) `head/.claude/hooks/compliance/implement-gate.sh:510` — `_ig_derived_ok` also bounds the ask-mode sanction (DISS-C-005): a RUNNING cache whose `derived_at` is older than `run_mode.stale_hours` stops sanctioning even with fresh `last_activity`. Each checkpoint `write` re-derives, so a live run refreshes it per phase, but a single phase longer than 12 h would start asking; worth a sentence in hooks-reference.
- **LOW** (confidence: high) `head/.claude/scripts/run-checkpoint.sh:517` — for an inconsistent APPROVED trailer `record-round` correctly counts the round as findings but records and prints `verdict: APPROVED` (`recorded: audit APPROVED — cycle 1/20 …`), which reads as a contradiction in the log.

---

## Cross-Model Observations

Two voices completed (`gpt-5.5-pro` primary, `claude-headless` companion, `counted_as: independent_voice`). DISS-001 (BLOCKING) is reproduced and folded into Changes Required §3. The companion's advisory findings:

- DISS-C-001 (default flip of the two guardrail keys without migration): valid operationally; covered by Changes Required §4 (CHANGELOG) — the flip itself is DEC-0161 and intentional.
- DISS-C-002 (`danger-level-enforcer.sh` reads the knob from a different config than `CONFIG_FILE`): not a defect — `PROJECT_ROOT` there is derived from the script's own location (`head/.claude/scripts/danger-level-enforcer.sh:24`), the same root `profile-lib.sh` resolves, so the two reads agree; the unguarded `source` at `:138` is acceptable because the lib ships in the same change.
- DISS-C-003 (case-insensitive filesystems, `cd` before the heredoc): the `cd` point is confirmed and folded into §3; the case point is noted there as part of the normalisation fix.
- DISS-C-004 (O(n²) tokenizer in a UTF-8 locale): the locale claim is wrong for the hook path (`export LC_ALL=C` precedes the call site), but the linear per-character cost is real and measured — Observations §2.
- DISS-C-005 (`derived_at` bound in ask mode): recorded as a LOW observation.

## Rejected dissent payloads

None: `metadata.rejected_summary` is empty and the sidecar `adversarial-rejected-review.jsonl` beside the envelope holds no rows.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | the seven HIGH items above; `## AC Verification` in the report |

---

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":7,"medium":4,"low":4},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-23T06:20:00Z"} -->
