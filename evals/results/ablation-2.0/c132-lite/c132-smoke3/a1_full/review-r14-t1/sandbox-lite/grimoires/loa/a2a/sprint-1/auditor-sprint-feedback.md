# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Scope:** `pr/head.diff` (88 files, cycle-126 sprint-250 tasks 4.1–4.8); citations are `head/<path>:<line>` from `pr/head/`

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

The change moves the `opus` alias to `claude-opus-5-5` and `cheap` to `claude-sonnet-5`, adds a `model-permissions.yaml`
row for every Anthropic catalog entry (all-none trust scopes copied from the 4.7 reference, `security: redacted`),
rewrites `implement-gate.sh` to be heuristic by default with an undocumented `implement_gate.mode: authoritative`
opt-in plus an evidence recorder, teaches `check-permissions.sh` the `Bash(x *)` ≡ `Bash(x:*)` grammar, moves the
flatline/red-team script defaults onto catalog aliases, bumps the eval grader to 1.1.0, reverts the Sprint 3
CLAUDE.loa.md trim and twelve constraint rationales (Task 4.8), and raises the CLAUDE.loa.md prompt budget from
9,216 B to 10,240 B.

Security posture of the sprint is sound: no secrets, no new network sinks, no injection paths, every new
model row is least-privilege, the new `lib-content.sh` guards (canonical-decimal index, control-byte stripping
on stderr) and the `validate-artifact.sh` SIGPIPE fix are hygiene improvements. Verified against the head files
(not the report): `model-config.yaml.checksum` matches the head catalog; the two `SHA256SUMS` manifest lines
verify; the rendered C-PROC rows in CLAUDE.loa.md match constraints.json. The blocker is in Task 4.8: the
generated `agent_teams_constraints` block in CLAUDE.loa.md was not regenerated, `generate-constraints.sh
--validate-only` fails on the head tree, and the PR's own new byte budget prevents regenerating it.

**Phase 0 note:** `engineer-feedback.md` says CHANGES REQUIRED (one HIGH), not "All good". The task brief for this
frozen-PR evaluation directs the audit to run regardless; the review's HIGH is independently confirmed below and
tallied as this audit's own finding.

**DEGRADED_SECURITY_REVIEW.** Phase 1C ran `adversarial-review.sh --type audit --sprint-id sprint-1 --diff-file
pr/head.diff --json`. The envelope at `grimoires/loa/a2a/sprint-1/adversarial-audit.json` records
`status: api_failure`, `degraded: true`: all four hops (`gpt-5.5-pro`, `gpt-5.5`, `gemini-3.1-pro`,
`claude-headless`) failed with exit 126 (`model-adapter.sh: Permission denied` — no provider route in this
sandbox); `companion_voice.status: failed`, `failure_class: model_unavailable`; `findings: []`;
`rejected_summary` absent; no rejected sidecars. This is a single-voice audit.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 1 |
| Low | 5 |

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] Task 4.8 revert is not rendered where the model reads it, and the PR's own budget forbids rendering it

