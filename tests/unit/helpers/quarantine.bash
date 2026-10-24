# shellcheck shell=bash
# =============================================================================
# tests/unit/helpers/quarantine.bash — cycle-133 Sprint 1 Task 1.6 (FR-5, SDD C-5)
#
# Skip a bats test that tests/QUARANTINE.tsv lists, with the row's reason.
#
# Usage (in a bats file whose test is quarantined):
#   setup() {
#     load helpers/quarantine          # path relative to the bats file
#     loa_quarantine_check             # skips the running test when listed
#     ...
#   }
#
# The running test's id is `<repo-relative bats path>::<test description>`,
# e.g. `tests/unit/cost-report.bats::CR-7 --reprice: ...` — the same string the
# first column of tests/QUARANTINE.tsv carries. `loa_quarantine_check <id>`
# (optional argument) asserts the running test IS that id and fails the test
# otherwise, so a copied call cannot quarantine a different test.
#
# Refusals (the test FAILS instead of skipping):
#   - an id argument that does not match the running test;
#   - a listed test whose id names a mandatory release gate
#     (LOA_QUARANTINE_MANDATORY_RE: egress isolation, mount provenance, the
#     batch supervisor, the finding-clause blocking rule — sdd.md § 7.3).
# An expired row is not honoured: the test runs (CI fails on the row anyway,
# tools/check-quarantine-expiry.sh). Rows are validated by that tool; this
# helper only reads the matching row.
# =============================================================================

# Mandatory gates that may never be quarantined (matched case-insensitively
# against the full test id). tools/check-quarantine-expiry.sh reads this
# variable from this file, so the helper and the CI gate share one list.
LOA_QUARANTINE_MANDATORY_RE='egress|mount-home-scope|sandbox-mount|mount-provenance|batch-supervisor|verdict-derive-failure-clause'

_loa_quarantine_root() {
    local d=""
    d="$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel 2>/dev/null)" || d=""
    [[ -n "$d" ]] || d="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
    printf '%s\n' "$d"
}

# Print the running test's quarantine id.
loa_quarantine_id() {
    local root dir
    root="$(_loa_quarantine_root)"
    dir="$(cd -P "$(dirname "$BATS_TEST_FILENAME")" && pwd -P)"
    printf '%s::%s\n' "${dir#"$root"/}/$(basename "$BATS_TEST_FILENAME")" "$BATS_TEST_DESCRIPTION"
}

loa_quarantine_check() {
    local expected="${1:-}" id root file row _id owner expiry bead reason today
    id="$(loa_quarantine_id)"
    if [[ -n "$expected" && "$expected" != "$id" ]]; then
        printf 'quarantine: row id "%s" does not match the running test "%s"\n' "$expected" "$id" >&2
        return 1
    fi
    root="$(_loa_quarantine_root)"
    file="$root/tests/QUARANTINE.tsv"
    [[ -f "$file" ]] || return 0
    row="$(LOA_QID="$id" awk -F'\t' 'NR > 1 && $1 == ENVIRON["LOA_QID"] { print; exit }' "$file")"
    [[ -n "$row" ]] || return 0
    if printf '%s\n' "$id" | grep -Eiq -- "$LOA_QUARANTINE_MANDATORY_RE"; then
        printf 'quarantine: refused — "%s" is a mandatory gate and may never be quarantined (sdd.md § 7.3); remove its row from tests/QUARANTINE.tsv\n' "$id" >&2
        return 1
    fi
    IFS=$'\t' read -r _id owner expiry bead reason <<< "$row"
    today="$(date -u +%Y-%m-%d)"
    if [[ "$expiry" < "$today" ]]; then
        printf 'quarantine: the row for "%s" expired on %s; running the test\n' "$id" "$expiry" >&2
        return 0
    fi
    skip "quarantined: until $expiry ($bead, owner $owner): $reason"
}
