import { cpSync, existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync, } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, join, resolve } from 'node:path';
import { CORE_STAGES, LOA_LEDGER_RECEIPT_FORMAT, } from './types.js';
import { assertNoSymlinkComponents, assertPathWithin, assertSafeRelativePath, nextDecimal, sha256Digest, stableJson, stableJsonBytes, writeFileAtomic, } from './fs.js';
import { acquireDurableProcessLock, openHumanAuthorityGate, readRunState, stateCheckpointDigest, writeRunState, updateRunState, } from './run-control.js';
import { ValidatedWorkerReturn } from './worker-return.js';
import { verifyWorkerBundle } from './worker-bundle.js';
import { buildProceduralAuthorityLedgerRow, CLOSURE_PHASES, closurePhasesFromText, loadPinnedCoreAuthority, nextClosurePhase, nextProceduralAuthoritySequence, parseInternalAmbiguities, planProceduralAuthorityFollowup, proceduralAuthorityLedgerRowMarkdown, validateMaterialImpactAuthorityBasis, validateProceduralAuthorityRequest, validateProceduralAuthorityResponse, } from '../../../scripts/lib/internal-ambiguity.js';
import { hasRunLogEvent } from '../../../scripts/lib/check-helpers.js';
import { runK2Ambiguities } from '../../../scripts/lib/checks-k2-ambiguities.js';
import { runK2Relations } from '../../../scripts/lib/checks-k2-relations.js';
import { ResultCollector } from '../../../scripts/lib/results.js';
import { loadRun, usesFormalLayoutBindings, usesInternalAmbiguityLifecycle, hasRunCapability } from '../../../scripts/lib/run-model.js';
import { assertSemanticWindow, validateSemanticPlan, validateSemanticRun, planSemanticWrite, semanticJson, semanticClosureHash, validateSemanticAcceptedBindings, SEMANTIC_PATH, semanticRequiresWritePlan, validateCompletedSemanticPlan, } from '../../../scripts/lib/semantic-review.js';
import { materialHash, assertMaterialReturnWritable, assertMaterialUseProduced, assertMaterialReviewUpheld, materialFindingRows, materialSubjectWritePaths, validateMaterialPlanIdentity, assertMaterialWriteWindow, requiresMaterialUsePlan, planRepresentationUseWrite, representationReviewView, representationUseDigest, representationUseClosureHash, representationUseNeedsReview, validateMaterialUseInput, REPRESENTATION_PATH, REPRESENTATION_USE_PATH, validateRepresentationRun, } from '../../../scripts/lib/source-representation.js';
const CANONICAL_PREFIXES = [
    'arms/',
    'clusters/',
    'ledgers/',
    'projections/',
    'synthesis/',
    'verification/',
];
const CANONICAL_FILES = new Set([
    'precis.md',
    'run-log.md',
    'run-manifest.md',
]);
function defaultClock() {
    return { now: () => new Date().toISOString() };
}
function canonicalRunPath(path) {
    return CANONICAL_FILES.has(path)
        || CANONICAL_PREFIXES.some((prefix) => path.startsWith(prefix));
}
const LINEAGE_LEDGER_PATH = 'ledgers/lineage.md';
const RELATION_LEDGER_PATH = 'ledgers/relations.md';
const AMBIGUITY_LEDGER_PATH = 'ledgers/internal-ambiguities.md';
const RUN_LOG_PATH = 'run-log.md';
const LATE_LINEAGE_HALT_CODE = 'LATE_UNIT_LINEAGE_CORRECTION';
function retainedMaterialImpactSequences(runDir, ambiguityId, assessmentSeq) {
    const root = join(runDir, 'verification', 'harness', 'S4', 'material-impact-subjects');
    if (!existsSync(root))
        return [];
    const pattern = new RegExp(`^${ambiguityId}-A${String(assessmentSeq)}-M([1-9]\\d*)\\.json$`, 'u');
    const sequences = readdirSync(root)
        .map((name) => Number(name.match(pattern)?.[1] || '0'))
        .filter((value) => value > 0)
        .sort((left, right) => left - right);
    if (sequences.some((value, index) => value !== index + 1)) {
        throw new Error('retained material-impact M history is forked or noncontiguous');
    }
    return sequences;
}
function assertRetainedMaterialImpactAuthorityBasis(runDir, subject) {
    const subjectPath = join(runDir, 'verification', 'harness', 'S4', 'material-impact-subjects', `${subject.ambiguity_id}-A${String(subject.assessment_seq)}-M${String(subject.material_impact_seq)}.json`);
    if (!existsSync(subjectPath))
        throw new Error('procedural authority subject has no retained material-impact subject');
    const model = loadRun(runDir);
    validateMaterialImpactAuthorityBasis({
        material_subject_bytes: readFileSync(subjectPath),
        verifier_files: model.files
            .filter((file) => file.relativePath.startsWith('verification/harness/'))
            .map((file) => ({
            path: file.relativePath,
            bytes: Buffer.from(file.text, 'utf8'),
        })),
        authority_subject: subject,
    });
}
function retainedClosurePhases(runDir) {
    const path = join(runDir, RUN_LOG_PATH);
    return existsSync(path) ? closurePhasesFromText(readFileSync(path, 'utf8')) : [];
}
function assertSlice5WriteWindow(runDir, state, relativePath, operation) {
    if (!usesInternalAmbiguityLifecycle(state.identity.run_format_version))
        return;
    const phases = retainedClosurePhases(runDir);
    const hasC1 = phases.includes('S4-C1-relations-closed');
    const hasC2 = phases.includes('S4-C2-ambiguities-finalized');
    if (relativePath === RELATION_LEDGER_PATH) {
        if (state.execution.stage !== 'S4') {
            throw new Error(`canonical relation ${operation} is legal only during S4`);
        }
        if (hasC1) {
            throw new Error(`post-C1 canonical relation ${operation} refused before bytes change`);
        }
    }
    if (relativePath === AMBIGUITY_LEDGER_PATH) {
        if (state.execution.stage !== 'S4' || !hasC1 || hasC2) {
            throw new Error(`canonical ambiguity ${operation} is legal only during the S4-C2 write window`);
        }
    }
}
function lineageStageIndex(stage) {
    return CORE_STAGES.indexOf(stage);
}
function appendedBytes(before, addition) {
    if (!addition.trim())
        throw new Error('ledger append must not be empty');
    const prefix = before.byteLength === 0 || before[before.byteLength - 1] === 0x0a
        ? ''
        : '\n';
    const suffix = addition.endsWith('\n') ? '' : '\n';
    return Buffer.concat([before, Buffer.from(`${prefix}${addition}${suffix}`, 'utf8')]);
}
function isRecord(value) {
    return typeof value === 'object' && value !== null && !Array.isArray(value);
}
function applySemanticTransaction(runDir, path) {
    const transaction = JSON.parse(readFileSync(path, 'utf8'));
    const { digest, status, ...payload } = transaction;
    if (transaction.format !== 'aleph-loa-semantic-transaction/v1' || !['prepared', 'committed'].includes(status)
        || materialHash(semanticJson(payload)) !== digest)
        throw new Error('SEM_STATE semantic transaction changed');
    validateSemanticPlan(transaction.plan);
    if (basename(path) !== `TXN-semantic-${materialHash(transaction.plan.key).slice(7)}.json`)
        throw new Error('SEM_STATE semantic journal reservation path differs');
    for (const ref of [...transaction.acceptance_refs, ...(status === 'prepared' ? transaction.plan.prerequisite_hashes : [])]) {
        assertSafeRelativePath(ref.path, 'semantic prerequisite');
        assertNoSymlinkComponents(runDir, join(runDir, ref.path));
        if (!existsSync(join(runDir, ref.path)) || materialHash(readFileSync(join(runDir, ref.path))) !== ref.digest)
            throw new Error(`SEM_SUBJECT lost/changed semantic prerequisite ${ref.path}`);
    }
    const state = readRunState(runDir), chainPath = join(runDir, 'control/ledger-chain.jsonl');
    if (status === 'committed') {
        if (!stableJsonBytes(state.identity).equals(stableJsonBytes(transaction.state_after.identity))
            || !readFileSync(chainPath).subarray(0, Buffer.byteLength(transaction.chain_after)).equals(Buffer.from(transaction.chain_after))) {
            throw new Error('SEM_STATE committed semantic identity/chain differs');
        }
        validateCompletedSemanticPlan(loadRun(runDir), transaction.plan);
        return;
    }
    if (state.execution.stage !== transaction.plan.stage || !stableJsonBytes(state.identity).equals(stableJsonBytes(transaction.state_after.identity))
        || ![transaction.state_checkpoint, transaction.state_after.execution.resume.checkpoint_digest].includes(state.execution.resume.checkpoint_digest))
        throw new Error('SEM_STATE semantic transaction run/stage/checkpoint differs');
    const chain = existsSync(chainPath) ? readFileSync(chainPath) : Buffer.alloc(0);
    if (![transaction.chain_before_hash, materialHash(transaction.chain_after)].includes(materialHash(chain)))
        throw new Error('SEM_STATE semantic chain changed');
    const scratch = mkdtempSync(join(tmpdir(), 'aleph-semantic-recovery-'));
    try {
        cpSync(runDir, join(scratch, 'run'), { recursive: true });
        for (const write of transaction.plan.writes) {
            assertSafeRelativePath(write.path, 'semantic write');
            assertNoSymlinkComponents(runDir, join(runDir, write.path));
            const before = existsSync(join(runDir, write.path)) ? readFileSync(join(runDir, write.path)) : Buffer.alloc(0);
            if (![write.before_hash, write.after_hash].includes(materialHash(before)))
                throw new Error(`SEM_STATE semantic preimage changed ${write.path}`);
            writeFileAtomic(join(scratch, 'run', write.path), Buffer.from(write.after_base64, 'base64'));
        }
        const proposed = loadRun(join(scratch, 'run'));
        validateSemanticRun(proposed);
        validateRepresentationRun(proposed);
        const closed = semanticClosureHash(loadRun(runDir));
        if (closed !== null && !transaction.plan.key.endsWith(':seal:C1'))
            throw new Error('SEM_WINDOW pending semantic transaction cannot reopen C1');
        for (const write of transaction.plan.writes) {
            const bytes = Buffer.from(write.after_base64, 'base64');
            if (!existsSync(join(runDir, write.path)) || !readFileSync(join(runDir, write.path)).equals(bytes))
                writeFileAtomic(join(runDir, write.path), bytes);
        }
        writeFileAtomic(chainPath, transaction.chain_after);
        writeRunState(runDir, structuredClone(transaction.state_after));
        writeFileAtomic(path, Buffer.from(semanticJson({ ...transaction, status: 'committed' })));
    }
    finally {
        rmSync(scratch, { recursive: true, force: true });
    }
}
function recoverSemanticTransactionsUnlocked(runDir) {
    const root = join(runDir, 'control/transactions');
    if (!existsSync(root))
        return;
    const pending = readdirSync(root).filter((name) => /^TXN-semantic-[0-9a-f]{64}\.json$/u.test(name))
        .map((name) => join(root, name)).filter((path) => JSON.parse(readFileSync(path, 'utf8')).status !== 'committed');
    if (pending.length > 1)
        throw new Error('SEM_STATE forked prepared semantic transactions');
    for (const path of pending)
        applySemanticTransaction(runDir, path);
}
export function recoverPendingSemanticTransactions(runDir) {
    const release = acquireLedgerLock(runDir, new Date().toISOString(), true);
    try {
        recoverSemanticTransactionsUnlocked(runDir);
    }
    finally {
        release();
    }
}
function applyMaterialTransaction(runDir, path) {
    const raw = JSON.parse(readFileSync(path, 'utf8'));
    if (!isRecord(raw) || raw.format !== 'aleph-loa-material-transaction/v1')
        throw new Error('invalid material transaction');
    const transaction = raw;
    const { digest, status, ...payload } = transaction;
    if (!['prepared', 'committed'].includes(status) || digest !== materialHash(stableJsonBytes(payload)))
        throw new Error('material transaction identity changed');
    if (status === 'committed')
        return;
    validateMaterialPlanIdentity(transaction.plan, transaction.row, transaction.stage);
    if (transaction.semantic_plan)
        validateSemanticPlan(transaction.semantic_plan);
    const state = readRunState(runDir);
    if (hasRunCapability(state.identity.run_format_version, 'semantic-unit-review') && transaction.row === null) {
        if (!transaction.semantic_plan || !stableJsonBytes(transaction.semantic_plan.writes).equals(stableJsonBytes(transaction.plan.writes))) {
            throw new Error('SEM_STATE C1 requires the composed Core semantic seal plan');
        }
        for (const ref of transaction.semantic_plan.prerequisite_hashes) {
            assertSafeRelativePath(ref.path, 'semantic C1 prerequisite');
            assertNoSymlinkComponents(runDir, join(runDir, ref.path));
            if (materialHash(readFileSync(join(runDir, ref.path))) !== ref.digest)
                throw new Error('SEM_SUBJECT C1 prerequisite changed');
        }
    }
    if (state.execution.stage !== transaction.stage
        || ![transaction.state_checkpoint, transaction.state_after.execution.resume.checkpoint_digest].includes(state.execution.resume.checkpoint_digest)
        || !stableJsonBytes(state.identity).equals(stableJsonBytes(transaction.state_after.identity)))
        throw new Error('material transaction state preimage changed');
    if (materialHash(readFileSync(join(runDir, REPRESENTATION_PATH))) !== transaction.plan.inventory_hash)
        throw new Error('material transaction capture basis changed');
    const scratch = mkdtempSync(join(tmpdir(), 'aleph-material-recovery-'));
    try {
        cpSync(runDir, join(scratch, 'run'), { recursive: true });
        for (const write of transaction.plan.writes) {
            assertSafeRelativePath(write.path, 'material transaction path');
            assertNoSymlinkComponents(runDir, join(runDir, write.path));
            const before = existsSync(join(runDir, write.path)) ? readFileSync(join(runDir, write.path)) : Buffer.alloc(0);
            const bytes = Buffer.from(write.after_base64, 'base64');
            if (![write.before_hash, write.after_hash].includes(materialHash(before))
                || bytes.toString('base64') !== write.after_base64 || materialHash(bytes) !== write.after_hash)
                throw new Error(`material preimage/after-image differs: ${write.path}`);
            writeFileAtomic(join(scratch, 'run', write.path), bytes);
        }
        const proposed = loadRun(join(scratch, 'run'));
        const context = validateRepresentationRun(proposed);
        if (transaction.semantic_plan)
            validateSemanticRun(proposed);
        if (transaction.row) {
            if (representationUseClosureHash(proposed) !== null)
                throw new Error('FROZEN_WRITE: pending material use cannot reopen C1');
            const receipt = context.uses.find((row) => row.use_id === transaction.row.use_id);
            if (stableJson(receipt) !== stableJson(transaction.row))
                throw new Error('reserved material subject/receipt changed');
        }
        else if (transaction.plan.key !== `representation-use-closure:${representationUseClosureHash(proposed)}`) {
            throw new Error('material C1 closure differs from prepared seal');
        }
        const chainPath = join(runDir, 'control', 'ledger-chain.jsonl');
        const chain = existsSync(chainPath) ? readFileSync(chainPath) : Buffer.alloc(0);
        if (![transaction.chain_before_hash, materialHash(transaction.chain_after)].includes(materialHash(chain)))
            throw new Error('material ledger chain preimage changed');
        for (const write of transaction.plan.writes)
            writeFileAtomic(join(runDir, write.path), Buffer.from(write.after_base64, 'base64'));
        writeFileAtomic(chainPath, transaction.chain_after);
        writeRunState(runDir, structuredClone(transaction.state_after));
        writeFileAtomic(path, transaction.semantic_plan ? Buffer.from(semanticJson({ ...transaction, status: 'committed' }))
            : stableJsonBytes({ ...transaction, status: 'committed' }));
    }
    finally {
        rmSync(scratch, { recursive: true, force: true });
    }
}
function recoverMaterialTransactionsUnlocked(runDir) {
    const root = join(runDir, 'control', 'transactions');
    if (!existsSync(root))
        return;
    for (const name of readdirSync(root).filter((name) => /^TXN-material-[0-9a-f]{64}\.json$/u.test(name)).sort())
        applyMaterialTransaction(runDir, join(root, name));
}
export function recoverPendingMaterialTransactions(runDir) {
    const release = acquireLedgerLock(runDir, new Date().toISOString(), true);
    try {
        recoverMaterialTransactionsUnlocked(runDir);
    }
    finally {
        release();
    }
}
const SHA256_PATTERN = /^sha256:[0-9a-f]{64}$/u;
const LEDGER_RECEIPT_KEYS = [
    'format',
    'sequence',
    'path',
    'before_digest',
    'after_digest',
    'return_digest',
    'previous_chain_digest',
    'chain_digest',
    'writer',
    'written_at',
];
function validatedLedgerReceipt(receiptRecord, label) {
    if (Object.keys(receiptRecord).sort().join('\0')
        !== [...LEDGER_RECEIPT_KEYS].sort().join('\0')) {
        throw new Error(`ledger receipt fields are malformed: ${label}`);
    }
    const receipt = receiptRecord;
    if (receipt.format !== LOA_LEDGER_RECEIPT_FORMAT
        || !/^(0|[1-9][0-9]*)$/u.test(receipt.sequence)
        || receipt.writer !== 'loa-orchestrator'
        || typeof receipt.written_at !== 'string'
        || !receipt.written_at
        || [
            receipt.before_digest,
            receipt.after_digest,
            receipt.return_digest,
            receipt.previous_chain_digest,
            receipt.chain_digest,
        ].some((digest) => !SHA256_PATTERN.test(digest))) {
        throw new Error(`ledger receipt is inconsistent: ${label}`);
    }
    const { chain_digest: _chainDigest, ...base } = receipt;
    if (sha256Digest(stableJsonBytes(base)) !== receipt.chain_digest) {
        throw new Error(`ledger receipt chain digest is invalid: ${label}`);
    }
    assertSafeRelativePath(receipt.path, 'recovered canonical run path');
    if (!canonicalRunPath(receipt.path)) {
        throw new Error(`ledger receipt targets a noncanonical path: ${label}`);
    }
    return receipt;
}
function ledgerTransactionReceipt(value, name) {
    if (value.format !== 'aleph-loa-ledger-transaction/v1'
        || !['prepared', 'committed', 'rolled-back'].includes(String(value.status))
        || typeof value.sequence !== 'string'
        || typeof value.path !== 'string'
        || typeof value.before_digest !== 'string'
        || typeof value.after_digest !== 'string'
        || typeof value.chain_before_digest !== 'string'
        || typeof value.chain_after_digest !== 'string'
        || typeof value.prior_state_checkpoint !== 'string'
        || !isRecord(value.receipt)
        || [
            value.chain_before_digest,
            value.chain_after_digest,
            value.prior_state_checkpoint,
        ].some((digest) => !SHA256_PATTERN.test(digest))) {
        throw new Error(`ledger transaction cannot be authenticated: ${name}`);
    }
    const receipt = validatedLedgerReceipt(value.receipt, name);
    if (receipt.sequence !== value.sequence
        || receipt.path !== value.path
        || receipt.before_digest !== value.before_digest
        || receipt.after_digest !== value.after_digest) {
        throw new Error(`ledger transaction receipt is inconsistent: ${name}`);
    }
    if (name !== `TXN-ledger-${receipt.sequence}.json`) {
        throw new Error(`ledger transaction filename disagrees with its receipt: ${name}`);
    }
    return receipt;
}
function readBytesOrEmpty(path) {
    return existsSync(path) ? readFileSync(path) : Buffer.alloc(0);
}
function validatedLedgerChain(runDir) {
    const chainPath = join(runDir, 'control', 'ledger-chain.jsonl');
    const bytes = readBytesOrEmpty(chainPath);
    if (bytes.byteLength > 0 && bytes[bytes.byteLength - 1] !== 0x0a) {
        throw new Error('ledger chain is not newline-terminated');
    }
    const text = bytes.toString('utf8');
    const lines = text ? text.slice(0, -1).split('\n') : [];
    if (lines.some((line) => !line))
        throw new Error('ledger chain contains an empty record');
    const receipts = [];
    const lastByPath = new Map();
    let sequence = '0';
    let head = sha256Digest(Buffer.alloc(0));
    for (const [index, line] of lines.entries()) {
        let value;
        try {
            value = JSON.parse(line);
        }
        catch {
            throw new Error(`ledger chain record ${String(index + 1)} is invalid JSON`);
        }
        if (!isRecord(value) || stableJson(value) !== line) {
            throw new Error(`ledger chain record ${String(index + 1)} is not canonical`);
        }
        const receipt = validatedLedgerReceipt(value, `chain record ${String(index + 1)}`);
        if (receipt.sequence !== nextDecimal(sequence)
            || receipt.previous_chain_digest !== head) {
            throw new Error(`ledger chain order is invalid at sequence ${receipt.sequence}`);
        }
        const priorForPath = lastByPath.get(receipt.path);
        if (priorForPath && receipt.before_digest !== priorForPath.after_digest) {
            throw new Error(`ledger target digest chain is invalid for ${receipt.path}`);
        }
        receipts.push(receipt);
        lastByPath.set(receipt.path, receipt);
        sequence = receipt.sequence;
        head = receipt.chain_digest;
    }
    const state = readRunState(runDir);
    if (state.ledger.writer_id !== 'loa-orchestrator'
        || state.ledger.sequence !== sequence
        || state.ledger.chain_head !== head) {
        throw new Error('ledger chain head or sequence disagrees with run state');
    }
    for (const receipt of lastByPath.values()) {
        const target = join(runDir, receipt.path);
        assertPathWithin(runDir, target, 'canonical ledger target');
        assertNoSymlinkComponents(runDir, target);
        if (sha256Digest(readBytesOrEmpty(target)) !== receipt.after_digest) {
            throw new Error(`canonical ledger target disagrees with chain: ${receipt.path}`);
        }
    }
    return receipts;
}
function acquireLedgerLock(runDir, acquiredAt, _recoverDeadOwner) {
    return acquireDurableProcessLock(join(runDir, 'control', 'ledger-writer.lock'), {
        format: 'aleph-loa-ledger-lock/v1',
        label: 'canonical ledger writer lock',
        acquiredAt,
    });
}
function recoverPendingLedgerTransactionsUnlocked(runDir, recoveredAt) {
    const transactionRoot = join(runDir, 'control', 'transactions');
    const result = { committed: [], alreadyCommitted: [], rolledBack: [] };
    const committedCandidates = [];
    if (!existsSync(transactionRoot)) {
        validatedLedgerChain(runDir);
        return result;
    }
    for (const name of readdirSync(transactionRoot).sort()) {
        if (!/^TXN-ledger-[0-9]+\.json$/u.test(name))
            continue;
        const transactionPath = join(transactionRoot, name);
        let value;
        try {
            value = JSON.parse(readFileSync(transactionPath, 'utf8'));
        }
        catch {
            throw new Error(`ledger transaction journal is malformed: ${name}`);
        }
        if (!isRecord(value))
            throw new Error(`ledger transaction journal is malformed: ${name}`);
        const receipt = ledgerTransactionReceipt(value, name);
        if (value.status === 'committed') {
            const finalizedAt = typeof value.committed_at === 'string'
                ? value.committed_at
                : value.recovered_at;
            if (typeof finalizedAt !== 'string' || !finalizedAt) {
                throw new Error(`committed ledger transaction has no finalization time: ${name}`);
            }
            committedCandidates.push(receipt);
            continue;
        }
        if (value.status === 'rolled-back')
            continue;
        const target = join(runDir, receipt.path);
        assertPathWithin(runDir, target, 'recovered canonical run path');
        assertNoSymlinkComponents(runDir, target);
        const targetDigest = sha256Digest(readBytesOrEmpty(target));
        const chainPath = join(runDir, 'control', 'ledger-chain.jsonl');
        const chainBefore = readBytesOrEmpty(chainPath);
        const chainDigest = sha256Digest(chainBefore);
        const state = readRunState(runDir);
        const stateIsBefore = state.execution.resume.checkpoint_digest === value.prior_state_checkpoint
            && state.ledger.chain_head === receipt.previous_chain_digest;
        const stateIsAfter = state.ledger.sequence === receipt.sequence
            && state.ledger.chain_head === receipt.chain_digest;
        if (targetDigest === value.before_digest) {
            if (chainDigest !== value.chain_before_digest || !stateIsBefore) {
                throw new Error(`ledger transaction has contradictory pre-write state: ${name}`);
            }
            writeFileAtomic(transactionPath, stableJson({
                ...value,
                status: 'rolled-back',
                recovered_at: recoveredAt,
            }));
            result.rolledBack.push(name);
            continue;
        }
        if (targetDigest !== value.after_digest) {
            throw new Error(`ledger transaction target is neither before nor after image: ${name}`);
        }
        if (chainDigest === value.chain_before_digest) {
            if (!stateIsBefore) {
                throw new Error(`ledger transaction state advanced before its chain: ${name}`);
            }
            const chainText = chainBefore.toString('utf8');
            const chainAfter = `${chainText}${chainText && !chainText.endsWith('\n') ? '\n' : ''}${stableJson(receipt)}\n`;
            if (sha256Digest(Buffer.from(chainAfter, 'utf8')) !== value.chain_after_digest) {
                throw new Error(`ledger transaction cannot reproduce its chain after-image: ${name}`);
            }
            writeFileAtomic(chainPath, chainAfter);
        }
        else if (chainDigest !== value.chain_after_digest) {
            throw new Error(`ledger transaction chain is neither before nor after image: ${name}`);
        }
        const refreshed = readRunState(runDir);
        const refreshedIsBefore = refreshed.execution.resume.checkpoint_digest
            === value.prior_state_checkpoint
            && refreshed.ledger.chain_head === receipt.previous_chain_digest;
        const refreshedIsAfter = refreshed.ledger.sequence === receipt.sequence
            && refreshed.ledger.chain_head === receipt.chain_digest;
        if (refreshedIsBefore) {
            updateRunState(runDir, recoveredAt, (draft) => {
                draft.ledger.sequence = receipt.sequence;
                draft.ledger.chain_head = receipt.chain_digest;
            });
        }
        else if (!refreshedIsAfter) {
            throw new Error(`ledger transaction run state is neither before nor after image: ${name}`);
        }
        writeFileAtomic(transactionPath, stableJson({
            ...value,
            status: 'committed',
            recovered_at: recoveredAt,
        }));
        result.committed.push(receipt);
    }
    const chain = validatedLedgerChain(runDir);
    for (const receipt of committedCandidates) {
        const matches = chain.filter((entry) => stableJson(entry) === stableJson(receipt));
        if (matches.length !== 1) {
            throw new Error(`committed ledger receipt does not occur exactly once in the validated chain: ${receipt.sequence}`);
        }
        result.alreadyCommitted.push(receipt);
    }
    return result;
}
export function recoverPendingLedgerTransactions(runDir, clock = defaultClock()) {
    const root = resolve(runDir);
    const recoveredAt = clock.now();
    const release = acquireLedgerLock(root, recoveredAt, true);
    try {
        return recoverPendingLedgerTransactionsUnlocked(root, recoveredAt);
    }
    finally {
        release();
    }
}
export class LedgerWriter {
    runDir;
    clock;
    constructor(runDir, clock = defaultClock()) {
        this.runDir = resolve(runDir);
        this.clock = clock;
    }
    executeSemanticWrite(options) {
        if (!(options.producer instanceof ValidatedWorkerReturn) || options.reviews.some((r) => !(r instanceof ValidatedWorkerReturn)))
            throw new Error('SEM_ISOLATION semantic writes require accepted transport returns');
        const release = acquireLedgerLock(this.runDir, this.clock.now(), false);
        const scratch = mkdtempSync(join(tmpdir(), 'aleph-semantic-plan-'));
        try {
            recoverMaterialTransactionsUnlocked(this.runDir);
            recoverPendingLedgerTransactionsUnlocked(this.runDir, this.clock.now());
            recoverSemanticTransactionsUnlocked(this.runDir);
            const state = readRunState(this.runDir), stage = state.execution.stage;
            if (state.ledger.writer_id !== 'loa-orchestrator' || state.execution.halt || options.producer.simulation && state.full_mode !== 'fixture-simulated')
                throw new Error('SEM_ISOLATION writer/halt/simulation boundary');
            const key = `semantic:${options.semantic_id}:${options.subject_digest}:${options.operation}:${options.record_id}`;
            const path = join(this.runDir, 'control/transactions', `TXN-semantic-${materialHash(key).slice(7)}.json`);
            if (existsSync(path)) {
                const prior = JSON.parse(readFileSync(path, 'utf8'));
                const after = Object.fromEntries(prior.plan.writes.map((w) => [w.path, Buffer.from(w.after_base64, 'base64').toString('utf8')]));
                if (semanticJson(after) !== semanticJson(options.next))
                    throw new Error('SEM_STATE changed bytes under existing semantic idempotency key');
                applySemanticTransaction(this.runDir, path);
                return prior.plan;
            }
            assertSemanticWindow(loadRun(this.runDir), stage);
            const acceptanceRefs = [];
            const acceptedBindings = [];
            for (const returned of [options.producer, ...options.reviews]) {
                returned.assertAuthenticAndIntact();
                if (returned.simulation && state.full_mode !== 'fixture-simulated')
                    throw new Error('SEM_ISOLATION simulated review in native run');
                const request = verifyWorkerBundle(join(this.runDir, 'control/worker-bundles', returned.callId));
                acceptedBindings.push({ call_id: returned.callId, context_id: returned.contextId, raw_return_hash: returned.rawDigest, role: request.role });
                if (returned !== options.producer && (request.kind !== 'refuter' || !['verifier-l2s', 'verifier-l2f'].includes(request.role)
                    || returned.producerContextId !== options.producer.contextId || returned.contextId === options.producer.contextId))
                    throw new Error('SEM_ISOLATION actual accepted reviewer context/role differs');
                for (const name of ['raw.json', 'validation.json']) {
                    const ref = `control/worker-returns/${returned.callId}/${name}`;
                    const bytes = readFileSync(join(this.runDir, ref));
                    if (name === 'raw.json' && materialHash(bytes) !== returned.rawDigest)
                        throw new Error('SEM_SUBJECT raw accepted return changed');
                    acceptanceRefs.push({ path: ref, digest: materialHash(bytes) });
                }
            }
            const prospective = join(scratch, 'run');
            cpSync(this.runDir, prospective, { recursive: true });
            const writes = Object.entries(options.next).map(([path, text]) => {
                assertSafeRelativePath(path, 'semantic write');
                assertNoSymlinkComponents(this.runDir, join(this.runDir, path));
                const before = existsSync(join(this.runDir, path)) ? readFileSync(join(this.runDir, path)) : Buffer.alloc(0);
                const after = Buffer.from(text);
                writeFileAtomic(join(prospective, path), after);
                return { path, before_hash: materialHash(before), after_base64: after.toString('base64'), after_hash: materialHash(after) };
            });
            const plan = planSemanticWrite({ model: loadRun(this.runDir), proposedModel: loadRun(prospective), stage,
                semantic_id: options.semantic_id, subject_digest: options.subject_digest, operation: options.operation, record_id: options.record_id,
                writes, prerequisite_paths: options.prerequisite_paths });
            validateSemanticAcceptedBindings(loadRun(prospective), options.semantic_id, options.operation, acceptedBindings[0], acceptedBindings.slice(1));
            validateRepresentationRun(loadRun(prospective));
            const stateAfter = structuredClone(state), chainPath = join(this.runDir, 'control/ledger-chain.jsonl');
            const chainBefore = existsSync(chainPath) ? readFileSync(chainPath, 'utf8') : '';
            let chainAfter = chainBefore;
            for (const write of plan.writes) {
                const receipt = { format: LOA_LEDGER_RECEIPT_FORMAT, sequence: nextDecimal(stateAfter.ledger.sequence), path: write.path,
                    before_digest: write.before_hash, after_digest: write.after_hash, return_digest: options.producer.rawDigest,
                    previous_chain_digest: stateAfter.ledger.chain_head, writer: 'loa-orchestrator', written_at: this.clock.now() };
                const digest = materialHash(stableJsonBytes(receipt));
                chainAfter += `${chainAfter && !chainAfter.endsWith('\n') ? '\n' : ''}${stableJson({ ...receipt, chain_digest: digest })}\n`;
                stateAfter.ledger.sequence = receipt.sequence;
                stateAfter.ledger.chain_head = digest;
            }
            stateAfter.execution.resume.sequence = nextDecimal(stateAfter.execution.resume.sequence);
            stateAfter.execution.resume.last_verified_at = this.clock.now();
            stateAfter.execution.resume.checkpoint_digest = stateCheckpointDigest(stateAfter);
            const transaction = { format: 'aleph-loa-semantic-transaction/v1', plan, acceptance_refs: acceptanceRefs,
                state_checkpoint: state.execution.resume.checkpoint_digest, state_after: stateAfter,
                chain_before_hash: materialHash(chainBefore), chain_after: chainAfter };
            writeFileAtomic(path, Buffer.from(semanticJson({ ...transaction, digest: materialHash(semanticJson(transaction)), status: 'prepared' })));
            applySemanticTransaction(this.runDir, path);
            return plan;
        }
        finally {
            rmSync(scratch, { recursive: true, force: true });
            release();
        }
    }
    assertMaterialWindow(ownerStage) {
        const state = readRunState(this.runDir);
        try {
            assertMaterialWriteWindow(loadRun(this.runDir), state.execution.stage, ownerStage);
        }
        catch (error) {
            if (usesFormalLayoutBindings(state.identity.run_format_version) && !state.execution.halt)
                updateRunState(this.runDir, this.clock.now(), (draft) => {
                    draft.execution.core_state = 'BLOCKED';
                    draft.execution.halt = {
                        code: 'SOURCE_REPRESENTATION_FROZEN_WRITE', blocking: true, at: this.clock.now(),
                        reason: error instanceof Error ? error.message : String(error),
                    };
                });
            throw error;
        }
    }
    append(relativePath, validated, render) {
        assertSafeRelativePath(relativePath, 'canonical run path');
        if (semanticRequiresWritePlan(loadRun(this.runDir), relativePath))
            throw new Error('SEM_WINDOW canonical semantic writes require a Core semantic plan');
        if (usesFormalLayoutBindings(readRunState(this.runDir).identity.run_format_version)
            && requiresMaterialUsePlan(relativePath)) {
            throw new Error('1.6 canonical material subjects require an atomic Core material-use plan');
        }
        assertSlice5WriteWindow(this.runDir, readRunState(this.runDir), relativePath, 'append');
        if (!(validated instanceof ValidatedWorkerReturn)) {
            throw new Error('canonical writes require a validated worker return');
        }
        validated.assertAuthenticAndIntact();
        if (usesFormalLayoutBindings(readRunState(this.runDir).identity.run_format_version))
            assertMaterialReturnWritable(validated.data);
        if (!canonicalRunPath(relativePath)) {
            throw new Error(`path is outside the canonical writer surface: ${relativePath}`);
        }
        return this.commitAppend(relativePath, validated.rawDigest, () => {
            const verifiedData = validated.assertAuthenticAndIntact();
            const rendered = render(verifiedData);
            validated.assertAuthenticAndIntact();
            return rendered;
        }, validated.simulation !== null, true);
    }
    reserveMaterialUse(validated, row, render) {
        if (!(validated instanceof ValidatedWorkerReturn))
            throw new Error('material reservation requires a validated producer');
        const data = validated.assertAuthenticAndIntact();
        assertMaterialUseProduced(data, row);
        const release = acquireLedgerLock(this.runDir, this.clock.now(), false);
        const scratch = mkdtempSync(join(tmpdir(), 'aleph-material-reservation-'));
        try {
            recoverMaterialTransactionsUnlocked(this.runDir);
            recoverPendingLedgerTransactionsUnlocked(this.runDir, this.clock.now());
            const state = readRunState(this.runDir);
            if (state.execution.halt
                || (validated.simulation && state.full_mode !== 'fixture-simulated'))
                throw new Error('material reservation outside write window');
            const context = validateRepresentationRun(loadRun(this.runDir));
            this.assertMaterialWindow(row.owner_stage);
            const prospective = join(scratch, 'run');
            cpSync(this.runDir, prospective, { recursive: true });
            const outputs = render(data);
            const writes = Object.entries(outputs).map(([path, text]) => {
                assertSafeRelativePath(path, 'reserved material subject');
                if (!materialSubjectWritePaths(row.subject_kind).includes(path))
                    throw new Error('reservation escaped Core subject surface');
                assertNoSymlinkComponents(this.runDir, join(this.runDir, path));
                const before = existsSync(join(this.runDir, path)) ? readFileSync(join(this.runDir, path)) : Buffer.alloc(0);
                const after = Buffer.from(text);
                writeFileAtomic(join(prospective, path), after);
                return { path, before_hash: materialHash(before), after_base64: after.toString('base64'), after_hash: materialHash(after) };
            });
            const proposed = loadRun(prospective);
            const reserved = { ...row, reviewed_by: 'none' };
            reserved.review_subject_digest = representationUseDigest(proposed, context, reserved);
            const view = representationReviewView(proposed, context, reserved);
            const id = reserved.review_subject_digest.slice('sha256:'.length);
            const reviewPath = `verification/harness/material-use-subjects/${id}.json`;
            const reservationPath = join(this.runDir, 'control', 'transactions', `RES-material-${id}.json`);
            const payload = {
                format: 'aleph-loa-material-reservation/v1', raw_digest: validated.rawDigest,
                producer_context_id: validated.contextId,
                inventory_hash: context.inventoryHash, row: reserved, writes, review_path: reviewPath, view_hash: materialHash(view),
            };
            const bytes = stableJsonBytes(payload);
            if (existsSync(reservationPath) && !readFileSync(reservationPath).equals(bytes))
                throw new Error('material reservation retry changed');
            if (existsSync(join(this.runDir, reviewPath)) && materialHash(readFileSync(join(this.runDir, reviewPath))) !== payload.view_hash)
                throw new Error('reserved review view changed');
            writeFileAtomic(reservationPath, bytes);
            writeFileAtomic(join(this.runDir, reviewPath), view, 0o400);
            return { row: reserved, review_path: reviewPath };
        }
        finally {
            rmSync(scratch, { recursive: true, force: true });
            release();
        }
    }
    appendMaterialUse(validated, row, render, review) {
        if (!(validated instanceof ValidatedWorkerReturn))
            throw new Error('material writes require a validated worker return');
        if (row.subject_kind === 'CC' && semanticRequiresWritePlan(loadRun(this.runDir), 'ledgers/claim-inventory.md')) {
            throw new Error('SEM_WINDOW 1.7 CC admission requires the composed Core semantic/material plan');
        }
        const data = validated.assertAuthenticAndIntact();
        assertMaterialUseProduced(data, row);
        if (row.subject_kind !== 'OBJ')
            this.appendMaterialFindings(validated);
        const release = acquireLedgerLock(this.runDir, this.clock.now(), false);
        const scratch = mkdtempSync(join(tmpdir(), 'aleph-material-plan-'));
        try {
            recoverMaterialTransactionsUnlocked(this.runDir);
            recoverPendingLedgerTransactionsUnlocked(this.runDir, this.clock.now());
            const state = readRunState(this.runDir);
            if (state.ledger.writer_id !== 'loa-orchestrator' || state.execution.halt
                || (validated.simulation && state.full_mode !== 'fixture-simulated')) {
                throw new Error('material write conflicts with pinned writer, halt, or simulation boundary');
            }
            const context = validateRepresentationRun(loadRun(this.runDir));
            const retained = context.uses.find((use) => use.subject_kind === row.subject_kind && use.subject_id === row.subject_id
                && use.review_subject_digest === row.review_subject_digest);
            if (retained) {
                if (stableJson(retained) !== stableJson(row))
                    throw new Error('material retry differs from retained receipt');
                return { key: `representation-use-subject:${row.review_subject_digest}:${row.subject_kind}:${row.subject_id}`,
                    inventory_hash: context.inventoryHash, writes: [] };
            }
            this.assertMaterialWindow(row.owner_stage);
            const next = render(data);
            validated.assertAuthenticAndIntact();
            const prospective = join(scratch, 'run');
            cpSync(this.runDir, prospective, { recursive: true });
            const writes = Object.entries(next).map(([path, text]) => {
                assertSafeRelativePath(path, 'material subject path');
                assertNoSymlinkComponents(this.runDir, join(this.runDir, path));
                const before = existsSync(join(this.runDir, path)) ? readFileSync(join(this.runDir, path)) : Buffer.alloc(0);
                const after = Buffer.from(text);
                writeFileAtomic(join(prospective, path), after);
                return { path, before_hash: materialHash(before), after_base64: after.toString('base64'), after_hash: materialHash(after) };
            });
            const materialInput = validateMaterialUseInput({
                requirements: JSON.parse(row.requirements), use_state: row.use_state, fidelity_claim: row.fidelity_claim,
                limitation_refs: JSON.parse(row.limitation_refs), reason: row.reason,
            });
            if (['CC', 'REL'].includes(row.subject_kind) && representationUseNeedsReview(context, materialInput)) {
                const id = row.review_subject_digest.slice('sha256:'.length);
                const reservation = JSON.parse(readFileSync(join(this.runDir, 'control', 'transactions', `RES-material-${id}.json`), 'utf8'));
                if (reservation.inventory_hash !== context.inventoryHash || reservation.raw_digest !== validated.rawDigest
                    || stableJson(reservation.writes) !== stableJson(writes)
                    || stableJson(reservation.row) !== stableJson({ ...row, reviewed_by: 'none' }))
                    throw new Error('reviewed material reservation differs');
                if (!(review instanceof ValidatedWorkerReturn))
                    throw new Error('material use requires accepted fresh L2F transport receipt');
                if (!validated.contextId || review.producerContextId !== validated.contextId || review.contextId === validated.contextId)
                    throw new Error('material reviewer did not isolate the actual producer context');
                const verdict = review.assertAuthenticAndIntact();
                assertMaterialReviewUpheld(verdict, row.review_subject_digest);
                if (review.simulation && state.full_mode !== 'fixture-simulated')
                    throw new Error('material review simulation cannot authorize this use');
                const request = verifyWorkerBundle(join(this.runDir, 'control', 'worker-bundles', review.callId));
                if (request.role !== 'verifier-l2f' || request.stage !== row.owner_stage
                    || request.allowlist.length !== 1 || request.allowlist[0].run_path !== reservation.review_path)
                    throw new Error('review transport did not challenge reserved material subject');
            }
            const plan = planRepresentationUseWrite({ model: loadRun(this.runDir), proposedModel: loadRun(prospective),
                row, subjectWrites: writes, stage: state.execution.stage });
            for (const write of plan.writes)
                writeFileAtomic(join(prospective, write.path), Buffer.from(write.after_base64, 'base64'));
            validateRepresentationRun(loadRun(prospective));
            const key = materialHash(plan.key).slice('sha256:'.length);
            const path = join(this.runDir, 'control', 'transactions', `TXN-material-${key}.json`);
            if (existsSync(path))
                throw new Error('material transaction key is already reserved with different bytes');
            const stateAfter = structuredClone(state), at = this.clock.now();
            const chainPath = join(this.runDir, 'control', 'ledger-chain.jsonl');
            const chainBefore = existsSync(chainPath) ? readFileSync(chainPath, 'utf8') : '';
            let chainAfter = chainBefore;
            for (const write of plan.writes) {
                const receipt = { format: LOA_LEDGER_RECEIPT_FORMAT, sequence: nextDecimal(stateAfter.ledger.sequence), path: write.path,
                    before_digest: write.before_hash, after_digest: write.after_hash, return_digest: validated.rawDigest,
                    previous_chain_digest: stateAfter.ledger.chain_head, writer: 'loa-orchestrator', written_at: at };
                const chainDigest = materialHash(stableJsonBytes(receipt));
                chainAfter += `${chainAfter && !chainAfter.endsWith('\n') ? '\n' : ''}${stableJson({ ...receipt, chain_digest: chainDigest })}\n`;
                stateAfter.ledger.sequence = receipt.sequence;
                stateAfter.ledger.chain_head = chainDigest;
            }
            stateAfter.execution.resume.sequence = nextDecimal(stateAfter.execution.resume.sequence);
            stateAfter.execution.resume.last_verified_at = at;
            stateAfter.execution.resume.checkpoint_digest = stateCheckpointDigest(stateAfter);
            const transaction = { format: 'aleph-loa-material-transaction/v1', plan, raw_digest: validated.rawDigest,
                state_checkpoint: state.execution.resume.checkpoint_digest, state_after: stateAfter,
                chain_before_hash: materialHash(chainBefore), chain_after: chainAfter, stage: state.execution.stage, row };
            writeFileAtomic(path, stableJsonBytes({ ...transaction, digest: materialHash(stableJsonBytes(transaction)), status: 'prepared' }));
            applyMaterialTransaction(this.runDir, path);
            return plan;
        }
        finally {
            rmSync(scratch, { recursive: true, force: true });
            release();
        }
    }
    appendMaterialFindings(validated) {
        if (!(validated instanceof ValidatedWorkerReturn))
            throw new Error('material findings require validated retained output');
        const rows = materialFindingRows(loadRun(this.runDir), validated.assertAuthenticAndIntact(), readRunState(this.runDir).execution.stage, `invocation:${validated.callId}`);
        for (const row of rows)
            this.appendMaterialUse(validated, row, () => ({}));
    }
    commitAppend(relativePath, returnDigest, render, simulated, enforceLineageWindow) {
        const target = join(this.runDir, relativePath);
        assertPathWithin(this.runDir, target, 'canonical run path');
        assertNoSymlinkComponents(this.runDir, target);
        const release = acquireLedgerLock(this.runDir, this.clock.now(), false);
        try {
            const recovery = recoverPendingLedgerTransactionsUnlocked(this.runDir, this.clock.now());
            const matches = [
                ...recovery.alreadyCommitted,
                ...recovery.committed,
            ].filter((receipt) => (receipt.path === relativePath
                && receipt.return_digest === returnDigest));
            if (matches.length > 1) {
                throw new Error('multiple committed ledger receipts claim the same worker return');
            }
            if (matches[0])
                return matches[0];
            let state = readRunState(this.runDir);
            assertSlice5WriteWindow(this.runDir, state, relativePath, 'append');
            if (enforceLineageWindow && relativePath === LINEAGE_LEDGER_PATH) {
                const stage = state.execution.stage;
                const stageIndex = lineageStageIndex(stage);
                const s2Index = lineageStageIndex('S2');
                const s4Index = lineageStageIndex('S4');
                if (stageIndex < s2Index) {
                    throw new Error(`Core lineage write window has not opened at stage ${stage}; expected S2-S4`);
                }
                if (stageIndex > s4Index) {
                    const blockedAt = this.clock.now();
                    const existingHalt = state.execution.halt;
                    if (existingHalt !== null && existingHalt.code !== LATE_LINEAGE_HALT_CODE) {
                        throw new Error(`Core late-correction boundary refused new lineage append at retained stage ${stage}; `
                            + `existing halt ${existingHalt.code} is preserved`);
                    }
                    if (state.execution.core_state !== 'BLOCKED' || existingHalt === null) {
                        state = updateRunState(this.runDir, blockedAt, (draft) => {
                            draft.execution.core_state = 'BLOCKED';
                            draft.execution.halt = {
                                code: LATE_LINEAGE_HALT_CODE,
                                reason: `new unit lineage is forbidden after S4; retained stage is ${stage}`,
                                at: blockedAt,
                                blocking: true,
                            };
                        });
                    }
                    throw new Error(`Core late-correction boundary BLOCKED new lineage append at retained stage ${stage}`);
                }
                if (state.execution.halt !== null) {
                    throw new Error(`blocked run cannot append lineage at stage ${stage}`);
                }
            }
            if (state.ledger.writer_id !== 'loa-orchestrator') {
                throw new Error('run does not designate the Loa orchestrator as ledger writer');
            }
            if (simulated && state.full_mode !== 'fixture-simulated') {
                throw new Error('fixture-simulated worker return cannot enter a full Aleph run ledger');
            }
            const before = existsSync(target) ? readFileSync(target) : Buffer.alloc(0);
            const beforeDigest = sha256Digest(before);
            const rendered = render();
            const next = appendedBytes(before, rendered);
            const afterDigest = sha256Digest(next);
            const sequence = nextDecimal(state.ledger.sequence);
            const writtenAt = this.clock.now();
            const base = {
                format: LOA_LEDGER_RECEIPT_FORMAT,
                sequence,
                path: relativePath,
                before_digest: beforeDigest,
                after_digest: afterDigest,
                return_digest: returnDigest,
                previous_chain_digest: state.ledger.chain_head,
                writer: 'loa-orchestrator',
                written_at: writtenAt,
            };
            const receipt = {
                ...base,
                chain_digest: sha256Digest(stableJsonBytes(base)),
            };
            const chainPath = join(this.runDir, 'control', 'ledger-chain.jsonl');
            const chainBefore = existsSync(chainPath) ? readFileSync(chainPath, 'utf8') : '';
            const chainAfter = `${chainBefore}${chainBefore && !chainBefore.endsWith('\n') ? '\n' : ''}${stableJson(receipt)}\n`;
            const transactionPath = join(this.runDir, 'control', 'transactions', `TXN-ledger-${sequence}.json`);
            const transaction = {
                format: 'aleph-loa-ledger-transaction/v1',
                status: 'prepared',
                sequence,
                path: relativePath,
                before_digest: beforeDigest,
                after_digest: afterDigest,
                chain_before_digest: sha256Digest(Buffer.from(chainBefore, 'utf8')),
                chain_after_digest: sha256Digest(Buffer.from(chainAfter, 'utf8')),
                prior_state_checkpoint: state.execution.resume.checkpoint_digest,
                receipt,
                prepared_at: writtenAt,
            };
            writeFileAtomic(transactionPath, stableJson(transaction));
            writeFileAtomic(target, next);
            writeFileAtomic(chainPath, chainAfter);
            updateRunState(this.runDir, writtenAt, (draft) => {
                draft.ledger.sequence = sequence;
                draft.ledger.chain_head = receipt.chain_digest;
            });
            writeFileAtomic(transactionPath, stableJson({
                ...transaction,
                status: 'committed',
                committed_at: this.clock.now(),
            }));
            return receipt;
        }
        finally {
            release();
        }
    }
    appendProceduralAuthorityResponse(requestId) {
        if (!/^GATE-S4-AMB-\d{4,}-A[1-9]\d*-Q[1-9]\d*$/u.test(requestId)) {
            throw new Error('procedural authority request ID is invalid');
        }
        const requestPath = join(this.runDir, 'control', 'gates', `${requestId}-request.json`);
        const responsePath = join(this.runDir, 'control', 'gates', `${requestId}-response.json`);
        if (!existsSync(requestPath) || !existsSync(responsePath)) {
            throw new Error('procedural authority application requires retained request and response bytes');
        }
        const requestBytes = readFileSync(requestPath);
        const responseBytes = readFileSync(responsePath);
        let request;
        let response;
        try {
            request = JSON.parse(requestBytes.toString('utf8'));
            response = JSON.parse(responseBytes.toString('utf8'));
        }
        catch {
            throw new Error('procedural authority request or response is not valid JSON');
        }
        if (!validateProceduralAuthorityRequest(request).equals(requestBytes)
            || !validateProceduralAuthorityResponse(request, requestBytes, response).equals(responseBytes)) {
            throw new Error('procedural authority request or response retained bytes are not exact canonical bytes');
        }
        const receipt = this.commitAppend(AMBIGUITY_LEDGER_PATH, sha256Digest(responseBytes), () => {
            const ambiguity = parseInternalAmbiguities(loadRun(this.runDir));
            const row = buildProceduralAuthorityLedgerRow({
                request,
                request_bytes: requestBytes,
                response,
                response_bytes: responseBytes,
                authority_seq: nextProceduralAuthoritySequence(ambiguity.t5_3Rows.map((entry) => entry.values), request.ambiguity_id),
            });
            return proceduralAuthorityLedgerRowMarkdown(row);
        }, false, false);
        const state = readRunState(this.runDir);
        if (state.execution.gate?.id !== requestId
            || state.execution.gate.status !== 'approved'
            || state.execution.gate.response_ref !== `control/gates/${requestId}-response.json`) {
            throw new Error('procedural authority response is not the retained approved active gate');
        }
        if (state.execution.halt?.code === 'S4_C2_RESPONSE_APPLICATION_REQUIRED') {
            updateRunState(this.runDir, this.clock.now(), (draft) => {
                draft.execution.stage_status = 'running';
                if (response.selected_action === 'carry-unresolved'
                    || response.selected_action === 'restrict-downstream-use') {
                    draft.execution.halt = null;
                }
                else {
                    const successor = response.selected_action === 'request-successor-corpus-run';
                    const suspensive = response.selected_action === 'block-at-current-barrier';
                    if (successor || suspensive)
                        draft.execution.core_state = 'BLOCKED';
                    draft.execution.halt = {
                        code: successor
                            ? 'SUCCESSOR_CORPUS_RUN_REQUIRED'
                            : suspensive
                                ? 'BLOCKED_AT_S4_C2'
                                : 'S4_C2_FOLLOWUP_REQUEST_REQUIRED',
                        reason: `${response.selected_action} retained; S4-C2 cannot finalize without the next exact durable action`,
                        at: this.clock.now(),
                        blocking: true,
                    };
                }
            });
        }
        return receipt;
    }
    openProceduralAuthorityFollowup(options) {
        if (!/^GATE-S4-AMB-\d{4,}-A[1-9]\d*-Q[1-9]\d*$/u.test(options.request_id)) {
            throw new Error('procedural follow-up predecessor request ID is invalid');
        }
        const gatesRoot = join(this.runDir, 'control', 'gates');
        const requestPath = join(gatesRoot, `${options.request_id}-request.json`);
        if (!existsSync(requestPath))
            throw new Error('procedural follow-up predecessor request is absent');
        const requestBytes = readFileSync(requestPath);
        let request;
        try {
            request = JSON.parse(requestBytes.toString('utf8'));
        }
        catch {
            throw new Error('procedural follow-up predecessor request is not valid JSON');
        }
        if (!validateProceduralAuthorityRequest(request).equals(requestBytes)) {
            throw new Error('procedural follow-up predecessor request bytes are not canonical');
        }
        const responsePath = join(gatesRoot, `${options.request_id}-response.json`);
        const responseBytes = existsSync(responsePath) ? readFileSync(responsePath) : null;
        let response = null;
        if (responseBytes) {
            try {
                response = JSON.parse(responseBytes.toString('utf8'));
            }
            catch {
                throw new Error('procedural follow-up predecessor response is not valid JSON');
            }
            if (!validateProceduralAuthorityResponse(request, requestBytes, response).equals(responseBytes)) {
                throw new Error('procedural follow-up predecessor response bytes are not canonical');
            }
            const responseDigest = sha256Digest(responseBytes);
            const ambiguity = parseInternalAmbiguities(loadRun(this.runDir));
            const retained = ambiguity.t5_3Rows.some((row) => (row.values.ambiguityId === request.ambiguity_id
                && row.values.assessmentSeq === String(request.assessment_seq)
                && row.values.authorityRef === `authority-response:${response?.response_id}@${responseDigest}`));
            if (!retained) {
                throw new Error('procedural follow-up requires the predecessor response to be applied to T5.3 exactly once');
            }
        }
        const prefix = `GATE-S4-${request.ambiguity_id}-A${String(request.assessment_seq)}-Q`;
        const existing = readdirSync(gatesRoot)
            .filter((name) => name.startsWith(prefix) && name.endsWith('-request.json'))
            .map((name) => name.slice(0, -'-request.json'.length))
            .sort((left, right) => (Number(left.slice(prefix.length)) - Number(right.slice(prefix.length))));
        const currentSequence = Number(options.request_id.slice(prefix.length));
        const currentHistory = existing.filter((id) => Number(id.slice(prefix.length)) <= currentSequence);
        const materialSequences = retainedMaterialImpactSequences(this.runDir, request.ambiguity_id, request.assessment_seq);
        assertRetainedMaterialImpactAuthorityBasis(this.runDir, options.next_subject);
        const nextRequest = planProceduralAuthorityFollowup({
            current_request: request,
            current_request_bytes: requestBytes,
            current_response: response,
            current_response_bytes: responseBytes,
            existing_request_ids: currentHistory,
            retained_material_impact_seqs: materialSequences,
            reason: options.reason,
            next_subject: options.next_subject,
            presentation: options.presentation,
            required_authority_identity: options.required_authority_identity,
            prepared_by: options.prepared_by,
            requested_at: options.requested_at,
        });
        const nextPath = join(gatesRoot, `${nextRequest.request_id}-request.json`);
        const unexpected = existing.filter((id) => (Number(id.slice(prefix.length)) > currentSequence
            && id !== nextRequest.request_id));
        if (unexpected.length) {
            throw new Error('procedural follow-up found a forked or skipped retained Q request');
        }
        if (existsSync(nextPath)) {
            const retained = readFileSync(nextPath);
            if (!validateProceduralAuthorityRequest(nextRequest).equals(retained)) {
                throw new Error('retained procedural follow-up request disagrees with the Core plan');
            }
            const state = readRunState(this.runDir);
            if (state.execution.gate?.id !== nextRequest.request_id
                || state.execution.gate.status !== 'awaiting-authority') {
                throw new Error('retained procedural follow-up request is not the one active request');
            }
            return nextRequest;
        }
        openHumanAuthorityGate(this.runDir, {
            gateId: nextRequest.request_id,
            gateType: 'internal-ambiguity-procedural-decision',
            stage: 'S4',
            now: options.requested_at,
            request: nextRequest,
            proceduralFollowup: {
                priorGateId: options.request_id,
                reason: options.reason,
            },
        });
        return nextRequest;
    }
    replace(relativePath, validated, _render) {
        assertSafeRelativePath(relativePath, 'canonical run path');
        assertSlice5WriteWindow(this.runDir, readRunState(this.runDir), relativePath, 'replace');
        if (!(validated instanceof ValidatedWorkerReturn)) {
            throw new Error('canonical writes require a validated worker return');
        }
        validated.assertAuthenticAndIntact();
        throw new Error('canonical ledger replacement is not a supported Loa persistence operation');
    }
    remove(relativePath) {
        assertSafeRelativePath(relativePath, 'canonical run path');
        assertSlice5WriteWindow(this.runDir, readRunState(this.runDir), relativePath, 'delete');
        throw new Error('canonical ledger deletion is not a supported Loa persistence operation');
    }
    retarget(relativePath, validated, _render) {
        assertSafeRelativePath(relativePath, 'canonical run path');
        assertSlice5WriteWindow(this.runDir, readRunState(this.runDir), relativePath, 'retarget');
        if (!(validated instanceof ValidatedWorkerReturn)) {
            throw new Error('canonical writes require a validated worker return');
        }
        validated.assertAuthenticAndIntact();
        throw new Error('canonical relation retarget is not a supported Loa persistence operation');
    }
    advanceSlice5ClosurePhase(phase) {
        const material = usesFormalLayoutBindings(readRunState(this.runDir).identity.run_format_version)
            && phase === 'S4-C1-relations-closed';
        const release = material ? acquireLedgerLock(this.runDir, this.clock.now(), false) : () => { };
        try {
            if (material) {
                recoverMaterialTransactionsUnlocked(this.runDir);
                if (hasRunCapability(readRunState(this.runDir).identity.run_format_version, 'semantic-unit-review')) {
                    recoverPendingLedgerTransactionsUnlocked(this.runDir, this.clock.now());
                    recoverSemanticTransactionsUnlocked(this.runDir);
                }
                if (retainedClosurePhases(this.runDir).includes(phase))
                    return;
            }
            this.commitSlice5ClosurePhase(phase);
        }
        finally {
            release();
        }
    }
    commitSlice5ClosurePhase(phase) {
        const state = readRunState(this.runDir);
        if (!usesInternalAmbiguityLifecycle(state.identity.run_format_version)
            || state.execution.stage !== 'S4') {
            throw new Error('Slice 5 closure phases require a run-format 1.5 S4 run');
        }
        const phases = retainedClosurePhases(this.runDir);
        if (nextClosurePhase(phases) !== phase) {
            throw new Error(`Slice 5 closure phase ${phase} is not the single next durable phase`);
        }
        const runLogPath = join(this.runDir, RUN_LOG_PATH);
        const before = existsSync(runLogPath) ? readFileSync(runLogPath) : Buffer.alloc(0);
        let addition = `closure_phase: ${phase}`;
        if (usesFormalLayoutBindings(state.identity.run_format_version)) {
            validateRepresentationRun(loadRun(this.runDir));
            if (phase === 'S4-C1-relations-closed')
                addition += `\nrepresentation_use_closure_hash: ${materialHash(readFileSync(join(this.runDir, REPRESENTATION_USE_PATH)))}`;
        }
        if (hasRunCapability(state.identity.run_format_version, 'semantic-unit-review') && phase === 'S4-C1-relations-closed') {
            const semantic = validateSemanticRun(loadRun(this.runDir));
            if (semantic.pending.length)
                throw new Error('SEM_ACCOUNTING pending semantic subjects block C1');
            addition += `\nsemantic_review_closure_hash: ${materialHash(readFileSync(join(this.runDir, SEMANTIC_PATH)))}`;
        }
        const next = appendedBytes(before, addition);
        const scratch = mkdtempSync(join(tmpdir(), 'aleph-s5-phase-'));
        const prospective = join(scratch, 'run');
        let semanticSealPlan;
        try {
            cpSync(this.runDir, prospective, { recursive: true });
            writeFileSync(join(prospective, RUN_LOG_PATH), next);
            const model = loadRun(prospective);
            if (hasRunCapability(state.identity.run_format_version, 'semantic-unit-review'))
                validateSemanticRun(model);
            if (hasRunCapability(state.identity.run_format_version, 'semantic-unit-review') && phase === 'S4-C1-relations-closed') {
                semanticSealPlan = planSemanticWrite({ model: loadRun(this.runDir), proposedModel: model, stage: 'S4',
                    semantic_id: 'none', subject_digest: materialHash(readFileSync(join(this.runDir, SEMANTIC_PATH))),
                    operation: 'seal', record_id: 'C1', prerequisite_paths: [],
                    writes: [{ path: RUN_LOG_PATH, before_hash: materialHash(before), after_base64: next.toString('base64'), after_hash: materialHash(next) }] });
            }
            const results = new ResultCollector(state.run_id);
            runK2Relations(results, model);
            if (usesFormalLayoutBindings(state.identity.run_format_version))
                validateRepresentationRun(model);
            if (phase !== 'S4-C1-relations-closed') {
                const bundleRoot = join(this.runDir, 'control', 'runtime', 'bundle');
                const authority = loadPinnedCoreAuthority({
                    bundle_lock_path: join(bundleRoot, 'bundle.lock.json'),
                    expected_bundle_digest: state.identity.bundle.digest,
                    expected_core_digest: state.identity.core.tree_digest,
                });
                runK2Ambiguities(results, model, authority);
            }
            const failed = results.checks.filter((check) => check.status === 'FAIL');
            if (failed.length > 0) {
                throw new Error(`Slice 5 closure phase ${phase} failed Core structural checks: ${failed.map((check) => check.message).join('; ')}`);
            }
        }
        finally {
            rmSync(scratch, { recursive: true, force: true });
        }
        if (usesFormalLayoutBindings(state.identity.run_format_version) && phase === 'S4-C1-relations-closed') {
            const seal = materialHash(readFileSync(join(this.runDir, REPRESENTATION_USE_PATH)));
            const stateAfter = structuredClone(state);
            stateAfter.execution.resume.sequence = nextDecimal(stateAfter.execution.resume.sequence);
            stateAfter.execution.resume.last_verified_at = this.clock.now();
            const chainPath = join(this.runDir, 'control', 'ledger-chain.jsonl');
            const chain = existsSync(chainPath) ? readFileSync(chainPath, 'utf8') : '';
            let chainAfter = chain;
            if (semanticSealPlan) {
                const receipt = { format: LOA_LEDGER_RECEIPT_FORMAT, sequence: nextDecimal(stateAfter.ledger.sequence),
                    path: RUN_LOG_PATH, before_digest: materialHash(before), after_digest: materialHash(next),
                    return_digest: semanticSealPlan.subject_digest, previous_chain_digest: stateAfter.ledger.chain_head,
                    writer: 'loa-orchestrator', written_at: this.clock.now() };
                const digest = materialHash(stableJsonBytes(receipt));
                chainAfter += `${chainAfter && !chainAfter.endsWith('\n') ? '\n' : ''}${stableJson({ ...receipt, chain_digest: digest })}\n`;
                stateAfter.ledger.sequence = receipt.sequence;
                stateAfter.ledger.chain_head = digest;
            }
            stateAfter.execution.resume.checkpoint_digest = stateCheckpointDigest(stateAfter);
            const plan = {
                key: `representation-use-closure:${seal}`, inventory_hash: materialHash(readFileSync(join(this.runDir, REPRESENTATION_PATH))),
                writes: [{ path: RUN_LOG_PATH, before_hash: materialHash(before), after_base64: next.toString('base64'), after_hash: materialHash(next) }],
            };
            const transaction = { format: 'aleph-loa-material-transaction/v1', plan, raw_digest: seal,
                state_checkpoint: state.execution.resume.checkpoint_digest, state_after: stateAfter,
                chain_before_hash: materialHash(chain), chain_after: chainAfter, stage: 'S4', row: null,
                ...(semanticSealPlan ? { semantic_plan: semanticSealPlan } : {}) };
            const path = join(this.runDir, 'control', 'transactions', `TXN-material-${materialHash(plan.key).slice(7)}.json`);
            const record = { ...transaction, digest: materialHash(stableJsonBytes(transaction)), status: 'prepared' };
            writeFileAtomic(path, semanticSealPlan ? Buffer.from(semanticJson(record)) : stableJsonBytes(record));
            applyMaterialTransaction(this.runDir, path);
            return;
        }
        writeFileAtomic(runLogPath, next);
        updateRunState(this.runDir, this.clock.now(), (draft) => {
            if (phase === 'S4-C3-exit')
                draft.execution.stage_status = 'closed';
        });
    }
    enterS5AfterSlice5Closure() {
        const state = readRunState(this.runDir);
        const phases = retainedClosurePhases(this.runDir);
        if (state.execution.stage !== 'S4'
            || state.execution.stage_status !== 'closed'
            || phases.length !== CLOSURE_PHASES.length
            || phases.some((phase, index) => phase !== CLOSURE_PHASES[index])
            || state.execution.halt !== null) {
            throw new Error('S5 entry requires a complete unblocked S4-C3 closure');
        }
        const model = loadRun(this.runDir);
        const results = new ResultCollector(state.run_id);
        runK2Relations(results, model);
        const bundleRoot = join(this.runDir, 'control', 'runtime', 'bundle');
        const authority = loadPinnedCoreAuthority({
            bundle_lock_path: join(bundleRoot, 'bundle.lock.json'),
            expected_bundle_digest: state.identity.bundle.digest,
            expected_core_digest: state.identity.core.tree_digest,
        });
        runK2Ambiguities(results, model, authority);
        const failed = results.checks.filter((check) => check.status === 'FAIL');
        if (failed.length > 0) {
            throw new Error(`S5 entry failed retained Core structural checks: ${failed.map((check) => check.message).join('; ')}`);
        }
        const runLogPath = join(this.runDir, RUN_LOG_PATH);
        const before = existsSync(runLogPath) ? readFileSync(runLogPath) : Buffer.alloc(0);
        const existingS5Entry = hasRunLogEvent(model.runLog, 'S5', 'entry');
        const enteredAt = this.clock.now();
        if (!existingS5Entry) {
            writeFileAtomic(runLogPath, appendedBytes(before, `## ${enteredAt} — S5 — entry`));
        }
        updateRunState(this.runDir, enteredAt, (draft) => {
            draft.execution.stage = 'S5';
            draft.execution.stage_status = 'running';
        });
    }
}
