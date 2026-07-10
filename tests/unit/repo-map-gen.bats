#!/usr/bin/env bats
# cycle-116 D4 (bd-c116-d4-repo-map-x69d) -- repo-map-gen.sh coverage.
# Idioms lifted from tests/unit/agents-md-gen.bats + tests/unit/grimoire-index.bats:
# JSON-shape assertion, byte-determinism via $output compare, tamper-and-restore
# (restore BEFORE asserting so the tree is never left dirty), synthetic mktemp corpus.

setup() {
  BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
  GEN="$PROJECT_ROOT/.claude/scripts/repo-map-gen.sh"
  ENGINE="$PROJECT_ROOT/.claude/scripts/lib/repo_map.py"
  MAP="$PROJECT_ROOT/grimoires/loa/REPO-MAP.md"
}

@test "repo-map: --json is valid JSON with the expected top-level keys" {
  run bash "$GEN" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '
    (.symbols|type=="array") and (.symbol_count|type=="number")
    and (.input_hash|type=="string") and (.file_count|type=="number")
    and (.damping==0.85) and (.iterations==50)' >/dev/null
}

@test "repo-map: --json is byte-deterministic across two runs" {
  run bash "$GEN" --json; [ "$status" -eq 0 ]; local a="$output"
  run bash "$GEN" --json; [ "$status" -eq 0 ]; [ "$a" = "$output" ]
}

@test "repo-map: --validate passes against the committed REPO-MAP.md" {
  run bash "$GEN" --validate
  [ "$status" -eq 0 ]
}

@test "repo-map: --validate FAILS when REPO-MAP.md is tampered (drift detection)" {
  cp "$MAP" "$BATS_TMPDIR/REPO-MAP.md.bak"
  printf '\nTAMPERED LINE\n' >> "$MAP"
  run bash "$GEN" --validate
  cp "$BATS_TMPDIR/REPO-MAP.md.bak" "$MAP"   # restore before asserting
  [ "$status" -ne 0 ]
  [[ "$output" == *"REPO-MAP-DRIFT"* ]]
}

@test "repo-map: PageRank surfaces the more-referenced symbol first (synthetic fixture)" {
  local dir; dir="$(mktemp -d)"
  mkdir -p "$dir/pkg"
  printf 'popular() { echo hi; }\nlonely() { echo bye; }\n' > "$dir/pkg/defs.sh"
  printf 'c1() { popular; }\n' > "$dir/pkg/caller1.sh"
  printf 'c2() { popular; }\n' > "$dir/pkg/caller2.sh"
  printf 'c3() { popular; }\n' > "$dir/pkg/caller3.sh"
  run python3 "$ENGINE" --root "$dir" --scan "pkg" --emit json
  [ "$status" -eq 0 ]
  local pop lon
  pop=$(echo "$output" | jq '[.symbols[].name] | index("popular")')
  lon=$(echo "$output" | jq '[.symbols[].name] | index("lonely")')
  [ "$pop" -lt "$lon" ]
}

@test "repo-map: same-named symbols in different files collapse into one node (collision)" {
  local dir; dir="$(mktemp -d)"
  mkdir -p "$dir/pkg"
  printf 'dup() { :; }\n' > "$dir/pkg/one.sh"
  printf 'dup() { :; }\n' > "$dir/pkg/two.sh"
  run python3 "$ENGINE" --root "$dir" --scan "pkg" --emit json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '
    [.symbols[] | select(.name=="dup")] as $d
    | ($d|length==1) and ($d[0].collision==true) and ($d[0].def_sites|length==2)' >/dev/null
}
