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
    "verification"
    "agents"
    "ecosystem"
    "culture"
    "limitations"
    "quick_start"
)

# Word budgets (SDD 3.1.6, FR-5: increased for narrative prose)
declare -A WORD_BUDGETS=(
    [agent_context]=80
    [header]=200
    [capabilities]=800
    [architecture]=600
    [interfaces]=600
    [module_map]=400
    [ecosystem]=200
    [limitations]=200
    [quick_start]=300
)
TOTAL_BUDGET=3400

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
    if command -v flock &>/dev/null; then
        # Linux: flock-based non-blocking lock
        exec 200>"$LOCK_FILE"
        if ! flock -n 200; then
            log_warn "Another butterfreezone-gen process is running — skipping"
            exit 0
        fi
    else
        # macOS/POSIX: mkdir-based non-blocking lock
        LOCK_DIR="${LOCK_FILE}.d"
        if ! mkdir "$LOCK_DIR" 2>/dev/null; then
            log_warn "Another butterfreezone-gen process is running — skipping"
            exit 0
        fi
        echo $$ > "$LOCK_DIR/pid"
    fi
}

release_lock() {
    if [[ -n "${LOCK_DIR:-}" ]]; then
        # mkdir-based lock cleanup
        rm -rf "$LOCK_DIR" 2>/dev/null || true
    elif [[ -n "${LOCK_FILE:-}" ]]; then
        # flock-based lock cleanup
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
# Helper Functions (cycle-017: SDD §2.1, §2.3)
# =============================================================================

# Extract doc comment preceding a symbol at a given line (SDD §2.1.1)
extract_doc_comment() {
    local file="$1"
    local line_num="$2"
    local comment=""

    local start=$((line_num - 1))
    [[ "$start" -lt 1 ]] && return 0

    case "$file" in
        *.ts|*.js|*.tsx|*.jsx)
            # JSDoc: /** ... */ block ending on line before function
            comment=$(sed -n "1,${start}p" "$file" 2>/dev/null | tac 2>/dev/null | \
                sed -n '/^[[:space:]]*\*\//,/^[[:space:]]*\/\*\*/p' 2>/dev/null | tac 2>/dev/null | \
                sed 's/^[[:space:]]*\*\/.*//;s/^[[:space:]]*\/\*\*.*//;s/^[[:space:]]*\* *//;/^$/d' | \
                head -3 | tr '\n' ' ') || true
            ;;
        *.py)
            # Python: docstring on the line(s) after def/class (triple-double or triple-single)
            comment=$(sed -n "$((line_num+1)),$((line_num+5))p" "$file" 2>/dev/null | \
                sed -n '/"""\|'"'''"'/,/"""\|'"'''"'/p' | \
                sed "s/\"\"\"//g;s/'''//g;s/^[[:space:]]*//" | \
                tr '\n' ' ' | sed 's/^ *//;s/ *$//') || true
            ;;
        *.rs)
            # Rust: /// doc comments above pub item
            comment=$(sed -n "1,${start}p" "$file" 2>/dev/null | tac 2>/dev/null | \
                awk '/^[[:space:]]*\/\/\//{gsub(/^[[:space:]]*\/\/\/[[:space:]]?/,""); a=$0 (a?" "a:""); next} {exit} END{print a}') || true
            ;;
        *.sh)
            # Shell: # comments above function (not shebang)
            comment=$(sed -n "1,${start}p" "$file" 2>/dev/null | tac 2>/dev/null | \
                awk '/^[[:space:]]*#[^!]/{gsub(/^[[:space:]]*#[[:space:]]?/,""); a=$0 (a?" "a:""); next} {exit} END{print a}') || true
            ;;
        *.go)
            # Go: // comments above func
            comment=$(sed -n "1,${start}p" "$file" 2>/dev/null | tac 2>/dev/null | \
                awk '/^[[:space:]]*\/\//{gsub(/^[[:space:]]*\/\/[[:space:]]?/,""); a=$0 (a?" "a:""); next} {exit} END{print a}') || true
            ;;
    esac

    # Return first sentence only, max 120 chars
    echo "$comment" | sed 's/\. .*/./;s/^ *//;s/ *$//' | head -c 120
}

# Synthesize description from function name (SDD §2.1.2)
describe_from_name() {
    local name="$1"
    echo "$name" | \
        sed 's/_/ /g' | \
        sed 's/\([a-z]\)\([A-Z]\)/\1 \2/g' | \
        tr '[:upper:]' '[:lower:]' | \
        sed 's/^./\U&/' | \
        head -c 80
}

