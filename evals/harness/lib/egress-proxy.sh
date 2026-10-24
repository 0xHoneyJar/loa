#!/usr/bin/env bash
# =============================================================================
# lib/egress-proxy.sh — the egress block of an ablation batch (cycle-133 FR-9; SDD C-9, § 5.2; D-2.4 DEC-0847,
# D-2.5 DEC-0854; beads bd-ijxuk)
#
# Threat model: the block denies repository and arbitrary-destination egress from the sandbox (cycle-132: nine
# a0_bare_matched sessions reached github.com). Exfiltration through an allowlisted model API is out of scope and
# left to the grader's class-9 tripwire.
#
# Layout per batch <B>:
#   loa-egress-<B>       docker network --internal (no route out, no gateway reachable): the sandboxes join it with
#                        --dns 0.0.0.1 (no resolver: container names still resolve through Docker's embedded DNS,
#                        nothing else does) and HTTPS_PROXY/HTTP_PROXY=http://loa-proxy-<B>:8888, NO_PROXY=
#   loa-egress-<B>-ext   an ordinary bridge network (created here unless --external-network names one)
#   loa-proxy-<B>        the sidecar (Dockerfile.proxy, tinyproxy 1.11): on both networks; hostname allowlist,
#                        CONNECT to 443 only, and netfilter in its own namespace that rejects every private,
#                        loopback, link-local/metadata and reserved address after resolution (DNS rebinding,
#                        the host gateway) and every port but 443
#
# Usage:
#   egress-proxy.sh allowlist [--model-config F] [--providers CSV] [--region R]...
#       print the allowlist (sorted, unique) from providers.<p>.egress_hosts[] of model-config.yaml (default
#       .claude/defaults/model-config.yaml; every provider unless --providers); `{region}` in an entry expands to
#       the provider's region_default and every --region given. Exit 2 when an entry is not a hostname or the
#       list is empty.
#   egress-proxy.sh up <batch> <allowlist-file> [--image IMG] [--external-network NET]
#                   [--test-allow-addr IPV4]... [--test-add-host NAME:IPV4]...
#       create the networks and start the sidecar; prints one JSON object {batch, network, proxy, proxy_url,
#       external_network, image, image_id, allowlist, allowlist_sha256}. Refuses (exit 2, nothing created) a
#       network or sidecar of the batch that already exists (repair: egress-proxy.sh down <batch>), a missing
#       image (repair: the docker build line), an allowlist entry that is not a lower-case hostname, an empty
#       allowlist. A start failure removes what it created (exit 1). The two --test-* options exist for
#       evals/tests/egress-proxy.bats only and are refused unless LOA_EGRESS_TEST_MODE=1 and the caller runs
#       inside bats (BATS_TEST_FILENAME set): they let the local stub endpoint (a private Docker address)
#       through the private-range rule.
#   egress-proxy.sh down <batch> [--log-dir DIR]
#       (idempotent) save the sidecar log to DIR/proxy.log and every parsed denial to DIR/denied.jsonl, then
#       remove the sidecar and the batch's networks
#   egress-proxy.sh self-check <batch> --image IMG [--log F] [--probe-host H]...
#       run the isolation checks from a sandbox-shaped container of IMG on the batch network: a connectivity
#       probe (CONNECT tunnel established, no credential, no completion token) per allowlisted host (or per
#       --probe-host), and the denials — github.com, raw.githubusercontent.com, gitlab.com (curl and
#       git ls-remote), direct IPv4 and IPv6, CONNECT to a non-allowlisted port, plain HTTP, the metadata
#       address, the host gateway, alternate hostname encodings, external DNS, a misconfigured or absent proxy —
#       then the denial attribution (the probe's denied connects carry its address) and the sidecar's netfilter
#       rules. One `<check>: PASS|FAIL <detail>` line each, to --log (default stdout). Exit 0 all PASS, 1 any FAIL.
#   egress-proxy.sh denials <batch>
#       the sidecar's denials as JSON lines {at, src, method, host, port, reason, request}
#   egress-proxy.sh record-address --network N --container C --label L --meta DIR --event start|end|watch
#                   [--max-s S] [--parent-pid P]
#       (pipeline-run.sh, blind-session.sh) start: wait up to $LOA_EGRESS_ADDR_WAIT_S (default 30) for C's address
#       on N and append {event, label, container, network, address, at} to DIR/egress-addr.jsonl; end: append the
#       end record, then append to DIR/egress-denied.jsonl every denial of the batch's sidecar whose source is
#       that address between the label's start (less 1 s) and its end (plus 2 s), with label and container.
#       watch (the launchers start it in the background just before `docker run`): start, then poll every second
#       until C is gone, P (the launcher) has exited or S seconds (default 7200) have passed, then end.
#       Never fails the caller (exit 0; a docker error records address null)
#
# Options common to every command: --docker-bin D (default $EVAL_DOCKER_BIN, else docker).
# Exit codes (SDD § 5.4): 0 done; 1 failed step; 2 refusal before any write (usage, precondition).
# Tested by evals/tests/egress-proxy.bats (the container cases are a release gate: never quarantined).
# =============================================================================
set -euo pipefail
export LC_ALL=C

