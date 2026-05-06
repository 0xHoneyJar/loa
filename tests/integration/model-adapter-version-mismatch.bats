#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# =============================================================================
# model-adapter-version-mismatch.bats — cycle-099 Sprint 2C (T2.5)
#
# Verifies that model-adapter.sh detects cross-process regen of
# `.run/merged-model-aliases.sh` via the monotonic version header. This is
# the long-running-process drift defense per Brief E.
#
# For a one-shot adapter invocation, version-mismatch is mostly inert (each
# run sources fresh). These tests exercise the helper functions directly to
# pin the contract: a version bump between init and a subsequent
# refresh_if_stale call MUST cause re-source, and the new arrays MUST reflect
# the bumped content.
# =============================================================================

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  HELPER="$REPO_ROOT/.claude/scripts/lib/overlay-source-helper.sh"
  ADAPTER="$REPO_ROOT/.claude/scripts/model-adapter.sh"
  WORK="$(mktemp -d)"
  MERGED="$WORK/merged-model-aliases.sh"
  LOCKFILE="$MERGED.lock"
  INPUT="$WORK/input.txt"
  printf 'sample input\n' > "$INPUT"
  export LOA_OVERLAY_MERGED="$MERGED"
  export LOA_OVERLAY_LOCKFILE="$LOCKFILE"
  export HOUNFOUR_FLATLINE_ROUTING=true
}

teardown() {
  rm -rf "$WORK"
}

# Helper: write a merged file with a specific version + a unique alias set,
# so we can prove the new content is loaded after refresh.
_write_merged_v1() {
  cat > "$MERGED" <<'EOF'
# version=1
# source-sha256=1111111111111111111111111111111111111111111111111111111111111111
# holder-pid=11
# DO NOT EDIT
declare -gA LOA_MODEL_PROVIDERS=( [v1-only]=anthropic )
declare -gA LOA_MODEL_IDS=( [v1-only]=v1-model-id )
declare -gA LOA_MODEL_ENDPOINT_FAMILIES=( [v1-only]=messages )
declare -gA LOA_MODEL_COST_INPUT_PER_MTOK=( [v1-only]=1 )
declare -gA LOA_MODEL_COST_OUTPUT_PER_MTOK=( [v1-only]=2 )
LOA_OVERLAY_FINGERPRINT=v1fingerpri
EOF
  : > "$LOCKFILE"
}

_write_merged_v2() {
  cat > "$MERGED" <<'EOF'
# version=2
# source-sha256=2222222222222222222222222222222222222222222222222222222222222222
# holder-pid=22
# DO NOT EDIT
declare -gA LOA_MODEL_PROVIDERS=( [v2-only]=openai )
declare -gA LOA_MODEL_IDS=( [v2-only]=v2-model-id )
declare -gA LOA_MODEL_ENDPOINT_FAMILIES=( [v2-only]=responses )
declare -gA LOA_MODEL_COST_INPUT_PER_MTOK=( [v2-only]=10 )
declare -gA LOA_MODEL_COST_OUTPUT_PER_MTOK=( [v2-only]=20 )
LOA_OVERLAY_FINGERPRINT=v2fingerpri
EOF
  : > "$LOCKFILE"
}

# -----------------------------------------------------------------------------
# A — refresh_if_stale picks up version bump
# -----------------------------------------------------------------------------

@test "A1: source v1 → bump to v2 → refresh_if_stale loads v2" {
  _write_merged_v1
  source "$HELPER"
  loa_overlay_init
  [ "$LOA_OVERLAY_VERSION_AT_LOAD" = "1" ]
  run loa_overlay_resolve_provider_id "v1-only"
  [ "$status" -eq 0 ]
  [ "$output" = "anthropic:v1-model-id" ]

  _write_merged_v2
  loa_overlay_refresh_if_stale
  [ "$LOA_OVERLAY_VERSION_AT_LOAD" = "2" ]
  run loa_overlay_resolve_provider_id "v2-only"
  [ "$status" -eq 0 ]
  [ "$output" = "openai:v2-model-id" ]
}

# -----------------------------------------------------------------------------
# B — Two sequential adapter invocations against bumped overlay
# -----------------------------------------------------------------------------

@test "B1: first adapter run resolves v1-only; second after bump resolves v2-only" {
  _write_merged_v1
  run --separate-stderr "$ADAPTER" \
    --model v1-only --mode review --input "$INPUT" --dry-run
  [[ "$stderr" == *"Model: v1-only → anthropic:v1-model-id"* ]]

  _write_merged_v2
  run --separate-stderr "$ADAPTER" \
    --model v2-only --mode review --input "$INPUT" --dry-run
  [[ "$stderr" == *"Model: v2-only → openai:v2-model-id"* ]]
}

# -----------------------------------------------------------------------------
# C — refresh_if_stale is a no-op when version unchanged
# -----------------------------------------------------------------------------

@test "C1: identical version → refresh_if_stale does NOT re-source" {
  _write_merged_v1
  source "$HELPER"
  loa_overlay_init
  # Capture the array contents
  local before_provider="${LOA_MODEL_PROVIDERS[v1-only]}"
  local before_id="${LOA_MODEL_IDS[v1-only]}"

  # Touch the file (mtime changes) but version header stays at 1
  touch "$MERGED"
  loa_overlay_refresh_if_stale

  # The arrays should still hold v1 content
  [ "${LOA_MODEL_PROVIDERS[v1-only]}" = "$before_provider" ]
  [ "${LOA_MODEL_IDS[v1-only]}" = "$before_id" ]
  [ "$LOA_OVERLAY_VERSION_AT_LOAD" = "1" ]
}

# -----------------------------------------------------------------------------
# D — Monotonic version: regression downgrade is also a mismatch (re-source)
# -----------------------------------------------------------------------------

@test "D1: version goes BACKWARD (rollback simulation) → refresh_if_stale also re-sources" {
  # Sprint 2B's hook emits monotonic-incrementing versions, but a manual
  # rollback (operator copies a backup) could decrement. The mismatch
  # detection treats any inequality as stale.
  _write_merged_v2
  source "$HELPER"
  loa_overlay_init
  [ "$LOA_OVERLAY_VERSION_AT_LOAD" = "2" ]

  _write_merged_v1
  loa_overlay_refresh_if_stale
  [ "$LOA_OVERLAY_VERSION_AT_LOAD" = "1" ]
  run loa_overlay_resolve_provider_id "v1-only"
  [ "$status" -eq 0 ]
  run loa_overlay_resolve_provider_id "v2-only"
  [ "$status" -eq 1 ]   # gone after re-source
}

# -----------------------------------------------------------------------------
# E — Adapter's pre-resolution refresh_if_stale call
# -----------------------------------------------------------------------------

@test "E1: adapter calls refresh_if_stale before resolution (defense vs cross-process drift)" {
  # This is a regression pin: future maintainers MUST keep the
  # `loa_overlay_refresh_if_stale` call in main()'s resolution chain.
  # We grep the adapter for the call.
  ADAPTER_PATH="$REPO_ROOT/.claude/scripts/model-adapter.sh"
  grep -q "loa_overlay_refresh_if_stale" "$ADAPTER_PATH"
}
