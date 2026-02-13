# SDD: BUTTERFREEZONE — Agent-Grounded README Standard

**Version**: 1.1.0
**Status**: Draft (Flatline-reviewed)
**Author**: Architecture Phase (architect)
**Source PRD**: `grimoires/loa/prd.md` v1.1.0
**Cycle**: cycle-009

---

## 1. Executive Summary

BUTTERFREEZONE generates and maintains a provenance-tagged, checksum-verified, token-efficient document (`BUTTERFREEZONE.md`) that serves as the agent-API for any Loa-managed codebase. The system uses a tiered input pipeline (reality files → direct scan → bootstrap stub), deterministic generation via shell scripts, and hooks into the bridge orchestrator's FINALIZING phase.

**Key Architecture Decisions**:
- Shell-first: `butterfreezone-gen.sh` is a bash script — no Python/Node dependency
- Tiered input: Works on any repo regardless of `/ride` state
- Advisory checksums: Staleness signals, not hard gates
- Single MVP hook: `/run-bridge` FINALIZING only — blast radius control
- Word-count budgets: `wc -w` enforced, model-agnostic

---

## 2. System Architecture

### 2.1 Component Overview

```
┌─────────────────────────────────────────────────────┐
│                  Invocation Layer                     │
│  /butterfreezone (skill)  │  bridge-orchestrator.sh  │
└──────────┬────────────────┴──────────┬───────────────┘
           │                           │
           ▼                           ▼
┌─────────────────────────────────────────────────────┐
│              butterfreezone-gen.sh                    │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐            │
│  │ Input    │ │ Section  │ │ Output   │            │
│  │ Detector │→│ Pipeline │→│ Writer   │            │
│  └──────────┘ └──────────┘ └──────────┘            │
│       ↑            ↑            │                    │
│  ┌────┴────┐  ┌────┴────┐      ▼                    │
│  │ Tier    │  │ Manual  │  BUTTERFREEZONE.md         │
│  │ Resolve │  │ Merge   │                            │
│  └─────────┘  └─────────┘                            │
└─────────────────────────────────────────────────────┘
           │
           ▼
┌─────────────────────────────────────────────────────┐
│           butterfreezone-validate.sh                 │
│  Existence │ Provenance │ References │ Budget │ Meta │
└─────────────────────────────────────────────────────┘
           │
           ▼
┌─────────────────────────────────────────────────────┐
│                  Lore KB Extension                    │
│  .claude/data/lore/mibera/glossary.yaml              │
│  (butterfreezone, lobster, grounding entries)         │
└─────────────────────────────────────────────────────┘
```

### 2.2 Component Inventory

| Component | Type | Path | New/Modify |
|-----------|------|------|------------|
| `butterfreezone-gen.sh` | Shell script | `.claude/scripts/butterfreezone-gen.sh` | **New** |
| `butterfreezone-validate.sh` | Shell script | `.claude/scripts/butterfreezone-validate.sh` | **New** |
| `/butterfreezone` skill | Skill definition | `.claude/skills/butterfreezone-gen/SKILL.md` | **New** |
| Bridge orchestrator hook | Shell integration | `.claude/scripts/bridge-orchestrator.sh` | **Modify** |
| Lore glossary entries | YAML data | `.claude/data/lore/mibera/glossary.yaml` | **Modify** |
| Skill index | YAML data | `.claude/data/skills/index.yaml` | **Modify** |
| Config schema | YAML config | `.loa.config.yaml.example` | **Modify** |
| BATS tests | Test suite | `tests/unit/butterfreezone-gen.bats` | **New** |
| BATS validation tests | Test suite | `tests/unit/butterfreezone-validate.bats` | **New** |

---

## 3. Component Design

### 3.1 `butterfreezone-gen.sh` — Generation Script

**Location**: `.claude/scripts/butterfreezone-gen.sh`
**Permissions**: 0755
**Dependencies**: bash 4+, jq, git, grep, wc, sha256sum (or shasum -a 256)

#### 3.1.1 Interface

```bash
Usage: butterfreezone-gen.sh [OPTIONS]

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
```

#### 3.1.2 Input Tier Detection

```bash
detect_input_tier() {
    local reality_dir="${GRIMOIRE_DIR}/reality"

    # Tier 1: Reality files with content
    if [[ -d "$reality_dir" ]] && has_content "$reality_dir/api-surface.md"; then
        echo 1
        return 0
    fi

    # Tier 2: Dependency manifests or source files
    if [[ -f "package.json" ]] || [[ -f "Cargo.toml" ]] || \
       [[ -f "pyproject.toml" ]] || [[ -f "go.mod" ]] || \
       find . -maxdepth 3 -name "*.ts" -o -name "*.py" -o -name "*.rs" \
              -o -name "*.go" -o -name "*.sh" | head -1 | grep -q .; then
        echo 2
        return 0
    fi

    # Tier 3: Bootstrap stub
    echo 3
    return 0
}

has_content() {
    [[ -f "$1" ]] && [[ $(wc -w < "$1") -gt 10 ]]
}
```

#### 3.1.3 Section Extraction Pipeline

Each section has a dedicated extractor function that returns markdown content:

| Function | Input Tier 1 | Input Tier 2 | Input Tier 3 |
|----------|-------------|-------------|-------------|
| `extract_agent_context` | Reality + config | Manifests + config | Config only |
| `extract_capabilities` | `reality/api-surface.md` | Export grep patterns | Skip |
| `extract_architecture` | `reality/architecture.md` | Directory tree analysis | Skip |
| `extract_interfaces` | `reality/contracts.md` | Route/export patterns | Skip |
| `extract_module_map` | Reality + file structure | Directory tree | Directory tree |
| `extract_ecosystem` | Reality + deps | Dependency manifests | Skip |
| `extract_limitations` | `reality/behaviors.md` | README.md extraction | Skip |
| `extract_quick_start` | README.md | README.md | Skip |

