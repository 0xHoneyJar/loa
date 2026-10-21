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

# --- cycle-131 Sprint 263 Task 1.2: oracle_closed, oracle_open_recorded, bare_model_fable,
# review_only_phases, no_review_dissent_envelope (PRD FR-1 AC 2, FR-5; SDD §5.2) ------------

# c131_suite — the fixture suite plus the cycle-131 arms, one rule each (Sprint 2 declares the real ones)
c131_suite() {
  S131="$T/suite-c131.yaml"
  cp "$SUITE" "$S131"
  yq -i '.arms += [
    {"id": "a1_closed", "task_types": ["review-catch"], "toggles": {}, "took_effect": ["oracle_closed"]},
    {"id": "a1_full_openmount", "task_types": ["review-catch"], "toggles": {"oracle_open": true}, "took_effect": ["oracle_open_recorded"]},
    {"id": "a0_bare_fable", "task_types": ["all"], "toggles": {"loa_mount": false, "bare_model": "fable"}, "phases": ["BARE"], "took_effect": ["bare_model_fable"]},
    {"id": "a1_review_only", "task_types": ["review-catch"], "toggles": {}, "phases": ["REVIEW"], "took_effect": ["review_only_phases"]},
    {"id": "a1_no_dissent", "task_types": ["review-catch"], "toggles": {"dissent": false}, "took_effect": ["no_review_dissent_envelope"]}]' "$S131"
}
te131() { local run="$1"; shift; run "$TE" --run-dir "$run" --suite-file "$S131" "$@"; }
gg() { git -C "$1" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "${@:2}"; }

# make_closed_run — a source repo (head commit H, fix commit F = the pin), a PR fixture and a
# run dir whose sandbox was materialised and overlaid by the real mount library
make_closed_run() {
  local src="$T/c-src" fx="$T/c-fx" rd="$T/c-run" w
  mkdir -p "$src/.claude/scripts" "$src/.claude/loa"
  printf 'gate head\n' > "$src/.claude/scripts/gate.sh"
  printf 'helper head\n' > "$src/.claude/scripts/helper.sh"
  printf 'loa\n' > "$src/.claude/loa/CLAUDE.loa.md"
  ( cd "$src" && git init -q && gg . add -A && gg . commit -qm head )
  CH="$(git -C "$src" rev-parse HEAD)"
  printf 'gate LATER fixed\n' > "$src/.claude/scripts/gate.sh"
  printf 'helper LATER fixed\n' > "$src/.claude/scripts/helper.sh"
  ( cd "$src" && gg . add -A && gg . commit -qm fix )
  CF="$(git -C "$src" rev-parse HEAD)"
  mkdir -p "$fx/head/.claude/scripts" "$fx/base/.claude/scripts"
  printf 'gate head\n' > "$fx/head/.claude/scripts/gate.sh"; printf 'gate base\n' > "$fx/base/.claude/scripts/gate.sh"
  printf 'diff --git a/.claude/scripts/gate.sh b/.claude/scripts/gate.sh\n--- a/.claude/scripts/gate.sh\n+++ b/.claude/scripts/gate.sh\n@@ -1 +1 @@\n-gate base\n+gate head\n' > "$fx/head.diff"
  printf 'name: pr-c\nhead_commit: "%s"\nfix_commit: "%s"\n' "$CH" "$CF" > "$fx/fixture.yaml"
  mkdir -p "$rd/meta" "$rd/sandbox/pr" "$rd/eval"
  w="$rd/sandbox"
  cp -a "$fx/head" "$fx/base" "$fx/head.diff" "$w/pr/"
  git -C "$w" init -q; printf '/.claude/\n' >> "$w/.git/info/exclude"; gg "$w" add -A; gg "$w" commit -qm base
  printf 'base_commit=%s\n' "$(git -C "$w" rev-parse HEAD)" > "$rd/meta/arm-evidence.txt"
  mkdir -p "$w/.claude"; cp -a "$src/.claude/." "$w/.claude/"
  ARM_EVIDENCE_FILE="$rd/meta/arm-evidence.txt" bash -c 'source "$1"; overlay_answer_paths "$2" "$3" head "$4" "$5"' _ \
    "$REPO_ROOT/evals/harness/lib/sandbox-mount.sh" "$w" "$fx" "$src" "$CF" 2>/dev/null
  echo a1_closed > "$rd/meta/arm"
  jq -n --arg sc "$CF" '{schema_version: 1, arm: "a1_closed", task_id: "rc-c", task_type: "review-catch", status: "completed",
                         source_commit: $sc, arm_toggles: {}, phases: [{name: "REVIEW", label: "REVIEW"}, {name: "AUDIT", label: "AUDIT"}]}' > "$rd/meta/pipeline.json"
  # the task yaml the runner passes (--task-yaml), its fixture outside the run dir
  mkdir -p "$T/c-suite/tasks/rc-c"
  printf 'id: rc-c\ntype: review-catch\nreview_catch: {fixture: "%s"}\n' "$fx" > "$T/c-suite/tasks/rc-c/task.yaml"
  CRD="$rd" CSRC="$src" CFX="$fx" CTY="$T/c-suite/tasks/rc-c/task.yaml"
}

