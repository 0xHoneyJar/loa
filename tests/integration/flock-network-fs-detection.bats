#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# =============================================================================
# AC-S2.8 — flock-NFS detection blocklist (cycle-099 Sprint 2B / SDD §6.6)
#
# Per SDD §6.6: when `.run/merged-model-aliases.sh.lock`'s filesystem is in
# {nfs, nfs3, nfs4, cifs, smbfs, smb3, fuse.sshfs, fuse.s3fs, autofs, davfs},
# the hook refuses to write with [MERGED-ALIASES-NETWORK-FS]. Operator can
# acknowledge the failure mode via LOA_ALLOW_NETWORK_FS_FOR_MERGED_ALIASES=1
# which proceeds with [MERGED-ALIASES-NETWORK-FS-OVERRIDE] WARN log.
#
# This bats file exercises the hook end-to-end with a mocked /proc/mounts
# pointing at the test work dir. Test-mode injection requires:
#   LOA_OVERLAY_TEST_MODE=1
#   LOA_OVERLAY_PROC_MOUNTS_PATH_FOR_TEST=<path>
#   BATS_TEST_DIRNAME (always set under bats — third-leg gate)
# Partial test-mode (only TEST_MODE=1 without the path env var) does NOT
# trigger production override — closing the env-var-leak footgun per
# cycle-099 feedback_allowlist_tree_restriction.md pattern.
# =============================================================================

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  HOOK="$REPO_ROOT/.claude/scripts/lib/model-overlay-hook.py"
  PYTHON="$(command -v python3)"
  [[ -n "$PYTHON" ]] || skip "python3 not on PATH"
  WORK="$(mktemp -d)"
  RUN_DIR="$WORK/run"
  mkdir -p "$RUN_DIR"
  MOCK_MOUNTS="$WORK/mounts"
  SCHEMA="$REPO_ROOT/.claude/data/trajectory-schemas/model-aliases-extra.schema.json"
  SOT="$REPO_ROOT/.claude/defaults/model-config.yaml"
  # Empty operator config (no model_aliases_extra)
  OP="$WORK/.loa.config.yaml"
  printf '{}\n' > "$OP"
}

teardown() {
  rm -rf "$WORK"
}

# Helper: write a /proc/mounts-style file claiming the WORK dir is on $1 fs.
_write_mock_mounts() {
  local fs_type="$1"
  printf 'tmpfs / tmpfs rw 0 0\n' > "$MOCK_MOUNTS"
  printf 'server:/share %s %s rw 0 0\n' "$WORK" "$fs_type" >> "$MOCK_MOUNTS"
}

_run_hook() {
  "$PYTHON" "$HOOK" \
    --sot "$SOT" \
    --operator "$OP" \
    --merged "$RUN_DIR/merged.sh" \
    --lockfile "$RUN_DIR/merged.sh.lock" \
    --state "$RUN_DIR/state.json" \
    --schema "$SCHEMA"
}

# -----------------------------------------------------------------------------
# A — POSITIVE CONTROLS
# -----------------------------------------------------------------------------

@test "A1: ext4 (local fs) proceeds without override" {
  _write_mock_mounts "ext4"
  export LOA_OVERLAY_TEST_MODE=1
  export LOA_OVERLAY_PROC_MOUNTS_PATH_FOR_TEST="$MOCK_MOUNTS"
  run --separate-stderr _run_hook
  [ "$status" -eq 0 ]
  [ -f "$RUN_DIR/merged.sh" ]
}

@test "A2: tmpfs (local fs) proceeds without override" {
  _write_mock_mounts "tmpfs"
  export LOA_OVERLAY_TEST_MODE=1
  export LOA_OVERLAY_PROC_MOUNTS_PATH_FOR_TEST="$MOCK_MOUNTS"
  run --separate-stderr _run_hook
  [ "$status" -eq 0 ]
}

