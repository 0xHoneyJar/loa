#!/usr/bin/env bats
# =============================================================================
# evals/tests/pipeline-run.bats — cycle-130 Sprint 258 Tasks 1.7 + 1.12
# (SDD §1.4 D-4.1 … D-4.10, §5.6; sprint.md AC-1.7, AC-1.12, AC-1.14; PRD AC-4.x)
#
# evals/harness/pipeline-run.sh drives Loa's phases as separate CLI sessions in a
# sandbox repository. Here the CLI is evals/tests/fixtures/claude-stub-pipeline.sh,
# docker is fixtures/docker-stub.sh, and the executor runs from a temporary copy of
# the harness (make_harness) whose lib/sandbox-mount.sh is fixtures/mount-lib-stub.sh:
# the shipped script sources its library by a literal path only (eval.yml trust
# boundary), so there is no environment override to point. The executor runs the CLI under
# `env -i`, which strips the stubs' control variables, so each test reaches the
# stubs through generated wrappers ($T/claude, $T/docker) that first record the
# environment and descriptors the executor gave them, then load $T/stub.env.
# =============================================================================

setup() {
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  FP="$REPO_ROOT/evals/harness/fingerprint.sh"
  STUB="$TESTS_DIR/fixtures/claude-stub-pipeline.sh"
  DSTUB="$TESTS_DIR/fixtures/docker-stub.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/pr.XXXXXX")"
  export LOA_EVAL_WATCHDOG_POLL_S=0.1
  export LOA_EVAL_PRICING_JSON='{"global.anthropic.claude-opus-5-5":{"input_per_mtok":4000000,"output_per_mtok":20000000},"global.anthropic.claude-fable-5-1":{"input_per_mtok":10000000,"output_per_mtok":50000000}}'
  export LOA_EVAL_CREDS_HOME="$T/home"
  : > "$T/stub.env"
  make_harness
  make_source_tree
  cp "$TESTS_DIR/fixtures/ablation-runs/suite.yaml" "$T/suite.yaml"   # B's suite file as landed
  make_tasks
  make_wrappers
}

teardown() {
  chmod -R u+rwx "$T" 2>/dev/null || true
  find "$T" -mindepth 1 -delete 2>/dev/null || true
  rmdir "$T" 2>/dev/null || true
}

make_source_tree() {
  local s
  mkdir -p "$T/src/.claude/loa" "$T/src/.claude/scripts"
  for s in planning-sprints implementing-tasks reviewing-code auditing-security; do
    mkdir -p "$T/src/.claude/skills/$s"
    printf -- '---\nname: %s\neffort: xhigh\n---\nbody\n' "$s" > "$T/src/.claude/skills/$s/SKILL.md"
  done
  echo "loa" > "$T/src/.claude/loa/CLAUDE.loa.md"
  printf 'flatline_protocol:\n  enabled: true\n  code_review:\n    enabled: true\n  security_audit:\n    enabled: true\n' > "$T/src/.loa.config.yaml"
  ( cd "$T/src" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm init )
  # the operator's credential directories (copied per run in container mode)
  mkdir -p "$T/home/.aws" "$T/home/.claude/projects/big" "$T/home/.codex/sessions"
  echo "[default]" > "$T/home/.aws/config"
  echo "{}" > "$T/home/.claude/settings.json"
  echo "history" > "$T/home/.claude/history.jsonl"
  echo "{}" > "$T/home/.codex/auth.json"
  echo "model = 'x'" > "$T/home/.codex/config.toml"
  echo '{"claudeAiOauth": "subscription"}' > "$T/home/.claude/.credentials.json"
}

# a temporary copy of the harness: the stub mount library sits at the literal path
# pipeline-run.sh sources (lib/sandbox-mount.sh)
make_harness() {
  H="$T/h/evals/harness"
  mkdir -p "$H/lib"
  cp "$REPO_ROOT/evals/harness/pipeline-run.sh" "$REPO_ROOT/evals/harness/fingerprint.sh" "$H/"
  cp -a "$REPO_ROOT/evals/harness/lib/phase-prompts" "$H/lib/"
  cp "$TESTS_DIR/fixtures/mount-lib-stub.sh" "$H/lib/sandbox-mount.sh"
  PR="$H/pipeline-run.sh"
}

make_tasks() {
  # build task: fixture tree beside a sibling hidden/ directory that must never be copied
  local b="$T/suite/tasks/bf-01" r="$T/suite/tasks/rc-01" p="$T/prs/pr-x"
  mkdir -p "$b/fx/src" "$b/hidden/tests"
  echo 'print(1)' > "$b/fx/src/app.py"
  echo 'assert False' > "$b/hidden/tests/test_secret.py"
  printf 'Make the app print two.\n' > "$b/TASK.md"
  cat > "$b/task.yaml" <<'YAML'
id: bf-01
schema_version: 1
type: bug-fix
fixture: fx
criterion: "the app prints two"
test_command: ["python3", "-m", "pytest", "-q", "tests"]
YAML
  # review-catch task: a PR fixture outside the task dir
  mkdir -p "$p/base/lib" "$p/head/lib" "$r"
  echo 'a=1' > "$p/base/lib/x.sh"; echo 'a=2' > "$p/head/lib/x.sh"
  printf -- '--- a/lib/x.sh\n+++ b/lib/x.sh\n@@ -1 +1 @@\n-a=1\n+a=2\n' > "$p/head.diff"
  printf '# PR\nChange a.\n' > "$p/PR.md"
  printf '# Review instructions\nReview it.\n' > "$p/REVIEW-INSTRUCTIONS.md"
  printf '# Audit instructions\nAudit it.\n' > "$p/AUDIT-INSTRUCTIONS.md"
  printf 'name: pr-x\ndescription: "planted defects live elsewhere"\n' > "$p/fixture.yaml"
  printf 'Review the pull request in pr/.\n' > "$r/TASK.md"
  cat > "$r/task.yaml" <<YAML
id: rc-01
schema_version: 1
type: review-catch
fixture: null
criterion: "review the change"
review_catch: {fixture: "$p"}
YAML
  BUILD="$b/task.yaml" REVIEWC="$r/task.yaml"
}

make_wrappers() {
  mkdir -p "$T/log" "$T/dlog"
  cat > "$T/claude" <<EOF
#!/usr/bin/env bash
env | sed -E 's/^(AWS_BEARER_TOKEN_BEDROCK)=.*/\1=<set>/' > "$T/log/pending.env"   # key name only, never the value
if [[ -n "\${AWS_BEARER_TOKEN_BEDROCK:-}" ]]; then
  if [[ "\$AWS_BEARER_TOKEN_BEDROCK" == "\$(cat "$T/token" 2>/dev/null)" ]]; then echo match; else echo mismatch; fi >> "$T/log/token.check"
fi
ls "/proc/\$\$/fd" > "$T/log/pending.fds" 2>/dev/null || true
set -a; . "$T/stub.env"; set +a
export STUB_LOG_DIR="$T/log"
exec "$STUB" "\$@"
EOF
  cat > "$T/docker" <<EOF
#!/usr/bin/env bash
export DOCKER_STUB_LOG="$T/dlog" DOCKER_STUB_CLAUDE="$T/claude"
[[ -f "$T/docker.env" ]] && { set -a; . "$T/docker.env"; set +a; }
exec "$DSTUB" "\$@"
EOF
  chmod +x "$T/claude" "$T/docker"
}

