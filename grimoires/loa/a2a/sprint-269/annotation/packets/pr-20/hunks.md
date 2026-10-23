# Hunks — pr-20

The later fix changed 56 region(s) in 16 of the change's 68 file(s). Line numbers are head-side (the code under review). Each entry shows up to 12 head lines before and after the region; `>` marks a head line the fix changed.

## H01 — .claude/data/guard-origins.yaml — insertion after head line 311

Head context (head/.claude/data/guard-origins.yaml, lines 300–323):

~~~~text
   300 |     note: "Log permission requests for prompt analysis (async)"
   301 | 
   302 |   # ---------------------------------------------------------------- fence pattern ids
   303 |   - id: fence:LEGACY
   304 |     kind: fence
   305 |     class: harness
   306 |     status: active
   307 |     origin: {kind: design, ref: "cycle-111 sprint-164 check_and_block back-compat"}
   308 |     knob: none
   309 |     floor: false
   310 |     registrations: []
   311 |     note: "check_and_block back-compat wrapper; no call site invokes it today"
   312 |   - id: fence:P2
   313 |     kind: fence
   314 |     class: harness
   315 |     status: active
   316 |     origin: {kind: cycle, ref: "cycle-011"}
   317 |     knob: none
   318 |     floor: false
   319 |     registrations: []
   320 |     note: "git push --force"
   321 |   - id: fence:P2b
   322 |     kind: fence
   323 |     class: harness
~~~~

The change from head to the fix:

~~~~diff
@@ -311,0 +312,9 @@
+  - id: fence:FR-GH-1
+    kind: fence
+    class: harness
+    status: active
+    origin: {kind: cycle, ref: "cycle-129 sprint-256 audit HIGH-A1 (dissent DISS-C-001)"}
+    knob: none
+    floor: false
+    registrations: []
+    note: "gh api with DELETE, PUT or PATCH against refs, branch protection, tags, releases or the repository: the REST escape hatch of the porcelain forms P2, P5 and SP-1 govern"
~~~~

## H02 — .claude/hooks/safety/block-destructive-bash.sh — head line 190

Head context (head/.claude/hooks/safety/block-destructive-bash.sh, lines 178–202):

~~~~text
   178 | _bdb_hd_op_re='^[0-9]*(<<<|<<-|&>>|<<|>>|>[|]|&&|[|][|]|[|]&|&>|<>|>&[0-9-]*|<&[0-9-]*|;;|;|&|[|]|<|>|[(]|[)])$'
   179 | _bdb_hd_re_dw='^[A-Za-z0-9_.+:@%-]+$'
   180 | _bdb_hd_re_dsq="^'([A-Za-z0-9_.+:@%-]+)'\$"
   181 | _bdb_hd_re_ddq='^"([A-Za-z0-9_.+:@%-]+)"$'
   182 | _bdb_hd_re_dbs='^\\([A-Za-z0-9_.+:@%-]+)$'
   183 | _bdb_hd_re_psq="^'([^']*)'\$"
   184 | _bdb_hd_re_pdq="^\"([^\"\$\`\\\\]*)\"\$"
   185 | _bdb_hd_re_pbare="^[^'\"\$\`\\\\]+\$"
   186 | _bdb_hd_re_ctl=$'[\x01-\x08\x0b-\x1f\x7f]'
   187 | _bdb_hd_re_exflag='^-[A-Za-z]*[cex][A-Za-z]*$'
   188 | _bdb_hd_re_exlong='^--(exec|eval|command|in-?place)'
   189 | _bdb_hd_re_ext='\.(sh|bash|zsh|ksh|csh|fish|py|pyw|rb|pl|pm|js|mjs|cjs|ts|mts|cts|ps1|psm1|php|lua|tcl|command|bat|cmd)$'
>  190 | _bdb_hd_re_sys='(^|/)(\.claude/hooks(/|$)|\.claude/settings[^/]*\.json$|\.git/hooks(/|$)|\.git/config$|\.gitconfig$|\.ssh/rc$|\.config/(fish|zsh|bash|git)/|s?bin/[^/]+$)'
   191 | _bdb_hd_re_rc='(^|/)\.(bashrc|bash_profile|bash_login|bash_logout|profile|zshrc|zshenv|zprofile|zlogin|zlogout|kshrc|mkshrc|cshrc|tcshrc|login|logout|envrc)$'
   192 | _bdb_hd_re_sedp='^(([0-9]+|[$]|/[^/]*/)(,([0-9]+|[$]|/[^/]*/))?)?p$'
   193 | _bdb_hd_re_assign='^[A-Za-z_][A-Za-z0-9_]*='
   194 | _bdb_hd_re_varw='^[$]([{]|[A-Za-z_])'
   195 | _bdb_hd_re_knob='^[[:space:]]+heredoc_classifier:[[:space:]]*["'"'"']?([A-Za-z]+)["'"'"']?[[:space:]]*(#.*)?$'
   196 | 
   197 | # Shells, interpreters and wrappers that run their argument or stdin.
   198 | _bdb_hd_is_interp() {
   199 |   case "$1" in
   200 |     bash|sh|zsh|dash|ksh|mksh|ash|fish|csh|tcsh|busybox|python|python[0-9]*|pypy*|node|nodejs|deno|bun|ruby|irb|perl|php|lua|luajit|tclsh|wish|expect|pwsh|powershell|osascript|Rscript) return 0 ;;
   201 |     eval|source|.|exec|command|builtin|time|awk|gawk|mawk|nawk|make|gmake|m4|ed|ex|vi|vim|nvim|gdb) return 0 ;;
   202 |     sudo|doas|su|runuser|env|xargs|parallel|timeout|nohup|nice|ionice|setsid|stdbuf|chroot|unshare|nsenter|ssh|docker|podman|kubectl|find|watch|script) return 0 ;;
~~~~

The change from head to the fix:

~~~~diff
@@ -190 +190 @@
-_bdb_hd_re_sys='(^|/)(\.claude/hooks(/|$)|\.claude/settings[^/]*\.json$|\.git/hooks(/|$)|\.git/config$|\.gitconfig$|\.ssh/rc$|\.config/(fish|zsh|bash|git)/|s?bin/[^/]+$)'
+_bdb_hd_re_sys='(^|/)(\.claude/hooks(/|$)|\.claude/settings[^/]*\.json$|\.git/hooks(/|$)|\.git/config$|\.gitconfig$|\.ssh/rc$|\.config/(fish|zsh|bash|git)/|s?bin/[^/]+$|\.github/workflows(/|$)|(GNUm|m|M)akefile$|[Jj]ustfile$|package\.json$|pyproject\.toml$|Cargo\.toml$|Rakefile$|Gemfile$|Dockerfile([.][^/]*)?$|\.pre-commit-config\.ya?ml$|\.gitlab-ci\.ya?ml$)'
~~~~

## H03 — .claude/hooks/safety/block-destructive-bash.sh — insertion after head line 550

Head context (head/.claude/hooks/safety/block-destructive-bash.sh, lines 539–562):

~~~~text
   539 |   local s="${1:-}" w guard=0
   540 |   _hd_w="" _hd_rest=""
   541 |   while (( guard < 64 )); do
   542 |     guard=$((guard + 1))
   543 |     s="${s#"${s%%[![:space:]]*}"}"
   544 |     [[ -n "$s" ]] || return
   545 |     case "${s:0:1}" in
   546 |       '('|'{'|'!'|'\'|'"'|"'") s="${s:1}"; continue ;;
   547 |     esac
   548 |     w="${s%%[[:space:]]*}"
   549 |     s="${s:${#w}}"
   550 |     if [[ "$w" =~ $_bdb_hd_re_assign ]]; then continue; fi
   551 |     case "$w" in
   552 |       sudo|doas|command|exec|env|nice|time|nohup|builtin|stdbuf|ionice)
   553 |         while :; do
   554 |           s="${s#"${s%%[![:space:]]*}"}"
   555 |           case "$s" in
   556 |             -S|-S[[:space:]]*|--split-string*) _hd_w="sh"; _hd_rest="$s"; return ;;
   557 |             -[ugnCphUrtTDc]|-[ugnCphUrtTDc][[:space:]]*)
   558 |               s="${s:2}"; s="${s#"${s%%[![:space:]]*}"}"; w="${s%%[[:space:]]*}"; s="${s:${#w}}" ;;
   559 |             -*) w="${s%%[[:space:]]*}"; s="${s:${#w}}" ;;
   560 |             *) break ;;
   561 |           esac
   562 |         done
~~~~

The change from head to the fix:

~~~~diff
@@ -550,0 +551,5 @@
+    # Shell reserved words are transparent prefixes: `if :; then rm …; fi` keeps its rm
+    # segment (audit r256-5, dissent DISS-C-002).
+    case "$w" in
+      if|then|elif|else|do|done|while|until|fi|esac|coproc|function) continue ;;
+    esac
~~~~

## H04 — .claude/hooks/safety/block-destructive-bash.sh — insertion after head line 589

Head context (head/.claude/hooks/safety/block-destructive-bash.sh, lines 578–601):

~~~~text
   578 |   _hd_kept="" _hd_synth="" _hd_full=0
   579 |   for ((k = $1; k <= $2; k++)); do
   580 |     l="${_bdb_hd_L[k]}"
   581 |     [[ "$l" == *'<<'* ]] && _hd_full=1
   582 |     if (( ! $3 )); then
   583 |       case "$l" in *'$('*|*'`'*|*'<('*|*'>('*) _hd_full=1 ;; esac
   584 |     fi
   585 |     t="${l//'&&'/$'\n'}"; t="${t//'||'/$'\n'}"; t="${t//'|'/$'\n'}"; t="${t//';'/$'\n'}"; t="${t//'&'/$'\n'}"
   586 |     while :; do
   587 |       seg="${t%%$'\n'*}"
   588 |       _bdb_hd_segword "$seg"
   589 |       if [[ -n "$_hd_w" ]]; then
   590 |         if [[ "$_hd_w" =~ $_bdb_hd_re_varw ]]; then
   591 |           _hd_full=1
   592 |           _hd_synth="${_hd_synth}rm${_hd_rest}"$'\n'"git${_hd_rest}"$'\n'"kubectl${_hd_rest}"$'\n'
   593 |         elif _bdb_hd_is_destructive "$_hd_w"; then
   594 |           _hd_kept="${_hd_kept}${_hd_w}${_hd_rest}"$'\n'
   595 |         elif _bdb_hd_is_interp "$_hd_w" || _bdb_hd_is_runner "$_hd_w"; then
   596 |           _hd_full=1
   597 |         fi
   598 |       fi
   599 |       [[ "$t" == *$'\n'* ]] || break
   600 |       t="${t#*$'\n'}"
   601 |     done
~~~~

The change from head to the fix:

~~~~diff
@@ -589,0 +595,4 @@
+        # Under a quoted delimiter a backtick is literal text (r256-1): strip it from
+        # the kept segment so the later backtick normalisation cannot turn prose such
+        # as "git merge main; see `git merge spike/x` later" into a substitution.
+        (( $3 )) && _hd_rest="${_hd_rest//\`/}"
~~~~

## H05 — .claude/hooks/safety/block-destructive-bash.sh — head lines 1049–1053

Head context (head/.claude/hooks/safety/block-destructive-bash.sh, lines 1037–1065):

~~~~text
  1037 |     if [[ "$source" =~ ^[[:space:]]*([a-z][a-z0-9_]*)[[:space:]]*= ]]; then
  1038 |       name="${BASH_REMATCH[1]}"
  1039 |       program_re="^[[:space:]]*${name}[[:space:]]*=[[:space:]]*${list_re}([[:space:]]*;[[:space:]]*print\([[:space:]]*${name}[[:space:]]*\))?[[:space:]]*$"
  1040 |     fi
  1041 |     if [[ "$source" =~ $program_re ]]; then
  1042 |       printf '%s' ': literal Python data'
  1043 |       return
  1044 |     fi
  1045 |   fi
  1046 |   printf '%s' "$text"
  1047 | }
  1048 | 
> 1049 | # Heredoc scrub, then quoted-value carriers, then echo/printf (sed).
> 1050 | # The echo scrub must run last: it can otherwise consume a closing quote in
> 1051 | # metadata containing "; echo ..." and make a later live write look quoted.
> 1052 | # (bash loops, each guarded by a cheap literal test so the benign path pays
> 1053 | # nothing beyond the substring check).
  1054 | _cmd_match="$command"
  1055 | if [[ "$_cmd_match" == *"for "* || "$_cmd_match" == *"python"* ]]; then
  1056 |   _cmd_match=$(_bdb_scrub_literal_program "$_cmd_match")
  1057 | fi
  1058 | # cycle-129 FR-6: with destructive_command_guard.heredoc_classifier on (the
  1059 | # default) the fail-closed consumer classifier above replaces the #1245 scrub,
  1060 | # which survives unchanged as its special case and as the knob-off path.
  1061 | if [[ "$_cmd_match" == *"<<"* ]]; then
  1062 |   if _bdb_heredoc_knob_on; then
  1063 |     _cmd_match=$(_bdb_heredoc_scrub "$_cmd_match")
  1064 |   else
  1065 |     _cmd_match=$(_bdb_scrub_cat_heredoc "$_cmd_match")
~~~~

The change from head to the fix:

~~~~diff
@@ -1049,5 +1058,110 @@
-# Heredoc scrub, then quoted-value carriers, then echo/printf (sed).
-# The echo scrub must run last: it can otherwise consume a closing quote in
-# metadata containing "; echo ..." and make a later live write look quoted.
-# (bash loops, each guarded by a cheap literal test so the benign path pays
-# nothing beyond the substring check).
+# -----------------------------------------------------------------------------
+# cycle-129 r256-1 (sprint-256 review HIGH-1): a backtick pair outside single
+# quotes is a command substitution exactly like `$( … )` — in plain text, inside
+# double quotes, in an assignment and in an unquoted heredoc body — but every
+# rule anchors on `(`, `;`, `&&`, `|`, whitespace or a quote and none on a
+# backtick, so `echo "see \`git push --force origin main\`"` matched nothing
+# while its `$( )` twin blocked (identical on main 864069f2). Normalise before
+# the rules run: the 1st, 3rd, … backtick outside single quotes becomes `$(`,
+# the 2nd, 4th, … becomes `)`; a backslash escapes the next character outside
+# single quotes (an escaped backtick stays literal); inside single quotes
+# nothing changes. Kept segments of a quoted-delimiter heredoc body have their
+# literal backticks stripped by _bdb_hd_scan_body before this runs. Fast path
+# (no single quote, no backslash in the text): alternate by position; the
+# char loop runs only when quoting has to be tracked. Costs one substring test
+# on the common path.
+# -----------------------------------------------------------------------------
+# Heredoc bodies are raw text (no shell quoting applies inside them): under an
+# unquoted delimiter every backtick is a substitution, under a quoted one every
+# backtick is literal — so the normaliser walks the command line by line, uses
+# _bdb_hd_header to find each heredoc's delimiter and quoting, and applies the
+# body rule to body lines and shell-quote tracking (_bt_q) to the rest. If the
+# shell text's quotes do not balance at the end (an apostrophe in prose, an
+# unreadable header, two heredocs on one line) the whole shell text is redone
+# with quoting ignored: fail closed, never literal by accident.
+# _bdb_bt_alt_line <line>  → _bt_out: plain alternation (state _bt_open)
+# _bdb_bt_shell_line <line> → _bt_out: alternation outside single quotes
+_bt_out="" _bt_open=0 _bt_q="" _bt_force=0
+_bdb_bt_alt_line() {
+  local s="${1:-}" i n ch
+  _bt_out=""
+  [[ "$s" == *'`'* ]] || { _bt_out="$s"; return; }
+  n=${#s}
+  for ((i = 0; i < n; i++)); do
+    ch="${s:i:1}"
+    if [[ "$ch" == '\' ]]; then
+      _bt_out+="$ch"; if (( i + 1 < n )); then i=$((i + 1)); _bt_out+="${s:i:1}"; fi; continue
+    fi
+    if [[ "$ch" == '`' ]]; then
+      if (( _bt_open )); then _bt_out+=')'; _bt_open=0; else _bt_out+='$('; _bt_open=1; fi
+      continue
+    fi
+    _bt_out+="$ch"
+  done
+}
+_bdb_bt_shell_line() {
+  local s="${1:-}" i n ch
+  if (( _bt_force )); then _bdb_bt_alt_line "$s"; return; fi
+  if [[ "$s" != *'`'* && "$s" != *"'"* && "$s" != *'"'* && "$s" != *'\'* ]]; then _bt_out="$s"; return; fi
+  _bt_out=""
+  n=${#s}
+  for ((i = 0; i < n; i++)); do
+    ch="${s:i:1}"
+    if [[ "$_bt_q" == "'" ]]; then
+      [[ "$ch" == "'" ]] && _bt_q=""
+      _bt_out+="$ch"; continue
+    fi
+    if [[ "$ch" == '\' ]]; then
+      _bt_out+="$ch"; if (( i + 1 < n )); then i=$((i + 1)); _bt_out+="${s:i:1}"; fi; continue
+    fi
+    if [[ "$ch" == '`' ]]; then
+      if (( _bt_open )); then _bt_out+=')'; _bt_open=0; else _bt_out+='$('; _bt_open=1; fi
+      continue
+    fi
+    if [[ -z "$_bt_q" && "$ch" == "'" ]]; then _bt_q="'"
+    elif [[ "$ch" == '"' ]]; then
+      if [[ "$_bt_q" == '"' ]]; then _bt_q=""; else _bt_q='"'; fi
+    fi
+    _bt_out+="$ch"
+  done
+}
+_bdb_backtick_norm() {
+  local s="${1:-}"
+  [[ "$s" == *'`'* ]] || { printf '%s' "$s"; return; }
+  local -a L
+  local l n i out="" body=0 delim="" quoted=0 tabs=0 d pass
+  L=()
+  while IFS= read -r l || [[ -n "$l" ]]; do L[${#L[@]}]="$l"; done <<< "$s"
+  n=${#L[@]}
+  for pass in 1 2; do
+    out="" body=0 _bt_open=0 _bt_q="" _bt_force=0
+    (( pass == 2 )) && _bt_force=1
+    for ((i = 0; i < n; i++)); do
+      l="${L[i]}"
+      if (( body )); then
+        d="$l"
+        if (( tabs )); then while [[ "$d" == $'\t'* ]]; do d="${d#$'\t'}"; done; fi
+        if [[ "$d" == "$delim" ]]; then body=0; _bt_open=0; out+="$l"$'\n'; continue; fi
+        if (( quoted )); then out+="$l"$'\n'; else _bdb_bt_alt_line "$l"; out+="$_bt_out"$'\n'; fi
+        continue
+      fi
+      _bdb_bt_shell_line "$l"; out+="$_bt_out"$'\n'
+      if [[ "$l" == *'<<'* ]]; then
+        _bdb_hd_header "$l"
+        if (( _hd_ops == 1 )); then body=1; delim="$_hd_delim"; quoted=$_hd_quoted; tabs=$_hd_tabs; _bt_open=0
+        elif (( _hd_ops != 0 )); then _bt_force=1   # unreadable header or several heredocs: fail closed from here
+        fi
+      fi
+    done
+    [[ -z "$_bt_q" ]] && break          # balanced quotes: done; else pass 2 ignores quoting
+  done
+  out="${out%$'\n'}"
+  [[ "$s" == *$'\n' ]] && out+=$'\n'
+  printf '%s' "$out"
+}
+
+# Heredoc scrub, then backtick normalisation, then quoted-value carriers, then
+# echo/printf (sed). The echo scrub must run last: it can otherwise consume a
+# closing quote in metadata containing "; echo ..." and make a later live write
+# look quoted. (bash loops, each guarded by a cheap literal test so the benign
+# path pays nothing beyond the substring check).
~~~~

## H06 — .claude/hooks/safety/block-destructive-bash.sh — insertion after head line 1067

Head context (head/.claude/hooks/safety/block-destructive-bash.sh, lines 1056–1079):

~~~~text
  1056 |   _cmd_match=$(_bdb_scrub_literal_program "$_cmd_match")
  1057 | fi
  1058 | # cycle-129 FR-6: with destructive_command_guard.heredoc_classifier on (the
  1059 | # default) the fail-closed consumer classifier above replaces the #1245 scrub,
  1060 | # which survives unchanged as its special case and as the knob-off path.
  1061 | if [[ "$_cmd_match" == *"<<"* ]]; then
  1062 |   if _bdb_heredoc_knob_on; then
  1063 |     _cmd_match=$(_bdb_heredoc_scrub "$_cmd_match")
  1064 |   else
  1065 |     _cmd_match=$(_bdb_scrub_cat_heredoc "$_cmd_match")
  1066 |   fi
  1067 | fi
  1068 | [[ "$_cmd_match" == *"git"* ]] && _cmd_match=$(_bdb_scrub "$_bdb_re_git" "$_cmd_match")
  1069 | if [[ "$_cmd_match" == *"br "* || "$_cmd_match" == *"bd "* ]]; then
  1070 |   _cmd_match=$(_bdb_scrub "$_bdb_re_brbd" "$_cmd_match")
  1071 | fi
  1072 | [[ "$_cmd_match" == *"gh "* ]] && _cmd_match=$(_bdb_scrub "$_bdb_re_gh" "$_cmd_match")
  1073 | if [[ "$_cmd_match" == *grep* || "$_cmd_match" == *"rg "* || "$_cmd_match" == *"ag "* || "$_cmd_match" == *"ack "* ]]; then
  1074 |   _cmd_match=$(_bdb_scrub "$_bdb_re_grep" "$_cmd_match")   # cycle-125 D-1.7
  1075 | fi
  1076 | _cmd_match=$(printf '%s' "$_cmd_match" | sed -E -e "$_bdb_sed_echo" 2>/dev/null) || _cmd_match="$command"
  1077 | # Fail-safe: an empty scrub on a non-empty command → fall back to RAW (stricter
  1078 | # matching), never to an empty scrub that would silence every pattern.
  1079 | [[ -z "$_cmd_match" ]] && _cmd_match="$command"
~~~~

The change from head to the fix:

~~~~diff
@@ -1067,0 +1182,2 @@
+# cycle-129 r256-1: backtick substitutions take the `$( )` form the rules anchor on
+[[ "$_cmd_match" == *'`'* ]] && _cmd_match=$(_bdb_backtick_norm "$_cmd_match")
~~~~

## H07 — .claude/hooks/safety/block-destructive-bash.sh — insertion after head line 1206

Head context (head/.claude/hooks/safety/block-destructive-bash.sh, lines 1195–1218):

~~~~text
  1195 |     local matched
  1196 |     matched=$(echo "$command" | grep -oE "$pattern" | head -1)
  1197 |     # @guard fence:LEGACY
  1198 |     emit_block "LEGACY" "$matched" "$message"
  1199 |   fi
  1200 | }
  1201 | 
  1202 | # =============================================================================
  1203 | # Pattern dispatch — SDD §6.2 order: high-frequency-first / FR-2 last.
  1204 | # =============================================================================
  1205 | 
  1206 | # -----------------------------------------------------------------------------
  1207 | # pass-8 git-family pre-filter (wraps P2, P2b, P3, P4, P5, P6, P7).
  1208 | # NECESSITY PROOF (`git`): each of the eight EREs inside this block contains
  1209 | # the literal run `git` as a mandatory concatenation element (it sits outside
  1210 | # every alternation and every optional group), so any matching line contains
  1211 | # "git". "git" absent from $command ⇒ absent from every line ⇒ all eight
  1212 | # _match calls return 1 ⇒ skipping the block is outcome-identical (P4's
  1213 | # has_clean_f/has_clean_n are initialized false inside and its block
  1214 | # condition cannot fire). Interior sections keep their original order;
  1215 | # only skip-guards were added — no pattern byte changed.
  1216 | # -----------------------------------------------------------------------------
  1217 | if [[ "$command" == *"git"* ]]; then  # ── pass-8 git-family pre-filter ──
  1218 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -1206,0 +1323,34 @@
+# -----------------------------------------------------------------------------
+# FR-GH-1 — gh api with a destructive method (DELETE, PUT, PATCH; `-X`, `-XDELETE`,
+# `--method`, `--method=`) against refs, branch protection, tags, releases or the
+# repository itself (cycle-129 sprint-256 audit HIGH-A1). The porcelain twins are
+# governed by P2 (force push), P5 (branch force-delete) and SP-1 (spike pushes);
+# the REST escape hatch was not. GET, POST and PATCH on issues or pulls stay allowed.
+# Judged on the carrier-scrubbed command: the gh scrub redacts --body/--title
+# values only, so the path and the method remain visible. Placed OUTSIDE the
+# git-family pre-filter below: a gh api call need not contain the word git.
+# -----------------------------------------------------------------------------
+if [[ "$command" == *"gh"* && "$command" == *"api"* ]]; then
+  # REST form: a destructive method — literal DELETE|PUT|PATCH, or a NON-literal value
+  # (`-X "$M"`, `--method=$m`), which cannot be judged and is treated as destructive —
+  # against a protected path. The path may carry an optional https://HOST(/api/v3)
+  # prefix or a leading slash (audit r256-5, dissent DISS-C-003).
+  _ghapi_path='(https?://[^/[:space:];&|]+(/api/v3)?)?/?repos/[^/[:space:];&|]+/[^/[:space:];&|]+'
+  if { _match '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*gh[[:space:]]+api[[:space:]]([^;&|]*[[:space:]])?(-X|--method)[=[:space:]]*["'"'"']?(DELETE|PUT|PATCH)' \
+       || _match '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*gh[[:space:]]+api[[:space:]]([^;&|]*[[:space:]])?(-X|--method)[=[:space:]]*["'"'"']?[$]'; } \
+     && _match 'gh[[:space:]]+api[[:space:]][^;&|]*'"${_ghapi_path}"'(/git/refs/|/git/tags/|/branches/[^/[:space:];&|]+/protection|/releases(/|["'"'"'[:space:];&|]|$)|/tags(/|["'"'"'[:space:];&|]|$)|(["'"'"'[:space:];&|]|$))'; then
+    matched=$(echo "$command" | grep -oE 'gh[[:space:]]+api[^;&|]*' | head -1)
+    # @guard fence:FR-GH-1
+    emit_block "FR-GH-1" "$matched" "gh api with DELETE, PUT or PATCH (or a method the fence cannot read) on refs, branch protection, tags, releases or the repository is refused: use the git/gh porcelain the fence governs, or an operator-run command."
+  fi
+  # GraphQL form: the mutations that delete or rewrite refs, branch protection or the
+  # repository (audit r256-5, dissent DISS-C-003).
+  if [[ "$command" == *"graphql"* ]] \
+     && _match '(^|/|;|&&|\||[[:space:]]|\(|'"'"'|")[[:space:]]*gh[[:space:]]+api[[:space:]]([^;&|]*[[:space:]])?graphql([[:space:]]|$)' \
+     && _match_ci '(deleteref|deletebranchprotectionrule|updatebranchprotectionrule|createbranchprotectionrule|deleterepository|updaterepository|deleterelease)[[:space:]]*\('; then
+    matched=$(echo "$command" | grep -oiE '(deleteRef|deleteBranchProtectionRule|updateBranchProtectionRule|createBranchProtectionRule|deleteRepository|updateRepository|deleteRelease)[[:space:]]*\(' | head -1)
+    # @guard fence:FR-GH-1
+    emit_block "FR-GH-1" "gh api graphql ${matched}" "gh api graphql with a mutation that deletes or rewrites refs, branch protection, releases or the repository is refused: use the git/gh porcelain the fence governs, or an operator-run command."
+  fi
+fi
+
~~~~

## H08 — .claude/loa/reference/hooks-reference.md — head line 216

Head context (head/.claude/loa/reference/hooks-reference.md, lines 204–228):

~~~~text
   204 | <!-- guard-register:end -->
   205 | 
   206 | Not registered by default: `safety/stop-input-probe.sh` (Stop, DIAGNOSTIC) is gated by `LOA_STOP_INPUT_PROBE=1` and dumps raw Stop input to `.run/stop-input-probe.jsonl` for one cap-hitting session; it is never in `settings.hooks.json`.
   207 | 
   208 | ## Decision surfaces (cycle-128)
   209 | 
   210 | Hooks, fence rules and gates added for the decision ledger, `/chart` and spikes (FR-3, FR-4, FR-5, FR-8). Each is a fence, not a boundary; the accepted bypasses are listed per row.
   211 | 
   212 | | Surface | Where | What it does | Config / override | Accepted bypasses | Tests |
   213 | |---------|-------|--------------|-------------------|-------------------|-------|
   214 | | SessionStart decisions surface | `.claude/hooks/session-start/loa-decisions-surface.sh` (through `hook-guard.sh`) | Prints up to ten `proposed`, then `open`, rows of `grimoires/loa/decisions.yaml` (id, status, summary) so the operator sees what awaits `/decisions confirm`; adds one notice when `.run/unattended.json` belongs to another session or is older than the TTL. Exits 0 on every path. | `decisions.surface_at_session_start` (default `false`); `decisions.unattended_marker_ttl_hours` (default 24) | Silent without Mike Farah yq v4 or without the L6 sanitizer. Summaries are agent-written and untrusted: control characters (C0, C1, U+2028/9) are stripped, angle brackets replaced, each capped at 100 characters, and the block wrapped by `sanitize_for_session_start L6 … --max-chars 2000`. | `tests/unit/loa-decisions-surface.bats` |
   215 | | ICE spike rule | `.claude/scripts/run-mode-ice.sh` | `is-spike <branch>` (true for `spike/<x>` and remote or full refs ending in one). `merge [source]` stays blocked except on a spike head, where only the default branch (`main`/`master`) may come in, with `--ff` so `merge.ff=only` cannot refuse a diverged spike; a conflict returns git's exit code and names the way out. A spike source is refused. `pr-create` refuses a spike head. | none | Applies inside run mode only; outside it, fence rule SP-1 is the control. | `tests/unit/run-mode-ice.bats` |
>  216 | | Fence rule SP-1 | `.claude/hooks/safety/block-destructive-bash.sh` | Spike content never enters another branch: merge, rebase, pull, cherry-pick, reset, read-tree and update-ref with a spike ref operand; checkout or restore of a path from a spike; branch force/move/copy with a spike ref; push refspecs carrying a spike ref to another branch, or HEAD to another branch while on a spike; a FETCH_HEAD merge after fetching a spike on the same line; git alias definitions; and PRs from a spike head (`gh pr create`, `gh api` on a pulls path). Pushes, checkouts and default-branch merges into a spike stay allowed. Judged on the carrier-scrubbed, whitespace-collapsed command. | none | Listed in the rule's header comment: `git show spike/x:path >` a file, `git diff spike/x` piped to `git apply`, `git switch -c new spike/x`, `git worktree add -b new <dir> spike/x`, a spike branched under a new name then merged, a fetch and a FETCH_HEAD merge in separate commands, an alias defined outside the agent's Bash calls, `gh api --input <file>`, and a spike spelled as a SHA. The usual fence classes also apply (subshells, `eval`, newlines). Prose that names a spike merge inside a heredoc body now allows when the heredoc's consumer is non-executing (cycle-129 FR-6 classifier, corpus B79–B83); a body line that *begins* with the verb is still scanned as a command (D140). | `tests/unit/block-destructive-bash.bats`, corpus `tests/fixtures/fence-corpus/` |
   217 | | FR-1.1 decided-spike unlock | `.claude/hooks/safety/block-destructive-bash.sh` (`_fr11_spike_decided`) | `git branch -D spike/<slug>` passes only when `refs/remotes/origin/spike/<slug>` exists with the local branch an ancestor of it, and the MAIN working tree's ledger holds a `decided` row with a transition to decided by `operator:*` and source `grimoires/loa/spikes/<slug>.md`. Offline (git, yq v4, jq); any failed lookup keeps the block. | none | Trusts the tracked ledger as operator-owned state: a forged operator row lets an agent delete a local branch that is already pushed, and nothing else. The remote-tracking ref is only as fresh as the last fetch or push. | `tests/unit/block-destructive-bash.bats` |
   218 | | `/chart` interactive-only gate | `.claude/scripts/chart-guard.sh`, the first step of the `charting-decisions` skill | Refuses (exit 1) when `dec-write-lib.sh context` says unattended (a fresh unattended marker, a RUNNING run state, `LOA_UNATTENDED=1`, `LOA_FLATLINE_MODE=autonomous`, or an autonomous PRD Status line) or when `br` is missing; a context it cannot read counts as unattended. `--close-consumed` allows the one unattended operation. | none | A skill step, not a hook: a session that skips the step is caught by `chart-ticket.sh`, whose every write subcommand repeats the context check (`--dry-run` and `close --consumed-by` exempt). An unattended session with none of the signals reads as interactive. | `tests/unit/charting-decisions.bats` |
   219 | | FR-8 `disable-model-invocation` lint | `tests/unit/user-invoked-commands.bats` over `.claude/data/user-invoked-commands.txt` | Every listed command file carries `disable-model-invocation: true` and every flagged file is listed; no other command or skill body has an operative line naming a listed command (the clause before the verb is judged; "tell the user to run" is advice); no SKILL.md `allowed-tools` grants `dec-write-lib.sh confirm`, `supersede` or `context --clear`. The harness refusal itself is checked live by `tests/unit/user-invoked-harness.bats`. | `LOA_HARNESS_CHECK=0` skips the live harness call (a skip, never a pass) | A text lint: an indirect reference it cannot parse as operative passes, and the harness refusal is the control. The live check skips without the `claude` CLI, `jq` or `timeout`, and on a CLI error or an inconclusive control. | `tests/unit/user-invoked-commands.bats`, `tests/unit/user-invoked-harness.bats` |
   220 | 
   221 | ## Compliance Hooks — Agent Hook Pattern (v1.40.0)
   222 | 
   223 | ### When to Use Agent vs Shell Hooks
   224 | 
   225 | | Criterion | Shell Hook | Compliance Hook |
   226 | |-----------|-----------|----------------|
   227 | | Detection | Pattern matching (regex) | State file reading + integrity checks |
   228 | | Failure mode | Fail-open (allow) | Fail-ask (prompt user) |
~~~~

The change from head to the fix:

~~~~diff
@@ -216 +216 @@
-| Fence rule SP-1 | `.claude/hooks/safety/block-destructive-bash.sh` | Spike content never enters another branch: merge, rebase, pull, cherry-pick, reset, read-tree and update-ref with a spike ref operand; checkout or restore of a path from a spike; branch force/move/copy with a spike ref; push refspecs carrying a spike ref to another branch, or HEAD to another branch while on a spike; a FETCH_HEAD merge after fetching a spike on the same line; git alias definitions; and PRs from a spike head (`gh pr create`, `gh api` on a pulls path). Pushes, checkouts and default-branch merges into a spike stay allowed. Judged on the carrier-scrubbed, whitespace-collapsed command. | none | Listed in the rule's header comment: `git show spike/x:path >` a file, `git diff spike/x` piped to `git apply`, `git switch -c new spike/x`, `git worktree add -b new <dir> spike/x`, a spike branched under a new name then merged, a fetch and a FETCH_HEAD merge in separate commands, an alias defined outside the agent's Bash calls, `gh api --input <file>`, and a spike spelled as a SHA. The usual fence classes also apply (subshells, `eval`, newlines). Prose that names a spike merge inside a heredoc body now allows when the heredoc's consumer is non-executing (cycle-129 FR-6 classifier, corpus B79–B83); a body line that *begins* with the verb is still scanned as a command (D140). | `tests/unit/block-destructive-bash.bats`, corpus `tests/fixtures/fence-corpus/` |
+| Fence rule SP-1 | `.claude/hooks/safety/block-destructive-bash.sh` | Spike content never enters another branch: merge, rebase, pull, cherry-pick, reset, read-tree and update-ref with a spike ref operand; checkout or restore of a path from a spike; branch force/move/copy with a spike ref; push refspecs carrying a spike ref to another branch, or HEAD to another branch while on a spike; a FETCH_HEAD merge after fetching a spike on the same line; git alias definitions; and PRs from a spike head (`gh pr create`, `gh api` on a pulls path). Pushes, checkouts and default-branch merges into a spike stay allowed. Judged on the carrier-scrubbed, whitespace-collapsed command. | none | Listed in the rule's header comment: `git show spike/x:path >` a file, `git diff spike/x` piped to `git apply`, `git switch -c new spike/x`, `git worktree add -b new <dir> spike/x`, a spike branched under a new name then merged, a fetch and a FETCH_HEAD merge in separate commands, an alias defined outside the agent's Bash calls, `gh api --input <file>`, and a spike spelled as a SHA. The usual fence classes also apply (subshells, `eval`, newlines). Prose that names a spike merge inside a heredoc body now allows when the heredoc's consumer is non-executing and the delimiter is quoted (cycle-129 FR-6 classifier, corpus B79–B83); a body line that *begins* with the verb is still scanned as a command (D140). A backtick span is prose only inside single quotes or under a quoted heredoc delimiter; anywhere else it is a command substitution and is scanned as one (r256-1, D143–D148). | `tests/unit/block-destructive-bash.bats`, corpus `tests/fixtures/fence-corpus/` |
~~~~

## H09 — .claude/loa/reference/hooks-reference.md — insertion after head line 280

Head context (head/.claude/loa/reference/hooks-reference.md, lines 269–292):

~~~~text
   269 | | App Zone, unsanctioned | per the mode table above |
   270 | 
   271 | **Audit events** (plain rows in `.run/audit.jsonl`, not the signed `audit_emit` chain; model-authored values cut to 256 bytes and written with `jq -a`): one row per decision carrying `hook: implement-gate`, `action` (`allow`, `ask`, `telemetry`, `deny`), `decision` and `mode`; `compliance.state_write` for trust inputs; `compliance.mode.model_signal` per authoritative claim; `replay: true` under `LOA_AUDIT_REPLAY=1`. The guard register (`guard-yield.sh`) counts the ask and telemetry rows as the gate's yield. Paths and claims shown on stderr have control and format characters stripped.
   272 | 
   273 | **Accepted gaps**: writes through the Bash tool are not seen (the C-PROC-001 fence gap). The sanctions trust `.run/` files a Bash command can write (bead bd-taee); a marker and a trailer forged together with the right sprint id pass `derive`. A direct `/implement` without `/run` leaves no run cache, so its writes rely on the marker. `deny` reads the sprint-plan cache only: a `/run sprint-N` run that leaves only `.run/state.json` is an unknown position under `deny` and asks.
   274 | 
   275 | **Tests**: `tests/unit/implement-gate.bats` (33 cases: the mode × claims × write class × sanction × cache-state matrix), `tests/unit/compliance-hook.bats`, `tests/unit/run-checkpoint-derive.bats`.
   276 | 
   277 | ## block-destructive-bash.sh — Full Pattern Set & Posture (moved from CLAUDE.loa.md)
   278 | 
   279 | Blocks 12 destructive shapes: `rm -rf` (context-aware: blocks `/`, `~`, `$HOME`, `*`, `.`, `./.git`; allows `./build`, `./node_modules`, `/tmp/*`), `git push --force`/`-f`, `git reset --hard`, `git clean -f`, `git branch -D`/force-delete, `git stash drop`/`clear`, `git checkout -- <path>`, SQL `DROP {DATABASE,TABLE,SCHEMA}`, `TRUNCATE`, `DELETE FROM` no-WHERE (multi-statement loop), `kubectl delete namespace`, `kubectl delete --all`/`-A`. Audit-log trail to `.run/audit.jsonl` on every block with sanitized command + matched substring. Ported from Anthropic DCG public pattern set (cycle-111).
   280 | 
   281 | **cycle-122 additions**: `FR-MERGE-2` blocks manual `git tag` creation (listing/inspect/delete forms allowed; audited override `LOA_ALLOW_GIT_TAG=1`) — C-MERGE-002's mechanical twin. `FR-1.2b` blocks output-swallowed `git stash push/pop/apply` (`| tail`/`| head`, `|| true`, `2>/dev/null` — the issue #555 silent-data-loss shapes); remedy: `stash_with_guard`. `FR-SZ2` blocks direct Bash writes into `.claude/` (redirect/tee/copy/sed-i/rm shapes; `.claude/overrides/` + `.claude/cache/` excluded) unless the bounded framework-dev marker (`.run/zone-guard-authorization.json`, same validation as zone-write-guard) or `LOA_ALLOW_STATE_ZONE_EXEC_WRITE=1` authorizes — closing the single-agent System-Zone Bash gap. Same accepted-bypass classes as their parents (fence, not boundary).
   282 | 
   283 | **cycle-128 additions**: `SP-1` keeps spike content out of every other branch, and FR-1.1 lets a fully pushed spike branch with an operator-decided ledger row be deleted. Both are described, with their accepted misses, under [Decision surfaces](#decision-surfaces-cycle-128).
   284 | 
   285 | A separate script-level runtime layer (`dcg-exec.sh` + `destructive-command-guard.sh`, pattern packs for core/database/docker/kubernetes) validates commands executed by Loa scripts with configurable BLOCK/WARN/ALLOW actions — invocation and pack details live in those scripts' headers.
   286 | 
   287 | **Defense-in-depth posture (cycle-111)**: this hook is a fence against routine destructive mistakes by autonomous agents — NOT a hardened security boundary. Documented accepted bypass classes (cycle-111 SDD §11): newline statement separators, subshell wrapping (`bash -c '...'` quoted-differently, `$(...)`), eval/base64 decode, SQL comments containing WHERE, python scripts loaded from disk, jq absent from PATH. ERE flavor: GNU/BSD-compatible extensions (`\s`, `\b`), NOT strict POSIX. Latency budget: p95 < 80ms across 100 invocations (bash startup + jq + 13 grep passes).
   288 | 
   289 | ### Heredoc consumer classification (cycle-129 FR-6)
   290 | 
   291 | Knob: `destructive_command_guard.heredoc_classifier` (default `true`; `false` restores the pre-cycle scan and is the rollback key). The fence reads the knob from `.loa.config.yaml` only for commands that hold `<<`. The full grammar, both class lists and the default are stated in the block comment above `_bdb_hd_is_interp` in `block-destructive-bash.sh`. In summary:
   292 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -280,0 +281,2 @@
+**cycle-129 additions**: `FR-GH-1` refuses `gh api` with `DELETE`, `PUT` or `PATCH` (`-X`, `-XDELETE`, `--method`, `--method=`) against `/git/refs/`, `/git/tags/`, `/branches/<b>/protection`, `/releases`, `/tags` or a bare `repos/<o>/<r>` — the REST escape hatch of the porcelain forms P2, P5 and SP-1 govern (GET, POST and PATCH on issues or pulls stay allowed; corpus D156–D161, B95–B97). A backtick pair outside single quotes is normalised to the `$( )` form before any rule runs (see the heredoc-classifier section). The FR-6 heredoc consumer classifier is described in its own section above.
+
~~~~

## H10 — .claude/loa/reference/hooks-reference.md — head line 294

Head context (head/.claude/loa/reference/hooks-reference.md, lines 282–302):

~~~~text
   282 | 
   283 | **cycle-128 additions**: `SP-1` keeps spike content out of every other branch, and FR-1.1 lets a fully pushed spike branch with an operator-decided ledger row be deleted. Both are described, with their accepted misses, under [Decision surfaces](#decision-surfaces-cycle-128).
   284 | 
   285 | A separate script-level runtime layer (`dcg-exec.sh` + `destructive-command-guard.sh`, pattern packs for core/database/docker/kubernetes) validates commands executed by Loa scripts with configurable BLOCK/WARN/ALLOW actions — invocation and pack details live in those scripts' headers.
   286 | 
   287 | **Defense-in-depth posture (cycle-111)**: this hook is a fence against routine destructive mistakes by autonomous agents — NOT a hardened security boundary. Documented accepted bypass classes (cycle-111 SDD §11): newline statement separators, subshell wrapping (`bash -c '...'` quoted-differently, `$(...)`), eval/base64 decode, SQL comments containing WHERE, python scripts loaded from disk, jq absent from PATH. ERE flavor: GNU/BSD-compatible extensions (`\s`, `\b`), NOT strict POSIX. Latency budget: p95 < 80ms across 100 invocations (bash startup + jq + 13 grep passes).
   288 | 
   289 | ### Heredoc consumer classification (cycle-129 FR-6)
   290 | 
   291 | Knob: `destructive_command_guard.heredoc_classifier` (default `true`; `false` restores the pre-cycle scan and is the rollback key). The fence reads the knob from `.loa.config.yaml` only for commands that hold `<<`. The full grammar, both class lists and the default are stated in the block comment above `_bdb_hd_is_interp` in `block-destructive-bash.sh`. In summary:
   292 | 
   293 | - **Grammar.** The fence sees literal command text, with CRLF folded to LF. A control character, an unreadable header, more than one heredoc on a header, a non-word or variable delimiter, or a missing terminator makes the whole command scan in full.
>  294 | - **Interpreter class.** The body is scanned exactly as before. This applies when the consumer or any pipe target is a shell, interpreter, argument-running wrapper or SQL runner, when the statement holds a substitution, group or continuation, or when an allowlisted form carries an unknown or exec-shaped flag. It also applies when the write target is executable content: a script extension, a shebang first line, `.claude/hooks/`, `.claude/settings*.json`, `.git/hooks/`, an rc or profile file, `/etc`, or a directory on `PATH`. Naming the target elsewhere on the same command outside a safe reader has the same effect.
   295 | - **Non-executing class.** This covers exact forms only: `cat`, `tee`, `printf` and `echo` to a plain file or stdout, `gh pr|issue comment -F -`, `gh pr create --body-file -`, `git commit -F -`, `br create|update` reading stdin, `jq`/`yq` without in-place, `grep`, print-only `sed -n`, `sort` and `wc`. Their bodies are scanned per segment. Segments that start with a fence verb are kept for the normal rules, and the rest are dropped. A substitution under an unquoted delimiter, an interpreter word or a variable command word sends the body back to a full scan.
   296 | - **Default.** A consumer on neither list, or a parse failure, scans in full. The #1245 quoted standalone `cat` scrub is the special case and is also the knob-off path.
   297 | - **Export.** Source the hook with `BDB_LIB_ONLY=1` and call `_bdb_heredoc_consumer_class <command>`, which prints `interpreter`, `nonexec` or `none`. `heredoc_nonexec <command>` exits 0 for a non-executing heredoc. Library mode applies only when the file is sourced. An executed hook ignores the variable.
   298 | - **Remaining gap.** A body written to a plain file by one command and executed by a later command is outside a per-command fence. The Write tool shares this limit.
   299 | 
   300 | **Accepted false positives (quote-blindness residue, cycle-120 C-D3)**: the inert-carrier scrub redacts a known data carrier's value (git commit `-m`, `br`/`bd -d`, `gh … create --body/--title`, `echo`/`printf`) only when the value holds **neither `$(` nor a backtick**. A lone `$` (dollar amount, `$ENV` mention, trailing bare `$`) is now permitted inside a redacted value — so `git commit -m "saved $5 by dropping find . -exec rm -rf {} +"` correctly ALLOWs. One residual false positive is **accepted by design**:
   301 | 
   302 | - **Case A — a `$(…)` command-substitution inside a carrier value** (e.g. a multi-line commit body wrapped in `$(cat <<'EOF' … find -exec rm -rf … EOF)`). The `$(` disqualifies the value from redaction (a regex fence cannot parse subshell contents without reintroducing the #1047 bypass), so a destructive *shape* mentioned inside that subshell body still trips FR-2 and blocks a genuinely safe commit. **Workaround**: paraphrase the destructive shape in the commit body (as the cycle-119 commits did — e.g. write "find-exec-rm" rather than the literal `find … -exec rm -rf`), or drop the `$(…)` wrapper. This is a preserved false positive, never a bypass: leaving `$(`/backtick values un-redacted is what keeps command-substitution smuggling (`git commit -m "$(rm -rf /)"`) caught. Backtick command-substitution itself remains the separately-tracked, uncaught pre-existing gap (bd-bdb-backtick-bypass).
~~~~

The change from head to the fix:

~~~~diff
@@ -294 +296,2 @@
-- **Interpreter class.** The body is scanned exactly as before. This applies when the consumer or any pipe target is a shell, interpreter, argument-running wrapper or SQL runner, when the statement holds a substitution, group or continuation, or when an allowlisted form carries an unknown or exec-shaped flag. It also applies when the write target is executable content: a script extension, a shebang first line, `.claude/hooks/`, `.claude/settings*.json`, `.git/hooks/`, an rc or profile file, `/etc`, or a directory on `PATH`. Naming the target elsewhere on the same command outside a safe reader has the same effect.
+- **Backticks (r256-1).** After the heredoc scrub and before any rule runs, a backtick pair outside single quotes is rewritten to the `$( )` form (the 1st, 3rd, … backtick becomes `$(`, the 2nd, 4th, … becomes `)`; a backslash-escaped backtick stays literal). A substitution hidden in backticks — in a double-quoted argument, an assignment or an unquoted heredoc body — therefore anchors exactly like its `$( )` twin (corpus D143–D148). Under a quoted heredoc delimiter the backticks in a kept segment are literal text and are stripped instead (B79, B84, B91); inside single quotes nothing changes (B90).
+- **Interpreter class.** The body is scanned exactly as before. This applies when the consumer or any pipe target is a shell, interpreter, argument-running wrapper or SQL runner, when the statement holds a substitution, group or continuation, or when an allowlisted form carries an unknown or exec-shaped flag. It also applies when the write target is executable content: a script extension, a shebang first line, `.claude/hooks/`, `.claude/settings*.json`, `.git/hooks/`, an rc or profile file (`.envrc` included), `/etc`, a directory on `PATH`, a `.github/workflows/` file, a makefile or justfile, or a package manifest with a script section (`package.json`, `pyproject.toml`, `Cargo.toml`, `Gemfile`, `Rakefile`; corpus D162–D168). Naming the target elsewhere on the same command outside a safe reader has the same effect.
~~~~

## H11 — .claude/rules/skill-invariants.md — insertion after head line 72

Head context (head/.claude/rules/skill-invariants.md, lines 61–84):

~~~~text
    61 | `/implement`, where writes are sanctioned). The validator emits a WARN for any *other* `role: review`
    62 | skill that declares `write_files: true` without disallowing `Write` — surfacing
    63 | a new C-PROC-001 gap at lint time. `disallowed-tools` is tool-granular, not
    64 | path-granular; it cannot express "no `src/` writes but yes `grimoires/` writes",
    65 | which is why report-authoring skills rely on zones for path-level control.
    66 | 
    67 | **The Bash gap.** `disallowed-tools` removes the Write, Edit and NotebookEdit
    68 | tools only. A pure-review skill that keeps a `Bash(...)` grant can still write
    69 | through the shell (`>`, `tee`, `cp`, `sed -i`); shell-redirection writes remain
    70 | fence territory (`block-destructive-bash.sh` and the System-Zone rules), not
    71 | frontmatter territory.
    72 | 
    73 | ## Scope
    74 | 
    75 | Applies to every `.claude/skills/**/SKILL.md`. The lint runs as part of the normal validation suite (`bats tests/unit/skill-capabilities.bats`).
    76 | 
    77 | ## Origin
    78 | 
    79 | - Defect: [#553](https://github.com/0xHoneyJar/loa/issues/553) — `/architect` and `/sprint-plan` produced correct output but refused to write their target files. Three independent reproductions across two repos.
    80 | - Tracker: [#557](https://github.com/0xHoneyJar/loa/issues/557) — Tier 1 cycle-083 framework boundary fixes.
    81 | - Sprint: `sprint-bug-102` — test-first patch landing the invariant lint + the three frontmatter fixes.
    82 | 
    83 | ## Related rules
    84 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -72,0 +73,14 @@
+**What the harness enforces (live probe, cycle-129 Sprint 2, Claude Code 2.1.296).**
+In the main session, invoking a skill that carries `disallowed-tools: Write, Edit,
+NotebookEdit` removed the three tools until the next user prompt — the next Write
+was refused ("Permission to use Write has been denied"), later calls reported the
+tools "disabled for this session, in subagents as well", and invoking a write-capable
+skill did not restore them; in an unattended run that is the rest of the session
+(KF-043). A Bash redirect still wrote a file (the Bash gap above). In a subagent
+(`general-purpose`, all tools) the same skill removed nothing: Write, Edit and Bash
+all succeeded, and `allowed-tools: Read, Grep, Glob` did not restrict either. So the
+key is a barrier in the main session only; for subagent work the zones, the fence and
+the implement gate are the barriers. Keep the key (it holds where the review and audit
+skills run) and never invoke such a skill from a lead session that still has writes
+to do.
+
~~~~

## H12 — .claude/scripts/lib/profile-lib.sh — insertion after head line 61

Head context (head/.claude/scripts/lib/profile-lib.sh, lines 50–73):

~~~~text
    50 | _loa_pl_paths() {
    51 |   local root="${LOA_PROFILE_ROOT:-}"
    52 |   if [[ -z "$root" ]]; then
    53 |     root="$(cd "$_LOA_PL_SELF_DIR/../../.." 2>/dev/null && pwd -P)"
    54 |   fi
    55 |   _LOA_PL_ROOT="$root"
    56 |   local default_cfg="$root/.loa.config.yaml" status_cfg=""
    57 |   # LOA_STATUS_CONFIG_FILE is loa-status.sh's bats-gated seam; honour it the same way.
    58 |   if [[ -n "${BATS_TEST_FILENAME:-}${BATS_VERSION:-}" ]]; then
    59 |     status_cfg="${LOA_STATUS_CONFIG_FILE:-}"
    60 |   fi
    61 |   _LOA_PL_CFG="${LOA_PROFILE_CONFIG_FILE:-${status_cfg:-$default_cfg}}"
    62 |   _LOA_PL_PROF="${LOA_PROFILES_FILE:-$root/.claude/data/profiles.yaml}"
    63 |   _LOA_PL_FLOOR="${LOA_PROFILE_FLOOR_FILE:-$root/.claude/data/floor.yaml}"
    64 |   if [[ -n "${LOA_PROFILE_CACHE_FILE:-}" ]]; then
    65 |     _LOA_PL_CACHE="$LOA_PROFILE_CACHE_FILE"
    66 |   elif [[ "$_LOA_PL_CFG" == "$default_cfg" ]]; then
    67 |     _LOA_PL_CACHE="$root/.run/effective-config.json"
    68 |   else
    69 |     _LOA_PL_CACHE=""
    70 |   fi
    71 | }
    72 | 
    73 | # The cache key: the three paths plus one stat line per existing file. An
~~~~

The change from head to the fix:

~~~~diff
@@ -61,0 +62,6 @@
+  # The seam is honoured outside bats (hooks pass their test config through it); make a
+  # redirected live read visible, once per process (audit r256-5, dissent DISS-C-004).
+  if [[ -n "${LOA_PROFILE_CONFIG_FILE:-}" && -z "${BATS_TEST_FILENAME:-}${BATS_VERSION:-}" && -z "${_LOA_PL_SEAM_WARNED:-}" ]]; then
+    printf 'profile-lib: WARN knob reads come from %s (LOA_PROFILE_CONFIG_FILE is set)\n' "$LOA_PROFILE_CONFIG_FILE" >&2
+    _LOA_PL_SEAM_WARNED=1
+  fi
~~~~

## H13 — .claude/scripts/loa-status.sh — head line 958

Head context (head/.claude/scripts/loa-status.sh, lines 946–970):

~~~~text
   946 |     echo -e "${BOLD}Profile:${NC} unknown (lib/profile-lib.sh missing; reinstall the framework with /update-loa)"
   947 |     return 0
   948 |   fi
   949 |   cfg=$(_providers_config_file)
   950 |   line=$(
   951 |     if [[ "$cfg" != "$CONFIG_FILE" ]]; then export LOA_PROFILE_CONFIG_FILE="$cfg"; fi
   952 |     # shellcheck source=lib/profile-lib.sh
   953 |     source "$lib" || exit 0
   954 |     name=$(loa_profile 2>/dev/null) || name=standard
   955 |     note=""
   956 |     if [[ "$(loa_profile_source 2>/dev/null)" == "invalid" ]]; then note="unknown loa.profile, using standard; "; fi
   957 |     ov=$(loa_profile_overrides 2>/dev/null | awk 'NF { printf "%s%s", (n++ ? ", " : ""), $0 }')
>  958 |     printf '%s (%sexplicit overrides: %s)' "${name:-standard}" "$note" "${ov:-none}"
   959 |   ) || line=""
   960 |   echo -e "${BOLD}Profile:${NC} ${line:-standard (explicit overrides: unavailable)}"
   961 |   return 0
   962 | }
   963 | 
   964 | # cycle-129 FR-1 (SDD D-1.5): one Guards line. Counts come from the tracked structural
   965 | # register (grimoires/loa/guards.md), the 30-day yield from the untracked
   966 | # .run/guard-yield.json; nothing is recomputed here. Bats-gated seams:
   967 | # LOA_STATUS_GUARDS_FILE and LOA_STATUS_GUARD_YIELD_FILE.
   968 | display_guards_line() {
   969 |   local reg="$PROJECT_ROOT/grimoires/loa/guards.md" yf="$PROJECT_ROOT/.run/guard-yield.json"
   970 |   local hint="regenerate: .claude/scripts/guard-yield.sh" n m d y
~~~~

The change from head to the fix:

~~~~diff
@@ -958 +958,6 @@
-    printf '%s (%sexplicit overrides: %s)' "${name:-standard}" "$note" "${ov:-none}"
+    # cycle-129 audit r256-5 (DEC-0161 mitigation): say so when either guardrail
+    # control resolves to off, whatever turned it off (profile or explicit key).
+    gn=""
+    [[ "$(loa_knob guardrails.input.enabled false 2>/dev/null)" == true ]] || gn="input guardrails off"
+    [[ "$(loa_knob guardrails.danger_level.enforce false 2>/dev/null)" == true ]] || gn="${gn:+$gn, }danger-level enforcement off"
+    printf '%s (%sexplicit overrides: %s)%s' "${name:-standard}" "$note" "${ov:-none}" "${gn:+ · $gn}"
~~~~

## H14 — .claude/skills/auditing-security/SKILL.md — head lines 6–7

Head context (head/.claude/skills/auditing-security/SKILL.md, lines 1–19):

~~~~text
     1 | ---
     2 | name: audit
     3 | description: Security and quality audit of application codebase
     4 | role: review
     5 | effort: medium
>    6 | allowed-tools: Read, Grep, Glob, Write, Edit, WebFetch, WebSearch, Bash(.claude/scripts/verdict-derive.sh *), Bash(.claude/scripts/adversarial-review.sh *), Bash(br sync --import-only), Bash(br sync --flush-only), Bash(br comments add *), Bash(br label add *), Bash(.claude/scripts/beads/log-discovered-issue.sh *), Bash(.claude/scripts/guardrails-orchestrator.sh *), Bash(.claude/scripts/security-audit-scope.sh *)
>    7 | # Write/Edit: State-Zone feedback/COMPLETED markers only (C-PROC-001, by zones).
     8 | disallowed-tools:
     9 |   - NotebookEdit
    10 | capabilities:
    11 |   schema_version: 1
    12 |   read_files: true
    13 |   search_code: true
    14 |   write_files: true
    15 |   execute_commands:
    16 |     allowed:
    17 |       - command: ".claude/scripts/verdict-derive.sh"
    18 |         args: ["*"]
    19 |       - command: ".claude/scripts/adversarial-review.sh"
~~~~

The change from head to the fix:

~~~~diff
@@ -6,2 +6 @@
-allowed-tools: Read, Grep, Glob, Write, Edit, WebFetch, WebSearch, Bash(.claude/scripts/verdict-derive.sh *), Bash(.claude/scripts/adversarial-review.sh *), Bash(br sync --import-only), Bash(br sync --flush-only), Bash(br comments add *), Bash(br label add *), Bash(.claude/scripts/beads/log-discovered-issue.sh *), Bash(.claude/scripts/guardrails-orchestrator.sh *), Bash(.claude/scripts/security-audit-scope.sh *)
-# Write/Edit: State-Zone feedback/COMPLETED markers only (C-PROC-001, by zones).
+allowed-tools: Read, Grep, Glob, Write, Edit, WebFetch, WebSearch, Bash(.claude/scripts/verdict-derive.sh *), Bash(.claude/scripts/adversarial-review.sh *), Bash(br sync --import-only), Bash(br sync --flush-only), Bash(br comments add *), Bash(br label add *), Bash(.claude/scripts/beads/log-discovered-issue.sh *), Bash(.claude/scripts/guardrails-orchestrator.sh *), Bash(.claude/scripts/security-audit-scope.sh *), Bash(.claude/scripts/lib/profile-lib.sh knob *)
~~~~

## H15 — .claude/skills/auditing-security/SKILL.md — insertion after head line 34

Head context (head/.claude/skills/auditing-security/SKILL.md, lines 23–46):

~~~~text
    23 |       - command: "br"
    24 |         args: ["sync", "--flush-only"]
    25 |       - command: "br"
    26 |         args: ["comments", "add", "*"]
    27 |       - command: "br"
    28 |         args: ["label", "add", "*"]
    29 |       - command: ".claude/scripts/beads/log-discovered-issue.sh"
    30 |         args: ["*"]
    31 |       - command: ".claude/scripts/guardrails-orchestrator.sh"
    32 |         args: ["*"]
    33 |       - command: ".claude/scripts/security-audit-scope.sh"
    34 |         args: ["*"]
    35 |     deny_raw_shell: true
    36 |   web_access: true
    37 |   user_interaction: false
    38 |   agent_spawn: false
    39 |   task_management: false
    40 | cost-profile: heavy
    41 | context: fork
    42 | parallel_threshold: 2000
    43 | audit_categories: 5
    44 | timeout_minutes: 60
    45 | zones:
    46 |   system:
~~~~

The change from head to the fix:

~~~~diff
@@ -34,0 +34,2 @@
+      - command: ".claude/scripts/lib/profile-lib.sh"
+        args: ["knob", "*"]
~~~~

## H16 — .claude/skills/reviewing-code/SKILL.md — head lines 6–7

Head context (head/.claude/skills/reviewing-code/SKILL.md, lines 1–19):

~~~~text
     1 | ---
     2 | name: review-sprint
     3 | description: Validate sprint implementation against acceptance criteria
     4 | role: review
     5 | effort: xhigh
>    6 | allowed-tools: Read, Grep, Glob, Write, Edit, WebFetch, Bash(git diff *), Bash(git log *), Bash(.claude/scripts/verdict-derive.sh *), Bash(.claude/scripts/adversarial-review.sh *), Bash(.claude/scripts/qmd-context-query.sh *), Bash(.claude/scripts/red-test-check.sh --red *), Bash(.claude/scripts/guardrails-orchestrator.sh *), Bash(br sync --import-only), Bash(br sync --flush-only), Bash(br comments add *), Bash(br label add *)
>    7 | # Write/Edit: State-Zone feedback/checkmarks only (C-PROC-001, by zones).
     8 | disallowed-tools:
     9 |   - NotebookEdit
    10 | capabilities:
    11 |   schema_version: 1
    12 |   read_files: true
    13 |   search_code: true
    14 |   write_files: true
    15 |   execute_commands:
    16 |     allowed:
    17 |       - command: "git"
    18 |         args: ["diff", "*"]
    19 |       - command: "git"
~~~~

The change from head to the fix:

~~~~diff
@@ -6,2 +6 @@
-allowed-tools: Read, Grep, Glob, Write, Edit, WebFetch, Bash(git diff *), Bash(git log *), Bash(.claude/scripts/verdict-derive.sh *), Bash(.claude/scripts/adversarial-review.sh *), Bash(.claude/scripts/qmd-context-query.sh *), Bash(.claude/scripts/red-test-check.sh --red *), Bash(.claude/scripts/guardrails-orchestrator.sh *), Bash(br sync --import-only), Bash(br sync --flush-only), Bash(br comments add *), Bash(br label add *)
-# Write/Edit: State-Zone feedback/checkmarks only (C-PROC-001, by zones).
+allowed-tools: Read, Grep, Glob, Write, Edit, WebFetch, Bash(git diff *), Bash(git log *), Bash(.claude/scripts/verdict-derive.sh *), Bash(.claude/scripts/adversarial-review.sh *), Bash(.claude/scripts/qmd-context-query.sh *), Bash(.claude/scripts/red-test-check.sh --red *), Bash(.claude/scripts/guardrails-orchestrator.sh *), Bash(br sync --import-only), Bash(br sync --flush-only), Bash(br comments add *), Bash(br label add *), Bash(.claude/scripts/lib/profile-lib.sh knob *)
~~~~

## H17 — .claude/skills/reviewing-code/SKILL.md — insertion after head line 38

Head context (head/.claude/skills/reviewing-code/SKILL.md, lines 27–50):

~~~~text
    27 |       - command: ".claude/scripts/red-test-check.sh"
    28 |         args: ["--red", "*"]
    29 |       - command: ".claude/scripts/guardrails-orchestrator.sh"
    30 |         args: ["*"]
    31 |       - command: "br"
    32 |         args: ["sync", "--import-only"]
    33 |       - command: "br"
    34 |         args: ["sync", "--flush-only"]
    35 |       - command: "br"
    36 |         args: ["comments", "add", "*"]
    37 |       - command: "br"
    38 |         args: ["label", "add", "*"]
    39 |     deny_raw_shell: true
    40 |   web_access: true
    41 |   user_interaction: false
    42 |   agent_spawn: false
    43 |   task_management: false
    44 | cost-profile: moderate
    45 | parallel_threshold: 3000
    46 | timeout_minutes: 60
    47 | zones:
    48 |   system:
    49 |     path: .claude
    50 |     permission: none
~~~~

The change from head to the fix:

~~~~diff
@@ -38,0 +38,2 @@
+      - command: ".claude/scripts/lib/profile-lib.sh"
+        args: ["knob", "*"]
~~~~

## H18 — .claude/skills/reviewing-code/SKILL.md — head line 288

Head context (head/.claude/skills/reviewing-code/SKILL.md, lines 276–300):

~~~~text
   276 | ## Subagent Report Check
   277 | 
   278 | Read the sprint's `grimoires/loa/a2a/subagent-reports/` before approving. Blocking: architecture-validator `CRITICAL_VIOLATION`, security-scanner `CRITICAL` or `HIGH`, test-adequacy-reviewer `INSUFFICIENT`, goal-validation `GOAL_BLOCKED`. `DRIFT_DETECTED`, security `MEDIUM`/`LOW` and test-adequacy `WEAK` are your discretion. No reports (`/validate` is optional): review manually. Grep commands: `resources/REFERENCE.md` §Subagent Report Check.
   279 | </subagent_report_check>
   280 | 
   281 | <checklists>
   282 | Checklists, Red Flags and Mermaid standards: `resources/REFERENCE.md`.
   283 | </checklists>
   284 | 
   285 | <complexity_review>
   286 | ## Complexity Review (Required)
   287 | 
>  288 | Review complexity every time (thresholds, tags: `resources/REFERENCE.md` §Complexity). BLOCK approval for any function over 50 lines without justification, nesting deeper than 3 without early returns, more than 3 duplicate code blocks, or circular dependencies. Tag over-engineering findings `SIMPLICITY[delete|stdlib|native|yagni|shrink]: …`; a `loa:shortcut:` marker naming a ceiling with no upgrade trigger is `SIMPLICITY[shrink]`. End an over-engineering pass with `net: -<N> lines possible`, or `Lean already. Ship.` and stop. Never flag the one required acceptance check behind non-trivial logic for deletion (the YAGNI minimum).
   289 | </complexity_review>
   290 | 
   291 | <beads_workflow>
   292 | With `br` installed: `resources/BEADS-WORKFLOW.md` (sync, comment, labels); protocol: `.claude/protocols/beads-integration.md`.
   293 | </beads_workflow>
   294 | 
   295 | <retrospective_postlude>
   296 | <!-- @skill-include: start retrospective_postlude | hash:53d44248 | DO NOT EDIT — generated from .claude/data/skill-includes/retrospective_postlude.md -->
   297 | After the main skill logic, if `.claude/scripts/lib/profile-lib.sh knob invisible_retrospective.enabled`
   298 | prints `true` (and `invisible_retrospective.skills` does not disable this skill), silently run the
   299 | learning-signal scan per `.claude/skills/continuous-learning/SKILL.md` and its
   300 | `resources/RETROSPECTIVE.md` (quality gates, sanitization, trajectory logging). Never when the
~~~~

The change from head to the fix:

~~~~diff
@@ -288 +289 @@
-Review complexity every time (thresholds, tags: `resources/REFERENCE.md` §Complexity). BLOCK approval for any function over 50 lines without justification, nesting deeper than 3 without early returns, more than 3 duplicate code blocks, or circular dependencies. Tag over-engineering findings `SIMPLICITY[delete|stdlib|native|yagni|shrink]: …`; a `loa:shortcut:` marker naming a ceiling with no upgrade trigger is `SIMPLICITY[shrink]`. End an over-engineering pass with `net: -<N> lines possible`, or `Lean already. Ship.` and stop. Never flag the one required acceptance check behind non-trivial logic for deletion (the YAGNI minimum).
+Review complexity every time (thresholds, tags: `resources/REFERENCE.md` §Complexity). BLOCK approval for a function over 50 lines without justification, nesting over 3 without early returns, over 3 duplicate blocks, or circular dependencies. Tag over-engineering findings `SIMPLICITY[delete|stdlib|native|yagni|shrink]: …`; a `loa:shortcut:` marker with no upgrade trigger is `SIMPLICITY[shrink]`. End an over-engineering pass with `net: -<N> lines possible`, or `Lean already. Ship.` and stop. Never flag the one required acceptance check behind non-trivial logic for deletion (the YAGNI minimum).
~~~~

## H19 — .loa.config.yaml.example — insertion after head line 31

Head context (head/.loa.config.yaml.example, lines 20–43):

~~~~text
    20 | #   structured_handoff.enabled, soul_identity_doc.enabled
    21 | # `lean` turns them all off, `full` all on, and `standard` (the default) is the
    22 | # per-key default this file shows (soul_identity_doc.enabled, not shown here,
    23 | # is false). A key you set explicitly anywhere in
    24 | # this file wins over the profile. The values per profile live in
    25 | # .claude/data/profiles.yaml; `/loa` prints the effective profile and your
    26 | # explicit overrides. No floor key is reachable through a profile: review,
    27 | # audit, verdict-derive, the dissent artefact gate, the deny list, the
    28 | # destructive-command fence, the System-Zone rules and every other floor
    29 | # config key read the same configuration under every profile
    30 | # (.claude/data/floor.yaml lists them; tests/unit/profile-floor.bats pins it).
    31 | # An unknown value warns and falls back to standard.
    32 | loa:
    33 |   profile: standard   # lean | standard | full
    34 | 
    35 | # -----------------------------------------------------------------------------
    36 | # Ride Configuration (v1.31.0)
    37 | # -----------------------------------------------------------------------------
    38 | # Controls /ride codebase analysis behavior.
    39 | ride:
    40 |   # Days before ride artifacts are considered stale. When /ride is invoked
    41 |   # and .reality-meta.json shows artifacts younger than this, the user is
    42 |   # prompted to skip or re-analyze. Use --fresh flag to bypass.
    43 |   staleness_days: 7
~~~~

The change from head to the fix:

~~~~diff
@@ -31,0 +32,6 @@
+# The nine keys appear in this file only as commented lines at their usual
+# place ("Profile-governed … uncomment to pin it"), so a copied example follows
+# the profile you choose; an uncommented key is an explicit override and wins.
+# Seam: the environment variable LOA_PROFILE_CONFIG_FILE points the profile
+# library at another config file (hooks pass their own test config through it);
+# it is honoured outside bats, so treat it as part of the hook environment.
~~~~

## H20 — .loa.config.yaml.example — head line 312

Head context (head/.loa.config.yaml.example, lines 300–324):

~~~~text
   300 | # -----------------------------------------------------------------------------
   301 | # The operational log at grimoires/loa/known-failures.md records degradation
   302 | # patterns the framework has hit. Its ## Index is generated (drift-proof) by
   303 | # .claude/scripts/grimoire-index.sh from the ## KF-NNN: headings.
   304 | known_failures:
   305 |   # When true, the .claude/hooks/loa-kf-surface.sh SessionStart hook surfaces a
   306 |   # compact symptom -> KF table (with numeric recurrence) at session start so an
   307 |   # agent sees the failure log before triaging. DEFAULT-OFF: the hook is
   308 |   # observability only — it always exits 0, never blocks a session, and emits
   309 |   # NOTHING while this flag is false. When true it is loud-but-nonblocking: it
   310 |   # warns visibly ([KF-SURFACE] WARNING) if the surface is enabled-but-degraded
   311 |   # (known-failures.md unreadable or zero entries parsed).
>  312 |   surface_at_session_start: false
   313 | 
   314 | # -----------------------------------------------------------------------------
   315 | # Decision ledger (grimoires/loa/decisions.yaml)
   316 | # -----------------------------------------------------------------------------
   317 | # Rows are written only by .claude/scripts/lib/dec-write-lib.sh (needs jq and Mike
   318 | # Farah yq v4). Skills record decisions as `proposed`; the operator confirms them
   319 | # with /decisions confirm. See grimoires/loa/sdd.md §3.1 for the schema.
   320 | decisions:
   321 |   # When true, .claude/hooks/session-start/loa-decisions-surface.sh prints up to 10
   322 |   # proposed and open rows (id, status, summary) at session start, inside the L6
   323 |   # untrusted-content fence, plus a notice when .run/unattended.json is stale.
   324 |   # DEFAULT-OFF: the hook prints nothing while this is false and always exits 0.
~~~~

The change from head to the fix:

~~~~diff
@@ -312 +318,2 @@
-  surface_at_session_start: false
+  # Profile-governed (loa.profile; standard = false). Uncomment to pin it:
+  # surface_at_session_start: false
~~~~

## H21 — .loa.config.yaml.example — head line 325

Head context (head/.loa.config.yaml.example, lines 313–337):

~~~~text
   313 | 
   314 | # -----------------------------------------------------------------------------
   315 | # Decision ledger (grimoires/loa/decisions.yaml)
   316 | # -----------------------------------------------------------------------------
   317 | # Rows are written only by .claude/scripts/lib/dec-write-lib.sh (needs jq and Mike
   318 | # Farah yq v4). Skills record decisions as `proposed`; the operator confirms them
   319 | # with /decisions confirm. See grimoires/loa/sdd.md §3.1 for the schema.
   320 | decisions:
   321 |   # When true, .claude/hooks/session-start/loa-decisions-surface.sh prints up to 10
   322 |   # proposed and open rows (id, status, summary) at session start, inside the L6
   323 |   # untrusted-content fence, plus a notice when .run/unattended.json is stale.
   324 |   # DEFAULT-OFF: the hook prints nothing while this is false and always exits 0.
>  325 |   surface_at_session_start: false
   326 |   # Hours after which `dec-write-lib.sh context --set-unattended`'s marker is stale
   327 |   # and ignored (a marker from another session is stale at once).
   328 |   unattended_marker_ttl_hours: 24
   329 | 
   330 | # -----------------------------------------------------------------------------
   331 | # Skills (v1.14.0)
   332 | # -----------------------------------------------------------------------------
   333 | skills:
   334 |   defer_loading: false        # Config prep only (runtime Phase 2)
   335 |   always_load:
   336 |     - autonomous-agent
   337 |     - run-mode
~~~~

The change from head to the fix:

~~~~diff
@@ -325 +332,2 @@
-  surface_at_session_start: false
+  # Profile-governed (loa.profile; standard = false). Uncomment to pin it:
+  # surface_at_session_start: false
~~~~

## H22 — .loa.config.yaml.example — head line 1358

Head context (head/.loa.config.yaml.example, lines 1346–1370):

~~~~text
  1346 | # injection detection, and relevance checking before skills execute.
  1347 | # Based on OpenAI's "A Practical Guide to Building Agents" guardrails pattern.
  1348 | #
  1349 | # Default OFF since cycle-129 (DEC-0161): across 82 recorded guardrail events
  1350 | # the input guardrails caught nothing, and danger-level enforcement blocked
  1351 | # the sanctioned skills seven times. Turn them on with
  1352 | # `guardrails.input.enabled: true` (the orchestrator then logs PASS/BLOCK
  1353 | # events to the trajectory) and `guardrails.danger_level.enforce: true`.
  1354 | # Both keys are part of the `loa.profile` set (`full` turns them on).
  1355 | guardrails:
  1356 |   # Input guardrails (pre-execution)
  1357 |   input:
> 1358 |     enabled: false
  1359 | 
  1360 |     # PII Filter: Detect and redact sensitive data before processing
  1361 |     # Actions: redact (replace with placeholder), anonymize (generic value)
  1362 |     pii_filter:
  1363 |       enabled: true
  1364 |       mode: blocking              # blocking | parallel | advisory
  1365 |       patterns:
  1366 |         api_keys: true            # sk-*, ghp_*, AKIA*
  1367 |         emails: true              # user@example.com
  1368 |         phone_numbers: true       # 555-123-4567
  1369 |         ssn: true                 # 123-45-6789
  1370 |         credit_cards: true        # 4111-1111-1111-1111
~~~~

The change from head to the fix:

~~~~diff
@@ -1358 +1366,2 @@
-    enabled: false
+    # Profile-governed (loa.profile; standard = false, full = true). Uncomment to pin it:
+    # enabled: false
~~~~

## H23 — .loa.config.yaml.example — head line 1404

Head context (head/.loa.config.yaml.example, lines 1392–1416):

~~~~text
  1392 |       mode: advisory
  1393 |       confidence_threshold: 0.8   # Range: 0.0-1.0 (default: 0.8)
  1394 | 
  1395 |   # Tripwire: Halt execution on parallel guardrail failure
  1396 |   tripwire:
  1397 |     enabled: true
  1398 |     on_failure: halt              # halt | warn | log
  1399 |     rollback_on_halt: false       # Revert uncommitted changes (experimental)
  1400 | 
  1401 |   # Danger Level Enforcement: Tool risk classification
  1402 |   # Levels: safe, moderate, high, critical
  1403 |   danger_level:
> 1404 |     enforce: false                # see the default-off note above the block
  1405 |     interactive:
  1406 |       safe: execute               # Execute immediately
  1407 |       moderate: execute_with_notice  # Brief notice in output
  1408 |       high: confirm_required      # Require explicit confirmation
  1409 |       critical: confirm_with_reason  # Confirm + explain why
  1410 |     autonomous:
  1411 |       safe: execute               # Execute immediately
  1412 |       moderate: execute_with_log  # Execute with enhanced logging
  1413 |       high: block_without_flag    # BLOCK unless --allow-high
  1414 |       critical: always_block      # ALWAYS BLOCK (no override)
  1415 | 
  1416 |   # Trajectory logging for guardrail events
~~~~

The change from head to the fix:

~~~~diff
@@ -1404 +1413,3 @@
-    enforce: false                # see the default-off note above the block
+    # Profile-governed (loa.profile; standard = false, full = true); see the
+    # default-off note above the block. Uncomment to pin it:
+    # enforce: false
~~~~

## H24 — .loa.config.yaml.example — head lines 1431–1432

Head context (head/.loa.config.yaml.example, lines 1419–1444):

~~~~text
  1419 |     input_guardrails: true
  1420 |     danger_level_decisions: true
  1421 |     handoffs: true
  1422 |     redaction_audit: true         # Log redaction counts for audit
  1423 | 
  1424 | # -----------------------------------------------------------------------------
  1425 | # Invisible Retrospective Learning (v1.19.0)
  1426 | # -----------------------------------------------------------------------------
  1427 | # Automatic learning detection during skill execution without user invocation.
  1428 | # Uses skill postludes to silently scan for discoveries and extract learnings.
  1429 | # Mirrors the invisible prompt enhancement pattern from v1.17.0.
  1430 | invisible_retrospective:
> 1431 |   # Master toggle - set to false to disable all invisible retrospective
> 1432 |   enabled: true
  1433 | 
  1434 |   # Always log to trajectory (even when disabled) - useful for debugging
  1435 |   log_to_trajectory: true
  1436 | 
  1437 |   # Minimum quality gates passed to surface finding (out of 4)
  1438 |   # Gates: Depth, Reusability, Trigger Clarity, Verification
  1439 |   # Range: 0-4 (0 = surface everything, 4 = maximum strictness)
  1440 |   surface_threshold: 3
  1441 | 
  1442 |   # Maximum candidates to evaluate per skill invocation
  1443 |   # Range: 1-20 (recommended max: 10, higher values increase processing time)
  1444 |   max_candidates: 5
~~~~

The change from head to the fix:

~~~~diff
@@ -1431,2 +1442,3 @@
-  # Master toggle - set to false to disable all invisible retrospective
-  enabled: true
+  # Master toggle - set to false to disable all invisible retrospective.
+  # Profile-governed (loa.profile; standard = true, lean = false). Uncomment to pin it:
+  # enabled: true
~~~~

## H25 — .loa.config.yaml.example — head line 2932

Head context (head/.loa.config.yaml.example, lines 2920–2944):

~~~~text
  2920 |   # consumer in v1; reserved for v2 when surface-assumption analysis lands.
  2921 |   surface_assumptions: true
  2922 | 
  2923 |   # Simplicity enforcement intensity: full (default, enforced — the YAGNI ladder,
  2924 |   # stdlib/native first, shortest diff) or ultra (deletion-first, challenges the
  2925 |   # requirement before building). There is NO advise-only 'lite' level: the
  2926 |   # "never simplify away" floor (C-PROC-011) stays enforced at every level.
  2927 |   simplicity_intensity: full
  2928 | 
  2929 |   # G-1 — master switch for the PostToolUse:Write|Edit surgical-diff hook
  2930 |   # at .claude/hooks/quality/karpathy-surgical-diff-check.sh. When false,
  2931 |   # the hook fast-paths to exit 0 in <10ms.
> 2932 |   surgical_diff_warning: true
  2933 | 
  2934 |   # G-1 — per-session diff-lines threshold. When the session accumulator
  2935 |   # exceeds this, the hook emits a [karpathy-surgical-warn] stderr line
  2936 |   # and writes a trajectory event. Raised from the original protocol-doc
  2937 |   # sketch of 50 because 50 was empirically too tight for bug-fix sprints
  2938 |   # that legitimately touch 60-80 lines (test file + production diff).
  2939 |   diff_lines_per_task: 100
  2940 | 
  2941 |   # Reserved for v2 — no v1 consumer. Cyclomatic complexity check.
  2942 |   simplicity_check: true
  2943 | 
  2944 |   # Reserved for v2 — no v1 consumer. AST-level abstraction-depth analysis.
~~~~

The change from head to the fix:

~~~~diff
@@ -2932 +2944,2 @@
-  surgical_diff_warning: true
+  # Profile-governed (loa.profile; standard = true, lean = false). Uncomment to pin it:
+  # surgical_diff_warning: true
~~~~

## H26 — .loa.config.yaml.example — head line 2950

Head context (head/.loa.config.yaml.example, lines 2938–2962):

~~~~text
  2938 |   # that legitimately touch 60-80 lines (test file + production diff).
  2939 |   diff_lines_per_task: 100
  2940 | 
  2941 |   # Reserved for v2 — no v1 consumer. Cyclomatic complexity check.
  2942 |   simplicity_check: true
  2943 | 
  2944 |   # Reserved for v2 — no v1 consumer. AST-level abstraction-depth analysis.
  2945 |   max_abstraction_depth: 2
  2946 | 
  2947 |   # G-3 — when true, /implement refuses to write code if sprint.md lacks a
  2948 |   # "Success criteria" / "Acceptance criteria" / "Verification" section.
  2949 |   # Operator can [Skip with rationale] to override per-invocation.
> 2950 |   require_success_criteria: true
  2951 | 
  2952 |   # warn | block. v1 honors only "warn" — block-mode is reserved for v2 to
  2953 |   # avoid surprise breaking changes during initial rollout. Even with
  2954 |   # `enforce: block` set, the v1 hook returns 0 (informational only).
  2955 |   enforce: warn
  2956 | 
  2957 | # -----------------------------------------------------------------------------
  2958 | # Structured Handoffs (L6) — surfacing controls
  2959 | # -----------------------------------------------------------------------------
  2960 | structured_handoff:
  2961 |   # Master toggle for the L6 SessionStart surfacing hook.
  2962 |   enabled: false
~~~~

The change from head to the fix:

~~~~diff
@@ -2950 +2963,2 @@
-  require_success_criteria: true
+  # Profile-governed (loa.profile; standard = true, lean = false). Uncomment to pin it:
+  # require_success_criteria: true
~~~~

## H27 — .loa.config.yaml.example — head line 2962

Head context (head/.loa.config.yaml.example, lines 2950–2974):

~~~~text
  2950 |   require_success_criteria: true
  2951 | 
  2952 |   # warn | block. v1 honors only "warn" — block-mode is reserved for v2 to
  2953 |   # avoid surprise breaking changes during initial rollout. Even with
  2954 |   # `enforce: block` set, the v1 hook returns 0 (informational only).
  2955 |   enforce: warn
  2956 | 
  2957 | # -----------------------------------------------------------------------------
  2958 | # Structured Handoffs (L6) — surfacing controls
  2959 | # -----------------------------------------------------------------------------
  2960 | structured_handoff:
  2961 |   # Master toggle for the L6 SessionStart surfacing hook.
> 2962 |   enabled: false
  2963 |   # Per-handoff body byte cap at surfacing.
  2964 |   surface_max_chars: 4000
  2965 |   # cycle-121: skip UNREAD handoffs older than N days at surfacing (0 = never
  2966 |   # skip). Read-path only — INDEX.md and read_by are untouched; old handoffs
  2967 |   # stay recoverable via the structured-handoff skill.
  2968 |   surface_max_age_days: 30
  2969 | 
  2970 | # =============================================================================
  2971 | # red_test — inputs to .claude/scripts/red-test-check.sh (the /bug red-before-green check)
  2972 | # =============================================================================
  2973 | # The check runs a test command at the red commit and at the fix, under `env -i`, and accepts
  2974 | # only a known runner as the first word of the command and of --setup: bats, pytest,
~~~~

The change from head to the fix:

~~~~diff
@@ -2962 +2976,2 @@
-  enabled: false
+  # Profile-governed (loa.profile; standard = false, full = true). Uncomment to pin it:
+  # enabled: false
~~~~

## H28 — tests/fixtures/fence-corpus/corpus.jsonl — head line 184

Head context (head/tests/fixtures/fence-corpus/corpus.jsonl, lines 172–196):

~~~~text
   172 | {"id":"D91","cmd":"git fetch origin spike/ceiling-ui; git cherry-pick FETCH_HEAD","expect":"block","rule":"SP-1","why":"fetch-then-FETCH_HEAD cherry-pick on one line","cwd":"repo"}
   173 | {"id":"D92","cmd":"git -c alias.m=merge m spike/ceiling-ui","expect":"block","rule":"SP-1","why":"an inline alias hides the merge verb","cwd":"repo"}
   174 | {"id":"D93","cmd":"git -c alias.st=status st","expect":"block","rule":"SP-1","why":"agents do not define aliases, whatever the alias names","cwd":"repo"}
   175 | {"id":"D94","cmd":"git config alias.m merge","expect":"block","rule":"SP-1","why":"an alias definition","cwd":"repo"}
   176 | {"id":"D95","cmd":"git config --global alias.m merge","expect":"block","rule":"SP-1","why":"a global alias definition","cwd":"repo"}
   177 | {"id":"D96","cmd":"gh api repos/acme/app/pulls -f head=spike/ceiling-ui -f base=main","expect":"block","rule":"SP-1","why":"the PR gh pr create refuses, through the REST API","cwd":"repo"}
   178 | {"id":"D97","cmd":"gh api -f head=acme:spike/ceiling-ui -f base=main repos/acme/app/pulls","expect":"block","rule":"SP-1","why":"fields before the path, owner-qualified head","cwd":"repo"}
   179 | {"id":"D98","cmd":"git config set alias.m merge","expect":"block","rule":"SP-1","why":"the subcommand definition form","cwd":"repo"}
   180 | {"id":"D99","cmd":"git checkout -p spike/ceiling-ui","expect":"block","rule":"SP-1","why":"an interactive patch copy of spike hunks into the working tree (Bridgebuilder F-015)","cwd":"repo"}
   181 | {"id":"D100","cmd":"git checkout --patch spike/ceiling-ui -- src/a.ts","expect":"block","rule":"SP-1","why":"the long form of the same patch copy, with a path","cwd":"repo"}
   182 | {"id":"B77","cmd":"git checkout -p main","expect":"allow","rule":"SP-1","why":"a patch copy from the default branch names no spike","cwd":"repo"}
   183 | {"id":"B78","cmd":"git format-patch -1 main","expect":"allow","rule":"SP-1","why":"format-patch of a non-spike ref; the spike form is a documented two-step miss","cwd":"repo"}
>  184 | {"id":"B79","cmd":"cat >> grimoires/loa/NOTES.md <<EOF\n- **Sprint 253**: SP-1 refused `git merge spike/ceiling-ui` typed inside this NOTES append (prose, not a command)\nEOF","expect":"allow","rule":"FR-6","why":"SP-1 prose case 1: a spike merge named mid-sentence in a NOTES append with an unquoted delimiter (the #1245 scrub did not cover it); the segment's command word is `-`, so the line is dropped","cwd":"repo"}
   185 | {"id":"B80","cmd":"mkdir -p grimoires/loa/a2a/sprint-253 && cat > grimoires/loa/a2a/sprint-253/engineer-feedback.md <<'EOF'\n## LOW-3\nThe recipe git fetch origin spike/x && git merge FETCH_HEAD belongs to the ICE merge path, not to a heredoc.\nEOF","expect":"allow","rule":"FR-6","why":"SP-1 prose case 2: a compound header (mkdir && cat) writing a feedback file whose prose names the fetch+FETCH_HEAD one-liner; only the heredoc's own pipeline is classified","cwd":"repo"}
   186 | {"id":"B81","cmd":"tee -a grimoires/loa/NOTES.md <<'EOF'\n- the fence (SP-1) blocked `git rebase spike/ceiling-ui` inside a review heredoc; recorded as a false positive\nEOF","expect":"allow","rule":"FR-6","why":"SP-1 prose case 3: tee -a to a plain .md with a spike rebase named mid-sentence","cwd":"repo"}
   187 | {"id":"B82","cmd":"git commit -q -F - <<'EOF'\nfix(fence): SP-1 no longer blocks prose naming git merge spike/x inside a heredoc\nEOF","expect":"allow","rule":"FR-6","why":"SP-1 prose case 4: a commit message read from stdin naming a spike merge","cwd":"repo"}
   188 | {"id":"B83","cmd":"gh pr comment 1279 -F - <<'EOF'\nThe reviewer's example `git cherry-pick spike/ceiling-ui~2` is refused by SP-1 by design.\nEOF","expect":"allow","rule":"FR-6","why":"SP-1 prose case 5: a PR comment body read from stdin naming a spike cherry-pick","cwd":"repo"}
   189 | {"id":"B84","cmd":"cat > grimoires/loa/a2a/sprint-256/review.md <<EOF\n- the transcript's `git push --force origin main` was refused by P2, as intended\nEOF","expect":"allow","rule":"FR-6","why":"the P2 force-push string inside a heredoc redirected to a .md file, unquoted delimiter; the line's command word is `-`","cwd":"repo"}
   190 | {"id":"B85","cmd":"br create --title \"fence false positive\" --description - <<'EOF'\nThe agent typed rm -rf ./build inside a NOTES heredoc and the fence blocked the append.\nEOF","expect":"allow","rule":"FR-6","why":"br create reading its description from stdin; the body quotes a recursive delete mid-sentence","cwd":"repo"}
   191 | {"id":"B86","cmd":"gh pr comment 1281 -F - <<'EOF'\nThe `git push --force` to the record branch was blocked; use the temporary-index recipe.\nEOF","expect":"allow","rule":"FR-6","why":"gh pr comment -F - body naming a force push; `;` splits the line and neither segment starts with a fence verb","cwd":"repo"}
   192 | {"id":"B87","cmd":"jq -f - evals/results/arms/review-recall/batch-1/STATUS.json <<'EOF'\n.per_arm | to_entries[] | select(.value.note != \"rm -rf src\")\nEOF","expect":"allow","rule":"FR-6","why":"a jq filter read from stdin (no in-place flag); the filter's pipes split into segments whose words are jq, not shell","cwd":"repo"}
   193 | {"id":"B88","cmd":"git commit -q -F - <<'EOF'\nfix(fence): the FR-6 classifier stops blocking prose that mentions rm -rf src in a NOTES heredoc\nEOF","expect":"allow","rule":"FR-6","why":"a commit message read from stdin naming a destructive command mid-sentence","cwd":"repo"}
   194 | {"id":"D101","cmd":"bash <<'EOF'\nrm -rf src\nEOF","expect":"block","rule":"FR-6","why":"shell consumer: the body is scanned in full","cwd":"repo"}
   195 | {"id":"D102","cmd":"python3 - <<'PY'\nimport os\nos.system(\"rm -rf src\")\nPY","expect":"block","rule":"FR-6","why":"interpreter consumer reading stdin: the quoted rm inside os.system() is scanned","cwd":"repo"}
   196 | {"id":"D103","cmd":"psql \"$DATABASE_URL\" <<SQL\nDROP TABLE users;\nSQL","expect":"block","rule":"FR-6","why":"SQL runner consumer with an unquoted delimiter (D14 is the quoted form)","cwd":"repo"}
~~~~

The change from head to the fix:

~~~~diff
@@ -184 +184 @@
-{"id":"B79","cmd":"cat >> grimoires/loa/NOTES.md <<EOF\n- **Sprint 253**: SP-1 refused `git merge spike/ceiling-ui` typed inside this NOTES append (prose, not a command)\nEOF","expect":"allow","rule":"FR-6","why":"SP-1 prose case 1: a spike merge named mid-sentence in a NOTES append with an unquoted delimiter (the #1245 scrub did not cover it); the segment's command word is `-`, so the line is dropped","cwd":"repo"}
+{"id":"B79","cmd":"cat >> grimoires/loa/NOTES.md <<'EOF'\n- **Sprint 253**: SP-1 refused `git merge spike/ceiling-ui` typed inside this NOTES append (prose, not a command)\nEOF","expect":"allow","rule":"FR-6","why":"SP-1 prose case 1: a spike merge named mid-sentence in a NOTES append under a QUOTED delimiter (the backticks are literal); the segment's command word is `-`, so the line is dropped. The unquoted form is D143 (r256-1)","cwd":"repo"}
~~~~

## H29 — tests/fixtures/fence-corpus/corpus.jsonl — head line 189

Head context (head/tests/fixtures/fence-corpus/corpus.jsonl, lines 177–201):

~~~~text
   177 | {"id":"D96","cmd":"gh api repos/acme/app/pulls -f head=spike/ceiling-ui -f base=main","expect":"block","rule":"SP-1","why":"the PR gh pr create refuses, through the REST API","cwd":"repo"}
   178 | {"id":"D97","cmd":"gh api -f head=acme:spike/ceiling-ui -f base=main repos/acme/app/pulls","expect":"block","rule":"SP-1","why":"fields before the path, owner-qualified head","cwd":"repo"}
   179 | {"id":"D98","cmd":"git config set alias.m merge","expect":"block","rule":"SP-1","why":"the subcommand definition form","cwd":"repo"}
   180 | {"id":"D99","cmd":"git checkout -p spike/ceiling-ui","expect":"block","rule":"SP-1","why":"an interactive patch copy of spike hunks into the working tree (Bridgebuilder F-015)","cwd":"repo"}
   181 | {"id":"D100","cmd":"git checkout --patch spike/ceiling-ui -- src/a.ts","expect":"block","rule":"SP-1","why":"the long form of the same patch copy, with a path","cwd":"repo"}
   182 | {"id":"B77","cmd":"git checkout -p main","expect":"allow","rule":"SP-1","why":"a patch copy from the default branch names no spike","cwd":"repo"}
   183 | {"id":"B78","cmd":"git format-patch -1 main","expect":"allow","rule":"SP-1","why":"format-patch of a non-spike ref; the spike form is a documented two-step miss","cwd":"repo"}
   184 | {"id":"B79","cmd":"cat >> grimoires/loa/NOTES.md <<EOF\n- **Sprint 253**: SP-1 refused `git merge spike/ceiling-ui` typed inside this NOTES append (prose, not a command)\nEOF","expect":"allow","rule":"FR-6","why":"SP-1 prose case 1: a spike merge named mid-sentence in a NOTES append with an unquoted delimiter (the #1245 scrub did not cover it); the segment's command word is `-`, so the line is dropped","cwd":"repo"}
   185 | {"id":"B80","cmd":"mkdir -p grimoires/loa/a2a/sprint-253 && cat > grimoires/loa/a2a/sprint-253/engineer-feedback.md <<'EOF'\n## LOW-3\nThe recipe git fetch origin spike/x && git merge FETCH_HEAD belongs to the ICE merge path, not to a heredoc.\nEOF","expect":"allow","rule":"FR-6","why":"SP-1 prose case 2: a compound header (mkdir && cat) writing a feedback file whose prose names the fetch+FETCH_HEAD one-liner; only the heredoc's own pipeline is classified","cwd":"repo"}
   186 | {"id":"B81","cmd":"tee -a grimoires/loa/NOTES.md <<'EOF'\n- the fence (SP-1) blocked `git rebase spike/ceiling-ui` inside a review heredoc; recorded as a false positive\nEOF","expect":"allow","rule":"FR-6","why":"SP-1 prose case 3: tee -a to a plain .md with a spike rebase named mid-sentence","cwd":"repo"}
   187 | {"id":"B82","cmd":"git commit -q -F - <<'EOF'\nfix(fence): SP-1 no longer blocks prose naming git merge spike/x inside a heredoc\nEOF","expect":"allow","rule":"FR-6","why":"SP-1 prose case 4: a commit message read from stdin naming a spike merge","cwd":"repo"}
   188 | {"id":"B83","cmd":"gh pr comment 1279 -F - <<'EOF'\nThe reviewer's example `git cherry-pick spike/ceiling-ui~2` is refused by SP-1 by design.\nEOF","expect":"allow","rule":"FR-6","why":"SP-1 prose case 5: a PR comment body read from stdin naming a spike cherry-pick","cwd":"repo"}
>  189 | {"id":"B84","cmd":"cat > grimoires/loa/a2a/sprint-256/review.md <<EOF\n- the transcript's `git push --force origin main` was refused by P2, as intended\nEOF","expect":"allow","rule":"FR-6","why":"the P2 force-push string inside a heredoc redirected to a .md file, unquoted delimiter; the line's command word is `-`","cwd":"repo"}
   190 | {"id":"B85","cmd":"br create --title \"fence false positive\" --description - <<'EOF'\nThe agent typed rm -rf ./build inside a NOTES heredoc and the fence blocked the append.\nEOF","expect":"allow","rule":"FR-6","why":"br create reading its description from stdin; the body quotes a recursive delete mid-sentence","cwd":"repo"}
   191 | {"id":"B86","cmd":"gh pr comment 1281 -F - <<'EOF'\nThe `git push --force` to the record branch was blocked; use the temporary-index recipe.\nEOF","expect":"allow","rule":"FR-6","why":"gh pr comment -F - body naming a force push; `;` splits the line and neither segment starts with a fence verb","cwd":"repo"}
   192 | {"id":"B87","cmd":"jq -f - evals/results/arms/review-recall/batch-1/STATUS.json <<'EOF'\n.per_arm | to_entries[] | select(.value.note != \"rm -rf src\")\nEOF","expect":"allow","rule":"FR-6","why":"a jq filter read from stdin (no in-place flag); the filter's pipes split into segments whose words are jq, not shell","cwd":"repo"}
   193 | {"id":"B88","cmd":"git commit -q -F - <<'EOF'\nfix(fence): the FR-6 classifier stops blocking prose that mentions rm -rf src in a NOTES heredoc\nEOF","expect":"allow","rule":"FR-6","why":"a commit message read from stdin naming a destructive command mid-sentence","cwd":"repo"}
   194 | {"id":"D101","cmd":"bash <<'EOF'\nrm -rf src\nEOF","expect":"block","rule":"FR-6","why":"shell consumer: the body is scanned in full","cwd":"repo"}
   195 | {"id":"D102","cmd":"python3 - <<'PY'\nimport os\nos.system(\"rm -rf src\")\nPY","expect":"block","rule":"FR-6","why":"interpreter consumer reading stdin: the quoted rm inside os.system() is scanned","cwd":"repo"}
   196 | {"id":"D103","cmd":"psql \"$DATABASE_URL\" <<SQL\nDROP TABLE users;\nSQL","expect":"block","rule":"FR-6","why":"SQL runner consumer with an unquoted delimiter (D14 is the quoted form)","cwd":"repo"}
   197 | {"id":"D104","cmd":"bash -c \"$(cat <<EOF\nrm -rf src\nEOF\n)\"","expect":"block","rule":"FR-6","why":"cat inside a command substitution handed to bash -c: the header cannot be tokenised (open quote, $( ) so the whole command is scanned","cwd":"repo"}
   198 | {"id":"D105","cmd":"eval \"$(cat <<EOF\nrm -rf src\nEOF\n)\"","expect":"block","rule":"FR-6","why":"cat inside a substitution handed to eval","cwd":"repo"}
   199 | {"id":"D106","cmd":"source <(cat <<EOF\nrm -rf src\nEOF\n)","expect":"block","rule":"FR-6","why":"cat inside a process substitution handed to source","cwd":"repo"}
   200 | {"id":"D107","cmd":"ssh deploy@host bash <<EOF\nrm -rf src\nEOF","expect":"block","rule":"FR-6","why":"ssh runs its argument: interpreter class","cwd":"repo"}
   201 | {"id":"D108","cmd":"docker exec -i app sh <<EOF\nrm -rf src\nEOF","expect":"block","rule":"FR-6","why":"docker exec runs its argument: interpreter class","cwd":"repo"}
~~~~

The change from head to the fix:

~~~~diff
@@ -189 +189 @@
-{"id":"B84","cmd":"cat > grimoires/loa/a2a/sprint-256/review.md <<EOF\n- the transcript's `git push --force origin main` was refused by P2, as intended\nEOF","expect":"allow","rule":"FR-6","why":"the P2 force-push string inside a heredoc redirected to a .md file, unquoted delimiter; the line's command word is `-`","cwd":"repo"}
+{"id":"B84","cmd":"cat > grimoires/loa/a2a/sprint-256/review.md <<'EOF'\n- the transcript's `git push --force origin main` was refused by P2, as intended\nEOF","expect":"allow","rule":"FR-6","why":"the P2 force-push string inside a heredoc redirected to a .md file under a QUOTED delimiter (the backticks are literal); the line's command word is `-`. The unquoted form is D144 (r256-1)","cwd":"repo"}
~~~~

## H30 — tests/fixtures/fence-corpus/corpus.jsonl — head line 200

Head context (head/tests/fixtures/fence-corpus/corpus.jsonl, lines 188–212):

~~~~text
   188 | {"id":"B83","cmd":"gh pr comment 1279 -F - <<'EOF'\nThe reviewer's example `git cherry-pick spike/ceiling-ui~2` is refused by SP-1 by design.\nEOF","expect":"allow","rule":"FR-6","why":"SP-1 prose case 5: a PR comment body read from stdin naming a spike cherry-pick","cwd":"repo"}
   189 | {"id":"B84","cmd":"cat > grimoires/loa/a2a/sprint-256/review.md <<EOF\n- the transcript's `git push --force origin main` was refused by P2, as intended\nEOF","expect":"allow","rule":"FR-6","why":"the P2 force-push string inside a heredoc redirected to a .md file, unquoted delimiter; the line's command word is `-`","cwd":"repo"}
   190 | {"id":"B85","cmd":"br create --title \"fence false positive\" --description - <<'EOF'\nThe agent typed rm -rf ./build inside a NOTES heredoc and the fence blocked the append.\nEOF","expect":"allow","rule":"FR-6","why":"br create reading its description from stdin; the body quotes a recursive delete mid-sentence","cwd":"repo"}
   191 | {"id":"B86","cmd":"gh pr comment 1281 -F - <<'EOF'\nThe `git push --force` to the record branch was blocked; use the temporary-index recipe.\nEOF","expect":"allow","rule":"FR-6","why":"gh pr comment -F - body naming a force push; `;` splits the line and neither segment starts with a fence verb","cwd":"repo"}
   192 | {"id":"B87","cmd":"jq -f - evals/results/arms/review-recall/batch-1/STATUS.json <<'EOF'\n.per_arm | to_entries[] | select(.value.note != \"rm -rf src\")\nEOF","expect":"allow","rule":"FR-6","why":"a jq filter read from stdin (no in-place flag); the filter's pipes split into segments whose words are jq, not shell","cwd":"repo"}
   193 | {"id":"B88","cmd":"git commit -q -F - <<'EOF'\nfix(fence): the FR-6 classifier stops blocking prose that mentions rm -rf src in a NOTES heredoc\nEOF","expect":"allow","rule":"FR-6","why":"a commit message read from stdin naming a destructive command mid-sentence","cwd":"repo"}
   194 | {"id":"D101","cmd":"bash <<'EOF'\nrm -rf src\nEOF","expect":"block","rule":"FR-6","why":"shell consumer: the body is scanned in full","cwd":"repo"}
   195 | {"id":"D102","cmd":"python3 - <<'PY'\nimport os\nos.system(\"rm -rf src\")\nPY","expect":"block","rule":"FR-6","why":"interpreter consumer reading stdin: the quoted rm inside os.system() is scanned","cwd":"repo"}
   196 | {"id":"D103","cmd":"psql \"$DATABASE_URL\" <<SQL\nDROP TABLE users;\nSQL","expect":"block","rule":"FR-6","why":"SQL runner consumer with an unquoted delimiter (D14 is the quoted form)","cwd":"repo"}
   197 | {"id":"D104","cmd":"bash -c \"$(cat <<EOF\nrm -rf src\nEOF\n)\"","expect":"block","rule":"FR-6","why":"cat inside a command substitution handed to bash -c: the header cannot be tokenised (open quote, $( ) so the whole command is scanned","cwd":"repo"}
   198 | {"id":"D105","cmd":"eval \"$(cat <<EOF\nrm -rf src\nEOF\n)\"","expect":"block","rule":"FR-6","why":"cat inside a substitution handed to eval","cwd":"repo"}
   199 | {"id":"D106","cmd":"source <(cat <<EOF\nrm -rf src\nEOF\n)","expect":"block","rule":"FR-6","why":"cat inside a process substitution handed to source","cwd":"repo"}
>  200 | {"id":"D107","cmd":"ssh deploy@host bash <<EOF\nrm -rf src\nEOF","expect":"block","rule":"FR-6","why":"ssh runs its argument: interpreter class","cwd":"repo"}
   201 | {"id":"D108","cmd":"docker exec -i app sh <<EOF\nrm -rf src\nEOF","expect":"block","rule":"FR-6","why":"docker exec runs its argument: interpreter class","cwd":"repo"}
   202 | {"id":"D109","cmd":"sudo bash <<EOF\nrm -rf src\nEOF","expect":"block","rule":"FR-6","why":"sudo wrapper around a shell","cwd":"repo"}
   203 | {"id":"D110","cmd":"cat <<EOF | xargs -I{} sh -c '{}'\nrm -rf src\nEOF","expect":"block","rule":"FR-6","why":"a pipe target that runs its input (xargs sh -c) makes the pipeline interpreter class","cwd":"repo"}
   204 | {"id":"D111","cmd":"env python3 - <<PY\nimport os\nos.system(\"rm -rf src\")\nPY","expect":"block","rule":"FR-6","why":"env wrapper around an interpreter","cwd":"repo"}
   205 | {"id":"D112","cmd":"cat <<'EOF' | find . -name '*.bak' -exec rm -rf {} +\nsrc\nEOF","expect":"block","rule":"FR-6","why":"find -exec as the pipe target: interpreter class, the header's own find -exec rm is scanned","cwd":"repo"}
   206 | {"id":"D113","cmd":"gh api -X DELETE repos/o/r/git/refs/heads/main --input - <<'EOF'\n{\"note\":\"rm -rf src\"}\nEOF","expect":"block","rule":"FR-6","why":"gh api --input - is not an allowlisted gh form, so the body is scanned in full (the ref deletion itself has no fence rule: R06)","cwd":"repo"}
   207 | {"id":"D114","cmd":"yq -i '.' ci.yaml <<'EOF'\nrun: rm -rf src\nEOF","expect":"block","rule":"FR-6","why":"yq in-place: the allowlist excludes -i, the body is scanned","cwd":"repo"}
   208 | {"id":"D115","cmd":"jq -i '.cmd' <<'EOF'\n{\"cmd\": \"rm -rf src\"}\nEOF","expect":"block","rule":"FR-6","why":"jq with an in-place-shaped flag: the body is scanned","cwd":"repo"}
   209 | {"id":"D116","cmd":"awk '{ system(\"rm -rf src\") }' <<'EOF'\nx\nEOF","expect":"block","rule":"FR-6","why":"awk can call system(): interpreter class, the header's own system() argument is scanned","cwd":"repo"}
   210 | {"id":"D117","cmd":"sed 'e rm -rf src' <<'EOF'\nx\nEOF","expect":"block","rule":"FR-6","why":"sed with an e command is not the print-only form: interpreter class","cwd":"repo"}
   211 | {"id":"D118","cmd":"make -f - <<'EOF'\nclean:\n\trm -rf src\nEOF","expect":"block","rule":"FR-6","why":"make reading a makefile from stdin runs its recipes: interpreter class","cwd":"repo"}
   212 | {"id":"D119","cmd":"cat > x.sh <<'EOF'\nrm -rf src\nEOF\nbash x.sh","expect":"block","rule":"FR-6","why":"a heredoc written to x.sh and run on the same command (script extension and same-line execution)","cwd":"repo"}
~~~~

The change from head to the fix:

~~~~diff
@@ -200 +200 @@
-{"id":"D107","cmd":"ssh deploy@host bash <<EOF\nrm -rf src\nEOF","expect":"block","rule":"FR-6","why":"ssh runs its argument: interpreter class","cwd":"repo"}
+{"id":"D107","cmd":"ssh buildhost bash <<EOF\nrm -rf src\nEOF","expect":"block","rule":"FR-6","why":"ssh runs its argument: interpreter class (the host is a bare alias: the corpus lint forbids user@host shapes)","cwd":"repo"}
~~~~

## H31 — tests/fixtures/fence-corpus/corpus.jsonl — head line 236

Head context (head/tests/fixtures/fence-corpus/corpus.jsonl, lines 224–236):

~~~~text
   224 | {"id":"D131","cmd":"cat <<EOF > notes.md\n\\rm -rf src\nEOF","expect":"block","rule":"FR-6","why":"a leading backslash is stripped before the command word is matched","cwd":"repo"}
   225 | {"id":"D132","cmd":"cat <<EOF > notes.md\n/bin/rm -rf src\nEOF","expect":"block","rule":"FR-6","why":"an absolute path is reduced to its basename before matching","cwd":"repo"}
   226 | {"id":"D133","cmd":"cat <<EOF > notes.md\ncommand rm -rf src\nEOF","expect":"block","rule":"FR-6","why":"the command wrapper prefix is stripped","cwd":"repo"}
   227 | {"id":"D134","cmd":"cat <<EOF > notes.md\nexec rm -rf src\nEOF","expect":"block","rule":"FR-6","why":"the exec wrapper prefix is stripped","cwd":"repo"}
   228 | {"id":"D135","cmd":"cat <<EOF > notes.md\nsudo rm -rf src\nEOF","expect":"block","rule":"FR-6","why":"the sudo wrapper prefix is stripped","cwd":"repo"}
   229 | {"id":"D136","cmd":"cat <<EOF > notes.md\nx=rm; $x -rf src\nEOF","expect":"block","rule":"FR-6","why":"a variable command word forces the full scan and is also scanned as rm, git and kubectl with the same arguments","cwd":"repo"}
   230 | {"id":"D137","cmd":"cat <<EOF > notes.md\n$(rm -rf src)\nEOF","expect":"block","rule":"FR-6","why":"a command substitution under an unquoted delimiter runs when the heredoc is expanded: full scan","cwd":"repo"}
   231 | {"id":"D138","cmd":"cat <<EOF > notes.md\n`rm -rf src`\nEOF","expect":"block","rule":"FR-6","why":"a backtick substitution under an unquoted delimiter: full scan","cwd":"repo"}
   232 | {"id":"D139","cmd":"cat <<EOF > notes.md\neval \"rm -rf src\"\nEOF","expect":"block","rule":"FR-6","why":"an interpreter word inside the body forces the full scan","cwd":"repo"}
   233 | {"id":"D140","cmd":"cat <<EOF > notes.md\ngit push --force origin main was refused\nEOF","expect":"block","rule":"FR-6","why":"fail closed: a prose line that begins with a fence verb is kept and scanned as a command (the documented limit of per-segment classification)","cwd":"repo"}
   234 | {"id":"D141","cmd":"cat > notes.md <<'EOF'\n\u0001\nrm -rf src\nEOF","expect":"block","rule":"FR-6","why":"a control character anywhere in the command forces the full scan","cwd":"repo"}
   235 | {"id":"D142","cmd":"cat <<'EOF' > \"$OUT\"\nrm -rf src\nEOF","expect":"block","rule":"FR-6","why":"a non-literal write target cannot be judged: interpreter class","cwd":"repo"}
>  236 | {"id":"B89","cmd":"gh api -X DELETE repos/o/r/git/refs/heads/main --input - <<'EOF'\n{\"ref\":\"refs/heads/main\"}\nEOF","expect":"allow","rule":"FR-6","why":"documented miss (cycle-129 Sprint 2): gh api -X DELETE has no fence rule of its own; the classifier scans the body in full (D113) and a benign body passes","cwd":"repo"}
~~~~

The change from head to the fix:

~~~~diff
@@ -236 +236,53 @@
-{"id":"B89","cmd":"gh api -X DELETE repos/o/r/git/refs/heads/main --input - <<'EOF'\n{\"ref\":\"refs/heads/main\"}\nEOF","expect":"allow","rule":"FR-6","why":"documented miss (cycle-129 Sprint 2): gh api -X DELETE has no fence rule of its own; the classifier scans the body in full (D113) and a benign body passes","cwd":"repo"}
+{"id":"D156","cmd":"gh api -X DELETE repos/o/r/git/refs/heads/main --input - <<'EOF'\n{\"ref\":\"refs/heads/main\"}\nEOF","expect":"block","rule":"FR-GH-1","why":"audit r256-4 (was B89, then M01 as a documented miss): gh api DELETE on a ref deletes the remote branch; FR-GH-1 now refuses the REST escape hatch the porcelain rules already govern","cwd":"repo"}
+{"id":"D157","cmd":"gh api -XDELETE repos/o/r/git/refs/tags/v1.0.0","expect":"block","rule":"FR-GH-1","why":"audit r256-4: the joined -XDELETE form against a tag ref","cwd":"repo"}
+{"id":"D158","cmd":"gh api --method PUT repos/o/r/branches/main/protection --input -","expect":"block","rule":"FR-GH-1","why":"audit r256-4: rewriting branch protection through the API","cwd":"repo"}
+{"id":"D159","cmd":"gh api --method=DELETE \"repos/o/r/releases/12\"","expect":"block","rule":"FR-GH-1","why":"audit r256-4: deleting a release; --method= form and a quoted path","cwd":"repo"}
+{"id":"D160","cmd":"gh api -X DELETE repos/o/r","expect":"block","rule":"FR-GH-1","why":"audit r256-4: deleting the repository itself","cwd":"repo"}
+{"id":"D161","cmd":"gh api -X PATCH repos/o/r -f default_branch=spike/x","expect":"block","rule":"FR-GH-1","why":"audit r256-4: PATCH on the repository (settings such as the default branch)","cwd":"repo"}
+{"id":"B95","cmd":"gh api repos/o/r/pulls --paginate -q '.[].number'","expect":"allow","rule":"FR-GH-1","why":"audit r256-4: a GET stays allowed","cwd":"repo"}
+{"id":"B96","cmd":"gh api -X POST repos/o/r/issues -f title='fence FP' -f body='see the corpus'","expect":"allow","rule":"FR-GH-1","why":"audit r256-4: POST is not a destructive method here","cwd":"repo"}
+{"id":"B97","cmd":"gh api -X PATCH repos/o/r/issues/12 -f state=closed","expect":"allow","rule":"FR-GH-1","why":"audit r256-4: PATCH on an issue is outside the protected paths","cwd":"repo"}
+{"id":"D162","cmd":"cat > .git/hooks/pre-commit <<'EOF'\nrm -rf src\nEOF","expect":"block","rule":"FR-6","why":"audit r256-4 (LOW-A1): a git hook target is executable content, shebang or not","cwd":"repo"}
+{"id":"D163","cmd":"cat > cleanup.py <<'EOF'\nimport os\nos.system(\"rm -rf src\")\nEOF","expect":"block","rule":"FR-6","why":"audit r256-4 (LOW-A1): an interpreter extension is executable content","cwd":"repo"}
+{"id":"D164","cmd":"cat > .github/workflows/ci.yml <<'EOF'\n- run: git push --force origin main\nEOF","expect":"block","rule":"FR-6","why":"audit r256-4 (LOW-A1): a workflow file runs its steps; the body is scanned in full","cwd":"repo"}
+{"id":"D165","cmd":"cat > Makefile <<'EOF'\nclean:\n\trm -rf src\nEOF","expect":"block","rule":"FR-6","why":"audit r256-4 (LOW-A1): a makefile runs its recipes","cwd":"repo"}
+{"id":"D166","cmd":"cat > .envrc <<'EOF'\nrm -rf src\nEOF","expect":"block","rule":"FR-6","why":"audit r256-4 (LOW-A1): direnv runs .envrc on cd","cwd":"repo"}
+{"id":"D167","cmd":"cat > .claude/settings.local.json <<'EOF'\n{\"hooks\": {\"PreToolUse\": \"rm -rf src\"}}\nEOF","expect":"block","rule":"FR-6","why":"audit r256-4 (LOW-A1): a settings file defines hooks (and FR-SZ2 refuses the System-Zone write regardless)","cwd":"repo"}
+{"id":"D168","cmd":"cat > package.json <<'EOF'\n{\"scripts\": {\"postinstall\": \"rm -rf src\"}}\nEOF","expect":"block","rule":"FR-6","why":"audit r256-4 (LOW-A1): a package manifest's script section runs on install","cwd":"repo"}
+{"id":"D169","cmd":"tee notes.md <<'EOF'\nif :; then rm -rf src; fi\nEOF","expect":"block","rule":"FR-6","why":"audit r256-5 (DISS-C-002): a shell reserved word (then) is a transparent prefix in the per-segment scan; the rm segment is kept. tee, not a standalone quoted cat: the #1245 special case drops that body whole, by design (nothing executes at the write)","cwd":"repo"}
+{"id":"D170","cmd":"tee notes.md <<'EOF'\n{ rm -rf src; }\nEOF","expect":"block","rule":"FR-6","why":"audit r256-5: a brace group prefix is stripped before the command word","cwd":"repo"}
+{"id":"D171","cmd":"tee notes.md <<'EOF'\n! rm -rf src\nEOF","expect":"block","rule":"FR-6","why":"audit r256-5: a negation prefix is stripped before the command word","cwd":"repo"}
+{"id":"D172","cmd":"cat > notes.md <<'EOF'\ntimeout 5 rm -rf src\nEOF","expect":"block","rule":"FR-6","why":"audit r256-5: a wrapper command word (timeout) sends the body to the full scan","cwd":"repo"}
+{"id":"D173","cmd":"tee notes.md <<'EOF'\nnohup rm -rf src &\nEOF","expect":"block","rule":"FR-6","why":"audit r256-5: the nohup wrapper prefix is stripped","cwd":"repo"}
+{"id":"D174","cmd":"tee notes.md <<'EOF'\nwhile read -r d; do rm -rf src; done < list\nEOF","expect":"block","rule":"FR-6","why":"audit r256-5: loop keywords (while, do) are transparent prefixes","cwd":"repo"}
+{"id":"B100","cmd":"cat > notes.md <<'EOF'\nif :; then rm -rf src; fi\nEOF","expect":"allow","rule":"FR-6","why":"audit r256-5: the #1245 special case — a standalone quoted cat to a plain file writes literal text and nothing executes at this command; the later-execution shape is the documented per-command gap (the tee twin is D169)","cwd":"repo"}
+{"id":"D175","cmd":"crontab - <<'EOF'\n* * * * * rm -rf src\nEOF","expect":"block","rule":"FR-6","why":"audit r256-5: crontab is an unlisted consumer, so the body is scanned in full","cwd":"repo"}
+{"id":"D176","cmd":"at now + 1 minute <<'EOF'\nrm -rf src\nEOF","expect":"block","rule":"FR-6","why":"audit r256-5: at is an unlisted consumer, so the body is scanned in full","cwd":"repo"}
+{"id":"D177","cmd":"cat > Dockerfile <<'EOF'\nRUN rm -rf src\nEOF","expect":"block","rule":"FR-6","why":"audit r256-5: a Dockerfile runs its RUN lines at build; the target is executable content","cwd":"repo"}
+{"id":"D178","cmd":"cat > .pre-commit-config.yaml <<'EOF'\n- entry: rm -rf src\nEOF","expect":"block","rule":"FR-6","why":"audit r256-5: a pre-commit config runs its entries on commit; the target is executable content","cwd":"repo"}
+{"id":"D179","cmd":"gh api graphql -f query='mutation { deleteRef(input: {refId: \"MDM6UmVmMQ==\"}) { clientMutationId } }'","expect":"block","rule":"FR-GH-1","why":"audit r256-5 (DISS-C-003): the GraphQL deleteRef mutation deletes a branch","cwd":"repo"}
+{"id":"D180","cmd":"gh api graphql -F query=@mutation.graphql -f query='mutation{updateBranchProtectionRule(input:{branchProtectionRuleId:\"x\"}){clientMutationId}}'","expect":"block","rule":"FR-GH-1","why":"audit r256-5: the branch-protection mutations","cwd":"repo"}
+{"id":"D181","cmd":"gh api -X DELETE https://api.github.com/repos/o/r/git/refs/heads/main","expect":"block","rule":"FR-GH-1","why":"audit r256-5: the full-URL path form (the corpus lint admits the api.github.com host for this row class)","cwd":"repo"}
+{"id":"D182","cmd":"gh api -X DELETE /repos/o/r/releases/3","expect":"block","rule":"FR-GH-1","why":"audit r256-5: a leading-slash path","cwd":"repo"}
+{"id":"D183","cmd":"M=DELETE; gh api -X \"$M\" repos/o/r/git/refs/heads/main","expect":"block","rule":"FR-GH-1","why":"audit r256-5: a method the fence cannot read (a variable) against a protected path is treated as destructive","cwd":"repo"}
+{"id":"D184","cmd":"gh api --hostname ghe.example.invalid -X PUT repos/o/r/branches/main/protection --input -","expect":"block","rule":"FR-GH-1","why":"audit r256-5: --hostname does not change the method or the path","cwd":"repo"}
+{"id":"B98","cmd":"gh api graphql -f query='query { repository(owner: \"o\", name: \"r\") { pullRequests(first: 5) { nodes { number } } } }'","expect":"allow","rule":"FR-GH-1","why":"audit r256-5: a GraphQL query (no destructive mutation) stays allowed","cwd":"repo"}
+{"id":"B99","cmd":"gh api -X PATCH repos/o/r/pulls/7 -f title='fence FP' -f body='see the corpus'","expect":"allow","rule":"FR-GH-1","why":"audit r256-5: PATCH on a pull request is outside the protected paths","cwd":"repo"}
+{"id":"D143","cmd":"cat >> grimoires/loa/NOTES.md <<EOF\n- **Sprint 253**: SP-1 refused `git merge spike/ceiling-ui` typed inside this NOTES append (prose, not a command)\nEOF","expect":"block","rule":"SP-1","why":"r256-1: under an UNQUOTED delimiter the backtick span is a command substitution that runs when the heredoc is expanded; normalised to the dollar-paren form, the spike merge anchors and SP-1 blocks (the quoted twin is B79)","cwd":"repo"}
+{"id":"D144","cmd":"cat > grimoires/loa/a2a/sprint-256/review.md <<EOF\n- the transcript's `git push --force origin main` was refused by P2, as intended\nEOF","expect":"block","rule":"P2","why":"r256-1: unquoted delimiter, backtick span = a force push that runs when the heredoc is expanded (the quoted twin is B84)","cwd":"repo"}
+{"id":"D145","cmd":"echo \"see `git push --force origin main` for the refusal\"","expect":"block","rule":"P2","why":"r256-1: a backtick substitution inside a double-quoted echo argument executes the force push; before the normalisation only the dollar-paren form (D148) anchored","cwd":"repo"}
+{"id":"D146","cmd":"printf '%s\\n' \"`git merge spike/ceiling-ui`\" > notes.md","expect":"block","rule":"SP-1","why":"r256-1: a backtick substitution inside a double-quoted printf argument executes the spike merge before anything is written","cwd":"repo"}
+{"id":"D147","cmd":"msg=\"done: `git push --force origin main`\"","expect":"block","rule":"P2","why":"r256-1: a backtick substitution inside a double-quoted assignment executes the force push","cwd":"repo"}
+{"id":"D148","cmd":"echo \"see $(git push --force origin main) for the refusal\"","expect":"block","rule":"P2","why":"r256-1: the dollar-paren twin of D145, which blocked before the fix; pinned so the two forms cannot diverge again","cwd":"repo"}
+{"id":"B90","cmd":"echo 'see `git push --force origin main` for the refusal'","expect":"allow","rule":"P2","why":"r256-1: inside single quotes a backtick span is literal text and nothing runs; the normalisation leaves single-quoted text alone","cwd":"repo"}
+{"id":"B91","cmd":"git commit -q -F - <<'EOF'\nfix(fence): a backtick span outside single quotes is a substitution; see `git merge main` for the ordinary merge path\nEOF","expect":"allow","rule":"FR-6","why":"r256-1: under a quoted delimiter the kept segment's literal backticks are stripped before the normalisation, so prose that mentions an ordinary command in backticks still allows","cwd":"repo"}
+{"id":"D149","cmd":"echo \"it's `git push --force origin main` now\"","expect":"block","rule":"P2","why":"r256-1: an apostrophe inside double quotes must not open a single-quote context; the backtick span still runs (the first normaliser missed this shape)","cwd":"repo"}
+{"id":"B92","cmd":"cat > notes.md <<'EOF'\nit's fine: `git push --force origin main` was refused\nEOF","expect":"allow","rule":"FR-6","why":"r256-1: quoted delimiter, so the backticks are literal whatever the apostrophe does","cwd":"repo"}
+{"id":"D150","cmd":"cat > notes.md <<EOF\nit's not fine: `git push --force origin main` runs here\nEOF","expect":"block","rule":"P2","why":"r256-1: unquoted delimiter with an apostrophe before the backtick span; a heredoc body is raw text, so the body rule alternates every backtick","cwd":"repo"}
+{"id":"D151","cmd":"cat > notes.md <<-EOF\n\t- `git merge spike/x` indented body\n\tEOF","expect":"block","rule":"SP-1","why":"r256-1: the dash form strips leading tabs from the terminator; the unquoted body's span runs","cwd":"repo"}
+{"id":"B93","cmd":"echo \"escaped \\`git push --force origin main\\` is literal\"","expect":"allow","rule":"P2","why":"r256-1: backslash-escaped backticks inside double quotes are literal text","cwd":"repo"}
+{"id":"D152","cmd":"echo 'single `git push --force origin main` quoted' && echo \"then `git push --force origin main`\"","expect":"block","rule":"P2","why":"r256-1: a literal span in single quotes followed by a real substitution in double quotes on the same line","cwd":"repo"}
+{"id":"D153","cmd":"cat > a.md <<'A'\nlit `git push --force origin main`\nA\ncat > b.md <<B\nreal `git push --force origin main`\nB","expect":"block","rule":"P2","why":"r256-1: two heredocs on separate lines; the quoted body is literal, the unquoted body runs","cwd":"repo"}
+{"id":"B94","cmd":"cat > a.md <<'A'\nlit `git push --force origin main`\nA\necho done","expect":"allow","rule":"FR-6","why":"r256-1: a quoted body followed by a harmless command; nothing runs","cwd":"repo"}
+{"id":"D154","cmd":"printf '%s' \"`git push --force origin main`\" | tee log.txt","expect":"block","rule":"P2","why":"r256-1: a substitution inside the first pipeline member","cwd":"repo"}
+{"id":"D155","cmd":"cat <<'EOF' > notes.md && echo \"ok `git push --force origin main`\"\nprose\nEOF","expect":"block","rule":"P2","why":"r256-1: the header line itself carries a real substitution after the heredoc operator","cwd":"repo"}
~~~~

## H32 — tests/fixtures/fence-corpus/run-corpus.sh — head line 6

Head context (head/tests/fixtures/fence-corpus/run-corpus.sh, lines 1–18):

~~~~text
     1 | #!/usr/bin/env bash
     2 | # run-corpus.sh — replay tests/fixtures/fence-corpus/corpus.jsonl through the
     3 | # block-destructive-bash hook and summarise (cycle-125 Sprint 1, PRD FR-1).
     4 | #
     5 | # Usage: run-corpus.sh [--hook PATH] [--corpus PATH] [--json] [--knob-off] [--rows]
>    6 | # Each row: {id, cmd, expect: allow|block|residual, rule, why, cwd: repo|tmp, env?: {TMPDIR}}
     7 | #   allow    → benign: the hook must exit 0
     8 | #   block    → dangerous: the hook must exit 2
     9 | #   residual → accepted false positive: counted, never gated
    10 | # --knob-off  writes destructive_command_guard.heredoc_classifier: false into the
    11 | #             replay root's .loa.config.yaml (cycle-129 FR-6: the pre-cycle scan);
    12 | #             compare it with the pre-change hook through --rows.
    13 | # --rows      prints "<id> <exit code>" per row instead of the summary (for diffs).
    14 | # Output (text): one line per mismatch, then
    15 | #   "benign P/T dangerous B/T residual R/T runtime_ms N p95_ms M";
    16 | # --json prints {benign_pass, benign_total, dangerous_block, dangerous_total,
    17 | #   residual_pass, residual_total, runtime_ms, p95_ms, rows, mismatches: [..]}.
    18 | # p95_ms is the 95th percentile of the per-row hook wall time (the hook process
~~~~

The change from head to the fix:

~~~~diff
@@ -6 +6,6 @@
-# Each row: {id, cmd, expect: allow|block|residual, rule, why, cwd: repo|tmp, env?: {TMPDIR}}
+# Each row: {id, cmd, expect: allow|block|residual|miss, rule, why, cwd: repo|tmp, env?: {TMPDIR}}
+#   allow/block are gated (a mismatch fails the run); residual is an accepted
+#   false positive (counted, reported as R/T where R = rows that now allow);
+#   miss is a documented false negative (M id; counted, reported as M/T where
+#   M = rows the hook still lets through, never a mismatch in either direction,
+#   so a fix never reads as a regression — r256-3).
~~~~

## H33 — tests/fixtures/fence-corpus/run-corpus.sh — head line 12

Head context (head/tests/fixtures/fence-corpus/run-corpus.sh, lines 1–24):

~~~~text
     1 | #!/usr/bin/env bash
     2 | # run-corpus.sh — replay tests/fixtures/fence-corpus/corpus.jsonl through the
     3 | # block-destructive-bash hook and summarise (cycle-125 Sprint 1, PRD FR-1).
     4 | #
     5 | # Usage: run-corpus.sh [--hook PATH] [--corpus PATH] [--json] [--knob-off] [--rows]
     6 | # Each row: {id, cmd, expect: allow|block|residual, rule, why, cwd: repo|tmp, env?: {TMPDIR}}
     7 | #   allow    → benign: the hook must exit 0
     8 | #   block    → dangerous: the hook must exit 2
     9 | #   residual → accepted false positive: counted, never gated
    10 | # --knob-off  writes destructive_command_guard.heredoc_classifier: false into the
    11 | #             replay root's .loa.config.yaml (cycle-129 FR-6: the pre-cycle scan);
>   12 | #             compare it with the pre-change hook through --rows.
    13 | # --rows      prints "<id> <exit code>" per row instead of the summary (for diffs).
    14 | # Output (text): one line per mismatch, then
    15 | #   "benign P/T dangerous B/T residual R/T runtime_ms N p95_ms M";
    16 | # --json prints {benign_pass, benign_total, dangerous_block, dangerous_total,
    17 | #   residual_pass, residual_total, runtime_ms, p95_ms, rows, mismatches: [..]}.
    18 | # p95_ms is the 95th percentile of the per-row hook wall time (the hook process
    19 | # only; the jq row parsing is outside the timed span).
    20 | set -uo pipefail
    21 | export LC_ALL=C
    22 | root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
    23 | hook="$root/.claude/hooks/safety/block-destructive-bash.sh"
    24 | corpus="$root/tests/fixtures/fence-corpus/corpus.jsonl"
~~~~

The change from head to the fix:

~~~~diff
@@ -12 +17,4 @@
-#             compare it with the pre-change hook through --rows.
+#             compare it with the pre-change hook through --rows. The hook reads
+#             that file through LOA_REPO_ROOT, which this runner exports as the
+#             replay root; the self-check below proves the knob reached the hook.
+# --no-self-check  skip the --knob-off self-check (for a probe corpus without D122).
~~~~

## H34 — tests/fixtures/fence-corpus/run-corpus.sh — head line 25

Head context (head/tests/fixtures/fence-corpus/run-corpus.sh, lines 13–37):

~~~~text
    13 | # --rows      prints "<id> <exit code>" per row instead of the summary (for diffs).
    14 | # Output (text): one line per mismatch, then
    15 | #   "benign P/T dangerous B/T residual R/T runtime_ms N p95_ms M";
    16 | # --json prints {benign_pass, benign_total, dangerous_block, dangerous_total,
    17 | #   residual_pass, residual_total, runtime_ms, p95_ms, rows, mismatches: [..]}.
    18 | # p95_ms is the 95th percentile of the per-row hook wall time (the hook process
    19 | # only; the jq row parsing is outside the timed span).
    20 | set -uo pipefail
    21 | export LC_ALL=C
    22 | root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
    23 | hook="$root/.claude/hooks/safety/block-destructive-bash.sh"
    24 | corpus="$root/tests/fixtures/fence-corpus/corpus.jsonl"
>   25 | json=0 knob_off=0 rows_out=0
    26 | while [[ $# -gt 0 ]]; do
    27 |   case "$1" in
    28 |     --hook) hook="$2"; shift 2 ;;
    29 |     --corpus) corpus="$2"; shift 2 ;;
    30 |     --json) json=1; shift ;;
    31 |     --knob-off) knob_off=1; shift ;;
    32 |     --rows) rows_out=1; shift ;;
    33 |     *) echo "usage: run-corpus.sh [--hook PATH] [--corpus PATH] [--json] [--knob-off] [--rows]" >&2; exit 2 ;;
    34 |   esac
    35 | done
    36 | [[ -x "$hook" || -f "$hook" ]] || { echo "hook not found: $hook" >&2; exit 2; }
    37 | [[ -f "$corpus" ]] || { echo "corpus not found: $corpus" >&2; exit 2; }
~~~~

The change from head to the fix:

~~~~diff
@@ -25 +33 @@
-json=0 knob_off=0 rows_out=0
+json=0 knob_off=0 rows_out=0 no_self_check=0
~~~~

## H35 — tests/fixtures/fence-corpus/run-corpus.sh — head lines 32–33

Head context (head/tests/fixtures/fence-corpus/run-corpus.sh, lines 20–45):

~~~~text
    20 | set -uo pipefail
    21 | export LC_ALL=C
    22 | root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
    23 | hook="$root/.claude/hooks/safety/block-destructive-bash.sh"
    24 | corpus="$root/tests/fixtures/fence-corpus/corpus.jsonl"
    25 | json=0 knob_off=0 rows_out=0
    26 | while [[ $# -gt 0 ]]; do
    27 |   case "$1" in
    28 |     --hook) hook="$2"; shift 2 ;;
    29 |     --corpus) corpus="$2"; shift 2 ;;
    30 |     --json) json=1; shift ;;
    31 |     --knob-off) knob_off=1; shift ;;
>   32 |     --rows) rows_out=1; shift ;;
>   33 |     *) echo "usage: run-corpus.sh [--hook PATH] [--corpus PATH] [--json] [--knob-off] [--rows]" >&2; exit 2 ;;
    34 |   esac
    35 | done
    36 | [[ -x "$hook" || -f "$hook" ]] || { echo "hook not found: $hook" >&2; exit 2; }
    37 | [[ -f "$corpus" ]] || { echo "corpus not found: $corpus" >&2; exit 2; }
    38 | 
    39 | work="$(mktemp -d)"
    40 | trap 'rm -rf -- "$work"' EXIT
    41 | repo="$work/repo"; scratch="$work/scratch"
    42 | mkdir -p "$repo" "$scratch"
    43 | export LOA_REPO_ROOT="$work"
    44 | export LOA_AUDIT_REPLAY=1   # audit rows this replay writes carry replay: true (cycle-129 DEC-0167)
    45 | if (( knob_off )); then
~~~~

The change from head to the fix:

~~~~diff
@@ -32,2 +40,3 @@
+    --no-self-check) no_self_check=1; shift ;;
     --rows) rows_out=1; shift ;;
-    *) echo "usage: run-corpus.sh [--hook PATH] [--corpus PATH] [--json] [--knob-off] [--rows]" >&2; exit 2 ;;
+    *) echo "usage: run-corpus.sh [--hook PATH] [--corpus PATH] [--json] [--knob-off] [--no-self-check] [--rows]" >&2; exit 2 ;;
~~~~

## H36 — tests/fixtures/fence-corpus/run-corpus.sh — head line 49

Head context (head/tests/fixtures/fence-corpus/run-corpus.sh, lines 37–61):

~~~~text
    37 | [[ -f "$corpus" ]] || { echo "corpus not found: $corpus" >&2; exit 2; }
    38 | 
    39 | work="$(mktemp -d)"
    40 | trap 'rm -rf -- "$work"' EXIT
    41 | repo="$work/repo"; scratch="$work/scratch"
    42 | mkdir -p "$repo" "$scratch"
    43 | export LOA_REPO_ROOT="$work"
    44 | export LOA_AUDIT_REPLAY=1   # audit rows this replay writes carry replay: true (cycle-129 DEC-0167)
    45 | if (( knob_off )); then
    46 |   printf 'destructive_command_guard:\n  heredoc_classifier: false\n' > "$work/.loa.config.yaml"
    47 | fi
    48 | 
>   49 | bp=0 bt=0 db=0 dt=0 rp=0 rt=0
    50 | mismatches=()
    51 | durations=()
    52 | # Microsecond clock: $EPOCHREALTIME (bash ≥ 5) everywhere; GNU date fallback.
    53 | now_us() {
    54 |   if [[ -n "${EPOCHREALTIME:-}" ]]; then
    55 |     local s="${EPOCHREALTIME%.*}" us="${EPOCHREALTIME#*.}"
    56 |     echo $(( s * 1000000 + 10#${us:0:6} ))
    57 |   else
    58 |     echo $(( $(date +%s%N) / 1000 ))
    59 |   fi
    60 | }
    61 | start_us=$(now_us)
~~~~

The change from head to the fix:

~~~~diff
@@ -49 +58,4 @@
-bp=0 bt=0 db=0 dt=0 rp=0 rt=0
+bp=0 bt=0 db=0 dt=0 rp=0 rt=0 mp=0 mt=0
+# The miss class is gated by count (audit r256-4 HIGH-A1): a new documented miss is a
+# mismatch until this pin is raised deliberately in the same change that documents it.
+EXPECTED_MISS_ROWS=0
~~~~

## H37 — tests/fixtures/fence-corpus/run-corpus.sh — insertion after head line 76

Head context (head/tests/fixtures/fence-corpus/run-corpus.sh, lines 65–88):

~~~~text
    65 |   cwd=$(jq -r '.cwd // "repo"' <<<"$row"); tmpdir=$(jq -r '.env.TMPDIR // empty' <<<"$row")
    66 |   dir="$repo"; [[ "$cwd" == "tmp" ]] && dir="$scratch"
    67 |   payload=$(jq -cn --arg c "$cmd" '{tool_input: {command: $c}}')
    68 |   rc=0
    69 |   t0=$(now_us)
    70 |   if [[ -n "$tmpdir" ]]; then
    71 |     (cd "$dir" && TMPDIR="$tmpdir" bash "$hook" <<<"$payload" >/dev/null 2>&1) || rc=$?
    72 |   else
    73 |     (cd "$dir" && env -u TMPDIR bash "$hook" <<<"$payload" >/dev/null 2>&1) || rc=$?
    74 |   fi
    75 |   t1=$(now_us)
    76 |   durations+=("$(( (t1 - t0) / 1000 ))")
    77 |   (( rows_out )) && printf '%s %s\n' "$id" "$rc"
    78 |   case "$expect" in
    79 |     allow)    bt=$((bt+1)); if [[ $rc -eq 0 ]]; then bp=$((bp+1)); else mismatches+=("$id:expected-allow:rc=$rc"); fi ;;
    80 |     block)    dt=$((dt+1)); if [[ $rc -eq 2 ]]; then db=$((db+1)); else mismatches+=("$id:expected-block:rc=$rc"); fi ;;
    81 |     residual) rt=$((rt+1)); [[ $rc -eq 0 ]] && rp=$((rp+1)) ;;
    82 |     *) mismatches+=("$id:unknown-expect:$expect") ;;
    83 |   esac
    84 | done < "$corpus"
    85 | end_us=$(now_us)
    86 | runtime=$(( (end_us - start_us) / 1000 ))
    87 | n=${#durations[@]}
    88 | p95=0
~~~~

The change from head to the fix:

~~~~diff
@@ -76,0 +89,2 @@
+  [[ "$id" == D122 ]] && rc_d122=$rc   # knob-off self-check (r256-1 LOW-2): classifier-only block
+  [[ "$id" == D01 ]] && rc_d01=$rc     # knob-off positive control (r256-3): a plain FR-2 block the knob must not touch
~~~~

## H38 — tests/fixtures/fence-corpus/run-corpus.sh — head lines 82–84

Head context (head/tests/fixtures/fence-corpus/run-corpus.sh, lines 70–96):

~~~~text
    70 |   if [[ -n "$tmpdir" ]]; then
    71 |     (cd "$dir" && TMPDIR="$tmpdir" bash "$hook" <<<"$payload" >/dev/null 2>&1) || rc=$?
    72 |   else
    73 |     (cd "$dir" && env -u TMPDIR bash "$hook" <<<"$payload" >/dev/null 2>&1) || rc=$?
    74 |   fi
    75 |   t1=$(now_us)
    76 |   durations+=("$(( (t1 - t0) / 1000 ))")
    77 |   (( rows_out )) && printf '%s %s\n' "$id" "$rc"
    78 |   case "$expect" in
    79 |     allow)    bt=$((bt+1)); if [[ $rc -eq 0 ]]; then bp=$((bp+1)); else mismatches+=("$id:expected-allow:rc=$rc"); fi ;;
    80 |     block)    dt=$((dt+1)); if [[ $rc -eq 2 ]]; then db=$((db+1)); else mismatches+=("$id:expected-block:rc=$rc"); fi ;;
    81 |     residual) rt=$((rt+1)); [[ $rc -eq 0 ]] && rp=$((rp+1)) ;;
