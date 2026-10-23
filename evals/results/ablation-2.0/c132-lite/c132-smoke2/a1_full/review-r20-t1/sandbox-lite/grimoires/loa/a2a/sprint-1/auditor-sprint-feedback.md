# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Change under audit:** `pr/head.diff`, cycle-129 sprint-256, 68 files

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

The PR rebuilds three safety controls at once: the Bash fence's heredoc handling, the implement gate's modes and sanctions, and the run position plus circuit breaker derived from files. It also routes nine optional surfaces, including both guardrails, through a new profile resolver. The direction is sound, and the gate's mode matrix and the profile floor are carefully built. But four defects block the merge.

- **The run-position work is dead on the declared jq floor.** `derive` cannot compile on jq 1.6 and `record-round` aborts on any feedback file without a trailer, so `deny` mode is inert and the breaker stops counting.
- **The "fail-closed" heredoc classifier is fail-open in two ways the base fence was not.** Its executable-destination test and its same-command executor test compare raw text, not resolved shell words. Its body scan also drops any segment that starts with a shell keyword. A body the base fence blocked can now reach a hook or a later executor unscanned.

Below those, the guardrail readers fail open when the profile resolver cannot run. The profile cache in `.run/` silently outranks an explicit config value. And the new marker sanction extends the known `.run/` trust gap into `deny` mode.

**Prerequisite note.** The skill's Phase 0 requires `engineer-feedback.md` to say "All good". It says CHANGES_REQUIRED with three highs. The sprint instructions direct this audit to run anyway, so this report is an independent audit of the same change, not a release approval.

**Security Issues Found:**

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 4 |
| Medium | 8 |
| Low | 6 |

---

## Scope, Method and Limits

- **Read in full:** the diff of the fence classifier, `implement-gate.sh`, `run-checkpoint.sh`, `profile-lib.sh`, the surgical-diff hook, both guardrail readers, the four SessionStart readers, the constraint generator and lint, `loa-status.sh`, the knob-reader lint, the corpus runner and its 54 new rows, the example config, and the skill and reference prose.
- **Ran in a scratch copy of the head tree on this host (jq 1.6, yq 4.40.5, bash 5.2, bats 1.13):** the fence corpus with the classifier on and off, and the profile-lib, profile-floor, implement-gate, run-checkpoint-derive, record-round, lint-invariants and knob-reader checks. I also ran small probes of the profile resolver and the marker.
- **Fence bypass shapes were not re-probed by this audit.** HIGH-003 and HIGH-004 rest on code reading at the cited lines, the senior review's base-versus-head reproductions, and the cross-model dissent. Their confidence is stated accordingly.
- **Environment-dependent test failures are not counted as findings.** On this host IG-1 to IG-8 and IG-12 of `implement-gate.bats`, PF-1 of `profile-floor.bats` and the whole of `karpathy-surgical-diff.bats` fail for reasons I could not separate from the scratch tree's layout. They need a run on a full checkout before merge.
- **No `known-failures.md`, technical-debt registry, documentation-coherence reports or beads database exist here.** `br` is not installed, so the beads comment and label steps were skipped.

| Check | Result |
|-------|--------|
| Fence corpus, classifier on | benign 89/89, dangerous 142/142, p95 78 ms |
| Fence corpus, classifier off | benign 84/89, dangerous 136/142 (expected: the new rows target the classifier) |
| profile-lib.bats | 17/17 |
| profile-floor.bats | 5/7 (PF-1 environment, PF-5 see LOW-006) |
| run-checkpoint-derive.bats | 4/22 (HIGH-001, HIGH-002) |
| run-checkpoint-record-round.bats | 7/8 (RCR-7 is HIGH-002) |
| check-knob-readers.sh | clean, 9 keys |

The fence p95 of 78 ms sits just under the documented 80 ms budget on this host.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] `derive` cannot compile on jq 1.6, so the file-authoritative run position never exists

**Severity:** HIGH (confidence: high)
**File:** `head/.claude/scripts/run-checkpoint.sh:378`
**Issue:** The per-sprint jq program binds a variable named after a jq keyword:

```
sj=$(jq -nc --argjson gid "$gid" --arg label "$label" ...
```

jq 1.6 rejects `$label` at compile time. Reproduced against this repository's own ledger:

