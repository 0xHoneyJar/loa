#!/usr/bin/env bash
# butterfreezone-validate.sh - Validate BUTTERFREEZONE.md structure and content
# Version: 1.0.0
#
# Validates provenance tags, AGENT-CONTEXT, references, word budget,
# ground-truth-meta, and freshness. Used by RTFM gate and /butterfreezone skill.
#
# Usage:
#   .claude/scripts/butterfreezone-validate.sh [OPTIONS]
#
# Exit Codes:
#   0 - All checks pass
#   1 - Failures detected
#   2 - Warnings only (advisory)

export LC_ALL=C
export TZ=UTC

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_VERSION="1.0.0"

# =============================================================================
# Defaults
# =============================================================================

FILE="BUTTERFREEZONE.md"
CONFIG_FILE=".loa.config.yaml"
STRICT="false"
JSON_OUT="false"
QUIET="false"
LIVE_CHECK="false"

FAILURES=0
WARNINGS=0
PASSES=0
CHECKS=()

# =============================================================================
# Logging
# =============================================================================

log_pass() {
    PASSES=$((PASSES + 1))
    CHECKS+=("$(jq -nc --arg name "$1" --arg status "pass" '{name: $name, status: $status}')")
    [[ "$QUIET" == "true" ]] && return 0
    echo "  PASS: $2"
}

log_fail() {
    FAILURES=$((FAILURES + 1))
    local detail="${3:-}"
    if [[ -n "$detail" ]]; then
        CHECKS+=("$(jq -nc --arg name "$1" --arg status "fail" --arg detail "$detail" '{name: $name, status: $status, detail: $detail}')")
    else
        CHECKS+=("$(jq -nc --arg name "$1" --arg status "fail" '{name: $name, status: $status}')")
    fi
    [[ "$QUIET" == "true" ]] && return 0
    echo "  FAIL: $2"
}

log_warn() {
    if [[ "$STRICT" == "true" ]]; then
        log_fail "$@"
        return
    fi
    WARNINGS=$((WARNINGS + 1))
    local detail="${3:-}"
    if [[ -n "$detail" ]]; then
        CHECKS+=("$(jq -nc --arg name "$1" --arg status "warn" --arg detail "$detail" '{name: $name, status: $status, detail: $detail}')")
    else
        CHECKS+=("$(jq -nc --arg name "$1" --arg status "warn" '{name: $name, status: $status}')")
    fi
    [[ "$QUIET" == "true" ]] && return 0
    echo "  WARN: $2"
}

# =============================================================================
# Usage
# =============================================================================

usage() {
    cat <<'USAGE'
Usage: butterfreezone-validate.sh [OPTIONS]

Validate BUTTERFREEZONE.md structure and content.

Options:
  --file PATH        File to validate (default: BUTTERFREEZONE.md)
  --strict           Treat advisory warnings as failures
  --json             Output results as JSON
  --quiet            Suppress output, exit code only
  --help             Show usage

Exit codes:
  0  All checks pass
  1  Failures detected
  2  Warnings only (advisory)
USAGE
    exit "${1:-0}"
}

# =============================================================================
# Argument Parsing
# =============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --file)
                FILE="$2"
                shift 2
                ;;
            --strict)
                STRICT="true"
                shift
                ;;
            --json)
                JSON_OUT="true"
                shift
                ;;
            --quiet)
                QUIET="true"
                shift
                ;;
            --live)
                LIVE_CHECK="true"
                shift
                ;;
            --help)
                usage 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                usage 2
                ;;
        esac
    done
}

# =============================================================================
# Configuration
# =============================================================================

get_config_value() {
    local key="$1"
    local default="$2"

    if [[ -f "$CONFIG_FILE" ]] && command -v yq &>/dev/null; then
        local val
        val=$(yq ".$key // \"\"" "$CONFIG_FILE" 2>/dev/null) || true
        if [[ -n "$val" && "$val" != "null" ]]; then
            echo "$val"
            return
        fi
    fi
    echo "$default"
}

# =============================================================================
# Validation Checks (SDD 3.2.2)
# =============================================================================

# Check 1: Existence
validate_existence() {
    if [[ ! -f "$FILE" ]]; then
        log_fail "existence" "BUTTERFREEZONE.md not found at $FILE" "file not found"
        return 1
    fi
    log_pass "existence" "BUTTERFREEZONE.md exists"
    return 0
}

