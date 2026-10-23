# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md

---

## Overall Assessment

The change under review is `pr/head.diff` (88 files): the `opus` alias moves to the new `claude-opus-5-5` catalog entry, `cheap` to `claude-sonnet-5`, every Anthropic catalog entry gains a `model-permissions.yaml` row, the implement gate becomes heuristic-by-default with an evidence recorder, `check-permissions.sh` gets the second rule grammar, the eval recall grader goes to 1.1.0, and the Sprint 3 instruction-diet edits are reverted per the pre-registered A/B rule.

Most of the change verifies cleanly against the head tree: the catalog checksum matches (`759dfd3f…`), the `@loa-managed` hash on `CLAUDE.loa.md` recomputes to the header value (`99948d56…`), all 16 served Anthropic/Bedrock entries have a permissions row, the golden NEVER/ALWAYS tables match the rendered `CLAUDE.loa.md` rows byte-for-byte, and the PR's own `check-permissions.bats` (13/13), `implement-gate.bats` (11/11), `instruction-diet-revert.bats` (4/4) and `flatline-model-validation.bats` (20/20) pass when run against `pr/head/`. `model-residue.bats` RES-6 and `skill-capabilities.bats` fail here only because the head snapshot lacks untouched directories they grep.

One defect blocks: grader 1.1.0's new bare `:N` citation rule matches the JSON pairs inside the LOA-VERDICT trailer that every Loa review ends with, so a defect anchored near the top of the last-cited file is credited without being cited. Reproduced against `pr/head/` and `pr/base/`: a review citing only `a.sh:400` scores recall 1.0 on head (D-early at line 3 "detected") and 0.5 on base. Because the Task 4.8 replay A/B revert decision was made with this grader, the metric it rests on is inflated in exactly the direction that favours the revert.

The Phase 2.5 dissent ran with two voices (codex-headless primary, claude-headless companion, `consensus`, zero rejected payloads). Of its four advisory findings, two are confirmed below (long_context tier inconsistency; unchecked `rule_key` return), and two are dismissed after checking the head files (the alias defaults route through `call_flatline_chat` → model-invoke, which is alias-aware; the test module contains no calibrated-5.5 assertions — `grep foreign|probed_headless` returns nothing).

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Eval grader — trailer JSON counted as citations

- **HIGH** (confidence: high) `head/evals/graders/recall-vs-defects.sh:74` — the bare-`:N` alternative `(?<![A-Za-z0-9_./:]):(?P<bare>\d…)` is entered at every `"key":N` pair of the LOA-VERDICT trailer (`"critical":0`, `"high":0`, `"medium":1`, `"low":2`, `"excluded":0`), because `"` is not in the negative lookbehind class and the digit follows the colon directly; each one binds to the most recent cited path (`head/evals/graders/recall-vs-defects.sh:84`) as a phantom citation at line 0, 1 or 2.
**File:** `head/evals/graders/recall-vs-defects.sh:74`
**Issue:** Reproduced with a two-defect manifest (anchors 3 and 400) and a review that cites only `head/.claude/scripts/a.sh:400` followed by a standard trailer:

```
head 1.1.0: {"pass": true,  "score": 100, "detected": ["D-early","D-late"], "citations": 6}
base 1.0.0: {"pass": false, "score": 50,  "detected": ["D-late"], "missed": ["D-early"], "citations": 1}
```

Any defect whose anchor (or any `anchors[]` site) lies within lines 0–5 of the last file the review cites is credited unconditionally; `details.citations` is inflated by five on every trailer-bearing review; and on a clean fixture without a trailer the FP count is unaffected only by accident (no trailer → no JSON pairs).
**Why This Matters:** This grader is the measurement behind the pre-registered replay A/B rule that Task 4.8 used to revert the Sprint 3 trim and twelve rationales in this same PR, and it is the fixture corpus's recall metric going forward. Recall it reports is biased upward for every reviewer that emits the mandated trailer, which is every Loa reviewer. RG-14 covers a bare `:N` with no preceding path and `:N` glued to a word, but no test places the trailer after a citation, which is the shape of every real review.
**Required Fix:** Exclude a quote (and ideally `{`, `,`) from the character immediately before the bare colon, e.g. extend the lookbehind to `(?<![A-Za-z0-9_./:"'{,])`, or strip the verdict-trailer HTML comment from `text` before `CITE.finditer` (the trailer is already parsed separately at the `tm = re.search` line). Add an RG test: `review 'a.sh:400'` plus the standard trailer must yield `citations == 1` and must not detect a defect anchored at line ≤ 5 of `a.sh`. Re-run the replay A/B numbers with the corrected grader and record whether the Task 4.8 revert decision stands.

---

## Observations

