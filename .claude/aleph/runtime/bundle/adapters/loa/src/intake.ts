import {
  existsSync,
  lstatSync,
  mkdirSync,
  readdirSync,
  rmSync,
} from 'node:fs';
import {
  basename,
  extname,
  join,
  relative,
  resolve,
  sep,
} from 'node:path';
import {
  LOA_CORPUS_SNAPSHOT_FORMAT,
  LOA_INSTALLED_BUNDLE_ROOT,
  type CorpusSnapshot,
  type FrozenSourceRecord,
  type S0AuthorityResponse,
} from './types.ts';
import {
  assertNoSymlinkComponents,
  assertPathWithin,
  digestTreeRecords,
  makeTreeReadOnly,
  pathIsWithin,
  readJsonFile,
  readStableRegularFile,
  sha256Digest,
  stableJsonBytes,
  type StableFileRead,
  utf8Compare,
  walkRegularFiles,
  writeFileAtomic,
  writeJsonAtomic,
} from './fs.ts';

export const DEFAULT_SUPPORTED_SOURCE_EXTENSIONS = [
  '',
  '.csv',
  '.json',
  '.jsonl',
  '.md',
  '.tsv',
  '.txt',
  '.yaml',
  '.yml',
] as const;

export interface SnapshotCorpusOptions {
  loaRoot: string;
  runDir: string;
  runId: string;
  inputs: string[];
  capturedAt: string;
  supportedExtensions?: readonly string[];
}

export interface CorpusFreezePlan {
  staged: CorpusSnapshot;
  frozen: CorpusSnapshot;
  response: S0AuthorityResponse;
  excluded_source_ids: string[];
}

const SENSITIVITY_LABELS = new Set(['none', 'pii', 'confidential', 'licensing']);

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function hasExactKeys(value: unknown, keys: readonly string[]): value is Record<string, unknown> {
  return isRecord(value)
    && Object.keys(value).sort(utf8Compare).join('\0') === [...keys].sort(utf8Compare).join('\0');
}

function exactNonemptyString(value: unknown): value is string {
  return typeof value === 'string'
    && value === value.trim()
    && value.length > 0
    && !/[\u0000-\u001f\u007f]/u.test(value);
}

function canonicalTimestamp(value: unknown): value is string {
  if (typeof value !== 'string') return false;
  try {
    return new Date(value).toISOString() === value;
  } catch {
    return false;
  }
}

function normalizedRelative(root: string, path: string): string {
  const value = relative(root, path).split(sep).join('/');
  if (!value || value === '.' || value.startsWith('../')) {
    throw new Error(`source path does not resolve below its input root: ${path}`);
  }
  return value;
}

function validRunId(value: string): boolean {
  return /^RUN-[A-Za-z0-9]+(?:[._-][A-Za-z0-9]+)*$/u.test(value);
}

function validateUtf8(bytes: Buffer, path: string): void {
  try {
    new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  } catch {
    throw new Error(`source is not valid UTF-8 text: ${path}`);
  }
  if (bytes.includes(0)) throw new Error(`source contains NUL bytes: ${path}`);
}

function sourceScheme(path: string): FrozenSourceRecord['scheme'] {
  return extname(path).toLowerCase() === '.md' ? 'md-lines' : 'text-lines';
}

function paddedSourceId(index: number): string {
  return `SRC-${String(index).padStart(3, '0')}`;
}

function assertEmptySourcesDirectory(path: string): void {
  if (!existsSync(path)) return;
  const stat = lstatSync(path);
  if (stat.isSymbolicLink() || !stat.isDirectory()) {
    throw new Error(`corpus sources path is not a normal directory: ${path}`);
  }
  if (readdirSync(path).length > 0) {
    throw new Error(`corpus sources directory is already populated: ${path}`);
  }
}

