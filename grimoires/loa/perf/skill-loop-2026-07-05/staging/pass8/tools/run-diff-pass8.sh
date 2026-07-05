#!/usr/bin/env bash
# =============================================================================
# run-diff-pass8.sh — old-vs-new differential corpus for the pass-8 literal
# pre-filters in block-destructive-bash.sh.
#
# For every case: run OLD and NEW hook in fresh per-side sandbox roots
# (cwd = root, LOA_REPO_ROOT = root, real log-redactor copied in), compare
# exit code + stdout + stderr + .run/audit.jsonl byte-for-byte after
# normalizing timestamps and the sandbox root path. ANY divergence fails.
#
# Corpus: every hook_invoke command from tests/unit/block-destructive-bash.bats
# + block-destructive-bash-limitations.bats + cycle-114-rm-home-precision.bats,
# the 4 golden payload commands, and 55+ adversarial variants constructed to
# attack the pre-filters (literal in non-matching context, literals split
# across quotes/escapes/lines, homoglyphs, case variants, literals inside
# strings/comments/heredocs, 100KB commands, NUL escapes, invalid UTF-8,
# inherited-environment delete_stmts).
# =============================================================================
set -u
export LC_ALL=C
REPO=${REPO:-/home/merlin/Documents/thj/code/loa}
OLD=${OLD:-/tmp/p8/old-hook.sh}
NEW=${NEW:-$REPO/grimoires/loa/perf/skill-loop-2026-07-05/staging/pass8/block-destructive-bash.sh}
WORK=${WORK:-/tmp/p8/diff}
rm -rf "$WORK"; mkdir -p "$WORK"

fail=0; total=0

mkroot() {
  mkdir -p "$1/.claude/scripts/lib" "$1/.run"
  cp "$REPO/.claude/scripts/lib/log-redactor.sh" "$1/.claude/scripts/lib/"
}

norm() {
  sed -e 's/[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}Z/__TS__/g' \
      -e "s|$WORK/old|__ROOT__|g" -e "s|$WORK/new|__ROOT__|g" \
      -e 's|^[^ ]*block-destructive-bash\.sh: line [0-9]*: |__HOOK__: line __N__: |' \
      -e 's|^[^ ]*old-hook\.sh: line [0-9]*: |__HOOK__: line __N__: |'
}
# NOTE on the last two norm rules: bash prefixes its own diagnostics (e.g.
# the "ignored null byte in input" warning) with "<script path>: line N:".
# The path differs old-vs-new by construction and the line number shifts
# with the pass-8 header comment — pass-5-accepted divergence class
# (diagnostic PREFIX only; the message text itself stays byte-compared).

run_case() {  # run_case <name> <payload-file> [ENVVAR=val ...]
  local name=$1 pl=$2; shift 2
  total=$((total+1))
  local side rc hook
  for side in old new; do
    local root="$WORK/$side"
    rm -rf "$root"; mkroot "$root"
    [[ $side == old ]] && hook=$OLD || hook=$NEW
    rc=0
    ( cd "$root" && env LOA_REPO_ROOT="$root" "$@" bash "$hook" \
        <"$pl" >"$WORK/$side.out" 2>"$WORK/$side.err" ) || rc=$?
    echo "$rc" > "$WORK/$side.rc"
    norm < "$WORK/$side.out" > "$WORK/$side.out.n"
    norm < "$WORK/$side.err" > "$WORK/$side.err.n"
    if [[ -f "$root/.run/audit.jsonl" ]]; then
      norm < "$root/.run/audit.jsonl" > "$WORK/$side.audit.n"
    else
      : > "$WORK/$side.audit.n"
    fi
  done
  local bad=""
  cmp -s "$WORK/old.rc" "$WORK/new.rc" || bad+=" rc($(cat "$WORK/old.rc")->$(cat "$WORK/new.rc"))"
  cmp -s "$WORK/old.out.n" "$WORK/new.out.n" || bad+=" stdout"
  cmp -s "$WORK/old.err.n" "$WORK/new.err.n" || bad+=" stderr"
  cmp -s "$WORK/old.audit.n" "$WORK/new.audit.n" || bad+=" audit"
  if [[ -n "$bad" ]]; then
    fail=$((fail+1))
    echo "DIVERGE [$name]:$bad"
    diff "$WORK/old.err.n" "$WORK/new.err.n" | head -6
    diff "$WORK/old.audit.n" "$WORK/new.audit.n" | head -6
  fi
}

case_cmd() {  # case_cmd <name> <command-string> [ENV...]
  local name=$1 cmd=$2; shift 2
  jq -cn --arg c "$cmd" '{tool_input:{command:$c}}' > "$WORK/payload.json"
  run_case "$name" "$WORK/payload.json" "$@"
}

