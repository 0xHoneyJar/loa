import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { join, posix } from 'node:path';
export const BUNDLE_LOCK_FORMAT = 'aleph-bundle-lock/v1';
export const SOURCE_PROVENANCE_FORMAT = 'aleph-source-provenance/v1';
export const DIGEST_ALGORITHM = 'sha256-path-file-digest-v1';
export const ASSEMBLY_TOOL_PATH = 'scripts/assemble-bundles.ts';
export function isRecord(value) {
    return typeof value === 'object' && value !== null && !Array.isArray(value);
}
export function stringLeaves(value) {
    if (typeof value === 'string')
        return [value];
    if (Array.isArray(value))
        return value.flatMap(stringLeaves);
    if (isRecord(value)) {
        return Object.entries(value).flatMap(([key, item]) => [
            key,
            ...stringLeaves(item),
        ]);
    }
    return [];
}
export function utf8Compare(left, right) {
    return Buffer.compare(Buffer.from(left, 'utf8'), Buffer.from(right, 'utf8'));
}
export function sortedUnique(values) {
    return [...new Set(values)].sort(utf8Compare);
}
export function normalizedRepositoryPath(path) {
    if (!path || path.startsWith('/') || path.includes('\\') || path.includes('\0')) {
        return false;
    }
    if (path.split('/').includes('..'))
        return false;
    return posix.normalize(path) === path && path !== '.';
}
export function sha256Hex(value) {
    return createHash('sha256').update(value).digest('hex');
}
export function sha256Digest(value) {
    return `sha256:${sha256Hex(value)}`;
}
export function bareSha256(digest) {
    const match = /^sha256:([0-9a-f]{64})$/.exec(digest);
    if (!match)
        throw new Error(`invalid SHA-256 digest "${digest}"`);
    return match[1];
}
export function fileDigest(root, path) {
    return sha256Digest(readFileSync(join(root, path)));
}
export function digestEntries(entries) {
    const records = [...entries]
        .sort((left, right) => utf8Compare(left.path, right.path))
        .map(({ path, digest }) => `${path}\0${bareSha256(digest)}\n`)
        .join('');
    return sha256Digest(records);
}
export function treeDigest(root, paths) {
    return digestEntries(sortedUnique(paths).map((path) => ({ path, digest: fileDigest(root, path) })));
}
function canonicalJsonString(value) {
    let result = '"';
    for (let index = 0; index < value.length; index += 1) {
        const code = value.charCodeAt(index);
        if (code === 0x22)
            result += '\\"';
        else if (code === 0x5c)
            result += '\\\\';
        else if (code === 0x08)
            result += '\\b';
        else if (code === 0x09)
            result += '\\t';
        else if (code === 0x0a)
            result += '\\n';
        else if (code === 0x0c)
            result += '\\f';
        else if (code === 0x0d)
            result += '\\r';
        else if (code <= 0x1f)
            result += `\\u${code.toString(16).padStart(4, '0')}`;
        else if (code >= 0xd800 && code <= 0xdbff) {
            const next = value.charCodeAt(index + 1);
            if (next >= 0xdc00 && next <= 0xdfff) {
                result += value[index] + value[index + 1];
                index += 1;
            }
            else {
                throw new Error('canonical JSON forbids unpaired UTF-16 surrogates');
            }
        }
        else if (code >= 0xdc00 && code <= 0xdfff) {
            throw new Error('canonical JSON forbids unpaired UTF-16 surrogates');
        }
        else {
            result += value[index];
        }
    }
    return `${result}"`;
}
export function canonicalJson(value) {
    if (value === null)
        return 'null';
    if (typeof value === 'string')
        return canonicalJsonString(value);
    if (typeof value === 'boolean')
        return value ? 'true' : 'false';
    if (typeof value === 'number') {
        throw new Error('canonical JSON forbids numbers');
    }
    if (Array.isArray(value))
        return `[${value.map(canonicalJson).join(',')}]`;
    if (!isRecord(value)) {
        throw new Error(`canonical JSON cannot serialize ${typeof value}`);
    }
    return `{${Object.keys(value)
        .sort(utf8Compare)
        .map((key) => `${canonicalJsonString(key)}:${canonicalJson(value[key])}`)
        .join(',')}}`;
}
export function canonicalJsonBytes(value) {
    return Buffer.from(`${canonicalJson(value)}\n`, 'utf8');
}
function payloadSet(manifest, target) {
    return new Set([
        ...manifest.files.core,
        ...(manifest.files.adapter[target.adapter_id] || []),
    ]);
}
export function selectedManifestProjection(manifest, target) {
    const selected = payloadSet(manifest, target);
    return {
        manifest_format: manifest.manifest_format,
        core: { ...manifest.core },
        manual_execution_binding: {
            ...manifest.manual_execution_binding,
            paths: sortedUnique(manifest.manual_execution_binding.paths),
        },
        files: {
            core: sortedUnique(manifest.files.core),
            adapter: {
                [target.adapter_id]: sortedUnique(manifest.files.adapter[target.adapter_id] || []),
            },
            packaging: ['core.manifest.json'],
            repository_administration: [],
        },
        checker_paths: sortedUnique(manifest.checker_paths),
        reference_documents: sortedUnique(manifest.reference_documents.filter((path) => selected.has(path))),
        bundle_targets: [{ ...target }],
    };
}
function fileRecords(root, manifest, target) {
    const core = manifest.files.core.map((path) => ({
        path,
        classification: 'core',
        digest: fileDigest(root, path),
    }));
    const adapter = (manifest.files.adapter[target.adapter_id] || [])
        .map((path) => ({
        path,
        classification: 'adapter',
        digest: fileDigest(root, path),
    }));
    return [...core, ...adapter]
        .sort((left, right) => utf8Compare(left.path, right.path));
}
export function lockIdentityProjection(lock) {
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
        source: {
            manifest_projection: lock.source.manifest_projection,
            manifest_projection_digest: lock.source.manifest_projection_digest,
            assembly_tool: { ...lock.source.assembly_tool },
        },
        provenance: structuredClone(lock.provenance),
        files: lock.files.map((file) => ({ ...file })),
    };
}
export function provenanceDigest(vcs) {
    return sha256Digest(canonicalJsonBytes(vcs));
}
export function resealBundleLock(lock) {
    const sealed = structuredClone(lock);
    sealed.source.manifest_projection_digest = sha256Digest(canonicalJsonBytes(sealed.source.manifest_projection));
    sealed.provenance.digest = provenanceDigest(sealed.provenance.vcs);
    sealed.lock_digest = sha256Digest(canonicalJsonBytes(lockIdentityProjection(sealed)));
    sealed.bundle.digest = digestEntries([
        ...sealed.files,
        { path: 'bundle.lock.json', digest: sealed.lock_digest },
    ]);
    return sealed;
}
export function buildBundlePlan(root, manifest, target, adapter, provenanceOverride) {
    const adapterPaths = manifest.files.adapter[target.adapter_id] || [];
    const payloadPaths = sortedUnique([...manifest.files.core, ...adapterPaths]);
    const files = fileRecords(root, manifest, target);
    const coreDigest = digestEntries(files.filter((file) => file.classification === 'core'));
    const adapterDigest = digestEntries(files.filter((file) => file.classification === 'adapter'));
    const checkerPathSet = new Set(manifest.checker_paths);
    const checkerFiles = files.filter((file) => checkerPathSet.has(file.path));
    const checkerDigest = digestEntries(checkerFiles);
    const payloadDigest = digestEntries(files);
    const manifestProjection = selectedManifestProjection(manifest, target);
    const source = {
        manifest_projection: manifestProjection,
        manifest_projection_digest: sha256Digest(canonicalJsonBytes(manifestProjection)),
        assembly_tool: {
            path: ASSEMBLY_TOOL_PATH,
            digest: fileDigest(root, ASSEMBLY_TOOL_PATH),
        },
    };
    const provenance = provenanceOverride
        ? structuredClone(provenanceOverride)
        : resolvedSourceProvenance(root, payloadPaths);
    const identity = {
        lock_format: BUNDLE_LOCK_FORMAT,
        digest_algorithm: DIGEST_ALGORITHM,
        bundle: {
            id: target.id,
            version: target.version,
            payload_digest: payloadDigest,
        },
        core: {
            id: manifest.core.id,
            version: manifest.core.version,
            tree_digest: coreDigest,
        },
        adapter: {
            id: adapter.adapter.id,
            version: adapter.adapter.version,
            lifecycle: adapter.adapter.lifecycle,
            tree_digest: adapterDigest,
        },
        checker_digest: checkerDigest,
        adapter_protocol_version: manifest.core.adapter_protocol_version,
        run_format_version: manifest.core.run_format_version,
        source,
        provenance,
        files,
    };
    const lockDigest = sha256Digest(canonicalJsonBytes(identity));
    const bundleDigest = digestEntries([
        ...files,
        { path: 'bundle.lock.json', digest: lockDigest },
    ]);
    return {
        target,
        payloadPaths,
        files,
        manifestProjection,
        payloadDigest,
        coreDigest,
        adapterDigest,
        checkerDigest,
        lockDigest,
        bundleDigest,
        identity,
    };
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
    return result.stdout.trim();
}
function runGitBuffer(root, args) {
    const result = spawnSync('git', ['-C', root, ...args], {
        encoding: 'buffer',
        maxBuffer: 32 * 1024 * 1024,
    });
    if (result.status !== 0) {
        throw new Error(`git ${args.join(' ')} failed: ${result.stderr.toString('utf8').trim()
            || result.error?.message
            || `status ${String(result.status)}`}`);
    }
    return result.stdout;
}
export function gitCommitObjectId(vcs) {
    const bytes = Buffer.from(vcs.commit_object, 'base64');
    const header = Buffer.from(`commit ${bytes.length}\0`, 'utf8');
    return createHash(vcs.object_format).update(header).update(bytes).digest('hex');
}
export function gitCommitTree(vcs) {
    const bytes = Buffer.from(vcs.commit_object, 'base64');
    const firstLineEnd = bytes.indexOf(0x0a);
    const firstLine = bytes
        .subarray(0, firstLineEnd >= 0 ? firstLineEnd : bytes.length)
        .toString('ascii');
    const match = /^tree ([0-9a-f]+)$/.exec(firstLine);
    return match?.[1] || '';
}
export function resolvedSourceProvenance(root, dependencyPaths) {
    const objectFormat = runGit(root, ['rev-parse', '--show-object-format']);
    if (objectFormat !== 'sha1' && objectFormat !== 'sha256') {
        throw new Error(`unsupported Git object format "${objectFormat}"`);
    }
    let commit = runGit(root, [
        '--literal-pathspecs',
        'log',
        '-1',
        '--format=%H',
        '--',
        ...sortedUnique(dependencyPaths),
    ]);
    if (!commit) {
        const roots = runGit(root, ['rev-list', '--max-parents=0', 'HEAD'])
            .split('\n')
            .filter(Boolean)
            .sort(utf8Compare);
        commit = roots[0] || '';
    }
    const commitTree = runGit(root, [
        'rev-parse',
        '--verify',
        `${commit}^{tree}`,
    ]);
    const commitObject = runGitBuffer(root, ['cat-file', 'commit', commit]);
    const expectedLength = objectFormat === 'sha1' ? 40 : 64;
    const objectPattern = new RegExp(`^[0-9a-f]{${expectedLength}}$`);
    if (!objectPattern.test(commit) || /^0+$/.test(commit)) {
        throw new Error('source commit is unresolved or malformed');
    }
    if (!objectPattern.test(commitTree) || /^0+$/.test(commitTree)) {
        throw new Error('source commit tree is unresolved or malformed');
    }
    const status = runGit(root, [
        '--literal-pathspecs',
        'status',
        '--porcelain=v1',
        '--untracked-files=all',
        '--',
        ...sortedUnique(dependencyPaths),
    ]);
    const vcs = {
        kind: 'git-dependency-closure-snapshot',
        object_format: objectFormat,
        commit,
        commit_object: commitObject.toString('base64'),
        commit_tree: commitTree,
        resolved: true,
        mutable_ref: null,
        worktree_state: status ? 'modified' : 'clean',
    };
    return {
        format: SOURCE_PROVENANCE_FORMAT,
        vcs,
        digest: provenanceDigest(vcs),
    };
}
export function createBundleLock(plan) {
    return resealBundleLock({
        lock_format: BUNDLE_LOCK_FORMAT,
        digest_algorithm: DIGEST_ALGORITHM,
        lock_digest: plan.lockDigest,
        bundle: {
            id: plan.target.id,
            version: plan.target.version,
            payload_digest: plan.payloadDigest,
            digest: plan.bundleDigest,
        },
        core: { ...plan.identity.core },
        adapter: { ...plan.identity.adapter },
        checker_digest: plan.checkerDigest,
        adapter_protocol_version: plan.identity.adapter_protocol_version,
        run_format_version: plan.identity.run_format_version,
        source: structuredClone(plan.identity.source),
        provenance: structuredClone(plan.identity.provenance),
        files: plan.files.map((file) => ({ ...file })),
    });
}
export function bundleLockBytes(lock) {
    return canonicalJsonBytes(lock);
}
export function readJsonFile(path) {
    return JSON.parse(readFileSync(path, 'utf8'));
}
