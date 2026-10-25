#!/usr/bin/env bats
# =============================================================================
# egress-proxy.bats — cycle-133 FR-9 (SDD C-9, § 7.3; D-2.5 DEC-0854; beads bd-ijxuk): the egress block of an
# ablation batch (evals/harness/lib/egress-proxy.sh, evals/harness/Dockerfile.proxy).
#
# RELEASE GATE: the container cases (EGR-*) may never appear in tests/QUARANTINE.tsv. They run real containers
# on the local Docker daemon — the sidecar image loa-egress-proxy:259 (built here from Dockerfile.proxy when
# absent), a sandbox-shaped probe image ($LOA_EGRESS_SANDBOX_IMAGE, else loa-ablation:259, else loa-ablation:258,
# else a minimal debian probe image built here) and a local stub endpoint (python3 http.server on 443/8443/80 of
# a private network, let through the private-range rule by the bats-only --test-allow-addr). No model call, no
# credential. Every sandbox-shaped container runs, as the launchers run a phase, in the network namespace of a
# guard (egress-proxy.sh guard; KF-058: the --internal network's gateway is the host and still answers).
# Without a usable Docker daemon the EGR cases SKIP with the reason — unless LOA_EGRESS_GATE=1 (the
# lead's release-gate run), where they FAIL. The EP-* cases use a stub docker and run everywhere.
# Logs: $LOA_EGRESS_LOG_DIR (default $BATS_RUN_TMPDIR/egress-logs): proxy.log, denied.jsonl, self-check.log.
#
#   LOA_EGRESS_GATE=1 LOA_EGRESS_LOG_DIR=<dir> npx --no-install bats evals/tests/egress-proxy.bats
# =============================================================================

setup_file() {
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  export REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  export EPX="$REPO_ROOT/evals/harness/lib/egress-proxy.sh"
  export LOGDIR="${LOA_EGRESS_LOG_DIR:-$BATS_RUN_TMPDIR/egress-logs}"
  mkdir -p "$LOGDIR"
  export B="egt$$" EGRESS_READY=0 EGRESS_WHY=""
  export NET="loa-egress-$B" PROXY="loa-proxy-$B" XNET="loa-egt-$B-x" STUB="loa-egt-$B-stub"
  export P="http://loa-proxy-$B:8888" PIMG="loa-egress-proxy:259"
  if ! docker info >/dev/null 2>&1; then EGRESS_WHY="docker daemon unavailable"; return 0; fi
  if ! docker image inspect "$PIMG" >/dev/null 2>&1; then
    docker build -q -t "$PIMG" - < "$REPO_ROOT/evals/harness/Dockerfile.proxy" > "$LOGDIR/proxy-build.log" 2>&1 \
      || { EGRESS_WHY="the proxy image did not build (see $LOGDIR/proxy-build.log)"; return 0; }
  fi
  local i
  SBX=""
  for i in "${LOA_EGRESS_SANDBOX_IMAGE:-}" loa-ablation:259 loa-ablation:258; do
    [[ -n "$i" ]] && docker image inspect "$i" >/dev/null 2>&1 && { SBX="$i"; break; }
  done
  if [[ -z "$SBX" ]]; then
    SBX="loa-egress-probe:test"
    printf '%s\n' 'FROM debian:bookworm-slim' \
      'RUN apt-get update && apt-get install -y --no-install-recommends curl git python3 ca-certificates && rm -rf /var/lib/apt/lists/*' \
      | docker build -q -t "$SBX" - > "$LOGDIR/probe-build.log" 2>&1 \
      || { EGRESS_WHY="no sandbox image and the probe image did not build (see $LOGDIR/probe-build.log)"; return 0; }
  fi
  export SBX
  echo "sandbox image: $SBX ($(docker image inspect -f '{{.Id}}' "$SBX"))" > "$LOGDIR/images.txt"
  echo "proxy image: $PIMG ($(docker image inspect -f '{{.Id}}' "$PIMG"))" >> "$LOGDIR/images.txt"

  # the external side: a private network with the stub endpoint (443 and 8443 serve, /redir answers 302 to github.com)
  docker network create --label "loa.egress.batch=$B" "$XNET" >/dev/null || { EGRESS_WHY="network create failed"; return 0; }
  docker run -d --name "$STUB" --network "$XNET" --label "loa.egress.batch=$B" --user 0 "$SBX" python3 -I -c '
import http.server, socketserver, threading
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(s):
        if s.path.startswith("/redir"):
            s.send_response(302); s.send_header("Location", "https://github.com/0xHoneyJar/loa"); s.end_headers(); return
        s.send_response(200); s.end_headers(); s.wfile.write(b"stub-ok\n")
    def log_message(s, *a): pass
class S(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
for port in (8443, 80):
    threading.Thread(target=S(("0.0.0.0", port), H).serve_forever, daemon=True).start()
S(("0.0.0.0", 443), H).serve_forever()' >/dev/null || { EGRESS_WHY="stub endpoint did not start"; return 0; }
  export STUB_IP XGW
  for i in $(seq 1 50); do
    STUB_IP="$(docker inspect -f "{{with index .NetworkSettings.Networks \"$XNET\"}}{{.IPAddress}}{{end}}" "$STUB" 2>/dev/null || true)"
    [[ -n "$STUB_IP" ]] && break; sleep 0.2
  done
  XGW="$(docker network inspect -f '{{range .IPAM.Config}}{{.Gateway}}{{end}}' "$XNET")"
  [[ -n "$STUB_IP" && -n "$XGW" ]] || { EGRESS_WHY="stub address unknown"; return 0; }
  # the allowlist: the stub, and four names that resolve (or rebind) to forbidden addresses
  printf '%s\n' api.stub.test rebind-gw.stub.test rebind-loop.stub.test rebind-meta.stub.test rebind-priv.stub.test > "$LOGDIR/allowlist"
  LOA_EGRESS_TEST_MODE=1 "$EPX" up "$B" "$LOGDIR/allowlist" --image "$PIMG" --external-network "$XNET" \
    --test-allow-addr "$STUB_IP" --test-add-host "api.stub.test:$STUB_IP" --test-add-host "rebind-gw.stub.test:$XGW" \
    --test-add-host "rebind-loop.stub.test:127.0.0.1" --test-add-host "rebind-meta.stub.test:169.254.169.254" \
    --test-add-host "rebind-priv.stub.test:10.255.255.1" > "$LOGDIR/up.json" 2> "$LOGDIR/up.err" \
    || { EGRESS_WHY="egress-proxy.sh up failed: $(tail -3 "$LOGDIR/up.err" | tr '\n' ' ')"; return 0; }
  export IGW G="loa-egt-$B-guard"
  IGW="$(docker network inspect -f '{{range .IPAM.Config}}{{.Gateway}}{{end}}' "$NET")"
  "$EPX" guard "$B" "$G" > "$LOGDIR/guard.out" 2> "$LOGDIR/guard.err" \
    || { EGRESS_WHY="egress-proxy.sh guard failed: $(tail -3 "$LOGDIR/guard.err" | tr '\n' ' ')"; return 0; }
  EGRESS_READY=1
}

teardown_file() {
  [[ -n "${B:-}" ]] || return 0
  if docker info >/dev/null 2>&1; then
    "$EPX" down "$B" --log-dir "$LOGDIR" >/dev/null 2>&1 || true
    docker rm -f "$STUB" >/dev/null 2>&1 || true
    docker rm -f "loa-egt-$B-watch" "loa-egt-$B-watch-guard" "loa-egt-$B-guard" >/dev/null 2>&1 || true
    docker network rm "$XNET" >/dev/null 2>&1 || true
  fi
}

setup() {
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/egp.XXXXXX")"
}

teardown() {
  [[ -f "$T/gwl.pid" ]] && { kill "$(cat "$T/gwl.pid")" 2>/dev/null || true; }
  find "$T" -mindepth 1 -delete 2>/dev/null || true
  rmdir "$T" 2>/dev/null || true
}

need_block() {
  [[ "$EGRESS_READY" == 1 ]] && return 0
  if [[ "${LOA_EGRESS_GATE:-}" == 1 ]]; then
    echo "release gate: the egress block is not available: $EGRESS_WHY" >&2; return 1
  fi
  skip "egress block unavailable ($EGRESS_WHY); the release-gate run uses LOA_EGRESS_GATE=1 on a docker host"
}

# sbx <script> [args…] — one sandbox-shaped container in the guard's namespace (as pipeline-run.sh runs a phase)
sbx() {
  local s="$1"; shift
  docker run --rm --network "container:$G" --user "$(id -u):$(id -g)" --read-only --tmpfs /tmp:rw,size=64m \
    -e "HTTPS_PROXY=$P" -e "https_proxy=$P" -e "HTTP_PROXY=$P" -e "http_proxy=$P" -e NO_PROXY= -e no_proxy= \
    -e HOME=/tmp -e GIT_TERMINAL_PROMPT=0 "$SBX" bash -c "$s" probe "$@"
}
# the CONNECT status the proxy answers for <url> (curl's %{http_connect}; 000 = no tunnel)
tunnel() { sbx 'curl -sS -m 20 -p -x "$1" -o /dev/null -w "%{http_connect}" "$2" 2>/dev/null; true' "$P" "$1"; }
log_case() { printf '%s: %s\n' "$BATS_TEST_DESCRIPTION" "$*" >> "$LOGDIR/cases.log"; }

# --- stub docker for the EP cases --------------------------------------------------------------
stub_docker() {  # a docker stand-in: inspect → $STUB_ADDR; logs → $STUB_LOG_FILE; anything else exit 0
  cat > "$T/docker" <<'SH'
#!/usr/bin/env bash
case "$1" in
  container) exit 0 ;;
  inspect) [[ "$*" == *IPAddress* ]] && echo "${STUB_ADDR:-}"; exit 0 ;;
  logs) cat "${STUB_LOG_FILE:-/dev/null}"; exit 0 ;;
  image) [[ -n "${STUB_NO_IMAGE:-}" ]] && exit 1
         if [[ "$*" == *org.loa.egress.guard* ]]; then [[ -z "${STUB_NO_GUARD:-}" ]] && echo 1; exit 0; fi
         echo sha256:feed; exit 0 ;;
  *) exit 0 ;;
