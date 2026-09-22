#!/usr/bin/env bash
# =============================================================================
# construct-index-gen.sh — Generate construct index from installed packs
# =============================================================================
# Scans .claude/constructs/packs/ for installed packs, extracts metadata from
# manifest.json (and optionally construct.yaml), aggregates skill capabilities,
# and writes a unified index to .run/construct-index.yaml.
#
# Usage:
#   construct-index-gen.sh                     # Generate YAML index
#   construct-index-gen.sh --json              # Generate JSON index
#   construct-index-gen.sh --output PATH       # Custom output path
#   construct-index-gen.sh --quiet             # Suppress log output
#
# Exit Codes:
#   0 = success
#   1 = no packs found
#   2 = script error
#
# Environment:
#   LOA_PACKS_DIR     Override packs directory
#   LOA_SKILLS_DIR    Override skills directory
#   PROJECT_ROOT      Override project root
#
# Sources: cycle-051, Sprint 103
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

# Source shared libraries
if [[ -f "$SCRIPT_DIR/compat-lib.sh" ]]; then
    source "$SCRIPT_DIR/compat-lib.sh"
fi

if [[ -f "$SCRIPT_DIR/yq-safe.sh" ]]; then
    source "$SCRIPT_DIR/yq-safe.sh"
fi

# =============================================================================
# Configuration
# =============================================================================

PACKS_DIR="${LOA_PACKS_DIR:-$PROJECT_ROOT/.claude/constructs/packs}"
SKILLS_DIR="${LOA_SKILLS_DIR:-$PROJECT_ROOT/.claude/skills}"
DEFAULT_OUTPUT="$PROJECT_ROOT/.run/construct-index.yaml"

# =============================================================================
# CLI Flags
# =============================================================================

OUTPUT_PATH=""
JSON_OUTPUT=false
QUIET=false
VALIDATE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json) JSON_OUTPUT=true; shift ;;
        --output) OUTPUT_PATH="$2"; shift 2 ;;
        --quiet) QUIET=true; shift ;;
        --validate) VALIDATE=true; shift ;;
        -h|--help)
            echo "Usage: construct-index-gen.sh [--json] [--output PATH] [--quiet] [--validate]"
            echo "  --json       Output JSON instead of YAML"
            echo "  --output     Write to custom path (default: .run/construct-index.yaml)"
            echo "  --quiet      Suppress log output"
            echo "  --validate   Validate generated index (check required fields, schema integrity)"
            exit 0
            ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

# Set output path
if [[ -z "$OUTPUT_PATH" ]]; then
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        OUTPUT_PATH="${DEFAULT_OUTPUT%.yaml}.json"
    else
        OUTPUT_PATH="$DEFAULT_OUTPUT"
    fi
fi

# =============================================================================
# Logging
# =============================================================================

log() {
    if [[ "$QUIET" != "true" ]]; then
        echo "$@" >&2
    fi
}

warn() {
    echo "WARNING: $*" >&2
}

# =============================================================================
# Capability Aggregation (Task 103.2)
# =============================================================================

# Extract frontmatter from a SKILL.md file
# Args: $1 = path to SKILL.md
# Returns: frontmatter YAML on stdout
extract_frontmatter() {
    local skill_md="$1"
    if [[ ! -f "$skill_md" ]]; then
        return 1
    fi
    awk '/^---$/{if(n++) exit; next} n' "$skill_md"
}

