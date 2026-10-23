#!/usr/bin/env bats
# =============================================================================
# evals/tests/arm-toggles.bats — cycle-129 Sprint 1 Task 1.4 (FR-2, SDD D-2.1)
#
# execute-agent.sh applies a control arm's toggles to the sandbox copy only.
# Every assertion here reads the sandbox as the EXECUTOR saw it: the CLI stub
# snapshots CLAUDE.md, .claude/, .loa.config.yaml and the appended system
# prompt at the moment it starts (STUB_SNAPSHOT_DIR), after every
# materialisation step. The arm ids and toggles come from the real suite
# files; the prompt tree is a synthetic fixture so later prose edits to the
# live kernel cannot change what this test proves.
# =============================================================================

setup() {
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  EXEC="$REPO_ROOT/evals/harness/execute-agent.sh"
  REVIEW_SUITE="$REPO_ROOT/evals/suites/review-recall.yaml"
  AUDIT_SUITE="$REPO_ROOT/evals/suites/audit-recall.yaml"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/at.XXXXXX")"
  WS="$T/ws"; SNAP="$T/snap"
  mkdir -p "$WS"
  ( cd "$WS" && git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init )
  export EVAL_CLAUDE_BIN="$TESTS_DIR/fixtures/claude-stub.sh"
  export EVAL_MODEL="claude-fable-5-1"
  export STUB_SNAPSHOT_DIR="$SNAP"
  unset LOA_EVAL_ARM LOA_EVAL_ARM_TOGGLES LOA_EVAL_SUITE_FILE LOA_EVAL_SOURCE_COMMIT EVAL_EFFORT

  # --- synthetic prompt tree (the shape of 864069f2) ---
  PT="$T/tree"
  mkdir -p "$PT/.claude/loa" "$PT/.claude/rules" "$PT/.claude/data" \
    "$PT/.claude/skills/reviewing-code" "$PT/.claude/skills/auditing-security"
  printf '%s\n' "# Loa Framework Instructions" "" "## Three-Zone Model" "" "zones" "" \
    "## Karpathy Principles" "" "Every code-touching turn." "" "1. **Think before coding** — state assumptions." "" \
    "## Process Compliance" "" "rules" > "$PT/.claude/loa/CLAUDE.loa.md"
  echo "# Git Stash Safety" > "$PT/.claude/rules/stash-safety.md"
  echo "# Skill Frontmatter Invariants" > "$PT/.claude/rules/skill-invariants.md"
  printf '%s\n' "---" "paths:" '  - "grimoires/**"' "---" "# zone state" > "$PT/.claude/rules/zone-state.md"
  printf '%s\n' "---" "name: reviewing-code" "---" "# Review" "Review the diff." > "$PT/.claude/skills/reviewing-code/SKILL.md"
  printf '%s\n' "---" "name: auditing-security" "---" "# Audit" "" "### Coverage" "" \
    "Report every finding you actually observe." "" \
    "Confirm the review's demotions independently: for each high the review trailer counts under" \
    "\`excluded\`, either confirm it or tally it as a finding of your own." "" \
    "## Phase 2.5: Severity Tally" "" "Count every finding." > "$PT/.claude/skills/auditing-security/SKILL.md"
  printf '%s\n' "flatline_protocol:" "  code_review:" "    enabled: true" "  security_audit:" "    enabled: true" > "$PT/.loa.config.yaml"
  ( cd "$PT" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -q -m tree )
  export EVAL_PROMPT_TREE="$PT"

  for s in reviewing-code auditing-security; do
    cat > "$T/task-$s.yaml" <<YAML
id: at-$s
schema_version: 1
skill: $s
category: skill-quality
fixture: hello-world-ts
description: "arm toggle task"
prompt: "Read the instructions and carry them out."
agent:
  skill: $s
  artifacts: [review.md]
graders:
  - type: code
    script: file-exists.sh
    args: ["review.md"]
YAML
  done
}

teardown() {
  find "$T" -mindepth 1 -delete 2>/dev/null || true
  rmdir "$T" 2>/dev/null || true
}

run_arm() {  # run_arm <arm> <suite-file> <skill>
  LOA_EVAL_ARM="$1" LOA_EVAL_SUITE_FILE="$2" run "$EXEC" --task-yaml "$T/task-$3.yaml" --workspace "$WS"
}

@test "AT-1 both suites declare the canonical arm ids and the pre-registered threshold block" {
  [ "$(yq -r '[.ab.arms[].id] | join(",")' "$REVIEW_SUITE")" = "baseline,no_companion,no_karpathy,no_rule_files" ]
  [ "$(yq -r '[.ab.arms[].id] | join(",")' "$AUDIT_SUITE")" = "baseline,no_audit_delta" ]
  [ "$(yq -r '.ab.arms[] | select(.id=="no_companion") | .informational' "$REVIEW_SUITE")" = "true" ]
  yq -r '.ab.arms[] | select(.id=="no_karpathy") | .description' "$REVIEW_SUITE" | grep -q 'kernel block only'
  for s in "$REVIEW_SUITE" "$AUDIT_SUITE"; do
    [ "$(yq -r '.ab.threshold.trials_required' "$s")" = "3" ]
    [ "$(yq -r '.ab.threshold.coverage_required' "$s")" = "full" ]
    [ "$(yq -r '.ab.threshold.mean_recall_max_drop' "$s")" = "0.10" ]
    [ "$(yq -r '.ab.threshold.min_trial_recall_max_drop' "$s")" = "0.15" ]
    [ "$(yq -r '.ab.threshold.refuted_share_max_rise' "$s")" = "0.10" ]
    [ "$(yq -r '.ab.threshold.bootstrap | [.method, .level, .resample, .iterations] | join(",")' "$s")" = "percentile,0.90,fixtures,2000" ]
    # the existing freshness keys are untouched
    [ "$(yq -r '.ab.corpus_manifest' "$s")" = "evals/fixtures/review-prs/SHA256SUMS" ]
  done
}

