#!/usr/bin/env bash
# =============================================================================
# finding-validate.sh — the jq validator of the canonical finding (cycle-133 C-11; FR-11; D-3.2 DEC-0849,
# D-3.5 DEC-0857). One of the four validators of .claude/schemas/finding.schema.json v1 (with the zod schema in
# the Bridgebuilder skill, lib/finding_validate.py and verdict-derive.sh's bullet grammar, which calls this one);
# all four must agree on every vector under .claude/schemas/finding.vectors/{valid,invalid}/.
#
# Usage (CLI):
#   finding-validate.sh [FILE|-]          validate one finding (a JSON object) from FILE or stdin
#   finding-validate.sh --vectors DIR     run every DIR/{valid,invalid}/*.json vector; one line per vector
# Usage (sourced): finding_validate_json <json> → the result JSON on stdout (rc 0 valid, 1 invalid, 2 jq failure);
#   FINDING_VALIDATE_JQ holds the jq program (input: one finding; output: the result plus `_derive`, the text whose
#   sha256 names a derived id — finding_validate_json replaces it with the id).
#
# Output: one JSON line — {"errors": [codes, sorted], "finding": <normalised> | null, "valid": bool,
#   "warnings": [text]} — the same document lib/finding_validate.py prints (rules and codes: that file's header
#   and the schema's x-loa-rules).
#
# Exit: 0 valid (every vector agreed); 1 invalid (a vector disagreed); 2 usage, unreadable input or a jq failure.
# bash 3.2-safe; hashing through compat-lib.sh sha256_portable.
# =============================================================================

[[ -n "${_FINDING_VALIDATE_LOADED:-}" ]] && return 0 2>/dev/null
_FINDING_VALIDATE_LOADED=1
_FV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../compat-lib.sh
source "$_FV_DIR/../compat-lib.sh"

