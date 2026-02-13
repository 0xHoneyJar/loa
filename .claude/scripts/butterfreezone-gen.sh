#!/usr/bin/env bash
# butterfreezone-gen.sh - Generate BUTTERFREEZONE.md from code reality
# Version: 1.0.0
#
# Produces a provenance-tagged, checksum-verified, token-efficient document
# that serves as the agent-API for any Loa-managed codebase.
#
# Usage:
#   .claude/scripts/butterfreezone-gen.sh [OPTIONS]
#
# Exit Codes:
#   0 - Success
#   1 - Generation failed
#   2 - Configuration error
#   3 - No input data available (Tier 3 bootstrap used)

# Determinism guarantees (SDD 3.1.16)
export LC_ALL=C
export TZ=UTC
shopt -s nullglob

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_VERSION="1.0.0"

# =============================================================================
# Defaults
# =============================================================================

OUTPUT="BUTTERFREEZONE.md"
CONFIG_FILE=".loa.config.yaml"
FORCED_TIER=""
DRY_RUN="false"
JSON_OUTPUT="false"
VERBOSE="false"
LOCK_FILE=""

# Detect project root
PROJECT_ROOT=""
if command -v git &>/dev/null && git rev-parse --show-toplevel &>/dev/null 2>&1; then
    PROJECT_ROOT="$(git rev-parse --show-toplevel)"
else
    PROJECT_ROOT="$(pwd)"
fi

# Canonical section order (SDD 3.1.12)
CANONICAL_ORDER=(
    "agent_context"
    "header"
    "capabilities"
    "architecture"
    "interfaces"
    "module_map"
    "ecosystem"
    "limitations"
    "quick_start"
)

# Word budgets (SDD 3.1.6)
declare -A WORD_BUDGETS=(
    [agent_context]=80
    [header]=120
    [capabilities]=600
    [architecture]=400
    [interfaces]=800
    [module_map]=600
    [ecosystem]=200
    [limitations]=200
    [quick_start]=200
)
TOTAL_BUDGET=3200

# Truncation priority (higher = truncated last)
TRUNCATION_PRIORITY=(
    "quick_start"
    "ecosystem"
    "limitations"
    "module_map"
    "architecture"
    "capabilities"
    "interfaces"
)

# Vendor/build exclusion directories (SDD 3.1.14)
EXCLUDE_DIRS=(
    --exclude-dir=node_modules
    --exclude-dir=vendor
    --exclude-dir=.git
    --exclude-dir=dist
    --exclude-dir=build
    --exclude-dir=__pycache__
    --exclude-dir=.next
    --exclude-dir=target
    --exclude-dir=.beads
    --exclude-dir=.run
)

# Security redaction patterns (SDD 3.1.8)
REDACTION_PATTERNS=(
    'AKIA[0-9A-Z]{16}'
    'ghp_[A-Za-z0-9_]{36}'
    'gho_[A-Za-z0-9_]{36}'
    'ghs_[A-Za-z0-9_]{36}'
    'ghr_[A-Za-z0-9_]{36}'
    'eyJ[A-Za-z0-9+/=]{20,}'
    'BEGIN[[:space:]]+(RSA|DSA|EC|OPENSSH)[[:space:]]+PRIVATE[[:space:]]+KEY'
    '(password|secret|token|api_key|apikey)[[:space:]]*[=:][[:space:]]*[^[:space:]]{8,}'
)

ALLOWLIST_PATTERNS=(
    'sha256:[a-f0-9]{64}'
    'data:image/[a-z]+;base64'
    'head_sha:'
    'generator:'
    'generated_at:'
)

# =============================================================================
# Logging
# =============================================================================

log_info() {
    [[ "$VERBOSE" == "true" ]] && echo "[butterfreezone-gen] INFO: $*" >&2
    return 0
}

log_warn() {
    echo "[butterfreezone-gen] WARN: $*" >&2
}

log_error() {
    echo "[butterfreezone-gen] ERROR: $*" >&2
}

# =============================================================================
# Usage
# =============================================================================

usage() {
    cat <<'USAGE'
Usage: butterfreezone-gen.sh [OPTIONS]

Generate BUTTERFREEZONE.md — the agent-grounded README for this codebase.

Options:
  --output PATH      Output file (default: BUTTERFREEZONE.md)
  --config PATH      Config file (default: .loa.config.yaml)
  --tier N           Force input tier (1|2|3, default: auto-detect)
  --dry-run          Print to stdout, don't write file
  --json             Output generation metadata as JSON to stderr
  --verbose          Enable debug logging
  --help             Show usage

Exit codes:
  0  Success
  1  Generation failed (partial output may exist)
  2  Configuration error
  3  No input data available (Tier 3 bootstrap used)
USAGE
    exit "${1:-0}"
}

# =============================================================================
# Argument Parsing (Task 1.1)
# =============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output)
                OUTPUT="$2"
                shift 2
                ;;
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --tier)
                FORCED_TIER="$2"
                if [[ ! "$FORCED_TIER" =~ ^[123]$ ]]; then
                    log_error "Invalid tier: $FORCED_TIER (must be 1, 2, or 3)"
                    exit 2
                fi
                shift 2
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --json)
                JSON_OUTPUT="true"
                shift
                ;;
            --verbose)
                VERBOSE="true"
                shift
                ;;
            --help)
                usage 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage 2
                ;;
        esac
    done
}