@test "AT-2 baseline: every toggled surface is present at executor start and the row records the arm" {
  run_arm baseline "$REVIEW_SUITE" reviewing-code
  [ "$status" -eq 0 ]
  grep -q '^## Karpathy Principles' "$SNAP/.claude/loa/CLAUDE.loa.md"
  [ -f "$SNAP/.claude/rules/stash-safety.md" ]
  [ -f "$SNAP/.claude/rules/skill-invariants.md" ]
  [ "$(yq -r '.flatline_protocol.code_review.companion_voice' "$SNAP/.loa.config.yaml")" = "null" ]
  [ "$(jq -r '.arm' "$WS/.eval/executor.json")" = "baseline" ]
  [ "$(jq -c '.arm_toggles' "$WS/.eval/executor.json")" = "{}" ]
  [ "$(jq -r '.source_commit' "$WS/.eval/executor.json")" = "$(git -C "$PT" rev-parse HEAD)" ]
}

@test "AT-3 audit baseline: the delta paragraph is in the sandbox SKILL.md and the system prompt" {
  run_arm baseline "$AUDIT_SUITE" auditing-security
  [ "$status" -eq 0 ]
  grep -q "Confirm the review's demotions independently" "$SNAP/.claude/skills/auditing-security/SKILL.md"
  grep -q "Confirm the review's demotions independently" "$SNAP/system-prompt.md"
}

@test "AT-4 no_rule_files: the two rule files are absent at executor start; other rules stay; the source tree is untouched" {
  run_arm no_rule_files "$REVIEW_SUITE" reviewing-code
  [ "$status" -eq 0 ]
  [ ! -e "$SNAP/.claude/rules/stash-safety.md" ]
  [ ! -e "$SNAP/.claude/rules/skill-invariants.md" ]
  [ -f "$SNAP/.claude/rules/zone-state.md" ]
  [ -f "$PT/.claude/rules/stash-safety.md" ]
  [ -z "$(git -C "$PT" status --porcelain)" ]
  [ "$(jq -r '.arm' "$WS/.eval/executor.json")" = "no_rule_files" ]
  [ "$(jq -r '.arm_toggles.rule_files' "$WS/.eval/executor.json")" = "false" ]
}

@test "AT-5 no_karpathy: the section is gone at executor start, its neighbours stay, a sandbox constraints.json loses its Karpathy rows" {
  mkdir -p "$WS/.claude/data"
  printf '%s\n' '{"version":1,"constraints":[{"id":"C-KARPATHY-1","text":"Karpathy surgical"},{"id":"C-PROC-001","text":"implement only"}]}' \
    > "$WS/.claude/data/constraints.json"
  run_arm no_karpathy "$REVIEW_SUITE" reviewing-code
  [ "$status" -eq 0 ]
  ! grep -q 'Karpathy' "$SNAP/.claude/loa/CLAUDE.loa.md"
  ! grep -q 'Think before coding' "$SNAP/.claude/loa/CLAUDE.loa.md"
  grep -q '^## Three-Zone Model' "$SNAP/.claude/loa/CLAUDE.loa.md"
  grep -q '^## Process Compliance' "$SNAP/.claude/loa/CLAUDE.loa.md"
  [ "$(jq -r '[.constraints[].id] | join(",")' "$SNAP/.claude/data/constraints.json")" = "C-PROC-001" ]
  grep -q 'Karpathy' "$PT/.claude/loa/CLAUDE.loa.md"
}

@test "AT-6 no_companion: companion_voice is false in the sandbox config at executor start; the source config is untouched" {
  run_arm no_companion "$REVIEW_SUITE" reviewing-code
  [ "$status" -eq 0 ]
  [ "$(yq -r '.flatline_protocol.code_review.companion_voice' "$SNAP/.loa.config.yaml")" = "false" ]
  [ "$(yq -r '.flatline_protocol.security_audit.companion_voice' "$SNAP/.loa.config.yaml")" = "false" ]
  [ "$(yq -r '.flatline_protocol.code_review.enabled' "$SNAP/.loa.config.yaml")" = "true" ]
  [ "$(yq -r '.flatline_protocol.code_review.companion_voice' "$PT/.loa.config.yaml")" = "null" ]
}

@test "AT-7 no_audit_delta: the delta paragraph is gone from the sandbox SKILL.md and the system prompt; the removed text is kept" {
  run_arm no_audit_delta "$AUDIT_SUITE" auditing-security
  [ "$status" -eq 0 ]
  ! grep -q "demotions independently" "$SNAP/.claude/skills/auditing-security/SKILL.md"
  ! grep -q "demotions independently" "$SNAP/system-prompt.md"
  grep -q 'Report every finding you actually observe' "$SNAP/system-prompt.md"
  grep -q '^## Phase 2.5' "$SNAP/system-prompt.md"
  grep -q "Confirm the review's demotions independently" "$WS/.eval/arm-removed.txt"
  grep -q "demotions independently" "$PT/.claude/skills/auditing-security/SKILL.md"
}

@test "AT-8 the literal 'look for what the review did not' paragraph wins when present" {
  printf '%s\n' "---" "name: auditing-security" "---" "# Audit" "" \
    "Read the review first, then look for what the review did not." "" \
    "Confirm the review's demotions independently." > "$PT/.claude/skills/auditing-security/SKILL.md"
  run_arm no_audit_delta "$AUDIT_SUITE" auditing-security
  [ "$status" -eq 0 ]
  ! grep -q 'look for what the review did not' "$SNAP/system-prompt.md"
  grep -q 'demotions independently' "$SNAP/system-prompt.md"
}

