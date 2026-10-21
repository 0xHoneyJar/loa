# suite-lib.bash — fixture-suite builders for validate-suite.bats and freeze.bats
# (cycle-130 Sprint 258 Task 1.11). Sourced by the bats files; the templates are
# the two committed smoke tasks, so the fixtures follow the real schema.
#
#   make_task <root> <group> <id> <type>   copy a smoke task to <root>/<group>/<id>
#                                          as <type> (build types from smoke-build-01,
#                                          review-catch from smoke-review-01)
#   make_full_suite <root>                 four tasks of each type under tasks/

SMOKE_ROOT="${SMOKE_ROOT:-$REPO_ROOT/grimoires/loa/evals/ablation-2.0/smoke}"

make_task() {
  local root="$1" group="$2" id="$3" type="$4" src
  case "$type" in review-catch) src="$SMOKE_ROOT/smoke-review-01" ;; *) src="$SMOKE_ROOT/smoke-build-01" ;; esac
  mkdir -p "$root/$group"
  cp -a "$src" "$root/$group/$id"
  local ty="$root/$group/$id/task.yaml"
  ID="$id" TY="$type" yq -i '.id = strenv(ID) | .type = strenv(TY)' "$ty"
  if [[ "$type" != "review-catch" ]]; then
    FX="$group/$id/fixture" yq -i '.fixture = strenv(FX)' "$ty"
  fi
  if [[ "$type" == "refactor" ]]; then
    printf 'def test_structure():\n    assert True\n' > "$root/$group/$id/hidden/tests/test_structure_check.py"
    yq -i '.structural_check = "hidden/tests/test_structure_check.py"' "$ty"
  fi
}

make_full_suite() {
  local root="$1" ty i
  for ty in feature-build bug-fix refactor review-catch; do
    for i in 1 2 3 4; do make_task "$root" tasks "$ty-0$i" "$ty"; done
  done
}