export function snapshotCorpus(options: SnapshotCorpusOptions): CorpusSnapshot {
  if (!validRunId(options.runId)) throw new Error(`invalid run ID: ${options.runId}`);
  if (options.inputs.length === 0) throw new Error('start requires at least one file or directory');
  const loaRoot = resolve(options.loaRoot);
  const runDir = resolve(options.runDir);
  assertPathWithin(loaRoot, runDir, 'run directory');
  const installedRoot = resolve(loaRoot, LOA_INSTALLED_BUNDLE_ROOT);
  const supported = new Set(
    (options.supportedExtensions || DEFAULT_SUPPORTED_SOURCE_EXTENSIONS)
      .map((extension) => extension.toLowerCase()),
  );
  const roots: CorpusSnapshot['roots'] = [];
  const candidates: Array<{
    rootIndex: number;
    absolute: string;
    relative: string;
  }> = [];
  const seen = new Set<string>();
  const directoryListings = new Map<string, string[]>();

  for (const [index, input] of options.inputs.entries()) {
    const absolute = resolve(loaRoot, input);
    assertPathWithin(loaRoot, absolute, `input ${String(index + 1)}`);
    if (pathIsWithin(runDir, absolute) || pathIsWithin(absolute, runDir)) {
      throw new Error(`input overlaps the run directory: ${input}`);
    }
    if (pathIsWithin(installedRoot, absolute) || pathIsWithin(absolute, installedRoot)) {
      throw new Error(`input overlaps the installed Aleph runtime: ${input}`);
    }
    if (!existsSync(absolute)) throw new Error(`input does not exist: ${input}`);
    assertNoSymlinkComponents(loaRoot, absolute);
    const stat = lstatSync(absolute);
    if (stat.isSymbolicLink() || (!stat.isFile() && !stat.isDirectory())) {
      throw new Error(`unsupported input kind: ${input}`);
    }
    const kind = stat.isDirectory() ? 'directory' : 'file';
    roots.push({
      argument_index: String(index),
      argument: input,
      resolved_path: absolute,
      kind,
    });
    const paths = walkRegularFiles(absolute);
    if (stat.isDirectory()) {
      directoryListings.set(absolute, paths.map((path) => normalizedRelative(absolute, path)));
    }
    for (const path of paths) {
      const canonical = resolve(path);
      if (seen.has(canonical)) throw new Error(`source was selected more than once: ${path}`);
      seen.add(canonical);
      const extension = extname(path).toLowerCase();
      if (!supported.has(extension)) {
        throw new Error(`unsupported source extension ${extension || '(none)'}: ${path}`);
      }
      candidates.push({
        rootIndex: index,
        absolute: path,
        relative: stat.isFile() ? basename(path) : normalizedRelative(absolute, path),
      });
    }
  }
  if (candidates.length === 0) throw new Error('the selected inputs contain no supported files');

  const sourcesRoot = join(runDir, 'corpus', 'sources');
  const snapshotPath = join(runDir, 'control', 'corpus.snapshot.json');
  if (existsSync(snapshotPath)) {
    throw new Error(`corpus snapshot already exists: ${snapshotPath}`);
  }
  assertEmptySourcesDirectory(sourcesRoot);
  mkdirSync(sourcesRoot, { recursive: true });
  const files: FrozenSourceRecord[] = [];
  const capturedSources: Array<{
    absolute: string;
    frozenPath: string;
    byteLength: string;
    digest: string;
    identity: StableFileRead['identity'];
  }> = [];
  try {
    for (const [index, candidate] of candidates.entries()) {
      const sourceId = paddedSourceId(index + 1);
      const relativePath = candidate.relative.split(sep).join('/');
      const frozenPath = `corpus/sources/${sourceId}/${relativePath}`;
      const destination = join(runDir, frozenPath);
      assertNoSymlinkComponents(runDir, destination);
      const stable = readStableRegularFile(candidate.absolute);
      validateUtf8(stable.bytes, candidate.absolute);
      writeFileAtomic(destination, stable.bytes, 0o600);
      const copied = readStableRegularFile(destination);
      if (!copied.bytes.equals(stable.bytes)) {
        throw new Error(`frozen copy differs from source: ${candidate.absolute}`);
      }
      const digest = sha256Digest(stable.bytes);
      files.push({
        source_id: sourceId,
        input_root_index: String(candidate.rootIndex),
        original_path: candidate.absolute,
        relative_path: relativePath,
        frozen_path: frozenPath,
        byte_length: String(stable.bytes.byteLength),
        digest,
        mode: stable.identity.mode,
        scheme: sourceScheme(candidate.absolute),
      });
      capturedSources.push({
        absolute: candidate.absolute,
        frozenPath,
        byteLength: String(stable.bytes.byteLength),
        digest,
        identity: stable.identity,
      });
    }
    for (const [directory, before] of directoryListings) {
      const after = walkRegularFiles(directory).map((path) => normalizedRelative(directory, path));
      if (before.length !== after.length || before.some((path, index) => path !== after[index])) {
        throw new Error(`input directory changed while it was captured: ${directory}`);
      }
    }
    for (const captured of capturedSources) {
      const source = readStableRegularFile(captured.absolute);
      const frozen = readStableRegularFile(join(runDir, captured.frozenPath));
      const sourceDigest = sha256Digest(source.bytes);
      const frozenDigest = sha256Digest(frozen.bytes);
      if (!stableJsonBytes(source.identity).equals(stableJsonBytes(captured.identity))
        || String(source.bytes.byteLength) !== captured.byteLength
        || sourceDigest !== captured.digest
        || String(frozen.bytes.byteLength) !== captured.byteLength
        || frozenDigest !== captured.digest
        || !source.bytes.equals(frozen.bytes)) {
        throw new Error(`source changed after its frozen copy was staged: ${captured.absolute}`);
      }
    }
  } catch (error) {
    rmSync(sourcesRoot, { recursive: true, force: true });
    rmSync(snapshotPath, { force: true });
    throw error;
  }

  const treeDigest = digestTreeRecords(files.map((file) => ({
    path: file.frozen_path,
    digest: file.digest,
  })));
  const snapshot: CorpusSnapshot = {
    format: LOA_CORPUS_SNAPSHOT_FORMAT,
    run_id: options.runId,
    status: 'staged',
    captured_at: options.capturedAt,
    frozen_at: null,
    roots,
    files,
    tree_digest: treeDigest,
  };
  writeJsonAtomic(snapshotPath, snapshot);
  return snapshot;
}

