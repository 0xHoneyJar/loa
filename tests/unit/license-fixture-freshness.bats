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

@test "LFF-3: a grace fixture that expires within the margin (now + 60 s) is regenerated, not trusted to outlive the suite" {
    # sprint-250 review run 1, n39: a zero-margin check passed a window closing
    # seconds later, and the fixture then expired mid-suite.
    python3 - "$WORK/grace_period_license.json" <<'PY'
import json, sys, datetime as dt
p = sys.argv[1]
d = json.load(open(p))
d["offline_valid_until"] = (dt.datetime.now(dt.timezone.utc) + dt.timedelta(seconds=60)).strftime("%Y-%m-%dT%H:%M:%SZ")
json.dump(d, open(p, "w"))
PY
    local soon; soon="$(_offline_until "$WORK/grace_period_license.json")"
    source "$WORK/ensure_license_fixtures.sh"
    [ "$(_offline_until "$WORK/grace_period_license.json")" != "$soon" ]
    python3 -c 'import sys,datetime as d; t=d.datetime.strptime(sys.argv[1],"%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=d.timezone.utc); sys.exit(0 if t > d.datetime.now(d.timezone.utc) + d.timedelta(hours=1) else 1)' "$(_offline_until "$WORK/grace_period_license.json")"
}

@test "LFF-4: on a host east of UTC the JWT exp agrees with expires_at (the generator never reads a naive UTC time as local)" {
    # sprint-250 review round 1: datetime.utcnow() is naive and .timestamp()
    # reads it as local time, so on AEDT (UTC+11) every JWT exp landed 11 hours
    # early and the pro tier's 24h grace closed 1 hour after generation.
    ( cd "$WORK" && TZ=Australia/Sydney python3 generate_test_licenses.py >/dev/null )
    python3 - "$WORK/grace_period_license.json" "$WORK/valid_license.json" <<'PY'
import base64, json, sys, datetime as dt
for p in sys.argv[1:]:
    d = json.load(open(p))
    seg = d["token"].split(".")[1]
    exp = json.loads(base64.urlsafe_b64decode(seg + "=" * (-len(seg) % 4)))["exp"]
    want = int(dt.datetime.strptime(d["expires_at"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc).timestamp())
    assert abs(exp - want) <= 1, f"{p}: jwt exp {exp} vs expires_at {want} (delta {exp - want} s)"
    issued = dt.datetime.strptime(d["issued_at"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc)
    assert abs((issued - dt.datetime.now(dt.timezone.utc)).total_seconds()) < 300, f"{p}: issued_at {d['issued_at']} is not UTC now"
PY
}

@test "LFF-5: fixtures older than the generator are regenerated (a generator fix reaches an existing checkout)" {
    local before; before="$(cksum < "$WORK/grace_period_license.json")"
    touch -d '2026-01-01T00:00:00Z' "$WORK"/*.json
    touch "$WORK/generate_test_licenses.py"
    sleep 1
    source "$WORK/ensure_license_fixtures.sh"
    [ "$(cksum < "$WORK/grace_period_license.json")" != "$before" ]
}
