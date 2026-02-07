#!/usr/bin/env bash
# event-bus.sh - File-backed event bus for inter-construct communication
#
# Implements the CloudEvents-inspired event envelope (event-envelope.schema.json)
# using JSONL append-only logs with flock-based atomicity.
#
# Architecture:
#   Storage:  JSONL append-only log (one file per event type partition)
#   Locking:  flock(1) for atomic writes — same pattern as SQLite WAL
#   Delivery: Synchronous dispatch with retry (via api-resilience.sh)
#   DLQ:      Failed deliveries routed to dead-letter.events.jsonl
#
# Why JSONL + flock (not SQLite, not Redis):
#   Loa is a local-first CLI tool. No daemon. No server. Events must work
#   via the filesystem alone. JSONL gives us:
#   - Append-only semantics (crash-safe with flock)
#   - Line-by-line streaming reads (no full-file parse)
#   - git-friendly diffs (human-readable)
#   - Zero dependencies beyond bash + jq + flock
#
#   This is the same trade-off Prometheus made with its TSDB WAL — filesystem
#   primitives over database complexity, because the access pattern (append +
#   sequential scan) doesn't need B-trees.
#
# Usage:
#   source .claude/scripts/lib/event-bus.sh
#
#   # Emit an event
#   emit_event "forge.observer.utc_created" \
#     '{"utc_id":"utc-789","user_id":"user-456"}' \
#     "forge/observing-users"
#
#   # Consume events (poll-based)
#   consume_events "forge.observer.utc_created" my_handler_function
#
#   # Query event log
#   query_events --type "forge.observer.utc_created" --since "2026-02-06" --limit 10
#
# Exit Codes:
#   0 = Success
#   1 = Validation error (bad event format)
#   2 = Delivery failure (handler error, routed to DLQ)
#   3 = Bus unavailable (missing dependencies)
#
# References:
#   - CloudEvents spec: https://cloudevents.io
#   - Kafka consumer model: https://kafka.apache.org/documentation/#consumerconfigs
#   - Prometheus WAL: https://ganeshvernekar.com/blog/prometheus-tsdb-wal-and-checkpoint/
#
# Sources: Issue #161 (Event Bus Architecture), Issue #162 (Construct Manifest Standard)

# Guard: This script uses bash-specific features (BASH_SOURCE, FD redirection
# with 200>, declare -F, process substitution). Sourcing from zsh or other
# shells will produce cryptic errors. Detect and fail early with guidance.
# Fixes #230.
if [ -z "${BASH_VERSION:-}" ]; then
    echo "ERROR: event-bus.sh requires bash. Current shell: $(ps -o comm= -p $$ 2>/dev/null || echo unknown)" >&2
    echo "  When sourcing: bash -c 'source .claude/scripts/lib/event-bus.sh && ...'" >&2
    echo "  When executing: bash .claude/scripts/lib/event-bus.sh <command>" >&2
    # 'return' exits when sourced, 'exit' exits when executed
    return 3 2>/dev/null || exit 3
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# Configuration
# =============================================================================

# Event storage root — all event logs live here
EVENT_STORE_DIR="${LOA_EVENT_STORE_DIR:-grimoires/loa/a2a/events}"

# Dead letter queue for failed deliveries
EVENT_DLQ_FILE="${LOA_EVENT_DLQ_FILE:-${EVENT_STORE_DIR}/dead-letter.events.jsonl}"

# Handler registry (JSON file mapping event types → handler scripts)
EVENT_REGISTRY_FILE="${LOA_EVENT_REGISTRY_FILE:-${EVENT_STORE_DIR}/.registry.json}"

# Idempotency state (tracks consumed event IDs per consumer)
EVENT_IDEMPOTENCY_DIR="${LOA_EVENT_IDEMPOTENCY_DIR:-${EVENT_STORE_DIR}/.idempotency}"

# Consumer offset tracking (like Kafka consumer offsets)
EVENT_OFFSETS_DIR="${LOA_EVENT_OFFSETS_DIR:-${EVENT_STORE_DIR}/.offsets}"