@test "AT-9 an arm that cannot take effect fails the trial before the executor starts (exit 2, no CLI call)" {
  printf '%s\n' "---" "name: auditing-security" "---" "# Audit" "no delta here" > "$PT/.claude/skills/auditing-security/SKILL.md"
  run_arm no_audit_delta "$AUDIT_SUITE" auditing-security
  [ "$status" -eq 2 ]
  [ ! -e "$SNAP" ]
  printf '%s\n' "# Loa" "## Other" > "$PT/.claude/loa/CLAUDE.loa.md"
  run_arm no_karpathy "$REVIEW_SUITE" reviewing-code
  [ "$status" -eq 2 ]
  [ ! -e "$SNAP" ]
}

@test "AT-10 an undeclared arm, an unknown toggle or a malformed toggle JSON is exit 2" {
  run_arm no_such_arm "$REVIEW_SUITE" reviewing-code
  [ "$status" -eq 2 ]
  LOA_EVAL_ARM=x LOA_EVAL_ARM_TOGGLES='{"warp_drive":false}' run "$EXEC" --task-yaml "$T/task-reviewing-code.yaml" --workspace "$WS"
  [ "$status" -eq 2 ]
  LOA_EVAL_ARM=x LOA_EVAL_ARM_TOGGLES='[1]' run "$EXEC" --task-yaml "$T/task-reviewing-code.yaml" --workspace "$WS"
  [ "$status" -eq 2 ]
  LOA_EVAL_ARM='../x' run "$EXEC" --task-yaml "$T/task-reviewing-code.yaml" --workspace "$WS"
  [ "$status" -eq 2 ]
  [ ! -e "$SNAP" ]
}

@test "AT-11 explicit LOA_EVAL_ARM_TOGGLES and LOA_EVAL_SOURCE_COMMIT are honoured and recorded" {
  head_sha="$(git -C "$PT" rev-parse HEAD)"
  LOA_EVAL_ARM=custom LOA_EVAL_ARM_TOGGLES='{"rule_files":false}' LOA_EVAL_SOURCE_COMMIT="$head_sha" \
    run "$EXEC" --task-yaml "$T/task-reviewing-code.yaml" --workspace "$WS"
  [ "$status" -eq 0 ]
  [ ! -e "$SNAP/.claude/rules/stash-safety.md" ]
  [ "$(jq -r '.arm' "$WS/.eval/executor.json")" = "custom" ]
  [ "$(jq -r '.source_commit' "$WS/.eval/executor.json")" = "$head_sha" ]
}

@test "AT-12 a source commit that is not the prompt tree's HEAD, a non-hex one, toggles outside arm mode and baseline toggles are refused or ignored (audit r1 DISS-C-001, DISS-C-009)" {
  LOA_EVAL_ARM=custom LOA_EVAL_ARM_TOGGLES='{"rule_files":false}' LOA_EVAL_SOURCE_COMMIT=864069f2 \
    run "$EXEC" --task-yaml "$T/task-reviewing-code.yaml" --workspace "$WS"
  [ "$status" -eq 2 ]
  grep -q "not the prompt tree's HEAD" <<<"$output"
  LOA_EVAL_ARM=custom LOA_EVAL_ARM_TOGGLES='{"rule_files":false}' LOA_EVAL_SOURCE_COMMIT='not-a-sha' \
    run "$EXEC" --task-yaml "$T/task-reviewing-code.yaml" --workspace "$WS"
  [ "$status" -eq 2 ]
  # baseline never carries toggles
  LOA_EVAL_ARM=baseline LOA_EVAL_ARM_TOGGLES='{"rule_files":false}' \
    run "$EXEC" --task-yaml "$T/task-reviewing-code.yaml" --workspace "$WS"
  [ "$status" -eq 2 ]
  grep -q "baseline arm takes no toggles" <<<"$output"
  # outside arm mode a stale LOA_EVAL_ARM_TOGGLES is ignored: the rule file stays
  rm -rf "$WS"; mkdir -p "$WS"
  LOA_EVAL_ARM_TOGGLES='{"rule_files":false}' run "$EXEC" --task-yaml "$T/task-reviewing-code.yaml" --workspace "$WS"
  [ "$status" -eq 0 ]
  grep -q "LOA_EVAL_ARM_TOGGLES is set but LOA_EVAL_ARM is not" <<<"$output"
  [ -e "$SNAP/.claude/rules/stash-safety.md" ]
}

# --- cycle-130 Sprint 258 Task 1.6 (PRD AC-3.1, AC-3.2, AC-5.6; sprint AC-1.6, AC-1.10;
# DEC-0421, DEC-0431, DEC-0433). The ablation-2.0 arms through execute-agent.sh, and
# lib/sandbox-mount.sh called directly for the pipeline-shaped (whole-tree) mount.

ABL_SUITE_REL="evals/suites/ablation-2.0.yaml"
LIB_REL="evals/harness/lib/sandbox-mount.sh"

lib() {  # lib <function> <args…> — one library call in a strict subshell
  bash -c 'set -euo pipefail; source "$1"; shift; "$@"' _ "$REPO_ROOT/$LIB_REL" "$@"
}

# The prompt tree as the pipeline mounts it: a catalog with two default_effort
# entries and its .checksum, a second skill with an effort line, the beads
# state script, and an overrides/ file the manifest must skip.
extend_tree() {
  mkdir -p "$PT/.claude/defaults" "$PT/.claude/skills/implementing-tasks" "$PT/.claude/scripts/beads" "$PT/.claude/overrides"
  printf '%s\n' "providers:" "  anthropic:" "    models:" "      claude-opus-5-5:" "        params:" "          default_effort: high" \
    "      claude-fable-5-1:" "        params:" "          default_effort: xhigh" > "$PT/.claude/defaults/model-config.yaml"
  sha256sum_of "$PT/.claude/defaults/model-config.yaml" > "$PT/.claude/defaults/model-config.yaml.checksum"
  printf '%s\n' "---" "name: implementing-tasks" "effort: xhigh" "model: opus" "---" "# Implement" "effort: this body line stays" \
    > "$PT/.claude/skills/implementing-tasks/SKILL.md"
  cp "$REPO_ROOT/.claude/scripts/beads/update-beads-state.sh" "$PT/.claude/scripts/beads/"
  echo "operator override" > "$PT/.claude/overrides/local.md"
}
sha256sum_of() { bash -c 'source "$1"; sha256_portable "$2" | cut -d" " -f1' _ "$REPO_ROOT/.claude/scripts/compat-lib.sh" "$1"; }

