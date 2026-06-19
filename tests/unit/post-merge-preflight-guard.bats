#!/usr/bin/env bats
# =============================================================================
# #1085 — post-merge.yml must preflight-guard submodule-symlinked Loa scripts
# =============================================================================
# When loa is submodule-mounted, .claude/scripts is a symlink that can fail to
# resolve on a CI runner. The pre-fix `chmod +x .claude/scripts/X.sh` then failed
# with a buried chmod error under `bash -e`, cascading (needs: classify) into a
# SILENT skip of the whole release pipeline (tag/CHANGELOG/release). The fix adds
# a loud `::error::` preflight before each chmod so the cause is audible. The
# downstream skip is intentional (don't release on a broken checkout) — the guard
# only makes WHY visible.
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    WF="$REPO_ROOT/.github/workflows/post-merge.yml"
    [[ -f "$WF" ]] || skip "post-merge.yml not found"
}

@test "#1085: every 'chmod +x .claude/scripts' is preceded by a preflight guard" {
    local chmods guards
    chmods=$(grep -c 'chmod +x .claude/scripts' "$WF")
    guards=$(grep -c '#1085 preflight' "$WF")
    [ "$chmods" -ge 3 ]
    [ "$chmods" -eq "$guards" ]
}

@test "#1085: the guard fails loud with an actionable ::error:: (not a buried chmod)" {
    grep -qE '::error::Loa script .* unresolved' "$WF"
    grep -q "submodules: recursive" "$WF"
}

@test "#1085: the guard logic exits 1 + emits ::error:: when a script is missing" {
    # Functional sim of the embedded guard against a non-existent path.
    run bash -c '
      set -e
      for _s in /nonexistent/loa-script.sh; do
        test -f "$_s" || { echo "::error::Loa script '"'"'$_s'"'"' unresolved (#1085)"; exit 1; }
      done
      echo "SHOULD-NOT-REACH"
    '
    [ "$status" -eq 1 ]
    [[ "$output" == *"::error::"* ]]
    [[ "$output" != *"SHOULD-NOT-REACH"* ]]
}
