import { existsSync, readFileSync } from 'node:fs';
import { basename, join } from 'node:path';
import {
  activeClaims,
  fieldValue,
  location,
  makeIndexes,
  normalizeSha256,
  pathIsWithin,
  parseTimestamp,
  compareTimestamp,
  resolveRenderedPath,
  sha256,
} from './check-helpers.ts';
import {
  envelopeSection,
  findTableByFirstHeader,
  idsIn,
  normalizeHeader,
  parseBulletFields,
  parseFieldTable,
  parseTables,
  renderedParagraphs,
  tableCells,
  isSeparatorRow,
} from './markdown.ts';
import type {
  FieldTable,
  MarkdownDocument,
} from './markdown.ts';
import type { ResultCollector } from './results.ts';
import type {
  ClaimRow,
  EvidenceEdgeRow,
  EvidenceMarkerRow,
  ProjectionModel,
  ProjectionSelectionRow,
  RouteCard,
  RunFile,
  RunModel,
} from './run-model.ts';

interface ProjectionContract {
  sections: string[];
  fields: string[];
}

interface EvidenceState {
  active: Map<string, ClaimRow>;
  activeEdges: EvidenceEdgeRow[];
  edgesByClaim: Map<string, EvidenceEdgeRow[]>;
  markers: Map<string, EvidenceMarkerRow>;
  targetClaims: ClaimRow[];
  qualifying: Set<string>;
  broad: Set<string>;
  marked: Set<string>;
  neither: Set<string>;
}

interface CardData {
  card: RouteCard;
  posture: string;
  history: string;
  packets: string[];
  sources: string[];
  claims: string[];
  tags: string[];
  refs: string[];
  deps: string[];
  impact: string;
}

type CardMap = Map<string, CardData>;
type CardReferentMap = Map<string, Set<string>>;

interface RoutingState {
  cards: CardMap;
  refs: ReturnType<typeof makeIndexes>['REF'];
  cardRefs: CardReferentMap;
  coneRefs: (id: string, visiting?: Set<string>) => Set<string>;
  coneCards: (id: string, visiting?: Set<string>) => Set<string>;
}

type ProjectionFieldDocument = Pick<MarkdownDocument, 'text'> & {
  fieldTable?: FieldTable;
};

const ROLES: readonly string[] = [
  'load-bearing',
  'corroborative',
  'contradictory',
  'contextual',
  'decorative',
  'unresolved-source',
];
const VERIFICATION: readonly string[] = ['verified-primary', 'verified-secondary', 'unverifiable'];
const REMOVAL_EFFECTS: readonly string[] = [
  'downgrades-to-unresolved',
  'confidence-decreases',
  'survives-independent-support',
  'must-be-excluded',
];
const POSTURES: readonly string[] = [
  'adversarial-weighted',
  'convergent-weighted',
  'hybrid',
  'unrouted-pending-external-referent',
];
const VECTOR_SIGNALS: readonly string[] = [
  'contradiction density',
  'reference density',
  'invariant-bearing strength',
  'implementation-constraint density',
  'open-question density',
  'external-referent need',
  'doctrine-spine strength',
];
const REF_STATUSES: readonly string[] = ['unresolved', 'supplied', 'declined'];
const TRACE_KINDS: readonly string[] = ['load-bearing', 'boundary', 'open-item', 'gap', 'scaffolding'];
const TYPE_CONTRACTS: ReadonlyMap<string, ProjectionContract> = new Map([
  ['product-doctrine', {
    sections: Array.from({ length: 8 }, (_, index) => String(index + 1)),
    fields: [
      'taint',
      'projection id',
      'projection type',
      'projection trace',
      'source run',
      'intended consumer',
      'commission',
      'source precis',
      'projection status',
    ],
  }],
  ['prd', {
    sections: Array.from({ length: 13 }, (_, index) => String(index + 1)),
    fields: [
      'taint',
      'projection id',
      'projection type',
      'projection trace',
      'source run',
      'intended consumer',
      'commission',
      'source precis',
      'domain assumption',
      'prd scope',
      'projection status',
    ],
  }],
]);

function evidenceState(model: RunModel): EvidenceState {
  const active = new Map<string, ClaimRow>(
    activeClaims(model).map((claim) => [claim.values.claimId, claim]),
  );
  const activeEdges = model.evidence.edges.filter((edge) => edge.values.status === 'active');
  const edgesByClaim = new Map<string, EvidenceEdgeRow[]>();
  for (const edge of activeEdges) {
    if (!edgesByClaim.has(edge.values.claimId)) edgesByClaim.set(edge.values.claimId, []);
    edgesByClaim.get(edge.values.claimId)!.push(edge);
  }
  const markers = new Map<string, EvidenceMarkerRow>(
    model.evidence.markers.map((row) => [row.values.claimId, row]),
  );
  const targetClaims = [...active.values()].filter((claim) => (
    claim.values.disposition === 'carried' || claim.values.disposition === 'merged'
  ));
  const qualifying = new Set<string>();
  const broad = new Set<string>();
  for (const claim of targetClaims) {
    const edges = edgesByClaim.get(claim.values.claimId) || [];
    if (edges.some((edge) => ['load-bearing', 'corroborative'].includes(edge.values.role))) {
      qualifying.add(claim.values.claimId);
    }
    if (edges.some((edge) => ['load-bearing', 'corroborative', 'decorative', 'contextual'].includes(edge.values.role))) {
      broad.add(claim.values.claimId);
    }
  }
  const marked = new Set(targetClaims
    .map((claim) => claim.values.claimId)
    .filter((id) => markers.has(id)));
  const neither = new Set(targetClaims
    .map((claim) => claim.values.claimId)
    .filter((id) => !qualifying.has(id) && !marked.has(id)));
  return {
    active,
    activeEdges,
    edgesByClaim,
    markers,
    targetClaims,
    qualifying,
    broad,
    marked,
    neither,
  };
}

function accountingValue(model: RunModel, prefix: string): number | null {
  for (const [key, value] of model.evidence.accounting.entries()) {
    if (key.startsWith(prefix)) return value;
  }
  return null;
}

