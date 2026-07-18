import { createHash } from 'node:crypto';
import {
  chmodSync,
  closeSync,
  constants,
  existsSync,
  fchmodSync,
  fstatSync,
  fsyncSync,
  lstatSync,
  mkdirSync,
  openSync,
  readFileSync,
  readdirSync,
  renameSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import type { BigIntStats } from 'node:fs';
import {
  basename,
  dirname,
  isAbsolute,
  join,
  relative,
  resolve,
  sep,
} from 'node:path';
import type { JsonValue } from './types.ts';

const SHA256_PATTERN = /^sha256:[0-9a-f]{64}$/;
let temporaryCounter = 0;

export interface StableFileRead {
  bytes: Buffer;
  identity: {
    device: string;
    inode: string;
    size: string;
    modified_ns: string;
    mode: string;
  };
}

export interface FileTreeRecord {
  path: string;
  digest: string;
  byte_length: string;
}

function unpairedSurrogate(value: string): boolean {
  for (let index = 0; index < value.length; index++) {
    const code = value.charCodeAt(index);
    if (code >= 0xd800 && code <= 0xdbff) {
      const next = value.charCodeAt(index + 1);
      if (next < 0xdc00 || next > 0xdfff) return true;
      index += 1;
    } else if (code >= 0xdc00 && code <= 0xdfff) {
      return true;
    }
  }
  return false;
}

export function utf8Compare(left: string, right: string): number {
  return Buffer.compare(Buffer.from(left, 'utf8'), Buffer.from(right, 'utf8'));
}

export function sha256Digest(bytes: string | Buffer): string {
  return `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
}

export function stableJson(value: JsonValue | unknown): string {
  function serialize(item: unknown, path: string): string {
    if (item === null) return 'null';
    if (typeof item === 'boolean') return item ? 'true' : 'false';
    if (typeof item === 'number') {
      if (!Number.isFinite(item) || Object.is(item, -0)) {
        throw new Error(`${path} contains a noncanonical number`);
      }
      return JSON.stringify(item);
    }
    if (typeof item === 'string') {
      if (unpairedSurrogate(item)) {
        throw new Error(`${path} contains an unpaired UTF-16 surrogate`);
      }
      return JSON.stringify(item);
    }
    if (Array.isArray(item)) {
      return `[${item.map((entry, index) => serialize(entry, `${path}[${index}]`)).join(',')}]`;
    }
    if (typeof item === 'object' && item !== null) {
      const record = item as Record<string, unknown>;
      const keys = Object.keys(record).sort(utf8Compare);
      for (const key of keys) {
        if (unpairedSurrogate(key)) {
          throw new Error(`${path} has a key with an unpaired UTF-16 surrogate`);
        }
        if (record[key] === undefined) {
          throw new Error(`${path}.${key} is undefined`);
        }
      }
      return `{${keys.map((key) => (
        `${JSON.stringify(key)}:${serialize(record[key], `${path}.${key}`)}`
      )).join(',')}}`;
    }
    throw new Error(`${path} contains unsupported JSON type ${typeof item}`);
  }
  return serialize(value, '$');
}

export function stableJsonBytes(value: JsonValue | unknown): Buffer {
  return Buffer.from(`${stableJson(value)}\n`, 'utf8');
}

export function assertSafeRelativePath(path: string, label = 'path'): void {
  if (!path || isAbsolute(path) || path.includes('\\') || path.includes('\0')) {
    throw new Error(`${label} must be a nonempty normalized relative path`);
  }
  const parts = path.split('/');
  if (parts.some((part) => !part || part === '.' || part === '..')) {
    throw new Error(`${label} must not contain empty, dot, or parent segments`);
  }
  if (parts.some((part) => /[\u0000-\u001f\u007f]/u.test(part))) {
    throw new Error(`${label} contains a control character`);
  }
}

export function pathIsWithin(parent: string, child: string): boolean {
  const rel = relative(resolve(parent), resolve(child));
  return rel === '' || (!rel.startsWith(`..${sep}`) && rel !== '..' && !isAbsolute(rel));
}

export function assertPathWithin(parent: string, child: string, label = 'path'): void {
  if (!pathIsWithin(parent, child)) {
    throw new Error(`${label} escapes ${resolve(parent)}`);
  }
}

export function assertNoSymlinkComponents(root: string, target: string): void {
  const parent = resolve(root);
  const child = resolve(target);
  assertPathWithin(parent, child, 'target');
  if (!existsSync(parent)) throw new Error(`root does not exist: ${parent}`);
  if (lstatSync(parent).isSymbolicLink()) throw new Error(`root is a symlink: ${parent}`);
  const rel = relative(parent, child);
  let cursor = parent;
  if (!rel) return;
  for (const part of rel.split(sep)) {
    cursor = join(cursor, part);
    if (!existsSync(cursor)) continue;
    if (lstatSync(cursor).isSymbolicLink()) {
      throw new Error(`path contains a symlink: ${cursor}`);
    }
  }
}

function sameIdentity(
  left: BigIntStats,
  right: BigIntStats,
): boolean {
  return left.dev === right.dev
    && left.ino === right.ino
    && left.size === right.size
    && left.mtimeNs === right.mtimeNs
    && left.mode === right.mode;
}

export function readStableRegularFile(path: string): StableFileRead {
  const before = lstatSync(path, { bigint: true });
  if (before.isSymbolicLink() || !before.isFile()) {
    throw new Error(`input is not a regular non-symlink file: ${path}`);
  }
  const noFollow = typeof constants.O_NOFOLLOW === 'number' ? constants.O_NOFOLLOW : 0;
  const descriptor = openSync(path, constants.O_RDONLY | noFollow);
  try {
    const openedBefore = fstatSync(descriptor, { bigint: true });
    if (!sameIdentity(before, openedBefore)) {
      throw new Error(`input changed while it was opened: ${path}`);
    }
    const bytes = readFileSync(descriptor);
    const openedAfter = fstatSync(descriptor, { bigint: true });
    const after = lstatSync(path, { bigint: true });
    if (!sameIdentity(openedBefore, openedAfter) || !sameIdentity(openedAfter, after)) {
      throw new Error(`input changed while it was read: ${path}`);
    }
    if (BigInt(bytes.byteLength) !== after.size) {
      throw new Error(`input byte count changed while it was read: ${path}`);
    }
    return {
      bytes,
      identity: {
        device: String(after.dev),
        inode: String(after.ino),
        size: String(after.size),
        modified_ns: String(after.mtimeNs),
        mode: after.mode.toString(8),
      },
    };
  } finally {
    closeSync(descriptor);
  }
}

export function walkRegularFiles(root: string): string[] {
  const absoluteRoot = resolve(root);
  const files: string[] = [];
  function visit(path: string): void {
    const stat = lstatSync(path);
    if (stat.isSymbolicLink()) throw new Error(`symlink inputs are unsupported: ${path}`);
    if (stat.isFile()) {
      files.push(path);
      return;
    }
    if (!stat.isDirectory()) {
      throw new Error(`non-file input is unsupported: ${path}`);
    }
    for (const name of readdirSync(path).sort(utf8Compare)) {
      if (!name || /[\u0000-\u001f\u007f]/u.test(name)) {
        throw new Error(`input name contains a control character under ${path}`);
      }
      visit(join(path, name));
    }
  }
  visit(absoluteRoot);
  return files.sort((left, right) => utf8Compare(
    relative(absoluteRoot, left),
    relative(absoluteRoot, right),
  ));
}

function fsyncDirectory(path: string): void {
  const descriptor = openSync(path, constants.O_RDONLY);
  try {
    fsyncSync(descriptor);
  } finally {
    closeSync(descriptor);
  }
}

export function writeFileAtomic(path: string, bytes: string | Buffer, mode = 0o600): void {
  const absolute = resolve(path);
  const directory = dirname(absolute);
  mkdirSync(directory, { recursive: true });
  assertNoSymlinkComponents(directory, absolute);
  temporaryCounter += 1;
  const temporary = join(
    directory,
    `.${basename(absolute)}.tmp-${String(process.pid)}-${String(temporaryCounter)}`,
  );
  const descriptor = openSync(
    temporary,
    constants.O_CREAT | constants.O_EXCL | constants.O_WRONLY,
    mode,
  );
  try {
    writeFileSync(descriptor, bytes);
    fchmodSync(descriptor, mode);
    fsyncSync(descriptor);
  } catch (error) {
    closeSync(descriptor);
    rmSync(temporary, { force: true });
    throw error;
  }
  closeSync(descriptor);
  try {
    renameSync(temporary, absolute);
    fsyncDirectory(directory);
  } catch (error) {
    rmSync(temporary, { force: true });
    throw error;
  }
}

export function writeJsonAtomic(path: string, value: unknown, mode = 0o600): void {
  writeFileAtomic(path, stableJsonBytes(value), mode);
}

export function readJsonFile(path: string): unknown {
  const bytes = readFileSync(path);
  let parsed: unknown;
  try {
    parsed = JSON.parse(bytes.toString('utf8')) as unknown;
  } catch (error) {
    throw new Error(`invalid JSON at ${path}: ${error instanceof Error ? error.message : String(error)}`);
  }
  return parsed;
}

export function copyExactFile(source: string, destination: string, mode = 0o600): string {
  const stable = readStableRegularFile(source);
  writeFileAtomic(destination, stable.bytes, mode);
  const copied = readStableRegularFile(destination);
  if (!copied.bytes.equals(stable.bytes)) {
    throw new Error(`copy verification failed for ${destination}`);
  }
  return sha256Digest(stable.bytes);
}

export function digestFile(path: string): string {
  return sha256Digest(readStableRegularFile(path).bytes);
}

export function digestTreeRecords(records: Array<{ path: string; digest: string }>): string {
  const ordered = [...records].sort((left, right) => utf8Compare(left.path, right.path));
  const seen = new Set<string>();
  const hash = createHash('sha256');
  for (const record of ordered) {
    assertSafeRelativePath(record.path, 'tree record path');
    if (seen.has(record.path)) throw new Error(`duplicate tree record path: ${record.path}`);
    seen.add(record.path);
    if (!SHA256_PATTERN.test(record.digest)) {
      throw new Error(`invalid digest for ${record.path}`);
    }
    hash.update(record.path, 'utf8');
    hash.update(Buffer.from([0]));
    hash.update(record.digest.slice('sha256:'.length), 'ascii');
    hash.update('\n', 'ascii');
  }
  return `sha256:${hash.digest('hex')}`;
}

export function inventoryTree(root: string): FileTreeRecord[] {
  const absoluteRoot = resolve(root);
  if (!existsSync(absoluteRoot) || !lstatSync(absoluteRoot).isDirectory()) {
    throw new Error(`tree root is missing or not a directory: ${absoluteRoot}`);
  }
  return walkRegularFiles(absoluteRoot).map((path) => {
    const bytes = readStableRegularFile(path).bytes;
    return {
      path: relative(absoluteRoot, path).split(sep).join('/'),
      digest: sha256Digest(bytes),
      byte_length: String(bytes.byteLength),
    };
  }).sort((left, right) => utf8Compare(left.path, right.path));
}

export function makeTreeReadOnly(root: string): void {
  const directories: string[] = [];
  function visit(path: string): void {
    const stat = lstatSync(path);
    if (stat.isSymbolicLink()) throw new Error(`cannot freeze a symlink: ${path}`);
    if (stat.isFile()) {
      chmodSync(path, 0o444);
      return;
    }
    if (!stat.isDirectory()) throw new Error(`cannot freeze a non-file: ${path}`);
    directories.push(path);
    for (const name of readdirSync(path).sort(utf8Compare)) visit(join(path, name));
  }
  visit(resolve(root));
  for (const directory of directories.reverse()) chmodSync(directory, 0o555);
}

export function makeTreeOwnerWritable(root: string): void {
  function visit(path: string): void {
    const stat = lstatSync(path);
    if (stat.isSymbolicLink()) throw new Error(`cannot thaw a symlink: ${path}`);
    if (stat.isFile()) {
      chmodSync(path, 0o600);
      return;
    }
    if (!stat.isDirectory()) throw new Error(`cannot thaw a non-file: ${path}`);
    chmodSync(path, 0o700);
    for (const name of readdirSync(path).sort(utf8Compare)) visit(join(path, name));
  }
  visit(resolve(root));
}

export function nextDecimal(value: string): string {
  if (!/^(?:0|[1-9][0-9]*)$/.test(value)) {
    throw new Error(`invalid decimal counter: ${value}`);
  }
  return String(BigInt(value) + 1n);
}
