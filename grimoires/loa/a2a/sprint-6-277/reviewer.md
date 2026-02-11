# Sprint 3 (Global Sprint-6) Implementation Report

**Sprint**: Sprint 3 — Bridgebuilder Refinements
**Cycle**: cycle-002 (Eval Sandbox #277)
**Branch**: feature/eval-sandbox-277
**Date**: 2026-02-11

## Summary

Addressed all 7 findings from the Bridgebuilder PR review (#282) and prior audit advisories. Sprint focused on hardening grader security, optimizing multi-trial eval performance, resolving the Dockerfile digest placeholder, and documenting architectural decisions.

## Task Completion

| Task | Description | Status | Files Modified |
|------|-------------|--------|----------------|
| 3.1 | ReDoS guard in pattern-match.sh | DONE | pattern-match.sh, test-graders.sh |
| 3.2 | Safer command execution in tests-pass.sh | DONE | tests-pass.sh, test-graders.sh |
| 3.3 | Grader source-injection guard in CI | DONE | eval.yml |
| 3.4 | Sequential testing optimization | DONE | compare.sh, run-eval.sh, test-compare.sh |
| 3.5 | Dockerfile real SHA256 digest | DONE | Dockerfile.sandbox |
| 3.6 | ADR decision trail | DONE | README.md |
| 3.7 | Multi-model routing documentation | DONE | README.md |

## Implementation Details

### Task 3.1: ReDoS Guard in pattern-match.sh

**File**: `evals/graders/pattern-match.sh`

Added two-layer regex complexity guard before `grep -qlE`:

1. **Length check**: Rejects patterns exceeding `MAX_REGEX_LEN` (default 200 chars, configurable via env var)
2. **Nested quantifier detection**: Rejects patterns matching `(x+)+`, `(x*)*`, `(x{n,}){n,}` — the classic ReDoS amplification patterns

Both guards return exit code 2 (grader error) with descriptive JSON explaining the rejection. Normal regex patterns are unaffected.

**Tests added**: 5 new test cases in test-graders.sh:
- `(a+)+` → rejected
- `(a*)*` → rejected
- `(a{2,}){2,}` → rejected
- 201-char pattern → rejected
- Normal pattern `function` → passes

### Task 3.2: Safer Command Execution in tests-pass.sh

**File**: `evals/graders/tests-pass.sh`

Replaced `bash -c "$test_command"` with array-based direct execution:

1. **Metacharacter rejection**: Before parsing, rejects commands containing `;|&\`$\\` — prevents injection via crafted task args
2. **Array splitting**: Uses `read -ra cmd_array <<< "$test_command"` to split command into array
3. **Direct execution**: Runs `"${cmd_array[@]}"` instead of `bash -c`, eliminating the subshell interpretation vector
4. **Allowlist preserved**: First token still validated against the allowlist

**Tests added**: 4 new test cases in test-graders.sh:
- Semicolon injection → rejected (exit 2)
- Pipe injection → rejected (exit 2)
- Backtick injection → rejected (exit 2)
- Dollar expansion → rejected (exit 2)

### Task 3.3: Grader Source-Injection Guard in CI

**File**: `.github/workflows/eval.yml`

Added step 3.5 "Validate grader trust boundary" between trusted file copy and tool installation:

- Scans all `.sh` files in `pr/evals/graders/` and `pr/evals/harness/`
- Detects `source`/`.` directives with variable expansion (`$`, backticks)
- Detects `eval` with variable expansion
- Skips comment lines
- Fails CI with `::error` annotations pointing to specific files
- Includes explanatory comment about the trust boundary rationale
- Does NOT block legitimate `source` of sibling scripts (only flags variable expansion)

### Task 3.4: Sequential Testing Optimization

**Files**: `evals/harness/compare.sh`, `evals/harness/run-eval.sh`

**compare.sh**: Added `can_early_stop()` function that computes whether regression is inevitable:
- Takes passes, failures, remaining, baseline_pass_rate, threshold
- Computes best-case raw pass rate (all remaining trials pass)
- Returns `"true"` if best-case pass rate < baseline - threshold
- Uses raw pass rate (not Wilson CI) to avoid false positives from wide CIs at small sample sizes

**run-eval.sh**: Modified trial loop in `execute_task()`:
- Added `es_passes` and `es_failures` counters
- After each trial, checks early stopping condition for multi-trial tasks (trials > 1)
- Uses inline python3 to compute best-case pass rate
- On early stop: logs message, writes a single "skipped" result with `early_stopped: true`, and breaks
- Single-trial framework evals are completely unaffected (guard: `trials > 1`)

**Tests added**: 4 new test cases in test-compare.sh:
- 0/3 done, 0 remaining → true (trivially)
- 0/1 done, 2 remaining, bl=1.0 → true (best case 2/3 < 0.90)
- 3/3 done, 2 remaining, bl=1.0 → false (best case 5/5 = 1.0 >= 0.90)
- 1/1 done, 4 remaining, bl=0.5 → false (best case 5/5 = 1.0 >= 0.40)

### Task 3.5: Dockerfile Real SHA256 Digest

**File**: `evals/harness/Dockerfile.sandbox`

Replaced placeholder digest `sha256:8e45e0d1e2c6c5e3b7e3c9b8e7f5d6a4c2b1a0e9d8c7b6a5f4e3d2c1b0a9e8d7` with real digest obtained from `docker manifest inspect node:20.11.0-bookworm-slim`:

```
sha256:8ea90c4f037cc3c2f566eb46c53eaac005129113487eda4090058fe554578104
```

Added comments documenting:
- Date the digest was pinned (2026-02-11)
- Command to refresh it (`docker manifest inspect ...`)

### Task 3.6: ADR Decision Trail

**File**: `evals/README.md`

Added `## Architecture Decisions` section with three ADRs in Context/Decision/Consequences format:

1. **ADR-001: JSONL for Result Storage** — Why append-only JSONL was chosen over SQLite (simplicity, no binary dependency, git-friendly audit trail, flock atomicity)
2. **ADR-002: mikefarah/yq (Go Binary)** — Why Go binary over Python wrapper (zero Python dependency, single binary, consistent behavior)
3. **ADR-003: Shell-Based Harness** — Why Bash over Node.js/Python (zero additional runtime, exit code contract, grader language alignment)

### Task 3.7: Multi-Model Eval Routing Documentation

**File**: `evals/README.md`

Added `## Multi-Model Evaluation` section documenting:

1. **model_version field**: Its purpose in result schema for cross-model comparison
2. **Model version skew detection**: How compare.sh marks results as advisory when models differ
3. **Per-model baseline tracking**: Future capability enabled by the existing schema
4. **Forward reference to Hounfour**: How eval data provides empirical evidence for routing decisions
5. **Early stopping**: Documentation of the new sequential testing optimization

## Test Results

### Grader Tests (test-graders.sh)
- **23/23 passed**, 0 failed
- Includes 5 new ReDoS guard tests and 4 new injection guard tests

### Compare Tests (test-compare.sh)
- **11/12 passed**, 1 failed
- 4/4 new early stopping tests pass
- Pre-existing failure: "Missing task detected for task-d" — jq `input` expression bug in `compare_baseline()` missing task detection. Not related to Sprint 3 changes.

### Framework Eval Suite
- **22/22 passed**, 0 regressions
- Run ID: run-20260211-042430-1cefce8c

## Files Modified

| File | Change |
|------|--------|
| `evals/graders/pattern-match.sh` | ReDoS guard (length + nested quantifiers) |
| `evals/graders/tests-pass.sh` | Metacharacter rejection + array-based execution |
| `.github/workflows/eval.yml` | Source-injection trust boundary check |
| `evals/harness/compare.sh` | `can_early_stop()` function |
| `evals/harness/run-eval.sh` | Early stopping in trial loop |
| `evals/harness/Dockerfile.sandbox` | Real SHA256 digest |
| `evals/README.md` | ADR section + Multi-Model section |
| `evals/harness/tests/test-graders.sh` | 9 new test cases |
| `evals/harness/tests/test-compare.sh` | 4 new test cases |
| `grimoires/loa/sprint.md` | Sprint 3 plan added |
| `grimoires/loa/ledger.json` | Sprint-3 registered (global sprint-6) |