function runK3Checks(results: ResultCollector, model: RunModel): void {
  results.run('K3.1', 'edge shape', (fail) => {
    const indexes = makeIndexes(model);
    const table = model.evidenceDocument
      ? model.evidenceDocument.tables.find((candidate) => candidate.normalizedHeader.includes('role'))
      : null;
    if (!table) {
      fail('evidence-roles.md has no claim-source edge table');
      return 'edge rows have exact shape and vocabularies';
    }
    if (table.header.length !== 7) fail(`edge header has ${table.header.length} columns, expected 7`);
    for (const edge of model.evidence.edges) {
      if (edge.cells.length !== 7) {
        fail(`edge row has ${edge.cells.length} columns at ${location(edge)}`);
        continue;
      }
      if (!ROLES.includes(edge.values.role)) {
        fail(`row ${edge.line} role "${edge.values.role}" not in vocabulary`);
      }
      if (!VERIFICATION.includes(edge.values.verification)) {
        fail(`row ${edge.line} verification "${edge.values.verification}" not in vocabulary`);
      }
      if (
        edge.values.status !== 'active'
        && !/^superseded-by:(?:CC|SRC)-\d+$/.test(edge.values.status)
        && !/^retracted:.+/.test(edge.values.status)
      ) {
        fail(`row ${edge.line} status "${edge.values.status || '(blank)'}" is invalid`);
      }
      const superseded = edge.values.status.match(/^superseded-by:((?:CC|SRC)-\d+)$/);
      if (superseded) {
        const family: 'CC' | 'SRC' = superseded[1].startsWith('CC-') ? 'CC' : 'SRC';
        const target = indexes[family].get(superseded[1]);
        const targetIsActive = (
          family === 'SRC'
          || indexes.CC.get(superseded[1])?.values.status === 'active'
        );
        if (!target || !targetIsActive) {
          fail(`row ${edge.line} supersession target ${superseded[1]} is not an active definition`);
        }
      }
    }
    return 'edge rows have exactly 7 columns and closed vocabulary values';
  });

  results.run('K3.2', 'edge resolution', (fail) => {
    const indexes = makeIndexes(model);
    const active = new Set<string>(activeClaims(model).map((claim) => claim.values.claimId));
    for (const edge of model.evidence.edges) {
      if (!active.has(edge.values.claimId)) {
        fail(`${edge.values.claimId || '(blank claim)'} is not an active inventory claim at ${location(edge)}`);
      }
      if (!indexes.SRC.has(edge.values.sourceId)) {
        fail(`${edge.values.sourceId || '(blank source)'} does not resolve at ${location(edge)}`);
      }
    }
    return 'every edge resolves to an active claim and corpus source';
  });

  results.run('K3.3', 'removal effect presence', (fail) => {
    for (const edge of model.evidence.edges.filter((row) => row.values.status === 'active')) {
      const effect = edge.values.removalEffect;
      if (edge.values.role === 'load-bearing') {
        if (!REMOVAL_EFFECTS.includes(effect)) {
          fail(`${edge.values.claimId}/${edge.values.sourceId} load-bearing effect "${effect || '(blank)'}" is invalid`);
        }
      } else if (effect) {
        fail(`${edge.values.claimId}/${edge.values.sourceId} has removal_effect but role is ${edge.values.role}`);
      }
    }
    return 'removal effects are present exactly on load-bearing edges';
  });

  results.run('K3.4', 'coverage', (fail) => {
    const state = evidenceState(model);
    const declared = {
      target: accountingValue(model, 'carried+merged claims'),
      support: accountingValue(model, 'with ≥1 load-bearing or corroborative edge')
        ?? accountingValue(model, 'with >=1 load-bearing or corroborative edge'),
      inference: accountingValue(model, 'explicitly marked synthesis/inference'),
      neither: accountingValue(model, 'neither'),
    };
    const actual = {
      target: state.targetClaims.length,
      support: state.qualifying.size,
      inference: state.marked.size,
      neither: state.neither.size,
    };
    for (const key of Object.keys(actual) as Array<keyof typeof actual>) {
      if (declared[key] === null) fail(`coverage accounting is missing "${key}"`);
      else if (declared[key] !== actual[key]) {
        fail(`coverage accounting ${key} declares ${declared[key]}, recomputed ${actual[key]}`);
      }
    }
    if (actual.neither !== 0) {
      fail(`NEITHER is ${actual.neither}: ${[...state.neither].join(', ')}`);
    }
    return 'carried/merged support and inference coverage recomputes with NEITHER=0';
  });

  results.run('K3.5', 'decorative counted', (fail) => {
    const state = evidenceState(model);
    const declared = accountingValue(model, 'with ≥1 load-bearing or corroborative edge')
      ?? accountingValue(model, 'with >=1 load-bearing or corroborative edge');
    if (
      declared !== null
      && declared !== state.qualifying.size
      && declared === state.broad.size
      && state.broad.size > state.qualifying.size
    ) {
      const decorativeOnly = [...state.broad].filter((id) => !state.qualifying.has(id));
      fail(`support count balances only by counting decorative/contextual edges for ${decorativeOnly.join(', ')}`);
    }
    return 'decorative and contextual edges do not contribute to support coverage';
  });

  results.run('K3.6', 'unverifiable support', (fail) => {
    const state = evidenceState(model);
    for (const claim of state.targetClaims.filter((row) => row.values.disposition === 'carried')) {
      const id = claim.values.claimId;
      const edges = state.edgesByClaim.get(id) || [];
      if (
        edges.length > 0
        && edges.every((edge) => ['unresolved-source', 'decorative', 'contextual'].includes(edge.values.role))
        && !state.markers.has(id)
      ) {
        fail(`${id} is carried on unresolved-source/decorative/contextual support only`);
      }
    }
    return 'no carried claim is confirmed solely by unresolved or non-supporting edges';
  });

  results.run('K3.7', 'contradiction preservation', (fail) => {
    const state = evidenceState(model);
    for (const merge of model.merges.filter((row) => row.values.status === 'active')) {
      const canonicalEdges = state.edgesByClaim.get(merge.values.canonical) || [];
      for (const absorbed of idsIn(merge.values.absorbs, 'CC')) {
        const contradictory = (state.edgesByClaim.get(absorbed) || [])
          .filter((edge) => edge.values.role === 'contradictory');
        for (const edge of contradictory) {
          if (!canonicalEdges.some((candidate) => (
            candidate.values.sourceId === edge.values.sourceId
            && candidate.values.role === 'contradictory'
          ))) {
            fail(`${merge.values.canonical} drops contradictory ${edge.values.sourceId} edge from ${absorbed}`);
          }
        }
      }
    }
    return 'canonical merged claims preserve every absorbed contradictory edge';
  });

  results.run('K3.8', 'inference markers resolve', (fail) => {
    const indexes = makeIndexes(model);
    const active = new Map<string, ClaimRow>(
      activeClaims(model).map((claim) => [claim.values.claimId, claim]),
    );
    for (const marker of model.evidence.markers) {
      const claim = active.get(marker.values.claimId);
      if (!claim || !['carried', 'merged'].includes(claim.values.disposition)) {
        fail(`${marker.values.claimId || '(blank claim)'} marker does not target active carried/merged claim`);
      }
      const structured = idsIn(marker.values.basisIds);
      const wrongFamily = structured.filter((id) => !/^(?:CC|PKT)-/.test(id));
      if (wrongFamily.length > 0) {
        fail(`${marker.values.claimId} marker basis uses invalid family: ${wrongFamily.join(', ')}`);
      }
      const basis = structured.filter((id) => /^(?:CC|PKT)-/.test(id));
      if (basis.length === 0) fail(`${marker.values.claimId} marker has no CC/PKT basis`);
      for (const id of basis) {
        const family = id.startsWith('CC-') ? 'CC' : 'PKT';
        if (!indexes[family].has(id)) fail(`${marker.values.claimId} marker basis ${id} does not resolve`);
      }
      if (!marker.values.uncertainty.trim()) {
        fail(`${marker.values.claimId} marker uncertainty is empty`);
      }
    }
    return 'all inference markers target active claims with resolving bases and uncertainty';
  });
}

