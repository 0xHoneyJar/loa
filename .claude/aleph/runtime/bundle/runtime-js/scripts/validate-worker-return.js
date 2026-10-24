#!/usr/bin/env node
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { validateWorkerReturnContract, parseStrictJson, } from './lib/worker-return-contract.js';
import { isSemanticOutputContract } from './lib/semantic-review.js';
const SCRIPT_PATH = fileURLToPath(import.meta.url);
const FORMAT = 'aleph-worker-return-validation/v1';
function digest(bytes) {
    return `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
}
export function validateWorkerReturnFiles(contractPath, returnPath) {
    const errors = [];
    let contractBytes = null;
    let returnBytes = null;
    try {
        contractBytes = readFileSync(resolve(contractPath));
    }
    catch (error) {
        errors.push(`could not read Core output contract: ${error instanceof Error ? error.message : String(error)}`);
    }
    try {
        returnBytes = readFileSync(resolve(returnPath));
    }
    catch (error) {
        errors.push(`could not read worker return: ${error instanceof Error ? error.message : String(error)}`);
    }
    let contract = null;
    if (contractBytes) {
        try {
            contract = JSON.parse(contractBytes.toString('utf8'));
            if (isSemanticOutputContract(contract))
                contract = parseStrictJson(contractBytes, true);
        }
        catch (error) {
            errors.push(`Core output contract is invalid JSON: ${error instanceof Error ? error.message : String(error)}`);
        }
    }
    let canonicalValue = null;
    let binding;
    if (errors.length === 0 && returnBytes) {
        const validation = validateWorkerReturnContract(returnBytes, contract);
        errors.push(...validation.errors);
        canonicalValue = validation.canonicalValue;
        binding = validation.binding;
    }
    return {
        format: FORMAT,
        result: errors.length === 0 ? 'PASS' : 'FAIL',
        contract_digest: contractBytes ? digest(contractBytes) : null,
        return_digest: returnBytes ? digest(returnBytes) : null,
        canonical_value: errors.length === 0 ? canonicalValue : null,
        errors,
        ...(binding ? { binding } : {}),
    };
}
function parseArgs(argv) {
    const options = {
        contract: '',
        workerReturn: '',
        json: false,
        help: false,
    };
    for (let index = 0; index < argv.length; index += 1) {
        const argument = argv[index];
        if (argument === '--help' || argument === '-h') {
            options.help = true;
        }
        else if (argument === '--json') {
            options.json = true;
        }
        else if (argument === '--contract') {
            options.contract = argv[++index] || '';
        }
        else if (argument.startsWith('--contract=')) {
            options.contract = argument.slice('--contract='.length);
        }
        else if (argument === '--return') {
            options.workerReturn = argv[++index] || '';
        }
        else if (argument.startsWith('--return=')) {
            options.workerReturn = argument.slice('--return='.length);
        }
        else {
            options.error = `unknown argument "${argument}"`;
            break;
        }
    }
    if (!options.help && !options.error && (!options.contract || !options.workerReturn)) {
        options.error = '--contract and --return are required';
    }
    return options;
}
function printHuman(report) {
    console.log('Aleph Worker Return Contract');
    for (const error of report.errors)
        console.error(`FAIL ${error}`);
    console.log(`RESULT: ${report.result}`);
    if (report.contract_digest)
        console.log(`CONTRACT: ${report.contract_digest}`);
    if (report.return_digest)
        console.log(`RETURN: ${report.return_digest}`);
}
function main() {
    const options = parseArgs(process.argv.slice(2));
    if (options.help) {
        console.log('Usage: node scripts/validate-worker-return.ts '
            + '--contract PATH --return PATH [--json]');
        return 0;
    }
    if (options.error) {
        console.error(options.error);
        return 2;
    }
    const report = validateWorkerReturnFiles(options.contract, options.workerReturn);
    if (options.json)
        console.log(JSON.stringify(report));
    else
        printHuman(report);
    return report.result === 'PASS' ? 0 : 1;
}
if (resolve(process.argv[1] || '') === SCRIPT_PATH)
    process.exitCode = main();
