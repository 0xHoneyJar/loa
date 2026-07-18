import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { join, posix } from 'node:path';

export const BUNDLE_LOCK_FORMAT = 'aleph-bundle-lock/v1';
export const SOURCE_PROVENANCE_FORMAT = 'aleph-source-provenance/v1';
export const DIGEST_ALGORITHM = 'sha256-path-file-digest-v1';
export const ASSEMBLY_TOOL_PATH = 'scripts/assemble-bundles.ts';

export interface CoreManifest {
  manifest_format: string;
  core: {
    id: string;
    version: string;
    adapter_protocol_version: string;
    run_format_version: string;
    digest_algorithm: string;
  };
  manual_execution_binding: {
    id: string;
    version: string;
    lifecycle: string;
    paths: string[];
  };
  files: {
    core: string[];
    adapter: Record<string, string[]>;
    packaging: string[];
    repository_administration: string[];
  };
  checker_paths: string[];
  reference_documents: string[];
  bundle_targets: Array<{
    id: string;
    version: string;
    adapter_id: string;
  }>;
}

export interface AdapterCapability {
  state: string;
  evidence: string[];
}

export interface AdapterManifest {
  $schema: string;
  manifest_format: string;
  adapter: {
    id: string;
    version: string;
    host: string;
    protocol_version: string;
    run_format_version: string;
    lifecycle: string;
  };
  core_consumption: {
    mode: string;
    allow_overrides: boolean;
    mutable_fetch: boolean;
    overrides: string[];
    duplicates: string[];
    transformations: string[];
  };
  owned_paths: string[];
  references: string[];
  entrypoints: Array<{
    id: string;
    kind: string;
    state: string;
    path: string | null;
  }>;
  installation: {
    state: string;
    path: string | null;
  };
  capabilities: Record<string, AdapterCapability>;
  full_mode: {
    claimed: boolean;
  };
  profiles: unknown[];
  evidence: {
    implementation: string[];
    validation: string[];
    sanction: string[];
  };
}

export type BundleFileClassification = 'core' | 'adapter';

export interface BundleFileRecord {
  path: string;
  classification: BundleFileClassification;
  digest: string;
}

export interface BundleSourceRecord {
  manifest_projection: CoreManifest;
  manifest_projection_digest: string;
  assembly_tool: {
    path: string;
    digest: string;
  };
}

export interface BundleVcsProvenance {
  kind: 'git-dependency-closure-snapshot';
  object_format: 'sha1' | 'sha256';
  commit: string;
  commit_object: string;
  commit_tree: string;
  resolved: true;
  mutable_ref: null;
  worktree_state: 'clean' | 'modified';
}

export interface BundleProvenance {
  format: typeof SOURCE_PROVENANCE_FORMAT;
  vcs: BundleVcsProvenance;
  digest: string;
}

export interface BundleLock {
  lock_format: typeof BUNDLE_LOCK_FORMAT;
  digest_algorithm: typeof DIGEST_ALGORITHM;
  lock_digest: string;
  bundle: {
    id: string;
    version: string;
    payload_digest: string;
    digest: string;
  };
  core: {
    id: string;
    version: string;
    tree_digest: string;
  };
  adapter: {
    id: string;
    version: string;
    lifecycle: string;
    tree_digest: string;
  };
  checker_digest: string;
  adapter_protocol_version: string;
  run_format_version: string;
  source: BundleSourceRecord;
  provenance: BundleProvenance;
  files: BundleFileRecord[];
}

export interface BundleIdentityProjection {
  lock_format: typeof BUNDLE_LOCK_FORMAT;
  digest_algorithm: typeof DIGEST_ALGORITHM;
  bundle: {
    id: string;
    version: string;
    payload_digest: string;
  };
  core: BundleLock['core'];
  adapter: BundleLock['adapter'];
  checker_digest: string;
  adapter_protocol_version: string;
  run_format_version: string;
  source: BundleSourceRecord;
  provenance: BundleProvenance;
  files: BundleFileRecord[];
}