# check-loa.sh's own integrity check, run inside the sandbox (its cwd-relative manifest)
integrity_in() {
  ( cd "$1" && bash -c 'source "$1" && { check_integrity || true; } && echo "FAILURES=$FAILURES"' _ "$REPO_ROOT/.claude/scripts/check-loa.sh" )
}

@test "AT-13 ablation-2.0 declares the nine canonical arms plus the four cycle-131 review-catch arms, task_types per arm, A8 absent with its evidence, integrity_clean on every runnable arm (AC-1.10; cycle-131 FR-5)" {
  S="$REPO_ROOT/$ABL_SUITE_REL"
  [ "$(yq -r '[.arms[].id] | join(",")' "$S")" = "a0_bare,a1_full,a2_no_sprint_plan,a3_one_voice,a4_no_gates,a5_no_flatline,a6_one_window,a7_effort_medium,a0_bare_fable,a1_review_only,a1_no_dissent,a1_full_openmount,a0_bare_matched,a0_bare_fable_matched,a8_no_ceremonies" ]   # the absent arm stays last (cycle-132: the two matched arms before it)
  [ "$(yq -r '[.arms[] | select((.task_types | join(",")) == "review-catch") | .id] | join(",")' "$S")" = "a0_bare_fable,a1_review_only,a1_no_dissent,a1_full_openmount,a0_bare_matched,a0_bare_fable_matched" ]
  [ "$(yq -r '[.arms[] | select(.eval_only == true) | .id] | join(",")' "$S")" = "a1_full_openmount" ]
  [ "$(yq -r '[.arms[] | select((.task_types | join(",")) == "build") | .id] | join(",")' "$S")" = "a2_no_sprint_plan,a4_no_gates,a5_no_flatline,a6_one_window" ]
  [ "$(yq -r '[.arms[] | select((.task_types | join(",")) == "all") | .id] | join(",")' "$S")" = "a0_bare,a1_full,a3_one_voice,a7_effort_medium" ]
  [ "$(yq -r '.arms[] | select(.id == "a8_no_ceremonies") | .absent' "$S")" = "true" ]
  yq -r '.arms[] | select(.id == "a8_no_ceremonies") | .evidence' "$S" | grep -q 'grep -rli sosyete .claude/ docs/'
  [ "$(yq -r '[.arms[] | select(.absent != true) | select((.took_effect // []) | contains(["integrity_clean"]) | not)] | length' "$S")" = "0" ]
  [ "$(yq -o=json -I=0 '.arms[] | select(.id == "a0_bare") | [.toggles, .phases, .effort]' "$S")" = '[{"loa_mount":false},["BARE"],"high"]' ]
  [ "$(yq -o=json -I=0 '.arms[] | select(.id == "a7_effort_medium") | .toggles' "$S")" = '{"effort":"medium"}' ]
  [ "$(yq -r '.phase_defaults.max_turns.BARE, .phase_defaults.timeout_min.BARE, .phase_defaults.models.REVIEW' "$S" | tr '\n' ,)" = "170,70,global.anthropic.claude-fable-5-1," ]
  [ "$(yq -r '.phase_sets.build | join(",")' "$S")" = "PLAN,IMPLEMENT,REVIEW,FIX,AUDIT,FIX" ]
  [ "$(yq -r '.rules.decision_states | length' "$S")" = "7" ]
  [ "$(yq -r '.rules.predicates | keys | join(",")' "$S")" = "inconclusive_by_degradation,investigate,keep,inconclusive,remove,simplify" ]   # DEC-0530: the degradation guard runs first
  [ "$(yq -r '.caps | [.cycle_usd, .run_usd, .reserve_usd] | join(",")' "$S")" = "1500,12,250" ]
  # resolve_arm_toggles: absent and undeclared are refused; a1_full and an undeclared baseline are {}
  run lib resolve_arm_toggles a8_no_ceremonies "$S"
  [ "$status" -eq 2 ]; grep -q 'declared absent' <<<"$output"
  run lib resolve_arm_toggles a9_nope "$S"
  [ "$status" -eq 2 ]; grep -q 'not declared' <<<"$output"
  run lib resolve_arm_toggles a1_full "$S"
  [ "$status" -eq 0 ]; [ "$output" = "{}" ]
  run lib resolve_arm_toggles a0_bare "$S"
  [ "$output" = '{"loa_mount":false}' ]
  run lib resolve_arm_toggles baseline "$S"
  [ "$output" = "{}" ]
  # the cycle-129 suites still resolve through ab.arms[]
  run lib resolve_arm_toggles no_rule_files "$REVIEW_SUITE"
  [ "$output" = '{"rule_files":false}' ]
}

