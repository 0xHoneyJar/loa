#!/usr/bin/env bash
# env_sanitize.sh — shared `env -i` allowlist for cycle-100 runner +
# differential.bats (Flatline IMP-003 environment parity).
#
# Both runners invoke the SUT under a deliberately small environment so
# stray developer-shell config can't perturb pass/fail. This file is the
# single source of truth for what's allowed through.

# Usage:
#   source env_sanitize.sh
#   loa_jailbreak_envi_invoke <command> [<args>...]
#
# Internally builds: env -i PATH=$PATH LANG=C LC_ALL=C HOME=$tmp BATS_TMPDIR=$tmp <cmd>

loa_jailbreak_envi_invoke() {
    local tmphome="${BATS_TMPDIR:-/tmp}/jailbreak-envi-home-$$"
    mkdir -p "$tmphome"
    env -i \
        PATH="${PATH:-/usr/bin:/bin}" \
        LANG="C" \
        LC_ALL="C" \
        HOME="$tmphome" \
        BATS_TMPDIR="${BATS_TMPDIR:-/tmp}" \
        "$@"
}
