#!/usr/bin/env bash
# =============================================================================
# PreToolUse:Bash Safety Hook — Block Destructive Commands (v1.38.0)
# =============================================================================
# Blocks dangerous patterns and suggests safer alternatives.
# Exit 0 = allow, Exit 2 = block (stderr message fed back to agent).
#
# Cycle-111 (sprint-164, 2026-05-16) — ports Anthropic DCG public pattern
# set inline. Source: github.com/anthropics/destructive-command-guard
# Pattern port reference SHA: HEAD as of 2026-05-16 (no specific commit
# pin available — DCG ships rule packs, not single-file source).
# REVIEW-BY: 2026-08-16 — re-sync against upstream DCG every quarter.
#
# IMPORTANT: No set -euo pipefail — this hook must never fail closed.
# A grep or jq failure must result in exit 0 (allow), not an error.
#
# WHY fail-open (not fail-closed): A safety hook that crashes or encounters
# a parse error must NOT block the agent from operating. The alternative —
# fail-closed — would make jq/grep bugs into denial-of-service attacks
# against the agent. Fail-open with logging is the standard pattern for
# inline security hooks (cf. ModSecurity DetectionOnly mode).
# (Source: bridge-20260213-c011he iter-1 HIGH-1 fix)
#
# WHY GNU/BSD ERE (NOT strict POSIX): grep -P (PCRE) is a GNU extension not
# available on macOS/BSD or minimal containers. grep -E (Extended Regex)
# with `\s`, `\S`, `\b` extensions works on both GNU grep (Linux) and BSD
# grep (macOS Sonoma+). Strict-POSIX ERE (busybox without -E extensions)
# is NOT in scope per cycle-111 SDD §5.0 honest-scope decision.
# (Source: bridge-20260213-c011he iter-1 HIGH-1 fix; cycle-111 SDD §5.0)
#
# WHY single script for all patterns: NFR-5 single-file invariant. Multiple
# hooks would each read stdin, parse JSON, and run regex — multiplying
# latency per command. A single emit_block helper with sequential patterns
# is simpler and faster. (cycle-111 SDD §5/§6.)
#
# Defense-in-depth posture (cycle-111 SDD §11): this hook is a fence
# against routine destructive-command mistakes by autonomous agents, NOT
# a hardened security boundary against intentional bypass. Known accepted
# bypass classes: newline statement separators, subshell wrapping
# (`bash -c '...'`, `$(...)`), eval/base64 decode, SQL comments containing
# WHERE, jq absent from PATH. See SDD §11 for full table.
# Current executable limit examples and issue dispositions:
# docs/runbooks/hook-safety.md (#1047, #1245, #1088, #1031).
#
# cycle-125 FR-1 (2026-09-23) — precision pass against the fleet corpus
# (tests/fixtures/fence-corpus/, replayed by tests/unit/block-destructive-
# bash.bats). Relaxations, each on a positively established predicate:
# FR-2 cache/build vocabulary by last segment, bare names after a
# statement-initial `cd <temp>`, paths strictly below /tmp|/var/tmp|
# /private/tmp, `$TMPDIR/<name>` only with a real temp TMPDIR, a variable
# bound exactly once to `$(mktemp -d)`; FR-1.1 branches that are ancestors
# of main/master (offline `git merge-base`); FR-1.3 generated paths;
# FR-1.4/5/6 only when a SQL runner (psql, mysql, sqlite3, prisma, …) or an
# inline interpreter program (`python -c`, `node -e`) is in the command.
# ACCEPTED RESIDUALS (deliberately not relaxed):
#   * Remote payloads: `ssh host 'rm -rf /'`, `docker exec c rm -rf /data`,
#     `kubectl exec p -- rm -rf /` keep blocking. A scrub of quoted remote
#     payloads was withdrawn at design time (Flatline SKP-001) — the text
#     fence cannot tell a remote target from a local one, and the blast
#     radius of a remote wipe is larger, not smaller.
#   * SQL through a script FILE (`python app.py` that drops a table) was
#     never matched and still is not; inline programs are matched by text.
#   * `cd "$(mktemp -d)" && rm -rf out` (substitution as the cd target) and
#     `rm -rf "$T"` where T came from anything but a plain `$(mktemp -d)`
#     or a temp path stay blocked — bind the path first, then rm.
#   * The hook never consults its own $PWD: a project checked out under
#     /tmp still has `rm -rf src` blocked.
#   * Rebinding builtins void the once-bound-variable proof only in command
#     position (`read T`, `while read T`, `IFS= read -r T`, `command read`,
#     `eval "read T"`); `exec read`, `env … read`, `sudo read`, `nice read`
#     are NOT counted — `read` is a builtin, so those forms fail or run in a
#     child and cannot rebind the caller's variable. `notes-guard.sh read`
#     and `echo read` are arguments, never rebinds.
#
# Registered in settings.hooks.json as PreToolUse matcher: "Bash"
# Part of Loa Harness Engineering (cycle-011, issue #297)
# Source: Trail of Bits claude-code-config safety patterns
# =============================================================================
# perf pass-2 (2026-07-05, skill-loop): fork/exec reduction. The boolean
# `echo | grep -qE` pattern dispatches (15 spawns on every benign Bash call)
# are replaced by bash [[ =~ ]] via the _match/_match_ci helpers below, which
# preserve grep's PER-LINE match model byte-for-byte (see helper comments).
# `\b` was translated to explicit POSIX boundary classes because bash =~
# compiles with the SYSTEM regex library — glibc supports \b, BSD libc does
# NOT, and this hook commits to macOS/BSD (header above). Each translated
# pattern carries an equivalence note. Deliberately NOT converted (grep
# retained): P10 DELETE-FROM segment extraction (grep -oiE multi-match with
# original-case output is not provably reproducible in bash — no match-offset
# primitive), the FR-SZ inner write-intent tests (their `X\b[^|;&]*` shapes
# make consuming \b-translation non-isomorphic; they only run when the
# command already mentions a protected path), and all `grep -oE | head -1`
# matched-substring extractions (block path only — the hook exits 2 right
# after). Also: stdin now streams straight into the Path-A jq (no cat spawn),
# audit timestamps use printf %(...)T (no date spawn), cwd uses $PWD.
# =============================================================================
# perf pass-8 (2026-07-05, skill-loop): provably-complete literal pre-filters
# on the pattern dispatch. After pass 2 the ~95% benign path still paid 13
# sequential ERE evaluations (~0.4 ms) plus the one unconditional P10 grep
# spawn (~3 ms). Each pattern group is now guarded by a cheap bash substring
# test on literal(s) PROVABLY NECESSARY for the group to match: each guard
# literal appears in the group's regex as a mandatory concatenation element —
# outside every alternation branch, optional (?) group and starred group — so
# any MATCHING LINE must contain it verbatim, hence the whole $command must
# contain it. Absence from the whole string therefore proves no line can
# match, and the group is skipped — outcome-identical by construction.
# Where a guard uses an alternation's literals (P6 drop|clear, FR-SZ
# .run/|grimoires/loa/skills), the guard tests ALL branch literals and any
# hit evaluates the group. Guards only ever SKIP, never accept: when the
# literal is present the group evaluates exactly as before, in the original
# order (first match still wins, block messages byte-identical).
# Case-insensitive groups (P8/P9/P10) guard on the same C-locale ASCII fold
# (${command,,}) that _match_ci applies per line and grep -i applies under
# the LC_ALL=C pin — folding is per-character and leaves \n untouched, so
# the folded whole string is exactly the folded lines joined by \n, and a
# literal absent from the folded whole is absent from every folded line.
# Per-group necessity proofs sit next to each guard. The P10 DELETE-FROM
# grep — the last unconditional spawn on the benign path — now runs only
# when the folded command contains both "delete" and "from" (both mandatory
# in its -i pattern). The log-redactor stays block-path-only (verified: it
# is exec'd only inside emit_block and the FR-SZ bypass audit branch).
# =============================================================================

# =============================================================================
# FR-6 heredoc consumer classifier (cycle-129 D-6.1; knob
# destructive_command_guard.heredoc_classifier, default true; false = the
# pre-cycle scan, i.e. only the #1245 quoted-cat scrub below).
# Defined BEFORE the bash-version guard and the stdin read so another script
# can source this file with BDB_LIB_ONLY=1 and call
#   _bdb_heredoc_consumer_class <command text>   → prints interpreter|nonexec|none
#   heredoc_nonexec <command text>               → exit 0 iff nonexec
# Bash 3.2 compatible (no ${x,,}, no mapfile, no associative arrays) and safe
# under a caller's `set -u`.
#
# Grammar (literal command text; no alias or function expansion; CRLF folded
# to LF). The command is walked line by line; a line holding an unquoted
# `<<` / `<<-` (not `<<<`) is a heredoc header, the body runs to the first
# line equal to the delimiter (leading tabs stripped for `<<-`). FULL SCAN
# (the whole command as today) on: any other control character, a header the
# tokenizer cannot read (open quote, trailing backslash, comment), more than
# one heredoc on a header, a delimiter that is not a plain word ('W', "W",
# \W or W with W in [A-Za-z0-9_.+:@%-]; `$X` is a variable delimiter), or a
# missing terminator. Per heredoc the class is:
#   interpreter — body scanned exactly as today: the header holds `$(`, a
#     backtick, `<(` or `>(`, a paren or brace group or a shell keyword; it
#     continues on the next line (`|`, `&&`, `||` last) or an earlier line
#     opened a substitution, group, quote or pipe; a member of the heredoc's
#     pipeline is a shell, interpreter, wrapper that runs its argument or SQL
#     runner (_bdb_hd_is_interp, _bdb_hd_is_runner); an allowlisted form
#     carries an unknown or exec-shaped flag (-c, -e, -x clusters, --exec,
#     --eval, --command, in-place); a write target is executable content
#     (_bdb_hd_exec_dest: script extension, .claude/hooks, .claude/settings*
#     .json, .git/hooks, .git/config, rc/profile files, /etc, a bin dir or a
#     directory on PATH, or any non-literal path); the first body line is a
#     shebang; the body holds `<<` (nested); a target's basename appears
#     elsewhere in the command outside the safe readers (_bdb_hd_same_line_exec:
#     `bash x`, `./x`, `source x`, `. x`, `chmod +x x`, `exec x`, cp/mv …).
#   nonexec — every pipeline member is an exact allowlisted form
#     (_bdb_hd_member): cat, tee, printf, echo with plain-file or stdout sinks;
#     gh pr|issue comment -F -; gh pr create --body-file -; git commit -F -;
#     br create|update reading `-`; jq/yq without in-place; grep; sed -n with
#     a print-only script; sort; wc. The body is then scanned PER SEGMENT
#     (_bdb_hd_scan_body): each line split on ; && || | &, wrapper prefixes
#     stripped (sudo command exec env nice time nohup builtin stdbuf ionice,
#     a leading backslash, quote, paren or brace, assignments, an absolute
#     path); a segment whose command word is a fence verb (rm git find dd
#     mkfs* shred truncate kubectl terraform aws gcloud psql mysql DROP
#     DELETE TRUNCATE) is kept on its own line for the normal rules, other
#     segments are dropped. The body falls back to a full scan when it holds
#     `$(`, a backtick, `<(` or `>(` under an unquoted delimiter, or a segment
#     word is an interpreter or wrapper, or a variable (`$x -rf /`; such a
#     segment is ALSO scanned as rm, git and kubectl with the same arguments).
#     Special case (the #1245 scrub): a standalone quoted-delimiter `cat`
#     whose header is exactly `cat <<'W' [> path]` drops the whole body.
#   none — the consumer is on neither list: full scan.
# Documented gap: a body written to a plain file by one command and executed
# by a LATER command is outside a per-command fence (the Write tool shares it).
# =============================================================================
_bdb_hd_op_re='^[0-9]*(<<<|<<-|&>>|<<|>>|>[|]|&&|[|][|]|[|]&|&>|<>|>&[0-9-]*|<&[0-9-]*|;;|;|&|[|]|<|>|[(]|[)])$'
_bdb_hd_re_dw='^[A-Za-z0-9_.+:@%-]+$'
_bdb_hd_re_dsq="^'([A-Za-z0-9_.+:@%-]+)'\$"
_bdb_hd_re_ddq='^"([A-Za-z0-9_.+:@%-]+)"$'
_bdb_hd_re_dbs='^\\([A-Za-z0-9_.+:@%-]+)$'
_bdb_hd_re_psq="^'([^']*)'\$"
_bdb_hd_re_pdq="^\"([^\"\$\`\\\\]*)\"\$"
_bdb_hd_re_pbare="^[^'\"\$\`\\\\]+\$"
_bdb_hd_re_ctl=$'[\x01-\x08\x0b-\x1f\x7f]'
_bdb_hd_re_exflag='^-[A-Za-z]*[cex][A-Za-z]*$'
_bdb_hd_re_exlong='^--(exec|eval|command|in-?place)'
_bdb_hd_re_ext='\.(sh|bash|zsh|ksh|csh|fish|py|pyw|rb|pl|pm|js|mjs|cjs|ts|mts|cts|ps1|psm1|php|lua|tcl|command|bat|cmd)$'
_bdb_hd_re_sys='(^|/)(\.claude/hooks(/|$)|\.claude/settings[^/]*\.json$|\.git/hooks(/|$)|\.git/config$|\.gitconfig$|\.ssh/rc$|\.config/(fish|zsh|bash|git)/|s?bin/[^/]+$|\.github/workflows(/|$)|(GNUm|m|M)akefile$|[Jj]ustfile$|package\.json$|pyproject\.toml$|Cargo\.toml$|Rakefile$|Gemfile$|Dockerfile([.][^/]*)?$|\.pre-commit-config\.ya?ml$|\.gitlab-ci\.ya?ml$)'
_bdb_hd_re_rc='(^|/)\.(bashrc|bash_profile|bash_login|bash_logout|profile|zshrc|zshenv|zprofile|zlogin|zlogout|kshrc|mkshrc|cshrc|tcshrc|login|logout|envrc)$'
_bdb_hd_re_sedp='^(([0-9]+|[$]|/[^/]*/)(,([0-9]+|[$]|/[^/]*/))?)?p$'
_bdb_hd_re_assign='^[A-Za-z_][A-Za-z0-9_]*='
_bdb_hd_re_varw='^[$]([{]|[A-Za-z_])'
_bdb_hd_re_knob='^[[:space:]]+heredoc_classifier:[[:space:]]*["'"'"']?([A-Za-z]+)["'"'"']?[[:space:]]*(#.*)?$'

# Shells, interpreters and wrappers that run their argument or stdin.
_bdb_hd_is_interp() {
  case "$1" in
    bash|sh|zsh|dash|ksh|mksh|ash|fish|csh|tcsh|busybox|python|python[0-9]*|pypy*|node|nodejs|deno|bun|ruby|irb|perl|php|lua|luajit|tclsh|wish|expect|pwsh|powershell|osascript|Rscript) return 0 ;;
    eval|source|.|exec|command|builtin|time|awk|gawk|mawk|nawk|make|gmake|m4|ed|ex|vi|vim|nvim|gdb) return 0 ;;
    sudo|doas|su|runuser|env|xargs|parallel|timeout|nohup|nice|ionice|setsid|stdbuf|chroot|unshare|nsenter|ssh|docker|podman|kubectl|find|watch|script) return 0 ;;
  esac
  return 1
}
# The SQL runners of the FR-1.4/5/6 precondition (same list).
_bdb_hd_is_runner() {
  case "$1" in
    psql|pgcli|mysql|mariadb|mysqlsh|sqlite3|sqlcmd|sqlplus|isql|usql|litecli|duckdb|clickhouse|clickhouse-client|cockroach|bq|wrangler|prisma|supabase|drizzle-kit|knex|sequelize|typeorm|flyway|liquibase|dbmate|goose|sqitch|rails|manage.py|artisan|alembic|dbt|atlas|mongosh|sqlx) return 0 ;;
  esac
  return 1
}
# Command words the fence's own rules match.
_bdb_hd_is_destructive() {
  case "$1" in
    rm|git|find|dd|shred|truncate|kubectl|terraform|aws|gcloud|psql|mysql|mkfs|mkfs.*) return 0 ;;
    [Dd][Rr][Oo][Pp]|[Dd][Ee][Ll][Ee][Tt][Ee]|[Tt][Rr][Uu][Nn][Cc][Aa][Tt][Ee]) return 0 ;;
  esac
  return 1
}
# Readers that may name a heredoc's target elsewhere on the line.
_bdb_hd_is_safe_reader() {
  case "$1" in
    cat|ls|wc|head|tail|grep|egrep|fgrep|rg|diff|cmp|stat|file|test|'['|echo|printf|sort|uniq|jq|yq|git|gh|br|mkdir|touch|realpath|readlink|basename|dirname|du|md5sum|sha1sum|sha256sum|shasum|b2sum|cksum) return 0 ;;
  esac
  return 1
}