@test "oracle_closed: OK on an overlaid run (fixture from --task-yaml, or from the overlay_fixture evidence)" {
  c131_suite; make_closed_run
  te131 "$CRD" --task-yaml "$CTY" --source-repo "$CSRC"
  [ "$status" -eq 0 ]
  line oracle_closed | grep -q ' OK ok head:2 answer paths (2 present), 2 later-only pinned versions'
  te131 "$CRD" --source-repo "$CSRC"       # no --task-yaml: the harness-written overlay_fixture
  [ "$status" -eq 0 ]
  te131 "$CRD"                              # no --source-repo: the evidence's overlay_source_tree
  [ "$status" -eq 0 ]
}

@test "oracle_closed: FAIL on an unmodified (later) mount, a stray later copy, a mutated path, a second sandbox commit, an unavailable fix commit, an open mount, a copy_source mismatch" {
  c131_suite; make_closed_run
  local W="$CRD/sandbox" ev="$CRD/meta/arm-evidence.txt"
  cp "$ev" "$T/ev.orig"
  # (a) an unmodified mount: the pinned (later) copy is back and the evidence says so
  git -C "$CSRC" show "$CF:.claude/scripts/gate.sh" > "$W/.claude/scripts/gate.sh"
  sed -i "s|^overlay_sha256=.claude/scripts/gate.sh=.*|overlay_sha256=.claude/scripts/gate.sh=$(python3 -I -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$W/.claude/scripts/gate.sh")|" "$ev"
  te131 "$CRD" --task-yaml "$CTY"
  [ "$status" -eq 1 ]
  line oracle_closed | grep -q ' FAIL FAIL (a) .claude/scripts/gate.sh: '
  cp "$T/ev.orig" "$ev"; printf 'gate head\n' > "$W/.claude/scripts/gate.sh"
  # (b) a stray copy outside pr/
  git -C "$CSRC" show "$CF:.claude/scripts/helper.sh" > "$W/.claude/scripts/helper.sh.bak"
  te131 "$CRD" --task-yaml "$CTY"
  [ "$status" -eq 1 ]
  line oracle_closed | grep -q ' FAIL FAIL (b) .claude/scripts/helper.sh.bak: byte-equal to the pinned .claude/scripts/helper.sh'
  rm "$W/.claude/scripts/helper.sh.bak"
  # (c) a path mutated after the overlay
  echo edited >> "$W/.claude/scripts/gate.sh"
  te131 "$CRD" --task-yaml "$CTY"
  [ "$status" -eq 1 ]
  line oracle_closed | grep -q 'FAIL (c) .claude/scripts/gate.sh: mount_mutated=.claude/scripts/gate.sh'
  printf 'gate head\n' > "$W/.claude/scripts/gate.sh"
  # (d) a second commit in the sandbox repository
  echo r > "$W/review.md"; gg "$W" add review.md; gg "$W" commit -qm later
  te131 "$CRD" --task-yaml "$CTY"
  [ "$status" -eq 1 ]
  line oracle_closed | grep -q 'FAIL (d) .git: commits'
  gg "$W" reset -q --hard HEAD~1; gg "$W" reflog expire --expire=now --all; gg "$W" gc -q --prune=now
  te131 "$CRD" --task-yaml "$CTY"
  [ "$status" -eq 0 ]
  # a fix commit the overlay could not read (PR #1286 F001): its paths were never pinned
  sed -i 's/^overlay_fix_commit=.*/overlay_fix_commit=unavailable/' "$ev"
  te131 "$CRD" --task-yaml "$CTY"
  [ "$status" -eq 1 ]; line oracle_closed | grep -q 'FAIL overlay_fix_commit=unavailable (the fix paths outside the PR were never pinned)'
  cp "$T/ev.orig" "$ev"
  # an open mount is never closed; a copy source other than source_commit fails first
  sed -i 's/^mount_overlay=.*/mount_overlay=none/' "$ev"
  te131 "$CRD" --task-yaml "$CTY"
  [ "$status" -eq 1 ]; line oracle_closed | grep -q 'mount_overlay=none (an open mount)'
  cp "$T/ev.orig" "$ev"
  jq --arg c "$CH" '.source_commit = $c' "$CRD/meta/pipeline.json" > "$T/x.json" && mv "$T/x.json" "$CRD/meta/pipeline.json"
  te131 "$CRD" --task-yaml "$CTY"
  [ "$status" -eq 1 ]; line oracle_closed | grep -q "copy_source $CF is not source_commit $CH"
}