# shellcheck disable=SC2016
FINDING_VALIDATE_JQ='
  def WS: "[ \\t\\n\\r\\f\\x0b]+";
  def line_of: if type == "number" and . == floor and . >= 1 and . <= 10000000 then floor else null end;
  def path_ok: type == "string" and length > 0 and (startswith("/") | not) and (contains("\\") | not)
    and ((explode | any(. < 32 or . == 127)) | not)
    and (split("/") | all(. != "" and . != "." and . != ".."));
  def toks: [splits(WS)] | map(select(length > 0));
  def denied: ascii_downcase as $l
    | any(("todo", "n/a", "see" + WS + "above", "as" + WS + "described", "placeholder");
          . as $p | $l | test("(?<![A-Za-z0-9])" + $p + "(?![A-Za-z0-9])"));
  def when_then: map(sub("^[^A-Za-z0-9]+"; "") | sub("[^A-Za-z0-9]+$"; "") | ascii_downcase) as $st
    | ($st | length) as $n
    | any(range(0; $n); . as $i | $st[$i] == "when" and any(range($i + 2; $n - 1); $st[.] == "then"));
  def content_ok: if denied then false else (toks | (length >= 12) or when_then) end;
  def conf_of: if type == "string" then (if . == "high" or . == "medium" or . == "low" then . else null end)
    elif type == "number" and . >= 0 and . <= 1 then (if . >= 0.75 then "high" elif . >= 0.45 then "medium" else "low" end)
    else null end;
  def warn($k): "`" + $k + "` is an alias of `failure_scenario`; removed in 2.1.0";
  if type != "object" then {errors: ["not_object"], finding: null, valid: false, warnings: []}
  else
    . as $f
    | (if ($f.severity | type) == "string" and ($f.severity | IN("CRITICAL","HIGH","MEDIUM","LOW","PRAISE","SPECULATION","REFRAME","INFO"))
       then ($f.severity | IN("CRITICAL","HIGH","MEDIUM","LOW")) else null end) as $defect
    | ($f.anchor_line | if . == null then null else line_of end) as $line
    | ($f.anchor_line_end | if . == null then null else line_of end) as $end
    | ([ (if $defect == null then "severity" else empty end),
         (if $f.id != null and (($f.id | type) != "string" or ($f.id | test("[^ \\t\\n\\r\\f\\x0b]") | not)) then "id" else empty end),
         (if $f.file != null then (if ($f.file | path_ok) then empty else "file" end) elif $defect == true then "file" else empty end),
         (if $f.anchor_line != null then (if $line == null then "anchor_line" else empty end) elif $defect == true then "anchor_line" else empty end),
         (if $f.anchor_line_end != null and ($end == null or $line == null or $end < $line) then "anchor_line_end" else empty end),
         (if $f.blocking != null and ($f.blocking | type) != "boolean" then "blocking" else empty end),
         (if $f.confidence != null and ($f.confidence | conf_of) == null then "confidence" else empty end),
         (if $f.title != null and ($f.title | type) != "string" then "title" else empty end),
         (if $f.suggestion != null and ($f.suggestion | type) != "string" then "suggestion" else empty end),
         (if $f.failure_scenario != null and $f.failure_mode != null
             and ((($f.failure_scenario | type) == "string" and ($f.failure_mode | type) == "string"
                   and $f.failure_scenario == $f.failure_mode) | not) then "alias_conflict" else empty end)
       ]) as $e0
    | ([["failure_scenario", $f.failure_scenario], ["failure_mode", $f.failure_mode], ["description", $f.description]]
       | map(select(.[1] != null)) | first // null) as $pick
    | (if $pick == null then (if $defect == true then ["failure_scenario"] else [] end)
       elif ($pick[1] | type) != "string" then ["failure_scenario"]
       elif $defect == true and ($pick[1] | content_ok | not) then ["failure_scenario"]
       else [] end) as $e1
    | (($e0 + $e1) | unique) as $errors
    | (if $pick != null and $pick[0] != "failure_scenario" then [warn($pick[0])] else [] end) as $warnings
    | if ($errors | length) > 0 then {errors: $errors, finding: null, valid: false, warnings: $warnings}
      else
        ({severity: $f.severity, blocking: ($f.blocking == true)}
         + (if $f.id != null then {id: $f.id} else {} end)
         + (if $f.file != null then {file: $f.file} else {} end)
         + (if $line != null then {anchor_line: $line} else {} end)
         + (if $end != null then {anchor_line_end: $end} else {} end)
         + (if $pick != null then {failure_scenario: $pick[1]} else {} end)
         + (if $f.confidence != null then {confidence: ($f.confidence | conf_of)} else {} end)
         + (if $f.title != null then {title: $f.title} else {} end)
         + (if $f.suggestion != null then {suggestion: $f.suggestion} else {} end)) as $n
        | {errors: [], finding: $n, valid: true, warnings: $warnings}
          + (if $f.id == null then {_derive: "\($f.file // ""):\($line // ""):\($f.title // "")"} else {} end)
      end
  end'

finding_validate_json() {  # <finding json> → result JSON; rc 0 valid, 1 invalid, 2 jq failure
    local _r _h
    _r=$(printf '%s' "$1" | jq -c "$FINDING_VALIDATE_JQ") || return 2
    [[ -n "$_r" ]] || return 2
    if [[ "$(jq -r 'has("_derive")' <<<"$_r")" == "true" ]]; then
        _h=$(jq -j '._derive' <<<"$_r" | sha256_portable) || return 2
        _r=$(jq -c --arg id "F-${_h:0:6}" '.finding.id = $id | del(._derive)' <<<"$_r") || return 2
    fi
    printf '%s\n' "$_r"
    [[ "$(jq -r '.valid' <<<"$_r")" == "true" ]] && return 0
    return 1
}

_finding_validate_vectors() {  # <dir>
    local root="$1" kind f got exp n=0 bad=0 rc same
    for kind in valid invalid; do
        for f in "$root/$kind"/*.json; do
            [[ -f "$f" ]] || continue
            n=$((n + 1))
            rc=0
            got=$(finding_validate_json "$(jq -c '.finding' "$f")") || rc=$?
            if [[ "$rc" -eq 2 ]]; then
                echo "DISAGREE $kind/$(basename "$f") (jq failure)"; bad=$((bad + 1)); continue
            fi
            exp=$(jq -c '.expect' "$f")
            same=$(jq -n --argjson a "$got" --argjson b "$exp" --arg k "$kind" '$a == $b and ($a.valid == ($k == "valid"))') || same=false
            if [[ "$same" == "true" ]]; then echo "ok $kind/$(basename "$f")"
            else echo "DISAGREE $kind/$(basename "$f") got $got"; bad=$((bad + 1)); fi
        done
    done
    if [[ "$n" -eq 0 ]]; then echo "finding-validate.sh: no vectors under $root" >&2; return 2; fi
    echo "vectors $n, disagreements $bad"
    [[ "$bad" -eq 0 ]]
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -euo pipefail
    export LC_ALL=C
    case "${1:-}" in
        -h|--help) sed -n '3,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        --vectors)
            [[ $# -eq 2 ]] || { echo "usage: finding-validate.sh --vectors DIR" >&2; exit 2; }
            _finding_validate_vectors "$2" && exit 0
            exit $? ;;
    esac
    [[ $# -le 1 ]] || { echo "usage: finding-validate.sh [FILE|-] | --vectors DIR" >&2; exit 2; }
    if [[ $# -eq 0 || "$1" == "-" ]]; then _in=$(cat); else
        [[ -r "$1" && ! -d "$1" ]] || { echo "finding-validate.sh: unreadable input: $1" >&2; exit 2; }
        _in=$(cat -- "$1"); fi
    jq empty <<<"$_in" 2>/dev/null || { echo "finding-validate.sh: unreadable input: not JSON" >&2; exit 2; }
    _rc=0
    finding_validate_json "$_in" || _rc=$?
    exit "$_rc"
fi
