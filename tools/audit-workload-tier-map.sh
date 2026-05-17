#!/usr/bin/env bash
# =============================================================================
# tools/audit-workload-tier-map.sh
# =============================================================================
# cycle-112 Sprint 2 (#167) T2.3 — exhaustiveness audit for workload_tier_map.
#
# Lists dispatching skills (those that reference model-adapter, cheval,
# adversarial-review, flatline-orchestrator, bridgebuilder, or model-invoke
# in their SKILL.md) and diffs the set against
# `.loa.config.yaml::workload_tier_map.entries`. Exits non-zero on missing
# coverage so CI can gate exhaustiveness per PRD AC: "every skill that
# currently dispatches a model".
#
# Usage:
#   tools/audit-workload-tier-map.sh                # human-readable diff
#   tools/audit-workload-tier-map.sh --json         # machine-readable diff
#
# Exit codes:
#   0  exhaustive coverage (all dispatching skills enumerated)
#   1  missing entries (CI gate failure)
#   2  invalid args
#   3  .loa.config.yaml missing or unreadable
#   4  schema validation failure
#  64  required toolchain missing (python3 / yq)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="$PROJECT_ROOT/.loa.config.yaml"
SCHEMA="$PROJECT_ROOT/.claude/data/schemas/workload-tier-map.schema.json"
SKILLS_DIR="$PROJECT_ROOT/.claude/skills"

JSON_MODE=false
for arg in "$@"; do
    case "$arg" in
        --json) JSON_MODE=true ;;
        --help|-h)
            sed -n '3,18p' "${BASH_SOURCE[0]}" | sed 's/^# //;s/^#//'
            exit 0
            ;;
        *)
            echo "[audit-workload-tier-map] error: unknown arg: $arg" >&2
            exit 2
            ;;
    esac
done

# Toolchain checks
if ! command -v python3 >/dev/null 2>&1; then
    echo "[audit-workload-tier-map] error: python3 not found on PATH" >&2
    exit 64
fi

if [[ ! -f "$CONFIG" ]]; then
    echo "[audit-workload-tier-map] error: .loa.config.yaml not found at $CONFIG" >&2
    exit 3
fi

# Schema validation step (runs before exhaustiveness so the operator sees
# the more-specific error if both are wrong).
python3 - "$CONFIG" "$SCHEMA" <<'PY'
import sys, json, yaml, jsonschema

config_path, schema_path = sys.argv[1], sys.argv[2]
try:
    config = yaml.safe_load(open(config_path)) or {}
except yaml.YAMLError as e:
    print(f"[audit-workload-tier-map] error: invalid YAML in {config_path}: {e}", file=sys.stderr)
    sys.exit(3)

wtm = config.get("workload_tier_map")
if not wtm:
    print(f"[audit-workload-tier-map] error: workload_tier_map missing from {config_path}", file=sys.stderr)
    sys.exit(4)

schema = json.load(open(schema_path))
try:
    jsonschema.Draft202012Validator(schema).validate(wtm)
except jsonschema.ValidationError as e:
    print(f"[audit-workload-tier-map] schema violation: {e.message}", file=sys.stderr)
    print(f"  path: {' / '.join(str(p) for p in e.absolute_path)}", file=sys.stderr)
    sys.exit(4)
PY

# Discover dispatching skills.
# Heuristic: any SKILL.md that references known dispatch surfaces
# (model-adapter, cheval, adversarial-review, flatline-orchestrator,
# bridgebuilder, model-invoke). Operators may extend this list in the
# DISPATCH_PATTERNS env var (comma-separated regex alternatives).
DISPATCH_PATTERNS="${DISPATCH_PATTERNS:-model-adapter|cheval|adversarial-review|flatline-orchestrator|bridgebuilder|model-invoke}"

discovered_skills=()
while IFS= read -r path; do
    # Skill name is the dir name (e.g., reviewing-code from
    # .claude/skills/reviewing-code/SKILL.md).
    skill_dir="$(dirname "$path")"
    skill_name="$(basename "$skill_dir")"
    discovered_skills+=("$skill_name")
done < <(find "$SKILLS_DIR" -maxdepth 2 -name SKILL.md 2>/dev/null \
         | xargs grep -lE "$DISPATCH_PATTERNS" 2>/dev/null \
         | sort -u)

