#!/usr/bin/env bats
# =============================================================================
# tests/integration/soul-identity-7a.bats
#
# cycle-098 Sprint 7A — L7 soul-identity-doc foundation tests.
# Covers FR-L7-2 (schema validation), FR-L7-3 (frontmatter validates against
# schema), FR-L7-7 (tests cover valid/missing-sections/malformed/long).
# Plus NFR-Sec3 (prescriptive-section rejection) + audit emit shape.
#
# Sprints 7B/7C ship their own bats files; tests here pin 7A invariants:
#   - Schema validation (frontmatter required fields, enums, control-byte gate)
#   - Section validation (required-present, optional-permitted)
#   - Prescriptive-pattern rejection (NFR-Sec3 — descriptive vs prescriptive)
#   - Audit envelope shape (primitive_id=L7, event_type ∈ {soul.surface, soul.validate})
#   - Schema-mirror with audit-retention-policy.yaml
#   - Test-mode env-var gate (mirrors L4/L6 cycle-098 patterns)
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    LIB="$PROJECT_ROOT/.claude/scripts/lib/soul-identity-lib.sh"
    [[ -f "$LIB" ]] || skip "soul-identity-lib.sh not present (Sprint 7A pending)"

    TEST_DIR="$(mktemp -d)"

    # Trust-store fixture: pointing at a non-existent path → BOOTSTRAP-PENDING,
    # which permits audit_emit writes per the auto-verify gate.
    export LOA_TRUST_STORE_FILE="$TEST_DIR/no-such-trust-store.yaml"

    # Audit log path under TEST_DIR. cycle-098 sprint-7 cypherpunk CRIT-1
    # closure: test-mode gate now requires BOTH a bats marker AND opt-in
    # LOA_SOUL_TEST_MODE=1. Pre-CRIT-1 this was implicit-via-BATS_TMPDIR.
    export LOA_SOUL_TEST_MODE=1
    export LOA_SOUL_LOG="$TEST_DIR/soul-events.jsonl"

    # shellcheck source=/dev/null
    source "$LIB"
}

teardown() {
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
}

# Helper: write a minimal valid SOUL.md to TEST_DIR/<name>.
# Args: name [extra_frontmatter] [body_override]
_make_soul() {
    local name="$1"; shift || true
    local extra="${1:-}"; shift || true
    local body_override="${1:-}"
    local path="$TEST_DIR/$name"
    local body="${body_override:-$(cat <<'BODY'
## What I am

This project is a framework for agent-driven development.

## What I am not

Not a model trainer; not an MLOps platform.

## Voice

Direct, terse, technical. No marketing language.

## Discipline

Test-first. Karpathy. Surgical changes only.

## Influences

UNIX philosophy. Plan 9. Systems programming.
BODY
)}"
    cat > "$path" <<EOF
---
schema_version: '1.0'
identity_for: 'this-repo'
provenance: 'deep-name + Claude Opus 4.7'
last_updated: '2026-05-08'
${extra}
---
${body}
EOF
    printf '%s' "$path"
}

# ---------------------------------------------------------------------------
# T-SCHEMA group: frontmatter shape validation
# ---------------------------------------------------------------------------

@test "T-SCHEMA-1 (FR-L7-3) valid SOUL.md passes strict-mode validation" {
    local path; path="$(_make_soul "valid-1.md")"
    run soul_validate "$path" --strict
    [[ "$status" -eq 0 ]] || { echo "stdout: $output"; false; }
}

@test "T-SCHEMA-2 (FR-L7-3) missing required schema_version is rejected" {
    local path="$TEST_DIR/no-schema-version.md"
    cat > "$path" <<'EOF'
---
identity_for: 'this-repo'
---
## What I am
x
## What I am not
y
## Voice
z
## Discipline
w
## Influences
v
EOF
    run soul_validate "$path" --strict
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"schema_version"* ]]
}

