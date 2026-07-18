import { existsSync, lstatSync, mkdirSync, realpathSync, rmSync, } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { LOA_ADAPTER_ID, LOA_HOST_FORMAT, LOA_MODEL_SLOTS, LOA_PROFILE_FORMAT, LOA_REQUIRED_HOST_CAPABILITIES, LOA_ROLE_IDS, LOA_RUNTIME_SNAPSHOT_FORMAT, } from './types.js';
import { assertSafeRelativePath, digestFile, digestTreeRecords, makeTreeReadOnly, readJsonFile, readStableRegularFile, sha256Digest, stableJsonBytes, utf8Compare, writeFileAtomic, writeJsonAtomic, } from './fs.js';
import { readLockedFile, readVerifiedBundleLock, verifyAndLoadLoaBundle, } from './core-loader.js';
function isRecord(value) {
    return typeof value === 'object' && value !== null && !Array.isArray(value);
}
function exactKeys(value, keys) {
    return isRecord(value)
        && Object.keys(value).sort(utf8Compare).join('\0') === [...keys].sort(utf8Compare).join('\0');
}
function exactStrings(value, expected) {
    return Array.isArray(value)
        && value.every((item) => typeof item === 'string')
        && [...value].sort(utf8Compare).join('\0') === [...expected].sort(utf8Compare).join('\0');
}
function nonemptyString(value) {
    return typeof value === 'string'
        && value === value.trim()
        && value.length > 0
        && !/[\u0000-\u001f\u007f]/u.test(value);
}
const MUTABLE_ALIAS = /(?:^|[-_.:/])(alias|auto|current|default|latest|recommended|rolling|stable)(?:$|[-_.:/])/iu;
const SHA256_ID = /^sha256:[0-9a-f]{64}$/u;
function exactImmutableLabel(value, label) {
    if (!nonemptyString(value) || MUTABLE_ALIAS.test(value)) {
        throw new Error(`${label} is empty, mutable, or aliased`);
    }
}
function contentAddressedIdentity(value, label) {
    if (typeof value !== 'string' || !SHA256_ID.test(value)) {
        throw new Error(`${label} must be a lowercase sha256 content identity`);
    }
}
function parseVersion(value) {
    const match = value.replace(/^v/u, '').match(/^(\d+)\.(\d+)\.(\d+)/u);
    if (!match)
        throw new Error(`invalid semantic version: ${value}`);
    return [Number(match[1]), Number(match[2]), Number(match[3])];
}
function versionAtLeast(actual, minimum) {
    const left = parseVersion(actual);
    const right = parseVersion(minimum);
    for (let index = 0; index < left.length; index++) {
        if (left[index] !== right[index])
            return left[index] > right[index];
    }
    return true;
}
function parseRoleMapping(value, role) {
    const keys = [
        'model_slot',
        'effort',
        'context_policy',
        'budget_policy',
        'cache_policy',
        'batch_policy',
    ];
    if (!exactKeys(value, keys))
        throw new Error(`profile role ${role} fields are malformed`);
    const record = value;
    if (typeof record.model_slot !== 'string'
        || !LOA_MODEL_SLOTS.includes(record.model_slot)
        || !keys.slice(1).every((key) => nonemptyString(record[key]))) {
        throw new Error(`profile role ${role} mapping is incomplete`);
    }
    return record;
}
export function parseLoaProfile(value) {
    if (!isRecord(value) || !exactKeys(value, [
        'profile_format',
        'id',
        'host',
        'runtime_requirements',
        'paths',
        'role_mappings',
        'model_slots',
    ])) {
        throw new Error('Loa profile top-level fields are malformed');
    }
    const profile = value;
    if (profile.profile_format !== LOA_PROFILE_FORMAT
        || !nonemptyString(profile.id)
        || profile.host !== LOA_ADAPTER_ID) {
        throw new Error('Loa profile identity is invalid');
    }
    if (!exactKeys(profile.runtime_requirements, [
        'node_min_version',
        'required_capabilities',
    ])) {
        throw new Error('Loa profile runtime requirements are malformed');
    }
    const runtime = profile.runtime_requirements;
    if (!nonemptyString(runtime.node_min_version)
        || !exactStrings(runtime.required_capabilities, LOA_REQUIRED_HOST_CAPABILITIES)) {
        throw new Error('Loa profile must declare the complete host capability set');
    }
    parseVersion(runtime.node_min_version);
    if (!exactKeys(profile.paths, ['run_root', 'installed_bundle_root', 'install_lock'])) {
        throw new Error('Loa profile paths are malformed');
    }
    for (const [key, path] of Object.entries(profile.paths)) {
        if (!nonemptyString(path))
            throw new Error(`Loa profile path ${key} is empty`);
        assertSafeRelativePath(path, `Loa profile path ${key}`);
    }
    if (!isRecord(profile.role_mappings)
        || !exactStrings(Object.keys(profile.role_mappings), LOA_ROLE_IDS)) {
        throw new Error('Loa profile does not map every Core role exactly once');
    }
    const roleMappingRecord = profile.role_mappings;
    const roleMappings = Object.fromEntries(LOA_ROLE_IDS.map((role) => ([role, parseRoleMapping(roleMappingRecord[role], role)])));
    const mechanicsBySlot = new Map();
    for (const role of LOA_ROLE_IDS) {
        const mapping = roleMappings[role];
        const signature = stableJsonBytes({
            effort: mapping.effort,
            context: mapping.context_policy,
            budget: mapping.budget_policy,
            cache: mapping.cache_policy,
            batch: mapping.batch_policy,
        }).toString('utf8');
        const prior = mechanicsBySlot.get(mapping.model_slot);
        if (prior !== undefined && prior !== signature) {
            throw new Error(`profile roles sharing model slot ${mapping.model_slot} declare different host mechanics`);
        }
        mechanicsBySlot.set(mapping.model_slot, signature);
    }
    if (!isRecord(profile.model_slots)
        || !exactStrings(Object.keys(profile.model_slots), LOA_MODEL_SLOTS)) {
        throw new Error('Loa profile model slots are incomplete');
    }
    const modelSlotRecord = profile.model_slots;
    const modelSlots = Object.fromEntries(LOA_MODEL_SLOTS.map((slot) => {
        const value = modelSlotRecord[slot];
        if (!exactKeys(value, [
            'capability_class',
            'exact_identity_required',
            'fallback_allowed',
        ])) {
            throw new Error(`Loa profile model slot ${slot} fields are malformed`);
        }
        const record = value;
        if (!nonemptyString(record.capability_class)
            || record.exact_identity_required !== true
            || record.fallback_allowed !== false) {
            throw new Error(`Loa profile model slot ${slot} weakens identity or fallback rules`);
        }
        return [slot, record];
    }));
    return {
        profile_format: LOA_PROFILE_FORMAT,
        id: profile.id,
        host: LOA_ADAPTER_ID,
        runtime_requirements: {
            node_min_version: runtime.node_min_version,
            required_capabilities: [...LOA_REQUIRED_HOST_CAPABILITIES],
        },
        paths: profile.paths,
        role_mappings: roleMappings,
        model_slots: modelSlots,
    };
}
export function loadLoaProfile(path) {
    const absolute = resolve(path);
    const bytes = readStableRegularFile(absolute).bytes;
    let value;
    try {
        value = JSON.parse(bytes.toString('utf8'));
    }
    catch (error) {
        throw new Error(`Loa profile is invalid JSON: ${error instanceof Error ? error.message : String(error)}`);
    }
    return {
        path: absolute,
        value: parseLoaProfile(value),
        digest: sha256Digest(bytes),
    };
}
function validateModelIdentity(value, slot) {
    const keys = [
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
    if (!exactKeys(value, keys))
        throw new Error(`model slot ${slot} fields are malformed`);
    const record = value;
    for (const key of keys.filter((key) => !['immutable', 'fallback'].includes(key))) {
        exactImmutableLabel(record[key], `model slot ${slot}.${key}`);
    }
    contentAddressedIdentity(record.resolved_version, `model slot ${slot}.resolved_version`);
    if (record.immutable !== true || record.fallback !== false) {
        throw new Error(`model slot ${slot} permits mutable identity or fallback`);
    }
    return record;
}
export function validateResolvedHost(value, profile, options = {}) {
    if (!exactKeys(value, [
        'host_format',
        'host',
        'capabilities',
        'models',
        'simulation',
    ])) {
        throw new Error('Loa host-capability receipt fields are malformed');
    }
    const receipt = value;
    if (receipt.host_format !== LOA_HOST_FORMAT
        || !exactKeys(receipt.host, ['id', 'version', 'build_id'])) {
        throw new Error('Loa host identity is malformed');
    }
    const host = receipt.host;
    if (host.id !== LOA_ADAPTER_ID
        || !nonemptyString(host.version)) {
        throw new Error('Loa host identity is unresolved');
    }
    exactImmutableLabel(host.version, 'Loa host version');
    contentAddressedIdentity(host.build_id, 'Loa host build_id');
    if (!isRecord(receipt.capabilities)
        || !exactStrings(Object.keys(receipt.capabilities), profile.runtime_requirements.required_capabilities)) {
        throw new Error('Loa host-capability receipt is incomplete');
    }
    for (const capability of profile.runtime_requirements.required_capabilities) {
        if (receipt.capabilities[capability] !== true) {
            throw new Error(`Loa host capability ${capability} is unavailable`);
        }
    }
    if (!isRecord(receipt.models)
        || !exactStrings(Object.keys(receipt.models), LOA_MODEL_SLOTS)) {
        throw new Error('Loa host model resolution is incomplete');
    }
    const modelRecord = receipt.models;
    const models = Object.fromEntries(LOA_MODEL_SLOTS.map((slot) => ([slot, validateModelIdentity(modelRecord[slot], slot)])));
    const mechanicFields = [
        ['effort', 'effort'],
        ['context_policy', 'context'],
        ['budget_policy', 'budget'],
        ['cache_policy', 'cache'],
        ['batch_policy', 'batch'],
    ];
    for (const role of LOA_ROLE_IDS) {
        const mapping = profile.role_mappings[role];
        const model = models[mapping.model_slot];
        for (const [profileField, hostField] of mechanicFields) {
            if (mapping[profileField] !== model[hostField]) {
                throw new Error(`role ${role} ${profileField}=${mapping[profileField]} does not match exact host slot ${mapping.model_slot}.${hostField}=${model[hostField]}`);
            }
        }
    }
    const simulation = receipt.simulation;
    if (simulation !== null) {
        if (!options.allowSimulation
            || !exactKeys(simulation, ['kind'])
            || simulation.kind !== 'fixture-simulated') {
            throw new Error('simulated host capabilities are not allowed for this invocation');
        }
    }
    if (!versionAtLeast(process.version, profile.runtime_requirements.node_min_version)) {
        throw new Error(`Node ${process.version} is below required ${profile.runtime_requirements.node_min_version}`);
    }
    return {
        host_format: LOA_HOST_FORMAT,
        host: host,
        capabilities: receipt.capabilities,
        models,
        simulation: simulation,
    };
}
function runtimeSnapshotDigest(snapshot) {
    return sha256Digest(stableJsonBytes(snapshot));
}
export function captureRuntimeSnapshot(options) {
    const executable = realpathSync(process.execPath);
    const runtimeRoot = dirname(resolve(options.outputPath));
    const runtimeBundleRoot = join(runtimeRoot, 'bundle');
    const hostReceiptPath = join(runtimeRoot, 'host-capabilities.json');
    if (existsSync(runtimeBundleRoot)) {
        throw new Error(`run-local runtime bundle already exists: ${runtimeBundleRoot}`);
    }
    if (existsSync(hostReceiptPath)) {
        throw new Error(`run-local host-capability receipt already exists: ${hostReceiptPath}`);
    }
    mkdirSync(runtimeBundleRoot, { recursive: true });
    let runtimeBundle;
    try {
        for (const file of options.bundle.lock.files) {
            writeFileAtomic(join(runtimeBundleRoot, file.path), readLockedFile(options.bundle, file.path, file.classification), 0o600);
        }
        writeFileAtomic(join(runtimeBundleRoot, 'bundle.lock.json'), readVerifiedBundleLock(options.bundle), 0o600);
        runtimeBundle = verifyAndLoadLoaBundle(runtimeBundleRoot);
    }
    catch (error) {
        rmSync(runtimeBundleRoot, { recursive: true, force: true });
        throw error;
    }
    const runtimeLockBytes = readVerifiedBundleLock(runtimeBundle);
    const files = [
        ...runtimeBundle.lock.files.map((file) => ({
            path: file.path,
            digest: file.digest,
            byte_length: String(readLockedFile(runtimeBundle, file.path, file.classification).byteLength),
        })),
        {
            path: 'bundle.lock.json',
            digest: sha256Digest(runtimeLockBytes),
            byte_length: String(runtimeLockBytes.byteLength),
        },
    ].sort((left, right) => utf8Compare(left.path, right.path));
    const runLocalProfilePath = join(runtimeBundleRoot, 'adapters', 'loa', 'profiles', 'loa-default.json');
    if (digestFile(runLocalProfilePath) !== options.profile.digest) {
        rmSync(runtimeBundleRoot, { recursive: true, force: true });
        throw new Error('selected profile does not match the profile in the verified bundle');
    }
    let hostReceiptBytes;
    try {
        writeJsonAtomic(hostReceiptPath, options.host, 0o400);
        hostReceiptBytes = readStableRegularFile(hostReceiptPath).bytes;
        if (!hostReceiptBytes.equals(stableJsonBytes(options.host))) {
            throw new Error('run-local host-capability receipt is not canonical');
        }
    }
    catch (error) {
        rmSync(hostReceiptPath, { force: true });
        rmSync(runtimeBundleRoot, { recursive: true, force: true });
        throw error;
    }
    const base = {
        format: LOA_RUNTIME_SNAPSHOT_FORMAT,
        run_id: options.runId,
        captured_at: options.capturedAt,
        bundle: {
            id: options.bundle.lock.bundle.id,
            digest: options.bundle.lock.bundle.digest,
            lock_digest: options.bundle.lock.lock_digest,
            root: runtimeBundleRoot,
        },
        profile: {
            id: options.profile.value.id,
            path: runLocalProfilePath,
            digest: options.profile.digest,
        },
        host: options.host,
        host_receipt: {
            path: hostReceiptPath,
            digest: sha256Digest(hostReceiptBytes),
            byte_length: String(hostReceiptBytes.byteLength),
        },
        node: {
            version: process.version,
            executable,
            executable_digest: digestFile(executable),
            platform: process.platform,
            arch: process.arch,
        },
        files,
    };
    const snapshot = {
        ...base,
        tree_digest: runtimeSnapshotDigest(base),
    };
    try {
        writeJsonAtomic(options.outputPath, snapshot);
        makeTreeReadOnly(runtimeBundleRoot);
    }
    catch (error) {
        rmSync(hostReceiptPath, { force: true });
        rmSync(runtimeBundleRoot, { recursive: true, force: true });
        throw error;
    }
    return snapshot;
}
function verifyPinnedHostCapabilities(snapshotPath, snapshot, profile, options) {
    const expectedPath = join(dirname(resolve(snapshotPath)), 'host-capabilities.json');
    if (!exactKeys(snapshot.host_receipt, ['path', 'digest', 'byte_length'])
        || resolve(snapshot.host_receipt.path) !== expectedPath
        || !/^(0|[1-9][0-9]*)$/u.test(snapshot.host_receipt.byte_length)) {
        throw new Error('runtime host-capability receipt metadata is malformed');
    }
    const stat = lstatSync(expectedPath);
    if (!stat.isFile() || stat.isSymbolicLink() || (stat.mode & 0o222) !== 0) {
        throw new Error('runtime host-capability receipt is not an immutable regular file');
    }
    const receipt = readStableRegularFile(expectedPath);
    if (snapshot.host_receipt.byte_length !== String(receipt.bytes.byteLength)
        || snapshot.host_receipt.digest !== sha256Digest(receipt.bytes)) {
        throw new Error('runtime host-capability receipt changed since the run was created');
    }
    if (!receipt.bytes.equals(stableJsonBytes(snapshot.host))) {
        throw new Error('runtime host-capability receipt disagrees with the pinned host identity');
    }
    return validateResolvedHost(snapshot.host, profile, options);
}
export function verifyRuntimeSnapshot(snapshotPath, options = {}) {
    const value = readJsonFile(resolve(snapshotPath));
    if (!isRecord(value) || !exactKeys(value, [
        'format',
        'run_id',
        'captured_at',
        'bundle',
        'profile',
        'host',
        'host_receipt',
        'node',
        'files',
        'tree_digest',
    ])
        || value.format !== LOA_RUNTIME_SNAPSHOT_FORMAT
        || typeof value.run_id !== 'string'
        || !isRecord(value.bundle)
        || !isRecord(value.profile)
        || !isRecord(value.host_receipt)
        || !isRecord(value.node)
        || !Array.isArray(value.files)
        || typeof value.tree_digest !== 'string') {
        throw new Error('runtime snapshot fields are malformed');
    }
    const snapshot = value;
    const runtimeRoot = dirname(resolve(snapshotPath));
    if (resolve(snapshot.bundle.root) !== join(runtimeRoot, 'bundle')) {
        throw new Error('runtime snapshot bundle root is not the run-local immutable bundle');
    }
    if (resolve(snapshot.profile.path) !== join(runtimeRoot, 'bundle', 'adapters', 'loa', 'profiles', 'loa-default.json')) {
        throw new Error('runtime snapshot profile path is not the run-local bundled profile');
    }
    const profile = loadLoaProfile(snapshot.profile.path);
    if (profile.value.id !== snapshot.profile.id || profile.digest !== snapshot.profile.digest) {
        throw new Error('runtime profile changed since the run was created');
    }
    verifyPinnedHostCapabilities(snapshotPath, snapshot, profile.value, options);
    const bundle = verifyAndLoadLoaBundle(snapshot.bundle.root);
    if (bundle.lock.bundle.id !== snapshot.bundle.id
        || bundle.lock.bundle.digest !== snapshot.bundle.digest
        || bundle.lock.lock_digest !== snapshot.bundle.lock_digest) {
        throw new Error('runtime bundle changed since the run was created');
    }
    const executable = realpathSync(process.execPath);
    if (snapshot.node.version !== process.version
        || snapshot.node.executable !== executable
        || snapshot.node.executable_digest !== digestFile(executable)
        || snapshot.node.platform !== process.platform
        || snapshot.node.arch !== process.arch) {
        throw new Error('runtime Node identity changed since the run was created');
    }
    const lockBytes = readVerifiedBundleLock(bundle);
    const expectedFiles = [
        ...bundle.lock.files,
        {
            path: 'bundle.lock.json',
            digest: sha256Digest(lockBytes),
        },
    ].sort((left, right) => utf8Compare(left.path, right.path));
    if (expectedFiles.length !== snapshot.files.length) {
        throw new Error('runtime adapter inventory changed');
    }
    for (const [index, file] of expectedFiles.entries()) {
        const recorded = snapshot.files[index];
        const actualBytes = file.path === 'bundle.lock.json'
            ? lockBytes
            : readLockedFile(bundle, file.path);
        if (recorded.path !== file.path
            || recorded.digest !== file.digest
            || !/^(0|[1-9][0-9]*)$/u.test(recorded.byte_length)
            || recorded.byte_length !== String(actualBytes.byteLength)
            || sha256Digest(actualBytes) !== recorded.digest) {
            throw new Error(`runtime adapter file changed: ${file.path}`);
        }
    }
    const { tree_digest: _treeDigest, ...base } = snapshot;
    const digest = runtimeSnapshotDigest(base);
    if (digest !== snapshot.tree_digest)
        throw new Error('runtime snapshot tree digest mismatch');
    return snapshot;
}
/**
 * Load host capabilities only from a fully verified run-local runtime pin.
 * Callers receive no mutable-host or installation-level fallback.
 */
export function loadPinnedHostCapabilities(snapshotPath, options = {}) {
    return verifyRuntimeSnapshot(snapshotPath, options).host;
}
export function runtimeSnapshotPath(runDir) {
    return join(resolve(runDir), 'control', 'runtime', 'snapshot.json');
}
export function defaultProfilePath(bundleRoot) {
    return join(resolve(bundleRoot), 'adapters', 'loa', 'profiles', 'loa-default.json');
}