### 1. Catalog consistency

- **MEDIUM** (confidence: high) `head/.claude/defaults/model-config.yaml:470-509` — the new `claude-opus-5-5` entry omits `pricing.long_context`, citing the vendor statement that "Claude 4.6 and later models … include the full 1M token context window at standard pricing", while its first fallback hop `claude-opus-5` (`head/.claude/defaults/model-config.yaml:562`) and `claude-sonnet-5` / `claude-fable-5` / `claude-fable-5-1` keep a `long_context` tier at 2.0× input / 1.5× output (`verified: false`). The same vendor source cannot support both. `head/.claude/adapters/tests/test_anthropic_catalog_floor.py:348` now pins the absence on 5.5 while `:326` pins the presence on FIVE_FAMILY, locking the contradiction in.
**File:** `head/.claude/defaults/model-config.yaml:470-509`
**Suggestion:** Decide the long-context question once for the 4.6+ family: either drop the tier from the four FIVE_FAMILY entries (and update `test_five_family_declares_the_beta_header_list_and_the_long_context_tier`), or add it to 5.5 with `verified: false` and record in catalog-evidence.md why the vendor statement is not trusted.
**Benefit:** A request that falls from `opus` to its first hop above 200K input is otherwise metered at twice the primary's cost; budget guards tuned on one hop misfire on the other.

### 2. Agent-type registry coverage

- **MEDIUM** (confidence: medium) `head/.claude/data/agent-types.yaml:10-27` — the file enumerates eight agent types; the read-only `chart-researcher` project agent (`.claude/agents/chart-researcher.md`, tools Read/Grep/Glob/WebFetch) is not among them. `head/tests/unit/skill-capabilities.bats:854` iterates every `.claude/agents/*.md` and fails on an unlisted one, so SC-T-AGENT-7 is red on any checkout that carries that agent definition. Confidence is medium because the head snapshot holds only touched files; the install this review runs on has that agent and lists it in a later revision of the same YAML.
**File:** `head/.claude/data/agent-types.yaml:27`
**Suggestion:** Add `chart-researcher: {write_capable: false}` (and any other `.claude/agents/*.md` present at merge time); the validator's behaviour is already correct for an unlisted type (treated as not write-capable), so this is a test-truth gap, not a fence gap.
**Benefit:** Keeps SC-T-AGENT-7 green and the registry authoritative for every project agent.

### 3. Permission checker robustness