function asCorpusSnapshot(value: unknown): CorpusSnapshot {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new Error('corpus snapshot must be an object');
  }
  const snapshot = value as Partial<CorpusSnapshot>;
  if (snapshot.format !== LOA_CORPUS_SNAPSHOT_FORMAT
    || typeof snapshot.run_id !== 'string'
    || (snapshot.status !== 'staged' && snapshot.status !== 'frozen')
    || !Array.isArray(snapshot.files)
    || typeof snapshot.tree_digest !== 'string') {
    throw new Error('corpus snapshot fields are malformed');
  }
  return snapshot as CorpusSnapshot;
}

export function verifyCorpusSnapshot(runDir: string): CorpusSnapshot {
  const root = resolve(runDir);
  const snapshot = asCorpusSnapshot(readJsonFile(join(root, 'control', 'corpus.snapshot.json')));
  const expected = new Map(snapshot.files.map((file) => [file.frozen_path, file]));
  if (expected.size !== snapshot.files.length) throw new Error('corpus snapshot contains duplicate paths');
  for (const file of snapshot.files) {
    const absolute = join(root, file.frozen_path);
    assertPathWithin(join(root, 'corpus', 'sources'), absolute, 'frozen source');
    const stable = readStableRegularFile(absolute);
    if (String(stable.bytes.byteLength) !== file.byte_length
      || sha256Digest(stable.bytes) !== file.digest) {
      throw new Error(`frozen source failed verification: ${file.frozen_path}`);
    }
  }
  const actualPaths = walkRegularFiles(join(root, 'corpus', 'sources'))
    .map((path) => relative(root, path).split(sep).join('/'))
    .sort(utf8Compare);
  const expectedPaths = [...expected.keys()].sort(utf8Compare);
  if (actualPaths.length !== expectedPaths.length
    || actualPaths.some((path, index) => path !== expectedPaths[index])) {
    throw new Error('frozen corpus contains missing or extra files');
  }
  const digest = digestTreeRecords(snapshot.files.map((file) => ({
    path: file.frozen_path,
    digest: file.digest,
  })));
  if (digest !== snapshot.tree_digest) throw new Error('corpus tree digest mismatch');
  return snapshot;
}

