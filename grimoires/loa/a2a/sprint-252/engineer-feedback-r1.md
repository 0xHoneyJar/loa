# Sprint 252 Review Feedback (round 1)

**Reviewer:** Senior Tech Lead Reviewer Agent (Claude Fable 5.1)
**Date:** 2026-10-13T02:43:44Z
**Sprint Reference:** grimoires/loa/sprint.md § Sprint 1 (global 252)
**Implementation Report:** grimoires/loa/a2a/sprint-252/reviewer.md (parts: reviewer-a.md, reviewer-b.md, reviewer-c.md)
**Commit under review:** 8dc4a49d on feature/cycle-128-decision-surfaces (44 files, +5,869/-110)

---

## Overall Assessment

The sprint delivers what it promised and the code holds up to a full read: the ledger writer derives attribution from context and never from a caller argument, every unattended write lands `proposed`, the verify-before-rename step compares the candidate row-by-row against the pre-write file, the validator enforces the transition invariants and the append-only rule, the SessionStart surface is default-off and fenced, the rounds text and the checker match, and the FR-8 flag is proven live by the harness check rather than assumed. All 343 tests in the 14-suite set pass; budgets, the sha256 lint, the AGENTS drift check and the AC-verification validator are green; `reviewer.md` carries every acceptance criterion verbatim with file:line evidence.

Zero critical or high findings. Three MEDIUM defects are real, small and worth fixing before approval because each undermines a guarantee the sprint documents (the shipped config example defeats the per-mode default it describes; the CI/hook refusal can be bypassed by naming the live ledger with `--file`; the FR-8 lint exempts any line that mentions the operator). One MEDIUM observation is recorded for a follow-up bead, not for this sprint. Changes are requested by the reviewer's call under the zero-critical/high rule; the fix round has been dispatched to the owning implementers.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Configuration: the shipped example overrides the per-mode pacing default

- **MEDIUM** (confidence: high) `.loa.config.yaml.example:139` — the block says "Unset: rounds for thorough, batch for minimal. An explicit value always wins", then ships `pacing: rounds` as an explicit value, so a project that copies the example and sets `mode: minimal` runs rounds instead of batch.
**File:** `.loa.config.yaml.example:139`
**Issue:** The documented mode-dependent default is unreachable from the template (dissent DISS-C-003, confirmed).
**Why This Matters:** The migration note promises "minimal still defaults to batch"; the example breaks the promise for every project that starts from it.
**Required Fix:** Ship the line commented (`# pacing: rounds`) with the per-mode rule beside it; confirm the SKILL.md `cfg` fallback and REFERENCE §Interview Modes agree.

### 2. Ledger writer: the CI/hook refusal is keyed on the flag, not the path

- **MEDIUM** (confidence: high) `.claude/scripts/lib/dec-write-lib.sh:250-261` — `resolve_target` treats any `--file` as a fixture, so `CI=1 dec-write-lib.sh new --file grimoires/loa/decisions.yaml ...` reaches the write path (probe: the call got past the CI check and failed only on missing row fields).
**File:** `.claude/scripts/lib/dec-write-lib.sh:250-261`
**Issue:** The "never written from CI or a hook" guarantee that `decisions.md` and the config example state can be bypassed by naming the live ledger or a pending file explicitly (dissent DISS-C-004, confirmed by probe).
**Why This Matters:** A hook or CI job with the wrong argument writes the tracked ledger; the test suite does not pin the guarantee.
**Required Fix:** Classify the target by its canonical path (live ledger, pending file under `grimoires/loa/a2a/*/`, else fixture) so the refusal applies; bats for relative and absolute live paths under `CI`, `GITHUB_ACTIONS` and `LOA_HOOK_CONTEXT`.

### 3. FR-8 lint: the exempt-word filter drops operative lines

