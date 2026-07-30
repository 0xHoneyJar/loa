#!/usr/bin/env bats
# =============================================================================
# compat-lib-date-to-epoch.bats — cycle-123 T2.3 (#1037)
# =============================================================================
# BSD `date -jf` consumes a trailing 'Z' in the FORMAT as a literal and then
# interprets the wall-clock in $TZ. Without -u, `_date_to_epoch` returns an
# epoch shifted by the local UTC offset — up to 14h wrong on Darwin — while
# the GNU tier-1 and perl tier-3 paths are correct. Five consumers depend on
# this helper, so the shift propagates into staleness and expiry decisions.
#
# This host is Linux/GNU, so darwin's tier 2 is reached by overriding
# _COMPAT_OS AFTER sourcing (it is cached from `uname -s` at load) and by
# putting a BSD-semantics `date` shim on a masked PATH.
#
# Ground rule 6: the shim carries a faithfulness positive control. If the shim
# does not itself reproduce the TZ shift, the suite proves nothing.
# =============================================================================

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    COMPAT_LIB="$PROJECT_ROOT/.claude/scripts/compat-lib.sh"
    SHIM_DIR="$BATS_TEST_TMPDIR/shim"
    mkdir -p "$SHIM_DIR"

    # BSD-semantics `date` shim.
    #   -j        : do not set the clock
    #   -f <fmt>  : parse per <fmt>; a trailing 'Z' in the format is a LITERAL,
    #               not a UTC marker, so the value is read as local wall-clock
    #   -u        : interpret/emit UTC (the fix)
    # GNU's `-d` is rejected, forcing the darwin tier.
    cat > "$SHIM_DIR/date" <<'SHIM'
#!/usr/bin/env bash
set -uo pipefail
utc=0; parse_fmt=""; value=""; outfmt=""
args=("$@")
i=0
while [[ $i -lt ${#args[@]} ]]; do
    a="${args[$i]}"
    case "$a" in
        -d|--date=*|--date)
            # GNU form — a BSD date has no -d parsing. Fail like BSD does.
            echo "date: illegal option -- d" >&2; exit 1 ;;
        -j) : ;;
        -u) utc=1 ;;
        -ju|-uj) utc=1 ;;
        -jf|-fj) i=$((i+1)); parse_fmt="${args[$i]}" ;;
        -juf|-jfu|-ujf) utc=1; i=$((i+1)); parse_fmt="${args[$i]}" ;;
        -f)  i=$((i+1)); parse_fmt="${args[$i]}" ;;
        +*)  outfmt="$a" ;;
        *)   value="$a" ;;
    esac
    i=$((i+1))
done

[[ -n "$parse_fmt" && -n "$value" ]] || { echo "date: bad usage" >&2; exit 1; }

# Strip the format's literal trailing Z and the value's trailing Z, mirroring
# BSD: the Z is consumed as a literal character, conveying no zone meaning.
fmt_noz="${parse_fmt%Z}"
val_noz="${value%Z}"
[[ "$fmt_noz" == "%Y-%m-%dT%H:%M:%S" ]] || { echo "date: unsupported format in shim" >&2; exit 1; }

# Re-parse the wall clock in the zone BSD would use: UTC with -u, else $TZ.
if [[ "$utc" -eq 1 ]]; then
    real=$(TZ=UTC /usr/bin/date -u -d "$val_noz" "$outfmt" 2>/dev/null) || \
        real=$(TZ=UTC date -u -d "$val_noz" "$outfmt" 2>/dev/null) || exit 1
else
    real=$(/usr/bin/date -d "$val_noz" "$outfmt" 2>/dev/null) || \
        real=$(date -d "$val_noz" "$outfmt" 2>/dev/null) || exit 1
fi
printf '%s\n' "$real"
SHIM
    chmod +x "$SHIM_DIR/date"

    # 2026-01-01T00:00:00Z
    EXPECTED_UTC=1767225600
    # Same wall clock read as America/New_York (UTC-5) — the defect's result.
    EXPECTED_SHIFTED=1767243600
}

teardown() {
    cd /
    rm -rf "$BATS_TEST_TMPDIR/shim"
}

# Run _date_to_epoch under the darwin tier with a chosen TZ.
_epoch_darwin() {
    local tz="$1" ts="$2"
    env PATH="$SHIM_DIR:/usr/bin:/bin" TZ="$tz" bash -c "
        source '$COMPAT_LIB' >/dev/null 2>&1
        _COMPAT_OS=darwin
        _date_to_epoch '$ts'
    " 2>/dev/null
}

