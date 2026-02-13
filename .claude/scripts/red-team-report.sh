#!/usr/bin/env bash
# =============================================================================
# red-team-report.sh — Generate markdown reports from red team JSON results
# =============================================================================
# Produces two outputs:
#   - Full report (0600): all attacks, counter-designs, attack tree
#   - Summary (safe): counts + CDR recommendations only (for PR bodies/CI)
#
# Exit codes:
#   0 - Success
#   1 - Missing input
#   2 - Invalid JSON
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Redaction patterns (reused from bridge-github-trail.sh)
REDACT_PATTERNS=(
    'aws_access_key|AKIA[0-9A-Z]{16}'
    'github_pat|ghp_[A-Za-z0-9]{36}'
    'github_oauth|gho_[A-Za-z0-9]{36}'
    'github_app|ghs_[A-Za-z0-9]{36}'
    'github_refresh|ghr_[A-Za-z0-9]{36}'
    'jwt_token|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}'
    'generic_secret|(api_key|api_secret|apikey|secret_key|access_token|auth_token|private_key)[[:space:]]*[=:][[:space:]]*["'"'"'][A-Za-z0-9+/=_-]{16,}'
)

# Allowlist
ALLOWLIST_PATTERNS=(
    'sha256:[a-f0-9]{64}'
    'EXAMPLE_KEY_[a-zA-Z0-9_]+'
)

# =============================================================================
# Logging
# =============================================================================

log() {
    echo "[red-team-report] $*" >&2
}

error() {
    echo "[red-team-report] ERROR: $*" >&2
}

# =============================================================================
# Redaction
# =============================================================================

redact_content() {
    local content
    content=$(cat; echo x)
    content="${content%x}"

    # Protect allowlisted content
    local sentinel_idx=0
    declare -A sentinel_map
    for pattern in "${ALLOWLIST_PATTERNS[@]}"; do
        while IFS= read -r match; do
            if [[ -n "$match" ]]; then
                local sentinel="__ALLOWLIST_${sentinel_idx}__"
                sentinel_map["$sentinel"]="$match"
                content="${content//$match/$sentinel}"
                sentinel_idx=$((sentinel_idx + 1))
            fi
        done < <(printf '%s' "$content" | grep -oE "$pattern" 2>/dev/null || true)
    done

    # Apply redaction
    local sed_expr=""
    for entry in "${REDACT_PATTERNS[@]}"; do
        local name="${entry%%|*}"
        local regex="${entry#*|}"
        sed_expr="${sed_expr}s/${regex}/[REDACTED:${name}]/g;"
    done

    if [[ -n "$sed_expr" ]]; then
        content=$(printf '%s' "$content" | sed -E "$sed_expr" 2>/dev/null || printf '%s' "$content")
    fi

    # Restore allowlisted content
    for sentinel in "${!sentinel_map[@]}"; do
        content="${content//$sentinel/${sentinel_map[$sentinel]}}"
    done

    printf '%s' "$content"
}

# Post-redaction safety check
post_redaction_check() {
    local content="$1"
    local leaked=false

    for prefix in "ghp_" "gho_" "ghs_" "ghr_" "AKIA" "eyJ"; do
        if printf '%s' "$content" | grep -qF "$prefix" 2>/dev/null; then
            error "Post-redaction leak detected: $prefix"
            leaked=true
        fi
    done

    if [[ "$leaked" == "true" ]]; then
        return 1
    fi
    return 0
}

# =============================================================================
# Report generation
# =============================================================================

