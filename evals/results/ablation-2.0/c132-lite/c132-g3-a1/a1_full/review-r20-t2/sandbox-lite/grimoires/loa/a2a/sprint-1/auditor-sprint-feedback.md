# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Change under review:** `pr/head.diff` (68 files). Citations use `head/<path>:<line>` from `pr/head/`.

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

The PR replaces the fence's narrow #1245 heredoc scrub with a broad heredoc consumer classifier, which is on by default. When the classifier calls a heredoc non-executing, it throws away every body line that does not start with a fence verb. Two of its fail-closed checks can be evaded. I confirmed both against the head hook, and the base hook blocks every case. The first is execution of the written file later in the same command. The second is the point where Bash ends an unquoted heredoc. Each one lets a destructive command reach the shell without hitting any fence rule. Both are regressions against the pre-PR scan, so this audit blocks the merge.

The other new sanctions and caches share a trust problem. An agent can produce the implement-gate marker and the profile cache with one Bash call. Neither is a trust input, and each can change gate or guardrail behaviour without touching `.loa.config.yaml`. I reproduced both. Two review/audit skills are now told to run a command their allowlists do not grant. The retrospective default also flips on silently for configs that omit the key.

**Security Issues Found:**

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 5 |
| Low | 12 |

Scope limits: I read the whole diff for the hooks, scripts, libraries, data and config files. I sampled the skill prose and tests. I tested the classifier, the implement gate and the profile lib by running copies of the `pr/head/` and `pr/base/` files in scratch directories under `/tmp`. Test payloads were only passed to the hooks on stdin and never run. I did not run the bats suites. This report gives the bypass classes in words, not as payloads ready to paste.

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] Heredoc classifier misses same-command execution of the written file

**Severity:** HIGH (confidence: high)
**File:** `head/.claude/hooks/safety/block-destructive-bash.sh:625`. Related lines: `:612`, `:631`, and the caller at `:688`.
**Issue:** `_bdb_hd_same_line_exec` is the only check that turns a `tee`/`cat >` heredoc into the interpreter class when its target is executed later in the same command. It compares each token's quote-stripped basename with the target's basename, for exactly one segment at a time:

```
u="${_bdb_hd_tok[c]}"; u="${u//[\"\']/}"; u="${u##*/}"
[[ "$u" == "$b" ]] && seg_has=1
...
if ! _bdb_hd_is_safe_reader "$cw" || [[ "$cw" == "$b" ]]; then return 0; fi
```

The head hook classed each of the following later references as `nonexec` and dropped the body. The base hook blocked every one with exit 2.
- **A safe reader piped into a shell.** `cat` is a safe reader, so the segment that names the target passes, and the next pipeline member, a shell, never names it.
- **A glob or single-character pattern** standing in for the target path, as an argument to a shell or inside a `for` loop.
- **A command substitution** that builds the path.
- **A quoted multi-word `-c` program**, where the basename becomes the target plus the trailing text. This is the reviewer's DISS-001 case.
- **Execution on the header line itself**, after `&&` or `;`. Only the heredoc's own pipeline is classified, and `_bdb_hd_ctx_bad` looks only at the last token.

**Impact:** The body scan keeps only segments whose first word is a fence verb (`:576`). The fence therefore never sees a destructive body line that starts with anything else, such as a shell keyword (MED-001). The same Bash call then executes that body. Before this PR, `_bdb_scrub_cat_heredoc` only exempted a standalone quoted `cat`, so a `tee` body was scanned in full and blocked. The hooks reference documents later-command execution as a gap, but same-command execution is what this check claims to cover (`head/.claude/hooks/safety/block-destructive-bash.sh:154`).
**Fix:**
- Fail closed to `interpreter` whenever another segment or pipeline member of the command is a shell, interpreter or wrapper (`_bdb_hd_is_interp`). Also fail closed for `source` or `.`, and for any segment that holds a glob, `$(`, a backtick or a variable path on a non-safe-reader command. Do this whether or not the target is named.
- Classify every pipeline on the header line, not only the heredoc's own pipeline.
- Add corpus rows for each class above, with the expectation `block`.

**Reference:** CWE-184, Incomplete List of Disallowed Inputs, https://cwe.mitre.org/data/definitions/184.html. Also CWE-78, https://cwe.mitre.org/data/definitions/78.html.

### [HIGH-002] Unquoted heredoc terminator is matched on physical lines, not after Bash's line-continuation folding

**Severity:** HIGH (confidence: high)
**File:** `head/.claude/hooks/safety/block-destructive-bash.sh:672`
**Issue:** The delimiter search compares physical lines:

```
if [[ "$d" == "$_hd_delim" ]]; then found=$j; break; fi
```