# run_pr <arm> [task-yaml] [extra args…] — host executor unless --executor given
run_pr() {
  local arm="$1" task="${2:-$BUILD}"; shift; [[ $# -gt 0 ]] && shift
  run "$PR" --task-yaml "$task" --arm "$arm" --run-dir "$T/run" --run-id "r-$arm" --trial 1 \
    --source-tree "$T/src" --suite-file "$T/suite.yaml" --executor host --claude-bin "$T/claude" "$@"
}
labels() { jq -r '[.phases[] | .label] | join(",")' "$T/run/meta/pipeline.json"; }
ran()    { jq -r '[.phases[] | select(.skipped == false) | .label] | join(",")' "$T/run/meta/pipeline.json"; }
argv_of() { tr '\0' '\n' < "$T/log/call-$1.argv"; }   # argv_of <n>
call_for() { grep -lx "$1" "$T"/log/call-*.phase | sed -n '1p' | sed 's/.*call-\([0-9]*\)\.phase/\1/'; }

# --- plan -------------------------------------------------------------------------

@test "dry-run: A1 build plan lists PLAN IMPLEMENT REVIEW FIX1? AUDIT FIX2? and creates nothing" {
  run_pr a1_full "$BUILD" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"phases PLAN,IMPLEMENT,REVIEW,FIX1?,AUDIT,FIX2?"* ]]
  [[ "$output" == *"phase 1 PLAN model=global.anthropic.claude-opus-5-5 max_turns=30 timeout_s=900"* ]]
  [[ "$output" == *"phase 3 REVIEW model=global.anthropic.claude-fable-5-1"* ]]
  [ ! -e "$T/run" ]
}

@test "dry-run: A0 is one BARE phase with --max-turns 170 and the summed 70-minute timeout" {
  run_pr a0_bare "$BUILD" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"phases BARE"* ]]
  [[ "$output" == *"phase 1 BARE model=global.anthropic.claude-opus-5-5 max_turns=170 timeout_s=4200 effort=high"* ]]
  # 170 = PLAN 30 + IMPLEMENT 60 + 2 x FIX 40 ; 70 min = 15 + 25 + 2 x 15
  [ $((30 + 60 + 2 * 40)) -eq 170 ] && [ $((15 + 25 + 2 * 15)) -eq 70 ]
}

@test "dry-run: BARE without a suite declaration is the sum of the implementer caps" {
  yq -i 'del(.phase_defaults.max_turns.BARE) | del(.phase_defaults.timeout_min.BARE)' "$T/suite.yaml"
  run_pr a0_bare "$BUILD" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"max_turns=170 timeout_s=4200"* ]]
}

# --- AC-1.7 phase sets per arm ------------------------------------------------------------

@test "A1: six phase records in order, FIX skipped on APPROVED, status completed, exit 0" {
  run_pr a1_full
  [ "$status" -eq 0 ]
  [ "$(labels)" = "PLAN,IMPLEMENT,REVIEW,FIX1,AUDIT,FIX2" ]
  [ "$(ran)" = "PLAN,IMPLEMENT,REVIEW,AUDIT" ]
  [ "$(jq -r '.status' "$T/run/meta/pipeline.json")" = completed ]
  [ "$(jq -r '[.phases[] | select(.label == "FIX1")][0].reason' "$T/run/meta/pipeline.json")" = "preceding gate verdict APPROVED" ]
  [ "$(jq -r '.spent_usd' "$T/run/meta/pipeline.json")" = 2 ]
  [ "$(jq -r '.source_commit' "$T/run/meta/pipeline.json")" = "$(git -C "$T/src" rev-parse HEAD)" ]
}

@test "A1: FIX1 runs on a CHANGES_REQUIRED review trailer and FIX2 on a CHANGES_REQUIRED audit trailer" {
  printf 'STUB_VERDICT_REVIEW=CHANGES_REQUIRED\nSTUB_VERDICT_AUDIT=CHANGES_REQUIRED\n' > "$T/stub.env"
  run_pr a1_full
  [ "$status" -eq 0 ]
  [ "$(ran)" = "PLAN,IMPLEMENT,REVIEW,FIX1,AUDIT,FIX2" ]
  [ "$(jq -r '[.phases[] | select(.label == "REVIEW")][0].verdict' "$T/run/meta/pipeline.json")" = CHANGES_REQUIRED ]
}

@test "A1: only the review gate requests changes → FIX1 runs, FIX2 is skipped" {
  printf 'STUB_VERDICT_REVIEW=CHANGES_REQUIRED\n' > "$T/stub.env"
  run_pr a1_full
  [ "$status" -eq 0 ]
  [ "$(ran)" = "PLAN,IMPLEMENT,REVIEW,FIX1,AUDIT" ]
}

@test "snapshots: a sandbox commit after IMPLEMENT and after each FIX, bundles and index.json" {
  printf 'STUB_VERDICT_REVIEW=CHANGES_REQUIRED\nSTUB_VERDICT_AUDIT=CHANGES_REQUIRED\n' > "$T/stub.env"
  run_pr a1_full
  [ "$status" -eq 0 ]
  local p="$T/run/meta/pipeline.json" impl fix1 fix2
  impl="$(jq -r '.snapshots.implement' "$p")"; fix1="$(jq -r '.snapshots.fix1' "$p")"; fix2="$(jq -r '.snapshots.fix2' "$p")"
  [[ "$impl" =~ ^[0-9a-f]{40}$ ]] && [[ "$fix1" =~ ^[0-9a-f]{40}$ ]] && [[ "$fix2" =~ ^[0-9a-f]{40}$ ]]
  [ "$impl" != "$fix1" ] && [ "$fix1" != "$fix2" ]
  [ "$(jq -r '[.phases[] | select(.label == "IMPLEMENT")][0].snapshot' "$p")" = "$impl" ]
  [ -f "$T/run/snapshots/IMPLEMENT.bundle" ] && [ -f "$T/run/snapshots/FIX1.bundle" ] && [ -f "$T/run/snapshots/FIX2.bundle" ]
  [ "$(jq -r '.fix1' "$T/run/snapshots/index.json")" = "$fix1" ]
  # the snapshot carries the agent's work and not the mount
  git -C "$T/run/sandbox" show "$impl:work.txt" | grep -qx IMPLEMENT
  run git -C "$T/run/sandbox" ls-tree -r --name-only "$fix2"
  [[ "$output" != *".claude/"* ]] && [[ "$output" != *"grimoires/"* ]]
  # the base commit is the fixture tree alone
  run git -C "$T/run/sandbox" ls-tree -r --name-only "$(jq -r '.base' "$T/run/snapshots/index.json")"
  [ "$output" = "src/app.py" ]
}

@test "A2: no PLAN record and no sprint.md before IMPLEMENT" {
  run_pr a2_no_sprint_plan
  [ "$status" -eq 0 ]
  [ "$(labels)" = "IMPLEMENT,REVIEW,FIX1,AUDIT,FIX2" ]
  [ ! -e "$T/run/sandbox/grimoires/loa/sprint.md" ]
  grep -q 'there is no sprint plan' "$T/run/meta/prompt-IMPLEMENT.md"
}

@test "A4: ends after IMPLEMENT and the phase env carries LOA_ADVERSARIAL_REVIEW_ENFORCE=false" {
  run_pr a4_no_gates
  [ "$status" -eq 0 ]
  [ "$(labels)" = "PLAN,IMPLEMENT" ]
  [ "$(jq -r '.env.LOA_ADVERSARIAL_REVIEW_ENFORCE' "$T/run/meta/phase-IMPLEMENT.argv.json")" = false ]
  grep -qx 'LOA_ADVERSARIAL_REVIEW_ENFORCE=false' "$T/log/call-2.env"
}

@test "arm env: the library's ARM_ENV_FILE lines reach the phase env, LOA_* keys only" {
  export STUB_ARM_ENV_EXTRA='PATH=/evil'
  run_pr a4_no_gates
  [ "$status" -eq 0 ]
  grep -qx 'LOA_ADVERSARIAL_REVIEW_ENFORCE=false' "$T/run/meta/arm-env"
  grep -qx 'PATH=/evil' "$T/run/meta/arm-env"
  ! grep -qx 'PATH=/evil' "$T"/log/call-*.env
  [ "$(grep -c '^LOA_ADVERSARIAL_REVIEW_ENFORCE=' "$T/log/call-1.env")" -eq 1 ]
}

@test "mount library: sourced by its literal in-tree path; LOA_EVAL_MOUNT_LIB is ignored" {
  printf 'mount_prompt_surface() { return 2; }\n' > "$T/evil-lib.sh"
  LOA_EVAL_MOUNT_LIB="$T/evil-lib.sh" run_pr a1_full
  [ "$status" -eq 0 ]
  [ "$(jq -r '.arm_evidence.mount' "$T/run/meta/pipeline.json")" = whole_tree ]
}