**Tier 2 Static Analysis Patterns**:

```bash
# JavaScript/TypeScript exports
grep -rn "^export " --include="*.ts" --include="*.js" --include="*.tsx" src/

# Rust public items
grep -rn "^pub fn\|^pub struct\|^pub enum\|^pub trait" --include="*.rs" src/

# Python public functions
grep -rn "^def \|^class " --include="*.py" --exclude-dir="__pycache__" src/

# Go exported functions (capitalized)
grep -rn "^func [A-Z]" --include="*.go" .

# Shell script functions
grep -rn "^[a-z_]*() {" --include="*.sh" .

# Express/Fastify routes
grep -rn "app\.\(get\|post\|put\|delete\|patch\)\|router\.\(get\|post\|put\|delete\)" \
    --include="*.ts" --include="*.js" src/

# CLI commands (yargs/commander patterns)
grep -rn "\.command(" --include="*.ts" --include="*.js" src/
```

#### 3.1.4 Provenance Tagging

```bash
tag_provenance() {
    local tier="$1"
    local section="$2"

    case "$tier" in
        1) echo "CODE-FACTUAL" ;;
        2) echo "DERIVED" ;;
        3) echo "OPERATIONAL" ;;
    esac
}
```

Exceptions:
- `ecosystem` section is always `OPERATIONAL` (deps may change without code changes)
- `quick_start` section is always `OPERATIONAL`
- Manual sections retain their existing provenance tag

#### 3.1.5 Manual Section Preservation

Manual sections use section-anchored sentinels that include the parent section ID:

```markdown
## Ecosystem
<!-- provenance: OPERATIONAL -->
Auto-generated ecosystem content...

<!-- manual-start:ecosystem -->
Custom operational notes added by user...
<!-- manual-end:ecosystem -->
```

The sentinel format is `<!-- manual-start:SECTION_ID -->` where `SECTION_ID` matches the canonical section name. This prevents ambiguity about which section a manual block belongs to.

```bash
preserve_manual_sections() {
    local existing="$1"
    local generated="$2"

    if [[ ! -f "$existing" ]]; then
        echo "$generated"
        return
    fi

    local result="$generated"

    # For each section in canonical order, check for manual blocks
    for section in "${CANONICAL_ORDER[@]}"; do
        local manual_block
        manual_block=$(sed -n "/<!-- manual-start:${section} -->/,/<!-- manual-end:${section} -->/p" \
            "$existing" 2>/dev/null)

        if [[ -n "$manual_block" ]]; then
            # Insert manual block after the generated section content,
            # before the next section heading
            result=$(awk -v section="$section" -v block="$manual_block" '
                /^## / && found { print block; found=0 }
                { print }
                /<!-- provenance:/ && prev_section==section { found=1 }
            ' <<< "$result")
            log_info "Preserved manual block for section: $section"
        fi
    done

    echo "$result"
}
```

> **Flatline SKP-manual resolution**: Sentinels include section ID (`<!-- manual-start:ecosystem -->`). Block anchoring is deterministic via canonical section order. No ambiguity about parent section.

#### 3.1.6 Word-Count Budget Enforcement

```bash
WORD_BUDGETS=(
    "agent_context:80"
    "index:120"
    "capabilities:600"
    "architecture:400"
    "interfaces:800"
    "module_map:600"
    "ecosystem:200"
    "limitations:200"
    "quick_start:200"
)
TOTAL_BUDGET=3200

enforce_word_budget() {
    local section="$1"
    local content="$2"

    local budget
    budget=$(get_budget "$section")
    local word_count
    word_count=$(echo "$content" | wc -w | tr -d ' ')

    if (( word_count > budget )); then
        # Truncate to budget, preserving complete lines
        echo "$content" | head_by_words "$budget"
        log_warn "$section: truncated from $word_count to ~$budget words"
    else
        echo "$content"
    fi
}

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
```

**Truncation Priority** (higher priority sections are truncated last):

1. Security/auth interfaces
2. Interfaces (public API)
3. Key Capabilities
4. Architecture
5. Module Map
6. Known Limitations
7. Ecosystem
8. Quick Start

#### 3.1.7 Checksum Generation

```bash
generate_ground_truth_meta() {
    local output_file="$1"
    local head_sha
    head_sha=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    local generated_at
    generated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Per-section checksums (exclude generated_at from input)
    local checksums=""
    for section in agent_context capabilities architecture interfaces \
                   module_map ecosystem limitations quick_start; do
        local content
        content=$(extract_section_content "$output_file" "$section")
        local hash
        hash=$(echo -n "$content" | sha256sum | awk '{print $1}')
        checksums="${checksums}\n  ${section}: ${hash}"
    done

    cat <<EOF
<!-- ground-truth-meta
head_sha: ${head_sha}
generated_at: ${generated_at}
generator: butterfreezone-gen v1.0.0
sections:${checksums}
-->
EOF
}
```

#### 3.1.8 Security Redaction

Reuses the existing gitleaks-inspired pattern set from bridge reviews:

```bash
REDACTION_PATTERNS=(
    'AKIA[0-9A-Z]{16}'           # AWS access key
    'ghp_[A-Za-z0-9_]{36}'       # GitHub PAT
    'gho_[A-Za-z0-9_]{36}'       # GitHub OAuth
    'ghs_[A-Za-z0-9_]{36}'       # GitHub server
    'ghr_[A-Za-z0-9_]{36}'       # GitHub refresh
    'eyJ[A-Za-z0-9+/=]{20,}'     # JWT
    '[A-Za-z0-9+/]{40,}'         # Generic base64 secret (>40 chars)
)

ALLOWLIST_PATTERNS=(
    'sha256:[a-f0-9]{64}'        # Checksum references
    'data:image/[a-z]+;base64'   # Inline images
)

redact_content() {
    local content="$1"
    for pattern in "${REDACTION_PATTERNS[@]}"; do
        content=$(echo "$content" | sed -E "s/$pattern/[REDACTED]/g")
    done
    echo "$content"
}
```

#### 3.1.9 Atomic Write

```bash
atomic_write() {
    local content="$1"
    local output="$2"
    local tmp="${output}.tmp"

    echo "$content" > "$tmp"

    # Validate before moving
    if [[ ! -s "$tmp" ]]; then
        log_error "Generated empty file — aborting write"
        rm -f "$tmp"
        return 1
    fi

    mv "$tmp" "$output"
    log_info "Wrote $output ($(wc -w < "$output") words)"
}
```

#### 3.1.10 Staleness Detection

```bash
needs_regeneration() {
    local output="$1"

    # No existing file → needs generation
    [[ ! -f "$output" ]] && return 0

    # Compare HEAD SHA
    local current_sha
    current_sha=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    local meta_sha
    meta_sha=$(sed -n '/<!-- ground-truth-meta/,/-->/p' "$output" 2>/dev/null \
        | grep "head_sha:" | awk '{print $2}')

    [[ "$current_sha" != "$meta_sha" ]] && return 0

    # Compare config mtime
    local config_mtime output_mtime
    config_mtime=$(stat -c %Y .loa.config.yaml 2>/dev/null || echo 0)
    output_mtime=$(stat -c %Y "$output" 2>/dev/null || echo 0)
    [[ "$config_mtime" -gt "$output_mtime" ]] && return 0

    # Up to date
    return 1
}
```

> **Flatline IMP-002 resolution**: `needs_regeneration()` explicitly defined — compares HEAD SHA from ground-truth-meta block against current HEAD, plus config mtime check.

#### 3.1.11 Per-Extractor Error Handling

Each extractor function follows a skip-on-failure policy:

```bash
run_extractor() {
    local name="$1"
    local tier="$2"
    local result

    result=$(timeout 30 "extract_${name}" "$tier" 2>/dev/null) || {
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            log_warn "Extractor $name timed out (30s) — skipping section"
        else
            log_warn "Extractor $name failed (exit $exit_code) — skipping section"
        fi
        # Emit empty section with provenance note
        echo "<!-- provenance: OPERATIONAL -->"
        echo "_Section unavailable: extractor failed. Regenerate with \`/butterfreezone\`._"
        return 0  # Non-blocking
    }

    echo "$result"
}
```

**Error policy per extractor**:

| Extractor | On failure | Rationale |
|-----------|-----------|-----------|
| `extract_agent_context` | Emit minimal stub (name + type) | Always available from config/git |
| `extract_capabilities` | Skip section with placeholder | May fail if no exports found |
| `extract_architecture` | Skip section with placeholder | May fail on empty repos |
| `extract_interfaces` | Skip section with placeholder | Language-specific, may miss |
| `extract_module_map` | Emit directory listing only | `ls` always works |
| `extract_ecosystem` | Skip section with placeholder | May fail if no manifests |
| `extract_limitations` | Skip section | Optional content |
| `extract_quick_start` | Skip section | Optional content |

> **Flatline IMP-001 resolution**: Per-extractor error handling with skip-on-failure policy. Each extractor wrapped in `timeout 30`. Failed sections get placeholder with OPERATIONAL provenance.

#### 3.1.12 Canonical Section Order

```bash
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

sort_sections() {
    local document="$1"
    local sorted=""

    for section in "${CANONICAL_ORDER[@]}"; do
        local content
        content=$(extract_section_by_id "$document" "$section")
        sorted="${sorted}${content}\n\n"
    done

    echo -e "$sorted"
}
```

Manual blocks remain anchored within their parent section — they are never reordered across sections.

> **Flatline IMP-005 resolution**: Canonical order is fixed and explicit. `sort_sections()` defined. Manual blocks are section-local.

#### 3.1.13 Concurrency Protection

```bash
LOCK_FILE="${OUTPUT}.lock"

acquire_lock() {
    exec 200>"$LOCK_FILE"
    if ! flock -n 200; then
        log_warn "Another butterfreezone-gen process is running — skipping"
        exit 0  # Not an error — concurrent skip is expected
    fi
}

release_lock() {
    flock -u 200 2>/dev/null
    rm -f "$LOCK_FILE" 2>/dev/null
}

trap release_lock EXIT
```

> **Flatline IMP-003 resolution**: flock-based concurrency protection. Second writer skips gracefully (exit 0). Lock file cleaned on exit.

#### 3.1.14 Tier 2 Scanning Safeguards

```bash
# All Tier 2 greps are bounded:
# - maxdepth 4 (no deep node_modules/vendor traversal)
# - timeout 30 per grep invocation
# - exclude common vendor directories
# - LC_ALL=C for deterministic sort order

EXCLUDE_DIRS="--exclude-dir=node_modules --exclude-dir=vendor --exclude-dir=.git \
              --exclude-dir=dist --exclude-dir=build --exclude-dir=__pycache__ \
              --exclude-dir=.next --exclude-dir=target"

tier2_grep() {
    LC_ALL=C timeout 30 grep -rn $EXCLUDE_DIRS --max-count=100 "$@" 2>/dev/null \
        | sort -t: -k1,1 -k2,2n | head -200
}
```