In an unquoted heredoc, Bash removes backslash-newline pairs before it compares a line with the delimiter. A delimiter split across two physical lines with a trailing backslash therefore ends the heredoc for Bash, but not for the classifier. I checked this directly. Bash ran the line after the folded terminator as a command. The classifier returned `nonexec` and removed that line from the scrub copy, because it treated the line as body text up to the later literal delimiter.
**Impact:** Any command placed between the folded terminator and the literal delimiter runs as top-level shell, and the per-segment body filter removes it from the fence's view. This applies whenever the line does not start with a fence verb, for example when it starts with a keyword. The cross-model audit dissent raised this as DISS-001, and I confirmed it here.
**Fix:** For unquoted delimiters, fall back to the full scan, with class `interpreter`, whenever any body line ends in an odd number of backslashes. Alternatively, fold the continuations before searching for the terminator. Add a corpus row.
**Reference:** CWE-436, Interpretation Conflict, https://cwe.mitre.org/data/definitions/436.html. Also CWE-184, https://cwe.mitre.org/data/definitions/184.html.

---

## Medium/Low Priority Issues

### [MED-001] Body segments that start with a shell keyword are dropped
- **File:** `head/.claude/hooks/safety/block-destructive-bash.sh:538` (`_bdb_hd_segword`), confidence high.
- **Issue:** The function strips wrappers, assignments, quotes and leading `( { ! \`, but not `then`, `do`, `else`, `elif`, `if`, `while` or `until`. A fence verb that follows a keyword is classed as a non-verb segment and dropped by `_bdb_hd_scan_body` (`:576`). This is the amplifier that turns HIGH-001 and HIGH-002 into full bypasses. Corpus rows D129 to D142 cover wrappers but no keyword-prefixed forms.
- **Fix:** Strip reserved words in `_bdb_hd_segword`, or set `_hd_full=1` for any segment that starts with one. Add corpus rows. Reference: https://cwe.mitre.org/data/definitions/184.html.

### [MED-002] One Bash call turns `implement_gate.mode: deny` back into allow
- **File:** `head/.claude/hooks/compliance/implement-gate.sh:589`. Related: `head/.claude/scripts/run-checkpoint.sh:534`. Confidence high.
- **Issue:** `sanction="sanctioned_marker"` allows in every mode. I reproduced it with a known INTERRUPTED position under `deny`. The write was denied, then `run-checkpoint.sh mark --skill implement --sprint sprint-9` ran as an ordinary Bash call, and the next write was allowed with the row `allow/sanctioned_marker`. Nothing ties the marker to a derived run position. The hooks reference says a forged "marker and a trailer forged together" pass. That understates it, because the marker alone is enough.
- **Fix:** Under `deny`, sanction only when the marker's sprint matches a RUNNING derived position. Alternatively, sign the marker through `audit_emit_signed`. Say plainly in the example's `deny` paragraph that the marker defeats it until then. Reference: CWE-807, https://cwe.mitre.org/data/definitions/807.html.

### [MED-003] A forged profile cache overrides guardrail knobs without touching the config
- **File:** `head/.claude/scripts/lib/profile-lib.sh:230`. Related: the cache path at `:67` and the trust list at `head/.claude/hooks/compliance/implement-gate.sh:340`. Confidence high.
- **Issue:** The warm path returns `.knobs[$k].value` from `.run/effective-config.json` whenever `.id` matches. The id is made of paths, mtimes and sizes, all of which can be recomputed. I reproduced it with a config holding `guardrails.danger_level.enforce: false`. After a `jq` edit of the cache, `profile-lib.sh knob guardrails.danger_level.enforce false` printed `true`, and the config was unchanged. The cache is not an implement-gate trust input, so a Write-tool write to it does not even ask. In the other direction, the same edit can turn `guardrails.input.enabled` or `karpathy_principles.*` off.
- **Fix:** Add the cache to the trust-input list. Also make sure every cached knob value equals what the config and profile give. The simplest way is to key the cache on a hash of the three input files' contents and recompute on mismatch. Reference: CWE-345, https://cwe.mitre.org/data/definitions/345.html.

### [MED-004] Review and audit skills gate on a command their allowlist does not grant
- **File:** `head/.claude/skills/auditing-security/SKILL.md:67` and `:285`. Also `head/.claude/skills/reviewing-code/SKILL.md:69` and `:297`. Confidence high.
- **Issue:** The regenerated includes say "Run only if `.claude/scripts/lib/profile-lib.sh knob guardrails.input.enabled false` prints `true`". Both skills declare `deny_raw_shell: true`, and their `allowed-tools` at `:6` grant no `profile-lib.sh` call. Under the head allowlists the gate cannot be evaluated, so the input guardrails and the retrospective are silently skipped or blocked.
- **Fix:** Add `Bash(.claude/scripts/lib/profile-lib.sh knob *)` to `allowed-tools` and `capabilities.execute_commands` of every skill that renders these includes. Add a lint that checks each include against the grants. Reference: CWE-636, https://cwe.mitre.org/data/definitions/636.html.

### [MED-005] `invisible_retrospective.enabled` silently flips on
- **File:** `head/.claude/data/profiles.yaml:42`, confidence high.
- **Issue:** `standard` sets `invisible_retrospective.enabled: true`. Before this PR the scan ran only on an explicit `true`. The repository config and any install that omits the key now run the learning-signal scan after every skill. The profiles.yaml header says only the two guardrail keys change default this cycle. The scan reads session content and writes trajectory and learning artefacts.
- **Fix:** Set `standard` to `false` for this key. Otherwise record the flip as a migration item with its own decision and changelog entry. Reference: CWE-1188, https://cwe.mitre.org/data/definitions/1188.html.

### [LOW-001] `LOA_IMPLEMENT_GATE_OVERRIDE=1` allows even under `deny`
- **File:** `head/.claude/hooks/compliance/implement-gate.sh:590`, confidence medium.
- **Issue:** A bare environment variable sanctions every write. This contradicts the invariant the same PR states for the fence at `head/.claude/hooks/safety/block-destructive-bash.sh:761`. The variable comes from the harness environment, which the Bash tool cannot reach directly, so the impact is low.
- **Fix:** Ignore the variable under `deny`, or require an operator-created file to go with it.

### [LOW-002] A configured `deny` silently drops to `ask` when the config cannot be read
- **File:** `head/.claude/hooks/compliance/implement-gate.sh:187` (`load_gate_config`), confidence medium.
- **Issue:** A missing `yq`, a missing config or a parse failure each leave `gate_mode=ask` and write no row. The result is still ask, never allow.
- **Fix:** Write a `compliance.mode.fallback` row when a config exists but cannot be parsed.

### [LOW-003] Unguarded `source` in two safety scripts, and their fallback reads disabled
- **File:** `head/.claude/scripts/danger-level-enforcer.sh:138` and `head/.claude/scripts/guardrails-orchestrator.sh:107`, confidence medium.
- **Issue:** `source "$SCRIPT_DIR/lib/profile-lib.sh"` runs under `set -euo pipefail`. A partial install kills both scripts, and the skill preludes treat that exit as fail-open. The caller fallback is also `false`, so a failed resolution reads disabled. The default flip itself is intended (DEC-0161) and documented in the example.
- **Fix:** Guard the `source` and fall back to an explicit config read.

### [LOW-004] The cache key falls back to filesystem statistics
- **File:** `head/.claude/scripts/lib/profile-lib.sh:77`, confidence high.
- **Issue:** When any of the three files is missing, GNU `stat -Lc` exits non-zero. The fallback `stat -Lf` then prints filesystem block counts, which I confirmed on this host. The cache key then follows free disk space instead of file edits, and stale knobs can be served.
- **Fix:** Stat only the files that exist, and disable caching when the output lacks the expected fields.

### [LOW-005] `_ig_within` only accepts the `Z` timestamp form
- **File:** `head/.claude/hooks/compliance/implement-gate.sh:475`, confidence low.
- **Issue:** A `derived_at` or `started_at` with an offset is read as stale. This fails toward ask, not allow.

### [LOW-006] The safe-reader list is wider than "reader"
- **File:** `head/.claude/hooks/safety/block-destructive-bash.sh:222`, confidence medium.
- **Issue:** `git`, `gh`, `br`, `jq` and `yq` can consume the target as a patch, program or upload, for example with `git apply` or `jq -f`. Naming the target with them does not trigger the interpreter class.
- **Fix:** Limit the list to pure readers, or to read-only subcommands.

### [LOW-007] Persistence locations are missing from the executable-destination list
- **File:** `head/.claude/hooks/safety/block-destructive-bash.sh:190`, confidence medium.
- **Issue:** `.bash_aliases`, `.github/workflows/`, `.claude/commands/`, `.claude/agents/`, `Makefile`, `.git/` files other than `hooks` and `config`, and `.ssh/config` are all classed as plain files. Their bodies are scrubbed, but the content runs at a later shell start, CI run or `make` call. This falls under the documented later-command gap, but these paths are cheap to add.

### [LOW-008] `LOA_AUDIT_REPLAY=1` marks live gate rows as replay
- **File:** `head/.claude/hooks/compliance/implement-gate.sh:214`, confidence low.
- **Issue:** The flag is inherited from the hook environment, so a stray value hides real decisions from consumers that discount replay rows.

### [LOW-009] A runtime state file is committed
- **File:** `head/.run/audit.jsonl:1`, confidence high.
- **Issue:** The PR adds a live audit row with a local workspace path (`/workspace/pr/head`). `.run/` is runtime state, and this row will confuse the gate's own register.
- **Fix:** Drop the file from the PR.

### [LOW-010] Every write now spawns `run-checkpoint.sh read`, including a `br show`
- **File:** `head/.claude/hooks/quality/karpathy-surgical-diff-check.sh:131`, confidence medium.
- **Issue:** The PR deletes the earlier perf caches, and this call adds a beads round-trip to every Write, Edit and NotebookEdit.
- **Fix:** Read `.checkpoint` with one `jq`.

### [LOW-011] The warning text still says "Session diff total"
- **File:** `head/.claude/hooks/quality/karpathy-surgical-diff-check.sh:193`, confidence high.
- **Issue:** The total is now counted per task.

### [LOW-012] The beads-unavailable fallback sentence was dropped
- **File:** `head/.claude/skills/implementing-tasks/SKILL.md:202`, confidence medium.
- **Issue:** "If beads is unavailable, fall back to markdown tracking in NOTES.md" was removed by the prose diet, so `/implement` without `br` has no instruction.

---

## Observations

- **Agent-team rules moved, not lost.** DISS-C-007 says the C-TEAM rules were deleted. They moved from `constraints.json` and the kernel to `head/.claude/loa/reference/agent-teams-reference.md`. `team-role-guard-write.sh` and `team-skill-guard.sh` are still registered in both settings files. This is not tallied.
- **AC walkthrough missing.** The implementation report has no `## AC Verification` section, as the review noted. This is a process gap, not a code defect, and it is not tallied here.
- **Excluded findings.** The review trailer excluded 0 findings, so there is nothing to confirm (`excluded_confirmed: 0`).
- **Skipped artefacts.** I did not write a structured `findings.jsonl` or beads comments for this frozen PR, because there is no beads database for it.