# =============================================================================
# Configuration (SDD 5.2)
# =============================================================================

load_config() {
    if [[ -f "$CONFIG_FILE" ]] && command -v yq &>/dev/null; then
        local cfg_output
        cfg_output=$(yq '.butterfreezone.output_path // ""' "$CONFIG_FILE" 2>/dev/null) || true
        [[ -n "$cfg_output" && "$cfg_output" != "null" ]] && OUTPUT="$cfg_output"

        local cfg_budget
        cfg_budget=$(yq '.butterfreezone.word_budget.total // ""' "$CONFIG_FILE" 2>/dev/null) || true
        [[ -n "$cfg_budget" && "$cfg_budget" != "null" ]] && TOTAL_BUDGET="$cfg_budget"

        log_info "Config loaded from $CONFIG_FILE"
    else
        log_info "Using default configuration"
    fi
}

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
# Concurrency Protection (SDD 3.1.13)
# =============================================================================

acquire_lock() {
    LOCK_FILE="${OUTPUT}.lock"
    exec 200>"$LOCK_FILE"
    if ! flock -n 200; then
        log_warn "Another butterfreezone-gen process is running — skipping"
        exit 0
    fi
}

release_lock() {
    if [[ -n "${LOCK_FILE:-}" ]]; then
        flock -u 200 2>/dev/null || true
        rm -f "$LOCK_FILE" 2>/dev/null || true
    fi
}

trap release_lock EXIT

# =============================================================================
# Input Tier Detection (Task 1.2 / SDD 3.1.2)
# =============================================================================

has_content() {
    local file="$1"
    [[ -f "$file" ]] && [[ $(wc -w < "$file" 2>/dev/null || echo 0) -gt 10 ]]
}

detect_input_tier() {
    if [[ -n "$FORCED_TIER" ]]; then
        echo "$FORCED_TIER"
        return 0
    fi

    # Resolve grimoire dir
    local grimoire_dir
    grimoire_dir=$(get_config_value "paths.grimoire" "grimoires/loa")
    local reality_dir="${grimoire_dir}/reality"

    # Tier 1: Reality files with content
    if [[ -d "$reality_dir" ]] && has_content "$reality_dir/api-surface.md"; then
        echo 1
        return 0
    fi

    # Tier 2: Dependency manifests or source files
    if [[ -f "package.json" ]] || [[ -f "Cargo.toml" ]] || \
       [[ -f "pyproject.toml" ]] || [[ -f "go.mod" ]] || \
       [[ -f "Makefile" ]] || [[ -f "CMakeLists.txt" ]]; then
        echo 2
        return 0
    fi

    # Tier 2: Source files within maxdepth 3
    local src_files
    src_files=$(find . -maxdepth 3 -type f \( \
        -name "*.ts" -o -name "*.js" -o -name "*.py" -o \
        -name "*.rs" -o -name "*.go" -o -name "*.sh" -o \
        -name "*.java" -o -name "*.rb" -o -name "*.c" -o \
        -name "*.cpp" \
    \) -not -path "*/node_modules/*" -not -path "*/.git/*" \
       -not -path "*/vendor/*" -not -path "*/target/*" \
    2>/dev/null | head -1)

    if [[ -n "$src_files" ]]; then
        echo 2
        return 0
    fi

    # Tier 3: Bootstrap stub
    echo 3
    return 0
}

# =============================================================================
# Tier 2 Grep Wrapper (SDD 3.1.14)
# =============================================================================

tier2_grep() {
    LC_ALL=C timeout 30 grep -rn "${EXCLUDE_DIRS[@]}" --max-count=100 "$@" 2>/dev/null \
        | sort -t: -k1,1 -k2,2n | head -200 || true
}

# =============================================================================
# Per-Extractor Error Handling (SDD 3.1.11)
# =============================================================================

run_extractor() {
    local name="$1"
    local tier="$2"
    local result=""

    # Call extractor function directly (not in subshell) with error trapping
    if result=$("extract_${name}" "$tier" 2>/dev/null); then
        echo "$result"
    else
        local exit_code=$?
        log_warn "Extractor $name failed (exit $exit_code) — skipping section"
        echo "<!-- provenance: OPERATIONAL -->"
        echo "_Section unavailable: extractor failed. Regenerate with \`/butterfreezone\`._"
    fi
}

# =============================================================================
# Section Extractors (Task 1.3 / SDD 3.1.3)
# =============================================================================

