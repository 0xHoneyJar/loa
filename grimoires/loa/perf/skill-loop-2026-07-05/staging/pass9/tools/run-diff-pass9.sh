#!/usr/bin/env bash
# =============================================================================
# run-diff-pass9.sh — old-vs-new differential corpus for the pass-9 changes:
#   1. adversarial-review-gate.sh  — raw-payload literal fast gate (pre-jq)
#   2. spiral-skill-sentinel.sh    — raw-payload literal fast gate (pre-jq)
#   3. mutation-logger.sh          — grep -qEi filter → folded per-line [[ =~ ]]
#
# For every case: run OLD (HEAD) and NEW (staged) hook in fresh per-side
# sandbox roots, compare exit code + stdout + stderr byte-for-byte after
# ts/root normalization, plus the hook's side-effect files:
#   ml:  .run/audit.jsonl
#   sss: .run/spiral-dispatch-active (existence + normalized content)
#   ag:  (no side effects — stderr/exit only)
#
# ANY divergence fails.
# =============================================================================
set -u
export LC_ALL=C
REPO=${REPO:-/home/merlin/Documents/thj/code/loa}
OLDDIR=${OLDDIR:-/tmp/p9/old}
NEWDIR=${NEWDIR:-$REPO/grimoires/loa/perf/skill-loop-2026-07-05/staging/pass9}
WORK=${WORK:-/tmp/p9/diff}
rm -rf "$WORK"; mkdir -p "$WORK"

fail=0; total=0

norm() {
  sed -e 's/[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}Z/__TS__/g' \
      -e "s|$WORK/old|__ROOT__|g" -e "s|$WORK/new|__ROOT__|g" \
      -e 's|^[^ ]*\.sh: line [0-9]*: |__HOOK__: line __N__: |'
}

# run_pair <hookname> <casename> <payload-file> <setup-fn|-> [ENV=VAL ...]
run_pair() {
  local hook=$1 name=$2 pl=$3 setup=$4; shift 4
  total=$((total+1))
  local side rc hookpath
  for side in old new; do
    local root="$WORK/$side"
    rm -rf "$root"; mkdir -p "$root/.run"
    [[ "$setup" != "-" ]] && "$setup" "$root"
    [[ $side == old ]] && hookpath="$OLDDIR/$hook" || hookpath="$NEWDIR/$hook"
    rc=0
    ( cd "$root" && env "$@" bash "$hookpath" \
        <"$pl" >"$WORK/$side.out" 2>"$WORK/$side.err" ) || rc=$?
    echo "$rc" > "$WORK/$side.rc"
    norm < "$WORK/$side.out" > "$WORK/$side.out.n"
    norm < "$WORK/$side.err" > "$WORK/$side.err.n"
    # side-effect capture: audit log + sentinel
    for sf in .run/audit.jsonl .run/spiral-dispatch-active; do
      local tag; tag=$(basename "$sf")
      if [[ -f "$root/$sf" ]]; then
        { echo "EXISTS"; norm < "$root/$sf"; } > "$WORK/$side.$tag.n"
      else
        echo "ABSENT" > "$WORK/$side.$tag.n"
      fi
    done
  done
  local bad=""
  cmp -s "$WORK/old.rc" "$WORK/new.rc" || bad+=" rc($(cat "$WORK/old.rc")->$(cat "$WORK/new.rc"))"
  cmp -s "$WORK/old.out.n" "$WORK/new.out.n" || bad+=" stdout"
  cmp -s "$WORK/old.err.n" "$WORK/new.err.n" || bad+=" stderr"
  cmp -s "$WORK/old.audit.jsonl.n" "$WORK/new.audit.jsonl.n" || bad+=" audit"
  cmp -s "$WORK/old.spiral-dispatch-active.n" "$WORK/new.spiral-dispatch-active.n" || bad+=" sentinel"
  if [[ -n "$bad" ]]; then
    fail=$((fail+1))
    echo "DIVERGE [$hook/$name]:$bad"
    diff "$WORK/old.err.n" "$WORK/new.err.n" | head -6
    diff "$WORK/old.audit.jsonl.n" "$WORK/new.audit.jsonl.n" | head -6
    diff "$WORK/old.spiral-dispatch-active.n" "$WORK/new.spiral-dispatch-active.n" | head -6
  fi
}

