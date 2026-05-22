#!/usr/bin/env bats
# =============================================================================
# Issue #938 — butterfreezone-validate false-positive for Express/Fastify
# route params
# =============================================================================
# Pre-fix, the validator's `path:symbol` backtick regex matched route
# patterns like `/factors/:factorId` and reported `/factors/` as a
# missing file. Affected every loa consumer with Express/Fastify routes.
#
# Fix (candidate A from issue body): skip references where file starts
# with `/` AND has no extension. Routes always match; real absolute-path
# file references have extensions and still get validated.
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    VALIDATE="$REPO_ROOT/.claude/scripts/butterfreezone-validate.sh"
    [[ -f "$VALIDATE" ]] || skip "butterfreezone-validate.sh not found"

    TMP_DIR="$(mktemp -d)"
}

teardown() {
    rm -rf "$TMP_DIR"
}

# Build a minimal BFZ-shaped document with the failing route pattern.
_write_bfz() {
    local out="$1"
    cat > "$out" <<'EOF'
<!-- AGENT-CONTEXT
name: test-consumer
type: webapp
version: v0.1.0
-->

# Test Consumer

## What this does

Test fixture for #938 regression.

### HTTP Routes
<!-- provenance: tier2_grep src/routes/*.ts -->

- **GET** `/factors/:factorId` (`./src/routes/config.ts:154`)
- **POST** `/users/:userId/sessions` (`./src/routes/auth.ts:42`)
- **GET** `/health` (`./src/routes/health.ts:8`)

### Real file references
<!-- provenance: tier1_explicit -->

- See `./src/index.ts:bootstrap` for the entry point.
EOF
}

@test "#938: Express route params don't trip validate_references" {
    local bfz="$TMP_DIR/BFZ.md"
    _write_bfz "$bfz"

    # Create the real file references so they don't false-positive
    # for OTHER reasons (missing file). We're testing only the
    # route-param skip logic.
    mkdir -p "$TMP_DIR/src/routes"
    echo "function bootstrap() {}" > "$TMP_DIR/src/index.ts"
    echo "// L154" > "$TMP_DIR/src/routes/config.ts"
    echo "// L42" > "$TMP_DIR/src/routes/auth.ts"
    echo "// L8" > "$TMP_DIR/src/routes/health.ts"

    cd "$TMP_DIR" || exit 1
    run bash "$VALIDATE" --file "$bfz"

    # The pre-fix failure mode was:
    #   FAIL: Referenced file missing: /factors/ (in `/factors/:factorId`)
    # Post-fix that line MUST NOT appear in output.
    ! [[ "$output" == *"Referenced file missing: /factors/"* ]]
    ! [[ "$output" == *"Referenced file missing: /users/"* ]]
}

@test "#938: real absolute path with extension is still validated" {
    local bfz="$TMP_DIR/BFZ.md"
    cat > "$bfz" <<'EOF'
<!-- AGENT-CONTEXT
name: test
type: lib
version: v0.1.0
-->

# Test

## What this does

Validates we still flag missing real absolute-path references.

### Files
<!-- provenance: tier1_explicit -->

- See `/nonexistent/path/foo.sh:bootstrap` for the entry point.
EOF

    cd "$TMP_DIR" || exit 1
    run bash "$VALIDATE" --file "$bfz"

    # The /nonexistent/path/foo.sh has a .sh extension, so the skip
    # heuristic doesn't apply — it should still report missing.
    [[ "$output" == *"Referenced file missing: /nonexistent/path/foo.sh"* ]]
}

@test "#938: relative path with extension still validated normally" {
    local bfz="$TMP_DIR/BFZ.md"
    cat > "$bfz" <<'EOF'
<!-- AGENT-CONTEXT
name: test
type: lib
version: v0.1.0
-->

# Test

## What this does

Validates relative-path refs still work.

### Files
<!-- provenance: tier1_explicit -->

- See `./src/missing.ts:Foo` for the entry point.
EOF

    cd "$TMP_DIR" || exit 1
    run bash "$VALIDATE" --file "$bfz"

    # ./src/missing.ts starts with `.`, doesn't start with `/`, has
    # extension → falls through to the normal existence check → MISS.
    [[ "$output" == *"Referenced file missing: ./src/missing.ts"* ]]
}
