#!/usr/bin/env bats
# =============================================================================
# Cycle-108 sprint-2 T2.I — tools/sprint-kind-classify.py
# =============================================================================
# Validates the multi-feature scored stratifier and operator override path.
# Tests are HERMETIC: each test creates a fresh sandbox git repo + commits
# files designed to match exactly one stratum rule, then classifies and
# asserts the picked stratum.
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    CLASSIFY="$REPO_ROOT/tools/sprint-kind-classify.py"
    SANDBOX="$(mktemp -d)"
    cd "$SANDBOX"
    git init -q
    git config user.email "test@example.com"
    git config user.name "test"
    # Initial commit so we have a pre_sha.
    echo "init" > README.md
    git add README.md
    git commit -q -m "init"
    PRE_SHA="$(git rev-parse HEAD)"
}

teardown() {
    rm -rf "$SANDBOX"
}

_classify() {
    local post_sha
    post_sha="$(git rev-parse HEAD)"
    python3 "$CLASSIFY" --pre-sha "$PRE_SHA" --post-sha "$post_sha" --repo-root "$SANDBOX"
}

@test "T2.I: classifies cryptographic stratum (ed25519 / signature paths)" {
    mkdir -p lib/crypto
    echo "ed25519 stub" > lib/crypto/signing.py
    echo "audit-keys-bootstrap stub" > docs/audit-keys-bootstrap.md
    git add .
    git commit -q -m "crypto"
    run _classify
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.stratum == "cryptographic"'
}

@test "T2.I: classifies parser stratum (parser/grammar paths)" {
    mkdir -p src
    echo "parser stub" > src/parser.rs
    echo "lexer stub" > src/lexer.rs
    echo "grammar" > src/grammar.bnf
    git add .
    git commit -q -m "parser"
    run _classify
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.stratum == "parser"'
}

@test "T2.I: classifies audit-envelope stratum (envelope / modelinv paths)" {
    mkdir -p .claude/scripts
    echo "audit-envelope.sh stub" > .claude/scripts/audit-envelope.sh
    echo "modelinv stub" > .claude/scripts/modelinv-rollup.sh
    git add .
    git commit -q -m "audit"
    run _classify
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.stratum == "audit-envelope"'
}

@test "T2.I: classifies testing stratum (tests/ + .bats paths)" {
    mkdir -p tests/unit
    echo "test stub" > tests/unit/my.bats
    echo "test stub" > tests/unit/test_other.py
    git add .
    git commit -q -m "tests"
    run _classify
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.stratum == "testing"'
}

@test "T2.I: classifies infrastructure stratum (workflows / docker)" {
    mkdir -p .github/workflows
    echo "workflow" > .github/workflows/ci.yml
    echo "FROM alpine" > Dockerfile
    git add .
    git commit -q -m "infra"
    run _classify
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.stratum == "infrastructure"'
}

@test "T2.I: classifies frontend stratum (.tsx / package.json)" {
    mkdir -p components
    echo "tsx stub" > components/Hello.tsx
    echo "{}" > package.json
    git add .
    git commit -q -m "frontend"
    run _classify
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.stratum == "frontend"'
}

@test "T2.I: glue stratum is low-confidence default (.sh edits only)" {
    mkdir -p scripts
    echo "echo hi" > scripts/run.sh
    git add .
    git commit -q -m "glue"
    run _classify
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.stratum == "glue"'
}

@test "T2.I: multi-feature — higher-confidence stratum wins over glue" {
    # Mix: 2 crypto files + 5 shell scripts. Crypto's higher confidence wins.
    mkdir -p crypto scripts
    echo "ed25519" > crypto/signing.py
    echo "signature" > crypto/verify.py
    for i in 1 2 3 4 5; do
        echo "echo $i" > "scripts/x$i.sh"
    done
    git add .
    git commit -q -m "mixed"
    run _classify
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.stratum == "cryptographic"'
}

@test "T2.I: priority tie-breaking — crypto > parser when both have equal hits" {
    mkdir -p src
    echo "ed25519" > src/signing.py        # crypto
    echo "parser stub" > src/parser.rs     # parser
    git add .
    git commit -q -m "equal-hits"
    run _classify
    [ "$status" -eq 0 ]
    # Crypto has higher priority; expect crypto wins.
    echo "$output" | jq -e '.stratum == "cryptographic"'
}

