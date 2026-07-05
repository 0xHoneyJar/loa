#!/usr/bin/env bash
# =============================================================================
# pass-4 differential corpus: OLD (repo working tree) vs NEW (staging/pass4)
# Compares: exit code, stdout, stderr, and full side-effect tree
# (settings.local.json bytes, audit.jsonl, trajectory files, markers,
# context/archive trees) with timestamps normalized.
# =============================================================================
set -uo pipefail
export LC_ALL=C

REPO=/home/merlin/Documents/thj/code/loa
STAGE=$REPO/grimoires/loa/perf/skill-loop-2026-07-05/staging/pass4
WORK=${1:-/tmp/p4diff/work}
rm -rf "$WORK" && mkdir -p "$WORK"

PASS=0; FAIL=0; XPASS=0
declare -a FAILURES=()

norm() {  # normalize timestamps + dates + the old/new sandbox root on stdin
  sed -E -e "s|${TARGET_OLD:-__NOTGT__}: line [0-9]+:|__SCRIPT_LINE__:|" \
         -e "s|${TARGET_NEW:-__NOTGT__}: line [0-9]+:|__SCRIPT_LINE__:|" \
         -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z/__TS__/g' \
         -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2}/__DATE__/g' \
         -e "s|${NORM_ROOT:-__NOROOT__}/(old\|new)|__SB__|g"
}

# tree_dump <dir> — deterministic listing + normalized content of every file
# (NUL-safe: multi-line archive paths create newline-bearing dirnames, which
# are themselves part of the behavior under comparison)
tree_dump() {
  local d="$1" f
  ( cd "$d" 2>/dev/null || exit 0
    local -a entries files
    mapfile -d '' -t entries < <(find . -mindepth 1 \( -name stdout -o -name stderr -o -name exitcode -o -name hookdir \) -prune -o -print0 | sort -z)
    for f in ${entries[@]+"${entries[@]}"}; do printf '%s' "$f" | norm; printf '\n'; done
    mapfile -d '' -t files < <(find . \( -name stdout -o -name stderr -o -name exitcode -o -name hookdir \) -prune -o -type f -print0 | sort -z)
    for f in ${files[@]+"${files[@]}"}; do
      printf '===== '; printf '%s' "$f" | norm; printf ' =====\n'
      norm < "$f"
    done
  )
}

# run_case <name> <mode> — mode: strict (stdout+stderr+exit+tree) or
#   nostderr (exit+stdout+tree only; stderr divergence accepted/logged)
# expects: setup_case <dir> defined; TARGET_OLD/TARGET_NEW; run_target <dir> <script>
run_case() {
  local name="$1" mode="$2"
  local base="$WORK/$name"
  NORM_ROOT="$base"
  for v in old new; do
    mkdir -p "$base/$v"
    setup_case "$base/$v"
  done
  run_target "$base/old" "$TARGET_OLD"
  run_target "$base/new" "$TARGET_NEW"
  local ok=1 why=""
  if ! diff -q <(cat "$base/old/exitcode") <(cat "$base/new/exitcode") >/dev/null; then
    ok=0; why="exit($(cat "$base/old/exitcode")→$(cat "$base/new/exitcode"))"
  fi
  if ! diff -q <(norm < "$base/old/stdout") <(norm < "$base/new/stdout") >/dev/null; then
    ok=0; why="$why stdout"
  fi
  if [[ "$mode" == "strict" ]]; then
    if ! diff -q <(norm < "$base/old/stderr") <(norm < "$base/new/stderr") >/dev/null; then
      ok=0; why="$why stderr"
    fi
  fi
  if ! diff -q <(tree_dump "$base/old") <(tree_dump "$base/new") >/dev/null; then
    ok=0; why="$why tree"
  fi
  if (( ok )); then
    PASS=$((PASS+1)); printf 'PASS  %-55s %s\n' "$name" "$mode"
  else
    FAIL=$((FAIL+1)); FAILURES+=("$name: $why")
    printf 'FAIL  %-55s %s\n' "$name" "$why"
  fi
}

# =============================================================================
# SECTION 1: settings-cleanup.sh
# =============================================================================
echo "=== settings-cleanup ==="
TARGET_OLD=$REPO/.claude/hooks/hygiene/settings-cleanup.sh
TARGET_NEW=$STAGE/settings-cleanup.sh

