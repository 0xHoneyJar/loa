#!/usr/bin/env bats
# =============================================================================
# #1076 defect 1 — POST_PR_AUDIT todo-comment / console-log false positives
# =============================================================================
# The audit's auto-fixable quality nits (todo-comment, console-log) used to
# grep the WHOLE changed file, so a pre-existing TODO (or prose containing
# "# TODO:") in a touched file was flagged auto_fixable -> CHANGES_REQUIRED.
# The orchestrator's audit "fix loop" has no fixer, so the false positive
# recurred every iteration -> "Max audit iterations (5) reached" -> HALTED.
#
# Fix: scope these nits to lines ADDED by the PR (the unified diff). Pins:
#   - pre-existing TODO (context line, not added)  -> NOT flagged (APPROVED)
#   - TODO on an added line                        -> flagged (CHANGES_REQUIRED)
#   - diff unavailable                             -> nits skipped (fail-safe)
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    AUDIT="$REPO_ROOT/.claude/scripts/post-pr-audit.sh"
    [[ -f "$AUDIT" ]] || skip "post-pr-audit.sh not found"
    command -v jq >/dev/null 2>&1 || skip "jq required"

    # The source-guard keeps main() from running on source, exposing the
    # internal functions (run_audit, _first_added_match, ...) for direct test.
    # shellcheck disable=SC1090
    source "$AUDIT"
    set +e  # the script sets -euo pipefail; relax for test-driver control

    WORK="$(mktemp -d)"
    cd "$WORK"
    mkdir -p app ctx
}

teardown() {
    cd /
    [[ -n "${WORK:-}" && -d "$WORK" ]] && rm -rf "$WORK"
}

_metadata() {
    local files_json="[]" p
    for p in "$@"; do
        files_json=$(echo "$files_json" | jq --arg p "$p" '. + [{path:$p}]')
    done
    jq -n --argjson f "$files_json" '{title:"t",body:"b",additions:1,deletions:0,files:$f}' \
        > ctx/pr-metadata.json
}

@test "#1076 d1: pre-existing TODO (context line, not added) is NOT flagged -> APPROVED" {
    printf '%s\n' '# header' '# TODO: load from database' 'x = 1' > app/main.py
    _metadata "app/main.py"
    cat > ctx/pr-diff.patch <<'DIFF'
diff --git a/app/main.py b/app/main.py
--- a/app/main.py
+++ b/app/main.py
@@ -1,2 +1,3 @@
 # header
 # TODO: load from database
+x = 1
DIFF
    run run_audit "ctx"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.verdict' ctx/audit-findings.json)" = "APPROVED" ]
    [ "$(jq -r '[.findings[]|select(.rule_id=="todo-comment")]|length' ctx/audit-findings.json)" = "0" ]
}

@test "#1076 d1: prose containing '# TODO:' (not added) is NOT flagged" {
    printf '%s\n' 'note: the literal text # TODO: load from database documents a prior skip' \
        > app/notes.txt
    _metadata "app/notes.txt"
    cat > ctx/pr-diff.patch <<'DIFF'
diff --git a/app/notes.txt b/app/notes.txt
--- a/app/notes.txt
+++ b/app/notes.txt
@@ -1,1 +1,1 @@
 note: the literal text # TODO: load from database documents a prior skip
DIFF
    run run_audit "ctx"
    [ "$status" -eq 0 ]
    [ "$(jq -r '[.findings[]|select(.rule_id=="todo-comment")]|length' ctx/audit-findings.json)" = "0" ]
}

@test "#1076 d1: TODO on an ADDED line IS flagged -> CHANGES_REQUIRED" {
    printf '%s\n' '# header' 'y = 2  # TODO: fix this' > app/main.py
    _metadata "app/main.py"
    cat > ctx/pr-diff.patch <<'DIFF'
diff --git a/app/main.py b/app/main.py
--- a/app/main.py
+++ b/app/main.py
@@ -1,1 +1,2 @@
 # header
+y = 2  # TODO: fix this
DIFF
    run run_audit "ctx"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.verdict' ctx/audit-findings.json)" = "CHANGES_REQUIRED" ]
    [ "$(jq -r '[.findings[]|select(.rule_id=="todo-comment")]|length' ctx/audit-findings.json)" = "1" ]
}

@test "#1076 d1: console.log on an ADDED .ts line IS flagged; pre-existing is not" {
    printf '%s\n' 'export const a = 1;' 'console.log("preexisting");' 'console.log("added");' > app/x.ts
    _metadata "app/x.ts"
    cat > ctx/pr-diff.patch <<'DIFF'
diff --git a/app/x.ts b/app/x.ts
--- a/app/x.ts
+++ b/app/x.ts
@@ -1,2 +1,3 @@
 export const a = 1;
 console.log("preexisting");
+console.log("added");
DIFF
    run run_audit "ctx"
    [ "$status" -eq 0 ]
    [ "$(jq -r '[.findings[]|select(.rule_id=="console-log")]|length' ctx/audit-findings.json)" = "1" ]
    # the flagged line must be the ADDED one (line 3), not the pre-existing (line 2)
    [ "$(jq -r '.findings[]|select(.rule_id=="console-log")|.line' ctx/audit-findings.json)" = "3" ]
}

@test "#1076 d1: diff unavailable -> quality nits skipped (fail-safe) -> APPROVED" {
    printf '%s\n' '# TODO: pre-existing only' > app/main.py
    _metadata "app/main.py"
    # No ctx/pr-diff.patch; LOA_POST_PR_DIFF_FILE unset.
    run run_audit "ctx"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.verdict' ctx/audit-findings.json)" = "APPROVED" ]
    [ "$(jq -r '[.findings[]|select(.rule_id=="todo-comment")]|length' ctx/audit-findings.json)" = "0" ]
}