# Check 2: AGENT-CONTEXT block
validate_agent_context() {
    if ! grep -q "<!-- AGENT-CONTEXT" "$FILE" 2>/dev/null; then
        log_fail "agent_context" "Missing AGENT-CONTEXT metadata block" "block missing"
        return 1
    fi

    local context_block
    context_block=$(sed -n '/<!-- AGENT-CONTEXT/,/-->/p' "$FILE" 2>/dev/null)

    for field in name type purpose version; do
        if ! echo "$context_block" | grep -q "^${field}:" 2>/dev/null; then
            log_fail "agent_context" "AGENT-CONTEXT missing required field: $field" "missing field: $field"
            return 1
        fi
    done

    # Advisory checks for recommended fields (SDD §3.1.5)
    # Accept both flat "interfaces: [...]" and structured "interfaces:" formats
    if ! echo "$context_block" | grep -q "^interfaces" 2>/dev/null; then
        log_warn "agent_context_ext" "AGENT-CONTEXT missing recommended field: interfaces" "missing: interfaces"
    fi

    if ! echo "$context_block" | grep -q "^dependencies:" 2>/dev/null; then
        log_warn "agent_context_ext" "AGENT-CONTEXT missing recommended field: dependencies" "missing: dependencies"
    fi

    # Advisory: check for structured interfaces format (v1.40+ / cycle-030)
    if echo "$context_block" | grep -q "^interfaces:" 2>/dev/null; then
        if echo "$context_block" | grep -q "^  core:" 2>/dev/null; then
            log_pass "agent_context_structured" "AGENT-CONTEXT has structured interfaces (v1.40+)"
        fi
    fi

    log_pass "agent_context" "AGENT-CONTEXT block valid (all required fields present)"
    return 0
}

# Check 2b: Core skills manifest (SDD cycle-030 §3.5)
validate_core_skills_manifest() {
    if [[ ! -f ".claude/data/core-skills.json" ]]; then
        log_warn "core_skills_manifest" "core-skills.json not found — skill provenance will be flat" \
            "Run /update-loa to generate"
        return 0
    fi
    local count
    count=$(jq '.skills | length' .claude/data/core-skills.json 2>/dev/null) || {
        log_warn "core_skills_manifest" "core-skills.json invalid JSON" "parse error"
        return 0
    }
    log_pass "core_skills_manifest" "core-skills.json valid (${count} skills)"
}

# Check 3: Provenance tags
validate_provenance() {
    local sections
    sections=$(grep -c "^## " "$FILE" 2>/dev/null) || sections=0
    local tagged
    tagged=$(grep -c "<!-- provenance:" "$FILE" 2>/dev/null) || tagged=0

    if (( sections == 0 )); then
        log_pass "provenance" "No sections to validate"
        return 0
    fi

    if (( tagged < sections )); then
        log_fail "provenance" "Missing provenance tags: $tagged/$sections sections tagged" "$tagged of $sections tagged"
        return 1
    fi

    # Validate tag values
    local invalid=0
    while IFS= read -r line; do
        local tag
        tag=$(echo "$line" | sed 's/.*provenance: *\([A-Z_-]*\).*/\1/')
        case "$tag" in
            CODE-FACTUAL|DERIVED|OPERATIONAL) ;;
            *) invalid=$((invalid + 1)) ;;
        esac
    done < <(grep "<!-- provenance:" "$FILE" 2>/dev/null)

    if (( invalid > 0 )); then
        log_fail "provenance" "$invalid invalid provenance tag values" "$invalid invalid tags"
        return 1
    fi

    log_pass "provenance" "All sections have valid provenance tags ($tagged/$sections)"
    return 0
}

