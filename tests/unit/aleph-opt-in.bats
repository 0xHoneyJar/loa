#!/usr/bin/env bats
# =============================================================================
# tests/unit/aleph-opt-in.bats — bug 20260922-13a3d1 / sprint-bug-239
#
# Aleph is a third-party, vendored component. It must be OPT-IN: with no
# `aleph.enabled: true` in .loa.config.yaml and no LOA_ALEPH_ENABLED=1, nothing
# Aleph-related may run in Loa's mount/update path, health check, required test
# job or CI workflows. With the opt-in set, the pre-existing behaviour is
# unchanged. Contract: .claude/scripts/lib/aleph-opt-in.sh.
# =============================================================================

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  LIB="$REPO_ROOT/.claude/scripts/lib/aleph-opt-in.sh"
  MOUNT="$REPO_ROOT/.claude/scripts/mount-submodule.sh"
  CHECK_LOA="$REPO_ROOT/.claude/scripts/check-loa.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/aleph-optin.XXXXXX")"
  unset LOA_ALEPH_ENABLED
}

teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

# A consumer-shaped fixture: a git repo carrying Aleph's managed paths.
_consumer() {  # <dir> [config-yaml]
  local d="$1"
  mkdir -p "$d/.claude/aleph/bin" "$d/.claude/skills/loa-aleph" "$d/.claude/commands"
  : > "$d/.claude/commands/loa-aleph.md"
  ( cd "$d" && git init -q -b main && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init )
  [[ -n "${2:-}" ]] && printf '%s\n' "$2" > "$d/.loa.config.yaml"
  return 0
}

@test "AO-1 predicate: disabled by default; enabled by aleph.enabled: true or LOA_ALEPH_ENABLED=1; malformed or mis-scoped reads as disabled; no yq dependency" {
  [ -f "$LIB" ]
  source "$LIB"
  _consumer "$T/c1"
  ! aleph_opt_in_enabled "$T/c1"
  _consumer "$T/c2" $'aleph:\n  enabled: true'
  aleph_opt_in_enabled "$T/c2"
  _consumer "$T/c3" $'aleph:\n  enabled: "yes please"'
  ! aleph_opt_in_enabled "$T/c3"
  LOA_ALEPH_ENABLED=1 aleph_opt_in_enabled "$T/c1"
  LOA_ALEPH_ENABLED=0 ; ! aleph_opt_in_enabled "$T/c1"
  # the switch must sit directly under the top-level aleph: key — a foreign `enabled: true` does not count
  _consumer "$T/c4" $'other:\n  enabled: true\naleph:\n  enabled: false'
  ! aleph_opt_in_enabled "$T/c4"
  _consumer "$T/c5" $'aleph:\n  enabled: true   # trailing comment is fine'
  aleph_opt_in_enabled "$T/c5"
  # no yq dependency: the reader is POSIX awk (comments may mention yq; code may not)
  ! grep -vE '^[[:space:]]*#' "$LIB" | grep -qE '\byq\b'
}

@test "AO-2 mount: aleph_refresh_is_applicable refuses without opt-in even when managed paths exist, and applies with it" {
  _consumer "$T/c"
  run bash -c "cd '$T/c' && SUBMODULE_PATH='.loa' source '$MOUNT' --source-only && declare -F aleph_refresh_is_applicable >/dev/null && aleph_refresh_is_applicable '$T/c' '.loa'"
  [ "$status" -ne 0 ]
  run bash -c "cd '$T/c' && SUBMODULE_PATH='.loa' source '$MOUNT' --source-only && declare -F aleph_refresh_is_applicable >/dev/null && LOA_ALEPH_ENABLED=1 aleph_refresh_is_applicable '$T/c' '.loa'"
  [ "$status" -eq 0 ]
  # the guard must be the predicate, not a missing function
  run bash -c "cd '$T/c' && SUBMODULE_PATH='.loa' source '$MOUNT' --source-only && declare -F aleph_refresh_is_applicable && declare -F aleph_opt_in_enabled"
  [ "$status" -eq 0 ]
}

@test "AO-3 check-loa: the Aleph integrity check is skipped without opt-in" {
  # grep-lock on the call site: the health check must consult the predicate
  grep -qE 'aleph_opt_in_enabled' "$CHECK_LOA"
  n=$(grep -nE '^\s*check_aleph_integrity$' "$CHECK_LOA" | head -1 | cut -d: -f1)
  [ -n "$n" ]
  sed -n "$((n-3)),$((n))p" "$CHECK_LOA" | grep -qE 'aleph_opt_in_enabled'
}

@test "AO-4 the three Aleph suites skip themselves unless opted in" {
  for f in aleph-release-ingestion aleph-framework-integration aleph-submodule-real-installer; do
    grep -qE 'aleph_opt_in_enabled' "$REPO_ROOT/tests/unit/$f.bats"
  done
  # the cheapest suite really skips (no LOA_ALEPH_ENABLED, repo config says false)
  run npx --no-install bats "$REPO_ROOT/tests/unit/aleph-release-ingestion.bats"
  [ "$status" -eq 0 ]
  [ "$(grep -cE '^ok [0-9]+ .*# skip' <<<"$output")" -ge 1 ]
  ! grep -qE '^not ok' <<<"$output"
}

@test "AO-5 both Aleph workflows carry a config gate: downstream jobs need it and run only when enabled" {
  for wf in aleph-bundle-integrity aleph-release-sync; do
    f="$REPO_ROOT/.github/workflows/$wf.yml"
    [ "$(yq eval '.jobs.gate.outputs.enabled // ""' "$f")" != "" ]
    grep -qE "aleph\.enabled" "$f"
    # the gate must not depend on a runner's parser inventory (dissent: parser absence must never decide)
    ! yq eval '.jobs.gate.steps[] | select(.id == "read") | .run' "$f" | grep -vE '^[[:space:]]*#' | grep -qE '\byq\b'
    # every non-gate job depends on the gate and is conditioned on it
    for job in $(yq eval '.jobs | keys | .[]' "$f" | grep -v '^gate$'); do
      needs=$(yq eval ".jobs.\"$job\".needs | [.] | flatten | join(\",\")" "$f")
      [[ "$needs" == *gate* ]]
      cond=$(yq eval ".jobs.\"$job\".if // \"\"" "$f")
      [[ "$cond" == *"needs.gate.outputs.enabled == 'true'"* ]]
    done
  done
}

@test "AO-5b the integrity gate reads the BASE ref's config on pull requests (a PR cannot flip its own gate)" {
  f="$REPO_ROOT/.github/workflows/aleph-bundle-integrity.yml"
  ref=$(yq eval '.jobs.gate.steps[] | select(.uses | test("actions/checkout")) | .with.ref' "$f")
  [[ "$ref" == *"github.event.pull_request.base.sha"* ]]
}

@test "AO-6 config: the example documents aleph.enabled (default false) and this repository sets it false explicitly" {
  [ "$(yq eval '.aleph.enabled' "$REPO_ROOT/.loa.config.yaml.example")" = "false" ]
  [ "$(yq eval '.aleph.enabled' "$REPO_ROOT/.loa.config.yaml")" = "false" ]
}

@test "AO-7 Loa's capabilities lint stays authoritative: loa-aleph/SKILL.md keeps its capabilities block and passes" {
  grep -qE '^capabilities:' "$REPO_ROOT/.claude/skills/loa-aleph/SKILL.md"
  run "$REPO_ROOT/.claude/scripts/validate-skill-capabilities.sh"
  [ "$status" -eq 0 ]
}