generate_full_report() {
    local input="$1"
    local run_id="$2"

    local execution_mode validated phase
    execution_mode=$(jq -r '.execution_mode // "standard"' "$input")
    validated=$(jq -r '.validated // true' "$input")
    phase=$(jq -r '.phase // "unknown"' "$input")

    local header=""
    if [[ "$execution_mode" == "quick" || "$validated" == "false" ]]; then
        header="
> **WARNING: UNVALIDATED RESULTS**
> Quick mode results are exploratory only. No cross-validation was performed.
> Use standard or deep mode for gating decisions.

"
    fi

    cat <<REPORT
# Red Team Report — ${phase^^}

**Run ID**: ${run_id}
**Execution Mode**: ${execution_mode}
**Classification**: $(jq -r '.classification // "INTERNAL"' "$input")
**Generated**: $(date -u +%Y-%m-%dT%H:%M:%SZ)
${header}
## Attack Summary

| Category | Count |
|----------|-------|
| CONFIRMED_ATTACK | $(jq '.attack_summary.confirmed_count // 0' "$input") |
| THEORETICAL | $(jq '.attack_summary.theoretical_count // 0' "$input") |
| CREATIVE_ONLY | $(jq '.attack_summary.creative_count // 0' "$input") |
| DEFENDED | $(jq '.attack_summary.defended_count // 0' "$input") |
| **Total** | $(jq '.attack_summary.total_attacks // 0' "$input") |
| Human Review Required | $(jq '.attack_summary.human_review_required // 0' "$input") |

## Confirmed Attacks

$(result=$(jq -r '
(.attacks.confirmed // [])[] |
"### \(.id): \(.name)\n\n" +
"- **Profile**: \(.attacker_profile // "unknown")\n" +
"- **Vector**: \(.vector // "unknown")\n" +
"- **Severity**: \(.severity_score // 0)/1000\n" +
"- **Likelihood**: \(.likelihood // "unknown")\n" +
"- **Target Surface**: \(.target_surface // "unknown")\n" +
"- **Trust Boundary**: \(.trust_boundary // "unknown")\n" +
"- **Asset at Risk**: \(.asset_at_risk // "unknown")\n" +
"- **Assumption Challenged**: \(.assumption_challenged // "none")\n" +
"- **GPT Score**: \(.gpt_score // 0) | **Opus Score**: \(.opus_score // 0)\n\n" +
"**Scenario**:\n" +
([.scenario[]? | . ] | to_entries | map("\(.key + 1). \(.value)") | join("\n")) +
"\n\n**Impact**: \(.impact // "unknown")\n\n" +
"**Reproducibility**: \(.reproducibility // "unknown")\n\n---\n"
' "$input" 2>/dev/null); [[ -n "$result" ]] && echo "$result" || echo "_No confirmed attacks._")

## Theoretical Attacks

$(result=$(jq -r '
(.attacks.theoretical // [])[] |
"### \(.id): \(.name)\n" +
"- **Severity**: \(.severity_score // 0)/1000 | **Consensus**: THEORETICAL\n" +
"- **Vector**: \(.vector // "unknown")\n\n"
' "$input" 2>/dev/null); [[ -n "$result" ]] && echo "$result" || echo "_No theoretical attacks._")

## Creative/Novel Attacks

$(result=$(jq -r '
(.attacks.creative // [])[] |
"### \(.id): \(.name)\n" +
"- **Severity**: \(.severity_score // 0)/1000 | **Consensus**: CREATIVE_ONLY\n" +
"- **Vector**: \(.vector // "unknown")\n\n"
' "$input" 2>/dev/null); [[ -n "$result" ]] && echo "$result" || echo "_No creative attacks._")

## Defended Attacks

$(result=$(jq -r '
(.attacks.defended // [])[] |
"### \(.id): \(.name) ✓\n" +
"- **Counter-design addresses this attack**\n\n"
' "$input" 2>/dev/null); [[ -n "$result" ]] && echo "$result" || echo "_No defended attacks._")

## Counter-Designs

$(result=$(jq -r '
(.counter_designs // [])[] |
"### \(.id): \(.description)\n" +
"- **Addresses**: \(.addresses | join(", "))\n" +
"- **Architectural Change**: \(.architectural_change // "none")\n" +
"- **Cost**: \(.implementation_cost // "unknown") | **Improvement**: \(.security_improvement // "unknown")\n" +
"- **Trade-offs**: \(.trade_offs // "none")\n\n"
' "$input" 2>/dev/null); [[ -n "$result" ]] && echo "$result" || echo "_No counter-designs generated._")

## Metrics

| Metric | Value |
|--------|-------|
| Total Latency | $(jq '.metrics.total_latency_ms // 0' "$input")ms |
| Tokens Used | $(jq '.metrics.tokens_used // 0' "$input") |
| Cost | $(jq '.metrics.cost_cents // 0' "$input") cents |

REPORT
}

generate_summary() {
    local input="$1"
    local run_id="$2"

    local execution_mode
    execution_mode=$(jq -r '.execution_mode // "standard"' "$input")

    local header=""
    if [[ "$execution_mode" == "quick" ]]; then
        header="
> **UNVALIDATED**: Quick mode — no cross-validation performed.

"
    fi

    cat <<SUMMARY
# Red Team Summary — $(jq -r '.phase // "unknown"' "$input" | tr '[:lower:]' '[:upper:]')

**Run ID**: ${run_id}
${header}
## Results

| Category | Count |
|----------|-------|
| CONFIRMED_ATTACK | $(jq '.attack_summary.confirmed_count // 0' "$input") |
| THEORETICAL | $(jq '.attack_summary.theoretical_count // 0' "$input") |
| CREATIVE_ONLY | $(jq '.attack_summary.creative_count // 0' "$input") |
| DEFENDED | $(jq '.attack_summary.defended_count // 0' "$input") |

## Recommended Counter-Designs

$(result=$(jq -r '
(.counter_designs // [])[] |
"- **\(.id)**: \(.description) (addresses \(.addresses | join(", "))) — Cost: \(.implementation_cost // "unknown")"
' "$input" 2>/dev/null); [[ -n "$result" ]] && echo "$result" || echo "_No counter-designs available._")

SUMMARY
}

# =============================================================================
# Main
# =============================================================================

main() {
    local input=""
    local output_dir=""
    local run_id=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --input)      input="$2"; shift 2 ;;
            --output-dir) output_dir="$2"; shift 2 ;;
            --run-id)     run_id="$2"; shift 2 ;;
            -h|--help)
                echo "Usage: red-team-report.sh --input <file> --output-dir <dir> --run-id <id>"
                exit 0
                ;;
            *)            error "Unknown option: $1"; exit 1 ;;
        esac
    done

    if [[ -z "$input" || -z "$output_dir" || -z "$run_id" ]]; then
        error "--input, --output-dir, and --run-id are required"
        exit 1
    fi

    if [[ ! -f "$input" ]]; then
        error "Input file not found: $input"
        exit 1
    fi

    if ! jq empty "$input" 2>/dev/null; then
        error "Invalid JSON: $input"
        exit 2
    fi

    mkdir -p "$output_dir"

    # Generate full report
    local full_report
    full_report=$(generate_full_report "$input" "$run_id")

    # Apply redaction
    full_report=$(printf '%s' "$full_report" | redact_content)

    # Post-redaction safety check
    if ! post_redaction_check "$full_report"; then
        error "Report blocked by post-redaction safety check"
        error "Full report saved to $output_dir/${run_id}-report.md.BLOCKED"
        printf '%s' "$full_report" > "$output_dir/${run_id}-report.md.BLOCKED"
        chmod 0600 "$output_dir/${run_id}-report.md.BLOCKED"
        exit 1
    fi

    # Write full report with restricted permissions
    printf '%s' "$full_report" > "$output_dir/${run_id}-report.md"
    chmod 0600 "$output_dir/${run_id}-report.md"
    log "Full report: $output_dir/${run_id}-report.md (0600)"

    # Generate summary (safe for CI/PR)
    local summary
    summary=$(generate_summary "$input" "$run_id")
    summary=$(printf '%s' "$summary" | redact_content)

    printf '%s' "$summary" > "$output_dir/${run_id}-summary.md"
    log "Summary: $output_dir/${run_id}-summary.md"

    # Write .ci-safe manifest
    echo "$output_dir/${run_id}-summary.md" > "$output_dir/.ci-safe"
    log "CI-safe manifest: $output_dir/.ci-safe"
}

main "$@"