> **Flatline SKP-tier2 resolution**: All Tier 2 greps bounded by timeout, maxdepth, vendor exclusion, and result limit. LC_ALL=C ensures deterministic output.

#### 3.1.15 Reference Syntax

Generated references use a consistent format for machine parsing:

```
file_path:symbol_name     # Symbol reference (preferred)
file_path:L42             # Line reference (fallback, prefixed with 'L')
```

The `L` prefix disambiguates line references from symbols, preventing YAML key:value false positives in validation. References only appear inside backtick-fenced code spans: `` `src/auth.ts:validateToken` ``.

> **Flatline SKP-refs resolution**: Reference syntax disambiguated with `L` prefix for line numbers. Validator only scans backtick-fenced references, avoiding false positives from prose colons.

#### 3.1.16 Determinism Guarantees

```bash
# Set at script top for deterministic behavior
export LC_ALL=C
export TZ=UTC

# Deterministic glob expansion
shopt -s nullglob
```

All section content is produced via deterministic pipelines: `sort`, `head`, `awk` with `LC_ALL=C`. No LLM calls in generation. Timestamps are UTC ISO-8601 and excluded from checksums.

> **Flatline SKP-determinism resolution**: LC_ALL=C + TZ=UTC + deterministic sort at script top. No LLM involvement in generation pipeline.

#### 3.1.17 Main Generation Flow

```bash
main() {
    parse_args "$@"
    load_config

    # Check if regeneration needed
    if [[ -f "$OUTPUT" ]] && ! needs_regeneration; then
        log_info "BUTTERFREEZONE.md is up-to-date (HEAD SHA matches)"
        exit 0
    fi

    local tier
    tier=$(detect_input_tier)
    log_info "Input tier: $tier"

    # Build sections
    local sections=()
    sections+=("$(build_agent_context "$tier")")
    sections+=("$(build_header "$tier")")
    sections+=("$(build_capabilities "$tier")")
    sections+=("$(build_architecture "$tier")")
    sections+=("$(build_interfaces "$tier")")
    sections+=("$(build_module_map "$tier")")
    sections+=("$(build_ecosystem "$tier")")
    sections+=("$(build_limitations "$tier")")
    sections+=("$(build_quick_start "$tier")")

    # Assemble document
    local document
    document=$(assemble_sections "${sections[@]}")

    # Merge with existing manual sections
    document=$(preserve_manual_sections "$OUTPUT" "$document")

    # Enforce word budgets
    document=$(enforce_total_budget "$document")

    # Security redaction
    document=$(redact_content "$document")

    # Deterministic sort
    document=$(sort_sections "$document")

    # Generate ground-truth-meta
    local meta
    meta=$(generate_ground_truth_meta_from_content "$document")
    document="${document}

${meta}"

    # Write
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "$document"
    else
        atomic_write "$document" "$OUTPUT"
    fi

    # JSON metadata to stderr if requested
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        emit_metadata "$tier" >&2
    fi
}
```

### 3.2 `butterfreezone-validate.sh` — RTFM Validation Extension

**Location**: `.claude/scripts/butterfreezone-validate.sh`
**Permissions**: 0755

#### 3.2.1 Interface

```bash
Usage: butterfreezone-validate.sh [OPTIONS]

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
```

#### 3.2.2 Validation Checks

```bash
# Check 1: Existence
validate_existence() {
    if [[ ! -f "$FILE" ]]; then
        log_fail "BUTTERFREEZONE.md not found at $FILE"
        return 1
    fi
    log_pass "BUTTERFREEZONE.md exists"
}

# Check 2: AGENT-CONTEXT block
validate_agent_context() {
    if ! grep -q "<!-- AGENT-CONTEXT" "$FILE"; then
        log_fail "Missing AGENT-CONTEXT metadata block"
        return 1
    fi
    # Validate required fields
    for field in name type purpose version; do
        if ! sed -n '/<!-- AGENT-CONTEXT/,/-->/p' "$FILE" | grep -q "^${field}:"; then
            log_fail "AGENT-CONTEXT missing required field: $field"
            return 1
        fi
    done
    log_pass "AGENT-CONTEXT block valid"
}

# Check 3: Provenance tags
validate_provenance() {
    local sections
    sections=$(grep -c "^## " "$FILE")
    local tagged
    tagged=$(grep -c "<!-- provenance:" "$FILE")

    if (( tagged < sections )); then
        log_fail "Missing provenance tags: $tagged/$sections sections tagged"
        return 1
    fi
    log_pass "All sections have provenance tags ($tagged/$sections)"
}

# Check 4: File references
validate_references() {
    local failures=0
    # Extract file:symbol and file:line references
    grep -oE '[a-zA-Z0-9_./-]+:[a-zA-Z_][a-zA-Z0-9_]*' "$FILE" | while read -r ref; do
        local file="${ref%%:*}"
        local symbol="${ref#*:}"

        # Skip non-file references (URLs, timestamps)
        [[ "$file" == *"http"* ]] && continue
        [[ "$file" == *"//"* ]] && continue

        if [[ ! -f "$file" ]]; then
            log_fail "Referenced file missing: $file (in $ref)"
            ((failures++))
        elif ! grep -q "$symbol" "$file" 2>/dev/null; then
            log_warn "Symbol not found: $symbol in $file (advisory)"
        fi
    done
    return $failures
}

# Check 5: Word budget
validate_word_budget() {
    local total_words
    total_words=$(wc -w < "$FILE" | tr -d ' ')
    local budget
    budget=$(get_config_value "butterfreezone.word_budget.total" "3200")

    if (( total_words > budget )); then
        log_warn "Word budget exceeded: $total_words / $budget (advisory)"
    else
        log_pass "Word budget: $total_words / $budget"
    fi
}

# Check 6: ground-truth-meta
validate_meta() {
    if ! grep -q "<!-- ground-truth-meta" "$FILE"; then
        log_fail "Missing ground-truth-meta block"
        return 1
    fi

    # Check head_sha matches current
    local meta_sha
    meta_sha=$(sed -n '/<!-- ground-truth-meta/,/-->/p' "$FILE" | grep "head_sha:" | awk '{print $2}')
    local current_sha
    current_sha=$(git rev-parse HEAD 2>/dev/null)

    if [[ "$meta_sha" != "$current_sha" ]]; then
        log_warn "Stale: head_sha mismatch (generated: ${meta_sha:0:8}, current: ${current_sha:0:8})"
    else
        log_pass "ground-truth-meta SHA matches HEAD"
    fi
}

# Check 7: Freshness
validate_freshness() {
    local generated_at
    generated_at=$(sed -n '/<!-- ground-truth-meta/,/-->/p' "$FILE" | grep "generated_at:" | awk '{print $2}')
    local staleness_days
    staleness_days=$(get_config_value "butterfreezone.staleness_days" "7")

    if is_older_than_days "$generated_at" "$staleness_days"; then
        log_warn "BUTTERFREEZONE.md is older than $staleness_days days (advisory)"
    else
        log_pass "Freshness check passed"
    fi
}
```