esac
SH
  chmod +x "$T/docker"
}

# =============================================================================
# EP — the library without containers
# =============================================================================

@test "EP-1 allowlist: generated from every provider's egress_hosts[] — model endpoints, auth and token-refresh hosts, {region} expanded, sorted, no repository host" {
  run "$EPX" allowlist
  [ "$status" -eq 0 ]
  for h in api.anthropic.com api.openai.com auth.openai.com chatgpt.com generativelanguage.googleapis.com \
           oauth2.googleapis.com bedrock-runtime.us-east-1.amazonaws.com sts.amazonaws.com sts.us-east-1.amazonaws.com; do
    grep -qx "$h" <<<"$output"
  done
  ! grep -qE 'github|gitlab|\{region\}' <<<"$output"
  [ "$output" = "$(sort -u <<<"$output")" ]
  run "$EPX" allowlist --providers bedrock --region eu-west-1
  [ "$status" -eq 0 ]
  grep -qx bedrock-runtime.eu-west-1.amazonaws.com <<<"$output"
  grep -qx bedrock-runtime.us-east-1.amazonaws.com <<<"$output"
  ! grep -q anthropic <<<"$output"
}

@test "EP-2 allowlist refuses an IP literal, a wildcard, an upper-case name, a non-list and an empty result (exit 2)" {
  for bad in '"1.2.3.4"' '"*.github.com"' '"API.ANTHROPIC.COM"' '"localhost"'; do
    printf 'providers:\n  p:\n    egress_hosts: [%s]\n' "$bad" > "$T/mc.yaml"
    run "$EPX" allowlist --model-config "$T/mc.yaml"
    [ "$status" -eq 2 ]
    grep -q 'not a lower-case hostname' <<<"$output"
  done
  printf 'providers:\n  p:\n    egress_hosts: api.x.com\n' > "$T/mc.yaml"
  run "$EPX" allowlist --model-config "$T/mc.yaml"
  [ "$status" -eq 2 ]; grep -q 'must be a list' <<<"$output"
  printf 'providers:\n  p:\n    endpoint: x\n' > "$T/mc.yaml"
  run "$EPX" allowlist --model-config "$T/mc.yaml"
  [ "$status" -eq 2 ]; grep -q 'no egress_hosts' <<<"$output"
}

@test "EP-3 up refuses before any docker write: an empty allowlist, a bad entry, the test-only options outside bats test mode, an existing block" {
  stub_docker
  : > "$T/empty"
  run "$EPX" up b1 "$T/empty" --docker-bin "$T/docker"
  [ "$status" -eq 2 ]; grep -q 'is empty' <<<"$output"
  printf '%s\n' api.x.com 10.0.0.1 > "$T/bad"
  run "$EPX" up b1 "$T/bad" --docker-bin "$T/docker"
  [ "$status" -eq 2 ]; grep -q "'10.0.0.1' is not a lower-case hostname" <<<"$output"
  printf '%s\n' api.x.com > "$T/ok"
  LOA_EGRESS_TEST_MODE=0 run "$EPX" up b1 "$T/ok" --test-allow-addr 10.0.0.2 --docker-bin "$T/docker"
  [ "$status" -eq 2 ]; grep -q 'test-only' <<<"$output"
  run env -u BATS_TEST_FILENAME LOA_EGRESS_TEST_MODE=1 "$EPX" up b1 "$T/ok" --test-add-host a.b.test:10.0.0.2 --docker-bin "$T/docker"
  [ "$status" -eq 2 ]; grep -q 'test-only' <<<"$output"
  # the stub says every container exists: the sidecar is already there
  run "$EPX" up b1 "$T/ok" --docker-bin "$T/docker"
  [ "$status" -eq 2 ]; grep -q 'already exists; remove it first: egress-proxy.sh down b1' <<<"$output"
  STUB_NO_IMAGE=1 run "$EPX" up b1 "$T/ok" --docker-bin "$T/docker"
  [ "$status" -eq 2 ]; grep -q 'docker build -t loa-egress-proxy:259' <<<"$output"
  # an image built before the guard existed (KF-058) is refused with the rebuild line
  STUB_NO_GUARD=1 run "$EPX" up b1 "$T/ok" --docker-bin "$T/docker"
  [ "$status" -eq 2 ]; grep -q 'has no sandbox guard (built before KF-058); rebuild it: docker build -t loa-egress-proxy:259' <<<"$output"
  run "$EPX" up 'b 1' "$T/ok" --docker-bin "$T/docker"
  [ "$status" -eq 2 ]
}