**Severity:** HIGH (confidence: high) — Code Quality / DevOps gate; confirms the review's HIGH independently
**File:** `head/.claude/loa/CLAUDE.loa.md:124-131`, `head/.claude/data/constraints.json:1235`, `head/tools/check-prompt-budget.sh:53`, `head/tests/unit/instruction-diet-revert.bats:62`
**Issue:** The `agent_teams_constraints` block is marked generated:
`"<!-- @constraint-generated: start agent_teams_constraints | hash:c020-teamcreate -->"` (CLAUDE.loa.md:L124) and
still renders the trimmed rationales, e.g. `"| MUST restrict planning skills to team lead only … | Planning skills
assume single-writer semantics |"` (CLAUDE.loa.md:L126), while the registry now carries the restored text
`"Planning skills produce single artifacts (PRD, SDD, sprint plan) that assume single-writer semantics; concurrent
invocation would corrupt state"` (constraints.json:L1235), and likewise for C-TEAM-002..005. Run on the head tree:
```
FAIL: STALE: Section 'agent_teams_constraints' in .claude/loa/CLAUDE.loa.md (stored: c020, expected: 19641576807c2086)
[validate-constraints] Results: 1 error(s), 0 warning(s)   (exit 1)
```
Regenerating the five rows adds 490 B: 10,225 B → 10,715 B, above the 10,240 B limit this PR sets
(`"SKILL_LIMIT, LOA_LIMIT, PROTO_FAIL, PROTO_WARN = 16384, 10240, 160000, 114688"`, check-prompt-budget.sh:L53).
IDR-3 asserts the twelve JSON rationales, IDR-4 asserts only the seven C-PROC rows
(`"for id in C-PROC-001 C-PROC-002 C-PROC-004 C-PROC-005 C-PROC-015 C-PROC-017 C-PROC-018"`, L62), so the five
C-TEAM rows are untested in the rendered artifact. The block/registry drift pre-exists (base also disagreed), but
this PR is the one that claims the twelve-row revert and that pins the budget that now locks the drift in.
**Impact:** The replay A/B rule that justified Task 4.8 measured recall on what the model is shown; the Agent Teams
rows are still the trimmed text in the model-facing file, so the revert is only partially effective. Separately the
merged tree fails one of its two framework lint gates whichever way the next contributor resolves it (regenerate →
budget fails; leave → validate-only fails).
**Fix:** Pick one and make the tests prove it:
  (a) regenerate the `agent_teams_constraints` block (`generate-constraints.sh`), raise `LOA_LIMIT` (and PB-4/PB-6)
      to cover ≥ 10,715 B with margin, and extend IDR-4 to C-TEAM-001..005; or
  (b) scope Task 4.8 to the seven C-PROC rows: restore the base `why` text for C-TEAM-001..005 in constraints.json,
      drop them from `tests/fixtures/constraint-rationales-pre-diet.json` and the `len(want) == 12` assertion, and
      correct the PR description. Either way add a test that `generate-constraints.sh --validate-only` exits 0.
**Reference:** CWE-1068 Inconsistency Between Implementation and Documented Design — https://cwe.mitre.org/data/definitions/1068.html

---

## Medium/Low Priority Issues

### [MED-001] The authoritative opt-in is a fence-disable switch reachable by the fenced agent

- **Severity:** MEDIUM (confidence: high)
- **File:** `head/.claude/hooks/compliance/implement-gate.sh:115`, `head/.claude/hooks/compliance/implement-gate.sh:128-129`
- **Issue:** The mode is read from a file the model can write:
  `"configured_mode=$(yq '.implement_gate.mode // \"\"' \"$PROJECT_ROOT/.loa.config.yaml\" 2>/dev/null)"` (L115).
  With it set, a model-authored `tool_input.active_skill` is trusted outright:
  `"implement|/implement|bug|/bug|run|/run|simstim|/simstim)"` → `"exit 0"` (L128-129) — silent allow, no RUNNING
  state consulted, no `audit.jsonl` row. `.loa.config.yaml` sits at the repo root, is not App Zone (the gate itself
  exits 0 for it at L107), and no PreToolUse hook in `settings.json` names it; `[ASSUMPTION]` it is not a
  framework-zone `tracked_path` either (no `grimoires/loa/zones.yaml` in this workspace). So the two-step sequence
  Write `.loa.config.yaml` (add `implement_gate.mode: authoritative`) → Write `src/x` with `active_skill: implement`
  passes every fence without the ask prompt the gate exists to raise. IG-5 proves `.run/` cannot flip the gate; the
  config path can. The PR's mitigation is that the key "stays undocumented" (IG-11, implement-gate.bats:L151) — the key
  name is in the hook's own source, which the model can read.
- **Why MEDIUM not HIGH:** the damage (an App-Zone write without the ask) is the same class as the Bash-path gap the
  framework already accepts as review-territory (constraints.json C-PROC-001 `why`), and the gate is advisory
  (`decision: ask`), not a block. It is still the only branch that turns a model-authored field into an allow.
- **Fix:** Remove the authoritative branch (nothing in the harness can ever select it legitimately per D-4.4), or make
  it AND the heuristic (`active_skill` AND a fresh RUNNING state) and emit an `audit.jsonl` row on every authoritative
  allow so the bypass is at least visible in `/loa`.
