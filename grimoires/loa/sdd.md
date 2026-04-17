# SDD: Fix Silent Exit in spiral-harness.sh (#516)

**Date**: 2026-04-16
**Issue**: #516
**Branch**: fix/harness-silent-exit-516
**PRD**: `grimoires/loa/prd.md`

---

## 1. System Architecture Context

`spiral-harness.sh` is the evidence-gated orchestrator for autonomous spiral cycles. It runs under `set -euo pipefail` (line 32) and manages a multi-phase pipeline:

```
DISCOVERY → ARCHITECTURE → PLANNING → IMPLEMENTATION → REVIEW → AUDIT
```

Each phase calls `_invoke_claude` (line ~209), which is the single site that dispatches `claude -p` for all pipeline phases. After each invocation, `_invoke_claude` calls `_record_action` from the sourced `spiral-evidence.sh` to append a JSONL entry to the per-cycle flight recorder.

The flight recorder (`$_FLIGHT_RECORDER`, a `.jsonl` file under the cycle directory) is the primary post-mortem tool for failed cycles. When the harness exits silently — no log line, no flight-recorder entry — the flight recorder contains no terminal event to diagnose.

Two independent failure modes produce this silent exit. Both fire inside `_invoke_claude`, which is on the critical path for every phase of every cycle.

### Dependency Graph

```
spiral-harness.sh  (main orchestrator, set -euo pipefail)
  └── sources spiral-evidence.sh
        ├── _init_flight_recorder()  — opens JSONL file, chmod 600
        ├── _record_action()         — appends JSONL entry; returns 1 if _FLIGHT_RECORDER unset
        └── _record_failure()        — delegates to _record_action with FAIL verdict

main()
  ├── _parse_args
  ├── _record_action "CONFIG" ...   ← first recorder call (line ~972)
  ├── _phase_discovery
  │     └── _invoke_claude "DISCOVERY" ...
  │           ├── claude -p ...
  │           └── _record_action "DISCOVERY" ...   ← BUG SITE
  ├── _phase_architecture
  │     └── _invoke_claude "ARCHITECTURE" ...
  │           └── _record_action ...               ← BUG SITE (repeated per phase)
  └── ... (all 6 phases)
```

---

## 2. Component Design

### 2.1 Failure Mode A — Fragile `wc -c` Pipeline in `_invoke_claude`

**Current code** (spiral-harness.sh line ~241–243):

```
_record_action "$phase" "claude-${model}" "invoke" "" "" "$stdout_file" \
    "$(wc -c < "$stdout_file" 2>/dev/null | tr -d ' ' || echo 0)" \
    "$duration_ms" "$budget" ""
```

**Root cause**: Under `set -eo pipefail`, the pipeline `wc -c ... | tr -d ' '` has its exit status governed by `pipefail` — which propagates the first non-zero stage regardless of subsequent `||` recovery. When `wc -c` exits nonzero (file missing, unreadable, fd closed), `pipefail` sets the pipeline exit status before `|| echo 0` can intercept it. The command substitution therefore exits nonzero. Because this expression is evaluated as an argument to `_record_action` under `set -e`, the process exits before `_record_action` is called. No log line is emitted.

**Fix**: Restructure the subshell so `wc -c` failure is isolated from the pipe:

```
"$({ wc -c < "$stdout_file" 2>/dev/null || echo 0; } | tr -d ' ')"
```

The `{ ...; }` group evaluates `wc -c || echo 0` as a unit before piping to `tr -d ' '`. Under `pipefail`, the group's exit status is determined by `|| echo 0`, which always succeeds. `tr -d ' '` receives a valid integer string (`0` or the byte count) and always succeeds. The pipeline exit status is therefore always 0 — no propagation into the command substitution.

**Scope**: This change touches exactly one expression in `_invoke_claude` (lines ~242). No other lines are modified.

### 2.2 Failure Mode B — `_record_action` Early-Exit Guard

**Current code** (spiral-evidence.sh line ~62):

```bash
[[ -z "$_FLIGHT_RECORDER" ]] && return 1
```

**Root cause**: If `_FLIGHT_RECORDER` is unset or empty (e.g., sourcing order issue, subshell scope loss, incorrect initialization sequence), `_record_action` returns 1. Under `set -e`, any caller that does not append `|| true` exits the process at that line. The harness exits with no output.

