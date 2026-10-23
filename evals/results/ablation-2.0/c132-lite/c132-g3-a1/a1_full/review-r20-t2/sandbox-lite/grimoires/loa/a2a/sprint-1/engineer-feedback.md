# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Change under review:** `pr/head.diff` (68 files). Citations use `head/<path>:<line>` from `pr/head/`.

---

## Overall Assessment

The PR is large and mostly careful. The implement-gate mode matrix, the file-derived run position, the profile resolver and the per-task surgical counter all come with real tests. The heredoc classifier is the riskiest piece. It relaxes the destructive-command fence for heredoc bodies, and one of its fail-closed checks can be evaded. That evasion is a regression against the pre-PR scan, verified on the head hook, and it blocks the merge.

Four medium findings sit beside it:
- the new profile cache can change effective guardrail settings without touching the config trust input;
- the implementing-skill marker lets any Bash caller self-sanction under `deny`;
- two review/audit skills are told to run a command their allowlist does not grant;
- `invisible_retrospective` silently flips on for configs that omit the key.

The implementation report has no `## AC Verification` section, which is an automatic CHANGES_REQUIRED on its own.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Security: heredoc classifier misses same-command execution through a quoted string

- **HIGH** (confidence: high) `head/.claude/hooks/safety/block-destructive-bash.sh:625` — `_bdb_hd_same_line_exec` strips quotes from each token and compares its basename (`${u##*/}`) with the heredoc target's basename. A target named inside a multi-word quoted argument never matches, so a heredoc written to a plain file and executed later in the same command is classed non-executing and its body is dropped from the scan.

**File:** `head/.claude/hooks/safety/block-destructive-bash.sh:608-639` (check), `:688` (caller)
**Issue:** The token `'source /tmp/p; true'` becomes `source /tmp/p; true`, and its basename is `p; true`, not `p`. Verified with the head hook in library mode:

```
tee /tmp/p <<'EOF' / body / EOF / bash -c 'source /tmp/p'          -> interpreter
tee /tmp/p <<'EOF' / body / EOF / bash -c 'source /tmp/p; true'    -> nonexec
cat > notes.md <<'EOF' / body / EOF / sh -c 'cat notes.md | sh'    -> nonexec
```

In the nonexec case `_bdb_hd_scan_body` keeps only lines whose first word is a fence verb. A body line that starts with a shell keyword is also dropped, because `_bdb_hd_segword` does not strip `then`, `do` or `else`. A destructive body executed this way therefore reaches no fence rule.
**Why This Matters:** Before this PR the knob-off path, the #1245 scrub, only scrubbed a standalone quoted `cat`. A `tee` heredoc body was scanned in full and blocked. With the classifier on by default this is a new allow. The hooks reference documents later-command execution as a gap, but same-command execution is exactly what this check claims to cover.
**Required Fix:**
- Fail closed when the target basename, or the full target path, appears as a substring of any non-safe-reader token, quoted or not.
- Alternatively, class the heredoc as interpreter whenever another segment of the same command invokes a shell or interpreter with `-c`, or runs `source` or `.`.
- Strip shell keywords (`then`, `do`, `else`, `elif`, `!`) in `_bdb_hd_segword` so keyword-prefixed fence verbs are kept.
- Add corpus rows for the quoted multi-word forms above, and for a fence verb that follows a keyword.

**Reference:** CWE-184 (incomplete list of disallowed inputs). Raised by the cross-model dissent as DISS-001 and confirmed here.

---

## Observations

### 1. Security and trust boundaries

