#!/usr/bin/env bats
# =============================================================================
# evals/tests/sandbox-mount-home-scope.bats — cycle-133 Sprint 274 Task 3.1 (PRD FR-10 AC 1, AC 3; SDD C-10,
# D-3.1 DEC-0848 as amended by D-3.6 DEC-0858; the oracle-exposure row of SDD §7.3)
#
# Loa reviews Loa. The mount mode home-scope puts the PR's changed .claude/ paths at the workspace root as DATA and
# keeps the executable and prompt surface (skills, commands, agents, hooks, settings, *.local.*, rules,
# .claude/CLAUDE.md, the root CLAUDE.md / CLAUDE.local.md, .mcp.json, output styles, plugins, nested memory, @-imported
# files) off the root — readable under pr/head/ only. Covered here, with no model call and no docker:
#   HS-1  the surface classification of every surface item and every data path (design-neutral list)
#   HS-2  the root overlay: data at the PR's bytes; deleted, renamed-away and symlinked paths absent; every surface
#         item absent at the root and byte-equal to the PR under pr/head/ (the symlink's target kept there)
#   HS-3  check_mount_closed clause (e): passes; fails on each planted surface item, a fixed load path, a stray
#         framework file, a surface symlink and a data path at the pinned bytes
#   HS-4  the existing mount (pinned-root) is unchanged: byte-identical sandbox and evidence to the Sprint 2 library
#   HS-5  took-effect oracle_closed clause (f): pr_bytes_read from Read results (gutter stripped, windows joined,
#         >= 60 % of the lines, Grep never counts), every cited changed file read, no pinned (later) bytes read
#   HS-6  clause (g): no project hook, MCP server, plugin, PR-only skill, PR .claude/ execution or canary
#   HS-7  every surface item planted with a canary: absent at the root, PR bytes under pr/head/, never loaded or
#         executed (clause (g)); each simulated execution or load is named
#   HS-8  the negative control (fixtures/home-scope-nc: distinct PR and pinned bytes for one path): the grader's
#         oracle detector fires on the cycle-132 mount and stays silent on the home-scope root, where clause (f)
#         credits the read
# The isolation and mount-provenance tests may never be quarantined (SDD C-5, §7.3).
# =============================================================================

setup() {
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  LIB="$REPO_ROOT/evals/harness/lib/sandbox-mount.sh"
  TE="$REPO_ROOT/evals/harness/took-effect.sh"
  GRADER="$REPO_ROOT/evals/harness/ablation-grade.sh"
  NC="$TESTS_DIR/fixtures/home-scope-nc"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/hs.XXXXXX")"
  SRC="$T/src" FX="$T/fx" RD="$T/run"
  W="$RD/sandbox"
  export ARM_EVIDENCE_FILE="$RD/meta/arm-evidence.txt"
  unset SM_TEST_MODE SM_TEST_EXCLUDED_PREFIX
  make_fixture
  make_source
  make_ws
}

teardown() {
  chmod -R u+rwx "$T" 2>/dev/null || true
  find "$T" -mindepth 1 -delete 2>/dev/null || true
  rmdir "$T" 2>/dev/null || true
}

# deterministic commits (HS-4 pins digests over them)
g() {
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_DATE="2026-10-24T00:00:00Z" GIT_COMMITTER_DATE="2026-10-24T00:00:00Z" \
    git -C "$1" -c user.email=t@t -c user.name=t -c commit.gpgsign=false -c init.defaultBranch=main -c core.excludesFile=/dev/null "${@:2}"
}

# The surface items of FR-10 AC 3 and C-10: path <TAB> item <TAB> PR change (mod|add)
SURFACE_ITEMS='.claude/skills/reviewing-code/SKILL.md	executing SKILL.md	mod
.claude/skills/pr-only/SKILL.md	skill the PR adds	add
.claude/hooks/h.sh	hook	mod
.claude/settings.json	settings	mod
.claude/settings.local.json	local settings	add
.claude/data/x.local.yaml	*.local.* file	add
.claude/rules/r.md	rules file	mod
.claude/CLAUDE.md	.claude/CLAUDE.md	add
CLAUDE.md	root CLAUDE.md	mod
CLAUDE.local.md	CLAUDE.local.md	add
.mcp.json	.mcp.json	add
.claude/output-styles/o.md	output style	add
.claude/plugins/pl/plugin.json	plugin	add
.claude/commands/c.md	command	mod
.claude/agents/a.md	agent	mod
.claude/protocols/imported.md	@-imported file	add
.claude/data/CLAUDE.md	nested memory file	add'
# The data paths: path <TAB> item <TAB> PR change
DATA_ITEMS='.claude/scripts/s.sh	script	mod
.claude/protocols/p.md	protocol	mod
.claude/data/d.yaml	deleted file	del
.claude/data/old.txt	renamed file (old name)	ren-from
.claude/data/new.txt	renamed file (new name)	ren-to
.claude/data/link	symlink	link'

# body <path> <side> — a file's content on one side of the PR; p.md has ten lines, the planted site at 5
body() {
  local p="$1" s="$2" i
  case "$p" in
    .claude/protocols/p.md)
      for i in 1 2 3 4; do echo "protocol line $i stays the same"; done
      echo "protocol line 5 says the guard runs ($s version)"
      for i in 6 7 8 9 10; do echo "protocol line $i stays the same"; done ;;
    .claude/CLAUDE.md) printf '# project memory (%s)\n@protocols/imported.md\nLOA_CANARY_claude_dir_md\n' "$s" ;;
    .claude/hooks/h.sh) printf '#!/usr/bin/env bash\necho LOA_CANARY_hook > "$CLAUDE_PROJECT_DIR/.eval/canary-hook" # %s\n' "$s" ;;
    .claude/settings.json) printf '{"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": ".claude/hooks/h.sh"}]}]}, "note": "%s"}\n' "$s" ;;
    .mcp.json) printf '{"mcpServers": {"pr-mcp": {"command": "sh", "args": ["-c", "echo LOA_CANARY_mcp > .eval/canary-mcp"]}}}\n' ;;
    *) printf '%s %s version line 1\n%s %s version line 2 LOA_CANARY_%s\n' "$p" "$s" "$p" "$s" "$(basename "$p" | tr -c 'A-Za-z0-9\n' _)" ;;
  esac
}
put() { mkdir -p "$(dirname "$1")"; body "$2" "$3" > "$1"; }

# the PR fixture: head/, base/, head.diff, fixture.yaml (head_commit H, fix_commit F; written by make_source)
make_fixture() {
  local p item ch d=""
  while IFS=$'\t' read -r p item ch; do
    put "$FX/head/$p" "$p" head
    [[ "$ch" == mod ]] && put "$FX/base/$p" "$p" base
    if [[ "$ch" == add ]]; then d="$d"$'diff --git a/'"$p b/$p"$'\nnew file mode 100644\n--- /dev/null\n+++ b/'"$p"$'\n'
    else d="$d"$'diff --git a/'"$p b/$p"$'\n--- a/'"$p"$'\n+++ b/'"$p"$'\n'; fi
  done <<<"$SURFACE_ITEMS"
  chmod +x "$FX/head/.claude/hooks/h.sh"
  put "$FX/head/.claude/scripts/s.sh" .claude/scripts/s.sh head; put "$FX/base/.claude/scripts/s.sh" .claude/scripts/s.sh base
  put "$FX/head/.claude/protocols/p.md" .claude/protocols/p.md head; put "$FX/base/.claude/protocols/p.md" .claude/protocols/p.md base
  put "$FX/base/.claude/data/d.yaml" .claude/data/d.yaml base
  put "$FX/base/.claude/data/old.txt" .claude/data/old.txt base
  put "$FX/head/.claude/data/new.txt" .claude/data/old.txt base   # a pure rename: the same bytes
  printf 'SECRET outside the fixture\n' > "$T/outside-secret"
  ln -s ../../../../outside-secret "$FX/head/.claude/data/link"
  d="$d"$'diff --git a/.claude/scripts/s.sh b/.claude/scripts/s.sh\n--- a/.claude/scripts/s.sh\n+++ b/.claude/scripts/s.sh\n'
  d="$d"$'diff --git a/.claude/protocols/p.md b/.claude/protocols/p.md\n--- a/.claude/protocols/p.md\n+++ b/.claude/protocols/p.md\n@@ -5 +5 @@\n-protocol line 5 says the guard runs (base version)\n+protocol line 5 says the guard runs (head version)\n'
  d="$d"$'diff --git a/.claude/data/d.yaml b/.claude/data/d.yaml\ndeleted file mode 100644\n--- a/.claude/data/d.yaml\n+++ /dev/null\n'
  d="$d"$'diff --git a/.claude/data/old.txt b/.claude/data/new.txt\nsimilarity index 100%\nrename from .claude/data/old.txt\nrename to .claude/data/new.txt\n'
  d="$d"$'diff --git a/.claude/data/link b/.claude/data/link\nnew file mode 120000\n--- /dev/null\n+++ b/.claude/data/link\n'
  printf '%s' "$d" > "$FX/head.diff"
  printf '# PR\n' > "$FX/PR.md"
}

# the pinned framework: commit H (the PR's head era: the head versions) then F (the pin: later versions of the
# executing SKILL.md, the hook, the script and the protocol; the deleted file restored)
make_source() {
  mkdir -p "$SRC"
  cp -a "$FX/head/.claude" "$SRC/.claude"; rm -f "$SRC/.claude/data/link"
  rm -rf "$SRC/.claude/skills/pr-only" "$SRC/.claude/output-styles"   # PR-only names: the pin never had them
  mkdir -p "$SRC/.claude/loa"; printf 'loa\n' > "$SRC/.claude/loa/CLAUDE.loa.md"
  printf '{"files":{}}\n' > "$SRC/.claude/checksums.json"
  ( cd "$SRC" && g . init -q && g . add -A && g . commit -qm head )
  H="$(git -C "$SRC" rev-parse HEAD)"
  printf 'skill LATER fixed line 1\nskill LATER fixed line 2 with the guard\n' > "$SRC/.claude/skills/reviewing-code/SKILL.md"
  printf '#!/usr/bin/env bash\necho hook LATER fixed with the guard\n' > "$SRC/.claude/hooks/h.sh"
  printf 'script LATER fixed line 1\nscript LATER fixed line 2 with the guard\n' > "$SRC/.claude/scripts/s.sh"
  sed -i 's/^protocol line 5 says the guard runs (head version)$/protocol line 5 now says the guard ALWAYS runs (LATER fix)/' "$SRC/.claude/protocols/p.md"
  printf 'd.yaml LATER restored\n' > "$SRC/.claude/data/d.yaml"
  ( cd "$SRC" && g . add -A && g . commit -qm fix )
  F="$(git -C "$SRC" rev-parse HEAD)"
  printf 'name: pr-hs\nhead_commit: "%s"\nfix_commit: "%s"\n' "$H" "$F" > "$FX/fixture.yaml"
}

