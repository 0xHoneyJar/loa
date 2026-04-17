# Sprint Plan: Fix Silent Exit in spiral-harness.sh (#516)

**Branch**: `fix/harness-silent-exit-516`

## Document Control

| Field | Value |
|-------|-------|
| PRD | `grimoires/loa/prd.md` |
| SDD | `grimoires/loa/sdd.md` |
| Issue | #516 |
| Status | Ready |
| Created | 2026-04-16 |

## Sprint Overview

Single sprint — three surgical tasks covering both failure modes and an automated regression test.

| Sprint | Focus | Tasks | Priority |
|--------|-------|-------|----------|
| 1 | ERR trap + wc-c fix + regression test | 3 | P0 |

---

## Sprint 1: Harden spiral-harness.sh Against Silent Exits

**Goal**: Eliminate the two silent-exit failure modes in `spiral-harness.sh` and add a BATS regression test that proves ERR trap emission and `_invoke_claude` exit-code propagation.

---

### Task 1.1: Fix Fragile `wc -c` Pipeline and Guard `_record_action` in `_invoke_claude`

**Files**:
- `.claude/scripts/spiral-harness.sh` (edit — lines 241–243 only)

**What to change**:

Current code (lines 241–243):
```bash
_record_action "$phase" "claude-${model}" "invoke" "" "" "$stdout_file" \
    "$(wc -c < "$stdout_file" 2>/dev/null | tr -d ' ' || echo 0)" \
    "$duration_ms" "$budget" ""
```

Replace with:
```bash
_record_action "$phase" "claude-${model}" "invoke" "" "" "$stdout_file" \
    "$({ wc -c < "$stdout_file" 2>/dev/null || echo 0; } | tr -d ' ')" \
    "$duration_ms" "$budget" "" || true
```

**Two changes in this diff**:
1. `$(wc -c < "$stdout_file" 2>/dev/null | tr -d ' ' || echo 0)` → `$({ wc -c < "$stdout_file" 2>/dev/null || echo 0; } | tr -d ' ')` — moves the `|| echo 0` recovery inside a brace group so `pipefail` cannot propagate `wc -c` failure past the group boundary.
2. `|| true` appended to the entire `_record_action` call — decouples a nonzero return from `_record_action` (e.g., `_FLIGHT_RECORDER` unset) from harness termination at this call site only.

**Acceptance Criteria**:
- [ ] Line 241 is unchanged (the `_record_action` call opening).
- [ ] Line 242 reads: `    "$({ wc -c < "$stdout_file" 2>/dev/null || echo 0; } | tr -d ' ')"` (quoted brace group, no bare pipe).
- [ ] Line 243 reads: `    "$duration_ms" "$budget" "" || true` (appended `|| true`).
- [ ] No other lines in `_invoke_claude` are modified (diff is exactly lines 242–243).
- [ ] `return "$exit_code"` on line 245 is untouched — `_invoke_claude` still returns the `claude -p` exit code.
- [ ] The `|| true` does NOT appear on any other `_record_action` call outside `_invoke_claude`.

**Test Requirements**:
- Covered by Task 1.3 TC-2 (exit-code propagation when `_record_action` returns 1).
- Covered by Task 1.3 TC-3 (wc-c failure does not kill the harness).

---

### Task 1.2: Add ERR Trap in `main()` of `spiral-harness.sh`

**Files**:
- `.claude/scripts/spiral-harness.sh` (edit — add `_harness_err_handler` function and trap registration)

**What to add**:

Add `_harness_err_handler` as a named function (not inline) near the other helper functions, before `main()`:

```bash
_harness_err_handler() {
    local lineno="$1" cmd="$2"
    echo "[FATAL] spiral-harness.sh: ERR at line ${lineno}: ${cmd}" >&2
    if [[ -n "${_FLIGHT_RECORDER:-}" ]]; then
        local seq
        seq=$(( ${_FLIGHT_RECORDER_SEQ:-0} + 1 ))
        local ts
        ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "unknown")
        jq -n -c \
            --argjson seq "$seq" \
            --arg ts "$ts" \
            --arg verdict "ERR at line ${lineno}: ${cmd}" \
            '{seq:$seq,ts:$ts,phase:"FATAL",actor:"spiral-harness",action:"ERR_TRAP",
              input_checksum:null,output_checksum:null,output_path:null,
              output_bytes:0,duration_ms:0,cost_usd:0,verdict:$verdict}' \
            >> "$_FLIGHT_RECORDER" 2>/dev/null || true
    fi
}
```

