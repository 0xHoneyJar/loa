import { cpSync, existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync, } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { CORE_STAGES, LOA_LEDGER_RECEIPT_FORMAT, } from './types.js';
import { assertNoSymlinkComponents, assertPathWithin, assertSafeRelativePath, nextDecimal, sha256Digest, stableJson, stableJsonBytes, writeFileAtomic, } from './fs.js';
import { acquireDurableProcessLock, openHumanAuthorityGate, readRunState, updateRunState, } from './run-control.js';
import { ValidatedWorkerReturn } from './worker-return.js';
import { buildProceduralAuthorityLedgerRow, CLOSURE_PHASES, closurePhasesFromText, loadPinnedCoreAuthority, nextClosurePhase, nextProceduralAuthoritySequence, parseInternalAmbiguities, planProceduralAuthorityFollowup, proceduralAuthorityLedgerRowMarkdown, validateMaterialImpactAuthorityBasis, validateProceduralAuthorityRequest, validateProceduralAuthorityResponse, } from '../../../scripts/lib/internal-ambiguity.js';
import { hasRunLogEvent } from '../../../scripts/lib/check-helpers.js';
import { runK2Ambiguities } from '../../../scripts/lib/checks-k2-ambiguities.js';
import { runK2Relations } from '../../../scripts/lib/checks-k2-relations.js';
import { ResultCollector } from '../../../scripts/lib/results.js';
import { loadRun, usesInternalAmbiguityLifecycle } from '../../../scripts/lib/run-model.js';
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
    append(relativePath, validated, render) {
        assertSafeRelativePath(relativePath, 'canonical run path');
        assertSlice5WriteWindow(this.runDir, readRunState(this.runDir), relativePath, 'append');
        if (!(validated instanceof ValidatedWorkerReturn)) {
            throw new Error('canonical writes require a validated worker return');
        }
        validated.assertAuthenticAndIntact();
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
        const next = appendedBytes(before, `closure_phase: ${phase}`);
        const scratch = mkdtempSync(join(tmpdir(), 'aleph-s5-phase-'));
        const prospective = join(scratch, 'run');
        try {
            cpSync(this.runDir, prospective, { recursive: true });
            writeFileSync(join(prospective, RUN_LOG_PATH), next);
            const model = loadRun(prospective);
            const results = new ResultCollector(state.run_id);
            runK2Relations(results, model);
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
