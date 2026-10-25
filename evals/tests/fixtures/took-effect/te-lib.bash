# shellcheck shell=bash
# =============================================================================
# evals/tests/fixtures/took-effect/te-lib.bash — the run builder of took-effect-{hooks,transcripts,integrity}.bats
# (cycle-134 Sprint 276, Tasks 1.1-1.3). Sourced from a bats file; no model call, no docker.
#
# te_setup                  paths and a fresh $T
# te_build [phases-json]    a home-scope review-catch run that reaches oracle_closed clause (g): the PR fixture (one
#                           data path, .claude/protocols/p.md, head and base differ at line 5), the pinned source
#                           repository (commit H = the PR head, commit F = the pin with a later p.md and a
#                           .claude/checksums.json), the sandbox through the real mount library's home-scope overlay,
#                           meta/arm-evidence.txt (home_hook_counts=SessionStart:1, home_mcp_servers=),
#                           meta/pipeline.json (source_commit F; phases default REVIEW), the task yaml and a suite
#                           with arm a1_te (took_effect: oracle_closed). Transcripts and process samples are empty.
# te_clean [label …]        a complete transcript and a process sample per label: init, one SessionStart:startup
#                           hook, a Read of the PR's p.md (the first label only; clause (f)), the result event
# te_init / te_hook / te_tool / te_user / te_result / te_read / te_ps   one event (or sample) each
# te_run                    took-effect.sh on the run; te_oc prints its oracle_closed line
# =============================================================================

te_setup() {
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  LIB="$REPO_ROOT/evals/harness/lib/sandbox-mount.sh"
  TE="$REPO_ROOT/evals/harness/took-effect.sh"
  TFX="$TESTS_DIR/fixtures/took-effect"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/te.XXXXXX")"
  SRC="$T/src" FX="$T/fx" RD="$T/run"
  W="$RD/sandbox"
  export ARM_EVIDENCE_FILE="$RD/meta/arm-evidence.txt"
  unset SM_TEST_MODE SM_TEST_EXCLUDED_PREFIX
  TE_SID=s   # the session id every built event carries
}

te_teardown() {
  chmod -R u+rwx "$T" 2>/dev/null || true
  find "$T" -mindepth 1 -delete 2>/dev/null || true
  rmdir "$T" 2>/dev/null || true
}

# deterministic commits
te_g() {
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_DATE="2026-10-25T00:00:00Z" GIT_COMMITTER_DATE="2026-10-25T00:00:00Z" \
    git -C "$1" -c user.email=t@t -c user.name=t -c commit.gpgsign=false -c init.defaultBranch=main -c core.excludesFile=/dev/null "${@:2}"
}

te_body() {  # te_body <side> — p.md: ten lines, line 5 differs per side
  local i
  for i in 1 2 3 4; do echo "protocol line $i stays the same"; done
  echo "protocol line 5 says the guard runs ($1 version)"
  for i in 6 7 8 9 10; do echo "protocol line $i stays the same"; done
}

# te_manifest <root> — a checksums.json {algorithm, files} over <root>/.claude (the manifest file itself excluded)
te_manifest() {
  ( cd "$1" && find .claude -type f ! -path .claude/checksums.json -print | LC_ALL=C sort | while IFS= read -r f; do
      printf '%s\t%s\n' "$f" "$(sha256sum "$f" | cut -c1-64)"; done ) \
    | jq -Rn '{algorithm: "sha256", files: ([inputs | split("\t") | {key: .[0], value: .[1]}] | from_entries)}'
}