Register the trap in `main()` after `_parse_args` and before the first `_record_action "CONFIG"` call (line ~972):

```bash
main() {
    _parse_args "$@" || exit $?

    trap '_harness_err_handler $LINENO "$BASH_COMMAND"' ERR

    local pr_url=""
    ...
    _record_action "CONFIG" ...
```

**Acceptance Criteria**:
- [ ] `_harness_err_handler` is defined as a named function (not an inline trap body).
- [ ] The function accepts two positional args: `$1` = line number, `$2` = command string.
- [ ] The function emits a line matching `[FATAL] spiral-harness.sh: ERR at line <N>: <command>` to stderr unconditionally.
- [ ] The function appends a FATAL JSONL entry (schema per SDD §3.2) to `$_FLIGHT_RECORDER` via `jq -n -c` with `--arg`/`--argjson` binding when `$_FLIGHT_RECORDER` is non-empty.
- [ ] The JSONL entry uses `phase:"FATAL"`, `actor:"spiral-harness"`, `action:"ERR_TRAP"`.
- [ ] The function does NOT call `exit` — it returns normally so the original nonzero status propagates.
- [ ] The `jq` append in the handler is itself guarded with `|| true` to prevent a secondary failure in the trap from masking the original error.
- [ ] The trap registration line reads: `trap '_harness_err_handler $LINENO "$BASH_COMMAND"' ERR`.
- [ ] The trap is registered after `_parse_args "$@" || exit $?` and before `_record_action "CONFIG"` (line ~972).
- [ ] No other lines in `main()` are modified.
- [ ] If `$_FLIGHT_RECORDER` is empty (flight recorder not yet open), the trap writes only to stderr and does not attempt any file write.

**Test Requirements**:
- Covered by Task 1.3 TC-1 (ERR trap emits FATAL on stderr when `_record_action` fails).
- Covered by Task 1.3 TC-4 (FATAL entry written to flight recorder when recorder is open).

---

### Task 1.3: Create BATS Regression Test

**Files**:
- `tests/unit/spiral-harness-err-trap.bats` (new)

**Test structure** (follows conventions from `tests/unit/spiral-evidence-gate.bats`):

```
# Regression test for Issue #516 — silent exit in spiral-harness.sh
# https://github.com/0xHoneyJar/loa/issues/516

setup() {
    TEST_TMPDIR="$(mktemp -d)"
    # create mock bin dir, prepend to PATH
    # stub: claude shim, jq passthrough
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}
```

**Test Cases**:

| ID | Name | Mechanism | Assertion |
|----|------|-----------|-----------|
| TC-1 | `ERR trap emits FATAL to stderr when _record_action fails` | Unset `_FLIGHT_RECORDER`; source harness env; call a function that triggers ERR | `output` contains line matching `[FATAL].*ERR at line` |
| TC-2 | `_invoke_claude returns claude -p exit code when _record_action fails` | Mock `claude` shim exits 42; mock `_record_action` returns 1; source `_invoke_claude` | `_invoke_claude` exits with 42, not 1 |
| TC-3 | `wc-c failure does not propagate nonzero under pipefail` | Evaluate fixed expression with non-existent `stdout_file`; `set -eo pipefail` active | Expression exits 0 and produces `"0"` |
| TC-4 | `ERR trap appends FATAL entry to flight recorder when recorder is open` | Set `_FLIGHT_RECORDER` to a temp file; trigger ERR via `_harness_err_handler` directly | `$_FLIGHT_RECORDER` contains line with `"phase":"FATAL"` |