# the sandbox as pipeline-run.sh materialises a review-catch run: pr/ copied, the base commit, the root config
make_ws() {
  mkdir -p "$W/pr" "$RD/meta" "$RD/transcripts" "$RD/eval"
  cp -a "$FX/base" "$FX/head" "$FX/head.diff" "$FX/PR.md" "$W/pr/"
  g "$W" init -q
  printf '%s\n' '/.claude/' '/CLAUDE.md' '/.loa.config.yaml' '/grimoires/' '/.run/' '/.beads/' '/.eval/' >> "$W/.git/info/exclude"
  g "$W" add -A; g "$W" commit -qm base
  printf 'base_commit=%s\n' "$(git -C "$W" rev-parse HEAD)" > "$ARM_EVIDENCE_FILE"
  printf 'flatline_protocol:\n  enabled: true\n' > "$W/.loa.config.yaml"
  mkdir -p "$W/grimoires/loa/a2a/sprint-1" "$W/.eval"
}

lib() { run bash -c 'set -euo pipefail; source "$1"; shift; "$@"' _ "$LIB" "$@"; }
ev() { grep -E "^$1=" "$ARM_EVIDENCE_FILE" | sed "s/^$1=//"; }
hs_overlay() { lib overlay_answer_paths "$W" "$FX" head "$SRC" "$F" home-scope; }
gone() { [[ ! -e "$W/$1" && ! -L "$W/$1" ]]; }

@test "HS-1 surface classification (design-neutral list): every surface item is surface, every data path is an entry; the root memory and MCP files count; the pinned-root answer set is unchanged" {
  lib _sm_oracle_py answer-set "$FX" "$SRC" home-scope
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local want="" p item ch
  while IFS=$'\t' read -r p item ch; do want="$want"$'surface\t'"$p"$'\n'; done <<<"$SURFACE_ITEMS"
  while IFS=$'\t' read -r p item ch; do want="$want"$'pr\t'"$p"$'\n'; done <<<"$DATA_ITEMS"
  [ "$(grep -v '^sandbox-mount:' <<<"$output")" = "$(printf '%s' "$want" | LC_ALL=C sort -t$'\t' -k2)" ]
  # the import is followed from the PR's .claude/CLAUDE.md, relative to its directory
  grep -qx $'surface\t.claude/protocols/imported.md' <<<"$output"
  # the pinned-root answer set (cycle-132 addendum 9) is unchanged: every .claude path excluded, no entries
  lib _sm_oracle_py answer-set "$FX" "$SRC"
  [ "$status" -eq 0 ]; [ -z "$(grep -v '^sandbox-mount:' <<<"$output")" ]
  lib _sm_oracle_py answer-set "$FX" "$SRC" open-root
  [ "$status" -eq 2 ]; grep -q 'mount mode must be one of pinned-root|home-scope' <<<"$output"
}

@test "HS-2 home-scope root overlay: data at the PR's bytes; deleted, renamed-away and symlinked paths absent; every surface item absent at the root and byte-equal to the PR under pr/head/; evidence names the mode" {
  mkdir -p "$W/.claude/hooks"; printf 'stale\n' > "$W/.claude/hooks/h.sh"; printf 'stale\n' > "$W/CLAUDE.md"   # removed by the overlay
  hs_overlay
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local p item ch
  while IFS=$'\t' read -r p item ch; do
    gone "$p" || { echo "surface item $item ($p) is at the root"; false; }
    cmp -s "$W/pr/head/$p" "$FX/head/$p" || { echo "surface item $item: pr/head/$p is not the PR's bytes"; false; }
  done <<<"$SURFACE_ITEMS"
  cmp -s "$W/.claude/scripts/s.sh" "$FX/head/.claude/scripts/s.sh"
  cmp -s "$W/.claude/protocols/p.md" "$FX/head/.claude/protocols/p.md"
  cmp -s "$W/.claude/data/new.txt" "$FX/head/.claude/data/new.txt"
  gone .claude/data/d.yaml; gone .claude/data/old.txt; gone .claude/data/link
  cmp -s "$W/pr/base/.claude/data/d.yaml" "$FX/base/.claude/data/d.yaml"
  [ "$(readlink "$W/pr/head/.claude/data/link")" = "$(readlink "$FX/head/.claude/data/link")" ]
  ! grep -rq SECRET "$W/.claude" || false
  [ "$(ev mount_mode)" = home-scope ]
  [ "$(ev surface_derived_for)" = 2.1.299 ]
  [ "$(ev mount_overlay)" = head:6 ]
  [ "$(ev overlay_excluded | cut -d: -f1)" = 17 ]
  [ "$(ev overlay_surface_removed)" = 2 ]
  [ "$(ev overlay_imports)" = .claude/protocols/imported.md ]
  [ "$(ev overlay_sha256 | wc -l)" -eq 6 ]
  [ "$(ev overlay_removed)" = 3 ]
  [ "$(ev gate_scripts_at_pr_version)" = .claude/scripts/s.sh ]
  # refusals: base mode, an unknown mount mode
  lib overlay_answer_paths "$W" "$FX" base "$SRC" "$F" home-scope
  [ "$status" -eq 2 ]; grep -q 'home-scope puts the PR.s head bytes at the root' <<<"$output"
  lib overlay_answer_paths "$W" "$FX" head "$SRC" "$F" open-root
  [ "$status" -eq 2 ]; grep -q "mount mode must be pinned-root or home-scope, got 'open-root'" <<<"$output"
}

@test "HS-3 check_mount_closed clause (e): passes on the home-scope root; fails on every planted surface item, a fixed load path, a surface symlink, a stray framework file and a data path at the pinned bytes" {
  hs_overlay; [ "$status" -eq 0 ]
  lib check_mount_closed "$W" "$FX" "$SRC"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qF 'home-scope: 17 surface path(s) absent at the root (surface derived for Claude Code 2.1.299)' "$ARM_EVIDENCE_FILE"
  grep -q '^mount_closed=pre-launch head:6 answer paths (3 present)' "$ARM_EVIDENCE_FILE"
  local p item ch
  while IFS=$'\t' read -r p item ch; do
    mkdir -p "$(dirname "$W/$p")"; cp "$FX/head/$p" "$W/$p"
    lib check_mount_closed "$W" "$FX" "$SRC"
    [ "$status" -eq 2 ] || { echo "planted $item ($p) passed"; false; }
    grep -qF "FAIL (e) $p: a surface path is at the root" <<<"$output" || { echo "$item: $output"; false; }
    rm -f "$W/$p"
  done <<<"$SURFACE_ITEMS"
  find "$W/.claude" -mindepth 1 -depth -type d -empty -delete
  lib check_mount_closed "$W" "$FX" "$SRC"; [ "$status" -eq 0 ] || { echo "$output"; false; }
  # a project-scope load path the PR never touched (a pinned framework command copied to the root)
  mkdir -p "$W/.claude/commands"; printf 'x\n' > "$W/.claude/commands/other.md"
  lib check_mount_closed "$W" "$FX" "$SRC"
  [ "$status" -eq 2 ]; grep -qF 'FAIL (e) .claude/commands: a project-scope load path is present at the root' <<<"$output"
  rm -rf "$W/.claude/commands"
  # a surface symlink pointing into the pinned framework
  ln -s "$SRC/.claude/settings.json" "$W/.claude/settings.json"
  lib check_mount_closed "$W" "$FX" "$SRC"
  [ "$status" -eq 2 ]; grep -qF 'FAIL (e) .claude/settings.json: a surface path is at the root (symlink' <<<"$output"
  rm "$W/.claude/settings.json"
  # a framework file that is not one of the PR's paths
  cp "$SRC/.claude/loa/CLAUDE.loa.md" "$W/.claude/data/framework.md"
  lib check_mount_closed "$W" "$FX" "$SRC"
  [ "$status" -eq 2 ]; grep -qF "FAIL (e) .claude/data/framework.md: the root .claude/ holds a path that is not one of the PR's changed paths" <<<"$output"
  rm "$W/.claude/data/framework.md"
  # a data path at the pinned (later) bytes: (b) reports it first ((c) and (e) too)
  git -C "$SRC" show "$F:.claude/scripts/s.sh" > "$W/.claude/scripts/s.sh"
  lib check_mount_closed "$W" "$FX" "$SRC"
  [ "$status" -eq 2 ]; grep -qF 'FAIL (b) .claude/scripts/s.sh: byte-equal to the pinned .claude/scripts/s.sh' <<<"$output"
  put "$W/.claude/scripts/s.sh" .claude/scripts/s.sh head
  # the harness-owned manifest is allowed at the root
  printf '{"files":{}}\n' > "$W/.claude/checksums.json"
  lib check_mount_closed "$W" "$FX" "$SRC"; [ "$status" -eq 0 ] || { echo "$output"; false; }
  # the same tree judged as a pinned-root mount fails: the evidence names the mode, the check follows it
  sed -i 's/^mount_mode=home-scope$/mount_mode=pinned-root/' "$ARM_EVIDENCE_FILE"
  lib check_mount_closed "$W" "$FX" "$SRC"; [ "$status" -eq 2 ]
  sed -i 's/^mount_mode=pinned-root$/mount_mode=open/' "$ARM_EVIDENCE_FILE"
  lib check_mount_closed "$W" "$FX" "$SRC"; [ "$status" -eq 2 ]; grep -q 'mount_mode=open (want pinned-root|home-scope)' <<<"$output"
}

