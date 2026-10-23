All good

Sprint 1 has been reviewed and approved. Observations documented and non-blocking. See Observations below.

# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, pr/PR.md)

---

## Overall Assessment

The change under review is the pull request in `pr/` (88 files): the catalog gains `claude-opus-5-5` and retargets `opus` → `claude-opus-5-5` and `cheap` → `claude-sonnet-5`; every bash alias map, script default, example pin and generated twin follows; every Anthropic catalog entry gets a `model-permissions.yaml` row; the implement gate stops reading `.run/` to pick its mode and records `tool_input.active_skill` as evidence only; `check-permissions.sh` learns the `Bash(cmd *)` wildcard form; the recall grader parser handles parenthesised, comma-continued and bare `:N` citations and multi-site `anchors[]`; the Sprint 3 CLAUDE.loa.md trim and twelve constraint rationales are reverted per the pre-registered replay A/B rule; plus small hardening in `lib-content.sh`, `model-adapter.sh`, `validate-artifact.sh` and the license-fixture freshness guard.

What I verified (code, not the report):
- `.claude/defaults/model-config.yaml.checksum` equals the sha256 of the head catalog; `evals/fixtures/review-prs/SHA256SUMS` matches the two edited manifests; the Bridgebuilder `.build-manifest.json` hashes match `config.generated.ts` and `truncation.generated.ts`; the `@loa-managed` hash on `CLAUDE.loa.md` verifies (`marker-utils.sh verify_hash` → VALID); both `@constraint-generated` block hashes recompute to the marker values; the golden NEVER/ALWAYS fixtures equal the rendered blocks.
- `gen-adapter-maps.sh --dry-run` against the head catalog reproduces `generated-model-maps.sh` byte-for-byte (comments aside).
- Every Anthropic entry the head catalog serves (12 direct, 4 Bedrock) has a `model-permissions.yaml` row; the `claude-opus-5-5` entry carries the same key set as `claude-opus-5` (only pricing, chain and calibration source differ, as intended).
- The new `reviewer`/`opus`/`cheap` script defaults route through `call_flatline_chat` → `model-invoke` (cheval), which resolves catalog aliases; the shim's `MODEL_TO_ALIAS` agrees with `backward_compat_aliases` for every shared name.
- Ran the PR's own suites against the head tree (overlaid on the installed framework): `implement-gate.bats` 11/11, `check-permissions.bats` 13/13, `model-residue.bats` 6/7 (RES-6 needs two skill dirs absent from the fixture), `model-adapter.bats` 6/6, `compliance-hook.bats` CH-T8..T10 3/3, `instruction-diet-revert.bats` 4/4, `prompt-budget.bats` 8/9 (PB-8 needs CI sentinel fixtures absent here), `validate-artifact.bats` bd-8ndx 3/3, `hook-guard.bats` (d) pass, `flatline-model-validation.bats` 20/20, `flatline-max-tokens.bats` 6/6, `loa-status-providers.bats` 5/5, `gen-adapter-maps.bats` idempotence pass, `eval-recall-grader.bats` RG-1..15 15/15 (RG-16/17 need the fixture corpora absent here), `skill-capabilities.bats` SC-T-AGENT-8/9 pass and **SC-T-AGENT-7 fails** (below). The Python adapter tests could not be collected here (the fixture ships only `base.py`, which does not import against the installed `openai_adapter.py`).

Pre-flight steps that need a sprint plan, beads or an `## AC Verification` walkthrough were skipped per `pr/REVIEW-INSTRUCTIONS.md` (the PR files are the entire input). The adversarial dissent ran two voices (gpt-5.5-pro via codex-headless: clean; claude-headless: seven ADVISORY findings) and is triaged under Cross-Model Observations.

No critical or high finding. Three medium and five low observations, none blocking: two are test-robustness issues (a yq operator the installed yq lacks; a test that pins the uncalibrated state the catalog comment tells operators to change), one is a grader false-credit path that the mandatory LOA-VERDICT trailer triggers.