PL="$WORK/payload.json"

# Literal backslash-u builder. The corpus needs raw JSON \uXXXX escape
# sequences in payload bytes, but the authoring tool decodes \uXXXX at
# file-write time (same constraint documented in mutation-logger.sh's
# header) — so the two bytes are assembled at runtime instead.
BSLASH=$(printf '\x5c')
U="${BSLASH}u"

# =============================================================================
# Section AG — adversarial-review-gate.sh
# =============================================================================
AG=adversarial-review-gate.sh

# setup: sandbox with a config + sprint dir (artefacts absent by default)
ag_setup() {
  local root=$1
  mkdir -p "$root/sprints/sprint-1"
  printf 'flatline_protocol:\n  code_review:\n    enabled: true\n  security_audit:\n    enabled: true\n' \
    > "$root/config-on.yaml"
  printf 'flatline_protocol:\n  code_review:\n    enabled: false\n  security_audit:\n    enabled: false\n' \
    > "$root/config-off.yaml"
  printf 'flatline_protocol: [broken\n' > "$root/config-bad.yaml"
  printf '{"metadata":{"type":"review","model":"gpt-5.5-pro"}}\n' > "$root/valid-artefact.json"
}
ag_setup_artefacts() {  # config on + valid artefacts present
  local root=$1
  ag_setup "$root"
  cp "$root/valid-artefact.json" "$root/sprints/sprint-1/adversarial-review.json"
  cp "$root/valid-artefact.json" "$root/sprints/sprint-1/adversarial-audit.json"
}

mkjson() { printf '%s' "$1" > "$PL"; }

# fast-path class: no COMPLETED, no \u anywhere
mkjson '{"tool_name":"Write","tool_input":{"file_path":"grimoires/loa/NOTES.md","content":"# notes\nline\n"}}'
run_pair "$AG" benign-write "$PL" ag_setup
mkjson '{"tool_name":"Edit","tool_input":{"file_path":"tests/unit/x.bats","old_string":"a","new_string":"b"}}'
run_pair "$AG" benign-edit "$PL" ag_setup
mkjson '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
run_pair "$AG" benign-bash "$PL" ag_setup
printf '' > "$PL"
run_pair "$AG" empty-stdin "$PL" ag_setup
mkjson 'complete garbage not json'
run_pair "$AG" garbage-no-tokens "$PL" ag_setup
mkjson '{"tool_name":"Write","tool_input":{"file_path":"notes.md","content":"completed lowercase mention"}}'
run_pair "$AG" lowercase-completed "$PL" ag_setup

# slow-path class: literal COMPLETED present but NOT a marker write
mkjson '{"tool_name":"Write","tool_input":{"file_path":"grimoires/notes.md","content":"sprint COMPLETED yesterday"}}'
run_pair "$AG" completed-in-content "$PL" ag_setup
mkjson '{"tool_name":"Write","tool_input":{"file_path":"COMPLETED","content":"x"}}'
run_pair "$AG" completed-no-slash "$PL" ag_setup
mkjson '{"tool_name":"Bash","tool_input":{"command":"touch sprints/sprint-1/COMPLETED"}}'
run_pair "$AG" completed-wrong-tool "$PL" ag_setup
mkjson '{"tool_name":"Write","session_id":"COMPLETED","tool_input":{"file_path":"a.md","content":"x"}}'
run_pair "$AG" completed-in-other-field "$PL" ag_setup

# slow-path class: \u present, no literal COMPLETED
mkjson "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"caf${U}00e9.md\",\"content\":\"x\"}}"
run_pair "$AG" unicode-escape-benign "$PL" ag_setup

