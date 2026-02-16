#!/usr/bin/env bash
# settings-cleanup.sh — Clean settings.local.json after each session (SDD §2.3)
# Trigger: Stop event (async, fail-open)
# Closes: #339

# Fail-open: never delay exit
trap 'exit 0' ERR

set -o pipefail

SETTINGS_FILE=".claude/settings.local.json"
AUDIT_LOG=".run/audit.jsonl"
SIZE_THRESHOLD=65536  # 64KB — skip cleanup for small files

# Credential patterns (SDD §2.3, Flatline IMP-004)
CREDENTIAL_PATTERNS=(
    'AKIA[A-Z0-9]{16}'
    'ghp_[a-zA-Z0-9]{36}'
    'gho_[a-zA-Z0-9]{36}'
    'ghs_[a-zA-Z0-9]{36}'
    'ghr_[a-zA-Z0-9]{36}'
    'eyJ[a-zA-Z0-9_-]*\.'
    '://[^:]+:[^@]+@'
    'Bearer [a-zA-Z0-9_.-]+'
    'sk-[a-zA-Z0-9]{20,}'
    'xoxb-[a-zA-Z0-9-]+'
    'xoxp-[a-zA-Z0-9-]+'
    '-----BEGIN .* PRIVATE KEY'
)

log() {
    echo "[settings-cleanup] $*" >&2
}

audit_log() {
    local event="$1" detail="$2"
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    mkdir -p "$(dirname "$AUDIT_LOG")"
    printf '{"timestamp":"%s","event":"%s","detail":%s}\n' \
        "$ts" "$event" "$detail" >> "$AUDIT_LOG"
}

# --- Main ---

# Check file exists
if [[ ! -f "$SETTINGS_FILE" ]]; then
    exit 0
fi

# Size check — exit early if below threshold
file_size=$(stat -c%s "$SETTINGS_FILE" 2>/dev/null || stat -f%z "$SETTINGS_FILE" 2>/dev/null || echo "0")
if [[ "$file_size" -lt "$SIZE_THRESHOLD" ]]; then
    exit 0
fi

# Validate jq is available
if ! command -v jq >/dev/null 2>&1; then
    log "WARNING: jq not found, skipping cleanup"
    exit 0
fi

# Parse .permissions.allow array
allow_array=$(jq -r '.permissions.allow // []' "$SETTINGS_FILE" 2>/dev/null)
if [[ -z "$allow_array" || "$allow_array" == "null" || "$allow_array" == "[]" ]]; then
    exit 0
fi

original_count=$(echo "$allow_array" | jq 'length')

# Build credential patterns as JSON array (BB-F7: avoid fragile regex concatenation)
# Each pattern is tested individually via jq's any(), avoiding PCRE dialect issues
# that arise when concatenating patterns with '|' into a single string.
pattern_json=$(printf '%s\n' "${CREDENTIAL_PATTERNS[@]}" | jq -R -s 'split("\n") | map(select(length > 0))')

# Filter entries: remove long, multiline, and credential-matching entries, then deduplicate
filtered=$(echo "$allow_array" | jq --argjson patterns "$pattern_json" '
    map(select(
        (length <= 200) and
        (test("\n") | not) and
        (. as $entry | [$patterns[] | . as $pat | ($entry | test($pat))] | any | not)
    )) | unique
')

filtered_count=$(echo "$filtered" | jq 'length')
removed_count=$((original_count - filtered_count))

if [[ "$removed_count" -eq 0 ]]; then
    exit 0
fi

# Write filtered array back via temp file + atomic rename
tmp_file="${SETTINGS_FILE}.cleanup-tmp"
jq --argjson filtered "$filtered" '.permissions.allow = $filtered' "$SETTINGS_FILE" > "$tmp_file"
mv "$tmp_file" "$SETTINGS_FILE"

log "Cleaned $removed_count entries from permissions.allow ($original_count → $filtered_count)"

# Post-cleanup scan: check for remaining suspected secrets (BB-201: derive from CREDENTIAL_PATTERNS)
# Uses the same source array as the main filter — single source of truth.
remaining_suspects=0
for pat in "${CREDENTIAL_PATTERNS[@]}"; do
    if grep -qP "$pat" "$SETTINGS_FILE" 2>/dev/null || grep -qE "$pat" "$SETTINGS_FILE" 2>/dev/null; then
        log "WARNING: Suspected secret pattern '$pat' still present after cleanup"
        remaining_suspects=$((remaining_suspects + 1))
    fi
done

# Log summary to audit file
audit_log "settings_cleanup" "$(printf '{"original":%d,"filtered":%d,"removed":%d,"remaining_suspects":%d,"file_size":%d}' \
    "$original_count" "$filtered_count" "$removed_count" "$remaining_suspects" "$file_size")"

exit 0