function validateAuthorityResponse(
  snapshot: CorpusSnapshot,
  candidate: unknown,
): {
  response: S0AuthorityResponse;
  retained: FrozenSourceRecord[];
  excluded: FrozenSourceRecord[];
} {
  if (!hasExactKeys(candidate, [
    'format',
    'gate_id',
    'run_id',
    'authority',
    'decision',
    'declared_scope',
    'exclusions',
    'sensitivity_rulings',
    'freeze',
    'recorded_at',
    'simulation',
  ])) {
    throw new Error('S0 authority response fields are malformed');
  }
  const response = candidate as unknown as S0AuthorityResponse;
  if (response.format !== 'aleph-loa-authority-response/v1'
    || response.gate_id !== 'S0'
    || response.run_id !== snapshot.run_id
    || !hasExactKeys(response.authority, ['kind', 'identity'])
    || response.authority.kind !== 'human'
    || !exactNonemptyString(response.authority.identity)
    || !exactNonemptyString(response.declared_scope)
    || !canonicalTimestamp(response.recorded_at)) {
    throw new Error('S0 authority response is incomplete or bound to another run');
  }
  if (response.decision !== 'approve-freeze' || response.freeze !== true) {
    throw new Error('S0 authority did not approve corpus freeze');
  }
  if (!Array.isArray(response.exclusions)
    || response.exclusions.some((entry) => !exactNonemptyString(entry))
    || new Set(response.exclusions).size !== response.exclusions.length) {
    throw new Error('S0 exclusions must be unique exact source IDs');
  }
  if (response.simulation !== null
    && (!hasExactKeys(response.simulation, ['kind'])
      || response.simulation.kind !== 'fixture-simulated')) {
    throw new Error('S0 simulation marker must be null or fixture-simulated');
  }
  if (!Array.isArray(response.sensitivity_rulings)) {
    throw new Error('S0 authority response must contain per-source sensitivity rulings');
  }
  for (const ruling of response.sensitivity_rulings) {
    if (!hasExactKeys(ruling, ['source_id', 'labels', 'decision'])
      || !exactNonemptyString(ruling.source_id)
      || (ruling.decision !== 'admit-exact-bytes' && ruling.decision !== 'exclude')
      || !Array.isArray(ruling.labels)
      || ruling.labels.length === 0
      || ruling.labels.some((label) => !SENSITIVITY_LABELS.has(label))
      || new Set(ruling.labels).size !== ruling.labels.length
      || (ruling.labels.includes('none') && ruling.labels.length !== 1)) {
      throw new Error(`S0 sensitivity ruling is malformed for ${String(ruling?.source_id)}`);
    }
  }
  const rulings = new Map(response.sensitivity_rulings.map((ruling) => [ruling.source_id, ruling]));
  if (rulings.size !== response.sensitivity_rulings.length) {
    throw new Error('S0 authority response contains duplicate sensitivity rulings');
  }
  for (const source of snapshot.files) {
    if (!rulings.has(source.source_id)) {
      throw new Error(`S0 authority response omits sensitivity ruling for ${source.source_id}`);
    }
  }
  for (const sourceId of rulings.keys()) {
    if (!snapshot.files.some((source) => source.source_id === sourceId)) {
      throw new Error(`S0 authority response names unknown source ${sourceId}`);
    }
  }
  const excludedIds = response.sensitivity_rulings
    .filter((ruling) => ruling.decision === 'exclude')
    .map((ruling) => ruling.source_id)
    .sort(utf8Compare);
  const declaredExclusions = [...response.exclusions].sort(utf8Compare);
  if (excludedIds.length !== declaredExclusions.length
    || excludedIds.some((sourceId, index) => sourceId !== declaredExclusions[index])) {
    throw new Error('S0 exclusions must exactly equal the source IDs ruled excluded');
  }
  const retained = snapshot.files.filter((source) => (
    rulings.get(source.source_id)?.decision === 'admit-exact-bytes'
  ));
  const excluded = snapshot.files.filter((source) => (
    rulings.get(source.source_id)?.decision === 'exclude'
  ));
  if (retained.length === 0) throw new Error('S0 authority excluded every staged source');
  return { response, retained, excluded };
}

