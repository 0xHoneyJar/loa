#!/usr/bin/env bash
# ensure_license_fixtures.sh — idempotently ensure license-validation test
# fixtures exist (gitignored .pem + paired license JSON files).
#
# Background: cycle-028 sprint-19 removed static PEM files from the repo
# and made keypairs ephemeral via generate_test_keypair() in mock_server.py.
# But 4 bats files in tests/unit/ still call `cp $FIXTURES_DIR/mock_public_key.pem`
# at setup() — that fixture path is gitignored and absent on a fresh checkout.
# Result: ~108 bats failures all stem from this one missing fixture (#953).
#
# This helper is called from each affected bats file's setup(). On first
# call per checkout, it runs generate_test_licenses.py which now writes
# the public key + regenerates the signed license fixtures together. On
# subsequent calls (file exists), it's a no-op.
#
# Usage:
#   In bats setup(): source "$FIXTURES_DIR/ensure_license_fixtures.sh"
#
# Exit codes:
#   0  ready (fixtures exist or were just generated)
#   1  generator failed
#   2  python3 missing

set -uo pipefail

_ELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_ELF_PUBKEY="$_ELF_DIR/mock_public_key.pem"
_ELF_GEN="$_ELF_DIR/generate_test_licenses.py"

# Fast path: ALL fixtures already present. The license JSONs and pubkey are
# paired (signed by the same keypair) so we re-run the generator if any are
# missing. Just checking the pubkey was insufficient: if a user deletes a
# license JSON (or after `git clean` since they're gitignored), the pubkey
# may still exist but the licenses won't, leaving downstream tests broken.
_ELF_ALL_PRESENT=true
for _lic in valid_license.json grace_period_license.json expired_license.json \
            invalid_signature_license.json team_license.json enterprise_license.json; do
    [[ -s "$_ELF_DIR/$_lic" ]] || { _ELF_ALL_PRESENT=false; break; }
done
if [[ -s "$_ELF_PUBKEY" && "$_ELF_ALL_PRESENT" == "true" ]]; then
    # Freshness guard: the generator computes expiry relative to now, but a
    # presence-only cache let stale fixtures survive across days — the "valid"
    # license would silently expire, breaking every date-sensitive test. Treat
    # an already-expired "valid" fixture as absent and regenerate.
    _ELF_VEXP="$(grep -oE '"expires_at"[[:space:]]*:[[:space:]]*"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z"' "$_ELF_DIR/valid_license.json" 2>/dev/null \
                 | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z' | head -1)"
    if [[ -n "$_ELF_VEXP" ]]; then
        _ELF_VEXP_TS="$(date -u -d "$_ELF_VEXP" +%s 2>/dev/null \
                        || date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$_ELF_VEXP" +%s 2>/dev/null || echo 0)"
        if [[ "${_ELF_VEXP_TS:-0}" -gt "$(date -u +%s)" ]]; then
            return 0 2>/dev/null || exit 0
        fi
    fi
    # else: stale (expired or unparseable) → fall through to regenerate
fi

# Generate. Requires python3.
if ! command -v python3 >/dev/null 2>&1; then
    echo "ensure_license_fixtures: python3 not on PATH; cannot generate fixtures" >&2
    return 2 2>/dev/null || exit 2
fi

if [[ ! -f "$_ELF_GEN" ]]; then
    echo "ensure_license_fixtures: $_ELF_GEN not found" >&2
    return 1 2>/dev/null || exit 1
fi

# Run the generator from the fixtures dir so relative paths resolve.
if ! (cd "$_ELF_DIR" && python3 "$_ELF_GEN" >/dev/null 2>&1); then
    echo "ensure_license_fixtures: $_ELF_GEN failed (check python deps: 'cryptography' or openssl)" >&2
    return 1 2>/dev/null || exit 1
fi

if [[ ! -s "$_ELF_PUBKEY" ]]; then
    echo "ensure_license_fixtures: generator ran but mock_public_key.pem missing or empty" >&2
    return 1 2>/dev/null || exit 1
fi

return 0 2>/dev/null || exit 0
