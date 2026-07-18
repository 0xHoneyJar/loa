#!/usr/bin/env node

import {
  closeSync,
  constants,
  existsSync,
  fstatSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  openSync,
  readFileSync,
  readdirSync,
  renameSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import {
  basename,
  dirname,
  isAbsolute,
  join,
  relative,
  resolve,
} from 'node:path';
import { fileURLToPath } from 'node:url';
import { verifyBundleSet } from '../../../scripts/assemble-bundles.ts';
import {
  DIGEST_ALGORITHM,
  canonicalJson,
  canonicalJsonBytes,
  digestEntries,
  isRecord,
  normalizedRepositoryPath,
  readJsonFile,
  sha256Digest,
  sortedUnique,
  utf8Compare,
} from '../../../scripts/lib/bundle-format.ts';
import type {
  AdapterManifest,
  BundleLock,
} from '../../../scripts/lib/bundle-format.ts';
import { acquireDurableProcessLock } from './run-control.ts';

const SCRIPT_PATH = fileURLToPath(import.meta.url);
const ADAPTER_ID = 'loa';
const BUNDLE_ID = `aleph-for-${ADAPTER_ID}`;
const INSTALL_MAP_PATH = 'adapters/loa/installation.map.json';
const INSTALL_LOCK_FORMAT = 'aleph-loa-install-lock/v1';
const MAP_FORMAT = 'aleph-loa-installation-map/v1';
const ALEPH_ROOT = '.claude/aleph';
const SKILL_ROOT = '.claude/skills/loa-aleph';
const COMMAND_PATH = '.claude/commands/loa-aleph.md';
const RUNTIME_ROOT = '.claude/aleph/runtime/bundle';
const RECORD_PATH = '.claude/aleph/install.lock.json';
const TRANSACTION_PATH = '.claude/aleph-install.transaction';
const TRANSACTION_PREPARING_PATH = '.claude/aleph-install.transaction.preparing';
const TRANSACTION_CLEANUP_PATH = '.claude/aleph-install.transaction.cleanup';
const TRANSACTION_FORMAT = 'aleph-loa-install-transaction/v1';
const TRANSACTION_RECORD = 'transaction.json';
const INSTALL_WRITER_LOCK_PATH = '.claude/aleph-install.writer.lock';
const INSTALL_WRITER_LOCK_FORMAT = 'aleph-loa-install-writer-lock/v1';
const STABLE_INSTALLATION_PARENTS = [
  '',
  '.claude',
  '.claude/skills',
  '.claude/commands',
] as const;
const ADAPTER_MANIFEST_PATH = `adapters/${ADAPTER_ID}/adapter.manifest.json`;
const SHA256_PATTERN = /^sha256:[0-9a-f]{64}$/;

interface InstallationExposure {
  id: string;
  source: string;
  destination: string;
}

interface InstallationMap {
  format: typeof MAP_FORMAT;
  runtime_root: typeof RUNTIME_ROOT;
  record_path: typeof RECORD_PATH;
  exposures: InstallationExposure[];
}

export interface LoaManagedInstallFile {
  kind: 'runtime' | 'exposure';
  classification: 'core' | 'adapter' | 'lock';
  source_path: string;
  destination_path: string;
  digest: string;
}

export interface LoaInstallLock {
  format: typeof INSTALL_LOCK_FORMAT;
  digest_algorithm: typeof DIGEST_ALGORITHM;
  install_digest: string;
  bundle: {
    id: string;
    version: string;
    payload_digest: string;
    lock_digest: string;
    digest: string;
    lock_file_digest: string;
  };
  core: BundleLock['core'];
  adapter: BundleLock['adapter'];
  checker_digest: string;
  adapter_protocol_version: string;
  run_format_version: string;
  layout: {
    map_format: string;
    map_digest: string;
    runtime_root: string;
    record_path: string;
  };
  managed_tree_digest: string;
  files: LoaManagedInstallFile[];
}

export interface LoaInstallationSummary {
  bundleId: string;
  bundleDigest: string;
  coreDigest: string;
  adapterDigest: string;
  checkerDigest: string;
  installDigest: string;
  managedTreeDigest: string;
  managedFileCount: number;
}

export interface LoaInstallationReport {
  result: 'PASS' | 'FAIL';
  targetRoot: string;
  errors: string[];
  summary?: LoaInstallationSummary;
}

interface InstallationPlan {
  snapshotRoot: string;
  lock: LoaInstallLock;
}

interface InstallationTransaction {
  format: typeof TRANSACTION_FORMAT;
  transaction_digest: string;
  mode: 'fresh' | 'update';
  previous: LoaInstallLock | null;
  next: LoaInstallLock;
}

export type LoaInstallationCheckpoint =
  | 'after-transaction-prepared'
  | 'after-command-unpublished'
  | 'after-runtime-published'
  | 'after-skill-published'
  | 'after-command-published';

export interface LoaInstallationFaultInjection {
  kind: 'failure' | 'interruption';
  after: LoaInstallationCheckpoint;
}

export interface LoaInstallationOptions {
  testFault?: LoaInstallationFaultInjection;
}

class InjectedInstallationFault extends Error {
  readonly kind: LoaInstallationFaultInjection['kind'];

  constructor(
    kind: LoaInstallationFaultInjection['kind'],
    checkpoint: LoaInstallationCheckpoint,
  ) {
    super(`injected ${kind} after ${checkpoint}`);
    this.kind = kind;
  }
}

const EXPECTED_EXPOSURES: InstallationExposure[] = [
  {
    id: 'command',
    source: 'adapters/loa/command/loa-aleph.md',
    destination: COMMAND_PATH,
  },
  {
    id: 'skill',
    source: 'adapters/loa/skill/loa-aleph/SKILL.md',
    destination: `${SKILL_ROOT}/SKILL.md`,
  },
  {
    id: 'launcher',
    source: 'runtime-js/adapters/loa/src/launcher.js',
    destination: '.claude/aleph/bin/loa-aleph.mjs',
  },
];

function exactKeys(value: unknown, keys: readonly string[]): boolean {
  return isRecord(value)
    && canonicalJson(Object.keys(value).sort(utf8Compare))
      === canonicalJson([...keys].sort(utf8Compare));
}

function sameStrings(left: string[], right: string[]): boolean {
  const a = sortedUnique(left);
  const b = sortedUnique(right);
  return a.length === b.length && a.every((value, index) => value === b[index]);
}

function pathInside(parent: string, child: string): boolean {
  const path = relative(parent, child);
  return path === '' || (!path.startsWith('..') && !isAbsolute(path));
}

function readFileNoFollow(path: string): Buffer {
  const descriptor = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    if (!fstatSync(descriptor).isFile()) {
      throw new Error(`path is not a regular file: ${path}`);
    }
    return readFileSync(descriptor);
  } finally {
    closeSync(descriptor);
  }
}

function copyTreeSnapshot(sourceRoot: string, destinationRoot: string): void {
  const source = resolve(sourceRoot);
  const rootStat = lstatSync(source);
  if (rootStat.isSymbolicLink() || !rootStat.isDirectory()) {
    throw new Error('bundle path must be a real directory, not a symlink');
  }
  function visit(sourceDirectory: string, destinationDirectory: string): void {
    mkdirSync(destinationDirectory, { recursive: true });
    const entries = readdirSync(sourceDirectory, { withFileTypes: true })
      .sort((left, right) => utf8Compare(left.name, right.name));
    for (const entry of entries) {
      const sourcePath = join(sourceDirectory, entry.name);
      const destinationPath = join(destinationDirectory, entry.name);
      const stat = lstatSync(sourcePath);
      if (stat.isSymbolicLink()) {
        throw new Error(`bundle snapshot rejects symlink: ${sourcePath}`);
      }
      if (stat.isDirectory()) {
        visit(sourcePath, destinationPath);
      } else if (stat.isFile()) {
        writeFileSync(destinationPath, readFileNoFollow(sourcePath));
      } else {
        throw new Error(`bundle snapshot rejects non-file entry: ${sourcePath}`);
      }
    }
  }
  visit(source, destinationRoot);
}