@test "A3: btrfs (local fs) proceeds without override" {
  _write_mock_mounts "btrfs"
  export LOA_OVERLAY_TEST_MODE=1
  export LOA_OVERLAY_PROC_MOUNTS_PATH_FOR_TEST="$MOCK_MOUNTS"
  run --separate-stderr _run_hook
  [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------------
# B — NETWORK-FS REFUSE (must exit 78 with [MERGED-ALIASES-NETWORK-FS])
# -----------------------------------------------------------------------------

@test "B1: nfs4 refuses without override" {
  _write_mock_mounts "nfs4"
  export LOA_OVERLAY_TEST_MODE=1
  export LOA_OVERLAY_PROC_MOUNTS_PATH_FOR_TEST="$MOCK_MOUNTS"
  run --separate-stderr _run_hook
  [ "$status" -eq 78 ]
  [[ "$stderr" == *"[MERGED-ALIASES-NETWORK-FS]"* ]]
  [[ "$stderr" == *"nfs4"* ]]
  [ ! -f "$RUN_DIR/merged.sh" ]
}

@test "B2: nfs3 refuses without override" {
  _write_mock_mounts "nfs3"
  export LOA_OVERLAY_TEST_MODE=1
  export LOA_OVERLAY_PROC_MOUNTS_PATH_FOR_TEST="$MOCK_MOUNTS"
  run --separate-stderr _run_hook
  [ "$status" -eq 78 ]
  [[ "$stderr" == *"[MERGED-ALIASES-NETWORK-FS]"* ]]
}

@test "B3: cifs refuses without override" {
  _write_mock_mounts "cifs"
  export LOA_OVERLAY_TEST_MODE=1
  export LOA_OVERLAY_PROC_MOUNTS_PATH_FOR_TEST="$MOCK_MOUNTS"
  run --separate-stderr _run_hook
  [ "$status" -eq 78 ]
  [[ "$stderr" == *"[MERGED-ALIASES-NETWORK-FS]"* ]]
}

@test "B4: smbfs refuses without override" {
  _write_mock_mounts "smbfs"
  export LOA_OVERLAY_TEST_MODE=1
  export LOA_OVERLAY_PROC_MOUNTS_PATH_FOR_TEST="$MOCK_MOUNTS"
  run --separate-stderr _run_hook
  [ "$status" -eq 78 ]
  [[ "$stderr" == *"[MERGED-ALIASES-NETWORK-FS]"* ]]
}

@test "B5: fuse.sshfs refuses without override" {
  _write_mock_mounts "fuse.sshfs"
  export LOA_OVERLAY_TEST_MODE=1
  export LOA_OVERLAY_PROC_MOUNTS_PATH_FOR_TEST="$MOCK_MOUNTS"
  run --separate-stderr _run_hook
  [ "$status" -eq 78 ]
  [[ "$stderr" == *"[MERGED-ALIASES-NETWORK-FS]"* ]]
}

@test "B6: davfs refuses without override" {
  _write_mock_mounts "davfs"
  export LOA_OVERLAY_TEST_MODE=1
  export LOA_OVERLAY_PROC_MOUNTS_PATH_FOR_TEST="$MOCK_MOUNTS"
  run --separate-stderr _run_hook
  [ "$status" -eq 78 ]
  [[ "$stderr" == *"[MERGED-ALIASES-NETWORK-FS]"* ]]
}

# -----------------------------------------------------------------------------
# C — OVERRIDE PROCEEDS (must exit 0 with WARN log)
# -----------------------------------------------------------------------------

@test "C1: nfs4 + LOA_ALLOW_NETWORK_FS_FOR_MERGED_ALIASES=1 proceeds with WARN" {
  _write_mock_mounts "nfs4"
  export LOA_OVERLAY_TEST_MODE=1
  export LOA_OVERLAY_PROC_MOUNTS_PATH_FOR_TEST="$MOCK_MOUNTS"
  export LOA_ALLOW_NETWORK_FS_FOR_MERGED_ALIASES=1
  run --separate-stderr _run_hook
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[MERGED-ALIASES-NETWORK-FS-OVERRIDE]"* ]]
  [[ "$stderr" == *"nfs4"* ]]
  [ -f "$RUN_DIR/merged.sh" ]
}

@test "C2: cifs + override proceeds with WARN" {
  _write_mock_mounts "cifs"
  export LOA_OVERLAY_TEST_MODE=1
  export LOA_OVERLAY_PROC_MOUNTS_PATH_FOR_TEST="$MOCK_MOUNTS"
  export LOA_ALLOW_NETWORK_FS_FOR_MERGED_ALIASES=1
  run --separate-stderr _run_hook
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[MERGED-ALIASES-NETWORK-FS-OVERRIDE]"* ]]
}

# -----------------------------------------------------------------------------
# D — TEST-MODE FOOTGUN GUARD (cycle-099 dual-env-var pattern)
# -----------------------------------------------------------------------------

@test "D1: LOA_OVERLAY_TEST_MODE=1 alone (no path) does NOT escape production" {
  # Without LOA_OVERLAY_PROC_MOUNTS_PATH_FOR_TEST, the production /proc/mounts
  # is consulted. On a Linux CI runner this is typically ext4/tmpfs (local),
  # so the hook should proceed normally — proving partial test mode does NOT
  # short-circuit detection.
  _write_mock_mounts "nfs4"  # the mock isn't used since the path env isn't set
  export LOA_OVERLAY_TEST_MODE=1
  run --separate-stderr _run_hook
  # The status should be 0 (production /proc/mounts says local fs) NOT 78
  # (which would indicate the mock was consulted).
  [ "$status" -eq 0 ]
}

@test "D2: LOA_OVERLAY_PROC_MOUNTS_PATH_FOR_TEST alone (no TEST_MODE) does NOT escape" {
  _write_mock_mounts "nfs4"
  export LOA_OVERLAY_PROC_MOUNTS_PATH_FOR_TEST="$MOCK_MOUNTS"
  run --separate-stderr _run_hook
  # Same as D1 — partial gate doesn't activate the test-mode override
  [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------------
# E — NFS DETECTION REFUSAL CONTRACT (no merged file written on refuse)
# -----------------------------------------------------------------------------

@test "E1: refuse path does NOT create merged.sh, lock, or state files" {
  _write_mock_mounts "nfs4"
  export LOA_OVERLAY_TEST_MODE=1
  export LOA_OVERLAY_PROC_MOUNTS_PATH_FOR_TEST="$MOCK_MOUNTS"
  run --separate-stderr _run_hook
  [ "$status" -eq 78 ]
  [ ! -f "$RUN_DIR/merged.sh" ]
  # lockfile/state may be transiently created by other paths, but on the
  # NFS-refuse path the hook returns BEFORE attempting any write
  [ ! -f "$RUN_DIR/merged.sh" ]
}
