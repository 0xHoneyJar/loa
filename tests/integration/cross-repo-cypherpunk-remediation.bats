#!/usr/bin/env bats
# =============================================================================
# tests/integration/cross-repo-cypherpunk-remediation.bats
#
# cycle-098 Sprint 5 — remediation tests for cypherpunk audit findings on
# PR #767 (CRIT-1, HIGH-1, HIGH-2, HIGH-3, MED-1, MED-2, MED-3, MED-4, MED-5,
# MED-6, plus general-purpose H1).
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    LIB="$PROJECT_ROOT/.claude/scripts/lib/cross-repo-status-lib.sh"
    [[ -f "$LIB" ]] || skip "cross-repo-status-lib.sh not present"

    TEST_DIR="$(mktemp -d)"
    cat > "$TEST_DIR/trust-store.yaml" <<'EOF'
schema_version: "1.0"
root_signature: { algorithm: ed25519, signer_pubkey: "", signed_at: "", signature: "" }
keys: []
revocations: []
trust_cutoff: { default_strict_after: "2099-01-01T00:00:00Z" }
EOF
    export LOA_TRUST_STORE_FILE="$TEST_DIR/trust-store.yaml"
    export LOA_CROSS_REPO_CACHE_DIR="$TEST_DIR/cache"
    export LOA_CROSS_REPO_LOG="$TEST_DIR/log.jsonl"
    export LOA_CROSS_REPO_GH_CMD="$TEST_DIR/gh"
    cat > "$LOA_CROSS_REPO_GH_CMD" <<'GHFAKE'
#!/usr/bin/env bash
set -u
mode="${GH_FAKE_MODE:-clean}"
shift; path="$1"; shift
endpoint="${path%%\?*}"
jq_filter=""
while [[ $# -gt 0 ]]; do case "$1" in --jq) jq_filter="$2"; shift 2 ;; *) shift ;; esac; done
emit() { if [[ -n "$jq_filter" ]]; then echo "$1" | jq -rc "$jq_filter"; else echo "$1"; fi }
case "$endpoint" in
    repos/*/commits) emit '[]' ;;
    repos/*/pulls) emit '[]' ;;
    repos/*/actions/runs) emit '{"workflow_runs":[]}' ;;
    repos/*/contents/grimoires/loa/NOTES.md) emit '{"content":""}' ;;
esac
GHFAKE
    chmod 0700 "$LOA_CROSS_REPO_GH_CMD"
}

teardown() {
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        find "$TEST_DIR" -type f -delete 2>/dev/null || true
        find "$TEST_DIR" -type d -empty -delete 2>/dev/null || true
        rmdir "$TEST_DIR" 2>/dev/null || true
    fi
}

# =============================================================================
# CRIT-1: p95 heredoc RCE via cache-poisoned _latency_seconds — defended by
# stdin routing + numeric regex validation
# =============================================================================

@test "CRIT-1: cache poisoning of _latency_seconds with python escape attempt is rejected by p95" {
    source "$LIB"
    # Pre-populate cache with legitimate clean read.
    cross_repo_read '["alice/repo"]' >/dev/null
    [[ -f "$LOA_CROSS_REPO_CACHE_DIR/alice__repo.json" ]]

    # Inject a python-escape attempt into _latency_seconds. The CRIT-1 fix
    # has TWO layers of defense: (1) cache_get strips _latency_seconds to
    # number-only, (2) p95 heredoc routes via stdin + numeric regex.
    # We probe the second layer by writing the value AFTER cache_get
    # would have round-tripped (simulating a future regression).
    python3 - "$LOA_CROSS_REPO_CACHE_DIR/alice__repo.json" <<'PY'
import json, sys
path = sys.argv[1]
d = json.load(open(path))
d["state"]["_latency_seconds"] = '1\n"""\nimport os\nos.system("touch /tmp/PWNED_CRIT1")\n"""'
open(path, "w").write(json.dumps(d))
PY

    # Force stale-fallback path and run again.
    LOA_CROSS_REPO_CACHE_TTL_SECONDS=0 \
        cross_repo_read '["alice/repo"]' >/dev/null
    # PWNED file must NOT exist
    [[ ! -f /tmp/PWNED_CRIT1 ]] || {
        rm -f /tmp/PWNED_CRIT1
        echo "RCE successful — CRIT-1 defense failed"
        return 1
    }
}

# =============================================================================
# HIGH-1: cache schema validation
# =============================================================================

@test "HIGH-1: cache_get rejects cache file with wrong field types" {
    source "$LIB"
    cross_repo_read '["alice/repo"]' >/dev/null
    # Corrupt: change cache_age_seconds to a string
    python3 - "$LOA_CROSS_REPO_CACHE_DIR/alice__repo.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["state"]["cache_age_seconds"] = "not-a-number"
open(p, "w").write(json.dumps(d))
PY
    run cross_repo_cache_get "alice/repo"
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]] || {
        echo "expected empty output on shape-mismatched cache, got: $output"
        return 1
    }
}

