# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md

---

## Overall Assessment

The change under review is the cycle-126 sprint-250 pull request (88 files): the `opus` alias moves to the new
`claude-opus-5-5` catalog entry and `cheap` to `claude-sonnet-5`; every Anthropic catalog entry (direct and Bedrock)
gains a `model-permissions.yaml` row; `implement-gate.sh` becomes heuristic-by-default with an undocumented
`implement_gate.mode: authoritative` opt-in and an evidence recorder; `check-permissions.sh` learns the
`Bash(x *)` ≡ `Bash(x:*)` grammar; the flatline/red-team scripts default to catalog aliases; the eval grader moves to
1.1.0; Task 4.8 reverts the Sprint 3 CLAUDE.loa.md trim and the twelve constraint rationales; the prompt budget for
CLAUDE.loa.md rises from 9,216 to 10,240 B.

What I verified (code, not the report), running the PR's own tests against the head files in a scratch tree:

- `implement-gate.bats` (11), `compliance-hook.bats`, `hook-guard.bats`: 33/33 pass.
- `check-permissions.bats` (CP-11..13 incl. the deny fuzz table), `instruction-diet-revert.bats`, `model-residue.bats`,
  `prompt-budget.bats` (PB-8 needs a fixture outside the diff, see Observations): all other cases pass.
- `validate-artifact.bats`, `flatline-model-validation.bats`, `flatline-model-allowlist.bats`, `model-adapter.bats`: 80/80 pass.
- `eval-recall-grader.bats` RG-11..15 pass (RG-16/17 need the fixture corpus outside the diff); the two manifest
  checksums in `SHA256SUMS` match the manifests.
- Python: `test_anthropic_catalog_floor.py`, `test_trust_scopes.py`, `test_model_registry_parity.py`,
  `test_anthropic_thinking.py` — 101 passed against the head catalog and permissions file.
- `gen-adapter-maps.sh --dry-run` on the head catalog is byte-identical to the committed `generated-model-maps.sh`;
  `model-config.yaml.checksum` matches the head catalog; all 16 served Anthropic/Bedrock entries have a permissions
  row whose scopes equal the 4.7 reference.
- `generate-constraints.sh --validate-only` on the head tree: **FAIL — `agent_teams_constraints` STALE** (see Changes Required).

The catalog, registry, probe and grammar work is sound and well tested. The blocker is in Task 4.8: the constraint
rationale revert is only half-rendered, and the PR's own prompt budget prevents completing it.

Phase 2.5 (adversarial dissent): invoked with `--diff-file pr/head.diff`; the envelope at
`grimoires/loa/a2a/sprint-1/adversarial-review.json` records `status: api_failure` — every hop
(`gpt-5.5-pro`, `gpt-5.5`, `gemini-3.1-pro`, `claude-headless`) failed (no provider route in this sandbox; the
companion hop died on `model-adapter.sh: Permission denied`), `findings: []`, `rejected_summary` absent,
`companion_voice.status: failed (model_unavailable)`. Single-voice assessment follows; no rejected payloads to triage.

`reviewer.md` is the PR description and carries no `## AC Verification` section; in this frozen-PR context that is
noted, not counted.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Task 4.8 — the C-TEAM rationale revert is not rendered where the model reads it, and cannot be under the new budget

- **HIGH** (confidence: medium) `head/.claude/loa/CLAUDE.loa.md:124-131` — the `agent_teams_constraints` block (marked "DO NOT EDIT — generated from constraints.json", hash `c020-teamcreate`) still carries the trimmed rationales ("Planning skills assume single-writer semantics", …) while `head/.claude/data/constraints.json:1235` and the other four C-TEAM rows now carry the restored long text; `generate-constraints.sh --validate-only` reports the section STALE, and regenerating it grows CLAUDE.loa.md to 10,715 B, over the 10,240 B limit this PR sets at `head/tools/check-prompt-budget.sh:53`.
**File:** `head/.claude/loa/CLAUDE.loa.md:124-131`, `head/.claude/data/constraints.json:1235`, `head/tools/check-prompt-budget.sh:53`, `head/tests/unit/instruction-diet-revert.bats:62`
**Issue:** The PR description and IDR-3 claim "the twelve rationales carry their pre-diet text", but the model reads
CLAUDE.loa.md, and five of the twelve (C-TEAM-001..005) are still the trimmed text there. The registry and its
rendered table disagree, the renderer's freshness check fails, and the two gates the PR itself tunes are now in
conflict: regenerate the block → `check-prompt-budget.sh` fails (10,715 B > 10,240 B); leave it → `generate-constraints.sh
--validate-only` fails. IDR-4 (`instruction-diet-revert.bats:62`) only asserts the seven C-PROC rows, so the gap is
untested. The drift between the block and constraints.json pre-exists this PR (the base block did not match the base
registry either), but this PR is the one that asserts the twelve-row revert and that sets the budget that now locks
the drift in.
**Why This Matters:** The replay A/B rule the sprint cites measured recall on what the model is shown; a revert that
only lands in the JSON registry does not restore that signal for the Agent Teams rows. Separately, the merged tree
fails one of the two framework lint gates whichever way the next contributor resolves it.
**Required Fix:** Pick one and make the tests say so:
  (a) regenerate the `agent_teams_constraints` block from constraints.json (restoring the five rows in CLAUDE.loa.md),
      raise `LOA_LIMIT` in `tools/check-prompt-budget.sh` (and PB-4/PB-6 in `prompt-budget.bats`) to cover the result,
      and extend IDR-4 to the five C-TEAM ids; or
  (b) scope Task 4.8's revert to the seven C-PROC rows: restore the base `why` text for C-TEAM-001..005 in
      constraints.json, drop them from `tests/fixtures/constraint-rationales-pre-diet.json` (and the `len(want) == 12`
      assertion), and correct the PR description / sprint notes.
  Either way, add a check that `generate-constraints.sh --validate-only` is green on the tree.