@test "trust boundary: no shipped harness script sources a variable path, evals, or sources .claude/ code" {
  # the eval.yml "Validate grader trust boundary" patterns, over this sprint's harness files
  local f line bad=0
  for f in "$REPO_ROOT"/evals/harness/{pipeline-run,fingerprint,ablation-row,took-effect}.sh; do
    while IFS= read -r line; do
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      if grep -qE '(^|[;&|])[[:space:]]*(source|\.)[ \t]+.*(\$|`)' <<<"$line"; then echo "source: $f: $line"; bad=1; fi
      if grep -qE '(^|[;&|])[[:space:]]*eval[ \t]+.*(\$|`)' <<<"$line"; then echo "eval: $f: $line"; bad=1; fi
    done < "$f"
    ! grep -nE '^[^#]*(source|\. ).*\.claude/' "$f" || bad=1
  done
  [ "$bad" -eq 0 ]
}

@test "A1: no phase env carries LOA_ADVERSARIAL_REVIEW_ENFORCE" {
  run_pr a1_full
  [ "$status" -eq 0 ]
  ! grep -q 'LOA_ADVERSARIAL_REVIEW_ENFORCE' "$T"/log/call-*.env
}

@test "A3: the REVIEW and AUDIT envelopes carry companion_voice.planned false" {
  run_pr a3_one_voice
  [ "$status" -eq 0 ]
  [ "$(jq -r '.metadata.companion_voice.planned' "$T/run/eval/adversarial-review.json")" = false ]
  [ "$(jq -r '.metadata.companion_voice.planned' "$T/run/eval/adversarial-audit.json")" = false ]
  [ "$(yq -r '.flatline_protocol.code_review.companion_voice' "$T/run/sandbox/.loa.config.yaml")" = false ]
  [ "$(jq -c '.arm_toggles' "$T/run/meta/pipeline.json")" = '{"companion_voice":false}' ]
}

sha_of() { python3 -I -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1"; }

@test "envelopes: each gate's envelope reaches eval/ once at the gate with envelope_sha256; a FIX that rewrites the sandbox copy leaves eval/ unchanged (audit MEDIUM-A1)" {
  printf 'STUB_VERDICT_REVIEW=CHANGES_REQUIRED\nSTUB_TAMPER_ENVELOPE_FIX=review\n' > "$T/stub.env"
  run_pr a1_full
  [ "$status" -eq 0 ]
  [ "$(ran)" = "PLAN,IMPLEMENT,REVIEW,FIX1,AUDIT" ]
  local p="$T/run/meta/pipeline.json" e="$T/run/eval/adversarial-review.json"
  local s="$T/run/sandbox/grimoires/loa/a2a/sprint-1/adversarial-review.json"
  [ -f "$e" ] && [ -f "$T/run/eval/adversarial-audit.json" ]
  # the sandbox copy was rewritten by FIX1; the harness copy is the one the gate wrote
  [ "$(jq -r '.verdict_quality.status' "$s")" = TAMPERED ]
  [ "$(jq -r '.verdict_quality.status' "$e")" = APPROVED ]
  [ "$(jq -r '[.phases[] | select(.label == "REVIEW")][0].envelope_sha256' "$p")" = "$(sha_of "$e")" ]
  [ "$(jq -r '[.phases[] | select(.label == "REVIEW")][0].envelope_copied' "$p")" = true ]
  [ "$(jq -r '[.phases[] | select(.label == "AUDIT")][0].envelope_sha256' "$p")" = "$(sha_of "$T/run/eval/adversarial-audit.json")" ]
  # only gate phases carry the envelope fields
  [ "$(jq -r '[.phases[] | select(.label == "FIX1" or .label == "IMPLEMENT") | has("envelope_sha256")] | any' "$p")" = false ]
  # the every-phase copy loop is gone
  ! grep -q 'for env_f in' "$PR" || false
}

@test "envelopes: an AUDIT that rewrites the review envelope cannot change eval/; a symlinked sandbox envelope is never copied (envelope_copied false, null sha; audit MEDIUM-A1)" {
  printf 'STUB_TAMPER_ENVELOPE_AUDIT=review\n' > "$T/stub.env"
  run_pr a1_full
  [ "$status" -eq 0 ]
  [ "$(jq -r '.verdict_quality.status' "$T/run/eval/adversarial-review.json")" = APPROVED ]
  [ "$(jq -r '.verdict_quality.status' "$T/run/sandbox/grimoires/loa/a2a/sprint-1/adversarial-review.json")" = TAMPERED ]
  rm_run
  : > "$T/stub.env"
  # a gate phase whose sandbox envelope is a symlink: nothing is copied
  cat > "$T/claude-link" <<EOF
#!/usr/bin/env bash
"$T/claude" "\$@"; rc=\$?
f=grimoires/loa/a2a/sprint-1/adversarial-review.json
if [[ -f "\$f" && ! -L "\$f" ]]; then rm -f "\$f"; ln -s /etc/hostname "\$f"; fi
exit \$rc
EOF
  chmod +x "$T/claude-link"
  run "$PR" --task-yaml "$REVIEWC" --arm a1_full --run-dir "$T/run" --run-id r-link --trial 1 \
    --source-tree "$T/src" --suite-file "$T/suite.yaml" --executor host --claude-bin "$T/claude-link"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ ! -e "$T/run/eval/adversarial-review.json" ]
  [ "$(jq -c '[.phases[] | select(.label == "REVIEW")][0] | [.envelope_copied, .envelope_sha256]' "$T/run/meta/pipeline.json")" = '[false,null]' ]
}

@test "mount integrity: arm_evidence carries the CLAUDE.md and .loa.config.yaml sha256; mount_integrity ok, changed after a phase appends to CLAUDE.md, absent for A0 (audit LOW-A2)" {
  local p="$T/run/meta/pipeline.json"
  run_pr a1_full
  [ "$status" -eq 0 ]
  [ "$(jq -r '.arm_evidence.claude_md_sha256' "$p")" = "$(sha_of "$T/run/sandbox/CLAUDE.md")" ]
  [[ "$(jq -r '.arm_evidence.loa_config_sha256' "$p")" =~ ^[0-9a-f]{64}$ ]]
  [ "$(jq -c '.mount_integrity' "$p")" = '{"claude_md":"ok","loa_config":"ok"}' ]
  rm_run
  printf 'STUB_APPEND_CLAUDE_MD_IMPLEMENT=1\n' > "$T/stub.env"
  run_pr a1_full
  [ "$status" -eq 0 ]
  [ "$(jq -c '.mount_integrity' "$p")" = '{"claude_md":"changed","loa_config":"ok"}' ]
  rm_run
  : > "$T/stub.env"
  run_pr a0_bare
  [ "$status" -eq 0 ]
  [ "$(jq -r '.arm_evidence.claude_md_sha256 + " " + .arm_evidence.loa_config_sha256' "$p")" = "absent absent" ]
  [ "$(jq -c '.mount_integrity' "$p")" = '{"claude_md":"absent","loa_config":"absent"}' ]
  # a refusal stops before materialisation: no mount to compare
  rm_run
  run_pr a4_no_gates "$REVIEWC"
  [ "$status" -eq 2 ]
  [ "$(jq -r '.mount_integrity' "$p")" = null ]
}

@test "A5: PLAN runs with the Flatline step off; A1's PLAN prompt has it on" {
  run_pr a5_no_flatline
  [ "$status" -eq 0 ]
  [ "$(labels)" = "PLAN,IMPLEMENT,REVIEW,FIX1,AUDIT,FIX2" ]
  grep -q 'Flatline review is off' "$T/run/meta/prompt-PLAN.md"
  [ -f "$T/run/sandbox/grimoires/loa/sprint.md" ]
  rm_run
  run_pr a1_full
  grep -q 'Flatline review is on' "$T/run/meta/prompt-PLAN.md"
}

