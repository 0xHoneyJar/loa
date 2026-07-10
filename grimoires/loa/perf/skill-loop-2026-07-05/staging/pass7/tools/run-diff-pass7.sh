#!/usr/bin/env bash
# =============================================================================
# pass-7 differential corpus: OLD (repo working tree) vs NEW (staging/pass7)
# for karpathy-surgical-diff-check.sh under the state-aggregate cache design.
#
# Every case is a SEQUENCE of hook invocations against a growing (or mutated)
# .run/karpathy-task-state.jsonl. Per STEP we compare stdout/stderr/exit
# (ts/root/line-number-normalized); at the END we compare the full
# side-effect tree (state file bytes, trajectory JSONL) excluding ONLY
# .run/perf-cache (the documented additive side effect).
#
# Additionally, after every sequence the NEW side's cache is checked against
# the CONSISTENCY INVARIANT: cache lines (pois, nl, sum, set, token) must
# equal a fresh full-scan recomputation over the first <offset> bytes of the
# state file. A stale-but-consistent cache passes; a corrupt one fails the
# case even if outputs happened to match.
#
# Vacuity guard: the normalizer and the comparators are self-tested before
# any case runs (pass-6 lesson: a broken sed emptied the normalizer and
# silently passed everything).
# =============================================================================
set -u
export LC_ALL=C

REPO=/home/merlin/Documents/thj/code/loa
STAGE=$REPO/grimoires/loa/perf/skill-loop-2026-07-05/staging/pass7
WORK=${1:-/tmp/p7diff/work}
rm -rf "$WORK" && mkdir -p "$WORK"

PASS=0; FAIL=0
declare -a FAILURES=()

norm() {
  sed -E -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z/__TS__/g' \
         -e 's#'"$CASE_DIR"'/(old|new)#__SB__#g' \
         -e 's/line [0-9]+:/line __N__:/g'
}

# --- self-test the normalizer (vacuity guard) --------------------------------
CASE_DIR=/tmp/p7diff/selftest
_nt=$(printf 'x %s/old 2026-07-05T01:02:03Z line 42: y\n' "$CASE_DIR" | norm)
if [[ "$_nt" != "x __SB__ __TS__ line __N__: y" ]]; then
  echo "FATAL: normalizer self-test failed: '$_nt'" >&2
  exit 1
fi

mkpay() { # mkpay <tool> <file> <nlines>  -> payload on stdout
  local tool=$1 file=$2 n=$3 body="l" i
  for ((i=1;i<n;i++)); do body+='\nl'; done
  local field="new_string"
  [[ "$tool" == "Write" ]] && field="content"
  printf '{"tool_name":"%s","tool_input":{"file_path":"%s","%s":"%s"}}' \
    "$tool" "$file" "$field" "$body"
}

build_side() { # build_side <dir> <hook> [threshold]
  local d=$1 h=$2 thr=${3:-10}
  mkdir -p "$d/root/.claude/hooks/quality" "$d/root/.run" \
           "$d/root/grimoires/loa/a2a/trajectory" "$d/out"
  cp "$h" "$d/root/.claude/hooks/quality/karpathy-surgical-diff-check.sh"
  printf 'karpathy_principles:\n  surgical_diff_warning: warn\n  diff_lines_per_task: %s\n' \
    "$thr" > "$d/root/.loa.config.yaml"
}

# step engine ------------------------------------------------------------------
# call <n> <payload...>          run hook on both sides with payload on stdin
# call_env <n> <VAR=v...> -- <payload>
# both <cmd...>                  run a mutation command in each side's root
# The per-step comparison happens inside call.
STEP_FAIL=""
call() { # call <stepname> <payload-string> [extra env as VAR=val ...]
  local step=$1 payload=$2; shift 2
  local s rc
  for s in old new; do
    ( cd "$CASE_DIR/$s/root" && printf '%s' "$payload" | \
        env KARPATHY_STATE_CACHE_MIN=0 LOA_SESSION_ID="${SEQ_SID:-sess-1}" "$@" \
        bash .claude/hooks/quality/karpathy-surgical-diff-check.sh \
        > "../out/$step.stdout" 2> "../out/$step.stderr"
      echo $? > "$CASE_DIR/$s/out/$step.rc" )
  done
  local f
  for f in stdout stderr rc; do
    if ! diff <(norm < "$CASE_DIR/old/out/$step.$f") \
              <(norm < "$CASE_DIR/new/out/$step.$f") >/dev/null 2>&1; then
      STEP_FAIL+="[step $step $f] "
    fi
  done
}
both() { # both <bash -c command string>  (cwd = side root)
  local s
  for s in old new; do ( cd "$CASE_DIR/$s/root" && bash -c "$1" ); done
}

