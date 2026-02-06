#!/usr/bin/env bats
# Integration tests for Loa Event Bus
#
# Tests the file-backed event bus (event-bus.sh) end-to-end:
#   1. Event emission and storage
#   2. Event consumption with offset tracking
#   3. Idempotency (duplicate detection)
#   4. Dead letter queue routing
#   5. Correlation chain propagation
#   6. Bus status and introspection
#   7. Event registry and topology validation
#
# Prerequisites:
#   - jq (required for event bus)
#   - flock (required for atomic writes — standard on Linux)
#
# Why these tests matter:
#   At LinkedIn, Kafka processes 10M+ events/sec. At that scale, a bug in
#   event ordering or idempotency can corrupt millions of records. While Loa
#   doesn't operate at that scale, the same correctness guarantees apply.
#   A test that catches a duplicate-delivery bug in CI saves hours of
#   debugging in production.

# Per-test setup — each test gets an isolated event store
setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    EVENT_BUS="$PROJECT_ROOT/.claude/scripts/lib/event-bus.sh"
    EVENT_REGISTRY="$PROJECT_ROOT/.claude/scripts/lib/event-registry.sh"

    # Check prerequisites
    if ! command -v jq &>/dev/null; then
        skip "jq not found (required for event bus)"
    fi
    if ! command -v flock &>/dev/null; then
        skip "flock not found (required for atomic writes)"
    fi

    # Create isolated test directory (prevents cross-test contamination)
    TEST_EVENT_DIR="$(mktemp -d)"
    export LOA_EVENT_STORE_DIR="$TEST_EVENT_DIR"
    export LOA_EVENT_DLQ_FILE="$TEST_EVENT_DIR/dead-letter.events.jsonl"
    export LOA_EVENT_REGISTRY_FILE="$TEST_EVENT_DIR/.registry.json"
    export LOA_EVENT_IDEMPOTENCY_DIR="$TEST_EVENT_DIR/.idempotency"
    export LOA_EVENT_OFFSETS_DIR="$TEST_EVENT_DIR/.offsets"

    # Source the library
    source "$EVENT_BUS"
}

# Cleanup test directory
teardown() {
    rm -rf "$TEST_EVENT_DIR" 2>/dev/null || true
}

# =============================================================================
# Emission Tests
# =============================================================================

@test "emit_event: creates JSONL file with correct envelope" {
    local event_id
    event_id=$(emit_event "test.system.event_fired" '{"key":"value"}' "test/skill")

    # Event ID should be returned
    [[ -n "$event_id" ]]
    [[ "$event_id" == evt-* ]]

    # JSONL file should exist
    local partition_file="$TEST_EVENT_DIR/test.system.event_fired.events.jsonl"
    [[ -f "$partition_file" ]]

    # Should have exactly one line
    local line_count
    line_count=$(wc -l < "$partition_file")
    [[ "$line_count" -eq 1 ]]

    # Verify envelope fields
    local event
    event=$(cat "$partition_file")
    [[ "$(echo "$event" | jq -r '.specversion')" == "1.0" ]]
    [[ "$(echo "$event" | jq -r '.type')" == "test.system.event_fired" ]]
    [[ "$(echo "$event" | jq -r '.source')" == "test/skill" ]]
    [[ "$(echo "$event" | jq -r '.data.key')" == "value" ]]
    [[ "$(echo "$event" | jq -r '.datacontenttype')" == "application/json" ]]
}

@test "emit_event: includes correlation_id when provided" {
    emit_event "test.system.traced" '{"x":1}' "test/skill" "trace-abc123" > /dev/null

    local partition_file="$TEST_EVENT_DIR/test.system.traced.events.jsonl"
    local event
    event=$(cat "$partition_file")
    [[ "$(echo "$event" | jq -r '.correlation_id')" == "trace-abc123" ]]
}

@test "emit_event: includes causation_id for event chains" {
    emit_event "test.system.caused" '{"x":1}' "test/skill" "trace-1" "evt-parent-123" > /dev/null

    local partition_file="$TEST_EVENT_DIR/test.system.caused.events.jsonl"
    local event
    event=$(cat "$partition_file")
    [[ "$(echo "$event" | jq -r '.causation_id')" == "evt-parent-123" ]]
    [[ "$(echo "$event" | jq -r '.correlation_id')" == "trace-1" ]]
}