# Also include slash-command-style entries for /review-sprint, /audit-sprint
# which match SKILL.md basenames "reviewing-code" / "auditing-security" via
# command files. The operator-visible name in workload_tier_map is the
# slash form because that's what `model-economy-roll-up.sh --skill` accepts.
# Skill→command mapping (operator-facing):
declare -A skill_to_command=(
    ["reviewing-code"]="/review-sprint"
    ["auditing-security"]="/audit-sprint"
)

# Build canonical set: each discovered skill, mapped to its command alias
# if one exists; otherwise the skill dir name.
declare -A canonical_set
for s in "${discovered_skills[@]}"; do
    if [[ -n "${skill_to_command[$s]+x}" ]]; then
        canonical_set["${skill_to_command[$s]}"]=1
    fi
    canonical_set["$s"]=1
done

# Extract entries from config
entries=()
while IFS= read -r e; do
    entries+=("$e")
done < <(python3 -c "
import yaml, sys
c = yaml.safe_load(open('$CONFIG'))
for k in sorted((c.get('workload_tier_map') or {}).get('entries', {}).keys()):
    print(k)
")

declare -A entry_set
for e in "${entries[@]}"; do
    entry_set["$e"]=1
done

# Compute the dispatching-skill set we care about (subset of canonical_set
# that's expected in workload_tier_map). Operators are expected to enumerate
# either the command alias OR the skill dir name, not both. To keep the
# audit fair, we require coverage of the COMMAND ALIAS when one exists,
# else the skill dir name.
expected=()
for s in "${discovered_skills[@]}"; do
    if [[ -n "${skill_to_command[$s]+x}" ]]; then
        expected+=("${skill_to_command[$s]}")
    else
        expected+=("$s")
    fi
done

missing=()
for e in "${expected[@]}"; do
    if [[ -z "${entry_set[$e]+x}" ]]; then
        missing+=("$e")
    fi
done

# Unexpected entries: present in workload_tier_map but not a discovered
# dispatching skill. NOT a hard failure — operators may track skills the
# heuristic doesn't catch — but surfaced for review.
#
# Coverage equivalence: an entry counts as covering the dispatching skill
# whether it uses the slash-command form (/review-sprint) OR the skill-dir
# name (reviewing-code). expected_set includes BOTH forms.
unexpected=()
declare -A expected_set
for e in "${expected[@]}"; do expected_set["$e"]=1; done
for s in "${discovered_skills[@]}"; do
    expected_set["$s"]=1
    if [[ -n "${skill_to_command[$s]+x}" ]]; then
        expected_set["${skill_to_command[$s]}"]=1
    fi
done
for e in "${entries[@]}"; do
    if [[ -z "${expected_set[$e]+x}" ]]; then
        unexpected+=("$e")
    fi
done

if [[ "$JSON_MODE" == "true" ]]; then
    python3 - "$@" <<PY
import json, sys
missing = """${missing[@]+${missing[@]}}""".split()
unexpected = """${unexpected[@]+${unexpected[@]}}""".split()
expected = """${expected[@]+${expected[@]}}""".split()
entries = """${entries[@]+${entries[@]}}""".split()
print(json.dumps({
    "missing": sorted(set(missing)),
    "unexpected": sorted(set(unexpected)),
    "expected_count": len(expected),
    "entries_count": len(entries),
    "verdict": "missing" if missing else ("unexpected" if unexpected else "exhaustive"),
}, indent=2))
PY
else
    echo "workload_tier_map audit"
    echo "  schema:  $SCHEMA"
    echo "  config:  $CONFIG"
    echo "  expected dispatching skills: ${#expected[@]}"
    echo "  configured entries:          ${#entries[@]}"
    if (( ${#missing[@]} > 0 )); then
        echo ""
        echo "  ❌ MISSING (${#missing[@]}):"
        for m in "${missing[@]}"; do echo "    - $m"; done
    fi
    if (( ${#unexpected[@]} > 0 )); then
        echo ""
        echo "  ⚠ UNEXPECTED (${#unexpected[@]} — present in config but not detected by heuristic):"
        for u in "${unexpected[@]}"; do echo "    - $u"; done
    fi
    if (( ${#missing[@]} == 0 )); then
        echo ""
        echo "  ✓ exhaustive coverage"
    fi
fi

if (( ${#missing[@]} > 0 )); then
    exit 1
fi
exit 0