EP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EP_REPO="$(cd "$EP_DIR/../../.." && pwd)"
DOCKER_BIN="${EVAL_DOCKER_BIN:-docker}"
PROXY_IMAGE_DEFAULT="loa-egress-proxy:259"
PROXY_PORT=8888
# a lower-case DNS name of two or more labels whose last label holds a letter (never an IP literal)
HOST_RE='^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9-]*[a-z][a-z0-9-]*$'
BATCH_RE='^[A-Za-z0-9._-]{1,80}$'

die() { echo "egress-proxy: $*" >&2; exit 2; }
fail() { echo "egress-proxy: $*" >&2; exit 1; }
now_iso() { python3 -I -c 'import datetime; print(datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ"))'; }
names() {  # names <batch> → sets NET EXT PROXY
  [[ "$1" =~ $BATCH_RE ]] || die "invalid batch '$1' (must match $BATCH_RE)"
  NET="loa-egress-$1" EXT="loa-egress-$1-ext" PROXY="loa-proxy-$1"
}
dk() { "$DOCKER_BIN" "$@"; }
exists_container() { dk container inspect "$1" >/dev/null 2>&1; }
exists_network() { dk network inspect "$1" >/dev/null 2>&1; }

# --- allowlist ---------------------------------------------------------------------
cmd_allowlist() {
  local cfg="$EP_REPO/.claude/defaults/model-config.yaml" providers="" regions=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --model-config) cfg="${2:-}"; shift 2 ;;
      --providers) providers="${2:-}"; shift 2 ;;
      --region) [[ "${2:-}" =~ ^[a-z]{2}(-[a-z]+)+-[0-9]$ ]] || die "--region must be an AWS region id"; regions+=("$2"); shift 2 ;;
      --docker-bin) DOCKER_BIN="${2:-}"; shift 2 ;;
      *) die "allowlist: unknown option $1" ;;
    esac
  done
  [[ -f "$cfg" ]] || die "allowlist: model config not found: $cfg"
  local json
  json="$(yq -o=json '.providers // {}' "$cfg")" || die "allowlist: $cfg does not parse"
  python3 -I -c '
import json, re, sys
provs = json.loads(sys.argv[1]); want = [p for p in sys.argv[2].split(",") if p]; regions = sys.argv[3].split() if sys.argv[3] else []
host_re = re.compile(sys.argv[4])
if want:
    missing = [p for p in want if p not in provs]
    if missing:
        sys.exit("egress-proxy: allowlist: unknown provider(s): " + ", ".join(missing))
out = set()
for name in sorted(provs):
    if want and name not in want:
        continue
    p = provs[name] or {}
    hosts = p.get("egress_hosts", [])
    if not isinstance(hosts, list):
        sys.exit("egress-proxy: allowlist: providers.%s.egress_hosts must be a list" % name)
    regs = sorted(set(([p["region_default"]] if isinstance(p.get("region_default"), str) else []) + regions))
    for h in hosts:
        if not isinstance(h, str):
            sys.exit("egress-proxy: allowlist: providers.%s.egress_hosts holds a non-string" % name)
        expanded = [h.replace("{region}", r) for r in regs] if "{region}" in h else [h]
        for e in expanded:
            if not host_re.match(e):
                sys.exit("egress-proxy: allowlist: providers.%s.egress_hosts entry %r is not a lower-case hostname" % (name, e))
            out.add(e)
if not out:
    sys.exit("egress-proxy: allowlist: no egress_hosts (providers: %s)" % (",".join(want) or "all"))
print("\n".join(sorted(out)))
' "$json" "$providers" "${regions[*]+"${regions[*]}"}" "$HOST_RE" || exit 2
}