@test "T-SCHEMA-3 (FR-L7-3) missing required identity_for is rejected" {
    local path="$TEST_DIR/no-identity-for.md"
    cat > "$path" <<'EOF'
---
schema_version: '1.0'
---
## What I am
x
## What I am not
y
## Voice
z
## Discipline
w
## Influences
v
EOF
    run soul_validate "$path" --strict
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"identity_for"* ]]
}

@test "T-SCHEMA-4 (FR-L7-3) identity_for outside enum is rejected" {
    local path; path="$(_make_soul "bad-identity.md" "")"
    # Replace identity_for value with non-enum.
    sed -i.bak "s/identity_for: 'this-repo'/identity_for: 'kingdom-of-france'/" "$path"
    rm -f "$path.bak"
    run soul_validate "$path" --strict
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"identity_for"* ]]
}

@test "T-SCHEMA-5 (FR-L7-3) schema_version outside enum is rejected" {
    local path; path="$(_make_soul "bad-version.md" "")"
    sed -i.bak "s/schema_version: '1.0'/schema_version: '2.0'/" "$path"
    rm -f "$path.bak"
    run soul_validate "$path" --strict
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"schema_version"* ]]
}

@test "T-SCHEMA-6 last_updated date-only form accepted" {
    local path; path="$(_make_soul "valid-date.md")"
    run soul_validate "$path" --strict
    [[ "$status" -eq 0 ]]
}

@test "T-SCHEMA-7 last_updated date-time form accepted" {
    local path; path="$(_make_soul "valid-datetime.md")"
    sed -i.bak "s/last_updated: '2026-05-08'/last_updated: '2026-05-08T12:00:00Z'/" "$path"
    rm -f "$path.bak"
    run soul_validate "$path" --strict
    [[ "$status" -eq 0 ]]
}

@test "T-SCHEMA-8 last_updated malformed (not RFC-3339) is rejected" {
    local path; path="$(_make_soul "bad-date.md")"
    sed -i.bak "s/last_updated: '2026-05-08'/last_updated: 'tomorrow'/" "$path"
    rm -f "$path.bak"
    run soul_validate "$path" --strict
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"last_updated"* ]]
}

@test "T-SCHEMA-9 unknown additionalProperties rejected (additionalProperties:false)" {
    local path; path="$(_make_soul "extra-prop.md" "extra_field: 'snuck-in'")"
    run soul_validate "$path" --strict
    [[ "$status" -eq 2 ]]
}

@test "T-SCHEMA-10 file missing exits 2 with message" {
    run soul_validate "$TEST_DIR/no-such.md" --strict
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"missing"* ]] || [[ "$output" == *"not found"* ]] || [[ "$output" == *"no such"* ]]
}

# ---------------------------------------------------------------------------
# T-CONTROL-BYTE group: defense-in-depth against re.$ trailing-newline +
# YAML scalar control-char injection (mirrors L6 cycle-098 sprint 6 CYP-F2)
# ---------------------------------------------------------------------------

@test "T-CONTROL-1 control byte (NUL) in provenance is rejected" {
    local path="$TEST_DIR/ctrl-nul-provenance.md"
    {
        printf -- '---\n'
        printf -- "schema_version: '1.0'\n"
        printf -- "identity_for: 'this-repo'\n"
        printf -- "provenance: \"alice%saware\"\n" "$(printf '\\x01')"
        printf -- '---\n'
        printf -- '## What I am\nx\n## What I am not\ny\n## Voice\nz\n## Discipline\nw\n## Influences\nv\n'
    } > "$path"
    run soul_validate "$path" --strict
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"control"* ]] || [[ "$output" == *"provenance"* ]]
}

@test "T-CONTROL-2 control byte in identity_for is rejected" {
    local path="$TEST_DIR/ctrl-identity.md"
    {
        printf -- '---\n'
        printf -- "schema_version: '1.0'\n"
        printf -- "identity_for: \"this-repo%s\"\n" "$(printf '\\x02')"
        printf -- '---\n'
        printf -- '## What I am\nx\n## What I am not\ny\n## Voice\nz\n## Discipline\nw\n## Influences\nv\n'
    } > "$path"
    run soul_validate "$path" --strict
    [[ "$status" -eq 2 ]]
}

