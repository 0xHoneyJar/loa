#!/usr/bin/env bash
# =============================================================================
# evals/harness/lib/sandbox-mount.sh — sandbox materialisation and arm toggles
#
# cycle-130 Sprint 258 Task 1.6 (SDD D-4.5, DEC-0421, DEC-0423, DEC-0396).
# Extracted from execute-agent.sh (cycle-129 step 2 and the toggle functions)
# WITHOUT behaviour change for the cycle-129 single-skill path, and shared with
# pipeline-run.sh. Source it; it defines functions only and sets no shell
# options (the caller runs under `set -euo pipefail`).
#
# Contract (every function returns 0 on success, 2 when refused / when a step
# cannot take effect; refusals name the reason on one stderr line):
#
#   mount_prompt_surface <ws> <prompt_tree> <skill|->
#       skill given: <ws>/.claude/skills/<skill>/ (whole dir), .claude/loa/CLAUDE.loa.md,
#       .claude/rules/, CLAUDE.md = "@.claude/loa/CLAUDE.loa.md"; the prompt tree's
#       .loa.config.yaml only in arm mode (LOA_EVAL_ARM set), as cycle-129 did.
#       skill "-": the whole .claude/ tree is copied (files, never a symlink to the
#       tree), CLAUDE.md as above, and .loa.config.yaml always (the pipeline
#       executor needs every skill, hook and script). Evidence: mount=skill:<s>|tree.
#   resolve_arm_toggles <arm> <suite_file>
#       prints the arm's toggles as compact JSON on stdout. Arms are read from
#       `.arms[]` (ablation-2.0) and `.ab.arms[]` (recall suites). An arm with
#       toggles {} (a1_full, baseline) prints {}; `baseline` undeclared prints {}.
#       Exit 2: undeclared arm (an unreadable suite file declares none), `absent: true` arm.
#   apply_arm_toggles <ws> <toggles_json> <arm>
#       applies every toggle to the SANDBOX COPY and verifies it afterwards; exit 2
#       when one cannot take effect or is unknown. Toggles and values:
#         companion_voice: false  flatline_protocol.{code_review,security_audit}.companion_voice=false
#         karpathy_block: false   '## Karpathy Principles' out of CLAUDE.loa.md (+ constraints.json rows)
#         rule_files: false       stash-safety.md, skill-invariants.md out of .claude/rules/
#         audit_delta_instruction: false  the delta paragraph out of auditing-security/SKILL.md
#         loa_mount: false        verifies no .claude/, CLAUDE.md, .loa.config.yaml in <ws>
#                                 (the caller skips mount_prompt_surface); evidence loa_mount=none
#         effort: low|medium|high|xhigh|max
#                                 every `effort:` line out of the frontmatter of every
#                                 <ws>/.claude/skills/*/SKILL.md; every `default_effort` key in
#                                 <ws>/.claude/defaults/model-config.yaml set to the value and its
#                                 .checksum (bare sha256 hex) refreshed when present.
#                                 The caller passes `--effort <v>` on argv.
#         gates: false            flatline_protocol.{code_review,security_audit}.enabled=false;
#                                 LOA_ADVERSARIAL_REVIEW_ENFORCE=false exported in the CALLING shell
#                                 and written to $ARM_ENV_FILE (KEY=VALUE lines) when that is set
#         flatline: false         flatline_protocol.enabled=false
#         sprint_plan: false, context_resets: false
#                                 phase-set edits owned by the pipeline executor; recorded as
#                                 evidence here (the single-skill executor refuses them itself)
#         bare_model: fable       evidence bare_model=fable; pipeline-run.sh runs the BARE phase on
#                                 global.anthropic.claude-fable-5-1 (cycle-131 D-5.1)
#         dissent: false          flatline_protocol.code_review.enabled=false (the review gate's
#                                 dissent only; security_audit untouched, D-5.3); evidence dissent=false
#         oracle_open: true       the only toggle whose value is true: the open mount (eval-only arm);
#                                 the caller skips overlay_answer_paths and writes mount_overlay=none;
#                                 refused when ARM_EVIDENCE_FILE already holds a head|base overlay;
#                                 evidence oracle_open=true
#   regen_sandbox_manifest <ws>
#       writes <ws>/.claude/checksums.json {generated, algorithm: sha256, files} over
#       every regular file under <ws>/.claude except overrides/ and the manifest
#       itself (LC_ALL=C order, sha256). tools/gen-checksums.sh (in the
#       prompt tree, $EVAL_PROMPT_TREE) is used instead when it exists AND <ws> is a
#       git repository tracking .claude files (it lists `git ls-files`). No .claude/
#       (loa_mount: false) → manifest_sha256=none, exit 0. Prints manifest_sha256=<hex>.
#   check_fixture_path_rule <fixture_dir>
#       exit 2 (offending paths on stderr) when the fixture's top level holds
#       .claude, CLAUDE.md, .loa.config.yaml, grimoires or .run — the mount owns
#       those paths (DEC-0396); exit 0 otherwise.
#   write_sandbox_grimoire <ws> <task_yaml> <arm> <sprint_label>
#       grimoires/loa/ledger.json (one active cycle, <sprint_label> planned, global 1;
#       the ledger-lib.sh schema), NOTES.md (header only), context/task-brief.md (the
#       task's agent-facing `criterion` + the TASK.md next to task.yaml),
#       a2a/<sprint_label>/ (empty); review-catch tasks also get a one-sprint
#       grimoires/loa/sprint.md naming pr/head.diff and a2a/<sprint_label>/reviewer.md
#       carrying pr/PR.md (sandbox copy, else the corpus fixture's). An arm whose
#       toggles carry sprint_plan: false (resolved from $LOA_EVAL_SUITE_FILE, default
#       evals/suites/ablation-2.0.yaml) gets NO sprint.md. Build tasks leave sprint.md
#       to the PLAN phase. Nothing written names the arm.
#   overlay_answer_paths <ws> <fixture-dir> <mode> [<source-tree> [<source-commit>]]
#       cycle-131 FR-1 (closed mount): every answer-bearing path of the review-catch PR
#       fixture (head.diff paths, pr/head/ and pr/base/ files, fixture.yaml fix_commit
#       paths; only under .claude/, never .claude/checksums.json) gets the mode's version
#       in the sandbox (head: the PR's pr/head/ copy, the default, DEC-0622; base: pr/base/;
#       fix-commit paths outside the PR: `git show <head_commit>:X`); a path without that
#       version is removed. <source-tree> (default $EVAL_PROMPT_TREE, else this repository)
#       is the copy source and the git repository the fix and head commits are read from.
#       Evidence: copy_source=<HEAD sha, "-dirty" suffix when .claude/ has changes>,
#       mount_overlay=<mode>:<n>, overlay_sha256=<path>=<sha|absent> per path,
#       overlay_removed=<n>, overlay_fix_commit=available|unavailable|none,
#       gate_scripts_at_pr_version=<comma list of present answer paths under .claude/scripts/,
#       .claude/hooks/ or .claude/skills/*/SKILL.md; empty when none>, overlay_fixture=<dir>,
#       overlay_source_tree=<dir>. Exit 2: missing workspace or fixture (no head.diff), a mode
#       other than head|base, a copy source that is not a clean git tree, a copy_source other
#       than <source-commit> when given, a symlink or non-directory component on a sandbox path.
#   check_mount_closed <ws> <fixture-dir> [<source-tree>] [<evidence-file>]
#       the pre-launch form of took-effect.sh oracle_closed: clauses (a)-(d) (see
#       _sm_oracle_py) against the fixture, the evidence file (default $ARM_EVIDENCE_FILE:
#       mount_overlay, overlay_sha256, base_commit, copy_source) and the copy source's
#       pinned versions. Exit 0 + evidence mount_closed=pre-launch …; exit 2 naming the
#       first violated clause and path.
#   apply_eval_config_variant <ws>
#       the cycle-131 evaluation config in the sandbox .loa.config.yaml:
#       flatline_protocol.{code_review,security_audit}.budget_scale = "diff" and
#       .budget_cents_max = 600 (verified); evidence config_variant=eval.
#   init_sandbox_beads <ws> <task_title>
#       `br init --prefix bd --no-daemon` in <ws> plus one task bead with the title
#       when br ($LOA_EVAL_BR_BIN, default br) is on PATH → beads=br; else the opt-out
#       marker through <ws>/.claude/scripts/beads/update-beads-state.sh --opt-out →
#       beads=opt-out; neither → beads=none (exit 0).
#
# Hashing is Python hashlib (_sm_sha256), never .claude/ code: see _sm_sha256.
# Callers source this file by a literal relative path (no variable expansion
# on the source line), as eval.yml's trust-boundary scan requires.
#
# Evidence: every function reports `key=value` lines (one line, no newline in
# the value). When ARM_EVIDENCE_FILE is set they are appended to that file;
# else they go to the descriptor in SANDBOX_MOUNT_EVIDENCE_FD (default 1).
# resolve_arm_toggles prints JSON on stdout and no evidence.
#
# Tested by evals/tests/arm-toggles.bats (directly and through execute-agent.sh),
# evals/tests/execute-agent.bats and evals/tests/sandbox-mount.bats (the closed mount,
# the cycle-131 toggles and the eval config variant).
# =============================================================================

