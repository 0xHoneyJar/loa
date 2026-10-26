#!/usr/bin/env bats
# =============================================================================
# evals/tests/seed-ts.bats — the TypeScript path of seed-bugfix-tasks.sh and
# seed-refactor-tasks.sh (lib/seed_tasks.py: runner `ts`, --node-modules)
#
# Over a throwaway workspace repository (a root package.json naming its
# `workspaces`, a package under tools/ whose test script is node --test, the
# workspace package it imports, a second package whose test script is vitest):
# a fix commit changing a *.test.ts becomes a task whose command is the
# package's own node --test flags plus the TAP reporter and the test
# directory's glob, whose fixture carries the package.json / tsconfig chain and
# the imported workspace package, whose proof ran against the installed
# checkout's node_modules through the proof tree's symlink farm (nothing
# written into the checkout), and that validates (ST-1); without
# --node-modules the candidate is skipped by name and a wrong --node-modules
# is exit 2 (ST-2); --dry-run lists it and a mixed candidate names its runners
# (ST-3); the vitest shape runs the package's own vitest through npx --prefix
# — a stub vitest here, since the real one is not on the host — and its cache
# lands in the proof tree, not in the checkout (ST-4); roots scope names the
# changed file and the brief names only the directory (ST-5); a test script
# that is neither is skipped with the reason (ST-6); a hidden test that cannot
# load fails its proof with the first error named (ST-7); the refactor seeder
# follows the same path (ST-8).
# Needs node >= 22.6 (--experimental-strip-types) and npx on PATH; skipped otherwise.
# =============================================================================

setup() {
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  SEED="$REPO_ROOT/evals/harness/seed-bugfix-tasks.sh"
  SEEDR="$REPO_ROOT/evals/harness/seed-refactor-tasks.sh"
  VS="$REPO_ROOT/evals/harness/validate-suite.sh"
  SV="$(yq -r .suite_version "$REPO_ROOT/evals/suites/ablation-2.0.yaml")"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/st.XXXXXX")"
  G="$T/repo"; S="$T/suite"; I="$T/installed"; NM="$I/node_modules"
  export LOA_EVAL_PHASE_PROMPTS_DIR="$T/no-prompts"
  node --experimental-strip-types -e 0 >/dev/null 2>&1 || skip "node >= 22.6 (--experimental-strip-types) not on PATH"
  command -v npx >/dev/null 2>&1 || skip "npx not on PATH"
  git init -q -b main "$G"
  mkdir -p "$G/tools/calc/src" "$G/tools/calc/tests" "$G/tools/shared/src" "$G/tools/vcalc/src" "$G/tools/vcalc/tests"
  # the workspace root: package.json names the members, tsconfig.base.json is what each member's tsconfig extends
  cat > "$G/package.json" <<'J'
{"name": "ws", "private": true, "workspaces": ["tools/*"], "scripts": {"test": "npm test --workspaces"}}
J
  cat > "$G/tsconfig.base.json" <<'J'
{"compilerOptions": {"target": "ES2022", "module": "NodeNext", "moduleResolution": "NodeNext", "strict": true, "allowImportingTsExtensions": true, "noEmit": true}}
J
  # a workspace package the module under test imports (@ws/shared), reached through node_modules at run time
  cat > "$G/tools/shared/package.json" <<'J'
{"name": "@ws/shared", "type": "module", "exports": {".": "./src/index.ts"}}
J
  cat > "$G/tools/shared/src/index.ts" <<'TS'
export function sign(x: number): number {
  return x < 0 ? -1 : 1;
}
TS
  # the package under test: its test script is node --test with its own flags
  cat > "$G/tools/calc/package.json" <<'J'
{"name": "@ws/calc", "type": "module", "scripts": {"test": "node --test --experimental-strip-types --test-timeout=5000 'tests/*.test.ts'"}, "dependencies": {"@ws/shared": "workspace:*"}}
J
  cat > "$G/tools/calc/tsconfig.json" <<'J'
{"extends": "../../tsconfig.base.json", "include": ["src/**/*", "tests/**/*"]}
J
  cat > "$G/tools/calc/src/round.ts" <<'TS'
import { sign } from '@ws/shared';

/** Round to the nearest integer, halves away from zero. */
export function roundHalf(x: number): number {
  return sign(x) * Math.trunc(x + 0.5);
}
TS
  cat > "$G/tools/calc/tests/round.test.ts" <<'TS'
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { roundHalf } from '../src/round.ts';

test('positive half rounds up', () => {
  assert.equal(roundHalf(2.5), 3);
});
TS
  # a second package whose test script is vitest
  cat > "$G/tools/vcalc/package.json" <<'J'
{"name": "@ws/vcalc", "type": "module", "scripts": {"test": "vitest run"}, "devDependencies": {"vitest": "^3.2.0"}}
J
  cat > "$G/tools/vcalc/src/clamp.ts" <<'TS'
export function clamp(x: number, lo: number, hi: number): number {
  return Math.min(hi, x);
}
TS
  cat > "$G/tools/vcalc/tests/clamp.test.ts" <<'TS'
import { test, expect } from 'vitest';
import { clamp } from '../src/clamp.ts';

test('clamps above', () => {
  expect(clamp(7, 0, 5)).toBe(5);
});
TS
  echo "notes" > "$G/README.md"
  gc add -A; gc commit -q -m "chore: initial"
  install_checkout
}

teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

gc() { git -C "$G" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }

# The "installed checkout": the repository's files at HEAD plus the node_modules an install leaves behind, in the shape
# pnpm and npm produce — the root's (empty here), tools/calc's with the workspace link to @ws/shared, tools/vcalc's with
# a stub vitest (package + .bin shim) that runs *.test.ts files under --root, prints TAP flat and writes a cache under
# <root>/node_modules/.vite as the real one does.
install_checkout() {
  rm -rf "$I"
  mkdir -p "$I" "$NM" "$I/tools/calc/node_modules/@ws" "$I/tools/vcalc/node_modules/.bin" "$I/tools/vcalc/node_modules/vitest"
  git -C "$G" archive HEAD | tar -x -C "$I"
  ln -s ../../../shared "$I/tools/calc/node_modules/@ws/shared"
  cat > "$I/tools/vcalc/node_modules/vitest/package.json" <<'J'
{"name": "vitest", "version": "0.0.0-stub", "type": "module", "bin": {"vitest": "./cli.mjs"}, "exports": {".": "./index.js"}}
J
  cat > "$I/tools/vcalc/node_modules/vitest/index.js" <<'JS'
export const tests = [];
export function test(name, fn) { tests.push({ name, fn }); }
export const it = test;
export function expect(actual) {
  return {
    toBe(expected) { if (actual !== expected) throw new Error(`expected ${actual} to be ${expected}`); },
  };
}
JS
  cat > "$I/tools/vcalc/node_modules/vitest/cli.mjs" <<'JS'
// stub of the vitest CLI: `vitest run --reporter=tap-flat [--root R] [filter…]`; TAP flat; exit 1 on any failure
import { readdirSync, statSync, mkdirSync, writeFileSync } from 'node:fs';
import { join, resolve, relative } from 'node:path';
import { pathToFileURL } from 'node:url';
const args = process.argv.slice(2);
let root = process.cwd();
const filters = [];
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === 'run' || a.startsWith('--reporter')) continue;
  if (a === '--root' || a === '-r') { root = resolve(args[++i]); continue; }
  filters.push(a);
}
function walk(d, out) {
  for (const e of readdirSync(d)) {
    if (e === 'node_modules') continue;
    const p = join(d, e);
    if (statSync(p).isDirectory()) walk(p, out); else if (/\.(test|spec)\.ts$/.test(e)) out.push(p);
  }
  return out;
}
const files = walk(root, []).filter(f => !filters.length || filters.some(x => f.includes(x))).sort();
mkdirSync(join(root, 'node_modules', '.vite'), { recursive: true });
writeFileSync(join(root, 'node_modules', '.vite', 'stub-cache.json'), '{}\n');
const api = await import('./index.js');
const results = [];
for (const f of files) {
  api.tests.length = 0;
  try { await import(pathToFileURL(f).href); } catch (e) { results.push({ name: relative(root, f), ok: false, err: e }); continue; }
  for (const t of api.tests) {
    try { await t.fn(); results.push({ name: `${relative(root, f)} > ${t.name}`, ok: true }); }
    catch (e) { results.push({ name: `${relative(root, f)} > ${t.name}`, ok: false, err: e }); }
  }
}
console.log('TAP version 13');
console.log(`1..${results.length}`);
results.forEach((r, i) => {
  console.log(`${r.ok ? 'ok' : 'not ok'} ${i + 1} - ${r.name}`);
  if (!r.ok) console.log(`    ---\n    error: ${JSON.stringify(String((r.err && r.err.message) || r.err))}\n    ...`);
});
process.exit(results.length && results.every(r => r.ok) ? 0 : 1);
JS
  cat > "$I/tools/vcalc/node_modules/.bin/vitest" <<'SH'
