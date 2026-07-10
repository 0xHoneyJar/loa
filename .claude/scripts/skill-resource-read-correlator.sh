#!/usr/bin/env bash
# =============================================================================
# skill-resource-read-correlator.sh — Offline read-vs-manifest correlator
# =============================================================================
# cycle-116 Wave-2 D2f: mines existing Claude Code session transcripts
# (~/.claude/projects/<cwd-slug>/*.jsonl) for `Skill` tool_use invocations
# followed by `Read` tool_use calls, and correlates the reads against each
# invoked skill's declared `inputs:` manifest paths (primary) and its
# `resources/` directory files (extension).
#
# Zero new hooks, zero PreToolUse/PostToolUse registration, zero per-turn
# cost — this reuses transcript data the harness already writes for free
# (see .claude/loa/reference/hooks-reference.md and mutation-logger.sh,
# neither of which capture Read tool calls today).
#
# PII posture: extracts ONLY the `name` field and `input.skill` /
# `input.file_path` values of tool_use blocks. Never reads, stores, or
# prints message text, Skill `args`, or any other content.
#
# Sidechain lines (isSidechain: true — subagent/Task transcripts embedded in
# the parent session) are excluded: their tool calls belong to a different
# actor than the top-level skill invocation and would misattribute reads.
#
# Usage:
#   skill-resource-read-correlator.sh [--project-dir DIR] [--json]
#
#   --project-dir DIR   Directory containing *.jsonl session transcripts.
#                        Default: ~/.claude/projects/<slug> where slug is
#                        PROJECT_ROOT with '/' replaced by '-' (the same
#                        convention Claude Code itself uses).
#   --json               Emit a JSON array (one object per invoked skill)
#                        instead of a human-readable report.
#
# Env overrides (matching validate-skill-capabilities.sh convention):
#   PROJECT_ROOT   Repo root used to resolve declared `inputs:` paths and
#                  the default transcript slug. Default: repo root of this
#                  script.
#   SKILLS_DIR     Directory of skill subdirectories (each containing a
#                  SKILL.md). Default: $PROJECT_ROOT/.claude/skills
#
# Output: a JSON array (or, without --json, one report block per skill).
# Only skills observed being invoked at least once are included. Each
# element has: skill, invocations, inputs_read, inputs_not_read,
# resources_read, resources_never_read, ratio.
#
# Exit status: 0 always, including the no-op case where no transcripts are
# found (expected in CI/sandboxes) — this is a diagnostic tool, not a gate.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
SKILLS_DIR="${SKILLS_DIR:-$PROJECT_ROOT/.claude/skills}"

JSON_OUTPUT=false
PROJECT_DIR_OVERRIDE=""

usage() {
    grep '^#' "${BASH_SOURCE[0]}" | sed -n '2,36p' | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-dir)
            PROJECT_DIR_OVERRIDE="${2:?--project-dir requires a value}"
            shift 2
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "skill-resource-read-correlator: unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

if [[ -n "$PROJECT_DIR_OVERRIDE" ]]; then
    TRANSCRIPT_DIR="$PROJECT_DIR_OVERRIDE"
else
    _slug="${PROJECT_ROOT//\//-}"
    TRANSCRIPT_DIR="$HOME/.claude/projects/$_slug"
fi

no_op() {
    local message="$1"
    if $JSON_OUTPUT; then
        echo "[]"
    else
        echo "skill-resource-read-correlator: $message Nothing to correlate."
    fi
    exit 0
}

[[ -d "$TRANSCRIPT_DIR" ]] || no_op "No session transcripts found at $TRANSCRIPT_DIR."

shopt -s nullglob
transcripts=("$TRANSCRIPT_DIR"/*.jsonl)
shopt -u nullglob

[[ ${#transcripts[@]} -gt 0 ]] || no_op "No *.jsonl transcripts found in $TRANSCRIPT_DIR."

# -----------------------------------------------------------------------
# Build the skill registry: alias -> canonical dirname, plus each skill's
# declared inputs: manifest paths and resources/ file list, both resolved
# to absolute paths (Read tool_use file_path values are always absolute).
# -----------------------------------------------------------------------
declare -A SKILL_ALIAS      # alias (dirname or frontmatter name:) -> dirname
declare -A SKILL_INPUTS     # dirname -> newline-separated absolute input paths
declare -A SKILL_RESOURCES  # dirname -> newline-separated absolute resource paths
declare -A INVOCATIONS      # dirname -> invocation count
declare -A INPUT_READS      # "dirname\tpath" -> 1 if observed read
declare -A RESOURCE_READS   # "dirname\tpath" -> 1 if observed read
SKILL_ORDER=()              # first-seen order of invoked skills

shopt -s nullglob
skill_manifests=("$SKILLS_DIR"/*/SKILL.md)
shopt -u nullglob