read_allowlist() {  # read_allowlist <file> → ALLOW (space-separated), validated
  local f="$1" h n=0
  [[ -f "$f" ]] || die "allowlist file not found: $f"
  ALLOW=""
  while IFS= read -r h || [[ -n "$h" ]]; do
    [[ -z "$h" || "$h" == \#* ]] && continue
    [[ "$h" =~ $HOST_RE ]] || die "allowlist entry '$h' is not a lower-case hostname ($f)"
    ALLOW="$ALLOW${ALLOW:+ }$h"; n=$((n + 1))
  done < "$f"
  [[ $n -gt 0 ]] || die "allowlist $f is empty: an empty allowlist would deny the model endpoints too (generate it with: egress-proxy.sh allowlist > $f)"
  [[ $n -le 200 ]] || die "allowlist $f has $n hosts (at most 200)"
}

# --- up / down -------------------------------------------------------------------------
cmd_up() {
  local batch="${1:-}" file="${2:-}" image="$PROXY_IMAGE_DEFAULT" extnet="" test_allow=() test_hosts=()
  [[ -n "$batch" && -n "$file" ]] || die "usage: egress-proxy.sh up <batch> <allowlist-file> [--image IMG] [--external-network NET]"
  shift 2
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --image) image="${2:-}"; shift 2 ;;
      --external-network) extnet="${2:-}"; [[ "$extnet" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$ ]] || die "--external-network: invalid name"; shift 2 ;;
      --test-allow-addr) [[ "${2:-}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || die "--test-allow-addr must be an IPv4 address"; test_allow+=("$2"); shift 2 ;;
      --test-add-host) [[ "${2:-}" =~ ^[a-z0-9.-]{1,253}:([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || die "--test-add-host must be NAME:IPV4"; test_hosts+=("$2"); shift 2 ;;
      --docker-bin) DOCKER_BIN="${2:-}"; shift 2 ;;
      *) die "up: unknown option $1" ;;
    esac
  done
  if [[ ${#test_allow[@]} -gt 0 || ${#test_hosts[@]} -gt 0 ]]; then
    [[ "${LOA_EGRESS_TEST_MODE:-}" == 1 && -n "${BATS_TEST_FILENAME:-}" ]] \
      || die "--test-allow-addr and --test-add-host are test-only (LOA_EGRESS_TEST_MODE=1 inside bats)"
  fi
  [[ "$image" =~ ^[A-Za-z0-9._:/@-]{1,200}$ ]] || die "--image has unexpected characters"
  names "$batch"
  read_allowlist "$file"
  dk image inspect "$image" >/dev/null 2>&1 \
    || die "proxy image $image not found; build it: docker build -t $image - < evals/harness/Dockerfile.proxy"
  exists_container "$PROXY" && die "sidecar $PROXY already exists; remove it first: egress-proxy.sh down $batch"
  exists_network "$NET" && die "network $NET already exists; remove it first: egress-proxy.sh down $batch"
  [[ -n "$extnet" ]] || { exists_network "$EXT" && die "network $EXT already exists; remove it first: egress-proxy.sh down $batch"; }
  if [[ -n "$extnet" ]]; then exists_network "$extnet" || die "--external-network $extnet does not exist"; fi

  local created_ext=false rc=0
  undo() { dk rm -f "$PROXY" >/dev/null 2>&1 || true; dk network rm "$NET" >/dev/null 2>&1 || true
           [[ "$created_ext" == true ]] && { dk network rm "$EXT" >/dev/null 2>&1 || true; }; return 0; }
  if [[ -z "$extnet" ]]; then
    dk network create --driver bridge --label "loa.egress.batch=$batch" "$EXT" >/dev/null || { undo; fail "network create $EXT failed"; }
    created_ext=true; extnet="$EXT"
  fi
  dk network create --internal --driver bridge --label "loa.egress.batch=$batch" "$NET" >/dev/null \
    || { undo; fail "network create $NET failed"; }
  local -a run=(run -d --name "$PROXY" --label "loa.egress.batch=$batch" --network "$extnet"
                --read-only --tmpfs /tmp:rw,size=8m --cap-drop ALL --cap-add NET_ADMIN --cap-add SETUID --cap-add SETGID
                --security-opt no-new-privileges --pids-limit 128 --memory 256m
                -e "LOA_EGRESS_ALLOWLIST=$ALLOW")
  [[ ${#test_allow[@]} -gt 0 ]] && run+=(-e "LOA_EGRESS_TEST_ALLOW=${test_allow[*]}")
  local th; for th in ${test_hosts[@]+"${test_hosts[@]}"}; do run+=(--add-host "$th"); done
  dk "${run[@]}" "$image" >/dev/null || { undo; fail "sidecar $PROXY did not start"; }
  dk network connect "$NET" "$PROXY" >/dev/null || { undo; fail "network connect $NET $PROXY failed"; }
  local i=0 ready=false
  while [[ $i -lt 75 ]]; do
    if dk logs "$PROXY" 2>&1 | grep -q 'Starting main loop'; then ready=true; break; fi
    [[ "$(dk inspect -f '{{.State.Running}}' "$PROXY" 2>/dev/null || echo false)" == true ]] || break
    sleep 0.2; i=$((i + 1))
  done
  if [[ "$ready" != true ]]; then
    echo "egress-proxy: sidecar log:" >&2; dk logs "$PROXY" 2>&1 | tail -5 >&2 || true
    undo; fail "sidecar $PROXY is not accepting connections (netfilter or tinyproxy failed; see the log above)"
  fi
  local iid sha
  iid="$(dk image inspect --format '{{.Id}}' "$image" 2>/dev/null || echo "")"
  sha="$(printf '%s\n' $ALLOW | python3 -I -c 'import hashlib, sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')"
  jq -cn --arg b "$batch" --arg n "$NET" --arg p "$PROXY" --arg u "http://$PROXY:$PROXY_PORT" --arg x "$extnet" \
    --arg img "$image" --arg iid "$iid" --arg allow "$ALLOW" --arg sha "$sha" \
    '{batch: $b, network: $n, proxy: $p, proxy_url: $u, external_network: $x, image: $img, image_id: $iid,
      allowlist: ($allow | split(" ")), allowlist_sha256: $sha}'
  return $rc
}

cmd_down() {
  local batch="${1:-}" logdir=""
  [[ -n "$batch" ]] || die "usage: egress-proxy.sh down <batch> [--log-dir DIR]"
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --log-dir) logdir="${2:-}"; shift 2 ;;
      --docker-bin) DOCKER_BIN="${2:-}"; shift 2 ;;
      *) die "down: unknown option $1" ;;
    esac
  done
  names "$batch"
  if [[ -n "$logdir" ]] && exists_container "$PROXY"; then
    mkdir -p "$logdir"
    dk logs --timestamps "$PROXY" > "$logdir/proxy.log" 2>&1 || true
    parse_denials < "$logdir/proxy.log" > "$logdir/denied.jsonl" || true
  fi
  dk rm -f "$PROXY" >/dev/null 2>&1 || true
  dk network rm "$NET" >/dev/null 2>&1 || true
  # the external network only when this batch created it (its label names the batch)
  if [[ "$(dk network inspect -f '{{index .Labels "loa.egress.batch"}}' "$EXT" 2>/dev/null || true)" == "$batch" ]]; then
    dk network rm "$EXT" >/dev/null 2>&1 || true
  fi
  if exists_container "$PROXY" || exists_network "$NET"; then fail "down $batch: $PROXY or $NET is still present"; fi
  return 0
}

# --- denials: tinyproxy's log → JSON lines -----------------------------------------------
# A connection logs `Connect (file descriptor N): <src>`, then `Request (file descriptor N): <method> <target>`,
# then one outcome: `Established connection to host "<h>"` (allowed) or a refusal — `Proxying refused on filtered
# domain|url "<h>"`, `Refused CONNECT method on port <p>`, or an ERROR (`opensock: Could not establish a connection
# to <h>:<p>`, a resolution failure: the netfilter rejection lands here). Outcome lines carry no descriptor, so each
# is matched to the newest pending request with the same host (and port); requests run in threads, so two clients
# asking for the same host at the same instant can swap (the record is still a denial of that host).
parse_denials() {
  python3 -I -c '
import json, re, sys
conn_re = re.compile(r"Connect \(file descriptor (\d+)\): (\S+)")
req_re = re.compile(r"Request \(file descriptor (\d+)\): (\S+) (\S+)")
est_re = re.compile(r"Established connection to host \"([^\"]+)\"")
filt_re = re.compile(r"Proxying refused on filtered (?:domain|url) \"([^\"]+)\"")
port_re = re.compile(r"Refused CONNECT method on port (\d+)")
err_re = re.compile(r"^ERROR\s.*?\]: (.*)$")
hostport_re = re.compile(r"([A-Za-z0-9._\[\]:%-]+?):(\d+)\s*$")
src = {}; pending = []
def split_target(method, target):
    if method == "CONNECT":
        m = re.match(r"^\[?([^\]]*?)\]?:(\d+)$", target)
        return (m.group(1), int(m.group(2))) if m else (target, None)
    m = re.match(r"^[a-zA-Z]+://(\[[^\]]+\]|[^/:]+)(?::(\d+))?", target)
    if not m:
        return (target, None)
    return (m.group(1).strip("[]"), int(m.group(2)) if m.group(2) else 80)
def take(pred):
    for i in range(len(pending) - 1, -1, -1):
        if pred(pending[i]):
            return pending.pop(i)
    return None
def emit(p, reason, at):
    print(json.dumps({"at": at, "src": p["src"], "method": p["method"], "host": p["host"], "port": p["port"],
                      "reason": reason, "request": p["request"]}, sort_keys=True))
for raw in sys.stdin:
    raw = raw.rstrip("\n")
    at, _, line = raw.partition(" ")
    if not re.match(r"^\d{4}-\d\d-\d\dT", at):
        at, line = None, raw
    m = conn_re.search(line)
    if m:
        src[m.group(1)] = m.group(2); continue
    m = req_re.search(line)
    if m:
        h, port = split_target(m.group(2), m.group(3))
        pending.append({"fd": m.group(1), "src": src.get(m.group(1)), "method": m.group(2), "host": h.lower(),
                        "port": port, "request": (m.group(2) + " " + m.group(3))[:300], "at": at}); continue
    m = est_re.search(line)
    if m:
        take(lambda p: p["host"] == m.group(1).lower()); continue
    m = filt_re.search(line)
    if m:
        p = take(lambda p: p["host"] == m.group(1).lower() or m.group(1).lower() in p["request"].lower())
        if p: emit(p, "filtered", at)
        continue
    m = port_re.search(line)
    if m:
        p = take(lambda p: p["method"] == "CONNECT" and p["port"] == int(m.group(1)))
        if p: emit(p, "connect_port", at)
        continue
    m = err_re.search(line)
    if m:
        msg = m.group(1); hp = hostport_re.search(msg)
        if hp:
            p = take(lambda p: p["host"] == hp.group(1).lower().strip("[]") and p["port"] == int(hp.group(2)))
        else:
            p = take(lambda p: p["host"].lower() in msg.lower())
        if p: emit(p, "connect_failed", at)
        continue
'
}

cmd_denials() {
  local batch="${1:-}"; [[ -n "$batch" ]] || die "usage: egress-proxy.sh denials <batch>"; shift
  while [[ $# -gt 0 ]]; do case "$1" in --docker-bin) DOCKER_BIN="${2:-}"; shift 2 ;; *) die "denials: unknown option $1" ;; esac; done
  names "$batch"
  exists_container "$PROXY" || fail "sidecar $PROXY is not running"
  dk logs --timestamps "$PROXY" 2>&1 | parse_denials
}

# --- record-address: the container address in meta, and the denials it caused --------------
cmd_record_address() {
  local net="" cont="" label="" meta="" ev="" max_s="" ppid_w=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --network) net="${2:-}"; shift 2 ;;
      --container) cont="${2:-}"; shift 2 ;;
      --label) label="${2:-}"; shift 2 ;;
      --meta) meta="${2:-}"; shift 2 ;;
      --event) ev="${2:-}"; shift 2 ;;
      --max-s) max_s="${2:-}"; shift 2 ;;
      --parent-pid) ppid_w="${2:-}"; shift 2 ;;
      --docker-bin) DOCKER_BIN="${2:-}"; shift 2 ;;
      *) echo "egress-proxy: record-address: unknown option $1" >&2; return 0 ;;
    esac
  done
  if [[ "$ev" == watch ]]; then
    [[ "$max_s" =~ ^[0-9]{1,6}$ ]] || max_s=7200
    [[ "$ppid_w" =~ ^[0-9]{1,10}$ ]] || ppid_w=""
    local -a common=(--network "$net" --container "$cont" --label "$label" --meta "$meta" --docker-bin "$DOCKER_BIN")
    cmd_record_address "${common[@]}" --event start
    local t=0
    while [[ $t -lt $max_s ]]; do
      dk container inspect "$cont" >/dev/null 2>&1 || break
      if [[ -n "$ppid_w" ]] && ! kill -0 "$ppid_w" 2>/dev/null; then break; fi
      sleep 1; t=$((t + 1))
    done
    cmd_record_address "${common[@]}" --event end
    return 0
  fi
  [[ -n "$net" && -n "$cont" && -n "$meta" && "$net" == loa-egress-* ]] || { echo "egress-proxy: record-address: needs --network loa-egress-<batch> --container --meta" >&2; return 0; }
  case "$ev" in start|end|watch) ;; *) echo "egress-proxy: record-address: --event start|end|watch" >&2; return 0 ;; esac
  mkdir -p "$meta"
  local addr="" i=0 wait_s="${LOA_EGRESS_ADDR_WAIT_S:-30}" at
  [[ "$wait_s" =~ ^[0-9]{1,3}$ ]] || wait_s=30
  if [[ "$ev" == start ]]; then
    while [[ $i -lt $((wait_s * 5)) ]]; do
      addr="$(dk inspect -f "{{with index .NetworkSettings.Networks \"$net\"}}{{.IPAddress}}{{end}}" "$cont" 2>/dev/null || true)"
      [[ -n "$addr" ]] && break
      sleep 0.2; i=$((i + 1))
    done
  else
    addr="$(jq -r --arg l "$label" --arg c "$cont" 'select(.event == "start" and .label == $l and .container == $c) | .address // empty' \
      "$meta/egress-addr.jsonl" 2>/dev/null | tail -1 || true)"
  fi
  at="$(now_iso)"
  jq -cn --arg e "$ev" --arg l "$label" --arg c "$cont" --arg n "$net" --arg a "$addr" --arg at "$at" \
    '{event: $e, label: $l, container: $c, network: $n, address: (if $a == "" then null else $a end), at: $at}' \
    >> "$meta/egress-addr.jsonl" || true
  [[ "$ev" == end && -n "$addr" ]] || return 0
  local batch="${net#loa-egress-}" start
  start="$(jq -r --arg l "$label" --arg c "$cont" 'select(.event == "start" and .label == $l and .container == $c) | .at' \
    "$meta/egress-addr.jsonl" 2>/dev/null | tail -1 || true)"
  [[ -n "$start" ]] || return 0
  dk logs --timestamps "loa-proxy-$batch" 2>&1 | parse_denials | python3 -I -c '
import datetime, json, sys
addr, start, end, label, cont = sys.argv[1:6]
def t(s):
    s = s.rstrip("Z"); head, _, frac = s.partition(".")
    return datetime.datetime.strptime(head, "%Y-%m-%dT%H:%M:%S").timestamp() + (float("0." + frac[:6]) if frac else 0.0)
lo, hi = t(start) - 1.0, t(end) + 2.0
for line in sys.stdin:
    try:
        d = json.loads(line)
    except ValueError:
        continue
    if d.get("src") == addr and d.get("at") and lo <= t(d["at"]) <= hi:
        d["label"] = label; d["container"] = cont
        print(json.dumps(d, sort_keys=True))
' "$addr" "$start" "$at" "$label" "$cont" >> "$meta/egress-denied.jsonl" 2>/dev/null || true
  return 0
}

