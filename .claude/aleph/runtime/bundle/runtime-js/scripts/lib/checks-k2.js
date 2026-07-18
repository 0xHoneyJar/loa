import { existsSync, lstatSync, readFileSync } from 'node:fs';
import { basename, join } from 'node:path';
import { activeClaims, allStatusRows, compareTimestamp, duplicateDefinitions, firstRunLogEntry, location, makeIndexes, mdLineSpan, normalizeSha256, parseTimestamp, pathIsWithin, reachedState, sha256, sourceFilePath, } from './check-helpers.js';
import { envelopeSection, findTableByFirstHeader, headingSection, idsIn, normalizeHeader, numberedEnvelopeHeadings, parseBulletFields, parseTables, tableCells, isSeparatorRow, } from './markdown.js';
import { DISPOSITIONS } from './run-model.js';
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
function distillingArtifactsApply(model) {
    return STATES.slice(2).some((state) => reachedState(model, state));
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
        return 'mode, hashes, ordered states, BLOCKED re-entry, and sign-offs are valid';
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
                if (s5Entered && !isDisposition(disposition)) {
                    fail(`${claimId} active after S5 has invalid disposition "${disposition || '(blank)'}"`);
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
                if (absorbed.values.disposition !== 'merged') {
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
}