#!/bin/sh
basedir=$(dirname "$(echo "$0" | sed -e 's,\\,/,g')")
exec node --experimental-strip-types "$basedir/../vitest/cli.mjs" "$@"
SH
  chmod +x "$I/tools/vcalc/node_modules/.bin/vitest"
}

# the clean fix: negative halves round away from zero; two new cases
commit_clean_fix() {
  cat > "$G/tools/calc/src/round.ts" <<'TS'
import { sign } from '@ws/shared';

/** Round to the nearest integer, halves away from zero. */
export function roundHalf(x: number): number {
  return sign(x) * Math.trunc(Math.abs(x) + 0.5);
}
TS
  cat >> "$G/tools/calc/tests/round.test.ts" <<'TS'

test('negative half rounds away from zero', () => {
  assert.equal(roundHalf(-2.5), -3);
});

test('negative rounds to nearest', () => {
  assert.equal(roundHalf(-1.6), -2);
});
TS
  gc add -A; gc commit -q -m "fix(calc): negative halves round away from zero"
  install_checkout
}

commit_vitest_fix() {
  cat > "$G/tools/vcalc/src/clamp.ts" <<'TS'
export function clamp(x: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, x));
}
TS
  cat >> "$G/tools/vcalc/tests/clamp.test.ts" <<'TS'

test('clamps below', () => {
  expect(clamp(-3, 0, 5)).toBe(0);
});
TS
  gc add -A; gc commit -q -m "fix(vcalc): clamp the lower bound too"
  install_checkout
}

@test "ST-1 a node --test fix becomes a task: the package's command with the TAP reporter and the directory glob, the infra chain and the imported workspace package in the fixture, red/green proof through the farm, validate-suite passes, the checkout untouched" {
  commit_clean_fix
  FIX="$(git -C "$G" rev-parse HEAD)"; BASE="$(git -C "$G" rev-parse HEAD~1)"
  before="$(cd "$I" && find . | sort)"
  run "$SEED" --since 2000-01-01 --select 4 --out "$S" --repo "$G" --suite-version "$SV" --node-modules "$NM"
  [ "$status" -eq 0 ]
  grep -q "^candidate ${FIX:0:12} " <<<"$output"
  grep -qx "proof bugfix-01 ${FIX:0:12}: red 2 failed / green 3 passed" <<<"$output"
  grep -q 'selected 1, written 1, proof failed 0' <<<"$output"
  D="$S/tasks/bugfix-01"
  # fixture: the module, the base test, the package.json / tsconfig chain to the root, the imported workspace package;
  # the vitest package is not imported and stays out; no node_modules, no .git
  [ "$(cd "$D/fixture" && find . -type f | sort | tr '\n' ' ')" = "./package.json ./tools/calc/package.json ./tools/calc/src/round.ts ./tools/calc/tests/round.test.ts ./tools/calc/tsconfig.json ./tools/shared/package.json ./tools/shared/src/index.ts ./tsconfig.base.json " ]
  grep -q 'Math.trunc(x + 0.5)' "$D/fixture/tools/calc/src/round.ts"
  [ "$(grep -c '^test(' "$D/fixture/tools/calc/tests/round.test.ts")" = "1" ]
  [ -z "$(find "$D" -name node_modules)" ]
  # hidden: the commit's test, the manifest, the source-only patch
  [ "$(grep -c '^test(' "$D/hidden/tests/tools/calc/tests/round.test.ts")" = "3" ]
  [ "$(jq -c . "$D/hidden/manifest.json")" = '{"files":[{"src":"tests/tools/calc/tests/round.test.ts","dest":"tools/calc/tests/round.test.ts"}]}' ]
  grep -q '^--- a/tools/calc/src/round.ts' "$D/hidden/reference.patch"
  ! grep -q 'round.test' "$D/hidden/reference.patch" || false
  # the command: the script's own flags, --test-reporter=tap, the test directory's glob (node expands it: no shell)
  [ "$(yq -o=json -I=0 .test_command "$D/task.yaml")" = '["node","--test","--experimental-strip-types","--test-timeout=5000","--test-reporter=tap","tools/calc/tests/*.test.ts"]' ]
  [ "$(yq -o=json -I=0 .grader_protected "$D/task.yaml")" = '["package.json","tools/calc/package.json","tools/calc/tsconfig.json","tsconfig.base.json"]' ]
  [ "$(yq -r .type "$D/task.yaml")" = "bug-fix" ]
  [ "$(yq -r .source.fix_commit "$D/task.yaml")" = "$FIX" ]
  [ "$(yq -r .source.base_commit "$D/task.yaml")" = "$BASE" ]
  grep -q 'passes 3 of 3' "$D/task.yaml"
  # the brief: the subject, the failure count, the command; no test name, no diff word
  grep -q '^# Task: negative halves round away from zero$' "$D/TASK.md"
  grep -q '2 of 3 checks' "$D/TASK.md"
  grep -qF 'Run the tests with `node --test --experimental-strip-types --test-timeout=5000 --test-reporter=tap tools/calc/tests/*.test.ts`' "$D/TASK.md"
  ! grep -qE 'round\.test|hidden|Math\.abs' "$D/TASK.md" || false
  run "$VS" --root "$S" --allow-partial
  [ "$status" -eq 0 ]
  # the installed checkout is read, never written
  [ "$(cd "$I" && find . | sort)" = "$before" ]
}