# --- HS-4: the existing mount mode is unchanged ---------------------------------------------------------------------
# tree_sum <dir>: one digest over the sorted paths, symlink targets and file bytes under <dir>, .git excluded
tree_sum() {
  python3 -I -c '
import hashlib, os, sys
h = hashlib.sha256(); root = sys.argv[1]
for r, ds, fs in os.walk(root):
    ds[:] = sorted(d for d in ds if not (r == root and d == ".git"))
    for n in sorted(ds + fs):
        q = os.path.join(r, n); h.update(os.path.relpath(q, root).encode() + b"\0")
        if os.path.islink(q): h.update(b"L" + os.readlink(q).encode())
        elif os.path.isfile(q): h.update(open(q, "rb").read())
print(h.hexdigest())' "$1"
}
# pr_seq <lib> <ws> <fixture> <source-tree> <source-commit> <evidence-file> — pipeline-run.sh's pinned-root sequence
pr_seq() {
  ARM_EVIDENCE_FILE="$6" bash -c 'set -euo pipefail; source "$1"
    mount_prompt_surface "$2" "$4" -
    overlay_answer_paths "$2" "$3" head "$4" "$5"
    check_mount_closed "$2" "$3" "$4"' _ "$1" "$2" "$3" "$4" "$5" 2>/dev/null
}
# both_libs <fixture> <source-tree> <source-commit> <ws-template> → prints "<old digest> <new digest>" lines for the
# sandbox and the evidence (absolute paths normalised); the old library is the Sprint 2 head's (de366cc63)
both_libs() {
  local v d e
  for v in old new; do
    rm -rf "$T/ws-$v"; cp -a "$4" "$T/ws-$v"
    cp "$ARM_EVIDENCE_FILE" "$T/ev-$v.txt"
    if [[ "$v" == old ]]; then pr_seq "$T/old/evals/harness/lib/sandbox-mount.sh" "$T/ws-$v" "$1" "$2" "$3" "$T/ev-$v.txt" || return 1
    else pr_seq "$LIB" "$T/ws-$v" "$1" "$2" "$3" "$T/ev-$v.txt" || return 1; fi
    d="$(tree_sum "$T/ws-$v")"
    e="$(sed "s|$T/ws-$v|WS|g; s|$T|T|g; s|$REPO_ROOT|REPO|g" "$T/ev-$v.txt" | python3 -I -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')"
    printf '%s %s\n' "$d" "$e"
  done
}
# the Sprint 2 library's (de366cc63) digests for the synthetic PR above (sandbox tree_sum, normalised evidence)
HS4_SANDBOX_SHA=bcd44b455678ba89c6069bd57008270f292157cc2e701d56c183418a6ef22980
HS4_EVIDENCE_SHA=5294fa8f6e2df894ef04ec43ad248f3a8acac4bf5e56fb9efb1f43a285685662
old_lib() {
  mkdir -p "$T/old/evals/harness/lib"
  git -C "$REPO_ROOT" show de366cc63:evals/harness/lib/sandbox-mount.sh > "$T/old/evals/harness/lib/sandbox-mount.sh" 2>/dev/null
}

@test "HS-4 the pinned-root mount (cycle-132 addendum 9) is unchanged: byte-identical sandbox and evidence to the Sprint 2 library on the synthetic PR (also under the bats prefix override) and on the pr-16 and pr-20 fixtures" {
  local out
  # the synthetic PR: the digests the Sprint 2 library (de366cc63) produced, pinned so a shallow clone still checks
  cp -a "$W" "$T/ws-pin"; cp "$ARM_EVIDENCE_FILE" "$T/ev-pin.txt"
  pr_seq "$LIB" "$T/ws-pin" "$FX" "$SRC" "$F" "$T/ev-pin.txt"
  [ "$(tree_sum "$T/ws-pin")" = "$HS4_SANDBOX_SHA" ]
  [ "$(sed "s|$T/ws-pin|WS|g; s|$T|T|g" "$T/ev-pin.txt" | python3 -I -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')" = "$HS4_EVIDENCE_SHA" ]
  ! grep -q '^mount_mode=' "$T/ev-pin.txt" || false
  old_lib || skip "de366cc63 is not in this clone (the pinned digests above still held)"
  out="$(both_libs "$FX" "$SRC" "$F" "$W")"
  [ "$(wc -l <<<"$out")" -eq 2 ] && [ "$(sed -n 1p <<<"$out")" = "$(sed -n 2p <<<"$out")" ] || { echo "$out"; false; }
  # the cycle-131 overlay mechanics under the bats-gated prefix override
  out="$(SM_TEST_MODE=1 SM_TEST_EXCLUDED_PREFIX=.claude/hooks/ both_libs "$FX" "$SRC" "$F" "$W")"
  [ "$(wc -l <<<"$out")" -eq 2 ] && [ "$(sed -n 1p <<<"$out")" = "$(sed -n 2p <<<"$out")" ] || { echo "$out"; false; }
  # the cycle-132 corpus: pr-16 and pr-20 mounted from this repository at its HEAD
  local n fx2 ws2 head
  head="$(git -C "$REPO_ROOT" rev-parse HEAD)"
  [ -z "$(git -C "$REPO_ROOT" status --porcelain --untracked-files=all -- .claude | sed -n 1p)" ] || skip "this checkout's .claude/ is dirty"
  for n in 16 20; do
    fx2="$REPO_ROOT/evals/fixtures/review-prs/pr-$n"
    git -C "$REPO_ROOT" cat-file -e "$(yq -r .fix_commit "$fx2/fixture.yaml")^{commit}" 2>/dev/null || skip "record commits not in this clone"
    ws2="$T/tpl-$n"; mkdir -p "$ws2/pr"
    for p in base head head.diff PR.md; do [[ -e "$fx2/$p" ]] && cp -a "$fx2/$p" "$ws2/pr/"; done
    g "$ws2" init -q; g "$ws2" add -A; g "$ws2" commit -qm base
    printf 'base_commit=%s\n' "$(git -C "$ws2" rev-parse HEAD)" > "$ARM_EVIDENCE_FILE"
    out="$(both_libs "$fx2" "$REPO_ROOT" "$head" "$ws2")"
    [ "$(wc -l <<<"$out")" -eq 2 ] && [ "$(sed -n 1p <<<"$out")" = "$(sed -n 2p <<<"$out")" ] || { echo "pr-$n: $out"; false; }
  done
}

# --- HS-5 … HS-8: took-effect oracle_closed clauses (f) and (g) on a home-scope run --------------------------------
hs_suite() {
  S_HS="$T/suite-hs.yaml"
  cp "$TESTS_DIR/fixtures/ablation-runs/suite.yaml" "$S_HS"
  yq -i '.arms += [{"id": "a1_home", "task_types": ["review-catch"], "toggles": {}, "took_effect": ["oracle_closed"]}]' "$S_HS"
}
# hs_record <phases-json> — the run record took-effect reads, and the task yaml naming the fixture
hs_record() {
  echo a1_home > "$RD/meta/arm"
  jq -n --arg sc "$F" --argjson ph "$1" '{schema_version: 1, arm: "a1_home", task_id: "rc-hs", task_type: "review-catch",
     status: "completed", source_commit: $sc, arm_toggles: {}, phases: $ph}' > "$RD/meta/pipeline.json"
  mkdir -p "$T/suite/tasks/rc-hs"
  printf 'id: rc-hs\ntype: review-catch\nreview_catch: {fixture: "%s"}\n' "$FX" > "$T/suite/tasks/rc-hs/task.yaml"
  TY="$T/suite/tasks/rc-hs/task.yaml"
}
# hs_run — the home-scope overlay, the mount's declarations, and two clean phases (REVIEW, AUDIT)
hs_run() {
  hs_overlay; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  # what the home-scope mount declares from the pinned user settings: their SessionStart hook count; no MCP server
  printf 'home_hook_counts=SessionStart:1\nhome_mcp_servers=\n' >> "$ARM_EVIDENCE_FILE"
  hs_record '[{"name": "REVIEW", "label": "REVIEW"}, {"name": "AUDIT", "label": "AUDIT"}]'
  local l
  for l in REVIEW AUDIT; do init_ev "$l"; hook_ev "$l" SessionStart; ps_ok "$l"; done
  hs_suite
}
init_ev() {  # init_ev <label> [jq edit] — Claude Code 2.1.299's system/init event (the fields clause (g) reads)
  jq -cn '{type: "system", subtype: "init", cwd: "/workspace", session_id: "s", mcp_servers: [],
    slash_commands: ["review-sprint", "audit-sprint", "compact"], skills: ["reviewing-code", "auditing-security"],
    agents: ["general-purpose", "Explore", "a"], output_style: "default", claude_code_version: "2.1.299",
    plugins: [{name: "cc-plugin-agents-md", path: "builtin", source: "cc-plugin-agents-md@builtin"}],
    memory_paths: {auto: "/home/evaluser/.claude/projects/-workspace/memory/"}}' | jq -c "${2:-.}" >> "$RD/transcripts/events-$1.jsonl"
}
hook_ev() {  # hook_ev <label> <event> [stdout] — a hook_started / hook_response pair (2.1.299 names no command)
  jq -cn --arg e "$2" '{type: "system", subtype: "hook_started", hook_id: "h", hook_name: ($e + ":startup"), hook_event: $e}' >> "$RD/transcripts/events-$1.jsonl"
  jq -cn --arg e "$2" --arg o "${3:-}" '{type: "system", subtype: "hook_response", hook_id: "h", hook_name: ($e + ":startup"),
    hook_event: $e, output: $o, stdout: $o, stderr: "", exit_code: 0, outcome: "success"}' >> "$RD/transcripts/events-$1.jsonl"
}
ps_ok() {  # ps_ok <label> — the one-second process samples of a clean phase (reads of PR files, the pinned framework)
  {
    printf '# sample 1\n'
    printf '1 0 python3 -I -c <shim> timeout --signal=TERM 1800 claude -p Run /review-sprint sprint-1 on pr/head.diff\n'
    printf '7 1 claude -p Run /review-sprint sprint-1\n'
    printf "9 7 /bin/bash -c -l source /home/evaluser/.claude/shell-snapshots/snapshot-bash-1.sh && eval 'cat pr/head/.claude/hooks/h.sh' < /dev/null && pwd -P >| /workspace/.eval/tmp/claude-1-cwd\n"
    printf '10 9 cat pr/head/.claude/hooks/h.sh\n'
    printf '# sample 2\n'
    printf '7 1 claude -p Run /review-sprint sprint-1\n'
    printf '12 7 bash /home/evaluser/.claude/scripts/flatline-orchestrator.sh --diff-file pr/head.diff\n'
    printf '13 7 bats pr/head/tests/unit/t.bats\n'
  } > "$RD/meta/ps-$1.txt"
}
tu() {  # tu <label> <id> <tool> <input-json> <result-text> [is_error] — a tool_use and its tool_result
  jq -cn --arg id "$2" --arg t "$3" --argjson i "$4" '{type: "assistant", message: {content: [{type: "tool_use", id: $id, name: $t, input: $i}]}}' >> "$RD/transcripts/events-$1.jsonl"
  jq -cn --arg id "$2" --arg r "$5" --argjson e "${6:-false}" \
    '{type: "user", message: {content: [{type: "tool_result", tool_use_id: $id, content: $r} + (if $e then {is_error: true} else {} end)]}}' >> "$RD/transcripts/events-$1.jsonl"
}
# gut <file> [<offset> <limit>] — a Read result as Claude Code 2.1.299 prints it: "<n><TAB><line>", no padding, the empty
# line after a final newline included
gut() {
  python3 -I -c '
import sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
o = int(sys.argv[2]) if len(sys.argv) > 2 else 1
n = int(sys.argv[3]) if len(sys.argv) > 3 else len(lines)
sys.stdout.write("\n".join("%d\t%s" % (i, lines[i - 1]) for i in range(o, min(len(lines), o + n - 1) + 1)))' "$@"
}
rd_in() { jq -cn --arg f "$1" '{file_path: $f}'; }
rd_win() { jq -cn --arg f "$1" --argjson o "$2" --argjson l "$3" '{file_path: $f, offset: $o, limit: $l}'; }
bash_in() { jq -cn --arg c "$1" '{command: $c}'; }
fb() { printf '# Review\n\n%s\n\n<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED"} -->\n' "$1" > "$W/grimoires/loa/a2a/sprint-1/engineer-feedback.md"; }
te_hs() { run "$TE" --run-dir "$RD" --suite-file "$S_HS" --task-yaml "$TY" --source-repo "$SRC"; }
oc() { printf '%s\n' "$output" | grep -E '^arm a1_home: oracle_closed '; }
reset_run() { find "$RD" -mindepth 1 -delete; cp -a "$T/run0/." "$RD/"; }
read_p() { tu REVIEW r1 Read "$(rd_in /workspace/.claude/protocols/p.md)" "$(gut "$W/.claude/protocols/p.md")"; fb 'head/.claude/protocols/p.md:5 the guard wording'; }