extract_agent_context() {
    local tier="$1"
    local name="" type="" purpose="" version="" key_files="" interfaces="" deps=""

    # Project name: try manifests, then config, then git remote
    if [[ -f "package.json" ]] && command -v jq &>/dev/null; then
        name=$(jq -r '.name // ""' package.json 2>/dev/null) || true
    fi
    if [[ -z "$name" || "$name" == "null" ]] && [[ -f "Cargo.toml" ]]; then
        name=$(grep '^name' Cargo.toml 2>/dev/null | head -1 | sed 's/.*= *"\(.*\)"/\1/') || true
    fi
    if [[ -z "$name" || "$name" == "null" ]] && [[ -f ".loa.config.yaml" ]] && command -v yq &>/dev/null; then
        name=$(yq '.project.name // ""' .loa.config.yaml 2>/dev/null) || true
    fi
    if [[ -z "$name" || "$name" == "null" ]]; then
        name=$(git remote get-url origin 2>/dev/null | sed 's|.*/||;s|\.git$||') || true
    fi
    if [[ -z "$name" || "$name" == "null" ]]; then
        name=$(basename "$(pwd)")
    fi

    # Type: detect from manifest or structure
    if [[ -f ".claude/skills" ]] || [[ -d ".claude/skills" ]]; then
        type="framework"
    elif [[ -f "package.json" ]] && command -v jq &>/dev/null; then
        local pkg_main
        pkg_main=$(jq -r '.main // ""' package.json 2>/dev/null) || true
        if [[ -n "$pkg_main" && "$pkg_main" != "null" ]]; then
            type="library"
        else
            type="application"
        fi
    elif [[ -f "Cargo.toml" ]] && grep -q '\[lib\]' Cargo.toml 2>/dev/null; then
        type="library"
    else
        type="application"
    fi

    # Version: git tag or manifest
    version=$(git describe --tags --abbrev=0 2>/dev/null) || true
    if [[ -z "$version" ]] && [[ -f "package.json" ]] && command -v jq &>/dev/null; then
        version=$(jq -r '.version // ""' package.json 2>/dev/null) || true
    fi
    if [[ -z "$version" ]] && [[ -f "Cargo.toml" ]]; then
        version=$(grep '^version' Cargo.toml 2>/dev/null | head -1 | sed 's/.*= *"\(.*\)"/\1/') || true
    fi
    [[ -z "$version" || "$version" == "null" ]] && version="unknown"

    # Purpose: from package description or README first line
    if [[ -f "package.json" ]] && command -v jq &>/dev/null; then
        purpose=$(jq -r '.description // ""' package.json 2>/dev/null) || true
    fi
    if [[ -z "$purpose" || "$purpose" == "null" ]] && [[ -f "README.md" ]]; then
        purpose=$(sed -n '2,5p' README.md 2>/dev/null | head -1 | sed 's/^[#> ]*//' | head -c 120) || true
    fi
    [[ -z "$purpose" || "$purpose" == "null" ]] && purpose="No description available"

    # Key files
    local kf=()
    [[ -f ".claude/loa/CLAUDE.loa.md" ]] && kf+=(".claude/loa/CLAUDE.loa.md")
    [[ -f ".loa.config.yaml" ]] && kf+=(".loa.config.yaml")
    [[ -d ".claude/scripts" ]] && kf+=(".claude/scripts/")
    [[ -f "package.json" ]] && kf+=("package.json")
    [[ -f "Cargo.toml" ]] && kf+=("Cargo.toml")
    [[ -f "pyproject.toml" ]] && kf+=("pyproject.toml")
    [[ -f "go.mod" ]] && kf+=("go.mod")
    key_files=$(printf '%s' "[$(IFS=,; echo "${kf[*]}" | sed 's/,/, /g')]")

    # Dependencies
    local dep_list=()
    command -v bash &>/dev/null && dep_list+=("bash")
    command -v jq &>/dev/null && dep_list+=("jq")
    command -v yq &>/dev/null && dep_list+=("yq")
    command -v git &>/dev/null && dep_list+=("git")
    deps=$(printf '%s' "[$(IFS=,; echo "${dep_list[*]}" | sed 's/,/, /g')]")

    cat <<EOF
<!-- AGENT-CONTEXT
name: ${name}
type: ${type}
purpose: ${purpose}
key_files: ${key_files}
version: ${version}
trust_level: grounded
-->
EOF
}

extract_header() {
    local tier="$1"
    local name=""

    if [[ -f "package.json" ]] && command -v jq &>/dev/null; then
        name=$(jq -r '.name // ""' package.json 2>/dev/null) || true
    fi
    [[ -z "$name" || "$name" == "null" ]] && name=$(basename "$(pwd)")

    local desc=""
    if [[ -f "package.json" ]] && command -v jq &>/dev/null; then
        desc=$(jq -r '.description // ""' package.json 2>/dev/null) || true
    fi
    if [[ -z "$desc" || "$desc" == "null" ]] && [[ -f "README.md" ]]; then
        desc=$(sed -n '2,5p' README.md 2>/dev/null | head -1 | sed 's/^[#> ]*//') || true
    fi
    [[ -z "$desc" || "$desc" == "null" ]] && desc="No description available"

    local provenance
    provenance=$(tag_provenance "$tier" "header")

    cat <<EOF
# ${name}

<!-- provenance: ${provenance} -->
${desc}
EOF
}