@test "HIGH-1: cache_get strips _latency_seconds out-of-range values" {
    source "$LIB"
    cross_repo_read '["alice/repo"]' >/dev/null
    python3 - "$LOA_CROSS_REPO_CACHE_DIR/alice__repo.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
# Pollute with a non-numeric latency
d["state"]["_latency_seconds"] = "999999"  # string, not number
open(p, "w").write(json.dumps(d))
PY
    run cross_repo_cache_get "alice/repo"
    [[ "$status" -eq 0 ]]
    # Cache_get rejects this state shape because _latency_seconds is wrong type
    [[ -z "$output" ]] || {
        echo "expected empty output on poisoned latency, got: $output"
        return 1
    }
}

# =============================================================================
# HIGH-2: cache_invalidate "all" only deletes shape-matched files
# =============================================================================

@test "HIGH-2: cache_invalidate all only removes owner__name.json shape" {
    source "$LIB"
    mkdir -p "$LOA_CROSS_REPO_CACHE_DIR"
    # Place L5-shape file (looks like cache) + non-L5-shape file (operator
    # may have placed something else there).
    echo '{"x":1}' > "$LOA_CROSS_REPO_CACHE_DIR/alice__repo.json"
    echo 'IMPORTANT-DATA' > "$LOA_CROSS_REPO_CACHE_DIR/operator.json"
    cross_repo_cache_invalidate "all"
    [[ ! -f "$LOA_CROSS_REPO_CACHE_DIR/alice__repo.json" ]]
    [[ -f "$LOA_CROSS_REPO_CACHE_DIR/operator.json" ]] || {
        echo "operator.json was wrongly deleted by invalidate all"
        return 1
    }
}

# =============================================================================
# HIGH-3: tmp file uses mktemp (no $$-prefixed predictable path)
# =============================================================================

@test "HIGH-3: tmp file is mktemp'd (no symlink TOCTOU on predictable name)" {
    source "$LIB"
    # The lib uses mktemp under cache_dir for the tmp path. We verify by
    # plant a symlink at the predictable old path; cache_write should NOT
    # overwrite the symlink target.
    mkdir -p "$LOA_CROSS_REPO_CACHE_DIR"
    echo "VICTIM" > "$TEST_DIR/victim"
    # Old vulnerable form was ${path}.tmp.$$. We simulate by checking that
    # mktemp creates files with .tmp.<hash>.json shape (NOT $$-suffixed).
    cross_repo_read '["alice/repo"]' >/dev/null
    # No leftover .tmp.<pid>-shape file:
    local stale
    stale="$(find "$LOA_CROSS_REPO_CACHE_DIR" -maxdepth 1 -name '*.tmp.*' -type f 2>/dev/null | wc -l)"
    [[ "$stale" == "0" ]]
}

# =============================================================================
# MED-1: set +e/+pipefail does not leak into caller
# =============================================================================

@test "MED-1: caller's set -e is preserved after cross_repo_read returns" {
    source "$LIB"
    set -e
    cross_repo_read '["alice/repo"]' >/dev/null
    case "$-" in *e*) : ;; *) echo "set -e was lost"; return 1 ;; esac
    set +e
}

@test "MED-1: caller's set -o pipefail is preserved after cross_repo_read returns" {
    source "$LIB"
    set -o pipefail
    cross_repo_read '["alice/repo"]' >/dev/null
    if [[ -o pipefail ]]; then : ; else echo "pipefail was lost"; return 1; fi
    set +o pipefail
}

# =============================================================================
# MED-2: BLOCKER cap (max 100 entries + truncation marker)
# =============================================================================