# real gate paths (COMPLETED marker writes) — decisions must stay identical
ag_case_marker() {  # <name> <setup> <extra env...>
  local name=$1 setup=$2; shift 2
  # relative path — the hook runs with CWD = sandbox root
  printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"sprints/sprint-1/COMPLETED","content":"done\n"}}' > "$PL"
  run_pair "$AG" "$name" "$PL" "$setup" "$@"
}
ag_case_marker marker-config-on-missing   ag_setup           LOA_CONFIG_PATH_OVERRIDE=config-on.yaml
ag_case_marker marker-config-on-valid     ag_setup_artefacts LOA_CONFIG_PATH_OVERRIDE=config-on.yaml
ag_case_marker marker-config-off          ag_setup           LOA_CONFIG_PATH_OVERRIDE=config-off.yaml
ag_case_marker marker-config-malformed    ag_setup           LOA_CONFIG_PATH_OVERRIDE=config-bad.yaml
ag_case_marker marker-config-unresolvable ag_setup
ag_case_marker marker-enforce-off         ag_setup           LOA_ADVERSARIAL_REVIEW_ENFORCE=false

# escaped-COMPLETED file_path (\u path; raw lacks the contiguous literal but
# decodes to a marker path) — must evaluate the gate on BOTH sides
mkjson "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"sprints/sprint-1/${U}0043OMPLETED\",\"content\":\"d\"}}"
run_pair "$AG" marker-u-escaped-on "$PL" ag_setup LOA_CONFIG_PATH_OVERRIDE=config-on.yaml
run_pair "$AG" marker-u-escaped-valid "$PL" ag_setup_artefacts LOA_CONFIG_PATH_OVERRIDE=config-on.yaml

# NotebookEdit + notebook_path
mkjson '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"sprints/sprint-1/COMPLETED"}}'
run_pair "$AG" marker-notebook "$PL" ag_setup LOA_CONFIG_PATH_OVERRIDE=config-off.yaml

# root-level marker: sprint_dir="/" — deterministic BLOCK (walk never checks /)
mkjson '{"tool_name":"Write","tool_input":{"file_path":"/COMPLETED","content":"d"}}'
run_pair "$AG" marker-root "$PL" ag_setup

# unparseable payload mentioning /COMPLETED — fail-closed BLOCK both
mkjson 'garbage with sprints/sprint-1/COMPLETED inside'
run_pair "$AG" garbage-with-marker "$PL" ag_setup
# unparseable with bare COMPLETED (no slash) — slow path, probe fails, allow
mkjson 'garbage with COMPLETED word'
run_pair "$AG" garbage-bare-completed "$PL" ag_setup
# unparseable with \u but no COMPLETED — slow path, jq fails, allow
mkjson "garbage with ${U}0043 escape"
run_pair "$AG" garbage-u-escape "$PL" ag_setup

# NUL-bearing payloads (read -rd '' truncation identical on both sides)
printf '{"tool_name":"Write","tool_input":{"file_path":"a.md","content":"x"}}\0junk COMPLETED' > "$PL"
run_pair "$AG" nul-then-completed "$PL" ag_setup
printf '{"tool_name":"Write","tool_input":{"file_path":"sprints/sprint-1/COMPLETED"}}\0junk' > "$PL"
run_pair "$AG" completed-then-nul "$PL" ag_setup LOA_CONFIG_PATH_OVERRIDE=config-off.yaml

# 1MB content payload without tokens (fast path at size)
python3 - "$PL" <<'PYEOF'
import json, sys
payload = {"tool_name": "Write",
           "tool_input": {"file_path": "grimoires/big.md",
                          "content": "benchmark line without markers " * 32000}}
open(sys.argv[1], "w").write(json.dumps(payload))
PYEOF
run_pair "$AG" big-1mb-benign "$PL" ag_setup

# =============================================================================
# Section SS — spiral-skill-sentinel.sh
# =============================================================================
SS=spiral-skill-sentinel.sh

