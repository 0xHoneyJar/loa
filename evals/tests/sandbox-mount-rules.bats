#!/usr/bin/env bats
# =============================================================================
# evals/tests/sandbox-mount-rules.bats — the R3/R5 rewrite rules of the home-scope mount and the hook-group evidence
# (cycle-134 Sprint 276 Task 1.5, sdd.md C-4, D-2.1, D-2.1a, § 3.2, § 11.F; bd-kgfh5)
#
#   MR-01 … MR-21  one case per sdd.md § 11.F row (fixtures/sandbox-mount/pinned/.claude/rows/rNN.*, a verbatim line of
#                  the pinned framework per row, adapted only where the row file must sit under a test-fixture path):
#                  a kept row is rewritten and round-trips (verify: reverse == pinned); a dropped row stays byte-identical
#   MR-22          a planted prose mention of a path the pinned tree does not hold is not rewritten; the pinned paths
#                  and the zone beside it are
#   MR-23          verify fails on a planted .claude/ Python literal and on an edited literal inside an R5 redirection
#   MR-24          the corpus (fixtures/sandbox-mount/r3r5-corpus.tsv, one line per R3/R5 hit over the pinned framework at
#                  f17bfe0e4): the TSV lists every hit, and the transform rewrites exactly its kept rows
#   HK-1 … HK-4    `hooks` prints home_hook_counts and home_hook_groups (§ 3.2): the shared sample, a matcher with colons
#                  and pipes, merged groups, and both evidence lines from mount_home_scope
# =============================================================================

setup() {
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  LIB="$REPO_ROOT/evals/harness/lib/sandbox-mount.sh"
  FXD="$TESTS_DIR/fixtures/sandbox-mount"
  SAMPLE="$TESTS_DIR/fixtures/home_hook_groups.sample"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/mr.XXXXXX")"
  export ARM_EVIDENCE_FILE="$T/arm-evidence.txt"
  : > "$ARM_EVIDENCE_FILE"
  unset SM_TEST_MODE SM_TEST_EXCLUDED_PREFIX
}

teardown() {
  chmod -R u+rwx "$T" 2>/dev/null || true
  find "$T" -mindepth 1 -delete 2>/dev/null || true
  rmdir "$T" 2>/dev/null || true
}

lib() { run bash -c 'set -euo pipefail; source "$1"; shift; "$@"' _ "$LIB" "$@"; }
ev() { grep -E "^$1=" "$ARM_EVIDENCE_FILE" | sed "s/^$1=//"; }
HOME_C=/home/evaluser
PRE='__import__("os").path.join(__import__("os").environ.get("LOA_FRAMEWORK_ROOT", ""), '

# mounts the row fixture under $T/hh (HOME) and checks verify ran clean
mount_rows() {
  mkdir -p "$T/hh"
  lib mount_home_scope "$T/hh" "$FXD/pinned" "$HOME_C" "$T/hh.report.json"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -q '^home_verify=ok [0-9]* files, [0-9]* redirected, reverse == pinned$' "$ARM_EVIDENCE_FILE"
}
# a kept row: the HOME copy equals <expected>, differs from the pinned bytes, and reverses to them
kept() {
  mount_rows
  local rel="$1" want="$2"
  [ "$(cat "$T/hh/.claude/$rel")" = "$want" ] || { echo "got: $(cat "$T/hh/.claude/$rel")"; echo "want: $want"; return 1; }
  ! cmp -s "$T/hh/.claude/$rel" "$FXD/pinned/.claude/$rel"
}
# a dropped row: the HOME copy is byte-identical to the pinned file
dropped() {
  mount_rows
  cmp "$T/hh/.claude/$1" "$FXD/pinned/.claude/$1"
}
F3='```'

