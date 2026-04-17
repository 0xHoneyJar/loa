# Security Audit — fix/harness-silent-exit-516

**Branch**: `fix/harness-silent-exit-516`
**PR**: fix(harness): eliminate silent exits in spiral-harness.sh (#516)
**Auditor**: Security Auditor (independent review)
**Date**: 2026-04-16
**Verdict**: **APPROVED** (0 critical, 0 high, 2 low/info)

---

## Scope

Files reviewed from git diff:

| File | Type | Risk |
|------|------|------|
| `.claude/scripts/spiral-harness.sh` (lines 239–244, 959–993) | Shell script (2 hunks) | Low |
| `tests/unit/spiral-harness-err-trap.bats` | BATS test file (new, 112 lines) | Low |

Supporting context read: `spiral-evidence.sh` (initialization of `_FLIGHT_RECORDER` / `_FLIGHT_RECORDER_SEQ`).

---

## Security Checklist

### 1. Hardcoded Secrets — PASS

No credentials, API keys, tokens, or secrets present in either changed file. The test file uses only `mktemp`-derived paths. No sensitive environment variables are referenced.

### 2. Input Validation — PASS (for changed code)

**`_invoke_claude` hunk** — `$stdout_file` is set internally within the function and is properly double-quoted in the redirect (`< "$stdout_file"`). No external input path.

**`_harness_err_handler`** — receives `$LINENO` (an integer) and `$BASH_COMMAND` (a string). Both are bash-internal values, not user-supplied. They reach jq only via `--arg verdict` (string-safe binding). No validation gap for the security checklist's scope.

**`_FLIGHT_RECORDER_SEQ` arithmetic** (`seq=$(( ${_FLIGHT_RECORDER_SEQ:-0} + 1 ))`): Cross-checked with `spiral-evidence.sh` line 35, which unconditionally assigns `_FLIGHT_RECORDER_SEQ=0` at source time—overwriting any env-level value before `main()` runs and before the trap can fire. An env-injected value of the form `$(cmd)` would be overridden at script initialization. Risk is neutralized by sourcing order.

### 3. Command Injection — PASS

All jq calls use parameter binding, not string interpolation:

```bash
jq -n -c \
    --argjson seq "$seq" \
    --arg ts "$ts" \
    --arg verdict "ERR at line ${lineno}: ${cmd}" \
    '{ ... }' >> "$_FLIGHT_RECORDER"
```

- `--arg verdict` treats `$BASH_COMMAND` as a literal string regardless of content. ✓
- `--argjson seq` receives a shell arithmetic result, guaranteed numeric. ✓
- `--arg ts` receives output from `date -u`, not external input. ✓
- `|| true` on the jq call suppresses errors without masking the claude exit code. ✓

The brace-group wc expression `$({ wc -c < "$stdout_file" 2>/dev/null || echo 0; } | tr -d ' ')` correctly isolates the `wc` failure from the pipeline under `pipefail`. No injection vector.

### 4. File Permissions — PASS

`_FLIGHT_RECORDER` is opened in `spiral-evidence.sh` with:
```bash
(umask 077 && touch "$_FLIGHT_RECORDER")
chmod 600 "$_FLIGHT_RECORDER"
```
The `_harness_err_handler` only appends to a file that was already created with `chmod 600`. No new file creation in the err handler itself. The `[[ -n "${_FLIGHT_RECORDER:-}" ]]` guard prevents writing when the recorder was never opened.

Test file: `mktemp -d` produces a `0700` directory. BATS temp dir cleaned in `teardown`. ✓

### 5. Path Traversal — PASS (with advisory)

`_FLIGHT_RECORDER` is set as `"$cycle_dir/flight-recorder.jsonl"` where `cycle_dir` comes from `--cycle-dir` CLI arg parsed in `_parse_args`. If `--cycle-dir` is caller-controlled with a `../` traversal (e.g., `../../etc/cron.d`), the err handler would append JSONL to an unintended path.

This is not new attack surface introduced by the err handler — `_record_action` already writes to `_FLIGHT_RECORDER` throughout the script. The err handler inherits the same pre-existing exposure. Confirmed pre-existing; outside this PR's scope.

---

## Findings

### F1 — LOW: `_FLIGHT_RECORDER_SEQ` not updated in err handler (sequence drift)

| Field | Value |
|-------|-------|
| Location | `.claude/scripts/spiral-harness.sh` (new `_harness_err_handler`) |
| Severity | LOW (correctness) |
| Type | State inconsistency |
| Introduced by this PR | YES |

**Finding**: `_record_action` updates the global `_FLIGHT_RECORDER_SEQ=$((_FLIGHT_RECORDER_SEQ + 1))`. The err handler uses a local `seq` variable and does not update the global. If the script somehow continued after ERR (e.g., ERR trap + return instead of exit), the next `_record_action` call would emit a duplicate sequence number in the flight recorder.

**Impact**: Negligible in practice — `set -euo pipefail` is active, so after ERR trap fires the script exits. Duplicate seq numbers would only appear if the trap were called in a subshell context that does not exit the parent. No security consequence; minor audit log integrity issue.

**Recommendation**: For consistency, consider `_FLIGHT_RECORDER_SEQ=$(( _FLIGHT_RECORDER_SEQ + 1 ))` inside the handler (updating the global) rather than a local `seq`. Low priority.

### F2 — INFO: Test TC-1 and TC-4 use `eval` / command substitution on harness source

| Field | Value |
|-------|-------|
| Location | `tests/unit/spiral-harness-err-trap.bats` lines 43, 58–60, 95–97 |
| Severity | INFO |
| Type | Test hygiene |
| Introduced by this PR | YES |

**Finding**: TC-1 and TC-4 extract the function body with `grep -A 20 ... | head -21` and pass it to `eval` or interpolate it into `bash -c "..."`. If the harness file were maliciously modified, this would execute arbitrary code during the test run.

**Impact**: The harness is a trusted repo file. In CI the harness is checked out from the repo under test — an attacker who can modify the harness can already run arbitrary code. The risk is theoretical and bounded to the test environment. Standard BATS practice.

**Recommendation**: Consider `source "$HARNESS"` with a stub environment as a more idiomatic isolation approach, avoiding partial-grep extraction. Advisory only.

---

## Positive Observations

1. **`|| true` on `_record_action`**: The fix correctly prevents `_record_action` logging failure from overriding the `claude -p` exit code. This is the surgical fix for Issue #516.
2. **Brace-group pipefail isolation**: `$({ wc -c < ... 2>/dev/null || echo 0; } | tr -d ' ')` is the correct pattern for pipefail-safe fallback — the `|| echo 0` is inside the brace group, not outside the pipe.
3. **jq `--arg`/`--argjson` throughout**: No jq filter string interpolation anywhere in the new code. Consistent with the project's established safe patterns.
4. **`2>/dev/null || true` on err handler's jq write**: An error handler that itself errors would be unhelpful — suppressing secondary failures is the right design.
5. **`[[ -n "${_FLIGHT_RECORDER:-}" ]]` guard**: The handler is a no-op when the flight recorder was never opened, preventing spurious file creation.
6. **TC-3 explicitly validates pipefail isolation**: The test asserts `status -eq 0` and `output = "0"` for a missing file — directly proves the silent-exit regression is fixed.

---

## Verdict

**APPROVED**

The diff is a targeted two-part fix: brace-group pipefail isolation on the wc expression, and an ERR trap handler with a flight recorder entry. No new secrets, no injection vectors, no path traversal from user input, correct file permissions. F1 is a low-severity sequence-drift nit with no security consequence. F2 is a test-hygiene advisory on a standard BATS extraction pattern. Neither warrants blocking the PR.

---

# Security Audit — fix/red-team-submodule-template-528

**Branch**: `fix/red-team-submodule-template-528`
**PR**: fix(red-team): anchor template paths to SCRIPT_DIR for submodule compatibility (#528)
**Auditor**: Security Auditor (independent review)
**Date**: 2026-04-16
**Verdict**: **APPROVED** (0 critical, 0 high, 1 advisory pre-existing)

---

## Scope

Files reviewed from git diff:

| File | Type | Risk |
|------|------|------|
| `.claude/scripts/red-team-pipeline.sh` (lines 29-30) | Shell script (2-line change) | Low |
| `tests/unit/red-team-template-resolution.bats` | BATS test file (new, 106 lines) | Low |

Broader script context read: lines 1–260 of `red-team-pipeline.sh`.

---

## Security Checklist

### 1. Hardcoded Secrets — PASS

No secrets, credentials, API keys, or tokens present in either changed file. The test file uses only filesystem paths derived from `mktemp`. No environment variables holding sensitive values are referenced.

### 2. Input Validation — PASS (for changed code)

The two changed lines assign path variables from `$SCRIPT_DIR`, which is set at script line 13:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

`pwd` after `cd` produces an absolute, canonicalized path — no user input involved. The `../templates/` component is a fixed string literal, not derived from any external source. The resulting paths are used only as source operands to `cp` (lines 103, 141) and `awk -v file=` (lines 115–130, 149–152) — read-only, never executed.

### 3. Command Injection — PASS (for changed code)

Neither changed line introduces a new injection vector:

- `ATTACK_TEMPLATE` and `COUNTER_TEMPLATE` are used as arguments to `cp` and as `awk -v file=` values. Both uses treat them as data, not code.
- No jq filter string interpolation in the changed lines or the render functions that consume them.
- `awk -v marker=... -v file=...` passes values via `-v` binding — equivalent to `--arg` in jq. Safe.

### 4. File Permissions — PASS

**Test file (`bats`):**
- `mktemp -d` creates the temp directory with mode `0700` (owner-only) on Linux — appropriate for test isolation.
- `touch` on template stubs inherits the process umask (typically `0644`). These are non-secret stub files used only for existence checks, so world-readable is acceptable.
- `rm -rf "$TEST_TMPDIR"` in `teardown` — safe: `TEST_TMPDIR` is always set by `mktemp`, never from user input. No risk of unintended deletion.

**Script (`red-team-pipeline.sh`):** No permission changes introduced. The script already runs under `set -euo pipefail`.

### 5. Path Traversal — PASS

The `../` in `$SCRIPT_DIR/../templates/` is a fixed string literal, not derived from user input, CLI arguments, environment variables, or config files. `SCRIPT_DIR` itself is canonicalized by `cd ... && pwd`, which resolves symlinks. A symlink-based attack on `BASH_SOURCE[0]` would require the attacker to already control the filesystem at script installation time — outside the threat model for this change.

No user-controlled path component exists in either changed line or the test file.

---

## Advisory Finding (Pre-Existing, Not Introduced by This PR)

### F1 — MEDIUM: `$surface` interpolated directly into yq expression (pre-existing)

| Field | Value |
|-------|-------|
| Location | `.claude/scripts/red-team-pipeline.sh:62` |
| Severity | MEDIUM |
| Type | Expression injection (pre-existing) |
| Introduced by this PR | NO |

**Finding**: `load_surface_context()` constructs the yq filter by interpolating `$surface` directly:

```bash
yq ".surfaces.\"$surface\"" "$ATTACK_SURFACES"
```

If `$surface` contains shell metacharacters or yq expression operators (e.g., `" | .foo`), the resulting expression could escape the intended path and evaluate arbitrary yq. The callers should validate `$surface` to `[a-zA-Z0-9_-]` before passing it here.

**Impact**: Depends on what calls `load_surface_context()`. If `$surface` is ultimately derived from CLI arguments to `red-team-pipeline.sh`, an attacker with script invocation access could craft a yq injection. This does not affect the correctness of the two changed lines, which do not touch `load_surface_context()`.

**Recommendation**: Validate `$surface` against an allowlist (e.g., `[[ "$surface" =~ ^[a-zA-Z0-9_-]+$ ]]`) before passing to `yq`. File a separate bug — this is outside the scope of PR #528.

---

## Positive Observations

1. **Correct use of `cd ... && pwd`**: `SCRIPT_DIR` is canonicalized at script load, not constructed from raw `dirname` output. This is the correct pattern for submodule-compatible path anchoring.
2. **`awk -v file=` for content injection**: The render functions use `awk -v` binding for file paths rather than string interpolation — the right approach for handling arbitrary file content safely.
3. **Test regression proof**: TC-1 explicitly asserts that the pre-fix path (`$PROJECT_ROOT/.claude/templates/`) does NOT exist in submodule mode. This is strong: it proves the old code would have failed, not just that the new code works.
4. **`set -euo pipefail` throughout**: Strict mode is active for the script.
5. **`mktemp -d` with safe teardown**: Test isolation is correct — no shared state, private temp dir, deterministic cleanup.

---

## Verdict

**APPROVED**

The diff is a narrow, surgical fix: two path variable reassignments and a regression test. No new secrets, no new injection vectors, no path traversal from user input, correct file permissions. The one MEDIUM finding (`$surface` yq injection) is pre-existing and outside PR scope. The implementation is secure for merge.