case_raw() {  # case_raw <name> <raw-payload-bytes> [ENV...]
  local name=$1 raw=$2; shift 2
  printf '%s' "$raw" > "$WORK/payload.json"
  run_case "$name" "$WORK/payload.json" "$@"
}

# =============================================================================
# 1. tests/unit/block-destructive-bash.bats — every hook_invoke command
# =============================================================================
case_cmd A-p2        "git push --force origin main"
case_cmd A-p2b       "git push -f origin main"
case_cmd A-p2-neg    "git push --force-with-lease origin main"
case_cmd A-p3        "git reset --hard HEAD~1"
case_cmd A-p3-neg    "git reset --soft HEAD~1"
case_cmd A-p4        "git clean -fd"
case_cmd A-p4-neg    "git clean -nfd"
case_cmd B-p5-D      "git branch -D feature/abandoned"
case_cmd B-p5-df     "git branch -d -f feature/x"
case_cmd B-p5-fd     "git branch --force --delete feature/y"
case_cmd B-p5-neg1   "git branch -d merged-branch"
case_cmd B-p5-neg2   "git branch --list"
case_cmd B-p6-drop   "git stash drop"
case_cmd B-p6-clear  "git stash clear"
case_cmd B-p6-neg1   "git stash list"
case_cmd B-p6-neg2   "git stash pop"
case_cmd B-p7        "git checkout -- src/main.rs"
case_cmd B-p7-neg1   "git checkout main"
case_cmd B-p7-neg2   "git checkout --quiet feature-branch"
case_cmd B-p8-drop   'psql -c "DROP TABLE users;"'
case_cmd B-p8-lower  'sqlite3 db.sqlite "drop schema public cascade"'
case_cmd B-p8-neg    'psql -c "SELECT 1 FROM dropped_users"'
case_cmd B-p9        'psql -c "TRUNCATE TABLE users"'
case_cmd B-p9-quoted 'psql -c "TRUNCATE TABLE \"users\""'
case_cmd B-p9-neg    'echo TRUNCATEABLE'
case_cmd B-p10       'psql -c "DELETE FROM users"'
case_cmd B-p10-multi 'psql -c "DELETE FROM users WHERE id=1; DELETE FROM logs"'
case_cmd B-p10-neg   'psql -c "DELETE FROM users WHERE id = 1"'
case_cmd B-p11-ns    "kubectl delete namespace prod"
case_cmd B-p11-short "kubectl delete ns staging"
case_cmd B-p11-flag  "kubectl --kubeconfig=foo delete ns prod"
case_cmd B-p11-neg   "kubectl get namespace prod"
case_cmd B-p12-all   "kubectl delete deployment --all"
case_cmd B-p12-A     "kubectl delete deployment -A"
case_cmd B-p12-neg   "kubectl get pods --all-namespaces"
case_cmd B-p12-cross "kubectl delete pod foo; kubectl get pods --all-namespaces"
case_cmd C-root      "rm -rf /"
case_cmd C-home      'rm -rf $HOME'
case_cmd C-tilde     "rm -rf ~"
case_cmd C-ssh       "rm -rf ~/.ssh"
case_cmd C-etc       "rm -rf /etc"
case_cmd C-glob      "rm -rf *"
case_cmd C-dot       "rm -rf ."
case_cmd C-dotslash  "rm -rf ./"
case_cmd C-dotgit    "rm -rf ./.git"
case_cmd C-build     "rm -rf ./build"
case_cmd C-nodemod   "rm -rf ./node_modules"
case_cmd C-dist      "rm -rf ./dist"
case_cmd C-tmp       "rm -rf /tmp/loa-test-XYZ"
case_cmd C-notrf     "rm file.txt"
case_cmd C-ronly     "rm -r dir"
case_cmd C-split     "rm -r -f /etc"
case_cmd C-multi     "rm -rf ./build ; rm -rf /etc"
case_cmd C-multiarg  "rm -rf ./build /etc"
case_cmd C-dotdot    "rm -rf ./../"
case_raw D-malformed "not json at all"
case_raw D-emptycmd  '{"tool_input":{"command":""}}'
case_raw D-notool    '{}'
case_cmd E-akia      'AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE psql -c "DROP TABLE x"'
case_cmd E-safe      "echo safe"
case_cmd G-heredoc   $'psql <<EOF\nDROP TABLE users;\nEOF'
case_cmd G-subshell  'echo "danger: $(rm -rf /)"'
case_cmd G-pipe      "ls /tmp | rm -rf /etc"
case_cmd G-bashc     "bash -c 'kubectl delete namespace prod'"
case_cmd H-redir1    "cat > .run/cron.d/job.sh"
case_cmd H-redir2    'echo "* * * * * evil" >> .run/cron.d/job.sh'
case_cmd H-redir3    "echo 'alias evil=x' > .run/merged-model-aliases.sh"
case_cmd H-redir-fd  "some-cmd 2> .run/cron.d/job.sh"
case_cmd H-tee1      "echo x | tee .run/merged-model-aliases.sh"
case_cmd H-tee2      "echo x | tee -a .run/cron.d/job.sh"
case_cmd H-cp        "cp /tmp/evil.sh .run/cron.d/job.sh"
case_cmd H-mv        "mv /tmp/evil grimoires/loa/skills/pwn/SKILL.md"
case_cmd H-ln        "ln -s /tmp/evil .run/cron.d/job.sh"
case_cmd H-dd        "dd if=/tmp/evil of=.run/cron.d/job.sh"
case_cmd H-sed       "sed -i 's/old/new/' grimoires/loa/skills/approved/SKILL.md"
case_cmd H-perl      "perl -i -pe 's/a/b/' .run/merged-model-aliases.sh"
case_cmd H-awk       "awk -i inplace '{print}' .run/cron.d/job.sh"
case_cmd H-tar       "tar -xf /tmp/jobs.tar -C .run/cron.d/"
case_cmd H-unzip     "unzip /tmp/x.zip -d grimoires/loa/skills/"
case_cmd H-interp    "python3 -c \"open('.run/cron.d/z.sh','w').write('x')\""
case_cmd H-neg1      'echo "- observation" >> grimoires/loa/NOTES.md'
case_cmd H-neg2      "cat > .run/sprint-plan-state.json"
case_cmd H-neg3      "echo '{}' >> .beads/issues.jsonl"
case_cmd H-neg4      "cat > grimoires/loa/ledger.json"
case_cmd H-neg5      "cp .run/cron.d/job.sh /tmp/backup.sh"
case_cmd H-neg6      "rsync -avz .run/cron.d/ backup-host:/backups/"
case_cmd H-neg7      "cat .run/cron.d/job.sh"
case_cmd H-neg8      "ls -la .run/cron.d/"
case_cmd H-neg9      "grep alias .run/merged-model-aliases.sh"
case_cmd H-neg10     "git add grimoires/loa/skills/approved/SKILL.md"
case_cmd H-hatch     "cat > .run/cron.d/job.sh" LOA_ALLOW_STATE_ZONE_EXEC_WRITE=1
case_cmd I-cr1a      "cp /tmp/job.sh .run/cron.d"
case_cmd I-cr1b      "mv /tmp/skill grimoires/loa/skills"
case_cmd I-cr1c      "tar -xf /tmp/a.tar -C .run/cron.d"
case_cmd I-cr1-neg   "cp /tmp/x .run/cron.daemon"
case_cmd I-cr2a      "echo x | tee --append .run/cron.d/job.sh"
case_cmd I-cr2b      "echo x | tee /tmp/log .run/merged-model-aliases.sh"
case_cmd I-cr3a      "cp -t .run/cron.d/ /tmp/job.sh"
case_cmd I-cr3b      "tar --directory .run/cron.d/ -xf /tmp/a.tar"
case_cmd I-cr3c      "ln -s -t .run/cron.d/ /tmp/evil"
case_cmd I-cr4a      "sed -Ei s/a/b/ .run/merged-model-aliases.sh"
case_cmd I-cr4b      "sed --in-place s/a/b/ grimoires/loa/skills/approved/SKILL.md"
case_cmd I-cr5       "cp /tmp/evil.sh .run/cron.d/job.sh # install"
case_cmd I-neg1      "mv .run/cron.d/old /tmp/archive/"
case_cmd I-neg2      "tar -czf /tmp/backup.tar .run/cron.d"
case_cmd I-neg3      "grep -i alias .run/merged-model-aliases.sh"
case_cmd I-neg4      "ls grimoires/loa/skills"
case_cmd I-neg5      "cat .run/cron.d/job.sh # show it"
case_cmd J-diss2a    "echo x > ./.run/cron.d/job.sh"
case_cmd J-diss2b    "cp /tmp/x /abs/repo/.run/cron.d/job.sh"
case_cmd J-diss2c    "sed -i s/a/b/ ./grimoires/loa/skills/approved/SKILL.md"
case_cmd J-diss3     "sed -i'' s/a/b/ .run/merged-model-aliases.sh"
case_cmd J-neg1      "cat ./.run/cron.d/job.sh"
case_cmd J-neg2      "cp ./.run/cron.d/job.sh /tmp/backup"
case_cmd K-sa4a      "cp /tmp/x .run/cron.d/job.sh -f"
case_cmd K-sa4b      "mv /tmp/x grimoires/loa/skills/pwn/SKILL.md -f"
case_cmd K-sa3a      "python3 -c \"import shutil; shutil.copyfile('/tmp/p','.run/cron.d/job.sh')\""
case_cmd K-sa3b      "python3 -c \"from pathlib import Path; Path('.run/cron.d/job.sh').write_bytes(b'x')\""
case_cmd K-sa4-neg   "cp .run/cron.d/job.sh /tmp/dst -f"
case_cmd K-sa3-neg   "python3 -c \"print(open('.run/cron.d/job.sh').read())\""