---

## Cross-Model Dissent

I ran the dissent as `adversarial-review.sh --type audit --sprint-id sprint-1 --diff-file pr/head.diff --json`. The primary voice was gpt-5.5-pro and the companion voice, claude-headless, succeeded. The run was not degraded, and `metadata.locality` is null, so there is no DEGRADED_SECURITY_REVIEW. It returned 10 findings, and there are no advisory voices.

| Finding | Triage |
|---------|--------|
| DISS-001 terminator folding | Confirmed by direct test. Tallied as HIGH-002. |
| DISS-C-001 unauthenticated marker under deny | Confirmed by direct test. Tallied as MED-002. It is kept at medium because `deny` is opt-in and this repository's head config stays on `ask`. |
| DISS-C-002 override environment variable | Tallied as LOW-001. |
| DISS-C-003 silent fallback from deny to ask | Tallied as LOW-002. It fails toward ask. |
| DISS-C-004 keyword drop and indirect references | Split into HIGH-001 and MED-001. |
| DISS-C-005 persistence destinations | Tallied as LOW-007. |
| DISS-C-006 guardrail defaults and unguarded source | The default flip is intended. The unguarded source and the fallback are LOW-003. |
| DISS-C-007 C-TEAM removal | Not a defect. See Observations. |
| DISS-C-008 safe readers too broad | Tallied as LOW-006. |
| DISS-C-009 replay environment variable | Tallied as LOW-008. |

## Rejected dissent payloads

None. `metadata.rejected_summary` is empty, `rejected_count` is 0, and `adversarial-rejected-audit.jsonl` has zero rows.

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added.
- [ ] Input validation on all new trust boundaries. HIGH-001, HIGH-002 and MED-001 fail it.
- [ ] Authentication or authorization of new sanctions. MED-002 and MED-003 fail it.
- [x] No SQL or XSS injection. Key paths are regex-checked before they reach `yq`, and audit rows are built with `jq`.
- [x] Error handling does not leak information. Paths are control-stripped and cut to 256 bytes. LOW-009 is the only path leak, and it is an artefact, not error handling.
- [ ] Tests cover security paths. The corpus has no rows for indirect same-command execution, terminator folding or keyword-prefixed bodies.

---

## Next Steps

1. Fix HIGH-001, HIGH-002 and MED-001 in the classifier, and add the corpus rows.
2. Make the marker and the profile cache trust inputs, or tie them to the derived position (MED-002, MED-003).
3. Fix the skill grants (MED-004) and decide the retrospective default (MED-005).
4. Run `/implement sprint-1`, then `/review-sprint sprint-1` and `/audit-sprint sprint-1` again.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":5,"low":12},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-22T19:20:02Z"} -->
