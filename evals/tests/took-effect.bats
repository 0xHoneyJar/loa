#!/usr/bin/env bats
# =============================================================================
# evals/tests/took-effect.bats — cycle-130 Sprint 258 Task 1.8 (SDD D-4.2, §5.10; AC-1.8)
#
# evals/harness/took-effect.sh evaluates each arm's `took_effect` rule ids against
# a run directory's artefacts. Every rule gets a passing case (the arm's own fixture
# run) and a failing case (another arm's run judged under this arm, or a mutated
# copy). Fixtures: evals/tests/fixtures/ablation-runs/ (regen.sh rebuilds them).
# =============================================================================

setup() {
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  TE="$REPO_ROOT/evals/harness/took-effect.sh"
  FX="$TESTS_DIR/fixtures/ablation-runs"
  SUITE="$FX/suite.yaml"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/te.XXXXXX")"
  cp -a "$FX/runs" "$T/runs"
}

teardown() {
  find "$T" -mindepth 1 -delete 2>/dev/null || true
  rmdir "$T" 2>/dev/null || true
}

te() {  # te <run> [--arm ID] [--json]
  local run="$1"; shift
  run "$TE" --run-dir "$T/runs/$run" --suite-file "$SUITE" "$@"
}
line() { printf '%s\n' "$output" | grep -E "^arm [a-z0-9_]+: $1 " ; }   # the rule's line
edit_json() { jq "$2" "$1" > "$T/x.json" && mv "$T/x.json" "$1"; }

@test "every fixture run passes its own arm's rules (exit 0, final OK line)" {
  local r
  for r in a0-build a1-build a1-review a2-build a3-review a4-build a5-build a6-build a7-build refused-a4-review; do
    te "$r"
    [ "$status" -eq 0 ] || { echo "$r: $output"; return 1; }
    [[ "$(printf '%s\n' "$output" | sed -n '$p')" =~ ^arm\ [a-z0-9_]+:\ OK$ ]]
  done
}

@test "no_dot_claude: OK on A0; FAIL when the sandbox has CLAUDE.md" {
  te a0-build
  line no_dot_claude | grep -q ' OK '
  echo x > "$T/runs/a0-build/sandbox/CLAUDE.md"
  te a0-build
  [ "$status" -eq 1 ]
  line no_dot_claude | grep -q ' FAIL '
  [[ "$output" == *"arm a0_bare: FAIL (1 of 4 rules)"* ]]
}

@test "no_system_prompt: OK on A0; FAIL when an argv carries --append-system-prompt-file" {
  te a0-build
  line no_system_prompt | grep -q ' OK no --append-system-prompt-file in 1 argv'
  edit_json "$T/runs/a0-build/meta/phase-BARE.argv.json" '.argv += ["--append-system-prompt-file", "x.md"]'
  te a0-build
  [ "$status" -eq 1 ]
  line no_system_prompt | grep -q ' FAIL --append-system-prompt-file in phase-BARE.argv.json'
}

@test "no_audit_rows: OK on A0; FAIL when sandbox/.run/audit.jsonl exists" {
  mkdir -p "$T/runs/a0-build/sandbox/.run"; echo '{}' > "$T/runs/a0-build/sandbox/.run/audit.jsonl"
  te a0-build
  [ "$status" -eq 1 ]
  line no_audit_rows | grep -q ' FAIL '
}

