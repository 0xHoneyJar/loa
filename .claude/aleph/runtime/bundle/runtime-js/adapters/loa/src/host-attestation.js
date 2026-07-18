#!/usr/bin/env node
import { existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { attestClaudeCodeHost, resolveBubblewrapExecutable, resolveClaudeCodeExecutable, } from './claude-code-host.js';
import { sha256Digest, stableJsonBytes, writeJsonAtomic } from './fs.js';
import { loadLoaProfile } from './runtime-snapshot.js';
const SCRIPT_PATH = fileURLToPath(import.meta.url);
function parseCli(argv) {
    const action = argv.shift();
    if (action !== 'attest') {
        throw new Error('host action must be attest');
    }
    let profilePath = '';
    let outputPath = '';
    let modelId = '';
    let provider = '';
    let claudePath = process.env.CLAUDE_CODE_BIN || 'claude';
    let sandboxPath = process.env.BWRAP_BIN || 'bwrap';
    let timeoutMs = '1800000';
    let maxOutputBytes = '16777216';
    let maxBudgetUsd = '25.00';
    let json = false;
    while (argv.length > 0) {
        const option = argv.shift();
        if (option === '--profile')
            profilePath = argv.shift() || '';
        else if (option === '--output')
            outputPath = argv.shift() || '';
        else if (option === '--model')
            modelId = argv.shift() || '';
        else if (option === '--provider')
            provider = argv.shift() || '';
        else if (option === '--claude')
            claudePath = argv.shift() || '';
        else if (option === '--bwrap')
            sandboxPath = argv.shift() || '';
        else if (option === '--timeout-ms')
            timeoutMs = argv.shift() || '';
        else if (option === '--max-output-bytes')
            maxOutputBytes = argv.shift() || '';
        else if (option === '--max-budget-usd')
            maxBudgetUsd = argv.shift() || '';
        else if (option === '--json')
            json = true;
        else
            throw new Error(`unknown host attestation option: ${option || '<empty>'}`);
    }
    if (!profilePath || !outputPath || !modelId || !provider) {
        throw new Error('--profile, --output, --model, and --provider are required');
    }
    if (provider !== 'amazon-bedrock') {
        throw new Error('--provider must be amazon-bedrock');
    }
    return {
        profilePath: resolve(profilePath),
        outputPath: resolve(outputPath),
        modelId,
        provider,
        claudePath,
        sandboxPath,
        timeoutMs,
        maxOutputBytes,
        maxBudgetUsd,
        json,
    };
}
export function runHostAttestationCli(argv = process.argv.slice(2)) {
    try {
        const parsed = parseCli([...argv]);
        if (existsSync(parsed.outputPath)) {
            throw new Error(`host capability receipt already exists: ${parsed.outputPath}`);
        }
        const profile = loadLoaProfile(parsed.profilePath);
        const host = attestClaudeCodeHost({
            profile: profile.value,
            modelId: parsed.modelId,
            provider: parsed.provider,
            claudePath: resolveClaudeCodeExecutable(parsed.claudePath),
            sandboxPath: resolveBubblewrapExecutable(parsed.sandboxPath),
            attestedAt: new Date().toISOString(),
            timeoutMs: parsed.timeoutMs,
            maxOutputBytes: parsed.maxOutputBytes,
            maxBudgetUsd: parsed.maxBudgetUsd,
        });
        writeJsonAtomic(parsed.outputPath, host, 0o600);
        const outputBytes = stableJsonBytes(host);
        const summary = {
            format: host.host_format,
            result: 'PASS',
            output_path: parsed.outputPath,
            receipt_digest: sha256Digest(outputBytes),
            host: host.host,
            provider: host.runtime?.provider,
            model_ids: [...new Set(Object.values(host.models).map((model) => model.model_id))],
            probes: host.runtime?.probes.map((probe) => ({
                slots: probe.slots,
                model: probe.observed_model,
                effort: probe.effort,
                session_id: probe.session_id,
                total_cost_usd: probe.total_cost_usd,
                event_stream_digest: probe.event_stream_digest,
            })),
            fallback: false,
        };
        process.stdout.write(parsed.json
            ? stableJsonBytes(summary)
            : `HOST ATTESTATION PASS ${parsed.outputPath} ${summary.receipt_digest}\n`);
        return 0;
    }
    catch (error) {
        process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
        return 1;
    }
}
if (process.argv[1] && resolve(process.argv[1]) === SCRIPT_PATH) {
    process.exitCode = runHostAttestationCli();
}
