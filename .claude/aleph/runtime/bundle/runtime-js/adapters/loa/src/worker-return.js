import { existsSync, mkdirSync, readFileSync } from 'node:fs';
import { basename, dirname, join, resolve, } from 'node:path';
import { LOA_WORKER_VALIDATION_FORMAT, } from './types.js';
import { assertNoSymlinkComponents, sha256Digest, stableJson, stableJsonBytes, writeFileAtomic, writeJsonAtomic, } from './fs.js';
import { assertWorkerRoleIsolation, verifyWorkerBundle, } from './worker-bundle.js';
import { contractExemplarToJsonSchema, validateWorkerReturnContract, } from '../../../scripts/lib/worker-return-contract.js';
import { validateMaterialProducerReturn } from '../../../scripts/lib/source-representation.js';
import { isSemanticOutputContract, validateSemanticReturn, parseSemanticJson, semanticJson, validateSemanticProducerDelivery } from '../../../scripts/lib/semantic-review.js';
import { loadRun } from '../../../scripts/lib/run-model.js';
export { contractExemplarToJsonSchema };
const VALIDATED_TOKEN = Symbol('validated-worker-return');
/**
 * Resolve the sole quarantine directory permitted for a sealed worker call.
 * The worker bundle itself must occupy the matching canonical run slot so a
 * caller cannot choose a different run root and then smuggle a return into a
 * canonical ledger, verification directory, or another call's quarantine.
 */