# _bdb_hd_tokenize <line> → _bdb_hd_tok[] (words keep their quotes; operators
# are separate tokens, an fd number joins its redirect). Returns 1 when the
# line cannot be read: open quote, trailing backslash, unquoted comment.
_bdb_hd_tokenize() {
  local s="${1:-}" n i=0 ch tok="" q="" have=0 op cand
  n=${#s}
  _bdb_hd_tok=()
  while (( i < n )); do
    ch="${s:i:1}"
    if [[ -n "$q" ]]; then
      tok="$tok$ch"
      if [[ "$q" == "'" ]]; then
        [[ "$ch" == "'" ]] && q=""
      elif [[ "$ch" == '\' ]]; then
        (( i + 1 < n )) || return 1
        i=$((i + 1)); tok="$tok${s:i:1}"
      elif [[ "$ch" == '"' ]]; then
        q=""
      fi
      i=$((i + 1)); continue
    fi
    case "$ch" in
      "'"|'"') q="$ch"; tok="$tok$ch"; have=1; i=$((i + 1)) ;;
      '\')
        (( i + 1 < n )) || return 1
        tok="$tok$ch${s:i+1:1}"; have=1; i=$((i + 2)) ;;
      ' '|$'\t')
        if (( have )); then _bdb_hd_tok[${#_bdb_hd_tok[@]}]="$tok"; tok=""; have=0; fi
        i=$((i + 1)) ;;
      '#')
        (( have )) || return 1
        tok="$tok$ch"; i=$((i + 1)) ;;
      ';'|'&'|'|'|'<'|'>'|'('|')')
        op=""
        for cand in '<<<' '<<-' '&>>' '<<' '>>' '>|' '&&' '||' '|&' '&>' '<>' '>&' '<&' ';;' ';' '&' '|' '<' '>' '(' ')'; do
          if [[ "${s:i:${#cand}}" == "$cand" ]]; then op="$cand"; break; fi
        done
        i=$((i + ${#op}))
        if [[ "$op" == '>&' || "$op" == '<&' ]]; then
          while (( i < n )) && [[ "${s:i:1}" == [0-9-] ]]; do op="$op${s:i:1}"; i=$((i + 1)); done
        fi
        if (( have )); then
          if [[ "$tok" =~ ^[0-9]+$ ]] && [[ "$op" == '<'* || "$op" == '>'* ]]; then
            op="$tok$op"
          else
            _bdb_hd_tok[${#_bdb_hd_tok[@]}]="$tok"
          fi
          tok=""; have=0
        fi
        _bdb_hd_tok[${#_bdb_hd_tok[@]}]="$op" ;;
      *) tok="$tok$ch"; have=1; i=$((i + 1)) ;;
    esac
  done
  [[ -z "$q" ]] || return 1
  (( have )) && _bdb_hd_tok[${#_bdb_hd_tok[@]}]="$tok"
  return 0
}

# _bdb_hd_unq_path <word> → _hd_up; returns 1 for a non-literal path (an
# expansion, an escape, mixed quoting) or an empty one.
_bdb_hd_unq_path() {
  _hd_up=""
  if [[ "${1:-}" =~ $_bdb_hd_re_psq ]] || [[ "${1:-}" =~ $_bdb_hd_re_pdq ]]; then
    _hd_up="${BASH_REMATCH[1]}"
  elif [[ "${1:-}" =~ $_bdb_hd_re_pbare ]]; then
    _hd_up="$1"
  else
    return 1
  fi
  [[ -n "$_hd_up" ]]
}

# _bdb_hd_exec_dest <unquoted path> → 0 when a write there is executable
# content (or cannot be judged).
_bdb_hd_exec_dest() {
  local p="${1:-}" d e b old_ifs
  case "$p" in
    *'*'*|*'?'*|*'['*|*'{'*|'~'|'~'[!/]*|'') return 0 ;;
  esac
  [[ "$p" == '~/'* ]] && p="${HOME:-}/${p#'~/'}"
  b="${p##*/}"
  [[ "$b" =~ $_bdb_hd_re_ext ]] && return 0
  [[ "$p" =~ $_bdb_hd_re_sys || "$p" =~ $_bdb_hd_re_rc ]] && return 0
  [[ "$p" == /etc/* ]] && return 0
  if [[ "$p" == /* ]]; then d="${p%/*}"; [[ -n "$d" ]] || d="/"
  elif [[ "$p" == */* ]]; then d="${PWD:-.}/${p%/*}"
  else d="${PWD:-.}"
  fi
  old_ifs="$IFS"; IFS=':'
  for e in ${PATH:-}; do
    [[ -z "$e" || "$e" == "." ]] && e="${PWD:-.}"
    [[ "$e" != "/" ]] && e="${e%/}"
    if [[ "$d" == "$e" ]]; then IFS="$old_ifs"; return 0; fi
  done
  IFS="$old_ifs"
  return 1
}

# _bdb_hd_member <tokens…> → _hd_mcls (interpreter|nonexec|none) for one
# pipeline member; write targets are appended to _hd_dests.
_bdb_hd_member() {
  local -a toks argv
  local t nxt i n stdout_files=0 a0 base fd stdin=0 ops=0 want="" has_n=0 script=""
  toks=("$@"); n=${#toks[@]}; argv=()
  _hd_mcls=none
  for ((i = 0; i < n; i++)); do
    t="${toks[i]}"
    if [[ "$t" =~ $_bdb_hd_op_re ]]; then
      case "$t" in
        *'<<<') return ;;
        *'<<'|*'<<-') i=$((i + 1)); continue ;;
        *'>&'[0-9]*|*'>&-'|*'<&'*) continue ;;
        *'>'|*'>>'|*'>|'|*'>&'|'&>'|'&>>')
          nxt="${toks[i+1]:-}"; i=$((i + 1))
          if [[ -z "$nxt" || "$nxt" =~ $_bdb_hd_op_re ]]; then _hd_mcls=interpreter; return; fi
          _bdb_hd_unq_path "$nxt" || { _hd_mcls=interpreter; return; }
          case "$_hd_up" in /dev/null|/dev/stdout|/dev/stderr) continue ;; esac
          _hd_dests[${#_hd_dests[@]}]="$_hd_up"
          fd="${t%%[>&]*}"
          [[ -z "$fd" || "$fd" == 1 || "$t" == '&>'* || "$t" == '>&' ]] && stdout_files=$((stdout_files + 1))
          continue ;;
        *) return ;;
      esac
    fi
    argv[${#argv[@]}]="$t"
  done
  (( ${#argv[@]} > 0 )) || return
  a0="${argv[0]}"
  base="${a0#\\}"; base="${base##*/}"
  if _bdb_hd_is_interp "$base" || _bdb_hd_is_runner "$base"; then _hd_mcls=interpreter; return; fi
  [[ "$a0" =~ ^[a-z][a-z0-9]*$ ]] || return
  (( stdout_files <= 1 )) || return
  for ((i = 1; i < ${#argv[@]}; i++)); do
    t="${argv[i]}"
    if [[ "$t" =~ $_bdb_hd_re_exflag || "$t" =~ $_bdb_hd_re_exlong ]]; then _hd_mcls=interpreter; return; fi
  done
  case "$a0" in
    cat)
      for ((i = 1; i < ${#argv[@]}; i++)); do [[ "${argv[i]}" == "-" ]] || { _hd_mcls=interpreter; return; }; done ;;
    tee)
      for ((i = 1; i < ${#argv[@]}; i++)); do
        t="${argv[i]}"
        case "$t" in
          -a|--append|-p) ;;
          -*) _hd_mcls=interpreter; return ;;
          *) _bdb_hd_unq_path "$t" || { _hd_mcls=interpreter; return; }
             _hd_dests[${#_hd_dests[@]}]="$_hd_up" ;;
        esac
      done ;;
    echo|printf)
      for ((i = 1; i < ${#argv[@]}; i++)); do
        case "${argv[i]}" in -n|-E) ;; -*) _hd_mcls=interpreter; return ;; esac
      done ;;
    gh)
      case "${argv[1]:-} ${argv[2]:-}" in
        "pr comment"|"issue comment") want=" -F --body-file -R --repo |" ;;
        "pr create") want=" -F --body-file --title -t --base -B --head -H --repo -R --label -l --reviewer -r --assignee -a --milestone -m --project -p --template -T | --draft -d --fill --fill-first --fill-verbose --no-maintainer-edit --dry-run " ;;
        *) return ;;
      esac
      for ((i = 3; i < ${#argv[@]}; i++)); do
        t="${argv[i]}"
        case "$t" in
          --body-file=-) stdin=1 ;;
          --*=*) [[ "${want%%|*}" == *" ${t%%=*} "* ]] || { _hd_mcls=interpreter; return; } ;;
          -*)
            if [[ "${want%%|*}" == *" $t "* ]]; then
              i=$((i + 1))
              [[ ( "$t" == "-F" || "$t" == "--body-file" ) && "${argv[i]:-}" == "-" ]] && stdin=1
            elif [[ "${want#*|}" != *" $t "* ]]; then
              _hd_mcls=interpreter; return
            fi ;;
          *) ops=$((ops + 1)); [[ "${argv[2]}" == comment && $ops -le 1 ]] || { _hd_mcls=interpreter; return; } ;;
        esac
      done
      (( stdin )) || { _hd_mcls=interpreter; return; } ;;
    git)
      [[ "${argv[1]:-}" == commit ]] || return
      for ((i = 2; i < ${#argv[@]}; i++)); do
        t="${argv[i]}"
        case "$t" in
          -F|--file) i=$((i + 1)); [[ "${argv[i]:-}" == "-" ]] || { _hd_mcls=interpreter; return; }; stdin=1 ;;
          --file=-|-F-) stdin=1 ;;
          -q|--quiet|-s|--signoff|-a|--all|--allow-empty|--allow-empty-message|-v|--verbose|--no-edit|--amend) ;;
          *) _hd_mcls=interpreter; return ;;
        esac
      done
      (( stdin )) || { _hd_mcls=interpreter; return; } ;;
    br)
      case "${argv[1]:-}" in create|update) ;; *) return ;; esac
      for ((i = 2; i < ${#argv[@]}; i++)); do
        t="${argv[i]}"
        case "$t" in
          -d|--description|--body) [[ "${argv[i+1]:-}" == "-" ]] && stdin=1 ;;
          -f|--file) [[ "${argv[1]}" == create && "${argv[i+1]:-}" == "-" ]] && stdin=1 ;;
          --description=-|--body=-) stdin=1 ;;
        esac
      done
      (( stdin )) || { _hd_mcls=interpreter; return; } ;;
    jq|yq)
      for ((i = 1; i < ${#argv[@]}; i++)); do
        # In-place flags: --inplace/--in-place, -i, -i=…, and any short-flag cluster holding an i
        # (corpus D114/D115: `-i` alone did not match `-[A-Za-z]*i*`, which needs a letter before the i).
        case "${argv[i]}" in --inplace|--in-place|-i*|-[A-Za-z]*i*) _hd_mcls=interpreter; return ;; esac
      done ;;
    grep|egrep|fgrep) ;;
    sed)
      for ((i = 1; i < ${#argv[@]}; i++)); do
        t="${argv[i]}"
        case "$t" in
          -n|--quiet|--silent) has_n=1 ;;
          -E|-r|--regexp-extended|-s|--separate|-u|--unbuffered|-z|--null-data) ;;
          -*) _hd_mcls=interpreter; return ;;
          *) if [[ -z "$script" ]]; then
               script="$t"; [[ "$script" =~ $_bdb_hd_re_psq || "$script" =~ $_bdb_hd_re_pdq ]] && script="${BASH_REMATCH[1]}"
               [[ "$script" =~ $_bdb_hd_re_sedp ]] || { _hd_mcls=interpreter; return; }
             fi ;;
        esac
      done
      (( has_n )) && [[ -n "$script" ]] || { _hd_mcls=interpreter; return; } ;;
    sort)
      for ((i = 1; i < ${#argv[@]}; i++)); do
        t="${argv[i]}"
        case "$t" in
          -o) i=$((i + 1)); _bdb_hd_unq_path "${argv[i]:-}" || { _hd_mcls=interpreter; return; }; _hd_dests[${#_hd_dests[@]}]="$_hd_up" ;;
          -k|-t) i=$((i + 1)) ;;
          -k*|-t*) ;;
          --*) _hd_mcls=interpreter; return ;;
          -*) [[ "$t" =~ ^-[bdfghiMnRrsuVz]+$ ]] || { _hd_mcls=interpreter; return; } ;;
        esac
      done ;;
    wc)
      for ((i = 1; i < ${#argv[@]}; i++)); do
        case "${argv[i]}" in -*) [[ "${argv[i]}" =~ ^-[lwmL]+$ ]] || { _hd_mcls=interpreter; return; } ;; esac
      done ;;
    *) return ;;
  esac
  _hd_mcls=nonexec
}

# _bdb_hd_ctx_bad <line> → 0 when a line before (or the header itself) leaves
# the next text inside a substitution, group, quote, compound command or
# pipeline: a later heredoc there is interpreter-class.
_bdb_hd_ctx_bad() {
  local l="${1:-}" k last
  case "$l" in *'$('*|*'`'*|*'<('*|*'>('*) return 0 ;; esac
  _bdb_hd_tokenize "$l" || return 0
  for ((k = 0; k < ${#_bdb_hd_tok[@]}; k++)); do
    case "${_bdb_hd_tok[k]}" in
      '('|')'|'{'|'}'|do|done|then|else|elif|if|fi|while|until|for|case|esac|select|function|coproc) return 0 ;;
    esac
  done
  (( ${#_bdb_hd_tok[@]} > 0 )) || return 1
  last="${_bdb_hd_tok[${#_bdb_hd_tok[@]}-1]}"
  case "$last" in '|'|'|&'|'&&'|'||') return 0 ;; esac
  return 1
}

# _bdb_hd_header <line> — parse one header line. Sets _hd_ops (heredoc count,
# -1 = unreadable), _hd_delim, _hd_quoted, _hd_tabs, _hd_cls, _hd_dests[],
# _hd_pipe (pipeline id of the heredoc on this line).
_bdb_hd_header() {
  local line="${1:-}" k nt t opi=-1 w seg=0 pipe=0
  local -a tpipe mtoks
  _hd_ops=0 _hd_delim="" _hd_quoted=0 _hd_tabs=0 _hd_cls=none _hd_pipe=-1
  _hd_dests=()
  if ! _bdb_hd_tokenize "$line"; then _hd_ops=-1; return; fi
  nt=${#_bdb_hd_tok[@]}
  tpipe=()
  for ((k = 0; k < nt; k++)); do
    t="${_bdb_hd_tok[k]}"
    case "$t" in
      ';'|';;'|'&'|'&&'|'||'|'('|')') pipe=$((pipe + 1)); tpipe[k]=-1; continue ;;
      '|'|'|&') tpipe[k]=-1; continue ;;
    esac
    tpipe[k]=$pipe
    if [[ "$t" =~ ^[0-9]*'<<'-?$ ]]; then _hd_ops=$((_hd_ops + 1)); opi=$k; fi
  done
  (( _hd_ops == 1 )) || return
  w="${_bdb_hd_tok[opi+1]:-}"
  [[ "${_bdb_hd_tok[opi]}" == *'<<-' ]] && _hd_tabs=1
  if [[ "$w" =~ $_bdb_hd_re_dsq || "$w" =~ $_bdb_hd_re_ddq || "$w" =~ $_bdb_hd_re_dbs ]]; then
    _hd_delim="${BASH_REMATCH[1]}"; _hd_quoted=1
  elif [[ "$w" =~ $_bdb_hd_re_dw ]]; then
    _hd_delim="$w"
  else
    _hd_ops=-1; return        # variable-expanded, mixed or missing delimiter
  fi
  _hd_pipe="${tpipe[opi]}"
  if _bdb_hd_ctx_bad "$line"; then _hd_cls=interpreter; return; fi
  _bdb_hd_tokenize "$line"    # _bdb_hd_ctx_bad reused the token buffer
  # Classify every member of the heredoc's pipeline; the most executing wins.
  local cls=nonexec
  k=0
  while (( k < nt )); do
    if [[ "${tpipe[k]}" != "$_hd_pipe" ]]; then k=$((k + 1)); continue; fi
    mtoks=()
    while (( k < nt )) && [[ "${tpipe[k]}" == "$_hd_pipe" ]]; do mtoks[${#mtoks[@]}]="${_bdb_hd_tok[k]}"; k=$((k + 1)); done
    _bdb_hd_member "${mtoks[@]}"
    case "$_hd_mcls" in
      interpreter) cls=interpreter ;;
      none) [[ "$cls" == interpreter ]] || cls=none ;;
    esac
    k=$((k + 1))
  done
  _hd_cls="$cls"
}

# _bdb_hd_segword <segment> → _hd_w (command word after wrapper stripping,
# quotes and an absolute path removed) and _hd_rest (the text after it).
_bdb_hd_segword() {
  local s="${1:-}" w guard=0
  _hd_w="" _hd_rest=""
  while (( guard < 64 )); do
    guard=$((guard + 1))
    s="${s#"${s%%[![:space:]]*}"}"
    [[ -n "$s" ]] || return
    case "${s:0:1}" in
      '('|'{'|'!'|'\'|'"'|"'") s="${s:1}"; continue ;;
    esac
    w="${s%%[[:space:]]*}"
    s="${s:${#w}}"
    if [[ "$w" =~ $_bdb_hd_re_assign ]]; then continue; fi
    # Shell reserved words are transparent prefixes: `if :; then rm …; fi` keeps its rm
    # segment (audit r256-5, dissent DISS-C-002).
    case "$w" in
      if|then|elif|else|do|done|while|until|fi|esac|coproc|function) continue ;;
    esac
    case "$w" in
      sudo|doas|command|exec|env|nice|time|nohup|builtin|stdbuf|ionice)
        while :; do
          s="${s#"${s%%[![:space:]]*}"}"
          case "$s" in
            -S|-S[[:space:]]*|--split-string*) _hd_w="sh"; _hd_rest="$s"; return ;;
            -[ugnCphUrtTDc]|-[ugnCphUrtTDc][[:space:]]*)
              s="${s:2}"; s="${s#"${s%%[![:space:]]*}"}"; w="${s%%[[:space:]]*}"; s="${s:${#w}}" ;;
            -*) w="${s%%[[:space:]]*}"; s="${s:${#w}}" ;;
            *) break ;;
          esac
        done
        continue ;;
    esac
    w="${w%%[\"\']*}"
    [[ "$w" == */* && "$w" != '$'* ]] && w="${w##*/}"
    _hd_w="$w"; _hd_rest="$s"
    return
  done
}

# _bdb_hd_scan_body <first> <last> <quoted> — per-segment scan of
# _bdb_hd_L[first..last]. Sets _hd_kept (fence-verb segments, one per line),
# _hd_synth (variable-command segments rewritten as rm/git/kubectl) and
# _hd_full (1 = the body needs the full scan).
_bdb_hd_scan_body() {
  local k l t seg
  _hd_kept="" _hd_synth="" _hd_full=0
  for ((k = $1; k <= $2; k++)); do
    l="${_bdb_hd_L[k]}"
    [[ "$l" == *'<<'* ]] && _hd_full=1
    if (( ! $3 )); then
      case "$l" in *'$('*|*'`'*|*'<('*|*'>('*) _hd_full=1 ;; esac
    fi
    t="${l//'&&'/$'\n'}"; t="${t//'||'/$'\n'}"; t="${t//'|'/$'\n'}"; t="${t//';'/$'\n'}"; t="${t//'&'/$'\n'}"
    while :; do
      seg="${t%%$'\n'*}"
      _bdb_hd_segword "$seg"
      if [[ -n "$_hd_w" ]]; then
        # Under a quoted delimiter a backtick is literal text (r256-1): strip it from
        # the kept segment so the later backtick normalisation cannot turn prose such
        # as "git merge main; see `git merge spike/x` later" into a substitution.
        (( $3 )) && _hd_rest="${_hd_rest//\`/}"
        if [[ "$_hd_w" =~ $_bdb_hd_re_varw ]]; then
          _hd_full=1
          _hd_synth="${_hd_synth}rm${_hd_rest}"$'\n'"git${_hd_rest}"$'\n'"kubectl${_hd_rest}"$'\n'
        elif _bdb_hd_is_destructive "$_hd_w"; then
          _hd_kept="${_hd_kept}${_hd_w}${_hd_rest}"$'\n'
        elif _bdb_hd_is_interp "$_hd_w" || _bdb_hd_is_runner "$_hd_w"; then
          _hd_full=1
        fi
      fi
      [[ "$t" == *$'\n'* ]] || break
      t="${t#*$'\n'}"
    done
  done
}

# _bdb_hd_same_line_exec <basename> <header idx> <body first> <body last>
# → 0 when the target is named anywhere else in the command outside a safe
# reader (it may be executed, sourced, made executable, copied or moved).
_bdb_hd_same_line_exec() {
  local b="$1" hi="$2" bf="$3" bl="$4" k nt t u c cw seg_has pipe start j own
  for ((k = 0; k < _bdb_hd_n; k++)); do
    (( k >= bf && k <= bl )) && continue
    [[ "${_bdb_hd_L[k]}" == *"$b"* ]] || continue
    _bdb_hd_tokenize "${_bdb_hd_L[k]}" || return 0
    nt=${#_bdb_hd_tok[@]}
    start=0 pipe=0
    for ((j = 0; j <= nt; j++)); do
      t="${_bdb_hd_tok[j]:-}"
      if (( j < nt )) && ! [[ "$t" =~ ^(';'|';;'|'&'|'&&'|'||'|'('|')'|'|'|'|&')$ ]]; then continue; fi
      # segment [start, j)
      own=0
      (( k == hi && pipe == _hd_pipe_saved )) && own=1
      if (( ! own )); then
        seg_has=0 cw=""
        for ((c = start; c < j; c++)); do
          u="${_bdb_hd_tok[c]}"; u="${u//[\"\']/}"; u="${u##*/}"
          [[ "$u" == "$b" ]] && seg_has=1
        done
        if (( seg_has )); then
          _bdb_hd_segword "${_bdb_hd_tok[*]:start:j-start}"
          cw="$_hd_w"
          if ! _bdb_hd_is_safe_reader "$cw" || [[ "$cw" == "$b" ]]; then return 0; fi
        fi
      fi
      case "$t" in '|'|'|&') ;; *) pipe=$((pipe + 1)) ;; esac
      start=$((j + 1))
    done
  done
  return 1
}

# _bdb_heredoc_scrub <command> — print the scrub copy (non-executing heredoc
# bodies reduced to their fence-verb segments) and set _bdb_hd_class to the
# most executing class seen (interpreter > none > nonexec; none if no heredoc).
_bdb_heredoc_scrub() {
  local text="${1:-}" out="" i j found l cls ctx=0 seen="" d first
  _bdb_hd_class=none
  text="${text//$'\r\n'/$'\n'}"
  if [[ "$text" =~ $_bdb_hd_re_ctl ]]; then _bdb_hd_class=interpreter; printf '%s' "${1:-}"; return; fi
  text="${text%$'\n'}"
  _bdb_hd_L=()
  while IFS= read -r l; do _bdb_hd_L[${#_bdb_hd_L[@]}]="$l"; done <<< "$text"
  _bdb_hd_n=${#_bdb_hd_L[@]}
  i=0
  while (( i < _bdb_hd_n )); do
    l="${_bdb_hd_L[i]}"
    if [[ "$l" != *'<<'* ]]; then
      out="$out$l"$'\n'
      (( ctx )) || ! _bdb_hd_ctx_bad "$l" || ctx=1
      i=$((i + 1)); continue
    fi
    _bdb_hd_header "$l"
    if (( _hd_ops == 0 )); then
      out="$out$l"$'\n'
      (( ctx )) || ! _bdb_hd_ctx_bad "$l" || ctx=1
      i=$((i + 1)); continue
    fi
    if (( _hd_ops != 1 )); then _bdb_hd_class=interpreter; printf '%s' "${1:-}"; return; fi
    found=-1
    for ((j = i + 1; j < _bdb_hd_n; j++)); do
      d="${_bdb_hd_L[j]}"
      if (( _hd_tabs )); then while [[ "$d" == $'\t'* ]]; do d="${d#$'\t'}"; done; fi
      if [[ "$d" == "$_hd_delim" ]]; then found=$j; break; fi
    done
    if (( found < 0 )); then _bdb_hd_class=interpreter; printf '%s' "${1:-}"; return; fi
    cls="$_hd_cls"
    (( ctx )) && cls=interpreter
    _hd_pipe_saved="$_hd_pipe"
    if [[ "$cls" == nonexec ]]; then
      first="${_bdb_hd_L[i+1]:-}"
      (( i + 1 < found )) || first=""
      first="${first#"${first%%[![:blank:]]*}"}"
      [[ "$first" == '#!'* ]] && cls=interpreter
    fi
    if [[ "$cls" == nonexec ]]; then
      local -a dests
      dests=(${_hd_dests[@]+"${_hd_dests[@]}"})
      for d in ${dests[@]+"${dests[@]}"}; do
        if _bdb_hd_exec_dest "$d" || _bdb_hd_same_line_exec "${d##*/}" "$i" $((i + 1)) $((found - 1)); then
          cls=interpreter; break
        fi
      done
    fi
    _bdb_hd_scan_body $((i + 1)) $((found - 1)) "$_hd_quoted"
    out="$out$l"$'\n'
    if [[ "$cls" == nonexec ]] && (( ! _hd_full )); then
      # #1245 special case: a standalone quoted `cat <<'W' [> path]` drops it all.
      if ! (( i == 0 && found == _bdb_hd_n - 1 && _hd_quoted )) || ! _bdb_hd_plain_cat "$l"; then
        out="$out$_hd_kept"
      fi
    else
      [[ "$cls" == nonexec ]] && cls=interpreter
      for ((j = i + 1; j < found; j++)); do out="$out${_bdb_hd_L[j]}"$'\n'; done
      out="$out$_hd_synth"
    fi
    out="$out${_bdb_hd_L[found]}"$'\n'
    (( ctx )) || ! _bdb_hd_ctx_bad "$l" || ctx=1
    case "$cls" in
      interpreter) seen=interpreter ;;
      none) [[ "$seen" == interpreter ]] || seen=none ;;
      nonexec) [[ -n "$seen" ]] || seen=nonexec ;;
    esac
    i=$((found + 1))
  done
  _bdb_hd_class="${seen:-none}"
  printf '%s' "${out%$'\n'}"
}

# The #1245 header grammar (byte-identical to _bdb_scrub_cat_heredoc's).
_bdb_hd_plain_cat() {
  local header="${1:-}" marker candidate
  local delimiter_re="<<(-?)('([[:alnum:]_]+)'|\"([[:alnum:]_]+)\")"
  local path_re="([[:alnum:]_./-]+|'[[:alnum:]_ ./-]+'|\"[[:alnum:]_ ./-]+\")"
  local header_re="^[[:blank:]]*cat[[:blank:]]+(HEREDOC([[:blank:]]+>>?[[:blank:]]*${path_re})?|>>?[[:blank:]]*${path_re}[[:blank:]]+HEREDOC)[[:blank:]]*$"
  [[ "$header" =~ $delimiter_re ]] || return 1
  marker="${BASH_REMATCH[0]}"
  candidate="${header/"$marker"/HEREDOC}"
  [[ "$candidate" =~ $header_re ]]
}

# Knob: destructive_command_guard.heredoc_classifier in the repo's
# .loa.config.yaml (read once, no fork, only for commands holding `<<`).
# Only an explicit false|no|off turns it off; turning it off only tightens.
_bdb_heredoc_knob_on() {
  local cfg="${LOA_REPO_ROOT:-${CLAUDE_PROJECT_DIR:-.}}/.loa.config.yaml" content="" l in_blk=0
  [[ -f "$cfg" && -r "$cfg" ]] || return 0
  IFS= read -r -d '' content < "$cfg" || true
  [[ "$content" == *heredoc_classifier* ]] || return 0
  while IFS= read -r l; do
    case "$l" in
      destructive_command_guard:*) in_blk=1; continue ;;
      [A-Za-z_]*) in_blk=0; continue ;;
    esac
    if (( in_blk )) && [[ "$l" =~ $_bdb_hd_re_knob ]]; then
      case "${BASH_REMATCH[1]}" in false|False|FALSE|no|No|NO|off|Off|OFF) return 1 ;; esac
    fi
  done <<< "$content"
  return 0
}

# Exported entry points (source with BDB_LIB_ONLY=1).
_bdb_heredoc_consumer_class() {
  local LC_ALL=C
  _bdb_heredoc_scrub "${1:-}" >/dev/null
  printf '%s\n' "$_bdb_hd_class"
}
heredoc_nonexec() {
  [[ "$(_bdb_heredoc_consumer_class "${1:-}")" == nonexec ]]
}

# Library mode: only when SOURCED. Executed with BDB_LIB_ONLY=1 the hook runs
# normally — an environment variable can never switch the fence off.
if [[ "${BDB_LIB_ONLY:-}" == "1" && "${BASH_SOURCE[0]:-}" != "${0:-}" ]]; then
  return 0
fi

