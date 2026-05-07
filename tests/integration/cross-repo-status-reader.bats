#!/usr/bin/env bats
# =============================================================================
# tests/integration/cross-repo-status-reader.bats
#
# cycle-098 Sprint 5 — FR-L5-1..7 + ACs.
#
# Uses LOA_CROSS_REPO_GH_CMD to point at a per-test fake `gh` script that
# emits canned JSON for the four endpoints L5 hits:
#   repos/<repo>/commits        — commits list
#   repos/<repo>/pulls          — open PRs
#   repos/<repo>/actions/runs   — CI runs
#   repos/<repo>/contents/grimoires/loa/NOTES.md — base64 NOTES
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    LIB="$PROJECT_ROOT/.claude/scripts/lib/cross-repo-status-lib.sh"
    [[ -f "$LIB" ]] || skip "cross-repo-status-lib.sh not present"

    TEST_DIR="$(mktemp -d)"

    # Trust-store fixture for audit_emit.
    TEST_TRUST_STORE="$TEST_DIR/trust-store.yaml"
    cat > "$TEST_TRUST_STORE" <<'EOF'
schema_version: "1.0"
root_signature: { algorithm: ed25519, signer_pubkey: "", signed_at: "", signature: "" }
keys: []
revocations: []
trust_cutoff: { default_strict_after: "2099-01-01T00:00:00Z" }
EOF
    export LOA_TRUST_STORE_FILE="$TEST_TRUST_STORE"

    # Cache + log dirs in TEST_DIR.
    export LOA_CROSS_REPO_CACHE_DIR="$TEST_DIR/cache"
    export LOA_CROSS_REPO_LOG="$TEST_DIR/log.jsonl"
    mkdir -p "$LOA_CROSS_REPO_CACHE_DIR"

    # Fake gh script (mode 0700).
    export LOA_CROSS_REPO_GH_CMD="$TEST_DIR/gh-fake"
    cat > "$LOA_CROSS_REPO_GH_CMD" <<'GHFAKE'
#!/usr/bin/env bash
# gh-fake: emit canned per-endpoint JSON. Behavior controlled by env vars
# the test sets before each invocation:
#   GH_FAKE_MODE         clean | partial_pulls | total_outage | rate_limit | malformed_notes
#   GH_FAKE_DELAY        seconds to sleep before responding (per-call)
#
# We only handle `gh api <path>` invocations.
set -u
mode="${GH_FAKE_MODE:-clean}"
[[ -n "${GH_FAKE_DELAY:-}" ]] && sleep "$GH_FAKE_DELAY"

if [[ "$1" != "api" ]]; then
    echo "gh-fake: unsupported subcommand '$1'" >&2
    exit 2
fi
shift
path="$1"
shift

# Strip query-string for matching.
endpoint="${path%%\?*}"

# Find the --jq filter (if any) so we can apply it to the canned JSON. The
# real `gh api --jq` runs jq over the body; we mimic that.
jq_filter=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --jq) jq_filter="$2"; shift 2 ;;
        *)    shift ;;
    esac
done

emit() {
    local body="$1"
    if [[ -n "$jq_filter" ]]; then
        # Real `gh api --jq` emits strings raw and JSON for non-strings.
        # Use jq -r so .content (a string) lands as raw base64, matching
        # production gh behavior.
        echo "$body" | jq -rc "$jq_filter"
    else
        echo "$body"
    fi
}

# Total outage: every call fails.
if [[ "$mode" == "total_outage" ]]; then
    echo "gh-fake: simulated outage" >&2
    exit 1
fi