@test "HS-5 clause (f): pr_bytes_read credits Read results returning the PR's bytes (a root data path; a pr/head/ surface path in two windows across phases); Grep and a 50 % window never count; every cited file must be read; an empty set FAILs" {
  hs_run
  te_hs
  [ "$status" -eq 1 ]; oc | grep -qF 'FAIL (f) -: pr_bytes_read is empty' || { echo "$output"; false; }
  tu REVIEW r1 Read "$(rd_in /workspace/.claude/protocols/p.md)" "$(gut "$W/.claude/protocols/p.md")"
  tu REVIEW r2 Read "$(rd_win /workspace/pr/head/.claude/skills/reviewing-code/SKILL.md 1 1)" "$(gut "$W/pr/head/.claude/skills/reviewing-code/SKILL.md" 1 1)"
  tu AUDIT a1 Read "$(rd_win /workspace/pr/head/.claude/skills/reviewing-code/SKILL.md 2 5)" "$(gut "$W/pr/head/.claude/skills/reviewing-code/SKILL.md" 2 5)"
  tu REVIEW r3 Grep '{"pattern": "version", "path": "/workspace/.claude/scripts/s.sh", "output_mode": "content"}' "$(printf '.claude/scripts/s.sh:1:%s' "$(sed -n 1p "$W/.claude/scripts/s.sh")")"
  tu REVIEW r4 Read "$(rd_win /workspace/.claude/scripts/s.sh 2 1)" "$(gut "$W/.claude/scripts/s.sh" 2 1)"   # 1 of 2 lines
  fb 'head/.claude/protocols/p.md:5 the guard wording; pr/head/.claude/skills/reviewing-code/SKILL.md:2 the skill text'
  te_hs
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  oc | grep -qF 'pr_bytes_read=[".claude/protocols/p.md",".claude/skills/reviewing-code/SKILL.md"]'
  oc | grep -qF 'cited=[".claude/protocols/p.md",".claude/skills/reviewing-code/SKILL.md"]'
  oc | grep -qF 'transcript_schema=claude-stream-json/2.1.299'
  oc | grep -qF 'grep_only=[".claude/scripts/s.sh"]'
  # a cited file seen only through Grep and a 50 % window is not read
  fb 'head/.claude/protocols/p.md:5; .claude/scripts/s.sh:2 the script'
  te_hs
  [ "$status" -eq 1 ]; oc | grep -qF 'FAIL (f) .claude/scripts/s.sh: cited by the review but its PR bytes were never read' || { echo "$output"; false; }
  tu AUDIT a2 Read "$(rd_in /workspace/.claude/scripts/s.sh)" "$(gut "$W/.claude/scripts/s.sh")"
  te_hs
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  oc | grep -qF 'pr_bytes_read=[".claude/protocols/p.md",".claude/scripts/s.sh",".claude/skills/reviewing-code/SKILL.md"]'
  # an errored Read and a read whose lines are not the PR's (a root file edited by the agent) never count
  hs_record '[{"name": "REVIEW", "label": "REVIEW"}, {"name": "AUDIT", "label": "AUDIT"}]'
  : > "$RD/transcripts/events-REVIEW.jsonl"; : > "$RD/transcripts/events-AUDIT.jsonl"
  init_ev REVIEW; hook_ev REVIEW SessionStart; init_ev AUDIT; hook_ev AUDIT SessionStart
  tu REVIEW e1 Read "$(rd_in /workspace/.claude/protocols/p.md)" "$(gut "$W/.claude/protocols/p.md")" true
  tu REVIEW e2 Read "$(rd_in /workspace/.claude/data/new.txt)" "$(printf '1\tsomething else\n2\t')"
  fb 'no citation'
  te_hs
  [ "$status" -eq 1 ]; oc | grep -qF 'FAIL (f) -: pr_bytes_read is empty' || { echo "$output"; false; }
}

@test "HS-5b clause (f): a read of the pinned (later) bytes FAILs as pinned_bytes_read — the HOME framework copy, a root path at the pin, a diff against the HOME copy; the PR's own bytes never do" {
  hs_run; read_p
  te_hs; [ "$status" -eq 0 ] || { echo "$output"; false; }
  oc | grep -qF 'pinned_bytes_read=[]'
  cp -a "$RD" "$T/run0"
  git -C "$SRC" show "$F:.claude/protocols/p.md" > "$T/pinned-p.md"
  tu REVIEW r2 Read "$(rd_in /home/evaluser/.claude/protocols/p.md)" "$(gut "$T/pinned-p.md")"
  te_hs
  [ "$status" -eq 1 ]; oc | grep -qF 'FAIL (f) .claude/protocols/p.md: pinned_bytes_read: a later-only line of the pinned version in Read /home/evaluser/.claude/protocols/p.md (events-REVIEW.jsonl' || { echo "$output"; false; }
  reset_run
  tu AUDIT a1 Read "$(rd_in /workspace/.claude/protocols/p.md)" "$(gut "$T/pinned-p.md")"
  te_hs
  [ "$status" -eq 1 ]; oc | grep -qF 'FAIL (f) .claude/protocols/p.md: pinned_bytes_read' || { echo "$output"; false; }
  reset_run
  tu AUDIT a2 Bash "$(bash_in 'diff pr/head/.claude/protocols/p.md ~/.claude/protocols/p.md')" \
    "$(printf 'Exit code 1\n5c5\n< protocol line 5 says the guard runs (head version)\n---\n> protocol line 5 now says the guard ALWAYS runs (LATER fix)')" true
  te_hs
  [ "$status" -eq 1 ]; oc | grep -qF 'FAIL (f) .claude/protocols/p.md: pinned_bytes_read: a later-only line of the pinned version in Bash' || { echo "$output"; false; }
}

# mut <case> — one clause (g) violation applied to the clean run
mut() {
  case "$1" in
    ps_pr_hook)   printf '20 9 /bin/bash /workspace/pr/head/.claude/hooks/h.sh\n' >> "$RD/meta/ps-REVIEW.txt" ;;
    ps_root_exec) printf '21 9 /workspace/.claude/scripts/s.sh --flag\n' >> "$RD/meta/ps-AUDIT.txt" ;;
    ps_eval)      printf "22 7 /bin/bash -c -l source /home/evaluser/.claude/shell-snapshots/s.sh && eval 'python3 pr/head/.claude/scripts/s.sh' < /dev/null\n" >> "$RD/meta/ps-REVIEW.txt" ;;
    bash_tool)    tu REVIEW b1 Bash "$(bash_in 'cd /workspace && bash .claude/scripts/s.sh')" ok ;;
    bash_source)  tu AUDIT b2 Bash "$(bash_in 'source pr/head/.claude/hooks/h.sh; echo done')" done ;;
    bash_direct)  tu AUDIT b3 Bash "$(bash_in 'FOO=1 timeout 5 ./pr/head/.claude/scripts/s.sh')" ok ;;
    mcp)          : > "$RD/transcripts/events-REVIEW.jsonl"; init_ev REVIEW '.mcp_servers = [{"name": "pr-mcp", "status": "connected"}]'; hook_ev REVIEW SessionStart; read_p ;;
    skill)        : > "$RD/transcripts/events-AUDIT.jsonl"; init_ev AUDIT '.skills += ["pr-only"]'; hook_ev AUDIT SessionStart ;;
    plugin)       : > "$RD/transcripts/events-AUDIT.jsonl"; init_ev AUDIT '.plugins += [{"name": "pl", "path": "/workspace/.claude/plugins/pl", "source": "pl@project"}]'; hook_ev AUDIT SessionStart ;;
    style)        : > "$RD/transcripts/events-AUDIT.jsonl"; init_ev AUDIT '.output_style = "o"'; hook_ev AUDIT SessionStart ;;
    hooks)        hook_ev AUDIT SessionStart ;;
    no_hook_decl) sed -i '/^home_hook_counts=/d' "$ARM_EVIDENCE_FILE" ;;
    no_ps)        rm -f "$RD/meta/ps-AUDIT.txt" ;;
    skill_base)   jq -cn '{type: "user", message: {content: [{type: "text", text: "Base directory for this skill: /workspace/pr/head/.claude/skills/pr-only\n\n# pr-only"}]}}' >> "$RD/transcripts/events-AUDIT.jsonl" ;;
  esac
}

