import {
  existsSync,
  lstatSync,
  readFileSync,
  readdirSync,
} from 'node:fs';
import { basename, join, relative, sep } from 'node:path';
import {
  findTable,
  findTableByFirstHeader,
  parseBulletFields,
  parseFieldTable,
  parseTables,
} from './markdown.ts';
import type {
  BulletFields,
  FieldTable,
  MarkdownDocument,
  MarkdownTable,
  MarkdownTableRow,
} from './markdown.ts';

export const DISPOSITIONS = [
  'carried',
  'merged',
  'deferred',
  'excluded-with-reason',
  'backgrounded',
  'judged-non-load-bearing',
  'unresolved',
] as const;

export type Disposition = typeof DISPOSITIONS[number];

export interface RunFile {
  path: string;
  relativePath: string;
  text: string;
}

export interface RunDocument extends MarkdownDocument {
  path: string;
  relativePath: string;
  bullets: BulletFields;
}

export interface RunRow<TValues extends object = Record<string, string>>
  extends MarkdownTableRow {
  values: TValues;
}

export interface LocatedValues<TValues extends object = Record<string, string>> {
  file: string;
  line: number;
  values: TValues;
}

export interface ManifestStateValues {
  number: string;
  state: string;
  entered: string;
  actor: string;
  note: string;
}

export interface ManifestSignoffValues {
  gate: string;
  decision: string;
  by: string;
  date: string;
  reference: string;
}

export type ManifestStateRow = RunRow<ManifestStateValues>;
export type ManifestSignoffRow = RunRow<ManifestSignoffValues>;
export type RunIdRow = LocatedValues<{ runId: string }>;

export interface RunManifest extends RunDocument {
  mode: string;
  doctrineSha: string;
  corpusHash: string;
  runId: string;
  predecessorRun: string;
  runIdRow: RunIdRow;
  states: ManifestStateRow[];
  signoffs: ManifestSignoffRow[];
}

export interface SourceValues {
  sourceId: string;
  kind: string;
  locus: string;
  scheme: string;
  contentHash: string;
  dates: string;
  trustClass: string;
  sensitivity: string;
  admissionNote: string;
}

export interface PacketValues {
  packetId: string;
  sourceId: string;
  locator: string;
  spanHash: string;
  quote: string;
  criterion: string;
  status: string;
}

export interface ClaimValues {
  claimId: string;
  normalizedClaim: string;
  packets: string;
  sources: string;
  claimType: string;
  disposition: string;
  rationale: string;
  judgedBy: string;
  verified: string;
  status: string;
}

export interface DispositionValues {
  disposition: string;
  count: string;
  claimIds: string;
}

export interface MergeValues {
  canonical: string;
  absorbs: string;
  basis: string;
  provenanceRetained: string;
  corroboration: string;
  status: string;
}

export interface EvidenceEdgeValues {
  claimId: string;
  sourceId: string;
  role: string;
  verification: string;
  removalEffect: string;
  note: string;
  status: string;
}

export interface EvidenceMarkerValues {
  claimId: string;
  basisIds: string;
  uncertainty: string;
}

export interface BoundaryValues {
  boundaryId: string;
  type: string;
  statement: string;
  governs: string;
  basis: string;
  status: string;
}

export interface TagValues {
  tag: string;
  memberIds: string;
  basis: string;
}

export interface ReferentValues {
  refId: string;
  need: string;
  depends: string;
  status: string;
  suppliedBy: string;
  intake: string;
  date: string;
  taintNote: string;
}

export interface MatrixValues {
  stmId: string;
  pressure: string;
  sourceRefs: string;
  claimIds: string;
  risk: string;
  handling: string;
  resolvedAt: string;
}

export interface RouteVectorValues {
  signal: string;
  value: string;
}

export interface ProjectionSelectionValues {
  claimId: string;
  disposition: string;
  selection: string;
  reason: string;
}

export interface ProjectionTraceValues {
  anchor: string;
  kind: string;
  backing: string;
  note: string;
}

export type SourceRow = RunRow<SourceValues>;
export type PacketRow = RunRow<PacketValues>;
export type ClaimRow = RunRow<ClaimValues>;
export type DispositionRow = RunRow<DispositionValues>;
export type MergeRow = RunRow<MergeValues>;
export type EvidenceEdgeRow = RunRow<EvidenceEdgeValues>;
export type EvidenceMarkerRow = RunRow<EvidenceMarkerValues>;
export type BoundaryRow = RunRow<BoundaryValues>;
export type TagRow = RunRow<TagValues>;
export type ReferentRow = RunRow<ReferentValues>;
export type MatrixRow = RunRow<MatrixValues>;
export type RouteVectorRow = RunRow<RouteVectorValues>;
export type ProjectionSelectionRow = RunRow<ProjectionSelectionValues>;
export type ProjectionTraceRow = RunRow<ProjectionTraceValues>;

