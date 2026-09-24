#!/usr/bin/env bats
# =============================================================================
# tests/unit/known-failures-seed.bats — cycle-125 Sprint 4 (PRD FR-4 AC 4)
# grimoires/loa/known-failures.md is seeded from .claude/templates/
# known-failures.md.template by mount-submodule.sh and mount-loa.sh (never
# overwritten), the seeded file is writable by kf-write-lib.sh, and
# check-loa.sh warns when it is absent.
# =============================================================================

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TEMPLATE="$PROJECT_ROOT/.claude/templates/known-failures.md.template"
  KFLIB="$PROJECT_ROOT/.claude/scripts/lib/kf-write-lib.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/kfs.XXXXXX")"
  mkdir -p "$T/proj/.claude/templates" "$T/proj/grimoires/loa"
  cp "$TEMPLATE" "$T/proj/.claude/templates/known-failures.md.template"
}
teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

# Extract one shell function from a script into a sourceable file.
fn_of() { awk -v f="$2" '$0 ~ "^"f"\\(\\) \\{" {p=1} p {print} p && /^}/ {exit}' "$1" > "$3"; [ -s "$3" ]; }

@test "KFS-1 the template carries the ledger header, the schema block and an empty Index table" {
  head -1 "$TEMPLATE" | grep -q '^# Known Failures'
  grep -q '^## Schema' "$TEMPLATE"
  grep -q '^## Index' "$TEMPLATE"
  grep -q '^| ID | Status | Feature | Recurrence |' "$TEMPLATE"
  grep -q 'kf-write-lib.sh' "$TEMPLATE"
  ! grep -qE 'sk-[A-Za-z0-9]{8,}|AKIA[0-9A-Z]{8,}|ghp_[A-Za-z0-9]{8,}' "$TEMPLATE"
}

@test "KFS-2 mount-submodule.sh seeds known-failures.md from the template, logs once, never overwrites" {
  fn_of "$PROJECT_ROOT/.claude/scripts/mount-submodule.sh" seed_known_failures_ledger "$T/fn.sh"
  cd "$T/proj"
  # sourced from $T, so the BASH_SOURCE-relative template path misses and the cwd fallback (.claude/templates/) is exercised
  run bash -c "log(){ echo \"LOG \$*\"; }; warn(){ echo \"WARN \$*\"; }; source '$T/fn.sh'; seed_known_failures_ledger grimoires/loa"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Created known-failures.md"* ]]
  [ -f grimoires/loa/known-failures.md ]
  cmp -s grimoires/loa/known-failures.md "$TEMPLATE"
  echo "operator edit" >> grimoires/loa/known-failures.md
  run bash -c "log(){ echo \"LOG \$*\"; }; warn(){ echo \"WARN \$*\"; }; source '$T/fn.sh'; seed_known_failures_ledger grimoires/loa"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  grep -q '^operator edit$' grimoires/loa/known-failures.md
}

@test "KFS-3 mount-loa.sh seeds the same file from the vendored template and warns when the template is missing" {
  fn_of "$PROJECT_ROOT/.claude/scripts/mount-loa.sh" seed_known_failures_ledger "$T/fn2.sh"
  cd "$T/proj"
  run bash -c "log(){ echo \"LOG \$*\"; }; warn(){ echo \"WARN \$*\"; }; source '$T/fn2.sh'; seed_known_failures_ledger grimoires/loa"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Created known-failures.md"* ]]
  cmp -s grimoires/loa/known-failures.md "$TEMPLATE"
  rm grimoires/loa/known-failures.md .claude/templates/known-failures.md.template
  run bash -c "log(){ echo \"LOG \$*\"; }; warn(){ echo \"WARN \$*\"; }; source '$T/fn2.sh'; seed_known_failures_ledger grimoires/loa"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN"*"not seeded"* ]]
  [ ! -f grimoires/loa/known-failures.md ]
}

@test "KFS-4 a seeded ledger accepts kf-write-lib.sh new: entry appended and Index row inserted" {
  cp "$TEMPLATE" "$T/kf.md"
  run bash "$KFLIB" new --file "$T/kf.md" --title "seeded ledger smoke" --status OPEN --feature "mount" --symptom "none" --quiet
  [ "$status" -eq 0 ]
  grep -q '^## KF-001: seeded ledger smoke' "$T/kf.md"
  grep -qE '^\| \[KF-001\]\(#kf-001-[a-z-]+\) \| OPEN \| mount \|' "$T/kf.md"
  grep -q '^\*\*Status\*\*: OPEN' "$T/kf.md"
}

@test "KFS-5 check-loa.sh check_memory warns when known-failures.md is missing and is silent about it when present" {
  fn_of "$PROJECT_ROOT/.claude/scripts/check-loa.sh" check_memory "$T/cm.sh"
  mkdir -p "$T/g"
  printf '# notes\n## Active Sub-Goals\n## Session Continuity\n## Decision Log\n' > "$T/g/NOTES.md"
  run bash -c "warn(){ echo \"WARN \$*\"; }; log(){ echo \"LOG \$*\"; }; NOTES_FILE='$T/g/NOTES.md'; source '$T/cm.sh'; check_memory"
  [ "$status" -eq 0 ]
  [[ "$output" == *"known-failures.md missing"* ]]
  cp "$TEMPLATE" "$T/g/known-failures.md"
  run bash -c "warn(){ echo \"WARN \$*\"; }; log(){ echo \"LOG \$*\"; }; NOTES_FILE='$T/g/NOTES.md'; source '$T/cm.sh'; check_memory"
  [[ "$output" != *"known-failures.md missing"* ]]
}
