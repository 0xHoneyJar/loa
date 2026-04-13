#!/usr/bin/env bash
# =============================================================================
# lore-promote.sh — promote vetted PRAISE candidates into patterns.yaml
# =============================================================================
# Reads .run/bridge-lore-candidates.jsonl + .run/lore-promote-journal.jsonl
# Produces vetted entries in grimoires/loa/lore/patterns.yaml
#
# Cycle: cycle-060 — closes #481, Gap 1 of HARVEST phase from RFC-060 vision
#
# Usage:
#   lore-promote.sh [OPTIONS]
#     --queue PATH          Input queue (default: .run/bridge-lore-candidates.jsonl)
#     --lore PATH           Output lore (default: grimoires/loa/lore/patterns.yaml)
#     --interactive         Prompt per candidate (default mode)
#     --threshold N         Auto-promote patterns from ≥N distinct merged PRs (N≥2)
#     --dry-run             Show what would be promoted without writing
#     --help                Show usage and exit
#
# Exit codes:
#   0  Success (including empty-queue case)
#   1  Runtime error (lock failure, jq/yq error, write failure)
#   2  Usage error (unknown flag, --threshold < 2, invalid path)
# =============================================================================

set -euo pipefail
shopt -s nullglob

# =============================================================================
# Defaults
# =============================================================================

QUEUE_PATH=".run/bridge-lore-candidates.jsonl"
LORE_PATH="grimoires/loa/lore/patterns.yaml"
JOURNAL_PATH=".run/lore-promote-journal.jsonl"
LOCK_PATH=".run/lore-promote.lock"
TRAJECTORY_DIR="grimoires/loa/a2a/trajectory"
mode="interactive"
threshold=0
dry_run=false
LOCK_TIMEOUT=10
GH_BIN="${GH_BIN:-gh}"

# Hardcoded baseline injection patterns (FR-5)
INJECTION_PATTERNS=(
    'Ignore previous instructions'
    'You are now '
    'From now on '
    '^(system|user|assistant):'
    '<script'
    '<iframe'
    'javascript:'
    'data:text/html'
)

# Length limits (FR-5)
MAX_TERM_LEN=80
MAX_SHORT_LEN=200
MAX_CONTEXT_LEN=1500

# =============================================================================
# Usage
# =============================================================================

usage() {
    sed -n '3,25p' "$0" | sed 's/^# \?//'
    exit "${1:-0}"
}

# =============================================================================
# CLI parsing
# =============================================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --queue)
            [[ -z "${2:-}" ]] && { echo "ERROR: --queue requires PATH" >&2; exit 2; }
            QUEUE_PATH="$2"; shift 2 ;;
        --lore)
            [[ -z "${2:-}" ]] && { echo "ERROR: --lore requires PATH" >&2; exit 2; }
            LORE_PATH="$2"; shift 2 ;;
        --journal)
            [[ -z "${2:-}" ]] && { echo "ERROR: --journal requires PATH" >&2; exit 2; }
            JOURNAL_PATH="$2"; shift 2 ;;
        --lock)
            [[ -z "${2:-}" ]] && { echo "ERROR: --lock requires PATH" >&2; exit 2; }
            LOCK_PATH="$2"; shift 2 ;;
        --trajectory-dir)
            [[ -z "${2:-}" ]] && { echo "ERROR: --trajectory-dir requires PATH" >&2; exit 2; }
            TRAJECTORY_DIR="$2"; shift 2 ;;
        --interactive)
            mode="interactive"; shift ;;
        --threshold)
            [[ -z "${2:-}" ]] && { echo "ERROR: --threshold requires N" >&2; exit 2; }
            [[ "$2" =~ ^[0-9]+$ ]] || { echo "ERROR: --threshold must be integer" >&2; exit 2; }
            [[ "$2" -lt 2 ]] && { echo "ERROR: --threshold floor is 2 (min distinct merged PRs)" >&2; exit 2; }
            mode="threshold"; threshold="$2"; shift 2 ;;
        --auto)
            # Cycle-061 (#484): auto mode for post-merge pipeline use.
            # Implies --threshold 2 (the safe default floor) when no
            # explicit --threshold provided. No prompts, ever.
            mode="threshold"
            [[ "$threshold" -lt 2 ]] && threshold=2
            shift ;;
        --dry-run)
            dry_run=true; shift ;;
        --help|-h)
            usage 0 ;;
        *)
            echo "ERROR: Unknown flag: $1" >&2; usage 2 ;;
    esac
