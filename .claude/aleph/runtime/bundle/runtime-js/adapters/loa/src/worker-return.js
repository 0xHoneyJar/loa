import { existsSync, mkdirSync, readFileSync } from 'node:fs';
import { basename, dirname, join, resolve, } from 'node:path';
import { LOA_WORKER_VALIDATION_FORMAT, } from './types.js';
import { assertNoSymlinkComponents, sha256Digest, stableJson, stableJsonBytes, writeFileAtomic, writeJsonAtomic, } from './fs.js';
import { verifyWorkerBundle } from './worker-bundle.js';
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
    #canonicalBytes;
    #token;
    constructor(token, callId, data, rawDigest, contractDigest, validationDigest, simulation) {
        if (token !== VALIDATED_TOKEN)
            throw new Error('validated returns are created only by validation');
        const canonicalBytes = stableJsonBytes(data);
        const canonicalClone = JSON.parse(canonicalBytes.toString('utf8'));
        this.#token = token;
        this.#canonicalBytes = Buffer.from(canonicalBytes);
        this.callId = callId;
        this.data = deepFreezeJson(canonicalClone);
        this.dataDigest = sha256Digest(canonicalBytes);
        this.rawDigest = rawDigest;
        this.contractDigest = contractDigest;
        this.validationDigest = validationDigest;
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
        const currentBytes = stableJsonBytes(this.data);
        if (!currentBytes.equals(this.#canonicalBytes)
            || sha256Digest(currentBytes) !== this.dataDigest) {
            throw new Error('validated worker return data failed its integrity check');
        }
        return this.data;
    }
}
function isRecord(value) {
    return typeof value === 'object' && value !== null && !Array.isArray(value);
}
function hasText(value) {
    return value.trim().length > 0;
}
function validateRequiredString(value, path, errors) {
    if (typeof value !== 'string') {
        errors.push(`${path} must be a string`);
        return false;
    }
    if (!hasText(value)) {
        errors.push(`${path} must be nonempty`);
        return false;
    }
    return true;
}
function literalPattern(literal) {
    const escaped = literal
        .split('…')
        .map((part) => part.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&'))
        .join('.+');
    return new RegExp(`^(?:${escaped})$`, 'u');
}
function exemplarAlternatives(example) {
    if (example.includes('|'))
        return example.split('|');
    const slashParts = example.split('/');
    if (slashParts.length > 1 && slashParts.every((part) => part.includes('…'))) {
        return slashParts;
    }
    return [example];
}
function nonemptyStringSchema() {
    return {
        type: 'string',
        pattern: '^[\\s\\S]*\\S[\\s\\S]*$',
    };
}
/**
 * Convert the canonical Core exemplar into the stricter JSON Schema accepted
 * by Claude Code. The existing post-return validator remains authoritative;
 * this schema prevents malformed shapes from leaving the model boundary.
 */
export function contractExemplarToJsonSchema(example) {
    if (example === null) {
        return {
            anyOf: [
                { type: 'null' },
                nonemptyStringSchema(),
            ],
        };
    }
    if (typeof example === 'string') {
        if (example === '')
            return nonemptyStringSchema();
        const alternatives = exemplarAlternatives(example);
        if (alternatives.length === 1) {
            return {
                type: 'string',
                pattern: literalPattern(alternatives[0]).source,
            };
        }
        return {
            anyOf: alternatives.map((alternative) => ({
                type: 'string',
                pattern: literalPattern(alternative).source,
            })),
        };
    }
    if (typeof example === 'number') {
        return example >= 0
            ? { type: 'integer', minimum: 0 }
            : { type: 'integer' };
    }
    if (typeof example === 'boolean')
        return { type: 'boolean' };
    if (Array.isArray(example)) {
        return {
            type: 'array',
            items: example.length > 0
                ? contractExemplarToJsonSchema(example[0])
                : nonemptyStringSchema(),
        };
    }
    if (isRecord(example)) {
        const properties = Object.fromEntries(Object.entries(example).map(([key, value]) => [key, contractExemplarToJsonSchema(value)]));
        return {
            type: 'object',
            additionalProperties: false,
            properties,
            required: Object.keys(example),
        };
    }
    throw new Error(`Core contract exemplar contains unsupported ${typeof example}`);
}
function validateContractString(value, example, path, errors) {
    if (!validateRequiredString(value, path, errors))
        return;
    if (example === '')
        return;
    const alternatives = exemplarAlternatives(example);
    if (alternatives.some((alternative) => literalPattern(alternative).test(value)))
        return;
    errors.push(alternatives.length > 1
        ? `${path} must match one of the Core literals ${alternatives.join(', ')}`
        : `${path} must match the Core literal ${example}`);
}
function rationaleSentenceCount(value) {
    const text = value.trim();
    let count = 0;
    for (let index = 0; index < text.length; index += 1) {
        if (!'.!?'.includes(text[index]))
            continue;
        while (index + 1 < text.length && '.!?'.includes(text[index + 1]))
            index += 1;
        let next = index + 1;
        while (next < text.length && `\"'”’)]}`.includes(text[next]))
            next += 1;
        if (next === text.length || /\s/u.test(text[next]))
            count += 1;
    }
    return count;
}
function validateJudgmentRationale(value, path, errors) {
    if (typeof value !== 'string' || !hasText(value))
        return;
    const trimmed = value.trim();
    const sentenceCount = rationaleSentenceCount(trimmed);
    if (!/[.!?]+["'”’)\]}]*$/u.test(trimmed) || sentenceCount < 1 || sentenceCount > 3) {
        errors.push(`${path} must contain 1-3 complete sentences`);
    }
}
function validateStringArray(value, path, errors) {
    if (!Array.isArray(value)) {
        errors.push(`${path} must be an array`);
        return;
    }
    value.forEach((entry, index) => {
        validateRequiredString(entry, `${path}[${String(index)}]`, errors);
    });
}
function validateAgainstContractExemplar(value, example, path, errors) {
    if (example === null) {
        if (value !== null && !validateRequiredString(value, path, errors)) {
            return;
        }
        return;
    }
    if (typeof example === 'string') {
        validateContractString(value, example, path, errors);
        return;
    }
    if (typeof example === 'number') {
        if (typeof value !== 'number'
            || !Number.isSafeInteger(value)
            || Object.is(value, -0)
            || (example >= 0 && value < 0)) {
            errors.push(`${path} must be a non-negative safe integer`);
        }
        return;
    }
    if (typeof example === 'boolean') {
        if (typeof value !== 'boolean')
            errors.push(`${path} must be a boolean`);
        return;
    }
    if (Array.isArray(example)) {
        if (!Array.isArray(value)) {
            errors.push(`${path} must be an array`);
            return;
        }
        if (example.length > 0) {
            value.forEach((entry, index) => (validateAgainstContractExemplar(entry, example[0], `${path}[${String(index)}]`, errors)));
        }
        else {
            // Every empty array placeholder in the current canonical Core contracts
            // is a string-valued collection. Treating it as arbitrary JSON would
            // silently widen the exact contract.
            validateStringArray(value, path, errors);
        }
        return;
    }
    if (isRecord(example)) {
        if (!isRecord(value)) {
            errors.push(`${path} must be an object`);
            return;
        }
        const expectedKeys = Object.keys(example).sort();
        const actualKeys = Object.keys(value).sort();
        for (const key of expectedKeys.filter((key) => !actualKeys.includes(key))) {
            errors.push(`${path}.${key} is missing`);
        }
        for (const key of actualKeys.filter((key) => !expectedKeys.includes(key))) {
            errors.push(`${path}.${key} is not allowed`);
        }
        for (const key of expectedKeys.filter((key) => actualKeys.includes(key))) {
            validateAgainstContractExemplar(value[key], example[key], `${path}.${key}`, errors);
        }
        if (expectedKeys.includes('flags') && actualKeys.includes('flags')) {
            validateStringArray(value.flags, `${path}.flags`, errors);
        }
        if (expectedKeys.includes('rationale') && actualKeys.includes('rationale')) {
            validateJudgmentRationale(value.rationale, `${path}.rationale`, errors);
        }
        return;
    }
    errors.push(`${path} has an unsupported Core contract exemplar`);
}
function parseRaw(raw) {
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
        const bytes = stableJsonBytes(raw);
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
        && request.isolation.producer_context_id
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
    const parsed = parseRaw(options.raw);
    const rawDigest = sha256Digest(parsed.bytes);
    writeFileAtomic(join(returnRoot, 'raw.json'), parsed.bytes);
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
    const errors = [];
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
        validateAgainstContractExemplar(parsed.value, example, '$', errors);
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
    const validated = new ValidatedWorkerReturn(VALIDATED_TOKEN, request.call_id, parsed.value, rawDigest, contractDigest, validationDigest, options.dispatchReceipt.simulation);
    writeFileAtomic(join(returnRoot, 'validated.json'), validated.canonicalBytes());
    return {
        report,
        validated,
    };
}
