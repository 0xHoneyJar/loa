#!/usr/bin/env bats
# =============================================================================
# tests/integration/ledger-hygiene-tripwire.bats
#
# cycle-124 FR-6 (AC-6.2, AC-6.3) — tools/check-ledger-hygiene.sh contract and
# the seal → move → fresh-chain rotation the runbook prescribes
# (grimoires/loa/runbooks/ledger-hygiene-rotation.md).
#
# Contract proven here:
#   LH-1: mock-row fixture → exit 1, cost-ledger.jsonl:<line> printed (the
#         corrupt line before it is skipped, not fatal)
#   LH-2: e2e-path fixture → exit 1, model-invoke.jsonl:<line> printed
#   LH-3: clean fixture → exit 0
#   LH-4: absent ledger → SKIP line, exit 0 (never a silent clean); an absent
#         default .run/ is two SKIPs and exit 0
#   LH-5: --quiet keeps the exit code, drops the listing, keeps SKIP
#   LH-6: unknown argument / nonexistent --root → exit 2
#   LH-7: a MODELINV chain built through audit-envelope.sh, sealed and moved,
#         still verifies; the next emit on the vacated path restarts at GENESIS
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
    SCANNER="$PROJECT_ROOT/tools/check-ledger-hygiene.sh"
    FIXTURES="$PROJECT_ROOT/tests/fixtures/ledger-hygiene"
    AUDIT_ENVELOPE="$PROJECT_ROOT/.claude/scripts/audit-envelope.sh"
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
}

@test "scanner: mock-row fixture is rejected with cost-ledger.jsonl:<line> (LH-1)" {
    run bash "$SCANNER" --root "$FIXTURES/mock-row"
    [ "$status" -eq 1 ]
    [[ "$output" == *"mock-row/cost-ledger.jsonl:3:"* ]]
    [[ "$output" != *"model-invoke.jsonl:"* ]]
}

@test "scanner: e2e-path fixture is rejected with model-invoke.jsonl:<line> (LH-2)" {
    run bash "$SCANNER" --root "$FIXTURES/e2e-path"
    [ "$status" -eq 1 ]
    [[ "$output" == *"e2e-path/model-invoke.jsonl:2:"* ]]
    [[ "$output" != *"cost-ledger.jsonl:"* ]]
}

@test "scanner: clean fixture passes (LH-3)" {
    run bash "$SCANNER" --root "$FIXTURES/clean"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
    [[ "$output" != *"SKIP"* ]]
}

@test "scanner: absent ledger prints SKIP and exits 0 — never silently clean (LH-4)" {
    local root="$BATS_TEST_TMPDIR/only-modelinv"
    mkdir -p "$root"
    cp "$FIXTURES/clean/model-invoke.jsonl" "$root/"
    run bash "$SCANNER" --root "$root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP: $root/cost-ledger.jsonl absent (nothing scanned)"* ]]
    [[ "$output" == *"OK"* ]]

    local empty="$BATS_TEST_TMPDIR/empty"
    mkdir -p "$empty"
    run bash "$SCANNER" --root "$empty"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP: $empty/cost-ledger.jsonl absent"* ]]
    [[ "$output" == *"SKIP: $empty/model-invoke.jsonl absent"* ]]

    # Default root: a checkout with no .run/ at all (gitignored) is two SKIPs
    # and exit 0 — the CI post-test step must not error on a fully isolated run.
    local no_run="$BATS_TEST_TMPDIR/no-run-dir"
    mkdir -p "$no_run"
    run bash -c "cd '$no_run' && bash '$SCANNER'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP: .run/cost-ledger.jsonl absent"* ]]
    [[ "$output" == *"SKIP: .run/model-invoke.jsonl absent"* ]]
}