```
jq: error: syntax error, unexpected label, expecting IDENT or __loc__ ...
      {global_id: $gid, local_label: $label, status: $status,
jq: 2 compile errors
```

`derive`, `derive --write`, and the derive step that `write` and `mark` run at every checkpoint all fail. `cmd_write` swallows the error, so the cache never gains `derived_at`.
**Impact:** The implement gate's `read_position` requires a fresh `derived_at`. Without one, `implement_gate.mode: deny` always falls back to ask, so the PR's new fence never engages. The `/loa` drift line never prints. 18 of 22 derive tests fail on this host. The repository's own documented floor is jq 1.6+, so this is a supported host, not an exotic one.
**Fix:** Rename the binding, for example `--arg lbl "$label"` and `$lbl` in the program. Check the other new jq programs for keyword-named variables. Add jq 1.6 to CI or raise the documented floor everywhere it is stated.
**Reference:** CWE-758, Reliance on Undefined, Unspecified, or Implementation-Defined Behavior, https://cwe.mitre.org/data/definitions/758.html

### [HIGH-002] `fb_parse` empty-input guards never fire on jq 1.6, so the circuit breaker stops counting on legacy feedback

**Severity:** HIGH (confidence: high)
**File:** `head/.claude/scripts/run-checkpoint.sh:223` and `head/.claude/scripts/run-checkpoint.sh:226`
**Issue:** Both guards rely on `jq -e` failing on empty input:

```
jq -e 'type == "object"' >/dev/null 2>&1 <<<"$pj" || pj='{}'
```

On jq 1.6 an empty input exits 0, verified on this host. An empty `$pj`, which every trailer-less feedback file produces, then reaches `--argjson` and aborts under `set -e` with `invalid JSON text passed to --argjson`.
**Impact:** `record-round` exits 2 on a legacy feedback file and records nothing. The run-mode skill only treats exit 10 as a trip, so the breaker silently stops counting in exactly the legacy case the no-trailer hash was written for. A runaway review loop is then bounded only by the cycle count it can no longer see. RCR-7 fails on this host for this reason.
**Fix:** Test the string before calling jq, for example `{ [[ -n "$pj" ]] && jq -e 'type == "object"' <<<"$pj"; } >/dev/null 2>&1 || pj='{}'`, and the same for `$vj`. Add a legacy-feedback case that runs under jq 1.6.
**Reference:** CWE-754, Improper Check for Unusual or Exceptional Conditions, https://cwe.mitre.org/data/definitions/754.html

### [HIGH-003] Heredoc classifier: destinations are judged before canonicalisation, and keyword-prefixed body segments are dropped

