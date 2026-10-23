# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)

---

## Overall Assessment

The change under review is `pr/head.diff` (88 files: cycle-126 sprint-250 tasks 4.1–4.8). Most of it is sound and was verified mechanically rather than from the report:

- `model-config.yaml.checksum`, the two manifest SHA256SUMS rows and the two bridgebuilder `.build-manifest.json` hashes all match the head files.
- `generated-model-maps.sh` regenerates byte-identically from the head catalog (`gen-adapter-maps.sh --dry-run`, comments excluded).
- The NEVER/ALWAYS tables in `CLAUDE.loa.md` re-render identically from `constraints.json` with matching section hashes (`74e01d57cbb517af`, `bcb45bf913806ff2`); the `@loa-managed` header hash verifies `VALID`.
- Every Anthropic catalog entry (direct and Bedrock) has a `model-permissions.yaml` row whose scopes, trust level, execution mode and capabilities equal the 4.7 reference row.
- The PR's own suites pass where their inputs are inside the PR: check-permissions (13/13), implement-gate (11/11), compliance-hook (14/14), model-residue (6/7; RES-6 needs skill dirs outside the PR), instruction-diet-revert (4/4), flatline-model-validation and -allowlist, schema V3 (skipped: parent schema outside the PR), recall grader (15/17; RG-16/17 need fixture trees outside the PR), model-adapter MA-1/MA-2 (MA-3..6 need `lib/model-resolver.sh`, outside the PR), validate-artifact bd-8ndx (3/3).

What blocks the merge is one design defect the PR's own analysis makes indefensible: it establishes that `tool_input.active_skill` is model-authored, then keeps (and pins with a new fixture corpus) an opt-in mode in which that model-authored string silently allows App Zone writes. Six medium findings follow: a catalog that now contradicts itself on long-context pricing, a permission grammar that misses the universal rule in both directions, a `mktemp` hard-fail regression in `model-adapter.sh`, a half-applied constraint-rationale revert whose regeneration would break the budget this PR raised, output budgets of 300/500 tokens now pointed at adaptive-thinking models, and a hook output shape the new tests entrench.

Adversarial dissent (Phase 2.5) ran on `pr/head.diff` with two voices (gpt-5.5-pro primary via codex-headless, claude-headless companion); status `clean`, six ADVISORY findings, zero rejected payloads. The advisory findings were triaged below; three were confirmed against head and are folded into findings here, one was dismissed as unreachable.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Security / Compliance fence — the opt-in mode trusts a model-authored field

- **HIGH** (confidence: high) `head/.claude/hooks/compliance/implement-gate.sh:128` — with `implement_gate.mode: authoritative` set, a Write/Edit payload whose model-authored `tool_input.active_skill` is `implement`, `bug`, `run` or `simstim` exits 0 silently, so the model being fenced self-certifies its own App Zone write and the fence's stated FAIL-ASK posture becomes fail-open.
**File:** `head/.claude/hooks/compliance/implement-gate.sh:128` (allow case), `:10-13` (header: "tool_input is model-authored"), `:114-117` (selector), `head/tests/fixtures/pretooluse-payloads/expected.tsv:8-9,11` (`allow` pinned for forged payloads), `head/tests/unit/implement-gate.bats:104` (IG-7 asserts those allows)
**Issue:** The PR's new header text is correct: the PreToolUse payload carries no harness-set skill field and `tool_input` is written by the model. The same file then keeps the authoritative branch that reads exactly that field and allows on it. The old selector (`.run/platform-features.json`) was removed, but the allow path survives behind an undocumented config key, and the new corpus (`expected.tsv` column `authoritative`) and IG-7 lock `allow` in as the expected outcome for `write-src-active-implement.json`, `edit-lib-active-bug.json` and `write-src-subagent-run.json`. IG-5's claim "a forged active_skill Write payload does not flip the gate" holds only in the default mode. The removed `compliance.mode.change` audit row also means a switch into the weaker mode now leaves no trace in `.run/audit.jsonl`. The dissent voice raised the same point independently.
**Why This Matters:** This hook is the mechanical fence for C-PROC-001 ("NEVER write application code outside `/implement`"). A fence whose allow condition is a string the fenced party writes is not a fence; under the opt-in, unreviewed application code reaches the tree with no ask and no log. Mitigation today is that the key is opt-in and undocumented (IG-11 enforces the latter), which is why this is HIGH rather than CRITICAL, but "undocumented" is not a control.
**Required Fix:** Make the claim tighten-only: a non-implementation claim may add an ask, an implementation claim must fall through to the heuristic exactly like an absent field (never `exit 0`). Update `expected.tsv` (rows 8, 9, 11 → `ask`) and IG-7 accordingly, or remove the authoritative branch and the config key outright. Re-add a one-row audit log when a claim influences the decision.
**Reference:** CWE-807 (Reliance on Untrusted Inputs in a Security Decision); CLAUDE.loa.md C-PROC-001 rationale ("implement-gate.sh fail-asks Write/Edit-tool App-Zone writes outside /implement//bug").