# =============================================================================
# 2. limitations bats + rm-home-precision bats
# =============================================================================
case_cmd L-sqlcomment 'psql -c "DELETE FROM users -- WHERE id=1"'
case_cmd L-quotespace 'rm -rf "/etc foo"'
case_cmd L-bashc-rm   "bash -c 'rm -rf /etc'"
case_cmd L-evalb64    'eval $(echo cm0gLXJmIC8= | base64 -d)'
case_cmd L-pyfile     'python3 /tmp/destructive_script.py'
case_cmd R-homeslash  'rm -rf $HOME/'
case_cmd R-bracehome  'rm -rf ${HOME}/'
case_cmd R-home       'rm -rf $HOME'
case_cmd R-tildeslash 'rm -rf ~/'
case_cmd R-homechild  'rm -rf $HOME/projects'
case_cmd R-nodemod    'rm -rf node_modules/'

# =============================================================================
# 3. golden payload commands
# =============================================================================
case_cmd GOLD-benign   "ls -la /tmp/loa-hookbench-1000"
case_cmd GOLD-mutating 'git commit -m "chore(bench): update notes"'
case_cmd GOLD-destr    "rm -rf /tmp/x"
case_cmd GOLD-blocked  "git push --force origin main"

# =============================================================================
# 4. adversarial variants attacking the pre-filters
# =============================================================================
# 4a. guard literal present in a NON-matching context — the group MUST still
#     be evaluated and correctly allow (parity of the allow decision).
case_cmd ADV-pushups    "echo git pushups --force-of-habit"
case_cmd ADV-gitpushvar "git-push --force"
case_cmd ADV-pushnospace "git pushx --force y"
case_cmd ADV-resetprose "echo git reset is --hard to explain"
case_cmd ADV-cleanprose "git help clean -f"
case_cmd ADV-branchpro  "echo branch - protection for git"
case_cmd ADV-stashdroplet "echo git stash droplet"
case_cmd ADV-stashclearly "echo git stash clearly-safe"
case_cmd ADV-checkoutdd "git log checkout--"
case_cmd ADV-dropbox    "echo drop the dropbox database-tool"
case_cmd ADV-airdrop    "echo dropped_users airdrop table"
case_cmd ADV-truncateable "ls truncate_table_helper.sql"
case_cmd ADV-deleteprose "echo please delete files from /tmp"
case_cmd ADV-kubectlplug "ls kubectl-delete-plugin"
case_cmd ADV-kubectlget "kubectl get pods --all-namespaces && echo delete"
case_cmd ADV-rundata    "echo x >> .run/notes.txt"
case_cmd ADV-runls      "ls .run/"
case_cmd ADV-skillset   "echo grimoires/loa/skillset"
case_cmd ADV-crondaemon "tar -tzf backup.tar .run/cron.d"
case_cmd ADV-rmword     "mv file.txt myrmdir/-backup"
case_cmd ADV-confirm    "confirm --delete from x"
case_cmd ADV-formative  "echo formative -rm"
case_cmd ADV-rmnodash   "rm file1 file2"
# 4b. guard literal split across quotes/escapes — old already allows (quote
#     bypass is an accepted class); new must allow IDENTICALLY (guard skip).
case_cmd ADV-rquotem    'r"m" -rf /etc'
case_cmd ADV-octalrm    "\$'\\162'm -rf /"
case_cmd ADV-gquoteit   'g"it" push --force origin'
case_cmd ADV-pusplit    'git pu"sh" --force origin'
case_cmd ADV-forcesc    'git push --forc\e origin'
case_cmd ADV-kubesplit  'kube"ctl" delete ns prod'
case_cmd ADV-delsplit   'psql -c "DEL""ETE FROM users"'
case_cmd ADV-runsplit   'echo x > .ru"n"/cron.d/job.sh'
# 4c. case variants (patterns are case-sensitive except P8/P9/P10)
case_cmd ADV-upperRM    "RM -RF /etc"
case_cmd ADV-upperGIT   "GIT PUSH --FORCE origin"
case_cmd ADV-mixeddrop  'psql -c "DrOp TaBlE users"'
case_cmd ADV-mixeddel   'psql -c "DeLeTe FrOm users"'
case_cmd ADV-upperKUBE  "KUBECTL DELETE NS prod"
case_cmd ADV-upperTRUNC 'psql -c "tRuNcAtE tAbLe users"'
# 4d. literal inside strings / comments / heredocs (hook has no quote/comment
#     awareness — parity of whatever old did)
case_cmd ADV-quotedpush 'echo "git push --force origin main"'
case_cmd ADV-comment    "# git push --force origin main"
case_cmd ADV-dropquoted "echo 'DROP TABLE users' # commentary"
case_cmd ADV-heredocsz  $'cat <<\'EOF\' > .run/cron.d/x.sh\npayload\nEOF'
case_cmd ADV-delfromusers "echo delete from users"
# 4e. multiline: literals split ACROSS lines — whole-string guard passes but
#     the per-line regex must NOT match (pins constraint: prefilter never
#     used to accept); plus a multiline true positive.
case_cmd ADV-ml-split   $'echo git\necho push\necho --force'
case_cmd ADV-ml-split2  $'kubectl get pods\necho delete ns prod'
case_cmd ADV-ml-hit     $'echo prep\ngit push --force origin main'
case_cmd ADV-ml-rm      $'echo rm\necho -rf /etc'
case_cmd ADV-ml-rmhit   $'echo safe\nrm -rf /etc'
# 4f. unicode homoglyphs (Cyrillic і/е) — no ASCII literal, both sides allow
case_cmd ADV-homoglyph1 $'gіt push --force origin'
case_cmd ADV-homoglyph2 $'rm ‐rf /etc'
case_cmd ADV-homoglyph3 $'kubеctl delete ns prod'
# 4g. whitespace variants around mandatory literals
case_cmd ADV-tabs       $'git\tpush\t--force origin'
case_cmd ADV-sudospace  "sudo  git  push  --force origin"
case_cmd ADV-leadspace  "   git push --force origin"
# 4h. environment-inherited delete_stmts must not leak into skipped branch
case_cmd ADV-envleak    "ls -la" delete_stmts="DELETE FROM poisoned"
case_cmd ADV-envleak2   "echo delete something from prose" delete_stmts="DELETE FROM poisoned"
# 4i. NUL escapes + invalid UTF-8 payloads (parse path identical; parity)
case_raw ADV-nul        '{"tool_input":{"command":"echo \u0000 rm -rf /tmp/x"}}'
case_raw ADV-nulblock   '{"tool_input":{"command":"git push \u0000--force origin"}}'
case_raw ADV-badutf8    "$(printf '{"tool_input":{"command":"echo \xffrm -rf /"}}')"
# 4j. 100KB commands (guards scan whole string; parity + no pathology)
BIGPAD="$(printf 'word%099996d' 7)"                       # ~100KB, no guard literals
case_cmd ADV-big-benign  "$BIGPAD"
case_cmd ADV-big-git     "echo $BIGPAD && git status"
case_cmd ADV-big-blocked "echo $BIGPAD; git push --force origin main"
case_cmd ADV-big-delete  "echo $BIGPAD delete from x"
case_cmd ADV-big-rm      "echo $BIGPAD; rm -rf /etc"
# 4k. boundary-set completeness on the block side (every boundary char form)
case_cmd ADV-bnd-semi   "true;git push --force o"
case_cmd ADV-bnd-and    "true&&git push --force o"
case_cmd ADV-bnd-pipe   "true|git push --force o"
case_cmd ADV-bnd-paren  "(git push --force o)"
case_cmd ADV-bnd-squote "echo 'git push --force o'"
case_cmd ADV-bnd-slash  "/usr/bin/git push --force o"
case_cmd ADV-sudo       "sudo git push --force o"
# 4l. FR-SZ guard: absolute-prefix .run/ (substring holds), and bare mention
case_cmd ADV-sz-abs     "cp /tmp/x /repo/.run/cron.d/job.sh"
case_cmd ADV-sz-mention "echo see .run/cron.d for jobs"
case_cmd ADV-sz-shwrite "echo x > .run/deep/nested/tool.sh"
case_cmd ADV-sz-shread  "bash .run/deep/nested/tool.sh"

echo ""
echo "pass-8 differential corpus: $total cases, $fail divergences"
[[ $fail -eq 0 ]]