@test "AT-14 a0_bare: no .claude/, CLAUDE.md or .loa.config.yaml at executor start, no --append-system-prompt-file, the task prompt only; skill effort is not read" {
  printf '%s\n' "---" "name: reviewing-code" "effort: xhigh" "---" "# Review" > "$PT/.claude/skills/reviewing-code/SKILL.md"
  export STUB_ARGV_FILE="$T/argv"
  run_arm a0_bare "$REPO_ROOT/$ABL_SUITE_REL" reviewing-code
  [ "$status" -eq 0 ]
  [ -d "$SNAP" ]
  [ ! -e "$SNAP/.claude" ] && [ ! -e "$SNAP/CLAUDE.md" ] && [ ! -e "$SNAP/.loa.config.yaml" ] && [ ! -e "$SNAP/system-prompt.md" ]
  [ ! -e "$WS/.claude" ] && [ ! -e "$WS/CLAUDE.md" ] && [ ! -e "$WS/.eval/skill-prompt.md" ]
  ! grep -qx -- '--append-system-prompt-file' "$T/argv"
  ! grep -qx -- '--effort' "$T/argv"
  grep -qxF 'Read the instructions and carry them out.' "$T/argv"
  [ "$(jq -r '.arm_evidence.loa_mount' "$WS/.eval/executor.json")" = "none" ]
  [ "$(jq -c '.arm_toggles' "$WS/.eval/executor.json")" = '{"loa_mount":false}' ]
  # a sandbox that already holds a mount-owned path cannot take the toggle: exit 2, no CLI call
  rm -rf "$SNAP"; mkdir -p "$WS/.claude"
  run_arm a0_bare "$REPO_ROOT/$ABL_SUITE_REL" reviewing-code
  [ "$status" -eq 2 ]
  [ ! -e "$SNAP" ]
}

@test "AT-15 a7_effort_medium through execute-agent: --effort medium on argv (over EVAL_EFFORT and the skill's own effort), no effort: in the sandbox SKILL.md frontmatter" {
  printf '%s\n' "---" "name: reviewing-code" "effort: xhigh" "---" "# Review" > "$PT/.claude/skills/reviewing-code/SKILL.md"
  export STUB_ARGV_FILE="$T/argv"
  EVAL_EFFORT=low run_arm a7_effort_medium "$REPO_ROOT/$ABL_SUITE_REL" reviewing-code
  [ "$status" -eq 0 ]
  [ "$(grep -x -A1 -- '--effort' "$T/argv" | tail -1)" = "medium" ]
  [ "$(grep -cx -- '--effort' "$T/argv")" -eq 1 ]
  ! grep -q '^effort:' "$SNAP/.claude/skills/reviewing-code/SKILL.md"
  grep -q '^effort: xhigh' "$PT/.claude/skills/reviewing-code/SKILL.md"
  E="$WS/.eval/executor.json"
  [ "$(jq -r '.effort' "$E")" = "medium" ]
  [ "$(jq -r '.arm_evidence.effort' "$E")" = "medium" ]
  [ "$(jq -r '.arm_evidence.effort_skills_stripped' "$E")" = "1/1" ]
  [ "$(jq -r '.arm_evidence.effort_catalog' "$E")" = "absent" ]
}

@test "AT-16 a7 on the whole-tree mount: every SKILL.md frontmatter stripped (body kept), every catalog default_effort medium, .checksum refreshed" {
  extend_tree
  W2="$T/ws2"; mkdir -p "$W2"
  run lib mount_prompt_surface "$W2" "$PT" -
  [ "$status" -eq 0 ]; [ "$output" = "mount=tree" ]
  [ -f "$W2/.loa.config.yaml" ] && [ -f "$W2/.claude/skills/auditing-security/SKILL.md" ] && [ -f "$W2/.claude/overrides/local.md" ]
  run lib apply_arm_toggles "$W2" '{"effort":"medium"}' a7_effort_medium
  [ "$status" -eq 0 ]
  grep -qx 'effort=medium' <<<"$output"
  grep -qx 'effort_skills_stripped=1/3' <<<"$output"
  grep -qx 'effort_catalog=default_effort=medium in 2 entries; .checksum refreshed' <<<"$output"
  # grep -L lists every skill: none carries a top-of-line effort: in its frontmatter
  [ "$(cd "$W2" && grep -L '^effort:' .claude/skills/*/SKILL.md | wc -l | tr -d ' ')" = "2" ]
  awk 'NR>1 && $0=="---"{exit} /^effort:/{f=1} END{exit f}' "$W2/.claude/skills/implementing-tasks/SKILL.md"
  grep -qx 'effort: this body line stays' "$W2/.claude/skills/implementing-tasks/SKILL.md"
  grep -qx 'model: opus' "$W2/.claude/skills/implementing-tasks/SKILL.md"
  [ "$(yq -r '[.. | select(tag == "!!map" and has("default_effort")) | .default_effort] | unique | join(",")' "$W2/.claude/defaults/model-config.yaml")" = "medium" ]
  [ "$(cat "$W2/.claude/defaults/model-config.yaml.checksum")" = "$(sha256sum_of "$W2/.claude/defaults/model-config.yaml")" ]
  [ "$(cat "$PT/.claude/defaults/model-config.yaml.checksum")" = "$(sha256sum_of "$PT/.claude/defaults/model-config.yaml")" ]
  grep -q 'default_effort: high' "$PT/.claude/defaults/model-config.yaml"
  # an unknown effort value cannot take effect
  run lib apply_arm_toggles "$W2" '{"effort":"turbo"}' x
  [ "$status" -eq 2 ]
}

