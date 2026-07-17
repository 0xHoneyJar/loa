#!/usr/bin/env node

import {
  cpSync,
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  renameSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  bundleLockBytes,
  canonicalJson,
  digestEntries,
  fileDigest,
  readJsonFile,
  resealBundleLock,
  sortedUnique,
  utf8Compare,
} from './lib/bundle-format.ts';
import type {
  AdapterManifest,
  BundleLock,
  CoreManifest,
} from './lib/bundle-format.ts';
import {
  assembleBundles,
  humanVerificationPrefix,
  verifyBundle,
  verifyBundleSet,
  verifyDefaultBundleOutput,
} from './assemble-bundles.ts';

const SCRIPT_PATH = fileURLToPath(import.meta.url);
const REPO_ROOT = resolve(dirname(SCRIPT_PATH), '..');
const BUNDLE_IDS = ['aleph-for-loa', 'aleph-for-hermes'] as const;
const FIXED_GIT_DATE = '2000-01-01T00:00:00Z';

interface CaseResult {
  name: string;
  status: 'PASS' | 'FAIL';
  error?: string;
}

interface TestReport {
  result: 'PASS' | 'FAIL';
  cases: CaseResult[];
}

interface BundleSet {
  output: string;
  loa: string;
  hermes: string;
  locks: {
    loa: BundleLock;
    hermes: BundleLock;
  };
}

interface CliOptions {
  json: boolean;
  help: boolean;
  error: string;
}

const options: CliOptions = {
  json: false,
  help: false,
  error: '',
};

for (const arg of process.argv.slice(2)) {
  if (arg === '--json') options.json = true;
  else if (arg === '--help' || arg === '-h') options.help = true;
  else options.error = `unknown argument "${arg}"`;
}

function fail(message: string): never {
  throw new Error(message);
}

function expect(condition: boolean, message: string): asserts condition {
  if (!condition) fail(message);
}

function expectEqual(
  actual: unknown,
  expected: unknown,
  message: string,
): void {
  if (actual !== expected) {
    fail(`${message}: expected ${String(expected)}, got ${String(actual)}`);
  }
}

function expectNotEqual(
  actual: unknown,
  expected: unknown,
  message: string,
): void {
  if (actual === expected) {
    fail(`${message}: both were ${String(actual)}`);
  }
}

function runGit(
  root: string,
  args: string[],
  fixedCommitDate = false,
): string {
  const result = spawnSync('git', ['-C', root, ...args], {
    encoding: 'utf8',
    maxBuffer: 32 * 1024 * 1024,
    env: fixedCommitDate
      ? {
          ...process.env,
          GIT_AUTHOR_DATE: FIXED_GIT_DATE,
          GIT_COMMITTER_DATE: FIXED_GIT_DATE,
        }
      : process.env,
  });
  if (result.status !== 0) {
    fail(
      `git ${args.join(' ')} failed: ${
        result.stderr.trim()
        || result.error?.message
        || `status ${String(result.status)}`
      }`,
    );
  }
  return result.stdout;
}

function sourceInventory(): string[] {
  return runGit(
    REPO_ROOT,
    ['ls-files', '-z', '--cached', '--others', '--exclude-standard'],
  )
    .split('\0')
    .filter(Boolean)
    .sort(utf8Compare);
}

function copyInventory(
  sourceRoot: string,
  destination: string,
  inventory: string[],
): void {
  mkdirSync(destination, { recursive: true });
  for (const path of inventory) {
    const source = join(sourceRoot, path);
    const target = join(destination, path);
    expect(
      existsSync(source) && lstatSync(source).isFile(),
      `live inventory path is missing or not a file: ${path}`,
    );
    mkdirSync(dirname(target), { recursive: true });
    cpSync(source, target);
  }
}

function copyRepository(
  sourceRoot: string,
  destination: string,
  inventory: string[],
  commit = true,
): void {
  copyInventory(sourceRoot, destination, inventory);
  runGit(destination, ['init', '-q']);
  runGit(destination, ['add', '--all']);
  if (commit) {
    runGit(
      destination,
      [
        '-c',
        'user.name=Aleph Bundle Tests',
        '-c',
        'user.email=aleph-bundle-tests.invalid',
        '-c',
        'commit.gpgsign=false',
        'commit',
        '-qm',
        'frozen bundle test source',
      ],
      true,
    );
  }
}