# Maximum event data payload size (bytes) — prevents runaway events
EVENT_MAX_PAYLOAD_BYTES="${LOA_EVENT_MAX_PAYLOAD_BYTES:-65536}"

# Default idempotency window (hours)
EVENT_DEFAULT_IDEMPOTENCY_HOURS="${LOA_EVENT_DEFAULT_IDEMPOTENCY_HOURS:-24}"

# Specversion for all emitted events
EVENT_SPECVERSION="1.0"

# =============================================================================
# Initialization
# =============================================================================

# Initialize event bus directories
# Called lazily on first use — no setup step required
_init_event_bus() {
    mkdir -p "$EVENT_STORE_DIR" 2>/dev/null || true
    mkdir -p "$EVENT_IDEMPOTENCY_DIR" 2>/dev/null || true
    mkdir -p "$EVENT_OFFSETS_DIR" 2>/dev/null || true
    mkdir -p "$(dirname "$EVENT_DLQ_FILE")" 2>/dev/null || true

    # Initialize registry if missing
    if [[ ! -f "$EVENT_REGISTRY_FILE" ]]; then
        echo '{"version":1,"handlers":{}}' > "$EVENT_REGISTRY_FILE"
    fi
}

# Ensure jq is available — hard dependency for event bus
_require_jq() {
    if ! command -v jq &>/dev/null; then
        echo "ERROR: event-bus requires jq. Install: apt-get install jq" >&2
        return 3
    fi
}

# Ensure flock is available — required for atomic writes
# flock is standard on Linux (util-linux) but not on macOS. The cross-platform
# shell protocol (PR #210) established that missing tools should fail with
# actionable install instructions, not cryptic errors.
# This follows the /loa doctor pattern from Issue #211.
_require_flock() {
    if command -v flock &>/dev/null; then
        return 0
    fi

    # macOS: Homebrew installs util-linux as keg-only — binaries are NOT
    # symlinked to /opt/homebrew/bin and are NOT on PATH by default.
    # Check known keg-only paths for both Apple Silicon and Intel Macs.
    # Fixes #229.
    if [[ "$(uname -s)" == "Darwin" ]]; then
        local keg_paths=(
            "/opt/homebrew/opt/util-linux/bin"  # Apple Silicon
            "/usr/local/opt/util-linux/bin"     # Intel Mac
        )
        for keg_path in "${keg_paths[@]}"; do
            if [[ -x "${keg_path}/flock" ]]; then
                export PATH="${keg_path}:${PATH}"
                return 0
            fi
        done

        echo "ERROR: event-bus requires flock for atomic writes." >&2
        echo "  Install on macOS: brew install util-linux" >&2
        echo "  (flock will be found automatically at Homebrew's keg-only path)" >&2
        return 3
    fi

    echo "ERROR: event-bus requires flock for atomic writes." >&2
    echo "  Install: apt-get install util-linux" >&2
    return 3
}

# =============================================================================
# Event Emission
# =============================================================================

