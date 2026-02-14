# Sprint Plan: Hounfour Hardening — Bridge Review Residuals

> Source: Bridgebuilder Review iterations 1 & 2, PR #324
> Cycle: cycle-013 (continuation)
> PR: https://github.com/0xHoneyJar/loa/pull/324
> Bridge ID: bridge-20260214-e8fa94
> Global Sprint Counter: starts at 89
> Findings: 3 MEDIUM + 7 LOW remaining from 2 bridge iterations

## Context

PR #324 completed a 2-iteration bridge loop. Iteration 1 found 18 findings (1 HIGH, 5 MEDIUM, 5 LOW, 1 vision, 6 praise). Iteration 2 fixed 4 findings (BB-007, BB-010, BB-011, BB-013) and found 3 new LOWs. Flatline declared at -90.6% severity reduction.

This sprint plan addresses the **10 remaining actionable findings** — 3 MEDIUMs and 7 LOWs. All are improvements, not blockers. Organized by code-change risk: Sprint 1 handles functional changes, Sprint 2 handles test/docs hardening.

---

## Sprint 1: Code Hardening — Functional Fixes

**Goal**: Address all 3 MEDIUM findings and 2 LOWs that require functional code changes. These are correctness and robustness improvements to production code paths.

**Global Sprint**: sprint-89

### Task 1.1: Document sed Fallback Limitation + Add Edge Case Test (BB-004)

**Finding**: BB-004 (MEDIUM) — sed fallback in Step 5 of `normalize_json_response()` may miss the correct JSON when multiple fragments exist.

**File**: `.claude/scripts/lib/normalize-json.sh:91-102`

**Changes**:
- Add a function header comment on lines 91-92 documenting that Step 5 is a last-resort fallback that only fires when python3 is unavailable
- Note that the sed pattern `s/^[^{[]*//;s/[^}\]]*$//` is greedy and may select incorrect fragments
- Add test fixture `fixtures/mock-responses/multi-fragment.txt` containing: `"Result: {x} and also {"real": "json"}`
- Add test case verifying behavior (either extraction succeeds via earlier steps, or failure is graceful)

**Acceptance Criteria**:
- [ ] Function header documents Step 5 limitations explicitly
- [ ] New fixture `multi-fragment.txt` exercises the multi-fragment edge case
- [ ] Test passes (Step 4 python3 handles it correctly; if python3 unavailable, graceful failure)
- [ ] Existing tests still pass

---

### Task 1.2: Broaden LazyValue Exception Handling (BB-005)

**Finding**: BB-005 (MEDIUM) — `_get_auth_header()` catches only `(KeyError, OSError)` but LazyValue resolution may raise other types.

**File**: `.claude/adapters/loa_cheval/providers/base.py:183-189`

**Changes**:
- Broaden the exception catch to `except Exception as exc` with a descriptive "Failed to resolve auth credential" message
- Log the original exception type for debugging
- Add a docstring to the method documenting the LazyValue resolution contract: callers should expect `ConfigError` on any resolution failure

**Acceptance Criteria**:
- [ ] `_get_auth_header()` catches `Exception` (not just `KeyError, OSError`)
- [ ] Error message includes the original exception type name
- [ ] Docstring documents the LazyValue contract
- [ ] Existing behavior unchanged for KeyError/OSError cases
- [ ] The outer `cmd_invoke()` handler at line 314 remains as defense-in-depth

---

### Task 1.3: Persist --repo in Bridge State JSON (BB-008)

**Finding**: BB-008 (MEDIUM) — Bridge signal emissions don't include repo context. Consuming agents must discover repo from environment.

**File**: `.claude/scripts/bridge-orchestrator.sh:336-344`

**Changes**:
- Add `"repo": "$BRIDGE_REPO"` to the bridge state JSON `config` object (written by `init_bridge_state()`)
- When `BRIDGE_REPO` is empty, write `""` (already the case in current state)
- Signal consumers can now read repo from `.run/bridge-state.json` config.repo

**Acceptance Criteria**:
- [ ] `init_bridge_state()` writes `config.repo` field in bridge state JSON
- [ ] Field is populated from `--repo` argument when provided
- [ ] Field defaults to `""` when `--repo` not provided
- [ ] Bridge state JSON schema remains valid (no breaking changes)