# Aggregate capabilities from all skills in a pack
# Args: $1 = pack slug, $2 = pack_dir (path to pack directory)
# Returns: JSON object with aggregated capabilities on stdout
aggregate_capabilities() {
    local pack_slug="$1"
    local pack_dir="$2"
    local skills_json="$3"  # JSON array of skill objects from manifest

    # Start with empty aggregation
    local agg_schema_version=0
    local agg_read_files="false"
    local agg_search_code="false"
    local agg_write_files="false"
    local agg_execute_commands="false"
    local agg_web_access="false"
    local agg_user_interaction="false"
    local agg_agent_spawn="false"
    local agg_task_management="false"
    local agg_execute_commands_is_object="false"
    local agg_allowed_commands="[]"
    local found_any_caps="false"

    # Iterate over skills
    local skill_count
    skill_count=$(echo "$skills_json" | jq -r 'length')

    local i=0
    while [[ $i -lt $skill_count ]]; do
        local skill_slug
        skill_slug=$(echo "$skills_json" | jq -r ".[$i].slug // empty")

        if [[ -z "$skill_slug" ]]; then
            i=$((i + 1))
            continue
        fi

        # Look for SKILL.md in the skills directory (symlinked or direct)
        local skill_md=""
        if [[ -f "$SKILLS_DIR/$skill_slug/SKILL.md" ]]; then
            skill_md="$SKILLS_DIR/$skill_slug/SKILL.md"
        elif [[ -f "$pack_dir/skills/$skill_slug/SKILL.md" ]]; then
            skill_md="$pack_dir/skills/$skill_slug/SKILL.md"
        fi

        if [[ -z "$skill_md" ]]; then
            i=$((i + 1))
            continue
        fi

        # Extract frontmatter
        local frontmatter
        frontmatter=$(extract_frontmatter "$skill_md") || { i=$((i + 1)); continue; }

        if [[ -z "$frontmatter" ]]; then
            i=$((i + 1))
            continue
        fi

        # Check if capabilities field exists
        if ! echo "$frontmatter" | grep -q "^capabilities:"; then
            i=$((i + 1))
            continue
        fi

        found_any_caps="true"

        # Parse capabilities using yq (convert frontmatter to temp file)
        local tmp_fm
        tmp_fm=$(mktemp)
        echo "$frontmatter" > "$tmp_fm"

        # Get schema_version
        local sv
        sv=$(yq eval '.capabilities.schema_version // 0' "$tmp_fm" 2>/dev/null || echo "0")
        if [[ "$sv" -gt "$agg_schema_version" ]] 2>/dev/null; then
            agg_schema_version="$sv"
        fi

        # Union semantics: if ANY skill has true, aggregate is true
        local val
        for field in read_files search_code write_files web_access user_interaction agent_spawn task_management; do
            val=$(yq eval ".capabilities.$field // false" "$tmp_fm" 2>/dev/null || echo "false")
            if [[ "$val" == "true" ]]; then
                eval "agg_${field}=true"
            fi
        done

        # Special handling for execute_commands
        local exec_type
        exec_type=$(yq eval '.capabilities.execute_commands | type' "$tmp_fm" 2>/dev/null || echo "!!null")

        if [[ "$exec_type" == "!!bool" || "$exec_type" == "boolean" ]]; then
            val=$(yq eval '.capabilities.execute_commands' "$tmp_fm" 2>/dev/null || echo "false")
            if [[ "$val" == "true" ]]; then
                agg_execute_commands="true"
            fi
        elif [[ "$exec_type" == "!!map" || "$exec_type" == "object" ]]; then
            if [[ "$agg_execute_commands" != "true" ]]; then
                agg_execute_commands_is_object="true"
                # Merge allowed lists
                local new_allowed
                new_allowed=$(yq eval -o=json '.capabilities.execute_commands.allowed // []' "$tmp_fm" 2>/dev/null || echo "[]")
                if [[ "$new_allowed" != "[]" && "$new_allowed" != "null" ]]; then
                    agg_allowed_commands=$(jq -n --argjson existing "$agg_allowed_commands" --argjson new_cmds "$new_allowed" '$existing + $new_cmds | unique_by(.command)')
                fi
            fi
        fi

        rm -f "$tmp_fm"
        i=$((i + 1))
    done

    if [[ "$found_any_caps" != "true" ]]; then
        echo "{}"
        return 0
    fi

    # Build result JSON
    local exec_commands_json
    if [[ "$agg_execute_commands" == "true" ]]; then
        exec_commands_json="true"
    elif [[ "$agg_execute_commands_is_object" == "true" ]]; then
        exec_commands_json=$(jq -n --argjson allowed "$agg_allowed_commands" '{"allowed": $allowed}')
    else
        exec_commands_json="false"
    fi

    jq -n \
        --argjson schema_version "$agg_schema_version" \
        --argjson read_files "$agg_read_files" \
        --argjson search_code "$agg_search_code" \
        --argjson write_files "$agg_write_files" \
        --argjson execute_commands "$exec_commands_json" \
        --argjson web_access "$agg_web_access" \
        --argjson user_interaction "$agg_user_interaction" \
        --argjson agent_spawn "$agg_agent_spawn" \
        --argjson task_management "$agg_task_management" \
        '{
            schema_version: $schema_version,
            read_files: $read_files,
            search_code: $search_code,
            write_files: $write_files,
            execute_commands: $execute_commands,
            web_access: $web_access,
            user_interaction: $user_interaction,
            agent_spawn: $agent_spawn,
            task_management: $task_management
        }'
}