@test "T2.3 AC-1: darwin tier returns true UTC epoch under TZ=America/New_York" {
    local got
    got=$(_epoch_darwin "America/New_York" "2026-01-01T00:00:00Z")
    [[ "$got" == "$EXPECTED_UTC" ]] || {
        echo "expected $EXPECTED_UTC; got '$got' (shift = $(( ${got:-0} - EXPECTED_UTC ))s)"
        return 1
    }
}

@test "T2.3 AC-2: same input under TZ=Asia/Tokyo yields the identical epoch" {
    local ny tokyo
    ny=$(_epoch_darwin "America/New_York" "2026-01-01T00:00:00Z")
    tokyo=$(_epoch_darwin "Asia/Tokyo" "2026-01-01T00:00:00Z")
    [[ "$ny" == "$tokyo" ]] || {
        echo "TZ-dependent result: NY=$ny Tokyo=$tokyo"
        return 1
    }
    [[ "$tokyo" == "$EXPECTED_UTC" ]]
}

@test "T2.3 AC-3: shim faithfulness — WITHOUT -u the shim reproduces the shift" {
    local got
    got=$(env PATH="$SHIM_DIR:/usr/bin:/bin" TZ="America/New_York" \
        date -j -f "%Y-%m-%dT%H:%M:%SZ" "2026-01-01T00:00:00Z" +%s 2>/dev/null)
    [[ "$got" == "$EXPECTED_SHIFTED" ]] || {
        echo "shim does not model the BSD TZ shift (got '$got', wanted $EXPECTED_SHIFTED) — this suite would prove nothing"
        return 1
    }

    # ...and WITH -u it is correct, proving -u is the operative fix.
    got=$(env PATH="$SHIM_DIR:/usr/bin:/bin" TZ="America/New_York" \
        date -ju -f "%Y-%m-%dT%H:%M:%SZ" "2026-01-01T00:00:00Z" +%s 2>/dev/null)
    [[ "$got" == "$EXPECTED_UTC" ]]
}

@test "T2.3 AC-4: parse_iso_date agrees with the darwin tier under a non-UTC TZ" {
    command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
    # parse_iso_date lives in constructs-lib.sh, not compat-lib.sh (the plan's
    # AC-4 named the wrong file); it is the second consumer of the same
    # BSD-tier pattern, so it gets the same guarantee.
    local constructs_lib="$PROJECT_ROOT/.claude/scripts/constructs-lib.sh"
    local via_python
    via_python=$(env TZ="America/New_York" bash -c "
        source '$constructs_lib' >/dev/null 2>&1
        parse_iso_date '2026-01-01T00:00:00Z'
    " 2>/dev/null)
    [[ "$via_python" == "$EXPECTED_UTC" ]] || {
        echo "parse_iso_date disagrees: got '$via_python', wanted $EXPECTED_UTC"
        return 1
    }
}

@test "T2.3 AC-5: every Z-format BSD date parse under .claude/ carries -u" {
    cd "$PROJECT_ROOT"
    # Z-format parses (the format string ends in Z) that lack any -u form.
    run bash -c "grep -rn 'date -j' .claude/scripts/ .claude/hooks/ 2>/dev/null \
        | grep 'Z\"\\|Z'\\''' \
        | grep -v -- '-u' \
        | grep -v -- '-ju' \
        | grep -v -- '-uj' \
        | grep -v -- '-juf' || true"
    [[ -z "$output" ]] || {
        echo "Z-format BSD date parses still missing -u:"
        echo "$output"
        return 1
    }
}

@test "T2.3 AC-6: the no-Z branch keeps local-time semantics (byte-unchanged)" {
    # compat-lib's second darwin attempt runs only when the input carried no Z,
    # where local-time interpretation is what GNU `date -d` also does.
    run grep -n "date -jf '%Y-%m-%dT%H:%M:%S' \"\$timestamp\"" "$COMPAT_LIB"
    [[ "$status" -eq 0 ]] || {
        echo "the no-Z branch changed shape; AC-6 pins it as-is"
        return 1
    }
    [[ ! "$output" == *"-u"* ]] || {
        echo "the no-Z branch must NOT gain -u: $output"
        return 1
    }
}
