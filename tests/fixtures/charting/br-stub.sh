#!/usr/bin/env bash
# br-stub.sh: a stand-in for beads_rust (br) in the charting suites. No real beads database is
# touched. State is a JSON array in $BR_STATE; every call is appended to $BR_LOG as one line of
# space-joined argv. BR_FAIL_ON=<subcommand> makes that subcommand exit 1 (recovery tests).
# Supported: --version, create, list, show, ready, update, dep add, comments add, close.
set -euo pipefail
: "${BR_STATE:?BR_STATE must be set}"
: "${BR_LOG:=/dev/null}"
[[ -f "$BR_STATE" ]] || echo '[]' > "$BR_STATE"
printf '%s\n' "$*" >> "$BR_LOG"
sub="${1:-}"; shift || true
if [[ -n "${BR_FAIL_ON:-}" && "$sub" == "$BR_FAIL_ON" ]]; then echo "br-stub: forced failure of $sub" >&2; exit 1; fi
# Install a new state only when the producer succeeded and wrote a JSON array; otherwise keep the
# old state and fail loudly. Usage: save <jq args...> (runs jq -c on $BR_STATE).
save(){
  local t; t="$(mktemp)"
  if jq -c "$@" "$BR_STATE" > "$t" 2>"$t.err" && jq -e 'type == "array"' "$t" >/dev/null 2>&1; then
    mv "$t" "$BR_STATE"; rm -f "$t.err"
  else
    echo "br-stub: state update failed; state kept: $(cat "$t.err" 2>/dev/null)" >&2
    rm -f "$t" "$t.err"; exit 1
  fi
}
case "$sub" in
  --version) echo "br 0.2.6-stub" ;;
  create)
    title=""; type="task"; parent=""; labels=""; ext=""; slug=""; desc=""; dry=0
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --type|-t) type="$2"; shift 2 ;;
        --parent) parent="$2"; shift 2 ;;
        --labels|-l) labels="$2"; shift 2 ;;
        --external-ref) ext="$2"; shift 2 ;;
        --slug) slug="$2"; shift 2 ;;
        --description|-d) desc="$2"; shift 2 ;;
        --dry-run) dry=1; shift ;;
        --json|--silent|--ephemeral|--no-daemon|--no-auto-flush|--no-auto-import|--allow-stale|--no-db|--no-color|-q|--quiet|-v|--verbose) shift ;;
        -*)
          # unknown flag: take a value only when one follows that is not itself a flag
          if [[ $# -ge 2 && "${2:0:1}" != "-" ]]; then shift 2; else shift; fi ;;
        *) title="$1"; shift ;;
      esac
    done
    n="$(jq 'length' "$BR_STATE")"
    id="bd-${slug:-x}-$((n + 1))"
    obj="$(jq -cn --arg id "$id" --arg t "$title" --arg ty "$type" --arg p "$parent" --arg l "$labels" --arg e "$ext" --arg d "$desc" \
      '{id:$id, title:$t, issue_type:$ty, status:"open", priority:2, assignee:null, description:$d,
        labels:($l | split(",") | map(select(length > 0))), external_ref:(if $e == "" then null else $e end),
        parent:(if $p == "" then null else $p end), deps:[], comments:[]}')"
    if [[ $dry -eq 1 ]]; then printf '%s\n' "$obj" | jq -c '{dry_run: true, would_create: .}'; exit 0; fi
    save --argjson o "$obj" '. + [$o]'
    printf '%s\n' "$obj" ;;
  list)
    all=0; while [[ $# -gt 0 ]]; do case "$1" in --all|-a) all=1; shift ;; --json) shift ;; *) shift ;; esac; done
    jq -c --argjson all "$all" '[.[] | select($all == 1 or .status != "closed")]' "$BR_STATE" ;;
  show)
    id="$1"; jq -ce --arg id "$id" '[.[] | select(.id == $id)] | if length == 0 then error("not found") else . end' "$BR_STATE" ;;
  ready)
    parent=""; types=()
    while [[ $# -gt 0 ]]; do case "$1" in --parent) parent="$2"; shift 2 ;; --type|-t) types+=("$2"); shift 2 ;; --limit) shift 2 ;; *) shift ;; esac; done
    ty="${types[0]:-}"
    jq -c --arg p "$parent" --arg ty "$ty" '. as $all
      | [.[] | select(.status == "open" and (.assignee == null))
             | select($p == "" or .parent == $p) | select($ty == "" or .issue_type == $ty)
             | select(all(.deps[]; . as $d | ($all | map(select(.id == $d)) | first | .status) == "closed"))]' "$BR_STATE" ;;
  update)
    id="$1"; shift
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --claim) save --arg id "$id" 'map(if .id == $id then .status = "in_progress" | .assignee = "stub" else . end)'; shift ;;
        --add-label) save --arg id "$id" --arg l "$2" 'map(if .id == $id then .labels += [$l] else . end)'; shift 2 ;;
        --status|-s) save --arg id "$id" --arg s "$2" 'map(if .id == $id then .status = $s else . end)'; shift 2 ;;
        *) shift ;;
      esac
    done ;;
  dep)
    [[ "${1:-}" == "add" ]] || { echo "br-stub: dep $1 unsupported" >&2; exit 2; }
    save --arg a "$2" --arg b "$3" 'map(if .id == $a then .deps += [$b] else . end)' ;;
  comments)
    [[ "${1:-}" == "add" ]] || { echo "br-stub: comments $1 unsupported" >&2; exit 2; }
    save --arg id "$2" --arg c "$3" 'map(if .id == $id then .comments += [$c] else . end)' ;;
  close)
    id="$1"; shift; reason=""
    while [[ $# -gt 0 ]]; do case "$1" in --reason|-r) reason="$2"; shift 2 ;; *) shift ;; esac; done
    jq -e --arg id "$id" 'any(.[]; .id == $id)' "$BR_STATE" >/dev/null || { echo "br-stub: unknown $id" >&2; exit 1; }
    save --arg id "$id" --arg r "$reason" 'map(if .id == $id then .status = "closed" | .close_reason = $r else . end)' ;;
  *) echo "br-stub: unsupported subcommand '$sub'" >&2; exit 2 ;;
esac
