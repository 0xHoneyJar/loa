# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Scope:** `pr/head.diff` — sprint-256 (cycle-129), 68 files: the heredoc consumer classifier in `block-destructive-bash.sh`, the file-authoritative run position in `run-checkpoint.sh`, the three-mode `implement-gate.sh` with its marker sanction, the `loa.profile` resolver (`profile-lib.sh`, `profiles.yaml`), the guardrail default flip, the per-task surgical-diff hook, the C-TEAM removal from the kernel, and their tests and documentation.

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

The change moves three safety controls onto new machinery: the Bash fence now classifies heredoc consumers instead of scanning every body, the run position and circuit breaker are re-derived from files at every checkpoint, and nine optional surfaces (two of them security guardrails) resolve through a profile layer with a cache under `.run/`. The design is sound and the test matrices are large, but the shipped code fails in ways that matter for a security control. The classifier judges a write target by literal spelling and a hand-written list of executable locations, so six command shapes the base hook blocked now pass, each replayed through both hooks in scratch trees (a cron drop-in through `/tmp/../etc`, `//etc` and `/./etc`; a `package.json` script run by `npm run` in the same command; an `ssh` `ProxyCommand` appended to `~/.ssh/config` and invoked on the next line; a function-wrapped body executed through `eval "$(cat …)"`). The run-position engine does not run at all on jq 1.6 because its per-sprint program binds `$label`, a jq keyword; once that is fixed, a single trailer-less feedback file anywhere in the active cycle aborts `derive` (the empty-input guard never fires on jq 1.6), and once that is fixed too, three legacy "All good" rounds trip the derived breaker and rewrite a RUNNING run to HALTED. All three were reproduced here.

On the trust-boundary side, the new profile cache `.run/effective-config.json` is served before the configuration whenever its stat id matches. A plain write to it flipped `guardrails.input.enabled` and `guardrails.danger_level.enforce` to false in this audit while `.loa.config.yaml` still said true, and the implement gate silently allows a Write-tool write to that file while asking on a write to `.loa.config.yaml`. Both guardrail defaults also flip to off for every repository that never set them (an intentional decision, DEC-0161, but with no upgrade notice). The adversarial dissent ran with two independent voices (`gpt-5.5-pro`, companion `claude-headless`, both completed, no rejected payloads) and its two HIGH findings are confirmed and counted below.

Verification limits: the eval workspace is a later revision than both base and head and carries no `tests/` tree, so the PR's suites ran against the workspace's untouched dependencies (notably `verdict-derive.sh`, `floor.yaml`, `guard-yield.sh`, `agent-types.yaml`). Suites needing fixtures outside the PR (`pretooluse-payloads/`, `constraint-rationales-pre-diet.json`, `prompt-budget/` sentinels, `guard-origins.bats`) could not be completed; the two karpathy suites carry a redacted literal that is a bash syntax error in this snapshot and did not load. The review's prerequisite ("All good") is not met — its verdict is CHANGES REQUIRED — and this audit ran on the task's explicit instruction to proceed regardless. No `documentation-coherence-*` subagent reports exist; the touched documentation was checked by hand (two inaccuracies, counted below).

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 4 |
| Medium | 4 |
| Low | 5 |

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] Heredoc classifier drops bodies written to targets it does not recognise as executable; six base-blocked shapes now pass

**Severity:** HIGH | **Confidence:** high
**File:** `head/.claude/hooks/safety/block-destructive-bash.sh:312` (the unnormalised `/etc/` prefix test), `:190` (`_bdb_hd_re_sys`, the executable-location denylist), `:608` (`_bdb_hd_same_line_exec`), `:698` (the body reduced to `_hd_kept`)
**Issue:** `_bdb_hd_exec_dest` decides that a write target is non-executing by literal spelling: `[[ "$p" == /etc/* ]] && return 0` (`:312`) and a fixed regex of rc files, hook directories and PATH entries (`:189-190`). A path that reaches the same place through `..`, `//` or `/./`, or a file a daemon or tool executes that is not on the list (`package.json`, `~/.ssh/config`, user systemd units, `Makefile`), is classed `nonexec`; its body is cut down to segments whose first word is a fence verb (`:576-604`, `:698`) and everything else never reaches the rules. `_bdb_hd_same_line_exec` (`:608-640`) is the only guard against the same command executing that file, and it compares tokens byte-for-byte with the basename, so `eval "$(cat /tmp/x)"` (token `/tmp/x)"`), `bash ./*` and tool-mediated execution (`npm run`, `ssh`, `make`) are not recognised. Replayed through the base and head hooks in scratch trees (payload cwd set, `CLAUDE_PROJECT_DIR`/`LOA_REPO_ROOT` pinned):