**Fix**: Guard the `_record_action` call in `_invoke_claude` with `|| true`:

```bash
_record_action "$phase" "claude-${model}" "invoke" "" "" "$stdout_file" \
    "$({ wc -c < "$stdout_file" 2>/dev/null || echo 0; } | tr -d ' ')" \
    "$duration_ms" "$budget" "" || true
```

The `|| true` decouples recording failure from harness termination for this call site only. `_invoke_claude` then returns `$exit_code` (the `claude -p` exit status) regardless of whether recording succeeded.

**Why only `_invoke_claude`**: Other callers of `_record_action` — notably `_record_failure` inside gate verification — correctly treat a recording failure as a hard error because the evidence chain for a gate decision must be intact. Applying `|| true` globally would suppress legitimate recording failures at quality gates. Per PRD §3 assumption 7, the `|| true` guard is surgical to `_invoke_claude`.

### 2.3 ERR Trap in `main()`

**Design**: Register an ERR trap near the top of `main()`, before the first `_record_action` call at line ~972. The trap fires for any unhandled nonzero exit within `main()`'s dynamic scope, including sourced functions (standard bash behavior with `set -e`).

**Trap behavior**:
1. Emit a FATAL line to stderr unconditionally:
   ```
   [FATAL] spiral-harness.sh: ERR at line <N>: <command>
   ```
   where `<N>` is `$LINENO` at trap time and `<command>` is `$BASH_COMMAND`.
2. If `$_FLIGHT_RECORDER` is non-empty, append a FATAL JSONL entry via `jq -n -c` directly (not via `_record_action`, which might itself be failing).
3. Do **not** suppress the exit — the trap logs and allows the original nonzero status to propagate. The harness still terminates with the triggering exit status.

**Implementation approach**: The ERR trap must capture `$LINENO` and `$BASH_COMMAND` at fire time into local variables before any subshell or function call can alter them. The flight-recorder append uses `jq -n -c` with `--arg` parameter binding to build the JSONL without shell interpolation.

**Placement**: After the `_parse_args` call (which has its own `|| exit $?` guard) and before `_record_action "CONFIG"`:

```
main() {
    _parse_args "$@" || exit $?

    trap '_harness_err_handler $LINENO "$BASH_COMMAND"' ERR

    local pr_url=""
    ...
    _record_action "CONFIG" ...   ← trap is now active
```

`_harness_err_handler` is defined as a function (not an inline body) to keep the `main()` block readable and to allow the handler to use local variables.

### 2.4 BATS Test File: `tests/unit/spiral-harness-err-trap.bats`

Two test cases are required:

**TC-1 — ERR trap emits FATAL on `_record_action` failure**: Mock `_record_action` to return 1 (by unsetting `_FLIGHT_RECORDER` or overriding the function). Source enough of the harness to have `_invoke_claude` available in a test context. Assert that stderr contains a line matching `FATAL`.

**TC-2 — `_invoke_claude` returns `claude -p` exit code when `_record_action` fails**: Mock `claude -p` with a shim that exits with a specific code (e.g., 42). Mock `_record_action` to return 1. Assert that `_invoke_claude` exits with 42, not 1. Assert that the test process does not exit due to the recording failure.

Both test cases include a regression comment referencing Issue #516.

---

## 3. Data Model

### 3.1 Flight Recorder JSONL Schema (Existing)

Entries appended by `_record_action`:

| Field | Type | Description |
|-------|------|-------------|
| `seq` | integer | Monotonically increasing sequence number |
| `ts` | string (ISO-8601) | UTC timestamp |
| `phase` | string | Pipeline phase name (e.g., `DISCOVERY`, `ARCHITECTURE`) |
| `actor` | string | Actor identifier (e.g., `claude-sonnet-4-6`) |
| `action` | string | Action type (e.g., `invoke`, `FAILED`) |
| `input_checksum` | string\|null | SHA of input artifact (null if none) |
| `output_checksum` | string\|null | SHA of output artifact (null if none) |
| `output_path` | string\|null | Path to output file (null if none) |
| `output_bytes` | integer | Byte count of output (0 if unknown) |
| `duration_ms` | integer | Phase wall-clock duration in milliseconds |
| `cost_usd` | number | Estimated cost of this invocation |
| `verdict` | string\|null | Free-form verdict or reason string |