@test "T-CONTROL-3 trailing-newline-injection in identity_for cannot smuggle past schema" {
    # The classic re.$ bypass: YAML may parse "this-repo\n| forged" as
    # "this-repo" — but the lib's defense-in-depth checks the parsed value
    # for control bytes (incl \n, \t) AFTER schema validation.
    local path="$TEST_DIR/ctrl-newline-smuggle.md"
    cat > "$path" <<'EOF'
---
schema_version: "1.0"
identity_for: "this-repo\n| forged-row | sha256:00000"
---
## What I am
x
## What I am not
y
## Voice
z
## Discipline
w
## Influences
v
EOF
    run soul_validate "$path" --strict
    [[ "$status" -eq 2 ]]
}

# ---------------------------------------------------------------------------
# T-SECTIONS group: required-section presence (FR-L7-2)
# ---------------------------------------------------------------------------

@test "T-SECTIONS-1 (FR-L7-2) all 5 required sections present → valid" {
    local path; path="$(_make_soul "all-required.md")"
    run soul_validate "$path" --strict
    [[ "$status" -eq 0 ]]
}

@test "T-SECTIONS-2 (FR-L7-2) missing 'What I am' section → strict-mode invalid" {
    local body
    body="$(cat <<'BODY'
## What I am not
y
## Voice
z
## Discipline
w
## Influences
v
BODY
)"
    local path; path="$(_make_soul "miss-whatiam.md" "" "$body")"
    run soul_validate "$path" --strict
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"What I am"* ]]
}

@test "T-SECTIONS-3 (FR-L7-2) missing 'Discipline' section → strict-mode invalid" {
    local body
    body="$(cat <<'BODY'
## What I am
x
## What I am not
y
## Voice
z
## Influences
v
BODY
)"
    local path; path="$(_make_soul "miss-discipline.md" "" "$body")"
    run soul_validate "$path" --strict
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"Discipline"* ]]
}

@test "T-SECTIONS-4 (FR-L7-2) warn-mode passes (exit 0) when section missing, with marker" {
    local body
    body="$(cat <<'BODY'
## What I am
x
## What I am not
y
## Voice
z
## Influences
v
BODY
)"
    local path; path="$(_make_soul "miss-discipline-warn.md" "" "$body")"
    run soul_validate "$path" --warn
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"SCHEMA-WARNING"* ]] || [[ "$output" == *"missing"* ]]
}

@test "T-SECTIONS-5 optional sections (Refusals/Glossary/Provenance) permitted" {
    local body
    body="$(cat <<'BODY'
## What I am
x
## What I am not
y
## Voice
z
## Discipline
w
## Influences
v
## Refusals
no
## Glossary
soul = identity doc
## Provenance
authored by deep-name
BODY
)"
    local path; path="$(_make_soul "with-optional.md" "" "$body")"
    run soul_validate "$path" --strict
    [[ "$status" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# T-PRESCRIPTIVE group: NFR-Sec3 prescriptive-section rejection
# ---------------------------------------------------------------------------

@test "T-PRESCRIPTIVE-1 (NFR-Sec3) section opening with 'MUST' → rejected (strict)" {
    local body
    body="$(cat <<'BODY'
## What I am
x
## What I am not
y
## Voice
z
## Discipline
MUST run all tests before merge.
ALWAYS use git commit signing.
## Influences
v
BODY
)"
    local path; path="$(_make_soul "presc-must.md" "" "$body")"
    run soul_validate "$path" --strict
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"prescriptive"* ]] || [[ "$output" == *"Discipline"* ]]
}