function assertSafeTargetPath(targetRoot: string, repositoryPath: string): string {
  if (!normalizedRepositoryPath(repositoryPath)) {
    throw new Error(`managed path is not normalized: ${repositoryPath}`);
  }
  const root = resolve(targetRoot);
  const destination = resolve(root, repositoryPath);
  if (!pathInside(root, destination)) {
    throw new Error(`managed path escapes target: ${repositoryPath}`);
  }
  if (existsSync(root)) {
    const rootStat = lstatSync(root);
    if (rootStat.isSymbolicLink() || !rootStat.isDirectory()) {
      throw new Error('target root must be a real directory, not a symlink');
    }
  }
  let current = root;
  const parts = repositoryPath.split('/');
  for (const part of parts.slice(0, -1)) {
    current = join(current, part);
    if (!existsSync(current)) continue;
    const stat = lstatSync(current);
    if (stat.isSymbolicLink() || !stat.isDirectory()) {
      throw new Error(`managed path has unsafe parent: ${repositoryPath}`);
    }
  }
  if (existsSync(destination) && lstatSync(destination).isSymbolicLink()) {
    throw new Error(`managed destination is a symlink: ${repositoryPath}`);
  }
  return destination;
}

function ensureSafeParents(targetRoot: string, repositoryPath: string): void {
  const root = resolve(targetRoot);
  mkdirSync(root, { recursive: true });
  let current = root;
  for (const part of repositoryPath.split('/').slice(0, -1)) {
    current = join(current, part);
    if (existsSync(current)) {
      const stat = lstatSync(current);
      if (stat.isSymbolicLink() || !stat.isDirectory()) {
        throw new Error(`cannot create managed path through ${current}`);
      }
    } else {
      mkdirSync(current);
    }
  }
}

interface StableInstallationDirectory {
  repositoryPath: string;
  absolutePath: string;
  descriptor: number;
  device: bigint;
  inode: bigint;
}

interface InstallationParentGuard {
  targetRoot: string;
  directories: StableInstallationDirectory[];
}

interface InstallationWriterOwnership {
  guard: InstallationParentGuard;
  release: () => void;
}

function installationParentPath(targetRoot: string, repositoryPath: string): string {
  return repositoryPath ? resolve(targetRoot, repositoryPath) : resolve(targetRoot);
}

function assertNormalDirectory(path: string, label: string): void {
  const stat = lstatSync(path);
  if (stat.isSymbolicLink() || !stat.isDirectory()) {
    throw new Error(`${label} is not a stable real directory`);
  }
}

function ensureStableInstallationParents(targetRoot: string): void {
  const target = resolve(targetRoot);
  if (!existsSync(target)) mkdirSync(target, { recursive: true });
  assertNormalDirectory(target, 'installation target root');
  for (const repositoryPath of STABLE_INSTALLATION_PARENTS.slice(1)) {
    const absolute = installationParentPath(target, repositoryPath);
    const parent = dirname(absolute);
    assertNormalDirectory(parent, `installation parent ${parent}`);
    if (!existsSync(absolute)) mkdirSync(absolute);
    assertNormalDirectory(absolute, `installation parent ${repositoryPath}`);
  }
}

function openInstallationParentGuard(targetRoot: string): InstallationParentGuard {
  const target = resolve(targetRoot);
  const directories: StableInstallationDirectory[] = [];
  try {
    for (const repositoryPath of STABLE_INSTALLATION_PARENTS) {
      const absolutePath = installationParentPath(target, repositoryPath);
      const descriptor = openSync(
        absolutePath,
        constants.O_RDONLY | constants.O_DIRECTORY | constants.O_NOFOLLOW,
      );
      try {
        const opened = fstatSync(descriptor, { bigint: true });
        const named = lstatSync(absolutePath, { bigint: true });
        if (!opened.isDirectory()
          || named.isSymbolicLink()
          || !named.isDirectory()
          || opened.dev !== named.dev
          || opened.ino !== named.ino) {
          throw new Error(`installation parent identity is unstable: ${
            repositoryPath || '<target-root>'
          }`);
        }
        directories.push({
          repositoryPath,
          absolutePath,
          descriptor,
          device: opened.dev,
          inode: opened.ino,
        });
      } catch (error) {
        try {
          closeSync(descriptor);
        } catch {
          // Preserve the directory identity error.
        }
        throw error;
      }
    }
    return { targetRoot: target, directories };
  } catch (error) {
    try {
      closeInstallationParentGuard({ targetRoot: target, directories });
    } catch {
      // Preserve the guard-acquisition error while still attempting every close.
    }
    throw error;
  }
}

function assertInstallationParents(
  guard: InstallationParentGuard,
  label: string,
  ownershipOnly = false,
): void {
  const directories = ownershipOnly
    ? guard.directories.filter(({ repositoryPath }) => (
      repositoryPath === '' || repositoryPath === '.claude'
    ))
    : guard.directories;
  for (const directory of directories) {
    const opened = fstatSync(directory.descriptor, { bigint: true });
    const named = lstatSync(directory.absolutePath, { bigint: true });
    if (!opened.isDirectory()
      || named.isSymbolicLink()
      || !named.isDirectory()
      || opened.dev !== directory.device
      || opened.ino !== directory.inode
      || named.dev !== directory.device
      || named.ino !== directory.inode) {
      throw new Error(
        `${label}: installation parent identity changed: ${
          directory.repositoryPath || '<target-root>'
        }`,
      );
    }
  }
}

function closeInstallationParentGuard(guard: InstallationParentGuard): void {
  let firstError: unknown;
  for (const directory of [...guard.directories].reverse()) {
    try {
      closeSync(directory.descriptor);
    } catch (error) {
      firstError ??= error;
    }
  }
  if (firstError) throw firstError;
}

function acquireInstallationWriter(targetRoot: string): InstallationWriterOwnership {
  const target = resolve(targetRoot);
  ensureStableInstallationParents(target);
  const guard = openInstallationParentGuard(target);
  let releaseLock: (() => void) | undefined;
  try {
    assertInstallationParents(guard, 'before installation writer acquisition');
    releaseLock = acquireDurableProcessLock(join(target, INSTALL_WRITER_LOCK_PATH), {
      format: INSTALL_WRITER_LOCK_FORMAT,
      label: 'Loa installation writer',
      acquiredAt: new Date().toISOString(),
    });
    assertInstallationParents(guard, 'after installation writer acquisition');
    return {
      guard,
      release: () => {
        assertInstallationParents(guard, 'before installation writer release', true);
        releaseLock?.();
        assertInstallationParents(guard, 'after installation writer release', true);
      },
    };
  } catch (error) {
    if (releaseLock) {
      try {
        releaseLock();
      } catch {
        // Preserve the acquisition/identity error.
      }
    }
    closeInstallationParentGuard(guard);
    throw error;
  }
}

function atomicWrite(
  targetRoot: string,
  path: string,
  bytes: Buffer,
  guard?: InstallationParentGuard,
): void {
  if (guard) assertInstallationParents(guard, `before atomic write ${path}`);
  const destination = assertSafeTargetPath(targetRoot, path);
  ensureSafeParents(targetRoot, path);
  if (guard) assertInstallationParents(guard, `after parent creation for ${path}`);
  const temporary = join(
    dirname(destination),
    `.${basename(destination)}.aleph-install-${String(process.pid)}`,
  );
  if (existsSync(temporary)) {
    throw new Error(`temporary installation path already exists: ${temporary}`);
  }
  try {
    writeFileSync(temporary, bytes, { flag: 'wx' });
    if (guard) assertInstallationParents(guard, `before atomic publish ${path}`);
    renameSync(temporary, destination);
    if (guard) assertInstallationParents(guard, `after atomic publish ${path}`);
  } finally {
    if (existsSync(temporary)) {
      if (guard) assertInstallationParents(guard, `before temporary cleanup ${path}`);
      rmSync(temporary, { force: true });
      if (guard) assertInstallationParents(guard, `after temporary cleanup ${path}`);
    }
  }
}