function cardData(model: RunModel): CardMap {
  const byId = new Map<string, CardData>();
  for (const card of model.cards) {
    byId.set(card.id, {
      card,
      posture: fieldValue(card, 'Routing posture'),
      history: fieldValue(card, 'Posture history'),
      packets: idsIn(fieldValue(card, 'Packet/source IDs'), 'PKT'),
      sources: idsIn(fieldValue(card, 'Packet/source IDs'), 'SRC'),
      claims: idsIn(fieldValue(card, 'Candidate claim IDs'), 'CC'),
      tags: idsIn(fieldValue(card, 'Structural pre-cluster tags used'), 'PC'),
      refs: idsIn(fieldValue(card, 'Unresolved external referents'), 'REF'),
      deps: idsIn(fieldValue(card, 'Depends on'), 'RC'),
      impact: fieldValue(card, 'Blocks/finalization impact'),
    });
  }
  return byId;
}

function cardReferentIds(model: RunModel, cards: CardMap): CardReferentMap {
  const byCard = new Map<string, Set<string>>();
  for (const [id, data] of cards) {
    byCard.set(id, new Set<string>(data.refs));
  }
  for (const referent of model.referents) {
    const refId = referent.values.refId;
    for (const cardId of idsIn(referent.values.depends, 'RC')) {
      if (byCard.has(cardId)) byCard.get(cardId)!.add(refId);
    }
    const claimIds = new Set<string>(idsIn(referent.values.depends, 'CC'));
    if (claimIds.size > 0) {
      for (const [cardId, data] of cards) {
        if (data.claims.some((id) => claimIds.has(id))) byCard.get(cardId)!.add(refId);
      }
    }
  }
  return byCard;
}