extract_capabilities() {
    local tier="$1"

    if [[ "$tier" -eq 3 ]]; then
        return 0
    fi

    local provenance
    provenance=$(tag_provenance "$tier" "capabilities")
    local caps=""

    if [[ "$tier" -eq 1 ]]; then
        local grimoire_dir
        grimoire_dir=$(get_config_value "paths.grimoire" "grimoires/loa")
        if [[ -f "${grimoire_dir}/reality/api-surface.md" ]]; then
            caps=$(head -50 "${grimoire_dir}/reality/api-surface.md" 2>/dev/null | \
                grep -E '^[-*]|^#+' | head -20) || true
        fi
    fi

    if [[ -z "$caps" ]]; then
        # Tier 2: grep-based extraction
        local found=""

        # JavaScript/TypeScript exports
        local js_exports
        js_exports=$(tier2_grep -E "^export (function|const|class|default)" \
            --include="*.ts" --include="*.js" --include="*.tsx" 2>/dev/null | head -20) || true
        [[ -n "$js_exports" ]] && found="${found}${js_exports}\n"

        # Rust public items
        local rs_exports
        rs_exports=$(tier2_grep -E "^pub (fn|struct|enum|trait)" \
            --include="*.rs" 2>/dev/null | head -20) || true
        [[ -n "$rs_exports" ]] && found="${found}${rs_exports}\n"

        # Python public functions/classes
        local py_exports
        py_exports=$(tier2_grep -E "^(def |class )" \
            --include="*.py" 2>/dev/null | head -20) || true
        [[ -n "$py_exports" ]] && found="${found}${py_exports}\n"

        # Go exported functions
        local go_exports
        go_exports=$(tier2_grep -E "^func [A-Z]" \
            --include="*.go" 2>/dev/null | head -20) || true
        [[ -n "$go_exports" ]] && found="${found}${go_exports}\n"

        # Shell functions
        local sh_funcs
        sh_funcs=$(tier2_grep -E "^[a-z_]+\(\) \{" \
            --include="*.sh" 2>/dev/null | head -20) || true
        [[ -n "$sh_funcs" ]] && found="${found}${sh_funcs}\n"

        if [[ -n "$found" ]]; then
            caps=$(echo -e "$found" | while IFS=: read -r file line content; do
                [[ -z "$content" ]] && continue
                local sym
                sym=$(echo "$content" | sed 's/^export //;s/^pub //;s/(.*//;s/ {.*//;s/^function //;s/^const //;s/^class //;s/^def //;s/^fn //;s/^struct //;s/^enum //;s/^trait //;s/^func //' | tr -d ' ' | head -c 60)
                [[ -n "$sym" && -n "$file" ]] && echo "- \`${file}:${sym}\`"
            done | sort -u | head -30)
        fi
    fi

    if [[ -z "$caps" ]]; then
        return 0
    fi

    cat <<EOF
## Key Capabilities
<!-- provenance: ${provenance} -->
${caps}
EOF
}

extract_architecture() {
    local tier="$1"

    if [[ "$tier" -eq 3 ]]; then
        return 0
    fi

    local provenance
    provenance=$(tag_provenance "$tier" "architecture")
    local arch=""

    if [[ "$tier" -eq 1 ]]; then
        local grimoire_dir
        grimoire_dir=$(get_config_value "paths.grimoire" "grimoires/loa")
        if [[ -f "${grimoire_dir}/reality/architecture.md" ]]; then
            arch=$(head -30 "${grimoire_dir}/reality/architecture.md" 2>/dev/null) || true
        fi
    fi

    if [[ -z "$arch" ]]; then
        # Tier 2: Directory tree analysis (exclude hidden, vendor, build)
        local tree=""
        tree=$(find . -maxdepth 2 -type d \
            -not -path "*/\.*" \
            -not -path "*/node_modules*" \
            -not -path "*/vendor/*" \
            -not -path "*/target/*" \
            -not -path "*/.next/*" \
            -not -path "*/dist/*" \
            -not -path "*/build/*" \
            -not -path "*/__pycache__/*" \
            -not -name ".*" \
            -not -name "node_modules" \
            2>/dev/null | sort | head -30) || true

        if [[ -n "$tree" ]]; then
            arch="Directory structure:"
            arch="${arch}\n\`\`\`"
            arch="${arch}\n${tree}"
            arch="${arch}\n\`\`\`"
        fi
    fi

    if [[ -z "$arch" ]]; then
        return 0
    fi

    cat <<EOF
## Architecture
<!-- provenance: ${provenance} -->
$(echo -e "$arch")
EOF
}

