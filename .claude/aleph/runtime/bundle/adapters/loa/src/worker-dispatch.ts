#!/usr/bin/env node

import {
  chmodSync,
  existsSync,
  lstatSync,
  readFileSync,
} from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  LOA_ADAPTER_ID,
  LOA_CLAUDE_CODE_DISPATCH_FORMAT,
  LOA_HOST_FORMAT,
  LOA_MODEL_SLOTS,
  LOA_REQUIRED_HOST_CAPABILITIES,
  type JsonValue,
  type ClaudeCodeDispatchEvidence,
  type LoaHostCapabilities,
  type WorkerDispatchReceipt,
  type WorkerRequest,
} from './types.ts';
import {
  assertNoSymlinkComponents,
  readJsonFile,
  readStableRegularFile,
  sha256Digest,
  stableJson,
  stableJsonBytes,
  writeFileAtomic,
  writeJsonAtomic,
} from './fs.ts';
import { readRunState } from './run-control.ts';
import {
  runtimeSnapshotPath,
  verifyRuntimeSnapshot,
} from './runtime-snapshot.ts';
import { verifyWorkerBundle } from './worker-bundle.ts';
import {
  canonicalWorkerReturnRoot,
  contractExemplarToJsonSchema,
  validateWorkerReturn,
  type WorkerReturnResult,
} from './worker-return.ts';
import {
  buildClaudeCodeWorkerPrompt,
  invokeClaudeCodeWorker,
  isProviderPinnedClaudeModelId,
  parseClaudeCodeStream,
} from './claude-code-host.ts';

const SCRIPT_PATH = fileURLToPath(import.meta.url);
const INVOCATION_FORMAT = 'aleph-loa-native-worker-invocation/v1';
const NATIVE_DISPATCH_FORMAT = 'aleph-loa-native-worker-dispatch/v1';
const INVOCATION_FILE = 'invocation.json';
const CAPABILITIES_FILE = 'host-capabilities.json';
const NATIVE_DISPATCH_FILE = 'native-dispatch.json';
const NATIVE_RETURN_FILE = 'native-return.json';
const EVENT_STREAM_FILE = 'claude-stream.jsonl';

interface NativeResultPaths {
  dispatch_receipt_path: string;
  structured_return_path: string;
  event_stream_path: string;
}

interface RetainedHostCapabilityReceipt {
  path: string;
  digest: string;
}

/**
 * This is the exact object handed to Loa's native fresh-context/subagent
 * primitive. The worker receives no write path. Loa's installed skill, still
 * acting as the orchestrator, persists the primitive's returned receipt and
 * structured value to the two result paths after the native call completes.
 */
export interface LoaNativeWorkerInvocation {
  format: typeof INVOCATION_FORMAT;
  invocation_digest: string;
  request: WorkerRequest;
  request_digest: string;
  worker_bundle_root: string;
  worker_bundle_digest: string;
  host_capability_receipt: RetainedHostCapabilityReceipt;
  readable_paths: [string];
  writable_paths: [];
  inherit_context: false;
  require_fresh_context: true;
  require_exact_model_identity: true;
  model_identity: WorkerRequest['model_identity'];
  producer_context_id: string | null;
  result: NativeResultPaths;
  simulation: LoaHostCapabilities['simulation'];
}

export interface LoaNativeWorkerResult {
  receipt: WorkerDispatchReceipt;
  structured_return: JsonValue;
}

export interface LoaNativeDispatchRecord {
  format: typeof NATIVE_DISPATCH_FORMAT;
  invocation_digest: string;
  worker_bundle_digest: string;
  host_capability_receipt_digest: string;
  event_stream_digest: string | null;
  structured_return_digest: string;
  host_evidence: ClaudeCodeDispatchEvidence | null;
  receipt: WorkerDispatchReceipt;
}

/**
 * Host binding supplied by the installed Loa skill. There is deliberately no
 * default implementation: a host without a real fresh-context primitive must
 * fail preflight rather than reuse the orchestrator conversation.
 */
export interface LoaFreshContextHost {
  invokeFreshContext(invocation: LoaNativeWorkerInvocation): LoaNativeWorkerResult;
}

export interface DispatchLoaWorkerOptions {
  workerBundleRoot: string;
  returnRoot: string;
  hostCapabilities: LoaHostCapabilities;
  host: LoaFreshContextHost;
}

export interface LoaDispatchedWorkerResult extends WorkerReturnResult {
  receipt: WorkerDispatchReceipt;
  dispatchRecordPath: string;
}

export interface PrepareLoaWorkerHandoffOptions {
  workerBundleRoot: string;
  returnRoot: string;
  hostCapabilities: LoaHostCapabilities;
  hostCapabilitiesPath?: string;
}