| Shape | Base | Head |
|-------|------|------|
| `cat <<'EOF' \| tee /tmp/../etc/cron.d/job` + schedule line carrying `rm -rf /` | block (FR-2) | allow |
| same with `//etc/cron.d/job` | block | allow |
| same with `/./etc/cron.d/job` | block | allow |
| `cat <<'EOF' > package.json` with a `scripts` entry carrying `rm -rf /`, then `npm run x` | block | allow |
| `cat <<'EOF' >> ~/.ssh/config` with `ProxyCommand rm -rf /`, then `ssh example.com true` | block | allow |
| `cat <<'EOF' > /tmp/x` with body `f() { rm -rf /; }; f`, then `eval "$(cat /tmp/x)"` | block | allow |

The direct `/etc/cron.d/job`, the `.git/config` tee, the `.claude/hooks/` redirect and `bash -s <<EOF` stay blocked, so the classifier's lists work where they apply; the gap is everything they do not name. The header comment's "Documented gap" (`:175-176`) covers a *later* command only; these executors run in the same Bash call. The title's "fail-closed" claim and `hooks-reference.md:294` do not hold for these shapes.
**Impact:** The fence is the framework's control against routine destructive mistakes by autonomous agents (hooks-reference, "Defense-in-depth posture"). Six shapes the previous hook caught now reach the shell; three of them are the cron class the `/etc/` test was written to cover.
**Fix:** Normalise the destination before any test (collapse `.`/`..`/`//`, expand `~`, resolve against the payload `cwd`, treat an un-normalisable path as executable); add the build/task and daemon manifests (`Makefile`, `GNUmakefile`, `*.mk`, `Justfile`, `Rakefile`, `package.json`, `.mcp.json`, `Dockerfile`, `Procfile`, `*.service`, `*.timer`, `.ssh/config`, `crontab`) to `_bdb_hd_re_sys`; in `_bdb_hd_same_line_exec` return interpreter-class when a line naming the target also holds `$(`, a backtick, `<(` or `>(`, or when any later segment's command word is an interpreter, `make`, `npm`/`yarn`/`pnpm`, `just`, `ssh`, `systemctl`, `docker` or `crontab`; add the six shapes above to `tests/fixtures/fence-corpus/corpus.jsonl` as `block` rows.
**Reference:** CWE-184 Incomplete List of Disallowed Inputs — https://cwe.mitre.org/data/definitions/184.html; CWE-22 Improper Limitation of a Pathname — https://cwe.mitre.org/data/definitions/22.html. Confirmed by cross-model review (DISS-001 `gpt-5.5-pro`, DISS-C-001 `claude-headless`) and by the review's Changes Required 1.

### [HIGH-002] `run-checkpoint.sh derive` fails to compile on jq 1.6: the per-sprint program binds `$label`, a jq keyword

