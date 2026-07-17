import { existsSync, linkSync, lstatSync, mkdirSync, readFileSync, readdirSync, rmSync, } from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';
import { CORE_RUN_STATES, CORE_STAGES, LOA_ADAPTER_ID, LOA_BUNDLE_ID, LOA_RUN_ROOT, LOA_RUN_STATE_FORMAT, } from './types.js';
import { assertNoSymlinkComponents, assertPathWithin, assertSafeRelativePath, nextDecimal, readJsonFile, sha256Digest, stableJsonBytes, utf8Compare, writeFileAtomic, writeJsonAtomic, } from './fs.js';
import { verifyCorpusSnapshot } from './intake.js';
import { extractMarkdownHeading, readLockedFile, verifyAndLoadLoaBundle, } from './core-loader.js';
export const RUN_CONTROL_PATH = 'control/run-state.json';
export const ORIGINAL_BUNDLE_LOCK_PATH = 'control/original-bundle.lock.json';
export const RUNTIME_SNAPSHOT_PATH = 'control/runtime/snapshot.json';
export function runtimeSnapshotPath(runDir) {
    return join(resolve(runDir), RUNTIME_SNAPSHOT_PATH);
}
const INITIAL_DIRECTORIES = [
    'arms/reconciliations',
    'clusters/route-cards',
    'control/checks',
    'control/gates',
    'control/runtime',
    'control/transactions',
    'control/worker-bundles',
    'control/worker-returns',
    'corpus/sources',
    'ledgers',
    'projections/tier-1',
    'projections/tier-2',
    'projections/traces',
    'synthesis',
    'verification/audit',
    'verification/harness',
];
function isRecord(value) {
    return typeof value === 'object' && value !== null && !Array.isArray(value);
}
function processIsAlive(pid) {
    try {
        process.kill(pid, 0);
        return true;
    }
    catch (error) {
        return error.code !== 'ESRCH';
    }
}
function parseDurableProcessLock(bytes, expectedFormat) {
    let value;
    try {
        value = JSON.parse(bytes.toString('utf8'));
    }
    catch {
        return null;
    }
    if (!isRecord(value)
        || Object.keys(value).sort(utf8Compare).join('\0')
            !== ['acquired_at', 'format', 'nonce', 'pid'].join('\0')
        || value.format !== expectedFormat
        || typeof value.pid !== 'string'
        || !/^[1-9][0-9]*$/u.test(value.pid)
        || typeof value.acquired_at !== 'string'
        || typeof value.nonce !== 'string'
        || !/^sha256:[0-9a-f]{64}$/u.test(value.nonce)) {
        return null;
    }
    return value;
}
function partialLockPid(bytes) {
    const match = bytes.toString('utf8').match(/"pid"\s*:\s*"([1-9][0-9]*)"/u);
    return match ? Number(match[1]) : null;
}
/**
 * Acquire a process-owner lock whose visible pathname is created only after
 * the complete owner record is durable. A hard-link publication is exclusive
 * and atomic: process death while preparing the contender can leave only an
 * unreferenced contender, never a zero/truncated live lock.
 */