@test "T2.I: --stratum-override pins operator decision" {
    mkdir -p crypto
    echo "ed25519" > crypto/signing.py
    git add .
    git commit -q -m "would-be-crypto"
    post_sha="$(git rev-parse HEAD)"
    audit_log="$SANDBOX/audit/classification.jsonl"
    run python3 "$CLASSIFY" --pre-sha "$PRE_SHA" --post-sha "$post_sha" \
        --repo-root "$SANDBOX" --stratum-override "testing" \
        --rationale "operator-marks-as-testing" \
        --audit-log "$audit_log"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.stratum == "testing"'
    echo "$output" | jq -e '.confidence == 1.0'
    echo "$output" | jq -e '.override_origin.original_stratum == "cryptographic"'
    [ -f "$audit_log" ]
    grep -q "operator-marks-as-testing" "$audit_log"
}

@test "T2.I: --stratum-override REQUIRES --rationale" {
    mkdir -p crypto
    echo "ed25519" > crypto/signing.py
    git add .
    git commit -q -m "x"
    post_sha="$(git rev-parse HEAD)"
    run python3 "$CLASSIFY" --pre-sha "$PRE_SHA" --post-sha "$post_sha" \
        --repo-root "$SANDBOX" --stratum-override testing
    [ "$status" -eq 2 ]
    echo "$output" | grep -q "requires --rationale"
}

@test "T2.I: --stratum-override unknown stratum rejected" {
    mkdir -p crypto
    echo "x" > crypto/signing.py
    git add .
    git commit -q -m "x"
    post_sha="$(git rev-parse HEAD)"
    run python3 "$CLASSIFY" --pre-sha "$PRE_SHA" --post-sha "$post_sha" \
        --repo-root "$SANDBOX" --stratum-override invalid_kind --rationale "r"
    [ "$status" -eq 2 ]
    echo "$output" | grep -q "unknown stratum"
}

@test "T2.I: classifier is deterministic (same input → byte-identical output)" {
    mkdir -p crypto
    echo "ed25519" > crypto/signing.py
    git add .
    git commit -q -m "det"
    post_sha="$(git rev-parse HEAD)"
    python3 "$CLASSIFY" --pre-sha "$PRE_SHA" --post-sha "$post_sha" --repo-root "$SANDBOX" > /tmp/run1.json
    python3 "$CLASSIFY" --pre-sha "$PRE_SHA" --post-sha "$post_sha" --repo-root "$SANDBOX" > /tmp/run2.json
    diff /tmp/run1.json /tmp/run2.json
    [ "$?" -eq 0 ]
    rm -f /tmp/run1.json /tmp/run2.json
}

@test "T2.I: bulk mode processes multiple sprints" {
    mkdir -p crypto
    echo "x" > crypto/a.py
    git add .
    git commit -q -m "s1"
    sha1="$(git rev-parse HEAD)"
    mkdir -p tests
    echo "test" > tests/a.bats
    git add .
    git commit -q -m "s2"
    sha2="$(git rev-parse HEAD)"
    cat > prs.json <<EOF
[
  {"pre_sha": "$PRE_SHA", "post_sha": "$sha1", "pr_number": 1, "merged_at": "2026-04-01T00:00:00Z"},
  {"pre_sha": "$sha1", "post_sha": "$sha2", "pr_number": 2, "merged_at": "2026-04-02T00:00:00Z"}
]
EOF
    run python3 "$CLASSIFY" --bulk-from-prs-json prs.json --repo-root "$SANDBOX"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e 'length == 2'
    echo "$output" | jq -e '.[0].pr_number == 1'
    echo "$output" | jq -e '.[1].pr_number == 2'
}

@test "T2.I: rule_hits surfaces per-stratum match counts" {
    mkdir -p crypto
    echo "ed25519" > crypto/a.py
    git add .
    git commit -q -m "x"
    run _classify
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.rule_hits.cryptographic > 0'
}