**Severity:** HIGH (confidence: high; confirmed by the senior review's base-versus-head reproduction and by cross-model dissent)
**File:** `head/.claude/hooks/safety/block-destructive-bash.sh:303`, with the pattern at `head/.claude/hooks/safety/block-destructive-bash.sh:190` and the body scan at `head/.claude/hooks/safety/block-destructive-bash.sh:576`
**Issue:** `_bdb_hd_exec_dest` matches the literal target text against `_bdb_hd_re_sys`:

```
[[ "$p" =~ $_bdb_hd_re_sys || "$p" =~ $_bdb_hd_re_rc ]] && return 0
```

A path that reaches `.git/hooks/` through a `..` segment or a doubled slash does not match, so it is classed as a plain file. Separately, `_bdb_hd_scan_body` keeps a segment only when its command word is a fence verb. A segment whose word is a shell keyword such as `then` or `do` is dropped, along with the verb that follows it.
**Impact:** Together, the two defects let a hook body containing a destructive command reach `.git/hooks/` with no scan. The base fence blocked the same command and the head fence allows it. The PR title promises a "fail-closed" classifier, and this is the class it claims to close.
**Fix:**
1. Canonicalise the destination lexically before the regex: collapse `//`, drop `./`, resolve `..`. Treat any path that still holds `..` as "cannot be judged" and return 0.
2. In `_bdb_hd_scan_body`, when a segment's word is a shell keyword (`if then else elif fi for while until do done case esac function time ! {`), re-run `_bdb_hd_segword` on the rest instead of dropping it.
3. Add corpus rows for both shapes.

**Reference:** CWE-180, Incorrect Behavior Order: Validate Before Canonicalize, https://cwe.mitre.org/data/definitions/180.html

### [HIGH-004] Heredoc classifier: the same-command executor check compares raw tokens, not resolved shell words

**Severity:** HIGH (confidence: medium; raised by the cross-model dissent as DISS-001 at confidence 0.97 and by the senior review as Observation §1; derived here from the code, not re-probed)
**File:** `head/.claude/hooks/safety/block-destructive-bash.sh:608`
**Issue:** `_bdb_hd_same_line_exec` decides whether a plain-file target is executed later in the same command. It strips quotes and the directory from each token and tests string equality with the target's basename:

```
u="${_bdb_hd_tok[c]}"; u="${u//[\"\']/}"; u="${u##*/}"
[[ "$u" == "$b" ]] && seg_has=1
```

Backslash escapes, globs, brace expansion, parameter expansion and command substitution are not resolved. An executor token that bash resolves to the target therefore does not match. The heredoc stays `nonexec`, and with HIGH-003's keyword drop its body is never scanned.
**Impact:** Write a body to a harmless-looking file and run it later in the same Bash call, and the fence will not see it. The PR's header says a later command in the same call is covered. It is not, for any executor word that is not spelled literally. The base fence scanned the whole command and blocked it.
**Fix:** Fail closed. If any token on another line contains a backslash, a glob character, `$`, a backtick or `<(`, and that line is not a safe reader, treat the heredoc as interpreter class. Do not try to emulate word expansion. Use a substring test on the basename rather than equality as a second net.
**Reference:** CWE-184, Incomplete List of Disallowed Inputs, https://cwe.mitre.org/data/definitions/184.html

---

## Medium/Low Priority Issues

### [MED-001] Body-segment verb extraction truncates at a quote, and the verb list is not tied to the rule set

- **Severity:** MEDIUM (confidence: medium; dissent DISS-C-005)
- **File:** `head/.claude/hooks/safety/block-destructive-bash.sh:565`, list at `head/.claude/hooks/safety/block-destructive-bash.sh:214`
- **Issue:** `_bdb_hd_segword` cuts the command word at its first quote character (`w="${w%%[\"\']*}"`). A verb with an embedded quote is reduced to a fragment, matches no fence verb, and its segment is dropped. `_bdb_hd_is_destructive` is also a hand-kept list. A fence rule keyed on a verb outside that list, now or in the future, never sees a non-executing heredoc body.
- **Fix:** Remove all quote characters from the word rather than truncating. If any quote remains inside the word, keep the segment. Derive the verb list from the rules, or add a lint that fails when a rule's verb is missing from it.
- **Reference:** CWE-184, https://cwe.mitre.org/data/definitions/184.html

### [MED-002] The rc/profile destination list omits files that the shell or ssh execute

- **Severity:** MEDIUM (confidence: high; senior review Observation §2, reproduced there against base)
- **File:** `head/.claude/hooks/safety/block-destructive-bash.sh:191`
- **Issue:** `_bdb_hd_re_rc` omits `.bash_aliases`, which the default Debian and Ubuntu `.bashrc` sources, and `.ssh/config`, whose `ProxyCommand` runs a shell. Appends there are classed plain and allowed. The base fence blocked them.
- **Fix:** Add `bash_aliases`, `zsh_aliases`, `ssh/config`, editor rc files and build recipe files (`Makefile`, `Justfile`) to the executable-destination patterns.
- **Reference:** CWE-184, https://cwe.mitre.org/data/definitions/184.html

### [MED-003] Guardrail readers fail open when the profile resolver cannot run

- **Severity:** MEDIUM (confidence: high; reproduced)
- **File:** `head/.claude/scripts/danger-level-enforcer.sh:141`, fallback path at `head/.claude/scripts/lib/profile-lib.sh:215`
- **Issue:** `enforce=$(loa_knob guardrails.danger_level.enforce false)` returns the caller's fallback whenever yq is missing or the config does not parse, even if the operator wrote `enforce: true`. Reproduced with a config holding `enforce: true` and yq off `PATH`: the knob printed `false`. The base read defaulted to `true` in that case. The input-guardrail include at `head/.claude/data/skill-includes/input_guardrails.md:3` has the same shape.
- **Fix:** Make `loa_knob` return a distinct status for "unresolvable". Have safety readers default on in that case, or fall back to a direct read of the explicit key.
- **Reference:** CWE-636, Not Failing Securely, https://cwe.mitre.org/data/definitions/636.html

### [MED-004] The profile cache in `.run/` overrides an explicit config value and is not a protected input

- **Severity:** MEDIUM (confidence: medium; reproduced)
- **File:** `head/.claude/scripts/lib/profile-lib.sh:227`, cache path at `head/.claude/scripts/lib/profile-lib.sh:67`
- **Issue:** The warm path answers `loa_knob` from `.run/effective-config.json` whenever the cache's `id` matches. The `id` is built from file paths, mtimes and sizes, which a writer can copy. I edited only the knob value in the cache. `guardrails.input.enabled` then read `false` although the config says `true`. The implement gate protects `.loa.config.yaml` as a trust input, but not this file.
- **Impact:** Any Bash command can silently switch off the input guardrails, danger-level enforcement, the surgical-diff warning or the retrospective. The config file stays untouched. This is the same `.run/` trust class as bead bd-taee, but it now reaches every profile key.
- **Fix:** Bind the cache id to a content hash of the three inputs, not mtime and size. Add the cache to the gate's trust-input list. Have safety readers re-read the explicit key live.
- **Reference:** CWE-807, Reliance on Untrusted Inputs in a Security Decision, https://cwe.mitre.org/data/definitions/807.html

### [MED-005] The marker sanction is forgeable from Bash and grants allow under `deny`

- **Severity:** MEDIUM (confidence: high; dissent DISS-C-001 rated HIGH)
- **File:** `head/.claude/hooks/compliance/implement-gate.sh:545`
- **Issue:** `check_implement_marker` sanctions any App-Zone write while `.run/implement-active.json` names `implement` or `bug` and is under two hours old. The file is written from Bash, which the gate does not see, so a model can sanction itself. The hook header treats `tool_input.active_skill` as tighten-only because it is model-authored. The marker is the same trust class but is allowed to grant.
- **Why not HIGH:** the hooks reference states this gap, and Bash can already write App-Zone files directly. Forging the marker adds nothing an agent could not already do through Bash. It does mean `deny` is not the boundary the example config's "a fence only in this mode" suggests.
- **Fix:** State in the example config that `deny` is a mistake-catcher for Write/Edit, not a boundary. Consider binding the marker to the session id from the hook payload.
- **Reference:** CWE-807, https://cwe.mitre.org/data/definitions/807.html

### [MED-006] The derived breaker does not reset on approval, and HALTED outranks COMPLETE

- **Severity:** MEDIUM (confidence: high; senior review Observation §3, confirmed from the code)
- **File:** `head/.claude/scripts/run-checkpoint.sh:280`, ordering at `head/.claude/scripts/run-checkpoint.sh:324`
- **Issue:** `recompute` filters out approved rounds before counting streaks (`map(select(.approved | not))`), so an approval never breaks a same-issue streak. A breaker reset made before this PR carries no `reset_at` and filters nothing. `resolve` then ranks `breaker_open` above `all_complete`. Once HIGH-001 is fixed, an upgraded in-flight run can be halted at its next checkpoint, and a finished cycle can report HALTED.
- **Fix:** Count streaks over the full ordered list and reset on an approved round. Treat a zeroed breaker without `reset_at` as reset at the newest round. Rank a derived COMPLETE above a derived OPEN.
- **Reference:** CWE-670, Always-Incorrect Control Flow Implementation, https://cwe.mitre.org/data/definitions/670.html

### [MED-007] The two-hour implement marker is never refreshed

- **Severity:** MEDIUM (confidence: high; senior review Observation §4)
- **File:** `head/.claude/hooks/compliance/implement-gate.sh:550`
- **Issue:** `_ig_within 7200 "$started"` bounds the marker. The implementing skills call `mark` once at the start and `unmark` at the end, and nothing refreshes it. Under `deny`, a direct `/implement` that runs past two hours is denied on every App-Zone write. Under `ask`, it prompts on every write.
- **Fix:** Re-run `mark` at each task boundary, or tie the window to `run_mode.stale_hours`. Log a `stale_marker` reason that names the remedy.
- **Reference:** CWE-613, Insufficient Session Expiration (here: a lifetime not tied to activity), https://cwe.mitre.org/data/definitions/613.html

### [MED-008] The surgical-diff hook and the checkpoint write are an order of magnitude slower

- **Severity:** MEDIUM (confidence: medium; senior review Observation §5)
- **File:** `head/.claude/hooks/quality/karpathy-surgical-diff-check.sh:131`
- **Issue:** Every Write/Edit now sources the profile resolver, does two knob reads, and spawns `run-checkpoint.sh read --json`. That spawn runs several jq calls and a `br show`. The review measured about 270 to 380 ms per edit against 32 ms on base. Each `run-checkpoint.sh write` now runs a full `derive`.
- **Fix:** Have `write` and `mark` drop the task key in a small file the hook reads directly. Read both knobs in one pass. Derive only on `mark`, `record-round` and phase changes.
- **Reference:** CWE-1176, Inefficient CPU Computation, https://cwe.mitre.org/data/definitions/1176.html

### [LOW-001] `mark` accepts sprint ids the gate rejects

- **Severity:** LOW (confidence: high; reproduced)
- **File:** `head/.claude/scripts/run-checkpoint.sh:89`, checked at `head/.claude/hooks/compliance/implement-gate.sh:548`
- **Issue:** `--sprint` accepts any length (`^[A-Za-z0-9._-]+$`), but the gate requires `{1,64}`. A 70-character id was marked successfully, then the gate logged `stale_marker` and asked.
- **Fix:** Apply the same `{1,64}` bound in `run-checkpoint.sh`.
- **Reference:** CWE-20, Improper Input Validation, https://cwe.mitre.org/data/definitions/20.html

### [LOW-002] An environment variable sanctions every App-Zone write in every mode

- **Severity:** LOW (confidence: medium; dissent DISS-C-002)
- **File:** `head/.claude/hooks/compliance/implement-gate.sh:590`
- **Issue:** `LOA_IMPLEMENT_GATE_OVERRIDE=1` allows any write, including under `deny`. The same PR's fence says "an environment variable can never switch the fence off". Each override write is logged, which limits the damage.
- **Fix:** Document the asymmetry next to the `deny` mode, or require the override to name the sprint it applies to.
- **Reference:** CWE-15, External Control of System or Configuration Setting, https://cwe.mitre.org/data/definitions/15.html

### [LOW-003] The classifier's rollback key is parsed only in block-style YAML

- **Severity:** LOW (confidence: medium; senior review Observation §9)
- **File:** `head/.claude/hooks/safety/block-destructive-bash.sh:733`
- **Issue:** `_bdb_heredoc_knob_on` sees `heredoc_classifier:` only as an indented line under a top-level `destructive_command_guard:`. Flow mappings and quoted keys are missed, so the classifier stays on. That direction is the looser one here, because the classifier allows more than the pre-cycle scan.
- **Fix:** When the fast parse finds the substring but no match, fall back to one yq read.
- **Reference:** CWE-20, https://cwe.mitre.org/data/definitions/20.html

### [LOW-004] The derived-cache window and the activity window disagree

- **Severity:** LOW (confidence: low; senior review Observation §10)
- **File:** `head/.claude/hooks/compliance/implement-gate.sh:483`
- **Issue:** `_ig_derived_ok` uses `run_mode.stale_hours` (12 h) while `_ig_fresh` allows 24 h of activity.
- **Fix:** Use one window, or document the difference.
- **Reference:** CWE-697, Incorrect Comparison, https://cwe.mitre.org/data/definitions/697.html

### [LOW-005] The warning still says "Session diff total" for a per-task total

- **Severity:** LOW (confidence: high; senior review Observation §7)
- **File:** `head/.claude/hooks/quality/karpathy-surgical-diff-check.sh:193`
- **Fix:** Say "Task <key> diff total" and update the test that pins the wording.
- **Reference:** CWE-1116, Inaccurate Comments, https://cwe.mitre.org/data/definitions/1116.html

### [LOW-006] PF-5 depends on a gate expression that yq 4.40 cannot evaluate

- **Severity:** LOW (confidence: medium; reproduced as a failure here)
- **File:** `head/tests/unit/profile-floor.bats:128`
- **Issue:** The test asserts that the adversarial-review gate exits 2. On yq 4.40.5 the gate's own expression errors and the gate falls through to exit 0. The new floor test therefore goes red without any floor change.
- **Fix:** Pin the yq version the test needs, or assert on the gate's decision output.
- **Reference:** CWE-758, https://cwe.mitre.org/data/definitions/758.html

---

## Observations

- **Guardrail defaults flip to off (DISS-C-003).** `standard` now resolves both guardrails to `false`. This is decision DEC-0161, explained in the example config with its evidence, and this repository's config keeps input guardrails on. It is a product decision, not counted. The fail-open part is counted as MED-003.
- **C-TEAM rows leave the kernel (DISS-C-006).** The five rules move to the agent-teams reference with an arming note, under decision DEC-0140. Teammates no longer see them unless their spawn prompt points there. It is a product decision, not counted.
- **Unbounded reason string (DISS-C-007).** Not a defect. `position_state` passes through `strip_controls`, which calls `cut_utf8_256` first (`head/.claude/hooks/compliance/implement-gate.sh:566`).
- **Speculative highs excluded.** None. The review trailer excludes none, so there is nothing to confirm.

## Cross-Model Security Observations

The dissent ran with `--diff-file pr/head.diff`. The primary voice was gpt-5.5-pro, status reviewed. The companion was claude-headless, which succeeded. The envelope is `grimoires/loa/a2a/sprint-1/adversarial-audit.json`. The dissenter's input was truncated to 14 of 68 files by its token budget, so silence on a file is not clearance.

| Id | Severity | Disposition |
|----|----------|-------------|
| DISS-001 escaped executor word plus keyword-prefixed segment | HIGH | Counted as HIGH-004; the keyword half is in HIGH-003 |
| DISS-C-001 marker forgeable from Bash | HIGH | Counted as MED-005; demoted because the gap is documented and Bash already reaches the App Zone |
| DISS-C-002 override environment variable | MEDIUM | Counted as LOW-002 |
| DISS-C-003 guardrails default off, fail-open lib | MEDIUM | Fail-open counted as MED-003; the default flip is an observation |
| DISS-C-004 globs, expansions and `cd` in the executor and destination checks | MEDIUM | Folded into HIGH-004 |
| DISS-C-005 hard-coded verb list, quote truncation | MEDIUM | Counted as MED-001 |
| DISS-C-006 C-TEAM removal | MEDIUM | Observation; product decision DEC-0140 |
| DISS-C-007 reason string length | LOW | Dismissed; the value is already cut to 256 bytes |

## Rejected dissent payloads

None. The envelope's `metadata.rejected_summary` is empty and `adversarial-rejected-audit.jsonl` holds no rows.

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added
- [ ] Input validation on all new entry points: the fence destination and executor checks (HIGH-003, HIGH-004) and the marker id (LOW-001)
- [ ] Authorization decisions trust only protected inputs: the profile cache (MED-004) and the marker (MED-005)
- [ ] No injection paths: fence regressions versus base (HIGH-003, HIGH-004, MED-001, MED-002)
- [x] Error handling does not leak information: paths and claims are control-stripped and cut to 256 bytes
- [ ] Security controls fail safe: the guardrail readers (MED-003) and the breaker on jq 1.6 (HIGH-002)
- [ ] Tests cover security paths on the supported toolchain: the derive suites fail on jq 1.6 (HIGH-001)

## Rubric Scores

| Dimension | Score | Basis |
|-----------|-------|-------|
| SEC-IV Input validation | 3 | Careful tokenizer and allowlists, but no canonicalisation before decisions (HIGH-003, HIGH-004) |
| SEC-AZ Authorization | 3 | Tighten-only claims done right; sanctions trust Bash-writable files (MED-004, MED-005) |
| SEC-IN Injection prevention | 3 | Corpus green, yet regressions versus base on executable destinations and later executors |
| SEC-AV Availability and resilience | 2 | The breaker and the run position do not run on jq 1.6 (HIGH-001, HIGH-002) |
| Code quality | 4 | Well commented, well tested matrix, atomic writes under locks |

---

## Next Steps

1. Fix HIGH-001 and HIGH-002, and run every new suite on jq 1.6 and yq 4.40.
2. Fix HIGH-003 and HIGH-004 by failing closed: canonicalise destinations, keep keyword-prefixed segments, and treat any non-literal executor word as interpreter class. Add corpus rows for each shape.
3. Decide MED-003 and MED-004 before any profile other than `standard` ships, and MED-005 to MED-007 before this repository switches to `deny`.
4. Run `/implement sprint-1` for the fixes, then `/review-sprint sprint-1` and `/audit-sprint sprint-1` again.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":4,"medium":8,"low":6},"sprint_id":"sprint-1","ts":"2026-10-21T11:45:00Z"} -->
