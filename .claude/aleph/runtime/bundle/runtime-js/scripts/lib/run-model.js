import { existsSync, lstatSync, readFileSync, readdirSync, } from 'node:fs';
import { basename, join, relative, sep } from 'node:path';
import { findTable, findTableByFirstHeader, parseBulletFields, parseFieldTable, parseTables, } from './markdown.js';
export const DISPOSITIONS = [
    'carried',
    'merged',
    'deferred',
    'excluded-with-reason',
    'backgrounded',
    'judged-non-load-bearing',
    'unresolved',
];
export function walkFiles(root) {
    const files = [];
    function visit(directory) {
        for (const name of readdirSync(directory).sort()) {
            const path = join(directory, name);
            const stat = lstatSync(path);
            if (stat.isSymbolicLink())
                continue;
            if (stat.isDirectory())
                visit(path);
            else if (stat.isFile())
                files.push(path);
        }
    }
    if (existsSync(root))
        visit(root);
    return files;
}
function isCoreRunArtifact(runDir, path) {
    const [topLevel] = relative(runDir, path).split(sep);
    return topLevel !== 'control';
}
function readDocument(runDir, relativePath) {
    const path = join(runDir, relativePath);
    if (!existsSync(path) || !lstatSync(path).isFile())
        return null;
    const text = readFileSync(path, 'utf8');
    return {
        path,
        relativePath,
        text,
        lines: text.split('\n'),
        tables: parseTables(text, relativePath),
        bullets: parseBulletFields(text),
    };
}
function rowObjects(table, keys) {
    if (!table)
        return [];
    return table.rows.map((row) => {
        const values = {};
        keys.forEach((key, index) => { values[key] = row.cells[index] ?? ''; });
        return { ...row, values };
    });
}
function parseManifest(document) {
    if (!document)
        return null;
    const stateTable = findTable(document.tables, ['#', 'state', 'entered', 'actor', 'note']);
    const signoffTable = findTable(document.tables, ['gate', 'decision', 'by', 'date', 'reference']);
    const runId = document.bullets.fields.get('run id') || '';
    return {
        ...document,
        mode: document.bullets.fields.get('mode') || '',
        doctrineSha: document.bullets.fields.get('doctrine sha') || '',
        corpusHash: document.bullets.fields.get('corpus hash') || '',
        runId,
        predecessorRun: document.bullets.fields.get('predecessor run') || '',
        runIdRow: {
            file: document.relativePath,
            line: document.bullets.locations.get('run id') || 1,
            values: { runId },
        },
        states: rowObjects(stateTable, ['number', 'state', 'entered', 'actor', 'note']),
        signoffs: rowObjects(signoffTable, ['gate', 'decision', 'by', 'date', 'reference']),
    };
}
function parseCorpus(document) {
    if (!document)
        return { document: null, sources: [] };
    const table = findTable(document.tables, [
        'source id', 'kind', 'locus', 'scheme', 'content hash',
        'date(s)', 'trust class', 'sensitivity', 'admission note',
    ]) || findTableByFirstHeader(document.tables, 'source id');
    return {
        document,
        sources: rowObjects(table, [
            'sourceId', 'kind', 'locus', 'scheme', 'contentHash',
            'dates', 'trustClass', 'sensitivity', 'admissionNote',
        ]),
    };
}
function parsePackets(document) {
    if (!document)
        return [];
    const table = findTable(document.tables, [
        'packet id', 'source id', 'locator', 'span hash', 'quote', 'criterion', 'status',
    ]) || findTableByFirstHeader(document.tables, 'packet id');
    return rowObjects(table, [
        'packetId', 'sourceId', 'locator', 'spanHash', 'quote', 'criterion', 'status',
    ]);
}
function parseClaims(document) {
    if (!document)
        return [];
    const table = findTable(document.tables, [
        'claim id', 'normalized claim', 'packets', 'sources', 'claim type',
        'disposition', 'rationale', 'judged by', 'verified', 'status',
    ]) || findTableByFirstHeader(document.tables, 'claim id');
    return rowObjects(table, [
        'claimId', 'normalizedClaim', 'packets', 'sources', 'claimType',
        'disposition', 'rationale', 'judgedBy', 'verified', 'status',
    ]);
}
function parseDispositionRows(document) {
    if (!document)
        return [];
    return rowObjects(findTable(document.tables, ['disposition', 'count', 'claim ids'])
        || findTableByFirstHeader(document.tables, 'disposition'), ['disposition', 'count', 'claimIds']);
}
function parseMerges(document) {
    if (!document)
        return [];
    return rowObjects(findTable(document.tables, [
        'canonical', 'absorbs', 'basis', 'provenance retained', 'corroboration', 'status',
    ]) || findTableByFirstHeader(document.tables, 'canonical'), ['canonical', 'absorbs', 'basis', 'provenanceRetained', 'corroboration', 'status']);
}
function parseEvidence(document) {
    if (!document)
        return { edges: [], markers: [], accounting: new Map() };
    const edges = rowObjects(findTable(document.tables, [
        'claim id', 'source id', 'role', 'verification', 'removal effect', 'note', 'status',
    ]), ['claimId', 'sourceId', 'role', 'verification', 'removalEffect', 'note', 'status']);
    const markers = rowObjects(findTable(document.tables, [
        'claim id', 'inference basis (claim/packet ids)', 'uncertainty note',
    ]), ['claimId', 'basisIds', 'uncertainty']);
    const accounting = new Map();
    for (const line of document.lines) {
        const match = line.match(/^\s*-\s*([^:]+):\s*(\d+)\s*$/);
        if (match)
            accounting.set(match[1].trim().toLowerCase(), Number(match[2]));
    }
    return { edges, markers, accounting };
}
function parseBoundaries(document) {
    if (!document)
        return [];
    return rowObjects(findTableByFirstHeader(document.tables, 'boundary id'), ['boundaryId', 'type', 'statement', 'governs', 'basis', 'status']);
}
function parseTags(document) {
    if (!document)
        return [];
    return rowObjects(findTable(document.tables, ['tag', 'member ids (PKT/CC)', 'structural basis (one phrase)'])
        || findTableByFirstHeader(document.tables, 'tag'), ['tag', 'memberIds', 'basis']);
}
function parseReferents(document) {
    if (!document)
        return [];
    return rowObjects(findTableByFirstHeader(document.tables, 'ref id'), ['refId', 'need', 'depends', 'status', 'suppliedBy', 'intake', 'date', 'taintNote']);
}
function parseMatrix(document) {
    if (!document)
        return [];
    const rows = [];
    for (const table of document.tables) {
        if (!['stm id', 'case id'].includes(table.normalizedHeader[0]))
            continue;
        rows.push(...rowObjects(table, [
            'stmId', 'pressure', 'sourceRefs', 'claimIds', 'risk', 'handling', 'resolvedAt',
        ]));
    }
    return rows;
}
function parseCards(runDir) {
    const directory = join(runDir, 'clusters', 'route-cards');
    if (!existsSync(directory))
        return [];
    return walkFiles(directory)
        .filter((path) => /^RC-\d+\.md$/.test(basename(path)))
        .map((path) => {
        const relativePath = relative(runDir, path);
        const text = readFileSync(path, 'utf8');
        const tables = parseTables(text, relativePath);
        const fieldTable = parseFieldTable(tables);
        const heading = text.match(/^#\s+Route Cluster\s+(RC-\d+)\b/m);
        const vectorTable = findTable(tables, ['signal', 'value']);
        return {
            path,
            relativePath,
            text,
            lines: text.split('\n'),
            tables,
            fieldTable,
            id: heading?.[1] || '',
            filenameId: basename(path, '.md'),
            vectorRows: rowObjects(vectorTable, ['signal', 'value']),
        };
    });
}
function parseProjections(runDir) {
    const directory = join(runDir, 'projections');
    if (!existsSync(directory))
        return [];
    const byType = new Map();
    const ensure = (type) => {
        const existing = byType.get(type);
        if (existing)
            return existing;
        const projection = { type };
        byType.set(type, projection);
        return projection;
    };
    for (const path of walkFiles(directory)) {
        const relativePath = relative(runDir, path);
        const name = basename(path);
        let match = name.match(/^commission-(.+)\.md$/);
        if (match) {
            const document = readDocument(runDir, relativePath);
            ensure(match[1]).commission = {
                ...document,
                fieldTable: parseFieldTable(document.tables),
            };
            continue;
        }
        match = name.match(/^(.+)-selection\.md$/);
        if (match) {
            const document = readDocument(runDir, relativePath);
            const table = findTable(document.tables, [
                'claim id', 'disposition', 'selection', 'reason if not-used / open-handling',
            ]) || findTableByFirstHeader(document.tables, 'claim id');
            ensure(match[1]).selection = {
                ...document,
                rows: rowObjects(table, ['claimId', 'disposition', 'selection', 'reason']),
            };
            continue;
        }
        match = name.match(/^(.+)-trace\.md$/);
        if (match) {
            const document = readDocument(runDir, relativePath);
            const table = findTable(document.tables, [
                'anchor', 'statement kind', 'backing (CC/NB ids)', 'note',
            ]) || findTable(document.tables, [
                'anchor', 'statement kind', 'backing (CC ids)', 'note',
            ]) || findTableByFirstHeader(document.tables, 'anchor');
            ensure(match[1]).trace = {
                ...document,
                rows: rowObjects(table, ['anchor', 'kind', 'backing', 'note']),
            };
        }
    }
    for (const projection of byType.values()) {
        projection.projectionId = projection.commission?.fieldTable.fields.get('projection id') || '';
        projection.projectionIdRow = projection.commission?.fieldTable.rows.get('projection id') || null;
        projection.projectionTracePath = (projection.commission?.fieldTable.fields.get('projection trace') || '');
    }
    return [...byType.values()]
        .sort((a, b) => a.type.localeCompare(b.type));
}
export function loadRun(runDir) {
    const documents = new Map();
    const get = (path) => {
        if (!documents.has(path))
            documents.set(path, readDocument(runDir, path));
        return documents.get(path) ?? null;
    };
    // Host adapters may retain their immutable runtime, dispatch checkpoints,
    // and other resume mechanics under the top-level control/ directory. Those
    // bytes are part of the durable run record, but they are not canonical Core
    // artifacts and must not participate in K2-K6 discovery or identifier scans.
    const filePaths = walkFiles(runDir).filter((path) => isCoreRunArtifact(runDir, path));
    const files = filePaths.map((path) => ({
        path,
        relativePath: relative(runDir, path),
        text: readFileSync(path, 'utf8'),
    }));
    for (const file of files) {
        if (file.relativePath.endsWith('.md'))
            get(file.relativePath);
    }
    const manifestDocument = get('run-manifest.md');
    const runLog = get('run-log.md');
    const criteria = get('ledgers/extraction-criteria.md');
    const packetDocument = get('ledgers/packet-index.md');
    const claimDocument = get('ledgers/claim-inventory.md');
    const dispositionDocument = get('ledgers/disposition-ledger.md');
    const mergeDocument = get('ledgers/merge-map.md');
    const evidenceDocument = get('ledgers/evidence-roles.md');
    const boundaryDocument = get('ledgers/negative-boundaries.md');
    const tagDocument = get('clusters/pre-cluster-tags.md');
    const referentDocument = get('ledgers/external-referents.md');
    const matrixDocument = get('arms/stress-test-matrix.md');
    return {
        runDir,
        files,
        documents,
        manifest: parseManifest(manifestDocument),
        runLog,
        corpus: parseCorpus(get('corpus/manifest.md')),
        criteria,
        packets: parsePackets(packetDocument),
        claims: parseClaims(claimDocument),
        dispositionRows: parseDispositionRows(dispositionDocument),
        merges: parseMerges(mergeDocument),
        evidence: parseEvidence(evidenceDocument),
        boundaries: parseBoundaries(boundaryDocument),
        tags: parseTags(tagDocument),
        referents: parseReferents(referentDocument),
        matrix: parseMatrix(matrixDocument),
        cards: parseCards(runDir),
        precis: get('precis.md'),
        unresolvedQueue: get('ledgers/unresolved-queue.md'),
        synthesis: get('synthesis/cluster-synthesis.md'),
        projections: parseProjections(runDir),
        packetDocument,
        claimDocument,
        dispositionDocument,
        mergeDocument,
        evidenceDocument,
        boundaryDocument,
        tagDocument,
        referentDocument,
        matrixDocument,
    };
}