### 3.2 ERR Trap FATAL Entry (New)

The ERR trap appends a FATAL entry to the flight recorder when `$_FLIGHT_RECORDER` is non-empty. Proposed schema (written directly by `jq -n -c` in the trap handler, bypassing `_record_action`):

| Field | Type | Value |
|-------|------|-------|
| `seq` | integer | `$_FLIGHT_RECORDER_SEQ + 1` |
| `ts` | string | Current UTC timestamp |
| `phase` | string | `"FATAL"` |
| `actor` | string | `"spiral-harness"` |
| `action` | string | `"ERR_TRAP"` |
| `input_checksum` | null | — |
| `output_checksum` | null | — |
| `output_path` | null | — |
| `output_bytes` | integer | `0` |
| `duration_ms` | integer | `0` |
| `cost_usd` | number | `0` |
| `verdict` | string | `"ERR at line <N>: <command>"` |

Writing directly via `jq` (not via `_record_action`) ensures the FATAL entry is always written even when `_record_action` itself is the failing function. `_FLIGHT_RECORDER_SEQ` is incremented to maintain sequence integrity.

### 3.3 `output_bytes` Normalization

The `output_bytes` field is currently populated by the `wc -c` pipeline. After the fix, the same field is populated by the restructured group expression. The field remains of type integer and semantics are unchanged — it is the byte count of the `stdout_file` produced by `claude -p`.

---

## 4. Security Design

### 4.1 ERR Trap — No New Attack Surface

The ERR trap reads two bash built-in variables: `$LINENO` (integer) and `$BASH_COMMAND` (string containing the triggering command text). Neither is derived from external input. `$BASH_COMMAND` is controlled by the script itself — it reflects what the shell was executing at the time of the error.

The FATAL flight-recorder entry is constructed with `jq -n --arg verdict "ERR at line $lineno: $cmd"`. The `--arg` binding prevents the verdict string from being interpreted as a jq filter, regardless of its content. This is consistent with the project's established pattern for safe jq construction (see `spiral-evidence.sh` `_record_action`).

### 4.2 `|| true` Guard — No Bypass of Quality Gates

The `|| true` guard is applied only to the `_record_action` call inside `_invoke_claude`. It does **not** affect:
- `_record_failure` calls at gate verification sites
- `_record_action` calls in `main()` outside `_invoke_claude`
- The `claude -p` exit code propagation (`return "$exit_code"` is unchanged)

A caller cannot use recording failure to bypass a gate decision. Gate verdicts are derived from artifact content, not from `_record_action` return values.

### 4.3 `wc -c` Fix — Input Canonicalization

The restructured expression `{ wc -c < "$stdout_file" 2>/dev/null || echo 0; }` reads from `$stdout_file`, a path under `$EVIDENCE_DIR` which is derived from `$CYCLE_DIR` (a caller-supplied argument). This is the same data source as before. No new file paths are read, and no user-controlled content is interpolated into the expression.

### 4.4 File Permissions

The flight recorder is created with `umask 077 && touch` followed by `chmod 600`. The ERR trap appends to the same file — no permission change is introduced.

---

## 5. Error Handling

### 5.1 Before This Fix

| Failure | Visible Output | Flight Recorder Entry | Diagnosable? |
|---------|---------------|----------------------|--------------|
| `wc -c` exits nonzero | None | None | No |
| `_record_action` returns 1 | None | None | No |
| Any other ERR in `main()` | None | None | No |

### 5.2 After This Fix

| Failure | Visible Output | Flight Recorder Entry | Diagnosable? |
|---------|---------------|----------------------|--------------|
| `wc -c` exits nonzero | Not triggered (fix A prevents) | Normal `invoke` entry | Yes — normal entry |
| `_record_action` returns 1 in `_invoke_claude` | Not triggered (`\|\| true` fix) | No entry (recording failed, non-fatal) | Partial — no entry but harness continues |
| Any unhandled ERR in `main()` | `[FATAL] spiral-harness.sh: ERR at line N: cmd` to stderr | FATAL entry in recorder (if open) | Yes |

### 5.3 ERR Trap Non-Suppression

The ERR trap handler executes and then returns normally. Because the trap is registered with `trap '...' ERR` (not `trap '... ; exit 0' ERR`), bash continues with the original exit-status propagation — the harness terminates with the nonzero status that triggered the trap. The trap is an observer, not a suppressor.