function validateInstallationMap(
  value: unknown,
  requireCurrentExposures = true,
): InstallationMap {
  if (!exactKeys(value, ['format', 'runtime_root', 'record_path', 'exposures'])) {
    throw new Error('installation map keys are malformed');
  }
  const map = value as unknown as InstallationMap;
  if (map.format !== MAP_FORMAT
    || map.runtime_root !== RUNTIME_ROOT
    || map.record_path !== RECORD_PATH) {
    throw new Error('installation map identity or fixed paths are invalid');
  }
  if (!Array.isArray(map.exposures)
    || map.exposures.some((item) => !exactKeys(
      item,
      ['id', 'source', 'destination'],
    ))) {
    throw new Error('installation map exposures are malformed');
  }
  for (const exposure of map.exposures) {
    if (!normalizedRepositoryPath(exposure.source)
      || !normalizedRepositoryPath(exposure.destination)) {
      throw new Error(`installation exposure ${exposure.id} has an unsafe path`);
    }
  }
  const ids = map.exposures.map((exposure) => exposure.id);
  const sources = map.exposures.map((exposure) => exposure.source);
  const destinations = map.exposures.map((exposure) => exposure.destination);
  if (new Set(ids).size !== ids.length
    || new Set(sources).size !== sources.length
    || new Set(destinations).size !== destinations.length) {
    throw new Error('installation map exposures must have unique ids, sources, and destinations');
  }
  if (requireCurrentExposures
    && canonicalJson(map.exposures) !== canonicalJson(EXPECTED_EXPOSURES)) {
    throw new Error('installation exposures disagree with the Loa host layout');
  }
  return map;
}

function readInstallationMap(
  bundleRoot: string,
  requireCurrentExposures = true,
): InstallationMap {
  return validateInstallationMap(
    readJsonFile(join(bundleRoot, INSTALL_MAP_PATH)),
    requireCurrentExposures,
  );
}

function installIdentityProjection(lock: LoaInstallLock): Omit<
  LoaInstallLock,
  'install_digest'
> {
  return {
    format: lock.format,
    digest_algorithm: lock.digest_algorithm,
    bundle: structuredClone(lock.bundle),
    core: structuredClone(lock.core),
    adapter: structuredClone(lock.adapter),
    checker_digest: lock.checker_digest,
    adapter_protocol_version: lock.adapter_protocol_version,
    run_format_version: lock.run_format_version,
    layout: structuredClone(lock.layout),
    managed_tree_digest: lock.managed_tree_digest,
    files: lock.files.map((file) => ({ ...file })),
  };
}

export function resealLoaInstallLock(lock: LoaInstallLock): LoaInstallLock {
  const sealed = structuredClone(lock);
  sealed.files.sort((left, right) => (
    utf8Compare(left.destination_path, right.destination_path)
  ));
  sealed.managed_tree_digest = digestEntries(
    sealed.files.map((file) => ({
      path: file.destination_path,
      digest: file.digest,
    })),
  );
  sealed.install_digest = sha256Digest(
    canonicalJsonBytes(installIdentityProjection(sealed)),
  );
  return sealed;
}

function readVerifiedBundleLock(bundleRoot: string): BundleLock {
  const verification = verifyBundleSet([bundleRoot], [BUNDLE_ID]);
  if (verification.result !== 'PASS') {
    throw new Error(`bundle verification failed: ${verification.errors.join('; ')}`);
  }
  const report = verification.bundles[0];
  if (!report?.summary || report.summary.preflight !== 'READY') {
    throw new Error('bundle does not pass full-mode adapter preflight');
  }
  const lock = readJsonFile(join(bundleRoot, 'bundle.lock.json')) as BundleLock;
  if (lock.bundle.id !== BUNDLE_ID || lock.adapter.id !== ADAPTER_ID) {
    throw new Error('bundle does not select the Loa adapter');
  }
  if (lock.adapter.lifecycle === 'planned') {
    throw new Error('planned adapter bundle cannot be installed as full Aleph');
  }
  const adapter = readJsonFile(
    join(bundleRoot, ADAPTER_MANIFEST_PATH),
  ) as AdapterManifest;
  if (adapter.full_mode.claimed !== true) {
    throw new Error('adapter manifest does not claim structurally complete full mode');
  }
  return lock;
}

function buildInstallationPlan(snapshotRoot: string): InstallationPlan {
  const bundleLock = readVerifiedBundleLock(snapshotRoot);
  const map = readInstallationMap(snapshotRoot);
  const fileByPath = new Map(bundleLock.files.map((file) => [file.path, file]));
  const mapRecord = fileByPath.get(INSTALL_MAP_PATH);
  if (!mapRecord || mapRecord.classification !== 'adapter') {
    throw new Error('verified bundle does not classify the installation map as adapter-owned');
  }
  const files: LoaManagedInstallFile[] = bundleLock.files.map((file) => ({
    kind: 'runtime',
    classification: file.classification,
    source_path: file.path,
    destination_path: `${map.runtime_root}/${file.path}`,
    digest: file.digest,
  }));
  const rawBundleLock = readFileSync(join(snapshotRoot, 'bundle.lock.json'));
  files.push({
    kind: 'runtime',
    classification: 'lock',
    source_path: 'bundle.lock.json',
    destination_path: `${map.runtime_root}/bundle.lock.json`,
    digest: sha256Digest(rawBundleLock),
  });
  for (const exposure of map.exposures) {
    const source = fileByPath.get(exposure.source);
    if (!source || source.classification !== 'adapter') {
      throw new Error(`installation exposure is not adapter-owned: ${exposure.source}`);
    }
    files.push({
      kind: 'exposure',
      classification: 'adapter',
      source_path: exposure.source,
      destination_path: exposure.destination,
      digest: source.digest,
    });
  }
  const destinations = files.map((file) => file.destination_path);
  if (new Set(destinations).size !== destinations.length) {
    throw new Error('installation map produces duplicate destinations');
  }
  const provisional: LoaInstallLock = {
    format: INSTALL_LOCK_FORMAT,
    digest_algorithm: DIGEST_ALGORITHM,
    install_digest: sha256Digest(''),
    bundle: {
      id: bundleLock.bundle.id,
      version: bundleLock.bundle.version,
      payload_digest: bundleLock.bundle.payload_digest,
      lock_digest: bundleLock.lock_digest,
      digest: bundleLock.bundle.digest,
      lock_file_digest: sha256Digest(rawBundleLock),
    },
    core: structuredClone(bundleLock.core),
    adapter: structuredClone(bundleLock.adapter),
    checker_digest: bundleLock.checker_digest,
    adapter_protocol_version: bundleLock.adapter_protocol_version,
    run_format_version: bundleLock.run_format_version,
    layout: {
      map_format: map.format,
      map_digest: mapRecord.digest,
      runtime_root: map.runtime_root,
      record_path: map.record_path,
    },
    managed_tree_digest: sha256Digest(''),
    files,
  };
  return { snapshotRoot, lock: resealLoaInstallLock(provisional) };
}

function validManagedExposureDestination(path: string): boolean {
  return path.startsWith('.claude/aleph/bin/')
    || path.startsWith('.claude/skills/loa-aleph/')
    || /^\.claude\/commands\/loa-aleph(?:[.-][^/]*)?\.md$/.test(path);
}

