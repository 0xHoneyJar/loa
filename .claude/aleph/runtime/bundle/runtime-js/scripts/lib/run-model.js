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
export const EXACT_EVIDENCE_FORMAT = 'aleph-exact-evidence/v1';
export const SOURCE_WALK_FORMAT = 'aleph-source-walk/v1';
export const SOURCE_POSITION_FORMAT = 'zero-based-utf8-byte-half-open/v1';
export const SOURCE_WALK_CURSOR_REASONS = [
    'initial',
    'progress',
    'bounded-pause',
    'resumed-shared-position',
    'source-complete',
];
export const LEGACY_RUN_FORMAT_VERSION = '1.0.0-provisional';
export const EXACT_EVIDENCE_RUN_FORMAT_VERSION = '1.1.0-provisional';
export const SOURCE_WALK_RUN_FORMAT_VERSION = '1.2.0-provisional';
export const LINEAGE_RUN_FORMAT_VERSION = '1.3.0-provisional';
export const TYPED_RELATIONS_RUN_FORMAT_VERSION = '1.4.0-provisional';
export const INTERNAL_AMBIGUITY_RUN_FORMAT_VERSION = '1.5.0-provisional';
export const CURRENT_RUN_FORMAT_VERSION = INTERNAL_AMBIGUITY_RUN_FORMAT_VERSION;
export const PACKET_DEFINITION_HEADER = [
    'packet id',
    'source id',
    'locator',
    'span hash',
    'quote',
    'criterion',
    'status',
];
export const CLAIM_DEFINITION_HEADER = [
    'claim id',
    'normalized claim',
    'packets',
    'sources',
    'claim type',
    'disposition',
    'rationale',
    'judged by',
    'verified',
    'status',
];
export const SUPPORTED_RUN_FORMAT_VERSIONS = [
    LEGACY_RUN_FORMAT_VERSION,
    EXACT_EVIDENCE_RUN_FORMAT_VERSION,
    SOURCE_WALK_RUN_FORMAT_VERSION,
    LINEAGE_RUN_FORMAT_VERSION,
    TYPED_RELATIONS_RUN_FORMAT_VERSION,
    CURRENT_RUN_FORMAT_VERSION,
];
export const RUN_CAPABILITIES = [
    'legacy',
    'forward-execution-identity',
    'exact-evidence',
    'source-walk',
    'lineage',
    'typed-relations',
    'internal-ambiguity-lifecycle',
];
const RUN_FORMAT_CAPABILITY_ADDITIONS = [
    {
        version: LEGACY_RUN_FORMAT_VERSION,
        additions: ['legacy'],
    },
    {
        version: EXACT_EVIDENCE_RUN_FORMAT_VERSION,
        additions: ['forward-execution-identity', 'exact-evidence'],
    },
    {
        version: SOURCE_WALK_RUN_FORMAT_VERSION,
        additions: ['source-walk'],
    },
    {
        version: LINEAGE_RUN_FORMAT_VERSION,
        additions: ['lineage'],
    },
    {
        version: TYPED_RELATIONS_RUN_FORMAT_VERSION,
        additions: ['typed-relations'],
    },
    {
        version: INTERNAL_AMBIGUITY_RUN_FORMAT_VERSION,
        additions: ['internal-ambiguity-lifecycle'],
    },
];
export function hasRunCapability(runFormatVersion, capability) {
    const formatIndex = RUN_FORMAT_CAPABILITY_ADDITIONS.findIndex((entry) => entry.version === runFormatVersion);
    if (formatIndex < 0)
        return false;
    return RUN_FORMAT_CAPABILITY_ADDITIONS
        .slice(0, formatIndex + 1)
        .some((entry) => entry.additions.includes(capability));
}
export function usesForwardExecutionIdentity(runFormatVersion) {
    return hasRunCapability(runFormatVersion, 'forward-execution-identity');
}
export function usesExactEvidence(runFormatVersion) {
    return hasRunCapability(runFormatVersion, 'exact-evidence');
}
export function usesSourceWalk(runFormatVersion) {
    return hasRunCapability(runFormatVersion, 'source-walk');
}
export function usesLineage(runFormatVersion) {
    return hasRunCapability(runFormatVersion, 'lineage');
}
export function usesTypedRelations(runFormatVersion) {
    return hasRunCapability(runFormatVersion, 'typed-relations');
}
export function usesInternalAmbiguityLifecycle(runFormatVersion) {
    return hasRunCapability(runFormatVersion, 'internal-ambiguity-lifecycle');
}
export const EXACT_EVIDENCE_JOIN_POLICIES = [
    'single-fragment',
    'adjacent-fragments',
    'separate-fragments',
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
    const executionProfile = parseFieldTable(document.tables);
    const runId = document.bullets.fields.get('run id') || '';
    return {
        ...document,
        mode: document.bullets.fields.get('mode') || '',
        doctrineSha: document.bullets.fields.get('doctrine sha') || '',
        corpusHash: document.bullets.fields.get('corpus hash') || '',
        runFormatVersion: document.bullets.fields.get('run format version') || '',
        runId,
        predecessorRun: document.bullets.fields.get('predecessor run') || '',
        forwardIdentity: {
            coreId: document.bullets.fields.get('core id') || '',
            coreVersion: document.bullets.fields.get('core version') || '',
            coreDigest: document.bullets.fields.get('core digest') || '',
            adapterId: document.bullets.fields.get('adapter id') || '',
            adapterVersion: document.bullets.fields.get('adapter version') || '',
            adapterDigest: document.bullets.fields.get('adapter digest') || '',
            bundleId: document.bullets.fields.get('bundle id') || '',
            bundleDigest: document.bullets.fields.get('bundle digest') || '',
            bundleLockRef: document.bullets.fields.get('bundle lock ref') || '',
            checkerDigest: document.bullets.fields.get('checker digest') || '',
            adapterProtocolVersion: document.bullets.fields.get('adapter protocol version') || '',
            hostIdentity: document.bullets.fields.get('host identity') || '',
            runtimeSnapshotRef: document.bullets.fields.get('runtime snapshot ref') || '',
            runtimeSnapshotDigest: document.bullets.fields.get('runtime snapshot digest') || '',
            modelIds: executionProfile.fields.get('model ids (per role, exact strings; or "human")') || '',
            adapterProfile: executionProfile.fields.get('adapter profile id + digest') || '',
            modelExecutionMapping: executionProfile.fields.get('model/context/effort mapping actually used') || '',
        },
        executionProfile,
        runIdRow: {
            file: document.relativePath,
            line: document.bullets.locations.get('run id') || 1,
            values: { runId },
        },
        states: rowObjects(stateTable, ['number', 'state', 'entered', 'actor', 'note']),
        signoffs: rowObjects(signoffTable, ['gate', 'decision', 'by', 'date', 'reference']),
    };
}
const FORWARD_IDENTITY_BULLET_FIELDS = [
    'core_id',
    'core_version',
    'core_digest',
    'adapter_id',
    'adapter_version',
    'adapter_digest',
    'bundle_id',
    'bundle_digest',
    'bundle_lock_ref',
    'checker_digest',
    'adapter_protocol_version',
    'host_identity',
    'runtime_snapshot_ref',
    'runtime_snapshot_digest',
];
const FORWARD_IDENTITY_PROFILE_FIELDS = [
    ['model_ids', 'model ids (per role, exact strings; or "human")'],
    ['adapter profile ID + digest', 'adapter profile id + digest'],
    ['model/context/effort mapping actually used', 'model/context/effort mapping actually used'],
];
const IDENTITY_IDENTIFIER = /^[a-z][a-z0-9-]*$/;
const IDENTITY_VERSION = /^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z][0-9A-Za-z.-]*)?$/;
const IDENTITY_DIGEST = /^sha256:[a-f0-9]{64}$/;
const MUTABLE_IDENTITY_ALIAS = /(?:^|[-_.:/])(?:alias|auto|current|default|latest|main|master|recommended|rolling|stable)(?:$|[-_.:/])/i;
function bulletFieldCount(manifest, field) {
    const pattern = new RegExp(`^\\s*-\\s*${field.split('_').join('[_ -]')}\\s*:`, 'i');
    return manifest.lines.filter((line) => pattern.test(line)).length;
}
function profileFieldCount(manifest, field) {
    return manifest.executionProfile.table?.rows.filter((row) => (row.cells.length >= 2
        && row.cells[0]
            .replace(/[`*]/g, '')
            .replace(/_/g, ' ')
            .replace(/\s+/g, ' ')
            .trim()
            .toLowerCase() === field)).length || 0;
}
function exactIdentityLabel(value) {
    return value.length > 0
        && value === value.trim()
        && !/[\u0000-\u001f\u007f]/.test(value)
        && !MUTABLE_IDENTITY_ALIAS.test(value);
}
function normalizedRunReference(value) {
    if (IDENTITY_DIGEST.test(value))
        return true;
    if (!value || value.startsWith('/') || value.includes('\\') || value.includes('\0')) {
        return false;
    }
    const segments = value.split('/');
    return segments.every((segment) => segment.length > 0 && segment !== '.' && segment !== '..');
}
function exactJsonIdentity(value) {
    if (typeof value === 'string')
        return exactIdentityLabel(value);
    if (typeof value === 'boolean')
        return true;
    if (typeof value === 'number')
        return Number.isFinite(value);
    if (Array.isArray(value))
        return value.length > 0 && value.every(exactJsonIdentity);
    if (typeof value !== 'object' || value === null)
        return false;
    const entries = Object.entries(value);
    return entries.length > 0
        && entries.every(([key, entry]) => (key.length > 0
            && !/[\u0000-\u001f\u007f]/.test(key)
            && exactJsonIdentity(entry)));
}
function exactJsonObject(value) {
    try {
        const parsed = JSON.parse(value);
        return typeof parsed === 'object'
            && parsed !== null
            && !Array.isArray(parsed)
            && exactJsonIdentity(parsed);
    }
    catch {
        return false;
    }
}
export function forwardExecutionIdentityProblems(manifest) {
    if (!usesForwardExecutionIdentity(manifest.runFormatVersion))
        return [];
    const problems = [];
    for (const display of FORWARD_IDENTITY_BULLET_FIELDS) {
        const count = bulletFieldCount(manifest, display);
        if (count !== 1) {
            problems.push(`${display} must be defined exactly once; found ${count}`);
        }
    }
    for (const [display, field] of FORWARD_IDENTITY_PROFILE_FIELDS) {
        const count = profileFieldCount(manifest, field);
        if (count !== 1) {
            problems.push(`${display} must be defined exactly once; found ${count}`);
        }
    }
    const identity = manifest.forwardIdentity;
    for (const [field, value] of [
        ['core_id', identity.coreId],
        ['adapter_id', identity.adapterId],
        ['bundle_id', identity.bundleId],
    ]) {
        if (!IDENTITY_IDENTIFIER.test(value)) {
            problems.push(`${field} must be a lowercase immutable identifier`);
        }
    }
    for (const [field, value] of [
        ['core_version', identity.coreVersion],
        ['adapter_version', identity.adapterVersion],
        ['adapter_protocol_version', identity.adapterProtocolVersion],
    ]) {
        if (!IDENTITY_VERSION.test(value)) {
            problems.push(`${field} must be an exact semantic version`);
        }
    }
    for (const [field, value] of [
        ['core_digest', identity.coreDigest],
        ['adapter_digest', identity.adapterDigest],
        ['bundle_digest', identity.bundleDigest],
        ['checker_digest', identity.checkerDigest],
        ['runtime_snapshot_digest', identity.runtimeSnapshotDigest],
    ]) {
        if (!IDENTITY_DIGEST.test(value)) {
            problems.push(`${field} must be sha256:<lowercase hex>`);
        }
    }
    if (!normalizedRunReference(identity.bundleLockRef)) {
        problems.push('bundle_lock_ref must be a normalized run-relative or content-addressed reference');
    }
    if (!normalizedRunReference(identity.runtimeSnapshotRef)) {
        problems.push('runtime_snapshot_ref must be a normalized run-relative reference');
    }
    if (!exactIdentityLabel(identity.hostIdentity)) {
        problems.push('host_identity must be exact and must not be a mutable alias');
    }
    if (manifest.mode === 'manual') {
        if (identity.adapterId !== 'core-manual') {
            problems.push('manual forward-format runs must use adapter_id core-manual');
        }
        if (identity.hostIdentity !== 'human-operator') {
            problems.push('manual forward-format runs must use host_identity human-operator');
        }
        if (identity.modelIds !== 'human') {
            problems.push('manual forward-format runs must use model_ids human');
        }
        if (identity.adapterProfile !== 'n/a (core-manual)') {
            problems.push('manual forward-format runs must use adapter profile n/a (core-manual)');
        }
        if (identity.modelExecutionMapping !== 'n/a (manual)') {
            problems.push('manual forward-format runs must use model execution mapping n/a (manual)');
        }
    }
    else {
        if (identity.adapterId === 'core-manual') {
            problems.push('agent and hybrid forward-format runs must name a real host adapter');
        }
        if (!exactJsonObject(identity.modelIds)) {
            problems.push('model_ids must be a nonempty exact JSON object for agent or hybrid runs');
        }
        if (!/^.+ @ sha256:[a-f0-9]{64}$/.test(identity.adapterProfile)) {
            problems.push('adapter profile ID + digest must include an exact sha256 digest');
        }
        if (!exactJsonObject(identity.modelExecutionMapping)) {
            problems.push('model/context/effort mapping must be a nonempty exact JSON object');
        }
    }
    return problems;
}
export function loadRunManifest(runDir) {
    return parseManifest(readDocument(runDir, 'run-manifest.md'));
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
    const table = findTable(document.tables, PACKET_DEFINITION_HEADER)
        || findTableByFirstHeader(document.tables, 'packet id');
    return rowObjects(table, [
        'packetId', 'sourceId', 'locator', 'spanHash', 'quote', 'criterion', 'status',
    ]);
}
function parseExactEvidence(document) {
    if (!document) {
        return {
            format: '',
            records: [],
            fragments: [],
            transformations: [],
            recordTable: null,
            fragmentTable: null,
            transformationTable: null,
        };
    }
    const recordTable = findTable(document.tables, [
        'evidence key',
        'packet ids',
        'evidence state',
        'fragment count',
        'join policy',
        'exact evidence hash',
        'degraded source id',
        'degraded source locator',
        'degradation reason',
    ]);
    const fragmentTable = findTable(document.tables, [
        'fragment key',
        'evidence key',
        'packet id',
        'fragment order',
        'source id',
        'locator',
        'source relation',
        'byte role',
        'fragment hash',
        'exact bytes base64',
    ]);
    const transformationTable = findTable(document.tables, [
        'transform key',
        'evidence key',
        'output role',
        'predecessor exact evidence hash',
        'effective exact evidence hash',
        'output text',
        'output text hash',
    ]);
    return {
        format: document.bullets.fields.get('exact evidence format') || '',
        records: rowObjects(recordTable, [
            'evidenceKey',
            'packetIds',
            'evidenceState',
            'fragmentCount',
            'joinPolicy',
            'exactEvidenceHash',
            'degradedSourceId',
            'degradedSourceLocator',
            'degradationReason',
        ]),
        fragments: rowObjects(fragmentTable, [
            'fragmentKey',
            'evidenceKey',
            'packetId',
            'fragmentOrder',
            'sourceId',
            'locator',
            'sourceRelation',
            'byteRole',
            'fragmentHash',
            'exactBytesBase64',
        ]),
        transformations: rowObjects(transformationTable, [
            'transformKey',
            'evidenceKey',
            'outputRole',
            'predecessorExactEvidenceHash',
            'effectiveExactEvidenceHash',
            'outputText',
            'outputTextHash',
        ]),
        recordTable,
        fragmentTable,
        transformationTable,
    };
}
function parseSourceWalk(document) {
    if (!document) {
        return {
            format: '',
            positionFormat: '',
            intervals: [],
            events: [],
            cursors: [],
            gapReviews: [],
            completions: [],
            intervalTable: null,
            eventTable: null,
            cursorTable: null,
            gapReviewTable: null,
            completionTable: null,
        };
    }
    const intervalTable = findTable(document.tables, [
        'walk id',
        'source id',
        'start byte',
        'end byte',
        'outcome',
        'packet ids',
        'criterion ref',
        'producer invocation id',
        'closure state',
        'reason',
        'closure note',
    ]);
    const eventTable = findTable(document.tables, [
        'event id',
        'source id',
        'start byte',
        'end byte',
        'shared position key',
        'event ordinal',
        'packet id',
        'origin',
        'producer invocation id',
        'status',
    ]);
    const cursorTable = findTable(document.tables, [
        'cursor id',
        'source id',
        'byte offset',
        'shared position key',
        'next event ordinal',
        'predecessor walk id',
        'predecessor event id',
        'source hash',
        'reason',
    ]);
    const gapReviewTable = findTable(document.tables, [
        'gap review id',
        'source id',
        'producer invocation id',
        'reviewer invocation id',
        'review basis cursor id',
        'review basis digest',
        'result',
        'candidate start byte',
        'candidate end byte',
        'proposed packet id',
        'reconciliation event id',
        'status',
        'note',
    ]);
    const completionTable = findTable(document.tables, [
        'source id',
        'source hash',
        'source length bytes',
        'final cursor id',
        'gap review ids',
        'completion state',
        'declared by',
        'note',
    ]);
    return {
        format: document.bullets.fields.get('source walk format') || '',
        positionFormat: document.bullets.fields.get('source position format') || '',
        intervals: rowObjects(intervalTable, [
            'walkId',
            'sourceId',
            'startByte',
            'endByte',
            'outcome',
            'packetIds',
            'criterionRef',
            'producerInvocationId',
            'closureState',
            'reason',
            'closureNote',
        ]),
        events: rowObjects(eventTable, [
            'eventId',
            'sourceId',
            'startByte',
            'endByte',
            'sharedPositionKey',
            'eventOrdinal',
            'packetId',
            'origin',
            'producerInvocationId',
            'status',
        ]),
        cursors: rowObjects(cursorTable, [
            'cursorId',
            'sourceId',
            'byteOffset',
            'sharedPositionKey',
            'nextEventOrdinal',
            'predecessorWalkId',
            'predecessorEventId',
            'sourceHash',
            'reason',
        ]),
        gapReviews: rowObjects(gapReviewTable, [
            'gapReviewId',
            'sourceId',
            'producerInvocationId',
            'reviewerInvocationId',
            'reviewBasisCursorId',
            'reviewBasisDigest',
            'result',
            'candidateStartByte',
            'candidateEndByte',
            'proposedPacketId',
            'reconciliationEventId',
            'status',
            'note',
        ]),
        completions: rowObjects(completionTable, [
            'sourceId',
            'sourceHash',
            'sourceLengthBytes',
            'finalCursorId',
            'gapReviewIds',
            'completionState',
            'declaredBy',
            'note',
        ]),
        intervalTable,
        eventTable,
        cursorTable,
        gapReviewTable,
        completionTable,
    };
}
function parseClaims(document) {
    if (!document)
        return [];
    const table = findTable(document.tables, CLAIM_DEFINITION_HEADER)
        || findTableByFirstHeader(document.tables, 'claim id');
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
    const sourceWalkDocument = get('ledgers/source-walk.md');
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
        exactEvidence: parseExactEvidence(packetDocument),
        sourceWalk: parseSourceWalk(sourceWalkDocument),
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
        sourceWalkDocument,
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