@test "emit_event: rejects invalid event type format" {
    run emit_event "INVALID_TYPE" '{"x":1}' "test/skill"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Invalid event type format"* ]]
}

@test "emit_event: rejects invalid JSON data" {
    run emit_event "test.system.bad_json" 'not-json' "test/skill"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"not valid JSON"* ]]
}

@test "emit_event: rejects oversized payload" {
    # Generate a payload larger than a small limit
    # This prevents runaway events from bloating the event store —
    # the same protection Kafka provides with max.message.bytes
    #
    # Override the runtime variable directly (env var is only read at
    # source time, so exporting after setup() won't take effect)
    EVENT_MAX_PAYLOAD_BYTES=100
    local big_data='{"padding":"'
    for _ in $(seq 1 120); do big_data+="x"; done
    big_data+='"}'

    run emit_event "test.system.big_payload" "$big_data" "test/skill"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"exceeds max payload size"* ]]
}

@test "emit_event: multiple events append to same partition" {
    emit_event "test.system.multi" '{"seq":1}' "test/a" > /dev/null
    emit_event "test.system.multi" '{"seq":2}' "test/b" > /dev/null
    emit_event "test.system.multi" '{"seq":3}' "test/c" > /dev/null

    local partition_file="$TEST_EVENT_DIR/test.system.multi.events.jsonl"
    local line_count
    line_count=$(wc -l < "$partition_file")
    [[ "$line_count" -eq 3 ]]

    # Verify ordering (append-only guarantees order)
    [[ "$(sed -n '1p' "$partition_file" | jq -r '.data.seq')" -eq 1 ]]
    [[ "$(sed -n '3p' "$partition_file" | jq -r '.data.seq')" -eq 3 ]]
}

@test "emit_event: different types go to different partitions" {
    emit_event "test.alpha.event" '{"t":"a"}' "test/skill" > /dev/null
    emit_event "test.beta.event" '{"t":"b"}' "test/skill" > /dev/null

    [[ -f "$TEST_EVENT_DIR/test.alpha.event.events.jsonl" ]]
    [[ -f "$TEST_EVENT_DIR/test.beta.event.events.jsonl" ]]
}

# =============================================================================
# Consumption Tests
# =============================================================================

@test "consume_events: processes all events from offset 0" {
    # Emit 3 events
    emit_event "test.consume.basic" '{"n":1}' "test/src" > /dev/null
    emit_event "test.consume.basic" '{"n":2}' "test/src" > /dev/null
    emit_event "test.consume.basic" '{"n":3}' "test/src" > /dev/null

    # Create a handler that counts events
    local handler_log="$TEST_EVENT_DIR/handler.log"
    local handler_script="$TEST_EVENT_DIR/handler.sh"
    cat > "$handler_script" << 'HANDLER'
#!/usr/bin/env bash
cat >> "$HANDLER_LOG"
echo "" >> "$HANDLER_LOG"
HANDLER
    chmod +x "$handler_script"
    export HANDLER_LOG="$handler_log"

    # Consume
    local processed
    processed=$(consume_events "test.consume.basic" "$handler_script")
    [[ "$processed" -eq 3 ]]
}

@test "consume_events: tracks offset across calls" {
    emit_event "test.consume.offset" '{"n":1}' "test/src" > /dev/null
    emit_event "test.consume.offset" '{"n":2}' "test/src" > /dev/null

    # Create a no-op handler
    local handler_script="$TEST_EVENT_DIR/noop.sh"
    echo '#!/usr/bin/env bash' > "$handler_script"
    echo 'cat > /dev/null' >> "$handler_script"
    chmod +x "$handler_script"

    # First consume — should process 2
    local first
    first=$(consume_events "test.consume.offset" "$handler_script" "group-a")
    [[ "$first" -eq 2 ]]

    # Emit 1 more
    emit_event "test.consume.offset" '{"n":3}' "test/src" > /dev/null

    # Second consume — should only process 1 (new event)
    local second
    second=$(consume_events "test.consume.offset" "$handler_script" "group-a")
    [[ "$second" -eq 1 ]]
}