for skill_md in ${skill_manifests[@]+"${skill_manifests[@]}"}; do
    [[ -f "$skill_md" ]] || continue
    skill_dir="$(dirname "$skill_md")"
    dirname="$(basename "$skill_dir")"
    frontmatter="$(awk '/^---$/{if(n++) exit; next} n' "$skill_md")" || frontmatter=""

    SKILL_ALIAS["$dirname"]="$dirname"
    truename="$(printf '%s\n' "$frontmatter" | yq eval '.name // ""' - 2>/dev/null)" || truename=""
    if [[ -n "$truename" && "$truename" != "null" ]]; then
        SKILL_ALIAS["$truename"]="$dirname"
    fi

    n_inputs="$(printf '%s\n' "$frontmatter" | yq eval '.inputs | length' - 2>/dev/null)" || n_inputs=0
    [[ "$n_inputs" =~ ^[0-9]+$ ]] || n_inputs=0
    inputs_list=""
    for ((i = 0; i < n_inputs; i++)); do
        p="$(printf '%s\n' "$frontmatter" | yq eval ".inputs[$i].path // \"\"" - 2>/dev/null)" || p=""
        [[ -n "$p" && "$p" != "null" ]] || continue
        case "$p" in
            /*) abs_p="$p" ;;
            *) abs_p="$PROJECT_ROOT/$p" ;;
        esac
        inputs_list+="$abs_p"$'\n'
    done
    SKILL_INPUTS["$dirname"]="$inputs_list"

    resources_list=""
    if [[ -d "$skill_dir/resources" ]]; then
        while IFS= read -r -d '' f; do
            resources_list+="$f"$'\n'
        done < <(find "$skill_dir/resources" -type f -print0 | LC_ALL=C sort -z)
    fi
    SKILL_RESOURCES["$dirname"]="$resources_list"
done

# -----------------------------------------------------------------------
# Walk each transcript in chronological (line) order. Track the most
# recently invoked skill and attribute subsequent Read file_paths to it.
# Only `name`, `input.skill`, and `input.file_path` are ever extracted —
# no message text/content is read.
# -----------------------------------------------------------------------
for transcript in "${transcripts[@]}"; do
    current_skill=""
    while IFS= read -r event; do
        [[ -n "$event" ]] || continue
        ev_name="$(jq -r '.name // empty' <<<"$event")"
        if [[ "$ev_name" == "Skill" ]]; then
            raw_skill="$(jq -r '.skill // empty' <<<"$event")"
            [[ -n "$raw_skill" ]] || continue
            current_skill="${SKILL_ALIAS[$raw_skill]:-$raw_skill}"
            if [[ -z "${INVOCATIONS[$current_skill]:-}" ]]; then
                SKILL_ORDER+=("$current_skill")
            fi
            INVOCATIONS["$current_skill"]=$(( ${INVOCATIONS[$current_skill]:-0} + 1 ))
        elif [[ "$ev_name" == "Read" ]]; then
            [[ -n "$current_skill" ]] || continue
            file_path="$(jq -r '.file_path // empty' <<<"$event")"
            [[ -n "$file_path" ]] || continue
            while IFS= read -r declared; do
                [[ -n "$declared" ]] || continue
                [[ "$file_path" == "$declared" ]] && INPUT_READS["$current_skill"$'\t'"$declared"]=1
            done <<<"${SKILL_INPUTS[$current_skill]:-}"
            while IFS= read -r entry; do
                [[ -n "$entry" ]] || continue
                [[ "$file_path" == "$entry" ]] && RESOURCE_READS["$current_skill"$'\t'"$entry"]=1
            done <<<"${SKILL_RESOURCES[$current_skill]:-}"
        fi
    # -R + fromjson? tolerates malformed/truncated JSONL lines (a session killed
    # mid-write leaves one); without it a single bad line aborts the whole run
    # with jq exit 5 and zero output (review:D2f HIGH finding, cycle-116).
    done < <(jq -cR '
        fromjson? // empty
        | select(.isSidechain != true)
        | select(.message.content != null)
        | .message.content[]?
        | select(.type == "tool_use" and (.name == "Skill" or .name == "Read"))
        | {name, skill: (.input.skill // null), file_path: (.input.file_path // null)}
    ' "$transcript" 2>/dev/null)
done

[[ ${#SKILL_ORDER[@]} -gt 0 ]] || no_op "No Skill tool_use invocations found under $TRANSCRIPT_DIR."

# -----------------------------------------------------------------------
# Emit the per-skill summary.
# -----------------------------------------------------------------------
if $JSON_OUTPUT; then
    result="[]"
    for dirname in "${SKILL_ORDER[@]}"; do
        inputs_read="[]"; inputs_not_read="[]"
        while IFS= read -r declared; do
            [[ -n "$declared" ]] || continue
            if [[ -n "${INPUT_READS[$dirname$'\t'$declared]:-}" ]]; then
                inputs_read="$(jq -c --arg p "$declared" '. + [$p]' <<<"$inputs_read")"
            else
                inputs_not_read="$(jq -c --arg p "$declared" '. + [$p]' <<<"$inputs_not_read")"
            fi
        done <<<"${SKILL_INPUTS[$dirname]:-}"

        resources_read="[]"; resources_never_read="[]"
        while IFS= read -r entry; do
            [[ -n "$entry" ]] || continue
            if [[ -n "${RESOURCE_READS[$dirname$'\t'$entry]:-}" ]]; then
                resources_read="$(jq -c --arg p "$entry" '. + [$p]' <<<"$resources_read")"
            else
                resources_never_read="$(jq -c --arg p "$entry" '. + [$p]' <<<"$resources_never_read")"
            fi
        done <<<"${SKILL_RESOURCES[$dirname]:-}"

        n_read=$(( $(jq 'length' <<<"$inputs_read") + $(jq 'length' <<<"$resources_read") ))
        n_total=$(( n_read + $(jq 'length' <<<"$inputs_not_read") + $(jq 'length' <<<"$resources_never_read") ))

        entry_json="$(jq -n \
            --arg skill "$dirname" \
            --argjson invocations "${INVOCATIONS[$dirname]}" \
            --argjson inputs_read "$inputs_read" \
            --argjson inputs_not_read "$inputs_not_read" \
            --argjson resources_read "$resources_read" \
            --argjson resources_never_read "$resources_never_read" \
            --arg ratio "$n_read/$n_total" \
            '{skill: $skill, invocations: $invocations, inputs_read: $inputs_read,
              inputs_not_read: $inputs_not_read, resources_read: $resources_read,
              resources_never_read: $resources_never_read, ratio: $ratio}')"
        result="$(jq -c --argjson e "$entry_json" '. + [$e]' <<<"$result")"
    done
    echo "$result"
else
    for dirname in "${SKILL_ORDER[@]}"; do
        inputs_not_read_lines=(); inputs_read_lines=()
        while IFS= read -r declared; do
            [[ -n "$declared" ]] || continue
            if [[ -n "${INPUT_READS[$dirname$'\t'$declared]:-}" ]]; then
                inputs_read_lines+=("$declared")
            else
                inputs_not_read_lines+=("$declared")
            fi
        done <<<"${SKILL_INPUTS[$dirname]:-}"

        resources_never_read_lines=(); resources_read_lines=()
        while IFS= read -r entry; do
            [[ -n "$entry" ]] || continue
            if [[ -n "${RESOURCE_READS[$dirname$'\t'$entry]:-}" ]]; then
                resources_read_lines+=("$entry")
            else
                resources_never_read_lines+=("$entry")
            fi
        done <<<"${SKILL_RESOURCES[$dirname]:-}"

        n_read=$(( ${#inputs_read_lines[@]} + ${#resources_read_lines[@]} ))
        n_total=$(( n_read + ${#inputs_not_read_lines[@]} + ${#resources_never_read_lines[@]} ))

        echo "$dirname: invocations=${INVOCATIONS[$dirname]}"
        for p in ${inputs_read_lines[@]+"${inputs_read_lines[@]}"}; do
            echo "  inputs_read: $p"
        done
        for p in ${inputs_not_read_lines[@]+"${inputs_not_read_lines[@]}"}; do
            echo "  inputs_not_read: $p"
        done
        for p in ${resources_read_lines[@]+"${resources_read_lines[@]}"}; do
            echo "  resources_read: $p"
        done
        for p in ${resources_never_read_lines[@]+"${resources_never_read_lines[@]}"}; do
            echo "  resources_never_read: $p"
        done
        echo "  ratio: $n_read/$n_total"
        echo
    done
fi