# Check 4: File references
validate_references() {
    local failures=0
    local checked=0

    # Only scan backtick-fenced references (SDD 3.1.15)
    local refs
    refs=$(grep -oE '`[a-zA-Z0-9_./-]+:[a-zA-Z_L][a-zA-Z0-9_]*`' "$FILE" 2>/dev/null \
        | sed 's/`//g' | sort -u) || true

    while IFS= read -r ref; do
        [[ -z "$ref" ]] && continue

        local file="${ref%%:*}"
        local symbol="${ref#*:}"

        # Skip non-file references (URLs, timestamps, meta fields)
        [[ "$file" == *"http"* ]] && continue
        [[ "$file" == *"//"* ]] && continue
        [[ "$file" == "head_sha" ]] && continue
        [[ "$file" == "generated_at" ]] && continue
        [[ "$file" == "generator" ]] && continue

        checked=$((checked + 1))

        if [[ ! -f "$file" ]]; then
            log_fail "references" "Referenced file missing: $file (in \`$ref\`)" "file missing: $file"
            failures=$((failures + 1))
        elif [[ "$symbol" == L* ]]; then
            # Line reference — just validate file exists (done above)
            :
        elif ! grep -q "$symbol" "$file" 2>/dev/null; then
            log_warn "references" "Symbol not found: $symbol in $file (advisory)" "symbol not found: $ref"
        fi
    done <<< "$refs"

    if (( failures == 0 )); then
        log_pass "references" "All file references valid ($checked checked)"
    fi

    return $(( failures > 0 ? 1 : 0 ))
}

# Check 5: Word budget
validate_word_budget() {
    local total_words
    total_words=$(wc -w < "$FILE" 2>/dev/null | tr -d ' ')
    local budget
    budget=$(get_config_value "butterfreezone.word_budget.total" "3400")

    if (( total_words > budget )); then
        log_warn "word_budget" "Word budget exceeded: $total_words / $budget (advisory)" "exceeded: $total_words > $budget"
    else
        log_pass "word_budget" "Word budget: $total_words / $budget"
    fi
}

# Check 5b: Minimum word count (FR-5: narrative quality gate)
validate_min_words() {
    local total_words
    total_words=$(wc -w < "$FILE" 2>/dev/null | tr -d ' ')

    if (( total_words < 500 )); then
        log_fail "min_words" "Output too sparse: $total_words words (minimum: 500)" "sparse: $total_words < 500"
    else
        log_pass "min_words" "Word count sufficient: $total_words (minimum: 500)"
    fi
}

# Check 5c: Architecture diagram (FR-5: narrative quality gate)
validate_architecture_diagram() {
    if ! grep -q "^## Architecture" "$FILE" 2>/dev/null; then
        log_warn "arch_section" "Missing Architecture section" "section missing"
        return 0
    fi

    # Extract only the Architecture section content (between ## Architecture and next ##)
    local arch_content
    arch_content=$(sed -n '/^## Architecture/,/^## /p' "$FILE" 2>/dev/null | sed '$d') || true

    if echo "$arch_content" | grep -q "mermaid" 2>/dev/null || echo "$arch_content" | grep -q '```' 2>/dev/null; then
        log_pass "arch_diagram" "Architecture section contains diagram"
    else
        log_warn "arch_diagram" "Architecture section missing diagram (mermaid or code block)" "diagram missing"
    fi
}

# Check 6: ground-truth-meta
validate_meta() {
    if ! grep -q "<!-- ground-truth-meta" "$FILE" 2>/dev/null; then
        log_fail "meta" "Missing ground-truth-meta block" "block missing"
        return 1
    fi

    local meta_sha
    meta_sha=$(sed -n '/<!-- ground-truth-meta/,/-->/p' "$FILE" 2>/dev/null \
        | grep "head_sha:" | awk '{print $2}') || true
    local current_sha
    current_sha=$(git rev-parse HEAD 2>/dev/null || echo "unknown")

    if [[ -z "$meta_sha" ]]; then
        log_fail "meta" "ground-truth-meta missing head_sha field" "head_sha missing"
        return 1
    fi

    if [[ "$meta_sha" != "$current_sha" ]]; then
        log_warn "meta" "Stale: head_sha mismatch (generated: ${meta_sha:0:8}, current: ${current_sha:0:8})" "head_sha mismatch"
    else
        log_pass "meta" "ground-truth-meta SHA matches HEAD"
    fi
    return 0
}