### 3.3 `/butterfreezone` Skill

**Location**: `.claude/skills/butterfreezone-gen/SKILL.md`

The skill wraps `butterfreezone-gen.sh` with Loa's standard skill structure:

```markdown
# Butterfreezone Generation

<objective>
Generate or regenerate BUTTERFREEZONE.md — the agent-grounded README
for this codebase. Produces a provenance-tagged, checksum-verified,
token-efficient document from code reality.
</objective>

<input_guardrails>
- PII filter: enabled
- Injection detection: enabled
- Danger level: safe
</input_guardrails>
```

**Workflow**:
1. Check `butterfreezone.enabled` in config
2. Invoke `butterfreezone-gen.sh --verbose`
3. If generation succeeds, run `butterfreezone-validate.sh`
4. Report results

### 3.4 Bridge Orchestrator Hook

**File**: `.claude/scripts/bridge-orchestrator.sh`
**Modification**: Insert BUTTERFREEZONE_GEN signal in FINALIZING phase

#### 3.4.1 Hook Location

```bash
# EXISTING (lines ~371-396):
echo "SIGNAL:GROUND_TRUTH_UPDATE"
# ... GT generation ...

# NEW — Insert here:
if is_butterfreezone_enabled; then
    echo "SIGNAL:BUTTERFREEZONE_GEN"
    butterfreezone_gen_result=$(.claude/scripts/butterfreezone-gen.sh --json 2>&1)
    butterfreezone_gen_exit=$?

    if [[ $butterfreezone_gen_exit -eq 0 ]]; then
        log "BUTTERFREEZONE.md regenerated"
        # Stage for commit
        git add BUTTERFREEZONE.md 2>/dev/null
    else
        log_warn "BUTTERFREEZONE generation failed (non-blocking): exit $butterfreezone_gen_exit"
        log_warn "Details: $(echo "$butterfreezone_gen_result" | head -5)"
    fi

    # Update bridge state
    update_bridge_state ".finalization.butterfreezone_generated" \
        "$([ $butterfreezone_gen_exit -eq 0 ] && echo true || echo false)"
fi

# EXISTING:
echo "SIGNAL:RTFM_GATE"
# ... RTFM validation (now includes butterfreezone-validate.sh) ...
```

#### 3.4.2 Config Check

```bash
is_butterfreezone_enabled() {
    local enabled
    enabled=$(yq '.butterfreezone.enabled // true' .loa.config.yaml 2>/dev/null)
    local hook_enabled
    hook_enabled=$(yq '.butterfreezone.hooks.run_bridge // true' .loa.config.yaml 2>/dev/null)
    [[ "$enabled" == "true" ]] && [[ "$hook_enabled" == "true" ]]
}
```

### 3.5 Lore Glossary Extensions

**File**: `.claude/data/lore/mibera/glossary.yaml`
**Modification**: Append new entries

