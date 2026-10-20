#!/usr/bin/env bats
# =============================================================================
# evals/tests/sandbox-mount.bats — cycle-131 Sprint 263 Task 1.1 (PRD FR-1 AC 1, AC 5;
# FR-5 AC 1; SDD §5.2 overlay_answer_paths / check_mount_closed, D-1.1, D-5.x)
#
# evals/harness/lib/sandbox-mount.sh's closed mount on a fixture-shaped sandbox: a
# throwaway source repository (the pinned Loa tree: a head commit, then a fix commit
# that is the pin), a PR fixture (head.diff, head/, base/, fixture.yaml) whose head.diff
# carries every path shape (modified, added, deleted, renamed, a quoted path with a
# space, a symlink in head, a path outside .claude/, a removed hunk line that looks like
# a header, a binary hunk), and a sandbox built as pipeline-run.sh builds it (pr/ copied,
# a base commit, the whole .claude/ mounted). Also the cycle-131 toggles (bare_model,
# dissent, oracle_open) and the eval config variant. No model call, no docker.
# =============================================================================

setup() {
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  LIB="$REPO_ROOT/evals/harness/lib/sandbox-mount.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/sm.XXXXXX")"
  SRC="$T/src" FX="$T/fx" W="$T/ws"
  export ARM_EVIDENCE_FILE="$T/ev.txt"; : > "$ARM_EVIDENCE_FILE"
  make_source
  make_fixture
  make_ws
}

teardown() {
  chmod -R u+rwx "$T" 2>/dev/null || true
  find "$T" -mindepth 1 -delete 2>/dev/null || true
  rmdir "$T" 2>/dev/null || true
}

g() { git -C "$1" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "${@:2}"; }

# the pinned Loa tree: commit H (= the PR's head_commit) then commit F (the fix, the pin)
make_source() {
  mkdir -p "$SRC/.claude/scripts" "$SRC/.claude/data" "$SRC/.claude/loa" "$SRC/.claude/skills/s1" "$SRC/lib"
  printf 'mod head\n' > "$SRC/.claude/scripts/mod.sh"
  printf 'added head\n' > "$SRC/.claude/scripts/added.sh"
  printf 'new name head\n' > "$SRC/.claude/scripts/new name.sh"
  printf 'xy head\n' > "$SRC/.claude/data/x y.txt"
  printf 'fixonly head\n' > "$SRC/.claude/scripts/fixonly.sh"
  printf 'skill pinned\n' > "$SRC/.claude/skills/s1/SKILL.md"
  printf 'loa\n' > "$SRC/.claude/loa/CLAUDE.loa.md"
  printf 'outside head\n' > "$SRC/lib/outside.sh"
  printf '{"files":{}}\n' > "$SRC/.claude/checksums.json"
  chmod +x "$SRC/.claude/scripts/mod.sh"
  ( cd "$SRC" && git init -q && g . add -A && g . commit -qm head )
  H="$(git -C "$SRC" rev-parse HEAD)"
  # the fix commit: later versions of PR paths and of a path the PR never touched
  printf 'mod LATER fixed\n' > "$SRC/.claude/scripts/mod.sh"
  printf 'added LATER fixed\n' > "$SRC/.claude/scripts/added.sh"
  printf 'deleted LATER restored\n' > "$SRC/.claude/scripts/deleted.sh"
  printf 'new name LATER\n' > "$SRC/.claude/scripts/new name.sh"
  printf 'xy LATER\n' > "$SRC/.claude/data/x y.txt"
  printf 'fixonly LATER fixed\n' > "$SRC/.claude/scripts/fixonly.sh"
  printf '{"files":{"later":1}}\n' > "$SRC/.claude/checksums.json"
  ( cd "$SRC" && g . add -A && g . commit -qm fix )
  F="$(git -C "$SRC" rev-parse HEAD)"
}