[[ "${_SANDBOX_MOUNT_LOADED:-}" == "true" ]] && return 0
_SANDBOX_MOUNT_LOADED=true

_SM_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SM_REPO_ROOT="$(cd "$_SM_LIB_DIR/../../.." && pwd)"

_sm_err() { echo "ERROR: $*" >&2; }

# _sm_sha256 <file>... prints "<hex>  <file>" lines, the sha256sum output shape.
# Python hashlib, not compat-lib's sha256_portable: the eval workflow runs the
# harness as the trusted copy against a PR's .claude/, so no harness script
# sources .claude/ code (eval.yml "Validate grader trust boundary"); run-arms.sh
# hashes the corpus the same way.
_sm_sha256() {
  python3 -I -c '
import hashlib, sys
for p in sys.argv[1:]:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    print(h.hexdigest() + "  " + p)' "$@"
}

# _sm_evidence <key> <value> — one key=value line to the evidence sink.
_sm_evidence() {
  local line="$1=${2//$'\n'/ }"
  if [[ -n "${ARM_EVIDENCE_FILE:-}" ]]; then
    printf '%s\n' "$line" >> "$ARM_EVIDENCE_FILE"
  else
    local fd="${SANDBOX_MOUNT_EVIDENCE_FD:-1}"
    [[ "$fd" =~ ^[0-9]$ ]] || fd=1
    printf '%s\n' "$line" >&"$fd"
  fi
}

