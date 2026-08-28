import { existsSync, lstatSync, readFileSync } from 'node:fs';
import { basename, join } from 'node:path';
import { TextDecoder } from 'node:util';
import { activeClaims, allStatusRows, compareTimestamp, duplicateDefinitions, firstRunLogEntry, location, makeIndexes, mdLineSpan, normalizeSha256, parseTimestamp, pathIsWithin, reachedState, sha256, sourceFilePath, } from './check-helpers.js';
import { envelopeSection, findTable, findTables, findTableByFirstHeader, headingSection, idsIn, normalizeHeader, numberedEnvelopeHeadings, parseBulletFields, parseTables, tableCells, isSeparatorRow, } from './markdown.js';
import { CURRENT_RUN_FORMAT_VERSION, CLAIM_DEFINITION_HEADER, DISPOSITIONS, EXACT_EVIDENCE_FORMAT, EXACT_EVIDENCE_JOIN_POLICIES, EXACT_EVIDENCE_RUN_FORMAT_VERSION, forwardExecutionIdentityProblems, LEGACY_RUN_FORMAT_VERSION, PACKET_DEFINITION_HEADER, SOURCE_POSITION_FORMAT, SOURCE_WALK_CURSOR_REASONS, SOURCE_WALK_FORMAT, SUPPORTED_RUN_FORMAT_VERSIONS, usesExactEvidence, usesForwardExecutionIdentity, usesLineage, usesSourceWalk, } from './run-model.js';
import { runK2Lineage } from './checks-k2-lineage.js';
const CLAIM_TYPES = [
    'factual',
    'design-intent',
    'constraint',
    'preference',
    'open-question',
];
const STATES = [
    'DRAFT',
    'CORPUS-FROZEN',
    'DISTILLING',
    'ASSEMBLED',
    'VERIFIED',
    'ACCEPTED',
    'PROJECTING',
    'PROJECTION-ACCEPTED',
];
const ID_FAMILIES = [
    'RUN', 'SRC', 'PKT', 'CC', 'PC', 'RC', 'REF', 'STM', 'VER', 'NB', 'PRJ',
];
const STATUS_TARGET_FAMILIES = [
    'PKT',
    'CC',
    'SRC',
    'NB',
];
function isDisposition(value) {
    return DISPOSITIONS.includes(value);
}
function isStatusTargetFamily(value) {
    return STATUS_TARGET_FAMILIES.includes(value);
}
function isRecord(value) {
    return typeof value === 'object' && value !== null;
}
function stringProperty(value, property) {
    if (!isRecord(value))
        return '';
    const candidate = value[property];
    return typeof candidate === 'string' ? candidate : '';
}
function definitionStatus(target) {
    const values = isRecord(target) ? target.values : null;
    return stringProperty(values, 'status') || stringProperty(target, 'status') || 'active';
}
function existsPath(path, type = 'file') {
    if (!existsSync(path))
        return false;
    const stat = lstatSync(path);
    return type === 'directory' ? stat.isDirectory() : stat.isFile();
}
function distillingArtifactSignals(model) {
    const signals = [];
    if (model.packetDocument)
        signals.push('ledgers/packet-index.md');
    if (model.packets.length > 0)
        signals.push('packet rows');
    if (firstRunLogEntry(model.runLog, 'S2'))
        signals.push('run-log S2 entry');
    if (model.exactEvidence.format)
        signals.push('exact_evidence_format');
    if (model.exactEvidence.recordTable
        || model.exactEvidence.fragmentTable
        || model.exactEvidence.transformationTable) {
        signals.push('exact-evidence tables');
    }
    if (model.sourceWalkDocument)
        signals.push('ledgers/source-walk.md');
    if (model.documents.has('ledgers/lineage.md'))
        signals.push('ledgers/lineage.md');
    if (model.sourceWalk.format)
        signals.push('source_walk_format');
    if (model.sourceWalk.intervalTable
        || model.sourceWalk.eventTable
        || model.sourceWalk.cursorTable
        || model.sourceWalk.gapReviewTable
        || model.sourceWalk.completionTable) {
        signals.push('source-walk tables');
    }
    return signals;
}
function distillingArtifactsApply(model) {
    return STATES.slice(2).some((state) => reachedState(model, state))
        || (usesForwardExecutionIdentity(model.manifest?.runFormatVersion || '')
            && distillingArtifactSignals(model).length > 0);
}
function checkLayout(results, model) {
    results.run('K2.1', 'layout', (fail) => {
        const baseFiles = [
            'run-manifest.md',
            'run-log.md',
            'corpus/manifest.md',
        ];
        for (const path of baseFiles) {
            if (!existsPath(join(model.runDir, path)))
                fail(`required path ${path} is missing`);
        }
        const distillingFiles = [
            'ledgers/extraction-criteria.md',
            'ledgers/packet-index.md',
            'ledgers/claim-inventory.md',
            'ledgers/disposition-ledger.md',
        ];
        if (distillingArtifactsApply(model)) {
            for (const path of distillingFiles) {
                if (!existsPath(join(model.runDir, path)))
                    fail(`required path ${path} is missing`);
            }
            if (usesSourceWalk(model.manifest?.runFormatVersion || '')
                && !existsPath(join(model.runDir, 'ledgers/source-walk.md'))) {
                fail('required path ledgers/source-walk.md is missing');
            }
            if (usesLineage(model.manifest?.runFormatVersion || '')
                && !existsPath(join(model.runDir, 'ledgers/lineage.md'))) {
                fail('required path ledgers/lineage.md is missing');
            }
        }
        if (reachedState(model, 'ASSEMBLED') || STATES.slice(4).some((state) => reachedState(model, state))) {
            const assembledFiles = [
                'ledgers/merge-map.md',
                'ledgers/evidence-roles.md',
                'ledgers/negative-boundaries.md',
                'ledgers/unresolved-queue.md',
                'ledgers/external-referents.md',
                'clusters/pre-cluster-tags.md',
                'arms/stress-test-matrix.md',
                'synthesis/cluster-synthesis.md',
                'precis.md',
            ];
            for (const path of assembledFiles) {
                if (!existsPath(join(model.runDir, path))) {
                    fail(`ASSEMBLED run is missing ${path}`);
                }
            }
            if (!existsPath(join(model.runDir, 'clusters', 'route-cards'), 'directory')) {
                fail('ASSEMBLED run is missing clusters/route-cards/');
            }
        }
        if (reachedState(model, 'VERIFIED') || STATES.slice(5).some((state) => reachedState(model, state))) {
            if (!existsPath(join(model.runDir, 'verification'), 'directory')) {
                fail('VERIFIED run is missing verification/');
            }
            if (!existsPath(join(model.runDir, 'verification', 'kernel-report.md'))) {
                fail('VERIFIED run is missing verification/kernel-report.md');
            }
        }
        if (reachedState(model, 'PROJECTING') || reachedState(model, 'PROJECTION-ACCEPTED')) {
            if (!existsPath(join(model.runDir, 'projections'), 'directory')) {
                fail('PROJECTING run is missing projections/');
            }
        }
        return 'required base and reached-state artifacts are present';
    });
}
function positiveDecision(value) {
    return /^(?:approved|accepted|fixture-simulated)(?:\b|:)/i.test(String(value || '').trim());
}
function checkManifest(results, model) {
    results.run('K2.2', 'manifest', (fail) => {
        const manifest = model.manifest;
        if (!manifest) {
            fail('run-manifest.md is missing or unreadable');
            return 'manifest parsed';
        }
        const runIdFields = manifest.lines.filter((line) => /^\s*-\s*run[_ -]id\s*:/i.test(line));
        const predecessorFields = manifest.lines.filter((line) => /^\s*-\s*predecessor[_ -]run\s*:/i.test(line));
        if (runIdFields.length !== 1) {
            fail(`run_id must be defined exactly once; found ${runIdFields.length}`);
        }
        if (predecessorFields.length !== 1) {
            fail(`predecessor_run must be defined exactly once; found ${predecessorFields.length}`);
        }
        if (!['agent', 'manual', 'hybrid'].includes(manifest.mode)) {
            fail(`mode "${manifest.mode || '(blank)'}" is not agent, manual, or hybrid`);
        }
        if (!/^RUN-[A-Za-z0-9]+(?:[._-][A-Za-z0-9]+)*$/.test(manifest.runId)) {
            fail('run_id must be a RUN-<slug> identifier');
        }
        if (manifest.predecessorRun !== 'none'
            && !/^RUN-[A-Za-z0-9]+(?:[._-][A-Za-z0-9]+)*$/.test(manifest.predecessorRun)) {
            fail('predecessor_run must be none or a RUN-<slug> identifier');
        }
        else if (manifest.predecessorRun === manifest.runId) {
            fail('predecessor_run must not equal run_id');
        }
        if (!/^[a-fA-F0-9]{40}$/.test(manifest.doctrineSha)) {
            fail('doctrine_sha must be exactly 40 hexadecimal characters');
        }
        const runFormatFields = manifest.lines.filter((line) => /^\s*-\s*run[_ -]format[_ -]version\s*:/i.test(line));
        if (usesForwardExecutionIdentity(manifest.runFormatVersion)
            && runFormatFields.length !== 1) {
            fail(`run_format_version must be defined exactly once; found ${runFormatFields.length}`);
        }
        else if (runFormatFields.length > 1) {
            fail(`run_format_version must be defined at most once; found ${runFormatFields.length}`);
        }
        if (manifest.runFormatVersion
            && !SUPPORTED_RUN_FORMAT_VERSIONS.some((version) => version === manifest.runFormatVersion)) {
            fail(`run_format_version "${manifest.runFormatVersion}" is unsupported; expected `
                + SUPPORTED_RUN_FORMAT_VERSIONS.join(', '));
        }
        for (const problem of forwardExecutionIdentityProblems(manifest))
            fail(problem);
        if (!manifest.corpusHash.trim())
            fail('corpus_hash is missing');
        if (manifest.states.length === 0) {
            fail('state log has no rows');
            return 'manifest fields and state log are valid';
        }
        let current = null;
        let blockedFrom = null;
        let previousTimestamp = null;
        for (let i = 0; i < manifest.states.length; i++) {
            const row = manifest.states[i];
            const state = row.values.state.trim();
            const entered = parseTimestamp(row.values.entered);
            if (!entered) {
                fail(`state ${state || '(blank)'} has invalid entered timestamp "${row.values.entered}" at ${location(row)}`);
            }
            else if (previousTimestamp && compareTimestamp(previousTimestamp, entered) > 0) {
                fail(`state timestamp moves backwards at ${location(row)}`);
            }
            if (entered)
                previousTimestamp = entered;
            if (!STATES.includes(state) && state !== 'BLOCKED') {
                fail(`unknown state "${state}" at ${location(row)}`);
                continue;
            }
            if (i === 0 && state !== 'DRAFT') {
                fail(`state log must start at DRAFT, found ${state} at ${location(row)}`);
            }
            if (state === 'BLOCKED') {
                if (blockedFrom !== null) {
                    fail(`BLOCKED at ${location(row)} occurs before re-entry into ${blockedFrom}`);
                }
                else if (current === null || ['PROJECTION-ACCEPTED'].includes(current)) {
                    fail(`BLOCKED at ${location(row)} has no resumable interrupted state`);
                }
                else {
                    blockedFrom = current;
                }
                continue;
            }
            if (blockedFrom !== null) {
                if (state !== blockedFrom) {
                    fail(`BLOCKED after ${blockedFrom} re-enters ${state} at ${location(row)}`);
                }
                blockedFrom = null;
                current = state;
                continue;
            }
            if (current === null) {
                current = state;
                continue;
            }
            const repeatProjection = ((current === 'ACCEPTED' || current === 'PROJECTION-ACCEPTED')
                && state === 'PROJECTING');
            const normalNext = STATES.indexOf(state) === STATES.indexOf(current) + 1;
            if (!repeatProjection && !normalNext) {
                fail(`invalid state transition ${current} -> ${state} at ${location(row)}`);
            }
            current = state;
        }
        const hasStateAtOrAfter = (state) => {
            const threshold = STATES.indexOf(state);
            return manifest.states.some((row) => STATES.indexOf(row.values.state.trim()) >= threshold);
        };
        const distillingSignals = distillingArtifactSignals(model);
        if (usesForwardExecutionIdentity(manifest.runFormatVersion)
            && distillingSignals.length > 0
            && !hasStateAtOrAfter('DISTILLING')) {
            fail(`state log understates DISTILLING; observed ${distillingSignals.join(', ')}`);
        }
        if (hasStateAtOrAfter('CORPUS-FROZEN')) {
            const s0 = manifest.signoffs.find((row) => /\bS0\b/i.test(row.values.gate));
            if (!s0 || !positiveDecision(s0.values.decision)) {
                fail('CORPUS-FROZEN requires an approved S0 scope/sensitivity sign-off');
            }
            else {
                const signed = parseTimestamp(s0.values.date);
                const firstS2 = firstRunLogEntry(model.runLog, 'S2');
                const packetStart = firstS2 ? parseTimestamp(firstS2.timestamp) : null;
                if (!signed) {
                    fail(`S0 sign-off has invalid date "${s0.values.date}"`);
                }
                else if (packetStart && compareTimestamp(signed, packetStart) > 0) {
                    fail(`S0 sign-off ${s0.values.date} occurs after first S2 entry ${firstS2.timestamp}`);
                }
            }
        }
        if (hasStateAtOrAfter('ACCEPTED')) {
            const acceptance = manifest.signoffs.find((row) => /accept/i.test(row.values.gate));
            if (!acceptance || !positiveDecision(acceptance.values.decision)) {
                fail('ACCEPTED requires an authority acceptance sign-off');
            }
        }
        const projectionAcceptances = manifest.states
            .filter((row) => row.values.state.trim() === 'PROJECTION-ACCEPTED');
        if (projectionAcceptances.length > 0) {
            const p3Signoffs = manifest.signoffs.filter((row) => (positiveDecision(row.values.decision)
                && (/\bP3\b/i.test(row.values.gate) || /projection.*accept/i.test(row.values.gate))));
            if (p3Signoffs.length < projectionAcceptances.length) {
                fail(`${projectionAcceptances.length} PROJECTION-ACCEPTED state(s) require at least `
                    + `${projectionAcceptances.length} positive P3 sign-off row(s), found ${p3Signoffs.length}`);
            }
        }
        return 'mode, forward identity, stage consistency, ordered states, BLOCKED re-entry, and sign-offs are valid';
    });
}
function checkForbidden(results, model, root) {
    results.run('K2.3', 'forbidden tokens', (fail) => {
        const fixtureRoot = join(root, 'docs', 'fixtures');
        if (!pathIsWithin(fixtureRoot, model.runDir)) {
            return 'real run is exempt from fixture-only forbidden-token scanning';
        }
        const deferredBusinessIntelligenceConsumerPattern = new RegExp(`\\b${['sense', 'net'].join('')}\\b`, 'i');
        const tokens = [
            ['Phase', /\bphase\b/i],
            [
                'deferred business-intelligence consumer name',
                deferredBusinessIntelligenceConsumerPattern,
            ],
        ];
        for (const file of model.files) {
            const lines = file.text.split('\n');
            for (const [label, pattern] of tokens) {
                for (let index = 0; index < lines.length; index++) {
                    if (pattern.test(lines[index])) {
                        fail(`"${label}" found in ${file.relativePath}:${index + 1}`);
                    }
                }
            }
        }
        return 'fixture run contains zero absolute-forbidden tokens';
    });
}
function checkPackets(results, model) {
    results.run('K2.4', 'packet resolution', (fail) => {
        const sources = makeIndexes(model).SRC;
        const unverified = new Set();
        for (const packet of model.packets) {
            const { packetId, sourceId, locator, spanHash } = packet.values;
            const source = sources.get(sourceId);
            if (!source) {
                fail(`${packetId || 'packet row'} source ${sourceId || '(blank)'} does not resolve at ${location(packet)}`);
                continue;
            }
            const scheme = source.values.scheme.replace(/`/g, '').trim();
            if (scheme === 'md-lines') {
                const match = locator.match(/^L(\d+)-L(\d+)$/);
                if (!match) {
                    fail(`${packetId} locator "${locator}" is not L<start>-L<end> at ${location(packet)}`);
                    continue;
                }
                const start = Number(match[1]);
                const end = Number(match[2]);
                const sourcePath = sourceFilePath(model.runDir, source.values.locus);
                if (!sourcePath || !existsPath(sourcePath)) {
                    fail(`${packetId} source locus "${source.values.locus}" is not a readable corpus file`);
                    continue;
                }
                const span = mdLineSpan(sourcePath, start, end);
                if (!span || !span.bytes) {
                    fail(`${packetId} locator ${locator} is outside ${sourceId}'s ${span?.lineCount ?? 0} lines`);
                    continue;
                }
                if (!/^sha256:[a-f0-9]{64}$/.test(spanHash)) {
                    fail(`${packetId} span_hash must be sha256:<lowercase hex> at ${location(packet)}`);
                    continue;
                }
                const actual = sha256(span.bytes);
                if (spanHash.slice('sha256:'.length) !== actual) {
                    fail(`${packetId} locator ${locator} hash mismatch in ${source.values.locus}`);
                }
            }
            else if (scheme === 'chat-msg') {
                if (!/^M[1-9]\d*(?::S[1-9]\d*)?$/.test(locator)) {
                    fail(`${packetId} locator "${locator}" is not M<n> or M<n>:S<k>`);
                }
                unverified.add(scheme);
            }
            else {
                if (!scheme)
                    fail(`${sourceId} has no declared locator scheme`);
                else
                    unverified.add(scheme);
            }
        }
        return unverified.size
            ? `packet references resolve; scheme(s) ${[...unverified].sort().join(', ')} unverified`
            : 'all packet locators reopen source spans and hashes match';
    });
}
function parseMdLineLocator(value) {
    const match = value.match(/^L(\d+)-L(\d+)$/);
    if (!match)
        return null;
    const start = Number(match[1]);
    const end = Number(match[2]);
    return start >= 1 && end >= start ? { start, end } : null;
}
function canonicalBase64(value) {
    const encoded = value.trim();
    if (!encoded
        || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(encoded)) {
        return null;
    }
    const decoded = Buffer.from(encoded, 'base64');
    return decoded.toString('base64') === encoded ? decoded : null;
}
function exactSha256(value) {
    const match = value.match(/^sha256:([a-f0-9]{64})$/);
    return match ? match[1] : null;
}
function framedExactEvidenceHash(fragments) {
    const parts = [
        Buffer.from(`${EXACT_EVIDENCE_FORMAT}\0`, 'utf8'),
    ];
    for (const fragment of fragments) {
        const length = Buffer.alloc(8);
        length.writeBigUInt64BE(BigInt(fragment.byteLength));
        parts.push(length, fragment);
    }
    return sha256(Buffer.concat(parts));
}
function firstByteDifference(left, right) {
    const limit = Math.min(left.byteLength, right.byteLength);
    for (let index = 0; index < limit; index++) {
        if (left[index] !== right[index])
            return index;
    }
    return left.byteLength === right.byteLength ? -1 : limit;
}
function packetIdList(value) {
    const parts = value.split(',').map((part) => part.trim());
    if (parts.length === 0 || parts.some((part) => !/^PKT-\d+$/.test(part))) {
        return null;
    }
    return parts;
}
function checkExactEvidence(results, model) {
    results.run('K2.13', 'exact evidence and ordered fragments', (fail) => {
        const exact = model.exactEvidence;
        const runFormatVersion = model.manifest?.runFormatVersion || '';
        const isLegacyRun = (runFormatVersion === ''
            || runFormatVersion === LEGACY_RUN_FORMAT_VERSION);
        const hasExactEvidenceContract = usesExactEvidence(runFormatVersion);
        const tablesPresent = Boolean(exact.recordTable || exact.fragmentTable || exact.transformationTable);
        if (!isLegacyRun && !hasExactEvidenceContract) {
            fail(`exact-evidence activation cannot determine unsupported run_format_version `
                + `"${runFormatVersion || '(blank)'}"`);
            return 'run format selects the exact-evidence contract';
        }
        if (isLegacyRun) {
            if (exact.format || tablesPresent) {
                fail(`legacy run format ${runFormatVersion || '(pre-versioned)'} must not be `
                    + `reinterpreted as ${EXACT_EVIDENCE_FORMAT}`);
            }
            return `legacy run format ${runFormatVersion || '(pre-versioned)'} retains K2.4 behavior`;
        }
        if (!exact.format) {
            if (tablesPresent) {
                fail('exact-evidence tables require an exact_evidence_format declaration');
            }
            if (distillingArtifactsApply(model)) {
                fail(`run format ${runFormatVersion} requires `
                    + `exact_evidence_format ${EXACT_EVIDENCE_FORMAT} once DISTILLING is reached`);
            }
            return `exact evidence is not applicable before DISTILLING in run format ${runFormatVersion}`;
        }
        if (exact.format !== EXACT_EVIDENCE_FORMAT) {
            fail(`exact_evidence_format "${exact.format}" is unsupported; expected ${EXACT_EVIDENCE_FORMAT}`);
            return 'versioned exact-evidence structure is valid';
        }
        if (!exact.recordTable)
            fail('exact evidence record table is missing or has the wrong header');
        if (!exact.fragmentTable)
            fail('ordered fragment table is missing or has the wrong header');
        if (!exact.transformationTable) {
            fail('evidence transformation table is missing or has the wrong header');
        }
        const recordByKey = new Map();
        const fragmentByKey = new Map();
        const transformKeys = new Set();
        const fragmentsByEvidence = new Map();
        const packetCoverage = new Map();
        const sourceBytes = new Map();
        const observedByFragment = new Map();
        const degradedUnverifiedSchemes = new Set();
        const sources = makeIndexes(model).SRC;
        const packets = makeIndexes(model).PKT;
        for (const record of exact.records) {
            const { evidenceKey } = record.values;
            if (!/^EVID-\d+$/.test(evidenceKey)) {
                fail(`${evidenceKey || 'evidence row'} evidence_key must be EVID-<digits> at ${location(record)}`);
            }
            if (recordByKey.has(evidenceKey)) {
                fail(`${evidenceKey || 'evidence row'} is defined more than once at ${location(record)}`);
            }
            else if (evidenceKey) {
                recordByKey.set(evidenceKey, record);
            }
        }
        for (const fragment of exact.fragments) {
            const { fragmentKey, evidenceKey, packetId, fragmentOrder, sourceId, locator, sourceRelation, byteRole, fragmentHash, exactBytesBase64, } = fragment.values;
            if (!/^FRAG-\d+$/.test(fragmentKey)) {
                fail(`${fragmentKey || 'fragment row'} fragment_key must be FRAG-<digits> at ${location(fragment)}`);
            }
            if (fragmentByKey.has(fragmentKey)) {
                fail(`${fragmentKey || 'fragment row'} is defined more than once at ${location(fragment)}`);
            }
            else if (fragmentKey) {
                fragmentByKey.set(fragmentKey, fragment);
            }
            if (!recordByKey.has(evidenceKey)) {
                fail(`${fragmentKey || 'fragment row'} references missing evidence_key ${evidenceKey || '(blank)'}`);
            }
            const order = Number(fragmentOrder);
            if (!Number.isInteger(order) || order < 1) {
                fail(`${fragmentKey || 'fragment row'} fragment_order must be a positive integer`);
            }
            if (sourceRelation !== 'frozen-source') {
                fail(`${fragmentKey || 'fragment row'} source_relation must be frozen-source`);
            }
            if (byteRole !== 'exact-source-bytes') {
                fail(`${fragmentKey || 'fragment row'} byte_role "${byteRole || '(blank)'}" cannot substitute rendered or normalized text for exact-source-bytes`);
            }
            const source = sources.get(sourceId);
            const packet = packets.get(packetId);
            if (!source) {
                fail(`${fragmentKey || 'fragment row'} source ${sourceId || '(blank)'} does not resolve`);
            }
            if (!packet) {
                fail(`${fragmentKey || 'fragment row'} packet ${packetId || '(blank)'} does not resolve`);
            }
            const locatorParts = parseMdLineLocator(locator);
            if (!locatorParts) {
                fail(`${fragmentKey || 'fragment row'} locator "${locator}" is not L<start>-L<end>`);
            }
            let observed = null;
            if (source) {
                const scheme = source.values.scheme.replace(/`/g, '').trim();
                if (scheme !== 'md-lines') {
                    fail(`${fragmentKey || 'fragment row'} exact evidence requires a mechanically verified md-lines source, found ${scheme || '(blank)'}`);
                }
                const sourcePath = sourceFilePath(model.runDir, source.values.locus);
                if (!sourcePath || !existsPath(sourcePath)) {
                    fail(`${fragmentKey || 'fragment row'} frozen source locus "${source.values.locus}" is not a readable file`);
                }
                else {
                    let frozenBytes = sourceBytes.get(sourceId);
                    if (!frozenBytes) {
                        frozenBytes = readFileSync(sourcePath);
                        sourceBytes.set(sourceId, frozenBytes);
                        const declaredSourceHash = exactSha256(source.values.contentHash);
                        if (!declaredSourceHash) {
                            fail(`${sourceId} content_hash must be sha256:<lowercase hex> for exact evidence`);
                        }
                        else if (sha256(frozenBytes) !== declaredSourceHash) {
                            fail(`${sourceId} content_hash does not match the frozen source bytes`);
                        }
                    }
                    if (locatorParts) {
                        const span = mdLineSpan(sourcePath, locatorParts.start, locatorParts.end);
                        if (!span?.bytes) {
                            fail(`${fragmentKey || 'fragment row'} locator ${locator} is outside ${sourceId}'s ${span?.lineCount ?? 0} lines`);
                        }
                        else {
                            observed = span.bytes;
                            observedByFragment.set(fragmentKey, observed);
                        }
                    }
                }
            }
            const exactBytes = canonicalBase64(exactBytesBase64);
            if (!exactBytes) {
                fail(`${fragmentKey || 'fragment row'} exact_bytes_base64 is not canonical base64`);
            }
            else if (observed && !exactBytes.equals(observed)) {
                const offset = firstByteDifference(exactBytes, observed);
                fail(`${fragmentKey || 'fragment row'} exact bytes differ from frozen source at byte ${offset}`);
            }
            const declaredFragmentHash = exactSha256(fragmentHash);
            if (!declaredFragmentHash) {
                fail(`${fragmentKey || 'fragment row'} fragment_hash must be sha256:<lowercase hex>`);
            }
            else {
                if (observed && sha256(observed) !== declaredFragmentHash) {
                    fail(`${fragmentKey || 'fragment row'} fragment_hash does not match exact source bytes`);
                }
                if (exactBytes && sha256(exactBytes) !== declaredFragmentHash) {
                    fail(`${fragmentKey || 'fragment row'} fragment_hash does not match exact_bytes_base64`);
                }
            }
            if (packet) {
                if (packet.values.sourceId !== sourceId
                    || packet.values.locator !== locator
                    || exactSha256(packet.values.spanHash) !== declaredFragmentHash) {
                    fail(`${fragmentKey || 'fragment row'} packet ${packetId} does not bind the same source, locator, and fragment hash`);
                }
            }
            const group = fragmentsByEvidence.get(evidenceKey) || [];
            group.push(fragment);
            fragmentsByEvidence.set(evidenceKey, group);
        }
        for (const record of exact.records) {
            const { evidenceKey, packetIds: packetIdsValue, evidenceState, fragmentCount, joinPolicy, exactEvidenceHash, degradedSourceId, degradedSourceLocator, degradationReason, } = record.values;
            const fragments = fragmentsByEvidence.get(evidenceKey) || [];
            const count = Number(fragmentCount);
            if (!Number.isInteger(count) || count < 0) {
                fail(`${evidenceKey || 'evidence row'} fragment_count must be a non-negative integer`);
            }
            if (evidenceState === 'degraded-non-exact') {
                if (packetIdsValue !== 'none') {
                    fail(`${evidenceKey} degraded evidence must not claim packet_ids`);
                }
                if (count !== 0 || fragments.length !== 0) {
                    fail(`${evidenceKey} degraded evidence must have zero exact fragments`);
                }
                if (joinPolicy !== 'not-applicable') {
                    fail(`${evidenceKey} degraded evidence join_policy must be not-applicable`);
                }
                if (exactEvidenceHash !== 'none') {
                    fail(`${evidenceKey} degraded evidence must not claim an exact_evidence_hash`);
                }
                const source = sources.get(degradedSourceId);
                if (!degradedSourceId || degradedSourceId === 'none') {
                    fail(`${evidenceKey} degraded evidence requires a degraded_source_id`);
                }
                else if (!source) {
                    fail(`${evidenceKey} degraded source ${degradedSourceId} does not resolve`);
                }
                if (!degradedSourceLocator || degradedSourceLocator === 'none') {
                    fail(`${evidenceKey} degraded evidence requires a degraded_source_locator`);
                }
                if (source) {
                    const scheme = source.values.scheme.replace(/`/g, '').trim();
                    const sourcePath = sourceFilePath(model.runDir, source.values.locus);
                    if (!sourcePath || !existsPath(sourcePath)) {
                        fail(`${evidenceKey} degraded source ${degradedSourceId} locus `
                            + `"${source.values.locus}" is not a readable file`);
                    }
                    else {
                        let frozenBytes = sourceBytes.get(degradedSourceId);
                        if (!frozenBytes) {
                            frozenBytes = readFileSync(sourcePath);
                            sourceBytes.set(degradedSourceId, frozenBytes);
                        }
                        const declaredSourceHash = exactSha256(source.values.contentHash);
                        if (!declaredSourceHash) {
                            fail(`${degradedSourceId} content_hash must be sha256:<lowercase hex>`);
                        }
                        else if (sha256(frozenBytes) !== declaredSourceHash) {
                            fail(`${degradedSourceId} content_hash does not match the frozen source bytes`);
                        }
                    }
                    if (!scheme) {
                        fail(`${degradedSourceId} has no declared locator scheme`);
                    }
                    else if (scheme === 'md-lines'
                        && degradedSourceLocator !== 'none'
                        && !parseMdLineLocator(degradedSourceLocator)) {
                        fail(`${evidenceKey} degraded locator "${degradedSourceLocator}" `
                            + 'is not L<start>-L<end>');
                    }
                    else if (scheme === 'md-lines'
                        && sourcePath
                        && existsPath(sourcePath)
                        && degradedSourceLocator !== 'none') {
                        const locator = parseMdLineLocator(degradedSourceLocator);
                        if (locator) {
                            const span = mdLineSpan(sourcePath, locator.start, locator.end);
                            if (!span?.bytes) {
                                fail(`${evidenceKey} degraded locator ${degradedSourceLocator} is outside `
                                    + `${degradedSourceId}'s ${span?.lineCount ?? 0} lines`);
                            }
                        }
                    }
                    else if (scheme === 'chat-msg'
                        && degradedSourceLocator !== 'none'
                        && !/^M[1-9]\d*(?::S[1-9]\d*)?$/.test(degradedSourceLocator)) {
                        fail(`${evidenceKey} degraded locator "${degradedSourceLocator}" `
                            + 'is not M<n> or M<n>:S<k>');
                    }
                    else if (scheme !== 'md-lines') {
                        degradedUnverifiedSchemes.add(scheme);
                    }
                }
                if (!degradationReason || degradationReason === 'none') {
                    fail(`${evidenceKey} degraded evidence requires a degradation_reason`);
                }
                continue;
            }
            if (evidenceState !== 'exact') {
                fail(`${evidenceKey || 'evidence row'} evidence_state must be exact or degraded-non-exact`);
                continue;
            }
            if (degradationReason !== 'none') {
                fail(`${evidenceKey} exact evidence degradation_reason must be none`);
            }
            if (degradedSourceId !== 'none' || degradedSourceLocator !== 'none') {
                fail(`${evidenceKey} exact evidence degraded source provenance must be none`);
            }
            if (!EXACT_EVIDENCE_JOIN_POLICIES.includes(joinPolicy)) {
                fail(`${evidenceKey} join_policy "${joinPolicy || '(blank)'}" is undeclared`);
            }
            if (count !== fragments.length) {
                fail(`${evidenceKey} fragment_count ${fragmentCount} does not match ${fragments.length} fragment row(s)`);
            }
            const orders = fragments.map((fragment) => Number(fragment.values.fragmentOrder));
            const expectedOrders = fragments.map((_, index) => index + 1);
            if (orders.some((order, index) => order !== expectedOrders[index])) {
                fail(`${evidenceKey} fragment rows must appear in explicit fragment_order 1..${fragments.length}`);
            }
            const declaredPackets = packetIdList(packetIdsValue);
            if (!declaredPackets) {
                fail(`${evidenceKey} packet_ids must be a comma-separated ordered PKT list`);
            }
            else {
                const fragmentPackets = fragments.map((fragment) => fragment.values.packetId);
                if (declaredPackets.length !== fragmentPackets.length
                    || declaredPackets.some((packetId, index) => packetId !== fragmentPackets[index])) {
                    fail(`${evidenceKey} packet_ids do not match fragment packet order`);
                }
                for (const packetId of declaredPackets) {
                    const prior = packetCoverage.get(packetId);
                    if (prior) {
                        fail(`${packetId} is claimed by both ${prior} and ${evidenceKey}`);
                    }
                    else {
                        packetCoverage.set(packetId, evidenceKey);
                    }
                }
            }
            if (joinPolicy === 'single-fragment' && fragments.length !== 1) {
                fail(`${evidenceKey} single-fragment join requires exactly one fragment`);
            }
            if (joinPolicy === 'adjacent-fragments') {
                if (fragments.length < 2) {
                    fail(`${evidenceKey} adjacent-fragments join requires at least two fragments`);
                }
                for (let index = 1; index < fragments.length; index++) {
                    const previous = fragments[index - 1].values;
                    const current = fragments[index].values;
                    const previousLocator = parseMdLineLocator(previous.locator);
                    const currentLocator = parseMdLineLocator(current.locator);
                    if (previous.sourceId !== current.sourceId
                        || !previousLocator
                        || !currentLocator
                        || previousLocator.end + 1 !== currentLocator.start) {
                        fail(`${evidenceKey} adjacent-fragments join contains a non-adjacent fragment boundary`);
                    }
                }
            }
            if (joinPolicy === 'separate-fragments' && fragments.length < 2) {
                fail(`${evidenceKey} separate-fragments join requires at least two fragments`);
            }
            const orderedBytes = fragments.map((fragment) => observedByFragment.get(fragment.values.fragmentKey));
            const declaredEvidenceHash = exactSha256(exactEvidenceHash);
            if (!declaredEvidenceHash) {
                fail(`${evidenceKey} exact_evidence_hash must be sha256:<lowercase hex>`);
            }
            else if (orderedBytes.every((bytes) => Boolean(bytes))) {
                const actual = framedExactEvidenceHash(orderedBytes);
                if (actual !== declaredEvidenceHash) {
                    fail(`${evidenceKey} exact_evidence_hash does not match ordered framed fragment bytes`);
                }
            }
        }
        for (const packet of model.packets) {
            if (!packetCoverage.has(packet.values.packetId)) {
                fail(`${packet.values.packetId} lacks an exact evidence record; rendered or normalized text cannot substitute for exact evidence`);
            }
        }
        const transformationsByEvidence = new Map();
        for (const transformation of exact.transformations) {
            const { transformKey, evidenceKey, outputRole, predecessorExactEvidenceHash, effectiveExactEvidenceHash, outputText, outputTextHash, } = transformation.values;
            if (!/^XFORM-\d+$/.test(transformKey)) {
                fail(`${transformKey || 'transformation row'} transform_key must be XFORM-<digits> at ${location(transformation)}`);
            }
            if (transformKeys.has(transformKey)) {
                fail(`${transformKey || 'transformation row'} is defined more than once at ${location(transformation)}`);
            }
            transformKeys.add(transformKey);
            const record = recordByKey.get(evidenceKey);
            if (!record) {
                fail(`${transformKey || 'transformation row'} references missing evidence_key ${evidenceKey || '(blank)'}`);
                continue;
            }
            transformationsByEvidence.set(evidenceKey, (transformationsByEvidence.get(evidenceKey) || 0) + 1);
            if (!['rendered', 'normalized'].includes(outputRole)) {
                fail(`${transformKey} output_role must be rendered or normalized`);
            }
            if (!outputText)
                fail(`${transformKey} output_text must not be empty`);
            const declaredOutputHash = exactSha256(outputTextHash);
            if (!declaredOutputHash) {
                fail(`${transformKey} output_text_hash must be sha256:<lowercase hex>`);
            }
            else if (sha256(Buffer.from(outputText, 'utf8')) !== declaredOutputHash) {
                fail(`${transformKey} output_text_hash does not match UTF-8 output_text`);
            }
            if (record.values.evidenceState === 'degraded-non-exact') {
                if (outputRole !== 'rendered') {
                    fail(`${transformKey} degraded evidence may record rendered text only`);
                }
                if (predecessorExactEvidenceHash !== 'none'
                    || effectiveExactEvidenceHash !== 'none') {
                    fail(`${transformKey} degraded evidence must not claim exact predecessor/effective hashes`);
                }
                continue;
            }
            const exactHash = exactSha256(record.values.exactEvidenceHash);
            if (!exactHash
                || exactSha256(predecessorExactEvidenceHash) !== exactHash) {
                fail(`${transformKey} predecessor_exact_evidence_hash does not match ${evidenceKey}`);
            }
            if (!exactHash
                || exactSha256(effectiveExactEvidenceHash) !== exactHash) {
                fail(`${transformKey} changes exact evidence identity during ${outputRole || 'transformation'}`);
            }
        }
        for (const record of exact.records) {
            if (record.values.evidenceState === 'degraded-non-exact'
                && !transformationsByEvidence.has(record.values.evidenceKey)) {
                fail(`${record.values.evidenceKey} degraded evidence requires a rendered transformation row`);
            }
        }
        return degradedUnverifiedSchemes.size > 0
            ? `exact fragments reopen frozen bytes; degraded scheme(s) ${[...degradedUnverifiedSchemes].sort().join(', ')} are structurally checked but not mechanically reopened`
            : 'exact fragments reopen frozen bytes; degraded source loci reopen and order, joins, hashes, and transformation identities are valid';
    });
}
const SOURCE_WALK_OUTCOMES = [
    'admitted',
    'no-candidate-observed',
    'excluded',
    'deferred',
    'unsupported',
];
const GAP_REVIEW_RESULTS = [
    'no-gap-candidate-found',
    'gap-candidate-found',
    'cannot-determine',
];
const SOURCE_WALK_REVIEW_BASIS_FORMAT = 'aleph-source-walk-review-basis/v1';
function canonicalNonnegativeInteger(value) {
    if (!/^(?:0|[1-9]\d*)$/.test(value))
        return null;
    const parsed = Number(value);
    return Number.isSafeInteger(parsed) ? parsed : null;
}
function customIdList(value, family) {
    if (value === 'none')
        return [];
    const parts = value.split(',').map((part) => part.trim());
    const pattern = new RegExp(`^${family}-\\d+$`);
    if (parts.length === 0 || parts.some((part) => !pattern.test(part)))
        return null;
    return parts;
}
function substantiveValue(value) {
    return Boolean(value.trim()) && value.trim() !== 'none';
}
function utf8Boundary(bytes, offset) {
    return offset === 0
        || offset === bytes.byteLength
        || (bytes[offset] & 0xc0) !== 0x80;
}
function sourceWalkTablesPresent(model) {
    const walk = model.sourceWalk;
    return Boolean(walk.intervalTable
        || walk.eventTable
        || walk.cursorTable
        || walk.gapReviewTable
        || walk.completionTable);
}
function sourceWalkStageClosed(model) {
    const distillingIndex = STATES.indexOf('DISTILLING');
    const advanced = Boolean(model.manifest?.states.some((row) => (STATES.indexOf(row.values.state.trim()) > distillingIndex)));
    const loggedExit = Boolean(model.runLog?.lines.some((line) => (/^##\s+.+\s+[—-]\s+S2\s+[—-]\s+exit\s*$/i.test(line))));
    return advanced || loggedExit;
}
export function sourceWalkReviewBasisDigest(model, sourceId, cursorId) {
    const source = model.corpus.sources.find((row) => row.values.sourceId === sourceId);
    const cursor = model.sourceWalk.cursors.find((row) => row.values.cursorId === cursorId);
    const sourcePath = source ? sourceFilePath(model.runDir, source.values.locus) : null;
    if (!source
        || !cursor
        || !sourcePath
        || !existsPath(sourcePath)
        || !model.criteria
        || !existsPath(model.criteria.path)) {
        return null;
    }
    const primaryEvents = model.sourceWalk.events.filter((row) => (row.values.sourceId === sourceId
        && row.values.origin === 'primary'));
    const packetIds = [...new Set(primaryEvents.map((row) => row.values.packetId))];
    const primaryPacketEvidence = packetIds.map((packetId) => {
        const packet = model.packets.find((row) => row.values.packetId === packetId);
        const records = model.exactEvidence.records.filter((record) => (packetIdList(record.values.packetIds)?.includes(packetId)));
        const fragments = model.exactEvidence.fragments
            .filter((fragment) => fragment.values.packetId === packetId)
            .sort((left, right) => (Number(left.values.fragmentOrder) - Number(right.values.fragmentOrder)
            || left.values.fragmentKey.localeCompare(right.values.fragmentKey)));
        if (!packet || records.length !== 1 || fragments.length === 0)
            return null;
        const record = records[0];
        return {
            packet_id: packetId,
            packet_source_id: packet.values.sourceId,
            packet_locator: packet.values.locator,
            packet_span_hash: packet.values.spanHash,
            evidence_key: record.values.evidenceKey,
            evidence_packet_ids: record.values.packetIds,
            evidence_fragment_count: record.values.fragmentCount,
            evidence_join_policy: record.values.joinPolicy,
            exact_evidence_hash: record.values.exactEvidenceHash,
            fragments: fragments.map((fragment) => ({
                fragment_key: fragment.values.fragmentKey,
                fragment_order: fragment.values.fragmentOrder,
                source_id: fragment.values.sourceId,
                locator: fragment.values.locator,
                source_relation: fragment.values.sourceRelation,
                byte_role: fragment.values.byteRole,
                fragment_hash: fragment.values.fragmentHash,
            })),
        };
    });
    if (primaryPacketEvidence.some((entry) => entry === null))
        return null;
    const sourceBytes = readFileSync(sourcePath);
    const criteriaBytes = readFileSync(model.criteria.path);
    const payload = {
        format: SOURCE_WALK_REVIEW_BASIS_FORMAT,
        source_id: sourceId,
        source_hash: `sha256:${sha256(sourceBytes)}`,
        extraction_criteria_digest: `sha256:${sha256(criteriaBytes)}`,
        extraction_criteria_byte_length: criteriaBytes.byteLength,
        primary_walk_intervals: model.sourceWalk.intervals
            .filter((row) => row.values.sourceId === sourceId)
            .map((row) => ({
            walk_id: row.values.walkId,
            source_id: row.values.sourceId,
            start_byte: row.values.startByte,
            end_byte: row.values.endByte,
            outcome: row.values.outcome,
            packet_ids: row.values.packetIds,
            criterion_ref: row.values.criterionRef,
            producer_invocation_id: row.values.producerInvocationId,
            closure_state: row.values.closureState,
            reason: row.values.reason,
            closure_note: row.values.closureNote,
        })),
        primary_extraction_events: primaryEvents.map((row) => ({
            event_id: row.values.eventId,
            source_id: row.values.sourceId,
            start_byte: row.values.startByte,
            end_byte: row.values.endByte,
            shared_position_key: row.values.sharedPositionKey,
            event_ordinal: row.values.eventOrdinal,
            packet_id: row.values.packetId,
            origin: row.values.origin,
            producer_invocation_id: row.values.producerInvocationId,
            status: row.values.status,
        })),
        primary_packet_exact_evidence: primaryPacketEvidence,
        terminal_primary_cursor: {
            cursor_id: cursor.values.cursorId,
            source_id: cursor.values.sourceId,
            byte_offset: cursor.values.byteOffset,
            shared_position_key: cursor.values.sharedPositionKey,
            next_event_ordinal: cursor.values.nextEventOrdinal,
            predecessor_walk_id: cursor.values.predecessorWalkId,
            predecessor_event_id: cursor.values.predecessorEventId,
            source_hash: cursor.values.sourceHash,
            reason: cursor.values.reason,
        },
    };
    return `sha256:${sha256(Buffer.from(JSON.stringify(payload), 'utf8'))}`;
}
function checkSourceWalk(results, model) {
    results.run('K2.14', 'source walk, gap review, and resume accounting', (fail) => {
        const version = model.manifest?.runFormatVersion || '';
        const walk = model.sourceWalk;
        const structurePresent = Boolean(model.sourceWalkDocument
            || walk.format
            || walk.positionFormat
            || sourceWalkTablesPresent(model));
        if (!usesSourceWalk(version)) {
            if (structurePresent) {
                fail(`run format ${version || '(pre-versioned)'} must not be reinterpreted as `
                    + `${SOURCE_WALK_FORMAT}`);
            }
            if (version
                && !SUPPORTED_RUN_FORMAT_VERSIONS.includes(version)) {
                fail(`source-walk activation cannot determine unsupported run_format_version `
                    + `"${version}"`);
            }
            return `source walk is not applicable to run format ${version || '(pre-versioned)'}`;
        }
        if (!distillingArtifactsApply(model) && !structurePresent) {
            return `source walk is not applicable before DISTILLING in run format ${version}`;
        }
        if (!model.sourceWalkDocument) {
            fail(`run format ${version} requires ledgers/source-walk.md once S2 begins`);
            return 'source-walk structure is valid';
        }
        const walkFormatCount = model.sourceWalkDocument.lines.filter((line) => /^\s*-\s*source[_ -]walk[_ -]format\s*:/i.test(line)).length;
        const positionFormatCount = model.sourceWalkDocument.lines.filter((line) => /^\s*-\s*source[_ -]position[_ -]format\s*:/i.test(line)).length;
        if (walkFormatCount !== 1 || walk.format !== SOURCE_WALK_FORMAT) {
            fail(`run format ${version} requires source_walk_format ${SOURCE_WALK_FORMAT} `
                + `exactly once`);
        }
        if (positionFormatCount !== 1 || walk.positionFormat !== SOURCE_POSITION_FORMAT) {
            fail(`run format ${version} requires source_position_format `
                + `${SOURCE_POSITION_FORMAT} exactly once`);
        }
        if (!walk.intervalTable) {
            fail('primary walk interval table is missing or has the wrong header');
        }
        if (!walk.eventTable) {
            fail('extraction event table is missing or has the wrong header');
        }
        if (!walk.cursorTable) {
            fail('resume cursor table is missing or has the wrong header');
        }
        if (!walk.gapReviewTable) {
            fail('fresh gap-review table is missing or has the wrong header');
        }
        if (!walk.completionTable) {
            fail('per-source completion table is missing or has the wrong header');
        }
        const sources = makeIndexes(model).SRC;
        const packets = makeIndexes(model).PKT;
        const sourceData = new Map();
        for (const source of model.corpus.sources) {
            const sourceId = source.values.sourceId;
            const sourcePath = sourceFilePath(model.runDir, source.values.locus);
            if (!sourcePath || !existsPath(sourcePath)) {
                fail(`${sourceId || 'source row'} locus "${source.values.locus}" `
                    + 'is not a readable frozen source file');
                continue;
            }
            const bytes = readFileSync(sourcePath);
            const actualHash = sha256(bytes);
            const declaredHash = exactSha256(source.values.contentHash);
            if (!declaredHash) {
                fail(`${sourceId} content_hash must be sha256:<lowercase hex>`);
            }
            else if (declaredHash !== actualHash) {
                fail(`${sourceId} content_hash does not match the frozen source bytes`);
            }
            let validUtf8 = true;
            try {
                new TextDecoder('utf-8', { fatal: true }).decode(bytes);
            }
            catch {
                validUtf8 = false;
                fail(`${sourceId} is not valid UTF-8 and cannot use ${SOURCE_POSITION_FORMAT}`);
            }
            sourceData.set(sourceId, {
                source,
                bytes,
                hash: `sha256:${actualHash}`,
                validUtf8,
            });
        }
        const admissionCriteria = new Set();
        const exclusionCriteria = new Set();
        if (model.criteria) {
            const admissionTable = findTable(model.criteria.tables, [
                '#',
                'criterion',
                'example span that qualifies',
            ]);
            const exclusionTable = findTable(model.criteria.tables, [
                'class',
                'description',
                'example',
            ]);
            for (const row of admissionTable?.rows || []) {
                const value = row.cells[0]?.replace(/\*/g, '').trim() || '';
                if (/^[1-9]\d*$/.test(value))
                    admissionCriteria.add(value);
            }
            for (const row of exclusionTable?.rows || []) {
                const value = row.cells[0]?.replace(/\*/g, '').trim() || '';
                if (value)
                    exclusionCriteria.add(value);
            }
        }
        const exactPackets = new Set();
        for (const record of model.exactEvidence.records) {
            if (record.values.evidenceState !== 'exact')
                continue;
            const ids = packetIdList(record.values.packetIds);
            if (ids)
                ids.forEach((id) => exactPackets.add(id));
        }
        const exactFragmentPositionsByPacket = new Map();
        for (const fragment of model.exactEvidence.fragments) {
            const { fragmentKey, packetId, sourceId, locator, } = fragment.values;
            const source = sources.get(sourceId);
            const sourcePath = source ? sourceFilePath(model.runDir, source.values.locus) : null;
            const scheme = source?.values.scheme.replace(/`/g, '').trim() || '';
            const locatorParts = parseMdLineLocator(locator);
            let position;
            if (scheme !== 'md-lines') {
                position = {
                    fragmentKey,
                    sourceId,
                    start: null,
                    end: null,
                    mappingError: `locator scheme ${scheme || '(blank)'} is unsupported`,
                };
            }
            else if (!sourcePath || !existsPath(sourcePath)) {
                position = {
                    fragmentKey,
                    sourceId,
                    start: null,
                    end: null,
                    mappingError: 'frozen source locus is unreadable',
                };
            }
            else if (!locatorParts) {
                position = {
                    fragmentKey,
                    sourceId,
                    start: null,
                    end: null,
                    mappingError: `locator ${locator || '(blank)'} is not mechanically mappable`,
                };
            }
            else {
                const span = mdLineSpan(sourcePath, locatorParts.start, locatorParts.end);
                position = {
                    fragmentKey,
                    sourceId,
                    start: span?.startByte ?? null,
                    end: span?.endByte ?? null,
                    mappingError: span?.bytes ? '' : `locator ${locator} is outside the frozen source`,
                };
            }
            const group = exactFragmentPositionsByPacket.get(packetId) || [];
            group.push(position);
            exactFragmentPositionsByPacket.set(packetId, group);
        }
        const intervalIds = new Map();
        const intervalsBySource = new Map();
        for (const row of walk.intervals) {
            const { walkId, sourceId, startByte, endByte, outcome, packetIds: packetIdsValue, criterionRef, producerInvocationId, closureState, reason, closureNote, } = row.values;
            if (!/^WLK-\d+$/.test(walkId)) {
                fail(`${walkId || 'walk row'} walk_id must be WLK-<digits> at ${location(row)}`);
            }
            if (intervalIds.has(walkId)) {
                fail(`${walkId || 'walk row'} is defined more than once at ${location(row)}`);
            }
            const source = sources.get(sourceId);
            const data = sourceData.get(sourceId);
            if (!source) {
                fail(`${walkId || 'walk row'} source ${sourceId || '(blank)'} does not resolve`);
            }
            const start = canonicalNonnegativeInteger(startByte);
            const end = canonicalNonnegativeInteger(endByte);
            if (start === null) {
                fail(`${walkId || 'walk row'} start_byte must be a canonical non-negative integer`);
            }
            if (end === null) {
                fail(`${walkId || 'walk row'} end_byte must be a canonical non-negative integer`);
            }
            if (start !== null && end !== null) {
                if (end <= start) {
                    fail(`${walkId || 'walk row'} interval ${start}..${end} is reversed or empty`);
                }
                if (data && (start > data.bytes.byteLength || end > data.bytes.byteLength)) {
                    fail(`${walkId || 'walk row'} interval ${start}..${end} exceeds `
                        + `source length ${data.bytes.byteLength}`);
                }
                if (data?.validUtf8) {
                    if (!utf8Boundary(data.bytes, start)) {
                        fail(`${walkId || 'walk row'} start_byte ${start} splits a UTF-8 code point`);
                    }
                    if (!utf8Boundary(data.bytes, end)) {
                        fail(`${walkId || 'walk row'} end_byte ${end} splits a UTF-8 code point`);
                    }
                }
            }
            if (!SOURCE_WALK_OUTCOMES.includes(outcome)) {
                fail(`${walkId || 'walk row'} outcome "${outcome || '(blank)'}" is unsupported`);
            }
            if (!/^[A-Za-z][A-Za-z0-9._-]*$/.test(producerInvocationId)) {
                fail(`${walkId || 'walk row'} producer_invocation_id is missing or malformed`);
            }
            let declaredPacketIds = [];
            if (outcome === 'admitted') {
                const parsed = packetIdList(packetIdsValue);
                if (!parsed) {
                    fail(`${walkId || 'walk row'} admitted interval requires packet_ids`);
                }
                else {
                    declaredPacketIds = parsed;
                    for (const packetId of parsed) {
                        if (!packets.has(packetId)) {
                            fail(`${walkId || 'walk row'} references missing packet ${packetId}`);
                        }
                    }
                }
                const criterion = criterionRef.match(/^admission:([1-9]\d*)$/)?.[1];
                if (!criterion || !admissionCriteria.has(criterion)) {
                    fail(`${walkId || 'walk row'} admission criterion `
                        + `"${criterion || criterionRef || '(blank)'}" does not resolve`);
                }
                if (closureState !== 'closed') {
                    fail(`${walkId || 'walk row'} admitted interval closure_state must be closed`);
                }
            }
            else {
                if (packetIdsValue !== 'none') {
                    fail(`${walkId || 'walk row'} ${outcome || 'non-admitted'} interval must use packet_ids none`);
                }
                if (outcome === 'excluded') {
                    const criterion = criterionRef.match(/^exclusion:(.+)$/)?.[1] || '';
                    if (!criterion || !exclusionCriteria.has(criterion)) {
                        fail(`${walkId || 'walk row'} exclusion criterion `
                            + `"${criterion || criterionRef || '(blank)'}" does not resolve`);
                    }
                    if (closureState !== 'closed') {
                        fail(`${walkId || 'walk row'} excluded interval closure_state must be closed`);
                    }
                }
                else if (criterionRef !== 'none') {
                    fail(`${walkId || 'walk row'} ${outcome || 'non-admitted'} interval criterion_ref must be none`);
                }
                if (outcome === 'no-candidate-observed' && closureState !== 'closed') {
                    fail(`${walkId || 'walk row'} no-candidate-observed interval closure_state must be closed`);
                }
                if (outcome === 'deferred') {
                    if (!['open', 'resolved'].includes(closureState)) {
                        fail(`${walkId || 'walk row'} deferred interval closure_state must be open or resolved`);
                    }
                    if (!substantiveValue(reason)) {
                        fail(`${walkId || 'walk row'} deferred interval requires a nonempty reason`);
                    }
                    if (closureState === 'resolved' && !substantiveValue(closureNote)) {
                        fail(`${walkId || 'walk row'} resolved deferred interval requires a closure_note`);
                    }
                }
                if (outcome === 'unsupported') {
                    if (closureState !== 'open') {
                        fail(`${walkId || 'walk row'} unsupported interval must remain open`);
                    }
                    if (!substantiveValue(reason)) {
                        fail(`${walkId || 'walk row'} unsupported interval requires a nonempty reason`);
                    }
                }
            }
            if (start !== null && end !== null) {
                const parsed = { row, start, end, packetIds: declaredPacketIds };
                if (walkId)
                    intervalIds.set(walkId, parsed);
                const group = intervalsBySource.get(sourceId) || [];
                group.push(parsed);
                intervalsBySource.set(sourceId, group);
            }
        }
        const coveredEndBySource = new Map();
        for (const source of model.corpus.sources) {
            const sourceId = source.values.sourceId;
            const intervals = intervalsBySource.get(sourceId) || [];
            let expected = 0;
            for (const [index, interval] of intervals.entries()) {
                const { walkId } = interval.row.values;
                if (index === 0 && interval.start !== 0) {
                    fail(`${sourceId} walk must begin at byte 0; found ${interval.start}`);
                }
                else if (index > 0 && interval.start > expected) {
                    fail(`${sourceId} walk has a hole before ${walkId || 'walk row'}: `
                        + `expected ${expected}, found ${interval.start}`);
                }
                else if (index > 0 && interval.start < expected) {
                    fail(`${sourceId} walk overlaps before ${walkId || 'walk row'}: `
                        + `prior end ${expected}, found ${interval.start}`);
                }
                expected = Math.max(expected, interval.end);
            }
            coveredEndBySource.set(sourceId, expected);
        }
        const eventIds = new Map();
        const eventsBySource = new Map();
        const eventsByPacket = new Map();
        const eventsBySharedPosition = new Map();
        for (const row of walk.events) {
            const { eventId, sourceId, startByte, endByte, sharedPositionKey, eventOrdinal, packetId, origin, producerInvocationId, status, } = row.values;
            if (!/^EVT-\d+$/.test(eventId)) {
                fail(`${eventId || 'event row'} event_id must be EVT-<digits> at ${location(row)}`);
            }
            if (eventIds.has(eventId)) {
                fail(`${eventId || 'event row'} is defined more than once at ${location(row)}`);
            }
            const data = sourceData.get(sourceId);
            if (!sources.has(sourceId)) {
                fail(`${eventId || 'event row'} source ${sourceId || '(blank)'} does not resolve`);
            }
            const start = canonicalNonnegativeInteger(startByte);
            const end = canonicalNonnegativeInteger(endByte);
            const ordinal = canonicalNonnegativeInteger(eventOrdinal);
            if (start === null || end === null) {
                fail(`${eventId || 'event row'} event coordinates must be canonical non-negative integers`);
            }
            else {
                if (end <= start)
                    fail(`${eventId || 'event row'} interval ${start}..${end} is reversed or empty`);
                if (data && (start > data.bytes.byteLength || end > data.bytes.byteLength)) {
                    fail(`${eventId || 'event row'} interval ${start}..${end} exceeds `
                        + `source length ${data.bytes.byteLength}`);
                }
                if (data?.validUtf8) {
                    if (!utf8Boundary(data.bytes, start)) {
                        fail(`${eventId || 'event row'} start_byte ${start} splits a UTF-8 code point`);
                    }
                    if (!utf8Boundary(data.bytes, end)) {
                        fail(`${eventId || 'event row'} end_byte ${end} splits a UTF-8 code point`);
                    }
                }
            }
            if (!/^SP-\d+$/.test(sharedPositionKey)) {
                fail(`${eventId || 'event row'} shared_position_key must be SP-<digits>`);
            }
            if (ordinal === null || ordinal < 1) {
                fail(`${eventId || 'event row'} event_ordinal must be a positive integer`);
            }
            if (!['primary', 'gap-reconciliation'].includes(origin)) {
                fail(`${eventId || 'event row'} origin must be primary or gap-reconciliation`);
            }
            if (!/^[A-Za-z][A-Za-z0-9._-]*$/.test(producerInvocationId)) {
                fail(`${eventId || 'event row'} producer_invocation_id is missing or malformed`);
            }
            if (!['committed', 'pending'].includes(status)) {
                fail(`${eventId || 'event row'} status must be committed or pending`);
            }
            const packet = packets.get(packetId);
            if (!packet) {
                fail(`${eventId || 'event row'} packet ${packetId || '(blank)'} does not resolve`);
            }
            else {
                if (packet.values.sourceId !== sourceId) {
                    fail(`${eventId || 'event row'} packet ${packetId} belongs to ${packet.values.sourceId}`);
                }
                if (!exactPackets.has(packetId)) {
                    fail(`${packetId} lacks a Slice-1 exact evidence record`);
                }
                const fragmentPositions = exactFragmentPositionsByPacket.get(packetId) || [];
                const unmapped = fragmentPositions.find((position) => (position.start === null || position.end === null));
                if (fragmentPositions.length === 0) {
                    fail(`${eventId || 'event row'} packet ${packetId} has no exact fragment `
                        + 'for source-walk position binding');
                }
                else if (unmapped) {
                    fail(`${eventId || 'event row'} cannot verify packet ${packetId} exact-evidence `
                        + `position at ${unmapped.fragmentKey || 'fragment row'}: ${unmapped.mappingError}`);
                }
                else if (start !== null && end !== null) {
                    const containingFragments = fragmentPositions.filter((position) => (position.sourceId === sourceId
                        && position.start !== null
                        && position.end !== null
                        && start >= position.start
                        && end <= position.end));
                    if (containingFragments.length !== 1) {
                        fail(`${eventId || 'event row'} interval ${start}..${end} must be contained `
                            + `in exactly one exact fragment for packet ${packetId}; found `
                            + `${containingFragments.length}`);
                    }
                }
            }
            if (start !== null && end !== null && ordinal !== null) {
                const parsed = { row, start, end, ordinal };
                if (eventId)
                    eventIds.set(eventId, parsed);
                const sourceEvents = eventsBySource.get(sourceId) || [];
                sourceEvents.push(parsed);
                eventsBySource.set(sourceId, sourceEvents);
                const packetEvents = eventsByPacket.get(packetId) || [];
                packetEvents.push(parsed);
                eventsByPacket.set(packetId, packetEvents);
                const shared = eventsBySharedPosition.get(sharedPositionKey) || [];
                shared.push(parsed);
                eventsBySharedPosition.set(sharedPositionKey, shared);
                const containing = (intervalsBySource.get(sourceId) || []).filter((interval) => start >= interval.start && end <= interval.end);
                if (containing.length !== 1) {
                    fail(`${eventId || 'event row'} must lie within exactly one primary walk interval`);
                }
                else {
                    const interval = containing[0];
                    if (origin === 'primary') {
                        if (interval.row.values.outcome !== 'admitted'
                            || !interval.packetIds.includes(packetId)) {
                            fail(`${eventId || 'event row'} primary event is not declared by its admitted interval`);
                        }
                        if (interval.row.values.producerInvocationId !== producerInvocationId) {
                            fail(`${eventId || 'event row'} primary producer differs from its walk interval`);
                        }
                    }
                    else if (!['admitted', 'no-candidate-observed'].includes(interval.row.values.outcome)) {
                        fail(`${eventId || 'event row'} gap reconciliation conflicts with `
                            + `${interval.row.values.outcome || 'blank'} primary accounting`);
                    }
                }
            }
        }
        for (const [packetId, packetEvents] of eventsByPacket) {
            if (packetEvents.length !== 1) {
                fail(`${packetId || 'packet'} is bound to ${packetEvents.length} extraction events`);
            }
        }
        for (const packet of model.packets) {
            if (!eventsByPacket.has(packet.values.packetId)) {
                fail(`${packet.values.packetId} has no source-walk extraction event`);
            }
        }
        for (const interval of intervalIds.values()) {
            if (interval.row.values.outcome !== 'admitted')
                continue;
            for (const packetId of interval.packetIds) {
                const event = eventsByPacket.get(packetId)?.[0];
                if (!event || event.row.values.origin !== 'primary') {
                    fail(`${interval.row.values.walkId || 'walk row'} packet ${packetId} `
                        + 'lacks one primary extraction event');
                }
            }
        }
        for (const sourceEvents of eventsBySource.values()) {
            for (let leftIndex = 0; leftIndex < sourceEvents.length; leftIndex++) {
                const left = sourceEvents[leftIndex];
                for (let rightIndex = leftIndex + 1; rightIndex < sourceEvents.length; rightIndex++) {
                    const right = sourceEvents[rightIndex];
                    const overlaps = left.start < right.end && right.start < left.end;
                    if (!overlaps)
                        continue;
                    const shared = (left.start === right.start
                        && left.end === right.end
                        && left.row.values.sharedPositionKey === right.row.values.sharedPositionKey);
                    if (!shared) {
                        fail(`${left.row.values.eventId} and ${right.row.values.eventId} overlap `
                            + 'without one exact shared-position group');
                    }
                }
            }
        }
        for (const [key, sharedEvents] of eventsBySharedPosition) {
            const first = sharedEvents[0];
            const samePosition = sharedEvents.every((event) => (event.row.values.sourceId === first.row.values.sourceId
                && event.start === first.start
                && event.end === first.end));
            if (!samePosition) {
                fail(`${key || 'shared position'} spans more than one source position`);
            }
            const ordinals = sharedEvents.map((event) => event.ordinal).sort((a, b) => a - b);
            const validOrdinals = (new Set(ordinals).size === ordinals.length
                && ordinals.every((ordinal, index) => ordinal === index + 1));
            if (!validOrdinals) {
                fail(`${key || 'shared position'} event ordinals must be unique and contiguous 1..${sharedEvents.length}`);
            }
        }
        const cursorIds = new Map();
        const cursorsBySource = new Map();
        const lastCursorOrdinalBySharedPosition = new Map();
        for (const row of walk.cursors) {
            const { cursorId, sourceId, byteOffset, sharedPositionKey, nextEventOrdinal, predecessorWalkId, predecessorEventId, sourceHash, reason, } = row.values;
            if (!/^CUR-\d+$/.test(cursorId)) {
                fail(`${cursorId || 'cursor row'} cursor_id must be CUR-<digits> at ${location(row)}`);
            }
            if (cursorIds.has(cursorId)) {
                fail(`${cursorId || 'cursor row'} is defined more than once at ${location(row)}`);
            }
            const data = sourceData.get(sourceId);
            if (!sources.has(sourceId)) {
                fail(`${cursorId || 'cursor row'} source ${sourceId || '(blank)'} does not resolve`);
            }
            const offset = canonicalNonnegativeInteger(byteOffset);
            if (offset === null) {
                fail(`${cursorId || 'cursor row'} byte_offset must be a canonical non-negative integer`);
            }
            else if (data) {
                if (offset > data.bytes.byteLength) {
                    fail(`${cursorId || 'cursor row'} byte_offset ${offset} exceeds `
                        + `source length ${data.bytes.byteLength}`);
                }
                else if (data.validUtf8 && !utf8Boundary(data.bytes, offset)) {
                    fail(`${cursorId || 'cursor row'} byte_offset ${offset} splits a UTF-8 code point`);
                }
            }
            if (data && sourceHash !== data.hash) {
                fail(`${cursorId || 'cursor row'} source_hash does not match frozen ${sourceId}`);
            }
            if (!SOURCE_WALK_CURSOR_REASONS.includes(reason)) {
                fail(`${cursorId || 'cursor row'} reason must be one of `
                    + SOURCE_WALK_CURSOR_REASONS.join(', '));
            }
            const predecessorWalk = predecessorWalkId === 'none'
                ? null
                : intervalIds.get(predecessorWalkId);
            if (predecessorWalkId !== 'none' && !predecessorWalk) {
                fail(`${cursorId || 'cursor row'} predecessor walk ${predecessorWalkId} does not resolve`);
            }
            else if (predecessorWalk && predecessorWalk.row.values.sourceId !== sourceId) {
                fail(`${cursorId || 'cursor row'} predecessor walk belongs to another source`);
            }
            const predecessorEvent = predecessorEventId === 'none'
                ? null
                : eventIds.get(predecessorEventId);
            if (predecessorEventId !== 'none' && !predecessorEvent) {
                fail(`${cursorId || 'cursor row'} predecessor event ${predecessorEventId} does not resolve`);
            }
            else if (predecessorEvent && predecessorEvent.row.values.sourceId !== sourceId) {
                fail(`${cursorId || 'cursor row'} predecessor event belongs to another source`);
            }
            if (sharedPositionKey === 'none') {
                if (nextEventOrdinal !== 'none') {
                    fail(`${cursorId || 'cursor row'} without a shared position must use next_event_ordinal none`);
                }
                if (offset === 0
                    && (predecessorWalkId !== 'none' || predecessorEventId !== 'none')) {
                    fail(`${cursorId || 'cursor row'} at source origin must not claim a predecessor`);
                }
                if (offset !== null && offset > 0 && predecessorWalk?.end !== offset) {
                    fail(`${cursorId || 'cursor row'} predecessor walk must end at next byte `
                        + `${offset}`);
                }
                if (offset !== null
                    && predecessorEvent
                    && predecessorEvent.end !== offset) {
                    fail(`${cursorId || 'cursor row'} predecessor event must end at next byte `
                        + `${offset}`);
                }
            }
            else {
                const shared = eventsBySharedPosition.get(sharedPositionKey);
                const nextOrdinal = canonicalNonnegativeInteger(nextEventOrdinal);
                if (!shared || shared.length === 0) {
                    fail(`${cursorId || 'cursor row'} shared position ${sharedPositionKey} does not resolve`);
                }
                else {
                    const first = shared[0];
                    if (first.row.values.sourceId !== sourceId) {
                        fail(`${cursorId || 'cursor row'} shared position belongs to another source`);
                    }
                    if (offset !== null && offset !== first.start) {
                        fail(`${cursorId || 'cursor row'} shared-position cursor must remain at byte `
                            + `${first.start}`);
                    }
                    if (offset !== null
                        && (!predecessorWalk
                            || predecessorWalk.start > offset
                            || predecessorWalk.end <= offset)) {
                        fail(`${cursorId || 'cursor row'} predecessor walk must contain the `
                            + 'shared position');
                    }
                    if (nextOrdinal === null || nextOrdinal < 2 || nextOrdinal > shared.length) {
                        fail(`${cursorId || 'cursor row'} next_event_ordinal must identify a pending `
                            + `shared event in 2..${shared.length}`);
                    }
                    else {
                        const expectedPredecessor = shared.find((event) => event.ordinal === nextOrdinal - 1);
                        if (!expectedPredecessor
                            || predecessorEventId !== expectedPredecessor.row.values.eventId) {
                            fail(`${cursorId || 'cursor row'} predecessor event does not precede `
                                + `shared ordinal ${nextOrdinal}`);
                        }
                    }
                }
            }
            if (offset !== null) {
                if (offset > 0 && predecessorWalkId === 'none') {
                    fail(`${cursorId || 'cursor row'} after source origin requires a predecessor walk`);
                }
                for (const interval of intervalsBySource.get(sourceId) || []) {
                    if (interval.start < offset && interval.row.values.closureState === 'open') {
                        fail(`${cursorId || 'cursor row'} jumps over open interval `
                            + `${interval.row.values.walkId}`);
                    }
                }
                if (sharedPositionKey === 'none') {
                    for (const event of eventsBySource.get(sourceId) || []) {
                        if (event.start < offset && event.row.values.status === 'pending') {
                            fail(`${cursorId || 'cursor row'} jumps over pending event `
                                + `${event.row.values.eventId}`);
                        }
                    }
                }
                const parsed = { row, offset };
                if (cursorId)
                    cursorIds.set(cursorId, parsed);
                const group = cursorsBySource.get(sourceId) || [];
                const previous = group.at(-1);
                if (previous && offset < previous.offset) {
                    fail(`${cursorId || 'cursor row'} cursor moves backwards from `
                        + `${previous.offset} to ${offset}`);
                }
                if (sharedPositionKey !== 'none') {
                    const previousOrdinal = lastCursorOrdinalBySharedPosition.get(sharedPositionKey);
                    const currentOrdinal = canonicalNonnegativeInteger(nextEventOrdinal);
                    if (previousOrdinal !== undefined
                        && currentOrdinal !== null
                        && currentOrdinal < previousOrdinal) {
                        fail(`${cursorId || 'cursor row'} shared-position cursor ordinal regresses `
                            + `from ${previousOrdinal} to ${currentOrdinal} at ${sharedPositionKey}`);
                    }
                    if (currentOrdinal !== null) {
                        lastCursorOrdinalBySharedPosition.set(sharedPositionKey, Math.max(previousOrdinal || 0, currentOrdinal));
                    }
                }
                group.push(parsed);
                cursorsBySource.set(sourceId, group);
            }
        }
        const gapReviewIds = new Map();
        const gapReviewsBySource = new Map();
        const reconciliationEvents = new Map();
        for (const row of walk.gapReviews) {
            const { gapReviewId, sourceId, producerInvocationId, reviewerInvocationId, reviewBasisCursorId, reviewBasisDigest, result, candidateStartByte, candidateEndByte, proposedPacketId, reconciliationEventId, status, note, } = row.values;
            if (!/^GAP-\d+$/.test(gapReviewId)) {
                fail(`${gapReviewId || 'gap-review row'} gap_review_id must be GAP-<digits> at ${location(row)}`);
            }
            if (gapReviewIds.has(gapReviewId)) {
                fail(`${gapReviewId || 'gap-review row'} is defined more than once at ${location(row)}`);
            }
            else if (gapReviewId) {
                gapReviewIds.set(gapReviewId, row);
            }
            if (!sources.has(sourceId)) {
                fail(`${gapReviewId || 'gap-review row'} source ${sourceId || '(blank)'} does not resolve`);
            }
            const primaryProducers = new Set((intervalsBySource.get(sourceId) || []).map((interval) => interval.row.values.producerInvocationId));
            if (!primaryProducers.has(producerInvocationId)) {
                fail(`${gapReviewId || 'gap-review row'} producer invocation does not resolve to the primary walk`);
            }
            if (reviewerInvocationId === producerInvocationId
                || primaryProducers.has(reviewerInvocationId)) {
                fail(`${gapReviewId || 'gap-review row'} reviewer invocation must differ `
                    + 'from the primary producer');
            }
            if (!/^[A-Za-z][A-Za-z0-9._-]*$/.test(reviewerInvocationId)) {
                fail(`${gapReviewId || 'gap-review row'} reviewer_invocation_id is missing or malformed`);
            }
            const reviewBasisCursor = cursorIds.get(reviewBasisCursorId);
            const data = sourceData.get(sourceId);
            if (!reviewBasisCursor) {
                fail(`${gapReviewId || 'gap-review row'} review basis cursor `
                    + `${reviewBasisCursorId || '(blank)'} does not resolve`);
            }
            else {
                const predecessorWalk = intervalIds.get(reviewBasisCursor.row.values.predecessorWalkId);
                const predecessorEventId = reviewBasisCursor.row.values.predecessorEventId;
                const predecessorEvent = predecessorEventId === 'none'
                    ? null
                    : eventIds.get(predecessorEventId) || null;
                if (reviewBasisCursor.row.values.sourceId !== sourceId
                    || !data
                    || reviewBasisCursor.offset !== data.bytes.byteLength
                    || reviewBasisCursor.row.values.sharedPositionKey !== 'none'
                    || reviewBasisCursor.row.values.nextEventOrdinal !== 'none'
                    || !predecessorWalk
                    || predecessorWalk.row.values.sourceId !== sourceId
                    || predecessorWalk.end !== data.bytes.byteLength
                    || (predecessorEvent !== null
                        && (predecessorEvent.row.values.origin !== 'primary'
                            || predecessorEvent.row.values.status !== 'committed'))) {
                    fail(`${gapReviewId || 'gap-review row'} review_basis_cursor_id must identify `
                        + 'the terminal primary source-end cursor');
                }
            }
            if (!/^sha256:[a-f0-9]{64}$/.test(reviewBasisDigest)) {
                fail(`${gapReviewId || 'gap-review row'} review_basis_digest must be `
                    + 'sha256:<lowercase hex>');
            }
            const recomputedReviewBasisDigest = sourceWalkReviewBasisDigest(model, sourceId, reviewBasisCursorId);
            if (!recomputedReviewBasisDigest) {
                fail(`${gapReviewId || 'gap-review row'} review basis cannot be mechanically recomputed`);
            }
            else if (reviewBasisDigest !== recomputedReviewBasisDigest) {
                fail(`${gapReviewId || 'gap-review row'} review_basis_digest does not match `
                    + `the current primary review basis; expected ${recomputedReviewBasisDigest}`);
            }
            if (!GAP_REVIEW_RESULTS.includes(result)) {
                fail(`${gapReviewId || 'gap-review row'} result "${result || '(blank)'}" is unsupported`);
            }
            if (!substantiveValue(note)) {
                fail(`${gapReviewId || 'gap-review row'} note is required`);
            }
            if (result === 'gap-candidate-found') {
                const start = canonicalNonnegativeInteger(candidateStartByte);
                const end = canonicalNonnegativeInteger(candidateEndByte);
                if (start === null || end === null || end <= start) {
                    fail(`${gapReviewId || 'gap-review row'} candidate coordinates are invalid`);
                }
                else if (data) {
                    if (end > data.bytes.byteLength) {
                        fail(`${gapReviewId || 'gap-review row'} candidate exceeds source length`);
                    }
                    if (data.validUtf8
                        && (!utf8Boundary(data.bytes, start) || !utf8Boundary(data.bytes, end))) {
                        fail(`${gapReviewId || 'gap-review row'} candidate splits a UTF-8 code point`);
                    }
                }
                if (!['open', 'reconciled'].includes(status)) {
                    fail(`${gapReviewId || 'gap-review row'} gap candidate status must be open or reconciled`);
                }
                else if (status === 'open') {
                    if (proposedPacketId !== 'none' || reconciliationEventId !== 'none') {
                        fail(`${gapReviewId || 'gap-review row'} open candidate must use `
                            + 'proposed_packet_id none and reconciliation_event_id none');
                    }
                }
                else {
                    const packet = packets.get(proposedPacketId);
                    if (!packet) {
                        fail(`${gapReviewId || 'gap-review row'} proposed packet ${proposedPacketId || '(blank)'} does not resolve`);
                    }
                    else if (packet.values.sourceId !== sourceId
                        || !exactPackets.has(proposedPacketId)) {
                        fail(`${gapReviewId || 'gap-review row'} proposed packet lacks valid Slice-1 exact evidence`);
                    }
                    const event = eventIds.get(reconciliationEventId);
                    if (!event) {
                        fail(`${gapReviewId || 'gap-review row'} reconciliation event ${reconciliationEventId || '(blank)'} does not resolve`);
                    }
                    else {
                        if (event.row.values.origin !== 'gap-reconciliation'
                            || event.row.values.sourceId !== sourceId
                            || event.row.values.packetId !== proposedPacketId
                            || start === null
                            || end === null
                            || event.start !== start
                            || event.end !== end) {
                            fail(`${gapReviewId || 'gap-review row'} reconciliation event does not match the proposed candidate`);
                        }
                        if (event.row.values.status !== 'committed') {
                            fail(`${gapReviewId || 'gap-review row'} reconciled candidate event is not committed`);
                        }
                        const linked = reconciliationEvents.get(reconciliationEventId) || [];
                        linked.push(row);
                        reconciliationEvents.set(reconciliationEventId, linked);
                    }
                }
            }
            else {
                if (candidateStartByte !== 'none'
                    || candidateEndByte !== 'none'
                    || proposedPacketId !== 'none'
                    || reconciliationEventId !== 'none') {
                    fail(`${gapReviewId || 'gap-review row'} ${result || 'non-candidate'} result must not claim a candidate`);
                }
                if (result === 'no-gap-candidate-found' && status !== 'closed') {
                    fail(`${gapReviewId || 'gap-review row'} no-gap result status must be closed`);
                }
                if (result === 'cannot-determine' && status !== 'blocked') {
                    fail(`${gapReviewId || 'gap-review row'} cannot-determine status must be blocked`);
                }
            }
            const group = gapReviewsBySource.get(sourceId) || [];
            group.push(row);
            gapReviewsBySource.set(sourceId, group);
        }
        for (const event of eventIds.values()) {
            if (event.row.values.origin !== 'gap-reconciliation')
                continue;
            const linked = reconciliationEvents.get(event.row.values.eventId) || [];
            if (linked.length !== 1) {
                fail(`${event.row.values.eventId} gap-reconciliation event is linked by `
                    + `${linked.length} gap-review rows`);
            }
        }
        const completionsBySource = new Map();
        for (const completion of walk.completions) {
            const { sourceId, sourceHash, sourceLengthBytes, finalCursorId, gapReviewIds: gapReviewIdsValue, completionState, declaredBy, } = completion.values;
            if (completionsBySource.has(sourceId)) {
                fail(`${sourceId || 'completion row'} has more than one final traversal state`);
            }
            else if (sourceId) {
                completionsBySource.set(sourceId, completion);
            }
            const data = sourceData.get(sourceId);
            if (!sources.has(sourceId)) {
                fail(`${sourceId || 'completion row'} completion source does not resolve`);
            }
            if (data && sourceHash !== data.hash) {
                fail(`${sourceId || 'completion row'} completion source_hash does not match frozen bytes`);
            }
            const sourceLength = canonicalNonnegativeInteger(sourceLengthBytes);
            if (sourceLength === null) {
                fail(`${sourceId || 'completion row'} source_length_bytes must be a canonical non-negative integer`);
            }
            else if (data && sourceLength !== data.bytes.byteLength) {
                fail(`${sourceId || 'completion row'} source_length_bytes ${sourceLength} `
                    + `does not match ${data.bytes.byteLength}`);
            }
            if (!['complete', 'blocked'].includes(completionState)) {
                fail(`${sourceId || 'completion row'} completion_state must be complete or blocked`);
            }
            if (!substantiveValue(declaredBy)) {
                fail(`${sourceId || 'completion row'} declared_by is required`);
            }
            const finalCursor = cursorIds.get(finalCursorId);
            if (!finalCursor) {
                fail(`${sourceId || 'completion row'} final cursor ${finalCursorId || '(blank)'} does not resolve`);
            }
            else if (finalCursor.row.values.sourceId !== sourceId) {
                fail(`${sourceId || 'completion row'} final cursor belongs to another source`);
            }
            const sourceCursors = cursorsBySource.get(sourceId) || [];
            if (sourceCursors.at(-1)?.row.values.cursorId !== finalCursorId) {
                fail(`${sourceId || 'completion row'} final_cursor_id is not the last recorded cursor`);
            }
            if (completionState === 'blocked' && finalCursor) {
                const primaryIntervals = intervalsBySource.get(sourceId) || [];
                const committedPrimaryEvents = (eventsBySource.get(sourceId) || []).filter((event) => (event.row.values.origin === 'primary'
                    && event.row.values.status === 'committed'));
                const finalSharedPosition = finalCursor.row.values.sharedPositionKey;
                if (finalSharedPosition === 'none') {
                    const laterInterval = primaryIntervals.find((interval) => (['closed', 'resolved'].includes(interval.row.values.closureState)
                        && interval.end > finalCursor.offset));
                    if (laterInterval) {
                        fail(`${sourceId || 'completion row'} blocked final cursor ${finalCursorId} `
                            + `is behind committed primary walk ${laterInterval.row.values.walkId}`);
                    }
                    const laterEvent = committedPrimaryEvents.find((event) => event.end > finalCursor.offset);
                    if (laterEvent) {
                        fail(`${sourceId || 'completion row'} blocked final cursor ${finalCursorId} `
                            + `is behind committed primary event ${laterEvent.row.values.eventId}`);
                    }
                }
                else {
                    const nextOrdinal = canonicalNonnegativeInteger(finalCursor.row.values.nextEventOrdinal);
                    const primarySharedEvents = (eventsBySharedPosition.get(finalSharedPosition) || []).filter((event) => event.row.values.origin === 'primary');
                    if (primarySharedEvents.length === 0) {
                        fail(`${sourceId || 'completion row'} blocked final cursor ${finalCursorId} `
                            + 'does not identify a primary shared-position frontier');
                    }
                    else if (nextOrdinal !== null) {
                        for (const event of primarySharedEvents) {
                            if (event.ordinal < nextOrdinal
                                && event.row.values.status !== 'committed') {
                                fail(`${finalCursorId} requires shared ordinal ${event.ordinal} to be `
                                    + `committed before ordinal ${nextOrdinal}`);
                            }
                            if (event.ordinal >= nextOrdinal
                                && event.row.values.status === 'committed') {
                                fail(`${finalCursorId} names shared ordinal ${nextOrdinal} as pending `
                                    + `but ${event.row.values.eventId} at ordinal ${event.ordinal} `
                                    + 'is already committed');
                            }
                        }
                    }
                    const containingWalk = intervalIds.get(finalCursor.row.values.predecessorWalkId);
                    const laterInterval = primaryIntervals.find((interval) => (interval !== containingWalk
                        && ['closed', 'resolved'].includes(interval.row.values.closureState)
                        && (containingWalk
                            ? interval.start >= containingWalk.end
                            : interval.start > finalCursor.offset)));
                    if (laterInterval) {
                        fail(`${sourceId || 'completion row'} blocked final cursor ${finalCursorId} `
                            + `is behind committed primary walk ${laterInterval.row.values.walkId}`);
                    }
                    const laterEvent = committedPrimaryEvents.find((event) => event.start > finalCursor.offset);
                    if (laterEvent) {
                        fail(`${sourceId || 'completion row'} blocked final cursor ${finalCursorId} `
                            + `is behind committed primary event ${laterEvent.row.values.eventId}`);
                    }
                }
            }
            const declaredGapIds = customIdList(gapReviewIdsValue, 'GAP');
            if (declaredGapIds === null) {
                fail(`${sourceId || 'completion row'} gap_review_ids must be a comma-separated GAP list`);
            }
            else {
                if (new Set(declaredGapIds).size !== declaredGapIds.length) {
                    fail(`${sourceId || 'completion row'} gap_review_ids must not contain duplicates`);
                }
                for (const gapId of declaredGapIds) {
                    const review = gapReviewIds.get(gapId);
                    if (!review || review.values.sourceId !== sourceId) {
                        fail(`${sourceId || 'completion row'} gap review ${gapId} does not resolve for this source`);
                    }
                }
                const actualGapIds = (gapReviewsBySource.get(sourceId) || [])
                    .map((review) => review.values.gapReviewId);
                const drift = [...new Set([...declaredGapIds, ...actualGapIds])]
                    .filter((id) => declaredGapIds.includes(id) !== actualGapIds.includes(id));
                if (drift.length > 0) {
                    fail(`${sourceId || 'completion row'} gap_review_ids omit or add ${drift.join(', ')}`);
                }
            }
            if (completionState === 'complete') {
                const coveredEnd = coveredEndBySource.get(sourceId) || 0;
                if (data && coveredEnd !== data.bytes.byteLength) {
                    fail(`${sourceId} complete walk ends at byte ${coveredEnd}, expected `
                        + `${data.bytes.byteLength}`);
                }
                if (data
                    && finalCursor
                    && (finalCursor.offset !== data.bytes.byteLength
                        || finalCursor.row.values.sharedPositionKey !== 'none')) {
                    fail(`${sourceId} complete source final cursor must identify source end`);
                }
                for (const interval of intervalsBySource.get(sourceId) || []) {
                    if (interval.row.values.closureState === 'open') {
                        fail(`${sourceId} complete source has open interval `
                            + `${interval.row.values.walkId}`);
                    }
                    if (interval.row.values.outcome === 'deferred'
                        && interval.row.values.closureState !== 'resolved') {
                        fail(`${sourceId} complete source has unresolved deferred interval `
                            + `${interval.row.values.walkId}`);
                    }
                    if (interval.row.values.outcome === 'unsupported') {
                        fail(`${sourceId} complete source has unsupported interval `
                            + `${interval.row.values.walkId}`);
                    }
                }
                for (const event of eventsBySource.get(sourceId) || []) {
                    if (event.row.values.status !== 'committed') {
                        fail(`${sourceId} complete source has pending event `
                            + `${event.row.values.eventId}`);
                    }
                }
                const sourceReviews = gapReviewsBySource.get(sourceId) || [];
                if (sourceReviews.length === 0) {
                    fail(`${sourceId} complete source requires at least one gap review`);
                }
                for (const review of sourceReviews) {
                    if (review.values.result === 'cannot-determine') {
                        fail(`${sourceId} complete source cannot use cannot-determine gap review `
                            + `${review.values.gapReviewId}`);
                    }
                    if (review.values.result === 'gap-candidate-found'
                        && review.values.status !== 'reconciled') {
                        fail(`${sourceId} complete source has unreconciled gap review `
                            + `${review.values.gapReviewId}`);
                    }
                }
            }
        }
        for (const source of model.corpus.sources) {
            if (!completionsBySource.has(source.values.sourceId)) {
                fail(`${source.values.sourceId} lacks one per-source completion row`);
            }
        }
        if (sourceWalkStageClosed(model)) {
            for (const completion of walk.completions) {
                if (completion.values.completionState !== 'complete') {
                    fail(`S2 exit cannot be recorded while ${completion.values.sourceId || 'a source'} `
                        + 'is blocked');
                }
            }
        }
        return 'source walks, shared-position events, next-work cursors, gap reviews, and completion states are structurally valid; semantic recall is not judged';
    });
}
function checkIds(results, model) {
    results.run('K2.5', 'id integrity', (fail) => {
        const indexes = makeIndexes(model);
        const predecessorRun = model.manifest?.predecessorRun || '';
        const predecessorLine = model.manifest?.bullets.locations.get('predecessor run') || 0;
        for (const duplicate of duplicateDefinitions(model)) {
            fail(`${duplicate.id} has duplicate defining rows, including ${location(duplicate.row)}`);
        }
        for (const file of model.files) {
            for (const family of ID_FAMILIES) {
                let scanText = file.text;
                if (family === 'RUN'
                    && file.relativePath === 'run-manifest.md'
                    && predecessorRun.startsWith('RUN-')
                    && predecessorLine > 0) {
                    const lines = scanText.split('\n');
                    const line = lines[predecessorLine - 1] || '';
                    const field = line.match(/^\s*-\s*predecessor[_ -]run:\s*(\S+)\s*$/i);
                    if (field?.[1] === predecessorRun) {
                        lines[predecessorLine - 1] = line.replace(predecessorRun, 'none');
                        scanText = lines.join('\n');
                    }
                }
                const seen = new Set(idsIn(scanText, family));
                for (const id of seen) {
                    if (!indexes[family].has(id)) {
                        fail(`${id} in ${file.relativePath} has no defining ${family} row`);
                    }
                }
            }
        }
        return 'every structured ID token resolves to one home definition, except the manifest predecessor field';
    });
}
function checkClaimShape(results, model) {
    results.run('K2.6', 'claim table shape', (fail) => {
        if (!model.claimDocument && !distillingArtifactsApply(model)) {
            return 'claim inventory is not applicable before DISTILLING';
        }
        const table = model.claimDocument
            ? findTableByFirstHeader(model.claimDocument.tables, 'claim id')
            : null;
        if (!table) {
            fail('claim-inventory.md has no claim_id table');
            return 'claim rows are well formed';
        }
        if (table.header.length !== 10) {
            fail(`claim inventory header has ${table.header.length} columns, expected 10`);
        }
        const packetIndex = makeIndexes(model).PKT;
        const currentClaimIds = new Set(activeClaims(model).map((claim) => claim.values.claimId));
        const s5Entered = reachedState(model, 'ASSEMBLED') || Boolean(firstRunLogEntry(model.runLog, 'S5'));
        for (const claim of model.claims) {
            const { claimId, packets, sources, claimType, disposition, status, } = claim.values;
            if (claim.cells.length !== 10) {
                fail(`${claimId || 'claim row'} has ${claim.cells.length} columns at ${location(claim)}`);
                continue;
            }
            if (!CLAIM_TYPES.includes(claimType)) {
                fail(`${claimId} claim_type "${claimType || '(blank)'}" is not in the five-value vocabulary`);
            }
            if (status === 'active') {
                if (s5Entered && currentClaimIds.has(claimId) && !isDisposition(disposition)) {
                    fail(`${claimId} lineage-current after S5 has invalid disposition "${disposition || '(blank)'}"`);
                }
                else if (disposition && !isDisposition(disposition)) {
                    fail(`${claimId} has invalid disposition "${disposition}"`);
                }
            }
            const packetIds = idsIn(packets, 'PKT');
            if (packetIds.length === 0) {
                fail(`${claimId} packets is empty at ${location(claim)}`);
                continue;
            }
            const derivedSources = new Set();
            for (const packetId of packetIds) {
                const packet = packetIndex.get(packetId);
                if (packet)
                    derivedSources.add(packet.values.sourceId);
            }
            const declaredSources = new Set(idsIn(sources, 'SRC'));
            const missing = [...derivedSources].filter((id) => !declaredSources.has(id));
            const extra = [...declaredSources].filter((id) => !derivedSources.has(id));
            if (missing.length || extra.length) {
                fail(`${claimId} sources differ from packet union (missing ${missing.join(', ') || 'none'}; extra ${extra.join(', ') || 'none'})`);
            }
        }
        return s5Entered
            ? '10-column claims, claim types, dispositions, packets, and source unions are valid'
            : '10-column claims, claim types, packets, and source unions are valid; disposition requirement not active before S5';
    });
}
function checkAccounting(results, model) {
    results.run('K2.7', 'accounting', (fail) => {
        const s5Entered = reachedState(model, 'ASSEMBLED') || Boolean(firstRunLogEntry(model.runLog, 'S5'));
        if (!s5Entered)
            return 'disposition accounting is not applicable before S5';
        const claims = activeClaims(model);
        const actual = new Map(DISPOSITIONS.map((disposition) => [disposition, []]));
        for (const claim of claims) {
            if (isDisposition(claim.values.disposition)) {
                actual.get(claim.values.disposition).push(claim.values.claimId);
            }
        }
        const rows = new Map();
        let total = null;
        for (const row of model.dispositionRows) {
            const disposition = row.values.disposition.replace(/\*/g, '').trim();
            if (disposition.toLowerCase() === 'total') {
                total = Number(row.values.count.replace(/\*/g, ''));
                continue;
            }
            if (rows.has(disposition))
                fail(`duplicate disposition row "${disposition}" at ${location(row)}`);
            rows.set(disposition, row);
        }
        for (const disposition of DISPOSITIONS) {
            const row = rows.get(disposition);
            if (!row) {
                fail(`missing disposition row "${disposition}"`);
                continue;
            }
            const count = Number(row.values.count);
            const expected = actual.get(disposition).length;
            if (!Number.isInteger(count) || count !== expected) {
                fail(`${disposition} declares ${row.values.count}, recomputed ${expected}`);
            }
            const declaredIds = new Set(idsIn(row.values.claimIds, 'CC'));
            const expectedIds = new Set(actual.get(disposition));
            const drift = [...new Set([...declaredIds, ...expectedIds])]
                .filter((id) => declaredIds.has(id) !== expectedIds.has(id));
            if (drift.length)
                fail(`${disposition} claim_ids drift: ${drift.join(', ')}`);
        }
        if (total !== claims.length) {
            fail(`total row is ${total === null ? 'missing' : total}, active inventory count is ${claims.length}`);
        }
        return `all seven rows and total balance over ${claims.length} active claims`;
    });
}
function checkMerges(results, model) {
    results.run('K2.8', 'merge provenance', (fail) => {
        if (!model.mergeDocument)
            return 'merge map not yet applicable';
        const claims = makeIndexes(model).CC;
        for (const merge of model.merges.filter((row) => row.values.status === 'active')) {
            const canonical = claims.get(merge.values.canonical);
            if (!canonical)
                continue;
            const canonicalSources = new Set(idsIn(canonical.values.sources, 'SRC'));
            for (const absorbedId of idsIn(merge.values.absorbs, 'CC')) {
                const absorbed = claims.get(absorbedId);
                if (!absorbed)
                    continue;
                const dropped = idsIn(absorbed.values.sources, 'SRC')
                    .filter((source) => !canonicalSources.has(source));
                if (dropped.length) {
                    fail(`${merge.values.canonical} drops ${dropped.join(', ')} from absorbed ${absorbedId}`);
                }
                if (!usesLineage(model.manifest?.runFormatVersion || '')
                    && absorbed.values.disposition !== 'merged') {
                    fail(`${absorbedId} is absorbed but disposition is "${absorbed.values.disposition}"`);
                }
            }
        }
        return 'canonical source sets retain absorbed provenance and absorbed claims are merged';
    });
}
function checkCriteria(results, model) {
    results.run('K2.9', 'criteria precede packets', (fail) => {
        if (!model.criteria) {
            if (!distillingArtifactsApply(model)) {
                return 'criteria chronology is not applicable before DISTILLING';
            }
            fail('extraction-criteria.md is missing');
            return 'criteria chronology is valid';
        }
        const written = model.criteria.bullets.fields.get('written') || '';
        const writtenTimestamp = parseTimestamp(written);
        if (!writtenTimestamp)
            fail(`written timestamp "${written || '(blank)'}" is invalid`);
        const s2 = firstRunLogEntry(model.runLog, 'S2');
        if (model.packets.length > 0 && !s2) {
            fail('packet rows exist but run-log.md has no S2 entry');
        }
        else if (s2 && writtenTimestamp) {
            const s2Timestamp = parseTimestamp(s2.timestamp);
            if (!s2Timestamp || compareTimestamp(writtenTimestamp, s2Timestamp) > 0) {
                fail(`criteria written ${written} after first S2 entry ${s2.timestamp}`);
            }
        }
        const supersessions = findTableByFirstHeader(model.criteria.tables, '#');
        if (supersessions && /supersession/i.test(model.criteria.text)) {
            for (const row of supersessions.rows) {
                if (row.cells.length < 4 || !row.cells[0].trim())
                    continue;
                const completed = row.cells[3].trim();
                const logHasNote = model.runLog
                    && /re-extraction/i.test(model.runLog.text)
                    && (model.runLog.text.includes(`supersession ${row.cells[0].trim()}`)
                        || (row.cells[1] && model.runLog.text.includes(row.cells[1])));
                if (!completed || !logHasNote) {
                    fail(`supersession ${row.cells[0]} lacks a matching re-extraction record`);
                }
            }
        }
        return 'criteria timestamp precedes S2 and supersessions have re-extraction records';
    });
}
function checkStatuses(results, model) {
    results.run('K2.10', 'status discipline', (fail) => {
        const rows = allStatusRows(model);
        const indexes = makeIndexes(model);
        const lineageStatus = usesLineage(model.manifest?.runFormatVersion || '');
        const durableUnitLocations = new Set();
        if (lineageStatus && distillingArtifactsApply(model)) {
            const unitDefinitionSurfaces = [
                {
                    label: 'packet',
                    document: model.packetDocument,
                    header: PACKET_DEFINITION_HEADER,
                },
                {
                    label: 'claim',
                    document: model.claimDocument,
                    header: CLAIM_DEFINITION_HEADER,
                },
            ];
            for (const surface of unitDefinitionSurfaces) {
                const tables = findTables(surface.document?.tables || [], surface.header);
                if (tables.length !== 1) {
                    fail(`run-format 1.3 requires exactly one canonical ${surface.label} home-definition table; found ${tables.length}`);
                }
                for (const table of tables) {
                    for (const row of table.rows)
                        durableUnitLocations.add(location(row));
                }
            }
        }
        const homeRows = new Map();
        const homeDefinitions = [
            {
                family: 'PKT',
                records: model.packets.map((row) => ({ id: row.values.packetId, row })),
            },
            {
                family: 'CC',
                records: model.claims.map((row) => ({ id: row.values.claimId, row })),
            },
            {
                family: 'NB',
                records: model.boundaries.map((row) => ({ id: row.values.boundaryId, row })),
            },
        ];
        for (const { family, records } of homeDefinitions) {
            const byId = new Map();
            for (const { id, row } of records) {
                if (new RegExp(`^${family}-\\d+$`).test(id)) {
                    byId.set(id, { ...row, status: row.values.status || '' });
                }
            }
            homeRows.set(family, byId);
        }
        for (const row of rows) {
            if (lineageStatus
                && durableUnitLocations.has(location(row))
                && row.status !== 'active') {
                fail(`${row.id} run-format 1.3 unit rows must use durable status active; identity currentness belongs to lineage`);
                continue;
            }
            if (row.status === 'active')
                continue;
            const superseded = row.status.match(/^superseded-by:((?:PKT|CC|SRC|NB)-\d+)$/);
            const retracted = row.status.match(/^retracted:(.+)$/);
            if (!superseded && !retracted) {
                fail(`${row.id || 'row'} status "${row.status || '(blank)'}" is invalid at ${location(row)}`);
                continue;
            }
            if (retracted && !retracted[1].trim()) {
                fail(`${row.id || 'row'} has an empty retraction reason at ${location(row)}`);
            }
            if (!superseded)
                continue;
            const targetId = superseded[1];
            const family = targetId.split('-')[0];
            if (!isStatusTargetFamily(family)) {
                fail(`${row.id || 'row'} supersedes to missing ${targetId} at ${location(row)}`);
                continue;
            }
            const target = indexes[family].get(targetId);
            if (!target) {
                fail(`${row.id || 'row'} supersedes to missing ${targetId} at ${location(row)}`);
                continue;
            }
            const targetStatus = definitionStatus(target);
            if (targetStatus.startsWith('retracted:')) {
                fail(`${row.id || 'row'} supersedes to retracted target ${targetId}`);
            }
        }
        for (const [family, byId] of homeRows) {
            for (const row of byId.values()) {
                if (!row.status.startsWith('superseded-by:'))
                    continue;
                const seen = new Set([row.id || row.values?.packetId || row.values?.claimId || row.values?.boundaryId]);
                let current = row;
                while (current.status.startsWith('superseded-by:')) {
                    const targetId = current.status.slice('superseded-by:'.length);
                    if (seen.has(targetId)) {
                        fail(`${[...seen][0]} supersession chain contains a cycle at ${targetId}`);
                        break;
                    }
                    seen.add(targetId);
                    if (!targetId.startsWith(`${family}-`)) {
                        fail(`${[...seen][0]} supersession chain changes family at ${targetId}`);
                        break;
                    }
                    const target = byId.get(targetId);
                    if (!target)
                        break;
                    current = target;
                }
                if (current && current.status !== 'active' && !current.status.startsWith('superseded-by:')) {
                    fail(`${[...seen][0]} supersession chain does not terminate at an active row`);
                }
            }
        }
        return 'all append-ledger status cells and supersession chains are valid';
    });
}
const PROJECTION_TERMS = [
    /\bPRD\b/,
    /\bGTM\b/,
    /\bmarket landscape\b/i,
    /\bproduct spec\b/i,
    /\bpitch deck\b/i,
    /\bdownstream projection\b/i,
    /\badjacent-consumer formalization\b/i,
    /\bprojection\b/i,
];
const GENERATION_VERBS = /\b(generat(?:e|es|ing|ed|ion)|produc(?:e|es|ing|ed|tion)|emit(?:s|ting|ted)?|formaliz(?:e|es|ing|ed|ation)|render(?:s|ed|ing)? into|ship(?:s|ped|ping)?|deliver(?:s|ed|ing)?\b|projects|projecting|project into)\b/i;
const EXEMPTION_CUES = /\b(no|not|never|none|neither|nor|without|cannot|can't|don't|doesn't|won't|could|would|may|might|should not|stops?|stopped|refus\w*|defer(?:s|red|ring)?|projection-neutral)\b|out[ -]of[ -]scope/i;
function inventoryFromPrecis(text) {
    const section = envelopeSection(text, 4);
    const table = findTableByFirstHeader(parseTables(section, 'precis.md'), 'claim id');
    if (!table)
        return [];
    return table.rows
        .filter((row) => row.cells.some((cell) => /\bCC-\d+\b/.test(cell)))
        .map((row) => ({
        row,
        id: row.cells[0] || '',
        claim: row.cells[1] || '',
        sources: row.cells[2] || '',
        disposition: (row.cells[3] || '').toLowerCase(),
    }));
}
function checkPrecis(results, model) {
    results.run('K2.11', 'precis consistency', (fail) => {
        if (!model.precis)
            return 'precis.md not yet applicable';
        const text = model.precis.text;
        const headings = numberedEnvelopeHeadings(text);
        const missing = Array.from({ length: 17 }, (_, index) => index + 1)
            .filter((number) => !headings.includes(number));
        if (missing.length)
            fail(`missing envelope section(s) ${missing.join(', ')}`);
        if (headings.filter((number) => number >= 1 && number <= 17).join(',') !==
            Array.from({ length: 17 }, (_, index) => index + 1).join(',')) {
            fail('numbered envelope sections 1-17 are not present exactly once in order');
        }
        for (let index = 0; index < model.precis.lines.length; index++) {
            const line = model.precis.lines[index];
            if (PROJECTION_TERMS.some((pattern) => pattern.test(line))
                && GENERATION_VERBS.test(line)
                && !EXEMPTION_CUES.test(line)) {
                fail(`precis.md:${index + 1} appears to generate a downstream projection`);
            }
            if (/chatgpt said:|\[oai_citation/i.test(line) || /^\s*user:\s*$/i.test(line)) {
                fail(`real-export marker found at precis.md:${index + 1}`);
            }
        }
        const active = activeClaims(model);
        const activeMap = new Map(active.map((claim) => [claim.values.claimId, claim]));
        const precisRows = inventoryFromPrecis(text);
        const seen = new Set();
        for (const entry of precisRows) {
            if (entry.row.cells.length !== 4) {
                fail(`${entry.id || '§4 row'} has ${entry.row.cells.length} columns, expected 4`);
                continue;
            }
            const claim = activeMap.get(entry.id);
            if (!claim) {
                fail(`§4 defines ${entry.id}, which is not an active inventory claim`);
                continue;
            }
            if (seen.has(entry.id))
                fail(`§4 defines ${entry.id} more than once`);
            seen.add(entry.id);
            if (entry.claim !== claim.values.normalizedClaim) {
                fail(`§4 normalized text for ${entry.id} differs from the active inventory`);
            }
            const left = new Set(idsIn(entry.sources, 'SRC'));
            const right = new Set(idsIn(claim.values.sources, 'SRC'));
            if ([...new Set([...left, ...right])].some((id) => left.has(id) !== right.has(id))) {
                fail(`§4 source projection for ${entry.id} differs from the active inventory`);
            }
            if (entry.disposition !== claim.values.disposition) {
                fail(`§4 disposition for ${entry.id} is ${entry.disposition}, inventory is ${claim.values.disposition}`);
            }
        }
        for (const claim of active) {
            if (!seen.has(claim.values.claimId))
                fail(`§4 is missing active claim ${claim.values.claimId}`);
        }
        const ids = new Set(precisRows.map((entry) => entry.id));
        for (const id of idsIn(text, 'CC')) {
            if (!ids.has(id))
                fail(`C1 phantom CC: ${id} is referenced but not defined in §4`);
        }
        let outside = text;
        for (const number of [4, 5]) {
            const section = envelopeSection(text, number);
            if (section)
                outside = outside.replace(section, '');
        }
        for (const id of ids) {
            if (!new RegExp(`\\b${id}\\b`).test(outside)) {
                fail(`C2 orphan claim: ${id} never appears outside §4/§5`);
            }
        }
        const ledgerTable = findTableByFirstHeader(parseTables(envelopeSection(text, 5), 'precis.md'), 'disposition');
        const ledgerIds = new Set();
        if (!ledgerTable) {
            fail('C3 ledger drift: §5 has no disposition table');
        }
        else {
            const actualCounts = new Map(DISPOSITIONS.map((disposition) => [disposition, 0]));
            for (const entry of precisRows) {
                if (isDisposition(entry.disposition)) {
                    actualCounts.set(entry.disposition, actualCounts.get(entry.disposition) + 1);
                }
            }
            const declared = new Map();
            let declaredTotal = null;
            for (const row of ledgerTable.rows) {
                const disposition = normalizeHeader(row.cells[0] || '');
                const count = Number((row.cells[1] || '').replace(/\*/g, ''));
                if (disposition === 'total') {
                    declaredTotal = count;
                    continue;
                }
                if (!isDisposition(disposition))
                    continue;
                if (declared.has(disposition)) {
                    fail(`C3 ledger drift: §5 repeats ${disposition}`);
                }
                declared.set(disposition, count);
                if (!Number.isInteger(count) || count !== actualCounts.get(disposition)) {
                    fail(`C3 ledger count: §5 declares ${row.cells[1] || '(blank)'} ${disposition}, `
                        + `recomputed ${actualCounts.get(disposition)}`);
                }
                for (const id of idsIn(row.cells[2] || '', 'CC')) {
                    ledgerIds.add(id);
                    const entry = precisRows.find((candidate) => candidate.id === id);
                    if (!entry || entry.disposition !== disposition) {
                        fail(`C3 disposition drift: §5 lists ${id} under ${disposition}`);
                    }
                }
            }
            for (const disposition of DISPOSITIONS) {
                if (!declared.has(disposition)) {
                    fail(`C3 ledger drift: §5 is missing ${disposition}`);
                }
            }
            if (!Number.isInteger(declaredTotal) || declaredTotal !== precisRows.length) {
                fail(`C3 ledger total: §5 declares ${declaredTotal ?? '(missing)'}, `
                    + `recomputed ${precisRows.length}`);
            }
            for (const id of ids) {
                if (!ledgerIds.has(id))
                    fail(`C3 ledger coverage: ${id} is absent from §5`);
            }
        }
        const sourceIds = new Set(model.corpus.sources.map((source) => source.values.sourceId));
        const sourceTable = findTableByFirstHeader(parseTables(envelopeSection(text, 2), 'precis.md'), 'source id');
        const precisSourceIds = new Set();
        if (!sourceTable) {
            fail('C4 source inventory: §2 has no source_id table');
        }
        else {
            for (const row of sourceTable.rows) {
                if (/^SRC-\d+$/.test(row.cells[0] || ''))
                    precisSourceIds.add(row.cells[0]);
            }
        }
        for (const id of new Set([...sourceIds, ...precisSourceIds])) {
            if (sourceIds.has(id) !== precisSourceIds.has(id)) {
                fail(`C4 source inventory: §2 and corpus manifest disagree on ${id}`);
            }
        }
        for (const id of idsIn(text, 'SRC')) {
            if (!precisSourceIds.has(id))
                fail(`C4 phantom SRC: ${id} does not resolve to Précis §2`);
        }
        const matrixSection = headingSection(text, /^##\s+stress-test matrix\s*$/i);
        const matrixTables = parseTables(matrixSection, 'precis.md');
        const matrixTable = findTableByFirstHeader(matrixTables, 'case id', 'stm id');
        const stmRows = new Set();
        if (matrixTable) {
            const ccIndex = matrixTable.normalizedHeader.findIndex((header) => /candidate claim ids?/.test(header));
            const srcIndex = matrixTable.normalizedHeader.findIndex((header) => /source refs?/.test(header));
            for (const row of matrixTable.rows) {
                const stm = row.cells[0] || '';
                if (/^STM-\d+$/.test(stm))
                    stmRows.add(stm);
                if (ccIndex >= 0) {
                    for (const id of idsIn(row.cells[ccIndex] || '', 'CC')) {
                        if (!ids.has(id))
                            fail(`C5 matrix CC ref: ${stm} references missing ${id}`);
                    }
                }
                if (srcIndex >= 0) {
                    for (const id of idsIn(row.cells[srcIndex] || '', 'SRC')) {
                        if (!precisSourceIds.has(id))
                            fail(`C6 matrix SRC ref: ${stm} references missing ${id}`);
                    }
                }
            }
        }
        for (const id of idsIn(text, 'STM')) {
            if (!stmRows.has(id))
                fail(`C7 phantom STM: ${id} is not a matrix row`);
        }
        const sourceByClaim = new Map(precisRows.map((entry) => [
            entry.id,
            new Set(idsIn(entry.sources, 'SRC')),
        ]));
        const mergeTable = findTableByFirstHeader(parseTables(envelopeSection(text, 11), 'precis.md'), 'canonical');
        if (mergeTable) {
            for (const row of mergeTable.rows) {
                const canonical = row.cells[0] || '';
                const canonicalSources = sourceByClaim.get(canonical) || new Set();
                for (const absorbed of idsIn(row.cells[1] || '', 'CC')) {
                    const dropped = [...(sourceByClaim.get(absorbed) || new Set())]
                        .filter((source) => !canonicalSources.has(source));
                    if (dropped.length) {
                        fail(`C8 merge provenance: ${canonical} drops ${dropped.join(', ')} from ${absorbed}`);
                    }
                }
            }
        }
        return 'envelope, neutrality, exact §4 projection, and C1-C8 are consistent';
    });
}
function checkKernelReport(results, model) {
    results.run('K2.12', 'kernel honesty', (fail) => {
        const reports = model.files
            .filter((file) => /^verification\/kernel-report(?:-\d+)?\.md$/.test(file.relativePath))
            .sort((left, right) => {
            const ordinal = (path) => {
                const match = path.match(/kernel-report(?:-(\d+))?\.md$/);
                return match?.[1] ? Number(match[1]) : 1;
            };
            return ordinal(left.relativePath) - ordinal(right.relativePath);
        });
        let passingCanonicalReport = false;
        for (const report of reports) {
            const fields = parseBulletFields(report.text).fields;
            const command = fields.get('command') || '';
            const result = (fields.get('result') || '').toUpperCase();
            const recordRole = fields.get('record role') || '';
            const namesSourceChecker = command.includes('validate-run.ts');
            const namesCompiledChecker = command.includes('runtime-js/scripts/validate-run.js');
            const namesCanonicalChecker = namesSourceChecker || namesCompiledChecker;
            const isSupersededJavaScriptHistory = (command.includes('validate-run.mjs')
                && /\b(?:historical|superseded)\b/i.test(recordRole));
            if (!namesCanonicalChecker && !isSupersededJavaScriptHistory) {
                fail(`${report.relativePath} command neither names a canonical validate-run entrypoint `
                    + 'nor records an explicitly superseded JavaScript checker');
            }
            if (!['PASS', 'FAIL'].includes(result)) {
                fail(`${report.relativePath} result is not PASS or FAIL`);
            }
            if (namesCanonicalChecker && result === 'PASS')
                passingCanonicalReport = true;
        }
        const latest = reports.at(-1);
        if (latest) {
            const latestCommand = parseBulletFields(latest.text).fields.get('command') || '';
            if (!latestCommand.includes('validate-run.ts')
                && !latestCommand.includes('runtime-js/scripts/validate-run.js')) {
                fail(`${latest.relativePath} is the latest report but does not name a canonical validate-run entrypoint`);
            }
        }
        if (reachedState(model, 'VERIFIED') && !passingCanonicalReport) {
            fail('VERIFIED state requires a canonical kernel report with result PASS');
        }
        return reports.length
            ? `${reports.length} kernel report(s) have valid results and the latest names a canonical checker`
            : 'kernel report not yet applicable';
    });
}
export function runK2(results, model, root) {
    checkLayout(results, model);
    checkManifest(results, model);
    checkForbidden(results, model, root);
    checkPackets(results, model);
    checkIds(results, model);
    checkClaimShape(results, model);
    checkAccounting(results, model);
    checkMerges(results, model);
    checkCriteria(results, model);
    checkStatuses(results, model);
    checkPrecis(results, model);
    checkKernelReport(results, model);
    checkExactEvidence(results, model);
    checkSourceWalk(results, model);
    runK2Lineage(results, model);
}