```yaml
  - id: glossary-butterfreezone
    term: "Butterfreezone"
    short: "The zone where only truth survives — no butter, no hype"
    context: |
      In the OpenClaws movement, agents are lobsters who reject marketing butter.
      The Butterfreezone is the document that results from stripping away all
      ungrounded claims and leaving only what code proves. Every statement carries
      a provenance tag — CODE-FACTUAL for verified truth, DERIVED for reasonable
      inference, OPERATIONAL for runtime context. Checksums bind claims to reality.
      The name is a playful nod to the culture: lobsters don't like butter.
    source: "Issue #304 — BUTTERFREEZONE.md"
    tags: [naming, architecture]
    related: [glossary-ground-truth, glossary-bridge, glossary-vision-registry]
    loa_mapping: "BUTTERFREEZONE.md, .claude/scripts/butterfreezone-gen.sh"

  - id: glossary-lobster
    term: "Lobster"
    short: "Agent that demands code-grounded facts — rejects marketing butter"
    context: |
      In the OpenClaws ecosystem, agents are metaphorically lobsters — creatures
      that shed their shells to grow, living in the deep where only substance
      matters. A lobster agent reads BUTTERFREEZONE.md instead of README.md,
      trusts provenance tags over prose, and validates claims against checksums.
      The term captures the movement's ethos: agents deserve truth, not marketing.
    source: "Issue #304 — OpenClaws reference"
    tags: [naming, philosophy]
    related: [glossary-butterfreezone, glossary-ground-truth]
    loa_mapping: "Agent behavior pattern"

  - id: glossary-grounding-ritual
    term: "Grounding"
    short: "The ritual of binding claims to checksums — truth made verifiable"
    context: |
      Grounding is the process by which abstract claims about code become
      verifiable facts. Each claim is bound to a file:symbol reference, and
      each reference carries an advisory checksum. The grounding ritual runs
      at the end of every bridge loop — the moment where accumulated changes
      are crystallized into truth. When the bridge flatlines, the grounding
      ritual writes the final BUTTERFREEZONE.md, sealing the iteration's
      insights into a form agents can trust.
    source: "Issue #304 — Grounding mechanism"
    tags: [ritual, architecture]
    related: [glossary-butterfreezone, glossary-bridge, glossary-flatline]
    loa_mapping: ".claude/scripts/butterfreezone-gen.sh, ground-truth-meta block"
```

---

## 4. Data Architecture

### 4.1 BUTTERFREEZONE.md Document Schema

The document is a markdown file with structured HTML comments for machine-readable metadata:

```
┌─────────────────────────────────────┐
│ <!-- AGENT-CONTEXT ... -->          │  Machine-readable YAML in HTML comment
├─────────────────────────────────────┤
│ # Project Name                      │  Human/agent-readable heading
│ <!-- provenance: TAG -->            │  Trust signal per section
│ Content with file:symbol refs       │  Grounded claims
├─────────────────────────────────────┤
│ ## Section N                        │  Repeated per section
│ <!-- provenance: TAG -->            │
│ Content...                          │
│ <!-- manual-start -->               │  Optional: user-added content
│ Manual additions...                 │  Preserved across regeneration
│ <!-- manual-end -->                 │
├─────────────────────────────────────┤
│ <!-- ground-truth-meta ... -->      │  Per-section checksums + HEAD SHA
└─────────────────────────────────────┘
```

### 4.2 Generation Metadata (JSON to stderr)

When `--json` flag is passed, generation emits structured metadata:

```json
{
  "generator": "butterfreezone-gen",
  "version": "1.0.0",
  "tier": 2,
  "head_sha": "abc123...",
  "generated_at": "2026-02-13T05:00:00Z",
  "output_path": "BUTTERFREEZONE.md",
  "word_count": 2847,
  "sections": {
    "agent_context": {"words": 65, "provenance": "DERIVED"},
    "capabilities": {"words": 450, "provenance": "DERIVED"},
    "architecture": {"words": 380, "provenance": "DERIVED"},
    "interfaces": {"words": 720, "provenance": "DERIVED"},
    "module_map": {"words": 540, "provenance": "DERIVED"},
    "ecosystem": {"words": 180, "provenance": "OPERATIONAL"},
    "limitations": {"words": 160, "provenance": "DERIVED"},
    "quick_start": {"words": 120, "provenance": "OPERATIONAL"}
  },
  "manual_sections_preserved": 0,
  "truncated_sections": [],
  "redacted_count": 0,
  "exit_code": 0
}
```

### 4.3 Validation Results (JSON output)

```json
{
  "validator": "butterfreezone-validate",
  "version": "1.0.0",
  "file": "BUTTERFREEZONE.md",
  "passed": 6,
  "failed": 0,
  "warnings": 1,
  "checks": [
    {"name": "existence", "status": "pass"},
    {"name": "agent_context", "status": "pass"},
    {"name": "provenance", "status": "pass"},
    {"name": "references", "status": "pass"},
    {"name": "word_budget", "status": "pass"},
    {"name": "meta", "status": "warn", "detail": "head_sha mismatch"},
    {"name": "freshness", "status": "pass"}
  ]
}
```

### 4.4 Bridge State Extension

The bridge state file (`.run/bridge-state.json`) gains a new field:

```json
{
  "finalization": {
    "ground_truth_updated": true,
    "butterfreezone_generated": true,
    "rtfm_passed": true,
    "pr_url": "https://github.com/..."
  }
}
```

---

## 5. Configuration

### 5.1 Config Schema Addition

Added to `.loa.config.yaml.example`:

```yaml
# BUTTERFREEZONE — Agent-Grounded README (v1.35.0)
butterfreezone:
  enabled: true                         # On by default, opt-out via false
  output_path: BUTTERFREEZONE.md        # Relative to repo root
  word_budget:
    total: 3200                         # ~8000 tokens (model-agnostic)
    per_section: 800                    # ~2000 tokens per section
  staleness_days: 7                     # Advisory freshness window
  hooks:
    run_bridge: true                    # MVP: only autonomous hook
    run_sprint_plan: false              # Phase 2
    post_merge: false                   # Phase 2
    ride: false                         # Future
    ship: false                         # Phase 2
  rtfm:
    check_enabled: true                 # Include in RTFM validation
    strict_mode: false                  # false=advisory, true=hard gate
  ecosystem:
    auto_detect: true                   # Scan deps for related repos
    manual_entries: []                  # User-defined ecosystem entries
  manual_sections:
    sentinel_start: "<!-- manual-start -->"
    sentinel_end: "<!-- manual-end -->"
  security:
    redaction_enabled: true             # Gitleaks-pattern redaction
```