# -----------------------------------------------------------------------------
# jq presence probe (SDD §6.5 — SKP-008 mitigation, not full fix).
# If jq is absent, the input parse on line ~120 returns empty → existing
# fail-open guard exits 0. v1.38.0 adds a one-shot stderr WARNING so the
# operator / agent sees the safety guard is disabled this session.
# Tracked as cycle-112 candidate (filesystem-marker variant for cross-
# invocation persistence; env-var doesn't propagate across hook subprocess
# invocations per Flatline SKP-002 round-3 finding).
# -----------------------------------------------------------------------------
# perf pass-11 (skill-loop, 2026-07-06): HIGH-002 fix (BB review of PR #1176).
# Passes 2 & 8 introduced bash-4-only constructs into this fence (${x,,}
# case-folding, `mapfile`); pre-loop it was bash-3.2-portable (echo|grep -i).
# macOS ships bash 3.2. This guard runs BEFORE any bash-4 expansion executes
# (bash 3.2 defers ${,,} validation and the mapfile builtin lookup to runtime,
# so a runtime guard at the first executable line runs first and never reaches
# them). If a bash >=4 exists (the framework already requires it — beads-health
# etc. source bash-version-guard.sh), re-exec under it; stdin (the hook payload)
# and argv survive exec. Otherwise FAIL CLOSED (exit 2 = block): a
# destructive-command fence must never silently allow when it cannot evaluate.
# The generic bash-version-guard.sh exits 1, which is a NON-blocking PreToolUse
# hook error (fail-OPEN) — wrong direction for this hook, hence the inline form.
if [ "${BASH_VERSINFO:-0}" -lt 4 ]; then
    for _bh_cand in /opt/homebrew/bin/bash /usr/local/bin/bash /usr/bin/bash bash; do
        if command -v "$_bh_cand" >/dev/null 2>&1; then
            _bh_major="$("$_bh_cand" -c 'echo "${BASH_VERSINFO:-0}"' 2>/dev/null || echo 0)"
            if [ "${_bh_major:-0}" -ge 4 ]; then exec "$_bh_cand" "$0" "$@"; fi
        fi
    done
    echo "[block-destructive-bash] BLOCKED: bash >=4 required to evaluate the destructive-command fence (found ${BASH_VERSION:-unknown}); refusing to run degraded rather than allow a command unchecked. Install bash>=4 (macOS: brew install bash)." >&2
    exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  if [[ -z "${LOA_BLOCK_DESTRUCTIVE_JQ_MISSING_WARNED:-}" ]]; then
    echo "WARNING: block-destructive-bash: jq not in PATH — destructive-command pattern matching is DISABLED for this session. Install jq to restore safety guards." >&2
    export LOA_BLOCK_DESTRUCTIVE_JQ_MISSING_WARNED=1
  fi
  exit 0  # Existing fail-open behavior preserved.
fi

# perf pass-2: pin byte-oriented ASCII regex/case-fold semantics for both the
# remaining greps and the bash [[ =~ ]]/${var,,} conversions. All patterns in
# this file are pure-ASCII; C-locale folding is the semantics they were
# written for (and what the test/golden harness already pins).
export LC_ALL=C

# Read tool input from stdin (JSON with tool_input.command).
# Path A jq call (SDD §6.4): failure here → empty $command → allow.
# perf pass-2: jq reads the hook's stdin directly — identical bytes reach the
# same jq program; the interim $(cat) copy and echo-pipe only added 2 forks.
command=$(jq -r '.tool_input.command // empty' 2>/dev/null) || true

# If we can't parse the command, allow (don't block on parse errors).
if [[ -z "$command" ]]; then
  exit 0
fi

# -----------------------------------------------------------------------------
# quote-blindness scrub (bd-bdb-quote-blindness-pt1g).
# Produce _cmd_match, a LOCAL scrub-copy of $command used SOLELY for the
# block/allow decision below. $command itself is left byte-for-byte intact so
# emit_block's audit row still records the operator's original command.
#
# The fence is quote-blind: it sees a destructive TOKEN (rm -rf, DROP/TRUNCATE
# TABLE, DELETE FROM, git branch -D, ...) inside an INERT data carrier — an
# echo argument, a git commit message, a bead description, a gh PR body — and
# blocks a harmless command. The GENERAL problem (deciding whether an arbitrary
# quoted string will be executed) is NOT tractable in a regex fence — any
# allowlist of *execution* shapes (ssh/su -c/sh -c/xargs/...) is unbounded and
# reintroduces bypass (issue #1047). This is the INVERSE: a curated allowlist
# of KNOWN-INERT data carriers, whose value we redact into the scrub-copy.
#
# The metadata content gate (cycle-120 C-D3a) leaves values containing `$(` or
# backticks INTACT, including `$$(...)`. Those expansions can execute even in
# double quotes. A lone `$` is permitted. Double-quote escapes are consumed as
# pairs so an escaped quote cannot open a fake tail flag spanning a live write.
# The command-position prefix check rejects names inside other quoted data or
# interpreter/eval arguments. Unknown contexts retain conservative matching;
# these bounded recognizers do not establish arbitrary execution semantics.
#
# Carrier values may contain literal separators; following executable segments
# remain visible, so `echo 'safe' && rm -rf /` still blocks. Word boundaries and
# the prefix check keep `notgit commit -m '…'` from matching. echo/printf stays a sed
# scrub (rest-of-segment, not a quoted value); the git/br/gh quoted-value
# carriers use the content-gated bash loop `_bdb_scrub` below (replace the value
# with a single SPACE, never empty). BSD/GNU ERE only — no \b (BSD libc lacks
# it; header §).
# -----------------------------------------------------------------------------
# Bare echo/printf carrier: from a segment-start echo/printf to the end of its
# segment. The rest-class excludes ; & | (segment separators — per-segment
# scoping), $ and backtick (command-substitution — never redact past them), and
# < > (redirect operators — leave redirects + their targets intact so the FR-SZ
# State-Zone write guard, which keys off the raw path, still fires on
# `echo x >> .run/cron.d/job.sh`).
_bdb_sed_echo='s/(^|;|&&|\|\||\|)([[:space:]]*(sudo[[:space:]]+)?(echo|printf)[[:space:]]+)[^;&|<>$`]*/\1\2 /g'

# Quoted-value carriers (git commit -m / br|bd … -d / gh … create --body|--title).
# cycle-120 C-D3a: content-gated redaction. The value permits `$` and stops at
# an unescaped closing quote; _bdb_scrub then applies the content gate. The
# quoted value is the penultimate capture group. [^;&|]* keeps
# the prefix within one segment; (^|[^[:alnum:]_]) is the anti-spoof boundary.
# cycle-120 R1 fix (CRITICAL): the pre-flag prefix classes ALSO exclude quotes
# (`[^;&|'"]*`). Without that, POSIX leftmost-longest lets the prefix walk PAST
# the real flag+opening-quote and re-anchor on a decoy flag literal embedded in
# the value (`git commit -m "-m " && rm -rf "/"`), so the value capture spans
# from the string's real closing quote to the NEXT quote — swallowing a live
# `&& rm -rf "` into a redacted "carrier value". Barring quotes from the prefix
# means a flag can only be matched before any quote in the segment is opened.
# A double-quoted value consumes backslash/character pairs together. An escaped
# quote must never become a terminator and expose a fake subsequent flag.
# The value is the penultimate group; the last group is the double-quote atom.
_bdb_qval_perm="('[^']*'|\"([^\"\\\\]|\\\\.)*\")"
_bdb_re_git="(^|[^[:alnum:]_])git[[:space:]][^;&|'\"]*commit[^;&|'\"]*(-m|--message)[[:space:]]+${_bdb_qval_perm}"
_bdb_re_brbd="(^|[^[:alnum:]_])(br|bd)[[:space:]][^;&|'\"]*(create|update)[^;&|'\"]*(-d|--description)[[:space:]]+${_bdb_qval_perm}"
_bdb_re_gh="(^|[^[:alnum:]_])gh[[:space:]][^;&|'\"]*(issue|pr)[^;&|'\"]*create[^;&|'\"]*(--body|--title)[[:space:]]+${_bdb_qval_perm}"
# cycle-125 FR-1 (D-1.7): the quoted pattern argument of a read-only search
# tool is text, never a command — `grep -rn "rm -rf dist" file` and
# `rg 'DROP TABLE' migrations/` were the most common benign shapes the SQL and
# rm rules matched. Only grep-family tools are carriers here: sed/awk can
# execute (`s///e`, `system()`), so their scripts stay visible. The value is
# the first quoted argument after any flags; content-gated like every carrier.
_bdb_re_grep="(^|[^[:alnum:]_])(grep|egrep|fgrep|rg|ag|ack)[[:space:]]+((-[^[:space:]]+)[[:space:]]+)*${_bdb_qval_perm}"

# Tail-run of contiguous message flags after the primary carrier match. A
# single `git commit`/`gh create`/… can carry MULTIPLE `-m/--message`/`-d`/
# `--body`… pairs (git concatenates multi-`-m` into paragraphs). The primary
# regex, now that the prefix bars quotes (R1 fix), only anchors the FIRST pair;
# this tail consumes further contiguous `flag <quoted-value>` pairs so all of a
# genuine multi-flag message is redacted. It is anchored at the START of the
# remaining text (`^[[:space:]]*flag …`), so it CANNOT cross a statement
# separator: the moment the remainder begins with anything other than another
# message flag (e.g. `&& rm -rf`), the tail stops and that text is left INTACT
# for FR-2. This keeps multi-`-m` benign commits allowed WITHOUT reopening the
# `&&`-crossing bypass.
_bdb_re_tail="^[[:space:]]*(-m|--message|-d|--description|--body|--title)[[:space:]]+${_bdb_qval_perm}"

# A carrier name must start a command, not occur inside another value or an
# interpreter/eval argument. This small prefix scan tracks quoting/escaping
# only; complex substitution/heredoc prefixes are conservatively left raw.
_bdb_at_command_start() {
  local prefix="$1" i ch quote="" escaped=0 at_start=1
  [[ "$prefix" != *'$('* && "$prefix" != *'`'* && "$prefix" != *'<<'* ]] || return 1
  for ((i=0; i<${#prefix}; i++)); do
    ch="${prefix:i:1}"
    if [[ "$quote" == "'" ]]; then
      [[ "$ch" == "'" ]] && quote=""
      continue
    fi
    if (( escaped )); then escaped=0; at_start=0; continue; fi
    if [[ "$ch" == '\' ]]; then escaped=1; at_start=0; continue; fi
    if [[ "$quote" == '"' ]]; then
      [[ "$ch" == '"' ]] && quote=""
      continue
    fi
    case "$ch" in
      "'"|'"') quote="$ch"; at_start=0 ;;
      '#') return 1 ;;
      ';'|'&'|'|'|$'\n') at_start=1 ;;
      ' '|$'\t') ;;
      *) at_start=0 ;;
    esac
  done
  [[ -z "$quote" && "$escaped" == 0 && "$at_start" == 1 ]]
}

