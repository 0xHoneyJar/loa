#!/usr/bin/env bats
# run-dir-creators.bats — every hook that can create .run (or a directory under it) does so under umask 077,
# and the SessionStart context-class hook repairs a legacy group/other-writable .run (cycle-138 Sprint 284
# review round 1, DISS-C-003: on an umask-002 host the first creator of .run used to make it 775, which the
# profile-lib trust predicate (FR-1) refuses — the cache was off from the first session with no automatic repair).
#
# RDC-1  static guard: every `mkdir` of .run under .claude/hooks, .claude/scripts and .claude/scripts/lib is inside a
#        `( umask 077; … mkdir … )` subshell (the mkdir itself inside it, not a `( umask 077; : ); mkdir` neighbour) or
#        in a file that sets `umask 077` globally before it (the karpathy hook) (cycle-138 bd-r8pfc, audit DISS-C-003).
# RDC-2  dynamic: a fresh root under umask 002 — the SessionStart context-class hook, the Write/Edit audit logger
#        and the Bash mutation logger each create .run 0700; `find .run -type d -perm /022` prints nothing.
# RDC-3  repair: a pre-existing uid-owned 775 .run is tightened with `chmod go-w` (→ 755: the predicate needs no
#        group/other WRITE bit, the same repair grimoire-index.sh applies) by the context-class hook — the SessionStart
#        repair owner; its context-class file still written, stdout/stderr/rc unchanged.
# RDC-4  a symlinked .run is never chmod-ed through (the target keeps its mode) and the hook still exits 0.
# RDC-5  a uid-owned 700 .run is left alone (no chmod call; a recording chmod shim sees nothing).
# RDC-6  the static guard's own teeth (Sprint 284 review round 2, DISS-C-001): on a fixture tree (RDC_HOOKS_DIR seam) a
#        creator spelled through `$(dirname "$AUDIT_LOG")` IS inventoried, a trailing `# umask 077` comment does NOT
#        satisfy the guard, a `( umask 077; : ); mkdir -p .run` neighbour subshell does NOT either, and the
#        `( umask 077; mkdir … )` subshell and a file-global `umask 077` do.

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

# RDC_INVENTORY_RE: a `mkdir` line that can create .run — a literal `.run`, or the known indirections `$AUDIT_LOG` /
# `${AUDIT_LOG%/*}` / `$RUN_DIR` (hooks, detect-platform-features, simstim-state, session-limit-capture) and
# `$LOA_CACHE_DIR` (model-health-probe: defaults to $PROJECT_ROOT/.run). A bare `CACHE_DIR` is NOT a spelling: under
# .claude/scripts it names ~/.loa/cache or .claude/cache (anthropic-oracle, cache-manager, check-updates, condense,
# constructs-browse), never .run; LOA_STATUS_RUN_DIR (loa-status.sh) is a read-only bats seam with no mkdir.
RDC_INVENTORY_RE='(^|[^[:alnum:]_])mkdir([^[:alnum:]_]).*(\.run|AUDIT_LOG|RUN_DIR|LOA_CACHE_DIR)'   # no `#` exclusion: a parameter expansion's `#` is not a comment (review r2 DISS-C-002); comments are stripped in _unguarded; POSIX classes (bash =~ on a BSD libc has no \b)
# RDC_SUBSHELL_RE: the mkdir itself sits inside the `( umask 077; … )` subshell — no `)` between the `umask 077;` and
# the mkdir word (POSIX classes, no \b: bash's =~ on a BSD libc has no \b).
RDC_SUBSHELL_RE='\([[:space:]]*umask[[:space:]]+077;([^)]*[^[:alnum:]_)])?mkdir([^[:alnum:]_]|$)'

# _rdc_strip <code>: drop a shell comment — a `#` at the start of the line or after whitespace — but never the `#` of a
# `${var#…}` / `${var##…}` expansion (review r2 DISS-C-002). _rdc_nosubst <code>: additionally drop non-nested `$(…)`
# substitutions, so an inner `)` does not end the `( umask 077; … )` subshell for RDC_SUBSHELL_RE (the inventory test runs
# on the comment-stripped line, where `$(dirname "$AUDIT_LOG")` still names its spelling).
_rdc_strip() { printf '%s' "$1" | sed -E 's/(^|[[:space:]])#.*$//'; }
_rdc_nosubst() { printf '%s' "$1" | sed -E 's/\$\([^()]*\)//g'; }

