#!/usr/bin/env node
import { chmodSync, existsSync, lstatSync, readFileSync, } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { LOA_ADAPTER_ID, LOA_HOST_FORMAT, LOA_MODEL_SLOTS, LOA_REQUIRED_HOST_CAPABILITIES, } from './types.js';
import { assertNoSymlinkComponents, readJsonFile, readStableRegularFile, sha256Digest, stableJson, stableJsonBytes, writeFileAtomic, writeJsonAtomic, } from './fs.js';
import { readRunState } from './run-control.js';
import { runtimeSnapshotPath, verifyRuntimeSnapshot, } from './runtime-snapshot.js';
import { verifyWorkerBundle } from './worker-bundle.js';
import { canonicalWorkerReturnRoot, validateWorkerReturn, } from './worker-return.js';
const SCRIPT_PATH = fileURLToPath(import.meta.url);
const INVOCATION_FORMAT = 'aleph-loa-native-worker-invocation/v1';
const NATIVE_DISPATCH_FORMAT = 'aleph-loa-native-worker-dispatch/v1';
const INVOCATION_FILE = 'invocation.json';
const CAPABILITIES_FILE = 'host-capabilities.json';
const NATIVE_DISPATCH_FILE = 'native-dispatch.json';
const NATIVE_RETURN_FILE = 'native-return.json';
function isRecord(value) {
    return typeof value === 'object' && value !== null && !Array.isArray(value);
}
function exactKeys(value, keys) {
    if (!isRecord(value))
        return false;
    const actual = Object.keys(value).sort();
    const expected = [...keys].sort();
    return actual.length === expected.length
        && actual.every((key, index) => key === expected[index]);
}
function canonicalFile(path, label) {
    const stable = readStableRegularFile(path);
    let value;
    try {
        value = JSON.parse(stable.bytes.toString('utf8'));
    }
    catch (error) {
        throw new Error(`${label} is invalid JSON: ${error instanceof Error ? error.message : String(error)}`);
    }
    if (!stable.bytes.equals(stableJsonBytes(value))) {
        throw new Error(`${label} is not canonical JSON`);
    }
    return { value, bytes: stable.bytes };
}
function assertImmutableRegularFile(path, label) {
    const stat = lstatSync(path);
    if (!stat.isFile() || stat.isSymbolicLink()) {
        throw new Error(`${label} is not a regular non-symlink file`);
    }
    if ((stat.mode & 0o222) !== 0) {
        throw new Error(`${label} must be immutable to the invoking worker`);
    }
}
function assertExactModelIdentity(value, slot) {
    const fields = [
        'provider',
        'model_id',
        'resolved_version',
        'immutable',
        'context',
        'effort',
        'budget',
        'cache',
        'batch',
        'fallback',
    ];
    if (!exactKeys(value, fields)) {
        throw new Error(`Loa host model slot ${slot} fields are malformed`);
    }
    const model = value;
    for (const field of fields.filter((field) => field !== 'immutable' && field !== 'fallback')) {
        if (typeof model[field] !== 'string'
            || !model[field].trim()
            || /(?:^|[^a-z0-9])(?:latest|current|default|recommended|rolling|auto)(?:[^a-z0-9]|$)/iu.test(model[field])) {
            throw new Error(`Loa host model slot ${slot}.${field} is empty or mutable`);
        }
    }
    if (!/^sha256:[0-9a-f]{64}$/u.test(String(model.resolved_version))) {
        throw new Error(`Loa host model slot ${slot}.resolved_version is not content-addressed`);
    }
    if (model.immutable !== true || model.fallback !== false) {
        throw new Error(`Loa host model slot ${slot} permits mutation or fallback`);
    }
}
function assertHostCanDispatch(host, request) {
    if (!exactKeys(host, ['host_format', 'host', 'capabilities', 'models', 'simulation'])
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
    for (const slot of LOA_MODEL_SLOTS)
        assertExactModelIdentity(host.models[slot], slot);
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
    ]) {
        if (host.capabilities[capability] !== true) {
            throw new Error(`Loa host cannot dispatch full-mode worker: ${capability}`);
        }
    }
    if (!Object.values(host.models).some((model) => (stableJson(model) === stableJson(request.model_identity)))) {
        throw new Error('worker exact model identity is absent from the host capability receipt');
    }
}
function pinnedHostBinding(workerBundleRootInput, request) {
    const workerBundleRoot = resolve(workerBundleRootInput);
    const runDir = dirname(dirname(dirname(workerBundleRoot)));
    if (workerBundleRoot !== join(runDir, 'control', 'worker-bundles', request.call_id)) {
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
function assertSuppliedHostMatchesPin(supplied, binding) {
    if (!stableJsonBytes(supplied).equals(binding.receiptBytes)) {
        throw new Error('supplied host capabilities do not equal the run-pinned host capability receipt');
    }
}
function invocationProjection(invocation) {
    return { ...invocation, invocation_digest: '' };
}
function sealInvocation(invocation) {
    return {
        ...invocation,
        invocation_digest: sha256Digest(stableJsonBytes(invocationProjection(invocation))),
    };
}
function verifyInvocation(workerBundleRoot, returnRoot) {
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
    const invocation = loaded.value;
    const expectedBundleRoot = resolve(workerBundleRoot);
    const expectedDispatchPath = join(returnRoot, NATIVE_DISPATCH_FILE);
    const expectedReturnPath = join(returnRoot, NATIVE_RETURN_FILE);
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
        || !exactKeys(invocation.result, ['dispatch_receipt_path', 'structured_return_path'])
        || invocation.result.dispatch_receipt_path !== expectedDispatchPath
        || invocation.result.structured_return_path !== expectedReturnPath
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
export function prepareLoaWorkerHandoff(options) {
    const workerBundleRoot = resolve(options.workerBundleRoot);
    const request = verifyWorkerBundle(workerBundleRoot);
    const returnRoot = canonicalWorkerReturnRoot(workerBundleRoot, request.call_id, options.returnRoot);
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
        || existsSync(join(returnRoot, NATIVE_RETURN_FILE))) {
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
        },
        simulation: binding.host.simulation,
    });
    writeJsonAtomic(invocationPath, invocation, 0o400);
    chmodSync(capabilitiesPath, 0o400);
    chmodSync(invocationPath, 0o400);
    verifyInvocation(workerBundleRoot, returnRoot);
    return { invocation, invocationPath, nativeDispatchPath, nativeReturnPath };
}
function readNativeDispatchRecord(path, invocation) {
    assertImmutableRegularFile(path, 'Loa native dispatch record');
    const loaded = canonicalFile(path, 'Loa native dispatch record');
    if (!exactKeys(loaded.value, [
        'format',
        'invocation_digest',
        'worker_bundle_digest',
        'host_capability_receipt_digest',
        'receipt',
    ])) {
        throw new Error('Loa native dispatch record fields are malformed');
    }
    const record = loaded.value;
    if (record.format !== NATIVE_DISPATCH_FORMAT
        || record.invocation_digest !== invocation.invocation_digest
        || record.worker_bundle_digest !== invocation.worker_bundle_digest
        || record.host_capability_receipt_digest !== invocation.host_capability_receipt.digest
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
    return record;
}
/**
 * Accept the two files persisted by the installed Loa skill after its native
 * fresh-context call. The untrusted return is quarantined and validated. This
 * API exposes no canonical-ledger handle and performs no ledger write.
 */
export function acceptLoaWorkerHandoff(options) {
    const workerBundleRoot = resolve(options.workerBundleRoot);
    const returnRoot = resolve(options.returnRoot);
    const invocation = verifyInvocation(workerBundleRoot, returnRoot);
    const dispatchRecordPath = join(returnRoot, NATIVE_DISPATCH_FILE);
    const nativeReturnPath = join(returnRoot, NATIVE_RETURN_FILE);
    const dispatch = readNativeDispatchRecord(dispatchRecordPath, invocation);
    assertImmutableRegularFile(nativeReturnPath, 'Loa native structured return');
    const raw = readStableRegularFile(nativeReturnPath).bytes;
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
 * Synchronous embedding interface retained for harnesses that already expose
 * a genuine Loa fresh-context primitive as a callback. No default or degraded
 * implementation exists.
 */
export function dispatchLoaWorker(options) {
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
    const dispatchRecord = {
        format: NATIVE_DISPATCH_FORMAT,
        invocation_digest: prepared.invocation.invocation_digest,
        worker_bundle_digest: prepared.invocation.worker_bundle_digest,
        host_capability_receipt_digest: prepared.invocation.host_capability_receipt.digest,
        receipt: result.receipt,
    };
    writeJsonAtomic(prepared.nativeDispatchPath, dispatchRecord, 0o400);
    writeJsonAtomic(prepared.nativeReturnPath, result.structured_return, 0o400);
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
function parseCli(argv) {
    const action = argv.shift();
    if (action !== 'prepare' && action !== 'accept') {
        throw new Error('worker handoff action must be prepare or accept');
    }
    let workerBundleRoot = '';
    let returnRoot = '';
    let capabilitiesPath;
    let json = false;
    while (argv.length > 0) {
        const option = argv.shift();
        if (option === '--worker-bundle')
            workerBundleRoot = argv.shift() || '';
        else if (option === '--return-root')
            returnRoot = argv.shift() || '';
        else if (option === '--capabilities')
            capabilitiesPath = argv.shift() || '';
        else if (option === '--json')
            json = true;
        else
            throw new Error(`unknown worker handoff option: ${option || '<empty>'}`);
    }
    if (!workerBundleRoot || !returnRoot) {
        throw new Error('--worker-bundle and --return-root are required');
    }
    if (action === 'prepare' && !capabilitiesPath) {
        throw new Error('prepare requires --capabilities');
    }
    if (action === 'accept' && capabilitiesPath) {
        throw new Error('accept does not take a mutable capability receipt');
    }
    return { action, workerBundleRoot, returnRoot, capabilitiesPath, json };
}
function printResult(value, json) {
    if (json)
        process.stdout.write(stableJsonBytes(value));
    else
        process.stdout.write(`${stableJson(value)}\n`);
}
export function runWorkerDispatchCli(argv = process.argv.slice(2)) {
    try {
        const parsed = parseCli([...argv]);
        if (parsed.action === 'prepare') {
            const prepared = prepareLoaWorkerHandoff({
                workerBundleRoot: parsed.workerBundleRoot,
                returnRoot: parsed.returnRoot,
                hostCapabilities: readJsonFile(parsed.capabilitiesPath || ''),
                hostCapabilitiesPath: parsed.capabilitiesPath,
            });
            printResult({
                format: INVOCATION_FORMAT,
                result: 'PASS',
                invocation_digest: prepared.invocation.invocation_digest,
                invocation_path: prepared.invocationPath,
                native_dispatch_path: prepared.nativeDispatchPath,
                native_return_path: prepared.nativeReturnPath,
                simulation: prepared.invocation.simulation,
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
    }
    catch (error) {
        process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
        return 1;
    }
}
if (process.argv[1] && resolve(process.argv[1]) === SCRIPT_PATH) {
    process.exitCode = runWorkerDispatchCli();
}