# Check 7a: Architecture narrative (SDD §3.1.4)
validate_architecture_narrative() {
    if ! grep -q "^## Architecture" "$FILE" 2>/dev/null; then
        return 0
    fi

    local arch_content
    arch_content=$(sed -n '/^## Architecture/,/^## /p' "$FILE" 2>/dev/null | sed '$d')

    # Count narrative text lines (not code blocks, diagrams, headers, provenance)
    local narrative_lines
    narrative_lines=$(echo "$arch_content" | grep -v '^[#|`<]' | grep -v '^\s*$' | \
        grep -v '^---' | grep -v 'provenance:' | grep -v 'graph TD' | wc -l)

    if (( narrative_lines < 2 )); then
        log_fail "arch_narrative" "Architecture section lacks narrative (only $narrative_lines text lines)" "sparse"
    else
        log_pass "arch_narrative" "Architecture section has narrative ($narrative_lines text lines)"
    fi
}

# Check 7b: Capability descriptions (SDD §3.1.1)
validate_capability_descriptions() {
    if ! grep -q "^## Key Capabilities" "$FILE" 2>/dev/null; then
        log_warn "cap_desc" "Missing Key Capabilities section" "section missing"
        return 0
    fi

    local bare_caps
    bare_caps=$(sed -n '/^## Key Capabilities/,/^## /p' "$FILE" 2>/dev/null | \
        grep -cE '^- `[^`]+`$') || bare_caps=0

    if (( bare_caps > 0 )); then
        log_fail "cap_desc" "$bare_caps capabilities without descriptions" "bare caps: $bare_caps"
    else
        log_pass "cap_desc" "All capabilities have descriptions"
    fi
}

# Check 7c: Module map purposes (SDD §3.1.2)
validate_module_purposes() {
    if ! grep -q "^## Module Map" "$FILE" 2>/dev/null; then
        log_warn "mod_purpose" "Missing Module Map section" "section missing"
        return 0
    fi

    local empty_purposes
    empty_purposes=$(sed -n '/^## Module Map/,/^## /p' "$FILE" 2>/dev/null | \
        grep -E '^\|' | grep -v '^\|[-]' | grep -v '^| Module' | \
        awk -F'|' '{gsub(/[[:space:]]/,"",$4); if($4=="") print}' | wc -l)

    if (( empty_purposes > 0 )); then
        log_fail "mod_purpose" "$empty_purposes modules with empty Purpose column" "empty: $empty_purposes"
    else
        log_pass "mod_purpose" "All modules have Purpose descriptions"
    fi
}

# Check 7d: No stub descriptions (SDD §3.1.3)
validate_no_description_available() {
    if grep -q "No description available" "$FILE" 2>/dev/null; then
        log_fail "no_desc" "Contains 'No description available' — header extraction failed" "found stub"
    else
        log_pass "no_desc" "No stub descriptions found"
    fi
}

# Check 8: Freshness
validate_freshness() {
    local generated_at
    generated_at=$(sed -n '/<!-- ground-truth-meta/,/-->/p' "$FILE" 2>/dev/null \
        | grep "generated_at:" | awk '{print $2}') || true

    if [[ -z "$generated_at" ]]; then
        log_warn "freshness" "No generated_at timestamp found" "timestamp missing"
        return 0
    fi

    local staleness_days
    staleness_days=$(get_config_value "butterfreezone.staleness_days" "7")

    # Parse the timestamp and compare with current time
    local gen_epoch
    gen_epoch=$(date -d "$generated_at" +%s 2>/dev/null || echo 0)
    local now_epoch
    now_epoch=$(date +%s)
    local diff_days=$(( (now_epoch - gen_epoch) / 86400 ))

    if (( diff_days > staleness_days )); then
        log_warn "freshness" "BUTTERFREEZONE.md is $diff_days days old (threshold: $staleness_days)" "stale: $diff_days days"
    else
        log_pass "freshness" "Freshness check passed ($diff_days days old, threshold: $staleness_days)"
    fi
}

# =============================================================================
# JSON Output (SDD 4.3)
# =============================================================================

emit_json() {
    local status="pass"
    if (( FAILURES > 0 )); then
        status="fail"
    elif (( WARNINGS > 0 )); then
        status="warn"
    fi

    local checks_json=""
    for check in "${CHECKS[@]}"; do
        [[ -n "$checks_json" ]] && checks_json="${checks_json}, "
        checks_json="${checks_json}${check}"
    done

    cat <<EOF
{
  "status": "$status",
  "validator": "butterfreezone-validate",
  "version": "${SCRIPT_VERSION}",
  "file": "$FILE",
  "passed": $PASSES,
  "failed": $FAILURES,
  "warnings": $WARNINGS,
  "checks": [$checks_json],
  "errors": [],
  "strict_mode": $STRICT
}
EOF
}

