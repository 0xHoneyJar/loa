# Sprint Plan: Bridgebuilder Findings — The Hygiene Sprint (Iteration 2)

> Cycle: cycle-024 | Source: [Bridgebuilder Review of PR #353](https://github.com/0xHoneyJar/loa/pull/353)
> Previous: Sprints 1-2 committed (adapter fix, scoring engine, cleanup hook)
> This sprint: Address review findings BB-F3, BB-F5, BB-F7, BB-F8

## Sprint Structure

1 sprint, 5 tasks. All changes are refinements to code already committed in Sprints 1-2.

| Sprint | Focus | Files | Est. Lines |
|--------|-------|-------|------------|
| Sprint 3 | Bridgebuilder findings: regex safety, confidence signal, decision trails | 3 files | ~35 |

---

## Sprint 3: Bridgebuilder Review Findings

**Goal**: Address all actionable findings from the Bridgebuilder review — harden the regex matching in the cleanup hook, add a confidence signal to degraded consensus, and document decision boundaries at critical logic points.

### Task 3.1: Cleanup Hook — Array-Based Credential Pattern Matching (BB-F7)

**File**: `.claude/hooks/hygiene/settings-cleanup.sh`
**Finding**: [BB-F7, Medium, Security] Regex construction fragility — concatenating patterns with `|` is fragile and mixes PCRE (jq) with ERE (grep) dialects.

**Changes**:
1. Replace the `combined_pattern` string concatenation loop (lines 71-79) with a JSON array passed to jq
2. Use `jq`'s `any()` with pattern array instead of a single concatenated regex string
3. Align post-cleanup scan (lines 105-111) to use the same pattern source for consistency

**Before** (fragile concatenation):
```bash
combined_pattern=""
for pat in "${CREDENTIAL_PATTERNS[@]}"; do
    combined_pattern="${combined_pattern}|${pat}"
done
# ... jq test($cred_pattern) ...
```

**After** (array-based matching):
```bash
pattern_json=$(printf '%s\n' "${CREDENTIAL_PATTERNS[@]}" | jq -R -s 'split("\n") | map(select(length > 0))')
# ... jq with any(patterns[]; test(.)) ...
```

**Acceptance**:
- Same filtering behavior as before (no functional change)
- Pattern list is inspectable as JSON array
- No string concatenation of regex fragments

### Task 3.2: Scoring Engine — Confidence Signal for Degraded Consensus (BB-F5)

**File**: `.claude/scripts/scoring-engine.sh`
**Finding**: [BB-F5, Praise+Suggestion] When one model is degraded, `model_agreement_percent` is misleading — if GPT is empty, all items come from Opus only, so "agreement" is trivially 100% but meaningless.

**Changes**:
1. Add a `confidence` field to the consensus output JSON: `"full"` | `"degraded"` | `"single_model"`
2. Logic:
   - `"full"` — both models produced valid scores
   - `"degraded"` — one model had invalid JSON but the other had valid `.scores` array
   - `"single_model"` — one model had valid JSON but produced 0 scored items

**After** (in final output object):
```jq
confidence: (
    if ($gpt_degraded or $opus_degraded) then "degraded"
    elif (($gpt.scores | length) == 0 or ($opus.scores | length) == 0) then "single_model"
    else "full"
    end
),
```

**Acceptance**:
- Normal run → `"confidence": "full"`
- One model invalid JSON → `"confidence": "degraded"`
- One model valid JSON but empty scores → `"confidence": "single_model"`

### Task 3.3: OpenAI Adapter — Decision Trail Comment (BB-F8a)

**File**: `.claude/adapters/loa_cheval/providers/openai_adapter.py`
**Finding**: [BB-F8, Low, Documentation] No documentation on when `legacy_prefixes` needs updating, or what happens with hypothetical models like `gpt-4.5-turbo`.

**Change**: Add decision documentation comment to `_token_limit_key`:
```python
@staticmethod
def _token_limit_key(model: str) -> str:
    """Return the correct token limit parameter for the model.

    GPT-4o and earlier use 'max_tokens'.
    GPT-5.2+ use 'max_completion_tokens' (OpenAI API deprecation).

    Decision: Prefix matching chosen over version map because all known
    legacy models start with 'gpt-4' or 'gpt-3'. New model families
    (GPT-5.x, o1, etc.) default to the current API parameter.
    Update legacy_prefixes only if OpenAI releases a model with a new
    prefix that still requires the deprecated 'max_tokens' parameter.
    """
```

**Acceptance**: Docstring includes decision rationale and update trigger

### Task 3.4: Scoring Engine — Dedup Decision Trail Comment (BB-F8b)

**File**: `.claude/scripts/scoring-engine.sh`
**Finding**: [BB-F8, Low, Documentation] + [BB-F3 note] No documentation on why exact-match dedup is used vs fuzzy matching, or when to reconsider.

**Change**: Add comment above the dedup line:
```bash
# Deduplicate skeptic concerns by exact .concern text match.
# Exact match is sufficient because models reviewing the same document typically
# echo each other's phrasing. If the Hounfour scales to 3+ diverse models with
# varied prompting, consider fuzzy dedup (e.g., cosine similarity on concern text
# or a canonical concern ID assigned upstream in the skeptic prompt).
```

**Acceptance**: Comment explains the decision and documents the reconsideration trigger

### Task 3.5: Verify All Bridgebuilder Findings Addressed

**Verification checklist**:
1. `settings-cleanup.sh` — credential patterns passed as JSON array to jq, no string concatenation
2. `scoring-engine.sh` — `confidence` field present in consensus output
3. `openai_adapter.py` — `_token_limit_key` docstring includes decision trail
4. `scoring-engine.sh` — dedup comment documents exact-match decision
5. Bash syntax check passes on all modified scripts
6. Python import check passes on adapter
7. No functional regressions (existing acceptance criteria still hold)

---

## Bridgebuilder Findings Traceability

| Finding | Severity | Category | Sprint Task | Status |
|---------|----------|----------|-------------|--------|
| BB-F1: Protocol version negotiator | Praise | Architecture | Task 3.3 (add decision trail) | Addressed |
| BB-F2: Byzantine consensus fix | High→Fixed | Correctness | Sprint 1 (already committed) | Done |
| BB-F3: Skeptic dedup exact-match | Medium | Correctness | Task 3.4 (document decision) | Addressed |
| BB-F4: Mode display fix | Low | Correctness | Sprint 1 (already committed) | Done |
| BB-F5: Degraded mode signal | Praise+Suggestion | Architecture | Task 3.2 (add confidence field) | Addressed |
| BB-F6: Permission GC design | Praise | Security | No change needed | Done |
| BB-F7: Regex construction fragility | Medium | Security | Task 3.1 (array-based matching) | Addressed |
| BB-F8: Decision trail gaps | Low | Documentation | Tasks 3.3 + 3.4 | Addressed |

---

## Commit Strategy

| Sprint | Commit Message |
|--------|---------------|
| Sprint 3 | `fix(bridge-review): address Bridgebuilder findings — regex safety, confidence signal, decision trails` |