**Severity:** HIGH | **Confidence:** high
**File:** `head/.claude/scripts/run-checkpoint.sh:378` (`--arg label "$label"`), `:380` and `:389` (`$label` in the program)
**Issue:** `sj=$(jq -nc --argjson gid "$gid" --arg label "$label" …` (`:378`). `label` is a reserved word in jq and jq 1.6 (installed here; Debian 12, Ubuntu 22.04) rejects `$label` with `syntax error, unexpected label, expecting IDENT or __loc__`. Reproduced directly (`jq -nc --arg label x '{l: $label}'` → compile error, exit 3) and through the suite: 18 of 22 `run-checkpoint-derive.bats` cases fail in a scratch head tree with that error in `Last stderr`; renaming the binding to `lbl` in a scratch copy drops the failures to 2 (RCD-3, see HIGH-003, and RCD-R5, which needs the workspace's `loa-status.sh`). Nothing pins jq ≥ 1.7.
**Impact:** The sprint's central feature is dead on a common jq: `write` (`:174`) and `mark` (`:541`) print the jq error at every checkpoint, no cache ever carries `derived_at`, the `/loa` Run line never appears, and `implement_gate.mode: deny` degrades to ask everywhere because the position is never "known".
**Fix:** Rename the binding (`--arg lbl` / `$lbl`, as `--arg status` already does), grep the new programs for other keyword names (`label`, `import`, `include`, `def`, `reduce`, `foreach`, `try`, `catch`, `if`, `then`, `elif`, `else`, `end`, `as`, `and`, `or`, `not`), and run the derive suite under jq 1.6 in CI or pin jq ≥ 1.7 in the preflight.
**Reference:** CWE-703 Improper Check or Handling of Exceptional Conditions — https://cwe.mitre.org/data/definitions/703.html (a reliability defect in a control-plane script; no exploit path). Confirmed by the review's Changes Required 2.

### [HIGH-003] The empty-input guards never fire on jq 1.6: one trailer-less feedback file aborts `derive` and `record-round`

**Severity:** HIGH | **Confidence:** high
**File:** `head/.claude/scripts/run-checkpoint.sh:226` (`jq -e 'type == "object"' >/dev/null 2>&1 <<<"$pj" || pj='{}'`), `:223` (the same for `$vj`)
**Issue:** For a file without a `LOA-VERDICT` trailer, `tl` is empty and `pj` is empty. `jq -e` exits 0 on empty input (verified on jq 1.6: `jq -e 'type == "object"' <<< ""` → exit 0), so the fallback never runs and `fb_parse` reaches `--argjson p ""`, which jq rejects (`invalid JSON text passed to --argjson`). `fb_parse` then prints nothing, and in `cmd_derive` `--argjson rv "$rv"` (`:378`) fails under `set -e`, so the whole derive aborts. Reproduced in the scratch copy with the `$label` fix applied: RCD-3 ("legacy feedback yields no verdict") fails with exactly that error, and RCR-7 fails the same way for `record-round`. Note that `cmd_derive` parses the review and audit file of *every* sprint of the active cycle (`:370-371`), not only the active sprint's.
**Impact:** Any repository whose active cycle holds one pre-trailer `engineer-feedback.md` or `auditor-sprint-feedback.md` gets no derived position at all: the same symptoms as HIGH-002 (jq errors on every checkpoint, no `derived_at`, deny degrades to ask), and `record-round` exits 3 on a legacy file. The review counted this as medium; the demonstrated blast radius is the whole feature, so it is counted high here.
**Fix:** Test `[[ -n "$pj" ]]` (and `[[ -n "$vj" ]]`) before the `jq -e` check; make `fb_parse` emit a well-formed object on every path and have `cmd_derive` treat an empty `rv`/`au` as `{exists:false}` rather than passing it to `--argjson`.
**Reference:** CWE-703 — https://cwe.mitre.org/data/definitions/703.html; CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html. Confirmed by the review's Observation 2 (as medium).

### [HIGH-004] Legacy approved rounds are counted as repeated changes-required rounds and HALT a running run

**Severity:** HIGH | **Confidence:** high
**File:** `head/.claude/scripts/run-checkpoint.sh:280` (`map(select(.approved | not))`), `:230` (the legacy hash), `:174` and `:541` (automatic `derive --write` from `write` and `mark`)
**Issue:** `recompute` keeps every round whose `approved` is false. `fb_parse` sets `approved` from `exit_code == 0 and verdict == "APPROVED"` (`:239`), so a trailer-less "All good" file is unapproved, and its hash is the md5 of `grep -A 100 "## Findings\|## Issues\|## Changes Required"` (`:230`), which for an approval with no findings section is the md5 of the empty string (`d41d8cd98f00b204e9800998ecf8427e`). Three such files hash identically, `same` reaches 3, `merge_breaker` opens the breaker (`:303-311`) and `resolve` derives HALTED (`:324`). Reproduced in a scratch copy with the `$label` and empty-input guards patched so the code path runs: a fixture with one in-progress sprint, `engineer-feedback-r1..r3.md` reading "All good" without a trailer, a consistent APPROVED current file and a fresh RUNNING cache; `derive --json` reports `state: HALTED`, `breaker: {state: OPEN, same_issue: 3}`, and `derive --write` rewrites the cache to `HALTED` and appends `{trigger: same_issue, source: derive}` to the breaker history. The same fixture with an *inconsistent* current round after them shows a second weakness: `recompute` reports the final streak, not the maximum, so the trip depends on round order.
**Impact:** A false HALTED needs an operator and `/run-resume --reset-ice`; because `write` runs `derive --write` at every checkpoint, a repository whose active cycle holds any pre-trailer sprint halts at its first checkpoint for history that was not a failure. The same logic inflates `cycle_count` with approved rounds.
**Fix:** Exclude rounds with `trailer: false` from `recompute` (they already surface under `legacy_feedback`), or at least never let two legacy files with no findings section compare equal; take the maximum streak rather than the final one; add an RCD case with three trailer-less "All good" rounds asserting the breaker stays CLOSED.
**Reference:** CWE-682 Incorrect Calculation — https://cwe.mitre.org/data/definitions/682.html; CWE-703 — https://cwe.mitre.org/data/definitions/703.html. Confirmed by the review's Changes Required 3.

---

## Medium/Low Priority Issues

### [MED-001] The profile cache under `.run/` is served before the configuration and is not a gate trust input
- **Severity:** MEDIUM | **Confidence:** high
- **File:** `head/.claude/scripts/lib/profile-lib.sh:67` (`_LOA_PL_CACHE="$root/.run/effective-config.json"`), `:189-197` and `:230-246` (the cache served whenever `.id` matches the config's stat line); `head/.claude/hooks/compliance/implement-gate.sh:340` (the trust-input list, which names `.loa.config.yaml` but not the cache)
- **Issue:** The cache key is the three input paths plus `stat` mtime and size (`:75-84`), all readable, so a writer can produce a cache with the right id and any knob values. Demonstrated in the scratch head tree, whose `.loa.config.yaml` sets `guardrails.input.enabled: true`: after a fresh resolve, `jq '.knobs["guardrails.input.enabled"].value=false' …` written over the cache made `profile-lib.sh knob guardrails.input.enabled false` print `false` and `guardrails.danger_level.enforce` print `false`, the config untouched. `guardrails-orchestrator.sh:110` and `danger-level-enforcer.sh:141` read exactly these knobs through `loa_knob`, so the input guardrails and danger-level enforcement are switched off by a `.run/` write. The implement gate, run on a Write-tool payload for that path, exited 0 with empty stdout (silent allow) while the same payload for `.loa.config.yaml` produced the trust-input ask. Neither `hooks-reference.md` nor the example names the cache among the accepted `.run/` gaps (bd-taee).
- **Impact:** A configuration-equivalent input gains a weaker trust boundary than the configuration it mirrors; the two guardrails are defense in depth, not the fence, so the exposure is medium.
- **Fix:** Key the cache on a content hash of the three inputs (not mtime/size), or verify the cached document against the config on each read; add `.run/effective-config.json` to the gate's trust-input list and to the documented `.run/` gaps.
- **Reference:** CWE-349 Acceptance of Extraneous Untrusted Data With Trusted Data — https://cwe.mitre.org/data/definitions/349.html; CWE-284 Improper Access Control — https://cwe.mitre.org/data/definitions/284.html.

### [MED-002] `--file` outside a directory named `.run` writes the repository's own breaker and cache from the repository ledger
- **Severity:** MEDIUM | **Confidence:** high
- **File:** `head/.claude/scripts/run-checkpoint.sh:113` (`[[ "$(basename "$fdir")" == .run ]]`), `:117` (`breaker="$run_dir/circuit-breaker.json"`), `:174` (`write` runs `derive --write`)
- **Issue:** When `--file` is, say, `/tmp/x/state.json`, `fdir` is `/tmp/x`, the basename test fails, `root` stays the script's checkout and `run_dir` its `.run/`, so `write --file /tmp/x/state.json …` updates the scratch file and then `derive --write` reads the checkout's ledger and writes the checkout's `.run/circuit-breaker.json` and (through `$file`) the scratch cache from the real repository's facts. The caller believes it is working on a scratch file.
- **Impact:** Tests and ad-hoc calls can open or reset the live breaker; a live run can be halted by a scratch invocation.
- **Fix:** Derive `run_dir` from the directory of `--file` whatever its name, or refuse `derive --write` when `--file` and `run_dir` disagree.
- **Reference:** CWE-706 Use of Incorrectly-Resolved Name or Reference — https://cwe.mitre.org/data/definitions/706.html.

### [MED-003] The kept-verb list and the safe-reader list are narrower than the fence's contract
- **Severity:** MEDIUM | **Confidence:** medium
- **File:** `head/.claude/hooks/safety/block-destructive-bash.sh:214` (`_bdb_hd_is_destructive`), `:222` (`_bdb_hd_is_safe_reader`), `:538` (`_bdb_hd_segword`)
- **Issue:** `_bdb_hd_is_destructive` is described as "command words the fence's own rules match" yet omits words the rule set keys on (`sed -i`, `cp`, `mv`, `br`/`bd`, `docker`, `npm`, `make`, redirections into `.claude/`), so a `nonexec` body carrying those words is dropped before the rules run. `_bdb_hd_segword` strips wrappers, assignments and a leading paren or brace but not shell keywords, so `if :; then rm -rf /; fi`, `while :; do …; done` and `case … in *) kubectl delete ns prod;; esac` resolve to `then`/`do`/`case` and are dropped (the header-context check `_bdb_hd_ctx_bad` knows these keywords; the body scanner does not). `_bdb_hd_is_safe_reader` treats `git`, `gh`, `br`, `touch` and `mkdir` as readers although `git -c core.sshCommand=./x fetch`, `git -c alias.r='!./x' r`, `gh alias set --shell` execute or install the named file.
- **Impact:** Each is a further path by which a dropped body reaches execution once the target is executed (HIGH-001); none was replayed here, so confidence is medium.
- **Fix:** Derive the verb list from the rule table (or assert equality in `run-corpus.sh`); treat shell keywords as wrappers in `_bdb_hd_segword`; remove `git`, `gh`, `br`, `touch` and `mkdir` from the safe-reader list or inspect their arguments for `-c`, `alias`, `hooksPath`, `--shell`.
- **Reference:** CWE-184 — https://cwe.mitre.org/data/definitions/184.html. Raised by cross-model review (DISS-C-002, DISS-C-003) and the review's Observation 3.

### [MED-004] Two guardrail defaults flip to off with no migration notice, and the enforcer has no fallback when the profile library is missing
- **Severity:** MEDIUM | **Confidence:** high
- **File:** `head/.claude/data/profiles.yaml:40-41` (`standard` reads both keys `false`), `head/.claude/scripts/danger-level-enforcer.sh:138-141` (`source "$SCRIPT_DIR/lib/profile-lib.sh"` unconditionally; `loa_knob guardrails.danger_level.enforce false`), `head/.claude/scripts/guardrails-orchestrator.sh:107-110`, `head/.loa.config.yaml.example:1349-1356`
- **Issue:** Before this change an unset `guardrails.danger_level.enforce` read as true (`// true`) and the input guardrails ran unless explicitly disabled; now an unset key resolves through `standard` to false. The change is intentional and recorded (DEC-0161, D-4.4, the example comment at `:1349`), but nothing at session start or on the new `/loa` Profile line (`loa-status.sh:943-962`) tells an upgrading operator that enforcement they relied on is now off; the Profile line prints explicit overrides only. `danger-level-enforcer.sh` also sources the library with no `|| exit`/fallback, so a missing or broken `profile-lib.sh` fails the enforcer open rather than defaulting to enforce.
- **Impact:** Silent loss of two defense-in-depth controls on upgrade; an operator who audits by reading their config sees nothing changed.
- **Fix:** Print a one-time notice (session start or the Profile line) when `loa.profile` is unset and neither guardrail key is explicit; in the enforcer, `source … || { echo WARN; exit 0-with-enforce; }` or read the key directly as the fallback.
- **Reference:** CWE-1188 Initialization of a Resource with an Insecure Default — https://cwe.mitre.org/data/definitions/1188.html; CWE-636 Not Failing Securely — https://cwe.mitre.org/data/definitions/636.html. Raised by cross-model review (DISS-C-005) and the review's Observation 8.

### [LOW-001] "Turning it off only tightens" is false in both directions
- **Severity:** LOW | **Confidence:** high
- **File:** `head/.claude/hooks/safety/block-destructive-bash.sh:732`, `head/.loa.config.yaml.example:1243`
- **Issue:** `run-corpus.sh --knob-off` in the scratch head tree: 84/89 benign and 136/142 dangerous — five benign rows block (B80, B82, B85, B87, B88) and six dangerous rows pass (D122, D123, D127, D131, D136, D141) with the classifier off. The rollback key is looser in one direction and tighter in the other.
- **Fix:** Reword to "restores the pre-cycle scan" and list the FR-6 rows the pre-cycle scan misses so an operator rolling back knows what coverage they lose.
- **Reference:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html.

### [LOW-002] `_ig_within` rejects ISO timestamps with a UTC offset
- **Severity:** LOW | **Confidence:** medium
- **File:** `head/.claude/hooks/compliance/implement-gate.sh:475-480`
- **Issue:** `fromdateiso8601` parses only a trailing `Z`; a `derived_at` or `started_at` written as `+00:00` is treated as stale, so a sanction silently disappears and a deny-mode position reads unknown. Every writer in this PR uses `Z`, so no live path fails today.
- **Fix:** Normalise `+00:00`/`-00:00` to `Z` before parsing.
- **Reference:** CWE-20 Improper Input Validation — https://cwe.mitre.org/data/definitions/20.html. Raised by the review's Observation 7 (companion DISS-C-002 of the review round).

### [LOW-003] A configured `deny` degrades to `ask` silently when yq is missing or the config does not parse
- **Severity:** LOW | **Confidence:** high
- **File:** `head/.claude/hooks/compliance/implement-gate.sh:187-204`
- **Issue:** `load_gate_config` returns 0 with `gate_mode="ask"` when `yq`/`jq` are missing, the file is absent, or both yq invocations fail (a YAML parse error introduced through Bash). Nothing is logged; the audit rows simply carry `mode: ask`.
- **Fix:** Log one `compliance.mode.fallback` row naming the cause when a config file exists but the mode could not be read; consider treating an unparseable config as `deny`-with-unknown-position (ask) but say so on stderr.
- **Reference:** CWE-636 — https://cwe.mitre.org/data/definitions/636.html. Raised by cross-model review (DISS-C-007).

### [LOW-004] `LOA_AUDIT_REPLAY=1` in the hook environment tags live decisions as replay
- **Severity:** LOW | **Confidence:** medium
- **File:** `head/.claude/hooks/compliance/implement-gate.sh:214`
- **Issue:** Every row the gate writes carries `replay: true` when the variable is set; the guard register excludes replay rows from yield counts by design, so an environment the agent can influence hides real ask/deny/allow decisions from the register. The same variable exists in the fence, so this is consistent, but the gate is new fence territory under `deny`.
- **Fix:** Require a second signal (a `.run/replay-session.json` written by the replay driver, or a bats marker) before stamping rows, as the test-mode gates elsewhere do.
- **Reference:** CWE-807 Reliance on Untrusted Inputs in a Security Decision — https://cwe.mitre.org/data/definitions/807.html. Raised by cross-model review (DISS-C-008).

### [LOW-005] The surgical-diff hook forks `run-checkpoint.sh read` (and `br show`) on every Write/Edit
- **Severity:** LOW | **Confidence:** medium
- **File:** `head/.claude/hooks/quality/karpathy-surgical-diff-check.sh:131`
- **Issue:** Each counted write spawns bash plus the checkpoint reader, which runs `br show <task> --json` whenever a task checkpoint exists (`run-checkpoint.sh:179-184`). The design note (`:40-44`) says the perf caches were removed because per-task files are small; the new per-write fork is the larger cost and sits on the PostToolUse path.
- **Fix:** Read `.checkpoint.task` with one jq and skip the beads confirmation in the hook (the SURGICAL axis is advisory), or cache the resolved key keyed on the checkpoint file's mtime.
- **Reference:** CWE-405 Asymmetric Resource Consumption — https://cwe.mitre.org/data/definitions/405.html. Raised by the review's Observation 6.

---

## Cross-Model Security Observations

Two voices answered the audit dissent (`adversarial-audit.json`: primary `gpt-5.5-pro`, companion `claude-headless`, `counted_as: independent_voice`, both `succeeded`, `rejected_count: 0`). Not a degraded review.

- **DISS-001** (`gpt-5.5-pro`, HIGH) — unnormalised destinations (`.git//config` + `git status`): counted as HIGH-001, confirmed by replay with the cron and ssh shapes.
- **DISS-C-001** (`claude-headless`, HIGH) — same-command execution forms the basename check misses (`eval "$(cat x)"`, `bash <(cat x)`, `BASH_ENV=x bash`, `bash ./*`): counted as HIGH-001, the `eval "$(cat /tmp/x)"` form confirmed by replay.
- **DISS-C-002**, **DISS-C-003** (MEDIUM) — shell keywords and `br` dropped by the body scanner; `git`/`gh` as safe readers: counted as MED-003.
- **DISS-C-005** (MEDIUM) — guardrail defaults flip and the enforcer's unconditional `source`: counted as MED-004.
- **DISS-C-007**, **DISS-C-008** (LOW) — silent mode degradation and the replay stamp: counted as LOW-003 and LOW-004.
- **DISS-C-004** (MEDIUM) — the marker, the RUNNING cache and `LOA_IMPLEMENT_GATE_OVERRIDE` are all writable or settable by the agent the gate governs. Not counted: `head/.claude/loa/reference/hooks-reference.md:273` records exactly this as an accepted gap (bd-taee, "a marker and a trailer forged together with the right sprint id pass derive"), and the example documents the override as audited. Its third point (a forged cache without `derived_at` skips the `stale_hours` bound) is real but is bounded by the 24-hour `_ig_fresh` test and falls in the same accepted class.
- **DISS-C-006** (MEDIUM) — the five C-TEAM rules leave the kernel. Not counted: the rules and their rationales now live at `head/.claude/loa/reference/agent-teams-reference.md:32-45`, the three team hooks stay registered and are armed by `LOA_TEAM_MEMBER` (`:47`), and `instruction-diet-revert.bats` reads them there. The reference itself admits that unarmed they are "prose the teammate is asked to follow"; that was equally true before the move.

## Rejected dissent payloads

- none — `metadata.rejected_summary` is empty and `adversarial-rejected-audit.jsonl` holds no rows.

---

## Review demotions confirmed

The review trailer records `excluded: 0`; there are no demoted highs to confirm. `excluded_confirmed` is 0.

---

## Test and tooling evidence (scratch head tree, workspace dependencies)

| Check | Result |
|-------|--------|
| `run-corpus.sh` (classifier on) | benign 89/89, dangerous 142/142 |
| `run-corpus.sh --knob-off` | benign 84/89, dangerous 136/142 (LOW-001) |
| `run-checkpoint-derive.bats` | 18/22 fail (HIGH-002); 2/22 fail after renaming `$label` (RCD-3 = HIGH-003; RCD-R5 needs the workspace `loa-status.sh`) |
| `run-checkpoint-record-round.bats` | 7/8; RCR-7 fails with `invalid JSON text passed to --argjson` (HIGH-003) |
| `implement-gate.bats` | 24/33; the 9 failures need `tests/fixtures/pretooluse-payloads/` (absent from the PR); IG-24 to IG-33 (modes × sanctions matrix) pass |
| `profile-lib.bats` | 17/17 |
| `profile-floor.bats` | 5/7; PF-1 needs `guard-origins.bats`, PF-5 needs the PR's `adversarial-review-gate.sh` revision |
| `lint-invariants.bats`, `karpathy-trajectory-event.bats` | 9/9, 4/4 |
| `skill-capabilities.bats` | 42/43 (SC-T-AGENT-7 reads the workspace `agent-types.yaml`) |
| `prompt-budget.bats` | 9/10 (PB-8 sentinel fixtures absent); live gate: kernel 9,189 B of 9,445 B |
| `golden-path-c8-verdict-trailer.bats` | 32/33 (test 23 exercises the workspace `verdict-derive.sh`) |
| `karpathy-surgical-diff.bats`, `karpathy-surgical-diff-hook.bats` | did not load: a redacted literal (`local REDACTED-TEST-SECRET"`) is a bash syntax error in this snapshot |
| `guard-yield.bats`, `instruction-diet-revert.bats` IDR-3 | need fixtures or scripts outside the PR |
| `check-knob-readers.sh`, `validate-constraints.sh` | clean, 0 errors |

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added
- [ ] Input validation on all new entry points — the heredoc destination test does not normalise paths (HIGH-001); the profile cache is accepted on a stat match (MED-001)
- [x] Authentication/authorization — the marker sanction's trust model is documented as an accepted gap; no new privilege path beyond it
- [x] No injection via jq/yq — key paths are regex-checked before yq; jq values pass through `--arg`/`--argjson` (one `--argjson` receives an empty string, HIGH-003, a crash not an injection)
- [x] Error handling does not leak sensitive data — paths are control-stripped and cut to 256 bytes; audit rows use `jq -a`
- [ ] Tests cover security paths — the corpus holds no row for a normalised-path or same-command-executor shape; the derive suite was never run on jq 1.6

---

## Documentation audit

No `documentation-coherence-*` subagent reports exist in this workspace; the touched documentation was checked by hand. `hooks-reference.md` (gate modes, sanctions, trust inputs, the classifier section), `.loa.config.yaml.example` (profile, `run_mode.file_authoritative`/`stale_hours`, `implement_gate`, `heredoc_classifier`, the guardrail flip with its DEC-0161 rationale), `agent-teams-reference.md` (the C-TEAM rules and arming) and the run-mode resources match the code, with two exceptions counted above: the "turning it off only tightens" claim (LOW-001) and the "fail-closed" wording for the classifier (HIGH-001). The profile cache is not named as a trust input anywhere (MED-001).

---

## Next Steps

1. Fix HIGH-001 (normalise destinations, extend the executable-content list, recognise same-command executors) and add the six replayed shapes to the corpus as `block` rows.
2. Fix HIGH-002 and HIGH-003 together (rename `$label`, guard empty `pj`/`vj`), then HIGH-004 (exclude trailer-less rounds from `recompute`, take the maximum streak); run `run-checkpoint-derive.bats` and `run-checkpoint-record-round.bats` under jq 1.6 and 1.7.
3. Address MED-001 (content-hash cache key or add the cache to the trust-input list and the documented gaps) and MED-004 (upgrade notice; enforcer fallback).
4. Run `/implement sprint-1` for the fixes, then re-run `/review-sprint sprint-1` and `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":4,"medium":4,"low":5},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-22T19:58:00Z"} -->