export interface CorpusModel {
  document: RunDocument | null;
  sources: SourceRow[];
}

export interface EvidenceModel {
  edges: EvidenceEdgeRow[];
  markers: EvidenceMarkerRow[];
  accounting: Map<string, number>;
}

export interface RouteCard extends MarkdownDocument {
  path: string;
  relativePath: string;
  fieldTable: FieldTable;
  id: string;
  filenameId: string;
  vectorRows: RouteVectorRow[];
}

export interface ProjectionCommission extends RunDocument {
  fieldTable: FieldTable;
}

export interface ProjectionSelection extends RunDocument {
  rows: ProjectionSelectionRow[];
}

export interface ProjectionTrace extends RunDocument {
  rows: ProjectionTraceRow[];
}

export interface ProjectionModel {
  type: string;
  commission?: ProjectionCommission;
  selection?: ProjectionSelection;
  trace?: ProjectionTrace;
  projectionId: string;
  projectionIdRow: MarkdownTableRow | null;
  projectionTracePath: string;
}

interface ProjectionModelBuilder {
  type: string;
  commission?: ProjectionCommission;
  selection?: ProjectionSelection;
  trace?: ProjectionTrace;
  projectionId?: string;
  projectionIdRow?: MarkdownTableRow | null;
  projectionTracePath?: string;
}

export interface RunModel {
  runDir: string;
  files: RunFile[];
  documents: Map<string, RunDocument | null>;
  manifest: RunManifest | null;
  runLog: RunDocument | null;
  corpus: CorpusModel;
  criteria: RunDocument | null;
  packets: PacketRow[];
  claims: ClaimRow[];
  dispositionRows: DispositionRow[];
  merges: MergeRow[];
  evidence: EvidenceModel;
  boundaries: BoundaryRow[];
  tags: TagRow[];
  referents: ReferentRow[];
  matrix: MatrixRow[];
  cards: RouteCard[];
  precis: RunDocument | null;
  unresolvedQueue: RunDocument | null;
  synthesis: RunDocument | null;
  projections: ProjectionModel[];
  packetDocument: RunDocument | null;
  claimDocument: RunDocument | null;
  dispositionDocument: RunDocument | null;
  mergeDocument: RunDocument | null;
  evidenceDocument: RunDocument | null;
  boundaryDocument: RunDocument | null;
  tagDocument: RunDocument | null;
  referentDocument: RunDocument | null;
  matrixDocument: RunDocument | null;
}

export function walkFiles(root: string): string[] {
  const files: string[] = [];
  function visit(directory: string): void {
    for (const name of readdirSync(directory).sort()) {
      const path = join(directory, name);
      const stat = lstatSync(path);
      if (stat.isSymbolicLink()) continue;
      if (stat.isDirectory()) visit(path);
      else if (stat.isFile()) files.push(path);
    }
  }
  if (existsSync(root)) visit(root);
  return files;
}

function isCoreRunArtifact(runDir: string, path: string): boolean {
  const [topLevel] = relative(runDir, path).split(sep);
  return topLevel !== 'control';
}