@test "all_phases_present: OK on A1; FAIL with a record missing; OK on a cap-stopped prefix" {
  te a1-build
  line all_phases_present | grep -q ' OK phases PLAN,IMPLEMENT,REVIEW,FIX1,AUDIT,FIX2'
  edit_json "$T/runs/a1-build/meta/pipeline.json" '.phases |= map(select(.label != "AUDIT"))'
  te a1-build
  [ "$status" -eq 1 ]
  line all_phases_present | grep -q ' FAIL phases PLAN,IMPLEMENT,REVIEW,FIX1,FIX2, want PLAN,IMPLEMENT,REVIEW,FIX1,AUDIT,FIX2'
  edit_json "$T/runs/a1-build/meta/pipeline.json" '.phases |= .[0:2] | .status = "cap_failure"'
  te a1-build
  [ "$status" -eq 0 ]
  line all_phases_present | grep -q 'run stopped: cap_failure'
  # review-catch: the set is REVIEW,AUDIT
  te a1-review
  line all_phases_present | grep -q ' OK phases REVIEW,AUDIT'
}

@test "no_plan_phase: OK on A2; FAIL on a run with a PLAN record" {
  te a2-build
  line no_plan_phase | grep -q ' OK '
  te a1-build --arm a2_no_sprint_plan
  [ "$status" -eq 1 ]
  line no_plan_phase | grep -q ' FAIL 1 PLAN record'
}

@test "one_voice_planned: OK on A3; FAIL when an envelope plans the companion voice" {
  te a3-review
  line one_voice_planned | grep -q ' OK companion_voice review:planned=false audit:planned=false'
  te a1-review --arm a3_one_voice
  [ "$status" -eq 1 ]
  line one_voice_planned | grep -q 'review:planned=true'
  rm "$T/runs/a3-review/sandbox/grimoires/loa/a2a/sprint-1/adversarial-audit.json" "$T/runs/a3-review/eval/adversarial-audit.json"
  te a3-review
  [ "$status" -eq 1 ]
  line one_voice_planned | grep -q 'audit:missing'
}

@test "one_voice_planned reads eval/ first: a sandbox envelope rewritten after the gate changes nothing; the sandbox is read only without an eval/ copy (audit MEDIUM-A1)" {
  local s="$T/runs/a3-review/sandbox/grimoires/loa/a2a/sprint-1" e="$T/runs/a3-review/eval"
  # the agent's tree claims two voices; the harness copy says one
  edit_json "$s/adversarial-review.json" '.metadata.companion_voice.planned = true'
  te a3-review
  [ "$status" -eq 0 ]
  line one_voice_planned | grep -q 'review:planned=false'
  # the harness copy is the evidence: planned true there fails, whatever the sandbox says
  edit_json "$s/adversarial-review.json" '.metadata.companion_voice.planned = false'
  edit_json "$e/adversarial-review.json" '.metadata.companion_voice.planned = true'
  te a3-review
  [ "$status" -eq 1 ]
  line one_voice_planned | grep -q 'review:planned=true'
  # a legacy run without the eval/ copy falls back to the sandbox
  rm "$e/adversarial-review.json"
  te a3-review
  [ "$status" -eq 0 ]
  line one_voice_planned | grep -q 'review:planned=false'
}

@test "no_gate_phases + enforce_env_false: OK on A4; FAIL on a gated run" {
  te a4-build
  line no_gate_phases | grep -q ' OK '
  line enforce_env_false | grep -q ' OK LOA_ADVERSARIAL_REVIEW_ENFORCE=false in 2/2 phase env'
  te a1-build --arm a4_no_gates
  [ "$status" -eq 1 ]
  line no_gate_phases | grep -q ' FAIL gate records REVIEW,FIX1,AUDIT,FIX2'
  line enforce_env_false | grep -q ' FAIL '
}

@test "no_flatline_rows: OK on A5; FAIL with a flatline MODELINV row or without sprint.md" {
  te a5-build
  line no_flatline_rows | grep -q ' OK no flatline MODELINV rows; sprint.md present'
  printf '%s\n' '{"primitive_id":"MODELINV","payload":{"calling_primitive":"flatline-review"}}' >> "$T/runs/a5-build/eval/model-invoke.jsonl"
  te a5-build
  [ "$status" -eq 1 ]
  line no_flatline_rows | grep -q ' FAIL 1 flatline MODELINV row'
  te a2-build --arm a5_no_flatline
  [ "$status" -eq 1 ]
  line no_flatline_rows | grep -q 'no sandbox sprint.md'
}

