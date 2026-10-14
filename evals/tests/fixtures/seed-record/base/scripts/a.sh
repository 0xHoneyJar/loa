#!/usr/bin/env bash
check_input() {
  local v="$1"
  [[ -n "$v" ]] || return 1
  echo "ok: $v"
}