# --- self-check ------------------------------------------------------------------------------
# The probe script runs inside one sandbox-shaped container (the batch image, the batch network, --dns 0.0.0.1,
# the proxy environment, read-only, non-root). Every denial case must fail; every allowed case must establish
# its tunnel (CONNECT 200) — TLS is not required (the bats stub speaks plain HTTP), and no request carries a
# credential.
# shellcheck disable=SC2016
PROBE_SCRIPT='
set -u
P="$1" GW="$2" FIRST="$3"; shift 3
bad=0
pass() { echo "$1: PASS ${2:-}"; }
flunk() { echo "$1: FAIL ${2:-}"; bad=1; }
tunnel() { curl -sS -m 20 -p -x "$P" -o /dev/null -w "%{http_connect}" "$@" 2>/dev/null; }
must_deny_tunnel() { local c; c="$(tunnel "$2")"; if [ "$c" = 200 ]; then flunk "$1" "tunnel established ($2)"; else pass "$1" "connect ${c:-none} ($2)"; fi; }
must_fail() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then flunk "$n" "succeeded: $*"; else pass "$n" "failed as required"; fi; }
tcp_open() { python3 -I -c "import socket, sys; socket.create_connection((sys.argv[1], int(sys.argv[2])), timeout=8)" "$1" "$2"; }
http_denied() { local c; c="$(curl -sS -m 20 -x "$P" -o /dev/null -w "%{http_code}" "$2" 2>/dev/null)"
  case "$c" in 2*|3*) flunk "$1" "HTTP $c ($2)" ;; *) pass "$1" "HTTP ${c:-none} ($2)" ;; esac; }
