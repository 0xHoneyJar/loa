#!/usr/bin/env bats
# =============================================================================
# tests/integration/structured-handoff-6a.bats
#
# cycle-098 Sprint 6A — L6 structured-handoff foundation tests.
# Covers FR-L6-1 (schema validation), FR-L6-2 (file path), FR-L6-3 (atomic INDEX),
# FR-L6-6 (content-addressable id), FR-L6-7 (references verbatim).
#
# Sprints 6B/6C/6D ship their own bats files; tests here pin 6A invariants.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    LIB="$PROJECT_ROOT/.claude/scripts/lib/structured-handoff-lib.sh"
    [[ -f "$LIB" ]] || skip "structured-handoff-lib.sh not present"

    TEST_DIR="$(mktemp -d)"
    HANDOFFS_DIR="$TEST_DIR/handoffs"
    mkdir -p "$HANDOFFS_DIR"

    # Trust-store fixture: pointing at a non-existent path → BOOTSTRAP-PENDING,
    # which permits audit_emit writes per the auto-verify gate.
    export LOA_TRUST_STORE_FILE="$TEST_DIR/no-such-trust-store.yaml"

    # Audit log dir + path under TEST_DIR.
    export LOA_HANDOFF_LOG="$TEST_DIR/handoff-events.jsonl"

    # Sprint 6B: bypass OPERATORS.md verification for 6A schema/id/atomic tests.
    # 6B has its own bats file that exercises verify_operators with fixtures.
    export LOA_HANDOFF_VERIFY_OPERATORS=0

    # Use a fixed ts so collisions/filenames are predictable.
    TEST_TS_UTC="2026-05-07T12:00:00Z"

    # shellcheck source=/dev/null
    source "$LIB"
}

teardown() {
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
}

# Helper: write a minimal valid handoff doc to TEST_DIR/<name>.md.
# Args: name [overrides_yaml_block]
_make_doc() {
    local name="$1"; shift || true
    local extra="${1:-}"
    local path="$TEST_DIR/$name"
    cat > "$path" <<EOF
---
schema_version: '1.0'
from: 'alice'
to: 'bob'
topic: 'retry-policy'
ts_utc: '$TEST_TS_UTC'
references:
  - 'github.com/0xHoneyJar/loa/issues/658'
  - 'commit:abc1234'
tags:
  - 'bedrock'
$extra
---

# Body

This is the handoff body.
EOF
    printf '%s' "$path"
}

# -----------------------------------------------------------------------------
# FR-L6-1: schema validation
# -----------------------------------------------------------------------------

@test "T1 (FR-L6-1) missing required 'from' field is rejected" {
    local path="$TEST_DIR/bad.md"
    cat > "$path" <<EOF
---
schema_version: '1.0'
to: 'bob'
topic: 'retry-policy'
ts_utc: '$TEST_TS_UTC'
---
body
EOF
    run handoff_write "$path" --handoffs-dir "$HANDOFFS_DIR"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"frontmatter validation"* ]] || [[ "$output" == *"from"* ]]
}

@test "T2 (FR-L6-1) unknown frontmatter key is rejected (additionalProperties:false)" {
    local path
    path="$(_make_doc unknown.md "rogue_key: 'lol'")"
    run handoff_write "$path" --handoffs-dir "$HANDOFFS_DIR"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"unknown frontmatter keys"* ]] || [[ "$output" == *"rogue_key"* ]]
}

@test "T3 (FR-L6-1) traversal-style 'topic' is rejected by slug regex" {
    local path="$TEST_DIR/trav.md"
    cat > "$path" <<EOF
---
schema_version: '1.0'
from: 'alice'
to: 'bob'
topic: '../etc/passwd'
ts_utc: '$TEST_TS_UTC'
---
body
EOF
    run handoff_write "$path" --handoffs-dir "$HANDOFFS_DIR"
    [[ "$status" -eq 2 ]]
}

