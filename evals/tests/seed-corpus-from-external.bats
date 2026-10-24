#!/usr/bin/env bats
# =============================================================================
# evals/tests/seed-corpus-from-external.bats — cycle-133 Sprint 3 Task 3.3
# (PRD FR-12, SDD C-12, §5.4): evals/harness/seed-corpus-from-external.sh.
#
# Hermetic: an upstream repository built here (base → PR branch with
# refs/pull/7/head → merge → fix on main) is cloned through the bats-only seam
# (LOA_SEED_EXTERNAL_TEST_MODE=1 + LOA_SEED_EXTERNAL_CLONE_FROM); `gh api` is
# fixtures/seed-external/gh-stub.sh on PATH. No network, no model call.
# Planted secrets are assembled at run time (no credential-shaped literal here).
# =============================================================================

setup() {
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  SEED="$REPO_ROOT/evals/harness/seed-corpus-from-external.sh"
  RECORD_SEED="$REPO_ROOT/evals/harness/seed-corpus-from-record.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/sx.XXXXXX")"
  export TMPDIR="$T"
  U="$T/upstream"; C="$T/corpus"; K="$T/tasks"
  export STUB_DIR="$T/stub" STUB_UPSTREAM="$U"
  mkdir -p "$STUB_DIR/bin" "$C/pr-01" "$K"
  cp "$TESTS_DIR/fixtures/seed-external/gh-stub.sh" "$STUB_DIR/bin/gh"
  export PATH="$STUB_DIR/bin:$PATH"
  export LOA_SEED_EXTERNAL_TEST_MODE=1 LOA_SEED_EXTERNAL_CLONE_FROM="$U"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  echo "# Review instructions" > "$C/pr-01/REVIEW-INSTRUCTIONS.md"
  echo "# Audit instructions" > "$C/pr-01/AUDIT-INSTRUCTIONS.md"
  printf 'fixture\tkind\tcommit\tfile\tdefect_id\tseverity\tcategory\tmust_match\n' > "$C/corpus.tsv"
  "$RECORD_SEED" --corpus "$C" --freeze >/dev/null
  BEFORE="$(cd "$C" && find . -type f | sort | xargs cat | python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')"
  FIX_LINE='    if value is None or value == "":  # the empty string is not a value'
}

teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

ug() { git -C "$U" -c commit.gpgsign=false "$@"; }

# build_upstream [extra-setup-function] — base, the PR (refs/pull/7/head), its merge, the fix
build_upstream() {
  git init -q -b main "$U"
  git -C "$U" config uploadpack.allowFilter true
  git -C "$U" config uploadpack.allowAnySHA1InWant true
  mkdir -p "$U/src"
  printf 'MIT License\n\nCopyright (c) 2026 Upstream\n' > "$U/LICENSE"
  printf 'def check(value):\n    """accept a value"""\n    if value is None:\n        return False\n    return True\n' > "$U/src/app.py"
  printf 'unrelated\n' > "$U/README.md"
  ug add -A; ug commit -q -m base
  BASE_SHA="$(ug rev-parse HEAD)"
  ug checkout -q -b feature
  printf 'def check(value):\n    """accept a value (now also strings)"""\n    if value is None:\n        return False\n    return bool(str(value)) or True\n' > "$U/src/app.py"
  printf 'def helper():\n    return 42\n' > "$U/src/util.py"
  if [[ -n "${1:-}" ]]; then "$1"; fi
  ug add -A; ug commit -q -m "feat: strings accepted"
  HEAD_SHA="$(ug rev-parse HEAD)"
  ug update-ref refs/pull/7/head "$HEAD_SHA"
  ug checkout -q main
  ug merge -q --no-ff -m "Merge pull request #7" feature
  MERGE_SHA="$(ug rev-parse HEAD)"
  printf 'later\n' >> "$U/README.md"; ug add -A; ug commit -q -m "docs: unrelated"
  python3 - "$U/src/app.py" "$FIX_LINE" <<'PY'
import sys
p, fix = sys.argv[1], sys.argv[2]
s = open(p).read().replace("    if value is None:\n", fix + "\n")
open(p, "w").write(s)
PY
  ug add -A; ug commit -q -m "fix: the empty string is not a value"
  FIX_SHA="$(ug rev-parse HEAD)"
  stub_meta
}