# _bdb_scrub <carrier-ere> <input> — echo the input with every carrier value
# that passes the content gate replaced by a single SPACE (never empty, never
# crossing a segment). A value containing `$(` (this catches `$$(` too — the
# substring is present) or a backtick is left INTACT. bash =~ exposes no match
# offset, so the split is by string slice on the matched text.
_bdb_scrub() {
  local re="$1" rest="$2" out="" m val inner pre po vi boundary
  while [[ "$rest" =~ $re ]]; do
    m="${BASH_REMATCH[0]}"
    boundary="${BASH_REMATCH[1]}"
    vi=$(( ${#BASH_REMATCH[@]} - 2 ))   # group before the double-quote atom
    val="${BASH_REMATCH[$vi]}"
    pre="${rest%%"$m"*}"                 # text before this match
    rest="${rest#*"$m"}"                 # text after this match
    if ! _bdb_at_command_start "$out$pre$boundary"; then
      out+="$pre$m"
      continue                         # no tail recovery inside unknown quoting
    fi
    inner="${val:1:${#val}-2}"          # strip the outer quotes
    if [[ "$inner" == *'$('* || "$inner" == *'`'* ]]; then
      out+="$pre$m"                     # command-sub value — leave INTACT
    else
      po="${m%"$val"}"                  # matched text minus the trailing value
      out+="$pre$po "                   # value → single space
    fi
    # Consume any contiguous trailing message-flag pairs (multi-`-m`), each
    # content-gated the same way. Stops at the first non-flag token (separator
    # or real content), so it never crosses a statement boundary.
    while [[ "$rest" =~ $_bdb_re_tail ]]; do
      m="${BASH_REMATCH[0]}"
      vi=$(( ${#BASH_REMATCH[@]} - 2 ))
      val="${BASH_REMATCH[$vi]}"
      rest="${rest#"$m"}"
      inner="${val:1:${#val}-2}"
      if [[ "$inner" == *'$('* || "$inner" == *'`'* ]]; then
        out+="$m"                       # command-sub value — leave INTACT
      else
        po="${m%"$val"}"
        out+="$po "
      fi
    done
  done
  printf '%s' "$out$rest"
}

# #1245: recognize ONLY a complete, standalone cat with a quoted heredoc.
# The delimiter disables shell expansion in the body. The header remains
# visible (including protected redirect targets). Interpreter consumers,
# pipelines, unquoted delimiters, nested contexts and trailing commands keep
# their raw text: the body may execute in those forms. This is deliberately
# a small carrier grammar, not a shell parser.
_bdb_scrub_cat_heredoc() {
  local text="$1" header rest marker delim strip_tabs line candidate
  local delimiter_re="<<(-?)('([[:alnum:]_]+)'|\"([[:alnum:]_]+)\")"
  local path_re="([[:alnum:]_./-]+|'[[:alnum:]_ ./-]+'|\"[[:alnum:]_ ./-]+\")"
  local header_re="^[[:blank:]]*cat[[:blank:]]+(HEREDOC([[:blank:]]+>>?[[:blank:]]*${path_re})?|>>?[[:blank:]]*${path_re}[[:blank:]]+HEREDOC)[[:blank:]]*$"
  [[ "$text" == *$'\n'* ]] || { printf '%s' "$text"; return; }
  header="${text%%$'\n'*}"
  if [[ ! "$header" =~ $delimiter_re ]]; then
    printf '%s' "$text"; return
  fi
  marker="${BASH_REMATCH[0]}"
  strip_tabs="${BASH_REMATCH[1]}"
  delim="${BASH_REMATCH[3]:-${BASH_REMATCH[4]}}"
  candidate="${header/"$marker"/HEREDOC}"
  if [[ ! "$candidate" =~ $header_re ]]; then
    printf '%s' "$text"; return
  fi
  rest="${text#*$'\n'}"
  while [[ -n "$rest" ]]; do
    line="${rest%%$'\n'*}"
    if [[ "$rest" == *$'\n'* ]]; then rest="${rest#*$'\n'}"; else rest=""; fi
    if [[ "$strip_tabs" == "-" ]]; then
      while [[ "$line" == $'\t'* ]]; do line="${line#$'\t'}"; done
    fi
    if [[ "$line" == "$delim" ]]; then
      if [[ -z "$rest" ]]; then printf '%s' "$header"; else printf '%s' "$text"; fi
      return
    fi
  done
  # No closing delimiter: leave the entire command visible.
  printf '%s' "$text"
}

# #1245: two COMPLETE data-only programs, not arbitrary interpreter exemptions.
# Loop: single-quoted items, one printf with a fixed format and the same lower-
# case variable. Python: single-quoted -c source, double-quoted string literals
# without escapes, a list optionally assigned and printed. No imports, calls
# other than that print, interpolation, other consumers or trailing shell text.
# Single shell quotes keep $()/backticks in these literals inert. Any mismatch
# retains raw input, including double-quoted arguments where expansions execute.
_bdb_scrub_literal_program() {
  local text="$1" loop_re python_re source name list_re program_re
  loop_re="^[[:space:]]*for[[:blank:]]+([a-z][a-z0-9_]*)[[:blank:]]+in[[:blank:]]+'[^']*'([[:blank:]]+'[^']*')*[[:blank:]]*;[[:space:]]*do[[:space:]]+printf[[:blank:]]+'%s"
  loop_re+='\\n'
  loop_re+="'[[:blank:]]+"
  loop_re+='"[$]([a-z][a-z0-9_]*)"[[:blank:]]*;[[:space:]]*done[[:space:]]*$'
  if [[ "$text" =~ $loop_re ]] && [[ "${BASH_REMATCH[1]}" == "${BASH_REMATCH[3]}" ]]; then
    printf '%s' ': literal loop data'
    return
  fi
  python_re="^[[:blank:]]*python3?[[:blank:]]+-c[[:blank:]]+'([^']*)'[[:blank:]]*$"
  if [[ "$text" =~ $python_re ]]; then
    source="${BASH_REMATCH[1]}"
    list_re='\[[[:space:]]*("[^"\\]*"[[:space:]]*(,[[:space:]]*"[^"\\]*"[[:space:]]*)*,?[[:space:]]*)?\]'
    program_re="^[[:space:]]*${list_re}[[:space:]]*$"
    if [[ "$source" =~ ^[[:space:]]*([a-z][a-z0-9_]*)[[:space:]]*= ]]; then
      name="${BASH_REMATCH[1]}"
      program_re="^[[:space:]]*${name}[[:space:]]*=[[:space:]]*${list_re}([[:space:]]*;[[:space:]]*print\([[:space:]]*${name}[[:space:]]*\))?[[:space:]]*$"
    fi
    if [[ "$source" =~ $program_re ]]; then
      printf '%s' ': literal Python data'
      return
    fi
  fi
  printf '%s' "$text"
}

# -----------------------------------------------------------------------------
# cycle-129 r256-1 (sprint-256 review HIGH-1): a backtick pair outside single
# quotes is a command substitution exactly like `$( … )` — in plain text, inside
# double quotes, in an assignment and in an unquoted heredoc body — but every
# rule anchors on `(`, `;`, `&&`, `|`, whitespace or a quote and none on a
# backtick, so `echo "see \`git push --force origin main\`"` matched nothing
# while its `$( )` twin blocked (identical on main 864069f2). Normalise before
# the rules run: the 1st, 3rd, … backtick outside single quotes becomes `$(`,
# the 2nd, 4th, … becomes `)`; a backslash escapes the next character outside
# single quotes (an escaped backtick stays literal); inside single quotes
# nothing changes. Kept segments of a quoted-delimiter heredoc body have their
# literal backticks stripped by _bdb_hd_scan_body before this runs. Fast path
# (no single quote, no backslash in the text): alternate by position; the
# char loop runs only when quoting has to be tracked. Costs one substring test
# on the common path.
# -----------------------------------------------------------------------------
# Heredoc bodies are raw text (no shell quoting applies inside them): under an
# unquoted delimiter every backtick is a substitution, under a quoted one every
# backtick is literal — so the normaliser walks the command line by line, uses
# _bdb_hd_header to find each heredoc's delimiter and quoting, and applies the
# body rule to body lines and shell-quote tracking (_bt_q) to the rest. If the
# shell text's quotes do not balance at the end (an apostrophe in prose, an
# unreadable header, two heredocs on one line) the whole shell text is redone
# with quoting ignored: fail closed, never literal by accident.
# _bdb_bt_alt_line <line>  → _bt_out: plain alternation (state _bt_open)
# _bdb_bt_shell_line <line> → _bt_out: alternation outside single quotes
_bt_out="" _bt_open=0 _bt_q="" _bt_force=0
_bdb_bt_alt_line() {
  local s="${1:-}" i n ch
  _bt_out=""
  [[ "$s" == *'`'* ]] || { _bt_out="$s"; return; }
  n=${#s}
  for ((i = 0; i < n; i++)); do
    ch="${s:i:1}"
    if [[ "$ch" == '\' ]]; then
      _bt_out+="$ch"; if (( i + 1 < n )); then i=$((i + 1)); _bt_out+="${s:i:1}"; fi; continue
    fi
    if [[ "$ch" == '`' ]]; then
      if (( _bt_open )); then _bt_out+=')'; _bt_open=0; else _bt_out+='$('; _bt_open=1; fi
      continue
    fi
    _bt_out+="$ch"
  done
}
_bdb_bt_shell_line() {
  local s="${1:-}" i n ch
  if (( _bt_force )); then _bdb_bt_alt_line "$s"; return; fi
  if [[ "$s" != *'`'* && "$s" != *"'"* && "$s" != *'"'* && "$s" != *'\'* ]]; then _bt_out="$s"; return; fi
  _bt_out=""
  n=${#s}
  for ((i = 0; i < n; i++)); do
    ch="${s:i:1}"
    if [[ "$_bt_q" == "'" ]]; then
      [[ "$ch" == "'" ]] && _bt_q=""
      _bt_out+="$ch"; continue
    fi
    if [[ "$ch" == '\' ]]; then
      _bt_out+="$ch"; if (( i + 1 < n )); then i=$((i + 1)); _bt_out+="${s:i:1}"; fi; continue
    fi
    if [[ "$ch" == '`' ]]; then
      if (( _bt_open )); then _bt_out+=')'; _bt_open=0; else _bt_out+='$('; _bt_open=1; fi
      continue
    fi
    if [[ -z "$_bt_q" && "$ch" == "'" ]]; then _bt_q="'"
    elif [[ "$ch" == '"' ]]; then
      if [[ "$_bt_q" == '"' ]]; then _bt_q=""; else _bt_q='"'; fi
    fi
    _bt_out+="$ch"
  done
}
_bdb_backtick_norm() {
  local s="${1:-}"
  [[ "$s" == *'`'* ]] || { printf '%s' "$s"; return; }
  local -a L
  local l n i out="" body=0 delim="" quoted=0 tabs=0 d pass
  L=()
  while IFS= read -r l || [[ -n "$l" ]]; do L[${#L[@]}]="$l"; done <<< "$s"
  n=${#L[@]}
  for pass in 1 2; do
    out="" body=0 _bt_open=0 _bt_q="" _bt_force=0
    (( pass == 2 )) && _bt_force=1
    for ((i = 0; i < n; i++)); do
      l="${L[i]}"
      if (( body )); then
        d="$l"
        if (( tabs )); then while [[ "$d" == $'\t'* ]]; do d="${d#$'\t'}"; done; fi
        if [[ "$d" == "$delim" ]]; then body=0; _bt_open=0; out+="$l"$'\n'; continue; fi
        if (( quoted )); then out+="$l"$'\n'; else _bdb_bt_alt_line "$l"; out+="$_bt_out"$'\n'; fi
        continue
      fi
      _bdb_bt_shell_line "$l"; out+="$_bt_out"$'\n'
      if [[ "$l" == *'<<'* ]]; then
        _bdb_hd_header "$l"
        if (( _hd_ops == 1 )); then body=1; delim="$_hd_delim"; quoted=$_hd_quoted; tabs=$_hd_tabs; _bt_open=0
        elif (( _hd_ops != 0 )); then _bt_force=1   # unreadable header or several heredocs: fail closed from here
        fi
      fi
    done
    [[ -z "$_bt_q" ]] && break          # balanced quotes: done; else pass 2 ignores quoting
  done
  out="${out%$'\n'}"
  [[ "$s" == *$'\n' ]] && out+=$'\n'
  printf '%s' "$out"
}

# Heredoc scrub, then backtick normalisation, then quoted-value carriers, then
# echo/printf (sed). The echo scrub must run last: it can otherwise consume a
# closing quote in metadata containing "; echo ..." and make a later live write
# look quoted. (bash loops, each guarded by a cheap literal test so the benign
# path pays nothing beyond the substring check).
_cmd_match="$command"
if [[ "$_cmd_match" == *"for "* || "$_cmd_match" == *"python"* ]]; then
  _cmd_match=$(_bdb_scrub_literal_program "$_cmd_match")
fi
# cycle-129 FR-6: with destructive_command_guard.heredoc_classifier on (the
# default) the fail-closed consumer classifier above replaces the #1245 scrub,
# which survives unchanged as its special case and as the knob-off path.
if [[ "$_cmd_match" == *"<<"* ]]; then
  if _bdb_heredoc_knob_on; then
    _cmd_match=$(_bdb_heredoc_scrub "$_cmd_match")
  else
    _cmd_match=$(_bdb_scrub_cat_heredoc "$_cmd_match")
  fi
fi
# cycle-129 r256-1: backtick substitutions take the `$( )` form the rules anchor on
[[ "$_cmd_match" == *'`'* ]] && _cmd_match=$(_bdb_backtick_norm "$_cmd_match")
[[ "$_cmd_match" == *"git"* ]] && _cmd_match=$(_bdb_scrub "$_bdb_re_git" "$_cmd_match")
if [[ "$_cmd_match" == *"br "* || "$_cmd_match" == *"bd "* ]]; then
  _cmd_match=$(_bdb_scrub "$_bdb_re_brbd" "$_cmd_match")
fi
[[ "$_cmd_match" == *"gh "* ]] && _cmd_match=$(_bdb_scrub "$_bdb_re_gh" "$_cmd_match")
if [[ "$_cmd_match" == *grep* || "$_cmd_match" == *"rg "* || "$_cmd_match" == *"ag "* || "$_cmd_match" == *"ack "* ]]; then
  _cmd_match=$(_bdb_scrub "$_bdb_re_grep" "$_cmd_match")   # cycle-125 D-1.7
fi
_cmd_match=$(printf '%s' "$_cmd_match" | sed -E -e "$_bdb_sed_echo" 2>/dev/null) || _cmd_match="$command"
# Fail-safe: an empty scrub on a non-empty command → fall back to RAW (stricter
# matching), never to an empty scrub that would silence every pattern.
[[ -z "$_cmd_match" ]] && _cmd_match="$command"

# -----------------------------------------------------------------------------
# perf pass-2 line-model helpers.
#
# `echo "$cmd" | grep -qE PAT` tests PAT against each LINE; bash [[ =~ ]]
# tests the WHOLE string, where a `[[:space:]]` would match the newline
# itself, negated classes like [^-] would cross line boundaries, and ^/$
# anchor only at string edges. To keep byte-identical semantics we split
# $command into grep's line model ONCE (trailing \n is a terminator, not an
# extra empty line; a final fragment without \n is still a line) and test
# per line. Invalid-regex behavior also matches the old `grep -qE …
# 2>/dev/null`: [[ =~ ]] returns non-zero silently.
# -----------------------------------------------------------------------------
# quote-blindness fix: derive the line model from the scrub-copy _cmd_match so
# every pattern that goes through _match/_match_ci (P2-P9, P11, P12, FR-2 gate)
# sees inert carrier values redacted, with ZERO change to their own regexes.
_cmd_lines=()
if [[ "$_cmd_match" == *$'\n'* ]]; then
  mapfile -t _cmd_lines <<<"${_cmd_match%$'\n'}"
else
  _cmd_lines=("$_cmd_match")
fi

# _match <ere> — exit 0 iff any line matches; ≡ echo "$command" | grep -qE <ere>
_match() {
  local _l
  for _l in "${_cmd_lines[@]}"; do
    [[ "$_l" =~ $1 ]] && return 0
  done
  return 1
}

# _match_ci <lowercase-ere> — ≡ echo "$command" | grep -qiE <ere>.
# Case-insensitivity via ${line,,} against a pre-lowercased pattern: ASCII
# fold under the LC_ALL=C pin above, exactly grep -i's C-locale fold.
_match_ci() {
  local _l
  for _l in "${_cmd_lines[@]}"; do
    [[ "${_l,,}" =~ $1 ]] && return 0
  done
  return 1
}

# =============================================================================
# emit_block — SDD §6.1 helper
# =============================================================================
# Args: pattern_id, matched_substring, message
# Emits BLOCKED stderr for the agent, appends a sanitized audit row to
# .run/audit.jsonl, then exit 2.
#
# Path B jq call (SDD §6.4): the audit-emit jq runs inside a `|| true`-
# wrapped subshell. Failures here drop the audit row but the exit 2
# (block decision) still fires. Path A and Path B failure modes are
# distinct and CANNOT collapse: Path B only runs after Path A succeeded
# (otherwise $command is empty and the hook already exited 0).
emit_block() {
  local pattern_id="$1"
  local matched="$2"
  local message="$3"

  # Stderr to the agent — pattern_id + message gives enough to pick an alternative.
  echo "BLOCKED [$pattern_id]: $message" >&2

  # Audit row emission — best-effort, never affects block decision.
  {
    local redactor="${LOA_REPO_ROOT:-.}/.claude/scripts/lib/log-redactor.sh"

    local sanitized_cmd
    sanitized_cmd=$(printf '%s' "$command" | "$redactor" 2>/dev/null) || sanitized_cmd="[REDACTOR-FAILED]"

    # SDD §6.1 v1.1 SKP-008 closure: also redact the matched substring.
    local sanitized_match
    sanitized_match=$(printf '%s' "$matched" | "$redactor" 2>/dev/null) || sanitized_match="[REDACTOR-FAILED]"

    # Truncate AFTER redaction (so partial AKIA prefixes can't slip through).
    if [[ ${#sanitized_cmd} -gt 2048 ]]; then
      sanitized_cmd="${sanitized_cmd:0:2048}[...TRUNCATED]"
    fi
    if [[ ${#sanitized_match} -gt 256 ]]; then
      sanitized_match="${sanitized_match:0:256}[...TRUNCATED]"
    fi

    ( umask 077; mkdir -p -- "${LOA_REPO_ROOT:-.}/.run" ) 2>/dev/null || true

    # perf pass-2: UTC timestamp via bash strftime (was `date -u` spawn);
    # cwd via $PWD (bash keeps it identical to the pwd builtin's output).
    local _ts
    TZ=UTC0 printf -v _ts '%(%Y-%m-%dT%H:%M:%SZ)T' -1

    jq -cn \
      --arg ts "$_ts" \
      --arg cmd "$sanitized_cmd" \
      --arg cwd "$PWD" \
      --arg model "${LOA_CURRENT_MODEL:-}" \
      --arg provider "${LOA_CURRENT_PROVIDER:-}" \
      --arg trace_id "${LOA_TRACE_ID:-}" \
      --arg team_id "${LOA_TEAM_ID:-}" \
      --arg team_member "${LOA_TEAM_MEMBER:-}" \
      --arg pattern_id "$pattern_id" \
      --arg matched "$sanitized_match" \
      --arg replay "${LOA_AUDIT_REPLAY:-}" \
      '{ts: $ts, tool: "Bash", command: $cmd, exit_code: 2, cwd: $cwd, model: $model, provider: $provider, trace_id: $trace_id, team_id: $team_id, team_member: $team_member, hook: "block-destructive-bash", action: "block", pattern_id: $pattern_id, matched: $matched} + (if $replay == "1" then {replay: true} else {} end)' \
      >> "${LOA_REPO_ROOT:-.}/.run/audit.jsonl" 2>/dev/null || true
  } 2>/dev/null || true

  exit 2
}

# Backward-compat helper: existing call sites used check_and_block. Keep it
# as a thin wrapper that funnels through emit_block with pattern_id="LEGACY".
# All new direct callers should use emit_block with a real pattern_id.
check_and_block() {
  local pattern="$1"
  local message="$2"
  if echo "$command" | grep -qE "$pattern" 2>/dev/null; then
    local matched
    matched=$(echo "$command" | grep -oE "$pattern" | head -1)
    # @guard fence:LEGACY
    emit_block "LEGACY" "$matched" "$message"
  fi
}

# =============================================================================
# Pattern dispatch — SDD §6.2 order: high-frequency-first / FR-2 last.
# =============================================================================

# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# FR-GH-1 — gh api with a destructive method (DELETE, PUT, PATCH; `-X`, `-XDELETE`,
# `--method`, `--method=`) against refs, branch protection, tags, releases or the
# repository itself (cycle-129 sprint-256 audit HIGH-A1). The porcelain twins are
# governed by P2 (force push), P5 (branch force-delete) and SP-1 (spike pushes);
# the REST escape hatch was not. GET, POST and PATCH on issues or pulls stay allowed.
# Judged on the carrier-scrubbed command: the gh scrub redacts --body/--title
# values only, so the path and the method remain visible. Placed OUTSIDE the
# git-family pre-filter below: a gh api call need not contain the word git.
# -----------------------------------------------------------------------------
if [[ "$command" == *"gh"* && "$command" == *"api"* ]]; then
  # REST form: a destructive method — literal DELETE|PUT|PATCH, or a NON-literal value
  # (`-X "$M"`, `--method=$m`), which cannot be judged and is treated as destructive —
  # against a protected path. The path may carry an optional https://HOST(/api/v3)
  # prefix or a leading slash (audit r256-5, dissent DISS-C-003).
  _ghapi_path='(https?://[^/[:space:];&|]+(/api/v3)?)?/?repos/[^/[:space:];&|]+/[^/[:space:];&|]+'
  if { _match '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*gh[[:space:]]+api[[:space:]]([^;&|]*[[:space:]])?(-X|--method)[=[:space:]]*["'"'"']?(DELETE|PUT|PATCH)' \
       || _match '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*gh[[:space:]]+api[[:space:]]([^;&|]*[[:space:]])?(-X|--method)[=[:space:]]*["'"'"']?[$]'; } \
     && _match 'gh[[:space:]]+api[[:space:]][^;&|]*'"${_ghapi_path}"'(/git/refs/|/git/tags/|/branches/[^/[:space:];&|]+/protection|/releases(/|["'"'"'[:space:];&|]|$)|/tags(/|["'"'"'[:space:];&|]|$)|(["'"'"'[:space:];&|]|$))'; then
    matched=$(echo "$command" | grep -oE 'gh[[:space:]]+api[^;&|]*' | head -1)
    # @guard fence:FR-GH-1
    emit_block "FR-GH-1" "$matched" "gh api with DELETE, PUT or PATCH (or a method the fence cannot read) on refs, branch protection, tags, releases or the repository is refused: use the git/gh porcelain the fence governs, or an operator-run command."
  fi
  # GraphQL form: the mutations that delete or rewrite refs, branch protection or the
  # repository (audit r256-5, dissent DISS-C-003).
  if [[ "$command" == *"graphql"* ]] \
     && _match '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*gh[[:space:]]+api[[:space:]]([^;&|]*[[:space:]])?graphql([[:space:]]|$)' \
     && _match_ci '(deleteref|deletebranchprotectionrule|updatebranchprotectionrule|createbranchprotectionrule|deleterepository|updaterepository|deleterelease)[[:space:]]*\('; then
    matched=$(echo "$command" | grep -oiE '(deleteRef|deleteBranchProtectionRule|updateBranchProtectionRule|createBranchProtectionRule|deleteRepository|updateRepository|deleteRelease)[[:space:]]*\(' | head -1)
    # @guard fence:FR-GH-1
    emit_block "FR-GH-1" "gh api graphql ${matched}" "gh api graphql with a mutation that deletes or rewrites refs, branch protection, releases or the repository is refused: use the git/gh porcelain the fence governs, or an operator-run command."
  fi
fi

# pass-8 git-family pre-filter (wraps P2, P2b, P3, P4, P5, P6, P7).
# NECESSITY PROOF (`git`): each of the eight EREs inside this block contains
# the literal run `git` as a mandatory concatenation element (it sits outside
# every alternation and every optional group), so any matching line contains
# "git". "git" absent from $command ⇒ absent from every line ⇒ all eight
# _match calls return 1 ⇒ skipping the block is outcome-identical (P4's
# has_clean_f/has_clean_n are initialized false inside and its block
# condition cannot fire). Interior sections keep their original order;
# only skip-guards were added — no pattern byte changed.
# -----------------------------------------------------------------------------
if [[ "$command" == *"git"* ]]; then  # ── pass-8 git-family pre-filter ──

# -----------------------------------------------------------------------------
# P2 / P2b — git push --force / git push -f  (existing; pattern_id back-fill)
# pass-8 pre-filters: `push` is a mandatory concatenation element of both
# EREs. P2 additionally mandates the literal `--force` (its trailing ($|[^-])
# matches AFTER the complete literal), P2b the literal `-f` — each appears
# in its ERE outside any alternation/optional group.
# -----------------------------------------------------------------------------
if [[ "$command" == *"push"* ]]; then
  if [[ "$command" == *"--force"* ]] \
     && _match '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?git[[:space:]]+push[[:space:]]+.*--force($|[^-])'; then
    matched=$(echo "$command" | grep -oE 'git[[:space:]]+push[[:space:]]+.*--force[^-]?' | head -1)
    # @guard fence:P2
    emit_block "P2" "$matched" "git push --force detected. Use --force-with-lease for safer force push, or push to a feature branch."
  fi
  if [[ "$command" == *"-f"* ]] \
     && _match '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?git[[:space:]]+push[[:space:]]+.*-f($|[[:space:]])'; then
    matched=$(echo "$command" | grep -oE 'git[[:space:]]+push[[:space:]]+.*-f' | head -1)
    # @guard fence:P2b
    emit_block "P2b" "$matched" "git push -f detected. Use --force-with-lease for safer force push, or push to a feature branch."
  fi
fi

# -----------------------------------------------------------------------------
# P3 — git reset --hard  (existing; pattern_id back-fill)
# pass-8 pre-filter: `reset` and `--hard` are both mandatory concatenation
# elements of the ERE (adjacent, joined by [[:space:]]+).
# -----------------------------------------------------------------------------
if [[ "$command" == *"reset"* && "$command" == *"--hard"* ]] \
   && _match '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?git[[:space:]]+reset[[:space:]]+--hard'; then
  matched=$(echo "$command" | grep -oE 'git[[:space:]]+reset[[:space:]]+--hard[^[:space:]]*' | head -1)
  # @guard fence:P3
  emit_block "P3" "$matched" "git reset --hard discards uncommitted work. Use 'git stash' to save changes, or 'git reset --soft' to keep them staged."
fi

# -----------------------------------------------------------------------------
# P4 — git clean -f without -n dry-run  (existing; pattern_id back-fill)
# pass-8 pre-filter: `clean` is a mandatory concatenation element of BOTH
# EREs; when absent, both flags provably stay false and the block condition
# below cannot fire — identical to two failed matches. The final check stays
# outside the guard so the flag semantics are untouched.
# -----------------------------------------------------------------------------
has_clean_f=false
has_clean_n=false
if [[ "$command" == *"clean"* ]]; then
  if _match '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*f'; then
    has_clean_f=true
  fi
  if _match '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*n'; then
    has_clean_n=true
  fi
fi
if [[ "$has_clean_f" == "true" && "$has_clean_n" == "false" ]]; then
  matched=$(echo "$command" | grep -oE 'git[[:space:]]+clean[[:space:]]+-[a-zA-Z]+' | head -1)
  # @guard fence:P4
  emit_block "P4" "$matched" "git clean -f without dry-run. Run 'git clean -nd' first to preview what would be deleted."
fi

# -----------------------------------------------------------------------------
# P5 — git branch -D / force-delete  (FR-1.1)
# Covers grouped -D, --delete --force / --force --delete, split -d -f / -f -d.
# pass-2 \b translation: `--delete\b.*--force` → `--delete([^[:alnum:]_].*)?--force`
# (existence-equivalent: either --force follows immediately — its '-' IS the
# non-word boundary char — or a non-word char then anything then --force.
# The naive consuming form `--delete[^[:alnum:]_].*--force` would MISS
# `--delete--force`; the optional-group form does not). Same for the
# mirrored `--force\b.*--delete`.
# pass-8 pre-filter: `branch` is a mandatory concatenation element; every
# branch of the flags alternation begins with the literal `-`.
# -----------------------------------------------------------------------------
# cycle-125 FR-1 (D-1.4): a branch that is already an ancestor of the base
# holds no unmerged work, so `-D` on it loses nothing. Offline only — one
# local `git merge-base` per named branch, no network (the hook runs under the
# fail-open hook-guard). Squash-merged branches are not ancestors; they go
# through the sanctioned helper `.claude/scripts/git-branch-prune.sh`, which
# may consult `gh` with a timeout. Any doubt (no git, no such branch, a name
# with shell metacharacters, no base ref) keeps the block.
# grimoires/loa/sdd.md D-5.9: a spike/<slug> branch also qualifies once it is
# pushed and its verdict is decided. Pushed: refs/remotes/origin/spike/<slug>
# exists and the local branch is an ancestor of it (nothing local-only is lost;
# the remote-tracking ref is as fresh as the last fetch or push, no network).
# Decided: the decision ledger of the MAIN working tree (the parent of
# `git rev-parse --git-common-dir`, so a linked worktree's checkout is not the
# authority) holds a row with status decided, a transition to decided by
# operator:*, and source grimoires/loa/spikes/<slug>.md. Positive and offline
# (git, yq v4, jq); any failed lookup keeps the block.
_fr11_spike_decided() {
  local slug="$1" common top ledger v
  [[ "$slug" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ && "$slug" != *..* ]] || return 1
  git rev-parse -q --verify "refs/remotes/origin/spike/$slug" >/dev/null 2>&1 || return 1
  git merge-base --is-ancestor "refs/heads/spike/$slug" "refs/remotes/origin/spike/$slug" >/dev/null 2>&1 || return 1
  common=$(git rev-parse --git-common-dir 2>/dev/null) || return 1
  common=$(cd "$common" 2>/dev/null && pwd -P) || return 1
  [[ "${common##*/}" == ".git" ]] || return 1
  top="${common%/.git}"
  [[ -n "$top" && -d "$top" ]] || return 1
  ledger="$top/grimoires/loa/decisions.yaml"
  [[ -f "$ledger" && ! -L "$ledger" ]] || return 1
  command -v yq >/dev/null 2>&1 || return 1
  v=$(yq --version 2>&1 || true)
  [[ "$v" == *mikefarah* && "$v" == *"version v4."* ]] || return 1
  yq -o=json -I0 '.' "$ledger" 2>/dev/null | jq -e --arg src "grimoires/loa/spikes/${slug}.md" '
    any((.decisions // [])[] | objects;
        .status == "decided"
        and (((.source // "") | tostring | split("#")[0]) == $src)
        and ([(.transitions // [])[] | objects | select(.to == "decided") | (.by // "") | tostring | startswith("operator:")] | last == true))
  ' >/dev/null 2>&1
}
_fr11_all_merged() {
  local seg names name base merged tok deleting segs=0
  command -v git >/dev/null 2>&1 || return 1
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  names=""
  # EVERY `git branch` segment of the command (review round 1, H-4): each
  # segment that carries a force-delete flag must name ≥ 1 branch, and every
  # name across all such segments must be merged.
  while IFS= read -r seg; do
    [[ -n "$seg" ]] || continue
    deleting=0
    for tok in ${seg#*branch}; do
      case "$tok" in
        --delete|--force|-d|-f) deleting=1 ;;
        --*) ;;
        -*D*) deleting=1 ;;
      esac
    done
    (( deleting )) || continue
    segs=$((segs + 1))
    local seg_names=""
    for name in ${seg#*branch}; do
      [[ "$name" == -* ]] && continue
      seg_names+="$name "
    done
    [[ -n "$seg_names" ]] || return 1
    names+="$seg_names"
  done < <(printf '%s' "$_cmd_match" | grep -oE 'git[[:space:]]+branch[[:space:]]+[^;&|]*')
  (( segs > 0 )) && [[ -n "$names" ]] || return 1
  for name in $names; do
    [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || return 1
    case "$name" in main|master|develop|trunk) return 1 ;; esac
    git rev-parse -q --verify "refs/heads/$name" >/dev/null 2>&1 || return 1
    # Trust boundary: decisions.yaml is tracked state the operator owns; a forged decided row is an operator-level trust failure, and its consequence is a local delete of a spike branch the predicate has checked is fully pushed.
    if [[ "$name" == spike/* ]] && _fr11_spike_decided "${name#spike/}"; then continue; fi
    merged=0
    for base in origin/main main origin/master master; do
      git rev-parse -q --verify "$base" >/dev/null 2>&1 || continue
      if git merge-base --is-ancestor "$name" "$base" 2>/dev/null; then merged=1; break; fi
    done
    [[ $merged -eq 1 ]] || return 1
  done
  return 0
}
if [[ "$command" == *"branch"* && "$command" == *"-"* ]] \
   && _match '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?git[[:space:]]+branch[[:space:]]+(-[a-zA-Z]*D[a-zA-Z]*|--delete[[:space:]]+--force|--force[[:space:]]+--delete|-d[[:space:]]+-f|-f[[:space:]]+-d|--delete([^[:alnum:]_].*)?--force|--force([^[:alnum:]_].*)?--delete)' \
   && ! _fr11_all_merged; then
  matched=$(echo "$command" | grep -oE 'git[[:space:]]+branch[[:space:]]+[^[:space:]&|;]+([[:space:]]+[^[:space:]&|;]+)?' | head -1)
  # @guard fence:FR-1.1
  emit_block "FR-1.1" "$matched" "git branch -D loses unmerged work. Use 'git branch -d' (lowercase) — it refuses to drop branches with unmerged commits. A branch already merged into main/master is allowed, and so is a spike/<slug> branch that is fully pushed to origin and whose verdict row (source grimoires/loa/spikes/<slug>.md) is decided; for squash-merged branches use .claude/scripts/git-branch-prune.sh."
fi

# -----------------------------------------------------------------------------
# P6 — git stash drop / git stash clear  (FR-1.2)
# Note: git stash pop is NOT included (recoverable from reflog per SDD §5.3).
# pass-2 \b translation: trailing `(drop|clear)\b` at regex end →
# `(drop|clear)($|[^[:alnum:]_])` (word-boundary-after ≡ end-of-line or a
# consumed non-word char; nothing follows in the regex, so consuming is safe).
# pass-8 pre-filter: `stash` is a mandatory concatenation element; the
# mandatory (drop|clear) alternation has exactly two branch literals, so the
# guard tests BOTH — either present ⇒ evaluate the group.
# -----------------------------------------------------------------------------
if [[ "$command" == *"stash"* && ( "$command" == *"drop"* || "$command" == *"clear"* ) ]] \
   && _match '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?git[[:space:]]+stash[[:space:]]+(drop|clear)($|[^[:alnum:]_])'; then
  matched=$(echo "$command" | grep -oE 'git[[:space:]]+stash[[:space:]]+(drop|clear)([[:space:]]+[^[:space:]&|;]+)?' | head -1)
  # @guard fence:FR-1.2
  emit_block "FR-1.2" "$matched" "git stash {drop,clear} permanently destroys stashed work. Run 'git stash list' first; consider 'git stash show' / 'git stash apply' before dropping."
fi

# -----------------------------------------------------------------------------
# P6b — stash output-swallowing (FR-1.2b, cycle-122, issue #555 shapes)
# git stash push/pop/apply with its output truncated (| tail / | head),
# error stream suppressed (2>/dev/null), or exit masked (|| true) hides
# CONFLICT lines and wrong-slot pops — the exact silent-data-loss chain from
# #555 (4 NOTES.md edits lost; recovered only because gc hadn't pruned).
# `[^;&|]*` keeps the swallow-operator in the SAME statement segment as the
# stash call. `\|\|` (masking) vs `\|` (pipe) are distinguished by the
# alternation order + explicit true operand.
# pass-8 pre-filter: `stash` plus one of the swallow literals.
# -----------------------------------------------------------------------------
# @guard fence:FR-1.2b
if [[ "$command" == *"stash"* && ( "$command" == *"tail"* || "$command" == *"head"* || "$command" == *"/dev/null"* || "$command" == *"true"* ) ]] \
   && _match '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?git[[:space:]]+stash[[:space:]]+(push|pop|apply)[^;&|]*(\|[[:space:]]*(tail|head)([[:space:]]|$)|\|\|[[:space:]]*true([[:space:]]*([;&|#]|$))|(&|[0-9]*)>>?[[:space:]]*/dev/null)'; then
  matched=$(echo "$command" | grep -oE 'git[[:space:]]+stash[[:space:]]+(push|pop|apply)[^;&|]*.{0,20}' | head -1)
  emit_block "FR-1.2b" "$matched" "Output-swallowing (pipe-truncate, exit-mask, or ANY /dev/null redirect) around git stash push/pop/apply hides CONFLICT lines and wrong-slot pops (silent data loss, issue #555). Use stash_with_guard from .claude/scripts/stash-safety.sh, or run the stash bare and read its FULL output. Rules: .claude/rules/stash-safety.md"
fi

# -----------------------------------------------------------------------------
# P13 — git tag creation (FR-MERGE-2, cycle-122, C-MERGE-002)
# Manual tag creation bypasses semver-bump.sh conventional-commit parsing and
# can mint wrong versions; the post-merge pipeline owns tags. Listing and
# inspection forms stay allowed: bare `git tag`, -l/--list, -n*, -v/--verify,
# --contains/--points-at/--sort/--merged, and -d/--delete (separately
# recoverable; deletion is not version-minting).
# Creation shapes: first arg is a bare tagname, or a creation flag
# (-a/-s/-f/-u/-m/-F and long forms).
# Sanctioned override (audited): LOA_ALLOW_GIT_TAG=1 in the hook environment
# (operator terminals / release tooling), same posture as FR-SZ's override.
# pass-8 pre-filter: `tag` mandatory.
# -----------------------------------------------------------------------------
if [[ "$command" == *"tag"* ]] \
   && _match '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?git[[:space:]]+tag[[:space:]]+(-[asfumF]|--(annotate|sign|force|local-user|message|file|edit|create-reflog)([=[:space:]]|$)|[^-[:space:]])'; then
  if [[ "${LOA_ALLOW_GIT_TAG:-}" == "1" ]]; then
    if [[ -z "${LOA_GIT_TAG_BYPASS_WARNED:-}" ]]; then
      echo "WARNING: block-destructive-bash: LOA_ALLOW_GIT_TAG=1 — manual git tag guard bypassed this session." >&2
      export LOA_GIT_TAG_BYPASS_WARNED=1
    fi
    # @guard fence:FR-MERGE-2
    jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg cwd "$PWD" --arg replay "${LOA_AUDIT_REPLAY:-}" \
      '{ts: $ts, tool: "Bash", exit_code: 0, cwd: $cwd, hook: "block-destructive-bash", action: "allow-override", pattern_id: "FR-MERGE-2", override: "LOA_ALLOW_GIT_TAG"} + (if $replay == "1" then {replay: true} else {} end)' \
      >> "${LOA_REPO_ROOT:-.}/.run/audit.jsonl" 2>/dev/null || true
  else
    matched=$(echo "$command" | grep -oE 'git[[:space:]]+tag[[:space:]]+[^[:space:]&|;]+([[:space:]]+[^[:space:]&|;]+)?' | head -1)
    # @guard fence:FR-MERGE-2
    emit_block "FR-MERGE-2" "$matched" "Manual tags bypass semver-bump.sh version computation (C-MERGE-002) — the post-merge pipeline owns tag creation. Listing forms (git tag / git tag -l) are allowed. Sanctioned override: LOA_ALLOW_GIT_TAG=1 (audited)."
  fi
fi

# -----------------------------------------------------------------------------
# P7 — git checkout -- <path>  (FR-1.3) — legacy form, overwrites uncommitted
# Refined ERE per SDD §5.4 v1.3: path must NOT start with `-` (so --quiet
# and similar flag-shaped tokens don't trigger).
# pass-8 pre-filter: `checkout` and `--` are both mandatory concatenation
# elements (`--` is the two-char literal between the [[:space:]] runs).
# -----------------------------------------------------------------------------
# cycle-125 FR-1 (D-1.5): restoring a GENERATED file overwrites nothing an
# author typed — build outputs (dist/, build/, coverage/, out/), codegen dirs
# (_generated/, __generated__/, generated/), build info, lockfiles, and any
# path git itself marks `linguist-generated` in .gitattributes. Every operand
# must qualify; anything else keeps the block.
_fr13_all_generated() {
  local seg names name attr segs=0
  names=""
  # EVERY `git checkout --` segment (review round 1, H-4): all operands of
  # all segments must qualify; an operand-less segment is not a proof.
  while IFS= read -r seg; do
    [[ -n "$seg" ]] || continue
    segs=$((segs + 1))
    [[ -n "${seg#*-- }" && "${seg#*-- }" != "$seg" ]] || return 1
    names+="${seg#*-- } "
  done < <(printf '%s' "$_cmd_match" | grep -oE 'git[[:space:]]+checkout[[:space:]]+--[[:space:]]+[^;&|]*')
  (( segs > 0 )) && [[ -n "${names// /}" ]] || return 1
  for name in $names; do
    [[ "$name" == -* ]] && continue
    [[ "$name" =~ ^[A-Za-z0-9._/@+-]+$ ]] || return 1
    [[ "$name" =~ (^|/)\.\.(/|$) ]] && return 1
    if [[ "$name" =~ (^|/)(dist|build|out|coverage|_generated|__generated__|generated)(/|$) ]]; then continue; fi
    if [[ "$name" =~ (\.tsbuildinfo|\.lock|-lock\.(json|yaml|yml))$ ]] \
       || [[ "$name" =~ (^|/)(pnpm-lock\.yaml|package-lock\.json|yarn\.lock|Cargo\.lock|poetry\.lock|uv\.lock|go\.sum|composer\.lock|Gemfile\.lock)$ ]]; then continue; fi
    if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      attr=$(git check-attr linguist-generated -- "$name" 2>/dev/null)
      [[ "$attr" =~ linguist-generated:[[:space:]]*(set|true)$ ]] && continue
    fi
    return 1
  done
  return 0
}
if [[ "$command" == *"checkout"* && "$command" == *"--"* ]] \
   && _match '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?git[[:space:]]+checkout[[:space:]]+--[[:space:]]+[^-][^[:space:]]*' \
   && ! _fr13_all_generated; then
  matched=$(echo "$command" | grep -oE 'git[[:space:]]+checkout[[:space:]]+--[[:space:]]+[^[:space:]&|;]+' | head -1)
  # @guard fence:FR-1.3
  emit_block "FR-1.3" "$matched" "git checkout -- <file> overwrites uncommitted changes irreversibly. Use 'git stash push <file>' to save first, or 'git restore --source=HEAD <file>' (explicit source). Generated paths (dist/, build/, coverage/, _generated/, lockfiles, linguist-generated) are allowed."
fi

fi  # ── end pass-8 git-family pre-filter ──

# -----------------------------------------------------------------------------
# SP-1: spike content never enters another branch (grimoires/loa/sdd.md D-5.4)
# A spike/<slug> branch is a prototype pushed as the pointer for a decision:
# pushed, never merged, no PR. Judged on the carrier-scrubbed line model (a
# commit message or echo that merely mentions spike/x stays allowed).
# Blocked:
#   git merge|rebase|pull|cherry-pick|reset|read-tree|update-ref with a spike
#     ref operand (also main..spike/x, origin/spike/x, "spike/x")
#   git checkout <spike ref> -- <path>, and git checkout <spike ref> <path>
#     (a path copy without --), and git checkout -p|--patch <spike ref> (hunks
#     copied into the working tree, with or without paths)
#   git restore --source[= ]<spike ref> / -s <spike ref>
#   git branch -f|--force|-m|-M|-c|-C|--move|--copy with a spike ref operand
#     (moves or copies a branch onto the spike head, or renames a spike out of
#     the spike/ namespace)
#   git push refspecs: src:dst with a spike ref on either side (spike/x:main,
#     +spike/x:main, origin/spike/x:main, main:spike/x), except the same spike
#     branch on both sides; HEAD:<dst>, @:<dst> and :<dst> while the checkout is
#     on spike/* (one offline git rev-parse), except HEAD:<that same branch>;
#     HEAD here is any spelling of the checkout or its ancestors: HEAD, @,
#     HEAD~N, HEAD^N, @~N and HEAD@{N} in any combination;
#     a force push (--force, -f, --force-with-lease, --force-if-includes) or a
#     +refspec naming a spike ref (P2/P2b already block --force/-f generally)
#   git fetch naming a spike ref on the same line as merge|rebase|cherry-pick|
#     reset of FETCH_HEAD
#   git -c alias.<x>=... / --config-env=alias.<x>=... anywhere in a git call,
#     and git config alias.<x> definitions (get, list and unset forms pass):
#     agents do not define aliases, and an alias hides the verb from this fence
#   gh pr create --head|-H [owner:]spike/<x>, gh pr create with no head while
#     the checkout is on spike/* (one offline git call), and gh api on a
#     .../pulls path with a head= field naming a spike ref
# Allowed: git push [-u|--set-upstream] origin spike/x, git push origin
# spike/x:spike/x, git push origin HEAD on spike/x, git checkout spike/x,
# git checkout -b|-B|--orphan spike/x, git branch spike/x and git branch new
# spike/x (a plain create, the same class as git switch -c new spike/x below),
# and on a spike branch git merge main / git rebase main (the default branch
# flows in).
# Accepted edge: 'git pull origin spike/x' while on spike/x is blocked too
# (it names a spike ref); bare 'git pull' is the supported form there.
# Span rule for the verb patterns: between the verb and the spike ref sit
# whitespace-separated tokens (each may open with a quote) with no backtick,
# comma, quote or separator inside, so the ref must sit in the verb's own shell
# segment; prose naming `git merge FETCH_HEAD` and, later on the line, a spike
# path passes. Each repetition of the span consumes exactly ONE whitespace
# character and then a token that cannot contain whitespace, so a run of spaces
# has a single parse and matching stays linear under bash =~ (glibc regexec).
# Misses (fence, not boundary): git show spike/x:path > file, git diff spike/x |
# git apply, git format-patch main..spike/x then git am (one line or two),
# git archive spike/x | tar -x, git switch -c new spike/x, git worktree add -b new <dir> spike/x,
# git branch new spike/x then a merge of new, git fetch origin spike/x and a
# FETCH_HEAD merge in a later command, an alias defined outside the agent's
# Bash calls (~/.gitconfig edited by hand), gh api --input <file>, and refs
# spelled without the spike/ prefix (a SHA). ICE (run-mode-ice.sh) refuses the
# same merges and PRs inside run mode. The skill grant
# Bash(git push -u origin spike/*) cannot exclude a colon by glob (the * spans
# ':'), so this fence, not the grant, is the control for push refspecs.
# -----------------------------------------------------------------------------
_sp1_git='(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?git([[:space:]]+(-C|-c)[[:space:]]+[^[:space:];&|]+|[[:space:]]+--[a-z-]+(=[^[:space:];&|]+)?)*[[:space:]]+'
_sp1_ref='["'"'"']?([^[:space:];&|"'"'"']*/)?spike/'
# One whitespace character, an optional opening quote, one token (see Span rule).
_sp1_span='([[:space:]]["'"'"']?[^];&|`,"'"'"'[:space:]]*)*'
_sp1_msg="Spike branches are never merged, cherry-picked, copied from, pushed onto another branch or opened as a PR: a spike/<slug> branch is the pointer for a decision. Record the verdict in grimoires/loa/spikes/<slug>.md and its DEC row on the working branch. Allowed: git push -u origin spike/<slug>, git checkout spike/<slug>, and on the spike branch git merge main or git rebase main."
_sp1_alias_msg="Agents do not define git aliases (git -c alias.*, git config alias.*): an alias hides the verb from this fence. Spell the git command out."

# SP-1 judges a whitespace-collapsed copy of the scrubbed command: tabs become
# spaces and every run of spaces one space (pure bash, each pass halves a run).
# Every SP-1 pattern treats a whitespace run as one separator, so the verdict is
# unchanged, and a command padded with thousands of spaces stays linear to match
# (glibc regexec is quadratic in a long run under a leading [[:space:]]*).
_sp1_text="${_cmd_match//$'\t'/ }"
while [[ "$_sp1_text" == *"  "* ]]; do _sp1_text="${_sp1_text//  / }"; done
_sp1_lines=()
while IFS= read -r _sp1_l; do _sp1_lines+=("$_sp1_l"); done <<< "$_sp1_text"

# _sp1_match <ere>: exit 0 iff any collapsed line matches (as _match does).
_sp1_match() {
  local _l
  for _l in "${_sp1_lines[@]}"; do
    [[ "$_l" =~ $1 ]] && return 0
  done
  return 1
}

# Is $1 (quotes stripped) a spike ref: spike/<x>, or a ref path ending in one
# (origin/spike/<x>, refs/heads/spike/<x>, refs/remotes/origin/spike/<x>)?
_sp1_is_spike_ref() {
  local r="${1//[\"\']/}"
  [[ "$r" =~ (^|/)spike/[^/] ]]
}

# A spike ref reduced to its branch name: refs/heads/spike/x, origin/spike/x
# and spike/x all give spike/x.
_sp1_spike_name() {
  local r="${1//[\"\']/}"
  printf 'spike/%s' "${r##*spike/}"
}

# Segments of the scrubbed command for one git verb, from the git word on.
_sp1_segments() {
  printf '%s' "$_sp1_text" | grep -oE "git([[:space:]]+(-C|-c)[[:space:]]+[^[:space:];&|]+|[[:space:]]+--[a-z-]+(=[^[:space:];&|]+)?)*[[:space:]]+$1([[:space:]][^;&|]*)?" || true
}

# Every `git checkout` segment: a spike ref as the first operand followed by
# another operand is a path copy (no create flag in the segment).
_sp1_checkout_copies() {
  local seg tok create n first patch
  local -a toks
  while IFS= read -r seg; do
    [[ -n "$seg" ]] || continue
    read -ra toks <<< "${seg#*checkout}"
    create=0 n=0 first="" patch=0
    for tok in "${toks[@]}"; do
      case "$tok" in
        -b|-B|--orphan|-t|--track|--orphan=*|--track=*) create=1 ;;
        -p|--patch) patch=1 ;;
        -*) ;;
        *) n=$((n + 1)); [[ $n -eq 1 ]] && first="$tok" ;;
      esac
    done
    (( create )) && continue
    # -p/--patch copies hunks from the first operand even with no path after it
    if (( n >= 2 || (patch && n >= 1) )) && [[ "$first" =~ ^${_sp1_ref} ]]; then
      return 0
    fi
  done < <(_sp1_segments checkout)
  return 1
}

# Every `git branch` segment with a force, move or copy flag and a spike ref
# among its operands.
_sp1_branch_moves() {
  local seg tok mover spike
  local -a toks
  while IFS= read -r seg; do
    [[ -n "$seg" ]] || continue
    read -ra toks <<< "${seg#*branch}"
    mover=0 spike=0
    for tok in "${toks[@]}"; do
      case "$tok" in
        --force|--move|--copy) mover=1 ;;
        --*) ;;
        -*[fmMcC]*) mover=1 ;;
        -*) ;;
        *) _sp1_is_spike_ref "$tok" && spike=1 ;;
      esac
    done
    (( mover && spike )) && return 0
  done < <(_sp1_segments branch)
  return 1
}

# Is $1 a spelling of the checked-out commit or an ancestor of it: HEAD, @, HEAD~N,
# HEAD^N, @~N, HEAD@{N} and their combinations (HEAD~0, HEAD^^, @{0}~2)?
_sp1_is_head_src() {
  [[ "$1" =~ ^(HEAD|@)(\{[0-9]+\}|@\{[0-9]+\}|[~^][0-9]*)*$ ]]
}

# Every `git push` segment: judge each refspec (see the header).
_sp1_push_refspec() {
  local seg tok force skip n plus src dst cur="" curset=0
  local -a toks
  while IFS= read -r seg; do
    [[ -n "$seg" ]] || continue
    read -ra toks <<< "${seg#*push}"
    force=0 skip=0 n=0
    for tok in "${toks[@]}"; do
      if (( skip )); then skip=0; continue; fi
      case "$tok" in
        --force|--force=*|--force-with-lease|--force-with-lease=*|--force-if-includes) force=1; continue ;;
        -o|--push-option|--repo|--receive-pack|--exec) skip=1; continue ;;
        --*) continue ;;
        -*f*) force=1; continue ;;
        -*) continue ;;
      esac
      n=$((n + 1))
      (( n == 1 )) && continue   # the remote
      tok="${tok//[\"\']/}"
      plus=0
      if [[ "$tok" == +* ]]; then plus=1; tok="${tok#+}"; fi
      if [[ "$tok" == *:* ]]; then
        src="${tok%%:*}" dst="${tok#*:}"
        # HEAD:<the spike branch checked out> is the spike pushed under its own name
        if _sp1_is_head_src "$src" && _sp1_is_spike_ref "$dst" && (( ! plus && ! force )); then
          if (( ! curset )); then
            cur=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true); curset=1
          fi
          [[ "$cur" == spike/* && "$(_sp1_spike_name "$dst")" == "$cur" ]] && continue
        fi
        if _sp1_is_spike_ref "$src" || _sp1_is_spike_ref "$dst"; then
          # the same spike branch on both sides moves nothing between branches
          if _sp1_is_spike_ref "$src" && _sp1_is_spike_ref "$dst" \
             && [[ "$(_sp1_spike_name "$src")" == "$(_sp1_spike_name "$dst")" ]] \
             && (( ! plus && ! force )); then
            continue
          fi
          return 0
        fi
        if [[ -z "$src" ]] || _sp1_is_head_src "$src"; then
          if (( ! curset )); then
            cur=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true); curset=1
          fi
          if [[ "$cur" == spike/* ]]; then
            [[ -n "$src" && ( "$dst" == "$cur" || "$dst" == "refs/heads/$cur" ) ]] && (( ! plus && ! force )) && continue
            return 0
          fi
        fi
      elif (( plus || force )) && _sp1_is_spike_ref "$tok"; then
        return 0
      fi
    done
  done < <(_sp1_segments push)
  return 1
}

_sp1_re_fetch="${_sp1_git}fetch${_sp1_span}"'[^[:alnum:]_]["'"'"']?spike/'
_sp1_re_fetchhead="${_sp1_git}(merge|rebase|cherry-pick|reset)${_sp1_span}"'[^[:alnum:]_]["'"'"']?FETCH_HEAD'
# A line that fetches a spike ref and merges, rebases, cherry-picks or resets
# FETCH_HEAD.
_sp1_fetch_head() {
  local l
  for l in "${_sp1_lines[@]}"; do
    [[ "$l" =~ $_sp1_re_fetch ]] || continue
    [[ "$l" =~ $_sp1_re_fetchhead ]] && return 0
  done
  return 1
}

# Every `git config` segment that defines an alias (not a get, list or unset).
_sp1_alias_def() {
  local seg tok defines reads n
  local -a toks
  while IFS= read -r seg; do
    [[ -n "$seg" ]] || continue
    read -ra toks <<< "${seg#*config}"
    defines=0 reads=0 n=0
    for tok in "${toks[@]}"; do
      tok="${tok//[\"\']/}"
      case "$tok" in
        --get|--get-all|--get-regexp|--get-urlmatch|-l|--list|--unset|--unset-all|--remove-section|--rename-section) reads=1 ;;
        -*) ;;
        *)
          n=$((n + 1))
          if (( n == 1 )); then
            case "$tok" in get|list|unset|remove-section|rename-section) reads=1 ;; esac
          fi
          [[ "$tok" == alias.* ]] && defines=1 ;;
      esac
    done
    (( defines && ! reads )) && return 0
  done < <(_sp1_segments config)
  return 1
}

if [[ "$command" == *"git"* && "$command" == *"alias."* ]]; then
  if _sp1_match '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?git[[:space:]]([^;&|]*[[:space:]])?(-c[[:space:]]*|--config-env[=[:space:]])["'"'"']?alias\.' \
     || _sp1_alias_def; then
    matched=$(echo "$command" | grep -oE 'git[[:space:]][^;&|]*alias\.[^[:space:];&|]*' | head -1)
    # @guard fence:SP-1
    emit_block "SP-1" "$matched" "$_sp1_alias_msg"
  fi
fi

if [[ "$command" == *"git"* && "$command" == *"push"* ]] \
   && [[ "$command" == *":"* || "$command" == *"spike/"* ]] \
   && _sp1_push_refspec; then
  matched=$(echo "$command" | grep -oE 'git[[:space:]][^;&|]*push[^;&|]*' | head -1)
  # @guard fence:SP-1
  emit_block "SP-1" "$matched" "$_sp1_msg"
fi

if [[ "$command" == *"spike/"* ]]; then
  if [[ "$command" == *"git"* ]] \
     && _sp1_match "${_sp1_git}"'(merge|rebase|pull|cherry-pick|reset|read-tree|update-ref)'"${_sp1_span}"'[^[:alnum:]_]["'"'"']?spike/'; then
    matched=$(echo "$command" | grep -oE 'git[[:space:]].*(merge|rebase|pull|cherry-pick|reset|read-tree|update-ref)[^;&|]*spike/[^[:space:];&|]*' | head -1)
    # @guard fence:SP-1
    emit_block "SP-1" "$matched" "$_sp1_msg"
  fi
  if [[ "$command" == *"git"* && "$command" == *"checkout"* ]] \
     && { _sp1_match "${_sp1_git}"'checkout[[:space:]]([^;&|]*[[:space:]])?'"${_sp1_ref}"'[^;&|]*[[:space:]]--([[:space:]]|$)' \
          || _sp1_checkout_copies; }; then
    matched=$(echo "$command" | grep -oE 'git[[:space:]].*checkout[^;&|]*spike/[^;&|]*' | head -1)
    # @guard fence:SP-1
    emit_block "SP-1" "$matched" "$_sp1_msg"
  fi
  if [[ "$command" == *"git"* && "$command" == *"restore"* ]] \
     && _sp1_match "${_sp1_git}"'restore([[:space:]][^;&|]*)?[[:space:]](--source[=[:space:]]+|-s[[:space:]]*)'"${_sp1_ref}"; then
    matched=$(echo "$command" | grep -oE 'git[[:space:]].*restore[^;&|]*spike/[^[:space:];&|]*' | head -1)
    # @guard fence:SP-1
    emit_block "SP-1" "$matched" "$_sp1_msg"
  fi
  if [[ "$command" == *"git"* && "$command" == *"branch"* ]] && _sp1_branch_moves; then
    matched=$(echo "$command" | grep -oE 'git[[:space:]][^;&|]*branch[^;&|]*spike/[^[:space:];&|]*' | head -1)
    # @guard fence:SP-1
    emit_block "SP-1" "$matched" "$_sp1_msg"
  fi
  if [[ "$command" == *"git"* && "$command" == *"fetch"* && "$command" == *"FETCH_HEAD"* ]] && _sp1_fetch_head; then
    matched=$(echo "$command" | grep -oE 'git[[:space:]][^;&|]*fetch[^;&|]*spike/[^[:space:];&|]*' | head -1)
    # @guard fence:SP-1
    emit_block "SP-1" "$matched" "$_sp1_msg"
  fi
  if [[ "$command" == *"gh"* ]] \
     && _sp1_match '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*gh[[:space:]]+pr[[:space:]]+create([[:space:]][^;&|]*)?[[:space:]](--head[=[:space:]]+|-H[[:space:]]*)["'"'"']?([^[:space:];&|"'"'"']*:)?spike/'; then
    matched=$(echo "$command" | grep -oE 'gh[[:space:]]+pr[[:space:]]+create[^;&|]*spike/[^[:space:];&|]*' | head -1)
    # @guard fence:SP-1
    emit_block "SP-1" "$matched" "$_sp1_msg"
  fi
  if [[ "$command" == *"gh"* && "$command" == *"/pulls"* && "$command" == *"head="* ]] \
     && { _sp1_match '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*gh[[:space:]]+api[[:space:]][^;&|]*/pulls[^;&|]*[^[:alnum:]_]head=["'"'"']?([^[:space:];&|"'"'"']*:)?spike/' \
          || _sp1_match '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*gh[[:space:]]+api[[:space:]][^;&|]*[^[:alnum:]_]head=["'"'"']?([^[:space:];&|"'"'"']*:)?spike/[^;&|]*/pulls'; }; then
    matched=$(echo "$command" | grep -oE 'gh[[:space:]]+api[^;&|]*' | head -1)
    # @guard fence:SP-1
    emit_block "SP-1" "$matched" "$_sp1_msg"
  fi
fi
if [[ "$command" == *"gh"* && "$command" == *"create"* ]] \
   && _sp1_match '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)' \
   && ! _sp1_match '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*gh[[:space:]]+pr[[:space:]]+create[^;&|]*[[:space:]](--head|-H)([=[:space:]]|[^[:space:]])'; then
  _sp1_cur=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  if [[ "$_sp1_cur" == spike/* ]]; then
    # @guard fence:SP-1
    emit_block "SP-1" "gh pr create (on $_sp1_cur)" "$_sp1_msg"
  fi
fi

# -----------------------------------------------------------------------------
# pass-8: one C-locale fold of the whole command for the case-insensitive
# groups (P8, P9, P10). ${command,,} applies the same per-character ASCII
# fold that _match_ci applies per line and grep -i applies under LC_ALL=C;
# folding leaves \n untouched, so a literal absent from this folded whole
# string is absent from every folded line.
# -----------------------------------------------------------------------------
_cmd_lc="${_cmd_match,,}"  # quote-blindness fix: fold the scrub-copy (see above)

# -----------------------------------------------------------------------------
# P8 — DROP DATABASE / DROP TABLE / DROP SCHEMA  (FR-1.4)
# Case-insensitive via -iE. Accepted false-positive: `cat | grep DROP TABLE`
# (read-only inspection of schema files). Documented as known limitation.
# pass-2: -i → _match_ci with lowercased literals; leading/trailing \b →
# `(^|[^[:alnum:]_])`/`($|[^[:alnum:]_])` (leading \b before a word char ≡
# start-of-line or preceded by non-word; trailing \b at regex end ≡
# end-of-line or followed by non-word — consuming forms are existence-
# equivalent since nothing else competes for the boundary char).
# pass-8 pre-filter: folded `drop` is a mandatory concatenation element of
# the folded ERE (the (database|table|schema) alternation is deliberately
# NOT used — `drop` alone is the necessary literal).
# -----------------------------------------------------------------------------
# cycle-125 FR-1 (D-1.3): the DROP / TRUNCATE / DELETE rules guard statements
# that reach a SQL runner. A keyword in a heredoc written to a file, an echo,
# a commit body or a search pattern is text (the dominant false-positive
# class). The precondition is the presence of a runner anywhere in the
# command — psql/mysql/sqlite3/…, ORM and migration CLIs, docker-exec'd
# clients included — so `psql <<SQL`, `psql -c`, `mysql -e` and
# `docker exec db psql …` keep today's matching. Inline interpreter programs
# (`python -c`, `node -e`, `python3 - <<PY`) count as runners too, so a
# driver call inside them keeps today's text match; a driver call in a
# script FILE was never matched and still is not (residual, unchanged).
_sql_runner=0
if [[ "$_cmd_lc" =~ (^|[^[:alnum:]_.-])(psql|pgcli|mysql|mariadb|mysqlsh|sqlite3|sqlcmd|sqlplus|isql|usql|litecli|duckdb|clickhouse|clickhouse-client|cockroach|bq|wrangler|prisma|supabase|drizzle-kit|knex|sequelize|typeorm|flyway|liquibase|dbmate|goose|sqitch|rails|manage\.py|artisan|alembic|dbt|atlas|mongosh|sqlx)([[:space:]]|$) ]] \
   || [[ "$_cmd_lc" =~ (^|[^[:alnum:]_.-])(python[0-9.]*|node|deno|bun|ruby|php|perl)[[:space:]]+(-c|-e|-r|--eval|-)([[:space:]]|$) ]]; then
  _sql_runner=1
fi
if [[ $_sql_runner -eq 1 && "$_cmd_lc" == *"drop"* ]] \
   && _match_ci '(^|[^[:alnum:]_])(drop[[:space:]]+(database|table|schema))($|[^[:alnum:]_])'; then
  matched=$(echo "$command" | grep -oiE '\b(DROP[[:space:]]+(DATABASE|TABLE|SCHEMA))[[:space:]]+[^;]*' | head -1)
  # @guard fence:FR-1.4
  emit_block "FR-1.4" "$matched" "DROP {DATABASE,TABLE,SCHEMA} is irreversible. If this is a migration, run via your migration tool with explicit confirmation; otherwise temporarily disable the hook for the next command only."
fi

# -----------------------------------------------------------------------------
# P9 — TRUNCATE TABLE  (FR-1.5)
# Case-insensitive. SDD §5.6 v1.3: quoted-ident coverage for Postgres
# ("users") + MySQL (`users`) + bare unquoted.
# pass-2: -i → _match_ci (literals lowercased; the ident classes already
# cover both cases so folding the text cannot change their outcome);
# leading \b → (^|[^[:alnum:]_]) as in P8.
# pass-8 pre-filter: folded `truncate` is a mandatory concatenation element
# (the optional table group and the ident alternation share no literal —
# `truncate` alone is the necessary literal).
# -----------------------------------------------------------------------------
if [[ $_sql_runner -eq 1 && "$_cmd_lc" == *"truncate"* ]] \
   && _match_ci '(^|[^[:alnum:]_])truncate[[:space:]]+(table[[:space:]]+)?("[^"]+"|`[^`]+`|[a-zA-Z_][a-zA-Z0-9_]*)'; then
  matched=$(echo "$command" | grep -oiE '\bTRUNCATE[[:space:]]+(TABLE[[:space:]]+)?("[^"]+"|`[^`]+`|[a-zA-Z_][a-zA-Z0-9_]*)' | head -1)
  # @guard fence:FR-1.5
  emit_block "FR-1.5" "$matched" "TRUNCATE wipes the table. Use 'DELETE FROM <table> WHERE ...' for scoped row removal, or run in a transaction with explicit operator approval."
fi

# -----------------------------------------------------------------------------
# P10 — DELETE FROM <table> without WHERE  (FR-1.6)
# Two-pass per SDD §5.7 v1.3: iterate ALL DELETE FROM segments (multi-
# statement bypass closure). For each segment, fail if no WHERE present.
# Quoted-ident extended via the ("[^"]+"|`[^`]+`|...) alternation.
# pass-2: NOT converted — grep -oiE extracts every match per line with the
# ORIGINAL case preserved (the segment text feeds emit_block/audit); bash
# =~ exposes no match offset, so case-preserving multi-match extraction
# cannot be reproduced provably. One grep spawn retained by design.
# pass-8 pre-filter: folded `delete` and `from` are both mandatory
# concatenation elements of the -i pattern (\b is zero-width and does not
# affect literal necessity), so when either is absent the grep provably
# emits nothing → delete_stmts="" → the [[ -n ]] branch was already dead.
# This removes the last unconditional spawn on the benign path.
# delete_stmts is pre-initialized so an inherited environment value can
# never leak into the skipped branch.
# -----------------------------------------------------------------------------
delete_stmts=""
if [[ $_sql_runner -eq 1 && "$_cmd_lc" == *"delete"* && "$_cmd_lc" == *"from"* ]]; then
  # quote-blindness fix (step 3, CRITICAL): P10's raw grep does NOT go through
  # _cmd_lines, so it must read the scrub-copy _cmd_match too — otherwise a
  # DELETE FROM inside a redacted carrier value (e.g. git commit -m '…DELETE
  # FROM users…') stays a false positive while everything else is fixed.
  delete_stmts=$(echo "$_cmd_match" | grep -oiE '\bDELETE[[:space:]]+FROM[[:space:]]+("[^"]+"|`[^`]+`|[a-zA-Z_][a-zA-Z0-9_]*)[^;]*' 2>/dev/null)
fi
if [[ -n "$delete_stmts" ]]; then
  while IFS= read -r delete_stmt; do
    [[ -z "$delete_stmt" ]] && continue
    if ! echo "$delete_stmt" | grep -qiE '\bWHERE\b' 2>/dev/null; then
      # @guard fence:FR-1.6
      emit_block "FR-1.6" "$delete_stmt" "DELETE FROM without WHERE removes all rows. Add a WHERE clause."
    fi
  done <<<"$delete_stmts"
fi

# -----------------------------------------------------------------------------
# pass-8 kubectl pre-filter (wraps P11, P12).
# NECESSITY PROOF (`kubectl` AND `delete`): both are mandatory concatenation
# elements of BOTH EREs below (the optional global-flag block sits between
# them; neither literal is inside it). Either literal absent ⇒ neither group
# can match ⇒ skip. Original evaluation order preserved inside.
# -----------------------------------------------------------------------------
if [[ "$command" == *"kubectl"* && "$command" == *"delete"* ]]; then  # ── pass-8 kubectl pre-filter ──

# -----------------------------------------------------------------------------
# P11 — kubectl delete namespace  (FR-1.7)
# SDD §5.8 v1.3: global-flag placement covered via the
# ([[:space:]]+(-X[[:space:]]+|--X)*) optional-flag-block between kubectl
# and delete. Catches `kubectl --kubeconfig=foo delete ns prod`.
# -----------------------------------------------------------------------------
if _match '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?kubectl([[:space:]]+(-[a-zA-Z]+([[:space:]]+|=)[^[:space:]]+|--[a-zA-Z][a-zA-Z0-9-]*(=[^[:space:]]+|[[:space:]]+[^[:space:]-]+)?))*[[:space:]]+delete[[:space:]]+(ns|namespace|namespaces)[[:space:]]+[a-zA-Z0-9_-]+'; then
  matched=$(echo "$command" | grep -oE 'kubectl[^;&|]*delete[[:space:]]+(ns|namespace|namespaces)[[:space:]]+[a-zA-Z0-9_-]+' | head -1)
  # @guard fence:FR-1.7
  emit_block "FR-1.7" "$matched" "kubectl delete namespace wipes the entire namespace and everything inside it. Use 'kubectl delete -n <ns> -l <selector>' for scoped deletion, or temporarily disable the hook."
fi

# -----------------------------------------------------------------------------
# P12 — kubectl delete --all / -A  (FR-1.8)
# SDD §5.9 v1.3: `[^;&|]*` cross-statement bound (closes SKP-003 unbounded
# `.*`) + global-flag placement coverage. Verb-or-resource MUST appear in
# the same shell statement as the --all/-A token.
# pass-2 \b translation: `--all\b` / `-A\b` sit at the end of their
# alternation branches AND of the whole regex → `($|[^[:alnum:]_])`
# consuming form is existence-equivalent (nothing follows).
# -----------------------------------------------------------------------------
if _match '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?kubectl([[:space:]]+(-[a-zA-Z]+([[:space:]]+|=)[^[:space:]]+|--[a-zA-Z][a-zA-Z0-9-]*(=[^[:space:]]+|[[:space:]]+[^[:space:]-]+)?))*[[:space:]]+delete[[:space:]]+[^[:space:]]+[^;&|]*([[:space:]]--all($|[^[:alnum:]_])|[[:space:]]-A($|[^[:alnum:]_]))'; then
  matched=$(echo "$command" | grep -oE 'kubectl[^;&|]*delete[^;&|]*(--all|-A)' | head -1)
  # @guard fence:FR-1.8
  emit_block "FR-1.8" "$matched" "kubectl delete --all / -A removes all resources in scope. Use label selectors instead: 'kubectl delete <type> -l app=<X>'."
fi

fi  # ── end pass-8 kubectl pre-filter ──

# -----------------------------------------------------------------------------
# FR-SZ — State-Zone executable/lifecycle write guard (sprint-bug-213 / #1044)
# -----------------------------------------------------------------------------
# Blocks DIRECT inline agent writes to the executable / lifecycle-controlled
# subset of the State Zone, which the shipped Bash allow-list (cp/tee/cat/echo/
# python3/bash/sh/ln/dd/tar/sed/...) otherwise permits with no prompt:
#   - .run/cron.d           deferred-execution cron scripts (dir + descendants)
#   - .run/...*.sh          sourced for model routing (incl. merged-model-aliases.sh)
#   - grimoires/loa/skills  skill-approval lifecycle (dir + descendants)
# Companion tool-layer half: the Write/Edit deny rules in .claude/settings.json
# (deny > allow). A Write-only deny without this Bash guard is theater (#1044).
#
# SCOPE (validated): the PreToolUse:Bash hook sees only the agent's OUTER command
# string. A generator invoked as `python3 .../model-overlay-hook.py` or `bash X.sh`
# that writes these paths INTERNALLY is invisible here (the redirect lives inside an
# already-approved subprocess) — so this guard blocks only DIRECT inline writes and
# leaves the legitimate generators frictionless (recon: zero inline callers).
#
# Coverage (sprint-bug-213 iter-2, cross-model dissent CR-1..CR-5): directory
# destinations with or without a trailing slash; option-form destinations
# (-t/--target-directory for the copy family, -C/--directory for tar, -d for unzip);
# tee long-options and non-first operands; grouped/long in-place editor flags
# (-Ei, --in-place); and a trailing shell comment as a statement terminator.
#
# Accepted bypass classes (defense-in-depth fence, NOT a hardened boundary; cf. the
# header section-11 list): post-cd relative writes, variable-indirected targets,
# obfuscated interpreter writes (base64/concat path in -c), a pipe-delimited sed
# in-place edit (the statement-bound stops at the first pipe), git checkout of a
# tracked path, non-allow-listed writers (truncate/sponge/ex/ed already prompt),
# and a trailing comment that merely mentions a protected path. Sanctioned override
# for the skill-audit approve move + operator use: LOA_ALLOW_STATE_ZONE_EXEC_WRITE=1.
#
# pass-2: only the cheap OUTER gate below was converted to _match (it runs on
# every Bash call). The inner write-intent greps fire only when the command
# already mentions a protected path — left as grep because their `\btee\b…`,
# `\bdd\b…[^|;&]*` shapes do not admit a provably-isomorphic consuming \b
# translation (the boundary char can be the first char of the next element).
# pass-8 pre-filter: the outer-gate ERE is a three-branch alternation whose
# branches mandate, respectively, the literals `.run/` (from \.run/…\.sh),
# `.run/cron.d` (⊃ `.run/`), and `grimoires/loa/skills`. The guard tests the
# two distinct covering literals — either present ⇒ evaluate the gate.
# -----------------------------------------------------------------------------
# Path fragments (ERE; substring match also covers absolute / $PWD-prefixed forms).
_sz_pc="[^[:space:]'\";&|#]"                              # one path character
_sz_sh="\\.run/${_sz_pc}*\\.sh"                          # a .sh file anywhere under .run/
_sz_root="(\\.run/cron\\.d|grimoires/loa/skills)"        # protected directory roots
_sz_tgt="(${_sz_sh}|${_sz_root}(/${_sz_pc}*)?)"          # a protected target (file OR dir[/desc])
_sz_file="(${_sz_sh}|${_sz_root}/${_sz_pc}*)"            # a protected descendant FILE
_sz_b="([[:space:]]|['\"]|[;&|#]|\$)"                    # right token boundary (NOT '/')
_sz_end="([[:space:]]+--?[a-zA-Z][a-zA-Z0-9-]*)*[[:space:]]*([;&|#]|\$)"  # end-of-stmt; allows trailing option flags (GNU options-after-operands)
_sz_pre="${_sz_pc}*"                                     # optional leading path prefix (./, abs, $PWD/, repo-root)

if [[ "$command" == *".run/"* || "$command" == *"grimoires/loa/skills"* ]] \
   && _match "(${_sz_sh}|\\.run/cron\\.d|grimoires/loa/skills)"; then
  if [[ "${LOA_ALLOW_STATE_ZONE_EXEC_WRITE:-}" == "1" ]]; then
    # Sanctioned override — allow, warn once, audit the bypass (best-effort).
    if [[ -z "${LOA_SZ_EXEC_WRITE_BYPASS_WARNED:-}" ]]; then
      echo "WARNING: block-destructive-bash: LOA_ALLOW_STATE_ZONE_EXEC_WRITE=1 — State-Zone executable/lifecycle write guard bypassed this session." >&2
      export LOA_SZ_EXEC_WRITE_BYPASS_WARNED=1
    fi
    {
      _sz_redactor="${LOA_REPO_ROOT:-.}/.claude/scripts/lib/log-redactor.sh"
      _sz_cmd=$(printf '%s' "$command" | "$_sz_redactor" 2>/dev/null) || _sz_cmd="[REDACTOR-FAILED]"
      [[ ${#_sz_cmd} -gt 2048 ]] && _sz_cmd="${_sz_cmd:0:2048}[...TRUNCATED]"
      ( umask 077; mkdir -p -- "${LOA_REPO_ROOT:-.}/.run" ) 2>/dev/null || true
      TZ=UTC0 printf -v _sz_ts '%(%Y-%m-%dT%H:%M:%SZ)T' -1
      # @guard fence:FR-SZ
      jq -cn --arg ts "$_sz_ts" --arg cmd "$_sz_cmd" --arg cwd "$PWD" --arg replay "${LOA_AUDIT_REPLAY:-}" \
        '{ts: $ts, tool: "Bash", command: $cmd, exit_code: 0, cwd: $cwd, hook: "block-destructive-bash", action: "bypass", pattern_id: "FR-SZ"} + (if $replay == "1" then {replay: true} else {} end)' \
        >> "${LOA_REPO_ROOT:-.}/.run/audit.jsonl" 2>/dev/null || true
    } 2>/dev/null || true
  else
    # Write-intent tests — first match blocks (emit_block exits 2). Anchored to write
    # operations so read-only references (cat/ls/grep/source/cp-FROM) pass through.

    # SZ-REDIR: redirect (any fd / append / noclobber-override) INTO a protected file.
    if echo "$_cmd_match" | grep -qE "([0-9]*|&)?>>?\\|?[[:space:]]*['\"]?${_sz_pre}${_sz_file}${_sz_b}" 2>/dev/null; then
      matched=$(echo "$_cmd_match" | grep -oE ">>?[[:space:]]*['\"]?${_sz_pre}${_sz_file}" | head -1)
      # @guard fence:FR-SZ-REDIR
      emit_block "FR-SZ-REDIR" "$matched" "Redirect-write to a State-Zone executable/lifecycle path. These are generator/approval-only. Run the owning generator/skill, or set LOA_ALLOW_STATE_ZONE_EXEC_WRITE=1 for an audited override."
    fi

    # SZ-TEE: tee writes ALL its file operands (any position, short or long flags).
    if echo "$_cmd_match" | grep -qE "\\btee\\b[^|;&]*[[:space:]]['\"]?${_sz_pre}${_sz_file}${_sz_b}" 2>/dev/null; then
      matched=$(echo "$_cmd_match" | grep -oE "${_sz_file}" | head -1)
      # @guard fence:FR-SZ-TEE
      emit_block "FR-SZ-TEE" "$matched" "tee-write to a State-Zone executable/lifecycle path. Use the owning generator/skill, or LOA_ALLOW_STATE_ZONE_EXEC_WRITE=1."
    fi

    # SZ-COPY: cp/mv/install/rsync. (a) protected DESTINATION as last operand
    # (end-anchored, so reading a protected file OUT stays allowed); (b) protected
    # directory via -t / --target-directory.
    if echo "$_cmd_match" | grep -qE "\\b(cp|mv|install|rsync)\\b[^|;&]+[[:space:]]['\"]?${_sz_pre}${_sz_tgt}['\"]?${_sz_end}" 2>/dev/null \
       || echo "$_cmd_match" | grep -qE "\\b(cp|mv|install|ln)\\b[^|;&]*[[:space:]](-t|--target-directory)(=|[[:space:]]+)['\"]?${_sz_pre}${_sz_tgt}${_sz_b}" 2>/dev/null; then
      matched=$(echo "$_cmd_match" | grep -oE "${_sz_tgt}" | head -1)
      # @guard fence:FR-SZ-COPY
      emit_block "FR-SZ-COPY" "$matched" "copy/move into a State-Zone executable/lifecycle path. Use the owning generator/skill, or LOA_ALLOW_STATE_ZONE_EXEC_WRITE=1."
    fi

    # SZ-LINK: ln with a protected linkname as last operand (positional dest).
    if echo "$_cmd_match" | grep -qE "\\bln\\b[^|;&]+[[:space:]]['\"]?${_sz_pre}${_sz_tgt}['\"]?${_sz_end}" 2>/dev/null; then
      matched=$(echo "$_cmd_match" | grep -oE "${_sz_tgt}" | head -1)
      # @guard fence:FR-SZ-LINK
      emit_block "FR-SZ-LINK" "$matched" "symlink/hardlink into a State-Zone executable/lifecycle path. Use the owning generator/skill, or LOA_ALLOW_STATE_ZONE_EXEC_WRITE=1."
    fi

    # SZ-DD: dd of=<protected file>.
    if echo "$_cmd_match" | grep -qE "\\bdd\\b[^|;&]*of=['\"]?${_sz_pre}${_sz_file}${_sz_b}" 2>/dev/null; then
      matched=$(echo "$_cmd_match" | grep -oE "of=['\"]?${_sz_pre}${_sz_file}" | head -1)
      # @guard fence:FR-SZ-DD
      emit_block "FR-SZ-DD" "$matched" "dd-write to a State-Zone executable/lifecycle path. Use the owning generator/skill, or LOA_ALLOW_STATE_ZONE_EXEC_WRITE=1."
    fi

    # SZ-INPLACE: sed/perl/awk in-place edit of a protected file. Recognizes grouped
    # short clusters (-Ei) and the long --in-place[=...] form; end-anchors the file
    # operand so a sed EXPRESSION that merely mentions a protected path while editing
    # another file is NOT blocked.
    if echo "$_cmd_match" | grep -qE "\\b(sed|perl|awk|gawk)\\b[^|;&]*[[:space:]](-[a-zA-Z]*i[a-zA-Z.]*|--in-place)(=|[[:space:]]|['\"])[^|;&]*[[:space:]]['\"]?${_sz_pre}${_sz_tgt}['\"]?${_sz_end}" 2>/dev/null; then
      matched=$(echo "$_cmd_match" | grep -oE "${_sz_tgt}['\"]?${_sz_end}" | head -1)
      # @guard fence:FR-SZ-INPLACE
      emit_block "FR-SZ-INPLACE" "$matched" "in-place edit of a State-Zone executable/lifecycle path (tamper with an approved skill or the sourced overlay). Use the owning generator/skill, or LOA_ALLOW_STATE_ZONE_EXEC_WRITE=1."
    fi

    # SZ-EXTRACT: archive extraction INTO a protected dir (tar -C/--directory, unzip -d).
    if echo "$_cmd_match" | grep -qE "\\btar\\b[^|;&]*[[:space:]](-C|--directory)(=|[[:space:]]+)['\"]?${_sz_pre}${_sz_tgt}${_sz_b}" 2>/dev/null \
       || echo "$_cmd_match" | grep -qE "\\bunzip\\b[^|;&]*[[:space:]]-d(=|[[:space:]]+)['\"]?${_sz_pre}${_sz_tgt}${_sz_b}" 2>/dev/null; then
      matched=$(echo "$_cmd_match" | grep -oE "(-C|--directory|-d)(=|[[:space:]]+)['\"]?${_sz_pre}${_sz_tgt}" | head -1)
      # @guard fence:FR-SZ-EXTRACT
      emit_block "FR-SZ-EXTRACT" "$matched" "archive extraction into a State-Zone executable/lifecycle path (drops cron-eligible / lifecycle files). Extract elsewhere, or set LOA_ALLOW_STATE_ZONE_EXEC_WRITE=1."
    fi

    # SZ-INTERP: naive interpreter -c/-e literal write (fence value vs. injected agents;
    # obfuscated/variable-built interpreter writes remain an accepted bypass).
    if echo "$_cmd_match" | grep -qE "\\b(python3?|python|perl|ruby|node|bash|sh)\\b[^|;&]*[[:space:]]-[ce].*(${_sz_sh}|\\.run/cron\\.d|grimoires/loa/skills)" 2>/dev/null \
       && echo "$_cmd_match" | grep -qE "(,[[:space:]]*['\"][wax]|>>?[[:space:]]*['\"]?${_sz_pre}${_sz_file}|write_text|\\.write\\b|O_WRONLY|O_CREAT|write_bytes|copyfile|copy2|shutil.copy)" 2>/dev/null; then
      # @guard fence:FR-SZ-INTERP
      emit_block "FR-SZ-INTERP" "interpreter-inline" "naive interpreter inline write to a State-Zone executable/lifecycle path. Use the owning generator/skill, or LOA_ALLOW_STATE_ZONE_EXEC_WRITE=1. (Obfuscated interpreter writes are an accepted bypass — fence, not boundary.)"
    fi
  fi
fi

# -----------------------------------------------------------------------------
# FR-SZ2 — System-Zone (.claude/) direct Bash writes (cycle-122)
# Closes the single-agent gap: zone-write-guard fences Write/Edit tools, the
# team guards fence teammates, but a plain-shell `echo x > .claude/foo` or
# `sed -i` on a hook passed every wired fence. Same trust posture as
# zone-write-guard: the bounded framework-dev marker
# (.run/zone-guard-authorization.json — scope=framework, RFC3339 expires_at,
# 24h mtime cap; test override via LOA_ZONE_GUARD_AUTH_FILE) authorizes
# upstream self-development sessions, audited per-session. Sanctioned paths
# `.claude/overrides/` and `.claude/cache/` are excluded (they are the
# documented customization/runtime surfaces). LOA_ALLOW_STATE_ZONE_EXEC_WRITE=1
# is honored with the same warn+audit semantics as FR-SZ.
# Shapes: redirect, tee, copy-family dest, sed-in-place, rm. Same accepted
# bypass classes as FR-SZ (fence, not boundary).
# -----------------------------------------------------------------------------
if [[ "$_cmd_match" == *".."* ]]; then
  # traversal-looking command: no exclusions (a path like
  # .claude/overrides/../hooks/x resolves back into protected space)
  _c2_cmd="$_cmd_match"
else
  _c2_cmd="${_cmd_match//.claude\/overrides/.EXCLUDED-OVR}"
  _c2_cmd="${_c2_cmd//.claude\/cache/.EXCLUDED-CACHE}"
fi
if [[ "$_c2_cmd" == *".claude/"* ]]; then
  _c2_file="\\.claude/${_sz_pc}+"
  _c2_tgt="\\.claude(/${_sz_pc}*)?"
  _c2_authorized=""
  # 1) env override (operator terminals) — same var as FR-SZ
  if [[ "${LOA_ALLOW_STATE_ZONE_EXEC_WRITE:-}" == "1" ]]; then
    _c2_authorized="env"
  else
    # 2) bounded framework-dev marker (mirrors zone-write-guard validation)
    _c2_auth_file="${LOA_ZONE_GUARD_AUTH_FILE:-${LOA_REPO_ROOT:-.}/.run/zone-guard-authorization.json}"
    if [[ -f "$_c2_auth_file" ]] && command -v jq >/dev/null 2>&1; then
      _c2_row="$(jq -r 'select(type=="object" and .scope=="framework"
                          and (.reason|type=="string") and ((.reason|length)>0)
                          and (.expires_at|type=="string")
                          and (.expires_at|test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")))
                        | .expires_at' "$_c2_auth_file" 2>/dev/null)" || _c2_row=""
      if [[ -n "$_c2_row" ]]; then
        TZ=UTC0 printf -v _c2_now '%(%Y-%m-%dT%H:%M:%SZ)T' -1
        printf -v _c2_epoch '%(%s)T' -1
        _c2_mtime="$(stat -Lc '%Y' -- "$_c2_auth_file" 2>/dev/null || stat -Lf '%m' -- "$_c2_auth_file" 2>/dev/null || echo 0)"
        if [[ "$_c2_mtime" =~ ^[0-9]+$ ]] && (( _c2_epoch - _c2_mtime <= 86400 )) && [[ "$_c2_now" < "$_c2_row" ]]; then
          _c2_authorized="marker"
        fi
      fi
    fi
  fi
  if [[ -z "$_c2_authorized" ]]; then
    if echo "$_c2_cmd" | grep -qE "([0-9]*|&)?>>?\\|?[[:space:]]*['\"]?${_sz_pre}${_c2_file}${_sz_b}" 2>/dev/null; then
      matched=$(echo "$_c2_cmd" | grep -oE ">>?[[:space:]]*['\"]?${_sz_pre}${_c2_file}" | head -1)
      # @guard fence:FR-SZ2-REDIR
      emit_block "FR-SZ2-REDIR" "$matched" "Direct shell write into .claude/ (System Zone — framework-managed). Use .claude/overrides/ or .loa.config.yaml for customization; upstream framework dev uses the bounded marker (.run/zone-guard-authorization.json) or LOA_ALLOW_STATE_ZONE_EXEC_WRITE=1 (audited)."
    fi
    if echo "$_c2_cmd" | grep -qE "\\btee\\b[^|;&]*[[:space:]]['\"]?${_sz_pre}${_c2_file}${_sz_b}" 2>/dev/null; then
      matched=$(echo "$_c2_cmd" | grep -oE "${_c2_file}" | head -1)
      # @guard fence:FR-SZ2-TEE
      emit_block "FR-SZ2-TEE" "$matched" "tee-write into .claude/ (System Zone). Use overrides/config, the bounded marker, or LOA_ALLOW_STATE_ZONE_EXEC_WRITE=1."
    fi
    if echo "$_c2_cmd" | grep -qE "\\b(cp|mv|install|rsync)\\b[^|;&]+[[:space:]]['\"]?${_sz_pre}${_c2_tgt}['\"]?${_sz_end}" 2>/dev/null \
       || echo "$_c2_cmd" | grep -qE "\\b(cp|mv|install|ln)\\b[^|;&]*[[:space:]](-t|--target-directory)(=|[[:space:]]+)['\"]?${_sz_pre}${_c2_tgt}${_sz_b}" 2>/dev/null; then
      matched=$(echo "$_c2_cmd" | grep -oE "${_c2_tgt}" | head -1)
      # @guard fence:FR-SZ2-COPY
      emit_block "FR-SZ2-COPY" "$matched" "copy/move into .claude/ (System Zone). Use overrides/config, the bounded marker, or LOA_ALLOW_STATE_ZONE_EXEC_WRITE=1."
    fi
    if echo "$_c2_cmd" | grep -qE "\\b(sed|perl)\\b[[:space:]][^|;&]*(-[a-zA-Z]*i[a-zA-Z]*|--in-place(=[^[:space:]]*)?)[^|;&]*[[:space:]]['\"]?${_sz_pre}${_c2_file}['\"]?" 2>/dev/null; then
      matched=$(echo "$_c2_cmd" | grep -oE "${_c2_file}" | head -1)
      # @guard fence:FR-SZ2-INPLACE
      emit_block "FR-SZ2-INPLACE" "$matched" "in-place edit of a .claude/ file (System Zone — hook/skill tamper shape). Use overrides/config, the bounded marker, or LOA_ALLOW_STATE_ZONE_EXEC_WRITE=1."
    fi
    if echo "$_c2_cmd" | grep -qE "\\brm\\b[^|;&]*[[:space:]]['\"]?${_sz_pre}${_c2_file}${_sz_b}" 2>/dev/null; then
      matched=$(echo "$_c2_cmd" | grep -oE "rm\\b[^|;&]*${_c2_file}" | head -1 | cut -c1-80)
      # @guard fence:FR-SZ2-RM
      emit_block "FR-SZ2-RM" "$matched" "rm of a .claude/ path (System Zone). Framework files are managed by mount/update tooling; use the bounded marker or LOA_ALLOW_STATE_ZONE_EXEC_WRITE=1 for upstream dev."
    fi
  elif [[ "$_c2_authorized" == "marker" && -z "${LOA_SZ2_MARKER_NOTED:-}" ]]; then
    export LOA_SZ2_MARKER_NOTED=1
    # @guard fence:FR-SZ2
    jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg cwd "$PWD" --arg replay "${LOA_AUDIT_REPLAY:-}" \
      '{ts: $ts, tool: "Bash", exit_code: 0, cwd: $cwd, hook: "block-destructive-bash", action: "allow-marker", pattern_id: "FR-SZ2"} + (if $replay == "1" then {replay: true} else {} end)' \
      >> "${LOA_REPO_ROOT:-.}/.run/audit.jsonl" 2>/dev/null || true
  fi
fi

# -----------------------------------------------------------------------------
# FR-2 — Context-aware rm -rf (P1 refined)
# SDD §5.1 v1.3: multi-invocation iteration + per-arg classification.
# Replaces the v1.37.0 blanket-block. Block on catastrophic paths; allow
# clearly-bounded subpaths; conservative-block on ambiguous shapes.
#
# Limitations (SDD §5.0.1 / §11):
# - `read -r -a` does NOT shell-parse quotes — paths with embedded spaces
#   get split into multiple tokens, falling into the AMBIGUOUS branch
#   (conservative block, NOT incorrect allow). Acceptable behavior.
# - The ALLOW list now EXCLUDES `./`, `./*`, `./.git`, `./.ssh`, `./.env`
#   (SKP-002 round-3 closure) — these were dangerous shapes that v1.0
#   incorrectly hit the `^\./` allow-prefix.
# - FR-2-REDIR (bd-c117-e, #1177): before segment extraction a scrub removes
#   shell `&`-redirect operators (`2>&1`/`>&2` fd-dups, `&>file`/`&>>file`)
#   from a LOCAL copy of the command, and a per-arg pre-pass below strips the
#   remaining non-`&` redirects (`2>/dev/null`, `>log`, spaced `2> /dev/null`)
#   so none are misclassified as rm operands. The scrub runs FIRST precisely
#   so an `&` cannot truncate rm_segments and hide a catastrophic operand that
#   FOLLOWS the redirect (`rm -rf 2>&1 /` — the `/` would otherwise be lost).
#   `&&` command separators survive the scrub (fd-dup needs `>` before the `&`,
#   `&>` needs `>` after), so multi-statement detection stays intact.
# - C15/cycle-119 panel amendment: `find ROOT ... -exec rm -rf {} [+|\;]`
#   shapes previously misclassified the {} / + PLACEHOLDER tokens (never real
#   paths) as ambiguous rm operands, blocking even a fully safe root (e.g.
#   `find ./build -exec rm -rf {} +`). When an rm segment's only non-flag
#   operands are find-exec placeholders AND that segment is immediately
#   preceded (same statement) by `find ROOT ... -exec`, the FIND ROOT is
#   classified through this SAME ladder instead of the placeholders. A root
#   containing `$` matches none of the ladder's branches (never a bypass —
#   see _re_find_exec_prefix below), so it always falls to AMBIGUOUS, same as
#   today: $-expansion roots are NEVER allowed. Backslash-semicolon
#   (`-exec ... {} \;`) is not covered by the ALLOW path — the segment
#   extraction below already stops at the bare `;` (pre-existing, unrelated
#   to this change), so that shape keeps its prior conservative-block
#   behavior unchanged.
#
# pass-2: gate + per-arg classification tests converted to [[ =~ ]]. The
# per-arg tests match DIRECTLY (no line loop): $unquoted derives from
# `read -r -a` word-splitting, so it can never contain a newline — a
# 1-token string IS grep's single-line input. The rm_segments grep -oE
# multi-match extraction is retained (same rationale as P10).
# pass-8 pre-filter: `rm` is a mandatory concatenation element of the gate
# ERE; every branch of its flags alternation begins with the literal `-`.
# -----------------------------------------------------------------------------
if [[ "$command" == *"rm"* && "$command" == *"-"* ]] \
   && _match '(^|/|;|&&|\||[[:space:]]|\(|`|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?rm[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r|--recursive[[:space:]]+--force|--force[[:space:]]+--recursive|-[a-zA-Z]*r[a-zA-Z]*[[:space:]]+-[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*[[:space:]]+-[a-zA-Z]*r)'; then

  # FR-2-REDIR (bd-c117-e-redirect-1pq8, #1177 item E): scrub shell
  # `&`-redirect operators from a LOCAL copy of the command BEFORE segment
  # extraction. (a) `[0-9]*>&[0-9]*` — N>&M fd-dups (`2>&1`, `>&2`, `>&`);
  # (b) `&>>?[^space]*` — `&>file` / `&>>file` operator+attached target.
  # These are pure shell syntax, never rm operands. Scrubbing first stops the
  # rm_segments `[^;&|)]*` class (below) from truncating a segment at the
  # first bare `&` and thereby dropping a catastrophic operand that FOLLOWS an
  # `&`-redirect (e.g. `rm -rf 2>&1 /`). `&&` separators survive both patterns
  # ((a) needs `>` before the `&`, (b) needs `>` after). cycle-120 C-D3b:
  # derive from $_cmd_match (the quote-blindness scrub-copy), NOT raw $command,
  # so the FR-2 GATE (which tests _cmd_match via _match) and this segment
  # EXTRACTOR read the SAME text — a redacted inert carrier can no longer feed
  # the extractor an rm operand the gate never saw (gate/extractor can't
  # disagree toward ALLOW). $command itself stays intact so emit_block's audit
  # row still records the operator's real text.
  _fr2_cmd=$(printf '%s' "$_cmd_match" | sed -E -e 's/[0-9]*>&[0-9]*/ /g' -e 's/&>>?[^[:space:]]*/ /g')

  # Collect ALL rm invocation segments (one per line).
  rm_segments=$(echo "$_fr2_cmd" | grep -oE '(^|;|&&|\|\||\||[[:space:]]|\(|`|'\''|")[[:space:]]*(sudo[[:space:]]+)?(/[^[:space:]]*/)?rm[[:space:]][^;&|)`]*')

  # pass-2: per-arg EREs in variables (regex-in-variable is the safe [[ =~ ]]
  # form — inline |/(/$ are conditional-command parse hazards). Bytes are
  # identical to the former grep -qE arguments.
  _re_dotdot='(^|/)\.\.(/|$)'
  _re_block_list='^(/|\$HOME|\$\{HOME\}|~|~/|/etc|/usr|/var|/home|\*|\.)$|^(/etc/|/usr/|/var/|/home/|~/|\$HOME/$|\$\{HOME\}/$)'
  # HIDDEN PATHS ARE CONSERVATIVELY BLOCKED (bd-m1o6 fix-forward, 2026-07-12).
  # R-002 originally tried to ALLOW bounded hidden subdirs via a *denylist* of
  # sensitive names (.git .ssh .aws …). An independent security audit proved
  # the denylist leaks: it newly allowed `rm -rf ./.netrc / ./.npmrc /
  # ./.git-credentials / ./.password-store / ./.aws-old`, etc. — every hidden
  # dir NOT enumerated. That is the classic denylist-whack-a-mole failure
  # (see feedback_env_loader_allowlist_lesson / bug #898): a denylist fails
  # UNSAFE (unlisted → allowed → data loss), whereas the allow_list below is
  # an ALLOWLIST that fails SAFE (unlisted → blocked → mere friction). So the
  # exclude/allow regexes are restored to the pre-R-002 bytes — the leading
  # `\.` alternative in _re_allow_exclude blocks ALL `./.hidden` paths — and
  # the S-1 defect (the message recommended a form that didn't work) is fixed
  # in the FR-2 *messages* alone: they now name alternatives that actually
  # work (`trash`, `find … -mindepth 1 -delete`) instead of a bogus form.
  _re_allow_exclude='^\./($|\*|\.|\.git$|\.git/|\.ssh$|\.ssh/|\.env)'
  _re_allow_list='^(\./[^/*.][^*]*|node_modules$|node_modules/|dist$|dist/|build$|build/|target$|target/|\.next$|\.next/|/tmp/.+|/var/tmp/.+|/private/tmp/.+|out$|out/|coverage$|coverage/)'

  # ---------------------------------------------------------------------------
  # cycle-125 FR-1 (D-1.1): four narrow allowances, evaluated ONLY after the
  # ..-escape, catastrophic and exclude checks above have not fired. None of
  # them admits an arbitrary project directory: `rm -rf src` stays AMBIGUOUS
  # and `./src/` remains the explicit spelling (Flatline SKP-002).
  #   1. cache vocabulary by LAST segment at any relative depth
  #      (`packages/web/dist`, `deploy/x/.terraform`); intermediate hidden
  #      segments are refused (`.git/objects`), so is any glob/var/escape char.
  #   2. scratch working directory: the last statement-initial `cd <dir>` in
  #      the text before this rm names a temp root (or the hook's own $PWD is
  #      one) → bare relative visible names are allowed (`cd /tmp && rm -rf x`).
  #   3. $TMPDIR/<suffix> when the hook's REAL $TMPDIR resolves under a temp
  #      root and the command does not assign TMPDIR itself (SKP-004).
  #   4. a variable bound EXACTLY ONCE in the command to `$(mktemp -d …)` or to
  #      a literal that this same ladder allows (`S=/tmp/x; rm -rf "$S/y"`);
  #      a second assignment voids it (`T=$(mktemp -d); T=/; rm -rf "$T"`).
  # Remote payloads (`ssh h 'rm -rf …'`) keep today's scanning (SKP-001).
  # ---------------------------------------------------------------------------
  _fr2_temp_root_re='^/(tmp|var/tmp|private/tmp)(/|$)'     # a cd target: the root itself or below
  _fr2_temp_path_re='^/(tmp|var/tmp|private/tmp)/[^/]'      # an rm operand: strictly below a temp root
  _fr2_temp_glob_re='^/(tmp|var/tmp|private/tmp)/+[*?]+/*$'  # the whole temp root through a glob: block
  _fr2_vocab_re='^(dist|build|out|coverage|target|node_modules|tmp|temp|__pycache__|cdk\.out|\.next|\.turbo|\.terraform|\.terraform\.lock\.hcl|\.venv|venv|\.tox|\.nox|\.pytest_cache|\.mypy_cache|\.ruff_cache|\.parcel-cache|\.npm-cache|\.pnpm-store|[A-Za-z0-9_.+-]+\.egg-info)$'
  _fr2_last_seg=""; _fr2_hidden_mid=0
  # Plain relative path: no leading / ~ $ - , no glob/var/escape/space chars,
  # no . or .. segments. Sets _fr2_last_seg and _fr2_hidden_mid.
  _fr2_plain_relative() {
    local p="${1%/}" seg i n
    local -a segs
    _fr2_last_seg=""; _fr2_hidden_mid=0
    [[ -n "$p" && "$p" != /* && "$p" != -* && "$p" != *'*'* && "$p" != *'?'* && "$p" != *'['* && "$p" != *'$'* && "$p" != *'`'* && "$p" != *'~'* && "$p" != *' '* && "$p" != *'\'* ]] || return 1
    local IFS='/'
    read -r -a segs <<<"$p"
    n=${#segs[@]}
    (( n > 0 )) || return 1
    for ((i = 0; i < n; i++)); do
      seg="${segs[i]}"
      [[ -n "$seg" && "$seg" != "." && "$seg" != ".." ]] || return 1
      [[ "$seg" =~ ^[A-Za-z0-9_.+-]+$ ]] || return 1
      if (( i < n - 1 )) && [[ "$seg" == .* ]]; then _fr2_hidden_mid=1; fi
    done
    _fr2_last_seg="${segs[n-1]}"
    return 0
  }
  # Value of a variable assigned EXACTLY once in the command (env-prefix form
  # `NAME=v cmd` and statement-initial `NAME=v` both count); prints it.
  # Can anything in the command rebind NAME behind the textual check?
  # Flatline SKP-002/003 and review round 1: a binding is trusted only when
  # the command contains no other way to change the name — no eval / read /
  # readarray / mapfile / declare / typeset / local / readonly / unset /
  # source (or statement-initial `.`) / getopts / printf -v anywhere, no
  # `for NAME in` / `select NAME in`, no `${NAME:=` / `${NAME=`, no `NAME+=`,
  # no array element `NAME[`. Any of these → not a proof (return 0 = rebindable).
  _fr2_rebindable() {
    local name="$1"
    # The rebinding builtins count only in COMMAND position — statement start
    # (also after `&&`/`||`/`(`/`{`), optionally behind reserved words
    # (`while read x; do`, `if read x; then`, `! read x`), `command`/`builtin`,
    # or assignment prefixes (`IFS= read -r x`). As an ARGUMENT the word is
    # text: `notes-guard.sh read --file …`, `echo read`, `git log --format=…`
    # never rebind anything (Sprint 4 dogfooding: the framework's own reader
    # was voiding the mktemp proof).
    local cmdpos=$'(^|[;&|(){]|\n|\\|\\||&&)[[:space:]]*((if|then|else|elif|while|until|do|time|!|command|builtin)[[:space:]]+|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
    local rebind_re="${cmdpos}"'(eval|read|readarray|mapfile|declare|typeset|local|readonly|unset|source|getopts|printf[[:space:]]+-v)([[:space:]]|$)'
    local dot_re=$'(^|[;&|(]|\n)[[:space:]]*\\.[[:space:]]'
    [[ "$command" =~ $rebind_re ]] && return 0
    [[ "$command" =~ $dot_re ]] && return 0
    [[ "$command" =~ (^|[^[:alnum:]_])(for|select)[[:space:]]+${name}[[:space:]]+in([[:space:]]|$) ]] && return 0
    [[ "$command" == *"\${${name}:="* || "$command" == *"\${${name}="* ]] && return 0
    [[ "$command" == *"${name}+="* || "$command" == *"${name}["* ]] && return 0
    return 1
  }
  _fr2_var_value() {
    local name="$1" rest="$command" count=0 val="" m after
    # ANSI-C quoting: the newline alternative must be a real newline (a
    # double-quoted "\n" is the letter n — review round 1, H-1).
    local re=$'(^|[;&|(]|\n)[[:space:]]*(export[[:space:]]+)?'"${name}="
    _fr2_rebindable "$name" && return 1
    while [[ "$rest" =~ $re ]]; do
      m="${BASH_REMATCH[0]}"
      count=$((count + 1))
      rest="${rest#*"$m"}"
      val="$rest"
    done
    [[ $count -eq 1 ]] || return 1
    # Audit round 1 (dissent, rejected-on-schema but true): an assignment in
    # command position after a reserved word (`if T=/; then`, `while T=/; do`,
    # `{ T=/; }`, `! T=/`) is a real rebinding the statement-initial regex
    # does not see. Every `NAME=` token anywhere in the command must be that
    # one statement-initial binding; a second occurrence in ANY position
    # (also `$NAME=`, `--opt=NAME=`) voids the proof.
    local tot=0 any_re=$'(^|[^[:alnum:]_])'"${name}="
    rest="$command"
    while [[ "$rest" =~ $any_re ]]; do tot=$((tot + 1)); rest="${rest#*"${BASH_REMATCH[0]}"}"; done
    [[ $tot -eq 1 ]] || return 1
    case "$val" in
      \"\$\(*|\$\(*) # command substitution: keep up to the closing paren; nothing may follow it
        val="${val#\"}"; after="${val#*\)}"; val="${val%%\)*})"
        after="${after#\"}"
        [[ -z "$after" || "$after" =~ ^[[:space:]\;\&\|] ]] || return 1 ;;
      \"*) val="${val#\"}"; val="${val%%\"*}" ;;
      \'*) val="${val#\'}"; val="${val%%\'*}" ;;
      *)   val="${val%%[[:space:];&|]*}" ;;
    esac
    [[ -n "$val" ]] || return 1
    printf '%s' "$val"
  }
  # Is this token an allowed scratch/temp location? (depth guards recursion)
  _fr2_value_allowed() {
    local v="$1" depth="${2:-0}" name suffix val
    v="${v#\"}"; v="${v%\"}"; v="${v#\'}"; v="${v%\'}"
    [[ -n "$v" ]] || return 1
    [[ "$v" =~ $_re_dotdot ]] && return 1
    # Strictly below a temp root is allowed before the catastrophic list sees
    # the `/var/` prefix; a bare temp root (`rm -rf /tmp`) is never allowed.
    [[ "$v" =~ $_fr2_temp_path_re ]] && return 0
    [[ "$v" =~ $_re_block_list ]] && return 1
    # A whole, plain mktemp -d substitution — no `;`, `|`, `&`, redirects or
    # trailing path text inside or after it (`$(mktemp -d >/dev/null; echo /)`
    # and `$(mktemp -d)/../..` are refused; Flatline SKP-002).
    [[ "$v" =~ ^\$\(mktemp[[:space:]]+(-d|--directory)([[:space:]]+(-p[[:space:]]+)?[A-Za-z0-9_./\$\{\}\"-]+)*\)$ ]] && return 0
    if [[ "$v" =~ ^\$\{?TMPDIR\}?(/.*)?$ ]]; then
      suffix="${BASH_REMATCH[1]}"   # capture first: every later =~ clobbers BASH_REMATCH
      # The real TMPDIR is proof only if the command cannot change it
      # (assignment, `+=`, read, unset, … — review round 1, H-2).
      [[ "$command" != *"TMPDIR="* ]] || return 1
      _fr2_rebindable TMPDIR && return 1
      [[ -n "${TMPDIR:-}" && "$TMPDIR" =~ $_fr2_temp_root_re ]] || return 1
      [[ -z "$suffix" || ! "$suffix" =~ $_re_dotdot ]] || return 1
      [[ "$suffix" =~ ^/+[*?]+/*$ ]] && return 1   # `$TMPDIR/*` empties the temp dir (DISS-001)
      return 0
    fi
    if (( depth == 0 )) && [[ "$v" =~ ^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?(/[^\$\`\"\']*)?$ ]]; then
      name="${BASH_REMATCH[1]}"; suffix="${BASH_REMATCH[2]}"
      [[ "$name" != HOME && "$name" != TMPDIR && "$name" != PWD && "$name" != OLDPWD ]] || return 1
      [[ -z "$suffix" || ! "$suffix" =~ $_re_dotdot ]] || return 1
      val=$(_fr2_var_value "$name") || return 1
      _fr2_value_allowed "$val" 1
      return $?
    fi
    return 1
  }
  # Is the working directory scratch for this rm segment? $1 = text before it.
  _fr2_scratch_cwd() {
    local before="$1" rest last="" pre m si=0 tot=0
    local re=$'(^|[;&|(]|\n)[[:space:]]*cd[[:space:]]+([^[:space:];&|)]+)'
    # Review round 1, H-3b: the cwd is unknown once anything other than a
    # statement-initial `cd` may have moved it — pushd/popd/eval/source/exec,
    # an inline shell (`bash -c …`), or a `cd` token that is NOT statement-
    # initial (quoted, nested, after `-c`). Conservative: return 1.
    local void_re=$'(^|[^[:alnum:]_])(pushd|popd|eval|source|exec|chdir)([[:space:]]|$)'
    local shell_c_re=$'(^|[^[:alnum:]_])(ba|z|k|da|fi)?sh[[:space:]]+-[A-Za-z]*c([[:space:]]|$)'
    local dot_re=$'(^|[;&|(]|\n)[[:space:]]*\\.[[:space:]]'
    local any_cd_re=$'(^|[^[:alnum:]_./-])cd[[:space:]]'
    [[ "$before" =~ $void_re || "$before" =~ $shell_c_re || "$before" =~ $dot_re ]] && return 1
    rest="$before"
    while [[ "$rest" =~ $any_cd_re ]]; do tot=$((tot + 1)); rest="${rest#*"${BASH_REMATCH[0]}"}"; done
    rest="$before"
    while [[ "$rest" =~ $re ]]; do
      m="${BASH_REMATCH[0]}"
      pre="${rest%%"$m"*}"
      if _bdb_at_command_start "${before%%"$rest"*}$pre${BASH_REMATCH[1]}"; then
        last="${BASH_REMATCH[2]}"; si=$((si + 1))
      fi
      rest="${rest#*"$m"}"
    done
    (( tot == si )) || return 1
    # Only an explicit `cd` establishes scratch: the hook's own $PWD is not
    # consulted (a project that lives under /tmp — eval sandboxes, CI
    # checkouts — must keep `rm -rf src` blocked; found by the corpus).
    [[ -n "$last" ]] || return 1
    local t="$last"; t="${t#\"}"; t="${t%\"}"; t="${t#\'}"; t="${t%\'}"
    [[ "$t" =~ $_fr2_temp_root_re ]] && return 0
    _fr2_value_allowed "$last"
  }
  # The four allowances for one operand ($1 unquoted, $2 text before the segment).
  _fr2_extra_allow() {
    local u="$1" before="$2"
    if _fr2_plain_relative "$u"; then
      if (( _fr2_hidden_mid == 0 )) && [[ "$_fr2_last_seg" =~ $_fr2_vocab_re ]]; then return 0; fi
      if (( _fr2_hidden_mid == 0 )) && [[ "$_fr2_last_seg" != .* ]] && _fr2_scratch_cwd "$before"; then return 0; fi
    fi
    _fr2_value_allowed "$u"
  }

  # C15/cycle-119: matches the text immediately preceding an rm segment
  # (bounded to the SAME statement, via the identical boundary-alternation
  # style used by every other pattern in this file) when it is a
  # `find <span> -exec` prefix. `$`-anchored: nothing may sit between
  # `-exec` and this rm invocation (sudo / an absolute /path/to/rm are
  # consumed by the rm_segment extraction itself, not this prefix). Group 3
  # is the FULL span between `find` and `-exec`; a token-walk below extracts
  # the start-point roots from it — find accepts MULTIPLE start paths, so a
  # single-token regex capture would classify only the first root and
  # silently allow `find ./build /etc -exec ...` (lead-review catch,
  # cycle-119). Eligibility requires EXACTLY ONE root; zero roots (GNU
  # default `.`, or flags-before-root like `find -L root`) and multi-root
  # shapes stay conservative-blocked.
  _re_find_exec_prefix='(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*(sudo[[:space:]]+)?find[[:space:]]+([^;&|)]*)-exec$'
  # Left-to-right cursor over _fr2_cmd so repeated identical rm segments each
  # resolve against THEIR OWN preceding text, not the first occurrence's.
  _fr2_remaining="$_fr2_cmd"

  # FR-2-REDIR (bd-c117-e-redirect-1pq8, issue #1177 item E): syntactic
  # redirect-token EREs for the rm_args strip loop below. Matched against
  # the RAW token (before quote-stripping), so a genuinely-quoted operand
  # like "2>weird" — which starts with a literal quote char, not a
  # digit/operator — never matches and falls through unchanged to the
  # existing ambiguous path. `&`-forms (`&>`, `&>>`, `N>&M`) need no branch
  # here: the scrub above already removed them from the extraction input, so
  # only non-`&` redirects (`2>/dev/null`, `>log`, spaced `2> /dev/null`)
  # can reach this array.
  _re_redir_bare='^([0-9]*(>>|>|<<<|<<|<))$'
  _re_redir_attached='^([0-9]*(>>|>|<<<|<<|<))[^[:space:]]+$'

  any_block=0
  any_ambiguous=0
  matched_arg=""

  while IFS= read -r rm_segment; do
    [[ -z "$rm_segment" ]] && continue

    # C15/cycle-119: isolate the text preceding THIS occurrence of rm_segment
    # (cursor-advance so a later identical segment doesn't re-match the first
    # occurrence's prefix), then test for a find-exec shape ending right here.
    _seg_prefix="${_fr2_remaining%%"$rm_segment"*}"
    # cycle-125 D-1.1 (review round 1, H-3a): the FULL text before THIS
    # occurrence — consumed text plus this segment's own prefix — so a later
    # identical segment is judged by the `cd` that precedes it, not the first.
    _seg_before="${_fr2_cmd:0:$(( ${#_fr2_cmd} - ${#_fr2_remaining} + ${#_seg_prefix} ))}"
    _fr2_remaining="${_fr2_remaining#*"$rm_segment"}"
    _seg_find_root=""
    if [[ "$_seg_prefix" =~ $_re_find_exec_prefix ]]; then
      # Token-walk the find span: start-point roots are the LEADING tokens up
      # to the first primary/flag/paren token (-*, !, (, ), \-escaped).
      # Exactly one root => eligible; zero or many => _seg_find_root stays
      # empty and the segment falls to the untouched conservative ladder.
      # NESTED-find disqualifier (R3 review catch, cycle-119): in
      # `find <safe> -exec find <dangerous> ... -exec rm ...` the {} paths
      # come from the INNER find's root, which this walk never reaches (it
      # breaks at the first `-exec`). Any `find` token inside the span means
      # the outer root does not govern the deletions => ineligible.
      # SYMLINK-FOLLOW disqualifier (audit catch, cycle-119): -L / -H /
      # -follow make find traverse symlinks, so deletions can escape the
      # classified root through a planted link ({} resolves OUTSIDE the safe
      # tree). GNU find tolerates these after the root, where the leading-
      # flag break below never sees them => scan the whole span.
      read -r -a _find_span_toks <<<"${BASH_REMATCH[3]}"
      _find_root_count=0
      _find_nested=0
      for _ftok in ${_find_span_toks[@]+"${_find_span_toks[@]}"}; do
        [[ "$_ftok" == "find" || "$_ftok" == */find ]] && _find_nested=1
        [[ "$_ftok" == "-L" || "$_ftok" == "-H" || "$_ftok" == "-follow" ]] && _find_nested=1
      done
      for _ftok in ${_find_span_toks[@]+"${_find_span_toks[@]}"}; do
        case "$_ftok" in
          -*|'!'*|'('*|')'*|'\'*) break ;;
          *) _find_root_count=$((_find_root_count + 1)); _seg_find_root="$_ftok" ;;
        esac
      done
      [[ "$_find_root_count" -ne 1 || "$_find_nested" -eq 1 ]] && _seg_find_root=""
    fi

    rm_args_raw="${rm_segment#*rm}"
    # shellcheck disable=SC2086,SC2206 — intentional word-split on rm args
    read -r -a rm_args <<<"$rm_args_raw"

    # FR-2-REDIR: strip shell-redirect tokens before per-arg classification.
    # A bare operator (empty tail, e.g. "2>", ">", "<<") consumes ITSELF
    # plus the NEXT array element (the separate-word target of "2> /dev/null");
    # an attached operator (non-empty tail glued on, e.g. "2>/dev/null",
    # ">log", "2>&1") consumes only itself. A token that does not start
    # with an optional fd-digit run immediately followed by an operator
    # char is untouched — a real operand named "2" (no operator) or a
    # filename with '>' NOT at the token start (e.g. "./build>x", one
    # token because read -a doesn't split on it) is never mistaken for a
    # redirect and falls through to the existing block/allow/ambiguous
    # ladder unchanged.
    rm_args_filtered=()
    _skip_next=0
    for ((_i = 0; _i < ${#rm_args[@]}; _i++)); do
      _tok="${rm_args[_i]}"
      if [[ $_skip_next -eq 1 ]]; then
        _skip_next=0
        continue
      fi
      if [[ "$_tok" =~ $_re_redir_bare ]]; then
        _skip_next=1
        continue
      fi
      if [[ "$_tok" =~ $_re_redir_attached ]]; then
        continue
      fi
      rm_args_filtered+=("$_tok")
    done
    rm_args=(${rm_args_filtered[@]+"${rm_args_filtered[@]}"})

    # C15/cycle-119: this segment is find-exec-governed ONLY when a root was
    # detected AND every non-flag operand of THIS rm invocation is a find-exec
    # placeholder ({}, +, \;, ;) — i.e. the rm has no operand of its own.
    # Any segment with a real operand (find-exec or not) keeps the untouched
    # per-arg ladder below, so this can never suppress a genuine dangerous arg.
    _seg_placeholder_only=0
    if [[ -n "$_seg_find_root" ]]; then
      _seg_placeholder_only=1
      for arg in "${rm_args[@]}"; do
        [[ "$arg" == -* ]] && continue
        case "$arg" in
          '{}'|'+'|'\;'|';') ;;
          *) _seg_placeholder_only=0 ;;
        esac
      done
    fi

    if [[ $_seg_placeholder_only -eq 1 ]]; then
      # Classify the FIND ROOT through the EXACT SAME ladder as any rm operand
      # (never a bypass path — see _re_find_exec_prefix comment: a `$`-bearing
      # root matches none of these branches and falls to AMBIGUOUS, same as
      # every other unrecognized shape).
      unquoted="${_seg_find_root#\'}"; unquoted="${unquoted%\'}"
      unquoted="${unquoted#\"}"; unquoted="${unquoted%\"}"
      if [[ "$unquoted" =~ $_re_dotdot ]]; then
        any_ambiguous=1; matched_arg="$_seg_find_root"
      elif [[ "$unquoted" =~ $_re_block_list ]]; then
        any_block=1; matched_arg="$_seg_find_root"
      elif [[ "$unquoted" =~ $_re_allow_exclude ]]; then
        any_ambiguous=1; matched_arg="$_seg_find_root"
      elif [[ "$unquoted" =~ $_re_allow_list ]]; then
        : # explicit safe relative root — allow this find-exec segment
      else
        any_ambiguous=1; matched_arg="$_seg_find_root"
      fi
    else
      for arg in "${rm_args[@]}"; do
        # Skip flag tokens.
        [[ "$arg" == -* ]] && continue
        # Strip outer balanced quotes for pattern-matching (does NOT shell-parse).
        unquoted="${arg#\'}"; unquoted="${unquoted%\'}"
        unquoted="${unquoted#\"}"; unquoted="${unquoted%\"}"
        # ..-segment escape → conservative block.
        if [[ "$unquoted" =~ $_re_dotdot ]]; then
          any_ambiguous=1; matched_arg="$arg"; continue
        fi
        # cycle-125 D-1.1: strictly below /var/tmp or /private/tmp is a temp
        # path, checked here because the catastrophic list below owns the
        # whole `/var/` prefix; a bare `/var/tmp` still falls through to it.
        # A temp root followed only by a glob (`/tmp/*`, `/tmp//*`) empties the
        # shared temp directory — catastrophic-equivalent (review dissent
        # DISS-001; the pre-sprint `/tmp/.+` allow entry let it through).
        if [[ "$unquoted" =~ $_fr2_temp_glob_re ]]; then
          any_block=1; matched_arg="$arg"; break
        fi
        if [[ "$unquoted" =~ $_fr2_temp_path_re ]]; then
          continue
        fi
        # BLOCK list (catastrophic paths).
        # cycle-114 FR-6: the home-root trailing-slash forms ($HOME/, ${HOME}/,
        # ~/) are catastrophic-equivalent to bare $HOME/~ and must hit BLOCK, not
        # the AMBIGUOUS fallback. A CHILD path (e.g. $HOME/projects, ~/subdir) is
        # NOT matched here and correctly falls through to AMBIGUOUS. Mirrors the
        # Claude Code 2.1.154 $HOME-trailing-slash fix.
        if [[ "$unquoted" =~ $_re_block_list ]]; then
          any_block=1; matched_arg="$arg"; break
        fi
        # ALLOW-EXCLUDE (was bypassing via `./` prefix).
        if [[ "$unquoted" =~ $_re_allow_exclude ]]; then
          any_ambiguous=1; matched_arg="$arg"; continue
        fi
        # ALLOW list (bounded subpaths).
        if [[ "$unquoted" =~ $_re_allow_list ]]; then
          continue
        fi
        # cycle-125 D-1.1: cache vocabulary / scratch cwd / real $TMPDIR /
        # once-bound variable — each positively established, else fall through.
        if _fr2_extra_allow "$unquoted" "$_seg_before"; then
          continue
        fi
        # Ambiguous → conservative block.
        any_ambiguous=1; matched_arg="$arg"
      done
    fi

    [[ $any_block -eq 1 ]] && break
  done <<<"$rm_segments"

  if [[ $any_block -eq 1 ]]; then
    # @guard fence:FR-2-BLOCK
    emit_block "FR-2-BLOCK" "$matched_arg" "rm -rf on catastrophic path '$matched_arg' (system root / home / glob / current-dir) refused. Accepted: an explicit relative VISIBLE subdirectory ('./name/'). Alternatives: 'trash <path>' (recoverable) or 'find <path> -mindepth 1 -delete' (contents only)."
  elif [[ $any_ambiguous -eq 1 ]]; then
    # @guard fence:FR-2-AMBIGUOUS
    emit_block "FR-2-AMBIGUOUS" "$matched_arg" "rm -rf on an unclear path '$matched_arg'. Accepted: explicit relative VISIBLE subdirs ('./name/'), build/cache dirs by name at any depth (dist, build, coverage, node_modules, .venv, .terraform, …), bare names after a statement-initial 'cd /tmp/…', /tmp|/var/tmp paths, \$TMPDIR/<name> with a real temp TMPDIR, and a variable bound once to \$(mktemp -d) or such a path. Hidden paths ('./.name') and dot-roots are conservatively blocked — use 'trash <path>' (recoverable) or 'find <path> -mindepth 1 -delete' (contents only, works on hidden dirs too)."
  fi
  # else: every arg matched the allow list → fall through.
fi

# -----------------------------------------------------------------------------
# FR-NOTES — NOTES.md append gate (cycle-124 FR-10, PRD AC-10.1)
# `>> …grimoires/loa/NOTES.md` is the sanctioned append writer for session
# memory (team-role-guard-write.sh lists NOTES.md as append-only), so it is
# fenced rather than exempted: blocked only while notes-guard.sh check exits 3
# (the file is at/over 200 KiB). Reads, other files, NOTES.md.bak-style
# siblings and `notes-guard.sh rotate` (the escape hatch; it uses mv) never
# match. The size is read from $LOA_GRIMOIRE_DIR/NOTES.md (the configurable
# grimoire dir); a missing file or guard script falls through (allow).
# pass-8 pre-filter: `NOTES.md` mandatory.
# -----------------------------------------------------------------------------
if [[ "$command" == *"NOTES.md"* ]] \
   && _match '>>[[:space:]]*[^;&|]*grimoires/loa/NOTES\.md($|[^A-Za-z0-9._-])'; then
  _notes_guard="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../scripts/notes-guard.sh"
  _notes_file="${LOA_GRIMOIRE_DIR:-${LOA_REPO_ROOT:-.}/grimoires/loa}/NOTES.md"
  if [[ -x "$_notes_guard" && -f "$_notes_file" ]]; then
    _notes_rc=0
    "$_notes_guard" check --file "$_notes_file" >/dev/null 2>&1 || _notes_rc=$?
    if [[ $_notes_rc -eq 3 ]]; then
      matched=$(echo "$command" | grep -oE '>>[[:space:]]*[^;&|]*grimoires/loa/NOTES\.md' | head -1)
      # @guard fence:FR-NOTES
      emit_block "FR-NOTES" "$matched" "grimoires/loa/NOTES.md is at or over 200 KiB — appends are refused until it is rotated. Run .claude/scripts/notes-guard.sh rotate (archives the whole file, keeps Blockers + the latest Session Continuity + the 3 newest Decision Logs) or /compound; shrinking edits and rotate itself are never blocked."
    fi
  fi
fi

# All checks passed — allow execution.
exit 0