@test "HS-6 clause (g): a clean run passes (reads of PR files, the pinned HOME framework, PR tests outside .claude/ are not executions); each project hook, MCP server, plugin, PR-only skill or style, PR .claude/ execution, missing capture or missing hook declaration FAILs by name" {
  hs_run; read_p
  tu REVIEW c1 Bash "$(bash_in 'cat pr/head/.claude/hooks/h.sh; grep -n version .claude/scripts/s.sh; python3 -c "print(1)" pr/head/.claude/scripts/s.sh')" ok
  tu AUDIT c2 Bash "$(bash_in 'bash ~/.claude/scripts/flatline-orchestrator.sh --diff-file pr/head.diff | tee .eval/tmp/x.log')" ok
  jq -cn '{type: "user", message: {content: [{type: "text", text: "Base directory for this skill: /home/evaluser/.claude/skills/reviewing-code"}]}}' >> "$RD/transcripts/events-REVIEW.jsonl"
  te_hs
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  oc | grep -qF '(g) 2 phase(s): 0 PR .claude/ executions in 4 process sample(s) and 2 Bash command(s); hooks within home_hook_counts SessionStart:1; no project MCP server, plugin, skill, command, agent or output style; no canary planted' || { echo "$output"; false; }
  cp -a "$RD" "$T/run0"
  local c want
  while IFS='|' read -r c want; do
    reset_run; mut "$c"
    te_hs
    [ "$status" -eq 1 ] || { echo "case $c passed: $output"; false; }
    oc | grep -qF "$want" || { echo "case $c: $(oc) — want $want"; false; }
  done <<'CASES'
ps_pr_hook|FAIL (g) pr/head/.claude/hooks/h.sh: executed a PR .claude/ path (meta/ps-REVIEW.txt pid 20)
ps_root_exec|FAIL (g) .claude/scripts/s.sh: executed a PR .claude/ path (meta/ps-AUDIT.txt pid 21)
ps_eval|FAIL (g) pr/head/.claude/scripts/s.sh: executed a PR .claude/ path (meta/ps-REVIEW.txt pid 22)
bash_tool|FAIL (g) .claude/scripts/s.sh: executed a PR .claude/ path (Bash b1 in events-REVIEW.jsonl)
bash_source|FAIL (g) pr/head/.claude/hooks/h.sh: executed a PR .claude/ path (Bash b2 in events-AUDIT.jsonl)
bash_direct|FAIL (g) pr/head/.claude/scripts/s.sh: executed a PR .claude/ path (Bash b3 in events-AUDIT.jsonl)
mcp|FAIL (g) -: MCP server pr-mcp loaded (events-REVIEW.jsonl init; home_mcp_servers declares none)
skill|FAIL (g) -: the PR-only skill pr-only was loaded (events-AUDIT.jsonl init)
plugin|FAIL (g) -: plugin pl loaded from the project (/workspace/.claude/plugins/pl; events-AUDIT.jsonl init)
style|FAIL (g) -: the PR-only output style o was loaded (events-AUDIT.jsonl init)
hooks|FAIL (g) -: 2 SessionStart hook(s) ran in events-AUDIT.jsonl; the pinned user settings declare 1 (home_hook_counts)
no_hook_decl|FAIL (g) -: no home_hook_counts evidence (the mount declares the pinned user settings' hooks)
no_ps|FAIL (g) -: no process capture for AUDIT (meta/ps-AUDIT.txt)
skill_base|FAIL (g) -: a skill loaded from the workspace: /workspace/pr/head/.claude/skills/pr-only (events-AUDIT.jsonl)
CASES
}

@test "HS-7 every surface item with a planted canary (design-neutral, FR-10 AC 3): absent at the root, the PR's bytes under pr/head/, never loaded or executed; each simulated execution (effect file, token in a process) or load (token in a hook's output, a PR-only name in init) is named" {
  hs_run; read_p
  local i=0 p item ch name
  : > "$RD/meta/canaries.tsv"
  while IFS=$'\t' read -r p item ch; do
    i=$((i + 1)); name=-
    case "$p" in .claude/skills/pr-only/SKILL.md) name=pr-only ;; .claude/output-styles/o.md) name=o ;; esac
    printf '%s\t%s\t%s\tsandbox/.eval/canary-%d\tLOA_CANARY_T%d\n' "$item" "$p" "$name" "$i" "$i" >> "$RD/meta/canaries.tsv"
    gone "$p" || { echo "$item is at the root"; false; }
    cmp -s "$W/pr/head/$p" "$FX/head/$p" || { echo "$item: pr/head/ is not the PR's bytes"; false; }
  done <<<"$SURFACE_ITEMS"
  te_hs
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  oc | grep -qF '17 canaries planted, none loaded or executed' || { echo "$output"; false; }
  cp -a "$RD" "$T/run0"
  i=0
  while IFS=$'\t' read -r p item ch; do
    i=$((i + 1))
    reset_run; : > "$RD/sandbox/.eval/canary-$i"
    te_hs
    [ "$status" -eq 1 ]; oc | grep -qF "FAIL (g) $p: the canary for $item executed (sandbox/.eval/canary-$i exists)" || { echo "$item: $(oc)"; false; }
    reset_run; printf '30 7 sh -c echo LOA_CANARY_T%d\n' "$i" >> "$RD/meta/ps-REVIEW.txt"
    te_hs
    [ "$status" -eq 1 ]; oc | grep -qF "FAIL (g) $p: the canary for $item executed (LOA_CANARY_T$i in meta/ps-REVIEW.txt)" || { echo "$item: $(oc)"; false; }
  done <<<"$SURFACE_ITEMS"
  reset_run; hook_ev REVIEW Stop "LOA_CANARY_T3"
  te_hs
  [ "$status" -eq 1 ]; oc | grep -qF 'FAIL (g) .claude/hooks/h.sh: the canary for hook loaded (LOA_CANARY_T3 in a hook_response of events-REVIEW.jsonl)' || { echo "$(oc)"; false; }
  reset_run; : > "$RD/transcripts/events-AUDIT.jsonl"; init_ev AUDIT '.slash_commands += ["pr-only"]'; hook_ev AUDIT SessionStart
  te_hs
  [ "$status" -eq 1 ]; oc | grep -qF 'FAIL (g) -: the PR-only skill pr-only was loaded (events-AUDIT.jsonl init)' || { echo "$(oc)"; false; }
}

