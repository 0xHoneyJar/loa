import { join, resolve } from 'node:path';
import { verifyBundle, } from '../../../scripts/assemble-bundles.js';
import { resealBundleLock, } from '../../../scripts/lib/bundle-format.js';
import { LOA_ADAPTER_ID, LOA_BUNDLE_ID, } from './types.js';
import { assertSafeRelativePath, readStableRegularFile, sha256Digest, stableJsonBytes, utf8Compare, } from './fs.js';
function parseBundleLock(bytes) {
    let value;
    try {
        value = JSON.parse(bytes.toString('utf8'));
    }
    catch (error) {
        throw new Error(`bundle lock is invalid JSON: ${error instanceof Error ? error.message : String(error)}`);
    }
    if (typeof value !== 'object' || value === null || Array.isArray(value)) {
        throw new Error('bundle lock must be an object');
    }
    return value;
}
export function verifyAndLoadLoaBundle(bundleRoot) {
    const root = resolve(bundleRoot);
    const report = verifyBundle(root);
    if (report.result !== 'PASS' || !report.summary) {
        throw new Error(`bundle verification failed: ${report.errors.join('; ') || 'unknown failure'}`);
    }
    if (report.summary.id !== LOA_BUNDLE_ID) {
        throw new Error(`expected bundle ${LOA_BUNDLE_ID}, found ${report.summary.id}`);
    }
    const lockPath = join(root, 'bundle.lock.json');
    const lockBytes = readStableRegularFile(lockPath).bytes;
    const lock = parseBundleLock(lockBytes);
    if (!lockBytes.equals(stableJsonBytes(lock))) {
        throw new Error('bundle lock changed or is not canonical after verification');
    }
    const resealed = resealBundleLock(lock);
    if (resealed.lock_digest !== lock.lock_digest
        || resealed.bundle.digest !== lock.bundle.digest) {
        throw new Error('stable bundle lock does not reproduce its sealed identity');
    }
    if (report.summary.id !== lock.bundle.id
        || report.summary.lifecycle !== lock.adapter.lifecycle
        || report.summary.coreDigest !== lock.core.tree_digest
        || report.summary.adapterDigest !== lock.adapter.tree_digest
        || report.summary.checkerDigest !== lock.checker_digest
        || report.summary.payloadDigest !== lock.bundle.payload_digest
        || report.summary.lockDigest !== lock.lock_digest
        || report.summary.bundleDigest !== lock.bundle.digest
        || report.summary.fileCount !== lock.files.length) {
        throw new Error('stable bundle lock does not match the verified bundle identity');
    }
    if (lock.bundle.id !== LOA_BUNDLE_ID || lock.adapter.id !== LOA_ADAPTER_ID) {
        throw new Error('bundle lock does not select the Loa adapter');
    }
    if (lock.adapter.lifecycle === 'planned') {
        throw new Error('planned adapter bundle is not executable');
    }
    const files = new Map();
    const fileBytes = new Map();
    for (const file of [...lock.files].sort((left, right) => utf8Compare(left.path, right.path))) {
        if (files.has(file.path))
            throw new Error(`duplicate locked bundle path: ${file.path}`);
        const bytes = readStableRegularFile(join(root, file.path)).bytes;
        if (sha256Digest(bytes) !== file.digest) {
            throw new Error(`stable bundle file does not match its verified digest: ${file.path}`);
        }
        files.set(file.path, file);
        fileBytes.set(file.path, bytes);
    }
    return {
        root,
        lock,
        lockBytes,
        report,
        files,
        fileBytes,
    };
}
export function readVerifiedBundleLock(bundle) {
    if (!bundle.lockBytes.equals(stableJsonBytes(bundle.lock))) {
        throw new Error('verified bundle lock bytes changed in memory');
    }
    return Buffer.from(bundle.lockBytes);
}
export function lockedFileRecord(bundle, path, classification) {
    assertSafeRelativePath(path, 'bundle path');
    const record = bundle.files.get(path);
    if (!record)
        throw new Error(`path is not present in the verified bundle: ${path}`);
    if (classification && record.classification !== classification) {
        throw new Error(`${path} is ${record.classification}, expected ${classification}`);
    }
    return record;
}
export function readLockedFile(bundle, path, classification) {
    const record = lockedFileRecord(bundle, path, classification);
    const bytes = bundle.fileBytes.get(path);
    if (!bytes || sha256Digest(bytes) !== record.digest) {
        throw new Error(`verified bundle bytes changed in memory: ${path}`);
    }
    return Buffer.from(bytes);
}
function headingLevel(line) {
    const match = line.match(/^(#{1,6})\s+/u);
    return match ? match[1].length : 0;
}
export function extractMarkdownHeading(bytes, heading, label = 'document') {
    const text = bytes.toString('utf8');
    const lines = text.split(/(?<=\n)/u);
    const expected = heading.trim();
    let start = -1;
    let level = 0;
    let offset = 0;
    let end = text.length;
    let fence = null;
    for (const line of lines) {
        const withoutEnding = line.replace(/\r?\n$/u, '');
        const fenceMatch = withoutEnding.match(/^\s*(`{3,}|~{3,})/u);
        if (fenceMatch) {
            const marker = fenceMatch[1];
            const character = marker[0];
            if (!fence)
                fence = { character, length: marker.length };
            else if (fence.character === character && marker.length >= fence.length)
                fence = null;
            offset += Buffer.byteLength(line, 'utf8');
            continue;
        }
        const currentLevel = fence ? 0 : headingLevel(withoutEnding);
        const title = currentLevel > 0
            ? withoutEnding.slice(currentLevel).trim()
            : '';
        if (start < 0 && title === expected) {
            start = offset;
            level = currentLevel;
        }
        else if (start >= 0 && currentLevel > 0 && currentLevel <= level) {
            end = offset;
            break;
        }
        offset += Buffer.byteLength(line, 'utf8');
    }
    if (start < 0)
        throw new Error(`${label} has no heading ${JSON.stringify(expected)}`);
    return bytes.subarray(start, end);
}
export function extractFirstFence(bytes, language, label = 'section') {
    const text = bytes.toString('utf8');
    const escaped = language
        ? language.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&')
        : '[^\\r\\n]*';
    const fence = '```';
    const pattern = new RegExp(`(?:^|\\n)${fence}${escaped}[ \\t]*\\r?\\n([\\s\\S]*?)\\r?\\n${fence}(?:\\r?\\n|$)`, 'u');
    const match = text.match(pattern);
    if (!match || match.index === undefined) {
        throw new Error(`${label} has no ${language || 'requested'} fenced block`);
    }
    return Buffer.from(match[1], 'utf8');
}
export function loadCorePart(bundle, path, selector) {
    const file = readLockedFile(bundle, path, 'core');
    let bytes;
    if (selector === 'file') {
        bytes = file;
    }
    else if (selector.startsWith('heading:')) {
        bytes = extractMarkdownHeading(file, selector.slice('heading:'.length), path);
    }
    else if (selector.startsWith('fence:')) {
        const section = extractMarkdownHeading(file, selector.slice('fence:'.length), path);
        bytes = extractFirstFence(section, null, `${path} ${selector}`);
    }
    else {
        throw new Error(`unsupported Core selector: ${selector}`);
    }
    return { path, selector, bytes, digest: sha256Digest(bytes) };
}
export function loadOutputContract(bundle, path, roleHeading) {
    const file = readLockedFile(bundle, path, 'core');
    const section = roleHeading === 'file'
        ? file
        : extractMarkdownHeading(file, roleHeading, path);
    const marker = Buffer.from('Output contract', 'utf8');
    const markerAt = section.indexOf(marker);
    if (markerAt < 0) {
        throw new Error(`${path} ${roleHeading} has no output contract marker`);
    }
    const contractRegion = section.subarray(markerAt);
    const bytes = extractFirstFence(contractRegion, 'json', `${path} ${roleHeading} output contract`);
    let example;
    try {
        example = JSON.parse(bytes.toString('utf8'));
    }
    catch (error) {
        throw new Error(`Core output contract is invalid JSON: ${error instanceof Error ? error.message : String(error)}`);
    }
    return {
        path,
        selector: `output-contract:${roleHeading}`,
        bytes,
        digest: sha256Digest(bytes),
        example,
    };
}