extract_interfaces() {
    local tier="$1"

    if [[ "$tier" -eq 3 ]]; then
        return 0
    fi

    local provenance
    provenance=$(tag_provenance "$tier" "interfaces")
    local ifaces=""

    if [[ "$tier" -eq 1 ]]; then
        local grimoire_dir
        grimoire_dir=$(get_config_value "paths.grimoire" "grimoires/loa")
        if [[ -f "${grimoire_dir}/reality/contracts.md" ]]; then
            ifaces=$(head -50 "${grimoire_dir}/reality/contracts.md" 2>/dev/null) || true
        fi
    fi

    if [[ -z "$ifaces" ]]; then
        local found=""

        # Express/Fastify routes (exclude test fixtures and grimoires)
        local routes
        routes=$(tier2_grep -E '(app|router)\.(get|post|put|delete|patch)\(' \
            --include="*.ts" --include="*.js" \
            --exclude-dir=tests --exclude-dir=test --exclude-dir=fixtures \
            --exclude-dir=grimoires --exclude-dir=evals \
            2>/dev/null | head -20) || true
        [[ -n "$routes" ]] && found="${found}### HTTP Routes\n${routes}\n\n"

        # CLI commands (exclude test fixtures)
        local cli
        cli=$(tier2_grep -E '\.command\(' \
            --include="*.ts" --include="*.js" \
            --exclude-dir=tests --exclude-dir=test --exclude-dir=fixtures \
            --exclude-dir=grimoires --exclude-dir=evals \
            2>/dev/null | head -10) || true
        [[ -n "$cli" ]] && found="${found}### CLI Commands\n${cli}\n\n"

        # Shell skill commands (Loa specific)
        if [[ -d ".claude/skills" ]]; then
            local skills
            skills=$(find .claude/skills -maxdepth 1 -type d 2>/dev/null | \
                sort | tail -n +2 | while read -r d; do
                    local sname
                    sname=$(basename "$d")
                    echo "- \`/${sname}\`"
                done) || true
            [[ -n "$skills" ]] && found="${found}### Skill Commands\n${skills}\n\n"
        fi

        ifaces=$(echo -e "$found")
    fi

    if [[ -z "$ifaces" ]]; then
        return 0
    fi

    cat <<EOF
## Interfaces
<!-- provenance: ${provenance} -->
${ifaces}
EOF
}

extract_module_map() {
    local tier="$1"
    local provenance
    provenance=$(tag_provenance "$tier" "module_map")

    local table="| Module | Files | Purpose |\n|--------|-------|---------|\n"
    local found_any=false

    # Get top-level directories (exclude hidden dirs, vendor, build artifacts)
    local dirs
    dirs=$(find . -maxdepth 1 -type d \
        -not -name "." \
        -not -name "node_modules" \
        -not -name "vendor" \
        -not -name "target" \
        -not -name "dist" \
        -not -name "build" \
        -not -name "__pycache__" \
        -not -name ".next" \
        -not -name ".*" \
        2>/dev/null | sort) || true

    while IFS= read -r dir; do
        [[ -z "$dir" ]] && continue
        local dname
        dname=$(basename "$dir")
        local count
        count=$(find "$dir" -type f 2>/dev/null | wc -l | tr -d ' ') || true

        local purpose=""
        case "$dname" in
            src|lib|app) purpose="Source code" ;;
            tests|test|spec) purpose="Test suites" ;;
            docs|doc) purpose="Documentation" ;;
            scripts) purpose="Utility scripts" ;;
            grimoires) purpose="Loa state files" ;;
            .github) purpose="GitHub workflows" ;;
            *) purpose="" ;;
        esac

        table="${table}| \`${dname}/\` | ${count} | ${purpose} |\n"
        found_any=true
    done <<< "$dirs"

    if [[ "$found_any" == "false" ]]; then
        return 0
    fi

    cat <<EOF
## Module Map
<!-- provenance: ${provenance} -->
$(echo -e "$table")
EOF
}

extract_ecosystem() {
    local tier="$1"
    local provenance="OPERATIONAL"  # Always OPERATIONAL per SDD
    local eco=""

    if [[ -f "package.json" ]] && command -v jq &>/dev/null; then
        local deps
        deps=$(jq -r '(.dependencies // {}) + (.devDependencies // {}) | keys[]' package.json 2>/dev/null \
            | head -20 | while read -r dep; do
                echo "- \`${dep}\`"
            done) || true
        [[ -n "$deps" ]] && eco="### Dependencies\n${deps}"
    elif [[ -f "Cargo.toml" ]]; then
        local deps
        deps=$(grep -A1 '^\[dependencies\]' Cargo.toml 2>/dev/null | \
            grep -v '^\[' | grep '=' | head -20 | while IFS='=' read -r dep ver; do
                dep=$(echo "$dep" | tr -d ' ')
                [[ -n "$dep" ]] && echo "- \`${dep}\`"
            done) || true
        [[ -n "$deps" ]] && eco="### Dependencies\n${deps}"
    elif [[ -f "pyproject.toml" ]]; then
        local deps
        deps=$(grep -A50 '^\[project\]' pyproject.toml 2>/dev/null | \
            sed -n '/^dependencies/,/^\[/p' | grep -v '^\[' | head -20 | while read -r dep; do
                dep=$(echo "$dep" | sed 's/[",]//g;s/>=.*//;s/==.*//' | tr -d ' ')
                [[ -n "$dep" && "$dep" != "dependencies" ]] && echo "- \`${dep}\`"
            done) || true
        [[ -n "$deps" ]] && eco="### Dependencies\n${deps}"
    fi

    if [[ -z "$eco" ]]; then
        return 0
    fi

    cat <<EOF
## Ecosystem
<!-- provenance: ${provenance} -->
$(echo -e "$eco")
EOF
}