@test "ST-2 without --node-modules a ts candidate is skipped by name and nothing is written; a --node-modules that is not an installed node_modules directory is exit 2" {
  commit_clean_fix
  FIX="$(git -C "$G" rev-parse HEAD)"
  run "$SEED" --since 2000-01-01 --out "$S" --repo "$G"
  [ "$status" -eq 0 ]
  grep -q "^candidate ${FIX:0:12} " <<<"$output"
  grep -qx "skipped ${FIX:0:12}: no node_modules for the proof (--node-modules DIR)" <<<"$output"
  grep -q '1 candidate(s), 0 refused, 1 skipped; selected 1, written 0, proof failed 0' <<<"$output"
  [ ! -e "$S/tasks" ]
  run "$SEED" --since 2000-01-01 --out "$S" --repo "$G" --node-modules "$I"
  [ "$status" -eq 2 ]
  grep -q 'node-modules must be an installed node_modules directory' <<<"$output"
  run "$SEED" --since 2000-01-01 --out "$S" --repo "$G" --node-modules "$T/absent/node_modules"
  [ "$status" -eq 2 ]
  [ ! -e "$S" ]
}

@test "ST-3 --dry-run lists the ts candidate and writes nothing; a candidate changing pytest and ts tests is mixed by name, --runner ts takes it" {
  commit_clean_fix
  FIX="$(git -C "$G" rev-parse HEAD)"
  run "$SEED" --since 2000-01-01 --out "$S" --repo "$G" --dry-run
  [ "$status" -eq 0 ]
  grep -q "^candidate ${FIX:0:12} " <<<"$output"
  grep -q '1 candidate(s), 0 refused, 0 skipped; dry run, nothing written' <<<"$output"
  [ ! -e "$S" ]
  mkdir -p "$G/tools/py/tests"
  printf 'def one():\n    return 1\n' > "$G/tools/py/one.py"
  printf 'from one import one\n\ndef test_one():\n    assert one() == 1\n' > "$G/tools/py/tests/test_one.py"
  printf '\ntest(%s, () => {\n  assert.equal(roundHalf(0.2), 0);\n});\n' "'small'" >> "$G/tools/calc/tests/round.test.ts"
  gc add -A; gc commit -q -m "fix: two runners at once"
  MIX="$(git -C "$G" rev-parse HEAD)"
  run "$SEED" --since 2000-01-01 --out "$S" --repo "$G" --dry-run
  [ "$status" -eq 0 ]
  grep -qx "skipped ${MIX:0:12}: mixed test runners (pytest and ts)" <<<"$output"
  run "$SEED" --since 2000-01-01 --out "$S" --repo "$G" --dry-run --runner ts
  [ "$status" -eq 0 ]
  grep -q "^candidate ${MIX:0:12} " <<<"$output"
  run "$SEED" --since 2000-01-01 --out "$S" --repo "$G" --dry-run --runner bats
  grep -qx "skipped ${MIX:0:12}: no bats test added or changed" <<<"$output"
}

