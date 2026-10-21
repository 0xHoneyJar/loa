#!/usr/bin/env bash
# mount-lib-stub.sh — test stand-in for implementer B's evals/harness/lib/sandbox-mount.sh
# (cycle-130 Sprint 258). pipeline-run.sh sources lib/sandbox-mount.sh by a literal
# path; pipeline-run.bats (make_harness) and ablation-runs/regen.sh run a temporary
# copy of the harness with THIS file in that place. Same function names, signatures
# and return codes as B's contract (0 ok, 2 refused); evidence `key=value` lines go
# to stdout (the driver appends them to $ARM_EVIDENCE_FILE); the gates toggle writes
# LOA_ADVERSARIAL_REVIEW_ENFORCE=false to $ARM_ENV_FILE as B's library does. The
# behaviour is deliberately small: copy the prompt tree's .claude/, CLAUDE.md and
# .loa.config.yaml; apply the toggles the tests check; hash .claude/ with hashlib.
#   STUB_MOUNT_FAIL=<fn>   make that function return 2 (infrastructure path)
#   STUB_BRIEF_EXTRA=<s>   appended to task-brief.md (leak-guard cases)
#   STUB_ARM_ENV_EXTRA=<l> an extra line written to $ARM_ENV_FILE (env filter case)
#   STUB_MOUNT_CALLS=<f>   every library call appends its function name to <f> (wiring order)
#   STUB_COPY_SOURCE=<sha> overlay_answer_paths reports this copy_source instead of the tree's HEAD
# cycle-131 (Sprint 263 Task 1.1): overlay_answer_paths, check_mount_closed and
# apply_eval_config_variant are stubbed with their evidence shapes; the toggles
# bare_model, dissent and oracle_open print their evidence lines.
# cycle-132 (Sprint 269 Task 1.7a): bare_sessions prints bare_sessions=matched; print_toggle_vocabulary
# is the real library's table (pipeline-run.sh --dry-run derives config_edits from it; arm-toggles.bats
# pins this copy byte-equal to evals/harness/lib/sandbox-mount.sh's).

_stub_fail() {
  [[ -n "${STUB_MOUNT_CALLS:-}" ]] && printf '%s\n' "$1" >> "$STUB_MOUNT_CALLS"
  [[ "${STUB_MOUNT_FAIL:-}" == "$1" ]] && { echo "stub: $1 refused" >&2; return 0; }; return 1
}

mount_prompt_surface() {  # <ws> <prompt_tree> <skill|->
  _stub_fail mount_prompt_surface && return 2
  local ws="$1" tree="$2"
  [[ -d "$tree/.claude" ]] || { echo "stub: no .claude in $tree" >&2; return 2; }
  cp -a "$tree/.claude" "$ws/.claude"
  printf '@.claude/loa/CLAUDE.loa.md\n' > "$ws/CLAUDE.md"
  [[ -f "$tree/.loa.config.yaml" ]] && cp "$tree/.loa.config.yaml" "$ws/.loa.config.yaml"
  echo "mount=whole_tree"
}

resolve_arm_toggles() {  # <arm> <suite_file>
  _stub_fail resolve_arm_toggles && return 2
  local def
  def="$(ARM="$1" yq -o=json '.arms[] | select(.id == env(ARM))' "$2" 2>/dev/null)"
  [[ -n "$def" ]] || { echo "stub: arm $1 undeclared" >&2; return 2; }
  [[ "$(jq -r '.absent // false' <<<"$def")" == true ]] && { echo "stub: arm $1 absent" >&2; return 2; }
  jq -c '.toggles // {}' <<<"$def"
}

