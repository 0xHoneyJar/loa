#!/usr/bin/env bats
# =============================================================================
# tests/unit/lint-walk-excludes-fixtures.bats — cycle-133 Sprint 1 Task 1.6
# (FR-5, SDD C-5; bead bd-dt5r8, PR #1289 Bridgebuilder r1 F-006)
#
# The frozen fixture trees — vendored framework snapshots under
# evals/fixtures/review-prs/pr-*/ and the sensitivity-grade trees
# grimoires/loa/reports/ablation-2.0/*-grades/ — carry patterns the live gates
# reject. No repo-wide lint walk may report them.
#
# Mechanism: a repo-shaped temp root gets one script that violates every lint
# tool at once (swallowed jq, raw sha256sum, raw curl, raw yq knob read, a
# direct provider URL). Planted inside the tools' scope it is reported by each
# tool (positive control: the plant is real). Planted under a temp copy of
# evals/fixtures/review-prs/pr-99/ and a *-grades tree it is reported by none,
# each tool run the way CI runs it (and check-no-swallowed-jq.sh also with
# `--root .`, its whole-tree walk). A mutated copy of check-no-swallowed-jq.sh
# without its prune reports the planted fixture (the tripwire is not vacuous).
# A discovery test fails when a new tools/check-*.sh grows a recursive walk
# this file does not classify.
# =============================================================================

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TOOLS="$PROJECT_ROOT/tools"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/lw.XXXXXX")"
  local d=.claude
  mkdir -p "$T/$d/scripts" "$T/$d/skills" "$T/$d/data" "$T/tools"
  cp "$PROJECT_ROOT/$d/data/profiles.yaml" "$T/$d/data/"
  KEY="$(yq -r '.profiles[] | keys | .[]' "$PROJECT_ROOT/$d/data/profiles.yaml" | sort -u | head -1)"
  [ -n "$KEY" ]
  # an enforced file must exist for check-no-swallowed-jq.sh's default mode to run
  printf '#!/usr/bin/env bash\ntrue\n' > "$T/$d/scripts/scoring-engine.sh"
  FROZEN_A="evals/fixtures/review-prs/pr-99/head/$d/scripts"
  FROZEN_B="grimoires/loa/reports/ablation-2.0/c999-sensitivity-grades/$d/scripts"
}

teardown() {
  find "$T" -mindepth 1 -delete 2>/dev/null || true
  rmdir "$T" 2>/dev/null || true
}

# Plant the all-tools violation at <dir>/red-team-planted.sh under $T.
_plant() {
  mkdir -p "$T/$1"
  cat > "$T/$1/red-team-planted.sh" <<EOF
#!/usr/bin/env bash
v=\$(jq -r '.a' f.json 2>/dev/null || echo 0)
h=\$(sha256sum f | cut -d' ' -f1)
curl -s https://example.com/x
s=\$(yq '.$KEY // "x"' .loa.config.yaml)
u="https://api.anthropic.com/v1/messages"
EOF
}

# Every walking lint tool, as CI invokes it (tool<TAB>args). Run from $T.
WALKS=$'check-no-swallowed-jq.sh\t\ncheck-no-swallowed-jq.sh\t--root .\ncheck-no-raw-sha256sum.sh\t\ncheck-no-raw-curl.sh\t\ncheck-knob-readers.sh\t\ncheck-no-direct-llm-fetch.sh\t'

# Recursive walkers whose roots are fixed relative to the script (not the cwd
# or a --root): Bridgebuilder resources, and lib/ .claude/ tests/. Checked
# statically below.
FIXED_SCOPE="check-bb-dist-fresh.sh check-bb-no-direct-fetch.sh check-trigger-leak.sh"

_run_walks() {
  local tool args out rc
  while IFS=$'\t' read -r tool args; do
    rc=0
    # shellcheck disable=SC2086 # args is a fixed word list from WALKS
    out="$(cd "$T" && bash "$TOOLS/$tool" $args 2>&1)" || rc=$?
    printf '%s\t%s\t%s\n' "$tool $args" "$rc" "$(printf '%s' "$out" | grep -c 'red-team-planted' || true)"
  done <<< "$WALKS"
}

@test "LW-1 positive control: planted inside the tools' scope, every walking lint tool reports the plant" {
  _plant .claude/scripts
  run _run_walks
  [ "$status" -eq 0 ]
  local line name rc hits
  while IFS=$'\t' read -r name rc hits; do
    [ "$rc" -eq 1 ] || { echo "$name: exit $rc, expected 1" >&2; return 1; }
    [ "$hits" -ge 1 ] || { echo "$name: plant not reported" >&2; return 1; }
  done <<< "$output"
}

@test "LW-2 planted under a temp copy of evals/fixtures/review-prs/pr-99/ and a *-grades tree, no walking lint tool reports it" {
  _plant "$FROZEN_A"
  _plant "$FROZEN_B"
  run _run_walks
  [ "$status" -eq 0 ]
  local name rc hits
  while IFS=$'\t' read -r name rc hits; do
    [ "$hits" -eq 0 ] || { echo "$name reported a frozen fixture path" >&2; return 1; }
    [ "$rc" -eq 0 ] || { echo "$name: exit $rc, expected 0 (clean tree)" >&2; return 1; }
  done <<< "$output"
}