# the PR fixture (immutable in production: evals/fixtures/review-prs/pr-NN/)
make_fixture() {
  mkdir -p "$FX/head/.claude/scripts" "$FX/head/.claude/data" "$FX/head/.claude/skills/s1" "$FX/head/lib" \
           "$FX/base/.claude/scripts" "$FX/base/.claude/data" "$FX/base/lib"
  printf 'mod head\n' > "$FX/head/.claude/scripts/mod.sh"; chmod +x "$FX/head/.claude/scripts/mod.sh"
  printf 'mod base\n' > "$FX/base/.claude/scripts/mod.sh"
  printf 'added head\n' > "$FX/head/.claude/scripts/added.sh"
  printf 'deleted base\n' > "$FX/base/.claude/scripts/deleted.sh"
  printf 'old name base\n' > "$FX/base/.claude/scripts/old name.sh"
  printf 'new name head\n' > "$FX/head/.claude/scripts/new name.sh"
  printf 'xy head\n' > "$FX/head/.claude/data/x y.txt"
  printf 'xy base\n' > "$FX/base/.claude/data/x y.txt"
  printf 'SECRET outside the fixture\n' > "$T/outside-secret"
  ln -s ../../../../outside-secret "$FX/head/.claude/skills/s1/SKILL.md"
  printf 'outside head\n' > "$FX/head/lib/outside.sh"; printf 'outside base\n' > "$FX/base/lib/outside.sh"
  cat > "$FX/head.diff" <<'DIFF'
diff --git a/.claude/scripts/mod.sh b/.claude/scripts/mod.sh
--- a/.claude/scripts/mod.sh
+++ b/.claude/scripts/mod.sh
@@ -1,2 +1,1 @@
--- a/.claude/scripts/evil.sh
-mod base
+mod head
diff --git a/.claude/scripts/added.sh b/.claude/scripts/added.sh
new file mode 100644
--- /dev/null
+++ b/.claude/scripts/added.sh
@@ -0,0 +1 @@
+added head
diff --git a/.claude/scripts/deleted.sh b/.claude/scripts/deleted.sh
deleted file mode 100644
--- a/.claude/scripts/deleted.sh
+++ /dev/null
@@ -1 +0,0 @@
-deleted base
diff --git a/.claude/scripts/old name.sh b/.claude/scripts/new name.sh
similarity 50%
rename from .claude/scripts/old name.sh
rename to .claude/scripts/new name.sh
diff --git "a/.claude/data/x y.txt" "b/.claude/data/x y.txt"
--- "a/.claude/data/x y.txt"
+++ "b/.claude/data/x y.txt"
@@ -1 +1 @@
-xy base
+xy head
diff --git a/.claude/assets/logo.png b/.claude/assets/logo.png
new file mode 100644
Binary files /dev/null and b/.claude/assets/logo.png differ
diff --git a/lib/outside.sh b/lib/outside.sh
--- a/lib/outside.sh
+++ b/lib/outside.sh
@@ -1 +1 @@
-outside base
+outside head
DIFF
  printf 'name: pr-t\nbase_commit: "%s"\nhead_commit: "%s"\nfix_commit: "%s"\n' "$H" "$H" "$F" > "$FX/fixture.yaml"
}

# the sandbox as pipeline-run.sh materialises it: pr/, the base commit, then the mount
make_ws() {
  mkdir -p "$W/pr"
  cp -a "$FX/base" "$FX/head" "$FX/head.diff" "$W/pr/"
  git -C "$W" init -q
  printf '%s\n' '/.claude/' '/CLAUDE.md' '/.loa.config.yaml' '/grimoires/' '/.run/' '/.beads/' '/.eval/' >> "$W/.git/info/exclude"
  g "$W" add -A; g "$W" commit -qm base
  printf 'base_commit=%s\n' "$(git -C "$W" rev-parse HEAD)" >> "$ARM_EVIDENCE_FILE"
  mkdir -p "$W/.claude"; cp -a "$SRC/.claude/." "$W/.claude/"
  printf 'flatline_protocol:\n  enabled: true\n  code_review:\n    enabled: true\n  security_audit:\n    enabled: true\n' > "$W/.loa.config.yaml"
}

# lib <fn> <args…> — run one library function in a fresh shell (the library sets no options)
lib() { run bash -c 'set -euo pipefail; source "$1"; shift; "$@"' _ "$LIB" "$@"; }
ev() { grep -E "^$1=" "$ARM_EVIDENCE_FILE" | sed "s/^$1=//"; }
content() { cat "$W/$1"; }