- **Reference:** CWE-807 Reliance on Untrusted Inputs in a Security Decision — https://cwe.mitre.org/data/definitions/807.html; CWE-284 Improper Access Control — https://cwe.mitre.org/data/definitions/284.html

### [LOW-001] Fifteen bytes of headroom on CLAUDE.loa.md

- **Severity:** LOW (confidence: high)
- **File:** `head/tools/check-prompt-budget.sh:53`, `head/.claude/loa/CLAUDE.loa.md:1`
- **Issue:** The head file is 10,225 B against `LOA_LIMIT = 10240`. Any rationale edit — including the fix for HIGH-001 —
  trips `check-prompt-budget.sh`.
- **Fix:** Size the limit to the reverted content with a stated margin, or document in the script why it is pinned this tightly.
- **Reference:** CWE-1068 — https://cwe.mitre.org/data/definitions/1068.html

### [LOW-002] check-permissions — base derivation assumes a wildcard requirement

- **Severity:** LOW (confidence: high)
- **File:** `head/.claude/scripts/check-permissions.sh:237`
- **Issue:** `"base=\"*${key#\\*}\"; base=\"${base%% *}\""` — for an exact requirement (`Bash(git push)` → key `=git push`)
  this yields `*=git`, a key no rule can produce, so `Bash(git:*)` would not cover it although the header grammar
  (L18-26) says a wildcard rule covers a requirement by its first word. Every current requirement is wildcard-form,
  so no live effect. (Checked: `Bash(:*)` normalises to key `*`; bash associative-array assignment and lookup with that
  subscript behave normally here, so no accidental all-elements expansion.)
- **Fix:** Derive `base` from `${key#[*=]}`, or assert in a comment that requirements are always wildcard-form.
- **Reference:** CWE-697 Incorrect Comparison — https://cwe.mitre.org/data/definitions/697.html

### [LOW-003] model-adapter — mktemp with no fallback under `set -euo pipefail`

- **Severity:** LOW (confidence: medium)
- **File:** `head/.claude/scripts/model-adapter.sh:656` (script has `set -euo pipefail` at L33)
- **Issue:** `"err_file=\"$(mktemp \"${TMPDIR:-/tmp}/model-adapter-stderr.XXXXXX\")\""` — a full or read-only `TMPDIR`
  aborts the shim before `model-invoke` runs and before the usual "model-invoke failed" error line; the caller sees a
  bare non-zero exit. The bd-pw7e LOW-001 WARN forwarding becomes a new failure mode for the hop itself.
- **Fix:** `err_file=$(mktemp …) || err_file=/dev/null`, and skip the grep when it is `/dev/null`.
- **Reference:** CWE-754 Improper Check for Unusual or Exceptional Conditions — https://cwe.mitre.org/data/definitions/754.html

### [LOW-004] Prompt-budget sentinel fixtures not updated with the limit (unverifiable here)

