#!/usr/bin/env node
import { existsSync, readFileSync, rmSync, } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { LOA_COMMAND_RESULT_FORMAT, LOA_INSTALL_LOCK_PATH, LOA_INSTALLED_BUNDLE_ROOT, LOA_RUN_ROOT, } from './types.js';
import { extractFirstFence, extractMarkdownHeading, readLockedFile, readVerifiedBundleLock, verifyAndLoadLoaBundle, } from './core-loader.js';
import { readJsonFile, makeTreeOwnerWritable, nextDecimal, sha256Digest, stableJson, stableJsonBytes, writeFileAtomic, writeJsonAtomic, } from './fs.js';
import { applyCorpusFreeze, planCorpusFreeze, snapshotCorpus, verifyCorpusSnapshot, } from './intake.js';
import { acquireDurableProcessLock, createRunDirectory, initializeRunControl, listRunIds, openHumanAuthorityGate, readRunState, recordHumanAuthorityDecision, recoverPendingAuthorityTransactions, runDirectory, runtimeSnapshotPath, stateCheckpointDigest, verifyRunControl, writeRunState, } from './run-control.js';
import { captureRuntimeSnapshot, defaultProfilePath, loadLoaProfile, validateResolvedHost, verifyRuntimeSnapshot, } from './runtime-snapshot.js';
import { invokePinnedChecker, } from './checker.js';
import { verifyLoaInstallation } from './installer.js';
import { runLoaPreflight } from './preflight.js';
import { recoverPendingLedgerTransactions } from './ledger-writer.js';
const SCRIPT_PATH = fileURLToPath(import.meta.url);
const DEFAULT_CAPABILITIES_PATH = 'grimoires/loa/aleph/host-capabilities.json';
function isRecord(value) {
    return typeof value === 'object' && value !== null && !Array.isArray(value);
}
function exactKeys(value, required, optional = []) {
    if (!isRecord(value))
        return false;
    const keys = Object.keys(value).sort();
    if (required.some((key) => !keys.includes(key)))
        return false;
    return keys.every((key) => required.includes(key) || optional.includes(key));
}
function parseFileOpenGate(value) {
    if (!exactKeys(value, ['gateId', 'gateType', 'stage', 'now', 'request'])
        || typeof value.gateId !== 'string'
        || typeof value.gateType !== 'string'
        || typeof value.stage !== 'string'
        || typeof value.now !== 'string') {
        throw new Error('--open-gate JSON has missing, extra, or malformed fields');
    }
    stableJsonBytes(value.request);
    return value;
}
function parseFileHumanAuthorityDecision(value) {
    if (!exactKeys(value, [
        'gateId',
        'authorityIdentity',
        'decision',
        'recordedAt',
        'simulation',
        'response',
    ], ['approvedState'])
        || typeof value.gateId !== 'string'
        || typeof value.authorityIdentity !== 'string'
        || typeof value.decision !== 'string'
        || typeof value.recordedAt !== 'string'
        || (value.approvedState !== undefined && typeof value.approvedState !== 'string')
        || (value.simulation !== null
            && (!exactKeys(value.simulation, ['kind'])
                || value.simulation.kind !== 'fixture-simulated'))) {
        throw new Error('--authority-response generic JSON has missing, extra, or malformed fields');
    }
    stableJsonBytes(value.response);
    return value;
}
function defaultClock() {
    return { now: () => new Date().toISOString() };
}
function defaultIdSource(clock) {
    let call = 0;
    return {
        nextRunId(corpusHint) {
            const time = clock.now().replace(/[-:.]/gu, '').replace(/Z$/u, 'Z');
            return `RUN-${time}-${corpusHint.replace(/^sha256:/u, '').slice(0, 12)}`;
        },
        nextCallId(runId) {
            call += 1;
            return `CALL-${runId.slice('RUN-'.length)}-${String(call).padStart(4, '0')}`;
        },
    };
}
function result(command, status, fields = {}) {
    return {
        format: LOA_COMMAND_RESULT_FORMAT,
        command,
        result: status,
        run_id: fields.run_id ?? null,
        full_mode: fields.full_mode ?? 'not-started',
        state: fields.state ?? null,
        stage: fields.stage ?? null,
        gate: fields.gate ?? null,
        errors: fields.errors ?? [],
        details: fields.details ?? null,
    };
}
function safeTable(value) {
    return value.replaceAll('|', '\\|').replace(/[\r\n]+/gu, ' ').trim();
}
function stripTemplateComments(value) {
    return value.replace(/<!--[\s\S]*?-->/gu, '').replace(/\n{3,}/gu, '\n\n');
}
function templateBlock(bundle, path, heading) {
    const file = readLockedFile(bundle, path, 'core');
    const section = extractMarkdownHeading(file, heading, path);
    return extractFirstFence(section, 'markdown', `${path} ${heading}`).toString('utf8');
}
function insertTableRow(document, heading, row) {
    const rendered = document.endsWith('\n') ? document : `${document}\n`;
    const headingAt = rendered.indexOf(heading);
    if (headingAt < 0)
        throw new Error(`rendered Core template omits ${heading}`);
    const firstPipe = rendered.indexOf('|', headingAt);
    const firstEnd = rendered.indexOf('\n', firstPipe);
    const delimiterEnd = rendered.indexOf('\n', firstEnd + 1);
    if (firstPipe < 0 || firstEnd < 0 || delimiterEnd < 0) {
        throw new Error(`rendered Core template has malformed table under ${heading}`);
    }
    let insertion = delimiterEnd + 1;
    while (rendered[insertion] === '|') {
        const next = rendered.indexOf('\n', insertion);
        if (next < 0)
            break;
        insertion = next + 1;
    }
    return `${rendered.slice(0, insertion)}${row}\n${rendered.slice(insertion)}`;
}
function renderRunManifest(bundle, state, now) {
    let manifest = stripTemplateComments(templateBlock(bundle, 'docs/architecture/templates/01-run-control.md', 'T1.1 Run manifest → `runs/<run-id>/run-manifest.md`')).replaceAll('⟨RUN-slug⟩', state.run_id);
    const identity = state.identity;
    const fields = {
        run_id: state.run_id,
        predecessor_run: 'none',
        mode: 'agent',
        created: now.slice(0, 10),
        core_id: identity.core.id,
        core_version: identity.core.version,
        core_digest: identity.core.tree_digest,
        adapter_id: identity.adapter.id,
        adapter_version: identity.adapter.version,
        adapter_digest: identity.adapter.tree_digest,
        bundle_id: identity.bundle.id,
        bundle_digest: identity.bundle.digest,
        bundle_lock_ref: identity.bundle.lock_ref,
        checker_digest: identity.checker_digest,
        adapter_protocol_version: identity.adapter_protocol_version,
        run_format_version: identity.run_format_version,
        host_identity: `${identity.host.id}@${identity.host.version}+${identity.host.build_id}`,
        runtime_snapshot_ref: identity.runtime.snapshot_ref,
        runtime_snapshot_digest: identity.runtime.digest,
        doctrine_sha: bundle.lock.provenance.vcs.commit,
        runbook: `docs/architecture/08-runbook-agent-mode.md @ ${identity.core.tree_digest}`,
        corpus_ref: 'corpus/manifest.md',
        corpus_hash: state.corpus.tree_digest,
    };
    manifest = manifest.split('\n').map((line) => {
        const match = line.match(/^- ([a-z_]+):/u);
        if (!match || fields[match[1]] === undefined)
            return line;
        return `- ${match[1]}: ${fields[match[1]]}`;
    }).join('\n');
    manifest = manifest.replace(/- declared_scope: >\s*\n\s*⟨[^⟩]+⟩/u, '- declared_scope: >\n    PENDING S0 HUMAN AUTHORITY');
    const profileValue = `${identity.profile.id} @ ${identity.profile.digest}`;
    const mappings = stableJson(identity.models);
    const budgetMap = stableJson(Object.fromEntries(Object.entries(identity.models).map(([role, model]) => [role, model.budget])));
    manifest = manifest.split('\n').map((line) => {
        if (/^\| model_ids \(per role/u.test(line))
            return `| model_ids (per role, exact strings; or "human") | ${safeTable(mappings)} |`;
        if (/^\| adapter profile ID/u.test(line))
            return `| adapter profile ID + digest | ${safeTable(profileValue)} |`;
        if (/^\| model\/context\/effort mapping/u.test(line))
            return `| model/context/effort mapping actually used | ${safeTable(mappings)} |`;
        if (/^\| profile deviations/u.test(line))
            return `| profile deviations | ${state.full_mode === 'fixture-simulated' ? 'fixture-simulated; not validation or acceptance evidence' : 'none'} |`;
        if (/^\| fan-out limits/u.test(line))
            return '| fan-out limits | pinned by host profile and per-stage dispatch |';
        if (/^\| budgets granted/u.test(line))
            return `| budgets granted (per stage, tokens) | ${safeTable(budgetMap)} |`;
        if (/^\| 1 \| DRAFT/u.test(line))
            return `| 1 | DRAFT | ${now} | loa-orchestrator | run created; S0 authority gate pending |`;
        if (line.includes('⟨approved/…⟩') || line.includes('| ⟨none | list⟩ |'))
            return '';
        return line;
    }).join('\n');
    if (state.full_mode === 'fixture-simulated') {
        manifest = insertTableRow(manifest, '## Unvalidated-machinery notices', `| fixture-simulated host | structural implementation fixture only; not replay, validation, acceptance, or sanction evidence | ${now.slice(0, 10)} |`);
    }
    return manifest.endsWith('\n') ? manifest : `${manifest}\n`;
}
function renderRunLog(bundle, state, now) {
    const template = stripTemplateComments(templateBlock(bundle, 'docs/architecture/templates/01-run-control.md', 'T1.2 Run log → `runs/<run-id>/run-log.md`'));
    const heading = template.split('\n')[0].replaceAll('⟨RUN-slug⟩', state.run_id);
    const simulation = state.full_mode === 'fixture-simulated'
        ? ' The host and all responses in this fixture are explicitly simulated; they are not replay, validation, acceptance, or sanction evidence.'
        : '';
    return `${heading}\n\n## ${now} — S0 — entry\n`
        + `The Loa adapter created the durable run directory from the verified immutable bundle and staged the exact source bytes.${simulation}\n\n`
        + `## ${now} — S0 — gate\n`
        + 'The run is BLOCKED for human decisions on corpus scope, exclusions, sensitivity, authority identity, and freeze. No downstream worker has been dispatched.\n';
}
function renderCorpusManifest(bundle, state, files) {
    let manifest = stripTemplateComments(templateBlock(bundle, 'docs/architecture/templates/02-corpus-intake.md', 'T2.1 Corpus manifest → `runs/<run-id>/corpus/manifest.md`')).replaceAll('⟨RUN-slug⟩', state.run_id);
    manifest = manifest.replace('⟨The approved scope statement, verbatim from the manifest sign-off.⟩', 'PENDING S0 HUMAN AUTHORITY');
    for (const file of files) {
        manifest = insertTableRow(manifest, '## Source inventory', `| ${file.source_id} | design-note | ${safeTable(file.frozen_path.replace(/^corpus\//u, ''))} | ${file.scheme} | ${file.digest} | not-recorded | unverifiable | pending-authority | staged exact bytes; admission pending S0 authority |`);
    }
    return manifest.endsWith('\n') ? manifest : `${manifest}\n`;
}
function renderFrozenCorpusManifest(bundle, state, staged, frozen, response) {
    let manifest = stripTemplateComments(templateBlock(bundle, 'docs/architecture/templates/02-corpus-intake.md', 'T2.1 Corpus manifest → `runs/<run-id>/corpus/manifest.md`')).replaceAll('⟨RUN-slug⟩', state.run_id);
    manifest = manifest.replace('⟨The approved scope statement, verbatim from the manifest sign-off.⟩', response.declared_scope);
    const schemes = new Set(frozen.files.map((file) => file.scheme));
    manifest = manifest.split('\n').filter((line) => {
        if (line.startsWith('| chat-msg |'))
            return false;
        if (line.startsWith('| ⟨add per format;'))
            return false;
        return line !== '| md-lines | markdown/plain files | `L⟨start⟩-L⟨end⟩` of the frozen file |'
            || schemes.has('md-lines');
    }).join('\n');
    if (schemes.has('text-lines')) {
        manifest = insertTableRow(manifest, '## Span-addressing schemes in use', '| text-lines | UTF-8 text files | `L⟨start⟩-L⟨end⟩` of the frozen file |');
    }
    const rulings = new Map(response.sensitivity_rulings.map((ruling) => [ruling.source_id, ruling]));
    for (const file of frozen.files) {
        const ruling = rulings.get(file.source_id);
        if (!ruling || ruling.decision !== 'admit-exact-bytes') {
            throw new Error(`frozen source ${file.source_id} has no admission ruling`);
        }
        manifest = insertTableRow(manifest, '## Source inventory', `| ${file.source_id} | design-note | ${safeTable(file.frozen_path.replace(/^corpus\//u, ''))} | ${file.scheme} | ${file.digest} | not-recorded | unverifiable | ${ruling.labels.join(',')} | admitted as exact bytes by S0 human authority; see control/gates/GATE-S0-response.json |`);
    }
    const stagedById = new Map(staged.files.map((file) => [file.source_id, file]));
    manifest += '\n## S0 exclusion rulings\n\n';
    manifest += '| source_id | staged locus | ruling | authority record |\n';
    manifest += '|-----------|--------------|--------|------------------|\n';
    for (const sourceId of response.exclusions) {
        const file = stagedById.get(sourceId);
        if (!file)
            throw new Error(`excluded source disappeared from staged inventory: ${sourceId}`);
        manifest += `| ${sourceId} | ${safeTable(file.frozen_path.replace(/^corpus\//u, ''))} | excluded before freeze | control/gates/GATE-S0-response.json |\n`;
    }
    if (response.exclusions.length === 0) {
        manifest += '| none | n/a | no staged source excluded | control/gates/GATE-S0-response.json |\n';
    }
    return manifest.endsWith('\n') ? manifest : `${manifest}\n`;
}
function writeCanonicalDraft(bundle, runDir, state, corpus, now) {
    writeFileAtomic(join(runDir, 'run-manifest.md'), renderRunManifest(bundle, state, now));
    writeFileAtomic(join(runDir, 'run-log.md'), renderRunLog(bundle, state, now));
    writeFileAtomic(join(runDir, 'corpus', 'manifest.md'), renderCorpusManifest(bundle, state, corpus.files));
}
function runtimeDetails(state) {
    return {
        bundle_digest: state.identity.bundle.digest,
        core_digest: state.identity.core.tree_digest,
        adapter_digest: state.identity.adapter.tree_digest,
        checker_digest: state.identity.checker_digest,
        runtime_digest: state.identity.runtime.digest,
        corpus_digest: state.corpus.tree_digest,
        resume_sequence: state.execution.resume.sequence,
    };
}
export function startLoaRun(inputs, options = {}) {
    const clock = options.clock || defaultClock();
    const loaRoot = resolve(options.loaRoot || process.cwd());
    const bundleRoot = resolve(options.bundleRoot || join(loaRoot, LOA_INSTALLED_BUNDLE_ROOT));
    const capabilitiesPath = resolve(loaRoot, options.capabilitiesPath || DEFAULT_CAPABILITIES_PATH);
    let runDir = '';
    try {
        if (!options.bundleRoot) {
            const install = verifyLoaInstallation(loaRoot);
            if (install.result !== 'PASS') {
                throw new Error(`installed Aleph runtime failed verification: ${install.errors.join('; ')}`);
            }
        }
        const bundle = verifyAndLoadLoaBundle(bundleRoot);
        const profile = loadLoaProfile(defaultProfilePath(bundle.root));
        const host = validateResolvedHost(readJsonFile(capabilitiesPath), profile.value, { allowSimulation: options.allowSimulation });
        const preflight = runLoaPreflight({ root: bundle.root, capabilities: capabilitiesPath });
        if (preflight.result !== 'PASS') {
            throw new Error(`Loa full-mode preflight failed: ${preflight.checks
                .filter((check) => check.status === 'FAIL')
                .flatMap((check) => check.problems)
                .join('; ')}`);
        }
        if (!host.simulation && !preflight.runtimeReady) {
            throw new Error('Loa full-mode runtime preflight did not establish every live capability');
        }
        const now = clock.now();
        const hint = sha256Digest(stableJsonBytes(inputs));
        const idSource = options.idSource || defaultIdSource(clock);
        const runId = idSource.nextRunId(hint);
        runDir = createRunDirectory(loaRoot, runId);
        const corpus = snapshotCorpus({
            loaRoot,
            runDir,
            runId,
            inputs,
            capturedAt: now,
        });
        const runtime = captureRuntimeSnapshot({
            runId,
            bundle,
            profile,
            host,
            capturedAt: now,
            outputPath: runtimeSnapshotPath(runDir),
        });
        const originalLockBytes = readVerifiedBundleLock(bundle);
        const state = initializeRunControl({
            loaRoot,
            runDir,
            runId,
            lock: bundle.lock,
            originalLockBytes,
            installationRef: options.bundleRoot
                ? bundle.root
                : LOA_INSTALL_LOCK_PATH,
            profile: profile.value,
            profileDigest: profile.digest,
            host,
            runtimeSnapshot: runtime,
            corpus,
            now,
        });
        const pinnedBundle = verifyAndLoadLoaBundle(runtime.bundle.root);
        writeCanonicalDraft(pinnedBundle, runDir, state, corpus, now);
        return result('start', 'BLOCKED', {
            run_id: runId,
            full_mode: state.full_mode,
            state: state.execution.core_state,
            stage: state.execution.stage,
            gate: state.execution.gate,
            details: runtimeDetails(state),
        });
    }
    catch (error) {
        if (runDir && existsSync(runDir)) {
            makeTreeOwnerWritable(runDir);
            rmSync(runDir, { recursive: true, force: true });
        }
        return result('start', 'FAIL', {
            errors: [error instanceof Error ? error.message : String(error)],
        });
    }
}
function stateSummary(state) {
    return JSON.parse(stableJson({
        run_id: state.run_id,
        full_mode: state.full_mode,
        state: state.execution.core_state,
        stage: state.execution.stage,
        stage_status: state.execution.stage_status,
        gate: state.execution.gate,
        halt: state.execution.halt,
        pins: runtimeDetails(state),
    }));
}
export function statusLoaRun(runId, options = {}) {
    const loaRoot = resolve(options.loaRoot || process.cwd());
    try {
        if (!runId) {
            const runs = listRunIds(loaRoot).map((id) => stateSummary(readRunState(runDirectory(loaRoot, id))));
            return result('status', 'PASS', { details: { runs } });
        }
        const state = readRunState(runDirectory(loaRoot, runId));
        return result('status', state.execution.halt ? 'BLOCKED' : 'PASS', {
            run_id: runId,
            full_mode: state.full_mode,
            state: state.execution.core_state,
            stage: state.execution.stage,
            gate: state.execution.gate,
            details: stateSummary(state),
        });
    }
    catch (error) {
        return result('status', 'FAIL', {
            run_id: runId || null,
            errors: [error instanceof Error ? error.message : String(error)],
        });
    }
}
export function resumeLoaRun(runId, options = {}) {
    const loaRoot = resolve(options.loaRoot || process.cwd());
    try {
        const runDir = runDirectory(loaRoot, runId);
        recoverPendingS0Transaction(runDir, options.clock);
        recoverPendingAuthorityTransactions(runDir, options.clock);
        recoverPendingLedgerTransactions(runDir, options.clock);
        const state = verifyRunControl(runDir);
        const runtime = verifyRuntimeSnapshot(runtimeSnapshotPath(runDir), {
            allowSimulation: options.allowSimulation || state.full_mode === 'fixture-simulated',
        });
        if (runtime.tree_digest !== state.identity.runtime.digest
            || runtime.bundle.digest !== state.identity.bundle.digest) {
            throw new Error('run-local runtime snapshot disagrees with run state');
        }
        if (state.full_mode === 'fixture-simulated'
            && ['ACCEPTED', 'PROJECTION-ACCEPTED'].includes(state.execution.core_state)) {
            throw new Error('fixture-simulated execution cannot carry acceptance state');
        }
        const blocked = Boolean(state.execution.halt || state.execution.gate?.status === 'awaiting-authority');
        return result('resume', blocked ? 'BLOCKED' : 'PASS', {
            run_id: runId,
            full_mode: state.full_mode,
            state: state.execution.core_state,
            stage: state.execution.stage,
            gate: state.execution.gate,
            details: {
                ...runtimeDetails(state),
                pinned_bundle_root: runtime.bundle.root,
                next: blocked ? 'present-persisted-human-gate' : 'load-pinned-Core-orchestrator-and-first-unmet-DoD',
            },
        });
    }
    catch (error) {
        return result('resume', 'FAIL', {
            run_id: runId,
            errors: [error instanceof Error ? error.message : String(error)],
        });
    }
}
export function validateLoaRun(runId, options = {}) {
    const loaRoot = resolve(options.loaRoot || process.cwd());
    try {
        const runDir = runDirectory(loaRoot, runId);
        const state = readRunState(runDir);
        const checked = invokePinnedChecker({
            runDir,
            clock: options.clock,
            spawn: options.checkerSpawn,
            allowSimulation: options.allowSimulation || state.full_mode === 'fixture-simulated',
        });
        return result('validate', checked.record.result, {
            run_id: runId,
            full_mode: state.full_mode,
            state: state.execution.core_state,
            stage: state.execution.stage,
            gate: state.execution.gate,
            details: {
                check_record: checked.recordPath,
                kernel_report: checked.kernelReportPath,
                exit_status: checked.record.exit_status,
            },
        });
    }
    catch (error) {
        return result('validate', 'FAIL', {
            run_id: runId,
            errors: [error instanceof Error ? error.message : String(error)],
        });
    }
}
function renderUpdatedManifestForS0(runDir, response, state) {
    const path = join(runDir, 'run-manifest.md');
    let manifest = readFileSync(path, 'utf8');
    manifest = manifest.replace(/- declared_scope: >\s*\n\s*PENDING S0 HUMAN AUTHORITY/u, `- declared_scope: >\n    ${response.declared_scope.replace(/[\r\n]+/gu, ' ')}`);
    manifest = manifest.replace(/^- corpus_hash: .*$/mu, `- corpus_hash: ${state.corpus.tree_digest}`);
    manifest = insertTableRow(manifest, '## State log', `| ${state.execution.resume.sequence} | CORPUS-FROZEN | ${response.recorded_at} | ${safeTable(response.authority.identity)} | S0 authority approved exact frozen corpus |`);
    manifest = insertTableRow(manifest, '## Authority sign-offs', `| S0 corpus scope + sensitivity | approved | ${safeTable(response.authority.identity)} | ${response.recorded_at.slice(0, 10)} | control/gates/GATE-S0-response.json |`);
    if (response.simulation && !manifest.includes('fixture-simulated authority response')) {
        manifest = insertTableRow(manifest, '## Unvalidated-machinery notices', `| fixture-simulated authority response | structural fixture only; not acceptance evidence | ${response.recorded_at.slice(0, 10)} |`);
    }
    const logPath = join(runDir, 'run-log.md');
    const log = readFileSync(logPath, 'utf8');
    const simulation = response.simulation
        ? ' This authority response is fixture-simulated and is not acceptance evidence.'
        : '';
    return {
        runManifest: manifest,
        runLog: `${log}${log.endsWith('\n') ? '' : '\n'}\n## ${response.recorded_at} — S0 — exit\n`
            + `Human authority approved the declared scope and sensitivity rulings. The exact staged source bytes are now frozen at ${state.corpus.tree_digest}.${simulation}\n`,
    };
}
const S0_TRANSACTION_FORMAT = 'aleph-loa-s0-freeze-transaction/v1';
const S0_TRANSACTION_REF = 'control/transactions/TXN-s0-freeze.json';
function s0TransactionPayload(transaction) {
    return sha256Digest(stableJsonBytes(transaction));
}
function acquireS0TransactionLock(runDir, acquiredAt, _recoverDeadOwner) {
    return acquireDurableProcessLock(join(runDir, 'control', 's0-transaction.lock'), {
        format: 'aleph-loa-s0-transaction-lock/v1',
        label: 'S0 transaction writer lock',
        acquiredAt,
    });
}
function parseS0Transaction(path) {
    const value = readJsonFile(path);
    const committed = isRecord(value) && value.status === 'committed';
    const required = [
        'files_after',
        'format',
        'payload_digest',
        'plan',
        'prepared_at',
        'run_id',
        'state_after',
        'state_before_checkpoint',
        'status',
        ...(committed ? ['committed_at'] : []),
    ];
    if (!exactKeys(value, required)
        || value.format !== S0_TRANSACTION_FORMAT
        || (value.status !== 'prepared' && value.status !== 'committed')
        || typeof value.run_id !== 'string'
        || typeof value.prepared_at !== 'string'
        || typeof value.state_before_checkpoint !== 'string'
        || typeof value.payload_digest !== 'string'
        || !/^sha256:[0-9a-f]{64}$/u.test(value.payload_digest)
        || !isRecord(value.plan)
        || !isRecord(value.state_after)
        || !exactKeys(value.files_after, ['run_manifest', 'run_log', 'corpus_manifest'])
        || typeof value.files_after.run_manifest !== 'string'
        || typeof value.files_after.run_log !== 'string'
        || typeof value.files_after.corpus_manifest !== 'string'
        || (value.status === 'committed' && typeof value.committed_at !== 'string')) {
        throw new Error('S0 freeze transaction is malformed');
    }
    const transaction = value;
    const payload = {
        format: transaction.format,
        run_id: transaction.run_id,
        prepared_at: transaction.prepared_at,
        state_before_checkpoint: transaction.state_before_checkpoint,
        plan: transaction.plan,
        state_after: transaction.state_after,
        files_after: transaction.files_after,
    };
    if (transaction.payload_digest !== s0TransactionPayload(payload)
        || transaction.state_after.run_id !== transaction.run_id
        || transaction.plan.staged.run_id !== transaction.run_id
        || transaction.plan.frozen.run_id !== transaction.run_id
        || transaction.plan.response.run_id !== transaction.run_id
        || transaction.state_after.execution.resume.checkpoint_digest
            !== stateCheckpointDigest(transaction.state_after)) {
        throw new Error('S0 freeze transaction payload is inconsistent');
    }
    return transaction;
}
function applyS0Transaction(runDir, transactionPath, transaction, committedAt) {
    const current = readRunState(runDir);
    if (current.run_id !== transaction.run_id
        || !stableJsonBytes(current.identity).equals(stableJsonBytes(transaction.state_after.identity))) {
        throw new Error('S0 transaction attempted to change the run or its pinned identity');
    }
    if (transaction.status === 'committed') {
        const frozen = verifyCorpusSnapshot(runDir);
        const responsePath = join(runDir, 'control', 'gates', 'GATE-S0-response.json');
        if (!stableJsonBytes(frozen).equals(stableJsonBytes(transaction.plan.frozen))
            || current.corpus.state !== 'frozen'
            || current.corpus.tree_digest !== frozen.tree_digest
            || !existsSync(responsePath)
            || !stableJsonBytes(readJsonFile(responsePath)).equals(stableJsonBytes(transaction.plan.response))) {
            throw new Error('committed S0 transaction no longer matches its immutable corpus evidence');
        }
        return current;
    }
    const before = current.execution.resume.checkpoint_digest === transaction.state_before_checkpoint;
    const after = current.execution.resume.checkpoint_digest
        === transaction.state_after.execution.resume.checkpoint_digest;
    if (!before && !after) {
        throw new Error('S0 transaction state is neither its before nor after image');
    }
    const paths = {
        run_manifest: join(runDir, 'run-manifest.md'),
        run_log: join(runDir, 'run-log.md'),
        corpus_manifest: join(runDir, 'corpus', 'manifest.md'),
    };
    const frozen = applyCorpusFreeze(runDir, transaction.plan);
    if (frozen.tree_digest !== transaction.state_after.corpus.tree_digest) {
        throw new Error('S0 transaction frozen corpus disagrees with its state after-image');
    }
    writeFileAtomic(paths.run_manifest, transaction.files_after.run_manifest);
    writeFileAtomic(paths.run_log, transaction.files_after.run_log);
    writeFileAtomic(paths.corpus_manifest, transaction.files_after.corpus_manifest);
    if (before)
        writeRunState(runDir, structuredClone(transaction.state_after));
    writeJsonAtomic(transactionPath, {
        ...transaction,
        status: 'committed',
        committed_at: committedAt,
    });
    return readRunState(runDir);
}
export function recoverPendingS0Transaction(runDir, clock = { now: () => new Date().toISOString() }) {
    const root = resolve(runDir);
    const transactionPath = join(root, S0_TRANSACTION_REF);
    if (!existsSync(transactionPath))
        return null;
    const recoveredAt = clock.now();
    const release = acquireS0TransactionLock(root, recoveredAt, true);
    try {
        return applyS0Transaction(root, transactionPath, parseS0Transaction(transactionPath), recoveredAt);
    }
    finally {
        release();
    }
}
export function recordS0AuthorityResponse(runId, response, options = {}) {
    const loaRoot = resolve(options.loaRoot || process.cwd());
    let release = null;
    try {
        const runDir = runDirectory(loaRoot, runId);
        release = acquireS0TransactionLock(runDir, options.clock?.now() || new Date().toISOString(), false);
        const prior = verifyRunControl(runDir);
        const runtime = verifyRuntimeSnapshot(runtimeSnapshotPath(runDir), {
            allowSimulation: options.allowSimulation
                || prior.full_mode === 'fixture-simulated'
                || Boolean(response.simulation),
        });
        if (runtime.tree_digest !== prior.identity.runtime.digest
            || runtime.bundle.digest !== prior.identity.bundle.digest) {
            throw new Error('run-local runtime snapshot disagrees with run state');
        }
        if (prior.execution.stage !== 'S0'
            || prior.execution.gate?.status !== 'awaiting-authority') {
            throw new Error('run is not awaiting its S0 authority response');
        }
        const transactionPath = join(runDir, S0_TRANSACTION_REF);
        if (existsSync(transactionPath))
            throw new Error('S0 freeze transaction already exists');
        const plan = planCorpusFreeze(runDir, response);
        const state = structuredClone(prior);
        if (response.simulation)
            state.full_mode = 'fixture-simulated';
        state.corpus = {
            state: 'frozen',
            inventory_ref: 'control/corpus.snapshot.json',
            tree_digest: plan.frozen.tree_digest,
        };
        state.execution.core_state = 'CORPUS-FROZEN';
        state.execution.stage_status = 'closed';
        state.execution.halt = null;
        if (!state.execution.gate)
            throw new Error('S0 gate disappeared during update');
        state.execution.gate.status = 'approved';
        state.execution.gate.response_ref = 'control/gates/GATE-S0-response.json';
        state.execution.resume.sequence = nextDecimal(prior.execution.resume.sequence);
        state.execution.resume.last_verified_at = response.recorded_at;
        state.execution.resume.checkpoint_digest = stateCheckpointDigest(state);
        const updated = renderUpdatedManifestForS0(runDir, response, state);
        const pinnedBundle = verifyAndLoadLoaBundle(runtime.bundle.root);
        const filesAfter = {
            run_manifest: updated.runManifest,
            run_log: updated.runLog,
            corpus_manifest: renderFrozenCorpusManifest(pinnedBundle, state, plan.staged, plan.frozen, response),
        };
        const payload = {
            format: S0_TRANSACTION_FORMAT,
            run_id: runId,
            prepared_at: response.recorded_at,
            state_before_checkpoint: prior.execution.resume.checkpoint_digest,
            plan,
            state_after: state,
            files_after: filesAfter,
        };
        const transaction = {
            ...payload,
            status: 'prepared',
            payload_digest: s0TransactionPayload(payload),
        };
        writeJsonAtomic(transactionPath, transaction);
        const committed = applyS0Transaction(runDir, transactionPath, transaction, response.recorded_at);
        return result('resume', 'PASS', {
            run_id: runId,
            full_mode: committed.full_mode,
            state: committed.execution.core_state,
            stage: committed.execution.stage,
            gate: committed.execution.gate,
            details: runtimeDetails(committed),
        });
    }
    catch (error) {
        return result('resume', 'FAIL', {
            run_id: runId,
            errors: [error instanceof Error ? error.message : String(error)],
        });
    }
    finally {
        release?.();
    }
}
export function openGenericHumanAuthorityGate(runId, gate, options = {}) {
    const loaRoot = resolve(options.loaRoot || process.cwd());
    try {
        const runDir = runDirectory(loaRoot, runId);
        recoverPendingAuthorityTransactions(runDir, options.clock);
        const prior = verifyRunControl(runDir);
        const runtime = verifyRuntimeSnapshot(runtimeSnapshotPath(runDir), {
            allowSimulation: options.allowSimulation || prior.full_mode === 'fixture-simulated',
        });
        if (runtime.tree_digest !== prior.identity.runtime.digest
            || runtime.bundle.digest !== prior.identity.bundle.digest) {
            throw new Error('run-local runtime snapshot disagrees with run state');
        }
        const state = openHumanAuthorityGate(runDir, gate);
        return result('resume', 'BLOCKED', {
            run_id: runId,
            full_mode: state.full_mode,
            state: state.execution.core_state,
            stage: state.execution.stage,
            gate: state.execution.gate,
            details: runtimeDetails(state),
        });
    }
    catch (error) {
        return result('resume', 'FAIL', {
            run_id: runId,
            errors: [error instanceof Error ? error.message : String(error)],
        });
    }
}
export function recordGenericHumanAuthorityResponse(runId, decision, options = {}) {
    const loaRoot = resolve(options.loaRoot || process.cwd());
    try {
        const runDir = runDirectory(loaRoot, runId);
        recoverPendingAuthorityTransactions(runDir, options.clock);
        const prior = verifyRunControl(runDir);
        const runtime = verifyRuntimeSnapshot(runtimeSnapshotPath(runDir), {
            allowSimulation: options.allowSimulation
                || prior.full_mode === 'fixture-simulated'
                || decision.simulation !== null,
        });
        if (runtime.tree_digest !== prior.identity.runtime.digest
            || runtime.bundle.digest !== prior.identity.bundle.digest) {
            throw new Error('run-local runtime snapshot disagrees with run state');
        }
        const state = recordHumanAuthorityDecision(runDir, decision);
        return result('resume', state.execution.halt ? 'BLOCKED' : 'PASS', {
            run_id: runId,
            full_mode: state.full_mode,
            state: state.execution.core_state,
            stage: state.execution.stage,
            gate: state.execution.gate,
            details: runtimeDetails(state),
        });
    }
    catch (error) {
        return result('resume', 'FAIL', {
            run_id: runId,
            errors: [error instanceof Error ? error.message : String(error)],
        });
    }
}
function recordPersistedAuthorityResponse(runId, response, options) {
    const loaRoot = resolve(options.loaRoot || process.cwd());
    try {
        const state = readRunState(runDirectory(loaRoot, runId));
        if (state.execution.stage === 'S0'
            && state.execution.gate?.id === 'GATE-S0'
            && state.execution.gate.status === 'awaiting-authority') {
            return recordS0AuthorityResponse(runId, response, options);
        }
        return recordGenericHumanAuthorityResponse(runId, parseFileHumanAuthorityDecision(response), options);
    }
    catch (error) {
        return result('resume', 'FAIL', {
            run_id: runId,
            errors: [error instanceof Error ? error.message : String(error)],
        });
    }
}
export function dispatchLoaCommand(argv, options = {}) {
    const command = argv[0];
    if (command === 'start') {
        return startLoaRun(argv.slice(1), options);
    }
    if (command === 'status') {
        if (argv.length > 2)
            return result('status', 'FAIL', { errors: ['status accepts at most one RUN-id'] });
        return statusLoaRun(argv[1], options);
    }
    if (command === 'resume') {
        if (argv.length !== 2)
            return result('resume', 'FAIL', { errors: ['resume requires exactly one RUN-id'] });
        return resumeLoaRun(argv[1], options);
    }
    if (command === 'validate') {
        if (argv.length !== 2)
            return result('validate', 'FAIL', { errors: ['validate requires exactly one RUN-id'] });
        return validateLoaRun(argv[1], options);
    }
    return result('status', 'FAIL', {
        errors: ['usage: loa-aleph start <files-or-directories...> | status [RUN-id] | resume <RUN-id> | validate <RUN-id>'],
    });
}
function parseCli(argv) {
    const options = {};
    const forwarded = [];
    let json = false;
    let authorityResponsePath;
    let openGatePath;
    for (let index = 0; index < argv.length; index++) {
        const arg = argv[index];
        if (arg === '--json')
            json = true;
        else if (arg === '--root')
            options.loaRoot = argv[++index];
        else if (arg === '--capabilities')
            options.capabilitiesPath = argv[++index];
        else if (arg === '--allow-fixture-simulation')
            options.allowSimulation = true;
        else if (arg === '--authority-response')
            authorityResponsePath = argv[++index];
        else if (arg === '--open-gate')
            openGatePath = argv[++index];
        else
            forwarded.push(arg);
    }
    return { argv: forwarded, options, json, authorityResponsePath, openGatePath };
}
export function runLoaCli(argv = process.argv.slice(2)) {
    const parsed = parseCli(argv);
    let commandResult;
    if (parsed.authorityResponsePath && parsed.openGatePath) {
        commandResult = result('resume', 'FAIL', {
            errors: ['--authority-response and --open-gate are mutually exclusive'],
        });
    }
    else if (parsed.authorityResponsePath) {
        const runId = parsed.argv[0];
        if (!runId || parsed.argv.length !== 1) {
            commandResult = result('resume', 'FAIL', {
                errors: ['--authority-response requires exactly one RUN-id'],
            });
        }
        else {
            try {
                commandResult = recordPersistedAuthorityResponse(runId, readJsonFile(parsed.authorityResponsePath), parsed.options);
            }
            catch (error) {
                commandResult = result('resume', 'FAIL', {
                    run_id: runId,
                    errors: [error instanceof Error ? error.message : String(error)],
                });
            }
        }
    }
    else if (parsed.openGatePath) {
        const runId = parsed.argv[0];
        if (!runId || parsed.argv.length !== 1) {
            commandResult = result('resume', 'FAIL', {
                errors: ['--open-gate requires exactly one RUN-id'],
            });
        }
        else {
            try {
                commandResult = openGenericHumanAuthorityGate(runId, parseFileOpenGate(readJsonFile(parsed.openGatePath)), parsed.options);
            }
            catch (error) {
                commandResult = result('resume', 'FAIL', {
                    run_id: runId,
                    errors: [error instanceof Error ? error.message : String(error)],
                });
            }
        }
    }
    else {
        commandResult = dispatchLoaCommand(parsed.argv, parsed.options);
    }
    if (parsed.json) {
        console.log(stableJson(commandResult));
    }
    else {
        console.log(`${commandResult.result} ${commandResult.command}${commandResult.run_id ? ` ${commandResult.run_id}` : ''}`);
        if (commandResult.state)
            console.log(`STATE ${commandResult.state} STAGE ${commandResult.stage}`);
        for (const error of commandResult.errors)
            console.error(`ERROR ${error}`);
        if (commandResult.gate)
            console.log(`GATE ${commandResult.gate.id} ${commandResult.gate.status}`);
    }
    return commandResult.result === 'FAIL' ? 1 : 0;
}
if (process.argv[1] && resolve(process.argv[1]) === SCRIPT_PATH) {
    process.exitCode = runLoaCli();
}