**Example:**
```bash
# Current (head/.claude/hooks/compliance/implement-gate.sh:127-131)
case "$active_skill" in
    implement|/implement|bug|/bug|run|/run|simstim|/simstim)
        exit 0
        ;;
esac

# Should be: a model claim never grants; it may only tighten
case "$active_skill" in
    implement|/implement|bug|/bug|run|/run|simstim|/simstim)
        ;;   # fall through to the heuristic below, exactly like an absent field
    *)
        echo '{"decision":"ask",...}'; exit 0 ;;
esac
```

---

## Observations

### 1. Catalog data — the pricing model now contradicts itself

- **MEDIUM** (confidence: high) `head/.claude/defaults/model-config.yaml:505-509` — the new `claude-opus-5-5` entry ships no `long_context` tier on the stated ground that "Claude 4.6 and later models … include the full 1M token context window at standard pricing" (`:476-478`), while `claude-opus-5` (`:558-566`), `claude-fable-5-1` and `claude-sonnet-5`, all "4.6 and later", keep the cycle-126 FR-1.9 tier of 2.0×/1.5× above 200K tokens in the same file; one of the two readings is wrong, so cost estimates above 200K are off by 2× on one side or the other.
**File:** `head/.claude/defaults/model-config.yaml:476-478`, `:505-509`, `:558-566`; `head/.claude/adapters/tests/test_anthropic_catalog_floor.py:69` (0.05× cache-read exception) and `:343` (test that pins "no long_context" for 5.5 only); `head/docs/migration/v2.0-model-generation-floor.md:246`
**Suggestion:** Decide once: either the vendor statement applies to the whole 1M family (drop the FR-1.9 tiers, or set `verified: false` → remove) or it does not (give 5.5 the same `reference`/unverified tier). The 0.05× cache-read price also departs from the 0.1× rule every other Anthropic entry follows; record the source line for both in `catalog-evidence.md` rather than only in a comment.
**Benefit:** Cost ledger and budget gates (`BudgetEnforcer`, dissent `budget_scale: diff`) price the same request consistently across the family.

### 2. Permission grammar — the universal rule is outside the grammar, in both directions

- **MEDIUM** (confidence: high) `head/.claude/scripts/check-permissions.sh:164-172` — a universal rule is never a key the lookup can hit: bare `Bash` fails the `Bash(…)` guard (`:164`) and is skipped, `Bash(*)` becomes the exact key `=*`, `Bash(:*)` becomes the empty wildcard key `*`; so `"deny": ["Bash"]` or `["Bash(:*)"]` is ignored and the checker reports all 16 requirements found (Claude Code then denies every Bash call mid-run), and `"allow": ["Bash"]` is reported as 16 missing (run preflight refuses to start a run that would in fact succeed).
**File:** `head/.claude/scripts/check-permissions.sh:164`, `:167-172`, `:238-247`; `head/tests/unit/check-permissions.bats:209-216` (the 21-shape deny fuzz set has no universal shape); `head/docs/migration/v2.0-model-generation-floor.md:258-262` ("reads permission rules the way Claude Code does … Deny still wins over allow")
**Suggestion:** Give `rule_key` an `ALL` key for bare `Bash`, `Bash(*)` and an empty wildcard body; check `deny_by[ALL]` before the per-key lookups and `allow_by[ALL]` with them; add the three shapes to CP-13. Verified with the function extracted from head: `Bash → SKIPPED`, `Bash(*) → =*`, `Bash(:*) → *`.
**Benefit:** The documented "deny wins" contract holds for the one rule shape operators most often use to lock Bash down, and blanket-allow operators are not told to add 16 redundant rules. (Pre-existing gap in the old matcher too, but this PR rewrote the grammar and documents parity.)

### 3. Shell robustness — `mktemp` failure now aborts the model call

