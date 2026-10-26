#!/usr/bin/env bash
# docker-stub.sh — stand-in for the docker 26.1 CLI in evals/tests/pipeline-run.bats.
#   docker image inspect --format … <img>  prints $DOCKER_STUB_IMAGE_ID (default
#                                         sha256:feedface…); exit 1 when
#                                         DOCKER_STUB_NO_IMAGE=1
#   docker kill … / docker rm …           records the argv line to $DOCKER_STUB_LOG/kill.log
#                                         or rm.log and exits 0
#   (each -v spec and, for the non-/workspace mounts, every path under its source go
#    to $DOCKER_STUB_LOG/run-<n>.mounts; a mount nested under /workspace — the runtime
#    node_modules mounts, `-v <src>:/workspace/<rel>:ro` — is emulated for the command's
#    duration by a symlink <ws>/<rel> -> <src> in place of the empty mountpoint directory
#    the harness made, and the directory is put back afterwards)
#   docker run <flags> <image> <cmd…>     records argv (NUL-separated) to
#                                         $DOCKER_STUB_LOG/run-<n>.argv, then runs
#                                         <cmd…> on the host: /workspace in args and
#                                         env values maps to the -v source of
#                                         every mount (/workspace, /home/evaluser),
#                                         the environment is exactly the -e set
#                                         (bare `-e KEY` takes the client's value),
#                                         the command word `claude` maps to
#                                         $DOCKER_STUB_CLAUDE; when $DOCKER_STUB_PATH is
#                                         set and no -e PATH was given, PATH=<it> joins
#                                         the environment (ablation-grade.bats: the
#                                         image's python3/bats stand-ins); with
#                                         DOCKER_STUB_HANG=1 a leading `timeout [opts] T`
#                                         is dropped from <cmd…> (a container whose
#                                         deadline never fires: the grader's own client
#                                         deadline and docker kill/rm -f must act)
set -euo pipefail
log="${DOCKER_STUB_LOG:-/dev/null}"
case "${1:-}" in
  --version) echo "Docker version 26.1.5 (stub)"; exit 0 ;;
  image)
    [[ "${DOCKER_STUB_NO_IMAGE:-0}" == 1 ]] && { echo "Error: No such image" >&2; exit 1; }
    echo "${DOCKER_STUB_IMAGE_ID:-sha256:feedfacefeedfacefeedfacefeedfacefeedfacefeedfacefeedfacefeedface}"; exit 0 ;;
  kill) [[ "$log" != /dev/null ]] && printf '%s\n' "$*" >> "$log/kill.log"; exit 0 ;;
  rm) [[ "$log" != /dev/null ]] && printf '%s\n' "$*" >> "$log/rm.log"; exit 0 ;;
  run) shift ;;
  *) echo "docker-stub: unsupported: $*" >&2; exit 2 ;;
esac
if [[ "$log" != /dev/null ]]; then
  mkdir -p "$log"; n=1; while [[ -e "$log/run-$n.argv" ]]; do n=$((n + 1)); done
  printf '%s\0' run "$@" > "$log/run-$n.argv"
fi
ws="" wd="/"
mounts=() envs=() nested=()
# flags that take a value (docker 26.1 run); everything else before the image is boolean
while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--volume)
      src="${2%%:*}" rest="${2#*:}"; dst="${rest%%:*}"; [[ "$dst" == /workspace ]] && ws="$src"
      mounts+=("$dst=$src")
      [[ "$dst" == /workspace/* ]] && nested+=("$dst=$src")
      # record each mount and, for the non-/workspace mounts, every path under its source
      if [[ "$log" != /dev/null ]]; then
        { printf '%s\n' "$2"
          if [[ "$dst" != /workspace ]]; then (cd "$src" && find . -mindepth 1 | sed 's|^\./|  |' | LC_ALL=C sort); fi
        } >> "$log/run-$n.mounts"
      fi
      shift 2 ;;
    -e|--env)
      # KEY=value as given; a bare KEY takes the client's own value (how secrets travel)
      if [[ "$2" == *=* ]]; then envs+=("$2"); elif [[ -n "${!2+x}" ]]; then envs+=("$2=${!2}"); fi
      shift 2 ;;
    -w|--workdir) wd="$2"; shift 2 ;;
    --name|--user|--network|--tmpfs|--pids-limit|--memory|--cpus|--cap-drop|--security-opt) shift 2 ;;
    --rm|--read-only|--init|-i|-t) shift ;;
    -*) echo "docker-stub: unknown flag $1" >&2; exit 2 ;;
    *) break ;;
  esac
done
shift   # the image
if [[ "${DOCKER_STUB_HANG:-0}" == 1 && "${1:-}" == timeout ]]; then
  shift; while [[ "${1:-}" == -* ]]; do shift; done; shift
fi
[[ -n "$ws" ]] || { echo "docker-stub: no /workspace mount" >&2; exit 2; }
map() {  # container path → host path, for every mount
  local s="$1" m dst src
  for m in "${mounts[@]}"; do dst="${m%%=*}" src="${m#*=}"; s="${s//$dst/$src}"; done
  printf '%s' "$s"
}
cmd=() menv=()
for a in "$@"; do
  a="$(map "$a")"
  [[ "$a" == claude ]] && a="${DOCKER_STUB_CLAUDE:?DOCKER_STUB_CLAUDE unset}"
  cmd+=("$a")
done
for e in ${envs[@]+"${envs[@]}"}; do menv+=("${e%%=*}=$(map "${e#*=}")"); done
if [[ -n "${DOCKER_STUB_PATH:-}" ]]; then
  has_path=0; for e in ${menv[@]+"${menv[@]}"}; do [[ "$e" == PATH=* ]] && has_path=1; done
  [[ $has_path -eq 1 ]] || menv+=("PATH=$DOCKER_STUB_PATH")
fi
cd "$(map "$wd")"
# the container's environment is exactly the -e set (plus nothing from this host)
if [[ ${#nested[@]} -eq 0 ]]; then exec env -i ${menv[@]+"${menv[@]}"} "${cmd[@]}"; fi
# nested mounts: emulate each by a symlink at the mountpoint for the command's duration, then restore the directory
links=()
for m in "${nested[@]}"; do
  dst="${m%%=*}" src="${m#*=}"; tgt="$ws/${dst#/workspace/}"
  rmdir "$tgt" 2>/dev/null || true
  if [[ -e "$tgt" || -L "$tgt" ]]; then echo "docker-stub: mountpoint $tgt is not an empty directory" >&2; exit 2; fi
  mkdir -p "$(dirname "$tgt")"; ln -s "$src" "$tgt"; links+=("$tgt")
done
restore() { local l; for l in ${links[@]+"${links[@]}"}; do rm -f "$l"; mkdir -p "$l"; done; }
child=""
trap 'kill -TERM "$child" 2>/dev/null' TERM
env -i ${menv[@]+"${menv[@]}"} "${cmd[@]}" & child=$!
rc=0; wait "$child" || rc=$?
restore
exit "$rc"