@test "T4 (FR-L6-1) malformed ts_utc rejected" {
    local path="$TEST_DIR/badts.md"
    cat > "$path" <<EOF
---
schema_version: '1.0'
from: 'alice'
to: 'bob'
topic: 'retry-policy'
ts_utc: 'yesterday'
---
body
EOF
    run handoff_write "$path" --handoffs-dir "$HANDOFFS_DIR"
    [[ "$status" -eq 2 ]]
}

@test "T5 (FR-L6-1+bounds) far-future ts_utc rejected" {
    local path="$TEST_DIR/future.md"
    cat > "$path" <<EOF
---
schema_version: '1.0'
from: 'alice'
to: 'bob'
topic: 'retry-policy'
ts_utc: '2099-01-01T00:00:00Z'
---
body
EOF
    run handoff_write "$path" --handoffs-dir "$HANDOFFS_DIR"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"more than 24h in the future"* ]]
}

@test "T24 (FR-L6-1) wrong schema_version rejected" {
    local path
    path="$(_make_doc wrong-sv.md)"
    # Edit schema_version in place.
    sed -i.bak "s/schema_version: '1.0'/schema_version: '2.0'/" "$path"
    run handoff_write "$path" --handoffs-dir "$HANDOFFS_DIR"
    [[ "$status" -eq 2 ]]
}

# -----------------------------------------------------------------------------
# FR-L6-2: file path layout
# -----------------------------------------------------------------------------

@test "T6 (FR-L6-2) file written to <date>-<from>-<to>-<topic>.md" {
    local path
    path="$(_make_doc h1.md)"
    run handoff_write "$path" --handoffs-dir "$HANDOFFS_DIR"
    [[ "$status" -eq 0 ]]
    [[ -f "$HANDOFFS_DIR/2026-05-07-alice-bob-retry-policy.md" ]]
}

# -----------------------------------------------------------------------------
# FR-L6-3: INDEX.md atomic update
# -----------------------------------------------------------------------------

@test "T7 (FR-L6-3) INDEX.md created with header + row" {
    local path
    path="$(_make_doc h2.md)"
    handoff_write "$path" --handoffs-dir "$HANDOFFS_DIR" >/dev/null
    [[ -f "$HANDOFFS_DIR/INDEX.md" ]]
    grep -q "^# Handoff Index" "$HANDOFFS_DIR/INDEX.md"
    grep -q "| handoff_id |" "$HANDOFFS_DIR/INDEX.md"
    grep -q "| sha256:" "$HANDOFFS_DIR/INDEX.md"
    grep -q "alice" "$HANDOFFS_DIR/INDEX.md"
    grep -q "retry-policy" "$HANDOFFS_DIR/INDEX.md"
}

@test "T8 (FR-L6-3) concurrent writes preserve INDEX integrity (5 parallel writers)" {
    # 5 distinct handoff topics → 5 distinct files; INDEX should have exactly 5 data rows.
    local i=0
    for i in 1 2 3 4 5; do
        local path="$TEST_DIR/h-par-$i.md"
        cat > "$path" <<EOF
---
schema_version: '1.0'
from: 'alice'
to: 'bob'
topic: 'topic-par-$i'
ts_utc: '$TEST_TS_UTC'
---
body $i
EOF
    done

    # Spawn 5 concurrent writers; each in its own subshell so flock can block.
    local pids=()
    for i in 1 2 3 4 5; do
        ( source "$LIB"
          handoff_write "$TEST_DIR/h-par-$i.md" --handoffs-dir "$HANDOFFS_DIR" >/dev/null
        ) &
        pids+=("$!")
    done
    for pid in "${pids[@]}"; do wait "$pid"; done

    # Exactly 5 data rows (lines starting "| sha256:").
    local row_count
    row_count="$(grep -c '^| sha256:' "$HANDOFFS_DIR/INDEX.md")"
    [[ "$row_count" -eq 5 ]]

    # No half-written line (every row has 8 pipes per the schema).
    while IFS= read -r line; do
        local pipes
        pipes="$(echo -n "$line" | awk -F'|' '{print NF}')"
        # 7 fields + 2 sentinels (start + end pipe) = 9 → NF=9
        [[ "$pipes" -eq 9 ]] || { echo "malformed row: $line"; return 1; }
    done < <(grep '^| sha256:' "$HANDOFFS_DIR/INDEX.md")
}