@test "LW-3 the prune is what excludes the fixtures: check-no-swallowed-jq.sh without it reports the planted fixture" {
  _plant "$FROZEN_A"
  grep -q 'frozen-fixture-prune:begin' "$TOOLS/check-no-swallowed-jq.sh"
  # the mutant lives outside the scan root so it is not itself scanned
  local m="${BATS_TEST_TMPDIR:-/tmp}/mutant-check-no-swallowed-jq.sh"
  sed '/frozen-fixture-prune:begin/,/frozen-fixture-prune:end/d' "$TOOLS/check-no-swallowed-jq.sh" > "$m"
  run bash -c 'cd "$1" && bash "$2" --root .' _ "$T" "$m"
  [ "$status" -eq 1 ]
  [[ "$output" == *"evals/fixtures/review-prs/pr-99/"*"red-team-planted.sh"* ]]
  run bash -c 'cd "$1" && bash "$2" --root .' _ "$T" "$TOOLS/check-no-swallowed-jq.sh"
  [ "$status" -eq 0 ]
}

@test "LW-4 the prune is anchored at the scan root: a fixture-like path elsewhere, and a file at the fixture root, are still scanned" {
  _plant "evals/fixtures/review-prs"
  _plant "lib/evals/fixtures/review-prs/pr-99"
  run bash -c 'cd "$1" && bash "$2" --root .' _ "$T" "$TOOLS/check-no-swallowed-jq.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"./evals/fixtures/review-prs/red-team-planted.sh"* ]]
  [[ "$output" == *"./lib/evals/fixtures/review-prs/pr-99/red-team-planted.sh"* ]]
  # a trailing slash on --root does not defeat the prune
  local t2; t2="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/lw2.XXXXXX")"
  mkdir -p "$t2/evals/fixtures/review-prs/pr-01"
  printf '#!/usr/bin/env bash\nv=$(jq -r .a f 2>/dev/null || echo 0)\n' > "$t2/evals/fixtures/review-prs/pr-01/x.sh"
  run bash "$TOOLS/check-no-swallowed-jq.sh" --root "$t2/"
  [ "$status" -eq 0 ]
}

@test "LW-5 discovery: every tools/check-*.sh with a recursive walk is classified here (runtime-planted or fixed-scope)" {
  local f base walked
  walked="$(printf '%s\n' "$WALKS" | cut -f1 | sort -u)"
  for f in "$TOOLS"/check-*.sh; do
    grep -qE '(^|[^[:alnum:]_])find "\$|(^|[[:space:]|(])grep[[:space:]]+-[A-Za-z]*[rR]' "$f" || continue
    base="$(basename "$f")"
    if ! printf '%s\n' "$walked" | grep -qx -- "$base" && [[ " $FIXED_SCOPE " != *" $base "* ]]; then
      echo "$base walks files but is not in WALKS or FIXED_SCOPE of $BATS_TEST_FILENAME" >&2
      return 1
    fi
  done
}

@test "LW-6 fixed-scope walkers never start a find at the bare repository root" {
  local base
  for base in $FIXED_SCOPE; do
    [ -f "$TOOLS/$base" ]
    ! grep -nE 'find[[:space:]]+"?\$\{?(REPO_ROOT|ROOT|PROJECT_ROOT)\}?"?([[:space:]]|$)' "$TOOLS/$base"
    ! grep -nE 'find[[:space:]]+\.([[:space:]]|$)' "$TOOLS/$base"
  done
  # check-trigger-leak.sh walks only lib/, .claude/ and tests/ under the repo root
  run sed -n '/^SEARCH_ROOTS=(/,/^)/p' "$TOOLS/check-trigger-leak.sh"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c 'REPO_ROOT}/')" -eq 3 ]
  [[ "$output" == *'/lib"'* && "$output" == *'/.claude"'* && "$output" == *'/tests"'* ]]
}

@test "LW-7 .gitattributes marks the frozen trees linguist-generated -diff and keeps the workflows merge=ours rule" {
  grep -qx 'evals/fixtures/review-prs/pr-\*/\*\* linguist-generated -diff' "$PROJECT_ROOT/.gitattributes"
  grep -qx 'grimoires/loa/reports/ablation-2.0/\*-grades/\*\* linguist-generated -diff' "$PROJECT_ROOT/.gitattributes"
  grep -qx '.github/workflows/\*.yml merge=ours' "$PROJECT_ROOT/.gitattributes"
  run git -C "$PROJECT_ROOT" check-attr linguist-generated diff -- evals/fixtures/review-prs/pr-01/head/x.sh evals/fixtures/review-prs/corpus.tsv grimoires/loa/reports/ablation-2.0/c132-sensitivity-grades/a.json
  [ "$status" -eq 0 ]
  [[ "$output" == *"pr-01/head/x.sh: linguist-generated: set"* ]]
  [[ "$output" == *"pr-01/head/x.sh: diff: unset"* ]]
  [[ "$output" == *"corpus.tsv: linguist-generated: unspecified"* ]]
  [[ "$output" == *"c132-sensitivity-grades/a.json: diff: unset"* ]]
  # the gitattributes-workflow-protection eval task's grader still passes, on
  # the repository's own file alone (the grader walks its whole workspace, so
  # the workspace holds only that copy) and on the task's fixture
  mkdir -p "$T/ws"
  cp "$PROJECT_ROOT/.gitattributes" "$T/ws/.gitattributes"
  run bash "$PROJECT_ROOT/evals/graders/pattern-match.sh" "$T/ws" "github/workflows/.*merge=ours" ".gitattributes"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"pass":true'* ]]
  run bash "$PROJECT_ROOT/evals/graders/pattern-match.sh" "$PROJECT_ROOT/evals/fixtures/loa-skill-dir" "github/workflows/.*merge=ours" ".gitattributes"
  [ "$status" -eq 0 ]
}