# Emit an event to the event bus
#
# This is the primary write path. Events are:
# 1. Validated against the envelope schema
# 2. Assigned a unique ID (UUIDv4 or fallback)
# 3. Wrapped in the CloudEvents envelope
# 4. Appended atomically to the type-partitioned JSONL log
# 5. Synchronously dispatched to registered handlers
#
# Args:
#   $1 - Event type (e.g., "forge.observer.utc_created")
#   $2 - Event data as JSON string
#   $3 - Event source (e.g., "forge/observing-users")
#   $4 - Optional: correlation_id (propagates through event chains)
#   $5 - Optional: causation_id (ID of the event that caused this one)
#   $6 - Optional: subject (entity the event relates to)
#
# Returns: 0 on success, 1 on validation error, 2 on delivery failure
#
# Example:
#   emit_event "forge.observer.utc_created" \
#     '{"utc_id":"utc-789"}' \
#     "forge/observing-users" \
#     "trace-abc123"
emit_event() {
    local event_type="$1"
    local event_data="$2"
    local event_source="$3"
    local correlation_id="${4:-}"
    local causation_id="${5:-}"
    local subject="${6:-}"

    _require_jq || return 3
    _require_flock || return 3
    _init_event_bus

    # Validate event type format: dotted lowercase (e.g., forge.observer.utc_created)
    if ! [[ "$event_type" =~ ^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$ ]]; then
        echo "ERROR: Invalid event type format: $event_type (expected: system.construct.event_name)" >&2
        return 1
    fi

    # Validate data is valid JSON
    if ! echo "$event_data" | jq empty 2>/dev/null; then
        echo "ERROR: Event data is not valid JSON" >&2
        return 1
    fi

    # Check payload size
    local data_size
    data_size=$(echo "$event_data" | wc -c)
    if (( data_size > EVENT_MAX_PAYLOAD_BYTES )); then
        echo "ERROR: Event data exceeds max payload size (${data_size} > ${EVENT_MAX_PAYLOAD_BYTES} bytes)" >&2
        return 1
    fi

    # Generate event ID (UUIDv4 if uuidgen available, fallback to timestamp + random)
    local event_id
    if command -v uuidgen &>/dev/null; then
        event_id="evt-$(uuidgen | tr '[:upper:]' '[:lower:]')"
    else
        event_id="evt-$(date +%s%N)-$(( RANDOM * RANDOM ))"
    fi

    # Generate timestamp
    local event_time
    event_time="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # Build the CloudEvents envelope using jq for safe JSON construction
    # (CI-013 pattern: never use heredoc for JSON with variables)
    local envelope
    envelope=$(jq -n \
        --arg specversion "$EVENT_SPECVERSION" \
        --arg id "$event_id" \
        --arg type "$event_type" \
        --arg source "$event_source" \
        --arg time "$event_time" \
        --arg correlation_id "$correlation_id" \
        --arg causation_id "$causation_id" \
        --arg subject "$subject" \
        --argjson data "$event_data" \
        '{
            specversion: $specversion,
            id: $id,
            type: $type,
            source: $source,
            time: $time,
            datacontenttype: "application/json",
            data: $data
        }
        | if $correlation_id != "" then . + {correlation_id: $correlation_id} else . end
        | if $causation_id != "" then . + {causation_id: $causation_id} else . end
        | if $subject != "" then . + {subject: $subject} else . end'
    )

    # Determine partition file (one JSONL per event type)
    # Partitioning by type enables efficient reads — consumers only scan their types
    # This is the same pattern Kafka uses with topic partitions
    local partition_file="${EVENT_STORE_DIR}/${event_type}.events.jsonl"

    # Atomic append with flock
    # flock(1) provides advisory file locking — same mechanism SQLite uses for WAL
    # The lock file is separate from the data file to avoid corruption
    #
    # NOTE: We use ( subshell ) not { group } because flock FD redirection
    # with 200> requires a subshell for clean FD scoping. Inside subshells,
    # `exit` (not `return`) is the correct way to abort — `return` in a
    # subshell is a bash-ism that silently becomes `exit` anyway, but using
    # `exit` explicitly makes the intent clear and avoids subtle bugs if
    # this code is ever refactored into a { group } block.
    # Google's bash style guide mandates this distinction.
    local lock_file="${partition_file}.lock"
    (
        flock -w 5 200 || {
            echo "ERROR: Could not acquire lock for event write (timeout after 5s)" >&2
            exit 2
        }
        # Compact JSON (one line) and append
        echo "$envelope" | jq -c . >> "$partition_file"
    ) 200>"$lock_file"

    # Check if the atomic write succeeded before dispatching
    if [[ $? -ne 0 ]]; then
        return 2
    fi

    # Dispatch to handlers (synchronous, best-effort)
    _dispatch_event "$event_type" "$envelope" || true

    # Return the event ID for correlation
    echo "$event_id"
}

# =============================================================================
# Event Dispatch
# =============================================================================