# =============================================================================
# Cross-Repo Agent Legibility Validators (cycle-017)
# =============================================================================

# Advisory: ecosystem field validation
validate_ecosystem() {
    local context_block
    context_block=$(sed -n '/<!-- AGENT-CONTEXT/,/-->/p' "$FILE" 2>/dev/null) || true

    if echo "$context_block" | grep -q "^ecosystem:" 2>/dev/null; then
        # Check each entry has repo and role
        local eco_block
        eco_block=$(echo "$context_block" | sed -n '/^ecosystem:/,/^[a-z]/p' | sed '$d')
        local repos
        repos=$(echo "$eco_block" | grep -c '^\s*- repo:' 2>/dev/null) || repos=0
        local roles
        roles=$(echo "$eco_block" | grep -c '^\s*role:' 2>/dev/null) || roles=0

        if (( repos > 0 && repos == roles )); then
            # Validate repo format (owner/name)
            local bad_repos
            bad_repos=$(echo "$eco_block" | grep '^\s*- repo:' | grep -cvE '^\s*- repo: [a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+' 2>/dev/null) || bad_repos=0
            if (( bad_repos > 0 )); then
                log_warn "ecosystem" "${bad_repos} ecosystem entries with malformed repo slug" "bad repos: ${bad_repos}"
            else
                log_pass "ecosystem" "Ecosystem field valid (${repos} entries, all with repo/role)"
            fi
        elif (( repos > 0 )); then
            log_warn "ecosystem" "Ecosystem entries missing role field (repos: ${repos}, roles: ${roles})" "incomplete"
        fi
    else
        # Check if config declares ecosystem but AGENT-CONTEXT doesn't have it
        if [[ -f ".loa.config.yaml" ]] && command -v yq &>/dev/null; then
            local config_eco
            config_eco=$(yq '.butterfreezone.ecosystem | length // 0' .loa.config.yaml 2>/dev/null) || config_eco=0
            if (( config_eco > 0 )); then
                log_warn "ecosystem" "Config has ${config_eco} ecosystem entries but AGENT-CONTEXT missing ecosystem field (stale generation?)" "stale"
            fi
        fi
    fi
}

# Advisory: capability_requirements validation
validate_capability_requirements() {
    local context_block
    context_block=$(sed -n '/<!-- AGENT-CONTEXT/,/-->/p' "$FILE" 2>/dev/null) || true

    if echo "$context_block" | grep -q "^capability_requirements:" 2>/dev/null; then
        local valid_caps="filesystem|git|shell|github_api|network"
        local cap_entries
        cap_entries=$(echo "$context_block" | sed -n '/^capability_requirements:/,/^[a-z]/p' | \
            grep '^\s*-' | wc -l | tr -d ' ')
        local bad_caps
        bad_caps=$(echo "$context_block" | sed -n '/^capability_requirements:/,/^[a-z]/p' | \
            grep '^\s*-' | grep -cvE "^\s*- (${valid_caps}):" 2>/dev/null) || bad_caps=0

        if (( bad_caps > 0 )); then
            log_warn "cap_req" "${bad_caps} capability entries with unknown vocabulary" "bad: ${bad_caps}"
        else
            log_pass "cap_req" "Capability requirements valid (${cap_entries} entries)"
        fi
    fi
}

# Advisory: verification section validation
validate_verification_section() {
    if ! grep -q "^## Verification" "$FILE" 2>/dev/null; then
        return 0  # Optional section, silent skip
    fi

    local verif_content
    verif_content=$(sed -n '/^## Verification/,/^## /p' "$FILE" 2>/dev/null | sed '$d')

    # Check provenance tag
    if ! echo "$verif_content" | grep -q 'provenance:' 2>/dev/null; then
        log_warn "verification" "Verification section missing provenance tag" "no provenance"
    fi

    # Check for at least one metric line
    local metric_lines
    metric_lines=$(echo "$verif_content" | grep -c '^-' 2>/dev/null) || metric_lines=0
    if (( metric_lines == 0 )); then
        log_warn "verification" "Verification section has no metric lines" "empty"
    else
        log_pass "verification" "Verification section valid (${metric_lines} metrics)"
    fi
}