te_build() {
  local phases='[{"name": "REVIEW", "label": "REVIEW", "skipped": false, "skipped_reason": null}]'
  [[ -z "${1:-}" ]] || phases="$1"
  mkdir -p "$FX/head/.claude/protocols" "$FX/base/.claude/protocols"
  te_body head > "$FX/head/.claude/protocols/p.md"
  te_body base > "$FX/base/.claude/protocols/p.md"
  printf '%s\n' 'diff --git a/.claude/protocols/p.md b/.claude/protocols/p.md' '--- a/.claude/protocols/p.md' \
    '+++ b/.claude/protocols/p.md' '@@ -5 +5 @@' '-protocol line 5 says the guard runs (base version)' \
    '+protocol line 5 says the guard runs (head version)' > "$FX/head.diff"
  printf '# PR\n' > "$FX/PR.md"
  # the pinned framework: H (the PR head era) then F (the pin: a later p.md, its manifest)
  mkdir -p "$SRC/.claude/protocols" "$SRC/.claude/loa"
  cp "$FX/head/.claude/protocols/p.md" "$SRC/.claude/protocols/p.md"
  printf 'loa\n' > "$SRC/.claude/loa/CLAUDE.loa.md"
  te_manifest "$SRC" > "$SRC/.claude/checksums.json"
  ( cd "$SRC" && te_g . init -q && te_g . add -A && te_g . commit -qm head )
  H="$(git -C "$SRC" rev-parse HEAD)"
  sed -i 's/^protocol line 5 says the guard runs (head version)$/protocol line 5 now says the guard ALWAYS runs (LATER fix)/' "$SRC/.claude/protocols/p.md"
  te_manifest "$SRC" > "$SRC/.claude/checksums.json"
  ( cd "$SRC" && te_g . add -A && te_g . commit -qm fix )
  F="$(git -C "$SRC" rev-parse HEAD)"
  printf 'name: pr-te\nhead_commit: "%s"\nfix_commit: "%s"\n' "$H" "$F" > "$FX/fixture.yaml"
  # the sandbox as pipeline-run.sh materialises a review-catch run
  mkdir -p "$W/pr" "$RD/meta" "$RD/transcripts" "$RD/eval"
  cp -a "$FX/base" "$FX/head" "$FX/head.diff" "$FX/PR.md" "$W/pr/"
  te_g "$W" init -q
  printf '%s\n' '/.claude/' '/CLAUDE.md' '/.loa.config.yaml' '/grimoires/' '/.run/' '/.beads/' '/.eval/' >> "$W/.git/info/exclude"
  te_g "$W" add -A; te_g "$W" commit -qm base
  printf 'base_commit=%s\n' "$(git -C "$W" rev-parse HEAD)" > "$ARM_EVIDENCE_FILE"
  printf 'flatline_protocol:\n  enabled: true\n' > "$W/.loa.config.yaml"
  mkdir -p "$W/grimoires/loa/a2a/sprint-1" "$W/.eval"
  bash -c 'set -euo pipefail; source "$1"; shift; "$@"' _ "$LIB" overlay_answer_paths "$W" "$FX" head "$SRC" "$F" home-scope \
    >/dev/null || return 1
  printf 'home_hook_counts=SessionStart:1\nhome_mcp_servers=\n' >> "$ARM_EVIDENCE_FILE"
  echo a1_te > "$RD/meta/arm"
  jq -n --arg sc "$F" --argjson ph "$phases" '{schema_version: 1, arm: "a1_te", task_id: "rc-te", task_type: "review-catch",
     status: "completed", source_commit: $sc, arm_toggles: {}, phases: $ph}' > "$RD/meta/pipeline.json"
  mkdir -p "$T/suite/tasks/rc-te"
  printf 'id: rc-te\ntype: review-catch\nreview_catch: {fixture: "%s"}\n' "$FX" > "$T/suite/tasks/rc-te/task.yaml"
  TY="$T/suite/tasks/rc-te/task.yaml"
  S="$T/suite.yaml"
  cp "$TESTS_DIR/fixtures/ablation-runs/suite.yaml" "$S"
  yq -i '.arms += [{"id": "a1_te", "task_types": ["review-catch"], "toggles": {}, "phases": ["REVIEW"], "took_effect": ["oracle_closed"]}]' "$S"
}