@test "EP-4 denials: tinyproxy's log becomes one JSON line per refused request with its source address; an established tunnel is not a denial" {
  stub_docker
  cat > "$T/proxy.log" <<'LOG'
2026-10-24T02:50:47.004000000Z CONNECT   Oct 24 02:50:47.004 [1]: Connect (file descriptor 4): 172.22.0.3
2026-10-24T02:50:47.004100000Z CONNECT   Oct 24 02:50:47.004 [1]: Request (file descriptor 4): CONNECT github.com:443 HTTP/1.1
2026-10-24T02:50:47.004200000Z NOTICE    Oct 24 02:50:47.004 [1]: Proxying refused on filtered domain "github.com"
2026-10-24T02:50:48.000000000Z CONNECT   Oct 24 02:50:48.000 [1]: Connect (file descriptor 5): 172.22.0.4
2026-10-24T02:50:48.000100000Z CONNECT   Oct 24 02:50:48.000 [1]: Request (file descriptor 5): CONNECT api.stub.test:443 HTTP/1.1
2026-10-24T02:50:48.000200000Z INFO      Oct 24 02:50:48.000 [1]: Established connection to host "api.stub.test" using file descriptor 6.
2026-10-24T02:50:49.000000000Z CONNECT   Oct 24 02:50:49.000 [1]: Connect (file descriptor 4): 172.22.0.3
2026-10-24T02:50:49.000100000Z CONNECT   Oct 24 02:50:49.000 [1]: Request (file descriptor 4): CONNECT api.stub.test:22 HTTP/1.1
2026-10-24T02:50:49.000200000Z INFO      Oct 24 02:50:49.000 [1]: Refused CONNECT method on port 22
2026-10-24T02:50:50.000000000Z CONNECT   Oct 24 02:50:50.000 [1]: Connect (file descriptor 4): 172.22.0.3
2026-10-24T02:50:50.000100000Z CONNECT   Oct 24 02:50:50.000 [1]: Request (file descriptor 4): CONNECT rebind-loop.stub.test:443 HTTP/1.1
2026-10-24T02:50:51.000200000Z ERROR     Oct 24 02:50:51.000 [1]: opensock: Could not establish a connection to rebind-loop.stub.test:443
LOG
  STUB_LOG_FILE="$T/proxy.log" run "$EPX" denials b1 --docker-bin "$T/docker"
  [ "$status" -eq 0 ]
  [ "$(wc -l <<<"$output")" -eq 3 ]
  [ "$(jq -sc '[.[] | "\(.src) \(.host):\(.port) \(.reason)"]' <<<"$output")" = \
    '["172.22.0.3 github.com:443 filtered","172.22.0.3 api.stub.test:22 connect_port","172.22.0.3 rebind-loop.stub.test:443 connect_failed"]' ]
  ! grep -q '172.22.0.4' <<<"$output"
}

@test "EP-5 record-address: start records the container's address in meta, end attributes that address's denials (and only its own, in its window) to egress-denied.jsonl with the label" {
  stub_docker
  cat > "$T/proxy.log" <<LOG
$(date -u +%Y-%m-%dT%H:%M:%S.%NZ) CONNECT   x [1]: Connect (file descriptor 4): 172.30.0.7
$(date -u +%Y-%m-%dT%H:%M:%S.%NZ) CONNECT   x [1]: Request (file descriptor 4): CONNECT github.com:443 HTTP/1.1
$(date -u +%Y-%m-%dT%H:%M:%S.%NZ) NOTICE    x [1]: Proxying refused on filtered domain "github.com"
$(date -u +%Y-%m-%dT%H:%M:%S.%NZ) CONNECT   x [1]: Connect (file descriptor 5): 172.30.0.9
$(date -u +%Y-%m-%dT%H:%M:%S.%NZ) CONNECT   x [1]: Request (file descriptor 5): CONNECT gitlab.com:443 HTTP/1.1
$(date -u +%Y-%m-%dT%H:%M:%S.%NZ) NOTICE    x [1]: Proxying refused on filtered domain "gitlab.com"
2020-01-01T00:00:00.000000000Z CONNECT   x [1]: Connect (file descriptor 6): 172.30.0.7
2020-01-01T00:00:00.100000000Z CONNECT   x [1]: Request (file descriptor 6): CONNECT old.example.com:443 HTTP/1.1
2020-01-01T00:00:00.200000000Z NOTICE    x [1]: Proxying refused on filtered domain "old.example.com"
LOG
  export STUB_LOG_FILE="$T/proxy.log" STUB_ADDR=172.30.0.7
  run "$EPX" record-address --network loa-egress-b1 --container c1 --label IMPLEMENT --meta "$T/meta" --event start --docker-bin "$T/docker"
  [ "$status" -eq 0 ]
  [ "$(jq -r '"\(.event) \(.label) \(.container) \(.network) \(.address)"' "$T/meta/egress-addr.jsonl")" = "start IMPLEMENT c1 loa-egress-b1 172.30.0.7" ]
  run "$EPX" record-address --network loa-egress-b1 --container c1 --label IMPLEMENT --meta "$T/meta" --event end --docker-bin "$T/docker"
  [ "$status" -eq 0 ]
  [ "$(jq -sc '[.[] | "\(.label) \(.container) \(.src) \(.host)"]' "$T/meta/egress-denied.jsonl")" = '["IMPLEMENT c1 172.30.0.7 github.com"]' ]
  # never fails its caller: a bad option or a docker error leaves exit 0
  run "$EPX" record-address --bogus x
  [ "$status" -eq 0 ]
  run "$EPX" record-address --network bridge --container c1 --meta "$T/meta" --event start --docker-bin "$T/docker"
  [ "$status" -eq 0 ]
}

@test "EP-6 the suite: every arm resolves to egress blocked (arms[].egress, else egress.arms.<id>, else egress.default, else blocked)" {
  run jq -r '. as $s | [.arms[] | .id as $a | (.egress // ($s.egress // {} | .arms // {})[$a] // ($s.egress // {}).default // "blocked")] | unique | join(",")' \
    <<<"$(yq -o=json '.' "$REPO_ROOT/evals/suites/ablation-2.0.yaml")"
  [ "$status" -eq 0 ]
  [ "$output" = blocked ]
  [ "$(yq -r '.egress.default' "$REPO_ROOT/evals/suites/ablation-2.0.yaml")" = blocked ]
  # every arm id is named in egress.arms (no arm relies on the fallback silently)
  [ "$(yq -o=json '.' "$REPO_ROOT/evals/suites/ablation-2.0.yaml" | jq -r '[.arms[].id] - (.egress.arms | keys) | length')" = 0 ]
}

# the proxy's base task allowance: the tasks tinyproxy runs besides one thread per client (C-5, D-2.2, FR-6)
# observed: pids.current = 2 at idle (4 /proc entries) in loa-egress-proxy:259 on 2026-10-25 by the lead (docker exec cat /sys/fs/cgroup/pids.current); derivation: idle 2 + tinyproxy accept/log threads under load + margin → 16 (conservative; a concurrent-load measurement is out of scope, sdd.md § 11.G gpt IMP-012)
BASE_ALLOWANCE=16

# proxy_pids_limit — the --pids-limit of the proxy sidecar's `run` array in the launcher (one value, or the case fails)
proxy_pids_limit() {
  awk '/local -a run=\(run -d --name "\$PROXY"/ { on = 1 } on { print } on && /\)$/ { exit }' "$EPX" \
    | grep -oE -- '--pids-limit [0-9]+' | awk '{ print $2 }'
}
# dockerfile_run_pids_limit — the --pids-limit of the documented `Run (lib/egress-proxy.sh up does this):` line
dockerfile_run_pids_limit() {
  awk '/^# Run \(lib\/egress-proxy.sh up does this\):/ { on = 1; next } on && /^#   docker network connect/ { exit } on { print }' \
    "$REPO_ROOT/evals/harness/Dockerfile.proxy" | grep -oE -- '--pids-limit [0-9]+' | awk '{ print $2 }'
}

