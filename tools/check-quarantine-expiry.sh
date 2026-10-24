#!/usr/bin/env bash
# =============================================================================
# tools/check-quarantine-expiry.sh — cycle-133 Sprint 1 Task 1.6 (FR-5, SDD C-5)
#
# CI gate for tests/QUARANTINE.tsv, the list of bats tests skipped on purpose.
# Format: a header line `test_id<TAB>owner<TAB>expiry<TAB>bead<TAB>reason`,
# then one row per quarantined test (blank lines and `#` lines ignored):
#   test_id  `<repo-relative bats path>::<test description>` (exact)
#   owner    who repairs it (non-empty)
#   expiry   ISO date (YYYY-MM-DD) = the row's quarantine date + 30 days
#   bead     the open bead tracking the repair (bd-…)
#   reason   why it is quarantined (non-empty)
#
# Every row must satisfy all of:
#   - the bats file exists and declares `@test "<description>"`, and the file
#     calls loa_quarantine_check (tests/unit/helpers/quarantine.bash), else
#     the row would not take effect;
#   - the id does not name a mandatory gate (LOA_QUARANTINE_MANDATORY_RE in
#     the helper: egress, mount-home-scope, sandbox-mount, mount-provenance,
#     batch-supervisor, verdict-derive-failure-clause);
#   - the id is not listed twice;
#   - expiry is a real ISO date 30 or 31 days after the row's quarantine date
#     (the COMMITTER date, UTC, of the commit that last wrote the line, per
#     git blame — the commit that put the row on the branch, so a rebase,
#     cherry-pick or squash re-dates it; the extra day absorbs a commit made
#     the day after the row was written; an uncommitted line is dated
#     --today; in a shallow clone the boundary commit's date says nothing
#     about the row, so a line blamed on it only needs expiry <= today + 31),
#     never more than 60 days after today, and not before today (expired);
#   - the bead exists and is open (status open or in_progress), checked with
#     `br show <bead> --json` from the repository root. Only br's structured
#     ISSUE_NOT_FOUND answer (exit 3, `{"error":{"code":"ISSUE_NOT_FOUND"}}`
#     on stderr) counts as a missing bead; no `.beads/` directory, no br, or
#     any other br failure leaves the bead unverified (exit 3).
#
# Usage:
#   tools/check-quarantine-expiry.sh [--repo DIR] [--file PATH] [--today YYYY-MM-DD]
#                                    [--tap FILE] [--quiet]
#     --repo DIR    repository root the test ids resolve against (default: git top level)
#     --file PATH   quarantine file (default: DIR/tests/QUARANTINE.tsv)
#     --today D     the date expiry is judged against (default: today, UTC)
#     --tap FILE    TAP output of the full unit suite; prints its totals
#     --quiet       problems only, no totals line
#   Environment: LOA_QUARANTINE_BR — the beads CLI (default `br`).
#
# Output: one stderr line per problem, then on stdout
#   quarantine: rows=N executed=E skipped=S quarantined=Q
# where executed / skipped / quarantined come from --tap (skipped excludes the
# quarantine skips, which the helper prefixes `quarantined:`); without --tap
# executed and skipped print `-` and quarantined is the row count.
#
# Exit codes (sdd.md § 5.4):
#   0  every row valid
#   1  at least one invalid or expired row (named on stderr)
#   2  usage error, missing or unreadable file, bad header, or a --tap file
#      with no TAP test lines
#   3  rows are otherwise valid but a bead's status could not be verified
#      (no beads CLI or no beads workspace — the CI runner); named reason
#
# Tested by tests/unit/quarantine-expiry.bats.
# =============================================================================
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/../tests/unit/helpers/quarantine.bash"