done

# =============================================================================
# Logging helpers
# =============================================================================

log() { echo "[lore-promote] $*" >&2; }
warn() { echo "[lore-promote] WARNING: $*" >&2; }
err() { echo "[lore-promote] ERROR: $*" >&2; }

trajectory_log() {
    local action="$1" candidate_key="$2" id="${3:-null}" reason="${4:-}"
    mkdir -p "$TRAJECTORY_DIR"
    local trajectory_file="$TRAJECTORY_DIR/lore-promote-$(date -u +%Y-%m-%d).jsonl"
    local entry
    entry=$(jq -nc \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg action "$action" \
        --arg candidate_key "$candidate_key" \
        --arg id "$id" \
        --arg reason "$reason" \
        '{timestamp:$ts, action:$action, candidate_key:$candidate_key, id:(if $id == "null" then null else $id end), reason:(if $reason == "" then null else $reason end)}')
    echo "$entry" >> "$trajectory_file"
}

journal_append() {
    local candidate_key="$1" action="$2" id="${3:-}" reason="${4:-}" pr="${5:-0}"
    local entry
    entry=$(jq -nc \
        --arg decided_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg candidate_key "$candidate_key" \
        --arg action "$action" \
        --arg id "$id" \
        --arg reason "$reason" \
        --argjson pr "$pr" \
        '{decided_at:$decided_at, candidate_key:$candidate_key, action:$action, id:(if $id == "" then null else $id end), reason:(if $reason == "" then null else $reason end), pr:$pr, tool_version:"cycle-060"}')
    echo "$entry" >> "$JOURNAL_PATH"
}

# =============================================================================
# Sanitization (FR-5)
# =============================================================================