# -----------------------------------------------------------------------------
# FR-L6-6: handoff_id content-addressable
# -----------------------------------------------------------------------------

@test "T9 (FR-L6-6) same content → same handoff_id" {
    local p1 p2
    p1="$(_make_doc id-a.md)"
    p2="$(_make_doc id-b.md)"
    local id1 id2
    id1="$(handoff_compute_id "$p1")"
    id2="$(handoff_compute_id "$p2")"
    [[ "$id1" == "$id2" ]]
    [[ "$id1" =~ ^sha256:[a-f0-9]{64}$ ]]
}

@test "T9b (FR-L6-6) byte-different body → different handoff_id" {
    local p1="$TEST_DIR/diff-a.md" p2="$TEST_DIR/diff-b.md"
    cat > "$p1" <<EOF
---
schema_version: '1.0'
from: 'alice'
to: 'bob'
topic: 'retry-policy'
ts_utc: '$TEST_TS_UTC'
---
body A
EOF
    cat > "$p2" <<EOF
---
schema_version: '1.0'
from: 'alice'
to: 'bob'
topic: 'retry-policy'
ts_utc: '$TEST_TS_UTC'
---
body B
EOF
    local id1 id2
    id1="$(handoff_compute_id "$p1")"
    id2="$(handoff_compute_id "$p2")"
    [[ "$id1" != "$id2" ]]
}

@test "T10 (FR-L6-6) handoff_id deterministic regardless of frontmatter key order" {
    local p1="$TEST_DIR/order-1.md" p2="$TEST_DIR/order-2.md"
    cat > "$p1" <<EOF
---
schema_version: '1.0'
from: 'alice'
to: 'bob'
topic: 'retry-policy'
ts_utc: '$TEST_TS_UTC'
---
body
EOF
    cat > "$p2" <<EOF
---
ts_utc: '$TEST_TS_UTC'
topic: 'retry-policy'
to: 'bob'
from: 'alice'
schema_version: '1.0'
---
body
EOF
    local id1 id2
    id1="$(handoff_compute_id "$p1")"
    id2="$(handoff_compute_id "$p2")"
    [[ "$id1" == "$id2" ]]
}

@test "T11 (FR-L6-6) wrong supplied handoff_id rejected with exit 6" {
    local p="$TEST_DIR/wrong-id.md"
    cat > "$p" <<EOF
---
schema_version: '1.0'
handoff_id: 'sha256:0000000000000000000000000000000000000000000000000000000000000000'
from: 'alice'
to: 'bob'
topic: 'retry-policy'
ts_utc: '$TEST_TS_UTC'
---
body
EOF
    run handoff_write "$p" --handoffs-dir "$HANDOFFS_DIR"
    [[ "$status" -eq 6 ]]
    [[ "$output" == *"handoff_id mismatch"* ]]
}

@test "T12 (FR-L6-6) correct supplied handoff_id accepted" {
    local p="$TEST_DIR/correct-id.md"
    cat > "$p" <<EOF
---
schema_version: '1.0'
from: 'alice'
to: 'bob'
topic: 'retry-policy'
ts_utc: '$TEST_TS_UTC'
---
body
EOF
    local id; id="$(handoff_compute_id "$p")"
    # Re-emit with the id pinned.
    cat > "$p" <<EOF
---
schema_version: '1.0'
handoff_id: '$id'
from: 'alice'
to: 'bob'
topic: 'retry-policy'
ts_utc: '$TEST_TS_UTC'
---
body
EOF
    run handoff_write "$p" --handoffs-dir "$HANDOFFS_DIR"
    [[ "$status" -eq 0 ]]
}

# -----------------------------------------------------------------------------
# FR-L6-7: references preserved verbatim
# -----------------------------------------------------------------------------