@test "MR-01 row 1 code span naming a pinned file: kept, absolute, round-trips" {
  kept rows/r01.md '1. Run `/home/evaluser/.claude/scripts/collect-trace.sh` to gather execution data'
}
@test "MR-02 row 2 fenced code naming a pinned file (a command): kept" {
  kept rows/r02.md "$F3"'bash
/home/evaluser/.claude/scripts/update.sh --check
'"$F3"
}
@test "MR-03 row 3 table cell (code span) naming a pinned directory: kept" {
  kept rows/r03.md '| New command | New file in `/home/evaluser/.claude/commands/` |'
}
@test "MR-04 row 4 bare prose / frontmatter value naming a pinned file: kept" {
  kept rows/r04.md '- EXECUTE: /home/evaluser/.claude/scripts/butterfreezone-gen.sh'
}
@test "MR-05 row 5 fenced command line: the absent temp path is rewritten with the pinned path beside it (a command is rewritten whole)" {
  kept rows/r05.md "$F3"'bash
mv /home/evaluser/.claude/loa/CLAUDE.loa.md.tmp.$$ /home/evaluser/.claude/loa/CLAUDE.loa.md
'"$F3"
}
# rows 6-10: the zone itself is pinned (under home-scope the System Zone is the HOME copy; "never edit", audit scope)
@test "MR-06 row 6 code span naming the zone (.claude/ alone): kept" {
  kept rows/r06.md '- `/home/evaluser/.claude/` directory exists (Loa is mounted)'
}
@test "MR-07 row 7 fenced zone glob (a case pattern): kept" {
  kept rows/r07.md "$F3"'bash
/home/evaluser/.claude/*) ;;
'"$F3"
}
@test "MR-08 row 8 table cell (code span) naming the zone: kept" {
  kept rows/r08.md '| "System Zone missing" | No `/home/evaluser/.claude/` | Run `/mount` first |'
}
@test "MR-09 row 9 table cell (bare) message string naming the zone: kept" {
  kept rows/r09.md '| Not a Loa project | "No /home/evaluser/.claude/ directory found. Is Loa mounted?" |'
}
@test "MR-10 row 10 bare prose / frontmatter zone glob (.claude/**): kept" {
  kept rows/r10.md '- "/home/evaluser/.claude/**"'
}
@test "MR-11 row 11 code span naming a path the pinned tree does not hold (a documentation example): dropped" { dropped rows/r11.md; }
@test "MR-12 row 12 fenced code naming an absent (project-owned) path: dropped" { dropped rows/r12.md; }
@test "MR-13 row 13 table cell placeholder whose directory the pinned tree does not hold: dropped" {
  [ -d "$FXD/pinned/.claude/overrides" ] && [ ! -e "$FXD/pinned/.claude/overrides/skills" ]
  dropped rows/r13.md
}
@test "MR-14 row 14 bare prose / frontmatter value naming an absent path: dropped" { dropped rows/r14.md; }
@test "MR-15 row 15 heading naming a pinned script: kept" {
  kept rows/r15.md '## Record Branch (`/home/evaluser/.claude/scripts/record-branch.sh`)'
}
@test "MR-16 row 16 HTML comment naming a pinned file (a provenance marker in an executing skill): kept" {
  kept rows/r16.md '<!-- DO NOT EDIT — generated from /home/evaluser/.claude/data/constraints.json -->'
}
@test "MR-17 row 17 a file under a test-fixture directory (data): dropped although the glob matches a pinned file" {
  [ -f "$FXD/pinned/.claude/settings.json" ]
  dropped rows/resources/__tests__/fixtures/r17.md
}
@test "MR-18 row 18 R5 Path() operand (cheval.py persona search list): kept; the bare .claude name is not" {
  kept adapters/rows/r18.py "for search_dir in [${PRE}\".claude/skills\"), \".claude\"]:
    pass"
}
@test "MR-19 row 19 R5 pathlib join operand (modelinv.py writer-version path): kept" {
  kept adapters/rows/r19.py "_WRITER_VERSION_PATH = ${PRE}\".claude/data/cycle-108/modelinv-writer-version\")"
}
@test "MR-20 row 20 R5 pathlib join operand (advisor_strategy.py schema path): kept" {
  kept adapters/rows/r20.py "SCHEMA_PATH_REL = ${PRE}\".claude/data/schemas/advisor-strategy.schema.json\")"
}
@test "MR-21 row 21 R5 argparse default opened as a path (economy.py model config): kept" {
  kept adapters/rows/r21.py "DEFAULT_MODEL_CONFIG_PATH = ${PRE}\".claude/defaults/model-config.yaml\")"
}

@test "MR-22 a planted prose mention of a path the pinned tree does not hold is not rewritten; the zone and the pinned script beside it are" {
  cp -a "$FXD/pinned" "$T/pin"
  printf '%s\n' 'Never edit `.claude/` directly; see `.claude/HEARTBEAT.md`.' \
    'Installed packs go to `.claude/constructs/packs/` (gitignored); run `.claude/scripts/update.sh`.' > "$T/pin/.claude/rows/planted.md"
  mkdir -p "$T/hh"
  lib mount_home_scope "$T/hh" "$T/pin" "$HOME_C" "$T/hh.report.json"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cat "$T/hh/.claude/rows/planted.md")" = 'Never edit `/home/evaluser/.claude/` directly; see `.claude/HEARTBEAT.md`.
Installed packs go to `.claude/constructs/packs/` (gitignored); run `/home/evaluser/.claude/scripts/update.sh`.' ] || { cat "$T/hh/.claude/rows/planted.md"; false; }
}

@test "MR-23 verify fails on a planted .claude/ Python literal in the HOME copy and on an edited literal inside an R5 redirection" {
  mount_rows
  lib _sm_home_py verify "$T/hh" "$FXD/pinned" "$HOME_C"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  cp "$T/hh/.claude/adapters/rows/r19.py" "$T/r19.keep"
  printf 'EXTRA = ".claude/data/planted"\n' >> "$T/hh/.claude/adapters/rows/r19.py"
  lib _sm_home_py verify "$T/hh" "$FXD/pinned" "$HOME_C"
  [ "$status" -eq 1 ]
  grep -qxF 'FAIL .claude/adapters/rows/r19.py: differs from the pinned bytes beyond the recorded redirection' <<<"$output"
  cp "$T/r19.keep" "$T/hh/.claude/adapters/rows/r19.py"
  sed -i 's#cycle-108/modelinv-writer-version#cycle-108/other#' "$T/hh/.claude/adapters/rows/r19.py"
  lib _sm_home_py verify "$T/hh" "$FXD/pinned" "$HOME_C"
  [ "$status" -eq 1 ]
  grep -qxF 'FAIL .claude/adapters/rows/r19.py: differs from the pinned bytes beyond the recorded redirection' <<<"$output"
}

@test "MR-24 the corpus (r3r5-corpus.tsv) at f17bfe0e4: every R3/R5 hit is a TSV row, and the transform rewrites exactly the kept rows" {
  git -C "$REPO_ROOT" cat-file -e 'f17bfe0e4^{commit}' 2>/dev/null || skip "the corpus commit f17bfe0e4 is not in this clone"
  mkdir -p "$T/pin" "$T/hh"
  git -C "$REPO_ROOT" archive f17bfe0e4 .claude | tar -x -C "$T/pin"
  lib mount_home_scope "$T/hh" "$T/pin" "$HOME_C" "$T/hh.report.json"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run python3 -I - "$LIB" "$T/pin" "$T/hh" "$FXD/r3r5-corpus.tsv" "$HOME_C" <<'PY'
import os, sys
lib, pin, hh, tsv, home = sys.argv[1:6]
body = open(lib, encoding="utf-8").read()
src = body.split("_sm_home_py() {\n  python3 -I - \"$@\" <<'PY'\n", 1)[1].split("\ncmd = sys.argv[1]", 1)[0]
g = {}
exec(src, g)
rows = [l.rstrip("\n").split("\t") for l in open(tsv, encoding="utf-8") if not l.startswith(("#", "row\t"))]
byfile, n_keep = {}, 0
for row, rule, path, line, col, ctx, dec, tok in rows:
    byfile.setdefault(path, []).append((rule, int(line), int(col), dec))
    n_keep += dec.startswith("rewrite")
# completeness: the TSV holds exactly the hits of the current rules over the pinned tree
hits = set()
for p in g["walk"](os.path.join(pin, ".claude")):
    data = open(p, "rb").read()
    k = g["kind"](p, data)
    if k not in ("md", "py") or b"\0" in data:
        continue
    rel = os.path.relpath(p, pin)
    rx = g["R3"] if k == "md" else g["R5"]
    for i, l in enumerate(data.decode("utf-8").split("\n"), 1):
        for m in rx.finditer(l):
            hits.add((rel, i, m.start()))
listed = set((p, i, c) for p, v in byfile.items() for _, i, c, _ in v)
if hits != listed:
    print("TSV mismatch: %d unlisted, %d stale (first unlisted %s)" % (len(hits - listed), len(listed - hits), sorted(hits - listed)[:1]))
    sys.exit(1)
bad = []
for path, v in sorted(byfile.items()):
    P = open(os.path.join(pin, path), encoding="utf-8").read()
    T = open(os.path.join(hh, path), encoding="utf-8").read()
    if path.endswith(".py"):
        if T.count(g["R5_PRE"]) != sum(1 for r in v if r[3].startswith("rewrite")):
            bad.append(path)
        continue
    # R1/R2 undone, the HOME text must be the pinned text with <home>/ inserted before each kept hit and nowhere else
    Tp = g["R1_REV"].sub(lambda m: m.group(1), g["R2_REV"].sub(lambda m: m.group(1), T))
    exp = P.split("\n")
    for i in sorted(set(r[1] for r in v)):
        l = exp[i - 1]
        for c in sorted((r[2] for r in v if r[1] == i and r[3].startswith("rewrite")), reverse=True):
            l = l[:c] + home + "/" + l[c:]
        exp[i - 1] = l
    if Tp != "\n".join(exp):
        bad.append(path)
# a markdown file without a TSV row carries no <home>/.claude/
for p in g["walk"](os.path.join(hh, ".claude")):
    rel = os.path.relpath(p, hh)
    if rel.endswith(".md") and rel not in byfile and rel != ".claude/CLAUDE.md" and (home + "/.claude/") in open(p, encoding="utf-8", errors="replace").read():
        bad.append(rel)
if bad:
    print("rewrite differs from the TSV in %d file(s): %s" % (len(bad), ", ".join(bad[:5])))
    sys.exit(1)
print("ok %d rows, %d kept, %d dropped" % (len(rows), n_keep, len(rows) - n_keep))
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "ok 1216 rows, 1173 kept, 43 dropped" ] || { echo "$output"; false; }
}

@test "HK-1 hooks prints home_hook_counts then home_hook_groups; the shared sample is what it prints for the sample settings (Bash x2 and matcher-less x1 PreToolUse, 8 SessionStart, 2 UserPromptSubmit)" {
  [ "$(printf %s Bash | sha256sum | cut -c1-12)" = d1e9567da9a8 ]
  [ "$(printf '' | sha256sum | cut -c1-12)" = e3b0c44298fc ]
  lib _sm_home_py hooks "$FXD/pinned/.claude/settings.json"
  [ "$status" -eq 0 ]
  [ "$output" = "$(sed 's/^home_hook_[a-z]*=//' "$SAMPLE")" ] || { echo "$output"; false; }
}

@test "HK-2 a matcher with colons and pipes (Write|Edit:x) hashes and round-trips through a hook_name parse (the matcher is everything after the first colon)" {
  printf '%s' '{"hooks":{"PreToolUse":[{"matcher":"Write|Edit:x","hooks":[{"type":"command","command":"a"},{"type":"command","command":"b"}]}]}}' > "$T/s.json"
  lib _sm_home_py hooks "$T/s.json"
  [ "$status" -eq 0 ]
  [ "$output" = $'PreToolUse:2\nPreToolUse:2b07a9f0e8be:2' ] || { echo "$output"; false; }
  local name='PreToolUse:Write|Edit:x' hex
  hex="$(printf %s "${name#*:}" | sha256sum | cut -c1-12)"
  [ "$(sed -n 2p <<<"$output")" = "${name%%:*}:$hex:2" ]
}

@test "HK-3 groups with the same (event, matcher) merge, counts summed; an empty and a missing matcher are the same group; no hooks prints two empty lines" {
  printf '%s' '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"command":"a"}]},{"matcher":"","hooks":[{"command":"b"}]},{"matcher":"Bash","hooks":[{"command":"c"},{"command":"d"}]},{"hooks":[{"command":"e"}]}],"Stop":[]}}' > "$T/s.json"
  lib _sm_home_py hooks "$T/s.json"
  [ "$status" -eq 0 ]
  [ "$output" = $'PreToolUse:5,Stop:0\nPreToolUse:d1e9567da9a8:3;PreToolUse:e3b0c44298fc:2' ] || { echo "$output"; false; }
  printf '{}' > "$T/e.json"
  lib _sm_home_py hooks "$T/e.json"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "HK-4 mount_home_scope writes home_hook_counts and home_hook_groups into the arm evidence, equal to the shared sample" {
  mount_rows
  [ "$(grep -E '^home_hook_(counts|groups)=' "$ARM_EVIDENCE_FILE")" = "$(cat "$SAMPLE")" ] || { cat "$ARM_EVIDENCE_FILE"; false; }
  [ "$(grep -c '^home_hook_' "$ARM_EVIDENCE_FILE")" = 2 ]
}