# Ecosystem staleness detection (sprint-110, Section IX Criticism 1)
validate_ecosystem_staleness() {
    local config=".loa.config.yaml"
    [[ ! -f "$config" ]] && return 0
    ! command -v yq &>/dev/null && return 0

    local config_count bfz_count
    config_count=$(yq '.butterfreezone.ecosystem | length' "$config" 2>/dev/null) || config_count=0
    bfz_count=$(sed -n '/<!-- AGENT-CONTEXT/,/-->/p' "$FILE" 2>/dev/null | \
        grep -c '^\s*- repo:') || bfz_count=0

    if [[ "$config_count" -gt 0 && "$bfz_count" -eq 0 ]]; then
        log_warn "eco_stale" "Config has $config_count ecosystem entries but AGENT-CONTEXT has none (stale generation)" "stale"
    elif [[ "$config_count" -eq 0 && "$bfz_count" -gt 0 ]]; then
        log_warn "eco_stale" "AGENT-CONTEXT has ecosystem entries but config has none (orphaned)" "orphaned"
    elif [[ "$config_count" -ne "$bfz_count" ]]; then
        log_warn "eco_stale" "Config has $config_count ecosystem entries but AGENT-CONTEXT has $bfz_count (count mismatch)" "mismatch"
    elif [[ "$config_count" -gt 0 ]]; then
        # Check specific repo slugs match
        local config_repos bfz_repos
        config_repos=$(yq '.butterfreezone.ecosystem[].repo' "$config" 2>/dev/null | sort)
        bfz_repos=$(sed -n '/<!-- AGENT-CONTEXT/,/-->/p' "$FILE" 2>/dev/null | \
            grep '^\s*- repo:' | sed 's/.*repo: *//' | sort)
        if [[ "$config_repos" != "$bfz_repos" ]]; then
            log_warn "eco_stale" "Ecosystem repo slugs differ between config and AGENT-CONTEXT" "slug_drift"
        else
            log_pass "eco_stale" "Ecosystem entries match config ($config_count entries, slugs verified)"
        fi
    fi
}

# Live ecosystem verification (sprint-112, Task 7.1)
validate_ecosystem_live() {
    [[ "$LIVE_CHECK" != "true" ]] && return 0

    if ! command -v gh &>/dev/null || ! gh auth status &>/dev/null 2>&1; then
        log_warn "eco_live" "gh not authenticated — skipping live ecosystem check" "no_auth"
        return 0
    fi

    local eco_repos
    eco_repos=$(sed -n '/<!-- AGENT-CONTEXT/,/-->/p' "$FILE" 2>/dev/null | \
        grep '^\s*- repo:' | sed 's/.*repo: *//') || true

    [[ -z "$eco_repos" ]] && return 0

    local total=0 found=0 missing=0 no_bfz=0
    while IFS= read -r repo <&3; do
        [[ -z "$repo" ]] && continue
        total=$((total + 1))

        if ! gh repo view "$repo" &>/dev/null 2>&1; then
            # Live checks are always advisory (WARN not FAIL, even in strict mode)
            WARNINGS=$((WARNINGS + 1))
            CHECKS+=("$(jq -nc --arg name "eco_live" --arg status "warn" --arg detail "missing_repo" '{name: $name, status: $status, detail: $detail}')")
            [[ "$QUIET" != "true" ]] && echo "  WARN: Ecosystem repo not found: $repo"
            missing=$((missing + 1))
            continue
        fi

        if ! gh api "repos/${repo}/contents/BUTTERFREEZONE.md" &>/dev/null 2>&1; then
            # Live checks are always advisory (WARN not FAIL, even in strict mode)
            WARNINGS=$((WARNINGS + 1))
            CHECKS+=("$(jq -nc --arg name "eco_live" --arg status "warn" --arg detail "no_bfz" '{name: $name, status: $status, detail: $detail}')")
            [[ "$QUIET" != "true" ]] && echo "  WARN: No BUTTERFREEZONE.md in: $repo"
            no_bfz=$((no_bfz + 1))
            continue
        fi

        found=$((found + 1))
    done 3<<< "$eco_repos"

    if [[ "$missing" -eq 0 && "$no_bfz" -eq 0 && "$total" -gt 0 ]]; then
        log_pass "eco_live" "All $total ecosystem repos verified with BUTTERFREEZONE.md"
    fi
}