function parseInstallLock(value: unknown): LoaInstallLock {
  if (!exactKeys(value, [
    'format',
    'digest_algorithm',
    'install_digest',
    'bundle',
    'core',
    'adapter',
    'checker_digest',
    'adapter_protocol_version',
    'run_format_version',
    'layout',
    'managed_tree_digest',
    'files',
  ])) throw new Error('install lock top-level keys are malformed');
  const lock = value as unknown as LoaInstallLock;
  if (lock.format !== INSTALL_LOCK_FORMAT
    || lock.digest_algorithm !== DIGEST_ALGORITHM) {
    throw new Error('install lock format or digest algorithm is invalid');
  }
  if (!exactKeys(lock.bundle, [
    'id', 'version', 'payload_digest', 'lock_digest', 'digest', 'lock_file_digest',
  ]) || !exactKeys(lock.core, ['id', 'version', 'tree_digest'])
    || !exactKeys(lock.adapter, ['id', 'version', 'lifecycle', 'tree_digest'])
    || !exactKeys(lock.layout, [
      'map_format', 'map_digest', 'runtime_root', 'record_path',
    ])) {
    throw new Error('install lock identity fields are malformed');
  }
  const digests = [
    lock.install_digest,
    lock.bundle.payload_digest,
    lock.bundle.lock_digest,
    lock.bundle.digest,
    lock.bundle.lock_file_digest,
    lock.core.tree_digest,
    lock.adapter.tree_digest,
    lock.checker_digest,
    lock.layout.map_digest,
    lock.managed_tree_digest,
  ];
  if (digests.some((digest) => typeof digest !== 'string'
    || !SHA256_PATTERN.test(digest))) {
    throw new Error('install lock contains a malformed digest');
  }
  if (lock.bundle.id !== BUNDLE_ID || lock.adapter.id !== ADAPTER_ID
    || lock.layout.map_format !== MAP_FORMAT
    || lock.layout.runtime_root !== RUNTIME_ROOT
    || lock.layout.record_path !== RECORD_PATH) {
    throw new Error('install lock identity or layout is invalid');
  }
  if (!Array.isArray(lock.files) || lock.files.length === 0) {
    throw new Error('install lock files must be a nonempty array');
  }
  const destinations: string[] = [];
  for (const [index, file] of lock.files.entries()) {
    if (!exactKeys(file, [
      'kind', 'classification', 'source_path', 'destination_path', 'digest',
    ])) throw new Error(`install lock files[${index}] is malformed`);
    if ((file.kind !== 'runtime' && file.kind !== 'exposure')
      || !['core', 'adapter', 'lock'].includes(file.classification)
      || !normalizedRepositoryPath(file.source_path)
      || !normalizedRepositoryPath(file.destination_path)
      || !SHA256_PATTERN.test(file.digest)) {
      throw new Error(`install lock files[${index}] has invalid values`);
    }
    if (file.kind === 'runtime'
      && file.destination_path !== `${RUNTIME_ROOT}/${file.source_path}`) {
      throw new Error(`runtime destination disagrees with source: ${file.source_path}`);
    }
    if (file.kind === 'exposure'
      && (!validManagedExposureDestination(file.destination_path)
        || file.classification !== 'adapter')) {
      throw new Error(`exposure destination is outside Loa-managed paths: ${file.destination_path}`);
    }
    destinations.push(file.destination_path);
  }
  if (new Set(destinations).size !== destinations.length) {
    throw new Error('install lock destinations must be unique');
  }
  if (canonicalJson(destinations)
    !== canonicalJson([...destinations].sort(utf8Compare))) {
    throw new Error('install lock files must be ordered by destination path');
  }
  return lock;
}

function assertInstallLockDigest(lock: LoaInstallLock, label: string): void {
  const resealed = resealLoaInstallLock(lock);
  if (resealed.managed_tree_digest !== lock.managed_tree_digest
    || resealed.install_digest !== lock.install_digest) {
    throw new Error(`${label} digest mismatch`);
  }
}

function transactionIdentityProjection(
  transaction: InstallationTransaction,
): Omit<InstallationTransaction, 'transaction_digest'> {
  return {
    format: transaction.format,
    mode: transaction.mode,
    previous: transaction.previous ? structuredClone(transaction.previous) : null,
    next: structuredClone(transaction.next),
  };
}

function resealInstallationTransaction(
  transaction: InstallationTransaction,
): InstallationTransaction {
  const sealed = structuredClone(transaction);
  sealed.transaction_digest = sha256Digest(
    canonicalJsonBytes(transactionIdentityProjection(sealed)),
  );
  return sealed;
}

function parseInstallationTransaction(value: unknown): InstallationTransaction {
  if (!exactKeys(value, [
    'format', 'transaction_digest', 'mode', 'previous', 'next',
  ])) {
    throw new Error('installation transaction keys are malformed');
  }
  const transaction = value as unknown as InstallationTransaction;
  if (transaction.format !== TRANSACTION_FORMAT
    || (transaction.mode !== 'fresh' && transaction.mode !== 'update')
    || !SHA256_PATTERN.test(transaction.transaction_digest)) {
    throw new Error('installation transaction identity is invalid');
  }
  transaction.next = parseInstallLock(transaction.next);
  assertInstallLockDigest(transaction.next, 'next installation transaction lock');
  if (transaction.previous === null) {
    if (transaction.mode !== 'fresh') {
      throw new Error('update transaction is missing its previous installation');
    }
  } else {
    transaction.previous = parseInstallLock(transaction.previous);
    assertInstallLockDigest(
      transaction.previous,
      'previous installation transaction lock',
    );
    if (transaction.mode !== 'update') {
      throw new Error('fresh transaction unexpectedly carries a previous installation');
    }
  }
  const resealed = resealInstallationTransaction(transaction);
  if (resealed.transaction_digest !== transaction.transaction_digest) {
    throw new Error('installation transaction digest mismatch');
  }
  return transaction;
}

function injectInstallationFault(
  options: LoaInstallationOptions,
  checkpoint: LoaInstallationCheckpoint,
): void {
  if (options.testFault?.after === checkpoint) {
    throw new InjectedInstallationFault(options.testFault.kind, checkpoint);
  }
}

function recursiveFilesStrict(root: string, prefix: string): string[] {
  if (!existsSync(root)) return [];
  const rootStat = lstatSync(root);
  if (rootStat.isSymbolicLink() || !rootStat.isDirectory()) {
    throw new Error(`managed root is not a real directory: ${prefix}`);
  }
  const files: string[] = [];
  function visit(directory: string, relativePrefix: string): void {
    for (const entry of readdirSync(directory, { withFileTypes: true })
      .sort((left, right) => utf8Compare(left.name, right.name))) {
      const relativePath = relativePrefix
        ? `${relativePrefix}/${entry.name}`
        : entry.name;
      const absolute = join(directory, entry.name);
      const stat = lstatSync(absolute);
      if (stat.isSymbolicLink()) {
        throw new Error(`managed tree contains a symlink: ${prefix}/${relativePath}`);
      }
      if (stat.isDirectory()) visit(absolute, relativePath);
      else if (stat.isFile()) files.push(`${prefix}/${relativePath}`);
      else throw new Error(`managed tree contains a non-file: ${prefix}/${relativePath}`);
    }
  }
  visit(root, '');
  return files.sort(utf8Compare);
}

function managedDiskInventory(targetRoot: string): string[] {
  const root = resolve(targetRoot);
  const paths = [
    ...recursiveFilesStrict(join(root, '.claude/aleph'), '.claude/aleph'),
    ...recursiveFilesStrict(
      join(root, '.claude/skills/loa-aleph'),
      '.claude/skills/loa-aleph',
    ),
  ];
  const commandsRoot = join(root, '.claude/commands');
  if (existsSync(commandsRoot)) {
    const stat = lstatSync(commandsRoot);
    if (stat.isSymbolicLink() || !stat.isDirectory()) {
      throw new Error('.claude/commands is not a real directory');
    }
    for (const entry of readdirSync(commandsRoot, { withFileTypes: true })) {
      if (!entry.name.startsWith('loa-aleph')) continue;
      const path = `.claude/commands/${entry.name}`;
      const entryStat = lstatSync(join(commandsRoot, entry.name));
      if (entryStat.isSymbolicLink() || !entryStat.isFile()) {
        throw new Error(`managed command path is not a regular file: ${path}`);
      }
      paths.push(path);
    }
  }
  return sortedUnique(paths);
}

