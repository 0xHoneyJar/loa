#!/usr/bin/env node
import { existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, renameSync, rmSync, writeFileSync, } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { dirname, isAbsolute, join, relative, resolve, } from 'node:path';
import { fileURLToPath } from 'node:url';
import { ASSEMBLY_TOOL_PATH, BUNDLE_LOCK_FORMAT, DIGEST_ALGORITHM, SOURCE_PROVENANCE_FORMAT, buildBundlePlan, bundleLockBytes, canonicalJson, createBundleLock, digestEntries, fileDigest, gitCommitObjectId, gitCommitTree, isRecord, normalizedRepositoryPath, provenanceDigest, readJsonFile, resealBundleLock, sha256Digest, sortedUnique, stringLeaves, utf8Compare, } from './lib/bundle-format.js';
import { validateCoreBoundary } from './validate-core-boundary.js';
const SCRIPT_PATH = fileURLToPath(import.meta.url);
const REPO_ROOT = resolve(dirname(SCRIPT_PATH), '..');
const DEFAULT_OUTPUT = join(REPO_ROOT, '.aleph-bundles');
const HOST_ADAPTER_IDS = ['loa', 'hermes'];
const SHA256_PATTERN = /^sha256:[0-9a-f]{64}$/;
export function humanVerificationPrefix(report) {
    return report.result === 'PASS' && report.summary ? 'VERIFIED' : null;
}
function sameStrings(left, right) {
    const a = sortedUnique(left);
    const b = sortedUnique(right);
    return a.length === b.length && a.every((value, index) => value === b[index]);
}
function exactKeys(value, keys) {
    return isRecord(value) && sameStrings(Object.keys(value), [...keys]);
}
function parseCli(args) {
    const options = {
        command: '',
        root: REPO_ROOT,
        output: DEFAULT_OUTPUT,
        bundles: [],
        json: false,
        help: false,
        error: '',
    };
    const [command, ...rest] = args;
    if (command === 'assemble' || command === 'verify')
        options.command = command;
    else if (command === '--help' || command === '-h' || command === undefined) {
        options.help = true;
    }
    else {
        options.error = `unknown command "${command}"`;
    }
    for (let index = 0; index < rest.length; index += 1) {
        const arg = rest[index];
        if (arg === '--json')
            options.json = true;
        else if (arg === '--help' || arg === '-h')
            options.help = true;
        else if (arg === '--root') {
            const value = rest[index + 1];
            if (!value)
                options.error = '--root requires a directory';
            else {
                options.root = resolve(value);
                index += 1;
            }
        }
        else if (arg === '--output') {
            const value = rest[index + 1];
            if (!value)
                options.error = '--output requires a directory';
            else {
                options.output = resolve(value);
                index += 1;
            }
        }
        else if (arg === '--bundle') {
            const value = rest[index + 1];
            if (!value)
                options.error = '--bundle requires a directory';
            else {
                options.bundles.push(resolve(value));
                index += 1;
            }
        }
        else {
            options.error = `unknown argument "${arg}"`;
        }
    }
    if (options.root !== REPO_ROOT && options.output === DEFAULT_OUTPUT) {
        options.output = join(options.root, '.aleph-bundles');
    }
    return options;
}
function failureMessages(report) {
    return report.checks
        .filter((check) => check.status === 'FAIL')
        .map((check) => `${check.id} ${check.message}`);
}
function loadSource(root) {
    const report = validateCoreBoundary({ root });
    if (report.result !== 'PASS') {
        throw new Error(`source Core-boundary validation failed: ${failureMessages(report).join('; ')}`);
    }
    const manifest = readJsonFile(join(root, 'core.manifest.json'));
    const plans = manifest.bundle_targets
        .map((target) => {
        const adapterPath = join(root, 'adapters', target.adapter_id, 'adapter.manifest.json');
        const adapter = readJsonFile(adapterPath);
        return buildBundlePlan(root, manifest, target, adapter);
    })
        .sort((left, right) => utf8Compare(left.target.id, right.target.id));
    if (plans.length !== 2
        || !sameStrings(plans.map((plan) => plan.target.id), ['aleph-for-loa', 'aleph-for-hermes'])) {
        throw new Error('source must define exactly aleph-for-loa and aleph-for-hermes');
    }
    const coreDigests = new Set(plans.map((plan) => plan.coreDigest));
    const coreInventories = new Set(plans.map((plan) => canonicalJson(plan.files.filter((file) => file.classification === 'core'))));
    if (coreDigests.size !== 1 || coreInventories.size !== 1) {
        throw new Error('release-blocking Core digest or inventory equality failed');
    }
    return { manifest, plans, report };
}
function pathInside(parent, child) {
    const path = relative(parent, child);
    return path === '' || (!path.startsWith('..') && !isAbsolute(path));
}
function assertIgnoredOutput(root, output) {
    if (!pathInside(root, output))
        return;
    const relativeOutput = relative(root, output);
    if (!relativeOutput)
        throw new Error('bundle output may not replace the source root');
    const probe = `${relativeOutput.replaceAll('\\', '/')}/.aleph-ignore-probe`;
    const result = spawnSync('git', ['-C', root, 'check-ignore', '-q', '--', probe], {
        encoding: 'utf8',
    });
    if (result.status !== 0) {
        throw new Error(`bundle output inside the repository must be ignored: ${relativeOutput}`);
    }
}
function sourceSnapshot(plans, root) {
    const records = new Map();
    for (const plan of plans) {
        for (const file of plan.files) {
            const existing = records.get(file.path);
            if (existing && canonicalJson(existing) !== canonicalJson(file)) {
                throw new Error(`bundle plans disagree about source file ${file.path}`);
            }
            records.set(file.path, file);
        }
    }
    const snapshot = new Map();
    for (const [path, record] of [...records].sort(([left], [right]) => (utf8Compare(left, right)))) {
        const absolute = join(root, path);
        if (!existsSync(absolute) || !lstatSync(absolute).isFile()) {
            throw new Error(`source snapshot path is missing or not a file: ${path}`);
        }
        if (lstatSync(absolute).isSymbolicLink()) {
            throw new Error(`source snapshot path is a symlink: ${path}`);
        }
        const bytes = readFileSync(absolute);
        if (sha256Digest(bytes) !== record.digest) {
            throw new Error(`source changed while snapshotting: ${path}`);
        }
        snapshot.set(path, bytes);
    }
    return snapshot;
}
function writeStagedBundle(stageRoot, plan, snapshot, lock) {
    const bundleRoot = join(stageRoot, plan.target.id);
    mkdirSync(bundleRoot, { recursive: true });
    for (const file of plan.files) {
        const bytes = snapshot.get(file.path);
        if (!bytes)
            throw new Error(`source snapshot omitted ${file.path}`);
        const destination = join(bundleRoot, file.path);
        mkdirSync(dirname(destination), { recursive: true });
        writeFileSync(destination, bytes);
    }
    writeFileSync(join(bundleRoot, 'bundle.lock.json'), bundleLockBytes(lock));
    return bundleRoot;
}
function recursiveFiles(root) {
    const files = [];
    const errors = [];
    function visit(directory, prefix) {
        for (const entry of readdirSync(directory, { withFileTypes: true })) {
            const path = prefix ? `${prefix}/${entry.name}` : entry.name;
            const absolute = join(directory, entry.name);
            const stat = lstatSync(absolute);
            if (stat.isSymbolicLink()) {
                errors.push(`symlink is forbidden: ${path}`);
            }
            else if (stat.isDirectory()) {
                visit(absolute, path);
            }
            else if (stat.isFile()) {
                files.push(path);
            }
            else {
                errors.push(`non-file bundle entry is forbidden: ${path}`);
            }
        }
    }
    visit(root, '');
    return { files: files.sort(utf8Compare), errors };
}
function validateDigest(value, scope, errors) {
    if (typeof value !== 'string' || !SHA256_PATTERN.test(value)) {
        errors.push(`${scope} must be sha256:<64 lowercase hex>`);
    }
}
function validateLockStructure(value, errors) {
    if (!exactKeys(value, [
        'lock_format',
        'digest_algorithm',
        'lock_digest',
        'bundle',
        'core',
        'adapter',
        'checker_digest',
        'adapter_protocol_version',
        'run_format_version',
        'source',
        'provenance',
        'files',
    ])) {
        errors.push('lock top-level keys are malformed');
        return null;
    }
    const lock = value;
    if (lock.lock_format !== BUNDLE_LOCK_FORMAT) {
        errors.push(`lock_format must be ${BUNDLE_LOCK_FORMAT}`);
    }
    if (lock.digest_algorithm !== DIGEST_ALGORITHM) {
        errors.push(`digest_algorithm must be ${DIGEST_ALGORITHM}`);
    }
    validateDigest(lock.lock_digest, 'lock_digest', errors);
    if (!exactKeys(lock.bundle, [
        'id',
        'version',
        'payload_digest',
        'digest',
    ])) {
        errors.push('bundle fields are malformed');
    }
    else {
        if (typeof lock.bundle.id !== 'string' || !/^aleph-for-[a-z][a-z0-9-]*$/.test(lock.bundle.id))
            errors.push('bundle.id is malformed');
        if (typeof lock.bundle.version !== 'string')
            errors.push('bundle.version is malformed');
        validateDigest(lock.bundle.payload_digest, 'bundle.payload_digest', errors);
        validateDigest(lock.bundle.digest, 'bundle.digest', errors);
    }
    if (!exactKeys(lock.core, ['id', 'version', 'tree_digest'])) {
        errors.push('core fields are malformed');
    }
    else {
        if (typeof lock.core.id !== 'string')
            errors.push('core.id is malformed');
        if (typeof lock.core.version !== 'string')
            errors.push('core.version is malformed');
        validateDigest(lock.core.tree_digest, 'core.tree_digest', errors);
    }
    if (!exactKeys(lock.adapter, ['id', 'version', 'lifecycle', 'tree_digest'])) {
        errors.push('adapter fields are malformed');
    }
    else {
        if (typeof lock.adapter.id !== 'string'
            || !/^[a-z][a-z0-9-]*$/.test(lock.adapter.id)) {
            errors.push('adapter.id is malformed');
        }
        if (typeof lock.adapter.version !== 'string') {
            errors.push('adapter.version is malformed');
        }
        if (!['planned', 'implemented', 'validated', 'sanctioned'].includes(lock.adapter.lifecycle)) {
            errors.push('adapter.lifecycle is malformed');
        }
        validateDigest(lock.adapter.tree_digest, 'adapter.tree_digest', errors);
    }
    validateDigest(lock.checker_digest, 'checker_digest', errors);
    if (typeof lock.adapter_protocol_version !== 'string') {
        errors.push('adapter_protocol_version is malformed');
    }
    if (typeof lock.run_format_version !== 'string') {
        errors.push('run_format_version is malformed');
    }
    if (!exactKeys(lock.source, [
        'manifest_projection',
        'manifest_projection_digest',
        'assembly_tool',
    ])) {
        errors.push('source fields are malformed');
    }
    else {
        if (!isRecord(lock.source.manifest_projection)) {
            errors.push('source.manifest_projection must be an object');
        }
        validateDigest(lock.source.manifest_projection_digest, 'source.manifest_projection_digest', errors);
        if (!exactKeys(lock.source.assembly_tool, ['path', 'digest'])) {
            errors.push('source.assembly_tool fields are malformed');
        }
        else {
            if (lock.source.assembly_tool.path !== ASSEMBLY_TOOL_PATH) {
                errors.push(`source.assembly_tool.path must be ${ASSEMBLY_TOOL_PATH}`);
            }
            validateDigest(lock.source.assembly_tool.digest, 'source.assembly_tool.digest', errors);
        }
    }
    if (!exactKeys(lock.provenance, ['format', 'vcs', 'digest'])) {
        errors.push('provenance fields are malformed');
    }
    else {
        if (lock.provenance.format !== SOURCE_PROVENANCE_FORMAT) {
            errors.push(`provenance.format must be ${SOURCE_PROVENANCE_FORMAT}`);
        }
        validateDigest(lock.provenance.digest, 'provenance.digest', errors);
        const vcs = lock.provenance.vcs;
        if (!exactKeys(vcs, [
            'kind',
            'object_format',
            'commit',
            'commit_object',
            'commit_tree',
            'resolved',
            'mutable_ref',
            'worktree_state',
        ])) {
            errors.push('provenance.vcs fields are malformed');
        }
        else {
            if (vcs.kind !== 'git-dependency-closure-snapshot') {
                errors.push('provenance.vcs.kind must be git-dependency-closure-snapshot');
            }
            if (vcs.object_format !== 'sha1' && vcs.object_format !== 'sha256') {
                errors.push('provenance.vcs.object_format must be sha1 or sha256');
            }
            else {
                const length = vcs.object_format === 'sha1' ? 40 : 64;
                const pattern = new RegExp(`^[0-9a-f]{${length}}$`);
                if (!pattern.test(vcs.commit) || /^0+$/.test(vcs.commit)) {
                    errors.push('provenance.vcs.commit must be a full resolved object ID');
                }
                if (!pattern.test(vcs.commit_tree) || /^0+$/.test(vcs.commit_tree)) {
                    errors.push('provenance.vcs.commit_tree must be a full resolved object ID');
                }
                if (typeof vcs.commit_object !== 'string'
                    || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/
                        .test(vcs.commit_object)
                    || Buffer.from(vcs.commit_object, 'base64').toString('base64')
                        !== vcs.commit_object) {
                    errors.push('provenance.vcs.commit_object must be canonical base64');
                }
                else {
                    if (gitCommitObjectId(vcs) !== vcs.commit) {
                        errors.push('provenance.vcs.commit does not match commit_object');
                    }
                    if (gitCommitTree(vcs) !== vcs.commit_tree) {
                        errors.push('provenance.vcs.commit_tree does not match commit_object');
                    }
                }
            }
            if (vcs.resolved !== true) {
                errors.push('provenance.vcs.resolved must be true');
            }
            if (vcs.mutable_ref !== null) {
                errors.push('provenance.vcs.mutable_ref must be null');
            }
            if (vcs.worktree_state !== 'clean' && vcs.worktree_state !== 'modified') {
                errors.push('provenance.vcs.worktree_state must be clean or modified');
            }
        }
    }
    if (!Array.isArray(lock.files) || lock.files.length === 0) {
        errors.push('files must be a nonempty ordered inventory');
    }
    else {
        const paths = [];
        for (const [index, file] of lock.files.entries()) {
            if (!exactKeys(file, ['path', 'classification', 'digest'])) {
                errors.push(`files[${index}] fields are malformed`);
                continue;
            }
            if (typeof file.path !== 'string' || !normalizedRepositoryPath(file.path)) {
                errors.push(`files[${index}].path is not normalized`);
            }
            else {
                paths.push(file.path);
            }
            if (file.classification !== 'core' && file.classification !== 'adapter') {
                errors.push(`files[${index}].classification is invalid`);
            }
            validateDigest(file.digest, `files[${index}].digest`, errors);
        }
        if (new Set(paths).size !== paths.length)
            errors.push('files paths must be unique');
        if (canonicalJson(paths) !== canonicalJson([...paths].sort(utf8Compare))) {
            errors.push('files inventory must be ordered by UTF-8 path bytes');
        }
    }
    return errors.length ? null : lock;
}
function adapterForeignProblems(bundleRoot, lock) {
    const problems = [];
    for (const foreignId of HOST_ADAPTER_IDS.filter((id) => id !== lock.adapter.id)) {
        const pathToken = Buffer.from(`adapters/${foreignId}/`, 'utf8');
        const bundleToken = Buffer.from(`aleph-for-${foreignId}`, 'utf8');
        const namePattern = new RegExp(`(^|[^a-z0-9])${foreignId}([^a-z0-9]|$)`, 'i');
        for (const file of lock.files.filter((item) => item.classification === 'adapter')) {
            const absolute = join(bundleRoot, file.path);
            if (!existsSync(absolute))
                continue;
            const stat = lstatSync(absolute);
            if (stat.isSymbolicLink() || !stat.isFile())
                continue;
            const bytes = readFileSync(absolute);
            if (bytes.indexOf(pathToken) >= 0 || bytes.indexOf(bundleToken) >= 0) {
                problems.push(`${file.path} contains foreign-adapter path ${foreignId}`);
            }
            if (namePattern.test(bytes.toString('latin1'))) {
                problems.push(`${file.path} names foreign adapter or host ${foreignId}`);
            }
        }
    }
    return sortedUnique(problems);
}
function decodedAdapterForeignProblems(adapter, adapterId) {
    const problems = [];
    const values = stringLeaves(adapter);
    for (const foreignId of HOST_ADAPTER_IDS.filter((id) => id !== adapterId)) {
        const namePattern = new RegExp(`(^|[^a-z0-9])${foreignId}([^a-z0-9]|$)`, 'i');
        if (values.some((value) => (value.includes(`adapters/${foreignId}/`)
            || value.includes(`aleph-for-${foreignId}`)
            || namePattern.test(value)))) {
            problems.push(`decoded adapter manifest names foreign adapter or host ${foreignId}`);
        }
    }
    return problems;
}
function runGit(root, args) {
    const result = spawnSync('git', ['-C', root, ...args], {
        encoding: 'utf8',
        maxBuffer: 32 * 1024 * 1024,
    });
    if (result.status !== 0) {
        throw new Error(`git ${args.join(' ')} failed: ${result.stderr.trim()
            || result.error?.message
            || `status ${String(result.status)}`}`);
    }
}
function emittedBoundaryReport(bundleRoot, lock) {
    const tempRoot = mkdtempSync(join(tmpdir(), 'aleph-bundle-boundary-'));
    try {
        for (const file of lock.files) {
            const destination = join(tempRoot, file.path);
            mkdirSync(dirname(destination), { recursive: true });
            writeFileSync(destination, readFileSync(join(bundleRoot, file.path)));
        }
        writeFileSync(join(tempRoot, 'core.manifest.json'), `${JSON.stringify(lock.source.manifest_projection, null, 2)}\n`);
        runGit(tempRoot, ['init', '-q']);
        runGit(tempRoot, ['add', '--all']);
        const report = validateCoreBoundary({
            root: tempRoot,
            bundleProvenance: {
                [lock.bundle.id]: lock.provenance,
            },
        });
        if (report.result !== 'PASS') {
            throw new Error(`emitted Core-boundary validator failed: ${JSON.stringify(report.checks)}`);
        }
        return report;
    }
    finally {
        rmSync(tempRoot, { recursive: true, force: true });
    }
}
function compareBoundaryDigests(report, lock, errors) {
    if (!isRecord(report.digests)) {
        errors.push('emitted Core-boundary report omitted digests');
        return;
    }
    const digests = report.digests;
    if (digests.core !== lock.core.tree_digest) {
        errors.push('emitted Core-boundary Core digest disagrees with lock');
    }
    if (digests.checker !== lock.checker_digest) {
        errors.push('emitted Core-boundary checker digest disagrees with lock');
    }
    if (!isRecord(digests.adapters)
        || digests.adapters[lock.adapter.id] !== lock.adapter.tree_digest) {
        errors.push('emitted Core-boundary adapter digest disagrees with lock');
    }
    const bundleDigests = isRecord(digests.bundles)
        ? digests.bundles[lock.bundle.id]
        : null;
    if (!isRecord(bundleDigests)
        || bundleDigests.bundleDigest !== lock.bundle.digest) {
        errors.push('emitted Core-boundary bundle digest disagrees with lock');
    }
}
export function verifyBundle(bundlePath) {
    const bundleRoot = resolve(bundlePath);
    const errors = [];
    if (!existsSync(bundleRoot) || !lstatSync(bundleRoot).isDirectory()) {
        return {
            result: 'FAIL',
            bundlePath: bundleRoot,
            errors: ['bundle path is missing or not a directory'],
        };
    }
    const lockPath = join(bundleRoot, 'bundle.lock.json');
    if (!existsSync(lockPath) || !lstatSync(lockPath).isFile()) {
        return {
            result: 'FAIL',
            bundlePath: bundleRoot,
            errors: ['bundle.lock.json is missing or not a file'],
        };
    }
    const rawLock = readFileSync(lockPath);
    let value;
    try {
        value = JSON.parse(rawLock.toString('utf8'));
    }
    catch (error) {
        return {
            result: 'FAIL',
            bundlePath: bundleRoot,
            errors: [`bundle.lock.json is invalid JSON: ${error instanceof Error ? error.message : String(error)}`],
        };
    }
    let canonical;
    try {
        canonical = Buffer.from(`${canonicalJson(value)}\n`, 'utf8');
    }
    catch (error) {
        return {
            result: 'FAIL',
            bundlePath: bundleRoot,
            errors: [`bundle.lock.json cannot be canonically serialized: ${error instanceof Error ? error.message : String(error)}`],
        };
    }
    if (!rawLock.equals(canonical)) {
        errors.push('bundle.lock.json is not canonical JSON plus one LF');
    }
    const lock = validateLockStructure(value, errors);
    if (!lock) {
        return { result: 'FAIL', bundlePath: bundleRoot, errors: sortedUnique(errors) };
    }
    const disk = recursiveFiles(bundleRoot);
    errors.push(...disk.errors);
    const expectedPaths = [...lock.files.map((file) => file.path), 'bundle.lock.json']
        .sort(utf8Compare);
    for (const path of expectedPaths.filter((path) => !disk.files.includes(path))) {
        errors.push(`missing bundle file: ${path}`);
    }
    for (const path of disk.files.filter((path) => !expectedPaths.includes(path))) {
        errors.push(`extra bundle file: ${path}`);
    }
    const actualFiles = [];
    for (const file of lock.files) {
        const absolute = join(bundleRoot, file.path);
        if (!existsSync(absolute) || !lstatSync(absolute).isFile())
            continue;
        if (lstatSync(absolute).isSymbolicLink()) {
            errors.push(`bundle file is a symlink: ${file.path}`);
            continue;
        }
        const digest = fileDigest(bundleRoot, file.path);
        if (digest !== file.digest)
            errors.push(`modified bundle file: ${file.path}`);
        actualFiles.push({ ...file, digest });
    }
    const projection = lock.source.manifest_projection;
    const projectionFiles = isRecord(projection.files) ? projection.files : null;
    const projectionAdapters = projectionFiles && isRecord(projectionFiles.adapter)
        ? projectionFiles.adapter
        : null;
    const projectionCorePaths = projectionFiles && Array.isArray(projectionFiles.core)
        && projectionFiles.core.every((path) => typeof path === 'string')
        ? projectionFiles.core
        : [];
    const projectionAdapterPaths = projectionAdapters
        && Array.isArray(projectionAdapters[lock.adapter.id])
        && projectionAdapters[lock.adapter.id].every((path) => typeof path === 'string')
        ? projectionAdapters[lock.adapter.id]
        : [];
    const projectionCheckerPaths = Array.isArray(projection.checker_paths)
        && projection.checker_paths.every((path) => typeof path === 'string')
        ? projection.checker_paths
        : [];
    const projectionTargets = Array.isArray(projection.bundle_targets)
        ? projection.bundle_targets
        : [];
    if (!projectionFiles || !projectionAdapters
        || projectionCorePaths.length === 0
        || projectionAdapterPaths.length === 0
        || projectionCheckerPaths.length === 0
        || projectionTargets.length !== 1) {
        errors.push('source manifest projection inventories are malformed');
    }
    const adapterIds = projectionAdapters ? Object.keys(projectionAdapters) : [];
    if (projection.manifest_format !== 'aleph-core-manifest/v1') {
        errors.push('source manifest projection format is invalid');
    }
    if (adapterIds.length !== 1 || adapterIds[0] !== lock.adapter.id) {
        errors.push('source manifest projection must select exactly the locked adapter');
    }
    const target = projectionTargets[0];
    if (projectionTargets.length !== 1
        || target?.id !== lock.bundle.id
        || target?.adapter_id !== lock.adapter.id
        || target?.version !== lock.bundle.version) {
        errors.push('source manifest projection target disagrees with bundle');
    }
    const corePaths = lock.files
        .filter((file) => file.classification === 'core')
        .map((file) => file.path);
    const adapterPaths = lock.files
        .filter((file) => file.classification === 'adapter')
        .map((file) => file.path);
    if (!sameStrings(corePaths, projectionCorePaths)) {
        errors.push('Core inventory disagrees with source manifest projection');
    }
    if (!sameStrings(adapterPaths, projectionAdapterPaths)) {
        errors.push('adapter inventory disagrees with source manifest projection');
    }
    if (!projectionCheckerPaths.every((path) => corePaths.includes(path))) {
        errors.push('checker inventory must be a subset of Core');
    }
    const coreDigest = digestEntries(actualFiles.filter((file) => file.classification === 'core'));
    const adapterDigest = digestEntries(actualFiles.filter((file) => file.classification === 'adapter'));
    const payloadDigest = digestEntries(actualFiles);
    const checkerPathSet = new Set(projectionCheckerPaths);
    const checkerDigest = digestEntries(actualFiles.filter((file) => checkerPathSet.has(file.path)));
    if (coreDigest !== lock.core.tree_digest)
        errors.push('Core tree digest mismatch');
    if (adapterDigest !== lock.adapter.tree_digest) {
        errors.push('adapter tree digest mismatch');
    }
    if (payloadDigest !== lock.bundle.payload_digest) {
        errors.push('payload digest mismatch');
    }
    if (checkerDigest !== lock.checker_digest)
        errors.push('checker digest mismatch');
    if (lock.source.manifest_projection_digest !== sha256Digest(Buffer.from(`${canonicalJson(projection)}\n`, 'utf8'))) {
        errors.push('source manifest projection digest mismatch');
    }
    const toolRecord = actualFiles.find((file) => file.path === lock.source.assembly_tool.path);
    if (!toolRecord || toolRecord.classification !== 'core'
        || toolRecord.digest !== lock.source.assembly_tool.digest) {
        errors.push('assembly tool identity does not resolve to emitted Core bytes');
    }
    if (lock.provenance.digest !== provenanceDigest(lock.provenance.vcs)) {
        errors.push('source provenance digest mismatch');
    }
    const resealed = resealBundleLock(lock);
    if (resealed.lock_digest !== lock.lock_digest)
        errors.push('lock digest mismatch');
    if (resealed.bundle.digest !== lock.bundle.digest)
        errors.push('bundle digest mismatch');
    const adapterManifestPath = `adapters/${lock.adapter.id}/adapter.manifest.json`;
    if (!adapterPaths.includes(adapterManifestPath)) {
        errors.push(`adapter inventory omits ${adapterManifestPath}`);
    }
    else if (existsSync(join(bundleRoot, adapterManifestPath))
        && !lstatSync(join(bundleRoot, adapterManifestPath)).isSymbolicLink()
        && lstatSync(join(bundleRoot, adapterManifestPath)).isFile()) {
        try {
            const adapter = readJsonFile(join(bundleRoot, adapterManifestPath));
            if (adapter.adapter.id !== lock.adapter.id
                || adapter.adapter.version !== lock.adapter.version
                || adapter.adapter.lifecycle !== lock.adapter.lifecycle) {
                errors.push('adapter lock identity disagrees with emitted manifest');
            }
            if (adapter.adapter.protocol_version !== lock.adapter_protocol_version
                || adapter.adapter.run_format_version !== lock.run_format_version) {
                errors.push('adapter protocol/run-format versions disagree with lock');
            }
            errors.push(...decodedAdapterForeignProblems(adapter, lock.adapter.id));
        }
        catch (error) {
            errors.push(`emitted adapter manifest is invalid JSON: ${error instanceof Error ? error.message : String(error)}`);
        }
    }
    errors.push(...adapterForeignProblems(bundleRoot, lock));
    if (errors.length === 0) {
        try {
            const boundary = emittedBoundaryReport(bundleRoot, lock);
            compareBoundaryDigests(boundary, lock, errors);
        }
        catch (error) {
            errors.push(error instanceof Error ? error.message : String(error));
        }
    }
    const lifecycle = lock.adapter.lifecycle;
    const verificationPassed = errors.length === 0;
    const summary = {
        id: lock.bundle.id,
        path: bundleRoot,
        lifecycle,
        preflight: verificationPassed && lifecycle !== 'planned'
            ? 'READY'
            : 'NOT-READY',
        coreDigest: lock.core.tree_digest,
        adapterDigest: lock.adapter.tree_digest,
        checkerDigest: lock.checker_digest,
        payloadDigest: lock.bundle.payload_digest,
        lockDigest: lock.lock_digest,
        bundleDigest: lock.bundle.digest,
        fileCount: lock.files.length,
    };
    return {
        result: verificationPassed ? 'PASS' : 'FAIL',
        bundlePath: bundleRoot,
        errors: sortedUnique(errors),
        summary,
    };
}
function compareEmittedCore(bundleRoots, reports) {
    if (bundleRoots.length !== 2 || reports.length !== 2) {
        throw new Error('release comparison requires both host bundles');
    }
    const locks = bundleRoots.map((root) => readJsonFile(join(root, 'bundle.lock.json')));
    const coreInventories = locks.map((lock) => (lock.files.filter((file) => file.classification === 'core')));
    if (canonicalJson(coreInventories[0]) !== canonicalJson(coreInventories[1])) {
        throw new Error('emitted Core inventories or file digests differ');
    }
    if (reports[0].summary?.coreDigest !== reports[1].summary?.coreDigest) {
        throw new Error('emitted Core tree digests differ');
    }
    for (const file of coreInventories[0]) {
        const left = readFileSync(join(bundleRoots[0], file.path));
        const right = readFileSync(join(bundleRoots[1], file.path));
        if (!left.equals(right)) {
            throw new Error(`emitted Core bytes differ at ${file.path}`);
        }
    }
}
export function verifyBundleSet(bundlePaths, expectedBundleIds = []) {
    const reports = bundlePaths.map((path) => verifyBundle(path));
    const errors = [];
    for (const report of reports) {
        errors.push(...report.errors.map((error) => `${report.bundlePath}: ${error}`));
    }
    if (expectedBundleIds.length > 0) {
        if (expectedBundleIds.length !== bundlePaths.length) {
            errors.push('expected bundle ID count must match the bundle path count');
        }
        else {
            for (const [index, expectedId] of expectedBundleIds.entries()) {
                const actualId = reports[index]?.summary?.id;
                if (actualId && actualId !== expectedId) {
                    errors.push(`${reports[index].bundlePath}: expected bundle ${expectedId}, found ${actualId}`);
                }
            }
        }
    }
    if (bundlePaths.length === 2 && reports.every((report) => (report.result === 'PASS' && report.summary))) {
        const pairs = reports
            .map((report) => ({
            report,
            path: report.bundlePath,
            id: report.summary?.id || '',
        }))
            .sort((left, right) => utf8Compare(left.id, right.id));
        if (!sameStrings(pairs.map((pair) => pair.id), ['aleph-for-loa', 'aleph-for-hermes'])) {
            errors.push('release verification requires exactly aleph-for-loa and aleph-for-hermes');
        }
        else {
            try {
                compareEmittedCore(pairs.map((pair) => pair.path), pairs.map((pair) => pair.report));
            }
            catch (error) {
                errors.push(error instanceof Error ? error.message : String(error));
            }
        }
    }
    else if (bundlePaths.length > 1) {
        errors.push('release verification accepts one bundle or exactly two host bundles');
    }
    return {
        result: errors.length ? 'FAIL' : 'PASS',
        bundles: reports,
        errors: sortedUnique(errors),
    };
}
export function verifyDefaultBundleOutput(outputRoot = DEFAULT_OUTPUT) {
    const paths = HOST_ADAPTER_IDS.map((id) => join(outputRoot, `aleph-for-${id}`));
    const expectedBundleIds = HOST_ADAPTER_IDS.map((id) => `aleph-for-${id}`);
    return verifyBundleSet(paths, expectedBundleIds);
}
function sourceStillMatches(root, snapshot, plans) {
    for (const [path, bytes] of snapshot) {
        const absolute = join(root, path);
        if (!existsSync(absolute) || !readFileSync(absolute).equals(bytes)) {
            throw new Error(`source changed during assembly: ${path}`);
        }
    }
    const refreshed = loadSource(root).plans;
    const before = plans.map((plan) => ({
        id: plan.target.id,
        lockDigest: plan.lockDigest,
        bundleDigest: plan.bundleDigest,
    }));
    const after = refreshed.map((plan) => ({
        id: plan.target.id,
        lockDigest: plan.lockDigest,
        bundleDigest: plan.bundleDigest,
    }));
    if (canonicalJson(before) !== canonicalJson(after)) {
        throw new Error('source dependency closure changed during assembly');
    }
}
export function assembleBundles(sourceRoot = REPO_ROOT, outputRoot = join(sourceRoot, '.aleph-bundles')) {
    const root = resolve(sourceRoot);
    const output = resolve(outputRoot);
    const errors = [];
    const bundles = [];
    let stageRoot = '';
    try {
        assertIgnoredOutput(root, output);
        const source = loadSource(root);
        const snapshot = sourceSnapshot(source.plans, root);
        mkdirSync(output, { recursive: true });
        stageRoot = mkdtempSync(join(output, '.assembly-'));
        const stagedRoots = [];
        for (const plan of source.plans) {
            const lock = createBundleLock(plan);
            stagedRoots.push(writeStagedBundle(stageRoot, plan, snapshot, lock));
        }
        const verification = stagedRoots.map((path) => verifyBundle(path));
        for (const report of verification) {
            if (report.result !== 'PASS' || !report.summary) {
                throw new Error(`staged verification failed for ${report.bundlePath}: ${report.errors.join('; ')}`);
            }
        }
        compareEmittedCore(stagedRoots, verification);
        sourceStillMatches(root, snapshot, source.plans);
        for (const [index, plan] of source.plans.entries()) {
            const destination = join(output, plan.target.id);
            rmSync(destination, { recursive: true, force: true });
            renameSync(stagedRoots[index], destination);
            const final = verifyBundle(destination);
            if (final.result !== 'PASS' || !final.summary) {
                throw new Error(`final verification failed for ${destination}: ${final.errors.join('; ')}`);
            }
            bundles.push(final.summary);
        }
        rmSync(stageRoot, { recursive: true, force: true });
        stageRoot = '';
    }
    catch (error) {
        errors.push(error instanceof Error ? error.message : String(error));
    }
    finally {
        if (stageRoot)
            rmSync(stageRoot, { recursive: true, force: true });
    }
    return {
        result: errors.length ? 'FAIL' : 'PASS',
        sourceRoot: root,
        outputRoot: output,
        bundles,
        errors,
    };
}
function printBundleSummary(prefix, summary) {
    console.log(`${prefix} ${summary.id} ${summary.path}`);
    console.log(`DIGEST core ${summary.coreDigest}`);
    console.log(`DIGEST adapter:${summary.id.replace('aleph-for-', '')} ${summary.adapterDigest}`);
    console.log(`DIGEST checker ${summary.checkerDigest}`);
    console.log(`DIGEST payload ${summary.payloadDigest}`);
    console.log(`DIGEST lock ${summary.lockDigest}`);
    console.log(`DIGEST bundle ${summary.bundleDigest}`);
    console.log(`PREFLIGHT ${summary.id.replace('aleph-for-', '')} ${summary.preflight} `
        + `lifecycle=${summary.lifecycle}`);
}
function main() {
    const options = parseCli(process.argv.slice(2));
    if (options.help) {
        console.log('Usage:\n'
            + '  node scripts/assemble-bundles.ts assemble '
            + '[--root <repo>] [--output <dir>] [--json]\n'
            + '  node scripts/assemble-bundles.ts verify '
            + '[--output <dir>] [--bundle <dir> ...] [--json]');
        return;
    }
    if (options.error || !options.command) {
        console.error(options.error || 'assemble or verify command is required');
        process.exitCode = 2;
        return;
    }
    if (options.command === 'assemble') {
        const report = assembleBundles(options.root, options.output);
        if (options.json)
            console.log(JSON.stringify(report, null, 2));
        else {
            for (const summary of report.bundles)
                printBundleSummary('ASSEMBLED', summary);
            for (const error of report.errors)
                console.error(`FAIL ${error}`);
            console.log(`RESULT: ${report.result}`);
        }
        process.exitCode = report.result === 'PASS' ? 0 : 1;
        return;
    }
    const explicitBundles = options.bundles.length > 0;
    const report = explicitBundles
        ? verifyBundleSet(options.bundles)
        : verifyDefaultBundleOutput(options.output);
    if (options.json)
        console.log(JSON.stringify(report, null, 2));
    else {
        for (const bundle of report.bundles) {
            const prefix = humanVerificationPrefix(bundle);
            if (prefix && bundle.summary) {
                printBundleSummary(prefix, bundle.summary);
            }
            for (const error of bundle.errors) {
                console.error(`FAIL ${bundle.bundlePath}: ${error}`);
            }
        }
        for (const error of report.errors)
            console.error(`FAIL ${error}`);
        console.log(`RESULT: ${report.result}`);
    }
    process.exitCode = report.result === 'PASS' ? 0 : 1;
}
if (resolve(process.argv[1] || '') === SCRIPT_PATH)
    main();