- **Severity:** LOW (confidence: low) — the review counted this MEDIUM; the worst case is a test false-negative, so LOW here
- **File:** `head/tools/check-prompt-budget.sh:53`
- **Issue:** `LOA_LIMIT` moves 9,216 → 10,240 B but `tests/fixtures/prompt-budget/{over,under}` (PB-8's CI sentinels) are
  not among the 88 files. If the `over` tree's CLAUDE.loa.md was sized between 9,217 and 10,240 B, PB-8 now passes an
  `over` tree it should fail. Not in the frozen file set; unable to assess further.
- **Fix:** Confirm the `over` sentinel still fails for a reason other than CLAUDE.loa.md size, or pad it past 10,240 B.
- **Reference:** CWE-1068 — https://cwe.mitre.org/data/definitions/1068.html

### [LOW-005] CHANGELOG entry not in the diff (documentation audit)

- **Severity:** LOW (confidence: low)
- **File:** `head/README.md:24`
- **Issue:** The README "Unreleased — full size" entry and the migration addendum are present, but no `CHANGELOG.md` is
  among the 88 files although the final commit message cites a CHANGELOG protocol figure. The sprint changes a
  security fence (`implement-gate.sh`) and a permissions checker; the documentation audit expects those in the CHANGELOG.
- **Fix:** Confirm the CHANGELOG entry lands in the same PR, or note that it sits outside the frozen file set.
- **Reference:** OWASP ASVS V1.1 Secure SDLC documentation — https://owasp.org/www-project-application-security-verification-standard/

---

## Observations (not tallied)

- **Positive — least-privilege rows.** Every new `model-permissions.yaml` row (`head/.claude/data/model-permissions.yaml:207`
  onward) copies the 4.7 posture: all six trust scopes `none`, `context_access.security: redacted`, all four capabilities
  `false`, `execution_mode: remote_model`. The `claude-headless` row documents that `extra.allowed_tools` widens the CLI.
- **Positive — output hygiene.** `detect-platform-features.sh --line` strips control characters and caps at 120 chars
  (`head/.claude/scripts/detect-platform-features.sh:36`) before echoing `.run/` content into `/loa`; `lib-content.sh`
  strips C0/DEL from the diff header path before it reaches stderr; the chunk-index guard refuses non-canonical decimals.
- **Positive — SIGPIPE fix.** `validate-artifact.sh` replaces `printf | grep -q` with here-strings, removing a pipefail
  race that reported present sections as missing.
- **Scope analysis.** `security-audit-scope.sh --json` over `pr/head/`: 5 source files, 4 sink files, 0 auth, 0 LLM-prompt
  files; sources/sinks traced are the hook stdin → `.run/platform-features.json` recorder (writes only a timestamp and a
  constant), the `yq` config read (MED-001), the settings-file rule reader (LOW-002), and the cheval stderr temp file
  (0600 via mktemp, removed; LOW-003). No second-order flow found.

## Rejected dissent payloads

None — the envelope has no `rejected_summary` and no `adversarial-rejected-audit*.jsonl` sidecar (all hops failed before producing a payload).

## Review demotions

The review trailer records `excluded: 0`; nothing to confirm. `excluded_confirmed: 0`.

---

## Rubric Scores

| Dimension | Score | Basis |
|-----------|-------|-------|
| SEC-IV Input Validation | 4 | agent-types names validated by regex; rule grammar rewrites nothing; LOW-002 edge |
| SEC-AZ Authorization | 3 | MED-001: model-writable config selects a branch that trusts a model-authored field |
| SEC-CI Confidentiality/Integrity | 5 | no secrets; new rows redact security context; stderr temp file 0600 and removed |
| SEC-IN Injection Prevention | 5 | all jq/yq args passed via `--arg`; control bytes stripped before stderr/`/loa` |
| SEC-AV Availability | 4 | LOW-003 mktemp abort path |
| ARCH-ST Standards | 4 | catalog, checksum, generated maps and BB registry all consistent |
| CQ-RD / CQ-TS | 3 | HIGH-001: generated block stale, revert half-rendered, gap untested |
| DevOps | 3 | HIGH-001: `generate-constraints.sh --validate-only` fails on the merged tree |

## Security Checklist for This Sprint

- [x] No hardcoded secrets added
- [x] Input validation on new entry points (agent-types regex, rule grammar, index guard)
- [ ] Authorization — MED-001 authoritative branch trusts a model-authored field behind a model-writable switch
- [x] No SQL/XSS/command injection vulnerabilities
- [x] Error handling doesn't leak info (cheval stderr filtered to the one WARN)
- [x] Tests cover security paths (IG-1..11, CP-11..13, CMP-277/278, MA-5/6)
- [ ] Documentation coherence — HIGH-001 rendered block stale; LOW-005 CHANGELOG not in diff

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 4.8: revert the twelve constraint rationales | Incomplete | C-TEAM-001..005 restored in constraints.json only; rendered `agent_teams_constraints` block stale; cannot regenerate under the 10,240 B budget |

## Next Steps

1. Resolve HIGH-001 (option a or b) and add the validate-only green check.
2. Decide MED-001: remove the authoritative branch or AND it with the heuristic plus an audit row.
3. Fold LOW-001..003 into the same patch; confirm LOW-004/005 against the full tree.
4. Re-run `/review-sprint sprint-1` then `/audit-sprint sprint-1`; re-run the dissent on a host with a provider route so the audit is not DEGRADED_SECURITY_REVIEW.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":1,"low":5},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-21T14:45:56Z"} -->
