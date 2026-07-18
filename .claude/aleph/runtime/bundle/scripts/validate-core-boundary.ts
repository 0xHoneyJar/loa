#!/usr/bin/env node

import {
  existsSync,
  lstatSync,
  readFileSync,
} from 'node:fs';
import { spawnSync } from 'node:child_process';
import { dirname, isAbsolute, join, posix, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  buildBundlePlan,
  DIGEST_ALGORITHM,
  sortedUnique,
  stringLeaves,
  treeDigest,
} from './lib/bundle-format.ts';
import type { BundleProvenance } from './lib/bundle-format.ts';
import { ResultCollector } from './lib/results.ts';
import type { CheckReport } from './lib/results.ts';

const SCRIPT_PATH = fileURLToPath(import.meta.url);
const DEFAULT_ROOT = resolve(dirname(SCRIPT_PATH), '..');
const LIFECYCLES = ['planned', 'implemented', 'validated', 'sanctioned'] as const;
const ENTRYPOINT_KINDS = ['slash-command', 'native-agent', 'executable', 'tool'] as const;
const IDENTIFIER_PATTERN = /^[a-z][a-z0-9-]*$/;
const VERSION_PATTERN = /^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z][0-9A-Za-z.-]*)?$/;
const CAPABILITIES = [
  'durable_file_io',
  'frozen_corpus_snapshots',
  'fresh_context_workers',
  'blind_bundles',
  'validated_structured_returns',
  'single_writer_ledgers',
  'deterministic_checker_invocation',
  'human_authority_gates',
  'durable_pause_resume',
  'exact_model_identity',
  'immutable_runtime_snapshot',
  'host_model_effort_mapping',
  'immutable_bundle_installation',
] as const;

type Lifecycle = typeof LIFECYCLES[number];
type Classification =
  | 'core'
  | 'adapter'
  | 'packaging'
  | 'repository-administration';

interface CoreManifest {
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
  bundle_targets: Array<{ id: string; version: string; adapter_id: string }>;
}

interface AdapterCapability {
  state: string;
  evidence: string[];
}

