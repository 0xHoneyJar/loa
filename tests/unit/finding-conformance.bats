#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# =============================================================================
# tests/unit/finding-conformance.bats — cycle-133 Sprint 274 Task 3.2 (sdd.md C-11; PRD FR-11; G-5): the four
# validators of the canonical finding (.claude/schemas/finding.schema.json v1) agree on every conformance vector
# under .claude/schemas/finding.vectors/{valid,invalid}/:
#   python  .claude/scripts/lib/finding_validate.py      jq  .claude/scripts/lib/finding-validate.sh
#   zod     bridgebuilder-review resources/core/finding-schema.ts (its node:test suite; skipped without node_modules)
#   markdown  verdict-derive.sh on each vector's markdown rendering (valid ⇔ consistent, the violation codes = the
#             vector's error codes)
# =============================================================================

setup() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    VEC="$PROJECT_ROOT/.claude/schemas/finding.vectors"
    PYV="$PROJECT_ROOT/.claude/scripts/lib/finding_validate.py"
    JQV="$PROJECT_ROOT/.claude/scripts/lib/finding-validate.sh"
    VD="$PROJECT_ROOT/.claude/scripts/verdict-derive.sh"
    BB="$PROJECT_ROOT/.claude/skills/bridgebuilder-review"
    T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/fc.XXXXXX")"
}

teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

@test "FC-1 the python validator agrees with every vector" {
    run python3 -I "$PYV" --vectors "$VEC"
    [ "$status" -eq 0 ] || { echo "$output" | grep -v '^ok'; return 1; }
    [[ "$output" == *"disagreements 0"* ]]
}

@test "FC-2 the jq validator agrees with every vector" {
    run bash "$JQV" --vectors "$VEC"
    [ "$status" -eq 0 ] || { echo "$output" | grep -v '^ok'; return 1; }
    [[ "$output" == *"disagreements 0"* ]]
}

@test "FC-3 the zod validator agrees with every vector (node:test suite)" {
    [[ -d "$BB/node_modules/zod" ]] || skip "bridgebuilder-review node_modules absent (npm ci)"
    run bash -c 'cd "$1/resources" && npx --no-install tsx --test __tests__/finding-schema.test.ts' _ "$BB"
    [ "$status" -eq 0 ] || { echo "$output" | tail -30; return 1; }
    [[ "$output" == *"# fail 0"* ]]
}

@test "FC-4 the markdown grammar (verdict-derive.sh) agrees with every vector carrying a rendering" {
    local n=0 f kind md sev spec blocking codes exp got
    for kind in valid invalid; do
        for f in "$VEC/$kind"/*.json; do
            md=$(jq -r '.markdown // empty' "$f"); [[ -n "$md" ]] || continue
            n=$((n + 1))
            sev=$(jq -r '.finding.severity' "$f"); spec=0; blocking=0
            [[ "$md" == *"speculative"* ]] && spec=1
            [[ "$(jq -r '.finding.blocking // false' "$f")" == "true" ]] && blocking=1
            local c=0 h=0 m=0 l=0
            case "$sev" in CRITICAL) c=1 ;; HIGH) h=1 ;; MEDIUM) m=1 ;; LOW) l=1 ;; esac
            if [[ "$spec" -eq 1 ]]; then
                { printf 'All good\n\n## Observations\n\n%s\n\n' "$md"
                  printf '<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"excluded":1,"sprint_id":"sprint-274","ts":"2026-10-24T00:00:00Z"} -->\n'; } > "$T/r.md"
            elif [[ "$c$h" != "00" || "$blocking" -eq 1 ]]; then
                { printf '## Changes Required\n\n%s\n\n' "$md"
                  printf '<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":%s,"high":%s,"medium":%s,"low":%s},"sprint_id":"sprint-274","ts":"2026-10-24T00:00:00Z"} -->\n' "$c" "$h" "$m" "$l"; } > "$T/r.md"
            else
                { printf 'All good\n\n## Observations\n\n%s\n\n' "$md"
                  printf '<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":%s,"low":%s},"sprint_id":"sprint-274","ts":"2026-10-24T00:00:00Z"} -->\n' "$m" "$l"; } > "$T/r.md"
            fi
            run --separate-stderr "$VD" --file "$T/r.md" --gate review --json
            if [[ "$kind" == "valid" ]]; then
                [ "$status" -eq 0 ] || { echo "$kind/$(basename "$f"): exit $status: $output"; return 1; }
            else
                [ "$status" -eq 1 ] || { echo "$kind/$(basename "$f"): exit $status"; return 1; }
                exp=$(jq -r '.expect.errors | join(",")' "$f")
                got=$(jq -r '[.violations[] | capture("Failure clause \\((?<c>[a-z_,]+)\\)").c] | join(";")' <<<"$output")
                [ "$got" = "$exp" ] || { echo "$kind/$(basename "$f"): codes '$got' != '$exp'"; return 1; }
            fi
        done
    done
    [ "$n" -ge 10 ]
}

@test "FC-5 the seam: a HIGH with a one-word Failure clause is refused by all four validators" {
    local f="$VEC/invalid/01-one-word-clause.json"
    run python3 -I "$PYV" <(jq -c '.finding' "$f"); [ "$status" -eq 1 ]
    run bash "$JQV" <(jq -c '.finding' "$f"); [ "$status" -eq 1 ]
    [[ "$output" == *'"errors":["failure_scenario"]'* ]]
    { printf '## Changes Required\n\n%s\n\n' "$(jq -r '.markdown' "$f")"
      printf '<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":0,"low":0},"sprint_id":"sprint-274","ts":"2026-10-24T00:00:00Z"} -->\n'; } > "$T/r.md"
    run "$VD" --file "$T/r.md" --gate review; [ "$status" -eq 1 ]
    # zod: FC-3 runs the same vector through validateCanonicalFinding and CanonicalFindingSchema
}

@test "FC-6 the vector set covers every error code and both directories" {
    [ "$(ls "$VEC/valid"/*.json | wc -l)" -ge 15 ]
    [ "$(ls "$VEC/invalid"/*.json | wc -l)" -ge 15 ]
    local codes
    codes=$(jq -r '.["x-loa-rules"].error_codes[]' "$PROJECT_ROOT/.claude/schemas/finding.schema.json" | sort)
    local seen
    seen=$(jq -r '.expect.errors[]' "$VEC"/invalid/*.json | sort -u)
    local missing
    missing=$(comm -23 <(printf '%s\n' "$codes") <(printf '%s\n' "$seen") | grep -v '^suggestion$' || true)
    [ -z "$missing" ] || { echo "no vector for: $missing"; return 1; }
}

@test "FC-7 the jq and python validators print the same document for every vector, aliases with the named warning" {
    local f a b
    for f in "$VEC"/*/*.json; do
        a=$(python3 -I "$PYV" <(jq -c '.finding' "$f")) || true
        b=$(bash "$JQV" <(jq -c '.finding' "$f")) || true
        jq -n -e --argjson a "$a" --argjson b "$b" '$a == $b' >/dev/null || { echo "$(basename "$f"): $a vs $b"; return 1; }
    done
    run bash -c 'jq -c .finding "$1" | bash "$2"' _ "$VEC/valid/10-alias-failure-mode.json" "$JQV"
    [[ "$output" == *'`failure_mode` is an alias of `failure_scenario`; removed in 2.1.0'* ]]
}