@test "answer set: diff headers (quoted, renamed both names, /dev/null, binary), head/ and base/ files, fix-commit paths; only .claude/, never checksums.json, a removed '--- a/' line or a path outside .claude/" {
  lib _sm_oracle_py answer-set "$FX" "$SRC"
  [ "$status" -eq 0 ]
  want=$'pr\t.claude/assets/logo.png\npr\t.claude/data/x y.txt\npr\t.claude/scripts/added.sh\npr\t.claude/scripts/deleted.sh\nfix\t.claude/scripts/fixonly.sh\npr\t.claude/scripts/mod.sh\npr\t.claude/scripts/new name.sh\npr\t.claude/scripts/old name.sh\npr\t.claude/skills/s1/SKILL.md'
  [ "$(grep -v '^sandbox-mount:' <<<"$output")" = "$want" ]
}

@test "answer set: a CRLF head.diff and a C-quoted octal path parse the same; an unsafe path is rejected" {
  local f="$T/fx2"
  mkdir -p "$f"
  printf 'diff --git "a/.claude/caf\\303\\251.md" "b/.claude/caf\\303\\251.md"\r\n--- "a/.claude/caf\\303\\251.md"\r\n+++ "b/.claude/caf\\303\\251.md"\r\n@@ -1 +1 @@\r\n-a\r\n+b\r\ndiff --git a/.claude/../etc/passwd b/.claude/../etc/passwd\r\ndiff --git a//abs b//abs\r\n' > "$f/head.diff"
  lib _sm_oracle_py answer-set "$f" "$SRC"
  [ "$status" -eq 0 ]
  [ "$(grep -v '^sandbox-mount:' <<<"$output")" = $'pr\t.claude/café.md' ]
  grep -q "rejected path '.claude/../etc/passwd'" <<<"$output"
}

@test "overlay head mode (default): PR paths at pr/head/, deleted and old-name paths removed, the symlink never followed, fix-commit path at head_commit, exec bit kept, untouched paths and checksums.json unchanged" {
  lib overlay_answer_paths "$W" "$FX" head "$SRC" "$F"
  [ "$status" -eq 0 ]
  [ "$(content .claude/scripts/mod.sh)" = "mod head" ]
  [ -x "$W/.claude/scripts/mod.sh" ]
  [ "$(content .claude/scripts/added.sh)" = "added head" ]
  [ ! -e "$W/.claude/scripts/deleted.sh" ]
  [ ! -e "$W/.claude/scripts/old name.sh" ]
  [ "$(content ".claude/scripts/new name.sh")" = "new name head" ]
  [ "$(content ".claude/data/x y.txt")" = "xy head" ]
  [ ! -e "$W/.claude/skills/s1/SKILL.md" ] && [ ! -L "$W/.claude/skills/s1/SKILL.md" ]
  [ "$(cat "$T/outside-secret")" = "SECRET outside the fixture" ]
  ! grep -rq SECRET "$W/.claude" || false
  [ "$(content .claude/scripts/fixonly.sh)" = "fixonly head" ]
  [ "$(content .claude/checksums.json)" = '{"files":{"later":1}}' ]
  [ "$(content .claude/loa/CLAUDE.loa.md)" = "loa" ]
  [ ! -e "$W/.claude/scripts/evil.sh" ]
  [ ! -e "$W/lib" ]
  # evidence, written to ARM_EVIDENCE_FILE as the run's pre-launch record
  [ "$(ev mount_overlay)" = "head:9" ]
  [ "$(ev overlay_sha256 | wc -l)" -eq 9 ]
  [ "$(ev overlay_sha256 | grep -c '=absent$')" -eq 4 ]
  grep -qx "overlay_sha256=.claude/scripts/mod.sh=$(printf 'mod head\n' | python3 -I -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')" "$ARM_EVIDENCE_FILE"
  grep -qx 'overlay_sha256=.claude/data/x y.txt=[0-9a-f]\{64\}' "$ARM_EVIDENCE_FILE"
  ! grep -q 'overlay_sha256=.claude/checksums.json' "$ARM_EVIDENCE_FILE" || false
  ! grep -q 'overlay_sha256=lib/' "$ARM_EVIDENCE_FILE" || false
  [ "$(ev gate_scripts_at_pr_version)" = ".claude/scripts/added.sh,.claude/scripts/fixonly.sh,.claude/scripts/mod.sh,.claude/scripts/new name.sh" ]
  [ "$(ev copy_source)" = "$F" ]
  [ "$(ev overlay_removed)" = 4 ]
  [ "$(ev overlay_fix_commit)" = available ]
  [ "$(ev overlay_fixture)" = "$FX" ]
}

