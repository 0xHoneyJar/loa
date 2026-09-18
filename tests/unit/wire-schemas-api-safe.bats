#!/usr/bin/env bats
# =============================================================================
# tests/unit/wire-schemas-api-safe.bats
#
# cycle-124 Sprint 2 Task 2.1 (FR-7 / SDD §2.3): the five wire schemas under
# .claude/schemas/wire/ stay inside the strict subset both Anthropic
# (output_config.format json_schema) and OpenAI (text.format strict) accept,
# and stay in lock-step with the personas and validators that consume them:
#   W1  valid JSON, root is an object
#   W2  every object node: additionalProperties:false AND required == keys(properties)
#   W3  no unsupported keyword anywhere (minimum, maximum, exclusive*, multipleOf,
#       minLength, maxLength, pattern, patternProperties, format, if/then/else,
#       dependentRequired, dependentSchemas, unevaluated*, minItems/maxItems,
#       uniqueItems, minProperties/maxProperties)
#   W4  dissent enums == the enums adversarial-review.sh advertises in its prompt
#       (label-anchored) AND ⊆ validate_finding() (marker-anchored); severities equal
#   W5  every field a Flatline persona documents is present AND required in its twin
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    WIRE="$PROJECT_ROOT/.claude/schemas/wire"
    ADV="$PROJECT_ROOT/.claude/scripts/adversarial-review.sh"
    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN="$(command -v python3)"
    fi
    FILES=(dissent-review dissent-audit flatline-reviewer flatline-skeptic flatline-scorer)
}

@test "W1: five wire schemas exist, parse as JSON, root is an object" {
    for f in "${FILES[@]}"; do
        [ -f "$WIRE/$f.wire.json" ] || { echo "missing $f.wire.json" >&2; return 1; }
        run jq -e '.type == "object"' "$WIRE/$f.wire.json"
        [ "$status" -eq 0 ] || { echo "$f: root is not an object" >&2; return 1; }
    done
}