# =============================================================================
# Idempotency Tests
# =============================================================================

@test "idempotency: duplicate events are not reprocessed" {
    # Register handler
    register_handler "test.idempotent.event" "$TEST_EVENT_DIR/counting-handler.sh"

    # Create counting handler
    local count_file="$TEST_EVENT_DIR/invocation_count"
    echo "0" > "$count_file"
    cat > "$TEST_EVENT_DIR/counting-handler.sh" << HANDLER
#!/usr/bin/env bash
count=\$(cat "$count_file")
echo \$((count + 1)) > "$count_file"
cat > /dev/null
HANDLER
    chmod +x "$TEST_EVENT_DIR/counting-handler.sh"

    # Emit event (handler fires via dispatch)
    emit_event "test.idempotent.event" '{"id":"dedup-1"}' "test/src" > /dev/null

    # Manually try to dispatch same event again
    local partition_file="$TEST_EVENT_DIR/test.idempotent.event.events.jsonl"
    local event
    event=$(cat "$partition_file")
    _dispatch_event "test.idempotent.event" "$event" || true

    # Handler should have been called only once (second dispatch skipped by idempotency)
    local final_count
    final_count=$(cat "$count_file")
    [[ "$final_count" -eq 1 ]]
}

# =============================================================================
# Dead Letter Queue Tests
# =============================================================================

@test "DLQ: failed handler routes event to dead letter queue" {
    # Register a handler that always fails
    register_handler "test.dlq.failing" "$TEST_EVENT_DIR/failing-handler.sh"

    cat > "$TEST_EVENT_DIR/failing-handler.sh" << 'HANDLER'
#!/usr/bin/env bash
cat > /dev/null
exit 1
HANDLER
    chmod +x "$TEST_EVENT_DIR/failing-handler.sh"

    # Emit event (will be dispatched to failing handler)
    emit_event "test.dlq.failing" '{"should":"fail"}' "test/src" > /dev/null 2>&1

    # DLQ should have the failed delivery
    [[ -f "$TEST_EVENT_DIR/dead-letter.events.jsonl" ]]
    local dlq_count
    dlq_count=$(wc -l < "$TEST_EVENT_DIR/dead-letter.events.jsonl")
    [[ "$dlq_count" -eq 1 ]]

    # DLQ entry should contain failure context
    local dlq_entry
    dlq_entry=$(cat "$TEST_EVENT_DIR/dead-letter.events.jsonl")
    [[ "$(echo "$dlq_entry" | jq -r '.event_type')" == "test.dlq.failing" ]]
    [[ "$(echo "$dlq_entry" | jq -r '.exit_code')" -eq 1 ]]
    [[ "$(echo "$dlq_entry" | jq -r '.event.data.should')" == "fail" ]]
}

@test "DLQ: captures handler stderr in error_output field" {
    # In production systems (AWS SQS DLQ, GCP Pub/Sub dead lettering),
    # the error context is the most valuable part of a dead letter.
    # Verify that handler stderr is preserved for debugging.
    register_handler "test.dlq.verbose" "$TEST_EVENT_DIR/verbose-fail.sh"

    cat > "$TEST_EVENT_DIR/verbose-fail.sh" << 'HANDLER'
#!/usr/bin/env bash
cat > /dev/null
echo "ERROR: connection refused to upstream service" >&2
exit 1
HANDLER
    chmod +x "$TEST_EVENT_DIR/verbose-fail.sh"

    emit_event "test.dlq.verbose" '{"debug":"true"}' "test/src" > /dev/null 2>&1

    local dlq_entry
    dlq_entry=$(cat "$TEST_EVENT_DIR/dead-letter.events.jsonl")
    [[ "$(echo "$dlq_entry" | jq -r '.error_output')" == *"connection refused"* ]]
}

# =============================================================================
# Query Tests
# =============================================================================