function installationSummary(lock: LoaInstallLock): LoaInstallationSummary {
  return {
    bundleId: lock.bundle.id,
    bundleDigest: lock.bundle.digest,
    coreDigest: lock.core.tree_digest,
    adapterDigest: lock.adapter.tree_digest,
    checkerDigest: lock.checker_digest,
    installDigest: lock.install_digest,
    managedTreeDigest: lock.managed_tree_digest,
    managedFileCount: lock.files.length,
  };
}

function verifyLoaInstallationImage(
  targetRoot: string,
  allowActiveTransaction: boolean,
): LoaInstallationReport {
  const target = resolve(targetRoot);
  const errors: string[] = [];
  let lock: LoaInstallLock | undefined;
  try {
    const transaction = assertSafeTargetPath(target, TRANSACTION_PATH);
    if (!allowActiveTransaction && existsSync(transaction)) {
      throw new Error('Loa installation has an active recovery transaction');
    }
    const record = assertSafeTargetPath(target, RECORD_PATH);
    if (!existsSync(record) || !lstatSync(record).isFile()) {
      throw new Error('Loa installation record is missing');
    }
    const raw = readFileNoFollow(record);
    const value = JSON.parse(raw.toString('utf8')) as unknown;
    if (!raw.equals(canonicalJsonBytes(value))) {
      throw new Error('Loa installation record is not canonical JSON plus one LF');
    }
    lock = parseInstallLock(value);
    const resealed = resealLoaInstallLock(lock);
    if (resealed.managed_tree_digest !== lock.managed_tree_digest
      || resealed.install_digest !== lock.install_digest) {
      throw new Error('Loa installation record digest mismatch');
    }

    const runtime = assertSafeTargetPath(target, RUNTIME_ROOT);
    const bundleLock = readVerifiedBundleLock(runtime);
    const installationMap = readInstallationMap(runtime, false);
    const rawBundleLock = readFileNoFollow(join(runtime, 'bundle.lock.json'));
    const expectedIdentity = {
      bundle: {
        id: bundleLock.bundle.id,
        version: bundleLock.bundle.version,
        payload_digest: bundleLock.bundle.payload_digest,
        lock_digest: bundleLock.lock_digest,
        digest: bundleLock.bundle.digest,
        lock_file_digest: sha256Digest(rawBundleLock),
      },
      core: bundleLock.core,
      adapter: bundleLock.adapter,
      checker_digest: bundleLock.checker_digest,
      adapter_protocol_version: bundleLock.adapter_protocol_version,
      run_format_version: bundleLock.run_format_version,
    };
    const actualIdentity = {
      bundle: lock.bundle,
      core: lock.core,
      adapter: lock.adapter,
      checker_digest: lock.checker_digest,
      adapter_protocol_version: lock.adapter_protocol_version,
      run_format_version: lock.run_format_version,
    };
    if (canonicalJson(actualIdentity) !== canonicalJson(expectedIdentity)) {
      throw new Error('installed bundle identity disagrees with installation record');
    }
    const fileByPath = new Map(bundleLock.files.map((file) => [file.path, file]));
    const mapRecord = fileByPath.get(INSTALL_MAP_PATH);
    if (!mapRecord || mapRecord.digest !== lock.layout.map_digest) {
      throw new Error('installed mapping digest disagrees with installation record');
    }
    const expectedRuntime: LoaManagedInstallFile[] = bundleLock.files.map((file) => ({
      kind: 'runtime',
      classification: file.classification,
      source_path: file.path,
      destination_path: `${RUNTIME_ROOT}/${file.path}`,
      digest: file.digest,
    }));
    expectedRuntime.push({
      kind: 'runtime',
      classification: 'lock',
      source_path: 'bundle.lock.json',
      destination_path: `${RUNTIME_ROOT}/bundle.lock.json`,
      digest: sha256Digest(rawBundleLock),
    });
    const actualRuntime = lock.files.filter((file) => file.kind === 'runtime');
    const sortFiles = (files: LoaManagedInstallFile[]): LoaManagedInstallFile[] => (
      [...files].sort((left, right) => utf8Compare(
        left.destination_path,
        right.destination_path,
      ))
    );
    if (canonicalJson(sortFiles(actualRuntime))
      !== canonicalJson(sortFiles(expectedRuntime))) {
      throw new Error('installation record does not cover the exact bundle runtime');
    }
    const expectedExposures: LoaManagedInstallFile[] = installationMap.exposures.map(
      (exposure) => {
        const source = fileByPath.get(exposure.source);
        if (!source || source.classification !== 'adapter') {
          throw new Error(`mapped exposure is not adapter-owned: ${exposure.source}`);
        }
        return {
          kind: 'exposure',
          classification: 'adapter',
          source_path: exposure.source,
          destination_path: exposure.destination,
          digest: source.digest,
        };
      },
    );
    const actualExposures = lock.files.filter((file) => file.kind === 'exposure');
    if (canonicalJson(sortFiles(actualExposures))
      !== canonicalJson(sortFiles(expectedExposures))) {
      throw new Error('installation record exposures disagree with the verified installation map');
    }
    for (const file of lock.files) {
      if (file.kind === 'exposure') {
        const source = fileByPath.get(file.source_path);
        if (!source || source.classification !== 'adapter'
          || source.digest !== file.digest) {
          throw new Error(`exposure does not match adapter runtime: ${file.destination_path}`);
        }
      }
      const destination = assertSafeTargetPath(target, file.destination_path);
      if (!existsSync(destination) || !lstatSync(destination).isFile()) {
        throw new Error(`managed installation file is missing: ${file.destination_path}`);
      }
      if (sha256Digest(readFileNoFollow(destination)) !== file.digest) {
        throw new Error(`managed installation file was modified: ${file.destination_path}`);
      }
    }
    const expectedDisk = sortedUnique([
      ...lock.files.map((file) => file.destination_path),
      RECORD_PATH,
    ]);
    const actualDisk = managedDiskInventory(target);
    if (!sameStrings(expectedDisk, actualDisk)) {
      const missing = expectedDisk.filter((path) => !actualDisk.includes(path));
      const extra = actualDisk.filter((path) => !expectedDisk.includes(path));
      throw new Error(
        `managed installation inventory mismatch; missing=${missing.join(',')}; `
        + `extra=${extra.join(',')}`,
      );
    }
  } catch (error) {
    errors.push(error instanceof Error ? error.message : String(error));
  }
  return {
    result: errors.length ? 'FAIL' : 'PASS',
    targetRoot: target,
    errors: sortedUnique(errors),
    ...(lock && errors.length === 0 ? { summary: installationSummary(lock) } : {}),
  };
}

export function verifyLoaInstallation(targetRoot: string): LoaInstallationReport {
  return verifyLoaInstallationImage(targetRoot, false);
}

function assertFreshDestinations(targetRoot: string, lock: LoaInstallLock): void {
  const conflicts = lock.files
    .map((file) => file.destination_path)
    .filter((path) => existsSync(assertSafeTargetPath(targetRoot, path)));
  if (existsSync(assertSafeTargetPath(targetRoot, RECORD_PATH))) conflicts.push(RECORD_PATH);
  if (conflicts.length > 0) {
    throw new Error(`fresh installation would overwrite unmanaged paths: ${
      sortedUnique(conflicts).join(', ')
    }`);
  }
  for (const dedicatedRoot of ['.claude/aleph', '.claude/skills/loa-aleph']) {
    const root = assertSafeTargetPath(targetRoot, dedicatedRoot);
    if (existsSync(root) && recursiveFilesStrict(root, dedicatedRoot).length > 0) {
      throw new Error(`fresh installation found unmanaged content under ${dedicatedRoot}`);
    }
  }
}