@test "W2: every object node is closed (additionalProperties:false) and required == properties" {
    run "$PYTHON_BIN" - "$WIRE" <<'PY'
import json, sys, glob, os
bad = []
def walk(node, path, fname):
    if isinstance(node, dict):
        if node.get("type") == "object":
            if node.get("additionalProperties") is not False:
                bad.append(f"{fname}:{path}: additionalProperties must be false")
            props = node.get("properties") or {}
            if sorted(node.get("required") or []) != sorted(props):
                bad.append(f"{fname}:{path}: required {sorted(node.get('required') or [])} != properties {sorted(props)}")
        for k, v in node.items():
            walk(v, f"{path}/{k}", fname)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            walk(v, f"{path}[{i}]", fname)
for f in sorted(glob.glob(os.path.join(sys.argv[1], "*.wire.json"))):
    walk(json.load(open(f)), "", os.path.basename(f))
print("\n".join(bad)); sys.exit(1 if bad else 0)
PY
    [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
}

@test "W3: no keyword outside the provider-safe subset" {
    run "$PYTHON_BIN" - "$WIRE" <<'PY'
import json, sys, glob, os
FORBIDDEN = {"minimum","maximum","exclusiveMinimum","exclusiveMaximum","multipleOf","minLength","maxLength",
             "pattern","patternProperties","format","if","then","else","dependentRequired","dependentSchemas",
             "unevaluatedProperties","unevaluatedItems","minItems","maxItems","uniqueItems","minProperties",
             "maxProperties","contains","propertyNames","not","oneOf","allOf","$ref","$defs","definitions","default"}
bad = []
def walk(node, path, fname, in_props=False):
    if isinstance(node, dict):
        for k, v in node.items():
            # keys directly under "properties" are field names, not keywords
            if not in_props and k in FORBIDDEN:
                bad.append(f"{fname}:{path}/{k}")
            walk(v, f"{path}/{k}", fname, in_props=(k == "properties"))
    elif isinstance(node, list):
        for i, v in enumerate(node):
            walk(v, f"{path}[{i}]", fname)
for f in sorted(glob.glob(os.path.join(sys.argv[1], "*.wire.json"))):
    walk(json.load(open(f)), "", os.path.basename(f))
print("\n".join(bad)); sys.exit(1 if bad else 0)
PY
    [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
}

# The dissent prompts are single-quoted bash strings, so their enum blocks are
# anchored on the prompt's OWN labels ("CATEGORY (required, one of):" up to
# "OUTPUT:", "SEVERITY LEVELS (…):" bullet lines); the validator lists sit
# between `# wire-enums:validate:start/end` shell comments. No line numbers.
_prompt_block() {  # <review|audit> <categories|severities>
    local kind="$1" what="$2" nth
    [[ "$kind" == review ]] && nth=1 || nth=2
    if [[ "$what" == categories ]]; then
        awk -v n="$nth" '/CATEGORY \(required, one of\):/{c++; if(c==n){f=1; next}} f && /^OUTPUT:/{exit} f' "$ADV" \
            | tr ',' '\n' | grep -oE '[a-z][a-z-]+' | sort -u | tr '\n' ' '
    else
        awk -v n="$nth" '/^SEVERITY LEVELS \(/{c++; if(c==n){f=1; next}} f && /^$/{exit} f' "$ADV" \
            | grep -oE '^- [A-Z]+' | sed 's/^- //' | sort -u | tr '\n' ' '
    fi
}
_validator_block() {  # prints the text between the validate markers
    awk '/# wire-enums:validate:start/{f=1; next} /# wire-enums:validate:end/{f=0} f' "$ADV"
}

@test "W4: dissent enums — wire == prompt (what the model is asked for) and wire ⊆ validate_finding (never wider)" {
    local block; block=$(_validator_block)
    [ -n "$block" ] || { echo "validate markers missing in adversarial-review.sh" >&2; return 1; }
    local validate_cats; validate_cats=$(printf '%s' "$block" | grep -oE "valid_categories='\[[^]]*\]'" | grep -oE '"[a-z-]+"' | tr -d '"' | sort -u)
    for kind in review audit; do
        local prompt_cats prompt_sevs wire_cats wire_sevs validate_sevs
        prompt_cats=$(_prompt_block "$kind" categories)
        prompt_sevs=$(_prompt_block "$kind" severities)
        wire_cats=$(jq -r '.properties.findings.items.properties.category.enum[]' "$WIRE/dissent-$kind.wire.json" | sort -u | tr '\n' ' ')
        wire_sevs=$(jq -r '.properties.findings.items.properties.severity.enum[]' "$WIRE/dissent-$kind.wire.json" | sort -u | tr '\n' ' ')
        if [[ "$kind" == review ]]; then
            validate_sevs=$(printf '%s' "$block" | grep -A1 '"review"' | grep -oE '"[A-Z]+"' | tr -d '"' | sort -u | tr '\n' ' ')
        else
            validate_sevs=$(printf '%s' "$block" | grep -A1 'else' | grep -oE '"[A-Z]+"' | tr -d '"' | sort -u | tr '\n' ' ')
        fi
        [ -n "$prompt_cats" ] || { echo "$kind: prompt category block not found" >&2; return 1; }
        [ "$wire_cats" = "$prompt_cats" ] || { echo "$kind categories: wire [$wire_cats] != prompt [$prompt_cats]" >&2; return 1; }
        [ "$wire_sevs" = "$prompt_sevs" ] || { echo "$kind severities: wire [$wire_sevs] != prompt [$prompt_sevs]" >&2; return 1; }
        [ "$wire_sevs" = "$validate_sevs" ] || { echo "$kind severities: wire [$wire_sevs] != validate_finding [$validate_sevs]" >&2; return 1; }
        for c in $wire_cats; do
            grep -qx "$c" <<<"$validate_cats" || { echo "$kind category '$c' is in the wire schema but validate_finding would reject it" >&2; return 1; }
        done
    done
}

@test "W5: every field a Flatline persona documents is present and required in its wire twin" {
    run "$PYTHON_BIN" - "$PROJECT_ROOT" <<'PY'
import json, re, sys, os
root = sys.argv[1]
TOP = {"flatline-reviewer": "improvements", "flatline-skeptic": "concerns", "flatline-scorer": "scores"}
bad = []
for persona, top in TOP.items():
    text = open(os.path.join(root, ".claude/skills", persona, "persona.md")).read()
    m = re.search(r"## Schema\s*```json\s*(\{.*?\})\s*```", text, re.S)
    assert m, f"{persona}: no ```json schema block"
    doc = json.loads(m.group(1))
    wire = json.load(open(os.path.join(root, ".claude/schemas/wire", f"{persona}.wire.json")))
    # top-level keys
    for k in doc:
        if k not in wire["properties"] or k not in wire["required"]:
            bad.append(f"{persona}: top-level '{k}' missing or optional in the wire twin")
    # item keys
    item_doc = doc[top][0] if isinstance(doc.get(top), list) and doc[top] else {}
    item_wire = wire["properties"][top]["items"]
    for k in item_doc:
        if k not in item_wire["properties"] or k not in item_wire["required"]:
            bad.append(f"{persona}: item field '{k}' missing or optional in the wire twin")
print("\n".join(bad)); sys.exit(1 if bad else 0)
PY
    [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
}