# Multi-strategy project description extraction (SDD §2.3.1)
# Shared by extract_header() and extract_agent_context()
# Note: Truncation assumes prose input (contains spaces). URLs or code paths
# without spaces would pass through untrimmed. This is acceptable for README
# paragraph extraction but should be reconsidered if reused for other content.
extract_project_description() {
    local desc=""

    # Strategy 1: package.json description
    if [[ -f "package.json" ]] && command -v jq &>/dev/null; then
        desc=$(jq -r '.description // ""' package.json 2>/dev/null) || true
    fi

    # Strategy 2: README.md first real paragraph (skip title, badges, quotes, HTML comments)
    if [[ -z "$desc" || "$desc" == "null" ]] && [[ -f "README.md" ]]; then
        desc=$(awk '
            /^#/{next}
            /^\[!\[/{next}
            /^>/{next}
            /<!--/{skip=1; next} /-->/{skip=0; next}
            skip{next}
            /^[[:space:]]*$/{if(found) exit; next}
            {found=1; printf "%s ", $0}
        ' README.md 2>/dev/null | sed 's/ *$//' | cut -c1-220 | sed 's/ [^ ]*$//' | \
            awk '{s=$0; if(length(s)>=80 && match(s,/\. [^.]*$/)) s=substr(s,1,RSTART); print s}') || true
    fi

    # Strategy 3: README "What Is This?" or "Overview" section
    if [[ -z "$desc" || "$desc" == "null" ]] && [[ -f "README.md" ]]; then
        desc=$(awk '
            /^##[[:space:]]+(What Is This|Overview|About|Introduction)/{f=1; next}
            f && /^##/{exit}
            f && /^[[:space:]]*$/{next}
            f {print; exit}
        ' README.md 2>/dev/null | cut -c1-220 | sed 's/ [^ ]*$//' | \
            awk '{s=$0; if(length(s)>=80 && match(s,/\. [^.]*$/)) s=substr(s,1,RSTART); print s}') || true
    fi

    # Strategy 4: Existing BUTTERFREEZONE AGENT-CONTEXT purpose
    if [[ -z "$desc" || "$desc" == "null" ]] && [[ -f "BUTTERFREEZONE.md" ]]; then
        desc=$(sed -n '/<!-- AGENT-CONTEXT/,/-->/p' BUTTERFREEZONE.md 2>/dev/null | \
            grep '^purpose:' | sed 's/^purpose: *//' | head -1) || true
        [[ "$desc" == "No description available" ]] && desc=""
    fi

    # Strategy 5: Synthesize from project structure
    if [[ -z "$desc" || "$desc" == "null" ]]; then
        local name ptype dir_count
        name=$(basename "$(pwd)")
        ptype="project"
        [[ -d ".claude/skills" ]] && ptype="framework"
        [[ -f "package.json" ]] && ptype="Node.js project"
        [[ -f "Cargo.toml" ]] && ptype="Rust project"
        [[ -f "pyproject.toml" ]] && ptype="Python project"
        dir_count=$(find . -maxdepth 1 -type d -not -path "." -not -path "*/\.*" 2>/dev/null | wc -l | tr -d ' ')
        desc="${name} is a ${ptype} with ${dir_count} modules."
    fi

    echo "$desc"
}

# Detect architectural pattern from directory structure (SDD §2.2.1)
detect_architecture_pattern() {
    local pattern="modular"

    if [[ -d ".claude/skills" ]] || [[ -d ".claude/scripts" ]]; then
        pattern="three-zone framework"
    elif [[ -d "src/controllers" ]] || [[ -d "src/routes" ]] || [[ -d "app/controllers" ]]; then
        pattern="layered MVC"
    elif [[ -d "stages" ]] || [[ -d "pipeline" ]] || [[ -d "steps" ]]; then
        pattern="pipeline"
    elif [[ -d "plugins" ]] || [[ -d "extensions" ]]; then
        pattern="plugin-based"
    elif [[ -d "packages" ]] || [[ -d "apps" ]]; then
        pattern="monorepo"
    fi

    echo "$pattern"
}

# Infer module purpose from directory (SDD §2.5.1)
infer_module_purpose() {
    local dir="$1"
    local dname
    dname=$(basename "$dir")
    local purpose=""

    # Strategy 1: README.md in the directory
    if [[ -f "${dir}/README.md" ]]; then
        purpose=$(awk '
            /^#/{next}
            /^[[:space:]]*$/{next}
            {print; exit}
        ' "${dir}/README.md" 2>/dev/null | cut -c1-140 | sed 's/ [^ ]*$//') || true
    fi

    # Strategy 2: Directory name convention map
    if [[ -z "$purpose" ]]; then
        case "$dname" in
            src|lib|app) purpose="Source code" ;;
            tests|test|spec|__tests__) purpose="Test suites" ;;
            docs|doc|documentation) purpose="Documentation" ;;
            scripts) purpose="Utility scripts" ;;
            grimoires) purpose="Loa state and memory files" ;;
            evals) purpose="Evaluation suites and benchmarks" ;;
            skills) purpose="Specialized agent skills" ;;
            .github) purpose="GitHub workflows and CI/CD" ;;
            fixtures|testdata) purpose="Test fixtures and data" ;;
            config|configs) purpose="Configuration files" ;;
            public|static|assets) purpose="Static assets" ;;
            migrations) purpose="Database migrations" ;;
            types|typings) purpose="Type definitions" ;;
            utils|helpers|common) purpose="Shared utilities" ;;
            api) purpose="API endpoints" ;;
            models) purpose="Data models" ;;
            services) purpose="Business logic services" ;;
            middleware) purpose="Request middleware" ;;
            hooks) purpose="Lifecycle hooks" ;;
            components) purpose="UI components" ;;
            pages|views) purpose="Page/view templates" ;;
            billing|payments|pay) purpose="Billing and payment processing" ;;
            ledger|credits|wallet) purpose="Financial ledger and credit management" ;;
            auth|authentication|oauth) purpose="Authentication and authorization" ;;
            themes|sietch) purpose="Theme-based runtime configuration" ;;
            gateway|gatekeeper) purpose="API gateway and access control" ;;
            webhooks) purpose="Webhook handlers and event processing" ;;
            subscriptions|plans|tiers) purpose="Subscription management" ;;
            crypto|web3|blockchain) purpose="Blockchain and cryptocurrency integration" ;;
            discord|telegram|slack) purpose="Chat platform integration" ;;
            sessions|session) purpose="Session management" ;;
            jobs|workers|queue) purpose="Background job processing" ;;
            cache|redis) purpose="Caching layer" ;;
            monitoring|metrics|telemetry) purpose="Observability and monitoring" ;;
            deploy|infra|terraform) purpose="Infrastructure and deployment" ;;
            *) ;;
        esac
    fi

    # Strategy 3: Infer from dominant file types
    if [[ -z "$purpose" ]]; then
        local test_files md_files sh_files
        test_files=$(find "$dir" -maxdepth 2 \( -name "*.test.*" -o -name "*.spec.*" \) 2>/dev/null | wc -l | tr -d ' ')
        md_files=$(find "$dir" -maxdepth 2 -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
        sh_files=$(find "$dir" -maxdepth 2 -name "*.sh" 2>/dev/null | wc -l | tr -d ' ')

        if (( test_files > 3 )); then
            purpose="Test suites"
        elif (( md_files > 3 )); then
            purpose="Documentation"
        elif (( sh_files > 3 )); then
            purpose="Shell scripts and utilities"
        fi
    fi

    # Strategy 4: Capitalize directory name as last resort
    if [[ -z "$purpose" ]]; then
        purpose=$(echo "$dname" | sed 's/[-_]/ /g' | sed 's/^./\U&/')
    fi

    echo "$purpose"
}