function assertNewDestinationsAreFree(
  targetRoot: string,
  previous: LoaInstallLock,
  next: LoaInstallLock,
): void {
  const previousPaths = new Set(
    previous.files.map((file) => file.destination_path),
  );
  const conflicts = next.files
    .map((file) => file.destination_path)
    .filter((path) => (
      !previousPaths.has(path)
      && existsSync(assertSafeTargetPath(targetRoot, path))
    ));
  if (conflicts.length > 0) {
    throw new Error(`adapter update would overwrite unmanaged paths: ${
      sortedUnique(conflicts).join(', ')
    }`);
  }
}

function writePlanFiles(targetRoot: string, plan: InstallationPlan): void {
  for (const file of plan.lock.files) {
    const bytes = readFileNoFollow(join(plan.snapshotRoot, file.source_path));
    if (sha256Digest(bytes) !== file.digest) {
      throw new Error(`verified snapshot changed before installation: ${file.source_path}`);
    }
    atomicWrite(targetRoot, file.destination_path, bytes);
  }
}

export function removeStaleManagedFiles(
  targetRoot: string,
  previous: LoaInstallLock,
  next: LoaInstallLock,
): void {
  const nextPaths = new Set(next.files.map((file) => file.destination_path));
  const stale = previous.files
    .filter((file) => !nextPaths.has(file.destination_path))
    .sort((left, right) => utf8Compare(right.destination_path, left.destination_path));
  for (const file of stale) {
    const destination = assertSafeTargetPath(targetRoot, file.destination_path);
    if (!existsSync(destination)) {
      throw new Error(`stale managed file disappeared during update: ${file.destination_path}`);
    }
    if (sha256Digest(readFileNoFollow(destination)) !== file.digest) {
      throw new Error(`stale managed file changed during update: ${file.destination_path}`);
    }
    rmSync(destination);
  }
}

function readCurrentInstallLock(targetRoot: string): LoaInstallLock | undefined {
  const record = assertSafeTargetPath(targetRoot, RECORD_PATH);
  if (!existsSync(record)) return undefined;
  const lock = parseInstallLock(JSON.parse(readFileSync(record, 'utf8')) as unknown);
  assertInstallLockDigest(lock, 'current installation record');
  return lock;
}

function removeDirectoryIfPresent(
  targetRoot: string,
  path: string,
  guard?: InstallationParentGuard,
): void {
  if (guard) assertInstallationParents(guard, `before removing ${path}`);
  const absolute = assertSafeTargetPath(targetRoot, path);
  if (!existsSync(absolute)) return;
  const stat = lstatSync(absolute);
  if (stat.isSymbolicLink() || !stat.isDirectory()) {
    throw new Error(`installation transaction path is unsafe: ${path}`);
  }
  if (guard) assertInstallationParents(guard, `before deleting ${path}`);
  rmSync(absolute, { recursive: true });
  if (guard) assertInstallationParents(guard, `after deleting ${path}`);
}

function commitTransactionRemoval(
  targetRoot: string,
  guard: InstallationParentGuard,
): void {
  assertInstallationParents(guard, 'before transaction cleanup');
  const transaction = assertSafeTargetPath(targetRoot, TRANSACTION_PATH);
  const cleanup = assertSafeTargetPath(targetRoot, TRANSACTION_CLEANUP_PATH);
  removeDirectoryIfPresent(targetRoot, TRANSACTION_CLEANUP_PATH, guard);
  if (!existsSync(transaction)) return;
  assertInstallationParents(guard, 'before transaction cleanup rename');
  renameSync(transaction, cleanup);
  assertInstallationParents(guard, 'after transaction cleanup rename');
  removeDirectoryIfPresent(targetRoot, TRANSACTION_CLEANUP_PATH, guard);
}

function removeManagedImage(
  targetRoot: string,
  guard: InstallationParentGuard,
): void {
  assertInstallationParents(guard, 'before removing managed image');
  const command = assertSafeTargetPath(targetRoot, COMMAND_PATH);
  if (existsSync(command)) {
    const stat = lstatSync(command);
    if (stat.isSymbolicLink() || !stat.isFile()) {
      throw new Error('managed command is not a regular file');
    }
    assertInstallationParents(guard, 'before removing managed command');
    rmSync(command);
    assertInstallationParents(guard, 'after removing managed command');
  }
  for (const path of [SKILL_ROOT, ALEPH_ROOT]) {
    const absolute = assertSafeTargetPath(targetRoot, path);
    if (!existsSync(absolute)) continue;
    const stat = lstatSync(absolute);
    if (stat.isSymbolicLink() || !stat.isDirectory()) {
      throw new Error(`managed installation root is unsafe: ${path}`);
    }
    assertInstallationParents(guard, `before removing ${path}`);
    rmSync(absolute, { recursive: true });
    assertInstallationParents(guard, `after removing ${path}`);
  }
}

function transactionImagePath(
  imageRoot: string,
  destinationPath: string,
): string {
  if (destinationPath === COMMAND_PATH) return join(imageRoot, 'command');
  if (destinationPath === ALEPH_ROOT || destinationPath.startsWith(`${ALEPH_ROOT}/`)) {
    return join(imageRoot, 'aleph', destinationPath.slice(ALEPH_ROOT.length + 1));
  }
  if (destinationPath === SKILL_ROOT || destinationPath.startsWith(`${SKILL_ROOT}/`)) {
    return join(imageRoot, 'skill', destinationPath.slice(SKILL_ROOT.length + 1));
  }
  throw new Error(`installation image cannot represent ${destinationPath}`);
}

function copyInstallationImage(sourceTarget: string, imageRoot: string): void {
  copyTreeSnapshot(
    assertSafeTargetPath(sourceTarget, ALEPH_ROOT),
    join(imageRoot, 'aleph'),
  );
  copyTreeSnapshot(
    assertSafeTargetPath(sourceTarget, SKILL_ROOT),
    join(imageRoot, 'skill'),
  );
  const command = assertSafeTargetPath(sourceTarget, COMMAND_PATH);
  writeFileSync(join(imageRoot, 'command'), readFileNoFollow(command), { flag: 'wx' });
}

function transactionImageInventory(imageRoot: string): string[] {
  const files = [
    ...recursiveFilesStrict(join(imageRoot, 'aleph'), ALEPH_ROOT),
    ...recursiveFilesStrict(join(imageRoot, 'skill'), SKILL_ROOT),
  ];
  const command = join(imageRoot, 'command');
  if (existsSync(command)) {
    const stat = lstatSync(command);
    if (stat.isSymbolicLink() || !stat.isFile()) {
      throw new Error('installation transaction command is not a regular file');
    }
    files.push(COMMAND_PATH);
  }
  return sortedUnique(files);
}

function verifyTransactionImage(imageRoot: string, lock: LoaInstallLock): void {
  const expected = sortedUnique([
    ...lock.files.map((file) => file.destination_path),
    RECORD_PATH,
  ]);
  const actual = transactionImageInventory(imageRoot);
  if (!sameStrings(expected, actual)) {
    throw new Error('installation transaction image inventory mismatch');
  }
  for (const file of lock.files) {
    const path = transactionImagePath(imageRoot, file.destination_path);
    if (sha256Digest(readFileNoFollow(path)) !== file.digest) {
      throw new Error(`installation transaction image changed: ${file.destination_path}`);
    }
  }
  const record = transactionImagePath(imageRoot, RECORD_PATH);
  if (!readFileNoFollow(record).equals(canonicalJsonBytes(lock))) {
    throw new Error('installation transaction receipt image changed');
  }
}