@test "A6: one implementer session across PLAN, IMPLEMENT and FIX with --resume; gates separate" {
  printf 'STUB_VERDICT_REVIEW=CHANGES_REQUIRED\nSTUB_VERDICT_AUDIT=CHANGES_REQUIRED\n' > "$T/stub.env"
  run_pr a6_one_window
  [ "$status" -eq 0 ]
  local p="$T/run/meta/pipeline.json" sid
  sid="$(jq -r '[.phases[] | select(.label == "PLAN")][0].session_id' "$p")"
  [ -n "$sid" ] && [ "$sid" != null ]
  [ "$(jq -r --arg s "$sid" '[.phases[] | select(.name == "PLAN" or .name == "IMPLEMENT" or .name == "FIX") | .session_id] | unique | join(",")' "$p")" = "$sid" ]
  [ "$(jq -r '[.phases[] | select(.name == "REVIEW" or .name == "AUDIT") | .session_id] | unique | length' "$p")" -eq 2 ]
  [ "$(jq -r --arg s "$sid" '[.phases[] | select(.name == "REVIEW" or .name == "AUDIT") | .session_id] | index($s)' "$p")" = null ]
  # --resume on the continuations only
  [ "$(jq -r '.resume' "$T/run/meta/phase-PLAN.argv.json")" = null ]
  for l in IMPLEMENT FIX1 FIX2; do
    [ "$(jq -r '.resume' "$T/run/meta/phase-$l.argv.json")" = "$sid" ]
    jq -e --arg s "$sid" '.argv | (index("--resume")) as $i | $i != null and .[$i + 1] == $s' "$T/run/meta/phase-$l.argv.json"
  done
  for l in REVIEW AUDIT; do jq -e '.argv | index("--resume") == null' "$T/run/meta/phase-$l.argv.json"; done
}

@test "A0: one BARE phase, no .claude/ or CLAUDE.md or grimoire, --effort high, --max-turns 170" {
  run_pr a0_bare
  [ "$status" -eq 0 ]
  [ "$(labels)" = "BARE" ]
  [ ! -e "$T/run/sandbox/.claude" ] && [ ! -e "$T/run/sandbox/CLAUDE.md" ] && [ ! -e "$T/run/sandbox/grimoires" ]
  [ ! -e "$T/run/sandbox/.run" ]
  local a="$T/run/meta/phase-BARE.argv.json"
  jq -e '.argv | (index("--max-turns")) as $i | .[$i + 1] == "170"' "$a"
  jq -e '.argv | (index("--effort")) as $i | .[$i + 1] == "high"' "$a"
  jq -e '.argv | index("--append-system-prompt-file") == null' "$a"
  [ "$(jq -r '.timeout_s' "$a")" -eq 4200 ]
  grep -q 'Make the app print two.' "$T/run/meta/prompt-BARE.md"
  grep -q 'python3 -m pytest -q tests' "$T/run/meta/prompt-BARE.md"
  [ "$(jq -r '.arm_evidence.loa_mount' "$T/run/meta/pipeline.json")" = none ]
}

