#!/usr/bin/env bats
# =============================================================================
# tests/unit/prompt-audit-keeplist.bats — cycle-124 FR-8 / AC-8.3
#
# tools/prompt-keeplist.txt names the prompt text the audit may never delete
# (fences and remedies, the one-way verdict rule, the zone model, tool
# contracts, format-pinning examples, agent-network invariants, routing text,
# the list itself). Each entry is `<id> TAB <glob> TAB <ERE> TAB <reason>`;
# every file the glob matches must still match the ERE, and the human
# companion tools/prompt-keeplist.md explains
# every id.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    LIST="$PROJECT_ROOT/tools/prompt-keeplist.txt"
    COMPANION="$PROJECT_ROOT/tools/prompt-keeplist.md"
}

entries() { grep -v -E '^\s*(#|$)' "$LIST"; }

@test "KL-1 every entry has four tab-separated fields, a unique K-NN id and a reason" {
    local n ids
    n="$(entries | awk -F'\t' 'NF!=4 || $1 !~ /^K-[0-9]{2}$/ || $4 == ""' | wc -l)"
    [ "$n" -eq 0 ]
    ids="$(entries | cut -f1 | sort | uniq -d)"
    [ -z "$ids" ]
    [ "$(entries | wc -l)" -ge 40 ]
}

@test "KL-2 every keep-listed string survives in every file its glob matches" {
    local failures=0 id glob ere reason f matched
    while IFS=$'\t' read -r id glob ere reason; do
        matched=0
        shopt -s nullglob
        # brace lists and globs expand relative to the repo root
        for f in $(cd "$PROJECT_ROOT" && eval "printf '%s\n' $glob"); do
            matched=1
            if ! grep -qE -- "$ere" "$PROJECT_ROOT/$f"; then
                echo "MISSING $id in $f: /$ere/ ($reason)"
                failures=$((failures + 1))
            fi
        done
        shopt -u nullglob
        if [ "$matched" -eq 0 ]; then
            echo "NO FILE for $id glob $glob"
            failures=$((failures + 1))
        fi
    done < <(entries)
    [ "$failures" -eq 0 ]
}

@test "KL-3 the companion keep-list.md explains every id" {
    [ -f "$COMPANION" ]
    local missing=0 id rest
    while IFS=$'\t' read -r id rest; do
        grep -q -- "$id" "$COMPANION" || { echo "no companion row for $id"; missing=$((missing + 1)); }
    done < <(entries)
    [ "$missing" -eq 0 ]
}