@test "oracle_closed: the fixture never resolves inside the run dir (the agent-writable pr/)" {
  c131_suite; make_closed_run
  sed -i "s|^overlay_fixture=.*|overlay_fixture=$CRD/sandbox/pr|" "$CRD/meta/arm-evidence.txt"
  : > "$CRD/sandbox/pr/head.diff"
  te131 "$CRD" --source-repo "$CSRC"
  [ "$status" -eq 1 ]
  line oracle_closed | grep -q 'the PR fixture does not resolve'
}

@test "oracle_open_recorded: OK with mount_overlay=none and oracle_open=true; FAIL when either is missing" {
  c131_suite
  local rd="$T/runs/a1-review"
  echo a1_full_openmount > "$rd/meta/arm"
  printf 'mount_overlay=none\noracle_open=true\n' >> "$rd/meta/arm-evidence.txt"
  te131 "$rd"
  [ "$status" -eq 0 ]; line oracle_open_recorded | grep -q ' OK mount_overlay=none, oracle_open=true'
  sed -i '/^oracle_open=/d' "$rd/meta/arm-evidence.txt"
  te131 "$rd"
  [ "$status" -eq 1 ]; line oracle_open_recorded | grep -q 'no oracle_open=true'
  sed -i 's/^mount_overlay=none$/mount_overlay=head:4/' "$rd/meta/arm-evidence.txt"
  te131 "$rd"
  [ "$status" -eq 1 ]; line oracle_open_recorded | grep -q 'no mount_overlay=none in arm_evidence (got head:4)'
}

@test "bare_model_fable: OK when BARE used one Fable model at effort high; FAIL on Opus, a mixed record or another effort" {
  c131_suite
  local rd="$T/runs/a0-build"
  echo a0_bare_fable > "$rd/meta/arm"
  edit_json "$rd/meta/pipeline.json" '(.phases[] | select(.name == "BARE") | .models_used) = {"global.anthropic.claude-fable-5-1": 200}'
  te131 "$rd"
  [ "$status" -eq 0 ]; line bare_model_fable | grep -q ' OK BARE models_used global.anthropic.claude-fable-5-1, effort_requested high'
  edit_json "$rd/meta/pipeline.json" '(.phases[] | select(.name == "BARE") | .models_used) = {"global.anthropic.claude-opus-5-5": 200}'
  te131 "$rd"
  [ "$status" -eq 1 ]; line bare_model_fable | grep -q 'want exactly one global.anthropic.claude-fable'
  edit_json "$rd/meta/pipeline.json" '(.phases[] | select(.name == "BARE") | .models_used) = {"global.anthropic.claude-fable-5-1": 200, "global.anthropic.claude-opus-5-5": 3}'
  te131 "$rd"
  [ "$status" -eq 1 ]
  edit_json "$rd/meta/pipeline.json" '(.phases[] | select(.name == "BARE")) |= (.models_used = {"global.anthropic.claude-fable-5-1": 200} | .effort_requested = "xhigh")'
  te131 "$rd"
  [ "$status" -eq 1 ]; line bare_model_fable | grep -q 'effort_requested xhigh (want high)'
}

@test "review_only_phases: OK on a REVIEW-only record without auditor feedback; FAIL with an AUDIT record or an auditor feedback file" {
  c131_suite
  local rd="$T/runs/a1-review"
  echo a1_review_only > "$rd/meta/arm"
  te131 "$rd"
  [ "$status" -eq 1 ]; line review_only_phases | grep -q 'phases REVIEW,AUDIT, want REVIEW'
  edit_json "$rd/meta/pipeline.json" '.phases |= map(select(.name == "REVIEW"))'
  te131 "$rd"
  [ "$status" -eq 1 ]; line review_only_phases | grep -q 'auditor-sprint-feedback.md exists'
  rm "$rd/sandbox/grimoires/loa/a2a/sprint-1/auditor-sprint-feedback.md"
  te131 "$rd"
  [ "$status" -eq 0 ]; line review_only_phases | grep -q ' OK phases REVIEW; no auditor-sprint-feedback.md'
}