run_target() {  # <dir> <script> — Stop-hook contract: stdin JSON (ignored), cwd
  local d="$1" s="$2"
  ( cd "$d" && printf '{"hook_event_name":"Stop"}' | "$s" > stdout 2> stderr; echo $? > exitcode )
}

mk_settings() {  # <dir> <jq-program building the doc>  (also mkdir .run)
  mkdir -p "$1/.claude" "$1/.run"
  jq -n "$2" > "$1/.claude/settings.local.json"
}

# helper: entries that pad a file over 64KB
PAD='[range(0; 900) | "Bash(echo bench-entry-number-\(.) --with-some-longer-arguments:*)"]'

setup_case() { mk_settings "$1" "{permissions: {allow: ($PAD + [\"Bash(\" + (\"x\" * 300) + \":*)\"])}}"; }
run_case "sc-golden-large-fixture" strict

setup_case() { mkdir -p "$1/.claude" "$1/.run"; cp "$REPO/.claude/settings.local.json" "$1/.claude/settings.local.json"; }
run_case "sc-real-settings-55k-early-exit" strict

setup_case() {
  mkdir -p "$1/.claude" "$1/.run"
  jq ".permissions.allow += [range(0; 200) | \"Bash(echo realistic-pad-entry-\(.) --with-longer-arguments-to-cross-threshold:*)\"] + [\"Bash(\" + (\"y\" * 250) + \":*)\"]" \
    "$REPO/.claude/settings.local.json" > "$1/.claude/settings.local.json"
}
run_case "sc-real-settings-padded-over-64k" strict

setup_case() {
  mkdir -p "$1/.claude" "$1/.run"
  jq ".permissions.allow += [range(0; 200) | \"Bash(echo realistic-pad-entry-\(.) --with-longer-arguments-to-cross-threshold:*)\"]" \
    "$REPO/.claude/settings.local.json" > "$1/.claude/settings.local.json"
}
run_case "sc-real-settings-padded-nothing-removed" strict

# exact 64KB boundary (65536 bytes → full path) and 65535 (early exit)
mk_exact() {  # <dir> <target-size>
  mkdir -p "$1/.claude" "$1/.run"
  local f="$1/.claude/settings.local.json"
  jq -n "{permissions: {allow: ($PAD + [\"Bash(\" + (\"x\" * 300) + \":*)\"] + [\"FILLER\"])}}" > "$f"
  local sz gap
  sz=$(stat -c%s "$f")
  gap=$(( $2 - sz ))
  # grow/shrink FILLER by gap bytes (ASCII only → bytes == chars)
  jq --argjson n "$gap" '.permissions.allow |= map(if . == "FILLER" then "F" + ("f" * (5 + $n)) else . end)' "$f" > "$f.t" && mv "$f.t" "$f"
  sz=$(stat -c%s "$f")
  [[ "$sz" -eq "$2" ]] || echo "WARN: exact-size build got $sz wanted $2" >&2
}
setup_case() { mk_exact "$1" 65536; }
run_case "sc-exact-65536-full-path" strict
setup_case() { mk_exact "$1" 65535; }
run_case "sc-65535-early-exit" strict

setup_case() { mk_settings "$1" "{permissions: {allow: ($PAD + [\"Bash(echo 🦋🌈 unicode-kept:*)\"] + [\"Bash(echo \" + (\"🦋\" * 300) + \":*)\"] + [\"Bash(echo café-naïve-日本語:*)\"])}}"; }
run_case "sc-unicode-emoji-entries" strict

setup_case() { mk_settings "$1" '{permissions: {allow: ([range(0; 900) | "Bash(echo bench-entry-number-\(.) --with-some-longer-arguments:*)"] + ["Bash(echo \"quoted \\\\ backslash\" and more:*)"] + ["Bash(" + ("x" * 300) + ":*)"] )}}'; }
run_case "sc-quotes-backslashes" strict

setup_case() {
  mk_settings "$1" "{permissions: {allow: ($PAD + [\"Bash(\" + (\"x\" * 300) + \":*)\"])}}"
  local f="$1/.claude/settings.local.json"
  head -c $(( $(stat -c%s "$f") - 100 )) "$f" > "$f.t" && mv "$f.t" "$f"
}
run_case "sc-malformed-json-truncated" strict