export function canonicalWorkerReturnRoot(workerBundleRootInput, callId, suppliedReturnRoot) {
    const workerBundleRoot = resolve(workerBundleRootInput);
    const workerBundlesRoot = dirname(workerBundleRoot);
    const controlRoot = dirname(workerBundlesRoot);
    const runDir = dirname(controlRoot);
    const expectedWorkerBundleRoot = join(runDir, 'control', 'worker-bundles', callId);
    if (basename(workerBundleRoot) !== callId
        || basename(workerBundlesRoot) !== 'worker-bundles'
        || basename(controlRoot) !== 'control'
        || workerBundleRoot !== expectedWorkerBundleRoot) {
        throw new Error(`worker bundle root must be the canonical control/worker-bundles/${callId} path`);
    }
    const expectedReturnRoot = join(runDir, 'control', 'worker-returns', callId);
    const actualReturnRoot = suppliedReturnRoot === undefined
        ? expectedReturnRoot
        : resolve(suppliedReturnRoot);
    if (actualReturnRoot !== expectedReturnRoot) {
        throw new Error(`worker return root must exactly match control/worker-returns/${callId} in the sealed run`);
    }
    assertNoSymlinkComponents(runDir, expectedReturnRoot);
    return expectedReturnRoot;
}
function deepFreezeJson(value) {
    if (typeof value !== 'object' || value === null || Object.isFrozen(value))
        return value;
    if (Array.isArray(value)) {
        for (const entry of value)
            deepFreezeJson(entry);
    }
    else {
        for (const entry of Object.values(value))
            deepFreezeJson(entry);
    }
    return Object.freeze(value);
}
export class ValidatedWorkerReturn {
    callId;
    data;
    dataDigest;
    rawDigest;
    contractDigest;
    validationDigest;
    simulation;
    contextId;
    producerContextId;
    #canonicalBytes;
    #token;
    #semantic;
    constructor(token, callId, data, rawDigest, contractDigest, validationDigest, simulation, contextId = null, producerContextId = null, semantic = false) {
        if (token !== VALIDATED_TOKEN)
            throw new Error('validated returns are created only by validation');
        const canonicalBytes = semantic ? Buffer.from(semanticJson(data)) : stableJsonBytes(data);
        const canonicalClone = JSON.parse(canonicalBytes.toString('utf8'));
        this.#token = token;
        this.#semantic = semantic;
        this.#canonicalBytes = Buffer.from(canonicalBytes);
        this.callId = callId;
        this.data = deepFreezeJson(canonicalClone);
        this.dataDigest = sha256Digest(canonicalBytes);
        this.rawDigest = rawDigest;
        this.contractDigest = contractDigest;
        this.validationDigest = validationDigest;
        this.contextId = contextId;
        this.producerContextId = producerContextId;
        this.simulation = simulation === null
            ? null
            : Object.freeze({ kind: simulation.kind });
        Object.freeze(this);
    }
    isAuthentic() {
        try {
            this.assertAuthenticAndIntact();
            return true;
        }
        catch {
            return false;
        }
    }
    canonicalBytes() {
        this.assertAuthenticAndIntact();
        return Buffer.from(this.#canonicalBytes);
    }
    assertAuthenticAndIntact() {
        if (this.#token !== VALIDATED_TOKEN) {
            throw new Error('worker return does not carry the validation brand');
        }
        const currentBytes = this.#semantic ? Buffer.from(semanticJson(this.data)) : stableJsonBytes(this.data);
        if (!currentBytes.equals(this.#canonicalBytes)
            || sha256Digest(currentBytes) !== this.dataDigest) {
            throw new Error('validated worker return data failed its integrity check');
        }
        return this.data;
    }
}
function parseRaw(raw, semantic = false) {
    if (Buffer.isBuffer(raw) || typeof raw === 'string') {
        const bytes = Buffer.isBuffer(raw) ? raw : Buffer.from(raw, 'utf8');
        try {
            return { value: JSON.parse(bytes.toString('utf8')), bytes };
        }
        catch (error) {
            return {
                value: null,
                bytes,
                error: `worker return is invalid JSON: ${error instanceof Error ? error.message : String(error)}`,
            };
        }
    }
    try {
        const bytes = semantic ? Buffer.from(semanticJson(raw)) : stableJsonBytes(raw);
        return {
            value: JSON.parse(bytes.toString('utf8')),
            bytes,
        };
    }
    catch (error) {
        return {
            value: null,
            bytes: Buffer.from(String(raw), 'utf8'),
            error: `worker return is not serializable JSON: ${error instanceof Error ? error.message : String(error)}`,
        };
    }
}
export function validateWorkerDispatch(request, receipt) {
    assertWorkerRoleIsolation(request.role, request.kind, request.isolation?.producer_context_id);
    if (receipt.format !== 'aleph-loa-worker-dispatch/v1'
        || receipt.call_id !== request.call_id
        || !receipt.context_id
        || receipt.fresh_context !== true
        || receipt.inherited_context !== false
        || receipt.filesystem !== 'bundle-read-only') {
        throw new Error('worker dispatch receipt does not prove required isolation');
    }
    if (receipt.simulation !== null
        && (typeof receipt.simulation !== 'object'
            || Object.keys(receipt.simulation).length !== 1
            || receipt.simulation.kind !== 'fixture-simulated')) {
        throw new Error('worker dispatch receipt has an invalid simulation marker');
    }
    if (request.kind === 'refuter'
        && receipt.context_id === request.isolation.producer_context_id) {
        throw new Error('fresh-context refuter reused the producer context');
    }
    if (receipt.producer_context_id !== request.isolation.producer_context_id) {
        throw new Error('worker dispatch receipt producer context disagrees with request');
    }
    if (stableJson(receipt.model_identity) !== stableJson(request.model_identity)) {
        throw new Error('worker dispatch used an unpinned model identity');
    }
}
export function validateWorkerReturn(options) {
    const workerRoot = resolve(options.workerBundleRoot);
    const request = verifyWorkerBundle(workerRoot);
    const returnRoot = canonicalWorkerReturnRoot(workerRoot, request.call_id, options.returnRoot);
    validateWorkerDispatch(request, options.dispatchReceipt);
    mkdirSync(returnRoot, { recursive: true });
    const contractPath = join(workerRoot, 'contracts', 'output.json');
    if (!existsSync(contractPath))
        throw new Error('worker bundle omits its Core output contract');
    const contractBytes = readFileSync(contractPath);
    const contractDigest = sha256Digest(contractBytes);
    if (contractDigest !== request.output_contract.digest) {
        throw new Error('worker output contract digest mismatch');
    }
    if (!request.output_contract.selector.startsWith('output-contract:')
        || request.output_contract.selector.length === 'output-contract:'.length) {
        throw new Error('worker output contract selector is invalid');
    }
    const parsed = parseRaw(options.raw, isSemanticOutputContract(JSON.parse(contractBytes.toString('utf8'))));
    const rawDigest = sha256Digest(parsed.bytes);
    writeFileAtomic(join(returnRoot, 'raw.json'), parsed.bytes);
    const errors = [];
    let canonicalValue = null;
    let semantic = false;
    if (parsed.error) {
        errors.push(parsed.error);
    }
    else {
        let example;
        try {
            example = JSON.parse(contractBytes.toString('utf8'));
        }
        catch (error) {
            throw new Error(`sealed Core output contract is invalid JSON: ${error instanceof Error ? error.message : String(error)}`);
        }
        const validation = validateWorkerReturnContract(parsed.bytes, example);
        semantic = isSemanticOutputContract(example);
        errors.push(...validation.errors);
        canonicalValue = validation.canonicalValue;
        if (canonicalValue !== null && errors.length === 0) {
            if (isSemanticOutputContract(example)) {
                const runDir = dirname(dirname(dirname(workerRoot)));
                const model = loadRun(runDir);
                const subjectPath = request.role === 'verifier-l2s'
                    ? request.allowlist.find((a) => a.run_path.startsWith('verification/harness/semantic-subjects/'))?.run_path : undefined;
                const subject = subjectPath ? parseSemanticJson(readFileSync(join(runDir, subjectPath))) : undefined;
                const context = request.role === 'verifier-l2s' ? {
                    model, subject, owner_stage: request.stage, legal_source_ids: subject.anchors.map((a) => a.source_id),
                } : validateSemanticProducerDelivery(model, request.role, request.stage, request.call_id, request.task_line, request.allowlist.map((a) => ({ path: a.run_path, bytes: readFileSync(join(workerRoot, a.attachment_path)) })));
                const validation = validateSemanticReturn(request.role, model.manifest.runFormatVersion, canonicalValue, context);
                errors.push(...validation.errors);
            }
            try {
                validateMaterialProducerReturn(canonicalValue);
            }
            catch (error) {
                errors.push(error instanceof Error ? error.message : String(error));
            }
            if (request.role === 'verifier-l2f') {
                const returned = canonicalValue;
                if (!Array.isArray(returned.candidate_evidence) || returned.candidate_evidence.length !== 0) {
                    errors.push('L2F requires empty candidate_evidence');
                }
            }
        }
    }
    const report = {
        format: LOA_WORKER_VALIDATION_FORMAT,
        call_id: request.call_id,
        contract_digest: contractDigest,
        raw_digest: rawDigest,
        simulation: options.dispatchReceipt.simulation,
        result: errors.length > 0 ? 'FAIL' : 'PASS',
        errors,
    };
    writeJsonAtomic(join(returnRoot, 'validation.json'), report);
    if (errors.length > 0)
        return { report, validated: null };
    const validationDigest = sha256Digest(stableJsonBytes(report));
    const validated = new ValidatedWorkerReturn(VALIDATED_TOKEN, request.call_id, canonicalValue, rawDigest, contractDigest, validationDigest, options.dispatchReceipt.simulation, options.dispatchReceipt.context_id, options.dispatchReceipt.producer_context_id, semantic);
    writeFileAtomic(join(returnRoot, 'validated.json'), validated.canonicalBytes());
    return {
        report,
        validated,
    };
}