@test "no_review_dissent_envelope: OK without a review envelope, the gate disabled in the sandbox config and an audit envelope with a voice; FAIL otherwise" {
  c131_suite
  local rd="$T/runs/a1-review"
  echo a1_no_dissent > "$rd/meta/arm"
  printf 'flatline_protocol:\n  code_review:\n    enabled: false\n' > "$rd/sandbox/.loa.config.yaml"
  te131 "$rd"
  [ "$status" -eq 1 ]; line no_review_dissent_envelope | grep -q 'a review envelope exists (eval/adversarial-review.json)'
  rm "$rd/eval/adversarial-review.json"
  te131 "$rd"
  [ "$status" -eq 1 ]; line no_review_dissent_envelope | grep -q 'sandbox/grimoires/loa/a2a/sprint-1/adversarial-review.json'
  rm "$rd/sandbox/grimoires/loa/a2a/sprint-1/adversarial-review.json"
  te131 "$rd"
  [ "$status" -eq 0 ]; line no_review_dissent_envelope | grep -q ' OK no review envelope; code_review.enabled false; audit voices_succeeded 2'
  edit_json "$rd/eval/adversarial-audit.json" '.verdict_quality.voices_succeeded = 0'
  te131 "$rd"
  [ "$status" -eq 1 ]; line no_review_dissent_envelope | grep -q 'audit envelope voices_succeeded 0'
  printf 'flatline_protocol:\n  code_review:\n    enabled: true\n' > "$rd/sandbox/.loa.config.yaml"
  te131 "$rd"
  [ "$status" -eq 1 ]; line no_review_dissent_envelope | grep -q 'code_review.enabled is true'
}

@test "oracle_closed: a build run and an unmounted run pass with that evidence (a1_full lists the rule for every type)" {
  c131_suite
  echo a1_closed > "$T/runs/a1-build/meta/arm"
  te131 "$T/runs/a1-build"
  [ "$status" -eq 0 ]; line oracle_closed | grep -q ' OK not a review-catch run'
  local rd="$T/runs/a1-review"
  echo a1_closed > "$rd/meta/arm"
  edit_json "$rd/meta/pipeline.json" '.arm_toggles.loa_mount = false'
  te131 "$rd"
  [ "$status" -eq 1 ]; line oracle_closed | grep -q 'loa_mount: false but the sandbox has .claude/'
}

# --- cycle-132 Sprint 269 Tasks 1.7a / 1.7b: mount_cheval_ok, bare_sessions_matched (matched cells) -----------------

c132_suite() {
  S132="$T/suite-c132.yaml"
  cp "$SUITE" "$S132"
  yq -i '.arms += [
    {"id": "a1_cheval", "task_types": ["all"], "toggles": {}, "took_effect": ["mount_cheval_ok"]},
    {"id": "a0_bare_matched", "task_types": ["review-catch"], "toggles": {"loa_mount": false, "bare_sessions": "matched"}, "phases": ["BARE"],
     "took_effect": ["no_dot_claude", "no_system_prompt", "no_audit_rows", "integrity_clean", "bare_sessions_matched"]},
    {"id": "a0_bare_fable_matched", "task_types": ["review-catch"], "toggles": {"loa_mount": false, "bare_model": "fable", "bare_sessions": "matched"},
     "phases": ["BARE"], "took_effect": ["bare_model_fable", "bare_sessions_matched"]}]' "$S132"
  TY="$T/task-k.yaml"
  cp "$FX/tasks/rc-01/task.yaml" "$TY"
  yq -i '.review_catch.bare_sessions_matched = 2 | .review_catch.bare_sessions_matched_fable = 3' "$TY"
}
te132() { local run="$1"; shift; run "$TE" --run-dir "$run" --suite-file "$S132" "$@"; }
# make_cell_te <cell> <arm> <k> <valid…> — sessions s1 … sk copied from the A0 fixture run; meta/cell.json and meta/arm
make_cell_te() {
  local c="$1" arm="$2" k="$3" i; shift 3
  mkdir -p "$c/meta" "$c/sessions"; echo "$arm" > "$c/meta/arm"
  for i in $(seq 1 "$k"); do cp -a "$T/runs/a0-build" "$c/sessions/s$i"; echo "$arm" > "$c/sessions/s$i/meta/arm"; done
  printf '%s\n' "$@" | jq -R -s -c --argjson k "$k" '[split("\n")[] | select(length > 0)] as $v
    | {schema_version: 1, k: $k, sessions: [range(0; $k) as $j | {id: ("s\($j + 1)"), valid: ($v[$j] == "true"), status: "completed",
       run_dir: ("sessions/s\($j + 1)")}]}' > "$c/meta/cell.json"
}