@test "scanner: --quiet keeps the exit code, drops the listing, keeps SKIP (LH-5)" {
    run bash "$SCANNER" --root "$FIXTURES/mock-row" --quiet
    [ "$status" -eq 1 ]
    [[ "$output" != *"cost-ledger.jsonl:3"* ]]

    local empty="$BATS_TEST_TMPDIR/quiet-empty"
    mkdir -p "$empty"
    run bash "$SCANNER" --root "$empty" --quiet
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP:"* ]]
}

@test "scanner: unknown argument and nonexistent --root exit 2 (LH-6)" {
    run bash "$SCANNER" --bogus-flag
    [ "$status" -eq 2 ]
    run bash "$SCANNER" --root "$BATS_TEST_TMPDIR/does-not-exist"
    [ "$status" -eq 2 ]
}

@test "rotation: sealed + moved MODELINV chain still verifies; fresh chain restarts at GENESIS (LH-7)" {
    [[ -f "$AUDIT_ENVELOPE" ]] || skip "audit-envelope.sh not present"
    command -v python3 >/dev/null 2>&1 || skip "python3 not on PATH"
    # Bootstrap posture (no keys, no trust store → BOOTSTRAP-PENDING permits
    # unsigned writes and verification). Needed because the tracked
    # grimoires/loa/trust-store.yaml carries a 2026-06-29 signing cutoff: on a
    # runner without keys an unsigned post-cutoff envelope would fail
    # verification, and on an operator box the host key would sign it. The
    # mechanics under test — seal marker skipped, GENESIS restart — are the
    # same either way; the runbook's live run keeps the host posture.
    unset LOA_AUDIT_SIGNING_KEY_ID LOA_AUDIT_KEY_DIR LOA_AUDIT_STRICT_VERIFY
    export LOA_TRUST_STORE_FILE="$BATS_TEST_TMPDIR/no-trust-store.yaml"
    export LOA_PINNED_ROOT_PUBKEY_PATH="$BATS_TEST_TMPDIR/no-root.pub"

    local run_dir="$BATS_TEST_TMPDIR/run"
    local archive_dir="$run_dir/archive"
    mkdir -p "$archive_dir"
    local log="$run_dir/model-invoke.jsonl"
    local payload='{"models_requested":["anthropic:claude-opus-4-7"],"models_succeeded":["anthropic:claude-opus-4-7"],"models_failed":[],"operator_visible_warn":false,"kill_switch_active":false}'

    run bash "$AUDIT_ENVELOPE" emit MODELINV model.invoke.complete "$payload" "$log"
    [ "$status" -eq 0 ]
    run bash "$AUDIT_ENVELOPE" emit MODELINV model.invoke.complete "$payload" "$log"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$log")" -eq 2 ]
    run bash "$AUDIT_ENVELOPE" verify-chain "$log"
    [ "$status" -eq 0 ]

    # Runbook: verify → seal → mv (UTC stamp) → verify the archive.
    run bash "$AUDIT_ENVELOPE" seal MODELINV "$log"
    [ "$status" -eq 0 ]
    [ "$(tail -n 1 "$log")" = "[MODELINV-DISABLED]" ]
    local archive="$archive_dir/model-invoke-$(date -u +%Y%m%dT%H%M%SZ).jsonl"
    mv "$log" "$archive"
    run bash "$AUDIT_ENVELOPE" verify-chain "$archive"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK 2 entries"* ]]

    # Vacated path: the scanner says SKIP (not a silent clean) and the next
    # emit starts a fresh chain at GENESIS instead of chaining to the archive.
    run bash "$SCANNER" --root "$run_dir"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP: $log absent"* ]]
    run bash "$AUDIT_ENVELOPE" emit MODELINV model.invoke.complete "$payload" "$log"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.prev_hash' "$log")" = "GENESIS" ]
    run bash "$AUDIT_ENVELOPE" verify-chain "$log"
    [ "$status" -eq 0 ]
    run bash "$SCANNER" --root "$run_dir"
    [ "$status" -eq 0 ]
}