- **MEDIUM** (confidence: high) `head/.claude/scripts/model-adapter.sh:656` — `err_file="$(mktemp …)"` runs under `set -euo pipefail` (`:33`); with an unusable `TMPDIR` the assignment fails and the script exits before `model-invoke` is called, where the previous code (`2>/dev/null`) completed the hop; the file is also never removed if the shim is killed between `:656` and `:659`.
**File:** `head/.claude/scripts/model-adapter.sh:33`, `:655-659`
**Suggestion:** `err_file="$(mktemp … 2>/dev/null)" || err_file=""`; fall back to the old discard path with a one-line WARN when empty; `trap 'rm -f -- "$err_file"' EXIT` (chaining any existing EXIT trap) while the hop runs.
**Benefit:** A logging convenience (relaying one WARN line) cannot turn a working dispatch into a hard failure.

### 4. Constraint registry — the rationale revert is half-applied and would break the budget it raised

- **MEDIUM** (confidence: high) `head/.claude/loa/CLAUDE.loa.md:124` — the `agent_teams_constraints` block still carries the placeholder marker `hash:c020-teamcreate` and five "Why" cells that match neither the diet text nor the pre-diet text the PR restored in `constraints.json` (`:1235`, `:1256`, `:1277`, `:1298`, `:1319`); re-rendering the section from the registry (jq template `claude-loa-md-table.jq`) changes all five rows (773 → 1,263 bytes) and puts `CLAUDE.loa.md` at 10,715 bytes, over the 10,240-byte limit this PR set in `head/tools/check-prompt-budget.sh:53`.
**File:** `head/.claude/loa/CLAUDE.loa.md:124-130`; `head/.claude/data/constraints.json:1235,1256,1277,1298,1319`; `head/tools/check-prompt-budget.sh:53`; `head/tests/unit/instruction-diet-revert.bats:37` (IDR-3 checks the registry only) and `:61` (IDR-4 checks only the seven C-PROC rows)
**Suggestion:** Either regenerate the Agent Teams block (and size the budget for the generated file, or keep the budget and shorten elsewhere), or scope the revert to the seven rendered C-PROC rows and say so in the commit. Extend IDR-4 to every `@constraint-generated` block in the file so a "DO NOT EDIT — generated" block cannot drift with a fake hash. The file currently sits 15 bytes under the raised limit, so the next registry edit will trip PB-9 regardless.
**Benefit:** "generated from constraints.json" stays true, and `generate-constraints.sh` can be run without failing the prompt-budget gate.

### 5. Model retargeting — 300/500-token output budgets now land on adaptive-thinking models

