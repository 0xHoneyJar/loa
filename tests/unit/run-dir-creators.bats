#!/usr/bin/env bats
# run-dir-creators.bats — every hook that can create .run (or a directory under it) does so under umask 077,
# and the SessionStart context-class hook repairs a legacy group/other-writable .run (cycle-138 Sprint 284
# review round 1, DISS-C-003: on an umask-002 host the first creator of .run used to make it 775, which the
# profile-lib trust predicate (FR-1) refuses — the cache was off from the first session with no automatic repair).
#
# RDC-1  static guard: every `mkdir` of .run under .claude/hooks is inside a `( umask 077; … )` subshell or in a
#        file that sets `umask 077` globally before it (the karpathy hook).
# RDC-2  dynamic: a fresh root under umask 002 — the SessionStart context-class hook, the Write/Edit audit logger
#        and the Bash mutation logger each create .run 0700; `find .run -type d -perm /022` prints nothing.
# RDC-3  repair: a pre-existing uid-owned 775 .run is tightened with `chmod go-w` (→ 755: the predicate needs no
#        group/other WRITE bit, the same repair grimoire-index.sh applies) by the context-class hook — the SessionStart
#        repair owner; its context-class file still written, stdout/stderr/rc unchanged.
# RDC-4  a symlinked .run is never chmod-ed through (the target keeps its mode) and the hook still exits 0.
# RDC-5  a uid-owned 700 .run is left alone (no chmod call; a recording chmod shim sees nothing).

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  CC="$PROJECT_ROOT/.claude/hooks/session-start/loa-context-class.sh"
  WML="$PROJECT_ROOT/.claude/hooks/audit/write-mutation-logger.sh"
  ML="$PROJECT_ROOT/.claude/hooks/audit/mutation-logger.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/rdc.XXXXXX")"
  unset LOA_CONTEXT_CLASS
}
teardown() { chmod -R u+rwx "$T" 2>/dev/null || true; find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

_mode() { stat -c '%a' -- "$1" 2>/dev/null || stat -f '%Lp' -- "$1"; }

# _run_cc <root> [umask]: the SessionStart hook on <root> under the given umask; stdout/stderr/rc captured
_run_cc() {
  local root="$1" um="${2:-002}"
  ( umask "$um"; cd "$root" && bash "$CC" --root "$root" < /dev/null > "$T/cc.out" 2> "$T/cc.err"; echo $? > "$T/cc.rc" )
}

@test "RDC-1 static guard: every mkdir of .run under .claude/hooks runs under umask 077 (subshell or file-global)" {
  local hits bad=0 f line n file_umask
  hits="$(grep -rnE '^[^#]*\bmkdir\b[^#]*\.run' "$PROJECT_ROOT/.claude/hooks" --include='*.sh' || true)"
  [ -n "$hits" ]   # the inventory is not empty: the guard has something to guard
  while IFS= read -r line; do
    f="${line%%:*}"; n="${line#*:}"; n="${n%%:*}"
    if [[ "$line" == *"umask 077"* ]]; then continue; fi
    # a file-global `umask 077` before the mkdir also satisfies the guard (karpathy-surgical-diff-check.sh)
    file_umask="$(awk -v n="$n" 'NR < n && /^umask 077/ { found = 1 } END { print found + 0 }' "$f")"
    if [[ "$file_umask" != 1 ]]; then echo "unguarded .run creator: $line" >&2; bad=1; fi
  done <<<"$hits"
  [ "$bad" -eq 0 ]
}

@test "RDC-2 fresh root under umask 002: context-class, write-mutation-logger and mutation-logger create .run 0700; no g/o-writable dir under .run" {
  local root="$T/root"; mkdir -p "$root"
  [ ! -e "$root/.run" ]
  _run_cc "$root" 002
  [ "$(cat "$T/cc.rc")" -eq 0 ]
  [ -f "$root/.run/context-class" ]
  [ "$(_mode "$root/.run")" = "700" ]
  # the Write/Edit audit logger (PostToolUse Write payload; cwd-relative .run)
  local root2="$T/root2"; mkdir -p "$root2"
  ( umask 002; cd "$root2" && printf '{"tool_name":"Write","tool_input":{"file_path":"%s/a.md","content":"x"}}\n' "$root2" | bash "$WML" > /dev/null 2>&1 ) || true
  [ -f "$root2/.run/audit.jsonl" ]
  [ "$(_mode "$root2/.run")" = "700" ]
  # the Bash mutation logger (a mutating command per its filter)
  local root3="$T/root3"; mkdir -p "$root3"
  ( umask 002; cd "$root3" && printf '{"tool_name":"Bash","tool_input":{"command":"git status"}}\n' | bash "$ML" > /dev/null 2>&1 ) || true
  [ -f "$root3/.run/audit.jsonl" ]
  [ "$(_mode "$root3/.run")" = "700" ]
  for r in "$root" "$root2" "$root3"; do
    [ -z "$(find "$r/.run" -type d -perm /022 2>/dev/null)" ]
  done
}

@test "RDC-3 repair: a uid-owned 775 .run is tightened go-w (755) by the SessionStart context-class hook; output and rc unchanged" {
  local a="$T/a" b="$T/b"
  mkdir -p "$a/.run" "$b/.run"; chmod 775 "$a/.run"; chmod 700 "$b/.run"
  _run_cc "$a" 002; cp "$T/cc.out" "$T/a.out"; cp "$T/cc.err" "$T/a.err"; cp "$T/cc.rc" "$T/a.rc"
  _run_cc "$b" 002
  [ "$(cat "$T/a.rc")" -eq 0 ]
  [ "$(_mode "$a/.run")" = "755" ]
  [ -z "$(find "$a/.run" -maxdepth 0 -perm /022)" ]
  [ -f "$a/.run/context-class" ]
  cmp -s "$T/a.out" "$T/cc.out"; cmp -s "$T/a.err" "$T/cc.err"; cmp -s "$T/a.rc" "$T/cc.rc"
}

@test "RDC-4 a symlinked .run is not chmod-ed through: the target keeps its mode and the hook still exits 0" {
  local root="$T/root" victim="$T/victim"
  mkdir -p "$root" "$victim"; chmod 775 "$victim"
  ln -s "$victim" "$root/.run"
  _run_cc "$root" 002
  [ "$(cat "$T/cc.rc")" -eq 0 ]
  [ "$(_mode "$victim")" = "775" ]
}

@test "RDC-5 a uid-owned 700 .run is left alone: a recording chmod shim sees no call" {
  local root="$T/root" bin="$T/bin"
  mkdir -p "$root/.run" "$bin"; chmod 700 "$root/.run"
  printf '#!/usr/bin/env bash\necho "chmod $*" >> "%s/chmod.log"\nexec /bin/chmod "$@"\n' "$T" > "$bin/chmod"; chmod +x "$bin/chmod"
  ( umask 002; cd "$root" && PATH="$bin:$PATH" bash "$CC" --root "$root" < /dev/null > /dev/null 2>&1; echo $? > "$T/cc.rc" )
  [ "$(cat "$T/cc.rc")" -eq 0 ]
  [ ! -s "$T/chmod.log" ]
  [ "$(_mode "$root/.run")" = "700" ]
}
