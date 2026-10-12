import { createHash } from 'node:crypto';
import { findTables, normalizeHeader, parseBulletFields } from './markdown.js';
export const RELATION_FORMAT = 'aleph-relations/v1';
export const RELATION_REVIEW_SUBJECT_FORMAT = 'aleph-relation-review-subject/v1';
export const RELATION_TABLE_HEADER = [
    'relation_id',
    'owner_stage',
    'family',
    'type',
    'source_kind',
    'source_id',
    'target_kind',
    'target_id',
    'target_source_id',
    'target_locator',
    'target_span_hash',
    'record_state',
    'null_reason',
    'basis_packet_ids',
    'proposed_by',
    'review_subject_digest',
    'reviewed_by',
];
export const RELATION_FAMILIES = [
    'claim-dependency',
    'source-context',
    'formal-reference',
    'discourse',
];
export const RELATION_TYPES = [
    'semantic-prerequisite',
    'antecedent-context',
    'qualifier-context',
    'configuration-context',
    'structural-anchor',
    'notation-definition',
    'continuation-context',
    'parallel-contrast-context',
];
export const RELATION_FAMILY_TYPES = {
    'claim-dependency': ['semantic-prerequisite'],
    'source-context': [
        'antecedent-context',
        'qualifier-context',
        'configuration-context',
    ],
    'formal-reference': ['structural-anchor', 'notation-definition'],
    discourse: ['continuation-context', 'parallel-contrast-context'],
};
export const RELATION_RECORD_STATES = [
    'asserted',
    'unresolved-target',
    'explicitly-absent',
    'indeterminate',
];
export const RELATION_UNRESOLVED_REASONS = [
    'unresolved-in-frozen-corpus',
    'outside-frozen-corpus',
    'target-not-materialized',
];
export const RELATION_INDETERMINATE_REASONS = [
    'insufficient-frozen-context',
    'conflicting-durable-representations',
    'unsupported-source-structure',
];
export const RELATION_EXPLICIT_ABSENCE_REASON = 'bounded-review-found-none';
export function parsePacketBasis(value) {
    const parts = value.split(',').map((part) => part.trim());
    const ids = parts.filter(Boolean);
    return {
        ids,
        clean: ids.length > 0
            && ids.length === parts.length
            && ids.every((id) => /^PKT-\d+$/.test(id)),
    };
}
export function parseRelations(model) {
    const document = model.documents.get('ledgers/relations.md') || null;
    if (!document) {
        return {
            document: null,
            format: '',
            relationTables: [],
            canonicalTables: [],
            table: null,
            rows: [],
        };
    }
    const bullets = parseBulletFields(document.text);
    const canonicalTables = findTables(document.tables, RELATION_TABLE_HEADER);
    const relationTables = document.tables.filter((table) => normalizeHeader(table.header[0]) === 'relation id');
    const table = canonicalTables[0] || null;
    const rows = (table?.rows || []).map((row) => ({
        ...row,
        values: {
            relationId: row.cells[0] || '',
            ownerStage: row.cells[1] || '',
            family: row.cells[2] || '',
            type: row.cells[3] || '',
            sourceKind: row.cells[4] || '',
            sourceId: row.cells[5] || '',
            targetKind: row.cells[6] || '',
            targetId: row.cells[7] || '',
            targetSourceId: row.cells[8] || '',
            targetLocator: row.cells[9] || '',
            targetSpanHash: row.cells[10] || '',
            recordState: row.cells[11] || '',
            nullReason: row.cells[12] || '',
            basisPacketIds: row.cells[13] || '',
            proposedBy: row.cells[14] || '',
            reviewSubjectDigest: row.cells[15] || '',
            reviewedBy: row.cells[16] || '',
        },
    }));
    return {
        document,
        format: bullets.fields.get('relation format') || '',
        relationTables,
        canonicalTables,
        table,
        rows,
    };
}
export function relationReviewSubjectJson(values) {
    return JSON.stringify({
        format: RELATION_REVIEW_SUBJECT_FORMAT,
        owner_stage: values.ownerStage,
        family: values.family,
        type: values.type,
        source_kind: values.sourceKind,
        source_id: values.sourceId,
        target_kind: values.targetKind,
        target_id: values.targetId,
        target_source_id: values.targetSourceId,
        target_locator: values.targetLocator,
        target_span_hash: values.targetSpanHash,
        record_state: values.recordState,
        null_reason: values.nullReason,
        basis_packet_ids: parsePacketBasis(values.basisPacketIds).ids,
        proposed_by: values.proposedBy,
    });
}
export function relationReviewSubjectDigest(values) {
    return `sha256:${createHash('sha256')
        .update(Buffer.from(relationReviewSubjectJson(values), 'utf8'))
        .digest('hex')}`;
}
export function requireRelationWriteWindow(phase) {
    if (phase !== 's4-closure') {
        throw new Error(`canonical relation writes are forbidden during ${phase}`);
    }
}