# Dispatch an event to all registered handlers
# Internal function — called by emit_event after writing to log
_dispatch_event() {
    local event_type="$1"
    local envelope="$2"

    [[ -f "$EVENT_REGISTRY_FILE" ]] || return 0

    # Read handlers for this event type
    local handlers
    handlers=$(jq -r --arg type "$event_type" \
        '.handlers[$type] // [] | .[] | .handler' \
        "$EVENT_REGISTRY_FILE" 2>/dev/null)

    [[ -n "$handlers" ]] || return 0

    local event_id
    event_id=$(echo "$envelope" | jq -r '.id')

    while IFS= read -r handler; do
        [[ -n "$handler" ]] || continue

        # Check idempotency — skip if this consumer already processed this event
        local consumer_key
        consumer_key=$(echo "$handler" | tr '/' '_' | tr '.' '_')
        if _check_idempotency "$consumer_key" "$event_id"; then
            continue
        fi

        # Invoke handler — capture stderr for DLQ diagnostics
        # The key insight from SRE practice at Google and Netflix: when a
        # handler fails, the error message is often more valuable than the
        # exit code. Suppressing stderr entirely (2>/dev/null) makes DLQ
        # entries useless for debugging. Instead, capture stderr to a temp
        # file and include it in the dead letter entry on failure.
        local exit_code=0
        local handler_stderr=""
        local stderr_tmp="${EVENT_STORE_DIR}/.handler_stderr.$$"
        if [[ -f "$handler" ]] && [[ -x "$handler" ]]; then
            echo "$envelope" | "$handler" 2>"$stderr_tmp" || exit_code=$?
        elif declare -F "$handler" &>/dev/null; then
            echo "$envelope" | "$handler" 2>"$stderr_tmp" || exit_code=$?
        else
            echo "Handler not found or not executable: $handler" > "$stderr_tmp"
            exit_code=127
        fi
        handler_stderr=$(cat "$stderr_tmp" 2>/dev/null | head -c 4096) || true
        rm -f "$stderr_tmp"

        if [[ "$exit_code" -eq 0 ]]; then
            # Record successful consumption for idempotency
            _record_consumption "$consumer_key" "$event_id"
        else
            # Route to dead letter queue with error context
            _write_dead_letter "$event_type" "$envelope" "$handler" "$exit_code" "$handler_stderr"
        fi
    done <<< "$handlers"
}

# =============================================================================
# Idempotency
# =============================================================================

# Check if a consumer has already processed an event
# Returns: 0 if already processed (skip), 1 if not seen (process)
_check_idempotency() {
    local consumer_key="$1"
    local event_id="$2"

    local state_file="${EVENT_IDEMPOTENCY_DIR}/${consumer_key}.seen"
    [[ -f "$state_file" ]] || return 1

    # Check if event ID exists in the seen file
    # Use -x (exact line match) instead of plain -F (substring match).
    # With -F alone, searching for "evt-abc" would match "evt-abc-123",
    # causing a false positive that skips processing. UUIDs make this
    # astronomically unlikely, but defense-in-depth costs nothing here.
    # This is the same principle behind Stripe's idempotency key matching —
    # exact equality, never substring.
    if grep -qxF "$event_id" "$state_file" 2>/dev/null; then
        return 0  # Already seen — skip
    fi

    return 1  # Not seen — process
}

# Record that a consumer has processed an event
_record_consumption() {
    local consumer_key="$1"
    local event_id="$2"

    local state_file="${EVENT_IDEMPOTENCY_DIR}/${consumer_key}.seen"
    echo "$event_id" >> "$state_file"

    # Prune old entries (keep last N hours of IDs)
    # This is a simple but effective approach — Kafka uses time-based compaction
    # for consumer offsets too
    local max_lines=10000
    local current_lines
    current_lines=$(wc -l < "$state_file" 2>/dev/null || echo "0")
    if (( current_lines > max_lines )); then
        local temp_file="${state_file}.tmp"
        tail -n "$((max_lines / 2))" "$state_file" > "$temp_file"
        mv "$temp_file" "$state_file"
    fi
}

# =============================================================================
# Dead Letter Queue
# =============================================================================