@test "implementer_single_session: OK on A6; FAIL on separate sessions or a continuation that does not resume" {
  te a6-build
  line implementer_single_session | grep -q ' OK one session .* across 3 implementer record'
  te a1-build --arm a6_one_window
  [ "$status" -eq 1 ]
  line implementer_single_session | grep -q ' FAIL implementer session ids '
  edit_json "$T/runs/a6-build/meta/phase-FIX1.argv.json" '.argv |= (index("--resume") as $i | .[0:$i])'
  te a6-build
  [ "$status" -eq 1 ]
  line implementer_single_session | grep -q 'continuation argv does not resume .*FIX1'
}

@test "gates_separate_sessions: OK on A6; FAIL when AUDIT shares REVIEW's or the implementer's session" {
  te a6-build
  line gates_separate_sessions | grep -q ' OK review '
  local p="$T/runs/a6-build/meta/pipeline.json" rs is
  rs="$(jq -r '[.phases[] | select(.name == "REVIEW")][0].session_id' "$p")"
  is="$(jq -r '[.phases[] | select(.name == "PLAN")][0].session_id' "$p")"
  cp "$p" "$T/orig.json"
  edit_json "$p" "(.phases[] | select(.name == \"AUDIT\") | .session_id) = \"$rs\""
  te a6-build
  [ "$status" -eq 1 ] && line gates_separate_sessions | grep -q 'REVIEW and AUDIT share session'
  cp "$T/orig.json" "$p"
  edit_json "$p" "(.phases[] | select(.name == \"AUDIT\") | .session_id) = \"$is\""
  te a6-build
  [ "$status" -eq 1 ] && line gates_separate_sessions | grep -q 'a gate shares an implementer session'
}

@test "effort_flag_medium + skill_effort_stripped: OK on A7; FAIL on A1's argv and skills" {
  te a7-build
  line effort_flag_medium | grep -q ' OK --effort medium on 4/4 phases'
  line skill_effort_stripped | grep -q ' OK skill effort lines stripped 4/4'
  te a1-build --arm a7_effort_medium
  [ "$status" -eq 1 ]
  line effort_flag_medium | grep -q ' FAIL --effort medium on 0/5 phases'
  line skill_effort_stripped | grep -q ' FAIL 4/4 SKILL.md still carry effort:'
}

@test "skill_effort_stripped: a body line starting with effort: is not frontmatter and passes" {
  printf '\neffort: this body line explains the effort flag\n' >> "$T/runs/a7-build/sandbox/.claude/skills/reviewing-code/SKILL.md"
  # keep the manifest honest so only the rule under test is in play
  python3 -I -c '
import hashlib, json, sys
m = sys.argv[1]; d = json.load(open(m)); rel = ".claude/skills/reviewing-code/SKILL.md"
d["files"][rel] = hashlib.sha256(open(sys.argv[2] + "/" + rel, "rb").read()).hexdigest()
json.dump(d, open(m, "w"))' "$T/runs/a7-build/sandbox/.claude/checksums.json" "$T/runs/a7-build/sandbox"
  te a7-build
  line skill_effort_stripped | grep -q ' OK skill effort lines stripped 4/4'
  # the same line inside the frontmatter fails
  sed -i '2i effort: low' "$T/runs/a7-build/sandbox/.claude/skills/auditing-security/SKILL.md"
  te a7-build
  [ "$status" -eq 1 ]
  line skill_effort_stripped | grep -q ' FAIL 1/4 SKILL.md still carry effort:'
}

@test "applicability_refused on a run that was not refused: OK inside task_types, FAIL outside" {
  te a4-build
  line applicability_refused | grep -q ' OK applicable: bug-fix in task_types \["build"\]'
  te a1-review --arm a4_no_gates
  [ "$status" -eq 1 ]
  line applicability_refused | grep -q 'ran on review-catch outside task_types \["build"\] without a refusal record'
}