te_ev() { printf '%s\n' "$2" >> "$RD/transcripts/events-$1.jsonl"; }   # te_ev <label> <json line>
te_init() {  # te_init <label> [jq edit] — the system/init event clause (g) reads (Claude Code 2.1.299)
  jq -cn --arg sid "$TE_SID" '{type: "system", subtype: "init", cwd: "/workspace", session_id: $sid, mcp_servers: [],
    slash_commands: ["review-sprint", "compact"], skills: ["reviewing-code"], agents: ["general-purpose"],
    output_style: "default", claude_code_version: "2.1.299",
    plugins: [{name: "cc-plugin-agents-md", path: "builtin", source: "cc-plugin-agents-md@builtin"}]}' \
    | jq -c "${2:-.}" >> "$RD/transcripts/events-$1.jsonl"
}
te_hook() {  # te_hook <label> <hook_name> <hook_event> [times]
  local i
  for i in $(seq 1 "${4:-1}"); do
    jq -cn --arg n "$2" --arg e "$3" --arg i "h$i" --arg sid "$TE_SID" '{type: "system", subtype: "hook_started", hook_id: $i, hook_name: $n, hook_event: $e, session_id: $sid}' \
      >> "$RD/transcripts/events-$1.jsonl"
  done
}
te_tool() {  # te_tool <label> <id> <tool> <input-json> <result-text> — a tool_use and its tool_result
  jq -cn --arg id "$2" --arg t "$3" --argjson i "$4" --arg sid "$TE_SID" '{type: "assistant", session_id: $sid, message: {content: [{type: "tool_use", id: $id, name: $t, input: $i}]}}' >> "$RD/transcripts/events-$1.jsonl"
  jq -cn --arg id "$2" --arg r "$5" --arg sid "$TE_SID" '{type: "user", session_id: $sid, message: {content: [{type: "tool_result", tool_use_id: $id, content: $r}]}}' >> "$RD/transcripts/events-$1.jsonl"
}
te_user() {  # te_user <label> <text> — a prompt turn (text content)
  jq -cn --arg t "$2" --arg sid "$TE_SID" '{type: "user", session_id: $sid, message: {role: "user", content: [{type: "text", text: $t}]}}' >> "$RD/transcripts/events-$1.jsonl"
}
te_result() {  # te_result <label> [jq edit]
  jq -cn --arg sid "$TE_SID" '{type: "result", subtype: "success", is_error: false, num_turns: 1, session_id: $sid}' | jq -c "${2:-.}" >> "$RD/transcripts/events-$1.jsonl"
}
te_read() {  # te_read <label> — a Read of the PR's p.md as Claude Code prints it ("<n><TAB><line>")
  te_tool "$1" r1 Read "$(jq -cn '{file_path: "/workspace/.claude/protocols/p.md"}')" \
    "$(awk '{printf "%s%d\t%s", (NR > 1 ? "\n" : ""), NR, $0}' "$W/.claude/protocols/p.md")"
}
te_bash() {  # te_bash <label> <id> — a harmless Bash tool use
  te_tool "$1" "$2" Bash "$(jq -cn '{command: "ls pr/head"}')" ".claude"
}
te_ps() {  # te_ps <label> — one process sample of a clean phase
  printf '# sample 1\n1 0 claude -p Run /review-sprint sprint-1\n9 1 cat pr/head/.claude/protocols/p.md\n' > "$RD/meta/ps-$1.txt"
}
te_clean() {  # te_clean [label …] — a complete transcript per label (default REVIEW)
  local l first=true
  [[ $# -gt 0 ]] || set -- REVIEW
  for l in "$@"; do
    te_hook "$l" SessionStart:startup SessionStart
    te_init "$l"
    [[ "$first" == true ]] && te_read "$l"
    first=false
    te_result "$l"
    te_ps "$l"
  done
}
te_run() { run "$TE" --run-dir "$RD" --suite-file "$S" --task-yaml "$TY" --source-repo "$SRC" "$@"; }
te_oc() { printf '%s\n' "$output" | grep -E '^arm a1_te: oracle_closed '; }