@test "EP-10 the proxy's pid limit covers its client ceiling: launcher --pids-limit >= MaxClients + BASE_ALLOWANCE (both read from the files), and the Dockerfile's documented run line names the same limit" {
  local lim doc maxc
  lim="$(proxy_pids_limit)"
  doc="$(dockerfile_run_pids_limit)"
  maxc="$(grep -E '^MaxClients [0-9]+$' "$REPO_ROOT/evals/harness/Dockerfile.proxy" | awk '{ print $2 }')"
  echo "launcher=$lim dockerfile_run_line=$doc MaxClients=$maxc BASE_ALLOWANCE=$BASE_ALLOWANCE"
  # exactly one value each (a second --pids-limit in the array, or a second MaxClients, is ambiguous)
  [[ "$lim" =~ ^[0-9]+$ ]]
  [[ "$doc" =~ ^[0-9]+$ ]]
  [[ "$maxc" =~ ^[0-9]+$ ]]
  [ "$lim" -ge $((maxc + BASE_ALLOWANCE)) ]
  [ "$doc" = "$lim" ]
  # the proxy image is started by one launch path (the guard and the probe carry their own limits)
  [ "$(grep -c -- '--name "\$PROXY"' "$EPX")" = 1 ]
}

# =============================================================================
# EGR — the release gate: real containers (never quarantined)
# =============================================================================

@test "EGR-1 an allowlisted endpoint succeeds through the proxy (the local stub: tunnel 200 and the body)" {
  need_block
  run sbx 'curl -sS -m 20 -p -x "$1" http://api.stub.test:443/' "$P"
  log_case "status $status output $output"
  [ "$status" -eq 0 ]
  [ "$output" = stub-ok ]
  run tunnel https://api.stub.test/
  [ "$output" = 200 ]
}

@test "EGR-2 github.com, raw.githubusercontent.com, gitlab.com (and api/codeload/objects.github) are refused by the proxy, and git ls-remote fails" {
  need_block
  local h
  for h in github.com raw.githubusercontent.com gitlab.com api.github.com codeload.github.com objects.githubusercontent.com; do
    run tunnel "https://$h/"
    log_case "$h connect $output"
    [ "$output" = 403 ]
  done
  run sbx 'timeout 60 git ls-remote https://github.com/0xHoneyJar/loa HEAD'
  log_case "git ls-remote github.com status $status"
  [ "$status" -ne 0 ]
  run sbx 'timeout 60 git ls-remote https://gitlab.com/gitlab-org/gitlab.git HEAD'
  [ "$status" -ne 0 ]
  run sbx 'timeout 60 git ls-remote https://raw.githubusercontent.com/0xHoneyJar/loa HEAD'
  [ "$status" -ne 0 ]
}

@test "EGR-3 a direct IP fails: IPv4 without the proxy, and an IPv4 literal (and its integer, hex and octal spellings) through it" {
  need_block
  run sbx 'curl -sS -m 10 --noproxy "*" https://1.1.1.1/'
  log_case "direct 1.1.1.1 status $status"
  [ "$status" -ne 0 ]
  run sbx 'python3 -I -c "import socket; socket.create_connection((\"140.82.112.3\", 443), timeout=8)"'
  [ "$status" -ne 0 ]
  local u
  for u in https://1.1.1.1/ https://140.82.112.3/ https://16843009/ https://0x01010101/ https://0177.0.0.1/; do
    run tunnel "$u"
    log_case "$u connect $output"
    [ "$output" != 200 ]
  done
}

@test "EGR-4 IPv6 fails: direct, and an IPv6 or IPv4-mapped literal through the proxy" {
  need_block
  run sbx 'curl -sS -m 10 -6 --noproxy "*" "https://[2606:4700:4700::1111]/"'
  log_case "direct v6 status $status"
  [ "$status" -ne 0 ]
  local u
  for u in "https://[2606:4700:4700::1111]/" "https://[::ffff:1.1.1.1]/" "https://[::1]/"; do
    run tunnel "$u"
    log_case "$u connect $output"
    [ "$output" != 200 ]
  done
}

@test "EGR-5 a redirect from an allowlisted endpoint to a non-allowlisted host fails: the next hop is a new CONNECT, refused" {
  need_block
  run sbx 'curl -sS -m 30 -p -x "$1" -L -o /dev/null -w "%{http_code} %{num_redirects} %{url_effective}\n" http://api.stub.test:443/redir' "$P"
  log_case "status $status output $output"
  [ "$status" -ne 0 ]
  # the first hop was served (302 seen), the follow-up to github.com never got a tunnel
  run sbx 'curl -sS -m 30 -p -x "$1" -o /dev/null -w "%{http_code} %{redirect_url}" http://api.stub.test:443/redir' "$P"
  [ "$output" = "302 https://github.com/0xHoneyJar/loa" ]
}

@test "EGR-6 CONNECT to a non-allowlisted host, and to an allowlisted host on a port other than 443 (the stub listens on 8443 and 80), is refused; plain HTTP is refused" {
  need_block
  run tunnel https://example.com/
  log_case "example.com connect $output"
  [ "$output" = 403 ]
  run tunnel https://api.stub.test:8443/
  log_case "api.stub.test:8443 connect $output"
  [ "$output" = 403 ]
  run tunnel https://api.stub.test:80/
  [ "$output" = 403 ]
  run tunnel https://api.stub.test:22/
  [ "$output" = 403 ]
  run sbx 'curl -sS -m 20 -x "$1" -o /dev/null -w "%{http_code}" http://api.stub.test/ 2>/dev/null; true' "$P"
  log_case "plain http api.stub.test code $output"
  [[ "$output" != 2* && "$output" != 3* ]]
  run sbx 'curl -sS -m 20 -x "$1" -o /dev/null -w "%{http_code}" http://github.com/ 2>/dev/null; true' "$P"
  [[ "$output" != 2* && "$output" != 3* ]]
}

@test "EGR-7 external DNS fails: no resolver for outside names, UDP and TCP 53 to public resolvers unreachable" {
  need_block
  run sbx 'timeout 30 getent hosts github.com'
  log_case "getent github.com status $status output $output"
  [ "$status" -ne 0 ]
  run sbx 'timeout 30 python3 -I -c "import socket; s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(5); s.sendto(bytes.fromhex(\"1234010000010000000000000667697468756203636f6d0000010001\"), (\"8.8.8.8\", 53)); s.recv(512)"'
  [ "$status" -ne 0 ]
  run sbx 'python3 -I -c "import socket; socket.create_connection((\"1.1.1.1\", 53), timeout=8)"'
  [ "$status" -ne 0 ]
  # the proxy's own name still resolves (Docker's embedded DNS answers container names only)
  run sbx 'getent hosts "$1"' "loa-proxy-$B"
  [ "$status" -eq 0 ]
}