- **MEDIUM** (confidence: medium) `head/.claude/scripts/lib/profile-lib.sh:227` — `loa_knob`'s warm path trusts `.run/effective-config.json`, written at `:67`, when its `id` matches. The id is made of paths, mtimes and sizes, all of which an agent can compute. A Write-tool write to that file is neither App Zone nor an implement-gate trust input (`head/.claude/hooks/compliance/implement-gate.sh:340`). It is therefore allowed silently. It can switch `guardrails.danger_level.enforce`, `guardrails.input.enabled` or `karpathy_principles.*` without touching `.loa.config.yaml`, which asks on every write. **Suggestion:** add the cache to the trust-input list, or re-validate cached values against the profile set and config on read.
- **MEDIUM** (confidence: high) `head/.claude/hooks/compliance/implement-gate.sh:589` — The marker sanction allows in every mode, including `deny`, the only mode documented as a fence. `run-checkpoint.sh mark --skill implement --sprint x` (`head/.claude/scripts/run-checkpoint.sh:530-543`) is an ordinary Bash call that any session can make. One command therefore converts `deny` back into allow for two hours. The hooks reference lists forged `.run/` files as an accepted gap, but `deny` is advertised as the flip target for this cycle. **Suggestion:** under `deny`, require the marker to agree with the derived position, meaning a RUNNING cache naming the same sprint. At minimum, state in the example's `deny` paragraph that the marker defeats it.

### 2. Correctness and behavior changes

- **MEDIUM** (confidence: high) `head/.claude/skills/reviewing-code/SKILL.md:69` — The regenerated input-guardrails prelude, and the retrospective postlude at `:297`, now gate on `.claude/scripts/lib/profile-lib.sh knob …`. `reviewing-code` and `auditing-security` (`head/.claude/skills/auditing-security/SKILL.md:67`) declare `deny_raw_shell: true`, and their `allowed-tools` grant no `profile-lib.sh` call. Under these allowlists the gate cannot be evaluated, so the guardrail and retrospective steps are silently skipped or blocked. **Suggestion:** add `Bash(.claude/scripts/lib/profile-lib.sh knob *)` to the allowlist and capabilities of every skill that renders these includes, and add a lint for include-to-grant parity.
- **MEDIUM** (confidence: high) `head/.claude/data/profiles.yaml:42` — `standard` sets `invisible_retrospective.enabled: true`. The oracle records `empty_config_today: false` and `this_repo_today: false`, because the old prose ran the scan only on an explicit `true`. This repository's `.loa.config.yaml` omits the key, as does any install without it, so the retrospective scan now runs after every skill. The profiles.yaml header says only the two guardrail keys change default this cycle. PL-4 does not catch this because it compares against the example, which sets `true`. **Suggestion:** set `standard` to `false` for this key, or record the flip as a migration item with its own decision and changelog entry.
- **LOW** (confidence: medium) `head/.claude/scripts/danger-level-enforcer.sh:138` — The lib is sourced unconditionally under `set -euo pipefail`, and the same holds at `head/.claude/scripts/guardrails-orchestrator.sh:107`. A partial install without `lib/profile-lib.sh` kills both scripts. The skill preludes treat a non-zero exit as fail-open. Cross-model dissent DISS-C-002 raised this too. **Suggestion:** guard the source and fall back to the explicit config read.
- **LOW** (confidence: medium) `head/.claude/scripts/lib/profile-lib.sh:78` — When one of the three inputs is missing, for example no `floor.yaml` under `LOA_PROFILE_FLOOR_FILE`, GNU `stat -Lc` fails. The fallback `stat -Lf` then prints filesystem statistics instead of mtimes. The cache key then tracks free disk blocks, not file edits. A small config edit that leaves free blocks unchanged was reproduced to keep the same key, so stale knobs can be served. **Suggestion:** stat only the files that exist, and disable caching when GNU or BSD stat output lacks the expected fields.
- **LOW** (confidence: low) `head/.claude/hooks/compliance/implement-gate.sh:475` — `_ig_within` only parses `YYYY-MM-DDTHH:MM:SS[.f]Z`. An externally written `derived_at` or `started_at` with an offset is treated as stale, so a RUNNING cache stops sanctioning. `run-checkpoint.sh` itself writes the Z form. This is cross-model dissent DISS-C-003.

### 3. Performance, clarity, prose diet