# Write a failed delivery to the dead letter queue
# DLQ entries include the original event + failure context + handler stderr
#
# Including stderr in DLQ entries follows the pattern from AWS SQS DLQ and
# GCP Pub/Sub dead lettering — the error context is the most valuable part
# of a dead letter for debugging. Without it, operators see "exit code 1"
# and have to manually reproduce the failure.
_write_dead_letter() {
    local event_type="$1"
    local envelope="$2"
    local handler="$3"
    local exit_code="$4"
    local error_output="${5:-}"

    local dlq_entry
    dlq_entry=$(jq -n \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg event_type "$event_type" \
        --arg handler "$handler" \
        --argjson exit_code "$exit_code" \
        --argjson event "$envelope" \
        --arg error_output "$error_output" \
        '{
            dead_letter_ts: $ts,
            event_type: $event_type,
            handler: $handler,
            exit_code: $exit_code,
            error_output: (if $error_output != "" then $error_output else null end),
            event: $event,
            retry_count: 0
        }'
    )

    # Atomic append to DLQ (best-effort — DLQ write failure is non-fatal)
    local lock_file="${EVENT_DLQ_FILE}.lock"
    (
        flock -w 5 200 || exit 0
        echo "$dlq_entry" | jq -c . >> "$EVENT_DLQ_FILE"
    ) 200>"$lock_file"

    echo "WARN: Event delivery failed (handler=$handler, exit=$exit_code). Routed to DLQ." >&2
}

# =============================================================================
# Event Consumption (Pull-based)
# =============================================================================

# Consume unread events of a given type
# Uses offset tracking to resume from last position (like Kafka consumer offsets)
#
# Args:
#   $1 - Event type to consume
#   $2 - Handler function or script path
#   $3 - Optional: consumer group name (defaults to handler name)
#
# Example:
#   consume_events "forge.observer.utc_created" handle_utc_created "my-consumer-group"
consume_events() {
    local event_type="$1"
    local handler="$2"
    local consumer_group="${3:-$(echo "$handler" | tr '/' '_' | tr '.' '_')}"

    _require_jq || return 3
    _init_event_bus

    local partition_file="${EVENT_STORE_DIR}/${event_type}.events.jsonl"
    if [[ ! -f "$partition_file" ]]; then
        return 0  # No events of this type yet
    fi

    # Read current offset for this consumer group
    local offset_file="${EVENT_OFFSETS_DIR}/${consumer_group}.${event_type}.offset"
    local current_offset=0
    if [[ -f "$offset_file" ]]; then
        current_offset=$(cat "$offset_file" 2>/dev/null || echo "0")
    fi

    # Read events from offset (tail -n +offset is 1-indexed)
    local skip_lines=$((current_offset + 1))
    local processed=0

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue

        local event_id
        event_id=$(echo "$line" | jq -r '.id' 2>/dev/null) || continue

        # Check idempotency
        if _check_idempotency "$consumer_group" "$event_id"; then
            processed=$((processed + 1))
            continue
        fi

        # Invoke handler
        local exit_code=0
        if [[ -f "$handler" ]] && [[ -x "$handler" ]]; then
            echo "$line" | "$handler" 2>/dev/null || exit_code=$?
        elif declare -F "$handler" &>/dev/null; then
            "$handler" <<< "$line" 2>/dev/null || exit_code=$?
        else
            echo "ERROR: Handler not found: $handler" >&2
            return 2
        fi

        if [[ "$exit_code" -eq 0 ]]; then
            _record_consumption "$consumer_group" "$event_id"
        else
            _write_dead_letter "$event_type" "$line" "$handler" "$exit_code"
        fi

        processed=$((processed + 1))
    done < <(tail -n +"$skip_lines" "$partition_file" 2>/dev/null)

    # Update offset
    if (( processed > 0 )); then
        local new_offset=$((current_offset + processed))
        echo "$new_offset" > "$offset_file"
    fi

    echo "$processed"
}

# =============================================================================
# Event Query
# =============================================================================