export interface PreparedLoaWorkerHandoff {
  invocation: LoaNativeWorkerInvocation;
  invocationPath: string;
  nativeDispatchPath: string;
  nativeReturnPath: string;
  eventStreamPath: string;
}

export interface AcceptLoaWorkerHandoffOptions {
  workerBundleRoot: string;
  returnRoot: string;
}

export interface AcceptedLoaWorkerHandoff extends WorkerReturnResult {
  receipt: WorkerDispatchReceipt;
  dispatchRecordPath: string;
  invocationPath: string;
}

export interface DispatchedClaudeCodeHandoff {
  receipt: WorkerDispatchReceipt;
  evidence: ClaudeCodeDispatchEvidence;
  dispatchRecordPath: string;
  structuredReturnPath: string;
  eventStreamPath: string;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function exactKeys(value: unknown, keys: readonly string[]): value is Record<string, unknown> {
  if (!isRecord(value)) return false;
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  return actual.length === expected.length
    && actual.every((key, index) => key === expected[index]);
}

function canonicalFile(path: string, label: string): { value: unknown; bytes: Buffer } {
  const stable = readStableRegularFile(path);
  let value: unknown;
  try {
    value = JSON.parse(stable.bytes.toString('utf8')) as unknown;
  } catch (error) {
    throw new Error(`${label} is invalid JSON: ${error instanceof Error ? error.message : String(error)}`);
  }
  if (!stable.bytes.equals(stableJsonBytes(value))) {
    throw new Error(`${label} is not canonical JSON`);
  }
  return { value, bytes: stable.bytes };
}

function assertImmutableRegularFile(path: string, label: string): void {
  const stat = lstatSync(path);
  if (!stat.isFile() || stat.isSymbolicLink()) {
    throw new Error(`${label} is not a regular non-symlink file`);
  }
  if ((stat.mode & 0o222) !== 0) {
    throw new Error(`${label} must be immutable to the invoking worker`);
  }
}

function assertExactModelIdentity(value: unknown, slot: string): void {
  const fields = [
    'provider',
    'model_id',
    'resolved_version',
    'identity_kind',
    'immutable',
    'context',
    'effort',
    'budget',
    'cache',
    'batch',
    'fallback',
  ] as const;
  if (!exactKeys(value, fields)) {
    throw new Error(`Loa host model slot ${slot} fields are malformed`);
  }
  const model = value as Record<string, unknown>;
  for (const field of fields.filter((field) => ![
    'identity_kind',
    'immutable',
    'fallback',
  ].includes(field))) {
    if (typeof model[field] !== 'string'
      || !model[field].trim()
      || /(?:^|[^a-z0-9])(?:latest|current|default|recommended|rolling|auto)(?:[^a-z0-9]|$)/iu.test(model[field])) {
      throw new Error(`Loa host model slot ${slot}.${field} is empty or mutable`);
    }
  }
  if (model.immutable !== true || model.fallback !== false) {
    throw new Error(`Loa host model slot ${slot} permits mutation or fallback`);
  }
  const fixtureIdentity = model.identity_kind === 'fixture-simulated'
    && /^sha256:[0-9a-f]{64}$/u.test(String(model.resolved_version));
  const providerIdentity = model.identity_kind === 'provider-pinned-snapshot'
    && model.resolved_version === model.model_id
    && typeof model.model_id === 'string'
    && isProviderPinnedClaudeModelId(model.model_id);
  if (!(fixtureIdentity || providerIdentity)) {
    throw new Error(`Loa host model slot ${slot} has no exact immutable identity`);
  }
}

function assertHostCanDispatch(host: LoaHostCapabilities, request: WorkerRequest): void {
  if (!exactKeys(host, [
    'host_format',
    'host',
    'capabilities',
    'models',
    'runtime',
    'simulation',
  ])
    || host.host_format !== LOA_HOST_FORMAT
    || !exactKeys(host.host, ['id', 'version', 'build_id'])
    || host.host.id !== LOA_ADAPTER_ID
    || typeof host.host.version !== 'string'
    || !host.host.version.trim()
    || /(?:^|[^a-z0-9])(?:latest|current|default|recommended|rolling|auto)(?:[^a-z0-9]|$)/iu.test(host.host.version)
    || !/^sha256:[0-9a-f]{64}$/u.test(host.host.build_id)) {
    throw new Error('Loa host capability receipt identity is malformed or mutable');
  }
  if (!exactKeys(host.capabilities, LOA_REQUIRED_HOST_CAPABILITIES)
    || LOA_REQUIRED_HOST_CAPABILITIES.some((capability) => host.capabilities[capability] !== true)) {
    throw new Error('Loa host capability receipt does not prove the complete required capability set');
  }
  if (!exactKeys(host.models, LOA_MODEL_SLOTS)) {
    throw new Error('Loa host capability receipt does not resolve every model slot');
  }
  for (const slot of LOA_MODEL_SLOTS) assertExactModelIdentity(host.models[slot], slot);
  if (host.simulation !== null
    && (!exactKeys(host.simulation, ['kind'])
      || host.simulation.kind !== 'fixture-simulated')) {
    throw new Error('Loa host capability receipt has an invalid simulation marker');
  }
  for (const capability of [
    'fresh_context_workers',
    'context_inheritance_control',
    'read_only_worker_bundles',
    'structured_worker_returns',
    'exact_model_resolution',
  ] as const) {
    if (host.capabilities[capability] !== true) {
      throw new Error(`Loa host cannot dispatch full-mode worker: ${capability}`);
    }
  }
  if (!Object.values(host.models).some((model) => (
    stableJson(model) === stableJson(request.model_identity)
  ))) {
    throw new Error('worker exact model identity is absent from the host capability receipt');
  }
}

interface PinnedHostBinding {
  host: LoaHostCapabilities;
  receiptPath: string;
  receiptBytes: Buffer;
  receiptDigest: string;
}

function pinnedHostBinding(
  workerBundleRootInput: string,
  request: WorkerRequest,
): PinnedHostBinding {
  const workerBundleRoot = resolve(workerBundleRootInput);
  const runDir = dirname(dirname(dirname(workerBundleRoot)));
  if (workerBundleRoot !== join(
    runDir,
    'control',
    'worker-bundles',
    request.call_id,
  )) {
    throw new Error('worker bundle does not belong to a canonical retained run');
  }

  const state = readRunState(runDir);
  const snapshotPath = runtimeSnapshotPath(runDir);
  if (resolve(runDir, state.identity.runtime.snapshot_ref) !== snapshotPath) {
    throw new Error('run-state runtime snapshot reference is not canonical');
  }
  const snapshot = verifyRuntimeSnapshot(snapshotPath, {
    allowSimulation: state.full_mode === 'fixture-simulated',
  });
  if (state.run_id !== request.run_id
    || snapshot.run_id !== request.run_id
    || snapshot.tree_digest !== state.identity.runtime.digest
    || snapshot.bundle.id !== state.identity.bundle.id
    || snapshot.bundle.digest !== state.identity.bundle.digest
    || snapshot.bundle.lock_digest !== state.identity.bundle.lock_digest) {
    throw new Error('worker handoff does not match the run-pinned runtime identity');
  }

  const receiptPath = resolve(snapshot.host_receipt.path);
  const receiptBytes = readStableRegularFile(receiptPath).bytes;
  const receiptDigest = sha256Digest(receiptBytes);
  if (snapshot.host_receipt.byte_length !== String(receiptBytes.byteLength)
    || snapshot.host_receipt.digest !== receiptDigest
    || !receiptBytes.equals(stableJsonBytes(snapshot.host))) {
    throw new Error('run-pinned host capability receipt changed during dispatch');
  }
  assertHostCanDispatch(snapshot.host, request);
  return {
    host: snapshot.host,
    receiptPath,
    receiptBytes,
    receiptDigest,
  };
}

function assertSuppliedHostMatchesPin(
  supplied: LoaHostCapabilities,
  binding: PinnedHostBinding,
): void {
  if (!stableJsonBytes(supplied).equals(binding.receiptBytes)) {
    throw new Error('supplied host capabilities do not equal the run-pinned host capability receipt');
  }
}

function invocationProjection(
  invocation: LoaNativeWorkerInvocation,
): LoaNativeWorkerInvocation {
  return { ...invocation, invocation_digest: '' };
}

function sealInvocation(
  invocation: LoaNativeWorkerInvocation,
): LoaNativeWorkerInvocation {
  return {
    ...invocation,
    invocation_digest: sha256Digest(stableJsonBytes(invocationProjection(invocation))),
  };
}

function verifyInvocation(
  workerBundleRoot: string,
  returnRoot: string,
): LoaNativeWorkerInvocation {
  const request = verifyWorkerBundle(workerBundleRoot);
  returnRoot = canonicalWorkerReturnRoot(workerBundleRoot, request.call_id, returnRoot);
  const invocationPath = join(returnRoot, INVOCATION_FILE);
  assertImmutableRegularFile(invocationPath, 'Loa native worker invocation envelope');
  const loaded = canonicalFile(invocationPath, 'Loa native worker invocation envelope');
  if (!exactKeys(loaded.value, [
    'format',
    'invocation_digest',
    'request',
    'request_digest',
    'worker_bundle_root',
    'worker_bundle_digest',
    'host_capability_receipt',
    'readable_paths',
    'writable_paths',
    'inherit_context',
    'require_fresh_context',
    'require_exact_model_identity',
    'model_identity',
    'producer_context_id',
    'result',
    'simulation',
  ])) {
    throw new Error('Loa native worker invocation envelope fields are malformed');
  }
  const invocation = loaded.value as unknown as LoaNativeWorkerInvocation;
  const expectedBundleRoot = resolve(workerBundleRoot);
  const expectedDispatchPath = join(returnRoot, NATIVE_DISPATCH_FILE);
  const expectedReturnPath = join(returnRoot, NATIVE_RETURN_FILE);
  const expectedEventStreamPath = join(returnRoot, EVENT_STREAM_FILE);
  const expectedCapabilitiesPath = join(returnRoot, CAPABILITIES_FILE);
  if (invocation.format !== INVOCATION_FORMAT
    || invocation.invocation_digest !== sha256Digest(stableJsonBytes(invocationProjection(invocation)))
    || invocation.worker_bundle_root !== expectedBundleRoot
    || invocation.worker_bundle_digest !== request.bundle_digest
    || invocation.request_digest !== sha256Digest(stableJsonBytes(request))
    || stableJson(invocation.request) !== stableJson(request)
    || stableJson(invocation.model_identity) !== stableJson(request.model_identity)
    || invocation.producer_context_id !== request.isolation.producer_context_id
    || !Array.isArray(invocation.readable_paths)
    || invocation.readable_paths.length !== 1
    || invocation.readable_paths[0] !== expectedBundleRoot
    || !Array.isArray(invocation.writable_paths)
    || invocation.writable_paths.length !== 0
    || invocation.inherit_context !== false
    || invocation.require_fresh_context !== true
    || invocation.require_exact_model_identity !== true
    || !exactKeys(invocation.result, [
      'dispatch_receipt_path',
      'structured_return_path',
      'event_stream_path',
    ])
    || invocation.result.dispatch_receipt_path !== expectedDispatchPath
    || invocation.result.structured_return_path !== expectedReturnPath
    || invocation.result.event_stream_path !== expectedEventStreamPath
    || !exactKeys(invocation.host_capability_receipt, ['path', 'digest'])
    || invocation.host_capability_receipt.path !== expectedCapabilitiesPath) {
    throw new Error('Loa native worker invocation envelope does not match its sealed worker bundle');
  }
  assertImmutableRegularFile(expectedCapabilitiesPath, 'retained host capability receipt');
  const retained = canonicalFile(expectedCapabilitiesPath, 'retained host capability receipt');
  const binding = pinnedHostBinding(workerBundleRoot, request);
  if (!retained.bytes.equals(binding.receiptBytes)
    || sha256Digest(retained.bytes) !== binding.receiptDigest
    || invocation.host_capability_receipt.digest !== binding.receiptDigest) {
    throw new Error('retained host capability receipt is not the exact run-pinned receipt');
  }
  if (stableJson(binding.host.simulation) !== stableJson(invocation.simulation)) {
    throw new Error('invocation simulation label disagrees with the run-pinned host receipt');
  }
  return invocation;
}

/**
 * Deterministically materialize the immutable handoff consumed by the Loa
 * skill. This function does not invoke a worker or a model.
 */
export function prepareLoaWorkerHandoff(
  options: PrepareLoaWorkerHandoffOptions,
): PreparedLoaWorkerHandoff {
  const workerBundleRoot = resolve(options.workerBundleRoot);
  const request = verifyWorkerBundle(workerBundleRoot);
  const returnRoot = canonicalWorkerReturnRoot(
    workerBundleRoot,
    request.call_id,
    options.returnRoot,
  );
  const binding = pinnedHostBinding(workerBundleRoot, request);
  assertSuppliedHostMatchesPin(options.hostCapabilities, binding);
  if (options.hostCapabilitiesPath !== undefined
    && resolve(options.hostCapabilitiesPath) !== binding.receiptPath) {
    throw new Error('capability receipt path is not the canonical run-pinned host receipt');
  }
  assertNoSymlinkComponents(workerBundleRoot, workerBundleRoot);
  if (existsSync(join(returnRoot, INVOCATION_FILE))
    || existsSync(join(returnRoot, CAPABILITIES_FILE))
    || existsSync(join(returnRoot, NATIVE_DISPATCH_FILE))
    || existsSync(join(returnRoot, NATIVE_RETURN_FILE))
    || existsSync(join(returnRoot, EVENT_STREAM_FILE))) {
    throw new Error('Loa native worker handoff already exists; stale handoffs are never reused');
  }
  const capabilitiesPath = join(returnRoot, CAPABILITIES_FILE);
  writeFileAtomic(capabilitiesPath, binding.receiptBytes, 0o400);
  const capabilityBytes = readStableRegularFile(capabilitiesPath).bytes;
  if (!capabilityBytes.equals(binding.receiptBytes)
    || sha256Digest(capabilityBytes) !== binding.receiptDigest) {
    throw new Error('retained host receipt differs from the run pin');
  }
  const invocationPath = join(returnRoot, INVOCATION_FILE);
  const nativeDispatchPath = join(returnRoot, NATIVE_DISPATCH_FILE);
  const nativeReturnPath = join(returnRoot, NATIVE_RETURN_FILE);
  const eventStreamPath = join(returnRoot, EVENT_STREAM_FILE);
  const invocation = sealInvocation({
    format: INVOCATION_FORMAT,
    invocation_digest: '',
    request,
    request_digest: sha256Digest(stableJsonBytes(request)),
    worker_bundle_root: workerBundleRoot,
    worker_bundle_digest: request.bundle_digest,
    host_capability_receipt: {
      path: capabilitiesPath,
      digest: binding.receiptDigest,
    },
    readable_paths: [workerBundleRoot],
    writable_paths: [],
    inherit_context: false,
    require_fresh_context: true,
    require_exact_model_identity: true,
    model_identity: request.model_identity,
    producer_context_id: request.isolation.producer_context_id,
    result: {
      dispatch_receipt_path: nativeDispatchPath,
      structured_return_path: nativeReturnPath,
      event_stream_path: eventStreamPath,
    },
    simulation: binding.host.simulation,
  });
  writeJsonAtomic(invocationPath, invocation, 0o400);
  chmodSync(capabilitiesPath, 0o400);
  chmodSync(invocationPath, 0o400);
  verifyInvocation(workerBundleRoot, returnRoot);
  return {
    invocation,
    invocationPath,
    nativeDispatchPath,
    nativeReturnPath,
    eventStreamPath,
  };
}

function readNativeDispatchRecord(
  path: string,
  invocation: LoaNativeWorkerInvocation,
  host: LoaHostCapabilities,
  structuredReturnBytes: Buffer,
): LoaNativeDispatchRecord {
  assertImmutableRegularFile(path, 'Loa native dispatch record');
  const loaded = canonicalFile(path, 'Loa native dispatch record');
  if (!exactKeys(loaded.value, [
    'format',
    'invocation_digest',
    'worker_bundle_digest',
    'host_capability_receipt_digest',
    'event_stream_digest',
    'structured_return_digest',
    'host_evidence',
    'receipt',
  ])) {
    throw new Error('Loa native dispatch record fields are malformed');
  }
  const record = loaded.value as unknown as LoaNativeDispatchRecord;
  if (record.format !== NATIVE_DISPATCH_FORMAT
    || record.invocation_digest !== invocation.invocation_digest
    || record.worker_bundle_digest !== invocation.worker_bundle_digest
    || record.host_capability_receipt_digest !== invocation.host_capability_receipt.digest
    || record.structured_return_digest !== sha256Digest(structuredReturnBytes)
    || !exactKeys(record.receipt, [
      'format',
      'call_id',
      'context_id',
      'producer_context_id',
      'fresh_context',
      'inherited_context',
      'filesystem',
      'model_identity',
      'simulation',
    ])) {
    throw new Error('Loa native dispatch record is not exactly bound to the sealed invocation');
  }
  if (stableJson(record.receipt.simulation) !== stableJson(invocation.simulation)) {
    throw new Error('Loa native dispatch receipt lost or forged its simulation label');
  }
  if (invocation.simulation !== null) {
    if (record.host_evidence !== null || record.event_stream_digest !== null) {
      throw new Error('fixture-simulated native dispatch forged live host evidence');
    }
    return record;
  }
  if (host.runtime === null
    || record.host_evidence === null
    || typeof record.event_stream_digest !== 'string'
    || !/^sha256:[0-9a-f]{64}$/u.test(record.event_stream_digest)) {
    throw new Error('live native dispatch omits Claude Code host evidence');
  }
  const evidence = record.host_evidence;
  if (!exactKeys(evidence, [
    'format',
    'session_id',
    'requested_model',
    'observed_model',
    'effort',
    'claude_code_version',
    'host_build_id',
    'claude_executable_digest',
    'sandbox_executable_digest',
    'sandbox_policy_digest',
    'prompt_digest',
    'output_schema_digest',
    'event_stream_digest',
    'event_stream_byte_length',
    'event_count',
    'structured_output_digest',
    'total_cost_usd',
    'usage',
    'model_usage',
    'stop_reason',
    'terminal_reason',
  ])
    || !exactKeys(evidence.usage, [
      'input_tokens',
      'output_tokens',
      'cache_read_input_tokens',
      'cache_creation_input_tokens',
    ])
    || !exactKeys(evidence.model_usage, [
      'input_tokens',
      'output_tokens',
      'cache_read_input_tokens',
      'cache_creation_input_tokens',
      'cost_usd',
      'context_window',
      'max_output_tokens',
    ])) {
    throw new Error('Claude Code native dispatch evidence fields are malformed');
  }
  const eventPath = invocation.result.event_stream_path;
  assertImmutableRegularFile(eventPath, 'Claude Code event stream');
  const eventStream = readStableRegularFile(eventPath).bytes;
  if (record.event_stream_digest !== sha256Digest(eventStream)
    || evidence.event_stream_digest !== record.event_stream_digest
    || evidence.event_stream_byte_length !== String(eventStream.byteLength)) {
    throw new Error('Claude Code event stream changed after native dispatch');
  }
  const parsed = parseClaudeCodeStream(
    eventStream,
    invocation.model_identity.model_id,
    host.runtime.claude.version,
  );
  const contractPath = join(
    invocation.worker_bundle_root,
    'contracts',
    'output.json',
  );
  const contractBytes = readStableRegularFile(contractPath).bytes;
  if (sha256Digest(contractBytes) !== invocation.request.output_contract.digest) {
    throw new Error('Claude Code output contract changed after dispatch');
  }
  let contractExemplar: unknown;
  try {
    contractExemplar = JSON.parse(contractBytes.toString('utf8')) as unknown;
  } catch {
    throw new Error('Claude Code output contract is invalid JSON');
  }
  const expectedPromptDigest = sha256Digest(
    buildClaudeCodeWorkerPrompt(invocation),
  );
  const expectedSchemaDigest = sha256Digest(stableJsonBytes(
    contractExemplarToJsonSchema(contractExemplar),
  ));
  let structuredValue: unknown;
  try {
    structuredValue = JSON.parse(structuredReturnBytes.toString('utf8')) as unknown;
  } catch {
    throw new Error('Loa native structured return is invalid JSON');
  }
  if (stableJson(parsed.structuredOutput) !== stableJson(structuredValue)
    || evidence.format !== LOA_CLAUDE_CODE_DISPATCH_FORMAT
    || evidence.structured_output_digest !== sha256Digest(structuredReturnBytes)
    || record.receipt.context_id !== evidence.session_id
    || record.receipt.model_identity.model_id !== evidence.observed_model
    || evidence.effort !== invocation.model_identity.effort
    || evidence.host_build_id !== host.host.build_id
    || evidence.claude_executable_digest !== host.runtime.claude.digest
    || evidence.sandbox_executable_digest !== host.runtime.sandbox.digest
    || evidence.sandbox_policy_digest !== host.runtime.sandbox.policy_digest
    || evidence.prompt_digest !== expectedPromptDigest
    || evidence.output_schema_digest !== expectedSchemaDigest
    || stableJson({
      session_id: evidence.session_id,
      requested_model: evidence.requested_model,
      observed_model: evidence.observed_model,
      claude_code_version: evidence.claude_code_version,
      event_stream_digest: evidence.event_stream_digest,
      event_count: evidence.event_count,
      structured_output_digest: evidence.structured_output_digest,
      total_cost_usd: evidence.total_cost_usd,
      usage: evidence.usage,
      model_usage: evidence.model_usage,
      stop_reason: evidence.stop_reason,
      terminal_reason: evidence.terminal_reason,
    }) !== stableJson(parsed.evidence)) {
    throw new Error('Claude Code native dispatch evidence is not bound to its stream and return');
  }
  return record;
}

/**
 * Accept the two files persisted by the installed Loa skill after its native
 * fresh-context call. The untrusted return is quarantined and validated. This
 * API exposes no canonical-ledger handle and performs no ledger write.
 */
export function acceptLoaWorkerHandoff(
  options: AcceptLoaWorkerHandoffOptions,
): AcceptedLoaWorkerHandoff {
  const workerBundleRoot = resolve(options.workerBundleRoot);
  const returnRoot = resolve(options.returnRoot);
  const invocation = verifyInvocation(workerBundleRoot, returnRoot);
  const dispatchRecordPath = join(returnRoot, NATIVE_DISPATCH_FILE);
  const nativeReturnPath = join(returnRoot, NATIVE_RETURN_FILE);
  assertImmutableRegularFile(nativeReturnPath, 'Loa native structured return');
  const returned = canonicalFile(nativeReturnPath, 'Loa native structured return');
  const raw = returned.bytes;
  const host = pinnedHostBinding(workerBundleRoot, invocation.request).host;
  const dispatch = readNativeDispatchRecord(
    dispatchRecordPath,
    invocation,
    host,
    raw,
  );
  const validated = validateWorkerReturn({
    workerBundleRoot,
    returnRoot,
    raw,
    dispatchReceipt: dispatch.receipt,
  });
  return {
    ...validated,
    receipt: dispatch.receipt,
    dispatchRecordPath,
    invocationPath: join(returnRoot, INVOCATION_FILE),
  };
}

/**
 * Execute an already prepared live handoff through the binary-attested Claude
 * Code and bubblewrap binding. The raw stream and structured return remain in
 * quarantine until the separate accept operation re-verifies them.
 */
export function dispatchPreparedClaudeCodeHandoff(
  options: AcceptLoaWorkerHandoffOptions,
): DispatchedClaudeCodeHandoff {
  const workerBundleRoot = resolve(options.workerBundleRoot);
  const returnRoot = resolve(options.returnRoot);
  const invocation = verifyInvocation(workerBundleRoot, returnRoot);
  const binding = pinnedHostBinding(workerBundleRoot, invocation.request);
  if (invocation.simulation !== null || binding.host.simulation !== null) {
    throw new Error('live Claude Code dispatch rejects fixture-simulated handoffs');
  }
  for (const path of [
    invocation.result.dispatch_receipt_path,
    invocation.result.structured_return_path,
    invocation.result.event_stream_path,
  ]) {
    if (existsSync(path)) {
      throw new Error('Loa native worker result already exists; dispatch is never retried in place');
    }
  }
  const completed = invokeClaudeCodeWorker(invocation, binding.host);
  const returnBytes = stableJsonBytes(completed.structuredReturn);
  const dispatchRecord: LoaNativeDispatchRecord = {
    format: NATIVE_DISPATCH_FORMAT,
    invocation_digest: invocation.invocation_digest,
    worker_bundle_digest: invocation.worker_bundle_digest,
    host_capability_receipt_digest: invocation.host_capability_receipt.digest,
    event_stream_digest: completed.evidence.event_stream_digest,
    structured_return_digest: sha256Digest(returnBytes),
    host_evidence: completed.evidence,
    receipt: completed.receipt,
  };
  writeFileAtomic(
    invocation.result.event_stream_path,
    completed.eventStream,
    0o400,
  );
  writeFileAtomic(
    invocation.result.structured_return_path,
    returnBytes,
    0o400,
  );
  writeJsonAtomic(
    invocation.result.dispatch_receipt_path,
    dispatchRecord,
    0o400,
  );
  chmodSync(invocation.result.event_stream_path, 0o400);
  chmodSync(invocation.result.structured_return_path, 0o400);
  chmodSync(invocation.result.dispatch_receipt_path, 0o400);
  readNativeDispatchRecord(
    invocation.result.dispatch_receipt_path,
    invocation,
    binding.host,
    returnBytes,
  );
  return {
    receipt: completed.receipt,
    evidence: completed.evidence,
    dispatchRecordPath: invocation.result.dispatch_receipt_path,
    structuredReturnPath: invocation.result.structured_return_path,
    eventStreamPath: invocation.result.event_stream_path,
  };
}

/**
 * Synchronous embedding interface retained only for fixture-simulated
 * harnesses. Live calls must use the binary-attested binding above.
 */
export function dispatchLoaWorker(
  options: DispatchLoaWorkerOptions,
): LoaDispatchedWorkerResult {
  if (!options.host || typeof options.host.invokeFreshContext !== 'function') {
    throw new Error('Loa fresh-context worker host binding is unavailable; no fallback is permitted');
  }
  const returnRoot = resolve(options.returnRoot);
  const prepared = prepareLoaWorkerHandoff({
    workerBundleRoot: options.workerBundleRoot,
    returnRoot,
    hostCapabilities: options.hostCapabilities,
  });
  const result = options.host.invokeFreshContext(prepared.invocation);
  if (!result || typeof result !== 'object') {
    throw new Error('Loa fresh-context host returned no structured dispatch result');
  }
  if (stableJson(result.receipt.simulation)
    !== stableJson(prepared.invocation.simulation)) {
    throw new Error('Loa fresh-context host lost or forged its simulation label');
  }
  if (prepared.invocation.simulation === null) {
    throw new Error('live callback dispatch is unsupported; use the attested Claude Code binding');
  }
  const returnBytes = stableJsonBytes(result.structured_return);
  const dispatchRecord: LoaNativeDispatchRecord = {
    format: NATIVE_DISPATCH_FORMAT,
    invocation_digest: prepared.invocation.invocation_digest,
    worker_bundle_digest: prepared.invocation.worker_bundle_digest,
    host_capability_receipt_digest:
      prepared.invocation.host_capability_receipt.digest,
    event_stream_digest: null,
    structured_return_digest: sha256Digest(returnBytes),
    host_evidence: null,
    receipt: result.receipt,
  };
  writeJsonAtomic(prepared.nativeDispatchPath, dispatchRecord, 0o400);
  writeFileAtomic(prepared.nativeReturnPath, returnBytes, 0o400);
  chmodSync(prepared.nativeDispatchPath, 0o400);
  chmodSync(prepared.nativeReturnPath, 0o400);
  const accepted = acceptLoaWorkerHandoff({
    workerBundleRoot: options.workerBundleRoot,
    returnRoot,
  });
  return {
    report: accepted.report,
    validated: accepted.validated,
    receipt: accepted.receipt,
    dispatchRecordPath: accepted.dispatchRecordPath,
  };
}

interface ParsedCli {
  action: 'prepare' | 'dispatch' | 'accept';
  workerBundleRoot: string;
  returnRoot: string;
  capabilitiesPath?: string;
  json: boolean;
}

function parseCli(argv: string[]): ParsedCli {
  const action = argv.shift();
  if (action !== 'prepare' && action !== 'dispatch' && action !== 'accept') {
    throw new Error('worker handoff action must be prepare, dispatch, or accept');
  }
  let workerBundleRoot = '';
  let returnRoot = '';
  let capabilitiesPath: string | undefined;
  let json = false;
  while (argv.length > 0) {
    const option = argv.shift();
    if (option === '--worker-bundle') workerBundleRoot = argv.shift() || '';
    else if (option === '--return-root') returnRoot = argv.shift() || '';
    else if (option === '--capabilities') capabilitiesPath = argv.shift() || '';
    else if (option === '--json') json = true;
    else throw new Error(`unknown worker handoff option: ${option || '<empty>'}`);
  }
  if (!workerBundleRoot || !returnRoot) {
    throw new Error('--worker-bundle and --return-root are required');
  }
  if (action === 'prepare' && !capabilitiesPath) {
    throw new Error('prepare requires --capabilities');
  }
  if (action !== 'prepare' && capabilitiesPath) {
    throw new Error(`${action} does not take a mutable capability receipt`);
  }
  return { action, workerBundleRoot, returnRoot, capabilitiesPath, json };
}

function printResult(value: unknown, json: boolean): void {
  if (json) process.stdout.write(stableJsonBytes(value));
  else process.stdout.write(`${stableJson(value)}\n`);
}

export function runWorkerDispatchCli(argv = process.argv.slice(2)): number {
  try {
    const parsed = parseCli([...argv]);
    if (parsed.action === 'prepare') {
      const prepared = prepareLoaWorkerHandoff({
        workerBundleRoot: parsed.workerBundleRoot,
        returnRoot: parsed.returnRoot,
        hostCapabilities: readJsonFile(parsed.capabilitiesPath || '') as LoaHostCapabilities,
        hostCapabilitiesPath: parsed.capabilitiesPath,
      });
      printResult({
        format: INVOCATION_FORMAT,
        result: 'PASS',
        invocation_digest: prepared.invocation.invocation_digest,
        invocation_path: prepared.invocationPath,
        native_dispatch_path: prepared.nativeDispatchPath,
        native_return_path: prepared.nativeReturnPath,
        event_stream_path: prepared.eventStreamPath,
        simulation: prepared.invocation.simulation,
      }, parsed.json);
      return 0;
    }
    if (parsed.action === 'dispatch') {
      const dispatched = dispatchPreparedClaudeCodeHandoff({
        workerBundleRoot: parsed.workerBundleRoot,
        returnRoot: parsed.returnRoot,
      });
      printResult({
        format: 'aleph-loa-native-worker-dispatch-result/v1',
        result: 'PASS',
        call_id: dispatched.receipt.call_id,
        context_id: dispatched.receipt.context_id,
        model: dispatched.evidence.observed_model,
        total_cost_usd: dispatched.evidence.total_cost_usd,
        dispatch_record_path: dispatched.dispatchRecordPath,
        structured_return_path: dispatched.structuredReturnPath,
        event_stream_path: dispatched.eventStreamPath,
        event_stream_digest: dispatched.evidence.event_stream_digest,
        ledger_write: false,
      }, parsed.json);
      return 0;
    }
    const accepted = acceptLoaWorkerHandoff({
      workerBundleRoot: parsed.workerBundleRoot,
      returnRoot: parsed.returnRoot,
    });
    printResult({
      format: 'aleph-loa-native-worker-accept/v1',
      result: accepted.report.result,
      call_id: accepted.report.call_id,
      dispatch_record_path: accepted.dispatchRecordPath,
      validation_record_path: join(resolve(parsed.returnRoot), 'validation.json'),
      simulation: accepted.report.simulation,
      ledger_write: false,
    }, parsed.json);
    return accepted.report.result === 'PASS' ? 0 : 1;
  } catch (error) {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    return 1;
  }
}

if (process.argv[1] && resolve(process.argv[1]) === SCRIPT_PATH) {
  process.exitCode = runWorkerDispatchCli();
}