- **MEDIUM** (confidence: high) `tests/unit/user-invoked-commands.bats:65-74` — `grep -viE "$exempt"` discards any line containing user/operator/human/ask/tell/suggest/recommend/manually, so "Run `/decisions confirm` on the operator's behalf" is never reported.
**File:** `tests/unit/user-invoked-commands.bats:65-74`
**Issue:** Systematic false negatives; for `/decisions` almost every plausible sentence mentions the operator (dissent DISS-C-001).
**Why This Matters:** The lint is the only mechanical guard that no body instructs the model to run a flagged command as a step; the harness refusal remains, but the lint should not stay green on the sentences it exists to catch.
**Required Fix:** Exempt a line only when an exempt word precedes the verb ("tell the user to run /x"), never when it follows the command name; fixture cases for both shapes; re-run the live-tree check and report any newly reported real lines rather than weakening the rule.

---

## Observations

### 1. Operator-only transitions rest on a convention the harness cannot enforce

- **MEDIUM** (confidence: high) `.claude/scripts/lib/dec-write-lib.sh:303` — `is_operator_call` is `--recorded-by decisions-command`, a free argument; a skill with unrestricted Bash can pass it and run `confirm`, `supersede` or `context --clear`.
**File:** `.claude/scripts/lib/dec-write-lib.sh:303`
**Suggestion:** The design states this honest limit (SDD §9: attribution is tamper-evident, not enforced). Two mitigations already hold: `confirm` refuses while any live-run signal stands, and the lint keeps the operations out of every SKILL.md `allowed-tools`. Raise the bypass cost with a Bash fence rule in `block-destructive-bash.sh` that blocks `dec-write-lib.sh (confirm|supersede|context --clear)` and `reject` of a decided row unless the `/decisions` command's documented step is the caller; a fenced block is logged, so a bypass leaves a trace. Follow-up bead, not this sprint.
**Benefit:** Turns a prose rule into a logged fence, the Mechanical Floor pattern.

### 2. Round checker: a multi-array capture exits 2 instead of reporting a violation

- **LOW** (confidence: medium) `tools/check-round-independence.sh:63-72` — the shape check runs `jq -e` over a JSON stream and reflects only the last value; a greedy capture holding two arrays passes the check and the later `--argjson` fails with exit 2 (dissent DISS-C-002). Fixed in the same round (part A) since it is a one-line change with a fixture.
**Suggestion:** Reject a multi-value stream in the shape check so malformed input is exit 1 with the "malformed questions array" violation.
**Benefit:** Callers branching on exit 1 vs 2 get the documented contract.

---

## Cross-Model Observations

Two voices (gpt-5.5-pro primary via cheval, claude-headless companion; companion status succeeded; 0 rejected payloads). Five findings:

- **DISS-001 (BLOCKING, gpt-5.5-pro) REFUTED with evidence.** Claim: jq membership checks `index([$q.id])` / `index([$d])` "never match" because the arrays hold strings. jq's `index` on an array takes a subarray and finds a one-element sequence: `jq -n '["Q1","Q2"] | index(["Q2"])'` → `1`, `index(["Q3"])` → `null`. The fixtures prove the behaviour: `tests/fixtures/rounds/independent.md` → PASS (4 rounds, average 2.33), `same-round-dependency.md` → `VIOLATION: round 1: Q3 depends on Q2, asked in the same round`; `tests/unit/check-round-independence.bats` 16/16. Not a defect; excluded from the tally as refuted (not as a demoted high).
- **DISS-C-001** → Changes Required 3. **DISS-C-003** → Changes Required 1. **DISS-C-004** → Changes Required 2 (confirmed by probe). **DISS-C-002** → Observation 2.

## Rejected dissent payloads

None. `adversarial-rejected-review.jsonl` is empty and `metadata.rejected_summary` is `[]`.

---

## Previous Feedback Status

Not applicable (first round).

---

## Incomplete Tasks

None. All ten Sprint 1 tasks are implemented and their beads closed; the three changes above are corrections to delivered work.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":0,"medium":4,"low":1},"excluded":0,"sprint_id":"sprint-252","ts":"2026-10-13T02:43:44Z"} -->
