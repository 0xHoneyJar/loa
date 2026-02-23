# Sprint 3 (Global Sprint-39) — Engineer Review Feedback

All good

## Review Summary

Sprint 3 (Integration + Hardening) passes all acceptance criteria. The implementation is thorough, well-structured, and the bug fixes are correct. Approved for merge.

---

## Task-by-Task Verification

### Task 3.1: Integration Tests (>=20 test cases) -- PASS

**Test count**: 53 integration test cases in `test-gpt-review-integration.bats` (AC: >=20). Confirmed via `grep -c '@test'`.

**Coverage verified**:
- All 4 review types via codex path: tests at lines 81-107 (code, prd, sdd, sprint)
- Curl fallback path: tests at lines 113-144 (auto degrade, curl-only mode, codex hard-fail)
- Multi-pass mode: tests at lines 150-193 (3-pass output, --fast override, single-pass default)
- --fast + --tool-access combinations: tests at lines 199-218
- Iteration/re-review workflow: tests at lines 224-243 (iter 1, iter 2 with --previous, max-iteration auto-approve)
- Output format validation: tests at lines 249-267 (valid JSON, verdict field, iteration field)
- Exit codes: tests at lines 273-288 (0 success, 2 bad input, 4 no API key)
- Hounfour routing: test at line 593-605

**AC met**: All review types produce schema-valid output, exit codes match spec (0-5), >=20 test cases.

### Task 3.2: Backward Compatibility -- PASS

- **Schema conformance**: Tests at lines 294-325 verify verdict field, enum values, minimal config defaults, and all existing flags
- **Line count**: 225 lines confirmed (AC: <=300). Verified independently via `wc -l`
- **No caller changes**: Tests at lines 611-649 verify all library functions are exported correctly (`call_api`, `is_flatline_routing_enabled`, `codex_is_available`, `codex_exec_single`, `parse_codex_output`, `setup_review_workspace`, `cleanup_workspace`, `run_multipass`, `estimate_token_count`, `enforce_token_budget`, `check_budget_overflow`, `ensure_codex_auth`, `redact_secrets`, `is_sensitive_file`)
- **Zero curl in primary path**: Confirmed 0 non-comment curl calls in `gpt-review-api.sh`

**AC met**: schema-equivalent output, no caller changes, 225 lines <= 300.

### Task 3.3: Security Audit -- PASS

- **Real API key pattern redaction**: Tests at lines 341-375 cover OpenAI (sk-proj-), GitHub (ghp_), AWS (AKIA), Anthropic (sk-ant-api), JWT (eyJ)
- **JSON integrity post-redaction**: Tests at lines 381-396 verify valid JSON and key count preservation
- **--tool-access off by default**: Test at line 402-413 verifies workspace has no project files without explicit opt-in
- **No codex login**: Test at line 419-435 uses a spy script to verify `codex login` is never called (SDD SKP-003 invariant 7)
- **Hard-fail enforcement**: Test at line 441-449 verifies exit 2 when `execution_mode=codex` and codex unavailable (SDD invariant 6)
- **Sensitive file patterns**: Tests at lines 456-472 verify `.env` and `.pem` caught, `.ts` allowed

**SDD Section 8.2 invariants verified**:
1. OPENAI_API_KEY never in process args -- env-only auth confirmed in `ensure_codex_auth()`
2. Output scanned for secrets before persistence -- `redact_secrets()` called at line 219 of gpt-review-api.sh
3. --sandbox read-only always set -- `codex_exec_single()` line 233 adds flag when capability detected
4. --ephemeral always set -- `codex_exec_single()` line 236 adds flag when capability detected
5. Default mode: no repo access -- `setup_review_workspace()` only copies files when `tool_access="true"`
6. Hard fail when execution_mode=codex and capability missing -- verified in routing tests
7. `codex login` never called -- test confirms with spy script
8. JSON integrity verified post-redaction -- `_redact_json()` checks key count before/after

**AC met**: Zero secrets in output, all SDD 8.2 invariants verified.

### Task 3.E2E: Goal Validation (G1-G7) -- PASS

| Goal | Evidence | Result |
|------|----------|--------|
| G1: Lines <= 300 | `wc -l gpt-review-api.sh` = 225 | PASS |
| G2: Zero curl in primary path | 0 non-comment curl calls | PASS |
| G3: All 4 review types via codex | Tests pass for code, prd, sdd, sprint | PASS |
| G4: Schema conformance | verdict + iteration present, enum valid | PASS |
| G5: Config compatibility | Minimal config works with defaults | PASS |
| G6: Multi-pass quality | pass_metadata.passes_completed == 3, file:line in findings | PASS |
| G7: Graceful degradation | Codex removed, auto mode does not exit 2 | PASS |

---

## Bug Fixes Review

### Bug 1: `load_config()` return 0 -- CORRECT

File: `.claude/scripts/gpt-review-api.sh:62`

The fix (`return 0` at end of `load_config()`) is correct. Under `set -e`, the last conditional `[[ ... ]] && REASONING_MODE="$v"` could return 1 when the condition is false, killing the script. The explicit `return 0` ensures `load_config()` always succeeds. No regression risk.

### Bug 2: CONFIG_FILE override -- CORRECT

File: `.claude/scripts/gpt-review-api.sh:12`

Changed from `CONFIG_FILE=".loa.config.yaml"` to `CONFIG_FILE="${CONFIG_FILE:-.loa.config.yaml}"`. This allows tests (and CI) to override the config path via environment variable. Standard Bash pattern. No regression risk.

### Bug 3: Mock codex brace-matching -- CORRECT

File: `.claude/scripts/tests/fixtures/gpt-review/mock_codex.bash:69`

The fix uses a separate variable (`_default_resp='...'`) instead of inline JSON in `${MOCK_CODEX_RESPONSE:-{...}}`. This avoids Bash's brace-matching ambiguity with JSON content. Correct approach.

### Bug 4: Codex stdout suppression -- CORRECT

File: `.claude/scripts/lib-codex-exec.sh:260`

Added `>/dev/null` to suppress codex stdout. Output is captured via `--output-last-message` file, not stdout. The `2>/dev/null` also suppresses stderr. This is the right fix -- without it, mock codex stdout would leak into `route_review()`'s command substitution and corrupt the JSON response.

---

## Code Quality Assessment

**Strengths**:
- Clean modular architecture: 5 library files with double-source guards
- Consistent patterns across all libraries (header format, source guards, function signatures)
- Comprehensive error handling in `run_multipass()` with graceful degradation chain
- Security-first design: env-only auth, jq-based JSON redaction, structural integrity verification
- Well-documented mock with per-call behavior overrides for multi-pass testing

**Minor observations** (non-blocking):
1. `local` at file scope in `lib-codex-exec.sh:46` and `lib-curl-fallback.sh:40` -- Bash treats `local` outside a function as a no-op for scoping. This code is never reached when sourced in normal order (lib-security.sh is sourced first on line 19 of gpt-review-api.sh), but would produce a Bash warning if the dependency loading conditional were to execute at top-level scope. Non-blocking since the guard prevents execution.

2. Implementation report has a minor discrepancy in suite counts: reports "17/17" for codex-adapter and "18/18" for security, but actual counts are 18 and 17 respectively. Total of 117 is correct.

---

## Verdict

**APPROVED**. All acceptance criteria met. All 7 PRD goals validated. 117/117 tests confirmed. Bug fixes are correct and well-reasoned. Security invariants verified. Ready for sprint completion.
