#!/usr/bin/env bats
# =============================================================================
# license-fixture-freshness.bats — ensure_license_fixtures.sh regenerates any
# time-relative fixture whose window has closed, not only valid_license.json.
# The grace-period fixture is usable for 12 hours after generation
# (offline_valid_until = now + 12h) while valid_license.json lasts 30 days, so
# a freshness guard keyed on the valid fixture alone left a stale grace fixture
# in place for weeks (test_license_validator "grace period … pro tier" failed
# on a checkout whose fixtures were generated 2026-09-21).
# =============================================================================

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    command -v python3 >/dev/null || skip "python3 required"
    WORK="$BATS_TEST_TMPDIR/fixtures"
    mkdir -p "$WORK"
    cp "$PROJECT_ROOT/tests/fixtures/ensure_license_fixtures.sh" \
       "$PROJECT_ROOT/tests/fixtures/generate_test_licenses.py" \
       "$PROJECT_ROOT/tests/fixtures/mock_server.py" "$WORK/"
    # shellcheck disable=SC1091
    source "$WORK/ensure_license_fixtures.sh" || skip "fixture generator unavailable"
    [[ -s "$WORK/grace_period_license.json" ]] || skip "fixture generator produced nothing"
}

_offline_until() {
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["offline_valid_until"])' "$1"
}

_is_future() {
    python3 -c 'import sys,datetime as d; t=d.datetime.strptime(sys.argv[1],"%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=d.timezone.utc); sys.exit(0 if t > d.datetime.now(d.timezone.utc) else 1)' "$1"
}

@test "LFF-1: a grace fixture past its offline window is regenerated even when valid_license.json is fresh" {
    # Age only the grace fixture: its window closed yesterday.
    python3 - "$WORK/grace_period_license.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["expires_at"] = "2026-01-01T00:00:00Z"
d["offline_valid_until"] = "2026-01-02T00:00:00Z"
json.dump(d, open(p, "w"))
PY
    source "$WORK/ensure_license_fixtures.sh"
    _is_future "$(_offline_until "$WORK/grace_period_license.json")"
}

@test "LFF-2: fresh fixtures are left alone (no regeneration on every call)" {
    local before; before="$(cksum < "$WORK/grace_period_license.json")"
    source "$WORK/ensure_license_fixtures.sh"
    [ "$(cksum < "$WORK/grace_period_license.json")" = "$before" ]
}