setup_case() { mkdir -p "$1/.claude" "$1/.run"; : > "$1/.claude/settings.local.json"; }
run_case "sc-empty-file" strict

setup_case() { mkdir -p "$1/.claude" "$1/.run"; }
run_case "sc-no-settings-file" strict

setup_case() { mk_settings "$1" "{permissions: {allow: ([range(0; 1000) | \"Bash(echo unsorted-\(1000 - .) nothing-removable-here --args:*)\"])}}"; }
run_case "sc-large-nothing-removed-no-write" strict

setup_case() { mk_settings "$1" "{permissions: {allow: ($PAD + [\"Bash(echo dupe:*)\", \"Bash(echo dupe:*)\"])}}"; }
run_case "sc-duplicates-unique-dedup" strict

setup_case() { mk_settings "$1" "{permissions: {allow: ($PAD + [\"Bash(\" + (\"x\" * 300) + \":*)\"]), deny: [\"Bash(echo ghp_123456789012345678901234567890123456:*)\", \"Bash(curl https://user:pass@host:*)\"]}}"; }
run_case "sc-cred-in-deny-scan-warnings" strict

# private-key material remaining in deny: the OLD grep post-scan can never
# match the leading-dash pattern (option-parse defect) — new must replicate
setup_case() { mk_settings "$1" "{permissions: {allow: ($PAD + [\"Bash(\" + (\"x\" * 300) + \":*)\"]), deny: [\"Bash(echo -----BEGIN RSA PRIVATE KEY-----:*)\"]}}"; }
run_case "sc-privkey-in-deny-preserved-defect" strict

# cross-line '://' + ':x@' trap: whole-text scan must NOT match where the
# per-line grep did not (pattern 7 stays on the line model)
setup_case() { mk_settings "$1" "{permissions: {allow: ($PAD + [\"Bash(\" + (\"x\" * 300) + \":*)\"]), deny: [\"Bash(see https://example:*)\", \"Bash(echo user:pass@host:*)\"]}}"; }
run_case "sc-crossline-url-cred-trap" strict

setup_case() { mk_settings "$1" "{permissions: {allow: ($PAD + [\"Bash(echo line1\\nline2:*)\"] + [\"Bash(echo AKIA1234567890ABCDEF:*)\"] + [\"Bash(echo eyJhbGciOi.payload:*)\"] + [\"Bash(echo Bearer tok.en-123:*)\"] + [\"Bash(echo sk-abcdefghijklmnopqrstuv:*)\"])}}"; }
run_case "sc-multiline-and-credential-entries" strict

setup_case() { mk_settings "$1" "{permissions: {allow: ($PAD + [(\"K\" * 200)] + [(\"L\" * 201)])}}"; }
run_case "sc-200-201-boundary" strict

setup_case() { mk_settings "$1" "{permissions: {allow: []}, env: {PAD: (\"p\" * 70000)}}"; }
run_case "sc-large-empty-allow-skip" strict

setup_case() { mk_settings "$1" "{permissions: {deny: []}, env: {PAD: (\"p\" * 70000)}}"; }
run_case "sc-large-allow-missing-skip" strict

setup_case() { mk_settings "$1" "{permissions: {allow: ((($PAD) + [(\"S\" * 300)]) | tojson)}, env: {PAD: (\"p\" * 9000)}}"; }
run_case "sc-allow-string-encoded-array" strict

setup_case() { mk_settings "$1" "{permissions: {allow: {a: \"Bash(echo short:*)\", b: (\"B\" * 300)}}, env: {PAD: (\"p\" * 70000)}}"; }
run_case "sc-allow-object-value" nostderr

setup_case() { mk_settings "$1" "{permissions: {allow: 42}, env: {PAD: (\"p\" * 70000)}}"; }
run_case "sc-allow-number-value" nostderr

setup_case() { mk_settings "$1" "{permissions: {allow: \"foo bar\"}, env: {PAD: (\"p\" * 70000)}}"; }
run_case "sc-allow-garbage-string" nostderr