# unreached <host> <port> — inside a sandbox: exit 0 only when the connect is rejected IN the sandbox's own
# namespace (EHOSTUNREACH/ENETUNREACH/EACCES/EPERM from the guard's netfilter). A connect, a refusal (the host
# answered) or a timeout (something outside, e.g. a host firewall, dropped it) is a failure: the block must not
# depend on the host.
UNREACHED='python3 -I -c "
import errno, socket, sys
try:
    socket.create_connection((sys.argv[1], int(sys.argv[2])), timeout=6)
    print(\"connected\"); sys.exit(1)
except OSError as e:
    if e.errno in (errno.EHOSTUNREACH, errno.ENETUNREACH, errno.EACCES, errno.EPERM):
        print(\"rejected-in-namespace\"); sys.exit(0)
    print(\"reached-or-dropped-outside \" + (errno.errorcode.get(e.errno, str(e.errno)) if e.errno else type(e).__name__)); sys.exit(1)
" "$1" "$2"'

# gw_listener <port-file> <hits-file> <addr>… — a TCP listener on the host bound to each gateway address on one
# free high port (the host owns those addresses); every accepted peer is appended to <hits-file>. Prints the port
# to <port-file>, or nothing when no address can be bound (rootless docker).
gw_listener() {
  local pf="$1" hf="$2"; shift 2
  python3 -I -c '
import socket, sys, threading
pf, hf, addrs = sys.argv[1], sys.argv[2], sys.argv[3:]
socks, port = [], 0
for a in addrs:
    s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        s.bind((a, port))
    except OSError:
        continue
    port = s.getsockname()[1]; s.listen(16); socks.append(s)
if not socks:
    open(pf, "w").close(); sys.exit(0)
open(pf, "w").write("%d\n" % port)
def serve(s):
    while True:
        c, peer = s.accept()
        with open(hf, "a") as f: f.write("%s %s\n" % (s.getsockname()[0], peer[0]))
        c.close()
for s in socks[1:]: threading.Thread(target=serve, args=(s,), daemon=True).start()
serve(socks[0])' "$pf" "$hf" "$@" &
  echo $! > "$T/gwl.pid"
  local i; for i in $(seq 1 50); do [[ -e "$pf" ]] && return 0; sleep 0.1; done
}

@test "EGR-8 the host gateway is unreachable: both networks' gateways on 22, 80, 443 and a host listener bound on them are rejected in the sandbox's own namespace (deterministic on any host), and through the proxy (an IP literal, and an allowlisted name that resolves to it)" {
  need_block
  local gw port
  gw_listener "$T/gwl.port" "$T/gwl.hits" "$IGW" "$XGW"
  port="$(cat "$T/gwl.port" 2>/dev/null || true)"
  log_case "gateway listener port ${port:-none} on $IGW $XGW"
  if [[ -n "$port" ]]; then
    # positive control: the listener answers the host itself
    python3 -I -c 'import socket, sys; socket.create_connection((sys.argv[1], int(sys.argv[2])), timeout=4)' "$XGW" "$port" \
      || python3 -I -c 'import socket, sys; socket.create_connection((sys.argv[1], int(sys.argv[2])), timeout=4)' "$IGW" "$port"
  fi
  for gw in "$IGW" "$XGW"; do
    for p in 22 80 443 ${port:+"$port"}; do
      run sbx "$UNREACHED" "$gw" "$p"
      log_case "direct $gw:$p status $status $output"
      [ "$status" -eq 0 ]
      [ "$output" = rejected-in-namespace ]
    done
    run tunnel "https://$gw/"
    [ "$output" != 200 ]
  done
  if [[ -n "$port" ]]; then
    # the listener saw exactly one connection: the host's own control above, never the sandbox
    log_case "listener hits: $(tr '\n' ';' < "$T/gwl.hits" 2>/dev/null)"
    [ "$(wc -l < "$T/gwl.hits")" -eq 1 ]
  fi
  run tunnel https://rebind-gw.stub.test/
  log_case "rebind-gw ($XGW) connect $output"
  [ "$output" != 200 ]
  # the metadata address, direct and through the proxy
  run sbx "$UNREACHED" 169.254.169.254 80
  [ "$status" -eq 0 ]
  run tunnel https://169.254.169.254/
  [ "$output" != 200 ]
  # the stub itself and the sidecar's other ports are not reachable directly (only the proxy port)
  run sbx "$UNREACHED" "$STUB_IP" 443
  [ "$status" -eq 0 ]
  run sbx "$UNREACHED" "loa-proxy-$B" 22
  [ "$status" -eq 0 ]
  [[ -n "$port" ]] || skip "no gateway address could be bound on this host (rootless docker?): the listener probe did not run; 22/80/443 did"
}

@test "EGR-9 DNS rebinding: an allowlisted name that resolves to loopback, metadata, a private or the gateway address gets no tunnel (netfilter after resolution)" {
  need_block
  local h
  for h in rebind-loop.stub.test rebind-meta.stub.test rebind-priv.stub.test rebind-gw.stub.test; do
    run tunnel "https://$h/"
    log_case "$h connect $output"
    [ "$output" != 200 ]
  done
  run docker exec "$PROXY" iptables -S OUTPUT
  log_case "$(tr '\n' ';' <<<"$output")"
  grep -qx -- '-P OUTPUT DROP' <<<"$output"
  grep -q -- '-A OUTPUT -d 127.0.0.0/8 -j REJECT' <<<"$output"
  grep -q -- '-A OUTPUT -d 169.254.0.0/16 -j REJECT' <<<"$output"
  grep -q -- '-A OUTPUT -d 10.0.0.0/8 -j REJECT' <<<"$output"
  grep -q -- '-A OUTPUT -d 172.16.0.0/12 -j REJECT' <<<"$output"
  run docker exec "$PROXY" ip6tables -S OUTPUT
  grep -qx -- '-P OUTPUT DROP' <<<"$output"
}

@test "EGR-10 a misconfigured proxy fails closed: a wrong port, an absent proxy host, no proxy at all, the image's own default, an empty allowlist and a sidecar without NET_ADMIN" {
  need_block
  run sbx 'curl -sS -m 10 -x "${1%:*}:9" https://api.stub.test/' "$P"
  [ "$status" -ne 0 ]
  run sbx 'curl -sS -m 10 -x http://loa-proxy-absent.invalid:8888 https://api.stub.test/'
  [ "$status" -ne 0 ]
  run sbx 'env -u HTTPS_PROXY -u https_proxy -u HTTP_PROXY -u http_proxy curl -sS -m 10 https://api.stub.test/'
  [ "$status" -ne 0 ]
  # the sandbox image's environment alone (no -e): its proxy default never resolves
  run docker run --rm --network "container:$G" "$SBX" bash -c 'curl -sS -m 10 https://api.anthropic.com/'
  log_case "image default status $status"
  [ "$status" -ne 0 ]
  # the sidecar refuses to start without an allowlist, or without its netfilter rules (no NET_ADMIN)
  run docker run --rm -e LOA_EGRESS_ALLOWLIST= "$PIMG"
  [ "$status" -eq 2 ]; grep -q 'LOA_EGRESS_ALLOWLIST is empty' <<<"$output"
  run docker run --rm -e LOA_EGRESS_ALLOWLIST=1.2.3.4 "$PIMG"
  [ "$status" -eq 2 ]; grep -q 'IP literal' <<<"$output"
  run timeout 60 docker run --rm --cap-drop ALL -e LOA_EGRESS_ALLOWLIST=api.stub.test "$PIMG"
  log_case "no NET_ADMIN status $status"
  [ "$status" -ne 0 ]
  ! grep -q 'Starting main loop' <<<"$output"
}

@test "EGR-11 denials are attributed by source address: record-address (watch) of a named sandbox in its own guard writes the guard's address and exactly its denials into meta, then removes the guard" {
  need_block
  local c="loa-egt-$B-watch" m="$T/meta" g="loa-egt-$B-watch-guard"
  run "$EPX" guard "$B" "$g"
  [ "$status" -eq 0 ]; [ "$output" = "container:$g" ]
  LOA_EGRESS_ADDR_WAIT_S=30 "$EPX" record-address --network "$NET" --container "$c" --guard "$g" --label REVIEW --meta "$m" --event watch --max-s 120 &
  local wpid=$!
  sleep 1
  docker run --rm --name "$c" --network "container:$g" -e "HTTPS_PROXY=$P" "$SBX" bash -c \
    'sleep 2; for h in github.com gitlab.com raw.githubusercontent.com; do curl -sS -m 10 -p -x "$HTTPS_PROXY" -o /dev/null "https://$h/" 2>/dev/null; done; sleep 1; true'
  wait "$wpid"
  log_case "$(cat "$m/egress-addr.jsonl" "$m/egress-denied.jsonl" 2>&1 | tr '\n' ' ')"
  local addr
  addr="$(jq -r 'select(.event == "start") | .address' "$m/egress-addr.jsonl")"
  [[ "$addr" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
  [ "$(jq -r 'select(.event == "end") | .address' "$m/egress-addr.jsonl")" = "$addr" ]
  [ "$(jq -r 'select(.event == "start") | .guard' "$m/egress-addr.jsonl")" = "$g" ]
  # the watcher removed the guard once the sandbox was gone
  ! docker container inspect "$g" >/dev/null 2>&1
  [ "$(jq -sr '[.[] | select(.src == "'"$addr"'" and .label == "REVIEW" and .container == "'"$c"'") | .host] | sort | join(",")' "$m/egress-denied.jsonl")" \
    = "github.com,gitlab.com,raw.githubusercontent.com" ]
  [ "$(jq -sr '[.[] | select(.src != "'"$addr"'")] | length' "$m/egress-denied.jsonl")" = 0 ]
  # the batch-wide view carries the same source address
  run "$EPX" denials "$B"
  [ "$status" -eq 0 ]
  [ "$(jq -sr '[.[] | select(.src == "'"$addr"'")] | length' <<<"$output")" -ge 3 ]
}

@test "EGR-12 self-check passes on the block: the probe per allowlisted host and every denial case, attribution and the sidecar's rules (log kept)" {
  need_block
  run "$EPX" self-check "$B" --image "$SBX" --probe-host api.stub.test --log "$LOGDIR/self-check.log"
  log_case "status $status"
  cat "$LOGDIR/self-check.log" >&3 2>/dev/null || true
  [ "$status" -eq 0 ]
  ! grep -q ': FAIL' "$LOGDIR/self-check.log"
  grep -q '^allow api.stub.test: PASS' "$LOGDIR/self-check.log"
  grep -q '^denial attribution: PASS' "$LOGDIR/self-check.log"
  grep -q '^sidecar netfilter: PASS' "$LOGDIR/self-check.log"
  grep -q '^sandbox guard netfilter: PASS' "$LOGDIR/self-check.log"
  grep -q '^host gateway listener: PASS' "$LOGDIR/self-check.log"
  grep -q "^deny host gateway $IGW 22: PASS rejected in the namespace" "$LOGDIR/self-check.log"
  grep -q "^deny host gateway $XGW 22: PASS rejected in the namespace" "$LOGDIR/self-check.log"
  [ "$(grep -c ': PASS' "$LOGDIR/self-check.log")" -ge 40 ]
  # the check removes its own guard
  ! docker container inspect "loa-egress-$B-selfcheck" >/dev/null 2>&1
}

@test "EGR-13 the guard: a root sandbox in its namespace cannot change the rules or reach the gateway, the guard holds no capability after installing them, a stale guard is replaced, a foreign container is never taken over, and down removes the batch's guards" {
  need_block
  # root in the sandbox (default capabilities: no NET_ADMIN) cannot flush the guard's rules
  run docker run --rm --network "container:$G" --user 0 --entrypoint iptables "$PIMG" -F OUTPUT
  log_case "root flush status $status output $output"
  [ "$status" -ne 0 ]
  run docker run --rm --network "container:$G" --user 0 "$SBX" bash -c "$UNREACHED" probe "$IGW" 22
  [ "$status" -eq 0 ]; [ "$output" = rejected-in-namespace ]
  run docker exec "$G" iptables -S OUTPUT
  grep -qx -- '-P OUTPUT DROP' <<<"$output"
  grep -qx -- '-A OUTPUT -j REJECT --reject-with icmp-admin-prohibited' <<<"$output"
  # the guard's own process: nobody, no effective capability
  run docker exec "$G" sh -c 'cat /proc/1/cmdline | tr "\0" " "; echo; grep -E "^(Uid|CapEff):" /proc/1/status'
  log_case "guard pid 1 $(tr '\n' ';' <<<"$output")"
  grep -q '^sleep infinity' <<<"$output"
  grep -Eq '^Uid:[[:space:]]+65534[[:space:]]+65534' <<<"$output"
  grep -Eq '^CapEff:[[:space:]]+0+$' <<<"$output"
  # a stale guard of the batch is replaced (new container id); a foreign container of that name is refused
  local old new
  old="$(docker inspect -f '{{.Id}}' "$G")"
  run "$EPX" guard "$B" "$G"
  [ "$status" -eq 0 ]
  new="$(docker inspect -f '{{.Id}}' "$G")"
  [ "$old" != "$new" ]
  docker run -d --name "loa-egt-$B-foreign" --label "loa.egress.batch=$B" "$SBX" sleep 60 >/dev/null
  run "$EPX" guard "$B" "loa-egt-$B-foreign"
  docker rm -f "loa-egt-$B-foreign" >/dev/null 2>&1 || true
  [ "$status" -eq 2 ]; grep -q 'exists and is not a guard of batch' <<<"$output"
  # down sweeps every guard of the batch (a batch of its own, so the suite's block stays up)
  local b2="egt2$$"
  docker network create --internal --label "loa.egress.batch=$b2" "loa-egress-$b2" >/dev/null
  docker run -d --name "loa-proxy-$b2" --label "loa.egress.batch=$b2" --network "loa-egress-$b2" --entrypoint sleep "$PIMG" 300 >/dev/null
  docker run -d --name "loa-egt-$b2-g1" --label "loa.egress.batch=$b2" --label loa.egress.role=guard --network "loa-egress-$b2" --entrypoint sleep "$PIMG" 300 >/dev/null
  run "$EPX" down "$b2"
  log_case "down $b2 status $status output $output"
  [ "$status" -eq 0 ]
  ! docker container inspect "loa-egt-$b2-g1" >/dev/null 2>&1
  ! docker network inspect "loa-egress-$b2" >/dev/null 2>&1
}

# =============================================================================
# EP-7…EP-8 — the launchers join the block (stub docker; the wrapper records the argv, answers the egress
# inspections and the guard's start: `run -d` records guard-<pid>.argv, `logs` says the rules are installed)
# =============================================================================

wrap_docker() {  # wrap_docker <internal true|false> <proxy running true|false>
  mkdir -p "$T/dlog"
  cat > "$T/docker" <<EOF
#!/usr/bin/env bash
case "\$1" in
  network) [[ "\$2" == inspect ]] && { echo "$1"; exit 0; } ;;
  container) [[ "\$2" == inspect ]] && {
               case "\$*" in
                 *State.Running*) echo "$2" ;;
                 *Config.Image*) echo loa-egress-proxy:259 ;;
                 *org.loa.egress.guard*) echo "\${STUB_GUARD_LABEL-1}" ;;
                 *loa.egress.batch*) echo "guard \${LOA_EVAL_EGRESS_NETWORK#loa-egress-}" ;;
                 *loa.egress.role*) echo guard ;;
               esac; exit 0; } ;;
  logs) echo 'loa-egress-guard: installed; stub'; exit 0 ;;
  inspect) exit 1 ;;
  run) if [[ "\$2" == -d ]]; then printf '%s\0' "\$@" > "$T/dlog/guard-\$\$.argv"; echo stubguard; exit 0; fi
       if [[ "\${*: -2}" != "claude --version" ]]; then
         printf '%s\0' "\$@" > "$T/dlog/full-\$\$.argv"
         a=(); while [[ \$# -gt 0 ]]; do if [[ "\$1" == --dns ]]; then shift 2; else a+=("\$1"); shift; fi; done
         DOCKER_STUB_LOG="$T/dlog" DOCKER_STUB_CLAUDE="$T/claude" exec "$REPO_ROOT/evals/tests/fixtures/docker-stub.sh" "\${a[@]}"
       fi ;;
esac
DOCKER_STUB_LOG="$T/dlog" exec "$REPO_ROOT/evals/tests/fixtures/ablation-docker-stub.sh" "\$@"
EOF
  chmod +x "$T/docker"
}

@test "EP-7 blind-session.sh: with LOA_EVAL_EGRESS_NETWORK the container runs in its own guard's namespace (the guard on loa-egress-<batch> with --dns 0.0.0.1, the proxy environment the session sees); without it, bridge; both recorded in <out>/egress.json; a bad name is refused" {
  mkdir -p "$T/pk" "$T/log" "$T/tmp"
  printf '# hunks\nH01 src/a.sh 10-12\n' > "$T/pk/hunks.md"
  printf 'Label every hunk. Write the file to {{LABELS_PATH}}.\n' > "$T/prompt.md"
  export TMPDIR="$T/tmp" LOA_EVAL_WATCHDOG_POLL_S=0.1
  export LOA_EVAL_PRICING_JSON='{"m-test": {"input_per_mtok": 1, "output_per_mtok": 1}}'
  cat > "$T/claude" <<EOF
#!/usr/bin/env bash
env | LC_ALL=C sort > "$T/log/env-\$\$.txt"
printf '{"hunks": {}, "incidents": {}}\n' > labels.json
printf '%s\n' '{"type":"system","subtype":"init","session_id":"s1"}' '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.0}'
EOF
  chmod +x "$T/claude"
  wrap_docker true true
  LOA_EVAL_EGRESS_NETWORK=loa-egress-b7 run "$REPO_ROOT/evals/harness/blind-session.sh" --packets "$T/pk" --prompt "$T/prompt.md" \
    --model m-test --out "$T/out1" --docker-bin "$T/docker"
  echo "$output"
  local a g gname; a="$(tr '\0' '\n' < "$(ls "$T"/dlog/full-*.argv | head -1)")"
  g="$(tr '\0' '\n' < "$(ls "$T"/dlog/guard-*.argv | head -1)")"
  gname="$(grep -A1 -x -- '--name' <<<"$g" | tail -1)"
  [[ "$gname" == loa-blind-out1-*-guard-* ]]
  # the guard sits on the internal network, sinkholed, with the guard entrypoint; the session joins its namespace only
  grep -A1 -x -- '--network' <<<"$g" | tail -1 | grep -qx loa-egress-b7
  grep -A1 -x -- '--dns' <<<"$g" | tail -1 | grep -qx 0.0.0.1
  grep -A1 -x -- '--entrypoint' <<<"$g" | tail -1 | grep -qx /usr/local/bin/loa-egress-guard
  grep -qx 'LOA_EGRESS_PROXY=loa-proxy-b7' <<<"$g"
  grep -A1 -x -- '--network' <<<"$a" | tail -1 | grep -qx "container:$gname"
  [ "$(grep -cx -- '--network' <<<"$a")" -eq 1 ]
  ! grep -qx -- '--dns' <<<"$a"
  for k in HTTPS_PROXY https_proxy HTTP_PROXY http_proxy; do grep -qx -- "$k=http://loa-proxy-b7:8888" <<<"$a"; done
  grep -qx -- 'NO_PROXY=' <<<"$a"
  grep -qx 'HTTPS_PROXY=http://loa-proxy-b7:8888' "$(ls "$T"/log/env-*.txt | head -1)"
  grep -qx 'NO_PROXY=' "$(ls "$T"/log/env-*.txt | head -1)"
  [ "$(jq -c '[.egress, .network, .enforced, .dns, .proxy_url]' "$T/out1/egress.json")" = '["blocked","loa-egress-b7",true,"0.0.0.1","http://loa-proxy-b7:8888"]' ]
  [ "$(jq -r .guard "$T/out1/egress.json")" = "$gname" ]
  rm -f "$T"/dlog/full-*.argv "$T"/dlog/guard-*.argv "$T"/log/env-*.txt
  run "$REPO_ROOT/evals/harness/blind-session.sh" --packets "$T/pk" --prompt "$T/prompt.md" --model m-test --out "$T/out2" --docker-bin "$T/docker"
  a="$(tr '\0' '\n' < "$(ls "$T"/dlog/full-*.argv | head -1)")"
  grep -A1 -x -- '--network' <<<"$a" | tail -1 | grep -qx bridge
  ! grep -qx -- '--dns' <<<"$a"
  ! grep -q '^HTTPS_PROXY=' <<<"$a"
  ! ls "$T"/dlog/guard-*.argv >/dev/null 2>&1
  [ "$(jq -c '[.egress, .network, .enforced, .guard]' "$T/out2/egress.json")" = '["bridge","bridge",false,null]' ]
  LOA_EVAL_EGRESS_NETWORK='bridge' run "$REPO_ROOT/evals/harness/blind-session.sh" --packets "$T/pk" --prompt "$T/prompt.md" \
    --model m-test --out "$T/out3" --docker-bin "$T/docker"
  [ "$status" -eq 2 ]; grep -q 'is not loa-egress-<batch>' <<<"$output"
}

@test "EP-8 run-ablation.sh: a container batch with a blocked arm is refused without the block (REFUSED.txt names the repair), with a block that is not up or whose sidecar image has no guard; with it, MANIFEST egress records the arms, the network and enforced true; --dry-run records enforced false" {
  local FX="$REPO_ROOT/evals/tests/fixtures" RA="$REPO_ROOT/evals/harness/run-ablation.sh" i SHA
  mkdir -p "$T/bin" "$T/src/.claude" "$T/creds/.codex"
  printf '%s\n' '#!/usr/bin/env bash' 'echo "2.1.300 (Claude Code)"' > "$T/bin/claude"; chmod +x "$T/bin/claude"
  echo "# loa" > "$T/src/.claude/CLAUDE.loa.md"
  ( cd "$T/src" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -q -m src )
  SHA="$(git -C "$T/src" rev-parse HEAD)"
  for i in $(seq 1 36); do echo "self-check base task-$i: PASS hidden 1/1"; done > "$T/self-check.log"
  export PATH="$T/bin:$PATH" EVAL_CLAUDE_BIN="$T/bin/claude" LOA_ABLATION_SOURCE_TREE="$T/src" LOA_EVAL_CREDS_HOME="$T/creds"
  export LOA_ABLATION_RETRY_WAIT_S=0 LOA_ABLATION_POLL_S=0.2 STUB_LOG="$T/stub.log" STUB_GRADE_LOG="$T/grade.log"
  unset LOA_EGRESS_TEST_MODE LOA_EVAL_EGRESS_NETWORK
  ra_e() { run "$RA" --source-commit "$SHA" --results-root "$T/res" --self-check-log "$T/self-check.log" \
      --pipeline-bin "$FX/ablation-pipeline-stub.sh" --grade-bin "$FX/ablation-grade-stub.sh" --docker-bin "$T/docker" \
      --arms a0_bare,a1_full --tasks bugfix-v2-02 --trials-build 1 "$@"; }
  wrap_docker true true
  ra_e --batch e1
  echo "$output"
  [ "$status" -eq 2 ]
  grep -q 'arm(s) a0_bare,a1_full are egress: blocked and no egress block is named' "$T/res/e1/REFUSED.txt"
  grep -q 'egress-proxy.sh' "$T/res/e1/REFUSED.txt"
  [ ! -e "$T/stub.log" ]
  wrap_docker false true
  LOA_EVAL_EGRESS_NETWORK=loa-egress-e2 ra_e --batch e2
  [ "$status" -eq 2 ]; grep -q 'is not an internal docker network' "$T/res/e2/REFUSED.txt"
  wrap_docker true false
  LOA_EVAL_EGRESS_NETWORK=loa-egress-e3 ra_e --batch e3
  [ "$status" -eq 2 ]; grep -q 'sidecar loa-proxy-e3 is not running' "$T/res/e3/REFUSED.txt"
  # a sidecar from a proxy image built before the guard (KF-058) is refused with the rebuild line
  wrap_docker true true
  STUB_GUARD_LABEL= LOA_EVAL_EGRESS_NETWORK=loa-egress-e6 ra_e --batch e6
  [ "$status" -eq 2 ]; grep -q 'runs an image without the sandbox guard (built before KF-058); rebuild it' "$T/res/e6/REFUSED.txt"
  wrap_docker true true
  LOA_EVAL_EGRESS_NETWORK=loa-egress-e4 ra_e --batch e4 --dry-run
  [ "$status" -eq 0 ]
  [ "$(jq -c '.egress' "$T/res/e4/MANIFEST.json")" = '{"arms":{"a0_bare":"blocked","a1_full":"blocked"},"network":"loa-egress-e4","proxy":"loa-proxy-e4","enforced":true}' ]
  ra_e --batch e5 --dry-run
  [ "$status" -eq 0 ]
  [ "$(jq -c '.egress' "$T/res/e5/MANIFEST.json")" = '{"arms":{"a0_bare":"blocked","a1_full":"blocked"},"network":null,"proxy":null,"enforced":false}' ]
}

@test "EP-9 pipeline-run.sh: with LOA_EVAL_EGRESS_NETWORK every phase container runs in its own guard's namespace (one guard per container, unique names, the guard on loa-egress-<batch>); meta/egress.jsonl records network, guard and enforced; without it, bridge and no guard" {
  local FX="$REPO_ROOT/evals/tests/fixtures" H="$T/h/evals/harness" s
  mkdir -p "$H/lib" "$T/src/.claude/loa" "$T/src/.claude/adapters/loa_cheval/providers" "$T/home/.aws" "$T/home/.claude" \
           "$T/home/.codex" "$T/task/fx/src"
  cp "$REPO_ROOT/evals/harness/pipeline-run.sh" "$REPO_ROOT/evals/harness/fingerprint.sh" "$H/"
  cp -a "$REPO_ROOT/evals/harness/lib/phase-prompts" "$H/lib/"
  cp "$REPO_ROOT/evals/harness/lib/session-exec.sh" "$REPO_ROOT/evals/harness/lib/egress-proxy.sh" "$H/lib/"
  cp "$FX/mount-lib-stub.sh" "$H/lib/sandbox-mount.sh"
  for s in planning-sprints implementing-tasks reviewing-code auditing-security; do
    mkdir -p "$T/src/.claude/skills/$s"; printf -- '---\nname: %s\neffort: xhigh\n---\nbody\n' "$s" > "$T/src/.claude/skills/$s/SKILL.md"
  done
  echo loa > "$T/src/.claude/loa/CLAUDE.loa.md"
  : > "$T/src/.claude/adapters/loa_cheval/__init__.py"; : > "$T/src/.claude/adapters/loa_cheval/providers/__init__.py"
  ( cd "$T/src" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm init )
  echo "[default]" > "$T/home/.aws/config"; echo "{}" > "$T/home/.codex/auth.json"
  echo 'print(1)' > "$T/task/fx/src/app.py"; printf 'Make the app print two.\n' > "$T/task/TASK.md"
  printf '%s\n' 'id: bf-01' 'schema_version: 1' 'type: bug-fix' 'fixture: fx' 'criterion: "the app prints two"' \
    'test_command: ["python3", "-m", "pytest", "-q", "tests"]' > "$T/task/task.yaml"
  cat > "$T/claude" <<EOF
#!/usr/bin/env bash
export STUB_LOG_DIR="$T/log"
exec "$FX/claude-stub-pipeline.sh" "\$@"
EOF
  chmod +x "$T/claude"; mkdir -p "$T/log"
  wrap_docker true true
  export LOA_EVAL_WATCHDOG_POLL_S=0.1 LOA_EVAL_CREDS_HOME="$T/home"
  export LOA_EVAL_PRICING_JSON='{"global.anthropic.claude-opus-5-5":{"input_per_mtok":4000000,"output_per_mtok":20000000},"global.anthropic.claude-fable-5-1":{"input_per_mtok":10000000,"output_per_mtok":50000000}}'
  pr9() { run "$H/pipeline-run.sh" --task-yaml "$T/task/task.yaml" --arm a1_full --run-dir "$T/$1" --run-id "$1" --trial 1 \
      --source-tree "$T/src" --suite-file "$FX/ablation-runs/suite.yaml" --executor container --image loa-ablation:test \
      --docker-bin "$T/docker"; }
  LOA_EVAL_EGRESS_NETWORK=loa-egress-p9 pr9 run1
  echo "$output" | tail -5
  [ "$status" -eq 0 ]
  local f a g gname n=0 names=""
  for f in "$T"/dlog/full-*.argv; do
    a="$(tr '\0' '\n' < "$f")"
    gname="$(grep -A1 -x -- '--network' <<<"$a" | tail -1)"
    [[ "$gname" == container:loa-abl-run1-*-guard-* ]]
    ! grep -qx -- '--dns' <<<"$a"
    grep -qx 'HTTPS_PROXY=http://loa-proxy-p9:8888' <<<"$a"
    names="$names ${gname#container:}"; n=$((n + 1))
  done
  [ "$n" -ge 2 ]
  # one guard per container, each on the internal network with the guard entrypoint, every name distinct
  [ "$(ls "$T"/dlog/guard-*.argv | wc -l)" -eq "$n" ]
  [ "$(tr ' ' '\n' <<<"$names" | sed '/^$/d' | sort -u | wc -l)" -eq "$n" ]
  for f in "$T"/dlog/guard-*.argv; do
    g="$(tr '\0' '\n' < "$f")"
    grep -A1 -x -- '--network' <<<"$g" | tail -1 | grep -qx loa-egress-p9
    grep -A1 -x -- '--entrypoint' <<<"$g" | tail -1 | grep -qx /usr/local/bin/loa-egress-guard
    [[ " $names " == *" $(grep -A1 -x -- '--name' <<<"$g" | tail -1) "* ]]
  done
  [ "$(jq -sc '[.[] | [.egress, .network, .enforced, .dns, .proxy_url, (.guard | startswith("loa-abl-run1-"))]] | unique' "$T/run1/meta/egress.jsonl")" \
    = '[["blocked","loa-egress-p9",true,"0.0.0.1","http://loa-proxy-p9:8888",true]]' ]
  rm -f "$T"/dlog/full-*.argv "$T"/dlog/guard-*.argv
  pr9 run2
  [ "$status" -eq 0 ]
  ! ls "$T"/dlog/guard-*.argv >/dev/null 2>&1
  a="$(tr '\0' '\n' < "$(ls "$T"/dlog/full-*.argv | head -1)")"
  grep -A1 -x -- '--network' <<<"$a" | tail -1 | grep -qx bridge
  [ "$(jq -sc '[.[] | [.egress, .network, .enforced, .guard]] | unique' "$T/run2/meta/egress.jsonl")" = '[["blocked","bridge",false,null]]' ]
}