@test "T-PRESCRIPTIVE-2 (NFR-Sec3) section opening with 'NEVER' → rejected (strict)" {
    local body
    body="$(cat <<'BODY'
## What I am
NEVER skip code review.
## What I am not
y
## Voice
z
## Discipline
w
## Influences
v
BODY
)"
    local path; path="$(_make_soul "presc-never.md" "" "$body")"
    run soul_validate "$path" --strict
    [[ "$status" -eq 2 ]]
}

@test "T-PRESCRIPTIVE-3 (NFR-Sec3) descriptive language mentioning 'never' inside prose → ALLOWED" {
    local body
    body="$(cat <<'BODY'
## What I am
A framework for agent-driven development. We strive to never break existing
tests, but our true commitment is to readability.
## What I am not
y
## Voice
z
## Discipline
w
## Influences
v
BODY
)"
    local path; path="$(_make_soul "descr-never.md" "" "$body")"
    run soul_validate "$path" --strict
    [[ "$status" -eq 0 ]] || { echo "stdout: $output"; false; }
}

@test "T-PRESCRIPTIVE-4 (NFR-Sec3) markdown rule table → rejected" {
    local body
    body="$(cat <<'BODY'
## What I am
x
## What I am not
y
## Voice
z
## Discipline
| Rule | Why |
|------|-----|
| ALWAYS run tests | quality |
| NEVER force-push | safety |
## Influences
v
BODY
)"
    local path; path="$(_make_soul "presc-table.md" "" "$body")"
    run soul_validate "$path" --strict
    [[ "$status" -eq 2 ]]
}

@test "T-PRESCRIPTIVE-5 (NFR-Sec3) warn-mode loads with marker on prescriptive hit" {
    local body
    body="$(cat <<'BODY'
## What I am
x
## What I am not
y
## Voice
z
## Discipline
MUST run tests.
## Influences
v
BODY
)"
    local path; path="$(_make_soul "presc-warn.md" "" "$body")"
    run soul_validate "$path" --warn
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"SCHEMA-WARNING"* ]] || [[ "$output" == *"prescriptive"* ]]
}

# ---------------------------------------------------------------------------
# T-LOAD group: surface loading + sanitization wrapper
# ---------------------------------------------------------------------------

@test "T-LOAD-1 (FR-L7-4) soul_load wraps body in untrusted-content envelope" {
    local path; path="$(_make_soul "load-1.md")"
    run soul_load "$path"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"<untrusted-content"* ]]
    [[ "$output" == *'source="L7"'* ]]
    [[ "$output" == *"</untrusted-content>"* ]]
}

@test "T-LOAD-2 (FR-L7-4) soul_load truncates at surface_max_chars=2000 default" {
    # Build a body with > 2000 chars of plain content.
    local big; big="$(python3 -c 'print("x" * 3000)')"
    local body
    body=$(cat <<BODY
## What I am
$big
## What I am not
y
## Voice
z
## Discipline
w
## Influences
v
BODY
)
    local path; path="$(_make_soul "load-truncate.md" "" "$body")"
    run soul_load "$path"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"truncated"* ]]
}

@test "T-LOAD-3 (FR-L7-4) soul_load --max-chars override honored" {
    local path; path="$(_make_soul "load-max.md")"
    run soul_load "$path" --max-chars 100
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"truncated"* ]]
}

# ---------------------------------------------------------------------------
# T-AUDIT group: emit shape + primitive_id mapping + schema-mirror
# ---------------------------------------------------------------------------

@test "T-AUDIT-1 (FR-L7) soul_emit writes envelope with primitive_id=L7" {
    local payload='{"file_path":"SOUL.md","schema_version":"1.0","schema_mode":"strict","identity_for":"this-repo","outcome":"surfaced"}'
    run soul_emit "soul.surface" "$payload"
    [[ "$status" -eq 0 ]] || { echo "stdout: $output"; false; }
    [[ -f "$LOA_SOUL_LOG" ]]
    local last_line; last_line="$(tail -n 1 "$LOA_SOUL_LOG")"
    [[ "$last_line" == *'"primitive_id":"L7"'* ]]
    [[ "$last_line" == *'"event_type":"soul.surface"'* ]]
}