export function planCorpusFreeze(
  runDir: string,
  candidate: S0AuthorityResponse,
): CorpusFreezePlan {
  const root = resolve(runDir);
  const snapshot = verifyCorpusSnapshot(root);
  if (snapshot.status !== 'staged') throw new Error('corpus is already frozen');
  const { response, retained, excluded } = validateAuthorityResponse(snapshot, candidate);
  const frozen: CorpusSnapshot = {
    ...snapshot,
    status: 'frozen',
    frozen_at: response.recorded_at,
    files: retained,
    tree_digest: digestTreeRecords(retained.map((file) => ({
      path: file.frozen_path,
      digest: file.digest,
    }))),
  };
  return {
    staged: snapshot,
    frozen,
    response,
    excluded_source_ids: excluded.map((source) => source.source_id).sort(utf8Compare),
  };
}

function writeJsonExactOrFail(path: string, value: unknown, label: string): void {
  if (existsSync(path)) {
    if (!stableJsonBytes(readJsonFile(path)).equals(stableJsonBytes(value))) {
      throw new Error(`${label} already exists with different bytes`);
    }
    return;
  }
  writeJsonAtomic(path, value);
}

export function applyCorpusFreeze(
  runDir: string,
  plan: CorpusFreezePlan,
): CorpusSnapshot {
  const root = resolve(runDir);
  const snapshotPath = join(root, 'control', 'corpus.snapshot.json');
  const current = asCorpusSnapshot(readJsonFile(snapshotPath));
  if (plan.staged.run_id !== plan.frozen.run_id
    || plan.response.run_id !== plan.staged.run_id
    || plan.staged.status !== 'staged'
    || plan.frozen.status !== 'frozen') {
    throw new Error('corpus freeze plan is internally inconsistent');
  }
  const currentBytes = stableJsonBytes(current);
  if (!currentBytes.equals(stableJsonBytes(plan.staged))
    && !currentBytes.equals(stableJsonBytes(plan.frozen))) {
    throw new Error('corpus snapshot is neither the staged nor frozen transaction image');
  }
  for (const sourceId of plan.excluded_source_ids) {
    if (!/^SRC-[0-9]{3}$/u.test(sourceId)
      || plan.frozen.files.some((source) => source.source_id === sourceId)
      || !plan.staged.files.some((source) => source.source_id === sourceId)) {
      throw new Error(`corpus freeze plan has invalid exclusion ${sourceId}`);
    }
    rmSync(join(root, 'corpus', 'sources', sourceId), {
      recursive: true,
      force: true,
    });
  }
  writeJsonExactOrFail(
    join(root, 'control', 'gates', 'GATE-S0-response.json'),
    plan.response,
    'S0 authority response',
  );
  if (!currentBytes.equals(stableJsonBytes(plan.frozen))) {
    writeJsonAtomic(snapshotPath, plan.frozen);
  }
  makeTreeReadOnly(join(root, 'corpus', 'sources'));
  return verifyCorpusSnapshot(root);
}

export function freezeCorpus(
  runDir: string,
  candidate: S0AuthorityResponse,
): CorpusSnapshot {
  return applyCorpusFreeze(runDir, planCorpusFreeze(runDir, candidate));
}