**Complexity:** the shell changes are small and flat; `rule_key` is 11 lines, the evidence recorder 11 lines, no function over 50 lines added, no new nesting over 3. Lean already. Ship.

**Verdict:** APPROVED

---

## Observations

### 1. Grader citation parser (evals)

- **MEDIUM** (confidence: high) `head/evals/graders/recall-vs-defects.sh:74` — the bare-`:N` alternative only excludes `[A-Za-z0-9_./:]` before the colon, so a colon preceded by `"` qualifies. Every review file ends with the LOA-VERDICT trailer `"counts":{"critical":0,"high":0,"medium":3,"low":5},"excluded":0`; each of those `":N` tokens becomes a bare citation bound to the last cited path (verified: a review citing `x.sh:807` followed by the trailer yields citations `x.sh:1,2,3,4,0`). Any manifest defect anchored within ±3 of a small count in the last-cited file is credited for free, and `details.citations` is inflated on every graded review.
**File:** `head/evals/graders/recall-vs-defects.sh:74`
**Suggestion:** add `"`, `'` and `}` / `{` to the lookbehind class (or require the bare form to be preceded by whitespace, a backtick or a line start), and add an RG case that a review body plus the trailer credits nothing from the trailer.
**Benefit:** keeps recall a measure of the review, not of its machine trailer.