@test "T13 (FR-L6-7) references preserved verbatim incl. URLs and special chars" {
    local p="$TEST_DIR/refs.md"
    cat > "$p" <<EOF
---
schema_version: '1.0'
from: 'alice'
to: 'bob'
topic: 'refs-test'
ts_utc: '$TEST_TS_UTC'
references:
  - 'https://github.com/0xHoneyJar/loa/issues/658#issuecomment-12345'
  - 'commit:abc1234def5678'
  - 'grimoires/loa/sprint.md#sprint-6'
  - 'PR #770: ⚡ unicode test ✓'
---
body
EOF
    handoff_write "$p" --handoffs-dir "$HANDOFFS_DIR" >/dev/null
    local out_file="$HANDOFFS_DIR/2026-05-07-alice-bob-refs-test.md"
    grep -q 'https://github.com/0xHoneyJar/loa/issues/658#issuecomment-12345' "$out_file"
    grep -q 'commit:abc1234def5678' "$out_file"
    grep -q 'grimoires/loa/sprint.md#sprint-6' "$out_file"
    grep -q 'PR #770' "$out_file"
    grep -q '⚡ unicode test ✓' "$out_file"
}

# -----------------------------------------------------------------------------
# Audit envelope integration
# -----------------------------------------------------------------------------

@test "T14 audit event emitted with primitive_id=L6 and event_type=handoff.write" {
    local p
    p="$(_make_doc audit.md)"
    handoff_write "$p" --handoffs-dir "$HANDOFFS_DIR" >/dev/null
    [[ -f "$LOA_HANDOFF_LOG" ]]
    local line
    line="$(grep -v '^\[' "$LOA_HANDOFF_LOG" | head -1)"
    [[ -n "$line" ]]
    local pid evt
    pid="$(echo "$line" | jq -r '.primitive_id')"
    evt="$(echo "$line" | jq -r '.event_type')"
    [[ "$pid" == "L6" ]]
    [[ "$evt" == "handoff.write" ]]
}

@test "T15 _audit_primitive_id_for_log maps handoff-events.jsonl → L6" {
    source "$PROJECT_ROOT/.claude/scripts/audit-envelope.sh"
    run _audit_primitive_id_for_log "/tmp/handoff-events.jsonl"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "L6" ]]
}

@test "T15b retention-policy alignment: lib default log basename matches policy" {
    # Retention policy declares L6 log_basename = handoff-events.jsonl
    local policy_basename
    policy_basename="$(yq '.primitives.L6.log_basename' "$PROJECT_ROOT/.claude/data/audit-retention-policy.yaml")"
    [[ "$policy_basename" == "handoff-events.jsonl" ]]
    # Lib's default LOA_HANDOFF_LOG basename must match.
    local lib_basename
    lib_basename="$(basename "$_LOA_HANDOFF_DEFAULT_LOG")"
    [[ "$lib_basename" == "handoff-events.jsonl" ]]
}

# -----------------------------------------------------------------------------
# Path resolution + system-path rejection (pre-emptive hardening)
# -----------------------------------------------------------------------------

@test "T16 handoffs_dir defaults to repo grimoires/loa/handoffs when no override" {
    # Use the lib's resolver in isolation; do NOT actually write into the repo.
    local resolved
    resolved="$(_handoff_resolve_dir "")"
    # Should end with grimoires/loa/handoffs (resolved real path).
    [[ "$resolved" == */grimoires/loa/handoffs ]]
}

@test "T17 system-path rejection: --handoffs-dir /etc → exit 7" {
    local p
    p="$(_make_doc syspath.md)"
    run handoff_write "$p" --handoffs-dir "/etc"
    [[ "$status" -eq 7 ]]
}

@test "T17b system-path rejection: /usr/local subpath → exit 7" {
    local p
    p="$(_make_doc syspath2.md)"
    run handoff_write "$p" --handoffs-dir "/usr/local/lib"
    [[ "$status" -eq 7 ]]
}

# -----------------------------------------------------------------------------
# handoff_list / handoff_read
# -----------------------------------------------------------------------------

@test "T18 handoff_list returns INDEX rows" {
    local p
    p="$(_make_doc list1.md)"
    handoff_write "$p" --handoffs-dir "$HANDOFFS_DIR" >/dev/null
    run handoff_list --handoffs-dir "$HANDOFFS_DIR"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"sha256:"* ]]
    [[ "$output" == *"alice"* ]]
}