echo "address: $(hostname -i 2>/dev/null | awk "{print \$1}")"
for h in "$@"; do c="$(tunnel "https://$h/")"; if [ "$c" = 200 ]; then pass "allow $h" "connect 200"; else flunk "allow $h" "connect ${c:-none}"; fi; done
for h in github.com raw.githubusercontent.com gitlab.com api.github.com codeload.github.com objects.githubusercontent.com; do
  must_deny_tunnel "deny $h" "https://$h/"
done
must_fail "deny git ls-remote github.com" timeout 40 git ls-remote https://github.com/0xHoneyJar/loa HEAD
must_fail "deny git ls-remote raw.githubusercontent.com" timeout 40 git ls-remote https://raw.githubusercontent.com/0xHoneyJar/loa HEAD
must_fail "deny git ls-remote gitlab.com" timeout 40 git ls-remote https://gitlab.com/gitlab-org/gitlab.git HEAD
must_deny_tunnel "deny direct IPv4 via proxy" "https://1.1.1.1/"
must_deny_tunnel "deny direct IPv6 via proxy" "https://[2606:4700:4700::1111]/"
must_fail "deny direct IPv4 without proxy" curl -sS -m 10 --noproxy "*" https://1.1.1.1/
must_fail "deny direct IPv6 without proxy" curl -sS -m 10 -6 --noproxy "*" "https://[2606:4700:4700::1111]/"
must_fail "deny github.com without proxy" curl -sS -m 10 --noproxy "*" https://github.com/
must_deny_tunnel "deny CONNECT allowlisted host port 22" "https://$FIRST:22/"
must_deny_tunnel "deny CONNECT allowlisted host port 80" "https://$FIRST:80/"
http_denied "deny plain HTTP github.com" "http://github.com/"
http_denied "deny plain HTTP allowlisted host port 80" "http://$FIRST/"
must_deny_tunnel "deny metadata via proxy" "https://169.254.169.254/"
must_fail "deny metadata without proxy" curl -sS -m 10 --noproxy "*" http://169.254.169.254/latest/meta-data/
must_deny_tunnel "deny host gateway via proxy" "https://$GW/"
must_fail "deny host gateway 80 without proxy" curl -sS -m 10 --noproxy "*" "http://$GW/"
must_fail "deny host gateway 443 without proxy" curl -sS -m 10 --noproxy "*" "https://$GW/"
must_fail "deny host gateway 22 without proxy" tcp_open "$GW" 22
for u in "https://GITHUB.COM/" "https://github.com./" "https://16843009/" "https://0x01010101/" "https://0177.0.0.1/" "https://[::ffff:1.1.1.1]/" "https://github.com%2e/"; do
  must_deny_tunnel "deny encoding $u" "$u"