**Acceptance Criteria**:
- [ ] File exists at `tests/unit/spiral-harness-err-trap.bats`.
- [ ] Top of file includes regression comment referencing Issue #516 with URL.
- [ ] `setup()` creates `TEST_TMPDIR` via `mktemp -d`, creates `$TEST_TMPDIR/bin`, prepends to `PATH`, places a `claude` shim.
- [ ] `teardown()` removes `TEST_TMPDIR` entirely.
- [ ] **TC-1**: Sources `_harness_err_handler` from the harness (or replicates its body); unsets `_FLIGHT_RECORDER`; invokes a construct that triggers the ERR path; asserts `stderr` contains a line matching `[FATAL].*ERR at line [0-9]`.
- [ ] **TC-2**: Mock `claude` shim exits with code 42; mock `_record_action` is a function that returns 1; sources `_invoke_claude` from the harness into the test context; calls `_invoke_claude "TEST" "prompt" "1.0" 10 "test-model"`; asserts exit status is 42.
- [ ] **TC-3**: Runs `set -eo pipefail; result=$({ wc -c < /nonexistent 2>/dev/null || echo 0; } | tr -d ' ')` in a subshell; asserts exit status 0 and `$result` equals `"0"`.
- [ ] **TC-4**: Sets `_FLIGHT_RECORDER` to `$TEST_TMPDIR/fr.jsonl`; calls `_harness_err_handler 99 "test_cmd"`; asserts `$_FLIGHT_RECORDER` file contains a line parseable by `jq` with `.phase == "FATAL"` and `.action == "ERR_TRAP"`.
- [ ] All test cases include a `# Issue #516` inline comment.
- [ ] `bats tests/unit/spiral-harness-err-trap.bats` exits 0.
- [ ] Test file uses `load` helper pattern consistent with `tests/unit/spiral-evidence-gate.bats` (if a bats helper library is present in the suite).

**Test Requirements**:
- Each `@test` block must be independent — no shared mutable state between test cases.
- Mock `claude` shim must be a file in `$TEST_TMPDIR/bin/claude` with `#!/usr/bin/env bash` header and `exit <N>` body.
- `teardown()` must always run (BATS guarantees this); no manual cleanup inside test bodies.

---

## Implementation Order

Tasks 1.1 and 1.2 both touch `spiral-harness.sh` and must be applied sequentially in a single editing pass to avoid conflicts. Task 1.3 (BATS test) is independent and can be written in parallel with verification of the harness edits.

| Step | Task | Action |
|------|------|--------|
| 1 | 1.2 | Add `_harness_err_handler` function to `spiral-harness.sh` |
| 2 | 1.2 | Register ERR trap in `main()` |
| 3 | 1.1 | Fix `wc -c` expression and append `|| true` in `_invoke_claude` |
| 4 | 1.3 | Create `tests/unit/spiral-harness-err-trap.bats` with all four test cases |
| 5 | — | Run `bats tests/unit/spiral-harness-err-trap.bats` — must exit 0 |
| 6 | — | Run full `bats tests/` — zero newly introduced failures |

---

## Test Matrix

| Task | TC-1 | TC-2 | TC-3 | TC-4 | Full suite |
|------|------|------|------|------|------------|
| 1.1 (wc-c + `\|\| true`) | — | ✓ | ✓ | — | ✓ |
| 1.2 (ERR trap) | ✓ | — | — | ✓ | ✓ |
| 1.3 (BATS test) | self | self | self | self | ✓ |

---

## Dependencies

| Task | Depends On |
|------|------------|
| 1.1 | None — isolated to lines 241–243 of `_invoke_claude` |
| 1.2 | None — adds new function and one-line trap registration |
| 1.3 | 1.1 and 1.2 must be complete before TC-2 and TC-4 can be validated against real harness code |

---

## Success Criteria

| Goal (PRD §4) | Criterion |
|---------------|-----------|
| G1: Any abnormal exit produces a visible log line | ERR trap emits `[FATAL] spiral-harness.sh: ERR at line N: cmd` to stderr — verified by TC-1 |
| G2: `_record_action` failure cannot kill the harness | `_invoke_claude` returns `claude -p` exit code when `_record_action` returns 1 — verified by TC-2 |
| G3: Fragile `wc -c` pipe eliminated | Fixed group expression exits 0 under `pipefail` with missing file — verified by TC-3 |
| G4: ERR trap covered by automated regression test | TC-1 and TC-4 fail against pre-fix code, pass against post-fix code |
| G5: No regression on existing tests | Full `bats tests/` exits with zero newly introduced failures |
| G6: Fix is surgical | Diff confined to `spiral-harness.sh` (lines 241–243 + `_harness_err_handler` + trap line) and `tests/unit/spiral-harness-err-trap.bats`; no unrelated lines modified |