---

### Task 1.4: Tighten sed Comment Pattern to Require Space Before # (BB-019)

**Finding**: BB-019 (LOW) — `sed 's/ *#.*//'` matches `#` with zero leading spaces, which is more aggressive than standard dotenv parsers.

**File**: `.claude/scripts/gpt-review-api.sh:785,792`

**Changes**:
- Change both occurrences from `sed 's/ *#.*//'` to `sed 's/ \+#.*//'` (require at least one space before `#`)
- This matches the behavior of standard dotenv libraries (direnv, dotenv-ruby, python-dotenv)
- Update the test fixture `inline-comment.env` to ensure it has a space before `#`

**Acceptance Criteria**:
- [ ] Both `.env` and `.env.local` parsing use `sed 's/ \+#.*//'`
- [ ] Values containing `#` without a preceding space are preserved (e.g., hypothetical `sk-abc#def` stays intact)
- [ ] Test 5 in `test-env-loading.sh` still passes with space-prefixed comment
- [ ] All existing env loading tests pass

---

### Task 1.5: Randomize Allowlist Sentinel Suffixes (BB-015)

**Finding**: BB-015 (LOW) — Deterministic `__ALLOWLIST_SENTINEL_N__` format has theoretical collision risk with real content.

**File**: `.claude/scripts/bridge-github-trail.sh:108-119`

**Changes**:
- Generate a random suffix per invocation: `SENTINEL_SALT=$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')`
- Change sentinel format from `__ALLOWLIST_SENTINEL_${idx}__` to `__ALLOWLIST_${SENTINEL_SALT}_${idx}__`
- Both the pre-redaction swap and post-redaction restoration use the same salt

**Acceptance Criteria**:
- [ ] Sentinels include a random component unique per invocation
- [ ] Pre-swap and post-restoration use matching sentinel format
- [ ] Allowlisted content (sha256 hashes, base64 URLs) survives redaction
- [ ] No raw sentinels remain in final output

---

## Sprint 2: Test & Documentation Hardening

**Goal**: Strengthen test coverage and add documentation for the 5 remaining LOW findings. No functional code changes to production paths — only tests, comments, and metadata.

**Global Sprint**: sprint-90

### Task 2.1: Add BOM Hex Verification Assertion (BB-020)

**Finding**: BB-020 (LOW) — BOM fixture may not contain actual BOM bytes, making Test 7 a potential false positive.

**File**: `.claude/tests/hounfour/test-normalize-json.sh:84-87`, `.claude/tests/hounfour/fixtures/mock-responses/bom-prefixed-json.txt`

**Changes**:
- Before Test 7, add an assertion that the fixture file starts with BOM bytes:
  ```bash
  # Verify fixture actually contains BOM prefix
  bom_check=$(head -c 3 "$FIXTURES/bom-prefixed-json.txt" | od -An -tx1 | tr -d ' \n')
  assert_eq "BOM fixture has BOM bytes" "efbbbf" "$bom_check"
  ```
- If the fixture lacks BOM bytes, recreate it with proper BOM prefix using `printf '\xef\xbb\xbf'`
- Add a negative assertion that raw `jq` parsing of the BOM-prefixed file fails (confirming BOM strip is exercised)

**Acceptance Criteria**:
- [ ] Test verifies fixture contains actual EF BB BF bytes
- [ ] Test verifies raw `jq` rejects BOM-prefixed content (confirming Step 1 is exercised)
- [ ] Test 7 (BOM extraction) still passes via the BOM-strip code path
- [ ] All 25+ existing assertions still pass

---

### Task 2.2: Add Quoted Values + Inline Comments Test (BB-021)

**Finding**: BB-021 (LOW) — Test suite doesn't cover the interaction between quoted values and inline comments.

**File**: `.claude/tests/hounfour/test-env-loading.sh`, `.claude/tests/hounfour/fixtures/env/`

**Changes**:
- Create fixture `quoted-inline-comment.env` containing: `OPENAI_API_KEY="sk-test-key-456" # staging key`
- Add Test 6: Parse the fixture through the same pipeline as gpt-review-api.sh
- Assert the result is `sk-test-key-456` (sed strips ` # staging key`, then tr strips quotes)