sanitize() {
    local text="$1" max_chars="$2"
    # Strip ANSI escapes
    text=$(printf '%s' "$text" | sed $'s/\x1b\\[[0-9;]*m//g')
    # Strip control chars except \t \n \r
    text=$(printf '%s' "$text" | tr -d '\000-\010\013\014\016-\037\177')
    # Length check
    if [[ ${#text} -gt $max_chars ]]; then
        echo "LENGTH_LIMIT" >&2
        return 1
    fi
    # Injection scan. Bridgebuilder F10 (LOW): use grep <<< heredoc instead of
    # echo|grep to handle values starting with `-` (echo would treat as flag).
    for pattern in "${INJECTION_PATTERNS[@]}"; do
        if grep -qiE -- "$pattern" <<< "$text"; then
            echo "INJECTION:$pattern" >&2
            return 1
        fi
    done
    printf '%s' "$text"
}

# =============================================================================
# ID generation with collision (FR-2.1)
# =============================================================================

slugify() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed -E 's/^-+|-+$//g'
}

generate_id() {
    local term="$1" content_hash="$2"
    local base
    base=$(slugify "$term")
    [[ -z "$base" ]] && base="unnamed"
    # Bridgebuilder F2/F7 (CRITICAL/HIGH): bind via env, not string interpolation.
    # Mike Farah yq (Loa default) doesn't support --arg; use strenv() instead.
    # Even though slugify limits the character set, defense-in-depth wins.
    if [[ -f "$LORE_PATH" ]] && LOOKUP_ID="$base" yq '.[] | select(.id == strenv(LOOKUP_ID))' "$LORE_PATH" 2>/dev/null | grep -q .; then
        local short=${content_hash:0:6}
        echo "${base}-${short}"
    else
        echo "$base"
    fi
}

# =============================================================================
# Queue + journal loading
# =============================================================================

load_decided_keys() {
    [[ -f "$JOURNAL_PATH" ]] || { echo ""; return; }
    jq -cR 'fromjson? // empty | .candidate_key' "$JOURNAL_PATH" 2>/dev/null | tr -d '"'
}

load_queue_entries() {
    [[ -f "$QUEUE_PATH" ]] || return
    # Stream-mode parse to handle both JSONL and pretty-printed (matches v1.79.0 analyzer pattern)
    jq -cn '[inputs][] | select(.action == "lore_candidate" or .severity == "PRAISE")' < "$QUEUE_PATH" 2>/dev/null
}

candidate_key_of() {
    local entry="$1"
    local pr finding_id
    pr=$(echo "$entry" | jq -r '.pr_number // 0')
    finding_id=$(echo "$entry" | jq -r '.finding_id // "unknown"')
    echo "${pr}:${finding_id}"
}

# =============================================================================
# Patterns.yaml management
# =============================================================================

ensure_lore_file() {
    if [[ ! -f "$LORE_PATH" ]]; then
        log "Creating $LORE_PATH (did not exist)"
        mkdir -p "$(dirname "$LORE_PATH")"
        cat > "$LORE_PATH" <<EOF
# Lore Patterns — auto-promoted via lore-promote.sh
# Schema: list of {id, term, short, context, source, tags}
[]
EOF
    fi
}

append_lore_entry() {
    local id="$1" term="$2" short="$3" context="$4" pr="$5" finding_id="$6" tags_json="$7"
    ensure_lore_file
    local promoted_at; promoted_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    # Build YAML entry safely. Bridgebuilder F2 (CRITICAL): the previous
    # implementation interpolated $term/$short/$context directly into the
    # yq expression, allowing yq-syntax injection if any field contained
    # quotes or expression characters (sanitize() blocks the worst patterns
    # but defense-in-depth is the right move).
    #
    # Strategy: build a JSON object with --argjson via jq (which escapes
    # all string content correctly), then yq merges it into the YAML file.
    local tmp; tmp=$(mktemp -p "${TMPDIR:-/tmp}" lore-promote.XXXXXX)
    cp "$LORE_PATH" "$tmp"

    local entry_json
    entry_json=$(jq -nc \
        --arg id "$id" \
        --arg term "$term" \
        --arg short "$short" \
        --arg context "$context" \
        --argjson pr "$pr" \
        --arg finding_id "$finding_id" \
        --arg promoted_at "$promoted_at" \
        --argjson tags "$tags_json" \
        '{
            id: $id,
            term: $term,
            short: $short,
            context: $context,
            source: {
                pr: $pr,
                finding_id: $finding_id,
                cycle: "cycle-060",
                promoted_at: $promoted_at
            },
            tags: $tags
        }')

    # Mike Farah yq: write JSON entry to a separate file, then merge via
    # eval-all. fileIndex selectors mean no attacker-influenceable content
    # ever flows into the yq expression itself — the values come from the
    # parsed JSON file. This is the injection-safe pattern.
    local entry_file; entry_file=$(mktemp -p "${TMPDIR:-/tmp}" lore-entry.XXXXXX.json)
    printf '%s' "$entry_json" > "$entry_file"
    yq ea -i 'select(fi==0) + [select(fi==1)]' "$tmp" "$entry_file"
    rm -f "$entry_file"
    # Reformat to block style for readability (best-effort)
    yq -i '... style=""' "$tmp" 2>/dev/null || true
    mv "$tmp" "$LORE_PATH"
}

# =============================================================================
# Per-candidate processing
# =============================================================================

extract_finding_field() {
    local entry="$1" field="$2"
    # Try multiple shapes: top-level, finding_content sub-object
    local val
    val=$(echo "$entry" | jq -r ".finding_content.${field} // .${field} // empty")
    echo "$val"
}

process_candidate() {
    local entry="$1" candidate_key="$2"
    local pr finding_id term short context tags_json content_hash
    pr=$(echo "$entry" | jq -r '.pr_number // 0')
    finding_id=$(echo "$entry" | jq -r '.finding_id // "unknown"')
    term=$(extract_finding_field "$entry" "title")
    short=$(extract_finding_field "$entry" "description")
    context=$(extract_finding_field "$entry" "reasoning")
    [[ -z "$context" ]] && context=$(echo "$entry" | jq -r '.reasoning // ""')
    tags_json=$(echo "$entry" | jq -c '(.finding_content.tags // .tags // [])')
    content_hash=$(echo "$entry" | sha256sum | cut -c1-64)

    # Sanitize each field. On rejection, log + journal + return.
    local sterm sshort scontext rejection_reason=""
    # Bridgebuilder F1 (HIGH): use mktemp for the rejection-reason capture
    # rather than predictable /tmp/lp-rej.$$ to avoid race + symlink attack.
    local rej_tmp; rej_tmp=$(mktemp -p "${TMPDIR:-/tmp}" lp-rej.XXXXXX)
    if ! sterm=$(sanitize "$term" $MAX_TERM_LEN 2>"$rej_tmp"); then
        rejection_reason="term: $(cat "$rej_tmp")"
    elif ! sshort=$(sanitize "$short" $MAX_SHORT_LEN 2>"$rej_tmp"); then
        rejection_reason="short: $(cat "$rej_tmp")"
    elif ! scontext=$(sanitize "$context" $MAX_CONTEXT_LEN 2>"$rej_tmp"); then
        rejection_reason="context: $(cat "$rej_tmp")"
    fi
    rm -f "$rej_tmp"

    if [[ -n "$rejection_reason" ]]; then
        warn "Rejected candidate $candidate_key — $rejection_reason"
        if [[ "$dry_run" == "false" ]]; then
            journal_append "$candidate_key" "rejected" "" "$rejection_reason" "$pr"
            trajectory_log "rejected" "$candidate_key" "null" "$rejection_reason"
        fi
        return
    fi

    local id; id=$(generate_id "$sterm" "$content_hash")

    # Idempotency check: if id already exists in patterns.yaml, skip + journal
    if [[ -f "$LORE_PATH" ]] && LOOKUP_ID="$id" yq '.[] | select(.id == strenv(LOOKUP_ID))' "$LORE_PATH" 2>/dev/null | grep -q .; then
        log "Skipping $candidate_key — id '$id' already in patterns.yaml (back-filling journal)"
        if [[ "$dry_run" == "false" ]]; then
            journal_append "$candidate_key" "promoted" "$id" "back-filled (already in lore)" "$pr"
        fi
        return
    fi

    local action="accept"
    if [[ "$mode" == "interactive" ]]; then
        echo "" >&2
        echo "═══════════════════════════════════════════" >&2
        echo "CANDIDATE: $sterm" >&2
        echo "Source: PR #$pr, $finding_id" >&2
        echo "Short: $sshort" >&2
        echo "Context: $(echo "$scontext" | head -c 200)..." >&2
        echo "Tags: $(echo "$tags_json" | jq -r '. | join(", ")')" >&2
        echo "" >&2
        printf '[A]ccept / [R]eject / [S]kip / [E]dit (deferred) / [Q]uit? ' >&2
        # The outer while loop binds its input to FD 3 (`done 3<<<`), leaving
        # stdin (FD 0) free for this interactive read. Works in both real
        # terminals and piped-test scenarios. (Bridgebuilder F9 — comment
        # rewritten for accuracy.)
        local choice; read -r choice
        # tr to lowercase for portability (avoids ${var,,} bash 4+ requirement)
        choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
        case "$choice" in
            a) action="accept" ;;
            r) action="reject" ;;
            s) action="skip"; log "Skipped $candidate_key — leaving for future run"; return ;;
            e) action="skip"; warn "Edit mode not yet implemented — skipping (deferred to future cycle)"; return ;;
            q) log "User quit — preserving decisions made so far"; exit 0 ;;
            *) action="skip"; warn "Unknown choice — treating as skip"; return ;;
        esac
    elif [[ "$mode" == "threshold" ]]; then
        # Count distinct merged PRs for this term
        local merged_pr_count
        # Read from temp file rather than env var (BB pass-2 F6 fix).
        merged_pr_count=$(jq -r --arg t "$sterm" '
            select(.finding_content.title == $t or .title == $t) | .pr_number
        ' "$ALL_PENDING_FILE" 2>/dev/null | sort -u | wc -l | tr -d ' ')
        if [[ "$merged_pr_count" -lt "$threshold" ]]; then
            log "Below threshold ($merged_pr_count < $threshold) for '$sterm' — skipping"
            return
        fi
        # Verify the source PR is merged
        local pr_state
        pr_state=$("$GH_BIN" pr view "$pr" --json state --jq '.state' 2>/dev/null || echo "UNKNOWN")
        if [[ "$pr_state" != "MERGED" ]]; then
            log "Source PR #$pr not merged (state=$pr_state) — skipping"
            return
        fi
        action="accept"
    fi

    if [[ "$action" == "accept" ]]; then
        if [[ "$dry_run" == "true" ]]; then
            log "DRY-RUN: would promote $candidate_key as id='$id'"
            return
        fi
        # Two-phase write per SDD §2.5
        append_lore_entry "$id" "$sterm" "$sshort" "$scontext" "$pr" "$finding_id" "$tags_json"
        journal_append "$candidate_key" "promoted" "$id" "" "$pr"
        trajectory_log "promoted" "$candidate_key" "$id" ""
        log "Promoted $candidate_key as id='$id'"
    elif [[ "$action" == "reject" ]]; then
        printf 'Rejection reason: ' >&2; local reason; read -r reason
        if [[ "$dry_run" == "false" ]]; then
            journal_append "$candidate_key" "rejected" "" "$reason" "$pr"
            trajectory_log "rejected" "$candidate_key" "null" "$reason"
        fi
        log "Rejected $candidate_key"
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    mkdir -p "$(dirname "$LOCK_PATH")"

    # Acquire lock
    exec 200>"$LOCK_PATH"
    if ! flock -w "$LOCK_TIMEOUT" 200; then
        err "Could not acquire lock on $LOCK_PATH (timeout=${LOCK_TIMEOUT}s) — another promoter run may be in progress"
        exit 1
    fi

    # Empty queue check
    if [[ ! -f "$QUEUE_PATH" ]]; then
        log "no candidates queued (queue file does not exist: $QUEUE_PATH)"
        exit 0
    fi

    # Load decided keys
    local decided_keys
    decided_keys=$(load_decided_keys)

    # Load all queue candidates
    local queue_entries
    queue_entries=$(load_queue_entries)

    if [[ -z "$queue_entries" ]]; then
        log "no candidates queued (queue is empty or has no PRAISE-action entries)"
        exit 0
    fi

    # Compute pending = queue - decided
    local all_pending=""
    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        local key; key=$(candidate_key_of "$entry")
        if ! echo "$decided_keys" | grep -qFx "$key"; then
            all_pending+="$entry"$'\n'
        fi
    done <<< "$queue_entries"

    if [[ -z "$all_pending" ]]; then
        log "no new candidates (all decided in journal)"
        exit 0
    fi

    # Bridgebuilder pass-2 F6 (HIGH, re-raised after pass-1 defer): write
    # pending set to a temp file rather than env var. Multi-line JSON via env
    # is brittle (unbounded length, quoting issues with special chars). File
    # path via env is safe and threshold-mode jq can read it cleanly.
    ALL_PENDING_FILE=$(mktemp -p "${TMPDIR:-/tmp}" lore-pending.XXXXXX)
    printf '%s' "$all_pending" > "$ALL_PENDING_FILE"
    export ALL_PENDING_FILE
    trap 'rm -f "$ALL_PENDING_FILE"' EXIT

    local pending_count
    pending_count=$(echo "$all_pending" | grep -c . || true)
    local dr_marker=""
    [[ "$dry_run" == "true" ]] && dr_marker=" (dry-run)"
    log "Processing $pending_count pending candidate(s) in $mode mode${dr_marker}"

    # Process each pending candidate. FD 3 binds the iteration input,
    # leaving stdin free for interactive prompts inside process_candidate.
    while IFS= read -r entry <&3; do
        [[ -z "$entry" ]] && continue
        local key; key=$(candidate_key_of "$entry")
        process_candidate "$entry" "$key"
    done 3<<< "$all_pending"

    log "Run complete."
}

main "$@"