- **MEDIUM** (confidence: medium) `head/.claude/scripts/flatline-validate-learning.sh:80-81` — the defaults move from non-thinking wire ids (`gpt-4o`, `claude-3-opus-20240229`) to the `reviewer`/`opus` aliases, but the calls keep `max_tokens` 300 (`:264`, `:315`) and 500 (`head/.claude/scripts/flatline-proposal-review.sh:182,233`; `head/.claude/scripts/flatline-learning-extractor.sh:317`); `opus` now resolves to Opus 5.5, whose catalog comment says "adaptive thinking always on" (`head/.claude/defaults/model-config.yaml:474`) and `cheap` to Sonnet 5 with `thinking_adaptive: true`, and thinking tokens are charged against `max_tokens`, so a 300-token reply can be exhausted by the thinking block and come back empty or truncated, which these scripts treat as a model failure.
**File:** `head/.claude/scripts/flatline-validate-learning.sh:80-81,264,315`; `head/.claude/scripts/flatline-proposal-review.sh:75-77,182,233`; `head/.claude/scripts/flatline-learning-extractor.sh:317`
**Suggestion:** Raise the per-call budgets for the Anthropic hops (or let `call_flatline_chat` pass no `--max-tokens` and take cheval's per-model default), and add one live or mocked check that a 300-token call on the `opus` alias returns non-empty text. The alias routing itself is fine: `call_flatline_chat` goes through `model-adapter.sh` → cheval, which resolves aliases (dissent finding 5 checked and dismissed on that point).
**Benefit:** The knowledge-extraction scripts keep working after the retarget instead of logging "Empty response from LLM".

### 6. Hook output contract — new fixtures pin a decision value the harness does not define

- **MEDIUM** (confidence: medium) `head/.claude/hooks/compliance/implement-gate.sh:230` — the ask reply is `{"decision":"ask","reason":…}` (also `:135`), but Claude Code's PreToolUse contract puts `allow|deny|ask` under `hookSpecificOutput.permissionDecision` and accepts only `approve|block` at top-level `decision`, so the gate's "ask" is not a recognised reply and the write may proceed as if allowed; the new `decision()` helper (`head/tests/unit/implement-gate.bats:35`) and `expected.tsv:5` pin this shape as the contract. Not introduced by this PR, but the PR's new corpus is the place it should have been caught.
**File:** `head/.claude/hooks/compliance/implement-gate.sh:135,230`; `head/tests/unit/implement-gate.bats:35`; `head/tests/fixtures/pretooluse-payloads/expected.tsv:5`
**Suggestion:** Emit `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"…"}}` and assert that shape in the corpus; verify once against the hooks reference the PR itself cites.
**Benefit:** The fence actually asks.

### 7. Smaller items

- **LOW** (confidence: high) `head/evals/graders/recall-vs-defects.sh:72-75` — the comma-continuation branch of `CITE` binds any following number to the cited path, so the sentence `a.sh:40, 2 of the 3 callers` credits `a.sh:2` (verified by running the regex); a decoy defect at line 2 ± 3 would be scored as detected.
**File:** `head/evals/graders/recall-vs-defects.sh:72-75`, `:78-92`
**Suggestion:** Require the continuation to be followed by a line-number context (end of token, `)`, `;`, newline) or cap it at numbers glued to the comma without a following word.

- **LOW** (confidence: high) `head/.claude/scripts/lib-content.sh:295` — `tr -d '\000-\037\177'` removes only C0 and DEL; UTF-8 C1 controls (`C2 80..9F`) and bidi/format code points (U+202E, U+200B) in a `diff --git` header path still reach the operator's stderr.
**File:** `head/.claude/scripts/lib-content.sh:295`
**Suggestion:** Strip to printable, or filter the C1/bidi sequences as well, since the test (CMP-278) only covers C0/DEL.

- **LOW** (confidence: high) `head/.claude/scripts/detect-platform-features.sh:35-36` — the `/loa` evidence line prints `active_skill_seen_at` and `active_skill_source` from `.run/platform-features.json` after `tr -d '[:cntrl:]'` only, and the refresh (`:66`) carries any value forward; a non-timestamp or a non-`tool_input` source is echoed as "evidence", and Unicode format characters survive `[:cntrl:]`.
**File:** `head/.claude/scripts/detect-platform-features.sh:35-36,66`
**Suggestion:** Accept only an ISO-8601 Z timestamp and the literal `tool_input`; print `none`/`unknown` otherwise; filter to printable ASCII.

- **LOW** (confidence: high) `head/.claude/scripts/validate-skill-capabilities.sh:110` — the ambient `AGENT_TYPES_FILE` variable redirects the write-capable allowlist, so any CI environment can swap the registry without a visible flag; and `:117` silently re-enables `general-purpose` when the file parses but no entry is `write_capable: true`.
**File:** `head/.claude/scripts/validate-skill-capabilities.sh:110,117`
**Suggestion:** Take the override as an explicit `--agent-types-file` argument (the test seam) and treat an all-false file as "nothing is write-capable", not as the default.

- **LOW** (confidence: medium) `head/.claude/scripts/check-permissions.sh:235` — `rule_key "$perm"` is a bare statement under `set -euo pipefail`; the first non-`Bash(…)` requirement added to `all_required` (a `Read(...)`/`WebFetch` rule) aborts the whole preflight with no report rather than being reported missing. Latent today (all requirements are `Bash(…)`); raised by the dissent voice and confirmed.
**File:** `head/.claude/scripts/check-permissions.sh:235`
**Suggestion:** `rule_key "$perm" || { missing_permissions+=("$perm"); continue; }`.

- **LOW** (confidence: medium) `head/.claude/scripts/flatline-orchestrator.sh:556` — the no-generated-maps stub allowlist now admits `cheap`, `gpt-5.5`, `gpt-5.5-pro` and `gemini-3.1-pro-preview`, but the fallback `MODEL_TO_PROVIDER_ID` (`:694-702`) has no rows for them; on that path the bare name is passed through (`${MODEL_TO_PROVIDER_ID[$model]:-$model}`) and works only because cheval resolves aliases. Dissent finding 6, confirmed as a mismatch, downgraded because the fallback is benign.
**File:** `head/.claude/scripts/flatline-orchestrator.sh:556,694-702`
**Suggestion:** Either add the rows or drop the names from the stub so the two fallback tables agree.

- **LOW** (confidence: high) `head/tests/unit/implement-gate.bats:151` — IG-11 asserts that `implement_gate` appears nowhere in `.loa.config.yaml.example`, `docs/` or `README.md`; a test that enforces an undocumented operator-facing key inverts the usual contract (operators cannot discover the mode they are expected to opt into or avoid).
**File:** `head/tests/unit/implement-gate.bats:151-154`
**Suggestion:** Document the key with its caveat, or remove the key (see Changes Required §1) and the test with it.

- **LOW** (confidence: medium) `head/.loa.config.yaml.example:2717` — the advisor tier still names `claude-opus-5` while `opus` moved to 5.5 (`:2024`) and `test_advisor_tier_points_at_opus_5` pins the former; if intentional, say so beside the alias comment, since the migration note presents 5.5 as "the current generation".
**File:** `head/.loa.config.yaml.example:2024,2717`
**Suggestion:** One comment line stating whether the advisor tier deliberately lags the alias.

- **LOW** (confidence: medium) `head/.claude/data/model-permissions.yaml:446` — `anthropic:claude-headless` is registered as `execution_mode: remote_model` with `command_execution: false`, yet it is a local `claude -p` process whose tool surface depends on `extra.allowed_tools`; the row documents the caveat in prose only.
**File:** `head/.claude/data/model-permissions.yaml:446-473`
**Suggestion:** Add a check (or a note in `test_trust_scopes.py`) that the headless adapter is invoked with `--tools ""` whenever this row is relied upon.

### 8. Process notes (not counted)

- `reviewer.md` is the PR description: six commit subjects, no `## AC Verification`, no test evidence. The REVIEW-INSTRUCTIONS state there is no implementation report for this evaluation, so the skill's automatic CHANGES_REQUIRED for a missing AC Verification was not applied; the verdict above rests on the code findings.
- The last commit subject refers to a CHANGELOG protocol figure, but no `CHANGELOG.md` is among the 88 touched files, so a CHANGELOG entry per task could not be verified.
- `qmd-context-query.sh` and `br` are not available in this workspace; both steps were skipped.

---

## Rejected dissent payloads

None. The envelope `grimoires/loa/a2a/sprint-1/adversarial-review.json` records `rejected_count: 0`, `rejected_summary: []`, `rejected_sidecars: []`; primary `gpt-5.5-pro` (answered by codex-headless) status `clean`, companion `claude-headless` status `succeeded` with zero findings. The six ADVISORY findings were triaged: #3 (model-authored claim) → Changes Required §1; #2 (bare `rule_key` under `set -e`) and #6 (stub allowlist vs provider map) → Observations §7; #4 (500-token budget on an adaptive-thinking model) → Observations §5; #5 (aliases sent verbatim to a provider) dismissed after confirming `call_flatline_chat` routes through cheval; #1 (exact-form requirement base derivation) dismissed as unreachable, every requirement is a `Bash(…:*)` rule.

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

| Criterion | Status | Notes |
|-----------|--------|-------|
| "report each defect it introduces with the file and line it sits on" | Pass | 1 high, 6 medium, 9 low above, each cited `head/<path>:<line>` |
| "give a merge verdict" | Pass | CHANGES_REQUIRED |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [ ] Input validation and sanitization present — model-authored `active_skill` trusted under opt-in (§1); C1/bidi bytes reach stderr (§7)
- [ ] Authentication/authorization correct — compliance fence fail-open under opt-in (§1)
- [x] No SQL/XSS injection vulnerabilities
- [x] Dependencies secure (no known CVEs) — no dependency changes
- [x] Error messages don't leak sensitive data

---

## Code Quality Summary

**Strengths:**
- Generated artifacts (bash maps, bridgebuilder registry, checksums, constraint tables) were regenerated correctly, not hand-edited.
- Every retarget is pinned by a test that reads the catalog rather than a literal (`model-residue.bats`, `cycle-124-effort-flag.bats`, `gen-bb-registry-codegen.bats`).
- The `rule_key` normaliser is fork-free and the 21-shape deny fuzz set is a good pattern; it just needs the universal shape.
- The license-fixture freshness fix and the `grep -q <<<` pipefail fix are correct and minimal.

**Areas for Improvement:**
- When analysis in a header says a signal is untrusted, the code below it must not grant on that signal.
- A "DO NOT EDIT — generated" block with a placeholder hash should fail a test, not pass one.
- New error-capture plumbing (`mktemp`) must degrade to the old behaviour, not abort.

---

## Next Steps

1. Address the HIGH in `implement-gate.sh` (tighten-only claim) and update `expected.tsv`/IG-7.
2. Resolve the catalog long-context inconsistency one way and fix the universal permission rule.
3. Re-run `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":6,"low":9},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T18:32:00Z"} -->
