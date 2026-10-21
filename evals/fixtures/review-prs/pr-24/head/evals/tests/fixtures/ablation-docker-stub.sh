#!/usr/bin/env bash
# ablation-docker-stub.sh — docker stand-in for evals/tests/run-ablation.bats (no docker run).
#   docker --version                       Docker version 26.1.5 (stub)
#   docker image inspect … <img>           $DOCKER_STUB_IMAGE_ID (default sha256:feedface…);
#                                          exit 1 when DOCKER_STUB_NO_IMAGE=1
#   docker run … <img> claude --version    "$STUB_IMAGE_CLI (Claude Code)" (default 2.1.299)
#   anything else                          delegated to docker-stub.sh beside this file
set -euo pipefail
case "${1:-}" in
  --version) echo "Docker version 26.1.5 (stub)"; exit 0 ;;
  image)
    [[ "${DOCKER_STUB_NO_IMAGE:-0}" == 1 ]] && { echo "Error: No such image" >&2; exit 1; }
    echo "${DOCKER_STUB_IMAGE_ID:-sha256:feedfacefeedfacefeedfacefeedfacefeedfacefeedfacefeedfacefeedface}"; exit 0 ;;
  run)
    if [[ "${*: -2}" == "claude --version" ]]; then echo "${STUB_IMAGE_CLI:-2.1.299} (Claude Code)"; exit 0; fi ;;
esac
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/docker-stub.sh" "$@"