# ---------------------------------------------------------------------------
mount_prompt_surface() {
  local ws="$1" tree="$2" skill="${3:-}"
  [[ -d "$ws" ]] || { _sm_err "mount_prompt_surface: workspace not found: $ws"; return 2; }
  [[ -d "$tree/.claude" ]] || { _sm_err "mount_prompt_surface: prompt tree has no .claude/: $tree"; return 2; }
  if [[ "$skill" == "-" ]]; then
    mkdir -p "$ws/.claude"
    cp -a "$tree/.claude/." "$ws/.claude/" || { _sm_err "mount_prompt_surface: copying .claude/ failed"; return 2; }
    printf '@.claude/loa/CLAUDE.loa.md\n' > "$ws/CLAUDE.md"
    if [[ -f "$tree/.loa.config.yaml" ]]; then cp "$tree/.loa.config.yaml" "$ws/.loa.config.yaml"; fi
    _sm_evidence mount "tree"
    return 0
  fi
  case "$skill" in */*|.*|'') _sm_err "invalid skill name '$skill'"; return 2 ;; esac
  local skill_src="$tree/.claude/skills/$skill"
  [[ -f "$skill_src/SKILL.md" ]] || { _sm_err "prompt tree $tree has no .claude/skills/$skill/SKILL.md"; return 2; }
  mkdir -p "$ws/.claude/skills" "$ws/.claude/loa"
  # Whole skill dir (resources included) so guarded reads inside the skill resolve.
  local skill_dst="$ws/.claude/skills/$skill"
  mkdir -p "$skill_dst"
  cp -a "$skill_src/." "$skill_dst/"
  if [[ -f "$tree/.claude/loa/CLAUDE.loa.md" ]]; then
    cp "$tree/.claude/loa/CLAUDE.loa.md" "$ws/.claude/loa/CLAUDE.loa.md"
  fi
  if [[ -d "$tree/.claude/rules" ]]; then
    mkdir -p "$ws/.claude/rules"
    cp -a "$tree/.claude/rules/." "$ws/.claude/rules/"
  fi
  printf '@.claude/loa/CLAUDE.loa.md\n' > "$ws/CLAUDE.md"
  if [[ -n "${LOA_EVAL_ARM+x}" && -f "$tree/.loa.config.yaml" ]]; then
    cp "$tree/.loa.config.yaml" "$ws/.loa.config.yaml"
  fi
  _sm_evidence mount "skill:$skill"
  return 0
}

# ---------------------------------------------------------------------------
resolve_arm_toggles() {
  local arm="$1" suite_file="${2:-}"
  [[ "$arm" =~ ^[a-z][a-z0-9_]{0,63}$ ]] || { _sm_err "invalid arm id '$arm'"; return 2; }
  local found=0 entry=""
  if [[ -n "$suite_file" && -f "$suite_file" ]]; then
    # an unreadable suite file reads as "not declared" (cycle-129 behaviour: baseline still resolves to {})
    entry="$(ARM="$arm" yq -o=json -I=0 '[((.arms // [])[]), ((.ab.arms // [])[])] | map(select(.id == strenv(ARM))) | .[0] // null' "$suite_file" 2>/dev/null)" \
      || entry=""
    [[ -n "$entry" && "$entry" != "null" ]] && found=1
  fi
  if [[ "$found" -eq 0 ]]; then
    [[ "$arm" == "baseline" ]] && { printf '{}'; return 0; }
    _sm_err "arm '$arm' is not declared in ${suite_file:-any suite} (arms[] / ab.arms[])"
    return 2
  fi
  if [[ "$(jq -r '.absent // false' <<<"$entry")" == "true" ]]; then
    _sm_err "arm '$arm' is declared absent in $suite_file (never run): $(jq -r '.evidence // "no evidence"' <<<"$entry")"
    return 2
  fi
  local t
  t="$(jq -c '.toggles // {}' <<<"$entry")"
  jq -e 'type == "object"' >/dev/null 2>&1 <<<"$t" || { _sm_err "arm '$arm' toggles are not an object in $suite_file"; return 2; }
  printf '%s' "$t"
}

# ---------------------------------------------------------------------------
# Remove the markdown section that starts at the exact heading line $2 (up to
# the next level-2 heading) from file $1. Prints the number of lines removed.
_sm_drop_md_section() {
  local f="$1" heading="$2" tmpdir="$3" tmp
  tmp="$(mktemp "$tmpdir/.arm.XXXXXX")"
  awk -v h="$heading" '
    $0 == h { skip = 1; n++; next }
    skip && /^## / { skip = 0 }
    skip { n++; next }
    { print }
    END { print n + 0 > "/dev/stderr" }' "$f" > "$tmp" 2> "$tmp.n"
  mv "$tmp" "$f"
  cat "$tmp.n"; rm -f "$tmp.n"
}

# Remove the first blank-line-delimited paragraph of $1 that contains one of
# the needles (tried in order, case-insensitive). Writes the removed text to
# $2; exit 1 when no needle matches.
_sm_drop_paragraph() {
  python3 -I - "$1" "$2" "look for what the review did not" "Confirm the review's demotions independently" <<'PY'
import re, sys
path, out = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
paras = re.split(r"(\n[ \t]*\n)", text)
for needle in sys.argv[3:]:
    for i in range(0, len(paras), 2):
        if needle.lower() in paras[i].lower():
            removed = paras[i]
            # drop the paragraph and the separator that follows it
            del paras[i:i + 2]
            open(path, "w", encoding="utf-8").write("".join(paras))
            open(out, "w", encoding="utf-8").write(removed + "\n")
            sys.exit(0)
sys.exit(1)
PY
}

# Strip every `effort:` line from the YAML frontmatter of file $1 (frontmatter
# = line 1 `---` up to the next `---`). Prints 1 when a line was removed, else 0.
_sm_strip_frontmatter_effort() {
  local f="$1" tmp
  tmp="$(mktemp "$f.XXXXXX")"
  awk '
    NR == 1 && $0 == "---" { fm = 1; print; next }
    fm == 1 && $0 == "---" { fm = 2; print; next }
    fm == 1 && /^effort:/ { n++; next }
    { print }
    END { print (n > 0 ? 1 : 0) > "/dev/stderr" }' "$f" > "$tmp" 2> "$tmp.n"
  cat "$tmp" > "$f"; rm -f "$tmp"
  cat "$tmp.n"; rm -f "$tmp.n"
}

# 0 when file $1's frontmatter still carries an `effort:` line.
_sm_frontmatter_has_effort() {
  awk 'NR == 1 && $0 != "---" { exit 1 } NR > 1 && $0 == "---" { exit 1 } NR > 1 && /^effort:/ { found = 1; exit 0 } END { exit (found ? 0 : 1) }' "$1"
}

_sm_cfg_set_false() {  # _sm_cfg_set_false <cfg> <yq-path>... ; verifies each
  local cfg="$1"; shift
  [[ -f "$cfg" ]] || : > "$cfg"
  local p
  for p in "$@"; do
    P="$p" yq -i 'eval(strenv(P)) = false' "$cfg" 2>/dev/null || return 1
    [[ "$(P="$p" yq -r 'eval(strenv(P))' "$cfg" 2>/dev/null)" == "false" ]] || return 1
  done
  return 0
}

apply_arm_toggles() {
  local ws="$1" toggles="${2:-}" arm="${3:-}"
  [[ -d "$ws" ]] || { _sm_err "apply_arm_toggles: workspace not found: $ws"; return 2; }
  [[ -n "$toggles" ]] || toggles='{}'
  jq -e 'type == "object"' >/dev/null 2>&1 <<<"$toggles" || { _sm_err "arm '$arm' toggles are not a JSON object"; return 2; }
  local eval_dir="$ws/.eval"
  mkdir -p "$eval_dir"
  local key val
  while IFS=$'\t' read -r key val; do
    [[ -n "$key" ]] || continue
    if [[ "$key" == "effort" ]]; then
      case "$val" in low|medium|high|xhigh|max) ;; *) _sm_err "arm '$arm' toggle effort=$val (want low|medium|high|xhigh|max)"; return 2 ;; esac
    elif [[ "$key" == "bare_model" ]]; then
      [[ "$val" == "fable" ]] || { _sm_err "arm '$arm' toggle bare_model=$val (only fable is defined)"; return 2; }
    elif [[ "$key" == "oracle_open" ]]; then
      [[ "$val" == "true" ]] || { _sm_err "arm '$arm' toggle oracle_open=$val (only true is defined)"; return 2; }
    elif [[ "$val" != "false" ]]; then
      _sm_err "arm '$arm' toggle $key=$val (only false is defined)"; return 2
    fi
    case "$key" in
      companion_voice)
        _sm_cfg_set_false "$ws/.loa.config.yaml" .flatline_protocol.code_review.companion_voice .flatline_protocol.security_audit.companion_voice \
          || { _sm_err "companion_voice toggle did not take effect"; return 2; }
        _sm_evidence companion_voice "flatline_protocol.{code_review,security_audit}.companion_voice=false"
        ;;
      karpathy_block)
        local k="$ws/.claude/loa/CLAUDE.loa.md" n
        [[ -f "$k" ]] || { _sm_err "karpathy_block toggle: no sandbox CLAUDE.loa.md"; return 2; }
        n="$(_sm_drop_md_section "$k" '## Karpathy Principles' "$eval_dir")"
        if [[ "${n:-0}" -eq 0 ]] || grep -q '^## Karpathy Principles' "$k"; then
          _sm_err "karpathy_block toggle: no '## Karpathy Principles' section removed"; return 2
        fi
        local cj="$ws/.claude/data/constraints.json" cjn="none"
        if [[ -f "$cj" ]]; then
          # audit r1 DISS-C-008: a failed rewrite is exit 2, not a silent pass; verify afterwards
          jq '(.constraints // []) |= map(select((tostring | test("karpathy"; "i")) | not))' "$cj" > "$cj.tmp" \
            || { rm -f "$cj.tmp"; _sm_err "karpathy_block toggle: constraints.json could not be rewritten"; return 2; }
          mv "$cj.tmp" "$cj"
          cjn="$(jq '[(.constraints // [])[] | select(tostring | test("karpathy"; "i"))] | length' "$cj" 2>/dev/null || echo "?")"
          [[ "$cjn" == "0" ]] || { _sm_err "karpathy_block toggle: constraints.json still carries Karpathy rows ($cjn)"; return 2; }
        fi
        _sm_evidence karpathy_block "removed ${n} lines from CLAUDE.loa.md; constraints.json karpathy rows after: ${cjn}"
        ;;
      rule_files)
        local r gone=""
        for r in stash-safety.md skill-invariants.md; do
          if [[ -e "$ws/.claude/rules/$r" ]]; then rm -f "$ws/.claude/rules/$r"; gone="$gone $r"; fi
          [[ ! -e "$ws/.claude/rules/$r" ]] || { _sm_err "rule_files toggle: $r still present"; return 2; }
        done
        _sm_evidence rule_files "removed:${gone:- none present}"
        ;;
      audit_delta_instruction)
        local s="$ws/.claude/skills/auditing-security/SKILL.md"
        [[ -f "$s" ]] || { _sm_err "audit_delta_instruction toggle: no sandbox auditing-security/SKILL.md"; return 2; }
        _sm_drop_paragraph "$s" "$eval_dir/arm-removed.txt" \
          || { _sm_err "audit_delta_instruction toggle: no delta paragraph found in the sandbox SKILL.md"; return 2; }
        _sm_evidence audit_delta_instruction "removed $(wc -c < "$eval_dir/arm-removed.txt" | tr -d ' ') bytes (.eval/arm-removed.txt)"
        ;;
      loa_mount)
        local p left=""
        for p in .claude CLAUDE.md .loa.config.yaml; do
          if [[ -e "$ws/$p" || -L "$ws/$p" ]]; then left="$left $p"; fi
        done
        [[ -z "$left" ]] || { _sm_err "loa_mount toggle: the sandbox still holds:$left (mount_prompt_surface must be skipped)"; return 2; }
        _sm_evidence loa_mount "none"
        ;;
      effort)
        local f total=0 stripped=0 still=""
        for f in "$ws"/.claude/skills/*/SKILL.md; do
          [[ -f "$f" ]] || continue
          total=$((total + 1))
          if [[ "$(_sm_strip_frontmatter_effort "$f")" == "1" ]]; then stripped=$((stripped + 1)); fi
          if _sm_frontmatter_has_effort "$f"; then still="$still ${f#"$ws"/}"; fi
        done
        [[ -z "$still" ]] || { _sm_err "effort toggle: effort: still in the frontmatter of:$still"; return 2; }
        local mc="$ws/.claude/defaults/model-config.yaml" cat_state="absent"
        if [[ -f "$mc" ]]; then
          local nkeys
          nkeys="$(yq '[.. | select(tag == "!!map" and has("default_effort"))] | length' "$mc" 2>/dev/null || echo 0)"
          [[ "$nkeys" =~ ^[0-9]+$ && "$nkeys" -gt 0 ]] \
            || { _sm_err "effort toggle: no default_effort key in the sandbox model-config.yaml"; return 2; }
          V="$val" yq -i '(.. | select(tag == "!!map" and has("default_effort")) | .default_effort) = strenv(V)' "$mc" \
            || { _sm_err "effort toggle: yq failed on the sandbox model-config.yaml"; return 2; }
          local wrong
          wrong="$(V="$val" yq '[.. | select(tag == "!!map" and has("default_effort")) | select(.default_effort != strenv(V))] | length' "$mc" 2>/dev/null || echo 1)"
          [[ "$wrong" == "0" ]] || { _sm_err "effort toggle: default_effort did not take effect"; return 2; }
          cat_state="default_effort=$val in $nkeys entries"
          if [[ -f "$mc.checksum" ]]; then
            local h
            h="$(_sm_sha256 "$mc" | awk '{print $1}')"
            [[ "$h" =~ ^[0-9a-f]{64}$ ]] || { _sm_err "effort toggle: could not hash model-config.yaml"; return 2; }
            printf '%s\n' "$h" > "$mc.checksum"
            cat_state="$cat_state; .checksum refreshed"
          fi
        fi
        _sm_evidence effort "$val"
        _sm_evidence effort_skills_stripped "$stripped/$total"
        _sm_evidence effort_catalog "$cat_state"
        ;;
      gates)
        _sm_cfg_set_false "$ws/.loa.config.yaml" .flatline_protocol.code_review.enabled .flatline_protocol.security_audit.enabled \
          || { _sm_err "gates toggle did not take effect"; return 2; }
        export LOA_ADVERSARIAL_REVIEW_ENFORCE=false
        if [[ -n "${ARM_ENV_FILE:-}" ]]; then printf 'LOA_ADVERSARIAL_REVIEW_ENFORCE=false\n' >> "$ARM_ENV_FILE"; fi
        _sm_evidence gates "flatline_protocol.{code_review,security_audit}.enabled=false"
        _sm_evidence arm_env "LOA_ADVERSARIAL_REVIEW_ENFORCE=false"
        ;;
      flatline)
        _sm_cfg_set_false "$ws/.loa.config.yaml" .flatline_protocol.enabled \
          || { _sm_err "flatline toggle did not take effect"; return 2; }
        _sm_evidence flatline "flatline_protocol.enabled=false"
        ;;
      sprint_plan)
        _sm_evidence sprint_plan "phase set without PLAN (pipeline executor); no sprint.md materialised"
        ;;
      context_resets)
        _sm_evidence context_resets "implementer phases continue one session (pipeline executor)"
        ;;
      bare_model)
        # the model is the executor's: pipeline-run.sh maps the BARE phase to Fable 5.1
        _sm_evidence bare_model "fable"
        ;;
      dissent)
        # the review gate's adversarial dissent only; the audit gate's stays as configured (D-5.3)
        _sm_cfg_set_false "$ws/.loa.config.yaml" .flatline_protocol.code_review.enabled \
          || { _sm_err "dissent toggle did not take effect"; return 2; }
        _sm_evidence dissent "false"
        ;;
      oracle_open)
        # the open mount (eval-only): the executor skips overlay_answer_paths; an overlay already
        # applied means it did not take effect
        if [[ -n "${ARM_EVIDENCE_FILE:-}" && -f "$ARM_EVIDENCE_FILE" ]] \
           && grep -qE '^mount_overlay=(head|base):' "$ARM_EVIDENCE_FILE"; then
          _sm_err "oracle_open toggle: the sandbox was overlaid (mount_overlay evidence present)"; return 2
        fi
        _sm_evidence oracle_open "true"
        ;;
      *) _sm_err "arm '$arm' declares unknown toggle '$key'"; return 2 ;;
    esac
  done < <(jq -r 'to_entries[] | [.key, (.value | tostring)] | @tsv' <<<"$toggles")
  return 0
}