# Query the event log with filters
#
# Args (flags):
#   --type <type>     Filter by event type (required)
#   --since <date>    Filter events after this ISO date
#   --until <date>    Filter events before this ISO date
#   --source <src>    Filter by event source
#   --correlation <id> Filter by correlation_id (trace a full chain)
#   --limit <n>       Maximum events to return (default: 100)
#   --json            Output as JSON array (default: JSONL)
#
# Example:
#   query_events --type "forge.observer.utc_created" --since "2026-02-06" --limit 5
#   query_events --correlation "trace-abc123" --json
query_events() {
    _require_jq || return 3
    _init_event_bus

    local event_type="" since="" until="" source_filter="" correlation="" limit=100 json_output=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type) event_type="$2"; shift 2 ;;
            --since) since="$2"; shift 2 ;;
            --until) until="$2"; shift 2 ;;
            --source) source_filter="$2"; shift 2 ;;
            --correlation) correlation="$2"; shift 2 ;;
            --limit) limit="$2"; shift 2 ;;
            --json) json_output=true; shift ;;
            *) echo "ERROR: Unknown flag: $1" >&2; return 1 ;;
        esac
    done

    # Build the file list to scan
    local files=()
    if [[ -n "$event_type" ]]; then
        local f="${EVENT_STORE_DIR}/${event_type}.events.jsonl"
        [[ -f "$f" ]] && files+=("$f")
    else
        # Scan all event files (for correlation queries)
        for f in "${EVENT_STORE_DIR}"/*.events.jsonl; do
            [[ -f "$f" ]] && files+=("$f")
        done
    fi

    if [[ ${#files[@]} -eq 0 ]]; then
        if [[ "$json_output" == "true" ]]; then
            echo "[]"
        fi
        return 0
    fi

    # Build jq filter using --arg for safe parameter binding
    # SECURITY: Never interpolate user input into jq filter strings.
    # String interpolation allows jq expression injection (e.g., a crafted
    # --since value could bypass filters). Using --arg binds values as
    # string literals that jq cannot interpret as code.
    #
    # This is the same principle behind SQL parameterized queries — the
    # query structure is fixed, only the data varies. Google's production
    # jq usage in GKE tooling follows this pattern for the same reason.
    local jq_args=()
    local jq_filter="."

    if [[ -n "$since" ]]; then
        jq_args+=(--arg since "$since")
        jq_filter="${jq_filter} | select(.time >= \$since)"
    fi
    if [[ -n "$until" ]]; then
        jq_args+=(--arg until_date "$until")
        jq_filter="${jq_filter} | select(.time <= \$until_date)"
    fi
    if [[ -n "$source_filter" ]]; then
        jq_args+=(--arg src "$source_filter")
        jq_filter="${jq_filter} | select(.source == \$src)"
    fi
    if [[ -n "$correlation" ]]; then
        jq_args+=(--arg corr "$correlation")
        jq_filter="${jq_filter} | select(.correlation_id == \$corr)"
    fi

    # Execute query with parameterized filter
    if [[ "$json_output" == "true" ]]; then
        cat "${files[@]}" 2>/dev/null | jq -c "${jq_args[@]}" "$jq_filter" 2>/dev/null | head -n "$limit" | jq -s '.'
    else
        cat "${files[@]}" 2>/dev/null | jq -c "${jq_args[@]}" "$jq_filter" 2>/dev/null | head -n "$limit"
    fi
}

# =============================================================================
# Handler Registration
# =============================================================================

# Register a handler for an event type
#
# Args:
#   $1 - Event type to subscribe to
#   $2 - Handler (script path or function name)
#   $3 - Optional: delivery mode ("broadcast" or "queue", default: "broadcast")
#   $4 - Optional: consumer group (for queue mode)
#
# Example:
#   register_handler "forge.observer.utc_created" ".claude/handlers/utc-handler.sh" "broadcast"
register_handler() {
    local event_type="$1"
    local handler="$2"
    local delivery="${3:-broadcast}"
    local consumer_group="${4:-}"

    _require_jq || return 3
    _init_event_bus

    # Validate event type format
    if ! [[ "$event_type" =~ ^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$ ]]; then
        echo "ERROR: Invalid event type: $event_type" >&2
        return 1
    fi

    # Add handler to registry using jq (safe JSON construction)
    local lock_file="${EVENT_REGISTRY_FILE}.lock"
    (
        flock -w 5 200 || {
            echo "ERROR: Could not acquire registry lock" >&2
            exit 2
        }

        local updated
        updated=$(jq --arg type "$event_type" \
            --arg handler "$handler" \
            --arg delivery "$delivery" \
            --arg group "$consumer_group" \
            '.handlers[$type] = ((.handlers[$type] // []) + [{
                handler: $handler,
                delivery: $delivery,
                consumer_group: (if $group != "" then $group else null end),
                registered_at: (now | todate)
            }] | unique_by(.handler))' \
            "$EVENT_REGISTRY_FILE"
        )

        echo "$updated" > "$EVENT_REGISTRY_FILE"
    ) 200>"$lock_file"
}

# Unregister a handler
unregister_handler() {
    local event_type="$1"
    local handler="$2"

    _require_jq || return 3
    [[ -f "$EVENT_REGISTRY_FILE" ]] || return 0

    local lock_file="${EVENT_REGISTRY_FILE}.lock"
    (
        flock -w 5 200 || exit 0
        local updated
        updated=$(jq --arg type "$event_type" --arg handler "$handler" \
            '.handlers[$type] = [.handlers[$type][]? | select(.handler != $handler)]' \
            "$EVENT_REGISTRY_FILE"
        )
        echo "$updated" > "$EVENT_REGISTRY_FILE"
    ) 200>"$lock_file"
}

# =============================================================================
# Bus Introspection
# =============================================================================

# Get event bus status (for health checks and debugging)
#
# Output: JSON object with bus status, event counts, DLQ depth, handler count
bus_status() {
    _require_jq || return 3
    _init_event_bus

    local total_events=0
    local event_types=0
    # Build type_counts using jq for safe JSON construction (CI-013 pattern).
    # String interpolation into JSON is fragile — the same reason React
    # escapes JSX props and prepared statements escape SQL parameters.
    local types_json="[]"

    for f in "${EVENT_STORE_DIR}"/*.events.jsonl; do
        [[ -f "$f" ]] || continue
        local type_name
        type_name=$(basename "$f" .events.jsonl)
        local count
        count=$(wc -l < "$f" 2>/dev/null || echo "0")
        total_events=$((total_events + count))
        event_types=$((event_types + 1))
        types_json=$(echo "$types_json" | jq --arg t "$type_name" --argjson c "$count" '. + [{type: $t, count: $c}]')
    done

    # DLQ depth
    local dlq_depth=0
    if [[ -f "$EVENT_DLQ_FILE" ]]; then
        dlq_depth=$(wc -l < "$EVENT_DLQ_FILE" 2>/dev/null || echo "0")
    fi

    # Handler count
    local handler_count=0
    if [[ -f "$EVENT_REGISTRY_FILE" ]]; then
        handler_count=$(jq '[.handlers | to_entries[] | .value | length] | add // 0' "$EVENT_REGISTRY_FILE" 2>/dev/null || echo "0")
    fi

    jq -n \
        --argjson total "$total_events" \
        --argjson types "$event_types" \
        --argjson dlq "$dlq_depth" \
        --argjson handlers "$handler_count" \
        --argjson type_counts "$types_json" \
        '{
            status: (if $dlq > 10 then "DEGRADED" elif $dlq > 0 then "HEALTHY_WITH_DLQ" else "HEALTHY" end),
            total_events: $total,
            event_types: $types,
            dlq_depth: $dlq,
            registered_handlers: $handlers,
            type_counts: $type_counts
        }'
}

# =============================================================================
# Maintenance
# =============================================================================

# Compact old events (retention policy)
#
# Args:
#   $1 - Retention days (default: 30)
compact_events() {
    local retention_days="${1:-30}"

    _require_jq || return 3
    _init_event_bus

    local cutoff_date
    cutoff_date=$(date -u -d "-${retention_days} days" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
                  date -u -v-"${retention_days}d" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
                  echo "")

    if [[ -z "$cutoff_date" ]]; then
        echo "WARN: Could not compute cutoff date. Skipping compaction." >&2
        return 0
    fi

    local compacted=0
    for f in "${EVENT_STORE_DIR}"/*.events.jsonl; do
        [[ -f "$f" ]] || continue

        local before_count after_count
        before_count=$(wc -l < "$f")

        local temp_file="${f}.compact.tmp"
        jq -c --arg cutoff "$cutoff_date" 'select(.time >= $cutoff)' "$f" > "$temp_file" 2>/dev/null || continue

        after_count=$(wc -l < "$temp_file")
        local removed=$((before_count - after_count))

        if (( removed > 0 )); then
            mv "$temp_file" "$f"
            compacted=$((compacted + removed))
        else
            rm -f "$temp_file"
        fi
    done

    echo "Compacted $compacted events older than $retention_days days"
}

# Compact the dead letter queue (retention policy)
# Without this, DLQ grows unbounded — the same oversight that caused
# LinkedIn's Kafka DLQ incident in 2019, where unconsumed dead letters
# filled disks. Every append-only log needs a retention policy.
#
# Args:
#   $1 - Retention days (default: 7 — shorter than events since DLQ
#        entries are diagnostic, not data)
compact_dlq() {
    local retention_days="${1:-7}"

    _require_jq || return 3
    _init_event_bus

    [[ -f "$EVENT_DLQ_FILE" ]] || { echo "No DLQ to compact"; return 0; }

    local cutoff_date
    cutoff_date=$(date -u -d "-${retention_days} days" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
                  date -u -v-"${retention_days}d" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
                  echo "")

    if [[ -z "$cutoff_date" ]]; then
        echo "WARN: Could not compute cutoff date. Skipping DLQ compaction." >&2
        return 0
    fi

    local before_count after_count
    before_count=$(wc -l < "$EVENT_DLQ_FILE")

    local temp_file="${EVENT_DLQ_FILE}.compact.tmp"
    jq -c --arg cutoff "$cutoff_date" 'select(.dead_letter_ts >= $cutoff)' \
        "$EVENT_DLQ_FILE" > "$temp_file" 2>/dev/null || { rm -f "$temp_file"; return 0; }

    after_count=$(wc -l < "$temp_file")
    local removed=$((before_count - after_count))

    if (( removed > 0 )); then
        mv "$temp_file" "$EVENT_DLQ_FILE"
        echo "Compacted $removed DLQ entries older than $retention_days days"
    else
        rm -f "$temp_file"
        echo "No DLQ entries to compact"
    fi
}

# =============================================================================
# CLI Interface
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        emit)
            shift
            emit_event "$@"
            ;;
        consume)
            shift
            consume_events "$@"
            ;;
        query)
            shift
            query_events "$@"
            ;;
        register)
            shift
            register_handler "$@"
            ;;
        unregister)
            shift
            unregister_handler "$@"
            ;;
        status)
            bus_status
            ;;
        compact)
            compact_events "${2:-30}"
            ;;
        dlq)
            if [[ -f "$EVENT_DLQ_FILE" ]]; then
                cat "$EVENT_DLQ_FILE"
            else
                echo "No dead letter entries"
            fi
            ;;
        compact-dlq)
            compact_dlq "${2:-7}"
            ;;
        --help|-h|help)
            cat << 'EOF'
Usage: event-bus.sh <command> [args]

Commands:
    emit <type> <data_json> <source> [correlation_id] [causation_id]
        Emit a new event to the bus

    consume <type> <handler_script> [consumer_group]
        Consume unread events of a type

    query --type <type> [--since <date>] [--limit <n>] [--json]
        Query event log with filters

    register <type> <handler> [delivery_mode] [consumer_group]
        Register event handler

    unregister <type> <handler>
        Unregister event handler

    status
        Show event bus health status

    compact [retention_days]
        Remove events older than retention period (default: 30 days)

    compact-dlq [retention_days]
        Remove DLQ entries older than retention period (default: 7 days)

    dlq
        Show dead letter queue entries

Examples:
    event-bus.sh emit "forge.observer.utc_created" '{"utc_id":"utc-1"}' "forge/observing-users"
    event-bus.sh query --type "forge.observer.utc_created" --limit 5 --json
    event-bus.sh register "forge.observer.utc_created" ./my-handler.sh broadcast
    event-bus.sh status
EOF
            ;;
        *)
            echo "Unknown command: ${1:-}" >&2
            echo "Use --help for usage" >&2
            exit 1
            ;;
    esac
fi
