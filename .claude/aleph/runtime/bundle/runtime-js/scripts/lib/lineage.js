import { findTables, parseBulletFields } from './markdown.js';
export const LINEAGE_FORMAT = 'aleph-lineage/v1';
export const LINEAGE_TYPES = [
    'split',
    'merge',
    'replace',
    'supersede',
    'duplicate',
    'reject',
    'exclude',
    'no-claim',
];
export const LINEAGE_TABLE_HEADER = [
    'lineage_id',
    'owner_stage',
    'type',
    'predecessors',
    'successors',
    'basis',
    'established_by',
];
export function parseUnitIds(value, allowNone = false) {
    const cleanValue = value.trim();
    if (allowNone && cleanValue === 'none') {
        return { ids: [], clean: true, family: null };
    }
    const parts = cleanValue.split(',').map((part) => part.trim());
    if (parts.length === 0 || parts.some((part) => !/^(?:PKT|CC)-\d+$/.test(part))) {
        return { ids: parts.filter(Boolean), clean: false, family: null };
    }
    const families = new Set(parts.map((part) => part.startsWith('PKT-') ? 'PKT' : 'CC'));
    return {
        ids: parts,
        clean: true,
        family: families.size === 1 ? [...families][0] : null,
    };
}
export function parseLineage(model) {
    const document = model.documents.get('ledgers/lineage.md') || null;
    if (!document) {
        return {
            document: null,
            format: '',
            tables: [],
            table: null,
            rows: [],
        };
    }
    const bullets = parseBulletFields(document.text);
    const format = bullets.fields.get('lineage format') || '';
    const tables = findTables(document.tables, LINEAGE_TABLE_HEADER);
    const table = tables[0] || null;
    const rows = (table?.rows || []).map((row) => ({
        ...row,
        values: {
            lineageId: row.cells[0] || '',
            ownerStage: row.cells[1] || '',
            type: row.cells[2] || '',
            predecessors: row.cells[3] || '',
            successors: row.cells[4] || '',
            basis: row.cells[5] || '',
            establishedBy: row.cells[6] || '',
        },
    }));
    return {
        document,
        format,
        tables,
        table,
        rows,
    };
}
export function lineagePredecessorIds(model) {
    const predecessors = new Set();
    for (const row of parseLineage(model).rows) {
        const parsed = parseUnitIds(row.values.predecessors);
        if (!parsed.clean)
            continue;
        for (const id of parsed.ids)
            predecessors.add(id);
    }
    return predecessors;
}
export function lineageCurrentPacketIds(model) {
    const predecessors = lineagePredecessorIds(model);
    return new Set(model.packets
        .map((row) => row.values.packetId)
        .filter((id) => /^PKT-\d+$/.test(id) && !predecessors.has(id)));
}
export function lineageCurrentClaimIds(model) {
    const predecessors = lineagePredecessorIds(model);
    return new Set(model.claims
        .map((row) => row.values.claimId)
        .filter((id) => /^CC-\d+$/.test(id) && !predecessors.has(id)));
}
export function lineageCurrentClaims(model) {
    const ids = lineageCurrentClaimIds(model);
    return model.claims.filter((claim) => ids.has(claim.values.claimId));
}