@test "ST-4 the vitest shape: npx --prefix runs the package's own vitest with --root and the TAP flat reporter; its cache lands in the proof tree, the checkout stays as it was" {
  commit_vitest_fix
  FIX="$(git -C "$G" rev-parse HEAD)"
  before="$(cd "$I" && find . | sort)"
  run "$SEED" --since 2000-01-01 --out "$S" --repo "$G" --suite-version "$SV" --node-modules "$NM"
  [ "$status" -eq 0 ]
  grep -qx "proof bugfix-01 ${FIX:0:12}: red 1 failed / green 2 passed" <<<"$output"
  D="$S/tasks/bugfix-01"
  [ "$(yq -o=json -I=0 .test_command "$D/task.yaml")" = '["npx","--prefix","tools/vcalc","vitest","run","--reporter=tap-flat","--root","tools/vcalc","tools/vcalc/tests/"]' ]
  [ "$(yq -o=json -I=0 .grader_protected "$D/task.yaml")" = '["package.json","tools/vcalc/package.json","tsconfig.base.json"]' ]
  [ "$(cd "$D/fixture" && find . -type f | sort | tr '\n' ' ')" = "./package.json ./tools/vcalc/package.json ./tools/vcalc/src/clamp.ts ./tools/vcalc/tests/clamp.test.ts ./tsconfig.base.json " ]
  grep -qF 'Run the tests with `npx --prefix tools/vcalc vitest run --reporter=tap-flat --root tools/vcalc tools/vcalc/tests/`' "$D/TASK.md"
  run "$VS" --root "$S" --allow-partial
  [ "$status" -eq 0 ]
  [ "$(cd "$I" && find . | sort)" = "$before" ]
  [ ! -e "$I/tools/vcalc/node_modules/.vite" ]
}

@test "ST-5 --fixture-scope roots: the whole roots slice, the command names the changed file, the brief names the directory and the runner only" {
  commit_clean_fix
  FIX="$(git -C "$G" rev-parse HEAD)"
  run "$SEED" --since 2000-01-01 --out "$S" --repo "$G" --suite-version "$SV" --node-modules "$NM" --fixture-scope roots --paths tools
  [ "$status" -eq 0 ]
  grep -qx "proof bugfix-01 ${FIX:0:12}: red 2 failed / green 3 passed" <<<"$output"
  D="$S/tasks/bugfix-01"
  [ "$(yq -o=json -I=0 .test_command "$D/task.yaml")" = '["node","--test","--experimental-strip-types","--test-timeout=5000","--test-reporter=tap","tools/calc/tests/round.test.ts"]' ]
  [ -f "$D/fixture/tools/vcalc/src/clamp.ts" ]
  [ -f "$D/fixture/tools/shared/src/index.ts" ]
  [ -f "$D/fixture/tsconfig.base.json" ]
  [ ! -e "$D/fixture/README.md" ]
  grep -qF 'Run the tests under `tools/calc/tests` that cover the code you change, with `node --test --experimental-strip-types --test-timeout=5000 --test-reporter=tap <file>`' "$D/TASK.md"
  ! grep -qE 'round\.test|hidden' "$D/TASK.md" || false
  run "$VS" --root "$S" --allow-partial
  [ "$status" -eq 0 ]
}