export function acquireDurableProcessLock(lockPathInput, options) {
    const lockPath = resolve(lockPathInput);
    const recoveryPath = `${lockPath}.recovery`;
    const recoveryOwnerPath = join(recoveryPath, 'owner.json');
    const pid = String(process.pid);
    const owner = {
        format: options.format,
        pid,
        acquired_at: options.acquiredAt,
        nonce: sha256Digest(stableJsonBytes({
            pid,
            acquired_at: options.acquiredAt,
            monotonic: process.hrtime.bigint().toString(),
            lock_path: lockPath,
        })),
    };
    const bytes = stableJsonBytes(owner);
    const contenderPath = `${lockPath}.contender-${pid}-${owner.nonce.slice('sha256:'.length)}`;
    const recoveryContenderPath = `${lockPath}.recovery-contender-${pid}-${owner.nonce.slice('sha256:'.length)}`;
    const publish = () => {
        writeFileAtomic(contenderPath, bytes, 0o600);
        try {
            linkSync(contenderPath, lockPath);
        }
        finally {
            rmSync(contenderPath, { force: true });
        }
    };
    const readOwner = (path) => {
        const stat = lstatSync(path);
        if (stat.isSymbolicLink() || !stat.isFile()) {
            throw new Error(`${options.label} owner record is not a normal file: ${path}`);
        }
        const observed = readFileSync(path);
        return {
            bytes: observed,
            owner: parseDurableProcessLock(observed, options.format),
        };
    };
    const recoveryCandidates = () => {
        const directory = dirname(lockPath);
        const prefix = `${basename(lockPath)}.recovery-contender-`;
        const candidates = [];
        for (const name of readdirSync(directory).filter((entry) => entry.startsWith(prefix))) {
            const path = join(directory, name);
            const record = readOwner(path);
            if (!record.owner) {
                throw new Error(`${options.label} recovery contender is malformed: ${path}`);
            }
            if (!processIsAlive(Number(record.owner.pid))) {
                rmSync(path, { force: true });
                continue;
            }
            candidates.push({
                path,
                owner: record.owner,
                modifiedNs: lstatSync(path, { bigint: true }).mtimeNs,
            });
        }
        return candidates.sort((left, right) => {
            if (left.modifiedNs < right.modifiedNs)
                return -1;
            if (left.modifiedNs > right.modifiedNs)
                return 1;
            return utf8Compare(left.path, right.path);
        });
    };
    const acquireRecoveryOwnership = () => {
        writeFileAtomic(recoveryContenderPath, bytes, 0o600);
        try {
            mkdirSync(recoveryPath);
            linkSync(recoveryContenderPath, recoveryOwnerPath);
            return;
        }
        catch (error) {
            if (error.code !== 'EEXIST')
                throw error;
        }
        const recoveryStat = lstatSync(recoveryPath);
        if (recoveryStat.isSymbolicLink() || !recoveryStat.isDirectory()) {
            throw new Error(`${options.label} recovery path is not a normal directory`);
        }
        let observedRecoveryOwner = null;
        if (existsSync(recoveryOwnerPath)) {
            const record = readOwner(recoveryOwnerPath);
            observedRecoveryOwner = record.bytes;
            if (!record.owner) {
                throw new Error(`${options.label} recovery owner is malformed`);
            }
            if (processIsAlive(Number(record.owner.pid))) {
                throw new Error(`${options.label} recovery is already active under pid ${record.owner.pid}`);
            }
        }
        const candidates = recoveryCandidates();
        const winner = candidates[0];
        if (!winner || winner.path !== recoveryContenderPath) {
            throw new Error(`${options.label} recovery is already active${winner ? ` under pid ${winner.owner.pid}` : ''}`);
        }
        if (observedRecoveryOwner !== null
            && (!existsSync(recoveryOwnerPath)
                || !readFileSync(recoveryOwnerPath).equals(observedRecoveryOwner))) {
            throw new Error(`${options.label} recovery owner changed during takeover`);
        }
        rmSync(recoveryPath, { recursive: true, force: true });
        mkdirSync(recoveryPath);
        linkSync(recoveryContenderPath, recoveryOwnerPath);
    };
    try {
        publish();
    }
    catch (error) {
        if (error.code !== 'EEXIST')
            throw error;
        const initial = readOwner(lockPath);
        const initialPid = initial.owner
            ? Number(initial.owner.pid)
            : partialLockPid(initial.bytes);
        if (initialPid !== null && processIsAlive(initialPid)) {
            throw new Error(`${options.label} is already active under pid ${String(initialPid)}`);
        }
        try {
            acquireRecoveryOwnership();
            if (!existsSync(lockPath)) {
                publish();
            }
            else {
                const current = readOwner(lockPath);
                const observablePid = current.owner
                    ? Number(current.owner.pid)
                    : partialLockPid(current.bytes);
                if (observablePid !== null && processIsAlive(observablePid)) {
                    throw new Error(`${options.label} is already active under pid ${String(observablePid)}`);
                }
                if (!readFileSync(lockPath).equals(current.bytes)) {
                    throw new Error(`${options.label} owner changed during recovery`);
                }
                rmSync(lockPath, { force: true });
                publish();
            }
        }
        finally {
            if (existsSync(recoveryOwnerPath)
                && readFileSync(recoveryOwnerPath).equals(bytes)) {
                rmSync(recoveryPath, { recursive: true, force: true });
            }
            rmSync(recoveryContenderPath, { force: true });
        }
    }
    return () => {
        if (!existsSync(lockPath) || !readFileSync(lockPath).equals(bytes)) {
            throw new Error(`${options.label} ownership changed or disappeared`);
        }
        rmSync(lockPath, { force: true });
    };
}
function mapModels(profile, host) {
    return Object.fromEntries(Object.entries(profile.role_mappings).map(([role, mapping]) => {
        const identity = host.models[mapping.model_slot];
        if (!identity)
            throw new Error(`host did not resolve model slot ${mapping.model_slot}`);
        return [role, identity];
    }));
}
export function runDirectory(loaRoot, runId) {
    if (!/^RUN-[A-Za-z0-9]+(?:[._-][A-Za-z0-9]+)*$/u.test(runId)) {
        throw new Error(`invalid run ID: ${runId}`);
    }
    const root = resolve(loaRoot, LOA_RUN_ROOT);
    const path = resolve(root, runId);
    assertPathWithin(root, path, 'run directory');
    return path;
}
export function createRunDirectory(loaRoot, runId) {
    const root = runDirectory(loaRoot, runId);
    if (existsSync(root))
        throw new Error(`run already exists: ${runId}`);
    for (const relativePath of INITIAL_DIRECTORIES) {
        mkdirSync(join(root, relativePath), { recursive: true });
    }
    return root;
}
export function listRunIds(loaRoot) {
    const root = resolve(loaRoot, LOA_RUN_ROOT);
    if (!existsSync(root))
        return [];
    if (!lstatSync(root).isDirectory() || lstatSync(root).isSymbolicLink()) {
        throw new Error(`run root is not a normal directory: ${root}`);
    }
    return readdirSync(root)
        .filter((name) => /^RUN-[A-Za-z0-9]+(?:[._-][A-Za-z0-9]+)*$/u.test(name))
        .filter((name) => {
        const path = join(root, name);
        return lstatSync(path).isDirectory() && !lstatSync(path).isSymbolicLink();
    })
        .sort(utf8Compare);
}
export function stateCheckpointDigest(state) {
    const projection = structuredClone(state);
    projection.execution.resume.checkpoint_digest = '';
    return sha256Digest(stableJsonBytes(projection));
}
export function assertLoaRunState(value) {
    if (!isRecord(value)
        || value.format !== LOA_RUN_STATE_FORMAT
        || typeof value.run_id !== 'string'
        || value.mode !== 'agent'
        || (value.full_mode !== 'full-aleph' && value.full_mode !== 'fixture-simulated')
        || !isRecord(value.identity)
        || !isRecord(value.corpus)
        || !isRecord(value.execution)
        || !isRecord(value.ledger)) {
        throw new Error('run state is malformed');
    }
    const execution = value.execution;
    if (typeof execution.core_state !== 'string'
        || !CORE_RUN_STATES.includes(execution.core_state)
        || typeof execution.stage !== 'string'
        || !CORE_STAGES.includes(execution.stage)
        || !isRecord(execution.resume)) {
        throw new Error('run execution state is malformed');
    }
    const identity = value.identity;
    if (!isRecord(identity.adapter)
        || identity.adapter.id !== LOA_ADAPTER_ID
        || !isRecord(identity.bundle)
        || identity.bundle.id !== LOA_BUNDLE_ID) {
        throw new Error('run state is not bound to the Loa bundle');
    }
}
export function readRunState(runDir) {
    const path = join(resolve(runDir), RUN_CONTROL_PATH);
    const value = readJsonFile(path);
    assertLoaRunState(value);
    if (value.execution.resume.checkpoint_digest !== stateCheckpointDigest(value)) {
        throw new Error('run-state checkpoint digest mismatch');
    }
    return value;
}
export function writeRunState(runDir, state) {
    assertLoaRunState(state);
    state.execution.resume.checkpoint_digest = stateCheckpointDigest(state);
    writeJsonAtomic(join(resolve(runDir), RUN_CONTROL_PATH), state);
}
export function updateRunState(runDir, now, update) {
    const current = readRunState(runDir);
    const draft = structuredClone(current);
    update(draft);
    if (draft.run_id !== current.run_id
        || !stableJsonBytes(draft.identity).equals(stableJsonBytes(current.identity))) {
        throw new Error('an update attempted to mutate pinned run identity');
    }
    draft.execution.resume.sequence = nextDecimal(current.execution.resume.sequence);
    draft.execution.resume.last_verified_at = now;
    writeRunState(runDir, draft);
    return draft;
}
export function initializeRunControl(options) {
    const loaRoot = resolve(options.loaRoot);
    const runDir = resolve(options.runDir);
    assertPathWithin(loaRoot, runDir, 'run directory');
    assertNoSymlinkComponents(loaRoot, runDir);
    if (options.lock.bundle.id !== LOA_BUNDLE_ID
        || options.lock.adapter.id !== LOA_ADAPTER_ID
        || options.lock.adapter.lifecycle === 'planned') {
        throw new Error('cannot initialize a run from a non-executable Loa bundle');
    }
    if (options.corpus.run_id !== options.runId || options.runtimeSnapshot.run_id !== options.runId) {
        throw new Error('run artifacts disagree on run ID');
    }
    const originalLockPath = join(runDir, ORIGINAL_BUNDLE_LOCK_PATH);
    writeFileAtomic(originalLockPath, options.originalLockBytes);
    const gate = {
        id: 'GATE-S0',
        type: 'corpus-scope-sensitivity-freeze',
        status: 'awaiting-authority',
        request_ref: 'control/gates/GATE-S0-request.json',
        response_ref: null,
    };
    writeJsonAtomic(join(runDir, gate.request_ref), {
        format: 'aleph-loa-authority-request/v1',
        gate_id: 'S0',
        run_id: options.runId,
        required_decisions: [
            'scope',
            'exclusions',
            'sensitivity',
            'authority',
            'freeze',
        ],
        corpus_snapshot_ref: 'control/corpus.snapshot.json',
    });
    const state = {
        format: LOA_RUN_STATE_FORMAT,
        run_id: options.runId,
        mode: 'agent',
        full_mode: options.host.simulation ? 'fixture-simulated' : 'full-aleph',
        identity: {
            core: options.lock.core,
            adapter: options.lock.adapter,
            bundle: {
                ...options.lock.bundle,
                lock_digest: options.lock.lock_digest,
                lock_ref: ORIGINAL_BUNDLE_LOCK_PATH,
                installation_ref: options.installationRef,
            },
            checker_digest: options.lock.checker_digest,
            adapter_protocol_version: options.lock.adapter_protocol_version,
            run_format_version: options.lock.run_format_version,
            host: options.host.host,
            profile: {
                id: options.profile.id,
                digest: options.profileDigest,
            },
            models: mapModels(options.profile, options.host),
            runtime: {
                snapshot_ref: RUNTIME_SNAPSHOT_PATH,
                digest: options.runtimeSnapshot.tree_digest,
            },
        },
        corpus: {
            state: options.corpus.status,
            inventory_ref: 'control/corpus.snapshot.json',
            tree_digest: options.corpus.tree_digest,
        },
        execution: {
            core_state: 'BLOCKED',
            stage: 'S0',
            stage_status: 'awaiting-authority',
            gate,
            halt: {
                code: 'HUMAN_AUTHORITY_GATE',
                reason: 'S0 corpus scope, exclusions, sensitivity, authority, and freeze decisions are required',
                at: options.now,
                blocking: true,
            },
            resume: {
                sequence: '0',
                checkpoint_digest: '',
                last_verified_at: options.now,
            },
        },
        ledger: {
            writer_id: 'loa-orchestrator',
            sequence: '0',
            chain_head: sha256Digest(Buffer.alloc(0)),
        },
    };
    writeRunState(runDir, state);
    return state;
}
export function verifyOriginalBundleLock(runDir, state) {
    const current = state || readRunState(runDir);
    const lockPath = join(resolve(runDir), current.identity.bundle.lock_ref);
    const raw = readFileSync(lockPath);
    let value;
    try {
        value = JSON.parse(raw.toString('utf8'));
    }
    catch (error) {
        throw new Error(`original bundle lock is invalid JSON: ${error instanceof Error ? error.message : String(error)}`);
    }
    const lock = value;
    if (!isRecord(lock)
        || lock.lock_digest !== current.identity.bundle.lock_digest
        || lock.bundle?.digest !== current.identity.bundle.digest
        || lock.core?.tree_digest !== current.identity.core.tree_digest
        || lock.adapter?.tree_digest !== current.identity.adapter.tree_digest
        || lock.checker_digest !== current.identity.checker_digest) {
        throw new Error('original bundle lock disagrees with pinned run identity');
    }
    return lock;
}
export function verifyRunControl(runDir) {
    const state = readRunState(runDir);
    verifyOriginalBundleLock(runDir, state);
    const corpus = verifyCorpusSnapshot(runDir);
    if (corpus.run_id !== state.run_id
        || corpus.tree_digest !== state.corpus.tree_digest
        || corpus.status !== state.corpus.state) {
        throw new Error('corpus snapshot disagrees with run state');
    }
    return state;
}
function validGateId(value) {
    return /^GATE-[A-Za-z0-9]+(?:[._-][A-Za-z0-9]+)*$/u.test(value);
}
function exactAuthorityIdentity(value) {
    return typeof value === 'string'
        && value === value.trim()
        && value.length > 0
        && !/[\u0000-\u001f\u007f]/u.test(value);
}
const AUTHORITY_TRANSACTION_FORMAT = 'aleph-loa-authority-transaction/v1';
const AUTHORITY_LOCK_FORMAT = 'aleph-loa-authority-lock/v1';
const CORE_STAGE_CONTRACT_PATH = 'docs/architecture/04-pipeline-stages-and-dod.md';
const GATE_STAGE_RULES = {
    'external-referent-resolution': ['S8'],
    'precis-acceptance': ['S13'],
    'projection-commission': ['P1'],
    'projection-acceptance': ['P3'],
    'budget-exhaustion': CORE_STAGES,
    'suspected-contamination': CORE_STAGES,
};
function defaultAuthorityClock() {
    return { now: () => new Date().toISOString() };
}
function acquireAuthorityLock(runDir, acquiredAt, _recoverDeadOwner) {
    const lockPath = join(runDir, 'control', 'authority-transactions.lock');
    return acquireDurableProcessLock(lockPath, {
        format: AUTHORITY_LOCK_FORMAT,
        label: 'authority transaction writer lock',
        acquiredAt,
    });
}
function assertGateTypeStage(gateType, stage) {
    const stages = GATE_STAGE_RULES[gateType];
    if (!stages || !stages.includes(stage)) {
        throw new Error(`human authority gate type ${gateType} is not valid at Core stage ${stage}`);
    }
}
function assertGatePrerequisites(current, gateType, stage) {
    if (current.execution.stage !== stage) {
        throw new Error(`human authority gate cannot jump from Core stage ${current.execution.stage} to ${stage}`);
    }
    const state = current.execution.core_state;
    if (gateType === 'external-referent-resolution' && state !== 'DISTILLING') {
        throw new Error('S8 external-referent authority requires Core state DISTILLING');
    }
    if (gateType === 'precis-acceptance' && state !== 'VERIFIED') {
        throw new Error('S13 Precis acceptance requires Core state VERIFIED');
    }
    if (gateType === 'projection-commission'
        && state !== 'ACCEPTED'
        && state !== 'PROJECTION-ACCEPTED') {
        throw new Error('P1 projection commission requires Core state ACCEPTED or PROJECTION-ACCEPTED');
    }
    if (gateType === 'projection-acceptance' && state !== 'PROJECTING') {
        throw new Error('P3 projection acceptance requires Core state PROJECTING');
    }
}
function stageContractBinding(runDir, state, stage) {
    const bundleRoot = join(runDir, 'control', 'runtime', 'bundle');
    const bundle = verifyAndLoadLoaBundle(bundleRoot);
    if (bundle.lock.bundle.digest !== state.identity.bundle.digest
        || bundle.lock.core.tree_digest !== state.identity.core.tree_digest
        || bundle.lock.adapter.tree_digest !== state.identity.adapter.tree_digest
        || bundle.lock.checker_digest !== state.identity.checker_digest) {
        throw new Error('run-local verified bundle disagrees with pinned run identity');
    }
    const file = readLockedFile(bundle, CORE_STAGE_CONTRACT_PATH, 'core');
    const headings = file.toString('utf8').split(/\r?\n/u)
        .filter((line) => line.startsWith(`## ${stage} — `));
    if (headings.length !== 1) {
        throw new Error(`canonical Core has ${String(headings.length)} stage contracts for ${stage}`);
    }
    const heading = headings[0].slice('## '.length);
    const bytes = extractMarkdownHeading(file, heading, CORE_STAGE_CONTRACT_PATH);
    return {
        bundle_digest: bundle.lock.bundle.digest,
        core_digest: bundle.lock.core.tree_digest,
        path: CORE_STAGE_CONTRACT_PATH,
        selector: `heading:${heading}`,
        digest: sha256Digest(bytes),
    };
}
function transitionedState(current, at, update) {
    const draft = structuredClone(current);
    update(draft);
    if (draft.run_id !== current.run_id
        || !stableJsonBytes(draft.identity).equals(stableJsonBytes(current.identity))) {
        throw new Error('authority transition attempted to mutate pinned run identity');
    }
    draft.execution.resume.sequence = nextDecimal(current.execution.resume.sequence);
    draft.execution.resume.last_verified_at = at;
    draft.execution.resume.checkpoint_digest = stateCheckpointDigest(draft);
    assertLoaRunState(draft);
    return draft;
}
function authorityTransactionPath(runDir, operation, gateId) {
    const suffix = operation === 'open-gate' ? 'open' : 'decision';
    return join(runDir, 'control', 'transactions', `TXN-authority-${suffix}-${gateId}.json`);
}
function parseAuthorityTransaction(path) {
    const value = readJsonFile(path);
    const expectedKeys = value && typeof value === 'object' && !Array.isArray(value)
        && value.status === 'committed'
        ? [
            'artifact',
            'artifact_digest',
            'artifact_ref',
            'committed_at',
            'format',
            'gate_id',
            'operation',
            'prepared_at',
            'run_id',
            'stage',
            'state_after',
            'state_before_checkpoint',
            'status',
        ]
        : [
            'artifact',
            'artifact_digest',
            'artifact_ref',
            'format',
            'gate_id',
            'operation',
            'prepared_at',
            'run_id',
            'stage',
            'state_after',
            'state_before_checkpoint',
            'status',
        ];
    if (!isRecord(value)
        || Object.keys(value).sort(utf8Compare).join('\0') !== expectedKeys.join('\0')
        || value.format !== AUTHORITY_TRANSACTION_FORMAT
        || (value.operation !== 'open-gate' && value.operation !== 'record-decision')
        || (value.status !== 'prepared' && value.status !== 'committed')
        || typeof value.run_id !== 'string'
        || typeof value.gate_id !== 'string'
        || !validGateId(value.gate_id)
        || typeof value.stage !== 'string'
        || !CORE_STAGES.includes(value.stage)
        || typeof value.artifact_ref !== 'string'
        || typeof value.artifact_digest !== 'string'
        || !/^sha256:[0-9a-f]{64}$/u.test(value.artifact_digest)
        || typeof value.state_before_checkpoint !== 'string'
        || typeof value.prepared_at !== 'string'
        || (value.status === 'committed' && typeof value.committed_at !== 'string')
        || !isRecord(value.state_after)) {
        throw new Error(`authority transaction is malformed: ${path}`);
    }
    assertSafeRelativePath(value.artifact_ref, 'authority transaction artifact ref');
    const transaction = value;
    assertLoaRunState(transaction.state_after);
    if (transaction.state_after.run_id !== transaction.run_id
        || transaction.state_after.execution.stage !== transaction.stage
        || transaction.state_after.execution.resume.checkpoint_digest
            !== stateCheckpointDigest(transaction.state_after)
        || transaction.artifact_digest !== sha256Digest(stableJsonBytes(transaction.artifact))) {
        throw new Error(`authority transaction after-image is inconsistent: ${path}`);
    }
    const expectedRef = transaction.operation === 'open-gate'
        ? `control/gates/${transaction.gate_id}-request.json`
        : `control/gates/${transaction.gate_id}-response.json`;
    if (transaction.artifact_ref !== expectedRef) {
        throw new Error(`authority transaction targets the wrong artifact: ${path}`);
    }
    return transaction;
}
function applyAuthorityTransaction(runDir, transactionPath, transaction, committedAt) {
    const initial = readRunState(runDir);
    if (transaction.run_id !== initial.run_id) {
        throw new Error(`authority transaction belongs to another run: ${transactionPath}`);
    }
    if (!stableJsonBytes(transaction.state_after.identity).equals(stableJsonBytes(initial.identity))) {
        throw new Error(`authority transaction attempted to mutate pinned run identity: ${transactionPath}`);
    }
    const artifactPath = join(runDir, transaction.artifact_ref);
    assertPathWithin(runDir, artifactPath, 'authority transaction artifact');
    assertNoSymlinkComponents(runDir, artifactPath);
    if (existsSync(artifactPath)) {
        if (sha256Digest(readFileSync(artifactPath)) !== transaction.artifact_digest) {
            throw new Error(`authority transaction artifact changed: ${transaction.artifact_ref}`);
        }
    }
    else {
        writeJsonAtomic(artifactPath, transaction.artifact);
    }
    const current = readRunState(runDir);
    const checkpoint = current.execution.resume.checkpoint_digest;
    const afterCheckpoint = transaction.state_after.execution.resume.checkpoint_digest;
    if (checkpoint === transaction.state_before_checkpoint) {
        writeRunState(runDir, structuredClone(transaction.state_after));
    }
    else if (checkpoint !== afterCheckpoint) {
        throw new Error(`authority transaction state is neither before nor after image: ${transactionPath}`);
    }
    if (transaction.status === 'prepared') {
        writeJsonAtomic(transactionPath, {
            ...transaction,
            status: 'committed',
            committed_at: committedAt,
        });
    }
    return readRunState(runDir);
}
function recoverPendingAuthorityTransactionsUnlocked(runDir, recoveredAt) {
    const result = { committed: [], alreadyCommitted: [] };
    const root = join(runDir, 'control', 'transactions');
    if (!existsSync(root))
        return result;
    for (const name of readdirSync(root).sort(utf8Compare)) {
        if (!/^TXN-authority-(?:open|decision)-GATE-[A-Za-z0-9._-]+\.json$/u.test(name))
            continue;
        const path = join(root, name);
        const transaction = parseAuthorityTransaction(path);
        if (transaction.status === 'committed') {
            const artifactPath = join(runDir, transaction.artifact_ref);
            if (!existsSync(artifactPath)
                || sha256Digest(readFileSync(artifactPath)) !== transaction.artifact_digest) {
                throw new Error(`committed authority transaction artifact changed: ${name}`);
            }
            result.alreadyCommitted.push(name);
            continue;
        }
        applyAuthorityTransaction(runDir, path, transaction, recoveredAt);
        result.committed.push(name);
    }
    return result;
}
export function recoverPendingAuthorityTransactions(runDir, clock = defaultAuthorityClock()) {
    const root = resolve(runDir);
    const recoveredAt = clock.now();
    const release = acquireAuthorityLock(root, recoveredAt, true);
    try {
        return recoverPendingAuthorityTransactionsUnlocked(root, recoveredAt);
    }
    finally {
        release();
    }
}
function prepareAndCommitAuthorityTransaction(runDir, transaction) {
    const path = authorityTransactionPath(runDir, transaction.operation, transaction.gate_id);
    if (existsSync(path)) {
        throw new Error(`authority transaction already exists for ${transaction.gate_id}`);
    }
    writeJsonAtomic(path, transaction);
    return applyAuthorityTransaction(runDir, path, transaction, transaction.prepared_at);
}
export function openHumanAuthorityGate(runDir, options) {
    if (!validGateId(options.gateId)
        || !CORE_STAGES.includes(options.stage)
        || !exactAuthorityIdentity(options.now)) {
        throw new Error('human authority gate identity, stage, or timestamp is invalid');
    }
    assertGateTypeStage(options.gateType, options.stage);
    const root = resolve(runDir);
    const release = acquireAuthorityLock(root, options.now, false);
    try {
        recoverPendingAuthorityTransactionsUnlocked(root, options.now);
        const requestRef = `control/gates/${options.gateId}-request.json`;
        if (existsSync(join(root, requestRef))) {
            throw new Error(`human authority gate already exists: ${options.gateId}`);
        }
        const current = readRunState(root);
        if (current.execution.gate?.status === 'awaiting-authority') {
            throw new Error(`human authority gate ${current.execution.gate.id} is already awaiting a response`);
        }
        assertGatePrerequisites(current, options.gateType, options.stage);
        const contract = stageContractBinding(root, current, options.stage);
        const artifact = {
            format: 'aleph-loa-authority-request/v1',
            gate_id: options.gateId,
            gate_type: options.gateType,
            run_id: current.run_id,
            stage: options.stage,
            requested_at: options.now,
            core_stage_contract: contract,
            request: options.request,
        };
        const after = transitionedState(current, options.now, (draft) => {
            draft.execution.stage_status = 'awaiting-authority';
            draft.execution.gate = {
                id: options.gateId,
                type: options.gateType,
                status: 'awaiting-authority',
                request_ref: requestRef,
                response_ref: null,
            };
            draft.execution.halt = {
                code: 'HUMAN_AUTHORITY_GATE',
                reason: `${options.gateId} requires a recorded human authority decision`,
                at: options.now,
                blocking: true,
            };
        });
        return prepareAndCommitAuthorityTransaction(root, {
            format: AUTHORITY_TRANSACTION_FORMAT,
            operation: 'open-gate',
            status: 'prepared',
            run_id: current.run_id,
            gate_id: options.gateId,
            stage: options.stage,
            artifact_ref: requestRef,
            artifact_digest: sha256Digest(stableJsonBytes(artifact)),
            artifact,
            state_before_checkpoint: current.execution.resume.checkpoint_digest,
            state_after: after,
            prepared_at: options.now,
        });
    }
    finally {
        release();
    }
}
function validateDecisionState(current, gateType, decision) {
    if (decision.approvedState !== undefined
        && !CORE_RUN_STATES.includes(decision.approvedState)) {
        throw new Error('human authority decision names an invalid Core state');
    }
    if (decision.decision === 'decline' && decision.approvedState !== undefined) {
        throw new Error('a declined authority decision cannot name an approved Core state');
    }
    const simulated = current.full_mode === 'fixture-simulated' || decision.simulation !== null;
    if (current.full_mode === 'fixture-simulated' && decision.simulation === null) {
        throw new Error('fixture-simulated run authority responses must remain explicitly labeled');
    }
    if (decision.decision !== 'approve')
        return;
    if (gateType === 'precis-acceptance') {
        if (simulated) {
            if (decision.approvedState !== undefined) {
                throw new Error('fixture-simulated authority cannot confer acceptance');
            }
        }
        else if (decision.approvedState !== 'ACCEPTED') {
            throw new Error('live S13 approval must name Core state ACCEPTED');
        }
        return;
    }
    if (gateType === 'projection-acceptance') {
        if (simulated) {
            if (decision.approvedState !== undefined) {
                throw new Error('fixture-simulated authority cannot confer acceptance');
            }
        }
        else if (decision.approvedState !== 'PROJECTION-ACCEPTED') {
            throw new Error('live P3 approval must name Core state PROJECTION-ACCEPTED');
        }
        return;
    }
    if (gateType === 'projection-commission') {
        if (decision.approvedState !== 'PROJECTING') {
            throw new Error('P1 commission approval must advance to Core state PROJECTING');
        }
        return;
    }
    if (decision.approvedState !== undefined) {
        throw new Error(`${gateType} may not advance the Core state`);
    }
}
export function recordHumanAuthorityDecision(runDir, decision) {
    if (!validGateId(decision.gateId)
        || !exactAuthorityIdentity(decision.authorityIdentity)
        || !exactAuthorityIdentity(decision.recordedAt)
        || (decision.decision !== 'approve' && decision.decision !== 'decline')) {
        throw new Error('human authority decision identity, verdict, or timestamp is invalid');
    }
    if (decision.simulation !== null
        && (!isRecord(decision.simulation)
            || Object.keys(decision.simulation).length !== 1
            || decision.simulation.kind !== 'fixture-simulated')) {
        throw new Error('human authority simulation marker is invalid');
    }
    const root = resolve(runDir);
    const release = acquireAuthorityLock(root, decision.recordedAt, false);
    try {
        recoverPendingAuthorityTransactionsUnlocked(root, decision.recordedAt);
        const current = readRunState(root);
        const gate = current.execution.gate;
        if (!gate || gate.id !== decision.gateId || gate.status !== 'awaiting-authority') {
            throw new Error('run is not awaiting the named human authority gate');
        }
        assertGateTypeStage(gate.type, current.execution.stage);
        validateDecisionState(current, gate.type, decision);
        const responseRef = `control/gates/${decision.gateId}-response.json`;
        if (existsSync(join(root, responseRef))) {
            throw new Error(`human authority response already exists: ${decision.gateId}`);
        }
        const requestPath = join(root, gate.request_ref);
        if (!existsSync(requestPath))
            throw new Error('human authority gate request disappeared');
        const requestDigest = sha256Digest(readFileSync(requestPath));
        const artifact = {
            format: 'aleph-loa-authority-response/v1',
            gate_id: decision.gateId,
            gate_type: gate.type,
            run_id: current.run_id,
            stage: current.execution.stage,
            request_ref: gate.request_ref,
            request_digest: requestDigest,
            authority: { kind: 'human', identity: decision.authorityIdentity },
            decision: decision.decision,
            approved_state: decision.approvedState ?? null,
            recorded_at: decision.recordedAt,
            simulation: decision.simulation,
            response: decision.response,
        };
        const after = transitionedState(current, decision.recordedAt, (draft) => {
            if (decision.simulation !== null)
                draft.full_mode = 'fixture-simulated';
            if (!draft.execution.gate)
                throw new Error('human authority gate disappeared during update');
            draft.execution.gate.status = decision.decision === 'approve' ? 'approved' : 'declined';
            draft.execution.gate.response_ref = responseRef;
            if (decision.decision === 'approve') {
                draft.execution.stage_status = 'closed';
                draft.execution.halt = null;
                if (decision.approvedState)
                    draft.execution.core_state = decision.approvedState;
            }
            else {
                draft.execution.halt = {
                    code: 'HUMAN_AUTHORITY_DECLINED',
                    reason: `${decision.gateId} was declined by human authority`,
                    at: decision.recordedAt,
                    blocking: true,
                };
            }
        });
        return prepareAndCommitAuthorityTransaction(root, {
            format: AUTHORITY_TRANSACTION_FORMAT,
            operation: 'record-decision',
            status: 'prepared',
            run_id: current.run_id,
            gate_id: decision.gateId,
            stage: current.execution.stage,
            artifact_ref: responseRef,
            artifact_digest: sha256Digest(stableJsonBytes(artifact)),
            artifact,
            state_before_checkpoint: current.execution.resume.checkpoint_digest,
            state_after: after,
            prepared_at: decision.recordedAt,
        });
    }
    finally {
        release();
    }
}
