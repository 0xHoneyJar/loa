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
# Tested by evals/tests/arm-toggles.bats (directly and through execute-agent.sh)
# and evals/tests/execute-agent.bats.
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