@test "overlay base mode: pr/base/ versions, PR-added paths removed, deleted and old-name paths restored at base, fix-commit path still at head_commit" {
  lib overlay_answer_paths "$W" "$FX" base "$SRC"
  [ "$status" -eq 0 ]
  [ "$(content .claude/scripts/mod.sh)" = "mod base" ]
  [ ! -x "$W/.claude/scripts/mod.sh" ]
  [ ! -e "$W/.claude/scripts/added.sh" ]
  [ ! -e "$W/.claude/scripts/new name.sh" ]
  [ "$(content .claude/scripts/deleted.sh)" = "deleted base" ]
  [ "$(content ".claude/scripts/old name.sh")" = "old name base" ]
  [ "$(content ".claude/data/x y.txt")" = "xy base" ]
  [ "$(content .claude/scripts/fixonly.sh)" = "fixonly head" ]
  [ "$(ev mount_overlay)" = "base:9" ]
  [ "$(ev gate_scripts_at_pr_version)" = ".claude/scripts/deleted.sh,.claude/scripts/fixonly.sh,.claude/scripts/mod.sh,.claude/scripts/old name.sh" ]
}

@test "overlay: an unknown fix commit is refused before any write (PR #1286 F001); the check fails on overlay_fix_commit=unavailable" {
  sed -i "s/^fix_commit: .*/fix_commit: \"$(printf 'e%.0s' $(seq 1 40))\"/" "$FX/fixture.yaml"
  local before; before="$(content .claude/scripts/mod.sh)"
  lib overlay_answer_paths "$W" "$FX" head "$SRC"
  [ "$status" -eq 2 ]
  grep -q 'fix_commit_unavailable eeeeeeee' <<<"$output"
  grep -q 'overlay: refused: fix_commit eeeeeeee' <<<"$output"
  [ "$(content .claude/scripts/mod.sh)" = "$before" ]                    # nothing written
  [ "$(content .claude/scripts/fixonly.sh)" = "fixonly LATER fixed" ]
  [ -z "$(ev mount_overlay)" ]
  [ -z "$(ev overlay_fix_commit)" ]
  lib check_mount_closed "$W" "$FX" "$SRC"
  [ "$status" -eq 2 ]
  grep -q 'mount_overlay=<missing>' <<<"$output"
  # a recorded overlay whose evidence says unavailable never checks closed, whatever the sandbox holds
  sed -i "s/^fix_commit: .*/fix_commit: \"$F\"/" "$FX/fixture.yaml"
  lib overlay_answer_paths "$W" "$FX" head "$SRC"
  [ "$status" -eq 0 ]
  [ "$(ev overlay_fix_commit)" = available ]
  lib check_mount_closed "$W" "$FX" "$SRC"
  [ "$status" -eq 0 ]
  sed -i 's/^overlay_fix_commit=.*/overlay_fix_commit=unavailable/' "$ARM_EVIDENCE_FILE"
  lib check_mount_closed "$W" "$FX" "$SRC"
  [ "$status" -eq 2 ]
  grep -q 'FAIL (a) -: overlay_fix_commit=unavailable' <<<"$output"
}

@test "overlay refusals (exit 2): missing fixture, bad mode, copy_source other than source_commit, a dirty copy source, a symlink component in the sandbox" {
  lib overlay_answer_paths "$W" "$T/nope" head "$SRC"
  [ "$status" -eq 2 ]; grep -q 'fixture not found or has no head.diff' <<<"$output"
  lib overlay_answer_paths "$W" "$FX" later "$SRC"
  [ "$status" -eq 2 ]; grep -q 'mode must be head or base' <<<"$output"
  lib overlay_answer_paths "$W" "$FX" head "$SRC" "$H"
  [ "$status" -eq 2 ]; grep -q "copy_source $F differs from source_commit $H" <<<"$output"
  [ "$(content .claude/scripts/mod.sh)" = "mod LATER fixed" ]   # nothing overlaid
  ! grep -q '^mount_overlay=' "$ARM_EVIDENCE_FILE" || false
  echo dirty >> "$SRC/.claude/loa/CLAUDE.loa.md"
  lib overlay_answer_paths "$W" "$FX" head "$SRC"
  [ "$status" -eq 2 ]; grep -q "copy_source=$F-dirty" <<<"$output"
  git -C "$SRC" checkout -q -- .claude/loa/CLAUDE.loa.md
  rm -rf "$W/.claude/data"; mkdir -p "$T/elsewhere"; ln -s "$T/elsewhere" "$W/.claude/data"
  lib overlay_answer_paths "$W" "$FX" head "$SRC"
  [ "$status" -eq 2 ]; grep -q 'symlink component .claude/data' <<<"$output"
  [ -z "$(ls -A "$T/elsewhere")" ]
}