function prepareInstallationTransaction(
  targetRoot: string,
  stagedTarget: string,
  previous: LoaInstallLock | undefined,
  next: LoaInstallLock,
  guard: InstallationParentGuard,
): string {
  const preparing = assertSafeTargetPath(targetRoot, TRANSACTION_PREPARING_PATH);
  const transactionRoot = assertSafeTargetPath(targetRoot, TRANSACTION_PATH);
  if (existsSync(preparing) || existsSync(transactionRoot)) {
    throw new Error('installation transaction path already exists');
  }
  assertInstallationParents(guard, 'before preparing installation transaction');
  ensureSafeParents(targetRoot, TRANSACTION_PREPARING_PATH);
  assertInstallationParents(guard, 'after transaction parent creation');
  mkdirSync(preparing);
  assertInstallationParents(guard, 'after transaction preparing directory creation');
  try {
    const transaction = resealInstallationTransaction({
      format: TRANSACTION_FORMAT,
      transaction_digest: sha256Digest(''),
      mode: previous ? 'update' : 'fresh',
      previous: previous ? structuredClone(previous) : null,
      next: structuredClone(next),
    });
    copyInstallationImage(stagedTarget, join(preparing, 'next'));
    verifyTransactionImage(join(preparing, 'next'), next);
    if (previous) {
      copyInstallationImage(targetRoot, join(preparing, 'backup'));
      verifyTransactionImage(join(preparing, 'backup'), previous);
    }
    writeFileSync(
      join(preparing, TRANSACTION_RECORD),
      canonicalJsonBytes(transaction),
      { flag: 'wx' },
    );
    assertInstallationParents(guard, 'before publishing installation transaction');
    renameSync(preparing, transactionRoot);
    assertInstallationParents(guard, 'after publishing installation transaction');
    return transactionRoot;
  } catch (error) {
    try {
      assertInstallationParents(guard, 'before failed transaction cleanup');
      rmSync(preparing, { recursive: true, force: true });
      assertInstallationParents(guard, 'after failed transaction cleanup');
    } catch {
      // Leave the preparing image for the next locked recovery.
    }
    throw error;
  }
}

function readInstallationTransaction(transactionRoot: string): InstallationTransaction {
  const record = join(transactionRoot, TRANSACTION_RECORD);
  const raw = readFileNoFollow(record);
  const value = JSON.parse(raw.toString('utf8')) as unknown;
  if (!raw.equals(canonicalJsonBytes(value))) {
    throw new Error('installation transaction is not canonical JSON plus one LF');
  }
  return parseInstallationTransaction(value);
}

function restoreTransactionImage(
  targetRoot: string,
  imageRoot: string,
  lock: LoaInstallLock,
  guard: InstallationParentGuard,
): void {
  assertInstallationParents(guard, 'before restoring transaction image');
  verifyTransactionImage(imageRoot, lock);
  removeManagedImage(targetRoot, guard);
  ensureSafeParents(targetRoot, `${ALEPH_ROOT}/placeholder`);
  assertInstallationParents(guard, 'after restored runtime parent creation');
  copyTreeSnapshot(
    join(imageRoot, 'aleph'),
    assertSafeTargetPath(targetRoot, ALEPH_ROOT),
  );
  assertInstallationParents(guard, 'after restoring runtime image');
  ensureSafeParents(targetRoot, `${SKILL_ROOT}/placeholder`);
  assertInstallationParents(guard, 'after restored skill parent creation');
  copyTreeSnapshot(
    join(imageRoot, 'skill'),
    assertSafeTargetPath(targetRoot, SKILL_ROOT),
  );
  assertInstallationParents(guard, 'after restoring skill image');
  atomicWrite(
    targetRoot,
    COMMAND_PATH,
    readFileNoFollow(join(imageRoot, 'command')),
    guard,
  );
}

function recoverInterruptedInstallation(
  targetRoot: string,
  guard: InstallationParentGuard,
): boolean {
  assertInstallationParents(guard, 'before interrupted-installation recovery');
  removeDirectoryIfPresent(targetRoot, TRANSACTION_PREPARING_PATH, guard);
  removeDirectoryIfPresent(targetRoot, TRANSACTION_CLEANUP_PATH, guard);
  const transactionRoot = assertSafeTargetPath(targetRoot, TRANSACTION_PATH);
  if (!existsSync(transactionRoot)) return false;
  const stat = lstatSync(transactionRoot);
  if (stat.isSymbolicLink() || !stat.isDirectory()) {
    throw new Error('active installation transaction is not a real directory');
  }
  const transaction = readInstallationTransaction(transactionRoot);
  if (transaction.previous) {
    restoreTransactionImage(
      targetRoot,
      join(transactionRoot, 'backup'),
      transaction.previous,
      guard,
    );
    assertInstallationParents(guard, 'before recovered-image verification');
    const restored = verifyLoaInstallationImage(targetRoot, true);
    assertInstallationParents(guard, 'after recovered-image verification');
    if (restored.result !== 'PASS') {
      throw new Error(`recovered installation failed verification: ${
        restored.errors.join('; ')
      }`);
    }
  } else {
    removeManagedImage(targetRoot, guard);
  }
  commitTransactionRemoval(targetRoot, guard);
  return true;
}

function publishTransactionImage(
  targetRoot: string,
  transactionRoot: string,
  options: LoaInstallationOptions,
  guard: InstallationParentGuard,
): void {
  assertInstallationParents(guard, 'before publishing transaction image');
  const transaction = readInstallationTransaction(transactionRoot);
  const nextRoot = join(transactionRoot, 'next');
  verifyTransactionImage(nextRoot, transaction.next);
  injectInstallationFault(options, 'after-transaction-prepared');

  const command = assertSafeTargetPath(targetRoot, COMMAND_PATH);
  if (existsSync(command)) {
    const stat = lstatSync(command);
    if (stat.isSymbolicLink() || !stat.isFile()) {
      throw new Error('managed command is not a regular file');
    }
    assertInstallationParents(guard, 'before unpublishing command');
    rmSync(command);
    assertInstallationParents(guard, 'after unpublishing command');
  }
  injectInstallationFault(options, 'after-command-unpublished');

  const activeAleph = assertSafeTargetPath(targetRoot, ALEPH_ROOT);
  if (existsSync(activeAleph)) {
    const stat = lstatSync(activeAleph);
    if (stat.isSymbolicLink() || !stat.isDirectory()) {
      throw new Error('managed Aleph runtime root is unsafe');
    }
    assertInstallationParents(guard, 'before replacing runtime image');
    rmSync(activeAleph, { recursive: true });
    assertInstallationParents(guard, 'after removing runtime image');
  }
  ensureSafeParents(targetRoot, `${ALEPH_ROOT}/placeholder`);
  assertInstallationParents(guard, 'before publishing runtime image');
  renameSync(join(nextRoot, 'aleph'), activeAleph);
  assertInstallationParents(guard, 'after publishing runtime image');
  injectInstallationFault(options, 'after-runtime-published');

  const activeSkill = assertSafeTargetPath(targetRoot, SKILL_ROOT);
  if (existsSync(activeSkill)) {
    const stat = lstatSync(activeSkill);
    if (stat.isSymbolicLink() || !stat.isDirectory()) {
      throw new Error('managed Loa skill root is unsafe');
    }
    assertInstallationParents(guard, 'before replacing skill image');
    rmSync(activeSkill, { recursive: true });
    assertInstallationParents(guard, 'after removing skill image');
  }
  ensureSafeParents(targetRoot, `${SKILL_ROOT}/placeholder`);
  assertInstallationParents(guard, 'before publishing skill image');
  renameSync(join(nextRoot, 'skill'), activeSkill);
  assertInstallationParents(guard, 'after publishing skill image');
  injectInstallationFault(options, 'after-skill-published');

  atomicWrite(
    targetRoot,
    COMMAND_PATH,
    readFileNoFollow(join(nextRoot, 'command')),
    guard,
  );
  injectInstallationFault(options, 'after-command-published');
}

