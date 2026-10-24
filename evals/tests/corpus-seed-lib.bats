#!/usr/bin/env bats
# =============================================================================
# evals/tests/corpus-seed-lib.bats — cycle-133 Sprint 3 Task 3.3 (SDD C-12):
# evals/harness/lib/corpus-seed.sh is extracted from seed-corpus-from-record.sh
# (fixture layout, labels grammar, exposure block, SHA256SUMS freeze/check,
# corpus.tsv row) and both seeders source it.
#
# Byte-identity: fixtures/corpus-seed/scenario.sh drives every record-seeder mode
# (dry-run, seed, re-seed, --paths, a gap, --allow-no-labels, --build-manifest,
# --stamp-exposure, --sync-labels, --approve, --freeze, --check, usage refusals)
# over the seed-record fixture with fixed commit dates, rebuilds every tracked
# manifest, and prints exit codes, stdout, stderr and the sha256 of every written
# file. transcript.golden is that transcript from the pre-extraction seeder
# (commit de366cc63).
# =============================================================================

setup() {
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  SEED="$REPO_ROOT/evals/harness/seed-corpus-from-record.sh"
  LIB="$REPO_ROOT/evals/harness/lib/corpus-seed.sh"
  FX="$TESTS_DIR/fixtures/corpus-seed"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/csl.XXXXXX")"
}

teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

@test "CSL-1 the record seeder's transcript over every mode is byte-identical to the pre-extraction seeder's" {
  run bash "$FX/scenario.sh" "$SEED" "$T"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > "$T/transcript"
  diff -u "$FX/transcript.golden" "$T/transcript"
}

@test "CSL-2 the record seeder sources lib/corpus-seed.sh and keeps no copy of the shared definitions" {
  [ -f "$LIB" ]
  grep -q '^source ./lib/corpus-seed.sh' "$SEED"
  for def in 'def exposure_block' 'def freeze' 'def check' 'def read_labels' 'def build_manifest' 'MODEL_AVAILABILITY = ' 'def corpus_row'; do
    grep -q "$def" "$LIB"
    ! grep -q "$def" "$SEED"
  done
}

@test "CSL-3 the library is the external seeder's too" {
  grep -q '^source ./lib/corpus-seed.sh' "$REPO_ROOT/evals/harness/seed-corpus-from-external.sh"
}

@test "CSL-4 the library defines functions only: sourcing it changes no shell option and prints nothing" {
  run bash -c 'set +e +u; before="$(set +o)"; source "$1"; after="$(set +o)"; [ "$before" = "$after" ] && declare -F corpus_seed_python >/dev/null' _ "$LIB"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