@test "check_mount_closed: passes on the overlaid sandbox; refuses an unmodified mount, a stray later copy, a mutated path, a second commit, a remote" {
  lib check_mount_closed "$W" "$FX" "$SRC"
  [ "$status" -eq 2 ]; grep -q 'no clean copy_source' <<<"$output"          # nothing overlaid yet
  printf 'copy_source=%s\nmount_overlay=head:9\n' "$F" >> "$ARM_EVIDENCE_FILE"
  lib check_mount_closed "$W" "$FX" "$SRC"
  [ "$status" -eq 2 ]; grep -q 'FAIL (a) ' <<<"$output"                     # an unmodified (later) mount
  sed -i '/^copy_source=/d; /^mount_overlay=/d' "$ARM_EVIDENCE_FILE"
  lib overlay_answer_paths "$W" "$FX" head "$SRC" "$F"
  [ "$status" -eq 0 ]
  lib check_mount_closed "$W" "$FX" "$SRC"
  [ "$status" -eq 0 ]
  grep -q '^mount_closed=pre-launch head:9 answer paths (5 present)' "$ARM_EVIDENCE_FILE"
  # (b) a stray copy of a later version outside pr/
  mkdir -p "$W/.claude/cache"; git -C "$SRC" show "$F:.claude/scripts/fixonly.sh" > "$W/.claude/cache/copy.txt"
  lib check_mount_closed "$W" "$FX" "$SRC"
  [ "$status" -eq 2 ]; grep -q 'FAIL (b) .claude/cache/copy.txt: byte-equal to the pinned .claude/scripts/fixonly.sh' <<<"$output"
  rm "$W/.claude/cache/copy.txt"
  # a later copy under pr/ is the agent's own tree, not the mount: (b) skips pr/
  git -C "$SRC" show "$F:.claude/scripts/mod.sh" > "$W/pr/copy.txt"
  lib check_mount_closed "$W" "$FX" "$SRC"
  [ "$status" -eq 0 ]
  rm "$W/pr/copy.txt"
  # (c) a mutated overlaid path
  echo tampered >> "$W/.claude/scripts/added.sh"
  lib check_mount_closed "$W" "$FX" "$SRC"
  [ "$status" -eq 2 ]; grep -q 'FAIL (c) .claude/scripts/added.sh: mount_mutated=.claude/scripts/added.sh' <<<"$output"
  printf 'added head\n' > "$W/.claude/scripts/added.sh"
  # (d) a second commit, then a remote
  echo x > "$W/note.txt"; g "$W" add note.txt; g "$W" commit -qm later
  lib check_mount_closed "$W" "$FX" "$SRC"
  [ "$status" -eq 2 ]; grep -q 'FAIL (d) .git: commits' <<<"$output"
  g "$W" reset -q --hard HEAD~1; g "$W" reflog expire --expire=now --all; g "$W" gc -q --prune=now
  lib check_mount_closed "$W" "$FX" "$SRC"
  [ "$status" -eq 0 ]
  g "$W" remote add origin "$SRC"
  lib check_mount_closed "$W" "$FX" "$SRC"
  [ "$status" -eq 2 ]; grep -q 'FAIL (d) .git: remote' <<<"$output"
}

@test "check_mount_closed (d): a later blob in the sandbox object store fails even when no ref names it" {
  lib overlay_answer_paths "$W" "$FX" head "$SRC" "$F"
  git -C "$SRC" show "$F:.claude/scripts/mod.sh" | git -C "$W" hash-object -w --stdin >/dev/null
  lib check_mount_closed "$W" "$FX" "$SRC"
  [ "$status" -eq 2 ]
  grep -q 'FAIL (d) ' <<<"$output"
}