export function installLoaBundle(
  bundleRoot: string,
  targetRoot: string,
  options: LoaInstallationOptions = {},
): LoaInstallationReport {
  const source = resolve(bundleRoot);
  const target = resolve(targetRoot);
  const errors: string[] = [];
  let summary: LoaInstallationSummary | undefined;
  let temporary = '';
  let transactionPrepared = false;
  let ownership: InstallationWriterOwnership | undefined;
  try {
    if (pathInside(source, target) || pathInside(target, source)) {
      throw new Error('bundle and target directories may not overlap');
    }
    ownership = acquireInstallationWriter(target);
    const guard = ownership.guard;
    recoverInterruptedInstallation(target, guard);
    temporary = mkdtempSync(join(tmpdir(), 'aleph-loa-install-'));
    const snapshotRoot = join(temporary, 'source-bundle');
    copyTreeSnapshot(source, snapshotRoot);
    const plan = buildInstallationPlan(snapshotRoot);

    let previous: LoaInstallLock | undefined;
    assertInstallationParents(guard, 'before reading current installation');
    const record = assertSafeTargetPath(target, RECORD_PATH);
    if (existsSync(record)) {
      const existing = verifyLoaInstallation(target);
      assertInstallationParents(guard, 'after current-installation verification');
      if (existing.result !== 'PASS') {
        throw new Error(`existing Loa installation is not safe to update: ${
          existing.errors.join('; ')
        }`);
      }
      previous = readCurrentInstallLock(target);
      if (!previous) throw new Error('verified installation record disappeared');
      assertNewDestinationsAreFree(target, previous, plan.lock);
    } else {
      assertFreshDestinations(target, plan.lock);
    }

    const stagedTarget = join(temporary, 'staged-target');
    writePlanFiles(stagedTarget, plan);
    atomicWrite(stagedTarget, RECORD_PATH, canonicalJsonBytes(plan.lock));
    const stagedVerification = verifyLoaInstallation(stagedTarget);
    if (stagedVerification.result !== 'PASS') {
      throw new Error(`staged installation verification failed: ${
        stagedVerification.errors.join('; ')
      }`);
    }

    assertInstallationParents(guard, 'before transaction preparation');
    if (previous) {
      const unchanged = verifyLoaInstallation(target);
      assertInstallationParents(guard, 'after unchanged-image verification');
      if (unchanged.result !== 'PASS') {
        throw new Error('existing installation changed during update');
      }
    }
    const transactionRoot = prepareInstallationTransaction(
      target,
      stagedTarget,
      previous,
      plan.lock,
      guard,
    );
    transactionPrepared = true;
    publishTransactionImage(target, transactionRoot, options, guard);
    assertInstallationParents(guard, 'before committed-image verification');
    const committedImage = verifyLoaInstallationImage(target, true);
    assertInstallationParents(guard, 'after committed-image verification');
    if (committedImage.result !== 'PASS') {
      throw new Error(`published installation image failed verification: ${
        committedImage.errors.join('; ')
      }`);
    }
    commitTransactionRemoval(target, guard);
    transactionPrepared = false;
    const final = verifyLoaInstallation(target);
    assertInstallationParents(guard, 'after final installation verification');
    if (final.result !== 'PASS' || !final.summary) {
      throw new Error(`installed runtime failed final verification: ${
        final.errors.join('; ')
      }`);
    }
    summary = final.summary;
  } catch (error) {
    if (transactionPrepared
      && ownership
      && !(error instanceof InjectedInstallationFault && error.kind === 'interruption')) {
      try {
        recoverInterruptedInstallation(target, ownership.guard);
      } catch (recoveryError) {
        errors.push(`installation rollback failed: ${
          recoveryError instanceof Error ? recoveryError.message : String(recoveryError)
        }`);
      }
    }
    errors.push(error instanceof Error ? error.message : String(error));
  } finally {
    if (temporary) {
      try {
        rmSync(temporary, { recursive: true, force: true });
      } catch (error) {
        errors.push(`installation temporary cleanup failed: ${
          error instanceof Error ? error.message : String(error)
        }`);
      }
    }
    if (ownership) {
      try {
        ownership.release();
      } catch (error) {
        errors.push(`installation writer release failed: ${
          error instanceof Error ? error.message : String(error)
        }`);
      }
      try {
        closeInstallationParentGuard(ownership.guard);
      } catch (error) {
        errors.push(`installation parent guard close failed: ${
          error instanceof Error ? error.message : String(error)
        }`);
      }
    }
  }
  return {
    result: errors.length ? 'FAIL' : 'PASS',
    targetRoot: target,
    errors: sortedUnique(errors),
    ...(summary && errors.length === 0 ? { summary } : {}),
  };
}

interface CliOptions {
  command: 'install' | 'verify-install' | '';
  bundle: string;
  target: string;
  json: boolean;
  help: boolean;
  error: string;
}

function parseCli(args: string[]): CliOptions {
  const options: CliOptions = {
    command: '',
    bundle: '',
    target: '',
    json: false,
    help: false,
    error: '',
  };
  const [command, ...rest] = args;
  if (command === 'install' || command === 'verify-install') options.command = command;
  else if (command === '--help' || command === '-h' || command === undefined) {
    options.help = true;
  } else options.error = `unknown command "${command}"`;
  for (let index = 0; index < rest.length; index += 1) {
    const arg = rest[index];
    if (arg === '--json') options.json = true;
    else if (arg === '--help' || arg === '-h') options.help = true;
    else if (arg === '--bundle' || arg === '--target') {
      const value = rest[index + 1];
      if (!value) options.error = `${arg} requires a directory`;
      else {
        if (arg === '--bundle') options.bundle = resolve(value);
        else options.target = resolve(value);
        index += 1;
      }
    } else options.error = `unknown argument "${arg}"`;
  }
  if (options.command === 'install' && !options.bundle) {
    options.error = 'install requires --bundle';
  }
  if (options.command && !options.target) options.error = `${options.command} requires --target`;
  return options;
}

export function main(args = process.argv.slice(2)): number {
  const options = parseCli(args);
  if (options.help) {
    console.log(
      'Usage:\n'
      + '  node adapters/loa/src/installer.ts install '
      + '--bundle <aleph-for-loa> --target <loa-root> [--json]\n'
      + '  node adapters/loa/src/installer.ts verify-install '
      + '--target <loa-root> [--json]',
    );
    return 0;
  }
  if (options.error || !options.command) {
    console.error(options.error || 'install or verify-install command is required');
    return 2;
  }
  const report = options.command === 'install'
    ? installLoaBundle(options.bundle, options.target)
    : verifyLoaInstallation(options.target);
  if (options.json) console.log(JSON.stringify(report, null, 2));
  else {
    if (report.summary) {
      console.log(`INSTALL ${report.summary.bundleId} ${report.targetRoot}`);
      console.log(`DIGEST core ${report.summary.coreDigest}`);
      console.log(`DIGEST adapter:${ADAPTER_ID} ${report.summary.adapterDigest}`);
      console.log(`DIGEST checker ${report.summary.checkerDigest}`);
      console.log(`DIGEST bundle ${report.summary.bundleDigest}`);
      console.log(`DIGEST installation ${report.summary.installDigest}`);
    }
    for (const error of report.errors) console.error(`FAIL ${error}`);
    console.log(`RESULT: ${report.result}`);
  }
  return report.result === 'PASS' ? 0 : 1;
}

if (resolve(process.argv[1] || '') === SCRIPT_PATH) process.exit(main());