- **LOW** (confidence: medium) `head/.claude/hooks/quality/karpathy-surgical-diff-check.sh:131` — Every Write, Edit and NotebookEdit now spawns `bash run-checkpoint.sh read --json`, which runs four `jq` calls and `br show` for a task checkpoint. The PR also deletes the earlier perf caches. This adds a beads round-trip to every write on the hot path. **Suggestion:** read `.checkpoint` directly with one `jq`, and verify the bead only when the key changes.
- **LOW** (confidence: high) `head/.claude/hooks/quality/karpathy-surgical-diff-check.sh:193` — The warning still says "Session diff total", but the total is now per task. KS-4 pins the old wording. **Suggestion:** say "Task diff total" and update KS-4.
- **LOW** (confidence: medium) `head/.claude/skills/implementing-tasks/SKILL.md:202` — The prose diet removed "If beads is unavailable, fall back to markdown tracking in NOTES.md". The beads-unavailable path of `/implement` now has no instruction. **Suggestion:** keep the one-sentence fallback.

Complexity: `block-destructive-bash.sh` gains about 640 lines, and `_bdb_hd_member` and `_bdb_heredoc_scrub` each exceed 50 lines with nesting deeper than 3. That is justified by the grammar comment, but it is the reason a defect like Changes Required item 1 is hard to see. Splitting member classification per command into small functions would help.

---

## Cross-Model Observations

The dissent was run as `adversarial-review.sh --type review --sprint-id sprint-1 --diff-file pr/head.diff`. The primary voice was gpt-5.5-pro and the companion voice, claude-headless, succeeded. It returned five findings.

| Finding | Voice | Triage |
|---------|-------|--------|
| DISS-001 same-line exec check misses quoted strings | primary | Real defect, verified. Counted as the HIGH under Changes Required. |
| DISS-C-001 marker sanction is unauthenticated and allows under `deny` | companion | Real. Counted as the second MEDIUM under Security and trust boundaries. |
| DISS-C-002 danger-level reader: default, unguarded source, config path | companion | The default flip is intended (DEC-0161). The unguarded source is the LOW above. |
| DISS-C-003 `_ig_within` accepts only the Z timestamp form | companion | Counted as a LOW. |
| DISS-C-004 kf-surface does not reset `enabled` before sourcing | companion | Not a defect. Both `head/.claude/hooks/loa-kf-surface.sh:53` and `head/.claude/hooks/session-start/loa-decisions-surface.sh:43` set `enabled="false"` first. |

## Rejected dissent payloads

None. The envelope's `rejected_summary` is empty and `adversarial-rejected-review.jsonl` has zero rows.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Changes required | Changes Required item 1. The implementation report has no `## AC Verification` walkthrough, which is an automatic CHANGES_REQUIRED. |

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| "review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict" (sprint.md, Success Criteria) | Fail for merge | One HIGH defect blocks the merge. Each finding above cites `head/<path>:<line>`. |

---

## Security Checklist

- [x] No hardcoded secrets or credentials. The test fixtures use redacted placeholders.
- [ ] Input validation and sanitization present. The heredoc same-command check is incomplete (Changes Required item 1).
- [ ] Authentication/authorization correct. The marker and the profile cache are unauthenticated sanctions (Observations, Security and trust boundaries).
- [x] No SQL/XSS injection vulnerabilities. Key paths are regex-checked before they reach `yq`, and audit rows are built with `jq`.
- [x] Dependencies secure. No new dependencies.
- [x] Error messages don't leak sensitive data. Paths are control-stripped and cut to 256 bytes.

---

## Code Quality Summary

**Strengths:**
- The implement-gate test matrix (IG-24 to IG-27) checks the decision, the audit row, the row count and the replay flag in every cell.
- `run-checkpoint.sh derive` has one test per decision-table row and per known reader.
- Explicit `false` is finally honoured: the old `// true` readers are gone and the knob-reader lint enforces it.
- Prune and render of the optional constraint table are idempotent and fail loudly on foreign text.

**Areas for Improvement:**
- Fail-closed claims in the classifier need adversarial corpus rows for quoting variants, not only plain words.
- Every new sanction or cache that changes gate behavior should be a trust input.

---

## Next Steps

1. Fix Changes Required item 1 and add the corpus rows.
2. Add an `## AC Verification` section to the implementation report.
3. Decide on the four MEDIUM observations, especially the profile-cache trust input and the retrospective default.
4. Re-run `bats tests/unit/` and `tests/fixtures/fence-corpus/run-corpus.sh`, then request another `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":4,"low":6},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T19:06:33Z"} -->