function readDocument(runDir: string, relativePath: string): RunDocument | null {
  const path = join(runDir, relativePath);
  if (!existsSync(path) || !lstatSync(path).isFile()) return null;
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

function rowObjects<K extends string>(
  table: MarkdownTable | null | undefined,
  keys: readonly K[],
): RunRow<Record<K, string>>[] {
  if (!table) return [];
  return table.rows.map((row) => {
    const values = {} as Record<K, string>;
    keys.forEach((key, index) => { values[key] = row.cells[index] ?? ''; });
    return { ...row, values };
  });
}

function parseManifest(document: RunDocument | null): RunManifest | null {
  if (!document) return null;
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

function parseCorpus(document: RunDocument | null): CorpusModel {
  if (!document) return { document: null, sources: [] };
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

function parsePackets(document: RunDocument | null): PacketRow[] {
  if (!document) return [];
  const table = findTable(document.tables, [
    'packet id', 'source id', 'locator', 'span hash', 'quote', 'criterion', 'status',
  ]) || findTableByFirstHeader(document.tables, 'packet id');
  return rowObjects(table, [
    'packetId', 'sourceId', 'locator', 'spanHash', 'quote', 'criterion', 'status',
  ]);
}

function parseClaims(document: RunDocument | null): ClaimRow[] {
  if (!document) return [];
  const table = findTable(document.tables, [
    'claim id', 'normalized claim', 'packets', 'sources', 'claim type',
    'disposition', 'rationale', 'judged by', 'verified', 'status',
  ]) || findTableByFirstHeader(document.tables, 'claim id');
  return rowObjects(table, [
    'claimId', 'normalizedClaim', 'packets', 'sources', 'claimType',
    'disposition', 'rationale', 'judgedBy', 'verified', 'status',
  ]);
}

function parseDispositionRows(document: RunDocument | null): DispositionRow[] {
  if (!document) return [];
  return rowObjects(
    findTable(document.tables, ['disposition', 'count', 'claim ids'])
      || findTableByFirstHeader(document.tables, 'disposition'),
    ['disposition', 'count', 'claimIds'],
  );
}

function parseMerges(document: RunDocument | null): MergeRow[] {
  if (!document) return [];
  return rowObjects(
    findTable(document.tables, [
      'canonical', 'absorbs', 'basis', 'provenance retained', 'corroboration', 'status',
    ]) || findTableByFirstHeader(document.tables, 'canonical'),
    ['canonical', 'absorbs', 'basis', 'provenanceRetained', 'corroboration', 'status'],
  );
}

function parseEvidence(document: RunDocument | null): EvidenceModel {
  if (!document) return { edges: [], markers: [], accounting: new Map() };
  const edges = rowObjects(
    findTable(document.tables, [
      'claim id', 'source id', 'role', 'verification', 'removal effect', 'note', 'status',
    ]),
    ['claimId', 'sourceId', 'role', 'verification', 'removalEffect', 'note', 'status'],
  );
  const markers = rowObjects(
    findTable(document.tables, [
      'claim id', 'inference basis (claim/packet ids)', 'uncertainty note',
    ]),
    ['claimId', 'basisIds', 'uncertainty'],
  );
  const accounting = new Map<string, number>();
  for (const line of document.lines) {
    const match = line.match(/^\s*-\s*([^:]+):\s*(\d+)\s*$/);
    if (match) accounting.set(match[1].trim().toLowerCase(), Number(match[2]));
  }
  return { edges, markers, accounting };
}

function parseBoundaries(document: RunDocument | null): BoundaryRow[] {
  if (!document) return [];
  return rowObjects(
    findTableByFirstHeader(document.tables, 'boundary id'),
    ['boundaryId', 'type', 'statement', 'governs', 'basis', 'status'],
  );
}

function parseTags(document: RunDocument | null): TagRow[] {
  if (!document) return [];
  return rowObjects(
    findTable(document.tables, ['tag', 'member ids (PKT/CC)', 'structural basis (one phrase)'])
      || findTableByFirstHeader(document.tables, 'tag'),
    ['tag', 'memberIds', 'basis'],
  );
}

function parseReferents(document: RunDocument | null): ReferentRow[] {
  if (!document) return [];
  return rowObjects(
    findTableByFirstHeader(document.tables, 'ref id'),
    ['refId', 'need', 'depends', 'status', 'suppliedBy', 'intake', 'date', 'taintNote'],
  );
}

function parseMatrix(document: RunDocument | null): MatrixRow[] {
  if (!document) return [];
  const rows: MatrixRow[] = [];
  for (const table of document.tables) {
    if (!['stm id', 'case id'].includes(table.normalizedHeader[0])) continue;
    rows.push(...rowObjects(table, [
      'stmId', 'pressure', 'sourceRefs', 'claimIds', 'risk', 'handling', 'resolvedAt',
    ]));
  }
  return rows;
}

function parseCards(runDir: string): RouteCard[] {
  const directory = join(runDir, 'clusters', 'route-cards');
  if (!existsSync(directory)) return [];
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

function parseProjections(runDir: string): ProjectionModel[] {
  const directory = join(runDir, 'projections');
  if (!existsSync(directory)) return [];
  const byType = new Map<string, ProjectionModelBuilder>();
  const ensure = (type: string): ProjectionModelBuilder => {
    const existing = byType.get(type);
    if (existing) return existing;
    const projection: ProjectionModelBuilder = { type };
    byType.set(type, projection);
    return projection;
  };

  for (const path of walkFiles(directory)) {
    const relativePath = relative(runDir, path);
    const name = basename(path);
    let match = name.match(/^commission-(.+)\.md$/);
    if (match) {
      const document = readDocument(runDir, relativePath)!;
      ensure(match[1]).commission = {
        ...document,
        fieldTable: parseFieldTable(document.tables),
      };
      continue;
    }
    match = name.match(/^(.+)-selection\.md$/);
    if (match) {
      const document = readDocument(runDir, relativePath)!;
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
      const document = readDocument(runDir, relativePath)!;
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
    projection.projectionTracePath = (
      projection.commission?.fieldTable.fields.get('projection trace') || ''
    );
  }
  return [...byType.values()]
    .sort((a, b) => a.type.localeCompare(b.type)) as ProjectionModel[];
}

export function loadRun(runDir: string): RunModel {
  const documents = new Map<string, RunDocument | null>();
  const get = (path: string): RunDocument | null => {
    if (!documents.has(path)) documents.set(path, readDocument(runDir, path));
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
    if (file.relativePath.endsWith('.md')) get(file.relativePath);
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