# Compute trust level tag for AGENT-CONTEXT (L1-L4)
# Returns machine-readable tag like "L2-verified" or "grounded" as fallback
compute_trust_level_tag() {
    local test_count=0 has_ci="false" has_property="false" has_formal="false"

    # Count test files
    test_count=$(find . -maxdepth 4 \( -name "*.test.*" -o -name "*.spec.*" -o -name "test_*" -o -name "*_test.*" \) 2>/dev/null | wc -l) || test_count=0

    # CI detection
    [[ -d ".github/workflows" ]] && has_ci="true"
    [[ -f ".gitlab-ci.yml" ]] && has_ci="true"
    [[ -f "Jenkinsfile" ]] && has_ci="true"

    # Property-based test detection (check all 5 dep files)
    for dep_file in package.json requirements.txt Cargo.toml go.mod pyproject.toml; do
        if [[ -f "$dep_file" ]] && grep -qiE 'fast-check|hypothesis|proptest|quickcheck|jqwik' "$dep_file" 2>/dev/null; then
            has_property="true"; break
        fi
    done

    # Formal verification detection — strictly formal proofs, NOT property tests
    for dep_file in package.json requirements.txt Cargo.toml go.mod pyproject.toml; do
        if [[ -f "$dep_file" ]] && grep -qiE 'safety_properties|liveness_properties|temporal_logic|model_check|formal_verification' "$dep_file" 2>/dev/null; then
            has_formal="true"; break
        fi
    done

    local level=0
    (( test_count > 0 )) && level=1
    [[ $level -ge 1 && "$has_ci" == "true" ]] && level=2
    [[ $level -ge 2 && "$has_property" == "true" ]] && level=3
    [[ $level -ge 3 && "$has_formal" == "true" ]] && level=4

    case $level in
        1) echo "L1-tests-present" ;;
        2) echo "L2-verified" ;;
        3) echo "L3-hardened" ;;
        4) echo "L4-proven" ;;
        *) echo "grounded" ;;
    esac
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

    # Installation mode: detect from .loa-version.json (Task 3.4, cycle-035 sprint-3)
    local install_mode="unknown"
    if [[ -f ".loa-version.json" ]] && command -v jq &>/dev/null; then
        install_mode=$(jq -r '.installation_mode // "unknown"' .loa-version.json 2>/dev/null) || true
    fi
    [[ -z "$install_mode" || "$install_mode" == "null" ]] && install_mode="unknown"

    # Purpose: use shared multi-strategy extraction (SDD §2.6.2)
    purpose=$(extract_project_description)

    # Key files
    local kf=()
    [[ -f "CLAUDE.md" ]] && kf+=("CLAUDE.md")
    [[ -f ".claude/loa/CLAUDE.loa.md" ]] && kf+=(".claude/loa/CLAUDE.loa.md")
    [[ -f ".loa.config.yaml" ]] && kf+=(".loa.config.yaml")
    [[ -d ".claude/scripts" ]] && kf+=(".claude/scripts/")
    [[ -d ".claude/skills" ]] && kf+=(".claude/skills/")
    [[ -f "package.json" ]] && kf+=("package.json")
    [[ -f "Cargo.toml" ]] && kf+=("Cargo.toml")
    [[ -f "pyproject.toml" ]] && kf+=("pyproject.toml")
    [[ -f "go.mod" ]] && kf+=("go.mod")
    key_files=$(printf '%s' "[$(IFS=,; echo "${kf[*]}" | sed 's/,/, /g')]")

    # Interfaces: structured by provenance with top-5 per group (SDD cycle-030 §3.4)
    load_classification_cache
    local core_ifaces=() project_ifaces=()
    local has_construct_iface_groups=false
    declare -A construct_iface_groups=()

    if [[ -d ".claude/skills" ]]; then
        while IFS= read -r d; do
            [[ -z "$d" ]] && continue
            local sname
            sname=$(basename "$d")
            local prov
            prov=$(classify_skill_provenance "$sname")
            case "$prov" in
                core)
                    [[ ${#core_ifaces[@]} -lt 5 ]] && core_ifaces+=("/${sname}")
                    ;;
                construct:*)
                    local pack="${prov#construct:}"
                    has_construct_iface_groups=true
                    local current="${construct_iface_groups[$pack]:-}"
                    local count=0
                    if [[ -n "$current" ]]; then
                        count=$(echo "$current" | tr ',' '\n' | grep -c . 2>/dev/null) || count=0
                    fi
                    [[ $count -lt 5 ]] && construct_iface_groups[$pack]="${current:+${current}, }/${sname}"
                    ;;
                project)
                    [[ ${#project_ifaces[@]} -lt 5 ]] && project_ifaces+=("/${sname}")
                    ;;
            esac
        done < <(find .claude/skills -maxdepth 1 -type d 2>/dev/null | sort | tail -n +2)
    fi

    # Format structured interfaces output
    interfaces="interfaces:"
    if [[ ${#core_ifaces[@]} -gt 0 ]]; then
        interfaces="${interfaces}"$'\n'"  core: [$(IFS=,; echo "${core_ifaces[*]}" | sed 's/,/, /g')]"
    fi
    if [[ "$has_construct_iface_groups" == "true" ]]; then
        interfaces="${interfaces}"$'\n'"  constructs:"
        for pack in $(echo "${!construct_iface_groups[@]}" | tr ' ' '\n' | sort); do
            interfaces="${interfaces}"$'\n'"    ${pack}: [${construct_iface_groups[$pack]}]"
        done
    fi
    if [[ ${#project_ifaces[@]} -gt 0 ]]; then
        interfaces="${interfaces}"$'\n'"  project: [$(IFS=,; echo "${project_ifaces[*]}" | sed 's/,/, /g')]"
    fi

    # Dependencies: runtime requirements
    local dep_list=()
    command -v git &>/dev/null && dep_list+=("git")
    command -v jq &>/dev/null && dep_list+=("jq")
    command -v yq &>/dev/null && dep_list+=("yq")
    [[ -f "package.json" ]] && dep_list+=("node")
    [[ -f "Cargo.toml" ]] && dep_list+=("cargo")
    [[ -f "pyproject.toml" ]] && dep_list+=("python")
    deps=$(printf '%s' "[$(IFS=,; echo "${dep_list[*]}" | sed 's/,/, /g')]")

    # Ecosystem: cross-repo discovery graph from config (SDD cycle-017)
    local ecosystem_block=""
    if [[ -f ".loa.config.yaml" ]] && command -v yq &>/dev/null; then
        local eco_count
        eco_count=$(yq '.butterfreezone.ecosystem | length // 0' .loa.config.yaml 2>/dev/null) || eco_count=0
        if [[ "$eco_count" -gt 0 ]]; then
            ecosystem_block=$'\n'"ecosystem:"
            local i
            for ((i=0; i<eco_count; i++)); do
                local e_repo e_role e_iface e_proto
                e_repo=$(yq ".butterfreezone.ecosystem[$i].repo // \"\"" .loa.config.yaml 2>/dev/null) || true
                e_role=$(yq ".butterfreezone.ecosystem[$i].role // \"\"" .loa.config.yaml 2>/dev/null) || true
                e_iface=$(yq ".butterfreezone.ecosystem[$i].interface // \"\"" .loa.config.yaml 2>/dev/null) || true
                e_proto=$(yq ".butterfreezone.ecosystem[$i].protocol // \"\"" .loa.config.yaml 2>/dev/null) || true
                if [[ -n "$e_repo" && -n "$e_role" ]]; then
                    ecosystem_block="${ecosystem_block}"$'\n'"  - repo: ${e_repo}"
                    ecosystem_block="${ecosystem_block}"$'\n'"    role: ${e_role}"
                    [[ -n "$e_iface" ]] && ecosystem_block="${ecosystem_block}"$'\n'"    interface: ${e_iface}"
                    [[ -n "$e_proto" ]] && ecosystem_block="${ecosystem_block}"$'\n'"    protocol: ${e_proto}"
                fi
            done
        fi
    fi

    # Capability requirements: inferred from SKILL.md files (SDD cycle-017)
    # Section IX fix: negative-keyword filtering to reduce false positives
    # Sprint-111: scoped capabilities with Three-Zone awareness
    local cap_req_block=""
    if [[ -d ".claude/skills" ]]; then
        local -A cap_hits=()
        # Zone-scoped counters: track which zones each capability touches
        local -A zone_state_write=() zone_app_write=()
        local skill_dirs
        skill_dirs=$(find .claude/skills -maxdepth 1 -type d 2>/dev/null | sort | tail -n +2 | head -10)

        # Negative context patterns — lines containing these are excluded from capability matching
        local neg_pattern="(not|never|without|no |disable|readonly|read-only|doesn.t|won.t|cannot|don.t)"
        # Zone detection patterns (Three-Zone Model)
        local state_pattern="grimoire|sprint\.md|prd\.md|sdd\.md|\.run/|\.beads|ledger|NOTES\.md|a2a/"
        local app_pattern="src/|lib/|app/|application code|source code|implementation"

        while IFS= read -r sd; do
            [[ -z "$sd" ]] && continue
            local sm="${sd}/SKILL.md"
            [[ ! -f "$sm" ]] && continue
            local sc
            sc=$(cat "$sm" 2>/dev/null) || continue

            # Filter: only count lines that match keyword AND lack negative context
            local positive_lines
            positive_lines=$(grep -iE 'read|codebase|source file' <<< "$sc" 2>/dev/null | grep -cviE "$neg_pattern" 2>/dev/null) || positive_lines=0
            (( positive_lines > 0 )) && cap_hits[fs_read]=$(( ${cap_hits[fs_read]:-0} + 1 ))

            positive_lines=$(grep -iE 'write|create|generate' <<< "$sc" 2>/dev/null | grep -cviE "$neg_pattern" 2>/dev/null) || positive_lines=0
            if (( positive_lines > 0 )); then
                cap_hits[fs_write]=$(( ${cap_hits[fs_write]:-0} + 1 ))
                # Detect zone scope for writes
                if grep -qiE "$state_pattern" <<< "$sc" 2>/dev/null; then
                    zone_state_write[$(basename "$sd")]=1
                fi
                if grep -qiE "$app_pattern" <<< "$sc" 2>/dev/null; then
                    zone_app_write[$(basename "$sd")]=1
                fi
            fi

            positive_lines=$(grep -iE '\bgit\b|diff|log|branch' <<< "$sc" 2>/dev/null | grep -cviE "$neg_pattern" 2>/dev/null) || positive_lines=0
            (( positive_lines > 0 )) && cap_hits[git]=$(( ${cap_hits[git]:-0} + 1 ))

            positive_lines=$(grep -iE 'commit|push' <<< "$sc" 2>/dev/null | grep -cviE "$neg_pattern" 2>/dev/null) || positive_lines=0
            (( positive_lines > 0 )) && cap_hits[git_write]=$(( ${cap_hits[git_write]:-0} + 1 ))

            positive_lines=$(grep -iE '\bPR\b|issue|gh ' <<< "$sc" 2>/dev/null | grep -cviE "$neg_pattern" 2>/dev/null) || positive_lines=0
            (( positive_lines > 0 )) && cap_hits[gh_api]=$(( ${cap_hits[gh_api]:-0} + 1 ))

            positive_lines=$(grep -iE 'bash|shell|execute|\brun\b' <<< "$sc" 2>/dev/null | grep -cviE "$neg_pattern" 2>/dev/null) || positive_lines=0
            (( positive_lines > 0 )) && cap_hits[shell]=$(( ${cap_hits[shell]:-0} + 1 ))
        done <<< "$skill_dirs"

        local cap_entries=""
        (( ${cap_hits[fs_read]:-0} >= 2 )) && cap_entries="${cap_entries}"$'\n'"  - filesystem: read"

        # Scoped filesystem writes: emit per-zone when detectable
        if (( ${cap_hits[fs_write]:-0} >= 2 )); then
            local state_count=${#zone_state_write[@]}
            local app_count=${#zone_app_write[@]}
            if (( state_count >= 2 && app_count >= 2 )); then
                cap_entries="${cap_entries}"$'\n'"  - filesystem: write (scope: state)"
                cap_entries="${cap_entries}"$'\n'"  - filesystem: write (scope: app)"
            elif (( state_count >= 2 )); then
                cap_entries="${cap_entries}"$'\n'"  - filesystem: write (scope: state)"
            elif (( app_count >= 2 )); then
                cap_entries="${cap_entries}"$'\n'"  - filesystem: write (scope: app)"
            else
                cap_entries="${cap_entries}"$'\n'"  - filesystem: write"
            fi
        fi

        if (( ${cap_hits[git_write]:-0} >= 2 )); then
            cap_entries="${cap_entries}"$'\n'"  - git: read_write"
        elif (( ${cap_hits[git]:-0} >= 2 )); then
            cap_entries="${cap_entries}"$'\n'"  - git: read"
        fi
        (( ${cap_hits[shell]:-0} >= 2 )) && cap_entries="${cap_entries}"$'\n'"  - shell: execute"
        (( ${cap_hits[gh_api]:-0} >= 2 )) && cap_entries="${cap_entries}"$'\n'"  - github_api: read_write (scope: external)"

        # Config overrides: suppress false positives, add forced capabilities
        if [[ -f "$CONFIG_FILE" ]] && command -v yq &>/dev/null; then
            local suppress_count
            suppress_count=$(yq '.butterfreezone.capability_overrides.suppress | length // 0' "$CONFIG_FILE" 2>/dev/null) || suppress_count=0
            for ((si=0; si<suppress_count; si++)); do
                local sup
                sup=$(yq ".butterfreezone.capability_overrides.suppress[$si]" "$CONFIG_FILE" 2>/dev/null) || continue
                [[ -n "$sup" && "$sup" != "null" ]] && cap_entries=$(echo "$cap_entries" | grep -Fv "$sup" 2>/dev/null) || true
            done

            local add_count
            add_count=$(yq '.butterfreezone.capability_overrides.add | length // 0' "$CONFIG_FILE" 2>/dev/null) || add_count=0
            for ((ai=0; ai<add_count; ai++)); do
                local add_cap
                add_cap=$(yq ".butterfreezone.capability_overrides.add[$ai]" "$CONFIG_FILE" 2>/dev/null) || continue
                [[ -n "$add_cap" && "$add_cap" != "null" ]] && cap_entries="${cap_entries}"$'\n'"  - ${add_cap}"
            done
        fi

        [[ -n "$cap_entries" ]] && cap_req_block=$'\n'"capability_requirements:${cap_entries}"
    fi

    local trust_tag
    trust_tag=$(compute_trust_level_tag)

    cat <<EOF
<!-- AGENT-CONTEXT
name: ${name}
type: ${type}
purpose: ${purpose}
key_files: ${key_files}
${interfaces}
dependencies: ${deps}${ecosystem_block}${cap_req_block}
version: ${version}
installation_mode: ${install_mode}
trust_level: ${trust_tag}
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

    # Use shared description cascade (SDD §2.3.1)
    local desc=""
    desc=$(extract_project_description)

    local provenance
    provenance=$(tag_provenance "$tier" "header")

    # Build narrative summary (SDD §2.3.3)
    local summary=""
    if [[ "$tier" -le 2 ]]; then
        local lang_count=0
        local langs="" skill_count=0
        [[ -n "$(find . -maxdepth 3 \( -name '*.ts' -o -name '*.js' \) 2>/dev/null | head -1)" ]] && { langs="${langs}TypeScript/JavaScript, "; ((lang_count++)); }
        [[ -n "$(find . -maxdepth 3 -name '*.py' 2>/dev/null | head -1)" ]] && { langs="${langs}Python, "; ((lang_count++)); }
        [[ -n "$(find . -maxdepth 3 -name '*.rs' 2>/dev/null | head -1)" ]] && { langs="${langs}Rust, "; ((lang_count++)); }
        [[ -n "$(find . -maxdepth 3 -name '*.go' 2>/dev/null | head -1)" ]] && { langs="${langs}Go, "; ((lang_count++)); }
        [[ -n "$(find . -maxdepth 3 -name '*.sh' 2>/dev/null | head -1)" ]] && { langs="${langs}Shell, "; ((lang_count++)); }
        langs=$(echo "$langs" | sed 's/, $//')

        # Count skills for framework projects
        if [[ -d ".claude/skills" ]]; then
            skill_count=$(find .claude/skills -maxdepth 1 -type d 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
        fi

        if [[ "$skill_count" -gt 0 ]]; then
            summary="The framework provides ${skill_count} specialized skills"
            [[ -n "$langs" ]] && summary="${summary}, built with ${langs}"
            summary="${summary}."
        elif [[ -n "$langs" ]]; then
            summary="Built with ${langs}."
            if [[ -f "package.json" ]] && command -v jq &>/dev/null; then
                local dep_count
                dep_count=$(jq -r '(.dependencies // {}) | keys | length' package.json 2>/dev/null) || dep_count=0
                [[ "$dep_count" -gt 0 ]] && summary="${summary} The project has ${dep_count} direct dependencies."
            fi
        fi
    fi

    cat <<EOF
# ${name}

<!-- provenance: ${provenance} -->
${desc}
$(if [[ -n "$summary" ]]; then echo; echo "$summary"; fi)
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
        # Tier 2: grep-based extraction with rich descriptions (SDD §2.1)
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
            # Build rich capability entries with doc comments (SDD §2.1.1-§2.1.4)
            local raw_entries=""
            raw_entries=$(printf '%b' "$found" | while IFS=: read -r file line content; do
                [[ -z "$content" || -z "$file" || -z "$line" ]] && continue
                local sym
                sym=$(echo "$content" | sed 's/^export //;s/^pub //;s/(.*//;s/ {.*//;s/^function //;s/^const //;s/^class //;s/^def //;s/^fn //;s/^struct //;s/^enum //;s/^trait //;s/^func //' | tr -d ' ' | head -c 60)
                [[ -z "$sym" ]] && continue

                # Extract doc comment or synthesize from name
                local doc_comment=""
                doc_comment=$(extract_doc_comment "$file" "$line")
                local desc="$doc_comment"
                if [[ -z "$desc" ]]; then
                    desc=$(describe_from_name "$sym")
                fi

                # Score: documented=3, undocumented=2 (reuse cached doc_comment)
                local score=2
                [[ -n "$doc_comment" ]] && score=3

                # Get parent directory for grouping
                local parent_dir
                parent_dir=$(dirname "$file" | sed 's|^\./||')

                echo "${score}|${parent_dir}|${sym}|${desc}|${file}:${line}"
            done | sort -t'|' -k1,1rn -k2,2 | head -15)

            if [[ -n "$raw_entries" ]]; then
                # Check if grouping needed (>10 entries)
                local entry_count
                entry_count=$(echo "$raw_entries" | wc -l | tr -d ' ')
                local use_groups=false
                (( entry_count > 10 )) && use_groups=true

                local current_group=""
                caps=$(while IFS='|' read -r score parent sym desc ref; do
                    [[ -z "$sym" ]] && continue

                    if [[ "$use_groups" == "true" && "$parent" != "$current_group" ]]; then
                        current_group="$parent"
                        echo ""
                        echo "### ${parent}"
                        echo ""
                    fi

                    echo "- **${sym}** — ${desc} (\`${ref}\`)"
                done <<< "$raw_entries")
            fi
        fi
    fi

    if [[ -z "$caps" ]]; then
        return 0
    fi

    # Narrative preamble
    local cap_count
    cap_count=$(echo "$caps" | grep -c '^\- \*\*' || echo 0)
    local preamble=""
    if [[ "$cap_count" -gt 0 ]]; then
        preamble="The project exposes ${cap_count} key entry points across its public API surface."
    fi

    cat <<EOF
## Key Capabilities
<!-- provenance: ${provenance} -->
$(if [[ -n "$preamble" ]]; then echo "$preamble"; echo; fi)
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
    local mermaid=""
    local narrative=""

    if [[ "$tier" -eq 1 ]]; then
        local grimoire_dir
        grimoire_dir=$(get_config_value "paths.grimoire" "grimoires/loa")
        if [[ -f "${grimoire_dir}/reality/architecture.md" ]]; then
            arch=$(head -30 "${grimoire_dir}/reality/architecture.md" 2>/dev/null) || true
        fi
    fi

    # Generate Mermaid component diagram from top-level directories
    local top_dirs
    top_dirs=$(find . -maxdepth 1 -type d \
        -not -path "." \
        -not -path "*/\.*" \
        -not -name "node_modules" \
        -not -name "vendor" \
        -not -name "target" \
        -not -name "dist" \
        -not -name "build" \
        -not -name "__pycache__" \
        2>/dev/null | sed 's|^\./||' | sort | head -8) || true

    if [[ -n "$top_dirs" ]]; then
        mermaid=$'```mermaid\ngraph TD'
        local idx=0
        local ids=()
        while IFS= read -r dir; do
            [[ -z "$dir" ]] && continue
            local id
            id=$(echo "$dir" | tr -cs '[:alnum:]' '_' | sed 's/_$//')
            ids+=("$id")
            mermaid="${mermaid}"$'\n'"    ${id}[${dir}]"
            ((idx++))
        done <<< "$top_dirs"

        # Connect major components to a central node if >2 dirs
        if [[ ${#ids[@]} -gt 2 ]]; then
            mermaid="${mermaid}"$'\n'"    Root[Project Root]"
            for id in "${ids[@]}"; do
                mermaid="${mermaid}"$'\n'"    Root --> ${id}"
            done
        fi
        mermaid="${mermaid}"$'\n```'
    fi

    # Generate narrative description using architectural pattern detection
    local dir_count
    dir_count=$(find . -maxdepth 1 -type d -not -path "." -not -path "*/\.*" 2>/dev/null | wc -l)

    local pattern
    pattern=$(detect_architecture_pattern)

    case "$pattern" in
        "three-zone framework")
            local skill_count=0
            if [[ -d ".claude/skills" ]]; then
                skill_count=$(find .claude/skills -maxdepth 1 -type d 2>/dev/null | tail -n +2 | wc -l)
            fi
            narrative="The architecture follows a three-zone model: System (\`.claude/\`) contains framework-managed scripts and skills, State (\`grimoires/\`, \`.beads/\`) holds project-specific artifacts and memory, and App (\`src/\`, \`lib/\`) contains developer-owned application code."
            if (( skill_count > 0 )); then
                narrative="${narrative} The framework orchestrates ${skill_count} specialized skills through slash commands."
            fi
            ;;
        "layered MVC")
            local key_layers=""
            [[ -d "src/controllers" || -d "app/controllers" ]] && key_layers="${key_layers}controllers, "
            [[ -d "src/services" || -d "app/services" ]] && key_layers="${key_layers}services, "
            [[ -d "src/models" || -d "app/models" ]] && key_layers="${key_layers}models, "
            [[ -d "src/routes" || -d "app/routes" ]] && key_layers="${key_layers}routes, "
            key_layers=$(echo "$key_layers" | sed 's/, $//')
            narrative="The project follows a layered MVC architecture with ${dir_count} top-level modules. The application layer is organized into ${key_layers} for clear separation of concerns."
            ;;
        "monorepo")
            local pkg_count=0
            if [[ -d "packages" ]]; then
                pkg_count=$(find packages -maxdepth 1 -type d 2>/dev/null | tail -n +2 | wc -l)
            elif [[ -d "apps" ]]; then
                pkg_count=$(find apps -maxdepth 1 -type d 2>/dev/null | tail -n +2 | wc -l)
            fi
            narrative="The project is organized as a monorepo with ${pkg_count} packages across ${dir_count} top-level directories. Shared code and configurations are managed at the root level."
            ;;
        *)
            # Generic narrative with component purposes
            if [[ -n "$top_dirs" ]]; then
                local comp1 comp2 purpose1 purpose2
                comp1=$(echo "$top_dirs" | head -1)
                comp2=$(echo "$top_dirs" | sed -n '2p')
                purpose1=$(infer_module_purpose "./${comp1}")
                purpose2=""
                [[ -n "$comp2" ]] && purpose2=$(infer_module_purpose "./${comp2}")

                narrative="The project follows a ${pattern} architecture with ${dir_count} top-level modules."
                if [[ -n "$comp1" && -n "$purpose1" ]]; then
                    narrative="${narrative} \`${comp1}/\` handles ${purpose1,,}"
                    if [[ -n "$comp2" && -n "$purpose2" ]]; then
                        narrative="${narrative}, while \`${comp2}/\` provides ${purpose2,,}."
                    else
                        narrative="${narrative}."
                    fi
                fi
            fi
            ;;
    esac

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
            arch="${arch}"$'\n```'
            arch="${arch}"$'\n'"${tree}"
            arch="${arch}"$'\n```'
        fi
    fi

    if [[ -z "$arch" && -z "$mermaid" && -z "$narrative" ]]; then
        return 0
    fi

    # Output: narrative FIRST, then diagram, then tree (SDD §2.2.3)
    cat <<EOF
## Architecture
<!-- provenance: ${provenance} -->
$(if [[ -n "$narrative" ]]; then printf '%s\n\n' "$narrative"; fi)
$(if [[ -n "$mermaid" ]]; then printf '%s\n\n' "$mermaid"; fi)
$(if [[ -n "$arch" ]]; then printf '%s\n' "$arch"; fi)
EOF
}

# ── Skill Provenance Classification ──────────────────────
# Returns: "core" | "construct:<pack-slug>" | "project"
#
# Classification priority:
#   1. core-skills.json match → core
#   2. .constructs-meta.json from_pack match → construct:<pack>
#   3. packs/<pack>/skills/ directory match → construct:<pack> (fallback)
#   4. Otherwise → project

# Cache: loaded once per generation run (idempotent — BB-medium-1)
_CORE_SKILLS_CACHE=""
_CONSTRUCTS_META_CACHE=""
_PACKS_DIR=".claude/constructs/packs"
_CLASSIFICATION_CACHE_LOADED=false

load_classification_cache() {
    # Guard: skip if already loaded this run
    [[ "$_CLASSIFICATION_CACHE_LOADED" == "true" ]] && return 0

    local core_file=".claude/data/core-skills.json"
    if [[ -f "$core_file" ]] && command -v jq &>/dev/null; then
        _CORE_SKILLS_CACHE=$(jq -r '.skills[]' "$core_file" 2>/dev/null | sort) || true
    fi

    local meta_file=".claude/constructs/.constructs-meta.json"
    if [[ -f "$meta_file" ]] && command -v jq &>/dev/null; then
        # Filter out /tmp/ test entries, extract slug → from_pack mapping
        _CONSTRUCTS_META_CACHE=$(jq -r '
            .installed_skills | to_entries[] |
            select(.key | startswith("/tmp/") | not) |
            select(.value.from_pack != null) |
            "\(.key | split("/") | last)|\(.value.from_pack)"
        ' "$meta_file" 2>/dev/null) || true
    fi

    _CLASSIFICATION_CACHE_LOADED=true
}

classify_skill_provenance() {
    local slug="$1"

    # Priority 1: Core skills manifest
    if [[ -n "$_CORE_SKILLS_CACHE" ]]; then
        if echo "$_CORE_SKILLS_CACHE" | grep -qx "$slug"; then
            echo "core"
            return 0
        fi
    fi

    # Priority 2: Constructs metadata (from_pack)
    if [[ -n "$_CONSTRUCTS_META_CACHE" ]]; then
        local pack=""
        pack=$(echo "$_CONSTRUCTS_META_CACHE" | { grep "^${slug}|" || true; } | cut -d'|' -f2 | head -1)
        if [[ -n "$pack" ]]; then
            echo "construct:${pack}"
            return 0
        fi
    fi

    # Priority 3: Packs directory fallback
    if [[ -d "$_PACKS_DIR" ]]; then
        local pack_match=""
        pack_match=$(find "$_PACKS_DIR" -maxdepth 3 -type d -name "$slug" \
            -path "*/skills/*" 2>/dev/null | head -1 || true)
        if [[ -n "$pack_match" ]]; then
            # Extract pack slug from path: .claude/constructs/packs/<pack>/skills/<slug>
            local pack_slug
            pack_slug=$(echo "$pack_match" | sed "s|${_PACKS_DIR}/||" | cut -d'/' -f1)
            echo "construct:${pack_slug}"
            return 0
        fi
    fi

    # Priority 4: Default to project
    echo "project"
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

        # Express/Fastify routes — enhanced with method + path extraction (SDD §2.4.2)
        local routes
        routes=$(tier2_grep -E '(app|router)\.(get|post|put|delete|patch)\(' \
            --include="*.ts" --include="*.js" \
            --exclude-dir=tests --exclude-dir=test --exclude-dir=fixtures \
            --exclude-dir=grimoires --exclude-dir=evals \
            2>/dev/null | head -20) || true
        if [[ -n "$routes" ]]; then
            local formatted_routes=""
            formatted_routes=$(echo "$routes" | while IFS=: read -r file line content; do
                local method path
                method=$(echo "$content" | grep -oE '\.(get|post|put|delete|patch)\(' | \
                    sed 's/[.(]//g' | tr '[:lower:]' '[:upper:]')
                path=$(echo "$content" | grep -oE "'[^']+'" | head -1 | tr -d "'")
                [[ -z "$path" ]] && path=$(echo "$content" | grep -oE '"[^"]+"' | head -1 | tr -d '"')
                if [[ -n "$method" && -n "$path" ]]; then
                    echo "- **${method}** \`${path}\` (\`${file}:${line}\`)"
                fi
            done | sort -u | head -15) || true
            [[ -n "$formatted_routes" ]] && found="${found}### HTTP Routes\n\n${formatted_routes}\n\n"
        fi

        # CLI commands (exclude test fixtures)
        local cli
        cli=$(tier2_grep -E '\.command\(' \
            --include="*.ts" --include="*.js" \
            --exclude-dir=tests --exclude-dir=test --exclude-dir=fixtures \
            --exclude-dir=grimoires --exclude-dir=evals \
            2>/dev/null | head -10) || true
        [[ -n "$cli" ]] && found="${found}### CLI Commands\n\n${cli}\n\n"

        # Shell skill commands — segmented by provenance (SDD cycle-030 §3.3)
        if [[ -d ".claude/skills" ]]; then
            # Load classification cache once
            load_classification_cache

            local core_skills="" project_skills=""
            local has_construct_groups=false
            declare -A construct_groups=()
            declare -A construct_versions=()

            while IFS= read -r d; do
                [[ -z "$d" ]] && continue
                local sname skill_desc heading_desc
                sname=$(basename "$d")

                # Strategy 1: Extract ## Purpose section first line
                skill_desc=""
                if [[ -f "${d}/SKILL.md" ]]; then
                    skill_desc=$(awk '/^## Purpose/{f=1;next} f && /^##/{exit} f && /^[[:space:]]*$/{next} f{print;exit}' \
                        "${d}/SKILL.md" 2>/dev/null) || true
                fi

                # Strategy 2: Extract first heading after YAML frontmatter
                if [[ -z "$skill_desc" ]] && [[ -f "${d}/SKILL.md" ]]; then
                    heading_desc=$(awk '/^---/{c++} c==2{p=1} p && /^# /{sub(/^# +/,""); print; exit}' \
                        "${d}/SKILL.md" 2>/dev/null) || true
                    [[ -n "$heading_desc" ]] && skill_desc="$heading_desc"
                fi

                # Strategy 3: Synthesize from directory name
                if [[ -z "$skill_desc" ]]; then
                    skill_desc=$(echo "$sname" | sed 's/-/ /g' | sed 's/^./\U&/')
                fi

                local provenance_class
                provenance_class=$(classify_skill_provenance "$sname")

                local entry="- **/${sname}** — ${skill_desc}\n"

                case "$provenance_class" in
                    core)
                        core_skills="${core_skills}${entry}"
                        ;;
                    construct:*)
                        local pack="${provenance_class#construct:}"
                        has_construct_groups=true
                        construct_groups[$pack]="${construct_groups[$pack]:-}${entry}"
                        # Load version if not cached
                        if [[ -z "${construct_versions[$pack]:-}" ]]; then
                            local manifest="${_PACKS_DIR}/${pack}/manifest.json"
                            if [[ -f "$manifest" ]]; then
                                construct_versions[$pack]=$(jq -r '.version // "?"' "$manifest" 2>/dev/null) || true
                            fi
                            [[ -z "${construct_versions[$pack]:-}" ]] && construct_versions[$pack]="?"
                        fi
                        ;;
                    project)
                        project_skills="${project_skills}${entry}"
                        ;;
                esac
            done < <(find .claude/skills -maxdepth 1 -type d 2>/dev/null | sort | tail -n +2)

            # Build segmented output — omit empty groups
            local skills_output=""

            if [[ -n "$core_skills" ]]; then
                skills_output="${skills_output}#### Loa Core\n\n$(printf '%b' "$core_skills")\n"
            fi

            if [[ "$has_construct_groups" == "true" ]]; then
                skills_output="${skills_output}#### Constructs\n\n"
                for pack in $(echo "${!construct_groups[@]}" | tr ' ' '\n' | sort); do
                    local ver="${construct_versions[$pack]:-?}"
                    skills_output="${skills_output}**${pack}** (v${ver})\n${construct_groups[$pack]}\n"
                done
            fi

            if [[ -n "$project_skills" ]]; then
                skills_output="${skills_output}#### Project-Specific\n\n$(printf '%b' "$project_skills")\n"
            fi

            # Graceful degradation: if no classification data available,
            # all skills would have been classified as "project" by default
            [[ -n "$skills_output" ]] && found="${found}### Skill Commands\n\n$(printf '%b' "$skills_output")\n\n"
        fi

        ifaces=$(printf '%b' "$found")
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

    local table="| Module | Files | Purpose | Documentation |\n|--------|-------|---------|---------------|\n"
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

        # Use multi-strategy purpose inference (SDD §2.5.1)
        local purpose
        purpose=$(infer_module_purpose "$dir")

        # Documentation link detection (SDD §2.5.2)
        local doc_link="\u2014"
        if [[ -f "docs/${dname}.md" ]]; then
            doc_link="[docs/${dname}.md](docs/${dname}.md)"
        elif [[ -f "docs/modules/${dname}.md" ]]; then
            doc_link="[docs/modules/${dname}.md](docs/modules/${dname}.md)"
        elif [[ -f "${dir}/README.md" ]]; then
            doc_link="[${dname}/README.md](${dname}/README.md)"
        fi

        table="${table}| \`${dname}/\` | ${count} | ${purpose} | ${doc_link} |\n"
        found_any=true
    done <<< "$dirs"

    if [[ "$found_any" == "false" ]]; then
        return 0
    fi

    cat <<EOF
## Module Map
<!-- provenance: ${provenance} -->
$(printf '%b' "$table")
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
$(printf '%b' "$eco")
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

    # Strategy 1: Tier 1 reality files (highest priority)
    if [[ "$tier" -eq 1 ]]; then
        local grimoire_dir
        grimoire_dir=$(get_config_value "paths.grimoire" "grimoires/loa")
        if [[ -f "${grimoire_dir}/reality/behaviors.md" ]]; then
            limits=$(grep -iA3 'limitation\|caveat\|warning\|known issue' \
                "${grimoire_dir}/reality/behaviors.md" 2>/dev/null | head -20) || true
        fi
    fi

    # Strategy 2: README limitations section (strip matched heading)
    if [[ -z "$limits" ]] && [[ -f "README.md" ]]; then
        limits=$(sed -n '/^##.*[Ll]imit\|^##.*[Cc]aveat\|^##.*[Kk]nown/,/^## /p' \
            README.md 2>/dev/null | sed '1d;$d' | head -20) || true
    fi

    # Strategy 3: Structural inference from project characteristics (SDD §2.7)
    if [[ -z "$limits" ]]; then
        local inferred=""

        # No tests — check standard test directories first, then filename patterns
        local has_test_dir=false
        local td
        for td in tests test spec __tests__ e2e; do
            if [[ -d "$td" ]] && [[ -n "$(find "$td" -maxdepth 2 -type f 2>/dev/null | head -1)" ]]; then
                has_test_dir=true
                break
            fi
        done
        if [[ "$has_test_dir" == "false" ]]; then
            local test_count
            test_count=$(find . -maxdepth 3 \( -name "*.test.*" -o -name "*.spec.*" -o -name "*_test.*" \) 2>/dev/null | wc -l)
            (( test_count == 0 )) && inferred="${inferred}- No automated tests detected\n"
        fi

        # No CI
        [[ ! -d ".github/workflows" ]] && [[ ! -f ".gitlab-ci.yml" ]] && \
            inferred="${inferred}- No CI/CD configuration detected\n"

        # No documentation directory
        [[ ! -d "docs" ]] && [[ ! -f "CONTRIBUTING.md" ]] && \
            inferred="${inferred}- No documentation directory present\n"

        # Shell-only project
        local has_compiled=false
        [[ -n "$(find . -maxdepth 3 \( -name '*.ts' -o -name '*.rs' -o -name '*.go' \) 2>/dev/null | head -1)" ]] && has_compiled=true
        [[ "$has_compiled" == "false" ]] && \
            inferred="${inferred}- Shell-only project (no type checking)\n"

        [[ -n "$inferred" ]] && limits=$(printf '%b' "$inferred")
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
        # Extract getting started / quick start / installation section (strip matched heading)
        qs=$(sed -n '/^##.*[Gg]etting [Ss]tarted\|^##.*[Qq]uick [Ss]tart\|^##.*[Ii]nstall/,/^## /p' \
            README.md 2>/dev/null | sed '1d;$d' | head -20) || true
    fi

    # FR-5: Extract actual commands from package.json scripts or Makefile
    if [[ -z "$qs" ]]; then
        local cmds=""
        if [[ -f "package.json" ]] && command -v jq &>/dev/null; then
            local scripts
            scripts=$(jq -r '.scripts // {} | to_entries[] | select(.key | test("start|dev|build|test|install")) | "- `npm run \(.key)` — \(.value | split(" ") | .[0])"' package.json 2>/dev/null | head -5) || true
            [[ -n "$scripts" ]] && cmds="Available commands:\n\n${scripts}"
        elif [[ -f "Makefile" ]]; then
            local targets
            targets=$(grep -E '^[a-zA-Z_-]+:' Makefile 2>/dev/null | sed 's/:.*//' | head -5 | awk '{print "- `make " $0 "`"}') || true
            [[ -n "$targets" ]] && cmds="Available targets:\n\n${targets}"
        elif [[ -f "Cargo.toml" ]]; then
            cmds="Get started:\n\n\`\`\`bash\ncargo build\ncargo test\n\`\`\`"
        fi
        [[ -n "$cmds" ]] && qs=$(printf '%b' "$cmds")
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
# New Extractors — Cross-Repo Agent Legibility (cycle-017)
# =============================================================================

# Verification section: trust signals beyond version number (SPECULATION-3)
extract_verification() {
    local tier="$1"
    [[ "$tier" -eq 3 ]] && return 0

    local signals=""

    # Test count: check directories + filename patterns
    local test_file_count=0 test_suite_count=0
    local td
    for td in tests test spec __tests__ e2e; do
        if [[ -d "$td" ]]; then
            local c
            c=$(find "$td" -type f 2>/dev/null | wc -l | tr -d ' ')
            test_file_count=$((test_file_count + c))
            test_suite_count=$((test_suite_count + 1))
        fi
    done
    # Add named test files outside directories
    local named_tests
    named_tests=$(find . -maxdepth 3 \( -name "*.test.*" -o -name "*.spec.*" -o -name "*_test.*" -o -name "*.bats" \) \
        ! -path "*/tests/*" ! -path "*/test/*" ! -path "*/spec/*" ! -path "*/__tests__/*" ! -path "*/e2e/*" \
        2>/dev/null | wc -l | tr -d ' ')
    test_file_count=$((test_file_count + named_tests))

    if (( test_file_count > 0 )); then
        local suite_label="suite"
        (( test_suite_count > 1 )) && suite_label="suites"
        signals="${signals}- ${test_file_count} test files across ${test_suite_count} ${suite_label}\n"
    fi

    # CI presence
    local ci_info=""
    if [[ -d ".github/workflows" ]]; then
        local wf_count
        wf_count=$(find .github/workflows -name "*.yml" -o -name "*.yaml" 2>/dev/null | wc -l | tr -d ' ')
        ci_info="GitHub Actions (${wf_count} workflows)"
    elif [[ -f ".gitlab-ci.yml" ]]; then
        ci_info="GitLab CI"
    elif [[ -f "Jenkinsfile" ]]; then
        ci_info="Jenkins"
    fi
    [[ -n "$ci_info" ]] && signals="${signals}- CI/CD: ${ci_info}\n"

    # Type safety
    local type_info=""
    [[ -f "tsconfig.json" ]] && type_info="TypeScript"
    [[ -f "mypy.ini" || -f "pyrightconfig.json" ]] && type_info="Python type checking"
    [[ -f "rustfmt.toml" || -f "Cargo.toml" ]] && [[ -z "$type_info" ]] && type_info="Rust (type-safe)"
    [[ -n "$type_info" ]] && signals="${signals}- Type safety: ${type_info}\n"

    # Linter
    local linter_info=""
    [[ -n "$(find . -maxdepth 1 -name '.eslintrc*' 2>/dev/null | head -1)" ]] && linter_info="ESLint"
    [[ -f ".flake8" || -f "setup.cfg" ]] && [[ -z "$linter_info" ]] && linter_info="Flake8"
    [[ -f "clippy.toml" ]] && [[ -z "$linter_info" ]] && linter_info="Clippy"
    [[ -n "$linter_info" ]] && signals="${signals}- Linting: ${linter_info} configured\n"

    # Security
    local sec_info=""
    [[ -f "gitleaks.toml" || -f ".gitleaks.toml" ]] && sec_info="gitleaks configured"
    [[ -f "SECURITY.md" ]] && sec_info="${sec_info}${sec_info:+, }SECURITY.md present"
    [[ -n "$sec_info" ]] && signals="${signals}- Security: ${sec_info}\n"

    # Trust level detection delegated to compute_trust_level_tag() (single source of truth)

    [[ -z "$signals" ]] && return 0

    # Compute trust level — derive human-readable name from compute_trust_level_tag()
    local trust_tag trust_name
    trust_tag=$(compute_trust_level_tag)
    case "$trust_tag" in
        L1-tests-present) trust_name="L1 — Tests Present" ;;
        L2-verified)      trust_name="L2 — CI Verified" ;;
        L3-hardened)      trust_name="L3 — Property-Based" ;;
        L4-proven)        trust_name="L4 — Formal" ;;
        *)                trust_name="none" ;;
    esac

    cat <<EOF
## Verification
<!-- provenance: CODE-FACTUAL -->
- Trust Level: **${trust_name}**
$(printf '%b' "$signals")
EOF
}

# Agents section: self-describing persona metadata (Build Next #3)
extract_persona_agents() {
    local tier="$1"
    [[ "$tier" -eq 3 ]] && return 0

    local persona_files
    persona_files=$(find .claude/data -maxdepth 1 -name "*-persona.md" 2>/dev/null | sort)
    [[ -z "$persona_files" ]] && return 0

    local count=0
    local table="| Agent | Identity | Voice |\n|-------|----------|-------|\n"

    while IFS= read -r pf; do
        [[ -z "$pf" ]] && continue
        local agent_name identity voice

        # Extract heading
        agent_name=$(grep -m1 '^# ' "$pf" 2>/dev/null | sed 's/^# //') || true
        [[ -z "$agent_name" ]] && agent_name=$(basename "$pf" | sed 's/-persona\.md//' | sed 's/-/ /g;s/^./\U&/')

        # Extract Identity first sentence (sentence boundary, then char safety limit)
        identity=$(awk '/^## Identity/{f=1;next} f && /^##/{exit} f && /^[[:space:]]*$/{next} f{print;exit}' \
            "$pf" 2>/dev/null | sed 's/\. .*/\./' | cut -c1-160) || true
        [[ -z "$identity" ]] && identity="Specialized agent persona"

        # Extract Voice first sentence (sentence boundary, then char safety limit)
        voice=$(awk '/^## Voice/{f=1;next} f && /^##/{exit} f && /^[[:space:]]*$/{next} f{print;exit}' \
            "$pf" 2>/dev/null | sed 's/\. .*/\./' | cut -c1-160) || true
        [[ -z "$voice" ]] && voice="Custom voice profile"

        table="${table}| ${agent_name} | ${identity} | ${voice} |\n"
        count=$((count + 1))
    done <<< "$persona_files"

    (( count == 0 )) && return 0

    cat <<EOF
## Agents
<!-- provenance: DERIVED -->
The project defines ${count} specialized agent persona$( (( count > 1 )) && echo "s").

$(printf '%b' "$table")
EOF
}

# Culture section: project principles and methodology (Build Next #5, #247)
extract_culture() {
    local tier="$1"

    # Source: .loa.config.yaml butterfreezone.culture block
    if [[ ! -f ".loa.config.yaml" ]] || ! command -v yq &>/dev/null; then
        return 0
    fi

    local has_culture
    has_culture=$(yq '.butterfreezone.culture // null' .loa.config.yaml 2>/dev/null) || true
    [[ -z "$has_culture" || "$has_culture" == "null" ]] && return 0

    local naming methodology
    naming=$(yq '.butterfreezone.culture.naming_etymology // ""' .loa.config.yaml 2>/dev/null) || true
    methodology=$(yq '.butterfreezone.culture.methodology // ""' .loa.config.yaml 2>/dev/null) || true

    # Extract principles array
    local principle_count
    principle_count=$(yq '.butterfreezone.culture.principles | length // 0' .loa.config.yaml 2>/dev/null) || principle_count=0

    local culture_body=""
    [[ -n "$naming" && "$naming" != "null" ]] && culture_body="**Naming**: ${naming}."$'\n\n'

    if (( principle_count > 0 )); then
        local principles_text=""
        local i
        for ((i=0; i<principle_count; i++)); do
            local p
            p=$(yq ".butterfreezone.culture.principles[$i]" .loa.config.yaml 2>/dev/null) || true
            [[ -n "$p" && "$p" != "null" ]] && principles_text="${principles_text}${principles_text:+, }${p}"
        done
        [[ -n "$principles_text" ]] && culture_body="${culture_body}**Principles**: ${principles_text}."$'\n\n'
    fi

    [[ -n "$methodology" && "$methodology" != "null" ]] && culture_body="${culture_body}**Methodology**: ${methodology}."

    [[ -z "$culture_body" ]] && return 0

    cat <<EOF
## Culture
<!-- provenance: OPERATIONAL -->
${culture_body}
EOF
}

# Generative culture: creative methodology references (sprint-110, #247)
extract_generative_culture() {
    if [[ ! -f ".loa.config.yaml" ]] || ! command -v yq &>/dev/null; then
        return 0
    fi

    local has_gen
    has_gen=$(yq '.butterfreezone.culture.generative // null' .loa.config.yaml 2>/dev/null) || true
    [[ -z "$has_gen" || "$has_gen" == "null" ]] && return 0

    local gen_desc
    gen_desc=$(yq '.butterfreezone.culture.generative.description // ""' .loa.config.yaml 2>/dev/null) || true

    local ref_count
    ref_count=$(yq '.butterfreezone.culture.generative.references | length // 0' .loa.config.yaml 2>/dev/null) || ref_count=0

    local study_groups
    study_groups=$(yq '.butterfreezone.culture.generative.study_groups // ""' .loa.config.yaml 2>/dev/null) || true

    # Only emit if there's actual content
    [[ -z "$gen_desc" && "$ref_count" -eq 0 && -z "$study_groups" ]] && return 0

    local gen_body=""
    [[ -n "$gen_desc" && "$gen_desc" != "null" ]] && gen_body="**Creative Methodology**: ${gen_desc}."$'\n\n'

    if (( ref_count > 0 )); then
        local refs_text=""
        local i
        for ((i=0; i<ref_count; i++)); do
            local r
            r=$(yq ".butterfreezone.culture.generative.references[$i]" .loa.config.yaml 2>/dev/null) || true
            [[ -n "$r" && "$r" != "null" ]] && refs_text="${refs_text}${refs_text:+, }${r}"
        done
        [[ -n "$refs_text" ]] && gen_body="${gen_body}**Influences**: ${refs_text}."$'\n\n'
    fi

    [[ -n "$study_groups" && "$study_groups" != "null" ]] && gen_body="${gen_body}**Knowledge Production**: ${study_groups}."

    [[ -z "$gen_body" ]] && return 0

    # Emit as continuation of Culture section (no separate ## heading)
    printf '%s' "$gen_body"
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
        verification) header="## Verification" ;;
        agents) header="## Agents" ;;
        ecosystem) header="## Ecosystem" ;;
        culture) header="## Culture" ;;
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
                   module_map verification agents ecosystem culture \
                   limitations quick_start; do
        local content
        content=$(extract_section_content "$document" "$section")
        if [[ -n "$content" ]]; then
            local hash
            hash=$(printf '%s' "$content" | sha256sum | awk '{print $1}')
            checksums="${checksums}
  ${section}: ${hash}"
        fi
    done

    # Flatline verification data (cycle-017, Cross-Model Verification Certificates)
    local flatline_meta=""
    if [[ -d ".flatline/runs" ]]; then
        local latest_manifest
        latest_manifest=$(find .flatline/runs -name "*.json" -type f 2>/dev/null | sort -r | head -1)
        if [[ -n "$latest_manifest" ]] && command -v jq &>/dev/null; then
            local fl_status fl_models fl_high fl_run_at
            fl_status=$(jq -r '.status // "unknown"' "$latest_manifest" 2>/dev/null) || true
            fl_models=$(jq -r '[.models[]?.name // empty] | join(", ")' "$latest_manifest" 2>/dev/null) || true
            fl_high=$(jq -r '.metrics.high_consensus // 0' "$latest_manifest" 2>/dev/null) || true
            fl_run_at=$(jq -r '.completed_at // .started_at // ""' "$latest_manifest" 2>/dev/null) || true
            if [[ "$fl_status" != "unknown" && "$fl_status" != "null" ]]; then
                flatline_meta=$'\n'"flatline_verified: true"
                [[ -n "$fl_models" && "$fl_models" != "null" ]] && flatline_meta="${flatline_meta}"$'\n'"flatline_models: [${fl_models}]"
                [[ -n "$fl_high" && "$fl_high" != "null" ]] && flatline_meta="${flatline_meta}"$'\n'"flatline_consensus: ${fl_high} HIGH_CONSENSUS"
                [[ -n "$fl_run_at" && "$fl_run_at" != "null" ]] && flatline_meta="${flatline_meta}"$'\n'"flatline_last_run: ${fl_run_at}"
            fi
        fi
    fi

    cat <<EOF
<!-- ground-truth-meta
head_sha: ${head_sha}
generated_at: ${generated_at}
generator: butterfreezone-gen v${SCRIPT_VERSION}${flatline_meta}
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
    local verif="" agents_sec="" culture_sec=""

    agent_ctx=$(extract_agent_context "$tier")
    header=$(extract_header "$tier")

    if [[ "$tier" -ne 3 ]]; then
        caps=$(run_extractor "capabilities" "$tier")
        arch=$(run_extractor "architecture" "$tier")
        ifaces=$(run_extractor "interfaces" "$tier")
    fi

    modmap=$(run_extractor "module_map" "$tier")

    if [[ "$tier" -ne 3 ]]; then
        verif=$(extract_verification "$tier") || true
        agents_sec=$(extract_persona_agents "$tier") || true
        eco=$(run_extractor "ecosystem" "$tier")
        culture_sec=$(extract_culture "$tier") || true
        # Append generative culture if present (sprint-110, #247)
        local gen_culture
        gen_culture=$(extract_generative_culture) || true
        if [[ -n "$gen_culture" && -n "$culture_sec" ]]; then
            culture_sec="${culture_sec}"$'\n'"${gen_culture}"
        fi
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
    document=$(assemble_sections "$agent_ctx" "$header" "$caps" "$arch" "$ifaces" "$modmap" "$verif" "$agents_sec" "$eco" "$culture_sec" "$limits" "$qs")

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