setup_case() {
  mk_settings "$1" "{permissions: {allow: ($PAD + [\"Bash(\" + (\"x\" * 300) + \":*)\"])}}"
  local f="$1/.claude/settings.local.json"
  cat "$f" "$f" > "$f.t" && mv "$f.t" "$f"   # two concatenated docs
}
run_case "sc-multi-doc-file" nostderr

setup_case() { mkdir -p "$1/.claude"; jq -n "{permissions: {allow: ($PAD + [\"Bash(\" + (\"x\" * 300) + \":*)\"])}}" > "$1/.claude/settings.local.json"; }
run_case "sc-no-run-dir-mkdir-path" strict

# =============================================================================
# SECTION 2: post-compact-reminder.sh
# =============================================================================
echo "=== post-compact-reminder ==="
TARGET_OLD=$REPO/.claude/hooks/post-compact-reminder.sh
TARGET_NEW=$STAGE/post-compact-reminder.sh

run_target() {  # UserPromptSubmit contract; HOME + PROJECT_ROOT into sandbox
  local d="$1" s="$2"
  ( cd "$d/proj" && printf '{"prompt":"hello"}' | \
      env HOME="$d/home" PROJECT_ROOT="$d/proj" "$s" > ../stdout 2> ../stderr; echo $? > ../exitcode )
}

pc_base() {  # <dir> — proj skeleton with a2a parent (trajectory loggable)
  mkdir -p "$1/proj/.run" "$1/proj/grimoires/loa/a2a" "$1/home/.local/state/loa-compact"
}
mkmarker() { printf '%s' "$2" > "$1"; }

setup_case() { pc_base "$1"; mkmarker "$1/proj/.run/compact-pending" '{"run_mode": {"active": true, "state": "RUNNING"}, "simstim": {"active": false, "phase": "unknown"}}'; }
run_case "pc-marker-running" strict

setup_case() { pc_base "$1"; mkmarker "$1/proj/.run/compact-pending" '{"run_mode": {"active": true, "state": "HALTED"}, "simstim": {"active": true, "phase": "implementation"}}'; }
run_case "pc-marker-halted-simstim" strict

setup_case() { pc_base "$1"; mkmarker "$1/proj/.run/compact-pending" '{"run_mode": {"active": true, "state": "JACKED_OUT"}, "simstim": {"active": true, "phase": "flatline_sdd"}}'; }
run_case "pc-marker-jacked-simstim" strict

setup_case() { pc_base "$1"; mkmarker "$1/proj/.run/compact-pending" '{"run_mode": {"active": "true", "state": "EVIL\nINJECTED $(rm -rf /) `x`"}, "simstim": {"active": true, "phase": "not-a-phase"}}'; }
run_case "pc-marker-injection-attempt" strict

setup_case() { pc_base "$1"; mkmarker "$1/proj/.run/compact-pending" '{broken json'; }
run_case "pc-marker-malformed" strict

setup_case() { pc_base "$1"; : > "$1/proj/.run/compact-pending"; }
run_case "pc-marker-empty-file" strict

setup_case() { pc_base "$1"; }
run_case "pc-no-marker" strict

setup_case() { pc_base "$1"; mkmarker "$1/home/.local/state/loa-compact/compact-pending" '{"run_mode": {"active": true, "state": "RUNNING"}, "simstim": {"active": false, "phase": "unknown"}}'; }
run_case "pc-global-marker-only" strict

setup_case() { pc_base "$1"
  mkmarker "$1/proj/.run/compact-pending" '{"run_mode": {"active": true, "state": "HALTED"}, "simstim": {"active": false, "phase": "unknown"}}'
  mkmarker "$1/home/.local/state/loa-compact/compact-pending" '{"run_mode": {"active": false, "state": "unknown"}, "simstim": {"active": false, "phase": "unknown"}}'
}
run_case "pc-both-markers-project-wins" strict

setup_case() { pc_base "$1"; mkmarker "$1/proj/.run/compact-pending" '{"run_mode": {"active": {"weird": 1}, "state": ["container"]}, "simstim": {"active": 0, "phase": 3.14}}'; }
run_case "pc-container-values" strict

setup_case() { pc_base "$1"; mkmarker "$1/proj/.run/compact-pending" '{"run_mode": "scalar", "simstim": {"active": true, "phase": "planning"}}'; }
run_case "pc-scalar-run-mode-partial-fields" strict