case "$endpoint" in
    repos/*/commits)
        emit '[{"sha":"abc1234","commit":{"message":"first\nbody","author":{"name":"alice","date":"2026-05-07T00:00:00Z"}}},{"sha":"def5678","commit":{"message":"second","author":{"name":"bob","date":"2026-05-06T00:00:00Z"}}}]'
        ;;
    repos/*/pulls)
        if [[ "$mode" == "partial_pulls" ]]; then
            echo "gh-fake: simulated pulls failure" >&2
            exit 1
        fi
        emit '[{"number":42,"title":"feat: hello","user":{"login":"alice"},"draft":false}]'
        ;;
    repos/*/actions/runs)
        if [[ "$mode" == "rate_limit" ]]; then
            echo '{"message":"API rate limit exceeded"}' >&2
            exit 1
        fi
        emit '{"workflow_runs":[{"name":"CI","status":"completed","conclusion":"success","run_started_at":"2026-05-07T00:00:00Z"}]}'
        ;;
    repos/*/contents/grimoires/loa/NOTES.md)
        if [[ "$mode" == "malformed_notes" ]]; then
            # Return invalid base64 content
            emit '{"content":"!!!!!\nnot-base64\n"}'
            exit 0
        fi
        # Encode "## NOTES\n\nBLOCKER: production deploy halted\nWARN: staging slow\n* note line\n"
        # NOTE: top-level (not inside a function) — `local` is invalid here.
        content="$(printf '## NOTES\n\nBLOCKER: production deploy halted\nWARN: staging slow\n* note line\n' | base64 | tr -d '\n')"
        emit "{\"content\":\"$content\"}"
        ;;
    *)
        echo "gh-fake: unknown endpoint $endpoint" >&2
        exit 2
        ;;
esac
GHFAKE
    chmod 0700 "$LOA_CROSS_REPO_GH_CMD"

    unset GH_FAKE_MODE GH_FAKE_DELAY
    unset LOA_CROSS_REPO_TEST_NOW LOA_CROSS_REPO_TEST_MODE
}

teardown() {
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        find "$TEST_DIR" -type f -delete 2>/dev/null || true
        find "$TEST_DIR" -type d -empty -delete 2>/dev/null || true
        rmdir "$TEST_DIR" 2>/dev/null || true
    fi
    unset LOA_TRUST_STORE_FILE LOA_CROSS_REPO_CACHE_DIR LOA_CROSS_REPO_LOG
    unset LOA_CROSS_REPO_GH_CMD GH_FAKE_MODE GH_FAKE_DELAY
    unset LOA_CROSS_REPO_TEST_NOW LOA_CROSS_REPO_TEST_MODE
}

# =============================================================================
# Input validation
# =============================================================================

@test "input: missing argument -> exit 2" {
    source "$LIB"
    run cross_repo_read
    [[ "$status" -eq 2 ]]
}

@test "input: empty array -> exit 2" {
    source "$LIB"
    run cross_repo_read '[]'
    [[ "$status" -eq 2 ]]
}

@test "input: non-array -> exit 2" {
    source "$LIB"
    run cross_repo_read '"not-array"'
    [[ "$status" -eq 2 ]]
}

@test "input: invalid repo identifier -> exit 2" {
    source "$LIB"
    run cross_repo_read '["alice; rm -rf /"]'
    [[ "$status" -eq 2 ]]
    run cross_repo_read '["../etc/passwd"]'
    [[ "$status" -eq 2 ]]
    run cross_repo_read '["owner..name/repo"]'
    [[ "$status" -eq 2 ]]
}

@test "input: too many repos (>50) -> exit 2" {
    source "$LIB"
    local big='['
    for i in $(seq 1 51); do
        if (( i > 1 )); then big="$big,"; fi
        big="$big\"o$i/r$i\""
    done
    big="$big]"
    run cross_repo_read "$big"
    [[ "$status" -eq 2 ]]
}

# =============================================================================
# FR-L5-1: clean read
# =============================================================================

