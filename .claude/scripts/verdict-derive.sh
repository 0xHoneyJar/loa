#!/usr/bin/env bash
# =============================================================================
# verdict-derive.sh — Derive & validate the LOA-VERDICT machine trailer (C7)
# =============================================================================
# Part of cycle-119 "mechanical floor" (structured-first gate consumption).
#
# Validates a reviewing-code/auditing-security feedback file's LOA-VERDICT
# trailer (C6: `<!-- LOA-VERDICT {json} -->` as the LAST LINE of the file):
#   1. trailer present, parses as JSON, is the last line
#   2. prose<->trailer agreement (review: first line "All good" iff APPROVED;
#      audit: exact ritual string "APPROVED - LET'S FUCKING GO" iff APPROVED)
#   3. one-way severity rule: counts.critical + counts.high > 0 => verdict
#      MUST be CHANGES_REQUIRED (zero does NOT force APPROVED)
#   4. an APPROVED review file carries no '## Changes Required' / 'Findings'
#      / 'Issues' heading
#   5. FR-9 coverage-first (additive): `excluded` counts the HIGH findings
#      demoted to '## Observations' as speculative + confidence: low; critical
#      is never excludable; an audit's `excluded_confirmed` must match the
#      review's `excluded` (--review-file)
#
# Usage:
#   verdict-derive.sh --file <feedback.md> --gate review|audit [--json] [--require-trailer]
#
# Exit codes:
#   0 = trailer present and consistent
#   1 = trailer present but a violation was found (repair text on stderr),
#       OR a usage error, OR trailer missing with --require-trailer
#   2 = no trailer found (legacy file) — success unless --require-trailer
# =============================================================================

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

JSON_OUTPUT=false
REQUIRE_TRAILER=false
FILE=""
GATE=""
REVIEW_FILE=""
ENVELOPE_FILE=""      # sprint-248 review (chunk b C-005): initialised like the others — an exported variable is not an option
ENVELOPE_EXPLICIT=false
_EMPTY_FLAGS=""        # the optional flags given an EMPTY value (sixteenth run, c2d C-002: accepted as "not given", said once)

show_help() {
    cat <<EOF
Usage: $SCRIPT_NAME --file <feedback.md> --gate review|audit [--json] [--require-trailer] [--envelope <adversarial-<gate>.json>]
       [--review-file <engineer-feedback.md>]

Derive and validate the LOA-VERDICT machine trailer (C6) on a review/audit
feedback file.

Options:
  --file PATH         Feedback file to check (required)
  --gate review|audit Which gate this file belongs to (required)
  --json              Emit a JSON result object to stdout
  --require-trailer   Treat a missing trailer as a violation (exit 1) instead
                       of the default legacy-file pass (exit 2)
  --envelope <path>   The dissent envelope for the rejected-payload contract (default: adversarial-<gate>.json
                      beside --file). Rejected sidecar rows count too: the files the envelope lists in
                      metadata.rejected_sidecars always count, and so does a non-empty unlisted
                      adversarial-rejected-<gate>*.jsonl beside the envelope (with a warning naming it: an
                      earlier run's rows that were never folded); without an envelope, or without that field,
                      every adversarial-rejected-<gate>*.jsonl beside it counts; a pre-FR-2 envelope (no
                      metadata.rejected_summary key and none of rejected_sidecars or companion_voice —
                      rejected_count is no marker, the writer before cycle-126 set it too) counts none of the
                      rows as old as itself, while a sidecar newer than it counts, with a warning
                      (one git tracks with its committed bytes is history, whatever mtime a checkout
                      gave it); one top-level bullet per rejected payload
                      under '## Rejected dissent payloads'; a missing explicit path is a usage error (exit 1).
                      A moved-aside adversarial-<gate>.json.prev or adversarial-rejected-<gate>*.jsonl.prev
                      with no envelope is a violation (dissent_aborted: the run never wrote its envelope).
  --review-file PATH  Audit gate only: cross-check the audit trailer's
                       excluded_confirmed against the review trailer's excluded
  -h, --help          Show this help message

Coverage-first rule (FR-9, additive): the trailer may carry "excluded": N —
the number of HIGH findings the reviewer demoted to "## Observations" because
they are tagged speculative with confidence: low. critical is never excludable;
a HIGH under ## Observations needs both markers; N must equal what the section
holds. An audit trailer carries "excluded_confirmed": N and must match.

Exit codes:
  0  trailer present and consistent
  1  trailer present but inconsistent (repair text on stderr), a usage
     error, or a missing trailer with --require-trailer set
  2  no trailer found (legacy file — pass unless --require-trailer)
EOF
}

# ≤ 6 digits: bash arithmetic wraps at 2^64, so an absurd count like
# 18446744073709551616 would sum to 0 and read as consistent (audit, slice C).
is_num() { [[ "$1" =~ ^[0-9]{1,6}$ ]]; }
# Detection is loose (tab/NBSP/U+2010 variants are still "a trailer"); the
# canonical form is enforced below — a malformed marker is a violation, never a
# silent fall-through to the legacy prose heuristic.
TRAILER_DETECT='<!--[^A-Za-z0-9]{0,4}LOA[^A-Za-z0-9]{0,4}VERDICT'
TRAILER_CANON='^<!-- LOA-VERDICT \{.*\} -->$'

# sprint-248 review (chunk b C-002): a usage error is a failure (exit 1, as the header says) — never
# exit 2, which every consumer reads as the legacy no-trailer pass — and with --json it is a result
# object (consistent:false, usage_error:true) instead of an empty stdout.
usage_error() {  # <message>
    echo "Error: $1" >&2
    if [[ "${JSON_OUTPUT:-false}" == "true" ]]; then
        # (twenty-ninth run, b1 DISS-C-001: emit_json's keys, in its order — one --json schema on every path)
        jq -n --arg e "$1" --arg f "${FILE:-}" --arg g "${GATE:-}" \
          '{file: $f, gate: $g, trailer_found: false, verdict: null, counts: null, excluded: 0, excluded_confirmed: 0,
            consistent: false, usage_error: true, violations: [$e], warnings: [], envelope: null, envelope_explicit: false,
            exit_code: 1}'
    fi
    exit 1
}

