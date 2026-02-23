# Sprint 3 (Global Sprint-39) — Implementation Report

## Summary

Sprint 3: Integration + Hardening — all 4 tasks completed with 53 integration test cases and 117 total tests passing across 5 suites.

## Tasks Completed

### Task 3.1: Integration Tests (≥20 test cases) — DONE

Created `test-gpt-review-integration.bats` with 53 test cases covering:

- **All 4 review types via codex** (tests 1-4): code, prd, sdd, sprint — all produce schema-valid output
- **Curl fallback path** (tests 5-7): auto mode degrades gracefully, curl mode skips codex, codex mode hard-fails
- **Multi-pass reasoning** (tests 8-10): 3-pass output with pass_metadata, --fast forces single-pass, default is single-pass
- **Flag combinations** (tests 11-13): --fast, --tool-access, both combined
- **Iteration workflow** (tests 14-16): iteration 1, iteration 2 with --previous, max iteration auto-approve
- **Output validation** (tests 17-19): valid JSON, verdict field, iteration field
- **Exit codes** (tests 20-22): 0 on success, 2 on bad input, 4 without API key
- **Hounfour routing** (test 49): flatline_routing: true falls through to codex

**53 test cases > 20 minimum. AC met.**

### Task 3.2: Backward Compatibility Verification — DONE

- **Schema conformance** (tests 23-26): verdict field present, enum matches spec, minimal config works, all existing flags work
- **Line count** (test 27): gpt-review-api.sh is 225 lines (≤ 300)
- **No caller changes** (tests 50-53): all lib functions exported, all required functions available via `type`
- **Config defaults**: config without reasoning_mode, pass_budgets, or new options uses correct defaults

**AC met: schema-equivalent output, no caller changes, 225 lines.**

### Task 3.3: Security Audit Tests — DONE

- **Real API key redaction** (tests 28-32): OpenAI sk-proj, GitHub ghp_, AWS AKIA, Anthropic sk-ant-api, JWT eyJ — all redacted
- **JSON integrity** (tests 33-34): output valid JSON after redaction, key count preserved
- **Tool-access default** (test 35): --tool-access off by default, workspace has no project files
- **No codex login** (test 36): ensure_codex_auth never calls `codex login`
- **Hard-fail enforcement** (test 37): execution_mode=codex hard-fails when codex unavailable
- **Sensitive file patterns** (tests 38-40): .env caught, .pem caught, .ts allowed

**AC met: zero secrets in output, all SDD §8.2 invariants verified.**

### Task 3.E2E: End-to-End Goal Validation (G1-G7) — DONE

| Goal | Test | Result |
|------|------|--------|
| G1 | `wc -l gpt-review-api.sh` = 225 ≤ 300 | PASS |
| G2 | `grep -c 'curl ' gpt-review-api.sh` (non-comment) = 0 | PASS |
| G3 | All 4 review types succeed via codex | PASS |
| G4 | Output has verdict + iteration, verdict enum valid | PASS |
| G5 | Config without new options uses defaults | PASS |
| G6 | Multi-pass output has file:line references + 3 passes | PASS |
| G7 | Codex removed → curl fallback (not exit 2) | PASS |

**All 7 PRD goals validated.**

## Bugs Found and Fixed

### Bug 1: `load_config()` silent exit under `set -e` (Sprint 2 regression)

**File:** `.claude/scripts/gpt-review-api.sh:60-63`
**Root cause:** The last line of `load_config()` was `[[ -n "$v" && "$v" != "null" ]] && REASONING_MODE="$v"`. When `v` is empty (no reasoning_mode config), the `[[ ]]` condition returns false (exit 1), and being the last command in the function, the function returns 1. Under `set -euo pipefail`, this kills the script silently.
**Fix:** Added `return 0` at end of `load_config()`.

### Bug 2: `CONFIG_FILE` not overridable by tests

**File:** `.claude/scripts/gpt-review-api.sh:12`
**Root cause:** `CONFIG_FILE=".loa.config.yaml"` overwrites any env export. Tests couldn't redirect to test configs.
**Fix:** Changed to `CONFIG_FILE="${CONFIG_FILE:-.loa.config.yaml}"`.

### Bug 3: Mock codex `${VAR:-default}` brace-matching bug

**File:** `.claude/scripts/tests/fixtures/gpt-review/mock_codex.bash:69`
**Root cause:** `response="${MOCK_CODEX_RESPONSE:-{\"verdict\":...}}"` — the `}` in the JSON default value closes the `${...}` expansion early, leaving a trailing literal `}` appended to any custom MOCK_CODEX_RESPONSE. This caused `{"verdict":...}}` (invalid JSON).
**Fix:** Used separate variable: `_default_resp='...'` then `response="${MOCK_CODEX_RESPONSE:-$_default_resp}"`.

### Bug 4: Codex stdout leaking into command substitution

**File:** `.claude/scripts/lib-codex-exec.sh:259`
**Root cause:** `codex_exec_single` did not redirect codex's stdout. The mock (and real codex) could echo to stdout which leaked into `route_review()`'s `resp=$(route_review ...)` command substitution, causing duplicate JSON objects in the output.
**Fix:** Added `>/dev/null` to the timeout line: `timeout "$timeout_secs" "${cmd[@]}" < "$prompt_file" >/dev/null 2>/dev/null || exit_code=$?`. Output is captured via `--output-last-message` file, not stdout.

## Files Changed

| File | Change |
|------|--------|
| `.claude/scripts/gpt-review-api.sh` | +`return 0` in load_config, CONFIG_FILE env override |
| `.claude/scripts/lib-codex-exec.sh` | stdout suppression in codex_exec_single |
| `.claude/scripts/tests/fixtures/gpt-review/mock_codex.bash` | brace-matching fix, removed stdout echo |
| `.claude/scripts/tests/test-gpt-review-integration.bats` | NEW: 53 integration test cases |

## Test Results

```
5 suites, 117 tests, 117 passing, 0 failing

- test-gpt-review-integration.bats: 53/53
- test-gpt-review-security.bats: 18/18
- test-gpt-review-codex-adapter.bats: 17/17
- test-gpt-review-multipass.bats: 15/15
- test-gpt-review-routing.bats: 14/14
```