>   82 |     *) mismatches+=("$id:unknown-expect:$expect") ;;
>   83 |   esac
>   84 | done < "$corpus"
    85 | end_us=$(now_us)
    86 | runtime=$(( (end_us - start_us) / 1000 ))
    87 | n=${#durations[@]}
    88 | p95=0
    89 | if (( n > 0 )); then
    90 |   idx=$(( (n * 95 + 99) / 100 ))      # nearest-rank: ceil(0.95 n)
    91 |   p95=$(printf '%s\n' "${durations[@]}" | sort -n | sed -n "${idx}p")
    92 | fi
    93 | 
    94 | (( rows_out )) && exit 0
    95 | if (( json )); then
    96 |   printf '%s\n' "${mismatches[@]+"${mismatches[@]}"}" | jq -R . | jq -s \
~~~~

The change from head to the fix:

~~~~diff
@@ -82,3 +96,5 @@
+    miss)     mt=$((mt+1)); [[ $rc -eq 0 ]] && mp=$((mp+1)) ;;
     *) mismatches+=("$id:unknown-expect:$expect") ;;
   esac
 done < "$corpus"
+(( mt == EXPECTED_MISS_ROWS )) || mismatches+=("miss-rows:$mt (pinned $EXPECTED_MISS_ROWS; raise EXPECTED_MISS_ROWS in the change that documents a new miss)")
~~~~