function copyFreshRepository(
  tempRoot: string,
  inventory: string[],
  frozenSource: string,
  name: string,
  commit = true,
): string {
  const root = join(tempRoot, name, 'source');
  copyRepository(frozenSource, root, inventory, commit);
  return root;
}

function readLock(bundleRoot: string): BundleLock {
  return readJsonFile(join(bundleRoot, 'bundle.lock.json')) as BundleLock;
}

function bundleSet(output: string): BundleSet {
  const loa = join(output, 'aleph-for-loa');
  const hermes = join(output, 'aleph-for-hermes');
  return {
    output,
    loa,
    hermes,
    locks: {
      loa: readLock(loa),
      hermes: readLock(hermes),
    },
  };
}

function assemblyFailureText(
  report: ReturnType<typeof assembleBundles>,
): string {
  return report.errors.join('; ');
}

function assembleOrFail(source: string, output: string): BundleSet {
  const report = assembleBundles(source, output);
  if (report.result !== 'PASS') {
    fail(`assembly failed: ${assemblyFailureText(report) || 'no error reported'}`);
  }
  expectEqual(report.bundles.length, 2, 'assembly bundle count');
  const ids = report.bundles.map((bundle) => bundle.id).sort(utf8Compare);
  expectEqual(
    canonicalJson(ids),
    canonicalJson([...BUNDLE_IDS].sort(utf8Compare)),
    'assembly target set',
  );
  const set = bundleSet(output);
  for (const path of [set.loa, set.hermes]) {
    const verification = verifyBundle(path);
    if (verification.result !== 'PASS') {
      fail(
        `independent verification failed for ${path}: ${
          verification.errors.join('; ')
        }`,
      );
    }
  }
  return set;
}

function expectAssemblyFailure(
  source: string,
  output: string,
  pattern: RegExp,
): void {
  const report = assembleBundles(source, output);
  expectEqual(report.result, 'FAIL', 'assembly mutation result');
  const text = assemblyFailureText(report);
  expect(text.length > 0, 'failed assembly omitted diagnostics');
  expect(pattern.test(text), `assembly failure did not match ${String(pattern)}: ${text}`);
}

function recursiveFiles(root: string): string[] {
  const paths: string[] = [];
  function visit(directory: string, prefix: string): void {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const path = prefix ? `${prefix}/${entry.name}` : entry.name;
      const absolute = join(directory, entry.name);
      const stat = lstatSync(absolute);
      if (stat.isSymbolicLink()) fail(`unexpected symlink in test tree: ${path}`);
      if (stat.isDirectory()) visit(absolute, path);
      else if (stat.isFile()) paths.push(path);
      else fail(`unexpected non-file in test tree: ${path}`);
    }
  }
  visit(root, '');
  return paths.sort(utf8Compare);
}

function expectByteIdenticalTrees(left: string, right: string): void {
  const leftPaths = recursiveFiles(left);
  const rightPaths = recursiveFiles(right);
  expectEqual(
    canonicalJson(leftPaths),
    canonicalJson(rightPaths),
    'repeated assembly file inventory',
  );
  for (const path of leftPaths) {
    expect(
      readFileSync(join(left, path)).equals(readFileSync(join(right, path))),
      `repeated assembly bytes differ at ${path}`,
    );
  }
}

function expectEqualCore(set: BundleSet): void {
  expectEqual(
    set.locks.loa.core.tree_digest,
    set.locks.hermes.core.tree_digest,
    'host bundle Core digest equality',
  );
  const loaFiles = set.locks.loa.files
    .filter((file) => file.classification === 'core');
  const hermesFiles = set.locks.hermes.files
    .filter((file) => file.classification === 'core');
  expectEqual(
    canonicalJson(loaFiles),
    canonicalJson(hermesFiles),
    'host bundle Core inventories',
  );
  for (const file of loaFiles) {
    expect(
      readFileSync(join(set.loa, file.path)).equals(
        readFileSync(join(set.hermes, file.path)),
      ),
      `host bundle Core bytes differ at ${file.path}`,
    );
  }
}

function appendBytes(path: string, suffix = '\n'): void {
  writeFileSync(path, Buffer.concat([
    readFileSync(path),
    Buffer.from(suffix, 'utf8'),
  ]));
}