mkjson '{"tool_name":"Skill","tool_input":{"skill":"implement","args":"sprint-1"}}'
run_pair "$SS" skill-implement "$PL" -
mkjson '{"tool_name":"Skill","tool_input":{"skill":"spiraling"}}'
run_pair "$SS" skill-spiraling "$PL" -
mkjson '{"tool_name":"Skill","tool_input":{"skill":"loa:spiraling"}}'
run_pair "$SS" skill-ns-spiraling "$PL" -
mkjson '{"tool_name":"Skill","tool_input":{"skill":"spiralingX"}}'
run_pair "$SS" skill-spiralingX "$PL" -
mkjson '{"tool_name":"Skill","tool_input":{"skill":"SPIRALING"}}'
run_pair "$SS" skill-upper "$PL" -
mkjson "{\"tool_name\":\"Skill\",\"tool_input\":{\"skill\":\"${U}0073piraling\"}}"
run_pair "$SS" skill-u-escaped "$PL" -
mkjson "{\"tool_name\":\"Skill\",\"tool_input\":{\"skill\":\"spira${U}006cing\"}}"
run_pair "$SS" skill-u-escaped-mid "$PL" -
mkjson '{"tool_name":"Skill","tool_input":{"skill":42},"args":"spiraling"}'
run_pair "$SS" skill-nonstring-forced-slow "$PL" -
mkjson 'garbage mentioning spiraling'
run_pair "$SS" garbage-spiraling "$PL" -
mkjson 'garbage plain'
run_pair "$SS" garbage-plain "$PL" -
printf '' > "$PL"
run_pair "$SS" empty-stdin "$PL" -
# multi-doc (no NUL): old and new jq both see both docs
printf '%s\n%s' '{"tool_input":{"skill":"x"}}' '{"tool_input":{"skill":"spiraling"}}' > "$PL"
run_pair "$SS" multidoc-x-spiraling "$PL" -
printf '%s\n%s' '{"tool_input":{"skill":"spiraling"}}' '{"tool_input":{"skill":"x"}}' > "$PL"
run_pair "$SS" multidoc-spiraling-x "$PL" -
# NUL cases — old jq read raw stdin; new truncates at NUL (header argument)
printf '{"tool_input":{"skill":"spiraling"}}\0junk-after' > "$PL"
run_pair "$SS" nul-after-spiraling-doc "$PL" -
printf '{"tool_input":{"skill":"x"}}\0{"tool_input":{"skill":"spiraling"}}' > "$PL"
run_pair "$SS" nul-hides-second-doc "$PL" -
printf '{"tool_input":{"skill":"spir\0aling"}}' > "$PL"
run_pair "$SS" nul-inside-value "$PL" -
printf '%s\n%s' '{"tool_input":{"skill":"spiraling"}}' '{"tool_input":{"skill":"spir' > "$PL"
run_pair "$SS" multidoc-truncated-second "$PL" -
# LOA_PROJECT_ROOT relative default (.) vs explicit
mkjson '{"tool_name":"Skill","tool_input":{"skill":"spiraling"}}'
run_pair "$SS" spiraling-explicit-root "$PL" - LOA_PROJECT_ROOT=.
# spiraling in args only (slow path, no sentinel)
mkjson '{"tool_name":"Skill","tool_input":{"skill":"implement","args":"run spiraling later"}}'
run_pair "$SS" spiraling-in-args "$PL" -

# =============================================================================
# Section ML — mutation-logger.sh
# =============================================================================
ML=mutation-logger.sh

mkcmd() {  # <command-string> [exit_code]
  jq -cn --arg c "$1" --argjson ec "${2:-0}" \
    '{tool_name:"Bash",tool_input:{command:$c},tool_result:{exit_code:$ec}}' > "$PL"
}