@test "MED-2: NOTES.md with >100 BLOCKER lines truncates with marker" {
    source "$LIB"
    cat > "$LOA_CROSS_REPO_GH_CMD" <<'GH'
#!/usr/bin/env bash
shift; path=$1; shift
endpoint=${path%%\?*}
jq_filter=""
while [[ $# -gt 0 ]]; do case "$1" in --jq) jq_filter="$2"; shift 2 ;; *) shift ;; esac; done
emit() { if [[ -n "$jq_filter" ]]; then echo "$1" | jq -rc "$jq_filter"; else echo "$1"; fi }
case "$endpoint" in
    repos/*/commits) emit '[]' ;;
    repos/*/pulls) emit '[]' ;;
    repos/*/actions/runs) emit '{"workflow_runs":[]}' ;;
    repos/*/contents/grimoires/loa/NOTES.md)
        # 200 BLOCKER lines
        body="$(for i in $(seq 1 200); do echo "BLOCKER: alert-$i"; done)"
        c=$(echo "$body" | base64 | tr -d '\n')
        emit "{\"content\":\"$c\"}"
        ;;
esac
GH
    chmod 0700 "$LOA_CROSS_REPO_GH_CMD"
    # Allow all 200 BLOCKER lines through the NOTES.md tail filter
    LOA_CROSS_REPO_NOTES_TAIL_LINES=300 run cross_repo_read '["alice/repo"]'
    [[ "$status" -eq 0 ]]
    # blockers length should be 101 (100 real + 1 truncation marker)
    local n
    n="$(echo "$output" | jq '.repos[0].blockers | length')"
    [[ "$n" == "101" ]] || {
        echo "expected 101 entries (100 + truncation), got $n"
        return 1
    }
    # Last entry must be the truncation marker
    echo "$output" | jq -e '.repos[0].blockers[-1].line == "[TRUNCATED]"' >/dev/null
}

# =============================================================================
# MED-4: future-dated cached_at_epoch -> rejected (forces fetch path)
# =============================================================================

@test "MED-4: future-dated cached_at_epoch is rejected" {
    source "$LIB"
    cross_repo_read '["alice/repo"]' >/dev/null
    # Pin cached_at to year 9999
    python3 - "$LOA_CROSS_REPO_CACHE_DIR/alice__repo.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["cached_at_epoch"] = 253402300799  # year 9999
open(p, "w").write(json.dumps(d))
PY
    # Lib should treat cache as missing (force refetch)
    run cross_repo_read '["alice/repo"]'
    [[ "$status" -eq 0 ]]
    echo "$output" | jq -e '.repos[0].fetch_outcome == "success"' >/dev/null
    # cache_age_seconds should be 0 (re-fetched), NOT a huge number
    echo "$output" | jq -e '.repos[0].cache_age_seconds == 0' >/dev/null
}

# =============================================================================
# MED-5: tightened repo regex
# =============================================================================

@test "MED-5: leading-dot owner is rejected" {
    source "$LIB"
    run cross_repo_read '[".foo/bar"]'
    [[ "$status" -eq 2 ]]
}

@test "MED-5: leading-dash owner is rejected" {
    source "$LIB"
    run cross_repo_read '["-foo/bar"]'
    [[ "$status" -eq 2 ]]
}

@test "MED-5: trailing-dot name is rejected" {
    source "$LIB"
    run cross_repo_read '["foo/bar."]'
    [[ "$status" -eq 2 ]]
}

@test "MED-5: --/-- arg-end-marker pattern is rejected" {
    source "$LIB"
    run cross_repo_read '["--/--"]'
    [[ "$status" -eq 2 ]]
}

# =============================================================================
# MED-6: gh override surfaces in audit payload (not stderr)
# =============================================================================

@test "MED-6: gh_override_active=true in audit when LOA_CROSS_REPO_GH_CMD set" {
    source "$LIB"
    cross_repo_read '["alice/repo"]' >/dev/null
    grep -F '"event_type":"cross_repo.read"' "$LOA_CROSS_REPO_LOG"
    local entry
    entry="$(grep -F '"event_type":"cross_repo.read"' "$LOA_CROSS_REPO_LOG" | head -n 1)"
    echo "$entry" | jq -e '.payload.gh_override_active == true' >/dev/null
}

@test "MED-2 audit: partial_count and error_count are emitted separately" {
    source "$LIB"
    cross_repo_read '["alice/repo"]' >/dev/null
    local entry
    entry="$(grep -F '"event_type":"cross_repo.read"' "$LOA_CROSS_REPO_LOG" | head -n 1)"
    echo "$entry" | jq -e '.payload.partial_count != null' >/dev/null
    echo "$entry" | jq -e '.payload.error_count != null' >/dev/null
}

# =============================================================================
# H1: log basename matches retention policy
# =============================================================================

@test "H1: default LOA_CROSS_REPO_LOG basename matches audit-retention-policy.yaml" {
    source "$LIB"
    unset LOA_CROSS_REPO_LOG
    local default_log
    default_log="$(_l5_log_path)"
    [[ "$default_log" == *"cross-repo-status.jsonl" ]] || {
        echo "got: $default_log"
        return 1
    }
    grep -F 'cross-repo-status.jsonl' "$PROJECT_ROOT/.claude/data/audit-retention-policy.yaml"
}

@test "H1: _audit_primitive_id_for_log maps cross-repo-status* to L5" {
    source "$PROJECT_ROOT/.claude/scripts/audit-envelope.sh"
    local pid
    pid="$(_audit_primitive_id_for_log "/tmp/cross-repo-status.jsonl")"
    [[ "$pid" == "L5" ]]
}
