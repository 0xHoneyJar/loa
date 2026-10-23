#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# =============================================================================
# tests/unit/gen-checksums.bats — cycle-130 Sprint 1 (PRD FR-1, AC-1.1/AC-1.2;
# SDD §5.1). tools/gen-checksums.sh writes .claude/checksums.json from the
# TRACKED .claude/ tree only: untracked build/cache/runtime artefacts
# (__pycache__, .run/, node_modules) and .claude/overrides/ never enter it.
# Every case runs on a fixture git repository built in setup(); the live
# manifest is only read by GC-8.
# =============================================================================

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
  GEN="$ROOT/tools/gen-checksums.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/gencs.XXXXXX")"
  R="$T/repo"
  mkdir -p "$R/.claude/scripts/lib" "$R/.claude/overrides" "$R/.claude/scripts/__pycache__" \
    "$R/.claude/.run" "$R/.claude/node_modules/pkg"
  printf 'echo a\n' > "$R/.claude/scripts/a.sh"
  printf 'echo c\n' > "$R/.claude/scripts/lib/c.sh"
  printf 'doc\n' > "$R/.claude/README.md"
  printf 'override\n' > "$R/.claude/overrides/o.md"
  printf 'outside\n' > "$R/outside.txt"
  # untracked artefacts that a working-tree walk would pick up
  printf 'bytecode' > "$R/.claude/scripts/__pycache__/x.pyc"
  printf 'lock' > "$R/.claude/.run/a.lock"
  printf '{}' > "$R/.claude/node_modules/pkg/index.js"
  git -C "$R" init --quiet
  git -C "$R" -c core.hooksPath=/dev/null add .claude/scripts/a.sh .claude/scripts/lib/c.sh \
    .claude/README.md .claude/overrides/o.md outside.txt
  git -C "$R" -c user.name=t -c user.email=t@t -c core.hooksPath=/dev/null commit --quiet -m fixture
}
teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

@test "GC-1 the manifest lists exactly the tracked non-override .claude files" {
  run bash "$GEN" --root "$R"
  [ "$status" -eq 0 ]
  run jq -r '.files | keys[]' "$R/.claude/checksums.json"
  [ "$status" -eq 0 ]
  [ "$output" = $'.claude/README.md\n.claude/scripts/a.sh\n.claude/scripts/lib/c.sh' ]
  [ "$(jq -r '.algorithm' "$R/.claude/checksums.json")" = "sha256" ]
  [[ "$(jq -r '.generated' "$R/.claude/checksums.json")" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$ ]]
}

@test "GC-2 hashes are sha256_portable digests of the working-tree content" {
  bash "$GEN" --root "$R" 2>/dev/null
  source "$ROOT/.claude/scripts/compat-lib.sh"
  expected="$(cd "$R" && sha256_portable .claude/scripts/a.sh | cut -d' ' -f1)"
  [ "$(jq -r '.files[".claude/scripts/a.sh"]' "$R/.claude/checksums.json")" = "$expected" ]
}

@test "GC-3 two runs are byte-identical except generated" {
  bash "$GEN" --root "$R" --out "$T/one.json" 2>/dev/null
  sleep 1
  bash "$GEN" --root "$R" --out "$T/two.json" 2>/dev/null
  jq 'del(.generated)' "$T/one.json" > "$T/one.nogen"
  jq 'del(.generated)' "$T/two.json" > "$T/two.nogen"
  cmp "$T/one.nogen" "$T/two.nogen"
  # the raw files differ on the generated line only
  run diff <(grep -v '"generated"' "$T/one.json") <(grep -v '"generated"' "$T/two.json")
  [ "$status" -eq 0 ]
}

@test "GC-4 --check exits 0 right after generation" {
  bash "$GEN" --root "$R" 2>/dev/null
  run bash "$GEN" --root "$R" --check
  [ "$status" -eq 0 ]
}

@test "GC-5 --check exits 1 naming a changed tracked file" {
  bash "$GEN" --root "$R" 2>/dev/null
  printf 'echo changed\n' > "$R/.claude/scripts/a.sh"
  run --separate-stderr bash "$GEN" --root "$R" --check
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"changed: .claude/scripts/a.sh"* ]]
}

@test "GC-6 --check exits 1 naming a deleted tracked file" {
  bash "$GEN" --root "$R" 2>/dev/null
  rm -f "$R/.claude/scripts/lib/c.sh"
  run --separate-stderr bash "$GEN" --root "$R" --check
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"removed: .claude/scripts/lib/c.sh"* ]]
}

@test "GC-7 exit 2 outside a git repository and on a usage error" {
  mkdir -p "$T/plain/.claude"
  printf 'x\n' > "$T/plain/.claude/x.sh"
  run --separate-stderr bash "$GEN" --root "$T/plain" --check
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"not a git work tree"* ]]
  run bash "$GEN" --bogus
  [ "$status" -eq 2 ]
}
