#!/usr/bin/env bash
# scenario.sh SEEDER WORKDIR — drives every mode of seed-corpus-from-record.sh over the
# seed-record fixture (fixed commit dates, so the commit ids are reproducible) and over a
# copy of the tracked corpus, and prints one transcript: each step's exit code, stdout and
# stderr, then the sha256 of every file the steps wrote. corpus-seed-lib.bats compares the
# transcript of the current seeder with transcript.golden, which the pre-extraction seeder
# (commit de366cc63) produced: the lib/corpus-seed.sh extraction is byte-identical.
set -euo pipefail
export LC_ALL=C TZ=UTC
SEED="$1"; T="$2"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../../.." && pwd)"
FX="$ROOT/evals/tests/fixtures/seed-record"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
G="$T/repo"; C="$T/corpus"; K="$T/tasks"
mkdir -p "$G" "$C/pr-01" "$C/labels" "$K"
FAKE_KEY="AKIA$(printf 'QZ%.0s' 1 2 3 4 5 6 7 8)"
n=0
gc() { n=$((n + 1)); GIT_AUTHOR_DATE="2026-07-0${n}T12:00:00Z" GIT_COMMITTER_DATE="2026-07-0${n}T12:00:00Z" git -C "$G" -c commit.gpgsign=false "$@"; }
git -C "$G" init -q -b main
cp -R "$FX/base/." "$G/"; git -C "$G" add -A; gc commit -q -m "base"
cp -R "$FX/head/." "$G/"; git -C "$G" add -A; gc commit -q -m "feat: sprint-901 the input helper (round 1)"
cp -R "$FX/fix/." "$G/"; git -C "$G" add -A; gc commit -q -m "fix: sprint-901 review round 1"
BASE="$(git -C "$G" rev-parse HEAD~2)"; HEAD_C="$(git -C "$G" rev-parse HEAD~1)"; FIX="$(git -C "$G" rev-parse HEAD)"
git -C "$G" checkout -q --orphan record/cycle-901-a2a
git -C "$G" rm -rqf .
mkdir -p "$G/grimoires/loa/a2a/sprint-901"
sed "s/@SECRET@/$FAKE_KEY/" "$FX/engineer-feedback-r1.md.in" > "$G/grimoires/loa/a2a/sprint-901/engineer-feedback-r1.md"
git -C "$G" add -A; gc commit -q -m "record"; git -C "$G" checkout -q main
echo "# Review instructions" > "$C/pr-01/REVIEW-INSTRUCTIONS.md"
echo "# Audit instructions" > "$C/pr-01/AUDIT-INSTRUCTIONS.md"
printf 'fixture\tkind\tcommit\tfile\tdefect_id\tseverity\tcategory\tmust_match\n' > "$C/corpus.tsv"
A=(--repo "$G" --corpus "$C" --tasks-dir "$K")
SEEDA=("${A[@]}" --base "$BASE" --head "$HEAD_C" --fix "$FIX" --feedback engineer-feedback-r1.md)
step() {  # step LABEL ARGS… — one transcript block
  local label="$1"; shift
  local rc=0
  "$SEED" "$@" > "$T/out" 2> "$T/err" || rc=$?
  printf '== %s rc=%s\n-- stdout\n' "$label" "$rc"
  sed -e "s#$T#<T>#g" -e "s#$ROOT#<ROOT>#g" "$T/out"
  printf -- '-- stderr\n'
  sed -e "s#$T#<T>#g" -e "s#$ROOT#<ROOT>#g" "$T/err"
}
step dry-run 901 record/cycle-901-a2a "${SEEDA[@]}" --out "$C/pr-90" --dry-run
step seed 901 record/cycle-901-a2a "${SEEDA[@]}" --out "$C/pr-90"
step seed-again 901 record/cycle-901-a2a "${SEEDA[@]}" --out "$C/pr-90"
step paths 901 record/cycle-901-a2a "${SEEDA[@]}" --out "$C/pr-91" --paths 'scripts/a.sh'
step no-labels 901 record/cycle-901-a2a "${A[@]}" --base "$BASE" --head "$HEAD_C" --fix "$FIX" --feedback missing.md --out "$C/pr-92"
step allow-no-labels 901 record/cycle-901-a2a "${A[@]}" --base "$BASE" --head "$HEAD_C" --fix "$FIX" --feedback missing.md --out "$C/pr-93" --allow-no-labels
step build-manifest "${A[@]}" --build-manifest pr-90
step stamp-exposure "${A[@]}" --stamp-exposure pr-90
step sync-labels "${A[@]}" --sync-labels pr-90
step approve "${A[@]}" --approve pr-90 --by "tester 2026-10-24"
step freeze "${A[@]}" --freeze
step check "${A[@]}" --check
step usage-bad-fixture "${A[@]}" --build-manifest pr-9
step usage-no-sprint "${A[@]}"
step missing-commit 901 record/cycle-901-a2a "${A[@]}" --base nope --head "$HEAD_C" --fix "$FIX" --feedback engineer-feedback-r1.md --out "$C/pr-94"
# the tracked corpus (its contents change between cycles, so only identity is printed): every
# labelled fixture's manifest rebuilt from its labels must equal the tracked manifest, and the
# refrozen SHA256SUMS the tracked one
R="$T/tracked"
cp -R "$ROOT/evals/fixtures/review-prs" "$R"
for l in "$R"/labels/pr-*.tsv; do
  fx="$(basename "$l" .tsv)"
  rc=0
  "$SEED" --repo "$ROOT" --corpus "$R" --tasks-dir "$T/tracked-tasks" --build-manifest "$fx" > /dev/null 2>&1 || rc=$?
  same=no; cmp -s "$R/manifests/$fx.json" "$ROOT/evals/fixtures/review-prs/manifests/$fx.json" && same=yes
  [[ "$rc" == 0 && "$same" == yes ]] || printf '== tracked-build %s rc=%s identical=%s\n' "$fx" "$rc" "$same"
done
printf '== tracked-build done\n'
rc=0; "$SEED" --repo "$ROOT" --corpus "$R" --check > /dev/null 2>&1 || rc=$?
same=no; cmp -s "$R/SHA256SUMS" "$ROOT/evals/fixtures/review-prs/SHA256SUMS" && same=yes
printf '== tracked-check rc=%s sums-identical=%s\n' "$rc" "$same"
printf '== files\n'
(cd "$T" && find corpus tasks -type f | sort | while IFS= read -r f; do
  python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest(), sys.argv[1])' "$f"
done)