# stub_meta [title] [body] [spdx|-] — the API answers for repo, PR and licence
stub_meta() {
  local title="${1:-Accept strings in check()}" body="${2:-This lets check() take string input.}" spdx="${3:-MIT}"
  jq -n --arg spdx "$spdx" '{language: "Python", private: false, license: {spdx_id: $spdx}}' > "$STUB_DIR/repo.json"
  jq -n --arg t "$title" --arg b "$body" --arg base "$BASE_SHA" --arg head "$HEAD_SHA" --arg m "$MERGE_SHA" \
    '{number: 7, title: $t, body: $b, created_at: "2026-07-20T10:00:00Z", merged_at: "2026-07-21T10:00:00Z",
      merge_commit_sha: $m, base: {sha: $base, repo: {full_name: "upstream/proj"}}, head: {sha: $head}}' > "$STUB_DIR/pr.json"
  if [[ "$spdx" == "-" ]]; then rm -f "$STUB_DIR/license.json"; else
    jq -n --arg spdx "$spdx" '{license: {spdx_id: $spdx}}' > "$STUB_DIR/license.json"; fi
}

URL=https://github.com/upstream/proj
seed() { "$SEED" "$URL" 7 --fix "$FIX_SHA" --corpus "$C" --tasks-dir "$K" "$@"; }
corpus_unchanged() {
  local now
  now="$(cd "$C" && find . -type f | sort | xargs cat | python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')"
  [ "$now" = "$BEFORE" ]
}
dry_corpus() { printf '%s\n' "$1" | sed -n 's/^dry run: temporary corpus \([^,]*\),.*/\1/p'; }

@test "SX-1 --dry-run builds a temporary fixture tree that passes --check; the corpus is untouched" {
  build_upstream
  run seed --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  D="$(dry_corpus "$output")"
  [ -d "$D/pr-99" ]
  corpus_unchanged
  [ -f "$D/pr-99/head/src/app.py" ] && [ -f "$D/pr-99/head/src/util.py" ] && [ -f "$D/pr-99/base/src/app.py" ]
  [ ! -e "$D/pr-99/base/src/util.py" ]
  [ ! -e "$D/pr-99/head/README.md" ]                       # only the PR's files
  grep -q 'return bool(str(value)) or True' "$D/pr-99/head/src/app.py"   # the pre-fix head
  [ "$(head -1 "$D/pr-99/PR.md")" = "# Accept strings in check()" ]
  grep -q '^kind: external$' "$D/pr-99/fixture.yaml"
  grep -q "^head_commit: \"$HEAD_SHA\"$" "$D/pr-99/fixture.yaml"
  grep -q "^base_commit: \"$BASE_SHA\"$" "$D/pr-99/fixture.yaml"
  grep -q "^fix_parent: \"$(git -C "$U" rev-parse "$FIX_SHA^")\"$" "$D/pr-99/fixture.yaml"
  grep -q '^source_url: "https://github.com/upstream/proj"$' "$D/pr-99/fixture.yaml"
  grep -q '^licence: "MIT"$' "$D/pr-99/fixture.yaml"
  grep -q '^exposure:$' "$D/pr-99/fixture.yaml"
  [ -f "$D/pr-99/upstream/LICENSE" ]
  grep -q $'^F001\t-\tfix\tsrc/app.py\t' "$D/labels/pr-99.tsv"
  [ -f "$(dirname "$D")/DRY-RUN-REPORT.txt" ]
  run "$SEED" --check "$D"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"external OK: 1 external fixture(s)"* ]]
  run "$RECORD_SEED" --corpus "$D" --check
  [ "$status" -eq 0 ]
  ! grep -q 'claude\|codex' "$STUB_DIR/gh.log"          # only gh api reads; nothing else was called
}