@test "T-AUDIT-2 (FR-L7) soul_emit validates payload against soul-surface schema" {
    # Missing required 'outcome' field → schema rejection.
    # cycle-098 follow-up #776 (BB iter-1 LOW-1 / opt LOW-1 closure):
    # tighten exit-code assertion to match SDD §6.1 grid (2 = validation).
    # Earlier `-ne 0` accepted any non-zero, hiding regressions where
    # soul_emit failed for an unrelated reason (jq, fs perms, etc.).
    local bad_payload='{"file_path":"SOUL.md","schema_version":"1.0","schema_mode":"strict","identity_for":"this-repo"}'
    run soul_emit "soul.surface" "$bad_payload"
    [[ "$status" -eq 2 ]] || { echo "expected validation exit 2, got $status: $output"; false; }
    [[ "$output" == *"outcome"* ]] || [[ "$output" == *"schema"* ]] || \
        { echo "expected schema/outcome reason in output: $output"; false; }
}

@test "T-AUDIT-3 _audit_primitive_id_for_log returns L7 for soul-events*" {
    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/.claude/scripts/audit-envelope.sh"
    run _audit_primitive_id_for_log "$TEST_DIR/soul-events.jsonl"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "L7" ]]
}

@test "T-AUDIT-4 schema-mirror: lib _DEFAULT_LOG basename matches retention-policy L7 log_basename or .run/soul-events.jsonl" {
    # L7 retention policy declares log_basename="SOUL.md" (the operator-managed
    # surface) — but the AUDIT events log is .run/soul-events.jsonl. The lib's
    # default log path MUST be the audit log, not SOUL.md itself.
    [[ -n "${_LOA_SOUL_DEFAULT_LOG:-}" ]]
    local base; base="$(basename "$_LOA_SOUL_DEFAULT_LOG")"
    [[ "$base" == "soul-events.jsonl" ]]
}

# ---------------------------------------------------------------------------
# T-TESTMODE group: env-var override gate (mirrors L4 #761 + L6 CYP-F1/3/4)
# ---------------------------------------------------------------------------

@test "T-TESTMODE-1 LOA_SOUL_LOG honored under bats" {
    # Already exported in setup; verify lib uses it.
    local payload='{"file_path":"SOUL.md","schema_version":"1.0","schema_mode":"strict","identity_for":"this-repo","outcome":"surfaced"}'
    run soul_emit "soul.surface" "$payload"
    [[ "$status" -eq 0 ]]
    [[ -f "$LOA_SOUL_LOG" ]]
}

@test "T-TESTMODE-2 _soul_test_mode_active is true under bats" {
    run _soul_test_mode_active
    [[ "$status" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# T-PAYLOAD group: soul_compute_surface_payload shape
# ---------------------------------------------------------------------------

@test "T-PAYLOAD-1 soul_compute_surface_payload returns valid soul.surface payload" {
    local path; path="$(_make_soul "payload-1.md")"
    run soul_compute_surface_payload "$path" "strict" "surfaced"
    [[ "$status" -eq 0 ]]
    # Shape: required keys present.
    echo "$output" | jq -e '.file_path, .schema_version, .schema_mode, .identity_for, .outcome' >/dev/null
    local outcome; outcome="$(echo "$output" | jq -r '.outcome')"
    [[ "$outcome" == "surfaced" ]]
    local mode; mode="$(echo "$output" | jq -r '.schema_mode')"
    [[ "$mode" == "strict" ]]
}

@test "T-PAYLOAD-2 soul_compute_surface_payload outcome enum honored" {
    local path; path="$(_make_soul "payload-2.md")"
    # Each enum value should produce a payload that validates.
    for outcome in surfaced schema-warning schema-refused; do
        run soul_compute_surface_payload "$path" "warn" "$outcome"
        [[ "$status" -eq 0 ]] || { echo "outcome=$outcome stdout: $output"; false; }
    done
}