@test "AT-17 a4_no_gates: both enabled keys false at executor start and LOA_ADVERSARIAL_REVIEW_ENFORCE=false in the executor env; it never leaks into another arm" {
  export EVAL_CLAUDE_BIN="$TESTS_DIR/fixtures/ablation/claude-ablation-stub.sh" STUB_FULL_ENV_FILE="$T/env"
  run_arm a4_no_gates "$REPO_ROOT/$ABL_SUITE_REL" reviewing-code
  [ "$status" -eq 0 ]
  [ "$(yq -r '.flatline_protocol.code_review.enabled' "$SNAP/.loa.config.yaml")" = "false" ]
  [ "$(yq -r '.flatline_protocol.security_audit.enabled' "$SNAP/.loa.config.yaml")" = "false" ]
  [ "$(yq -r '.flatline_protocol.code_review.enabled' "$PT/.loa.config.yaml")" = "true" ]
  grep -qx 'LOA_ADVERSARIAL_REVIEW_ENFORCE=false' "$T/env"
  [ "$(jq -r '.arm_evidence.arm_env' "$WS/.eval/executor.json")" = "LOA_ADVERSARIAL_REVIEW_ENFORCE=false" ]
  [ "$(jq -r '.arm_evidence.gates' "$WS/.eval/executor.json")" = "flatline_protocol.{code_review,security_audit}.enabled=false" ]
  # executor.json records the value the executor environment carried (audit LOW-A3)
  [ "$(jq -r '.adversarial_review_enforce' "$WS/.eval/executor.json")" = "false" ]
  # an inherited override never reaches an arm that did not declare it
  rm -rf "$SNAP" "$WS"; mkdir -p "$WS"
  # exported: bats `run` does not hand a prefix assignment to the command it runs (audit LOW-A3 round)
  export LOA_ADVERSARIAL_REVIEW_ENFORCE=false
  run_arm a1_full "$REPO_ROOT/$ABL_SUITE_REL" reviewing-code
  unset LOA_ADVERSARIAL_REVIEW_ENFORCE
  [ "$status" -eq 0 ]
  [ -s "$T/env" ]
  ! grep -q '^LOA_ADVERSARIAL_REVIEW_ENFORCE=' "$T/env" || false   # a bare `! cmd` never fails a bats test
  [ "$(jq -r '.adversarial_review_enforce' "$WS/.eval/executor.json")" = "unset" ]
  # the library also hands the variable to a caller-owned env file (pipeline-run.sh)
  W2="$T/ws2"; mkdir -p "$W2"
  ARM_ENV_FILE="$T/arm.env" run lib apply_arm_toggles "$W2" '{"gates":false}' a4_no_gates
  [ "$status" -eq 0 ]
  [ "$(cat "$T/arm.env")" = "LOA_ADVERSARIAL_REVIEW_ENFORCE=false" ]
}

@test "AT-18 a5_no_flatline leaves flatline_protocol.enabled false; a3_one_voice leaves companion_voice false in both gate blocks" {
  run_arm a5_no_flatline "$REPO_ROOT/$ABL_SUITE_REL" reviewing-code
  [ "$status" -eq 0 ]
  [ "$(yq -r '.flatline_protocol.enabled' "$SNAP/.loa.config.yaml")" = "false" ]
  [ "$(yq -r '.flatline_protocol.code_review.enabled' "$SNAP/.loa.config.yaml")" = "true" ]
  [ "$(jq -r '.arm_evidence.flatline' "$WS/.eval/executor.json")" = "flatline_protocol.enabled=false" ]
  rm -rf "$SNAP" "$WS"; mkdir -p "$WS"
  run_arm a3_one_voice "$REPO_ROOT/$ABL_SUITE_REL" reviewing-code
  [ "$status" -eq 0 ]
  [ "$(yq -r '.flatline_protocol.code_review.companion_voice' "$SNAP/.loa.config.yaml")" = "false" ]
  [ "$(yq -r '.flatline_protocol.security_audit.companion_voice' "$SNAP/.loa.config.yaml")" = "false" ]
}

@test "AT-19 a1_full takes no toggles: config and kernel unchanged, evidence is only the regenerated manifest" {
  run_arm a1_full "$REPO_ROOT/$ABL_SUITE_REL" reviewing-code
  [ "$status" -eq 0 ]
  E="$WS/.eval/executor.json"
  [ "$(jq -c '.arm_toggles' "$E")" = "{}" ]
  [ "$(jq -r '.arm_evidence | keys | join(",")' "$E")" = "manifest_files,manifest_sha256" ]
  cmp -s "$PT/.loa.config.yaml" "$SNAP/.loa.config.yaml"
  cmp -s "$PT/.claude/loa/CLAUDE.loa.md" "$SNAP/.claude/loa/CLAUDE.loa.md"
}

@test "AT-20 every runnable arm: the sandbox manifest is regenerated after its toggles and check-loa.sh integrity is green inside it; a tampered file then fails" {
  extend_tree
  S="$REPO_ROOT/$ABL_SUITE_REL"
  for arm in a0_bare a1_full a2_no_sprint_plan a3_one_voice a4_no_gates a5_no_flatline a6_one_window a7_effort_medium; do
    W2="$T/m-$arm"; mkdir -p "$W2"
    tg="$(lib resolve_arm_toggles "$arm" "$S")"
    if [[ "$(jq -r 'if has("loa_mount") then (.loa_mount | tostring) else "true" end' <<<"$tg")" != "false" ]]; then lib mount_prompt_surface "$W2" "$PT" - >/dev/null; fi
    ARM_EVIDENCE_FILE="$T/ev-$arm" lib apply_arm_toggles "$W2" "$tg" "$arm"
    ARM_EVIDENCE_FILE="$T/ev-$arm" lib regen_sandbox_manifest "$W2"
    if [[ "$arm" == "a0_bare" ]]; then
      grep -qx 'manifest_sha256=none' "$T/ev-$arm"
      [ ! -e "$W2/.claude" ]
      continue
    fi
    [ "$(grep '^manifest_sha256=' "$T/ev-$arm" | cut -d= -f2)" = "$(sha256sum_of "$W2/.claude/checksums.json")" ]
    [ "$(jq -r '.algorithm' "$W2/.claude/checksums.json")" = "sha256" ]
    [ "$(jq -r '.files | has(".claude/overrides/local.md") or has(".claude/checksums.json")' "$W2/.claude/checksums.json")" = "false" ]
    [ "$(jq -r '.files | length' "$W2/.claude/checksums.json")" = "$(cd "$W2" && find .claude -type f ! -path '.claude/overrides/*' ! -name checksums.json | wc -l | tr -d ' ')" ]
    out="$(integrity_in "$W2")"
    grep -q 'Integrity verified' <<<"$out"
    grep -qx 'FAILURES=0' <<<"$out"
  done
  # the manifest names the toggled bytes: a7's stripped SKILL.md hash, not the source's
  [ "$(jq -r '.files[".claude/skills/implementing-tasks/SKILL.md"]' "$T/m-a7_effort_medium/.claude/checksums.json")" = "$(sha256sum_of "$T/m-a7_effort_medium/.claude/skills/implementing-tasks/SKILL.md")" ]
  # meta: the integrity check is live — one changed file reads Tampered
  echo tamper >> "$T/m-a1_full/.claude/rules/zone-state.md"
  out="$(integrity_in "$T/m-a1_full")"
  grep -q 'Tampered: .claude/rules/zone-state.md' <<<"$out"
  ! grep -qx 'FAILURES=0' <<<"$out"
}