function runK4Checks(results: ResultCollector, model: RunModel): void {
  const cards = cardData(model);
  const cardRefs = cardReferentIds(model, cards);
  results.run('K4.1', 'card shape', (fail) => {
    const expectedFields = [
      'routing posture',
      'posture history',
      'structural pre-cluster tags used',
      'packet/source ids',
      'candidate claim ids',
      'key dispositions',
      'unresolved external referents',
      'depends on',
      'blocks/finalization impact',
    ];
    for (const card of model.cards) {
      if (card.filenameId !== card.id) {
        fail(`${card.relativePath} filename id ${card.filenameId} differs from heading id ${card.id || '(missing)'}`);
      }
      if (!card.fieldTable.table) {
        fail(`${card.relativePath} has no field/value table`);
      } else {
        const fieldNames = card.fieldTable.table.rows.map((row) => normalizeHeader(row.cells[0]));
        for (const field of expectedFields) {
          if (!fieldNames.includes(field)) fail(`${card.id} is missing field "${field}"`);
        }
        if (fieldNames.length !== expectedFields.length) {
          fail(`${card.id} has ${fieldNames.length} card fields, expected exactly 9`);
        }
      }
      const posture = fieldValue(card, 'Routing posture');
      if (!POSTURES.includes(posture)) fail(`${card.id} posture "${posture || '(blank)'}" is invalid`);

      const vector = new Map<string, string>();
      for (const row of card.vectorRows) {
        const signal = normalizeHeader(row.values.signal);
        if (vector.has(signal)) fail(`${card.id} repeats shape signal "${signal}"`);
        vector.set(signal, row.values.value);
      }
      for (const signal of VECTOR_SIGNALS) {
        const value = vector.get(signal);
        if (value === undefined) fail(`${card.id} is missing shape signal "${signal}"`);
        else if (!['low', 'med', 'high'].includes(value)) {
          fail(`${card.id} shape signal "${signal}" has invalid value "${value}"`);
        }
      }
      if (vector.size !== VECTOR_SIGNALS.length) {
        fail(`${card.id} has ${vector.size} shape signals, expected exactly 7`);
      }
    }
    return 'every route card has matching IDs, 9 fields, and a 7-signal vector';
  });

  results.run('K4.2', 'smallest invariant', (fail) => {
    const indexes = makeIndexes(model);
    for (const data of cards.values()) {
      if (data.packets.length === 0) fail(`${data.card.id} lists no packet ids`);
      for (const family of ['PKT', 'SRC', 'CC', 'PC', 'RC', 'REF'] as const) {
        for (const id of idsIn(data.card.text, family)) {
          if (!indexes[family].has(id)) fail(`${data.card.id} cites missing ${id}`);
        }
      }
    }
    for (const referent of model.referents) {
      for (const family of ['RC', 'CC'] as const) {
        for (const id of idsIn(referent.values.depends, family)) {
          if (!indexes[family].has(id)) {
            fail(`${referent.values.refId || 'referent row'} depends on missing ${id}`);
          }
        }
      }
    }
    return 'every card lists a packet and every card ID resolves';
  });

  results.run('K4.3', 'pending posture => REF', (fail) => {
    const refs = makeIndexes(model).REF;
    for (const referent of model.referents) {
      if (!REF_STATUSES.includes(referent.values.status)) {
        fail(`${referent.values.refId || 'referent row'} status "${referent.values.status || '(blank)'}" is invalid`);
      }
    }
    for (const data of cards.values()) {
      const relatedRefs = [...(cardRefs.get(data.card.id) || [])];
      if (data.posture === 'unrouted-pending-external-referent') {
        if (relatedRefs.length === 0) fail(`${data.card.id} pending posture lists no REF`);
        for (const id of relatedRefs) {
          const ref = refs.get(id);
          if (ref && ref.values.status !== 'unresolved') {
            fail(`${data.card.id} remains pending although ${id} is ${ref.values.status}`);
          }
        }
      }
      for (const id of relatedRefs) {
        const ref = refs.get(id);
        if (!ref) continue;
        if (ref.values.status === 'unresolved' && data.posture !== 'unrouted-pending-external-referent') {
          fail(`${data.card.id} cites unresolved ${id} but posture is ${data.posture}`);
        }
        if (['supplied', 'declined'].includes(ref.values.status)) {
          const occurrences: string[] = [];
          const pattern = new RegExp(`\\b(${POSTURES.join('|')})\\b`, 'g');
          for (const match of data.history.matchAll(pattern)) occurrences.push(match[1]);
          const pendingIndex = occurrences.lastIndexOf('unrouted-pending-external-referent');
          const currentIndex = occurrences.lastIndexOf(data.posture);
          if (
            pendingIndex === -1
            || data.posture === 'unrouted-pending-external-referent'
            || currentIndex <= pendingIndex
          ) {
            fail(`${data.card.id} has resolved ${id} without a later re-route history entry`);
          }
        }
      }
    }
    return 'pending and resolved referents agree with card posture histories';
  });

  results.run('K4.4', 'tags are tags', (fail) => {
    const table = model.tagDocument
      ? findTableByFirstHeader(model.tagDocument.tables, 'tag')
      : null;
    if (!table) fail('pre-cluster-tags.md has no tag table');
    else {
      if (table.header.length !== 3) fail(`tag header has ${table.header.length} columns, expected 3`);
      for (const row of table.rows) {
        if (row.cells.length !== 3) fail(`tag row has ${row.cells.length} columns at ${location(row)}`);
      }
    }
    for (const file of model.files) {
      if (
        file.relativePath.startsWith('clusters/')
        && /(?:^|\/)PC-\d+\.md$/.test(file.relativePath)
      ) {
        fail(`${file.relativePath} materializes a pre-cluster as a document`);
      }
    }
    return 'pre-clusters are exact 3-column tags and never documents';
  });

  results.run('K4.5', 'dependency sanity', (fail) => {
    const indexes = makeIndexes(model);
    const edges: Array<{ from: string; to: string; mutual: boolean }> = [];
    for (const data of cards.values()) {
      const field = fieldValue(data.card, 'Depends on');
      for (const dependency of data.deps) {
        if (!indexes.RC.has(dependency)) fail(`${data.card.id} depends on missing ${dependency}`);
        const escaped = dependency.replace('-', '\\-');
        const mutual = new RegExp(`${escaped}[^;,|]*\\bmutual\\b`, 'i').test(field);
        edges.push({ from: data.card.id, to: dependency, mutual });
      }
    }
    const graph = new Map<string, string[]>();
    for (const id of cards.keys()) graph.set(id, []);
    for (const edge of edges) {
      if (graph.has(edge.from)) graph.get(edge.from)!.push(edge.to);
    }
    const reachable = (
      start: string,
      target: string,
      seen: Set<string> = new Set<string>(),
    ): boolean => {
      if (start === target) return true;
      if (seen.has(start)) return false;
      seen.add(start);
      return (graph.get(start) || []).some((next) => reachable(next, target, seen));
    };
    for (const edge of edges) {
      if (reachable(edge.to, edge.from) && !edge.mutual) {
        fail(`cycle edge ${edge.from} -> ${edge.to} lacks literal mutual annotation`);
      }
    }
    return 'dependencies resolve and every cyclic edge is explicitly mutual';
  });

  results.run('K4.6', 'posture history', (fail) => {
    for (const data of cards.values()) {
      const occurrences: string[] = [];
      const pattern = new RegExp(`\\b(${POSTURES.join('|')})\\b`, 'g');
      for (const match of data.history.matchAll(pattern)) occurrences.push(match[1]);
      if (occurrences.length === 0) fail(`${data.card.id} has no posture-history entry`);
      else if (occurrences[occurrences.length - 1] !== data.posture) {
        fail(`${data.card.id} last history posture ${occurrences.at(-1)} differs from ${data.posture}`);
      }
    }
    return 'every card has history ending at its current posture';
  });
}

function routingState(model: RunModel): RoutingState {
  const cards = cardData(model);
  const refs = makeIndexes(model).REF;
  const cardRefs = cardReferentIds(model, cards);
  const ownUnresolved = new Map<string, Set<string>>();
  for (const [id, data] of cards.entries()) {
    ownUnresolved.set(
      id,
      new Set<string>([...(cardRefs.get(id) || [])]
        .filter((refId) => refs.get(refId)?.values.status === 'unresolved')),
    );
  }
  const memo = new Map<string, Set<string>>();
  const cardMemo = new Map<string, Set<string>>();
  const coneRefs = (
    id: string,
    visiting: Set<string> = new Set<string>(),
  ): Set<string> => {
    if (memo.has(id)) return new Set<string>(memo.get(id));
    if (visiting.has(id)) return new Set<string>(ownUnresolved.get(id) || []);
    visiting.add(id);
    const result = new Set<string>(ownUnresolved.get(id) || []);
    for (const dependency of cards.get(id)?.deps || []) {
      for (const ref of coneRefs(dependency, visiting)) result.add(ref);
    }
    visiting.delete(id);
    memo.set(id, result);
    return new Set<string>(result);
  };
  const coneCards = (
    id: string,
    visiting: Set<string> = new Set<string>(),
  ): Set<string> => {
    if (cardMemo.has(id)) return new Set<string>(cardMemo.get(id));
    if (visiting.has(id)) return new Set<string>([id]);
    visiting.add(id);
    const result = new Set<string>([id]);
    for (const dependency of cards.get(id)?.deps || []) {
      for (const cardId of coneCards(dependency, visiting)) result.add(cardId);
    }
    visiting.delete(id);
    cardMemo.set(id, result);
    return new Set<string>(result);
  };
  for (const id of cards.keys()) coneRefs(id);
  for (const id of cards.keys()) coneCards(id);
  return {
    cards,
    refs,
    cardRefs,
    coneRefs,
    coneCards,
  };
}