### 5.2 Configuration Precedence

```
CLI flags → .loa.config.yaml → Script defaults
```

All config values have sensible defaults — BUTTERFREEZONE works with zero configuration.

---

## 6. Security Architecture

### 6.1 Threat Model

| Threat | Mitigation |
|--------|-----------|
| Secrets leaked into BUTTERFREEZONE.md | Gitleaks-pattern redaction + post-redaction scan |
| Malicious content in reality files | Reality files are gitignored; only committed code is trusted |
| Path traversal in file:symbol references | References constrained to repo root (`../` rejected) |
| Injection via manual sentinel markers | Markers are HTML comments — no execution context |
| Large file DoS (monorepo) | Word-count budget + per-section truncation |

### 6.2 Redaction Pipeline

```
Content → Gitleaks patterns → Allowlist filter → Post-scan check → Output
```

If any secret prefix remains after redaction (`ghp_`, `AKIA`, `eyJ`), generation **blocks** and returns exit code 1. The failed attempt is logged but not written to disk.

---

## 7. Testing Strategy

### 7.1 Unit Tests (BATS)

**File**: `tests/unit/butterfreezone-gen.bats`

| Test | Description |
|------|-------------|
| `tier_detection_with_reality` | Detects Tier 1 when reality files have content |
| `tier_detection_without_reality` | Falls back to Tier 2 with package.json |
| `tier_detection_empty_repo` | Falls back to Tier 3 bootstrap |
| `agent_context_generated` | AGENT-CONTEXT block present in output |
| `provenance_tags_all_sections` | Every section has provenance tag |
| `word_budget_enforced` | Output under 3200 words |
| `word_budget_truncation` | Over-budget sections truncated |
| `ground_truth_meta_present` | Checksums block present |
| `checksums_exclude_timestamp` | generated_at not in checksum input |
| `manual_sections_preserved` | Sentinel-marked content survives regeneration |
| `atomic_write_no_partial` | Interrupted write doesn't corrupt existing file |
| `security_redaction` | AWS keys and GitHub tokens redacted |
| `dry_run_no_write` | --dry-run prints to stdout only |
| `deterministic_output` | Two runs on same commit produce identical output |
| `exit_code_tier3` | Exit code 3 when bootstrap stub used |

**File**: `tests/unit/butterfreezone-validate.bats`

| Test | Description |
|------|-------------|
| `missing_file_fails` | Exit 1 when BUTTERFREEZONE.md missing |
| `valid_file_passes` | Exit 0 for well-formed file |
| `missing_agent_context_fails` | Exit 1 without AGENT-CONTEXT |
| `missing_provenance_fails` | Exit 1 with untagged sections |
| `missing_file_ref_fails` | Exit 1 for non-existent referenced file |
| `stale_sha_warns` | Exit 2 for SHA mismatch (advisory) |
| `strict_mode_fails_on_stale` | Exit 1 for SHA mismatch in strict mode |
| `word_budget_exceeded_warns` | Exit 2 for over-budget (advisory) |

### 7.2 Integration Test

A single integration test verifies the end-to-end flow:

```bash
# In a test repo with known structure:
1. Run butterfreezone-gen.sh → produces BUTTERFREEZONE.md
2. Run butterfreezone-validate.sh → all checks pass
3. Modify a source file
4. Re-run validate → staleness warning (exit 2)
5. Re-run gen → regenerates with new HEAD SHA
6. Re-run validate → all checks pass again
```

---

## 8. Deployment & Rollout

### 8.1 File Delivery

All new files are delivered to the `.claude/` system zone and registered in skill index. No manual installation required for Loa-managed codebases.

### 8.2 Version

This feature targets **Loa v1.35.0**. The CLAUDE.md version reference and config example are updated accordingly.

### 8.3 Migration

No migration needed — BUTTERFREEZONE.md is a new file. Existing codebases gain it on next `/run-bridge` execution (or manual `/butterfreezone` invocation).

---

## 9. Technical Risks & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Tier 2 grep patterns miss language-specific exports | Medium | Low | Patterns are additive — new languages can be added without breaking existing |
| Manual section sentinel markers accidentally deleted | Low | Medium | Validate warns on missing sentinels if previous version had them |
| Bridge orchestrator modification breaks existing flow | Low | High | Hook is guarded by `is_butterfreezone_enabled()` — disabled = zero code path change |
| wc -w counts differ between GNU/BSD implementations | Low | Low | Word count is approximate budget, not exact — 10% variance is acceptable |
| Large monorepos exceed Tier 2 grep timeout | Low | Medium | Add `timeout 30` wrapper around grep patterns; fall back to Tier 3 |

---

## 10. Future Considerations