extract_limitations() {
    local tier="$1"

    if [[ "$tier" -eq 3 ]]; then
        return 0
    fi

    local provenance
    provenance=$(tag_provenance "$tier" "limitations")
    local limits=""

    if [[ "$tier" -eq 1 ]]; then
        local grimoire_dir
        grimoire_dir=$(get_config_value "paths.grimoire" "grimoires/loa")
        if [[ -f "${grimoire_dir}/reality/behaviors.md" ]]; then
            limits=$(grep -iA3 'limitation\|caveat\|warning\|known issue' \
                "${grimoire_dir}/reality/behaviors.md" 2>/dev/null | head -20) || true
        fi
    fi

    if [[ -z "$limits" ]] && [[ -f "README.md" ]]; then
        limits=$(sed -n '/^##.*[Ll]imit\|^##.*[Cc]aveat\|^##.*[Kk]nown/,/^## /p' \
            README.md 2>/dev/null | head -20 | sed '$d') || true
    fi

    if [[ -z "$limits" ]]; then
        return 0
    fi

    cat <<EOF
## Known Limitations
<!-- provenance: ${provenance} -->
${limits}
EOF
}

extract_quick_start() {
    local tier="$1"
    local provenance="OPERATIONAL"  # Always OPERATIONAL per SDD

    if [[ "$tier" -eq 3 ]]; then
        return 0
    fi

    local qs=""

    if [[ -f "README.md" ]]; then
        # Extract getting started / quick start / installation section
        qs=$(sed -n '/^##.*[Gg]etting [Ss]tarted\|^##.*[Qq]uick [Ss]tart\|^##.*[Ii]nstall/,/^## /p' \
            README.md 2>/dev/null | head -20 | sed '$d') || true
    fi

    if [[ -z "$qs" ]]; then
        return 0
    fi

    cat <<EOF
## Quick Start
<!-- provenance: ${provenance} -->
${qs}
EOF
}

# =============================================================================
# Provenance Tagging (Task 1.4 / SDD 3.1.4)
# =============================================================================

tag_provenance() {
    local tier="$1"
    local section="${2:-}"

    # Exceptions: always OPERATIONAL
    case "$section" in
        ecosystem|quick_start)
            echo "OPERATIONAL"
            return 0
            ;;
    esac

    case "$tier" in
        1) echo "CODE-FACTUAL" ;;
        2) echo "DERIVED" ;;
        3) echo "OPERATIONAL" ;;
        *) echo "OPERATIONAL" ;;
    esac
}

# =============================================================================
# Word Budget Enforcement (SDD 3.1.6)
# =============================================================================

head_by_words() {
    local target="$1"
    local count=0
    while IFS= read -r line; do
        local line_words
        line_words=$(echo "$line" | wc -w | tr -d ' ')
        count=$((count + line_words))
        echo "$line"
        if (( count >= target )); then
            break
        fi
    done
}

enforce_word_budget() {
    local section="$1"
    local content="$2"

    local budget="${WORD_BUDGETS[$section]:-800}"
    local word_count
    word_count=$(echo "$content" | wc -w | tr -d ' ')

    if (( word_count > budget )); then
        echo "$content" | head_by_words "$budget"
        log_warn "$section: truncated from $word_count to ~$budget words"
    else
        echo "$content"
    fi
}