@test "SX-2 --check finds a tampered temporary tree (a changed head file, an added symlink)" {
  build_upstream
  run seed --dry-run
  [ "$status" -eq 0 ]
  D="$(dry_corpus "$output")"
  printf 'x\n' >> "$D/pr-99/head/src/util.py"
  run "$SEED" --check "$D"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SHA256SUMS mismatch"* ]]
  git -C "$U" show "$HEAD_SHA:src/util.py" > "$D/pr-99/head/src/util.py"
  ln -s ../../../../etc/passwd "$D/pr-99/head/link"
  run "$SEED" --check "$D"
  [ "$status" -eq 1 ]
}

@test "SX-3 --commit-trees writes the fixture with the upstream licence, the attribution row and provenance; both checks pass" {
  build_upstream
  run seed --commit-trees --out "$C/pr-40"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f "$C/pr-40/head/src/app.py" ] && [ -f "$C/pr-40/head.diff" ] && [ -f "$C/pr-40/upstream/LICENSE" ]
  grep -q '^trees: committed$' "$C/pr-40/fixture.yaml"
  grep -q $'^pr-40\thttps://github.com/upstream/proj\t7\t'"$HEAD_SHA"$'\tMIT\tupstream/LICENSE$' "$C/THIRD-PARTY.tsv"
  grep -q $'^pr-40\texternal\t'"${HEAD_SHA:0:8}" "$C/corpus.tsv"
  jq -e '.trees == "committed" and (.files.head | length) == 2 and .licence == "MIT"' "$C/external/pr-40.json" >/dev/null
  jq -e '.defects == [] and (.fix_regions | length) >= 1' "$C/manifests/pr-40.json" >/dev/null
  [ -f "$K/review-recall/review-pr-40.yaml" ]
  run "$SEED" --check --corpus "$C"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run "$RECORD_SEED" --corpus "$C" --check
  [ "$status" -eq 0 ]
}

@test "SX-4 without --commit-trees only a fetch manifest with hashes is written (no third-party bytes)" {
  build_upstream
  run seed --out "$C/pr-41"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -e "$C/pr-41/head" ] && [ ! -e "$C/pr-41/base" ] && [ ! -e "$C/pr-41/head.diff" ] && [ ! -e "$C/pr-41/upstream" ]
  grep -q '^trees: fetch-at-run-time$' "$C/pr-41/fixture.yaml"
  jq -e '.trees == "fetch-at-run-time" and (.files.head[0].sha256 | length) == 64' "$C/external/pr-41.json" >/dev/null
  grep -q $'^pr-41\texternal-fetch\t' "$C/corpus.tsv"
  [ ! -e "$C/labels/pr-41.tsv" ]
  run "$SEED" --check --corpus "$C"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

plant_symlink() { ln -s ../README.md "$U/src/link.md"; }
@test "SX-5 a symlink in the PR is refused before extraction (exit 2, corpus untouched)" {
  build_upstream plant_symlink
  run seed --commit-trees --out "$C/pr-42"
  [ "$status" -eq 2 ]
  [[ "$output" == *"src/link.md is a symlink"* ]]
  [[ "$output" != *"fetching blobs"* ]]
  corpus_unchanged
}

plant_submodule() {   # an embedded repository: `git add -A` records it as a gitlink (mode 160000)
  git init -q "$U/vendor/lib"; printf 'x\n' > "$U/vendor/lib/x"
  git -C "$U/vendor/lib" add -A; git -C "$U/vendor/lib" -c commit.gpgsign=false commit -q -m sub
}
@test "SX-6 a submodule in the PR is refused before extraction (exit 2, corpus untouched)" {
  build_upstream plant_submodule
  run seed --commit-trees --out "$C/pr-42"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"vendor/lib is a submodule"* ]]
  corpus_unchanged
}

@test "SX-7 an oversize tree is refused from tree metadata before any blob is fetched (files and bytes)" {
  build_upstream
  run seed --dry-run --max-files 2
  [ "$status" -eq 2 ]
  [[ "$output" == *"exceed --max-files 2 (checked from tree metadata; nothing fetched)"* ]]
  [[ "$output" != *"fetching blobs"* ]]
  run seed --dry-run --max-bytes 100
  [ "$status" -eq 2 ]
  [[ "$output" == *"exceed --max-bytes 100"* ]]
  grep -q 'git/trees/' "$STUB_DIR/gh.log"
}