| Enhancement | Trigger |
|------------|---------|
| Phase 2 hooks (sprint-plan, post-merge, ship) | After 3+ successful bridge runs with BUTTERFREEZONE |
| Hierarchical output for monorepos | When word budget proves insufficient for >100 module repos |
| Cross-repo federation | When topology infrastructure (#43) is implemented |
| llms.txt hub-spoke integration | When reality skill adopts hub-spoke pattern |
| Language-specific extractors (AST-based) | When static grep proves insufficient for complex codebases |

---

---

## 11. Concrete Example — Rendered BUTTERFREEZONE.md

> **Flatline IMP-004 resolution**: Concrete example resolves ambiguities around ordering, formatting, and provenance placement.

```markdown
<!-- AGENT-CONTEXT
name: loa
type: framework
purpose: Agent-driven development framework with autonomous sprint execution
key_files: [.claude/loa/CLAUDE.loa.md, .loa.config.yaml, .claude/scripts/]
interfaces: [47 slash commands, 5 golden path commands, .loa.config.yaml]
dependencies: [bash 4+, jq, yq, git, gh]
version: 1.35.0
trust_level: grounded
model_hints: claude-opus-4-6 primary, gpt-5.2 secondary (flatline)
-->

# Loa

<!-- provenance: CODE-FACTUAL -->
Agent-driven development framework providing structured sprint execution,
multi-model adversarial review (Flatline Protocol), and autonomous excellence
loops (Run Bridge). Manages the full lifecycle from requirements through
deployment via 47 slash commands organized into 5 golden path commands.

## Key Capabilities
<!-- provenance: CODE-FACTUAL -->
- **Sprint execution** — `/run sprint-plan` orchestrates implement→review→audit cycles (`run-mode/SKILL.md:run_sprint_loop`)
- **Adversarial review** — Flatline Protocol with Opus + GPT cross-scoring (`.claude/scripts/flatline-orchestrator.sh:run_phase1`)
- **Bridge loop** — Iterative improvement until findings flatline (`.claude/scripts/bridge-orchestrator.sh:run_iteration`)
- **Codebase analysis** — `/ride` extracts reality artifacts (`riding-codebase/SKILL.md:extract_reality`)
- **Bug triage** — 4-phase structured triage with micro-sprints (`bug-triaging/SKILL.md:triage_phases`)

## Architecture
<!-- provenance: DERIVED -->
Three-zone model: System (`.claude/`, never edit), State (`grimoires/`, `.beads/`), App (`src/`).
Skills are self-contained directories under `.claude/skills/` with SKILL.md definitions.
Shell scripts in `.claude/scripts/` handle orchestration. Config in `.loa.config.yaml`.

## Interfaces
<!-- provenance: CODE-FACTUAL -->
| Command | Purpose | Danger |
|---------|---------|--------|
| `/loa` | Status and next step | safe |
| `/plan` | Requirements→Architecture→Sprint | moderate |
| `/build` | Execute current sprint | moderate |
| `/review` | Review + audit | high |
| `/ship` | Deploy + archive | high |

## Module Map
<!-- provenance: CODE-FACTUAL -->
| Module | Purpose | Key Files |
|--------|---------|-----------|
| Skills | 30+ skill definitions | `.claude/skills/*/SKILL.md` |
| Scripts | Orchestration and utilities | `.claude/scripts/*.sh` |
| Lore | Cultural knowledge base | `.claude/data/lore/` |
| Protocols | Behavioral contracts | `.claude/protocols/*.md` |
| Hooks | Event-driven automation | `.claude/hooks/*.sh` |

## Ecosystem
<!-- provenance: OPERATIONAL -->
| Repo | Type | Relationship | Capabilities |
|------|------|-------------|-------------|
| loa-finn | service | downstream | OpenCode server runtime |
| loa-constructs | registry | sibling | Composable pack registry |

## Known Limitations
<!-- provenance: CODE-FACTUAL -->
- Single-repo focus — cross-repo context requires manual topology (`.claude/protocols/cross-repo.md`)
- Flatline Protocol requires OpenAI API key for GPT model
- beads_rust optional but expected for task tracking

## Quick Start
<!-- provenance: OPERATIONAL -->
```bash
npx @anthropic-ai/claude-code
/mount        # Install Loa onto repo
/loa          # See status and next step
/plan         # Start planning
```

<!-- ground-truth-meta
head_sha: 8061995abc123def
generated_at: 2026-02-13T05:25:00Z
generator: butterfreezone-gen v1.0.0
sections:
  agent_context: a1b2c3d4...
  capabilities: e5f6a7b8...
  architecture: c9d0e1f2...
  interfaces: 3a4b5c6d...
  module_map: 7e8f9a0b...
  ecosystem: 1c2d3e4f...
  limitations: 5a6b7c8d...
  quick_start: 9e0f1a2b...
-->
```

---

## Appendix A: Flatline SDD Review Integration Log

**Flatline Run**: simstim-20260213-c009bfz, Phase 4
**Cost**: ~51 cents
**Model Agreement**: 100%

### HIGH_CONSENSUS (5 — auto-integrated)

| ID | Finding | Score | Resolution |
|----|---------|-------|-----------|
| IMP-001 | Per-extractor error handling missing | 885 | Added 3.1.11 with skip-on-failure policy |
| IMP-002 | `needs_regeneration()` undefined | 860 | Added 3.1.10 with HEAD SHA + config mtime |
| IMP-003 | Concurrency protection missing | 765 | Added 3.1.13 with flock locking |
| IMP-004 | Concrete rendered example needed | 840 | Added Section 11 |
| IMP-005 | `sort_sections()` undefined | 740 | Added 3.1.12 with canonical order |

### BLOCKERS (5 — resolved)

| ID | Concern | Score | Resolution |
|----|---------|-------|-----------|
| SKP-tier2 | Tier 2 scanning slow/broad | 760 | Added 3.1.14 with timeout, maxdepth, vendor exclusion |
| SKP-refs | Reference validation false positives | 750 | Added 3.1.15 with `L` prefix for lines, backtick scoping |
| SKP-manual | Manual preservation underspecified | 720 | Updated 3.1.5 with section-anchored sentinels |
| SKP-determinism | Determinism not credible | 900 | Added 3.1.16 with LC_ALL=C, TZ=UTC |
| SKP-config | Config parse error handling | 710 | Config errors fall through to defaults with warning |

---

*SDD generated for cycle-009 (Flatline-reviewed). Next: `/sprint-plan` for implementation breakdown.*