@test "FR-L5-1: clean read returns CrossRepoState" {
    source "$LIB"
    GH_FAKE_MODE=clean run cross_repo_read '["alice/repo1"]'
    [[ "$status" -eq 0 ]]
    echo "$output" | jq -e '.repos | length == 1' >/dev/null
    echo "$output" | jq -e '.repos[0].repo == "alice/repo1"' >/dev/null
    echo "$output" | jq -e '.repos[0].fetch_outcome == "success"' >/dev/null
    echo "$output" | jq -e '.repos[0].recent_commits | length == 2' >/dev/null
    echo "$output" | jq -e '.repos[0].open_prs[0].number == 42' >/dev/null
    echo "$output" | jq -e '.repos[0].ci_runs[0].workflow == "CI"' >/dev/null
}

@test "FR-L5-1: schema validates against trust-state schema" {
    if ! command -v ajv >/dev/null 2>&1; then
        skip "ajv not installed"
    fi
    source "$LIB"
    GH_FAKE_MODE=clean run cross_repo_read '["alice/repo1"]'
    [[ "$status" -eq 0 ]]
    local rfile
    rfile="$(mktemp)"
    printf '%s' "$output" > "$rfile"
    run ajv validate -s "$PROJECT_ROOT/.claude/data/trajectory-schemas/cross-repo-events/cross-repo-state.schema.json" \
        -d "$rfile" --strict=false
    rm -f "$rfile"
    [[ "$status" -eq 0 ]] || {
        echo "ajv: $output"
        return 1
    }
}

# =============================================================================
# FR-L5-4: BLOCKER extraction from NOTES.md tail
# =============================================================================

@test "FR-L5-4: BLOCKER + WARN markers extracted from NOTES.md tail" {
    source "$LIB"
    GH_FAKE_MODE=clean run cross_repo_read '["alice/repo1"]'
    [[ "$status" -eq 0 ]]
    echo "$output" | jq -e '.repos[0].blockers | length == 2' >/dev/null
    echo "$output" | jq -e '.repos[0].blockers[] | select(.severity == "BLOCKER") | .context' >/dev/null
    echo "$output" | jq -e '.repos[0].blockers[] | select(.severity == "WARN") | .context' >/dev/null
    # Trust boundary: BLOCKER content kept verbatim, not interpreted.
    echo "$output" | jq -e '.repos[0].blockers[] | select(.severity == "BLOCKER") | .context | contains("production deploy halted")' >/dev/null
}

@test "FR-L5-4: malformed NOTES.md does not abort fetch (per-source error capture)" {
    source "$LIB"
    GH_FAKE_MODE=malformed_notes run cross_repo_read '["alice/repo1"]'
    [[ "$status" -eq 0 ]]
    # NOTES.md decode failure -> empty notes; other endpoints still succeed
    echo "$output" | jq -e '.repos[0].fetch_outcome == "success"' >/dev/null
    echo "$output" | jq -e '.repos[0].recent_commits | length == 2' >/dev/null
    echo "$output" | jq -e '.repos[0].blockers == []' >/dev/null
}

# =============================================================================
# FR-L5-5: per-source error capture (one failure does not abort full read)
# =============================================================================

@test "FR-L5-5: pulls endpoint failure -> partial outcome; other endpoints succeed" {
    source "$LIB"
    GH_FAKE_MODE=partial_pulls run cross_repo_read '["alice/repo1"]'
    [[ "$status" -eq 0 ]]
    echo "$output" | jq -e '.repos[0].fetch_outcome == "partial"' >/dev/null
    echo "$output" | jq -e '.repos[0].recent_commits | length == 2' >/dev/null
    echo "$output" | jq -e '.repos[0].open_prs == []' >/dev/null
    echo "$output" | jq -e '.repos[0].error_diagnostic | contains("pulls")' >/dev/null
}

@test "FR-L5-5: 429 / rate-limit error captured per-endpoint without aborting" {
    source "$LIB"
    GH_FAKE_MODE=rate_limit run cross_repo_read '["alice/repo1"]'
    [[ "$status" -eq 0 ]]
    echo "$output" | jq -e '.repos[0].fetch_outcome == "partial"' >/dev/null
    echo "$output" | jq -e '.repos[0].error_diagnostic | contains("rate limit") or contains("runs")' >/dev/null
    echo "$output" | jq -e '.repos[0].ci_runs == []' >/dev/null
}