# final tree comparison ---------------------------------------------------------
tree_cmp() {
  local s f rel
  for s in old new; do
    ( cd "$CASE_DIR/$s/root" 2>/dev/null || exit 0
      find . -mindepth 1 \( -path ./.claude -o -path ./.run/perf-cache \) -prune -o -print \
        | sort | norm
      find . \( -path ./.claude -o -path ./.run/perf-cache \) -prune -o -type f -print \
        | sort | while IFS= read -r f; do
            printf '===== %s =====\n' "$(printf '%s' "$f" | norm)"
            norm < "$f" 2>/dev/null || printf '__UNREADABLE__\n'
          done
    ) > "$CASE_DIR/$s/out/__tree__"
  done
  diff "$CASE_DIR/old/out/__tree__" "$CASE_DIR/new/out/__tree__" >/dev/null 2>&1
}

# cache consistency invariant ---------------------------------------------------
# cache(pois,nl,sum,set,token) must equal a full-scan recomputation over the
# first <offset> bytes of the CURRENT state file (when the key matches it).
verify_cache() {
  local root=$CASE_DIR/new/root
  local cache=$root/.run/perf-cache/karpathy-state.v1.agg
  local state=${VC_STATE:-$root/.run/karpathy-task-state.jsonl}
  [[ -f "$cache" ]] || return 0            # no cache = nothing to verify
  local -a c
  mapfile -t c < "$cache"
  [[ "${#c[@]}" -eq 9 ]] || { echo "cache-shape"; return 1; }
  [[ -f "$state" ]] || return 0
  local id; id=$(stat -Lc '%d:%i' -- "$state" 2>/dev/null) || return 0
  [[ "${c[0]}" == "$id:"* ]] || return 0   # cache for another file: skip
  local off=${c[1]}
  [[ "$off" =~ ^[0-9]+$ ]] || { echo "cache-off"; return 1; }
  local sz; sz=$(stat -Lc '%s' -- "$state")
  [[ "$off" -le "$sz" ]] || { echo "cache-off-gt-size"; return 1; }
  head -c "$off" "$state" > "$CASE_DIR/vc.prefix"
  # recompute pois/nl/set with the ORIGINAL expressions
  local want
  want=$(jq -rn --rawfile s "$CASE_DIR/vc.prefix" '
    (try ($s | split("\n") | map(select(length > 0) | fromjson) | [.[].file // empty]) catch null) as $fs |
    (if $fs == null then "1" else "0" end),
    (($s | split("\n") | length) - 1 | tostring),
    (if $fs == null then "SKIP" else ($fs | unique | tojson) end)')
  local wpois wnl wset
  wpois=$(sed -n 1p <<<"$want"); wnl=$(sed -n 2p <<<"$want"); wset=$(sed -n 3p <<<"$want")
  local wsum
  wsum=$(awk -F'"lines_changed":' '/"lines_changed":/{n=$2+0; sum+=n} END{print sum+0}' "$CASE_DIR/vc.prefix")
  [[ "${c[3]}" == "$wpois" ]] || { echo "pois ${c[3]}!=$wpois"; return 1; }
  [[ "${c[4]}" == "$wnl" ]] || { echo "nl ${c[4]}!=$wnl"; return 1; }
  [[ "${c[5]}" == "$wsum" ]] || { echo "sum ${c[5]}!=$wsum"; return 1; }
  if [[ "$wset" != "SKIP" ]]; then
    [[ "${c[8]}" == "$wset" ]] || { echo "set"; return 1; }
    local wcnt; wcnt=$(jq -rn --argjson s "$wset" '$s | length')
    [[ "${c[6]}" == "$wcnt" ]] || { echo "count ${c[6]}!=$wcnt"; return 1; }
  fi
  # token must be the final line of the prefix
  local tl; tl=$(tail -n 1 "$CASE_DIR/vc.prefix")
  [[ "${c[7]}" == "$tl" ]] || { echo "token"; return 1; }
  # prefix must end on a line boundary
  [[ "$(tail -c 1 "$CASE_DIR/vc.prefix" | od -An -tx1 | tr -d ' \n')" == "0a" ]] || { echo "boundary"; return 1; }
  return 0
}

begin_case() { # begin_case <name> [threshold]
  CASE=$1
  CASE_DIR=$WORK/$1
  mkdir -p "$CASE_DIR"
  build_side "$CASE_DIR/old" "$REPO/.claude/hooks/quality/karpathy-surgical-diff-check.sh" "${2:-10}"
  build_side "$CASE_DIR/new" "$STAGE/karpathy-surgical-diff-check.sh" "${2:-10}"
  STEP_FAIL=""
  SEQ_SID="sess-1"
  VC_STATE=""
}
end_case() {
  local why=""
  tree_cmp || why+="[tree] "
  local vc; vc=$(verify_cache) || why+="[cache-invariant: $vc] "
  [[ -n "$STEP_FAIL" ]] && why+="$STEP_FAIL"
  if [[ -z "$why" ]]; then
    PASS=$((PASS+1)); echo "PASS  $CASE"
  else
    FAIL=$((FAIL+1)); FAILURES+=("$CASE: $why"); echo "FAIL  $CASE  $why"
  fi
}

P_EDIT3() { mkpay Edit "/src/f$1.md" 3; }

# =============================================================================
# CASES
# =============================================================================

# --- 1. 14-step growing sequence, warn regime (threshold 10) -----------------
begin_case seq-warn-14
for i in $(seq 1 14); do call "s$i" "$(P_EDIT3 $i)"; done
end_case

# --- 2. no-warn sequence (huge threshold), Write payloads --------------------
begin_case seq-nowarn-10 100000
for i in $(seq 1 10); do call "s$i" "$(mkpay Write /src/w$i.md 5)"; done
end_case

# --- 3. mixed tools + junk stdin mid-sequence ---------------------------------
begin_case seq-mixed
call s1 "$(P_EDIT3 1)"
call s2 "$(mkpay Write /src/w.md 4)"
call s3 "$(mkpay NotebookEdit /src/nb.ipynb 2)"
call s4 '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
call s5 'not json at all'
call s6 ''
call s7 '5'
call s8 "$(P_EDIT3 8)"
end_case

# --- 4. truncation mid-sequence ------------------------------------------------
begin_case seq-truncate
for i in 1 2 3 4; do call "s$i" "$(P_EDIT3 $i)"; done
both 'head -n 2 .run/karpathy-task-state.jsonl > .run/t && mv .run/t .run/karpathy-task-state.jsonl'
for i in 5 6 7; do call "s$i" "$(P_EDIT3 $i)"; done
end_case

# --- 5. rotation: replace with different same-size content (new inode) --------
begin_case seq-rotate
for i in 1 2 3; do call "s$i" "$(P_EDIT3 $i)"; done
both 'tr "0-9" "5" < .run/karpathy-task-state.jsonl > .run/rot && mv -f .run/rot .run/karpathy-task-state.jsonl' 2>/dev/null
both 'sed -e "s/lines_changed/lines_chonged/" .run/karpathy-task-state.jsonl > .run/rot && mv -f .run/rot .run/karpathy-task-state.jsonl'
for i in 4 5; do call "s$i" "$(P_EDIT3 $i)"; done
end_case

# --- 6. in-place same-size rewrite (same inode, mtime changes) -----------------
begin_case seq-rewrite-inplace
for i in 1 2 3; do call "s$i" "$(P_EDIT3 $i)"; done
both 'c=$(sed "s/f1/f9/" .run/karpathy-task-state.jsonl); printf "%s\n" "$c" > .run/karpathy-task-state.jsonl'
for i in 4 5; do call "s$i" "$(P_EDIT3 $i)"; done
end_case

# --- 7. external appends (delta path) ------------------------------------------
begin_case seq-ext-append
for i in 1 2; do call "s$i" "$(P_EDIT3 $i)"; done
both 'printf "%s\n" "{\"ts\":\"2026-07-05T00:00:00Z\",\"tool\":\"Edit\",\"file\":\"/ext/a.md\",\"lines_changed\":4,\"running_total\":0,\"session_id\":\"x\"}" >> .run/karpathy-task-state.jsonl'
call s3 "$(P_EDIT3 3)"
both 'for k in 1 2 3; do printf "%s\n" "{\"ts\":\"2026-07-05T00:00:00Z\",\"tool\":\"Write\",\"file\":\"/ext/b$k.md\",\"lines_changed\":2,\"running_total\":0,\"session_id\":\"x\"}" >> .run/karpathy-task-state.jsonl; done'
for i in 4 5 6; do call "s$i" "$(P_EDIT3 $i)"; done
end_case

# --- 8. malformed lines in the delta (strtod + poison semantics) ---------------
begin_case seq-malformed-delta
for i in 1 2; do call "s$i" "$(P_EDIT3 $i)"; done
both 'printf "%s\n" "{\"lines_changed\":12" >> .run/karpathy-task-state.jsonl'          # truncated JSON, digit prefix
call s3 "$(P_EDIT3 3)"
both 'printf "%s\n" "garbage\"lines_changed\": 42,\"x" >> .run/karpathy-task-state.jsonl' # strtod leading space
call s4 "$(P_EDIT3 4)"
both 'printf "%s\n" "{\"lines_changed\":}" >> .run/karpathy-task-state.jsonl'            # empty numeric field
both 'printf "%s\n" " " >> .run/karpathy-task-state.jsonl'                                # whitespace-only line
both 'printf "%s\n" "null" >> .run/karpathy-task-state.jsonl'                             # JSON scalar line
call s5 "$(P_EDIT3 5)"
both 'printf "%s\n" "{\"file\":123,\"lines_changed\":1}" >> .run/karpathy-task-state.jsonl' # non-string .file
call s6 "$(P_EDIT3 6)"
call s7 "$(P_EDIT3 7)"
end_case

# --- 9. non-integral running total: identical arithmetic death ------------------
begin_case seq-float-death 1000000
call s1 "$(P_EDIT3 1)"
both 'printf "%s\n" "x\"lines_changed\":7.5" >> .run/karpathy-task-state.jsonl'
call s2 "$(P_EDIT3 2)"
call s3 "$(P_EDIT3 3)"
end_case

# --- 10. unterminated final line (glue), incl. valid-JSON partial --------------
begin_case seq-glue
for i in 1 2; do call "s$i" "$(P_EDIT3 $i)"; done
both 'printf "%s" "{\"file\":\"/part/x.md\",\"lines_changed\":5}" >> .run/karpathy-task-state.jsonl'
call s3 "$(P_EDIT3 3)"
call s4 "$(P_EDIT3 4)"
both 'printf "%s" "partial-not-json" >> .run/karpathy-task-state.jsonl'
call s5 "$(P_EDIT3 5)"
call s6 "$(P_EDIT3 6)"
end_case

# --- 11. unicode payloads + unicode/NUL lines in delta --------------------------
begin_case seq-unicode
call s1 "$(mkpay Edit '/src/café-émoji-🦋.md' 3)"
call s2 "$(mkpay Write '/src/日本語パス.md' 4)"
both 'printf "%s\n" "{\"ts\":\"t\",\"tool\":\"Edit\",\"file\":\"/ext/naïve-Ω.md\",\"lines_changed\":2,\"running_total\":0,\"session_id\":\"x\"}" >> .run/karpathy-task-state.jsonl'
call s3 "$(mkpay Edit '/src/café-émoji-🦋.md' 2)"
both 'printf "a\000b\n" >> .run/karpathy-task-state.jsonl'
call s4 "$(P_EDIT3 4)"
call s5 "$(P_EDIT3 5)"
end_case

# --- 12. invalid UTF-8 bytes in delta (FFFD anomaly path) -----------------------
begin_case seq-badutf8
for i in 1 2; do call "s$i" "$(P_EDIT3 $i)"; done
both 'printf "\377\376bad\n" >> .run/karpathy-task-state.jsonl'
call s3 "$(P_EDIT3 3)"
call s4 "$(P_EDIT3 4)"
end_case

# --- 13. state deleted mid-sequence ---------------------------------------------
begin_case seq-delete
for i in 1 2 3; do call "s$i" "$(P_EDIT3 $i)"; done
both 'rm -f .run/karpathy-task-state.jsonl'
for i in 4 5 6; do call "s$i" "$(P_EDIT3 $i)"; done
end_case

# --- 14. state unreadable mid-sequence ------------------------------------------
begin_case seq-unreadable
for i in 1 2; do call "s$i" "$(P_EDIT3 $i)"; done
both 'chmod 000 .run/karpathy-task-state.jsonl'
call s3 "$(P_EDIT3 3)"
both 'chmod 600 .run/karpathy-task-state.jsonl'
call s4 "$(P_EDIT3 4)"
call s5 "$(P_EDIT3 5)"
end_case

# --- 15. empty state file start --------------------------------------------------
begin_case seq-empty-start
both ': > .run/karpathy-task-state.jsonl'
for i in 1 2 3; do call "s$i" "$(P_EDIT3 $i)"; done
end_case

# --- 16. corrupt cache variants (new side only; old has no cache) ----------------
begin_case seq-corrupt-cache
for i in 1 2; do call "s$i" "$(P_EDIT3 $i)"; done
CN=$CASE_DIR/new/root/.run/perf-cache/karpathy-state.v1.agg
printf '\x00\x01\x02garbage' > "$CN";                        call s3 "$(P_EDIT3 3)"
head -n 4 "$CN" > "$CN.t" 2>/dev/null; mv -f "$CN.t" "$CN";  call s4 "$(P_EDIT3 4)"
{ cat "$CN"; printf '\nextra\n'; } > "$CN.t"; mv -f "$CN.t" "$CN"; call s5 "$(P_EDIT3 5)"
# bad numerics / bad set / oversized offset (9-line format)
mapfile -t CC < "$CN" 2>/dev/null || CC=()
printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s' "${CC[0]:-k}" "99999999" "${CC[2]:-m}" "0" "3" "9" "1" "tok" "[]" > "$CN"
call s6 "$(P_EDIT3 6)"
printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s' "${CC[0]:-k}" "12" "${CC[2]:-m}" "x" "3" "9" "1" "tok" "notaset" > "$CN"
call s7 "$(P_EDIT3 7)"
call s8 "$(P_EDIT3 8)"
end_case

# --- 17. cache pathologies: dir / unreadable / RO dir ----------------------------
begin_case seq-cache-patho
call s1 "$(P_EDIT3 1)"
CN=$CASE_DIR/new/root/.run/perf-cache/karpathy-state.v1.agg
rm -f "$CN"; mkdir -p "$CN";                    call s2 "$(P_EDIT3 2)"
rmdir "$CN" 2>/dev/null || rm -rf "$CN";        call s3 "$(P_EDIT3 3)"
chmod 000 "$CN" 2>/dev/null;                    call s4 "$(P_EDIT3 4)"
chmod 600 "$CN" 2>/dev/null
chmod 500 "$CASE_DIR/new/root/.run/perf-cache"; call s5 "$(P_EDIT3 5)"
chmod 700 "$CASE_DIR/new/root/.run/perf-cache"
call s6 "$(P_EDIT3 6)"
end_case

# --- 18. cross-file contamination (two state paths, one cache) -------------------
begin_case seq-crossfile
call s1 "$(P_EDIT3 1)"
call s2 "$(P_EDIT3 2)" KARPATHY_TASK_STATE=.run/alt-state.jsonl
call s3 "$(P_EDIT3 3)"
call s4 "$(P_EDIT3 4)" KARPATHY_TASK_STATE=.run/alt-state.jsonl
call s5 "$(P_EDIT3 5)"
VC_STATE=""
end_case

# --- 19. leading-zero threshold (007) with warm cache ----------------------------
begin_case seq-thr007 007
for i in 1 2 3 4; do call "s$i" "$(P_EDIT3 $i)"; done
end_case

# --- 20. LOA_SESSION_ID unset (USER-derived session id) --------------------------
begin_case seq-nosid
SEQ_SID=""
for i in 1 2 3; do call "s$i" "$(P_EDIT3 $i)" LOA_SESSION_ID= USER=tester; done
end_case

# --- 21. oversized unique-file set: permanent full-scan --------------------------
begin_case seq-bigset 1000000
longp() { printf '/very/long/path/%03d/' "$1"; printf 'x%.0s' $(seq 1 90); printf '%03d.md' "$1"; }
# seed 750 unique ~110-char paths directly into state (identical both sides)
both 'for k in $(seq 1 750); do printf "{\"ts\":\"t\",\"tool\":\"Edit\",\"file\":\"/very/long/path/p%04d/xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx%04d.md\",\"lines_changed\":1,\"running_total\":0,\"session_id\":\"x\"}\n" $k $k; done >> .run/karpathy-task-state.jsonl'
call s1 "$(P_EDIT3 1)"
call s2 "$(P_EDIT3 2)"
if [[ -f $CASE_DIR/new/root/.run/perf-cache/karpathy-state.v1.agg ]]; then
  STEP_FAIL+="[oversize-set: cache exists] "
fi
end_case

# --- 22. token >1024 bytes: cache write skipped ----------------------------------
begin_case seq-bigtoken 1000000
BIGP="/p/$(printf 'y%.0s' $(seq 1 1200)).md"
call s1 "$(mkpay Edit "$BIGP" 2)"
if [[ -f $CASE_DIR/new/root/.run/perf-cache/karpathy-state.v1.agg ]]; then
  STEP_FAIL+="[bigtoken: cache exists] "
fi
call s2 "$(P_EDIT3 2)"
call s3 "$(P_EDIT3 3)"
end_case

# --- 23. EVAL_ERR payload with warm cache ----------------------------------------
begin_case seq-evalerr
for i in 1 2; do call "s$i" "$(P_EDIT3 $i)"; done
call s3 '5'
call s4 '[1,2]'
call s5 "$(P_EDIT3 5)"
end_case

# --- 24. forged cache with matching key (ACCEPTED DIVERGENCE, asserted) ----------
# Anyone able to write .run/perf-cache can already write the state file itself
# (same trust domain — header note). A forged cache whose key+token match the
# live file IS served. We assert the documented behavior explicitly rather
# than diffing old-vs-new.
begin_case seq-forged-cache 10
call s1 "$(P_EDIT3 1)"
CN=$CASE_DIR/new/root/.run/perf-cache/karpathy-state.v1.agg
if [[ -f "$CN" ]]; then
  mapfile -t FC < "$CN"
  printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s' \
    "${FC[0]}" "${FC[1]}" "${FC[2]}" "${FC[3]}" "${FC[4]}" "999" "${FC[6]}" "${FC[7]}" "${FC[8]}" > "$CN"
  ( cd "$CASE_DIR/new/root" && printf '%s' "$(P_EDIT3 2)" | KARPATHY_STATE_CACHE_MIN=0 LOA_SESSION_ID=sess-1 \
      bash .claude/hooks/quality/karpathy-surgical-diff-check.sh >/dev/null 2> "$CASE_DIR/forged.err" )
  grep -q "total 1002 lines" "$CASE_DIR/forged.err" || STEP_FAIL+="[forged-sum-not-served] "
else
  STEP_FAIL+="[no-cache-to-forge] "
fi
# old side: keep step counts equal for the tree compare? No — this case skips
# tree/cache comparison entirely (documented divergence assertion only).
if [[ -z "$STEP_FAIL" ]]; then
  PASS=$((PASS+1)); echo "PASS  seq-forged-cache (accepted-divergence asserted)"
else
  FAIL=$((FAIL+1)); FAILURES+=("seq-forged-cache: $STEP_FAIL"); echo "FAIL  seq-forged-cache  $STEP_FAIL"
fi

# --- 25. concurrent stress (new side only): cache never corrupt ------------------
begin_case seq-concurrent
call s1 "$(P_EDIT3 1)"
( cd "$CASE_DIR/new/root"
  for p in 1 2 3 4; do
    ( for k in 1 2 3 4 5; do
        printf '%s' "$(mkpay Edit "/con/p$p-$k.md" 2)" | KARPATHY_STATE_CACHE_MIN=0 LOA_SESSION_ID=sess-1 \
          bash .claude/hooks/quality/karpathy-surgical-diff-check.sh >/dev/null 2>&1
      done ) &
  done
  wait )
# mirror the same 20 appends on the old side SEQUENTIALLY so final line counts
# match is NOT expected — skip tree compare; assert: line count == 21 and the
# cache invariant holds (stale-but-consistent allowed).
NLINES=$(grep -c '' "$CASE_DIR/new/root/.run/karpathy-task-state.jsonl")
[[ "$NLINES" == "21" ]] || STEP_FAIL+="[concurrent-lines=$NLINES] "
vc=$(verify_cache) || STEP_FAIL+="[cache-invariant: $vc] "
# one more sequential call must produce a total equal to full-scan expectation:
# 1*3 + 20*2 + 3 = 46
( cd "$CASE_DIR/new/root" && printf '%s' "$(P_EDIT3 99)" | KARPATHY_STATE_CACHE_MIN=0 LOA_SESSION_ID=sess-1 \
    bash .claude/hooks/quality/karpathy-surgical-diff-check.sh >/dev/null 2> "$CASE_DIR/con.err" )
grep -q "total 46 lines" "$CASE_DIR/con.err" || STEP_FAIL+="[concurrent-total] "
if [[ -z "$STEP_FAIL" ]]; then
  PASS=$((PASS+1)); echo "PASS  seq-concurrent (invariant + total)"
else
  FAIL=$((FAIL+1)); FAILURES+=("seq-concurrent: $STEP_FAIL"); echo "FAIL  seq-concurrent  $STEP_FAIL"
fi

# --- 26. relative KARPATHY_TASK_STATE path ---------------------------------------
begin_case seq-relpath
for i in 1 2 3; do call "s$i" "$(P_EDIT3 $i)" KARPATHY_TASK_STATE=.run/rel-state.jsonl; done
VC_STATE=$CASE_DIR/new/root/.run/rel-state.jsonl
end_case

# --- 27. missing state dir (mkdir path) ------------------------------------------
begin_case seq-nodir
both 'rm -rf .run'
for i in 1 2 3; do call "s$i" "$(P_EDIT3 $i)"; done
end_case

# --- 28. .run read-only: append fails ---------------------------------------------
begin_case seq-ro-run
call s1 "$(P_EDIT3 1)"
both 'chmod 500 .run'
call s2 "$(P_EDIT3 2)"
both 'chmod 700 .run'
call s3 "$(P_EDIT3 3)"
end_case

# --- 29. delta immediately after external truncate-to-zero ------------------------
begin_case seq-trunc-zero
for i in 1 2; do call "s$i" "$(P_EDIT3 $i)"; done
both ': > .run/karpathy-task-state.jsonl'
call s3 "$(P_EDIT3 3)"
call s4 "$(P_EDIT3 4)"
end_case

# --- 30. same-size flip with SAME mtime (touch -d): trust-domain divergence -------
# Same accepted posture as pass-6: an mtime+size-preserving rewrite is a
# deliberate forgery within the trust domain. Asserted, not diffed.
begin_case seq-mtime-forge 1
call s1 "$(P_EDIT3 1)"
call s2 "$(P_EDIT3 2)"
NST=$CASE_DIR/new/root/.run/karpathy-task-state.jsonl
MT=$(stat -Lc '%y' "$NST")
sed 's/f1/f8/' "$NST" > "$NST.t" && cat "$NST.t" > "$NST" && rm -f "$NST.t"
touch -d "$MT" "$NST"
( cd "$CASE_DIR/new/root" && printf '%s' "$(P_EDIT3 3)" | KARPATHY_STATE_CACHE_MIN=0 LOA_SESSION_ID=sess-1 \
    bash .claude/hooks/quality/karpathy-surgical-diff-check.sh >/dev/null 2> "$CASE_DIR/mt.err" )
# FAST path serves cached aggregates (f1-era set) — documented; total still 9
grep -q "total 9 lines" "$CASE_DIR/mt.err" || STEP_FAIL+="[mtime-forge-total] "
if [[ -z "$STEP_FAIL" ]]; then
  PASS=$((PASS+1)); echo "PASS  seq-mtime-forge (accepted-divergence asserted)"
else
  FAIL=$((FAIL+1)); FAILURES+=("seq-mtime-forge: $STEP_FAIL"); echo "FAIL  seq-mtime-forge  $STEP_FAIL"
fi

# --- 31. DEFAULT size gate: small state stays on the original path ----------------
# (call() pins KARPATHY_STATE_CACHE_MIN=0 for every other case so warm paths
# are exercised; this case runs with the production default of 262144.)
begin_case seq-gate-default
for i in 1 2 3 4; do
  for s in old new; do
    ( cd "$CASE_DIR/$s/root" && printf '%s' "$(P_EDIT3 $i)" | \
        env LOA_SESSION_ID=sess-1 \
        bash .claude/hooks/quality/karpathy-surgical-diff-check.sh \
        > "../out/g$i.stdout" 2> "../out/g$i.stderr"
      echo $? > "$CASE_DIR/$s/out/g$i.rc" )
  done
  for f in stdout stderr rc; do
    diff <(norm < "$CASE_DIR/old/out/g$i.$f") <(norm < "$CASE_DIR/new/out/g$i.$f") >/dev/null 2>&1 \
      || STEP_FAIL+="[step g$i $f] "
  done
done
if [[ -f "$CASE_DIR/new/root/.run/perf-cache/karpathy-state.v1.agg" ]]; then
  STEP_FAIL+="[gate-default: cache written below gate] "
fi
end_case

# --- 32. gate boundary: file crossing the gate starts caching ---------------------
begin_case seq-gate-cross 1000000
both 'for k in $(seq 1 300); do printf "{\"ts\":\"t\",\"tool\":\"Edit\",\"file\":\"/g/f%03d.md\",\"lines_changed\":3,\"running_total\":0,\"session_id\":\"x\"}\n" $((k % 40)) ; done >> .run/karpathy-task-state.jsonl'
for i in 1 2 3; do
  for s in old new; do
    ( cd "$CASE_DIR/$s/root" && printf '%s' "$(P_EDIT3 $i)" | \
        env KARPATHY_STATE_CACHE_MIN=20000 LOA_SESSION_ID=sess-1 \
        bash .claude/hooks/quality/karpathy-surgical-diff-check.sh \
        > "../out/x$i.stdout" 2> "../out/x$i.stderr"
      echo $? > "$CASE_DIR/$s/out/x$i.rc" )
  done
  for f in stdout stderr rc; do
    diff <(norm < "$CASE_DIR/old/out/x$i.$f") <(norm < "$CASE_DIR/new/out/x$i.$f") >/dev/null 2>&1 \
      || STEP_FAIL+="[step x$i $f] "
  done
done
if [[ ! -f "$CASE_DIR/new/root/.run/perf-cache/karpathy-state.v1.agg" ]]; then
  STEP_FAIL+="[gate-cross: no cache above gate] "
fi
end_case

# =============================================================================
echo "----------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${FAILURES[@]}"
  exit 1
fi
exit 0