apply_arm_toggles() {  # <ws> <toggles_json> <arm>
  _stub_fail apply_arm_toggles && return 2
  local ws="$1" tg="$2" cfg="$1/.loa.config.yaml" f n=0 e
  if [[ "$(jq -r '.companion_voice' <<<"$tg")" == false ]]; then
    yq -i '.flatline_protocol.code_review.companion_voice = false | .flatline_protocol.security_audit.companion_voice = false' "$cfg"
    echo "companion_voice=false"
  fi
  if [[ "$(jq -r '.gates' <<<"$tg")" == false ]]; then
    yq -i '.flatline_protocol.code_review.enabled = false | .flatline_protocol.security_audit.enabled = false' "$cfg"
    echo "gates=false"; echo "arm_env=LOA_ADVERSARIAL_REVIEW_ENFORCE=false"
    [[ -n "${ARM_ENV_FILE:-}" ]] && echo "LOA_ADVERSARIAL_REVIEW_ENFORCE=false" >> "$ARM_ENV_FILE"
  fi
  if [[ "$(jq -r '.flatline' <<<"$tg")" == false ]]; then
    yq -i '.flatline_protocol.enabled = false' "$cfg"; echo "flatline=false"
  fi
  e="$(jq -r '.effort // empty' <<<"$tg")"
  if [[ -n "$e" ]]; then
    for f in "$ws"/.claude/skills/*/SKILL.md; do
      [[ -f "$f" ]] || continue
      # frontmatter only (between the first two --- lines), as B's library does
      awk 'NR == 1 {fm = ($0 == "---")} NR > 1 && fm && $0 == "---" {fm = 0; print; next} fm && NR > 1 && /^effort:/ {next} {print}' \
        "$f" > "$f.tmp" && mv "$f.tmp" "$f"; n=$((n + 1))
    done
    echo "effort=$e"; echo "effort_stripped=$n"
  fi
  [[ "$(jq -r '.loa_mount' <<<"$tg")" == false ]] && echo "loa_mount=none"
  [[ "$(jq -r '.bare_model // empty' <<<"$tg")" == fable ]] && echo "bare_model=fable"
  if [[ "$(jq -r '.dissent' <<<"$tg")" == false ]]; then
    yq -i '.flatline_protocol.code_review.enabled = false' "$cfg"; echo "dissent=false"
  fi
  [[ "$(jq -r '.oracle_open' <<<"$tg")" == true ]] && echo "oracle_open=true"
  [[ "$(jq -r '.bare_sessions // empty' <<<"$tg")" == matched ]] && echo "bare_sessions=matched"
  [[ -n "${STUB_ARM_ENV_EXTRA:-}" && -n "${ARM_ENV_FILE:-}" ]] && printf '%s\n' "$STUB_ARM_ENV_EXTRA" >> "$ARM_ENV_FILE"
  return 0
}

print_toggle_vocabulary() {
  printf '%s\t%s\t%s\n' \
    companion_voice false "flatline_protocol.code_review.companion_voice=false,flatline_protocol.security_audit.companion_voice=false" \
    karpathy_block false - \
    rule_files false - \
    audit_delta_instruction false - \
    loa_mount false - \
    effort "low|medium|high|xhigh|max" - \
    gates false "flatline_protocol.code_review.enabled=false,flatline_protocol.security_audit.enabled=false" \
    dissent false "flatline_protocol.code_review.enabled=false" \
    flatline false "flatline_protocol.enabled=false" \
    sprint_plan false - \
    context_resets false - \
    bare_model fable - \
    oracle_open true - \
    bare_sessions matched -
}

regen_sandbox_manifest() {  # <ws>
  _stub_fail regen_sandbox_manifest && return 2
  python3 -I -c '
import hashlib, json, os, sys
ws = sys.argv[1]
files = {}
for d, _, names in os.walk(os.path.join(ws, ".claude")):
    for n in names:
        p = os.path.join(d, n); rel = os.path.relpath(p, ws)
        if rel == ".claude/checksums.json" or rel.startswith(".claude/overrides/"):
            continue
        files[rel] = hashlib.sha256(open(p, "rb").read()).hexdigest()
man = os.path.join(ws, ".claude", "checksums.json")
with open(man, "w") as f:
    json.dump({"generated": "stub", "algorithm": "sha256", "files": dict(sorted(files.items()))}, f, indent=2)
print("manifest_files=%d" % len(files))
print("manifest_sha256=" + hashlib.sha256(open(man, "rb").read()).hexdigest())' "$1"
}

check_fixture_path_rule() {  # <fixture_dir>
  _stub_fail check_fixture_path_rule && return 2
  local d="$1" p bad=0
  for p in .claude CLAUDE.md .loa.config.yaml grimoires .run; do
    [[ -e "$d/$p" ]] && { echo "fixture path rule: $p" >&2; bad=1; }
  done
  [[ $bad -eq 0 ]] || return 2
  return 0
}

write_sandbox_grimoire() {  # <ws> <task_yaml> <arm> <sprint_label>
  _stub_fail write_sandbox_grimoire && return 2
  local ws="$1" ty="$2" arm="$3" sp="$4" g="$1/grimoires/loa" type
  mkdir -p "$g/context" "$g/a2a/$sp"
  printf '{"cycles":[{"id":"cycle-eval","status":"active","sprints":[{"local":"%s","status":"planned"}]}]}\n' "$sp" > "$g/ledger.json"
  printf '# NOTES\n' > "$g/NOTES.md"
  { printf '# Task brief\n\n%s\n' "$(yq -r '.criterion // ""' "$ty")"
    [[ -f "$(dirname "$ty")/TASK.md" ]] && cat "$(dirname "$ty")/TASK.md"
    [[ -n "${STUB_BRIEF_EXTRA:-}" ]] && printf '%s\n' "$STUB_BRIEF_EXTRA"
  } > "$g/context/task-brief.md"
  type="$(yq -r '.type' "$ty")"
  if [[ "$type" == review-catch ]]; then
    printf '# Sprint plan\n\n## %s\nReview the change in pr/head.diff.\n' "$sp" > "$g/sprint.md"
    cp "$ws/pr/PR.md" "$g/a2a/$sp/reviewer.md" 2>/dev/null || true
  fi
  return 0
}

init_sandbox_beads() {  # <ws> <task_title>
  _stub_fail init_sandbox_beads && return 2
  echo "beads=opt-out"
}

overlay_answer_paths() {  # <ws> <fixture-dir> <mode> [<source-tree> [<source-commit>]]
  _stub_fail overlay_answer_paths && return 2
  local cs="${STUB_COPY_SOURCE:-$(git -C "${4:-.}" rev-parse HEAD 2>/dev/null || echo unknown)}"
  echo "copy_source=$cs"
  [[ -f "$2/head.diff" ]] || { echo "stub: no head.diff in $2" >&2; return 2; }
  echo "mount_overlay=$3:0"; echo "overlay_removed=0"; echo "overlay_fix_commit=none"; echo "gate_scripts_at_pr_version="
  echo "overlay_fixture=$2"
}

check_mount_closed() {  # <ws> <fixture-dir> [<source-tree>]
  _stub_fail check_mount_closed && { echo "check_mount_closed: FAIL (b) .claude/x: byte-equal to the pinned .claude/y (stub)" >&2; return 2; }
  echo "mount_closed=pre-launch stub"
}

apply_eval_config_variant() {  # <ws>
  _stub_fail apply_eval_config_variant && return 2
  local cfg="$1/.loa.config.yaml"
  [[ -f "$cfg" ]] || : > "$cfg"
  yq -i '.flatline_protocol.code_review.budget_scale = "diff" | .flatline_protocol.security_audit.budget_scale = "diff"
         | .flatline_protocol.code_review.budget_cents_max = 600 | .flatline_protocol.security_audit.budget_cents_max = 600' "$cfg"
  echo "config_variant=eval"
}