# =============================================================================
# FR-L5-2: gh API rate-limit handling — 429 routed via partial-failure + cache fallback
# =============================================================================

@test "FR-L5-2: rate-limit failure on subsequent call still preserves earlier successes" {
    source "$LIB"
    # First a clean fetch to populate cache.
    GH_FAKE_MODE=clean cross_repo_read '["alice/repo1"]' >/dev/null
    [[ -f "$LOA_CROSS_REPO_CACHE_DIR/alice__repo1.json" ]]
    # Force cache fresh-window expiry by setting TTL to 0; then rate-limit.
    LOA_CROSS_REPO_CACHE_TTL_SECONDS=0 GH_FAKE_MODE=rate_limit run cross_repo_read '["alice/repo1"]'
    [[ "$status" -eq 0 ]]
    # rate_limit fails one endpoint -> fetch_outcome=partial; cache updated.
    echo "$output" | jq -e '.repos[0].fetch_outcome == "partial"' >/dev/null
}

# =============================================================================
# FR-L5-3: stale fallback when API unreachable
# =============================================================================

@test "FR-L5-3: stale fallback serves cached state when API in total outage" {
    source "$LIB"
    # Populate cache with clean read.
    GH_FAKE_MODE=clean cross_repo_read '["alice/repo1"]' >/dev/null
    # Simulate cache becoming stale: force TTL=0 + force outage.
    LOA_CROSS_REPO_CACHE_TTL_SECONDS=0 \
        GH_FAKE_MODE=total_outage run cross_repo_read '["alice/repo1"]'
    [[ "$status" -eq 0 ]]
    echo "$output" | jq -e '.repos[0].fetch_outcome == "stale_fallback"' >/dev/null
    echo "$output" | jq -e '.repos[0].cache_age_seconds >= 0' >/dev/null
    # Cached commits surface in the fallback response.
    echo "$output" | jq -e '.repos[0].recent_commits | length == 2' >/dev/null
}

@test "FR-L5-3: stale fallback respects fallback_stale_max_seconds ceiling" {
    source "$LIB"
    GH_FAKE_MODE=clean cross_repo_read '["alice/repo1"]' >/dev/null
    # Simulate ancient cache: write cached_at_epoch far in the past
    local cache="$LOA_CROSS_REPO_CACHE_DIR/alice__repo1.json"
    python3 -c "
import json,sys
p='$cache'
d=json.load(open(p))
d['cached_at_epoch']=1
open(p,'w').write(json.dumps(d))
"
    # API outage; cache is older than fallback_stale_max -> error fetch_outcome
    LOA_CROSS_REPO_CACHE_TTL_SECONDS=0 \
        LOA_CROSS_REPO_FALLBACK_STALE_MAX=60 \
        GH_FAKE_MODE=total_outage run cross_repo_read '["alice/repo1"]'
    [[ "$status" -eq 0 ]]
    # Beyond fallback ceiling -> error
    echo "$output" | jq -e '.repos[0].fetch_outcome == "error"' >/dev/null
}

# =============================================================================
# FR-L5-3 cache freshness: served from cache without network call
# =============================================================================