@test "AT-21 execute-agent in arm mode records the regenerated sandbox manifest digest" {
  run_arm a7_effort_medium "$REPO_ROOT/$ABL_SUITE_REL" reviewing-code
  [ "$status" -eq 0 ]
  [ "$(jq -r '.arm_evidence.manifest_sha256' "$WS/.eval/executor.json")" = "$(sha256sum_of "$WS/.claude/checksums.json")" ]
  [ "$(jq -r '.files[".claude/skills/reviewing-code/SKILL.md"]' "$WS/.claude/checksums.json")" = "$(sha256sum_of "$WS/.claude/skills/reviewing-code/SKILL.md")" ]
}

@test "AT-22 the materialiser's fixture path rule refuses a tree holding .claude/, CLAUDE.md, .loa.config.yaml, grimoires/ or .run/ at its top level" {
  for p in .claude/scripts CLAUDE.md .loa.config.yaml grimoires/loa .run; do
    F="$T/fx-$(echo "$p" | tr '/.' '__')"; mkdir -p "$F/src"
    case "$p" in */*|.run) mkdir -p "$F/$p" ;; *) echo x > "$F/$p" ;; esac
    run lib check_fixture_path_rule "$F"
    [ "$status" -eq 2 ]
    grep -q "holds paths the Loa mount owns: ${p%%/*}" <<<"$output"
  done
  F="$T/fx-clean"; mkdir -p "$F/src/.claude" "$F/tests"
  run lib check_fixture_path_rule "$F"
  [ "$status" -eq 0 ]
  # the committed smoke build fixture obeys the rule
  run lib check_fixture_path_rule "$REPO_ROOT/grimoires/loa/evals/ablation-2.0/smoke/smoke-build-01/fixture"
  [ "$status" -eq 0 ]
}

@test "AT-23 phase-set toggles belong to the pipeline: a2 and a6 are exit 2 on the single-skill path; A8 (absent) is exit 2; no CLI call" {
  for arm in a2_no_sprint_plan a6_one_window a8_no_ceremonies; do
    run_arm "$arm" "$REPO_ROOT/$ABL_SUITE_REL" reviewing-code
    [ "$status" -eq 2 ]
    [ ! -e "$SNAP" ]
  done
  run_arm a2_no_sprint_plan "$REPO_ROOT/$ABL_SUITE_REL" reviewing-code
  grep -q 'applies to the pipeline executor' <<<"$output"
  # the library records them as evidence for pipeline-run.sh
  W2="$T/ws2"; mkdir -p "$W2"
  run lib apply_arm_toggles "$W2" '{"sprint_plan":false,"context_resets":false}' x
  [ "$status" -eq 0 ]
  grep -q '^sprint_plan=' <<<"$output"
  grep -q '^context_resets=' <<<"$output"
}

@test "AT-24 write_sandbox_grimoire and init_sandbox_beads: ledger with sprint-1 planned, brief, review-catch sprint.md + reviewer.md, none for A2 or build; no grader word or arm id written" {
  extend_tree
  SM="$REPO_ROOT/grimoires/loa/evals/ablation-2.0/smoke"
  export LOA_EVAL_SUITE_FILE="$REPO_ROOT/$ABL_SUITE_REL"
  W2="$T/rc"; mkdir -p "$W2"
  run lib write_sandbox_grimoire "$W2" "$SM/smoke-review-01/task.yaml" a1_full sprint-1
  [ "$status" -eq 0 ]
  G="$W2/grimoires/loa"
  [ "$(jq -r '.cycles[0].sprints[0] | .local_label + " " + .status + " " + (.global_id | tostring)' "$G/ledger.json")" = "sprint-1 planned 1" ]
  [ "$(jq -r '.active_cycle' "$G/ledger.json")" = "cycle-001" ]
  ( PROJECT_ROOT="$W2" bash -c 'source "$1/.claude/scripts/ledger-lib.sh" && validate_ledger >/dev/null && [ "$(resolve_sprint sprint-1)" = 1 ]' _ "$REPO_ROOT" )
  [ "$(cat "$G/NOTES.md")" = "# NOTES" ]
  grep -qF "$(yq -r '.criterion' "$SM/smoke-review-01/task.yaml")" "$G/context/task-brief.md"
  grep -q '## Output contract' "$G/context/task-brief.md"
  grep -q 'pr/head.diff' "$G/sprint.md"
  grep -q -- '--diff-file pr/head.diff' "$G/sprint.md"
  grep -q '^## Sprint 1: ' "$G/sprint.md"
  grep -q '^## Success Criteria' "$G/sprint.md"
  grep -qF "$(head -1 "$REPO_ROOT/evals/fixtures/review-prs/pr-01/PR.md")" "$G/a2a/sprint-1/reviewer.md"
  ! grep -rqiE 'hidden|a[0-8]_[a-z]' "$W2/grimoires"
  # build task: no sprint.md (the PLAN phase writes it); A2: none even for review-catch
  W3="$T/b"; mkdir -p "$W3"
  lib write_sandbox_grimoire "$W3" "$SM/smoke-build-01/task.yaml" a1_full sprint-1 >/dev/null
  [ -f "$W3/grimoires/loa/context/task-brief.md" ] && [ -d "$W3/grimoires/loa/a2a/sprint-1" ]
  [ ! -e "$W3/grimoires/loa/sprint.md" ] && [ ! -e "$W3/grimoires/loa/a2a/sprint-1/reviewer.md" ]
  W4="$T/a2"; mkdir -p "$W4"
  lib write_sandbox_grimoire "$W4" "$SM/smoke-review-01/task.yaml" a2_no_sprint_plan sprint-1 >/dev/null
  [ ! -e "$W4/grimoires/loa/sprint.md" ]
  run lib write_sandbox_grimoire "$W4" "$SM/smoke-review-01/task.yaml" a1_full 'sprint-1;x'
  [ "$status" -eq 2 ]
  # beads: br when on PATH, else the opt-out marker through the sandbox's own script, else none
  W5="$T/beads"; mkdir -p "$W5"; lib mount_prompt_surface "$W5" "$PT" - >/dev/null
  LOA_EVAL_BR_BIN=/nonexistent/br run lib init_sandbox_beads "$W5" "slugify collapses separator runs"
  [ "$status" -eq 0 ]; [ "$output" = "beads=opt-out" ]
  [ "$(jq -r '.opt_out.active' "$W5/.run/beads-state.json")" = "true" ]
  W6="$T/nobeads"; mkdir -p "$W6"
  LOA_EVAL_BR_BIN=/nonexistent/br run lib init_sandbox_beads "$W6" "t"
  [ "$status" -eq 0 ]; [ "$output" = "beads=none" ]
  if command -v br >/dev/null 2>&1; then
    W7="$T/br"; mkdir -p "$W7"
    run lib init_sandbox_beads "$W7" "slugify collapses separator runs"
    [ "$status" -eq 0 ]; [ "$output" = "beads=br" ]
    ( cd "$W7" && br list --json 2>/dev/null ) | grep -q 'slugify collapses separator runs'
  fi
}

# --- cycle-132 Sprint 269 Task 1.7a (bd-gdl5s): the toggle vocabulary is one table ------------------------------------

@test "AT-c132-1 print_toggle_vocabulary is the toggle table: its keys are apply_arm_toggles' case labels (both ways), the mount stub's copy is byte-equal, and neither validate-suite.sh nor pipeline-run.sh keeps a hand copy" {
  LIB="$REPO_ROOT/evals/harness/lib/sandbox-mount.sh"
  vocab="$(bash -c 'source "$1" && print_toggle_vocabulary' _ "$LIB")"
  keys="$(cut -f1 <<<"$vocab" | sort)"
  # the case labels inside apply_arm_toggles (one per toggle, six spaces of indent, before the catch-all)
  labels="$(awk '/^apply_arm_toggles\(\) \{/ {f = 1} f && /^}/ {exit} f' "$LIB" | sed -n 's/^      \([a-z_][a-z_]*\))$/\1/p' | sort -u)"
  [ -n "$labels" ]
  [ "$keys" = "$labels" ] || { diff <(echo "$keys") <(echo "$labels"); false; }
  [ "$(cut -f1 <<<"$vocab" | sort | uniq -d)" = "" ]
  awk -F'\t' 'NF != 3 { exit 1 }' <<<"$vocab"
  stub="$(bash -c 'source "$1" && print_toggle_vocabulary' _ "$REPO_ROOT/evals/tests/fixtures/mount-lib-stub.sh")"
  [ "$stub" = "$vocab" ]
  # no hand-kept copy: the old literal lists are gone
  ! grep -q '"companion_voice", "karpathy_block"' "$REPO_ROOT/evals/harness/validate-suite.sh" || false
  ! grep -q 'flatline_protocol.code_review.companion_voice=false' "$REPO_ROOT/evals/harness/pipeline-run.sh" || false
  grep -q 'print_toggle_vocabulary' "$REPO_ROOT/evals/harness/validate-suite.sh"
  grep -q 'print_toggle_vocabulary' "$REPO_ROOT/evals/harness/pipeline-run.sh"
}

@test "AT-c132-2 bare_sessions: matched (cycle-132 FR-3) applies with loa_mount: false (evidence bare_sessions=matched); without it, or with another value, the toggle is refused" {
  mkdir -p "$WS"
  run bash -c 'source "$1"; ARM_EVIDENCE_FILE="$2" apply_arm_toggles "$3" "{\"loa_mount\": false, \"bare_sessions\": \"matched\"}" a0_bare_matched' _ \
    "$REPO_ROOT/evals/harness/lib/sandbox-mount.sh" "$T/ev.txt" "$WS"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qx 'bare_sessions=matched' "$T/ev.txt"
  grep -qx 'loa_mount=none' "$T/ev.txt"
  run bash -c 'source "$1"; ARM_EVIDENCE_FILE="$2" apply_arm_toggles "$3" "{\"bare_sessions\": \"matched\"}" x' _ \
    "$REPO_ROOT/evals/harness/lib/sandbox-mount.sh" "$T/ev2.txt" "$WS"
  [ "$status" -eq 2 ]; grep -q 'needs loa_mount: false' <<<"$output"
  run bash -c 'source "$1"; ARM_EVIDENCE_FILE="$2" apply_arm_toggles "$3" "{\"loa_mount\": false, \"bare_sessions\": \"double\"}" x' _ \
    "$REPO_ROOT/evals/harness/lib/sandbox-mount.sh" "$T/ev3.txt" "$WS"
  [ "$status" -eq 2 ]; grep -q 'bare_sessions=double (only matched is defined)' <<<"$output"
}