# =============================================================================
# Index Generation (Task 103.1)
# =============================================================================

# Process a single pack directory into a JSON object
# Args: $1 = pack directory path
# Returns: JSON object on stdout
process_pack() {
    local pack_dir="$1"
    local pack_slug
    pack_slug=$(basename "$pack_dir")

    local manifest="$pack_dir/manifest.json"
    if [[ ! -f "$manifest" ]]; then
        return 1
    fi

    # Validate manifest is valid JSON
    if ! jq empty "$manifest" 2>/dev/null; then
        warn "Malformed manifest.json in pack '$pack_slug' — skipping"
        return 1
    fi

    log "  Processing pack: $pack_slug"

    # Extract base fields from manifest.json
    local name version description tags_json skills_json commands_json events_json
    name=$(jq -r '.name // ""' "$manifest")
    version=$(jq -r '.version // ""' "$manifest")
    description=$(jq -r '.description // ""' "$manifest")
    tags_json=$(jq -c '.tags // []' "$manifest")
    skills_json=$(jq -c '.skills // []' "$manifest")
    commands_json=$(jq -c '.commands // []' "$manifest")
    events_json=$(jq -c '.events // {}' "$manifest")

    # Extract events into emits/consumes arrays
    local emits_json consumes_json
    emits_json=$(jq -c '.events.emits // [] | [.[].name // empty]' "$manifest" 2>/dev/null || echo "[]")
    consumes_json=$(jq -c '.events.consumes // [] | [.[].event // empty]' "$manifest" 2>/dev/null || echo "[]")

    # Initialize overlay fields
    local writes_json="[]"
    local reads_json="[]"
    local gates_json="{}"

    # Check for construct.yaml overlay
    local construct_yaml="$pack_dir/construct.yaml"
    if [[ -f "$construct_yaml" ]] && command -v yq &>/dev/null; then
        log "    Merging construct.yaml"

        # construct.yaml fields win on overlap
        local cy_name cy_version cy_description
        cy_name=$(yq eval '.name // ""' "$construct_yaml" 2>/dev/null || echo "")
        cy_version=$(yq eval '.version // ""' "$construct_yaml" 2>/dev/null || echo "")
        cy_description=$(yq eval '.description // ""' "$construct_yaml" 2>/dev/null || echo "")

        [[ -n "$cy_name" && "$cy_name" != "null" ]] && name="$cy_name"
        [[ -n "$cy_version" && "$cy_version" != "null" ]] && version="$cy_version"
        [[ -n "$cy_description" && "$cy_description" != "null" ]] && description="$cy_description"

        # Extract writes, reads, gates
        writes_json=$(yq eval -o=json '.writes // []' "$construct_yaml" 2>/dev/null || echo "[]")
        reads_json=$(yq eval -o=json '.reads // []' "$construct_yaml" 2>/dev/null || echo "[]")
        gates_json=$(yq eval -o=json '.gates // {}' "$construct_yaml" 2>/dev/null || echo "{}")

        # Extract tags from construct.yaml if present
        local cy_tags
        cy_tags=$(yq eval -o=json '.tags // null' "$construct_yaml" 2>/dev/null || echo "null")
        if [[ "$cy_tags" != "null" ]]; then
            tags_json="$cy_tags"
        fi
    fi

    # Scan for persona file
    local persona_path="null"
    for skill_entry in $(echo "$skills_json" | jq -r '.[].slug // empty'); do
        for candidate in "$SKILLS_DIR/$skill_entry/persona.md" "$SKILLS_DIR/$skill_entry/PERSONA.md" \
                         "$pack_dir/skills/$skill_entry/persona.md" "$pack_dir/skills/$skill_entry/PERSONA.md"; do
            if [[ -f "$candidate" ]]; then
                persona_path="$candidate"
                break 2
            fi
        done
    done

    # Determine quick_start (first command name)
    local quick_start="null"
    local first_cmd
    first_cmd=$(echo "$commands_json" | jq -r '.[0].name // empty')
    if [[ -n "$first_cmd" ]]; then
        quick_start="$first_cmd"
    fi

    # Aggregate capabilities (Task 103.2)
    local aggregated_caps
    aggregated_caps=$(aggregate_capabilities "$pack_slug" "$pack_dir" "$skills_json")

    # Build the construct entry JSON using jq --arg for safety
    jq -n \
        --arg slug "$pack_slug" \
        --arg name "$name" \
        --arg version "$version" \
        --arg description "$description" \
        --arg persona_path "$persona_path" \
        --arg quick_start "$quick_start" \
        --argjson skills "$skills_json" \
        --argjson commands "$commands_json" \
        --argjson writes "$writes_json" \
        --argjson reads "$reads_json" \
        --argjson gates "$gates_json" \
        --argjson emits "$emits_json" \
        --argjson consumes "$consumes_json" \
        --argjson tags "$tags_json" \
        --argjson aggregated_capabilities "$aggregated_caps" \
        '{
            slug: $slug,
            name: $name,
            version: $version,
            description: $description,
            persona_path: (if $persona_path == "null" then null else $persona_path end),
            quick_start: (if $quick_start == "null" then null else $quick_start end),
            skills: $skills,
            commands: $commands,
            writes: $writes,
            reads: $reads,
            gates: $gates,
            events: {
                emits: $emits,
                consumes: $consumes
            },
            tags: $tags,
            composes_with: [],
            aggregated_capabilities: $aggregated_capabilities
        }'
}