interface AdapterManifest {
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

interface PathOwner {
  classification: Classification;
  adapterId?: string;
}

interface AdapterSummary {
  id: string;
  lifecycle: string;
  fullModeClaimed: boolean;
  preflight: 'READY' | 'NOT-READY';
  preflightReasons: string[];
}

interface DigestReport {
  algorithm: string;
  core: string;
  checker: string;
  manualExecutionBinding: string;
  adapters: Record<string, string>;
  bundles: Record<string, {
    adapterId: string;
    coreDigest: string;
    adapterDigest: string;
    payloadDigest: string;
    lockProjectionDigest: string;
    bundleDigest: string;
  }>;
}

interface InventoryReport {
  total: number;
  core: number;
  adapters: Record<string, number>;
  packaging: number;
  repositoryAdministration: number;
}

export type CoreBoundaryReport = CheckReport<{
  inventory: InventoryReport;
  digests: DigestReport;
  adapters: AdapterSummary[];
}>;

export interface ValidateCoreBoundaryOptions {
  root?: string;
  preflightAdapter?: string;
  bundleProvenance?: Record<string, BundleProvenance>;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((item) => typeof item === 'string');
}

function sameStrings(left: string[], right: string[]): boolean {
  const a = sortedUnique(left);
  const b = sortedUnique(right);
  return a.length === b.length && a.every((value, index) => value === b[index]);
}

function exactKeys(value: unknown, keys: readonly string[]): boolean {
  if (!isRecord(value)) return false;
  return sameStrings(Object.keys(value), [...keys]);
}

function normalizedRepositoryPath(path: string): boolean {
  if (!path || isAbsolute(path) || path.includes('\\') || path.includes('\0')) {
    return false;
  }
  if (path.split('/').includes('..')) return false;
  return posix.normalize(path) === path && path !== '.';
}

function validateIdentifier(
  value: unknown,
  scope: string,
  errors: string[],
): void {
  if (typeof value !== 'string' || !IDENTIFIER_PATTERN.test(value)) {
    errors.push(`${scope} must match ${IDENTIFIER_PATTERN.source}`);
  }
}

function validateVersion(
  value: unknown,
  scope: string,
  errors: string[],
): void {
  if (typeof value !== 'string' || !VERSION_PATTERN.test(value)) {
    errors.push(`${scope} must be a semantic version`);
  }
}

function validateRepositoryPath(
  value: unknown,
  scope: string,
  errors: string[],
  allowNull = false,
): void {
  if (allowNull && value === null) return;
  if (typeof value !== 'string' || !normalizedRepositoryPath(value)) {
    errors.push(`${scope} must be a normalized repository-relative path${
      allowNull ? ' or null' : ''
    }`);
  }
}

function validateRepositoryPathList(
  value: unknown,
  scope: string,
  errors: string[],
  requireNonempty = false,
): string[] {
  if (!isStringArray(value)) {
    errors.push(`${scope} must be an array of repository-relative paths`);
    return [];
  }
  if (requireNonempty && value.length === 0) errors.push(`${scope} must not be empty`);
  if (new Set(value).size !== value.length) errors.push(`${scope} must contain unique paths`);
  for (const [index, path] of value.entries()) {
    validateRepositoryPath(path, `${scope}[${index}]`, errors);
  }
  return value;
}

function lifecycle(value: string): value is Lifecycle {
  return (LIFECYCLES as readonly string[]).includes(value);
}

function rank(value: string): number {
  return (LIFECYCLES as readonly string[]).indexOf(value);
}

function parseJson(path: string): unknown {
  return JSON.parse(readFileSync(path, 'utf8')) as unknown;
}

function gitInventory(root: string): { paths: string[]; error: string } {
  const result = spawnSync(
    'git',
    ['-C', root, 'ls-files', '-z', '--cached', '--others', '--exclude-standard'],
    { encoding: 'buffer', maxBuffer: 32 * 1024 * 1024 },
  );
  if (result.status !== 0) {
    return {
      paths: [],
      error: result.stderr.toString('utf8').trim()
        || result.error?.message
        || `git exited ${String(result.status)}`,
    };
  }
  const paths = result.stdout
    .toString('utf8')
    .split('\0')
    .filter(Boolean);
  return { paths: sortedUnique(paths), error: '' };
}

function validateCoreManifestShape(value: unknown): string[] {
  const errors: string[] = [];
  if (!exactKeys(value, [
    'manifest_format',
    'core',
    'manual_execution_binding',
    'files',
    'checker_paths',
    'reference_documents',
    'bundle_targets',
  ])) {
    errors.push('core manifest top-level keys do not match aleph-core-manifest/v1');
  }
  if (!isRecord(value)) return errors;
  if (value.manifest_format !== 'aleph-core-manifest/v1') {
    errors.push('manifest_format must be aleph-core-manifest/v1');
  }
  if (!exactKeys(value.core, [
    'id',
    'version',
    'adapter_protocol_version',
    'run_format_version',
    'digest_algorithm',
  ])) {
    errors.push('core fields are malformed');
  } else if (isRecord(value.core)) {
    validateIdentifier(value.core.id, 'core.id', errors);
    validateVersion(value.core.version, 'core.version', errors);
    validateVersion(
      value.core.adapter_protocol_version,
      'core.adapter_protocol_version',
      errors,
    );
    validateVersion(value.core.run_format_version, 'core.run_format_version', errors);
    if (value.core.digest_algorithm !== 'sha256-path-file-digest-v1') {
      errors.push('core.digest_algorithm must be sha256-path-file-digest-v1');
    }
  }
  if (!exactKeys(value.manual_execution_binding, [
    'id',
    'version',
    'lifecycle',
    'paths',
  ])) {
    errors.push('manual_execution_binding fields are malformed');
  } else if (isRecord(value.manual_execution_binding)) {
    validateIdentifier(
      value.manual_execution_binding.id,
      'manual_execution_binding.id',
      errors,
    );
    validateVersion(
      value.manual_execution_binding.version,
      'manual_execution_binding.version',
      errors,
    );
    if (value.manual_execution_binding.lifecycle !== 'sanctioned') {
      errors.push('manual_execution_binding.lifecycle must be sanctioned');
    }
    validateRepositoryPathList(
      value.manual_execution_binding.paths,
      'manual_execution_binding.paths',
      errors,
      true,
    );
  }
  if (!exactKeys(value.files, [
    'core',
    'adapter',
    'packaging',
    'repository_administration',
  ])) {
    errors.push('files classifications are malformed');
  } else if (isRecord(value.files)) {
    validateRepositoryPathList(value.files.core, 'files.core', errors);
    validateRepositoryPathList(value.files.packaging, 'files.packaging', errors);
    validateRepositoryPathList(
      value.files.repository_administration,
      'files.repository_administration',
      errors,
    );
    if (!isRecord(value.files.adapter)) {
      errors.push('files.adapter must be an object of adapter path arrays');
    } else {
      for (const [adapterId, paths] of Object.entries(value.files.adapter)) {
        validateIdentifier(adapterId, `files.adapter key ${adapterId || '(blank)'}`, errors);
        validateRepositoryPathList(
          paths,
          `files.adapter.${adapterId || '(blank)'}`,
          errors,
          true,
        );
      }
    }
  }
  validateRepositoryPathList(value.checker_paths, 'checker_paths', errors, true);
  validateRepositoryPathList(value.reference_documents, 'reference_documents', errors);
  if (!Array.isArray(value.bundle_targets) || value.bundle_targets.length === 0) {
    errors.push('bundle_targets must be a nonempty array');
  } else {
    for (const [index, target] of value.bundle_targets.entries()) {
      if (!exactKeys(target, ['id', 'version', 'adapter_id'])) {
        errors.push(`bundle_targets[${index}] fields are malformed`);
      } else if (isRecord(target)) {
        validateIdentifier(target.id, `bundle_targets[${index}].id`, errors);
        validateVersion(
          target.version,
          `bundle_targets[${index}].version`,
          errors,
        );
        validateIdentifier(
          target.adapter_id,
          `bundle_targets[${index}].adapter_id`,
          errors,
        );
      }
    }
  }
  return errors;
}

function asCoreManifest(value: unknown): CoreManifest | null {
  return validateCoreManifestShape(value).length === 0
    ? value as CoreManifest
    : null;
}

function adapterShapeErrors(value: unknown): string[] {
  const errors: string[] = [];
  if (!exactKeys(value, [
    '$schema',
    'manifest_format',
    'adapter',
    'core_consumption',
    'owned_paths',
    'references',
    'entrypoints',
    'installation',
    'capabilities',
    'full_mode',
    'profiles',
    'evidence',
  ])) {
    errors.push('top-level keys do not match aleph-adapter-manifest/v1');
  }
  if (!isRecord(value)) return errors;
  if (value.$schema !== '../../adapter-protocol/adapter.schema.json') {
    errors.push('$schema must reference ../../adapter-protocol/adapter.schema.json');
  }
  if (value.manifest_format !== 'aleph-adapter-manifest/v1') {
    errors.push('manifest_format must be aleph-adapter-manifest/v1');
  }
  if (!exactKeys(value.adapter, [
    'id',
    'version',
    'host',
    'protocol_version',
    'run_format_version',
    'lifecycle',
  ])) {
    errors.push('adapter identity fields are malformed');
  } else if (isRecord(value.adapter)) {
    validateIdentifier(value.adapter.id, 'adapter.id', errors);
    validateVersion(value.adapter.version, 'adapter.version', errors);
    validateIdentifier(value.adapter.host, 'adapter.host', errors);
    validateVersion(value.adapter.protocol_version, 'adapter.protocol_version', errors);
    validateVersion(value.adapter.run_format_version, 'adapter.run_format_version', errors);
    if (typeof value.adapter.lifecycle !== 'string'
      || !lifecycle(value.adapter.lifecycle)) {
      errors.push('adapter.lifecycle must be planned, implemented, validated, or sanctioned');
    }
  }
  if (!exactKeys(value.core_consumption, [
    'mode',
    'allow_overrides',
    'mutable_fetch',
    'overrides',
    'duplicates',
    'transformations',
  ])) {
    errors.push('core_consumption fields are malformed');
  } else if (isRecord(value.core_consumption)) {
    if (typeof value.core_consumption.mode !== 'string') {
      errors.push('core_consumption.mode must be a string');
    }
    if (typeof value.core_consumption.allow_overrides !== 'boolean') {
      errors.push('core_consumption.allow_overrides must be a boolean');
    }
    if (typeof value.core_consumption.mutable_fetch !== 'boolean') {
      errors.push('core_consumption.mutable_fetch must be a boolean');
    }
    validateRepositoryPathList(
      value.core_consumption.overrides,
      'core_consumption.overrides',
      errors,
    );
    validateRepositoryPathList(
      value.core_consumption.duplicates,
      'core_consumption.duplicates',
      errors,
    );
    validateRepositoryPathList(
      value.core_consumption.transformations,
      'core_consumption.transformations',
      errors,
    );
  }
  validateRepositoryPathList(value.owned_paths, 'owned_paths', errors, true);
  validateRepositoryPathList(value.references, 'references', errors);
  if (!Array.isArray(value.entrypoints) || value.entrypoints.length === 0) {
    errors.push('entrypoints must be a nonempty array');
  } else {
    for (const [index, entrypoint] of value.entrypoints.entries()) {
      if (!exactKeys(entrypoint, ['id', 'kind', 'state', 'path'])) {
        errors.push(`entrypoints[${index}] fields are malformed`);
      } else if (isRecord(entrypoint)) {
        if (typeof entrypoint.id !== 'string' || entrypoint.id.length === 0) {
          errors.push(`entrypoints[${index}].id must be a nonempty string`);
        }
        if (typeof entrypoint.kind !== 'string'
          || !(ENTRYPOINT_KINDS as readonly string[]).includes(entrypoint.kind)) {
          errors.push(
            `entrypoints[${index}].kind must be one of ${ENTRYPOINT_KINDS.join(', ')}`,
          );
        }
        if (typeof entrypoint.state !== 'string' || !lifecycle(entrypoint.state)) {
          errors.push(`entrypoints[${index}].state is not a valid lifecycle`);
        }
        validateRepositoryPath(
          entrypoint.path,
          `entrypoints[${index}].path`,
          errors,
          true,
        );
      }
    }
  }
  if (!exactKeys(value.installation, ['state', 'path'])) {
    errors.push('installation fields are malformed');
  } else if (isRecord(value.installation)) {
    if (typeof value.installation.state !== 'string'
      || !lifecycle(value.installation.state)) {
      errors.push('installation.state is not a valid lifecycle');
    }
    validateRepositoryPath(value.installation.path, 'installation.path', errors, true);
  }
  if (!isRecord(value.capabilities)) {
    errors.push('capabilities must be an object');
  } else {
    if (!sameStrings(Object.keys(value.capabilities), [...CAPABILITIES])) {
      errors.push('capabilities must contain exactly the thirteen protocol keys');
    }
    for (const capability of CAPABILITIES) {
      const record = value.capabilities[capability];
      if (!exactKeys(record, ['state', 'evidence'])) {
        errors.push(`capabilities.${capability} fields are malformed`);
      } else if (isRecord(record)) {
        if (typeof record.state !== 'string' || !lifecycle(record.state)) {
          errors.push(`capabilities.${capability}.state is not a valid lifecycle`);
        }
        validateRepositoryPathList(
          record.evidence,
          `capabilities.${capability}.evidence`,
          errors,
        );
      }
    }
  }
  if (!exactKeys(value.full_mode, ['claimed'])
    || !isRecord(value.full_mode)
    || typeof value.full_mode.claimed !== 'boolean') {
    errors.push('full_mode must contain one boolean claimed field');
  }
  if (!Array.isArray(value.profiles)) {
    errors.push('profiles must be an array');
  } else {
    for (const [index, profile] of value.profiles.entries()) {
      if (!exactKeys(profile, [
        'id',
        'state',
        'path',
        'runtime_requirements',
        'model_mapping',
        'effort_mapping',
        'evidence',
      ])) {
        errors.push(`profiles[${index}] fields are malformed`);
        continue;
      }
      if (!isRecord(profile)) continue;
      validateIdentifier(profile.id, `profiles[${index}].id`, errors);
      if (typeof profile.state !== 'string' || !lifecycle(profile.state)) {
        errors.push(`profiles[${index}].state is not a valid lifecycle`);
      }
      validateRepositoryPath(profile.path, `profiles[${index}].path`, errors, true);
      if (!isStringArray(profile.runtime_requirements)
        || profile.runtime_requirements.some((item) => item.length === 0)) {
        errors.push(`profiles[${index}].runtime_requirements must be nonempty strings`);
      }
      if (!isRecord(profile.model_mapping)) {
        errors.push(`profiles[${index}].model_mapping must be an object`);
      }
      if (!isRecord(profile.effort_mapping)) {
        errors.push(`profiles[${index}].effort_mapping must be an object`);
      }
      validateRepositoryPathList(
        profile.evidence,
        `profiles[${index}].evidence`,
        errors,
      );
    }
  }
  if (!exactKeys(value.evidence, ['implementation', 'validation', 'sanction'])) {
    errors.push('evidence fields are malformed');
  } else if (isRecord(value.evidence)) {
    for (const key of ['implementation', 'validation', 'sanction']) {
      validateRepositoryPathList(value.evidence[key], `evidence.${key}`, errors);
    }
  }
  return errors;
}

function asAdapterManifest(value: unknown): AdapterManifest | null {
  return adapterShapeErrors(value).length === 0
    ? value as AdapterManifest
    : null;
}

function pathOwner(
  ownership: Map<string, PathOwner>,
  path: string,
): PathOwner | undefined {
  return ownership.get(path);
}

function referenceAllowed(
  ownership: Map<string, PathOwner>,
  path: string,
  adapterId: string,
): boolean {
  const owner = pathOwner(ownership, path);
  return owner?.classification === 'core'
    || (owner?.classification === 'adapter' && owner.adapterId === adapterId);
}

function allAdapterReferences(manifest: AdapterManifest): string[] {
  const paths = [
    ...manifest.references,
    ...manifest.evidence.implementation,
    ...manifest.evidence.validation,
    ...manifest.evidence.sanction,
  ];
  for (const entrypoint of manifest.entrypoints) {
    if (entrypoint.path) paths.push(entrypoint.path);
  }
  if (manifest.installation.path) paths.push(manifest.installation.path);
  for (const capability of Object.values(manifest.capabilities)) {
    paths.push(...capability.evidence);
  }
  for (const profile of manifest.profiles) {
    if (isRecord(profile) && typeof profile.path === 'string') paths.push(profile.path);
    if (isRecord(profile) && isStringArray(profile.evidence)) paths.push(...profile.evidence);
  }
  return sortedUnique(paths);
}

function lifecycleProblems(
  root: string,
  adapterId: string,
  manifest: AdapterManifest,
  ownership: Map<string, PathOwner>,
): string[] {
  const problems: string[] = [];
  const state = manifest.adapter.lifecycle;
  if (!lifecycle(state)) {
    problems.push(`adapter lifecycle "${state}" is invalid`);
    return problems;
  }
  const planned = state === 'planned';
  if (manifest.adapter.id !== adapterId || manifest.adapter.host !== adapterId) {
    problems.push('adapter id and host must match its inventory key');
  }
  for (const entrypoint of manifest.entrypoints) {
    if (!lifecycle(entrypoint.state) || entrypoint.state !== state) {
      problems.push(`entrypoint ${entrypoint.id} state must equal adapter lifecycle ${state}`);
    }
    if (planned && entrypoint.path !== null) {
      problems.push(`planned entrypoint ${entrypoint.id} must have path null`);
    }
    if (!planned) {
      if (typeof entrypoint.path !== 'string') {
        problems.push(`nonplanned entrypoint ${entrypoint.id} needs a path`);
      } else if (!referenceAllowed(ownership, entrypoint.path, adapterId)
        || pathOwner(ownership, entrypoint.path)?.adapterId !== adapterId
        || !existsSync(join(root, entrypoint.path))) {
        problems.push(`entrypoint ${entrypoint.id} path must resolve inside its adapter`);
      }
    }
  }
  if (!lifecycle(manifest.installation.state) || manifest.installation.state !== state) {
    problems.push(`installation state must equal adapter lifecycle ${state}`);
  }
  if (planned && manifest.installation.path !== null) {
    problems.push('planned installation path must be null');
  }
  if (!planned) {
    const path = manifest.installation.path;
    if (typeof path !== 'string'
      || !referenceAllowed(ownership, path, adapterId)
      || pathOwner(ownership, path)?.adapterId !== adapterId
      || !existsSync(join(root, path))) {
      problems.push('nonplanned installation path must resolve inside its adapter');
    }
  }
  for (const capability of CAPABILITIES) {
    const record = manifest.capabilities[capability];
    if (!record || !lifecycle(record.state) || record.state !== state) {
      problems.push(`${capability} state must equal adapter lifecycle ${state}`);
      continue;
    }
    if (planned && record.evidence.length > 0) {
      problems.push(`planned capability ${capability} must have empty evidence`);
    }
    if (!planned && record.evidence.length === 0) {
      problems.push(`${state} capability ${capability} needs evidence`);
    }
  }
  if (planned !== !manifest.full_mode.claimed) {
    problems.push(
      planned
        ? 'planned adapter may not claim full mode'
        : `${state} complete adapter must claim full mode`,
    );
  }
  if (planned && manifest.profiles.length > 0) {
    problems.push('planned adapter profiles must be empty');
  }
  if (!planned && manifest.profiles.length === 0) {
    problems.push(`${state} adapter needs at least one host profile`);
  }
  for (const profile of manifest.profiles) {
    if (!isRecord(profile)) continue;
    const profileId = typeof profile.id === 'string' ? profile.id : '(unknown)';
    if (profile.state !== state) {
      problems.push(`profile ${profileId} state must equal adapter lifecycle ${state}`);
    }
    if (!planned) {
      if (typeof profile.path !== 'string'
        || pathOwner(ownership, profile.path)?.classification !== 'adapter'
        || pathOwner(ownership, profile.path)?.adapterId !== adapterId
        || !existsSync(join(root, profile.path))) {
        problems.push(`profile ${profileId} path must resolve inside its adapter`);
      }
      if (!isStringArray(profile.evidence) || profile.evidence.length === 0) {
        problems.push(`${state} profile ${profileId} needs evidence`);
      }
    }
  }
  const evidence = manifest.evidence;
  if (planned) {
    if (evidence.implementation.length
      || evidence.validation.length
      || evidence.sanction.length) {
      problems.push('planned adapter lifecycle evidence must be empty');
    }
  } else {
    if (evidence.implementation.length === 0) {
      problems.push(`${state} adapter needs implementation evidence`);
    }
    if (rank(state) >= rank('validated') && evidence.validation.length === 0) {
      problems.push(`${state} adapter needs validation evidence`);
    }
    if (state === 'sanctioned' && evidence.sanction.length === 0) {
      problems.push('sanctioned adapter needs authority sanction evidence');
    }
    if (state === 'implemented'
      && (evidence.validation.length > 0 || evidence.sanction.length > 0)) {
      problems.push('implemented adapter may not carry validation or sanction evidence');
    }
    if (state === 'validated' && evidence.sanction.length > 0) {
      problems.push('validated adapter may not carry sanction evidence');
    }
  }
  for (const path of allAdapterReferences(manifest)) {
    if (!referenceAllowed(ownership, path, adapterId)
      || !existsSync(join(root, path))) {
      problems.push(`typed reference ${path} does not resolve to Core or ${adapterId}`);
    }
  }
  return sortedUnique(problems);
}

function emptyReport(): Omit<CoreBoundaryReport, 'result' | 'checks'> {
  return {
    inventory: {
      total: 0,
      core: 0,
      adapters: {},
      packaging: 0,
      repositoryAdministration: 0,
    },
    digests: {
      algorithm: DIGEST_ALGORITHM,
      core: '',
      checker: '',
      manualExecutionBinding: '',
      adapters: {},
      bundles: {},
    },
    adapters: [],
  };
}

export function validateCoreBoundary(
  options: ValidateCoreBoundaryOptions = {},
): CoreBoundaryReport {
  const root = resolve(options.root || DEFAULT_ROOT);
  const results = new ResultCollector('CORE-BOUNDARY');
  const extra = emptyReport();
  let coreValue: unknown = null;

  results.run('CB1', 'core manifest', (fail) => {
    const path = join(root, 'core.manifest.json');
    if (!existsSync(path)) {
      fail('core.manifest.json is missing');
      return 'core manifest checked';
    }
    try {
      coreValue = parseJson(path);
    } catch (error) {
      fail(`core.manifest.json is not valid JSON: ${
        error instanceof Error ? error.message : String(error)
      }`);
      return 'core manifest checked';
    }
    for (const error of validateCoreManifestShape(coreValue)) fail(error);
    return 'core manifest format and required fields are valid';
  });

  const manifest = asCoreManifest(coreValue);
  if (!manifest) return results.report(extra);
  const inventory = gitInventory(root);
  const ownership = new Map<string, PathOwner>();
  const classifiedPaths: string[] = [];
  const duplicatePaths = new Set<string>();

  function classify(paths: string[], owner: PathOwner): void {
    for (const path of paths) {
      classifiedPaths.push(path);
      if (ownership.has(path)) duplicatePaths.add(path);
      else ownership.set(path, owner);
    }
  }

  classify(manifest.files.core, { classification: 'core' });
  for (const [adapterId, paths] of Object.entries(manifest.files.adapter)) {
    classify(paths, { classification: 'adapter', adapterId });
  }
  classify(manifest.files.packaging, { classification: 'packaging' });
  classify(manifest.files.repository_administration, {
    classification: 'repository-administration',
  });

  extra.inventory = {
    total: inventory.paths.length,
    core: manifest.files.core.length,
    adapters: Object.fromEntries(
      Object.entries(manifest.files.adapter).map(([id, paths]) => [id, paths.length]),
    ),
    packaging: manifest.files.packaging.length,
    repositoryAdministration: manifest.files.repository_administration.length,
  };

  results.run('CB2', 'inventory classification', (fail) => {
    if (inventory.error) {
      fail(`git inventory failed: ${inventory.error}`);
      return 'inventory checked';
    }
    for (const path of classifiedPaths) {
      if (!normalizedRepositoryPath(path)) fail(`classified path is not normalized: ${path}`);
    }
    for (const path of duplicatePaths) fail(`path has multiple classifications: ${path}`);
    const actual = new Set(inventory.paths);
    for (const path of inventory.paths) {
      if (!ownership.has(path)) fail(`unclassified tracked/nonignored path: ${path}`);
      if (!normalizedRepositoryPath(path)) fail(`inventory path is not normalized: ${path}`);
      const absolute = join(root, path);
      if (!existsSync(absolute)) fail(`inventoried path is missing: ${path}`);
      else if (lstatSync(absolute).isSymbolicLink()) fail(`symlink is not allowed: ${path}`);
      else if (!lstatSync(absolute).isFile()) fail(`inventory entry is not a file: ${path}`);
    }
    for (const path of classifiedPaths) {
      if (!actual.has(path)) fail(`classified path is absent from git inventory: ${path}`);
    }
    return `${inventory.paths.length} tracked and nonignored untracked files have exactly one classification`;
  });

  results.run('CB3', 'Core completeness and class boundaries', (fail) => {
    const requiredCoreRoots = [
      'AGENTS.md',
      'README.md',
      'package.json',
      'package-lock.json',
      'tsconfig.json',
    ];
    for (const path of inventory.paths) {
      const owner = pathOwner(ownership, path);
      if (
        path.startsWith('docs/')
        || path.startsWith('scripts/')
        || path.startsWith('adapter-protocol/')
        || requiredCoreRoots.includes(path)
      ) {
        if (owner?.classification !== 'core') fail(`Core-owned path is not Core: ${path}`);
      }
      if (path === 'core.manifest.json'
        || path === 'adapters/README.md'
        || path.startsWith('packaging/')) {
        if (owner?.classification !== 'packaging') {
          fail(`packaging path is misclassified: ${path}`);
        }
      }
      if (path === '.gitattributes'
        || path === '.gitignore'
        || path.startsWith('.github/')) {
        if (owner?.classification !== 'repository-administration') {
          fail(`repository administration path is misclassified: ${path}`);
        }
      }
      const adapterMatch = /^adapters\/([^/]+)\/(.+)$/.exec(path);
      if (adapterMatch) {
        const adapterId = adapterMatch[1];
        if (owner?.classification !== 'adapter' || owner.adapterId !== adapterId) {
          fail(`adapter path is not owned by ${adapterId}: ${path}`);
        }
      }
    }
    for (const required of [
      'docs/fixtures/run-slice-2/README.md',
      'docs/fixtures/slice-1/precis.md',
      'docs/fixtures/slice-2/precis.md',
      'scripts/test-conformance-mutations.ts',
      'scripts/test-core-boundary-mutations.ts',
      'scripts/validate-core-boundary.ts',
    ]) {
      if (pathOwner(ownership, required)?.classification !== 'core') {
        fail(`required Core evidence/checker path is absent from Core: ${required}`);
      }
    }
    for (const path of manifest.manual_execution_binding.paths) {
      if (pathOwner(ownership, path)?.classification !== 'core'
        || !existsSync(join(root, path))) {
        fail(`manual binding path must resolve to Core: ${path}`);
      }
    }
    return 'doctrine, contracts, fixtures, goldens, checkers, and manual binding remain in Core';
  });

  results.run('CB4', 'checker and typed manifest references', (fail) => {
    for (const path of manifest.checker_paths) {
      if (!normalizedRepositoryPath(path)) fail(`checker path is not normalized: ${path}`);
      if (pathOwner(ownership, path)?.classification !== 'core') {
        fail(`checker path is not Core: ${path}`);
      }
      if (!existsSync(join(root, path))) fail(`checker path does not resolve: ${path}`);
    }
    for (const path of inventory.paths.filter((item) => (
      item.startsWith('scripts/') && item.endsWith('.ts')
    ))) {
      if (!manifest.checker_paths.includes(path)) {
        fail(`TypeScript checker surface is absent from checker_paths: ${path}`);
      }
    }
    for (const path of manifest.reference_documents) {
      const owner = pathOwner(ownership, path);
      if (!owner || !existsSync(join(root, path))) {
        fail(`reference document does not resolve: ${path}`);
      }
    }
    return 'checker and typed boundary references resolve to classified paths';
  });

  const adapters = new Map<string, AdapterManifest>();
  results.run('CB5', 'adapter manifest shape', (fail) => {
    for (const [adapterId, paths] of Object.entries(manifest.files.adapter)) {
      const manifestPath = `adapters/${adapterId}/adapter.manifest.json`;
      if (!paths.includes(manifestPath)) {
        fail(`${adapterId} inventory does not include ${manifestPath}`);
        continue;
      }
      let value: unknown;
      try {
        value = parseJson(join(root, manifestPath));
      } catch (error) {
        fail(`${manifestPath} is not valid JSON: ${
          error instanceof Error ? error.message : String(error)
        }`);
        continue;
      }
      for (const error of adapterShapeErrors(value)) fail(`${adapterId}: ${error}`);
      const adapter = asAdapterManifest(value);
      if (!adapter) continue;
      if (adapter.adapter.protocol_version !== manifest.core.adapter_protocol_version) {
        fail(`${adapterId}: protocol version disagrees with Core manifest`);
      }
      if (adapter.adapter.run_format_version !== manifest.core.run_format_version) {
        fail(`${adapterId}: run-format version disagrees with Core manifest`);
      }
      adapters.set(adapterId, adapter);
    }
    const schemaPath = 'adapter-protocol/adapter.schema.json';
    try {
      const schema = parseJson(join(root, schemaPath));
      if (!isRecord(schema) || schema.$schema !== 'https://json-schema.org/draft/2020-12/schema') {
        fail('adapter.schema.json is not a Draft 2020-12 schema');
      }
    } catch (error) {
      fail(`adapter.schema.json is malformed: ${
        error instanceof Error ? error.message : String(error)
      }`);
    }
    return 'adapter manifests and protocol schema are structurally valid';
  });

  const preflight = new Map<string, string[]>();
  results.run('CB6', 'adapter lifecycle honesty', (fail) => {
    for (const [adapterId, adapter] of adapters) {
      const problems = lifecycleProblems(root, adapterId, adapter, ownership);
      preflight.set(adapterId, adapter.adapter.lifecycle === 'planned'
        ? ['adapter lifecycle is planned; no runnable entrypoint or installation exists']
        : problems);
      for (const problem of problems) fail(`${adapterId}: ${problem}`);
    }
    return 'lifecycle labels, capabilities, entrypoints, installation, profiles, and evidence agree';
  });

  results.run('CB7', 'adapter ownership and Core non-override', (fail) => {
    for (const [adapterId, adapter] of adapters) {
      const inventoryPaths = manifest.files.adapter[adapterId] || [];
      if (!sameStrings(adapter.owned_paths, inventoryPaths)) {
        fail(`${adapterId}: owned_paths must exactly equal its classified adapter inventory`);
      }
      const consumption = adapter.core_consumption;
      if (consumption.mode !== 'immutable-complete-core'
        || consumption.allow_overrides
        || consumption.mutable_fetch
        || consumption.overrides.length
        || consumption.duplicates.length
        || consumption.transformations.length) {
        fail(`${adapterId}: Core override, duplication, transformation, or mutable fetch is forbidden`);
      }
      for (const path of adapter.owned_paths) {
        const owner = pathOwner(ownership, path);
        if (owner?.classification !== 'adapter' || owner.adapterId !== adapterId) {
          fail(`${adapterId}: owned path overlaps another class or adapter: ${path}`);
        }
      }
      for (const path of allAdapterReferences(adapter)) {
        if (!referenceAllowed(ownership, path, adapterId)
          || !existsSync(join(root, path))) {
          fail(`${adapterId}: unresolved or disallowed typed reference ${path}`);
        }
      }
    }
    return 'adapters own only their host paths and cannot override or duplicate Core';
  });

  results.run('CB8', 'foreign-adapter exclusion', (fail) => {
    const adapterIds = [...adapters.keys()];
    for (const [adapterId, adapter] of adapters) {
      const payload = adapter.owned_paths
        .map((path) => readFileSync(join(root, path), 'utf8'))
        .join('\n');
      for (const foreignId of adapterIds.filter((id) => id !== adapterId)) {
        const forbiddenPaths = [
          `adapters/${foreignId}/`,
          `aleph-for-${foreignId}`,
        ];
        for (const token of forbiddenPaths) {
          if (payload.includes(token)) {
            fail(`${adapterId}: adapter payload contains foreign-adapter token ${token}`);
          }
        }
        const foreignName = new RegExp(
          `(^|[^A-Za-z0-9])${foreignId.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}([^A-Za-z0-9]|$)`,
          'i',
        );
        if (foreignName.test(payload)) {
          fail(`${adapterId}: adapter payload names foreign adapter or host ${foreignId}`);
        }
        for (const value of stringLeaves(adapter)) {
          if (forbiddenPaths.some((token) => value.includes(token))
            || foreignName.test(value)) {
            fail(
              `${adapterId}: decoded adapter manifest names foreign adapter or host `
              + foreignId,
            );
            break;
          }
        }
        for (const path of allAdapterReferences(adapter)) {
          if (pathOwner(ownership, path)?.adapterId === foreignId) {
            fail(`${adapterId}: typed reference reaches foreign adapter ${foreignId}: ${path}`);
          }
        }
      }
    }
    for (const target of manifest.bundle_targets) {
      const foreignPaths = Object.entries(manifest.files.adapter)
        .filter(([id]) => id !== target.adapter_id)
        .flatMap(([, paths]) => paths);
      const selected = new Set([
        ...manifest.files.core,
        ...(manifest.files.adapter[target.adapter_id] || []),
      ]);
      for (const path of foreignPaths) {
        if (selected.has(path)) fail(`${target.id}: bundle includes foreign adapter path ${path}`);
      }
    }
    return 'selected-adapter payloads, typed dependencies, and bundle inventories exclude foreign adapters';
  });

  results.run('CB9', 'bundle digests and Core equality', (fail) => {
    const coreDigest = treeDigest(root, manifest.files.core);
    const checkerDigest = treeDigest(root, manifest.checker_paths);
    const manualDigest = treeDigest(root, manifest.manual_execution_binding.paths);
    extra.digests.core = coreDigest;
    extra.digests.checker = checkerDigest;
    extra.digests.manualExecutionBinding = manualDigest;
    const coreDigests: string[] = [];
    const targetIds = new Set<string>();
    const targetAdapterIds = manifest.bundle_targets.map((target) => target.adapter_id);
    const adapterIds = Object.keys(manifest.files.adapter);
    if (!sameStrings(targetAdapterIds, adapterIds)
      || new Set(targetAdapterIds).size !== targetAdapterIds.length) {
      fail('bundle targets must select every registered adapter exactly once');
    }
    for (const target of manifest.bundle_targets) {
      if (targetIds.has(target.id)) fail(`duplicate bundle target id ${target.id}`);
      targetIds.add(target.id);
      if (target.id !== `aleph-for-${target.adapter_id}`) {
        fail(`${target.id}: bundle id must be aleph-for-${target.adapter_id}`);
      }
      const adapter = adapters.get(target.adapter_id);
      const adapterPaths = manifest.files.adapter[target.adapter_id];
      if (!adapter || !adapterPaths) {
        fail(`${target.id}: selected adapter ${target.adapter_id} is not registered`);
        continue;
      }
      const plan = buildBundlePlan(
        root,
        manifest,
        target,
        adapter,
        options.bundleProvenance?.[target.id],
      );
      const targetCoreDigest = plan.coreDigest;
      const adapterDigest = plan.adapterDigest;
      coreDigests.push(targetCoreDigest);
      extra.digests.adapters[target.adapter_id] = adapterDigest;
      extra.digests.bundles[target.id] = {
        adapterId: target.adapter_id,
        coreDigest: targetCoreDigest,
        adapterDigest,
        payloadDigest: plan.payloadDigest,
        lockProjectionDigest: plan.lockDigest,
        bundleDigest: plan.bundleDigest,
      };
    }
    if (new Set(coreDigests).size > 1) {
      fail(`bundle Core digests differ: ${coreDigests.join(', ')}`);
    }
    if (coreDigests.some((digest) => digest !== coreDigest)) {
      fail('a bundle Core digest differs from the complete source Core digest');
    }
    return `all bundle targets share Core digest ${coreDigest}`;
  });

  extra.adapters = [...adapters.entries()]
    .sort(([left], [right]) => left.localeCompare(right, 'en'))
    .map(([id, adapter]) => {
      const reasons = preflight.get(id) || [];
      const ready = adapter.adapter.lifecycle !== 'planned' && reasons.length === 0;
      return {
        id,
        lifecycle: adapter.adapter.lifecycle,
        fullModeClaimed: adapter.full_mode.claimed,
        preflight: ready ? 'READY' : 'NOT-READY',
        preflightReasons: reasons,
      };
    });

  if (options.preflightAdapter) {
    results.run('CBP', 'full-mode preflight', (fail) => {
      const summary = extra.adapters.find((item) => item.id === options.preflightAdapter);
      if (!summary) {
        fail(`adapter ${options.preflightAdapter} is not registered`);
      } else if (summary.preflight !== 'READY') {
        fail(`${summary.id} full-mode preflight failed: ${summary.preflightReasons.join('; ')}`);
      }
      return `${options.preflightAdapter} is full-mode preflight ready`;
    });
  }

  return results.report(extra);
}

interface CliOptions {
  root: string;
  json: boolean;
  preflightAdapter?: string;
  help: boolean;
  error: string;
}

function parseCli(args: string[]): CliOptions {
  const options: CliOptions = {
    root: DEFAULT_ROOT,
    json: false,
    help: false,
    error: '',
  };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === '--json') options.json = true;
    else if (arg === '--help' || arg === '-h') options.help = true;
    else if (arg === '--root') {
      const value = args[index + 1];
      if (!value) options.error = '--root requires a directory';
      else {
        options.root = resolve(value);
        index += 1;
      }
    } else if (arg === '--preflight') {
      const value = args[index + 1];
      if (!value) options.error = '--preflight requires an adapter id';
      else {
        options.preflightAdapter = value;
        index += 1;
      }
    } else {
      options.error = `unknown argument "${arg}"`;
    }
  }
  return options;
}