**Acceptance Criteria**:
- [ ] New fixture exists with quoted value + inline comment
- [ ] Test 6 validates correct extraction: `sk-test-key-456`
- [ ] Processing order confirmed: sed comment strip → tr quote strip
- [ ] All existing tests still pass

---

### Task 2.3: Document Redaction Pattern Coverage (BB-006)

**Finding**: BB-006 (LOW) — The `sk-*` pattern implicitly covers `sk-ant-*` but this isn't documented.

**File**: `.claude/scripts/lib/invoke-diagnostics.sh:28-38`

**Changes**:
- Add inline comments documenting pattern coverage:
  ```bash
  # sk-* covers: OpenAI (sk-proj-*), Anthropic (sk-ant-*), generic (sk-*)
  # ghp_/gho_/ghs_/ghr_* covers: GitHub PATs, OAuth, Apps, Refresh tokens
  # AKIA* covers: AWS access key IDs
  # eyJ* covers: JWT/JWS tokens (base64-encoded JSON header)
  ```
- Add a `# Pattern Maintenance` comment block noting that new provider key prefixes (e.g., `xai-*` for X.AI) should be added as the routing layer expands

**Acceptance Criteria**:
- [ ] Each pattern has an inline comment explaining what it covers
- [ ] Pattern maintenance note exists for future provider additions
- [ ] No functional changes — comments only

---

### Task 2.4: Add Version Headers to Persona Files (BB-009)

**Finding**: BB-009 (LOW) — All persona files lack version headers, preventing drift detection across providers.

**Files**:
- `.claude/skills/flatline-reviewer/persona.md`
- `.claude/skills/flatline-skeptic/persona.md`
- `.claude/skills/flatline-scorer/persona.md`
- `.claude/skills/gpt-reviewer/persona.md`
- `.claude/data/bridgebuilder-persona.md`

**Changes**:
- Add a version header comment to each file: `<!-- persona-version: 1.0.0 | agent: <agent-name> | created: 2026-02-14 -->`
- Update Phase 4 of `run-tests.sh` to validate that all persona files contain the `persona-version` metadata

**Acceptance Criteria**:
- [ ] All 5 persona files have version header comments
- [ ] Headers follow consistent format: `<!-- persona-version: X.Y.Z | agent: NAME | created: DATE -->`
- [ ] Test runner Phase 4 validates version headers exist
- [ ] All tests pass

---

### Task 2.5: Optimize jq Pipe Invocations in normalize_json_response (BB-017)

**Finding**: BB-017 (LOW) — Steps 2 and 3 each pipe input through `echo "$input" | ...` separately, creating redundant subprocess invocations.

**File**: `.claude/scripts/lib/normalize-json.sh:45-58`

**Changes**:
- Combine the markdown fence check (Step 2) and raw JSON check (Step 3) into a single `echo "$input"` pipeline where feasible
- Store the fence-extracted result in a variable before `jq` validation to avoid re-piping
- Add comment explaining the optimization rationale

**Acceptance Criteria**:
- [ ] Steps 2-3 reduce from 4+ subprocess invocations to 2-3
- [ ] All 25+ existing test assertions still pass
- [ ] No behavioral changes — pure performance optimization
- [ ] Large input (50K+ chars) completes without measurable regression

---

## Summary

| Sprint | Global ID | Tasks | Severity Coverage | Theme |
|--------|-----------|-------|-------------------|-------|
| Sprint 1 | sprint-89 | 5 | 3 MEDIUM + 2 LOW | Code hardening — functional fixes |
| Sprint 2 | sprint-90 | 5 | 5 LOW | Test & documentation hardening |
| **Total** | | **10** | **3 MEDIUM + 7 LOW** | |

### Dependencies

- Sprint 1 tasks are independent of each other (can be implemented in any order)
- Sprint 2 tasks are independent of each other
- Sprint 2 Task 2.1 (BOM test) builds on Sprint 1 Task 1.4 only if both touch test-env-loading.sh (they don't — separate test files)

### Risk Assessment

- **Low risk**: All changes are surgical — single-function modifications, comment additions, or test additions
- **No breaking changes**: All functional modifications maintain backward compatibility
- **Test coverage**: Sprint 2 exclusively adds test coverage, reducing future regression risk

### Branch Strategy

Continue on `fix/hounfour-hardening-c013` branch, targeting PR #324.