---

## Observations

### 1. Implement gate — the opt-in authoritative branch is a fence-disable switch

- **MEDIUM** (confidence: high) `head/.claude/hooks/compliance/implement-gate.sh:128` — with `implement_gate.mode: authoritative` set, any Write/Edit whose model-authored `tool_input.active_skill` is `implement|bug|run|simstim` is allowed silently (exit 0, no audit row), even with no RUNNING state in `.run/`.
**File:** `head/.claude/hooks/compliance/implement-gate.sh:128`
**Suggestion:** The PR correctly concludes the field is model-authored and keeps the mode undocumented (IG-11), but the
branch still exists and is still a one-line config change away. Either remove the authoritative branch outright, or make
it AND the heuristic (active_skill AND a RUNNING state) and emit an `audit.jsonl` row on every allow so the bypass is
at least visible.
**Benefit:** Closes the only path by which a forged payload can turn the fence off.

### 2. Prompt-budget sentinel fixtures not updated with the limit

- **MEDIUM** (confidence: low) `head/tools/check-prompt-budget.sh:53` — `LOA_LIMIT` moves 9,216 → 10,240 B but `tests/fixtures/prompt-budget/{over,under}` (PB-8's CI sentinels) are not in the diff; if the `over` tree's CLAUDE.loa.md was sized between 9,217 and 10,240 B to trip the old limit, PB-8 now fails.
**File:** `head/tools/check-prompt-budget.sh:53`
**Suggestion:** Confirm `tests/fixtures/prompt-budget/over` still fails for a reason other than the CLAUDE.loa.md size, or
pad it past 10,240 B. Not verifiable from the frozen PR files.
**Benefit:** Keeps PB-8 meaningful after the limit change.

### 3. Fifteen bytes of headroom on CLAUDE.loa.md

- **LOW** (confidence: high) `head/.claude/loa/CLAUDE.loa.md:1` — the file is 10,225 B against the 10,240 B limit; any further edit to a rendered rationale (including the fix for Changes Required §1) trips `check-prompt-budget.sh`.
**File:** `head/.claude/loa/CLAUDE.loa.md:1`
**Suggestion:** Size the limit to the reverted content with a margin, or state in `check-prompt-budget.sh` why the
budget is pinned this tightly.
**Benefit:** Avoids a budget failure on the next unrelated constraint edit.

### 4. check-permissions — base derivation for an exact-form requirement

- **LOW** (confidence: high) `head/.claude/scripts/check-permissions.sh:237` — `base="*${key#\*}"` assumes the requirement key is a wildcard; for an exact requirement (`Bash(git push)` → key `=git push`) it produces `*=git`, which no rule can match, so `Bash(git:*)` would not cover it although the header grammar (lines 18-26) says a wildcard rule covers a requirement by its first word.
**File:** `head/.claude/scripts/check-permissions.sh:237`
**Suggestion:** Every current requirement is a wildcard, so no live impact. Either derive `base` from `${key#[*=]}` or
assert in a comment that requirements are always wildcard-form.
**Benefit:** Keeps the implementation honest to its own documented grammar.

### 5. model-adapter — mktemp with no fallback under `set -e`

- **LOW** (confidence: medium) `head/.claude/scripts/model-adapter.sh:656` — `err_file="$(mktemp …)"` under `set -euo pipefail`: a full or read-only `TMPDIR` aborts the shim before `model-invoke` runs and before the usual "model-invoke failed" error line, so the caller sees a bare non-zero exit.
**File:** `head/.claude/scripts/model-adapter.sh:656`
**Suggestion:** `err_file=$(mktemp …) || err_file=/dev/null` (and skip the grep when it is `/dev/null`).
**Benefit:** The agy WARN forwarding never becomes a new failure mode for the hop itself.

### 6. CHANGELOG entry not in the diff

- **LOW** (confidence: low) `head/README.md:24` — the README "Unreleased — full size" entry and the migration addendum are present, but no `CHANGELOG.md` is among the 88 files although the last commit message references a CHANGELOG protocol figure.
**File:** `head/README.md:24`
**Suggestion:** Confirm the CHANGELOG entry per task lands in the same PR (it may simply sit outside the frozen file set).
**Benefit:** Documentation-verification gate.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 4.8: revert the twelve constraint rationales | Incomplete | Five C-TEAM rows reverted in constraints.json only; the rendered `agent_teams_constraints` block in CLAUDE.loa.md is stale and cannot be regenerated under the PR's 10,240 B budget (see Changes Required §1) |

---

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":2,"low":4},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T14:35:00Z"} -->