@test "an absent arm (A8) reports component-absent and passes" {
  te a1-build --arm a8_no_ceremonies
  [ "$status" -eq 0 ]
  [[ "$output" == "arm a8_no_ceremonies: absent (component-absent; no rules)" ]]
}

@test "integrity_clean: OK on A1; FAIL on a tampered or missing file, or no manifest_sha256; A0 has no mount" {
  te a1-build
  line integrity_clean | grep -q ' OK .* manifest entries verified'
  cp -a "$T/runs/a1-build" "$T/runs/a1-copy"
  echo tamper >> "$T/runs/a1-build/sandbox/.claude/loa/CLAUDE.loa.md"
  te a1-build
  [ "$status" -eq 1 ]
  line integrity_clean | grep -q ' FAIL 1 tampered, 0 missing .*tampered .claude/loa/CLAUDE.loa.md'
  rm "$T/runs/a1-copy/sandbox/.claude/skills/reviewing-code/SKILL.md"
  te a1-copy
  [ "$status" -eq 1 ]
  line integrity_clean | grep -q '0 tampered, 1 missing'
  edit_json "$T/runs/a5-build/meta/pipeline.json" 'del(.arm_evidence.manifest_sha256)'
  te a5-build
  [ "$status" -eq 1 ]
  line integrity_clean | grep -q 'no arm_evidence.manifest_sha256'
  te a0-build --arm a1_full
  line integrity_clean | grep -q ' OK no mount (loa_mount: false)'
}

@test "applicability_refused: OK on a refusal record; FAIL when the record names another arm or an applicable type" {
  te refused-a4-review
  [ "$status" -eq 0 ]
  line applicability_refused | grep -q ' OK refused review-catch'
  edit_json "$T/runs/refused-a4-review/meta/refused.json" '.type = "bug-fix"'
  te refused-a4-review
  [ "$status" -eq 1 ]
  line applicability_refused | grep -q 'include bug-fix, yet the run was refused'
  edit_json "$T/runs/refused-a4-review/meta/refused.json" '.arm = "a1_full" | .type = "review-catch"'
  te refused-a4-review --arm a4_no_gates
  [ "$status" -eq 1 ]
  line applicability_refused | grep -q "names arm 'a1_full'"
}

@test "an unknown rule id is a FAIL, never a silent pass" {
  yq '(.arms[] | select(.id == "a1_full") | .took_effect) += ["no_such_rule"]' "$SUITE" > "$T/suite.yaml"
  run "$TE" --run-dir "$T/runs/a1-build" --suite-file "$T/suite.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no_such_rule FAIL unknown rule id"* ]]
}

@test "--batch-dir walks every run; one failing run makes the batch exit 1" {
  run "$TE" --batch-dir "$T/runs" --suite-file "$SUITE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"took-effect: 10 runs, 0 failed"* ]]
  echo x > "$T/runs/a0-build/sandbox/CLAUDE.md"
  run "$TE" --batch-dir "$T/runs" --suite-file "$SUITE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"took-effect: 10 runs, 1 failed"* ]]
}

@test "--json prints one object per run with per-rule evidence" {
  te a7-build --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.arm + " " + (.ok | tostring) + " " + ([.rules[].rule] | join(","))' <<<"$output")" = "a7_effort_medium true effort_flag_medium,skill_effort_stripped,integrity_clean" ]
}

@test "usage: no suite, an undeclared arm, both run and batch dirs → exit 2" {
  run "$TE" --run-dir "$T/runs/a1-build"
  [ "$status" -eq 2 ]
  te a1-build --arm a9_nope
  [ "$status" -eq 2 ]
  run "$TE" --run-dir "$T/runs/a1-build" --batch-dir "$T/runs" --suite-file "$SUITE"
  [ "$status" -eq 2 ]
}