function artifactCone(file: RunFile, routing: RoutingState): Set<string> {
  const seeds = new Set<string>(idsIn(file.text, 'RC'));
  const claimIds = new Set<string>(idsIn(file.text, 'CC'));
  const packetIds = new Set<string>(idsIn(file.text, 'PKT'));
  for (const [id, data] of routing.cards.entries()) {
    if (
      data.claims.some((claim) => claimIds.has(claim))
      || data.packets.some((packet) => packetIds.has(packet))
    ) seeds.add(id);
  }
  const all = new Set<string>();
  const visit = (id: string): void => {
    if (all.has(id)) return;
    all.add(id);
    for (const dependency of routing.cards.get(id)?.deps || []) visit(dependency);
  };
  for (const id of seeds) visit(id);
  return all;
}

function runK5Checks(results: ResultCollector, model: RunModel): void {
  const routing = routingState(model);
  results.run('K5.1', 'taint declaration', (fail) => {
    for (const [id, data] of routing.cards.entries()) {
      if (routing.coneRefs(id).size > 0 && !data.impact.trim()) {
        fail(`${id} is tainted but Blocks/finalization impact is empty`);
      }
    }
    for (const referent of model.referents) {
      if (referent.values.status === 'unresolved' && !referent.values.taintNote.trim()) {
        fail(`${referent.values.refId} is unresolved but taint note is empty`);
      }
    }
    return 'every tainted card and unresolved referent declares its impact';
  });

  results.run('K5.2', 'gate', (fail) => {
    const surfaces = model.files.filter((file) => (
      file.relativePath === 'precis.md'
      || file.relativePath.startsWith('synthesis/')
      || file.relativePath.startsWith('projections/')
      || file.relativePath.startsWith('clusters/route-cards/')
    ));
    for (const file of surfaces) {
      if (!/externally complete/i.test(file.text)) continue;
      const cone = artifactCone(file, routing);
      const tainted = [...cone].some((id) => routing.coneRefs(id).size > 0);
      if (tainted && !/external-referent unresolved/i.test(file.text)) {
        fail(`${file.relativePath} claims externally complete over a tainted provenance cone`);
      }
    }
    return 'no finalization surface claims external completeness without its taint marker';
  });

  results.run('K5.3', 'Precis taint honesty', (fail) => {
    if (!model.precis) return 'precis.md not present; taint rendering not yet applicable';
    const active = new Map<string, ClaimRow>(
      activeClaims(model).map((claim) => [claim.values.claimId, claim]),
    );
    const relevantRefs = new Set<string>();
    const declined = new Set<string>();
    for (const [id, data] of routing.cards.entries()) {
      const loadBearing = data.claims.some((claimId) => {
        const claim = active.get(claimId);
        return claim && ['carried', 'merged'].includes(claim.values.disposition);
      });
      if (!loadBearing) continue;
      for (const cardId of routing.coneCards(id)) {
        for (const ref of routing.cardRefs.get(cardId) || []) {
          const status = routing.refs.get(ref)?.values.status;
          if (status === 'unresolved') relevantRefs.add(ref);
          if (status === 'declined') declined.add(ref);
        }
      }
    }
    const section = envelopeSection(model.precis.text, 17);
    if (relevantRefs.size > 0 && !/external-referent unresolved/i.test(section)) {
      fail('precis.md §17 lacks the external-referent unresolved marker');
    }
    for (const ref of [...relevantRefs, ...declined]) {
      if (!new RegExp(`\\b${ref}\\b`).test(section)) fail(`precis.md §17 does not name ${ref}`);
    }
    return 'Précis §17 names every load-bearing taint and declined referent';
  });

  results.run('K5.4', 'resolution hygiene', (fail) => {
    const sources = makeIndexes(model).SRC;
    for (const referent of model.referents) {
      if (referent.values.status !== 'supplied') continue;
      if (!referent.values.suppliedBy.trim()) {
        fail(`${referent.values.refId} supplied_by is empty`);
      }
      const sourceBacked = idsIn(referent.values.intake, 'SRC').some((id) => {
        const source = sources.get(id);
        return source && ['external-research-intake', 'authority-statement'].includes(source.values.kind);
      });
      const intake = referent.values.intake.replace(/`/g, '').trim();
      const signoffBacked = Boolean(intake && model.manifest?.signoffs.some((row) => {
        const positive = /^(?:approved|accepted|fixture-simulated)(?:\b|:)/i
          .test(row.values.decision.trim());
        const cited = (
          (row.values.gate.trim() && intake.includes(row.values.gate.trim()))
          || (row.values.reference.trim() && intake.includes(row.values.reference.trim()))
        );
        return (
          positive
          && cited
          && row.values.by.trim()
          && row.values.by.trim() === referent.values.suppliedBy.trim()
        );
      }));
      if (!sourceBacked && !signoffBacked) {
        fail(`${referent.values.refId} supplied without an intake source or manifest sign-off`);
      }
    }
    return 'every supplied referent names a supplier and authorized intake/sign-off';
  });
}

function projectionFields(
  document: ProjectionFieldDocument | null | undefined,
): Map<string, string> {
  if (!document) return new Map<string, string>();
  return document.fieldTable?.fields || parseBulletFields(document.text).fields;
}

function acceptedTimestamp(model: RunModel): ReturnType<typeof parseTimestamp> {
  if (!model.manifest) return null;
  const rows = model.manifest.states.filter((row) => row.values.state === 'ACCEPTED');
  if (rows.length === 0) return null;
  return parseTimestamp(rows.at(-1)!.values.entered);
}

function traceDocumentPath(model: RunModel, projection: ProjectionModel): string | null {
  if (!projection.trace) return null;
  const bullets = projection.trace.bullets.fields;
  return resolveRenderedPath(model.runDir, bullets.get('renders') || '');
}

function runK6Checks(results: ResultCollector, model: RunModel): void {
  const routing = routingState(model);
  const active = new Map<string, ClaimRow>(
    activeClaims(model).map((claim) => [claim.values.claimId, claim]),
  );
  const activeBoundaries = new Map(
    model.boundaries
      .filter((boundary) => boundary.values.status === 'active')
      .map((boundary) => [boundary.values.boundaryId, boundary] as const),
  );
  const byType = model.projections;

  results.run('K6.1', 'commission', (fail) => {
    if (byType.length === 0) {
      fail('projection validation found no commissioned projection');
      return 'at least one complete projection is present';
    }
    if (!model.precis) {
      fail('projection validation requires precis.md');
      return 'projection commissions bind the accepted Précis hash';
    }
    const currentHash = sha256(Buffer.from(model.precis.text, 'utf8'));
    const accepted = acceptedTimestamp(model);
    const projectionIds = new Map<string, string>();
    for (const projection of byType) {
      if (!projection.commission) {
        fail(`${projection.type} has no commission file`);
        continue;
      }
      const fields = projectionFields(projection.commission);
      const projectionIdRows = projection.commission.fieldTable?.table?.rows
        .filter((row) => normalizeHeader(row.cells[0]) === 'projection id') || [];
      if (projectionIdRows.length !== 1) {
        fail(
          `${projection.type} commission has ${projectionIdRows.length} projection id rows, `
          + 'expected exactly one',
        );
      }
      for (const field of [
        'projection id',
        'commissioned by',
        'date',
        'projection type',
        'projection trace',
        'intended consumer',
        'type parameters',
        'precis hash at commissioning',
      ]) {
        if (!fields.get(field)?.trim()) {
          fail(`${projection.type} commission field "${field}" is empty or missing`);
        }
      }
      const projectionId = fields.get('projection id') || '';
      if (!/^PRJ-\d+$/.test(projectionId)) {
        fail(`${projection.type} commission projection id "${projectionId || '(blank)'}" is not PRJ-NNN`);
      } else if (projectionIds.has(projectionId)) {
        fail(
          `${projection.type} commission repeats ${projectionId} from `
          + `${projectionIds.get(projectionId)}`,
        );
      } else {
        projectionIds.set(projectionId, projection.type);
      }
      if (fields.get('projection type') !== projection.type) {
        fail(
          `${projection.type} commission declares projection type `
          + `"${fields.get('projection type') || '(blank)'}"`,
        );
      }
      const expectedTrace = projection.trace?.relativePath || '';
      if (fields.get('projection trace') !== expectedTrace) {
        fail(
          `${projection.type} commission projection trace `
          + `"${fields.get('projection trace') || '(blank)'}" does not match `
          + `${expectedTrace || '(missing trace)'}`,
        );
      }
      const traceProjectionId = projection.trace?.bullets.fields.get('projection id') || '';
      if (traceProjectionId !== projectionId) {
        fail(
          `${projection.type} trace projection id `
          + `"${traceProjectionId || '(blank)'}" does not match ${projectionId || '(blank commission id)'}`,
        );
      }
      const declaredHash = normalizeSha256(
        fields.get('precis hash at commissioning')
        || fields.get('precis hash')
        || '',
      );
      if (declaredHash !== currentHash) {
        fail(`${projection.type} commission Précis hash does not match precis.md now`);
      }
      if (model.manifest) {
        const date = parseTimestamp(fields.get('date') || '');
        if (!accepted) fail(`${projection.type} commission has no preceding ACCEPTED state`);
        else if (!date) fail(`${projection.type} commission date is invalid`);
        else if (compareTimestamp(accepted, date) > 0) {
          fail(`${projection.type} commission predates the ACCEPTED state`);
        }
      }
    }
    return 'every commission defines one projection ID and binds its trace and accepted Précis';
  });

  results.run('K6.2', 'selection coverage', (fail) => {
    const carried = [...active.values()].filter((claim) => (
      claim.values.disposition === 'carried' || claim.values.disposition === 'merged'
    ));
    for (const projection of byType) {
      if (!projection.selection) {
        fail(`${projection.type} has no selection ledger`);
        continue;
      }
      const rows = new Map<string, ProjectionSelectionRow>();
      for (const row of projection.selection.rows) {
        if (rows.has(row.values.claimId)) {
          fail(`${projection.type} selection repeats ${row.values.claimId}`);
        }
        rows.set(row.values.claimId, row);
        const claim = active.get(row.values.claimId);
        if (!claim) {
          fail(`${projection.type} selection ${row.values.claimId || '(blank)'} is not an active claim`);
        } else if (row.values.disposition !== claim.values.disposition) {
          fail(
            `${projection.type} ${row.values.claimId} declares disposition `
            + `${row.values.disposition || '(blank)'}, inventory is ${claim.values.disposition}`,
          );
        }
        if (!['used', 'not-used', 'surfaced-as-open'].includes(row.values.selection)) {
          fail(`${projection.type} ${row.values.claimId} selection "${row.values.selection}" is invalid`);
        }
        if (
          claim
          && ['carried', 'merged'].includes(claim.values.disposition)
          && !['used', 'not-used'].includes(row.values.selection)
        ) {
          fail(`${projection.type} carried/merged ${row.values.claimId} is ${row.values.selection}`);
        }
        if (
          claim
          && ['deferred', 'unresolved'].includes(claim.values.disposition)
          && row.values.selection !== 'surfaced-as-open'
        ) {
          fail(`${projection.type} open ${row.values.claimId} is ${row.values.selection}`);
        }
        if (
          claim
          && !['carried', 'merged', 'deferred', 'unresolved'].includes(claim.values.disposition)
          && row.values.selection === 'used'
        ) {
          fail(`${projection.type} uses ${row.values.claimId} with disposition ${claim.values.disposition}`);
        }
        if (
          row.values.selection === 'not-used'
          && !/^(?:out-of-projection-scope(?::.+)?|superseded-by:CC-\d+|deferred-to:.+)$/.test(row.values.reason)
        ) {
          fail(`${projection.type} ${row.values.claimId} has invalid not-used reason`);
        }
      }
      for (const claim of carried) {
        const row = rows.get(claim.values.claimId);
        if (!row) fail(`${projection.type} selection is missing ${claim.values.claimId}`);
        else if (!['used', 'not-used'].includes(row.values.selection)) {
          fail(`${projection.type} carried/merged ${claim.values.claimId} is ${row.values.selection}`);
        }
      }

      const used = new Set<string>(projection.selection.rows
        .filter((row) => row.values.selection === 'used')
        .map((row) => row.values.claimId));
      const touchedCards = [...routing.cards.values()]
        .filter((card) => card.claims.some((id) => used.has(id)));
      const openRequired = new Set<string>();
      for (const card of touchedCards) {
        for (const id of card.claims) {
          const claim = active.get(id);
          if (claim && ['deferred', 'unresolved'].includes(claim.values.disposition)) {
            openRequired.add(id);
          }
        }
      }
      for (const id of openRequired) {
        const row = rows.get(id);
        if (!row || row.values.selection !== 'surfaced-as-open') {
          fail(`${projection.type} touched-cluster open claim ${id} is not surfaced-as-open`);
        }
      }
    }
    return 'selection ledgers cover carried/merged and touched-cluster open claims';
  });

  results.run('K6.3', 'trace resolution', (fail) => {
    for (const projection of byType) {
      if (!projection.trace) {
        fail(`${projection.type} has no projection trace`);
        continue;
      }
      for (const row of projection.trace.rows) {
        if (!TRACE_KINDS.includes(row.values.kind)) {
          fail(`${projection.type} trace kind "${row.values.kind}" is invalid at ${location(row)}`);
          continue;
        }
        const backing = idsIn(row.values.backing, 'CC');
        const boundaryBacking = idsIn(row.values.backing, 'NB');
        const backingResidue = row.values.backing
          .replace(/\b(?:CC|NB)-\d+\b/g, '')
          .replace(/[,\s;]+/g, '');
        if (backingResidue) {
          fail(`${projection.type} ${row.values.kind} ${row.values.anchor} has invalid backing`);
        }
        if (row.values.kind === 'load-bearing') {
          if (boundaryBacking.length > 0) {
            fail(`${projection.type} load-bearing ${row.values.anchor} must not use boundary backing`);
          }
          for (const id of backing) {
            const claim = active.get(id);
            if (!claim || !['carried', 'merged'].includes(claim.values.disposition)) {
              fail(`${projection.type} load-bearing trace backs onto invalid ${id}`);
            }
          }
        } else if (row.values.kind === 'boundary') {
          if (backing.length > 0) {
            fail(`${projection.type} boundary ${row.values.anchor} must not use claim backing`);
          }
          if (boundaryBacking.length === 0) {
            fail(`${projection.type} boundary ${row.values.anchor} has no backing`);
          }
          for (const id of boundaryBacking) {
            if (!activeBoundaries.has(id)) {
              fail(`${projection.type} boundary trace backs onto invalid ${id}`);
            }
          }
        } else if (row.values.kind === 'open-item') {
          if (boundaryBacking.length > 0) {
            fail(`${projection.type} open-item ${row.values.anchor} must not use boundary backing`);
          }
          if (backing.length === 0) fail(`${projection.type} open-item ${row.values.anchor} has no backing`);
          for (const id of backing) {
            const claim = active.get(id);
            if (!claim || !['deferred', 'unresolved'].includes(claim.values.disposition)) {
              fail(`${projection.type} open-item backs onto invalid ${id}`);
            }
          }
        } else if (backing.length > 0 || boundaryBacking.length > 0) {
          fail(`${projection.type} ${row.values.kind} ${row.values.anchor} must have empty backing`);
        }
      }
    }
    return 'claim and negative-boundary backing resolve for every statement kind';
  });

  results.run('K6.4', 'trace coverage', (fail) => {
    for (const projection of byType) {
      if (!projection.trace) continue;
      const path = traceDocumentPath(model, projection);
      if (!path || !existsSync(path)) {
        fail(`${projection.type} trace renders path is missing or invalid`);
        continue;
      }
      if (!pathIsWithin(join(model.runDir, 'projections'), path)) {
        fail(`${projection.type} trace renders outside projections/`);
        continue;
      }
      const text = readFileSync(path, 'utf8');
      const paragraphs = new Set<string>(
        renderedParagraphs(text).map((paragraph) => paragraph.anchor),
      );
      const anchors = new Set<string>(
        projection.trace.rows.map((row) => row.values.anchor),
      );
      for (const anchor of paragraphs) {
        if (!anchors.has(anchor)) fail(`${projection.type} rendered paragraph ${anchor} has no trace row`);
      }
      for (const anchor of anchors) {
        if (!paragraphs.has(anchor)) fail(`${projection.type} trace anchor ${anchor} does not exist`);
      }
    }
    return 'every rendered paragraph and trace anchor resolve bidirectionally';
  });

  results.run('K6.5', 'new claim', (fail) => {
    for (const projection of byType) {
      for (const row of projection.trace?.rows || []) {
        if (row.values.kind === 'load-bearing' && idsIn(row.values.backing, 'CC').length === 0) {
          fail(`${projection.type} ${row.values.anchor} is load-bearing with no backing`);
        }
      }
    }
    return 'every load-bearing projection statement has claim backing';
  });

  results.run('K6.6', 'boundary honor', (fail) => {
    const prohibited = new Set<string>();
    for (const boundary of model.boundaries) {
      if (boundary.values.type === 'do-not-use-harm' && boundary.values.status === 'active') {
        for (const id of idsIn(boundary.values.governs, 'CC')) prohibited.add(id);
      }
    }
    for (const projection of byType) {
      for (const row of projection.trace?.rows || []) {
        for (const id of idsIn(row.values.backing, 'CC')) {
          if (prohibited.has(id)) {
            fail(`${projection.type} ${row.values.anchor} backs onto do-not-use claim ${id}`);
          }
          if (row.values.kind === 'load-bearing' && active.get(id)?.values.disposition === 'backgrounded') {
            fail(`${projection.type} ${row.values.anchor} uses backgrounded ${id} as support`);
          }
        }
      }
    }
    return 'projection traces honor do-not-use and background-only boundaries';
  });

  results.run('K6.7', 'open voice', (fail) => {
    for (const projection of byType) {
      const selections = new Map<string, ProjectionSelectionRow>(
        (projection.selection?.rows || [])
          .map((row) => [row.values.claimId, row]),
      );
      const openRows = new Map<string, ProjectionSelectionRow>(
        [...selections].filter(([, row]) => row.values.selection === 'surfaced-as-open'),
      );
      const openTraces = projection.trace?.rows.filter((row) => row.values.kind === 'open-item') || [];

      for (const trace of openTraces) {
        for (const id of idsIn(trace.values.backing, 'CC')) {
          const selection = selections.get(id);
          if (!selection || selection.values.selection !== 'surfaced-as-open') {
            fail(`${projection.type} open-item ${trace.values.anchor} backs ${id} without a surfaced-as-open selection`);
            continue;
          }
          const sectionMatch = selection.values.reason.match(/§([^\s,;]+)/);
          const expected = sectionMatch?.[1];
          const actual = trace.values.anchor.match(/^§([^\s]+)\s+¶\d+$/)?.[1];
          if (!expected) {
            fail(`${projection.type} ${id} open handling names no §section`);
          } else if (actual !== expected) {
            fail(`${projection.type} ${id} open-item is in §${actual || '?'}, handling names §${expected}`);
          }
        }
      }

      for (const [id, selection] of openRows) {
        const sectionMatch = selection.values.reason.match(/§([^\s,;]+)/);
        if (!sectionMatch) {
          fail(`${projection.type} ${id} open handling names no §section`);
          continue;
        }
        const traces = openTraces.filter((row) => (
          row.values.kind === 'open-item' && idsIn(row.values.backing, 'CC').includes(id)
        ));
        if (traces.length === 0) fail(`${projection.type} ${id} has no open-item trace row`);
      }
    }
    return 'surfaced-open selections and trace anchors name the same sections';
  });

  results.run('K6.8', 'taint propagation', (fail) => {
    for (const projection of byType) {
      const used = new Set<string>((projection.selection?.rows || [])
        .filter((row) => row.values.selection === 'used')
        .map((row) => row.values.claimId));
      const tainted = [...routing.cards.entries()].some(([id, card]) => (
        card.claims.some((claim) => used.has(claim)) && routing.coneRefs(id).size > 0
      ));
      if (!tainted) continue;
      const path = traceDocumentPath(model, projection);
      if (!path || !existsSync(path)) continue;
      const firstTen = readFileSync(path, 'utf8').split('\n').slice(0, 10).join('\n');
      if (!/external-referent unresolved/i.test(firstTen)) {
        fail(`${projection.type} is tainted but its first 10 lines lack the marker`);
      }
    }
    return 'tainted projections carry a prominent first-ten-line marker';
  });

  results.run('K6.9', 'neutrality both ways', (fail) => {
    for (const projection of byType) {
      const path = traceDocumentPath(model, projection);
      if (!path || !existsSync(path)) continue;
      const text = readFileSync(path, 'utf8');
      if (/\bPKT-\d+\b/.test(text)) fail(`${projection.type} rendered document leaks packet IDs`);
      for (const [index, line] of text.split('\n').entries()) {
        const cells = tableCells(line);
        if (!cells || isSeparatorRow(cells) || cells.length !== 4) continue;
        if (cells.some((cell) => [
          'carried', 'merged', 'deferred', 'excluded-with-reason',
          'backgrounded', 'judged-non-load-bearing', 'unresolved',
        ].includes(cell.toLowerCase()))) {
          fail(`${projection.type} rendered document copies a §4-shaped disposition row at line ${index + 1}`);
        }
      }
    }
    return 'rendered projections leak neither packet IDs nor Précis disposition tables';
  });

  results.run('K6.10', 'type contract', (fail) => {
    for (const projection of byType) {
      const contract = TYPE_CONTRACTS.get(projection.type);
      if (!contract) {
        fail(`${projection.type} has no registered projection-type contract`);
        continue;
      }
      const path = traceDocumentPath(model, projection);
      if (!path || !existsSync(path) || !pathIsWithin(join(model.runDir, 'projections'), path)) {
        fail(`${projection.type} has no readable rendered document under projections/`);
        continue;
      }
      const text = readFileSync(path, 'utf8');
      if (/\{\{[^}]+\}\}|<!--/.test(text)) {
        fail(`${projection.type} rendered document retains a template placeholder or comment`);
      }
      const fields = parseFieldTable(parseTables(text, basename(path))).fields;
      for (const field of contract.fields) {
        if (!fields.get(field)?.trim()) {
          fail(`${projection.type} rendered metadata field "${field}" is empty or missing`);
        }
      }
      if (fields.get('projection type') !== projection.type) {
        fail(
          `${projection.type} rendered metadata declares type `
          + `"${fields.get('projection type') || '(blank)'}"`,
        );
      }
      const commissionFields = projectionFields(projection.commission);
      if (fields.get('projection id') !== commissionFields.get('projection id')) {
        fail(`${projection.type} rendered metadata does not cite its commissioned projection id`);
      }
      if (fields.get('projection trace') !== projection.trace?.relativePath) {
        fail(`${projection.type} rendered metadata does not cite its projection trace path`);
      }
      if (fields.get('commission') !== `projections/commission-${projection.type}.md`) {
        fail(`${projection.type} rendered metadata does not cite its commission path`);
      }
      const sourceHash = fields.get('source precis')?.match(/[a-fA-F0-9]{64}/)?.[0]?.toLowerCase();
      const currentHash = model.precis ? sha256(Buffer.from(model.precis.text, 'utf8')) : null;
      if (!sourceHash || sourceHash !== currentHash) {
        fail(`${projection.type} rendered metadata does not bind the current Précis hash`);
      }

      const sections = text.split('\n')
        .map((line) => line.match(/^##\s+(\d+)\.\s+/)?.[1])
        .filter(Boolean);
      if (sections.join(',') !== contract.sections.join(',')) {
        fail(
          `${projection.type} top-level sections are [${sections.join(', ')}], `
          + `expected [${contract.sections.join(', ')}]`,
        );
      }
    }
    return 'registered projection metadata and required section sets are complete';
  });
}

export function runK3(results: ResultCollector, model: RunModel): void {
  runK3Checks(results, model);
}

export function runK4K5(results: ResultCollector, model: RunModel): void {
  runK4Checks(results, model);
  runK5Checks(results, model);
}

export function runK6(results: ResultCollector, model: RunModel): void {
  runK6Checks(results, model);
}