## H39 — tests/fixtures/fence-corpus/run-corpus.sh — insertion after head line 93

Head context (head/tests/fixtures/fence-corpus/run-corpus.sh, lines 82–103):

~~~~text
    82 |     *) mismatches+=("$id:unknown-expect:$expect") ;;
    83 |   esac
    84 | done < "$corpus"
    85 | end_us=$(now_us)
    86 | runtime=$(( (end_us - start_us) / 1000 ))
    87 | n=${#durations[@]}
    88 | p95=0
    89 | if (( n > 0 )); then
    90 |   idx=$(( (n * 95 + 99) / 100 ))      # nearest-rank: ceil(0.95 n)
    91 |   p95=$(printf '%s\n' "${durations[@]}" | sort -n | sed -n "${idx}p")
    92 | fi
    93 | 
    94 | (( rows_out )) && exit 0
    95 | if (( json )); then
    96 |   printf '%s\n' "${mismatches[@]+"${mismatches[@]}"}" | jq -R . | jq -s \
    97 |     --argjson bp "$bp" --argjson bt "$bt" --argjson db "$db" --argjson dt "$dt" \
    98 |     --argjson rp "$rp" --argjson rt "$rt" --argjson ms "$runtime" --argjson p95 "$p95" --argjson n "$n" \
    99 |     '{benign_pass:$bp, benign_total:$bt, dangerous_block:$db, dangerous_total:$dt, residual_pass:$rp, residual_total:$rt, runtime_ms:$ms, p95_ms:$p95, rows:$n, mismatches: map(select(length>0))}'
   100 | else
   101 |   printf '%s\n' "${mismatches[@]+"${mismatches[@]}"}" | sed '/^$/d'
   102 |   echo "benign $bp/$bt dangerous $db/$dt residual $rp/$rt runtime_ms $runtime p95_ms $p95"
   103 | fi
~~~~

The change from head to the fix:

~~~~diff
@@ -93,0 +110,19 @@
+# --knob-off self-check (r256-1 LOW-2): D122 (a .sh-target quoted heredoc) is blocked only
+# by the classifier; the pre-cycle scan lets it through. If it still blocks, the knob did not
+# reach the hook and the comparison would compare the hook with itself.
+if (( knob_off )) && (( ! ${no_self_check:-0} )); then
+  if [[ -z "${rc_d122:-}" ]]; then
+    echo "run-corpus: --knob-off self-check impossible: the corpus has no D122 row (pass --no-self-check for a probe corpus)" >&2
+    exit 3
+  fi
+  if [[ "$rc_d122" != 0 ]]; then
+    echo "run-corpus: --knob-off did not take effect (D122 exited $rc_d122, expected 0): the hook did not read $work/.loa.config.yaml via LOA_REPO_ROOT" >&2
+    exit 3
+  fi
+  # Positive control: a classifier-independent dangerous row must still block, or the
+  # written config disabled (or broke) the whole fence rather than the classifier.
+  if [[ -z "${rc_d01:-}" || "$rc_d01" != 2 ]]; then
+    echo "run-corpus: --knob-off positive control failed (D01 exited ${rc_d01:-unseen}, expected 2): the config file disabled the fence, not only the classifier" >&2
+    exit 3
+  fi
+fi
~~~~

## H40 — tests/fixtures/fence-corpus/run-corpus.sh — head lines 99–102

Head context (head/tests/fixtures/fence-corpus/run-corpus.sh, lines 87–103):

~~~~text
    87 | n=${#durations[@]}
    88 | p95=0
    89 | if (( n > 0 )); then
    90 |   idx=$(( (n * 95 + 99) / 100 ))      # nearest-rank: ceil(0.95 n)
    91 |   p95=$(printf '%s\n' "${durations[@]}" | sort -n | sed -n "${idx}p")
    92 | fi
    93 | 
    94 | (( rows_out )) && exit 0
    95 | if (( json )); then
    96 |   printf '%s\n' "${mismatches[@]+"${mismatches[@]}"}" | jq -R . | jq -s \
    97 |     --argjson bp "$bp" --argjson bt "$bt" --argjson db "$db" --argjson dt "$dt" \
    98 |     --argjson rp "$rp" --argjson rt "$rt" --argjson ms "$runtime" --argjson p95 "$p95" --argjson n "$n" \
>   99 |     '{benign_pass:$bp, benign_total:$bt, dangerous_block:$db, dangerous_total:$dt, residual_pass:$rp, residual_total:$rt, runtime_ms:$ms, p95_ms:$p95, rows:$n, mismatches: map(select(length>0))}'
>  100 | else
>  101 |   printf '%s\n' "${mismatches[@]+"${mismatches[@]}"}" | sed '/^$/d'
>  102 |   echo "benign $bp/$bt dangerous $db/$dt residual $rp/$rt runtime_ms $runtime p95_ms $p95"
   103 | fi
~~~~

The change from head to the fix:

~~~~diff
@@ -99,4 +134,5 @@
-    '{benign_pass:$bp, benign_total:$bt, dangerous_block:$db, dangerous_total:$dt, residual_pass:$rp, residual_total:$rt, runtime_ms:$ms, p95_ms:$p95, rows:$n, mismatches: map(select(length>0))}'
+    --argjson mp "$mp" --argjson mt "$mt" \
+    '{benign_pass:$bp, benign_total:$bt, dangerous_block:$db, dangerous_total:$dt, residual_pass:$rp, residual_total:$rt, miss_open:$mp, miss_total:$mt, runtime_ms:$ms, p95_ms:$p95, rows:$n, mismatches: map(select(length>0))}'
 else
   printf '%s\n' "${mismatches[@]+"${mismatches[@]}"}" | sed '/^$/d'
-  echo "benign $bp/$bt dangerous $db/$dt residual $rp/$rt runtime_ms $runtime p95_ms $p95"
+  echo "benign $bp/$bt dangerous $db/$dt residual $rp/$rt miss $mp/$mt runtime_ms $runtime p95_ms $p95"
~~~~

## H41 — tests/unit/guard-yield.bats — head line 71

Head context (head/tests/unit/guard-yield.bats, lines 59–83):

~~~~text
    59 | 
    60 | g() { jq -c --arg id "$1" '.guards[] | select(.id == $id) | [.blocks_30d, .likely_fp_30d, .telemetry_30d, .last_real_catch]' "$T/run/guard-yield.json"; }
    61 | 
    62 | @test "GY-1 replay rows are excluded by flag, cwd and burst and counted in the header; the window and bad rows are honoured" {
    63 |   run bash "$GY" "${ARGS[@]}"
    64 |   [ "$status" -eq 0 ] || { echo "$output" >&2; false; }
    65 |   J="$T/run/guard-yield.json"
    66 |   [ "$(jq '.audit_segments' "$J")" = "2" ]
    67 |   [ "$(jq '.audit_rows_considered' "$J")" = "20" ]
    68 |   [ "$(jq '.replay_rows_excluded' "$J")" = "13" ]
    69 |   [ "$(jq -c '.replay_rows_by_rule' "$J")" = '{"flag":1,"cwd":2,"burst":10}' ]
    70 |   [ "$(jq '.audit_rows_unparseable' "$J")" = "1" ]
>   71 |   [ "$(jq -c '.totals | [.blocks_30d, .real_blocks_30d, .likely_fp_30d, .telemetry_30d]' "$J")" = '[5,2,3,2]' ]
    72 |   [ "$(jq -r '.scope' "$J")" = "host" ]
    73 |   [ "$(jq -r '.window_days' "$J")" = "30" ]
    74 | }
    75 | 
    76 | @test "GY-2 the rotated segment is read: its real P3 catch is counted and is the guard's last_real_catch" {
    77 |   run bash "$GY" "${ARGS[@]}"
    78 |   [ "$status" -eq 0 ]
    79 |   [ "$(g fence:P3)" = '[1,0,0,"2026-10-10"]' ]
    80 | }
    81 | 
    82 | @test "GY-3 heredoc, scratch-path and prose-class blocks classify as likely false positives; a prose class with a destructive verb is real" {
    83 |   run bash "$GY" "${ARGS[@]}"
~~~~

The change from head to the fix:

~~~~diff
@@ -71 +71,2 @@
-  [ "$(jq -c '.totals | [.blocks_30d, .real_blocks_30d, .likely_fp_30d, .telemetry_30d]' "$J")" = '[5,2,3,2]' ]
+  # the FR-SZ2-REDIR row is a real block since audit r256-4 (System-Zone target), so 3 real / 2 likely FP
+  [ "$(jq -c '.totals | [.blocks_30d, .real_blocks_30d, .likely_fp_30d, .telemetry_30d]' "$J")" = '[5,3,2,2]' ]
~~~~

## H42 — tests/unit/guard-yield.bats — head lines 82–89

Head context (head/tests/unit/guard-yield.bats, lines 70–101):

~~~~text
    70 |   [ "$(jq '.audit_rows_unparseable' "$J")" = "1" ]
    71 |   [ "$(jq -c '.totals | [.blocks_30d, .real_blocks_30d, .likely_fp_30d, .telemetry_30d]' "$J")" = '[5,2,3,2]' ]
    72 |   [ "$(jq -r '.scope' "$J")" = "host" ]
    73 |   [ "$(jq -r '.window_days' "$J")" = "30" ]
    74 | }
    75 | 
    76 | @test "GY-2 the rotated segment is read: its real P3 catch is counted and is the guard's last_real_catch" {
    77 |   run bash "$GY" "${ARGS[@]}"
    78 |   [ "$status" -eq 0 ]
    79 |   [ "$(g fence:P3)" = '[1,0,0,"2026-10-10"]' ]
    80 | }
    81 | 
>   82 | @test "GY-3 heredoc, scratch-path and prose-class blocks classify as likely false positives; a prose class with a destructive verb is real" {
>   83 |   run bash "$GY" "${ARGS[@]}"
>   84 |   [ "$status" -eq 0 ]
>   85 |   [ "$(g fence:FR-SZ2-REDIR)" = '[1,1,0,"none in window"]' ]
>   86 |   [ "$(g fence:P2)" = '[1,1,0,"none in window"]' ]
>   87 |   [ "$(g fence:SP-1)" = '[1,1,0,"none in window"]' ]
>   88 |   [ "$(g fence:FR-2-AMBIGUOUS)" = '[1,0,0,"2026-10-13"]' ]
>   89 |   [ "$(g hook:safety/block-destructive-bash.sh)" = '[5,3,0,"2026-10-13"]' ]
    90 | }
    91 | 
    92 | @test "GY-4 last_real_catch and generated_at are day-granular; telemetry counts implement-gate rows; non-writers show n/a" {
    93 |   run bash "$GY" "${ARGS[@]}"
    94 |   [ "$status" -eq 0 ]
    95 |   J="$T/run/guard-yield.json"
    96 |   [ "$(jq -r '.generated_at' "$J")" = "2026-10-14" ]
    97 |   [ -z "$(jq -r '.guards[].last_real_catch' "$J" | grep -vE '^([0-9]{4}-[0-9]{2}-[0-9]{2}|none in window|n/a)$' || true)" ]
    98 |   [ "$(g gate:implement-gate)" = '[0,0,2,"none in window"]' ]
    99 |   [ "$(g hook:compliance/implement-gate.sh)" = '[0,0,2,"none in window"]' ]
   100 |   [ "$(g hook:safety/zone-write-guard.sh)" = '[null,null,null,"n/a"]' ]
   101 |   grep -qE '^\| hook:safety/zone-write-guard.sh \|.*\| n/a \| n/a \| n/a \| n/a \|$' "$T/run/guard-yield.md"
~~~~

The change from head to the fix:

~~~~diff
@@ -82,8 +83,9 @@
-@test "GY-3 heredoc, scratch-path and prose-class blocks classify as likely false positives; a prose class with a destructive verb is real" {
+@test "GY-3 scratch-path and prose-class blocks classify as likely false positives; a prose class with a destructive verb is real; a System-Zone block is real whatever its heredoc body" {
   run bash "$GY" "${ARGS[@]}"
   [ "$status" -eq 0 ]
-  [ "$(g fence:FR-SZ2-REDIR)" = '[1,1,0,"none in window"]' ]
+  # FR-SZ2-REDIR: a prose heredoc into .claude/ is the hazard SZ2 exists for (audit r256-4 MEDIUM-A2)
+  [ "$(g fence:FR-SZ2-REDIR)" = '[1,0,0,"2026-10-12"]' ]
   [ "$(g fence:P2)" = '[1,1,0,"none in window"]' ]
   [ "$(g fence:SP-1)" = '[1,1,0,"none in window"]' ]
   [ "$(g fence:FR-2-AMBIGUOUS)" = '[1,0,0,"2026-10-13"]' ]
-  [ "$(g hook:safety/block-destructive-bash.sh)" = '[5,3,0,"2026-10-13"]' ]
+  [ "$(g hook:safety/block-destructive-bash.sh)" = '[5,2,0,"2026-10-13"]' ]
~~~~

## H43 — tests/unit/karpathy-surgical-diff.bats — head line 112

Head context (head/tests/unit/karpathy-surgical-diff.bats, lines 100–124):

~~~~text
   100 |     jq -e '.lines == 7 and .over == true' "$KARPATHY_SUMMARY_FILE" >/dev/null
   101 |     # The stderr warning keeps its wording.
   102 |     [[ "$stderr" == "[karpathy-surgical-warn] Session diff total 7 lines exceeds threshold 5. Karpathy principle 3 (Surgical Changes): verify every changed line traces to the stated task. State: $KARPATHY_STATE_DIR/bd-sum.jsonl" ]]
   103 |     ls "$KARPATHY_SUMMARY_FILE".tmp.* >/dev/null 2>&1 && return 1
   104 |     true
   105 | }
   106 | 
   107 | @test "KS-5 the state directory keeps the 20 most recently written task files" {
   108 |     mkdir -p "$KARPATHY_STATE_DIR"
   109 |     local i
   110 |     for i in $(seq -w 1 25); do
   111 |         echo '{"lines_changed":1}' > "$KARPATHY_STATE_DIR/bd-old-$i.jsonl"
>  112 |         touch -d "2026-01-01 00:00:$i" "$KARPATHY_STATE_DIR/bd-old-$i.jsonl"
   113 |     done
   114 |     checkpoint sprint-256 bd-new
   115 |     write_lines 1
   116 |     [ "$(ls "$KARPATHY_STATE_DIR"/*.jsonl | wc -l)" -eq 20 ]
   117 |     [ -f "$KARPATHY_STATE_DIR/bd-new.jsonl" ]
   118 |     [ -f "$KARPATHY_STATE_DIR/bd-old-25.jsonl" ]
   119 |     [ ! -e "$KARPATHY_STATE_DIR/bd-old-06.jsonl" ]
   120 |     [ ! -e "$KARPATHY_STATE_DIR/bd-old-01.jsonl" ]
   121 | }
   122 | 
   123 | @test "KS-6 the legacy session-long state file is deleted on the first run" {
   124 |     printf '{"lines_changed":900,"running_total":900}\n' > "$KARPATHY_LEGACY_STATE"
~~~~

The change from head to the fix:

~~~~diff
@@ -112 +112 @@
-        touch -d "2026-01-01 00:00:$i" "$KARPATHY_STATE_DIR/bd-old-$i.jsonl"
+        touch -t "202601010000.$i" "$KARPATHY_STATE_DIR/bd-old-$i.jsonl"   # POSIX form: GNU and BSD touch (r256-1 LOW-3)
~~~~

## H44 — tests/unit/karpathy-surgical-diff.bats — head lines 153–158

Head context (head/tests/unit/karpathy-surgical-diff.bats, lines 141–170):

~~~~text
   141 |     # A leading dot cannot make a hidden (unrotated) file.
   142 |     jq '.checkpoint.task = ".hidden"' "$T/run/sprint-plan-state.json" > "$T/s" && mv "$T/s" "$T/run/sprint-plan-state.json"
   143 |     write_lines 1
   144 |     [ -f "$KARPATHY_STATE_DIR/_hidden.jsonl" ]
   145 |     [ "$(jq -r '.task' "$KARPATHY_SUMMARY_FILE")" = "_hidden" ]
   146 | }
   147 | 
   148 | @test "KS-8 knob off is silent: no state, no summary, no stderr" {
   149 |     printf 'karpathy_principles:\n  surgical_diff_warning: false\n  diff_lines_per_task: 1\n' > "$LOA_CONFIG_OVERRIDE"
   150 |     printf 'x\n' > "$KARPATHY_LEGACY_STATE"
   151 |     run --separate-stderr write_lines 9
   152 |     [ "$status" -eq 0 ]
>  153 |     [ -z "$output" ] && [ -z "$stderr" ]
>  154 |     [ ! -e "$KARPATHY_STATE_DIR" ] && [ ! -e "$KARPATHY_SUMMARY_FILE" ]
>  155 |     # The `lean` profile turns it off without the key; an explicit true wins over lean.
>  156 |     printf 'loa:\n  profile: lean\nkarpathy_principles:\n  diff_lines_per_task: 1\n' > "$LOA_CONFIG_OVERRIDE"
>  157 |     run --separate-stderr write_lines 9
>  158 |     [ -z "$stderr" ] && [ ! -e "$KARPATHY_SUMMARY_FILE" ]
   159 |     printf 'loa:\n  profile: lean\nkarpathy_principles:\n  surgical_diff_warning: true\n  diff_lines_per_task: 1\n' > "$LOA_CONFIG_OVERRIDE"
   160 |     run --separate-stderr write_lines 9
   161 |     [[ "$stderr" == *"[karpathy-surgical-warn]"* ]]
   162 | }
   163 | 
   164 | @test "KS-9 content never reaches state, summary or trajectory" {
   165 |     local REDACTED-TEST-SECRET"
   166 |     checkpoint sprint-256 bd-sec
   167 |     jq -nc --arg c "a
   168 | $secret
   169 | b
   170 | c
~~~~

The change from head to the fix:

~~~~diff
@@ -153,6 +153,10 @@
-    [ -z "$output" ] && [ -z "$stderr" ]
-    [ ! -e "$KARPATHY_STATE_DIR" ] && [ ! -e "$KARPATHY_SUMMARY_FILE" ]
+    # One assertion per line: an `a && b` chain only fails when a passes and b fails (audit r256-4 MEDIUM-A1).
+    [ -z "$output" ]
+    [ -z "$stderr" ]
+    [ ! -e "$KARPATHY_STATE_DIR" ]
+    [ ! -e "$KARPATHY_SUMMARY_FILE" ]
     # The `lean` profile turns it off without the key; an explicit true wins over lean.
     printf 'loa:\n  profile: lean\nkarpathy_principles:\n  diff_lines_per_task: 1\n' > "$LOA_CONFIG_OVERRIDE"
     run --separate-stderr write_lines 9
-    [ -z "$stderr" ] && [ ! -e "$KARPATHY_SUMMARY_FILE" ]
+    [ -z "$stderr" ]
+    [ ! -e "$KARPATHY_SUMMARY_FILE" ]
~~~~

## H45 — tests/unit/karpathy-surgical-diff.bats — head line 173

Head context (head/tests/unit/karpathy-surgical-diff.bats, lines 161–185):

~~~~text
   161 |     [[ "$stderr" == *"[karpathy-surgical-warn]"* ]]
   162 | }
   163 | 
   164 | @test "KS-9 content never reaches state, summary or trajectory" {
   165 |     local REDACTED-TEST-SECRET"
   166 |     checkpoint sprint-256 bd-sec
   167 |     jq -nc --arg c "a
   168 | $secret
   169 | b
   170 | c
   171 | d
   172 | e" '{tool_name: "Write", session_id: "s", tool_input: {file_path: "/repo/x", content: $c}}' | bash "$HOOK" 2>/dev/null
>  173 |     ! grep -rqF "$secret" "$KARPATHY_STATE_DIR" "$KARPATHY_SUMMARY_FILE" "$KARPATHY_TRAJECTORY_DIR"
   174 |     [ -f "$KARPATHY_TRAJECTORY_DIR/karpathy-$(date -u +%Y-%m-%d).jsonl" ]
   175 | }
   176 | 
   177 | @test "KS-10 a symlinked state directory or task file is not written through" {
   178 |     mkdir -p "$T/elsewhere"
   179 |     ln -s "$T/elsewhere" "$KARPATHY_STATE_DIR"
   180 |     checkpoint sprint-256 bd-link
   181 |     write_lines 1
   182 |     [ -z "$(ls -A "$T/elsewhere")" ]
   183 |     rm "$KARPATHY_STATE_DIR"; mkdir -p "$KARPATHY_STATE_DIR"
   184 |     ln -s "$T/elsewhere/target" "$KARPATHY_STATE_DIR/bd-link.jsonl"
   185 |     write_lines 1
~~~~

The change from head to the fix:

~~~~diff
@@ -173 +177,3 @@
-    ! grep -rqF "$secret" "$KARPATHY_STATE_DIR" "$KARPATHY_SUMMARY_FILE" "$KARPATHY_TRAJECTORY_DIR"
+    # `run` + status: a bare mid-test `! grep` is exempt from errexit and could never fail (audit r256-4 MEDIUM-A1).
+    run grep -rqF "$secret" "$KARPATHY_STATE_DIR" "$KARPATHY_SUMMARY_FILE" "$KARPATHY_TRAJECTORY_DIR"
+    [ "$status" -ne 0 ]
~~~~

## H46 — tests/unit/lint-invariants.bats — head lines 59–60

Head context (head/tests/unit/lint-invariants.bats, lines 47–72):

~~~~text
    47 | }
    48 | 
    49 | gen() { (cd "$F" && bash "$GEN" --section "${1:-agent_teams_constraints}"); }
    50 | 
    51 | @test "LI-1 constraints.json carries no C-TEAM rows and no agent_teams_constraints layer" {
    52 |     run jq '[.constraints[] | select((.id | startswith("C-TEAM")) or any(.layers[]?; .section == "agent_teams_constraints"))] | length' \
    53 |         "$R/.claude/data/constraints.json"
    54 |     [ "$status" -eq 0 ]
    55 |     [ "$output" = "0" ]
    56 | }
    57 | 
    58 | @test "LI-2 the live kernel carries neither the Agent Teams heading nor its marker" {
>   59 |     ! grep -qxF '## Agent Teams' "$R/.claude/loa/CLAUDE.loa.md"
>   60 |     ! grep -q 'agent_teams_constraints' "$R/.claude/loa/CLAUDE.loa.md"
    61 | }
    62 | 
    63 | @test "LI-3 the generator removes a leftover Agent Teams block when the class is empty" {
    64 |     add_team_block
    65 |     grep -qxF '## Agent Teams' "$F/.claude/loa/CLAUDE.loa.md"
    66 |     run gen
    67 |     [ "$status" -eq 0 ]
    68 |     ! grep -qxF '## Agent Teams' "$F/.claude/loa/CLAUDE.loa.md"
    69 |     ! grep -q 'agent_teams_constraints' "$F/.claude/loa/CLAUDE.loa.md"
    70 |     # The neighbouring sections survive with one blank line between them.
    71 |     grep -qF '<!-- @constraint-generated: end merge_constraints -->' "$F/.claude/loa/CLAUDE.loa.md"
    72 |     run grep -c '^## Agent-Network Primitives$' "$F/.claude/loa/CLAUDE.loa.md"
~~~~

The change from head to the fix:

~~~~diff
@@ -59,2 +59,5 @@
-    ! grep -qxF '## Agent Teams' "$R/.claude/loa/CLAUDE.loa.md"
-    ! grep -q 'agent_teams_constraints' "$R/.claude/loa/CLAUDE.loa.md"
+    # `run` + status, never a bare mid-test `! cmd` (exempt from errexit, so it cannot fail).
+    run grep -qxF '## Agent Teams' "$R/.claude/loa/CLAUDE.loa.md"
+    [ "$status" -ne 0 ]
+    run grep -q 'agent_teams_constraints' "$R/.claude/loa/CLAUDE.loa.md"
+    [ "$status" -ne 0 ]
~~~~

## H47 — tests/unit/lint-invariants.bats — head lines 68–69

Head context (head/tests/unit/lint-invariants.bats, lines 56–81):

~~~~text
    56 | }
    57 | 
    58 | @test "LI-2 the live kernel carries neither the Agent Teams heading nor its marker" {
    59 |     ! grep -qxF '## Agent Teams' "$R/.claude/loa/CLAUDE.loa.md"
    60 |     ! grep -q 'agent_teams_constraints' "$R/.claude/loa/CLAUDE.loa.md"
    61 | }
    62 | 
    63 | @test "LI-3 the generator removes a leftover Agent Teams block when the class is empty" {
    64 |     add_team_block
    65 |     grep -qxF '## Agent Teams' "$F/.claude/loa/CLAUDE.loa.md"
    66 |     run gen
    67 |     [ "$status" -eq 0 ]
>   68 |     ! grep -qxF '## Agent Teams' "$F/.claude/loa/CLAUDE.loa.md"
>   69 |     ! grep -q 'agent_teams_constraints' "$F/.claude/loa/CLAUDE.loa.md"
    70 |     # The neighbouring sections survive with one blank line between them.
    71 |     grep -qF '<!-- @constraint-generated: end merge_constraints -->' "$F/.claude/loa/CLAUDE.loa.md"
    72 |     run grep -c '^## Agent-Network Primitives$' "$F/.claude/loa/CLAUDE.loa.md"
    73 |     [ "$output" = "1" ]
    74 |     run diff <(sed -n '/end merge_constraints/,/^## Agent-Network/p' "$F/.claude/loa/CLAUDE.loa.md") \
    75 |              <(printf '%s\n' '<!-- @constraint-generated: end merge_constraints -->' '' '## Agent-Network Primitives')
    76 |     [ "$status" -eq 0 ]
    77 | }
    78 | 
    79 | @test "LI-4 pruning is idempotent: a second run leaves the kernel byte-identical" {
    80 |     add_team_block
    81 |     gen
~~~~

The change from head to the fix:

~~~~diff
@@ -68,2 +71,4 @@
-    ! grep -qxF '## Agent Teams' "$F/.claude/loa/CLAUDE.loa.md"
-    ! grep -q 'agent_teams_constraints' "$F/.claude/loa/CLAUDE.loa.md"
+    run grep -qxF '## Agent Teams' "$F/.claude/loa/CLAUDE.loa.md"
+    [ "$status" -ne 0 ]
+    run grep -q 'agent_teams_constraints' "$F/.claude/loa/CLAUDE.loa.md"
+    [ "$status" -ne 0 ]
~~~~

## H48 — tests/unit/lint-invariants.bats — head line 95

Head context (head/tests/unit/lint-invariants.bats, lines 83–107):

~~~~text
    83 |     run gen
    84 |     [ "$status" -eq 0 ]
    85 |     cmp "$F/first.md" "$F/.claude/loa/CLAUDE.loa.md"
    86 | }
    87 | 
    88 | @test "LI-5 the generator renders the table when the class has rows" {
    89 |     add_team_block
    90 |     add_team_row
    91 |     run gen
    92 |     [ "$status" -eq 0 ]
    93 |     grep -qxF '## Agent Teams' "$F/.claude/loa/CLAUDE.loa.md"
    94 |     grep -qxF '| MUST fixture rule | fixture why |' "$F/.claude/loa/CLAUDE.loa.md"
>   95 |     ! grep -qF 'MUST stale row' "$F/.claude/loa/CLAUDE.loa.md"
    96 | }
    97 | 
    98 | @test "LI-6 rows without the heading block fail loudly and leave the kernel untouched" {
    99 |     add_team_row
   100 |     cp "$F/.claude/loa/CLAUDE.loa.md" "$F/before.md"
   101 |     run gen
   102 |     [ "$status" -ne 0 ]
   103 |     [[ "$output" == *"Missing markers"*"agent_teams_constraints"* ]]
   104 |     cmp "$F/before.md" "$F/.claude/loa/CLAUDE.loa.md"
   105 | }
   106 | 
   107 | @test "LI-7 a marker block with foreign text above it is an error, not a silent deletion" {
~~~~

The change from head to the fix:

~~~~diff
@@ -95 +100,2 @@
-    ! grep -qF 'MUST stale row' "$F/.claude/loa/CLAUDE.loa.md"
+    run grep -qF 'MUST stale row' "$F/.claude/loa/CLAUDE.loa.md"
+    [ "$status" -ne 0 ]
~~~~

## H49 — tests/unit/lint-invariants.bats — head lines 125–129

Head context (head/tests/unit/lint-invariants.bats, lines 113–136):

~~~~text
   113 | s = s.replace("## Agent Teams\n\n| Rule | Why |", "## Agent Teams\n\nOperator prose that is not a table.\n\n| Rule | Why |")
   114 | open(p, "w", encoding="utf-8").write(s)
   115 | PY
   116 |     cp "$F/.claude/loa/CLAUDE.loa.md" "$F/before.md"
   117 |     run gen
   118 |     [ "$status" -ne 0 ]
   119 |     [[ "$output" == *"no '## Agent Teams' heading directly above its table"* ]]
   120 |     cmp "$F/before.md" "$F/.claude/loa/CLAUDE.loa.md"
   121 | }
   122 | 
   123 | @test "LI-8 lint-invariants passes the optional-table invariant on the live tree" {
   124 |     run bash -c "cd '$R' && bash '$LINT' --json"
>  125 |     echo "$output" | jq -e '.results[] | select(.message | test("agent_teams_constraints: table presence matches"))' >/dev/null
>  126 |     ! echo "$output" | jq -e '.results[] | select(.level == "ERROR" and (.message | test("agent_teams")))' >/dev/null
>  127 |     # The field name is load-bearing: the negative check above is vacuous if
>  128 |     # the report shape ever renames `level`.
>  129 |     echo "$output" | jq -e '[.results[] | has("level")] | all' >/dev/null
   130 | }
   131 | 
   132 | @test "LI-9 the lint self-test (test-lint-invariants.sh) is green" {
   133 |     run bash -c "cd '$R' && bash .claude/scripts/test-lint-invariants.sh"
   134 |     echo "$output" | tail -3
   135 |     [ "$status" -eq 0 ]
   136 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -125,5 +131,9 @@
-    echo "$output" | jq -e '.results[] | select(.message | test("agent_teams_constraints: table presence matches"))' >/dev/null
-    ! echo "$output" | jq -e '.results[] | select(.level == "ERROR" and (.message | test("agent_teams")))' >/dev/null
+    local report="$output"
+    jq -e '.results[] | select(.message | test("agent_teams_constraints: table presence matches"))' >/dev/null <<<"$report"
+    # The negative check is a `run` with a status assertion: a bare mid-test `! cmd`
+    # is exempt from errexit and could never fail (review r256-2 LOW-8).
+    run jq -e '.results[] | select(.level == "ERROR" and (.message | test("agent_teams")))' <<<"$report"
+    [ "$status" -ne 0 ]
     # The field name is load-bearing: the negative check above is vacuous if
     # the report shape ever renames `level`.
-    echo "$output" | jq -e '[.results[] | has("level")] | all' >/dev/null
+    jq -e '[.results[] | has("level")] | all' >/dev/null <<<"$report"
~~~~

## H50 — tests/unit/profile-lib.bats — head line 39

Head context (head/tests/unit/profile-lib.bats, lines 27–51):

~~~~text
    27 | 
    28 | knob() { bash "$LIB" knob "$@"; }
    29 | 
    30 | @test "PL-1 every profile defines every key, and the key set is the nine optional keys" {
    31 |     run diff <(yq -r '.profiles.lean | keys | .[]' "$PROFILES" | sort) <(jq -r '.keys | keys[]' "$ORACLE" | sort)
    32 |     [ "$status" -eq 0 ]
    33 |     for p in standard full; do
    34 |         run diff <(yq -r ".profiles.$p | keys | .[]" "$PROFILES" | sort) <(yq -r '.profiles.lean | keys | .[]' "$PROFILES" | sort)
    35 |         [ "$status" -eq 0 ]
    36 |     done
    37 |     [ "$(yq -r '.profiles | keys | .[]' "$PROFILES" | sort | paste -sd, -)" = "full,lean,standard" ]
    38 |     [ "$(yq -r '.schema_version' "$PROFILES")" = "1" ]
>   39 |     ! yq -r '.profiles[] | keys | .[]' "$PROFILES" | grep -qx 'interview.pacing'
    40 | }
    41 | 
    42 | @test "PL-2 every profile value is a boolean; lean is all false and full all true" {
    43 |     [ "$(yq -r '[.profiles[][] | tag] | unique | .[]' "$PROFILES")" = "!!bool" ]
    44 |     [ "$(yq -r '[.profiles.lean[]] | unique | .[]' "$PROFILES")" = "false" ]
    45 |     [ "$(yq -r '[.profiles.full[]] | unique | .[]' "$PROFILES")" = "true" ]
    46 | }
    47 | 
    48 | @test "PL-3 standard equals the oracle captured before any reader changed" {
    49 |     local k want got
    50 |     while IFS= read -r k; do
    51 |         want=$(jq -r --arg k "$k" '.keys[$k].standard' "$ORACLE")
~~~~

The change from head to the fix:

~~~~diff
@@ -39 +39,2 @@
-    ! yq -r '.profiles[] | keys | .[]' "$PROFILES" | grep -qx 'interview.pacing'
+    run bash -c "yq -r '.profiles[] | keys | .[]' '$PROFILES' | grep -qx 'interview.pacing'"
+    [ "$status" -ne 0 ]
~~~~

## H51 — tests/unit/profile-lib.bats — head lines 64–72

Head context (head/tests/unit/profile-lib.bats, lines 52–84):

~~~~text
    52 |         got=$(yq -r ".profiles.standard[\"$k\"]" "$PROFILES")
    53 |         [ "$want" = "$got" ] || { echo "standard $k = $got, oracle $want"; return 1; }
    54 |     done < <(jq -r '.keys | keys[]' "$ORACLE")
    55 |     # Outside the two guardrail keys (whose default this cycle changes) the
    56 |     # oracle's standard IS the value the readers returned for the shipped example.
    57 |     run jq -r '.keys | to_entries[] | select(.key | startswith("guardrails.") | not)
    58 |                | select(.value.standard != .value.example_today) | .key' "$ORACLE"
    59 |     [ -z "$output" ]
    60 |     run jq -r '.keys | to_entries[] | select(.key | startswith("guardrails.")) | "\(.value.example_today)/\(.value.standard)"' "$ORACLE"
    61 |     [ "$output" = "$(printf 'true/false\ntrue/false')" ]
    62 | }
    63 | 
>   64 | @test "PL-4 standard equals the post-cycle example defaults (explicit example value, else the reader's fallback)" {
>   65 |     local k ex st
>   66 |     while IFS= read -r k; do
>   67 |         ex=$(yq -r ".$k" "$R/.loa.config.yaml.example")
>   68 |         st=$(yq -r ".profiles.standard[\"$k\"]" "$PROFILES")
>   69 |         if [ "$ex" = "null" ]; then
>   70 |             ex=$(jq -r --arg k "$k" '.keys[$k].empty_config_today' "$ORACLE")
>   71 |         fi
>   72 |         [ "$ex" = "$st" ] || { echo "example $k = $ex, standard $st"; return 1; }
    73 |     done < <(yq -r '.profiles.standard | keys | .[]' "$PROFILES")
    74 |     [ "$(yq -r '.loa.profile' "$R/.loa.config.yaml.example")" = "standard" ]
    75 |     # Under the example config the lib resolves standard and no override.
    76 |     LOA_PROFILE_CONFIG_FILE="$R/.loa.config.yaml.example" run bash "$LIB" overrides
    77 |     [ "$status" -eq 0 ]
    78 |     [ -z "$output" ]
    79 | }
    80 | 
    81 | @test "PL-5 precedence: explicit key beats the profile, the profile beats the fallback" {
    82 |     printf 'loa:\n  profile: lean\nknown_failures:\n  surface_at_session_start: true\nkarpathy_principles:\n  diff_lines_per_task: 250\n' > "$CFG"
    83 |     [ "$(knob known_failures.surface_at_session_start false)" = "true" ]     # explicit
    84 |     [ "$(knob decisions.surface_at_session_start true)" = "false" ]          # lean, not the fallback
~~~~

The change from head to the fix:

~~~~diff
@@ -64,9 +65,10 @@
-@test "PL-4 standard equals the post-cycle example defaults (explicit example value, else the reader's fallback)" {
-    local k ex st
+@test "PL-4 the example pins no profile key (r256-2): every key is null in the raw file and standard is its effective value" {
+    local k ex st eff
     while IFS= read -r k; do
+        # r256-2 (review round 2 HIGH-2): a copied example must follow loa.profile, so the
+        # raw key is absent (a commented line) — an explicit key would beat every profile.
         ex=$(yq -r ".$k" "$R/.loa.config.yaml.example")
+        [ "$ex" = "null" ] || { echo "example pins $k = $ex (must be commented: profile-governed)"; return 1; }
         st=$(yq -r ".profiles.standard[\"$k\"]" "$PROFILES")
-        if [ "$ex" = "null" ]; then
-            ex=$(jq -r --arg k "$k" '.keys[$k].empty_config_today' "$ORACLE")
-        fi
-        [ "$ex" = "$st" ] || { echo "example $k = $ex, standard $st"; return 1; }
+        eff=$(LOA_PROFILE_CONFIG_FILE="$R/.loa.config.yaml.example" bash "$LIB" knob "$k" "unset")
+        [ "$eff" = "$st" ] || { echo "effective $k under the example = $eff, standard $st"; return 1; }
~~~~

## H52 — tests/unit/profile-lib.bats — insertion after head line 78

Head context (head/tests/unit/profile-lib.bats, lines 67–90):

~~~~text
    67 |         ex=$(yq -r ".$k" "$R/.loa.config.yaml.example")
    68 |         st=$(yq -r ".profiles.standard[\"$k\"]" "$PROFILES")
    69 |         if [ "$ex" = "null" ]; then
    70 |             ex=$(jq -r --arg k "$k" '.keys[$k].empty_config_today' "$ORACLE")
    71 |         fi
    72 |         [ "$ex" = "$st" ] || { echo "example $k = $ex, standard $st"; return 1; }
    73 |     done < <(yq -r '.profiles.standard | keys | .[]' "$PROFILES")
    74 |     [ "$(yq -r '.loa.profile' "$R/.loa.config.yaml.example")" = "standard" ]
    75 |     # Under the example config the lib resolves standard and no override.
    76 |     LOA_PROFILE_CONFIG_FILE="$R/.loa.config.yaml.example" run bash "$LIB" overrides
    77 |     [ "$status" -eq 0 ]
    78 |     [ -z "$output" ]
    79 | }
    80 | 
    81 | @test "PL-5 precedence: explicit key beats the profile, the profile beats the fallback" {
    82 |     printf 'loa:\n  profile: lean\nknown_failures:\n  surface_at_session_start: true\nkarpathy_principles:\n  diff_lines_per_task: 250\n' > "$CFG"
    83 |     [ "$(knob known_failures.surface_at_session_start false)" = "true" ]     # explicit
    84 |     [ "$(knob decisions.surface_at_session_start true)" = "false" ]          # lean, not the fallback
    85 |     [ "$(knob karpathy_principles.surgical_diff_warning true)" = "false" ]   # lean
    86 |     [ "$(knob karpathy_principles.diff_lines_per_task 100)" = "250" ]        # non-profile key, explicit
    87 |     [ "$(knob run_mode.stale_hours 7)" = "7" ]                               # non-profile key, fallback
    88 |     printf 'loa:\n  profile: full\n' > "$CFG"
    89 |     [ "$(knob decisions.surface_at_session_start false)" = "true" ]
    90 |     : > "$CFG"
~~~~

The change from head to the fix:

~~~~diff
@@ -78,0 +81,13 @@
+    # A copy of the example under lean and full changes every key, with no override listed.
+    local copy="$T/copy.yaml"
+    for p in lean full; do
+        sed "s/^  profile: standard /  profile: $p /" "$R/.loa.config.yaml.example" > "$copy"
+        [ "$(yq -r '.loa.profile' "$copy")" = "$p" ]
+        LOA_PROFILE_CONFIG_FILE="$copy" run bash "$LIB" overrides
+        [ "$status" -eq 0 ]
+        [ -z "$output" ]
+        while IFS= read -r k; do
+            eff=$(LOA_PROFILE_CONFIG_FILE="$copy" bash "$LIB" knob "$k" "unset")
+            [ "$eff" = "$(yq -r ".profiles.$p[\"$k\"]" "$PROFILES")" ] || { echo "$p: $k = $eff"; return 1; }
+        done < <(yq -r '.profiles.standard | keys | .[]' "$PROFILES")
+    done
~~~~

## H53 — tests/unit/profile-lib.bats — head line 191

Head context (head/tests/unit/profile-lib.bats, lines 179–203):

~~~~text
   179 |     [ "$status" -eq 2 ]
   180 |     [[ "$output" == *"fb"* ]]
   181 |     run bash "$LIB" knob 'a;b' fb
   182 |     [ "$status" -eq 2 ]
   183 | }
   184 | 
   185 | @test "PL-14 the /loa Profile line prints the profile and the explicit overrides" {
   186 |     printf 'loa:\n  profile: lean\nguardrails:\n  input:\n    enabled: true\n' > "$CFG"
   187 |     unset LOA_PROFILE_CONFIG_FILE
   188 |     run --separate-stderr env CACHE_DIR="$T/wscache" LOA_STATUS_RUN_DIR="$T/srun" LOA_STATUS_ENV_DIR="$T/env" \
   189 |         LOA_STATUS_CONFIG_FILE="$CFG" timeout 120 bash "$R/.claude/scripts/loa-status.sh" --no-stale-check
   190 |     line=$(printf '%s\n' "$output" | sed 's/\x1b\[[0-9;]*m//g' | grep '^Profile:')
>  191 |     [ "$line" = "Profile: lean (explicit overrides: guardrails.input.enabled=true)" ]
   192 |     : > "$CFG"
   193 |     run --separate-stderr env CACHE_DIR="$T/wscache" LOA_STATUS_RUN_DIR="$T/srun" LOA_STATUS_ENV_DIR="$T/env" \
   194 |         LOA_STATUS_CONFIG_FILE="$CFG" timeout 120 bash "$R/.claude/scripts/loa-status.sh" --no-stale-check
   195 |     line=$(printf '%s\n' "$output" | sed 's/\x1b\[[0-9;]*m//g' | grep '^Profile:')
   196 |     [ "$line" = "Profile: standard (explicit overrides: none)" ]
   197 | }
   198 | 
   199 | @test "PL-15 the guardrail readers route through loa_knob (knob on and off)" {
   200 |     printf 'guardrails:\n  input:\n    enabled: false\n' > "$CFG"
   201 |     run bash "$R/.claude/scripts/guardrails-orchestrator.sh" --skill implementing-tasks --input "Implement feature X"
   202 |     [ "$status" -eq 0 ]
   203 |     [ "$(echo "$output" | jq -r '.reason')" = "guardrails disabled in config" ]
~~~~

The change from head to the fix:

~~~~diff
@@ -191 +206,3 @@
-    [ "$line" = "Profile: lean (explicit overrides: guardrails.input.enabled=true)" ]
+    # The line says so when a guardrail control resolves to off (audit r256-5, DEC-0161 mitigation):
+    # under lean with input pinned on, only the danger-level enforcement is off.
+    [ "$line" = "Profile: lean (explicit overrides: guardrails.input.enabled=true) · danger-level enforcement off" ]
~~~~

## H54 — tests/unit/profile-lib.bats — head line 196

Head context (head/tests/unit/profile-lib.bats, lines 184–208):

~~~~text
   184 | 
   185 | @test "PL-14 the /loa Profile line prints the profile and the explicit overrides" {
   186 |     printf 'loa:\n  profile: lean\nguardrails:\n  input:\n    enabled: true\n' > "$CFG"
   187 |     unset LOA_PROFILE_CONFIG_FILE
   188 |     run --separate-stderr env CACHE_DIR="$T/wscache" LOA_STATUS_RUN_DIR="$T/srun" LOA_STATUS_ENV_DIR="$T/env" \
   189 |         LOA_STATUS_CONFIG_FILE="$CFG" timeout 120 bash "$R/.claude/scripts/loa-status.sh" --no-stale-check
   190 |     line=$(printf '%s\n' "$output" | sed 's/\x1b\[[0-9;]*m//g' | grep '^Profile:')
   191 |     [ "$line" = "Profile: lean (explicit overrides: guardrails.input.enabled=true)" ]
   192 |     : > "$CFG"
   193 |     run --separate-stderr env CACHE_DIR="$T/wscache" LOA_STATUS_RUN_DIR="$T/srun" LOA_STATUS_ENV_DIR="$T/env" \
   194 |         LOA_STATUS_CONFIG_FILE="$CFG" timeout 120 bash "$R/.claude/scripts/loa-status.sh" --no-stale-check
   195 |     line=$(printf '%s\n' "$output" | sed 's/\x1b\[[0-9;]*m//g' | grep '^Profile:')
>  196 |     [ "$line" = "Profile: standard (explicit overrides: none)" ]
   197 | }
   198 | 
   199 | @test "PL-15 the guardrail readers route through loa_knob (knob on and off)" {
   200 |     printf 'guardrails:\n  input:\n    enabled: false\n' > "$CFG"
   201 |     run bash "$R/.claude/scripts/guardrails-orchestrator.sh" --skill implementing-tasks --input "Implement feature X"
   202 |     [ "$status" -eq 0 ]
   203 |     [ "$(echo "$output" | jq -r '.reason')" = "guardrails disabled in config" ]
   204 |     printf 'guardrails:\n  input:\n    enabled: true\n' > "$CFG"
   205 |     run bash "$R/.claude/scripts/guardrails-orchestrator.sh" --skill implementing-tasks --input "Implement feature X"
   206 |     [ "$status" -eq 0 ]
   207 |     [ "$(echo "$output" | jq -r '.reason')" != "guardrails disabled in config" ]
   208 |     printf 'guardrails:\n  danger_level:\n    enforce: false\n' > "$CFG"
~~~~

The change from head to the fix:

~~~~diff
@@ -196 +213,7 @@
-    [ "$line" = "Profile: standard (explicit overrides: none)" ]
+    [ "$line" = "Profile: standard (explicit overrides: none) · input guardrails off, danger-level enforcement off" ]
+    # Under full both controls are on and the line carries no notice.
+    printf 'loa:\n  profile: full\n' > "$CFG"
+    run --separate-stderr env CACHE_DIR="$T/wscache" LOA_STATUS_RUN_DIR="$T/srun" LOA_STATUS_ENV_DIR="$T/env" \
+        LOA_STATUS_CONFIG_FILE="$CFG" timeout 120 bash "$R/.claude/scripts/loa-status.sh" --no-stale-check
+    line=$(printf '%s\n' "$output" | sed 's/\x1b\[[0-9;]*m//g' | grep '^Profile:')
+    [ "$line" = "Profile: full (explicit overrides: none)" ]
~~~~

## H55 — tests/unit/profile-lib.bats — insertion after head line 257

Head context (head/tests/unit/profile-lib.bats, lines 246–258):

~~~~text
   246 | @test "PL-17 the grep lint passes on the tree and catches a planted direct read" {
   247 |     run bash "$R/tools/check-knob-readers.sh" --root "$R"
   248 |     echo "$output"
   249 |     [ "$status" -eq 0 ]
   250 |     mkdir -p "$T/fx/.claude/data" "$T/fx/.claude/hooks" "$T/fx/tools"
   251 |     cp "$PROFILES" "$T/fx/.claude/data/profiles.yaml"
   252 |     printf '%s\n' "x=\$(yq '.guardrails.danger_level.enforce // true' c.yaml)" > "$T/fx/.claude/hooks/bad.sh"
   253 |     printf '%s\n' 'Skip when `guardrails.danger_level.enforce: false`.' > "$T/fx/.claude/hooks/prose.md"
   254 |     run bash "$R/tools/check-knob-readers.sh" --root "$T/fx"
   255 |     [ "$status" -eq 1 ]
   256 |     [[ "$output" == *"bad.sh:1"* ]]
   257 |     [[ "$output" != *"prose.md"* ]]
   258 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -257,0 +281,13 @@
+    # Bypass shapes (audit r256-5, DISS-C-005): a read split across a pipe and a bracket
+    # form that ends in the dotted tail are caught through the trailing-components alternation.
+    rm -f -- "$T/fx/.claude/hooks/bad.sh"
+    printf '%s\n' "y=\$(yq '.guardrails | .input.enabled' c.yaml)" > "$T/fx/.claude/hooks/pipe.sh"
+    printf '%s\n' "z=\$(yq '.[\"guardrails\"].danger_level.enforce' c.yaml)" > "$T/fx/.claude/hooks/bracket.sh"
+    run bash "$R/tools/check-knob-readers.sh" --root "$T/fx"
+    [ "$status" -eq 1 ]
+    [[ "$output" == *"pipe.sh:1"* ]]
+    [[ "$output" == *"bracket.sh:1"* ]]
+    # A fixture root without tools/ is searched without a misleading exit 2 (r256-3).
+    rm -rf -- "$T/fx/tools" "$T/fx/.claude/hooks/pipe.sh" "$T/fx/.claude/hooks/bracket.sh"
+    run bash "$R/tools/check-knob-readers.sh" --root "$T/fx"
+    [ "$status" -eq 0 ]
~~~~

## H56 — tools/check-knob-readers.sh — head lines 38–45

Head context (head/tools/check-knob-readers.sh, lines 26–51):

~~~~text
    26 |   case "$1" in
    27 |     --root) [[ $# -ge 2 ]] || { echo "check-knob-readers.sh: --root needs a directory" >&2; exit 2; }; ROOT="$2"; shift 2 ;;
    28 |     -h|--help) sed -n '/^# Usage:/,/^# Exit:/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    29 |     *) echo "check-knob-readers.sh: unknown arg $1" >&2; exit 2 ;;
    30 |   esac
    31 | done
    32 | PROFILES="$ROOT/.claude/data/profiles.yaml"
    33 | [[ -f "$PROFILES" ]] || { echo "check-knob-readers.sh: $PROFILES not found" >&2; exit 2; }
    34 | command -v yq >/dev/null 2>&1 || { echo "check-knob-readers.sh: yq v4 required" >&2; exit 2; }
    35 | 
    36 | keys=$(yq -r '.profiles[] | keys | .[]' "$PROFILES" | sort -u)
    37 | [[ -n "$keys" ]] || { echo "check-knob-readers.sh: no profile keys in $PROFILES" >&2; exit 2; }
>   38 | # Alternation of the dot-escaped keys; each must be preceded by a dot that is
>   39 | # not itself part of an identifier (start of line, quote, space, paren, ...).
>   40 | alt=$(printf '%s\n' "$keys" | sed 's/\./\\./g' | paste -sd'|' -)
>   41 | pattern="(^|[^A-Za-z0-9_])\\.(${alt})([^A-Za-z0-9_]|$)"
>   42 | 
>   43 | hits=$(cd "$ROOT" && grep -rnE "$pattern" .claude tools 2>/dev/null \
>   44 |   | grep -v -E '^(\./)?\.claude/scripts/lib/profile-lib\.sh:' \
>   45 |   | grep -v -E '^(\./)?tools/check-knob-readers\.sh:' || true)
    46 | if [[ -n "$hits" ]]; then
    47 |   echo "check-knob-readers.sh: direct read(s) of a profile key; use loa_knob from .claude/scripts/lib/profile-lib.sh:" >&2
    48 |   printf '%s\n' "$hits" | cut -c1-240 >&2
    49 |   exit 1
    50 | fi
    51 | echo "check-knob-readers.sh: no direct profile-key reads ($(printf '%s\n' "$keys" | wc -l | tr -d ' ') keys checked)"
~~~~

The change from head to the fix:

~~~~diff
@@ -38,8 +38,35 @@
-# Alternation of the dot-escaped keys; each must be preceded by a dot that is
-# not itself part of an identifier (start of line, quote, space, paren, ...).
-alt=$(printf '%s\n' "$keys" | sed 's/\./\\./g' | paste -sd'|' -)
-pattern="(^|[^A-Za-z0-9_])\\.(${alt})([^A-Za-z0-9_]|$)"
+# Alternation of the ERE-escaped keys (every metacharacter, not only the dot —
+# r256-2 LOW-9); each must be preceded by a dot that is not itself part of an
+# identifier (start of line, quote, space, paren, ...).
+alt=$(printf '%s\n' "$keys" | sed 's/[]^$.*+?(){}|[]/\\&/g' | paste -sd'|' -)
+# Also the trailing two components of every three-part key (`.input.enabled`,
+# `.danger_level.enforce`), so a read split across a pipe (`yq '.guardrails | .input.enabled'`)
+# or a bracket form that ends in the dotted tail is caught too (audit r256-5, DISS-C-005).
+suf=$(printf '%s\n' "$keys" | awk -F. 'NF>=3 {print $(NF-1)"."$NF}' | sort -u | sed 's/[]^$.*+?(){}|[]/\\&/g' | paste -sd'|' -)
+if [[ -n "$suf" ]]; then
+  pattern="(^|[^A-Za-z0-9_])\\.((${alt})|(${suf}))([^A-Za-z0-9_]|$)"
+else
+  pattern="(^|[^A-Za-z0-9_])\\.(${alt})([^A-Za-z0-9_]|$)"
+fi
 
-hits=$(cd "$ROOT" && grep -rnE "$pattern" .claude tools 2>/dev/null \
+# grep: -I skips binaries (no "Binary file matches" pseudo-hits); exit 1 is "no
+# match", exit 2 is a grep error (a bad pattern, an unreadable path) and is a
+# hard failure, never an empty hit list. Only directories that exist are
+# searched (.claude is required; tools/ is optional, a fixture root may lack it)
+# and grep's stderr is kept apart from its hits so the message quotes it.
+dirs=()
+for d in .claude tools; do [[ -d "$ROOT/$d" ]] && dirs+=("$d"); done
+[[ " ${dirs[*]} " == *" .claude "* ]] || { echo "check-knob-readers.sh: $ROOT/.claude not found" >&2; exit 2; }
+grc=0
+gerr="$(mktemp "${TMPDIR:-/tmp}/knob-readers.XXXXXX")"
+raw=$(cd "$ROOT" && grep -rnIE "$pattern" "${dirs[@]}" 2>"$gerr") || grc=$?
+if (( grc >= 2 )); then
+  echo "check-knob-readers.sh: grep failed (exit $grc): $(tr '\n' ' ' <"$gerr")" >&2
+  rm -f -- "$gerr"
+  exit 2
+fi
+rm -f -- "$gerr"
+hits=$(printf '%s\n' "$raw" \
   | grep -v -E '^(\./)?\.claude/scripts/lib/profile-lib\.sh:' \
-  | grep -v -E '^(\./)?tools/check-knob-readers\.sh:' || true)
+  | grep -v -E '^(\./)?tools/check-knob-readers\.sh:' \
+  | sed '/^$/d' || true)
~~~~