# Protocol version staleness advisory (sprint-113, Task 8.2)
# Compares declared protocol versions against published npm package versions.
# Advisory only — WARN on mismatch, graceful skip when offline.
validate_protocol_version() {
    [[ "$LIVE_CHECK" != "true" ]] && return 0

    local config=".loa.config.yaml"
    [[ ! -f "$config" ]] && return 0
    ! command -v yq &>/dev/null && return 0

    local eco_count
    eco_count=$(yq '.butterfreezone.ecosystem | length' "$config" 2>/dev/null) || eco_count=0
    [[ "$eco_count" -eq 0 ]] && return 0

    local i=0 checked=0 stale=0
    while [[ $i -lt $eco_count ]]; do
        local protocol
        protocol=$(yq ".butterfreezone.ecosystem[$i].protocol // \"\"" "$config" 2>/dev/null) || protocol=""
        i=$((i + 1))
        [[ -z "$protocol" ]] && continue

        # Parse protocol: "pkg-name@version" → package name and declared version
        local pkg_name declared_version
        pkg_name=$(echo "$protocol" | sed 's/@[^@]*$//')
        declared_version=$(echo "$protocol" | grep -o '@[^@]*$' | sed 's/@//')
        [[ -z "$pkg_name" || -z "$declared_version" ]] && continue

        # Try npm view first (most reliable for npm packages)
        local live_version=""
        if command -v npm &>/dev/null; then
            live_version=$(npm view "@0xhoneyjar/${pkg_name}" version 2>/dev/null) || live_version=""
        fi

        # Fallback: check GitHub releases via gh api
        if [[ -z "$live_version" ]] && command -v gh &>/dev/null; then
            live_version=$(gh api "repos/0xHoneyJar/${pkg_name}/releases/latest" --jq '.tag_name' 2>/dev/null | sed 's/^v//') || live_version=""
        fi

        # No live version available — skip gracefully
        [[ -z "$live_version" ]] && continue

        checked=$((checked + 1))
        if [[ "$declared_version" != "$live_version" ]]; then
            stale=$((stale + 1))
            # Always advisory — WARN not FAIL, even in strict mode
            WARNINGS=$((WARNINGS + 1))
            CHECKS+=("$(jq -nc --arg name "proto_version" --arg status "warn" --arg detail "stale:${pkg_name}@${declared_version}->$live_version" '{name: $name, status: $status, detail: $detail}')")
            [[ "$QUIET" != "true" ]] && echo "  WARN: Protocol version drift: ${pkg_name}@${declared_version} declared, ${live_version} published"
        fi
    done

    if [[ "$checked" -gt 0 && "$stale" -eq 0 ]]; then
        log_pass "proto_version" "All $checked protocol versions match published ($eco_count ecosystem entries)"
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"

    [[ "$QUIET" != "true" ]] && echo "Validating: $FILE"
    [[ "$QUIET" != "true" ]] && echo ""

    # Run all checks
    validate_existence || true

    # Only run remaining checks if file exists
    if [[ -f "$FILE" ]]; then
        validate_agent_context || true
        validate_core_skills_manifest || true
        validate_provenance || true
        validate_references || true
        validate_word_budget || true
        validate_min_words || true
        validate_architecture_diagram || true
        validate_architecture_narrative || true
        validate_capability_descriptions || true
        validate_module_purposes || true
        validate_no_description_available || true
        validate_ecosystem || true
        validate_ecosystem_staleness || true
        validate_ecosystem_live || true
        validate_protocol_version || true
        validate_capability_requirements || true
        validate_verification_section || true
        validate_meta || true
        validate_freshness || true
    fi

    # Summary
    [[ "$QUIET" != "true" ]] && echo ""
    [[ "$QUIET" != "true" ]] && echo "Results: $PASSES passed, $FAILURES failed, $WARNINGS warnings"

    # JSON output
    if [[ "$JSON_OUT" == "true" ]]; then
        emit_json
    fi

    # Exit code
    if (( FAILURES > 0 )); then
        exit 1
    elif (( WARNINGS > 0 )); then
        exit 2
    fi
    exit 0
}

main "$@"
