import { findTables, parseBulletFields } from './markdown.ts';
import type { MarkdownTable, MarkdownTableRow } from './markdown.ts';
import type { ClaimRow, RunDocument, RunModel } from './run-model.ts';

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
] as const;
export const LINEAGE_TABLE_HEADER = [
  'lineage_id',
  'owner_stage',
  'type',
  'predecessors',
  'successors',
  'basis',
  'established_by',
] as const;

export type LineageType = typeof LINEAGE_TYPES[number];
export type UnitFamily = 'PKT' | 'CC';

export interface LineageValues {
  lineageId: string;
  ownerStage: string;
  type: string;
  predecessors: string;
  successors: string;
  basis: string;
  establishedBy: string;
}

export interface LineageRow extends MarkdownTableRow {
  values: LineageValues;
}

export interface ParsedUnitIds {
  ids: string[];
  clean: boolean;
  family: UnitFamily | null;
}

export interface LineageModel {
  document: RunDocument | null;
  format: string;
  tables: MarkdownTable[];
  table: MarkdownTable | null;
  rows: LineageRow[];
}

export function parseUnitIds(value: string, allowNone = false): ParsedUnitIds {
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
    family: families.size === 1 ? [...families][0] as UnitFamily : null,
  };
}

export function parseLineage(model: RunModel): LineageModel {
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
  const rows: LineageRow[] = (table?.rows || []).map((row) => ({
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

export function lineagePredecessorIds(model: RunModel): Set<string> {
  const predecessors = new Set<string>();
  for (const row of parseLineage(model).rows) {
    const parsed = parseUnitIds(row.values.predecessors);
    if (!parsed.clean) continue;
    for (const id of parsed.ids) predecessors.add(id);
  }
  return predecessors;
}

export function lineageCurrentPacketIds(model: RunModel): Set<string> {
  const predecessors = lineagePredecessorIds(model);
  return new Set(
    model.packets
      .map((row) => row.values.packetId)
      .filter((id) => /^PKT-\d+$/.test(id) && !predecessors.has(id)),
  );
}

export function lineageCurrentClaimIds(model: RunModel): Set<string> {
  const predecessors = lineagePredecessorIds(model);
  return new Set(
    model.claims
      .map((row) => row.values.claimId)
      .filter((id) => /^CC-\d+$/.test(id) && !predecessors.has(id)),
  );
}

export function lineageCurrentClaims(model: RunModel): ClaimRow[] {
  const ids = lineageCurrentClaimIds(model);
  return model.claims.filter((claim) => ids.has(claim.values.claimId));
}