function readCoreManifest(root: string): CoreManifest {
  return readJsonFile(join(root, 'core.manifest.json')) as CoreManifest;
}

function writeJson(path: string, value: unknown): void {
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`);
}

function writeCoreManifest(root: string, manifest: CoreManifest): void {
  writeJson(join(root, 'core.manifest.json'), manifest);
}

function adapterManifestPath(root: string, adapterId: 'loa' | 'hermes'): string {
  return join(root, 'adapters', adapterId, 'adapter.manifest.json');
}

function readAdapterManifest(
  root: string,
  adapterId: 'loa' | 'hermes',
): AdapterManifest {
  return readJsonFile(adapterManifestPath(root, adapterId)) as AdapterManifest;
}

function writeAdapterManifest(
  root: string,
  adapterId: 'loa' | 'hermes',
  manifest: AdapterManifest,
): void {
  writeJson(adapterManifestPath(root, adapterId), manifest);
}

function cloneBundle(source: string, destination: string): string {
  cpSync(source, destination, { recursive: true });
  return destination;
}

function writeLock(bundleRoot: string, lock: BundleLock): void {
  writeFileSync(join(bundleRoot, 'bundle.lock.json'), bundleLockBytes(lock));
}

function mutateResealedLock(
  bundleRoot: string,
  mutate: (lock: BundleLock) => void,
): void {
  const lock = readLock(bundleRoot);
  mutate(lock);
  writeLock(bundleRoot, resealBundleLock(lock));
}

function resealPayloadFromDisk(bundleRoot: string): void {
  const lock = readLock(bundleRoot);
  lock.files = lock.files.map((file) => ({
    ...file,
    digest: fileDigest(bundleRoot, file.path),
  }));
  lock.core.tree_digest = digestEntries(
    lock.files.filter((file) => file.classification === 'core'),
  );
  lock.adapter.tree_digest = digestEntries(
    lock.files.filter((file) => file.classification === 'adapter'),
  );
  lock.checker_digest = digestEntries(
    lock.files.filter((file) => (
      lock.source.manifest_projection.checker_paths.includes(file.path)
    )),
  );
  lock.bundle.payload_digest = digestEntries(lock.files);
  const assemblyTool = lock.files.find(
    (file) => file.path === lock.source.assembly_tool.path,
  );
  expect(assemblyTool !== undefined, 'resealed payload omitted assembly tool');
  lock.source.assembly_tool.digest = assemblyTool.digest;
  writeLock(bundleRoot, resealBundleLock(lock));
}

function expectVerificationFailure(
  bundleRoot: string,
  pattern: RegExp,
): void {
  const report = verifyBundle(bundleRoot);
  expectEqual(report.result, 'FAIL', 'bundle verification mutation result');
  if (report.summary) {
    expectEqual(
      report.summary.preflight,
      'NOT-READY',
      'failed bundle verification preflight',
    );
  }
  expectEqual(
    humanVerificationPrefix(report),
    null,
    'failed bundle human CLI verification prefix',
  );
  const text = report.errors.join('; ');
  expect(text.length > 0, 'failed bundle verification omitted diagnostics');
  expect(pattern.test(text), `verification failure did not match ${String(pattern)}: ${text}`);
}

function runCase(
  results: CaseResult[],
  name: string,
  execute: () => void,
): void {
  try {
    execute();
    results.push({ name, status: 'PASS' });
  } catch (error) {
    results.push({
      name,
      status: 'FAIL',
      error: error instanceof Error ? error.message : String(error),
    });
  }
}

function expectSetVerificationFailure(
  bundleRoots: string[],
  pattern: RegExp,
  expectedBundleIds: readonly string[] = [],
): void {
  const report = verifyBundleSet(bundleRoots, expectedBundleIds);
  expectEqual(report.result, 'FAIL', 'release-set verification mutation result');
  const text = report.errors.join('; ');
  expect(
    pattern.test(text),
    `release-set verification failure did not match ${String(pattern)}: ${text}`,
  );
}

function expectDefaultVerificationFailure(
  output: string,
  pattern: RegExp,
): void {
  const result = verifyDefaultBundleOutput(output);
  expectEqual(result.result, 'FAIL', 'default bundle verification mutation result');
  const text = result.errors.join('; ');
  expect(
    pattern.test(text),
    `default verification failure did not match ${String(pattern)}: ${text}`,
  );
}

function compareCoreMutation(baseline: BundleSet, changed: BundleSet): void {
  expectNotEqual(
    changed.locks.loa.core.tree_digest,
    baseline.locks.loa.core.tree_digest,
    'Core mutation Loa Core digest',
  );
  expectEqualCore(changed);
  expectEqual(
    changed.locks.loa.adapter.tree_digest,
    baseline.locks.loa.adapter.tree_digest,
    'Core mutation Loa adapter digest',
  );
  expectEqual(
    changed.locks.hermes.adapter.tree_digest,
    baseline.locks.hermes.adapter.tree_digest,
    'Core mutation Hermes adapter digest',
  );
  expectNotEqual(
    changed.locks.loa.lock_digest,
    baseline.locks.loa.lock_digest,
    'Core mutation Loa lock digest',
  );
  expectNotEqual(
    changed.locks.hermes.lock_digest,
    baseline.locks.hermes.lock_digest,
    'Core mutation Hermes lock digest',
  );
  expectNotEqual(
    changed.locks.loa.bundle.digest,
    baseline.locks.loa.bundle.digest,
    'Core mutation Loa bundle digest',
  );
  expectNotEqual(
    changed.locks.hermes.bundle.digest,
    baseline.locks.hermes.bundle.digest,
    'Core mutation Hermes bundle digest',
  );
}

function compareAdapterMutation(
  baseline: BundleSet,
  changed: BundleSet,
  selected: 'loa' | 'hermes',
): void {
  const foreign = selected === 'loa' ? 'hermes' : 'loa';
  expectEqual(
    changed.locks[selected].core.tree_digest,
    baseline.locks[selected].core.tree_digest,
    `${selected}-only mutation Core digest`,
  );
  expectNotEqual(
    changed.locks[selected].adapter.tree_digest,
    baseline.locks[selected].adapter.tree_digest,
    `${selected}-only mutation selected adapter digest`,
  );
  expectNotEqual(
    changed.locks[selected].lock_digest,
    baseline.locks[selected].lock_digest,
    `${selected}-only mutation selected lock digest`,
  );
  expectNotEqual(
    changed.locks[selected].bundle.digest,
    baseline.locks[selected].bundle.digest,
    `${selected}-only mutation selected bundle digest`,
  );
  expectEqual(
    changed.locks[foreign].adapter.tree_digest,
    baseline.locks[foreign].adapter.tree_digest,
    `${selected}-only mutation foreign adapter digest`,
  );
  expectEqual(
    changed.locks[foreign].lock_digest,
    baseline.locks[foreign].lock_digest,
    `${selected}-only mutation foreign lock digest`,
  );
  expectEqual(
    changed.locks[foreign].bundle.digest,
    baseline.locks[foreign].bundle.digest,
    `${selected}-only mutation foreign bundle digest`,
  );
  expectByteIdenticalTrees(
    baseline[foreign],
    changed[foreign],
  );
}

function addLoaOwnedFile(root: string, path: string, bytes: string): void {
  mkdirSync(dirname(join(root, path)), { recursive: true });
  writeFileSync(join(root, path), bytes);
  const core = readCoreManifest(root);
  core.files.adapter.loa = sortedUnique([
    ...(core.files.adapter.loa || []),
    path,
  ]);
  writeCoreManifest(root, core);
  const loa = readAdapterManifest(root, 'loa');
  loa.owned_paths = sortedUnique([...loa.owned_paths, path]);
  writeAdapterManifest(root, 'loa', loa);
}

function renameLoaOwnedFile(
  root: string,
  from: string,
  to: string,
): void {
  mkdirSync(dirname(join(root, to)), { recursive: true });
  renameSync(join(root, from), join(root, to));
  const core = readCoreManifest(root);
  core.files.adapter.loa = sortedUnique(
    core.files.adapter.loa.map((path) => path === from ? to : path),
  );
  writeCoreManifest(root, core);
  const loa = readAdapterManifest(root, 'loa');
  loa.owned_paths = sortedUnique(
    loa.owned_paths.map((path) => path === from ? to : path),
  );
  writeAdapterManifest(root, 'loa', loa);
}

function deleteLoaOwnedFile(root: string, path: string): void {
  rmSync(join(root, path), { force: true });
  const core = readCoreManifest(root);
  core.files.adapter.loa = core.files.adapter.loa.filter(
    (candidate) => candidate !== path,
  );
  writeCoreManifest(root, core);
  const loa = readAdapterManifest(root, 'loa');
  loa.owned_paths = loa.owned_paths.filter((candidate) => candidate !== path);
  writeAdapterManifest(root, 'loa', loa);
}

function execute(): TestReport {
  const results: CaseResult[] = [];
  const tempRoot = mkdtempSync(join(tmpdir(), 'aleph-bundle-tests-'));
  try {
    const inventory = sourceInventory();
    const frozenSource = join(tempRoot, 'live-source-snapshot');
    copyInventory(REPO_ROOT, frozenSource, inventory);
    let baseline: BundleSet;
    let repeated: BundleSet;
    let coreMutation: BundleSet | undefined;
    try {
      const source = copyFreshRepository(
        tempRoot,
        inventory,
        frozenSource,
        'baseline',
      );
      baseline = assembleOrFail(source, join(tempRoot, 'baseline-output'));
      repeated = assembleOrFail(source, join(tempRoot, 'repeated-output'));
    } catch (error) {
      results.push({
        name: 'baseline assembly and verification',
        status: 'FAIL',
        error: error instanceof Error ? error.message : String(error),
      });
      return { result: 'FAIL', cases: results };
    }

    runCase(results, 'repeated assembly is byte-identical', () => {
      expectByteIdenticalTrees(baseline.loa, repeated.loa);
      expectByteIdenticalTrees(baseline.hermes, repeated.hermes);
    });

    runCase(results, 'canonical JSON rejects unpaired UTF-16 surrogates', () => {
      let error = '';
      try {
        canonicalJson('\ud800');
      } catch (caught) {
        error = caught instanceof Error ? caught.message : String(caught);
      }
      expect(
        /surrogate|unicode|utf-?16/i.test(error),
        `unpaired surrogate was accepted or misdiagnosed: ${error || 'no error'}`,
      );
    });

    runCase(results, 'both bundles contain byte-identical Core', () => {
      expectEqualCore(baseline);
    });

    runCase(results, 'independent verification accepts both baseline bundles', () => {
      for (const [path, preflight] of [
        [baseline.loa, 'READY'],
        [baseline.hermes, 'NOT-READY'],
      ] as const) {
        const report = verifyBundle(path);
        if (report.result !== 'PASS') {
          fail(`${path}: ${report.errors.join('; ')}`);
        }
        expectEqual(report.summary?.preflight, preflight, `${path} preflight`);
        expectEqual(
          humanVerificationPrefix(report),
          'VERIFIED',
          `${path} human CLI verification prefix`,
        );
      }
    });

    runCase(results, 'Core mutation changes both bundle identities', () => {
      const source = copyFreshRepository(
        tempRoot,
        inventory,
        frozenSource,
        'core-mutation',
      );
      appendBytes(join(source, 'README.md'));
      const changed = assembleOrFail(source, join(tempRoot, 'core-output'));
      compareCoreMutation(baseline, changed);
      coreMutation = changed;
    });

    runCase(results, 'Loa-only mutation changes only aleph-for-loa', () => {
      const source = copyFreshRepository(
        tempRoot,
        inventory,
        frozenSource,
        'loa-mutation',
      );
      appendBytes(adapterManifestPath(source, 'loa'));
      const changed = assembleOrFail(source, join(tempRoot, 'loa-output'));
      compareAdapterMutation(baseline, changed, 'loa');
    });

    runCase(results, 'Hermes-only mutation changes only aleph-for-hermes', () => {
      const source = copyFreshRepository(
        tempRoot,
        inventory,
        frozenSource,
        'hermes-mutation',
      );
      appendBytes(adapterManifestPath(source, 'hermes'));
      const changed = assembleOrFail(source, join(tempRoot, 'hermes-output'));
      compareAdapterMutation(baseline, changed, 'hermes');
    });

    runCase(results, 'foreign-adapter reference injection fails', () => {
      const source = copyFreshRepository(
        tempRoot,
        inventory,
        frozenSource,
        'foreign-reference',
      );
      const loa = readAdapterManifest(source, 'loa');
      loa.references.push('adapters/hermes/adapter.manifest.json');
      writeAdapterManifest(source, 'loa', loa);
      expectAssemblyFailure(
        source,
        join(tempRoot, 'foreign-reference-output'),
        /CB8|foreign[- ]adapter|Hermes/i,
      );
    });

    runCase(results, 'release verification rejects divergent Core bundles', () => {
      expect(coreMutation !== undefined, 'Core-mutation bundle is unavailable');
      expectSetVerificationFailure(
        [baseline.loa, coreMutation.hermes],
        /FAIL|Core|diverg/i,
      );
    });

    runCase(results, 'release verification rejects duplicate host bundles', () => {
      expectSetVerificationFailure(
        [baseline.loa, baseline.loa],
        /FAIL|exact|duplicate|loa|hermes|target/i,
      );
    });

    runCase(results, 'default verification rejects swapped host directories', () => {
      const output = join(tempRoot, 'swapped-host-output');
      mkdirSync(output, { recursive: true });
      cloneBundle(baseline.hermes, join(output, 'aleph-for-loa'));
      cloneBundle(baseline.loa, join(output, 'aleph-for-hermes'));
      expectDefaultVerificationFailure(
        output,
        /expected bundle aleph-for-(loa|hermes), found aleph-for-(hermes|loa)/i,
      );
    });

    runCase(results, 'adapter Core override fails', () => {
      const source = copyFreshRepository(
        tempRoot,
        inventory,
        frozenSource,
        'core-override',
      );
      const loa = readAdapterManifest(source, 'loa');
      loa.core_consumption.overrides.push('README.md');
      writeAdapterManifest(source, 'loa', loa);
      expectAssemblyFailure(
        source,
        join(tempRoot, 'core-override-output'),
        /CB5|CB7|override/i,
      );
    });

    runCase(results, 'nonignored untracked unclassified source file fails', () => {
      const source = copyFreshRepository(
        tempRoot,
        inventory,
        frozenSource,
        'unclassified-source',
      );
      writeFileSync(
        join(source, 'UNCLASSIFIED.txt'),
        'nonignored and intentionally unclassified\n',
      );
      expectAssemblyFailure(
        source,
        join(tempRoot, 'unclassified-output'),
        /CB2|unclassified/i,
      );
    });

    runCase(results, 'tracked source deletion cannot escape inventory', () => {
      const source = copyFreshRepository(
        tempRoot,
        inventory,
        frozenSource,
        'tracked-deletion',
      );
      const deletedPath = 'docs/architecture/10-build-roadmap-slices.md';
      rmSync(join(source, deletedPath));
      const core = readCoreManifest(source);
      core.files.core = core.files.core.filter((path) => path !== deletedPath);
      writeCoreManifest(source, core);
      expectAssemblyFailure(
        source,
        join(tempRoot, 'tracked-deletion-output'),
        /CB2|tracked|missing|unclassified/i,
      );
    });

    runCase(results, 'unresolved source repository provenance fails', () => {
      const source = copyFreshRepository(
        tempRoot,
        inventory,
        frozenSource,
        'unresolved-source',
        false,
      );
      expectAssemblyFailure(
        source,
        join(tempRoot, 'unresolved-source-output'),
        /HEAD|commit|provenance|revision|unresolved/i,
      );
    });

    runCase(results, 'missing emitted file fails verification', () => {
      const bundle = cloneBundle(
        baseline.loa,
        join(tempRoot, 'bundle-missing'),
      );
      rmSync(join(bundle, 'README.md'));
      expectVerificationFailure(bundle, /missing bundle file|digest mismatch/i);
    });

    runCase(results, 'extra emitted file fails verification', () => {
      const bundle = cloneBundle(
        baseline.loa,
        join(tempRoot, 'bundle-extra'),
      );
      writeFileSync(join(bundle, 'EXTRA.txt'), 'not in the lock\n');
      expectVerificationFailure(bundle, /extra bundle file/i);
    });

    runCase(results, 'modified emitted file fails verification', () => {
      const bundle = cloneBundle(
        baseline.loa,
        join(tempRoot, 'bundle-modified'),
      );
      appendBytes(join(bundle, 'README.md'), '\nmodified\n');
      expectVerificationFailure(bundle, /modified bundle file|digest mismatch/i);
    });

    runCase(results, 'failed implemented bundle is not READY or VERIFIED', () => {
      const bundle = cloneBundle(
        baseline.loa,
        join(tempRoot, 'bundle-failed-preflight'),
      );
      expectEqual(
        readLock(bundle).adapter.lifecycle,
        'implemented',
        'failed-preflight fixture lifecycle',
      );
      appendBytes(join(bundle, 'README.md'), '\nmodified for failed preflight\n');
      expectVerificationFailure(bundle, /modified bundle file|digest mismatch/i);
    });

    runCase(results, 'renamed emitted file fails verification', () => {
      const bundle = cloneBundle(
        baseline.loa,
        join(tempRoot, 'bundle-renamed'),
      );
      renameSync(
        join(bundle, 'README.md'),
        join(bundle, 'README-renamed.md'),
      );
      expectVerificationFailure(bundle, /missing bundle file|extra bundle file/i);
    });

    runCase(results, 'unresealed lock tampering fails verification', () => {
      const bundle = cloneBundle(
        baseline.loa,
        join(tempRoot, 'bundle-lock-tamper'),
      );
      const lock = readLock(bundle);
      lock.core.version = `${lock.core.version}-tampered`;
      writeLock(bundle, lock);
      expectVerificationFailure(bundle, /lock digest mismatch|bundle digest mismatch/i);
    });

    runCase(results, 'resealed decoded foreign-host injection fails verification', () => {
      const bundle = cloneBundle(
        baseline.loa,
        join(tempRoot, 'bundle-decoded-foreign-host'),
      );
      const manifestPath = join(bundle, 'adapters/loa/adapter.manifest.json');
      const before = readFileSync(manifestPath, 'utf8');
      const after = before.replace(
        '"/loa-aleph"',
        '"herm\\u0065s-entry"',
      );
      expectNotEqual(after, before, 'foreign-host escape mutation');
      writeFileSync(manifestPath, after);
      resealPayloadFromDisk(bundle);
      expectVerificationFailure(
        bundle,
        /foreign[- ]adapter|foreign host|hermes/i,
      );
    });

    runCase(results, 'resealed decoded foreign-host object key fails verification', () => {
      const bundle = cloneBundle(
        baseline.loa,
        join(tempRoot, 'bundle-decoded-foreign-host-key'),
      );
      const manifestPath = join(bundle, 'adapters/loa/adapter.manifest.json');
      const before = readFileSync(manifestPath, 'utf8');
      const after = before.replace(
        '"full_mode": {',
        '"full_mode": {\n    "herm\\u0065s-flag": false,',
      );
      expectNotEqual(after, before, 'foreign-host escaped object-key mutation');
      writeFileSync(manifestPath, after);
      resealPayloadFromDisk(bundle);
      expectVerificationFailure(
        bundle,
        /decoded adapter manifest names foreign adapter or host hermes/i,
      );
    });

    runCase(results, 'resealed lifecycle mismatch fails verification', () => {
      const bundle = cloneBundle(
        baseline.loa,
        join(tempRoot, 'bundle-lifecycle-mismatch'),
      );
      mutateResealedLock(bundle, (lock) => {
        lock.adapter.lifecycle = lock.adapter.lifecycle === 'implemented'
          ? 'validated'
          : 'implemented';
      });
      expectVerificationFailure(
        bundle,
        /adapter lock identity disagrees with emitted manifest/i,
      );
    });

    runCase(results, 'provenance object-ID substitution fails verification', () => {
      const bundle = cloneBundle(
        baseline.loa,
        join(tempRoot, 'bundle-provenance-substitution'),
      );
      mutateResealedLock(bundle, (lock) => {
        const objectLength = lock.provenance.vcs.object_format === 'sha1' ? 40 : 64;
        lock.provenance.vcs.commit = '1'.repeat(objectLength);
        lock.provenance.vcs.commit_tree = '2'.repeat(objectLength);
      });
      expectVerificationFailure(
        bundle,
        /lock digest mismatch|bundle digest mismatch|provenance/i,
      );
    });

    runCase(results, 'resealed malformed lifecycle fails verification', () => {
      const bundle = cloneBundle(
        baseline.loa,
        join(tempRoot, 'bundle-lifecycle-malformed'),
      );
      mutateResealedLock(bundle, (lock) => {
        lock.adapter.lifecycle = 'not-a-lifecycle';
      });
      expectVerificationFailure(bundle, /adapter\.lifecycle is malformed/i);
    });

    runCase(results, 'resealed malformed provenance fails verification', () => {
      const bundle = cloneBundle(
        baseline.loa,
        join(tempRoot, 'bundle-provenance-malformed'),
      );
      mutateResealedLock(bundle, (lock) => {
        const vcs = lock.provenance.vcs as unknown as Record<string, unknown>;
        vcs.kind = 'mutable-branch-checkout';
        vcs.object_format = 'unknown';
      });
      expectVerificationFailure(
        bundle,
        /provenance\.vcs\.(kind|object_format)/i,
      );
    });

    runCase(results, 'resealed mutable provenance fails verification', () => {
      const bundle = cloneBundle(
        baseline.loa,
        join(tempRoot, 'bundle-provenance-mutable'),
      );
      mutateResealedLock(bundle, (lock) => {
        const vcs = lock.provenance.vcs as unknown as Record<string, unknown>;
        vcs.mutable_ref = 'refs/heads/main';
      });
      expectVerificationFailure(
        bundle,
        /provenance\.vcs\.mutable_ref must be null/i,
      );
    });

    runCase(results, 'resealed unresolved provenance fails verification', () => {
      const bundle = cloneBundle(
        baseline.loa,
        join(tempRoot, 'bundle-provenance-unresolved'),
      );
      mutateResealedLock(bundle, (lock) => {
        const vcs = lock.provenance.vcs as unknown as Record<string, unknown>;
        vcs.resolved = false;
        vcs.commit = '0'.repeat(
          lock.provenance.vcs.object_format === 'sha1' ? 40 : 64,
        );
      });
      expectVerificationFailure(
        bundle,
        /provenance\.vcs\.(resolved|commit)/i,
      );
    });

    runCase(results, 'valid rename and deletion remove stale output paths', () => {
      const source = copyFreshRepository(
        tempRoot,
        inventory,
        frozenSource,
        'stale-output',
      );
      const output = join(tempRoot, 'stale-output-bundles');
      const original = 'adapters/loa/planned-bundle-note.txt';
      const renamed = 'adapters/loa/planned-bundle-note-renamed.txt';

      addLoaOwnedFile(source, original, 'planned adapter packaging note\n');
      let assembled = assembleOrFail(source, output);
      expect(
        existsSync(join(assembled.loa, original)),
        'initial classified adapter file was not emitted',
      );

      renameLoaOwnedFile(source, original, renamed);
      assembled = assembleOrFail(source, output);
      expect(
        !existsSync(join(assembled.loa, original)),
        'renamed source left its stale output path',
      );
      expect(
        existsSync(join(assembled.loa, renamed)),
        'renamed source path was not emitted',
      );

      deleteLoaOwnedFile(source, renamed);
      assembled = assembleOrFail(source, output);
      expect(
        !existsSync(join(assembled.loa, original))
          && !existsSync(join(assembled.loa, renamed)),
        'deleted source left a stale output path',
      );
      expectEqual(
        verifyBundle(assembled.loa).result,
        'PASS',
        'post-deletion Loa verification',
      );
      expectEqual(
        verifyBundle(assembled.hermes).result,
        'PASS',
        'post-deletion Hermes verification',
      );
    });
  } finally {
    rmSync(tempRoot, { recursive: true, force: true });
  }
  return {
    result: results.every((item) => item.status === 'PASS') ? 'PASS' : 'FAIL',
    cases: results,
  };
}

function main(): void {
  if (options.help) {
    console.log('Usage: node scripts/test-bundle-assembly.ts [--json]');
    process.exit(0);
  }
  if (options.error) {
    if (options.json) {
      console.log(JSON.stringify({ result: 'FAIL', error: options.error }, null, 2));
    } else {
      console.error(`FAIL ${options.error}`);
    }
    process.exit(2);
  }
  try {
    const report = execute();
    if (options.json) {
      console.log(JSON.stringify(report, null, 2));
    } else {
      for (const result of report.cases) {
        console.log(
          `${result.status} ${result.name}`
          + (result.error ? `: ${result.error}` : ''),
        );
      }
      console.log(`RESULT: ${report.result}`);
    }
    process.exit(report.result === 'PASS' ? 0 : 1);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (options.json) {
      console.log(JSON.stringify({ result: 'FAIL', error: message }, null, 2));
    } else {
      console.error(`FAIL ${message}`);
      console.log('RESULT: FAIL');
    }
    process.exit(1);
  }
}

if (resolve(process.argv[1] || '') === SCRIPT_PATH) main();