export interface BundlePlan {
  target: CoreManifest['bundle_targets'][number];
  payloadPaths: string[];
  files: BundleFileRecord[];
  manifestProjection: CoreManifest;
  payloadDigest: string;
  coreDigest: string;
  adapterDigest: string;
  checkerDigest: string;
  lockDigest: string;
  bundleDigest: string;
  identity: BundleIdentityProjection;
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

export function stringLeaves(value: unknown): string[] {
  if (typeof value === 'string') return [value];
  if (Array.isArray(value)) return value.flatMap(stringLeaves);
  if (isRecord(value)) {
    return Object.entries(value).flatMap(([key, item]) => [
      key,
      ...stringLeaves(item),
    ]);
  }
  return [];
}

export function utf8Compare(left: string, right: string): number {
  return Buffer.compare(Buffer.from(left, 'utf8'), Buffer.from(right, 'utf8'));
}

export function sortedUnique(values: string[]): string[] {
  return [...new Set(values)].sort(utf8Compare);
}

export function normalizedRepositoryPath(path: string): boolean {
  if (!path || path.startsWith('/') || path.includes('\\') || path.includes('\0')) {
    return false;
  }
  if (path.split('/').includes('..')) return false;
  return posix.normalize(path) === path && path !== '.';
}

export function sha256Hex(value: string | Buffer): string {
  return createHash('sha256').update(value).digest('hex');
}

export function sha256Digest(value: string | Buffer): string {
  return `sha256:${sha256Hex(value)}`;
}

export function bareSha256(digest: string): string {
  const match = /^sha256:([0-9a-f]{64})$/.exec(digest);
  if (!match) throw new Error(`invalid SHA-256 digest "${digest}"`);
  return match[1];
}

export function fileDigest(root: string, path: string): string {
  return sha256Digest(readFileSync(join(root, path)));
}

export function digestEntries(
  entries: Array<{ path: string; digest: string }>,
): string {
  const records = [...entries]
    .sort((left, right) => utf8Compare(left.path, right.path))
    .map(({ path, digest }) => `${path}\0${bareSha256(digest)}\n`)
    .join('');
  return sha256Digest(records);
}

export function treeDigest(root: string, paths: string[]): string {
  return digestEntries(
    sortedUnique(paths).map((path) => ({ path, digest: fileDigest(root, path) })),
  );
}

function canonicalJsonString(value: string): string {
  let result = '"';
  for (let index = 0; index < value.length; index += 1) {
    const code = value.charCodeAt(index);
    if (code === 0x22) result += '\\"';
    else if (code === 0x5c) result += '\\\\';
    else if (code === 0x08) result += '\\b';
    else if (code === 0x09) result += '\\t';
    else if (code === 0x0a) result += '\\n';
    else if (code === 0x0c) result += '\\f';
    else if (code === 0x0d) result += '\\r';
    else if (code <= 0x1f) result += `\\u${code.toString(16).padStart(4, '0')}`;
    else if (code >= 0xd800 && code <= 0xdbff) {
      const next = value.charCodeAt(index + 1);
      if (next >= 0xdc00 && next <= 0xdfff) {
        result += value[index] + value[index + 1];
        index += 1;
      } else {
        throw new Error('canonical JSON forbids unpaired UTF-16 surrogates');
      }
    } else if (code >= 0xdc00 && code <= 0xdfff) {
      throw new Error('canonical JSON forbids unpaired UTF-16 surrogates');
    } else {
      result += value[index];
    }
  }
  return `${result}"`;
}

export function canonicalJson(value: unknown): string {
  if (value === null) return 'null';
  if (typeof value === 'string') return canonicalJsonString(value);
  if (typeof value === 'boolean') return value ? 'true' : 'false';
  if (typeof value === 'number') {
    throw new Error('canonical JSON forbids numbers');
  }
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  if (!isRecord(value)) {
    throw new Error(`canonical JSON cannot serialize ${typeof value}`);
  }
  return `{${
    Object.keys(value)
      .sort(utf8Compare)
      .map((key) => `${canonicalJsonString(key)}:${canonicalJson(value[key])}`)
      .join(',')
  }}`;
}

export function canonicalJsonBytes(value: unknown): Buffer {
  return Buffer.from(`${canonicalJson(value)}\n`, 'utf8');
}

function payloadSet(
  manifest: CoreManifest,
  target: CoreManifest['bundle_targets'][number],
): Set<string> {
  return new Set([
    ...manifest.files.core,
    ...(manifest.files.adapter[target.adapter_id] || []),
  ]);
}

export function selectedManifestProjection(
  manifest: CoreManifest,
  target: CoreManifest['bundle_targets'][number],
): CoreManifest {
  const selected = payloadSet(manifest, target);
  return {
    manifest_format: manifest.manifest_format,
    core: { ...manifest.core },
    manual_execution_binding: {
      ...manifest.manual_execution_binding,
      paths: sortedUnique(manifest.manual_execution_binding.paths),
    },
    files: {
      core: sortedUnique(manifest.files.core),
      adapter: {
        [target.adapter_id]: sortedUnique(
          manifest.files.adapter[target.adapter_id] || [],
        ),
      },
      packaging: ['core.manifest.json'],
      repository_administration: [],
    },
    checker_paths: sortedUnique(manifest.checker_paths),
    reference_documents: sortedUnique(
      manifest.reference_documents.filter((path) => selected.has(path)),
    ),
    bundle_targets: [{ ...target }],
  };
}

function fileRecords(
  root: string,
  manifest: CoreManifest,
  target: CoreManifest['bundle_targets'][number],
): BundleFileRecord[] {
  const core = manifest.files.core.map((path): BundleFileRecord => ({
    path,
    classification: 'core',
    digest: fileDigest(root, path),
  }));
  const adapter = (manifest.files.adapter[target.adapter_id] || [])
    .map((path): BundleFileRecord => ({
      path,
      classification: 'adapter',
      digest: fileDigest(root, path),
    }));
  return [...core, ...adapter]
    .sort((left, right) => utf8Compare(left.path, right.path));
}

export function lockIdentityProjection(lock: BundleLock): BundleIdentityProjection {
  return {
    lock_format: lock.lock_format,
    digest_algorithm: lock.digest_algorithm,
    bundle: {
      id: lock.bundle.id,
      version: lock.bundle.version,
      payload_digest: lock.bundle.payload_digest,
    },
    core: { ...lock.core },
    adapter: { ...lock.adapter },
    checker_digest: lock.checker_digest,
    adapter_protocol_version: lock.adapter_protocol_version,
    run_format_version: lock.run_format_version,
    source: {
      manifest_projection: lock.source.manifest_projection,
      manifest_projection_digest: lock.source.manifest_projection_digest,
      assembly_tool: { ...lock.source.assembly_tool },
    },
    provenance: structuredClone(lock.provenance),
    files: lock.files.map((file) => ({ ...file })),
  };
}

export function provenanceDigest(vcs: BundleVcsProvenance): string {
  return sha256Digest(canonicalJsonBytes(vcs));
}

export function resealBundleLock(lock: BundleLock): BundleLock {
  const sealed = structuredClone(lock);
  sealed.source.manifest_projection_digest = sha256Digest(
    canonicalJsonBytes(sealed.source.manifest_projection),
  );
  sealed.provenance.digest = provenanceDigest(sealed.provenance.vcs);
  sealed.lock_digest = sha256Digest(
    canonicalJsonBytes(lockIdentityProjection(sealed)),
  );
  sealed.bundle.digest = digestEntries([
    ...sealed.files,
    { path: 'bundle.lock.json', digest: sealed.lock_digest },
  ]);
  return sealed;
}

export function buildBundlePlan(
  root: string,
  manifest: CoreManifest,
  target: CoreManifest['bundle_targets'][number],
  adapter: AdapterManifest,
  provenanceOverride?: BundleProvenance,
): BundlePlan {
  const adapterPaths = manifest.files.adapter[target.adapter_id] || [];
  const payloadPaths = sortedUnique([...manifest.files.core, ...adapterPaths]);
  const files = fileRecords(root, manifest, target);
  const coreDigest = digestEntries(
    files.filter((file) => file.classification === 'core'),
  );
  const adapterDigest = digestEntries(
    files.filter((file) => file.classification === 'adapter'),
  );
  const checkerPathSet = new Set(manifest.checker_paths);
  const checkerFiles = files.filter((file) => checkerPathSet.has(file.path));
  const checkerDigest = digestEntries(checkerFiles);
  const payloadDigest = digestEntries(files);
  const manifestProjection = selectedManifestProjection(manifest, target);
  const source: BundleSourceRecord = {
    manifest_projection: manifestProjection,
    manifest_projection_digest: sha256Digest(
      canonicalJsonBytes(manifestProjection),
    ),
    assembly_tool: {
      path: ASSEMBLY_TOOL_PATH,
      digest: fileDigest(root, ASSEMBLY_TOOL_PATH),
    },
  };
  const provenance = provenanceOverride
    ? structuredClone(provenanceOverride)
    : resolvedSourceProvenance(root, payloadPaths);
  const identity: BundleIdentityProjection = {
    lock_format: BUNDLE_LOCK_FORMAT,
    digest_algorithm: DIGEST_ALGORITHM,
    bundle: {
      id: target.id,
      version: target.version,
      payload_digest: payloadDigest,
    },
    core: {
      id: manifest.core.id,
      version: manifest.core.version,
      tree_digest: coreDigest,
    },
    adapter: {
      id: adapter.adapter.id,
      version: adapter.adapter.version,
      lifecycle: adapter.adapter.lifecycle,
      tree_digest: adapterDigest,
    },
    checker_digest: checkerDigest,
    adapter_protocol_version: manifest.core.adapter_protocol_version,
    run_format_version: manifest.core.run_format_version,
    source,
    provenance,
    files,
  };
  const lockDigest = sha256Digest(canonicalJsonBytes(identity));
  const bundleDigest = digestEntries([
    ...files,
    { path: 'bundle.lock.json', digest: lockDigest },
  ]);
  return {
    target,
    payloadPaths,
    files,
    manifestProjection,
    payloadDigest,
    coreDigest,
    adapterDigest,
    checkerDigest,
    lockDigest,
    bundleDigest,
    identity,
  };
}

function runGit(root: string, args: string[]): string {
  const result = spawnSync('git', ['-C', root, ...args], {
    encoding: 'utf8',
    maxBuffer: 32 * 1024 * 1024,
  });
  if (result.status !== 0) {
    throw new Error(
      `git ${args.join(' ')} failed: ${
        result.stderr.trim()
        || result.error?.message
        || `status ${String(result.status)}`
      }`,
    );
  }
  return result.stdout.trim();
}

function runGitBuffer(root: string, args: string[]): Buffer {
  const result = spawnSync('git', ['-C', root, ...args], {
    encoding: 'buffer',
    maxBuffer: 32 * 1024 * 1024,
  });
  if (result.status !== 0) {
    throw new Error(
      `git ${args.join(' ')} failed: ${
        result.stderr.toString('utf8').trim()
        || result.error?.message
        || `status ${String(result.status)}`
      }`,
    );
  }
  return result.stdout;
}

export function gitCommitObjectId(vcs: BundleVcsProvenance): string {
  const bytes = Buffer.from(vcs.commit_object, 'base64');
  const header = Buffer.from(`commit ${bytes.length}\0`, 'utf8');
  return createHash(vcs.object_format).update(header).update(bytes).digest('hex');
}

export function gitCommitTree(vcs: BundleVcsProvenance): string {
  const bytes = Buffer.from(vcs.commit_object, 'base64');
  const firstLineEnd = bytes.indexOf(0x0a);
  const firstLine = bytes
    .subarray(0, firstLineEnd >= 0 ? firstLineEnd : bytes.length)
    .toString('ascii');
  const match = /^tree ([0-9a-f]+)$/.exec(firstLine);
  return match?.[1] || '';
}

export function resolvedSourceProvenance(
  root: string,
  dependencyPaths: string[],
): BundleProvenance {
  const objectFormat = runGit(root, ['rev-parse', '--show-object-format']);
  if (objectFormat !== 'sha1' && objectFormat !== 'sha256') {
    throw new Error(`unsupported Git object format "${objectFormat}"`);
  }
  let commit = runGit(root, [
    '--literal-pathspecs',
    'log',
    '-1',
    '--format=%H',
    '--',
    ...sortedUnique(dependencyPaths),
  ]);
  if (!commit) {
    const roots = runGit(root, ['rev-list', '--max-parents=0', 'HEAD'])
      .split('\n')
      .filter(Boolean)
      .sort(utf8Compare);
    commit = roots[0] || '';
  }
  const commitTree = runGit(root, [
    'rev-parse',
    '--verify',
    `${commit}^{tree}`,
  ]);
  const commitObject = runGitBuffer(root, ['cat-file', 'commit', commit]);
  const expectedLength = objectFormat === 'sha1' ? 40 : 64;
  const objectPattern = new RegExp(`^[0-9a-f]{${expectedLength}}$`);
  if (!objectPattern.test(commit) || /^0+$/.test(commit)) {
    throw new Error('source commit is unresolved or malformed');
  }
  if (!objectPattern.test(commitTree) || /^0+$/.test(commitTree)) {
    throw new Error('source commit tree is unresolved or malformed');
  }
  const status = runGit(root, [
    '--literal-pathspecs',
    'status',
    '--porcelain=v1',
    '--untracked-files=all',
    '--',
    ...sortedUnique(dependencyPaths),
  ]);
  const vcs: BundleVcsProvenance = {
    kind: 'git-dependency-closure-snapshot',
    object_format: objectFormat,
    commit,
    commit_object: commitObject.toString('base64'),
    commit_tree: commitTree,
    resolved: true,
    mutable_ref: null,
    worktree_state: status ? 'modified' : 'clean',
  };
  return {
    format: SOURCE_PROVENANCE_FORMAT,
    vcs,
    digest: provenanceDigest(vcs),
  };
}

export function createBundleLock(
  plan: BundlePlan,
): BundleLock {
  return resealBundleLock({
    lock_format: BUNDLE_LOCK_FORMAT,
    digest_algorithm: DIGEST_ALGORITHM,
    lock_digest: plan.lockDigest,
    bundle: {
      id: plan.target.id,
      version: plan.target.version,
      payload_digest: plan.payloadDigest,
      digest: plan.bundleDigest,
    },
    core: { ...plan.identity.core },
    adapter: { ...plan.identity.adapter },
    checker_digest: plan.checkerDigest,
    adapter_protocol_version: plan.identity.adapter_protocol_version,
    run_format_version: plan.identity.run_format_version,
    source: structuredClone(plan.identity.source),
    provenance: structuredClone(plan.identity.provenance),
    files: plan.files.map((file) => ({ ...file })),
  });
}

export function bundleLockBytes(lock: BundleLock): Buffer {
  return canonicalJsonBytes(lock);
}

export function readJsonFile(path: string): unknown {
  return JSON.parse(readFileSync(path, 'utf8')) as unknown;
}
