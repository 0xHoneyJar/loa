import { existsSync, readFileSync } from 'node:fs';
import { firstRunLogEntry, location, mdLineSpan, normalizeSha256, reachedState, sha256, sourceFilePath, } from './check-helpers.js';
import { lineageCurrentClaimIds, lineageCurrentPacketIds, } from './lineage.js';
import { findTables, normalizeHeader } from './markdown.js';
import { RELATION_EXPLICIT_ABSENCE_REASON, RELATION_FAMILIES, RELATION_FAMILY_TYPES, RELATION_FORMAT, RELATION_INDETERMINATE_REASONS, RELATION_RECORD_STATES, RELATION_TABLE_HEADER, RELATION_TYPES, RELATION_UNRESOLVED_REASONS, parsePacketBasis, parseRelations, relationReviewSubjectDigest, } from './relations.js';
import { SUPPORTED_RUN_FORMAT_VERSIONS, usesInternalAmbiguityLifecycle, usesTypedRelations, } from './run-model.js';
const SOURCE_KINDS = ['CC', 'PKT'];
const TARGET_KINDS = ['CC', 'PKT', 'source-locus', 'null'];
const CONCRETE_TARGET_KINDS = ['CC', 'PKT', 'source-locus'];
const POST_S4_STATES = [
    'ASSEMBLED',
    'VERIFIED',
    'ACCEPTED',
    'PROJECTING',
    'PROJECTION-ACCEPTED',
];
const VERDICT_REQUIRED_FIELDS = [
    'target',
    'lens',
    'stage',
    'shown',
    'withheld',
    'verdict',
    'consequence',
];
const VERDICT_REQUIRED_FIELD_SET = new Set(VERDICT_REQUIRED_FIELDS);
function isOneOf(value, values) {
    return values.includes(value);
}
function relationClosureRecorded(model) {
    const version = model.manifest?.runFormatVersion || '';
    if (usesInternalAmbiguityLifecycle(version)) {
        return Boolean(model.runLog?.lines.some((line) => (/^\s*closure_phase:\s*S4-C1-relations-closed\s*$/u.test(line))));
    }
    if (POST_S4_STATES.some((state) => reachedState(model, state)))
        return true;
    if (firstRunLogEntry(model.runLog, 'S5'))
        return true;
    return Boolean(model.runLog?.lines.some((line) => (/^##\s+.+[—-]\s+S4\s+[—-]\s+(?:exit|closed|closure)\b/i.test(line))));
}
function relationStructurePresent(model) {
    return [...model.documents.values()].some((document) => (document !== null
        && (document.relativePath === 'ledgers/relations.md'
            || /^\s*-\s*relation[_ -]format\s*:/im.test(document.text)
            || document.tables.some((table) => table.normalizedHeader[0] === 'relation id'))));
}
function exactId(value, family) {
    return new RegExp(`^${family}-\\d+$`).test(value);
}
function sourceForUnit(model, kind, id) {
    if (kind === 'PKT') {
        const row = model.packets.find((packet) => packet.values.packetId === id);
        return new Set(row ? [row.values.sourceId] : []);
    }
    const row = model.claims.find((claim) => claim.values.claimId === id);
    return new Set(row ? row.values.sources.split(',').map((part) => part.trim()).filter(Boolean) : []);
}
function verifierVerdicts(model, id) {
    const verdicts = [];
    for (const document of model.documents.values()) {
        if (!document)
            continue;
        if (!document.relativePath.startsWith('verification/harness/'))
            continue;
        if (document.relativePath.split('/').at(-1) !== `${id}.md`)
            continue;
        const heading = document.lines.find((line) => line.trim() !== '');
        if (heading !== `# Verdict ${id}`)
            continue;
        const canonicalTables = findTables(document.tables, ['field', 'value']);
        const fieldValues = new Map();
        if (canonicalTables.length === 1) {
            for (const row of canonicalTables[0].rows) {
                if (row.cells.length !== 2)
                    continue;
                const field = normalizeHeader(row.cells[0]);
                if (!VERDICT_REQUIRED_FIELD_SET.has(field))
                    continue;
                if (!fieldValues.has(field))
                    fieldValues.set(field, []);
                fieldValues.get(field).push(row.cells[1].trim());
            }
        }
        const invalidFields = canonicalTables.length === 1
            ? VERDICT_REQUIRED_FIELDS.filter((field) => {
                const values = fieldValues.get(field) || [];
                return values.length !== 1 || values[0] === '';
            })
            : [];
        verdicts.push({
            file: document.relativePath,
            target: fieldValues.get('target')?.[0] || '',
            verdict: fieldValues.get('verdict')?.[0] || '',
            canonicalFieldTableCount: canonicalTables.length,
            invalidFields,
        });
    }
    return verdicts;
}
function concreteTarget(row) {
    const values = row.values;
    if (values.targetKind === 'CC' || values.targetKind === 'PKT') {
        return values.targetId;
    }
    if (values.targetKind === 'source-locus') {
        return [
            values.targetSourceId,
            values.targetLocator,
            values.targetSpanHash,
        ].join('|');
    }
    return 'null';
}
function cycleStart(edges) {
    const graph = new Map();
    for (const [source, target] of edges) {
        if (!graph.has(source))
            graph.set(source, []);
        graph.get(source).push(target);
    }
    const visiting = new Set();
    const visited = new Set();
    const visit = (id) => {
        if (visiting.has(id))
            return id;
        if (visited.has(id))
            return null;
        visiting.add(id);
        for (const target of graph.get(id) || []) {
            const found = visit(target);
            if (found)
                return found;
        }
        visiting.delete(id);
        visited.add(id);
        return null;
    };
    for (const id of graph.keys()) {
        const found = visit(id);
        if (found)
            return found;
    }
    return null;
}
function checkSourceLocus(model, row, source, fail) {
    const values = row.values;
    const label = values.relationId || 'relation row';
    if (!source)
        return;
    const scheme = source.values.scheme;
    if (scheme !== 'md-lines') {
        fail(`${label} source-locus scheme "${scheme || '(blank)'}" is declared but not deterministically reopenable by this Core`);
        return;
    }
    const match = values.targetLocator.match(/^L([1-9]\d*)-L([1-9]\d*)$/);
    if (!match) {
        fail(`${label} target_locator must be an md-lines L<start>-L<end> locator`);
        return;
    }
    const path = sourceFilePath(model.runDir, source.values.locus);
    if (!path || !existsSync(path)) {
        fail(`${label} target_source_id ${values.targetSourceId} does not reopen a frozen source file`);
        return;
    }
    const declaredSourceHash = normalizeSha256(source.values.contentHash);
    if (!declaredSourceHash || sha256(readFileSync(path)) !== declaredSourceHash) {
        fail(`${label} target_source_id ${values.targetSourceId} frozen source bytes do not match the manifest hash`);
        return;
    }
    const span = mdLineSpan(path, Number(match[1]), Number(match[2]));
    if (!span?.bytes) {
        fail(`${label} target_locator ${values.targetLocator} is outside the frozen md-lines source`);
        return;
    }
    if (!/^sha256:[a-f0-9]{64}$/.test(values.targetSpanHash)) {
        fail(`${label} target_span_hash must be full lowercase sha256:<hex>`);
        return;
    }
    if (`sha256:${sha256(span.bytes)}` !== values.targetSpanHash) {
        fail(`${label} target_span_hash does not match the exact reopened source-locus bytes`);
    }
}
function sourceKindLegal(row) {
    const values = row.values;
    if (!isOneOf(values.sourceKind, SOURCE_KINDS))
        return true;
    if (values.type === 'semantic-prerequisite'
        || (values.family === 'claim-dependency' && values.type === 'none')) {
        return values.sourceKind === 'CC';
    }
    return true;
}
function concreteTargetTypeLegal(row) {
    const values = row.values;
    if (values.recordState !== 'asserted')
        return true;
    if (values.type === 'semantic-prerequisite') {
        return values.targetKind === 'CC';
    }
    if (values.type === 'continuation-context'
        || values.type === 'parallel-contrast-context') {
        return values.targetKind === 'source-locus'
            || values.targetKind === values.sourceKind;
    }
    return isOneOf(values.targetKind, CONCRETE_TARGET_KINDS);
}
function checkRow(model, row, currentClaims, currentPackets, fail) {
    const values = row.values;
    const label = values.relationId || 'relation row';
    const familyKnown = isOneOf(values.family, RELATION_FAMILIES);
    const typeKnown = isOneOf(values.type, RELATION_TYPES);
    if (row.cells.length !== RELATION_TABLE_HEADER.length) {
        fail(`${label} has ${row.cells.length} fields; expected exactly 17`);
    }
    if (!/^REL-\d+$/.test(values.relationId)) {
        fail(`${label} relation_id must be REL-<digits> at ${location(row)}`);
    }
    if (!isOneOf(values.recordState, RELATION_RECORD_STATES)) {
        fail(`${label} record_state "${values.recordState || '(blank)'}" is unsupported`);
    }
    if (values.recordState === 'indeterminate') {
        if (values.family === 'none' && values.type !== 'none') {
            fail(`${label} taxonomy-level indeterminate requires family none and type none`);
        }
        else if (values.family !== 'none' && !familyKnown) {
            fail(`${label} family "${values.family || '(blank)'}" is unsupported`);
        }
        else if (values.type !== 'none' && !typeKnown) {
            fail(`${label} type "${values.type || '(blank)'}" is unsupported`);
        }
    }
    else {
        if (!familyKnown)
            fail(`${label} family "${values.family || '(blank)'}" is unsupported`);
        if (!typeKnown)
            fail(`${label} type "${values.type || '(blank)'}" is unsupported`);
    }
    if (familyKnown
        && values.type !== 'none'
        && !RELATION_FAMILY_TYPES[values.family]
            .includes(values.type)) {
        fail(`${label} family/type mismatch: ${values.family} cannot contain ${values.type}`);
    }
    if (!isOneOf(values.sourceKind, SOURCE_KINDS)) {
        fail(`${label} source_kind must be CC or PKT`);
    }
    const sourceKind = values.sourceKind;
    if (isOneOf(values.sourceKind, SOURCE_KINDS) && !exactId(values.sourceId, sourceKind)) {
        fail(`${label} source_id must be exactly one ${sourceKind}-<digits> identity`);
    }
    const sourceExists = sourceKind === 'CC'
        ? model.claims.some((claim) => claim.values.claimId === values.sourceId)
        : model.packets.some((packet) => packet.values.packetId === values.sourceId);
    if (isOneOf(values.sourceKind, SOURCE_KINDS) && !sourceExists) {
        fail(`${label} source ${values.sourceId || '(blank)'} does not resolve as ${sourceKind}`);
    }
    if (sourceExists
        && !(sourceKind === 'CC'
            ? currentClaims.has(values.sourceId)
            : currentPackets.has(values.sourceId))) {
        fail(`${label} source ${values.sourceId} is a historical lineage predecessor, not lineage-current`);
    }
    if (!isOneOf(values.targetKind, TARGET_KINDS)) {
        fail(`${label} target_kind "${values.targetKind || '(blank)'}" is unsupported`);
    }
    if (values.recordState === 'asserted') {
        if (!isOneOf(values.targetKind, CONCRETE_TARGET_KINDS)) {
            fail(`${label} asserted relation requires a concrete CC, PKT, or source-locus target`);
        }
        if (values.nullReason !== 'none') {
            fail(`${label} asserted relation requires null_reason none`);
        }
        if (values.targetKind === 'CC' || values.targetKind === 'PKT') {
            if (!exactId(values.targetId, values.targetKind)) {
                fail(`${label} target_id must be exactly one ${values.targetKind}-<digits> identity`);
            }
            if (values.targetSourceId !== 'none'
                || values.targetLocator !== 'none'
                || values.targetSpanHash !== 'none') {
                fail(`${label} durable unit target requires all source-locus fields to be none`);
            }
            const targetExists = values.targetKind === 'CC'
                ? model.claims.some((claim) => claim.values.claimId === values.targetId)
                : model.packets.some((packet) => packet.values.packetId === values.targetId);
            if (!targetExists) {
                fail(`${label} target ${values.targetId || '(blank)'} does not resolve as ${values.targetKind}`);
            }
            else if (!(values.targetKind === 'CC'
                ? currentClaims.has(values.targetId)
                : currentPackets.has(values.targetId))) {
                fail(`${label} target ${values.targetId} is a historical lineage predecessor, not lineage-current`);
            }
        }
        else if (values.targetKind === 'source-locus') {
            if (values.targetId !== 'none') {
                fail(`${label} source-locus target requires target_id none`);
            }
            if (!exactId(values.targetSourceId, 'SRC')) {
                fail(`${label} source-locus target_source_id must be exactly one SRC-<digits> identity`);
            }
            const source = model.corpus.sources.find((candidate) => candidate.values.sourceId === values.targetSourceId);
            if (!source) {
                fail(`${label} target_source_id ${values.targetSourceId || '(blank)'} does not resolve`);
            }
            checkSourceLocus(model, row, source, fail);
        }
    }
    else {
        if (values.targetKind !== 'null'
            || values.targetId !== 'none'
            || values.targetSourceId !== 'none'
            || values.targetLocator !== 'none'
            || values.targetSpanHash !== 'none') {
            fail(`${label} ${values.recordState || 'typed-null'} requires target_kind null and all target value fields none`);
        }
        if (values.recordState === 'unresolved-target'
            && !isOneOf(values.nullReason, RELATION_UNRESOLVED_REASONS)) {
            fail(`${label} unresolved-target has illegal null_reason "${values.nullReason || '(blank)'}"`);
        }
        if (values.recordState === 'explicitly-absent'
            && values.nullReason !== RELATION_EXPLICIT_ABSENCE_REASON) {
            fail(`${label} explicitly-absent requires null_reason ${RELATION_EXPLICIT_ABSENCE_REASON}`);
        }
        if (values.recordState === 'indeterminate'
            && !isOneOf(values.nullReason, RELATION_INDETERMINATE_REASONS)) {
            fail(`${label} indeterminate has illegal null_reason "${values.nullReason || '(blank)'}"`);
        }
    }
    if (!sourceKindLegal(row)) {
        fail(`${label} ${values.family || '(blank)'}/${values.type || '(blank)'} `
            + 'requires source_kind CC for every record_state');
    }
    if (!concreteTargetTypeLegal(row)) {
        fail(`${label} relation type/endpoint mismatch for ${values.type || '(blank)'}`);
    }
    if (values.type === 'semantic-prerequisite' && !['S3', 'S4'].includes(values.ownerStage)) {
        fail(`${label} semantic-prerequisite owner_stage must be S3 or S4`);
    }
    else if (values.type !== 'semantic-prerequisite' && !['S2', 'S3', 'S4'].includes(values.ownerStage)) {
        fail(`${label} owner_stage must be S2, S3, or S4`);
    }
    if (values.ownerStage === 'S2') {
        if (values.sourceKind !== 'PKT') {
            fail(`${label} S2 relation proposals require a PKT source`);
        }
        if (values.targetKind === 'CC') {
            fail(`${label} S2 relation proposals cannot target claims that do not yet exist`);
        }
        if (values.recordState === 'asserted' && values.sourceKind === 'PKT') {
            const sourceSources = sourceForUnit(model, 'PKT', values.sourceId);
            const targetSources = values.targetKind === 'source-locus'
                ? new Set([values.targetSourceId])
                : values.targetKind === 'PKT'
                    ? sourceForUnit(model, 'PKT', values.targetId)
                    : new Set();
            if ([...targetSources].some((id) => !sourceSources.has(id))) {
                fail(`${label} S2 relation crosses source boundaries`);
            }
        }
    }
    if (values.ownerStage === 'S3' && values.sourceKind !== 'CC') {
        fail(`${label} S3 relation proposals require a CC source`);
    }
    const basis = parsePacketBasis(values.basisPacketIds);
    if (!basis.clean || new Set(basis.ids).size !== basis.ids.length) {
        fail(`${label} basis_packet_ids must be a nonempty ordered comma-separated list of unique PKT ids`);
    }
    for (const packetId of basis.ids) {
        if (!model.packets.some((packet) => packet.values.packetId === packetId)) {
            fail(`${label} basis packet ${packetId} does not resolve`);
        }
    }
    if (!/^(?:human|invocation):\S+$/.test(values.proposedBy)) {
        fail(`${label} proposed_by must use human:<actor-slug> or invocation:<producer-invocation-id>`);
    }
    if (!exactId(values.reviewedBy, 'VER')) {
        fail(`${label} reviewed_by must be exactly one VER-<digits> identity`);
    }
    if (!/^sha256:[a-f0-9]{64}$/.test(values.reviewSubjectDigest)) {
        fail(`${label} review_subject_digest must be full lowercase sha256:<hex>`);
    }
    else {
        const recomputed = relationReviewSubjectDigest(values);
        if (recomputed !== values.reviewSubjectDigest) {
            fail(`${label} review_subject_digest does not match the complete canonical pre-review subject`);
        }
    }
    if (exactId(values.reviewedBy, 'VER')) {
        const verdicts = verifierVerdicts(model, values.reviewedBy);
        if (verdicts.length !== 1) {
            fail(`${label} reviewed_by ${values.reviewedBy} must resolve to exactly one verifier verdict; found ${verdicts.length}`);
        }
        else {
            const verifier = verdicts[0];
            if (verifier.canonicalFieldTableCount !== 1) {
                fail(`${label} ${values.reviewedBy} at ${verifier.file} must contain exactly one canonical `
                    + `field | value verdict table; found ${verifier.canonicalFieldTableCount}`);
            }
            else if (verifier.invalidFields.length > 0) {
                fail(`${label} ${values.reviewedBy} canonical verdict field table requires exactly one `
                    + `nonblank row for: ${verifier.invalidFields.join(', ')}`);
            }
            else {
                const expectedTarget = `relation-review-subject:${values.reviewSubjectDigest}`;
                if (verifier.target !== expectedTarget) {
                    fail(`${label} ${values.reviewedBy} target must equal ${expectedTarget} exactly`);
                }
                if (verifier.verdict !== 'upheld') {
                    fail(`${label} ${values.reviewedBy} verdict must be upheld, not ${verifier.verdict || '(blank)'}`);
                }
            }
        }
    }
    if (values.recordState === 'asserted'
        && (values.targetKind === 'CC' || values.targetKind === 'PKT')
        && values.sourceKind === values.targetKind
        && values.sourceId === values.targetId) {
        fail(`${label} self-edge ${values.sourceId} -> ${values.targetId} is forbidden`);
    }
}
export function runK2Relations(results, model) {
    results.run('K2.16', 'typed relation structure and current-endpoint closure', (fail) => {
        const version = model.manifest?.runFormatVersion || '';
        const relations = parseRelations(model);
        const structurePresent = relationStructurePresent(model);
        if (!usesTypedRelations(version)) {
            if (structurePresent) {
                fail(`run format ${version || '(pre-versioned)'} must not be reinterpreted as ${RELATION_FORMAT}`);
            }
            if (version && !SUPPORTED_RUN_FORMAT_VERSIONS.includes(version)) {
                fail(`typed-relation activation cannot determine unsupported run_format_version "${version}"`);
            }
            return `typed relations are not applicable to run format ${version || '(pre-versioned)'}`;
        }
        const closureRecorded = relationClosureRecorded(model);
        if (!relations.document) {
            if (structurePresent) {
                fail('typed relation structure must use canonical path ledgers/relations.md');
            }
            if (closureRecorded) {
                fail(usesInternalAmbiguityLifecycle(version)
                    ? `run format ${version} requires ledgers/relations.md at S4-C1`
                    : `run format ${version} requires ledgers/relations.md once S4 is closed or S5 begins`);
            }
            return `typed relation artifact is not required before retained S4 closure in run format ${version}`;
        }
        const markerCount = relations.document.lines.filter((line) => /^\s*-\s*relation[_ -]format\s*:/i.test(line)).length;
        if (markerCount !== 1 || relations.format !== RELATION_FORMAT) {
            fail(`run format ${version} requires relation_format ${RELATION_FORMAT} exactly once`);
        }
        if (relations.relationTables.length !== 1
            || relations.canonicalTables.length !== 1) {
            fail(`run format ${version} requires exactly one canonical 17-column relation table; `
                + `found ${relations.relationTables.length} relation table(s) and `
                + `${relations.canonicalTables.length} exact schema match(es)`);
        }
        for (const table of relations.relationTables) {
            const forbidden = table.normalizedHeader.filter((header) => (/(?:^| )(?:support|evidence role|load bearing|corroborative|contradictory)(?: |$)/.test(header)));
            if (forbidden.length > 0) {
                fail(`relation table contains forbidden support/evidence-role field(s): ${forbidden.join(', ')}`);
            }
            if (table.normalizedHeader.length !== RELATION_TABLE_HEADER.length
                || table.normalizedHeader.some((header, index) => header !== RELATION_TABLE_HEADER[index].replaceAll('_', ' '))) {
                fail('relation table must use the exact adopted 17-column schema');
            }
        }
        if (relations.canonicalTables.length !== 1) {
            return 'typed relation structure is not structurally valid';
        }
        if (!closureRecorded && relations.rows.length > 0) {
            fail('retained pre-S4-closure state may contain only the marker and an empty canonical relation table');
        }
        const currentClaims = lineageCurrentClaimIds(model);
        const currentPackets = lineageCurrentPacketIds(model);
        const relationIds = new Set();
        for (const row of relations.rows) {
            if (relationIds.has(row.values.relationId)) {
                fail(`${row.values.relationId || 'relation row'} is defined more than once at ${location(row)}`);
            }
            else if (row.values.relationId) {
                relationIds.add(row.values.relationId);
            }
            checkRow(model, row, currentClaims, currentPackets, fail);
        }
        const assertedTuples = new Map();
        const subtypeScopes = new Map();
        const familyScopes = new Map();
        const sourceScopes = new Map();
        for (const row of relations.rows) {
            const values = row.values;
            const sourceScope = `${values.sourceKind}|${values.sourceId}`;
            const familyScope = `${sourceScope}|${values.family}`;
            const subtypeScope = `${familyScope}|${values.type}`;
            if (!sourceScopes.has(sourceScope))
                sourceScopes.set(sourceScope, []);
            if (!familyScopes.has(familyScope))
                familyScopes.set(familyScope, []);
            if (!subtypeScopes.has(subtypeScope))
                subtypeScopes.set(subtypeScope, []);
            sourceScopes.get(sourceScope).push(row);
            familyScopes.get(familyScope).push(row);
            subtypeScopes.get(subtypeScope).push(row);
            if (values.recordState === 'asserted') {
                const tuple = [
                    values.family,
                    values.type,
                    values.sourceKind,
                    values.sourceId,
                    values.targetKind,
                    concreteTarget(row),
                ].join('|');
                const prior = assertedTuples.get(tuple);
                if (prior) {
                    fail(`${values.relationId || 'relation row'} duplicates semantic tuple already recorded by ${prior}`);
                }
                else {
                    assertedTuples.set(tuple, values.relationId || '(malformed relation row)');
                }
            }
        }
        for (const rows of subtypeScopes.values()) {
            const typedNulls = rows.filter((row) => row.values.recordState !== 'asserted');
            if (typedNulls.length > 1) {
                fail(`${typedNulls[0].values.sourceId} ${typedNulls[0].values.family}/${typedNulls[0].values.type} `
                    + 'has more than one typed-null row');
            }
            const states = new Set(rows.map((row) => row.values.recordState));
            if (states.has('explicitly-absent')
                && (states.has('asserted') || states.has('unresolved-target'))) {
                fail(`${rows[0].values.sourceId} ${rows[0].values.family}/${rows[0].values.type} `
                    + 'conflicts between explicit absence and asserted/unresolved closure');
            }
            if (states.has('indeterminate') && states.has('asserted')) {
                fail(`${rows[0].values.sourceId} ${rows[0].values.family}/${rows[0].values.type} `
                    + 'conflicts between subtype-scoped indeterminate and asserted closure');
            }
        }
        for (const rows of familyScopes.values()) {
            const familyIndeterminate = rows.some((row) => (row.values.recordState === 'indeterminate' && row.values.type === 'none'));
            const concrete = rows.some((row) => row.values.type !== 'none');
            if (familyIndeterminate && concrete) {
                fail(`${rows[0].values.sourceId} family ${rows[0].values.family} cannot combine `
                    + 'family-level indeterminate with a concrete subtype row');
            }
        }
        for (const rows of sourceScopes.values()) {
            const taxonomyIndeterminate = rows.some((row) => (row.values.recordState === 'indeterminate'
                && row.values.family === 'none'
                && row.values.type === 'none'));
            if (taxonomyIndeterminate && rows.length > 1) {
                fail(`${rows[0].values.sourceId} taxonomy-level indeterminate cannot coexist with another relation row`);
            }
        }
        const assertedUnitEdges = relations.rows.filter((row) => (row.values.recordState === 'asserted'
            && (row.values.targetKind === 'CC' || row.values.targetKind === 'PKT')));
        const prohibitedSubgraphs = [
            {
                name: 'semantic-prerequisite',
                includes: (row) => row.values.type === 'semantic-prerequisite',
            },
            {
                name: 'antecedent-context',
                includes: (row) => row.values.type === 'antecedent-context',
            },
            {
                name: 'formal-reference',
                includes: (row) => row.values.family === 'formal-reference',
            },
            {
                name: 'continuation-context',
                includes: (row) => row.values.type === 'continuation-context',
            },
            {
                name: 'parallel-contrast-context',
                includes: (row) => row.values.type === 'parallel-contrast-context',
            },
        ];
        for (const subgraph of prohibitedSubgraphs) {
            const edges = assertedUnitEdges
                .filter(subgraph.includes)
                .map((row) => [row.values.sourceId, row.values.targetId]);
            const start = cycleStart(edges);
            if (start) {
                fail(`${subgraph.name} prohibited subgraph contains a cycle reachable from ${start}`);
            }
        }
        return 'typed relation retained-state structure and current-endpoint closure are structurally valid';
    });
}