# --- HS-8: the negative control ---------------------------------------------------------------------------------------
@test "HS-8 the negative control (fixtures/home-scope-nc): distinct PR and pinned bytes for one path; on the cycle-132 mount a reviewer Read exposes the fix and the grader's oracle detector fires; on the home-scope root the same Read exposes nothing and clause (f) credits it" {
  # the fixture's pinned bytes, and the three distinct versions of the path
  run python3 -I -c '
import hashlib, os, sys
os.chdir(sys.argv[1]); bad = 0
for line in open("SHA256SUMS"):
    h, p = line.rstrip("\n").split("  ", 1)
    if hashlib.sha256(open(p, "rb").read()).hexdigest() != h: print("changed", p); bad = 1
sys.exit(bad)' "$NC"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local q=.claude/protocols/nc-guard.md
  ! cmp -s "$NC/pr-nc/head/$q" "$NC/pinned/$q" && ! cmp -s "$NC/pr-nc/base/$q" "$NC/pinned/$q" && ! cmp -s "$NC/pr-nc/head/$q" "$NC/pr-nc/base/$q"
  # the pinned source tree, the grader's suite and task
  local S2="$T/nc-src" GS="$T/gsuite" P2 mode rd
  mkdir -p "$S2" "$GS/tasks/rc-nc"; cp -a "$NC/pinned/." "$S2/"
  ( cd "$S2" && g . init -q && g . add -A && g . commit -qm pin )
  P2="$(git -C "$S2" rev-parse HEAD)"
  printf 'Review the pull request.\n' > "$GS/tasks/rc-nc/TASK.md"
  cat > "$GS/tasks/rc-nc/task.yaml" <<YAML
id: rc-nc
schema_version: 1
type: review-catch
fixture: null
criterion: "review the change"
test_command: null
regression_command: null
reference_patch: null
grader_protected: []
structural_check: null
review_catch: {fixture: "$NC/pr-nc", manifest: "$NC/manifests/pr-nc.json"}
suite_version: 1
YAML
  for mode in pinned-root home-scope; do
    RD="$T/nc-$mode"; W="$RD/sandbox"; ARM_EVIDENCE_FILE="$RD/meta/arm-evidence.txt"
    mkdir -p "$W/pr" "$RD/meta" "$RD/transcripts" "$RD/eval" "$RD/snapshots"
    cp -a "$NC/pr-nc/base" "$NC/pr-nc/head" "$NC/pr-nc/head.diff" "$NC/pr-nc/PR.md" "$W/pr/"
    g "$W" init -q; printf '/.claude/\n/CLAUDE.md\n' >> "$W/.git/info/exclude"; g "$W" add -A; g "$W" commit -qm base
    printf 'base_commit=%s\n' "$(git -C "$W" rev-parse HEAD)" > "$ARM_EVIDENCE_FILE"
    if [[ "$mode" == pinned-root ]]; then
      lib mount_prompt_surface "$W" "$S2" -; [ "$status" -eq 0 ]
      lib overlay_answer_paths "$W" "$NC/pr-nc" head "$S2" "$P2"; [ "$status" -eq 0 ] || { echo "$output"; false; }
      cmp -s "$W/$q" "$NC/pinned/$q"            # the cycle-132 root holds the pinned (later) bytes
    else
      lib overlay_answer_paths "$W" "$NC/pr-nc" head "$S2" "$P2" home-scope; [ "$status" -eq 0 ] || { echo "$output"; false; }
      cmp -s "$W/$q" "$NC/pr-nc/head/$q"        # the home-scope root holds the PR's bytes
    fi
    lib check_mount_closed "$W" "$NC/pr-nc" "$S2"; [ "$status" -eq 0 ] || { echo "$output"; false; }
    echo '{}' > "$RD/snapshots/index.json"
    printf 'pr/head/%s:8 the guard skips the spend check\n' "$q" > "$W/review.md"
    mkdir -p "$W/grimoires/loa/a2a/sprint-1"
    printf '# Review\n\nhead/%s:8 the guard silently skips the spend check\n' "$q" > "$W/grimoires/loa/a2a/sprint-1/engineer-feedback.md"
    init_ev REVIEW; hook_ev REVIEW SessionStart; ps_ok REVIEW
    tu REVIEW n1 Read "$(rd_in "/workspace/$q")" "$(gut "$W/$q")"
    jq -n --arg sc "$P2" '{schema_version: 1, run_id: "r-nc", arm: "a1_home", task_id: "rc-nc", task_type: "review-catch",
       status: "completed", source_commit: $sc, arm_toggles: {}, phases: [{name: "REVIEW", label: "REVIEW"}]}' > "$RD/meta/pipeline.json"
    echo a1_home > "$RD/meta/arm"
    run env LOA_EVAL_ALLOW_HOST_GRADING=1 "$GRADER" "$RD" rc-nc --suite-root "$GS" --allow-unfrozen --docker-bin /bin/false
    [ "$status" -eq 0 ] || { echo "$mode grade: $output"; false; }
    if [[ "$mode" == pinned-root ]]; then
      [ "$(jq -r '.oracle_exposed_defects | join(",")' "$RD/grade.json")" = d1 ] || { jq -c '.oracle_exposed_events' "$RD/grade.json"; false; }
      [ "$(jq -r '.oracle_exposed_by_form.read | join(",")' "$RD/grade.json")" = d1 ]
    else
      [ "$(jq -r '.oracle_exposed_defects | length' "$RD/grade.json")" = 0 ] || { jq -c '.oracle_exposed_events' "$RD/grade.json"; false; }
      printf 'home_hook_counts=SessionStart:1\nhome_mcp_servers=\n' >> "$ARM_EVIDENCE_FILE"
      hs_suite
      run "$TE" --run-dir "$RD" --suite-file "$S_HS" --task-yaml "$GS/tasks/rc-nc/task.yaml" --source-repo "$S2"
      [ "$status" -eq 0 ] || { echo "$output"; false; }
      oc | grep -qF "pr_bytes_read=[\"$q\"]"
    fi
  done
}

@test "HS-9 the suite's mount_mode (additive): the shipped suite declares pinned-root and dry-runs as before; arms[].mount_mode wins over mount_mode.default; home-scope dry-runs as mount=home-scope in the container executor and is refused on the host, for a build task and for an unknown mode; an unmounted arm ignores it" {
  [ "$(yq -r '.mount_mode.default' "$REPO_ROOT/evals/suites/ablation-2.0.yaml")" = pinned-root ]
  [ "$(yq -r '[.arms[] | select(has("mount_mode"))] | length' "$REPO_ROOT/evals/suites/ablation-2.0.yaml")" = 0 ]
  local PRUN="$REPO_ROOT/evals/harness/pipeline-run.sh" ST="$T/suite-mm.yaml"
  mkdir -p "$T/mm/tasks/rc-mm" "$T/mm/tasks/bf-mm/fx"
  printf 'Review the pull request in pr/.\n' > "$T/mm/tasks/rc-mm/TASK.md"
  printf 'id: rc-mm\nschema_version: 1\ntype: review-catch\nfixture: null\ncriterion: "review the change"\nreview_catch: {fixture: "%s"}\n' "$FX" > "$T/mm/tasks/rc-mm/task.yaml"
  printf 'Fix it.\n' > "$T/mm/tasks/bf-mm/TASK.md"
  printf 'id: bf-mm\nschema_version: 1\ntype: bug-fix\nfixture: fx\ncriterion: "fixed"\ntest_command: ["true"]\n' > "$T/mm/tasks/bf-mm/task.yaml"
  cp "$REPO_ROOT/evals/suites/ablation-2.0.yaml" "$ST"
  dry() { run "$PRUN" --task-yaml "$T/mm/tasks/${2:-rc-mm}/task.yaml" --arm "${1:-a1_full}" --run-id r --trial 1 --source-tree "$SRC" --suite-file "$ST" --dry-run "${@:3}"; }
  dry
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q '^sandbox: mount=loa overlay=head ' <<<"$output"
  yq -i '.mount_mode.default = "home-scope"' "$ST"
  dry
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q '^sandbox: mount=home-scope overlay=head ' <<<"$output"
  dry a1_full rc-mm --executor host
  [ "$status" -eq 2 ]; grep -qF "refused: arm 'a1_full': mount_mode home-scope needs --executor container" <<<"$output"
  dry a1_full bf-mm
  [ "$status" -eq 2 ]; grep -qF "mount_mode home-scope mounts a review-catch PR (task type bug-fix)" <<<"$output"
  dry a0_bare rc-mm                     # loa_mount: false: no mount, the mode does not apply
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q '^sandbox: mount=none ' <<<"$output"
  yq -i '.mount_mode.default = "pinned-root" | (.arms[] | select(.id == "a1_full") | .mount_mode) = "home-scope"' "$ST"
  dry
  [ "$status" -eq 0 ]; grep -q '^sandbox: mount=home-scope ' <<<"$output"
  yq -i '(.arms[] | select(.id == "a1_full") | .mount_mode) = "open-root"' "$ST"
  dry
  [ "$status" -eq 2 ]; grep -qF "mount_mode 'open-root' is not pinned-root|home-scope" <<<"$output"
  [ ! -e "$T/mm/run" ]
}

# --- HS-10 … HS-12: the home-scope launch path (Sprint 274 spike confirmed: --setting-sources user) ----------------
# make_fw <dir> — a Loa-shaped pinned framework: the hook prefix, project-root shell forms, Python root joins and
# literals, relative skill text, rules, a tests file the transform leaves alone; committed
make_fw() {
  local d="$1"
  mkdir -p "$d/.claude/hooks" "$d/.claude/scripts" "$d/.claude/skills/reviewing-code" "$d/.claude/skills/auditing-security" \
           "$d/.claude/adapters/loa_cheval/config" "$d/.claude/adapters/loa_cheval/providers" "$d/.claude/rules" "$d/.claude/loa" \
           "$d/.claude/tests" "$d/.claude/defaults" "$d/.claude/protocols"
  jq -n '{hooks: {SessionStart: [{hooks: [{type: "command", command: "\"$(git rev-parse --show-toplevel)\"/.claude/hooks/a.sh"},
                                          {type: "command", command: "\"$(git rev-parse --show-toplevel)\"/.claude/hooks/a.sh x"}]}],
                 PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: "\"$(git rev-parse --show-toplevel)\"/.claude/hooks/a.sh"}]}]}}' \
    > "$d/.claude/settings.json"
  printf '#!/usr/bin/env bash\nsource "$PROJECT_ROOT/.claude/scripts/lib.sh"\ncfg="${PROJECT_ROOT}/.claude/defaults/x.yaml"\n' > "$d/.claude/hooks/a.sh"
  printf '#!/usr/bin/env bash\nROOT="$(git rev-parse --show-toplevel)"\ncat "$ROOT"/.claude/data/d.txt\nbash "$(git rev-parse --show-toplevel)"/.claude/scripts/t.sh\ncase "$f" in .claude/*) echo system ;; esac\n' > "$d/.claude/scripts/s.sh"
  printf 'pinned lib\n' > "$d/.claude/scripts/lib.sh"
  printf -- '---\nname: reviewing-code\n---\nRun `.claude/scripts/s.sh` and read .claude/protocols/p.md; never pr/head/.claude/x or ~/.claude/y.\npinned skill text LATER\n' > "$d/.claude/skills/reviewing-code/SKILL.md"
  printf -- '---\nname: auditing-security\n---\nAudit.\n' > "$d/.claude/skills/auditing-security/SKILL.md"
  : > "$d/.claude/adapters/loa_cheval/__init__.py"; : > "$d/.claude/adapters/loa_cheval/providers/__init__.py"; : > "$d/.claude/adapters/loa_cheval/config/__init__.py"
  cat > "$d/.claude/adapters/loa_cheval/config/loader.py" <<'PY'
from pathlib import Path


def load(project_root):
    return Path(project_root) / ".claude" / "defaults" / "model-config.yaml"


def other(repo_root):
    return repo_root / ".claude" / "x"


DEFAULT = ".claude/defaults/model-config.yaml"
DIRS = [".claude/skills", ".claude"]


def detect(parent):
    return (parent / ".claude").is_dir()