@test "SX-8 licences: outside the allowlist, missing, contradicted by --licence, or a conflicting declaration — each refused (exit 2)" {
  build_upstream
  stub_meta "" "" GPL-3.0
  run seed --commit-trees --out "$C/pr-43"
  [ "$status" -eq 2 ]
  [[ "$output" == *"licence GPL-3.0 is outside the allowlist"* ]]
  stub_meta "" "" -
  run seed --commit-trees --out "$C/pr-43"
  [ "$status" -eq 2 ]
  [[ "$output" == *"identifies no licence"* ]]
  stub_meta
  run seed --commit-trees --out "$C/pr-43" --licence Apache-2.0
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot override"* ]]
  corpus_unchanged
}

plant_pkg() { printf '{"name": "proj", "license": "GPL-2.0-only"}\n' > "$U/package.json"; }
@test "SX-9 a root package.json declaring another licence than the API is a conflict and refuses" {
  build_upstream plant_pkg
  run seed --commit-trees --out "$C/pr-43"
  [ "$status" -eq 2 ]
  [[ "$output" == *"package.json declares licence 'GPL-2.0-only'"* ]]
  corpus_unchanged
}

@test "SX-10 leakage: a PR body carrying a fix-diff line refuses and names the line; short or syntax-only overlap does not" {
  build_upstream
  stub_meta "Accept strings" "Also: $FIX_LINE"
  run seed --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"leakage: src/app.py: +if value is None or value == \"\": # the empty string is not a value"* ]]
  [[ "$output" == *"PR.md carries 1 line(s) of the fix diff"* ]]
  stub_meta "Accept strings" "return True } ) value"     # under 20 characters per fix line / stop-list
  run seed --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "SX-11 URLs: only https://github.com/<owner>/<repo>; credentials are stripped and never printed" {
  build_upstream
  for u in http://github.com/upstream/proj file:///tmp/x https://gitlab.com/upstream/proj "https://github.com/upstream/proj?x=1" https://github.com/upstream; do
    run "$SEED" "$u" 7 --fix "$FIX_SHA" --corpus "$C" --dry-run
    [ "$status" -eq 2 ] || { echo "$u: $output"; false; }
  done
  tok="tok$(printf 'en%.0s' 1 2 3)"
  run "$SEED" "https://someone:$tok@github.com/upstream/proj.git" 7 --fix "$FIX_SHA" --corpus "$C" --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"source https://github.com/upstream/proj (credentials stripped from the given URL)"* ]]
  [[ "$output" != *"$tok"* ]]
  ! grep -rq "$tok" "$(dry_corpus "$output")"
}

@test "SX-12 binding: the API head differs from refs/pull/7/head, the PR belongs to another repo, the fix precedes the head — each refused" {
  build_upstream
  jq --arg h "$BASE_SHA" '.head.sha = $h' "$STUB_DIR/pr.json" > "$T/p" && mv "$T/p" "$STUB_DIR/pr.json"
  run seed --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"the PR moved"* ]]
  stub_meta
  jq '.base.repo.full_name = "someone/else"' "$STUB_DIR/pr.json" > "$T/p" && mv "$T/p" "$STUB_DIR/pr.json"
  run seed --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"belongs to someone/else"* ]]
  stub_meta
  ug checkout -q -b side "$BASE_SHA"; printf 'side\n' > "$U/side.txt"; ug add -A; ug commit -q -m side
  side="$(ug rev-parse HEAD)"; ug checkout -q main
  run "$SEED" "$URL" 7 --fix "$side" --corpus "$C" --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"the fix does not follow the PR"* ]]
}

plant_secret() { printf 'TOKEN = "%s%s"\n' 'gh' "p_$(printf 'Ab1Cd2Ef3Gh4%.0s' 1 2 3)" > "$U/src/conf.py"; }
@test "SX-13 the C-4 scanner over the materialised trees refuses a credential and never prints it" {
  build_upstream plant_secret
  run seed --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"secret scan hit: head/src/conf.py:1:github-token"* ]]
  [[ "$output" != *"Ab1Cd2Ef3Gh4"* ]]
}