@test "ST-6 a package whose test script is neither vitest nor node --test is skipped with the script named" {
  mkdir -p "$G/tools/jcalc/src" "$G/tools/jcalc/tests"
  printf '{"name": "@ws/jcalc", "type": "module", "scripts": {"test": "jest"}}\n' > "$G/tools/jcalc/package.json"
  printf 'export const one = (): number => 1;\n' > "$G/tools/jcalc/src/one.ts"
  printf "import { one } from '../src/one.ts';\ntest('one', () => { expect(one()).toBe(1); });\n" > "$G/tools/jcalc/tests/one.test.ts"
  gc add -A; gc commit -q -m "chore: a jest package"
  printf 'export const one = (): number => 1; // fixed\n' > "$G/tools/jcalc/src/one.ts"
  printf "test('still one', () => { expect(one()).toBe(1); });\n" >> "$G/tools/jcalc/tests/one.test.ts"
  gc add -A; gc commit -q -m "fix(jcalc): a comment"
  FIX="$(git -C "$G" rev-parse HEAD)"
  install_checkout
  run "$SEED" --since 2000-01-01 --out "$S" --repo "$G" --node-modules "$NM"
  [ "$status" -eq 0 ]
  grep -qx "skipped ${FIX:0:12}: the test script of tools/jcalc/package.json is not vitest or node --test: 'jest'" <<<"$output"
  [ ! -e "$S/tasks" ]
}

@test "ST-7 a hidden test that cannot load is red at base but not green at reference: the proof fails with the first error named, nothing written (touched scope carries only the changed tests, so the one file runs)" {
  commit_clean_fix
  printf "import { test } from 'node:test';\nimport assert from 'node:assert/strict';\nimport { nope } from '../src/missing.ts';\n\ntest('nope', () => {\n  assert.equal(nope(), 1);\n});\n" > "$G/tools/calc/tests/broken.test.ts"
  echo '// touched' >> "$G/tools/calc/src/round.ts"
  gc add -A; gc commit -q -m "fix(calc): a test of a module that is not there"
  BAD="$(git -C "$G" rev-parse HEAD)"
  install_checkout
  run "$SEED" --since 2000-01-01 --select 1 --out "$S" --repo "$G" --node-modules "$NM"
  [ "$status" -eq 1 ]
  grep -q "^proof-failed ${BAD:0:12}: not green at reference (exit 1, 1 failed, 0 passed); first error: " <<<"$output"
  grep -qE 'Cannot find module|ERR_MODULE_NOT_FOUND' <<<"$output"
  [ ! -e "$S/tasks" ]
}

@test "ST-8 the refactor seeder: a two-file refactor under a node --test package is proved green at both ends through the farm; without --node-modules it is skipped by name" {
  commit_clean_fix
  cat > "$G/tools/calc/src/half.ts" <<'TS'
export function halfUp(x: number): number {
  return Math.trunc(Math.abs(x) + 0.5);
}
TS
  cat > "$G/tools/calc/src/round.ts" <<'TS'
import { sign } from '@ws/shared';
import { halfUp } from './half.ts';

/** Round to the nearest integer, halves away from zero. */
export function roundHalf(x: number): number {
  return sign(x) * halfUp(x);
}
TS
  gc add -A; gc commit -q -m "refactor(calc): the half-up step in its own module"
  REF="$(git -C "$G" rev-parse HEAD)"
  install_checkout
  run "$SEEDR" --since 2000-01-01 --select 1 --out "$S" --repo "$G" --suite-version "$SV"
  [ "$status" -eq 0 ]
  grep -qx "skipped ${REF:0:12}: no node_modules for the proof (--node-modules DIR)" <<<"$output"
  [ ! -e "$S/tasks" ]
  run "$SEEDR" --since 2000-01-01 --select 1 --out "$S" --repo "$G" --suite-version "$SV" --node-modules "$NM"
  [ "$status" -eq 0 ]
  grep -qx "proof refactor-01 ${REF:0:12}: green at base (3 passed) / green at reference (3 passed)" <<<"$output"
  grep -qx "churn refactor-01: files 2, insertions 5, deletions 1" <<<"$output"
  D="$S/tasks/refactor-01"
  [ "$(yq -o=json -I=0 .test_command "$D/task.yaml")" = '["node","--test","--experimental-strip-types","--test-timeout=5000","--test-reporter=tap","tools/calc/tests/*.test.ts"]' ]
  [ -f "$D/fixture/tools/shared/src/index.ts" ]
  [ ! -e "$D/fixture/tools/calc/src/half.ts" ]
  grep -q '^+++ b/tools/calc/src/half.ts' "$D/hidden/reference.patch"
}