# a usage error anywhere in argv must still speak JSON when --json is present (third run, chunk b C-004)
for _a in "$@"; do [[ "$_a" == "--json" ]] && JSON_OUTPUT=true; done
_need_value() {  # <flag> <argc> <value> — a value flag as the LAST token is a usage error, not a failed `shift` (fourth run, chunk b
                 # DISS-001); an EMPTY value is accepted and reads as "not given" (a caller assembling argv from an optional
                 # variable — `--review-file "$review_path"` — must not start failing; eleventh run, chunk b DISS-C-002)
    [[ "$2" -ge 2 ]] || usage_error "$1 requires a value"
}
while [[ $# -gt 0 ]]; do
    case "$1" in
        --file) _need_value "$1" $# "${2:-}"; FILE="$2"; shift 2 ;;
        --gate) _need_value "$1" $# "${2:-}"; GATE="$2"; shift 2 ;;
        --json) JSON_OUTPUT=true; shift ;;
        --require-trailer) REQUIRE_TRAILER=true; shift ;;
        --review-file) _need_value "$1" $# "${2:-}"; REVIEW_FILE="$2"; [[ -n "$2" ]] || _EMPTY_FLAGS+="--review-file "; shift 2 ;;
        --envelope) _need_value "$1" $# "${2:-}"; ENVELOPE_FILE="$2"; [[ -n "$2" ]] || _EMPTY_FLAGS+="--envelope "; shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) show_help >&2; usage_error "Unknown option: $1" ;;
    esac
done

if [[ -z "$FILE" || -z "$GATE" ]]; then
    show_help >&2
    usage_error "--file and --gate are required"
fi
[[ "$GATE" == "review" || "$GATE" == "audit" ]] || usage_error "--gate must be 'review' or 'audit' (got: $GATE)"
# (thirty-first run, b1 DISS-C-001: --file and --review-file are named like --envelope — a path that exists is never "not found")
if [[ ! -f "$FILE" ]]; then
    [[ -e "$FILE" ]] && usage_error "file is not a regular file: $FILE"
    usage_error "file not found: $FILE"
fi
if [[ -n "$REVIEW_FILE" ]]; then
    [[ "$GATE" == "audit" ]] || usage_error "--review-file applies to --gate audit only"
    if [[ ! -f "$REVIEW_FILE" ]]; then
        [[ -e "$REVIEW_FILE" ]] && usage_error "review file is not a regular file: $REVIEW_FILE"
        usage_error "review file not found: $REVIEW_FILE"
    fi
fi
# sprint-248 review (chunk b C-002): an explicit envelope that is not a regular file is a usage
# error, like --review-file — never a warning that --json consumers ignore
# (twenty-sixth run, c2d DISS-C-002: a path that exists — a directory, a FIFO — is named as what it is, never "not found")
if [[ -n "$ENVELOPE_FILE" && ! -f "$ENVELOPE_FILE" ]]; then
    if [[ -e "$ENVELOPE_FILE" ]]; then usage_error "envelope file is not a regular file: $ENVELOPE_FILE"; fi
    usage_error "envelope file not found: $ENVELOPE_FILE"
fi

# cycle-126 FR-2.3 (SDD D-2.3): the dissent envelope beside the feedback file
# (adversarial-<gate>.json, or --envelope) — when its metadata.rejected_summary
# is non-empty the feedback MUST triage it under "## Rejected dissent payloads".
if [[ -z "${ENVELOPE_FILE:-}" ]]; then
    ENVELOPE_FILE="$(dirname -- "$FILE")/adversarial-${GATE}.json"
    ENVELOPE_EXPLICIT=false
else
    ENVELOPE_EXPLICIT=true