enforce_total_budget() {
    local document="$1"
    local total_words
    total_words=$(echo "$document" | wc -w | tr -d ' ')

    if (( total_words <= TOTAL_BUDGET )); then
        echo "$document"
        return
    fi

    log_warn "Total word count $total_words exceeds budget $TOTAL_BUDGET — truncating low-priority sections"

    # Map section keys to markdown headers for extraction
    declare -A SECTION_HEADER_MAP=(
        [capabilities]="## Key Capabilities"
        [architecture]="## Architecture"
        [interfaces]="## Interfaces"
        [module_map]="## Module Map"
        [ecosystem]="## Ecosystem"
        [limitations]="## Limitations"
        [quick_start]="## Quick Start"
    )

    local result="$document"
    for section in "${TRUNCATION_PRIORITY[@]}"; do
        total_words=$(echo "$result" | wc -w | tr -d ' ')
        if (( total_words <= TOTAL_BUDGET )); then
            break
        fi

        local header="${SECTION_HEADER_MAP[$section]:-}"
        [[ -z "$header" ]] && continue

        local budget="${WORD_BUDGETS[$section]:-200}"
        local reduced_budget=$((budget / 2))
        (( reduced_budget < 20 )) && reduced_budget=20

        # Extract section content between this header and the next ## or ground-truth-meta
        local section_content
        section_content=$(echo "$result" | awk -v hdr="$header" '
            BEGIN { in_section=0 }
            $0 == hdr { in_section=1; print; next }
            in_section && (/^## / || /^<!-- ground-truth-meta/) { exit }
            in_section { print }
        ' 2>/dev/null) || true

        if [[ -n "$section_content" ]]; then
            local truncated
            truncated=$(echo "$section_content" | head_by_words "$reduced_budget")

            # Only replace if we actually reduced content
            if [[ "$truncated" != "$section_content" ]]; then
                # Build replacement: header + provenance + truncated body
                local header_line provenance_line body_lines
                header_line=$(echo "$section_content" | head -1)
                provenance_line=$(echo "$section_content" | grep "<!-- provenance:" 2>/dev/null | head -1) || true
                body_lines=$(echo "$truncated" | tail -n +2)
                if [[ -n "$provenance_line" ]]; then
                    body_lines=$(echo "$truncated" | grep -v "<!-- provenance:" 2>/dev/null | tail -n +2) || true
                fi

                local replacement="${header_line}
${provenance_line}
${body_lines}"

                # Use awk for safe multi-line replacement
                result=$(echo "$result" | awk -v hdr="$header" -v repl="$replacement" '
                    BEGIN { in_section=0; printed=0 }
                    /^## / || /^<!-- ground-truth-meta/ {
                        if (in_section && !printed) { printf "%s\n", repl; printed=1 }
                        in_section=0
                    }
                    $0 == hdr { in_section=1; next }
                    !in_section { print; next }
                    END { if (in_section && !printed) printf "%s\n", repl }
                ')

                log_warn "Reduced $section from $(echo "$section_content" | wc -w | tr -d ' ') to ~$reduced_budget words"
            fi
        fi
    done
    echo "$result"
}

# =============================================================================
# Manual Section Preservation (SDD 3.1.5)
# =============================================================================

preserve_manual_sections() {
    local existing="$1"
    local generated="$2"

    if [[ ! -f "$existing" ]]; then
        echo "$generated"
        return
    fi

    local result="$generated"

    for section in "${CANONICAL_ORDER[@]}"; do
        local manual_block
        manual_block=$(sed -n "/<!-- manual-start:${section} -->/,/<!-- manual-end:${section} -->/p" \
            "$existing" 2>/dev/null) || true

        if [[ -n "$manual_block" ]]; then
            # Append manual block at end of document if section exists
            if echo "$result" | grep -q "<!-- provenance:.*-->"; then
                result="${result}

${manual_block}"
            fi
            log_info "Preserved manual block for section: $section"
        fi
    done

    echo "$result"
}

# =============================================================================
# Security Redaction (SDD 3.1.8)
# =============================================================================

redact_content() {
    local content="$1"

    # Apply redaction patterns
    for pattern in "${REDACTION_PATTERNS[@]}"; do
        content=$(echo "$content" | sed -E "s/${pattern}/[REDACTED]/g" 2>/dev/null) || true
    done

    # Post-redaction safety check: ensure full-pattern secrets don't remain
    # Uses the same patterns as redaction (not just prefixes) to avoid false positives
    local leaked=false
    for pattern in "${REDACTION_PATTERNS[@]}"; do
        if echo "$content" | grep -v 'sha256:' | grep -v 'head_sha:' | grep -v 'generator:' | \
           grep -v 'data:image/' | grep -v '\[REDACTED\]' | \
           grep -qE "$pattern" 2>/dev/null; then
            log_error "Post-redaction safety check failed: pattern '$pattern' still present"
            leaked=true
        fi
    done

    if [[ "$leaked" == "true" ]]; then
        log_error "BLOCKING: Secret pattern found after redaction — aborting"
        return 1
    fi

    echo "$content"
}

# =============================================================================
# Checksum Generation (SDD 3.1.7)
# =============================================================================

extract_section_content() {
    local document="$1"
    local section="$2"

    local header=""
    case "$section" in
        agent_context) header="AGENT-CONTEXT" ;;
        header) header="^# " ;;
        capabilities) header="## Key Capabilities" ;;
        architecture) header="## Architecture" ;;
        interfaces) header="## Interfaces" ;;
        module_map) header="## Module Map" ;;
        ecosystem) header="## Ecosystem" ;;
        limitations) header="## Known Limitations" ;;
        quick_start) header="## Quick Start" ;;
    esac

    if [[ "$section" == "agent_context" ]]; then
        echo "$document" | sed -n '/<!-- AGENT-CONTEXT/,/-->/p'
    else
        echo "$document" | awk -v hdr="$header" '
            BEGIN { in_section=0 }
            $0 ~ hdr { in_section=1; print; next }
            in_section && (/^## / || /^<!-- ground-truth-meta/) { exit }
            in_section { print }
        '
    fi
}

generate_ground_truth_meta() {
    local document="$1"
    local head_sha
    head_sha=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    local generated_at
    generated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local checksums=""
    for section in agent_context capabilities architecture interfaces \
                   module_map ecosystem limitations quick_start; do
        local content
        content=$(extract_section_content "$document" "$section")
        if [[ -n "$content" ]]; then
            local hash
            hash=$(printf '%s' "$content" | sha256sum | awk '{print $1}')
            checksums="${checksums}
  ${section}: ${hash}"
        fi
    done

    cat <<EOF
<!-- ground-truth-meta
head_sha: ${head_sha}
generated_at: ${generated_at}
generator: butterfreezone-gen v${SCRIPT_VERSION}
sections:${checksums}
-->
EOF
}

# =============================================================================
# Staleness Detection (SDD 3.1.10)
# =============================================================================

needs_regeneration() {
    local output="$1"

    # No existing file → needs generation
    [[ ! -f "$output" ]] && return 0

    # Compare HEAD SHA
    local current_sha
    current_sha=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    local meta_sha
    meta_sha=$(sed -n '/<!-- ground-truth-meta/,/-->/p' "$output" 2>/dev/null \
        | grep "head_sha:" | awk '{print $2}') || true

    [[ "$current_sha" != "$meta_sha" ]] && return 0

    # Compare config mtime
    if [[ -f "$CONFIG_FILE" ]]; then
        local config_mtime output_mtime
        config_mtime=$(stat -c %Y "$CONFIG_FILE" 2>/dev/null || echo 0)
        output_mtime=$(stat -c %Y "$output" 2>/dev/null || echo 0)
        [[ "$config_mtime" -gt "$output_mtime" ]] && return 0
    fi

    # Up to date
    return 1
}