mkcmd 'ls -la /tmp'
run_pair "$ML" benign-ls "$PL" -
mkcmd 'git commit -m "chore: update"'
run_pair "$ML" mutating-git "$PL" -
mkcmd 'GIT COMMIT -M X'
run_pair "$ML" mutating-upper "$PL" -
mkcmd 'Docker Run --rm img'
run_pair "$ML" mutating-mixed-case "$PL" -
mkcmd 'echo prep && npm install'
run_pair "$ML" chained-and "$PL" -
mkcmd 'true;cargo build'
run_pair "$ML" chained-semi "$PL" -
mkcmd 'cat f | kubectl apply -f -'
run_pair "$ML" chained-pipe "$PL" -
mkcmd 'sudo make install'
run_pair "$ML" prefix-sudo "$PL" -
mkcmd 'env FOO=1 yarn build'
run_pair "$ML" prefix-env "$PL" -
mkcmd 'command mkdir -p /tmp/d'
run_pair "$ML" prefix-command "$PL" -
mkcmd 'sudo  env  A=1  git  push'
run_pair "$ML" prefix-stacked "$PL" -
mkcmd 'github actions status'
run_pair "$ML" nearmiss-github "$PL" -
mkcmd 'digit status'
run_pair "$ML" nearmiss-digit "$PL" -
mkcmd 'echo git'
run_pair "$ML" nearmiss-verb-no-space "$PL" -
mkcmd 'formative -rm'
run_pair "$ML" nearmiss-formative "$PL" -
mkcmd 'echo docker'
run_pair "$ML" nearmiss-trailing-verb "$PL" -
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"echo line1\ngit push origin"},"tool_result":{"exit_code":0}}' > "$PL"
run_pair "$ML" multiline-verb-line2 "$PL" -
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"echo git\necho push"},"tool_result":{"exit_code":0}}' > "$PL"
run_pair "$ML" multiline-split-nomatch "$PL" -
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"a\r\ngit push"},"tool_result":{"exit_code":0}}' > "$PL"
run_pair "$ML" multiline-crlf "$PL" -
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git\tstatus --short"},"tool_result":{"exit_code":0}}' > "$PL"
run_pair "$ML" tab-after-verb "$PL" -
mkcmd '   git push'
run_pair "$ML" leading-spaces "$PL" -
mkcmd '-n'
run_pair "$ML" echo-option-shape "$PL" -
mkcmd '-e git push'
run_pair "$ML" dash-e-prefix "$PL" -
mkcmd 'gіt push'
run_pair "$ML" cyrillic-homoglyph "$PL" -
mkcmd ''
run_pair "$ML" empty-command "$PL" -
mkcmd 'rm -rf /tmp/scratch'
run_pair "$ML" mutating-rm "$PL" -
mkcmd 'pnpm dlx create-app'
run_pair "$ML" mutating-pnpm "$PL" -
mkcmd 'npx cowsay hi'
run_pair "$ML" mutating-npx "$PL" -
mkcmd 'chmod +x f.sh' 1
run_pair "$ML" mutating-nonzero-exit "$PL" -
# non-numeric exit_code: builder fails, filter+touch still run
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git push"},"tool_result":{"exit_code":"boom"}}' > "$PL"
run_pair "$ML" nonnumeric-exit "$PL" -
# container command (pass-3 accepted class: tojson render); mutating bytes
printf '%s' '{"tool_name":"Bash","tool_input":{"command":["git","push"]},"tool_result":{"exit_code":0}}' > "$PL"
run_pair "$ML" container-command "$PL" -
# NUL escape in command (pass-3 denul class)
printf '%s' "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git ${U}0000 push origin\"},\"tool_result\":{\"exit_code\":0}}" > "$PL"
run_pair "$ML" nul-escape-command "$PL" -
mkjson 'garbage not json'
run_pair "$ML" garbage "$PL" -
printf '' > "$PL"
run_pair "$ML" empty-stdin "$PL" -
# identity env vars flow into the logged line
mkcmd 'git push origin main'
run_pair "$ML" env-identity "$PL" - LOA_TEAM_MEMBER=bench-mate LOA_TRACE_ID=tr-1 LOA_CURRENT_MODEL=m1
# 100KB commands — benign and mutating (regex pathology check rides ab-pass9)
python3 - "$PL" benign <<'PYEOF'
import json, sys
pad = "wordpad " * 12800
cmd = pad if sys.argv[2] == "benign" else pad + "; git push"
payload = {"tool_name": "Bash", "tool_input": {"command": cmd},
           "tool_result": {"exit_code": 0}}
open(sys.argv[1], "w").write(json.dumps(payload))
PYEOF
run_pair "$ML" big-100kb-benign "$PL" -
python3 - "$PL" mut <<'PYEOF'
import json, sys
pad = "wordpad " * 12800
cmd = pad + "; git push"
payload = {"tool_name": "Bash", "tool_input": {"command": cmd},
           "tool_result": {"exit_code": 0}}
open(sys.argv[1], "w").write(json.dumps(payload))
PYEOF
run_pair "$ML" big-100kb-mutating "$PL" -

echo ""
echo "pass-9 differential corpus: $total cases, $fail divergences"
[[ $fail -eq 0 ]]