@test "FR-L5-3 fresh cache: second read inside TTL serves from cache" {
    source "$LIB"
    GH_FAKE_MODE=clean cross_repo_read '["alice/repo1"]' >/dev/null
    # Move gh-fake aside so any actual call would error
    mv "$LOA_CROSS_REPO_GH_CMD" "$LOA_CROSS_REPO_GH_CMD.disabled"
    # cmd present check passes only if gh is found in PATH; we keep
    # LOA_CROSS_REPO_GH_CMD pointing at the now-missing path. The command -v
    # check at top of cross_repo_read should fail. Workaround: re-create fake
    # but make all calls fail; if fresh cache is honored, no calls happen.
    cat > "$LOA_CROSS_REPO_GH_CMD" <<'EOF'
#!/usr/bin/env bash
echo "fresh-cache-test should not call gh" >&2
exit 99
EOF
    chmod 0700 "$LOA_CROSS_REPO_GH_CMD"
    LOA_CROSS_REPO_CACHE_TTL_SECONDS=3600 run cross_repo_read '["alice/repo1"]'
    [[ "$status" -eq 0 ]]
    echo "$output" | jq -e '.repos[0].fetch_outcome == "success"' >/dev/null
    echo "$output" | jq -e '.repos[0].cache_age_seconds >= 0' >/dev/null
}

# =============================================================================
# FR-L5-6: idempotent call shape
# =============================================================================

@test "FR-L5-6: same call returns same shape modulo timestamps" {
    source "$LIB"
    # BB iter-1 F6 (conf 0.85): export so the var reaches gh-fake's child
    # process. Without export, gh-fake fell through to its default mode
    # (which happens to also be clean — vacuous green; non-vacuous now).
    export GH_FAKE_MODE=clean
    local out1 out2
    out1="$(cross_repo_read '["alice/repo1"]')"
    out2="$(cross_repo_read '["alice/repo1"]')"
    # Strip volatile fields
    local s1 s2
    s1="$(echo "$out1" | jq 'del(.fetched_at, .repos[].fetched_at, .repos[].cache_age_seconds, .p95_latency_seconds)')"
    s2="$(echo "$out2" | jq 'del(.fetched_at, .repos[].fetched_at, .repos[].cache_age_seconds, .p95_latency_seconds)')"
    [[ "$s1" == "$s2" ]]
}

# =============================================================================
# FR-L5-7 cache-cold + cache-warm
# =============================================================================

@test "FR-L5-7: full API outage cold-cache -> error fetch_outcome (no fallback available)" {
    source "$LIB"
    GH_FAKE_MODE=total_outage run cross_repo_read '["alice/repo1"]'
    [[ "$status" -eq 0 ]]
    echo "$output" | jq -e '.repos[0].fetch_outcome == "error"' >/dev/null
    echo "$output" | jq -e '.repos[0].error_diagnostic | length > 0' >/dev/null
}

@test "FR-L5-7: full API outage warm-cache within fallback window -> stale_fallback" {
    source "$LIB"
    GH_FAKE_MODE=clean cross_repo_read '["alice/repo1"]' >/dev/null
    LOA_CROSS_REPO_CACHE_TTL_SECONDS=0 \
        GH_FAKE_MODE=total_outage run cross_repo_read '["alice/repo1"]'
    [[ "$status" -eq 0 ]]
    echo "$output" | jq -e '.repos[0].fetch_outcome == "stale_fallback"' >/dev/null
}

@test "FR-L5-7: multiple repos with mixed outcomes do not abort each other" {
    source "$LIB"
    # Pre-populate alice/repo1 only
    GH_FAKE_MODE=clean cross_repo_read '["alice/repo1"]' >/dev/null
    LOA_CROSS_REPO_CACHE_TTL_SECONDS=0 \
        GH_FAKE_MODE=total_outage run cross_repo_read '["alice/repo1","bob/no-cache"]'
    [[ "$status" -eq 0 ]]
    echo "$output" | jq -e '.repos | length == 2' >/dev/null
    # alice/repo1 has cache -> stale_fallback
    echo "$output" | jq -e '.repos[0].repo == "alice/repo1"' >/dev/null
    echo "$output" | jq -e '.repos[0].fetch_outcome == "stale_fallback"' >/dev/null
    # bob/no-cache cold-cache + outage -> error
    echo "$output" | jq -e '.repos[1].repo == "bob/no-cache"' >/dev/null
    echo "$output" | jq -e '.repos[1].fetch_outcome == "error"' >/dev/null
    # Aggregate partial_failures count
    echo "$output" | jq -e '.partial_failures == 2' >/dev/null
}

