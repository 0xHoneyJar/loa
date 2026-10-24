#!/usr/bin/env bash
# gh-stub.sh — a stand-in for `gh api` in seed-corpus-from-external.bats (no network).
# Answers from $STUB_DIR: repo.json (repos/<o>/<r>), pr.json (…/pulls/<n>), license.json
# (…/license; absent → 404), and computes …/git/trees/<tree>?recursive=1 from the local
# repository $STUB_UPSTREAM the way the GitHub API lists it (path, mode, type, sha, size).
# Every call is appended to $STUB_DIR/gh.log.
set -euo pipefail
export LC_ALL=C
printf '%s\n' "$*" >> "$STUB_DIR/gh.log"
[[ "${1:-}" == "api" ]] || { echo "gh-stub: only 'gh api' is stubbed" >&2; exit 1; }
path="${2:-}"
nf() { echo '{"message":"Not Found","status":"404"}'; echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
case "$path" in
  repos/*/*/pulls/*)  [[ -f "$STUB_DIR/pr.json" ]] && cat "$STUB_DIR/pr.json" || nf ;;
  repos/*/*/license)  [[ -f "$STUB_DIR/license.json" ]] && cat "$STUB_DIR/license.json" || nf ;;
  repos/*/*/git/trees/*)
    tree="${path#*/git/trees/}"; tree="${tree%%\?*}"
    python3 -I - "$STUB_UPSTREAM" "$tree" <<'PY'
import json, subprocess, sys
repo, tree = sys.argv[1], sys.argv[2]
out = subprocess.run(["git", "-C", repo, "ls-tree", "-r", "-t", "-l", "-z", tree], capture_output=True, check=True).stdout
ents = []
for rec in out.split(b"\0"):
    if not rec:
        continue
    meta, p = rec.split(b"\t", 1)
    mode, typ, sha, size = meta.decode().split()
    e = {"path": p.decode(), "mode": mode, "type": typ, "sha": sha}
    if typ == "blob":
        e["size"] = int(size)
    ents.append(e)
print(json.dumps({"sha": tree, "tree": ents, "truncated": False}))
PY
    ;;
  repos/*/*)          [[ -f "$STUB_DIR/repo.json" ]] && cat "$STUB_DIR/repo.json" || nf ;;
  *)                  nf ;;
esac