function printHuman(report: CoreBoundaryReport): void {
  for (const check of report.checks) {
    console.log(`${check.status} ${check.scope} ${check.id} ${check.message}`);
  }
  if (report.digests.core) {
    console.log(`DIGEST core ${report.digests.core}`);
    console.log(`DIGEST checker ${report.digests.checker}`);
    console.log(`DIGEST manual-binding ${report.digests.manualExecutionBinding}`);
    for (const [id, digest] of Object.entries(report.digests.adapters)) {
      console.log(`DIGEST adapter:${id} ${digest}`);
    }
    for (const [id, record] of Object.entries(report.digests.bundles)) {
      console.log(`DIGEST bundle:${id} ${record.bundleDigest}`);
    }
  }
  for (const adapter of report.adapters) {
    console.log(
      `PREFLIGHT ${adapter.id} ${adapter.preflight} lifecycle=${adapter.lifecycle}`
      + (adapter.preflightReasons.length
        ? ` (${adapter.preflightReasons.join('; ')})`
        : ''),
    );
  }
  console.log(`RESULT: ${report.result}`);
}

function main(): void {
  const options = parseCli(process.argv.slice(2));
  if (options.help) {
    console.log(
      'Usage: node scripts/validate-core-boundary.ts '
      + '[--root <repo>] [--preflight <adapter-id>] [--json]',
    );
    process.exit(0);
  }
  if (options.error) {
    console.error(options.error);
    process.exit(2);
  }
  const report = validateCoreBoundary({
    root: options.root,
    preflightAdapter: options.preflightAdapter,
  });
  if (options.json) console.log(JSON.stringify(report, null, 2));
  else printHuman(report);
  process.exit(report.result === 'PASS' ? 0 : 1);
}

if (resolve(process.argv[1] || '') === SCRIPT_PATH) main();