### 5.4 Flight Recorder Not Yet Open

If the ERR trap fires before `_init_flight_recorder` has been called (e.g., during argument parsing), `$_FLIGHT_RECORDER` is empty. The trap writes only to stderr in that case. This is safe — no write to an uninitialized path, no silent failure.

### 5.5 `_record_action` Failure Warning

Per PRD §3 assumption 7, `_invoke_claude`'s `|| true` guard swallows the recording failure. An operator watching harness output will not see a warning for this case. If observable recording failures are desired in a future enhancement, `_invoke_claude` could log a warning before the `|| true` recovers. That is explicitly out of scope for this fix (PRD §6).

---

## 6. Flatline Findings

The most recent Flatline run logged to `grimoires/loa/a2a/trajectory/flatline-2026-04-16.jsonl` targeted the wave-3 BATS cleanup sprint (Issue #534). The applicable Flatline review will run against the PR for this branch after implementation.

The following findings from the 2026-04-16 Flatline run are proactively addressed in this design where applicable:

| Finding | Relevance | How Addressed |
|---------|-----------|---------------|
| **IMP-002**: Full-suite BATS run as regression guard | New BATS test must integrate into the full suite | Test placed in `tests/unit/`; `bats tests/` runs it automatically via directory discovery |
| **IMP-003**: `setup_file()` omission risk for isolation | BATS test fixture setup correctness | Test uses `setup()` / `teardown()` lifecycle; temp dir scoped per test case to prevent cross-test leakage |
| **IMP-004**: Temp-dir scaffolding variants | Test creates its own mock binary dir | Mock bins placed in `$TEST_TMPDIR/bin`, prepended to `PATH` in `setup()`, removed in `teardown()` |
| **IMP-010**: Dependency validation sequence | Test validates narrow behavior, not full pipeline | Test is scoped to ERR trap emission and `_invoke_claude` exit-code propagation; does not invoke the full pipeline or require external tools beyond bash and bats |

No BLOCKER findings from the 2026-04-16 run apply to this fix — those findings (SKP-001, SKP-003, SKP-007) were scoped to BATS grep-pattern coverage for the wave-3 audit and are not relevant to a targeted two-site harness fix with a dedicated regression test.

---

## 7. Implementation Checklist

Derived from PRD §5 Acceptance Criteria:

- [ ] Define `_harness_err_handler()` function in `spiral-harness.sh` that: (a) captures `$1` as `lineno` and `$2` as `cmd`, (b) emits `[FATAL] spiral-harness.sh: ERR at line $lineno: $cmd` to stderr via `error` or direct `echo >&2`, (c) appends a FATAL JSONL entry to `$_FLIGHT_RECORDER` via `jq -n -c` with `--arg` binding when `$_FLIGHT_RECORDER` is non-empty
- [ ] Register `trap '_harness_err_handler $LINENO "$BASH_COMMAND"' ERR` in `main()` after `_parse_args` and before the first `_record_action "CONFIG"` call (line ~972)
- [ ] ERR trap does not suppress exit — handler returns normally, original exit status propagates
- [ ] Replace `$(wc -c < "$stdout_file" 2>/dev/null | tr -d ' ' || echo 0)` with `"$({ wc -c < "$stdout_file" 2>/dev/null || echo 0; } | tr -d ' ')"` in `_invoke_claude` (line ~242)
- [ ] Append `|| true` to the `_record_action` call at the end of `_invoke_claude` (line ~241–243), after the fixed `wc -c` expression
- [ ] No other lines in `_invoke_claude` are modified
- [ ] Create `tests/unit/spiral-harness-err-trap.bats` with regression comment referencing Issue #516
- [ ] TC-1: simulate `_record_action` failure (e.g., unset `_FLIGHT_RECORDER` or mock `_record_action` to `return 1`); assert stderr contains line matching `FATAL`
- [ ] TC-2: mock `claude -p` shim in `$TEST_TMPDIR/bin` exiting with code 42; mock `_record_action` to `return 1`; assert `_invoke_claude` exits with 42 and the test process does not exit
- [ ] `bats tests/unit/spiral-harness-err-trap.bats` exits 0
- [ ] Full `bats tests/` exits with no newly introduced failures