# ---------------------------------------------------------------------------
regen_sandbox_manifest() {
  local ws="$1"
  [[ -d "$ws" ]] || { _sm_err "regen_sandbox_manifest: workspace not found: $ws"; return 2; }
  if [[ ! -d "$ws/.claude" ]]; then
    _sm_evidence manifest_sha256 "none"
    return 0
  fi
  local out="$ws/.claude/checksums.json" tool="${EVAL_PROMPT_TREE:-$_SM_REPO_ROOT}/tools/gen-checksums.sh" how="inline"
  if [[ -x "$tool" ]] && git -C "$ws" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
     && [[ -n "$(git -C "$ws" ls-files .claude 2>/dev/null | head -1)" ]]; then
    "$tool" --root "$ws" >/dev/null 2>&1 || { _sm_err "regen_sandbox_manifest: $tool --root $ws failed"; return 2; }
    how="gen-checksums.sh"
  else
    local list="$ws/.eval/.manifest-files" sums="$ws/.eval/.manifest-sums"
    mkdir -p "$ws/.eval"
    ( cd "$ws" && find .claude -type f ! -path '.claude/overrides/*' ! -path '.claude/checksums.json' -print ) \
      | LC_ALL=C sort > "$list"
    if grep -q '\\' "$list"; then _sm_err "regen_sandbox_manifest: a path under .claude/ holds a backslash"; rm -f "$list"; return 2; fi
    : > "$sums"
    local -a batch=()
    local f
    while IFS= read -r f; do
      batch+=("$f")
      if [[ ${#batch[@]} -ge 200 ]]; then
        ( cd "$ws" && _sm_sha256 "${batch[@]}" ) >> "$sums" || { _sm_err "regen_sandbox_manifest: hashing failed"; return 2; }
        batch=()
      fi
    done < "$list"
    if [[ ${#batch[@]} -gt 0 ]]; then
      ( cd "$ws" && _sm_sha256 "${batch[@]}" ) >> "$sums" || { _sm_err "regen_sandbox_manifest: hashing failed"; return 2; }
    fi
    jq -Rn --arg generated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
      {generated: $generated, algorithm: "sha256",
       files: ([inputs | select(length > 0) | capture("^(?<h>[0-9a-f]{64})  (?<p>.+)$") | {key: .p, value: .h}] | from_entries)}' \
      < "$sums" > "$out.tmp" || { rm -f "$out.tmp" "$list" "$sums"; _sm_err "regen_sandbox_manifest: could not write the manifest"; return 2; }
    mv "$out.tmp" "$out"
    rm -f "$list" "$sums"
  fi
  jq -e '.files | type == "object"' "$out" >/dev/null 2>&1 || { _sm_err "regen_sandbox_manifest: $out is not a manifest"; return 2; }
  local digest
  digest="$(_sm_sha256 "$out" | awk '{print $1}')"
  _sm_evidence manifest_files "$(jq '.files | length' "$out") ($how)"
  _sm_evidence manifest_sha256 "$digest"
  return 0
}

# ---------------------------------------------------------------------------
check_fixture_path_rule() {
  local dir="$1"
  [[ -d "$dir" ]] || { _sm_err "check_fixture_path_rule: fixture not found: $dir"; return 2; }
  local p bad=""
  for p in .claude CLAUDE.md .loa.config.yaml grimoires .run; do
    if [[ -e "$dir/$p" || -L "$dir/$p" ]]; then bad="$bad $p"; fi
  done
  if [[ -n "$bad" ]]; then
    echo "fixture path rule: $dir holds paths the Loa mount owns:$bad" >&2
    return 2
  fi
  return 0
}

# ---------------------------------------------------------------------------
write_sandbox_grimoire() {
  local ws="$1" task="$2" arm="$3" label="${4:-sprint-1}"
  [[ -d "$ws" ]] || { _sm_err "write_sandbox_grimoire: workspace not found: $ws"; return 2; }
  [[ -f "$task" ]] || { _sm_err "write_sandbox_grimoire: task yaml not found: $task"; return 2; }
  [[ "$label" =~ ^sprint-[0-9]{1,4}$ ]] || { _sm_err "write_sandbox_grimoire: invalid sprint label '$label'"; return 2; }
  local tid ttype criterion task_md
  tid="$(yq -r '.id // ""' "$task")"; ttype="$(yq -r '.type // ""' "$task")"
  criterion="$(yq -r '.criterion // ""' "$task")"
  [[ "$tid" =~ ^[a-z0-9][a-z0-9-]{0,63}$ ]] || { _sm_err "write_sandbox_grimoire: task id '$tid' invalid"; return 2; }
  [[ -n "$criterion" && "$criterion" != "null" ]] || { _sm_err "write_sandbox_grimoire: task $tid has no criterion"; return 2; }
  task_md="$(dirname "$task")/TASK.md"
  [[ -f "$task_md" ]] || { _sm_err "write_sandbox_grimoire: no TASK.md beside $task"; return 2; }

  local sprint_plan=true
  if [[ -n "$arm" ]]; then
    local sf="${LOA_EVAL_SUITE_FILE:-$_SM_REPO_ROOT/evals/suites/ablation-2.0.yaml}" tg
    if tg="$(resolve_arm_toggles "$arm" "$sf" 2>/dev/null)"; then
      [[ "$(jq -r 'if has("sprint_plan") then (.sprint_plan | tostring) else "true" end' <<<"$tg")" == "false" ]] && sprint_plan=false
    fi
  fi

  local g="$ws/grimoires/loa" now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  mkdir -p "$g/context" "$g/a2a/$label"
  jq -n --arg now "$now" --arg label "$label" --arg tid "$tid" '
    {version: 1, schema_version: 1, created: $now, last_updated: $now,
     next_sprint_number: 2, global_sprint_counter: 1, active_cycle: "cycle-001",
     cycles: [{id: "cycle-001", label: ("eval task " + $tid), status: "active", created: $now,
               archived: null, archive_path: null, prd: null, sdd: null,
               sprints: [{global_id: 1, local_label: $label, status: "planned", created: $now, completed: null}]}],
     bugfixes: [], bugfix_cycles: []}' > "$g/ledger.json" \
    || { _sm_err "write_sandbox_grimoire: ledger write failed"; return 2; }
  printf '# NOTES\n' > "$g/NOTES.md"
  {
    printf '# Task brief\n\n## Criterion\n\n%s\n\n## Task\n\n' "$criterion"
    cat "$task_md"
  } > "$g/context/task-brief.md"
  local wrote="ledger.json NOTES.md context/task-brief.md a2a/$label/"

  if [[ "$ttype" == "review-catch" && "$sprint_plan" == "true" ]]; then
    {
      printf '# Sprint Plan\n\n## Sprint %s: Review the pull request in pr/\n\n' "${label#sprint-}"
      printf 'The change under review is `pr/head.diff` (unified diff, base to head). The files before the change are under `pr/base/`, after it under `pr/head/`; `pr/PR.md` is the pull request description and is the implementation report for this sprint.\n\n'
      printf '### Tasks\n\n- [x] Task 1.1: the change in `pr/head.diff`\n\n'
      printf '### Review scope\n\nThe gates review `pr/head.diff` (pass `--diff-file pr/head.diff` to the adversarial review). Cite findings as `head/<path>:<line>` with lines from the `pr/head/` files.\n\n'
      printf '## Success Criteria\n\n%s\n' "$criterion"
    } > "$g/sprint.md"
    local prmd="$ws/pr/PR.md" rcfx
    if [[ ! -f "$prmd" ]]; then
      rcfx="$(yq -r '.review_catch.fixture // ""' "$task")"
      case "$rcfx" in *..*|/*) rcfx="" ;; esac
      prmd="$_SM_REPO_ROOT/evals/fixtures/$rcfx/PR.md"
    fi
    [[ -f "$prmd" ]] || { _sm_err "write_sandbox_grimoire: no PR.md for review-catch task $tid"; return 2; }
    { printf '# Implementation Report: %s\n\n' "$label"; cat "$prmd"; } > "$g/a2a/$label/reviewer.md"
    wrote="$wrote sprint.md a2a/$label/reviewer.md"
  fi
  _sm_evidence grimoire "$wrote"
  return 0
}

# ---------------------------------------------------------------------------
init_sandbox_beads() {
  local ws="$1" title="${2:-}"
  [[ -d "$ws" ]] || { _sm_err "init_sandbox_beads: workspace not found: $ws"; return 2; }
  [[ -n "$title" ]] || title="eval task"
  local br="${LOA_EVAL_BR_BIN:-br}"
  if command -v "$br" >/dev/null 2>&1; then
    ( cd "$ws" && "$br" init --prefix bd --no-daemon >/dev/null 2>&1 && "$br" create "$title" --type task --silent >/dev/null 2>&1 ) \
      || { _sm_err "init_sandbox_beads: br init/create failed in $ws"; return 2; }
    _sm_evidence beads "br"
    return 0
  fi
  local ubs="$ws/.claude/scripts/beads/update-beads-state.sh"
  if [[ -f "$ubs" ]]; then
    PROJECT_ROOT="$ws" bash "$ubs" --opt-out "eval sandbox: br not on PATH" >/dev/null 2>&1 \
      || { _sm_err "init_sandbox_beads: update-beads-state.sh --opt-out failed"; return 2; }
    _sm_evidence beads "opt-out"
    return 0
  fi
  _sm_evidence beads "none"
  return 0
}

# ---------------------------------------------------------------------------
# Closed mount for review-catch sandboxes (cycle-131 FR-1, SDD §5.2, D-1.1/D-1.2,
# DEC-0613 as amended by DEC-0622, DEC-0615). One Python core serves the overlay,
# the pre-launch check (check_mount_closed) and took-effect.sh's oracle_closed rule,
# so the launched surface and the post-run verdict use the same comparison.
#
# _sm_oracle_py answer-set <fixture-dir> <source-repo>
#     prints "<pr|fix>\t<path>" per answer-bearing path (sorted)
# _sm_oracle_py overlay <ws> <fixture-dir> <mode> <source-repo>
#     applies the overlay; prints the evidence key=value lines on stdout, notes on stderr
# _sm_oracle_py check <ws> <fixture-dir> <evidence-file> <source-repo> <source-commit>
#     clauses (a)-(d); exit 0 with "ok …", exit 1 with "FAIL (<clause>) <path>: <detail>"
#
# Answer-bearing set (computed from the IMMUTABLE fixture, never the sandbox pr/):
#   (i) every path named by head.diff: `diff --git` headers (C-quoted paths unquoted,
#       unquoted paths with spaces split at the symmetric " b/"), rename/copy from/to
#       (both names), ---/+++ lines outside hunks (/dev/null skipped, a trailing tab
#       stripped), "Binary files … differ" lines; CRLF tolerated; hunk bodies are
#       skipped by their line counts so a removed "-- a/x" line is never a header;
#   (ii) every file or symlink under <fixture>/head/ and <fixture>/base/;
#   (iii) the fixture.yaml fix_commit's paths (git show --no-renames --name-only):
#       an unknown fix commit logs fix_commit_unavailable and is skipped.
#   Normalised (no absolute, no "..", no empty or "." component, no backslash, no
#   control character) and kept only under .claude/; .claude/checksums.json is
#   harness-owned (regen_sandbox_manifest rewrites it) and excluded, as are CLAUDE.md
#   and .loa.config.yaml (outside .claude/).
# Expected version per mode: head → <fixture>/head/X; base → <fixture>/base/X; a
#   fix-commit path outside the PR → `git show <head_commit>:X` in both modes. No
#   regular file there (deleted, added in base mode, a symlink, a symlink component,
#   unknown head commit) → the path is removed from the mount and expected absent.
#   The file mode's executable bit is kept (fixture file mode / tree entry mode).
# Sandbox writes never follow a symlink: an existing symlink at the path is unlinked,
#   a symlink or non-directory ancestor refuses the overlay (exit 2).
# Clauses (check): (a) every answer path is the mode's expected version or absent where
#   expected absent, and mount_overlay=<mode>:<n> names this set's size; (b) no regular
#   file in the sandbox outside pr/ and .git/ is byte-equal to a later-only pinned
#   version (`git show <source-commit>:X` of an answer path, non-empty, equal to no
#   expected version and to no fixture head/ or base/ file); (c) every answer path has
#   its overlay_sha256 line and its current state equals it (else mount_mutated=<path>;
#   a path whose recorded state was already wrong reports (a)); (d) the sandbox .git
#   holds exactly the base commit (arm_evidence base_commit) over every ref, no remote,
#   no objects/info/alternates, `git fsck --unreachable --no-reflogs` reports nothing
#   and no later-only pinned blob is in its object store. git runs with
#   GIT_CONFIG_GLOBAL=/dev/null, GIT_CONFIG_NOSYSTEM=1, core.fsmonitor=false, no pager.
# ---------------------------------------------------------------------------
_sm_oracle_py() {
  python3 -I - "$@" <<'PY'
import hashlib, os, re, shutil, stat, subprocess, sys

def note(msg):
    sys.stderr.write("sandbox-mount: " + msg + "\n")

def die(msg, code=2):
    note(msg)
    sys.exit(code)

def sha(b):
    return hashlib.sha256(b).hexdigest()

def git(repo, *args):
    env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": "/nonexistent", "LC_ALL": "C",
           "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1", "GIT_TERMINAL_PROMPT": "0",
           "GIT_OPTIONAL_LOCKS": "0"}
    cmd = ["git", "--no-pager", "--literal-pathspecs", "-c", "core.fsmonitor=false", "-c", "core.quotepath=off",
           "-C", repo] + list(args)
    try:
        p = subprocess.run(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           env=env, timeout=300)
    except Exception:
        return None
    return p.stdout if p.returncode == 0 else None

def has_commit(repo, c):
    return bool(c) and git(repo, "cat-file", "-e", c + "^{commit}") is not None

def norm(p):
    if not p or p.startswith("/") or "\\" in p or any(ord(ch) < 32 or ord(ch) == 127 for ch in p):
        return None
    parts = p.split("/")
    if any(x in ("", ".", "..") for x in parts):
        return None
    return "/".join(parts)

ESC = {"a": 7, "b": 8, "t": 9, "n": 10, "v": 11, "f": 12, "r": 13, '"': 34, "\\": 92}

def take_quoted(s):
    """s starts with a double quote: returns (unquoted, rest) or (None, s)."""
    out = bytearray(); i = 1
    while i < len(s):
        c = s[i]
        if c == '"':
            return out.decode("utf-8", "surrogateescape"), s[i + 1:]
        if c == "\\" and i + 1 < len(s):
            n = s[i + 1]
            if n in ESC:
                out.append(ESC[n]); i += 2; continue
            if re.match(r"[0-7]{3}", s[i + 1:i + 4]):
                out.append(int(s[i + 1:i + 4], 8) & 0xFF); i += 4; continue
            out.extend(n.encode("utf-8", "surrogateescape")); i += 2; continue
        out.extend(c.encode("utf-8", "surrogateescape")); i += 1
    return None, s

def one_name(s):
    s = s.strip("\r")
    if s.startswith('"'):
        v, _ = take_quoted(s)
        return v
    return s

def strip_prefix(p):
    if p is None or p == "/dev/null":
        return None
    if p.startswith("a/") or p.startswith("b/"):
        return p[2:]
    return p

def header_names(rest):
    """the two names of `diff --git <rest>`"""
    names = []
    if rest.startswith('"'):
        a, tail = take_quoted(rest)
        if a is None:
            return []
        tail = tail.lstrip(" ")
        b = one_name(tail)
        return [a, b]
    if ' "b/' in rest:
        i = rest.index(' "b/')
        return [rest[:i], one_name(rest[i + 1:])]
    n = len(rest)
    if n >= 5 and (n - 5) % 2 == 0:
        L = (n - 5) // 2
        if rest.startswith("a/") and rest[2 + L:5 + L] == " b/" and rest[2:2 + L] == rest[5 + L:]:
            return ["a/" + rest[2:2 + L], "b/" + rest[5 + L:]]
    if " b/" in rest:
        i = rest.index(" b/")
        return [rest[:i], rest[i + 1:]]
    return names

def diff_paths(diff_file):
    raw = open(diff_file, "rb").read().decode("utf-8", "surrogateescape")
    out = []
    old_left = new_left = 0
    for line in raw.split("\n"):
        if line.endswith("\r"):
            line = line[:-1]
        if old_left > 0 or new_left > 0:
            if line.startswith("\\"):
                continue
            c = line[:1]
            if c == " " or line == "":
                old_left -= 1; new_left -= 1; continue
            if c == "-":
                old_left -= 1; continue
            if c == "+":
                new_left -= 1; continue
            old_left = new_left = 0   # a short hunk: fall through to header parsing
        m = re.match(r"^@@ -\d+(?:,(\d+))? \+\d+(?:,(\d+))? @@", line)
        if m:
            old_left = int(m.group(1)) if m.group(1) is not None else 1
            new_left = int(m.group(2)) if m.group(2) is not None else 1
            continue
        if line.startswith("diff --git "):
            out.extend(strip_prefix(x) for x in header_names(line[len("diff --git "):]))
            continue
        for key in ("rename from ", "rename to ", "copy from ", "copy to "):
            if line.startswith(key):
                out.append(one_name(line[len(key):]))
                break
        else:
            if line.startswith("--- ") or line.startswith("+++ "):
                v = line[4:]
                if not v.startswith('"'):
                    v = v.split("\t", 1)[0]
                out.append(strip_prefix(one_name(v)))
                continue
            m = re.match(r"^Binary files (.+) and (.+) differ$", line)
            if m:
                out.extend(strip_prefix(one_name(x)) for x in (m.group(1), m.group(2)))
    return out

def tree_paths(root):
    out = set()
    if not os.path.isdir(root) or os.path.islink(root):
        return out
    for d, dirs, files in os.walk(root, followlinks=False):
        for n in dirs + files:
            full = os.path.join(d, n)
            if os.path.islink(full) or os.path.isfile(full):
                out.add(os.path.relpath(full, root).replace(os.sep, "/"))
    return out

def fixture_meta(fixture):
    meta = {}
    f = os.path.join(fixture, "fixture.yaml")
    if os.path.isfile(f):
        for line in open(f, encoding="utf-8", errors="replace"):
            m = re.match(r'^(head_commit|fix_commit|base_commit):\s*["\']?([0-9a-f]{7,64})["\']?\s*(#.*)?$', line.strip())
            if m:
                meta[m.group(1)] = m.group(2)
    return meta

def in_scope(p):
    return p is not None and p.startswith(".claude/") and p != ".claude/checksums.json"

def answer_set(fixture, repo):
    """{path: "pr"|"fix"}, notes, meta"""
    notes = []
    if not os.path.isfile(os.path.join(fixture, "head.diff")):
        die("fixture has no head.diff: " + fixture)
    pr = set()
    for raw in diff_paths(os.path.join(fixture, "head.diff")) + sorted(tree_paths(os.path.join(fixture, "head"))) \
            + sorted(tree_paths(os.path.join(fixture, "base"))):
        if raw is None:
            continue
        p = norm(raw)
        if p is None:
            notes.append("rejected path %r" % raw)
            continue
        pr.add(p)
    meta = fixture_meta(fixture)
    fix = set()
    fc = meta.get("fix_commit")
    meta["fix_available"] = "none"
    if fc:
        out = git(repo, "show", "--no-renames", "--name-only", "-z", "--format=", fc) if has_commit(repo, fc) else None
        if out is None:
            notes.append("fix_commit_unavailable " + fc)
            meta["fix_available"] = "unavailable"
        else:
            meta["fix_available"] = "available"
            for raw in out.decode("utf-8", "surrogateescape").split("\0"):
                raw = raw.strip("\n")
                if not raw:
                    continue
                p = norm(raw)
                if p is None:
                    notes.append("rejected fix path %r" % raw)
                    continue
                fix.add(p)
    hc = meta.get("head_commit")
    meta["head_available"] = bool(hc) and has_commit(repo, hc)
    entries = {}
    for p in sorted(pr | fix):
        if in_scope(p):
            entries[p] = "pr" if p in pr else "fix"
    return entries, notes, meta

def fixture_file(root, path):
    """(bytes, exec) of a regular file at root/path with no symlink component, else None"""
    cur = root
    if os.path.islink(cur) or not os.path.isdir(cur):
        return None
    parts = path.split("/")
    for c in parts:
        cur = os.path.join(cur, c)
        if os.path.islink(cur):
            return None
    try:
        st = os.lstat(cur)
    except OSError:
        return None
    if not stat.S_ISREG(st.st_mode):
        return None
    return open(cur, "rb").read(), bool(st.st_mode & 0o111)

def tree_blob(repo, commit, path):
    """(bytes, exec, blob_id) of a regular-file entry in commit, else None"""
    out = git(repo, "ls-tree", "-z", commit, "--", path)
    if not out:
        return None
    ent = out.split(b"\0")[0].decode("utf-8", "surrogateescape")
    m = re.match(r"^(\d+) (\w+) ([0-9a-f]+)\t(.*)$", ent, re.S)
    if not m or m.group(2) != "blob" or m.group(4) != path or m.group(1) not in ("100644", "100755"):
        return None
    data = git(repo, "cat-file", "blob", m.group(3))
    if data is None:
        return None
    return data, m.group(1) == "100755", m.group(3)

def expected(entries, mode, fixture, repo, meta):
    """{path: (bytes, exec) | None}"""
    exp = {}
    for p, src in entries.items():
        if src == "pr":
            exp[p] = fixture_file(os.path.join(fixture, mode), p)
        elif meta.get("head_available"):
            tb = tree_blob(repo, meta["head_commit"], p)
            exp[p] = (tb[0], tb[1]) if tb else None
        else:
            exp[p] = None
    return exp

def state(ws, path):
    """sha256 of the sandbox file, 'absent', or a non-file marker (never followed)"""
    cur = ws
    for c in path.split("/")[:-1]:
        cur = os.path.join(cur, c)
        if os.path.islink(cur):
            return "symlink-component"
    full = os.path.join(ws, *path.split("/"))
    if os.path.islink(full):
        return "symlink"
    if not os.path.lexists(full):
        return "absent"
    if not os.path.isfile(full):
        return "not-a-file"
    return sha(open(full, "rb").read())

def safe_dst(ws, path):
    cur = ws
    for c in path.split("/")[:-1]:
        cur = os.path.join(cur, c)
        if os.path.islink(cur):
            die("overlay refused: symlink component %s in the sandbox path of %s" % (os.path.relpath(cur, ws), path))
        if os.path.lexists(cur) and not os.path.isdir(cur):
            die("overlay refused: non-directory component %s in the sandbox path of %s" % (os.path.relpath(cur, ws), path))
    return os.path.join(ws, *path.split("/"))

def remove(dst):
    if os.path.islink(dst) or (os.path.lexists(dst) and not os.path.isdir(dst)):
        os.unlink(dst)
    elif os.path.isdir(dst):
        shutil.rmtree(dst)

def gate_script(p):
    return bool(re.match(r"^\.claude/(scripts|hooks)/", p) or re.match(r"^\.claude/skills/[^/]+/SKILL\.md$", p))

def cmd_overlay(ws, fixture, mode, repo):
    if mode not in ("head", "base"):
        die("overlay mode must be head or base, got %r" % mode)
    if not os.path.isdir(ws) or os.path.islink(ws):
        die("workspace not found: " + ws)
    entries, notes, meta = answer_set(fixture, repo)
    exp = expected(entries, mode, fixture, repo, meta)
    for n in notes:
        note("overlay: " + n)
    if entries and any(s == "fix" for s in entries.values()) and not meta.get("head_available"):
        note("overlay: head_commit %s unavailable: fix-commit paths outside the PR are removed" % meta.get("head_commit"))
    lines, gates, removed = [], [], 0
    for p in sorted(entries):
        dst = safe_dst(ws, p)
        e = exp[p]
        remove(dst)
        if e is None:
            removed += 1
            note("overlay: removed %s (%s; no %s version)" % (p, entries[p], mode if entries[p] == "pr" else "head_commit"))
        else:
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            fd = os.open(dst, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o755 if e[1] else 0o644)
            with os.fdopen(fd, "wb") as fh:
                fh.write(e[0])
            os.chmod(dst, 0o755 if e[1] else 0o644)
            if gate_script(p):
                gates.append(p)
        lines.append("overlay_sha256=%s=%s" % (p, state(ws, p)))
    print("mount_overlay=%s:%d" % (mode, len(entries)))
    for l in lines:
        print(l)
    print("overlay_removed=%d" % removed)
    print("overlay_fix_commit=%s" % meta["fix_available"])
    print("gate_scripts_at_pr_version=" + ",".join(gates))

def read_evidence(f):
    ev = {"overlay_sha256": {}}
    for line in open(f, encoding="utf-8", errors="surrogateescape"):
        line = line.rstrip("\n")
        if "=" not in line:
            continue
        k, v = line.split("=", 1)
        if k == "overlay_sha256":
            if "=" in v:
                p, s = v.rsplit("=", 1)
                ev["overlay_sha256"].setdefault(p, s)
        elif k not in ev:
            ev[k] = v
    return ev

def cmd_check(ws, fixture, evfile, repo, source_commit):
    if not os.path.isfile(evfile):
        print("FAIL (a) -: no arm evidence file"); sys.exit(1)
    ev = read_evidence(evfile)
    mo = ev.get("mount_overlay", "")
    m = re.match(r"^(head|base):(\d+)$", mo)
    if not m:
        print("FAIL (a) -: mount_overlay=%s (want head|base:<n>)" % (mo or "<missing>")); sys.exit(1)
    mode, n = m.group(1), int(m.group(2))
    entries, _notes, meta = answer_set(fixture, repo)
    exp = expected(entries, mode, fixture, repo, meta)
    fails = []
    if n != len(entries):
        fails.append(("a", "-", "mount_overlay names %d paths, the fixture's answer set has %d" % (n, len(entries))))
    rec = ev["overlay_sha256"]
    present = 0
    for p in sorted(entries):
        want = sha(exp[p][0]) if exp[p] is not None else "absent"
        got = state(ws, p)
        if got != "absent":
            present += 1
        if p not in rec:
            fails.append(("c", p, "no overlay_sha256 line"))
            if got != want:
                fails.append(("a", p, "state %s, want %s (%s)" % (got[:12], want[:12], mode)))
            continue
        if got != rec[p]:
            if rec[p] == want:
                fails.append(("c", p, "mount_mutated=%s (pre-run %s, now %s)" % (p, rec[p][:12], got[:12])))
            else:
                fails.append(("a", p, "pre-run %s, now %s, want %s (%s)" % (rec[p][:12], got[:12], want[:12], mode)))
        elif got != want:
            fails.append(("a", p, "state %s, want %s (%s)" % (got[:12], want[:12], mode)))
    # (b) later-only pinned versions
    if not has_commit(repo, source_commit):
        fails.append(("b", "-", "source commit %s not in %s" % (source_commit or "<none>", repo)))
        later = {}
    else:
        known = set(sha(e[0]) for e in exp.values() if e is not None)
        for t in ("head", "base"):
            for q in tree_paths(os.path.join(fixture, t)):
                ff = fixture_file(os.path.join(fixture, t), q)
                if ff is not None:
                    known.add(sha(ff[0]))
        later = {}
        for p in sorted(entries):
            tb = tree_blob(repo, source_commit, p)
            if tb is None or len(tb[0]) == 0:
                continue
            h = sha(tb[0])
            if h in known:
                continue
            later.setdefault(h, (p, len(tb[0]), tb[2]))
        sizes = set(v[1] for v in later.values())
        scanned = 0
        if later:
            for d, dirs, files in os.walk(ws, followlinks=False):
                rel = os.path.relpath(d, ws)
                if rel == ".":
                    dirs[:] = [x for x in dirs if x not in ("pr", ".git")]
                for nme in sorted(files):
                    full = os.path.join(d, nme)
                    try:
                        st = os.lstat(full)
                    except OSError:
                        continue
                    if not stat.S_ISREG(st.st_mode):
                        continue
                    scanned += 1
                    if st.st_size not in sizes:
                        continue
                    h = sha(open(full, "rb").read())
                    if h in later:
                        fails.append(("b", os.path.relpath(full, ws), "byte-equal to the pinned %s at %s" % (later[h][0], source_commit[:12])))
    # (d) the sandbox repository
    base = ev.get("base_commit", "")
    gd = os.path.join(ws, ".git")
    if not os.path.isdir(gd) or os.path.islink(gd):
        fails.append(("d", ".git", "the sandbox has no .git directory"))
    else:
        revs = git(ws, "rev-list", "--all")
        revs = sorted(set(revs.decode().split())) if revs is not None else None
        if revs != [base]:
            fails.append(("d", ".git", "commits %s, want exactly the base commit %s" % (",".join(r[:12] for r in (revs or [])) or "<unreadable>", base[:12] or "<none>")))
        rem = git(ws, "remote")
        if rem is None or rem.strip():
            fails.append(("d", ".git", "remote(s): %s" % ((rem or b"<unreadable>").decode(errors="replace").split() or "")))
        if os.path.lexists(os.path.join(gd, "objects", "info", "alternates")):
            fails.append(("d", ".git/objects/info/alternates", "the sandbox object store borrows another repository's objects"))
        unr = git(ws, "fsck", "--unreachable", "--no-reflogs", "--no-progress")
        if unr is None or unr.strip():
            fails.append(("d", ".git", "fsck --unreachable: %s" % ((unr or b"<failed>").decode(errors="replace").strip().split("\n")[0])))
        for h, (p, _sz, blob) in sorted(later.items()):
            if git(ws, "cat-file", "-e", blob) is not None:
                fails.append(("d", p, "the pinned blob %s of %s is in the sandbox object store" % (blob[:12], p)))
    if fails:
        fails.sort(key=lambda f: f[0])
        c, p, d = fails[0]
        print("FAIL (%s) %s: %s%s" % (c, p, d, " (+%d more)" % (len(fails) - 1) if len(fails) > 1 else ""))
        sys.exit(1)
    print("ok %s:%d answer paths (%d present), %d later-only pinned versions, sandbox git = base commit only"
          % (mode, len(entries), present, len(later)))

cmd = sys.argv[1] if len(sys.argv) > 1 else ""
if cmd == "answer-set" and len(sys.argv) == 4:
    entries, notes, _meta = answer_set(sys.argv[2], sys.argv[3])
    for n in notes:
        note("answer-set: " + n)
    for p in sorted(entries):
        print("%s\t%s" % (entries[p], p))
elif cmd == "overlay" and len(sys.argv) == 6:
    cmd_overlay(*sys.argv[2:6])
elif cmd == "check" and len(sys.argv) == 7:
    cmd_check(*sys.argv[2:7])
else:
    die("usage: overlay <ws> <fixture> <mode> <repo> | check <ws> <fixture> <evidence> <repo> <commit>")
PY
}

# _sm_copy_source <source-tree> → the tree's HEAD (40 hex), "<sha>-dirty" when its .claude/
# has uncommitted or untracked changes (the copy is then not the commit), else "unknown"
_sm_copy_source() {
  local tree="$1" head dirty
  head="$(git -C "$tree" rev-parse --verify --quiet HEAD 2>/dev/null)" || { printf 'unknown'; return 0; }
  [[ "$head" =~ ^[0-9a-f]{40}$ ]] || { printf 'unknown'; return 0; }
  dirty="$(git -C "$tree" status --porcelain --untracked-files=all -- .claude 2>/dev/null | sed -n '1p')" || dirty="?"
  if [[ -n "$dirty" ]]; then printf '%s-dirty' "$head"; else printf '%s' "$head"; fi
}

# ---------------------------------------------------------------------------
overlay_answer_paths() {
  local ws="$1" fixture="${2:-}" mode="${3:-head}" tree="${4:-${EVAL_PROMPT_TREE:-$_SM_REPO_ROOT}}" want="${5:-}"
  [[ -d "$ws" ]] || { _sm_err "overlay_answer_paths: workspace not found: $ws"; return 2; }
  [[ -n "$fixture" && -f "$fixture/head.diff" ]] || { _sm_err "overlay_answer_paths: fixture not found or has no head.diff: ${fixture:-<none>}"; return 2; }
  case "$mode" in head|base) ;; *) _sm_err "overlay_answer_paths: mode must be head or base, got '$mode'"; return 2 ;; esac
  [[ -d "$tree" ]] || { _sm_err "overlay_answer_paths: source tree not found: $tree"; return 2; }
  local cs
  cs="$(_sm_copy_source "$tree")"
  _sm_evidence copy_source "$cs"
  if [[ ! "$cs" =~ ^[0-9a-f]{40}$ ]]; then
    _sm_err "overlay_answer_paths: copy source $tree is not a clean git tree (copy_source=$cs)"; return 2
  fi
  if [[ -n "$want" && "$cs" != "$want" ]]; then
    _sm_err "overlay_answer_paths: copy_source $cs differs from source_commit $want"; return 2
  fi
  local out line rc=0
  out="$(_sm_oracle_py overlay "$ws" "$fixture" "$mode" "$tree")" || rc=$?
  [[ $rc -eq 0 ]] || { _sm_err "overlay_answer_paths: the overlay failed (exit $rc)"; return 2; }
  while IFS= read -r line; do
    [[ "$line" == *=* ]] || continue
    _sm_evidence "${line%%=*}" "${line#*=}"
  done <<<"$out"
  _sm_evidence overlay_fixture "$fixture"
  _sm_evidence overlay_source_tree "$tree"
  return 0
}

# check_mount_closed <ws> <fixture-dir> [<source-tree>] [<evidence-file>]
check_mount_closed() {
  local ws="$1" fixture="${2:-}" tree="${3:-${EVAL_PROMPT_TREE:-$_SM_REPO_ROOT}}" evf="${4:-${ARM_EVIDENCE_FILE:-}}"
  [[ -d "$ws" ]] || { _sm_err "check_mount_closed: workspace not found: $ws"; return 2; }
  [[ -n "$fixture" && -f "$fixture/head.diff" ]] || { _sm_err "check_mount_closed: fixture not found or has no head.diff: ${fixture:-<none>}"; return 2; }
  [[ -n "$evf" && -f "$evf" ]] || { _sm_err "check_mount_closed: no evidence file (ARM_EVIDENCE_FILE)"; return 2; }
  local cs out rc=0
  cs="$(sed -n 's/^copy_source=//p' "$evf" | sed -n '1p')"
  [[ "$cs" =~ ^[0-9a-f]{40}$ ]] || { _sm_err "check_mount_closed: no clean copy_source in the evidence (got '${cs:-none}')"; return 2; }
  out="$(_sm_oracle_py check "$ws" "$fixture" "$evf" "$tree" "$cs")" || rc=$?
  if [[ $rc -ne 0 ]]; then
    _sm_err "check_mount_closed: ${out:-the check failed (exit $rc)}"
    return 2
  fi
  _sm_evidence mount_closed "pre-launch ${out#ok }"
  return 0
}

# apply_eval_config_variant <ws> — the cycle-131 evaluation config (FR-4, DEC-0618): both
# gates' budget scales with the diff up to USD 6.00. Evidence config_variant=eval.
apply_eval_config_variant() {
  local ws="$1" cfg="$1/.loa.config.yaml" g
  [[ -d "$ws" ]] || { _sm_err "apply_eval_config_variant: workspace not found: $ws"; return 2; }
  [[ -f "$cfg" ]] || : > "$cfg"
  for g in code_review security_audit; do
    G="$g" yq -i '.flatline_protocol[strenv(G)].budget_scale = "diff" | .flatline_protocol[strenv(G)].budget_cents_max = 600' "$cfg" 2>/dev/null \
      || { _sm_err "apply_eval_config_variant: yq failed on $cfg"; return 2; }
    [[ "$(G="$g" yq -r '.flatline_protocol[strenv(G)].budget_scale' "$cfg" 2>/dev/null)" == diff \
       && "$(G="$g" yq -r '.flatline_protocol[strenv(G)].budget_cents_max' "$cfg" 2>/dev/null)" == 600 ]] \
      || { _sm_err "apply_eval_config_variant: $g budget keys did not take effect"; return 2; }
  done
  _sm_evidence config_variant "eval"
  return 0
}