# Compute composes_with by finding write/read overlaps between constructs
# Args: reads JSON array from stdin
# Returns: updated JSON with composes_with populated
compute_composition() {
    local constructs_json="$1"

    # For each construct, find others whose writes overlap with its reads (and vice versa)
    jq '
        . as $all |
        [range(length)] | map(
            . as $i |
            $all[$i] as $current |
            $current + {
                composes_with: [
                    $all | to_entries[] |
                    select(.key != $i) |
                    select(
                        (.value.writes as $w | $current.reads | any(. as $r | $w | index($r))) or
                        (.value.reads as $r | $current.writes | any(. as $w | $r | index($w)))
                    ) |
                    .value.slug
                ] | unique
            }
        )
    ' <<< "$constructs_json"
}

# =============================================================================
# Main
# =============================================================================

main() {
    log "Generating construct index..."

    # Check packs directory exists
    if [[ ! -d "$PACKS_DIR" ]]; then
        warn "Packs directory not found: $PACKS_DIR"
        echo "constructs: []" > "$OUTPUT_PATH" 2>/dev/null || true
        exit 1
    fi

    # Find all packs with manifest.json
    local pack_dirs=()
    for pack_path in "$PACKS_DIR"/*/; do
        [[ -d "$pack_path" ]] || continue
        if [[ -f "$pack_path/manifest.json" ]]; then
            pack_dirs+=("$pack_path")
        fi
    done

    if [[ ${#pack_dirs[@]} -eq 0 ]]; then
        log "No packs found in $PACKS_DIR"
        mkdir -p "$(dirname "$OUTPUT_PATH")"
        echo "constructs: []" > "$OUTPUT_PATH"
        exit 1
    fi

    local pack_count=${#pack_dirs[@]}
    log "Found $pack_count pack(s)"

    # Process each pack
    local constructs_json="[]"
    for pack_path in "${pack_dirs[@]}"; do
        local entry_json
        entry_json=$(process_pack "$pack_path") || {
            warn "Failed to process pack at $pack_path — skipping"
            continue
        }

        if [[ -n "$entry_json" ]]; then
            constructs_json=$(jq --argjson entry "$entry_json" '. + [$entry]' <<< "$constructs_json")
        fi
    done

    # Compute composes_with relationships
    constructs_json=$(compute_composition "$constructs_json")

    # Wrap in top-level object
    local index_json
    index_json=$(jq -n \
        --argjson constructs "$constructs_json" \
        --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --argjson pack_count "$pack_count" \
        '{
            metadata: {
                generated_at: $generated_at,
                generator_version: "1.0.0",
                pack_count: $pack_count
            },
            constructs: $constructs
        }')

    # Ensure output directory exists
    mkdir -p "$(dirname "$OUTPUT_PATH")"

    # Write output
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        echo "$index_json" > "$OUTPUT_PATH"
    else
        # Convert JSON to YAML using yq if available, else write JSON
        if command -v yq &>/dev/null; then
            echo "$index_json" | yq eval -P '.' > "$OUTPUT_PATH"
        else
            # Fallback: write JSON with .yaml extension
            echo "$index_json" > "$OUTPUT_PATH"
            warn "yq not available — wrote JSON to YAML file"
        fi
    fi

    log "Index written to $OUTPUT_PATH"

    # Validate if requested
    if [[ "$VALIDATE" == "true" ]]; then
        validate_index "$OUTPUT_PATH"
        return $?
    fi

    return 0
}

# =============================================================================
# Index Validation (--validate flag)
# =============================================================================
# Checks that the generated index has valid structure and required fields.
# Catches malformed manifests before downstream consumers choke on the index.

validate_index() {
    local index_file="$1"
    local errors=0

    if [[ ! -f "$index_file" ]]; then
        echo "VALIDATE ERROR: Index file not found: $index_file" >&2
        return 1
    fi

    # Check valid YAML/JSON
    if ! jq empty "$index_file" 2>/dev/null && ! yq eval '.' "$index_file" &>/dev/null; then
        echo "VALIDATE ERROR: Index is not valid YAML or JSON" >&2
        return 1
    fi

    # Parse as JSON (convert YAML if needed)
    local index_json
    if jq empty "$index_file" 2>/dev/null; then
        index_json=$(cat "$index_file")
    else
        index_json=$(yq eval -o=json '.' "$index_file" 2>/dev/null) || {
            echo "VALIDATE ERROR: Cannot parse index" >&2
            return 1
        }
    fi

    # Check metadata
    local gen_at
    gen_at=$(echo "$index_json" | jq -r '.metadata.generated_at // empty') || true
    if [[ -z "$gen_at" ]]; then
        echo "VALIDATE WARN: Missing metadata.generated_at" >&2
        errors=$((errors + 1))
    fi

    # Check each construct has required fields
    local count
    count=$(echo "$index_json" | jq '.constructs | length') || count=0

    local i=0
    while [[ $i -lt $count ]]; do
        local slug name version
        slug=$(echo "$index_json" | jq -r ".constructs[$i].slug // empty")
        name=$(echo "$index_json" | jq -r ".constructs[$i].name // empty")
        version=$(echo "$index_json" | jq -r ".constructs[$i].version // empty")

        if [[ -z "$slug" ]]; then
            echo "VALIDATE ERROR: Construct at index $i missing slug" >&2
            errors=$((errors + 1))
        fi
        if [[ -z "$name" ]]; then
            echo "VALIDATE WARN: Construct '$slug' missing name" >&2
        fi
        if [[ -z "$version" ]]; then
            echo "VALIDATE WARN: Construct '$slug' missing version" >&2
        fi

        # Check skills is an array
        local skills_type
        skills_type=$(echo "$index_json" | jq -r ".constructs[$i].skills | type") || skills_type="null"
        if [[ "$skills_type" != "array" && "$skills_type" != "null" ]]; then
            echo "VALIDATE ERROR: Construct '$slug' skills is $skills_type, expected array" >&2
            errors=$((errors + 1))
        fi

        # Check commands is an array
        local cmds_type
        cmds_type=$(echo "$index_json" | jq -r ".constructs[$i].commands | type") || cmds_type="null"
        if [[ "$cmds_type" != "array" && "$cmds_type" != "null" ]]; then
            echo "VALIDATE ERROR: Construct '$slug' commands is $cmds_type, expected array" >&2
            errors=$((errors + 1))
        fi

        i=$((i + 1))
    done

    if [[ $errors -gt 0 ]]; then
        echo "VALIDATE: $count constructs checked, $errors errors" >&2
        return 1
    fi

    if [[ "$QUIET" != "true" ]]; then
        echo "VALIDATE: $count constructs checked, all valid"
    fi
    return 0
}

# Only run main if not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