REPO=""; FILE=""; TODAY=""; TAP=""; QUIET=0
die2() { printf 'check-quarantine-expiry: %s\n' "$1" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)  [[ $# -ge 2 ]] || die2 "--repo needs a directory"; REPO="$2"; shift 2 ;;
        --file)  [[ $# -ge 2 ]] || die2 "--file needs a path"; FILE="$2"; shift 2 ;;
        --today) [[ $# -ge 2 ]] || die2 "--today needs YYYY-MM-DD"; TODAY="$2"; shift 2 ;;
        --tap)   [[ $# -ge 2 ]] || die2 "--tap needs a file"; TAP="$2"; shift 2 ;;
        --quiet|-q) QUIET=1; shift ;;
        -h|--help) sed -n '/^# Usage:/,/^# Tested/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die2 "unknown argument $1 (see --help)" ;;
    esac
done

[[ -f "$HELPER" ]] || die2 "helper $HELPER not found"
# shellcheck source=../tests/unit/helpers/quarantine.bash
source "$HELPER"
[[ -n "${LOA_QUARANTINE_MANDATORY_RE:-}" ]] || die2 "LOA_QUARANTINE_MANDATORY_RE missing from $HELPER"
command -v python3 >/dev/null 2>&1 || die2 "python3 required"
command -v jq >/dev/null 2>&1 || die2 "jq required"

if [[ -z "$REPO" ]]; then
    REPO="$(git rev-parse --show-toplevel 2>/dev/null)" || die2 "not inside a git work tree (use --repo DIR)"
fi
[[ -d "$REPO" ]] || die2 "repository root $REPO is not a directory"
REPO="$(cd "$REPO" && pwd -P)"
[[ -n "$FILE" ]] || FILE="$REPO/tests/QUARANTINE.tsv"
[[ -f "$FILE" && -r "$FILE" ]] || die2 "$FILE not found — create it with the header line (see --help)"
[[ -z "$TAP" || -f "$TAP" ]] || die2 "TAP file $TAP not found"
BR="${LOA_QUARANTINE_BR:-br}"

# Date helpers (stdlib python; strict YYYY-MM-DD, real calendar dates).
_iso_ok() {
    [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
    python3 -I -c 'import sys, datetime; datetime.date.fromisoformat(sys.argv[1])' "$1" 2>/dev/null
}
_add_days() {
    python3 -I -c 'import sys, datetime as d; print(d.date.fromisoformat(sys.argv[1]) + d.timedelta(days=int(sys.argv[2])))' "$1" "$2"
}
_epoch_day() {
    python3 -I -c 'import sys, datetime as d; print(d.datetime.fromtimestamp(int(sys.argv[1]), d.timezone.utc).date())' "$1"
}

[[ -n "$TODAY" ]] || TODAY="$(date -u +%Y-%m-%d)"
_iso_ok "$TODAY" || die2 "--today must be an ISO date YYYY-MM-DD (got $TODAY)"
MAX_EXPIRY="$(_add_days "$TODAY" 60)"
SHALLOW_MAX="$(_add_days "$TODAY" 31)"

# Quarantine date of line N: committer date (UTC) of the commit that last wrote it.
# Prints `<YYYY-MM-DD> <exact|boundary>`.
QDIR="$(cd "$(dirname "$FILE")" && pwd -P)"; QBASE="$(basename "$FILE")"
SHALLOW="false"
IN_GIT=0
if git -C "$QDIR" ls-files --error-unmatch -- "$QBASE" >/dev/null 2>&1; then
    IN_GIT=1
    SHALLOW="$(git -C "$QDIR" rev-parse --is-shallow-repository)"
fi
_line_date() {
    local n="$1" porcelain sha ctime
    if [[ "$IN_GIT" -eq 0 ]]; then printf '%s exact\n' "$TODAY"; return 0; fi
    porcelain="$(git -C "$QDIR" blame --porcelain -L "$n,$n" -- "$QBASE")" \
        || { printf 'check-quarantine-expiry: git blame failed on %s line %s\n' "$FILE" "$n" >&2; return 1; }
    sha="${porcelain%% *}"
    if [[ "$sha" =~ ^0+$ ]]; then printf '%s exact\n' "$TODAY"; return 0; fi
    ctime="$(printf '%s\n' "$porcelain" | sed -n 's/^committer-time \([0-9][0-9]*\)$/\1/p' | head -1)"
    [[ -n "$ctime" ]] || { printf 'check-quarantine-expiry: no committer-time in git blame of %s line %s\n' "$FILE" "$n" >&2; return 1; }
    if [[ "$SHALLOW" == "true" ]] && printf '%s\n' "$porcelain" | grep -qx 'boundary'; then
        printf '%s boundary\n' "$(_epoch_day "$ctime")"
    else
        printf '%s exact\n' "$(_epoch_day "$ctime")"
    fi
}

HEADER=$'test_id\towner\texpiry\tbead\treason'
first="$(head -1 "$FILE" | tr -d '\r')"
[[ "$first" == "$HEADER" ]] || die2 "$FILE: first line must be the header test_id<TAB>owner<TAB>expiry<TAB>bead<TAB>reason"

BR_ERR="$(mktemp)"
trap 'rm -f "$BR_ERR"' EXIT
problems=0
unverified=0
rows=0
seen=$'\n'
problem() { printf 'check-quarantine-expiry: %s:%s: %s\n' "$FILE" "$1" "$2" >&2; problems=$((problems + 1)); }

n=1
while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    line="${line%$'\r'}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    rows=$((rows + 1))
    tabs="${line//[^$'\t']/}"
    if [[ "${#tabs}" -ne 4 ]]; then
        problem "$n" "expected 5 tab-separated columns, got $(( ${#tabs} + 1 ))"
        continue
    fi
    # Split on a non-whitespace separator: IFS=$'\t' would merge consecutive
    # tabs and shift every column after an empty field.
    IFS=$'\x1f' read -r id owner expiry bead reason <<< "${line//$'\t'/$'\x1f'}"

    # test id: <bats path>::<description>, the test exists, the file calls the helper
    if [[ "$id" != *"::"* ]]; then
        problem "$n" "test id \"$id\" must be <repo-relative bats path>::<test description>"
    else
        tfile="${id%%::*}"; tdesc="${id#*::}"
        if [[ "$tfile" == /* || "$tfile" == *..* || "$tfile" != *.bats || ! -f "$REPO/$tfile" ]]; then
            problem "$n" "\"$tfile\" is not a bats file under $REPO"
        else
            if ! grep -Fqx -- "@test \"$tdesc\" {" "$REPO/$tfile" && ! grep -Fqx -- "@test '$tdesc' {" "$REPO/$tfile"; then
                problem "$n" "no such test \"$tdesc\" in $tfile"
            fi
            if ! grep -Eq '^[[:space:]]*loa_quarantine_check([[:space:]]|$)' "$REPO/$tfile"; then
                problem "$n" "$tfile does not call loa_quarantine_check (load helpers/quarantine in setup), so the row would not take effect"
            fi
        fi
    fi
    if printf '%s\n' "$id" | grep -Eiq -- "$LOA_QUARANTINE_MANDATORY_RE"; then
        problem "$n" "\"$id\" is a mandatory gate and may never be quarantined (sdd.md § 7.3)"
    fi
    case "$seen" in
        *$'\n'"$id"$'\n'*) problem "$n" "duplicate test id \"$id\"" ;;
        *) seen="$seen$id"$'\n' ;;
    esac

    [[ -n "$owner" ]] || problem "$n" "owner is empty"
    [[ -n "$reason" ]] || problem "$n" "reason is empty"

    # expiry
    if ! _iso_ok "$expiry"; then
        problem "$n" "expiry \"$expiry\" is not an ISO date YYYY-MM-DD"
    else
        if [[ "$expiry" < "$TODAY" ]]; then
            problem "$n" "quarantine of \"$id\" expired on $expiry (today $TODAY): repair the test or renew the row with a new commit"
        fi
        if [[ "$expiry" > "$MAX_EXPIRY" ]]; then
            problem "$n" "expiry $expiry is more than 60 days after today ($MAX_EXPIRY)"
        fi
        if ld="$(_line_date "$n")"; then
            qday="${ld% *}"; kind="${ld#* }"
            if [[ "$kind" == "exact" ]]; then
                want="$(_add_days "$qday" 30)"; want1="$(_add_days "$qday" 31)"
                if [[ "$expiry" < "$want" || "$expiry" > "$want1" ]]; then
                    problem "$n" "expiry $expiry must be the quarantine date $qday + 30 days = $want (or one day later, $want1)"
                fi
            elif [[ "$expiry" > "$SHALLOW_MAX" ]]; then
                problem "$n" "expiry $expiry is later than today + 31 days ($SHALLOW_MAX); in a shallow clone the row's commit date is unknown"
            fi
        else
            problems=$((problems + 1))
        fi
    fi

    # bead: exists and open
    if [[ ! "$bead" =~ ^bd-[a-z0-9]+$ ]]; then
        problem "$n" "bead \"$bead\" is not a bead id (bd-…)"
    elif [[ ! -d "$REPO/.beads" ]]; then
        printf 'check-quarantine-expiry: %s:%s: bead %s status unverified — no beads workspace (%s/.beads absent)\n' "$FILE" "$n" "$bead" "$REPO" >&2
        unverified=$((unverified + 1))
    elif ! command -v "$BR" >/dev/null 2>&1; then
        printf 'check-quarantine-expiry: %s:%s: bead %s status unverified — beads CLI "%s" not available\n' "$FILE" "$n" "$bead" "$BR" >&2
        unverified=$((unverified + 1))
    else
        brc=0
        # stdout and stderr apart (a stderr warning must not break the parse);
        # </dev/null so br cannot read the row loop's input
        bout="$(cd "$REPO" && "$BR" show "$bead" --json 2>"$BR_ERR" </dev/null)" || brc=$?
        if [[ "$brc" -eq 0 ]]; then
            bstatus="$(printf '%s\n' "$bout" | jq -r 'if type == "array" then .[0].status else .status end')" \
                || { problem "$n" "bead $bead: unparseable br show output"; continue; }
            case "$bstatus" in
                open|in_progress) ;;
                *) problem "$n" "bead $bead is $bstatus, not open: close the quarantine or reopen the bead" ;;
            esac
        elif [[ "$brc" -eq 3 ]] && jq -e '.error.code == "ISSUE_NOT_FOUND"' "$BR_ERR" >/dev/null 2>&1; then
            problem "$n" "bead $bead not found"
        else
            printf 'check-quarantine-expiry: %s:%s: bead %s status unverified — br show failed (exit %s: %s)\n' "$FILE" "$n" "$bead" "$brc" "$(tr '\n' ' ' < "$BR_ERR" | cut -c1-160)" >&2
            unverified=$((unverified + 1))
        fi
    fi
done < <(tail -n +2 "$FILE")

executed="-"; skipped="-"; quarantined="$rows"
if [[ -n "$TAP" ]]; then
    total="$(grep -Ec '^(ok|not ok) [0-9]+' "$TAP" || true)"
    [[ "$total" -gt 0 ]] || die2 "$TAP: no TAP test lines found"
    skip_all="$(grep -Eic '^ok [0-9]+ .* # skip' "$TAP" || true)"
    quarantined="$(grep -Eic '^ok [0-9]+ .* # skip quarantined:' "$TAP" || true)"
    executed=$((total - skip_all))
    skipped=$((skip_all - quarantined))
fi
[[ "$QUIET" -eq 1 ]] || printf 'quarantine: rows=%s executed=%s skipped=%s quarantined=%s\n' "$rows" "$executed" "$skipped" "$quarantined"

if [[ "$problems" -gt 0 ]]; then
    printf 'check-quarantine-expiry: %s problem(s) in %s\n' "$problems" "$FILE" >&2
    exit 1
fi
if [[ "$unverified" -gt 0 ]]; then
    printf 'check-quarantine-expiry: degraded — %s bead status(es) unverified (no beads workspace); rows otherwise valid\n' "$unverified" >&2
    exit 3
fi
exit 0