setup_case() { pc_base "$1"; printf '%s\n%s' '{"run_mode": {"active": true, "state": "RUNNING"}}' '{"run_mode": {"active": false}}' > "$1/proj/.run/compact-pending"; }
run_case "pc-multi-doc-marker" strict

setup_case() { mkdir -p "$1/proj/.run" "$1/home/.local/state/loa-compact"; mkmarker "$1/proj/.run/compact-pending" '{"run_mode": {"active": true, "state": "RUNNING"}, "simstim": {"active": false, "phase": "unknown"}}'; }
run_case "pc-trajectory-parent-missing" strict

setup_case() { pc_base "$1"; mkmarker "$1/proj/.run/compact-pending" '{"note": "percent %s %d and \\ backslash", "run_mode": {"active": true, "state": "RUNNING"}}'; }
run_case "pc-percent-backslash-marker" strict

setup_case() { pc_base "$1"
  mkmarker "$1/proj/.run/compact-pending" '{"run_mode": {"active": true, "state": "RUNNING"}, "simstim": {"active": false, "phase": "unknown"}}'
  mkdir -p "$1/proj/.claude/scripts"
  printf '#!/usr/bin/env bash\necho "traj summary line 1"\necho "traj summary line 2"\n' > "$1/proj/.claude/scripts/trajectory-gen.sh"
  chmod +x "$1/proj/.claude/scripts/trajectory-gen.sh"
}
run_case "pc-trajectory-script-present" strict

setup_case() { pc_base "$1"; mkmarker "$1/proj/.run/compact-pending" '{"run_mode": {"active": true, "state": "RUNNING\n"}, "simstim": {"active": true, "phase": "complete"}}'; }
run_case "pc-trailing-newline-state-value" strict

# =============================================================================
# SECTION 3: cleanup-context.sh
# =============================================================================
echo "=== cleanup-context ==="
TARGET_OLD=$REPO/.claude/scripts/cleanup-context.sh
TARGET_NEW=$STAGE/cleanup-context.sh

CC_ARGS=()
run_target() {
  local d="$1" s="$2"
  ( cd "$d" && setsid env LOA_CONTEXT_DIR="$d/ctx" LOA_LEDGER="$d/ledger.json" \
      LOA_ARCHIVE_BASE="$d/archive" "$s" ${CC_ARGS[@]+"${CC_ARGS[@]}"} \
      < /dev/null > stdout 2> stderr; echo $? > exitcode )
}

cc_ctx() {  # <dir> — populated context dir
  mkdir -p "$1/ctx/research"
  printf '# doc %s\ncontent\n' 1 > "$1/ctx/doc-1.md"
  printf '# doc %s\ncontent\n' 2 > "$1/ctx/doc-2.md"
  printf '# README\n' > "$1/ctx/README.md"
  printf 'nested\n' > "$1/ctx/research/a.md"
}
LEDGER_FULL='{"active_cycle":"cycle-b","cycles":[{"id":"cycle-a","status":"archived","archived_at":"2026-06-01T00:00:00Z","archive_path":"ARCH/2026-06-01-a"},{"id":"cycle-b","status":"active","archive_path":"ARCH/2026-07-05-b"}]}'

setup_case() { cc_ctx "$1"; printf '%s' "${LEDGER_FULL//ARCH/$1\/archive}" > "$1/ledger.json"; }
run_case "cc-full-archive-active-cycle" strict

setup_case() { cc_ctx "$1"; printf '{"cycles":[{"id":"cycle-a","status":"archived","archived_at":"2026-06-01T00:00:00Z","archive_path":"%s/archive/2026-06-01-a"},{"id":"cycle-c","status":"archived","archived_at":"2026-06-20T00:00:00Z","archive_path":"%s/archive/2026-06-20-c"}]}' "$1" "$1" > "$1/ledger.json"; }
run_case "cc-no-active-fallback-most-recent-archived" strict

setup_case() { cc_ctx "$1"; printf '{"active_cycle":"missing-id","cycles":[{"id":"cycle-a","status":"archived","archived_at":"2026-06-01T00:00:00Z","archive_path":"%s/archive/2026-06-01-a"}]}' "$1" > "$1/ledger.json"; }
run_case "cc-active-id-missing-fallback" strict

