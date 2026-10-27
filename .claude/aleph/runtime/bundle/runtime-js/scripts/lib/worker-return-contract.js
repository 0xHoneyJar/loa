import { TextDecoder } from 'node:util';
import { isSemanticOutputContract, semanticReturnJsonSchema, validateSemanticOutputContract, validateSemanticReturn } from './semantic-review.js';
function isRecord(value) {
    return typeof value === 'object' && value !== null && !Array.isArray(value);
}
function hasText(value) {
    return value.trim().length > 0;
}
function hasUnpairedSurrogate(value) {
    for (let index = 0; index < value.length; index += 1) {
        const code = value.charCodeAt(index);
        if (code >= 0xd800 && code <= 0xdbff) {
            const next = value.charCodeAt(index + 1);
            if (!(next >= 0xdc00 && next <= 0xdfff))
                return true;
            index += 1;
        }
        else if (code >= 0xdc00 && code <= 0xdfff) {
            return true;
        }
    }
    return false;
}
function validateUnicode(value, path, errors) {
    if (typeof value === 'string') {
        if (hasUnpairedSurrogate(value)) {
            errors.push(`${path} contains an unpaired UTF-16 surrogate`);
        }
        return;
    }
    if (Array.isArray(value)) {
        value.forEach((entry, index) => (validateUnicode(entry, `${path}[${String(index)}]`, errors)));
        return;
    }
    if (!isRecord(value))
        return;
    for (const [key, entry] of Object.entries(value)) {
        if (hasUnpairedSurrogate(key)) {
            errors.push(`${path} has a key with an unpaired UTF-16 surrogate`);
        }
        validateUnicode(entry, `${path}[${JSON.stringify(key)}]`, errors);
    }
}
class JsonMemberScanner {
    index = 0;
    text;
    integerNumbers;
    duplicates = [];
    constructor(text, integerNumbers = false) {
        this.text = text;
        this.integerNumbers = integerNumbers;
    }
    scan() {
        this.scanValue('$');
        return this.duplicates;
    }
    skipWhitespace() {
        while (/\s/u.test(this.text[this.index] || ''))
            this.index += 1;
    }
    scanString() {
        const start = this.index;
        this.index += 1;
        while (this.index < this.text.length) {
            const character = this.text[this.index];
            this.index += 1;
            if (character === '\\') {
                this.index += 1;
            }
            else if (character === '"') {
                break;
            }
        }
        return JSON.parse(this.text.slice(start, this.index));
    }
    scanValue(path) {
        this.skipWhitespace();
        const character = this.text[this.index];
        if (character === '{') {
            this.scanObject(path);
        }
        else if (character === '[') {
            this.scanArray(path);
        }
        else if (character === '"') {
            this.scanString();
        }
        else {
            const start = this.index;
            while (this.index < this.text.length
                && !/[\s,\]}]/u.test(this.text[this.index])) {
                this.index += 1;
            }
            const token = this.text.slice(start, this.index);
            if (this.integerNumbers && /^[-0-9]/u.test(token)
                && (!/^(?:0|[1-9]\d*)$/u.test(token) || !Number.isSafeInteger(Number(token)))) {
                throw new Error(`noncanonical integer at ${path}`);
            }
        }
    }
    scanObject(path) {
        this.index += 1;
        this.skipWhitespace();
        if (this.text[this.index] === '}') {
            this.index += 1;
            return;
        }
        const seen = new Set();
        while (this.index < this.text.length) {
            const key = this.scanString();
            const memberPath = `${path}[${JSON.stringify(key)}]`;
            if (seen.has(key))
                this.duplicates.push(memberPath);
            seen.add(key);
            this.skipWhitespace();
            this.index += 1;
            this.scanValue(memberPath);
            this.skipWhitespace();
            const delimiter = this.text[this.index];
            this.index += 1;
            if (delimiter === '}')
                return;
            this.skipWhitespace();
        }
    }
    scanArray(path) {
        this.index += 1;
        this.skipWhitespace();
        if (this.text[this.index] === ']') {
            this.index += 1;
            return;
        }
        let item = 0;
        while (this.index < this.text.length) {
            this.scanValue(`${path}[${String(item)}]`);
            item += 1;
            this.skipWhitespace();
            const delimiter = this.text[this.index];
            this.index += 1;
            if (delimiter === ']')
                return;
            this.skipWhitespace();
        }
    }
}
export function parseStrictJson(raw, integerNumbers = false) {
    const text = typeof raw === 'string' ? raw
        : new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(raw);
    const value = JSON.parse(text);
    const errors = new JsonMemberScanner(text, integerNumbers).scan().map((path) => `duplicate key ${path}`);
    validateUnicode(value, '$', errors);
    if (errors.length)
        throw new Error(errors.join('; '));
    return value;
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
 * Convert a pinned Core output-contract exemplar into the closed JSON Schema
 * shape that a host-native constrained-output mechanism may enforce.
 */
export function contractExemplarToJsonSchema(example) {
    if (isSemanticOutputContract(example))
        return semanticReturnJsonSchema(validateSemanticOutputContract(example), '1.7.0-provisional');
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
export function validateJudgmentRationale(value, path, errors) {
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
        if (value !== null)
            validateRequiredString(value, path, errors);
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
            errors.push(example >= 0
                ? `${path} must be a non-negative safe integer`
                : `${path} must be a safe integer`);
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
            // Empty arrays in the current Core contracts are string collections.
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
/**
 * Validate raw JSON text against one pinned Core output-contract exemplar.
 * This function is import-safe and performs no writes, process execution, or
 * network access.
 */
export function validateWorkerReturnContract(raw, contractExemplar) {
    if (isSemanticOutputContract(contractExemplar)) {
        try {
            const role = validateSemanticOutputContract(contractExemplar);
            return validateSemanticReturn(role, '1.7.0-provisional', parseStrictJson(raw, true));
        }
        catch (error) {
            return { result: 'FAIL', errors: [error instanceof Error ? error.message : String(error)], canonicalValue: null, binding: 'not-checked' };
        }
    }
    const errors = [];
    if (!isRecord(contractExemplar)) {
        errors.push('Core output contract root must be an object');
    }
    else {
        try {
            contractExemplarToJsonSchema(contractExemplar);
        }
        catch (error) {
            errors.push(`Core output contract is malformed: ${error instanceof Error ? error.message : String(error)}`);
        }
    }
    let text = null;
    if (Buffer.isBuffer(raw)) {
        try {
            text = new TextDecoder('utf-8', {
                fatal: true,
                ignoreBOM: true,
            }).decode(raw);
        }
        catch {
            errors.push('worker return is not valid UTF-8');
        }
    }
    else {
        text = raw;
    }
    let value = null;
    try {
        if (text !== null)
            value = JSON.parse(text);
    }
    catch (error) {
        errors.push(`worker return is invalid JSON: ${error instanceof Error ? error.message : String(error)}`);
    }
    if (text !== null && value !== null && !errors.some((error) => /invalid JSON/u.test(error))) {
        try {
            for (const path of new JsonMemberScanner(text).scan()) {
                errors.push(`worker return contains duplicate object key at ${path}`);
            }
        }
        catch (error) {
            errors.push(`worker return member scan failed: ${error instanceof Error ? error.message : String(error)}`);
        }
        validateUnicode(value, '$', errors);
    }
    if (errors.length === 0) {
        validateAgainstContractExemplar(value, contractExemplar, '$', errors);
    }
    return {
        result: errors.length === 0 ? 'PASS' : 'FAIL',
        errors,
        canonicalValue: errors.length === 0 ? value : null,
    };
}
