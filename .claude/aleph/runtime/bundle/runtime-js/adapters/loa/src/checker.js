import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, } from 'node:fs';
import { join, resolve } from 'node:path';
import { LOA_CHECK_RECORD_FORMAT, } from './types.js';
import { extractMarkdownHeading, readLockedFile, verifyAndLoadLoaBundle, } from './core-loader.js';
import { runtimeSnapshotPath, verifyRuntimeSnapshot, } from './runtime-snapshot.js';
import { acquireDurableProcessLock, verifyRunControl, } from './run-control.js';
import { readStableRegularFile, makeTreeOwnerWritable, makeTreeReadOnly, sha256Digest, stableJsonBytes, writeFileAtomic, writeJsonAtomic, } from './fs.js';
const CHECKER_LOCK_FORMAT = 'aleph-loa-checker-lock/v1';
const CHECKER_TRANSACTION_FORMAT = 'aleph-loa-checker-transaction/v1';
const CHECKER_LOCK_WAIT_MS = 10_000;
const CHECKER_LOCK_POLL_MS = 10;
const CHECKER_LOCK_SLEEP = new Int32Array(new SharedArrayBuffer(4));
function defaultClock() {
    return { now: () => new Date().toISOString() };
}
function defaultSpawn(executable, args, cwd) {
    return spawnSync(executable, args, {
        cwd,
        encoding: 'utf8',
        maxBuffer: 64 * 1024 * 1024,
        shell: false,
    });
}
function materializePinnedChecker(runDir, bundle) {
    const parent = join(runDir, 'control', 'checker-invocations');
    mkdirSync(parent, { recursive: true });
    const root = mkdtempSync(join(parent, 'CHECKER-'));
    try {
        for (const path of bundle.lock.source.manifest_projection.checker_paths) {
            writeFileAtomic(join(root, path), readLockedFile(bundle, path, 'core'), 0o400);
        }
        const checkerPath = join(root, 'runtime-js', 'scripts', 'validate-run.js');
        if (!existsSync(checkerPath)) {
            throw new Error('pinned checker inventory omits runtime-js/scripts/validate-run.js');
        }
        makeTreeReadOnly(root);
        return { root, checkerPath };
    }
    catch (error) {
        if (existsSync(root)) {
            makeTreeOwnerWritable(root);
            rmSync(root, { recursive: true, force: true });
        }
        throw error;
    }
}
function nextCheckNumber(runDir) {
    const indexes = [];
    const checkDirectory = join(runDir, 'control', 'checks');
    if (existsSync(checkDirectory)) {
        indexes.push(...readdirSync(checkDirectory)
            .map((name) => name.match(/^CHECK-(\d+)\.json$/u))
            .filter((match) => Boolean(match))
            .map((match) => Number(match[1])));
    }
    const transactionDirectory = join(runDir, 'control', 'transactions');
    if (existsSync(transactionDirectory)) {
        indexes.push(...readdirSync(transactionDirectory)
            .map((name) => name.match(/^TXN-checker-(\d+)\.json$/u))
            .filter((match) => Boolean(match))
            .map((match) => Number(match[1])));
    }
    const verificationDirectory = join(runDir, 'verification');
    if (existsSync(verificationDirectory)) {
        indexes.push(...readdirSync(verificationDirectory).flatMap((name) => {
            if (name === 'kernel-report.md')
                return [1];
            const match = name.match(/^kernel-report-(\d+)\.md$/u);
            return match ? [Number(match[1])] : [];
        }));
    }
    return String((indexes.length ? Math.max(...indexes) : 0) + 1).padStart(4, '0');
}
function isCanonicalCheckNumber(value) {
    if (!/^\d{4,}$/u.test(value))
        return false;
    const index = Number(value);
    return Number.isSafeInteger(index)
        && index > 0
        && String(index).padStart(4, '0') === value;
}
function renderKernelReport(bundleRoot, record) {
    const bundle = verifyAndLoadLoaBundle(bundleRoot);
    const templateFile = readLockedFile(bundle, 'docs/architecture/templates/01-run-control.md', 'core');
    const section = extractMarkdownHeading(templateFile, 'T1.3 Kernel report → `runs/<run-id>/verification/kernel-report.md`', 'run-control template').toString('utf8');
    const start = section.indexOf('```markdown\n');
    const end = section.lastIndexOf('\n```');
    if (start < 0 || end <= start)
        throw new Error('Core kernel-report template is malformed');
    let report = section.slice(start + '```markdown\n'.length, end);
    const fields = {
        checker_digest: record.checker_digest,
        checker_source_provenance: 'pinned immutable bundle lock',
        command: `\`${record.command.join(' ')}\``,
        date: record.invoked_at,
        result: record.result,
    };
    report = report.split('\n').map((line) => {
        const match = line.match(/^- ([a-z_]+):/u);
        if (!match || fields[match[1]] === undefined)
            return line;
        return `- ${match[1]}: ${fields[match[1]]}`;
    }).join('\n');
    const output = `${record.stdout}${record.stderr}`;
    report = report.replace(/⟨paste the checker's full stdout\/stderr⟩/u, output);
    return report.endsWith('\n') ? report : `${report}\n`;
}
function kernelReportRelativePath(number) {
    const index = Number(number);
    return index === 1
        ? 'verification/kernel-report.md'
        : `verification/kernel-report-${String(index)}.md`;
}
function isRecord(value) {
    return typeof value === 'object' && value !== null && !Array.isArray(value);
}
function exactKeys(value, expected) {
    const actual = Object.keys(value).sort();
    const sortedExpected = [...expected].sort();
    return actual.length === sortedExpected.length
        && actual.every((key, index) => key === sortedExpected[index]);
}
function transactionRelativePath(number) {
    return `control/transactions/TXN-checker-${number}.json`;
}
function validateCheckerTransaction(runDir, name, value, expectedRunId, expectedCheckerDigest, expectedBundleDigest) {
    const match = name.match(/^TXN-checker-(\d+)\.json$/u);
    if (!match || !isRecord(value) || !exactKeys(value, [
        'format',
        'status',
        'check_id',
        'record_path',
        'record_digest',
        'record',
        'kernel_report_path',
        'kernel_report_digest',
        'kernel_report',
        'prepared_at',
        'committed_at',
    ])) {
        throw new Error(`checker transaction journal is malformed: ${name}`);
    }
    const number = match[1];
    if (!isCanonicalCheckNumber(number)) {
        throw new Error(`checker transaction journal has a noncanonical sequence: ${name}`);
    }
    const recordPath = `control/checks/CHECK-${number}.json`;
    const reportPath = kernelReportRelativePath(number);
    if (value.format !== CHECKER_TRANSACTION_FORMAT
        || (value.status !== 'prepared' && value.status !== 'committed')
        || value.check_id !== `CHECK-${number}`
        || value.record_path !== recordPath
        || value.kernel_report_path !== reportPath
        || typeof value.record_digest !== 'string'
        || typeof value.kernel_report_digest !== 'string'
        || typeof value.kernel_report !== 'string'
        || !value.kernel_report
        || typeof value.prepared_at !== 'string'
        || !value.prepared_at.trim()
        || (value.status === 'prepared'
            ? value.committed_at !== null
            : typeof value.committed_at !== 'string' || !value.committed_at.trim())
        || !isRecord(value.record)) {
        throw new Error(`checker transaction journal is inconsistent: ${name}`);
    }
    const record = value.record;
    if (!exactKeys(value.record, [
        'format',
        'run_id',
        'checker_digest',
        'bundle_digest',
        'command',
        'invoked_at',
        'exit_status',
        'signal',
        'stdout',
        'stderr',
        'result',
    ])
        || !Array.isArray(record.command)
        || record.command.length === 0
        || record.command.some((entry) => typeof entry !== 'string' || !entry)
        || typeof record.invoked_at !== 'string'
        || !record.invoked_at.trim()
        || typeof record.exit_status !== 'string'
        || (record.signal !== null && typeof record.signal !== 'string')
        || typeof record.stdout !== 'string'
        || typeof record.stderr !== 'string'
        || (record.result !== 'PASS' && record.result !== 'FAIL')) {
        throw new Error(`checker transaction record is malformed: ${name}`);
    }
    const recordBytes = stableJsonBytes(record);
    const reportBytes = Buffer.from(value.kernel_report, 'utf8');
    if (record.format !== LOA_CHECK_RECORD_FORMAT
        || record.run_id !== expectedRunId
        || record.checker_digest !== expectedCheckerDigest
        || record.bundle_digest !== expectedBundleDigest
        || value.record_digest !== sha256Digest(recordBytes)
        || value.kernel_report_digest !== sha256Digest(reportBytes)) {
        throw new Error(`checker transaction payload is inconsistent: ${name}`);
    }
    // All paths are reconstructed from the journal filename; no journal field
    // is ever trusted as a filesystem target.
    void runDir;
    return value;
}
function writeOrVerifyExact(path, bytes, label) {
    if (existsSync(path)) {
        if (!readStableRegularFile(path).bytes.equals(bytes)) {
            throw new Error(`${label} disagrees with its checker transaction journal`);
        }
        return;
    }
    writeFileAtomic(path, bytes);
}
function applyCheckerTransaction(runDir, transactionPath, transaction, committedAt) {
    const recordPath = join(runDir, transaction.record_path);
    const reportPath = join(runDir, transaction.kernel_report_path);
    writeOrVerifyExact(recordPath, stableJsonBytes(transaction.record), `${transaction.check_id} record`);
    writeOrVerifyExact(reportPath, Buffer.from(transaction.kernel_report, 'utf8'), `${transaction.check_id} kernel report`);
    if (transaction.status === 'committed')
        return transaction;
    if (!readStableRegularFile(transactionPath).bytes.equals(stableJsonBytes(transaction))) {
        throw new Error(`${transaction.check_id} transaction changed before commit`);
    }
    const committed = {
        ...transaction,
        status: 'committed',
        committed_at: committedAt,
    };
    writeJsonAtomic(transactionPath, committed);
    return committed;
}
function recoverCheckerTransactionsUnlocked(runDir, recoveredAt, expectedRunId, expectedCheckerDigest, expectedBundleDigest) {
    const transactionRoot = join(runDir, 'control', 'transactions');
    if (!existsSync(transactionRoot))
        return;
    for (const name of readdirSync(transactionRoot).sort()) {
        if (!/^TXN-checker-\d+\.json$/u.test(name))
            continue;
        const transactionPath = join(transactionRoot, name);
        const bytes = readStableRegularFile(transactionPath).bytes;
        let value;
        try {
            value = JSON.parse(bytes.toString('utf8'));
        }
        catch {
            throw new Error(`checker transaction journal is malformed: ${name}`);
        }
        if (!bytes.equals(stableJsonBytes(value))) {
            throw new Error(`checker transaction journal is not canonical JSON: ${name}`);
        }
        const transaction = validateCheckerTransaction(runDir, name, value, expectedRunId, expectedCheckerDigest, expectedBundleDigest);
        applyCheckerTransaction(runDir, transactionPath, transaction, recoveredAt);
    }
}
function withCheckerLock(runDir, acquiredAt, operation) {
    const lockPath = join(runDir, 'control', 'checker-writer.lock');
    const deadline = Date.now() + CHECKER_LOCK_WAIT_MS;
    let release;
    while (!release) {
        try {
            release = acquireDurableProcessLock(lockPath, {
                format: CHECKER_LOCK_FORMAT,
                label: 'pinned checker publisher lock',
                acquiredAt,
            });
        }
        catch (error) {
            const message = error instanceof Error ? error.message : String(error);
            if (!/(?:already active under pid|recovery is already active)/u.test(message)
                || Date.now() >= deadline) {
                throw error;
            }
            Atomics.wait(CHECKER_LOCK_SLEEP, 0, 0, CHECKER_LOCK_POLL_MS);
        }
    }
    try {
        return operation();
    }
    finally {
        release();
    }
}
export function invokePinnedChecker(options) {
    const runDir = resolve(options.runDir);
    const state = verifyRunControl(runDir);
    const runtime = verifyRuntimeSnapshot(runtimeSnapshotPath(runDir), {
        allowSimulation: options.allowSimulation,
    });
    if (runtime.run_id !== state.run_id
        || runtime.tree_digest !== state.identity.runtime.digest
        || runtime.bundle.digest !== state.identity.bundle.digest) {
        throw new Error('runtime snapshot disagrees with pinned run identity');
    }
    const bundle = verifyAndLoadLoaBundle(runtime.bundle.root);
    if (bundle.lock.checker_digest !== state.identity.checker_digest) {
        throw new Error('pinned checker digest disagrees with the verified runtime bundle');
    }
    const clock = options.clock || defaultClock();
    const invokedAt = clock.now();
    withCheckerLock(runDir, invokedAt, () => recoverCheckerTransactionsUnlocked(runDir, invokedAt, state.run_id, bundle.lock.checker_digest, bundle.lock.bundle.digest));
    const checkerInvocation = materializePinnedChecker(runDir, bundle);
    const args = [
        checkerInvocation.checkerPath,
        '--root',
        bundle.root,
        '--run',
        runDir,
        '--json',
    ];
    const result = (options.spawn || defaultSpawn)(process.execPath, args, checkerInvocation.root);
    if (result.error)
        throw result.error;
    const record = {
        format: LOA_CHECK_RECORD_FORMAT,
        run_id: state.run_id,
        checker_digest: bundle.lock.checker_digest,
        bundle_digest: bundle.lock.bundle.digest,
        command: [process.execPath, ...args],
        invoked_at: invokedAt,
        exit_status: result.status === null ? 'null' : String(result.status),
        signal: result.signal,
        stdout: result.stdout || '',
        stderr: result.stderr || '',
        result: result.status === 0 ? 'PASS' : 'FAIL',
    };
    return withCheckerLock(runDir, invokedAt, () => {
        recoverCheckerTransactionsUnlocked(runDir, invokedAt, state.run_id, bundle.lock.checker_digest, bundle.lock.bundle.digest);
        const number = nextCheckNumber(runDir);
        const recordRelativePath = `control/checks/CHECK-${number}.json`;
        const reportRelativePath = kernelReportRelativePath(number);
        const transactionPath = join(runDir, transactionRelativePath(number));
        const recordPath = join(runDir, recordRelativePath);
        const kernelReportPath = join(runDir, reportRelativePath);
        if (existsSync(transactionPath) || existsSync(recordPath) || existsSync(kernelReportPath)) {
            throw new Error(`checker result slot CHECK-${number} is already occupied`);
        }
        const kernelReport = renderKernelReport(bundle.root, record);
        const transaction = {
            format: CHECKER_TRANSACTION_FORMAT,
            status: 'prepared',
            check_id: `CHECK-${number}`,
            record_path: recordRelativePath,
            record_digest: sha256Digest(stableJsonBytes(record)),
            record,
            kernel_report_path: reportRelativePath,
            kernel_report_digest: sha256Digest(Buffer.from(kernelReport, 'utf8')),
            kernel_report: kernelReport,
            prepared_at: invokedAt,
            committed_at: null,
        };
        writeJsonAtomic(transactionPath, transaction);
        applyCheckerTransaction(runDir, transactionPath, transaction, invokedAt);
        return { record, recordPath, kernelReportPath };
    });
}