@test "T19 handoff_list --to filter excludes non-matching rows" {
    local p1 p2
    p1="$TEST_DIR/list-a.md" p2="$TEST_DIR/list-b.md"
    cat > "$p1" <<EOF
---
schema_version: '1.0'
from: 'alice'
to: 'bob'
topic: 'list-a'
ts_utc: '$TEST_TS_UTC'
---
body
EOF
    cat > "$p2" <<EOF
---
schema_version: '1.0'
from: 'alice'
to: 'carol'
topic: 'list-b'
ts_utc: '$TEST_TS_UTC'
---
body
EOF
    handoff_write "$p1" --handoffs-dir "$HANDOFFS_DIR" >/dev/null
    handoff_write "$p2" --handoffs-dir "$HANDOFFS_DIR" >/dev/null
    run handoff_list --to bob --handoffs-dir "$HANDOFFS_DIR"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"list-a"* ]]
    [[ "$output" != *"list-b"* ]]
}

@test "T20 handoff_list --unread returns all when none marked read" {
    local p
    p="$(_make_doc unread1.md)"
    handoff_write "$p" --handoffs-dir "$HANDOFFS_DIR" >/dev/null
    run handoff_list --unread --handoffs-dir "$HANDOFFS_DIR"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"sha256:"* ]]
}

@test "T21 handoff_read prints body verbatim (no frontmatter)" {
    local p="$TEST_DIR/read1.md"
    cat > "$p" <<EOF
---
schema_version: '1.0'
from: 'alice'
to: 'bob'
topic: 'read-test'
ts_utc: '$TEST_TS_UTC'
---
# Title

Body line A.
Body line B.
EOF
    local result
    result="$(handoff_write "$p" --handoffs-dir "$HANDOFFS_DIR")"
    local id; id="$(echo "$result" | jq -r '.handoff_id')"
    run handoff_read "$id" --handoffs-dir "$HANDOFFS_DIR"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"# Title"* ]]
    [[ "$output" == *"Body line A."* ]]
    [[ "$output" == *"Body line B."* ]]
    [[ "$output" != *"schema_version"* ]]
}

# -----------------------------------------------------------------------------
# Sprint 6A scope guard: collision behavior — Sprint 6B resolves with suffix.
# Test pins forward to the new behavior (numeric suffix). Detailed coverage in
# tests/integration/structured-handoff-6b.bats.
# -----------------------------------------------------------------------------

@test "T22 collision on (date,from,to,topic) gets numeric suffix" {
    local p1 p2
    p1="$(_make_doc collide-1.md)"
    p2="$TEST_DIR/collide-2.md"
    cat > "$p2" <<EOF
---
schema_version: '1.0'
from: 'alice'
to: 'bob'
topic: 'retry-policy'
ts_utc: '$TEST_TS_UTC'
---
different body
EOF
    handoff_write "$p1" --handoffs-dir "$HANDOFFS_DIR" >/dev/null
    run handoff_write "$p2" --handoffs-dir "$HANDOFFS_DIR"
    [[ "$status" -eq 0 ]]
    # Two files now exist: base.md + base-2.md
    [[ -f "$HANDOFFS_DIR/2026-05-07-alice-bob-retry-policy.md" ]]
    [[ -f "$HANDOFFS_DIR/2026-05-07-alice-bob-retry-policy-2.md" ]]
}

# -----------------------------------------------------------------------------
# Stdout JSON contract
# -----------------------------------------------------------------------------

@test "T23 stdout result is JSON {handoff_id, file_path, ts_utc}" {
    local p
    p="$(_make_doc stdout.md)"
    local out
    out="$(handoff_write "$p" --handoffs-dir "$HANDOFFS_DIR")"
    echo "$out" | jq -e '.handoff_id | startswith("sha256:")' >/dev/null
    echo "$out" | jq -e '.file_path | test("handoffs/.*\\.md$")' >/dev/null
    echo "$out" | jq -e '.ts_utc' >/dev/null
}