@test "query_events: filters by event type" {
    emit_event "test.query.alpha" '{"t":"a"}' "test/src" > /dev/null
    emit_event "test.query.beta" '{"t":"b"}' "test/src" > /dev/null

    local results
    results=$(query_events --type "test.query.alpha" --json)
    local count
    count=$(echo "$results" | jq length)
    [[ "$count" -eq 1 ]]
    [[ "$(echo "$results" | jq -r '.[0].data.t')" == "a" ]]
}

@test "query_events: filters by correlation_id across types" {
    emit_event "test.query.a" '{"step":1}' "test/src" "trace-xyz" > /dev/null
    emit_event "test.query.b" '{"step":2}' "test/src" "trace-xyz" "evt-1" > /dev/null
    emit_event "test.query.a" '{"step":3}' "test/src" "trace-other" > /dev/null

    # Query all events in the trace-xyz correlation chain
    local results
    results=$(query_events --correlation "trace-xyz" --json)
    local count
    count=$(echo "$results" | jq length)
    [[ "$count" -eq 2 ]]
}

@test "query_events: respects limit" {
    for i in 1 2 3 4 5; do
        emit_event "test.query.limited" "{\"n\":$i}" "test/src" > /dev/null
    done

    local results
    results=$(query_events --type "test.query.limited" --limit 3 --json)
    local count
    count=$(echo "$results" | jq length)
    [[ "$count" -eq 3 ]]
}

# =============================================================================
# Handler Registration Tests
# =============================================================================

@test "register_handler: adds handler to registry" {
    register_handler "test.reg.event" "/path/to/handler.sh" "broadcast"

    local handlers
    handlers=$(jq -r '.handlers["test.reg.event"] | length' "$TEST_EVENT_DIR/.registry.json")
    [[ "$handlers" -eq 1 ]]
}

@test "register_handler: prevents duplicate registration" {
    register_handler "test.reg.dedup" "/path/to/handler.sh"
    register_handler "test.reg.dedup" "/path/to/handler.sh"

    local handlers
    handlers=$(jq -r '.handlers["test.reg.dedup"] | length' "$TEST_EVENT_DIR/.registry.json")
    [[ "$handlers" -eq 1 ]]
}

@test "unregister_handler: removes handler from registry" {
    register_handler "test.unreg.event" "/path/to/handler.sh"
    unregister_handler "test.unreg.event" "/path/to/handler.sh"

    local handlers
    handlers=$(jq -r '.handlers["test.unreg.event"] | length' "$TEST_EVENT_DIR/.registry.json")
    [[ "$handlers" -eq 0 ]]
}

# =============================================================================
# Bus Status Tests
# =============================================================================

@test "bus_status: reports healthy state" {
    local status_json
    status_json=$(bus_status)

    [[ "$(echo "$status_json" | jq -r '.status')" == "HEALTHY" ]]
    [[ "$(echo "$status_json" | jq -r '.total_events')" -eq 0 ]]
    [[ "$(echo "$status_json" | jq -r '.dlq_depth')" -eq 0 ]]
}

@test "bus_status: counts events across types" {
    emit_event "test.status.a" '{"x":1}' "test/src" > /dev/null
    emit_event "test.status.b" '{"x":2}' "test/src" > /dev/null
    emit_event "test.status.a" '{"x":3}' "test/src" > /dev/null

    local status_json
    status_json=$(bus_status)

    [[ "$(echo "$status_json" | jq -r '.total_events')" -eq 3 ]]
    [[ "$(echo "$status_json" | jq -r '.event_types')" -eq 2 ]]
}

# =============================================================================
# CLI Tests
# =============================================================================

@test "CLI: emit command works" {
    run bash "$EVENT_BUS" emit "test.cli.event" '{"cli":true}' "test/cli"
    [[ "$status" -eq 0 ]]
    [[ "$output" == evt-* ]]
}

@test "CLI: status command returns JSON" {
    run bash "$EVENT_BUS" status
    [[ "$status" -eq 0 ]]
    echo "$output" | jq empty  # Must be valid JSON
}

@test "CLI: help flag works" {
    run bash "$EVENT_BUS" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"emit"* ]]
    [[ "$output" == *"consume"* ]]
    [[ "$output" == *"query"* ]]
}