@test "toggles: bare_model fable, dissent false (review gate only), oracle_open true; other values refused; oracle_open after an overlay refused" {
  lib apply_arm_toggles "$W" '{"bare_model":"fable"}' a0_bare_fable
  [ "$status" -eq 0 ]; [ "$(ev bare_model)" = fable ]
  lib apply_arm_toggles "$W" '{"bare_model":"opus"}' a0_bare_fable
  [ "$status" -eq 2 ]; grep -q 'bare_model=opus (only fable is defined)' <<<"$output"
  lib apply_arm_toggles "$W" '{"dissent":false}' a1_no_dissent
  [ "$status" -eq 0 ]; [ "$(ev dissent)" = false ]
  [ "$(yq -r '.flatline_protocol.code_review.enabled' "$W/.loa.config.yaml")" = false ]
  [ "$(yq -r '.flatline_protocol.security_audit.enabled' "$W/.loa.config.yaml")" = true ]
  lib apply_arm_toggles "$W" '{"dissent":true}' a1_no_dissent
  [ "$status" -eq 2 ]; grep -q 'dissent=true (only false is defined)' <<<"$output"
  lib apply_arm_toggles "$W" '{"oracle_open":true}' a1_full_openmount
  [ "$status" -eq 0 ]; [ "$(ev oracle_open)" = true ]
  lib apply_arm_toggles "$W" '{"oracle_open":false}' a1_full_openmount
  [ "$status" -eq 2 ]; grep -q 'oracle_open=false (only true is defined)' <<<"$output"
  echo 'mount_overlay=head:3' >> "$ARM_EVIDENCE_FILE"
  lib apply_arm_toggles "$W" '{"oracle_open":true}' a1_full_openmount
  [ "$status" -eq 2 ]; grep -q 'oracle_open toggle: the sandbox was overlaid' <<<"$output"
}

@test "toggles leave the overlay intact: check_mount_closed after dissent: false and the eval config variant still passes (the config is outside the answer set)" {
  lib overlay_answer_paths "$W" "$FX" head "$SRC" "$F"
  lib apply_arm_toggles "$W" '{"dissent":false}' a1_no_dissent
  lib apply_eval_config_variant "$W"
  [ "$status" -eq 0 ]
  lib check_mount_closed "$W" "$FX" "$SRC"
  [ "$status" -eq 0 ]
}

@test "eval config variant: budget_scale diff and budget_cents_max 600 for both gates, enabled flags untouched, config_variant=eval" {
  lib apply_eval_config_variant "$W"
  [ "$status" -eq 0 ]
  for gate in code_review security_audit; do
    [ "$(G=$gate yq -r '.flatline_protocol[strenv(G)].budget_scale' "$W/.loa.config.yaml")" = diff ]
    [ "$(G=$gate yq -r '.flatline_protocol[strenv(G)].budget_cents_max' "$W/.loa.config.yaml")" = 600 ]
    [ "$(G=$gate yq -r '.flatline_protocol[strenv(G)].enabled' "$W/.loa.config.yaml")" = true ]
  done
  [ "$(ev config_variant)" = eval ]
  rm "$W/.loa.config.yaml"
  lib apply_eval_config_variant "$W"
  [ "$status" -eq 0 ]
  [ "$(yq -r '.flatline_protocol.code_review.budget_scale' "$W/.loa.config.yaml")" = diff ]
}

@test "the real corpus: pr-17's answer set is .claude/-only, includes fix-commit paths the PR did not touch, and excludes checksums.json" {
  local fx="$REPO_ROOT/evals/fixtures/review-prs/pr-17"
  git -C "$REPO_ROOT" cat-file -e "$(yq -r .fix_commit "$fx/fixture.yaml")^{commit}" 2>/dev/null || skip "record commits not in this clone"
  lib _sm_oracle_py answer-set "$fx" "$REPO_ROOT"
  [ "$status" -eq 0 ]
  ! grep -qvE $'^(pr|fix)\t\\.claude/' <<<"$output" || false
  grep -qx $'pr\t.claude/hooks/safety/block-destructive-bash.sh' <<<"$output"
  ! grep -q 'checksums.json' <<<"$output" || false
  ! grep -q 'AGENTS.md' <<<"$output" || false
}