plant_subst() { printf 'src/util.py export-subst\n' > "$U/.gitattributes"; printf 'def helper():\n    return "$Format:%%H$"\n' > "$U/src/util.py"; }
@test "SX-14 an export-subst attribute cannot alter a materialised file: head/ holds the blob's bytes" {
  build_upstream plant_subst
  run seed --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  D="$(dry_corpus "$output")"
  cmp "$D/pr-99/head/src/util.py" <(git -C "$U" show "$HEAD_SHA:src/util.py")
  grep -qF '$Format:%H$' "$D/pr-99/head/src/util.py"
}

@test "SX-15 usage: no arguments, a bad --fix, a bad pr, --out outside the corpus and --check with seed arguments exit 2" {
  build_upstream
  run "$SEED"
  [ "$status" -eq 2 ]
  run "$SEED" "$URL" 7 --fix nothex --corpus "$C" --dry-run
  [ "$status" -eq 2 ]
  run "$SEED" "$URL" seven --fix "$FIX_SHA" --corpus "$C" --dry-run
  [ "$status" -eq 2 ]
  run "$SEED" "$URL" 7 --fix "$FIX_SHA" --corpus "$C" --out "$T/elsewhere/pr-40"
  [ "$status" -eq 2 ]
  run "$SEED" "$URL" 7 --check
  [ "$status" -eq 2 ]
  corpus_unchanged
}

@test "SX-16 the test seam needs the test-mode flag: without it the sanitised URL itself is cloned (here through a dead proxy, so it fails)" {
  build_upstream
  LOA_SEED_EXTERNAL_TEST_MODE=0 https_proxy=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9 run "$SEED" "$URL" 7 --fix "$FIX_SHA" --corpus "$C" --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"git clone https://github.com/upstream/proj failed"* ]]
  [[ "$output" != *"limits ok"* ]]
}

@test "SX-17 a fix hunk is carried to head/ line numbers across commits that moved the file between the PR and fix^" {
  build_upstream
  # rebuild the fix on top of a commit that prepends two lines to src/app.py
  ug reset -q --hard "$FIX_SHA^"
  { printf '# header 1\n# header 2\n'; cat "$U/src/app.py"; } > "$T/a" && mv "$T/a" "$U/src/app.py"
  ug commit -qam "docs: header"
  python3 - "$U/src/app.py" "$FIX_LINE" <<'PY'
import sys
p, fix = sys.argv[1], sys.argv[2]
s = open(p).read().replace("    if value is None:\n", fix + "\n")
open(p, "w").write(s)
PY
  ug commit -qam "fix: the empty string is not a value"
  FIX_SHA="$(ug rev-parse HEAD)"
  run seed --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  D="$(dry_corpus "$output")"
  grep -q $'^F001\t-\tfix\tsrc/app.py\t.*\tfix/'"${FIX_SHA:0:12}"':3-3$' "$D/labels/pr-99.tsv"
  [ "$(sed -n 3p "$D/pr-99/head/src/app.py")" = "    if value is None:" ]
}

@test "SX-18 a fix that touches no file the PR changed is refused (the PR is not the defect's origin)" {
  build_upstream
  printf 'more\n' >> "$U/README.md"; ug commit -qam "docs: more"
  run "$SEED" "$URL" 7 --fix "$(ug rev-parse HEAD)" --corpus "$C" --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"touches no file the PR changed"* ]]
}

plant_pyproject() { printf '[project]\nname = "proj"\nlicense = "MIT License"\n' > "$U/pyproject.toml"; }
@test "SX-19 a declaration naming the same licence family in prose (\"MIT License\") is not a conflict" {
  build_upstream plant_pyproject
  run seed --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "SX-20 a dry run refused after its temporary corpus was made (a secret) leaves no temporary tree behind" {
  build_upstream plant_secret
  run seed --dry-run
  [ "$status" -eq 2 ]
  [ -z "$(find "$T" -maxdepth 1 -name 'seed-external-dry-run.*')" ]
  [ -z "$(find "$T" -maxdepth 1 -name 'seed-external.*')" ]
}