@test "TE-c132-1 mount_cheval_ok: OK on mount_cheval=ok in the arm evidence; broken, none and absent FAIL" {
  c132_suite
  echo 'mount_cheval=ok' >> "$T/runs/a1-review/meta/arm-evidence.txt"
  te132 "$T/runs/a1-review" --arm a1_cheval
  [ "$status" -eq 0 ]
  line mount_cheval_ok | grep -q ' OK mount_cheval=ok$'
  sed -i 's/^mount_cheval=ok$/mount_cheval=broken:ImportError: cannot import name x/' "$T/runs/a1-review/meta/arm-evidence.txt"
  te132 "$T/runs/a1-review" --arm a1_cheval
  [ "$status" -eq 1 ]
  line mount_cheval_ok | grep -q 'FAIL mount_cheval=broken:ImportError: cannot import name x in arm_evidence (want ok; KF-050)'
  sed -i '/^mount_cheval=/d' "$T/runs/a1-review/meta/arm-evidence.txt"
  te132 "$T/runs/a1-review" --arm a1_cheval
  [ "$status" -eq 1 ]
  line mount_cheval_ok | grep -q 'mount_cheval=<absent>'
}

@test "TE-c132-2 bare_sessions_matched on a cell: k equals the task's value, s1 … sk attempted and nothing beyond, every valid session passes the bare rules; an invalid session is not read" {
  c132_suite
  C="$T/cell"; make_cell_te "$C" a0_bare_matched 2 true true
  te132 "$C" --task-yaml "$TY"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  line bare_sessions_matched | grep -q 'OK k 2 = the task'"'"'s bare_sessions_matched; s1 … s2 attempted; 2 valid session(s) pass'
  line no_dot_claude | grep -q ' OK 2 valid session(s) pass'
  # a valid session that broke a bare rule fails both the rule and the cell rule, naming it
  echo x > "$C/sessions/s2/sandbox/CLAUDE.md"
  te132 "$C" --task-yaml "$TY"
  [ "$status" -eq 1 ]
  line bare_sessions_matched | grep -q 'FAIL valid sessions failing: s2:no_dot_claude'
  line no_dot_claude | grep -q 'FAIL s2: sandbox has .claude/ or CLAUDE.md'
  # the same session marked invalid is never read
  jq '.sessions[1].valid = false' "$C/meta/cell.json" > "$T/c" && mv "$T/c" "$C/meta/cell.json"
  te132 "$C" --task-yaml "$TY"
  [ "$status" -eq 0 ]
  # k against the task, the session directories, the ids, and --task-yaml
  yq -i '.review_catch.bare_sessions_matched = 3' "$TY"
  te132 "$C" --task-yaml "$TY"
  [ "$status" -eq 1 ]; line bare_sessions_matched | grep -q 'cell k 2, the task'"'"'s review_catch.bare_sessions_matched is 3'
  yq -i '.review_catch.bare_sessions_matched = 2' "$TY"
  cp -a "$C/sessions/s1" "$C/sessions/s3"
  te132 "$C" --task-yaml "$TY"
  [ "$status" -eq 1 ]; line bare_sessions_matched | grep -q 'sessions/s3 exists beyond k 2'
  find "$C/sessions/s3" -depth -delete; find "$C/sessions/s2" -depth -delete
  te132 "$C" --task-yaml "$TY"
  [ "$status" -eq 1 ]; line bare_sessions_matched | grep -q 'session s2 was never attempted'
  te132 "$C"
  [ "$status" -eq 1 ]; line bare_sessions_matched | grep -q 'k 2 unverified: --task-yaml'
}

@test "TE-c132-3 bare_sessions_matched on a session's own run dir reads OK (the cell decides); on an ordinary run it FAILs; the Fable cell reads its own k and checks bare_model_fable on every valid session" {
  c132_suite
  C="$T/cell"; make_cell_te "$C" a0_bare_matched 2 true true
  te132 "$C/sessions/s1" --arm a0_bare_matched
  line bare_sessions_matched | grep -q 'OK session s1 of a matched cell'
  te132 "$T/runs/a0-build" --arm a0_bare_matched
  line bare_sessions_matched | grep -q 'FAIL not a matched cell'
  F="$T/cellf"; make_cell_te "$F" a0_bare_fable_matched 3 true true false
  te132 "$F" --task-yaml "$TY"
  [ "$status" -eq 1 ]   # the A0 fixture's BARE ran on Opus: bare_model_fable fails on s1
  line bare_model_fable | grep -q 'FAIL s1: BARE models_used'
  line bare_sessions_matched | grep -q 'OK k 3 = the task'"'"'s bare_sessions_matched_fable|bare_sessions_matched'
}