setup_case() { cc_ctx "$1"; mkdir -p "$1/archive/2026-05-01-old" "$1/archive/2026-06-15-newer"; }
run_case "cc-no-ledger-find-archive-dir" strict

setup_case() { cc_ctx "$1"; }
run_case "cc-no-ledger-dated-fallback" strict

setup_case() { cc_ctx "$1"; printf '{broken' > "$1/ledger.json"; }
run_case "cc-malformed-ledger" strict

setup_case() { cc_ctx "$1"; printf '{"active_cycle":"x"}' > "$1/ledger.json"; }
run_case "cc-ledger-no-cycles-key" strict

setup_case() { cc_ctx "$1"; printf '{"active_cycle":7,"cycles":[{"id":"7","status":"active","archive_path":"%s/archive/numeric"},{"id":7,"status":"active","archive_path":"%s/archive/really-numeric"}]}' "$1" "$1" > "$1/ledger.json"; }
run_case "cc-numeric-active-cycle" strict

setup_case() { cc_ctx "$1"; printf '{"active_cycle":"dup","cycles":[{"id":"dup","status":"active","archive_path":"%s/archive/first"},{"id":"dup","status":"active","archive_path":"%s/archive/second"}]}' "$1" "$1" > "$1/ledger.json"; }
run_case "cc-duplicate-cycle-ids-multiline" strict

setup_case() { cc_ctx "$1"; printf '{"active_cycle":"cycle-b","cycles":[{"id":"cycle-b","status":"active","archive_path":null},{"id":"cycle-a","status":"archived","archived_at":"2026-06-01T00:00:00Z","archive_path":"%s/archive/2026-06-01-a"}]}' "$1" > "$1/ledger.json"; }
run_case "cc-active-null-archive-path-fallback" strict

setup_case() { mkdir -p "$1"; }   # no ctx dir at all
run_case "cc-no-context-dir-early-exit" strict

setup_case() { mkdir -p "$1/ctx"; printf '# README\n' > "$1/ctx/README.md"; }
run_case "cc-already-clean-early-exit" strict

CC_ARGS=(--dry-run --verbose)
setup_case() { cc_ctx "$1"; printf '%s' "${LEDGER_FULL//ARCH/$1\/archive}" > "$1/ledger.json"; }
run_case "cc-dry-run-verbose" strict

CC_ARGS=(--no-archive)
setup_case() { cc_ctx "$1"; printf '%s' "${LEDGER_FULL//ARCH/$1\/archive}" > "$1/ledger.json"; }
run_case "cc-no-archive" strict

CC_ARGS=(--prompt)
setup_case() { cc_ctx "$1"; printf '%s' "${LEDGER_FULL//ARCH/$1\/archive}" > "$1/ledger.json"; }
run_case "cc-prompt-no-tty-defaults-yes" strict
CC_ARGS=()

# =============================================================================
# SECTION 4: mutation-logger.sh
# =============================================================================
echo "=== mutation-logger ==="
TARGET_OLD=$REPO/.claude/hooks/audit/mutation-logger.sh
TARGET_NEW=$STAGE/mutation-logger.sh

ML_PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"tool_result":{"exit_code":0}}'
run_target() {
  local d="$1" s="$2"
  ( cd "$d" && printf '%s' "$ML_PAYLOAD" | "$s" > stdout 2> stderr; echo $? > exitcode )
}

setup_case() { mkdir -p "$1/.run"; }
run_case "ml-mutating-run-exists" strict

setup_case() { mkdir -p "$1"; }
run_case "ml-mutating-no-run-dir" strict

ML_PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"ls -la"},"tool_result":{"exit_code":0}}'
setup_case() { mkdir -p "$1/.run"; }
run_case "ml-benign" strict

ML_PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"git push"},"tool_result":{"exit_code":0}}'
setup_case() {  # >10MB audit log → rotation path (deterministic content)
  mkdir -p "$1/.run"
  yes '{"ts":"2026-01-01T00:00:00Z","tool":"Bash","command":"filler","exit_code":0}' | head -c 10500000 > "$1/.run/audit.jsonl"
}
run_case "ml-rotation-over-10mb" strict