- **LOW** (confidence: medium) `head/evals/graders/recall-vs-defects.sh:73` — the comma continuation `(?:\s*,\s*RNG)*` has no boundary after the number, so prose such as `a.sh:40, 3 of which…` credits line 3 of `a.sh` (verified). Low because it only widens detection by a stray small number.
**Suggestion:** require the continuation to be followed by `,`, `)`, ``` or end-of-token rather than a space-word, or cap the list to numbers not followed by a letter.

### 2. Tests that depend on environment or transient state

- **MEDIUM** (confidence: medium) `head/tests/unit/skill-capabilities.bats:850` — `yq -r '… (.value.write_capable | tostring) …'` uses `tostring`, which Mike Farah yq v4.40.5 (the yq the framework documents as its requirement, "yq v4") rejects: `Error: 1:70: invalid input text "tostring)) | joi..."`; SC-T-AGENT-7 fails before it reaches the assertion while SC-T-AGENT-8/9 pass. Confidence medium because a newer yq may accept it; the repository's other yq expressions avoid jq-only operators.
**Suggestion:** build the string with jq (`yq -o=json … | jq -r 'to_entries | map(.key + "=" + (.value.write_capable|tostring)) | join(" ")'`) or compare with `yq -e` per key.

- **MEDIUM** (confidence: high) `head/.claude/adapters/tests/test_anthropic_catalog_floor.py:349-350` — the new test pins `ceiling_calibration.source == "conservative_default"` and `calibrated_at is None` for `claude-opus-5-5`, while the catalog comment at `head/.claude/defaults/model-config.yaml:491-492` (the `loa:shortcut` upgrade trigger) tells the operator to run `tools/ceiling-probe-live.py --write-catalog`, whose first success rewrites exactly those two fields. Performing the documented follow-up turns the suite red. (Raised by the companion dissent voice, DISS-C-007; confirmed in the test body.)
**Suggestion:** assert the invariant that survives calibration (`"long_context" not in pricing`, chain head, `probed_ceiling` present) and assert `calibrated_at is None` only while `source == "conservative_default"`.

### 3. Permission-rule grammar edge cases

- **LOW** (confidence: low) `head/.claude/scripts/check-permissions.sh:235` — `rule_key "$perm"` runs unguarded under `set -euo pipefail`; it returns 1 for anything that is not `Bash(...)`, so a future non-Bash requirement aborts the preflight mid-report. Related (companion dissent DISS-C-001/002): the loaders at `:198` and `:202` now `continue` past non-Bash allow/deny rules that the previous exact-string match accepted, and the base derivation at `:237` assumes a wildcard requirement (an exact `=git push` key yields the unmatchable base `*=git`). No live impact: every current requirement is a `Bash(…:*)` rule (lines 50-78).
**Suggestion:** `rule_key "$perm" || RULE_KEY="=$perm"` in all three places, and a bats case with one non-Bash requirement/allow pair.

### 4. Catalog and budget

- **LOW** (confidence: low) `head/.claude/defaults/model-config.yaml:509` — `cache_read_per_mtok: 200000` is 0.05× of the $4 input price; every other Anthropic entry except Fable 5.1 follows the 0.1× rule and the test adds a second exception on the strength of the entry comment alone ("platform.claude.com pricing, read 2026-10-05"). Worth a second pair of eyes on the vendor page before the cost ledger prices real runs with it.
**Suggestion:** link the pricing-page row in `catalog-evidence.md` next to the Fable exception.

- **LOW** (confidence: high) `head/tools/check-prompt-budget.sh:53` — `LOA_LIMIT` is raised to 10,240 B and the reverted `CLAUDE.loa.md` is 10,225 B: 15 bytes of headroom, so the next one-line edit fails PB-9. Acceptable if that is the intended fence; worth stating in the budget comment.

### 5. Implement gate mode semantics

- **LOW** (confidence: medium) `head/.claude/hooks/compliance/implement-gate.sh:113-117` — `implement_gate.mode: authoritative` is now a bare operator toggle that makes the gate trust the model-authored `tool_input.active_skill` (lines 122-137), with the key deliberately undocumented (IG-11) and the former `compliance.mode.change` audit event removed. The design (D-4.4) is sound as a default, but the name reads as the stricter mode and nothing records that the weaker mode is active. (Companion dissent DISS-C-004.)
**Suggestion:** emit one `audit.jsonl` event when the non-default mode is selected, or rename the key to say what it trusts.

### 6. Documentation

- The README and `docs/migration/v2.0-model-generation-floor.md` carry the cycle-126 addendum; no CHANGELOG file is in the diff although the last commit message references a CHANGELOG figure. Not blocking for this review; confirm the CHANGELOG entry lands with the release notes.

---

## Cross-Model Observations

Envelope: `grimoires/loa/a2a/sprint-1/adversarial-review.json` — two voices succeeded (primary gpt-5.5-pro answered by codex-headless: clean; companion claude-headless: 7 ADVISORY). Triage of the companion's advisory findings:

- DISS-C-001 / DISS-C-002 (check-permissions non-Bash rules, exact-requirement base) — folded into Observation 3 (LOW).
- DISS-C-003 (`_ig_base` assignment aborts under `set -e`) — not a defect: the hook runs without `set -euo pipefail` by design (`head/.claude/hooks/compliance/implement-gate.sh:22`); verified IG-1..IG-11 pass with the file absent.
- DISS-C-004 (authoritative mode trusts a model-authored field) — folded into Observation 5 (LOW).
- DISS-C-005 (alias defaults may hit vendor endpoints) — not a defect: `flatline-proposal-review.sh:182,233` and `flatline-validate-learning.sh:264,315` call `call_flatline_chat`, which dispatches through `model-invoke` (cheval) where `reviewer`/`opus` are catalog aliases; the catalog-driven `model-adapter.bats` MA-4 passes.
- DISS-C-006 (fallback `MODEL_TO_PROVIDER_ID` lacks `cheap`, `gpt-5.5`, …) — not a defect: `head/.claude/scripts/flatline-orchestrator.sh:992` falls back to the raw name (`${MODEL_TO_PROVIDER_ID[$model]:-$model}`), which cheval resolves from the catalog.
- DISS-C-007 (test pins the uncalibrated state) — accepted as Observation 2 (MEDIUM).

## Rejected dissent payloads

None — `metadata.rejected_summary` is empty and no `adversarial-rejected-review*.jsonl` sidecar exists.

---

## Incomplete Tasks

None. Task 1.1 (the change in `pr/head.diff`) was reviewed in full.

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":3,"low":5},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T06:29:53Z"} -->