fi
_rejected_rows_of() {  # <file> [listed] — adds the file's rejected rows to $rows; an unreadable, non-regular or (when listed) missing file is a violation
    local f="$1" t r c
    if [[ ! -e "$f" && ! -L "$f" ]]; then
        # seventh run, chunk c2 C-001: a sidecar the envelope names must be there — fail closed, never a silent zero
        [[ "${2:-}" == "listed" ]] && violations+=("rejected-payload sidecar $(basename -- "$f") is listed in the envelope's metadata.rejected_sidecars but is missing beside it — re-run the dissent or repair the envelope")
        return 0
    fi
    # seventh run, chunk b C-001: a directory, FIFO or device named as a sidecar would count 0 or hang grep
    if [[ ! -f "$f" ]]; then
        violations+=("rejected-payload sidecar $(basename -- "$f") is not a regular file — remove it or re-run the dissent; its rows cannot be triaged")
        return 0
    fi
    if [[ ! -r "$f" ]]; then
        violations+=("rejected-payload sidecar $(basename -- "$f") is not readable — fix its permissions or re-run the dissent; its rows cannot be triaged")
        return 0
    fi
    # rows whose repair succeeded were accepted upstream (the writer only records rejections; defensive) —
    # judged per row on the top-level key by jq, never by a substring over the payload (eighth run, b C-004);
    # a line that is not JSON still counts as a row to triage
    # type-safe (tenth run, chunk b C-003): a scalar row counts as one row; only an object with repair_succeeded true is excluded
    # (twelfth run, b C-002: a whitespace-only or CR-only line is not a row; a CR before the JSON is stripped)
    c=$(jq -Rn '[inputs | select(test("\\S")) | sub("\r$"; "") | (fromjson? // {}) | select((type == "object" and .repair_succeeded == true) | not)] | length' -- "$f" 2>/dev/null || true)
    [[ "$c" =~ ^[0-9]+$ ]] || c=$(grep -c '[^[:space:]]' -- "$f" 2>/dev/null || true)
    (( ${c:-0} > 0 )) && rows=$(( rows + c ))
    return 0
}
_vd_committed() {  # <file> → 0 when git tracks it and its bytes are the committed ones: history, whatever mtime a checkout gave it —
    # git writes a directory's files in index order, so a sidecar can land a clock tick after its envelope (thirty-fifth run,
    # e2a DISS-C-004); a caller's GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE never name the repository, nor the rest of git's
    # repository and discovery set (thirty-eighth run, c2d DISS-C-004: a ceiling, an object directory, a namespace); no git is no proof
    command -v git >/dev/null 2>&1 || return 1
    ( unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES \
            GIT_CEILING_DIRECTORIES GIT_DISCOVERY_ACROSS_FILESYSTEM GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE \
            GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_PREFIX GIT_IMPLICIT_WORK_TREE $(git rev-parse --local-env-vars 2>/dev/null) \
            GIT_GLOB_PATHSPECS GIT_NOGLOB_PATHSPECS GIT_ICASE_PATHSPECS
      # (thirty-ninth run, b1 DISS-C-001: the name is a literal path — `review?.jsonl` is no pattern matching a committed sibling)
      export GIT_LITERAL_PATHSPECS=1
      git -C "${1%/*}" ls-files --error-unmatch -- "${1##*/}" >/dev/null 2>&1 \
        && git -C "${1%/*}" diff --quiet HEAD -- "${1##*/}" >/dev/null 2>&1 )
}
_vd_listed() {  # <name> <listed…> → 0 when name is one of them, compared exactly
    local _n="$1" _x; shift
    for _x in "$@"; do [[ "$_x" == "$_n" ]] && return 0; done
    return 1
}
rejected_summary_check() {  # appends a violation when the contract is broken; silent otherwise
    # cycle-126 FR-2.3 (SDD D-2.3), hardened over sprint-248's live review runs:
    #   * the envelope's metadata.rejected_summary and the rejected-payload sidecar rows both count
    #     (need = max); one top-level bullet per payload under `## Rejected dissent payloads`;
    #   * when the envelope names the sidecars this run produced (metadata.rejected_sidecars[]) only
    #     those are counted — a stale file from a writer that did not run this time is not this run's;
    #     without an envelope, or without that field, every adversarial-rejected-<gate>*.jsonl beside
    #     the feedback file counts (a run that died after writing rows still leaves work to triage);
    #   * an unparseable envelope or a non-array summary is a violation; an unreadable sidecar too;
    #   * the same section and bullet count clear the violation whether or not the envelope exists.
    local rows=0 f envdir kind n=0 need source listed="" has_list="false" _snap
    envdir=$(dirname -- "$ENVELOPE_FILE")
    # twentieth run, a4 C-001: the dissent moves the previous round's envelope and sidecars aside (`.prev`) when it starts and
    # drops them once it writes its own envelope — `.prev` files with NO envelope are a run that ended in between (a session
    # limit, a signal, a fail-closed exit): the dissent never completed, so no file can be held to it as if it had
    if [[ ! -e "$ENVELOPE_FILE" && ! -L "$ENVELOPE_FILE" ]]; then
        local _pv _prev_files=""
        for _pv in "$ENVELOPE_FILE.prev" "$envdir"/adversarial-rejected-"$GATE"*.jsonl.prev; do
            [[ -e "$_pv" || -L "$_pv" ]] && _prev_files+="${_prev_files:+, }$(basename -- "$_pv")"
        done
        [[ -n "$_prev_files" ]] && violations+=("dissent_aborted: $_prev_files beside this file but no dissent envelope $(basename -- "$ENVELOPE_FILE") — a dissent run moved the previous round's files aside and wrote none of its own; re-run the dissent, or record the failure with the documented fallback envelope")
    fi
    # twenty-second run, b1 C-002: a sibling envelope that exists but is not a regular file (a directory, a FIFO, a dangling
    # symlink) cannot be read — an explicit one is a usage error above; the default sibling is a violation, never skipped
    if [[ ( -e "$ENVELOPE_FILE" || -L "$ENVELOPE_FILE" ) && ! -f "$ENVELOPE_FILE" ]]; then
        violations+=("dissent envelope $(basename -- "$ENVELOPE_FILE") is not a regular file — the rejected-payload contract cannot be checked; remove it and re-run the dissent")
        return 0
    fi
    # thirtieth run, b1 DISS-C-002: an envelope this user cannot read is said as such, never "not parseable JSON"
    if [[ -f "$ENVELOPE_FILE" && ! -r "$ENVELOPE_FILE" ]]; then
        violations+=("dissent envelope $(basename -- "$ENVELOPE_FILE") is not readable — fix its permissions or re-run the dissent; the rejected-payload contract cannot be checked")
        return 0
    fi
    if [[ -f "$ENVELOPE_FILE" ]]; then
        # eighth run, chunk b C-003: the summary's REAL type (null → the empty array; `false` is a boolean), and a
        # metadata that is not an object gets its own message; an envelope with no metadata at all, or a metadata WITHOUT
        # a rejected_summary key and without any FR-2 marker (rejected_sidecars / companion_voice — thirty-fifth run, e2a DISS-C-004:
        # not rejected_count, which every envelope since #832 carries, so two committed pre-FR-2 audit sprints read INCONSISTENT), is
        # a pre-FR-2 envelope — its sidecar rows are not counted (twelfth run, b C-005: historical sprints keep their
        # verdicts; thirteenth run, b C-001 / C-002); one jq read — a snapshot, never four
        # reads of a file a running dissent may be rewriting (b C-003); a non-string entry of rejected_sidecars is
        # carried out tagged, never used as a name (b C-004)
        # (twenty-fifth run, b1 DISS-C-001 / DISS-C-002: every binding is total — a fallback record's displaced that is null or absent
        # binds null, never the empty stream that printed nothing; rejected_sidecars is read on presence, so `false` is a boolean)
        _snap=$(jq -r '
            (if .metadata == null then "legacy"
             elif (.metadata | type) != "object" then "metadata:" + (.metadata | type)
             elif (.metadata | has("rejected_summary") | not)
                  and ((.metadata | (has("rejected_sidecars") or has("companion_voice"))) | not) then "legacy"
             elif .metadata.rejected_summary == null then "array" else (.metadata.rejected_summary | type) end) as $kind
            | (if ($kind | startswith("metadata:")) then {} else (.metadata // {}) end) as $md
            | ((($md.rejected_summary // []) | if type == "array" then length else 0 end)) as $n
            | (if $kind == "legacy" or ($md | has("rejected_sidecars") | not) then null else $md.rejected_sidecars end) as $rs
            | (($rs | type) == "array") as $has_list
            | (if $md.recorded_by? == "record-fallback" and ($md.displaced? | type) == "object" then $md.displaced else null end) as $dp
            | ([$kind, ($n | tostring), (if $has_list or $rs == null then ($has_list | tostring) else "type:" + ($rs | type) end),
                (($dp.findings? // 0) | if type == "number" then tostring else "0" end),
                (($dp.status? // "-") | tostring), (($dp.timestamp? // "-") | tostring),
                (($md.type? // "-") | if type == "string" and length > 0 then . else "-" end)]
               # (twenty-eighth run, b1 DISS-C-001: tab is IFS whitespace — an empty column collapses into its neighbour and
               # shifts every later one, so no column is ever empty)
               | map(if . == "" then "-" else . end) | @tsv),
              # (thirty-third run, b1 DISS-C-002: an empty name, or one holding a newline or another control character, is
              # tagged too — the line transport dropped the first and split the second into two names)
              (if $has_list then ($rs[] | if type != "string" then ("\u0001" + tojson)
                                          elif . == "" or test("[\u0000-\u001f\u007f]") then ("\u0002" + tojson) else . end) else empty end)' -- "$ENVELOPE_FILE" 2>/dev/null) || _snap=""
        if [[ -z "$_snap" ]]; then
            violations+=("dissent envelope $ENVELOPE_FILE is not parseable JSON — the rejected-payload contract cannot be checked; repair the envelope or re-run the dissent")
            return 0
        fi
        { IFS=$'\t' read -r kind n has_list dfind dstat dts etype; listed=$(cat); } <<<"$_snap"
        # twenty-seventh run, c2c DISS-C-001: an envelope that declares the other gate's type (an explicit --envelope at
        # adversarial-review.json for the audit gate) is never judged against that gate's rejected set — it is the violation
        if [[ -n "${etype:-}" && "$etype" != "-" && "$etype" != "$GATE" ]]; then
            violations+=("dissent envelope $ENVELOPE_FILE declares type $etype for gate $GATE — name this gate's envelope (adversarial-$GATE.json) or re-run the dissent")
            return 0
        fi
        # twenty-fourth run, b2 DISS-C-002: a fallback record that moved an envelope with findings aside — legitimate when that
        # was the previous round's, never when it was this round's dissent: said, for the reviewer to confirm
        [[ "${dfind:-0}" =~ ^[1-9][0-9]*$ ]] && warnings+=("dissent envelope $(basename -- "$ENVELOPE_FILE") is a --record-fallback record that displaced an envelope with $dfind findings (status ${dstat:--}, timestamp ${dts:--}; now .prev) — confirm it was the previous round's, not this round's dissent")
        [[ "$n" =~ ^[0-9]+$ ]] || n=0
        if [[ "$kind" == metadata:* ]]; then
            violations+=("dissent envelope $(basename -- "$ENVELOPE_FILE") carries a metadata of type ${kind#metadata:} (an object is the contract) — repair the envelope or re-run the dissent")
            return 0
        fi
        if [[ "$kind" == "legacy" ]]; then
            # (fifteenth run, b1 C-003: a sidecar NEWER than the pre-FR-2 envelope is a run that died after writing rows —
            # its rows count, as on the listed path; only rows as old as the envelope ride the legacy pass)
            local _lf _legacy_files="" _newer_files=""
            for _lf in "$envdir"/adversarial-rejected-"$GATE"*.jsonl; do
                [[ -e "$_lf" || -L "$_lf" ]] || continue            # (the literal pattern of a no-match glob)
                [[ -f "$_lf" && ! -s "$_lf" ]] && continue          # (an empty regular file counts nothing; anything else is judged by _rejected_rows_of — nineteenth run, b1 C-003)
                # (twentieth run, c2d C-002: a non-regular entry has no age to split on — `-nt` is false for a dangling link — so it is judged here)
                if [[ ! -f "$_lf" ]]; then _rejected_rows_of "$_lf"; continue; fi
                if [[ "$_lf" -nt "$ENVELOPE_FILE" ]] && ! _vd_committed "$_lf"; then _newer_files+="${_newer_files:+, }$(basename -- "$_lf")"; _rejected_rows_of "$_lf"
                else _legacy_files+="${_legacy_files:+, }$(basename -- "$_lf")"; fi
            done
            [[ -n "$_legacy_files" ]] && warnings+=("dissent envelope $(basename -- "$ENVELOPE_FILE") predates the rejected-payload contract (no metadata.rejected_summary) — the sidecar rows beside it ($_legacy_files) are not counted; re-run the dissent to bring them under the contract")
            [[ -n "$_newer_files" ]] && warnings+=("dissent envelope $(basename -- "$ENVELOPE_FILE") predates the rejected-payload contract but $_newer_files is newer than it — a later run ended after writing rows; those rows are counted: triage them under '## Rejected dissent payloads' or re-run the dissent")
            (( rows > 0 )) || return 0
            kind="array"; n=0; has_list="legacy"; listed=""   # (only the newer rows count: neither the listed nor the glob pass runs)
        fi
        # twenty-fourth run, b1 DISS-C-002: a rejected_sidecars that is not an array was read as absent, silently — it is a
        # violation naming its type; the glob scan below still counts the rows beside the envelope
        if [[ "$has_list" == type:* ]]; then
            violations+=("dissent envelope $(basename -- "$ENVELOPE_FILE") carries a metadata.rejected_sidecars of type ${has_list#type:} (an array is the contract) — repair the envelope or re-run the dissent")
            has_list="false"
        fi
        if [[ "$kind" != "array" ]]; then
            violations+=("dissent envelope $(basename -- "$ENVELOPE_FILE") carries a metadata.rejected_summary of type $kind (an array is the contract) — repair the envelope or re-run the dissent")
            return 0
        fi
    fi
    if [[ "$has_list" == "true" ]]; then
        # a listed sidecar is resolved beside the envelope only (never an arbitrary path from the envelope), and only
        # a sidecar NAME is counted — a non-string entry or a sibling that is no sidecar is a violation (b C-004)
        # (thirty-fifth run, b1 DISS-C-001: membership is an exact compare over an array — a space-joined string let a listed name
        # holding a space and another sidecar's name mask that sidecar as a substring)
        local -a listed_names=() ; local _bn
        while IFS= read -r f; do
            [[ -n "$f" ]] || continue
            if [[ "$f" == $'\001'* ]]; then
                violations+=("dissent envelope $(basename -- "$ENVELOPE_FILE") lists a non-string entry ${f#$'\001'} in metadata.rejected_sidecars — repair the envelope or re-run the dissent")
                continue
            fi
            if [[ "$f" == $'\002'* ]]; then
                violations+=("dissent envelope $(basename -- "$ENVELOPE_FILE") lists a malformed entry ${f#$'\002'} in metadata.rejected_sidecars (empty, or a control character no sidecar name holds) — repair the envelope or re-run the dissent")
                continue
            fi
            _bn=$(basename -- "$f")
            if [[ "$_bn" != adversarial-rejected-"$GATE"*.jsonl ]]; then
                violations+=("dissent envelope $(basename -- "$ENVELOPE_FILE") lists $_bn in metadata.rejected_sidecars, which is not an adversarial-rejected-$GATE*.jsonl sidecar — repair the envelope or re-run the dissent")
                continue
            fi
            _vd_listed "$_bn" ${listed_names[@]+"${listed_names[@]}"} && continue   # (thirteenth run, b C-003: listed twice, counted once)
            listed_names+=("$_bn")
            _rejected_rows_of "$envdir/$_bn" listed
        done <<<"$listed"
        # eighth / tenth run, chunk b C-001: a non-empty sidecar the envelope does not list is never silent and never
        # exempt by age (a failed companion's tagged rows from an earlier chunk are older than the final envelope).
        # eleventh run, chunk b DISS-C-001: its rows COUNT — they raise `need`, so the section must cover them and the
        # printed repair is real — and a warning names the file; a hard violation that only deleting the evidence
        # could clear contradicted the contract both resources state
        local u
        for u in "$envdir"/adversarial-rejected-"$GATE"*.jsonl; do
            [[ -e "$u" || -L "$u" ]] || continue                    # (the literal pattern of a no-match glob)
            [[ -f "$u" && ! -s "$u" ]] && continue                  # (an empty regular file counts nothing; anything else is judged by _rejected_rows_of — b1 C-003)
            _vd_listed "$(basename -- "$u")" ${listed_names[@]+"${listed_names[@]}"} && continue
            _rejected_rows_of "$u"
            [[ -f "$u" && -r "$u" ]] || continue                    # (its violation says the rows cannot be triaged — no "counted" warning beside it — twenty-sixth run, b1 DISS-C-002)
            if [[ "$u" -nt "$ENVELOPE_FILE" ]]; then
                warnings+=("rejected-payload sidecar $(basename -- "$u") is newer than the dissent envelope and not listed in its metadata.rejected_sidecars — the envelope may be stale (a run ended after writing rows); its rows are counted: triage them under '## Rejected dissent payloads' or re-run the dissent")
            else
                warnings+=("rejected-payload sidecar $(basename -- "$u") beside the envelope is not listed in its metadata.rejected_sidecars (an earlier run's file that was never folded) — its rows are counted: triage them under '## Rejected dissent payloads' or remove the file before re-running")
            fi
        done
    elif [[ "$has_list" == "false" ]]; then
        for f in "$envdir"/adversarial-rejected-"$GATE"*.jsonl; do _rejected_rows_of "$f"; done
    fi
    need="$n"; source="metadata.rejected_summary"
    if (( rows > n )); then need="$rows"; source="the adversarial-rejected-${GATE}*.jsonl sidecar rows beside it"; fi
    (( need > 0 )) || return 0
    local lines found
    # top-level bullets only (column 0): a sub-bullet under one entry is not a second triage line
    # (stdin, not `-- "$FILE"`: mawk treats `--` as a file name)
    # (thirtieth run, b1 DISS-C-001: a bullet inside a code fence, or under a later H1, is not a triage line — padded, the count
    # passed a section short of an entry; no interval expressions — mawk has none)
    # (thirty-second run, b1 DISS-C-001: no POSIX class either — a pre-1.3.4 mawk has none; b1 DISS-C-002: the section is found
    # by the same fence-aware pass that counts it — a heading quoted in a fence is not the section)
    # (thirty-third run, b1 DISS-C-001: a fence closes only on its own character, at least its own length, with nothing but
    # blanks after — a four-backtick fence quoting a three-backtick example, or a tilde block holding a backtick line, inverted
    # the pass; a backtick run followed by a backtick is no opening fence)
    read -r found lines < <(awk '/^ ? ? ?(```|~~~)/{l = $0; sub(/^ */, "", l); q = substr(l, 1, 1); k = 0; while (substr(l, k + 1, 1) == q) k++; r = substr(l, k + 1)
        if (!f) { if (q != "`" || r !~ /`/) { f = 1; fq = q; fl = k; next } }
        else if (q == fq && k >= fl && r ~ /^[ \t]*$/) { f = 0; next } }
      f{next} /^##? /{inside = ($0 ~ /^## Rejected dissent payloads/); if (inside) s = 1} inside && /^([-*+]|[0-9]+\.)[ \t]/ {c++} END{print s+0, c+0}' < "$FILE") || true
    if (( ! ${found:-0} )); then
        local where
        if [[ -f "$ENVELOPE_FILE" ]]; then where="the dissent envelope $(basename -- "$ENVELOPE_FILE") carries"
        else where="no dissent envelope $(basename -- "$ENVELOPE_FILE") beside this file, but its sidecar(s) hold"; fi
        violations+=("$where $need schema-rejected payload(s) ($source) but this file has no '## Rejected dissent payloads' section — triage each entry there (real defect → count it; not a defect → say why) so a dropped finding is never silently lost (cycle-126 FR-2.3)")
        return 0
    fi
    if (( ${lines:-0} < need )); then
        violations+=("'## Rejected dissent payloads' holds ${lines:-0} top-level triage line(s) but $source carries $need rejected payload(s) — one top-level bullet per entry (title, severity, anchor, reason → real defect counted under the matching heading, or why it is not one)")
    fi
}

violations=()
warnings=()
# sixteenth run, c2d C-002: an explicit empty value reads as "not given" (eleventh run, b DISS-C-002) but never silently —
# a caller whose variable came out empty upstream (a chunk driver's merged envelope) learns which file was read instead
if [[ "$_EMPTY_FLAGS" == *"--envelope "* ]]; then
    warnings+=("--envelope given empty — the sibling $(basename -- "$ENVELOPE_FILE") beside --file is read instead")
fi
if [[ "$_EMPTY_FLAGS" == *"--review-file "* ]]; then
    warnings+=("--review-file given empty — no review file is read")
fi
t_verdict=""
counts_json="null"
t_excluded=0
t_excluded_confirmed=0

# FR-9: scan the "## Observations" section (from that heading to the next
# "## " heading) for finding entries — a list item, table row or bold-led line
# whose first line carries an uppercase severity word (CRITICAL/HIGH/MEDIUM/LOW)
# or `severity: <level>`. Prints three integers: critical entries, HIGH entries
# carrying both `speculative` and `confidence: low`, HIGH entries missing one.
observations_scan() {
    awk '
        /^## / { in_obs = ($0 ~ /^## Observations/) ; next }
        in_obs && ($0 ~ /^[ \t]*([-*+]|[0-9]+\.)[ \t]/ || $0 ~ /^\|/ || $0 ~ /^\*\*/) {
            lc = tolower($0)
            crit = ($0 ~ /(^|[^A-Za-z])CRITICAL([^A-Za-z]|$)/ || lc ~ /severity:[ \t]*critical/)
            high = ($0 ~ /(^|[^A-Za-z])HIGH([^A-Za-z]|$)/ || lc ~ /severity:[ \t]*high/)
            if (crit) { c++ }
            else if (high) {
                if (lc ~ /speculative/ && lc ~ /confidence:[ \t]*low/) ok++; else bad++   # (no POSIX class: thirty-second run, b1 DISS-C-001)
            }
        }
        END { printf "%d %d %d\n", c + 0, ok + 0, bad + 0 }
    ' "$1"
}

# FR-9: an integer field from a trailer JSON payload — "0" when absent,
# "invalid" when present but not a 0..999999 integer.
trailer_int() {
    local payload="$1" field="$2" v
    v=$(printf '%s' "$payload" | jq -r --arg f "$field" \
        'if has($f) then (if (.[$f]|type)=="number" and (.[$f]|floor)==.[$f] and .[$f] >= 0 and ((.[$f]|tostring|length) <= 6) then (.[$f]|tostring) else "invalid" end) else "0" end' 2>/dev/null) || v="invalid"
    printf '%s' "$v"
}

# Emit the JSON result object (only used when --json is set).
emit_json() {
    local exit_code="$1" trailer_found="$2" consistent="$3"
    local viol_json="[]"
    local v
    for v in ${violations[@]+"${violations[@]}"}; do
        viol_json=$(echo "$viol_json" | jq --arg v "$v" '. + [$v]')
    done
    local warn_json="[]"
    for v in ${warnings[@]+"${warnings[@]}"}; do
        warn_json=$(echo "$warn_json" | jq --arg v "$v" '. + [$v]')
    done
    local verdict_arg="$t_verdict"
    jq -n \
        --arg file "$FILE" \
        --arg gate "$GATE" \
        --argjson trailer_found "$trailer_found" \
        --arg verdict "$verdict_arg" \
        --argjson counts "$counts_json" \
        --argjson excluded "$t_excluded" \
        --argjson excluded_confirmed "$t_excluded_confirmed" \
        --argjson consistent "$consistent" \
        --argjson violations "$viol_json" \
        --argjson warnings "$warn_json" \
        --argjson exit_code "$exit_code" \
        --arg envelope "${ENVELOPE_FILE:-}" \
        --argjson envelope_explicit "${ENVELOPE_EXPLICIT:-false}" \
        '{file: $file, gate: $gate, trailer_found: $trailer_found,
          verdict: (if $verdict == "" then null else $verdict end),
          counts: $counts, excluded: $excluded, excluded_confirmed: $excluded_confirmed,
          consistent: $consistent, usage_error: false, violations: $violations, warnings: $warnings,
          envelope: (if $envelope == "" then null else $envelope end), envelope_explicit: $envelope_explicit,
          exit_code: $exit_code}'
}

emit_plain() {
    local trailer_found="$1" consistent="$2"
    if [[ "$trailer_found" == "false" ]]; then
        echo "NO_TRAILER: legacy file, no LOA-VERDICT trailer found: $FILE"
    elif [[ "$consistent" == "true" ]]; then
        echo "CONSISTENT: gate=$GATE verdict=$t_verdict"
    else
        echo "INCONSISTENT: gate=$GATE verdict=${t_verdict:-unknown}"
    fi
}

# Late Sprint 2 review: detection is case-insensitive as well — a lowercase
# `loa-verdict` marker is a malformed trailer (violation), never a legacy file.
trailer_count=$(grep -ciE "$TRAILER_DETECT" -- "$FILE" 2>/dev/null || true)
[[ -z "$trailer_count" ]] && trailer_count=0

# seventh run, chunk b C-003: the rejected-payload contract depends only on the file, the gate and the
# envelope — checked once, before the trailer dispatch, so every path (legacy, --require-trailer, a
# duplicated or malformed trailer, a valid one) reports it in the same pass
rejected_summary_check

# --- No trailer at all: legacy file ---
if [[ "$trailer_count" -eq 0 ]]; then
    if [[ "$REQUIRE_TRAILER" == "true" ]]; then
        for v in ${warnings[@]+"${warnings[@]}"}; do echo "WARN: $v" >&2; done
        violations+=("no LOA-VERDICT trailer found but --require-trailer was set — add one as the last line: <!-- LOA-VERDICT {\"gate\":\"$GATE\",\"verdict\":\"APPROVED\",\"counts\":{\"critical\":0,\"high\":0,\"medium\":0,\"low\":0},\"sprint_id\":\"sprint-N\",\"ts\":\"<ISO8601>\"} -->")
        for v in "${violations[@]}"; do echo "$v" >&2; done
        [[ "$JSON_OUTPUT" == "true" ]] && emit_json 1 false false
        [[ "$JSON_OUTPUT" == "false" ]] && echo "INCONSISTENT: gate=$GATE verdict=none (no trailer)"   # (eleventh run, b DISS-C-003: a status line on every exit)
        exit 1
    fi
    # fourth run, chunk b C-002: the rejected-payload contract applies to a trailer-less file too —
    # untriaged rejected payloads never ride the legacy pass
    # (tenth run, chunk b C-002: warnings reach stderr on the trailer-less paths too)
    for v in ${warnings[@]+"${warnings[@]}"}; do echo "WARN: $v" >&2; done
    if (( ${#violations[@]} > 0 )); then
        for v in "${violations[@]}"; do echo "$v" >&2; done
        [[ "$JSON_OUTPUT" == "true" ]] && emit_json 1 false false
        [[ "$JSON_OUTPUT" == "false" ]] && echo "INCONSISTENT: gate=$GATE verdict=none (no trailer)"   # (eleventh run, b DISS-C-003)
        exit 1
    fi
    [[ "$JSON_OUTPUT" == "true" ]] && emit_json 2 false true
    [[ "$JSON_OUTPUT" == "false" ]] && emit_plain false true
    exit 2
fi

last_line=$(tail -n 1 -- "$FILE")
# R2 review (cycle-119): tolerate CRLF files — strip one trailing \r before
# every exact-string comparison below (first/last/trailer lines).
last_line="${last_line%$'\r'}"

if [[ "$trailer_count" -gt 1 ]]; then
    violations+=("multiple LOA-VERDICT trailers found ($trailer_count) — keep exactly one trailer, as the last line of the file")
else
    trailer_line=$(grep -iE "$TRAILER_DETECT" -- "$FILE" | head -1)
    trailer_line="${trailer_line%$'\r'}"
    if [[ ! "$trailer_line" =~ $TRAILER_CANON ]]; then
        violations+=("LOA-VERDICT marker is malformed — the exact form is '<!-- LOA-VERDICT {json} -->' (single ASCII spaces, ASCII hyphen)")
    fi
    if [[ "$trailer_line" != "$last_line" ]]; then
        violations+=("LOA-VERDICT trailer is not the last line of the file — move it to be the final line with nothing after it")
    fi

    json_payload=$(printf '%s' "$trailer_line" | sed -E 's/^<!-- LOA-VERDICT (.*) -->[[:space:]]*$/\1/')
    if ! printf '%s' "$json_payload" | jq empty >/dev/null 2>&1; then
        violations+=("LOA-VERDICT trailer content is not valid JSON — fix trailer syntax (must be a single JSON object)")
    else
        t_gate=$(printf '%s' "$json_payload" | jq -r '.gate // empty')
        t_verdict=$(printf '%s' "$json_payload" | jq -r '.verdict // empty')
        t_critical=$(printf '%s' "$json_payload" | jq -r '.counts.critical // empty')
        t_high=$(printf '%s' "$json_payload" | jq -r '.counts.high // empty')
        t_medium=$(printf '%s' "$json_payload" | jq -r '.counts.medium // empty')
        t_low=$(printf '%s' "$json_payload" | jq -r '.counts.low // empty')
        counts_json=$(printf '%s' "$json_payload" | jq -c '.counts // null')

        if [[ "$t_gate" != "review" && "$t_gate" != "audit" ]]; then
            violations+=("trailer gate '$t_gate' is not one of review|audit")
        elif [[ "$t_gate" != "$GATE" ]]; then
            violations+=("trailer gate '$t_gate' does not match requested --gate '$GATE'")
        fi

        if [[ "$t_verdict" != "APPROVED" && "$t_verdict" != "CHANGES_REQUIRED" ]]; then
            violations+=("trailer verdict '$t_verdict' is not one of APPROVED|CHANGES_REQUIRED")
        fi

        if ! is_num "$t_critical" || ! is_num "$t_high" || ! is_num "$t_medium" || ! is_num "$t_low"; then
            violations+=("trailer counts.critical/high/medium/low missing or non-numeric — trailer must include integer counts for all four severities")
        else
            severity_sum=$((t_critical + t_high))
            if (( severity_sum > 0 )) && [[ "$t_verdict" != "CHANGES_REQUIRED" ]]; then
                violations+=("trailer says $t_verdict but counts.critical=$t_critical counts.high=$t_high (sum>0) — set verdict CHANGES_REQUIRED or re-triage the HIGH/CRITICAL findings")
            fi
        fi

        # --- FR-9 coverage-first: excluded / Observations / excluded_confirmed ---
        ex_val=$(trailer_int "$json_payload" excluded)
        if [[ "$ex_val" == "invalid" ]]; then
            violations+=("trailer excluded must be a non-negative integer of at most six digits — it counts the HIGH findings demoted to ## Observations as speculative with confidence: low")
        else
            t_excluded=$ex_val
        fi
        exc_val=$(trailer_int "$json_payload" excluded_confirmed)
        if [[ "$exc_val" == "invalid" ]]; then
            violations+=("trailer excluded_confirmed must be a non-negative integer of at most six digits")
        else
            t_excluded_confirmed=$exc_val
        fi
        read -r obs_crit obs_ok obs_bad < <(observations_scan "$FILE")
        if (( obs_crit > 0 )); then
            violations+=("$obs_crit critical finding(s) under ## Observations — critical is never excludable; move them under ## Changes Required and count them")
        fi
        if (( obs_bad > 0 )); then
            violations+=("$obs_bad HIGH finding(s) under ## Observations without both 'speculative' and 'confidence: low' — confidence never demotes; move them under ## Changes Required and count them, or mark them speculative with confidence: low and record them under excluded")
        fi
        if [[ "$ex_val" != "invalid" ]] && (( obs_ok != t_excluded )); then
            violations+=("trailer excluded=$t_excluded but ## Observations holds $obs_ok speculative low-confidence HIGH finding(s) — the two must match so every demotion is visible")
        fi
        if [[ "$t_verdict" == "APPROVED" ]] && (( t_excluded > 0 )); then
            warnings+=("WARN: APPROVED with excluded=$t_excluded speculative low-confidence HIGH finding(s) demoted — the audit gate must confirm each one (excluded_confirmed)")
        fi
        if [[ "$GATE" == "audit" && -n "$REVIEW_FILE" ]]; then
            rev_line=$(grep -iE "$TRAILER_DETECT" -- "$REVIEW_FILE" 2>/dev/null | tail -1)
            rev_line="${rev_line%$'\r'}"
            rev_payload=$(printf '%s' "$rev_line" | sed -E 's/^<!--[^A-Za-z0-9]{0,4}LOA[^A-Za-z0-9]{0,4}VERDICT[[:space:]]*//; s/[[:space:]]*-->[[:space:]]*$//')
            rev_ex="0"
            if [[ -n "$rev_payload" ]] && printf '%s' "$rev_payload" | jq empty >/dev/null 2>&1; then
                rev_ex=$(trailer_int "$rev_payload" excluded)
            fi
            if [[ "$rev_ex" == "invalid" ]]; then
                violations+=("review trailer in $REVIEW_FILE carries a non-integer excluded field")
            elif (( rev_ex != t_excluded_confirmed )); then
                violations+=("audit trailer excluded_confirmed=$t_excluded_confirmed but the review trailer says excluded=$rev_ex — confirm each demoted high independently and record the count")
            fi
        fi

        first_line=$(head -n 1 -- "$FILE")
        first_line="${first_line%$'\r'}"
        if [[ "$GATE" == "review" ]]; then
            if [[ "$t_verdict" == "APPROVED" && "$first_line" != "All good" ]]; then
                violations+=("trailer says APPROVED but first line is not exactly 'All good' — set the first line to 'All good' or change verdict to CHANGES_REQUIRED")
            fi
            if [[ "$t_verdict" == "CHANGES_REQUIRED" && "$first_line" == "All good" ]]; then
                violations+=("first line is 'All good' but trailer verdict is CHANGES_REQUIRED — remove 'All good' as the first line or change verdict to APPROVED")
            fi
            if [[ "$t_verdict" == "APPROVED" ]] && grep -qE '^## (Changes Required|Findings|Issues)' -- "$FILE" 2>/dev/null; then
                violations+=("trailer says APPROVED but file contains a '## Changes Required'/'## Findings'/'## Issues' heading — remove the heading or change verdict to CHANGES_REQUIRED")
            fi
        else
            ritual="APPROVED - LET'S FUCKING GO"
            if [[ "$t_verdict" == "APPROVED" ]] && ! grep -qF "$ritual" -- "$FILE" 2>/dev/null; then
                violations+=("trailer says APPROVED but prose is missing the exact string \"$ritual\" — add it or change verdict to CHANGES_REQUIRED")
            fi
            if [[ "$t_verdict" == "CHANGES_REQUIRED" ]] && grep -qF "$ritual" -- "$FILE" 2>/dev/null; then
                violations+=("prose contains \"$ritual\" but trailer verdict is CHANGES_REQUIRED — remove it or change verdict to APPROVED")
            fi
        fi
    fi
fi

consistent=true
if [[ ${#violations[@]} -gt 0 ]]; then
    consistent=false
fi

for v in ${violations[@]+"${violations[@]}"}; do
    echo "$v" >&2
done
for v in ${warnings[@]+"${warnings[@]}"}; do
    echo "$v" >&2
done

if [[ "$consistent" == "true" ]]; then
    [[ "$JSON_OUTPUT" == "true" ]] && emit_json 0 true true
    [[ "$JSON_OUTPUT" == "false" ]] && emit_plain true true
    exit 0
else
    [[ "$JSON_OUTPUT" == "true" ]] && emit_json 1 true false
    [[ "$JSON_OUTPUT" == "false" ]] && emit_plain true false
    exit 1
fi