# =============================================================================
# SECTION 5: write-mutation-logger.sh
# =============================================================================
echo "=== write-mutation-logger ==="
TARGET_OLD=$REPO/.claude/hooks/audit/write-mutation-logger.sh
TARGET_NEW=$STAGE/write-mutation-logger.sh

WML_PAYLOAD='{"tool_name":"Write","tool_input":{"file_path":"grimoires/loa/NOTES.md","content":"x"}}'
run_target() {
  local d="$1" s="$2"
  ( cd "$d" && printf '%s' "$WML_PAYLOAD" | "$s" > stdout 2> stderr; echo $? > exitcode )
}
setup_case() { mkdir -p "$1/.run"; }
run_case "wml-write-run-exists" strict
setup_case() { mkdir -p "$1"; }
run_case "wml-write-no-run-dir" strict

# =============================================================================
# SECTION 6: karpathy-surgical-diff-check.sh
# =============================================================================
echo "=== karpathy ==="
TARGET_OLD=$REPO/.claude/hooks/quality/karpathy-surgical-diff-check.sh
TARGET_NEW=$STAGE/karpathy-surgical-diff-check.sh

KP_PAYLOAD='{"tool_name":"Write","tool_input":{"file_path":"src/x.md","content":"a\nb\nc\n"}}'
KP_STATE_ENV=""     # per-case override of KARPATHY_TASK_STATE (empty = default sandbox path)
KP_INVOKE="abs"     # abs | rel
run_target() {
  local d="$1" s="$2"
  local state="$d/.run/karpathy-task-state.jsonl"
  [[ -n "$KP_STATE_ENV" ]] && state="$d/$KP_STATE_ENV"
  local -a cmd=("$s")
  if [[ "$KP_INVOKE" == "rel" ]]; then
    # invoke via a relative path (exercises the SCRIPT_DIR idiom)
    mkdir -p "$d/hookdir"; cp "$s" "$d/hookdir/kp.sh"; cmd=(bash "hookdir/kp.sh")
  fi
  ( cd "$d" && printf '%s' "$KP_PAYLOAD" | \
      env LOA_CONFIG_OVERRIDE="$REPO/.loa.config.yaml" \
          KARPATHY_TASK_STATE="$state" \
          KARPATHY_TRAJECTORY_DIR="$d/traj" \
          LOA_SESSION_ID="bench-session" \
      "${cmd[@]}" > stdout 2> stderr; echo $? > exitcode )
}
kp_seed() { mkdir -p "$1/.run"; printf '{"ts":"2026-07-05T00:00:00Z","tool":"Write","file":"seed.md","lines_changed":200,"running_total":200,"session_id":"bench-seed"}\n' > "$1/.run/karpathy-task-state.jsonl"; }

setup_case() { kp_seed "$1"; }
run_case "kp-warn-regime-write" strict

setup_case() { mkdir -p "$1/.run"; : > "$1/.run/karpathy-task-state.jsonl"; }
run_case "kp-fresh-state" strict

KP_PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"tests/unit/x.bats","new_string":"1\n2\n"}}'
setup_case() { kp_seed "$1"; }
run_case "kp-warn-regime-edit" strict

KP_PAYLOAD='{"tool_name":"Write","tool_input":{"file_path":"src/x.md","content":"a\n"}}'
KP_STATE_ENV="deep/newdir/state.jsonl"
setup_case() { mkdir -p "$1"; }
run_case "kp-state-parent-missing-mkdir" strict
KP_STATE_ENV=""

KP_INVOKE="rel"
setup_case() { kp_seed "$1"; }
run_case "kp-relative-invocation-scriptdir" strict
KP_INVOKE="abs"

# state file with crash-truncated final line (awk-vs-jq divergence guard:
# the awk running-total path is UNCHANGED — this proves it)
setup_case() { kp_seed "$1"; printf '{"ts":"2026-07-05T00:01:00Z","tool":"Write","file":"t.md","lines_changed":42,"running_tot' >> "$1/.run/karpathy-task-state.jsonl"; }
run_case "kp-truncated-state-line" strict

# =============================================================================
echo ""
echo "RESULT: PASS=$PASS FAIL=$FAIL"
if (( FAIL > 0 )); then
  printf 'FAILURE: %s\n' "${FAILURES[@]}"
  exit 1
fi