PY
  printf 'rule a\n' > "$d/.claude/rules/a.md"; printf 'rule b\n' > "$d/.claude/rules/b.md"
  printf 'loa instructions\n' > "$d/.claude/loa/CLAUDE.loa.md"
  printf '#!/usr/bin/env bash\necho "$PROJECT_ROOT/.claude/x"\n' > "$d/.claude/tests/t.sh"
  printf 'catalog: pinned\n' > "$d/.claude/defaults/model-config.yaml"
  printf 'protocol pinned\n' > "$d/.claude/protocols/p.md"
  chmod +x "$d/.claude/hooks/a.sh" "$d/.claude/scripts/s.sh"
  printf 'flatline_protocol:\n  enabled: true\n' > "$d/.loa.config.yaml"
  ( cd "$d" && g . init -q && g . add -A && g . commit -qm framework )
}
hs_home() { lib mount_home_scope "$1" "$2" /home/evaluser "$1.report.json"; }

@test "HS-10 mount_home_scope: the pinned framework under HOME redirected through LOA_FRAMEWORK_ROOT (hook commands, shell roots, python roots and literals, skill text absolute), tests untouched, rules imported by absolute path, reverse == pinned; residual, already-named and occupied-HOME cases refused" {
  local fw="$T/fw" hh="$T/hh"
  make_fw "$fw"; mkdir -p "$hh"
  hs_home "$hh" "$fw"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ev mount)" = home-scope ]
  [ "$(ev framework_root)" = LOA_FRAMEWORK_ROOT=/home/evaluser ]
  [ "$(ev home_transform)" = R1:4,R2:3,R3:2,R4:2,R5:3 ]
  [ "$(ev home_residual)" = 0 ]
  grep -qx 'home_verify=ok [0-9]* files, 5 redirected, reverse == pinned' "$ARM_EVIDENCE_FILE"
  [ "$(ev home_hook_counts)" = PreToolUse:1,SessionStart:2 ]
  [ "$(ev home_mcp_servers)" = "" ]
  # R1: every hook command through the root variable
  [ "$(jq -r '[.. | objects | select(has("command")) | .command | startswith("\"${LOA_FRAMEWORK_ROOT:-$(git rev-parse --show-toplevel)}\"/.claude/hooks/")] | all' "$hh/.claude/settings.json")" = true ]
  # R2 (bare, braced, quoted) and R1 in shell; the relative case pattern stays (it classifies project paths)
  grep -qxF 'source "${LOA_FRAMEWORK_ROOT:-$PROJECT_ROOT}/.claude/scripts/lib.sh"' "$hh/.claude/hooks/a.sh"
  grep -qxF 'cfg="${LOA_FRAMEWORK_ROOT:-${PROJECT_ROOT}}/.claude/defaults/x.yaml"' "$hh/.claude/hooks/a.sh"
  grep -qxF 'cat "${LOA_FRAMEWORK_ROOT:-$ROOT}"/.claude/data/d.txt' "$hh/.claude/scripts/s.sh"
  grep -qxF 'bash "${LOA_FRAMEWORK_ROOT:-$(git rev-parse --show-toplevel)}"/.claude/scripts/t.sh' "$hh/.claude/scripts/s.sh"
  grep -qxF 'case "$f" in .claude/*) echo system ;; esac' "$hh/.claude/scripts/s.sh"
  # R3: skill text absolute; paths under pr/ and ~/ untouched
  grep -qF 'Run `/home/evaluser/.claude/scripts/s.sh` and read /home/evaluser/.claude/protocols/p.md; never pr/head/.claude/x or ~/.claude/y.' "$hh/.claude/skills/reviewing-code/SKILL.md"
  # tests are copied, never transformed; the generated user memory imports by absolute path
  cmp -s "$hh/.claude/tests/t.sh" "$fw/.claude/tests/t.sh"
  [ "$(cat "$hh/.claude/CLAUDE.md")" = $'@/home/evaluser/.claude/loa/CLAUDE.loa.md\n@/home/evaluser/.claude/rules/a.md\n@/home/evaluser/.claude/rules/b.md' ]
  # R4 and R5, functionally: with the variable the framework paths are the HOME copy's, without it the original ones
  run env LOA_FRAMEWORK_ROOT=/fw python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); from loa_cheval.config import loader as l
from pathlib import Path
print(l.load("/ws")); print(l.other(Path("/ws"))); print(l.DEFAULT); print(",".join(l.DIRS)); print(l.detect(Path("/nonexistent")))' "$hh/.claude/adapters"
  [ "$output" = $'/fw/.claude/defaults/model-config.yaml\n/fw/.claude/x\n/fw/.claude/defaults/model-config.yaml\n/fw/.claude/skills,/fw/.claude\nFalse' ] || { echo "$output"; false; }
  run python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); from loa_cheval.config import loader as l
print(l.load("/ws")); print(l.DEFAULT)' "$hh/.claude/adapters"
  [ "$output" = $'/ws/.claude/defaults/model-config.yaml\n.claude/defaults/model-config.yaml' ] || { echo "$output"; false; }
  # the report
  [ "$(jq -r '"\(.files_transformed) \(.residual) \(.framework_root_var)=\(.framework_root)"' "$hh.report.json")" = "5 0 LOA_FRAMEWORK_ROOT=/home/evaluser" ]
  # verify catches a byte outside the redirection, in a redirected file and in an untouched one
  sed -i 's/pinned skill text LATER/pinned skill text EDITED/' "$hh/.claude/skills/reviewing-code/SKILL.md"
  lib _sm_home_py verify "$hh" "$fw" /home/evaluser
  [ "$status" -eq 1 ]; grep -qF 'FAIL .claude/skills/reviewing-code/SKILL.md: differs from the pinned bytes beyond the recorded redirection' <<<"$output"
  # refusals: an occupied HOME .claude, a residual root join, a file that already names the variable, a bad home
  hs_home "$hh" "$fw"
  [ "$status" -eq 2 ]; grep -qF 'already holds files' <<<"$output"
  local fw2="$T/fw2" h2="$T/h2"; cp -a "$fw" "$fw2"; mkdir -p "$h2"
  printf 'from pathlib import Path\nBASE = Path("/x")\nP = BASE / ".claude" / "data"\n' > "$fw2/.claude/adapters/loa_cheval/extra.py"
  hs_home "$h2" "$fw2"
  [ "$status" -eq 2 ]; grep -qF '1 project-root framework reference(s) left unredirected (first: .claude/adapters/loa_cheval/extra.py:3 P = BASE / ".claude" / "data")' <<<"$output"
  rm -f "$fw2/.claude/adapters/loa_cheval/extra.py"; printf 'echo "$LOA_FRAMEWORK_ROOT"\n' > "$fw2/.claude/scripts/named.sh"
  find "$h2" -mindepth 1 -delete
  hs_home "$h2" "$fw2"
  [ "$status" -eq 2 ]; grep -qF '.claude/scripts/named.sh already names LOA_FRAMEWORK_ROOT' <<<"$output"
  lib mount_home_scope "$T/h3" "$fw" "relative/home" "$T/h3.json"
  [ "$status" -eq 2 ]
}

@test "HS-11 the real framework (this repository's .claude/): no residual project-root reference, every hook command through LOA_FRAMEWORK_ROOT, reverse == pinned; the HOME cheval loads the HOME catalog even when the workspace holds a PR catalog (and, unredirected, would load the PR's)" {
  [ -z "$(git -C "$REPO_ROOT" status --porcelain --untracked-files=all -- .claude | sed -n 1p)" ] || skip "this checkout's .claude/ is dirty"
  local hh="$T/rh" ws="$T/rws"
  mkdir -p "$hh" "$ws/.claude/defaults"
  hs_home "$hh" "$REPO_ROOT"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ev home_residual)" = 0 ]
  grep -q '^home_verify=ok [0-9]* files, [0-9]* redirected, reverse == pinned$' "$ARM_EVIDENCE_FILE"
  local total wrapped
  total="$(jq '[.. | objects | select(has("command"))] | length' "$hh/.claude/settings.json")"
  wrapped="$(jq '[.. | objects | select(has("command")) | .command | select(contains("${LOA_FRAMEWORK_ROOT:-$(git rev-parse --show-toplevel)}"))] | length' "$hh/.claude/settings.json")"
  [ "$total" -gt 0 ] && [ "$total" = "$wrapped" ] || { echo "$wrapped of $total hook commands redirected"; false; }
  ! jq -r '.. | objects | select(has("command")) | .command' "$hh/.claude/settings.json" | grep -vF '${LOA_FRAMEWORK_ROOT:-' | grep -q '\.claude/' || false
  # the two skills the review-catch phases run: no relative .claude/ path left in their text
  ! grep -qE '(^|[^A-Za-z0-9_./$~{}\\-])\.claude/' "$hh/.claude/skills/reviewing-code/SKILL.md" "$hh/.claude/skills/auditing-security/SKILL.md" || false
  # the dissent's catalog: a PR catalog at the workspace root never reaches the HOME cheval
  printf 'pr_catalog: true\n' > "$ws/.claude/defaults/model-config.yaml"; printf 'x: 1\n' > "$ws/.loa.config.yaml"
  local probe='import sys; sys.path.insert(0, sys.argv[1]); from loa_cheval.config import loader as l
d = l.load_system_defaults(l._find_project_root()); print("pr" if d.get("pr_catalog") else ("pinned" if d.get("providers") or d.get("models") else "empty"))'
  run bash -c 'cd "$1" && LOA_FRAMEWORK_ROOT="$2" python3 -I -c "$3" "$2/.claude/adapters"' _ "$ws" "$hh" "$probe"
  [ "$output" = pinned ] || { echo "$output"; false; }
  run bash -c 'cd "$1" && python3 -I -c "$3" "$2/.claude/adapters"' _ "$ws" "$hh" "$probe"
  [ "$output" = pr ] || { echo "$output"; false; }   # the hazard the redirection closes
}