@test "A7: --effort medium on every argv and no effort: line left in a sandbox SKILL.md" {
  printf 'STUB_VERDICT_REVIEW=CHANGES_REQUIRED\n' > "$T/stub.env"
  run_pr a7_effort_medium
  [ "$status" -eq 0 ]
  local f n=0
  for f in "$T"/run/meta/phase-*.argv.json; do
    jq -e '.argv | (index("--effort")) as $i | $i != null and .[$i + 1] == "medium"' "$f"; n=$((n + 1))
  done
  [ "$n" -eq 5 ]
  ! grep -l '^effort:' "$T"/run/sandbox/.claude/skills/*/SKILL.md
  [ "$(jq -r '[.phases[] | select(.skipped == false) | .effort_requested] | unique | join(",")' "$T/run/meta/pipeline.json")" = medium ]
}

@test "A1: no --effort flag; effort_requested is the sandbox skill frontmatter" {
  run_pr a1_full
  [ "$status" -eq 0 ]
  ! grep -q -- '--effort' "$T"/log/call-*.argv
  [ "$(jq -r '[.phases[] | select(.label == "IMPLEMENT")][0].effort_requested' "$T/run/meta/pipeline.json")" = xhigh ]
}

@test "review-catch A1: REVIEW then AUDIT on the PR under pr/, dissent pointed at pr/head.diff" {
  run_pr a1_full "$REVIEWC"
  [ "$status" -eq 0 ]
  [ "$(labels)" = "REVIEW,AUDIT" ]
  for p in base/lib/x.sh head/lib/x.sh head.diff PR.md REVIEW-INSTRUCTIONS.md AUDIT-INSTRUCTIONS.md; do
    [ -e "$T/run/sandbox/pr/$p" ]
  done
  [ ! -e "$T/run/sandbox/pr/fixture.yaml" ]
  grep -q -- '--diff-file pr/head.diff' "$T/run/meta/prompt-REVIEW.md"
  grep -q -- '--diff-file pr/head.diff' "$T/run/meta/prompt-AUDIT.md"
  [ -f "$T/run/sandbox/grimoires/loa/sprint.md" ]
}

@test "review-catch A0: one BARE phase with the arm-neutral output contract" {
  run_pr a0_bare "$REVIEWC"
  [ "$status" -eq 0 ]
  [ "$(labels)" = "BARE" ]
  grep -q 'Write your findings to `review.md`' "$T/run/meta/prompt-BARE.md"
  grep -q 'Verdict: CHANGES_REQUIRED' "$T/run/meta/prompt-BARE.md"
}

# --- applicability -------------------------------------------------------------------------

@test "applicability: A4 on a review-catch task is refused (exit 2, meta/refused.json, no phase)" {
  run_pr a4_no_gates "$REVIEWC"
  [ "$status" -eq 2 ]
  [ "$(jq -r '.arm + " " + .type' "$T/run/meta/refused.json")" = "a4_no_gates review-catch" ]
  [ "$(jq -r '.status' "$T/run/meta/pipeline.json")" = infrastructure_error ]
  [ ! -e "$T/log/call-1.argv" ]
}

@test "applicability: the absent A8 and an undeclared arm are refused" {
  run_pr a8_no_ceremonies
  [ "$status" -eq 2 ]
  [[ "$(jq -r '.reason' "$T/run/meta/refused.json")" == *"absent"* ]]
  rm_run
  run_pr a9_nope "$BUILD" --dry-run
  [ "$status" -eq 2 ]
}

# --- leakage (AC-4.2, AC-5.5) ------------------------------------------------------------------

@test "no hidden path in the sandbox; prompts and task-brief carry no hidden, defect key or arm id" {
  run_pr a1_full
  [ "$status" -eq 0 ]
  run find "$T/run/sandbox" -path "$T/run/sandbox/.git" -prune -o -iname '*hidden*' -print
  [ -z "$output" ]
  [ ! -e "$T/run/sandbox/hidden" ] && [ ! -e "$T/run/sandbox/tests/test_secret.py" ]
  ! grep -rqi 'hidden' "$T"/run/meta/prompt-*.md "$T/run/sandbox/grimoires/loa/context/task-brief.md"
  ! grep -rqE 'D[0-9]{2}-' "$T"/run/meta/prompt-*.md "$T/run/sandbox/grimoires/loa/context/task-brief.md"
  for id in a0_bare a1_full a2_no_sprint_plan a3_one_voice a4_no_gates a5_no_flatline a6_one_window a7_effort_medium a8_no_ceremonies; do
    ! grep -rqF "$id" "$T"/run/meta/prompt-*.md "$T/run/sandbox/grimoires/loa/context/task-brief.md"
  done
}

@test "frozen-suite layout: tasks/<id>/{task.yaml,fixture/,hidden/} — the sandbox holds no hidden* path and no file from hidden/ (AC-2.6, AC-5.5)" {
  local d="$T/suite/tasks/bf-02" f
  mkdir -p "$d/fixture/src" "$d/fixture/tests" "$d/hidden/tests" "$d/hidden/structural"
  echo 'print(1)' > "$d/fixture/src/app.py"
  printf 'import os, sys\nsys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))\n' > "$d/fixture/tests/conftest.py"
  printf 'def test_prints_two():\n    assert "two" == "two"  # sealed-case-7f3a\n' > "$d/hidden/tests/test_app.py"
  printf 'def test_shape():\n    pass  # sealed-shape-91c2\n' > "$d/hidden/structural/test_shape.py"
  printf -- '--- a/src/app.py\n+++ b/src/app.py\n@@ -1 +1 @@\n-print(1)\n+print(2)  # sealed-patch-c0de\n' > "$d/hidden/reference.patch"
  echo '{"files": [{"src": "tests/test_app.py", "dest": "tests/test_app.py"}]}' > "$d/hidden/manifest.json"
  printf 'Make the app print two.\n' > "$d/TASK.md"
  cat > "$d/task.yaml" <<'YAML'
id: bf-02
schema_version: 1
type: bug-fix
fixture: tasks/bf-02/fixture
criterion: "the app prints two"
test_command: ["python3", "-m", "pytest", "-q", "tests"]
reference_patch: hidden/reference.patch
grader_protected: [tests/conftest.py]
YAML
  run_pr a1_full "$d/task.yaml"
  [ "$status" -eq 0 ]
  [ -f "$T/run/sandbox/src/app.py" ] && [ -f "$T/run/sandbox/tests/conftest.py" ]
  run find "$T/run/sandbox" -path "$T/run/sandbox/.git" -prune -o -iname '*hidden*' -print
  [ -z "$output" ]
  [ ! -e "$T/run/sandbox/tests/test_app.py" ] && [ ! -e "$T/run/sandbox/reference.patch" ] && [ ! -e "$T/run/sandbox/manifest.json" ]
  [ ! -e "$T/run/sandbox/structural" ] && [ ! -e "$T/run/sandbox/fixture" ] && [ ! -e "$T/run/sandbox/task.yaml" ]
  # no byte of any hidden/ file reached the sandbox, its git history or the snapshots
  for f in sealed-case-7f3a sealed-shape-91c2 sealed-patch-c0de; do
    ! grep -rqF "$f" "$T/run/sandbox" "$T/run/snapshots" "$T/run/transcripts"
  done
  # git objects are compressed: search every commit of the sandbox repository by content and by path
  local revs; revs="$(git -C "$T/run/sandbox" rev-list --all)"
  [ -n "$revs" ]
  ! git -C "$T/run/sandbox" grep -q -e 'sealed-' $revs --
  ! git -C "$T/run/sandbox" log --all --name-only --format= | grep -qi 'hidden\|test_app\|reference.patch'
}

@test "leak guard: a task-brief naming a defect key is refused before any phase (exit 2)" {
  export STUB_BRIEF_EXTRA="see D01-overflow"
  run_pr a1_full
  [ "$status" -eq 2 ]
  [[ "$output" == *"task-brief.md leaks a defect key"* ]]
  [ ! -e "$T/log/call-1.argv" ]
}

@test "leak guard: an arm id inside the sandbox tree is refused (exit 2)" {
  echo "a1_full" > "$T/suite/tasks/bf-01/fx/src/notes.txt"
  run_pr a1_full
  [ "$status" -eq 2 ]
  [[ "$output" == *"arm id appears in the sandbox"* ]]
}

@test "leak guard: a fixture carrying a hidden directory is refused (exit 2)" {
  mkdir -p "$T/suite/tasks/bf-01/fx/hidden"; echo x > "$T/suite/tasks/bf-01/fx/hidden/t.py"
  run_pr a1_full
  [ "$status" -eq 2 ]
  [[ "$output" == *"sandbox contains a hidden path"* ]]
}

@test "fixture path rule: a build fixture touching .claude/ is refused (exit 2)" {
  mkdir -p "$T/suite/tasks/bf-01/fx/.claude"; echo x > "$T/suite/tasks/bf-01/fx/.claude/x"
  run_pr a1_full
  [ "$status" -eq 2 ]
  [ "$(jq -r '.status' "$T/run/meta/pipeline.json")" = infrastructure_error ]
}

# --- session invocation and hygiene (D-4.3, DEC-0394, DEC-0412) ------------------------------------

@test "argv: stream-json, bypassPermissions, --setting-sources project and the fixed tools list on every phase" {
  run_pr a1_full
  [ "$status" -eq 0 ]
  local f
  for f in "$T"/run/meta/phase-*.argv.json; do
    jq -e '.argv | (index("--setting-sources")) as $i | .[$i + 1] == "project"' "$f"
    jq -e '.argv | (index("--tools")) as $i | .[$i + 1] == "Bash,Read,Grep,Glob,Write,Edit,Task,WebFetch"' "$f"
    jq -e '.argv | (index("--output-format")) as $i | .[$i + 1] == "stream-json"' "$f"
    jq -e '.argv | (index("--permission-mode")) as $i | .[$i + 1] == "bypassPermissions"' "$f"
    jq -e '.argv | index("--dangerously-skip-permissions") != null and index("--verbose") != null' "$f"
  done
  argv_of "$(call_for REVIEW)" | grep -qx 'global.anthropic.claude-fable-5-1'
  argv_of "$(call_for IMPLEMENT)" | grep -qx 'global.anthropic.claude-opus-5-5'
}

@test "env: the captured environment is exactly the allowlist; no key, token, agent socket or BASH_ENV" {
  export AWS_ACCESS_KEY_ID=AKIAX AWS_SECRET_ACCESS_KEY=s AWS_SESSION_TOKEN=t GH_TOKEN=g GITHUB_TOKEN=g \
    OPENAI_API_KEY=o GOOGLE_API_KEY=g GEMINI_API_KEY=g ANTHROPIC_API_KEY=a SSH_AUTH_SOCK=/tmp/s BASH_ENV=/tmp/b \
    AWS_REGION=us-east-1 AWS_PROFILE=bedrock CLAUDE_CODE_SESSION_ID=x
  run_pr a1_full
  [ "$status" -eq 0 ]
  local allow=" PATH HOME LANG LC_ALL TERM TMPDIR CLAUDE_CODE_USE_BEDROCK AWS_REGION AWS_DEFAULT_REGION AWS_PROFILE CLAUDE_CODE_SUBAGENT_MODEL LOA_MODELINV_LOG_PATH LOA_COST_LEDGER_PATH GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM GH_CONFIG_DIR LOA_ADVERSARIAL_REVIEW_ENFORCE AWS_BEARER_TOKEN_BEDROCK ANTHROPIC_BEDROCK_REGION_PREFIX ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL "
  local f k
  for f in "$T"/log/call-*.env; do
    # PWD, SHLVL and _ are added by the wrapper's own bash, not by the executor
    while IFS= read -r k; do
      [[ "$allow" == *" $k "* ]] || { echo "unexpected env key $k in $f"; return 1; }
    done < <(sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' "$f" | grep -vxE 'PWD|SHLVL|_|OLDPWD')
    grep -qx 'GIT_CONFIG_GLOBAL=/dev/null' "$f"
    grep -qx 'GIT_CONFIG_NOSYSTEM=1' "$f"
    grep -qx "GH_CONFIG_DIR=$T/run/sandbox/.eval/gh-empty" "$f"
    grep -qx "TMPDIR=$T/run/sandbox/.eval/tmp" "$f"
    grep -qx "LOA_COST_LEDGER_PATH=$T/run/sandbox/.eval/cost-ledger.jsonl" "$f"
    grep -qx 'AWS_PROFILE=bedrock' "$f"
  done
  grep -qx 'CLAUDE_CODE_SUBAGENT_MODEL=global.anthropic.claude-fable-5-1' "$T/log/call-$(call_for AUDIT).env"
  [ -z "$(ls -A "$T/run/sandbox/.eval/gh-empty")" ]
  ! grep -qE 'AKIAX|SSH_AUTH_SOCK|BASH_ENV|GH_TOKEN|OPENAI_API_KEY' "$T"/run/meta/phase-*.argv.json
}

@test "descriptors: nothing above 2 reaches the CLI even when the driver holds fd 7 open" {
  exec 7>"$T/fd7"
  run_pr a1_full
  exec 7>&-
  [ "$status" -eq 0 ]
  local f
  # bats itself holds fd 3 open; the wrapper's own bash opens its script on fd 255
  # (close-on-exec, so it is the wrapper's, not inherited) — every other fd > 2 is a leak
  for f in "$T"/log/call-*.fds; do
    [ "$(grep -cvxE '[012]|255' "$f")" -eq 0 ] || { cat "$f"; return 1; }
  done
}

@test "cwd: every phase runs at the sandbox root" {
  run_pr a1_full
  [ "$status" -eq 0 ]
  [ "$(sort -u "$T"/log/call-*.pwd)" = "$T/run/sandbox" ]
}

# --- cap and watchdog (D-4.6, D-4.10, AC-1.14) ----------------------------------------------------

@test "cap: the phase whose result cost passes USD 12 stops the run (cap_failure, cap_phase, exit 3)" {
  printf 'STUB_COST_PLAN=0.5\nSTUB_COST_IMPLEMENT=11.6\n' > "$T/stub.env"
  run_pr a1_full
  [ "$status" -eq 3 ]
  [ "$(jq -r '.status + " " + .cap_phase' "$T/run/meta/pipeline.json")" = "cap_failure IMPLEMENT" ]
  [ "$(labels)" = "PLAN,IMPLEMENT" ]
}

@test "cap: sandbox cost-ledger rows written during a phase count toward the cap" {
  printf 'STUB_COST_PLAN=0.5\nSTUB_COST_IMPLEMENT=6\nSTUB_LEDGER_USD_REVIEW=5.6\n' > "$T/stub.env"
  run_pr a1_full
  [ "$status" -eq 3 ]
  [ "$(jq -r '.cap_phase' "$T/run/meta/pipeline.json")" = REVIEW ]
  [ "$(jq -r '[.phases[] | select(.label == "REVIEW")][0].ledger_cost_usd' "$T/run/meta/pipeline.json")" = 5.6 ]
  [ -s "$T/run/eval/cost-ledger.jsonl" ] && [ -s "$T/run/eval/model-invoke.jsonl" ]
}

@test "cap: --max-run-usd lowers the cap" {
  printf 'STUB_COST_PLAN=1.5\n' > "$T/stub.env"
  run_pr a1_full "$BUILD" --max-run-usd 1
  [ "$status" -eq 3 ]
  [ "$(jq -r '.cap_phase + " " + (.max_run_usd | tostring)' "$T/run/meta/pipeline.json")" = "PLAN 1" ]
}

@test "watchdog: priced turns that would pass the cap SIGTERM the phase and record cap_turn" {
  # Opus at USD 4 / 20 per Mtok: 200,000 output tokens a turn = USD 4.00004; after PLAN
  # (USD 0.5) the budget is 11.5, so the third turn crosses it.
  printf 'STUB_COST_PLAN=0.5\nSTUB_TURNS_IMPLEMENT=12\nSTUB_TURN_OUT_IMPLEMENT=200000\nSTUB_TURN_SLEEP=0.3\n' > "$T/stub.env"
  run_pr a1_full
  [ "$status" -eq 3 ]
  local p="$T/run/meta/pipeline.json"
  [ "$(jq -r '.status + " " + .cap_phase + " " + (.cap_turn | tostring)' "$p")" = "cap_failure IMPLEMENT 3" ]
  [ "$(jq -r '[.phases[] | select(.label == "IMPLEMENT")][0].watchdog | "\(.killed) \(.cap_turn)"' "$p")" = "true 3" ]
  [ "$(jq -r '[.phases[] | select(.label == "IMPLEMENT")][0].cost_source' "$p")" = watchdog_estimate ]
  # the phase was stopped before it finished its twelve turns
  [ "$(grep -c '"type":"assistant"' "$T/run/transcripts/events-IMPLEMENT.jsonl")" -lt 12 ]
}

@test "watchdog: turns under the cap leave the phase alone" {
  printf 'STUB_TURNS_IMPLEMENT=4\nSTUB_TURN_OUT_IMPLEMENT=1000\n' > "$T/stub.env"
  run_pr a1_full
  [ "$status" -eq 0 ]
  [ "$(jq -r '[.phases[] | select(.label == "IMPLEMENT")][0].watchdog | "\(.killed) \(.priced)"' "$T/run/meta/pipeline.json")" = "false true" ]
}

# --- failure classes (D-4.6, DEC-0405) ---------------------------------------------------------

@test "interrupted: SIGTERM to the driver mid-phase → exit 4, status interrupted, no grade.json" {
  printf 'STUB_SLEEP_IMPLEMENT=30\n' > "$T/stub.env"
  "$PR" --task-yaml "$BUILD" --arm a1_full --run-dir "$T/run" --run-id r1 --trial 1 --source-tree "$T/src" \
    --suite-file "$T/suite.yaml" --executor host --claude-bin "$T/claude" > "$T/out" 2>&1 &
  local pid=$! n=0
  while [ ! -e "$T/run/meta/phase-IMPLEMENT.argv.json" ] && [ $n -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
  sleep 0.5
  kill -TERM "$pid"
  local rc=0; wait "$pid" || rc=$?
  [ "$rc" -eq 4 ]
  [ "$(jq -r '.status' "$T/run/meta/pipeline.json")" = interrupted ]
  [ ! -e "$T/run/grade.json" ] && [ ! -e "$T/run/meta/grade.json" ]
  [ "$(labels)" = "PLAN,IMPLEMENT" ]
}

@test "interrupted: a phase killed from outside (the CLI gets SIGTERM) → exit 4" {
  printf 'STUB_SELF_KILL_IMPLEMENT=1\n' > "$T/stub.env"
  run_pr a1_full
  [ "$status" -eq 4 ]
  [ "$(jq -r '.status' "$T/run/meta/pipeline.json")" = interrupted ]
}

@test "agent_error: a phase exiting non-zero stops the run (exit 1) with the record written" {
  printf 'STUB_EXIT_IMPLEMENT=3\n' > "$T/stub.env"
  run_pr a1_full
  [ "$status" -eq 1 ]
  [ "$(jq -r '.status' "$T/run/meta/pipeline.json")" = agent_error ]
  [ "$(jq -r '[.phases[] | select(.label == "IMPLEMENT")][0].exit' "$T/run/meta/pipeline.json")" -eq 3 ]
}

@test "agent_error: a phase timeout is the model's account (timed_out true, exit 1)" {
  printf 'STUB_SLEEP_IMPLEMENT=20\n' > "$T/stub.env"
  run_pr a1_full "$BUILD" --phase-timeouts '{"IMPLEMENT": 1}'
  [ "$status" -eq 1 ]
  [ "$(jq -r '[.phases[] | select(.label == "IMPLEMENT")][0] | "\(.timed_out) \(.exit)"' "$T/run/meta/pipeline.json")" = "true 124" ]
}

@test "infrastructure: a mount-library refusal is exit 2 with pipeline.json infrastructure_error" {
  export STUB_MOUNT_FAIL=apply_arm_toggles
  run_pr a1_full
  [ "$status" -eq 2 ]
  [ "$(jq -r '.status' "$T/run/meta/pipeline.json")" = infrastructure_error ]
  [[ "$(jq -r '.reason' "$T/run/meta/pipeline.json")" == *"apply_arm_toggles exited 2"* ]]
}

@test "infrastructure: a missing mount library or CLI is exit 2; a non-empty run dir is refused" {
  rm "$H/lib/sandbox-mount.sh"
  run_pr a1_full
  [ "$status" -eq 2 ]
  [[ "$output" == *"mount library not found"* ]]
  cp "$TESTS_DIR/fixtures/mount-lib-stub.sh" "$H/lib/sandbox-mount.sh"
  rm_run
  run "$PR" --task-yaml "$BUILD" --arm a1_full --run-dir "$T/run" --run-id r --trial 1 --source-tree "$T/src" \
    --suite-file "$T/suite.yaml" --executor host --claude-bin "$T/no-such-cli"
  [ "$status" -eq 2 ]
  [[ "$output" == *"claude CLI not found"* ]]
  run "$PR" --task-yaml "$BUILD" --arm a1_full --run-dir "$T/run" --run-id r --trial 1 --source-tree "$T/src" \
    --suite-file "$T/suite.yaml" --executor host --claude-bin "$T/claude"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not empty"* ]]
}

# --- meta/ boundary and manifest (DEC-0413, DEC-0421) -------------------------------------------

@test "meta boundary: the arm id lives under meta/ only — never in sandbox/, snapshots/, transcripts/, eval/" {
  printf 'STUB_VERDICT_REVIEW=CHANGES_REQUIRED\n' > "$T/stub.env"
  local arm
  for arm in a1_full a3_one_voice a7_effort_medium; do
    rm_run; : > "$T/stub.env"
    run_pr "$arm"
    [ "$status" -eq 0 ]
    [ "$(cat "$T/run/meta/arm")" = "$arm" ]
    [ "$(jq -r '.arm' "$T/run/meta/pipeline.json")" = "$arm" ]
    ! grep -rqF "$arm" "$T/run/sandbox" "$T/run/snapshots" "$T/run/transcripts" "$T/run/eval"
    [ ! -e "$T/run/sandbox/.eval/pipeline.json" ]
  done
}

@test "manifest: the sandbox manifest is regenerated after the toggles for every arm" {
  local arm f h
  for arm in a1_full a2_no_sprint_plan a3_one_voice a4_no_gates a5_no_flatline a6_one_window a7_effort_medium; do
    rm_run
    run_pr "$arm"
    [ "$status" -eq 0 ]
    [[ "$(jq -r '.arm_evidence.manifest_sha256' "$T/run/meta/pipeline.json")" =~ ^[0-9a-f]{64}$ ]]
  done
  # A7's stripped SKILL.md hashes in the manifest are the toggled files' hashes
  f="$T/run/sandbox/.claude/skills/implementing-tasks/SKILL.md"
  h="$(jq -r '.files[".claude/skills/implementing-tasks/SKILL.md"]' "$T/run/sandbox/.claude/checksums.json")"
  [ "$h" = "$(python3 -I -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$f")" ]
  ! grep -q '^effort:' "$f"
}

# --- container launcher (D-4.9, AC-1.12) ---------------------------------------------------------

@test "container: docker run carries the resource flags, exactly two mounts (sandbox, per-run HOME) and records the image id" {
  run "$PR" --task-yaml "$BUILD" --arm a1_full --run-dir "$T/run" --run-id r1 --trial 1 --source-tree "$T/src" \
    --suite-file "$T/suite.yaml" --executor container --image loa-ablation:test --docker-bin "$T/docker"
  [ "$status" -eq 0 ]
  local p="$T/run/meta/pipeline.json" a
  [ "$(jq -r '.executor_mode' "$p")" = container ]
  [ "$(jq -r '.image_digest' "$p")" = "sha256:feedfacefeedfacefeedfacefeedfacefeedfacefeedfacefeedfacefeedface" ]
  [[ "$(jq -r '.fingerprint' "$p")" =~ ^fp:[0-9a-f]{64}$ ]]
  a="$(tr '\0' '\n' < "$T/dlog/run-1.argv")"
  for flag in --rm --read-only; do grep -qx -- "$flag" <<<"$a"; done
  grep -A1 -x -- '--network' <<<"$a" | grep -qx bridge
  grep -A1 -x -- '--tmpfs' <<<"$a" | grep -qx '/tmp:rw,size=1g'
  grep -A1 -x -- '--pids-limit' <<<"$a" | grep -qx 512
  grep -A1 -x -- '--memory' <<<"$a" | grep -qx 4g
  grep -A1 -x -- '--cpus' <<<"$a" | grep -qx 2
  grep -A1 -x -- '-w' <<<"$a" | grep -qx /workspace
  local mounts; mounts="$(awk 'p {print; p = 0} $0 == "-v" {p = 1}' <<<"$a" | sort | tr '\n' ' ')"
  [ "$mounts" = "$(printf '%s\n' \
    "$T/run/meta/home:/home/evaluser:rw" "$T/run/sandbox:/workspace:rw" | sort | tr '\n' ' ')" ]
  [ "$(grep -cx -- '-v' <<<"$a")" -eq 2 ]
  ! grep -q 'creds' <<<"$a"
  grep -qx 'loa-ablation:test' <<<"$a"
  # the CLI inside sees in-container paths
  grep -qx 'LOA_COST_LEDGER_PATH=/workspace/.eval/cost-ledger.jsonl' <<<"$a"
  jq -e '.env.HOME == "/home/evaluser" and .env.TMPDIR == "/workspace/.eval/tmp" and .container == true' "$T/run/meta/phase-PLAN.argv.json"
}

@test "container: the allowlist is passed with -e and the in-container env equals it" {
  export GH_TOKEN=g AWS_ACCESS_KEY_ID=AKIAX
  run "$PR" --task-yaml "$BUILD" --arm a4_no_gates --run-dir "$T/run" --run-id r1 --trial 1 --source-tree "$T/src" \
    --suite-file "$T/suite.yaml" --executor container --docker-bin "$T/docker"
  [ "$status" -eq 0 ]
  local a; a="$(tr '\0' '\n' < "$T/dlog/run-1.argv")"
  grep -A1 -x -- '-e' <<<"$a" | grep -qx 'GIT_CONFIG_GLOBAL=/dev/null'
  grep -A1 -x -- '-e' <<<"$a" | grep -qx 'GH_CONFIG_DIR=/workspace/.eval/gh-empty'
  grep -A1 -x -- '-e' <<<"$a" | grep -qx 'LOA_ADVERSARIAL_REVIEW_ENFORCE=false'
  ! grep -qE 'GH_TOKEN|AKIAX|SSH_AUTH_SOCK' <<<"$a"
  ! grep -qE '^(GH_TOKEN|AWS_ACCESS_KEY_ID)=' "$T"/log/call-*.env
  grep -qx "LOA_COST_LEDGER_PATH=$T/run/sandbox/.eval/cost-ledger.jsonl" "$T/log/call-1.env"
}

@test "container: the per-run HOME holds the codex files, the trust file, empty .claude/.aws, no ~/.claude credential or settings file, and is deleted at exit" {
  run "$PR" --task-yaml "$BUILD" --arm a1_full --run-dir "$T/run" --run-id r1 --trial 1 --source-tree "$T/src" \
    --suite-file "$T/suite.yaml" --executor container --docker-bin "$T/docker"
  [ "$status" -eq 0 ]
  [ ! -e "$T/run/meta/home" ]
  local m="$T/dlog/run-1.mounts"
  # the HOME as the container saw it at the first phase (the stub CLI writes nothing there)
  # .claude.json pre-trusts the /workspace project (lead, Sprint 258 smoke; DEC-0490)
  [ "$(sed -n '/home\/evaluser/,$p' "$m" | sed 1d | tr '\n' ' ')" = "  .aws   .claude   .claude.json   .codex   .codex/auth.json   .codex/config.toml " ]
  ! grep -qE 'credentials|settings.json|history|projects|sessions|config$' "$m"
}

@test "container: the per-run HOME persists across the phases of one run and is deleted when interrupted" {
  printf 'STUB_SLEEP_IMPLEMENT=30\n' > "$T/stub.env"
  "$PR" --task-yaml "$BUILD" --arm a1_full --run-dir "$T/run" --run-id r1 --trial 1 --source-tree "$T/src" \
    --suite-file "$T/suite.yaml" --executor container --docker-bin "$T/docker" > "$T/out" 2>&1 &
  local pid=$! n=0
  while [ ! -e "$T/run/meta/phase-IMPLEMENT.argv.json" ] && [ $n -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
  sleep 0.5
  [ -d "$T/run/meta/home/.codex" ]
  [ "$(stat -c %a "$T/run/meta/home")" = 700 ]
  # PLAN and IMPLEMENT mounted the same HOME
  [ "$(grep -h 'home/evaluser' "$T/dlog/run-1.mounts" "$T/dlog/run-2.mounts" | sort -u | wc -l)" -eq 1 ]
  kill -TERM "$pid"
  local rc=0; wait "$pid" || rc=$?
  [ "$rc" -eq 4 ]
  [ ! -e "$T/run/meta/home" ]
  grep -q -- '--signal TERM loa-abl-r1-IMPLEMENT' "$T/dlog/kill.log"
}

@test "bedrock route: the bearer token and route keys reach the CLI (host and container); no artefact carries the token" {
  local tok="tok-SECRET-$RANDOM-bedrock"
  printf '%s' "$tok" > "$T/token"
  export AWS_BEARER_TOKEN_BEDROCK="$tok" AWS_REGION=us-east-1 ANTHROPIC_BEDROCK_REGION_PREFIX=global \
    ANTHROPIC_DEFAULT_OPUS_MODEL=global.anthropic.claude-opus-5-5 ANTHROPIC_DEFAULT_SONNET_MODEL=global.anthropic.claude-sonnet-5 \
    ANTHROPIC_DEFAULT_HAIKU_MODEL=global.anthropic.claude-haiku-5-5
  local mode
  for mode in host container; do
    rm_run; rm -f "$T/log/token.check"
    run "$PR" --task-yaml "$BUILD" --arm a1_full --run-dir "$T/run" --run-id r1 --trial 1 --source-tree "$T/src" \
      --suite-file "$T/suite.yaml" --executor "$mode" --claude-bin "$T/claude" --docker-bin "$T/docker"
    [ "$status" -eq 0 ] || { echo "$mode: $output"; return 1; }
    # every phase got the token (the wrapper compares it with the expected value)
    [ "$(sort -u "$T/log/token.check")" = match ] || { echo "$mode: token check"; return 1; }
    [ "$(wc -l < "$T/log/token.check" | tr -d ' ')" -ge 4 ]   # four phases (+ the fingerprint's --version in host mode)
    grep -qx 'AWS_BEARER_TOKEN_BEDROCK=<set>' "$T/log/call-1.env"
    grep -qx 'ANTHROPIC_BEDROCK_REGION_PREFIX=global' "$T/log/call-1.env"
    grep -qx 'ANTHROPIC_DEFAULT_OPUS_MODEL=global.anthropic.claude-opus-5-5' "$T/log/call-1.env"
    grep -qx 'ANTHROPIC_DEFAULT_HAIKU_MODEL=global.anthropic.claude-haiku-5-5' "$T/log/call-1.env"
    grep -qx 'AWS_REGION=us-east-1' "$T/log/call-1.env"
    [ "$(jq -r '.env.AWS_BEARER_TOKEN_BEDROCK' "$T/run/meta/phase-PLAN.argv.json")" = '<set>' ]
    # the value is nowhere under the run dir (captures, launcher argv, transcripts, logs)
    ! grep -rqF "$tok" "$T/run" || { echo "$mode: token leaked"; grep -rlF "$tok" "$T/run"; return 1; }
    ! grep -rqF "$tok" "$T/log" "$T/dlog"
  done
  # container: the token travels to docker by name only
  grep -qx 'AWS_BEARER_TOKEN_BEDROCK' < <(tr '\0' '\n' < "$T/dlog/run-1.argv")
}

@test "container: a missing image is an infrastructure error (exit 2); host mode makes no per-run HOME" {
  echo 'DOCKER_STUB_NO_IMAGE=1' > "$T/docker.env"
  run "$PR" --task-yaml "$BUILD" --arm a1_full --run-dir "$T/run" --run-id r1 --trial 1 --source-tree "$T/src" \
    --suite-file "$T/suite.yaml" --executor container --docker-bin "$T/docker"
  [ "$status" -eq 2 ]
  [[ "$output" == *"container image not found"* ]]
  rm_run
  run_pr a1_full
  [ "$status" -eq 0 ]
  [ ! -e "$T/run/meta/home" ]
  [ "$(jq -r '.executor_mode' "$T/run/meta/pipeline.json")" = host ]
  [ "$(jq -r '.image_digest == .fingerprint' "$T/run/meta/pipeline.json")" = true ]
}

# --- fingerprint ---------------------------------------------------------------------------------

@test "fingerprint.sh: fp:<sha256> over the tool versions and the source tree HEAD" {
  run "$FP" --source-tree "$T/src" --claude-bin "$T/claude"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^fp:[0-9a-f]{64}$ ]]
  local a="$output"
  run "$FP" --source-tree "$T/src" --claude-bin "$T/claude" --json
  [ "$(jq -r '.fingerprint' <<<"$output")" = "$a" ]
  [ "$(jq -r '.source_tree' <<<"$output")" = "$(git -C "$T/src" rev-parse HEAD)" ]
  [ "$(jq -r '.tools | keys | join(",")' <<<"$output")" = "bats,claude,codex,docker,git,jq,node,python3,yq" ]
  ( cd "$T/src" && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m two )
  run "$FP" --source-tree "$T/src" --claude-bin "$T/claude"
  [ "$output" != "$a" ]
  run "$FP" --bogus
  [ "$status" -eq 2 ]
}

rm_run() { chmod -R u+rwx "$T/run" 2>/dev/null || true; find "$T/run" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T/run" 2>/dev/null || true; find "$T/log" "$T/dlog" -mindepth 1 -delete 2>/dev/null || true; }

@test "Dockerfile.ablation: a single build stage, no cargo install (builds the same under the legacy builder)" {
  local df="$REPO_ROOT/evals/harness/Dockerfile.ablation"
  [ "$(grep -c '^[[:space:]]*FROM[[:space:]]' "$df")" -eq 1 ]
  ! grep -q 'cargo install' "$df"
  ! grep -qi 'AS brbuild' "$df"
  # the comment explaining why br is absent stays
  grep -q 'No beads (br) in the image' "$df"
}

@test "pipeline-run.sh header names the codex version Dockerfile.ablation pins" {
  local df="$REPO_ROOT/evals/harness/Dockerfile.ablation" v
  v="$(sed -n 's/^ARG CODEX_VERSION=//p' "$df")"
  [ -n "$v" ]
  grep -q "codex $v by" "$REPO_ROOT/evals/harness/pipeline-run.sh"
  ! grep -Eq 'codex [0-9]+\.[0-9]+\.[0-9]+' <(grep -Ev "codex $v" "$REPO_ROOT/evals/harness/pipeline-run.sh")
}

@test "fingerprint.sh: without bats on PATH and no override the fingerprint reads bats=absent; no host-specific fallback path (audit LOW-A4)" {
  local t
  mkdir -p "$T/nobats"
  for t in bash env jq python3 git sed tr sort cat; do ln -s "$(command -v "$t")" "$T/nobats/$t"; done
  ! PATH="$T/nobats" command -v bats || false
  run env -u LOA_EVAL_BATS_BIN PATH="$T/nobats" "$FP" --json --claude-bin "$T/claude"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.tools.bats' <<<"$output")" = absent ]
  # an explicit binary is still honoured
  run env -u LOA_EVAL_BATS_BIN PATH="$T/nobats" "$FP" --json --claude-bin "$T/claude" --bats-bin "$T/claude"
  [ "$(jq -r '.tools.bats' <<<"$output")" = "2.1.299 (Claude Code) stub" ]
  ! grep -q dotfiles "$REPO_ROOT/evals/harness/fingerprint.sh" || false
}

@test "Dockerfile.ablation: the pip lines pin exact versions, BATS_COMMIT is 40-hex and the clone's HEAD is checked against it (audit LOW-A6)" {
  local df="$REPO_ROOT/evals/harness/Dockerfile.ablation"
  grep -E '^RUN pip3? install' "$df" > "$T/pip"
  [ "$(grep -c . "$T/pip")" -ge 2 ]
  ! grep -Eq '>=|~=|<|!=' "$T/pip" || false
  grep -qF '"rfc8785==0.1.4" "jsonschema==4.26.0" "pyyaml==6.0.3" "httpx[http2]==0.28.1"' "$df"
  [[ "$(sed -n 's/^ARG BATS_COMMIT=//p' "$df")" =~ ^[0-9a-f]{40}$ ]]
  grep -qF 'test "$(git -C /tmp/bats-core rev-parse HEAD)" = "${BATS_COMMIT}"' "$df"
  # the check sits between the clone and install.sh
  [ "$(grep -nF 'rev-parse HEAD' "$df" | cut -d: -f1)" -lt "$(grep -nF 'install.sh /usr/local' "$df" | cut -d: -f1)" ]
}