# _unguarded <dir-or-file>...: print every inventoried `mkdir` line (RDC_INVENTORY_RE) under the given directories
# (recursive, *.sh) or in the given files that is NOT inside a `( umask 077; … mkdir … )` subshell on the same line,
# nor in a file that sets `umask 077` at top level before it. Comments are stripped with _rdc_strip before matching, so
# a trailing `# umask 077` does not count and a comment-only mention is not inventoried. Exit 0 when nothing is
# unguarded, 2 on an empty inventory.
_unguarded() {
  local hits line f n code file_umask bad=0
  hits="$(grep -rnHE "$RDC_INVENTORY_RE" "$@" --include='*.sh' || true)"
  [ -n "$hits" ] || { echo "empty inventory under $*" >&2; return 2; }
  while IFS= read -r line; do
    f="${line%%:*}"; n="${line#*:}"; n="${n%%:*}"; code="$(_rdc_strip "${line#*:*:}")"
    [[ "$code" =~ $RDC_INVENTORY_RE ]] || continue          # the spelling sat in a comment
    if [[ "$(_rdc_nosubst "$code")" =~ $RDC_SUBSHELL_RE ]]; then continue; fi
    file_umask="$(awk -v n="$n" 'NR < n && /^umask 077/ { found = 1 } END { print found + 0 }' "$f")"
    if [[ "$file_umask" != 1 ]]; then echo "unguarded .run creator: $line"; bad=1; fi
  done <<<"$hits"
  return "$bad"
}

# _run_cc <root> [umask]: the SessionStart hook on <root> under the given umask; stdout/stderr/rc captured
_run_cc() {
  local root="$1" um="${2:-002}"
  ( umask "$um"; cd "$root" && bash "$CC" --root "$root" < /dev/null > "$T/cc.out" 2> "$T/cc.err"; echo $? > "$T/cc.rc" )
}

# _rdc_tree: the real inventory — .claude/hooks (recursive) plus the top-level scripts and their lib (not recursive:
# the scripts' tool subdirectories are outside the bd-r8pfc scope).
_rdc_tree() { _unguarded "$PROJECT_ROOT/.claude/hooks" "$PROJECT_ROOT"/.claude/scripts/*.sh "$PROJECT_ROOT"/.claude/scripts/lib/*.sh; }

@test "RDC-1 static guard: every mkdir of .run under .claude/hooks runs under umask 077 (subshell or file-global); the indirect creators are inventoried" {
  if [[ -n "${RDC_HOOKS_DIR:-}" ]]; then run _unguarded "$RDC_HOOKS_DIR"; else run _rdc_tree; fi
  echo "$output" >&2
  [ "$status" -eq 0 ]
  # the scripts and their lib are in the inventory too (bd-r8pfc)
  grep -nHE "$RDC_INVENTORY_RE" "$PROJECT_ROOT"/.claude/scripts/*.sh | grep -q 'grimoire-index.sh'
  grep -nHE "$RDC_INVENTORY_RE" "$PROJECT_ROOT"/.claude/scripts/lib/*.sh | grep -q 'dec-write-lib.sh'
  # the known indirect creator is in the inventory (not only the literal .run lines): settings-cleanup's audit-log dir
  grep -rnE '^[^#]*\bmkdir\b[^#]*(\.run|AUDIT_LOG|RUN_DIR)' "$PROJECT_ROOT/.claude/hooks" --include='*.sh' | grep -q 'settings-cleanup.sh'
  grep -q 'umask 077; mkdir -p -- "$(dirname "$AUDIT_LOG")"' "$PROJECT_ROOT/.claude/hooks/hygiene/settings-cleanup.sh"
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
    # find's rc is checked: an unsupported `-perm /mode` must fail the test, never pass it vacuously (DISS-C-001)
    run find "$r/.run" -type d -perm /022
    [ "$status" -eq 0 ]; [ -z "$output" ]
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


@test "RDC-6 the static guard has teeth: an indirect creator is inventoried, a comment-only umask does not satisfy it, a subshell or a file-global umask does" {
  local fx="$T/hooks"; mkdir -p "$fx/a" "$fx/b" "$fx/c" "$fx/d" "$fx/e"
  printf '#!/usr/bin/env bash\nAUDIT_LOG=.run/x.jsonl\n[[ -d "${AUDIT_LOG%%/*}" ]] || mkdir -p "$(dirname "$AUDIT_LOG")"\n' > "$fx/a/indirect.sh"
  printf '#!/usr/bin/env bash\nmkdir -p .run  # umask 077 is mentioned only in this comment\n' > "$fx/b/comment.sh"
  printf '#!/usr/bin/env bash\n[[ -d .run ]] || ( umask 077; mkdir -p -- .run ) 2>/dev/null\n' > "$fx/c/subshell.sh"
  printf '#!/usr/bin/env bash\numask 077\nmkdir -p .run/state\n' > "$fx/d/global.sh"
  printf '#!/usr/bin/env bash\n( umask 077; : ); mkdir -p .run\n' > "$fx/e/neighbour.sh"
  mkdir -p "$fx/f" "$fx/g"
  printf '#!/usr/bin/env bash\nROOT=./x\nmkdir -p -- "${ROOT#./}/.run"\n' > "$fx/f/expansion.sh"                       # the `#` of a parameter expansion is not a comment (review r2 DISS-C-002)
  printf '#!/usr/bin/env bash\nX=.run/a/b\n( umask 077; d=$(dirname "$X"); mkdir -p -- "$d/.run" )\n' > "$fx/g/inner.sh"   # an inner $(…) does not end the guarded subshell
  run _unguarded "$fx"
  [ "$status" -eq 1 ]
  [[ "$output" == *"a/indirect.sh:3:"* ]]
  [[ "$output" == *"b/comment.sh:2:"* ]]
  [[ "$output" != *"c/subshell.sh"* ]]
  [[ "$output" != *"d/global.sh"* ]]
  [[ "$output" == *"e/neighbour.sh:2:"* ]]   # the umask subshell ends before the mkdir: flagged (bd-r8pfc)
  [[ "$output" == *"f/expansion.sh:3:"* ]]   # inventoried although a `#` precedes the .run spelling (review r2 DISS-C-002)
  [[ "$output" != *"g/inner.sh"* ]]          # guarded although an inner `)` sits between `umask 077;` and the mkdir
  # the real tree is clean
  run _rdc_tree
  [ "$status" -eq 0 ]
}