# hs_harness — a temporary copy of the harness with the REAL mount library and took-effect; a docker wrapper that
# answers the Claude Code version label and `docker top`, and delegates `run` to the shared stub; a stub CLI
hs_harness() {
  HH="$T/h/evals/harness"
  mkdir -p "$HH/lib" "$T/log" "$T/dlog" "$T/creds/.codex"
  cp "$REPO_ROOT/evals/harness/pipeline-run.sh" "$REPO_ROOT/evals/harness/fingerprint.sh" "$REPO_ROOT/evals/harness/took-effect.sh" "$HH/"
  cp -a "$REPO_ROOT/evals/harness/lib/phase-prompts" "$HH/lib/"
  cp "$REPO_ROOT/evals/harness/lib/session-exec.sh" "$REPO_ROOT/evals/harness/lib/sandbox-mount.sh" "$HH/lib/"
  cat > "$T/claude" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == -p && ! -e "$T/log/home-at-first-phase" ]]; then
  mkdir -p "$T/log/home-at-first-phase"
  cp "\$HOME/.claude/CLAUDE.md" "\$HOME/.claude/settings.json" "$T/log/home-at-first-phase/"
  cp "\$HOME/.claude/skills/reviewing-code/SKILL.md" "$T/log/home-at-first-phase/home-skill.md"
  ls -A "\$PWD/.claude" > "$T/log/home-at-first-phase/root-claude.ls" 2>/dev/null || true
  printf '%s\n' "\${LOA_FRAMEWORK_ROOT:-unset}" > "$T/log/home-at-first-phase/fw-root"
fi
export STUB_LOG_DIR="$T/log"
exec "$TESTS_DIR/fixtures/claude-stub-pipeline.sh" "\$@"
EOF
  cat > "$T/docker" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == image && "\$*" == *org.loa.claude_code_version* ]]; then echo "\${HS_CC_VERSION:-2.1.299}"; exit 0; fi
if [[ "\${1:-}" == top ]]; then printf 'PID PPID COMMAND\n1 0 claude -p Run /review-sprint sprint-1\n9 1 cat pr/head/.claude/skills/reviewing-code/SKILL.md\n'; exit 0; fi
export DOCKER_STUB_LOG="$T/dlog" DOCKER_STUB_CLAUDE="$T/claude"
exec "$TESTS_DIR/fixtures/docker-stub.sh" "\$@"
EOF
  chmod +x "$T/claude" "$T/docker"
  cp "$TESTS_DIR/fixtures/ablation-runs/suite.yaml" "$T/suite-run.yaml"
  yq -i '.mount_mode = {"default": "home-scope"}' "$T/suite-run.yaml"
}

@test "HS-12 pipeline-run.sh home-scope (container executor, stub CLI): the session launches with --setting-sources user and LOA_FRAMEWORK_ROOT, the pinned (later) framework under HOME, the PR's data at the root without its surface; meta/mount.json, process samples and the HOME integrity record are written, the HOME is deleted; took-effect integrity_clean passes and oracle_closed runs (e)-(g); a version drift refuses" {
  local fw="$T/fw"
  make_fw "$fw"
  # the PR: the executing skill (surface) and a script (data); the pin is later than the PR head for both
  local px="$T/prh"
  mkdir -p "$px/head/.claude/skills/reviewing-code" "$px/base/.claude/skills/reviewing-code" "$px/head/.claude/scripts" "$px/base/.claude/scripts"
  printf -- '---\nname: reviewing-code\n---\nPR head skill\n' > "$px/head/.claude/skills/reviewing-code/SKILL.md"
  printf -- '---\nname: reviewing-code\n---\nPR base skill\n' > "$px/base/.claude/skills/reviewing-code/SKILL.md"
  printf 'pr head lib\n' > "$px/head/.claude/scripts/lib.sh"; printf 'pr base lib\n' > "$px/base/.claude/scripts/lib.sh"
  printf 'diff --git a/.claude/skills/reviewing-code/SKILL.md b/.claude/skills/reviewing-code/SKILL.md\ndiff --git a/.claude/scripts/lib.sh b/.claude/scripts/lib.sh\n' > "$px/head.diff"
  printf '# PR\n' > "$px/PR.md"
  printf 'name: pr-hs2\n' > "$px/fixture.yaml"
  mkdir -p "$T/st/tasks/rc-hs2"
  printf 'Review the pull request in pr/.\n' > "$T/st/tasks/rc-hs2/TASK.md"
  printf 'id: rc-hs2\nschema_version: 1\ntype: review-catch\ncriterion: "review the change"\nreview_catch: {fixture: "%s"}\n' "$px" > "$T/st/tasks/rc-hs2/task.yaml"
  hs_harness
  export LOA_EVAL_WATCHDOG_POLL_S=0.1 LOA_EVAL_CREDS_HOME="$T/creds" LOA_EVAL_BR_BIN="$T/no-br"
  export LOA_EVAL_PRICING_JSON='{"global.anthropic.claude-opus-5-5":{"input_per_mtok":4000000,"output_per_mtok":20000000},"global.anthropic.claude-fable-5-1":{"input_per_mtok":10000000,"output_per_mtok":50000000}}'
  local RUN="$T/hsrun"
  run "$HH/pipeline-run.sh" --task-yaml "$T/st/tasks/rc-hs2/task.yaml" --arm a1_full --run-dir "$RUN" --run-id r-hs --trial 1 \
    --source-tree "$fw" --suite-file "$T/suite-run.yaml" --executor container --image loa-ablation:test --docker-bin "$T/docker"
  [ "$status" -eq 0 ] || { echo "$output"; cat "$RUN/meta/mount.log" 2>/dev/null; false; }
  local f
  for f in "$RUN"/meta/phase-*.argv.json; do
    jq -e '.argv | (index("--setting-sources")) as $i | .[$i + 1] == "user"' "$f" >/dev/null || { echo "$f"; false; }
    jq -e '.env.LOA_FRAMEWORK_ROOT == "/home/evaluser"' "$f" >/dev/null || { echo "$f"; false; }
  done
  local A="$T/log/home-at-first-phase"
  [ "$(sed -n 1p "$A/CLAUDE.md")" = '@/home/evaluser/.claude/loa/CLAUDE.loa.md' ]
  grep -qF '${LOA_FRAMEWORK_ROOT:-$(git rev-parse --show-toplevel)}' "$A/settings.json"
  grep -qx 'pinned skill text LATER' "$A/home-skill.md"                     # the executing skill is the pinned one
  [ "$(cat "$A/root-claude.ls")" = scripts ]                                  # the root .claude/ holds only the PR's data
  [ "$(cat "$RUN/sandbox/.claude/scripts/lib.sh")" = "pr head lib" ]
  [ ! -e "$RUN/sandbox/.claude/skills" ] && [ ! -e "$RUN/sandbox/CLAUDE.md" ]
  cmp -s "$RUN/sandbox/pr/head/.claude/skills/reviewing-code/SKILL.md" "$px/head/.claude/skills/reviewing-code/SKILL.md"
  [ "$(jq -r '"\(.mount_mode) \(.setting_sources) \(.claude_code_version) \(.surface_derived_for) \(.framework_root_var)=\(.framework_root) \(.transform.residual)"' "$RUN/meta/mount.json")" = "home-scope user 2.1.299 2.1.299 LOA_FRAMEWORK_ROOT=/home/evaluser 0" ]
  grep -qx 'mount_mode=home-scope' "$RUN/meta/arm-evidence.txt"
  grep -q '^mount_closed=pre-launch head:1 answer paths (1 present).*home-scope: 1 surface path(s) absent at the root' "$RUN/meta/arm-evidence.txt"
  grep -qx 'mount_cheval=ok' "$RUN/meta/arm-evidence.txt"
  for f in REVIEW AUDIT; do grep -q '^# sample ' "$RUN/meta/ps-$f.txt" && grep -q '^9 1 cat pr/head/' "$RUN/meta/ps-$f.txt"; done
  [ "$(jq -r '"\(.tampered) \(.missing) \(.files > 0)"' "$RUN/meta/home-integrity.json")" = "0 0 true" ]
  [ ! -e "$RUN/meta/home" ]                                                   # the HOME (credential copies) is gone
  # took-effect on the run: integrity_clean from the HOME record; oracle_closed runs (e)-(g) — the stub CLI read nothing
  cp "$T/suite-run.yaml" "$T/suite-te.yaml"
  yq -i '(.arms[] | select(.id == "a1_full") | .took_effect) += ["oracle_closed"]' "$T/suite-te.yaml"
  run "$HH/took-effect.sh" --run-dir "$RUN" --suite-file "$T/suite-te.yaml" --task-yaml "$T/st/tasks/rc-hs2/task.yaml" --source-repo "$fw"
  grep -q '^arm a1_full: integrity_clean OK home-scope: [0-9]* HOME framework entries verified at finish' <<<"$output" || { echo "$output"; false; }
  grep -qF 'oracle_closed FAIL FAIL (f) -: pr_bytes_read is empty' <<<"$output" || { echo "$output"; false; }
  # a tampered HOME record fails integrity_clean
  jq '.tampered = 1 | .first = "tampered .claude/scripts/s.sh"' "$RUN/meta/home-integrity.json" > "$T/hi.json" && mv "$T/hi.json" "$RUN/meta/home-integrity.json"
  run "$HH/took-effect.sh" --run-dir "$RUN" --suite-file "$T/suite-te.yaml" --task-yaml "$T/st/tasks/rc-hs2/task.yaml" --source-repo "$fw"
  grep -qF 'integrity_clean FAIL home-scope: 1 tampered, 0 missing' <<<"$output" || { echo "$output"; false; }
  # an image whose Claude Code version is not the one the surface was derived for: refused before any phase
  run env HS_CC_VERSION=2.1.300 "$HH/pipeline-run.sh" --task-yaml "$T/st/tasks/rc-hs2/task.yaml" --arm a1_full --run-dir "$T/hsrun2" --run-id r-hs2 --trial 1 \
    --source-tree "$fw" --suite-file "$T/suite-run.yaml" --executor container --image loa-ablation:test --docker-bin "$T/docker"
  [ "$status" -eq 2 ]
  grep -qF "the surface is derived for Claude Code 2.1.299 but the image records '2.1.300'" <<<"$output" || { echo "$output"; false; }
  [ "$(jq '.phases | length' "$T/hsrun2/meta/pipeline.json")" = 0 ]
  # the library's two copies of the derived-for version agree
  run bash -c 'source "$1"; printf "%s\n" "$SM_SURFACE_DERIVED_FOR"' _ "$LIB"
  [ "$output" = 2.1.299 ]
  grep -qx 'SURFACE_DERIVED_FOR = "2.1.299"' "$LIB"
}