# =============================================================================
# Atomic Write (SDD 3.1.9)
# =============================================================================

atomic_write() {
    local content="$1"
    local output="$2"
    local tmp="${output}.tmp"

    printf '%s\n' "$content" > "$tmp"

    if [[ ! -s "$tmp" ]]; then
        log_error "Generated empty file — aborting write"
        rm -f "$tmp"
        return 1
    fi

    mv "$tmp" "$output"
    log_info "Wrote $output ($(wc -w < "$output" | tr -d ' ') words)"
}

# =============================================================================
# JSON Metadata (SDD 4.2)
# =============================================================================

emit_metadata() {
    local tier="$1"
    local head_sha
    head_sha=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    local generated_at
    generated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local word_count=0
    [[ -f "$OUTPUT" ]] && word_count=$(wc -w < "$OUTPUT" 2>/dev/null | tr -d ' ')

    cat <<EOF
{
  "status": "ok",
  "generator": "butterfreezone-gen",
  "version": "${SCRIPT_VERSION}",
  "tier": ${tier},
  "head_sha": "${head_sha}",
  "generated_at": "${generated_at}",
  "output": "${OUTPUT}",
  "word_count": ${word_count},
  "sections": [],
  "errors": []
}
EOF
}

# =============================================================================
# Document Assembly
# =============================================================================

assemble_sections() {
    local document=""

    for section_content in "$@"; do
        [[ -z "$section_content" ]] && continue
        document="${document}${section_content}

"
    done

    echo "$document"
}

# =============================================================================
# Main (SDD 3.1.17)
# =============================================================================

main() {
    parse_args "$@"
    load_config

    # Concurrency lock (skip for dry-run)
    if [[ "$DRY_RUN" != "true" ]]; then
        acquire_lock
    fi

    # Check staleness
    if [[ -f "$OUTPUT" ]] && ! needs_regeneration "$OUTPUT"; then
        log_info "BUTTERFREEZONE.md is up-to-date (HEAD SHA matches)"
        if [[ "$JSON_OUTPUT" == "true" ]]; then
            cat <<UPTODATE >&2
{"status": "ok", "generator": "butterfreezone-gen", "version": "${SCRIPT_VERSION}", "tier": 0, "output": "${OUTPUT}", "word_count": $(wc -w < "$OUTPUT" | tr -d ' '), "sections": [], "errors": [], "up_to_date": true}
UPTODATE
        fi
        exit 0
    fi

    local tier
    tier=$(detect_input_tier)
    log_info "Input tier: $tier"

    # Build sections
    local agent_ctx="" header="" caps="" arch="" ifaces="" modmap="" eco="" limits="" qs=""

    agent_ctx=$(extract_agent_context "$tier")
    header=$(extract_header "$tier")

    if [[ "$tier" -ne 3 ]]; then
        caps=$(run_extractor "capabilities" "$tier")
        arch=$(run_extractor "architecture" "$tier")
        ifaces=$(run_extractor "interfaces" "$tier")
    fi

    modmap=$(run_extractor "module_map" "$tier")

    if [[ "$tier" -ne 3 ]]; then
        eco=$(run_extractor "ecosystem" "$tier")
        limits=$(run_extractor "limitations" "$tier")
        qs=$(run_extractor "quick_start" "$tier")
    fi

    # Apply per-section word budgets
    [[ -n "$caps" ]] && caps=$(enforce_word_budget "capabilities" "$caps")
    [[ -n "$arch" ]] && arch=$(enforce_word_budget "architecture" "$arch")
    [[ -n "$ifaces" ]] && ifaces=$(enforce_word_budget "interfaces" "$ifaces")
    [[ -n "$modmap" ]] && modmap=$(enforce_word_budget "module_map" "$modmap")
    [[ -n "$eco" ]] && eco=$(enforce_word_budget "ecosystem" "$eco")
    [[ -n "$limits" ]] && limits=$(enforce_word_budget "limitations" "$limits")
    [[ -n "$qs" ]] && qs=$(enforce_word_budget "quick_start" "$qs")

    # Assemble document
    local document
    document=$(assemble_sections "$agent_ctx" "$header" "$caps" "$arch" "$ifaces" "$modmap" "$eco" "$limits" "$qs")

    # Merge with existing manual sections
    document=$(preserve_manual_sections "$OUTPUT" "$document")

    # Enforce total budget
    document=$(enforce_total_budget "$document")

    # Security redaction
    document=$(redact_content "$document") || {
        log_error "Security redaction blocked output — secrets detected"
        exit 1
    }

    # Generate ground-truth-meta
    local meta
    meta=$(generate_ground_truth_meta "$document")
    document="${document}
${meta}"

    # Output
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "$document"
    else
        atomic_write "$document" "$OUTPUT"
    fi

    # JSON metadata
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        emit_metadata "$tier" >&2
    fi

    # Exit code 3 for Tier 3 bootstrap
    if [[ "$tier" -eq 3 ]]; then
        exit 3
    fi

    exit 0
}

main "$@"