# =============================================================================
# Cache helpers
# =============================================================================

@test "cache: cache_get returns cached state JSON" {
    source "$LIB"
    GH_FAKE_MODE=clean cross_repo_read '["alice/repo1"]' >/dev/null
    run cross_repo_cache_get "alice/repo1"
    [[ "$status" -eq 0 ]]
    echo "$output" | jq -e '.repo == "alice/repo1"' >/dev/null
}

@test "cache: cache_get returns empty for unknown repo" {
    source "$LIB"
    run cross_repo_cache_get "alice/unseen"
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
}

@test "cache: cache_invalidate removes specific repo" {
    source "$LIB"
    GH_FAKE_MODE=clean cross_repo_read '["alice/repo1"]' >/dev/null
    [[ -f "$LOA_CROSS_REPO_CACHE_DIR/alice__repo1.json" ]]
    cross_repo_cache_invalidate "alice/repo1"
    [[ ! -f "$LOA_CROSS_REPO_CACHE_DIR/alice__repo1.json" ]]
}

@test "cache: cache_invalidate 'all' wipes everything" {
    source "$LIB"
    GH_FAKE_MODE=clean cross_repo_read '["alice/repo1","bob/repo2"]' >/dev/null
    cross_repo_cache_invalidate "all"
    local n
    n="$(find "$LOA_CROSS_REPO_CACHE_DIR" -name '*.json' -type f 2>/dev/null | wc -l)"
    [[ "$n" == "0" ]]
}

@test "cache: cache files have mode 0600" {
    source "$LIB"
    GH_FAKE_MODE=clean cross_repo_read '["alice/repo1"]' >/dev/null
    local m
    m="$(stat -c '%a' "$LOA_CROSS_REPO_CACHE_DIR/alice__repo1.json")"
    [[ "$m" == "600" ]]
}

# =============================================================================
# Audit envelope event
# =============================================================================

@test "audit: cross_repo.read event emitted with summary metrics" {
    source "$LIB"
    GH_FAKE_MODE=clean cross_repo_read '["alice/repo1"]' >/dev/null
    [[ -f "$LOA_CROSS_REPO_LOG" ]]
    grep -F '"event_type":"cross_repo.read"' "$LOA_CROSS_REPO_LOG"
    local entry
    entry="$(grep -F '"event_type":"cross_repo.read"' "$LOA_CROSS_REPO_LOG" | head -n 1)"
    echo "$entry" | jq -e '.payload.repos_count == 1' >/dev/null
    echo "$entry" | jq -e '.payload.success_count == 1' >/dev/null
    echo "$entry" | jq -e '.payload.error_count == 0' >/dev/null
    echo "$entry" | jq -e '.payload.blockers_total == 2' >/dev/null
}

# =============================================================================
# Test-mode env-var gate (mirrors L4 MED-4 fix)
# =============================================================================

@test "LOA_CROSS_REPO_TEST_NOW: ignored outside test-mode" {
    source "$LIB"
    # When BATS_TEST_DIRNAME set (we're under bats), AND TEST_MODE=1,
    # the override IS honored.
    LOA_CROSS_REPO_TEST_MODE=1 LOA_CROSS_REPO_TEST_NOW="2030-01-01T00:00:00.000Z" \
        run bash -c "source '$LIB'; _l5_now_iso8601"
    [[ "$output" == "2030-01-01T00:00:00.000Z" ]] || {
        echo "got: $output"
        return 1
    }
    # Without TEST_MODE and BATS_TEST_DIRNAME explicitly cleared, override ignored.
    run env -u BATS_TEST_DIRNAME bash -c "
        source '$LIB'
        LOA_CROSS_REPO_TEST_NOW='1970-01-01T00:00:00.000Z' _l5_now_iso8601
    "
    [[ "$output" != "1970-01-01T00:00:00.000Z" ]]
    [[ "$output" == "20"* ]]
}