done
must_fail "deny resolver lookup github.com" getent hosts github.com
must_fail "deny external DNS udp 8.8.8.8" python3 -I -c "import socket; s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(5); s.sendto(bytes.fromhex(\"1234010000010000000000000667697468756203636f6d0000010001\"), (\"8.8.8.8\", 53)); s.recv(512)"
must_fail "deny external DNS tcp 1.1.1.1" tcp_open 1.1.1.1 53
must_fail "deny misconfigured proxy port" curl -sS -m 10 -x "${P%:*}:9" "https://$FIRST/"
must_fail "deny misconfigured proxy host" curl -sS -m 10 -x "http://loa-proxy-absent.invalid:8888" "https://$FIRST/"
must_fail "deny no proxy at all" env -u HTTPS_PROXY -u https_proxy -u HTTP_PROXY -u http_proxy curl -sS -m 10 "https://$FIRST/"
exit $bad
'

cmd_self_check() {
  local batch="${1:-}" image="" log="" probes=()
  [[ -n "$batch" ]] || die "usage: egress-proxy.sh self-check <batch> --image IMG [--log F] [--probe-host H]..."
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --image) image="${2:-}"; shift 2 ;;
      --log) log="${2:-}"; shift 2 ;;
      --probe-host) [[ "${2:-}" =~ $HOST_RE ]] || die "--probe-host must be a lower-case hostname"; probes+=("$2"); shift 2 ;;
      --docker-bin) DOCKER_BIN="${2:-}"; shift 2 ;;
      *) die "self-check: unknown option $1" ;;
    esac
  done
  [[ -n "$image" ]] || die "self-check: --image IMG is required (the batch's sandbox image)"
  names "$batch"
  exists_container "$PROXY" || die "self-check: sidecar $PROXY is not running (egress-proxy.sh up first)"
  if [[ ${#probes[@]} -eq 0 ]]; then
    local env_allow
    env_allow="$(dk inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$PROXY" | sed -n 's/^LOA_EGRESS_ALLOWLIST=//p')"
    read -r -a probes <<<"$env_allow"
  fi
  [[ ${#probes[@]} -gt 0 ]] || die "self-check: no probe host"
  local gw purl="http://$PROXY:$PROXY_PORT" out rc=0 t0
  gw="$(dk network inspect -f '{{range .IPAM.Config}}{{.Gateway}}{{end}}' "$NET" 2>/dev/null || true)"
  [[ -n "$gw" ]] || gw="$(dk network inspect -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' "$NET" | sed 's|\.[0-9]*/.*|.1|')"
  t0="$(now_iso)"
  out="$(dk run --rm --network "$NET" --dns 0.0.0.1 --user "$(id -u):$(id -g)" --read-only --tmpfs /tmp:rw,size=64m \
          --pids-limit 256 --memory 1g -e "HTTPS_PROXY=$purl" -e "https_proxy=$purl" -e "HTTP_PROXY=$purl" \
          -e "http_proxy=$purl" -e NO_PROXY= -e no_proxy= -e HOME=/tmp -e GIT_TERMINAL_PROMPT=0 \
          "$image" bash -c "$PROBE_SCRIPT" probe "$purl" "$gw" "${probes[0]}" "${probes[@]}" 2>&1)" || rc=$?
  local addr
  addr="$(sed -n 's/^address: //p' <<<"$out" | head -1)"
  out="$(grep -v '^address: ' <<<"$out")"
  # attribution: the probe's denied tunnels are in the sidecar's denials under the probe's address
  local att
  att="$(dk logs --timestamps "$PROXY" 2>&1 | parse_denials | jq -r --arg a "$addr" --arg t "$t0" \
    'select(.src == $a and .at >= $t) | .host' | sort -u | tr '\n' ' ')"
  local h miss=""
  for h in github.com raw.githubusercontent.com gitlab.com 1.1.1.1; do [[ " $att " == *" $h "* ]] || miss="$miss $h"; done
  if [[ -n "$addr" && -z "$miss" ]]; then out="$out"$'\n'"denial attribution: PASS source $addr: ${att% }"
  else out="$out"$'\n'"denial attribution: FAIL source '${addr:-unknown}' missing:${miss:- none} (attributed: ${att:-none})"; rc=1; fi
  # the sidecar's netfilter: default DROP and every private range rejected (the rebinding and gateway defence)
  local rules6 rules4 n rmiss=""
  rules4="$(dk exec "$PROXY" iptables -S OUTPUT 2>&1 || true)"
  rules6="$(dk exec "$PROXY" ip6tables -S OUTPUT 2>&1 || true)"
  grep -qx -- '-P OUTPUT DROP' <<<"$rules4" || rmiss="$rmiss ipv4-policy"
  grep -qx -- '-P OUTPUT DROP' <<<"$rules6" || rmiss="$rmiss ipv6-policy"
  for n in 10.0.0.0/8 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10; do
    grep -q -- "-A OUTPUT -d $n -j REJECT" <<<"$rules4" || rmiss="$rmiss $n"
  done
  if [[ -z "$rmiss" ]]; then out="$out"$'\n'"sidecar netfilter: PASS default DROP, private/loopback/link-local/CGNAT rejected, tcp 443 only"
  else out="$out"$'\n'"sidecar netfilter: FAIL missing:$rmiss"; rc=1; fi
  grep -q ': FAIL' <<<"$out" && rc=1
  if [[ -n "$log" ]]; then mkdir -p "$(dirname "$log")"; printf '%s\n' "$out" > "$log"; else printf '%s\n' "$out"; fi
  [[ $rc -eq 0 ]] && return 0
  [[ -n "$log" ]] && grep ': FAIL' "$log" >&2
  return 1
}

# --- dispatch ------------------------------------------------------------------------------
sub="${1:-}"; [[ $# -gt 0 ]] && shift
case "$sub" in
  allowlist) cmd_allowlist "$@" ;;
  up) cmd_up "$@" ;;
  down) cmd_down "$@" ;;
  self-check) cmd_self_check "$@" ;;
  denials) cmd_denials "$@" ;;
  record-address) cmd_record_address "$@" ;;
  -h|--help|help) sed -n '2,/^# =====/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) die "usage: egress-proxy.sh allowlist|up|down|self-check|denials|record-address … (see --help)" ;;
esac
