# Security Audit: Sprint-73 (cycle-040, bug-flatline-3model)

## Decision: APPROVED -- LET'S FUCKING GO

**Auditor**: Paranoid Cypherpunk Auditor (auditing-security)
**Date**: 2026-02-26
**Scope**: `.claude/scripts/scoring-engine.sh`, `tests/unit/scoring-engine-3model.bats`, `tests/fixtures/scoring-engine/`

---

## 1. Engineer Feedback Verification

Senior lead approved with **ALL GOOD** in `grimoires/loa/a2a/sprint-73/engineer-feedback.md`. 15/15 tests passing, backward compatibility verified, interface contract confirmed against flatline-orchestrator.sh.

---

## 2. Security Review -- scoring-engine.sh

### 2.1 Injection Vectors: CLEAR

- **jq parameter binding**: All data passed via `--argjson` (lines 169-181). No user input interpolated into jq program strings. This is consistent with the jq injection prevention pattern established in PR #215.
- **No `eval` or `exec`**: Grep confirms zero instances in the file.
- **No shell expansion of user data**: File paths arrive via CLI argument parsing (`"$2"` after `shift 2`), stored in local variables, and passed quoted to `jq -c '.'` or `-f` checks. No unquoted expansion.
- **Process substitution for skeptic files** (lines 182-184): Uses `<(if ... cat "$file" ... else echo '...' fi)` with `--slurpfile`. The file path is quoted, and the fallback is a hardcoded JSON literal. No injection path.

### 2.2 Input Validation: ADEQUATE

- **Required files**: Existence check (`-f`) at lines 692-705, JSON validity check (`jq empty`) at lines 708-716, array structure check (`jq -e '.scores | type == "array"'`) at lines 119-133.
- **Tertiary files**: Optional. Each guarded by `[[ -n "$var" && -f "$var" ]]` before `jq -c '.'` with `2>/dev/null || fallback` (lines 147-163). Missing/invalid files gracefully degrade to `'{"scores":[]}'`.
- **Threshold values**: Loaded via `yq -r` from config with hardcoded defaults (lines 67-85). The `yq` call uses a static path string, not user input. Thresholds consumed as `--argjson` numeric values by jq, which will reject non-numeric input.

### 2.3 Secrets / Credentials: CLEAR

- No API keys, tokens, passwords, or credential references anywhere in the changed code.
- No network calls (`curl`, `wget`, etc.) -- pure local computation.
- No temp file creation or `/tmp/` usage in the new code paths.

### 2.4 Attack Surface: NO NEW SURFACE

- **4 new CLI flags** (lines 636-651): Each follows the identical `shift 2` pattern as all other flag-value pairs. The `*)` catch-all (line 672) rejects unknown flags. No parser ambiguity.
- **4 new function parameters** (lines 106-109): Positional params `${10:-}` through `${13:-}` with `:-` default to empty string. Cannot overflow or underflow the argument list.
- **New jq logic** (lines 190-276): Pure functional data transformation. No side effects, no file writes, no external commands.

### 2.5 Pre-existing Observation (non-blocking)

- `calculate_attack_consensus` (line 391) uses `cat "$file"` inside `$()` for `--argjson` rather than the safer `jq -c '.'` pattern used in the new code. This is **pre-existing** (not introduced by this fix) and is guarded by the input validation gate at lines 692-716 that runs before any function dispatch. Not a new vulnerability, but a future cleanup candidate.

---

## 3. Security Review -- Test File

### 3.1 Test Code: CLEAN

- `scoring-engine-3model.bats`: No `eval`, no network calls, no secret material.
- Fixture paths are relative to `$BATS_TEST_DIR`, constructed deterministically.
- `setup()` overwrites committed fixtures with heredocs using quoted `<<'FIXTURE'` delimiters (no shell expansion). Redundant but harmless per engineer review observation #3.
- No `teardown()` that could mask failures.

### 3.2 Test Coverage Assessment

| Category | Count | Verdict |
|----------|-------|---------|
| 2-model backward compat | 4 | Confirms no regression |
| 3-model full pipeline | 6 | Covers tertiary items, classification, field presence |
| Skeptic dedup (3-source) | 1 | Exact-match dedup verified |
| Degraded mode | 3 | Empty files, partial tertiary, nonexistent files |
| Help text | 1 | All 4 new options present |

**15/15 tests.** No negative-input fuzzing tests (e.g., malformed JSON with nested objects where scores expected, extremely large score values, negative scores), but this is reasonable scope for a targeted bug fix. The input validation layer already rejects malformed JSON at the gate.

---

## 4. Security Review -- Test Fixtures

All 10 fixture files reviewed individually:

| File | Content | Secrets | Verdict |
|------|---------|---------|---------|
| `gpt-scores-2model.json` | Synthetic IMP-001/002/003 scores | None | CLEAN |
| `opus-scores-2model.json` | Synthetic IMP-001/002/003 scores | None | CLEAN |
| `tertiary-scores-opus.json` | Synthetic IMP-001/002 tertiary scores | None | CLEAN |
| `tertiary-scores-gpt.json` | Synthetic IMP-001/003 tertiary scores | None | CLEAN |
| `gpt-scores-tertiary.json` | Synthetic TIMP-001/002 scores | None | CLEAN |
| `opus-scores-tertiary.json` | Synthetic TIMP-001/002 scores | None | CLEAN |
| `skeptic-gpt.json` | 1 generic concern | None | CLEAN |
| `skeptic-opus.json` | 1 generic concern | None | CLEAN |
| `skeptic-tertiary.json` | 2 generic concerns | None | CLEAN |
| `empty-scores.json` | `{"scores":[]}` | None | CLEAN |

All fixtures contain synthetic test data with generic evaluation text. No PII, no API keys, no real project names, no file paths that reveal infrastructure.

---

## 5. Verdict

**APPROVED -- LET'S FUCKING GO**

The fix is:
- **Minimal**: Only adds argument parsing and jq logic for tertiary cross-scores
- **Backward-compatible**: 2-model mode unchanged; all defaults to empty
- **Injection-safe**: All data flows through `--argjson` parameter binding
- **Secret-free**: No credentials, no network, no temp files
- **Well-tested**: 15 tests covering happy path, degraded mode, dedup, and help text
- **No new attack surface**: 4 new CLI flags following established patterns, 4 new positional params with safe defaults

No changes required. Ship it.
