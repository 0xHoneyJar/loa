#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    COMPAT="$REPO_ROOT/.claude/scripts/compat-lib.sh"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    # Model BSD -jf parsing: a literal Z does not choose a timezone; -u does.
    # Any unsupported invocation fails, so a GNU call cannot pass this test.
    cat > "$BATS_TEST_TMPDIR/bin/date" <<'PY'
#!/usr/bin/env python3
import calendar
import datetime
import os
import sys
import time

args = sys.argv[1:]
if args == ["+%s"]:
    print(1781438400)
    sys.exit(0)
utc = "-u" in args
if utc:
    args.remove("-u")
if args[:2] == ["-j", "-f"]:
    args[:2] = ["-jf"]
if len(args) != 4 or args[0] != "-jf" or args[3] != "+%s":
    sys.exit(1)
try:
    value = datetime.datetime.strptime(args[2], args[1])
except ValueError:
    sys.exit(1)
time.tzset()
print(calendar.timegm(value.timetuple()) if utc else int(time.mktime(value.timetuple())))
with open(os.environ["DATE_LOG"], "a") as log:
    log.write("bsd-success\n")
PY
    chmod +x "$BATS_TEST_TMPDIR/bin/date"
    export DATE_LOG="$BATS_TEST_TMPDIR/date.log"
}

@test "#1037: BSD Z timestamps have the UTC epoch in positive and negative timezones" {
    for zone in UTC America/New_York Asia/Tokyo; do
        run env TZ="$zone" PATH="$BATS_TEST_TMPDIR/bin:$PATH" bash -c '
            source "$1"
            _COMPAT_OS=darwin
            _date_to_epoch "2026-06-13T12:00:00Z"
        ' _ "$COMPAT"
        echo "$zone: $output"
        [ "$status" -eq 0 ]
        [ "$output" = 1781352000 ]
    done
    [ "$(wc -l < "$DATE_LOG" | tr -d ' ')" -eq 3 ]
}

@test "#1037: BSD timestamps without timezone retain local-time interpretation" {
    run env TZ=America/New_York PATH="$BATS_TEST_TMPDIR/bin:$PATH" bash -c '
        source "$1"
        _COMPAT_OS=darwin
        _date_to_epoch "2026-06-13T12:00:00"
    ' _ "$COMPAT"
    [ "$status" -eq 0 ]
    [ "$output" = 1781366400 ]
    [ -s "$DATE_LOG" ]
}

@test "#1037: GNU and Perl UTC parsing agree and invalid timestamps fail" {
    for platform in linux unknown; do
        run env TZ=Asia/Tokyo bash -c '
            source "$1"
            _COMPAT_OS="$2"
            _date_to_epoch "2026-06-13T12:00:00Z"
        ' _ "$COMPAT" "$platform"
        [ "$status" -eq 0 ]
        [ "$output" = 1781352000 ]
    done
    for timestamp in "" not-a-date; do
        run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" bash -c '
            source "$1"
            _COMPAT_OS=darwin
            _date_to_epoch "$2"
        ' _ "$COMPAT" "$timestamp"
        [ "$status" -ne 0 ]
        [ -z "$output" ]
    done
}

@test "#1037: constructs parser and standalone staleness fallback use UTC" {
    printf '{"installed_packs":{"demo":{"installed_at":"2026-06-13T12:00:00Z"}}}\n' \
      > "$BATS_TEST_TMPDIR/meta.json"
    for zone in America/New_York Asia/Tokyo; do
        run env TZ="$zone" PATH="$BATS_TEST_TMPDIR/bin:$PATH" bash -c '
            source "$1"
            parse_iso_date "2026-06-13T12:00:00Z"
        ' _ "$REPO_ROOT/.claude/scripts/constructs-lib.sh"
        [ "$status" -eq 0 ]
        [ "$output" = 1781352000 ]
        run env TZ="$zone" PATH="$BATS_TEST_TMPDIR/bin:$PATH" bash -c '
            source "$1"
            unset -f _date_to_epoch
            registry_fixture="$2"
            get_registry_meta_path() { printf "%s" "$registry_fixture"; }
            check_pack_staleness demo 1
        ' _ "$REPO_ROOT/.claude/scripts/constructs-lib.sh" "$BATS_TEST_TMPDIR/meta.json"
        [ "$status" -eq 0 ]
        [[ "$output" == *"installed 1 days ago"* ]]
    done
}
