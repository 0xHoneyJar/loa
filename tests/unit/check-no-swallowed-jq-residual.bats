#!/usr/bin/env bats
# #1025/#1065: residual gate scanner paths (jq/yq and continued commands).

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCANNER="$REPO/tools/check-no-swallowed-jq.sh"
    FIX="$BATS_TEST_TMPDIR/fixture"
    mkdir -p "$FIX/.claude/scripts"
}

@test "#1065 construct-index is enforced in default mode and yq swallows are caught" {
    cat > "$FIX/.claude/scripts/construct-index-gen.sh" <<'SH'
#!/usr/bin/env bash
name=$(yq eval '.name' construct.yaml 2>/dev/null || echo "")
SH
    run bash -c 'cd "$1" && bash "$2"' _ "$FIX" "$SCANNER"
    [ "$status" -eq 1 ]
    [[ "$output" == *"construct-index-gen.sh:2:"* ]]
}

@test "#1025 continued jq invocation cannot evade the gate scanner" {
    cat > "$FIX/continued.sh" <<'SH'
#!/usr/bin/env bash
count=$(jq -r \
    '.findings | length' data.json 2>/dev/null || echo 0)
SH
    run bash "$SCANNER" --root "$FIX"
    [ "$status" -eq 1 ]
    [[ "$output" == *"continued.sh:2:"* ]]
}

@test "#1025 fallback on following line cannot evade the gate scanner" {
    cat > "$FIX/fallback.sh" <<'SH'
#!/usr/bin/env bash
count=$(jq -r '.findings | length' data.json ||
    printf 0)
SH
    run bash "$SCANNER" --root "$FIX"
    [ "$status" -eq 1 ]
    [[ "$output" == *"fallback.sh:2:"* ]]
}

@test "#1065 continued yq in an executed heredoc remains enforced" {
    cat > "$FIX/executed.sh" <<'SH'
#!/usr/bin/env bash
bash <<'CODE'
name=$(yq eval \
    '.name' construct.yaml || echo "")
CODE
SH
    run bash "$SCANNER" --root "$FIX"
    [ "$status" -eq 1 ]
    [[ "$output" == *"executed.sh:3:"* ]]
}

@test "#1025 inert fixture and loud handled failures remain clean" {
    cat > "$FIX/good.sh" <<'SH'
#!/usr/bin/env bash
cat <<'DATA'
name=$(yq eval \
    '.name' construct.yaml || echo "")
DATA
if ! count=$(jq_strict '.findings | length' data.json); then
    echo 'parse failed' >&2
    exit 1
fi
name=$(_strict_or_default "" "name" yq eval '.name' construct.yaml)
jq -n \
    --argjson enabled "$( [[ "$enabled" == true ]] && echo true || echo false )" \
    '{enabled: $enabled}'
SH
    run bash "$SCANNER" --root "$FIX"
    [ "$status" -eq 0 ]
}
