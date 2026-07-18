#!/usr/bin/env node
var __rewriteRelativeImportExtension = (this && this.__rewriteRelativeImportExtension) || function (path, preserveJsx) {
    if (typeof path === "string" && /^\.\.?\//.test(path)) {
        return path.replace(/\.(tsx)$|((?:\.d)?)((?:\.[^./]+?)?)\.([cm]?)ts$/i, function (m, tsx, d, ext, cm) {
            return tsx ? preserveJsx ? ".jsx" : ".js" : d && (!ext || !cm) ? m : (d + ext + "." + cm.toLowerCase() + "js");
        });
    }
    return path;
};
import { createHash } from 'node:crypto';
import { closeSync, constants, existsSync, fstatSync, lstatSync, openSync, readFileSync, readdirSync, } from 'node:fs';
import { isAbsolute, join, relative, resolve, } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const RECORD_PATH = '.claude/aleph/install.lock.json';
const TRANSACTION_PATH = '.claude/aleph-install.transaction';
const ALEPH_ROOT = '.claude/aleph';
const SKILL_ROOT = '.claude/skills/loa-aleph';
const RUNTIME_ROOT = '.claude/aleph/runtime/bundle';
const BUNDLE_LOCK_DESTINATION = `${RUNTIME_ROOT}/bundle.lock.json`;
const INSTALL_MAP_SOURCE = 'adapters/loa/installation.map.json';
const INSTALL_MAP_DESTINATION = `${RUNTIME_ROOT}/${INSTALL_MAP_SOURCE}`;
const CLI_SOURCE = 'runtime-js/adapters/loa/src/cli.js';
const CLI_DESTINATION = `${RUNTIME_ROOT}/${CLI_SOURCE}`;
const SHA256 = /^sha256:[0-9a-f]{64}$/u;
const EXPECTED_EXPOSURES = [
    {
        id: 'command',
        source: 'adapters/loa/command/loa-aleph.md',
        destination: '.claude/commands/loa-aleph.md',
    },
    {
        id: 'skill',
        source: 'adapters/loa/skill/loa-aleph/SKILL.md',
        destination: `${SKILL_ROOT}/SKILL.md`,
    },
    {
        id: 'launcher',
        source: 'runtime-js/adapters/loa/src/launcher.js',
        destination: `${ALEPH_ROOT}/bin/loa-aleph.mjs`,
    },
];
function utf8Compare(left, right) {
    return Buffer.compare(Buffer.from(left, 'utf8'), Buffer.from(right, 'utf8'));
}
function canonicalJson(value) {
    if (value === null || typeof value === 'boolean')
        return JSON.stringify(value);
    if (typeof value === 'string')
        return JSON.stringify(value);
    if (Array.isArray(value))
        return `[${value.map(canonicalJson).join(',')}]`;
    if (typeof value === 'object') {
        const record = value;
        return `{${Object.keys(record).sort(utf8Compare).map((key) => (`${JSON.stringify(key)}:${canonicalJson(record[key])}`)).join(',')}}`;
    }
    throw new Error(`installation receipt contains unsupported ${typeof value}`);
}
function digest(bytes) {
    return `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
}
function exactKeys(value, keys) {
    return Boolean(value) && typeof value === 'object' && !Array.isArray(value)
        && canonicalJson(Object.keys(value).sort(utf8Compare))
            === canonicalJson([...keys].sort(utf8Compare));
}
function safeRepositoryPath(path) {
    return typeof path === 'string'
        && Boolean(path)
        && !isAbsolute(path)
        && !path.includes('\\')
        && !path.includes('\0')
        && path.split('/').every((part) => Boolean(part) && part !== '.' && part !== '..');
}
function sameStrings(left, right) {
    const a = [...new Set(left)].sort(utf8Compare);
    const b = [...new Set(right)].sort(utf8Compare);
    return a.length === b.length && a.every((value, index) => value === b[index]);
}
function digestEntries(entries) {
    const records = [...entries]
        .sort((left, right) => utf8Compare(left.path, right.path))
        .map(({ path, digest: value }) => {
        const match = /^sha256:([0-9a-f]{64})$/u.exec(value);
        if (!match)
            throw new Error(`managed digest is malformed for ${path}`);
        return `${path}\0${match[1]}\n`;
    })
        .join('');
    return digest(records);
}
function canonicalBytes(value) {
    return Buffer.from(`${canonicalJson(value)}\n`, 'utf8');
}
function safeManagedPath(root, repositoryPath) {
    if (!safeRepositoryPath(repositoryPath)) {
        throw new Error(`installation receipt contains unsafe path ${repositoryPath}`);
    }
    if (existsSync(root)) {
        const rootStat = lstatSync(root);
        if (rootStat.isSymbolicLink() || !rootStat.isDirectory()) {
            throw new Error('Loa installation root is not a real directory');
        }
    }
    const absolute = resolve(root, repositoryPath);
    const rel = relative(root, absolute);
    if (rel === '' || rel.startsWith('..') || isAbsolute(rel)) {
        throw new Error(`installation path escapes the Loa root: ${repositoryPath}`);
    }
    let current = root;
    for (const part of repositoryPath.split('/')) {
        current = join(current, part);
        if (existsSync(current) && lstatSync(current).isSymbolicLink()) {
            throw new Error(`installation path is symlinked: ${repositoryPath}`);
        }
    }
    return absolute;
}
function readRegularFile(path) {
    const descriptor = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW);
    try {
        if (!fstatSync(descriptor).isFile()) {
            throw new Error(`installed path is not a regular file: ${path}`);
        }
        return readFileSync(descriptor);
    }
    finally {
        closeSync(descriptor);
    }
}
function readCanonicalObject(path, label) {
    const raw = readRegularFile(path);
    const parsed = JSON.parse(raw.toString('utf8'));
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
        throw new Error(`${label} is malformed`);
    }
    if (!raw.equals(canonicalBytes(parsed))) {
        throw new Error(`${label} is not canonical JSON plus one LF`);
    }
    return { raw, value: parsed };
}
function recursiveFiles(root, prefix) {
    if (!existsSync(root))
        return [];
    const rootStat = lstatSync(root);
    if (rootStat.isSymbolicLink() || !rootStat.isDirectory()) {
        throw new Error(`managed root is unsafe: ${prefix}`);
    }
    const files = [];
    function visit(directory, relativePrefix) {
        for (const entry of readdirSync(directory, { withFileTypes: true })
            .sort((left, right) => utf8Compare(left.name, right.name))) {
            const relativePath = relativePrefix
                ? `${relativePrefix}/${entry.name}`
                : entry.name;
            const absolute = join(directory, entry.name);
            const stat = lstatSync(absolute);
            if (stat.isSymbolicLink()) {
                throw new Error(`managed tree contains a symlink: ${prefix}/${relativePath}`);
            }
            if (stat.isDirectory())
                visit(absolute, relativePath);
            else if (stat.isFile())
                files.push(`${prefix}/${relativePath}`);
            else
                throw new Error(`managed tree contains a non-file: ${prefix}/${relativePath}`);
        }
    }
    visit(root, '');
    return files.sort(utf8Compare);
}
function managedDiskInventory(root) {
    const files = [
        ...recursiveFiles(join(root, ALEPH_ROOT), ALEPH_ROOT),
        ...recursiveFiles(join(root, SKILL_ROOT), SKILL_ROOT),
    ];
    const commands = join(root, '.claude/commands');
    if (existsSync(commands)) {
        const stat = lstatSync(commands);
        if (stat.isSymbolicLink() || !stat.isDirectory()) {
            throw new Error('Loa commands root is unsafe');
        }
        for (const entry of readdirSync(commands, { withFileTypes: true })) {
            if (!entry.name.startsWith('loa-aleph'))
                continue;
            const path = `.claude/commands/${entry.name}`;
            const entryStat = lstatSync(join(commands, entry.name));
            if (entryStat.isSymbolicLink() || !entryStat.isFile()) {
                throw new Error(`managed command path is unsafe: ${path}`);
            }
            files.push(path);
        }
    }
    return [...new Set(files)].sort(utf8Compare);
}
function bundleLockIdentity(lock) {
    return {
        lock_format: lock.lock_format,
        digest_algorithm: lock.digest_algorithm,
        bundle: {
            id: lock.bundle.id,
            version: lock.bundle.version,
            payload_digest: lock.bundle.payload_digest,
        },
        core: { ...lock.core },
        adapter: { ...lock.adapter },
        checker_digest: lock.checker_digest,
        adapter_protocol_version: lock.adapter_protocol_version,
        run_format_version: lock.run_format_version,
        source: structuredClone(lock.source),
        provenance: structuredClone(lock.provenance),
        files: lock.files.map((file) => ({ ...file })),
    };
}
function parseBundleLock(value) {
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
    ]))
        throw new Error('installed bundle lock keys are malformed');
    const lock = value;
    if (lock.lock_format !== 'aleph-bundle-lock/v1'
        || lock.digest_algorithm !== 'sha256-path-file-digest-v1'
        || !exactKeys(lock.bundle, ['id', 'version', 'payload_digest', 'digest'])
        || !exactKeys(lock.core, ['id', 'version', 'tree_digest'])
        || !exactKeys(lock.adapter, ['id', 'version', 'lifecycle', 'tree_digest'])
        || !exactKeys(lock.source, [
            'manifest_projection', 'manifest_projection_digest', 'assembly_tool',
        ])
        || !exactKeys(lock.source.assembly_tool, ['path', 'digest'])
        || !exactKeys(lock.provenance, ['format', 'vcs', 'digest'])
        || lock.bundle.id !== 'aleph-for-loa'
        || lock.adapter.id !== 'loa'
        || !['implemented', 'validated', 'sanctioned'].includes(lock.adapter.lifecycle)) {
        throw new Error('installed bundle lock identity is invalid');
    }
    const digests = [
        lock.lock_digest,
        lock.bundle.payload_digest,
        lock.bundle.digest,
        lock.core.tree_digest,
        lock.adapter.tree_digest,
        lock.checker_digest,
        lock.source.manifest_projection_digest,
        lock.source.assembly_tool.digest,
        lock.provenance.digest,
    ];
    if (digests.some((value) => !SHA256.test(value))) {
        throw new Error('installed bundle lock contains a malformed digest');
    }
    if (!Array.isArray(lock.files) || lock.files.length === 0) {
        throw new Error('installed bundle lock has no file inventory');
    }
    const paths = [];
    for (const [index, file] of lock.files.entries()) {
        if (!exactKeys(file, ['path', 'classification', 'digest'])
            || !safeRepositoryPath(file.path)
            || (file.classification !== 'core' && file.classification !== 'adapter')
            || !SHA256.test(file.digest)) {
            throw new Error(`installed bundle lock file ${String(index)} is malformed`);
        }
        paths.push(file.path);
    }
    if (new Set(paths).size !== paths.length
        || canonicalJson(paths) !== canonicalJson([...paths].sort(utf8Compare))) {
        throw new Error('installed bundle lock paths are duplicate or unordered');
    }
    const projectedFiles = lock.source.manifest_projection.files;
    const projectedAdapters = projectedFiles && typeof projectedFiles === 'object'
        && !Array.isArray(projectedFiles)
        ? projectedFiles.adapter
        : null;
    const projectedCore = projectedFiles && typeof projectedFiles === 'object'
        && !Array.isArray(projectedFiles)
        ? projectedFiles.core
        : null;
    const projectedLoa = projectedAdapters && typeof projectedAdapters === 'object'
        && !Array.isArray(projectedAdapters)
        ? projectedAdapters.loa
        : null;
    const lockedCore = lock.files
        .filter((file) => file.classification === 'core')
        .map((file) => file.path);
    const lockedAdapter = lock.files
        .filter((file) => file.classification === 'adapter')
        .map((file) => file.path);
    const projectedTargets = lock.source.manifest_projection.bundle_targets;
    const projectedTarget = Array.isArray(projectedTargets)
        ? projectedTargets[0]
        : null;
    if (!Array.isArray(projectedCore)
        || !projectedCore.every((path) => typeof path === 'string')
        || !Array.isArray(projectedLoa)
        || !projectedLoa.every((path) => typeof path === 'string')
        || canonicalJson(projectedCore) !== canonicalJson(lockedCore)
        || canonicalJson(projectedLoa) !== canonicalJson(lockedAdapter)
        || !projectedAdapters
        || typeof projectedAdapters !== 'object'
        || Array.isArray(projectedAdapters)
        || canonicalJson(Object.keys(projectedAdapters))
            !== canonicalJson(['loa'])
        || !Array.isArray(projectedTargets)
        || projectedTargets.length !== 1
        || !projectedTarget
        || typeof projectedTarget !== 'object'
        || Array.isArray(projectedTarget)
        || projectedTarget.id !== lock.bundle.id
        || projectedTarget.adapter_id !== lock.adapter.id
        || projectedTarget.version !== lock.bundle.version) {
        throw new Error('installed bundle lock inventory disagrees with its manifest projection');
    }
    if (digestEntries(lock.files) !== lock.bundle.payload_digest
        || digestEntries(lock.files.filter((file) => file.classification === 'core'))
            !== lock.core.tree_digest
        || digestEntries(lock.files.filter((file) => file.classification === 'adapter'))
            !== lock.adapter.tree_digest) {
        throw new Error('installed bundle inventory digest mismatch');
    }
    const checkerPaths = lock.source.manifest_projection.checker_paths;
    if (!Array.isArray(checkerPaths)
        || !checkerPaths.every((path) => typeof path === 'string' && paths.includes(path))) {
        throw new Error('installed bundle checker inventory is malformed');
    }
    const checkerSet = new Set(checkerPaths);
    if (digestEntries(lock.files.filter((file) => checkerSet.has(file.path)))
        !== lock.checker_digest) {
        throw new Error('installed bundle checker digest mismatch');
    }
    if (digest(canonicalBytes(lock.source.manifest_projection))
        !== lock.source.manifest_projection_digest
        || digest(canonicalBytes(lock.provenance.vcs)) !== lock.provenance.digest
        || digest(canonicalBytes(bundleLockIdentity(lock))) !== lock.lock_digest
        || digestEntries([
            ...lock.files,
            { path: 'bundle.lock.json', digest: lock.lock_digest },
        ]) !== lock.bundle.digest) {
        throw new Error('installed bundle lock digest mismatch');
    }
    return lock;
}
function parseInstallationMap(value) {
    if (!exactKeys(value, ['format', 'runtime_root', 'record_path', 'exposures'])) {
        throw new Error('installed Loa installation map keys are malformed');
    }
    const map = value;
    if (map.format !== 'aleph-loa-installation-map/v1'
        || map.runtime_root !== RUNTIME_ROOT
        || map.record_path !== RECORD_PATH
        || !Array.isArray(map.exposures)
        || map.exposures.some((exposure) => !exactKeys(exposure, ['id', 'source', 'destination']))
        || canonicalJson(map.exposures) !== canonicalJson(EXPECTED_EXPOSURES)) {
        throw new Error('installed Loa installation map is invalid');
    }
    return map;
}
function parseInstallReceipt(value) {
    if (!exactKeys(value, [
        'format',
        'digest_algorithm',
        'install_digest',
        'bundle',
        'core',
        'adapter',
        'checker_digest',
        'adapter_protocol_version',
        'run_format_version',
        'layout',
        'managed_tree_digest',
        'files',
    ]))
        throw new Error('Loa Aleph installation receipt keys are malformed');
    const receipt = value;
    if (receipt.format !== 'aleph-loa-install-lock/v1'
        || receipt.digest_algorithm !== 'sha256-path-file-digest-v1'
        || !exactKeys(receipt.bundle, [
            'id', 'version', 'payload_digest', 'lock_digest', 'digest', 'lock_file_digest',
        ])
        || !exactKeys(receipt.core, ['id', 'version', 'tree_digest'])
        || !exactKeys(receipt.adapter, ['id', 'version', 'lifecycle', 'tree_digest'])
        || !exactKeys(receipt.layout, [
            'map_format', 'map_digest', 'runtime_root', 'record_path',
        ])
        || receipt.bundle?.id !== 'aleph-for-loa'
        || receipt.adapter?.id !== 'loa'
        || receipt.adapter.lifecycle === 'planned'
        || receipt.layout?.runtime_root !== RUNTIME_ROOT
        || receipt.layout?.record_path !== RECORD_PATH
        || !Array.isArray(receipt.files)
        || !SHA256.test(receipt.install_digest)
        || !SHA256.test(receipt.managed_tree_digest)
        || [
            receipt.bundle.payload_digest,
            receipt.bundle.lock_digest,
            receipt.bundle.digest,
            receipt.bundle.lock_file_digest,
            receipt.core.tree_digest,
            receipt.adapter.tree_digest,
            receipt.checker_digest,
            receipt.layout.map_digest,
        ].some((item) => !SHA256.test(item))) {
        throw new Error('Loa Aleph installation identity is invalid');
    }
    const destinations = [];
    for (const file of receipt.files) {
        if (!exactKeys(file, [
            'kind', 'classification', 'source_path', 'destination_path', 'digest',
        ])
            || (file.kind !== 'runtime' && file.kind !== 'exposure')
            || !safeRepositoryPath(file.source_path)
            || !safeRepositoryPath(file.destination_path)
            || !SHA256.test(file.digest)) {
            throw new Error('Loa Aleph managed-file receipt is malformed');
        }
        destinations.push(file.destination_path);
    }
    if (new Set(destinations).size !== destinations.length
        || canonicalJson(destinations)
            !== canonicalJson([...destinations].sort(utf8Compare))) {
        throw new Error('Loa Aleph managed-file receipt paths are duplicate or unordered');
    }
    const projection = structuredClone(receipt);
    delete projection.install_digest;
    if (digest(canonicalBytes(projection)) !== receipt.install_digest
        || digestEntries(receipt.files.map((file) => ({
            path: file.destination_path,
            digest: file.digest,
        }))) !== receipt.managed_tree_digest) {
        throw new Error('Loa Aleph installation receipt digest mismatch');
    }
    return receipt;
}
export function verifyInstalledLauncherRuntime(loaRoot) {
    const root = resolve(loaRoot);
    const transaction = safeManagedPath(root, TRANSACTION_PATH);
    if (existsSync(transaction)) {
        throw new Error('Loa Aleph installation has an active recovery transaction');
    }
    const recordPath = safeManagedPath(root, RECORD_PATH);
    if (!existsSync(recordPath) || !lstatSync(recordPath).isFile()) {
        throw new Error('Loa Aleph installation receipt is missing');
    }
    const receiptObject = readCanonicalObject(recordPath, 'Loa Aleph installation receipt');
    const receipt = parseInstallReceipt(receiptObject.value);
    const bundleLockPath = safeManagedPath(root, BUNDLE_LOCK_DESTINATION);
    const bundleLockObject = readCanonicalObject(bundleLockPath, 'installed bundle lock');
    const bundleLock = parseBundleLock(bundleLockObject.value);
    const expectedIdentity = {
        bundle: {
            id: bundleLock.bundle.id,
            version: bundleLock.bundle.version,
            payload_digest: bundleLock.bundle.payload_digest,
            lock_digest: bundleLock.lock_digest,
            digest: bundleLock.bundle.digest,
            lock_file_digest: digest(bundleLockObject.raw),
        },
        core: bundleLock.core,
        adapter: bundleLock.adapter,
        checker_digest: bundleLock.checker_digest,
        adapter_protocol_version: bundleLock.adapter_protocol_version,
        run_format_version: bundleLock.run_format_version,
    };
    const actualIdentity = {
        bundle: receipt.bundle,
        core: receipt.core,
        adapter: receipt.adapter,
        checker_digest: receipt.checker_digest,
        adapter_protocol_version: receipt.adapter_protocol_version,
        run_format_version: receipt.run_format_version,
    };
    if (canonicalJson(actualIdentity) !== canonicalJson(expectedIdentity)) {
        throw new Error('Loa Aleph receipt disagrees with the exact installed bundle identity');
    }
    const files = new Map(bundleLock.files.map((file) => [file.path, file]));
    const mapRecord = files.get(INSTALL_MAP_SOURCE);
    if (!mapRecord || mapRecord.classification !== 'adapter') {
        throw new Error('installed bundle does not contain its adapter-owned installation map');
    }
    const mapBytes = readRegularFile(safeManagedPath(root, INSTALL_MAP_DESTINATION));
    if (digest(mapBytes) !== mapRecord.digest
        || receipt.layout.map_digest !== mapRecord.digest
        || receipt.layout.map_format !== 'aleph-loa-installation-map/v1') {
        throw new Error('installed Loa installation map digest mismatch');
    }
    const map = parseInstallationMap(JSON.parse(mapBytes.toString('utf8')));
    const expected = bundleLock.files.map((file) => ({
        kind: 'runtime',
        classification: file.classification,
        source_path: file.path,
        destination_path: `${RUNTIME_ROOT}/${file.path}`,
        digest: file.digest,
    }));
    expected.push({
        kind: 'runtime',
        classification: 'lock',
        source_path: 'bundle.lock.json',
        destination_path: BUNDLE_LOCK_DESTINATION,
        digest: digest(bundleLockObject.raw),
    });
    for (const exposure of map.exposures) {
        const source = files.get(exposure.source);
        if (!source || source.classification !== 'adapter') {
            throw new Error(`installed exposure source is not adapter-owned: ${exposure.source}`);
        }
        expected.push({
            kind: 'exposure',
            classification: 'adapter',
            source_path: exposure.source,
            destination_path: exposure.destination,
            digest: source.digest,
        });
    }
    const sortFiles = (items) => [...items].sort((left, right) => utf8Compare(left.destination_path, right.destination_path));
    const exactExpected = sortFiles(expected);
    if (canonicalJson(receipt.files) !== canonicalJson(exactExpected)) {
        throw new Error('Loa Aleph receipt does not cover the exact bundle and installation map');
    }
    for (const file of exactExpected) {
        const absolute = safeManagedPath(root, file.destination_path);
        if (!existsSync(absolute) || !lstatSync(absolute).isFile()) {
            throw new Error(`Loa Aleph managed file is missing: ${file.destination_path}`);
        }
        if (digest(readRegularFile(absolute)) !== file.digest) {
            throw new Error(`Loa Aleph managed file is tampered: ${file.destination_path}`);
        }
    }
    const expectedRuntime = bundleLock.files.map((file) => (`${RUNTIME_ROOT}/${file.path}`));
    expectedRuntime.push(BUNDLE_LOCK_DESTINATION);
    const actualRuntime = recursiveFiles(join(root, RUNTIME_ROOT), RUNTIME_ROOT);
    if (!sameStrings(expectedRuntime, actualRuntime)) {
        throw new Error('installed Loa runtime inventory disagrees with its bundle lock');
    }
    const expectedDisk = [...exactExpected.map((file) => file.destination_path), RECORD_PATH];
    if (!sameStrings(expectedDisk, managedDiskInventory(root))) {
        throw new Error('installed Loa managed inventory is incomplete or contains extra paths');
    }
    const cli = exactExpected.find((file) => (file.kind === 'runtime'
        && file.classification === 'adapter'
        && file.source_path === CLI_SOURCE
        && file.destination_path === CLI_DESTINATION));
    if (!cli)
        throw new Error('verified Loa Aleph runtime does not contain its CLI');
    return safeManagedPath(root, cli.destination_path);
}
export async function runInstalledLauncher(loaRoot, argv) {
    const selected = verifyInstalledLauncherRuntime(loaRoot);
    const module = await import(__rewriteRelativeImportExtension(pathToFileURL(selected).href));
    return module.runLoaCli(argv);
}
async function main() {
    return runInstalledLauncher(process.cwd(), process.argv.slice(2));
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
    main().then((status) => { process.exitCode = status; }, (error) => {
        console.error(`ERROR ${error instanceof Error ? error.message : String(error)}`);
        process.exitCode = 1;
    });
}
