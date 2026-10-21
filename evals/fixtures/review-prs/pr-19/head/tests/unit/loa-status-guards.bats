#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# =============================================================================
# tests/unit/loa-status-guards.bats — cycle-129 Sprint 1 (PRD AC-1.5, SDD D-1.5)
# `/loa` prints one Guards line: register counts from grimoires/loa/guards.md and
# the 30-day host yield from .run/guard-yield.json (never recomputed at status
# time), or the regenerate hint when the yield file is missing. Fixture files via
# the bats-gated LOA_STATUS_GUARDS_FILE / LOA_STATUS_GUARD_YIELD_FILE seams.
# =============================================================================

setup() {
  umask 022
  export LOA_AUDIT_REPLAY=1
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  STATUS="$PROJECT_ROOT/.claude/scripts/loa-status.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/lsg.XXXXXX")"
  mkdir -p "$T/run" "$T/env"
  export LOA_STATUS_RUN_DIR="$T/run" LOA_STATUS_ENV_DIR="$T/env" LOA_STATUS_CONFIG_FILE="$T/no-loa-config.yaml"
  printf '# Guard register\n\n- guards: 94\n- guards_without_origin: 0\n- dormant: 3\n- floor: 21\n' > "$T/guards.md"
  jq -n '{schema_version: 1, generated_at: "2026-10-14", window_days: 30, scope: "host",
          totals: {guards: 94, real_blocks_30d: 87, likely_fp_30d: 72}}' > "$T/guard-yield.json"
  export LOA_STATUS_GUARDS_FILE="$T/guards.md" LOA_STATUS_GUARD_YIELD_FILE="$T/guard-yield.json"
}
teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

@test "LSG-1 the Guards line carries the register counts and the host yield from the yield file" {
  run timeout 120 bash "$STATUS" --no-stale-check
  [ "$status" -eq 0 ]
  line="$(grep -E '^Guards: ' <<<"$output" | sed 's/\x1b\[[0-9;]*m//g')"
  [ "$line" = "Guards: 94 (0 without origin, 3 dormant) · 30 d: 87 real blocks, 72 likely FP · scope host · regenerate: .claude/scripts/guard-yield.sh" ]
}

@test "LSG-2 with no yield file the line keeps the structural counts and prints the regenerate hint" {
  rm -f "$T/guard-yield.json"
  run timeout 120 bash "$STATUS" --no-stale-check
  [ "$status" -eq 0 ]
  line="$(grep -E '^Guards: ' <<<"$output" | sed 's/\x1b\[[0-9;]*m//g')"
  [ "$line" = "Guards: 94 (0 without origin, 3 dormant) · 30 d: no yield file (.run/guard-yield.json) · regenerate: .claude/scripts/guard-yield.sh" ]
}

@test "LSG-3 a malformed yield file is treated as missing; a missing register says so" {
  printf '{"totals": {"real_blocks_30d": "x; rm -rf /"}}\n' > "$T/guard-yield.json"
  run timeout 120 bash "$STATUS" --no-stale-check
  [ "$status" -eq 0 ]
  grep -qE '^.*Guards: .*94 \(0 without origin, 3 dormant\) · 30 d: no yield file' <<<"$output"
  [[ "$output" != *"rm -rf"* ]]
  rm -f "$T/guards.md"
  run timeout 120 bash "$STATUS" --no-stale-check
  [ "$status" -eq 0 ]
  grep -qE 'Guards: .*no register \(grimoires/loa/guards.md\) · regenerate: .claude/scripts/guard-yield.sh' <<<"$output"
}
