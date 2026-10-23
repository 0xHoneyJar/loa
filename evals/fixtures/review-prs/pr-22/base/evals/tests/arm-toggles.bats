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