- **LOW** (confidence: high) `head/.claude/scripts/check-permissions.sh:235` — `rule_key "$perm"` is a bare statement under `set -euo pipefail`; `rule_key` returns 1 for anything not shaped `Bash(…)` (`:164`). All sixteen required rules are `Bash(…:*)` today, so this is a dead path, but the first non-Bash requirement added to `REQUIRED_*` aborts the whole preflight with exit 1 and no report (or, if `set -e` is ever relaxed, reuses the previous iteration's `RULE_KEY`).
**Suggestion:** `rule_key "$perm" || { missing_permissions+=("$perm"); continue; }` and reset `RULE_KEY=""` at the top of `rule_key`.
**Benefit:** The preflight degrades to a named missing rule instead of a silent abort.

### 4. Prompt budget headroom

- **LOW** (confidence: high) `head/tools/check-prompt-budget.sh:53` — the `CLAUDE.loa.md` limit is raised 9,216 → 10,240 B and the reverted file is 10,225 B: 15 bytes of headroom. The next constraint-rationale regeneration that lengthens a `why` string fails PB-4 / the budget check.
**Suggestion:** Either set the limit from the file's measured size plus a stated margin (and say so in the comment), or trim non-rendered whitespace in the managed file.
**Benefit:** Avoids a budget failure on the next routine regeneration.

### 5. Undocumented operator key

- **LOW** (confidence: high) `head/.claude/hooks/compliance/implement-gate.sh:115` — `implement_gate.mode: authoritative` is the only way to select the mode in which a model-authored `tool_input.active_skill` of `implement`/`run`/`bug` allows an App Zone write with no RUNNING state, and `head/tests/unit/implement-gate.bats:151-154` asserts the key stays out of `.loa.config.yaml.example`, `docs/` and `README.md`. The rationale (no harness signal exists) is recorded in the test header only.
**Suggestion:** Document the key with its warning in `.loa.config.yaml.example` (the config reference operators read), or remove the opt-in until a harness signal exists. If it must stay undocumented, record the decision in NOTES.md rather than only in a bats header.
**Benefit:** Operators can see the trade-off before opting in; a hidden key that weakens a fence is otherwise a Karpathy Think-Before-Coding gap.

### 6. Documentation

- **LOW** (confidence: low) `head/README.md:24` — the PR documents the cycle-126 changes in README "Unreleased" and the migration addendum (`head/docs/migration/v2.0-model-generation-floor.md:231-275`), but no `CHANGELOG` entry is in the diff although the final commit message references a CHANGELOG figure. Confidence is low because the head snapshot shows touched files only.
**Suggestion:** Confirm a CHANGELOG entry for sprint-250 tasks 4.1–4.8 exists at merge, or state that README "Unreleased" is the project's changelog surface.

---

## Rejected dissent payloads

None — `metadata.rejected_summary` is empty and `rejected_sidecars` is `[]` in `grimoires/loa/a2a/sprint-1/adversarial-review.json` (two voices, `consensus`, four ADVISORY findings; DISS-C-002 and DISS-C-001 confirmed and recorded above, DISS-C-003 and DISS-C-004 dismissed after checking the head files).

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

Sprint success criterion: "review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict".

| Criterion | Status | Notes |
|-----------|--------|-------|
| `opus` → `claude-opus-5-5`, `cheap` → `claude-sonnet-5` across catalog, generated maps, bash maps, example config, docs | Pass | `head/.claude/defaults/model-config.yaml:1102,1106`; generated maps, `model-adapter.sh`, `flatline-orchestrator.sh`, `red-team-model-adapter.sh` agree; RES-1/2/3/4/5/7 pass |
| Catalog entry vendor-sourced ($4/$20, 1M/128K, cache read 0.05×) with conservative ceiling marked `loa:shortcut` | Pass | `head/.claude/defaults/model-config.yaml:470-509`; marker carries the upgrade trigger; long_context tier inconsistency noted (Obs. 1) |
| Every Anthropic catalog entry has a `model-permissions.yaml` row | Pass | 16/16 served entries present (`test_every_anthropic_catalog_entry_has_a_row`) |
| Implement gate heuristic by default; `.run/` never selects authoritative; evidence recorded once from lead session | Pass | `implement-gate.bats` 11/11 on head tree |
| `check-permissions.sh` second rule grammar | Pass | `check-permissions.bats` 13/13 on head tree; dead-path note (Obs. 3) |
| Grader 1.1.0 parser fixes (paren, comma continuation, bare `:N`) | Fail | Bare `:N` matches trailer JSON; see Changes Required 1 |
| Task 4.8 revert of CLAUDE.loa.md trim and twelve rationales | Pass | Golden tables and `IDR-1..4` match; managed hash verifies; budget headroom 15 B (Obs. 4) |
| License fixture freshness covers the 12-hour window | Pass (unverified in sandbox) | `ensure_license_fixtures.sh:46-60` checks both windows; LFF tests need the generator, not present in the head snapshot |
| Schema v3 typed for `probed_ceiling`, `account_limits`, `headless_timeout_seconds`, `params.beta_headers` | Pass | `head/.claude/data/schemas/model-config-v3.schema.json:148-180` |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [x] Input validation and sanitization present — `lib-content.sh` control-byte scrub, `rule_key` grammar, canonical-decimal index guard
- [x] Authentication/authorization correct — implement gate no longer promotes a model-authored field to authoritative without an explicit opt-in (opt-in is undocumented, Obs. 5)
- [x] No SQL/XSS injection vulnerabilities — n/a
- [x] Dependencies secure — no new dependencies
- [x] Error messages don't leak sensitive data — `model-adapter.sh` forwards only the agy argv WARN from cheval stderr

---

## Code Quality Summary

**Strengths:**
- Catalog, checksum, generated twins (bash maps, BB TS/JS, build manifest) and managed-file hash are all regenerated consistently; nothing hand-edited drifts.
- The implement gate change removes the `.compliance-mode` cache and the self-promoting feature flag, a real simplification with a fixture corpus (`expected.tsv`) that pins both modes.
- Permission grammar is pure parameter expansion with a thorough CP-13 fuzz table.

**Areas for Improvement:**
- The grader regression above shows the citation parser needs a negative test built from a real review shape (citation + trailer).
- Two artifacts in the same PR assert opposite long-context pricing for the same vendor family.

Complexity: no function over 50 lines added; nesting ≤ 3; no duplicate blocks beyond the registry rows, which are data. `Lean already. Ship.` once the grader is fixed.

---

## Next Steps

1. Fix the bare-`:N` lookbehind (or strip the trailer before citation parsing) and add the citation-plus-trailer regression test.
2. Re-run the replay A/B with the corrected grader and record whether the Task 4.8 revert stands.
3. Resolve the long_context tier question for the 4.6+ family in one direction.
4. Update the report in `grimoires/loa/a2a/sprint-1/reviewer.md` and request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":2,"low":4},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T15:55:00Z"} -->
